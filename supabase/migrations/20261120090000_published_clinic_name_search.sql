-- Search published Clinics by name — Phase 1 (SPEC-DIS-004).
--
-- Additive only. published_clinic_public_profiles, get_published_clinic_location,
-- discover_nearby_clinics, discover_clinics_in_viewport and
-- professional_clinic_search_key keep their definition and grants.
--
--   1. clinic_display_name_search_key(text) — internal. The SPEC-DIS-004 BR-5
--      search normalization N(text), executable by no client. Independent of
--      professional_clinic_search_key: the public contract does not change
--      when the professional one does.
--   2. discover_published_clinics(text, text, uuid, integer) — one keyset
--      page of the published Clinics in alphabetical order, optionally
--      narrowed by display name, for anon and authenticated alike.
--
-- Eligibility is exactly published_clinic_public_profiles' (BR-1): a
-- published Clinic with its public profile. The address follows exactly
-- get_published_clinic_location's rule (BR-4): the published Clinic's current
-- Location, joined optionally so a Clinic without one is still returned
-- (BR-3); clinic_locations is keyed by clinic_id, so no Clinic is repeated.
-- Every row comes from one statement; nothing is read per Clinic. No table,
-- column, index, constraint, extension, or table grant is added or changed,
-- and nothing is written.

begin;

-- ==================================================================
-- 1. Search normalization (SPEC-DIS-004 BR-5). Internal.
-- ==================================================================

-- N(text): NFKD; remove the combining marks U+0300–U+036F; root-locale
-- lowercase through the fixed ICU collation "und-x-icu", so the result never
-- depends on the database default collation or the input's collation; every
-- run of Unicode White_Space (U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680,
-- U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000) becomes one space;
-- leading and trailing spaces removed. `null` stays `null`.
--
-- Derived at read time only: no index or stored value depends on it.
create function public.clinic_display_name_search_key(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
    select pg_catalog.btrim(
        pg_catalog.regexp_replace(
            pg_catalog.lower(
                pg_catalog.regexp_replace(
                    pg_catalog.normalize(p_value, 'NFKD'),
                    '[\u0300-\u036f]', '', 'g'
                ) collate pg_catalog."und-x-icu"
            ),
            '[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+', ' ', 'g'
        ),
        ' '
    )
$$;

revoke all privileges
on function public.clinic_display_name_search_key(text)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 2. Published Clinics page (SPEC-DIS-004 §4, BR-1–BR-9).
--
-- Order (BR-6): display name in the database default collation, unnamed
-- last, then clinic_id. The cursor comparison uses exactly that key. One
-- probe row beyond p_limit decides has_more and is never returned or used as
-- the next cursor.
--
-- The caller's identity is never consulted (BR-2). STABLE: one snapshot per
-- call (BR-8).
-- ==================================================================

create function public.discover_published_clinics(
    p_search text default null,
    p_after_display_name text default null,
    p_after_clinic_id uuid default null,
    p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    search_key text;
    page_rows jsonb;
    has_more boolean;
    last_row jsonb;
begin
    -- Input validation, depending on no stored data.
    if p_limit is null or p_limit not between 1 and 50
       or (p_after_display_name is not null and p_after_clinic_id is null)
       or char_length(p_search) > 100 then
        raise exception 'Published Clinics page is invalid'
            using errcode = '22023';
    end if;

    search_key := nullif(public.clinic_display_name_search_key(p_search), '');

    select coalesce(jsonb_agg(jsonb_build_object(
               'clinic_id', page.clinic_id,
               'display_name', page.display_name,
               'description', page.description,
               'address_text', page.address_text
           ) order by page.display_name nulls last, page.clinic_id), '[]'::jsonb)
    into page_rows
    from (
        select
            clinic.id as clinic_id,
            profile.display_name,
            profile.description,
            location.address_text
        from public.clinics as clinic
        join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        left join public.clinic_locations as location
          on location.clinic_id = clinic.id
        where clinic.is_published = true
          -- BR-5: literal substring of the normalized display name.
          and (
              search_key is null
              or (
                  profile.display_name is not null
                  and pg_catalog.strpos(
                      public.clinic_display_name_search_key(profile.display_name),
                      search_key
                  ) > 0
              )
          )
          -- BR-7: strictly after the cursor, in exactly the order below.
          and (
              p_after_clinic_id is null
              or case
                  when p_after_display_name is null then
                      profile.display_name is null
                      and clinic.id > p_after_clinic_id
                  else
                      profile.display_name is null
                      or profile.display_name > p_after_display_name
                      or (
                          profile.display_name = p_after_display_name
                          and clinic.id > p_after_clinic_id
                      )
              end
          )
        order by
            profile.display_name nulls last,
            clinic.id
        limit p_limit + 1
    ) as page;

    has_more := pg_catalog.jsonb_array_length(page_rows) > p_limit;
    if has_more then
        -- Drop the probe row (zero-based index p_limit).
        page_rows := page_rows - p_limit;
    end if;
    last_row := page_rows -> -1;

    return pg_catalog.jsonb_build_object(
        'clinics', page_rows,
        'has_more', has_more,
        'next_after_display_name', last_row -> 'display_name',
        'next_after_clinic_id', last_row -> 'clinic_id'
    );
end;
$$;

-- As for the other Discovery reads: anon and authenticated (and the
-- platform's service_role); never PUBLIC.
revoke all privileges
on function public.discover_published_clinics(text, text, uuid, integer)
from public, anon, authenticated;

grant execute
on function public.discover_published_clinics(text, text, uuid, integer)
to anon, authenticated;

commit;

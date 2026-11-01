-- Organization Clinics list with search and pagination — Phase 1
-- (SPEC-ORG-008 §11, BR-19–BR-26; Punto 10).
--
-- Additive only. get_my_professional_clinics() and every other function keep
-- their signature, body and grants.
--
--   1. professional_clinic_search_key(text) — internal. The BR-22 search
--      normalization N(text), executable by no client.
--   2. get_my_organization_professional_clinics(uuid, text, text, uuid,
--      integer) — one keyset page of the acting User's Professional Clinics
--      of one Organization, optionally narrowed by display name.
--
-- Inclusion is decided only by the authoritative predicate
-- user_has_clinic_capability over the Clinic-context catalog, exactly as in
-- get_my_professional_clinics() (BR-21); no responsibility-to-capability
-- mapping is restated here. The search and the cursor are applied before the
-- page is cut, and every row of the page has passed the predicate. No table,
-- column, index, constraint, extension, or table grant is added or changed,
-- and nothing is written.

begin;

-- ==================================================================
-- 1. Search normalization (SPEC-ORG-008 BR-22). Internal.
-- ==================================================================

-- N(text): NFKD; remove the combining marks U+0300–U+036F; root-locale
-- lowercase through the fixed ICU collation "und-x-icu", so the result never
-- depends on the database default collation or the input's collation; every
-- run of Unicode White_Space (U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680,
-- U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000) becomes one space;
-- leading and trailing spaces removed. `null` stays `null`.
--
-- Derived at read time only: no index or stored value depends on it.
create function public.professional_clinic_search_key(p_value text)
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
on function public.professional_clinic_search_key(text)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 2. Organization Professional Clinics page (SPEC-ORG-008 BR-19–BR-25).
--
-- Rows: (clinic_id, clinic_display_name) only. Order (BR-23): display name
-- in the database default collation — the same as get_my_professional_clinics
-- — unnamed Clinics last, then clinic_id. The cursor comparison uses exactly
-- that key. An unknown, null or inaccessible Organization yields an empty
-- page, indistinguishable from an Organization with no Clinic (BR-21).
--
-- Candidate bound (BR-21). user_has_clinic_capability is exactly the
-- disjunction of user_has_organization_scoped_clinic_capability (for the
-- Clinic's Organization) and user_has_clinic_scoped_clinic_capability. Every
-- branch requires a current Membership of the acting User in the Clinic's
-- Organization, and the Clinic-scoped branch additionally requires a current
-- Clinic-scoped Responsibility Grant for that Clinic or a current Veterinarian
-- Clinic Assignment to it. So a Clinic can only be included when
--   * the Organization-scoped predicate grants some Clinic-context capability
--     in the Organization (evaluated once), or
--   * the Clinic is named by such a Grant or Assignment of the acting User.
-- The bound only skips Clinics that cannot be included; it never decides
-- inclusion. Candidates are filtered by search and cursor, ordered, and then
-- tested one by one with user_has_clinic_capability until the page is full.
--
-- STABLE: every statement of the call uses the calling statement's snapshot
-- and one statement_timestamp() (BR-24).
-- ==================================================================

create function public.get_my_organization_professional_clinics(
    p_organization_id uuid,
    p_search text default null,
    p_after_display_name text default null,
    p_after_clinic_id uuid default null,
    p_limit integer default 20
)
returns table (
    clinic_id uuid,
    clinic_display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    search_key text;
    organization_wide boolean;
    candidate record;
    returned_count integer := 0;
begin
    -- BR-20 step 1: authentication, before any input is considered.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- BR-20 step 2: input validation, independent of the Organization.
    if p_limit is null or p_limit not between 1 and 50
       or (p_after_display_name is not null and p_after_clinic_id is null)
       or char_length(p_search) > 100 then
        raise exception 'Professional Clinics page is invalid'
            using errcode = '22023';
    end if;

    -- Without a current Membership in the Organization no branch can hold.
    if not exists (
        select 1
        from public.organization_memberships as membership
        where membership.organization_id = p_organization_id
          and membership.user_id = acting_user_id
          and membership.effective_end is null
    ) then
        return;
    end if;

    search_key := nullif(public.professional_clinic_search_key(p_search), '');

    organization_wide := exists (
        select 1
        from public.professional_capability_catalog() as catalog_entry
        where catalog_entry.capability_context = 'CLINIC'
          and public.user_has_organization_scoped_clinic_capability(
              acting_user_id, p_organization_id, catalog_entry.capability
          )
    );

    for candidate in
        select
            clinic.id as candidate_clinic_id,
            profile.display_name as candidate_display_name
        from public.clinics as clinic
        left join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        where clinic.organization_id = p_organization_id
          and (
              organization_wide
              or clinic.id in (
                  select grant_record.clinic_id
                  from public.organization_responsibility_grants as grant_record
                  join public.organization_memberships as membership
                    on membership.id = grant_record.membership_id
                  where membership.organization_id = p_organization_id
                    and membership.user_id = acting_user_id
                    and membership.effective_end is null
                    and grant_record.effective_end is null
                    and grant_record.scope_type = 'CLINIC'
                  union
                  select assignment.clinic_id
                  from public.veterinarian_clinic_assignments as assignment
                  join public.organization_memberships as membership
                    on membership.id = assignment.supporting_membership_id
                  where membership.organization_id = p_organization_id
                    and membership.user_id = acting_user_id
                    and membership.effective_end is null
                    and assignment.effective_end is null
              )
          )
          -- BR-22: literal substring of the normalized display name.
          and (
              search_key is null
              or (
                  profile.display_name is not null
                  and pg_catalog.strpos(
                      public.professional_clinic_search_key(profile.display_name),
                      search_key
                  ) > 0
              )
          )
          -- BR-23: strictly after the cursor, in exactly the order below.
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
    loop
        -- BR-21: inclusion by the authoritative predicate only. The
        -- capabilities are tried in identifier order and the test stops at the
        -- first one granted; the order affects cost, never the outcome.
        if exists (
            select 1
            from (
                select catalog_entry.capability
                from public.professional_capability_catalog() as catalog_entry
                where catalog_entry.capability_context = 'CLINIC'
                order by catalog_entry.capability collate "C"
                offset 0
            ) as clinic_capability
            where public.user_has_clinic_capability(
                acting_user_id, candidate.candidate_clinic_id, clinic_capability.capability
            )
        ) then
            clinic_id := candidate.candidate_clinic_id;
            clinic_display_name := candidate.candidate_display_name;
            return next;
            returned_count := returned_count + 1;
            exit when returned_count = p_limit;
        end if;
    end loop;
end;
$$;

revoke all privileges
on function public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)
from public, anon, authenticated, service_role;

grant execute
on function public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)
to authenticated;

commit;

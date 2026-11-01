begin;

-- Slice 15 — Discovery query support.
--
-- Additive only: no table, view, index, or extension is introduced. This
-- migration adds three narrow, bounded, SECURITY DEFINER read functions over
-- the existing public.clinics / public.clinic_locations /
-- public.clinic_public_profiles structures established in Slice 4, mirroring
-- the trusted-boundary pattern already used by
-- public.get_published_clinic_service_offerings and
-- public.get_published_clinic_opening_hours (Slice 6). Base-table RLS and
-- grants from prior Slices are unchanged.
--
-- See SPEC-DIS-001, SPEC-DIS-002, SPEC-DIS-003, REQ-DIS-002/003/004,
-- REQ-NFR-006, RELATIONAL_MODEL.md §11 item 15.

-- 1. Published Clinic location — single-row point lookup (REQ-DIS-004).
--
-- Mirrors get_published_clinic_service_offerings: a nonexistent and an
-- unpublished Clinic both return zero rows, with no distinguishing error, so
-- Discovery cannot be used to probe for the existence of an unpublished
-- Clinic. The base clinic_locations table remains directly inaccessible to
-- anon/authenticated; this function is the only path to its content.

create function public.get_published_clinic_location(
    p_clinic_id uuid
)
returns table (
    clinic_id uuid,
    address_text text,
    latitude double precision,
    longitude double precision
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        clinic.id as clinic_id,
        location.address_text,
        location.latitude,
        location.longitude
    from public.clinics as clinic
    join public.clinic_locations as location
      on location.clinic_id = clinic.id
    where clinic.id = p_clinic_id
      and clinic.is_published = true
$$;

revoke all privileges
on function public.get_published_clinic_location(uuid)
from public, anon, authenticated;

grant execute
on function public.get_published_clinic_location(uuid)
to anon, authenticated;

-- 2. Nearby Clinic Discovery (SPEC-DIS-002).
--
-- p_radius_meters is a required caller input; no product-specific default
-- radius is invented here (SPEC-DIS-002 §5 leaves the exact default/limit to
-- product/architectural configuration, not this Specification).
--
-- MAX_GREAT_CIRCLE_DISTANCE_METERS (pi * mean Earth radius) is a purely
-- mathematical/model bound: it is the greatest possible great-circle
-- distance between two terrestrial points under the sphere model used by
-- the Haversine calculation below. A radius at or beyond that value could
-- not exclude any point on Earth and would therefore silently degenerate
-- into exactly the unbounded query SPEC-DIS-002 BR-5 forbids. It is not a
-- product search-radius tier.
--
-- Ordering is distance_meters asc, clinic_id asc (SPEC-DIS-002 BR-8; no
-- business-significant secondary order for equal distances is defined, so
-- clinic_id is used purely as a deterministic tie-breaker). The forward
-- keyset predicate therefore advances with strictly-greater-than:
--   (distance_meters, clinic_id) > (p_after_distance_meters, p_after_clinic_id)
--
-- distance_meters is computed exactly once per candidate row (the
-- "distance" CTE) and that same value is reused for radius filtering, the
-- cursor comparison, the ORDER BY, and the returned JSON — never recomputed
-- differently at any of those points.
--
-- That single computed value is rounded to millimeter precision (round to 3
-- decimal places) at the point of computation, before it is used for
-- anything. This is a deliberately introduced, load-bearing step: this
-- platform's Postgres reports extra_float_digits = 0, which prints/parses
-- double precision values with 15 significant decimal digits rather than
-- the 17 required to guarantee an exact binary round trip. Since every real
-- caller necessarily receives the cursor through a JSON response and sends
-- it back as JSON, an unrounded distance can silently lose its last bit or
-- two of precision on that round trip; for a distance whose row is exactly
-- the previous page's cursor, that loss makes the freshly recomputed
-- distance compare as strictly greater than the (very slightly smaller,
-- reparsed) cursor, and the boundary row reappears duplicated on the next
-- page. Millimeter precision carries at most ~11 significant decimal
-- digits for any distance on Earth, comfortably inside the 15-digit
-- guarantee, so the rounded value now round-trips through JSON exactly and
-- keyset pagination cannot skip or duplicate a boundary row. Millimeter
-- precision has no product-visible effect on "nearby" distance.
--
-- Latitude/longitude/radius/cursor-distance validation relies on ordinary
-- comparison operators rather than isfinite(double precision): PostgreSQL
-- defines NaN as comparing greater than every other double precision value
-- (and Infinity/-Infinity compare as ordinary extreme values), so a
-- two-sided bound such as "between -90 and 90" or "> 0 and < max" already
-- rejects NaN and both infinities without depending on an isfinite(float8)
-- overload.

create function public.discover_nearby_clinics(
    p_latitude double precision,
    p_longitude double precision,
    p_radius_meters double precision,
    p_limit integer default 50,
    p_after_distance_meters double precision default null,
    p_after_clinic_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    earth_radius_meters constant double precision := 6371000.0;
    max_radius_meters constant double precision := pi() * 6371000.0;
    bounded_limit integer;
    result_payload jsonb;
begin
    if p_latitude is null or p_latitude not between -90.0 and 90.0 then
        raise exception 'Nearby Discovery reference latitude must be between -90 and 90'
            using errcode = '22023';
    end if;

    if p_longitude is null or p_longitude not between -180.0 and 180.0 then
        raise exception 'Nearby Discovery reference longitude must be between -180 and 180'
            using errcode = '22023';
    end if;

    if p_radius_meters is null
       or p_radius_meters <= 0
       or p_radius_meters >= max_radius_meters then
        raise exception 'Nearby Discovery radius must be a positive distance below the maximum great-circle distance'
            using errcode = '22023';
    end if;

    if p_limit is null or p_limit < 1 then
        raise exception 'Page limit must be positive'
            using errcode = '22023';
    end if;
    bounded_limit := least(p_limit, 100);

    if (p_after_distance_meters is null) <> (p_after_clinic_id is null) then
        raise exception 'Nearby Discovery cursor components must be supplied together'
            using errcode = '22023';
    end if;

    if p_after_distance_meters is not null
       and (
           p_after_distance_meters < 0
           or p_after_distance_meters >= max_radius_meters
       ) then
        raise exception 'Nearby Discovery cursor distance is invalid'
            using errcode = '22023';
    end if;

    with candidate as materialized (
        select
            clinic.id as clinic_id,
            profile.display_name,
            profile.description,
            profile.public_phone,
            profile.public_email,
            profile.website,
            location.address_text,
            location.latitude,
            location.longitude,
            least(
                greatest(
                    power(sin(radians(location.latitude - p_latitude) / 2.0), 2)
                    + cos(radians(p_latitude)) * cos(radians(location.latitude))
                      * power(sin(radians(location.longitude - p_longitude) / 2.0), 2),
                    0.0::double precision
                ),
                1.0::double precision
            ) as haversine_a
        from public.clinics as clinic
        join public.clinic_locations as location
          on location.clinic_id = clinic.id
        join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        where clinic.is_published = true
    ),
    distance as materialized (
        select
            candidate.*,
            round(
                (
                    2.0 * earth_radius_meters
                    * atan2(
                        sqrt(candidate.haversine_a),
                        sqrt(1.0 - candidate.haversine_a)
                    )
                )::numeric,
                3
            )::double precision as distance_meters
        from candidate
    ),
    page_rows as materialized (
        select
            distance.*,
            row_number() over (
                order by distance.distance_meters asc, distance.clinic_id asc
            ) as page_number
        from distance
        where distance.distance_meters <= p_radius_meters
          and (
              p_after_clinic_id is null
              or (distance.distance_meters, distance.clinic_id)
                 > (p_after_distance_meters, p_after_clinic_id)
          )
        order by distance.distance_meters asc, distance.clinic_id asc
        limit bounded_limit + 1
    ),
    visible_rows as materialized (
        select * from page_rows where page_number <= bounded_limit
    )
    select jsonb_build_object(
        'clinics', coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'clinic_id', visible_rows.clinic_id,
                        'display_name', visible_rows.display_name,
                        'description', visible_rows.description,
                        'public_phone', visible_rows.public_phone,
                        'public_email', visible_rows.public_email,
                        'website', visible_rows.website,
                        'address_text', visible_rows.address_text,
                        'latitude', visible_rows.latitude,
                        'longitude', visible_rows.longitude,
                        'distance_meters', visible_rows.distance_meters
                    )
                    order by
                        visible_rows.distance_meters asc,
                        visible_rows.clinic_id asc
                )
                from visible_rows
            ),
            '[]'::jsonb
        ),
        'has_more', exists (
            select 1 from page_rows where page_number > bounded_limit
        ),
        'next_after_distance_meters', (
            select visible_rows.distance_meters
            from visible_rows
            order by
                visible_rows.distance_meters desc,
                visible_rows.clinic_id desc
            limit 1
        ),
        'next_after_clinic_id', (
            select visible_rows.clinic_id
            from visible_rows
            order by
                visible_rows.distance_meters desc,
                visible_rows.clinic_id desc
            limit 1
        )
    )
    into result_payload;

    return result_payload;
end;
$$;

revoke all privileges
on function public.discover_nearby_clinics(
    double precision, double precision, double precision, integer,
    double precision, uuid
)
from public, anon, authenticated;

grant execute
on function public.discover_nearby_clinics(
    double precision, double precision, double precision, integer,
    double precision, uuid
)
to anon, authenticated;

-- 3. Map/viewport Clinic Discovery (SPEC-DIS-003).
--
-- Bounds are inclusive on every side (SPEC-DIS-003 does not distinguish
-- boundary inclusion, and Nearby's own boundary-inclusive rule, RELATIONAL_
-- MODEL.md §5.9, is applied consistently here).
--
-- Ordering is clinic_id asc — SPEC-DIS-003 does not mandate distance
-- ordering for viewport results — with a keyset predicate
-- clinic_id > p_after_clinic_id so that a viewport containing more than
-- bounded_limit published Clinics is paginated rather than silently
-- truncated (CONVENTIONS.md §20; SPEC-DIS-003 §8 leaves the exact result-
-- limit/pagination strategy to architecture, not to silent data loss).
--
-- Phase 1 intentionally does not support an antimeridian-crossing viewport
-- (min_longitude > max_longitude): SPEC-DIS-003 is silent on antimeridian
-- behavior, and implementing longitude wrap-around would be invented
-- global-map behavior rather than an approved contract. A crossing request
-- is rejected as a documented Phase 1 API limitation; the client is
-- expected to issue two non-crossing viewport queries instead.

create function public.discover_clinics_in_viewport(
    p_min_latitude double precision,
    p_max_latitude double precision,
    p_min_longitude double precision,
    p_max_longitude double precision,
    p_limit integer default 100,
    p_after_clinic_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    bounded_limit integer;
    result_payload jsonb;
begin
    if p_min_latitude is null or p_min_latitude not between -90.0 and 90.0 then
        raise exception 'Viewport minimum latitude must be between -90 and 90'
            using errcode = '22023';
    end if;

    if p_max_latitude is null or p_max_latitude not between -90.0 and 90.0 then
        raise exception 'Viewport maximum latitude must be between -90 and 90'
            using errcode = '22023';
    end if;

    if p_min_latitude > p_max_latitude then
        raise exception 'Viewport minimum latitude must not exceed maximum latitude'
            using errcode = '22023';
    end if;

    if p_min_longitude is null or p_min_longitude not between -180.0 and 180.0 then
        raise exception 'Viewport minimum longitude must be between -180 and 180'
            using errcode = '22023';
    end if;

    if p_max_longitude is null or p_max_longitude not between -180.0 and 180.0 then
        raise exception 'Viewport maximum longitude must be between -180 and 180'
            using errcode = '22023';
    end if;

    if p_min_longitude > p_max_longitude then
        raise exception 'Antimeridian-crossing viewports (min_longitude greater than max_longitude) are not supported in Phase 1'
            using errcode = '22023';
    end if;

    if p_limit is null or p_limit < 1 then
        raise exception 'Page limit must be positive'
            using errcode = '22023';
    end if;
    bounded_limit := least(p_limit, 100);

    with candidate as materialized (
        select
            clinic.id as clinic_id,
            profile.display_name,
            profile.description,
            profile.public_phone,
            profile.public_email,
            profile.website,
            location.address_text,
            location.latitude,
            location.longitude
        from public.clinics as clinic
        join public.clinic_locations as location
          on location.clinic_id = clinic.id
        join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        where clinic.is_published = true
          and location.latitude between p_min_latitude and p_max_latitude
          and location.longitude between p_min_longitude and p_max_longitude
    ),
    page_rows as materialized (
        select
            candidate.*,
            row_number() over (
                order by candidate.clinic_id asc
            ) as page_number
        from candidate
        where p_after_clinic_id is null
           or candidate.clinic_id > p_after_clinic_id
        order by candidate.clinic_id asc
        limit bounded_limit + 1
    ),
    visible_rows as materialized (
        select * from page_rows where page_number <= bounded_limit
    )
    select jsonb_build_object(
        'clinics', coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'clinic_id', visible_rows.clinic_id,
                        'display_name', visible_rows.display_name,
                        'description', visible_rows.description,
                        'public_phone', visible_rows.public_phone,
                        'public_email', visible_rows.public_email,
                        'website', visible_rows.website,
                        'address_text', visible_rows.address_text,
                        'latitude', visible_rows.latitude,
                        'longitude', visible_rows.longitude
                    )
                    order by visible_rows.clinic_id asc
                )
                from visible_rows
            ),
            '[]'::jsonb
        ),
        'has_more', exists (
            select 1 from page_rows where page_number > bounded_limit
        ),
        'next_after_clinic_id', (
            select visible_rows.clinic_id
            from visible_rows
            order by visible_rows.clinic_id desc
            limit 1
        )
    )
    into result_payload;

    return result_payload;
end;
$$;

revoke all privileges
on function public.discover_clinics_in_viewport(
    double precision, double precision, double precision, double precision,
    integer, uuid
)
from public, anon, authenticated;

grant execute
on function public.discover_clinics_in_viewport(
    double precision, double precision, double precision, double precision,
    integer, uuid
)
to anon, authenticated;

commit;

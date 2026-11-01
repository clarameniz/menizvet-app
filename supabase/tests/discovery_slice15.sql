-- Run only against an isolated database with all source-controlled
-- migrations applied, through the Slice 15 migration. Synthetic fixtures and
-- assertions are rolled back; superuser test execution is required solely to
-- bypass unrelated establishment triggers while loading deliberately minimal
-- deterministic context, and to demonstrate genuine anon/authenticated
-- callable parity via SET LOCAL ROLE.
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_sqlstate(p_statement text, p_expected text)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected then return; end if;
        raise exception 'Expected SQLSTATE %, received %: %', p_expected, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected;
end;
$$;

-- Extraction helpers over the jsonb envelope — tests read the actual
-- returned payload rather than hand-computing distances or fabricating
-- cursors.
create function pg_temp.discovery_payload_has_clinic(p_payload jsonb, p_clinic_id uuid)
returns boolean language sql as $$
    select exists (
        select 1
        from jsonb_array_elements(p_payload -> 'clinics') as c
        where (c ->> 'clinic_id')::uuid = p_clinic_id
    )
$$;

create function pg_temp.discovery_payload_clinic_distance(p_payload jsonb, p_clinic_id uuid)
returns double precision language sql as $$
    select (c ->> 'distance_meters')::double precision
    from jsonb_array_elements(p_payload -> 'clinics') as c
    where (c ->> 'clinic_id')::uuid = p_clinic_id
$$;

-- Preserves the envelope's own array order (via with-ordinality) rather
-- than relying on any incidental re-sort.
create function pg_temp.discovery_payload_clinic_ids(p_payload jsonb)
returns uuid[] language sql as $$
    select array_agg((elem ->> 'clinic_id')::uuid order by ord)
    from jsonb_array_elements(p_payload -> 'clinics') with ordinality as t(elem, ord)
$$;

-- ===========================================================================
-- Fixtures. Discovery is anonymous by domain design (SPEC-DIS-001 BR-15), so
-- no auth.users / public.users / Guardianship context is required at all —
-- only an Organization and Clinics with varying publication/location state.
-- ===========================================================================

set local session_replication_role = replica;

insert into public.veterinary_organizations (id, display_name)
values ('15000000-0000-4000-8000-000000000001', 'Slice 15 Discovery Test Organization');

-- Cluster 1 — Nearby reference point (40.0, 0.0): identical-point,
-- unpublished-exclusion, no-location-exclusion, and antipodal safety.
insert into public.clinics (id, organization_id, is_published) values
    ('15000000-0000-4000-8000-000000000011', '15000000-0000-4000-8000-000000000001', true),   -- A: at the reference point
    ('15000000-0000-4000-8000-000000000012', '15000000-0000-4000-8000-000000000001', true),   -- B: ~85km east
    ('15000000-0000-4000-8000-000000000013', '15000000-0000-4000-8000-000000000001', false),  -- C: unpublished, closer than B
    ('15000000-0000-4000-8000-000000000014', '15000000-0000-4000-8000-000000000001', true),   -- D: published, no Location
    ('15000000-0000-4000-8000-000000000015', '15000000-0000-4000-8000-000000000001', true);   -- E: near-antipodal to A

insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    ('15000000-0000-4000-8000-000000000011', 'Cluster 1 Site A', 40.0, 0.0),
    ('15000000-0000-4000-8000-000000000012', 'Cluster 1 Site B', 40.0, 1.0),
    ('15000000-0000-4000-8000-000000000013', 'Cluster 1 Site C', 40.0, 0.5),
    ('15000000-0000-4000-8000-000000000015', 'Cluster 1 Site E', -38.0, 178.0);

insert into public.clinic_public_profiles (clinic_id, display_name) values
    ('15000000-0000-4000-8000-000000000011', 'Discovery Clinic A'),
    ('15000000-0000-4000-8000-000000000012', 'Discovery Clinic B'),
    ('15000000-0000-4000-8000-000000000013', 'Discovery Clinic C (unpublished)'),
    ('15000000-0000-4000-8000-000000000014', 'Discovery Clinic D (no location)'),
    ('15000000-0000-4000-8000-000000000015', 'Discovery Clinic E (near-antipodal)');

-- Cluster 2 — Nearby reference point (0.0, 0.0): deterministic equal-distance
-- tie ordering and keyset pagination round-trip. T1/T2 are symmetric around
-- the reference longitude and therefore equidistant; T1's id sorts below
-- T2's id.
insert into public.clinics (id, organization_id, is_published) values
    ('15000000-0000-4000-8000-000000000031', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000032', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000033', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000034', '15000000-0000-4000-8000-000000000001', true);

insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    ('15000000-0000-4000-8000-000000000031', 'Tie Cluster T1', 0.0, -1.0),
    ('15000000-0000-4000-8000-000000000032', 'Tie Cluster T2', 0.0, 1.0),
    ('15000000-0000-4000-8000-000000000033', 'Tie Cluster T3', 0.0, 2.0),
    ('15000000-0000-4000-8000-000000000034', 'Tie Cluster T4', 0.0, 3.0);

insert into public.clinic_public_profiles (clinic_id, display_name) values
    ('15000000-0000-4000-8000-000000000031', 'Tie Clinic T1'),
    ('15000000-0000-4000-8000-000000000032', 'Tie Clinic T2'),
    ('15000000-0000-4000-8000-000000000033', 'Tie Clinic T3'),
    ('15000000-0000-4000-8000-000000000034', 'Tie Clinic T4');

-- Cluster 3 — Viewport [9.9, 10.4] x [9.9, 10.4]: inside/outside/edge
-- behavior and viewport keyset pagination. V1 sits exactly on the min
-- corner, V4 exactly on the max corner (inclusive-bounds check). VU is
-- inside the box but unpublished. V5 is outside the box.
insert into public.clinics (id, organization_id, is_published) values
    ('15000000-0000-4000-8000-000000000041', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000042', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000043', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000044', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000045', '15000000-0000-4000-8000-000000000001', true),
    ('15000000-0000-4000-8000-000000000046', '15000000-0000-4000-8000-000000000001', false);

insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    ('15000000-0000-4000-8000-000000000041', 'Viewport Site V1', 9.9, 9.9),
    ('15000000-0000-4000-8000-000000000042', 'Viewport Site V2', 10.0, 10.0),
    ('15000000-0000-4000-8000-000000000043', 'Viewport Site V3', 10.2, 10.2),
    ('15000000-0000-4000-8000-000000000044', 'Viewport Site V4', 10.4, 10.4),
    ('15000000-0000-4000-8000-000000000045', 'Viewport Site V5 (outside)', 20.0, 20.0),
    ('15000000-0000-4000-8000-000000000046', 'Viewport Site VU (unpublished)', 10.05, 10.05);

insert into public.clinic_public_profiles (clinic_id, display_name) values
    ('15000000-0000-4000-8000-000000000041', 'Viewport Clinic V1'),
    ('15000000-0000-4000-8000-000000000042', 'Viewport Clinic V2'),
    ('15000000-0000-4000-8000-000000000043', 'Viewport Clinic V3'),
    ('15000000-0000-4000-8000-000000000044', 'Viewport Clinic V4'),
    ('15000000-0000-4000-8000-000000000045', 'Viewport Clinic V5'),
    ('15000000-0000-4000-8000-000000000046', 'Viewport Clinic VU');

set local session_replication_role = origin;

-- ===========================================================================
-- get_published_clinic_location — published vs unpublished vs nonexistent
-- vs published-without-location.
-- ===========================================================================
do $$
declare
    row_count integer;
begin
    select count(*) into row_count
    from public.get_published_clinic_location('15000000-0000-4000-8000-000000000011');
    perform pg_temp.assert_true(row_count = 1, 'Published Clinic A with a Location returns exactly one row');

    perform pg_temp.assert_true(
        (
            select location.latitude = 40.0 and location.longitude = 0.0
                and location.address_text = 'Cluster 1 Site A'
            from public.get_published_clinic_location('15000000-0000-4000-8000-000000000011') as location
        ),
        'Published Clinic A location fields match the authoritative Location row'
    );

    select count(*) into row_count
    from public.get_published_clinic_location('15000000-0000-4000-8000-000000000013');
    perform pg_temp.assert_true(row_count = 0, 'Unpublished Clinic C returns zero rows');

    select count(*) into row_count
    from public.get_published_clinic_location('15000000-0000-4000-8000-000000000014');
    perform pg_temp.assert_true(row_count = 0, 'Published Clinic D without a Location returns zero rows');

    select count(*) into row_count
    from public.get_published_clinic_location('15000000-0000-4000-8000-000000000999');
    perform pg_temp.assert_true(row_count = 0, 'Nonexistent Clinic id returns zero rows');

    -- No existence-disclosure distinction: unpublished, no-location, and
    -- nonexistent all produce the identical empty shape.
    perform pg_temp.assert_true(
        (select count(*) from public.get_published_clinic_location('15000000-0000-4000-8000-000000000013'))
        = (select count(*) from public.get_published_clinic_location('15000000-0000-4000-8000-000000000999')),
        'Unpublished and nonexistent Clinics are indistinguishable through this function'
    );
end;
$$;

-- ===========================================================================
-- anon / authenticated parity — genuine role-switched calls, not only
-- static grant checks. Superuser test session can assume any role.
-- ===========================================================================
create table pg_temp.discovery_probe (label text primary key, payload jsonb);

-- The role-switched blocks below write into this stash table while
-- current_user is anon/authenticated; grant them table-level access
-- explicitly rather than relying on default privileges (Postgres does not
-- grant table privileges to PUBLIC by default, unlike EXECUTE on
-- functions). This grant is local to the rolled-back test transaction.
-- "GRANT ... ON SCHEMA pg_temp" fails because pg_temp is a resolution-time
-- alias, not a literal registered schema name (unlike table/function
-- qualification, where it is understood by the parser). The temp schema
-- itself already grants USAGE to PUBLIC on creation, so only the concrete
-- table privilege needs to be granted here.
grant select, insert on pg_temp.discovery_probe to anon, authenticated;

insert into pg_temp.discovery_probe (label, payload)
select 'location_default', to_jsonb(location)
from public.get_published_clinic_location('15000000-0000-4000-8000-000000000011') as location;

set local role anon;
do $$
begin
    insert into pg_temp.discovery_probe (label, payload)
    select 'location_anon', to_jsonb(location)
    from public.get_published_clinic_location('15000000-0000-4000-8000-000000000011') as location;

    insert into pg_temp.discovery_probe (label, payload)
    values (
        'nearby_anon',
        public.discover_nearby_clinics(40.0, 0.0, 200000.0, 50)
    );
end;
$$;
reset role;

set local role authenticated;
do $$
begin
    insert into pg_temp.discovery_probe (label, payload)
    select 'location_authenticated', to_jsonb(location)
    from public.get_published_clinic_location('15000000-0000-4000-8000-000000000011') as location;

    insert into pg_temp.discovery_probe (label, payload)
    values (
        'nearby_authenticated',
        public.discover_nearby_clinics(40.0, 0.0, 200000.0, 50)
    );
end;
$$;
reset role;

do $$
declare
    baseline jsonb;
    as_anon jsonb;
    as_authenticated jsonb;
begin
    select payload into baseline from pg_temp.discovery_probe where label = 'location_default';
    select payload into as_anon from pg_temp.discovery_probe where label = 'location_anon';
    select payload into as_authenticated from pg_temp.discovery_probe where label = 'location_authenticated';
    perform pg_temp.assert_true(
        baseline = as_anon and baseline = as_authenticated,
        'get_published_clinic_location returns identical content regardless of caller role'
    );

    select payload into as_anon from pg_temp.discovery_probe where label = 'nearby_anon';
    select payload into as_authenticated from pg_temp.discovery_probe where label = 'nearby_authenticated';
    perform pg_temp.assert_true(
        as_anon = as_authenticated,
        'discover_nearby_clinics returns identical content for anon and authenticated callers'
    );
end;
$$;

-- ===========================================================================
-- Nearby Discovery — published/unpublished, no-location exclusion,
-- identical-point safety, boundary inclusion, outside-radius exclusion.
-- Radius boundary values are extracted from actual payloads, never
-- hand-computed.
-- ===========================================================================
do $$
declare
    modest jsonb;
    distance_b double precision;
begin
    modest := public.discover_nearby_clinics(40.0, 0.0, 200000.0, 50);

    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(modest, '15000000-0000-4000-8000-000000000011'),
        'Nearby Discovery includes published Clinic A (the reference point itself)'
    );
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(modest, '15000000-0000-4000-8000-000000000012'),
        'Nearby Discovery includes published Clinic B within the radius'
    );
    perform pg_temp.assert_true(
        not pg_temp.discovery_payload_has_clinic(modest, '15000000-0000-4000-8000-000000000013'),
        'Nearby Discovery excludes unpublished Clinic C even though it is closer than B'
    );
    perform pg_temp.assert_true(
        not pg_temp.discovery_payload_has_clinic(modest, '15000000-0000-4000-8000-000000000014'),
        'Nearby Discovery excludes published Clinic D, which has no Location'
    );
    perform pg_temp.assert_true(
        (modest ->> 'has_more') = 'false',
        'The modest-radius Cluster 1 page is complete'
    );

    -- Identical-point numerical safety: distance from (40,0) to (40,0) is 0.
    perform pg_temp.assert_true(
        abs(pg_temp.discovery_payload_clinic_distance(modest, '15000000-0000-4000-8000-000000000011')) < 1e-6,
        'Distance from the reference point to a Clinic at that same point is (numerically) zero'
    );

    -- Boundary inclusion / outside-radius exclusion using B's own reported
    -- distance rather than a hand-computed value.
    distance_b := pg_temp.discovery_payload_clinic_distance(modest, '15000000-0000-4000-8000-000000000012');
    perform pg_temp.assert_true(distance_b > 1000.0, 'Clinic B distance is a sane positive value');

    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(
            public.discover_nearby_clinics(40.0, 0.0, distance_b, 50),
            '15000000-0000-4000-8000-000000000012'
        ),
        'A Clinic exactly on the radius boundary is included'
    );
    perform pg_temp.assert_true(
        not pg_temp.discovery_payload_has_clinic(
            public.discover_nearby_clinics(40.0, 0.0, distance_b - 1.0, 50),
            '15000000-0000-4000-8000-000000000012'
        ),
        'A Clinic just outside the radius is excluded'
    );
end;
$$;

-- ===========================================================================
-- Nearby Discovery — near-antipodal Haversine numerical safety, and the
-- MAX_GREAT_CIRCLE_DISTANCE_METERS technical bound itself.
--
-- Clinic E sits close to (but deliberately not exactly at) the geometric
-- antipode of the reference point, so its Haversine "a" intermediate is
-- very close to 1 (exercising the clamp) while its true distance still sits
-- a comfortable, non-fragile few hundred kilometers below the theoretical
-- maximum — an exact antipode's floating-point shortfall below the maximum
-- is sub-meter and therefore too razor-thin to assert a stable inclusion
-- radius against.
-- ===========================================================================
do $$
declare
    max_radius constant double precision := pi() * 6371000.0;
    wide jsonb;
    e_distance double precision;
begin
    -- The technical bound rejects a radius at or beyond the maximum
    -- possible great-circle distance (SPEC-DIS-002 BR-5: never unbounded).
    perform pg_temp.assert_sqlstate(
        format('select public.discover_nearby_clinics(40.0, 0.0, %s)', max_radius),
        '22023'
    );
    perform pg_temp.assert_sqlstate(
        format('select public.discover_nearby_clinics(40.0, 0.0, %s)', max_radius * 2),
        '22023'
    );

    -- A radius comfortably below the bound, but large enough to reach the
    -- near-antipodal Clinic E, must not raise a Haversine domain error.
    wide := public.discover_nearby_clinics(40.0, 0.0, max_radius - 100000.0, 100);
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(wide, '15000000-0000-4000-8000-000000000015'),
        'A near-antipodal Clinic is safely included well inside the maximum radius, with no sqrt domain error'
    );

    e_distance := pg_temp.discovery_payload_clinic_distance(wide, '15000000-0000-4000-8000-000000000015');
    perform pg_temp.assert_true(
        e_distance > max_radius - 1000000.0 and e_distance < max_radius,
        'The near-antipodal distance is large, finite, and strictly below the theoretical maximum'
    );
end;
$$;

-- ===========================================================================
-- Nearby Discovery — deterministic equal-distance tie ordering and a real
-- keyset pagination round-trip. Page 2's cursor values are extracted from
-- page 1's actual returned JSON, never fabricated.
-- ===========================================================================
do $$
declare
    page1 jsonb;
    page2 jsonb;
    d1 double precision;
    d2 double precision;
    cursor_distance double precision;
    cursor_clinic_id uuid;
begin
    d1 := pg_temp.discovery_payload_clinic_distance(
        public.discover_nearby_clinics(0.0, 0.0, 500000.0, 50),
        '15000000-0000-4000-8000-000000000031'
    );
    d2 := pg_temp.discovery_payload_clinic_distance(
        public.discover_nearby_clinics(0.0, 0.0, 500000.0, 50),
        '15000000-0000-4000-8000-000000000032'
    );
    perform pg_temp.assert_true(
        d1 = d2,
        'T1 and T2 are symmetric around the reference longitude and are therefore exactly equidistant'
    );

    page1 := public.discover_nearby_clinics(0.0, 0.0, 500000.0, 2);
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_clinic_ids(page1) = array[
            '15000000-0000-4000-8000-000000000031'::uuid,
            '15000000-0000-4000-8000-000000000032'::uuid
        ],
        'Page 1 returns T1 then T2, tie broken deterministically by clinic_id ascending'
    );
    perform pg_temp.assert_true(
        (page1 ->> 'has_more') = 'true',
        'Page 1 reports more results remaining'
    );

    cursor_distance := (page1 ->> 'next_after_distance_meters')::double precision;
    cursor_clinic_id := (page1 ->> 'next_after_clinic_id')::uuid;
    perform pg_temp.assert_true(
        cursor_distance = d1 and cursor_clinic_id = '15000000-0000-4000-8000-000000000032'::uuid,
        'Page 1 cursor metadata comes from the final returned row (T2), not the probe row'
    );

    page2 := public.discover_nearby_clinics(0.0, 0.0, 500000.0, 2, cursor_distance, cursor_clinic_id);
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_clinic_ids(page2) = array[
            '15000000-0000-4000-8000-000000000033'::uuid,
            '15000000-0000-4000-8000-000000000034'::uuid
        ],
        'Page 2, built from the actual extracted cursor, continues with T3 then T4 with no duplicate and no gap'
    );
    perform pg_temp.assert_true(
        (page2 ->> 'has_more') = 'false',
        'Page 2 is the final page'
    );

    -- Malformed cursor: components must be supplied together.
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(0.0, 0.0, 500000.0, 2, 100.0, null)',
        '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(0.0, 0.0, 500000.0, 2, null, ''15000000-0000-4000-8000-000000000031'')',
        '22023'
    );
end;
$$;

-- ===========================================================================
-- Nearby Discovery — malformed / null / non-finite input validation.
-- ===========================================================================
do $$
begin
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(null, 0.0, 1000.0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, null, 1000.0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 0.0, null)', '22023');

    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(''NaN''::double precision, 0.0, 1000.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(''Infinity''::double precision, 0.0, 1000.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(''-Infinity''::double precision, 0.0, 1000.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(40.0, ''NaN''::double precision, 1000.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(40.0, 0.0, ''NaN''::double precision)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(40.0, 0.0, ''Infinity''::double precision)', '22023'
    );

    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(91.0, 0.0, 1000.0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(-91.0, 0.0, 1000.0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 181.0, 1000.0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, -181.0, 1000.0)', '22023');

    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 0.0, 0.0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 0.0, -5.0)', '22023');

    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 0.0, 1000.0, 0)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 0.0, 1000.0, -5)', '22023');
    perform pg_temp.assert_sqlstate('select public.discover_nearby_clinics(40.0, 0.0, 1000.0, null)', '22023');

    perform pg_temp.assert_sqlstate(
        'select public.discover_nearby_clinics(40.0, 0.0, 1000.0, 50, -5.0, ''15000000-0000-4000-8000-000000000031'')',
        '22023'
    );
    perform pg_temp.assert_sqlstate(
        format(
            'select public.discover_nearby_clinics(40.0, 0.0, 1000.0, 50, %s, ''15000000-0000-4000-8000-000000000031'')',
            pi() * 6371000.0
        ),
        '22023'
    );

    -- p_limit clamps rather than erroring for extreme positive values.
    perform pg_temp.assert_true(
        jsonb_typeof(
            public.discover_nearby_clinics(0.0, 0.0, 500000.0, 1000000) -> 'clinics'
        ) = 'array',
        'An extreme p_limit is clamped rather than rejected'
    );
end;
$$;

-- ===========================================================================
-- Map/viewport Discovery — inside/outside/edge behavior, invalid bounds,
-- antimeridian Phase-1 rejection, keyset pagination round-trip.
-- ===========================================================================
do $$
declare
    box jsonb;
    page1 jsonb;
    page2 jsonb;
    cursor_clinic_id uuid;
begin
    box := public.discover_clinics_in_viewport(9.9, 10.4, 9.9, 10.4, 100);

    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(box, '15000000-0000-4000-8000-000000000041'),
        'Viewport includes a Clinic exactly on the minimum corner (inclusive bounds)'
    );
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(box, '15000000-0000-4000-8000-000000000044'),
        'Viewport includes a Clinic exactly on the maximum corner (inclusive bounds)'
    );
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_has_clinic(box, '15000000-0000-4000-8000-000000000042')
        and pg_temp.discovery_payload_has_clinic(box, '15000000-0000-4000-8000-000000000043'),
        'Viewport includes published Clinics strictly inside the box'
    );
    perform pg_temp.assert_true(
        not pg_temp.discovery_payload_has_clinic(box, '15000000-0000-4000-8000-000000000045'),
        'Viewport excludes a published Clinic outside the box'
    );
    perform pg_temp.assert_true(
        not pg_temp.discovery_payload_has_clinic(box, '15000000-0000-4000-8000-000000000046'),
        'Viewport excludes an unpublished Clinic inside the box'
    );

    -- Keyset pagination round-trip: the cursor is extracted from the actual
    -- page 1 payload, never fabricated.
    page1 := public.discover_clinics_in_viewport(9.9, 10.4, 9.9, 10.4, 2);
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_clinic_ids(page1) = array[
            '15000000-0000-4000-8000-000000000041'::uuid,
            '15000000-0000-4000-8000-000000000042'::uuid
        ],
        'Viewport page 1 returns the two lowest clinic_id values in ascending order'
    );
    perform pg_temp.assert_true((page1 ->> 'has_more') = 'true', 'Viewport page 1 reports more results');

    cursor_clinic_id := (page1 ->> 'next_after_clinic_id')::uuid;
    perform pg_temp.assert_true(
        cursor_clinic_id = '15000000-0000-4000-8000-000000000042'::uuid,
        'Viewport page 1 cursor comes from the final returned row, not the probe row'
    );

    page2 := public.discover_clinics_in_viewport(9.9, 10.4, 9.9, 10.4, 2, cursor_clinic_id);
    perform pg_temp.assert_true(
        pg_temp.discovery_payload_clinic_ids(page2) = array[
            '15000000-0000-4000-8000-000000000043'::uuid,
            '15000000-0000-4000-8000-000000000044'::uuid
        ],
        'Viewport page 2, built from the actual extracted cursor, continues with no duplicate and no gap'
    );
    perform pg_temp.assert_true((page2 ->> 'has_more') = 'false', 'Viewport page 2 is the final page');

    -- Invalid bounds.
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(10.0, 5.0, 0.0, 1.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(null, 5.0, 0.0, 1.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(0.0, null, 0.0, 1.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(0.0, 1.0, null, 1.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(0.0, 1.0, 0.0, null)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(91.0, 92.0, 0.0, 1.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(0.0, 1.0, 181.0, 182.0)', '22023'
    );
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(0.0, 1.0, 0.0, 1.0, 0)', '22023'
    );

    -- Antimeridian-crossing viewport: explicit Phase 1 API limitation, not
    -- wrap-around global-map behavior.
    perform pg_temp.assert_sqlstate(
        'select public.discover_clinics_in_viewport(0.0, 1.0, 170.0, -170.0)', '22023'
    );

    -- A non-crossing full-globe-width box (min_longitude = -180,
    -- max_longitude = 180) is an ordinary wide box, not a crossing request.
    perform pg_temp.assert_true(
        jsonb_typeof(
            public.discover_clinics_in_viewport(-90.0, 90.0, -180.0, 180.0, 10) -> 'clinics'
        ) = 'array',
        'A non-crossing full-width viewport is accepted'
    );
end;
$$;

-- ===========================================================================
-- Cluster 4 — Oversized eligible result set: exactly 101 published Clinics,
-- each with a valid public profile and Location, constructed compactly via
-- generate_series rather than 101 hand-written rows. This proves the
-- server-side 100-row page cap against a genuinely oversized eligible
-- result (not merely a clamped p_limit on a small fixture), for both
-- Discovery collection functions.
--
-- Placement: latitude 30.0, longitude 0.001 * i for i in 1..101 — a tight
-- monotonic strip, isolated from every other cluster in this file by
-- latitude/longitude, with consecutive Clinics roughly 96m apart (far above
-- any floating-point ambiguity) so Nearby distances are strictly increasing
-- with no equal-distance ties, while remaining reusable for the viewport
-- cap regression too.
-- ===========================================================================

set local session_replication_role = replica;

insert into public.clinics (id, organization_id, is_published)
select
    ('15000000-0000-4000-9000-' || lpad(bulk.i::text, 12, '0'))::uuid,
    '15000000-0000-4000-8000-000000000001',
    true
from generate_series(1, 101) as bulk(i);

insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)
select
    ('15000000-0000-4000-9000-' || lpad(bulk.i::text, 12, '0'))::uuid,
    'Bulk Site ' || bulk.i,
    30.0,
    bulk.i * 0.001
from generate_series(1, 101) as bulk(i);

insert into public.clinic_public_profiles (clinic_id, display_name)
select
    ('15000000-0000-4000-9000-' || lpad(bulk.i::text, 12, '0'))::uuid,
    'Bulk Clinic ' || bulk.i
from generate_series(1, 101) as bulk(i);

set local session_replication_role = origin;

create function pg_temp.discovery_bulk_ids()
returns uuid[] language sql as $$
    select array_agg(('15000000-0000-4000-9000-' || lpad(i::text, 12, '0'))::uuid order by i)
    from generate_series(1, 101) as i
$$;

do $$
begin
    perform pg_temp.assert_true(
        array_length(pg_temp.discovery_bulk_ids(), 1) = 101,
        'Exactly 101 bulk Clinic ids were generated for the oversized-result regression'
    );
end;
$$;

-- --- Viewport: bounded 100-row cap against 101 genuinely eligible rows ---
do $$
declare
    all_ids uuid[] := pg_temp.discovery_bulk_ids();
    page1 jsonb;
    page2 jsonb;
    page1_ids uuid[];
    page2_ids uuid[];
    cursor_clinic_id uuid;
    combined_count integer;
    distinct_count integer;
begin
    page1 := public.discover_clinics_in_viewport(29.9, 30.1, 0.0, 0.2, 1000);
    page1_ids := pg_temp.discovery_payload_clinic_ids(page1);

    perform pg_temp.assert_true(
        array_length(page1_ids, 1) = 100,
        'Viewport returns exactly 100 Clinics from a genuinely oversized (101) eligible result, regardless of the requested p_limit'
    );
    perform pg_temp.assert_true(
        (page1 ->> 'has_more') = 'true',
        'Viewport reports more results beyond the 100-row cap'
    );

    cursor_clinic_id := (page1 ->> 'next_after_clinic_id')::uuid;
    perform pg_temp.assert_true(
        cursor_clinic_id = page1_ids[100],
        'Viewport cursor is the final (100th) returned row, not the 101st probe row'
    );

    page2 := public.discover_clinics_in_viewport(29.9, 30.1, 0.0, 0.2, 1000, cursor_clinic_id);
    page2_ids := pg_temp.discovery_payload_clinic_ids(page2);

    perform pg_temp.assert_true(
        array_length(page2_ids, 1) = 1 and (page2 ->> 'has_more') = 'false',
        'Continuing from the actual extracted cursor returns exactly the one remaining Clinic, as the final page'
    );

    select count(*), count(distinct id) into combined_count, distinct_count
    from unnest(page1_ids || page2_ids) as id;

    perform pg_temp.assert_true(
        combined_count = 101 and distinct_count = 101,
        'Across both viewport pages every one of the 101 eligible Clinics appears exactly once: no duplicate, no gap'
    );

    perform pg_temp.assert_true(
        (select array_agg(id order by id) from unnest(page1_ids || page2_ids) as id)
        = (select array_agg(id order by id) from unnest(all_ids) as id),
        'The two viewport pages together reproduce exactly the generated bulk Clinic id set, in full'
    );
end;
$$;

-- --- Nearby: bounded 100-row cap against 101 genuinely eligible rows ---
do $$
declare
    all_ids uuid[] := pg_temp.discovery_bulk_ids();
    page1 jsonb;
    page2 jsonb;
    page1_ids uuid[];
    page2_ids uuid[];
    cursor_distance double precision;
    cursor_clinic_id uuid;
    combined_count integer;
    distinct_count integer;
begin
    -- Reference point west of the entire strip: distance to every bulk
    -- Clinic increases strictly with i (longitude), so there is no
    -- equal-distance tie anywhere in this fixture, and the farthest bulk
    -- Clinic (~106km away) is still comfortably inside the 200km radius —
    -- all 101 are genuinely eligible before the page cap applies. No other
    -- cluster in this file is within 200km of this reference point.
    page1 := public.discover_nearby_clinics(30.0, -1.0, 200000.0, 1000);
    page1_ids := pg_temp.discovery_payload_clinic_ids(page1);

    perform pg_temp.assert_true(
        array_length(page1_ids, 1) = 100,
        'Nearby Discovery returns exactly 100 Clinics from a genuinely oversized (101) eligible result, regardless of the requested p_limit'
    );
    perform pg_temp.assert_true(
        (page1 ->> 'has_more') = 'true',
        'Nearby Discovery reports more results beyond the 100-row cap'
    );

    cursor_distance := (page1 ->> 'next_after_distance_meters')::double precision;
    cursor_clinic_id := (page1 ->> 'next_after_clinic_id')::uuid;
    perform pg_temp.assert_true(
        cursor_clinic_id = page1_ids[100]
        and cursor_distance = pg_temp.discovery_payload_clinic_distance(page1, page1_ids[100]),
        'Nearby cursor metadata comes from the final (100th) returned row, not the 101st probe row'
    );

    page2 := public.discover_nearby_clinics(30.0, -1.0, 200000.0, 1000, cursor_distance, cursor_clinic_id);
    page2_ids := pg_temp.discovery_payload_clinic_ids(page2);

    perform pg_temp.assert_true(
        array_length(page2_ids, 1) = 1 and (page2 ->> 'has_more') = 'false',
        'Continuing from the actual extracted cursor returns exactly the one remaining Clinic, as the final page'
    );

    select count(*), count(distinct id) into combined_count, distinct_count
    from unnest(page1_ids || page2_ids) as id;

    perform pg_temp.assert_true(
        combined_count = 101 and distinct_count = 101,
        'Across both Nearby pages every one of the 101 eligible Clinics appears exactly once: no duplicate, no gap'
    );

    perform pg_temp.assert_true(
        (select array_agg(id order by id) from unnest(page1_ids || page2_ids) as id)
        = (select array_agg(id order by id) from unnest(all_ids) as id),
        'The two Nearby pages together reproduce exactly the generated bulk Clinic id set, in full'
    );
end;
$$;

-- ===========================================================================
-- Static ACL / regression checks.
-- ===========================================================================
do $$
declare
    role_name text;
    relation_name text;
    function_signature text;
begin
    -- Direct base-table access remains denied for anon and authenticated —
    -- unchanged from Slice 4/6.
    foreach role_name in array array['anon', 'authenticated'] loop
        foreach relation_name in array array[
            'public.clinics',
            'public.clinic_locations',
            'public.clinic_public_profiles'
        ] loop
            perform pg_temp.assert_true(
                (select bool_and(not has_table_privilege(role_name, relation_name, p))
                 from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p),
                format('%s holds no direct privilege on %s', role_name, relation_name)
            );
        end loop;
    end loop;

    perform pg_temp.assert_true(
        (select bool_and(relrowsecurity)
         from pg_class
         where oid in (
             'public.clinics'::regclass,
             'public.clinic_locations'::regclass,
             'public.clinic_public_profiles'::regclass
         )),
        'Row level security stays enabled on every base Clinic table'
    );

    -- The three Slice 15 functions are callable by anon and authenticated.
    foreach function_signature in array array[
        'public.get_published_clinic_location(uuid)',
        'public.discover_nearby_clinics(double precision,double precision,double precision,integer,double precision,uuid)',
        'public.discover_clinics_in_viewport(double precision,double precision,double precision,double precision,integer,uuid)'
    ] loop
        perform pg_temp.assert_true(
            has_function_privilege('anon', function_signature, 'EXECUTE')
            and has_function_privilege('authenticated', function_signature, 'EXECUTE'),
            format('anon and authenticated can execute %s', function_signature)
        );
    end loop;

    -- Regression guard: the rejected unbounded view and optional browse RPC
    -- were not introduced.
    perform pg_temp.assert_true(
        to_regclass('public.published_clinic_locations') is null,
        'No unbounded published_clinic_locations view was introduced'
    );
    perform pg_temp.assert_true(
        to_regprocedure('public.list_published_clinics(integer,uuid)') is null,
        'No optional list_published_clinics browse RPC was introduced'
    );
end;
$$;

rollback;

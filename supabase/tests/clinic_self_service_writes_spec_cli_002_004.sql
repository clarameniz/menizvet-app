-- Regression suite for Clinic self-service Phase 1, Slice B: the Public
-- Profile and Location writes used by the professional editors
-- (20261024090000_clinic_profile_location_fail_closed_writes.sql;
-- SPEC-CLI-004 BR-15–BR-20, Verification Notes 13–22; SPEC-CLI-002
-- BR-12–BR-17, Verification Notes 11–19).
--
-- It pins: the exact stored result of each save (backend whitespace set,
-- blank = NULL, whole-value replacement, all-absent profile removal while
-- unpublished, published display name retained); location validity
-- (non-blank address, coordinate ranges, 0,0 allowed, no removal); the
-- allowed/denied role matrix with nothing written on denial; the fail-closed
-- disclosure order (28000, then the same 42501 for unknown and inaccessible
-- Clinics whatever the input, then 22023 / 23514 only for authorized
-- callers); Clinic isolation; no Entitlement; last-write-wins; that the
-- writes still lock Organization and Clinic; and the public effect (published
-- Clinics show the new values on public reads, unpublished stay invisible,
-- publication and scheduling configuration untouched).
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required to load a deterministic context with establishment
-- triggers bypassed, to read row-lock evidence, and to switch between
-- impersonated Users.
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_error(
    p_statement text, p_expected_sqlstate text, p_expected_message_fragment text
)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected_sqlstate
           and (p_expected_message_fragment is null
                or position(p_expected_message_fragment in sqlerrm) > 0) then
            return;
        end if;
        raise exception 'Expected SQLSTATE % (%), received %: % — %',
            p_expected_sqlstate, p_expected_message_fragment, sqlstate, sqlerrm, p_statement;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded: %', p_expected_sqlstate, p_statement;
end;
$$;

-- The complete observable outcome of a statement (SQLSTATE and message), or
-- 'SUCCEEDED'. Run in a subtransaction, so a succeeding write is undone.
create function pg_temp.outcome(p_statement text) returns text language plpgsql as $$
begin
    begin
        execute p_statement;
        raise exception using errcode = 'P0001', message = 'pg_temp.outcome: SUCCEEDED';
    exception when others then
        if sqlerrm = 'pg_temp.outcome: SUCCEEDED' then
            return 'SUCCEEDED';
        end if;
        return sqlstate || ': ' || sqlerrm;
    end;
end;
$$;

create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c1800000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c1800000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.act_anonymous() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true);
$$;
create function pg_temp.org(p_n integer) returns uuid language sql immutable as $$
    select ('c1800000-0000-4000-8000-0000000003' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c1800000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.profile_sql(
    p_clinic uuid, p_name text, p_description text, p_phone text, p_email text, p_website text
) returns text language sql immutable as $$
    select format('select public.set_clinic_public_profile(%L, %L, %L, %L, %L, %L)',
                  p_clinic, p_name, p_description, p_phone, p_email, p_website)
$$;
create function pg_temp.location_sql(
    p_clinic uuid, p_address text, p_latitude double precision, p_longitude double precision
) returns text language sql immutable as $$
    select format('select public.set_clinic_location(%L, %L, %L::double precision, %L::double precision)',
                  p_clinic, p_address, p_latitude, p_longitude)
$$;

-- Stored values, as JSON (NULL when no row).
create function pg_temp.profile_of(p_clinic uuid) returns jsonb language sql as $$
    select to_jsonb(profile) - 'clinic_id' from public.clinic_public_profiles as profile
    where profile.clinic_id = p_clinic
$$;
create function pg_temp.location_of(p_clinic uuid) returns jsonb language sql as $$
    select to_jsonb(location) - 'clinic_id' from public.clinic_locations as location
    where location.clinic_id = p_clinic
$$;
-- Everything this suite's Clinics store, to prove that a denied or failed
-- write changes nothing.
create function pg_temp.fingerprint() returns text language sql as $$
    select md5(concat_ws('|',
        (select string_agg(format('%s/%s/%s/%s/%s', id, is_published, scheduling_timezone_name,
                                  standard_appointment_duration_minutes,
                                  weekly_appointment_availability_revision), ',' order by id)
         from public.clinics where id::text like 'c1800000-%'),
        (select string_agg(to_jsonb(profile)::text, ',' order by clinic_id)
         from public.clinic_public_profiles as profile where clinic_id::text like 'c1800000-%'),
        (select string_agg(to_jsonb(location)::text, ',' order by clinic_id)
         from public.clinic_locations as location where clinic_id::text like 'c1800000-%')))
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c1800000-…-0000000001NN, domain Users …-0000000002NN:
--   01 no Membership                    09 ADMINISTRATOR @ A2 (Clinic)
--   04 OrgA OWNER                       10 VETERINARIAN OrgA, current Assignment @ A1
--   05 OrgA Org ADMINISTRATOR           11 OrgA Org ADMINISTRATOR, Membership ended
--   06 ADMINISTRATOR @ A1 (Clinic)      12 OrgA Org ADMINISTRATOR, Grant ended
--   07 OrgA Org RECEPTIONIST            14 OrgB OWNER
--   08 RECEPTIONIST @ A1 (Clinic)       16 authentication subject without a domain User
--   18 OWNER of L1 (section 7 lock evidence)
-- Organizations (none holds a Subscription, so every write runs without any
-- Entitlement): 0301 OrgA — A1 (0401) published with profile and location,
-- A2 (0402) unpublished and empty, A3 (0403) unpublished with a profile;
-- 0302 OrgB — B1 (0405) unpublished and empty; 0311 L1 — 0411.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('c1800000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 18]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c1800000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 18]) as n;

insert into public.veterinary_organizations (id, display_name)
select pg_temp.org(n), 'Clinic self-service writes Org ' || n
from unnest(array[1, 2, 11]) as n;

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes) values
    (pg_temp.clinic(1), pg_temp.org(1), true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), pg_temp.org(1), false, null, null),
    (pg_temp.clinic(3), pg_temp.org(1), false, 'Atlantic/Canary', null),
    (pg_temp.clinic(5), pg_temp.org(2), false, null, null),
    (pg_temp.clinic(11), pg_temp.org(11), false, null, null);

insert into public.clinic_public_profiles (clinic_id, display_name, description, public_phone, public_email, website) values
    (pg_temp.clinic(1), 'Animalia Madrid Centro', 'Centro', '+34 910 000 001', 'centro@example.test', 'https://centro.example.test'),
    (pg_temp.clinic(3), 'Animalia Las Palmas', 'Canarias', null, null, null);
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    (pg_temp.clinic(1), 'Calle Mayor 1, 28013 Madrid', 40.4168, -3.7038);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select ('c1800000-0000-4000-8000-0000000005' || lpad(member.n::text, 2, '0'))::uuid, pg_temp.org(member.org_n),
       pg_temp.domain_user(member.user_n), '2020-01-01Z', member.ended,
       case when member.ended is null then null else pg_temp.domain_user(4) end
from (values
    (4, 1, 4, null::timestamptz), (5, 1, 5, null), (6, 1, 6, null), (7, 1, 7, null), (8, 1, 8, null),
    (9, 1, 9, null), (10, 1, 10, null), (11, 1, 11, '2021-01-01Z'), (12, 1, 12, null),
    (14, 2, 14, null), (61, 11, 18, null)
) as member (n, org_n, user_n, ended);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
)
select ('c1800000-0000-4000-8000-0000000006' || lpad(grant_row.n::text, 2, '0'))::uuid,
       ('c1800000-0000-4000-8000-0000000005' || lpad(grant_row.n::text, 2, '0'))::uuid,
       grant_row.responsibility, grant_row.scope_type, grant_row.clinic_id, '2020-01-01Z', grant_row.ended,
       pg_temp.domain_user(4), case when grant_row.ended is null then null else pg_temp.domain_user(4) end
from (values
    (4, 'OWNER', 'ORGANIZATION', null::uuid, null::timestamptz),
    (5, 'ADMINISTRATOR', 'ORGANIZATION', null, null),
    (6, 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(1), null),
    (7, 'RECEPTIONIST', 'ORGANIZATION', null, null),
    (8, 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), null),
    (9, 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(2), null),
    (10, 'VETERINARIAN', 'ORGANIZATION', null, null),
    (11, 'ADMINISTRATOR', 'ORGANIZATION', null, null),
    (12, 'ADMINISTRATOR', 'ORGANIZATION', null, '2021-01-01Z'),
    (14, 'OWNER', 'ORGANIZATION', null, null),
    (61, 'OWNER', 'ORGANIZATION', null, null)
) as grant_row (n, responsibility, scope_type, clinic_id, ended);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('c1800000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('c1800000-0000-4000-8000-000000000810', 'c1800000-0000-4000-8000-000000000710',
     'c1800000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z', null);

set local session_replication_role = origin;

select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.org(1), 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement(pg_temp.org(1), 'PROFESSIONAL_SCHEDULING')
    and not public.organization_has_professional_entitlement(pg_temp.org(2), 'APPOINTMENT_MANAGEMENT'),
    'Fixture: no Organization holds any professional Entitlement'
);

-- ===========================================================================
-- 1. Contract: signatures, attributes, and ACL unchanged
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(
                proc.prosecdef
                and proc.proconfig = array['search_path=""']
                and pg_get_function_result(proc.oid) = 'uuid'
                and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                and not has_function_privilege('anon', proc.oid, 'EXECUTE'))
     from pg_proc as proc
     where proc.oid in (
         'public.set_clinic_public_profile(uuid, text, text, text, text, text)'::regprocedure,
         'public.set_clinic_location(uuid, text, double precision, double precision)'::regprocedure))
    and (select count(*) = 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'set_clinic_public_profile')
    and (select count(*) = 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'set_clinic_location'),
    'Contract: set_clinic_public_profile and set_clinic_location keep one overload each, SECURITY DEFINER, empty search_path, uuid result, authenticated-only'
);

select pg_temp.assert_true(
    not exists (
        select 1 from pg_proc
        where pronamespace = 'public'::regnamespace
          and proname ~ '(remove|clear|delete|unset).*location|location.*(remove|clear|delete)'),
    'Contract: there is no Clinic location removal operation (SPEC-CLI-002 BR-15)'
);

-- ===========================================================================
-- 2. Profile: normalization, blank = NULL, replacement, removal, published name
-- ===========================================================================

select pg_temp.act(4);

-- Backend whitespace set only: space, tab, LF, CR, FF, VT are trimmed; a
-- non-breaking space (U+00A0) is not; inner whitespace is kept.
select public.set_clinic_public_profile(
    pg_temp.clinic(2),
    E' \t Animalia Getafe \r\n',
    E'\nLínea uno\n\nLínea  dos \f',
    E'\013+34 910 000 002 ',
    '',
    E'  \t\n  ');
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(2)) = jsonb_build_object(
        'display_name', 'Animalia Getafe',
        'description', E'Línea uno\n\nLínea  dos',
        'public_phone', '+34 910 000 002',
        'public_email', null,
        'website', null),
    'Profile: values are trimmed with the backend whitespace set, inner whitespace kept, and blank values stored as NULL'
);

select public.set_clinic_public_profile(pg_temp.clinic(2), E' Animalia ', null, null, null, null);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(2)) ->> 'display_name' = E' Animalia ',
    'Profile: a non-breaking space is not part of the backend whitespace set and is kept'
);

-- Replacement, not patch: every value omitted from a save becomes NULL.
select public.set_clinic_public_profile(pg_temp.clinic(2), 'Animalia Getafe', 'Nueva descripción', null, 'getafe@example.test', null);
select public.set_clinic_public_profile(pg_temp.clinic(2), null, 'Solo descripción', null, null, null);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(2)) = jsonb_build_object(
        'display_name', null,
        'description', 'Solo descripción',
        'public_phone', null,
        'public_email', null,
        'website', null),
    'Profile: one save replaces all five values — values not resubmitted are cleared, never kept from the stored profile'
);

-- All absent on an unpublished Clinic removes the stored profile.
select public.set_clinic_public_profile(pg_temp.clinic(3), '  ', '', null, E'\t', null);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(3)) is null
    and (select not is_published from public.clinics where id = pg_temp.clinic(3)),
    'Profile: an all-absent save on an unpublished Clinic removes its profile and leaves it unpublished'
);

-- A published Clinic keeps its display name; optional values may be cleared.
create temporary table published_before as select pg_temp.fingerprint() as value;
select pg_temp.assert_error(
    pg_temp.profile_sql(pg_temp.clinic(1), '   ', 'Centro', null, null, null),
    '23514', 'A published Clinic must retain a valid public display name');
select pg_temp.assert_error(
    pg_temp.profile_sql(pg_temp.clinic(1), null, null, null, null, null),
    '23514', 'A published Clinic must retain a valid public display name');
select pg_temp.assert_true(
    pg_temp.fingerprint() = (select value from published_before),
    'Profile: removing the display name of a published Clinic (alone or with everything) is rejected and changes nothing'
);

select public.set_clinic_public_profile(pg_temp.clinic(1), 'Animalia Madrid Sol', null, null, null, null);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(1)) = jsonb_build_object(
        'display_name', 'Animalia Madrid Sol',
        'description', null, 'public_phone', null, 'public_email', null, 'website', null)
    and (select is_published from public.clinics where id = pg_temp.clinic(1)),
    'Profile: a published Clinic may replace its name and clear every optional value, and stays published'
);

select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(5)) is null,
    'Profile isolation: no other Clinic was given a profile by these saves'
);

-- ===========================================================================
-- 3. Location: create, replace, validity, 0,0, no removal
-- ===========================================================================

select pg_temp.act(4);

select public.set_clinic_location(pg_temp.clinic(2), E' \tAvenida de España 2,\nGetafe \n', 40.305712, -3.732915);
select pg_temp.assert_true(
    pg_temp.location_of(pg_temp.clinic(2)) = jsonb_build_object(
        'address_text', E'Avenida de España 2,\nGetafe', 'latitude', 40.305712, 'longitude', -3.732915),
    'Location: the first save establishes the location, address trimmed with the backend set, coordinates exact'
);

select public.set_clinic_location(pg_temp.clinic(2), E' Calle Sol 3 ', 40.305712, -3.732915);
select pg_temp.assert_true(
    pg_temp.location_of(pg_temp.clinic(2)) ->> 'address_text' = E' Calle Sol 3 ',
    'Location: a non-breaking space is not part of the backend whitespace set and is kept in the address'
);

select public.set_clinic_location(pg_temp.clinic(2), 'Calle Madrid 5, Getafe', 40.3, -3.73);
select pg_temp.assert_true(
    pg_temp.location_of(pg_temp.clinic(2)) = jsonb_build_object(
        'address_text', 'Calle Madrid 5, Getafe', 'latitude', 40.3, 'longitude', -3.73),
    'Location: a later save replaces address and both coordinates together'
);

create temporary table location_before as select pg_temp.fingerprint() as value;
do $$
declare
    invalid record;
begin
    for invalid in
        select * from (values
            (null::text, 40.0::double precision, -3.0::double precision, 'address must not be blank'),
            ('', 40.0, -3.0, 'address must not be blank'),
            (E' \t\r\n\f\013', 40.0, -3.0, 'address must not be blank'),
            ('Calle 1', null, -3.0, 'latitude must be between -90 and 90'),
            ('Calle 1', 90.000001, -3.0, 'latitude must be between -90 and 90'),
            ('Calle 1', -90.000001, -3.0, 'latitude must be between -90 and 90'),
            ('Calle 1', 'NaN', -3.0, 'latitude must be between -90 and 90'),
            ('Calle 1', 'Infinity', -3.0, 'latitude must be between -90 and 90'),
            ('Calle 1', 40.0, null, 'longitude must be between -180 and 180'),
            ('Calle 1', 40.0, 180.000001, 'longitude must be between -180 and 180'),
            ('Calle 1', 40.0, -180.000001, 'longitude must be between -180 and 180'),
            ('Calle 1', 40.0, '-Infinity', 'longitude must be between -180 and 180')
        ) as cases (address, latitude, longitude, message)
    loop
        perform pg_temp.assert_error(
            pg_temp.location_sql(pg_temp.clinic(2), invalid.address, invalid.latitude, invalid.longitude),
            '22023', invalid.message);
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.fingerprint() = (select value from location_before),
    'Location: blank or null address and out-of-range, null, NaN, or infinite coordinates are rejected with 22023 and change nothing'
);

do $$
declare
    boundary record;
begin
    for boundary in
        select * from (values
            (90.0::double precision, 180.0::double precision),
            (-90.0, -180.0),
            (0.0, 0.0),
            (-0.000001, 0.000001)
        ) as cases (latitude, longitude)
    loop
        perform public.set_clinic_location(pg_temp.clinic(3), 'Límite', boundary.latitude, boundary.longitude);
        perform pg_temp.assert_true(
            (select latitude = boundary.latitude and longitude = boundary.longitude
             from public.clinic_locations where clinic_id = pg_temp.clinic(3)),
            format('Location: boundary coordinate %s, %s is accepted and stored exactly', boundary.latitude, boundary.longitude));
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.location_of(pg_temp.clinic(3)) = jsonb_build_object(
        'address_text', 'Límite', 'latitude', -0.000001, 'longitude', 0.000001),
    'Location: 0,0 and both range boundaries are valid; no plausibility rule is applied'
);

-- ===========================================================================
-- 4. Authorization matrix and fail-closed disclosure order
-- ===========================================================================

do $$
declare
    actor integer;
begin
    -- Allowed at A1: Owner, Organization Administrator, A1's Clinic Administrator.
    foreach actor in array array[4, 5, 6] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_true(
            pg_temp.outcome(pg_temp.profile_sql(pg_temp.clinic(1), 'Nombre ' || actor, null, null, null, null)) = 'SUCCEEDED'
            and pg_temp.outcome(pg_temp.location_sql(pg_temp.clinic(1), 'Dirección ' || actor, 40.0, -3.0)) = 'SUCCEEDED',
            format('Authorization: User %s may save A1''s profile and location', actor));
    end loop;
end;
$$;

create temporary table denied_before as select pg_temp.fingerprint() as value;
do $$
declare
    actor integer;
begin
    -- Denied at A1: no Membership, Organization and Clinic Receptionists,
    -- another Clinic's Administrator, a Veterinarian with a current
    -- Assignment, an ended Membership, an ended Grant, another
    -- Organization's Owner.
    foreach actor in array array[1, 7, 8, 9, 10, 11, 12, 14] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_error(
            pg_temp.profile_sql(pg_temp.clinic(1), 'Intruso', null, null, null, null),
            '42501', 'Clinic Public Profile-management capability is required');
        perform pg_temp.assert_error(
            pg_temp.location_sql(pg_temp.clinic(1), 'Intruso', 1.0, 1.0),
            '42501', 'Clinic Location-management capability is required');
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.fingerprint() = (select value from denied_before),
    'Authorization: no Membership, Receptionists (Organization and Clinic scope), another Clinic''s Administrator, a Veterinarian, an ended Membership or Grant, and another Organization''s Owner are denied with 42501 and write nothing'
);

-- Unauthenticated: 28000 first, whatever the Clinic and input.
do $$
declare
    statement text;
begin
    foreach statement in array array[
        pg_temp.profile_sql(pg_temp.clinic(1), 'x', null, null, null, null),
        pg_temp.profile_sql(pg_temp.clinic(99), null, null, null, null, null),
        pg_temp.location_sql(pg_temp.clinic(1), 'x', 1.0, 1.0),
        pg_temp.location_sql(pg_temp.clinic(99), '', 999.0, 999.0)
    ] loop
        perform pg_temp.act_anonymous();
        perform pg_temp.assert_error(statement, '28000', 'Authentication is required');
        perform pg_temp.act(16);
        perform pg_temp.assert_error(statement, '28000', 'No coherent domain User exists');
    end loop;
end;
$$;

-- Unknown and inaccessible Clinics are indistinguishable, and nothing about
-- the submitted input is disclosed to a caller who may not manage the Clinic:
-- for each caller, every location submission (valid, blank address,
-- out-of-range coordinates) to an unknown Clinic, an inaccessible published
-- Clinic, and an inaccessible unpublished Clinic has the identical outcome.
-- The published-name rule likewise is never evaluated for them.
do $$
declare
    actor integer;
    expected_location text := '42501: Clinic Location-management capability is required';
    expected_profile text := '42501: Clinic Public Profile-management capability is required';
    target uuid;
    location_input record;
begin
    foreach actor in array array[14, 7, 1] loop
        perform pg_temp.act(actor);
        foreach target in array array[pg_temp.clinic(99), pg_temp.clinic(1), pg_temp.clinic(2)] loop
            for location_input in
                select * from (values
                    ('Calle 1'::text, 40.0::double precision, -3.0::double precision),
                    ('   ', 40.0, -3.0),
                    (null, 999.0, -999.0),
                    ('Calle 1', 'NaN', 0.0)
                ) as cases (address, latitude, longitude)
            loop
                perform pg_temp.assert_true(
                    pg_temp.outcome(pg_temp.location_sql(target, location_input.address,
                                                          location_input.latitude, location_input.longitude))
                        = expected_location,
                    format('Disclosure: User %s, Clinic %s, location input (%s, %s, %s) gets exactly "%s"',
                           actor, target, location_input.address, location_input.latitude,
                           location_input.longitude, expected_location));
            end loop;
            perform pg_temp.assert_true(
                pg_temp.outcome(pg_temp.profile_sql(target, 'Nombre', null, null, null, null)) = expected_profile
                and pg_temp.outcome(pg_temp.profile_sql(target, null, null, null, null, null)) = expected_profile,
                format('Disclosure: User %s, Clinic %s, any profile input (including removing a published name) gets exactly "%s"',
                       actor, target, expected_profile));
        end loop;
    end loop;

    -- An authorized caller writing to an unknown Clinic gets the same 42501.
    perform pg_temp.act(4);
    perform pg_temp.assert_true(
        pg_temp.outcome(pg_temp.location_sql(pg_temp.clinic(99), '', 999.0, 0.0)) = expected_location
        and pg_temp.outcome(pg_temp.profile_sql(pg_temp.clinic(99), 'x', null, null, null, null)) = expected_profile,
        'Disclosure: even an Owner gets 42501, not 23503, for an unknown Clinic');
end;
$$;

-- Input and state rules are evaluated only after authorization.
select pg_temp.act(4);
select pg_temp.assert_error(pg_temp.location_sql(pg_temp.clinic(1), '  ', 40.0, -3.0),
    '22023', 'address must not be blank');
select pg_temp.assert_error(pg_temp.profile_sql(pg_temp.clinic(1), '', null, null, null, null),
    '23514', 'must retain a valid public display name');

-- ===========================================================================
-- 5. Isolation and no Entitlement
-- ===========================================================================

-- A2's Clinic Administrator edits A2 but never A1, and an Owner of another
-- Organization (no Subscription) edits only its own Clinic.
select pg_temp.act(9);
create temporary table a1_before as
select pg_temp.profile_of(pg_temp.clinic(1)) as profile, pg_temp.location_of(pg_temp.clinic(1)) as location;
select public.set_clinic_public_profile(pg_temp.clinic(2), 'Getafe Norte', null, null, null, null);
select public.set_clinic_location(pg_temp.clinic(2), 'Getafe Norte 1', 40.31, -3.72);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(2)) ->> 'display_name' = 'Getafe Norte'
    and pg_temp.location_of(pg_temp.clinic(2)) ->> 'address_text' = 'Getafe Norte 1'
    and pg_temp.profile_of(pg_temp.clinic(1)) = (select profile from a1_before)
    and pg_temp.location_of(pg_temp.clinic(1)) = (select location from a1_before),
    'Isolation: a Clinic-scoped Administrator saves its own Clinic and no sibling Clinic changes'
);

select pg_temp.act(14);
select public.set_clinic_public_profile(pg_temp.clinic(5), 'VetCare', null, null, null, null);
select public.set_clinic_location(pg_temp.clinic(5), 'Rua Augusta 5, Lisboa', 38.7101, -9.1366);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(5)) ->> 'display_name' = 'VetCare'
    and pg_temp.location_of(pg_temp.clinic(5)) ->> 'address_text' = 'Rua Augusta 5, Lisboa',
    'Entitlement: an Organization with no Subscription saves its profile and location'
);

-- ===========================================================================
-- 6. Last-write-wins (approved Phase 1 policy, SPEC-CLI-004 BR-19,
--    SPEC-CLI-002 BR-16)
-- ===========================================================================
-- Two editors prepared their drafts from the same read of A2. The first
-- saves a name and a phone; the second, still holding the earlier draft
-- (no phone), saves later. The later save wins completely — including
-- clearing the phone the second editor never saw — and is not rejected as
-- stale. The same holds for the location.

select pg_temp.act(4);
select public.set_clinic_public_profile(pg_temp.clinic(2), 'Editor uno', null, '+34 600 000 001', null, null);
select pg_temp.act(5);
select public.set_clinic_public_profile(pg_temp.clinic(2), 'Editor dos', 'Borrador antiguo', null, null, null);
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(2)) = jsonb_build_object(
        'display_name', 'Editor dos', 'description', 'Borrador antiguo',
        'public_phone', null, 'public_email', null, 'website', null),
    'Last-write-wins: the later profile save replaces the earlier one entirely, without stale rejection'
);

select pg_temp.act(4);
select public.set_clinic_location(pg_temp.clinic(2), 'Primera dirección', 40.1, -3.1);
select pg_temp.act(5);
select public.set_clinic_location(pg_temp.clinic(2), 'Segunda dirección', 40.2, -3.2);
select pg_temp.assert_true(
    pg_temp.location_of(pg_temp.clinic(2)) = jsonb_build_object(
        'address_text', 'Segunda dirección', 'latitude', 40.2, 'longitude', -3.2),
    'Last-write-wins: the later location save replaces the earlier one'
);

-- ===========================================================================
-- 7. Writes keep their Organization -> Clinic locking
-- ===========================================================================

create function pg_temp.lock_marks(p_n integer) returns text language sql as $$
    select (select (xmax::text <> '0')::text from public.veterinary_organizations where id = pg_temp.org(p_n))
        || '/' || (select (xmax::text <> '0')::text from public.clinics where id = pg_temp.clinic(p_n))
$$;

select pg_temp.assert_true(pg_temp.lock_marks(11) = 'false/false',
    'Locking: before the write, L1 carries no lock');
select pg_temp.act(18);
select public.set_clinic_location(pg_temp.clinic(11), 'Calle Lock 1', 1.0, 1.0);
select pg_temp.assert_true(pg_temp.lock_marks(11) = 'true/true',
    'Locking: set_clinic_location still locks its Organization and Clinic rows');

-- ===========================================================================
-- 8. Public effect and unrelated state
-- ===========================================================================

-- A1 is published: the new profile and location reach every public read.
select pg_temp.act(4);
select public.set_clinic_public_profile(pg_temp.clinic(1), 'Animalia Retiro', 'Junto al parque', null, null, 'https://retiro.example.test');
select public.set_clinic_location(pg_temp.clinic(1), 'Calle de Alcalá 100, Madrid', 40.421, -3.68);

select pg_temp.act_anonymous();
select pg_temp.assert_true(
    (select display_name = 'Animalia Retiro' and description = 'Junto al parque'
            and website = 'https://retiro.example.test'
     from public.published_clinic_public_profiles where clinic_id = pg_temp.clinic(1))
    and (select address_text = 'Calle de Alcalá 100, Madrid' and latitude = 40.421 and longitude = -3.68
         from public.get_published_clinic_location(pg_temp.clinic(1)))
    and exists (
        select 1
        from jsonb_array_elements(public.discover_nearby_clinics(40.421, -3.68, 1000) -> 'clinics') as clinic_row
        where clinic_row ->> 'clinic_id' = pg_temp.clinic(1)::text
          and clinic_row ->> 'display_name' = 'Animalia Retiro'
          and clinic_row ->> 'address_text' = 'Calle de Alcalá 100, Madrid')
    and exists (
        select 1
        from jsonb_array_elements(public.discover_clinics_in_viewport(40.4, 40.5, -3.7, -3.6) -> 'clinics') as clinic_row
        where clinic_row ->> 'clinic_id' = pg_temp.clinic(1)::text)
    and not exists (
        select 1
        from jsonb_array_elements(public.discover_nearby_clinics(40.4168, -3.7038, 100) -> 'clinics') as clinic_row
        where clinic_row ->> 'clinic_id' = pg_temp.clinic(1)::text),
    'Public effect: the published Clinic''s new profile and location are what the public detail, location, nearby, and map reads return; its old position no longer matches'
);

-- A2 is unpublished: configured, but invisible to every public read.
select pg_temp.assert_true(
    pg_temp.profile_of(pg_temp.clinic(2)) is not null
    and pg_temp.location_of(pg_temp.clinic(2)) is not null
    and not exists (select 1 from public.published_clinic_public_profiles where clinic_id = pg_temp.clinic(2))
    and not exists (select 1 from public.get_published_clinic_location(pg_temp.clinic(2)))
    and not exists (
        select 1
        from jsonb_array_elements(public.discover_nearby_clinics(40.2, -3.2, 5000) -> 'clinics') as clinic_row
        where clinic_row ->> 'clinic_id' = pg_temp.clinic(2)::text),
    'Public effect: an unpublished Clinic with a profile and a location stays undiscoverable'
);

-- Profile and location saves never change publication, timezone, duration,
-- or the weekly revision.
select pg_temp.assert_true(
    (select string_agg(format('%s/%s/%s/%s', is_published, scheduling_timezone_name,
                              standard_appointment_duration_minutes, weekly_appointment_availability_revision),
                       ',' order by id)
     from public.clinics where id in (pg_temp.clinic(1), pg_temp.clinic(2), pg_temp.clinic(3), pg_temp.clinic(5)))
    = 't/Europe/Madrid/30/0,f///0,f/Atlantic/Canary//0,f///0',
    'Unrelated state: publication, scheduling timezone, standard duration, and weekly revision are unchanged by every save'
);

do $$ begin raise notice 'clinic_self_service_writes_spec_cli_002_004.sql: all assertions passed'; end $$;

rollback;

-- Regression suite for Clinic self-service Phase 1, Slice C: scheduling
-- timezone, Publish, and Unpublish
-- (20261025090000_clinic_timezone_publication_self_service.sql;
-- SPEC-APT-013 BR-56/BR-76, Verification Notes 48–54; SPEC-CLI-003
-- BR-15–BR-20, Verification Notes 12–23).
--
-- It pins: timezone changes (trimmed valid IANA name, invalid rejected, no
-- clearing, Location and Appointment history untouched, BR-56 gated and
-- ungated cases, last-write-wins); Publish requirements exactly as SPEC-CLI-003
-- BR-15 (display name + location; NOT timezone, duration, Availability, or
-- Entitlement), idempotency, and public visibility; Unpublish (idempotent,
-- configuration preserved, public reads and new requests stop, existing
-- REQUESTED and CONFIRMED Appointments untouched and still operable, no
-- Communication created by the unpublication, republish restores
-- visibility); the role matrix with nothing written on denial; the fail-closed
-- order (28000, then one 42501 for unknown and inaccessible Clinics whatever
-- the input, then 22023/23514/BR-56 only for authorized callers); and that
-- the writes still lock Organization and Clinic.
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

-- The complete observable outcome of a statement, run in a subtransaction
-- so that a succeeding write is undone.
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

-- Fires deferred constraint triggers (publication integrity, timezone
-- dependency) inside the transaction.
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c1900000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c1900000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.act_anonymous() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true);
$$;
create function pg_temp.org(p_n integer) returns uuid language sql immutable as $$
    select ('c1900000-0000-4000-8000-0000000003' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c1900000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.pet(p_n integer) returns uuid language sql immutable as $$
    select ('c1900000-0000-4000-8000-000000000a' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.timezone_sql(p_clinic uuid, p_timezone text) returns text language sql immutable as $$
    select format('select public.set_clinic_scheduling_timezone(%L, %L)', p_clinic, p_timezone)
$$;
create function pg_temp.publish_sql(p_clinic uuid) returns text language sql immutable as $$
    select format('select public.publish_clinic(%L)', p_clinic)
$$;
create function pg_temp.unpublish_sql(p_clinic uuid) returns text language sql immutable as $$
    select format('select public.unpublish_clinic(%L)', p_clinic)
$$;

-- All self-service configuration of this suite's Clinics (publication,
-- timezone, duration, revision, profile, location, Availability, Opening
-- Hours, Service Offerings).
create function pg_temp.configuration(p_clinic uuid) returns text language sql as $$
    select concat_ws('|',
        (select format('%s/%s/%s/%s', is_published, scheduling_timezone_name,
                       standard_appointment_duration_minutes, weekly_appointment_availability_revision)
         from public.clinics where id = p_clinic),
        (select to_jsonb(profile)::text from public.clinic_public_profiles as profile where clinic_id = p_clinic),
        (select to_jsonb(location)::text from public.clinic_locations as location where clinic_id = p_clinic),
        (select string_agg(to_jsonb(period)::text, ',' order by period.iso_weekday, period.start_time)
         from public.clinic_appointment_availability_periods as period where clinic_id = p_clinic),
        (select string_agg(to_jsonb(exception_record)::text, ',' order by exception_record.local_date)
         from public.clinic_appointment_availability_exceptions as exception_record where clinic_id = p_clinic),
        (select string_agg(to_jsonb(period)::text, ',' order by period.iso_weekday, period.start_time)
         from public.clinic_opening_periods as period where clinic_id = p_clinic),
        (select string_agg(to_jsonb(offering)::text, ',' order by offering.service_category)
         from public.clinic_service_offerings as offering where clinic_id = p_clinic))
$$;

-- Every row of every Appointment, Care Authorization, Reschedule Proposal,
-- and Communication table, so "Unpublish touches none of them" is checked
-- without depending on individual table names.
create function pg_temp.appointment_world() returns text language plpgsql as $$
declare
    table_name text;
    piece text;
    result text := '';
begin
    for table_name in
        select relname from pg_class
        where relnamespace = 'public'::regnamespace and relkind = 'r'
          and (relname like 'appointment%' or relname like 'care_authorization%'
               or relname like '%reschedule%' or relname like 'communication%')
        order by relname
    loop
        execute format('select coalesce(string_agg(md5(to_jsonb(t)::text), '','' order by md5(to_jsonb(t)::text)), '''') from public.%I as t', table_name)
        into piece;
        result := result || table_name || ':' || piece || ';';
    end loop;
    return md5(result);
end;
$$;

create function pg_temp.row_count(p_table_prefix text) returns bigint language plpgsql as $$
declare
    table_name text;
    total bigint := 0;
    counted bigint;
begin
    for table_name in
        select relname from pg_class
        where relnamespace = 'public'::regnamespace and relkind = 'r' and relname like p_table_prefix || '%'
    loop
        execute format('select count(*) from public.%I', table_name) into counted;
        total := total + counted;
    end loop;
    return total;
end;
$$;

create function pg_temp.publicly_visible(p_clinic uuid) returns text language sql as $$
    select concat_ws('/',
        exists (select 1 from public.published_clinic_public_profiles where clinic_id = p_clinic),
        exists (select 1 from public.get_published_clinic_location(p_clinic)),
        exists (
            select 1
            from jsonb_array_elements(public.discover_nearby_clinics(40.4168, -3.7038, 5000) -> 'clinics') as row_item
            where row_item ->> 'clinic_id' = p_clinic::text),
        exists (
            select 1
            from jsonb_array_elements(public.discover_clinics_in_viewport(40.3, 40.5, -3.8, -3.6) -> 'clinics') as row_item
            where row_item ->> 'clinic_id' = p_clinic::text))
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c1900000-…-0000000001NN, domain Users …-0000000002NN:
--   01 no Membership                    09 ADMINISTRATOR @ A2 (Clinic)
--   04 OrgA OWNER                       10 VETERINARIAN OrgA, current Assignment @ A1
--   05 OrgA Org ADMINISTRATOR           11 OrgA Org ADMINISTRATOR, Membership ended
--   06 ADMINISTRATOR @ A1 (Clinic)      12 OrgA Org ADMINISTRATOR, Grant ended
--   07 OrgA Org RECEPTIONIST            14 OrgB OWNER
--   08 RECEPTIONIST @ A1 (Clinic)       16 authentication subject without a domain User
--   18 OWNER of L1 (lock evidence)      20 Guardian of Pets a01–a03
-- Organizations: 0301 OrgA with an ACTIVE Subscription (APPOINTMENT_MANAGEMENT
-- and PROFESSIONAL_SCHEDULING) — A1 (0401) unpublished, fully configured for
-- Appointments (name, Madrid location, UTC, 30 min, weekly 09:00–17:00 every
-- day, Opening Hours, a Service); A2 (0402) unpublished and empty; A3 (0403)
-- unpublished with name and location but no timezone. 0302 OrgB with no
-- Subscription — B1 (0405) with weekly Availability in Europe/Madrid (BR-56
-- gated), B2 (0406) with a timezone and no Availability (ungated). 0311 L1 —
-- 0411.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('c1900000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 18, 20]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c1900000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 18, 20]) as n;

insert into public.veterinary_organizations (id, display_name)
select pg_temp.org(n), 'Clinic self-service C Org ' || n
from unnest(array[1, 2, 11]) as n;

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes) values
    (pg_temp.clinic(1), pg_temp.org(1), false, 'UTC', 30),
    (pg_temp.clinic(2), pg_temp.org(1), false, null, null),
    (pg_temp.clinic(3), pg_temp.org(1), false, null, null),
    (pg_temp.clinic(5), pg_temp.org(2), false, 'Europe/Madrid', 30),
    (pg_temp.clinic(6), pg_temp.org(2), false, 'Europe/Madrid', null),
    (pg_temp.clinic(11), pg_temp.org(11), false, null, null);

insert into public.clinic_public_profiles (clinic_id, display_name, description, public_phone, public_email, website) values
    (pg_temp.clinic(1), 'Animalia Madrid Centro', 'Centro', '+34 910 000 001', null, null),
    (pg_temp.clinic(3), 'Animalia Getafe', null, null, null, null),
    (pg_temp.clinic(5), 'VetCare Madrid', null, null, null, null);
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    (pg_temp.clinic(1), 'Calle Mayor 1, Madrid', 40.4168, -3.7038),
    (pg_temp.clinic(3), 'Avenida de España 2, Getafe', 40.3057, -3.7329),
    (pg_temp.clinic(5), 'Gran Vía 10, Madrid', 40.42, -3.705);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(1), weekday, '09:00', '17:00' from generate_series(1, 7) as weekday;
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(5), 1, '09:00', '13:00');
insert into public.clinic_opening_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(1), 1, '08:00', '20:00');
insert into public.clinic_service_offerings (clinic_id, service_category, public_description) values
    (pg_temp.clinic(1), 'VACCINATION', 'Vacunas');

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select ('c1900000-0000-4000-8000-0000000005' || lpad(member.n::text, 2, '0'))::uuid, pg_temp.org(member.org_n),
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
select ('c1900000-0000-4000-8000-0000000006' || lpad(grant_row.n::text, 2, '0'))::uuid,
       ('c1900000-0000-4000-8000-0000000005' || lpad(grant_row.n::text, 2, '0'))::uuid,
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
    ('c1900000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('c1900000-0000-4000-8000-000000000810', 'c1900000-0000-4000-8000-000000000710',
     'c1900000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z', null);

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('c1900000-0000-4000-8000-000000000901', pg_temp.org(1), '2020-01-01Z', 'ACTIVE', '2020-01-01Z',
     null, null, 'clinic-self-service-c-suite', 'c1900000-0000-4000-8000-000000000991');

insert into public.pets (id, name, species, created_at)
select pg_temp.pet(n), 'Mascota ' || n, 'Dog', '2020-01-01Z' from unnest(array[1, 2, 3]) as n;
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end)
select ('c1900000-0000-4000-8000-000000000b' || lpad(n::text, 2, '0'))::uuid, pg_temp.domain_user(20),
       pg_temp.pet(n), '2020-01-01Z', null
from unnest(array[1, 2, 3]) as n;

set local session_replication_role = origin;

select pg_temp.assert_true(
    public.organization_has_professional_entitlement(pg_temp.org(1), 'APPOINTMENT_MANAGEMENT')
    and public.organization_has_professional_entitlement(pg_temp.org(1), 'PROFESSIONAL_SCHEDULING')
    and not public.organization_has_professional_entitlement(pg_temp.org(2), 'PROFESSIONAL_SCHEDULING'),
    'Fixture: OrgA holds the professional Entitlements; OrgB holds none'
);

-- ===========================================================================
-- 1. Contract
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(
                proc.prosecdef
                and proc.proconfig = array['search_path=""']
                and pg_get_function_result(proc.oid) = 'uuid'
                and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                and not has_function_privilege('anon', proc.oid, 'EXECUTE')
                and not exists (select 1 from aclexplode(proc.proacl) as acl
                                where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'))
     from pg_proc as proc
     where proc.oid in (
         'public.set_clinic_scheduling_timezone(uuid, text)'::regprocedure,
         'public.publish_clinic(uuid)'::regprocedure,
         'public.unpublish_clinic(uuid)'::regprocedure))
    and (select count(*) = 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'unpublish_clinic'),
    'Contract: set_clinic_scheduling_timezone, publish_clinic, unpublish_clinic — SECURITY DEFINER, empty search_path, uuid result, authenticated-only'
);

-- ===========================================================================
-- 2. Scheduling timezone
-- ===========================================================================

select pg_temp.act(4);
create temporary table a2_before as select pg_temp.configuration(pg_temp.clinic(2)) as value;

select public.set_clinic_scheduling_timezone(pg_temp.clinic(2), E' \tAtlantic/Canary\n');
select pg_temp.assert_true(
    (select scheduling_timezone_name = 'Atlantic/Canary' from public.clinics where id = pg_temp.clinic(2)),
    'Timezone: an authorized change stores the trimmed IANA name'
);

do $$
declare
    invalid text;
begin
    foreach invalid in array array['Mars/Olympus_Mons', '', '   ', 'UTC+01:00', 'europe/madrid'] loop
        perform pg_temp.assert_error(pg_temp.timezone_sql(pg_temp.clinic(2), invalid),
            '22023', 'must be a valid named timezone');
    end loop;
    perform pg_temp.assert_error(
        format('select public.set_clinic_scheduling_timezone(%L, null)', pg_temp.clinic(2)),
        '22023', 'must be a valid named timezone');
end;
$$;
select pg_temp.assert_true(
    (select scheduling_timezone_name = 'Atlantic/Canary' from public.clinics where id = pg_temp.clinic(2)),
    'Timezone: invalid, blank, offset-style, wrongly cased, and NULL values are rejected with 22023 — the timezone cannot be cleared — and nothing changes'
);

-- Last-write-wins.
select public.set_clinic_scheduling_timezone(pg_temp.clinic(2), 'Europe/Lisbon');
select pg_temp.act(5);
select public.set_clinic_scheduling_timezone(pg_temp.clinic(2), 'Europe/Madrid');
select pg_temp.assert_true(
    (select scheduling_timezone_name = 'Europe/Madrid' from public.clinics where id = pg_temp.clinic(2)),
    'Timezone: the later change wins, without stale detection'
);

-- BR-56: B1 has current Availability and OrgB lacks PROFESSIONAL_SCHEDULING.
select pg_temp.act(14);
create temporary table b1_before as select pg_temp.configuration(pg_temp.clinic(5)) as value;
select pg_temp.assert_error(pg_temp.timezone_sql(pg_temp.clinic(5), 'Europe/Lisbon'),
    '42501', 'Professional scheduling Entitlement is required');
select pg_temp.assert_true(
    pg_temp.configuration(pg_temp.clinic(5)) = (select value from b1_before),
    'Timezone (BR-56): with currently effective Availability and no PROFESSIONAL_SCHEDULING the change is denied and nothing — timezone or Availability — changes'
);
-- Validation precedes the BR-56 gate.
select pg_temp.assert_error(pg_temp.timezone_sql(pg_temp.clinic(5), 'Mars/Phobos'),
    '22023', 'must be a valid named timezone');
-- Ungated: B2 has no Availability.
select public.set_clinic_scheduling_timezone(pg_temp.clinic(6), 'Atlantic/Canary');
select pg_temp.assert_true(
    (select scheduling_timezone_name = 'Atlantic/Canary' from public.clinics where id = pg_temp.clinic(6)),
    'Timezone (BR-56): without currently effective Availability no Entitlement is needed'
);

-- Role matrix at A1: Owner, Organization Administrator, A1's Clinic
-- Administrator may; Receptionists (who manage Appointment hours), another
-- Clinic's Administrator, a Veterinarian, no Membership, ended Membership or
-- Grant, and another Organization's Owner may not, and nothing changes.
create temporary table a1_config_before as select pg_temp.configuration(pg_temp.clinic(1)) as value;
do $$
declare
    actor integer;
begin
    foreach actor in array array[4, 5, 6] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_true(
            pg_temp.outcome(pg_temp.timezone_sql(pg_temp.clinic(1), 'Europe/Madrid')) = 'SUCCEEDED',
            format('Timezone authorization: User %s may change A1', actor));
    end loop;
    foreach actor in array array[1, 7, 8, 9, 10, 11, 12, 14] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_error(pg_temp.timezone_sql(pg_temp.clinic(1), 'Europe/Madrid'),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.configuration(pg_temp.clinic(1)) = (select value from a1_config_before),
    'Timezone authorization: every denied caller (Receptionists included) writes nothing'
);

-- ===========================================================================
-- 3. Publish requirements (SPEC-CLI-003 BR-15)
-- ===========================================================================

select pg_temp.act(4);
-- A2 has a timezone but nothing else.
select pg_temp.assert_error(pg_temp.publish_sql(pg_temp.clinic(2)), '23514', 'requires a valid current Location');
select public.set_clinic_location(pg_temp.clinic(2), 'Calle Sol 3, Madrid', 40.417, -3.704);
select pg_temp.assert_error(pg_temp.publish_sql(pg_temp.clinic(2)), '23514', 'requires a valid public display name');
select public.set_clinic_public_profile(pg_temp.clinic(2), null, 'Sin nombre todavía', null, null, null);
select pg_temp.assert_error(pg_temp.publish_sql(pg_temp.clinic(2)), '23514', 'requires a valid public display name');
select pg_temp.assert_true(
    (select not is_published from public.clinics where id = pg_temp.clinic(2))
    and pg_temp.publicly_visible(pg_temp.clinic(2)) = 'f/f/f/f',
    'Publish: missing location, missing profile, or a profile without a display name are each rejected with 23514 and the Clinic stays unpublished and invisible'
);

select public.set_clinic_public_profile(pg_temp.clinic(2), 'Animalia Sol', 'Sin nombre todavía', null, null, null);
create temporary table a2_ready as select pg_temp.configuration(pg_temp.clinic(2)) as value;
select public.publish_clinic(pg_temp.clinic(2));
select pg_temp.flush();
select pg_temp.assert_true(
    (select is_published from public.clinics where id = pg_temp.clinic(2))
    and pg_temp.configuration(pg_temp.clinic(2))
        = replace((select value from a2_ready), 'f/Europe/Madrid', 't/Europe/Madrid'),
    'Publish: with a display name and a location the Clinic is published, and only the publication state changes'
);
select public.publish_clinic(pg_temp.clinic(2));
select pg_temp.flush();
select pg_temp.assert_true(
    (select is_published from public.clinics where id = pg_temp.clinic(2))
    and pg_temp.configuration(pg_temp.clinic(2))
        = replace((select value from a2_ready), 'f/Europe/Madrid', 't/Europe/Madrid'),
    'Publish: publishing an already published Clinic succeeds and changes nothing'
);
select pg_temp.act_anonymous();
select pg_temp.assert_true(
    pg_temp.publicly_visible(pg_temp.clinic(2)) = 't/t/t/t',
    'Publish: the published Clinic appears in the public profile view, the location read, nearby, and viewport Discovery'
);

-- Not required: timezone (A3), duration, Availability, Entitlement (B1).
select pg_temp.act(4);
select public.publish_clinic(pg_temp.clinic(3));
select pg_temp.act(14);
select public.publish_clinic(pg_temp.clinic(5));
select pg_temp.flush();
select pg_temp.assert_true(
    (select is_published and scheduling_timezone_name is null and standard_appointment_duration_minutes is null
     from public.clinics where id = pg_temp.clinic(3))
    and (select is_published from public.clinics where id = pg_temp.clinic(5))
    and not public.organization_has_professional_entitlement(pg_temp.org(2), 'APPOINTMENT_MANAGEMENT'),
    'Publish: a scheduling timezone, standard duration, Availability, and any professional Entitlement are not required (SPEC-CLI-003 BR-15)'
);

-- ===========================================================================
-- 4. Publication authorization and disclosure
-- ===========================================================================

create temporary table publication_denied_before as
select pg_temp.configuration(pg_temp.clinic(1)) as a1, pg_temp.configuration(pg_temp.clinic(3)) as a3;
do $$
declare
    actor integer;
begin
    -- A1 is unpublished and ready; A3 is published (and not administered by User 09).
    foreach actor in array array[1, 7, 8, 9, 10, 11, 12, 14] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_error(pg_temp.publish_sql(pg_temp.clinic(1)),
            '42501', 'Clinic publication-management capability is required');
        perform pg_temp.assert_error(pg_temp.unpublish_sql(pg_temp.clinic(3)),
            '42501', 'Clinic publication-management capability is required');
    end loop;
    foreach actor in array array[4, 5, 6] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_true(
            pg_temp.outcome(pg_temp.publish_sql(pg_temp.clinic(1))) = 'SUCCEEDED',
            format('Publication authorization: User %s may publish A1', actor));
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.configuration(pg_temp.clinic(1)) = (select a1 from publication_denied_before)
    and pg_temp.configuration(pg_temp.clinic(3)) = (select a3 from publication_denied_before),
    'Publication authorization: Receptionists, another Clinic''s Administrator, a Veterinarian, no Membership, ended Membership or Grant, and another Organization''s Owner are denied Publish and Unpublish with nothing changed; Owner and Administrators may publish'
);

-- Unauthenticated callers are rejected first.
do $$
declare
    statement text;
begin
    foreach statement in array array[
        pg_temp.publish_sql(pg_temp.clinic(1)), pg_temp.unpublish_sql(pg_temp.clinic(99)),
        pg_temp.timezone_sql(pg_temp.clinic(99), 'Mars/Phobos')
    ] loop
        perform pg_temp.act_anonymous();
        perform pg_temp.assert_error(statement, '28000', 'Authentication is required');
        perform pg_temp.act(16);
        perform pg_temp.assert_error(statement, '28000', 'No coherent domain User exists');
    end loop;
end;
$$;

-- Unknown and inaccessible Clinics are indistinguishable, and neither the
-- publication requirements, the timezone validity, nor BR-56 are disclosed
-- to a caller who may not manage the Clinic.
do $$
declare
    actor integer;
    target uuid;
    publication_denied text := '42501: Clinic publication-management capability is required';
    timezone_denied text := '42501: Applicable Clinic-management capability is required';
begin
    foreach actor in array array[14, 7, 1] loop
        perform pg_temp.act(actor);
        -- unknown, A1 (unpublished, ready), A2 (published), A4-equivalent
        -- without a location (B2 for OrgA callers, A2 for OrgB's Owner is
        -- covered by A-targets).
        foreach target in array array[pg_temp.clinic(99), pg_temp.clinic(1), pg_temp.clinic(2), pg_temp.clinic(6)] loop
            if actor = 14 and target = pg_temp.clinic(6) then
                continue; -- OrgB's Owner manages B2
            end if;
            perform pg_temp.assert_true(
                pg_temp.outcome(pg_temp.publish_sql(target)) = publication_denied
                and pg_temp.outcome(pg_temp.unpublish_sql(target)) = publication_denied
                and pg_temp.outcome(pg_temp.timezone_sql(target, 'Europe/Madrid')) = timezone_denied
                and pg_temp.outcome(pg_temp.timezone_sql(target, 'Mars/Phobos')) = timezone_denied,
                format('Disclosure: User %s, Clinic %s — Publish, Unpublish, and any timezone input get the same capability outcome', actor, target));
        end loop;
    end loop;
    -- B1 (gated by BR-56) and B2 (no location) for an OrgA caller.
    perform pg_temp.act(4);
    perform pg_temp.assert_true(
        pg_temp.outcome(pg_temp.timezone_sql(pg_temp.clinic(5), 'Europe/Lisbon')) = timezone_denied
        and pg_temp.outcome(pg_temp.publish_sql(pg_temp.clinic(6))) = publication_denied
        and pg_temp.outcome(pg_temp.publish_sql(pg_temp.clinic(99))) = publication_denied
        and pg_temp.outcome(pg_temp.unpublish_sql(pg_temp.clinic(99))) = publication_denied
        and pg_temp.outcome(pg_temp.timezone_sql(pg_temp.clinic(99), 'Europe/Madrid')) = timezone_denied,
        'Disclosure: neither BR-56 nor the missing location of another Organization''s Clinic is revealed, and an unknown Clinic is 42501 (not 23503) even for an Owner');
end;
$$;

-- ===========================================================================
-- 5. Unpublish, with existing Appointments
-- ===========================================================================

-- A1 is published; the Guardian requests two Appointments; the Clinic
-- confirms one.
select pg_temp.act(4);
select public.publish_clinic(pg_temp.clinic(1));
select pg_temp.flush();

create temporary table appointment_ids (label text primary key, id uuid not null);
select pg_temp.act(20);
insert into appointment_ids
select 'requested', public.request_appointment(pg_temp.pet(1), pg_temp.clinic(1), current_date + 10, '10:00', 0, 'Revisión', null);
insert into appointment_ids
select 'confirmed', public.request_appointment(pg_temp.pet(2), pg_temp.clinic(1), current_date + 11, '11:00', 0, 'Vacuna', null);
select pg_temp.flush();
select pg_temp.act(4);
select public.confirm_appointment((select id from appointment_ids where label = 'confirmed'), 1);
select pg_temp.flush();
select pg_temp.assert_true(
    (select array_agg(lifecycle_state order by lifecycle_state) from public.appointments
     where id in (select id from appointment_ids)) = array['CONFIRMED', 'REQUESTED'],
    'Fixture: one REQUESTED and one CONFIRMED Appointment exist at the published A1'
);

-- Unpublish changes only publication: configuration, Appointments, their
-- revisions, Care Authorizations, proposals, and Communications untouched;
-- no Communication is created.
create temporary table before_unpublish as
select pg_temp.configuration(pg_temp.clinic(1)) as configuration,
       pg_temp.appointment_world() as world,
       pg_temp.row_count('communication') as communications;
select public.unpublish_clinic(pg_temp.clinic(1));
select pg_temp.flush();
select pg_temp.assert_true(
    (select not is_published from public.clinics where id = pg_temp.clinic(1))
    and pg_temp.configuration(pg_temp.clinic(1))
        = replace((select configuration from before_unpublish), 't/UTC/30/', 'f/UTC/30/')
    and pg_temp.appointment_world() = (select world from before_unpublish)
    and pg_temp.row_count('communication') = (select communications from before_unpublish),
    'Unpublish: only the publication state changes — profile, location, timezone, duration, Availability, Opening Hours, Services, Appointments, revisions, Care Authorizations, proposals, and Communications are untouched, and no Communication is created'
);

select public.unpublish_clinic(pg_temp.clinic(1));
select pg_temp.flush();
select pg_temp.assert_true(
    (select not is_published from public.clinics where id = pg_temp.clinic(1))
    and pg_temp.appointment_world() = (select world from before_unpublish),
    'Unpublish: unpublishing an already unpublished Clinic succeeds and changes nothing'
);

-- Public reads and new requests stop.
select pg_temp.act_anonymous();
select pg_temp.assert_true(
    pg_temp.publicly_visible(pg_temp.clinic(1)) = 'f/f/f/f',
    'Unpublish: the Clinic disappears from the public profile view, the location read, nearby, and viewport Discovery'
);
select pg_temp.act(20);
select pg_temp.assert_true(
    (select count(*) = 0 from public.get_requestable_appointment_start_times(pg_temp.clinic(1), current_date + 1, current_date + 20)),
    'Unpublish: the Guardian candidate read returns no candidates'
);
select pg_temp.assert_error(
    format('select public.request_appointment(%L, %L, current_date + 12, %L, 0, %L, null)',
           pg_temp.pet(3), pg_temp.clinic(1), '10:00', 'Nueva'),
    '23514', 'require a published Clinic');

-- Existing Appointments stay operable for both sides.
select pg_temp.act(4);
select public.confirm_appointment(
    (select id from appointment_ids where label = 'requested'),
    (select max(revision_sequence) from public.appointment_schedule_revisions
     where appointment_id = (select id from appointment_ids where label = 'requested')));
select pg_temp.act(20);
select public.cancel_appointment((select id from appointment_ids where label = 'confirmed'), 'GUARDIAN', 'Ya no hace falta', null);
select pg_temp.flush();
select pg_temp.assert_true(
    (select lifecycle_state = 'CONFIRMED' from public.appointments where id = (select id from appointment_ids where label = 'requested'))
    and (select lifecycle_state = 'CANCELLED' from public.appointments where id = (select id from appointment_ids where label = 'confirmed')),
    'Unpublish: after unpublication the Clinic still confirms an existing REQUESTED Appointment and the Guardian still cancels an existing CONFIRMED one'
);

-- A timezone change does not rewrite existing Appointment history.
create temporary table world_before_timezone as select pg_temp.appointment_world() as value,
       pg_temp.configuration(pg_temp.clinic(1)) as configuration;
select pg_temp.act(4);
select public.set_clinic_scheduling_timezone(pg_temp.clinic(1), 'Europe/Madrid');
select pg_temp.flush();
select pg_temp.assert_true(
    pg_temp.appointment_world() = (select value from world_before_timezone)
    and (select location.address_text = 'Calle Mayor 1, Madrid' and location.latitude = 40.4168
         from public.clinic_locations as location where clinic_id = pg_temp.clinic(1))
    and pg_temp.configuration(pg_temp.clinic(1))
        = replace((select configuration from world_before_timezone), 'f/UTC/30/', 'f/Europe/Madrid/30/'),
    'Timezone: changing it rewrites no Appointment, revision, or snapshot and changes nothing but the timezone (Location, Availability, profile untouched)'
);

-- Republish restores public visibility.
select public.publish_clinic(pg_temp.clinic(1));
select pg_temp.flush();
select pg_temp.act_anonymous();
select pg_temp.assert_true(
    pg_temp.publicly_visible(pg_temp.clinic(1)) = 't/t/t/t',
    'Republish: the same Clinic, with its stored information, is public again'
);

-- ===========================================================================
-- 6. Writes keep their Organization -> Clinic locking
-- ===========================================================================

create function pg_temp.lock_marks(p_n integer) returns text language sql as $$
    select (select (xmax::text <> '0')::text from public.veterinary_organizations where id = pg_temp.org(p_n))
        || '/' || (select (xmax::text <> '0')::text from public.clinics where id = pg_temp.clinic(p_n))
$$;

select pg_temp.assert_true(pg_temp.lock_marks(11) = 'false/false', 'Locking: L1 carries no lock before the write');
select pg_temp.act(18);
select public.unpublish_clinic(pg_temp.clinic(11));
select pg_temp.assert_true(pg_temp.lock_marks(11) = 'true/true',
    'Locking: unpublish_clinic locks its Organization and Clinic rows even when there is nothing to change');

do $$ begin raise notice 'clinic_self_service_publication_timezone_spec_cli_003_apt_013.sql: all assertions passed'; end $$;

rollback;

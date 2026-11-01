-- Regression suite for Clinic self-service Phase 1, Slice A: the managed Clinic
-- configuration read get_managed_clinic_profile(uuid)
-- (20261023090000_managed_clinic_profile_read.sql; SPEC-CLI-007 BR-1–BR-6,
-- Verification Notes 1–14).
--
-- It pins: the exact payload for empty, partial, and complete configuration,
-- published and unpublished; that each of the four Clinic self-service
-- capabilities alone authorizes the read and no other capability does; the
-- allowed/denied role matrix; that a nonexistent Clinic is indistinguishable
-- from an inaccessible one; that no Entitlement is needed; Clinic isolation;
-- that the read is side-effect free, takes no Organization or Clinic row lock
-- (while a Clinic write still does), and is STABLE; and the ACL.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required to load a deterministic context with establishment
-- triggers bypassed, to read row-lock evidence, to substitute the capability
-- predicate in section 3, and to switch between impersonated Users.
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
        raise exception 'Expected SQLSTATE % (%), received %: %',
            p_expected_sqlstate, p_expected_message_fragment, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded: %', p_expected_sqlstate, p_statement;
end;
$$;

-- The complete observable outcome of a failing statement (SQLSTATE and
-- message), or 'SUCCEEDED'.
create function pg_temp.outcome(p_statement text) returns text language plpgsql as $$
begin
    execute p_statement;
    return 'SUCCEEDED';
exception when others then
    return sqlstate || ': ' || sqlerrm;
end;
$$;

create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c1700000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c1700000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.act_anonymous() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true);
$$;
create function pg_temp.org(p_n integer) returns uuid language sql immutable as $$
    select ('c1700000-0000-4000-8000-0000000003' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c1700000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.read_sql(p_clinic uuid) returns text language sql immutable as $$
    select format('select public.get_managed_clinic_profile(%L)', p_clinic)
$$;
create function pg_temp.read(p_clinic uuid) returns jsonb language plpgsql as $$
declare
    result jsonb;
begin
    execute pg_temp.read_sql(p_clinic) into result;
    return result;
end;
$$;

-- Every stored self-service value of the fixture Clinics, to prove reads
-- change nothing.
create function pg_temp.configuration_fingerprint() returns text language sql as $$
    select md5(concat_ws('|',
        (select string_agg(format('%s/%s/%s/%s/%s/%s', id, organization_id, is_published,
                                  scheduling_timezone_name, standard_appointment_duration_minutes,
                                  weekly_appointment_availability_revision), ',' order by id)
         from public.clinics where id::text like 'c1700000-%'),
        (select string_agg(format('%s/%s/%s/%s/%s/%s', clinic_id, display_name, description,
                                  public_phone, public_email, website), ',' order by clinic_id)
         from public.clinic_public_profiles where clinic_id::text like 'c1700000-%'),
        (select string_agg(format('%s/%s/%s/%s', clinic_id, address_text, latitude, longitude),
                           ',' order by clinic_id)
         from public.clinic_locations where clinic_id::text like 'c1700000-%')))
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c1700000-…-0000000001NN, domain Users …-0000000002NN:
--   01 no Membership                    09 ADMINISTRATOR @ A2 (Clinic)
--   04 OrgA OWNER                       10 VETERINARIAN OrgA, current Assignment @ A1
--   05 OrgA Org ADMINISTRATOR           11 OrgA Org ADMINISTRATOR, Membership ended
--   06 ADMINISTRATOR @ A1 (Clinic)      12 OrgA Org ADMINISTRATOR, Grant ended
--   07 OrgA Org RECEPTIONIST            14 OrgB OWNER
--   08 RECEPTIONIST @ A1 (Clinic)       16 authentication subject without a domain User
--   18 OWNER of L1, L2 (section 6 lock evidence) and L3 (section 5)
-- Organizations: 0301 OrgA ACTIVE Subscription — A1 (0401) published and
-- fully configured, A2 (0402) unpublished and empty, A3 (0403) unpublished
-- with a partial profile and a timezone, A4 (0404) unpublished with a display
-- name and a location but no timezone; 0302 OrgB without Subscription — B1
-- (0405) published; 0311 L1 — 0411 and 0312 L2 — 0412 (section 6 only);
-- 0313 L3 — 0413 (section 5 only).
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('c1700000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 18]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c1700000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 18]) as n;

insert into public.veterinary_organizations (id, display_name)
select pg_temp.org(n), 'Clinic self-service Org ' || n
from unnest(array[1, 2, 11, 12, 13]) as n;

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes) values
    (pg_temp.clinic(1), pg_temp.org(1), true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), pg_temp.org(1), false, null, null),
    (pg_temp.clinic(3), pg_temp.org(1), false, 'Atlantic/Canary', null),
    (pg_temp.clinic(4), pg_temp.org(1), false, null, null),
    (pg_temp.clinic(5), pg_temp.org(2), true, 'Europe/Lisbon', null),
    (pg_temp.clinic(11), pg_temp.org(11), false, null, null),
    (pg_temp.clinic(12), pg_temp.org(12), false, null, null),
    (pg_temp.clinic(13), pg_temp.org(13), false, null, null);

insert into public.clinic_public_profiles (clinic_id, display_name, description, public_phone, public_email, website) values
    (pg_temp.clinic(1), 'Animalia Madrid Centro', E'Línea uno\nLínea  dos — ñ', '+34 910 000 001',
     'centro@example.test', 'https://centro.example.test'),
    (pg_temp.clinic(3), null, 'Solo descripción', '+34 922 000 003', null, null),
    (pg_temp.clinic(4), 'Animalia Getafe', null, null, null, null),
    (pg_temp.clinic(5), 'VetCare Lisboa', null, null, null, 'https://vetcare.example.test');

insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    (pg_temp.clinic(1), 'Calle Mayor 1, 28013 Madrid', 40.4168, -3.7038),
    (pg_temp.clinic(4), 'Avenida de España 2, Getafe', 40.3057, -3.7329),
    (pg_temp.clinic(5), 'Rua Augusta 5, Lisboa', 38.7101, -9.1366);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select ('c1700000-0000-4000-8000-0000000005' || lpad(member.n::text, 2, '0'))::uuid, pg_temp.org(member.org_n),
       pg_temp.domain_user(member.user_n), '2020-01-01Z', member.ended,
       case when member.ended is null then null else pg_temp.domain_user(4) end
from (values
    (4, 1, 4, null::timestamptz), (5, 1, 5, null), (6, 1, 6, null), (7, 1, 7, null), (8, 1, 8, null),
    (9, 1, 9, null), (10, 1, 10, null), (11, 1, 11, '2021-01-01Z'), (12, 1, 12, null),
    (14, 2, 14, null), (61, 11, 18, null), (62, 12, 18, null), (63, 13, 18, null)
) as member (n, org_n, user_n, ended);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
)
select ('c1700000-0000-4000-8000-0000000006' || lpad(grant_row.n::text, 2, '0'))::uuid,
       ('c1700000-0000-4000-8000-0000000005' || lpad(grant_row.n::text, 2, '0'))::uuid,
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
    (61, 'OWNER', 'ORGANIZATION', null, null),
    (62, 'OWNER', 'ORGANIZATION', null, null),
    (63, 'OWNER', 'ORGANIZATION', null, null)
) as grant_row (n, responsibility, scope_type, clinic_id, ended);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('c1700000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('c1700000-0000-4000-8000-000000000810', 'c1700000-0000-4000-8000-000000000710',
     'c1700000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z', null);

-- Only OrgA holds a Subscription; OrgB and L1–L3 hold none.
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('c1700000-0000-4000-8000-000000000901', pg_temp.org(1), '2020-01-01Z', 'ACTIVE', '2020-01-01Z',
     null, null, 'clinic-self-service-suite', 'c1700000-0000-4000-8000-000000000991');

-- Configuration the read must NOT return (BR-6).
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(1), 1, '09:00', '13:00');
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.clinic(1), '2035-03-05', 'OPEN', '10:00', '12:00');
insert into public.clinic_opening_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(1), 1, '08:00', '20:00');
insert into public.clinic_service_offerings (clinic_id, service_category, public_description) values
    (pg_temp.clinic(1), 'VACCINATION', 'Vacunas');

set local session_replication_role = origin;

-- The expected payloads, as stored.
create function pg_temp.expected(p_n integer) returns jsonb language sql immutable as $$
    select case p_n
        when 1 then jsonb_build_object(
            'clinic_id', pg_temp.clinic(1),
            'is_published', true,
            'scheduling_timezone_name', 'Europe/Madrid',
            'public_profile', jsonb_build_object(
                'display_name', 'Animalia Madrid Centro',
                'description', E'Línea uno\nLínea  dos — ñ',
                'public_phone', '+34 910 000 001',
                'public_email', 'centro@example.test',
                'website', 'https://centro.example.test'),
            'location', jsonb_build_object(
                'address_text', 'Calle Mayor 1, 28013 Madrid',
                'latitude', 40.4168,
                'longitude', -3.7038))
        when 2 then jsonb_build_object(
            'clinic_id', pg_temp.clinic(2),
            'is_published', false,
            'scheduling_timezone_name', null,
            'public_profile', null,
            'location', null)
        when 3 then jsonb_build_object(
            'clinic_id', pg_temp.clinic(3),
            'is_published', false,
            'scheduling_timezone_name', 'Atlantic/Canary',
            'public_profile', jsonb_build_object(
                'display_name', null,
                'description', 'Solo descripción',
                'public_phone', '+34 922 000 003',
                'public_email', null,
                'website', null),
            'location', null)
        when 4 then jsonb_build_object(
            'clinic_id', pg_temp.clinic(4),
            'is_published', false,
            'scheduling_timezone_name', null,
            'public_profile', jsonb_build_object(
                'display_name', 'Animalia Getafe',
                'description', null,
                'public_phone', null,
                'public_email', null,
                'website', null),
            'location', jsonb_build_object(
                'address_text', 'Avenida de España 2, Getafe',
                'latitude', 40.3057,
                'longitude', -3.7329))
        when 5 then jsonb_build_object(
            'clinic_id', pg_temp.clinic(5),
            'is_published', true,
            'scheduling_timezone_name', 'Europe/Lisbon',
            'public_profile', jsonb_build_object(
                'display_name', 'VetCare Lisboa',
                'description', null,
                'public_phone', null,
                'public_email', null,
                'website', 'https://vetcare.example.test'),
            'location', jsonb_build_object(
                'address_text', 'Rua Augusta 5, Lisboa',
                'latitude', 38.7101,
                'longitude', -9.1366))
    end
$$;

-- ===========================================================================
-- 1. Contract
-- ===========================================================================

select pg_temp.assert_true(
    (select proc.prosecdef
            and proc.proconfig = array['search_path=""']
            and pg_get_function_arguments(proc.oid) = 'p_clinic_id uuid'
            and pg_get_function_result(proc.oid) = 'jsonb'
            and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
            and not has_function_privilege('anon', proc.oid, 'EXECUTE')
            and not exists (
                select 1 from aclexplode(proc.proacl) as acl
                where acl.grantee = 0 and acl.privilege_type = 'EXECUTE')
     from pg_proc as proc
     where proc.oid = to_regprocedure('public.get_managed_clinic_profile(uuid)'))
    and (select count(*) = 1 from pg_proc
         where pronamespace = 'public'::regnamespace and proname = 'get_managed_clinic_profile'),
    'Contract: get_managed_clinic_profile(p_clinic_id uuid) returns jsonb — one overload, SECURITY DEFINER, empty search_path, executable by authenticated only (not anon, not PUBLIC)'
);

select pg_temp.assert_true(
    not has_table_privilege('authenticated', 'public.clinics', 'SELECT')
    and not has_table_privilege('anon', 'public.clinics', 'SELECT')
    and not has_table_privilege('authenticated', 'public.clinic_public_profiles', 'SELECT')
    and not has_table_privilege('anon', 'public.clinic_public_profiles', 'SELECT')
    and not has_table_privilege('authenticated', 'public.clinic_locations', 'SELECT')
    and not has_table_privilege('anon', 'public.clinic_locations', 'SELECT'),
    'Contract: no direct table privilege on clinics, clinic_public_profiles, or clinic_locations'
);

-- ===========================================================================
-- 2. Exact payloads (BR-1, BR-6) — published and unpublished, empty,
--    partial, and complete configuration
-- ===========================================================================

select pg_temp.act(4);
select pg_temp.assert_true(pg_temp.read(pg_temp.clinic(1)) = pg_temp.expected(1),
    'Payload: published, complete Clinic — every value exactly as stored (multi-line and non-ASCII text preserved); no duration, Availability, Opening Hours, or Service Offerings');
select pg_temp.assert_true(pg_temp.read(pg_temp.clinic(2)) = pg_temp.expected(2),
    'Payload: unpublished, unconfigured Clinic — is_published false and timezone, public_profile, location null');
select pg_temp.assert_true(pg_temp.read(pg_temp.clinic(3)) = pg_temp.expected(3),
    'Payload: partial profile — absent display name and fields null, stored ones returned; missing location null; timezone present');
select pg_temp.assert_true(pg_temp.read(pg_temp.clinic(4)) = pg_temp.expected(4),
    'Payload: display name and location present, missing timezone null');

do $$
declare
    clinic_n integer;
    result jsonb;
begin
    foreach clinic_n in array array[1, 2, 3, 4] loop
        result := pg_temp.read(pg_temp.clinic(clinic_n));
        perform pg_temp.assert_true(
            (select array_agg(key order by key) from jsonb_object_keys(result) as key)
                = array['clinic_id', 'is_published', 'location', 'public_profile', 'scheduling_timezone_name']
            and jsonb_typeof(result -> 'is_published') = 'boolean'
            and (jsonb_typeof(result -> 'public_profile') = 'null'
                 or (select array_agg(key order by key) from jsonb_object_keys(result -> 'public_profile') as key)
                    = array['description', 'display_name', 'public_email', 'public_phone', 'website'])
            and (jsonb_typeof(result -> 'location') = 'null'
                 or ((select array_agg(key order by key) from jsonb_object_keys(result -> 'location') as key)
                        = array['address_text', 'latitude', 'longitude']
                     and jsonb_typeof(result -> 'location' -> 'latitude') = 'number'
                     and jsonb_typeof(result -> 'location' -> 'longitude') = 'number')),
            format('Payload keys: Clinic %s has exactly the five members (always present) and exact nested members', clinic_n));
    end loop;
end;
$$;

-- ===========================================================================
-- 3. Each Clinic self-service capability alone authorizes the read (BR-2)
-- ===========================================================================
-- Phase 1 roles hold the four capabilities together, so no real role can
-- isolate one. The authoritative predicate is substituted, inside this
-- rolled-back transaction, by one that grants exactly the capability named
-- in a transaction setting to User 01 (no Membership) at A1 only, and is
-- restored before section 4.

create temporary table capability_predicate_backup as
select pg_get_functiondef('public.user_has_clinic_capability(uuid, uuid, text)'::regprocedure) as definition;

create or replace function public.user_has_clinic_capability(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select p_user_id = 'c1700000-0000-4000-8000-000000000201'::uuid
       and p_clinic_id = 'c1700000-0000-4000-8000-000000000401'::uuid
       and p_capability = current_setting('clinic_self_service_test.only_capability', true)
$$;

do $$
declare
    capability text;
begin
    perform pg_temp.act(1);
    foreach capability in array array[
        'CLINIC_MANAGE_PUBLIC_PROFILE', 'CLINIC_MANAGE_LOCATION',
        'CLINIC_MANAGE_PUBLICATION', 'CLINIC_MANAGE_OPENING_HOURS'
    ] loop
        perform set_config('clinic_self_service_test.only_capability', capability, true);
        perform pg_temp.assert_true(pg_temp.read(pg_temp.clinic(1)) = pg_temp.expected(1),
            format('Capability: %s alone authorizes the full payload', capability));
        perform pg_temp.assert_error(pg_temp.read_sql(pg_temp.clinic(2)),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
    foreach capability in array array[
        'CLINIC_MANAGE_SERVICES', 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
        'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CONFIRM',
        'CLINICAL_CARE', 'ORGANIZATION_CREATE_CLINICS', 'NONE'
    ] loop
        perform set_config('clinic_self_service_test.only_capability', capability, true);
        perform pg_temp.assert_error(pg_temp.read_sql(pg_temp.clinic(1)),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
end;
$$;
select pg_temp.assert_true(true,
    'Capability: each of CLINIC_MANAGE_PUBLIC_PROFILE, _LOCATION, _PUBLICATION, _OPENING_HOURS alone authorizes the read, only for its Clinic; Services, Veterinarian-assignment, Appointment, clinical, and Organization capabilities do not');

do $$ begin execute (select definition from capability_predicate_backup); end $$;
drop table capability_predicate_backup;

select pg_temp.assert_true(
    public.user_has_clinic_capability(pg_temp.domain_user(4), pg_temp.clinic(1), 'CLINIC_MANAGE_LOCATION')
    and not public.user_has_clinic_capability(pg_temp.domain_user(1), pg_temp.clinic(1), 'CLINIC_MANAGE_LOCATION'),
    'Capability: the authoritative predicate is restored'
);

-- ===========================================================================
-- 4. Authorization matrix with real responsibilities (BR-2, BR-4)
-- ===========================================================================

do $$
declare
    actor integer;
begin
    -- Allowed at A1: Owner, Organization Administrator, A1's Clinic Administrator.
    foreach actor in array array[4, 5, 6] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_true(pg_temp.read(pg_temp.clinic(1)) = pg_temp.expected(1),
            format('Authorization: User %s reads A1', actor));
    end loop;
    -- Denied at A1: no Membership, Organization and Clinic Receptionists,
    -- another Clinic's Administrator, a Veterinarian with a current
    -- Assignment, an ended Membership, an ended Grant, another
    -- Organization's Owner.
    foreach actor in array array[1, 7, 8, 9, 10, 11, 12, 14] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_error(pg_temp.read_sql(pg_temp.clinic(1)),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
end;
$$;
select pg_temp.assert_true(true,
    'Authorization: Owner, Organization Administrator, and the Clinic''s own Administrator read it; no Membership, Receptionists (Organization and Clinic scope), another Clinic''s Administrator, a Veterinarian with a current Assignment, an ended Membership or Grant, and another Organization''s Owner are denied with 42501');

-- Clinic scope: A2's Clinic Administrator reads A2 (unpublished, empty) but not A1.
select pg_temp.act(9);
select pg_temp.assert_true(pg_temp.read(pg_temp.clinic(2)) = pg_temp.expected(2),
    'Authorization: a Clinic-scoped Administrator reads its own (unpublished) Clinic');

-- Unauthenticated: anonymous, and an authentication subject with no domain User.
select pg_temp.act_anonymous();
select pg_temp.assert_error(pg_temp.read_sql(pg_temp.clinic(1)), '28000', 'Authentication is required');
select pg_temp.act(16);
select pg_temp.assert_error(pg_temp.read_sql(pg_temp.clinic(1)), '28000', 'No coherent domain User exists');

-- Nonexistent and inaccessible are indistinguishable (BR-4): the complete
-- outcome (SQLSTATE and message) of reading an unknown Clinic equals that of
-- reading an existing inaccessible one — published (A1) or unpublished (A2) —
-- for an Owner, a Receptionist, and a User without Membership.
do $$
declare
    actor integer;
    unknown_outcome text;
begin
    foreach actor in array array[14, 7, 1] loop
        perform pg_temp.act(actor);
        unknown_outcome := pg_temp.outcome(pg_temp.read_sql(pg_temp.clinic(99)));
        perform pg_temp.assert_true(
            unknown_outcome = '42501: Applicable Clinic-management capability is required'
            and unknown_outcome = pg_temp.outcome(pg_temp.read_sql(pg_temp.clinic(1)))
            and unknown_outcome = pg_temp.outcome(pg_temp.read_sql(pg_temp.clinic(2))),
            format('Disclosure: for User %s an unknown Clinic and an inaccessible published or unpublished Clinic produce the identical outcome', actor));
    end loop;
    perform pg_temp.act(4);
    perform pg_temp.assert_true(
        pg_temp.outcome(pg_temp.read_sql(pg_temp.clinic(99)))
            = '42501: Applicable Clinic-management capability is required',
        'Disclosure: an Owner reading an unknown Clinic gets the same 42501');
end;
$$;

-- ===========================================================================
-- 5. No Entitlement, no publication requirement; isolation (BR-3, BR-6)
-- ===========================================================================

select pg_temp.act(14);
select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.org(2), 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement(pg_temp.org(2), 'PROFESSIONAL_SCHEDULING')
    and pg_temp.read(pg_temp.clinic(5)) = pg_temp.expected(5),
    'Entitlement: an Organization with no Subscription reads its published Clinic'
);

select pg_temp.act(18);
select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.org(13), 'APPOINTMENT_MANAGEMENT')
    and pg_temp.read(pg_temp.clinic(13)) = jsonb_build_object(
        'clinic_id', pg_temp.clinic(13), 'is_published', false,
        'scheduling_timezone_name', null, 'public_profile', null, 'location', null),
    'Entitlement and publication: an unpublished Clinic of an Organization with no Subscription is readable'
);

-- Isolation: each Clinic returns only its own values — never a sibling's
-- profile or location, even where its own are absent.
select pg_temp.act(5);
select pg_temp.assert_true(
    pg_temp.read(pg_temp.clinic(1)) = pg_temp.expected(1)
    and pg_temp.read(pg_temp.clinic(2)) = pg_temp.expected(2)
    and pg_temp.read(pg_temp.clinic(3)) = pg_temp.expected(3)
    and pg_temp.read(pg_temp.clinic(4)) = pg_temp.expected(4),
    'Isolation: an Organization Administrator reads each of four sibling Clinics exactly, with no profile or location borrowed from another Clinic'
);

-- Existing public reads are unaffected by this Slice.
select pg_temp.act_anonymous();
select pg_temp.assert_true(
    (select count(*) = 1 from public.get_published_clinic_location(pg_temp.clinic(1)))
    and (select count(*) = 0 from public.get_published_clinic_location(pg_temp.clinic(4))),
    'Compatibility: the public location read still returns only published Clinics'
);

-- ===========================================================================
-- 6. Side effects, locking, and volatility (BR-5)
-- ===========================================================================
-- Technique (as in professional_management_reads_baseline.sql): L1/L2 and
-- their Clinics were inserted in replica mode by this transaction and nothing
-- has locked or updated them since, so their xmax is 0; a row locked FOR
-- UPDATE by this transaction carries this transaction's id. One Organization
-- per call keeps each observation attributable. A Clinic write at L2
-- (set_clinic_scheduling_timezone, Organization -> Clinic locking) shows the
-- technique still reports the lock a write takes.

create function pg_temp.lock_marks(p_n integer) returns text language sql as $$
    select (select (xmax::text <> '0')::text from public.veterinary_organizations where id = pg_temp.org(p_n))
        || '/' || (select (xmax::text <> '0')::text from public.clinics where id = pg_temp.clinic(p_n))
$$;

select pg_temp.assert_true(
    pg_temp.lock_marks(11) = 'false/false' and pg_temp.lock_marks(12) = 'false/false',
    'Locking: before any call, the L1 and L2 Organization and Clinic rows carry no lock'
);

select pg_temp.act(18);
select pg_temp.assert_true(
    pg_temp.read(pg_temp.clinic(11)) ->> 'clinic_id' = pg_temp.clinic(11)::text
    and pg_temp.lock_marks(11) = 'false/false',
    'Locking: get_managed_clinic_profile returns its payload without locking the Organization or Clinic row'
);

select public.set_clinic_scheduling_timezone(pg_temp.clinic(12), 'Europe/Madrid');
select pg_temp.assert_true(
    pg_temp.lock_marks(12) = 'true/true',
    'Locking (control): a Clinic configuration write still locks its Organization and Clinic rows'
);

-- Reads change nothing: the stored configuration of every fixture Clinic is
-- identical before and after reading all of them as several Users.
create temporary table fingerprint_before as select pg_temp.configuration_fingerprint() as value;
do $$
declare
    actor integer;
    clinic_n integer;
begin
    foreach actor in array array[4, 5, 6] loop
        perform pg_temp.act(actor);
        foreach clinic_n in array array[1, 2, 3, 4] loop
            perform pg_temp.outcome(pg_temp.read_sql(pg_temp.clinic(clinic_n)));
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.configuration_fingerprint() = (select value from fingerprint_before),
    'Side effects: reading every Clinic as several Users leaves all stored configuration unchanged'
);

select pg_temp.assert_true(
    (select provolatile = 's' from pg_proc
     where oid = 'public.get_managed_clinic_profile(uuid)'::regprocedure),
    'Volatility: get_managed_clinic_profile is STABLE'
);

do $$ begin raise notice 'clinic_self_service_spec_cli_007.sql: all assertions passed'; end $$;

rollback;

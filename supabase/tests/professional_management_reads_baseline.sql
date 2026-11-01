-- Regression suite for the four Professional management reads. Written as
-- the baseline before their lock removal and updated deliberately by
-- 20261014090000_professional_management_reads_without_locking.sql (only
-- the unknown-resource contract and section 4 changed):
--
--   get_managed_clinic_appointment_availability(uuid)   APPOINTMENT_MANAGE_AVAILABILITY
--   get_managed_clinic_opening_hours(uuid)              CLINIC_MANAGE_OPENING_HOURS
--   get_managed_clinic_service_offerings(uuid)          CLINIC_MANAGE_SERVICES
--   get_managed_veterinarian_availability(uuid)         APPOINTMENT_MANAGE_AVAILABILITY
--                                                       (of the Assignment's Clinic)
--
-- It pins: who may read, the exact error contract of every denial (an
-- unknown Clinic or Assignment fails closed with the same 42501 as an
-- inaccessible one — no existence disclosure; before 20261014090000 it was
-- 23503, the Assignment one even before authorization), isolation of the
-- returned data, that no read needs an Entitlement, and — section 4 — that
-- no read takes an Organization or Clinic row lock (before 20261014090000
-- each took FOR UPDATE locks through assert_clinic_capability_after_lock)
-- and that each is STABLE, while the configuration writes still lock.
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
        raise exception 'Expected SQLSTATE % (%), received %: %',
            p_expected_sqlstate, p_expected_message_fragment, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded: %', p_expected_sqlstate, p_statement;
end;
$$;

create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('a7150000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'a7150000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.act_anonymous() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true);
$$;
create function pg_temp.org(p_n integer) returns uuid language sql immutable as $$
    select ('a7150000-0000-4000-8000-0000000003' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('a7150000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.assignment(p_n integer) returns uuid language sql immutable as $$
    select ('a7150000-0000-4000-8000-0000000008' || lpad(p_n::text, 2, '0'))::uuid
$$;

-- One statement per read, so a read can be named in a matrix.
create function pg_temp.read_sql(p_read text, p_target uuid) returns text language sql immutable as $$
    select case p_read
        when 'appointment_availability' then format('select * from public.get_managed_clinic_appointment_availability(%L)', p_target)
        when 'opening_hours' then format('select * from public.get_managed_clinic_opening_hours(%L)', p_target)
        when 'service_offerings' then format('select * from public.get_managed_clinic_service_offerings(%L)', p_target)
        when 'veterinarian_availability' then format('select * from public.get_managed_veterinarian_availability(%L)', p_target)
    end
$$;

-- The whole result of a read as JSON, as the currently impersonated User.
create function pg_temp.read_json(p_read text, p_target uuid) returns jsonb language plpgsql as $$
declare
    result jsonb;
begin
    execute format('select coalesce(jsonb_agg(to_jsonb(read_row)), ''[]''::jsonb) from (%s) as read_row',
                   pg_temp.read_sql(p_read, p_target))
    into result;
    return result;
end;
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects a7150000-…-0000000001NN, domain Users …-0000000002NN:
--   01 no Membership                   10 VETERINARIAN OrgA, current Assignment @ A1
--   04 OrgA OWNER                      11 OrgA Org ADMINISTRATOR, Membership ended
--   05 OrgA Org ADMINISTRATOR          12 OrgA Org ADMINISTRATOR, Grant ended
--   06 ADMINISTRATOR @ A1 (Clinic)     13 OrgB Org RECEPTIONIST
--   07 OrgA Org RECEPTIONIST           14 OrgB OWNER
--   08 RECEPTIONIST @ A1 (Clinic)      15 VETERINARIAN OrgA, current Assignment @ A2
--   09 ADMINISTRATOR @ A2 (Clinic)     17 VETERINARIAN OrgA, ended Assignment @ A1
--   18 OWNER of the four lock-evidence Organizations L1–L4 (section 4)
-- Organizations: 0301 OrgA ACTIVE — A1 (0401), A2 (0402); 0302 OrgB with
-- no Subscription — B1 (0403); 0311–0314 L1–L4, one Clinic each
-- (0411–0414), used only by section 4.
-- Veterinarian Clinic Assignments: 0810 (10 @ A1), 0815 (15 @ A2),
-- 0817 (17 @ A1, ended), 0814 (L4).
-- Every Clinic carries distinct configuration so isolation is observable.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('a7150000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('a7150000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18]) as n;

insert into public.veterinary_organizations (id, display_name)
select pg_temp.org(n), 'Management read Org ' || n
from unnest(array[1, 2, 11, 12, 13, 14, 15]) as n;

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes) values
    (pg_temp.clinic(1), pg_temp.org(1), false, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), pg_temp.org(1), false, 'Atlantic/Canary', 20),
    (pg_temp.clinic(3), pg_temp.org(2), false, 'Europe/Lisbon', 45),
    (pg_temp.clinic(11), pg_temp.org(11), false, 'Europe/Madrid', 30),
    (pg_temp.clinic(12), pg_temp.org(12), false, 'Europe/Madrid', 30),
    (pg_temp.clinic(13), pg_temp.org(13), false, 'Europe/Madrid', 30),
    (pg_temp.clinic(14), pg_temp.org(14), false, 'Europe/Madrid', 30),
    (pg_temp.clinic(15), pg_temp.org(15), false, 'Europe/Madrid', 30);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select ('a7150000-0000-4000-8000-0000000005' || lpad(member.n::text, 2, '0'))::uuid, pg_temp.org(member.org_n),
       pg_temp.domain_user(member.user_n), '2020-01-01Z', member.ended, case when member.ended is null then null else pg_temp.domain_user(4) end
from (values
    (4, 1, 4, null::timestamptz), (5, 1, 5, null), (6, 1, 6, null), (7, 1, 7, null), (8, 1, 8, null),
    (9, 1, 9, null), (10, 1, 10, null), (11, 1, 11, '2021-01-01Z'), (12, 1, 12, null), (13, 2, 13, null),
    (14, 2, 14, null), (15, 1, 15, null), (17, 1, 17, null),
    (61, 11, 18, null), (62, 12, 18, null), (63, 13, 18, null), (64, 14, 18, null), (65, 14, 10, null),
    (66, 15, 18, null)
) as member (n, org_n, user_n, ended);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
)
select ('a7150000-0000-4000-8000-0000000006' || lpad(grant_row.n::text, 2, '0'))::uuid,
       ('a7150000-0000-4000-8000-0000000005' || lpad(grant_row.n::text, 2, '0'))::uuid,
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
    (13, 'RECEPTIONIST', 'ORGANIZATION', null, null),
    (14, 'OWNER', 'ORGANIZATION', null, null),
    (15, 'VETERINARIAN', 'ORGANIZATION', null, null),
    (17, 'VETERINARIAN', 'ORGANIZATION', null, null),
    (61, 'OWNER', 'ORGANIZATION', null, null),
    (62, 'OWNER', 'ORGANIZATION', null, null),
    (63, 'OWNER', 'ORGANIZATION', null, null),
    (64, 'OWNER', 'ORGANIZATION', null, null),
    (65, 'VETERINARIAN', 'ORGANIZATION', null, null),
    (66, 'OWNER', 'ORGANIZATION', null, null)
) as grant_row (n, responsibility, scope_type, clinic_id, ended);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('a7150000-0000-4000-8000-000000000710', pg_temp.domain_user(10)),
    ('a7150000-0000-4000-8000-000000000715', pg_temp.domain_user(15)),
    ('a7150000-0000-4000-8000-000000000717', pg_temp.domain_user(17));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.assignment(10), 'a7150000-0000-4000-8000-000000000710', 'a7150000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z', null),
    (pg_temp.assignment(15), 'a7150000-0000-4000-8000-000000000715', 'a7150000-0000-4000-8000-000000000515', pg_temp.clinic(2), '2020-01-01Z', null),
    (pg_temp.assignment(17), 'a7150000-0000-4000-8000-000000000717', 'a7150000-0000-4000-8000-000000000517', pg_temp.clinic(1), '2020-01-01Z', '2021-01-01Z'),
    (pg_temp.assignment(14), 'a7150000-0000-4000-8000-000000000710', 'a7150000-0000-4000-8000-000000000565', pg_temp.clinic(14), '2020-01-01Z', null);

-- OrgA and L5 hold a Subscription; OrgB and L1–L4 hold none (no read needs
-- one; L5's write in section 4 does).
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('a7150000-0000-4000-8000-000000000901', pg_temp.org(1), '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null, 'management-read-baseline', 'a7150000-0000-4000-8000-000000000991'),
    ('a7150000-0000-4000-8000-000000000915', pg_temp.org(15), '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null, 'management-read-baseline', 'a7150000-0000-4000-8000-000000000995');

-- Distinct configuration per Clinic (A1, A2, B1).
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(1), 1, '09:00', '13:00'),
    (pg_temp.clinic(2), 2, '10:00', '14:00'),
    (pg_temp.clinic(3), 3, '11:00', '15:00');
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.clinic(1), '2035-03-05', 'CLOSED', null, null),
    (pg_temp.clinic(2), '2035-03-06', 'OPEN', '08:00', '09:00');
insert into public.clinic_opening_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(1), 1, '08:00', '20:00'),
    (pg_temp.clinic(2), 2, '08:30', '19:30'),
    (pg_temp.clinic(3), 3, '07:00', '15:00');
insert into public.clinic_opening_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.clinic(1), '2035-03-05', 'OPEN', '10:00', '12:00'),
    (pg_temp.clinic(2), '2035-03-06', 'CLOSED', null, null);
insert into public.clinic_service_offerings (clinic_id, service_category, public_description) values
    (pg_temp.clinic(1), 'VACCINATION', 'Vacunas A1'),
    (pg_temp.clinic(1), 'GENERAL_CONSULTATION', null),
    (pg_temp.clinic(2), 'SURGERY', 'Cirugía A2'),
    (pg_temp.clinic(3), 'DENTISTRY', null);
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time) values
    (pg_temp.assignment(10), 1, '09:00', '12:00'),
    (pg_temp.assignment(15), 2, '15:00', '18:00'),
    (pg_temp.assignment(17), 4, '09:00', '10:00');
insert into public.veterinarian_availability_exceptions (veterinarian_clinic_assignment_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.assignment(10), '2035-03-05', 'OPEN', '10:00', '11:00'),
    (pg_temp.assignment(15), '2035-03-06', 'CLOSED', null, null);

set local session_replication_role = origin;

-- ===========================================================================
-- 1. Contract
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(
                proc.prosecdef
                and proc.proconfig = array['search_path=""']
                and pg_get_function_arguments(proc.oid) = expected.arguments
                and pg_get_function_result(proc.oid) = expected.result
                and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                and not has_function_privilege('anon', proc.oid, 'EXECUTE'))
     from (values
        ('public.get_managed_clinic_appointment_availability(uuid)', 'p_clinic_id uuid',
         'TABLE(scheduling_timezone_name text, standard_appointment_duration_minutes integer, recurring_periods jsonb, exceptions jsonb, weekly_appointment_availability_revision bigint)'),
        ('public.get_managed_clinic_opening_hours(uuid)', 'p_clinic_id uuid',
         'TABLE(scheduling_timezone_name text, recurring_periods jsonb, exceptions jsonb)'),
        ('public.get_managed_clinic_service_offerings(uuid)', 'p_clinic_id uuid',
         'TABLE(service_category text, public_description text)'),
        ('public.get_managed_veterinarian_availability(uuid)', 'p_veterinarian_clinic_assignment_id uuid',
         'TABLE(scheduling_timezone_name text, recurring_periods jsonb, exceptions jsonb)')
     ) as expected (signature, arguments, result)
     join pg_proc as proc on proc.oid = to_regprocedure(expected.signature)) is true
    and (select count(*) = 4 from pg_proc as proc
         where proc.pronamespace = 'public'::regnamespace
           and proc.proname in ('get_managed_clinic_appointment_availability', 'get_managed_clinic_opening_hours',
                                'get_managed_clinic_service_offerings', 'get_managed_veterinarian_availability')),
    'Contract: the four management reads — signatures, results, SECURITY DEFINER, empty search_path, authenticated-only'
);

-- ===========================================================================
-- 2. Authorization matrix (current error contracts preserved)
-- ===========================================================================
-- Allowed / denied actors per read, at A1 (for the Veterinarian read: the
-- current Assignment 0810 at A1). Receptionists hold
-- APPOINTMENT_MANAGE_AVAILABILITY but neither CLINIC_MANAGE_OPENING_HOURS nor
-- CLINIC_MANAGE_SERVICES; Veterinarians hold none of the three.

do $$
declare
    case_row record;
    actor integer;
    target uuid;
begin
    for case_row in
        select * from (values
            ('appointment_availability',  array[4, 5, 6, 7, 8],  array[1, 9, 10, 11, 12, 13, 14, 15, 17]),
            ('opening_hours',             array[4, 5, 6],        array[1, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17]),
            ('service_offerings',         array[4, 5, 6],        array[1, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17]),
            ('veterinarian_availability', array[4, 5, 6, 7, 8],  array[1, 9, 10, 11, 12, 13, 14, 15, 17])
        ) as matrix (read_name, allowed, denied)
    loop
        target := case when case_row.read_name = 'veterinarian_availability'
                       then pg_temp.assignment(10) else pg_temp.clinic(1) end;
        foreach actor in array case_row.allowed loop
            perform pg_temp.act(actor);
            perform pg_temp.assert_true(
                jsonb_array_length(pg_temp.read_json(case_row.read_name, target)) >= 1,
                format('Authorization: %s is allowed for User %s', case_row.read_name, actor));
        end loop;
        foreach actor in array case_row.denied loop
            perform pg_temp.act(actor);
            perform pg_temp.assert_error(pg_temp.read_sql(case_row.read_name, target),
                '42501', 'Applicable Clinic-management capability is required');
        end loop;
        perform pg_temp.act_anonymous();
        perform pg_temp.assert_error(pg_temp.read_sql(case_row.read_name, target),
            '28000', 'Authentication is required');
    end loop;
end;
$$;
select pg_temp.assert_true(true,
    'Authorization: every read allows exactly its capability holders (Owner, Org/Clinic Administrator, and Receptionists only for APPOINTMENT_MANAGE_AVAILABILITY) and denies no Membership, another Clinic''s Administrator, Veterinarians (current, other-Clinic, ended Assignment), an ended Membership or Grant, another Organization''s Receptionist and Owner (42501), and anonymous callers (28000)');

-- Scope is the requested Clinic: A2's Clinic Administrator reads A2 (and
-- the Veterinarian read of an Assignment at A2), A1's Clinic Receptionist
-- does not.
select pg_temp.act(9);
select pg_temp.assert_true(
    jsonb_array_length(pg_temp.read_json('appointment_availability', pg_temp.clinic(2))) = 1
    and jsonb_array_length(pg_temp.read_json('opening_hours', pg_temp.clinic(2))) = 1
    and jsonb_array_length(pg_temp.read_json('service_offerings', pg_temp.clinic(2))) = 1
    and jsonb_array_length(pg_temp.read_json('veterinarian_availability', pg_temp.assignment(15))) = 1,
    'Authorization: a Clinic-scoped Administrator reads its own Clinic with every read'
);
select pg_temp.act(8);
select pg_temp.assert_error(pg_temp.read_sql('appointment_availability', pg_temp.clinic(2)),
    '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error(pg_temp.read_sql('veterinarian_availability', pg_temp.assignment(15)),
    '42501', 'Applicable Clinic-management capability is required');

-- Unknown resources fail closed: the same 42501 and message as an
-- inaccessible one, for an Owner and for a User with no Membership alike,
-- so no caller can tell an existing Clinic or Assignment from an unknown one.
do $$
declare
    read_name text;
    actor integer;
begin
    foreach actor in array array[4, 1] loop
        perform pg_temp.act(actor);
        foreach read_name in array array['appointment_availability', 'opening_hours', 'service_offerings'] loop
            perform pg_temp.assert_error(pg_temp.read_sql(read_name, pg_temp.clinic(99)),
                '42501', 'Applicable Clinic-management capability is required');
        end loop;
        perform pg_temp.assert_error(pg_temp.read_sql('veterinarian_availability', pg_temp.assignment(99)),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
end;
$$;
select pg_temp.assert_true(true,
    'Unknown resources: an unknown Clinic or Assignment is denied with the generic 42501 capability error, identical to an inaccessible one (no existence disclosure)');

-- No Entitlement is needed by any read: OrgB has no Subscription.
select pg_temp.act(14);
select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.org(2), 'PROFESSIONAL_SCHEDULING')
    and jsonb_array_length(pg_temp.read_json('appointment_availability', pg_temp.clinic(3))) = 1
    and jsonb_array_length(pg_temp.read_json('opening_hours', pg_temp.clinic(3))) = 1
    and jsonb_array_length(pg_temp.read_json('service_offerings', pg_temp.clinic(3))) = 1,
    'Entitlement: the management reads need no Subscription Entitlement'
);

-- ===========================================================================
-- 3. Exact results and isolation
-- ===========================================================================

select pg_temp.act(4);
select pg_temp.assert_true(
    pg_temp.read_json('appointment_availability', pg_temp.clinic(1)) = '[{
        "scheduling_timezone_name": "Europe/Madrid",
        "standard_appointment_duration_minutes": 30,
        "recurring_periods": [{"iso_weekday": 1, "start_time": "09:00:00", "end_time": "13:00:00"}],
        "exceptions": [{"local_date": "2035-03-05", "exception_kind": "CLOSED", "start_time": null, "end_time": null}],
        "weekly_appointment_availability_revision": 0
    }]'::jsonb,
    'Isolation: the Appointment availability read of A1 returns exactly A1''s configuration'
);
select pg_temp.assert_true(
    pg_temp.read_json('opening_hours', pg_temp.clinic(1)) = '[{
        "scheduling_timezone_name": "Europe/Madrid",
        "recurring_periods": [{"iso_weekday": 1, "start_time": "08:00:00", "end_time": "20:00:00"}],
        "exceptions": [{"local_date": "2035-03-05", "exception_kind": "OPEN", "start_time": "10:00:00", "end_time": "12:00:00"}]
    }]'::jsonb
    and pg_temp.read_json('opening_hours', pg_temp.clinic(2)) = '[{
        "scheduling_timezone_name": "Atlantic/Canary",
        "recurring_periods": [{"iso_weekday": 2, "start_time": "08:30:00", "end_time": "19:30:00"}],
        "exceptions": [{"local_date": "2035-03-06", "exception_kind": "CLOSED", "start_time": null, "end_time": null}]
    }]'::jsonb,
    'Isolation: the Opening Hours read returns exactly the requested Clinic''s public hours, never another Clinic''s'
);
select pg_temp.assert_true(
    pg_temp.read_json('service_offerings', pg_temp.clinic(1)) = '[
        {"service_category": "GENERAL_CONSULTATION", "public_description": null},
        {"service_category": "VACCINATION", "public_description": "Vacunas A1"}
    ]'::jsonb
    and pg_temp.read_json('service_offerings', pg_temp.clinic(2))
        = '[{"service_category": "SURGERY", "public_description": "Cirugía A2"}]'::jsonb,
    'Isolation: the service offerings read returns exactly the requested Clinic''s offerings, ordered by category'
);
select pg_temp.assert_true(
    pg_temp.read_json('veterinarian_availability', pg_temp.assignment(10)) = '[{
        "scheduling_timezone_name": "Europe/Madrid",
        "recurring_periods": [{"iso_weekday": 1, "start_time": "09:00:00", "end_time": "12:00:00"}],
        "exceptions": [{"local_date": "2035-03-05", "exception_kind": "OPEN", "start_time": "10:00:00", "end_time": "11:00:00"}]
    }]'::jsonb
    and pg_temp.read_json('veterinarian_availability', pg_temp.assignment(15)) = '[{
        "scheduling_timezone_name": "Atlantic/Canary",
        "recurring_periods": [{"iso_weekday": 2, "start_time": "15:00:00", "end_time": "18:00:00"}],
        "exceptions": [{"local_date": "2035-03-06", "exception_kind": "CLOSED", "start_time": null, "end_time": null}]
    }]'::jsonb,
    'Isolation: the Veterinarian read returns exactly the requested Assignment''s Availability with its Clinic''s timezone — never another Veterinarian''s or another Clinic''s'
);
-- Ended Assignment: still readable by a capability holder of its Clinic,
-- returning its stored (ineffective) Availability — pinned current behaviour.
select pg_temp.assert_true(
    pg_temp.read_json('veterinarian_availability', pg_temp.assignment(17)) = '[{
        "scheduling_timezone_name": "Europe/Madrid",
        "recurring_periods": [{"iso_weekday": 4, "start_time": "09:00:00", "end_time": "10:00:00"}],
        "exceptions": []
    }]'::jsonb,
    'Veterinarian read: an ended Assignment''s stored Availability is still returned to a capability holder of its Clinic'
);

-- ===========================================================================
-- 4. Locking: the reads take no row lock; the writes still do
-- ===========================================================================
-- Technique: L1–L5 and their Clinics were inserted in replica mode by this
-- transaction and nothing has locked or updated them since, so their xmax
-- is 0. A row locked FOR UPDATE by this transaction has xmax set to this
-- transaction's id. Each call runs at top level (no subtransaction), one
-- per Organization, so every observation is independent and attributable
-- to exactly one RPC. The control read (get_clinic_appointment_schedule)
-- never locked; a configuration write at L5 shows the technique still
-- reports the lock a write takes. Before 20261014090000 each management
-- read set both marks to true.

create function pg_temp.lock_marks(p_n integer) returns text language sql as $$
    select (select (xmax::text <> '0')::text from public.veterinary_organizations where id = pg_temp.org(p_n))
        || '/' || (select (xmax::text <> '0')::text from public.clinics where id = pg_temp.clinic(p_n))
$$;

select pg_temp.assert_true(
    pg_temp.lock_marks(11) = 'false/false' and pg_temp.lock_marks(12) = 'false/false'
    and pg_temp.lock_marks(13) = 'false/false' and pg_temp.lock_marks(14) = 'false/false'
    and pg_temp.lock_marks(15) = 'false/false',
    'Locking: before any call, the L1–L5 Organization and Clinic rows carry no lock'
);

select pg_temp.act(18);
select count(*) from public.get_clinic_appointment_schedule(pg_temp.clinic(13));
select pg_temp.assert_true(
    pg_temp.lock_marks(13) = 'false/false',
    'Locking (control): get_clinic_appointment_schedule authorizes without locking the Organization or Clinic row'
);

select pg_temp.assert_true(
    (select count(*) = 1 from public.get_managed_clinic_appointment_availability(pg_temp.clinic(11)))
    and pg_temp.lock_marks(11) = 'false/false',
    'Locking: get_managed_clinic_appointment_availability returns its row without locking the Organization or Clinic row'
);
select pg_temp.assert_true(
    (select count(*) = 1 from public.get_managed_clinic_opening_hours(pg_temp.clinic(12)))
    and pg_temp.lock_marks(12) = 'false/false',
    'Locking: get_managed_clinic_opening_hours returns its row without locking the Organization or Clinic row'
);
select pg_temp.assert_true(
    (select count(*) = 0 from public.get_managed_clinic_service_offerings(pg_temp.clinic(13)))
    and pg_temp.lock_marks(13) = 'false/false',
    'Locking: get_managed_clinic_service_offerings answers (no offerings) without locking the Organization or Clinic row'
);
select pg_temp.assert_true(
    (select count(*) = 1 from public.get_managed_veterinarian_availability(pg_temp.assignment(14)))
    and pg_temp.lock_marks(14) = 'false/false'
    and (select xmax::text = '0' from public.veterinarian_clinic_assignments where id = pg_temp.assignment(14)),
    'Locking: get_managed_veterinarian_availability returns its row without locking the Organization, Clinic, or Assignment row'
);

-- The configuration writes keep their Organization -> Clinic locking.
select public.replace_clinic_appointment_availability(
    pg_temp.clinic(15), '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}]'::jsonb, 0);
select pg_temp.assert_true(
    pg_temp.lock_marks(15) = 'true/true'
    and (select xmax::text = (pg_current_xact_id()::text::bigint % 4294967296)::text
         from public.veterinary_organizations where id = pg_temp.org(15)),
    'Locking: a configuration write (replace_clinic_appointment_availability) still locks its Organization and Clinic rows for this transaction'
);

select pg_temp.assert_true(
    (select bool_and(proc.provolatile = 's')
     from pg_proc as proc
     where proc.oid in ('public.get_managed_clinic_appointment_availability(uuid)'::regprocedure,
                        'public.get_managed_clinic_opening_hours(uuid)'::regprocedure,
                        'public.get_managed_clinic_service_offerings(uuid)'::regprocedure,
                        'public.get_managed_veterinarian_availability(uuid)'::regprocedure,
                        'public.get_clinic_appointment_schedule(uuid)'::regprocedure)),
    'Volatility: the four management reads are STABLE, like the schedule read'
);

do $$ begin raise notice 'professional_management_reads_baseline.sql: all assertions passed'; end $$;

rollback;

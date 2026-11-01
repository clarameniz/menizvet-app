-- Regression suite for SPEC-APT-013 Clinic Appointment availability
-- management (BR-27, BR-37, BR-41, BR-43, BR-57–BR-64, BR-72–BR-75):
--
--   replace_clinic_appointment_availability(uuid, jsonb, bigint)
--     (stale-protected by 20261019090000_weekly_appointment_availability_revision.sql)
--   set_clinic_appointment_availability_exception(uuid, date, text, jsonb)
--   clear_clinic_appointment_availability_exception(uuid, date)
--   set_clinic_standard_appointment_duration(uuid, integer)
--   get_managed_clinic_appointment_availability(uuid)
--     (result extended by 20261013090000_clinic_appointment_hours_management_read.sql
--     and 20261019090000)
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables and internal
-- Availability helpers, and to switch between impersonated Users.
--
-- Every behavioral call goes through the real trusted operations. Helper
-- wrappers fire every pending deferred trigger at the end of each call (SET
-- CONSTRAINTS ALL IMMEDIATE, then back to DEFERRED), so the deferred overlap,
-- exception-coherence, and timezone-dependency constraints run inside the
-- same subtransaction as the call.
--
-- Concurrency: weekly replacement is stale-protected by the Clinic's weekly
-- availability revision (BR-75). Two editors are exercised serialized in one
-- session; that the revision is compared under the Clinic lock is shown here
-- by authorization preceding the stale check, and by a LOCAL two-session run
-- recorded in docs/IMPLEMENTATION_STATUS.md.
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
    select ('a7130000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'a7130000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.act_anonymous() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('a7130000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.appt(p_n integer) returns uuid language sql immutable as $$
    select ('a7130000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'a7130000-0000-4000-8000-000000000a01'::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

-- The stored weekly availability revision (superuser inspection).
create function pg_temp.revision_of(p_clinic uuid) returns bigint language sql as $$
    select weekly_appointment_availability_revision from public.clinics where id = p_clinic
$$;

-- Behavioral wrappers: the real RPC, then every deferred constraint.
-- replace_at submits an explicit expected weekly revision; replace is an
-- up-to-date editor (the current revision, 0 for an unknown Clinic).
create function pg_temp.replace_at(p_clinic uuid, p_periods text, p_revision bigint) returns void language plpgsql as $$
begin
    perform public.replace_clinic_appointment_availability(p_clinic, p_periods::jsonb, p_revision);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.replace(p_clinic uuid, p_periods text) returns void language plpgsql as $$
begin
    perform pg_temp.replace_at(p_clinic, p_periods, coalesce(pg_temp.revision_of(p_clinic), 0));
end;
$$;

create function pg_temp.set_exception(p_clinic uuid, p_date date, p_kind text, p_periods text)
returns void language plpgsql as $$
begin
    perform public.set_clinic_appointment_availability_exception(p_clinic, p_date, p_kind, p_periods::jsonb);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.clear_exception(p_clinic uuid, p_date date) returns void language plpgsql as $$
begin
    perform public.clear_clinic_appointment_availability_exception(p_clinic, p_date);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.set_duration(p_clinic uuid, p_minutes integer) returns void language plpgsql as $$
begin
    perform public.set_clinic_standard_appointment_duration(p_clinic, p_minutes);
    perform pg_temp.flush();
end;
$$;

-- The management read, as the currently impersonated User.
create function pg_temp.read_timezone(p_clinic uuid) returns text language sql as $$
    select scheduling_timezone_name from public.get_managed_clinic_appointment_availability(p_clinic)
$$;
create function pg_temp.read_duration(p_clinic uuid) returns integer language sql as $$
    select standard_appointment_duration_minutes from public.get_managed_clinic_appointment_availability(p_clinic)
$$;
create function pg_temp.read_periods(p_clinic uuid) returns jsonb language sql as $$
    select recurring_periods from public.get_managed_clinic_appointment_availability(p_clinic)
$$;
create function pg_temp.read_exceptions(p_clinic uuid) returns jsonb language sql as $$
    select exceptions from public.get_managed_clinic_appointment_availability(p_clinic)
$$;
create function pg_temp.read_revision(p_clinic uuid) returns bigint language sql as $$
    select weekly_appointment_availability_revision from public.get_managed_clinic_appointment_availability(p_clinic)
$$;

-- Effective covered civil ranges for a date, from the authoritative internal
-- helper every candidate read uses (superuser inspection).
create function pg_temp.ranges(p_clinic uuid, p_date date) returns text language sql as $$
    select coalesce(string_agg(covered.range_start::text || '-' || covered.range_end::text, ',' order by covered.range_start), '')
    from public.clinic_day_covered_civil_ranges(p_clinic, p_date) as covered
$$;

-- Every persisted Appointment-scheduling configuration fact for one Clinic.
create function pg_temp.config_fingerprint(p_clinic uuid) returns text language sql as $$
    select md5(
        coalesce((select clinic.scheduling_timezone_name || '|' || coalesce(clinic.standard_appointment_duration_minutes::text, 'null')
                  from public.clinics as clinic where clinic.id = p_clinic), '')
        || '#' || coalesce((select string_agg(period::text, '|' order by period.iso_weekday, period.start_time, period.end_time)
                  from public.clinic_appointment_availability_periods as period where period.clinic_id = p_clinic), '')
        || '#' || coalesce((select string_agg(
                      exception_record.local_date::text || exception_record.exception_kind
                      || coalesce(exception_record.start_time::text, '') || coalesce(exception_record.end_time::text, ''),
                      '|' order by exception_record.local_date, exception_record.start_time)
                  from public.clinic_appointment_availability_exceptions as exception_record
                  where exception_record.clinic_id = p_clinic), '')
    )
$$;

-- Every persisted Appointment scheduling fact a configuration change must
-- never touch: Appointments, Schedule Revisions, Reschedule Proposals,
-- Lifecycle Events.
create function pg_temp.appointment_fingerprint() returns text language sql as $$
    select md5(
        coalesce((select string_agg(appointment::text, '|' order by appointment.id)
                  from public.appointments as appointment), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.id)
                  from public.appointment_schedule_revisions as revision), '')
        || '#' || coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal), '')
        || '#' || coalesce((select string_agg(lifecycle_event::text, '|' order by lifecycle_event.id)
                  from public.appointment_lifecycle_events as lifecycle_event), '')
    )
$$;

create temporary table remembered (label text primary key, fingerprint text not null) on commit drop;

create function pg_temp.remember(p_label text, p_fingerprint text) returns void language sql as $$
    insert into remembered values (p_label, p_fingerprint)
    on conflict (label) do update set fingerprint = excluded.fingerprint
$$;

create function pg_temp.unchanged(p_label text, p_fingerprint text) returns boolean language sql as $$
    select p_fingerprint = fingerprint from remembered where label = p_label
$$;

-- ===========================================================================
-- 1. Contract
-- ===========================================================================

select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc as proc
     where proc.proname = 'get_managed_clinic_appointment_availability'
       and proc.pronamespace = 'public'::regnamespace)
    and (select pg_get_function_arguments(proc.oid) = 'p_clinic_id uuid'
                and pg_get_function_result(proc.oid)
                    = 'TABLE(scheduling_timezone_name text, standard_appointment_duration_minutes integer, recurring_periods jsonb, exceptions jsonb, weekly_appointment_availability_revision bigint)'
                and proc.prosecdef
                and proc.provolatile = 's'
                and proc.proconfig = array['search_path=""']
         from pg_proc as proc
         where proc.oid = 'public.get_managed_clinic_appointment_availability(uuid)'::regprocedure)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.oid = 'public.get_managed_clinic_appointment_availability(uuid)'::regprocedure
           and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.get_managed_clinic_appointment_availability(uuid)', 'EXECUTE'),
    'Contract: exactly one management read, (p_clinic_id uuid) -> TABLE(timezone, standard duration, recurring periods, exceptions, weekly revision), STABLE (non-locking, 20261014090000), SECURITY DEFINER, empty search_path, authenticated-only ACL'
);

select pg_temp.assert_true(
    to_regprocedure('public.replace_clinic_appointment_availability(uuid, jsonb)') is null
    and (select pg_get_constraintdef(oid) from pg_constraint
         where conname = 'clinics_weekly_appointment_availability_revision_check')
        = 'CHECK ((weekly_appointment_availability_revision >= 0))'
    and (select attnotnull and pg_get_expr(adbin, adrelid) = '0'
         from pg_attribute join pg_attrdef on adrelid = attrelid and adnum = attnum
         where attrelid = 'public.clinics'::regclass and attname = 'weekly_appointment_availability_revision'),
    'Contract: the two-argument weekly replacement is gone (no compatibility overload); clinics.weekly_appointment_availability_revision is NOT NULL, default 0, non-negative'
);

select pg_temp.assert_true(
    (select bool_and(
                (select count(*) = 1 from pg_proc as proc
                 where proc.proname = expected.name and proc.pronamespace = 'public'::regnamespace)
                and pg_get_function_arguments(to_regprocedure(expected.signature)) = expected.arguments
                and pg_get_function_result(to_regprocedure(expected.signature)) = 'uuid'
                and has_function_privilege('authenticated', expected.signature, 'EXECUTE')
                and not has_function_privilege('anon', expected.signature, 'EXECUTE'))
     from (values
        ('replace_clinic_appointment_availability',
         'public.replace_clinic_appointment_availability(uuid, jsonb, bigint)',
         'p_clinic_id uuid, p_periods jsonb, p_expected_weekly_availability_revision bigint'),
        ('set_clinic_appointment_availability_exception',
         'public.set_clinic_appointment_availability_exception(uuid, date, text, jsonb)',
         'p_clinic_id uuid, p_local_date date, p_exception_kind text, p_periods jsonb'),
        ('clear_clinic_appointment_availability_exception',
         'public.clear_clinic_appointment_availability_exception(uuid, date)',
         'p_clinic_id uuid, p_local_date date'),
        ('set_clinic_standard_appointment_duration',
         'public.set_clinic_standard_appointment_duration(uuid, integer)',
         'p_clinic_id uuid, p_duration_minutes integer')
     ) as expected (name, signature, arguments)),
    'Contract: the four write RPC signatures (weekly replacement with its expected revision), results, and ACLs'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects a7130000-…-0000000001NN, domain Users …-0000000002NN:
--   01 User with no Organization Membership (e.g. a Guardian)
--   04 OrgA OWNER                    09 RECEPTIONIST @ A2 (Clinic)
--   05 OrgA ADMINISTRATOR (Org)      10 VETERINARIAN, Clinic Assignment @ A1
--   06 ADMINISTRATOR @ A1 (Clinic)   11 Org RECEPTIONIST, Membership ended
--   07 OrgA RECEPTIONIST (Org)       12 Org RECEPTIONIST, Grant ended
--   08 RECEPTIONIST @ A1 (Clinic)    13 OrgB RECEPTIONIST (Org) — another Organization
--                                    14 ADMINISTRATOR @ A2 (Clinic)
--                                    16 OWNER of OrgB (PENDING) and OrgC (EXPIRED)
-- Organizations: 0301 OrgA ACTIVE — A1 (0401), A2 (0402), A3 (0403, no
-- timezone, no duration); 0303 OrgB PENDING — B1 (0404); 0305 OrgC
-- EXPIRED — C1 (0406).
-- Dates: 2035-03-04 Sunday, 2035-03-05 Monday, 2035-03-06 Tuesday,
-- 2035-03-11 Sunday, 2035-03-12 Monday.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('a7130000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('a7130000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('a7130000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('a7130000-0000-4000-8000-000000000303', 'Org Pending'),
    ('a7130000-0000-4000-8000-000000000305', 'Org Expired');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    (pg_temp.clinic(1), 'a7130000-0000-4000-8000-000000000301', false, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), 'a7130000-0000-4000-8000-000000000301', false, 'Atlantic/Canary', 20),
    (pg_temp.clinic(3), 'a7130000-0000-4000-8000-000000000301', false, null, null),
    (pg_temp.clinic(4), 'a7130000-0000-4000-8000-000000000303', false, 'Europe/Lisbon', 20),
    (pg_temp.clinic(6), 'a7130000-0000-4000-8000-000000000305', false, 'Europe/Madrid', 45);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('a7130000-0000-4000-8000-000000000504', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000505', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(5), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000506', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(6), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000507', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000508', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(8), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000509', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(9), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000510', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000511', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(11), '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4)),
    ('a7130000-0000-4000-8000-000000000512', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(12), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000513', 'a7130000-0000-4000-8000-000000000303', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000515', 'a7130000-0000-4000-8000-000000000305', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000517', 'a7130000-0000-4000-8000-000000000303', pg_temp.domain_user(13), '2020-01-01Z', null, null),
    ('a7130000-0000-4000-8000-000000000518', 'a7130000-0000-4000-8000-000000000301', pg_temp.domain_user(14), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('a7130000-0000-4000-8000-000000000604', 'a7130000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000605', 'a7130000-0000-4000-8000-000000000505', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000606', 'a7130000-0000-4000-8000-000000000506', 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000607', 'a7130000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000608', 'a7130000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000609', 'a7130000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000610', 'a7130000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000611', 'a7130000-0000-4000-8000-000000000511', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7130000-0000-4000-8000-000000000612', 'a7130000-0000-4000-8000-000000000512', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4), pg_temp.domain_user(4)),
    ('a7130000-0000-4000-8000-000000000613', 'a7130000-0000-4000-8000-000000000513', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('a7130000-0000-4000-8000-000000000615', 'a7130000-0000-4000-8000-000000000515', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('a7130000-0000-4000-8000-000000000617', 'a7130000-0000-4000-8000-000000000517', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('a7130000-0000-4000-8000-000000000618', 'a7130000-0000-4000-8000-000000000518', 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null);

insert into public.veterinarian_professional_profiles (id, user_id)
values ('a7130000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start
) values ('a7130000-0000-4000-8000-000000000810', 'a7130000-0000-4000-8000-000000000710',
          'a7130000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z');

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('a7130000-0000-4000-8000-000000000901', 'a7130000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',  '2020-01-01Z', null, null, 'spec-apt-013-test', 'a7130000-0000-4000-8000-000000000991'),
    ('a7130000-0000-4000-8000-000000000903', 'a7130000-0000-4000-8000-000000000303', '2020-01-01Z', 'PENDING', '2020-01-01Z', null, null, 'spec-apt-013-test', 'a7130000-0000-4000-8000-000000000993'),
    ('a7130000-0000-4000-8000-000000000905', 'a7130000-0000-4000-8000-000000000305', '2020-01-01Z', 'EXPIRED', '2020-01-01Z', null, null, 'spec-apt-013-test', 'a7130000-0000-4000-8000-000000000995');

-- B1 and C1 configuration established while their Organizations still held
-- PROFESSIONAL_SCHEDULING (loaded directly here).
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(4), 1, '09:00', '13:00'),
    (pg_temp.clinic(6), 3, '16:00', '19:00');
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.clinic(4), '2035-03-04', 'OPEN', '10:00', '12:00');

-- Existing Appointments at A1 (BR-29, BR-30, BR-63, BR-64, BR-70, BR-75):
--   b01 REQUESTED Monday 2035-03-05 10:00–10:30 Madrid (09:00Z–09:30Z);
--   b02 CONFIRMED Monday 2035-03-05 16:00–16:30 Madrid (15:00Z–15:30Z) with
--       a PENDING Clinic Reschedule Proposal for Tuesday 10:00 Madrid.
insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('a7130000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null);
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at) values
    (pg_temp.appt(1), pg_temp.luna(), pg_temp.clinic(1), pg_temp.domain_user(1), 'Vaccination', 'REQUESTED', '2026-01-01Z'),
    (pg_temp.appt(2), pg_temp.luna(), pg_temp.clinic(1), pg_temp.domain_user(1), 'Check-up', 'CONFIRMED', '2026-01-02Z');
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
) values
    (pg_temp.appt(1), 1, 'REQUESTED', '2035-03-05T09:00Z', '2035-03-05T09:30Z', 'Europe/Madrid', pg_temp.domain_user(1), null, '2026-01-01Z'),
    (pg_temp.appt(2), 1, 'REQUESTED', '2035-03-05T15:00Z', '2035-03-05T15:30Z', 'Europe/Madrid', pg_temp.domain_user(1), null, '2026-01-02Z'),
    (pg_temp.appt(2), 2, 'CONFIRMED', '2035-03-05T15:00Z', '2035-03-05T15:30Z', 'Europe/Madrid', pg_temp.domain_user(8), null, '2026-02-01Z');
insert into public.appointment_lifecycle_events (
    appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
) values (pg_temp.appt(2), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(8), 'CLINIC', null, '2026-02-01Z', '2026-02-01Z');
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
) select 'a7130000-0000-4000-8000-000000000d02', pg_temp.appt(2), revision.id, 'CONFIRMED',
         '2035-03-06T09:00Z', '2035-03-06T09:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(8),
         'Clinic needs to move it', '2026-03-01Z'
  from public.appointment_schedule_revisions as revision
  where revision.appointment_id = pg_temp.appt(2) and revision.revision_sequence = 2;

set local session_replication_role = origin;

select pg_temp.assert_true(
    extract(isodow from date '2035-03-04') = 7 and extract(isodow from date '2035-03-05') = 1
    and extract(isodow from date '2035-03-06') = 2 and extract(isodow from date '2035-03-11') = 7
    and extract(isodow from date '2035-03-12') = 1,
    'Fixture: fixed dates have the expected ISO weekdays'
);

select pg_temp.remember('appointments', pg_temp.appointment_fingerprint());

-- ===========================================================================
-- 2. Weekly replacement (BR-9, BR-41, BR-42, BR-75)
-- ===========================================================================

select pg_temp.act(4);

-- An existing Clinic starts at revision 0 (column default, no backfill).
select pg_temp.assert_true(pg_temp.read_revision(pg_temp.clinic(1)) = 0,
    'Revision: a Clinic whose week never changed reads revision 0');

-- One period.
select pg_temp.replace_at(pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}]', 0);
select pg_temp.assert_true(
    pg_temp.read_periods(pg_temp.clinic(1))
        = '[{"iso_weekday": 1, "start_time": "09:00:00", "end_time": "13:00:00"}]'::jsonb
    and pg_temp.read_revision(pg_temp.clinic(1)) = 1,
    'Weekly: one period is stored and read back exactly; the first real change makes revision 1'
);

-- Several weekdays, several periods per weekday, touching periods, a 24:00
-- end and second precision; read back ordered by weekday and start.
select pg_temp.replace_at(pg_temp.clinic(1), '[
    {"iso_weekday": 5, "start_time": "16:00", "end_time": "20:00"},
    {"iso_weekday": 1, "start_time": "16:00", "end_time": "20:00"},
    {"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"},
    {"iso_weekday": 2, "start_time": "13:00", "end_time": "14:00"},
    {"iso_weekday": 6, "start_time": "20:00", "end_time": "24:00"},
    {"iso_weekday": 3, "start_time": "08:30:15", "end_time": "12:45:30"}
]', 1);
select pg_temp.assert_true(pg_temp.read_revision(pg_temp.clinic(1)) = 2,
    'Revision: a second real change makes revision 2');
select pg_temp.assert_true(
    pg_temp.read_periods(pg_temp.clinic(1)) = '[
        {"iso_weekday": 1, "start_time": "09:00:00", "end_time": "13:00:00"},
        {"iso_weekday": 1, "start_time": "16:00:00", "end_time": "20:00:00"},
        {"iso_weekday": 2, "start_time": "09:00:00", "end_time": "13:00:00"},
        {"iso_weekday": 2, "start_time": "13:00:00", "end_time": "14:00:00"},
        {"iso_weekday": 3, "start_time": "08:30:15", "end_time": "12:45:30"},
        {"iso_weekday": 5, "start_time": "16:00:00", "end_time": "20:00:00"},
        {"iso_weekday": 6, "start_time": "20:00:00", "end_time": "24:00:00"}
    ]'::jsonb,
    'Weekly: multiple weekdays and periods, touching periods, 24:00 end, and second precision are stored exactly and read in weekday/start order'
);
select pg_temp.assert_true(
    pg_temp.ranges(pg_temp.clinic(1), '2035-03-06') = '09:00:00-14:00:00'
    and pg_temp.ranges(pg_temp.clinic(1), '2035-03-05') = '09:00:00-13:00:00,16:00:00-20:00:00'
    and pg_temp.ranges(pg_temp.clinic(1), '2035-03-04') = '',
    'Weekly: touching Tuesday periods cover one continuous range; Monday has two ranges; a weekday without periods is closed'
);

-- Full replacement: a later set removes every period it does not contain.
select pg_temp.replace(pg_temp.clinic(1), '[{"iso_weekday": 2, "start_time": "10:00", "end_time": "12:00"}]');
select pg_temp.assert_true(
    pg_temp.read_periods(pg_temp.clinic(1))
        = '[{"iso_weekday": 2, "start_time": "10:00:00", "end_time": "12:00:00"}]'::jsonb
    and (select count(*) = 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(1)),
    'Weekly: replacement is full-week — weekdays absent from the new set are removed'
);

-- Empty set clears.
select pg_temp.replace(pg_temp.clinic(1), '[]');
select pg_temp.assert_true(
    pg_temp.read_periods(pg_temp.clinic(1)) = '[]'::jsonb
    and not exists (select 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(1)),
    'Weekly: an empty set clears all recurring availability'
);

-- Working week for the remaining cases.
select pg_temp.replace(pg_temp.clinic(1), '[
    {"iso_weekday": 1, "start_time": "09:00", "end_time": "20:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"},
    {"iso_weekday": 2, "start_time": "16:00", "end_time": "20:00"}
]');
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));

-- Rejections leave the configuration unchanged.
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1),
           '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}, {"iso_weekday": 1, "start_time": "12:00", "end_time": "14:00"}]'),
    '23P01', 'must not overlap');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1),
           '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}, {"iso_weekday": 1, "start_time": "10:00", "end_time": "11:00"}]'),
    '23P01', 'must not overlap');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1),
           '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}, {"iso_weekday": 1, "start_time": "09:00:00", "end_time": "13:00"}]'),
    '23505', 'must not contain duplicates');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 0, "start_time": "09:00", "end_time": "13:00"}]'),
    '22023', 'ISO weekday must be between 1 and 7');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 8, "start_time": "09:00", "end_time": "13:00"}]'),
    '22023', 'ISO weekday must be between 1 and 7');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1.5, "start_time": "09:00", "end_time": "13:00"}]'),
    '22023', 'ISO weekday must be between 1 and 7');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": "1", "start_time": "09:00", "end_time": "13:00"}]'),
    '22023', 'requires valid iso_weekday, start_time, and end_time members');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "9:00", "end_time": "13:00"}]'),
    '22007', 'valid ISO local-time representation');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "25:00"}]'),
    '22007', 'valid ISO local-time representation');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "noon"}]'),
    '22007', 'valid ISO local-time representation');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "13:00", "end_time": "13:00"}]'),
    '22023', 'start_time before end_time');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "20:00", "end_time": "02:00"}]'),
    '22023', 'start_time before end_time');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00", "note": "x"}]'),
    '22023', 'unsupported member');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[{"iso_weekday": 1, "start_time": "09:00"}]'),
    '22023', 'requires valid iso_weekday, start_time, and end_time members');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}'),
    '22023', 'must be a JSON array');
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[1]'),
    '22023', 'must be a JSON object');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1))),
    'Weekly: every rejected replacement leaves the previous configuration intact'
);

-- Timezone required for non-empty availability (BR-43); empty is allowed.
select pg_temp.remember('a3', pg_temp.config_fingerprint(pg_temp.clinic(3)));
select pg_temp.assert_error(
    format('select pg_temp.replace(%L, %L)', pg_temp.clinic(3), '[{"iso_weekday": 1, "start_time": "09:00", "end_time": "13:00"}]'),
    '23514', 'requires a valid scheduling timezone');
select pg_temp.replace(pg_temp.clinic(3), '[]');
select pg_temp.assert_true(
    pg_temp.unchanged('a3', pg_temp.config_fingerprint(pg_temp.clinic(3))),
    'Weekly: a Clinic without a scheduling timezone rejects non-empty availability and accepts an empty set'
);

-- Clinic isolation (BR-3).
select pg_temp.replace(pg_temp.clinic(2), '[{"iso_weekday": 4, "start_time": "08:00", "end_time": "09:00"}]');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)))
    and pg_temp.read_periods(pg_temp.clinic(2))
        = '[{"iso_weekday": 4, "start_time": "08:00:00", "end_time": "09:00:00"}]'::jsonb,
    'Weekly: replacing one Clinic''s availability never touches another Clinic of the same Organization'
);

-- Two editors (BR-75): both read the same week at revision N. The first
-- saves a real change; the second, prepared from N, is rejected as stale and
-- changes nothing; after reviewing the current week it saves from N + 1.
create temporary table stale_editors (base bigint not null, after_first text not null) on commit drop;
select pg_temp.act(7);
insert into stale_editors (base, after_first) values (pg_temp.read_revision(pg_temp.clinic(1)), '');
select pg_temp.replace_at(pg_temp.clinic(1), '[
    {"iso_weekday": 1, "start_time": "09:00", "end_time": "20:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"},
    {"iso_weekday": 2, "start_time": "16:00", "end_time": "20:00"},
    {"iso_weekday": 4, "start_time": "09:00", "end_time": "13:00"}
]', (select base from stale_editors));
update stale_editors set after_first = pg_temp.config_fingerprint(pg_temp.clinic(1));
select pg_temp.assert_true(
    pg_temp.read_revision(pg_temp.clinic(1)) = (select base + 1 from stale_editors),
    'Stale: the first editor''s real change from revision N succeeds and makes N + 1');
select pg_temp.act(8);
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, %s)', pg_temp.clinic(1), '[
        {"iso_weekday": 1, "start_time": "09:00", "end_time": "20:00"},
        {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"},
        {"iso_weekday": 2, "start_time": "16:00", "end_time": "20:00"},
        {"iso_weekday": 5, "start_time": "09:00", "end_time": "13:00"}
    ]', (select base from stale_editors)),
    'P0001', 'Stale weekly Clinic Appointment Availability revision');
select pg_temp.assert_true(
    pg_temp.config_fingerprint(pg_temp.clinic(1)) = (select after_first from stale_editors)
    and exists (select 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(1) and iso_weekday = 4)
    and not exists (select 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(1) and iso_weekday = 5)
    and pg_temp.read_revision(pg_temp.clinic(1)) = (select base + 1 from stale_editors),
    'Stale: the second editor''s replacement from revision N is rejected; the first editor''s week and revision N + 1 stay exactly as they were');
-- A stale editor is told it is stale before its draft is validated.
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, %s)', pg_temp.clinic(1),
           '[{"iso_weekday": 9, "start_time": "09:00", "end_time": "13:00"}]', (select base from stale_editors)),
    'P0001', 'Stale weekly Clinic Appointment Availability revision');

-- Back to the working week, then an identical set in another order and
-- spelling: no write and no new revision.
select pg_temp.act(4);
select pg_temp.replace(pg_temp.clinic(1), '[
    {"iso_weekday": 1, "start_time": "09:00", "end_time": "20:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"},
    {"iso_weekday": 2, "start_time": "16:00", "end_time": "20:00"}
]');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1))),
    'Weekly: replacing with the same set is idempotent'
);
update stale_editors set base = pg_temp.read_revision(pg_temp.clinic(1));
select pg_temp.replace_at(pg_temp.clinic(1), '[
    {"iso_weekday": 2, "start_time": "16:00:00", "end_time": "20:00:00.000"},
    {"iso_weekday": 1, "start_time": "09:00:00", "end_time": "20:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00:00"}
]', (select base from stale_editors));
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)))
    and pg_temp.read_revision(pg_temp.clinic(1)) = (select base from stale_editors),
    'Revision: an identical week, in another order and time spelling, succeeds without a write or a new revision');

-- Unrelated configuration never changes the weekly revision: standard
-- duration, an exception set, changed, and cleared, and the timezone.
create temporary table unrelated (timezone_name text not null, duration integer) on commit drop;
insert into unrelated values (pg_temp.read_timezone(pg_temp.clinic(1)), pg_temp.read_duration(pg_temp.clinic(1)));
select pg_temp.set_duration(pg_temp.clinic(1), 45);
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-05', 'CLOSED', '[]');
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-05', 'OPEN', '[{"start_time": "10:00", "end_time": "12:00"}]');
select pg_temp.clear_exception(pg_temp.clinic(1), '2035-03-05');
select public.set_clinic_scheduling_timezone(pg_temp.clinic(1), 'Atlantic/Canary');
select pg_temp.flush();
select pg_temp.assert_true(
    pg_temp.read_revision(pg_temp.clinic(1)) = (select base from stale_editors)
    and pg_temp.read_timezone(pg_temp.clinic(1)) = 'Atlantic/Canary'
    and pg_temp.read_duration(pg_temp.clinic(1)) = 45,
    'Revision: duration, exception set/change/clear, and timezone changes leave the weekly revision unchanged');
select public.set_clinic_scheduling_timezone(pg_temp.clinic(1), (select timezone_name from unrelated));
select pg_temp.flush();
select pg_temp.set_duration(pg_temp.clinic(1), (select duration from unrelated));
-- So a weekly editor that read revision N before them still saves.
select pg_temp.replace_at(pg_temp.clinic(1), '[
    {"iso_weekday": 1, "start_time": "09:00", "end_time": "20:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"}
]', (select base from stale_editors));
select pg_temp.assert_true(
    pg_temp.read_revision(pg_temp.clinic(1)) = (select base + 1 from stale_editors),
    'Revision: a weekly save prepared before those changes is not stale, and its real change increments the revision once');
select pg_temp.replace(pg_temp.clinic(1), '[
    {"iso_weekday": 1, "start_time": "09:00", "end_time": "20:00"},
    {"iso_weekday": 2, "start_time": "09:00", "end_time": "13:00"},
    {"iso_weekday": 2, "start_time": "16:00", "end_time": "20:00"}
]');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1))),
    'Weekly: the working week is restored');

-- The expected revision is structural input: NULL and negative are 22023
-- before any Clinic state; nothing changes.
update stale_editors set base = pg_temp.read_revision(pg_temp.clinic(1));
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, null)', pg_temp.clinic(1), '[]'),
    '22023', 'Expected weekly Appointment Availability revision must be a non-negative integer');
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, -1)', pg_temp.clinic(1), '[]'),
    '22023', 'Expected weekly Appointment Availability revision must be a non-negative integer');
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, null)', pg_temp.clinic(99), '[]'),
    '22023', 'Expected weekly Appointment Availability revision must be a non-negative integer');
-- The revision is compared only after authorization under the Organization
-- -> Clinic lock: a caller without the capability, or for an unknown Clinic,
-- is denied as before even with an outdated revision.
select pg_temp.act(1);
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, 0)', pg_temp.clinic(1), '[]'),
    '42501', 'Applicable Appointment Availability-management capability is required');
select pg_temp.act(4);
select pg_temp.assert_error(
    format('select pg_temp.replace_at(%L, %L, 12345)', pg_temp.clinic(99), '[]'),
    '23503', 'Clinic does not exist');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)))
    and pg_temp.read_revision(pg_temp.clinic(1)) = (select base from stale_editors),
    'Revision: invalid tokens and denied calls change nothing');

-- ===========================================================================
-- 3. Exceptions (BR-10, BR-11, BR-73, BR-75)
-- ===========================================================================

-- OPEN on a normally closed Sunday.
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-04', 'OPEN', '[{"start_time": "10:00", "end_time": "13:00"}]');
select pg_temp.assert_true(
    pg_temp.ranges(pg_temp.clinic(1), '2035-03-04') = '10:00:00-13:00:00'
    and pg_temp.ranges(pg_temp.clinic(1), '2035-03-11') = ''
    and public.clinic_appointment_interval_is_available(pg_temp.clinic(1), '2035-03-04T09:00Z', '2035-03-04T09:30Z')
    and not exists (select 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(1) and iso_weekday = 7),
    'Exceptions: OPEN makes a normally closed Sunday bookable for that date only, without changing the recurring Sunday rule'
);

-- OPEN replaces a normally open Monday: partial-day closure from 14:00.
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-05', 'OPEN', '[{"start_time": "09:00", "end_time": "14:00"}]');
select pg_temp.assert_true(
    pg_temp.ranges(pg_temp.clinic(1), '2035-03-05') = '09:00:00-14:00:00'
    and pg_temp.ranges(pg_temp.clinic(1), '2035-03-12') = '09:00:00-20:00:00'
    and not public.clinic_appointment_interval_is_available(pg_temp.clinic(1), '2035-03-05T14:00Z', '2035-03-05T14:30Z'),
    'Exceptions: an OPEN exception replaces the whole recurring day — a partial-day closure is OPEN with the remaining hours'
);

-- Multiple OPEN periods, touching allowed.
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-06', 'OPEN',
    '[{"start_time": "16:00", "end_time": "18:00"}, {"start_time": "09:00", "end_time": "11:00"}, {"start_time": "11:00", "end_time": "12:00"}]');
select pg_temp.assert_true(
    pg_temp.ranges(pg_temp.clinic(1), '2035-03-06') = '09:00:00-12:00:00,16:00:00-18:00:00',
    'Exceptions: OPEN may carry several periods, touching periods included'
);

-- CLOSED.
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-12', 'CLOSED', '[]');
select pg_temp.assert_true(
    pg_temp.ranges(pg_temp.clinic(1), '2035-03-12') = ''
    and (select count(*) = 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(1) and iso_weekday = 1),
    'Exceptions: CLOSED removes all availability for that date and leaves the recurring Monday untouched'
);

-- Management read returns every exception exactly as stored, ordered.
select pg_temp.assert_true(
    pg_temp.read_exceptions(pg_temp.clinic(1)) = '[
        {"local_date": "2035-03-04", "exception_kind": "OPEN", "start_time": "10:00:00", "end_time": "13:00:00"},
        {"local_date": "2035-03-05", "exception_kind": "OPEN", "start_time": "09:00:00", "end_time": "14:00:00"},
        {"local_date": "2035-03-06", "exception_kind": "OPEN", "start_time": "09:00:00", "end_time": "11:00:00"},
        {"local_date": "2035-03-06", "exception_kind": "OPEN", "start_time": "11:00:00", "end_time": "12:00:00"},
        {"local_date": "2035-03-06", "exception_kind": "OPEN", "start_time": "16:00:00", "end_time": "18:00:00"},
        {"local_date": "2035-03-12", "exception_kind": "CLOSED", "start_time": null, "end_time": null}
    ]'::jsonb,
    'Exceptions: the management read returns each stored exception row by date and start'
);

-- Setting another exception on the same date replaces the first, both ways.
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-06', 'CLOSED', '[]');
select pg_temp.assert_true(
    (select array_agg(exception_kind) = array['CLOSED'] from public.clinic_appointment_availability_exceptions
     where clinic_id = pg_temp.clinic(1) and local_date = '2035-03-06')
    and pg_temp.ranges(pg_temp.clinic(1), '2035-03-06') = '',
    'Exceptions: CLOSED replaces an existing multi-period OPEN exception for the same date'
);
select pg_temp.assert_true(
    (select jsonb_agg(entry) from jsonb_array_elements(pg_temp.read_exceptions(pg_temp.clinic(1))) as entry
     where entry ->> 'local_date' = '2035-03-06')
        = '[{"local_date": "2035-03-06", "exception_kind": "CLOSED", "start_time": null, "end_time": null}]'::jsonb,
    'Exceptions: after OPEN then CLOSED (serialized, last write wins) the read shows exactly one CLOSED entry and no OPEN period for that date'
);
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-06', 'OPEN', '[{"start_time": "10:00", "end_time": "11:00"}]');
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-06', 'OPEN', '[{"start_time": "12:00", "end_time": "13:00"}]');
select pg_temp.assert_true(
    (select count(*) = 1 from public.clinic_appointment_availability_exceptions
     where clinic_id = pg_temp.clinic(1) and local_date = '2035-03-06')
    and pg_temp.ranges(pg_temp.clinic(1), '2035-03-06') = '12:00:00-13:00:00',
    'Exceptions: OPEN replaces CLOSED, and a later OPEN replaces an earlier OPEN entirely'
);

-- Clearing restores recurring availability; clearing is idempotent.
select pg_temp.clear_exception(pg_temp.clinic(1), '2035-03-06');
select pg_temp.assert_true(
    pg_temp.ranges(pg_temp.clinic(1), '2035-03-06') = '09:00:00-13:00:00,16:00:00-20:00:00'
    and not exists (select 1 from public.clinic_appointment_availability_exceptions
                    where clinic_id = pg_temp.clinic(1) and local_date = '2035-03-06'),
    'Exceptions: clearing restores the recurring Tuesday availability for that date'
);
select pg_temp.assert_true(
    not exists (select 1 from jsonb_array_elements(pg_temp.read_exceptions(pg_temp.clinic(1))) as entry
                where entry ->> 'local_date' = '2035-03-06')
    and public.clinic_appointment_interval_is_available(pg_temp.clinic(1), '2035-03-06T15:00Z', '2035-03-06T15:30Z')
    and not public.clinic_appointment_interval_is_available(pg_temp.clinic(1), '2035-03-06T12:00Z', '2035-03-06T12:30Z'),
    'Exceptions: after set then clear the read shows no entry for that date and the recurring rule is authoritative again (16:00 Madrid available, 13:00 not)'
);
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));
select pg_temp.clear_exception(pg_temp.clinic(1), '2035-03-06');
select pg_temp.clear_exception(pg_temp.clinic(1), '2040-01-01');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1))),
    'Exceptions: clearing an absent exception succeeds and changes nothing'
);

-- A past local date is accepted by the backend contract and returned by
-- the management read (clients decide what to present).
select pg_temp.set_exception(pg_temp.clinic(1), '2020-01-06', 'CLOSED', '[]');
select pg_temp.assert_true(
    pg_temp.read_exceptions(pg_temp.clinic(1)) -> 0
        = '{"local_date": "2020-01-06", "exception_kind": "CLOSED", "start_time": null, "end_time": null}'::jsonb,
    'Exceptions: past-date exceptions are stored and returned by the management read'
);
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));

-- Rejections leave the configuration unchanged.
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN',
           '[{"start_time": "09:00", "end_time": "12:00"}, {"start_time": "11:00", "end_time": "13:00"}]'),
    '23P01', 'must not overlap');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN',
           '[{"start_time": "09:00", "end_time": "12:00"}, {"start_time": "09:00", "end_time": "12:00"}]'),
    '23505', 'must not contain duplicates');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN',
           '[{"start_time": "12:00", "end_time": "09:00"}]'),
    '22023', 'start_time before end_time');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN',
           '[{"start_time": "9", "end_time": "12:00"}]'),
    '22007', 'valid ISO local-time representation');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN',
           '[{"start_time": "09:00", "end_time": "12:00", "iso_weekday": 7}]'),
    '22023', 'unsupported member');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'CLOSED',
           '[{"start_time": "09:00", "end_time": "12:00"}]'),
    '22023', 'CLOSED Clinic Appointment Availability Exception must not contain periods');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN', '[]'),
    '22023', 'OPEN Clinic Appointment Availability Exception requires at least one period');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'PARTIAL', '[]'),
    '22023', 'kind must be CLOSED or OPEN');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, null, %L)', pg_temp.clinic(1), '2035-03-04', '[]'),
    '22023', 'kind must be CLOSED or OPEN');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, null, %L, %L)', pg_temp.clinic(1), 'CLOSED', '[]'),
    '22023', 'must be a finite date');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), 'infinity', 'CLOSED', '[]'),
    '22023', 'must be a finite date');
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'OPEN',
           '{"start_time": "09:00", "end_time": "12:00"}'),
    '22023', 'must be a JSON array');
select pg_temp.assert_error(
    format('select pg_temp.clear_exception(%L, null)', pg_temp.clinic(1)),
    '22023', 'local date is required');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1))),
    'Exceptions: every rejected exception operation leaves the previous configuration intact'
);

-- Timezone required, even for CLOSED (BR-43, BR-75).
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(3), '2035-03-04', 'CLOSED', '[]'),
    '23514', 'requires a valid scheduling timezone');

-- Clinic isolation.
select pg_temp.assert_true(
    pg_temp.read_exceptions(pg_temp.clinic(2)) = '[]'::jsonb,
    'Exceptions: another Clinic''s exceptions are never returned'
);

-- ===========================================================================
-- 4. Standard Appointment duration (BR-57, BR-59, BR-61, BR-63, BR-64)
-- ===========================================================================

select pg_temp.set_duration(pg_temp.clinic(1), 10);
select pg_temp.assert_true(pg_temp.read_duration(pg_temp.clinic(1)) = 10, 'Duration: 10 minutes accepted and read back');
select pg_temp.set_duration(pg_temp.clinic(1), 240);
select pg_temp.assert_true(pg_temp.read_duration(pg_temp.clinic(1)) = 240, 'Duration: 240 minutes accepted and read back');
select pg_temp.set_duration(pg_temp.clinic(1), 45);
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));

select pg_temp.assert_error(format('select pg_temp.set_duration(%L, 9)', pg_temp.clinic(1)), '22023', 'between 10 and 240 minutes');
select pg_temp.assert_error(format('select pg_temp.set_duration(%L, 241)', pg_temp.clinic(1)), '22023', 'between 10 and 240 minutes');
select pg_temp.assert_error(format('select pg_temp.set_duration(%L, 0)', pg_temp.clinic(1)), '22023', 'between 10 and 240 minutes');
select pg_temp.assert_error(format('select pg_temp.set_duration(%L, -30)', pg_temp.clinic(1)), '22023', 'between 10 and 240 minutes');
-- Integer semantics: a fractional value does not resolve to the integer RPC
-- (as through PostgREST), and the read returns an integer.
select pg_temp.assert_error(
    format('select public.set_clinic_standard_appointment_duration(%L::uuid, 30.5)', pg_temp.clinic(1)),
    '42883', null);
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)))
    and pg_typeof(pg_temp.read_duration(pg_temp.clinic(1)))::text = 'integer',
    'Duration: out-of-range and fractional values are rejected without changing the configured duration'
);

-- ===========================================================================
-- 5. Existing Appointments are never rewritten (BR-29, BR-30, BR-63, BR-64,
--    BR-70, BR-75)
-- ===========================================================================

-- Every configuration change above (weekly replacement, exceptions on the
-- Appointments' own dates, duration changes) already happened after the
-- fingerprint was taken; repeat the most invasive ones explicitly.
select pg_temp.set_duration(pg_temp.clinic(1), 15);
select pg_temp.replace(pg_temp.clinic(1), '[{"iso_weekday": 3, "start_time": "09:00", "end_time": "10:00"}]');
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-05', 'CLOSED', '[]');
select pg_temp.set_exception(pg_temp.clinic(1), '2035-03-06', 'CLOSED', '[]');
select pg_temp.clear_exception(pg_temp.clinic(1), '2035-03-05');
select pg_temp.assert_true(
    pg_temp.unchanged('appointments', pg_temp.appointment_fingerprint())
    and (select lifecycle_state = 'REQUESTED' from public.appointments where id = pg_temp.appt(1))
    and (select lifecycle_state = 'CONFIRMED' from public.appointments where id = pg_temp.appt(2))
    and (select scheduled_end_at - scheduled_start_at = interval '30 minutes'
         from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(2) and revision_sequence = 2)
    and (select state = 'PENDING' from public.appointment_reschedule_proposals where id = 'a7130000-0000-4000-8000-000000000d02'),
    'Existing Appointments: duration, weekly, and exception changes rewrite no Appointment, Schedule Revision, Reschedule Proposal, or Lifecycle Event'
);

-- ===========================================================================
-- 6. Authorization (BR-27, BR-28, BR-37, BR-59, BR-74, BR-75)
-- ===========================================================================

-- Every write is allowed for each responsibility with the capability.
do $$
declare
    actor integer;
begin
    foreach actor in array array[4, 5, 6, 7, 8] loop
        perform pg_temp.act(actor);
        perform pg_temp.replace(pg_temp.clinic(1),
            format('[{"iso_weekday": 1, "start_time": "09:00", "end_time": "%s:00"}]', 10 + actor));
        perform pg_temp.set_exception(pg_temp.clinic(1), '2035-03-04', 'OPEN',
            format('[{"start_time": "10:00", "end_time": "%s:00"}]', 10 + actor));
        perform pg_temp.clear_exception(pg_temp.clinic(1), '2035-03-06');
        perform pg_temp.set_duration(pg_temp.clinic(1), 20 + actor);
        perform pg_temp.assert_true(
            pg_temp.read_periods(pg_temp.clinic(1))
                = jsonb_build_array(jsonb_build_object('iso_weekday', 1, 'start_time', '09:00:00',
                                                       'end_time', format('%s:00:00', 10 + actor)))
            and pg_temp.read_exceptions(pg_temp.clinic(1)) @> jsonb_build_array(jsonb_build_object(
                    'local_date', '2035-03-04', 'exception_kind', 'OPEN',
                    'start_time', '10:00:00', 'end_time', format('%s:00:00', 10 + actor)))
            and not (pg_temp.read_exceptions(pg_temp.clinic(1)) @> '[{"local_date": "2035-03-06"}]'::jsonb)
            and pg_temp.read_duration(pg_temp.clinic(1)) = 20 + actor
            and pg_temp.read_timezone(pg_temp.clinic(1)) = 'Europe/Madrid',
            format('Authorization: User %s (OWNER / Org ADMINISTRATOR / Clinic ADMINISTRATOR / Org RECEPTIONIST / Clinic RECEPTIONIST) may read and perform every write', actor)
        );
    end loop;
end;
$$;

-- Every write and the read are denied without the capability, with no change.
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));
do $$
declare
    actor integer;
begin
    -- 01 no Membership; 09 RECEPTIONIST of another Clinic; 10 VETERINARIAN
    -- with a current Clinic Assignment; 11 ended Membership; 12 ended Grant.
    foreach actor in array array[1, 9, 10, 11, 12] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_error(
            format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[]'),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'CLOSED', '[]'),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.clear_exception(%L, %L)', pg_temp.clinic(1), '2035-03-04'),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.set_duration(%L, 30)', pg_temp.clinic(1)),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.read_periods(%L)', pg_temp.clinic(1)),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1))),
    'Authorization: a User with no Membership, a RECEPTIONIST of another Clinic, a VETERINARIAN, an ended Membership, and an ended Grant are denied every write and the read, with no change'
);

-- The Clinic-scoped RECEPTIONIST of A2 is allowed at A2 only.
select pg_temp.act(9);
select pg_temp.replace(pg_temp.clinic(2), '[{"iso_weekday": 4, "start_time": "08:00", "end_time": "10:00"}]');
select pg_temp.assert_true(
    pg_temp.read_periods(pg_temp.clinic(2))
        = '[{"iso_weekday": 4, "start_time": "08:00:00", "end_time": "10:00:00"}]'::jsonb
    and pg_temp.read_timezone(pg_temp.clinic(2)) = 'Atlantic/Canary'
    and pg_temp.read_duration(pg_temp.clinic(2)) = 20,
    'Authorization: a Clinic-scoped RECEPTIONIST manages and reads its own Clinic'
);

-- Cross-Organization: OrgA's OWNER cannot read or change OrgB's Clinic.
select pg_temp.act(4);
select pg_temp.assert_error(format('select pg_temp.read_periods(%L)', pg_temp.clinic(4)), '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error(format('select pg_temp.replace(%L, %L)', pg_temp.clinic(4), '[]'), '42501', 'Applicable Appointment Availability-management capability is required');

-- Unauthenticated and nonexistent Clinic.
select pg_temp.act_anonymous();
select pg_temp.assert_error(format('select pg_temp.read_periods(%L)', pg_temp.clinic(1)), '28000', 'Authentication is required');
select pg_temp.assert_error(format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[]'), '28000', 'Authentication is required');
select pg_temp.assert_error(format('select pg_temp.set_duration(%L, 30)', pg_temp.clinic(1)), '28000', 'Authentication is required');
select pg_temp.act(4);
-- The read fails closed for an unknown Clinic exactly as for an inaccessible
-- one (20261014090000); the writes still report 23503.
select pg_temp.assert_error(format('select pg_temp.read_periods(%L)', pg_temp.clinic(99)), '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error(format('select pg_temp.replace(%L, %L)', pg_temp.clinic(99), '[]'), '23503', 'Clinic does not exist');

-- Remaining denial paths for every write (all four share one authorization
-- resolver; each RPC is still exercised once per path so a per-RPC bypass
-- would be caught), with no change anywhere.
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));
select pg_temp.remember('a2', pg_temp.config_fingerprint(pg_temp.clinic(2)));
select pg_temp.act_anonymous();
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'CLOSED', '[]'),
    '28000', 'Authentication is required');
select pg_temp.assert_error(
    format('select pg_temp.clear_exception(%L, %L)', pg_temp.clinic(1), '2035-03-04'),
    '28000', 'Authentication is required');
do $$
declare
    actor integer;
begin
    -- 13 RECEPTIONIST of another Organization; 14 ADMINISTRATOR of Clinic A2.
    foreach actor in array array[13, 14] loop
        perform pg_temp.act(actor);
        perform pg_temp.assert_error(
            format('select pg_temp.replace(%L, %L)', pg_temp.clinic(1), '[]'),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(1), '2035-03-04', 'CLOSED', '[]'),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.clear_exception(%L, %L)', pg_temp.clinic(1), '2035-03-04'),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.set_duration(%L, 30)', pg_temp.clinic(1)),
            '42501', 'Applicable Appointment Availability-management capability is required');
        perform pg_temp.assert_error(
            format('select pg_temp.read_periods(%L)', pg_temp.clinic(1)),
            '42501', 'Applicable Clinic-management capability is required');
    end loop;
end;
$$;
select pg_temp.act(4);
select pg_temp.assert_error(
    format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(99), '2035-03-04', 'CLOSED', '[]'),
    '23503', 'Clinic does not exist');
select pg_temp.assert_error(
    format('select pg_temp.clear_exception(%L, %L)', pg_temp.clinic(99), '2035-03-04'),
    '23503', 'Clinic does not exist');
select pg_temp.assert_error(
    format('select pg_temp.set_duration(%L, 30)', pg_temp.clinic(99)),
    '23503', 'Clinic does not exist');
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)))
    and pg_temp.unchanged('a2', pg_temp.config_fingerprint(pg_temp.clinic(2)))
    and not exists (select 1 from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.clinic(99)),
    'Authorization: anonymous exception set/clear, a Receptionist of another Organization, a Clinic Administrator of another Clinic, and an unknown Clinic are denied every write with no change'
);

-- The Clinic Administrator of A2 is allowed at A2 only (the denial above is
-- scope, not responsibility).
select pg_temp.act(14);
select pg_temp.set_duration(pg_temp.clinic(2), 25);
select pg_temp.assert_true(
    pg_temp.read_duration(pg_temp.clinic(2)) = 25,
    'Authorization: a Clinic-scoped ADMINISTRATOR manages its own Clinic'
);
select pg_temp.set_duration(pg_temp.clinic(2), 20);
select pg_temp.act(4);

-- Without PROFESSIONAL_SCHEDULING (PENDING and EXPIRED Subscriptions): the
-- read still returns the existing configuration; every write is denied and
-- changes nothing (BR-37, BR-38, BR-74, SPEC-SUB-003).
select pg_temp.act(16);
select pg_temp.assert_true(
    pg_temp.read_timezone(pg_temp.clinic(4)) = 'Europe/Lisbon'
    and pg_temp.read_duration(pg_temp.clinic(4)) = 20
    and pg_temp.read_periods(pg_temp.clinic(4))
        = '[{"iso_weekday": 1, "start_time": "09:00:00", "end_time": "13:00:00"}]'::jsonb
    and pg_temp.read_exceptions(pg_temp.clinic(4))
        = '[{"local_date": "2035-03-04", "exception_kind": "OPEN", "start_time": "10:00:00", "end_time": "12:00:00"}]'::jsonb
    and pg_temp.read_duration(pg_temp.clinic(6)) = 45
    and pg_temp.read_periods(pg_temp.clinic(6))
        = '[{"iso_weekday": 3, "start_time": "16:00:00", "end_time": "19:00:00"}]'::jsonb,
    'Entitlement: the management read returns existing configuration without PROFESSIONAL_SCHEDULING (PENDING and EXPIRED)'
);
select pg_temp.remember('b1', pg_temp.config_fingerprint(pg_temp.clinic(4)));
select pg_temp.remember('c1', pg_temp.config_fingerprint(pg_temp.clinic(6)));
do $$
declare
    target integer;
begin
    foreach target in array array[4, 6] loop
        perform pg_temp.assert_error(
            format('select pg_temp.replace(%L, %L)', pg_temp.clinic(target), '[]'),
            '42501', 'Professional scheduling Entitlement is required');
        perform pg_temp.assert_error(
            format('select pg_temp.set_exception(%L, %L, %L, %L)', pg_temp.clinic(target), '2035-03-05', 'CLOSED', '[]'),
            '42501', 'Professional scheduling Entitlement is required');
        perform pg_temp.assert_error(
            format('select pg_temp.clear_exception(%L, %L)', pg_temp.clinic(target), '2035-03-04'),
            '42501', 'Professional scheduling Entitlement is required');
        perform pg_temp.assert_error(
            format('select pg_temp.set_duration(%L, 30)', pg_temp.clinic(target)),
            '42501', 'Professional scheduling Entitlement is required');
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.unchanged('b1', pg_temp.config_fingerprint(pg_temp.clinic(4)))
    and pg_temp.unchanged('c1', pg_temp.config_fingerprint(pg_temp.clinic(6))),
    'Entitlement: every write is denied without PROFESSIONAL_SCHEDULING and existing configuration is preserved (BR-38)'
);

-- ===========================================================================
-- 7. Management read (BR-74)
-- ===========================================================================

-- A Clinic with no timezone and no duration: both absent, empty lists.
select pg_temp.act(5);
select pg_temp.assert_true(
    (select scheduling_timezone_name is null
            and standard_appointment_duration_minutes is null
            and recurring_periods = '[]'::jsonb
            and exceptions = '[]'::jsonb
     from public.get_managed_clinic_appointment_availability(pg_temp.clinic(3))),
    'Read: a Clinic without timezone, duration, periods, or exceptions returns NULL, NULL, [], []'
);

-- Exactly one row for the requested Clinic, independent of publication.
select pg_temp.assert_true(
    (select count(*) = 1 from public.get_managed_clinic_appointment_availability(pg_temp.clinic(1)))
    and not (select is_published from public.clinics where id = pg_temp.clinic(1)),
    'Read: exactly one row is returned for an unpublished Clinic'
);

-- The read persists nothing.
select pg_temp.remember('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)));
select pg_temp.remember('appointments', pg_temp.appointment_fingerprint());
select count(*) from public.get_managed_clinic_appointment_availability(pg_temp.clinic(1));
select pg_temp.assert_true(
    pg_temp.unchanged('a1', pg_temp.config_fingerprint(pg_temp.clinic(1)))
    and pg_temp.unchanged('appointments', pg_temp.appointment_fingerprint()),
    'Read: reading changes no configuration or Appointment state'
);

do $$ begin raise notice 'clinic_appointment_availability_management_spec_apt_013.sql: all assertions passed'; end $$;

rollback;

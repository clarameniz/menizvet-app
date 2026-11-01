-- Regression suite for SPEC-APT-002 — Confirm Appointment, including the
-- stale-safe confirmation contract (BR-21, BR-22, BR-23, Verification Notes
-- 1–25) and SPEC-APT-012 BR-43 (Verification Notes 28–30), migration
-- 20261003090000_stale_safe_appointment_confirmation.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions are
-- rolled back; superuser test execution is required solely to load a
-- deliberately minimal deterministic context with establishment triggers
-- bypassed, to inspect protected tables, and to switch between impersonated
-- Users (same rationale as professional_clinics_spec_org_008.sql).
--
-- Every behavioral call goes through the real trusted operations
-- (`confirm_appointment`, `reschedule_requested_appointment`,
-- `get_clinic_appointment_schedule`, `get_pet_appointments`). Deferred
-- integrity, conflict, and Care Authorization triggers normally fire only at
-- COMMIT, which a rolled-back suite never reaches; pg_temp.confirm and
-- pg_temp.reschedule therefore fire every pending deferred trigger at the end
-- of the call (SET CONSTRAINTS ALL IMMEDIATE, then back to DEFERRED — the
-- database has no DEFERRABLE INITIALLY IMMEDIATE constraint, so DEFERRED is
-- exactly the initial mode). A commit-time failure therefore surfaces inside
-- the same subtransaction and rolls back everything the call wrote.
--
-- Covers:
--   * contract: exact signatures, no default, single overload, attributes,
--     ACLs, and the identifier-only form no longer existing;
--   * schedule read: `current_schedule_revision_sequence` is the sequence of
--     exactly the revision whose interval is returned, in every lifecycle
--     state, and confirmation is driven by it;
--   * stale sequence after a Guardian reschedule, after a same-start
--     duration change, and after a timezone-only change; zero side effects;
--     fresh confirmation after re-reading;
--   * invalid expected sequence (NULL, zero, negative) as 22023;
--   * authorization by responsibility and scope, Entitlement by Subscription
--     state, lifecycle and concurrency, past time, Availability,
--     Veterinarian validation, and deferred cross-Clinic conflict rollback;
--   * Communications: one APPOINTMENT_CONFIRMED per current Guardian, none for
--     former Guardians or Clinic actors, none for any failed confirmation;
--   * Clinic and Guardian reads show CONFIRMED after success.
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
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected_sqlstate;
end;
$$;

-- Fixture identifiers.
create function pg_temp.appt(p_n integer)
returns uuid language sql immutable as $$
    select ('c0f10000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.domain_user(p_n integer)
returns uuid language sql immutable as $$
    select ('c0f10000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;

-- Impersonate auth subject N (domain User N when one exists).
create function pg_temp.act(p_n integer)
returns void language sql as $$
    select set_config(
        'request.jwt.claim.sub',
        'c0f10000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'),
        true
    );
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.confirm(p_appointment_id uuid, p_expected_sequence integer)
returns uuid language plpgsql as $$
declare
    confirmed_id uuid;
begin
    confirmed_id := public.confirm_appointment(p_appointment_id, p_expected_sequence);
    set constraints all immediate;
    set constraints all deferred;
    return confirmed_id;
end;
$$;

create function pg_temp.reschedule(
    p_appointment_id uuid, p_local_date date, p_local_time time, p_offset_seconds integer
)
returns void language plpgsql as $$
begin
    perform public.reschedule_requested_appointment(
        p_appointment_id, p_local_date, p_local_time, p_offset_seconds
    );
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

-- Every persisted fact a confirmation could touch for one Appointment.
create function pg_temp.appointment_fingerprint(p_appointment_id uuid)
returns text language sql as $$
    select md5(
        coalesce((select appointment::text from public.appointments as appointment
                  where appointment.id = p_appointment_id), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.revision_sequence)
                  from public.appointment_schedule_revisions as revision
                  where revision.appointment_id = p_appointment_id), '')
        || '#' || coalesce((select string_agg(lifecycle_event::text, '|' order by lifecycle_event.id)
                  from public.appointment_lifecycle_events as lifecycle_event
                  where lifecycle_event.appointment_id = p_appointment_id), '')
        || '#' || coalesce((select string_agg(assignment::text, '|' order by assignment.id)
                  from public.appointment_veterinarian_assignments as assignment
                  where assignment.appointment_id = p_appointment_id), '')
        || '#' || coalesce((select string_agg(care_auth::text, '|' order by care_auth.id)
                  from public.care_authorizations as care_auth
                  where care_auth.appointment_id = p_appointment_id), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication
                  where communication.appointment_id = p_appointment_id), '')
    )
$$;

create temporary table fingerprint_before (
    label text primary key,
    fingerprint text not null,
    total_communications bigint not null
) on commit drop;

create function pg_temp.remember(p_label text, p_appointment_id uuid)
returns void language sql as $$
    insert into fingerprint_before
    values (p_label, pg_temp.appointment_fingerprint(p_appointment_id),
            (select count(*) from public.transactional_communications))
$$;

create function pg_temp.unchanged(p_label text, p_appointment_id uuid)
returns boolean language sql as $$
    select pg_temp.appointment_fingerprint(p_appointment_id) = before.fingerprint
       and (select count(*) from public.transactional_communications) = before.total_communications
    from fingerprint_before as before
    where before.label = p_label
$$;

-- Captured Clinic schedule rows, keyed by label.
create temporary table schedule_snapshot (
    label text not null,
    id uuid not null,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_schedule_revision_sequence integer,
    current_veterinarian_clinic_assignment_id uuid,
    primary key (label, id)
) on commit drop;

grant select, insert on schedule_snapshot to authenticated;

create function pg_temp.capture_schedule(p_label text, p_clinic_id uuid)
returns void language sql as $$
    insert into schedule_snapshot
    select p_label, schedule.id, schedule.lifecycle_state, schedule.current_scheduled_start_at,
           schedule.current_scheduled_end_at, schedule.current_scheduling_timezone_name,
           schedule.current_schedule_revision_sequence, schedule.current_veterinarian_clinic_assignment_id
    from public.get_clinic_appointment_schedule(p_clinic_id) as schedule
$$;

-- Sequence the Clinic schedule exposes for one Appointment in a snapshot.
create function pg_temp.seen_sequence(p_label text, p_appointment_id uuid)
returns integer language sql as $$
    select snapshot.current_schedule_revision_sequence
    from schedule_snapshot as snapshot
    where snapshot.label = p_label and snapshot.id = p_appointment_id
$$;

create temporary table guardian_snapshot (
    label text not null,
    id uuid not null,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    primary key (label, id)
) on commit drop;

grant select, insert on guardian_snapshot to authenticated;

-- ===========================================================================
-- 1. Contract, attributes, ACLs (VN 25; SPEC-APT-012 VN 28–30).
-- ===========================================================================

select pg_temp.assert_true(
    to_regprocedure('public.confirm_appointment(uuid)') is null
    and (select count(*) = 1 from pg_proc as proc
         where proc.proname = 'confirm_appointment'
           and proc.pronamespace = 'public'::regnamespace),
    'Contract: the identifier-only confirm_appointment(uuid) no longer exists; exactly one overload remains'
);

select pg_temp.assert_true(
    (select pg_get_function_arguments(proc.oid) = 'p_appointment_id uuid, p_expected_requested_revision_sequence integer'
            and pg_get_function_result(proc.oid) = 'uuid'
            and proc.pronargdefaults = 0
            and proc.prosecdef
            and proc.provolatile = 'v'
            and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.confirm_appointment(uuid, integer)'::regprocedure),
    'Contract: confirm_appointment(p_appointment_id uuid, p_expected_requested_revision_sequence integer) returns uuid, no default, SECURITY DEFINER, VOLATILE, empty search_path'
);

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)
    = 'TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, '
      -- 20261107090000 (SPEC-APT-012 BR-49): the requester's current display name.
      'requester_display_name text, reason_for_visit text, '
      'guardian_notes text, lifecycle_state text, created_at timestamp with time zone, '
      'current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, '
      'current_scheduling_timezone_name text, current_schedule_revision_sequence integer, '
      'current_veterinarian_clinic_assignment_id uuid, '
      'pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, '
      'pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, '
      'pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, '
      'pending_reschedule_reason text, '
      -- 20261010090000 (SPEC-APT-012 BR-45): provenance of the relevant interval.
      'current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, '
      -- 20261022090000: the recorded reason of a CANCELLED Appointment.
      'cancellation_reason text, '
      -- 20261113090000 (SPEC-MED-010): whether clinical documentation exists.
      'has_clinical_record boolean)',
    'Contract: the schedule read adds only current_schedule_revision_sequence integer after the interval'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from pg_proc as proc, unnest(proc.proargnames) as argument_name
        where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure
          and argument_name ~ '(revision_id|revisions|history|established_by|source_proposal)'
          -- 20261010090000 (SPEC-APT-012 BR-45): the approved provenance of the
          -- relevant interval only.
          and argument_name not in (
              'current_schedule_source_proposal_id', 'current_schedule_source_proposing_context'
          )
    ),
    'Contract: no Schedule Revision id or revision history is exposed'
);

select pg_temp.assert_true(
    (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure),
    'Attributes: the schedule read keeps SECURITY DEFINER, STABLE, empty search_path'
);

-- service_role receives EXECUTE through the platform's default privileges,
-- exactly as for every other client RPC.
select pg_temp.assert_true(
    (select bool_and(
        (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from aclexplode(proc.proacl) as acl_entry
         where acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE'])
     from pg_proc as proc
     where proc.oid in ('public.confirm_appointment(uuid, integer)'::regprocedure,
                        'public.get_clinic_appointment_schedule(uuid)'::regprocedure))
    and not has_function_privilege('anon', 'public.confirm_appointment(uuid, integer)', 'EXECUTE')
    and not has_function_privilege('public', 'public.confirm_appointment(uuid, integer)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE'),
    'ACL: EXECUTE only for authenticated (plus platform service_role) on both RPCs'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c0f10000-…-0000000001NN, domain Users …-0000000002NN:
--   01 current Guardian G1 of Luna     09 RECEPTIONIST @ A2 (Clinic)
--   02 current Guardian G2 of Luna     10 VETERINARIAN assigned @ A1 (view only)
--   03 former Guardian of Luna         11 Org RECEPTIONIST, Membership ended
--   04 OrgA OWNER                      12 Org RECEPTIONIST grant ended
--   05 OrgA ADMINISTRATOR (Org)        13 Veterinarian V1 @ A1 and @ A2
--   06 ADMINISTRATOR @ A1 (Clinic)     14 Veterinarian V2, @ A1 ended
--   07 OrgA RECEPTIONIST (Org)         15 Veterinarian V3 @ A1, no Availability
--   08 RECEPTIONIST @ A1 (Clinic)      16 OWNER of every Entitlement-variant Org
--
-- Organizations (…03NN) and Clinics (…04NN):
--   0301 OrgA  ACTIVE, inside explicit validity  -> A1 0401, A2 0402
--   0302 OrgC  CANCELLED, before valid_until     -> 0403
--   0303 OrgP  PENDING                           -> 0404
--   0304 OrgD  PAST_DUE                          -> 0405
--   0305 OrgE  EXPIRED                           -> 0406
--   0306 OrgN  no Subscription                   -> 0407
--   0307 OrgL  ACTIVE, validity ended            -> 0408
-- Every Clinic: Europe/Madrid, 30-minute standard duration, Availability
-- 08:00–20:00 local every weekday. A1 is CLOSED on 2035-03-08.
--
-- Appointments (…0bNN), all for Luna, REQUESTED at 2035-03-06 09:00Z
-- (10:00 Madrid) for 30 minutes unless stated:
--   01 OWNER confirms              20 OrgC (CANCELLED, still valid)
--   02 Org ADMINISTRATOR confirms  21 OrgP  22 OrgD  23 OrgE  24 OrgN  25 OrgL
--   03 Clinic ADMINISTRATOR @ A1   30 CANCELLED    31 COMPLETED   32 NO_SHOW
--   04 @ A2 (scope denials)        33 two Clinic actors
--   05 Org RECEPTIONIST            34 past (2020-06-01 09:00Z)
--   06 Clinic RECEPTIONIST @ A1    35 2035-03-08 (A1 CLOSED that day)
--   08 authorization denials       40 2035-03-07, V1 assigned
--   10 fresh / invalid sequence    41 V2 assigned (Clinic Assignment ended)
--   11 Guardian reschedule         42 V3 assigned (no Availability)
--   12 same start, new duration    43 2035-03-09, V1 assigned @ A1
--   13 timezone-only revision 2    44 @ A2 CONFIRMED 2035-03-09, V1 assigned
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('c0f10000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 16) as n;

insert into public.users (id)
select pg_temp.domain_user(n) from generate_series(1, 16) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c0f10000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 16) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('c0f10000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('c0f10000-0000-4000-8000-000000000302', 'Org Cancelled Valid'),
    ('c0f10000-0000-4000-8000-000000000303', 'Org Pending'),
    ('c0f10000-0000-4000-8000-000000000304', 'Org Past Due'),
    ('c0f10000-0000-4000-8000-000000000305', 'Org Expired'),
    ('c0f10000-0000-4000-8000-000000000306', 'Org Without Subscription'),
    ('c0f10000-0000-4000-8000-000000000307', 'Org Active Lapsed');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    ('c0f10000-0000-4000-8000-000000000401', 'c0f10000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000402', 'c0f10000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000403', 'c0f10000-0000-4000-8000-000000000302', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000404', 'c0f10000-0000-4000-8000-000000000303', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000405', 'c0f10000-0000-4000-8000-000000000304', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000406', 'c0f10000-0000-4000-8000-000000000305', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000407', 'c0f10000-0000-4000-8000-000000000306', true, 'Europe/Madrid', 30),
    ('c0f10000-0000-4000-8000-000000000408', 'c0f10000-0000-4000-8000-000000000307', true, 'Europe/Madrid', 30);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select clinic.id, weekday, '08:00', '20:00'
from public.clinics as clinic, generate_series(1, 7) as weekday
where clinic.id::text like 'c0f10000-0000-4000-8000-0000000004%';

-- Availability removed for one local day after the Appointment was requested.
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
values ('c0f10000-0000-4000-8000-000000000401', '2035-03-08', 'CLOSED');

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('c0f10000-0000-4000-8000-000000000504', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000204', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000505', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000205', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000506', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000206', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000507', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000207', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000508', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000208', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000509', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000209', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000510', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000210', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000511', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000211', '2020-01-01Z', '2021-01-01Z', 'c0f10000-0000-4000-8000-000000000204'),
    ('c0f10000-0000-4000-8000-000000000512', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000212', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000513', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000213', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000514', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000214', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000515', 'c0f10000-0000-4000-8000-000000000301', 'c0f10000-0000-4000-8000-000000000215', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000516', 'c0f10000-0000-4000-8000-000000000302', 'c0f10000-0000-4000-8000-000000000216', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000517', 'c0f10000-0000-4000-8000-000000000303', 'c0f10000-0000-4000-8000-000000000216', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000518', 'c0f10000-0000-4000-8000-000000000304', 'c0f10000-0000-4000-8000-000000000216', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000519', 'c0f10000-0000-4000-8000-000000000305', 'c0f10000-0000-4000-8000-000000000216', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000520', 'c0f10000-0000-4000-8000-000000000306', 'c0f10000-0000-4000-8000-000000000216', '2020-01-01Z', null, null),
    ('c0f10000-0000-4000-8000-000000000521', 'c0f10000-0000-4000-8000-000000000307', 'c0f10000-0000-4000-8000-000000000216', '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('c0f10000-0000-4000-8000-000000000604', 'c0f10000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000605', 'c0f10000-0000-4000-8000-000000000505', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000606', 'c0f10000-0000-4000-8000-000000000506', 'ADMINISTRATOR', 'CLINIC', 'c0f10000-0000-4000-8000-000000000401', '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000607', 'c0f10000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000608', 'c0f10000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', 'c0f10000-0000-4000-8000-000000000401', '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000609', 'c0f10000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', 'c0f10000-0000-4000-8000-000000000402', '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000610', 'c0f10000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000611', 'c0f10000-0000-4000-8000-000000000511', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000612', 'c0f10000-0000-4000-8000-000000000512', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', 'c0f10000-0000-4000-8000-000000000204', 'c0f10000-0000-4000-8000-000000000204'),
    ('c0f10000-0000-4000-8000-000000000613', 'c0f10000-0000-4000-8000-000000000513', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000614', 'c0f10000-0000-4000-8000-000000000514', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000615', 'c0f10000-0000-4000-8000-000000000515', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000204', null),
    ('c0f10000-0000-4000-8000-000000000616', 'c0f10000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000216', null),
    ('c0f10000-0000-4000-8000-000000000617', 'c0f10000-0000-4000-8000-000000000517', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000216', null),
    ('c0f10000-0000-4000-8000-000000000618', 'c0f10000-0000-4000-8000-000000000518', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000216', null),
    ('c0f10000-0000-4000-8000-000000000619', 'c0f10000-0000-4000-8000-000000000519', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000216', null),
    ('c0f10000-0000-4000-8000-000000000620', 'c0f10000-0000-4000-8000-000000000520', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000216', null),
    ('c0f10000-0000-4000-8000-000000000621', 'c0f10000-0000-4000-8000-000000000521', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, 'c0f10000-0000-4000-8000-000000000216', null);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('c0f10000-0000-4000-8000-000000000710', 'c0f10000-0000-4000-8000-000000000210'),
    ('c0f10000-0000-4000-8000-000000000713', 'c0f10000-0000-4000-8000-000000000213'),
    ('c0f10000-0000-4000-8000-000000000714', 'c0f10000-0000-4000-8000-000000000214'),
    ('c0f10000-0000-4000-8000-000000000715', 'c0f10000-0000-4000-8000-000000000215');

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('c0f10000-0000-4000-8000-000000000810', 'c0f10000-0000-4000-8000-000000000710', 'c0f10000-0000-4000-8000-000000000510', 'c0f10000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    ('c0f10000-0000-4000-8000-000000000813', 'c0f10000-0000-4000-8000-000000000713', 'c0f10000-0000-4000-8000-000000000513', 'c0f10000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    ('c0f10000-0000-4000-8000-000000000823', 'c0f10000-0000-4000-8000-000000000713', 'c0f10000-0000-4000-8000-000000000513', 'c0f10000-0000-4000-8000-000000000402', '2020-01-01Z', null),
    ('c0f10000-0000-4000-8000-000000000814', 'c0f10000-0000-4000-8000-000000000714', 'c0f10000-0000-4000-8000-000000000514', 'c0f10000-0000-4000-8000-000000000401', '2020-01-01Z', '2021-01-01Z'),
    ('c0f10000-0000-4000-8000-000000000815', 'c0f10000-0000-4000-8000-000000000715', 'c0f10000-0000-4000-8000-000000000515', 'c0f10000-0000-4000-8000-000000000401', '2020-01-01Z', null);

-- V3 (…0815) deliberately has no Veterinarian Availability.
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time)
select assignment_id::uuid, weekday, '08:00', '20:00'
from unnest(array[
    'c0f10000-0000-4000-8000-000000000813',
    'c0f10000-0000-4000-8000-000000000823',
    'c0f10000-0000-4000-8000-000000000814'
]) as assignment_id, generate_series(1, 7) as weekday;

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('c0f10000-0000-4000-8000-000000000901', 'c0f10000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',    '2020-01-01Z', '2020-01-01Z', statement_timestamp() + interval '365 days', 'spec-apt-002-test', 'c0f10000-0000-4000-8000-000000000a91'),
    ('c0f10000-0000-4000-8000-000000000902', 'c0f10000-0000-4000-8000-000000000302', '2020-01-01Z', 'CANCELLED', '2020-01-01Z', null, statement_timestamp() + interval '365 days', 'spec-apt-002-test', 'c0f10000-0000-4000-8000-000000000a92'),
    ('c0f10000-0000-4000-8000-000000000903', 'c0f10000-0000-4000-8000-000000000303', '2020-01-01Z', 'PENDING',   '2020-01-01Z', null, null,                                      'spec-apt-002-test', 'c0f10000-0000-4000-8000-000000000a93'),
    ('c0f10000-0000-4000-8000-000000000904', 'c0f10000-0000-4000-8000-000000000304', '2020-01-01Z', 'PAST_DUE',  '2020-01-01Z', null, null,                                      'spec-apt-002-test', 'c0f10000-0000-4000-8000-000000000a94'),
    ('c0f10000-0000-4000-8000-000000000905', 'c0f10000-0000-4000-8000-000000000305', '2020-01-01Z', 'EXPIRED',   '2020-01-01Z', null, null,                                      'spec-apt-002-test', 'c0f10000-0000-4000-8000-000000000a95'),
    ('c0f10000-0000-4000-8000-000000000907', 'c0f10000-0000-4000-8000-000000000307', '2020-01-01Z', 'ACTIVE',    '2020-01-01Z', null, '2021-01-01Z',                             'spec-apt-002-test', 'c0f10000-0000-4000-8000-000000000a97');

insert into public.pets (id, name, species, created_at) values
    ('c0f10000-0000-4000-8000-000000000a01', 'Luna', 'Dog', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('c0f10000-0000-4000-8000-000000000a11', 'c0f10000-0000-4000-8000-000000000201', 'c0f10000-0000-4000-8000-000000000a01', '2020-01-01Z', null),
    ('c0f10000-0000-4000-8000-000000000a12', 'c0f10000-0000-4000-8000-000000000202', 'c0f10000-0000-4000-8000-000000000a01', '2020-01-01Z', null),
    ('c0f10000-0000-4000-8000-000000000a13', 'c0f10000-0000-4000-8000-000000000203', 'c0f10000-0000-4000-8000-000000000a01', '2020-01-01Z', '2021-01-01Z');

-- One Appointment with its initial REQUESTED revision and its
-- Appointment-derived Care Authorization (ENDED for a cancelled Appointment).
create function pg_temp.seed_appointment(
    p_n integer, p_clinic_id uuid, p_start_at timestamptz, p_lifecycle_state text
)
returns void language sql as $$
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), 'c0f10000-0000-4000-8000-000000000a01', p_clinic_id,
            'c0f10000-0000-4000-8000-000000000201', 'Visit ' || p_n, p_lifecycle_state,
            '2026-08-01T00:00:00Z'::timestamptz + make_interval(hours => p_n));

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    ) values (
        pg_temp.appt(p_n), 1, 'REQUESTED', p_start_at, p_start_at + interval '30 minutes',
        'Europe/Madrid', 'c0f10000-0000-4000-8000-000000000201', null,
        '2026-08-01T00:00:00Z'::timestamptz + make_interval(hours => p_n)
    );

    insert into public.care_authorizations (
        pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose,
        appointment_id, lifecycle_state, ended_at, ended_reason
    )
    select 'c0f10000-0000-4000-8000-000000000a01', clinic.id, clinic.organization_id,
           'c0f10000-0000-4000-8000-000000000a11',
           '2026-08-01T00:00:00Z'::timestamptz + make_interval(hours => p_n),
           'APPOINTMENT_CARE', pg_temp.appt(p_n),
           case when p_lifecycle_state = 'CANCELLED' then 'ENDED' else 'ACTIVE' end,
           case when p_lifecycle_state = 'CANCELLED' then '2026-08-20T00:00:00Z'::timestamptz end,
           case when p_lifecycle_state = 'CANCELLED' then 'APPOINTMENT_CANCELLED' end
    from public.clinics as clinic
    where clinic.id = p_clinic_id;
$$;

select pg_temp.seed_appointment(n, 'c0f10000-0000-4000-8000-000000000401', '2035-03-06T09:00Z', 'REQUESTED')
from unnest(array[1, 2, 3, 5, 6, 8, 10, 11, 12, 13, 33, 41, 42]) as n;
select pg_temp.seed_appointment(4, 'c0f10000-0000-4000-8000-000000000402', '2035-03-06T09:00Z', 'REQUESTED');
select pg_temp.seed_appointment(20 + k, ('c0f10000-0000-4000-8000-00000000040' || (3 + k))::uuid, '2035-03-06T09:00Z', 'REQUESTED')
from generate_series(0, 5) as k;
select pg_temp.seed_appointment(30, 'c0f10000-0000-4000-8000-000000000401', '2035-03-06T09:00Z', 'CANCELLED');
select pg_temp.seed_appointment(31, 'c0f10000-0000-4000-8000-000000000401', '2035-03-06T09:00Z', 'COMPLETED');
select pg_temp.seed_appointment(32, 'c0f10000-0000-4000-8000-000000000401', '2035-03-06T09:00Z', 'NO_SHOW');
select pg_temp.seed_appointment(34, 'c0f10000-0000-4000-8000-000000000401', '2020-06-01T09:00Z', 'REQUESTED');
select pg_temp.seed_appointment(35, 'c0f10000-0000-4000-8000-000000000401', '2035-03-08T09:00Z', 'REQUESTED');
select pg_temp.seed_appointment(40, 'c0f10000-0000-4000-8000-000000000401', '2035-03-07T09:00Z', 'REQUESTED');
select pg_temp.seed_appointment(43, 'c0f10000-0000-4000-8000-000000000401', '2035-03-09T09:00Z', 'REQUESTED');
select pg_temp.seed_appointment(44, 'c0f10000-0000-4000-8000-000000000402', '2035-03-09T09:00Z', 'CONFIRMED');

-- b13: a second REQUESTED revision with identical instants and only a
-- different (valid) establishment timezone.
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, source_proposal_id, created_at
) values (
    pg_temp.appt(13), 2, 'REQUESTED', '2035-03-06T09:00Z', '2035-03-06T09:30Z',
    'Atlantic/Canary', 'c0f10000-0000-4000-8000-000000000201', null, '2026-08-05T00:00Z'
);

-- Confirmed histories for the terminal and conflicting Appointments.
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, source_proposal_id, created_at
)
select pg_temp.appt(n), 2, 'CONFIRMED', revision.scheduled_start_at, revision.scheduled_end_at,
       revision.establishment_timezone_name, 'c0f10000-0000-4000-8000-000000000208', null, '2026-08-10T00:00Z'
from unnest(array[31, 32, 44]) as n
join public.appointment_schedule_revisions as revision
  on revision.appointment_id = pg_temp.appt(n) and revision.revision_sequence = 1;

-- The COMPLETED Event carries no clinical evidence (ADR-011).
insert into public.appointment_lifecycle_events (
    appointment_id, from_state, to_state, actor_user_id, actor_context, reason,
    effective_at, recorded_at) values
    (pg_temp.appt(30), 'REQUESTED', 'CANCELLED', 'c0f10000-0000-4000-8000-000000000201', 'GUARDIAN', null, '2026-08-20T00:00Z', '2026-08-20T00:00Z'),
    (pg_temp.appt(31), 'REQUESTED', 'CONFIRMED', 'c0f10000-0000-4000-8000-000000000208', 'CLINIC', null, '2026-08-10T00:00Z', '2026-08-10T00:00Z'),
    (pg_temp.appt(31), 'CONFIRMED', 'COMPLETED', 'c0f10000-0000-4000-8000-000000000208', 'CLINIC', null, '2026-08-21T00:00Z', '2026-08-21T00:00Z'),
    (pg_temp.appt(32), 'REQUESTED', 'CONFIRMED', 'c0f10000-0000-4000-8000-000000000208', 'CLINIC', null, '2026-08-10T00:00Z', '2026-08-10T00:00Z'),
    (pg_temp.appt(32), 'CONFIRMED', 'NO_SHOW', 'c0f10000-0000-4000-8000-000000000208', 'CLINIC', null, '2026-08-21T00:00Z', '2026-08-21T00:00Z'),
    (pg_temp.appt(44), 'REQUESTED', 'CONFIRMED', 'c0f10000-0000-4000-8000-000000000208', 'CLINIC', null, '2026-08-10T00:00Z', '2026-08-10T00:00Z');

insert into public.appointment_veterinarian_assignments (
    appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id
) values
    (pg_temp.appt(40), 'c0f10000-0000-4000-8000-000000000813', '2026-08-02T00:00Z', 'c0f10000-0000-4000-8000-000000000208'),
    (pg_temp.appt(41), 'c0f10000-0000-4000-8000-000000000814', '2020-06-01T00:00Z', 'c0f10000-0000-4000-8000-000000000208'),
    (pg_temp.appt(42), 'c0f10000-0000-4000-8000-000000000815', '2026-08-02T00:00Z', 'c0f10000-0000-4000-8000-000000000208'),
    (pg_temp.appt(43), 'c0f10000-0000-4000-8000-000000000813', '2026-08-02T00:00Z', 'c0f10000-0000-4000-8000-000000000208'),
    (pg_temp.appt(44), 'c0f10000-0000-4000-8000-000000000823', '2026-08-02T00:00Z', 'c0f10000-0000-4000-8000-000000000208');

set local session_replication_role = origin;

-- Fixture sanity: the conditions each case relies on.
select pg_temp.assert_true(
    public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000301', 'APPOINTMENT_MANAGEMENT')
    and public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000302', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000303', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000304', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000305', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000306', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0f10000-0000-4000-8000-000000000307', 'APPOINTMENT_MANAGEMENT'),
    'Fixture: APPOINTMENT_MANAGEMENT available only for ACTIVE-in-validity and CANCELLED-before-valid_until'
);

select pg_temp.assert_true(
    public.clinic_appointment_interval_is_available('c0f10000-0000-4000-8000-000000000401', '2035-03-06T09:00Z', '2035-03-06T09:30Z')
    and not public.clinic_appointment_interval_is_available('c0f10000-0000-4000-8000-000000000401', '2035-03-08T09:00Z', '2035-03-08T09:30Z')
    and public.veterinarian_clinic_assignment_is_current('c0f10000-0000-4000-8000-000000000813')
    and not public.veterinarian_clinic_assignment_is_current('c0f10000-0000-4000-8000-000000000814')
    and public.veterinarian_availability_covers_interval('c0f10000-0000-4000-8000-000000000814', '2035-03-06T09:00Z', '2035-03-06T09:30Z')
    and public.veterinarian_clinic_assignment_is_current('c0f10000-0000-4000-8000-000000000815')
    and not public.veterinarian_availability_covers_interval('c0f10000-0000-4000-8000-000000000815', '2035-03-06T09:00Z', '2035-03-06T09:30Z')
    and (select count(*) = 0 from public.transactional_communications as communication
         where communication.appointment_id::text like 'c0f10000-0000-4000-8000-000000000b%'),
    'Fixture: Availability, Veterinarian Assignment validity, and an empty Communication outbox as expected'
);

-- ===========================================================================
-- 2. Schedule exposes the revision sequence of exactly the returned
--    interval (case 1; SPEC-APT-012 VN 28).
-- ===========================================================================

select pg_temp.act(8);
set local role authenticated;
select pg_temp.capture_schedule('initial', 'c0f10000-0000-4000-8000-000000000401');
reset role;

select pg_temp.act(9);
set local role authenticated;
select pg_temp.capture_schedule('initial', 'c0f10000-0000-4000-8000-000000000402');
reset role;

create function pg_temp.schedule_matches_revisions(p_label text)
returns boolean language sql as $$
    select count(*) > 0
       and bool_and(
           snapshot.current_schedule_revision_sequence is not null
           and snapshot.current_schedule_revision_sequence > 0
           and snapshot.current_schedule_revision_sequence = (
               select max(revision.revision_sequence)
               from public.appointment_schedule_revisions as revision
               where revision.appointment_id = snapshot.id)
           and exists (
               select 1 from public.appointment_schedule_revisions as revision
               where revision.appointment_id = snapshot.id
                 and revision.revision_sequence = snapshot.current_schedule_revision_sequence
                 and revision.scheduled_start_at = snapshot.current_scheduled_start_at
                 and revision.scheduled_end_at = snapshot.current_scheduled_end_at
                 and revision.establishment_timezone_name = snapshot.current_scheduling_timezone_name))
    from schedule_snapshot as snapshot
    where snapshot.label = p_label
$$;

select pg_temp.assert_true(
    pg_temp.schedule_matches_revisions('initial')
    and (select count(*) = 22 from schedule_snapshot where label = 'initial')
    and pg_temp.seen_sequence('initial', pg_temp.appt(10)) = 1
    and pg_temp.seen_sequence('initial', pg_temp.appt(13)) = 2
    and pg_temp.seen_sequence('initial', pg_temp.appt(31)) = 2
    and pg_temp.seen_sequence('initial', pg_temp.appt(32)) = 2
    and pg_temp.seen_sequence('initial', pg_temp.appt(44)) = 2
    and (select current_scheduling_timezone_name = 'Atlantic/Canary' from schedule_snapshot
         where label = 'initial' and id = pg_temp.appt(13)),
    'Case 1: every schedule row exposes the positive sequence of exactly the revision supplying its start, end, and timezone'
);

-- ===========================================================================
-- 3. Invalid expected sequence (cases 7–8) and the removed signature (9).
-- ===========================================================================

select pg_temp.remember('b10 invalid', pg_temp.appt(10));

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(10), null)',
    '22023', 'Expected requested revision sequence must be a positive integer'
);
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(10), 0)',
    '22023', 'Expected requested revision sequence must be a positive integer'
);
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(10), -1)',
    '22023', 'Expected requested revision sequence must be a positive integer'
);
-- Structural validation precedes any Appointment state.
select pg_temp.assert_error(
    'select pg_temp.confirm(''c0f10000-0000-4000-8000-0000000000ff'', 0)',
    '22023', 'Expected requested revision sequence must be a positive integer'
);
select pg_temp.assert_error(
    'select public.confirm_appointment(pg_temp.appt(10))',
    '42883', 'confirm_appointment(uuid) does not exist'
);
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged('b10 invalid', pg_temp.appt(10)),
    'Cases 7–9: invalid sequences and the removed signature leave the Appointment and outbox unchanged'
);

-- ===========================================================================
-- 4. Fresh sequence confirms (case 2), with no Veterinarian (case 32);
--    confirming again is a lifecycle rejection, not staleness (case 24).
-- ===========================================================================

select pg_temp.act(8);
set local role authenticated;
select pg_temp.confirm(pg_temp.appt(10), pg_temp.seen_sequence('initial', pg_temp.appt(10)));
reset role;

select pg_temp.assert_true(
    (select lifecycle_state = 'CONFIRMED' from public.appointments where id = pg_temp.appt(10))
    and (select count(*) = 1 from public.appointment_schedule_revisions as revision
         join public.appointment_schedule_revisions as requested
           on requested.appointment_id = revision.appointment_id and requested.revision_sequence = 1
         where revision.appointment_id = pg_temp.appt(10)
           and revision.revision_context = 'CONFIRMED' and revision.revision_sequence = 2
           and revision.established_by_user_id = pg_temp.domain_user(8)
           and (revision.scheduled_start_at, revision.scheduled_end_at, revision.establishment_timezone_name)
               = (requested.scheduled_start_at, requested.scheduled_end_at, requested.establishment_timezone_name))
    and (select count(*) = 1 from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(10) and from_state = 'REQUESTED' and to_state = 'CONFIRMED'
           and actor_user_id = pg_temp.domain_user(8) and actor_context = 'CLINIC')
    and not exists (select 1 from public.appointment_veterinarian_assignments where appointment_id = pg_temp.appt(10))
    and (select requesting_user_id = pg_temp.domain_user(1) and pet_id = 'c0f10000-0000-4000-8000-000000000a01'
                and clinic_id = 'c0f10000-0000-4000-8000-000000000401'
         from public.appointments where id = pg_temp.appt(10))
    and (select count(*) = 1 and bool_and(lifecycle_state = 'ACTIVE') from public.care_authorizations
         where appointment_id = pg_temp.appt(10)),
    'Cases 2/32: the reviewed revision is confirmed without a Veterinarian; requester, Pet, Clinic, and Care Authorization preserved'
);

select pg_temp.remember('b10 confirmed', pg_temp.appt(10));

select pg_temp.act(7);
set local role authenticated;
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(10), 1)',
    '23514', 'Only a REQUESTED Appointment may be confirmed'
);
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(10), 2)',
    '23514', 'Only a REQUESTED Appointment may be confirmed'
);
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged('b10 confirmed', pg_temp.appt(10)),
    'Case 24: re-confirming a CONFIRMED Appointment is a lifecycle rejection with no duplicate state'
);

-- ===========================================================================
-- 5. Guardian reschedule makes the reviewed revision stale (cases 3, 4, 5,
--    31, 40).
-- ===========================================================================

-- G1 moves b11 from 10:00 to 12:00 Madrid (CET, +01:00), creating revision 2.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.reschedule(pg_temp.appt(11), '2035-03-06', '12:00', 3600);
reset role;

select pg_temp.remember('b11 stale', pg_temp.appt(11));

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.confirm(pg_temp.appt(11), %s)', pg_temp.seen_sequence('initial', pg_temp.appt(11))),
    'P0001', 'Stale requested Appointment schedule revision'
);
reset role;

select pg_temp.assert_true(
    pg_temp.seen_sequence('initial', pg_temp.appt(11)) = 1
    and pg_temp.unchanged('b11 stale', pg_temp.appt(11))
    and (select lifecycle_state = 'REQUESTED' from public.appointments where id = pg_temp.appt(11))
    and not exists (select 1 from public.appointment_schedule_revisions
                    where appointment_id = pg_temp.appt(11) and revision_context = 'CONFIRMED')
    and not exists (select 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(11))
    and not exists (select 1 from public.transactional_communications where appointment_id = pg_temp.appt(11)),
    'Cases 3/4: stale revision 1 after the Guardian created revision 2 fails with zero writes and zero Communications'
);

-- Refresh, review revision 2, confirm it.
select pg_temp.act(8);
set local role authenticated;
select pg_temp.capture_schedule('after reschedule', 'c0f10000-0000-4000-8000-000000000401');
reset role;

select pg_temp.assert_true(
    pg_temp.schedule_matches_revisions('after reschedule')
    and pg_temp.seen_sequence('after reschedule', pg_temp.appt(11)) = 2
    and (select current_scheduled_start_at = '2035-03-06T11:00Z' and current_scheduled_end_at = '2035-03-06T11:30Z'
         from schedule_snapshot where label = 'after reschedule' and id = pg_temp.appt(11)),
    'Case 5: the refreshed schedule exposes revision 2 with exactly its own 11:00Z–11:30Z interval'
);

select pg_temp.act(8);
set local role authenticated;
select pg_temp.confirm(pg_temp.appt(11), pg_temp.seen_sequence('after reschedule', pg_temp.appt(11)));
reset role;

select pg_temp.assert_true(
    (select lifecycle_state = 'CONFIRMED' from public.appointments where id = pg_temp.appt(11))
    and (select count(*) = 1 from public.appointment_schedule_revisions
         where appointment_id = pg_temp.appt(11) and revision_context = 'CONFIRMED' and revision_sequence = 3
           and scheduled_start_at = '2035-03-06T11:00Z' and scheduled_end_at = '2035-03-06T11:30Z'),
    'Cases 5/31: after re-reading, revision 2 is confirmed and the commitment is exactly the new 11:00Z–11:30Z interval'
);

-- ===========================================================================
-- 6. Same start, changed duration (case 6) and timezone-only change: the
--    sequence alone decides staleness.
-- ===========================================================================

-- A1's standard duration becomes 45 minutes; G1 resubmits the same 10:00
-- start, which SPEC-APT-004 BR-19 treats as a genuine new revision.
set local session_replication_role = replica;
update public.clinics set standard_appointment_duration_minutes = 45
where id = 'c0f10000-0000-4000-8000-000000000401';
set local session_replication_role = origin;

select pg_temp.act(1);
set local role authenticated;
select pg_temp.reschedule(pg_temp.appt(12), '2035-03-06', '10:00', 3600);
reset role;

set local session_replication_role = replica;
update public.clinics set standard_appointment_duration_minutes = 30
where id = 'c0f10000-0000-4000-8000-000000000401';
set local session_replication_role = origin;

select pg_temp.assert_true(
    (select array_agg(row(revision_sequence, scheduled_start_at, scheduled_end_at)::text order by revision_sequence)
     from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(12))
    = array[row(1, '2035-03-06T09:00Z'::timestamptz, '2035-03-06T09:30Z'::timestamptz)::text,
            row(2, '2035-03-06T09:00Z'::timestamptz, '2035-03-06T09:45Z'::timestamptz)::text],
    'Fixture: b12 revision 2 keeps the 09:00Z start and only extends the end to 09:45Z'
);

select pg_temp.remember('b12 stale', pg_temp.appt(12));
select pg_temp.remember('b13 stale', pg_temp.appt(13));

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(12), 1)',
    'P0001', 'Stale requested Appointment schedule revision'
);
select pg_temp.assert_error(
    'select pg_temp.confirm(pg_temp.appt(13), 1)',
    'P0001', 'Stale requested Appointment schedule revision'
);
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged('b12 stale', pg_temp.appt(12))
    and pg_temp.unchanged('b13 stale', pg_temp.appt(13)),
    'Case 6: an equal start (and equal instants with only another timezone) does not make the superseded revision current'
);

select pg_temp.act(8);
set local role authenticated;
select pg_temp.confirm(pg_temp.appt(12), 2);
select pg_temp.confirm(pg_temp.appt(13), pg_temp.seen_sequence('initial', pg_temp.appt(13)));
reset role;

select pg_temp.assert_true(
    (select count(*) = 1 from public.appointment_schedule_revisions
     where appointment_id = pg_temp.appt(12) and revision_context = 'CONFIRMED' and revision_sequence = 3
       and scheduled_start_at = '2035-03-06T09:00Z' and scheduled_end_at = '2035-03-06T09:45Z')
    and (select count(*) = 1 from public.appointment_schedule_revisions
         where appointment_id = pg_temp.appt(13) and revision_context = 'CONFIRMED' and revision_sequence = 3
           and establishment_timezone_name = 'Atlantic/Canary'),
    'Case 6: the current revision confirms exactly its own end and timezone'
);

-- ===========================================================================
-- 7. Authorization (cases 10–18).
-- ===========================================================================

create function pg_temp.confirm_as(p_user integer, p_appointment integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform pg_temp.confirm(pg_temp.appt(p_appointment), 1);
end;
$$;

create function pg_temp.is_confirmed_by(p_appointment integer, p_user integer)
returns boolean language sql as $$
    select appointment.lifecycle_state = 'CONFIRMED'
       and exists (select 1 from public.appointment_lifecycle_events as lifecycle_event
                   where lifecycle_event.appointment_id = appointment.id
                     and lifecycle_event.to_state = 'CONFIRMED'
                     and lifecycle_event.actor_user_id = pg_temp.domain_user(p_user))
    from public.appointments as appointment
    where appointment.id = pg_temp.appt(p_appointment)
$$;

set local role authenticated;
-- Allowed responsibilities and scopes.
select pg_temp.confirm_as(4, 1);
select pg_temp.confirm_as(5, 2);
select pg_temp.confirm_as(6, 3);
select pg_temp.confirm_as(7, 5);
select pg_temp.confirm_as(8, 6);
reset role;

select pg_temp.remember('b04 denied', pg_temp.appt(4));
select pg_temp.remember('b08 denied', pg_temp.appt(8));

set local role authenticated;
-- Clinic-scoped ADMINISTRATOR / RECEPTIONIST @ A1 on an A2 Appointment.
select pg_temp.assert_error('select pg_temp.confirm_as(6, 4)', '42501', 'Applicable Appointment-management capability is required');
select pg_temp.assert_error('select pg_temp.confirm_as(8, 4)', '42501', 'Applicable Appointment-management capability is required');
-- VETERINARIAN with schedule view only, ended Membership, ended Grant,
-- RECEPTIONIST @ A2 on an A1 Appointment, Guardian.
select pg_temp.assert_error('select pg_temp.confirm_as(10, 8)', '42501', 'Applicable Appointment-management capability is required');
select pg_temp.assert_error('select pg_temp.confirm_as(11, 8)', '42501', 'Applicable Appointment-management capability is required');
select pg_temp.assert_error('select pg_temp.confirm_as(12, 8)', '42501', 'Applicable Appointment-management capability is required');
select pg_temp.assert_error('select pg_temp.confirm_as(9, 8)', '42501', 'Applicable Appointment-management capability is required');
select pg_temp.assert_error('select pg_temp.confirm_as(1, 8)', '42501', 'Applicable Appointment-management capability is required');

-- The VETERINARIAN does hold schedule view at A1.
select pg_temp.act(10);
select pg_temp.capture_schedule('veterinarian view', 'c0f10000-0000-4000-8000-000000000401');
reset role;

select pg_temp.assert_true(
    pg_temp.is_confirmed_by(1, 4) and pg_temp.is_confirmed_by(2, 5) and pg_temp.is_confirmed_by(3, 6)
    and pg_temp.is_confirmed_by(5, 7) and pg_temp.is_confirmed_by(6, 8),
    'Cases 10/11/12/13/14: OWNER, Org and Clinic ADMINISTRATOR, Org and Clinic RECEPTIONIST confirm'
);

select pg_temp.assert_true(
    pg_temp.unchanged('b04 denied', pg_temp.appt(4))
    and pg_temp.unchanged('b08 denied', pg_temp.appt(8))
    and (select count(*) > 0 from schedule_snapshot where label = 'veterinarian view'),
    'Cases 12/14/15/16/17/18: out-of-scope, VETERINARIAN-only, ended Membership/Grant, and Guardian are denied without writes'
);

-- Positive scope controls: the A2 RECEPTIONIST confirms A2; A1 RECEPTIONIST
-- confirms the A1 Appointment the others could not.
set local role authenticated;
select pg_temp.confirm_as(9, 4);
select pg_temp.confirm_as(8, 8);
reset role;

select pg_temp.assert_true(
    pg_temp.is_confirmed_by(4, 9) and pg_temp.is_confirmed_by(8, 8),
    'Cases 12/14/18: Clinic-scoped responsibilities confirm only within their own Clinic'
);

-- ===========================================================================
-- 8. Entitlement (cases 19–23), evaluated for the Clinic's Organization.
-- ===========================================================================

set local role authenticated;
select pg_temp.confirm_as(16, 20);
reset role;

select pg_temp.remember('b' || n, pg_temp.appt(n)) from generate_series(21, 25) as n;

set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.confirm_as(16, %s)', n), '42501', 'Applicable professional Entitlement is required')
from generate_series(21, 25) as n;
reset role;

select pg_temp.assert_true(
    pg_temp.is_confirmed_by(1, 4)
    and pg_temp.is_confirmed_by(20, 16)
    and (select bool_and(pg_temp.unchanged('b' || n, pg_temp.appt(n))) from generate_series(21, 25) as n),
    'Cases 19–23: ACTIVE in validity and CANCELLED before valid_until confirm; PENDING, PAST_DUE, EXPIRED, no Subscription, and lapsed ACTIVE are denied without writes'
);

-- ===========================================================================
-- 9. Lifecycle, concurrency, past time (cases 25–29).
-- ===========================================================================

select pg_temp.remember('b' || n, pg_temp.appt(n)) from unnest(array[30, 31, 32, 34]) as n;

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.confirm(pg_temp.appt(%s), 1)', n), '23514', 'Only a REQUESTED Appointment may be confirmed')
from unnest(array[30, 31, 32]) as n;
select pg_temp.assert_error('select pg_temp.confirm(pg_temp.appt(34), 1)', '23514', 'A past requested Appointment cannot be confirmed');
reset role;

select pg_temp.assert_true(
    (select bool_and(pg_temp.unchanged('b' || n, pg_temp.appt(n))) from unnest(array[30, 31, 32, 34]) as n)
    and (select lifecycle_state = 'REQUESTED' from public.appointments where id = pg_temp.appt(34)),
    'Cases 25/26/27/29: CANCELLED, COMPLETED, NO_SHOW, and past REQUESTED Appointments are not confirmed'
);

-- Two Clinic actors both reviewed revision 1 of b33.
set local role authenticated;
select pg_temp.confirm_as(7, 33);
select pg_temp.assert_error('select pg_temp.confirm_as(8, 33)', '23514', 'Only a REQUESTED Appointment may be confirmed');
reset role;

select pg_temp.assert_true(
    pg_temp.is_confirmed_by(33, 7)
    and (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(33))
    and (select count(*) = 1 from public.appointment_schedule_revisions
         where appointment_id = pg_temp.appt(33) and revision_context = 'CONFIRMED')
    and (select count(*) = 2 from public.transactional_communications where appointment_id = pg_temp.appt(33)),
    'Case 28: the first actor confirms; the second sees a lifecycle rejection; one commitment and one set of Communications'
);

-- ===========================================================================
-- 10. Availability (case 30).
-- ===========================================================================

select pg_temp.remember('b35', pg_temp.appt(35));

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.confirm(pg_temp.appt(35), 1)', '23514', 'Clinic Appointment Availability does not cover the requested interval');
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged('b35', pg_temp.appt(35))
    and (select lifecycle_state = 'REQUESTED' from public.appointments where id = pg_temp.appt(35)),
    'Case 30: Availability removed after the request rejects confirmation; the Appointment stays REQUESTED at its time'
);

-- ===========================================================================
-- 11. Veterinarian (cases 33–36).
-- ===========================================================================

select pg_temp.act(8);
set local role authenticated;
select pg_temp.confirm(pg_temp.appt(40), 1);
reset role;

select pg_temp.remember('b' || n, pg_temp.appt(n)) from unnest(array[41, 42, 43, 44]) as n;

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.confirm(pg_temp.appt(41), 1)', '23514', 'Currently assigned Veterinarian no longer has a valid Clinic Assignment');
select pg_temp.assert_error('select pg_temp.confirm(pg_temp.appt(42), 1)', '23514', 'Currently assigned Veterinarian is not available for the requested interval');
-- b43 passes every in-function check; the deferred cross-Clinic conflict
-- fails it and rolls back the whole operation.
select pg_temp.assert_error('select pg_temp.confirm(pg_temp.appt(43), 1)', '23P01', 'conflicting confirmed Appointment commitments across Clinics');
reset role;

select pg_temp.assert_true(
    pg_temp.is_confirmed_by(40, 8)
    and (select count(*) = 1 from public.appointment_veterinarian_assignments
         where appointment_id = pg_temp.appt(40) and effective_end is null
           and veterinarian_clinic_assignment_id = 'c0f10000-0000-4000-8000-000000000813'),
    'Case 33: a current, available Veterinarian keeps the Assignment and the Appointment is confirmed'
);

select pg_temp.assert_true(
    (select bool_and(pg_temp.unchanged('b' || n, pg_temp.appt(n))) from unnest(array[41, 42, 43, 44]) as n)
    and (select lifecycle_state = 'REQUESTED' from public.appointments where id = pg_temp.appt(43)),
    'Cases 34/35/36: ended Clinic Assignment, missing Veterinarian Availability, and deferred conflict roll back fully, including Communications'
);

-- Concurrent cross-Clinic confirmations of one Veterinarian serialize on the
-- Professional Profile row: the deferred conflict check locks it FOR UPDATE
-- before re-querying, so a second committer waits for the first and then sees
-- its commitment (READ COMMITTED takes a new snapshot per statement). A real
-- two-session run (LOCAL, not source-controlled) showed the second commit
-- failing with 23P01, and both commits succeeding once this lock is removed —
-- which no single-session case above detects. This pins the lock itself.
-- Technique as in professional_management_reads_baseline.sql: a profile row
-- inserted here in replica mode has xmax 0 until locked; the check runs at
-- top level (a subtransaction would record its own xid).
set local session_replication_role = replica;
insert into public.users (id) values (pg_temp.domain_user(17));
insert into public.veterinarian_professional_profiles (id, user_id)
values ('c0f10000-0000-4000-8000-000000000717', pg_temp.domain_user(17));
set local session_replication_role = origin;
select pg_temp.assert_true(
    (select xmax::text = '0' from public.veterinarian_professional_profiles
     where id = 'c0f10000-0000-4000-8000-000000000717'),
    'Fresh Professional Profile row is unlocked'
);
select public.assert_veterinarian_confirmed_commitment_conflict_free('c0f10000-0000-4000-8000-000000000717');
select pg_temp.assert_true(
    (select xmax::text = (pg_current_xact_id()::text::bigint % 4294967296)::text
     from public.veterinarian_professional_profiles
     where id = 'c0f10000-0000-4000-8000-000000000717'),
    'The cross-Clinic conflict check locks the Professional Profile row for this transaction before evaluating'
);

-- ===========================================================================
-- 12. Communications (cases 37–40) and reads (cases 41–42).
-- ===========================================================================

select pg_temp.assert_true(
    (select array_agg(communication.recipient_user_id order by communication.recipient_user_id)
     from public.transactional_communications as communication
     where communication.appointment_id = pg_temp.appt(1))
    = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
    and (select bool_and(
                communication.communication_type = 'APPOINTMENT_CONFIRMED'
                and communication.appointment_lifecycle_event_id = lifecycle_event.id
                and lifecycle_event.to_state = 'CONFIRMED')
         from public.transactional_communications as communication
         join public.appointment_lifecycle_events as lifecycle_event
           on lifecycle_event.appointment_id = communication.appointment_id
         where communication.appointment_id = pg_temp.appt(1)),
    'Case 37: exactly one APPOINTMENT_CONFIRMED per current Guardian, tied to the confirmation Lifecycle Event'
);

select pg_temp.assert_true(
    -- Every successful confirmation produced exactly the two current-Guardian
    -- Communications and nothing else.
    (select bool_and(confirmed_communications.recipients = array[pg_temp.domain_user(1), pg_temp.domain_user(2)])
     from (
         select appointment.id,
                array_agg(communication.recipient_user_id order by communication.recipient_user_id) as recipients
         from public.appointments as appointment
         join public.transactional_communications as communication on communication.appointment_id = appointment.id
         where appointment.id::text like 'c0f10000-0000-4000-8000-000000000b%'
         group by appointment.id
     ) as confirmed_communications)
    -- Exactly the 14 successfully confirmed Appointments.
    and (select array_agg(distinct communication.appointment_id order by communication.appointment_id)
         from public.transactional_communications as communication
         where communication.appointment_id::text like 'c0f10000-0000-4000-8000-000000000b%')
        = (select array_agg(pg_temp.appt(n) order by pg_temp.appt(n))
           from unnest(array[1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 20, 33, 40]) as n)
    and (select count(distinct communication.appointment_id) = 14
         from public.transactional_communications as communication
         where communication.appointment_id::text like 'c0f10000-0000-4000-8000-000000000b%')
    and not exists (
        select 1 from public.transactional_communications as communication
        where communication.appointment_id::text like 'c0f10000-0000-4000-8000-000000000b%'
          and (communication.recipient_user_id = pg_temp.domain_user(3)
               or communication.recipient_user_id not in (pg_temp.domain_user(1), pg_temp.domain_user(2))
               or communication.communication_type <> 'APPOINTMENT_CONFIRMED')),
    'Cases 38/39/40: former Guardians and Clinic actors receive nothing; only the 14 successful confirmations enqueued Communications'
);

select pg_temp.act(4);
set local role authenticated;
select pg_temp.capture_schedule('final', 'c0f10000-0000-4000-8000-000000000401');
reset role;

select pg_temp.act(1);
set local role authenticated;
insert into guardian_snapshot
select 'final', appointment.id, appointment.lifecycle_state, appointment.current_scheduled_start_at
from public.get_pet_appointments('c0f10000-0000-4000-8000-000000000a01') as appointment;
reset role;

select pg_temp.assert_true(
    pg_temp.schedule_matches_revisions('final')
    and (select lifecycle_state = 'CONFIRMED' and current_schedule_revision_sequence = 2
         from schedule_snapshot where label = 'final' and id = pg_temp.appt(1))
    and (select lifecycle_state = 'CONFIRMED' and current_schedule_revision_sequence = 3
                and current_scheduled_start_at = '2035-03-06T11:00Z'
         from schedule_snapshot where label = 'final' and id = pg_temp.appt(11))
    and (select lifecycle_state = 'REQUESTED' and current_schedule_revision_sequence = 1
         from schedule_snapshot where label = 'final' and id = pg_temp.appt(43)),
    'Case 41: the Clinic schedule shows CONFIRMED with the confirmed revision sequence after success'
);

select pg_temp.assert_true(
    (select lifecycle_state = 'CONFIRMED' from guardian_snapshot where label = 'final' and id = pg_temp.appt(1))
    and (select lifecycle_state = 'CONFIRMED' and current_scheduled_start_at = '2035-03-06T11:00Z'
         from guardian_snapshot where label = 'final' and id = pg_temp.appt(11))
    and (select lifecycle_state = 'REQUESTED' from guardian_snapshot where label = 'final' and id = pg_temp.appt(35)),
    'Case 42: the Guardian view shows CONFIRMED (and the confirmed time) after success'
);

-- ===========================================================================
-- 13. Unauthenticated callers.
-- ===========================================================================

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.confirm(pg_temp.appt(43), 1)', '28000', 'Authentication is required');
reset role;

set local role anon;
select pg_temp.assert_error(
    'select public.confirm_appointment(''c0f10000-0000-4000-8000-000000000b43'', 1)',
    '42501', 'permission denied'
);
reset role;

rollback;

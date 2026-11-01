-- Regression suite for the relevant scheduled interval correction
-- (SPEC-APT-011 §4 and VN 19; SPEC-APT-012 §4 and VN 27), migration
-- 20261002090000_appointment_relevant_scheduled_interval.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions are
-- rolled back; superuser test execution is required solely to load a
-- deliberately minimal deterministic Appointment history with establishment
-- triggers bypassed, to validate that history against the same Schedule
-- Revision and lifecycle invariants the trusted operations enforce, and to
-- switch between impersonated Users (same rationale as
-- professional_clinics_spec_org_008.sql).
--
-- Covers both `get_pet_appointments` and `get_clinic_appointment_schedule`:
--   * the relevant scheduled interval for every lifecycle path, including the
--     reproduced defect (confirmed T1 -> accepted reschedule T2 -> CANCELLED
--     must show T2);
--   * the interval equals the Spec definition (latest REQUESTED if never
--     confirmed, otherwise latest CONFIRMED) and is the highest
--     revision_sequence, start/end/timezone taken from one revision;
--   * the selection differs from the previous lifecycle-context predicate
--     only for previously confirmed CANCELLED Appointments whose final
--     confirmed interval differs from their latest requested interval;
--   * pending proposals do not change the interval;
--   * Guardian / Clinic parity;
--   * revision, lifecycle-event, and proposal history unchanged by the reads;
--   * unchanged signatures, attributes, ACLs, and authorization.
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

-- Captured read results (one row per Appointment and read).
create temporary table read_snapshot (
    source text not null,
    ord bigint not null,
    id uuid not null,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposed_start_at timestamptz,
    primary key (source, id)
) on commit drop;

grant select, insert on read_snapshot to authenticated;

create function pg_temp.capture_guardian(p_pet_id uuid)
returns void language sql as $$
    insert into read_snapshot
    select 'guardian', appointment_row.ordinality, appointment_row.id, appointment_row.lifecycle_state,
           appointment_row.current_scheduled_start_at, appointment_row.current_scheduled_end_at,
           appointment_row.current_scheduling_timezone_name, appointment_row.pending_reschedule_proposal_id,
           appointment_row.pending_reschedule_proposed_start_at
    from public.get_pet_appointments(p_pet_id) with ordinality as appointment_row
$$;

create function pg_temp.capture_clinic(p_clinic_id uuid)
returns void language sql as $$
    insert into read_snapshot
    select 'clinic', schedule_row.ordinality, schedule_row.id, schedule_row.lifecycle_state,
           schedule_row.current_scheduled_start_at, schedule_row.current_scheduled_end_at,
           schedule_row.current_scheduling_timezone_name, schedule_row.pending_reschedule_proposal_id,
           schedule_row.pending_reschedule_proposed_start_at
    from public.get_clinic_appointment_schedule(p_clinic_id) with ordinality as schedule_row
$$;

-- Fingerprint of all fixture scheduling history.
create function pg_temp.history_fingerprint()
returns text language sql as $$
    select md5(
        coalesce((select string_agg(revision::text, '|' order by revision.id)
                  from public.appointment_schedule_revisions as revision
                  where revision.appointment_id::text like '1a7e0000-0000-4000-8000-000000000b%'), '')
        || '#' ||
        coalesce((select string_agg(lifecycle_event::text, '|' order by lifecycle_event.id)
                  from public.appointment_lifecycle_events as lifecycle_event
                  where lifecycle_event.appointment_id::text like '1a7e0000-0000-4000-8000-000000000b%'), '')
        || '#' ||
        coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal
                  where proposal.appointment_id::text like '1a7e0000-0000-4000-8000-000000000b%'), '')
        || '#' ||
        coalesce((select string_agg(appointment::text, '|' order by appointment.id)
                  from public.appointments as appointment
                  where appointment.id::text like '1a7e0000-0000-4000-8000-000000000b%'), '')
    )
$$;

-- ===========================================================================
-- 1. Unchanged contracts, attributes, and ACLs.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure)
    = 'TABLE(id uuid, clinic_id uuid, requesting_user_id uuid, reason_for_visit text, guardian_notes text, '
      'lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, '
      'current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, '
      'current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, '
      'pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, '
      'pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, '
      'pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, cancellation_reason text, '
          -- 20261010090000 (SPEC-APT-011 BR-33): provenance of the relevant interval.
          'current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_acceptable boolean, '
          -- 20261106090000 (SPEC-APT-011 BR-35): medical-access state.
          'medical_access_state text)',
    'Contract: get_pet_appointments return signature is unchanged except for '
    'cancellation_reason (20261007090000, SPEC-APT-011 BR-31)'
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
    'Contract: get_clinic_appointment_schedule return signature is unchanged except for '
    'current_schedule_revision_sequence (20261003090000, SPEC-APT-012 BR-43)'
);

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""'])
     from pg_proc as proc
     where proc.oid in ('public.get_pet_appointments(uuid)'::regprocedure,
                        'public.get_clinic_appointment_schedule(uuid)'::regprocedure)),
    'Attributes: both reads keep SECURITY DEFINER, STABLE, empty search_path'
);

-- service_role receives EXECUTE through the platform's default privileges,
-- exactly as for every other client read.
select pg_temp.assert_true(
    (select bool_and(
        (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from aclexplode(proc.proacl) as acl_entry
         where acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE'])
     from pg_proc as proc
     where proc.oid in ('public.get_pet_appointments(uuid)'::regprocedure,
                        'public.get_clinic_appointment_schedule(uuid)'::regprocedure))
    and not has_function_privilege('anon', 'public.get_pet_appointments(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_pet_appointments(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE'),
    'ACL: EXECUTE only for authenticated (plus platform service_role) on both reads'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects 1a7e0000-…-0000000001NN, domain Users …-0000000002NN:
--   01 current Guardian of Luna       03 RECEPTIONIST @ A2 (Clinic)
--   02 RECEPTIONIST @ A1 (Clinic)     04 former Guardian of Luna
--   05 authenticated subject without domain User
--
-- Clinic A1 (…0401) holds every Appointment; A2 (…0402) none.
--
-- Appointments (…0bNN), all for Luna (…0901) at A1. Times are UTC; T = final
-- expected relevant scheduled interval start.
--   b01 REQUESTED                                    T 2035-02-01 09:00
--   b02 REQUESTED, rescheduled 09:00 -> 11:00        T 2035-02-02 11:00
--   b03 REQUESTED 08:00 -> 10:00 -> CANCELLED        T 2035-02-03 10:00
--   b04 CONFIRMED                                    T 2035-02-04 09:00
--   b05 CONFIRMED -> CANCELLED                       T 2035-02-05 09:00
--   b06 CONFIRMED 09:00 (Europe/Madrid) -> accepted 17:00 (Atlantic/Canary)
--       -> CANCELLED  [reproduced defect]            T 2035-02-06 17:00
--   b07 REQUESTED 08:00 -> 09:00, CONFIRMED 09:00 -> accepted 17:00 ->
--       accepted 18:00 -> CANCELLED                  T 2035-02-07 18:00
--   b08 CONFIRMED 09:00 -> accepted 17:00 -> COMPLETED T 2026-09-08 17:00
--   b09 CONFIRMED 09:00 -> accepted 17:00 -> NO_SHOW   T 2026-09-09 17:00
--   b10 CONFIRMED 09:00, pending actionable CLINIC proposal for
--       2035-02-11 10:00                             T 2035-02-10 09:00
--   b11 CONFIRMED 09:00, pending GUARDIAN proposal for 2035-02-13 10:00,
--       then CANCELLED                               T 2035-02-12 09:00
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('1a7e0000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 5) as n;

insert into public.users (id)
select ('1a7e0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 4) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select
    ('1a7e0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
    ('1a7e0000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 4) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('1a7e0000-0000-4000-8000-000000000301', 'Animalia Veterinary Group');

insert into public.clinics (id, organization_id, is_published) values
    ('1a7e0000-0000-4000-8000-000000000401', '1a7e0000-0000-4000-8000-000000000301', true),
    ('1a7e0000-0000-4000-8000-000000000402', '1a7e0000-0000-4000-8000-000000000301', true);

insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    ('1a7e0000-0000-4000-8000-000000000502', '1a7e0000-0000-4000-8000-000000000301', '1a7e0000-0000-4000-8000-000000000202', '2020-01-01Z'),
    ('1a7e0000-0000-4000-8000-000000000503', '1a7e0000-0000-4000-8000-000000000301', '1a7e0000-0000-4000-8000-000000000203', '2020-01-01Z');

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values
    ('1a7e0000-0000-4000-8000-000000000602', '1a7e0000-0000-4000-8000-000000000502', 'RECEPTIONIST', 'CLINIC', '1a7e0000-0000-4000-8000-000000000401', '2020-01-01Z', '1a7e0000-0000-4000-8000-000000000202'),
    ('1a7e0000-0000-4000-8000-000000000603', '1a7e0000-0000-4000-8000-000000000503', 'RECEPTIONIST', 'CLINIC', '1a7e0000-0000-4000-8000-000000000402', '2020-01-01Z', '1a7e0000-0000-4000-8000-000000000202');

insert into public.pets (id, name, species, created_at) values
    ('1a7e0000-0000-4000-8000-000000000901', 'Luna', 'Dog', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('1a7e0000-0000-4000-8000-000000000a01', '1a7e0000-0000-4000-8000-000000000201', '1a7e0000-0000-4000-8000-000000000901', '2020-01-01Z', null),
    ('1a7e0000-0000-4000-8000-000000000a04', '1a7e0000-0000-4000-8000-000000000204', '1a7e0000-0000-4000-8000-000000000901', '2020-01-01Z', '2021-01-01Z');

insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select ('1a7e0000-0000-4000-8000-000000000b' || lpad(n::text, 2, '0'))::uuid,
       '1a7e0000-0000-4000-8000-000000000901', '1a7e0000-0000-4000-8000-000000000401',
       '1a7e0000-0000-4000-8000-000000000201', 'Visit ' || n, state,
       ('2026-08-01T00:00:00Z'::timestamptz + make_interval(hours => n))
from (values
    (1, 'REQUESTED'), (2, 'REQUESTED'), (3, 'CANCELLED'), (4, 'CONFIRMED'), (5, 'CANCELLED'),
    (6, 'CANCELLED'), (7, 'CANCELLED'), (8, 'COMPLETED'), (9, 'NO_SHOW'), (10, 'CONFIRMED'),
    (11, 'CANCELLED')
) as fixture (n, state);

-- Revision ids …0cNS (N = Appointment, S = sequence); Proposal ids …0eNS
-- (S = the resulting/target sequence).
insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, source_proposal_id, created_at
) values
    ('1a7e0000-0000-4000-8000-000000000c11', '1a7e0000-0000-4000-8000-000000000b01', 1, 'REQUESTED', '2035-02-01T09:00Z', '2035-02-01T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T01:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c21', '1a7e0000-0000-4000-8000-000000000b02', 1, 'REQUESTED', '2035-02-02T09:00Z', '2035-02-02T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T02:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c22', '1a7e0000-0000-4000-8000-000000000b02', 2, 'REQUESTED', '2035-02-02T11:00Z', '2035-02-02T11:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-02T02:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c31', '1a7e0000-0000-4000-8000-000000000b03', 1, 'REQUESTED', '2035-02-03T08:00Z', '2035-02-03T08:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T03:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c32', '1a7e0000-0000-4000-8000-000000000b03', 2, 'REQUESTED', '2035-02-03T10:00Z', '2035-02-03T10:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-02T03:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c41', '1a7e0000-0000-4000-8000-000000000b04', 1, 'REQUESTED', '2035-02-04T09:00Z', '2035-02-04T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T04:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c42', '1a7e0000-0000-4000-8000-000000000b04', 2, 'CONFIRMED', '2035-02-04T09:00Z', '2035-02-04T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T04:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c51', '1a7e0000-0000-4000-8000-000000000b05', 1, 'REQUESTED', '2035-02-05T09:00Z', '2035-02-05T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T05:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c52', '1a7e0000-0000-4000-8000-000000000b05', 2, 'CONFIRMED', '2035-02-05T09:00Z', '2035-02-05T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T05:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c61', '1a7e0000-0000-4000-8000-000000000b06', 1, 'REQUESTED', '2035-02-06T09:00Z', '2035-02-06T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T06:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c62', '1a7e0000-0000-4000-8000-000000000b06', 2, 'CONFIRMED', '2035-02-06T09:00Z', '2035-02-06T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T06:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c63', '1a7e0000-0000-4000-8000-000000000b06', 3, 'CONFIRMED', '2035-02-06T17:00Z', '2035-02-06T17:45Z', 'Atlantic/Canary', '1a7e0000-0000-4000-8000-000000000201', '1a7e0000-0000-4000-8000-000000000e63', '2026-08-03T06:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c71', '1a7e0000-0000-4000-8000-000000000b07', 1, 'REQUESTED', '2035-02-07T08:00Z', '2035-02-07T08:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T07:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c72', '1a7e0000-0000-4000-8000-000000000b07', 2, 'REQUESTED', '2035-02-07T09:00Z', '2035-02-07T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-02T07:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c73', '1a7e0000-0000-4000-8000-000000000b07', 3, 'CONFIRMED', '2035-02-07T09:00Z', '2035-02-07T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-03T07:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c74', '1a7e0000-0000-4000-8000-000000000b07', 4, 'CONFIRMED', '2035-02-07T17:00Z', '2035-02-07T17:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', '1a7e0000-0000-4000-8000-000000000e74', '2026-08-04T07:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c75', '1a7e0000-0000-4000-8000-000000000b07', 5, 'CONFIRMED', '2035-02-07T18:00Z', '2035-02-07T18:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', '1a7e0000-0000-4000-8000-000000000e75', '2026-08-05T07:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c81', '1a7e0000-0000-4000-8000-000000000b08', 1, 'REQUESTED', '2026-09-08T09:00Z', '2026-09-08T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T08:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c82', '1a7e0000-0000-4000-8000-000000000b08', 2, 'CONFIRMED', '2026-09-08T09:00Z', '2026-09-08T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T08:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c83', '1a7e0000-0000-4000-8000-000000000b08', 3, 'CONFIRMED', '2026-09-08T17:00Z', '2026-09-08T17:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', '1a7e0000-0000-4000-8000-000000000e83', '2026-08-03T08:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c91', '1a7e0000-0000-4000-8000-000000000b09', 1, 'REQUESTED', '2026-09-09T09:00Z', '2026-09-09T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T09:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c92', '1a7e0000-0000-4000-8000-000000000b09', 2, 'CONFIRMED', '2026-09-09T09:00Z', '2026-09-09T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T09:00Z'),
    ('1a7e0000-0000-4000-8000-000000000c93', '1a7e0000-0000-4000-8000-000000000b09', 3, 'CONFIRMED', '2026-09-09T17:00Z', '2026-09-09T17:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', '1a7e0000-0000-4000-8000-000000000e93', '2026-08-03T09:00Z'),
    ('1a7e0000-0000-4000-8000-000000000ca1', '1a7e0000-0000-4000-8000-000000000b10', 1, 'REQUESTED', '2035-02-10T09:00Z', '2035-02-10T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T10:00Z'),
    ('1a7e0000-0000-4000-8000-000000000ca2', '1a7e0000-0000-4000-8000-000000000b10', 2, 'CONFIRMED', '2035-02-10T09:00Z', '2035-02-10T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T10:00Z'),
    ('1a7e0000-0000-4000-8000-000000000cb1', '1a7e0000-0000-4000-8000-000000000b11', 1, 'REQUESTED', '2035-02-12T09:00Z', '2035-02-12T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000201', null, '2026-08-01T11:00Z'),
    ('1a7e0000-0000-4000-8000-000000000cb2', '1a7e0000-0000-4000-8000-000000000b11', 2, 'CONFIRMED', '2035-02-12T09:00Z', '2035-02-12T09:30Z', 'Europe/Madrid', '1a7e0000-0000-4000-8000-000000000202', null, '2026-08-02T11:00Z');

-- Accepted proposals produce the later CONFIRMED revisions; b10 keeps a
-- PENDING proposal, and b11's proposal was made VOID when b11 was cancelled
-- (SPEC-APT-005 BR-33). Acceptance facts are those of the resulting revision.
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, state, created_at,
    base_revision_context, voided_at, void_reason
) values
    ('1a7e0000-0000-4000-8000-000000000e63', '1a7e0000-0000-4000-8000-000000000b06', '1a7e0000-0000-4000-8000-000000000c62', '2035-02-06T17:00Z', '2035-02-06T17:45Z', 'Atlantic/Canary', 'CLINIC', '1a7e0000-0000-4000-8000-000000000202', 'Veterinarian unavailable', 'ACCEPTED', '2026-08-02T18:00Z', 'CONFIRMED', null, null),
    ('1a7e0000-0000-4000-8000-000000000e74', '1a7e0000-0000-4000-8000-000000000b07', '1a7e0000-0000-4000-8000-000000000c73', '2035-02-07T17:00Z', '2035-02-07T17:30Z', 'Europe/Madrid', 'CLINIC', '1a7e0000-0000-4000-8000-000000000202', 'Veterinarian unavailable', 'ACCEPTED', '2026-08-03T18:00Z', 'CONFIRMED', null, null),
    ('1a7e0000-0000-4000-8000-000000000e75', '1a7e0000-0000-4000-8000-000000000b07', '1a7e0000-0000-4000-8000-000000000c74', '2035-02-07T18:00Z', '2035-02-07T18:30Z', 'Europe/Madrid', 'GUARDIAN', '1a7e0000-0000-4000-8000-000000000201', null, 'ACCEPTED', '2026-08-04T18:00Z', 'CONFIRMED', null, null),
    ('1a7e0000-0000-4000-8000-000000000e83', '1a7e0000-0000-4000-8000-000000000b08', '1a7e0000-0000-4000-8000-000000000c82', '2026-09-08T17:00Z', '2026-09-08T17:30Z', 'Europe/Madrid', 'CLINIC', '1a7e0000-0000-4000-8000-000000000202', 'Veterinarian unavailable', 'ACCEPTED', '2026-08-02T18:00Z', 'CONFIRMED', null, null),
    ('1a7e0000-0000-4000-8000-000000000e93', '1a7e0000-0000-4000-8000-000000000b09', '1a7e0000-0000-4000-8000-000000000c92', '2026-09-09T17:00Z', '2026-09-09T17:30Z', 'Europe/Madrid', 'CLINIC', '1a7e0000-0000-4000-8000-000000000202', 'Veterinarian unavailable', 'ACCEPTED', '2026-08-02T18:00Z', 'CONFIRMED', null, null),
    ('1a7e0000-0000-4000-8000-000000000ea3', '1a7e0000-0000-4000-8000-000000000b10', '1a7e0000-0000-4000-8000-000000000ca2', '2035-02-11T10:00Z', '2035-02-11T10:30Z', 'Europe/Madrid', 'CLINIC', '1a7e0000-0000-4000-8000-000000000202', 'Veterinarian unavailable', 'PENDING', '2026-08-03T10:00Z', 'CONFIRMED', null, null),
    ('1a7e0000-0000-4000-8000-000000000eb3', '1a7e0000-0000-4000-8000-000000000b11', '1a7e0000-0000-4000-8000-000000000cb2', '2035-02-13T10:00Z', '2035-02-13T10:30Z', 'Europe/Madrid', 'GUARDIAN', '1a7e0000-0000-4000-8000-000000000201', null, 'VOID', '2026-08-03T11:00Z', 'CONFIRMED', '2026-08-10T11:00Z', 'APPOINTMENT_LIFECYCLE_CHANGED');

-- Lifecycle Events: one confirmation per confirmed Appointment and one
-- terminal Event per terminal Appointment. The COMPLETED Event carries no
-- clinical evidence (ADR-011).
insert into public.appointment_lifecycle_events (
    appointment_id, from_state, to_state, actor_user_id, actor_context, reason,
    effective_at, recorded_at)
select ('1a7e0000-0000-4000-8000-000000000b' || lpad(n::text, 2, '0'))::uuid,
       'REQUESTED', 'CONFIRMED', '1a7e0000-0000-4000-8000-000000000202', 'CLINIC', null,
       ('2026-08-02T00:00:00Z'::timestamptz + make_interval(hours => n)),
       ('2026-08-02T00:00:00Z'::timestamptz + make_interval(hours => n))
from generate_series(4, 11) as n;

insert into public.appointment_lifecycle_events (
    appointment_id, from_state, to_state, actor_user_id, actor_context, reason,
    effective_at, recorded_at) values
    ('1a7e0000-0000-4000-8000-000000000b03', 'REQUESTED', 'CANCELLED', '1a7e0000-0000-4000-8000-000000000201', 'GUARDIAN', null, '2026-08-10T03:00Z', '2026-08-10T03:00Z'),
    ('1a7e0000-0000-4000-8000-000000000b05', 'CONFIRMED', 'CANCELLED', '1a7e0000-0000-4000-8000-000000000201', 'GUARDIAN', null, '2026-08-10T05:00Z', '2026-08-10T05:00Z'),
    ('1a7e0000-0000-4000-8000-000000000b06', 'CONFIRMED', 'CANCELLED', '1a7e0000-0000-4000-8000-000000000202', 'CLINIC', 'Clinic closed', '2026-08-10T06:00Z', '2026-08-10T06:00Z'),
    ('1a7e0000-0000-4000-8000-000000000b07', 'CONFIRMED', 'CANCELLED', '1a7e0000-0000-4000-8000-000000000201', 'GUARDIAN', null, '2026-08-10T07:00Z', '2026-08-10T07:00Z'),
    ('1a7e0000-0000-4000-8000-000000000b08', 'CONFIRMED', 'COMPLETED', '1a7e0000-0000-4000-8000-000000000202', 'CLINIC', null, '2026-09-08T18:00Z', '2026-09-08T18:00Z'),
    ('1a7e0000-0000-4000-8000-000000000b09', 'CONFIRMED', 'NO_SHOW', '1a7e0000-0000-4000-8000-000000000202', 'CLINIC', null, '2026-09-09T18:00Z', '2026-09-09T18:00Z'),
    ('1a7e0000-0000-4000-8000-000000000b11', 'CONFIRMED', 'CANCELLED', '1a7e0000-0000-4000-8000-000000000201', 'GUARDIAN', null, '2026-08-10T11:00Z', '2026-08-10T11:00Z');

set local session_replication_role = origin;

-- Expected relevant scheduled interval per Appointment, transcribed from the
-- fixture table above (independent of any revision-selection SQL).
create temporary table expected_interval (
    id uuid primary key,
    start_at timestamptz not null,
    end_at timestamptz not null,
    timezone_name text not null
) on commit drop;

insert into expected_interval values
    ('1a7e0000-0000-4000-8000-000000000b01', '2035-02-01T09:00Z', '2035-02-01T09:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b02', '2035-02-02T11:00Z', '2035-02-02T11:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b03', '2035-02-03T10:00Z', '2035-02-03T10:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b04', '2035-02-04T09:00Z', '2035-02-04T09:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b05', '2035-02-05T09:00Z', '2035-02-05T09:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b06', '2035-02-06T17:00Z', '2035-02-06T17:45Z', 'Atlantic/Canary'),
    ('1a7e0000-0000-4000-8000-000000000b07', '2035-02-07T18:00Z', '2035-02-07T18:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b08', '2026-09-08T17:00Z', '2026-09-08T17:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b09', '2026-09-09T17:00Z', '2026-09-09T17:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b10', '2035-02-10T09:00Z', '2035-02-10T09:30Z', 'Europe/Madrid'),
    ('1a7e0000-0000-4000-8000-000000000b11', '2035-02-12T09:00Z', '2035-02-12T09:30Z', 'Europe/Madrid');

-- ===========================================================================
-- 2. The fixture history satisfies the invariants the correction relies on.
-- ===========================================================================

select pg_temp.assert_true(
    not exists (
        select 1
        from public.appointments as appointment
        where appointment.id::text like '1a7e0000-0000-4000-8000-000000000b%'
          and (
              -- contiguous sequence from 1, sequence 1 REQUESTED
              (select count(*) from public.appointment_schedule_revisions as revision
               where revision.appointment_id = appointment.id)
              <> (select max(revision.revision_sequence) from public.appointment_schedule_revisions as revision
                  where revision.appointment_id = appointment.id)
              or (select revision.revision_context from public.appointment_schedule_revisions as revision
                  where revision.appointment_id = appointment.id and revision.revision_sequence = 1)
                 <> 'REQUESTED'
              -- every CONFIRMED revision follows every REQUESTED revision
              or coalesce((select max(revision.revision_sequence) from public.appointment_schedule_revisions as revision
                           where revision.appointment_id = appointment.id and revision.revision_context = 'REQUESTED'), 0)
                 > coalesce((select min(revision.revision_sequence) from public.appointment_schedule_revisions as revision
                             where revision.appointment_id = appointment.id and revision.revision_context = 'CONFIRMED'), 2147483647)
              -- CONFIRMED revisions exist exactly when the Appointment was confirmed
              or exists (select 1 from public.appointment_schedule_revisions as revision
                         where revision.appointment_id = appointment.id and revision.revision_context = 'CONFIRMED')
                 is distinct from exists (
                     select 1 from public.appointment_lifecycle_events as lifecycle_event
                     where lifecycle_event.appointment_id = appointment.id
                       and lifecycle_event.to_state = 'CONFIRMED')
          )
    ),
    'Fixture: Schedule Revision sequence invariants hold'
);

select pg_temp.assert_true(
    not exists (
        -- first CONFIRMED copies the immediately preceding REQUESTED context
        select 1
        from public.appointment_schedule_revisions as first_confirmed
        join public.appointment_schedule_revisions as preceding
          on preceding.appointment_id = first_confirmed.appointment_id
         and preceding.revision_sequence = first_confirmed.revision_sequence - 1
        where first_confirmed.appointment_id::text like '1a7e0000-0000-4000-8000-000000000b%'
          and first_confirmed.revision_context = 'CONFIRMED'
          and preceding.revision_context = 'REQUESTED'
          and (first_confirmed.source_proposal_id is not null
               or (first_confirmed.scheduled_start_at, first_confirmed.scheduled_end_at, first_confirmed.establishment_timezone_name)
                  is distinct from (preceding.scheduled_start_at, preceding.scheduled_end_at, preceding.establishment_timezone_name))
    )
    and not exists (
        -- every later CONFIRMED revision comes from an ACCEPTED Proposal based
        -- on the immediately preceding CONFIRMED revision, with the same context
        select 1
        from public.appointment_schedule_revisions as later_confirmed
        join public.appointment_schedule_revisions as preceding
          on preceding.appointment_id = later_confirmed.appointment_id
         and preceding.revision_sequence = later_confirmed.revision_sequence - 1
        left join public.appointment_reschedule_proposals as proposal
          on proposal.id = later_confirmed.source_proposal_id
        where later_confirmed.appointment_id::text like '1a7e0000-0000-4000-8000-000000000b%'
          and later_confirmed.revision_context = 'CONFIRMED'
          and preceding.revision_context = 'CONFIRMED'
          and (proposal.id is null
               or proposal.state <> 'ACCEPTED'
               or proposal.base_revision_id <> preceding.id
               or (proposal.proposed_start_at, proposal.proposed_end_at, proposal.proposed_timezone_name)
                  is distinct from (later_confirmed.scheduled_start_at, later_confirmed.scheduled_end_at, later_confirmed.establishment_timezone_name))
    ),
    'Fixture: confirmed-revision provenance invariants hold'
);

-- Trusted lifecycle-coherence assertion; completion carries no clinical
-- evidence, so COMPLETED is asserted too.
select public.assert_appointment_lifecycle_coherence(appointment.id)
from public.appointments as appointment
where appointment.id::text like '1a7e0000-0000-4000-8000-000000000b%';

select pg_temp.assert_true(
    (select count(*) = 1 from public.appointment_lifecycle_events
     where appointment_id = '1a7e0000-0000-4000-8000-000000000b08' and to_state = 'COMPLETED')
    and (select count(*) = 1 from public.appointment_lifecycle_events
         where appointment_id = '1a7e0000-0000-4000-8000-000000000b08' and to_state = 'CONFIRMED'),
    'Fixture: the COMPLETED Appointment has one confirmation and one terminal Event'
);

-- ===========================================================================
-- 3. Both reads expose the relevant scheduled interval (VN 19 / VN 27).
-- ===========================================================================

create temporary table history_before (fingerprint text) on commit drop;
insert into history_before select pg_temp.history_fingerprint();

select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000101', true);
set local role authenticated;
select pg_temp.capture_guardian('1a7e0000-0000-4000-8000-000000000901');
reset role;

select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000102', true);
set local role authenticated;
select pg_temp.capture_clinic('1a7e0000-0000-4000-8000-000000000401');
reset role;

select pg_temp.assert_true(
    (select count(*) = 11 from read_snapshot where source = 'guardian')
    and (select count(*) = 11 from read_snapshot where source = 'clinic'),
    'Both reads return every fixture Appointment'
);

-- Cases 1–10: every Appointment, in each read, equals the transcribed expectation.
select pg_temp.assert_true(
    not exists (
        select 1
        from read_snapshot as snapshot
        join expected_interval as expected on expected.id = snapshot.id
        where (snapshot.current_scheduled_start_at, snapshot.current_scheduled_end_at, snapshot.current_scheduling_timezone_name)
              is distinct from (expected.start_at, expected.end_at, expected.timezone_name)
    ),
    'Every lifecycle path exposes its expected relevant scheduled interval in both reads'
);

-- Reproduced defect: confirmed T1 -> accepted T2 -> CANCELLED shows T2.
select pg_temp.assert_true(
    (select bool_and(
         snapshot.current_scheduled_start_at = '2035-02-06T17:00Z'
         and snapshot.current_scheduled_end_at = '2035-02-06T17:45Z'
         and snapshot.current_scheduling_timezone_name = 'Atlantic/Canary'
         and snapshot.lifecycle_state = 'CANCELLED')
     from read_snapshot as snapshot
     where snapshot.id = '1a7e0000-0000-4000-8000-000000000b06')
    and not exists (
        select 1 from read_snapshot as snapshot
        where snapshot.id = '1a7e0000-0000-4000-8000-000000000b06'
          and snapshot.current_scheduled_start_at = '2035-02-06T09:00Z'
    ),
    'Defect: rescheduled-then-CANCELLED Appointment shows T2 (17:00 Atlantic/Canary), never T1 or the requested 09:00'
);

select pg_temp.assert_true(
    (select bool_and(snapshot.current_scheduled_start_at = '2035-02-07T18:00Z')
     from read_snapshot as snapshot
     where snapshot.id = '1a7e0000-0000-4000-8000-000000000b07'),
    'Two accepted reschedules then CANCELLED: final confirmed 18:00, not original 08:00, requested 09:00, or 17:00'
);

-- The Spec definition, evaluated independently: latest REQUESTED if never
-- confirmed, otherwise latest CONFIRMED — and that it is the highest sequence.
select pg_temp.assert_true(
    not exists (
        select 1
        from read_snapshot as snapshot
        cross join lateral (
            select revision.*
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = snapshot.id
              and revision.revision_context = case
                  when exists (select 1 from public.appointment_schedule_revisions as confirmed
                               where confirmed.appointment_id = snapshot.id
                                 and confirmed.revision_context = 'CONFIRMED')
                  then 'CONFIRMED' else 'REQUESTED' end
            order by revision.revision_sequence desc
            limit 1
        ) as by_definition
        cross join lateral (
            select max(revision.revision_sequence) as max_sequence
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = snapshot.id
        ) as highest
        where (snapshot.current_scheduled_start_at, snapshot.current_scheduled_end_at, snapshot.current_scheduling_timezone_name)
              is distinct from (by_definition.scheduled_start_at, by_definition.scheduled_end_at, by_definition.establishment_timezone_name)
           or by_definition.revision_sequence <> highest.max_sequence
    ),
    'Both reads match the Spec definition, which is the highest revision_sequence'
);

-- The previous lifecycle-context predicate yields a different interval only
-- for previously confirmed CANCELLED Appointments with an accepted reschedule.
select pg_temp.assert_true(
    (select array_agg(snapshot.id order by snapshot.id)
     from read_snapshot as snapshot
     join public.appointments as appointment on appointment.id = snapshot.id
     cross join lateral (
         select revision.*
         from public.appointment_schedule_revisions as revision
         where revision.appointment_id = appointment.id
           and revision.revision_context = case
               when appointment.lifecycle_state in ('CONFIRMED', 'COMPLETED', 'NO_SHOW') then 'CONFIRMED'
               else 'REQUESTED' end
         order by revision.revision_sequence desc
         limit 1
     ) as previous_selection
     where snapshot.source = 'guardian'
       and (snapshot.current_scheduled_start_at, snapshot.current_scheduled_end_at, snapshot.current_scheduling_timezone_name)
           is distinct from (previous_selection.scheduled_start_at, previous_selection.scheduled_end_at, previous_selection.establishment_timezone_name))
    = array['1a7e0000-0000-4000-8000-000000000b06', '1a7e0000-0000-4000-8000-000000000b07']::uuid[],
    'Only the rescheduled-then-CANCELLED Appointments differ from the previous selection'
);

-- Case 10: pending proposals do not change the interval.
select pg_temp.assert_true(
    (select bool_and(
         snapshot.current_scheduled_start_at = '2035-02-10T09:00Z'
         and snapshot.pending_reschedule_proposal_id = '1a7e0000-0000-4000-8000-000000000ea3'
         and snapshot.pending_reschedule_proposed_start_at = '2035-02-11T10:00Z')
     from read_snapshot as snapshot
     where snapshot.id = '1a7e0000-0000-4000-8000-000000000b10')
    and (select bool_and(
             snapshot.current_scheduled_start_at = '2035-02-12T09:00Z'
             and snapshot.pending_reschedule_proposal_id is null
             and snapshot.pending_reschedule_proposed_start_at is null)
         from read_snapshot as snapshot
         where snapshot.id = '1a7e0000-0000-4000-8000-000000000b11'),
    'Pending proposals: the confirmed interval is shown; the proposal stays in pending fields only while actionable'
);

-- Case 11: Guardian / Clinic parity for every Appointment.
select pg_temp.assert_true(
    not exists (
        select 1
        from read_snapshot as guardian_row
        full join read_snapshot as clinic_row
          on clinic_row.id = guardian_row.id and clinic_row.source = 'clinic'
        where guardian_row.source = 'guardian'
          and (clinic_row.id is null
               or (guardian_row.lifecycle_state, guardian_row.current_scheduled_start_at,
                   guardian_row.current_scheduled_end_at, guardian_row.current_scheduling_timezone_name,
                   guardian_row.pending_reschedule_proposal_id, guardian_row.pending_reschedule_proposed_start_at)
                  is distinct from
                  (clinic_row.lifecycle_state, clinic_row.current_scheduled_start_at,
                   clinic_row.current_scheduled_end_at, clinic_row.current_scheduling_timezone_name,
                   clinic_row.pending_reschedule_proposal_id, clinic_row.pending_reschedule_proposed_start_at))
    ),
    'Parity: Guardian and Clinic reads expose the identical interval, timezone, and pending proposal'
);

-- Row ordering unchanged: (created_at, id) in both reads.
select pg_temp.assert_true(
    (select array_agg(id order by ord) from read_snapshot where source = 'guardian')
    = (select array_agg(appointment.id order by appointment.created_at, appointment.id)
       from public.appointments as appointment where appointment.pet_id = '1a7e0000-0000-4000-8000-000000000901')
    and (select array_agg(id order by ord) from read_snapshot where source = 'clinic')
    = (select array_agg(appointment.id order by appointment.created_at, appointment.id)
       from public.appointments as appointment where appointment.clinic_id = '1a7e0000-0000-4000-8000-000000000401'),
    'Ordering: both reads still order by (created_at, id)'
);

-- Case 12: history unchanged by the reads.
select pg_temp.assert_true(
    pg_temp.history_fingerprint() = (select fingerprint from history_before),
    'History: Schedule Revisions, Lifecycle Events, Proposals, and Appointments are unchanged by the reads'
);

-- ===========================================================================
-- 4. Authorization unchanged (case 13).
-- ===========================================================================

-- Guardian read.
select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000104', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_pet_appointments(''1a7e0000-0000-4000-8000-000000000901'')',
    '42501', 'Current Guardianship of the Pet is required'
);
reset role;

select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000102', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_pet_appointments(''1a7e0000-0000-4000-8000-000000000901'')',
    '42501', 'Current Guardianship of the Pet is required'
);
reset role;

-- Clinic read.
select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000103', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''1a7e0000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000101', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''1a7e0000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

-- No subject / no domain User, both reads.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_pet_appointments(''1a7e0000-0000-4000-8000-000000000901'')',
    '28000', 'Authentication is required'
);
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''1a7e0000-0000-4000-8000-000000000401'')',
    '28000', 'Authentication is required'
);
reset role;

select set_config('request.jwt.claim.sub', '1a7e0000-0000-4000-8000-000000000105', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_pet_appointments(''1a7e0000-0000-4000-8000-000000000901'')',
    '28000', 'No coherent domain User'
);
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''1a7e0000-0000-4000-8000-000000000401'')',
    '28000', 'No coherent domain User'
);
reset role;

-- anon cannot execute either read.
set local role anon;
select pg_temp.assert_error(
    'select * from public.get_pet_appointments(''1a7e0000-0000-4000-8000-000000000901'')',
    '42501', 'permission denied'
);
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''1a7e0000-0000-4000-8000-000000000401'')',
    '42501', 'permission denied'
);
reset role;

rollback;

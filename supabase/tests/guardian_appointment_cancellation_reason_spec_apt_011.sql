-- Regression suite for SPEC-APT-011 BR-31 — the Guardian Appointment read
-- exposes the cancellation reason of a CANCELLED Appointment; migration
-- 20261007090000_guardian_appointment_cancellation_reason.sql. Section 4
-- covers the same reason in the Clinic Appointment Schedule, migration
-- 20261022090000_clinic_schedule_cancellation_reason.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables, and to switch
-- between impersonated Users.
--
-- Every cancellation, reschedule proposal, and acceptance goes through the
-- real trusted operations, so the read is checked against reasons stored
-- exactly as `cancel_appointment` writes them. Terminal outcomes other than
-- CANCELLED are loaded as fixtures.
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

create function pg_temp.appt(p_n integer) returns uuid language sql immutable as $$
    select ('ca5e0000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('ca5e0000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('ca5e0000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'ca5e0000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic() returns uuid language sql immutable as $$
    select 'ca5e0000-0000-4000-8000-000000000401'::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'ca5e0000-0000-4000-8000-000000000a01'::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

create function pg_temp.cancel(p_n integer, p_context text, p_reason text, p_sequence integer)
returns void language plpgsql as $$
begin
    perform public.cancel_appointment(pg_temp.appt(p_n), p_context, p_reason, p_sequence);
    perform pg_temp.flush();
end;
$$;

-- The Guardian read, as a current Guardian, captured for inspection.
create temporary table guardian_read (
    reader integer, id uuid, lifecycle_state text, reason_for_visit text, guardian_notes text,
    current_scheduled_start_at timestamptz, cancellation_reason text,
    primary key (reader, id)
) on commit drop;
grant select, insert, delete on guardian_read to authenticated;

create function pg_temp.capture(p_reader integer) returns void language plpgsql as $$
begin
    perform pg_temp.act(p_reader);
    delete from guardian_read where reader = p_reader;
    insert into guardian_read
    select p_reader, appointment.id, appointment.lifecycle_state, appointment.reason_for_visit,
           appointment.guardian_notes, appointment.current_scheduled_start_at,
           appointment.cancellation_reason
    from public.get_pet_appointments(pg_temp.luna()) as appointment;
end;
$$;

create function pg_temp.read_of(p_n integer) returns guardian_read language sql as $$
    select * from guardian_read where reader = 1 and id = pg_temp.appt(p_n)
$$;

-- Every persisted fact for the fixture Appointments, and the outbox size.
create function pg_temp.fingerprint() returns text language sql as $$
    select md5(
        coalesce((select string_agg(appointment::text, '|' order by appointment.id)
                  from public.appointments as appointment where appointment.pet_id = pg_temp.luna()), '')
        || '#' || coalesce((select string_agg(lifecycle_event::text, '|' order by lifecycle_event.id)
                  from public.appointment_lifecycle_events as lifecycle_event
                  join public.appointments as appointment on appointment.id = lifecycle_event.appointment_id
                  where appointment.pet_id = pg_temp.luna()), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.id)
                  from public.appointment_schedule_revisions as revision
                  join public.appointments as appointment on appointment.id = revision.appointment_id
                  where appointment.pet_id = pg_temp.luna()), '')
        || '#' || (select count(*) from public.transactional_communications)::text
        || '#' || (select count(*) from public.care_authorizations where pet_id = pg_temp.luna())::text
    )
$$;

-- ===========================================================================
-- 1. Contract (case 9).
-- ===========================================================================

select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc as proc
     where proc.proname = 'get_pet_appointments' and proc.pronamespace = 'public'::regnamespace)
    and pg_get_function_arguments('public.get_pet_appointments(uuid)'::regprocedure) = 'p_pet_id uuid'
    and pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure)
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
          'medical_access_state text)'
    and (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
         from pg_proc as proc where proc.oid = 'public.get_pet_appointments(uuid)'::regprocedure)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.oid = 'public.get_pet_appointments(uuid)'::regprocedure
           and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.get_pet_appointments(uuid)', 'EXECUTE'),
    'Case 9: one get_pet_appointments(uuid), previous columns in order plus only cancellation_reason last; STABLE, SECURITY DEFINER, empty search_path, unchanged ACL'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects ca5e0000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current)   03 former Guardian G3
--   02 Guardian G2 (current)   04 OrgA RECEPTIONIST (Organization scope)
-- OrgA ACTIVE operates Clinic 0401 (Europe/Madrid, 30 minutes, Available
-- 08:00–20:00 every weekday). Every Appointment is Luna's; Appointment n has
-- Care Authorization c<n>. FUTURE = 2035 (CET, +01:00).
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('ca5e0000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 4) as n;
insert into public.users (id) select pg_temp.domain_user(n) from generate_series(1, 4) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('ca5e0000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 4) as n;

insert into public.veterinary_organizations (id, display_name)
values ('ca5e0000-0000-4000-8000-000000000301', 'Animalia Veterinary Group');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.clinic(), 'ca5e0000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30);
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(), weekday, '08:00', '20:00' from generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start)
values ('ca5e0000-0000-4000-8000-000000000504', 'ca5e0000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z');
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values ('ca5e0000-0000-4000-8000-000000000604', 'ca5e0000-0000-4000-8000-000000000504',
          'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4));

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values ('ca5e0000-0000-4000-8000-000000000901', 'ca5e0000-0000-4000-8000-000000000301', '2020-01-01Z',
          'ACTIVE', '2020-01-01Z', null, null, 'spec-apt-011-test', 'ca5e0000-0000-4000-8000-000000000991');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('ca5e0000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null),
    ('ca5e0000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z', null),
    ('ca5e0000-0000-4000-8000-000000000a13', pg_temp.domain_user(3), pg_temp.luna(), '2020-01-01Z', '2021-01-01Z');

-- An Appointment with revision 1 REQUESTED and an ACTIVE Care Authorization;
-- unless REQUESTED or EXPIRED, revision 2 CONFIRMED and its confirmation Event.
create function pg_temp.seed(
    p_n integer, p_start timestamptz, p_state text, p_reason_for_visit text, p_notes text
)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, guardian_notes, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), pg_temp.clinic(), pg_temp.domain_user(1), p_reason_for_visit, p_notes,
            p_state, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
              pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) values (pg_temp.ca(p_n), pg_temp.luna(), pg_temp.clinic(), 'ca5e0000-0000-4000-8000-000000000301',
              'ca5e0000-0000-4000-8000-000000000a11', '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n),
              'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE');
    if p_state not in ('REQUESTED', 'EXPIRED') then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
        ) values (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
                  pg_temp.domain_user(4), null, '2026-02-01T00:00:00Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(4), 'CLINIC', null,
                  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
    end if;
end;
$$;

-- Cancelled in-suite (1–6).
select pg_temp.seed(1, '2035-03-05T09:00Z', 'REQUESTED', 'Vaccination', null);
select pg_temp.seed(2, '2035-03-05T10:00Z', 'REQUESTED', 'Vaccination', null);
select pg_temp.seed(3, '2035-03-05T11:00Z', 'REQUESTED', 'Annual check-up', 'Bring her card');
select pg_temp.seed(4, '2035-03-06T09:00Z', 'CONFIRMED', 'Limping since yesterday', 'Prefers mornings');
select pg_temp.seed(5, '2035-03-06T10:00Z', 'CONFIRMED', 'Skin rash', null);
select pg_temp.seed(6, '2035-03-06T11:00Z', 'CONFIRMED', 'Dental cleaning', null);
-- Never cancelled (7–11).
select pg_temp.seed(7, '2035-03-07T09:00Z', 'REQUESTED', 'Clinic closed that day', null);
select pg_temp.seed(8, '2035-03-07T10:00Z', 'CONFIRMED', 'Follow-up', null);
select pg_temp.seed(9, '2026-06-01T10:00Z', 'COMPLETED', 'Follow-up', null);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(9), 'CONFIRMED', 'COMPLETED', pg_temp.domain_user(4), 'CLINIC', null, '2026-06-01T11:00Z', '2026-06-01T11:00Z');
select pg_temp.seed(10, '2026-06-01T10:00Z', 'NO_SHOW', 'Follow-up', null);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(10), 'CONFIRMED', 'NO_SHOW', pg_temp.domain_user(4), 'CLINIC', null, '2026-06-01T11:00Z', '2026-06-01T11:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T11:00Z', ended_reason = 'APPOINTMENT_NO_SHOW' where id = pg_temp.ca(10);
select pg_temp.seed(11, '2026-06-01T10:00Z', 'EXPIRED', 'Follow-up', null);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(11), 'REQUESTED', 'EXPIRED', null, 'SYSTEM', null, '2026-06-01T10:00Z', '2026-06-01T10:05Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T10:00Z', ended_reason = 'APPOINTMENT_EXPIRED' where id = pg_temp.ca(11);

set local session_replication_role = origin;

-- ===========================================================================
-- 2. Cancellations through the real trusted operations.
-- ===========================================================================

set local role authenticated;
-- 1: Guardian, REQUESTED, with a reason (normalized on write); 2: without one.
select pg_temp.act(1);
select pg_temp.cancel(1, 'GUARDIAN', '  We moved house  ', null);
select pg_temp.cancel(2, 'GUARDIAN', null, null);
-- 6: Guardian, CONFIRMED.
select pg_temp.cancel(6, 'GUARDIAN', 'Feeling better', null);
-- 3: Clinic, REQUESTED; 4: Clinic, CONFIRMED.
select pg_temp.act(4);
select pg_temp.cancel(3, 'CLINIC', 'Clinic closed that day', 1);
select pg_temp.cancel(4, 'CLINIC', 'Veterinarian unavailable', 2);
-- 5: a Clinic proposal (with its own reason) accepted by a Guardian, then a
-- Clinic cancellation of the new confirmed revision 3.
create temporary table proposal_5 on commit drop as
select public.propose_confirmed_appointment_reschedule(
    pg_temp.appt(5), 'CLINIC', '2035-03-06', '15:00', 3600, 'Room unavailable', 2
) as id;
select pg_temp.flush();
select pg_temp.act(1);
select public.accept_appointment_reschedule_proposal((select id from proposal_5), 'GUARDIAN');
select pg_temp.flush();
select pg_temp.act(4);
select pg_temp.cancel(5, 'CLINIC', 'Equipment failure', 3);
-- 8 stays CONFIRMED with a still-pending Clinic proposal whose reason must
-- never surface as a cancellation reason.
select public.propose_confirmed_appointment_reschedule(
    pg_temp.appt(8), 'CLINIC', '2035-03-07', '15:00', 3600, 'Surgery overrun', 2
);
select pg_temp.flush();
reset role;

-- ===========================================================================
-- 3. The Guardian read (cases 1–8, 10).
-- ===========================================================================

create temporary table before_read on commit drop as select pg_temp.fingerprint() as fingerprint;

set local role authenticated;
select pg_temp.capture(1);
select pg_temp.capture(2);
-- Former Guardians receive nothing, cancellation reasons included.
select pg_temp.act(3);
select pg_temp.assert_error(format('select * from public.get_pet_appointments(%L)', pg_temp.luna()),
                            '42501', 'Current Guardianship of the Pet is required');
reset role;

select pg_temp.assert_true(
    (select lifecycle_state = 'CANCELLED' and cancellation_reason = 'We moved house' from pg_temp.read_of(1))
    and (select lifecycle_state = 'CANCELLED' and cancellation_reason is null from pg_temp.read_of(2))
    and (select lifecycle_state = 'CANCELLED' and cancellation_reason = 'Feeling better' from pg_temp.read_of(6)),
    'Cases 1/3/4: Guardian cancellations of REQUESTED and CONFIRMED Appointments expose the stored (normalized) reason, and none when no reason was given'
);

select pg_temp.assert_true(
    (select lifecycle_state = 'CANCELLED' and cancellation_reason = 'Clinic closed that day' from pg_temp.read_of(3))
    and (select lifecycle_state = 'CANCELLED' and cancellation_reason = 'Veterinarian unavailable' from pg_temp.read_of(4)),
    'Cases 2/3/4: Clinic cancellations of REQUESTED and CONFIRMED Appointments expose exactly the Clinic reason'
);

select pg_temp.assert_true(
    (select cancellation_reason = 'Equipment failure'
            and current_scheduled_start_at = '2035-03-06T14:00Z'
     from pg_temp.read_of(5)),
    'Case 5: after an accepted confirmed reschedule, the interval is the latest confirmed one and the reason is the cancellation''s, not the proposal''s'
);

select pg_temp.assert_true(
    (select bool_and(cancellation_reason is null) from guardian_read
     where reader = 1 and id in (pg_temp.appt(7), pg_temp.appt(8), pg_temp.appt(9), pg_temp.appt(10), pg_temp.appt(11)))
    and (select array_agg(lifecycle_state order by id) from guardian_read
         where reader = 1 and id in (pg_temp.appt(7), pg_temp.appt(8), pg_temp.appt(9), pg_temp.appt(10), pg_temp.appt(11)))
        = array['REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'],
    'Case 6: REQUESTED, CONFIRMED, COMPLETED, NO_SHOW, and EXPIRED expose no cancellation reason'
);

select pg_temp.assert_true(
    (select reason_for_visit = 'Annual check-up' and guardian_notes = 'Bring her card'
            and cancellation_reason = 'Clinic closed that day' from pg_temp.read_of(3))
    and (select reason_for_visit = 'Limping since yesterday' and guardian_notes = 'Prefers mornings'
            and cancellation_reason = 'Veterinarian unavailable' from pg_temp.read_of(4))
    -- A reason for visit equal to another Appointment's cancellation reason
    -- never becomes a cancellation reason.
    and (select reason_for_visit = 'Clinic closed that day' and cancellation_reason is null from pg_temp.read_of(7)),
    'Case 7: reason for visit, Guardian notes, and cancellation reason stay separate and never substitute for each other'
);

select pg_temp.assert_true(
    (select count(*) = 11 from guardian_read where reader = 1)
    and not exists (
        select 1 from guardian_read as first_reader
        join guardian_read as second_reader
          on second_reader.reader = 2 and second_reader.id = first_reader.id
        where first_reader.reader = 1
          and (first_reader.cancellation_reason is distinct from second_reader.cancellation_reason
               or first_reader.lifecycle_state is distinct from second_reader.lifecycle_state)),
    'Shared Guardians see the same Appointments and the same cancellation reasons'
);

select pg_temp.assert_true(
    (select fingerprint from before_read) = pg_temp.fingerprint(),
    'Case 8: reading creates no Lifecycle Event, revision, Care Authorization change, or Communication'
);

-- Case 10: the only Lifecycle Event reason exposed is the CANCELLED one; the
-- result columns (case 9) carry no actor, context, Event time, or medical field.
select pg_temp.assert_true(
    (select count(*) = 6 from guardian_read where reader = 1 and cancellation_reason is not distinct from (
        select lifecycle_event.reason from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = guardian_read.id and lifecycle_event.to_state = 'CANCELLED'
    ) and lifecycle_state = 'CANCELLED')
    and not exists (select 1 from guardian_read where reader = 1
                    and cancellation_reason in ('Room unavailable', 'Surgery overrun')),
    'Case 10: each cancellation reason is its own CANCELLED Event''s reason, and no accepted or pending Proposal reason is exposed'
);

-- ===========================================================================
-- 4. The Clinic Appointment Schedule (migration
--    20261022090000_clinic_schedule_cancellation_reason.sql; SPEC-APT-012 §4,
--    SPEC-APT-003 BR-8/BR-9): the same recorded reason, from the same Event.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)
        like '%pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)'
    and (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
         from pg_proc as proc where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure)
    and has_function_privilege('authenticated', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE')
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure) not like '%actor%',
    'Case 11: the Clinic read appends only cancellation_reason text last, with unchanged attributes and ACL, and no actor column'
);

create temporary table clinic_read (id uuid primary key, lifecycle_state text, cancellation_reason text) on commit drop;
grant select, insert on clinic_read to authenticated;

set local role authenticated;
select pg_temp.act(4);
insert into clinic_read
select appointment.id, appointment.lifecycle_state, appointment.cancellation_reason
from public.get_clinic_appointment_schedule(pg_temp.clinic()) as appointment;
reset role;

select pg_temp.assert_true(
    (select count(*) = 11 from clinic_read)
    and (select cancellation_reason = 'Clinic closed that day' from clinic_read where id = pg_temp.appt(3))
    and (select cancellation_reason = 'Veterinarian unavailable' from clinic_read where id = pg_temp.appt(4))
    and (select cancellation_reason = 'Equipment failure' from clinic_read where id = pg_temp.appt(5))
    and (select cancellation_reason = 'We moved house' from clinic_read where id = pg_temp.appt(1))
    and (select cancellation_reason is null and lifecycle_state = 'CANCELLED' from clinic_read where id = pg_temp.appt(2)),
    'Case 12: the Clinic sees the reason it recorded (REQUESTED, CONFIRMED, after an accepted reschedule) and a Guardian''s, and none when none was given'
);

select pg_temp.assert_true(
    not exists (
        select 1 from clinic_read
        join guardian_read on guardian_read.reader = 1 and guardian_read.id = clinic_read.id
        where clinic_read.cancellation_reason is distinct from guardian_read.cancellation_reason
           or clinic_read.lifecycle_state is distinct from guardian_read.lifecycle_state)
    and (select bool_and(cancellation_reason is null) from clinic_read where lifecycle_state <> 'CANCELLED')
    and not exists (select 1 from clinic_read where cancellation_reason in ('Room unavailable', 'Surgery overrun')),
    'Case 13: the Clinic and Guardian reads expose the same cancellation reason; non-cancelled states and proposal reasons never appear as one'
);

select pg_temp.assert_true(
    (select fingerprint from before_read) = pg_temp.fingerprint(),
    'Case 14: the Clinic read writes nothing'
);

rollback;

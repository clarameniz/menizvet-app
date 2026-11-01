-- Regression suite for migration
-- 20261016090000_reschedule_proposal_current_feasibility.sql:
--   SPEC-APT-005 BR-34 (current scheduling feasibility), BR-35 (Guardian
--   current acceptability); SPEC-APT-011 BR-32
--   (pending_reschedule_currently_acceptable); SPEC-APT-012 BR-44
--   (pending_reschedule_currently_feasible); SPEC-APT-006 BR-26, BR-36;
--   SPEC-APT-016 BR-4; SPEC-APT-019 BR-6; SPEC-COM-003 BR-70, BR-72.
--
-- Both values are derived at read time for the projected actionable PENDING
-- proposal only, flip in both directions with scheduling (and, for the
-- Guardian value on a CONFIRMED base, Entitlement) state, never change the
-- proposal, never hide it, never block withdrawal, never replace the
-- authoritative acceptance checks, and never affect Communication delivery.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load fixtures and to change scheduling,
-- Veterinarian, timezone, and Subscription state with fixture triggers
-- bypassed. Every behavioral call goes through the real trusted operations as
-- the `authenticated` role.
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
    select ('fe500000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('fe500000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('fe500000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'fe500000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('fe500000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'fe500000-0000-4000-8000-000000000a01'::uuid
$$;
create function pg_temp.vca(p_n integer) returns uuid language sql immutable as $$
    select ('fe500000-0000-4000-8000-0000000008' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

create temporary table ids (name text primary key, id uuid not null) on commit drop;
grant select, insert, update on ids to authenticated;
create function pg_temp.id(p_name text) returns uuid language sql as $$
    select id from ids where name = p_name
$$;
create function pg_temp.keep(p_name text, p_id uuid) returns uuid language sql as $$
    insert into ids values (p_name, p_id) on conflict (name) do update set id = excluded.id returning id
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.confirmed_propose(p_user integer, p_n integer, p_context text, p_date date, p_time time)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_confirmed_appointment_reschedule(
        pg_temp.appt(p_n), p_context, p_date, p_time, 7200,
        case when p_context = 'CLINIC' then 'Room unavailable' end,
        case when p_context = 'CLINIC' then 2 end
    );
    perform pg_temp.flush();
    return created;
end;
$$;

create function pg_temp.alt_propose(p_user integer, p_n integer, p_date date, p_time time)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_requested_appointment_alternative_time(
        pg_temp.appt(p_n), p_date, p_time, 7200, 'No veterinarian free', 1
    );
    perform pg_temp.flush();
    return created;
end;
$$;

create function pg_temp.confirmed_accept(p_user integer, p_proposal uuid)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.accept_appointment_reschedule_proposal(p_proposal, 'GUARDIAN');
    perform pg_temp.flush();
end;
$$;

create function pg_temp.alt_accept(p_user integer, p_proposal uuid)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.accept_requested_appointment_alternative_time(p_proposal);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.withdraw(p_user integer, p_proposal uuid)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.withdraw_appointment_reschedule_proposal(p_proposal);
    perform pg_temp.flush();
end;
$$;

-- What each read projects for one Appointment: the projected proposal id and
-- its derived value ('id|value', with NULLs spelled out).
create function pg_temp.guardian(p_n integer) returns text language plpgsql as $$
declare result text;
begin
    perform pg_temp.act(1);
    select coalesce(read_row.pending_reschedule_proposal_id::text, 'null') || '|'
           || coalesce(read_row.pending_reschedule_currently_acceptable::text, 'null')
    into result
    from public.get_pet_appointments(pg_temp.luna()) as read_row
    where read_row.id = pg_temp.appt(p_n);
    return result;
end;
$$;

create function pg_temp.clinic_read(p_n integer) returns text language plpgsql as $$
declare result text;
begin
    perform pg_temp.act(4);
    select coalesce(read_row.pending_reschedule_proposal_id::text, 'null') || '|'
           || coalesce(read_row.pending_reschedule_currently_feasible::text, 'null')
    into result
    from public.get_clinic_appointment_schedule(pg_temp.clinic(1)) as read_row
    where read_row.id = pg_temp.appt(p_n);
    return result;
end;
$$;

-- Expected projection text for a proposal and value.
create function pg_temp.shown(p_name text, p_value boolean) returns text language sql as $$
    select pg_temp.id(p_name)::text || '|' || p_value::text
$$;

create function pg_temp.proposal(p_id uuid) returns public.appointment_reschedule_proposals language sql as $$
    select * from public.appointment_reschedule_proposals where id = p_id
$$;

create function pg_temp.eligible(p_proposal uuid) returns boolean language sql as $$
    select bool_and(public.communication_delivery_is_currently_eligible(communication.id, 'EMAIL', null, null))
    from public.transactional_communications as communication
    where communication.appointment_reschedule_proposal_id = p_proposal
      and communication.communication_type in ('APPOINTMENT_RESCHEDULE_PROPOSED', 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED')
$$;

-- Every persisted fact an operation could touch for one Appointment.
create function pg_temp.fingerprint(p_n integer) returns text language sql as $$
    select md5(
        coalesce((select appointment::text from public.appointments as appointment
                  where appointment.id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.revision_sequence)
                  from public.appointment_schedule_revisions as revision
                  where revision.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal
                  where proposal.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication
                  where communication.appointment_id = pg_temp.appt(p_n)), '')
    )
$$;
create temporary table remembered (n integer primary key, fingerprint text not null) on commit drop;
create function pg_temp.remember(p_n integer) returns void language sql as $$
    insert into remembered values (p_n, pg_temp.fingerprint(p_n))
    on conflict (n) do update set fingerprint = excluded.fingerprint
$$;
create function pg_temp.unchanged(p_n integer) returns boolean language sql as $$
    select pg_temp.fingerprint(p_n) = fingerprint from remembered where n = p_n
$$;

-- ===========================================================================
-- 1. Contract.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure)
        like '%current_schedule_source_proposing_context text, pending_reschedule_currently_acceptable boolean, medical_access_state text)'
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)
        like '%current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)'
    -- No reason column: the only text columns that carry a reason are the
    -- pre-existing proposal and cancellation reasons.
    and pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure) not like '%feasib%'
    and pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure) not like '%infeasibility%'
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure) not like '%acceptable%'
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure) not like '%infeasibility%',
    'Contract: each read appends exactly its one generic boolean and no reason'
);

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
                     and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                     and not has_function_privilege('anon', proc.oid, 'EXECUTE'))
     from pg_proc as proc
     where proc.oid in ('public.get_pet_appointments(uuid)'::regprocedure,
                        'public.get_clinic_appointment_schedule(uuid)'::regprocedure))
    and not (select bool_or(has_function_privilege(role_name, signature, 'EXECUTE'))
             from unnest(array['anon', 'authenticated']) as role_name,
                  unnest(array[
                      'public.appointment_reschedule_proposal_is_currently_feasible(uuid, text)',
                      'public.appointment_reschedule_proposal_is_guardian_acceptable(uuid, text)'
                  ]) as signature),
    'Contract: reads are STABLE SECURITY DEFINER for authenticated only; the derived helpers are internal'
);

-- Actionability is untouched: same signature, no feasibility, timezone, or
-- Entitlement inside it.
select pg_temp.assert_true(
    (select pg_get_function_identity_arguments(proc.oid) = 'p_proposal_id uuid, p_as_of timestamp with time zone'
            and proc.prosrc !~* 'infeasib|availability|timezone|entitlement'
     from pg_proc as proc
     where proc.oid = 'public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz)'::regprocedure),
    'Contract: appointment_reschedule_proposal_is_actionable is unchanged'
);

-- ===========================================================================
-- Fixtures
--
-- Auth subjects fe500000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current, requester)   07 OrgA RECEPTIONIST (Org)
--   04 OrgA OWNER                          10 VETERINARIAN @ A1 (vca 10)
-- OrgA ACTIVE (toggled to PAST_DUE in-suite); A1 0401 unpublished,
-- Europe/Madrid, 30-minute standard duration, Appointment Availability
-- 08:00–20:00 every day; Veterinarian 10 available 08:00–18:00 every day.
-- Every Appointment is Luna's; April 2035 is CEST (+02:00).
-- ===========================================================================

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at)
select ('fe500000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       'feas' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 4, 7, 10]) as n;
insert into public.users (id) select pg_temp.domain_user(n) from unnest(array[1, 4, 7, 10]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('fe500000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 7, 10]) as n;

insert into public.veterinary_organizations (id, display_name)
values ('fe500000-0000-4000-8000-000000000301', 'Feasibility Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.clinic(1), 'fe500000-0000-4000-8000-000000000301', false, 'Europe/Madrid', 30);
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(1), weekday, '08:00', '20:00' from generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    ('fe500000-0000-4000-8000-000000000504', 'fe500000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z'),
    ('fe500000-0000-4000-8000-000000000507', 'fe500000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z'),
    ('fe500000-0000-4000-8000-000000000510', 'fe500000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z');
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values
    ('fe500000-0000-4000-8000-000000000604', 'fe500000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4)),
    ('fe500000-0000-4000-8000-000000000607', 'fe500000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4)),
    ('fe500000-0000-4000-8000-000000000610', 'fe500000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4));
insert into public.veterinarian_professional_profiles (id, user_id)
values ('fe500000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values (pg_temp.vca(10), 'fe500000-0000-4000-8000-000000000710', 'fe500000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z');
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time)
select pg_temp.vca(10), weekday, '08:00', '18:00' from generate_series(1, 7) as weekday;

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values ('fe500000-0000-4000-8000-000000000901', 'fe500000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',
          '2020-01-01Z', null, null, 'feasibility-test', 'fe500000-0000-4000-8000-000000000991');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values ('fe500000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z');

-- An Appointment requested on 2026-01-01 (revision 1) and, when CONFIRMED,
-- confirmed on 2026-02-01 (revision 2, same interval), 30 minutes long.
create function pg_temp.seed(p_n integer, p_start timestamptz, p_state text)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), pg_temp.clinic(1), pg_temp.domain_user(1), 'Visit ' || p_n, p_state,
            '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
              pg_temp.domain_user(1), '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) values (pg_temp.ca(p_n), pg_temp.luna(), pg_temp.clinic(1), 'fe500000-0000-4000-8000-000000000301',
              'fe500000-0000-4000-8000-000000000a11', '2026-01-01T00:00:00Z', 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE');
    if p_state = 'CONFIRMED' then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, created_at
        ) values (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
                  pg_temp.domain_user(4), '2026-02-01T00:00:00Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(4), 'CLINIC', null,
                  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
    end if;
end;
$$;
create function pg_temp.assign_vet(p_n integer) returns void language sql as $$
    insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id)
    values (pg_temp.appt(p_n), pg_temp.vca(10), '2026-02-01T00:00:00Z', pg_temp.domain_user(4))
$$;

select pg_temp.seed(1, '2035-04-02T08:00Z', 'REQUESTED');   -- Alternative Time, Veterinarian 10
select pg_temp.seed(2, '2035-04-02T09:00Z', 'CONFIRMED');   -- confirmed Clinic proposal, Veterinarian 10
select pg_temp.seed(3, '2035-04-02T10:00Z', 'CONFIRMED');   -- Guardian proposal
select pg_temp.seed(4, '2035-04-02T11:00Z', 'CONFIRMED');   -- withdraw while infeasible
select pg_temp.seed(5, '2035-04-02T12:00Z', 'REQUESTED');   -- withdraw while infeasible
select pg_temp.seed(6, '2035-04-02T13:00Z', 'CONFIRMED');   -- lapsed proposal (absent, not false)
select pg_temp.seed(7, '2035-04-02T14:00Z', 'CONFIRMED');   -- pre-existing stored proposal
select pg_temp.seed(8, '2035-04-02T15:00Z', 'CONFIRMED');   -- no proposal (NULL contract)
select pg_temp.assign_vet(n) from unnest(array[1, 2]) as n;
-- A proposal no trusted operation produces now: created long ago, lapsed.
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name,
    proposing_context, proposed_by_user_id, reason, created_at
) values
    ('fe500000-0000-4000-8000-000000000d06', pg_temp.appt(6),
     (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(6) and revision_sequence = 2), 'CONFIRMED',
     '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Long ago', '2026-03-01T00:00Z'),
-- A pre-existing proposal stored before this migration (45 minutes, created
-- under an earlier rule): it is read with the derived value unchanged.
    ('fe500000-0000-4000-8000-000000000d07', pg_temp.appt(7),
     (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(7) and revision_sequence = 2), 'CONFIRMED',
     '2035-04-06T10:00Z', '2035-04-06T10:45Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Earlier rule', '2026-09-01T00:00Z');
select pg_temp.keep('p7', 'fe500000-0000-4000-8000-000000000d07');

set local session_replication_role = origin;

-- ===========================================================================
-- 2. Proposals, all feasible at creation; NULL contract.
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p1', pg_temp.alt_propose(7, 1, '2035-04-03', '12:00'));          -- 10:00Z
select pg_temp.keep('p2', pg_temp.confirmed_propose(7, 2, 'CLINIC', '2035-04-04', '12:00'));
select pg_temp.keep('p3', pg_temp.confirmed_propose(1, 3, 'GUARDIAN', '2035-04-05', '12:00'));
select pg_temp.assert_true(
    pg_temp.guardian(1) = pg_temp.shown('p1', true) and pg_temp.clinic_read(1) = pg_temp.shown('p1', true)
    and pg_temp.guardian(2) = pg_temp.shown('p2', true) and pg_temp.clinic_read(2) = pg_temp.shown('p2', true),
    'A feasible Clinic proposal is acceptable to the Guardian and feasible for the Clinic, on both bases'
);
select pg_temp.assert_true(
    pg_temp.guardian(3) = pg_temp.shown('p3', false) and pg_temp.clinic_read(3) = pg_temp.shown('p3', true),
    'A Guardian proposal is projected to the Guardian as not acceptable (only the Clinic accepts it) while feasible'
);
select pg_temp.assert_true(
    pg_temp.guardian(8) = 'null|null' and pg_temp.clinic_read(8) = 'null|null',
    'Without a projected proposal both derived values are NULL'
);
select pg_temp.assert_true(
    pg_temp.guardian(6) = 'null|null' and pg_temp.clinic_read(6) = 'null|null',
    'A lapsed (non-actionable) proposal is absent from both projections, not projected as false'
);
select pg_temp.assert_true(
    pg_temp.guardian(7) = pg_temp.shown('p7', true) and pg_temp.clinic_read(7) = pg_temp.shown('p7', true),
    'A proposal stored before this migration is read with its derived value; no backfill is needed'
);
reset role;

-- ===========================================================================
-- 3. Scheduling flips, both bases (SPEC-APT-005 BR-34).
-- ===========================================================================

select pg_temp.remember(1);
select pg_temp.remember(2);

-- Clinic Availability: CLOSED exceptions on both proposed dates.
set local session_replication_role = replica;
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
values (pg_temp.clinic(1), '2035-04-03', 'CLOSED'), (pg_temp.clinic(1), '2035-04-04', 'CLOSED');
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.guardian(1) = pg_temp.shown('p1', false) and pg_temp.clinic_read(1) = pg_temp.shown('p1', false)
    and pg_temp.guardian(2) = pg_temp.shown('p2', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', false),
    'A CLOSED exception makes both proposals infeasible and unacceptable; both stay projected'
);
-- Communications stay eligible while infeasible (SPEC-COM-003 BR-70, BR-72).
reset role;
select pg_temp.assert_true(
    pg_temp.eligible(pg_temp.id('p1')) and pg_temp.eligible(pg_temp.id('p2')),
    'Proposal notifications stay deliverable while the proposals are infeasible'
);
-- Acceptance remains authoritative and writes nothing.
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('p1')),
    '23514', 'Clinic Appointment Availability does not cover the proposed interval');
select pg_temp.assert_error(format('select pg_temp.confirmed_accept(1, %L)', pg_temp.id('p2')),
    '23514', 'Clinic Appointment Availability does not cover the proposed interval');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(1) and pg_temp.unchanged(2)
    and (pg_temp.proposal(pg_temp.id('p1'))).state = 'PENDING'
    and (pg_temp.proposal(pg_temp.id('p2'))).state = 'PENDING',
    'Infeasibility changes no proposal; a rejected acceptance writes nothing'
);
set local session_replication_role = replica;
delete from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.clinic(1);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.guardian(1) = pg_temp.shown('p1', true) and pg_temp.clinic_read(2) = pg_temp.shown('p2', true),
    'Clearing the exception makes the same proposals feasible and acceptable again'
);
reset role;

-- Veterinarian Availability: shrink to 08:00–09:00, then restore.
set local session_replication_role = replica;
update public.veterinarian_availability_periods set end_time = '09:00' where veterinarian_clinic_assignment_id = pg_temp.vca(10);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.guardian(1) = pg_temp.shown('p1', false) and pg_temp.clinic_read(1) = pg_temp.shown('p1', false)
    and pg_temp.guardian(2) = pg_temp.shown('p2', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', false),
    'Losing the assigned Veterinarian''s Availability makes both proposals infeasible'
);
reset role;
set local session_replication_role = replica;
update public.veterinarian_availability_periods set end_time = '18:00' where veterinarian_clinic_assignment_id = pg_temp.vca(10);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(1) = pg_temp.shown('p1', true) and pg_temp.clinic_read(2) = pg_temp.shown('p2', true),
    'Restoring the Veterinarian''s Availability restores feasibility'
);
reset role;

-- Veterinarian conflict: a competing CONFIRMED booking of Veterinarian 10 at
-- both proposed intervals, then cancelled.
set local session_replication_role = replica;
select pg_temp.seed(21, '2035-04-03T10:00Z', 'CONFIRMED');
select pg_temp.seed(22, '2035-04-04T10:00Z', 'CONFIRMED');
select pg_temp.assign_vet(n) from unnest(array[21, 22]) as n;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.guardian(1) = pg_temp.shown('p1', false) and pg_temp.clinic_read(1) = pg_temp.shown('p1', false)
    and pg_temp.guardian(2) = pg_temp.shown('p2', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', false),
    'A competing confirmed booking of the assigned Veterinarian makes both proposals infeasible'
);
select pg_temp.act(4);
select public.cancel_appointment(pg_temp.appt(n), 'CLINIC', 'Moved', 2) from unnest(array[21, 22]) as n;
select pg_temp.flush();
select pg_temp.assert_true(
    pg_temp.guardian(1) = pg_temp.shown('p1', true) and pg_temp.clinic_read(2) = pg_temp.shown('p2', true),
    'Cancelling the competing booking restores feasibility'
);
reset role;

-- Veterinarian Clinic Assignment ended, then restored.
set local session_replication_role = replica;
update public.veterinarian_clinic_assignments set effective_end = '2021-01-01Z' where id = pg_temp.vca(10);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(1) = pg_temp.shown('p1', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', false)
    and pg_temp.guardian(1) = pg_temp.shown('p1', false) and pg_temp.guardian(2) = pg_temp.shown('p2', false),
    'An ended Clinic Assignment of the assigned Veterinarian makes both proposals infeasible'
);
reset role;
set local session_replication_role = replica;
update public.veterinarian_clinic_assignments set effective_end = null where id = pg_temp.vca(10);
set local session_replication_role = origin;

-- Current Clinic timezone: missing, then invalid, then valid again. The
-- proposals' stored timezone is untouched and not used.
set local session_replication_role = replica;
update public.clinics set scheduling_timezone_name = null where id = pg_temp.clinic(1);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(1) = pg_temp.shown('p1', false) and pg_temp.guardian(2) = pg_temp.shown('p2', false),
    'A missing current Clinic timezone makes proposals infeasible; they stay projected'
);
reset role;
set local session_replication_role = replica;
update public.clinics set scheduling_timezone_name = 'Invalid/Not_A_Zone' where id = pg_temp.clinic(1);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(2) = pg_temp.shown('p2', false) and pg_temp.guardian(1) = pg_temp.shown('p1', false),
    'An invalid current Clinic timezone makes proposals infeasible, even though each proposal stores a valid one'
);
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p1'))).proposed_timezone_name = 'Europe/Madrid'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_timezone_name = 'Europe/Madrid',
    'The proposals keep their stored timezone'
);
-- A different valid current timezone is used for evaluation: under
-- America/New_York the frozen 10:00Z instant is 06:00 local, outside 08:00–20:00.
set local session_replication_role = replica;
update public.clinics set scheduling_timezone_name = 'America/New_York' where id = pg_temp.clinic(1);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(1) = pg_temp.shown('p1', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', false),
    'Feasibility is evaluated in the Clinic''s current timezone, not the proposal''s stored one'
);
reset role;
set local session_replication_role = replica;
update public.clinics set scheduling_timezone_name = 'Europe/Madrid' where id = pg_temp.clinic(1);
set local session_replication_role = origin;

-- Standard duration changes and removal do not affect the frozen interval.
-- With the Veterinarian available only 08:00–13:00, the frozen 12:00–12:30
-- intervals stay feasible, while an interval recomputed from a 240-minute
-- standard duration (12:00–16:00) would not be.
set local session_replication_role = replica;
update public.clinics set standard_appointment_duration_minutes = 240 where id = pg_temp.clinic(1);
update public.veterinarian_availability_periods set end_time = '13:00' where veterinarian_clinic_assignment_id = pg_temp.vca(10);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(1) = pg_temp.shown('p1', true) and pg_temp.guardian(2) = pg_temp.shown('p2', true)
    and pg_temp.clinic_read(7) = pg_temp.shown('p7', true),
    'A standard-duration change does not change feasibility or acceptability'
);
reset role;
set local session_replication_role = replica;
update public.clinics set standard_appointment_duration_minutes = null where id = pg_temp.clinic(1);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(2) = pg_temp.shown('p2', true) and pg_temp.guardian(1) = pg_temp.shown('p1', true),
    'Removing the standard duration does not change feasibility or acceptability'
);
reset role;
set local session_replication_role = replica;
update public.clinics set standard_appointment_duration_minutes = 30 where id = pg_temp.clinic(1);
update public.veterinarian_availability_periods set end_time = '18:00' where veterinarian_clinic_assignment_id = pg_temp.vca(10);
set local session_replication_role = origin;

-- ===========================================================================
-- 4. Guardian acceptability and Entitlement (SPEC-APT-005 BR-35,
--    SPEC-APT-006 BR-26).
-- ===========================================================================

set local session_replication_role = replica;
update public.organization_subscriptions set initial_state = 'PAST_DUE'
where id = 'fe500000-0000-4000-8000-000000000901';
set local session_replication_role = origin;
select pg_temp.assert_true(
    not public.organization_has_professional_entitlement('fe500000-0000-4000-8000-000000000301', 'APPOINTMENT_MANAGEMENT'),
    'Fixture: the Organization lost APPOINTMENT_MANAGEMENT'
);
select pg_temp.remember(2);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.guardian(2) = pg_temp.shown('p2', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', true)
    and pg_temp.guardian(1) = pg_temp.shown('p1', true),
    'Entitlement loss makes a feasible CONFIRMED proposal unacceptable to the Guardian only; Clinic feasibility and the REQUESTED alternative are unaffected'
);
select pg_temp.assert_error(format('select pg_temp.confirmed_accept(1, %L)', pg_temp.id('p2')),
    '42501', 'Applicable professional Entitlement is required');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(2) and pg_temp.eligible(pg_temp.id('p2')),
    'The authoritative Entitlement rejection writes nothing; the notification stays deliverable');
-- Infeasible and without Entitlement: still false.
set local session_replication_role = replica;
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
values (pg_temp.clinic(1), '2035-04-04', 'CLOSED');
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian(2) = pg_temp.shown('p2', false) and pg_temp.clinic_read(2) = pg_temp.shown('p2', false),
    'Infeasible and without Entitlement is not acceptable');
reset role;
set local session_replication_role = replica;
delete from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.clinic(1);
update public.organization_subscriptions set initial_state = 'ACTIVE'
where id = 'fe500000-0000-4000-8000-000000000901';
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian(2) = pg_temp.shown('p2', true),
    'Restoring the Entitlement makes the same CONFIRMED proposal acceptable again');
reset role;

-- ===========================================================================
-- 5. Withdrawal while infeasible (SPEC-APT-016 BR-4), both bases.
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p4', pg_temp.confirmed_propose(7, 4, 'CLINIC', '2035-04-07', '12:00'));
select pg_temp.keep('p5', pg_temp.alt_propose(7, 5, '2035-04-07', '13:00'));
reset role;
set local session_replication_role = replica;
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
values (pg_temp.clinic(1), '2035-04-07', 'CLOSED');
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.clinic_read(4) = pg_temp.shown('p4', false) and pg_temp.clinic_read(5) = pg_temp.shown('p5', false),
    'Infeasible proposals stay projected to the Clinic'
);
select pg_temp.withdraw(7, pg_temp.id('p4'));
select pg_temp.withdraw(7, pg_temp.id('p5'));
select pg_temp.assert_true(pg_temp.clinic_read(4) = 'null|null' and pg_temp.guardian(5) = 'null|null',
    'Withdrawn proposals are no longer projected');
-- The slot is free: a new, feasible proposal is accepted.
select pg_temp.keep('p4b', pg_temp.confirmed_propose(7, 4, 'CLINIC', '2035-04-08', '12:00'));
select pg_temp.keep('p5b', pg_temp.alt_propose(7, 5, '2035-04-08', '13:00'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p4'))).state = 'WITHDRAWN' and (pg_temp.proposal(pg_temp.id('p5'))).state = 'WITHDRAWN'
    and (pg_temp.proposal(pg_temp.id('p4b'))).state = 'PENDING' and (pg_temp.proposal(pg_temp.id('p5b'))).state = 'PENDING',
    'Withdrawal of an infeasible proposal succeeds on both bases and frees the pending slot'
);
set local session_replication_role = replica;
delete from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.clinic(1);
set local session_replication_role = origin;

-- ===========================================================================
-- 6. Acceptance after feasibility returns; history unchanged.
-- ===========================================================================

set local role authenticated;
select pg_temp.alt_accept(1, pg_temp.id('p1'));
select pg_temp.confirmed_accept(1, pg_temp.id('p2'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p1'))).state = 'ACCEPTED' and (pg_temp.proposal(pg_temp.id('p2'))).state = 'ACCEPTED'
    and (select scheduled_start_at = '2035-04-03T10:00Z' and revision_context = 'REQUESTED'
         from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p1'))
    and (select scheduled_start_at = '2035-04-04T10:00Z' and revision_context = 'CONFIRMED'
         from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p2')),
    'Once feasible (and, for CONFIRMED, entitled) again, the same proposals are accepted with their frozen intervals'
);
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian(1) = 'null|null' and pg_temp.clinic_read(2) = 'null|null',
    'Accepted proposals are no longer projected');
reset role;

-- ===========================================================================
-- 7. Reads never write.
-- ===========================================================================

select pg_temp.remember(3);
select pg_temp.remember(7);
set local role authenticated;
select pg_temp.guardian(3), pg_temp.clinic_read(3), pg_temp.guardian(7), pg_temp.clinic_read(7);
reset role;
select pg_temp.assert_true(pg_temp.unchanged(3) and pg_temp.unchanged(7), 'Reading the derived values changes nothing');

rollback;

-- Nothing synthetic is retained.
do $$
begin
    if exists (select 1 from public.appointments where id::text like 'fe500000-%')
       or exists (select 1 from public.users where id::text like 'fe500000-%')
       or exists (select 1 from public.veterinary_organizations where id::text like 'fe500000-%') then
        raise exception 'Synthetic rows were retained';
    end if;
end;
$$;

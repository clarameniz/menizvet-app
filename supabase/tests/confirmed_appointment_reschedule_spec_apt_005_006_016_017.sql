-- Regression suite for the confirmed Appointment reschedule slice, migrations
-- 20261008090000_confirmed_appointment_reschedule_and_withdrawal.sql and
-- 20261015090000_unified_standard_appointment_duration.sql:
--   SPEC-APT-005 BR-23–BR-32 (start-only, current standard duration at
--   creation, stale-safe, feasible proposal creation; actionability),
--   SPEC-APT-006 BR-28–BR-33 (frozen-interval acceptance), SPEC-APT-013
--   BR-62, BR-68–BR-71 (one duration rule, no standard duration → no new
--   interval), SPEC-APT-016 (Clinic withdrawal), SPEC-APT-017 (professional
--   candidate times), SPEC-COM-003 BR-70.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables, and to switch
-- between impersonated Users.
--
-- Every behavioral call goes through the real trusted operations as the
-- `authenticated` role. Helper wrappers fire every pending deferred trigger at
-- the end of each call (SET CONSTRAINTS ALL IMMEDIATE, then back to
-- DEFERRED), so deferred provenance and Veterinarian-conflict checks run
-- inside the same subtransaction. Scheduling contexts that no trusted
-- operation produces on demand (confirmed intervals established under an
-- earlier standard duration, a superseded-but-pending Proposal, a lapsed
-- Proposal) are loaded as fixtures.
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
    select ('c5a00000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('c5a00000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c5a00000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c5a00000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c5a00000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'c5a00000-0000-4000-8000-000000000a01'::uuid
$$;
create function pg_temp.vca(p_n integer) returns uuid language sql immutable as $$
    select ('c5a00000-0000-4000-8000-0000000008' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

-- Named Proposal ids, shared across the role switches of this suite.
create temporary table ids (name text primary key, id uuid not null) on commit drop;
grant select, insert, update on ids to authenticated;
create function pg_temp.id(p_name text) returns uuid language sql as $$
    select id from ids where name = p_name
$$;
create function pg_temp.keep(p_name text, p_id uuid) returns uuid language sql as $$
    insert into ids values (p_name, p_id) on conflict (name) do update set id = excluded.id returning id
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.propose(
    p_user integer, p_n integer, p_context text, p_date date, p_time time, p_offset integer,
    p_reason text, p_sequence integer
)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_confirmed_appointment_reschedule(
        pg_temp.appt(p_n), p_context, p_date, p_time, p_offset, p_reason, p_sequence
    );
    perform pg_temp.flush();
    return created;
end;
$$;

create function pg_temp.clinic_propose(
    p_user integer, p_n integer, p_date date, p_time time, p_offset integer, p_sequence integer
)
returns uuid language sql as $$
    select pg_temp.propose(p_user, p_n, 'CLINIC', p_date, p_time, p_offset, 'Veterinarian unavailable', p_sequence)
$$;

create function pg_temp.accept(p_user integer, p_proposal uuid)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.accept_appointment_reschedule_proposal(p_proposal, 'GUARDIAN');
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

-- Trusted fixtures (security definer) for SPEC-MED-010 clinical documentation.
-- assign_vet makes the Clinic Assignment the Appointment's current assigned
-- Veterinarian when it has none; record_entry records one Clinical Record
-- Entry as that Veterinarian. The client path is assign_appointment_veterinarian
-- / create_appointment_clinical_entry; the structural triggers (documentable
-- state, current eligible assignee) still apply here.
create function pg_temp.assign_vet(p_appointment uuid, p_vca uuid)
returns void language plpgsql security definer as $$
begin
    if not exists (select 1 from public.appointment_veterinarian_assignments as current_period
                   where current_period.appointment_id = p_appointment and current_period.effective_end is null) then
        insert into public.appointment_veterinarian_assignments (
            appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id
        ) select p_appointment, p_vca, clock_timestamp(), profile.user_id
          from public.veterinarian_clinic_assignments as assignment
          join public.veterinarian_professional_profiles as profile on profile.id = assignment.professional_profile_id
          where assignment.id = p_vca;
    end if;
end;
$$;

create function pg_temp.record_entry(p_appointment uuid, p_vca uuid)
returns uuid language plpgsql security definer as $$
declare created uuid;
begin
    perform pg_temp.assign_vet(p_appointment, p_vca);
    insert into public.clinical_record_entries (
        appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at,
        category, clinical_content, creation_idempotency_key, creation_request_digest
    ) select p_appointment, profile.user_id, p_vca, clock_timestamp(),
             'CLINICAL_NOTE', 'Fixture note', gen_random_uuid(), sha256(gen_random_uuid()::text::bytea)
      from public.veterinarian_clinic_assignments as assignment
      join public.veterinarian_professional_profiles as profile on profile.id = assignment.professional_profile_id
      where assignment.id = p_vca
    returning id into created;
    return created;
end;
$$;

create function pg_temp.clinical_entry(p_n integer)
returns uuid language plpgsql security definer as $$
declare created uuid;
begin
    created := pg_temp.record_entry(pg_temp.appt(p_n), pg_temp.vca(10));
    perform pg_temp.flush();
    return created;
end;
$$;

-- Candidate starts of one Appointment as 'date time' text, in order.
create function pg_temp.candidates(p_user integer, p_n integer, p_from date, p_to date)
returns text[] language plpgsql as $$
declare result text[];
begin
    perform pg_temp.act(p_user);
    select coalesce(array_agg(candidate.candidate_local_date || ' ' || candidate.candidate_local_time
                              order by candidate.candidate_local_date, candidate.candidate_local_time),
                    '{}')
    into result
    from public.get_appointment_reschedule_candidate_start_times(pg_temp.appt(p_n), p_from, p_to) as candidate;
    return result;
end;
$$;

-- The pending Proposal id each read projects for one Appointment.
create function pg_temp.guardian_pending(p_n integer) returns uuid language plpgsql as $$
declare result uuid;
begin
    perform pg_temp.act(1);
    select read_row.pending_reschedule_proposal_id into result
    from public.get_pet_appointments(pg_temp.luna()) as read_row
    where read_row.id = pg_temp.appt(p_n);
    return result;
end;
$$;

create function pg_temp.clinic_pending(p_n integer, p_clinic integer) returns uuid language plpgsql as $$
declare result uuid;
begin
    perform pg_temp.act(4);
    select read_row.pending_reschedule_proposal_id into result
    from public.get_clinic_appointment_schedule(pg_temp.clinic(p_clinic)) as read_row
    where read_row.id = pg_temp.appt(p_n);
    return result;
end;
$$;

create function pg_temp.latest_sequence(p_n integer) returns integer language sql as $$
    select max(revision_sequence) from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(p_n)
$$;

create function pg_temp.proposal(p_id uuid) returns public.appointment_reschedule_proposals language sql as $$
    select * from public.appointment_reschedule_proposals where id = p_id
$$;

create function pg_temp.elapsed_seconds(p_start timestamptz, p_end timestamptz) returns numeric language sql immutable as $$
    select extract(epoch from p_end) - extract(epoch from p_start)
$$;

-- The distinct elapsed lengths, in seconds, of one Appointment's candidates.
create function pg_temp.candidate_seconds(p_user integer, p_n integer, p_from date, p_to date)
returns numeric[] language plpgsql as $$
declare result numeric[];
begin
    perform pg_temp.act(p_user);
    select array_agg(distinct pg_temp.elapsed_seconds(
               ((candidate.candidate_local_date + candidate.candidate_local_time)
                - make_interval(secs => candidate.utc_offset_seconds)) at time zone 'UTC',
               candidate.candidate_end_at))
    into result
    from public.get_appointment_reschedule_candidate_start_times(pg_temp.appt(p_n), p_from, p_to) as candidate;
    return result;
end;
$$;

-- Changes a Clinic's standard duration. Callers run it as the database owner
-- with session_replication_role = replica (fixture triggers such as
-- publication integrity bypassed), which only a top-level SET can establish.
create function pg_temp.set_duration(p_clinic integer, p_minutes integer) returns void language sql as $$
    update public.clinics set standard_appointment_duration_minutes = p_minutes where id = pg_temp.clinic(p_clinic)
$$;

create function pg_temp.eligible(p_communication_id uuid) returns boolean language sql as $$
    select public.communication_delivery_is_currently_eligible(p_communication_id, 'EMAIL', null, null)
$$;

create function pg_temp.proposed_communication(p_proposal uuid, p_recipient integer) returns uuid language sql as $$
    select id from public.transactional_communications
    where appointment_reschedule_proposal_id = p_proposal
      and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
      and recipient_user_id = pg_temp.domain_user(p_recipient)
$$;

create function pg_temp.communication_count(p_n integer) returns bigint language sql as $$
    select count(*) from public.transactional_communications where appointment_id = pg_temp.appt(p_n)
$$;

-- Every persisted fact a proposal operation could touch for one Appointment.
create function pg_temp.fingerprint(p_n integer)
returns text language sql as $$
    select md5(
        coalesce((select appointment::text from public.appointments as appointment
                  where appointment.id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.revision_sequence)
                  from public.appointment_schedule_revisions as revision
                  where revision.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(lifecycle_event::text, '|' order by lifecycle_event.id)
                  from public.appointment_lifecycle_events as lifecycle_event
                  where lifecycle_event.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication
                  where communication.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal
                  where proposal.appointment_id = pg_temp.appt(p_n)), '')
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
    to_regprocedure('public.propose_confirmed_appointment_reschedule(uuid, text, date, time, integer, date, time, integer, text)') is null
    and (select count(*) = 1 from pg_proc as proc
         where proc.proname = 'propose_confirmed_appointment_reschedule'
           and proc.pronamespace = 'public'::regnamespace)
    and (select pg_get_function_arguments(proc.oid)
                    = 'p_appointment_id uuid, p_proposing_context text, p_start_local_date date, p_start_local_time time without time zone, p_start_utc_offset_seconds integer, p_reason text DEFAULT NULL::text, p_expected_confirmed_revision_sequence integer DEFAULT NULL::integer'
                and pg_get_function_result(proc.oid) = 'uuid'
                and proc.prosecdef and proc.provolatile = 'v'
                and proc.proconfig = array['search_path=""']
         from pg_proc as proc
         where proc.oid = 'public.propose_confirmed_appointment_reschedule(uuid, text, date, time, integer, text, integer)'::regprocedure),
    'Contract: only the start-only, token-carrying propose form exists; the 9-argument form is gone'
);

select pg_temp.assert_true(
    (select pg_get_function_arguments(proc.oid) = 'p_proposal_id uuid'
            and pg_get_function_result(proc.oid) = 'uuid'
            and proc.prosecdef and proc.provolatile = 'v'
            and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.withdraw_appointment_reschedule_proposal(uuid)'::regprocedure)
    and (select pg_get_function_arguments(proc.oid) = 'p_proposal_id uuid, p_accepting_context text'
            and pg_get_function_result(proc.oid) = 'uuid'
     from pg_proc as proc
     where proc.oid = 'public.accept_appointment_reschedule_proposal(uuid, text)'::regprocedure)
    and (select pg_get_function_arguments(proc.oid) = 'p_appointment_id uuid, p_start_date date, p_end_date date'
            and pg_get_function_result(proc.oid)
                = 'TABLE(candidate_local_date date, candidate_local_time time without time zone, utc_offset_seconds integer, candidate_end_at timestamp with time zone)'
            and proc.prosecdef and proc.provolatile = 's'
            and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.get_appointment_reschedule_candidate_start_times(uuid, date, date)'::regprocedure),
    'Contract: withdraw, accept (unchanged), and the STABLE candidate read have their exact signatures'
);

select pg_temp.assert_true(
    (select bool_and(
         (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                           order by acl_entry.grantee::regrole::text)
          from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
          where proc.oid = signature::regprocedure and acl_entry.grantee <> proc.proowner)
         = array['authenticated:EXECUTE', 'service_role:EXECUTE']
         and not has_function_privilege('anon', signature, 'EXECUTE'))
     from unnest(array[
         'public.propose_confirmed_appointment_reschedule(uuid, text, date, time, integer, text, integer)',
         'public.accept_appointment_reschedule_proposal(uuid, text)',
         'public.withdraw_appointment_reschedule_proposal(uuid)',
         'public.get_appointment_reschedule_candidate_start_times(uuid, date, date)'
     ]) as signature)
    and not (select bool_or(has_function_privilege('authenticated', signature, 'EXECUTE'))
             from unnest(array[
                 'public.appointment_reschedule_interval_infeasibility(uuid, uuid, timestamptz, timestamptz, text)',
                 'public.assert_appointment_reschedule_interval_feasible(uuid, uuid, timestamptz, timestamptz, text)',
                 'public.veterinarian_has_known_confirmed_commitment_conflict(uuid, timestamptz, timestamptz, uuid)',
                 'public.veterinarian_interval_is_covered_by_timezone(uuid, timestamptz, timestamptz, text)',
                 'public.appointment_reschedule_candidate_positions(uuid, uuid, text, date, date, bigint, timestamptz, timestamptz)',
                 'public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz)',
                 'public.void_open_reschedule_proposal(uuid, text)'
             ]) as signature),
    'Contract: the four RPCs are granted only to authenticated (and service_role); every helper is internal'
);

-- The base-confirmed elapsed-duration helper no longer exists (SPEC-APT-013 BR-69).
select pg_temp.assert_true(
    not exists (select 1 from pg_proc
                where proname = 'appointment_interval_duration_microseconds'
                  and pronamespace = 'public'::regnamespace),
    'Contract: appointment_interval_duration_microseconds is gone'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c5a00000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current)      08 RECEPTIONIST @ A1 (Clinic)
--   02 Guardian G2 (current)      09 RECEPTIONIST @ A2 (Clinic)
--   03 former Guardian G3         10 VETERINARIAN only, assigned @ A1 and @ B1
--   04 OrgA OWNER                 13 OrgA RECEPTIONIST (Org), Grant ended in-suite
--   07 OrgA RECEPTIONIST (Org)    14 VETERINARIAN whose Clinic Assignment @ A1 ended
--                                 16 OWNER of the PAST_DUE Org
-- Organizations: 0301 OrgA ACTIVE (A1 0401, A2 0402, A3 0403 unpublished, A7
-- 0407 without a standard duration), 0302 OrgB (B1 0406), 0304 PAST_DUE (C5
-- 0405). Standard duration 30 minutes unless noted. A1, A2, A7, B1, C5:
-- Appointment Availability 08:00–20:00 every day; A3: 00:00–24:00 every day.
-- All Europe/Madrid. Veterinarian 10 is available
-- 08:00–18:00 every day @ A1 (vca 10) and @ B1 (vca 11); Veterinarian 14's
-- vca 12 @ A1 ended in 2021. Every Appointment is Luna's; Appointment n has
-- Care Authorization c<n>. FUTURE = 2035.
-- ===========================================================================

insert into auth.users (id, email, email_confirmed_at)
select ('c5a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       'user' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 16]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 16]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c5a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 16]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('c5a00000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('c5a00000-0000-4000-8000-000000000302', 'Other Veterinary Group'),
    ('c5a00000-0000-4000-8000-000000000304', 'Org Past Due');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    (pg_temp.clinic(1), 'c5a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), 'c5a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(3), 'c5a00000-0000-4000-8000-000000000301', false, 'Europe/Madrid', 30),
    (pg_temp.clinic(5), 'c5a00000-0000-4000-8000-000000000304', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(6), 'c5a00000-0000-4000-8000-000000000302', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(7), 'c5a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', null);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select clinic_id, weekday, '08:00', '20:00'
from unnest(array[pg_temp.clinic(1), pg_temp.clinic(2), pg_temp.clinic(5), pg_temp.clinic(6), pg_temp.clinic(7)]) as clinic_id,
     generate_series(1, 7) as weekday;
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(3), weekday, '00:00', '24:00' from generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('c5a00000-0000-4000-8000-000000000504', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000507', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000508', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(8), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000509', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(9), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000510', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000520', 'c5a00000-0000-4000-8000-000000000302', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000513', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(13), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000514', 'c5a00000-0000-4000-8000-000000000301', pg_temp.domain_user(14), '2020-01-01Z', null, null),
    ('c5a00000-0000-4000-8000-000000000516', 'c5a00000-0000-4000-8000-000000000304', pg_temp.domain_user(16), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('c5a00000-0000-4000-8000-000000000604', 'c5a00000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000607', 'c5a00000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000608', 'c5a00000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000609', 'c5a00000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000610', 'c5a00000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000620', 'c5a00000-0000-4000-8000-000000000520', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000613', 'c5a00000-0000-4000-8000-000000000513', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000614', 'c5a00000-0000-4000-8000-000000000514', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c5a00000-0000-4000-8000-000000000616', 'c5a00000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('c5a00000-0000-4000-8000-000000000710', pg_temp.domain_user(10)),
    ('c5a00000-0000-4000-8000-000000000714', pg_temp.domain_user(14));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.vca(10), 'c5a00000-0000-4000-8000-000000000710', 'c5a00000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z', null),
    (pg_temp.vca(11), 'c5a00000-0000-4000-8000-000000000710', 'c5a00000-0000-4000-8000-000000000520', pg_temp.clinic(6), '2020-01-01Z', null),
    (pg_temp.vca(12), 'c5a00000-0000-4000-8000-000000000714', 'c5a00000-0000-4000-8000-000000000514', pg_temp.clinic(1), '2020-01-01Z', '2021-01-01Z');
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time)
select assignment_id, weekday, '08:00', '18:00'
from unnest(array[pg_temp.vca(10), pg_temp.vca(11), pg_temp.vca(12)]) as assignment_id,
     generate_series(1, 7) as weekday;

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('c5a00000-0000-4000-8000-000000000901', 'c5a00000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',   '2020-01-01Z', null, null, 'reschedule-test', 'c5a00000-0000-4000-8000-000000000991'),
    ('c5a00000-0000-4000-8000-000000000904', 'c5a00000-0000-4000-8000-000000000304', '2020-01-01Z', 'PAST_DUE', '2020-01-01Z', null, null, 'reschedule-test', 'c5a00000-0000-4000-8000-000000000994');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('c5a00000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null),
    ('c5a00000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z', null),
    ('c5a00000-0000-4000-8000-000000000a13', pg_temp.domain_user(3), pg_temp.luna(), '2020-01-01Z', '2021-01-01Z');

-- An Appointment requested on 2026-01-01 (revision 1 REQUESTED, ACTIVE Care
-- Authorization) and, when CONFIRMED, confirmed on 2026-02-01 (revision 2
-- CONFIRMED with the same interval). p_duration is the interval length.
create function pg_temp.seed(
    p_n integer, p_clinic integer, p_start timestamptz, p_state text, p_duration interval default interval '30 minutes'
)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), pg_temp.clinic(p_clinic), pg_temp.domain_user(1), 'Visit ' || p_n, p_state,
            '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + p_duration, 'Europe/Madrid',
              pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) select pg_temp.ca(p_n), pg_temp.luna(), clinic.id, clinic.organization_id, 'c5a00000-0000-4000-8000-000000000a11',
             '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n), 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE'
      from public.clinics as clinic where clinic.id = pg_temp.clinic(p_clinic);
    if p_state = 'CONFIRMED' then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
        ) values (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_start + p_duration, 'Europe/Madrid',
                  pg_temp.domain_user(8), null, '2026-02-01T00:00:00Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(8), 'CLINIC', null,
                  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
    end if;
end;
$$;

create function pg_temp.assign_vet(p_n integer, p_vca integer) returns void language sql as $$
    insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id)
    values (pg_temp.appt(p_n), pg_temp.vca(p_vca), '2026-02-01T00:00:00Z', pg_temp.domain_user(4))
$$;

-- Invalid input (1).
select pg_temp.seed(1, 1, '2035-03-05T09:00Z', 'CONFIRMED');
-- Current standard duration at creation (2–12). A confirmed interval may have
-- been established under an earlier standard duration.
select pg_temp.seed(2, 1, '2035-03-05T10:00Z', 'CONFIRMED');
select pg_temp.seed(3, 1, '2035-03-05T11:00Z', 'CONFIRMED', interval '45 minutes');           -- Guardian, 45 → 30
select pg_temp.seed(4, 7, '2035-03-05T12:00Z', 'CONFIRMED');                                  -- no standard duration
select pg_temp.seed(5, 1, '2035-03-08T09:00Z', 'CONFIRMED');                                  -- 10:00 local; 30 → 45, frozen, history
select pg_temp.seed(6, 1, '2035-03-09T11:00Z', 'CONFIRMED', interval '60 minutes');           -- 60 → 30
select pg_temp.seed(7, 1, '2035-03-09T13:00Z', 'CONFIRMED', interval '120 minutes');          -- shorter interval fits
select pg_temp.seed(8, 1, '2035-03-09T16:00Z', 'CONFIRMED');                                  -- longer interval does not fit
select pg_temp.seed(9, 3, '2035-03-10T09:00Z', 'CONFIRMED');                                  -- next spring-forward
select pg_temp.seed(10, 3, '2035-03-10T11:00Z', 'CONFIRMED');                                 -- next fall-back
select pg_temp.seed(12, 1, '2035-03-07T10:00Z', 'CONFIRMED');                                 -- 11:00 local; same start
-- Stale (13–14). 14 carries an accepted reschedule (revision 3, whose own
-- created_at and establishing User are the acceptance facts) and a Proposal on
-- the superseded revision 2, which the system records as VOID
-- (SPEC-APT-005 BR-33).
select pg_temp.seed(13, 1, '2035-03-12T09:00Z', 'CONFIRMED');
select pg_temp.seed(14, 1, '2035-03-12T10:00Z', 'CONFIRMED');
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name,
    proposing_context, proposed_by_user_id, reason, state, created_at
) values (
    'c5a00000-0000-4000-8000-000000000e14', pg_temp.appt(14),
    (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(14) and revision_sequence = 2), 'CONFIRMED',
    '2035-03-12T13:00Z', '2035-03-12T13:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Accepted change',
    'ACCEPTED', '2026-02-15T00:00Z'
);
insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
) values ('c5a00000-0000-4000-8000-000000000f14', pg_temp.appt(14), 3, 'CONFIRMED', '2035-03-12T13:00Z', '2035-03-12T13:30Z',
          'Europe/Madrid', pg_temp.domain_user(1), 'c5a00000-0000-4000-8000-000000000e14', '2026-02-20T00:00Z');
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name,
    proposing_context, proposed_by_user_id, reason, state, created_at, voided_at, void_reason
) values (
    'c5a00000-0000-4000-8000-000000000d14', pg_temp.appt(14),
    (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(14) and revision_sequence = 2), 'CONFIRMED',
    '2035-03-12T12:00Z', '2035-03-12T12:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Earlier change',
    'VOID', '2026-03-01T00:00Z', '2026-03-01T00:00Z', 'BASE_REVISION_SUPERSEDED'
);
insert into public.transactional_communications (
    communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id, locale, created_at
) values ('APPOINTMENT_RESCHEDULE_PROPOSED', pg_temp.domain_user(1), pg_temp.appt(14),
          'c5a00000-0000-4000-8000-000000000d14', 'es-ES', '2026-03-01T00:00Z');
-- Feasibility (15–22): Veterinarian 10 on 2035-04-02 is busy 12:00–13:00 @ A1 (16)
-- and 15:00–16:00 @ B1 in another Organization (17). April = CEST (+02:00).
select pg_temp.seed(15, 1, '2035-04-02T08:00Z', 'CONFIRMED');                                 -- 10:00 local
select pg_temp.seed(16, 1, '2035-04-02T10:00Z', 'CONFIRMED', interval '60 minutes');          -- 12:00 local
select pg_temp.seed(17, 6, '2035-04-02T13:00Z', 'CONFIRMED', interval '60 minutes');          -- 15:00 local, OrgB
select pg_temp.seed(18, 1, '2035-04-03T08:00Z', 'CONFIRMED');                                 -- 10:00 local
select pg_temp.seed(19, 1, '2035-04-03T09:00Z', 'CONFIRMED');
select pg_temp.seed(20, 1, '2035-04-04T07:00Z', 'CONFIRMED');                                 -- 09:00 local
select pg_temp.seed(21, 1, '2035-04-05T07:00Z', 'CONFIRMED');
select pg_temp.assign_vet(n, 10) from unnest(array[15, 16, 18, 20]) as n;
select pg_temp.assign_vet(17, 11);
select pg_temp.assign_vet(19, 12);
-- Clinical documentation (23), withdrawal (24–30), acceptance (31–34), candidates (35–36).
select pg_temp.seed(23, 1, '2035-04-10T08:00Z', 'CONFIRMED');
select pg_temp.seed(24, 1, '2035-04-11T08:00Z', 'CONFIRMED');
select pg_temp.seed(25, 1, '2035-04-11T09:00Z', 'CONFIRMED');
select pg_temp.seed(26, 5, '2035-04-11T10:00Z', 'CONFIRMED');
select pg_temp.seed(27, 1, '2035-04-11T11:00Z', 'CONFIRMED');
select pg_temp.seed(28, 1, '2035-04-11T12:00Z', 'CONFIRMED');
select pg_temp.seed(29, 1, '2035-04-11T13:00Z', 'CONFIRMED');
select pg_temp.seed(30, 1, '2035-04-11T14:00Z', 'CONFIRMED');
select pg_temp.seed(31, 1, '2035-04-12T08:00Z', 'CONFIRMED');
select pg_temp.seed(33, 1, '2035-04-12T09:00Z', 'CONFIRMED');
select pg_temp.seed(34, 1, '2035-04-12T10:00Z', 'CONFIRMED');
select pg_temp.seed(35, 1, '2035-04-12T11:00Z', 'REQUESTED');
select pg_temp.seed(36, 1, '2035-04-12T12:00Z', 'CONFIRMED', interval '45 minutes');
select pg_temp.seed(37, 3, '2035-04-12T13:00Z', 'CONFIRMED');
-- 26 (PAST_DUE C5), 30 and 4 (lapsed) Proposals, which no trusted operation can create.
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name,
    proposing_context, proposed_by_user_id, reason, created_at
) values
    ('c5a00000-0000-4000-8000-000000000d04', pg_temp.appt(4),
     (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(4) and revision_sequence = 2), 'CONFIRMED',
     '2026-06-01T11:00Z', '2026-06-01T11:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Long ago', '2026-03-01T00:00Z'),
    ('c5a00000-0000-4000-8000-000000000d26', pg_temp.appt(26),
     (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(26) and revision_sequence = 2), 'CONFIRMED',
     '2035-04-11T14:00Z', '2035-04-11T14:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(16), 'Owner away', '2026-03-01T00:00Z'),
    ('c5a00000-0000-4000-8000-000000000d30', pg_temp.appt(30),
     (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(30) and revision_sequence = 2), 'CONFIRMED',
     '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Long ago', '2026-03-01T00:00Z');
insert into public.transactional_communications (
    communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id, locale, created_at
) values ('APPOINTMENT_RESCHEDULE_PROPOSED', pg_temp.domain_user(1), pg_temp.appt(30),
          'c5a00000-0000-4000-8000-000000000d30', 'es-ES', '2026-03-01T00:00Z');

set local session_replication_role = origin;

-- ===========================================================================
-- 2. Invalid input, before any Appointment state.
-- ===========================================================================

select pg_temp.remember(1);
set local role authenticated;
select pg_temp.act(7);
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''CLINIC'', ''2035-03-06'', ''12:00'', 3600, ''Busy'')', pg_temp.appt(1)),
    '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''CLINIC'', ''2035-03-06'', ''12:00'', 3600, ''Busy'', %s)', pg_temp.appt(1), n),
    '22023', 'Expected confirmed revision sequence must be a positive integer')
from unnest(array[0, -1]) as n;
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''CLINIC'', ''2035-03-06'', ''12:00'', 3600, %L, 2)', pg_temp.appt(1), reason),
    '22023', 'A meaningful reason is required for a Clinic-proposed reschedule')
from unnest(array[null, E'  \t\n ']) as reason;
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''OTHER'', ''2035-03-06'', ''12:00'', 3600, ''Busy'', 2)', pg_temp.appt(1)),
    '22023', 'Proposing context must be GUARDIAN or CLINIC');
-- Structural validation precedes the Appointment lookup.
select pg_temp.assert_error('select public.propose_confirmed_appointment_reschedule(''c5a00000-0000-4000-8000-0000000000ff'', ''CLINIC'', ''2035-03-06'', ''12:00'', 3600, ''Busy'', 0)',
    '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error('select public.propose_confirmed_appointment_reschedule(''c5a00000-0000-4000-8000-0000000000ff'', ''CLINIC'', ''2035-03-06'', ''12:00'', 3600, ''Busy'', 2)',
    '23503', 'Appointment does not exist');
-- The client can never author an end: the 9-argument call no longer resolves.
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''CLINIC'', ''2035-03-06''::date, ''12:00''::time, 3600, ''2035-03-06''::date, ''12:30''::time, 3600, ''Busy'')', pg_temp.appt(1)),
    '42883', null);
select pg_temp.act(1);
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''GUARDIAN'', ''2035-03-06'', ''12:00'', 3600, null, 2)', pg_temp.appt(1)),
    '22023', 'Guardian reschedule proposal does not accept an expected confirmed revision sequence');
-- BR-27: Guardian authority precedes lifecycle disclosure. A non-Guardian — a
-- former Guardian (3) or a Clinic actor (7) acting in the GUARDIAN context —
-- gets the identical authorization error for a CONFIRMED (1) and a REQUESTED
-- (35) Appointment, so the lifecycle state is not revealed; a current
-- Guardian (1) does learn that 35 is not CONFIRMED.
select pg_temp.assert_error(format('select pg_temp.propose(%s, %s, ''GUARDIAN'', ''2035-03-06'', ''12:00'', 3600, null, null)', actor, n),
    '42501', 'Current Guardianship of the Appointment Pet is required')
from unnest(array[3, 7]) as actor, unnest(array[1, 35]) as n;
select pg_temp.assert_error('select pg_temp.propose(1, 35, ''GUARDIAN'', ''2035-04-13'', ''12:00'', 7200, null, null)',
    '23514', 'Only a CONFIRMED Appointment may receive a reschedule Proposal');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(1), 'Invalid input writes nothing');

-- ===========================================================================
-- 3. Current standard duration at creation (SPEC-APT-005 BR-23–BR-25,
--    SPEC-APT-006 BR-28–BR-29, SPEC-APT-013 BR-62, BR-68–BR-70).
-- ===========================================================================

-- CLINIC: end = new start + current standard duration (30); nothing else changes.
set local role authenticated;
select pg_temp.keep('p2', pg_temp.clinic_propose(7, 2, '2035-03-05', '14:00', 3600, 2));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p2'))).proposed_start_at = '2035-03-05T13:00Z'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_end_at = '2035-03-05T13:30Z'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_timezone_name = 'Europe/Madrid'
    and (pg_temp.proposal(pg_temp.id('p2'))).state = 'PENDING'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposing_context = 'CLINIC'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_by_user_id = pg_temp.domain_user(7)
    and pg_temp.latest_sequence(2) = 2
    and (select lifecycle_state = 'CONFIRMED' and reason_for_visit = 'Visit 2' from public.appointments where id = pg_temp.appt(2)),
    'CLINIC proposal stores start + current standard duration and leaves the Appointment unchanged'
);
select pg_temp.assert_true(
    (select array_agg(recipient_user_id order by recipient_user_id) from public.transactional_communications
     where appointment_reschedule_proposal_id = pg_temp.id('p2') and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED')
        = array[pg_temp.domain_user(1), pg_temp.domain_user(2)],
    'A Clinic proposal notifies exactly the current Guardians'
);
select pg_temp.assert_true(pg_temp.eligible(pg_temp.proposed_communication(pg_temp.id('p2'), 1)),
    'The proposal notification is deliverable while the proposal is actionable');
-- Both reads project it.
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian_pending(2) = pg_temp.id('p2') and pg_temp.clinic_pending(2, 1) = pg_temp.id('p2'),
    'Guardian and Clinic reads project the actionable proposal');
-- Guardian G2 accepts: the exact stored interval becomes revision 3.
select pg_temp.accept(2, pg_temp.id('p2'));
reset role;
select pg_temp.assert_true(
    pg_temp.latest_sequence(2) = 3
    and (select scheduled_start_at = '2035-03-05T13:00Z' and scheduled_end_at = '2035-03-05T13:30Z'
                and revision_context = 'CONFIRMED' and source_proposal_id = pg_temp.id('p2')
         from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(2) and revision_sequence = 3)
    and (select scheduled_start_at = '2035-03-05T10:00Z' from public.appointment_schedule_revisions
         where appointment_id = pg_temp.appt(2) and revision_sequence = 2)
    and (select lifecycle_state = 'CONFIRMED' from public.appointments where id = pg_temp.appt(2))
    and (pg_temp.proposal(pg_temp.id('p2'))).state = 'ACCEPTED'
    -- SPEC-APT-006 BR-34: the acceptance facts are the resulting revision's.
    and (select established_by_user_id = pg_temp.domain_user(2) and created_at >= (pg_temp.proposal(pg_temp.id('p2'))).created_at
         from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p2'))
    and (select count(*) = 2 from public.transactional_communications
         where appointment_reschedule_proposal_id = pg_temp.id('p2') and communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED')
    and not pg_temp.eligible(pg_temp.proposed_communication(pg_temp.id('p2'), 1)),
    'Acceptance establishes the stored interval as revision 3, keeps revision 2, stays CONFIRMED, notifies both Guardians'
);
-- The scheduling history still reports who accepted, through which context,
-- and when — derived from revision 3.
set local role authenticated;
select pg_temp.act(1);
select pg_temp.assert_true(
    (select is_accepted_reschedule
            and reschedule_proposing_context = 'CLINIC'
            and reschedule_proposed_by_user_id = pg_temp.domain_user(7)
            and reschedule_accepting_context = 'GUARDIAN'
            and reschedule_accepted_by_user_id = pg_temp.domain_user(2)
            and reschedule_accepted_at = established_at
     from public.get_appointment_scheduling_history(pg_temp.appt(2)) where revision_sequence = 3)
    and (select bool_and(not is_accepted_reschedule and reschedule_accepting_context is null
                         and reschedule_accepted_by_user_id is null and reschedule_accepted_at is null)
         from public.get_appointment_scheduling_history(pg_temp.appt(2)) where revision_sequence < 3),
    'The history read derives the acceptance context, User, and time from the resulting revision'
);
reset role;
-- A second acceptance creates nothing.
select pg_temp.remember(2);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p2')), '23514', 'Reschedule Proposal is no longer actionable');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(2), 'A repeated acceptance writes nothing');

-- GUARDIAN: start-only too; a 45-minute confirmed base under the current
-- 30-minute standard duration yields a 30-minute proposal; no proposal
-- notification.
set local role authenticated;
select pg_temp.keep('p3', pg_temp.propose(1, 3, 'GUARDIAN', '2035-03-06', '12:00', 3600, null, null));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p3'))).proposed_start_at = '2035-03-06T11:00Z'
    and (pg_temp.proposal(pg_temp.id('p3'))).proposed_end_at = '2035-03-06T11:30Z'
    and (pg_temp.proposal(pg_temp.id('p3'))).proposing_context = 'GUARDIAN'
    and (pg_temp.proposal(pg_temp.id('p3'))).reason is null
    and pg_temp.proposed_communication(pg_temp.id('p3'), 1) is null,
    'GUARDIAN proposal uses the current standard duration, not the base duration, and creates no proposal notification'
);

-- No configured standard duration (A7): the Clinic and the Guardian proposal
-- are rejected and the candidate read fails, after the lazy VOID would have
-- run — so nothing is written, not even the VOID of the lapsed Proposal d04.
select pg_temp.remember(4);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 4, ''2035-03-06'', ''09:00'', 3600, 2)',
    '23514', 'Clinic has no currently configured standard Appointment duration');
select pg_temp.assert_error('select pg_temp.propose(1, 4, ''GUARDIAN'', ''2035-03-06'', ''09:00'', 3600, null, null)',
    '23514', 'Clinic has no currently configured standard Appointment duration');
select pg_temp.assert_error('select pg_temp.candidates(7, 4, ''2035-03-06'', ''2035-03-06'')',
    '23514', 'Clinic has no currently configured standard Appointment duration');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(4) and (pg_temp.proposal('c5a00000-0000-4000-8000-000000000d04')).state = 'PENDING',
    'Without a standard duration no proposal, lazy VOID, or Communication is written'
);

-- 30 → 45: a 30-minute confirmed Appointment gets 45-minute candidates and a
-- 45-minute proposal.
set local session_replication_role = replica;
select pg_temp.set_duration(1, 45);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_true(
    (pg_temp.candidates(7, 5, '2035-03-10', '2035-03-10'))[1:3]
        = array['2035-03-10 08:00:00', '2035-03-10 08:45:00', '2035-03-10 09:30:00']
    and cardinality(pg_temp.candidates(7, 5, '2035-03-10', '2035-03-10')) = 16
    and pg_temp.candidate_seconds(7, 5, '2035-03-10', '2035-03-10') = array[2700]::numeric[],
    'After a 30 → 45 change the candidates last and step 45 minutes'
);
select pg_temp.keep('p5', pg_temp.clinic_propose(7, 5, '2035-03-09', '10:00', 3600, 2));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p5'))).proposed_start_at = '2035-03-09T09:00Z'
    and (pg_temp.proposal(pg_temp.id('p5'))).proposed_end_at = '2035-03-09T09:45Z',
    'After a 30 → 45 change a 30-minute confirmed Appointment receives a 45-minute proposal'
);
-- Frozen: lowering and then removing the standard duration changes neither the
-- proposal nor what acceptance establishes; acceptance never reads it.
set local session_replication_role = replica;
select pg_temp.set_duration(1, 30);
set local session_replication_role = origin;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p5'))).proposed_end_at = '2035-03-09T09:45Z',
    'A later standard-duration change does not alter the pending proposal');
set local session_replication_role = replica;
select pg_temp.set_duration(1, null);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.accept(1, pg_temp.id('p5'));
reset role;
set local session_replication_role = replica;
select pg_temp.set_duration(1, 30);
set local session_replication_role = origin;
-- History: revision 2 keeps its 30-minute interval; revision 3 is 45 minutes.
select pg_temp.assert_true(
    (select scheduled_start_at = '2035-03-09T09:00Z' and scheduled_end_at = '2035-03-09T09:45Z'
            and revision_context = 'CONFIRMED' and source_proposal_id = pg_temp.id('p5')
     from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(5) and revision_sequence = 3)
    and (select scheduled_start_at = '2035-03-08T09:00Z' and scheduled_end_at = '2035-03-08T09:30Z'
         from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(5) and revision_sequence = 2),
    'Acceptance without a standard duration establishes the frozen 45 minutes; the earlier 30-minute revision is unchanged'
);
-- New reads use the standard duration current now (30).
set local role authenticated;
select pg_temp.assert_true(
    (pg_temp.candidates(7, 5, '2035-03-10', '2035-03-10'))[1:3]
        = array['2035-03-10 08:00:00', '2035-03-10 08:30:00', '2035-03-10 09:00:00']
    and pg_temp.candidate_seconds(7, 5, '2035-03-10', '2035-03-10') = array[1800]::numeric[],
    'After the accepted 45-minute reschedule, new candidates use the current 30 minutes'
);

-- 60 → 30: a 60-minute confirmed Appointment gets 30-minute candidates and a
-- 30-minute proposal.
select pg_temp.assert_true(
    (pg_temp.candidates(7, 6, '2035-03-10', '2035-03-10'))[1:3]
        = array['2035-03-10 08:00:00', '2035-03-10 08:30:00', '2035-03-10 09:00:00']
    and pg_temp.candidate_seconds(7, 6, '2035-03-10', '2035-03-10') = array[1800]::numeric[],
    'A 60-minute confirmed Appointment gets 30-minute candidates under a 30-minute standard duration'
);
select pg_temp.keep('p6', pg_temp.clinic_propose(7, 6, '2035-04-10', '10:00', 7200, 2));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p6'))).proposed_start_at = '2035-04-10T08:00Z'
    and (pg_temp.proposal(pg_temp.id('p6'))).proposed_end_at = '2035-04-10T08:30Z',
    'A 60-minute confirmed Appointment receives a 30-minute proposal'
);

-- Feasibility uses the actual proposed end. 7 (120-minute base): 19:30 + 30
-- minutes fits Clinic Availability (until 20:00), where the base duration
-- would not. 8 (30-minute base) under a 60-minute standard duration: 19:30 +
-- 60 minutes does not fit, where the base duration would.
set local role authenticated;
select pg_temp.keep('p7', pg_temp.clinic_propose(7, 7, '2035-04-10', '19:30', 7200, 2));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p7'))).proposed_end_at = '2035-04-10T18:00Z',
    'A shorter interval derived from the current standard duration is feasible'
);
select pg_temp.remember(8);
set local session_replication_role = replica;
select pg_temp.set_duration(1, 60);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 8, ''2035-04-10'', ''19:30'', 7200, 2)',
    '23514', 'Clinic Appointment Availability does not cover the proposed interval');
reset role;
set local session_replication_role = replica;
select pg_temp.set_duration(1, 30);
set local session_replication_role = origin;
select pg_temp.assert_true(pg_temp.unchanged(8), 'A longer interval that no longer fits is rejected with no write');

-- Daylight saving: the standard duration is elapsed, not wall-clock, time,
-- whatever the session timezone. Spring-forward (02:00 -> 03:00 local) under
-- 60 minutes: 01:30 CET ends 03:30 CEST. Fall-back (03:00 -> 02:00 local)
-- under 120 minutes: 01:30 CEST ends 02:30 CET. Both bases last 30 minutes.
--
-- The dates are never hard-coded: they are the next real Europe/Madrid
-- spring-forward and fall-back dates strictly after the Clinic-local today,
-- found from the time-zone database (the first date whose noon UTC offset is
-- higher, respectively lower, than the previous date's), as in the REQUESTED
-- Alternative Time suite. The confirmed path has no business horizon, so this
-- is never skipped; a missing transition fails the suite.
create table pg_temp.dst_dates (spring_forward date not null, fall_back date not null);
grant select on pg_temp.dst_dates to authenticated;

do $$
declare
    local_today date := (clock_timestamp() at time zone 'Europe/Madrid')::date;
begin
    insert into pg_temp.dst_dates (spring_forward, fall_back)
    select
        min(candidate_date) filter (where noon_offset > previous_noon_offset),
        min(candidate_date) filter (where noon_offset < previous_noon_offset)
    from (
        select candidate_date,
               extract(epoch from (candidate_date + time '12:00')
                   - ((candidate_date + time '12:00') at time zone 'Europe/Madrid' at time zone 'UTC')) as noon_offset,
               extract(epoch from (candidate_date - 1 + time '12:00')
                   - ((candidate_date - 1 + time '12:00') at time zone 'Europe/Madrid' at time zone 'UTC')) as previous_noon_offset
        from (select local_today + day_offset as candidate_date from generate_series(1, 400) as day_offset) as days
    ) as offsets;

    perform pg_temp.assert_true(
        (select spring_forward is not null and fall_back is not null from pg_temp.dst_dates),
        'Europe/Madrid spring-forward and fall-back dates exist within 400 days'
    );
end;
$$;

set local timezone = 'Europe/Madrid';
set local session_replication_role = replica;
select pg_temp.set_duration(3, 60);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.keep('p9', pg_temp.clinic_propose(7, 9, (select spring_forward from pg_temp.dst_dates), '01:30', 3600, 2));
reset role;
set local session_replication_role = replica;
select pg_temp.set_duration(3, 120);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.keep('p10', pg_temp.clinic_propose(7, 10, (select fall_back from pg_temp.dst_dates), '01:30', 7200, 2));
reset role;
set local session_replication_role = replica;
select pg_temp.set_duration(3, 30);
set local session_replication_role = origin;
set local timezone = 'UTC';
select pg_temp.assert_true(
    (select (pg_temp.proposal(pg_temp.id('p9'))).proposed_start_at
                = (spring_forward + time '01:30') at time zone 'Europe/Madrid'
            and (pg_temp.proposal(pg_temp.id('p9'))).proposed_end_at
                - (pg_temp.proposal(pg_temp.id('p9'))).proposed_start_at = interval '1 hour'
            and ((pg_temp.proposal(pg_temp.id('p9'))).proposed_end_at at time zone 'Europe/Madrid')
                = spring_forward + time '03:30'
            and (pg_temp.proposal(pg_temp.id('p10'))).proposed_start_at
                = (fall_back + time '01:30') at time zone 'Europe/Madrid'
            and (pg_temp.proposal(pg_temp.id('p10'))).proposed_end_at
                - (pg_temp.proposal(pg_temp.id('p10'))).proposed_start_at = interval '2 hours'
            and ((pg_temp.proposal(pg_temp.id('p10'))).proposed_end_at at time zone 'Europe/Madrid')
                = fall_back + time '02:30'
     from pg_temp.dst_dates),
    'Across DST transitions the proposed interval lasts the standard duration in elapsed time'
);

-- Same resolved start is a no-op, even after the standard duration changed.
select pg_temp.remember(12);
set local session_replication_role = replica;
select pg_temp.set_duration(1, 45);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 12, ''2035-03-07'', ''11:00'', 3600, 2)', '22023', 'Proposed time must differ from the current confirmed time');
select pg_temp.assert_error('select pg_temp.propose(1, 12, ''GUARDIAN'', ''2035-03-07'', ''11:00'', 3600, null, null)', '22023', 'Proposed time must differ from the current confirmed time');
reset role;
set local session_replication_role = replica;
select pg_temp.set_duration(1, 30);
set local session_replication_role = origin;
select pg_temp.assert_true(pg_temp.unchanged(12), 'A same-start proposal writes nothing, whatever the standard duration');

-- ===========================================================================
-- 4. Stale Clinic proposals (SPEC-APT-005 BR-26, BR-27).
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p13', pg_temp.clinic_propose(7, 13, '2035-03-12', '12:00', 3600, 2));
select pg_temp.accept(1, pg_temp.id('p13'));
reset role;
select pg_temp.remember(13);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.clinic_propose(8, 13, ''2035-03-12'', ''15:00'', 3600, 2)', 'P0001',
    'Stale confirmed Appointment schedule revision for reschedule proposal');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(13), 'A stale proposal writes no proposal and no Communication');
set local role authenticated;
select pg_temp.keep('p13b', pg_temp.clinic_propose(8, 13, '2035-03-12', '15:00', 3600, 3));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p13b'))).base_revision_id
        = (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(13) and revision_sequence = 3),
    'After re-reading, the current confirmed revision proposes against revision 3'
);

-- 14: a stale call writes nothing, including to the superseded proposal.
select pg_temp.remember(14);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 14, ''2035-03-12'', ''15:00'', 3600, 2)', 'P0001',
    'Stale confirmed Appointment schedule revision for reschedule proposal');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(14)
    and (pg_temp.proposal('c5a00000-0000-4000-8000-000000000d14')).state = 'VOID'
    and (pg_temp.proposal('c5a00000-0000-4000-8000-000000000d14')).voided_at = '2026-03-01T00:00Z',
    'A stale proposal changes nothing, not even the superseded proposal');
select pg_temp.assert_true(not pg_temp.eligible(pg_temp.proposed_communication('c5a00000-0000-4000-8000-000000000d14', 1)),
    'A proposal whose base was superseded is not delivered');
set local role authenticated;
select pg_temp.keep('p14', pg_temp.clinic_propose(7, 14, '2035-03-12', '15:00', 3600, 3));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal('c5a00000-0000-4000-8000-000000000d14')).void_reason = 'BASE_REVISION_SUPERSEDED'
    and (pg_temp.proposal(pg_temp.id('p14'))).state = 'PENDING'
    and (pg_temp.proposal(pg_temp.id('p14'))).base_revision_id = 'c5a00000-0000-4000-8000-000000000f14',
    'A current proposal on revision 3 takes the slot; the superseded proposal stays VOID'
);

-- ===========================================================================
-- 5. Feasibility at creation and acceptance (SPEC-APT-005 BR-28, SPEC-APT-006 BR-30).
-- ===========================================================================

select pg_temp.remember(15);
set local role authenticated;
-- Outside Clinic Availability (20:00–20:30).
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 15, ''2035-04-02'', ''20:00'', 7200, 2)', '23514', 'Clinic Appointment Availability does not cover the proposed interval');
-- Inside Clinic but outside the Veterinarian's Availability (19:00).
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 15, ''2035-04-02'', ''19:00'', 7200, 2)', '23514', 'Currently assigned Veterinarian is not available for the proposed interval');
-- Known same-Clinic conflict (16, 12:00–13:00) and known other-Organization
-- conflict (17, 15:00–16:00 @ B1): the same generic outcome.
select pg_temp.assert_error(format('select pg_temp.clinic_propose(7, 15, ''2035-04-02'', %L, 7200, 2)', start_time), '23514', 'Currently assigned Veterinarian is not available for the proposed interval')
from unnest(array['12:15', '15:30']) as start_time;
reset role;
select pg_temp.assert_true(pg_temp.unchanged(15), 'Infeasible proposals write nothing');
-- The error never names the conflicting Clinic, Organization, or time.
do $$
begin
    perform pg_temp.clinic_propose(7, 15, '2035-04-02', '15:30', 7200, 2);
exception when others then
    if position('Other' in sqlerrm) > 0 or position('15:' in sqlerrm) > 0 or position('B1' in sqlerrm) > 0
       or position('c5a00000' in sqlerrm) > 0 then
        raise exception 'Conflict detail disclosed: %', sqlerrm;
    end if;
end;
$$;
-- The Appointment's own current interval never conflicts with itself (18:
-- 10:00–10:30 local, proposal 10:15–10:45).
set local role authenticated;
select pg_temp.keep('p18', pg_temp.clinic_propose(7, 18, '2035-04-03', '10:15', 7200, 2));
-- An assigned Veterinarian whose Clinic Assignment ended.
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 19, ''2035-04-03'', ''14:00'', 7200, 2)', '23514', 'Currently assigned Veterinarian no longer has a valid Clinic Assignment');
reset role;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p18'))).proposed_start_at = '2035-04-03T08:15Z',
    'A proposal overlapping only the Appointment''s own interval is feasible');

-- Acceptance revalidates: a commitment that appears after the proposal makes it fail atomically.
set local role authenticated;
select pg_temp.keep('p20', pg_temp.clinic_propose(7, 20, '2035-04-04', '11:00', 7200, 2));
reset role;
set local session_replication_role = replica;
select pg_temp.seed(22, 1, '2035-04-04T09:15Z', 'CONFIRMED');                                 -- 11:15 local
select pg_temp.assign_vet(22, 10);
set local session_replication_role = origin;
select pg_temp.remember(20);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p20')), '23514', 'Currently assigned Veterinarian is not available for the proposed interval');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(20) and (pg_temp.proposal(pg_temp.id('p20'))).state = 'PENDING',
    'An infeasible acceptance changes nothing and leaves the proposal pending');
-- Clinic Availability closing after the proposal also fails acceptance atomically.
set local role authenticated;
select pg_temp.keep('p21', pg_temp.clinic_propose(7, 21, '2035-04-06', '10:00', 7200, 2));
reset role;
set local session_replication_role = replica;
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time)
values (pg_temp.clinic(1), '2035-04-06', 'CLOSED', null, null);
set local session_replication_role = origin;
select pg_temp.remember(21);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p21')), '23514', 'Clinic Appointment Availability does not cover the proposed interval');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(21), 'An unavailable acceptance changes nothing');
-- The dead-end is resolved by withdrawal; a replacement proposal then succeeds.
set local role authenticated;
select pg_temp.withdraw(8, pg_temp.id('p20'));
select pg_temp.keep('p20b', pg_temp.clinic_propose(7, 20, '2035-04-04', '14:00', 7200, 2));
reset role;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p20b'))).state = 'PENDING',
    'After withdrawing an impossible proposal, a replacement proposal is created');

-- ===========================================================================
-- 6. Clinical documentation (SPEC-APT-005 BR-29, BR-31; SPEC-APT-006 BR-31; SPEC-MED-010 BR-8).
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p23', pg_temp.clinic_propose(7, 23, '2035-04-10', '14:00', 7200, 2));
select pg_temp.assert_true(pg_temp.guardian_pending(23) = pg_temp.id('p23'), 'Before the first Entry the proposal is pending');
select pg_temp.clinical_entry(23);
select pg_temp.assert_true(pg_temp.guardian_pending(23) is null and pg_temp.clinic_pending(23, 1) is null,
    'Once an Entry exists the proposal disappears from both reads');
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p23')), '23514', 'Appointment with clinical documentation cannot be rescheduled');
select pg_temp.assert_error(format('select pg_temp.withdraw(7, %L)', pg_temp.id('p23')), '23514', 'Reschedule Proposal is no longer actionable');
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 23, ''2035-04-10'', ''15:00'', 7200, 2)', '23514', 'Appointment with clinical documentation cannot be rescheduled');
select pg_temp.assert_error('select pg_temp.candidates(7, 23, ''2035-04-10'', ''2035-04-10'')', '23514', 'Appointment with clinical documentation cannot be rescheduled');
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p23'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p23'))).void_reason = 'CLINICAL_DOCUMENTATION_STARTED'
    and (pg_temp.proposal(pg_temp.id('p23'))).voided_at >= (pg_temp.proposal(pg_temp.id('p23'))).created_at
    and not pg_temp.eligible(pg_temp.proposed_communication(pg_temp.id('p23'), 1)),
    'The first Entry makes the proposal VOID (SPEC-APT-005 BR-33) and the proposal notification is suppressed'
);

-- ===========================================================================
-- 7. Withdrawal (SPEC-APT-016).
-- ===========================================================================

-- Another authorized Clinic actor withdraws; facts, immutability, freed slot.
set local role authenticated;
select pg_temp.keep('p24', pg_temp.clinic_propose(7, 24, '2035-04-11', '15:00', 7200, 2));
reset role;
create temporary table before_withdrawal on commit drop as
select pg_temp.communication_count(24) as communications,
       (select string_agg(revision::text, '|' order by revision_sequence) from public.appointment_schedule_revisions as revision
        where appointment_id = pg_temp.appt(24)) as revisions,
       (select appointment::text from public.appointments as appointment where id = pg_temp.appt(24)) as appointment_row;
set local role authenticated;
-- Wrong Clinic, Veterinarian-only, and Guardian actors are denied.
select pg_temp.assert_error(format('select pg_temp.withdraw(%s, %L)', actor, pg_temp.id('p24')), '42501', 'Applicable Clinic-management capability is required')
from unnest(array[9, 10, 1]) as actor;
select pg_temp.withdraw(8, pg_temp.id('p24'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p24'))).state = 'WITHDRAWN'
    and (pg_temp.proposal(pg_temp.id('p24'))).withdrawn_by_user_id = pg_temp.domain_user(8)
    and (pg_temp.proposal(pg_temp.id('p24'))).withdrawn_at >= (pg_temp.proposal(pg_temp.id('p24'))).created_at
    and (pg_temp.proposal(pg_temp.id('p24'))).proposed_by_user_id = pg_temp.domain_user(7)
    and (pg_temp.proposal(pg_temp.id('p24'))).voided_at is null
    and not exists (select 1 from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p24'))
    and pg_temp.communication_count(24) = (select communications from before_withdrawal)
    and (select string_agg(revision::text, '|' order by revision_sequence) from public.appointment_schedule_revisions as revision
         where appointment_id = pg_temp.appt(24)) = (select revisions from before_withdrawal)
    and (select appointment::text from public.appointments as appointment where id = pg_temp.appt(24))
        = (select appointment_row from before_withdrawal)
    and not pg_temp.eligible(pg_temp.proposed_communication(pg_temp.id('p24'), 1)),
    'Withdrawal records actor and time, changes nothing else, creates no Communication, and suppresses the notification'
);
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian_pending(24) is null and pg_temp.clinic_pending(24, 1) is null,
    'A withdrawn proposal is not projected by either read');
select pg_temp.assert_error(format('select pg_temp.withdraw(7, %L)', pg_temp.id('p24')), '23514', 'Reschedule Proposal is no longer actionable');
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p24')), '23514', 'Reschedule Proposal is no longer actionable');
select pg_temp.keep('p24b', pg_temp.clinic_propose(7, 24, '2035-04-11', '16:00', 7200, 2));
reset role;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p24b'))).state = 'PENDING', 'Withdrawal freed the pending-proposal slot');
-- Lost-response reconciliation, server side: retrying a proposal that already
-- committed fails and writes nothing, while the fresh Clinic schedule read
-- projects the committed Clinic proposal the client reconciles on.
select pg_temp.remember(24);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.clinic_propose(7, 24, ''2035-04-11'', ''16:00'', 7200, 2)', '23505', 'already has an actionable unresolved reschedule Proposal');
select pg_temp.assert_true(pg_temp.clinic_pending(24, 1) = pg_temp.id('p24b'), 'After a failed retry the schedule still projects the committed Clinic proposal');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(24), 'A retried proposal writes nothing');
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''PENDING'', withdrawn_at = null, withdrawn_by_user_id = null where id = %L', pg_temp.id('p24')),
    '23514', 'are immutable');

-- The original proposer may withdraw.
set local role authenticated;
select pg_temp.keep('p25', pg_temp.clinic_propose(7, 25, '2035-04-11', '15:00', 7200, 2));
select pg_temp.withdraw(7, pg_temp.id('p25'));
reset role;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p25'))).withdrawn_by_user_id = pg_temp.domain_user(7), 'The proposer may withdraw');

-- Without the APPOINTMENT_MANAGEMENT Entitlement (PAST_DUE), withdrawal succeeds.
set local role authenticated;
select pg_temp.withdraw(16, 'c5a00000-0000-4000-8000-000000000d26');
reset role;
select pg_temp.assert_true((pg_temp.proposal('c5a00000-0000-4000-8000-000000000d26')).state = 'WITHDRAWN', 'Withdrawal needs no Entitlement');

-- A Guardian proposal cannot be withdrawn through the Clinic workflow, nor
-- forced into WITHDRAWN directly.
set local role authenticated;
select pg_temp.keep('p27', pg_temp.propose(1, 27, 'GUARDIAN', '2035-04-11', '15:00', 7200, null, null));
select pg_temp.assert_error(format('select pg_temp.withdraw(7, %L)', pg_temp.id('p27')), '42501', 'Only a Clinic-originated Reschedule Proposal may be withdrawn');
reset role;
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''WITHDRAWN'', withdrawn_by_user_id = %L where id = %L', pg_temp.domain_user(7), pg_temp.id('p27')),
    '23514', 'Only a Clinic-originated Reschedule Proposal may be withdrawn');

-- Acceptance and withdrawal are serialized: whichever is first wins.
set local role authenticated;
select pg_temp.keep('p28', pg_temp.clinic_propose(7, 28, '2035-04-11', '16:00', 7200, 2));
select pg_temp.accept(1, pg_temp.id('p28'));
select pg_temp.assert_error(format('select pg_temp.withdraw(7, %L)', pg_temp.id('p28')), '23514', 'Reschedule Proposal is no longer actionable');
select pg_temp.keep('p29', pg_temp.clinic_propose(7, 29, '2035-04-11', '17:00', 7200, 2));
select pg_temp.withdraw(7, pg_temp.id('p29'));
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p29')), '23514', 'Reschedule Proposal is no longer actionable');
-- A lapsed proposal is already non-actionable.
select pg_temp.assert_error('select pg_temp.withdraw(7, ''c5a00000-0000-4000-8000-000000000d30'')', '23514', 'Reschedule Proposal is no longer actionable');
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p28'))).state = 'ACCEPTED'
    and (pg_temp.proposal(pg_temp.id('p29'))).state = 'WITHDRAWN'
    and pg_temp.latest_sequence(29) = 2
    and (pg_temp.proposal('c5a00000-0000-4000-8000-000000000d30')).state = 'PENDING'
    and not pg_temp.eligible(pg_temp.proposed_communication('c5a00000-0000-4000-8000-000000000d30', 1)),
    'Accepted stays accepted, withdrawn stays withdrawn, and a lapsed proposal is neither withdrawable nor delivered'
);

-- ===========================================================================
-- 8. Acceptance authority (SPEC-APT-006 BR-3, BR-23, BR-24, BR-26).
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p31', pg_temp.clinic_propose(7, 31, '2035-04-12', '15:00', 7200, 2));
-- A former Guardian cannot accept; the Clinic context cannot accept its own proposal.
select pg_temp.assert_error(format('select pg_temp.accept(3, %L)', pg_temp.id('p31')), '42501', 'Current Guardianship of the Appointment Pet is required');
select pg_temp.act(4);
select pg_temp.assert_error(format('select public.accept_appointment_reschedule_proposal(%L, ''CLINIC'')', pg_temp.id('p31')), '42501', 'The proposing context cannot accept its own Proposal');
-- The Organization's Entitlement is required for the Guardian's acceptance (C5, PAST_DUE).
reset role;
set local session_replication_role = replica;
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name,
    proposing_context, proposed_by_user_id, reason, created_at
) values ('c5a00000-0000-4000-8000-000000000e26', pg_temp.appt(26),
          (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(26) and revision_sequence = 2), 'CONFIRMED',
          '2035-04-11T15:00Z', '2035-04-11T15:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(16), 'Owner away', '2026-03-02T00:00Z');
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.assert_error('select pg_temp.accept(1, ''c5a00000-0000-4000-8000-000000000e26'')', '42501', 'Applicable professional Entitlement is required');
-- Proposing authority lost: User 13 proposes, then loses the Grant.
select pg_temp.keep('p33', pg_temp.clinic_propose(13, 33, '2035-04-12', '15:00', 7200, 2));
reset role;
set local session_replication_role = replica;
update public.organization_responsibility_grants
set effective_end = clock_timestamp(), ended_by_user_id = pg_temp.domain_user(4)
where id = 'c5a00000-0000-4000-8000-000000000613';
set local session_replication_role = origin;
select pg_temp.remember(33);
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian_pending(33) is null, 'A proposal whose proposer lost authority is not projected');
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p33')), '42501', 'The Clinic Proposal is no longer actionable because proposing authority was lost');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(33) and not pg_temp.eligible(pg_temp.proposed_communication(pg_temp.id('p33'), 1)),
    'Authority loss changes nothing and suppresses the notification');

-- Cancellation suppresses an undelivered proposal notification.
set local role authenticated;
select pg_temp.keep('p34', pg_temp.clinic_propose(7, 34, '2035-04-12', '15:00', 7200, 2));
select pg_temp.act(1);
select public.cancel_appointment(pg_temp.appt(34), 'GUARDIAN');
select pg_temp.flush();
reset role;
select pg_temp.assert_true(not pg_temp.eligible(pg_temp.proposed_communication(pg_temp.id('p34'), 1))
    and (pg_temp.proposal(pg_temp.id('p34'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p34'))).void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED',
    'Cancellation makes the proposal VOID and its notification is not delivered');

-- ===========================================================================
-- 9. Professional candidate times (SPEC-APT-017).
-- ===========================================================================

set local role authenticated;
-- Authority: wrong Clinic, Veterinarian only, Guardian; Entitlement (C5).
select pg_temp.assert_error(format('select pg_temp.candidates(%s, 5, ''2035-03-10'', ''2035-03-10'')', actor), '42501', 'Applicable Appointment-management capability is required')
from unnest(array[9, 10, 1]) as actor;
select pg_temp.assert_error('select pg_temp.candidates(16, 26, ''2035-04-13'', ''2035-04-13'')', '42501', 'Applicable professional Entitlement is required');
-- Structural span validation.
select pg_temp.assert_error('select pg_temp.candidates(7, 5, ''2035-03-10'', ''2035-05-10'')', '22023', 'Requested range must not span more than 60 days');
select pg_temp.assert_error('select pg_temp.candidates(7, 5, ''2035-03-10'', ''2035-03-09'')', '22023', 'End date must not precede start date');
select pg_temp.assert_error('select pg_temp.candidates(7, 5, null, ''2035-03-09'')', '22023', 'A start date and end date are required');
-- Lifecycle.
select pg_temp.assert_error('select pg_temp.candidates(7, 35, ''2035-04-13'', ''2035-04-13'')', '23514', 'Only a CONFIRMED Appointment may receive a reschedule Proposal');
select pg_temp.assert_true(
    -- A past range has no candidates; no horizon limits a far-future range.
    pg_temp.candidates(7, 5, '2020-01-01', '2020-01-31') = '{}'
    and cardinality(pg_temp.candidates(7, 5, '2040-01-01', '2040-01-01')) = 24
    -- Unpublished Clinic (A3, 00:00–24:00, 30 minutes).
    and cardinality(pg_temp.candidates(7, 37, '2035-05-01', '2035-05-01')) = 48,
    'Past ranges are empty, far-future ranges work, and unpublished Clinics work'
);
-- Length and step are the current standard duration (30), not the duration of
-- the confirmed context (36 lasts 45 minutes).
select pg_temp.assert_true(
    (pg_temp.candidates(7, 36, '2035-04-13', '2035-04-13'))
        = (select array_agg('2035-04-13 ' || to_char(slot, 'HH24:MI:SS') order by slot)
           from generate_series(timestamp '2035-04-13 08:00', timestamp '2035-04-13 19:30', interval '30 minutes') as slot)
    and pg_temp.candidate_seconds(7, 36, '2035-04-13', '2035-04-13') = array[1800]::numeric[],
    'Candidate length and cadence equal the current standard duration'
);
-- The current confirmed start is excluded (5 is now at 2035-03-09 10:00 local).
select pg_temp.assert_true(
    cardinality(pg_temp.candidates(7, 5, '2035-03-09', '2035-03-09')) = 23
    and not ('2035-03-09 10:00:00' = any(pg_temp.candidates(7, 5, '2035-03-09', '2035-03-09'))),
    'The current confirmed start is never a candidate'
);
-- Veterinarian Availability (08:00–18:00) and known conflicts (12:00–13:00 @ A1,
-- 15:00–16:00 @ B1) are applied; the current start 10:00 is excluded.
select pg_temp.assert_true(
    pg_temp.candidates(7, 15, '2035-04-02', '2035-04-02') = array[
        '2035-04-02 08:00:00', '2035-04-02 08:30:00', '2035-04-02 09:00:00', '2035-04-02 09:30:00',
        '2035-04-02 10:30:00', '2035-04-02 11:00:00', '2035-04-02 11:30:00',
        '2035-04-02 13:00:00', '2035-04-02 13:30:00', '2035-04-02 14:00:00', '2035-04-02 14:30:00',
        '2035-04-02 16:00:00', '2035-04-02 16:30:00', '2035-04-02 17:00:00', '2035-04-02 17:30:00'
    ],
    'Veterinarian Availability and known conflicts filter candidates'
);
-- An ended Veterinarian Clinic Assignment yields no candidates.
select pg_temp.assert_true(pg_temp.candidates(7, 19, '2035-04-04', '2035-04-04') = '{}', 'An ended Veterinarian assignment yields no candidates');
reset role;

-- Read/write parity: every candidate is accepted by propose with the same end.

create function pg_temp.round_trip(p_n integer, p_clinic integer, p_date date)
returns integer language plpgsql as $$
declare
    candidate record;
    checked integer := 0;
    stored_start timestamptz;
    stored_end timestamptz;
    expected_start timestamptz;
begin
    for candidate in
        select * from public.get_appointment_reschedule_candidate_start_times(pg_temp.appt(p_n), p_date, p_date)
    loop
        begin
            perform pg_temp.act(7);
            perform public.propose_confirmed_appointment_reschedule(
                pg_temp.appt(p_n), 'CLINIC', candidate.candidate_local_date, candidate.candidate_local_time,
                candidate.utc_offset_seconds, 'Parity', 2
            );
            perform pg_temp.flush();
            perform pg_temp.act(4);
            select read_row.pending_reschedule_proposed_start_at, read_row.pending_reschedule_proposed_end_at
            into stored_start, stored_end
            from public.get_clinic_appointment_schedule(pg_temp.clinic(p_clinic)) as read_row
            where read_row.id = pg_temp.appt(p_n);
            expected_start := ((candidate.candidate_local_date + candidate.candidate_local_time)
                               - make_interval(secs => candidate.utc_offset_seconds)) at time zone 'UTC';
            if stored_start is distinct from expected_start or stored_end is distinct from candidate.candidate_end_at then
                raise exception 'Parity broken for % %: stored % – %, read % – %',
                    candidate.candidate_local_date, candidate.candidate_local_time,
                    stored_start, stored_end, expected_start, candidate.candidate_end_at;
            end if;
            raise exception using errcode = 'P0002', message = 'rollback';
        exception when sqlstate 'P0002' then
            checked := checked + 1;
        end;
    end loop;
    return checked;
end;
$$;

set local role authenticated;
select pg_temp.act(7);
select pg_temp.assert_true(
    pg_temp.round_trip(15, 1, '2035-04-02') = 15
    and pg_temp.round_trip(36, 1, '2035-04-13') = 24
    and pg_temp.round_trip(37, 3, '2035-05-01') = 48,
    'Every candidate round-trips through propose with an identical start and end'
);
reset role;

-- A 60-day read stays fast (cf. the Slice 16 statement-timeout correction).
create temporary table timing on commit drop as select clock_timestamp() as started;
set local role authenticated;
select pg_temp.assert_true(cardinality(pg_temp.candidates(7, 15, '2035-04-01', '2035-05-31')) > 500,
    'A 60-day Veterinarian-constrained read returns its candidates');
reset role;
select pg_temp.assert_true((select clock_timestamp() - started < interval '3 seconds' from timing),
    'A 60-day candidate read completes within 3 seconds');

-- ===========================================================================
-- 10. Nothing persists.
-- ===========================================================================

rollback;

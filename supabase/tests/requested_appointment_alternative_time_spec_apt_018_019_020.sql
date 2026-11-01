-- Regression suite for the REQUESTED Appointment Alternative Time slice,
-- migration 20261010090000_requested_appointment_alternative_time.sql:
--   SPEC-APT-018 (Clinic proposal of an alternative time for a request),
--   SPEC-APT-019 (Guardian acceptance), SPEC-APT-020 (Professional candidate
--   read), SPEC-APT-016 generalized (withdrawal of a REQUESTED-base proposal),
--   the interactions amended into SPEC-APT-002/003/004/015, the reads amended
--   into SPEC-APT-011 BR-32/BR-33 and SPEC-APT-012 BR-44/BR-45, and
--   SPEC-COM-003 BR-71–BR-73.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables, and to switch
-- between impersonated Users. Every behavioral call goes through the real
-- trusted operations as the `authenticated` role; helper wrappers fire every
-- pending deferred trigger at the end of each call.
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
    select ('a1700000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('a1700000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('a1700000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'a1700000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('a1700000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'a1700000-0000-4000-8000-000000000a01'::uuid
$$;
create function pg_temp.vca(p_n integer) returns uuid language sql immutable as $$
    select ('a1700000-0000-4000-8000-0000000008' || lpad(p_n::text, 2, '0'))::uuid
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
create function pg_temp.alt_propose(
    p_user integer, p_n integer, p_date date, p_time time, p_offset integer, p_sequence integer,
    p_reason text default 'No veterinarian free at that time'
)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_requested_appointment_alternative_time(
        pg_temp.appt(p_n), p_date, p_time, p_offset, p_reason, p_sequence
    );
    perform pg_temp.flush();
    return created;
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

create function pg_temp.confirm(p_user integer, p_n integer, p_sequence integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.confirm_appointment(pg_temp.appt(p_n), p_sequence);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.guardian_reschedule(p_user integer, p_n integer, p_date date, p_time time, p_offset integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.reschedule_requested_appointment(pg_temp.appt(p_n), p_date, p_time, p_offset);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.cancel(p_user integer, p_n integer, p_context text, p_reason text, p_sequence integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.cancel_appointment(pg_temp.appt(p_n), p_context, p_reason, p_sequence);
    perform pg_temp.flush();
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
    from public.get_requested_appointment_alternative_candidate_start_times(pg_temp.appt(p_n), p_from, p_to) as candidate;
    return result;
end;
$$;

-- The Guardian and Clinic read rows of one Appointment.
create function pg_temp.guardian_row(p_n integer)
returns table (
    lifecycle_state text, start_at timestamptz, end_at timestamptz,
    pending_id uuid, pending_state text, pending_context text,
    pending_start_at timestamptz, pending_end_at timestamptz, pending_reason text,
    source_id uuid, source_context text
) language plpgsql as $$
begin
    perform pg_temp.act(1);
    return query
    select read_row.lifecycle_state, read_row.current_scheduled_start_at, read_row.current_scheduled_end_at,
           read_row.pending_reschedule_proposal_id, read_row.pending_reschedule_proposal_state,
           read_row.pending_reschedule_proposing_context, read_row.pending_reschedule_proposed_start_at,
           read_row.pending_reschedule_proposed_end_at, read_row.pending_reschedule_reason,
           read_row.current_schedule_source_proposal_id, read_row.current_schedule_source_proposing_context
    from public.get_pet_appointments(pg_temp.luna()) as read_row
    where read_row.id = pg_temp.appt(p_n);
end;
$$;

create function pg_temp.clinic_row(p_n integer, p_clinic integer)
returns table (
    lifecycle_state text, start_at timestamptz, sequence integer,
    pending_id uuid, pending_context text, pending_start_at timestamptz,
    source_id uuid, source_context text
) language plpgsql as $$
begin
    perform pg_temp.act(4);
    return query
    select read_row.lifecycle_state, read_row.current_scheduled_start_at,
           read_row.current_schedule_revision_sequence, read_row.pending_reschedule_proposal_id,
           read_row.pending_reschedule_proposing_context, read_row.pending_reschedule_proposed_start_at,
           read_row.current_schedule_source_proposal_id, read_row.current_schedule_source_proposing_context
    from public.get_clinic_appointment_schedule(pg_temp.clinic(p_clinic)) as read_row
    where read_row.id = pg_temp.appt(p_n);
end;
$$;

create function pg_temp.latest_revision(p_n integer) returns public.appointment_schedule_revisions language sql as $$
    select * from public.appointment_schedule_revisions
    where appointment_id = pg_temp.appt(p_n)
    order by revision_sequence desc limit 1
$$;

create function pg_temp.proposal(p_id uuid) returns public.appointment_reschedule_proposals language sql as $$
    select * from public.appointment_reschedule_proposals where id = p_id
$$;

create function pg_temp.lifecycle(p_n integer) returns text language sql as $$
    select lifecycle_state from public.appointments where id = pg_temp.appt(p_n)
$$;

create function pg_temp.event_count(p_n integer) returns bigint language sql as $$
    select count(*) from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(p_n)
$$;

create function pg_temp.communication_count(p_n integer) returns bigint language sql as $$
    select count(*) from public.transactional_communications where appointment_id = pg_temp.appt(p_n)
$$;

create function pg_temp.communications_of(p_proposal uuid, p_type text) returns uuid[] language sql as $$
    select coalesce(array_agg(recipient_user_id order by recipient_user_id), '{}')
    from public.transactional_communications
    where appointment_reschedule_proposal_id = p_proposal and communication_type = p_type
$$;

create function pg_temp.alternative_communication(p_proposal uuid, p_recipient integer) returns uuid language sql as $$
    select id from public.transactional_communications
    where appointment_reschedule_proposal_id = p_proposal
      and communication_type = 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
      and recipient_user_id = pg_temp.domain_user(p_recipient)
$$;

create function pg_temp.eligible(p_communication_id uuid) returns boolean language sql as $$
    select public.communication_delivery_is_currently_eligible(p_communication_id, 'EMAIL', null, null)
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
-- 1. Contract (signatures, attributes, ACLs, constraints).
-- ===========================================================================

select pg_temp.assert_true(
    (select pg_get_function_arguments(proc.oid)
                = 'p_appointment_id uuid, p_start_local_date date, p_start_local_time time without time zone, p_start_utc_offset_seconds integer, p_reason text, p_expected_requested_revision_sequence integer'
            and pg_get_function_result(proc.oid) = 'uuid'
            and proc.pronargdefaults = 0
            and proc.prosecdef and proc.provolatile = 'v'
            and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.propose_requested_appointment_alternative_time(uuid, date, time, integer, text, integer)'::regprocedure)
    and (select pg_get_function_arguments(proc.oid) = 'p_proposal_id uuid'
            and pg_get_function_result(proc.oid) = 'uuid'
            and proc.prosecdef and proc.provolatile = 'v'
            and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.accept_requested_appointment_alternative_time(uuid)'::regprocedure)
    and (select pg_get_function_arguments(proc.oid) = 'p_appointment_id uuid, p_start_date date, p_end_date date'
            and pg_get_function_result(proc.oid)
                = 'TABLE(candidate_local_date date, candidate_local_time time without time zone, utc_offset_seconds integer, candidate_end_at timestamp with time zone)'
            and proc.prosecdef and proc.provolatile = 's'
            and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.get_requested_appointment_alternative_candidate_start_times(uuid, date, date)'::regprocedure),
    'Contract: propose (no defaults: reason and token required), accept (proposal id only, no stale token), and the STABLE candidate read'
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
         'public.propose_requested_appointment_alternative_time(uuid, date, time, integer, text, integer)',
         'public.accept_requested_appointment_alternative_time(uuid)',
         'public.get_requested_appointment_alternative_candidate_start_times(uuid, date, date)',
         'public.withdraw_appointment_reschedule_proposal(uuid)',
         'public.get_appointment_reschedule_candidate_start_times(uuid, date, date)',
         'public.get_pet_appointments(uuid)',
         'public.get_clinic_appointment_schedule(uuid)'
     ]) as signature)
    and not has_function_privilege('authenticated',
        'public.appointment_reschedule_candidate_positions(uuid, uuid, text, date, date, bigint, timestamptz, timestamptz)', 'EXECUTE')
    and not has_function_privilege('anon',
        'public.appointment_reschedule_candidate_positions(uuid, uuid, text, date, date, bigint, timestamptz, timestamptz)', 'EXECUTE'),
    'Contract: the RPCs and reads are granted only to authenticated (and service_role); the shared grid generator is internal'
);

select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc where proname = 'withdraw_appointment_reschedule_proposal' and pronamespace = 'public'::regnamespace)
    and (select count(*) = 0 from pg_proc where proname like '%alternative%withdraw%' and pronamespace = 'public'::regnamespace)
    and (select count(*) = 0 from pg_class where relname like '%alternative%' and relkind = 'r' and relnamespace = 'public'::regnamespace)
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_reschedule_proposals_base_revision_context_check')
        = 'CHECK ((base_revision_context = ANY (ARRAY[''REQUESTED''::text, ''CONFIRMED''::text])))'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_reschedule_proposals_requested_base_clinic_check')
        = 'CHECK (((base_revision_context <> ''REQUESTED''::text) OR (proposing_context = ''CLINIC''::text)))'
    and exists (select 1 from pg_indexes where indexname = 'appointment_reschedule_proposals_pending_key')
    and exists (select 1 from pg_indexes where indexname = 'transactional_communications_alternative_time_proposed_key')
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'transactional_communications_type_check')
        like '%APPOINTMENT_ALTERNATIVE_TIME_PROPOSED%'
    and (select count(*) = 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'transactional_communications'
           and column_name like '%proposal%'),
    'Contract: one unified Proposal table and one withdraw RPC; REQUESTED base Clinic-only; one Proposal reference on Communications'
);

select pg_temp.assert_true(
    pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure)
        like '%cancellation_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_acceptable boolean, medical_access_state text)'
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)
        like '%pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)'
    and (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
         from pg_proc as proc where proc.oid = 'public.get_pet_appointments(uuid)'::regprocedure)
    and (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
         from pg_proc as proc where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure),
    'Contract: both reads append exactly the two provenance columns'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects a1700000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current, requester)   08 RECEPTIONIST @ A1 (Clinic)
--   02 Guardian G2 (current)              09 RECEPTIONIST @ A2 (Clinic)
--   03 former Guardian G3                 10 VETERINARIAN only, assigned @ A1 and @ B1
--   04 OrgA OWNER                         13 OrgA RECEPTIONIST (Org), Grant ended in-suite
--   07 OrgA RECEPTIONIST (Org)            14 VETERINARIAN whose Clinic Assignment @ A1 ended
--                                         16 OWNER of the PAST_DUE Org
-- Organizations: OrgA ACTIVE (A1 01, A2 02, A3 03 unpublished, A4 04 without
-- a standard duration, A7 07 unpublished, for standard-duration changes), OrgB ACTIVE
-- (B1 06), PAST_DUE (C5 05). Every Clinic: Europe/Madrid, Appointment
-- Availability 08:00–20:00 every day, 30-minute standard duration unless noted.
-- Veterinarian 10 is available 08:00–18:00 every day @ A1 (vca 10) and @ B1
-- (vca 11); Veterinarian 14's vca 12 @ A1 ended in 2021. Every Appointment is
-- Luna's, requested by G1; Appointment n has Care Authorization c<n>.
-- March 2035 is CET (+01:00), April 2035 CEST (+02:00).
-- ===========================================================================

insert into auth.users (id, email, email_confirmed_at)
select ('a1700000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       'alt' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 16]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 16]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('a1700000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 16]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('a1700000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('a1700000-0000-4000-8000-000000000302', 'Other Veterinary Group'),
    ('a1700000-0000-4000-8000-000000000304', 'Org Past Due');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    (pg_temp.clinic(1), 'a1700000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), 'a1700000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(3), 'a1700000-0000-4000-8000-000000000301', false, 'Europe/Madrid', 30),
    (pg_temp.clinic(4), 'a1700000-0000-4000-8000-000000000301', true, 'Europe/Madrid', null),
    (pg_temp.clinic(5), 'a1700000-0000-4000-8000-000000000304', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(6), 'a1700000-0000-4000-8000-000000000302', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(7), 'a1700000-0000-4000-8000-000000000301', false, 'Europe/Madrid', 30);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(n), weekday, '08:00', '20:00'
from unnest(array[1, 2, 3, 4, 5, 6, 7]) as n, generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('a1700000-0000-4000-8000-000000000504', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000507', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000508', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(8), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000509', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(9), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000510', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000520', 'a1700000-0000-4000-8000-000000000302', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000513', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(13), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000514', 'a1700000-0000-4000-8000-000000000301', pg_temp.domain_user(14), '2020-01-01Z', null, null),
    ('a1700000-0000-4000-8000-000000000516', 'a1700000-0000-4000-8000-000000000304', pg_temp.domain_user(16), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('a1700000-0000-4000-8000-000000000604', 'a1700000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000607', 'a1700000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000608', 'a1700000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000609', 'a1700000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000610', 'a1700000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000620', 'a1700000-0000-4000-8000-000000000520', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000613', 'a1700000-0000-4000-8000-000000000513', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000614', 'a1700000-0000-4000-8000-000000000514', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a1700000-0000-4000-8000-000000000616', 'a1700000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('a1700000-0000-4000-8000-000000000710', pg_temp.domain_user(10)),
    ('a1700000-0000-4000-8000-000000000714', pg_temp.domain_user(14));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.vca(10), 'a1700000-0000-4000-8000-000000000710', 'a1700000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z', null),
    (pg_temp.vca(11), 'a1700000-0000-4000-8000-000000000710', 'a1700000-0000-4000-8000-000000000520', pg_temp.clinic(6), '2020-01-01Z', null),
    (pg_temp.vca(12), 'a1700000-0000-4000-8000-000000000714', 'a1700000-0000-4000-8000-000000000514', pg_temp.clinic(1), '2020-01-01Z', '2021-01-01Z');
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time)
select assignment_id, weekday, '08:00', '18:00'
from unnest(array[pg_temp.vca(10), pg_temp.vca(11), pg_temp.vca(12)]) as assignment_id,
     generate_series(1, 7) as weekday;

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('a1700000-0000-4000-8000-000000000901', 'a1700000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',   '2020-01-01Z', null, null, 'alternative-test', 'a1700000-0000-4000-8000-000000000991'),
    ('a1700000-0000-4000-8000-000000000902', 'a1700000-0000-4000-8000-000000000302', '2020-01-01Z', 'ACTIVE',   '2020-01-01Z', null, null, 'alternative-test', 'a1700000-0000-4000-8000-000000000992'),
    ('a1700000-0000-4000-8000-000000000904', 'a1700000-0000-4000-8000-000000000304', '2020-01-01Z', 'PAST_DUE', '2020-01-01Z', null, null, 'alternative-test', 'a1700000-0000-4000-8000-000000000994');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('a1700000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null),
    ('a1700000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z', null),
    ('a1700000-0000-4000-8000-000000000a13', pg_temp.domain_user(3), pg_temp.luna(), '2020-01-01Z', '2021-01-01Z');

-- An Appointment requested on 2026-01-01 (revision 1 REQUESTED, ACTIVE Care
-- Authorization) and, when CONFIRMED, confirmed on 2026-02-01 (revision 2).
create function pg_temp.seed(
    p_n integer, p_clinic integer, p_start timestamptz, p_state text, p_duration interval default interval '30 minutes'
)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), pg_temp.clinic(p_clinic), pg_temp.domain_user(1), 'Visit ' || p_n,
            p_state, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + p_duration, 'Europe/Madrid',
              pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) select pg_temp.ca(p_n), pg_temp.luna(), clinic.id, clinic.organization_id, 'a1700000-0000-4000-8000-000000000a11',
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

-- A PENDING REQUESTED-base Clinic Proposal no trusted operation can create on
-- demand (a lapsed time, a proposer at a PAST_DUE Organization).
create function pg_temp.fixture_proposal(
    p_name text, p_n integer, p_start timestamptz, p_by integer, p_created timestamptz default '2026-03-01T00:00Z'
) returns void language sql as $$
    insert into public.appointment_reschedule_proposals (
        id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
        proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
    ) values (
        gen_random_uuid(), pg_temp.appt(p_n),
        (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(p_n) and revision_sequence = 1),
        'REQUESTED', p_start, p_start + interval '30 minutes', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(p_by),
        'Fixture alternative', p_created
    );
    select pg_temp.keep(p_name, (select id from public.appointment_reschedule_proposals
                                 where appointment_id = pg_temp.appt(p_n) and reason = 'Fixture alternative'));
$$;

select pg_temp.seed(1, 1, '2035-03-05T09:00Z', 'REQUESTED');   -- 10:00 local: invalid input, stale, lapse
select pg_temp.seed(2, 1, '2035-03-05T10:00Z', 'REQUESTED');   -- happy path through confirmation
select pg_temp.seed(3, 3, '2035-03-05T11:00Z', 'REQUESTED');   -- unpublished Clinic
select pg_temp.seed(4, 4, '2035-03-05T12:00Z', 'REQUESTED');   -- no standard duration
select pg_temp.seed(5, 7, '2035-03-05T13:00Z', 'REQUESTED');   -- frozen interval
select pg_temp.seed(6, 7, '2035-03-05T14:00Z', 'REQUESTED');   -- same start
select pg_temp.seed(7, 1, '2035-04-02T08:00Z', 'REQUESTED');   -- 10:00 CEST, Veterinarian 10
select pg_temp.seed(8, 1, '2035-04-03T08:00Z', 'REQUESTED');   -- Veterinarian 14, Assignment ended
select pg_temp.seed(9, 1, '2035-04-02T10:00Z', 'CONFIRMED', interval '60 minutes'); -- Veterinarian 10 busy 12:00–13:00 CEST
select pg_temp.seed(10, 1, '2035-03-06T09:00Z', 'REQUESTED');  -- one open proposal
select pg_temp.seed(11, 1, '2035-03-06T10:00Z', 'REQUESTED');  -- Guardian reschedule
select pg_temp.seed(12, 1, '2035-03-06T11:00Z', 'REQUESTED');  -- Clinic confirmation
select pg_temp.seed(13, 1, '2035-03-06T12:00Z', 'REQUESTED');  -- Guardian cancellation
select pg_temp.seed(14, 1, '2035-03-06T13:00Z', 'REQUESTED');  -- Clinic cancellation
select pg_temp.seed(15, 1, '2026-01-15T09:00Z', 'REQUESTED');  -- logically expired request
select pg_temp.seed(16, 1, '2035-03-06T14:00Z', 'REQUESTED');  -- proposer authority lost
select pg_temp.seed(17, 1, '2035-03-07T09:00Z', 'REQUESTED');  -- withdrawal
select pg_temp.seed(18, 1, '2035-03-08T09:00Z', 'REQUESTED');  -- acceptance revalidation
select pg_temp.seed(19, 5, '2035-03-08T10:00Z', 'REQUESTED');  -- PAST_DUE: accept
select pg_temp.seed(20, 1, '2035-03-06T09:00Z', 'REQUESTED');  -- candidates
select pg_temp.seed(21, 7, '2035-03-06T09:00Z', 'REQUESTED');  -- candidates after duration change
select pg_temp.seed(22, 1, '2035-03-09T09:00Z', 'REQUESTED');  -- workflows do not cross
select pg_temp.seed(23, 1, '2035-03-09T10:00Z', 'CONFIRMED');
select pg_temp.seed(24, 5, '2035-03-08T11:00Z', 'REQUESTED');  -- PAST_DUE: withdraw
select pg_temp.assign_vet(n, 10) from unnest(array[7, 9]) as n;
select pg_temp.assign_vet(8, 12);
-- Lapsed (1), base-lapsed (15), and PAST_DUE (19, 24) Proposals.
select pg_temp.fixture_proposal('lapsed1', 1, '2026-01-10T09:00Z', 7);
select pg_temp.fixture_proposal('lapsed15', 15, '2035-04-01T09:00Z', 8);
select pg_temp.fixture_proposal('pastdue19', 19, '2035-03-09T10:00Z', 16);
select pg_temp.fixture_proposal('pastdue24', 24, '2035-03-09T11:00Z', 16);

set local session_replication_role = origin;
select pg_temp.flush();
select pg_temp.remember(1);

-- ===========================================================================
-- 2. Invalid input before any state; Clinic-only, capability, scope, and
--    Entitlement at proposal (SPEC-APT-018 BR-2–BR-9).
-- ===========================================================================

set local role authenticated;
select pg_temp.act(8);
select pg_temp.assert_error(format('select public.propose_requested_appointment_alternative_time(%L, ''2035-03-06'', ''12:00'', 3600, ''Busy'', %s)', pg_temp.appt(1), bad),
    '22023', 'Expected requested revision sequence must be a positive integer')
from unnest(array['null', '0', '-1']) as bad;
select pg_temp.assert_error(format('select public.propose_requested_appointment_alternative_time(%L, ''2035-03-06'', ''12:00'', 3600, %L, 1)', pg_temp.appt(1), bad),
    '22023', 'A meaningful reason is required for a Clinic alternative time proposal')
from unnest(array[null, '', ' ', E'\t\n ']::text[]) as bad;
-- Structural checks precede the Appointment lookup.
select pg_temp.assert_error('select public.propose_requested_appointment_alternative_time(''a1700000-0000-4000-8000-0000000000ff'', ''2035-03-06'', ''12:00'', 3600, ''Busy'', 0)',
    '22023', 'Expected requested revision sequence must be a positive integer');
select pg_temp.assert_error('select public.propose_requested_appointment_alternative_time(''a1700000-0000-4000-8000-0000000000ff'', ''2035-03-06'', ''12:00'', 3600, ''Busy'', 1)',
    '23503', 'Appointment does not exist');
-- Clinic only: a Guardian, a Veterinarian, or a Clinic actor of another Clinic
-- holds no APPOINTMENT_RESCHEDULE for A1.
select pg_temp.assert_error(format('select pg_temp.alt_propose(%s, 1, ''2035-03-06'', ''12:00'', 3600, 1)', actor),
    '42501', 'Applicable Appointment-management capability is required')
from unnest(array[1, 2, 9, 10]) as actor;
-- Entitlement at proposal: the PAST_DUE Organization's OWNER is denied.
select pg_temp.assert_error('select pg_temp.alt_propose(16, 19, ''2035-03-10'', ''12:00'', 3600, 1)',
    '42501', 'Applicable professional Entitlement is required');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(1), 'Invalid input and denied proposals write nothing');

-- ===========================================================================
-- 3. Stale token: P0001, zero writes (no lazy VOID, no Communication), then
--    refresh-and-retry succeeds and makes the lapsed Proposal VOID
--    (SPEC-APT-018 BR-8, BR-9, BR-16).
-- ===========================================================================

set local role authenticated;
select pg_temp.assert_error('select pg_temp.alt_propose(8, 1, ''2035-03-06'', ''12:00'', 3600, 2)', 'P0001',
    'Stale requested Appointment schedule revision for alternative time proposal');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(1) and (pg_temp.proposal(pg_temp.id('lapsed1'))).state = 'PENDING',
    'A stale proposal writes nothing: the lapsed Proposal is not made VOID and no Communication exists'
);
set local role authenticated;
select pg_temp.keep('p1', pg_temp.alt_propose(8, 1, '2035-03-06', '12:00', 3600, 1));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('lapsed1'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('lapsed1'))).void_reason = 'PROPOSED_TIME_PASSED'
    and (pg_temp.proposal(pg_temp.id('p1'))).state = 'PENDING',
    'Refresh-and-retry succeeds; the lapsed Proposal becomes VOID PROPOSED_TIME_PASSED atomically'
);

-- ===========================================================================
-- 4. Successful proposal: frozen interval from the current standard duration;
--    the request is unchanged; Communications (SPEC-APT-018 BR-7, BR-11,
--    BR-12, BR-20; SPEC-COM-003 BR-71).
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p2', pg_temp.alt_propose(8, 2, '2035-03-06', '12:00', 3600, 1, '  No veterinarian free at 11:00  '));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p2'))).base_revision_context = 'REQUESTED'
    and (pg_temp.proposal(pg_temp.id('p2'))).base_revision_id
        = (select id from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(2) and revision_sequence = 1)
    and (pg_temp.proposal(pg_temp.id('p2'))).proposing_context = 'CLINIC'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_by_user_id = pg_temp.domain_user(8)
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_start_at = '2035-03-06T11:00Z'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_end_at = '2035-03-06T11:30Z'
    and (pg_temp.proposal(pg_temp.id('p2'))).proposed_timezone_name = 'Europe/Madrid'
    and (pg_temp.proposal(pg_temp.id('p2'))).reason = 'No veterinarian free at 11:00'
    and (pg_temp.proposal(pg_temp.id('p2'))).state = 'PENDING',
    'The Proposal binds the reviewed REQUESTED revision, derives end = start + 30 min, trims the reason'
);
select pg_temp.assert_true(
    pg_temp.lifecycle(2) = 'REQUESTED'
    and (pg_temp.latest_revision(2)).revision_sequence = 1
    and (pg_temp.latest_revision(2)).scheduled_start_at = '2035-03-05T10:00Z'
    and pg_temp.event_count(2) = 0,
    'Proposing never changes the request: still REQUESTED at the Guardian time, no revision, no Lifecycle Event'
);
select pg_temp.assert_true(
    pg_temp.communications_of(pg_temp.id('p2'), 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED')
        = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
    and pg_temp.communications_of(pg_temp.id('p2'), 'APPOINTMENT_RESCHEDULE_PROPOSED') = '{}'
    and (select count(*) = 2 from public.transactional_communications
         where appointment_reschedule_proposal_id = pg_temp.id('p2')
           and appointment_schedule_revision_id is null and appointment_lifecycle_event_id is null)
    and pg_temp.eligible(pg_temp.alternative_communication(pg_temp.id('p2'), 1)),
    'Current Guardians (not the former one) each get APPOINTMENT_ALTERNATIVE_TIME_PROPOSED, never RESCHEDULE_PROPOSED; deliverable while actionable'
);
select pg_temp.assert_true(
    (select pending_id = pg_temp.id('p2') and pending_state = 'PENDING' and pending_context = 'CLINIC'
            and pending_start_at = '2035-03-06T11:00Z' and pending_end_at = '2035-03-06T11:30Z'
            and pending_reason = 'No veterinarian free at 11:00'
            and lifecycle_state = 'REQUESTED' and start_at = '2035-03-05T10:00Z'
            and source_id is null and source_context is null
     from pg_temp.guardian_row(2))
    and (select pending_id = pg_temp.id('p2') and pending_context = 'CLINIC' and sequence = 1
                and start_at = '2035-03-05T10:00Z' and source_id is null
         from pg_temp.clinic_row(2, 1)),
    'Both reads show the pending alternative without changing the current requested interval or sequence'
);

-- Publication is irrelevant (BR-5).
set local role authenticated;
select pg_temp.keep('p3', pg_temp.alt_propose(4, 3, '2035-03-06', '12:00', 3600, 1));
reset role;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p3'))).state = 'PENDING', 'An unpublished Clinic may propose');

-- Standard duration required (BR-11).
select pg_temp.remember(4);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.alt_propose(4, 4, ''2035-03-06'', ''12:00'', 3600, 1)',
    '23514', 'Clinic has no currently configured standard Appointment duration');
select pg_temp.assert_error('select pg_temp.candidates(4, 4, ''2035-03-06'', ''2035-03-07'')',
    '23514', 'Clinic has no currently configured standard Appointment duration');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(4), 'No standard duration: no proposal, no write');

-- ===========================================================================
-- 5. Same start and duration (SPEC-APT-018 BR-11–BR-14, SPEC-APT-019 BR-6).
-- ===========================================================================

select pg_temp.remember(6);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.alt_propose(4, 6, ''2035-03-05'', ''15:00'', 3600, 1)',
    '22023', 'Proposed time must differ from the current requested time');
reset role;
update public.clinics set standard_appointment_duration_minutes = 45 where id = pg_temp.clinic(7);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.alt_propose(4, 6, ''2035-03-05'', ''15:00'', 3600, 1)',
    '22023', 'Proposed time must differ from the current requested time');
select pg_temp.assert_error('select pg_temp.alt_propose(4, 6, ''2026-01-02'', ''15:00'', 3600, 1)',
    '22023', 'Proposed Appointment time must be in the future');
-- The duration applied is the current one at creation: 45 minutes now.
select pg_temp.keep('p6', pg_temp.alt_propose(4, 6, '2035-03-07', '10:00', 3600, 1));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p6'))).proposed_end_at - (pg_temp.proposal(pg_temp.id('p6'))).proposed_start_at = interval '45 minutes',
    'Same start is rejected even after a duration change; a new proposal uses the duration current at creation'
);
update public.clinics set standard_appointment_duration_minutes = 30 where id = pg_temp.clinic(7);

-- Frozen interval: a later standard-duration change neither alters the
-- Proposal nor what acceptance establishes.
set local role authenticated;
select pg_temp.keep('p5', pg_temp.alt_propose(4, 5, '2035-03-06', '10:00', 3600, 1));
reset role;
update public.clinics set standard_appointment_duration_minutes = 60 where id = pg_temp.clinic(7);
set local role authenticated;
select pg_temp.alt_accept(1, pg_temp.id('p5'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p5'))).proposed_end_at = '2035-03-06T09:30Z'
    and (pg_temp.latest_revision(5)).scheduled_start_at = '2035-03-06T09:00Z'
    and (pg_temp.latest_revision(5)).scheduled_end_at = '2035-03-06T09:30Z',
    'The interval is frozen at creation and acceptance establishes it exactly'
);
update public.clinics set standard_appointment_duration_minutes = null where id = pg_temp.clinic(7);
select pg_temp.assert_true(
    (pg_temp.latest_revision(5)).scheduled_end_at = '2035-03-06T09:30Z',
    'Removing the standard duration afterwards changes nothing'
);
update public.clinics set standard_appointment_duration_minutes = 30 where id = pg_temp.clinic(7);

-- ===========================================================================
-- 6. Feasibility at creation, generic and non-disclosing (SPEC-APT-018 BR-15).
-- ===========================================================================

select pg_temp.remember(7);
select pg_temp.remember(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.alt_propose(8, 7, ''2035-04-02'', ''20:00'', 7200, 1)',
    '23514', 'Clinic Appointment Availability does not cover the proposed interval');
-- Outside Veterinarian Availability and a known confirmed conflict elsewhere in
-- the schedule are reported identically.
select pg_temp.assert_error(format('select pg_temp.alt_propose(8, 7, ''2035-04-02'', %L, 7200, 1)', local_time),
    '23514', 'Currently assigned Veterinarian is not available for the proposed interval')
from unnest(array['18:00', '12:00', '12:30']) as local_time;
select pg_temp.assert_error('select pg_temp.alt_propose(8, 8, ''2035-04-03'', ''12:00'', 7200, 1)',
    '23514', 'Currently assigned Veterinarian no longer has a valid Clinic Assignment');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(7) and pg_temp.unchanged(8), 'Infeasible proposals write nothing');
set local role authenticated;
select pg_temp.keep('p7', pg_temp.alt_propose(8, 7, '2035-04-02', '14:00', 7200, 1));
reset role;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p7'))).proposed_start_at = '2035-04-02T12:00Z',
    'A feasible time for the assigned Veterinarian is accepted');

-- ===========================================================================
-- 7. One open proposal per Appointment (SPEC-APT-018 BR-16).
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p10', pg_temp.alt_propose(8, 10, '2035-03-07', '11:00', 3600, 1));
select pg_temp.assert_error('select pg_temp.alt_propose(7, 10, ''2035-03-07'', ''12:00'', 3600, 1)',
    '23505', 'already has an actionable unresolved reschedule Proposal');
reset role;
select pg_temp.assert_true(
    (select count(*) = 1 from public.appointment_reschedule_proposals
     where appointment_id = pg_temp.appt(10) and state = 'PENDING'),
    'A second proposal is rejected; one PENDING Proposal remains'
);
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''REQUESTED'', ''2035-03-08T09:00Z'', ''2035-03-08T09:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', now())',
    pg_temp.appt(10), (pg_temp.latest_revision(10)).id, pg_temp.domain_user(7)),
    '23505', 'appointment_reschedule_proposals_pending_key');
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''REQUESTED'', ''2035-03-08T09:00Z'', ''2035-03-08T09:30Z'', ''Europe/Madrid'', ''GUARDIAN'', %L, null, now())',
    pg_temp.appt(22), (pg_temp.latest_revision(22)).id, pg_temp.domain_user(1)),
    '23514', 'appointment_reschedule_proposals_requested_base_clinic_check');
-- No Guardian-originated REQUESTED-base Proposal can exist, even when loaded
-- with triggers bypassed, and the CHECK is validated for every stored row:
-- propose_requested_appointment_alternative_time has no Guardian lazy-VOID
-- branch (20261017100000). Its remaining lazy paths are covered here: an
-- actionable Clinic proposal blocks (p10), a passed one becomes VOID
-- PROPOSED_TIME_PASSED (lapsed1), a lost Clinic authority PROPOSING_AUTHORITY_LOST (p16).
set local session_replication_role = replica;
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''REQUESTED'', ''2035-03-08T09:00Z'', ''2035-03-08T09:30Z'', ''Europe/Madrid'', ''GUARDIAN'', %L, null, now())',
    pg_temp.appt(22), (pg_temp.latest_revision(22)).id, pg_temp.domain_user(1)),
    '23514', 'appointment_reschedule_proposals_requested_base_clinic_check');
set local session_replication_role = origin;
select pg_temp.assert_true(
    (select convalidated from pg_constraint
     where conname = 'appointment_reschedule_proposals_requested_base_clinic_check'),
    'REQUESTED-base Proposals are Clinic-only by a CHECK validated for every stored row'
);

-- ===========================================================================
-- 8. Acceptance (SPEC-APT-019): disclosure ordering, Guardian only, exactly
--    one REQUESTED revision with provenance, no confirmation, no
--    Communication; then Clinic confirmation of N+1.
-- ===========================================================================

select pg_temp.remember(2);
set local role authenticated;
-- A User without current Guardianship — a Clinic actor, a former Guardian —
-- is denied before any proposal or lifecycle state is disclosed, identically
-- for a PENDING (2) and an ACCEPTED (5) Proposal.
select pg_temp.assert_error(format('select pg_temp.alt_accept(%s, %L)', actor, proposal_id),
    '42501', 'Current Guardianship of the Appointment Pet is required')
from unnest(array[3, 4, 8]) as actor, unnest(array[pg_temp.id('p2'), pg_temp.id('p5')]) as proposal_id;
select pg_temp.assert_error('select pg_temp.alt_accept(1, ''a1700000-0000-4000-8000-0000000000ff'')',
    '23503', 'Reschedule Proposal does not exist');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(2), 'Denied acceptance writes nothing');

select pg_temp.remember(2);
set local role authenticated;
select pg_temp.alt_accept(2, pg_temp.id('p2'));   -- G2: a current Guardian, not the requester
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p2'))).state = 'ACCEPTED'
    and (select count(*) = 1 from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p2'))
    and (pg_temp.latest_revision(2)).revision_sequence = 2
    and (pg_temp.latest_revision(2)).revision_context = 'REQUESTED'
    and (pg_temp.latest_revision(2)).source_proposal_id = pg_temp.id('p2')
    and (pg_temp.latest_revision(2)).established_by_user_id = pg_temp.domain_user(2)
    and (pg_temp.latest_revision(2)).scheduled_start_at = '2035-03-06T11:00Z'
    and (pg_temp.latest_revision(2)).scheduled_end_at = '2035-03-06T11:30Z'
    and (pg_temp.latest_revision(2)).establishment_timezone_name = 'Europe/Madrid'
    and pg_temp.lifecycle(2) = 'REQUESTED'
    and pg_temp.event_count(2) = 0
    and (select requesting_user_id = pg_temp.domain_user(1) from public.appointments where id = pg_temp.appt(2))
    and pg_temp.communication_count(2) = 2,
    'Acceptance: ACCEPTED, exactly one REQUESTED revision 2 = frozen interval, by the accepting Guardian, sourced from the Proposal; still REQUESTED; no Lifecycle Event; no Communication'
);
select pg_temp.assert_true(
    not pg_temp.eligible(pg_temp.alternative_communication(pg_temp.id('p2'), 1))
    and (select pending_id is null and lifecycle_state = 'REQUESTED' and start_at = '2035-03-06T11:00Z'
                and end_at = '2035-03-06T11:30Z' and source_id = pg_temp.id('p2') and source_context = 'CLINIC'
         from pg_temp.guardian_row(2))
    and (select pending_id is null and sequence = 2 and source_id = pg_temp.id('p2') and source_context = 'CLINIC'
         from pg_temp.clinic_row(2, 1)),
    'After acceptance: the undelivered alternative Communication is suppressed; both reads show the accepted interval, awaiting confirmation (REQUESTED + Clinic source)'
);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.alt_accept(%s, %L)', actor, pg_temp.id('p2')),
    '23514', 'Reschedule Proposal is no longer actionable')
from unnest(array[1, 2]) as actor;
-- Confirmation: the pre-acceptance sequence is stale; N+1 confirms exactly the
-- accepted interval.
select pg_temp.assert_error('select pg_temp.confirm(8, 2, 1)', 'P0001', 'Stale requested Appointment schedule revision');
select pg_temp.confirm(8, 2, 2);
reset role;
select pg_temp.assert_true(
    pg_temp.lifecycle(2) = 'CONFIRMED'
    and (pg_temp.latest_revision(2)).revision_context = 'CONFIRMED'
    and (pg_temp.latest_revision(2)).scheduled_start_at = '2035-03-06T11:00Z'
    and (pg_temp.latest_revision(2)).scheduled_end_at = '2035-03-06T11:30Z'
    and (pg_temp.latest_revision(2)).source_proposal_id is null
    and (select count(*) = 2 from public.transactional_communications
         where appointment_id = pg_temp.appt(2) and communication_type = 'APPOINTMENT_CONFIRMED')
    and (select source_id is null and lifecycle_state = 'CONFIRMED' from pg_temp.guardian_row(2)),
    'The Clinic then confirms N+1: CONFIRMED at the accepted interval, ordinary confirmation Communications, no longer awaiting'
);

-- No Entitlement gate at acceptance (BR-4): the PAST_DUE Organization's
-- Proposal is accepted by a current Guardian.
set local role authenticated;
select pg_temp.alt_accept(1, pg_temp.id('pastdue19'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('pastdue19'))).state = 'ACCEPTED' and pg_temp.lifecycle(19) = 'REQUESTED',
    'Guardian acceptance needs no APPOINTMENT_MANAGEMENT Entitlement'
);

-- Revalidation at acceptance (BR-6): a feasibility failure writes nothing
-- and leaves the Proposal PENDING.
set local role authenticated;
select pg_temp.keep('p18', pg_temp.alt_propose(8, 18, '2035-03-11', '11:00', 3600, 1));
select pg_temp.act(4);
select public.set_clinic_appointment_availability_exception(pg_temp.clinic(1), '2035-03-11', 'CLOSED', '[]'::jsonb);
reset role;
select pg_temp.remember(18);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('p18')),
    '23514', 'Clinic Appointment Availability does not cover the proposed interval');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(18) and (pg_temp.proposal(pg_temp.id('p18'))).state = 'PENDING',
    'A failed revalidation writes nothing; the Proposal stays PENDING'
);

-- ===========================================================================
-- 9. Interactions that end the proposal (SPEC-APT-018 BR-17, BR-18;
--    SPEC-APT-002 BR-24, SPEC-APT-003 BR-30, SPEC-APT-004 BR-28,
--    SPEC-APT-015 BR-19).
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p11', pg_temp.alt_propose(8, 11, '2035-03-08', '12:00', 3600, 1));
select pg_temp.keep('p12', pg_temp.alt_propose(8, 12, '2035-03-08', '13:00', 3600, 1));
select pg_temp.keep('p13', pg_temp.alt_propose(8, 13, '2035-03-08', '14:00', 3600, 1));
select pg_temp.keep('p14', pg_temp.alt_propose(8, 14, '2035-03-08', '15:00', 3600, 1));
-- Guardian requested reschedule: allowed; supersedes the base.
select pg_temp.guardian_reschedule(2, 11, '2035-03-10', '10:00', 3600);
-- Clinic confirmation without withdrawing first: confirms the Guardian time.
select pg_temp.confirm(8, 12, 1);
-- Guardian and Clinic cancellation.
select pg_temp.cancel(1, 13, 'GUARDIAN', null, null);
select pg_temp.cancel(8, 14, 'CLINIC', 'Clinic closed', 1);
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p11'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p11'))).void_reason = 'BASE_REVISION_SUPERSEDED'
    and (pg_temp.latest_revision(11)).revision_sequence = 2
    and (pg_temp.latest_revision(11)).source_proposal_id is null
    and (pg_temp.latest_revision(11)).scheduled_start_at = '2035-03-10T09:00Z'
    and pg_temp.lifecycle(11) = 'REQUESTED',
    'Guardian reschedule: an unsourced Guardian revision; the alternative is VOID BASE_REVISION_SUPERSEDED'
);
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p12'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p12'))).void_reason = 'BASE_REVISION_SUPERSEDED'
    and pg_temp.lifecycle(12) = 'CONFIRMED'
    and (pg_temp.latest_revision(12)).scheduled_start_at = '2035-03-06T11:00Z',
    'Clinic confirmation confirms the requested time and makes the alternative VOID BASE_REVISION_SUPERSEDED'
);
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p13'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p13'))).void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED'
    and (pg_temp.proposal(pg_temp.id('p14'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p14'))).void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED'
    and pg_temp.lifecycle(13) = 'CANCELLED' and pg_temp.lifecycle(14) = 'CANCELLED',
    'Guardian and Clinic cancellation make the alternative VOID APPOINTMENT_LIFECYCLE_CHANGED'
);
select pg_temp.assert_true(
    not pg_temp.eligible(pg_temp.alternative_communication(pg_temp.id(name), 1))
    and (select pending_id is null from pg_temp.guardian_row(n)),
    format('Superseded alternative %s is neither delivered nor shown', name)
)
from (values ('p11', 11), ('p12', 12), ('p13', 13), ('p14', 14)) as superseded(name, n);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('p11')),
    '23514', 'Alternative time proposal base revision is no longer the current requested context');
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('p12')),
    '23514', 'Appointment must remain REQUESTED to accept an alternative time');
-- Disclosure ordering (SPEC-APT-019 BR-3): a non-Guardian learns nothing about
-- the CONFIRMED (12) or CANCELLED (13) Appointment behind a Proposal.
select pg_temp.assert_error(format('select pg_temp.alt_accept(%s, %L)', actor, pg_temp.id(name)),
    '42501', 'Current Guardianship of the Appointment Pet is required')
from unnest(array[3, 8]) as actor, unnest(array['p12', 'p13']) as name;
select pg_temp.assert_error(format('select pg_temp.withdraw(8, %L)', pg_temp.id('p13')),
    '23514', 'Reschedule Proposal is no longer actionable');
-- Expiry: a lapsed request's alternative is not actionable before expiry is
-- materialized, and becomes VOID when it is.
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('lapsed15')),
    '23514', 'A REQUESTED Appointment whose requested time has passed cannot be rescheduled');
select pg_temp.assert_error('select pg_temp.alt_propose(8, 15, ''2035-04-02'', ''12:00'', 7200, 1)',
    '23514', 'A REQUESTED Appointment whose requested time has passed cannot receive an alternative time proposal');
reset role;
select pg_temp.assert_true(
    (select pending_id is null from pg_temp.guardian_row(15)),
    'A lapsed request does not show its alternative as pending'
);
select public.expire_lapsed_appointment_requests(clock_timestamp());
select pg_temp.flush();
select pg_temp.assert_true(
    pg_temp.lifecycle(15) = 'EXPIRED'
    and (pg_temp.proposal(pg_temp.id('lapsed15'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('lapsed15'))).void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED',
    'Expiry makes the pending alternative VOID APPOINTMENT_LIFECYCLE_CHANGED'
);

-- Proposer authority lost: non-actionable at once, made VOID lazily.
set local role authenticated;
select pg_temp.keep('p16', pg_temp.alt_propose(13, 16, '2035-03-08', '16:00', 3600, 1));
reset role;
set local session_replication_role = replica;
update public.organization_responsibility_grants
set effective_end = clock_timestamp(), ended_by_user_id = pg_temp.domain_user(4)
where id = 'a1700000-0000-4000-8000-000000000613';
set local session_replication_role = origin;
select pg_temp.assert_true(
    (select pending_id is null from pg_temp.guardian_row(16))
    and not pg_temp.eligible(pg_temp.alternative_communication(pg_temp.id('p16'), 1))
    and (pg_temp.proposal(pg_temp.id('p16'))).state = 'PENDING',
    'Authority loss: non-actionable, not shown, not delivered, still PENDING'
);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('p16')),
    '42501', 'proposing authority was lost');
select pg_temp.keep('p16b', pg_temp.alt_propose(7, 16, '2035-03-08', '17:00', 3600, 1));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p16'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p16'))).void_reason = 'PROPOSING_AUTHORITY_LOST'
    and (pg_temp.proposal(pg_temp.id('p16b'))).state = 'PENDING',
    'A new proposal makes the authority-lost one VOID PROPOSING_AUTHORITY_LOST'
);

-- ===========================================================================
-- 10. Withdrawal (SPEC-APT-016 generalized) and Communication delivery.
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p17', pg_temp.alt_propose(8, 17, '2035-03-09', '12:00', 3600, 1));
reset role;

-- PUSH fixtures (SPEC-COM-003): one live Push Registration, on a live Auth
-- session, for G1, G2 and the former Guardian G3 (sessions …f0N,
-- Registrations …f1N). They exist before the one-time fan-out below.
insert into auth.sessions (id, user_id, created_at, updated_at)
select ('a1700000-0000-4000-8000-000000000f0' || n)::uuid,
       ('a1700000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       clock_timestamp(), clock_timestamp()
from unnest(array[1, 2, 3]) as n;
insert into public.push_registrations (
    id, user_id, auth_session_id, device_installation_id, provider_token, platform, application_id
)
select ('a1700000-0000-4000-8000-000000000f1' || n)::uuid, pg_temp.domain_user(n),
       ('a1700000-0000-4000-8000-000000000f0' || n)::uuid,
       ('a1700000-0000-4000-8000-000000000f2' || n)::uuid,
       'ExponentPushToken[alt-guardian-' || n || ']', 'ANDROID', 'com.petcare.mobile.alt'
from unnest(array[1, 2, 3]) as n;

create function pg_temp.registration(p_user integer) returns uuid language sql immutable as $$
    select ('a1700000-0000-4000-8000-000000000f1' || p_user)::uuid
$$;
create function pg_temp.push_snapshot(p_user integer) returns text language sql as $$
    select 'sha256:' || encode(provider_token_digest, 'hex')
    from public.push_registrations where id = pg_temp.registration(p_user)
$$;
create function pg_temp.push_eligible(p_communication_id uuid, p_user integer) returns boolean language sql as $$
    select public.communication_delivery_is_currently_eligible(
        p_communication_id, 'PUSH', pg_temp.registration(p_user), pg_temp.push_snapshot(p_user))
$$;
create function pg_temp.push_job(p_communication_id uuid, p_user integer) returns uuid language sql as $$
    select id from public.communication_delivery_jobs
    where communication_id = p_communication_id and channel = 'PUSH'
      and push_registration_id = pg_temp.registration(p_user)
$$;

-- Delivery context of a live alternative, then suppression after withdrawal.
select public.materialize_communication_delivery_jobs();
do $$
declare
    job_id uuid;
    lease uuid := 'a1700000-0000-4000-8000-0000000000e1';
    context jsonb;
begin
    select job.id into job_id
    from public.communication_delivery_jobs as job
    where job.communication_id = pg_temp.alternative_communication(pg_temp.id('p10'), 1)
      and job.channel = 'EMAIL';
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = lease, lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = job_id;
    context := public.get_communication_delivery_context(job_id, lease);
    perform pg_temp.assert_true(
        context ->> 'communication_type' = 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
        and context ->> 'appointment_state' = 'REQUESTED'
        and (context ->> 'scheduled_start_at')::timestamptz = '2035-03-07T10:00Z'
        and (context ->> 'scheduled_end_at')::timestamptz = '2035-03-07T10:30Z'
        and context ->> 'timezone_name' = 'Europe/Madrid'
        and context ->> 'pet_name' = 'Luna'
        and context ->> 'pet_id' = pg_temp.luna()::text
        and context ->> 'reschedule_proposal_id' = pg_temp.id('p10')::text,
        format('Delivery context carries the proposed interval of the alternative: %s', context)
    );
end;
$$;
-- PUSH: a live alternative fans out to each current Guardian's Registration
-- (never the former Guardian's), is eligible, and its PUSH context names the
-- type, the Guardian's own device, the REQUESTED Appointment, and the
-- proposed interval (not the current request).
do $$
declare
    job_id uuid;
    lease uuid := 'a1700000-0000-4000-8000-0000000000e3';
    context jsonb;
begin
    perform pg_temp.assert_true(
        pg_temp.communications_of(pg_temp.id('p10'), 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED')
            = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
        and pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id('p10'), 1), 1) is not null
        and pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id('p10'), 2), 2) is not null
        and pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id('p10'), 1), 2) is null
        and pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id('p10'), 2), 1) is null
        and not exists (
            select 1 from public.communication_delivery_jobs
            where push_registration_id = pg_temp.registration(3)
              and communication_id in (
                  select id from public.transactional_communications
                  where communication_type = 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'))
        and pg_temp.push_eligible(pg_temp.alternative_communication(pg_temp.id('p10'), 1), 1)
        and pg_temp.push_eligible(pg_temp.alternative_communication(pg_temp.id('p10'), 2), 2)
        and not pg_temp.push_eligible(pg_temp.alternative_communication(pg_temp.id('p10'), 1), 2),
        'PUSH: a live alternative has one eligible PUSH job per current Guardian Registration; none for another User or the former Guardian'
    );

    job_id := pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id('p10'), 1), 1);
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = lease, lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = job_id;
    context := public.get_communication_delivery_context(job_id, lease);
    perform pg_temp.assert_true(
        context ->> 'channel' = 'PUSH'
        and context ->> 'communication_type' = 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
        and context ->> 'recipient' = 'ExponentPushToken[alt-guardian-1]'
        and context ->> 'appointment_id' = pg_temp.appt(10)::text
        and context ->> 'appointment_state' = 'REQUESTED'
        and (context ->> 'scheduled_start_at')::timestamptz = '2035-03-07T10:00Z'
        and (context ->> 'scheduled_end_at')::timestamptz = '2035-03-07T10:30Z'
        and (context ->> 'scheduled_start_at')::timestamptz
            is distinct from (pg_temp.latest_revision(10)).scheduled_start_at
        and context ->> 'timezone_name' = 'Europe/Madrid'
        and context ->> 'pet_id' = pg_temp.luna()::text
        and context ->> 'pet_name' = 'Luna'
        and context ->> 'reschedule_proposal_id' = pg_temp.id('p10')::text,
        format('PUSH delivery context carries the alternative for the REQUESTED Appointment: %s', context)
    );
end;
$$;
-- PUSH: accepted, superseded (Guardian reschedule, confirmation), cancelled,
-- and authority-lost alternatives are never eligible and were never fanned
-- out to PUSH. (The lapsed fixture 'lapsed15' is inserted directly and has no
-- Communication.)
select pg_temp.assert_true(
    pg_temp.alternative_communication(pg_temp.id(name), 1) is not null
    and not pg_temp.push_eligible(pg_temp.alternative_communication(pg_temp.id(name), 1), 1)
    and pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id(name), 1), 1) is null,
    format('PUSH: non-actionable alternative %s is suppressed', name)
)
from unnest(array['p2', 'p11', 'p12', 'p13', 'p14', 'p16']) as name;
do $$
declare
    job_id uuid;
    lease uuid := 'a1700000-0000-4000-8000-0000000000e2';
    context jsonb;
    push_job_id uuid;
    push_lease uuid := 'a1700000-0000-4000-8000-0000000000e4';
    push_context jsonb;
begin
    select job.id into job_id
    from public.communication_delivery_jobs as job
    where job.communication_id = pg_temp.alternative_communication(pg_temp.id('p17'), 1)
      and job.channel = 'EMAIL';
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = lease, lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = job_id;
    push_job_id := pg_temp.push_job(pg_temp.alternative_communication(pg_temp.id('p17'), 1), 1);
    perform pg_temp.assert_true(
        push_job_id is not null
        and pg_temp.push_eligible(pg_temp.alternative_communication(pg_temp.id('p17'), 1), 1),
        'PUSH: the live alternative about to be withdrawn has an eligible PUSH job'
    );
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = push_lease, lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = push_job_id;
    perform pg_temp.remember(17);
    set local role authenticated;
    -- Not withdrawable by another Clinic's actor or a Guardian.
    perform pg_temp.assert_error(format('select pg_temp.withdraw(%s, %L)', actor, pg_temp.id('p17')),
        '42501', null)
    from unnest(array[1, 9]) as actor;
    perform pg_temp.withdraw(7, pg_temp.id('p17'));   -- any authorized Clinic actor
    reset role;
    context := public.get_communication_delivery_context(job_id, lease);
    perform pg_temp.assert_true(
        context is null
        and (select state = 'SUPPRESSED' from public.communication_delivery_jobs where id = job_id),
        format('A withdrawn alternative is never delivered: context %s, job %s, state %s',
               context, job_id, (select state from public.communication_delivery_jobs where id = job_id))
    );
    push_context := public.get_communication_delivery_context(push_job_id, push_lease);
    perform pg_temp.assert_true(
        push_context is null
        and (select state = 'SUPPRESSED' from public.communication_delivery_jobs where id = push_job_id)
        and not pg_temp.push_eligible(pg_temp.alternative_communication(pg_temp.id('p17'), 1), 1),
        format('PUSH: a withdrawn alternative is never pushed: context %s, state %s',
               push_context, (select state from public.communication_delivery_jobs where id = push_job_id))
    );
end;
$$;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p17'))).state = 'WITHDRAWN'
    and (pg_temp.proposal(pg_temp.id('p17'))).withdrawn_by_user_id = pg_temp.domain_user(7)
    and pg_temp.lifecycle(17) = 'REQUESTED'
    and (pg_temp.latest_revision(17)).revision_sequence = 1
    and pg_temp.communication_count(17) = 2,
    'Withdrawal: WITHDRAWN by the withdrawing actor; the request is unchanged; no new Communication'
);
set local role authenticated;
select pg_temp.keep('p17b', pg_temp.alt_propose(8, 17, '2035-03-09', '13:00', 3600, 1));
select pg_temp.withdraw(16, pg_temp.id('pastdue24'));   -- no Entitlement gate
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p17b'))).state = 'PENDING'
    and (pg_temp.proposal(pg_temp.id('pastdue24'))).state = 'WITHDRAWN',
    'Withdrawal frees the slot at once and needs no Entitlement'
);

-- ===========================================================================
-- 11. The workflows do not cross; CONFIRMED behaviour unchanged
--     (SPEC-APT-005 §5, SPEC-APT-006 BR-35, SPEC-APT-019 BR-12).
-- ===========================================================================

set local role authenticated;
select pg_temp.act(8);
select pg_temp.assert_error(format('select public.propose_confirmed_appointment_reschedule(%L, ''CLINIC'', ''2035-03-10'', ''12:00'', 3600, ''Busy'', 1)', pg_temp.appt(22)),
    '23514', 'Only a CONFIRMED Appointment may receive a reschedule Proposal');
select pg_temp.assert_error('select pg_temp.alt_propose(8, 23, ''2035-03-10'', ''12:00'', 3600, 2)',
    '23514', 'Only a REQUESTED Appointment may receive an alternative time proposal');
select pg_temp.keep('c23', public.propose_confirmed_appointment_reschedule(
    pg_temp.appt(23), 'CLINIC', '2035-03-10', '12:00', 3600, 'Busy', 2));
select pg_temp.flush();
select pg_temp.assert_error(format('select pg_temp.alt_accept(1, %L)', pg_temp.id('c23')),
    '23514', 'Only a Clinic alternative time for a requested Appointment can be accepted through this operation');
select pg_temp.act(1);
select pg_temp.assert_error(format('select public.accept_appointment_reschedule_proposal(%L, ''GUARDIAN'')', pg_temp.id('p10')),
    '23514', 'Appointment must remain CONFIRMED to accept a reschedule Proposal');
reset role;
select pg_temp.assert_true(
    pg_temp.communications_of(pg_temp.id('c23'), 'APPOINTMENT_RESCHEDULE_PROPOSED')
        = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
    and pg_temp.communications_of(pg_temp.id('c23'), 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED') = '{}'
    and (select pending_id = pg_temp.id('c23') and lifecycle_state = 'CONFIRMED' and source_id is null
         from pg_temp.guardian_row(23)),
    'A CONFIRMED-base Clinic proposal keeps APPOINTMENT_RESCHEDULE_PROPOSED and its projection'
);
-- PUSH for a CONFIRMED-base proposal is unchanged: APPOINTMENT_RESCHEDULE_PROPOSED,
-- eligible while actionable, the CONFIRMED Appointment and the proposed interval.
select public.materialize_communication_delivery_jobs();
do $$
declare
    proposed_communication uuid;
    job_id uuid;
    lease uuid := 'a1700000-0000-4000-8000-0000000000e5';
    context jsonb;
begin
    select id into proposed_communication
    from public.transactional_communications
    where appointment_reschedule_proposal_id = pg_temp.id('c23')
      and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
      and recipient_user_id = pg_temp.domain_user(1);
    job_id := pg_temp.push_job(proposed_communication, 1);
    perform pg_temp.assert_true(
        job_id is not null and pg_temp.push_eligible(proposed_communication, 1),
        'PUSH: a CONFIRMED-base Clinic proposal still has an eligible PUSH job'
    );
    update public.communication_delivery_jobs
    set state = 'CLAIMED', lease_token = lease, lease_expires_at = clock_timestamp() + interval '2 minutes'
    where id = job_id;
    context := public.get_communication_delivery_context(job_id, lease);
    perform pg_temp.assert_true(
        context ->> 'channel' = 'PUSH'
        and context ->> 'communication_type' = 'APPOINTMENT_RESCHEDULE_PROPOSED'
        and context ->> 'appointment_state' = 'CONFIRMED'
        and (context ->> 'scheduled_start_at')::timestamptz = '2035-03-10T11:00Z'
        and context ->> 'reschedule_proposal_id' = pg_temp.id('c23')::text,
        format('PUSH: the CONFIRMED reschedule proposal context is unchanged: %s', context)
    );
end;
$$;
set local role authenticated;
select pg_temp.act(1);
select public.accept_appointment_reschedule_proposal(pg_temp.id('c23'), 'GUARDIAN');
select pg_temp.flush();
reset role;
select pg_temp.assert_true(
    not pg_temp.push_eligible(
        (select id from public.transactional_communications
         where appointment_reschedule_proposal_id = pg_temp.id('c23')
           and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
           and recipient_user_id = pg_temp.domain_user(2)), 2)
    and pg_temp.push_eligible(
        (select id from public.transactional_communications
         where appointment_reschedule_proposal_id = pg_temp.id('c23')
           and communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED'
           and recipient_user_id = pg_temp.domain_user(2)), 2),
    'PUSH: once accepted, the CONFIRMED proposal is no longer pushed and APPOINTMENT_RESCHEDULE_ACCEPTED is eligible'
);
select pg_temp.assert_true(
    pg_temp.communications_of(pg_temp.id('c23'), 'APPOINTMENT_RESCHEDULE_ACCEPTED')
        = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
    and (select lifecycle_state = 'CONFIRMED' and source_id = pg_temp.id('c23') and source_context = 'CLINIC'
         from pg_temp.guardian_row(23)),
    'Accepting a confirmed reschedule keeps APPOINTMENT_RESCHEDULE_ACCEPTED; its provenance is visible but the Appointment is CONFIRMED, never awaiting'
);

-- Communication origins must match the Proposal base context.
select pg_temp.assert_error(format(
    'insert into public.transactional_communications (communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id, locale) values (''APPOINTMENT_RESCHEDULE_PROPOSED'', %L, %L, %L, ''es-ES'')',
    pg_temp.domain_user(1), pg_temp.appt(10), pg_temp.id('p10')),
    '23514', 'Communication Proposal origin does not match');
select pg_temp.assert_error(format(
    'insert into public.transactional_communications (communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id, locale) values (''APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'', %L, %L, %L, ''es-ES'')',
    pg_temp.domain_user(1), pg_temp.appt(23), pg_temp.id('c23')),
    '23514', 'Communication Proposal origin does not match');
select pg_temp.assert_error(format(
    'insert into public.transactional_communications (communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id, appointment_schedule_revision_id, locale) values (''APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'', %L, %L, %L, %L, ''es-ES'')',
    pg_temp.domain_user(1), pg_temp.appt(10), pg_temp.id('p10'), (pg_temp.latest_revision(10)).id),
    '23514', null);
select pg_temp.assert_error(format(
    'insert into public.transactional_communications (communication_type, recipient_user_id, appointment_id, appointment_reschedule_proposal_id, locale) values (''APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'', %L, %L, %L, ''es-ES'')',
    pg_temp.domain_user(1), pg_temp.appt(10), pg_temp.id('p10')),
    '23505', 'transactional_communications_alternative_time_proposed_key');

-- ===========================================================================
-- 12. Candidate read (SPEC-APT-020).
-- ===========================================================================

set local role authenticated;
select pg_temp.assert_true(
    pg_temp.candidates(8, 20, '2035-03-07', '2035-03-07')
        = (select array_agg('2035-03-07 ' || to_char(slot, 'HH24:MI:SS') order by slot)
           from generate_series(timestamp '2035-03-07 08:00', timestamp '2035-03-07 19:30', interval '30 minutes') as slot),
    'Standard duration as length and cadence across Clinic Availability (24 slots)'
);
select pg_temp.assert_true(
    not ('2035-03-06 10:00:00' = any (pg_temp.candidates(8, 20, '2035-03-06', '2035-03-06')))
    and cardinality(pg_temp.candidates(8, 20, '2035-03-06', '2035-03-06')) = 23,
    'The current requested start is excluded'
);
select pg_temp.assert_true(
    (select bool_and(candidate.candidate_end_at
                     = (candidate.candidate_local_date + candidate.candidate_local_time) at time zone 'Europe/Madrid'
                       + interval '30 minutes'
                     and candidate.utc_offset_seconds = 3600)
     from public.get_requested_appointment_alternative_candidate_start_times(pg_temp.appt(20), '2035-03-07', '2035-03-07') as candidate),
    'Each candidate carries its offset and the server-authored end'
);
select pg_temp.assert_true(
    cardinality(pg_temp.candidates(4, 3, '2035-03-07', '2035-03-07')) = 24,
    'An unpublished Clinic still returns candidates'
);
select pg_temp.assert_true(
    cardinality(pg_temp.candidates(8, 20, '2040-01-01', '2040-03-01')) > 0,
    'No business horizon: a 60-day window years ahead is accepted'
);
select pg_temp.assert_error('select pg_temp.candidates(8, 20, ''2035-03-01'', ''2035-05-01'')',
    '22023', 'Requested range must not span more than 60 days');
select pg_temp.assert_error('select pg_temp.candidates(8, 20, ''2035-03-07'', ''2035-03-06'')',
    '22023', 'End date must not precede start date');
select pg_temp.assert_true(
    cardinality(pg_temp.candidates(8, 20, '2026-01-01', '2026-01-31')) = 0,
    'A past range yields nothing'
);
select pg_temp.assert_error(format('select pg_temp.candidates(%s, 20, ''2035-03-07'', ''2035-03-07'')', actor),
    '42501', 'Applicable Appointment-management capability is required')
from unnest(array[1, 9, 10]) as actor;
select pg_temp.assert_error('select pg_temp.candidates(16, 24, ''2035-03-09'', ''2035-03-09'')',
    '42501', 'Applicable professional Entitlement is required');
select pg_temp.assert_error('select pg_temp.candidates(8, 9, ''2035-04-02'', ''2035-04-02'')',
    '23514', 'Only a REQUESTED Appointment may receive an alternative time proposal');
-- 2035-04-02 for Appointment 7 (Veterinarian 10, available 08:00–18:00, busy
-- 12:00–13:00 elsewhere in the schedule; current start 10:00): 20 − 3 = 17.
select pg_temp.assert_true(
    pg_temp.candidates(8, 7, '2035-04-02', '2035-04-02')
        = (select array_agg('2035-04-02 ' || to_char(slot, 'HH24:MI:SS') order by slot)
           from generate_series(timestamp '2035-04-02 08:00', timestamp '2035-04-02 17:30', interval '30 minutes') as slot
           where slot::time not in ('10:00', '12:00', '12:30')),
    'Veterinarian Availability and a known conflict exclude positions without disclosure'
);
select pg_temp.assert_true(
    cardinality(pg_temp.candidates(8, 8, '2035-04-03', '2035-04-05')) = 0,
    'An ended Veterinarian Clinic Assignment yields no candidates'
);
reset role;
update public.clinics set standard_appointment_duration_minutes = 45 where id = pg_temp.clinic(7);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.candidates(4, 21, '2035-03-07', '2035-03-07')
        = (select array_agg('2035-03-07 ' || to_char(slot, 'HH24:MI:SS') order by slot)
           from generate_series(timestamp '2035-03-07 08:00', timestamp '2035-03-07 19:15', interval '45 minutes') as slot),
    'The current standard duration (now 45) drives length and cadence'
);
reset role;
update public.clinics set standard_appointment_duration_minutes = 30 where id = pg_temp.clinic(7);

-- Read/write parity: every candidate of a day round-trips through propose with
-- the identical start and end (withdrawing in between frees the slot).
do $$
declare
    candidate record;
    created uuid;
    tested integer := 0;
begin
    for candidate in
        select * from public.get_requested_appointment_alternative_candidate_start_times(
            pg_temp.appt(20), '2035-03-07', '2035-03-07')
    loop
        set local role authenticated;
        created := pg_temp.alt_propose(8, 20, candidate.candidate_local_date, candidate.candidate_local_time,
                                       candidate.utc_offset_seconds, 1);
        reset role;
        perform pg_temp.assert_true(
            (pg_temp.proposal(created)).proposed_end_at = candidate.candidate_end_at
            and (pg_temp.proposal(created)).proposed_start_at
                = (candidate.candidate_local_date + candidate.candidate_local_time) at time zone 'Europe/Madrid',
            format('Candidate %s %s round-trips', candidate.candidate_local_date, candidate.candidate_local_time)
        );
        set local role authenticated;
        perform pg_temp.withdraw(8, created);
        reset role;
        tested := tested + 1;
    end loop;
    perform pg_temp.assert_true(tested = 24, 'Every candidate of the day was round-tripped');
end;
$$;

-- A 60-day read stays fast.
do $$
declare
    started timestamptz := clock_timestamp();
begin
    set local role authenticated;
    perform pg_temp.candidates(8, 7, '2035-04-01', '2035-05-31');
    reset role;
    perform pg_temp.assert_true(clock_timestamp() - started < interval '5 seconds',
        format('A 60-day Veterinarian-constrained read took %s', clock_timestamp() - started));
end;
$$;

-- ===========================================================================
-- 12b. Daylight saving (SPEC-APT-018 VN 9, SPEC-APT-020 BR-5, SPEC-APT-013
--      BR-58): the standard duration is elapsed time in the proposal, the
--      candidate read, and the accepted revision.
--
-- The dates are never hard-coded: they are the next real Europe/Madrid
-- spring-forward and fall-back dates strictly after the Clinic-local today,
-- found from the time-zone database (the first date whose noon UTC offset is
-- higher, respectively lower, than the previous date's). The Alternative Time
-- path has no business horizon, so this never needs to be skipped. A8 is a
-- dedicated, unpublished OrgA Clinic available 00:00–24:00 every day, so the transition
-- hour is covered; its standard duration is changed per case. 25 and 26 are
-- requests far in the future (2035), so both transition days are valid,
-- different alternative starts.
-- ===========================================================================

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

set local session_replication_role = replica;
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.clinic(8), 'a1700000-0000-4000-8000-000000000301', false, 'Europe/Madrid', 60);
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(8), weekday, '00:00', '24:00' from generate_series(1, 7) as weekday;
select pg_temp.seed(25, 8, '2035-03-06T09:00Z', 'REQUESTED');
select pg_temp.seed(26, 8, '2035-03-06T10:00Z', 'REQUESTED');
set local session_replication_role = origin;
-- Run the trusted operations in the Clinic's own timezone: calendar or
-- wall-clock arithmetic would then visibly differ from elapsed time.
set local timezone = 'Europe/Madrid';

-- Spring-forward (02:00 -> 03:00 local), 60 minutes: the 02:00 position does
-- not exist, and 01:30 CET + 60 minutes ends at 03:30 CEST.
set local role authenticated;
select pg_temp.assert_true(
    (select not ((spring_forward || ' 02:00:00') = any (pg_temp.candidates(4, 25, spring_forward, spring_forward)))
            and cardinality(pg_temp.candidates(4, 25, spring_forward, spring_forward)) = 23
     from pg_temp.dst_dates),
    'Spring-forward: the nonexistent 02:00 position is omitted, 23 hourly candidates remain'
);
select pg_temp.assert_true(
    (select bool_and(extract(epoch from candidate.candidate_end_at)
                     - extract(epoch from ((candidate.candidate_local_date + candidate.candidate_local_time)
                                           - make_interval(secs => candidate.utc_offset_seconds)) at time zone 'UTC') = 3600)
     from pg_temp.dst_dates,
          public.get_requested_appointment_alternative_candidate_start_times(pg_temp.appt(25), spring_forward, spring_forward) as candidate),
    'Spring-forward: every candidate lasts exactly 60 elapsed minutes'
);
select pg_temp.keep('dst_spring', pg_temp.alt_propose(4, 25, (select spring_forward from pg_temp.dst_dates), '01:30', 3600, 1));
reset role;
select pg_temp.assert_true(
    (select (pg_temp.proposal(pg_temp.id('dst_spring'))).proposed_start_at
                = (spring_forward + time '01:30') at time zone 'Europe/Madrid'
            and (pg_temp.proposal(pg_temp.id('dst_spring'))).proposed_end_at
                - (pg_temp.proposal(pg_temp.id('dst_spring'))).proposed_start_at = interval '1 hour'
            and ((pg_temp.proposal(pg_temp.id('dst_spring'))).proposed_end_at at time zone 'Europe/Madrid')
                = spring_forward + time '03:30'
     from pg_temp.dst_dates),
    'Spring-forward: 01:30 + 60 elapsed minutes ends at 03:30 local'
);

-- Fall-back (03:00 -> 02:00 local), 120 minutes: the repeated 02:00 position is
-- ambiguous and omitted, and 01:30 CEST + 120 minutes ends at 02:30 CET.
update public.clinics set standard_appointment_duration_minutes = 120 where id = pg_temp.clinic(8);
set local role authenticated;
select pg_temp.assert_true(
    (select not ((fall_back || ' 02:00:00') = any (pg_temp.candidates(4, 26, fall_back, fall_back)))
            and pg_temp.candidates(4, 26, fall_back, fall_back)
                = array[fall_back || ' 00:00:00', fall_back || ' 04:00:00', fall_back || ' 06:00:00',
                        fall_back || ' 08:00:00', fall_back || ' 10:00:00', fall_back || ' 12:00:00',
                        fall_back || ' 14:00:00', fall_back || ' 16:00:00', fall_back || ' 18:00:00',
                        fall_back || ' 20:00:00', fall_back || ' 22:00:00']
     from pg_temp.dst_dates),
    'Fall-back: the ambiguous 02:00 position is omitted without shifting the 120-minute grid'
);
select pg_temp.keep('dst_fall', pg_temp.alt_propose(4, 26, (select fall_back from pg_temp.dst_dates), '01:30', 7200, 1));
reset role;
select pg_temp.assert_true(
    (select (pg_temp.proposal(pg_temp.id('dst_fall'))).proposed_end_at
                - (pg_temp.proposal(pg_temp.id('dst_fall'))).proposed_start_at = interval '2 hours'
            and ((pg_temp.proposal(pg_temp.id('dst_fall'))).proposed_end_at at time zone 'Europe/Madrid')
                = fall_back + time '02:30'
     from pg_temp.dst_dates),
    'Fall-back: 01:30 CEST + 120 elapsed minutes ends at 02:30 CET'
);

-- Acceptance adopts the elapsed interval exactly, under another duration.
update public.clinics set standard_appointment_duration_minutes = 30 where id = pg_temp.clinic(8);
set local role authenticated;
select pg_temp.alt_accept(1, pg_temp.id('dst_fall'));
reset role;
select pg_temp.assert_true(
    (pg_temp.latest_revision(26)).scheduled_start_at = (pg_temp.proposal(pg_temp.id('dst_fall'))).proposed_start_at
    and (pg_temp.latest_revision(26)).scheduled_end_at = (pg_temp.proposal(pg_temp.id('dst_fall'))).proposed_end_at
    and (pg_temp.latest_revision(26)).scheduled_end_at - (pg_temp.latest_revision(26)).scheduled_start_at = interval '2 hours',
    'Acceptance across fall-back establishes the frozen 120 elapsed minutes'
);

-- The 30-minute grid on both transition days (the grid 12c reads for a
-- regular day). Spring-forward: 02:00 and 02:30 do not exist. Fall-back: 02:00
-- and 02:30 occur twice and are omitted fail-closed in Phase 1 (SPEC-APT-013
-- BR-52, BR-58), without shifting the grid; the repeated elapsed hour is still
-- covered by intervals that span it. 32 is requested far away (2035); 33 is
-- requested at 10:00 on the fall-back day itself.
set local session_replication_role = replica;
select pg_temp.seed(32, 8, '2035-03-07T09:00Z', 'REQUESTED');
select pg_temp.seed(33, 8, (select (fall_back + time '10:00') at time zone 'Europe/Madrid' from pg_temp.dst_dates),
                    'REQUESTED');
set local session_replication_role = origin;

-- Every 30-minute Clinic-local position of a date, except the given times.
create function pg_temp.half_hour_positions(p_date date, p_omitted time[]) returns text[] language sql immutable as $$
    select array_agg(p_date || ' ' || to_char(time '00:00' + make_interval(mins => 30 * n), 'HH24:MI:SS') order by n)
    from generate_series(0, 47) as n
    where not (time '00:00' + make_interval(mins => 30 * n)) = any (p_omitted)
$$;

set local role authenticated;
select pg_temp.assert_true(
    (select pg_temp.candidates(4, 32, spring_forward, spring_forward)
                = pg_temp.half_hour_positions(spring_forward, array[time '02:00', time '02:30'])
     from pg_temp.dst_dates),
    'Spring-forward, 30 minutes: exactly the 46 existing positions; 02:00 and 02:30 do not exist'
);
select pg_temp.assert_true(
    (select candidate.candidate_end_at at time zone 'Europe/Madrid' = spring_forward + time '03:00'
            and candidate.candidate_end_at - ((spring_forward + time '01:30') at time zone 'Europe/Madrid')
                = interval '30 minutes'
     from pg_temp.dst_dates,
          public.get_requested_appointment_alternative_candidate_start_times(pg_temp.appt(32), spring_forward, spring_forward)
              as candidate
     where candidate.candidate_local_time = time '01:30'),
    'Spring-forward, 30 minutes: 01:30 + 30 elapsed minutes ends at 03:00 local'
);
select pg_temp.assert_true(
    (select pg_temp.candidates(4, 32, fall_back, fall_back)
                = pg_temp.half_hour_positions(fall_back, array[time '02:00', time '02:30'])
     from pg_temp.dst_dates),
    'Fall-back, 30 minutes: the repeated 02:00 and 02:30 positions are omitted; the other 46 remain'
);
select pg_temp.assert_true(
    (select bool_and(case
                when candidate.candidate_local_time < time '02:00'
                    then candidate.utc_offset_seconds = 7200
                else candidate.utc_offset_seconds = 3600
            end)
            and bool_and(candidate.candidate_end_at
                         - ((candidate.candidate_local_date + candidate.candidate_local_time)
                            - make_interval(secs => candidate.utc_offset_seconds)) at time zone 'UTC'
                         = interval '30 minutes')
            and count(*) filter (where candidate.candidate_local_time = time '01:30'
                                   and candidate.candidate_end_at
                                       = (fall_back + time '02:00') at time zone 'UTC' - interval '2 hours') = 1
     from pg_temp.dst_dates,
          public.get_requested_appointment_alternative_candidate_start_times(pg_temp.appt(32), fall_back, fall_back)
              as candidate),
    'Fall-back, 30 minutes: offsets are summer time before the repeated hour and winter time after it, every '
    || 'candidate lasts 30 elapsed minutes, and 01:30 ends at the first 02:00'
);
select pg_temp.assert_true(
    (select pg_temp.candidates(4, 33, fall_back, fall_back)
                = pg_temp.half_hour_positions(fall_back, array[time '02:00', time '02:30', time '10:00'])
     from pg_temp.dst_dates),
    'A request on the fall-back day: its own start is excluded and the other 45 positions remain'
);
reset role;
set local timezone = 'UTC';

-- ===========================================================================
-- 12c. Earlier than the request, today (SPEC-APT-018 BR-14, SPEC-APT-020
--      BR-4/BR-6): a request for Clinic-local tomorrow may receive an
--      alternative later today. No rule requires the proposed date to be on
--      or after the requested date; the only temporal floor is "after now".
--
-- Real clock, never hard-coded: the Clinic timezone is the first of three
-- zones far apart whose local time is before 21:00, so at least three hours of
-- 30-minute positions remain today, and whose today and tomorrow are regular
-- 24-hour days, so each has exactly 48 half-hour positions. A clock-transition
-- day is covered deterministically by 12b instead. Madrid and New York never
-- change their clocks on the same days and Tokyo never does, so such a zone
-- always exists. A9: Appointment Availability 00:00–24:00
-- every day, Veterinarian 10 assigned (vca 13, available 00:00–24:00) and busy
-- with a CONFIRMED Appointment at `conflict_time` today. A10: public Opening
-- Hours only, no Appointment Availability. A11: Appointment Availability with a
-- CLOSED exception today. Each request is for tomorrow (D+1).
-- ===========================================================================

create table pg_temp.today_ctx (zone text not null, d date not null, conflict_time time not null);
grant select on pg_temp.today_ctx to authenticated;

do $$
declare
    chosen text;
    local_now timestamp;
begin
    select zone into chosen
    from unnest(array['Europe/Madrid', 'America/New_York', 'Asia/Tokyo']) with ordinality as z(zone, ord)
    where (clock_timestamp() at time zone zone)::time < time '21:00'
      -- Local midnight today to local midnight the day after tomorrow is
      -- exactly 48 elapsed hours only without a clock transition in between.
      and (((clock_timestamp() at time zone zone)::date + 2)::timestamp at time zone zone)
          - (((clock_timestamp() at time zone zone)::date)::timestamp at time zone zone) = interval '48 hours'
    order by ord
    limit 1;
    perform pg_temp.assert_true(chosen is not null,
        'A zone with at least three hours left today and two regular days exists');
    local_now := clock_timestamp() at time zone chosen;
    -- The next half-hour position strictly after now, plus one hour.
    insert into pg_temp.today_ctx values (
        chosen, local_now::date,
        (date_trunc('hour', local_now)
         + case when extract(minute from local_now) < 30 then interval '30 minutes' else interval '60 minutes' end
         + interval '60 minutes')::time
    );
end;
$$;

create function pg_temp.seed_in_zone(p_n integer, p_clinic integer, p_start timestamptz, p_state text, p_zone text)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), pg_temp.clinic(p_clinic), pg_temp.domain_user(1), 'Visit ' || p_n,
            p_state, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + interval '30 minutes', p_zone,
              pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) select pg_temp.ca(p_n), pg_temp.luna(), clinic.id, clinic.organization_id, 'a1700000-0000-4000-8000-000000000a11',
             '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n), 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE'
      from public.clinics as clinic where clinic.id = pg_temp.clinic(p_clinic);
    if p_state = 'CONFIRMED' then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
        ) values (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_start + interval '30 minutes', p_zone,
                  pg_temp.domain_user(4), null, '2026-02-01T00:00:00Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(4), 'CLINIC', null,
                  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
    end if;
end;
$$;

-- Clinic-local "D H:MM" as the real instant.
create function pg_temp.at_local(p_date date, p_time time) returns timestamptz language sql stable as $$
    select (p_date + p_time) at time zone (select zone from pg_temp.today_ctx)
$$;

set local session_replication_role = replica;
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
select pg_temp.clinic(n), 'a1700000-0000-4000-8000-000000000301', true, ctx.zone, 30
from pg_temp.today_ctx as ctx, unnest(array[9, 10, 11]) as n;
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(n), weekday, '00:00', '24:00'
from unnest(array[9, 11]) as n, generate_series(1, 7) as weekday;
insert into public.clinic_opening_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(10), weekday, '00:00', '23:00' from generate_series(1, 7) as weekday;
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
select pg_temp.clinic(11), d, 'CLOSED' from pg_temp.today_ctx;
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values (pg_temp.vca(13), 'a1700000-0000-4000-8000-000000000710', 'a1700000-0000-4000-8000-000000000510',
          pg_temp.clinic(9), '2020-01-01Z', null);
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time)
select pg_temp.vca(13), weekday, '00:00', '24:00' from generate_series(1, 7) as weekday;
select pg_temp.seed_in_zone(27, 9, pg_temp.at_local(d + 1, '10:00'), 'REQUESTED', zone) from pg_temp.today_ctx;  -- no Veterinarian
select pg_temp.seed_in_zone(28, 9, pg_temp.at_local(d + 1, '11:00'), 'REQUESTED', zone) from pg_temp.today_ctx;  -- Veterinarian 10
select pg_temp.seed_in_zone(29, 9, pg_temp.at_local(d, conflict_time), 'CONFIRMED', zone) from pg_temp.today_ctx; -- Veterinarian 10 busy
select pg_temp.seed_in_zone(30, 10, pg_temp.at_local(d + 1, '10:00'), 'REQUESTED', zone) from pg_temp.today_ctx; -- Opening Hours only
select pg_temp.seed_in_zone(31, 11, pg_temp.at_local(d + 1, '10:00'), 'REQUESTED', zone) from pg_temp.today_ctx; -- CLOSED today
select pg_temp.assign_vet(n, 13) from unnest(array[28, 29]) as n;
set local session_replication_role = origin;
select pg_temp.flush();

create function pg_temp.slot(p_date date, p_time time) returns text language sql stable as $$
    select p_date || ' ' || to_char(p_time, 'HH24:MI:SS')
$$;

-- Today's candidates for a request made for tomorrow; past positions omitted.
do $$
declare
    ctx record;
    before_read timestamptz;
    today_candidates text[];
begin
    select * into ctx from pg_temp.today_ctx;
    before_read := clock_timestamp();
    set local role authenticated;
    today_candidates := pg_temp.candidates(4, 27, ctx.d, ctx.d);
    reset role;
    perform pg_temp.assert_true(
        cardinality(today_candidates) >= 2
        and pg_temp.slot(ctx.d, ctx.conflict_time - interval '30 minutes') = any (today_candidates)
        and pg_temp.slot(ctx.d, ctx.conflict_time) = any (today_candidates)
        and pg_temp.slot(ctx.d, ctx.conflict_time + interval '30 minutes') = any (today_candidates),
        format('Requested for tomorrow: several of today''s remaining positions are offered (%s)', today_candidates)
    );
    perform pg_temp.assert_true(
        (select bool_and(pg_temp.at_local(ctx.d, split_part(slot, ' ', 2)::time) > before_read)
         from unnest(today_candidates) as slot),
        'Today''s positions at or before now are never offered'
    );
end;
$$;

set local role authenticated;
select pg_temp.assert_true(
    (select not (pg_temp.slot(d + 1, '10:00') = any (pg_temp.candidates(4, 27, d, d + 1)))
            and cardinality(pg_temp.candidates(4, 27, d + 1, d + 1)) = 47
     from pg_temp.today_ctx),
    'Reading from today: the requested start tomorrow stays excluded and tomorrow''s other 47 positions remain'
);
select pg_temp.assert_true(
    (select not (pg_temp.slot(d, conflict_time) = any (pg_temp.candidates(4, 28, d, d)))
            and pg_temp.slot(d, conflict_time - interval '30 minutes') = any (pg_temp.candidates(4, 28, d, d))
            and pg_temp.slot(d, conflict_time + interval '30 minutes') = any (pg_temp.candidates(4, 28, d, d))
     from pg_temp.today_ctx),
    'The assigned Veterinarian''s CONFIRMED commitment today removes only that position'
);
select pg_temp.assert_true(
    (select cardinality(pg_temp.candidates(4, 30, d, d + 1)) = 0 from pg_temp.today_ctx),
    'Opening Hours without Appointment Availability yield no candidates (SPEC-APT-013 BR-72)'
);
select pg_temp.assert_true(
    (select cardinality(pg_temp.candidates(4, 31, d, d)) = 0
            and cardinality(pg_temp.candidates(4, 31, d + 1, d + 1)) = 47
     from pg_temp.today_ctx),
    'No Appointment Availability today (CLOSED exception): no candidate today, tomorrow unaffected'
);
reset role;

-- A returned candidate from today is accepted unchanged.
do $$
declare
    ctx record;
    candidate record;
    created uuid;
begin
    select * into ctx from pg_temp.today_ctx;
    set local role authenticated;
    perform pg_temp.act(4);
    select * into candidate
    from public.get_requested_appointment_alternative_candidate_start_times(pg_temp.appt(27), ctx.d, ctx.d)
    where candidate_local_time = ctx.conflict_time;
    created := pg_temp.alt_propose(4, 27, candidate.candidate_local_date, candidate.candidate_local_time,
                                   candidate.utc_offset_seconds, 1);
    reset role;
    perform pg_temp.assert_true(
        (pg_temp.proposal(created)).proposed_start_at = pg_temp.at_local(ctx.d, ctx.conflict_time)
        and (pg_temp.proposal(created)).proposed_end_at = candidate.candidate_end_at
        and (pg_temp.proposal(created)).proposed_start_at < (pg_temp.latest_revision(27)).scheduled_start_at
        and pg_temp.lifecycle(27) = 'REQUESTED',
        'A proposal earlier than the request (today, request tomorrow) is created exactly as read; the Appointment stays REQUESTED'
    );
end;
$$;

-- ===========================================================================
-- 13. Reads never write; nothing retained.
-- ===========================================================================

select pg_temp.remember(10);
set local role authenticated;
select count(*) from pg_temp.guardian_row(10);
select count(*) from pg_temp.clinic_row(10, 1);
select cardinality(pg_temp.candidates(8, 10, '2035-03-07', '2035-03-08'));
reset role;
select pg_temp.assert_true(pg_temp.unchanged(10), 'Reads never change Proposals or the Appointment');

rollback;

-- Nothing synthetic is retained.
do $$
begin
    if exists (select 1 from public.appointments where id::text like 'a1700000-%')
       or exists (select 1 from public.users where id::text like 'a1700000-%')
       or exists (select 1 from public.veterinary_organizations where id::text like 'a1700000-%') then
        raise exception 'Synthetic rows were retained';
    end if;
end;
$$;

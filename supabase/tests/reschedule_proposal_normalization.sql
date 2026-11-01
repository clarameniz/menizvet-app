-- Regression suite for the Reschedule Proposal normalization, migration
-- 20261009090000_reschedule_proposal_normalization.sql:
--   SPEC-APT-005 BR-14, BR-31, BR-33 (PENDING invariant, derived lapse, VOID),
--   SPEC-APT-006 BR-34 (acceptance facts are the resulting revision's),
--   SPEC-APT-016 (withdrawal facts), docs/RELATIONAL_MODEL.md (composite
--   integrity, provenance, one PENDING Proposal per Appointment).
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required to load a deterministic context, to write protected
-- tables directly when a rule must be shown to hold against a direct write,
-- and to switch between impersonated Users.
--
-- Behavioral calls go through the real trusted operations as `authenticated`;
-- wrappers fire every pending deferred trigger at the end of each call.
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
    select ('c6a00000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('c6a00000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c6a00000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c6a00000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c6a00000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'c6a00000-0000-4000-8000-000000000a01'::uuid
$$;
create function pg_temp.rev(p_n integer, p_sequence integer) returns uuid language sql as $$
    select id from public.appointment_schedule_revisions
    where appointment_id = pg_temp.appt(p_n) and revision_sequence = p_sequence
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

create function pg_temp.clinic_propose(p_user integer, p_n integer, p_date date, p_time time, p_offset integer, p_sequence integer)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_confirmed_appointment_reschedule(
        pg_temp.appt(p_n), 'CLINIC', p_date, p_time, p_offset, 'Veterinarian unavailable', p_sequence
    );
    perform pg_temp.flush();
    return created;
end;
$$;

create function pg_temp.guardian_propose(p_user integer, p_n integer, p_date date, p_time time, p_offset integer)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_confirmed_appointment_reschedule(
        pg_temp.appt(p_n), 'GUARDIAN', p_date, p_time, p_offset, null, null
    );
    perform pg_temp.flush();
    return created;
end;
$$;

create function pg_temp.accept(p_user integer, p_proposal uuid, p_context text default 'GUARDIAN')
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.accept_appointment_reschedule_proposal(p_proposal, p_context);
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

create function pg_temp.proposal(p_id uuid) returns public.appointment_reschedule_proposals language sql as $$
    select * from public.appointment_reschedule_proposals where id = p_id
$$;

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

create function pg_temp.clinic_pending(p_n integer) returns uuid language plpgsql as $$
declare result uuid;
begin
    perform pg_temp.act(4);
    select read_row.pending_reschedule_proposal_id into result
    from public.get_clinic_appointment_schedule(pg_temp.clinic(1)) as read_row
    where read_row.id = pg_temp.appt(p_n);
    return result;
end;
$$;

create function pg_temp.eligible(p_communication_id uuid) returns boolean language sql as $$
    select public.communication_delivery_is_currently_eligible(p_communication_id, 'EMAIL', null, null)
$$;

-- Every persisted scheduling and Communication fact of the suite's Appointments.
create function pg_temp.fingerprint() returns text language sql as $$
    select md5(
        coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.id)
                  from public.appointment_schedule_revisions as revision), '')
        || '#' || coalesce((select string_agg(appointment::text, '|' order by appointment.id)
                  from public.appointments as appointment), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication), '')
    )
$$;

-- The 20261008090000 actionability predicate, evaluated on the normalized
-- representation of the same facts: a proposal the old model kept PENDING
-- with no recorded fact (now VOID for a superseded base, a lifecycle change, or
-- clinical documentation) is presented as such; a recorded lazy fact maps to VOID.
create function pg_temp.legacy_is_actionable(p_proposal_id uuid, p_as_of timestamptz)
returns boolean language sql as $$
    select exists (
        select 1
        from public.appointment_reschedule_proposals as proposal
        join public.appointments as appointment on appointment.id = proposal.appointment_id
        join public.appointment_schedule_revisions as base_revision on base_revision.id = proposal.base_revision_id
        where proposal.id = p_proposal_id
          and (proposal.state = 'PENDING'
               or (proposal.state = 'VOID'
                   and proposal.void_reason in ('BASE_REVISION_SUPERSEDED', 'APPOINTMENT_LIFECYCLE_CHANGED',
                                                'CLINICAL_DOCUMENTATION_STARTED')))
          and appointment.lifecycle_state = 'CONFIRMED'
          and base_revision.revision_context = 'CONFIRMED'
          and base_revision.scheduled_start_at > p_as_of
          and proposal.proposed_start_at > p_as_of
          and not exists (select 1 from public.clinical_record_entries as entry_row
                          where entry_row.appointment_id = proposal.appointment_id)
          and not exists (select 1 from public.appointment_schedule_revisions as later_revision
                          where later_revision.appointment_id = proposal.appointment_id
                            and later_revision.revision_context = 'CONFIRMED'
                            and later_revision.revision_sequence > base_revision.revision_sequence)
          and ((proposal.proposing_context = 'GUARDIAN'
                and public.user_has_continuous_guardianship_since(proposal.proposed_by_user_id, appointment.pet_id, proposal.created_at))
               or (proposal.proposing_context = 'CLINIC'
                   and public.user_has_continuous_clinic_reschedule_authority_since(proposal.proposed_by_user_id, appointment.clinic_id, proposal.created_at)))
    )
$$;

-- ===========================================================================
-- 1. Schema contract.
-- ===========================================================================

select pg_temp.assert_true(
    (select array_agg(column_name::text order by ordinal_position)
     from information_schema.columns
     where table_schema = 'public' and table_name = 'appointment_reschedule_proposals')
        = array['id', 'appointment_id', 'base_revision_id', 'proposed_start_at', 'proposed_end_at',
                'proposed_timezone_name', 'proposing_context', 'proposed_by_user_id', 'reason', 'state',
                'created_at', 'withdrawn_at', 'withdrawn_by_user_id', 'base_revision_context',
                'voided_at', 'void_reason'],
    'Contract: the Proposal stores no acceptance or non-actionable columns'
);

select pg_temp.assert_true(
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_reschedule_proposals_base_revision_fkey')
        = 'FOREIGN KEY (base_revision_id, appointment_id, base_revision_context) REFERENCES appointment_schedule_revisions(id, appointment_id, revision_context) ON DELETE RESTRICT'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_schedule_revisions_source_proposal_fkey')
        = 'FOREIGN KEY (source_proposal_id, appointment_id, revision_context) REFERENCES appointment_reschedule_proposals(id, appointment_id, base_revision_context) ON DELETE RESTRICT'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_reschedule_proposals_appointment_context_key')
        = 'UNIQUE (id, appointment_id, base_revision_context)'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_schedule_revisions_appointment_context_key')
        = 'UNIQUE (id, appointment_id, revision_context)'
    -- 20261010090000 (SPEC-APT-018): REQUESTED bases are enabled, Clinic-originated only.
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_reschedule_proposals_base_revision_context_check')
        = 'CHECK ((base_revision_context = ANY (ARRAY[''REQUESTED''::text, ''CONFIRMED''::text])))'
    and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'appointment_reschedule_proposals_requested_base_clinic_check')
        = 'CHECK (((base_revision_context <> ''REQUESTED''::text) OR (proposing_context = ''CLINIC''::text)))'
    and not exists (select 1 from pg_constraint where conname in (
        'appointment_schedule_revisions_requested_no_proposal_check',
        'appointment_schedule_revisions_source_proposal_id_fkey',
        'appointment_reschedule_proposals_base_revision_id_fkey',
        'appointment_reschedule_proposals_resulting_revision_key')),
    'Contract: composite foreign keys and superkeys replace the single-column keys; a REQUESTED base is Clinic-only'
);

select pg_temp.assert_true(
    (select indexdef from pg_indexes where indexname = 'appointment_reschedule_proposals_pending_key')
        = 'CREATE UNIQUE INDEX appointment_reschedule_proposals_pending_key ON public.appointment_reschedule_proposals USING btree (appointment_id) WHERE (state = ''PENDING''::text)'
    and exists (select 1 from pg_indexes where indexname = 'appointment_reschedule_proposals_history_idx')
    and exists (select 1 from pg_indexes where indexname = 'appointment_schedule_revisions_source_proposal_key')
    and not exists (select 1 from pg_indexes where indexname = 'appointment_schedule_revisions_latest_idx'),
    'Contract: one PENDING Proposal per Appointment; the redundant latest-revision index is gone'
);

select pg_temp.assert_true(
    to_regprocedure('public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz, uuid)') is null
    and to_regprocedure('public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz)') is not null
    and to_regprocedure('public.resolve_clinic_appointment_interval(uuid, date, time, integer, date, time, integer)') is null
    and to_regprocedure('public.enforce_appointment_schedule_revision_source_proposal_context()') is null
    and not (select bool_or(has_function_privilege('authenticated', signature, 'EXECUTE'))
             from unnest(array[
                 'public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz)',
                 'public.void_open_reschedule_proposal(uuid, text)',
                 'public.enforce_reschedule_proposal_invalidation()'
             ]) as signature)
    and (select count(*) = 3 from pg_trigger
         where tgname in ('appointment_schedule_revisions_invalidate_reschedule_proposal',
                          'appointments_invalidate_reschedule_proposal',
                          'clinical_record_entries_invalidate_reschedule_proposal')
           and not tgisinternal and not tgdeferrable)
    and not exists (select 1 from pg_trigger where tgname = 'appointment_schedule_revisions_validate_source_proposal'),
    'Contract: internal helpers only; three immediate invalidation triggers; obsolete trigger and helper removed'
);

select pg_temp.assert_true(
    (select pg_get_function_arguments(oid) from pg_proc where oid = 'public.accept_appointment_reschedule_proposal(uuid, text)'::regprocedure)
        = 'p_proposal_id uuid, p_accepting_context text'
    and (select pg_get_function_result(oid) from pg_proc where oid = 'public.get_appointment_scheduling_history(uuid)'::regprocedure)
        = 'TABLE(revision_sequence integer, revision_context text, scheduled_start_at timestamp with time zone, scheduled_end_at timestamp with time zone, establishment_timezone_name text, established_by_user_id uuid, established_at timestamp with time zone, is_accepted_reschedule boolean, reschedule_proposing_context text, reschedule_proposed_by_user_id uuid, reschedule_reason text, reschedule_proposed_at timestamp with time zone, reschedule_accepting_context text, reschedule_accepted_by_user_id uuid, reschedule_accepted_at timestamp with time zone)',
    'Contract: the public acceptance RPC and the history read keep their signatures'
);

-- ===========================================================================
-- Fixtures. Users: 01, 02 Guardians; 04 OrgA OWNER; 07 OrgA RECEPTIONIST
-- (Org); 10 VETERINARIAN @ A1; 13 OrgA RECEPTIONIST whose Grant ends
-- in-suite. Clinic A1 (0401) 08:00–20:00 every day, Europe/Madrid.
-- Appointment n is Luna's, CONFIRMED (revision 1 REQUESTED, revision 2
-- CONFIRMED), with Care Authorization c<n>.
-- ===========================================================================

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at)
select ('c6a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'n' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 2, 4, 7, 10, 13]) as n;
insert into public.users (id) select pg_temp.domain_user(n) from unnest(array[1, 2, 4, 7, 10, 13]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c6a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 2, 4, 7, 10, 13]) as n;

insert into public.veterinary_organizations (id, display_name) values ('c6a00000-0000-4000-8000-000000000301', 'Org A');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.clinic(1), 'c6a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30);
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.clinic(1), weekday, '08:00', '20:00' from generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    ('c6a00000-0000-4000-8000-000000000504', 'c6a00000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z'),
    ('c6a00000-0000-4000-8000-000000000507', 'c6a00000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z'),
    ('c6a00000-0000-4000-8000-000000000510', 'c6a00000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z'),
    ('c6a00000-0000-4000-8000-000000000513', 'c6a00000-0000-4000-8000-000000000301', pg_temp.domain_user(13), '2020-01-01Z');
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values
    ('c6a00000-0000-4000-8000-000000000604', 'c6a00000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4)),
    ('c6a00000-0000-4000-8000-000000000607', 'c6a00000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4)),
    ('c6a00000-0000-4000-8000-000000000610', 'c6a00000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4)),
    ('c6a00000-0000-4000-8000-000000000613', 'c6a00000-0000-4000-8000-000000000513', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4));
insert into public.veterinarian_professional_profiles (id, user_id) values ('c6a00000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values ('c6a00000-0000-4000-8000-000000000810', 'c6a00000-0000-4000-8000-000000000710', 'c6a00000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z');
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until, establishment_source, establishment_idempotency_key
) values ('c6a00000-0000-4000-8000-000000000901', 'c6a00000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE', '2020-01-01Z',
          null, null, 'normalization-test', 'c6a00000-0000-4000-8000-000000000991');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values
    ('c6a00000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z'),
    ('c6a00000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z');

create function pg_temp.seed(p_n integer, p_start timestamptz)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), pg_temp.clinic(1), pg_temp.domain_user(1), 'Visit ' || p_n, 'CONFIRMED',
            '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values
        (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
         pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n)),
        (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
         pg_temp.domain_user(7), null, '2026-01-02T00:00:00Z');
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
    ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(7), 'CLINIC', null,
              '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z');
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) values (pg_temp.ca(p_n), pg_temp.luna(), pg_temp.clinic(1), 'c6a00000-0000-4000-8000-000000000301',
              'c6a00000-0000-4000-8000-000000000a11', '2026-01-01T00:00:00Z', 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE');
end;
$$;

-- A Proposal loaded directly, for states no trusted operation produces on demand.
create function pg_temp.load_proposal(p_name text, p_n integer, p_start timestamptz, p_user integer, p_created timestamptz)
returns uuid language sql as $$
    with created as (
        insert into public.appointment_reschedule_proposals (
            appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
            proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
        ) values (pg_temp.appt(p_n), pg_temp.rev(p_n, 2), 'CONFIRMED', p_start, p_start + interval '30 minutes',
                  'Europe/Madrid', 'CLINIC', pg_temp.domain_user(p_user), 'Loaded', p_created)
        returning id
    )
    insert into ids select p_name, id from created returning id
$$;

select pg_temp.seed(n, ('2035-06-01T08:00:00Z'::timestamptz + make_interval(days => n)))
from generate_series(1, 20) as n;
-- 21: the confirmed start has passed (NO_SHOW-eligible).
select pg_temp.seed(21, '2026-01-10T08:00:00Z');
select pg_temp.seed(22, '2035-07-01T08:00:00Z');
select pg_temp.seed(23, '2035-07-02T08:00:00Z');

-- 24: an Appointment at a second Clinic of the Organization, with an open
-- proposal that a read of Clinic A1 must never evaluate.
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.clinic(2), 'c6a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30);
select pg_temp.seed(24, '2035-07-03T08:00:00Z');
update public.appointments set clinic_id = pg_temp.clinic(2) where id = pg_temp.appt(24);
update public.care_authorizations set clinic_id = pg_temp.clinic(2) where id = pg_temp.ca(24);
select pg_temp.load_proposal('other_clinic', 24, '2035-07-10T08:00:00Z', 7, '2026-01-05T00:00:00Z');

-- 10: a lapsed PENDING proposal (proposed start passed, base still future).
select pg_temp.load_proposal('lapsed', 10, '2026-01-20T08:00:00Z', 7, '2026-01-05T00:00:00Z');
-- 21: a PENDING proposal whose base start has passed.
select pg_temp.load_proposal('base_passed', 21, '2035-01-01T08:00:00Z', 7, '2026-01-05T00:00:00Z');

set local session_replication_role = origin;

-- ===========================================================================
-- 2. Composite integrity — direct writes, the base trigger disabled so the
--    foreign keys themselves are exercised.
-- ===========================================================================

alter table public.appointment_reschedule_proposals disable trigger appointment_reschedule_proposals_validate_base_revision;
-- A base of another Appointment.
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''CONFIRMED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', now())',
    pg_temp.appt(1), pg_temp.rev(2, 2), pg_temp.domain_user(7)),
    '23503', 'appointment_reschedule_proposals_base_revision_fkey');
-- A base whose context is not the recorded base context (revision 1 is REQUESTED).
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''CONFIRMED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', now())',
    pg_temp.appt(1), pg_temp.rev(1, 1), pg_temp.domain_user(7)),
    '23503', 'appointment_reschedule_proposals_base_revision_fkey');
-- A REQUESTED base is enabled only for the Clinic context (20261010090000,
-- SPEC-APT-018 BR-2).
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''REQUESTED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''GUARDIAN'', %L, null, now())',
    pg_temp.appt(1), pg_temp.rev(1, 1), pg_temp.domain_user(1)),
    '23514', 'appointment_reschedule_proposals_requested_base_clinic_check');
alter table public.appointment_reschedule_proposals enable trigger appointment_reschedule_proposals_validate_base_revision;

-- A revision sourced from another Appointment's Proposal, or in another context.
select pg_temp.assert_error(format(
    'insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at) values (%L, 3, ''CONFIRMED'', ''2026-01-20T08:00Z'', ''2026-01-20T08:30Z'', ''Europe/Madrid'', %L, %L, now())',
    pg_temp.appt(1), pg_temp.domain_user(1), pg_temp.id('lapsed')),
    '23503', 'appointment_schedule_revisions_source_proposal_fkey');
select pg_temp.assert_error(format(
    'insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at) values (%L, 3, ''REQUESTED'', ''2026-01-20T08:00Z'', ''2026-01-20T08:30Z'', ''Europe/Madrid'', %L, %L, now())',
    pg_temp.appt(10), pg_temp.domain_user(1), pg_temp.id('lapsed')),
    '23503', 'appointment_schedule_revisions_source_proposal_fkey');

-- ===========================================================================
-- 3. Establishment and the four states' shapes.
-- ===========================================================================

-- A Proposal is established PENDING with no resolution facts.
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at, state, voided_at, void_reason) values (%L, %L, ''CONFIRMED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', now(), ''VOID'', now(), ''PROPOSED_TIME_PASSED'')',
    pg_temp.appt(2), pg_temp.rev(2, 2), pg_temp.domain_user(7)),
    '23514', 'must be established as PENDING');
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at, withdrawn_at) values (%L, %L, ''CONFIRMED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', now(), now())',
    pg_temp.appt(2), pg_temp.rev(2, 2), pg_temp.domain_user(7)),
    '23514', 'appointment_reschedule_proposals_withdrawn_shape_check');
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at, void_reason) values (%L, %L, ''CONFIRMED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', now(), ''PROPOSED_TIME_PASSED'')',
    pg_temp.appt(2), pg_temp.rev(2, 2), pg_temp.domain_user(7)),
    '23514', 'appointment_reschedule_proposals_void_shape_check');

-- The CHECKs hold without the integrity trigger (shape and reason vocabulary).
alter table public.appointment_reschedule_proposals disable trigger appointment_reschedule_proposals_enforce_integrity;
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''VOID'' where id = %L', pg_temp.id('lapsed')),
    '23514', 'appointment_reschedule_proposals_void_shape_check');
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''VOID'', voided_at = now(), void_reason = ''EXPIRED'' where id = %L', pg_temp.id('lapsed')),
    '23514', 'appointment_reschedule_proposals_void_reason_check');
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''WITHDRAWN'', withdrawn_at = now() where id = %L', pg_temp.id('lapsed')),
    '23514', 'appointment_reschedule_proposals_withdrawn_shape_check');
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''VOID'', voided_at = ''2020-01-01Z'', void_reason = ''PROPOSED_TIME_PASSED'' where id = %L', pg_temp.id('lapsed')),
    '23514', 'appointment_reschedule_proposals_voided_at_check');
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''REJECTED'' where id = %L', pg_temp.id('lapsed')),
    '23514', 'appointment_reschedule_proposals_state_check');
alter table public.appointment_reschedule_proposals enable trigger appointment_reschedule_proposals_enforce_integrity;

-- ===========================================================================
-- 4. A lapsed PENDING proposal is non-actionable, unprojected, and reads never
--    write.
-- ===========================================================================

create temporary table snapshot on commit drop as select pg_temp.fingerprint() as value;
set local role authenticated;
select pg_temp.assert_true(pg_temp.guardian_pending(10) is null and pg_temp.clinic_pending(10) is null
    and pg_temp.guardian_pending(21) is null and pg_temp.clinic_pending(21) is null,
    'Lapsed PENDING proposals are not projected by either read');
select pg_temp.act(1);
select count(*) from public.get_appointment_scheduling_history(pg_temp.appt(10));
select pg_temp.act(7);
select count(*) from public.get_appointment_reschedule_candidate_start_times(pg_temp.appt(11), '2035-06-12', '2035-06-13');
reset role;
select pg_temp.assert_true(
    (select value from snapshot) = pg_temp.fingerprint()
    and (pg_temp.proposal(pg_temp.id('lapsed'))).state = 'PENDING'
    and (pg_temp.proposal(pg_temp.id('base_passed'))).state = 'PENDING'
    and not public.appointment_reschedule_proposal_is_actionable(pg_temp.id('lapsed'), clock_timestamp())
    and not public.appointment_reschedule_proposal_is_actionable(pg_temp.id('base_passed'), clock_timestamp()),
    'A derived lapse keeps the proposal PENDING and non-actionable; reads change nothing'
);

-- ===========================================================================
-- 5. Lazy VOID on proposal creation.
-- ===========================================================================

-- Proposed time passed (10).
set local role authenticated;
select pg_temp.keep('p10', pg_temp.clinic_propose(7, 10, '2035-06-12', '12:00', 7200, 2));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('lapsed'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('lapsed'))).void_reason = 'PROPOSED_TIME_PASSED'
    and (pg_temp.proposal(pg_temp.id('lapsed'))).voided_at >= (pg_temp.proposal(pg_temp.id('lapsed'))).proposed_start_at
    and (pg_temp.proposal(pg_temp.id('p10'))).state = 'PENDING',
    'A new proposal voids a lapsed one with PROPOSED_TIME_PASSED and takes the slot'
);

-- Proposer authority lost (11): User 13 proposes, then loses the Grant.
set local role authenticated;
select pg_temp.keep('p11a', pg_temp.clinic_propose(13, 11, '2035-06-12', '12:00', 7200, 2));
reset role;
set local session_replication_role = replica;
update public.organization_responsibility_grants
set effective_end = clock_timestamp(), ended_by_user_id = pg_temp.domain_user(4)
where id = 'c6a00000-0000-4000-8000-000000000613';
set local session_replication_role = origin;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p11a'))).state = 'PENDING'
    and not public.appointment_reschedule_proposal_is_actionable(pg_temp.id('p11a'), clock_timestamp()),
    'Authority loss makes the proposal non-actionable but leaves it PENDING'
);
set local role authenticated;
select pg_temp.keep('p11b', pg_temp.clinic_propose(7, 11, '2035-06-12', '13:00', 7200, 2));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p11a'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p11a'))).void_reason = 'PROPOSING_AUTHORITY_LOST'
    and (pg_temp.proposal(pg_temp.id('p11b'))).state = 'PENDING',
    'A new proposal voids one whose proposer lost authority with PROPOSING_AUTHORITY_LOST'
);

-- ===========================================================================
-- 6. Eager VOID.
-- ===========================================================================

-- Lifecycle change: Clinic cancellation (1), Guardian cancellation (2), NO_SHOW (21).
set local role authenticated;
select pg_temp.keep('p1', pg_temp.clinic_propose(7, 1, '2035-06-02', '14:00', 7200, 2));
select pg_temp.keep('p2', pg_temp.clinic_propose(7, 2, '2035-06-03', '14:00', 7200, 2));
select pg_temp.act(7);
select public.cancel_appointment(pg_temp.appt(1), 'CLINIC', 'Closed', 2);
select pg_temp.act(1);
select public.cancel_appointment(pg_temp.appt(2), 'GUARDIAN');
select pg_temp.act(4);
select public.mark_appointment_no_show(pg_temp.appt(21), 2);
select pg_temp.flush();
reset role;
select pg_temp.assert_true(
    (select bool_and(state = 'VOID' and void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED' and voided_at >= created_at)
     from public.appointment_reschedule_proposals
     where id in (pg_temp.id('p1'), pg_temp.id('p2'), pg_temp.id('base_passed'))),
    'Clinic cancellation, Guardian cancellation, and NO_SHOW each void the pending proposal'
);

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

-- Clinical documentation (3): the first Clinical Record Entry (SPEC-MED-010 BR-8).
set local role authenticated;
select pg_temp.keep('p3', pg_temp.clinic_propose(7, 3, '2035-06-04', '14:00', 7200, 2));
reset role;
select pg_temp.record_entry(pg_temp.appt(3), 'c6a00000-0000-4000-8000-000000000810');
select pg_temp.flush();
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p3'))).state = 'VOID'
    and (pg_temp.proposal(pg_temp.id('p3'))).void_reason = 'CLINICAL_DOCUMENTATION_STARTED',
    'The first Clinical Record Entry voids the pending proposal'
);
-- The specific acceptance outcome is preserved for a documentation-voided proposal.
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p3')), '23514', 'Appointment with clinical documentation cannot be rescheduled');
reset role;

-- Superseding revision (4): no approved workflow inserts a later revision while
-- a proposal is open, so a direct insert shows the trigger; the subtransaction
-- is then rolled back (its deferred provenance check would reject it).
set local role authenticated;
select pg_temp.keep('p4', pg_temp.clinic_propose(7, 4, '2035-06-05', '14:00', 7200, 2));
reset role;
do $$
begin
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(4), 3, 'CONFIRMED', '2035-06-05T15:00Z', '2035-06-05T15:30Z', 'Europe/Madrid',
              pg_temp.domain_user(7), null, clock_timestamp());
    if (pg_temp.proposal(pg_temp.id('p4'))).state <> 'VOID'
       or (pg_temp.proposal(pg_temp.id('p4'))).void_reason <> 'BASE_REVISION_SUPERSEDED' then
        raise exception 'A superseding revision did not void the pending proposal';
    end if;
    raise exception using errcode = 'P0002', message = 'rollback';
exception when sqlstate 'P0002' then
    null;
end;
$$;
select pg_temp.assert_true((pg_temp.proposal(pg_temp.id('p4'))).state = 'PENDING', 'The superseding-revision probe was rolled back');

-- Every VOID reason must be true when recorded.
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''VOID'', void_reason = %L where id = %L', reason, pg_temp.id('p4')),
    '23514', message)
from (values
    ('BASE_REVISION_SUPERSEDED', 'has not been superseded'),
    ('APPOINTMENT_LIFECYCLE_CHANGED', 'still matches'),
    ('CLINICAL_DOCUMENTATION_STARTED', 'No Clinical Record Entry'),
    ('PROPOSED_TIME_PASSED', 'had not passed'),
    ('PROPOSING_AUTHORITY_LOST', 'has remained continuous')
) as unjustified(reason, message);

-- A missing eager void would be caught: with the revision trigger disabled,
-- the dead proposal stays PENDING and the next proposal hits the uniqueness.
alter table public.appointment_schedule_revisions disable trigger appointment_schedule_revisions_invalidate_reschedule_proposal;
do $$
begin
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(4), 3, 'CONFIRMED', '2035-06-05T15:00Z', '2035-06-05T15:30Z', 'Europe/Madrid',
              pg_temp.domain_user(7), null, clock_timestamp());
    perform pg_temp.assert_error(format(
        'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''CONFIRMED'', ''2035-06-05T16:00Z'', ''2035-06-05T16:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', clock_timestamp())',
        pg_temp.appt(4), pg_temp.rev(4, 3), pg_temp.domain_user(7)),
        '23505', 'appointment_reschedule_proposals_pending_key');
    raise exception using errcode = 'P0002', message = 'rollback';
exception when sqlstate 'P0002' then
    null;
end;
$$;
alter table public.appointment_schedule_revisions enable trigger appointment_schedule_revisions_invalidate_reschedule_proposal;

-- At most one PENDING proposal per Appointment, even for a direct write.
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''CONFIRMED'', ''2035-06-05T17:00Z'', ''2035-06-05T17:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', clock_timestamp())',
    pg_temp.appt(4), pg_temp.rev(4, 2), pg_temp.domain_user(7)),
    '23505', 'appointment_reschedule_proposals_pending_key');

-- ===========================================================================
-- 7. Acceptance: ordering, provenance, derived facts, Communications.
-- ===========================================================================

set local role authenticated;
select pg_temp.keep('p5', pg_temp.clinic_propose(7, 5, '2035-06-06', '14:00', 7200, 2));
select pg_temp.accept(2, pg_temp.id('p5'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p5'))).state = 'ACCEPTED'
    and (pg_temp.proposal(pg_temp.id('p5'))).voided_at is null
    and (select count(*) = 1 from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p5'))
    and (select revision_sequence = 3 and revision_context = 'CONFIRMED'
                and scheduled_start_at = (pg_temp.proposal(pg_temp.id('p5'))).proposed_start_at
                and scheduled_end_at = (pg_temp.proposal(pg_temp.id('p5'))).proposed_end_at
                and establishment_timezone_name = (pg_temp.proposal(pg_temp.id('p5'))).proposed_timezone_name
                and established_by_user_id = pg_temp.domain_user(2)
         from public.appointment_schedule_revisions where source_proposal_id = pg_temp.id('p5')),
    'Acceptance never voids its own proposal and produces exactly one revision: base + 1, the frozen interval, the accepting User'
);
-- Communications: one ACCEPTED per current Guardian, dated by the resulting revision.
select pg_temp.assert_true(
    (select array_agg(communication.recipient_user_id order by communication.recipient_user_id)
     from public.transactional_communications as communication
     where communication.appointment_reschedule_proposal_id = pg_temp.id('p5')
       and communication.communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED')
        = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
    and (select bool_and(communication.appointment_schedule_revision_id = revision.id and communication.created_at = revision.created_at)
         from public.transactional_communications as communication
         join public.appointment_schedule_revisions as revision on revision.source_proposal_id = pg_temp.id('p5')
         where communication.appointment_reschedule_proposal_id = pg_temp.id('p5')
           and communication.communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED')
    and (select count(*) = 2 from public.transactional_communications
         where appointment_reschedule_proposal_id = pg_temp.id('p5') and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED')
    and (select count(*) = 0 from public.transactional_communications
         where appointment_reschedule_proposal_id in (pg_temp.id('p1'), pg_temp.id('p2'), pg_temp.id('p3'),
                                                      pg_temp.id('lapsed'), pg_temp.id('p11a'))
           and communication_type <> 'APPOINTMENT_RESCHEDULE_PROPOSED'),
    'Acceptance notifies each current Guardian once, dated by the resulting revision; VOID creates no Communication'
);
-- A repeated acceptance writes nothing.
create temporary table before_repeat on commit drop as select pg_temp.fingerprint() as value;
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p5')), '23514', 'Reschedule Proposal is no longer actionable');
reset role;
select pg_temp.assert_true((select value from before_repeat) = pg_temp.fingerprint(), 'A repeated acceptance writes nothing');
-- An accepted proposal is immutable, including to VOID.
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''VOID'', void_reason = ''BASE_REVISION_SUPERSEDED'' where id = %L', pg_temp.id('p5')),
    '23514', 'are immutable');

-- The PENDING invariant holds at establishment, even for a direct write: the
-- base must be current (5 now has revision 3), the lifecycle must equal the
-- base context (1 is CANCELLED), and no clinical documentation may exist (3).
select pg_temp.assert_error(format(
    'insert into public.appointment_reschedule_proposals (appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at) values (%L, %L, ''CONFIRMED'', ''2035-08-01T08:00Z'', ''2035-08-01T08:30Z'', ''Europe/Madrid'', ''CLINIC'', %L, ''x'', clock_timestamp())',
    pg_temp.appt(n), pg_temp.rev(n, 2), pg_temp.domain_user(7)),
    '23514', message)
from (values
    (5, 'base revision must be the current scheduling context'),
    (1, 'base context must match the Appointment lifecycle state'),
    (3, 'Appointment with clinical documentation cannot be rescheduled')
) as stale(n, message);

-- Derived acceptance facts through the public history read, for both contexts.
set local role authenticated;
select pg_temp.keep('p6', pg_temp.guardian_propose(1, 6, '2035-06-07', '14:00', 7200));
select pg_temp.accept(7, pg_temp.id('p6'), 'CLINIC');
select pg_temp.act(2);
select pg_temp.assert_true(
    (select is_accepted_reschedule and reschedule_proposing_context = 'CLINIC' and reschedule_accepting_context = 'GUARDIAN'
            and reschedule_accepted_by_user_id = pg_temp.domain_user(2) and reschedule_accepted_at = established_at
            and reschedule_proposed_by_user_id = pg_temp.domain_user(7)
     from public.get_appointment_scheduling_history(pg_temp.appt(5)) where revision_sequence = 3)
    and (select is_accepted_reschedule and reschedule_proposing_context = 'GUARDIAN' and reschedule_accepting_context = 'CLINIC'
                and reschedule_accepted_by_user_id = pg_temp.domain_user(7) and reschedule_accepted_at = established_at
                and reschedule_proposed_by_user_id = pg_temp.domain_user(1)
         from public.get_appointment_scheduling_history(pg_temp.appt(6)) where revision_sequence = 3),
    'Accepting context, User, and time are derived exactly from the resulting revision'
);
reset role;

-- Transactionality: a resulting-revision failure rolls the ACCEPTED state back.
create function public.normalization_test_fail_revision() returns trigger language plpgsql as $$
begin
    raise exception 'Injected revision failure' using errcode = 'P0003';
end;
$$;
create trigger normalization_test_fail_revision before insert on public.appointment_schedule_revisions
for each row when (new.appointment_id = 'c6a00000-0000-4000-8000-000000000b07'::uuid)
execute function public.normalization_test_fail_revision();
set local role authenticated;
select pg_temp.keep('p7', pg_temp.clinic_propose(7, 7, '2035-06-08', '14:00', 7200, 2));
reset role;
create temporary table before_failed on commit drop as select pg_temp.fingerprint() as value;
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.accept(1, %L)', pg_temp.id('p7')), 'P0003', 'Injected revision failure');
reset role;
drop trigger normalization_test_fail_revision on public.appointment_schedule_revisions;
select pg_temp.assert_true(
    (select value from before_failed) = pg_temp.fingerprint()
    and (pg_temp.proposal(pg_temp.id('p7'))).state = 'PENDING',
    'A failed acceptance leaves the proposal PENDING with no revision or Communication'
);

-- Withdrawal facts stay audited.
set local role authenticated;
select pg_temp.withdraw(4, pg_temp.id('p7'));
reset role;
select pg_temp.assert_true(
    (pg_temp.proposal(pg_temp.id('p7'))).state = 'WITHDRAWN'
    and (pg_temp.proposal(pg_temp.id('p7'))).withdrawn_by_user_id = pg_temp.domain_user(4)
    and (pg_temp.proposal(pg_temp.id('p7'))).withdrawn_at >= (pg_temp.proposal(pg_temp.id('p7'))).created_at
    and (pg_temp.proposal(pg_temp.id('p7'))).voided_at is null,
    'Withdrawal records who and when'
);
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''VOID'', void_reason = ''PROPOSED_TIME_PASSED'' where id = %L', pg_temp.id('p7')),
    '23514', 'are immutable');

-- Transition rules on a PENDING proposal.
set local role authenticated;
select pg_temp.keep('p8', pg_temp.clinic_propose(7, 8, '2035-06-09', '14:00', 7200, 2));
reset role;
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set reason = ''Edited'' where id = %L', pg_temp.id('p8')),
    '23514', 'may only become ACCEPTED, WITHDRAWN, or VOID');
select pg_temp.assert_error(format('update public.appointment_reschedule_proposals set state = ''WITHDRAWN'', withdrawn_by_user_id = %L, reason = ''Edited'' where id = %L', pg_temp.domain_user(7), pg_temp.id('p8')),
    '23514', 'context is immutable');
select pg_temp.assert_error(format('delete from public.appointment_reschedule_proposals where id = %L', pg_temp.id('p8')),
    '23514', 'cannot be deleted');

-- ===========================================================================
-- 8. Revision provenance.
-- ===========================================================================

-- A proposal produces at most one revision.
select pg_temp.assert_error(format(
    'insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at) values (%L, 4, ''CONFIRMED'', ''2035-06-06T12:00Z'', ''2035-06-06T12:30Z'', ''Europe/Madrid'', %L, %L, clock_timestamp())',
    pg_temp.appt(5), pg_temp.domain_user(1), pg_temp.id('p5')),
    '23505', 'appointment_schedule_revisions_source_proposal_key');

-- ACCEPTED without a resulting revision fails at commit.
do $$
begin
    update public.appointment_reschedule_proposals set state = 'ACCEPTED' where id = pg_temp.id('p8');
    perform pg_temp.assert_error('select pg_temp.flush()', '23514', 'requires exactly one resulting Schedule Revision');
    raise exception using errcode = 'P0002', message = 'rollback';
exception when sqlstate 'P0002' then
    null;
end;
$$;

-- A revision sourced from a non-ACCEPTED proposal, or not matching its
-- frozen interval, fails at commit.
do $$
begin
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) select pg_temp.appt(8), 3, 'CONFIRMED', proposed_start_at, proposed_end_at, proposed_timezone_name,
             pg_temp.domain_user(1), id, clock_timestamp()
      from public.appointment_reschedule_proposals where id = pg_temp.id('p8');
    perform pg_temp.assert_error('select pg_temp.flush()', '23514', 'source Proposal must be ACCEPTED');
    raise exception using errcode = 'P0002', message = 'rollback';
exception when sqlstate 'P0002' then
    null;
end;
$$;
do $$
begin
    update public.appointment_reschedule_proposals set state = 'ACCEPTED' where id = pg_temp.id('p8');
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) select pg_temp.appt(8), 3, 'CONFIRMED', proposed_start_at, proposed_end_at + interval '1 minute', proposed_timezone_name,
             pg_temp.domain_user(1), id, clock_timestamp()
      from public.appointment_reschedule_proposals where id = pg_temp.id('p8');
    perform pg_temp.assert_error('select pg_temp.flush()', '23514', 'must exactly match its source Proposal');
    raise exception using errcode = 'P0002', message = 'rollback';
exception when sqlstate 'P0002' then
    null;
end;
$$;

-- A sourced revision must immediately follow its proposal's base: two
-- proposals on the same base, both ACCEPTED, cannot both produce a revision.
set local session_replication_role = replica;
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, state, created_at
) values
    ('c6a00000-0000-4000-8000-000000000e91', pg_temp.appt(9), pg_temp.rev(9, 2), 'CONFIRMED',
     '2035-06-10T12:00Z', '2035-06-10T12:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'First', 'ACCEPTED', '2026-02-01Z'),
    ('c6a00000-0000-4000-8000-000000000e92', pg_temp.appt(9), pg_temp.rev(9, 2), 'CONFIRMED',
     '2035-06-10T13:00Z', '2035-06-10T13:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(7), 'Second', 'ACCEPTED', '2026-02-01Z');
set local session_replication_role = origin;
do $$
begin
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values
        (pg_temp.appt(9), 3, 'CONFIRMED', '2035-06-10T12:00Z', '2035-06-10T12:30Z', 'Europe/Madrid',
         pg_temp.domain_user(1), 'c6a00000-0000-4000-8000-000000000e91', clock_timestamp()),
        (pg_temp.appt(9), 4, 'CONFIRMED', '2035-06-10T13:00Z', '2035-06-10T13:30Z', 'Europe/Madrid',
         pg_temp.domain_user(1), 'c6a00000-0000-4000-8000-000000000e92', clock_timestamp());
    perform pg_temp.assert_error('select pg_temp.flush()', '23514', 'base revision is no longer the current scheduling context');
    raise exception using errcode = 'P0002', message = 'rollback';
exception when sqlstate 'P0002' then
    null;
end;
$$;

-- ===========================================================================
-- 9. Pending reads project only the PENDING proposal; delivery follows
--    actionability.
-- ===========================================================================

-- 12 carries WITHDRAWN, VOID, and ACCEPTED history and one open proposal.
set local role authenticated;
select pg_temp.keep('p12a', pg_temp.clinic_propose(7, 12, '2035-06-13', '12:00', 7200, 2));
select pg_temp.withdraw(7, pg_temp.id('p12a'));
select pg_temp.keep('p12b', pg_temp.clinic_propose(7, 12, '2035-06-13', '13:00', 7200, 2));
select pg_temp.accept(1, pg_temp.id('p12b'));
select pg_temp.keep('p12c', pg_temp.clinic_propose(7, 12, '2035-06-13', '15:00', 7200, 3));
select pg_temp.assert_true(pg_temp.guardian_pending(12) = pg_temp.id('p12c') and pg_temp.clinic_pending(12) = pg_temp.id('p12c'),
    'Both reads project exactly the PENDING proposal among WITHDRAWN and ACCEPTED history');
select pg_temp.assert_true(pg_temp.guardian_pending(1) is null and pg_temp.clinic_pending(3) is null,
    'An Appointment with only VOID proposals projects none');
reset role;
select pg_temp.assert_true(
    pg_temp.eligible((select id from public.transactional_communications where appointment_reschedule_proposal_id = pg_temp.id('p12c')
                      and recipient_user_id = pg_temp.domain_user(1) and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'))
    and not pg_temp.eligible((select id from public.transactional_communications where appointment_reschedule_proposal_id = pg_temp.id('p1')
                              and recipient_user_id = pg_temp.domain_user(1) and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'))
    and not pg_temp.eligible((select id from public.transactional_communications where appointment_reschedule_proposal_id = pg_temp.id('p12a')
                              and recipient_user_id = pg_temp.domain_user(1) and communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED')),
    'Proposal notifications are delivered only for the actionable PENDING proposal'
);

-- The Clinic read evaluates actionability only for its own Appointments' open
-- proposals (one lookup per Appointment), never for every PENDING proposal.
set local track_functions = 'all';
create temporary table actionability_calls on commit drop as
select coalesce((select calls from pg_stat_xact_user_functions
                 where funcname = 'appointment_reschedule_proposal_is_actionable'), 0) as before_read;
set local role authenticated;
select pg_temp.clinic_pending(12);
reset role;
select pg_temp.assert_true(
    (select coalesce((select calls from pg_stat_xact_user_functions
                      where funcname = 'appointment_reschedule_proposal_is_actionable'), 0) - before_read
     from actionability_calls)
        = (select count(*) from public.appointment_reschedule_proposals as proposal
           join public.appointments as appointment on appointment.id = proposal.appointment_id
           where proposal.state = 'PENDING' and appointment.clinic_id = pg_temp.clinic(1))
    and (select count(*) from public.appointment_reschedule_proposals where state = 'PENDING' and id = pg_temp.id('other_clinic')) = 1,
    'The Clinic read evaluates actionability once per open proposal of that Clinic only'
);

-- ===========================================================================
-- 10. Actionability equals the previous predicate on every proposal.
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(public.appointment_reschedule_proposal_is_actionable(proposal.id, as_of)
                     = pg_temp.legacy_is_actionable(proposal.id, as_of))
     from public.appointment_reschedule_proposals as proposal
     cross join unnest(array[clock_timestamp(), '2026-01-15T00:00Z'::timestamptz, '2035-06-06T13:00Z'::timestamptz,
                             '2035-06-13T14:00Z'::timestamptz, '2040-01-01T00:00Z'::timestamptz]) as as_of)
    and (select count(*) >= 15 from public.appointment_reschedule_proposals),
    'For every proposal and instant, normalized actionability equals the 20261008 predicate'
);

-- ===========================================================================
-- 11. Nothing persists.
-- ===========================================================================

rollback;

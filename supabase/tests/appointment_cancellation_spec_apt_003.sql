-- Regression suite for SPEC-APT-003 — Cancel Appointment, stale-safe Clinic
-- cancellation (BR-24 to BR-29), migration
-- 20261006090000_stale_safe_clinic_appointment_cancellation.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables, and to switch
-- between impersonated Users.
--
-- Every behavioral call goes through the real trusted operations — including
-- the Guardian requested-time reschedule and the Clinic proposal / Guardian
-- acceptance that make a reviewed revision stale. Helper wrappers fire every
-- pending deferred trigger at the end of each call (SET CONSTRAINTS ALL
-- IMMEDIATE, then back to DEFERRED), so deferred lifecycle, Care
-- Authorization, and clinical documentation coherence run inside the same
-- subtransaction. Revisions that differ only in end or timezone, which no
-- trusted operation produces on demand, are loaded as fixtures.
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
    select ('c4a00000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('c4a00000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c4a00000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c4a00000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c4a00000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'c4a00000-0000-4000-8000-000000000a01'::uuid
$$;
create function pg_temp.vca() returns uuid language sql immutable as $$
    select 'c4a00000-0000-4000-8000-000000000810'::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.cancel(p_n integer, p_context text, p_reason text, p_sequence integer)
returns uuid language plpgsql as $$
declare cancelled uuid;
begin
    cancelled := public.cancel_appointment(pg_temp.appt(p_n), p_context, p_reason, p_sequence);
    perform pg_temp.flush();
    return cancelled;
end;
$$;

-- A CLINIC cancellation by User p_user with a fixed reason.
create function pg_temp.clinic_cancel_as(p_user integer, p_n integer, p_sequence integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform pg_temp.cancel(p_n, 'CLINIC', 'Clinic closed that day', p_sequence);
end;
$$;

create function pg_temp.no_show(p_n integer, p_sequence integer)
returns void language plpgsql as $$
begin
    perform public.mark_appointment_no_show(pg_temp.appt(p_n), p_sequence);
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
    created := pg_temp.record_entry(pg_temp.appt(p_n), pg_temp.vca());
    perform pg_temp.flush();
    return created;
end;
$$;

-- SPEC-APT-009: stale-safe lightweight completion; every fixture that is
-- completed here is CONFIRMED at revision 2 with a reached start.
create function pg_temp.complete(p_n integer)
returns void language plpgsql as $$
begin
    perform public.complete_appointment(pg_temp.appt(p_n), 2);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.reschedule_requested(p_n integer, p_date date, p_time time)
returns void language plpgsql as $$
begin
    perform public.reschedule_requested_appointment(pg_temp.appt(p_n), p_date, p_time, 3600);
    perform pg_temp.flush();
end;
$$;

-- Start-only proposal (SPEC-APT-005 BR-23): the end is the new start plus the
-- Clinic's current standard Appointment duration (BR-24; here 30 minutes, as is
-- every base interval), and the Clinic call carries the current confirmed
-- revision.
create function pg_temp.propose_and_accept(p_n integer, p_date date, p_start time, p_confirmed_sequence integer)
returns void language plpgsql as $$
declare proposal uuid;
begin
    perform pg_temp.act(7);
    proposal := public.propose_confirmed_appointment_reschedule(
        pg_temp.appt(p_n), 'CLINIC', p_date, p_start, 3600, 'Veterinarian unavailable', p_confirmed_sequence
    );
    perform pg_temp.flush();
    perform pg_temp.act(1);
    perform public.accept_appointment_reschedule_proposal(proposal, 'GUARDIAN');
    perform pg_temp.flush();
end;
$$;

create function pg_temp.state(p_n integer) returns text language sql as $$
    select lifecycle_state from public.appointments where id = pg_temp.appt(p_n)
$$;

create function pg_temp.latest_sequence(p_n integer) returns integer language sql as $$
    select max(revision_sequence) from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(p_n)
$$;

-- Every persisted fact a cancellation could touch for one Appointment.
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
        || '#' || coalesce((select string_agg(care_auth::text, '|' order by care_auth.id)
                  from public.care_authorizations as care_auth
                  where care_auth.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication
                  where communication.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal
                  where proposal.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(assignment::text, '|' order by assignment.id)
                  from public.appointment_veterinarian_assignments as assignment
                  where assignment.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(entry_row::text, '|' order by entry_row.id)
                  from public.clinical_record_entries as entry_row
                  where entry_row.appointment_id = pg_temp.appt(p_n)), '')
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

-- A successful cancellation: CANCELLED state; exactly one CANCELLED Event from
-- p_from_state by the actor in p_context with p_reason; the authorization
-- ENDED as APPOINTMENT_CANCELLED at the Event time; and exactly one
-- APPOINTMENT_CANCELLED Communication per current Guardian (G1, G2) — none
-- for the former Guardian G3 or for any Clinic actor.
create function pg_temp.is_cancelled_by(
    p_n integer, p_user integer, p_context text, p_from_state text, p_reason text
)
returns boolean language sql as $$
    select pg_temp.state(p_n) = 'CANCELLED'
       and (select count(*) = 1 from public.appointment_lifecycle_events as event
            where event.appointment_id = pg_temp.appt(p_n) and event.to_state = 'CANCELLED')
       and (select count(*) = 1 from public.appointment_lifecycle_events as event
            where event.appointment_id = pg_temp.appt(p_n) and event.to_state = 'CANCELLED'
              and event.from_state = p_from_state and event.actor_context = p_context
              and event.actor_user_id = pg_temp.domain_user(p_user)
              and event.reason is not distinct from p_reason)
       and (select care_auth.lifecycle_state = 'ENDED'
                   and care_auth.ended_reason = 'APPOINTMENT_CANCELLED'
                   and care_auth.ended_at = event.effective_at
            from public.care_authorizations as care_auth
            join public.appointment_lifecycle_events as event
              on event.appointment_id = care_auth.appointment_id and event.to_state = 'CANCELLED'
            where care_auth.id = pg_temp.ca(p_n))
       and (select array_agg(communication.recipient_user_id order by communication.recipient_user_id)
            from public.transactional_communications as communication
            where communication.appointment_id = pg_temp.appt(p_n)
              and communication.communication_type = 'APPOINTMENT_CANCELLED')
           = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
$$;

create function pg_temp.is_clinic_cancelled_by(p_n integer, p_user integer, p_from_state text)
returns boolean language sql as $$
    select pg_temp.is_cancelled_by(p_n, p_user, 'CLINIC', p_from_state, 'Clinic closed that day')
$$;

-- ===========================================================================
-- 1. Contract (cases 1–2).
-- ===========================================================================

select pg_temp.assert_true(
    to_regprocedure('public.cancel_appointment(uuid, text, text)') is null
    and (select count(*) = 1 from pg_proc as proc
         where proc.proname = 'cancel_appointment'
           and proc.pronamespace = 'public'::regnamespace)
    and (select pg_get_function_arguments(proc.oid)
                    = 'p_appointment_id uuid, p_cancelling_context text, p_reason text DEFAULT NULL::text, p_expected_schedule_revision_sequence integer DEFAULT NULL::integer'
                and pg_get_function_result(proc.oid) = 'uuid'
                and proc.pronargdefaults = 2
                and proc.prosecdef
                and proc.provolatile = 'v'
                and proc.proconfig = array['search_path=""']
         from pg_proc as proc
         where proc.oid = 'public.cancel_appointment(uuid, text, text, integer)'::regprocedure)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.oid = 'public.cancel_appointment(uuid, text, text, integer)'::regprocedure
           and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.cancel_appointment(uuid, text, text, integer)', 'EXECUTE'),
    'Cases 1/2: only cancel_appointment(uuid, text, text, integer) exists — two defaults, SECURITY DEFINER, VOLATILE, empty search_path, original ACL'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c4a00000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current)        08 RECEPTIONIST @ A1 (Clinic)
--   02 Guardian G2 (current)        09 RECEPTIONIST @ A2 (Clinic)
--   03 former Guardian G3           10 VETERINARIAN only, assigned @ A1
--   04 OrgA OWNER                   11 Org RECEPTIONIST, Membership ended
--   05 OrgA ADMINISTRATOR (Org)     12 Org RECEPTIONIST, Grant ended
--   06 ADMINISTRATOR @ A1 (Clinic)  16 OWNER of the Entitlement-variant Orgs
--   07 OrgA RECEPTIONIST (Org)
-- Organizations: 0301 OrgA ACTIVE (A1 0401, A2 0402), 0304 PAST_DUE (0405),
-- 0306 no Subscription (0407). Every Clinic is Europe/Madrid, 30 minutes,
-- Available 08:00–20:00 every weekday. Every Appointment is Luna's (a01);
-- Appointment n has Care Authorization c<n>. FUTURE = 2035 (CET, +01:00),
-- PAST = 2026-06-01.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('c4a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c4a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('c4a00000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('c4a00000-0000-4000-8000-000000000304', 'Org Past Due'),
    ('c4a00000-0000-4000-8000-000000000306', 'Org Without Subscription');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    (pg_temp.clinic(1), 'c4a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), 'c4a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(5), 'c4a00000-0000-4000-8000-000000000304', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(7), 'c4a00000-0000-4000-8000-000000000306', true, 'Europe/Madrid', 30);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select clinic_id, weekday, '08:00', '20:00'
from unnest(array[pg_temp.clinic(1), pg_temp.clinic(2)]) as clinic_id, generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('c4a00000-0000-4000-8000-000000000504', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000505', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(5), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000506', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(6), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000507', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000508', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(8), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000509', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(9), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000510', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000511', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(11), '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4)),
    ('c4a00000-0000-4000-8000-000000000512', 'c4a00000-0000-4000-8000-000000000301', pg_temp.domain_user(12), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000514', 'c4a00000-0000-4000-8000-000000000304', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('c4a00000-0000-4000-8000-000000000516', 'c4a00000-0000-4000-8000-000000000306', pg_temp.domain_user(16), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('c4a00000-0000-4000-8000-000000000604', 'c4a00000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000605', 'c4a00000-0000-4000-8000-000000000505', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000606', 'c4a00000-0000-4000-8000-000000000506', 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000607', 'c4a00000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000608', 'c4a00000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000609', 'c4a00000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000610', 'c4a00000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000611', 'c4a00000-0000-4000-8000-000000000511', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c4a00000-0000-4000-8000-000000000612', 'c4a00000-0000-4000-8000-000000000512', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4), pg_temp.domain_user(4)),
    ('c4a00000-0000-4000-8000-000000000614', 'c4a00000-0000-4000-8000-000000000514', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('c4a00000-0000-4000-8000-000000000616', 'c4a00000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null);

insert into public.veterinarian_professional_profiles (id, user_id)
values ('c4a00000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start
) values (pg_temp.vca(), 'c4a00000-0000-4000-8000-000000000710',
          'c4a00000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z');

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('c4a00000-0000-4000-8000-000000000901', 'c4a00000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',   '2020-01-01Z', null, null, 'spec-apt-003-test', 'c4a00000-0000-4000-8000-000000000991'),
    ('c4a00000-0000-4000-8000-000000000904', 'c4a00000-0000-4000-8000-000000000304', '2020-01-01Z', 'PAST_DUE', '2020-01-01Z', null, null, 'spec-apt-003-test', 'c4a00000-0000-4000-8000-000000000994');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('c4a00000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null),
    ('c4a00000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z', null),
    ('c4a00000-0000-4000-8000-000000000a13', pg_temp.domain_user(3), pg_temp.luna(), '2020-01-01Z', '2021-01-01Z');

-- An Appointment requested on 2026-01-01 with revision 1 REQUESTED and an
-- ACTIVE Care Authorization; when CONFIRMED, revision 2 CONFIRMED and its
-- confirmation Event on 2026-02-01.
create function pg_temp.seed(p_n integer, p_clinic uuid, p_start timestamptz, p_state text)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), p_clinic, pg_temp.domain_user(1), 'Visit ' || p_n, p_state,
            '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
              pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) select pg_temp.ca(p_n), pg_temp.luna(), p_clinic, clinic.organization_id, 'c4a00000-0000-4000-8000-000000000a11',
             '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n), 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE'
      from public.clinics as clinic where clinic.id = p_clinic;
    if p_state = 'CONFIRMED' then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
        ) values (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
                  pg_temp.domain_user(8), null, '2026-02-01T00:00:00Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(8), 'CLINIC', null,
                  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
    end if;
end;
$$;

-- A later revision of the same context, as a reschedule produces.
create function pg_temp.seed_revision(
    p_n integer, p_sequence integer, p_context text, p_start timestamptz, p_end timestamptz, p_timezone text
)
returns void language sql as $$
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), p_sequence, p_context, p_start, p_end, p_timezone, pg_temp.domain_user(1), null,
              '2026-03-01T00:00:00Z'::timestamptz + make_interval(mins => p_sequence));
$$;

-- Contract and Guardian compatibility (1–2).
select pg_temp.seed(1, pg_temp.clinic(1), '2035-03-05T09:00Z', 'REQUESTED');
select pg_temp.seed(2, pg_temp.clinic(1), '2035-03-05T10:00Z', 'REQUESTED');
-- REQUESTED Clinic cancellation (3–7).
select pg_temp.seed(3, pg_temp.clinic(1), '2035-03-06T09:00Z', 'REQUESTED');
select pg_temp.seed(4, pg_temp.clinic(1), '2035-03-06T10:00Z', 'REQUESTED');  -- Guardian reschedules in-suite
select pg_temp.seed(5, pg_temp.clinic(1), '2035-03-06T12:00Z', 'REQUESTED');  -- same-start newer request
select pg_temp.seed_revision(5, 2, 'REQUESTED', '2035-03-06T12:00Z', '2035-03-06T12:45Z', 'Europe/Madrid');
select pg_temp.seed(6, pg_temp.clinic(1), '2026-06-01T10:00Z', 'REQUESTED');  -- logically expired
select pg_temp.seed(7, pg_temp.clinic(1), '2026-06-01T10:00Z', 'EXPIRED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(7), 'REQUESTED', 'EXPIRED', null, 'SYSTEM', null, '2026-06-01T10:00Z', '2026-06-01T10:05Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T10:00Z', ended_reason = 'APPOINTMENT_EXPIRED' where id = pg_temp.ca(7);
-- CONFIRMED Clinic cancellation (8–12).
select pg_temp.seed(8, pg_temp.clinic(1), '2035-03-07T09:00Z', 'CONFIRMED');
select pg_temp.seed(9, pg_temp.clinic(1), '2035-03-07T10:00Z', 'CONFIRMED');  -- accepted reschedule in-suite
select pg_temp.seed(10, pg_temp.clinic(1), '2035-03-07T14:00Z', 'CONFIRMED');
select pg_temp.seed_revision(10, 3, 'CONFIRMED', '2035-03-07T14:00Z', '2035-03-07T14:30Z', 'Europe/Madrid');  -- identical values
select pg_temp.seed(11, pg_temp.clinic(1), '2035-03-07T15:00Z', 'CONFIRMED');
select pg_temp.seed_revision(11, 3, 'CONFIRMED', '2035-03-07T15:00Z', '2035-03-07T15:45Z', 'Europe/Madrid');  -- end only
select pg_temp.seed(12, pg_temp.clinic(1), '2035-03-07T16:00Z', 'CONFIRMED');
select pg_temp.seed_revision(12, 3, 'CONFIRMED', '2035-03-07T16:00Z', '2035-03-07T16:30Z', 'Atlantic/Canary');  -- timezone only
-- Races and clinical documentation (13–16).
select pg_temp.seed(13, pg_temp.clinic(1), '2035-03-08T09:00Z', 'CONFIRMED');
select pg_temp.seed(14, pg_temp.clinic(1), '2026-06-01T10:00Z', 'CONFIRMED');
-- 15 is past so that completion (start reached, SPEC-APT-009 BR-7) can win first.
select pg_temp.seed(15, pg_temp.clinic(1), '2026-06-01T11:00Z', 'CONFIRMED');
select pg_temp.seed(16, pg_temp.clinic(1), '2035-03-08T11:00Z', 'CONFIRMED');
-- Authorization (20–26).
select pg_temp.seed(20, pg_temp.clinic(1), '2035-03-09T09:00Z', 'REQUESTED');
select pg_temp.seed(n, pg_temp.clinic(1), '2035-03-09T10:00Z'::timestamptz + make_interval(hours => n - 21), 'CONFIRMED')
from generate_series(21, 25) as n;
select pg_temp.seed(26, pg_temp.clinic(2), '2035-03-09T09:00Z', 'CONFIRMED');
-- No Entitlement gate (27–28).
select pg_temp.seed(27, pg_temp.clinic(5), '2035-03-10T09:00Z', 'CONFIRMED');
select pg_temp.seed(28, pg_temp.clinic(7), '2035-03-10T09:00Z', 'REQUESTED');

set local session_replication_role = origin;

-- ===========================================================================
-- 2. Invalid input, before any Appointment state (cases 3–5, 7).
-- ===========================================================================

select pg_temp.remember(2);
select pg_temp.act(8);
set local role authenticated;
-- 3: a Clinic call without the token, positionally and through the old arity.
select pg_temp.assert_error(format('select pg_temp.cancel(2, ''CLINIC'', ''Closed'', null)'), '22023', 'Expected schedule revision sequence must be a positive integer');
select pg_temp.assert_error(format('select public.cancel_appointment(%L, ''CLINIC'', ''Closed'')', pg_temp.appt(2)), '22023', 'Expected schedule revision sequence must be a positive integer');
-- 4: zero and negative tokens.
select pg_temp.assert_error('select pg_temp.cancel(2, ''CLINIC'', ''Closed'', 0)', '22023', 'Expected schedule revision sequence must be a positive integer');
select pg_temp.assert_error('select pg_temp.cancel(2, ''CLINIC'', ''Closed'', -1)', '22023', 'Expected schedule revision sequence must be a positive integer');
-- 5: missing or blank Clinic reason, even with the current token.
select pg_temp.assert_error('select pg_temp.cancel(2, ''CLINIC'', null, 1)', '22023', 'A meaningful reason is required for a Clinic cancellation');
select pg_temp.assert_error(format('select pg_temp.cancel(2, ''CLINIC'', %L, 1)', E'  \t\n '), '22023', 'A meaningful reason is required for a Clinic cancellation');
-- Structural validation precedes any Appointment lookup.
select pg_temp.assert_error('select public.cancel_appointment(''c4a00000-0000-4000-8000-0000000000ff'', ''CLINIC'', ''Closed'', 0)', '22023', 'Expected schedule revision sequence must be a positive integer');
select pg_temp.assert_error('select public.cancel_appointment(''c4a00000-0000-4000-8000-0000000000ff'', ''CLINIC'', '' '', 1)', '22023', 'A meaningful reason is required for a Clinic cancellation');
select pg_temp.assert_error('select public.cancel_appointment(''c4a00000-0000-4000-8000-0000000000ff'', ''CLINIC'', ''Closed'', 1)', '23503', 'Appointment does not exist');
reset role;

-- 7: a Guardian token is invalid input, before any lookup.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(2, ''GUARDIAN'', null, 1)', '22023', 'Guardian cancellation does not accept an expected schedule revision sequence');
select pg_temp.assert_error('select public.cancel_appointment(''c4a00000-0000-4000-8000-0000000000ff'', ''GUARDIAN'', null, 1)', '22023', 'Guardian cancellation does not accept an expected schedule revision sequence');
reset role;

select pg_temp.assert_true(pg_temp.unchanged(2), 'Cases 3/4/5/7: invalid Clinic and Guardian input changes nothing');

-- ===========================================================================
-- 3. Guardian compatibility (case 6).
-- ===========================================================================

select pg_temp.act(1);
set local role authenticated;
-- Exactly the mobile Guardian call shape: named arguments, no token.
select public.cancel_appointment(
    p_appointment_id => pg_temp.appt(1), p_cancelling_context => 'GUARDIAN', p_reason => null
);
select pg_temp.flush();
-- The positional three-argument Guardian call still resolves too.
select public.cancel_appointment(pg_temp.appt(2), 'GUARDIAN', '  Plans changed  ');
select pg_temp.flush();
reset role;

select pg_temp.assert_true(
    pg_temp.is_cancelled_by(1, 1, 'GUARDIAN', 'REQUESTED', null)
    and pg_temp.is_cancelled_by(2, 1, 'GUARDIAN', 'REQUESTED', 'Plans changed'),
    'Case 6: Guardian cancellation without a token behaves as before — optional, trimmed reason; GUARDIAN Event; authorization ended; current Guardians notified'
);

-- ===========================================================================
-- 4. REQUESTED Clinic cancellation (cases 8–14).
-- ===========================================================================

-- 8: the current requested revision.
set local role authenticated;
select pg_temp.clinic_cancel_as(8, 3, 1);
reset role;
select pg_temp.assert_true(pg_temp.is_clinic_cancelled_by(3, 8, 'REQUESTED'), 'Case 8: a future REQUESTED Appointment is cancelled with its current revision');

-- 9–11: a real Guardian requested-time reschedule supersedes the reviewed revision.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.reschedule_requested(4, '2035-03-06', '13:00');
reset role;
select pg_temp.assert_true(pg_temp.latest_sequence(4) = 2, 'Fixture: the Guardian reschedule established requested revision 2');

select pg_temp.remember(n) from unnest(array[4, 5]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(4, ''CLINIC'', ''Clinic closed that day'', 1)', 'P0001', 'Stale Appointment schedule revision for cancellation');
select pg_temp.assert_error('select pg_temp.cancel(5, ''CLINIC'', ''Clinic closed that day'', 1)', 'P0001', 'Stale Appointment schedule revision for cancellation');
reset role;

do $$
begin
    perform pg_temp.act(8);
    set local role authenticated;
    perform pg_temp.cancel(4, 'CLINIC', 'Clinic closed that day', 1);
    raise exception 'stale cancellation succeeded';
exception when others then
    reset role;
    if sqlstate <> 'P0001' or sqlerrm <> 'Stale Appointment schedule revision for cancellation' then
        raise exception 'Case 10: expected exactly P0001 "Stale Appointment schedule revision for cancellation", got % "%"', sqlstate, sqlerrm;
    end if;
end;
$$;

select pg_temp.assert_true(
    pg_temp.unchanged(4) and pg_temp.unchanged(5)
    and pg_temp.state(4) = 'REQUESTED' and pg_temp.state(5) = 'REQUESTED',
    'Cases 9/10/11: a superseded requested revision — also with the same start — is P0001 stale and writes nothing'
);

-- 12: re-read and cancel the current, still-pending request.
set local role authenticated;
select pg_temp.clinic_cancel_as(8, 4, 2);
select pg_temp.clinic_cancel_as(8, 5, 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_clinic_cancelled_by(4, 8, 'REQUESTED') and pg_temp.is_clinic_cancelled_by(5, 8, 'REQUESTED'),
    'Case 12: after re-reading, the current requested revision cancels'
);

-- 13: a logically expired request — current token: pending rule; old token: stale first.
select pg_temp.remember(n) from unnest(array[6, 7]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(6, ''CLINIC'', ''Too late'', 1)', '23514', 'A REQUESTED Appointment whose requested time has passed cannot be cancelled');
select pg_temp.assert_error('select pg_temp.cancel(6, ''CLINIC'', ''Too late'', 2)', 'P0001', 'Stale Appointment schedule revision for cancellation');
-- 14: a materialized EXPIRED Appointment is a lifecycle rejection, never stale.
select pg_temp.assert_error('select pg_temp.cancel(7, ''CLINIC'', ''Too late'', 1)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
select pg_temp.assert_error('select pg_temp.cancel(7, ''CLINIC'', ''Too late'', 9)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(6) and pg_temp.unchanged(7)
    and (select lifecycle_state = 'ACTIVE' from public.care_authorizations where id = pg_temp.ca(6)),
    'Cases 13/14: a lapsed request and an EXPIRED Appointment are rejected with zero writes'
);

-- ===========================================================================
-- 5. CONFIRMED Clinic cancellation (cases 15–20).
-- ===========================================================================

-- 15: the current confirmed revision.
set local role authenticated;
select pg_temp.clinic_cancel_as(8, 8, 2);
reset role;
select pg_temp.assert_true(pg_temp.is_clinic_cancelled_by(8, 8, 'CONFIRMED'), 'Case 15: a future CONFIRMED Appointment is cancelled with its current revision');

-- 16: a real Clinic proposal accepted by a Guardian supersedes confirmed revision 2.
set local role authenticated;
select pg_temp.propose_and_accept(9, '2035-03-07', '13:00', 2);
reset role;
select pg_temp.assert_true(
    pg_temp.latest_sequence(9) = 3
    and (select revision_context = 'CONFIRMED' and source_proposal_id is not null
         from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(9) and revision_sequence = 3),
    'Fixture: the accepted reschedule established confirmed revision 3'
);

select pg_temp.remember(n) from unnest(array[9, 10, 11, 12]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(9, ''CLINIC'', ''Clinic closed that day'', 2)', 'P0001', 'Stale Appointment schedule revision for cancellation');
-- 17/18/19: the same start with identical values, end only, or timezone only.
select pg_temp.assert_error('select pg_temp.cancel(10, ''CLINIC'', ''Clinic closed that day'', 2)', 'P0001', 'Stale Appointment schedule revision for cancellation');
select pg_temp.assert_error('select pg_temp.cancel(11, ''CLINIC'', ''Clinic closed that day'', 2)', 'P0001', 'Stale Appointment schedule revision for cancellation');
select pg_temp.assert_error('select pg_temp.cancel(12, ''CLINIC'', ''Clinic closed that day'', 2)', 'P0001', 'Stale Appointment schedule revision for cancellation');
-- A requested revision sequence never matches a CONFIRMED Appointment.
select pg_temp.assert_error('select pg_temp.cancel(9, ''CLINIC'', ''Clinic closed that day'', 1)', 'P0001', 'Stale Appointment schedule revision for cancellation');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(9) and pg_temp.unchanged(10) and pg_temp.unchanged(11) and pg_temp.unchanged(12),
    'Cases 16–19: a superseded confirmed revision — accepted reschedule, identical values, end-only, timezone-only — is stale with zero writes, including the accepted Proposal'
);

-- 20: re-read and cancel the current confirmed revision.
set local role authenticated;
select pg_temp.clinic_cancel_as(8, n, 3) from generate_series(9, 12) as n;
reset role;
select pg_temp.assert_true(
    (select bool_and(pg_temp.is_clinic_cancelled_by(n, 8, 'CONFIRMED')) from generate_series(9, 12) as n),
    'Case 20: after re-reading, the current confirmed revision cancels'
);

-- ===========================================================================
-- 6. Races and clinical documentation (cases 21–25).
-- ===========================================================================

-- 21: a Guardian cancels first.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.cancel(13, 'GUARDIAN', null, null);
reset role;
-- 22: NO_SHOW wins first (a past CONFIRMED Appointment, which a Clinic may
-- still cancel after its start — SPEC-APT-003 BR-31 closes only Guardian
-- cancellation; see section 10).
select pg_temp.act(8);
set local role authenticated;
select pg_temp.no_show(14, 2);
reset role;
-- 23: Complete wins first; 24: a Clinical Record Entry exists.
select pg_temp.act(10);
set local role authenticated;
select pg_temp.clinical_entry(15);
select pg_temp.clinical_entry(16);
reset role;
select pg_temp.act(8);
set local role authenticated;
-- The existing Entry does not block completion (SPEC-APT-009 BR-12).
select pg_temp.complete(15);
reset role;

select pg_temp.remember(n) from generate_series(13, 16) as n;
select pg_temp.act(7);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.cancel(%s, ''CLINIC'', ''Clinic closed that day'', 2)', n), '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled')
from generate_series(13, 15) as n;
select pg_temp.assert_error('select pg_temp.cancel(16, ''CLINIC'', ''Clinic closed that day'', 2)', '23514', 'Appointment with clinical documentation cannot be cancelled');
reset role;

select pg_temp.assert_true(
    (select bool_and(pg_temp.unchanged(n)) from generate_series(13, 16) as n)
    and pg_temp.state(13) = 'CANCELLED' and pg_temp.state(14) = 'NO_SHOW'
    and pg_temp.state(15) = 'COMPLETED' and pg_temp.state(16) = 'CONFIRMED'
    and pg_temp.is_cancelled_by(13, 1, 'GUARDIAN', 'CONFIRMED', null)
    and (select lifecycle_state = 'ACTIVE' from public.care_authorizations where id = pg_temp.ca(16)),
    'Cases 21–25: a Guardian cancellation, NO_SHOW, or completion winning first leaves a lifecycle rejection; clinical documentation blocks cancellation even with the current token; no failed attempt writes anything'
);

select pg_temp.assert_true(
    not exists (select 1 from public.transactional_communications as communication
                where communication.communication_type = 'APPOINTMENT_CANCELLED'
                  and communication.appointment_id in (pg_temp.appt(6), pg_temp.appt(7), pg_temp.appt(14),
                                                       pg_temp.appt(15), pg_temp.appt(16))),
    'Case 25: rejected cancellations produce no APPOINTMENT_CANCELLED Communication'
);

-- ===========================================================================
-- 7. Authorization (cases 31–34).
-- ===========================================================================

set local role authenticated;
select pg_temp.clinic_cancel_as(4, 20, 1);
select pg_temp.clinic_cancel_as(5, 21, 2);
select pg_temp.clinic_cancel_as(6, 22, 2);
select pg_temp.clinic_cancel_as(7, 23, 2);
select pg_temp.clinic_cancel_as(8, 24, 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_clinic_cancelled_by(20, 4, 'REQUESTED') and pg_temp.is_clinic_cancelled_by(21, 5, 'CONFIRMED')
    and pg_temp.is_clinic_cancelled_by(22, 6, 'CONFIRMED') and pg_temp.is_clinic_cancelled_by(23, 7, 'CONFIRMED')
    and pg_temp.is_clinic_cancelled_by(24, 8, 'CONFIRMED'),
    'Case 31: OWNER, Org ADMINISTRATOR, Clinic ADMINISTRATOR, Org RECEPTIONIST, and Clinic RECEPTIONIST cancel'
);

select pg_temp.remember(n) from unnest(array[25, 26]) as n;
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.clinic_cancel_as(%s, 25, 2)', u), '42501', 'Applicable Clinic-management capability is required')
from unnest(array[10, 9, 11, 12, 1, 3]) as u;
select pg_temp.assert_error('select pg_temp.clinic_cancel_as(6, 26, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.clinic_cancel_as(8, 26, 2)', '42501', 'Applicable Clinic-management capability is required');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(25) and pg_temp.unchanged(26),
    'Cases 32–34: VETERINARIAN-only, other-Clinic, ended Membership, ended Grant, and Guardians acting as CLINIC are denied with zero writes'
);

set local role authenticated;
select pg_temp.clinic_cancel_as(9, 26, 2);
reset role;
select pg_temp.assert_true(pg_temp.is_clinic_cancelled_by(26, 9, 'CONFIRMED'), 'Case 33: a Clinic RECEPTIONIST cancels at its own Clinic');

-- ===========================================================================
-- 8. No Entitlement gate (case 35).
-- ===========================================================================

select pg_temp.assert_true(
    public.organization_has_professional_entitlement('c4a00000-0000-4000-8000-000000000301', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c4a00000-0000-4000-8000-000000000304', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c4a00000-0000-4000-8000-000000000306', 'APPOINTMENT_MANAGEMENT'),
    'Fixture: only OrgA holds normal professional Entitlement'
);

set local role authenticated;
select pg_temp.clinic_cancel_as(16, 27, 2);
select pg_temp.clinic_cancel_as(16, 28, 1);
reset role;
select pg_temp.assert_true(
    pg_temp.is_clinic_cancelled_by(27, 16, 'CONFIRMED') and pg_temp.is_clinic_cancelled_by(28, 16, 'REQUESTED'),
    'Case 35: stale-safe Clinic cancellation still resolves existing obligations under PAST_DUE and with no Subscription'
);

-- ===========================================================================
-- 9. Communications (cases 26–30) across every successful cancellation.
-- ===========================================================================

select pg_temp.assert_true(
    (select count(*) = 2 * 19 from public.transactional_communications
     where communication_type = 'APPOINTMENT_CANCELLED')
    and not exists (select 1 from public.transactional_communications
                    where communication_type = 'APPOINTMENT_CANCELLED'
                      and recipient_user_id not in (pg_temp.domain_user(1), pg_temp.domain_user(2)))
    and (select count(*) = 19 from public.appointment_lifecycle_events where to_state = 'CANCELLED'),
    'Cases 26–30: each of the 19 cancellations has exactly one CANCELLED Event and one APPOINTMENT_CANCELLED Communication per current Guardian, none for the former Guardian or any Clinic actor'
);

-- ===========================================================================
-- 10. Guardian cancellation closes at the latest confirmed start (BR-31),
--     migration 20261021090000_guardian_confirmed_cancellation_cutoff.sql.
--
-- Backend time cannot be frozen, so starts are seeded relative to it: "well
-- ahead" (+1 day), "just before" (+10 minutes, still ahead when evaluated),
-- and "reached" — clock_timestamp() at seeding, which is strictly later than
-- the transaction start and earlier than any later evaluation, so a cutoff
-- read from transaction time would wrongly allow it. The exact boundary
-- (start = reference instant) is pinned on the predicate the operation uses,
-- with explicit instants. PAST = 2026-06-01, FUTURE = 2035.
-- ===========================================================================

select pg_temp.assert_true(
    not has_function_privilege('authenticated', 'public.appointment_latest_confirmed_start_at(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.appointment_latest_confirmed_start_at(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.appointment_latest_confirmed_start_at(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.appointment_confirmed_start_is_in_future(uuid, timestamptz)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.appointment_confirmed_start_is_in_future(uuid, timestamptz)', 'EXECUTE')
    and not has_function_privilege('public', 'public.appointment_confirmed_start_is_in_future(uuid, timestamptz)', 'EXECUTE'),
    'Case 40: the cutoff helpers are internal — not executable by client roles'
);

create temporary table cutoff_start (n integer primary key, start_at timestamptz not null) on commit drop;

set local session_replication_role = replica;
-- 41 well ahead; 42 just before; 43 reached; 44 past, with a stored PENDING
-- Clinic proposal for a future time.
insert into cutoff_start values
    (41, clock_timestamp() + interval '1 day'),
    (42, clock_timestamp() + interval '10 minutes'),
    (43, clock_timestamp());
select pg_temp.seed(n, pg_temp.clinic(1), start_at, 'CONFIRMED') from cutoff_start;
select pg_temp.seed(44, pg_temp.clinic(1), '2026-06-01T09:00Z', 'CONFIRMED');
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
) select 'c4a00000-0000-4000-8000-000000000d44', pg_temp.appt(44), revision.id, 'CONFIRMED',
         '2035-04-01T09:00Z', '2035-04-01T09:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(8),
         'Clinic needs to move it', '2026-05-01T00:00Z'
  from public.appointment_schedule_revisions as revision
  where revision.appointment_id = pg_temp.appt(44) and revision.revision_sequence = 2;
-- 45: earlier confirmed start passed, latest confirmed revision (as an
-- accepted reschedule leaves) in the future; 46: the reverse.
select pg_temp.seed(45, pg_temp.clinic(1), '2026-06-01T10:00Z', 'CONFIRMED');
select pg_temp.seed_revision(45, 3, 'CONFIRMED', '2035-04-02T09:00Z', '2035-04-02T09:30Z', 'Europe/Madrid');
select pg_temp.seed(46, pg_temp.clinic(1), '2035-04-03T09:00Z', 'CONFIRMED');
select pg_temp.seed_revision(46, 3, 'CONFIRMED', '2026-06-01T11:00Z', '2026-06-01T11:30Z', 'Europe/Madrid');
-- 47: Clinic cancellation after the start; 48: lapsed REQUESTED;
-- 49/50: clinical documentation before / after the start.
select pg_temp.seed(47, pg_temp.clinic(1), '2026-06-01T12:00Z', 'CONFIRMED');
select pg_temp.seed(48, pg_temp.clinic(1), '2026-06-01T13:00Z', 'REQUESTED');
select pg_temp.seed(49, pg_temp.clinic(1), '2035-04-04T09:00Z', 'CONFIRMED');
select pg_temp.seed(50, pg_temp.clinic(1), '2026-06-01T14:00Z', 'CONFIRMED');
-- 51–56: races with completion, no-show, and Clinic cancellation.
select pg_temp.seed(n, pg_temp.clinic(1), '2026-06-02T09:00Z'::timestamptz + make_interval(hours => n - 51), 'CONFIRMED')
from unnest(array[51, 52, 53, 54, 55]) as n;
select pg_temp.seed(56, pg_temp.clinic(1), '2035-04-05T09:00Z', 'CONFIRMED');
set local session_replication_role = origin;

-- 41: exact predicate boundary on the seeded starts — strictly later than the
-- reference instant is in the future; equal is not.
select pg_temp.assert_true(
    (select bool_and(
                public.appointment_confirmed_start_is_in_future(pg_temp.appt(n), start_at - interval '1 microsecond')
                and not public.appointment_confirmed_start_is_in_future(pg_temp.appt(n), start_at)
                and not public.appointment_confirmed_start_is_in_future(pg_temp.appt(n), start_at + interval '1 microsecond'))
     from cutoff_start)
    and public.appointment_latest_confirmed_start_at(pg_temp.appt(45)) = '2035-04-02T09:00Z'
    and public.appointment_latest_confirmed_start_at(pg_temp.appt(46)) = '2026-06-01T11:00Z'
    and not public.appointment_confirmed_start_is_in_future(pg_temp.appt(48), '2020-01-01Z'),
    'Case 41: start > reference is in the future; start = reference and start < reference are not; the latest confirmed revision is used; a REQUESTED Appointment is never a confirmed future start'
);

-- 42/43: well ahead and just before the start — the Guardian cancels, with the
-- unchanged effects (CANCELLED, GUARDIAN Event, authorization ended,
-- APPOINTMENT_CANCELLED for each current Guardian).
select pg_temp.act(1);
set local role authenticated;
select pg_temp.cancel(41, 'GUARDIAN', null, null);
select pg_temp.cancel(42, 'GUARDIAN', 'Plans changed', null);
reset role;
select pg_temp.assert_true(
    pg_temp.is_cancelled_by(41, 1, 'GUARDIAN', 'CONFIRMED', null)
    and pg_temp.is_cancelled_by(42, 1, 'GUARDIAN', 'CONFIRMED', 'Plans changed'),
    'Cases 42/43: a Guardian cancels a CONFIRMED Appointment whose start is still ahead, with the existing effects'
);

-- 44/45/46: reached, past, and past with a pending proposal for a future time
-- — rejected with the exact contract and zero writes.
select pg_temp.remember(n) from unnest(array[43, 44]) as n;
do $$
begin
    perform pg_temp.act(1);
    set local role authenticated;
    perform pg_temp.cancel(43, 'GUARDIAN', null, null);
    raise exception 'post-start Guardian cancellation succeeded';
exception when others then
    reset role;
    if sqlstate <> '23514'
       or sqlerrm <> 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached' then
        raise exception 'Case 44: expected exactly 23514 "A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached", got % "%"', sqlstate, sqlerrm;
    end if;
end;
$$;
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(44, ''GUARDIAN'', ''Could not come'', null)', '23514', 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(43) and pg_temp.unchanged(44)
    and pg_temp.state(43) = 'CONFIRMED' and pg_temp.state(44) = 'CONFIRMED'
    and (select bool_and(lifecycle_state = 'ACTIVE') from public.care_authorizations
         where id in (pg_temp.ca(43), pg_temp.ca(44)))
    and (select state = 'PENDING' from public.appointment_reschedule_proposals
         where id = 'c4a00000-0000-4000-8000-000000000d44')
    and not exists (select 1 from public.appointment_lifecycle_events
                    where appointment_id in (pg_temp.appt(43), pg_temp.appt(44)) and to_state = 'CANCELLED')
    and not exists (select 1 from public.transactional_communications
                    where appointment_id in (pg_temp.appt(43), pg_temp.appt(44))),
    'Cases 44–46: a Guardian cancellation at or after the confirmed start is rejected with zero writes — state, Events, revisions, authorization, proposal, assignments, Communications unchanged — and a pending proposal for a future time does not move the cutoff'
);

-- 47/48: the latest confirmed revision decides, never an earlier one.
select pg_temp.remember(46);
select pg_temp.act(1);
set local role authenticated;
select pg_temp.cancel(45, 'GUARDIAN', null, null);
select pg_temp.assert_error('select pg_temp.cancel(46, ''GUARDIAN'', null, null)', '23514', 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached');
reset role;
select pg_temp.assert_true(
    pg_temp.is_cancelled_by(45, 1, 'GUARDIAN', 'CONFIRMED', null)
    and pg_temp.unchanged(46) and pg_temp.state(46) = 'CONFIRMED',
    'Cases 47/48: an earlier passed start with a future latest confirmed start cancels; an earlier future start with a reached latest confirmed start is rejected'
);

-- 49: Clinic cancellation after the start is unchanged.
select pg_temp.act(8);
set local role authenticated;
select pg_temp.clinic_cancel_as(8, 47, 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_clinic_cancelled_by(47, 8, 'CONFIRMED'),
    'Case 49: a Clinic still cancels a CONFIRMED Appointment after its start, with the existing effects'
);

-- 50: a lapsed REQUESTED keeps its own rule and message.
select pg_temp.remember(48);
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(48, ''GUARDIAN'', null, null)', '23514', 'A REQUESTED Appointment whose requested time has passed cannot be cancelled');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(48), 'Case 50: REQUESTED Guardian cancellation keeps the pending-request rule (BR-23), unchanged');

-- 51/52: clinical documentation — before the start the documentation prohibition
-- rejects; from the start the cutoff (evaluated first) rejects.
select pg_temp.act(10);
set local role authenticated;
select pg_temp.clinical_entry(49);
select pg_temp.clinical_entry(50);
reset role;
select pg_temp.remember(n) from unnest(array[49, 50]) as n;
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(49, ''GUARDIAN'', null, null)', '23514', 'Appointment with clinical documentation cannot be cancelled');
select pg_temp.assert_error('select pg_temp.cancel(50, ''GUARDIAN'', null, null)', '23514', 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(49) and pg_temp.unchanged(50),
    'Cases 51/52: the clinical documentation rule is unchanged before the start; from the start the cutoff rejects first; both write nothing'
);

-- 53–58: races, serialized by the Appointment lock (single session; the order
-- of arrival is the order of the calls).
-- 53: completion first → the Guardian gets the lifecycle rejection.
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(51);
reset role;
-- 54: the Guardian first, after the start → cutoff; the Clinic then completes.
select pg_temp.remember(52);
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(51, ''GUARDIAN'', null, null)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
select pg_temp.assert_error('select pg_temp.cancel(52, ''GUARDIAN'', null, null)', '23514', 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(52), 'Case 54: the rejected Guardian attempt leaves the Appointment for the Clinic');
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(52);
-- 55: NO_SHOW first → lifecycle rejection; 56: the Guardian first → cutoff,
-- then NO_SHOW.
select pg_temp.no_show(53, 2);
reset role;
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(53, ''GUARDIAN'', null, null)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
select pg_temp.assert_error('select pg_temp.cancel(54, ''GUARDIAN'', null, null)', '23514', 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached');
reset role;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.no_show(54, 2);
-- 57: Clinic cancellation first after the start → lifecycle rejection.
select pg_temp.clinic_cancel_as(8, 55, 2);
reset role;
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.cancel(55, ''GUARDIAN'', null, null)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
-- 58: before the start the Guardian validly wins; completion, no-show, and
-- Clinic cancellation that arrive afterwards are lifecycle rejections.
select pg_temp.cancel(56, 'GUARDIAN', null, null);
reset role;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error('select pg_temp.complete(56)', '23514', null);
select pg_temp.assert_error('select pg_temp.no_show(56, 2)', '23514', null);
select pg_temp.assert_error('select pg_temp.cancel(56, ''CLINIC'', ''Clinic closed that day'', 2)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
reset role;

select pg_temp.assert_true(
    pg_temp.state(51) = 'COMPLETED' and pg_temp.state(52) = 'COMPLETED'
    and pg_temp.state(53) = 'NO_SHOW' and pg_temp.state(54) = 'NO_SHOW'
    and pg_temp.is_clinic_cancelled_by(55, 8, 'CONFIRMED')
    and pg_temp.is_cancelled_by(56, 1, 'GUARDIAN', 'CONFIRMED', null)
    and (select count(*) = 1 from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(56) and to_state = 'CANCELLED'),
    'Cases 53–58: after the start a Guardian cancellation never wins — completion, no-show, or Clinic cancellation does; before the start it can win, and later Clinic resolutions are lifecycle rejections'
);

-- 59: Communications — APPOINTMENT_CANCELLED only for the successful
-- cancellations of this section, none for any rejected attempt.
select pg_temp.assert_true(
    (select count(*) = 2 * 6 from public.transactional_communications as communication
     where communication.communication_type = 'APPOINTMENT_CANCELLED'
       and communication.appointment_id in (pg_temp.appt(41), pg_temp.appt(42), pg_temp.appt(45),
                                            pg_temp.appt(47), pg_temp.appt(55), pg_temp.appt(56)))
    and not exists (select 1 from public.transactional_communications as communication
                    where communication.communication_type = 'APPOINTMENT_CANCELLED'
                      and communication.appointment_id in (pg_temp.appt(43), pg_temp.appt(44), pg_temp.appt(46),
                                                           pg_temp.appt(48), pg_temp.appt(49), pg_temp.appt(50),
                                                           pg_temp.appt(51), pg_temp.appt(52), pg_temp.appt(53),
                                                           pg_temp.appt(54))),
    'Case 59: successful cancellations notify each current Guardian; rejected post-start Guardian attempts notify no one'
);

rollback;

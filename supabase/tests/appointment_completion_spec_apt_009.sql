-- Regression suite for SPEC-APT-009 — Complete Appointment (lightweight,
-- stale-safe completion), migration
-- 20261011090000_lightweight_appointment_completion.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables, to call the
-- internal deferred coherence assertions directly, and to switch between
-- impersonated Users.
--
-- Every behavioral call goes through the real trusted operations. Helper
-- wrappers fire every pending deferred trigger at the end of each call (SET
-- CONSTRAINTS ALL IMMEDIATE, then back to DEFERRED), so deferred lifecycle,
-- provenance, Care Authorization, and clinical documentation coherence run inside
-- the same subtransaction.
--
-- Time boundary: the database clock cannot be frozen, so "exactly at the
-- start" is exercised with a start equal to the transaction start instant
-- (`now()`), which the call necessarily reaches.
--
-- Races are serialized in one session (whichever operation runs first wins),
-- as in the other Appointment lifecycle suites; they are not concurrent
-- sessions.
--
-- Clinical documentation after completion (SPEC-MED-010 BR-3) is exercised
-- here only as far as completion is concerned: neither blocks the other.
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
    select ('c0a90000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('c0a90000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.evt(p_n integer) returns uuid language sql immutable as $$
    select ('c0a90000-0000-4000-8000-000000000e' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('c0a90000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'c0a90000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('c0a90000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'c0a90000-0000-4000-8000-000000000a01'::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

create function pg_temp.complete(p_appointment uuid, p_sequence integer)
returns uuid language plpgsql as $$
declare completed uuid;
begin
    completed := public.complete_appointment(p_appointment, p_sequence);
    perform pg_temp.flush();
    return completed;
end;
$$;

create function pg_temp.complete_as(p_user integer, p_n integer, p_sequence integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform pg_temp.complete(pg_temp.appt(p_n), p_sequence);
end;
$$;

create function pg_temp.no_show(p_n integer)
returns void language plpgsql as $$
begin
    perform public.mark_appointment_no_show(pg_temp.appt(p_n), 2);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.cancel(p_n integer)
returns void language plpgsql as $$
begin
    perform public.cancel_appointment(pg_temp.appt(p_n), 'CLINIC', 'Clinic closed', 2);
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
    created := pg_temp.record_entry(pg_temp.appt(p_n), 'c0a90000-0000-4000-8000-000000000810'::uuid);
    perform pg_temp.flush();
    return created;
end;
$$;

create function pg_temp.state(p_n integer) returns text language sql as $$
    select lifecycle_state from public.appointments where id = pg_temp.appt(p_n)
$$;

-- Every persisted fact a completion could touch for one Appointment.
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
        || '#' || coalesce((select string_agg(proposal::text, '|' order by proposal.id)
                  from public.appointment_reschedule_proposals as proposal
                  where proposal.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(assignment::text, '|' order by assignment.id)
                  from public.appointment_veterinarian_assignments as assignment
                  where assignment.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(entry_row::text, '|' order by entry_row.id)
                  from public.clinical_record_entries as entry_row
                  where entry_row.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication
                  where communication.appointment_id = pg_temp.appt(p_n)), '')
    )
$$;

-- Veterinarian Assignment and Clinical Record Entry facts only: what completion
-- must never touch. The Care Authorization is ended by completion since
-- 20261114090000 (SPEC-MED-010 BR-16) and is checked by ended_by_completion.
create function pg_temp.untouchable(p_n integer)
returns text language sql as $$
    select md5(
        '#' || coalesce((select string_agg(assignment::text, '|' order by assignment.id)
                  from public.appointment_veterinarian_assignments as assignment
                  where assignment.appointment_id = pg_temp.appt(p_n)), '')
        || '#' || coalesce((select string_agg(entry_row::text, '|' order by entry_row.id)
                  from public.clinical_record_entries as entry_row
                  where entry_row.appointment_id = pg_temp.appt(p_n)), '')
    )
$$;

-- SPEC-MED-010 BR-16: the authorization is ENDED with APPOINTMENT_COMPLETED
-- exactly at the completion Event's effective time; nothing else about it moves.
create function pg_temp.ended_by_completion(p_n integer)
returns boolean language sql as $$
    select care_auth.lifecycle_state = 'ENDED'
       and care_auth.ended_reason = 'APPOINTMENT_COMPLETED'
       and care_auth.ended_at = (select event.effective_at from public.appointment_lifecycle_events as event
                                 where event.appointment_id = pg_temp.appt(p_n) and event.to_state = 'COMPLETED')
       and care_auth.revoked_at is null and care_auth.revoking_user_id is null
       and care_auth.revocation_reason is null
       and care_auth.purpose = 'APPOINTMENT_CARE' and care_auth.appointment_id = pg_temp.appt(p_n)
       and (select count(*) = 1 from public.care_authorizations as linked
            where linked.appointment_id = pg_temp.appt(p_n))
    from public.care_authorizations as care_auth
    where care_auth.id = pg_temp.ca(p_n)
$$;

create temporary table remembered (n integer primary key, fingerprint text not null, untouchable text not null) on commit drop;

create function pg_temp.remember(p_n integer) returns void language sql as $$
    insert into remembered values (p_n, pg_temp.fingerprint(p_n), pg_temp.untouchable(p_n))
    on conflict (n) do update set fingerprint = excluded.fingerprint, untouchable = excluded.untouchable
$$;

create function pg_temp.unchanged(p_n integer) returns boolean language sql as $$
    select pg_temp.fingerprint(p_n) = fingerprint from remembered where n = p_n
$$;

create function pg_temp.untouched(p_n integer) returns boolean language sql as $$
    select pg_temp.untouchable(p_n) = untouchable from remembered where n = p_n
$$;

-- A successful completion: COMPLETED state; exactly one CONFIRMED -> COMPLETED
-- Event by the actor, Clinic context, no reason, effective = recorded;
-- exactly one APPOINTMENT_COMPLETED Communication per
-- current Guardian (G1, G2), each originating from that Event.
create function pg_temp.is_completed_by(p_n integer, p_user integer)
returns boolean language sql as $$
    select pg_temp.state(p_n) = 'COMPLETED'
       and (select count(*) = 1 from public.appointment_lifecycle_events as event
            where event.appointment_id = pg_temp.appt(p_n) and event.to_state = 'COMPLETED')
       and (select count(*) = 1 from public.appointment_lifecycle_events as event
            where event.appointment_id = pg_temp.appt(p_n) and event.to_state = 'COMPLETED'
              and event.from_state = 'CONFIRMED' and event.actor_context = 'CLINIC'
              and event.actor_user_id = pg_temp.domain_user(p_user)
              and event.reason is null
              and event.effective_at = event.recorded_at)
       and (select array_agg(communication.recipient_user_id order by communication.recipient_user_id)
            from public.transactional_communications as communication
            join public.appointment_lifecycle_events as event
              on event.id = communication.appointment_lifecycle_event_id
            where communication.appointment_id = pg_temp.appt(p_n)
              and communication.communication_type = 'APPOINTMENT_COMPLETED'
              and event.to_state = 'COMPLETED')
           = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
       and (select count(*) = 2 from public.transactional_communications as communication
            where communication.appointment_id = pg_temp.appt(p_n)
              and communication.communication_type = 'APPOINTMENT_COMPLETED')
$$;

-- ===========================================================================
-- 1. Contract (cases 1–3).
-- ===========================================================================

select pg_temp.assert_true(
    to_regprocedure('public.complete_appointment(uuid, uuid)') is null
    and (select count(*) = 1 from pg_proc as proc
         where proc.proname = 'complete_appointment'
           and proc.pronamespace = 'public'::regnamespace)
    and (select pg_get_function_arguments(proc.oid) = 'p_appointment_id uuid, p_expected_confirmed_revision_sequence integer'
                and pg_get_function_result(proc.oid) = 'uuid'
                and proc.pronargdefaults = 0
                and proc.prosecdef
                and proc.provolatile = 'v'
                and proc.proconfig = array['search_path=""']
         from pg_proc as proc
         where proc.oid = 'public.complete_appointment(uuid, integer)'::regprocedure)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.oid = 'public.complete_appointment(uuid, integer)'::regprocedure
           and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.complete_appointment(uuid, integer)', 'EXECUTE'),
    'Cases 1/2: only complete_appointment(uuid, integer) exists — no default, SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only ACL; the Encounter-evidence form is gone'
);

select pg_temp.assert_true(
    to_regclass('public.clinical_encounters') is null
    and not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'appointment_lifecycle_events'
                      and column_name = 'clinical_encounter_id')
    and not exists (select 1 from pg_trigger as trigger_row
                    where trigger_row.tgrelid = 'public.appointment_lifecycle_events'::regclass
                      and trigger_row.tgname = 'appointment_lifecycle_events_no_new_encounter_reference')
    and to_regprocedure('public.enforce_appointment_lifecycle_event_no_new_encounter_reference()') is null,
    'Case 3: completion carries no clinical evidence — Clinical Encounters and the Lifecycle Event Encounter reference no longer exist (ADR-011)'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c0a90000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current)        08 RECEPTIONIST @ A1 (Clinic)
--   02 Guardian G2 (current)        09 RECEPTIONIST @ A2 (Clinic)
--   03 former Guardian G3           10 VETERINARIAN, Clinic Assignment @ A1
--   04 OrgA OWNER                   11 Org RECEPTIONIST, Membership ended
--   05 OrgA ADMINISTRATOR (Org)     12 Org RECEPTIONIST, Grant ended
--   06 ADMINISTRATOR @ A1 (Clinic)  16 OWNER of the Entitlement-variant Orgs
--   07 OrgA RECEPTIONIST (Org)
-- Organizations: 0301 OrgA ACTIVE (A1 0401, A2 0402), 0303 PENDING (0404),
-- 0304 PAST_DUE (0405), 0305 EXPIRED (0406), 0306 no Subscription (0407).
-- Every Appointment is Luna's (a01); Appointment n has Care Authorization c<n>.
-- PAST = 2026-06-01T10:00Z–10:30Z; FUTURE = 2035-03-06T09:00Z–09:30Z.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('c0a90000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('c0a90000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('c0a90000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('c0a90000-0000-4000-8000-000000000303', 'Org Pending'),
    ('c0a90000-0000-4000-8000-000000000304', 'Org Past Due'),
    ('c0a90000-0000-4000-8000-000000000305', 'Org Expired'),
    ('c0a90000-0000-4000-8000-000000000306', 'Org Without Subscription');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    (pg_temp.clinic(1), 'c0a90000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), 'c0a90000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(4), 'c0a90000-0000-4000-8000-000000000303', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(5), 'c0a90000-0000-4000-8000-000000000304', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(6), 'c0a90000-0000-4000-8000-000000000305', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(7), 'c0a90000-0000-4000-8000-000000000306', true, 'Europe/Madrid', 30);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('c0a90000-0000-4000-8000-000000000504', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000505', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(5), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000506', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(6), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000507', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000508', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(8), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000509', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(9), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000510', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000511', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(11), '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4)),
    ('c0a90000-0000-4000-8000-000000000512', 'c0a90000-0000-4000-8000-000000000301', pg_temp.domain_user(12), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000513', 'c0a90000-0000-4000-8000-000000000303', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000514', 'c0a90000-0000-4000-8000-000000000304', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000515', 'c0a90000-0000-4000-8000-000000000305', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('c0a90000-0000-4000-8000-000000000516', 'c0a90000-0000-4000-8000-000000000306', pg_temp.domain_user(16), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('c0a90000-0000-4000-8000-000000000604', 'c0a90000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000605', 'c0a90000-0000-4000-8000-000000000505', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000606', 'c0a90000-0000-4000-8000-000000000506', 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000607', 'c0a90000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000608', 'c0a90000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000609', 'c0a90000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000610', 'c0a90000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000611', 'c0a90000-0000-4000-8000-000000000511', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('c0a90000-0000-4000-8000-000000000612', 'c0a90000-0000-4000-8000-000000000512', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4), pg_temp.domain_user(4)),
    ('c0a90000-0000-4000-8000-000000000613', 'c0a90000-0000-4000-8000-000000000513', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('c0a90000-0000-4000-8000-000000000614', 'c0a90000-0000-4000-8000-000000000514', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('c0a90000-0000-4000-8000-000000000615', 'c0a90000-0000-4000-8000-000000000515', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('c0a90000-0000-4000-8000-000000000616', 'c0a90000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null);

insert into public.veterinarian_professional_profiles (id, user_id)
values ('c0a90000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start
) values ('c0a90000-0000-4000-8000-000000000810', 'c0a90000-0000-4000-8000-000000000710',
          'c0a90000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z');

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('c0a90000-0000-4000-8000-000000000901', 'c0a90000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',   '2020-01-01Z', null, null, 'spec-apt-009-test', 'c0a90000-0000-4000-8000-000000000991'),
    ('c0a90000-0000-4000-8000-000000000903', 'c0a90000-0000-4000-8000-000000000303', '2020-01-01Z', 'PENDING',  '2020-01-01Z', null, null, 'spec-apt-009-test', 'c0a90000-0000-4000-8000-000000000993'),
    ('c0a90000-0000-4000-8000-000000000904', 'c0a90000-0000-4000-8000-000000000304', '2020-01-01Z', 'PAST_DUE', '2020-01-01Z', null, null, 'spec-apt-009-test', 'c0a90000-0000-4000-8000-000000000994'),
    ('c0a90000-0000-4000-8000-000000000905', 'c0a90000-0000-4000-8000-000000000305', '2020-01-01Z', 'EXPIRED',  '2020-01-01Z', null, null, 'spec-apt-009-test', 'c0a90000-0000-4000-8000-000000000995');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('c0a90000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null),
    ('c0a90000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z', null),
    ('c0a90000-0000-4000-8000-000000000a13', pg_temp.domain_user(3), pg_temp.luna(), '2020-01-01Z', '2021-01-01Z');

-- An Appointment requested on 2026-01-01 with revision 1 REQUESTED, an
-- ACTIVE Care Authorization and, unless REQUESTED/EXPIRED/CANCELLED,
-- revision 2 CONFIRMED with its confirmation Event on 2026-02-01.
create function pg_temp.seed(
    p_n integer, p_clinic uuid, p_start timestamptz, p_end timestamptz, p_state text
)
returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), pg_temp.luna(), p_clinic, pg_temp.domain_user(1), 'Visit ' || p_n, p_state,
            '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_end, 'Europe/Madrid', pg_temp.domain_user(1), null,
              '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) select pg_temp.ca(p_n), pg_temp.luna(), p_clinic, clinic.organization_id, 'c0a90000-0000-4000-8000-000000000a11',
             '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n), 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE'
      from public.clinics as clinic where clinic.id = p_clinic;
    if p_state not in ('REQUESTED', 'EXPIRED', 'CANCELLED') then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
        ) values (pg_temp.appt(p_n), 2, 'CONFIRMED', p_start, p_end, 'Europe/Madrid', pg_temp.domain_user(8), null,
                  '2026-02-01T00:00:00Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(8), 'CLINIC', null,
                  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
    end if;
end;
$$;

-- A later CONFIRMED revision, as an accepted confirmed reschedule produces.
create function pg_temp.seed_reschedule(
    p_n integer, p_sequence integer, p_start timestamptz, p_end timestamptz, p_timezone text
)
returns void language sql as $$
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), p_sequence, 'CONFIRMED', p_start, p_end, p_timezone, pg_temp.domain_user(1), null,
              '2026-03-01T00:00:00Z'::timestamptz + make_interval(mins => p_sequence));
$$;

create function pg_temp.seed_past(p_n integer, p_clinic uuid) returns void language sql as $$
    select pg_temp.seed(p_n, p_clinic, '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'CONFIRMED');
$$;

-- A historical COMPLETED outcome for Appointment p_n.
create function pg_temp.seed_completion(p_n integer, p_effective timestamptz) returns void language sql as $$
    update public.appointments set lifecycle_state = 'COMPLETED' where id = pg_temp.appt(p_n);
    insert into public.appointment_lifecycle_events (
        id, appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
    ) values (pg_temp.evt(p_n), pg_temp.appt(p_n), 'CONFIRMED', 'COMPLETED', pg_temp.domain_user(8), 'CLINIC', null,
              p_effective, p_effective);
$$;

-- A historical Clinical Record Entry for Appointment p_n by Veterinarian 10 at
-- A1 (replica mode: no structural trigger).
create function pg_temp.seed_entry(p_n integer, p_created timestamptz) returns void language sql as $$
    insert into public.clinical_record_entries (
        appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at,
        category, clinical_content, creation_idempotency_key, creation_request_digest
    ) values (pg_temp.appt(p_n), pg_temp.domain_user(10), 'c0a90000-0000-4000-8000-000000000810', p_created,
              'CLINICAL_NOTE', 'Historical note', gen_random_uuid(), sha256(gen_random_uuid()::text::bytea));
$$;

-- Authorization (5–11).
select pg_temp.seed_past(n, pg_temp.clinic(1)) from unnest(array[5, 6, 7, 8, 9, 11]) as n;
select pg_temp.seed_past(10, pg_temp.clinic(2));
-- Entitlement (16–19); OrgA ACTIVE is covered by the cases above.
select pg_temp.seed_past(16, pg_temp.clinic(4));
select pg_temp.seed_past(17, pg_temp.clinic(5));
select pg_temp.seed_past(18, pg_temp.clinic(6));
select pg_temp.seed_past(19, pg_temp.clinic(7));
-- Lifecycle (20–24).
select pg_temp.seed(20, pg_temp.clinic(1), '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'REQUESTED');
select pg_temp.seed(21, pg_temp.clinic(1), '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'EXPIRED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(21), 'REQUESTED', 'EXPIRED', null, 'SYSTEM', null, '2026-06-01T10:00Z', '2026-06-01T10:05Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T10:00Z', ended_reason = 'APPOINTMENT_EXPIRED' where id = pg_temp.ca(21);
select pg_temp.seed(22, pg_temp.clinic(1), '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'CANCELLED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(22), 'REQUESTED', 'CANCELLED', pg_temp.domain_user(1), 'GUARDIAN', null, '2026-03-01Z', '2026-03-01Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-03-01Z', ended_reason = 'APPOINTMENT_CANCELLED' where id = pg_temp.ca(22);
select pg_temp.seed(23, pg_temp.clinic(1), '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'CONFIRMED');
select pg_temp.seed_completion(23, '2026-06-01T11:00Z');
select pg_temp.seed(24, pg_temp.clinic(1), '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'NO_SHOW');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(24), 'CONFIRMED', 'NO_SHOW', pg_temp.domain_user(8), 'CLINIC', null, '2026-06-01T11:00Z', '2026-06-01T11:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T11:00Z', ended_reason = 'APPOINTMENT_NO_SHOW' where id = pg_temp.ca(24);
-- Time (25–29).
select pg_temp.seed(25, pg_temp.clinic(1), '2035-03-06T09:00Z', '2035-03-06T09:30Z', 'CONFIRMED');
select pg_temp.seed(26, pg_temp.clinic(1), now(), now() + interval '30 minutes', 'CONFIRMED');
select pg_temp.seed(27, pg_temp.clinic(1), now() - interval '10 minutes', now() + interval '20 minutes', 'CONFIRMED');
select pg_temp.seed_past(28, pg_temp.clinic(1));
select pg_temp.seed_past(29, pg_temp.clinic(1));
select pg_temp.seed_reschedule(29, 3, '2035-03-07T09:00Z', '2035-03-07T09:30Z', 'Europe/Madrid');
-- Stale (30–36).
select pg_temp.seed_past(30, pg_temp.clinic(1));
select pg_temp.seed_past(31, pg_temp.clinic(1));
select pg_temp.seed_reschedule(31, 3, '2026-06-02T12:00Z', '2026-06-02T12:30Z', 'Europe/Madrid');
select pg_temp.seed_past(35, pg_temp.clinic(1));
select pg_temp.seed_reschedule(35, 3, '2026-06-01T10:00Z', '2026-06-01T10:45Z', 'Europe/Madrid');
select pg_temp.seed_past(36, pg_temp.clinic(1));
select pg_temp.seed_reschedule(36, 3, '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'Atlantic/Canary');
-- Optional tooling (37–40) and races (48–52).
select pg_temp.seed_past(n, pg_temp.clinic(1)) from unnest(array[37, 38, 39, 40, 41, 48, 49, 50, 51, 52]) as n;
-- 37: a current Veterinarian Assignment exists.
insert into public.appointment_veterinarian_assignments (
    id, appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id
) values ('c0a90000-0000-4000-8000-000000000d37', pg_temp.appt(37), 'c0a90000-0000-4000-8000-000000000810',
          '2026-01-15T00:00Z', pg_temp.domain_user(8));
-- 40: a PENDING Clinic Reschedule Proposal on the current confirmed revision.
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
) select 'c0a90000-0000-4000-8000-000000000d40', pg_temp.appt(40), revision.id, 'CONFIRMED',
         '2035-08-01T08:00Z', '2035-08-01T08:30Z', 'Europe/Madrid', 'CLINIC', pg_temp.domain_user(8),
         'Clinic needs to move it', '2026-05-01T00:00Z'
  from public.appointment_schedule_revisions as revision
  where revision.appointment_id = pg_temp.appt(40) and revision.revision_sequence = 2;
-- Historical provenance (60–64).
select pg_temp.seed_past(n, pg_temp.clinic(1)) from unnest(array[60, 61, 62, 63, 64]) as n;
-- 60: a completion with an Entry recorded before it.
select pg_temp.seed_entry(60, '2026-06-01T10:05Z');
select pg_temp.seed_completion(60, '2026-06-01T11:00Z');
-- 61: a completion with an Entry recorded after it.
select pg_temp.seed_completion(61, '2026-06-01T11:00Z');
select pg_temp.seed_entry(61, '2026-06-01T12:00Z');
-- 62: a NO_SHOW outcome that carries clinical documentation (incoherent).
update public.appointments set lifecycle_state = 'NO_SHOW' where id = pg_temp.appt(62);
insert into public.appointment_lifecycle_events (id, appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.evt(62), pg_temp.appt(62), 'CONFIRMED', 'NO_SHOW', pg_temp.domain_user(8), 'CLINIC', null, '2026-06-01T11:00Z', '2026-06-01T11:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T11:00Z', ended_reason = 'APPOINTMENT_NO_SHOW' where id = pg_temp.ca(62);
select pg_temp.seed_entry(62, '2026-06-01T10:05Z');
-- 63: a completion before the latest confirmed start.
select pg_temp.seed_completion(63, '2026-06-01T09:00Z');
-- Completion and the Care Authorization (65–69, SPEC-MED-010 BR-16).
select pg_temp.seed_past(n, pg_temp.clinic(1)) from unnest(array[65, 66, 67, 68, 69]) as n;
-- 65: the Guardian revoked before completion.
update public.care_authorizations set lifecycle_state = 'REVOKED', revoked_at = '2026-05-01Z',
    revoking_user_id = pg_temp.domain_user(1), revocation_reason = 'No longer needed'
where id = pg_temp.ca(65);
-- 67: a pre-M3 completion that kept its authorization ACTIVE (now incoherent).
select pg_temp.seed_completion(67, '2026-06-01T11:00Z');
-- 68: completion-ended at a time other than the completion Event.
select pg_temp.seed_completion(68, '2026-06-01T11:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T12:00Z',
    ended_reason = 'APPOINTMENT_COMPLETED' where id = pg_temp.ca(68);
-- 69: completion-ended although the Appointment is still CONFIRMED.
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-06-01T11:00Z',
    ended_reason = 'APPOINTMENT_COMPLETED' where id = pg_temp.ca(69);

set local session_replication_role = origin;

select pg_temp.assert_true(
    public.organization_has_professional_entitlement('c0a90000-0000-4000-8000-000000000301', 'CLINICAL_CARE')
    and not public.organization_has_professional_entitlement('c0a90000-0000-4000-8000-000000000303', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0a90000-0000-4000-8000-000000000304', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0a90000-0000-4000-8000-000000000305', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('c0a90000-0000-4000-8000-000000000306', 'APPOINTMENT_MANAGEMENT'),
    'Fixture: only OrgA holds normal professional Entitlement'
);

-- ===========================================================================
-- 2. Authentication and invalid expected sequence (cases 4–8).
-- ===========================================================================

select pg_temp.remember(30);
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(30)), '28000', 'Authentication is required');
reset role;
select set_config('request.jwt.claim.sub', 'c0a90000-0000-4000-8000-0000000001ff', true);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(30)), '28000', 'No coherent domain User exists');
reset role;

select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.complete(%L, null)', pg_temp.appt(30)), '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error(format('select pg_temp.complete(%L, 0)', pg_temp.appt(30)), '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error(format('select pg_temp.complete(%L, -2)', pg_temp.appt(30)), '22023', 'Expected confirmed revision sequence must be a positive integer');
-- Structural validation precedes any Appointment lookup or disclosure.
select pg_temp.assert_error('select pg_temp.complete(''c0a90000-0000-4000-8000-0000000000ff'', 0)', '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error('select pg_temp.complete(''c0a90000-0000-4000-8000-0000000000ff'', 2)', '23503', 'Appointment does not exist');
select pg_temp.assert_error(format('select public.complete_appointment(%L::uuid, %L::uuid)', pg_temp.appt(30), gen_random_uuid()), '42883', 'complete_appointment(uuid, uuid) does not exist');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(30), 'Cases 4–8: unauthenticated or incoherent callers, invalid input, an unknown Appointment, and the removed signature change nothing');

-- ===========================================================================
-- 3. Authorization (cases 9–18).
-- ===========================================================================

select pg_temp.remember(n) from unnest(array[10, 11]) as n;

set local role authenticated;
select pg_temp.complete_as(4, 5, 2);
select pg_temp.complete_as(5, 6, 2);
select pg_temp.complete_as(6, 7, 2);
select pg_temp.complete_as(7, 8, 2);
select pg_temp.complete_as(8, 9, 2);
-- Clinic-scoped A1 actors and the A1 Veterinarian on an A2 Appointment, then
-- everyone without authority on A1.
select pg_temp.assert_error('select pg_temp.complete_as(6, 10, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(8, 10, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(10, 10, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(9, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(11, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(12, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(1, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.complete_as(3, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
reset role;

select pg_temp.assert_true(
    pg_temp.is_completed_by(5, 4) and pg_temp.is_completed_by(6, 5) and pg_temp.is_completed_by(7, 6)
    and pg_temp.is_completed_by(8, 7) and pg_temp.is_completed_by(9, 8),
    'Cases 9–13: OWNER, Org ADMINISTRATOR, Clinic ADMINISTRATOR, Org RECEPTIONIST, and Clinic RECEPTIONIST complete'
);
select pg_temp.assert_true(
    pg_temp.unchanged(10) and pg_temp.unchanged(11),
    'Cases 14–17: other-Clinic actors, ended Membership, ended Grant, and current or former Guardians are denied with zero writes'
);

set local role authenticated;
select pg_temp.complete_as(9, 10, 2);
-- SPEC-ORG-005: VETERINARIAN provides APPOINTMENT_COMPLETE only where the
-- User has a current Clinic Assignment (A1, not A2 above).
select pg_temp.complete_as(10, 11, 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_completed_by(10, 9) and pg_temp.is_completed_by(11, 10),
    'Case 18: a Clinic RECEPTIONIST completes its own Clinic''s Appointment; a VETERINARIAN completes only through a current Clinic Assignment'
);

-- ===========================================================================
-- 4. No Entitlement gate (cases 19–22).
-- ===========================================================================

set local role authenticated;
select pg_temp.complete_as(16, n, 2) from generate_series(16, 19) as n;
reset role;

select pg_temp.assert_true(
    (select bool_and(pg_temp.is_completed_by(n, 16)) from generate_series(16, 19) as n),
    'Cases 19–22: completion resolves existing obligations under PENDING, PAST_DUE, EXPIRED, and no Subscription'
);

-- ===========================================================================
-- 5. Lifecycle (cases 23–27).
-- ===========================================================================

select pg_temp.remember(n) from generate_series(20, 24) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.complete(%L, %s)', pg_temp.appt(n), seq), '23514', 'Only a CONFIRMED Appointment may be completed')
from (values (20, 1), (21, 1), (22, 1), (23, 2), (24, 2)) as lifecycle_case (n, seq);
reset role;
select pg_temp.assert_true(
    (select bool_and(pg_temp.unchanged(n)) from generate_series(20, 24) as n),
    'Cases 23–27: REQUESTED, EXPIRED, CANCELLED, already COMPLETED, and NO_SHOW are rejected as lifecycle errors with zero writes'
);

-- ===========================================================================
-- 6. Time rule (cases 28–32).
-- ===========================================================================

select pg_temp.remember(n) from unnest(array[25, 29]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(25)), '23514', 'Appointment cannot be completed before its confirmed scheduled start');
select pg_temp.complete(pg_temp.appt(26), 2);
select pg_temp.complete(pg_temp.appt(27), 2);
select pg_temp.complete(pg_temp.appt(28), 2);
-- The accepted reschedule's later confirmed start (revision 3, future) applies.
select pg_temp.assert_error(format('select pg_temp.complete(%L, 3)', pg_temp.appt(29)), '23514', 'Appointment cannot be completed before its confirmed scheduled start');
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged(25) and pg_temp.unchanged(29)
    and pg_temp.is_completed_by(26, 8) and pg_temp.is_completed_by(27, 8) and pg_temp.is_completed_by(28, 8),
    'Cases 28–32: rejected before the start; permitted at the start, between start and end, and after the end; the latest accepted confirmed start applies'
);

-- ===========================================================================
-- 7. Stale-safe contract (cases 33–39).
-- ===========================================================================

select pg_temp.remember(n) from unnest(array[31, 35, 36]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(30), 2);
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(31)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(35)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(36)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(29)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.complete(%L, 4)', pg_temp.appt(31)), 'P0001', 'Stale confirmed Appointment schedule revision');
reset role;

select pg_temp.assert_true(
    pg_temp.is_completed_by(30, 8)
    and pg_temp.unchanged(31) and pg_temp.unchanged(35) and pg_temp.unchanged(36) and pg_temp.unchanged(29),
    'Cases 33–37: the current revision succeeds; a superseded or unknown one — also with the same start, end-only, or timezone-only differences, and with both starts past — is P0001 stale with zero writes'
);

select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(31), 3);
select pg_temp.complete(pg_temp.appt(35), 3);
select pg_temp.complete(pg_temp.appt(36), 3);
reset role;

select pg_temp.assert_true(
    pg_temp.is_completed_by(31, 8) and pg_temp.is_completed_by(35, 8) and pg_temp.is_completed_by(36, 8)
    and (select effective_at >= '2026-06-02T12:00Z' from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(31) and to_state = 'COMPLETED'),
    'Cases 38/39: after re-reading, the current revision succeeds'
);

-- ===========================================================================
-- 8. Optional clinical tooling is neither required nor touched (cases 40–46).
-- ===========================================================================

-- 37: a current Veterinarian Assignment exists.
select pg_temp.remember(37);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(37), 2);
reset role;

select pg_temp.assert_true(
    pg_temp.is_completed_by(37, 8) and pg_temp.untouched(37) and pg_temp.ended_by_completion(37)
    and (select effective_end is null from public.appointment_veterinarian_assignments
         where id = 'c0a90000-0000-4000-8000-000000000d37'),
    'Case 40: a current Veterinarian Assignment neither blocks nor changes with completion'
);

-- 38: a Clinical Record Entry exists; completion does not consume it, and
-- the assigned Veterinarian may still document afterwards.
select pg_temp.act(10);
set local role authenticated;
create temporary table entry_38 on commit drop as select pg_temp.clinical_entry(38) as id;
reset role;
select pg_temp.remember(38);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(38), 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_completed_by(38, 8) and pg_temp.untouched(38)
    and exists (select 1 from public.clinical_record_entries where id = (select id from entry_38))
    and pg_temp.ended_by_completion(38),
    'Case 41: an existing Entry does not block completion and is neither referenced nor changed; the Care Authorization ends with APPOINTMENT_COMPLETED'
);

select pg_temp.act(10);
set local role authenticated;
create temporary table entry_38_after on commit drop as select pg_temp.clinical_entry(38) as id;
reset role;
select pg_temp.assert_true(
    (select count(*) = 2 from public.clinical_record_entries where appointment_id = pg_temp.appt(38))
    and exists (select 1 from public.clinical_record_entries where id = (select id from entry_38_after))
    and pg_temp.state(38) = 'COMPLETED',
    'Case 42: after completion the assigned Veterinarian records another Entry with deferred coherence enforced; the Appointment stays COMPLETED'
);

-- 39: no assignment before completion; the Veterinarian assigned afterwards
-- documents the COMPLETED Appointment.
select pg_temp.remember(39);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(39), 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_completed_by(39, 8) and pg_temp.untouched(39) and pg_temp.ended_by_completion(39),
    'Case 43: an Appointment without assignment or documentation completes unchanged'
);
select pg_temp.act(10);
set local role authenticated;
select pg_temp.clinical_entry(39);
reset role;
select pg_temp.assert_true(
    pg_temp.state(39) = 'COMPLETED'
    and (select count(*) = 1 from public.clinical_record_entries where appointment_id = pg_temp.appt(39))
    and (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(39) and to_state = 'COMPLETED'),
    'Case 43b: a Veterinarian assigned after completion documents the COMPLETED Appointment without a new Lifecycle Event'
);

-- 41: no Assignment or clinical documentation at all; outcome,
-- Communications, Care Authorization, and reads.
select pg_temp.remember(41);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.complete(pg_temp.appt(41), 2) = pg_temp.appt(41),
    'Case 44: completion returns the Appointment identifier'
);
reset role;

create temporary table read_snapshot (
    source text, id uuid, lifecycle_state text, revision_sequence integer, primary key (source, id)
) on commit drop;
grant select, insert on read_snapshot to authenticated;
select pg_temp.act(1);
set local role authenticated;
insert into read_snapshot select 'guardian', id, lifecycle_state, null from public.get_pet_appointments(pg_temp.luna());
reset role;
select pg_temp.act(8);
set local role authenticated;
insert into read_snapshot select 'clinic', id, lifecycle_state, current_schedule_revision_sequence from public.get_clinic_appointment_schedule(pg_temp.clinic(1));
reset role;

select pg_temp.assert_true(
    pg_temp.is_completed_by(41, 8)
    and pg_temp.untouched(41)
    and not exists (select 1 from public.appointment_veterinarian_assignments where appointment_id = pg_temp.appt(41))
    and not exists (select 1 from public.clinical_record_entries where appointment_id = pg_temp.appt(41))
    and pg_temp.ended_by_completion(41)
    and not exists (select 1 from public.transactional_communications
                    where appointment_id = pg_temp.appt(41)
                      and (recipient_user_id in (pg_temp.domain_user(3), pg_temp.domain_user(8))
                           or communication_type <> 'APPOINTMENT_COMPLETED'))
    and (select lifecycle_state = 'COMPLETED' from read_snapshot where source = 'guardian' and id = pg_temp.appt(41))
    and (select lifecycle_state = 'COMPLETED' and revision_sequence = 2 from read_snapshot where source = 'clinic' and id = pg_temp.appt(41)),
    'Cases 45/46: with no clinical tooling, completion writes one Event and the COMPLETED state, ends the Care Authorization at the completion time, notifies only the two current Guardians, and both reads show COMPLETED with the unchanged confirmed revision'
);

-- ===========================================================================
-- 9. Pending Reschedule Proposal (case 47).
-- ===========================================================================

select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(40), 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_completed_by(40, 8)
    and (select state = 'VOID' and void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED' and voided_at is not null
         from public.appointment_reschedule_proposals where id = 'c0a90000-0000-4000-8000-000000000d40'),
    'Case 47: a PENDING confirmed-base proposal becomes VOID with APPOINTMENT_LIFECYCLE_CHANGED through the existing lifecycle invalidation'
);
-- A REQUESTED-base alternative cannot be PENDING on a CONFIRMED Appointment
-- (its base context must equal the lifecycle state), so it cannot coexist
-- with completion; the generic invalidation above covers both base contexts.

-- ===========================================================================
-- 10. Terminal behavior and serialized races (cases 48–55).
-- ===========================================================================

set local role authenticated;
-- 48: two Clinic actors with the same reviewed revision.
select pg_temp.complete_as(7, 48, 2);
select pg_temp.assert_error('select pg_temp.complete_as(8, 48, 2)', '23514', 'Only a CONFIRMED Appointment may be completed');
-- 49/50: NO_SHOW or cancellation wins first.
select pg_temp.act(8);
select pg_temp.no_show(49);
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(49)), '23514', 'Only a CONFIRMED Appointment may be completed');
select pg_temp.cancel(50);
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(50)), '23514', 'Only a CONFIRMED Appointment may be completed');
-- 51/52: completion wins first; NO_SHOW and cancellation are then lifecycle errors.
select pg_temp.complete(pg_temp.appt(51), 2);
select pg_temp.assert_error('select pg_temp.no_show(51)', '23514', 'Only a CONFIRMED Appointment may be marked no-show');
select pg_temp.complete(pg_temp.appt(52), 2);
select pg_temp.assert_error('select pg_temp.cancel(52)', '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled');
reset role;

select pg_temp.assert_true(
    pg_temp.is_completed_by(48, 7)
    and pg_temp.state(49) = 'NO_SHOW' and pg_temp.state(50) = 'CANCELLED'
    and not exists (select 1 from public.appointment_lifecycle_events
                    where appointment_id in (pg_temp.appt(49), pg_temp.appt(50)) and to_state = 'COMPLETED')
    and pg_temp.is_completed_by(51, 8) and pg_temp.is_completed_by(52, 8)
    and (select count(*) = 1 from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(51) and to_state in ('COMPLETED', 'NO_SHOW', 'CANCELLED'))
    and (select count(*) = 1 from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(52) and to_state in ('COMPLETED', 'NO_SHOW', 'CANCELLED'))
    and pg_temp.ended_by_completion(51) and pg_temp.ended_by_completion(52)
    and (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_NO_SHOW' from public.care_authorizations where id = pg_temp.ca(49))
    and (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_CANCELLED' from public.care_authorizations where id = pg_temp.ca(50)),
    'Cases 48–53: whichever terminal operation runs first wins; the loser is a lifecycle rejection with no second terminal Event, and each Care Authorization ends once with the winner''s context'
);

-- A completed Appointment's original completion facts survive every later attempt.
select pg_temp.assert_true(
    (select actor_user_id = pg_temp.domain_user(7) from public.appointment_lifecycle_events
     where appointment_id = pg_temp.appt(48) and to_state = 'COMPLETED'),
    'Cases 54/55: repeated completion keeps the original completing User and time'
);

-- ===========================================================================
-- 11. Lifecycle provenance with clinical documentation (cases 56–66). The
--     internal deferred assertions are called directly.
-- ===========================================================================

-- 60/61: clinical documentation recorded before or after the completion is
-- coherent under every assertion (completion carries no clinical evidence).
select public.assert_appointment_lifecycle_coherence(pg_temp.appt(60));
select public.assert_appointment_lifecycle_event_provenance(pg_temp.evt(60));
select public.assert_appointment_lifecycle_coherence(pg_temp.appt(61));
select public.assert_appointment_lifecycle_event_provenance(pg_temp.evt(61));
select pg_temp.assert_true(true, 'Cases 56/57: completion is coherent with clinical documentation recorded before or after it');

-- 62: a NO_SHOW outcome cannot coexist with clinical documentation.
select pg_temp.assert_error(format('select public.assert_appointment_lifecycle_coherence(%L)', pg_temp.appt(62)), '23514', 'cannot coexist with clinical documentation');
-- 63: a completion before the latest confirmed start.
select pg_temp.assert_error(format('select public.assert_appointment_lifecycle_event_provenance(%L)', pg_temp.evt(63)), '23514', 'cannot precede its latest confirmed scheduled start');
select public.assert_appointment_lifecycle_coherence(pg_temp.appt(23));
select public.assert_appointment_lifecycle_event_provenance(
    (select id from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(23) and to_state = 'COMPLETED'));

select pg_temp.assert_true(true, 'Cases 58–62: documented non-attendance and completion before the confirmed start are rejected; a valid historical completion is accepted');

-- No Event can carry an Encounter reference: the column no longer exists.
select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at, clinical_encounter_id)
            values (%L, ''CONFIRMED'', ''COMPLETED'', %L, ''CLINIC'', null, clock_timestamp(), clock_timestamp(), %L)',
           pg_temp.appt(64), pg_temp.domain_user(8), gen_random_uuid()),
    '42703', 'clinical_encounter_id'
);
-- Historical Events remain immutable.
select pg_temp.assert_error(
    format('update public.appointment_lifecycle_events set reason = ''changed'' where id = %L', pg_temp.evt(60)),
    '23514', 'Appointment Lifecycle Events are immutable'
);
select pg_temp.assert_true(
    pg_temp.state(64) = 'CONFIRMED'
    and (select reason is null from public.appointment_lifecycle_events where id = pg_temp.evt(60)),
    'Cases 63–66: no Event may reference an Encounter, and historical Events stay immutable'
);

-- ===========================================================================
-- 12. Completion ends the Care Authorization (cases 67–75, SPEC-MED-010 BR-16,
--     SPEC-ACC-002 BR-46).
-- ===========================================================================

-- 65: a REVOKED authorization stays revoked with its original history.
create temporary table revoked_65 on commit drop as
    select to_jsonb(care_auth) as row_value from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(65);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(65), 2);
reset role;
select pg_temp.assert_true(
    pg_temp.is_completed_by(65, 8)
    and (select to_jsonb(care_auth) = (select row_value from revoked_65)
         from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(65))
    and (select lifecycle_state = 'REVOKED' and ended_reason is null and ended_at is null
         from public.care_authorizations where id = pg_temp.ca(65)),
    'Case 67: completing an Appointment whose authorization is REVOKED keeps the revocation, its actor, time and reason'
);

-- 66: a retry after a lost response is a lifecycle rejection; the first
-- completion and its authorization ending stay exactly as recorded.
select pg_temp.act(8);
set local role authenticated;
select pg_temp.complete(pg_temp.appt(66), 2);
reset role;
select pg_temp.remember(66);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(66)), '23514', 'Only a CONFIRMED Appointment may be completed');
select pg_temp.act(7);
select pg_temp.assert_error(format('select pg_temp.complete(%L, 2)', pg_temp.appt(66)), '23514', 'Only a CONFIRMED Appointment may be completed');
reset role;
select pg_temp.assert_true(
    pg_temp.unchanged(66) and pg_temp.ended_by_completion(66)
    and (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(66) and to_state = 'COMPLETED')
    and (select count(*) = 1 from public.care_authorizations where appointment_id = pg_temp.appt(66)),
    'Case 68: a repeated completion writes nothing; the authorization was ended once, no new one was created'
);

-- A rejected completion leaves the authorization ACTIVE (stale and early cases).
select pg_temp.assert_true(
    (select bool_and(care_auth.lifecycle_state = 'ACTIVE') from public.care_authorizations as care_auth
     where care_auth.id in (pg_temp.ca(25), pg_temp.ca(29))),
    'Case 69: a rejected completion (early or stale) does not end the authorization'
);

-- A Guardian revocation after completion reconciles; nothing is reactivated.
select pg_temp.act(1);
set local role authenticated;
create temporary table revoke_after on commit drop as
    select public.revoke_my_appointment_care_authorization(pg_temp.appt(41)) as outcome;
reset role;
select pg_temp.assert_true(
    (select outcome = '{"outcome": "ALREADY_INACTIVE"}'::jsonb from revoke_after)
    and pg_temp.ended_by_completion(41),
    'Case 70: a Guardian revocation after completion is ALREADY_INACTIVE and the ending stays APPOINTMENT_COMPLETED'
);

-- Structural coherence (internal assertions and immutability), each outcome
-- captured so one assertion pins them all.
create function pg_temp.outcome_of(p_statement text) returns text language plpgsql as $$
begin
    execute p_statement;
    return 'OK';
exception when others then
    return sqlstate || ':' || sqlerrm;
end;
$$;
create temporary table structural on commit drop as select
    pg_temp.outcome_of(format('select public.assert_appointment_care_authorization_coherence(%L)', pg_temp.appt(67))) as completed_active,
    pg_temp.outcome_of(format('select public.assert_care_authorization_appointment_coherence(%L)', pg_temp.ca(68))) as wrong_time,
    pg_temp.outcome_of(format('select public.assert_care_authorization_appointment_coherence(%L)', pg_temp.ca(69))) as wrong_state,
    pg_temp.outcome_of(format('update public.care_authorizations set lifecycle_state = ''ACTIVE'', ended_at = null, ended_reason = null where id = %L', pg_temp.ca(41))) as reactivated,
    pg_temp.outcome_of(format('update public.care_authorizations set ended_reason = ''APPOINTMENT_CANCELLED'' where id = %L', pg_temp.ca(41))) as relabelled;
select pg_temp.assert_true(
    (select completed_active like '23514:%must not retain ACTIVE care authority'
            and wrong_time like '23514:%must match its terminal Appointment Event time'
            and wrong_state like '23514:%requires its matching terminal Appointment state'
            and reactivated like '23514:A terminal Care Authorization cannot be modified further%'
            and relabelled like '23514:A terminal Care Authorization cannot be modified further%'
     from structural)
    and coalesce(pg_get_constraintdef((select oid from pg_constraint where conname = 'care_authorizations_ended_reason_check'))
        like '%APPOINTMENT_COMPLETED%', false)
    and pg_temp.ended_by_completion(41),
    'Cases 71–75: a COMPLETED Appointment never keeps an ACTIVE authorization; APPOINTMENT_COMPLETED requires the COMPLETED state and the completion time; an ended authorization is never reactivated or re-labelled'
);

rollback;

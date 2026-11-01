-- Regression suite for SPEC-APT-010 — Mark Appointment No-Show, including the
-- stale-safe contract (BR-41, BR-42, BR-43) and the time rule (BR-44),
-- migration 20261005090000_stale_safe_appointment_no_show.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deterministic context with
-- establishment triggers bypassed, to inspect protected tables, and to switch
-- between impersonated Users.
--
-- Every behavioral call goes through the real trusted operations. Helper
-- wrappers fire every pending deferred trigger at the end of each call (SET
-- CONSTRAINTS ALL IMMEDIATE, then back to DEFERRED — the database has no
-- DEFERRABLE INITIALLY IMMEDIATE constraint), so deferred lifecycle, Care
-- Authorization, and clinical documentation coherence run inside the same
-- subtransaction.
--
-- Time boundary: the database clock cannot be frozen, so "exactly at the
-- start" is exercised with a start equal to the transaction start instant
-- (`now()`), which the call necessarily reaches; the rule under test is that
-- only a start strictly after the operation time is rejected.
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
    select ('d0e10000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('d0e10000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('d0e10000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'd0e10000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('d0e10000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.luna() returns uuid language sql immutable as $$
    select 'd0e10000-0000-4000-8000-000000000a01'::uuid
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

create function pg_temp.no_show(p_appointment uuid, p_sequence integer)
returns uuid language plpgsql as $$
declare marked uuid;
begin
    marked := public.mark_appointment_no_show(p_appointment, p_sequence);
    perform pg_temp.flush();
    return marked;
end;
$$;

create function pg_temp.no_show_as(p_user integer, p_n integer, p_sequence integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform pg_temp.no_show(pg_temp.appt(p_n), p_sequence);
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
    created := pg_temp.record_entry(pg_temp.appt(p_n), 'd0e10000-0000-4000-8000-000000000810'::uuid);
    perform pg_temp.flush();
    return created;
end;
$$;

-- SPEC-APT-009: stale-safe lightweight completion of a fixture CONFIRMED at
-- revision 2 whose start has been reached.
create function pg_temp.complete(p_n integer)
returns void language plpgsql as $$
begin
    perform public.complete_appointment(pg_temp.appt(p_n), 2);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.cancel(p_n integer)
returns void language plpgsql as $$
begin
    -- Every no-show fixture is CONFIRMED at revision 2 (SPEC-APT-003 BR-24).
    perform public.cancel_appointment(pg_temp.appt(p_n), 'CLINIC', 'Clinic closed', 2);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.state(p_n integer) returns text language sql as $$
    select lifecycle_state from public.appointments where id = pg_temp.appt(p_n)
$$;

-- Every persisted fact a no-show could touch for one Appointment.
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

-- A successful no-show: one CLINIC Event by the actor, NO_SHOW state, the
-- authorization ENDED as APPOINTMENT_NO_SHOW at the Event time, and exactly
-- one APPOINTMENT_NO_SHOW Communication per current Guardian (G1, G2).
create function pg_temp.is_no_show_by(p_n integer, p_user integer)
returns boolean language sql as $$
    select pg_temp.state(p_n) = 'NO_SHOW'
       and (select count(*) = 1 from public.appointment_lifecycle_events as event
            where event.appointment_id = pg_temp.appt(p_n) and event.to_state = 'NO_SHOW'
              and event.from_state = 'CONFIRMED' and event.actor_context = 'CLINIC'
              and event.actor_user_id = pg_temp.domain_user(p_user))
       and (select care_auth.lifecycle_state = 'ENDED'
                   and care_auth.ended_reason = 'APPOINTMENT_NO_SHOW'
                   and care_auth.ended_at = event.effective_at
            from public.care_authorizations as care_auth
            join public.appointment_lifecycle_events as event
              on event.appointment_id = care_auth.appointment_id and event.to_state = 'NO_SHOW'
            where care_auth.id = pg_temp.ca(p_n))
       and (select array_agg(communication.recipient_user_id order by communication.recipient_user_id)
            from public.transactional_communications as communication
            where communication.appointment_id = pg_temp.appt(p_n)
              and communication.communication_type = 'APPOINTMENT_NO_SHOW')
           = array[pg_temp.domain_user(1), pg_temp.domain_user(2)]
$$;

-- ===========================================================================
-- 1. Contract (cases 1–4).
-- ===========================================================================

select pg_temp.assert_true(
    to_regprocedure('public.mark_appointment_no_show(uuid)') is null
    and (select count(*) = 1 from pg_proc as proc
         where proc.proname = 'mark_appointment_no_show'
           and proc.pronamespace = 'public'::regnamespace)
    and (select pg_get_function_arguments(proc.oid) = 'p_appointment_id uuid, p_expected_confirmed_revision_sequence integer'
                and pg_get_function_result(proc.oid) = 'uuid'
                and proc.pronargdefaults = 0
                and proc.prosecdef
                and proc.provolatile = 'v'
                and proc.proconfig = array['search_path=""']
         from pg_proc as proc
         where proc.oid = 'public.mark_appointment_no_show(uuid, integer)'::regprocedure)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.oid = 'public.mark_appointment_no_show(uuid, integer)'::regprocedure
           and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.mark_appointment_no_show(uuid, integer)', 'EXECUTE'),
    'Cases 1/2: only mark_appointment_no_show(uuid, integer) exists — no default, SECURITY DEFINER, VOLATILE, empty search_path, original ACL'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects d0e10000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 (current)        08 RECEPTIONIST @ A1 (Clinic)
--   02 Guardian G2 (current)        09 RECEPTIONIST @ A2 (Clinic)
--   03 former Guardian G3           10 VETERINARIAN only, assigned @ A1
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
select ('d0e10000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('d0e10000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('d0e10000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('d0e10000-0000-4000-8000-000000000303', 'Org Pending'),
    ('d0e10000-0000-4000-8000-000000000304', 'Org Past Due'),
    ('d0e10000-0000-4000-8000-000000000305', 'Org Expired'),
    ('d0e10000-0000-4000-8000-000000000306', 'Org Without Subscription');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values
    (pg_temp.clinic(1), 'd0e10000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(2), 'd0e10000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(4), 'd0e10000-0000-4000-8000-000000000303', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(5), 'd0e10000-0000-4000-8000-000000000304', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(6), 'd0e10000-0000-4000-8000-000000000305', true, 'Europe/Madrid', 30),
    (pg_temp.clinic(7), 'd0e10000-0000-4000-8000-000000000306', true, 'Europe/Madrid', 30);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('d0e10000-0000-4000-8000-000000000504', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000505', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(5), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000506', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(6), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000507', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(7), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000508', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(8), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000509', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(9), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000510', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000511', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(11), '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4)),
    ('d0e10000-0000-4000-8000-000000000512', 'd0e10000-0000-4000-8000-000000000301', pg_temp.domain_user(12), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000513', 'd0e10000-0000-4000-8000-000000000303', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000514', 'd0e10000-0000-4000-8000-000000000304', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000515', 'd0e10000-0000-4000-8000-000000000305', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('d0e10000-0000-4000-8000-000000000516', 'd0e10000-0000-4000-8000-000000000306', pg_temp.domain_user(16), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('d0e10000-0000-4000-8000-000000000604', 'd0e10000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000605', 'd0e10000-0000-4000-8000-000000000505', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000606', 'd0e10000-0000-4000-8000-000000000506', 'ADMINISTRATOR', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000607', 'd0e10000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000608', 'd0e10000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(1), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000609', 'd0e10000-0000-4000-8000-000000000509', 'RECEPTIONIST', 'CLINIC', pg_temp.clinic(2), '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000610', 'd0e10000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000611', 'd0e10000-0000-4000-8000-000000000511', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('d0e10000-0000-4000-8000-000000000612', 'd0e10000-0000-4000-8000-000000000512', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', pg_temp.domain_user(4), pg_temp.domain_user(4)),
    ('d0e10000-0000-4000-8000-000000000613', 'd0e10000-0000-4000-8000-000000000513', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('d0e10000-0000-4000-8000-000000000614', 'd0e10000-0000-4000-8000-000000000514', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('d0e10000-0000-4000-8000-000000000615', 'd0e10000-0000-4000-8000-000000000515', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('d0e10000-0000-4000-8000-000000000616', 'd0e10000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null);

insert into public.veterinarian_professional_profiles (id, user_id)
values ('d0e10000-0000-4000-8000-000000000710', pg_temp.domain_user(10));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start
) values ('d0e10000-0000-4000-8000-000000000810', 'd0e10000-0000-4000-8000-000000000710',
          'd0e10000-0000-4000-8000-000000000510', pg_temp.clinic(1), '2020-01-01Z');

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('d0e10000-0000-4000-8000-000000000901', 'd0e10000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',   '2020-01-01Z', null, null, 'spec-apt-010-test', 'd0e10000-0000-4000-8000-000000000991'),
    ('d0e10000-0000-4000-8000-000000000903', 'd0e10000-0000-4000-8000-000000000303', '2020-01-01Z', 'PENDING',  '2020-01-01Z', null, null, 'spec-apt-010-test', 'd0e10000-0000-4000-8000-000000000993'),
    ('d0e10000-0000-4000-8000-000000000904', 'd0e10000-0000-4000-8000-000000000304', '2020-01-01Z', 'PAST_DUE', '2020-01-01Z', null, null, 'spec-apt-010-test', 'd0e10000-0000-4000-8000-000000000994'),
    ('d0e10000-0000-4000-8000-000000000905', 'd0e10000-0000-4000-8000-000000000305', '2020-01-01Z', 'EXPIRED',  '2020-01-01Z', null, null, 'spec-apt-010-test', 'd0e10000-0000-4000-8000-000000000995');

insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('d0e10000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z', null),
    ('d0e10000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z', null),
    ('d0e10000-0000-4000-8000-000000000a13', pg_temp.domain_user(3), pg_temp.luna(), '2020-01-01Z', '2021-01-01Z');

-- An Appointment requested on 2026-01-01 with revision 1 REQUESTED, an
-- ACTIVE Care Authorization and, unless REQUESTED, revision 2 CONFIRMED with
-- its confirmation Event on 2026-02-01.
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
    ) select pg_temp.ca(p_n), pg_temp.luna(), p_clinic, clinic.organization_id, 'd0e10000-0000-4000-8000-000000000a11',
             '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n), 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE'
      from public.clinics as clinic where clinic.id = p_clinic;
    if p_state <> 'REQUESTED' and p_state <> 'EXPIRED' and p_state <> 'CANCELLED' then
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

-- Authorization (5–14).
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
select pg_temp.seed(23, pg_temp.clinic(1), '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'COMPLETED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(23), 'CONFIRMED', 'COMPLETED', pg_temp.domain_user(8), 'CLINIC', null, '2026-06-01T11:00Z', '2026-06-01T11:00Z');
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
-- Clinical documentation (37–39) and races (48–50).
select pg_temp.seed_past(n, pg_temp.clinic(1)) from unnest(array[37, 39, 48, 49, 50]) as n;

set local session_replication_role = origin;

-- ===========================================================================
-- 2. Invalid expected sequence (cases 3–4).
-- ===========================================================================

select pg_temp.remember(30);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.no_show(%L, null)', pg_temp.appt(30)), '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 0)', pg_temp.appt(30)), '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error(format('select pg_temp.no_show(%L, -2)', pg_temp.appt(30)), '22023', 'Expected confirmed revision sequence must be a positive integer');
-- Structural validation precedes any Appointment lookup.
select pg_temp.assert_error('select pg_temp.no_show(''d0e10000-0000-4000-8000-0000000000ff'', 0)', '22023', 'Expected confirmed revision sequence must be a positive integer');
select pg_temp.assert_error(format('select public.mark_appointment_no_show(%L::uuid)', pg_temp.appt(30)), '42883', 'mark_appointment_no_show(uuid) does not exist');
reset role;
select pg_temp.assert_true(pg_temp.unchanged(30), 'Cases 2/3/4: invalid input and the removed signature change nothing');

-- ===========================================================================
-- 3. Authorization (cases 5–14).
-- ===========================================================================

select pg_temp.remember(n) from unnest(array[10, 11]) as n;

set local role authenticated;
select pg_temp.no_show_as(4, 5, 2);
select pg_temp.no_show_as(5, 6, 2);
select pg_temp.no_show_as(6, 7, 2);
select pg_temp.no_show_as(7, 8, 2);
select pg_temp.no_show_as(8, 9, 2);
-- Clinic-scoped A1 actors on an A2 Appointment, then everyone without authority on A1.
select pg_temp.assert_error('select pg_temp.no_show_as(6, 10, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.no_show_as(8, 10, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.no_show_as(10, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.no_show_as(9, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.no_show_as(11, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.no_show_as(12, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
select pg_temp.assert_error('select pg_temp.no_show_as(1, 11, 2)', '42501', 'Applicable Clinic-management capability is required');
reset role;

select pg_temp.assert_true(
    pg_temp.is_no_show_by(5, 4) and pg_temp.is_no_show_by(6, 5) and pg_temp.is_no_show_by(7, 6)
    and pg_temp.is_no_show_by(8, 7) and pg_temp.is_no_show_by(9, 8),
    'Cases 5–9: OWNER, Org ADMINISTRATOR, Clinic ADMINISTRATOR, Org RECEPTIONIST, and Clinic RECEPTIONIST mark NO_SHOW'
);
select pg_temp.assert_true(
    pg_temp.unchanged(10) and pg_temp.unchanged(11),
    'Cases 10–14: VETERINARIAN-only, other-Clinic, ended Membership, ended Grant, and Guardian are denied with zero writes'
);

set local role authenticated;
select pg_temp.no_show_as(9, 10, 2);
reset role;
select pg_temp.assert_true(pg_temp.is_no_show_by(10, 9), 'Cases 9/11: a Clinic RECEPTIONIST resolves its own Clinic''s Appointment');

-- ===========================================================================
-- 4. No Entitlement gate (cases 15–18).
-- ===========================================================================

select pg_temp.assert_true(
    public.organization_has_professional_entitlement('d0e10000-0000-4000-8000-000000000301', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('d0e10000-0000-4000-8000-000000000303', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('d0e10000-0000-4000-8000-000000000304', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('d0e10000-0000-4000-8000-000000000305', 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement('d0e10000-0000-4000-8000-000000000306', 'APPOINTMENT_MANAGEMENT'),
    'Fixture: only OrgA holds normal professional Entitlement'
);

set local role authenticated;
select pg_temp.no_show_as(16, n, 2) from generate_series(16, 19) as n;
reset role;

select pg_temp.assert_true(
    (select bool_and(pg_temp.is_no_show_by(n, 16)) from generate_series(16, 19) as n),
    'Cases 15–18: NO_SHOW resolves existing obligations under ACTIVE, PENDING, PAST_DUE, EXPIRED, and no Subscription'
);

-- ===========================================================================
-- 5. Lifecycle (cases 19–24).
-- ===========================================================================

select pg_temp.remember(n) from generate_series(20, 24) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.no_show(%L, %s)', pg_temp.appt(n), seq), '23514', 'Only a CONFIRMED Appointment may be marked no-show')
from (values (20, 1), (21, 1), (22, 1), (23, 2), (24, 2)) as lifecycle_case (n, seq);
reset role;
select pg_temp.assert_true(
    (select bool_and(pg_temp.unchanged(n)) from generate_series(20, 24) as n),
    'Cases 20–24: REQUESTED, EXPIRED, CANCELLED, COMPLETED, and already NO_SHOW are rejected as lifecycle errors with zero writes'
);

-- ===========================================================================
-- 6. Time rule (cases 25–29).
-- ===========================================================================

select pg_temp.remember(n) from unnest(array[25, 29]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(25)), '23514', 'Appointment cannot be marked no-show before its confirmed scheduled start');
select pg_temp.no_show(pg_temp.appt(26), 2);
select pg_temp.no_show(pg_temp.appt(27), 2);
select pg_temp.no_show(pg_temp.appt(28), 2);
-- The accepted reschedule's later confirmed start (revision 3, future) applies.
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 3)', pg_temp.appt(29)), '23514', 'Appointment cannot be marked no-show before its confirmed scheduled start');
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged(25) and pg_temp.unchanged(29)
    and pg_temp.is_no_show_by(26, 8) and pg_temp.is_no_show_by(27, 8) and pg_temp.is_no_show_by(28, 8),
    'Cases 25–29: rejected before the start, permitted at the start, between start and end, and after the end; the latest accepted confirmed start applies'
);

-- ===========================================================================
-- 7. Stale-safe contract (cases 30–36).
-- ===========================================================================

select pg_temp.remember(n) from unnest(array[31, 35, 36]) as n;
select pg_temp.act(8);
set local role authenticated;
select pg_temp.no_show(pg_temp.appt(30), 2);
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(31)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(35)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(36)), 'P0001', 'Stale confirmed Appointment schedule revision');
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(29)), 'P0001', 'Stale confirmed Appointment schedule revision');
reset role;

select pg_temp.assert_true(
    pg_temp.is_no_show_by(30, 8)
    and pg_temp.unchanged(31) and pg_temp.unchanged(35) and pg_temp.unchanged(36) and pg_temp.unchanged(29),
    'Cases 30–33/35/36: the current revision succeeds; a superseded one — also with the same start, end-only, or timezone-only differences, and with both starts past — is P0001 stale with zero writes'
);

select pg_temp.act(8);
set local role authenticated;
select pg_temp.no_show(pg_temp.appt(31), 3);
select pg_temp.no_show(pg_temp.appt(35), 3);
select pg_temp.no_show(pg_temp.appt(36), 3);
reset role;

select pg_temp.assert_true(
    pg_temp.is_no_show_by(31, 8) and pg_temp.is_no_show_by(35, 8) and pg_temp.is_no_show_by(36, 8)
    and (select effective_at >= '2026-06-02T12:00Z' from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(31) and to_state = 'NO_SHOW'),
    'Case 34: after re-reading, the current revision succeeds when its start has been reached'
);

-- ===========================================================================
-- 8. Clinical documentation (cases 37–39).
-- ===========================================================================

select pg_temp.act(10);
set local role authenticated;
select pg_temp.clinical_entry(37);
reset role;
-- 39 has its assigned Veterinarian before the no-show. Its window overlaps
-- 37's, so the period is a replica-mode fixture (no commitment check).
set local session_replication_role = replica;
select pg_temp.assign_vet(pg_temp.appt(39), 'd0e10000-0000-4000-8000-000000000810'::uuid);
set local session_replication_role = origin;

select pg_temp.remember(37);
select pg_temp.act(8);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(37)), '23514', 'Appointment with clinical documentation cannot be marked no-show');
-- 39: no-show first; the Entry attempted afterwards is refused.
select pg_temp.no_show(pg_temp.appt(39), 2);
reset role;

select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_error(format('select pg_temp.clinical_entry(%s)', 39), '23514', 'A Clinical Record Entry requires a legitimately confirmed CONFIRMED or COMPLETED Appointment');
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged(37)
    and pg_temp.state(37) = 'CONFIRMED'
    and (select lifecycle_state = 'ACTIVE' from public.care_authorizations where id = pg_temp.ca(37))
    and pg_temp.is_no_show_by(39, 8)
    and not exists (select 1 from public.clinical_record_entries where appointment_id = pg_temp.appt(39)),
    'Cases 37/38/39: an existing Entry blocks NO_SHOW with no partial write; whichever runs first wins and the other is refused'
);

-- ===========================================================================
-- 9. Outcome and reads (cases 40–47), on Appointment 30.
-- ===========================================================================

create temporary table read_snapshot (source text, id uuid, lifecycle_state text, primary key (source, id)) on commit drop;
grant select, insert on read_snapshot to authenticated;

select pg_temp.act(1);
set local role authenticated;
insert into read_snapshot select 'guardian', id, lifecycle_state from public.get_pet_appointments(pg_temp.luna());
reset role;

select pg_temp.act(8);
set local role authenticated;
insert into read_snapshot select 'clinic', id, lifecycle_state from public.get_clinic_appointment_schedule(pg_temp.clinic(1));
reset role;

select pg_temp.assert_true(
    pg_temp.is_no_show_by(30, 8)
    and (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(30) and to_state = 'NO_SHOW')
    and (select lifecycle_state = 'NO_SHOW' from read_snapshot where source = 'guardian' and id = pg_temp.appt(30))
    and (select lifecycle_state = 'NO_SHOW' from read_snapshot where source = 'clinic' and id = pg_temp.appt(30))
    and not exists (select 1 from public.transactional_communications
                    where appointment_id = pg_temp.appt(30)
                      and recipient_user_id in (pg_temp.domain_user(3), pg_temp.domain_user(8))),
    'Cases 40–47: one NO_SHOW Event, NO_SHOW state, authorization ended as APPOINTMENT_NO_SHOW, both reads show NO_SHOW, one Communication per current Guardian, none for the former Guardian or the Clinic actor'
);

-- ===========================================================================
-- 10. Races (cases 48–50).
-- ===========================================================================

set local role authenticated;
select pg_temp.no_show_as(7, 48, 2);
select pg_temp.assert_error('select pg_temp.no_show_as(8, 48, 2)', '23514', 'Only a CONFIRMED Appointment may be marked no-show');
reset role;

-- 49 overlaps 37 (still CONFIRMED with the same Veterinarian): replica-mode period.
set local session_replication_role = replica;
select pg_temp.assign_vet(pg_temp.appt(49), 'd0e10000-0000-4000-8000-000000000810'::uuid);
set local session_replication_role = origin;
select pg_temp.act(10);
set local role authenticated;
select pg_temp.clinical_entry(49);
reset role;
select pg_temp.act(8);
set local role authenticated;
-- The existing Entry does not block completion (SPEC-APT-009 BR-12).
select pg_temp.complete(49);
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(49)), '23514', 'Only a CONFIRMED Appointment may be marked no-show');
select pg_temp.cancel(50);
select pg_temp.assert_error(format('select pg_temp.no_show(%L, 2)', pg_temp.appt(50)), '23514', 'Only a CONFIRMED Appointment may be marked no-show');
reset role;

select pg_temp.assert_true(
    pg_temp.is_no_show_by(48, 7)
    and pg_temp.state(49) = 'COMPLETED'
    and pg_temp.state(50) = 'CANCELLED'
    and not exists (select 1 from public.appointment_lifecycle_events
                    where appointment_id in (pg_temp.appt(49), pg_temp.appt(50)) and to_state = 'NO_SHOW'),
    'Cases 48/49/50: a second actor, a completion, or a cancellation that wins first leaves the no-show as a lifecycle rejection'
);

rollback;

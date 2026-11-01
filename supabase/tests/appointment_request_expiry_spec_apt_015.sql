-- Regression suite for SPEC-APT-015 — Expire Unconfirmed Appointment Request
-- and the logical-expiry / pending-request rules of SPEC-APT-001 (BR-35,
-- BR-36), SPEC-APT-002 (BR-19), SPEC-APT-003 (BR-21–BR-23), SPEC-APT-004
-- (BR-27), SPEC-ACC-001 (BR-39–BR-41), SPEC-MED-001 (BR-34), and
-- SPEC-APT-009 (BR-40/BR-41), migration
-- 20261004090000_appointment_request_expiry_and_pending_policy.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back;
-- superuser execution is required solely to load a deterministic context
-- with establishment triggers bypassed, to inspect protected tables, to call
-- the internal expiry operation, and to switch between impersonated Users.
--
-- Every behavioral call goes through the real trusted operations. Helper
-- wrappers fire every pending deferred trigger at the end of each call (SET
-- CONSTRAINTS ALL IMMEDIATE, then back to DEFERRED — the database has no
-- DEFERRABLE INITIALLY IMMEDIATE constraint), so deferred coherence,
-- provenance, and conflict checks run inside the same subtransaction.
--
-- Genuine two-session races (concurrent pending requests, overlapping expiry
-- runs) cannot run inside one rolled-back session; they are covered by
-- deterministic interleavings here and by a separate two-session harness.
--
-- Fixture combinations are chosen so each pending-request case starts from a
-- known Pet + Clinic state:
--   Luna @ A1 — no Appointment at all (fresh duplicate checks);
--   Luna @ A2 — only a lapsed REQUESTED (it must not block);
--   Max  @ A1 — one Appointment in every non-blocking state;
--   Kira @ A1 / A2 — expiry, security, cancellation, rescheduling, and
--                    clinical documentation fixtures.
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
create function pg_temp.appt(p_n integer) returns uuid language sql immutable as $$
    select ('e1a00000-0000-4000-8000-000000000b' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.ca(p_n integer) returns uuid language sql immutable as $$
    select ('e1a00000-0000-4000-8000-000000000c' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('e1a00000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'e1a00000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;

-- Named constants.
create function pg_temp.luna() returns uuid language sql immutable as $$ select 'e1a00000-0000-4000-8000-000000000a01'::uuid $$;
create function pg_temp.max() returns uuid language sql immutable as $$ select 'e1a00000-0000-4000-8000-000000000a02'::uuid $$;
create function pg_temp.kira() returns uuid language sql immutable as $$ select 'e1a00000-0000-4000-8000-000000000a03'::uuid $$;
create function pg_temp.a1() returns uuid language sql immutable as $$ select 'e1a00000-0000-4000-8000-000000000401'::uuid $$;
create function pg_temp.a2() returns uuid language sql immutable as $$ select 'e1a00000-0000-4000-8000-000000000402'::uuid $$;

-- Ids produced by trusted operations during the run.
create temporary table produced (label text primary key, id uuid not null) on commit drop;
grant select, insert on produced to authenticated;
create function pg_temp.produced(p_label text) returns uuid language sql as $$
    select id from produced where label = p_label
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

create function pg_temp.request(
    p_label text, p_pet uuid, p_clinic uuid, p_date date, p_time time
)
returns uuid language plpgsql as $$
declare created uuid;
begin
    created := public.request_appointment(p_pet, p_clinic, p_date, p_time, 3600, 'Revisión', null);
    perform pg_temp.flush();
    if p_label is not null then insert into produced values (p_label, created); end if;
    return created;
end;
$$;

-- p_sequence: the reviewed schedule revision a CLINIC cancellation must carry
-- (SPEC-APT-003 BR-24); always NULL for a GUARDIAN cancellation.
create function pg_temp.cancel(p_appointment uuid, p_context text, p_reason text, p_sequence integer default null)
returns void language plpgsql as $$
begin
    perform public.cancel_appointment(p_appointment, p_context, p_reason, p_sequence);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.reschedule(p_appointment uuid, p_date date, p_time time)
returns void language plpgsql as $$
begin
    perform public.reschedule_requested_appointment(p_appointment, p_date, p_time, 3600);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.confirm(p_appointment uuid, p_sequence integer)
returns void language plpgsql as $$
begin
    perform public.confirm_appointment(p_appointment, p_sequence);
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

create function pg_temp.clinical_entry(p_appointment uuid)
returns uuid language plpgsql security definer as $$
declare created uuid;
begin
    created := pg_temp.record_entry(p_appointment, 'e1a00000-0000-4000-8000-000000000815'::uuid);
    perform pg_temp.flush();
    return created;
end;
$$;

-- SPEC-APT-009: stale-safe lightweight completion.
create function pg_temp.complete(p_appointment uuid, p_expected_confirmed_sequence integer)
returns void language plpgsql as $$
begin
    perform public.complete_appointment(p_appointment, p_expected_confirmed_sequence);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.no_show(p_appointment uuid, p_expected_confirmed_sequence integer)
returns void language plpgsql as $$
begin
    perform public.mark_appointment_no_show(p_appointment, p_expected_confirmed_sequence);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.expire(p_reference timestamptz)
returns integer language plpgsql as $$
declare expired integer;
begin
    expired := public.expire_lapsed_appointment_requests(p_reference);
    perform pg_temp.flush();
    return expired;
end;
$$;

-- Pre-care access through the client history read (SPEC-MED-005 §15), keyed
-- by Clinic and Appointment.
create function pg_temp.pre_care_status(p_clinic uuid, p_appointment uuid)
returns text language sql as $$
    select public.view_appointment_professional_medical_history(p_clinic, p_appointment) ->> 'status'
$$;

-- Every persisted fact an Appointment operation could touch.
create function pg_temp.fingerprint(p_appointment uuid)
returns text language sql as $$
    select md5(
        coalesce((select appointment::text from public.appointments as appointment
                  where appointment.id = p_appointment), '')
        || '#' || coalesce((select string_agg(revision::text, '|' order by revision.revision_sequence)
                  from public.appointment_schedule_revisions as revision
                  where revision.appointment_id = p_appointment), '')
        || '#' || coalesce((select string_agg(lifecycle_event::text, '|' order by lifecycle_event.id)
                  from public.appointment_lifecycle_events as lifecycle_event
                  where lifecycle_event.appointment_id = p_appointment), '')
        || '#' || coalesce((select string_agg(care_auth::text, '|' order by care_auth.id)
                  from public.care_authorizations as care_auth
                  where care_auth.appointment_id = p_appointment), '')
        || '#' || coalesce((select string_agg(communication::text, '|' order by communication.id)
                  from public.transactional_communications as communication
                  where communication.appointment_id = p_appointment), '')
    )
$$;

create temporary table remembered (
    label text primary key,
    fingerprint text not null,
    total_appointments bigint not null,
    total_care_authorizations bigint not null,
    total_communications bigint not null
) on commit drop;

create function pg_temp.remember(p_label text, p_appointment uuid)
returns void language sql as $$
    insert into remembered values (
        p_label, pg_temp.fingerprint(p_appointment),
        (select count(*) from public.appointments),
        (select count(*) from public.care_authorizations),
        (select count(*) from public.transactional_communications)
    )
$$;

create function pg_temp.unchanged(p_label text, p_appointment uuid)
returns boolean language sql as $$
    select pg_temp.fingerprint(p_appointment) = before.fingerprint
       and (select count(*) from public.appointments) = before.total_appointments
       and (select count(*) from public.care_authorizations) = before.total_care_authorizations
       and (select count(*) from public.transactional_communications) = before.total_communications
    from remembered as before where before.label = p_label
$$;

create function pg_temp.state(p_appointment uuid) returns text language sql as $$
    select lifecycle_state from public.appointments where id = p_appointment
$$;

-- ===========================================================================
-- 1. Contract: new internal operations are not client-callable; the
--    lifecycle and Care Authorization catalogs include the new values.
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(not has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                     and not has_function_privilege('anon', proc.oid, 'EXECUTE'))
     from pg_proc as proc
     where proc.oid in ('public.expire_lapsed_appointment_requests(timestamptz)'::regprocedure,
                        'public.appointment_latest_requested_start_at(uuid)'::regprocedure,
                        'public.appointment_is_pending_request(uuid, timestamptz)'::regprocedure,
                        'public.appointment_permits_pre_care_access(uuid, timestamptz)'::regprocedure))
    and has_function_privilege('authenticated', 'public.request_appointment(uuid, uuid, date, time, integer, text, text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.cancel_appointment(uuid, text, text, integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.reschedule_requested_appointment(uuid, date, time, integer)', 'EXECUTE')
    -- Stage M4 replaced the multi-context download authorizer with the Guardian one.
    and not has_function_privilege('authenticated', 'public.authorize_guardian_clinical_attachment_download(uuid, uuid)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.authorize_guardian_clinical_attachment_download(uuid, uuid)', 'EXECUTE'),
    'ACL: expiry and its predicates are internal; replaced RPCs keep their original grants'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects e1a00000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian G1 of Luna, Max, Kira    04 Org RECEPTIONIST (Org scope)
--   02 Guardian G2 of Luna               05 Veterinarian V1 @ A1 and A2
-- Organization 0301 (ACTIVE). Clinics A1 0401, A2 0402: Europe/Madrid,
-- 30-minute standard duration, Availability 08:00–20:00 every weekday.
-- Pets: Luna a01, Max a02, Kira a03. Appointment n has Care Authorization
-- c<n>. Past times are 2026, future times 2035 (CET, +01:00).
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('e1a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 5) as n;
insert into public.users (id) select pg_temp.domain_user(n) from generate_series(1, 5) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('e1a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 5) as n;

insert into public.veterinary_organizations (id, display_name)
values ('e1a00000-0000-4000-8000-000000000301', 'Animalia Veterinary Group');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.a1(), 'e1a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30),
       (pg_temp.a2(), 'e1a00000-0000-4000-8000-000000000301', true, 'Europe/Madrid', 30);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select clinic_id, weekday, '08:00', '20:00'
from unnest(array[pg_temp.a1(), pg_temp.a2()]) as clinic_id, generate_series(1, 7) as weekday;

insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    ('e1a00000-0000-4000-8000-000000000504', 'e1a00000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z'),
    ('e1a00000-0000-4000-8000-000000000505', 'e1a00000-0000-4000-8000-000000000301', pg_temp.domain_user(5), '2020-01-01Z');

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values
    ('e1a00000-0000-4000-8000-000000000604', 'e1a00000-0000-4000-8000-000000000504', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4)),
    ('e1a00000-0000-4000-8000-000000000605', 'e1a00000-0000-4000-8000-000000000505', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.domain_user(4));

insert into public.veterinarian_professional_profiles (id, user_id)
values ('e1a00000-0000-4000-8000-000000000705', pg_temp.domain_user(5));

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start
) values
    ('e1a00000-0000-4000-8000-000000000815', 'e1a00000-0000-4000-8000-000000000705', 'e1a00000-0000-4000-8000-000000000505', pg_temp.a1(), '2020-01-01Z'),
    ('e1a00000-0000-4000-8000-000000000825', 'e1a00000-0000-4000-8000-000000000705', 'e1a00000-0000-4000-8000-000000000505', pg_temp.a2(), '2020-01-01Z');

insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time)
select 'e1a00000-0000-4000-8000-000000000815'::uuid, weekday, '08:00', '20:00' from generate_series(1, 7) as weekday;

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values (
    'e1a00000-0000-4000-8000-000000000901', 'e1a00000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',
    '2020-01-01Z', null, null, 'spec-apt-015-test', 'e1a00000-0000-4000-8000-000000000991'
);

insert into public.pets (id, name, species, created_at) values
    (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z'),
    (pg_temp.max(), 'Max', 'Dog', '2020-01-01Z'),
    (pg_temp.kira(), 'Kira', 'Cat', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start) values
    ('e1a00000-0000-4000-8000-000000000a11', pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z'),
    ('e1a00000-0000-4000-8000-000000000a12', pg_temp.domain_user(2), pg_temp.luna(), '2020-01-01Z'),
    ('e1a00000-0000-4000-8000-000000000a13', pg_temp.domain_user(1), pg_temp.max(), '2020-01-01Z'),
    ('e1a00000-0000-4000-8000-000000000a14', pg_temp.domain_user(1), pg_temp.kira(), '2020-01-01Z');

-- One Appointment with its initial REQUESTED revision and ACTIVE
-- Appointment-derived Care Authorization, requested on 2026-01-01.
create function pg_temp.seed(p_n integer, p_pet uuid, p_clinic uuid, p_start timestamptz, p_state text)
returns void language sql as $$
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(p_n), p_pet, p_clinic, pg_temp.domain_user(1), 'Visit ' || p_n, p_state,
            '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) values (pg_temp.appt(p_n), 1, 'REQUESTED', p_start, p_start + interval '30 minutes', 'Europe/Madrid',
              pg_temp.domain_user(1), null, '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) select pg_temp.ca(p_n), p_pet, p_clinic, 'e1a00000-0000-4000-8000-000000000301', guardianship.id,
             '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => p_n), 'APPOINTMENT_CARE', pg_temp.appt(p_n), 'ACTIVE'
      from public.guardianships as guardianship
      where guardianship.pet_id = p_pet and guardianship.user_id = pg_temp.domain_user(1);
$$;

-- Adds a CONFIRMED revision and the confirmation Event.
create function pg_temp.seed_confirmation(p_n integer)
returns void language sql as $$
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
    ) select pg_temp.appt(p_n), 2, 'CONFIRMED', revision.scheduled_start_at, revision.scheduled_end_at,
             revision.establishment_timezone_name, pg_temp.domain_user(4), null, '2026-02-01T00:00:00Z'
      from public.appointment_schedule_revisions as revision
      where revision.appointment_id = pg_temp.appt(p_n) and revision.revision_sequence = 1;
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
    ) values (pg_temp.appt(p_n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(4), 'CLINIC', null,
              '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z');
$$;

-- --- Expiry fixtures (Kira @ A1). T1 = 2026-06-01T10:00Z.
select pg_temp.seed(1, pg_temp.kira(), pg_temp.a1(), '2026-06-01T10:00Z', 'REQUESTED');  -- start == T1
select pg_temp.seed(2, pg_temp.kira(), pg_temp.a1(), '2026-06-01T09:00Z', 'REQUESTED');  -- start <  T1
select pg_temp.seed(3, pg_temp.kira(), pg_temp.a1(), '2026-06-01T11:00Z', 'REQUESTED');  -- start >  T1
select pg_temp.seed(4, pg_temp.kira(), pg_temp.a1(), '2026-05-01T10:00Z', 'REQUESTED');  -- revision 1 past T1 ...
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
) values (pg_temp.appt(4), 2, 'REQUESTED', '2026-06-01T12:00Z', '2026-06-01T12:30Z', 'Europe/Madrid',
          pg_temp.domain_user(1), null, '2026-03-01T00:00Z');                             -- ... latest after T1
select pg_temp.seed(5, pg_temp.kira(), pg_temp.a1(), '2026-05-15T10:00Z', 'CONFIRMED');
select pg_temp.seed_confirmation(5);
select pg_temp.seed(6, pg_temp.kira(), pg_temp.a1(), '2026-05-15T10:00Z', 'CANCELLED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(6), 'REQUESTED', 'CANCELLED', pg_temp.domain_user(1), 'GUARDIAN', null, '2026-03-01T00:00Z', '2026-03-01T00:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-03-01T00:00Z', ended_reason = 'APPOINTMENT_CANCELLED'
where id = pg_temp.ca(6);
select pg_temp.seed(7, pg_temp.kira(), pg_temp.a1(), '2026-05-15T10:00Z', 'COMPLETED');
select pg_temp.seed_confirmation(7);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(7), 'CONFIRMED', 'COMPLETED', pg_temp.domain_user(4), 'CLINIC', null, '2026-05-15T11:00Z', '2026-05-15T11:00Z');
select pg_temp.seed(8, pg_temp.kira(), pg_temp.a1(), '2026-05-15T10:00Z', 'NO_SHOW');
select pg_temp.seed_confirmation(8);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(8), 'CONFIRMED', 'NO_SHOW', pg_temp.domain_user(4), 'CLINIC', null, '2026-05-15T11:00Z', '2026-05-15T11:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-05-15T11:00Z', ended_reason = 'APPOINTMENT_NO_SHOW'
where id = pg_temp.ca(8);
select pg_temp.seed(9, pg_temp.kira(), pg_temp.a1(), '2026-05-15T10:00Z', 'EXPIRED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(9), 'REQUESTED', 'EXPIRED', null, 'SYSTEM', null, '2026-05-15T10:00Z', '2026-05-15T10:05Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-05-15T10:00Z', ended_reason = 'APPOINTMENT_EXPIRED'
where id = pg_temp.ca(9);
select pg_temp.seed(10, pg_temp.kira(), pg_temp.a1(), '2026-05-20T10:00Z', 'REQUESTED');  -- authorization REVOKED
update public.care_authorizations set lifecycle_state = 'REVOKED', revoked_at = '2026-02-01T00:00Z',
       revoking_user_id = pg_temp.domain_user(1), revocation_reason = 'No longer needed'
where id = pg_temp.ca(10);

-- --- Security fixtures (Kira @ A2).
select pg_temp.seed(20, pg_temp.kira(), pg_temp.a2(), '2035-03-06T09:00Z', 'REQUESTED');
select pg_temp.seed(21, pg_temp.kira(), pg_temp.a2(), '2026-07-01T09:00Z', 'REQUESTED');
select pg_temp.seed(22, pg_temp.kira(), pg_temp.a2(), '2035-03-06T09:00Z', 'CONFIRMED');
select pg_temp.seed_confirmation(22);

-- --- Cancellation / rescheduling fixtures (Kira @ A2).
select pg_temp.seed(30, pg_temp.kira(), pg_temp.a2(), '2035-03-07T09:00Z', 'REQUESTED');  -- Guardian cancels
select pg_temp.seed(31, pg_temp.kira(), pg_temp.a2(), '2035-03-07T10:00Z', 'REQUESTED');  -- Clinic cancels
select pg_temp.seed(32, pg_temp.kira(), pg_temp.a2(), '2026-07-01T10:00Z', 'REQUESTED');  -- lapsed, Guardian
select pg_temp.seed(33, pg_temp.kira(), pg_temp.a2(), '2026-07-01T11:00Z', 'REQUESTED');  -- lapsed, Clinic
select pg_temp.seed(35, pg_temp.kira(), pg_temp.a2(), '2035-03-07T11:00Z', 'CONFIRMED');  -- confirmed cancel
select pg_temp.seed_confirmation(35);
select pg_temp.seed(40, pg_temp.kira(), pg_temp.a2(), '2035-03-08T09:00Z', 'REQUESTED');  -- reschedulable
select pg_temp.seed(41, pg_temp.kira(), pg_temp.a2(), '2026-07-01T12:00Z', 'REQUESTED');  -- lapsed reschedule

-- --- Pending-request fixtures.
select pg_temp.seed(43, pg_temp.luna(), pg_temp.a2(), '2026-07-01T09:00Z', 'REQUESTED');  -- lapsed only
select pg_temp.seed(50, pg_temp.max(), pg_temp.a1(), '2035-03-09T09:00Z', 'CONFIRMED');
select pg_temp.seed_confirmation(50);
select pg_temp.seed(51, pg_temp.max(), pg_temp.a1(), '2035-03-09T10:00Z', 'CANCELLED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(51), 'REQUESTED', 'CANCELLED', pg_temp.domain_user(1), 'GUARDIAN', null, '2026-03-01T00:00Z', '2026-03-01T00:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-03-01T00:00Z', ended_reason = 'APPOINTMENT_CANCELLED'
where id = pg_temp.ca(51);
select pg_temp.seed(52, pg_temp.max(), pg_temp.a1(), '2026-05-15T10:00Z', 'COMPLETED');
select pg_temp.seed_confirmation(52);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(52), 'CONFIRMED', 'COMPLETED', pg_temp.domain_user(4), 'CLINIC', null, '2026-05-15T11:00Z', '2026-05-15T11:00Z');
select pg_temp.seed(53, pg_temp.max(), pg_temp.a1(), '2026-05-15T10:00Z', 'NO_SHOW');
select pg_temp.seed_confirmation(53);
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(53), 'CONFIRMED', 'NO_SHOW', pg_temp.domain_user(4), 'CLINIC', null, '2026-05-15T11:00Z', '2026-05-15T11:00Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-05-15T11:00Z', ended_reason = 'APPOINTMENT_NO_SHOW'
where id = pg_temp.ca(53);
select pg_temp.seed(54, pg_temp.max(), pg_temp.a1(), '2026-05-15T10:00Z', 'EXPIRED');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at)
values (pg_temp.appt(54), 'REQUESTED', 'EXPIRED', null, 'SYSTEM', null, '2026-05-15T10:00Z', '2026-05-15T10:05Z');
update public.care_authorizations set lifecycle_state = 'ENDED', ended_at = '2026-05-15T10:00Z', ended_reason = 'APPOINTMENT_EXPIRED'
where id = pg_temp.ca(54);
select pg_temp.seed(55, pg_temp.max(), pg_temp.a1(), '2026-07-01T09:00Z', 'REQUESTED');  -- lapsed

-- --- Clinical documentation fixtures (Kira @ A1).
select pg_temp.seed(60, pg_temp.kira(), pg_temp.a1(), '2035-03-10T09:00Z', 'REQUESTED');
select pg_temp.seed(61, pg_temp.kira(), pg_temp.a1(), '2026-07-01T09:00Z', 'REQUESTED');
select pg_temp.seed(62, pg_temp.kira(), pg_temp.a1(), '2035-03-10T10:00Z', 'REQUESTED');  -- confirmed in-suite
select pg_temp.seed(63, pg_temp.kira(), pg_temp.a1(), '2035-03-10T11:00Z', 'REQUESTED');

set local session_replication_role = origin;

-- Snapshot of every terminal fixture and of the communication outbox.
select pg_temp.remember('terminal ' || n, pg_temp.appt(n)) from unnest(array[5, 6, 7, 8, 9]) as n;

-- ===========================================================================
-- 2. Lifecycle Event actor model (cases 13–14).
-- ===========================================================================

select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, effective_at, recorded_at) values (%L, ''REQUESTED'', ''CANCELLED'', null, ''CLINIC'', now(), now())', pg_temp.appt(20)),
    '23514', 'appointment_lifecycle_events_actor_user_shape_check'
);
select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, effective_at, recorded_at) values (%L, ''REQUESTED'', ''CANCELLED'', null, ''GUARDIAN'', now(), now())', pg_temp.appt(20)),
    '23514', 'appointment_lifecycle_events_actor_user_shape_check'
);
select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, effective_at, recorded_at) values (%L, ''REQUESTED'', ''EXPIRED'', %L, ''SYSTEM'', now(), now())', pg_temp.appt(20), pg_temp.domain_user(4)),
    '23514', 'appointment_lifecycle_events_actor_user_shape_check'
);
select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, effective_at, recorded_at) values (%L, ''REQUESTED'', ''CONFIRMED'', null, ''SYSTEM'', now(), now())', pg_temp.appt(20)),
    '23514', 'appointment_lifecycle_events_system_expiry_check'
);
-- SYSTEM is never a cancellation actor either (pre-existing check).
select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, effective_at, recorded_at) values (%L, ''REQUESTED'', ''CANCELLED'', null, ''SYSTEM'', now(), now())', pg_temp.appt(20)),
    '23514', 'appointment_lifecycle_events_cancellation_actor_context_check'
);
select pg_temp.assert_error(
    format('insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context, effective_at, recorded_at) values (%L, ''CONFIRMED'', ''EXPIRED'', null, ''SYSTEM'', now(), now())', pg_temp.appt(22)),
    '23514', 'appointment_lifecycle_events_transition_check'
);
select pg_temp.assert_error(
    format('update public.appointments set lifecycle_state = ''EXPIRED'' where id = %L', pg_temp.appt(22)),
    '23514', 'Unsupported Appointment lifecycle transition'
);

-- ===========================================================================
-- 3. Immediate pre-care access cutoff, before any expiry run (cases 20–23).
-- ===========================================================================

select pg_temp.act(5);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pre_care_status(pg_temp.a2(), pg_temp.appt(20)) = 'PERMITTED',
    'Case 20: a future REQUESTED Appointment supports pre-care access'
);
select pg_temp.assert_true(
    pg_temp.pre_care_status(pg_temp.a2(), pg_temp.appt(21)) = 'DENIED',
    'Case 21: a REQUESTED Appointment whose start has passed no longer grants pre-care access before any expiry run'
);
select pg_temp.assert_true(
    pg_temp.pre_care_status(pg_temp.a2(), pg_temp.appt(22)) = 'PERMITTED',
    'Case 22: CONFIRMED Appointment-derived pre-care access is unchanged'
);
reset role;

select pg_temp.assert_true(
    pg_temp.state(pg_temp.appt(21)) = 'REQUESTED'
    and (select lifecycle_state = 'ACTIVE' from public.care_authorizations where id = pg_temp.ca(21))
    and public.appointment_permits_pre_care_access(pg_temp.appt(20), clock_timestamp())
    and not public.appointment_permits_pre_care_access(pg_temp.appt(21), clock_timestamp())
    and public.appointment_permits_pre_care_access(pg_temp.appt(22), clock_timestamp()),
    'Case 21: the cutoff is logical — the Appointment is still stored REQUESTED with an ACTIVE authorization'
);

-- Case 23: Clinical Intake is unaffected. The CLINICAL_INTAKE grant is a
-- trusted operation since 20261106090000 (SPEC-ACC-002 BR-62), called here
-- as its owner for the Guardian.
select pg_temp.act(1);
insert into produced select 'intake', public.grant_pet_care_authorization(pg_temp.kira(), pg_temp.a1());
select pg_temp.flush();

select pg_temp.assert_true(
    (select lifecycle_state = 'ACTIVE' and purpose = 'CLINICAL_INTAKE' and appointment_id is null
     from public.care_authorizations where id = pg_temp.produced('intake')),
    'Case 23: a Clinical Intake authorization without Appointment remains valid while REQUESTED Appointments exist for the Pet'
);

-- ===========================================================================
-- 4. Cancellation (cases 24–28, 31) before any expiry run.
-- ===========================================================================

select pg_temp.remember('b32', pg_temp.appt(32));
select pg_temp.remember('b33', pg_temp.appt(33));

select pg_temp.act(1);
set local role authenticated;
select pg_temp.cancel(pg_temp.appt(30), 'GUARDIAN', null);
select pg_temp.assert_error(
    format('select pg_temp.cancel(%L, ''GUARDIAN'', null)', pg_temp.appt(32)),
    '23514', 'A REQUESTED Appointment whose requested time has passed cannot be cancelled'
);
reset role;

select pg_temp.act(4);
set local role authenticated;
select pg_temp.cancel(pg_temp.appt(31), 'CLINIC', 'Clinic closed that day', 1);
select pg_temp.assert_error(
    format('select pg_temp.cancel(%L, ''CLINIC'', ''Too late'', 1)', pg_temp.appt(33)),
    '23514', 'A REQUESTED Appointment whose requested time has passed cannot be cancelled'
);
select pg_temp.cancel(pg_temp.appt(35), 'CLINIC', 'Veterinarian unavailable', 2);
reset role;

select pg_temp.assert_true(
    pg_temp.state(pg_temp.appt(30)) = 'CANCELLED'
    and pg_temp.state(pg_temp.appt(31)) = 'CANCELLED'
    and (select ended_reason = 'APPOINTMENT_CANCELLED' from public.care_authorizations where id = pg_temp.ca(30))
    and (select count(*) = 1 from public.transactional_communications
         where appointment_id = pg_temp.appt(30) and communication_type = 'APPOINTMENT_CANCELLED'),
    'Cases 24/25: future REQUESTED Guardian and Clinic cancellations succeed normally'
);

select pg_temp.assert_true(
    -- Per-Appointment fingerprints (state, revisions, Events, authorization,
    -- Communications); the global counts legitimately moved with the
    -- successful cancellations in this section.
    (select fingerprint from remembered where label = 'b32') = pg_temp.fingerprint(pg_temp.appt(32))
    and pg_temp.state(pg_temp.appt(32)) = 'REQUESTED'
    and pg_temp.state(pg_temp.appt(33)) = 'REQUESTED'
    and (select fingerprint from remembered where label = 'b33') = pg_temp.fingerprint(pg_temp.appt(33))
    and not exists (select 1 from public.transactional_communications
                    where appointment_id in (pg_temp.appt(32), pg_temp.appt(33))),
    'Cases 26/27/28: lapsed Guardian and Clinic cancellations are rejected with zero writes and no Communication'
);

select pg_temp.assert_true(
    pg_temp.state(pg_temp.appt(35)) = 'CANCELLED',
    'Case 31: CONFIRMED cancellation is unchanged'
);

-- ===========================================================================
-- 5. Rescheduling (cases 32–33) before any expiry run.
-- ===========================================================================

select pg_temp.remember('b41', pg_temp.appt(41));

select pg_temp.act(1);
set local role authenticated;
select pg_temp.reschedule(pg_temp.appt(40), '2035-03-08', '12:00');
select pg_temp.assert_error(
    format('select pg_temp.reschedule(%L, ''2035-03-09'', ''10:00'')', pg_temp.appt(41)),
    '23514', 'A REQUESTED Appointment whose requested time has passed cannot be rescheduled'
);
reset role;

select pg_temp.assert_true(
    (select count(*) = 2 from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(40))
    and pg_temp.unchanged('b41', pg_temp.appt(41)),
    'Cases 32/33: a future REQUESTED reschedule succeeds; a lapsed one is rejected with zero writes'
);

-- ===========================================================================
-- 6. Pending-request policy (cases 35–49), before any expiry run.
-- ===========================================================================

select pg_temp.act(1);
set local role authenticated;
select pg_temp.request('luna a1', pg_temp.luna(), pg_temp.a1(), '2035-03-10', '10:00');
reset role;

select pg_temp.remember('after first pending', pg_temp.produced('luna a1'));

select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.request(null, %L, %L, ''2035-03-11'', ''10:00'')', pg_temp.luna(), pg_temp.a1()),
    '23514', 'A pending Appointment request already exists for this Pet at this Clinic'
);
reset role;

select pg_temp.act(2);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.request(null, %L, %L, ''2035-03-12'', ''10:00'')', pg_temp.luna(), pg_temp.a1()),
    '23514', 'A pending Appointment request already exists for this Pet at this Clinic'
);
reset role;

select pg_temp.assert_true(
    pg_temp.unchanged('after first pending', pg_temp.produced('luna a1'))
    and (select count(*) = 1 from public.appointments
         where pet_id = pg_temp.luna() and clinic_id = pg_temp.a1()),
    'Cases 36/37/38/40: the second pending request (same or other Guardian) is rejected with no Appointment, Care Authorization, history, or Communication'
);

-- Max @ A1 holds CONFIRMED, CANCELLED, COMPLETED, NO_SHOW, EXPIRED, and a
-- lapsed REQUESTED — none blocks (cases 41–46). Different Pet (48).
select pg_temp.assert_true(
    not public.appointment_is_pending_request(pg_temp.appt(50), clock_timestamp())
    and not public.appointment_is_pending_request(pg_temp.appt(51), clock_timestamp())
    and not public.appointment_is_pending_request(pg_temp.appt(52), clock_timestamp())
    and not public.appointment_is_pending_request(pg_temp.appt(53), clock_timestamp())
    and not public.appointment_is_pending_request(pg_temp.appt(54), clock_timestamp())
    and not public.appointment_is_pending_request(pg_temp.appt(55), clock_timestamp())
    and pg_temp.state(pg_temp.appt(55)) = 'REQUESTED'
    and public.appointment_is_pending_request(pg_temp.produced('luna a1'), clock_timestamp()),
    'Cases 41–46: CONFIRMED, CANCELLED, COMPLETED, NO_SHOW, EXPIRED, and lapsed REQUESTED are never pending requests'
);

select pg_temp.act(1);
set local role authenticated;
select pg_temp.request('max a1', pg_temp.max(), pg_temp.a1(), '2035-03-10', '11:00');
-- Luna @ A2 holds only a lapsed REQUESTED; a different Clinic from the
-- pending Luna @ A1 request (cases 35, 42, 47).
select pg_temp.request('luna a2', pg_temp.luna(), pg_temp.a2(), '2035-03-10', '11:00');
-- The one pending request remains reschedulable (case 49).
select pg_temp.reschedule(pg_temp.produced('luna a1'), '2035-03-10', '15:00');
reset role;

select pg_temp.assert_true(
    pg_temp.state(pg_temp.produced('max a1')) = 'REQUESTED'
    and pg_temp.state(pg_temp.produced('luna a2')) = 'REQUESTED'
    and pg_temp.state(pg_temp.appt(43)) = 'REQUESTED'
    and (select count(*) = 2 from public.appointment_schedule_revisions where appointment_id = pg_temp.produced('luna a1'))
    and (select count(*) = 1 from public.care_authorizations where appointment_id = pg_temp.produced('max a1'))
    and (select count(*) = 1 from public.care_authorizations where appointment_id = pg_temp.produced('luna a2')),
    'Cases 35/41–49: non-blocking states, a lapsed request before any expiry run, another Clinic, and another Pet all allow a new request; the pending request stays reschedulable'
);

-- ===========================================================================
-- 7. Clinical documentation regression (cases 54+, SPEC-MED-010 BR-3).
-- ===========================================================================

-- A REQUESTED Appointment, future (60) or lapsed (61), is not documentable
-- even with an assigned Veterinarian.
select pg_temp.act(5);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.clinical_entry(%L)', pg_temp.appt(60)),
    '23514', 'A Clinical Record Entry requires a legitimately confirmed CONFIRMED or COMPLETED Appointment'
);
select pg_temp.assert_error(
    format('select pg_temp.clinical_entry(%L)', pg_temp.appt(61)),
    '23514', 'A Clinical Record Entry requires a legitimately confirmed CONFIRMED or COMPLETED Appointment'
);
reset role;

select pg_temp.act(4);
set local role authenticated;
select pg_temp.confirm(pg_temp.appt(62), 1);
reset role;

-- Once CONFIRMED, its assigned Veterinarian records Entries; a Clinic
-- Assignment of another Clinic cannot.
select pg_temp.act(5);
set local role authenticated;
select pg_temp.clinical_entry(pg_temp.appt(62));
select pg_temp.clinical_entry(pg_temp.appt(62));
select pg_temp.assert_error(
    format('select pg_temp.record_entry(%L, %L)', pg_temp.appt(62), 'e1a00000-0000-4000-8000-000000000825'),
    '23514', null
);
reset role;

select pg_temp.act(4);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.cancel(%L, ''CLINIC'', ''Changed plans'', 2)', pg_temp.appt(62)),
    '23514', 'Appointment with clinical documentation cannot be cancelled'
);
select pg_temp.assert_error(
    format('select pg_temp.no_show(%L, 2)', pg_temp.appt(62)),
    '23514', 'Appointment with clinical documentation cannot be marked no-show'
);
-- Early care does not allow early completion (SPEC-APT-009 BR-7): clinical
-- documentation neither blocks nor enables completion, and the confirmed start
-- (2035) has not been reached.
select pg_temp.assert_error(
    format('select pg_temp.complete(%L, 2)', pg_temp.appt(62)),
    '23514', 'Appointment cannot be completed before its confirmed scheduled start'
);
reset role;

select pg_temp.assert_true(
    pg_temp.state(pg_temp.appt(60)) = 'REQUESTED'
    and pg_temp.state(pg_temp.appt(62)) = 'CONFIRMED'
    and (select count(*) = 2 from public.clinical_record_entries where appointment_id = pg_temp.appt(62))
    and not exists (select 1 from public.clinical_record_entries where appointment_id in (pg_temp.appt(60), pg_temp.appt(61), pg_temp.appt(63))),
    'Documentation regression: REQUESTED (future or past) Appointments are not documentable; a CONFIRMED one accepts its assigned Veterinarian''s Entries only, which block cancel and no-show and do not allow completion before the confirmed start'
);

-- ===========================================================================
-- 8. Materialization in stages (cases 1–19).
-- ===========================================================================

create temporary table run_counts (label text primary key, expired integer) on commit drop;

-- Stage T1 = 2026-06-01T10:00Z: start == T1 and start < T1 expire.
select pg_temp.remember('b03', pg_temp.appt(3));
select pg_temp.remember('b04', pg_temp.appt(4));
insert into run_counts values ('T1', pg_temp.expire('2026-06-01T10:00Z'));

select pg_temp.assert_true(
    (select expired = 3 from run_counts where label = 'T1')
    and pg_temp.state(pg_temp.appt(1)) = 'EXPIRED'
    and pg_temp.state(pg_temp.appt(2)) = 'EXPIRED'
    and pg_temp.state(pg_temp.appt(10)) = 'EXPIRED'
    and pg_temp.unchanged('b03', pg_temp.appt(3))
    and pg_temp.unchanged('b04', pg_temp.appt(4)),
    'Cases 1/2/3/4: at T1 exactly start == T1 and start < T1 expire; start > T1 and a request whose LATEST revision is after T1 are untouched'
);

select pg_temp.assert_true(
    (select count(*) = 1 from public.appointment_lifecycle_events
     where appointment_id = pg_temp.appt(1) and from_state = 'REQUESTED' and to_state = 'EXPIRED'
       and actor_context = 'SYSTEM' and actor_user_id is null and reason is null
       and effective_at = '2026-06-01T10:00Z' and recorded_at > effective_at)
    and (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(1)),
    'Cases 6/13/15: exactly one SYSTEM REQUESTED → EXPIRED Event with no User; logical instant 10:00Z, recorded later'
);

select pg_temp.assert_true(
    (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_EXPIRED' and ended_at = '2026-06-01T10:00Z'
     from public.care_authorizations where id = pg_temp.ca(1))
    and (select lifecycle_state = 'REVOKED' and ended_reason is null and revoked_at = '2026-02-01T00:00Z'
         from public.care_authorizations where id = pg_temp.ca(10))
    and (select count(*) = 1 and bool_and(revision_context = 'REQUESTED')
         from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(1)),
    'Cases 16/18/19: the authorization ends with APPOINTMENT_EXPIRED at the logical instant; a REVOKED one is untouched; revisions are unchanged'
);

-- Stage T2 = 2026-06-01T12:00Z: the latest REQUESTED revision decides.
insert into run_counts values ('T2', pg_temp.expire('2026-06-01T12:00Z'));
select pg_temp.remember('after T2 b04', pg_temp.appt(4));
insert into run_counts values ('T2 rerun', pg_temp.expire('2026-06-01T12:00Z'));

select pg_temp.assert_true(
    (select expired = 2 from run_counts where label = 'T2')
    and (select expired = 0 from run_counts where label = 'T2 rerun')
    and pg_temp.unchanged('after T2 b04', pg_temp.appt(4))
    and (select effective_at = '2026-06-01T12:00Z' from public.appointment_lifecycle_events
         where appointment_id = pg_temp.appt(4) and to_state = 'EXPIRED')
    and (select count(*) = 2 from public.appointment_schedule_revisions where appointment_id = pg_temp.appt(4)),
    'Cases 4/7/16: the latest REQUESTED revision (12:00Z) is the logical instant, and a second run is a no-op'
);

select pg_temp.assert_error(
    'select pg_temp.expire(clock_timestamp() + interval ''1 day'')',
    '22023', 'Expiry reference time must not be in the future'
);

-- Interleavings with logical time, before the current-time run
-- (expiry vs confirm / cancel / reschedule): the request is past, so every
-- operation is rejected and EXPIRED is the only outcome.
select pg_temp.remember('b21 pre', pg_temp.appt(21));
select pg_temp.act(4);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.confirm(%L, 1)', pg_temp.appt(21)),
    '23514', 'A past requested Appointment cannot be confirmed'
);
reset role;

-- Stage "now": every remaining lapsed REQUESTED expires; terminal fixtures,
-- future requests, and CONFIRMED stay untouched.
insert into run_counts values ('now', pg_temp.expire(clock_timestamp()));

select pg_temp.assert_true(
    not exists (
        select 1 from public.appointments as appointment
        where appointment.id::text like 'e1a00000-%'
          and appointment.lifecycle_state = 'REQUESTED'
          and public.appointment_latest_requested_start_at(appointment.id) <= clock_timestamp()
    )
    and (select array_agg(n order by n) from unnest(array[21, 32, 33, 41, 43, 55, 61]) as n
         where pg_temp.state(pg_temp.appt(n)) = 'EXPIRED')
        = array[21, 32, 33, 41, 43, 55, 61]
    and (select expired = 7 from run_counts where label = 'now')
    and pg_temp.state(pg_temp.appt(20)) = 'REQUESTED'
    and pg_temp.state(pg_temp.appt(22)) = 'CONFIRMED'
    and pg_temp.state(pg_temp.appt(40)) = 'REQUESTED',
    'Cases 1/5/29: a current-time run expires every lapsed request (legacy-style rows included) and leaves future and CONFIRMED Appointments'
);

select pg_temp.assert_true(
    (select bool_and(before.fingerprint = pg_temp.fingerprint(pg_temp.appt(n)))
     from unnest(array[5, 6, 7, 8, 9]) as n
     join remembered as before on before.label = 'terminal ' || n),
    'Cases 8/9/10/11/12: CONFIRMED, CANCELLED, COMPLETED, NO_SHOW, and already EXPIRED Appointments are untouched by every run'
);

select pg_temp.assert_true(
    not exists (
        select 1 from public.transactional_communications as communication
        join public.appointment_lifecycle_events as lifecycle_event
          on lifecycle_event.id = communication.appointment_lifecycle_event_id
        where lifecycle_event.to_state = 'EXPIRED'
    )
    and not exists (
        select 1 from public.transactional_communications as communication
        where communication.appointment_id in (
            select appointment_id from public.appointment_lifecycle_events where to_state = 'EXPIRED'
        )
    ),
    'Case 17: expiry creates no Communication of any type'
);

select pg_temp.assert_true(
    (select bool_and(event.effective_at = public.appointment_latest_requested_start_at(event.appointment_id)
                     and event.recorded_at >= event.effective_at
                     and care_auth.lifecycle_state = 'ENDED'
                     and care_auth.ended_reason = 'APPOINTMENT_EXPIRED'
                     and care_auth.ended_at = event.effective_at)
     from public.appointment_lifecycle_events as event
     join public.care_authorizations as care_auth on care_auth.appointment_id = event.appointment_id
     where event.to_state = 'EXPIRED' and event.appointment_id <> pg_temp.appt(10)
       and event.appointment_id::text like 'e1a00000-%'),
    'Legacy reconciliation: every materialized expiry keeps the original requested start as logical instant and ends its authorization there'
);

-- ===========================================================================
-- 9. After materialization: terminality and reads (cases 30, 34, 50–53).
-- ===========================================================================

select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.cancel(%L, ''GUARDIAN'', null)', pg_temp.appt(32)),
    '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled'
);
select pg_temp.assert_error(
    format('select pg_temp.reschedule(%L, ''2035-03-09'', ''10:00'')', pg_temp.appt(41)),
    '23514', 'Only a REQUESTED Appointment may be rescheduled'
);
reset role;

select pg_temp.act(4);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.cancel(%L, ''CLINIC'', ''Too late'', 1)', pg_temp.appt(33)),
    '23514', 'Only a REQUESTED or CONFIRMED Appointment may be cancelled'
);
select pg_temp.assert_error(
    format('select pg_temp.confirm(%L, 1)', pg_temp.appt(21)),
    '23514', 'Only a REQUESTED Appointment may be confirmed'
);
-- Since 20261112090000 the generic assignment operation is a trusted path only
-- (SPEC-APT-007 BR-40); its establishment rule is asserted as that caller.
reset role;
select pg_temp.assert_error(
    format('select public.assign_veterinarian_to_appointment(%L, %L)', pg_temp.appt(4), 'e1a00000-0000-4000-8000-000000000815'),
    '23514', 'Appointment Veterinarian Assignment requires a REQUESTED, CONFIRMED, or COMPLETED Appointment'
);
set local role authenticated;
select pg_temp.assert_error(
    format('select pg_temp.no_show(%L, 1)', pg_temp.appt(4)),
    '23514', 'Only a CONFIRMED Appointment may be marked no-show'
);
reset role;

select pg_temp.assert_true(
    (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(21))
    and (select count(*) = 1 from public.appointment_lifecycle_events where appointment_id = pg_temp.appt(32))
    and not exists (select 1 from public.transactional_communications where appointment_id in (pg_temp.appt(21), pg_temp.appt(32), pg_temp.appt(33), pg_temp.appt(41))),
    'Cases 29/30/34 and races: whichever runs first, a lapsed request ends EXPIRED with one Event — never CANCELLED, confirmed, or revived'
);

create temporary table read_snapshot (
    source text, id uuid, lifecycle_state text,
    start_at timestamptz, end_at timestamptz, sequence integer,
    primary key (source, id)
) on commit drop;
grant select, insert on read_snapshot to authenticated;

select pg_temp.act(1);
set local role authenticated;
insert into read_snapshot
select 'guardian', appointment.id, appointment.lifecycle_state,
       appointment.current_scheduled_start_at, appointment.current_scheduled_end_at, null
from public.get_pet_appointments(pg_temp.kira()) as appointment;
reset role;

select pg_temp.act(4);
set local role authenticated;
insert into read_snapshot
select 'clinic', schedule.id, schedule.lifecycle_state,
       schedule.current_scheduled_start_at, schedule.current_scheduled_end_at,
       schedule.current_schedule_revision_sequence
from public.get_clinic_appointment_schedule(pg_temp.a1()) as schedule;
reset role;

select pg_temp.assert_true(
    (select lifecycle_state = 'EXPIRED' and start_at = '2026-06-01T12:00Z' and end_at = '2026-06-01T12:30Z'
     from read_snapshot where source = 'guardian' and id = pg_temp.appt(4))
    and (select lifecycle_state = 'EXPIRED' and start_at = '2026-06-01T12:00Z' and sequence = 2
         from read_snapshot where source = 'clinic' and id = pg_temp.appt(4))
    and (select count(*) = 2 from read_snapshot where id = pg_temp.appt(1) and lifecycle_state = 'EXPIRED'),
    'Cases 50/51/52: both reads return EXPIRED with the latest requested interval and revision'
);

-- Case 53: an EXPIRED Appointment is not a confirmed commitment and
-- grants no pre-care access.
select pg_temp.assert_true(
    not public.appointment_permits_pre_care_access(pg_temp.appt(21), clock_timestamp())
    and not public.appointment_is_pending_request(pg_temp.appt(21), '2020-01-01Z'),
    'Case 53: EXPIRED is neither pending nor a pre-care access basis'
);

select pg_temp.act(5);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pre_care_status(pg_temp.a2(), pg_temp.appt(21)) = 'DENIED',
    'Case 53: after materialization the ended authorization still denies pre-care access'
);
reset role;

rollback;

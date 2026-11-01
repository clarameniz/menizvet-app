-- SPEC-APT-015 — Expire Unconfirmed Appointment Request, and the amended
-- SPEC-APT-001 (BR-35/BR-36), SPEC-APT-003 (BR-21–BR-23), SPEC-APT-004
-- (BR-27), and SPEC-ACC-001 (BR-39/BR-40) rules it relies on.
--
-- 1. `EXPIRED` becomes a terminal Appointment lifecycle state, reachable
--    only through `REQUESTED → EXPIRED`.
-- 2. That transition is recorded as a SYSTEM Lifecycle Event with no User
--    actor. `actor_user_id` becomes nullable, but only for
--    `actor_context = 'SYSTEM'`, and only an `EXPIRED` Event may be SYSTEM;
--    every Guardian and Clinic Event still requires its User.
-- 3. The existing temporal columns already carry both required facts: the
--    Event's `effective_at` is the logical expiry instant (the latest
--    REQUESTED scheduled start) and `recorded_at` is when the system
--    materialized it. The ended Care Authorization's `ended_at` equals that
--    `effective_at`, exactly as the existing coherence rule already requires
--    for cancellation and no-show endings. No timestamp column is added.
-- 4. Logical expiry is evaluated directly with authoritative backend time,
--    never through materialization: three shared predicates
--    (`appointment_latest_requested_start_at`,
--    `appointment_is_pending_request`, `appointment_permits_pre_care_access`)
--    drive the pending-request rule in `request_appointment`, the lapsed
--    request rejections in `cancel_appointment` and
--    `reschedule_requested_appointment`, and the pre-care medical-access
--    cutoff in both Appointment-derived access paths
--    (`slice12_view_professional_pet_medical_history`,
--    `authorize_clinical_attachment_download`). `confirm_appointment`
--    already rejects a past REQUESTED Appointment and any EXPIRED one, so it
--    is unchanged.
-- 5. `expire_lapsed_appointment_requests(timestamptz)` materializes expiry:
--    SYSTEM Event, lifecycle state, and the `APPOINTMENT_EXPIRED` Care
--    Authorization ending, idempotently and with no Communication. It is
--    not granted to `anon` or `authenticated`; scheduling is provisioned
--    separately (supabase/provisioning/appointment_request_expiry_scheduler.sql).
--
-- Every replaced function body is copied verbatim from its latest
-- definition and changed only where noted; the ACL statements each
-- function already had are re-applied unchanged. No view, rule, or other
-- function depends on any replaced signature. No existing row is
-- rewritten. The `REQUESTED → EXPIRED` Communication path stays empty: the
-- lifecycle Communication trigger maps only CONFIRMED, CANCELLED,
-- COMPLETED, and NO_SHOW, so an EXPIRED Event enqueues nothing.
--
-- Deployment order: client applications in the target environment must
-- parse `EXPIRED` before the expiry scheduler is provisioned there
-- (SPEC-APT-015 §7). This migration itself writes no `EXPIRED` row.
begin;

-- ==================================================================
-- 1. EXPIRED lifecycle state and the SYSTEM Lifecycle Event actor.
-- ==================================================================

alter table public.appointments
drop constraint appointments_lifecycle_state_check;

alter table public.appointments
add constraint appointments_lifecycle_state_check
check (lifecycle_state in (
    'REQUESTED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'
));

alter table public.appointment_lifecycle_events
alter column actor_user_id drop not null;

alter table public.appointment_lifecycle_events
drop constraint appointment_lifecycle_events_actor_context_check;

alter table public.appointment_lifecycle_events
drop constraint appointment_lifecycle_events_transition_check;

alter table public.appointment_lifecycle_events
add constraint appointment_lifecycle_events_actor_context_check
check (actor_context is null or actor_context in ('GUARDIAN', 'CLINIC', 'SYSTEM')),
-- SYSTEM Events have no User actor; every other Event keeps its User.
add constraint appointment_lifecycle_events_actor_user_shape_check
check ((actor_context is not distinct from 'SYSTEM') = (actor_user_id is null)),
-- Expiry is the only SYSTEM transition, and it is always SYSTEM.
add constraint appointment_lifecycle_events_system_expiry_check
check ((to_state = 'EXPIRED') = (actor_context is not distinct from 'SYSTEM')),
add constraint appointment_lifecycle_events_transition_check
check (
    (from_state = 'REQUESTED' and to_state = 'CONFIRMED')
    or (from_state in ('REQUESTED', 'CONFIRMED') and to_state = 'CANCELLED')
    or (from_state = 'CONFIRMED' and to_state in ('COMPLETED', 'NO_SHOW'))
    or (from_state = 'REQUESTED' and to_state = 'EXPIRED')
),
-- The logical expiry instant is never after the time it was recorded.
add constraint appointment_lifecycle_events_expiry_recording_check
check (to_state <> 'EXPIRED' or effective_at <= recorded_at);

drop index public.appointment_lifecycle_events_terminal_key;

create unique index appointment_lifecycle_events_terminal_key
on public.appointment_lifecycle_events (appointment_id)
where to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED');

-- ==================================================================
-- 2. Care Authorization normal-ending context APPOINTMENT_EXPIRED.
-- ==================================================================

alter table public.care_authorizations
drop constraint care_authorizations_ended_reason_check;

alter table public.care_authorizations
add constraint care_authorizations_ended_reason_check
check (
    ended_reason is null
    or ended_reason in ('APPOINTMENT_CANCELLED', 'APPOINTMENT_NO_SHOW', 'APPOINTMENT_EXPIRED')
);

-- ==================================================================
-- 3. Shared logical-expiry predicates. Internal only.
-- ==================================================================

-- The logical expiry instant of a never-confirmed request: the scheduled
-- start of its latest REQUESTED Schedule Revision.
create function public.appointment_latest_requested_start_at(
    p_appointment_id uuid
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
    select revision.scheduled_start_at
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'REQUESTED'
    order by revision.revision_sequence desc
    limit 1
$$;

revoke all privileges
on function public.appointment_latest_requested_start_at(uuid)
from public, anon, authenticated;

-- SPEC-APT-001 BR-35: REQUESTED and its latest requested start strictly
-- after the reference time. Otherwise the request is logically expired
-- (SPEC-APT-015 BR-4) whether or not EXPIRED has been materialized.
create function public.appointment_is_pending_request(
    p_appointment_id uuid,
    p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and appointment.lifecycle_state = 'REQUESTED'
          and public.appointment_latest_requested_start_at(appointment.id) > p_reference_time
    )
$$;

revoke all privileges
on function public.appointment_is_pending_request(uuid, timestamptz)
from public, anon, authenticated;

-- SPEC-ACC-001 BR-39: the Appointment states under which an
-- Appointment-derived Care Authorization may support pre-care access — a
-- CONFIRMED Appointment, or a still-pending REQUESTED one. The callers keep
-- their own ACTIVE-authorization and no-Encounter conditions.
create function public.appointment_permits_pre_care_access(
    p_appointment_id uuid,
    p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and (
              appointment.lifecycle_state = 'CONFIRMED'
              or public.appointment_is_pending_request(appointment.id, p_reference_time)
          )
    )
$$;

revoke all privileges
on function public.appointment_permits_pre_care_access(uuid, timestamptz)
from public, anon, authenticated;

-- ==================================================================
-- 4. Lifecycle trigger — REQUESTED -> EXPIRED is the only new transition.
-- ==================================================================

create or replace function public.enforce_appointment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointments cannot be deleted' using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.clinic_id is distinct from new.clinic_id
       or old.requesting_user_id is distinct from new.requesting_user_id
       or old.reason_for_visit is distinct from new.reason_for_visit
       or old.guardian_notes is distinct from new.guardian_notes
       or old.created_at is distinct from new.created_at then
        raise exception 'Appointment identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state = new.lifecycle_state then
        return new;
    end if;

    if not (
        (old.lifecycle_state = 'REQUESTED' and new.lifecycle_state = 'CONFIRMED')
        or (old.lifecycle_state in ('REQUESTED', 'CONFIRMED') and new.lifecycle_state = 'CANCELLED')
        or (old.lifecycle_state = 'CONFIRMED' and new.lifecycle_state in ('COMPLETED', 'NO_SHOW'))
        or (old.lifecycle_state = 'REQUESTED' and new.lifecycle_state = 'EXPIRED')
    ) then
        raise exception 'Unsupported Appointment lifecycle transition'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_immutability()
from public, anon, authenticated;

-- ==================================================================
-- 5. Deferred lifecycle and Care Authorization coherence (verbatim + EXPIRED).
-- ==================================================================

create or replace function public.assert_appointment_lifecycle_coherence(
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    requested_revision_count integer;
    confirmed_revision_count integer;
    confirmation_event_count integer;
    terminal_event_count integer;
    lifecycle_event_record public.appointment_lifecycle_events%rowtype;
    confirmation_effective_at timestamptz;
    latest_confirmed_scheduled_start_at timestamptz;
    encounter_record public.clinical_encounters%rowtype;
begin
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if not found then return; end if;

    select count(*) into requested_revision_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'REQUESTED'
      and revision.revision_sequence = 1;

    if requested_revision_count <> 1 then
        raise exception 'Appointment % requires exactly one initial REQUESTED Schedule Revision', p_appointment_id
            using errcode = '23514';
    end if;

    select count(*) into confirmation_event_count
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.from_state = 'REQUESTED'
      and lifecycle_event.to_state = 'CONFIRMED';

    select count(*) into terminal_event_count
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED');

    select count(*) into confirmed_revision_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED';

    if appointment_record.lifecycle_state = 'REQUESTED' then
        if confirmation_event_count <> 0 or terminal_event_count <> 0 then
            raise exception 'REQUESTED Appointment % must have zero Lifecycle Events', p_appointment_id
                using errcode = '23514';
        end if;
        return;
    end if;

    if appointment_record.lifecycle_state = 'CONFIRMED' then
        if confirmation_event_count <> 1 or terminal_event_count <> 0 or confirmed_revision_count < 1 then
            raise exception 'CONFIRMED Appointment % has incoherent confirmation history', p_appointment_id
                using errcode = '23514';
        end if;
        return;
    end if;

    if terminal_event_count <> 1 then
        raise exception 'Terminal Appointment % requires exactly one terminal Lifecycle Event', p_appointment_id
            using errcode = '23514';
    end if;

    select lifecycle_event.* into lifecycle_event_record
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED');

    if lifecycle_event_record.to_state <> appointment_record.lifecycle_state then
        raise exception 'Appointment % terminal Event must match its lifecycle state', p_appointment_id
            using errcode = '23514';
    end if;

    if lifecycle_event_record.from_state = 'REQUESTED' then
        if appointment_record.lifecycle_state not in ('CANCELLED', 'EXPIRED')
           or confirmation_event_count <> 0 then
            raise exception 'Only cancellation or expiry may terminate an unconfirmed Appointment %', p_appointment_id
                using errcode = '23514';
        end if;
        if appointment_record.lifecycle_state = 'EXPIRED' and confirmed_revision_count <> 0 then
            raise exception 'EXPIRED Appointment % must not have a CONFIRMED Schedule Revision', p_appointment_id
                using errcode = '23514';
        end if;
    else
        if confirmation_event_count <> 1 or confirmed_revision_count < 1 then
            raise exception 'Appointment % terminated from CONFIRMED requires confirmation history', p_appointment_id
                using errcode = '23514';
        end if;

        select lifecycle_event.effective_at into confirmation_effective_at
        from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = p_appointment_id
          and lifecycle_event.from_state = 'REQUESTED'
          and lifecycle_event.to_state = 'CONFIRMED';

        if lifecycle_event_record.effective_at < confirmation_effective_at then
            raise exception 'Appointment % terminal Event cannot precede confirmation', p_appointment_id
                using errcode = '23514';
        end if;
    end if;

    if appointment_record.lifecycle_state = 'COMPLETED' then
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = lifecycle_event_record.clinical_encounter_id;

        if not found
           or encounter_record.appointment_id is distinct from appointment_record.id
           or encounter_record.pet_id is distinct from appointment_record.pet_id
           or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
            raise exception 'COMPLETED Appointment % requires compatible Clinical Encounter evidence', p_appointment_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < encounter_record.started_at then
            raise exception 'COMPLETED Appointment % Event cannot precede its supporting Clinical Encounter', p_appointment_id
                using errcode = '23514';
        end if;
    else
        if lifecycle_event_record.clinical_encounter_id is not null then
            raise exception 'Only COMPLETED Appointment Events may reference a Clinical Encounter'
                using errcode = '23514';
        end if;
        if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED')
           and exists (
               select 1 from public.clinical_encounters as encounter_row
               where encounter_row.appointment_id = p_appointment_id
           ) then
            raise exception 'CANCELLED, NO_SHOW, or EXPIRED Appointment % cannot coexist with a Clinical Encounter', p_appointment_id
                using errcode = '23514';
        end if;

        if appointment_record.lifecycle_state = 'NO_SHOW' then
            select revision.scheduled_start_at
            into latest_confirmed_scheduled_start_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = p_appointment_id
              and revision.revision_context = 'CONFIRMED'
            order by revision.revision_sequence desc
            limit 1;

            if not found then
                raise exception 'NO_SHOW Appointment % requires its latest CONFIRMED Schedule Revision', p_appointment_id
                    using errcode = '23514';
            end if;

            if lifecycle_event_record.effective_at < latest_confirmed_scheduled_start_at then
                raise exception 'NO_SHOW Appointment % Event cannot precede its latest confirmed scheduled start', p_appointment_id
                    using errcode = '23514';
            end if;
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_coherence(uuid)
from public, anon, authenticated;

create or replace function public.assert_appointment_lifecycle_event_provenance(
    p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    lifecycle_event_record public.appointment_lifecycle_events%rowtype;
    appointment_record public.appointments%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    confirmed_revision_count integer;
    latest_confirmed_scheduled_start_at timestamptz;
begin
    select lifecycle_event.* into lifecycle_event_record
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.id = p_event_id;
    if not found then return; end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = lifecycle_event_record.appointment_id
    for update;

    if not found or appointment_record.lifecycle_state <> lifecycle_event_record.to_state then
        raise exception 'Appointment Lifecycle Event % requires a matching Appointment state', p_event_id
            using errcode = '23514';
    end if;

    if lifecycle_event_record.from_state = 'CONFIRMED'
       or lifecycle_event_record.to_state = 'CONFIRMED' then
        select count(*) into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED';
        if confirmed_revision_count < 1 then
            raise exception 'Lifecycle Event % requires a CONFIRMED Schedule Revision', p_event_id
                using errcode = '23514';
        end if;
    end if;

    if lifecycle_event_record.to_state = 'EXPIRED' then
        select count(*) into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED';
        if confirmed_revision_count <> 0 then
            raise exception 'Expiry Event % requires a never-confirmed Appointment', p_event_id
                using errcode = '23514';
        end if;
        if lifecycle_event_record.effective_at is distinct from
           public.appointment_latest_requested_start_at(appointment_record.id) then
            raise exception 'Expiry Event % must take effect at the latest requested scheduled start', p_event_id
                using errcode = '23514';
        end if;
    end if;

    if lifecycle_event_record.to_state = 'COMPLETED' then
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = lifecycle_event_record.clinical_encounter_id;
        if not found
           or encounter_record.appointment_id is distinct from appointment_record.id
           or encounter_record.pet_id is distinct from appointment_record.pet_id
           or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
            raise exception 'Completion Event % requires compatible Clinical Encounter evidence', p_event_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < encounter_record.started_at then
            raise exception 'Completion Event % cannot precede its supporting Clinical Encounter', p_event_id
                using errcode = '23514';
        end if;
    elsif lifecycle_event_record.to_state = 'NO_SHOW' then
        select revision.scheduled_start_at
        into latest_confirmed_scheduled_start_at
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED'
        order by revision.revision_sequence desc
        limit 1;

        if not found then
            raise exception 'NO_SHOW Event % requires its latest CONFIRMED Schedule Revision', p_event_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < latest_confirmed_scheduled_start_at then
            raise exception 'NO_SHOW Event % cannot precede its latest confirmed scheduled start', p_event_id
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_event_provenance(uuid)
from public, anon, authenticated;

create or replace function public.assert_appointment_care_authorization_coherence(
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    linked_count integer;
    linked_state text;
begin
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;
    if not found then return; end if;

    select count(*), min(care_auth.lifecycle_state)
    into linked_count, linked_state
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id;

    if linked_count <> 1 then
        raise exception 'Appointment % requires exactly one Appointment-derived Care Authorization', p_appointment_id
            using errcode = '23514';
    end if;

    if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED')
       and linked_state = 'ACTIVE' then
        raise exception 'Cancelled, no-show, or expired Appointment % must not retain ACTIVE care authority', p_appointment_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_care_authorization_coherence(uuid)
from public, anon, authenticated;

create or replace function public.assert_care_authorization_appointment_coherence(
    p_care_authorization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    care_auth_record public.care_authorizations%rowtype;
    expected_appointment_state text;
    expected_terminal_state text;
    terminal_effective_at timestamptz;
begin
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;
    if not found then return; end if;

    if care_auth_record.lifecycle_state <> 'ENDED'
       or care_auth_record.ended_reason not in ('APPOINTMENT_CANCELLED', 'APPOINTMENT_NO_SHOW', 'APPOINTMENT_EXPIRED') then
        return;
    end if;

    expected_appointment_state := case care_auth_record.ended_reason
        when 'APPOINTMENT_CANCELLED' then 'CANCELLED'
        when 'APPOINTMENT_EXPIRED' then 'EXPIRED'
        else 'NO_SHOW'
    end;
    expected_terminal_state := expected_appointment_state;

    select appointment.lifecycle_state into expected_appointment_state
    from public.appointments as appointment
    where appointment.id = care_auth_record.appointment_id
    for update;

    if not found or expected_appointment_state <> expected_terminal_state then
        raise exception 'Ended Care Authorization % requires its matching terminal Appointment state', p_care_authorization_id
            using errcode = '23514';
    end if;

    select lifecycle_event.effective_at into terminal_effective_at
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = care_auth_record.appointment_id
      and lifecycle_event.to_state = expected_terminal_state;

    if not found or terminal_effective_at is distinct from care_auth_record.ended_at then
        raise exception 'Ended Care Authorization % must match its terminal Appointment Event time', p_care_authorization_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_care_authorization_appointment_coherence(uuid)
from public, anon, authenticated;

-- ==================================================================
-- 6. Logical expiry in Guardian and Clinic mutations (verbatim + one check each).
-- ==================================================================

create or replace function public.request_appointment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_reason_for_visit text,
    p_guardian_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    clinic_is_published boolean;
    clinic_duration_minutes integer;
    guardianship_record public.guardianships%rowtype;
    resolved_start record;
    resolved_end_at timestamptz;
    normalized_reason text;
    normalized_notes text;
    operation_timestamp timestamptz;
    created_appointment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = acting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The acting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    -- Disclosure pre-check: unchanged from the prior contract
    -- (SPEC-APT-001 BR-34) — proves Guardian domain authority for the
    -- exact Pet before any Organization/Clinic lock is taken or
    -- Entitlement/publication/duration state is evaluated, so a User
    -- without Guardianship cannot learn any of that state through this
    -- operation's error ordering.
    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    target_organization_id := public.assert_clinic_organization_entitlement_after_lock(
        p_clinic_id, 'APPOINTMENT_MANAGEMENT'
    );

    select clinic.is_published, clinic.standard_appointment_duration_minutes
    into clinic_is_published, clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not coalesce(clinic_is_published, false) then
        raise exception 'Appointment requests require a published Clinic'
            using errcode = '23514';
    end if;

    -- SPEC-APT-001 BR-31: an additional necessary condition alongside
    -- publication/Entitlement above; it does not reorder them.
    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    -- Authoritative, locked revalidation of the exact current
    -- Guardianship row, after Organization -> Clinic locking.
    select guardianship.*
    into guardianship_record
    from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;

    if not found then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    normalized_reason := btrim(p_reason_for_visit, E' \t\n\r\f\013');

    if normalized_reason is null or normalized_reason = '' then
        raise exception 'Appointment request requires a reason for visit'
            using errcode = '22023';
    end if;

    normalized_notes := case
        when p_guardian_notes is null then null
        else btrim(p_guardian_notes, E' \t\n\r\f\013')
    end;

    if normalized_notes = '' then
        raise exception 'Guardian notes must not be blank when supplied'
            using errcode = '22023';
    end if;

    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        p_clinic_id, p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    operation_timestamp := clock_timestamp();

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Requested Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- SPEC-APT-001 BR-30: end is derived as real elapsed time from the
    -- resolved start instant, never by independently deriving and
    -- resolving a second civil end.
    resolved_end_at := resolved_start.resolved_start_at
        + (clinic_duration_minutes * interval '1 minute');

    if not public.clinic_appointment_interval_is_available(
        p_clinic_id,
        resolved_start.resolved_start_at,
        resolved_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the requested interval'
            using errcode = '23514';
    end if;

    -- SPEC-APT-001 BR-35/BR-36: at most one pending request per Pet and
    -- Clinic, whichever Guardian created it. Evaluated after the
    -- Organization -> Clinic locks taken above, which serialize every
    -- request at this Clinic, and before any write. Confirmed, terminal,
    -- and logically expired Appointments never block.
    if exists (
        select 1
        from public.appointments as existing_appointment
        where existing_appointment.pet_id = p_pet_id
          and existing_appointment.clinic_id = p_clinic_id
          and public.appointment_is_pending_request(existing_appointment.id, operation_timestamp)
    ) then
        raise exception 'A pending Appointment request already exists for this Pet at this Clinic'
            using errcode = '23514';
    end if;

    insert into public.appointments (
        pet_id, clinic_id, requesting_user_id, reason_for_visit, guardian_notes,
        lifecycle_state, created_at
    )
    values (
        p_pet_id, p_clinic_id, acting_user_id, normalized_reason, normalized_notes,
        'REQUESTED', operation_timestamp
    )
    returning id into created_appointment_id;

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        created_appointment_id, 1, 'REQUESTED',
        resolved_start.resolved_start_at, resolved_end_at,
        resolved_start.timezone_name, acting_user_id, null, operation_timestamp
    );

    insert into public.care_authorizations (
        pet_id, clinic_id, organization_id, granting_guardianship_id,
        granted_at, purpose, appointment_id, lifecycle_state
    )
    values (
        p_pet_id, p_clinic_id, target_organization_id, guardianship_record.id,
        operation_timestamp, 'APPOINTMENT_CARE', created_appointment_id, 'ACTIVE'
    );

    return created_appointment_id;
end;
$$;

revoke all privileges
on function public.request_appointment(
    uuid, uuid, date, time, integer, text, text
)
from public, anon, authenticated;

grant execute
on function public.request_appointment(
    uuid, uuid, date, time, integer, text, text
)
to authenticated;

create or replace function public.reschedule_requested_appointment(
    p_appointment_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
    clinic_duration_minutes integer;
    appointment_record public.appointments%rowtype;
    latest_requested_revision public.appointment_schedule_revisions%rowtype;
    current_assignment_record public.appointment_veterinarian_assignments%rowtype;
    resolved_start record;
    resolved_end_at timestamptz;
    next_sequence integer;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- Resolve the immutable Appointment -> Clinic identity without a
    -- write lock, then use Clinic as the scheduling-configuration
    -- serialization boundary. Guardian rescheduling intentionally
    -- acquires no Organization or Entitlement lock (unchanged).
    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id
    for update;

    if not found then
        raise exception 'Appointment Clinic does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = resolved_clinic_id
    for update;

    if not found then
        raise exception 'Appointment does not exist in the expected Clinic'
            using errcode = '23503';
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = resolved_clinic_id;

    if appointment_record.lifecycle_state <> 'REQUESTED' then
        raise exception 'Only a REQUESTED Appointment may be rescheduled through this workflow'
            using errcode = '23514';
    end if;

    -- Lock and revalidate the exact current Guardianship row after the
    -- Appointment serialization point (unchanged ordering).
    perform 1
    from public.guardianships as guardianship
    where guardianship.pet_id = appointment_record.pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_end is null
    for update;

    if not found then
        raise exception 'Current Guardianship of the Appointment Pet is required'
            using errcode = '42501';
    end if;

    -- SPEC-APT-004 BR-24: an additional necessary condition alongside
    -- the existing REQUESTED-state/Guardianship preconditions above;
    -- it does not reorder them.
    select clinic.standard_appointment_duration_minutes
    into clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id;

    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    select revision.*
    into latest_requested_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'REQUESTED'
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no requested scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    -- SPEC-APT-004 BR-27: a request whose latest requested start is no
    -- longer in the future is logically expired and cannot be revived.
    if latest_requested_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'A REQUESTED Appointment whose requested time has passed cannot be rescheduled'
            using errcode = '23514';
    end if;

    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        resolved_clinic_id, p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Rescheduled Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- SPEC-APT-004 BR-23: current standard duration, as real elapsed
    -- time — not necessarily the duration that produced the previous
    -- revision.
    resolved_end_at := resolved_start.resolved_start_at
        + (clinic_duration_minutes * interval '1 minute');

    -- SPEC-APT-004 BR-19 (revised): "the same effective requested time"
    -- means the same full resolved interval, so a same-start
    -- resubmission after a duration change is correctly NOT a no-op.
    if resolved_start.resolved_start_at = latest_requested_revision.scheduled_start_at
       and resolved_end_at = latest_requested_revision.scheduled_end_at then
        raise exception 'Rescheduled time must differ from the current requested time'
            using errcode = '22023';
    end if;

    if not public.clinic_appointment_interval_is_available(
        resolved_clinic_id,
        resolved_start.resolved_start_at,
        resolved_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the new requested interval'
            using errcode = '23514';
    end if;

    -- Re-evaluate any existing current Assignment against the NEW
    -- requested interval before committing to it (unchanged).
    select assignment.*
    into current_assignment_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null
    for update;

    if found then
        perform 1
        from public.veterinarian_clinic_assignments as clinic_assignment
        where clinic_assignment.id
                  = current_assignment_record.veterinarian_clinic_assignment_id
          and clinic_assignment.clinic_id = resolved_clinic_id
        for update;

        if not found then
            raise exception 'Current Appointment Veterinarian Assignment has no matching Clinic Assignment'
                using errcode = '23514';
        end if;

        if not public.veterinarian_clinic_assignment_is_current(
            current_assignment_record.veterinarian_clinic_assignment_id
        ) then
            raise exception 'Currently assigned Veterinarian no longer has a valid Clinic Assignment'
                using errcode = '23514';
        end if;

        if not public.veterinarian_availability_covers_interval(
            current_assignment_record.veterinarian_clinic_assignment_id,
            resolved_start.resolved_start_at, resolved_end_at
        ) then
            raise exception 'Currently assigned Veterinarian is not available for the new requested interval'
                using errcode = '23514';
        end if;
    end if;

    next_sequence := public.next_appointment_revision_sequence(p_appointment_id);

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        p_appointment_id, next_sequence, 'REQUESTED',
        resolved_start.resolved_start_at, resolved_end_at,
        resolved_start.timezone_name, acting_user_id, null, operation_timestamp
    );

    return p_appointment_id;
end;
$$;

revoke all privileges
on function public.reschedule_requested_appointment(uuid, date, time, integer)
from public, anon, authenticated;

grant execute
on function public.reschedule_requested_appointment(uuid, date, time, integer)
to authenticated;

create or replace function public.cancel_appointment(
    p_appointment_id uuid,
    p_cancelling_context text,
    p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_pet_id uuid;
    normalized_reason text;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_cancelling_context is null or p_cancelling_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Cancelling context must be GUARDIAN or CLINIC' using errcode = '22023';
    end if;
    select appointment.pet_id, appointment.clinic_id into appointment_pet_id, appointment_clinic_id
    from public.appointments as appointment where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    if p_cancelling_context = 'GUARDIAN' then
        if not exists (
            select 1 from public.guardianships as guardianship
            where guardianship.pet_id = appointment_pet_id and guardianship.user_id = acting_user_id
              and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
        ) then raise exception 'Current Guardianship of the Appointment Pet is required' using errcode = '42501'; end if;
    else
        perform public.assert_clinic_capability_after_lock(
            acting_user_id, appointment_clinic_id, 'APPOINTMENT_CANCEL'
        );
    end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    if p_cancelling_context = 'CLINIC' and normalized_reason is null then
        raise exception 'A meaningful reason is required for a Clinic cancellation' using errcode = '22023';
    end if;
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;
    if appointment_record.lifecycle_state not in ('REQUESTED', 'CONFIRMED') then
        raise exception 'Only a REQUESTED or CONFIRMED Appointment may be cancelled' using errcode = '23514';
    end if;
    -- SPEC-APT-003 BR-23 / SPEC-APT-015 BR-18: a logically expired request
    -- is never cancelled, whether or not EXPIRED has been materialized.
    if appointment_record.lifecycle_state = 'REQUESTED'
       and not public.appointment_is_pending_request(p_appointment_id, clock_timestamp()) then
        raise exception 'A REQUESTED Appointment whose requested time has passed cannot be cancelled' using errcode = '23514';
    end if;
    if exists (select 1 from public.clinical_encounters as encounter_row
               where encounter_row.appointment_id = p_appointment_id) then
        raise exception 'Appointment with a Clinical Encounter cannot be cancelled' using errcode = '23514';
    end if;
    if p_cancelling_context = 'GUARDIAN' then
        perform 1 from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
        for update;
        if not found then raise exception 'Current Guardianship of the Appointment Pet is required' using errcode = '42501'; end if;
    end if;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id for update;
    if not found then raise exception 'Appointment has no Appointment-derived Care Authorization' using errcode = '23514'; end if;
    operation_timestamp := clock_timestamp();
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at, clinical_encounter_id
    ) values (
        p_appointment_id, appointment_record.lifecycle_state, 'CANCELLED',
        acting_user_id, p_cancelling_context, normalized_reason,
        operation_timestamp, operation_timestamp, null
    );
    update public.appointments set lifecycle_state = 'CANCELLED' where id = p_appointment_id;
    if care_auth_record.lifecycle_state = 'ACTIVE' then
        update public.care_authorizations
        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_CANCELLED'
        where id = care_auth_record.id;
    end if;
    return p_appointment_id;
end;
$$;

revoke all privileges
on function public.cancel_appointment(uuid, text, text)
from public, anon, authenticated;

grant execute
on function public.cancel_appointment(uuid, text, text)
to authenticated;

-- ==================================================================
-- 7. Immediate pre-care access cutoff (verbatim + the shared predicate).
-- ==================================================================

create or replace function public.slice12_view_professional_pet_medical_history(
    p_pet_id uuid,
    p_accessing_clinic_id uuid,
    p_care_authorization_id uuid,
    p_clinical_encounter_id uuid default null,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    professional_context record;
    care_auth_record public.care_authorizations%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    bounded_limit integer;
    permitted boolean := false;
    professional_context_available boolean := false;
    care_auth_context_available boolean := false;
    result_payload jsonb;
    has_more boolean;
    next_order_at timestamptz;
    next_entry_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_limit is null or p_limit < 1 then raise exception 'Page limit must be positive' using errcode = '22023'; end if;
    if (p_before_history_order_at is null) <> (p_before_entry_id is null) then
        raise exception 'History cursor components must be supplied together' using errcode = '22023';
    end if;
    if p_before_history_order_at is not null and not isfinite(p_before_history_order_at) then
        raise exception 'History cursor timestamp must be finite' using errcode = '22023';
    end if;
    bounded_limit := least(p_limit, 100);
    if not exists (select 1 from public.pets as pet where pet.id = p_pet_id) then
        return jsonb_build_object('status', 'DENIED');
    end if;
    select clinic.organization_id into target_organization_id
    from public.clinics as clinic where clinic.id = p_accessing_clinic_id;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id
      and care_auth.pet_id = p_pet_id
      and care_auth.clinic_id = p_accessing_clinic_id
      and care_auth.organization_id = target_organization_id;
    care_auth_context_available := found;

    select * into professional_context
    from public.find_current_veterinarian_context_after_lock(
        acting_user_id, p_accessing_clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
    );
    professional_context_available := found;
    if professional_context_available then
        if care_auth_record.appointment_id is not null then
            perform 1 from public.appointments as appointment
            where appointment.id = care_auth_record.appointment_id
            for share;
        end if;

        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.id = p_care_authorization_id
          and care_auth.pet_id = p_pet_id
          and care_auth.clinic_id = p_accessing_clinic_id
          and care_auth.organization_id = professional_context.organization_id
        for share;
        care_auth_context_available := found;
        if found and care_auth_record.lifecycle_state = 'ACTIVE' then
            if p_clinical_encounter_id is null
               and care_auth_record.purpose = 'APPOINTMENT_CARE'
               and public.appointment_permits_pre_care_access(
                   care_auth_record.appointment_id, clock_timestamp()
               )
               and not exists (
                   select 1 from public.clinical_encounters as encounter_row
                   where encounter_row.care_authorization_id = care_auth_record.id
               ) then
                permitted := true;
            elsif p_clinical_encounter_id is not null then
                select encounter_row.* into encounter_record
                from public.clinical_encounters as encounter_row
                where encounter_row.id = p_clinical_encounter_id
                  and encounter_row.care_authorization_id = care_auth_record.id
                  and encounter_row.pet_id = p_pet_id
                  and encounter_row.clinic_id = p_accessing_clinic_id
                  and encounter_row.organization_id = professional_context.organization_id
                for share;
                permitted := found and encounter_record.lifecycle_state = 'ACTIVE';
            end if;
        end if;
    end if;

    if not permitted then
        perform public.establish_medical_access_audit_event(
            acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'DENIED',
            'PROFESSIONAL_CLINICAL', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
            null,
            case when care_auth_context_available then care_auth_record.id else null end,
            case when target_organization_id is not null then p_accessing_clinic_id else null end,
            target_organization_id,
            case when care_auth_context_available then care_auth_record.appointment_id else null end,
            case when professional_context_available then professional_context.organization_membership_id else null end,
            case when professional_context_available then professional_context.organization_responsibility_grant_id else null end,
            case when professional_context_available then professional_context.veterinarian_clinic_assignment_id else null end,
            case when encounter_record.id is not null then encounter_record.id else null end,
            null, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    with page_rows as (
        select record_entry.*, encounter_row.clinic_id, encounter_row.organization_id,
               encounter_row.started_at,
               encounter_row.lifecycle_state as encounter_lifecycle_state,
               encounter_row.concluded_at as encounter_concluded_at,
               encounter_row.responsible_veterinarian_clinic_assignment_id,
               coalesce(record_entry.clinical_event_at, encounter_row.started_at) as history_order_at,
               row_number() over (order by coalesce(record_entry.clinical_event_at, encounter_row.started_at) desc,
                                            record_entry.id desc) as page_number
        from public.clinical_record_entries as record_entry
        join public.clinical_encounters as encounter_row
          on encounter_row.id = record_entry.clinical_encounter_id
        where encounter_row.pet_id = p_pet_id and record_entry.lifecycle_state = 'FINALIZED'
          and (p_before_history_order_at is null or
               (coalesce(record_entry.clinical_event_at, encounter_row.started_at), record_entry.id)
                 < (p_before_history_order_at, p_before_entry_id))
        order by history_order_at desc, record_entry.id desc limit bounded_limit + 1
    ), visible_rows as (select * from page_rows where page_number <= bounded_limit)
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', visible_record.id, 'clinical_encounter_id', visible_record.clinical_encounter_id,
               'clinic_id', visible_record.clinic_id, 'organization_id', visible_record.organization_id,
               'encounter_started_at', visible_record.started_at,
               'encounter_lifecycle_state', visible_record.encounter_lifecycle_state,
               'encounter_concluded_at', visible_record.encounter_concluded_at,
               'responsible_veterinarian_clinic_assignment_id', visible_record.responsible_veterinarian_clinic_assignment_id,
               'created_by_user_id', visible_record.created_by_user_id,
               'creator_veterinarian_clinic_assignment_id', visible_record.creator_veterinarian_clinic_assignment_id,
               'created_at', visible_record.created_at,
               'draft_revision', visible_record.draft_revision,
               'last_modified_at', visible_record.last_modified_at,
               'clinical_content', visible_record.clinical_content, 'category', visible_record.category,
               'other_category_context', visible_record.other_category_context,
               'clinical_event_at', visible_record.clinical_event_at,
               'history_order_at', visible_record.history_order_at,
               'finalized_at', visible_record.finalized_at,
               'finalized_by_user_id', visible_record.finalized_by_user_id,
               'finalizer_veterinarian_clinic_assignment_id', visible_record.finalizer_veterinarian_clinic_assignment_id,
               'amendments', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', clinical_amendment.id, 'reason', clinical_amendment.reason,
                   'amendment_content', clinical_amendment.amendment_content,
                   'amending_user_id', clinical_amendment.amending_user_id,
                   'amending_veterinarian_clinic_assignment_id', clinical_amendment.amending_veterinarian_clinic_assignment_id,
                   'created_at', clinical_amendment.created_at
               ) order by clinical_amendment.created_at, clinical_amendment.id)
               from (
                   select amendment_source.*
                   from public.clinical_amendments as amendment_source
                   where amendment_source.original_clinical_record_entry_id = visible_record.id
                   order by amendment_source.created_at, amendment_source.id
                   limit 100
               ) as clinical_amendment), '[]'::jsonb),
               'amendment_count', (
                   select count(*) from public.clinical_amendments as amendment_count_source
                   where amendment_count_source.original_clinical_record_entry_id = visible_record.id
               ),
               'amendments_truncated', (
                   select count(*) > 100 from public.clinical_amendments as amendment_count_source
                   where amendment_count_source.original_clinical_record_entry_id = visible_record.id
               )
           ) order by visible_record.history_order_at desc, visible_record.id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page_rows),
           (array_agg(visible_record.history_order_at order by visible_record.history_order_at desc, visible_record.id desc))[bounded_limit],
           (array_agg(visible_record.id order by visible_record.history_order_at desc, visible_record.id desc))[bounded_limit]
    into result_payload, has_more, next_order_at, next_entry_id
    from visible_rows as visible_record;

    perform public.establish_medical_access_audit_event(
        acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'PERMITTED',
        'PROFESSIONAL_CLINICAL', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
        null, care_auth_record.id, p_accessing_clinic_id, professional_context.organization_id,
        care_auth_record.appointment_id, professional_context.organization_membership_id,
        professional_context.organization_responsibility_grant_id,
        professional_context.veterinarian_clinic_assignment_id,
        p_clinical_encounter_id, null, null
    );
    return jsonb_build_object(
        'status', 'PERMITTED', 'payload', jsonb_build_object('entries', result_payload),
        'cursor', case when has_more then jsonb_build_object(
            'before_history_order_at', next_order_at, 'before_entry_id', next_entry_id
        ) else null end
    );
end;
$$;

revoke all privileges
on function public.slice12_view_professional_pet_medical_history(
    uuid, uuid, uuid, uuid, integer, timestamptz, uuid
)
from public, anon, authenticated;

create or replace function public.authorize_clinical_attachment_download(
    p_auth_subject uuid,
    p_attachment_id uuid,
    p_access_context text,
    p_professional_scope text default null,
    p_accessing_clinic_id uuid default null,
    p_care_authorization_id uuid default null,
    p_accessing_clinical_encounter_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    attachment_record public.clinical_attachments%rowtype;
    record_entry public.clinical_record_entries%rowtype;
    origin_encounter public.clinical_encounters%rowtype;
    origin_care_auth public.care_authorizations%rowtype;
    access_care_auth public.care_authorizations%rowtype;
    access_encounter public.clinical_encounters%rowtype;
    guardianship_record public.guardianships%rowtype;
    professional_context record;
    accessing_organization_id uuid;
    professional_context_available boolean := false;
    audit_organization_membership_id uuid := null;
    audit_organization_responsibility_grant_id uuid := null;
    audit_veterinarian_clinic_assignment_id uuid := null;
    permitted boolean := false;
    exact_context_matches boolean := false;
    audit_care_authorization_id uuid;
    audit_appointment_id uuid;
begin
    if p_access_context is null
       or p_access_context not in ('GUARDIAN', 'PROFESSIONAL') then
        raise exception 'Access context must be GUARDIAN or PROFESSIONAL' using errcode = '22023';
    end if;
    if p_access_context = 'GUARDIAN' and (
        p_professional_scope is not null or p_accessing_clinic_id is not null
        or p_care_authorization_id is not null or p_accessing_clinical_encounter_id is not null
    ) then raise exception 'Guardian access cannot carry professional context' using errcode = '22023'; end if;
    if p_access_context = 'PROFESSIONAL'
       and (
           p_professional_scope is null
           or p_professional_scope not in ('LONGITUDINAL', 'EXACT_RESOURCE')
       ) then
        raise exception 'Professional scope must be explicit' using errcode = '22023';
    end if;
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth' and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id;
    if not found then return jsonb_build_object('status', 'DENIED'); end if;
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = attachment_record.clinical_record_entry_id;
    select encounter_row.* into origin_encounter from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select care_auth.* into origin_care_auth from public.care_authorizations as care_auth
    where care_auth.id = origin_encounter.care_authorization_id;
    if p_access_context = 'GUARDIAN' then
        select guardianship.* into guardianship_record from public.guardianships as guardianship
        where guardianship.pet_id = origin_encounter.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
        for share;
        if not found then
            select guardianship.* into guardianship_record from public.guardianships as guardianship
            where guardianship.pet_id = origin_encounter.pet_id and guardianship.user_id = acting_user_id
            order by guardianship.effective_start desc, guardianship.id desc limit 1;
        end if;
        perform 1 from public.clinical_encounters as encounter_row
        where encounter_row.id = origin_encounter.id for share;
        select entry_row.* into record_entry from public.clinical_record_entries as entry_row
        where entry_row.id = record_entry.id for share;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
        permitted := guardianship_record.id is not null
            and guardianship_record.effective_start <= clock_timestamp()
            and guardianship_record.effective_end is null
            and record_entry.lifecycle_state = 'FINALIZED'
            and attachment_record.removed_at is null
            and attachment_record.validation_state = 'AVAILABLE'
            and attachment_record.object_state = 'STORED';
    elsif p_professional_scope = 'LONGITUDINAL' then
        select clinic.organization_id into accessing_organization_id
        from public.clinics as clinic where clinic.id = p_accessing_clinic_id;
        select * into professional_context
        from public.find_current_veterinarian_context_after_lock(
            acting_user_id, p_accessing_clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
        );
        professional_context_available := found;
        if professional_context_available then
            audit_organization_membership_id := professional_context.organization_membership_id;
            audit_organization_responsibility_grant_id :=
                professional_context.organization_responsibility_grant_id;
            audit_veterinarian_clinic_assignment_id :=
                professional_context.veterinarian_clinic_assignment_id;
            select care_auth.* into access_care_auth from public.care_authorizations as care_auth
            where care_auth.id = p_care_authorization_id
              and care_auth.pet_id = origin_encounter.pet_id
              and care_auth.clinic_id = p_accessing_clinic_id
              and care_auth.organization_id = professional_context.organization_id;
            if found and access_care_auth.appointment_id is not null then
                perform 1 from public.appointments as appointment
                where appointment.id = access_care_auth.appointment_id for share;
            end if;
            select care_auth.* into access_care_auth from public.care_authorizations as care_auth
            where care_auth.id = p_care_authorization_id
              and care_auth.pet_id = origin_encounter.pet_id
              and care_auth.clinic_id = p_accessing_clinic_id
              and care_auth.organization_id = professional_context.organization_id
            for share;
            if found and access_care_auth.lifecycle_state = 'ACTIVE' then
                if p_accessing_clinical_encounter_id is null
                   and access_care_auth.purpose = 'APPOINTMENT_CARE'
                   and public.appointment_permits_pre_care_access(
                       access_care_auth.appointment_id, clock_timestamp()
                   )
                   and not exists (select 1 from public.clinical_encounters as encounter_row
                                   where encounter_row.care_authorization_id = access_care_auth.id) then
                    permitted := true;
                elsif p_accessing_clinical_encounter_id is not null then
                    select encounter_row.* into access_encounter from public.clinical_encounters as encounter_row
                    where encounter_row.id = p_accessing_clinical_encounter_id
                      and encounter_row.care_authorization_id = access_care_auth.id
                      and encounter_row.pet_id = origin_encounter.pet_id
                      and encounter_row.clinic_id = p_accessing_clinic_id
                      and encounter_row.organization_id = professional_context.organization_id
                    for share;
                    permitted := found and access_encounter.lifecycle_state = 'ACTIVE';
                end if;
            end if;
        end if;
        perform 1 from public.clinical_record_entries as entry_row
        where entry_row.id = record_entry.id for share;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
        permitted := permitted and record_entry.lifecycle_state = 'FINALIZED'
            and attachment_record.removed_at is null
            and attachment_record.validation_state = 'AVAILABLE'
            and attachment_record.object_state = 'STORED';
        -- Longitudinal authority may be based on a different care episode.
        -- The typed resource chain therefore records the origin Encounter while
        -- leaving the optional origin Care Authorization/Appointment slots null.
        audit_care_authorization_id := null;
        audit_appointment_id := null;
    else
        select clinic.organization_id into accessing_organization_id
        from public.clinics as clinic where clinic.id = p_accessing_clinic_id;
        exact_context_matches := p_accessing_clinic_id is not distinct from origin_encounter.clinic_id
            and (p_care_authorization_id is null
                 or p_care_authorization_id is not distinct from origin_care_auth.id)
            and (p_accessing_clinical_encounter_id is null
                 or p_accessing_clinical_encounter_id is not distinct from origin_encounter.id);
        if not exact_context_matches then
            permitted := false;
        else
            select * into professional_context
            from public.find_current_veterinarian_context_after_lock(
                acting_user_id, origin_encounter.clinic_id, 'CLINICAL_DOCUMENTATION', null
            );
            professional_context_available := found;
            if professional_context_available then
                audit_organization_membership_id := professional_context.organization_membership_id;
                audit_organization_responsibility_grant_id :=
                    professional_context.organization_responsibility_grant_id;
                audit_veterinarian_clinic_assignment_id :=
                    professional_context.veterinarian_clinic_assignment_id;
                select care_auth.* into origin_care_auth from public.care_authorizations as care_auth
                where care_auth.id = origin_encounter.care_authorization_id for share;
                select encounter_row.* into origin_encounter from public.clinical_encounters as encounter_row
                where encounter_row.id = origin_encounter.id for share;
                select entry_row.* into record_entry from public.clinical_record_entries as entry_row
                where entry_row.id = record_entry.id for share;
                select attachment.* into attachment_record from public.clinical_attachments as attachment
                where attachment.id = p_attachment_id for share;
                permitted := (
                    (origin_care_auth.lifecycle_state = 'ACTIVE'
                     and public.organization_has_professional_entitlement(
                         professional_context.organization_id, 'CLINICAL_DOCUMENTATION'))
                    or origin_encounter.lifecycle_state = 'ACTIVE'
                    or (origin_encounter.lifecycle_state = 'CONCLUDED'
                        and origin_care_auth.lifecycle_state = 'ACTIVE')
                ) and attachment_record.removed_at is null
                  and attachment_record.validation_state = 'AVAILABLE'
                  and attachment_record.object_state = 'STORED';
            end if;
        end if;
        audit_care_authorization_id := case when exact_context_matches then origin_care_auth.id else null end;
        audit_appointment_id := case when exact_context_matches then origin_encounter.appointment_id else null end;
    end if;

    if permitted and not exists (
        select 1 from storage.objects as object_record
        where object_record.bucket_id = 'clinical-attachments'
          and object_record.name = 'v1/' || attachment_record.storage_object_id::text
    ) then
        raise exception 'Authorized Clinical Attachment Storage object is missing'
            using errcode = 'XX001';
    end if;

    perform public.establish_medical_access_audit_event(
        acting_user_id, origin_encounter.pet_id, 'VIEW_CLINICAL_ATTACHMENT',
        case when permitted then 'PERMITTED' else 'DENIED' end,
        case when p_access_context = 'GUARDIAN' then 'GUARDIAN' else 'PROFESSIONAL_CLINICAL' end,
        'CLINICAL_ATTACHMENT', clock_timestamp(),
        case when p_access_context = 'GUARDIAN' then guardianship_record.id else null end,
        audit_care_authorization_id,
        case when p_access_context = 'PROFESSIONAL' and accessing_organization_id is not null
             then p_accessing_clinic_id else null end,
        case when p_access_context = 'PROFESSIONAL' then accessing_organization_id else null end,
        audit_appointment_id,
        audit_organization_membership_id,
        audit_organization_responsibility_grant_id,
        audit_veterinarian_clinic_assignment_id,
        origin_encounter.id, record_entry.id, null, attachment_record.id
    );
    if not permitted then return jsonb_build_object('status', 'DENIED'); end if;
    return jsonb_build_object(
        'status', 'PERMITTED',
        'attachment_id', attachment_record.id,
        'storage_object_id', attachment_record.storage_object_id,
        'original_filename', attachment_record.original_filename
    );
end;
$$;

revoke all privileges
on function public.authorize_clinical_attachment_download(
    uuid, uuid, text, text, uuid, uuid, uuid
)
from public, anon, authenticated;

grant execute
on function public.authorize_clinical_attachment_download(
    uuid, uuid, text, text, uuid, uuid, uuid
)
to service_role;

-- ==================================================================
-- 8. Authoritative SYSTEM expiry materialization.
-- ==================================================================

-- Materializes every logically expired request as of p_reference_time
-- (SPEC-APT-015 BR-5–BR-7, BR-11–BR-13, BR-17). Returns how many
-- Appointments it expired. Idempotent: a rerun finds nothing to do.
--
-- Locks follow the established Organization -> Clinic -> Appointment ->
-- Care Authorization order, candidates are processed in
-- (Organization, Clinic, Appointment) order, and eligibility is re-checked
-- under lock, so a concurrent confirmation, cancellation, or reschedule
-- either commits first (and the Appointment is skipped) or waits and then
-- observes EXPIRED. The reference time can never be in the future, so no
-- request is expired before its requested start.
create function public.expire_lapsed_appointment_requests(
    p_reference_time timestamptz default clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    candidate record;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    logical_expiry_at timestamptz;
    expired_count integer := 0;
begin
    if p_reference_time is null or not isfinite(p_reference_time) then
        raise exception 'Expiry reference time must be finite'
            using errcode = '22023';
    end if;

    if p_reference_time > clock_timestamp() then
        raise exception 'Expiry reference time must not be in the future'
            using errcode = '22023';
    end if;

    for candidate in
        select appointment.id as appointment_id,
               appointment.clinic_id,
               clinic.organization_id
        from public.appointments as appointment
        join public.clinics as clinic
          on clinic.id = appointment.clinic_id
        where appointment.lifecycle_state = 'REQUESTED'
          and public.appointment_latest_requested_start_at(appointment.id) <= p_reference_time
        order by clinic.organization_id, appointment.clinic_id, appointment.id
    loop
        perform 1
        from public.veterinary_organizations as organization
        where organization.id = candidate.organization_id
        for update;

        perform 1
        from public.clinics as clinic
        where clinic.id = candidate.clinic_id
        for update;

        select appointment.*
        into appointment_record
        from public.appointments as appointment
        where appointment.id = candidate.appointment_id
        for update;

        if appointment_record.lifecycle_state <> 'REQUESTED' then
            continue;
        end if;

        logical_expiry_at := public.appointment_latest_requested_start_at(candidate.appointment_id);

        if logical_expiry_at is null or logical_expiry_at > p_reference_time then
            continue;
        end if;

        select care_auth.*
        into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = candidate.appointment_id
        for update;

        if not found then
            raise exception 'Appointment % has no Appointment-derived Care Authorization',
                candidate.appointment_id
                using errcode = '23514';
        end if;

        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context,
            reason, effective_at, recorded_at, clinical_encounter_id
        ) values (
            candidate.appointment_id, 'REQUESTED', 'EXPIRED', null, 'SYSTEM',
            null, logical_expiry_at, clock_timestamp(), null
        );

        update public.appointments
        set lifecycle_state = 'EXPIRED'
        where id = candidate.appointment_id;

        if care_auth_record.lifecycle_state = 'ACTIVE' then
            update public.care_authorizations
            set lifecycle_state = 'ENDED',
                ended_at = logical_expiry_at,
                ended_reason = 'APPOINTMENT_EXPIRED'
            where id = care_auth_record.id;
        end if;

        expired_count := expired_count + 1;
    end loop;

    return expired_count;
end;
$$;

revoke all privileges
on function public.expire_lapsed_appointment_requests(timestamptz)
from public, anon, authenticated;

commit;

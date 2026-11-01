-- SPEC-APT-009 — Lightweight Appointment completion (Migration 1).
--
-- Completion becomes the Clinic's administrative assertion that the confirmed
-- visit occurred. It no longer requires, consumes, or references a Clinical
-- Encounter, a Veterinarian Assignment, or clinical documentation
-- (SPEC-APT-009 BR-2, BR-12, BR-15; SPEC-MED-001 BR-35).
--
-- 1. `complete_appointment(p_appointment_id uuid, p_clinical_encounter_id
--    uuid)` is dropped — it is not kept as an overload, because it would keep
--    the obsolete Encounter-evidence requirement and bypass the stale check
--    (SPEC-APT-009 §4 "Contract compatibility") — and replaced by
--    `complete_appointment(p_appointment_id uuid,
--    p_expected_confirmed_revision_sequence integer) returns uuid`, mirroring
--    the stale-safe NO_SHOW contract (20261005090000):
--      * a NULL or non-positive expected sequence is invalid input (22023),
--        evaluated before any Appointment state is consulted;
--      * Organization -> Clinic APPOINTMENT_COMPLETE capability lock, with no
--        Entitlement gate (SPEC-APT-009 BR-6);
--      * Appointment row lock, then CONFIRMED (lifecycle precedes staleness);
--      * the latest CONFIRMED revision's sequence must equal the expected one,
--        otherwise plain P0001 'Stale confirmed Appointment schedule revision'
--        with zero writes;
--      * that same revision's scheduled start must have been reached;
--      * one CONFIRMED -> COMPLETED Lifecycle Event (Clinic actor, acting User,
--        effective and recorded at the operation time, no Encounter
--        reference), then the COMPLETED state. A pending Reschedule Proposal
--        becomes VOID and the APPOINTMENT_COMPLETED Communications are
--        established by the existing lifecycle triggers; the Care
--        Authorization, any Clinical Encounter, and any Veterinarian
--        Assignment are neither read nor written.
--    The operation returns the Appointment identifier, like confirmation,
--    cancellation, and NO_SHOW.
--
-- 2. Lifecycle Event -> Clinical Encounter becomes legacy provenance only
--    (SPEC-APT-009 BR-15, RELATIONAL_MODEL):
--      * `appointment_lifecycle_events_encounter_shape_check` no longer
--        requires an Encounter on a COMPLETED Event; non-COMPLETED Events still
--        carry none;
--      * a new BEFORE INSERT rule rejects any Encounter reference on a new
--        Event. Lifecycle Events are already immutable after insert
--        (appointment_lifecycle_events_preserve_history), so historical
--        COMPLETED Events keep their reference and no new one can appear;
--      * the column is not dropped (deferred cleanup).
--
-- 3. Deferred coherence no longer treats the Encounter as completion evidence.
--    For a COMPLETED Appointment:
--      * a legacy Encounter reference, where present, must still identify an
--        Encounter of the same Appointment, Pet, and Clinic that began no
--        later than the completion (historical consistency unchanged);
--      * every Appointment-backed Encounter of the Appointment must have begun
--        no later than the completion Event (SPEC-MED-001 BR-35), whichever
--        was recorded first;
--      * `assert_clinical_encounter_appointment_coherence` no longer requires
--        the completion Event to reference the Encounter — otherwise an
--        Encounter established before an Encounter-less completion would fail
--        its deferred check on its next UPDATE (for example conclusion). It
--        now requires the same Pet, Clinic, and Appointment-derived Care
--        Authorization, the start bound above, and agreement with any legacy
--        reference.
--    Every other lifecycle, provenance, NO_SHOW, cancellation, and EXPIRED
--    rule is carried over verbatim from 20261004090000.
--
-- Not changed here (Migration 2): Clinical Encounter establishment still
-- requires a CONFIRMED Appointment (`assert_clinical_encounter_establishment`),
-- so no Encounter can yet be created for a COMPLETED Appointment.
--
-- No table, column, or index is added or removed, and no existing row is
-- changed.

begin;

-- ==================================================================
-- 1. Lifecycle Event Encounter reference: legacy only.
-- ==================================================================

alter table public.appointment_lifecycle_events
drop constraint appointment_lifecycle_events_encounter_shape_check;

alter table public.appointment_lifecycle_events
add constraint appointment_lifecycle_events_encounter_shape_check
check (to_state = 'COMPLETED' or clinical_encounter_id is null);

create function public.enforce_appointment_lifecycle_event_no_new_encounter_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.clinical_encounter_id is not null then
        raise exception 'New Appointment Lifecycle Events must not reference a Clinical Encounter'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_lifecycle_event_no_new_encounter_reference()
from public, anon, authenticated;

create trigger appointment_lifecycle_events_no_new_encounter_reference
before insert on public.appointment_lifecycle_events
for each row
execute function public.enforce_appointment_lifecycle_event_no_new_encounter_reference();

-- ==================================================================
-- 2. Deferred Appointment lifecycle coherence (20261004090000 verbatim,
--    except the COMPLETED branch).
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
        -- Legacy completion provenance: a historical Event that references an
        -- Encounter must still identify a compatible one.
        if lifecycle_event_record.clinical_encounter_id is not null then
            select encounter_row.* into encounter_record
            from public.clinical_encounters as encounter_row
            where encounter_row.id = lifecycle_event_record.clinical_encounter_id;

            if not found
               or encounter_record.appointment_id is distinct from appointment_record.id
               or encounter_record.pet_id is distinct from appointment_record.pet_id
               or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
                raise exception 'COMPLETED Appointment % legacy Clinical Encounter reference is incompatible', p_appointment_id
                    using errcode = '23514';
            end if;
        end if;

        -- SPEC-MED-001 BR-35: no Appointment-backed care began after the
        -- Clinic declared the Appointment completed.
        if exists (
            select 1
            from public.clinical_encounters as encounter_row
            where encounter_row.appointment_id = p_appointment_id
              and encounter_row.started_at > lifecycle_event_record.effective_at
        ) then
            raise exception 'COMPLETED Appointment % Event cannot precede the start of its Clinical Encounter', p_appointment_id
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

-- ==================================================================
-- 3. Deferred Lifecycle Event provenance (20261004090000 verbatim, except
--    the COMPLETED branch, which also gains the scheduled-start rule).
-- ==================================================================

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
        if lifecycle_event_record.clinical_encounter_id is not null then
            select encounter_row.* into encounter_record
            from public.clinical_encounters as encounter_row
            where encounter_row.id = lifecycle_event_record.clinical_encounter_id;
            if not found
               or encounter_record.appointment_id is distinct from appointment_record.id
               or encounter_record.pet_id is distinct from appointment_record.pet_id
               or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
                raise exception 'Completion Event % legacy Clinical Encounter reference is incompatible', p_event_id
                    using errcode = '23514';
            end if;
        end if;

        if exists (
            select 1
            from public.clinical_encounters as encounter_row
            where encounter_row.appointment_id = appointment_record.id
              and encounter_row.started_at > lifecycle_event_record.effective_at
        ) then
            raise exception 'Completion Event % cannot precede the start of its Clinical Encounter', p_event_id
                using errcode = '23514';
        end if;

        -- SPEC-APT-009 BR-7: completion is permitted from the latest
        -- confirmed start. Encounter-backed completion previously enforced an
        -- equivalent bound through the Encounter; this keeps the time rule
        -- structural for Encounter-less completion.
        select revision.scheduled_start_at
        into latest_confirmed_scheduled_start_at
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED'
        order by revision.revision_sequence desc
        limit 1;

        if not found then
            raise exception 'Completion Event % requires its latest CONFIRMED Schedule Revision', p_event_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.clinical_encounter_id is null
           and lifecycle_event_record.effective_at < latest_confirmed_scheduled_start_at then
            raise exception 'Completion Event % cannot precede its latest confirmed scheduled start', p_event_id
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

-- ==================================================================
-- 4. Deferred Clinical Encounter <-> Appointment coherence.
-- ==================================================================

create or replace function public.assert_clinical_encounter_appointment_coherence(
    p_clinical_encounter_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    encounter_record public.clinical_encounters%rowtype;
    appointment_record public.appointments%rowtype;
    completion_event_record public.appointment_lifecycle_events%rowtype;
begin
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id;
    if not found or encounter_record.appointment_id is null then return; end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = encounter_record.appointment_id
    for update;

    if appointment_record.lifecycle_state not in ('CONFIRMED', 'COMPLETED') then
        raise exception 'Appointment-derived Clinical Encounter % requires a CONFIRMED or COMPLETED Appointment', p_clinical_encounter_id
            using errcode = '23514';
    end if;

    if appointment_record.lifecycle_state = 'COMPLETED' then
        if encounter_record.pet_id is distinct from appointment_record.pet_id
           or encounter_record.clinic_id is distinct from appointment_record.clinic_id
           or not exists (
               select 1 from public.care_authorizations as care_auth
               where care_auth.id = encounter_record.care_authorization_id
                 and care_auth.appointment_id = appointment_record.id
           ) then
            raise exception 'Clinical Encounter % must match its COMPLETED Appointment and its Care Authorization', p_clinical_encounter_id
                using errcode = '23514';
        end if;

        select lifecycle_event.* into completion_event_record
        from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = appointment_record.id
          and lifecycle_event.to_state = 'COMPLETED';

        if not found then
            raise exception 'COMPLETED Appointment of Clinical Encounter % has no completion Event', p_clinical_encounter_id
                using errcode = '23514';
        end if;

        if encounter_record.started_at > completion_event_record.effective_at then
            raise exception 'Clinical Encounter % cannot begin after its Appointment was completed', p_clinical_encounter_id
                using errcode = '23514';
        end if;

        if completion_event_record.clinical_encounter_id is not null
           and completion_event_record.clinical_encounter_id <> encounter_record.id then
            raise exception 'Clinical Encounter % disagrees with its Appointment''s legacy completion reference', p_clinical_encounter_id
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinical_encounter_appointment_coherence(uuid)
from public, anon, authenticated;

-- ==================================================================
-- 5. SPEC-APT-009 — stale-safe lightweight completion.
-- ==================================================================

drop function public.complete_appointment(uuid, uuid);

create function public.complete_appointment(
    p_appointment_id uuid,
    p_expected_confirmed_revision_sequence integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    latest_confirmed_revision public.appointment_schedule_revisions%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    -- BR-8: structurally invalid input, rejected before any Appointment state
    -- is consulted. Distinct from a stale (well-formed but superseded)
    -- expected sequence.
    if p_expected_confirmed_revision_sequence is null
       or p_expected_confirmed_revision_sequence <= 0 then
        raise exception 'Expected confirmed revision sequence must be a positive integer'
            using errcode = '22023';
    end if;

    select appointment.clinic_id into appointment_clinic_id from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;

    -- BR-3/BR-6: Organization -> Clinic capability lock, no Entitlement gate.
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, appointment_clinic_id, 'APPOINTMENT_COMPLETE'
    );
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;

    -- BR-8/BR-11: lifecycle precedes staleness. An Appointment that is no
    -- longer CONFIRMED is an invalid transition, never a stale request.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may be completed' using errcode = '23514';
    end if;

    select revision.* into latest_confirmed_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc limit 1;
    if not found then
        raise exception 'Appointment % has no confirmed scheduling context', p_appointment_id
            using errcode = '23514';
    end if;

    -- BR-9/BR-10: the revision sequence alone decides staleness, never the
    -- scheduled values. Deterministic client-input mismatch: plain P0001.
    if latest_confirmed_revision.revision_sequence <> p_expected_confirmed_revision_sequence then
        raise exception 'Stale confirmed Appointment schedule revision';
    end if;

    operation_timestamp := clock_timestamp();
    -- BR-7: permitted once the reviewed (and current) confirmed start has
    -- been reached; the scheduled end is not required.
    if latest_confirmed_revision.scheduled_start_at > operation_timestamp then
        raise exception 'Appointment cannot be completed before its confirmed scheduled start' using errcode = '23514';
    end if;

    -- BR-12/BR-15: no Clinical Encounter, Veterinarian Assignment, or Care
    -- Authorization is read or written; the Event carries no Encounter.
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at, clinical_encounter_id
    ) values (
        p_appointment_id, 'CONFIRMED', 'COMPLETED', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp, null
    );
    update public.appointments set lifecycle_state = 'COMPLETED' where id = p_appointment_id;
    return p_appointment_id;
end;
$$;

revoke all privileges on function public.complete_appointment(uuid, integer)
from public, anon, authenticated;
grant execute on function public.complete_appointment(uuid, integer) to authenticated;

commit;

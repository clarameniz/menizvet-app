-- SPEC-APT-003 BR-24–BR-29 — stale-safe Clinic Appointment cancellation.
--
-- `cancel_appointment(p_appointment_id uuid, p_cancelling_context text,
-- p_reason text default null)` cancelled whatever the Appointment's current
-- scheduling context was at execution time. A Guardian requested-time
-- reschedule or an accepted confirmed reschedule committed after a Clinic actor
-- read the schedule could make that actor cancel a scheduling context they
-- never reviewed.
--
-- This migration replaces it with
-- `cancel_appointment(p_appointment_id uuid, p_cancelling_context text,
-- p_reason text default null,
-- p_expected_schedule_revision_sequence integer default null) returns uuid`:
--
--   * CLINIC context (BR-24, BR-25): before any Appointment state is
--     consulted, a NULL or non-positive expected sequence and a missing or
--     blank reason are structurally invalid input (22023). Then, unchanged:
--     the Organization -> Clinic APPOINTMENT_CANCEL capability lock (no
--     Entitlement gate, SPEC-APT-003 BR-19 / SPEC-SUB-004), the Appointment
--     row lock, and the REQUESTED/CONFIRMED lifecycle check. Then the latest
--     Schedule Revision of the Appointment's current lifecycle context
--     (REQUESTED -> latest REQUESTED, CONFIRMED -> latest CONFIRMED; the
--     revision whose sequence the Clinic schedule returns as
--     current_schedule_revision_sequence) must have exactly the expected
--     sequence; otherwise 'Stale Appointment schedule revision for
--     cancellation' is raised as plain P0001 — the repository's
--     deterministic stale-revision convention
--     (20260917120000_postgrest_conflict_status_correction.sql; never 40001
--     or PT409, which PostgREST or supabase-js may retry). Only then do the
--     unchanged pending-request, Clinical Encounter, and Care Authorization
--     rules and writes run.
--   * GUARDIAN context (BR-29): unchanged in every respect, except that a
--     non-NULL expected sequence — which no Guardian caller sends — is
--     rejected as invalid input (22023) instead of being silently ignored.
--
-- Because the lifecycle check precedes the revision check, an Appointment that
-- is already terminal is rejected as an invalid lifecycle transition, never as
-- stale. Cancellation of a CONFIRMED Appointment whose start has passed is
-- deliberately unchanged (SPEC-APT-003 BR-28, §7: undecided policy).
--
-- The three-argument form is dropped, not kept as an overload: it would let a
-- Clinic cancellation omit the token (SPEC-APT-003 §6 "Contract
-- compatibility") and would make PostgREST named-argument calls ambiguous. No
-- view, rule, or other function depends on or calls it. The Guardian mobile
-- call uses named arguments without the new parameter and keeps working
-- unchanged. ACL is re-applied exactly as before.
--
-- No table, column, constraint, index, trigger, or existing row is changed.

begin;

drop function public.cancel_appointment(uuid, text, text);

create function public.cancel_appointment(
    p_appointment_id uuid,
    p_cancelling_context text,
    p_reason text default null,
    p_expected_schedule_revision_sequence integer default null
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
    current_revision public.appointment_schedule_revisions%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_cancelling_context is null or p_cancelling_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Cancelling context must be GUARDIAN or CLINIC' using errcode = '22023';
    end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    -- SPEC-APT-003 BR-24/BR-25 step 2 and BR-29: structurally invalid input,
    -- rejected before any Appointment state is consulted.
    if p_cancelling_context = 'GUARDIAN' then
        if p_expected_schedule_revision_sequence is not null then
            raise exception 'Guardian cancellation does not accept an expected schedule revision sequence'
                using errcode = '22023';
        end if;
    else
        if p_expected_schedule_revision_sequence is null
           or p_expected_schedule_revision_sequence <= 0 then
            raise exception 'Expected schedule revision sequence must be a positive integer'
                using errcode = '22023';
        end if;
        if normalized_reason is null then
            raise exception 'A meaningful reason is required for a Clinic cancellation' using errcode = '22023';
        end if;
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
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;
    if appointment_record.lifecycle_state not in ('REQUESTED', 'CONFIRMED') then
        raise exception 'Only a REQUESTED or CONFIRMED Appointment may be cancelled' using errcode = '23514';
    end if;

    -- SPEC-APT-003 BR-25 steps 5–7 / BR-26 / BR-27: the revision sequence of
    -- the current scheduling context for the locked lifecycle state alone
    -- decides staleness, never the scheduled values. Deterministic
    -- client-input mismatch: plain P0001.
    if p_cancelling_context = 'CLINIC' then
        select revision.* into current_revision
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = p_appointment_id
          and revision.revision_context = appointment_record.lifecycle_state
        order by revision.revision_sequence desc limit 1;
        if not found then
            raise exception 'Appointment % has no current scheduling context', p_appointment_id
                using errcode = '23514';
        end if;
        if current_revision.revision_sequence <> p_expected_schedule_revision_sequence then
            raise exception 'Stale Appointment schedule revision for cancellation';
        end if;
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
on function public.cancel_appointment(uuid, text, text, integer)
from public, anon, authenticated;

grant execute
on function public.cancel_appointment(uuid, text, text, integer)
to authenticated;

commit;

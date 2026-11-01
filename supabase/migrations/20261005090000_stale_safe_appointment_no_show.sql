-- SPEC-APT-010 BR-41/BR-42/BR-43/BR-44 — stale-safe professional NO_SHOW.
--
-- `mark_appointment_no_show(p_appointment_id uuid)` resolved the outcome
-- against whatever the Appointment's latest CONFIRMED Schedule Revision was at
-- execution time. A confirmed reschedule accepted after a Clinic actor read the
-- schedule could make the actor record a no-show against a confirmed time they
-- never reviewed.
--
-- This migration replaces it with
-- `mark_appointment_no_show(p_appointment_id uuid,
-- p_expected_confirmed_revision_sequence integer) returns uuid` (no default):
--
--   * a NULL or non-positive expected sequence is structurally invalid input
--     (22023, the repository's invalid-argument convention), evaluated before
--     any Appointment state is consulted;
--   * after the unchanged Organization -> Clinic capability lock
--     (APPOINTMENT_MARK_NO_SHOW, deliberately with no Entitlement gate per
--     SPEC-APT-010 BR-34), the Appointment row lock, and the CONFIRMED check,
--     the latest CONFIRMED revision's sequence must equal the expected
--     sequence; otherwise 'Stale confirmed Appointment schedule revision' is
--     raised as plain P0001 — the repository's deterministic stale-revision
--     convention (20260917120000_postgrest_conflict_status_correction.sql;
--     never 40001 or PT409, which PostgREST or supabase-js may retry);
--   * the very revision record that passed that comparison supplies the time
--     rule (start reached; the end is not required), so the operation cannot
--     switch to another confirmed revision after the stale check;
--   * the existing Clinical Encounter prohibition, Care Authorization ending
--     (APPOINTMENT_NO_SHOW at the operation time, equal to the Event time),
--     and APPOINTMENT_NO_SHOW Communications (lifecycle trigger) are
--     unchanged, as is the original order of the Encounter and time checks.
--
-- The identifier-only form is dropped, not kept as an overload: it would
-- bypass the stale check (SPEC-APT-010 §4 "Contract compatibility"). No view,
-- rule, or other function depends on or calls it; no mobile client, Edge
-- Function, or runbook calls it. ACL is re-applied exactly as before.
--
-- No table, column, constraint, index, trigger, or existing row is changed.

begin;

drop function public.mark_appointment_no_show(uuid);

create function public.mark_appointment_no_show(
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
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    -- BR-41: structurally invalid input, rejected before any Appointment
    -- state is consulted. Distinct from a stale (well-formed but superseded)
    -- expected sequence.
    if p_expected_confirmed_revision_sequence is null
       or p_expected_confirmed_revision_sequence <= 0 then
        raise exception 'Expected confirmed revision sequence must be a positive integer'
            using errcode = '22023';
    end if;

    select appointment.clinic_id into appointment_clinic_id from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, appointment_clinic_id, 'APPOINTMENT_MARK_NO_SHOW'
    );
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;

    -- Lifecycle precedes staleness: an Appointment that is no longer
    -- CONFIRMED is an invalid transition, never a stale request.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may be marked no-show' using errcode = '23514';
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

    -- BR-42/BR-43: the revision sequence alone decides staleness, never the
    -- scheduled values. Deterministic client-input mismatch: plain P0001.
    if latest_confirmed_revision.revision_sequence <> p_expected_confirmed_revision_sequence then
        raise exception 'Stale confirmed Appointment schedule revision';
    end if;

    if exists (select 1 from public.clinical_encounters as encounter_row
               where encounter_row.appointment_id = p_appointment_id) then
        raise exception 'Appointment with a Clinical Encounter cannot be marked no-show' using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();
    -- BR-44: permitted once the reviewed (and current) confirmed start has
    -- been reached; the scheduled end is not required.
    if latest_confirmed_revision.scheduled_start_at > operation_timestamp then
        raise exception 'Appointment cannot be marked no-show before its confirmed scheduled start' using errcode = '23514';
    end if;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id for update;
    if not found then raise exception 'Appointment has no Care Authorization' using errcode = '23514'; end if;
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at, clinical_encounter_id
    ) values (
        p_appointment_id, 'CONFIRMED', 'NO_SHOW', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp, null
    );
    update public.appointments set lifecycle_state = 'NO_SHOW' where id = p_appointment_id;
    if care_auth_record.lifecycle_state = 'ACTIVE' then
        update public.care_authorizations
        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_NO_SHOW'
        where id = care_auth_record.id;
    end if;
    return p_appointment_id;
end;
$$;

revoke all privileges on function public.mark_appointment_no_show(uuid, integer)
from public, anon, authenticated;
grant execute on function public.mark_appointment_no_show(uuid, integer) to authenticated;

commit;

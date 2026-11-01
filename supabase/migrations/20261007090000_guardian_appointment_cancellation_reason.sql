-- SPEC-APT-011 BR-31 — the Guardian Appointment read exposes the
-- cancellation reason of a CANCELLED Appointment.
--
-- The cancellation reason is already stored, immutably, on the Appointment's
-- single CANCELLED Lifecycle Event (`appointment_lifecycle_events.reason`,
-- written by `cancel_appointment` for both GUARDIAN and CLINIC cancellations;
-- trimmed and non-empty when present by
-- `appointment_lifecycle_events_reason_check`; required for CLINIC by
-- `appointment_lifecycle_events_clinic_cancellation_reason_check`; at most one
-- CANCELLED Event per Appointment by `appointment_lifecycle_events_cancellation_key`).
-- No read exposed it to Guardians.
--
-- This migration adds exactly one column, `cancellation_reason text`, at the
-- END of `get_pet_appointments(uuid)`:
--
--   * for a CANCELLED Appointment: the `reason` of its CANCELLED Lifecycle
--     Event, exactly as stored (NULL when a Guardian cancelled without one);
--   * for every other lifecycle state: NULL.
--
-- It is never derived from the reason for visit, Guardian notes,
-- Communications, or the displayed Schedule Revision, and no other Lifecycle
-- Event field (actor, context, times) or other Event is exposed.
--
-- Because a RETURNS TABLE column set cannot change through CREATE OR REPLACE,
-- the read is dropped and recreated (precedent:
-- 20261003090000_stale_safe_appointment_confirmation.sql). Dependency
-- inspection: no view, rule, or other function depends on or calls it; only
-- clients call it, by column name. Body, attributes (STABLE, SECURITY DEFINER,
-- empty search_path), authorization, SQLSTATEs, row filtering, relevant
-- scheduled interval, pending-Proposal projection, ordering, and ACL are
-- otherwise copied verbatim from
-- 20261002090000_appointment_relevant_scheduled_interval.sql.
--
-- `get_clinic_appointment_schedule` is unchanged. No table, column,
-- constraint, index, trigger, or existing row is changed; existing cancelled
-- Appointments expose their already-stored reason without any backfill.

begin;

drop function public.get_pet_appointments(uuid);

create function public.get_pet_appointments(
    p_pet_id uuid
)
returns table (
    id uuid,
    clinic_id uuid,
    requesting_user_id uuid,
    reason_for_visit text,
    guardian_notes text,
    lifecycle_state text,
    created_at timestamptz,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text,
    cancellation_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
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
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    return query
    select
        appointment.id,
        appointment.clinic_id,
        appointment.requesting_user_id,
        appointment.reason_for_visit,
        appointment.guardian_notes,
        appointment.lifecycle_state,
        appointment.created_at,
        current_revision.scheduled_start_at,
        current_revision.scheduled_end_at,
        current_revision.establishment_timezone_name,
        current_assignment.veterinarian_clinic_assignment_id,
        pending_proposal.id,
        pending_proposal.state,
        pending_proposal.proposing_context,
        pending_proposal.proposed_start_at,
        pending_proposal.proposed_end_at,
        pending_proposal.proposed_timezone_name,
        pending_proposal.reason,
        cancellation_event.reason
    from public.appointments as appointment
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at, revision.establishment_timezone_name
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    left join public.appointment_reschedule_proposals as pending_proposal
      on pending_proposal.appointment_id = appointment.id
     and pending_proposal.state = 'PENDING'
     and public.appointment_reschedule_proposal_is_actionable(
         pending_proposal.id,
         statement_timestamp()
     )
    -- SPEC-APT-011 BR-31: only a CANCELLED Appointment carries a cancellation
    -- reason, from its single CANCELLED Lifecycle Event.
    left join public.appointment_lifecycle_events as cancellation_event
      on cancellation_event.appointment_id = appointment.id
     and cancellation_event.to_state = 'CANCELLED'
     and appointment.lifecycle_state = 'CANCELLED'
    where appointment.pet_id = p_pet_id
    order by appointment.created_at, appointment.id;
end;
$$;

revoke all privileges
on function public.get_pet_appointments(uuid)
from public, anon, authenticated;

grant execute
on function public.get_pet_appointments(uuid)
to authenticated;

commit;

-- SPEC-APT-011 / SPEC-APT-012 — relevant scheduled interval correction
-- (SPEC-APT-011 §4 and VN 19; SPEC-APT-012 §4 and VN 27).
--
-- Both Appointment reads exposed the scheduled interval through a
-- lifecycle-context selection written before CANCELLED existed:
--
--   CONFIRMED / COMPLETED / NO_SHOW -> latest CONFIRMED Schedule Revision
--   anything else                   -> latest REQUESTED Schedule Revision
--
-- A CANCELLED Appointment that had been confirmed and then accepted one or
-- more confirmed reschedules therefore showed an earlier interval instead of
-- its final effective confirmed interval.
--
-- The approved relevant scheduled interval is the latest effective scheduling
-- context: the latest REQUESTED context if the Appointment was never
-- confirmed, otherwise the latest CONFIRMED context, including accepted
-- reschedules. Under the existing Schedule Revision invariants this is exactly
-- the revision with the highest `revision_sequence`:
--   * sequence 1 is REQUESTED and sequences are contiguous;
--   * REQUESTED revisions are created only while the Appointment is
--     REQUESTED, CONFIRMED revisions only while it is CONFIRMED, and
--     REQUESTED -> CONFIRMED is one-way, so every CONFIRMED revision follows
--     every REQUESTED revision;
--   * cancellation, completion, and no-show create no Schedule Revision.
-- For REQUESTED, CONFIRMED, COMPLETED, NO_SHOW, and never-confirmed
-- CANCELLED Appointments the selected revision is unchanged; only a
-- previously confirmed CANCELLED Appointment changes, to its latest CONFIRMED
-- revision.
--
-- Only the schedule-revision lateral join of the two reads changes. Return
-- signatures, attributes, authorization, SQLSTATEs, `pet_name`, current
-- Veterinarian Assignment, pending reschedule proposal, row filtering,
-- ordering, and ACLs are unchanged, so CREATE OR REPLACE is sufficient. No
-- table, row, Schedule Revision, Lifecycle Event, Proposal, or other function
-- is changed.

begin;

create or replace function public.get_pet_appointments(
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
    pending_reschedule_reason text
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
        pending_proposal.reason
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

create or replace function public.get_clinic_appointment_schedule(
    p_clinic_id uuid
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
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
    pending_reschedule_reason text
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

    if not public.user_has_clinic_capability(
        acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE'
    ) then
        raise exception 'Applicable Appointment schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        appointment.id,
        appointment.pet_id,
        pet.name,
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
        pending_proposal.reason
    from public.appointments as appointment
    join public.pets as pet
      on pet.id = appointment.pet_id
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
    where appointment.clinic_id = p_clinic_id
    order by appointment.created_at, appointment.id;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_schedule(uuid)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_schedule(uuid)
to authenticated;

commit;

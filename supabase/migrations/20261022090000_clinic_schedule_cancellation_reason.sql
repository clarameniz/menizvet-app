-- The Clinic Appointment Schedule exposes the recorded cancellation reason of
-- a CANCELLED Appointment (SPEC-APT-012 §4 "terminal outcome" and "relevant
-- operational information defined by Appointment Specifications"; SPEC-APT-003
-- BR-8/BR-9), so a Clinic can inspect the reason recorded — for example, the
-- reason it gave for a cancellation after the confirmed start (BR-31).
--
-- get_clinic_appointment_schedule(uuid) gains exactly one trailing column,
-- `cancellation_reason text`: for a CANCELLED Appointment the immutable reason
-- on its single CANCELLED Lifecycle Event (NULL when a Guardian cancelled
-- without one); NULL for every other lifecycle state. It is the same source
-- and rule get_pet_appointments uses since 20261007090000. No actor identity,
-- actor context, or Event time is exposed. No storage is duplicated.
--
-- Because a RETURNS TABLE column set cannot change through CREATE OR REPLACE,
-- the read is dropped and recreated (no database object depends on it), with
-- its body, attributes (SECURITY DEFINER, STABLE, empty search_path),
-- authorization, filtering, ordering, derived proposal values, and ACL
-- otherwise those of 20261016090000. No table, column, constraint, index,
-- trigger, or existing data changes.

begin;

drop function public.get_clinic_appointment_schedule(uuid);

create function public.get_clinic_appointment_schedule(
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
    current_schedule_revision_sequence integer,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text,
    current_schedule_source_proposal_id uuid,
    current_schedule_source_proposing_context text,
    pending_reschedule_currently_feasible boolean,
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

    if not public.user_has_clinic_capability(
        acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE'
    ) then
        raise exception 'Applicable Appointment schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    -- The Clinic's current timezone, validated once and only when the Clinic
    -- has a PENDING proposal (NULL when absent or invalid).
    with pending_clinic_timezone as materialized (
        select case
                   when public.clinic_timezone_name_is_valid(clinic.scheduling_timezone_name)
                       then clinic.scheduling_timezone_name
               end as valid_timezone_name
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and exists (
              select 1
              from public.appointments as pending_appointment
              join public.appointment_reschedule_proposals as pending
                on pending.appointment_id = pending_appointment.id
               and pending.state = 'PENDING'
              where pending_appointment.clinic_id = p_clinic_id
          )
    )
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
        current_revision.revision_sequence,
        current_assignment.veterinarian_clinic_assignment_id,
        pending_proposal.id,
        pending_proposal.state,
        pending_proposal.proposing_context,
        pending_proposal.proposed_start_at,
        pending_proposal.proposed_end_at,
        pending_proposal.proposed_timezone_name,
        pending_proposal.reason,
        source_proposal.id,
        source_proposal.proposing_context,
        pending_proposal.currently_feasible,
        cancellation_event.reason
    from public.appointments as appointment
    join public.pets as pet
      on pet.id = appointment.pet_id
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at,
               revision.establishment_timezone_name, revision.revision_sequence,
               revision.source_proposal_id
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_reschedule_proposals as source_proposal
      on source_proposal.id = current_revision.source_proposal_id
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    -- The derived value is computed only for the projected actionable PENDING
    -- proposal; an infeasible proposal is still projected.
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason,
               public.appointment_reschedule_proposal_is_currently_feasible(
                   open_proposal.id,
                   (select timezone_row.valid_timezone_name from pending_clinic_timezone as timezone_row)
               ) as currently_feasible
        from public.appointment_reschedule_proposals as open_proposal
        where open_proposal.appointment_id = appointment.id
          and open_proposal.state = 'PENDING'
          and public.appointment_reschedule_proposal_is_actionable(
              open_proposal.id,
              statement_timestamp()
          )
        limit 1
    ) as pending_proposal on true
    -- SPEC-APT-012 §4 (terminal outcome), SPEC-APT-003 BR-8/BR-9: only a
    -- CANCELLED Appointment carries a cancellation reason, from its single
    -- CANCELLED Lifecycle Event — the same source as get_pet_appointments.
    left join public.appointment_lifecycle_events as cancellation_event
      on cancellation_event.appointment_id = appointment.id
     and cancellation_event.to_state = 'CANCELLED'
     and appointment.lifecycle_state = 'CANCELLED'
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

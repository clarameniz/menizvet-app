-- SPEC-APT-012 — View Clinic Appointment Schedule: Pet current name
-- (BR-41, BR-42; Verification Notes 21–26).
--
-- Adds exactly one returned column, `pet_name`, immediately after `pet_id`
-- in `public.get_clinic_appointment_schedule(uuid)`. `pet_name` is the Pet's
-- current name (`pets.name`), resolved at read time; no name snapshot or name
-- history exists or is introduced. `pet_id` remains the Appointment's Pet
-- domain identity.
--
-- The join to `public.pets` is an inner join: `appointments.pet_id` is
-- NOT NULL with a foreign key to `pets` (ON DELETE RESTRICT), Pets cannot be
-- deleted (`pets_preserve_identity`), and `pets.name` is NOT NULL and
-- non-empty (`pets_name_check`), so the join neither removes an Appointment
-- nor yields a null name.
--
-- PostgreSQL cannot change a RETURNS TABLE column set through
-- CREATE OR REPLACE FUNCTION, so the function is dropped and recreated (the
-- same approach used for `get_my_pets()` in
-- 20260906090000_pet_profile_update_completion.sql). No database object
-- depends on the function; it is called only by clients and test suites.
--
-- Everything else is copied unchanged from 20260829120000_clinical_care.sql:
-- attributes, authentication sequence, capability check, SQLSTATEs, schedule
-- revision selection, current Veterinarian Assignment, pending reschedule
-- proposal, WHERE condition, ordering, and ACL. No other Pet Profile field,
-- Guardianship, or Guardian information is returned. No table, column,
-- index, constraint, table grant, or existing data is changed.

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
          and revision.revision_context = case
              when appointment.lifecycle_state in ('CONFIRMED', 'COMPLETED', 'NO_SHOW') then 'CONFIRMED'
              else 'REQUESTED'
          end
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

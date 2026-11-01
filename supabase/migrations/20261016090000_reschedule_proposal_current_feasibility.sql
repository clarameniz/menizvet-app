-- Derived current scheduling feasibility and Guardian current acceptability of
-- an actionable pending Reschedule Proposal (SPEC-APT-005 BR-34, BR-35;
-- SPEC-APT-011 BR-32; SPEC-APT-012 BR-44; SPEC-APT-006 BR-36; SPEC-APT-019 §5;
-- SPEC-COM-003 BR-70, BR-72).
--
-- Forward-only, read-side only. No table, column, constraint, index, or
-- trigger change; no proposal state, VOID reason, or backfill:
--
--   A. appointment_reschedule_proposal_is_currently_feasible (internal): a
--      valid current Clinic scheduling timezone AND the frozen proposed
--      interval passing appointment_reschedule_interval_infeasibility, in that
--      current timezone — exactly the scheduling evaluation both acceptance
--      operations apply. It never reads the standard duration, the proposal's
--      stored timezone, or Entitlement. The caller passes the Clinic's current
--      timezone already validated (NULL when absent or invalid):
--      clinic_timezone_name_is_valid scans pg_timezone_names (~50 ms), so each
--      read evaluates it once per Clinic with a PENDING proposal rather than
--      once per proposal;
--   B. appointment_reschedule_proposal_is_guardian_acceptable (internal):
--      whether a current Guardian could accept the proposal now — FALSE for a
--      GUARDIAN proposal (only the Clinic accepts it); feasibility for a
--      REQUESTED-base Clinic proposal; feasibility AND the Organization's
--      current APPOINTMENT_MANAGEMENT for a CONFIRMED-base Clinic proposal;
--   C. get_pet_appointments gains the trailing column
--      pending_reschedule_currently_acceptable (B);
--   D. get_clinic_appointment_schedule gains the trailing column
--      pending_reschedule_currently_feasible (A).
--
-- Both values are computed only for the projected actionable PENDING proposal
-- (NULL when none is projected), are generic (no reason), are never stored,
-- and never change the proposal. Unchanged on purpose:
-- appointment_reschedule_proposal_is_actionable, withdrawal, both acceptance
-- operations (still authoritative: they revalidate everything), and
-- Communication delivery eligibility.

begin;

-- ==================================================================
-- A. Current scheduling feasibility (SPEC-APT-005 BR-34).
-- ==================================================================

create function public.appointment_reschedule_proposal_is_currently_feasible(
    p_proposal_id uuid,
    p_valid_clinic_timezone_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((
        select case
            -- The Clinic's CURRENT timezone, validated by the caller with
            -- clinic_timezone_name_is_valid; NULL (absent or invalid) means
            -- not currently feasible. The proposal's stored timezone is not
            -- used.
            when p_valid_clinic_timezone_name is null then false
            -- The frozen interval, never recomputed.
            else public.appointment_reschedule_interval_infeasibility(
                     appointment.id, appointment.clinic_id,
                     proposal.proposed_start_at, proposal.proposed_end_at,
                     p_valid_clinic_timezone_name
                 ) is null
        end
        from public.appointment_reschedule_proposals as proposal
        join public.appointments as appointment
          on appointment.id = proposal.appointment_id
        where proposal.id = p_proposal_id
    ), false)
$$;

revoke all privileges
on function public.appointment_reschedule_proposal_is_currently_feasible(uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- B. Guardian current acceptability (SPEC-APT-005 BR-35).
-- ==================================================================

create function public.appointment_reschedule_proposal_is_guardian_acceptable(
    p_proposal_id uuid,
    p_valid_clinic_timezone_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((
        select case
            -- Only the Clinic context accepts a Guardian proposal
            -- (SPEC-APT-006 BR-5).
            when proposal.proposing_context <> 'CLINIC' then false
            when not public.appointment_reschedule_proposal_is_currently_feasible(
                     proposal.id, p_valid_clinic_timezone_name
                 ) then false
            -- A confirmed reschedule establishes a new confirmed commitment
            -- (SPEC-APT-006 BR-26); an alternative time does not
            -- (SPEC-APT-019 BR-4). Non-locking predicate: the read is advisory.
            when proposal.base_revision_context = 'CONFIRMED'
                then public.organization_has_professional_entitlement(
                         clinic.organization_id, 'APPOINTMENT_MANAGEMENT'
                     )
            else true
        end
        from public.appointment_reschedule_proposals as proposal
        join public.appointments as appointment
          on appointment.id = proposal.appointment_id
        join public.clinics as clinic
          on clinic.id = appointment.clinic_id
        where proposal.id = p_proposal_id
    ), false)
$$;

revoke all privileges
on function public.appointment_reschedule_proposal_is_guardian_acceptable(uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- C. Guardian read (SPEC-APT-011 BR-32). The output gains one trailing
--    column, so the read is dropped and re-created with its grants; the body
--    is otherwise that of 20261010090000.
-- ==================================================================

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
    cancellation_reason text,
    current_schedule_source_proposal_id uuid,
    current_schedule_source_proposing_context text,
    pending_reschedule_currently_acceptable boolean
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
    -- The current timezone of each Clinic with a PENDING proposal for this
    -- Pet, validated once per Clinic (NULL when absent or invalid).
    with pending_clinic_timezone as materialized (
        select clinic.id as clinic_id,
               case
                   when public.clinic_timezone_name_is_valid(clinic.scheduling_timezone_name)
                       then clinic.scheduling_timezone_name
               end as valid_timezone_name
        from public.clinics as clinic
        where clinic.id in (
            select pending_appointment.clinic_id
            from public.appointments as pending_appointment
            join public.appointment_reschedule_proposals as pending
              on pending.appointment_id = pending_appointment.id
             and pending.state = 'PENDING'
            where pending_appointment.pet_id = p_pet_id
        )
    )
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
        cancellation_event.reason,
        source_proposal.id,
        source_proposal.proposing_context,
        pending_proposal.currently_acceptable
    from public.appointments as appointment
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at,
               revision.establishment_timezone_name, revision.source_proposal_id
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
    -- proposal; an infeasible or unacceptable proposal is still projected.
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason,
               public.appointment_reschedule_proposal_is_guardian_acceptable(
                   open_proposal.id,
                   (select timezone_row.valid_timezone_name
                    from pending_clinic_timezone as timezone_row
                    where timezone_row.clinic_id = appointment.clinic_id)
               ) as currently_acceptable
        from public.appointment_reschedule_proposals as open_proposal
        where open_proposal.appointment_id = appointment.id
          and open_proposal.state = 'PENDING'
          and public.appointment_reschedule_proposal_is_actionable(
              open_proposal.id,
              statement_timestamp()
          )
        limit 1
    ) as pending_proposal on true
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

-- ==================================================================
-- D. Clinic Appointment Schedule (SPEC-APT-012 BR-44). Same pattern; the
--    body is otherwise that of 20261010090000.
-- ==================================================================

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
    pending_reschedule_currently_feasible boolean
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
        pending_proposal.currently_feasible
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

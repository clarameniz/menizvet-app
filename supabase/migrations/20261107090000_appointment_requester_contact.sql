-- Appointment Requester Contact — Phase 1 (SPEC-ID-006 BR-42, SPEC-APT-012
-- BR-12/BR-42/BR-49/BR-50, SPEC-APT-001 BR-37).
--
-- Forward-only. No table, column, constraint, index, trigger, policy or table
-- ACL change:
--
--   1. get_clinic_appointment_schedule gains requester_display_name, placed
--      right after requesting_user_id: the requesting User's current User
--      Profile display name, trimmed, NULL when none or blank (BR-49). Dropped
--      and recreated; body, row set, ordering, attributes and ACL are
--      otherwise those of 20261103090000. Never an email address.
--   2. get_clinic_appointment_requester_contact(p_clinic_id, p_appointment_id):
--      the single-Appointment requester contact read (BR-50). Order:
--      authenticate → current APPOINTMENT_VIEW_SCHEDULE for the Clinic AND the
--      Appointment belongs to that Clinic, as one uniform 42501
--      'Appointment requester contact unavailable' (no hint) for an unknown or
--      foreign Clinic or Appointment and missing authority alike → one row of
--      the original requester's current display name and current verified
--      authentication email (NULL when unverified). Independent of lifecycle
--      state and of the requester's current Guardianship. The email is read
--      internally through user_authentication_identities; auth.users is never
--      exposed and no email is stored, logged or put in an error.
--
-- Unchanged on purpose: every Appointment operation, every authorization
-- predicate, the Guardian Appointment view, and the user_profiles/auth tables
-- and their client privileges (none on auth.users, own-row RLS on
-- user_profiles).

begin;

-- ==================================================================
-- 1. Clinic Appointment Schedule: requester_display_name (SPEC-APT-012 BR-49).
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
    requester_display_name text,
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
    cancellation_reason text,
    has_clinical_encounter boolean
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
        -- SPEC-APT-012 BR-49: the original requester's current display name.
        nullif(btrim(requester_profile.display_name, E' \t\n\r\f\013'), ''),
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
        cancellation_event.reason,
        -- SPEC-APT-012 BR-48: existence only, whatever the Encounter state.
        exists (
            select 1
            from public.clinical_encounters as encounter_row
            where encounter_row.appointment_id = appointment.id
        )
    from public.appointments as appointment
    join public.pets as pet
      on pet.id = appointment.pet_id
    left join public.user_profiles as requester_profile
      on requester_profile.user_id = appointment.requesting_user_id
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

-- ==================================================================
-- 2. Single-Appointment requester contact (SPEC-APT-012 BR-50,
--    SPEC-ID-006 BR-42).
-- ==================================================================

create function public.get_clinic_appointment_requester_contact(
    p_clinic_id uuid,
    p_appointment_id uuid
)
returns table (
    requester_display_name text,
    requester_email text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    requester_user_id uuid;
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

    -- Authority first; the Appointment is resolved only for an authorized
    -- Clinic and only inside it, so nothing distinguishes an unknown or foreign
    -- Clinic or Appointment from missing authority.
    if public.user_has_clinic_capability(
        acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE'
    ) then
        select appointment.requesting_user_id
        into requester_user_id
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and appointment.clinic_id = p_clinic_id;
    end if;

    if requester_user_id is null then
        raise exception 'Appointment requester contact unavailable'
            using errcode = '42501';
    end if;

    -- The original requester, whatever the lifecycle state or their current
    -- Guardianship; current values, no snapshot.
    return query
    select
        (
            select nullif(btrim(profile.display_name, E' \t\n\r\f\013'), '')
            from public.user_profiles as profile
            where profile.user_id = requester_user_id
        ),
        (
            select nullif(btrim(auth_user.email::text, E' \t\n\r\f\013'), '')
            from public.user_authentication_identities as identity_link
            join auth.users as auth_user
              on auth_user.id = identity_link.provider_subject
            where identity_link.user_id = requester_user_id
              and identity_link.provider = 'supabase_auth'
              and identity_link.issuer = 'primary'
              and auth_user.email_confirmed_at is not null
        );
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_requester_contact(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_requester_contact(uuid, uuid)
to authenticated;

commit;

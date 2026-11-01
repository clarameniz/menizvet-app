-- Guardian Appointment Medical Access Revocation — Phase 1 (SPEC-ACC-002
-- §16/§17 BR-56–BR-63, SPEC-APT-011 BR-35, SPEC-ACC-001 BR-41).
--
-- Forward-only. No table, column, constraint, index or trigger change:
--
--   1. revoke_my_appointment_care_authorization(p_appointment_id): the
--      Appointment-keyed Guardian client operation. Order: authenticate →
--      argument shape → the acting User's current Guardianship of the Pet of
--      the named Appointment, resolved together with it (a foreign, unknown or
--      formerly guarded Appointment is one uniform 42501) → its
--      Appointment-derived Care Authorization → locks in the Appointment
--      operation order (Appointment shared, Guardianship, Care Authorization)
--      with the Guardianship re-verified → reconcile → revoke through the
--      existing trusted transition. Outcomes REVOKED / ALREADY_INACTIVE; no
--      identifier, no reason, no Appointment or clinical change, no audit
--      event (revocation is not a medical access);
--   2. get_pet_appointments gains the trailing column medical_access_state
--      (ACTIVE / REVOKED / INACTIVE) of the Appointment's own
--      Appointment-derived Care Authorization; the body is otherwise that of
--      20261016090000;
--   3. ACL: authenticated EXECUTE is withdrawn from the generic
--      revoke_pet_care_authorization and revoke_appointment_care_authorization
--      (existence before authority, raw errors; no mobile caller) and from the
--      deferred CLINICAL_INTAKE grant_pet_care_authorization (no Phase 1
--      workflow, no mobile caller). They remain trusted internal operations.
--
-- Unchanged on purpose: every clinical access predicate. Professional
-- longitudinal history (appointment_professional_history_accessible), the
-- Appointment clinical record and Amendment basis
-- (appointment_clinical_record_accessible) and Encounter establishment
-- already evaluate the Care Authorization's current state.

begin;

-- ==================================================================
-- 1. Guardian Appointment-keyed revocation (SPEC-ACC-002 BR-56–BR-61).
-- ==================================================================

create function public.revoke_my_appointment_care_authorization(
    p_appointment_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_appointment_id uuid;
    target_pet_id uuid;
    care_auth_record public.care_authorizations%rowtype;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject' using errcode = '28000';
    end if;

    -- 2. Argument shape only.
    if p_appointment_id is null then
        raise exception 'An Appointment is required'
            using errcode = '22023', hint = 'INVALID_APPOINTMENT';
    end if;

    -- 3. Guardian authority before any target: the Appointment is resolved
    --    only through the acting User's current Guardianship of its Pet, so a
    --    foreign, unknown or formerly guarded Appointment is indistinguishable.
    select appointment.id, appointment.pet_id
    into target_appointment_id, target_pet_id
    from public.appointments as appointment
    join public.guardianships as guardianship
      on guardianship.pet_id = appointment.pet_id
     and guardianship.user_id = acting_user_id
     and guardianship.effective_start <= clock_timestamp()
     and guardianship.effective_end is null
    where appointment.id = p_appointment_id
    limit 1;
    if not found then
        raise exception 'Appointment medical access unavailable' using errcode = '42501';
    end if;

    -- 4–5. Locks in the order every Appointment operation uses: the
    --    Appointment (shared: revocation never changes it), the acting
    --    Guardianship (re-verified), then the Care Authorization, which is
    --    resolved under its lock.
    perform 1 from public.appointments as appointment
    where appointment.id = target_appointment_id
    for share;

    perform 1 from public.guardianships as guardianship
    where guardianship.pet_id = target_pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;
    if not found then
        raise exception 'Appointment medical access unavailable' using errcode = '42501';
    end if;

    -- The Appointment's unique Appointment-derived Care Authorization.
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = target_appointment_id
      and care_auth.purpose = 'APPOINTMENT_CARE'
      and care_auth.pet_id = target_pet_id
    for update;
    if not found then
        raise exception 'Appointment medical access unavailable' using errcode = '42501';
    end if;

    -- 6. Reconcile: an authorization that is no longer ACTIVE (an earlier
    --    revocation, a lost response, cancellation, no-show or expiry) is
    --    left exactly as it is.
    if care_auth_record.lifecycle_state <> 'ACTIVE' then
        return jsonb_build_object('outcome', 'ALREADY_INACTIVE');
    end if;

    -- 7. The trusted transition every revocation uses (no reason collected).
    perform public.revoke_care_authorization_after_guardianship_lock(
        care_auth_record.id, acting_user_id, null
    );

    return jsonb_build_object('outcome', 'REVOKED');
end;
$$;

revoke all privileges
on function public.revoke_my_appointment_care_authorization(uuid)
from public, anon, authenticated, service_role;

grant execute
on function public.revoke_my_appointment_care_authorization(uuid)
to authenticated;

-- ==================================================================
-- 2. Guardian read (SPEC-APT-011 BR-35). The output gains one trailing
--    column, so the read is dropped and re-created with its grants; the body
--    is otherwise that of 20261016090000.
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
    pending_reschedule_currently_acceptable boolean,
    medical_access_state text
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
        pending_proposal.currently_acceptable,
        -- SPEC-APT-011 BR-35: an operational state of this Appointment's own
        -- Appointment-derived Care Authorization only, never its metadata.
        case appointment_care_auth.lifecycle_state
            when 'ACTIVE' then 'ACTIVE'
            when 'REVOKED' then 'REVOKED'
            else 'INACTIVE'
        end
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
    left join public.care_authorizations as appointment_care_auth
      on appointment_care_auth.appointment_id = appointment.id
     and appointment_care_auth.purpose = 'APPOINTMENT_CARE'
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
-- 3. Generic and deferred client paths withdrawn (SPEC-ACC-002 BR-62).
--    service_role keeps them as trusted internal operations.
-- ==================================================================

revoke execute
on function public.revoke_pet_care_authorization(uuid, text)
from authenticated;

revoke execute
on function public.revoke_appointment_care_authorization(uuid, text)
from authenticated;

revoke execute
on function public.grant_pet_care_authorization(uuid, uuid)
from authenticated;

commit;

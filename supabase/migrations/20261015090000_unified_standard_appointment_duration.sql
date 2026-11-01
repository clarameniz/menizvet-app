-- Unified Standard Appointment Duration rule (SPEC-APT-013 BR-62, BR-63,
-- BR-68–BR-71; SPEC-APT-005 BR-24, BR-25, BR-27; SPEC-APT-006 BR-29;
-- SPEC-APT-017 BR-5, BR-6).
--
-- Forward-only. Every operation that constructs a new scheduled interval from
-- an actor-selected start uses the Clinic's standard Appointment duration
-- current at that operation, and cannot construct one without it. Guardian
-- requests, Guardian requested reschedules, and Clinic Alternative Time
-- proposals already did; this migration brings the confirmed-reschedule path
-- onto the same rule:
--
--   A. propose_confirmed_appointment_reschedule: for both the GUARDIAN and the
--      CLINIC context the end is the resolved start plus the current standard
--      duration (required, no fallback), checked at the same point as the
--      REQUESTED Alternative Time path (after the lazy VOID, before the start
--      is resolved). The elapsed duration of the base confirmed revision is no
--      longer read;
--   B. get_appointment_reschedule_candidate_start_times: the current standard
--      duration is the length and cadence of every candidate, and is required;
--   C. appointment_interval_duration_microseconds is dropped: it existed only
--      to preserve the base confirmed elapsed duration and has no caller left.
--
-- No table, column, constraint, or trigger changes. Signatures, grants, error
-- messages, and every other rule of both functions are unchanged.
--
-- Unchanged on purpose:
--   * accept_appointment_reschedule_proposal and
--     accept_requested_appointment_alternative_time adopt the frozen proposed
--     interval and never read the standard duration;
--   * appointment_reschedule_candidate_positions keeps its microsecond step
--     parameter: it is a unit, not a policy, and both Professional candidate
--     reads now pass the standard duration through it;
--   * existing Reschedule Proposals keep their frozen intervals and may be
--     accepted unchanged; nothing is backfilled or recomputed.

begin;

-- ==================================================================
-- A. Confirmed-reschedule proposal creation (SPEC-APT-005 BR-23–BR-30).
-- ==================================================================

create or replace function public.propose_confirmed_appointment_reschedule(
    p_appointment_id uuid,
    p_proposing_context text,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_reason text default null,
    p_expected_confirmed_revision_sequence integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    base_revision public.appointment_schedule_revisions%rowtype;
    existing_proposal_record public.appointment_reschedule_proposals%rowtype;
    clinic_duration_minutes integer;
    resolved_start record;
    normalized_reason text;
    proposed_end_at timestamptz;
    operation_timestamp timestamptz;
    created_proposal_id uuid;
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

    -- BR-27 step 2: structural input, before any Appointment state.
    if p_proposing_context is null
       or p_proposing_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Proposing context must be GUARDIAN or CLINIC'
            using errcode = '22023';
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    if p_proposing_context = 'GUARDIAN' then
        if p_expected_confirmed_revision_sequence is not null then
            raise exception 'Guardian reschedule proposal does not accept an expected confirmed revision sequence'
                using errcode = '22023';
        end if;
    else
        if p_expected_confirmed_revision_sequence is null
           or p_expected_confirmed_revision_sequence <= 0 then
            raise exception 'Expected confirmed revision sequence must be a positive integer'
                using errcode = '22023';
        end if;

        if normalized_reason is null then
            raise exception 'A meaningful reason is required for a Clinic-proposed reschedule'
                using errcode = '22023';
        end if;
    end if;

    -- BR-27 step 3: authority under the existing lock order (Organization ->
    -- Clinic before the Appointment for the CLINIC context).
    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if p_proposing_context = 'CLINIC' then
        perform public.assert_clinic_appointment_authorization_after_lock(
            acting_user_id, resolved_clinic_id,
            'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_MANAGEMENT'
        );
    else
        -- GUARDIAN: prove current Guardianship before any lifecycle state is
        -- disclosed (BR-27 step 3 before step 4), as acceptance does. The
        -- authoritative check is the locked revalidation below.
        if not exists (
            select 1
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = p_appointment_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_end is null
        ) then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- BR-27 step 4.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may receive a reschedule Proposal'
            using errcode = '23514';
    end if;

    -- Authoritative, locked revalidation of the exact current Guardianship row
    -- after the Appointment lock.
    if p_proposing_context = 'GUARDIAN' then
        perform 1
        from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
        for update;

        if not found then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    end if;

    -- BR-27 step 5: the base confirmed scheduling context and, for CLINIC,
    -- the reviewed-context check — before any write (including the lazy VOID
    -- below).
    select revision.*
    into base_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no confirmed scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    if p_proposing_context = 'CLINIC'
       and base_revision.revision_sequence <> p_expected_confirmed_revision_sequence then
        raise exception 'Stale confirmed Appointment schedule revision for reschedule proposal';
    end if;

    -- BR-27 step 6.
    operation_timestamp := clock_timestamp();

    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.clinical_encounters as encounter_row
        where encounter_row.appointment_id = p_appointment_id
    ) then
        raise exception 'Appointment with a Clinical Encounter cannot be rescheduled'
            using errcode = '23514';
    end if;

    -- The open Proposal, if any, is on this same current base (BR-33 makes a
    -- superseded, lifecycle-changed, or Encounter-blocked one VOID eagerly).
    -- Only an actionable one blocks a new negotiation; a lapsed one is made
    -- VOID here, releasing the slot atomically with the new Proposal.
    select proposal.*
    into existing_proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.appointment_id = p_appointment_id
      and proposal.state = 'PENDING'
    for update;

    if found then
        if existing_proposal_record.proposed_start_at <= operation_timestamp then
            update public.appointment_reschedule_proposals
            set state = 'VOID',
                void_reason = 'PROPOSED_TIME_PASSED'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'GUARDIAN'
              and not public.user_has_continuous_guardianship_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.pet_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set state = 'VOID',
                void_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'CLINIC'
              and not public.user_has_continuous_clinic_reschedule_authority_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.clinic_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set state = 'VOID',
                void_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        else
            raise exception 'Appointment % already has an actionable unresolved reschedule Proposal',
                p_appointment_id
                using errcode = '23505';
        end if;
    end if;

    -- BR-24: the current standard duration, required, no fallback; the base
    -- confirmed duration is not used.
    select clinic.standard_appointment_duration_minutes
    into clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    -- BR-23: only the new start is resolved, in the Clinic's authoritative
    -- timezone (validated once here).
    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        appointment_record.clinic_id,
        p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- BR-25: the same start instant is never a reschedule, whatever the
    -- duration.
    if resolved_start.resolved_start_at = base_revision.scheduled_start_at then
        raise exception 'Proposed time must differ from the current confirmed time'
            using errcode = '22023';
    end if;

    proposed_end_at := resolved_start.resolved_start_at
        + clinic_duration_minutes * interval '1 minute';

    -- BR-28.
    perform public.assert_appointment_reschedule_interval_feasible(
        p_appointment_id, appointment_record.clinic_id,
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name
    );

    -- The interval is frozen here (§6).
    insert into public.appointment_reschedule_proposals (
        appointment_id, base_revision_id, base_revision_context,
        proposed_start_at, proposed_end_at, proposed_timezone_name,
        proposing_context, proposed_by_user_id, reason, created_at
    )
    values (
        p_appointment_id, base_revision.id, base_revision.revision_context,
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name,
        p_proposing_context, acting_user_id, normalized_reason, operation_timestamp
    )
    returning id into created_proposal_id;

    return created_proposal_id;
end;
$$;

-- ==================================================================
-- B. Professional confirmed-reschedule candidates (SPEC-APT-017).
-- ==================================================================

create or replace function public.get_appointment_reschedule_candidate_start_times(
    p_appointment_id uuid,
    p_start_date date,
    p_end_date date
)
returns table (
    candidate_local_date date,
    candidate_local_time time,
    utc_offset_seconds integer,
    candidate_end_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_record public.appointments%rowtype;
    target_organization_id uuid;
    base_revision public.appointment_schedule_revisions%rowtype;
    clinic_timezone_name text;
    clinic_duration_minutes integer;
    operation_timestamp timestamptz;
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

    -- BR-4: structural span validation (a safety bound, not a horizon).
    if p_start_date is null or p_end_date is null then
        raise exception 'A start date and end date are required'
            using errcode = '22023';
    end if;

    if p_end_date < p_start_date then
        raise exception 'End date must not precede start date'
            using errcode = '22023';
    end if;

    if p_end_date - p_start_date > 60 then
        raise exception 'Requested range must not span more than 60 days'
            using errcode = '22023';
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    -- BR-1: the same capability and Entitlement as a Clinic proposal.
    if not public.user_has_clinic_capability(
        acting_user_id, appointment_record.clinic_id, 'APPOINTMENT_RESCHEDULE'
    ) then
        raise exception 'Applicable Appointment-management capability is required'
            using errcode = '42501';
    end if;

    select clinic.organization_id, clinic.scheduling_timezone_name,
           clinic.standard_appointment_duration_minutes
    into target_organization_id, clinic_timezone_name, clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if not public.organization_has_professional_entitlement(
        target_organization_id, 'APPOINTMENT_MANAGEMENT'
    ) then
        raise exception 'Applicable professional Entitlement is required'
            using errcode = '42501';
    end if;

    -- BR-2.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may receive a reschedule Proposal'
            using errcode = '23514';
    end if;

    select revision.*
    into base_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no confirmed scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.clinical_encounters as encounter_row
        where encounter_row.appointment_id = p_appointment_id
    ) then
        raise exception 'Appointment with a Clinical Encounter cannot be rescheduled'
            using errcode = '23514';
    end if;

    -- BR-5: the current standard duration is required, as for proposing.
    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Appointment scheduling requires a valid Clinic scheduling timezone'
            using errcode = '23514';
    end if;

    -- BR-5–BR-7: standard duration as length and cadence; the current
    -- confirmed start is excluded whatever its duration.
    return query
    select *
    from public.appointment_reschedule_candidate_positions(
        p_appointment_id, appointment_record.clinic_id, clinic_timezone_name,
        p_start_date, p_end_date,
        clinic_duration_minutes::bigint * 60000000,
        base_revision.scheduled_start_at, operation_timestamp
    );
end;
$$;

-- ==================================================================
-- C. The base-confirmed elapsed-duration helper has no caller left.
-- ==================================================================

drop function public.appointment_interval_duration_microseconds(timestamptz, timestamptz);

commit;

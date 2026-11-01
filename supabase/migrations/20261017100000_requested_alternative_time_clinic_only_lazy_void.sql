-- REQUESTED Alternative Time: remove the unreachable Guardian lazy-VOID branch
-- (SPEC-APT-018 BR-1, BR-16).
--
-- Forward-only. propose_requested_appointment_alternative_time (created in
-- 20261010090000_requested_appointment_alternative_time.sql) made an existing
-- PENDING Proposal VOID with PROPOSING_AUTHORITY_LOST in a branch for a
-- GUARDIAN-originated Proposal. That Proposal cannot exist here:
--
--   * the function runs only for a REQUESTED Appointment, whose row it holds
--     FOR UPDATE;
--   * a PENDING Proposal's base context equals the Appointment's lifecycle
--     state: enforce_appointment_reschedule_proposal_base_revision checks it
--     at insert, the lifecycle trigger makes any mismatching PENDING Proposal
--     VOID (APPOINTMENT_LIFECYCLE_CHANGED), and the context is immutable;
--   * appointment_reschedule_proposals_requested_base_clinic_check requires a
--     REQUESTED base to be CLINIC-originated, validated for every stored row.
--
-- So the open Proposal is always a Clinic one, and only the time-passed and
-- Clinic-authority-lost lazy VOIDs remain. propose_confirmed_appointment_reschedule,
-- the integrity trigger's VOID-reason verification (shared by both workflows),
-- and every other behaviour are unchanged. Signature, attributes, and ACL are
-- unchanged (create or replace).

begin;

create or replace function public.propose_requested_appointment_alternative_time(
    p_appointment_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_reason text,
    p_expected_requested_revision_sequence integer
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

    -- BR-9 step 2: structural input, before any Appointment state.
    if p_expected_requested_revision_sequence is null
       or p_expected_requested_revision_sequence <= 0 then
        raise exception 'Expected requested revision sequence must be a positive integer'
            using errcode = '22023';
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    if normalized_reason is null then
        raise exception 'A meaningful reason is required for a Clinic alternative time proposal'
            using errcode = '22023';
    end if;

    -- BR-9 step 3: authority and Entitlement under the existing lock order
    -- (Organization -> Clinic -> Appointment). Publication is not evaluated
    -- (BR-5).
    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform public.assert_clinic_appointment_authorization_after_lock(
        acting_user_id, resolved_clinic_id,
        'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_MANAGEMENT'
    );

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- BR-9 step 4: lifecycle before staleness.
    if appointment_record.lifecycle_state <> 'REQUESTED' then
        raise exception 'Only a REQUESTED Appointment may receive an alternative time proposal'
            using errcode = '23514';
    end if;

    -- BR-9 step 5: the reviewed requested context, before any write
    -- (including the lazy VOID below).
    select revision.*
    into base_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'REQUESTED'
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no requested scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    if base_revision.revision_sequence <> p_expected_requested_revision_sequence then
        raise exception 'Stale requested Appointment schedule revision for alternative time proposal';
    end if;

    -- BR-9 step 6.
    operation_timestamp := clock_timestamp();

    -- BR-23: only a pending request.
    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'A REQUESTED Appointment whose requested time has passed cannot receive an alternative time proposal'
            using errcode = '23514';
    end if;

    -- BR-16: one open proposal. Only an actionable one blocks; a lapsed one is
    -- made VOID here, atomically with the new proposal. On a REQUESTED
    -- Appointment the open Proposal has a REQUESTED base and is therefore
    -- Clinic-originated (requested_base_clinic_check), so only the passed
    -- time and the Clinic proposer's authority can have lapsed.
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
        elsif not public.user_has_continuous_clinic_reschedule_authority_since(
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

    -- BR-11: the current standard duration, required, no fallback.
    select clinic.standard_appointment_duration_minutes
    into clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    -- BR-10, BR-14: only the start, resolved in the Clinic's timezone.
    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        appointment_record.clinic_id,
        p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- BR-13: the same start instant is never an alternative time, whatever the
    -- duration.
    if resolved_start.resolved_start_at = base_revision.scheduled_start_at then
        raise exception 'Proposed time must differ from the current requested time'
            using errcode = '22023';
    end if;

    proposed_end_at := resolved_start.resolved_start_at
        + clinic_duration_minutes * interval '1 minute';

    -- BR-15.
    perform public.assert_appointment_reschedule_interval_feasible(
        p_appointment_id, appointment_record.clinic_id,
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name
    );

    -- BR-12: the interval is frozen here. BR-20: the enqueue trigger
    -- establishes APPOINTMENT_ALTERNATIVE_TIME_PROPOSED for current Guardians.
    insert into public.appointment_reschedule_proposals (
        appointment_id, base_revision_id, base_revision_context,
        proposed_start_at, proposed_end_at, proposed_timezone_name,
        proposing_context, proposed_by_user_id, reason, created_at
    )
    values (
        p_appointment_id, base_revision.id, 'REQUESTED',
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name,
        'CLINIC', acting_user_id, normalized_reason, operation_timestamp
    )
    returning id into created_proposal_id;

    return created_proposal_id;
end;
$$;

commit;

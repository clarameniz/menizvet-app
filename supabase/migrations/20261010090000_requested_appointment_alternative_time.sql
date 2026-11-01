-- REQUESTED Appointment Alternative Time (SPEC-APT-018, SPEC-APT-019,
-- SPEC-APT-020; amendments to SPEC-APT-002/003/004/011/012/013/015/016,
-- SPEC-COM-003 BR-71–BR-74; docs/RELATIONAL_MODEL.md).
--
-- Forward-only. Enables a REQUESTED base on the already-normalized, unified
-- Reschedule Proposal model (20261009090000). No second proposal table, no new
-- proposal state, no new VOID reason: the eager/lazy VOID machinery, the one
-- PENDING proposal per Appointment, and the source_proposal_id provenance are
-- reused unchanged.
--
--   A. preflight: every existing Proposal has a CONFIRMED base;
--   B. base context REQUESTED | CONFIRMED, and a REQUESTED base is always
--      Clinic-originated (CHECK);
--   C. one internal candidate-grid generator shared by both Professional
--      candidate reads; get_appointment_reschedule_candidate_start_times is
--      re-created on it with an identical contract and behaviour;
--   D. propose_requested_appointment_alternative_time (SPEC-APT-018);
--   E. accept_requested_appointment_alternative_time (SPEC-APT-019);
--   F. get_requested_appointment_alternative_candidate_start_times
--      (SPEC-APT-020);
--   G. get_pet_appointments / get_clinic_appointment_schedule gain the
--      provenance of the relevant scheduled interval
--      (current_schedule_source_proposal_id,
--      current_schedule_source_proposing_context; SPEC-APT-011 BR-33,
--      SPEC-APT-012 BR-45); everything else unchanged;
--   H. APPOINTMENT_ALTERNATIVE_TIME_PROPOSED: type, origin shape, uniqueness,
--      origin integrity (a proposal-originated type must match its Proposal's
--      base context), enqueueing, delivery eligibility, delivery context.
--
-- Unchanged on purpose:
--   * withdraw_appointment_reschedule_proposal: already base-context neutral
--     (SPEC-APT-016 generalized);
--   * propose_confirmed_appointment_reschedule and
--     accept_appointment_reschedule_proposal: both already reject a REQUESTED
--     Appointment (SPEC-APT-005 §5, SPEC-APT-006 BR-35);
--   * reschedule_requested_appointment, confirm_appointment, cancel_appointment,
--     expire_lapsed_appointment_requests: the existing invalidation triggers
--     make a pending REQUESTED-base Proposal VOID (BASE_REVISION_SUPERSEDED on
--     any later revision, APPOINTMENT_LIFECYCLE_CHANGED on a lifecycle change);
--   * get_appointment_scheduling_history: its provenance columns are already
--     state-neutral.
--
-- Deployment order (docs/COMMUNICATIONS_OPERATIONAL_POLICY.md): the
-- communications Edge Functions that render APPOINTMENT_ALTERNATIVE_TIME_PROPOSED
-- must be deployed to an environment before this migration is applied there.

begin;

-- ==================================================================
-- A. Preflight.
-- ==================================================================

do $$
declare
    violation_count integer;
begin
    select count(*) into violation_count
    from public.appointment_reschedule_proposals as proposal
    where proposal.base_revision_context <> 'CONFIRMED';

    if violation_count > 0 then
        raise exception 'Alternative time preflight: % Proposal(s) without a CONFIRMED base',
            violation_count;
    end if;
end;
$$;

-- ==================================================================
-- B. REQUESTED base (SPEC-APT-018 BR-1, BR-2; RELATIONAL_MODEL §5.4).
-- ==================================================================

alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_base_revision_context_check,
    add constraint appointment_reschedule_proposals_base_revision_context_check
        check (base_revision_context in ('REQUESTED', 'CONFIRMED')),
    -- Only the Clinic proposes an alternative time for a request; the
    -- counterparty rule then makes the accepting context GUARDIAN.
    add constraint appointment_reschedule_proposals_requested_base_clinic_check
        check (base_revision_context <> 'REQUESTED' or proposing_context = 'CLINIC');

-- ==================================================================
-- C. Shared Professional candidate grid (SPEC-APT-013 BR-58, SPEC-APT-017
--    BR-5–BR-7, SPEC-APT-020 BR-5–BR-7).
--
-- Positions are the covered civil range's start plus whole multiples of
-- p_duration_microseconds, as both length and cadence; a position must fit in
-- its range; an omitted position never shifts the grid. A position is returned
-- when it resolves to one instant, after p_as_of, other than
-- p_excluded_start_at, and its interval passes exactly the feasibility
-- classifier the proposal operations use — so read/write parity holds for
-- unchanged state. The caller authorizes and supplies a valid timezone.
-- ==================================================================

create function public.appointment_reschedule_candidate_positions(
    p_appointment_id uuid,
    p_clinic_id uuid,
    p_clinic_timezone_name text,
    p_start_date date,
    p_end_date date,
    p_duration_microseconds bigint,
    p_excluded_start_at timestamptz,
    p_as_of timestamptz
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
    iter_date date;
    range_row record;
    range_start_microseconds bigint;
    range_end_microseconds bigint;
    position_microseconds bigint;
    position_time time;
    candidate_resolution record;
    candidate_end_instant timestamptz;
begin
    if p_duration_microseconds is null or p_duration_microseconds <= 0 then
        return;
    end if;

    iter_date := p_start_date;
    while iter_date <= p_end_date loop
        for range_row in
            select covered.range_start, covered.range_end
            from public.clinic_day_covered_civil_ranges(p_clinic_id, iter_date) as covered
        loop
            range_start_microseconds := round(
                extract(epoch from range_row.range_start) * 1000000
            )::bigint;
            range_end_microseconds := round(
                extract(epoch from range_row.range_end) * 1000000
            )::bigint;

            position_microseconds := range_start_microseconds;

            while position_microseconds + p_duration_microseconds <= range_end_microseconds loop
                position_time := time '00:00:00'
                    + position_microseconds * interval '1 microsecond';

                select *
                into candidate_resolution
                from public.resolve_clinic_civil_candidate(
                    p_clinic_timezone_name, iter_date, position_time
                );

                if candidate_resolution.resolution_kind = 'UNIQUE'
                   and candidate_resolution.resolved_instant > p_as_of
                   and candidate_resolution.resolved_instant <> p_excluded_start_at then
                    candidate_end_instant := candidate_resolution.resolved_instant
                        + p_duration_microseconds * interval '1 microsecond';

                    if public.appointment_reschedule_interval_infeasibility(
                        p_appointment_id, p_clinic_id,
                        candidate_resolution.resolved_instant, candidate_end_instant,
                        p_clinic_timezone_name
                    ) is null then
                        candidate_local_date := iter_date;
                        candidate_local_time := position_time;
                        utc_offset_seconds := candidate_resolution.resolved_utc_offset_seconds;
                        candidate_end_at := candidate_end_instant;
                        return next;
                    end if;
                end if;

                position_microseconds := position_microseconds + p_duration_microseconds;
            end loop;
        end loop;

        iter_date := iter_date + 1;
    end loop;

    return;
end;
$$;

revoke all privileges
on function public.appointment_reschedule_candidate_positions(
    uuid, uuid, text, date, date, bigint, timestamptz, timestamptz
)
from public, anon, authenticated;

-- SPEC-APT-017: same signature, checks, and messages; the grid is now the
-- shared generator with the base confirmed elapsed duration D.
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

    select clinic.organization_id, clinic.scheduling_timezone_name
    into target_organization_id, clinic_timezone_name
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

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Appointment scheduling requires a valid Clinic scheduling timezone'
            using errcode = '23514';
    end if;

    -- BR-5: D from the base confirmed revision; the standard duration is never
    -- read.
    return query
    select *
    from public.appointment_reschedule_candidate_positions(
        p_appointment_id, appointment_record.clinic_id, clinic_timezone_name,
        p_start_date, p_end_date,
        public.appointment_interval_duration_microseconds(
            base_revision.scheduled_start_at, base_revision.scheduled_end_at
        ),
        base_revision.scheduled_start_at, operation_timestamp
    );
end;
$$;

-- ==================================================================
-- D. Clinic proposal of an alternative time for a request (SPEC-APT-018).
-- ==================================================================

create function public.propose_requested_appointment_alternative_time(
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
    -- made VOID here, atomically with the new proposal.
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

revoke all privileges
on function public.propose_requested_appointment_alternative_time(
    uuid, date, time, integer, text, integer
)
from public, anon, authenticated;

grant execute
on function public.propose_requested_appointment_alternative_time(
    uuid, date, time, integer, text, integer
)
to authenticated;

-- ==================================================================
-- E. Guardian acceptance of an alternative time (SPEC-APT-019).
-- ==================================================================

create function public.accept_requested_appointment_alternative_time(
    p_proposal_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_appointment_id uuid;
    resolved_clinic_id uuid;
    proposal_record public.appointment_reschedule_proposals%rowtype;
    appointment_record public.appointments%rowtype;
    base_revision public.appointment_schedule_revisions%rowtype;
    clinic_timezone_name text;
    next_sequence integer;
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

    -- BR-3 step 2.
    select proposal.appointment_id
    into resolved_appointment_id
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    if not found then
        raise exception 'Reschedule Proposal does not exist'
            using errcode = '23503';
    end if;

    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    -- BR-3 step 3: Guardianship before any lifecycle or proposal state is
    -- disclosed. No Entitlement is evaluated (BR-4).
    if not exists (
        select 1
        from public.appointments as appointment
        join public.guardianships as guardianship
          on guardianship.pet_id = appointment.pet_id
        where appointment.id = resolved_appointment_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Appointment Pet is required'
            using errcode = '42501';
    end if;

    -- BR-3 step 4: the Clinic is the scheduling-configuration serialization
    -- boundary (as for a Guardian requested reschedule), then the Appointment
    -- and the Proposal.
    perform 1
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id
    for update;

    select proposal.*
    into proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id
    for update;

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

    -- BR-3 step 5, BR-12: this workflow only.
    if proposal_record.base_revision_context <> 'REQUESTED'
       or proposal_record.proposing_context <> 'CLINIC' then
        raise exception 'Only a Clinic alternative time for a requested Appointment can be accepted through this operation'
            using errcode = '23514';
    end if;

    -- BR-3 step 6.
    if appointment_record.lifecycle_state <> 'REQUESTED' then
        raise exception 'Appointment must remain REQUESTED to accept an alternative time'
            using errcode = '23514';
    end if;

    -- BR-3 step 7: actionability, with the specific outcomes first.
    if proposal_record.state = 'VOID'
       and proposal_record.void_reason = 'BASE_REVISION_SUPERSEDED' then
        raise exception 'Alternative time proposal base revision is no longer the current requested context'
            using errcode = '23514';
    elsif proposal_record.state <> 'PENDING' then
        raise exception 'Reschedule Proposal is no longer actionable'
            using errcode = '23514';
    end if;

    if not public.user_has_continuous_clinic_reschedule_authority_since(
        proposal_record.proposed_by_user_id,
        appointment_record.clinic_id,
        proposal_record.created_at
    ) then
        raise exception 'The Clinic Proposal is no longer actionable because proposing authority was lost'
            using errcode = '42501';
    end if;

    -- PENDING guarantees the base is the current revision.
    select revision.*
    into base_revision
    from public.appointment_schedule_revisions as revision
    where revision.id = proposal_record.base_revision_id;

    operation_timestamp := clock_timestamp();

    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'A REQUESTED Appointment whose requested time has passed cannot be rescheduled'
            using errcode = '23514';
    end if;

    if proposal_record.proposed_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    if not public.appointment_reschedule_proposal_is_actionable(
        p_proposal_id, operation_timestamp
    ) then
        raise exception 'Reschedule Proposal is no longer actionable'
            using errcode = '23514';
    end if;

    -- BR-3 step 8, BR-6: revalidate the exact stored interval against the
    -- Clinic's current timezone and configuration. The standard duration is
    -- never read.
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Clinic Appointment Availability does not cover the proposed interval'
            using errcode = '23514';
    end if;

    perform public.assert_appointment_reschedule_interval_feasible(
        appointment_record.id, appointment_record.clinic_id,
        proposal_record.proposed_start_at, proposal_record.proposed_end_at,
        clinic_timezone_name
    );

    -- BR-7: the Proposal becomes ACCEPTED (the integrity trigger re-checks
    -- actionability), then its single resulting REQUESTED revision is the
    -- frozen interval, established by the accepting Guardian (BR-8). The
    -- Appointment stays REQUESTED; no Lifecycle Event, no Communication
    -- (BR-9, BR-13).
    update public.appointment_reschedule_proposals
    set state = 'ACCEPTED'
    where id = p_proposal_id;

    next_sequence := public.next_appointment_revision_sequence(appointment_record.id);

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        appointment_record.id, next_sequence, 'REQUESTED',
        proposal_record.proposed_start_at, proposal_record.proposed_end_at,
        proposal_record.proposed_timezone_name, acting_user_id, p_proposal_id,
        operation_timestamp
    );

    return p_proposal_id;
end;
$$;

revoke all privileges
on function public.accept_requested_appointment_alternative_time(uuid)
from public, anon, authenticated;

grant execute
on function public.accept_requested_appointment_alternative_time(uuid)
to authenticated;

-- ==================================================================
-- F. Professional alternative-time candidates (SPEC-APT-020).
-- ==================================================================

create function public.get_requested_appointment_alternative_candidate_start_times(
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

    -- BR-4: a per-read safety bound, not a horizon.
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

    -- BR-1: the same capability and Entitlement as proposing.
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

    -- BR-2: a future pending request only, as a lifecycle error.
    if appointment_record.lifecycle_state <> 'REQUESTED' then
        raise exception 'Only a REQUESTED Appointment may receive an alternative time proposal'
            using errcode = '23514';
    end if;

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

    operation_timestamp := clock_timestamp();

    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'A REQUESTED Appointment whose requested time has passed cannot receive an alternative time proposal'
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
    -- requested start is excluded whatever its duration.
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

revoke all privileges
on function public.get_requested_appointment_alternative_candidate_start_times(uuid, date, date)
from public, anon, authenticated;

grant execute
on function public.get_requested_appointment_alternative_candidate_start_times(uuid, date, date)
to authenticated;

-- ==================================================================
-- G. Reads: provenance of the relevant scheduled interval (SPEC-APT-011
--    BR-33, SPEC-APT-012 BR-45). The output gains two trailing columns, so
--    each read is dropped and re-created with its grants; the bodies are
--    otherwise those of 20261009090000.
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
    current_schedule_source_proposing_context text
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
        cancellation_event.reason,
        source_proposal.id,
        source_proposal.proposing_context
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
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason
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
    current_schedule_source_proposing_context text
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
        source_proposal.proposing_context
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
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason
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

-- ==================================================================
-- H. APPOINTMENT_ALTERNATIVE_TIME_PROPOSED (SPEC-COM-003 BR-71–BR-73).
-- ==================================================================

alter table public.transactional_communications
    drop constraint transactional_communications_type_check,
    add constraint transactional_communications_type_check check (
        communication_type in (
            'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION',
            'APPOINTMENT_REQUESTED', 'APPOINTMENT_CONFIRMED',
            'APPOINTMENT_CANCELLED', 'APPOINTMENT_RESCHEDULE_PROPOSED',
            'APPOINTMENT_RESCHEDULE_ACCEPTED', 'APPOINTMENT_COMPLETED',
            'APPOINTMENT_NO_SHOW', 'APPOINTMENT_REMINDER',
            'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
        )
    ),
    drop constraint transactional_communications_origin_shape_check,
    add constraint transactional_communications_origin_shape_check check (
        (
            communication_type = 'ORGANIZATION_INVITATION'
            and organization_invitation_id is not null
            and guardianship_invitation_id is null
            and appointment_id is null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'GUARDIANSHIP_INVITATION'
            and organization_invitation_id is null
            and guardianship_invitation_id is not null
            and appointment_id is null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'APPOINTMENT_REQUESTED'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is not null
        )
        or (
            communication_type in (
                'APPOINTMENT_CONFIRMED', 'APPOINTMENT_CANCELLED',
                'APPOINTMENT_COMPLETED', 'APPOINTMENT_NO_SHOW'
            )
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is not null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is null
        )
        or (
            -- Both proposal-created types reference only the Proposal
            -- (one Proposal reference, no second nullable key).
            communication_type in (
                'APPOINTMENT_RESCHEDULE_PROPOSED', 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
            )
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is not null
            and appointment_schedule_revision_id is null
        )
        or (
            communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is not null
            and appointment_schedule_revision_id is not null
        )
        or (
            communication_type = 'APPOINTMENT_REMINDER'
            and organization_invitation_id is null
            and guardianship_invitation_id is null
            and appointment_id is not null
            and appointment_lifecycle_event_id is null
            and appointment_reschedule_proposal_id is null
            and appointment_schedule_revision_id is not null
        )
    );

-- One logical Communication per Proposal and recipient.
create unique index transactional_communications_alternative_time_proposed_key
on public.transactional_communications (
    appointment_reschedule_proposal_id, recipient_user_id
)
where communication_type = 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED';

-- Enqueueing: unchanged except that a Clinic Proposal establishes the type of
-- its base context (BR-71); RESCHEDULE_PROPOSED keeps its CONFIRMED meaning.
create or replace function public.enqueue_appointment_communications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_type text;
begin
    if tg_table_name = 'appointment_schedule_revisions' then
        if new.revision_context = 'REQUESTED'
           and new.revision_sequence = 1 then
            resolved_type := 'APPOINTMENT_REQUESTED';

            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_schedule_revision_id, locale, created_at
            )
            select resolved_type, guardianship.user_id, appointment.id,
                   new.id, 'es-ES', new.created_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.created_at
              and guardianship.effective_end is null
            on conflict do nothing;
        elsif new.revision_context = 'CONFIRMED'
              and new.source_proposal_id is not null then
            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_reschedule_proposal_id,
                appointment_schedule_revision_id, locale, created_at
            )
            select 'APPOINTMENT_RESCHEDULE_ACCEPTED', guardianship.user_id,
                   appointment.id, new.source_proposal_id, new.id,
                   'es-ES', new.created_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.created_at
              and guardianship.effective_end is null
            on conflict do nothing;
        end if;
        -- A REQUESTED revision sourced from an accepted alternative time
        -- creates no Communication (SPEC-COM-003 BR-73).

    elsif tg_table_name = 'appointment_lifecycle_events' then
        resolved_type := case new.to_state
            when 'CONFIRMED' then 'APPOINTMENT_CONFIRMED'
            when 'CANCELLED' then 'APPOINTMENT_CANCELLED'
            when 'COMPLETED' then 'APPOINTMENT_COMPLETED'
            when 'NO_SHOW' then 'APPOINTMENT_NO_SHOW'
            else null
        end;

        if resolved_type is not null then
            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_lifecycle_event_id, locale, created_at
            )
            select resolved_type, guardianship.user_id, appointment.id,
                   new.id, 'es-ES', new.recorded_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.recorded_at
              and guardianship.effective_end is null
            on conflict do nothing;
        end if;

    elsif tg_table_name = 'appointment_reschedule_proposals' then
        insert into public.transactional_communications (
            communication_type, recipient_user_id, appointment_id,
            appointment_reschedule_proposal_id, locale, created_at
        )
        select case new.base_revision_context
                   when 'REQUESTED' then 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
                   else 'APPOINTMENT_RESCHEDULE_PROPOSED'
               end,
               guardianship.user_id, appointment.id, new.id, 'es-ES', new.created_at
        from public.appointments as appointment
        join public.guardianships as guardianship
          on guardianship.pet_id = appointment.pet_id
        where appointment.id = new.appointment_id
          and new.state = 'PENDING'
          and new.proposing_context = 'CLINIC'
          and guardianship.effective_start <= new.created_at
          and guardianship.effective_end is null
        on conflict do nothing;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enqueue_appointment_communications()
from public, anon, authenticated;

-- Origin integrity: unchanged except that a Proposal-originated type must
-- match its Proposal's base context (RELATIONAL_MODEL §5.8).
create or replace function public.enforce_transactional_communication_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.organization_invitation_id is not null
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = new.organization_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'organization', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Organization Invitation'
            using errcode = '23514';
    end if;

    if new.guardianship_invitation_id is not null
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = new.guardianship_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'guardianship', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Guardianship Invitation'
            using errcode = '23514';
    end if;

    if new.appointment_lifecycle_event_id is not null
       and not exists (
           select 1 from public.appointment_lifecycle_events as event_record
           where event_record.id = new.appointment_lifecycle_event_id
             and event_record.appointment_id = new.appointment_id
             and (
                 (new.communication_type = 'APPOINTMENT_CONFIRMED' and event_record.to_state = 'CONFIRMED')
                 or (new.communication_type = 'APPOINTMENT_CANCELLED' and event_record.to_state = 'CANCELLED')
                 or (new.communication_type = 'APPOINTMENT_COMPLETED' and event_record.to_state = 'COMPLETED')
                 or (new.communication_type = 'APPOINTMENT_NO_SHOW' and event_record.to_state = 'NO_SHOW')
             )
       ) then
        raise exception 'Communication lifecycle origin does not match its Appointment and type'
            using errcode = '23514';
    end if;

    if new.appointment_reschedule_proposal_id is not null
       and not exists (
           select 1 from public.appointment_reschedule_proposals as proposal
           where proposal.id = new.appointment_reschedule_proposal_id
             and proposal.appointment_id = new.appointment_id
              and (
                  new.appointment_schedule_revision_id is null
                  or exists (
                      select 1
                      from public.appointment_schedule_revisions as resulting_revision
                      where resulting_revision.id = new.appointment_schedule_revision_id
                        and resulting_revision.source_proposal_id = proposal.id
                  )
              )
              and (
                  (
                      new.communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
                      and proposal.proposing_context = 'CLINIC'
                      and proposal.base_revision_context = 'CONFIRMED'
                  )
                  or (
                      new.communication_type = 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
                      and proposal.proposing_context = 'CLINIC'
                      and proposal.base_revision_context = 'REQUESTED'
                  )
                  or (
                      new.communication_type = 'APPOINTMENT_RESCHEDULE_ACCEPTED'
                      and proposal.base_revision_context = 'CONFIRMED'
                  )
              )
       ) then
        raise exception 'Communication Proposal origin does not match its Appointment or revision'
            using errcode = '23514';
    end if;

    if new.appointment_schedule_revision_id is not null
       and not exists (
           select 1 from public.appointment_schedule_revisions as revision
           where revision.id = new.appointment_schedule_revision_id
             and revision.appointment_id = new.appointment_id
             and revision.revision_context = case
                 when new.communication_type = 'APPOINTMENT_REQUESTED'
                     then 'REQUESTED'
                 else 'CONFIRMED'
             end
       ) then
        raise exception 'Communication Schedule Revision origin does not match its Appointment'
            using errcode = '23514';
    end if;

    -- Establishment-time invariant only. A Communication created for a
    -- then-current Guardian stays valid historical intent after the
    -- Guardianship ends; later delivery eligibility is governed by
    -- communication_delivery_is_currently_eligible and the suppression sweeps.
    -- Re-checking here on an immutable-row bookkeeping UPDATE (for example the
    -- fanout_materialized_at freeze) would abort dispatch instead of suppressing
    -- the former-Guardian destination.
    if tg_op = 'INSERT'
       and new.recipient_user_id is not null
       and new.appointment_id is not null
       and not exists (
           select 1
           from public.appointments as appointment
           join public.guardianships as guardianship
             on guardianship.pet_id = appointment.pet_id
           where appointment.id = new.appointment_id
             and guardianship.user_id = new.recipient_user_id
             and guardianship.effective_start <= new.created_at
             and guardianship.effective_end is null
       ) then
        raise exception 'Appointment Communication recipient must be a current Guardian'
            using errcode = '23514';
    end if;

    if tg_op = 'UPDATE' then
        if old.id is distinct from new.id
           or old.communication_type is distinct from new.communication_type
           or old.recipient_user_id is distinct from new.recipient_user_id
           or old.recipient_email is distinct from new.recipient_email
           or old.locale is distinct from new.locale
           or old.organization_invitation_id is distinct from new.organization_invitation_id
           or old.guardianship_invitation_id is distinct from new.guardianship_invitation_id
           or old.appointment_id is distinct from new.appointment_id
           or old.appointment_lifecycle_event_id is distinct from new.appointment_lifecycle_event_id
           or old.appointment_reschedule_proposal_id is distinct from new.appointment_reschedule_proposal_id
           or old.appointment_schedule_revision_id is distinct from new.appointment_schedule_revision_id
           or old.secret_envelope_version is distinct from new.secret_envelope_version
           or old.secret_key_version is distinct from new.secret_key_version
           or old.secret_algorithm is distinct from new.secret_algorithm
           or old.secret_aad_context is distinct from new.secret_aad_context
           or old.created_at is distinct from new.created_at
           or (
               old.fanout_materialized_at is not null
               and new.fanout_materialized_at is distinct from
                   old.fanout_materialized_at
           )
           or (old.secret_consumed_at is not null and new.secret_consumed_at is distinct from old.secret_consumed_at)
           or (old.secret_consumed_at is null and new.secret_consumed_at is null and (
               old.secret_nonce is distinct from new.secret_nonce
               or old.secret_ciphertext is distinct from new.secret_ciphertext
           )) then
            raise exception 'Communication identity, origin, recipient, and encrypted handoff are immutable'
                using errcode = '23514';
        end if;

        if old.secret_consumed_at is null and new.secret_consumed_at is not null
           and (new.secret_nonce is not null or new.secret_ciphertext is not null) then
            raise exception 'Consuming an Invitation secret must erase its encrypted payload'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_transactional_communication_integrity()
from public, anon, authenticated;

-- Delivery eligibility: unchanged except that both proposal-created types are
-- delivered only while their Proposal is actionable (SPEC-COM-003 BR-70,
-- BR-72), through the single authoritative predicate.
create or replace function public.communication_delivery_is_currently_eligible(
    p_communication_id uuid,
    p_channel text,
    p_push_registration_id uuid default null,
    p_destination_snapshot text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    communication_record public.transactional_communications%rowtype;
begin
    select communication.* into communication_record
    from public.transactional_communications as communication
    where communication.id = p_communication_id;

    if not found or p_channel is null or p_channel not in ('EMAIL', 'PUSH') then
        return false;
    end if;

    if communication_record.communication_type in (
        'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
    ) and p_channel <> 'EMAIL' then
        return false;
    end if;

    if communication_record.communication_type = 'ORGANIZATION_INVITATION'
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = communication_record.organization_invitation_id
             and invitation.revoked_at is null
             and invitation.rejected_at is null
             and invitation.expires_at > clock_timestamp()
             and invitation.acceptance_secret_digest is not null
             and not exists (
                 select 1 from public.organization_memberships as membership
                 where membership.originating_invitation_id = invitation.id
             )
       ) then return false;
    end if;

    if communication_record.communication_type = 'GUARDIANSHIP_INVITATION'
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = communication_record.guardianship_invitation_id
             and invitation.revoked_at is null
             and invitation.expires_at > clock_timestamp()
             and invitation.acceptance_secret_digest is not null
             and not exists (
                 select 1 from public.guardianships as guardianship
                 where guardianship.originating_invitation_id = invitation.id
             )
       ) then return false;
    end if;

    if communication_record.appointment_id is not null then
        if not exists (
            select 1
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = communication_record.appointment_id
              and guardianship.user_id = communication_record.recipient_user_id
              and guardianship.effective_start <= clock_timestamp()
              and guardianship.effective_end is null
        ) then return false; end if;

        if communication_record.communication_type = 'APPOINTMENT_REMINDER'
           and not exists (
               select 1
               from public.appointments as appointment
               join public.appointment_schedule_revisions as revision
                 on revision.id = communication_record.appointment_schedule_revision_id
                and revision.appointment_id = appointment.id
               where appointment.id = communication_record.appointment_id
                 and appointment.lifecycle_state = 'CONFIRMED'
                 and revision.revision_context = 'CONFIRMED'
                 and revision.scheduled_start_at > clock_timestamp()
                 and revision.id = (
                     select latest.id
                     from public.appointment_schedule_revisions as latest
                     where latest.appointment_id = appointment.id
                       and latest.revision_context = 'CONFIRMED'
                     order by latest.revision_sequence desc
                     limit 1
                 )
           ) then return false; end if;

        if communication_record.communication_type in (
               'APPOINTMENT_RESCHEDULE_PROPOSED', 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
           )
           and not exists (
               select 1 from public.appointment_reschedule_proposals as proposal
                where proposal.id = communication_record.appointment_reschedule_proposal_id
                  and proposal.proposing_context = 'CLINIC'
                  and public.appointment_reschedule_proposal_is_actionable(
                      proposal.id, clock_timestamp()
                  )
           ) then return false; end if;
    end if;

    if p_channel = 'EMAIL'
       and communication_record.recipient_email is not null
       and p_destination_snapshot is distinct from
           communication_record.recipient_email then
        return false;
    end if;

    if p_channel = 'EMAIL'
       and communication_record.recipient_email is null
       and not exists (
           select 1
           from public.user_authentication_identities as identity_record
           join auth.users as auth_user
             on auth_user.id = identity_record.provider_subject
           where identity_record.user_id = communication_record.recipient_user_id
             and identity_record.provider = 'supabase_auth'
             and identity_record.issuer = 'primary'
             and auth_user.email_confirmed_at is not null
             and auth_user.email is not null
             and (
                 p_destination_snapshot is null
                 or auth_user.email = p_destination_snapshot
             )
       ) then return false; end if;

    if p_channel = 'PUSH' and not exists (
        select 1
        from public.push_registrations as registration
        join public.user_authentication_identities as identity_record
          on identity_record.user_id = registration.user_id
         and identity_record.provider = 'supabase_auth'
         and identity_record.issuer = 'primary'
        join auth.sessions as auth_session
          on auth_session.id = registration.auth_session_id
         and auth_session.user_id = identity_record.provider_subject
        where registration.id = p_push_registration_id
          and registration.user_id = communication_record.recipient_user_id
          and registration.invalidated_at is null
          and p_destination_snapshot = 'sha256:' ||
              encode(registration.provider_token_digest, 'hex')
    ) then return false; end if;

    return true;
end;
$$;

revoke all privileges on function public.communication_delivery_is_currently_eligible(
    uuid, text, uuid, text
) from public, anon, authenticated;

-- Delivery context: unchanged except that the alternative time, like a
-- confirmed reschedule proposal, carries the proposed interval (BR-71).
create or replace function public.get_communication_delivery_context(
    p_delivery_job_id uuid,
    p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    communication_record public.transactional_communications%rowtype;
    resolved_destination text;
    result jsonb;
begin
    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.state = 'CLAIMED'
      and attempt.lease_token = p_lease_token
      and attempt.lease_expires_at > clock_timestamp()
      and attempt.active_submission_started_at is null
    for update;

    if not found then
        raise exception 'A live delivery claim is required' using errcode = '55000';
    end if;

    if not public.communication_delivery_is_currently_eligible(
        attempt_record.communication_id, attempt_record.channel,
        attempt_record.push_registration_id,
        attempt_record.destination_snapshot
    ) then
        update public.communication_delivery_jobs
        set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
            last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
            lease_token = null, lease_expires_at = null,
            active_submission_started_at = null
        where id = attempt_record.id;
        return null;
    end if;

    select communication.* into communication_record
    from public.transactional_communications as communication
    where communication.id = attempt_record.communication_id;

    resolved_destination := attempt_record.destination_snapshot;
    if attempt_record.channel = 'PUSH' then
        -- The raw provider token lives only on the private Registration. Load
        -- it after final registration/session revalidation and lock both rows
        -- for the remainder of this imminent trusted provider operation.
        select registration.provider_token into resolved_destination
        from public.push_registrations as registration
        join public.user_authentication_identities as identity_record
          on identity_record.user_id = registration.user_id
         and identity_record.provider = 'supabase_auth'
         and identity_record.issuer = 'primary'
        join auth.sessions as auth_session
          on auth_session.id = registration.auth_session_id
         and auth_session.user_id = identity_record.provider_subject
        where registration.id = attempt_record.push_registration_id
          and registration.user_id = communication_record.recipient_user_id
          and registration.invalidated_at is null
          and attempt_record.destination_snapshot = 'sha256:' ||
              encode(registration.provider_token_digest, 'hex')
        for key share of registration, auth_session;

        if not found then
            update public.communication_delivery_jobs
            set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
                last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
                lease_token = null, lease_expires_at = null,
                active_submission_started_at = null
            where id = attempt_record.id;
            return null;
        end if;
    end if;

    result := jsonb_build_object(
        'communication_id', communication_record.id,
        'communication_type', communication_record.communication_type,
        'locale', communication_record.locale,
        'recipient', resolved_destination,
        'channel', attempt_record.channel,
        'appointment_id', communication_record.appointment_id,
        'organization_invitation_id', communication_record.organization_invitation_id,
        'guardianship_invitation_id', communication_record.guardianship_invitation_id,
        'secret_envelope_version', communication_record.secret_envelope_version,
        'secret_key_version', communication_record.secret_key_version,
        'secret_algorithm', communication_record.secret_algorithm,
        'secret_aad_context', communication_record.secret_aad_context,
        'secret_nonce', communication_record.secret_nonce,
        'secret_ciphertext', communication_record.secret_ciphertext
    );

    if communication_record.organization_invitation_id is not null then
        select result || jsonb_build_object(
            'organization_name', organization.display_name,
            'invitation_expires_at', invitation.expires_at
        ) into result
        from public.organization_invitations as invitation
        join public.veterinary_organizations as organization
          on organization.id = invitation.organization_id
        where invitation.id = communication_record.organization_invitation_id;
    elsif communication_record.guardianship_invitation_id is not null then
        select result || jsonb_build_object(
            'pet_name', pet.name,
            'invitation_expires_at', invitation.expires_at
        ) into result
        from public.guardianship_invitations as invitation
        join public.pets as pet on pet.id = invitation.pet_id
        where invitation.id = communication_record.guardianship_invitation_id;
    elsif communication_record.appointment_id is not null then
        select result || jsonb_build_object(
            'pet_id', pet.id,
            'pet_name', pet.name,
            'clinic_name', coalesce(profile.display_name, organization.display_name),
            'appointment_state', appointment.lifecycle_state,
            'scheduled_start_at', coalesce(
                selected_revision.scheduled_start_at,
                proposal.proposed_start_at,
                latest_revision.scheduled_start_at
            ),
            'scheduled_end_at', coalesce(
                selected_revision.scheduled_end_at,
                proposal.proposed_end_at,
                latest_revision.scheduled_end_at
            ),
            'timezone_name', coalesce(
                selected_revision.establishment_timezone_name,
                proposal.proposed_timezone_name,
                latest_revision.establishment_timezone_name
            ),
            'reschedule_proposal_id', communication_record.appointment_reschedule_proposal_id
        ) into result
        from public.appointments as appointment
        join public.pets as pet on pet.id = appointment.pet_id
        join public.clinics as clinic on clinic.id = appointment.clinic_id
        join public.veterinary_organizations as organization
          on organization.id = clinic.organization_id
        left join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        left join public.appointment_schedule_revisions as selected_revision
          on selected_revision.id = communication_record.appointment_schedule_revision_id
        left join public.appointment_reschedule_proposals as proposal
          on proposal.id = communication_record.appointment_reschedule_proposal_id
         and communication_record.communication_type in (
             'APPOINTMENT_RESCHEDULE_PROPOSED', 'APPOINTMENT_ALTERNATIVE_TIME_PROPOSED'
         )
        left join lateral (
            select revision.*
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
              and (
                  (communication_record.communication_type = 'APPOINTMENT_REQUESTED'
                   and revision.revision_context = 'REQUESTED')
                  or
                  (communication_record.communication_type <> 'APPOINTMENT_REQUESTED'
                   and revision.revision_context = 'CONFIRMED')
              )
            order by revision.revision_sequence desc
            limit 1
        ) as latest_revision on true
        where appointment.id = communication_record.appointment_id;
    end if;

    return result;
end;
$$;

revoke all privileges on function public.get_communication_delivery_context(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.get_communication_delivery_context(uuid, uuid)
to service_role;

commit;

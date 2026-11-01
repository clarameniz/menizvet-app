-- SPEC-APT-002 BR-21/BR-22/BR-23 and SPEC-APT-012 BR-43 — stale-safe
-- Clinic-side Appointment confirmation.
--
-- Before this migration `confirm_appointment(p_appointment_id uuid)` confirmed
-- whatever the Appointment's latest REQUESTED Schedule Revision was at
-- execution time. A Guardian reschedule committed after a Clinic actor read
-- the schedule (revision N) and before that actor confirmed would make the
-- confirmation commit the Clinic to revision N+1, a requested time the actor
-- never reviewed. The transaction was coherent, but the commitment was not
-- the one reviewed.
--
-- This migration makes the REQUESTED revision sequence an optimistic
-- concurrency token:
--
-- 1. `get_clinic_appointment_schedule(uuid)` additionally returns
--    `current_schedule_revision_sequence integer`: the `revision_sequence` of
--    exactly the Schedule Revision row that already supplies
--    `current_scheduled_start_at`, `current_scheduled_end_at`, and
--    `current_scheduling_timezone_name` (the same lateral row). A RETURNS
--    TABLE change cannot be made with CREATE OR REPLACE, so the read is
--    dropped and recreated (precedent:
--    20261001170000_clinic_appointment_schedule_pet_name.sql). Body,
--    attributes, authorization, SQLSTATEs, row filtering, ordering, and ACL
--    are otherwise unchanged.
--
-- 2. `confirm_appointment(uuid)` is dropped and replaced by
--    `confirm_appointment(p_appointment_id uuid,
--    p_expected_requested_revision_sequence integer)`, with no default. The
--    identifier-only form is not kept as a compatibility overload: it would
--    bypass the stale check (SPEC-APT-002 §6 "Contract compatibility").
--
--    New behavior, everything else unchanged:
--      * a NULL or non-positive expected sequence is structurally invalid
--        input: SQLSTATE 22023, the repository's invalid-argument
--        convention, evaluated before any Appointment state is consulted;
--      * after the existing authorization/Entitlement locks, the Appointment
--        row lock, and the REQUESTED-state check, the latest REQUESTED
--        revision's sequence must equal the expected sequence; otherwise
--        'Stale requested Appointment schedule revision' is raised as plain
--        P0001 — the repository's deterministic stale-revision convention
--        (20260917120000_postgrest_conflict_status_correction.sql: never
--        40001, which PostgREST retries, and never PT409/HTTP 409, which
--        supabase-js may retry);
--      * the CONFIRMED revision is still inserted from the very same record
--        variable that passed the stale check, so confirmation cannot switch
--        to another requested context after the check.
--
-- Dependency inspection before the DROPs (pg_depend, pg_rewrite, and every
-- function body in the database): no view, rule, or function depends on or
-- calls either function. Only clients call them — the mobile app reads
-- `get_clinic_appointment_schedule` by column name (an additive column is
-- compatible); no client calls `confirm_appointment`.
--
-- No table, column, constraint, index, trigger, or existing row is changed.

begin;

-- ==================================================================
-- 1. SPEC-APT-012 BR-43 — Clinic schedule exposes the relevant schedule
--    revision sequence.
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
        current_revision.revision_sequence,
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
        select revision.scheduled_start_at, revision.scheduled_end_at,
               revision.establishment_timezone_name, revision.revision_sequence
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

-- ==================================================================
-- 2. SPEC-APT-002 BR-21/BR-22/BR-23 — confirmation bound to the reviewed
--    requested scheduling context.
-- ==================================================================

drop function public.confirm_appointment(uuid);

create function public.confirm_appointment(
    p_appointment_id uuid,
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
    latest_requested_revision public.appointment_schedule_revisions%rowtype;
    current_assignment_record public.appointment_veterinarian_assignments%rowtype;
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

    -- BR-21: structurally invalid input, rejected before any Appointment
    -- state is consulted. Distinct from a stale (well-formed but superseded)
    -- expected sequence.
    if p_expected_requested_revision_sequence is null
       or p_expected_requested_revision_sequence <= 0 then
        raise exception 'Expected requested revision sequence must be a positive integer'
            using errcode = '22023';
    end if;

    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform public.assert_clinic_appointment_authorization_after_lock(
        acting_user_id,
        resolved_clinic_id,
        'APPOINTMENT_CONFIRM',
        'APPOINTMENT_MANAGEMENT'
    );

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    -- Lifecycle precedes staleness: an Appointment that is no longer
    -- REQUESTED is an invalid transition, never a stale confirmation.
    if appointment_record.lifecycle_state <> 'REQUESTED' then
        raise exception 'Only a REQUESTED Appointment may be confirmed'
            using errcode = '23514';
    end if;

    select revision.*
    into latest_requested_revision
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

    -- BR-22/BR-23: the revision sequence alone decides staleness, never the
    -- scheduled values. Deterministic client-input mismatch: plain P0001
    -- (20260917120000_postgrest_conflict_status_correction.sql), so neither
    -- PostgREST nor the client retries it.
    if latest_requested_revision.revision_sequence
       <> p_expected_requested_revision_sequence then
        raise exception 'Stale requested Appointment schedule revision';
    end if;

    operation_timestamp := clock_timestamp();

    if latest_requested_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'A past requested Appointment cannot be confirmed'
            using errcode = '23514';
    end if;

    if not public.clinic_appointment_interval_is_available(
        resolved_clinic_id,
        latest_requested_revision.scheduled_start_at,
        latest_requested_revision.scheduled_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the requested interval'
            using errcode = '23514';
    end if;

    select assignment.*
    into current_assignment_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null;

    if found then
        if not public.veterinarian_clinic_assignment_is_current(
            current_assignment_record.veterinarian_clinic_assignment_id
        ) then
            raise exception 'Currently assigned Veterinarian no longer has a valid Clinic Assignment'
                using errcode = '23514';
        end if;

        if not public.veterinarian_availability_covers_interval(
            current_assignment_record.veterinarian_clinic_assignment_id,
            latest_requested_revision.scheduled_start_at,
            latest_requested_revision.scheduled_end_at
        ) then
            raise exception 'Currently assigned Veterinarian is not available for the requested interval'
                using errcode = '23514';
        end if;
    end if;

    next_sequence := public.next_appointment_revision_sequence(p_appointment_id);

    -- Copied from the exact record that passed the stale check above.
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        p_appointment_id, next_sequence, 'CONFIRMED',
        latest_requested_revision.scheduled_start_at,
        latest_requested_revision.scheduled_end_at,
        latest_requested_revision.establishment_timezone_name,
        acting_user_id, null, operation_timestamp
    );

    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at
    )
    values (
        p_appointment_id, 'REQUESTED', 'CONFIRMED', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp
    );

    update public.appointments
    set lifecycle_state = 'CONFIRMED'
    where id = p_appointment_id;

    return p_appointment_id;
end;
$$;

revoke all privileges
on function public.confirm_appointment(uuid, integer)
from public, anon, authenticated;

grant execute
on function public.confirm_appointment(uuid, integer)
to authenticated;

commit;

begin;

-- ==================================================================
-- 1. Slice 9 tables — Appointment, Lifecycle Events, Schedule
--    Revisions, Reschedule Proposals, Veterinarian Assignments.
--    Care Authorization and Clinical Encounter do not exist yet
--    (Slices 10 and 12); nothing here references them.
-- ==================================================================

create table public.appointments (
    id uuid not null default gen_random_uuid(),
    pet_id uuid not null,
    clinic_id uuid not null,
    requesting_user_id uuid not null,
    reason_for_visit text not null,
    guardian_notes text,
    lifecycle_state text not null default 'REQUESTED',
    created_at timestamptz not null,
    constraint appointments_pkey primary key (id),
    constraint appointments_pet_id_fkey
        foreign key (pet_id)
        references public.pets (id)
        on update no action
        on delete restrict,
    constraint appointments_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint appointments_requesting_user_id_fkey
        foreign key (requesting_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint appointments_reason_for_visit_check
        check (
            reason_for_visit = btrim(reason_for_visit, E' \t\n\r\f\013')
            and reason_for_visit <> ''
        ),
    constraint appointments_guardian_notes_check
        check (
            guardian_notes is null
            or (
                guardian_notes = btrim(guardian_notes, E' \t\n\r\f\013')
                and guardian_notes <> ''
            )
        ),
    -- Slice 9 physically permits only REQUESTED and CONFIRMED. CANCELLED
    -- (Slice 10, Care Authorization ending) and COMPLETED / NO_SHOW
    -- (Slice 12, Clinical Encounter) become physically reachable only
    -- when this constraint is widened alongside their coherent workflows.
    constraint appointments_lifecycle_state_check
        check (lifecycle_state in ('REQUESTED', 'CONFIRMED')),
    constraint appointments_created_at_finite_check
        check (isfinite(created_at))
);

create index appointments_pet_history_idx
on public.appointments (pet_id, created_at, id);

create index appointments_clinic_history_idx
on public.appointments (clinic_id, created_at, id);

create table public.appointment_lifecycle_events (
    id uuid not null default gen_random_uuid(),
    appointment_id uuid not null,
    from_state text not null,
    to_state text not null,
    actor_user_id uuid not null,
    actor_context text,
    reason text,
    effective_at timestamptz not null,
    recorded_at timestamptz not null,
    constraint appointment_lifecycle_events_pkey primary key (id),
    constraint appointment_lifecycle_events_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint appointment_lifecycle_events_actor_user_id_fkey
        foreign key (actor_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    -- Narrowed to the one Slice 9 transition; widened alongside the
    -- CANCELLED/COMPLETED/NO_SHOW workflows in Slices 10 and 12.
    constraint appointment_lifecycle_events_transition_check
        check (from_state = 'REQUESTED' and to_state = 'CONFIRMED'),
    constraint appointment_lifecycle_events_actor_context_check
        check (actor_context is null or actor_context in ('GUARDIAN', 'CLINIC')),
    constraint appointment_lifecycle_events_reason_check
        check (
            reason is null
            or (reason = btrim(reason, E' \t\n\r\f\013') and reason <> '')
        ),
    constraint appointment_lifecycle_events_effective_at_finite_check
        check (isfinite(effective_at)),
    constraint appointment_lifecycle_events_recorded_at_finite_check
        check (isfinite(recorded_at))
);

-- At most one confirmation Event per Appointment — immediate, not deferred.
create unique index appointment_lifecycle_events_confirmation_key
on public.appointment_lifecycle_events (appointment_id)
where from_state = 'REQUESTED' and to_state = 'CONFIRMED';

create index appointment_lifecycle_events_history_idx
on public.appointment_lifecycle_events (appointment_id, effective_at, id);

create table public.appointment_schedule_revisions (
    id uuid not null default gen_random_uuid(),
    appointment_id uuid not null,
    revision_sequence integer not null,
    revision_context text not null,
    scheduled_start_at timestamptz not null,
    scheduled_end_at timestamptz not null,
    establishment_timezone_name text not null,
    established_by_user_id uuid not null,
    source_proposal_id uuid,
    created_at timestamptz not null,
    constraint appointment_schedule_revisions_pkey primary key (id),
    constraint appointment_schedule_revisions_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint appointment_schedule_revisions_established_by_user_id_fkey
        foreign key (established_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint appointment_schedule_revisions_sequence_positive_check
        check (revision_sequence > 0),
    constraint appointment_schedule_revisions_context_check
        check (revision_context in ('REQUESTED', 'CONFIRMED')),
    constraint appointment_schedule_revisions_interval_check
        check (scheduled_start_at < scheduled_end_at),
    constraint appointment_schedule_revisions_start_finite_check
        check (isfinite(scheduled_start_at)),
    constraint appointment_schedule_revisions_end_finite_check
        check (isfinite(scheduled_end_at)),
    constraint appointment_schedule_revisions_timezone_name_check
        check (
            establishment_timezone_name = btrim(
                establishment_timezone_name,
                E' \t\n\r\f\013'
            )
            and establishment_timezone_name <> ''
        ),
    constraint appointment_schedule_revisions_requested_no_proposal_check
        check (revision_context <> 'REQUESTED' or source_proposal_id is null),
    constraint appointment_schedule_revisions_created_at_finite_check
        check (isfinite(created_at)),
    constraint appointment_schedule_revisions_appointment_sequence_key
        unique (appointment_id, revision_sequence)
    -- source_proposal_id foreign key is added below, after
    -- appointment_reschedule_proposals exists (circular reference).
);

-- At most one confirmed Schedule Revision may result from a given Proposal.
create unique index appointment_schedule_revisions_source_proposal_key
on public.appointment_schedule_revisions (source_proposal_id)
where source_proposal_id is not null;

create index appointment_schedule_revisions_latest_idx
on public.appointment_schedule_revisions (appointment_id, revision_sequence desc);

create table public.appointment_reschedule_proposals (
    id uuid not null default gen_random_uuid(),
    appointment_id uuid not null,
    base_revision_id uuid not null,
    proposed_start_at timestamptz not null,
    proposed_end_at timestamptz not null,
    proposed_timezone_name text not null,
    proposing_context text not null,
    proposed_by_user_id uuid not null,
    reason text,
    state text not null default 'PENDING',
    created_at timestamptz not null,
    non_actionable_at timestamptz,
    non_actionable_reason text,
    accepted_at timestamptz,
    accepted_by_user_id uuid,
    accepting_context text,
    resulting_confirmed_revision_id uuid,
    constraint appointment_reschedule_proposals_pkey primary key (id),
    constraint appointment_reschedule_proposals_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint appointment_reschedule_proposals_base_revision_id_fkey
        foreign key (base_revision_id)
        references public.appointment_schedule_revisions (id)
        on update no action
        on delete restrict,
    constraint appointment_reschedule_proposals_proposed_by_user_id_fkey
        foreign key (proposed_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint appointment_reschedule_proposals_accepted_by_user_id_fkey
        foreign key (accepted_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint appointment_reschedule_proposals_resulting_revision_id_fkey
        foreign key (resulting_confirmed_revision_id)
        references public.appointment_schedule_revisions (id)
        on update no action
        on delete restrict,
    constraint appointment_reschedule_proposals_proposing_context_check
        check (proposing_context in ('GUARDIAN', 'CLINIC')),
    constraint appointment_reschedule_proposals_accepting_context_check
        check (accepting_context is null or accepting_context in ('GUARDIAN', 'CLINIC')),
    constraint appointment_reschedule_proposals_counterparty_context_check
        check (accepting_context is null or accepting_context <> proposing_context),
    constraint appointment_reschedule_proposals_reason_check
        check (
            reason is null
            or (reason = btrim(reason, E' \t\n\r\f\013') and reason <> '')
        ),
    constraint appointment_reschedule_proposals_clinic_reason_required_check
        check (proposing_context <> 'CLINIC' or reason is not null),
    constraint appointment_reschedule_proposals_state_check
        check (state in ('PENDING', 'ACCEPTED')),
    constraint appointment_reschedule_proposals_interval_check
        check (proposed_start_at < proposed_end_at),
    constraint appointment_reschedule_proposals_start_finite_check
        check (isfinite(proposed_start_at)),
    constraint appointment_reschedule_proposals_end_finite_check
        check (isfinite(proposed_end_at)),
    constraint appointment_reschedule_proposals_timezone_name_check
        check (
            proposed_timezone_name = btrim(proposed_timezone_name, E' \t\n\r\f\013')
            and proposed_timezone_name <> ''
        ),
    constraint appointment_reschedule_proposals_created_at_finite_check
        check (isfinite(created_at)),
    constraint appointment_reschedule_proposals_non_actionable_reason_check
        check (
            non_actionable_reason is null
            or non_actionable_reason in (
                'BASE_REVISION_SUPERSEDED',
                'PROPOSED_TIME_PASSED',
                'PROPOSING_AUTHORITY_LOST'
            )
        ),
    constraint appointment_reschedule_proposals_non_actionable_at_check
        check (
            non_actionable_at is null
            or (
                isfinite(non_actionable_at)
                and non_actionable_at >= created_at
            )
        ),
    -- Establishment-shape backstop; the authoritative INSERT-time guard is
    -- the enforce_appointment_reschedule_proposal_integrity() trigger below.
    constraint appointment_reschedule_proposals_shape_check
        check (
            (
                state = 'PENDING'
                and accepted_at is null
                and accepted_by_user_id is null
                and accepting_context is null
                and resulting_confirmed_revision_id is null
                and (
                    (non_actionable_at is null and non_actionable_reason is null)
                    or
                    (non_actionable_at is not null and non_actionable_reason is not null)
                )
            )
            or
            (
                state = 'ACCEPTED'
                and accepted_at is not null
                and accepted_by_user_id is not null
                and accepting_context is not null
                and resulting_confirmed_revision_id is not null
                and non_actionable_at is null
                and non_actionable_reason is null
            )
        ),
    constraint appointment_reschedule_proposals_resulting_revision_key
        unique (resulting_confirmed_revision_id)
);

create unique index appointment_reschedule_proposals_pending_key
on public.appointment_reschedule_proposals (appointment_id)
where state = 'PENDING'
  and non_actionable_at is null;

create index appointment_reschedule_proposals_history_idx
on public.appointment_reschedule_proposals (appointment_id, created_at, id);

alter table public.appointment_schedule_revisions
add constraint appointment_schedule_revisions_source_proposal_id_fkey
foreign key (source_proposal_id)
references public.appointment_reschedule_proposals (id)
on update no action
on delete restrict;

create table public.appointment_veterinarian_assignments (
    id uuid not null default gen_random_uuid(),
    appointment_id uuid not null,
    veterinarian_clinic_assignment_id uuid not null,
    effective_start timestamptz not null,
    effective_end timestamptz,
    assigned_by_user_id uuid not null,
    constraint appointment_veterinarian_assignments_pkey primary key (id),
    constraint appointment_veterinarian_assignments_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint appointment_veterinarian_assignments_assignment_id_fkey
        foreign key (veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint appointment_veterinarian_assignments_assigned_by_user_fkey
        foreign key (assigned_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint appointment_veterinarian_assignments_effective_period_check
        check (effective_end is null or effective_end >= effective_start),
    constraint appointment_veterinarian_assignments_start_finite_check
        check (isfinite(effective_start))
);

create unique index appointment_veterinarian_assignments_current_key
on public.appointment_veterinarian_assignments (appointment_id)
where effective_end is null;

create index appointment_veterinarian_assignments_history_idx
on public.appointment_veterinarian_assignments (appointment_id, effective_start);

create index appointment_veterinarian_assignments_clinic_assignment_idx
on public.appointment_veterinarian_assignments (veterinarian_clinic_assignment_id);

-- ==================================================================
-- 2. Civil-time resolution — explicit caller-supplied UTC-offset
--    disambiguation, verified against the server-derived Clinic named
--    timezone by exact civil round trip. Callers never supply the
--    authoritative timezone or a timestamptz.
-- ==================================================================

create function public.resolve_clinic_civil_instant(
    p_timezone_name text,
    p_local_date date,
    p_local_time time,
    p_utc_offset_seconds integer
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    civil_value timestamp;
    candidate_instant timestamptz;
    round_trip_civil timestamp;
begin
    if p_timezone_name is null
       or p_local_date is null
       or p_local_time is null
       or p_utc_offset_seconds is null then
        raise exception 'Clinic timezone, local date, local time, and UTC offset seconds are required'
            using errcode = '22023';
    end if;

    if p_local_date = 'infinity'::date or p_local_date = '-infinity'::date then
        raise exception 'Local date must be finite'
            using errcode = '22023';
    end if;

    -- PostgreSQL's own numeric-timezone displacement limit is strictly
    -- less than 16 hours (MAX_TZDISP_HOUR = 15), hence +/-15:59:59.
    -- Keeping second precision also supports historical IANA offsets.
    if p_utc_offset_seconds < -57599
       or p_utc_offset_seconds > 57599 then
        raise exception 'UTC offset seconds must be between -57599 and 57599'
            using errcode = '22023';
    end if;

    civil_value := p_local_date + p_local_time;

    -- Offset seconds use the ISO-style sign: positive is east of UTC.
    -- Interpret the arithmetic result explicitly as UTC so the session
    -- timezone cannot affect resolution.
    candidate_instant := (
        civil_value - (p_utc_offset_seconds * interval '1 second')
    ) at time zone 'UTC';

    round_trip_civil := candidate_instant at time zone p_timezone_name;

    if round_trip_civil <> civil_value then
        raise exception
            'UTC offset seconds % do not identify a valid occurrence of local civil time % in timezone %',
            p_utc_offset_seconds, civil_value, p_timezone_name
            using errcode = '22007';
    end if;

    return candidate_instant;
end;
$$;

revoke all privileges
on function public.resolve_clinic_civil_instant(text, date, time, integer)
from public, anon, authenticated;

create function public.resolve_clinic_appointment_interval(
    p_clinic_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_end_local_date date,
    p_end_local_time time,
    p_end_utc_offset_seconds integer
)
returns table (
    resolved_start_at timestamptz,
    resolved_end_at timestamptz,
    timezone_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    clinic_timezone_name text;
    computed_start_at timestamptz;
    computed_end_at timestamptz;
begin
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    if not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Appointment scheduling requires a valid Clinic scheduling timezone'
            using errcode = '23514';
    end if;

    computed_start_at := public.resolve_clinic_civil_instant(
        clinic_timezone_name, p_start_local_date, p_start_local_time,
        p_start_utc_offset_seconds
    );
    computed_end_at := public.resolve_clinic_civil_instant(
        clinic_timezone_name, p_end_local_date, p_end_local_time,
        p_end_utc_offset_seconds
    );

    if computed_start_at >= computed_end_at then
        raise exception 'Appointment scheduling interval must have a resolved start before its resolved end'
            using errcode = '22023';
    end if;

    return query
    select computed_start_at, computed_end_at, clinic_timezone_name;
end;
$$;

revoke all privileges
on function public.resolve_clinic_appointment_interval(
    uuid, date, time, integer, date, time, integer
)
from public, anon, authenticated;

-- ==================================================================
-- 3. Revision sequencing — the sole authoritative ordering source.
-- ==================================================================

create function public.next_appointment_revision_sequence(
    p_appointment_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    next_sequence integer;
begin
    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    select coalesce(max(revision.revision_sequence), 0) + 1
    into next_sequence
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id;

    return next_sequence;
end;
$$;

revoke all privileges
on function public.next_appointment_revision_sequence(uuid)
from public, anon, authenticated;

-- ==================================================================
-- 4. Availability evaluation over Slice 8 configuration, using the
--    full resolved actual interval (never only the start instant).
-- ==================================================================

-- Day-scoped union-coverage helpers. Candidate rows for one local date are
-- guaranteed non-overlapping by the Slice 8 integrity triggers, but may be
-- adjacent (touching, no gap) or may leave a genuine gap; both are only
-- distinguishable by merging the whole set in start_time order rather than
-- checking any single row. `p_end_time` may be '24:00:00' to represent the
-- end-of-day boundary, matching the convention already accepted by
-- parse_clinic_local_time.

create function public.clinic_day_interval_is_covered(
    p_clinic_id uuid,
    p_local_date date,
    p_start_time time,
    p_end_time time
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    has_closed_exception boolean;
    has_open_exception boolean;
    covered_until time;
    period_row record;
begin
    select exists (
        select 1
        from public.clinic_appointment_availability_exceptions as exception_record
        where exception_record.clinic_id = p_clinic_id
          and exception_record.local_date = p_local_date
          and exception_record.exception_kind = 'CLOSED'
    ) into has_closed_exception;

    if has_closed_exception then
        return false;
    end if;

    select exists (
        select 1
        from public.clinic_appointment_availability_exceptions as exception_record
        where exception_record.clinic_id = p_clinic_id
          and exception_record.local_date = p_local_date
          and exception_record.exception_kind = 'OPEN'
    ) into has_open_exception;

    covered_until := p_start_time;

    if has_open_exception then
        for period_row in
            select exception_record.start_time as period_start,
                   exception_record.end_time as period_end
            from public.clinic_appointment_availability_exceptions as exception_record
            where exception_record.clinic_id = p_clinic_id
              and exception_record.local_date = p_local_date
              and exception_record.exception_kind = 'OPEN'
            order by exception_record.start_time
        loop
            if period_row.period_start > covered_until then
                exit;
            end if;

            if period_row.period_end > covered_until then
                covered_until := period_row.period_end;
            end if;

            exit when covered_until >= p_end_time;
        end loop;

        return covered_until >= p_end_time;
    end if;

    for period_row in
        select period.start_time as period_start, period.end_time as period_end
        from public.clinic_appointment_availability_periods as period
        where period.clinic_id = p_clinic_id
          and period.iso_weekday = extract(isodow from p_local_date)
        order by period.start_time
    loop
        if period_row.period_start > covered_until then
            exit;
        end if;

        if period_row.period_end > covered_until then
            covered_until := period_row.period_end;
        end if;

        exit when covered_until >= p_end_time;
    end loop;

    return covered_until >= p_end_time;
end;
$$;

revoke all privileges
on function public.clinic_day_interval_is_covered(uuid, date, time, time)
from public, anon, authenticated;

create function public.veterinarian_day_interval_is_covered(
    p_veterinarian_clinic_assignment_id uuid,
    p_local_date date,
    p_start_time time,
    p_end_time time
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    has_closed_exception boolean;
    has_open_exception boolean;
    covered_until time;
    period_row record;
begin
    select exists (
        select 1
        from public.veterinarian_availability_exceptions as exception_record
        where exception_record.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and exception_record.local_date = p_local_date
          and exception_record.exception_kind = 'CLOSED'
    ) into has_closed_exception;

    if has_closed_exception then
        return false;
    end if;

    select exists (
        select 1
        from public.veterinarian_availability_exceptions as exception_record
        where exception_record.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and exception_record.local_date = p_local_date
          and exception_record.exception_kind = 'OPEN'
    ) into has_open_exception;

    covered_until := p_start_time;

    if has_open_exception then
        for period_row in
            select exception_record.start_time as period_start,
                   exception_record.end_time as period_end
            from public.veterinarian_availability_exceptions as exception_record
            where exception_record.veterinarian_clinic_assignment_id
                      = p_veterinarian_clinic_assignment_id
              and exception_record.local_date = p_local_date
              and exception_record.exception_kind = 'OPEN'
            order by exception_record.start_time
        loop
            if period_row.period_start > covered_until then
                exit;
            end if;

            if period_row.period_end > covered_until then
                covered_until := period_row.period_end;
            end if;

            exit when covered_until >= p_end_time;
        end loop;

        return covered_until >= p_end_time;
    end if;

    for period_row in
        select period.start_time as period_start, period.end_time as period_end
        from public.veterinarian_availability_periods as period
        where period.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and period.iso_weekday = extract(isodow from p_local_date)
        order by period.start_time
    loop
        if period_row.period_start > covered_until then
            exit;
        end if;

        if period_row.period_end > covered_until then
            covered_until := period_row.period_end;
        end if;

        exit when covered_until >= p_end_time;
    end loop;

    return covered_until >= p_end_time;
end;
$$;

revoke all privileges
on function public.veterinarian_day_interval_is_covered(uuid, date, time, time)
from public, anon, authenticated;

-- Segments the full resolved interval at local-midnight boundaries in the
-- Clinic timezone and requires every segment to be covered by that day's
-- applicable (exception-or-recurring) union, so cross-midnight intervals are
-- evaluated as continuous coverage rather than rejected outright.

create function public.clinic_appointment_interval_is_available(
    p_clinic_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    clinic_timezone_name text;
    local_start timestamp;
    local_end timestamp;
    segment_cursor timestamp;
    segment_date date;
    next_midnight timestamp;
    segment_end timestamp;
    segment_start_time time;
    segment_end_time time;
begin
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        return false;
    end if;

    local_start := p_start_at at time zone clinic_timezone_name;
    local_end := p_end_at at time zone clinic_timezone_name;

    if local_start >= local_end then
        return false;
    end if;

    segment_cursor := local_start;

    while segment_cursor < local_end loop
        segment_date := segment_cursor::date;
        next_midnight := (segment_date + 1)::timestamp;
        segment_end := least(local_end, next_midnight);

        segment_start_time := segment_cursor::time;
        segment_end_time := case
            when segment_end = next_midnight then '24:00:00'::time
            else segment_end::time
        end;

        if not public.clinic_day_interval_is_covered(
            p_clinic_id, segment_date, segment_start_time, segment_end_time
        ) then
            return false;
        end if;

        segment_cursor := segment_end;
    end loop;

    return true;
end;
$$;

revoke all privileges
on function public.clinic_appointment_interval_is_available(uuid, timestamptz, timestamptz)
from public, anon, authenticated;

create function public.veterinarian_availability_covers_interval(
    p_veterinarian_clinic_assignment_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    clinic_timezone_name text;
    local_start timestamp;
    local_end timestamp;
    segment_cursor timestamp;
    segment_date date;
    next_midnight timestamp;
    segment_end timestamp;
    segment_start_time time;
    segment_end_time time;
begin
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_veterinarian_clinic_assignment_id;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        return false;
    end if;

    local_start := p_start_at at time zone clinic_timezone_name;
    local_end := p_end_at at time zone clinic_timezone_name;

    if local_start >= local_end then
        return false;
    end if;

    segment_cursor := local_start;

    while segment_cursor < local_end loop
        segment_date := segment_cursor::date;
        next_midnight := (segment_date + 1)::timestamp;
        segment_end := least(local_end, next_midnight);

        segment_start_time := segment_cursor::time;
        segment_end_time := case
            when segment_end = next_midnight then '24:00:00'::time
            else segment_end::time
        end;

        if not public.veterinarian_day_interval_is_covered(
            p_veterinarian_clinic_assignment_id, segment_date,
            segment_start_time, segment_end_time
        ) then
            return false;
        end if;

        segment_cursor := segment_end;
    end loop;

    return true;
end;
$$;

revoke all privileges
on function public.veterinarian_availability_covers_interval(uuid, timestamptz, timestamptz)
from public, anon, authenticated;

-- ==================================================================
-- 5. Immutability — one trigger per table, following the established
--    enforce_*_immutability() naming and revoke-all pattern.
-- ==================================================================

create function public.enforce_appointment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointments cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.clinic_id is distinct from new.clinic_id
       or old.requesting_user_id is distinct from new.requesting_user_id
       or old.reason_for_visit is distinct from new.reason_for_visit
       or old.guardian_notes is distinct from new.guardian_notes
       or old.created_at is distinct from new.created_at then
        raise exception 'Appointment identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state = new.lifecycle_state then
        return new;
    end if;

    if not (old.lifecycle_state = 'REQUESTED' and new.lifecycle_state = 'CONFIRMED') then
        raise exception 'Unsupported Appointment lifecycle transition'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_immutability()
from public, anon, authenticated;

create trigger appointments_preserve_identity
before update or delete on public.appointments
for each row
execute function public.enforce_appointment_immutability();

create function public.enforce_appointment_lifecycle_event_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointment Lifecycle Events cannot be deleted'
            using errcode = '23514';
    end if;

    raise exception 'Appointment Lifecycle Events are immutable'
        using errcode = '23514';
end;
$$;

revoke all privileges
on function public.enforce_appointment_lifecycle_event_immutability()
from public, anon, authenticated;

create trigger appointment_lifecycle_events_preserve_history
before update or delete on public.appointment_lifecycle_events
for each row
execute function public.enforce_appointment_lifecycle_event_immutability();

create function public.enforce_appointment_schedule_revision_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointment Schedule Revisions cannot be deleted'
            using errcode = '23514';
    end if;

    raise exception 'Appointment Schedule Revisions are immutable'
        using errcode = '23514';
end;
$$;

revoke all privileges
on function public.enforce_appointment_schedule_revision_immutability()
from public, anon, authenticated;

create trigger appointment_schedule_revisions_preserve_history
before update or delete on public.appointment_schedule_revisions
for each row
execute function public.enforce_appointment_schedule_revision_immutability();

create function public.enforce_appointment_schedule_revision_timezone_validity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not public.clinic_timezone_name_is_valid(new.establishment_timezone_name) then
        raise exception 'Appointment Schedule Revision timezone snapshot must be a valid named timezone'
            using errcode = '22023';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_schedule_revision_timezone_validity()
from public, anon, authenticated;

create trigger appointment_schedule_revisions_validate_timezone
before insert on public.appointment_schedule_revisions
for each row
execute function public.enforce_appointment_schedule_revision_timezone_validity();

create function public.enforce_appointment_schedule_revision_source_proposal_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    proposal_appointment_id uuid;
begin
    if new.source_proposal_id is null then
        return new;
    end if;

    select proposal.appointment_id
    into proposal_appointment_id
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = new.source_proposal_id;

    if not found then
        raise exception 'Appointment Schedule Revision source Proposal does not exist'
            using errcode = '23503';
    end if;

    if proposal_appointment_id <> new.appointment_id then
        raise exception 'Appointment Schedule Revision source Proposal must belong to the same Appointment'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_schedule_revision_source_proposal_context()
from public, anon, authenticated;

create trigger appointment_schedule_revisions_validate_source_proposal
before insert on public.appointment_schedule_revisions
for each row
execute function public.enforce_appointment_schedule_revision_source_proposal_context();

create function public.enforce_appointment_reschedule_proposal_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointment Reschedule Proposals cannot be deleted'
            using errcode = '23514';
    end if;

    if tg_op = 'INSERT' then
        if new.state <> 'PENDING'
           or new.non_actionable_at is not null
           or new.non_actionable_reason is not null
           or new.accepted_at is not null
           or new.accepted_by_user_id is not null
           or new.accepting_context is not null
           or new.resulting_confirmed_revision_id is not null then
            raise exception 'Appointment Reschedule Proposal must be established as PENDING with no acceptance facts'
                using errcode = '23514';
        end if;

        return new;
    end if;

    -- tg_op = 'UPDATE'
    if old.state <> 'PENDING' or old.non_actionable_at is not null then
        raise exception 'Accepted and non-actionable Appointment Reschedule Proposals are immutable'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.appointment_id is distinct from new.appointment_id
       or old.base_revision_id is distinct from new.base_revision_id
       or old.proposed_start_at is distinct from new.proposed_start_at
       or old.proposed_end_at is distinct from new.proposed_end_at
       or old.proposed_timezone_name is distinct from new.proposed_timezone_name
       or old.proposing_context is distinct from new.proposing_context
       or old.proposed_by_user_id is distinct from new.proposed_by_user_id
       or old.reason is distinct from new.reason
       or old.created_at is distinct from new.created_at then
        raise exception 'Appointment Reschedule Proposal context is immutable'
            using errcode = '23514';
    end if;

    -- Resolution time is an observed database fact, not caller-authored
    -- history. This also prevents a future-dated direct update from releasing
    -- the actionable-Proposal uniqueness slot prematurely.
    if new.state = 'PENDING' and new.non_actionable_reason is not null then
        new.non_actionable_at := clock_timestamp();
    end if;

    if new.state = 'ACCEPTED'
       and not public.appointment_reschedule_proposal_is_actionable(
           old.id,
           clock_timestamp(),
           new.resulting_confirmed_revision_id
       ) then
        raise exception 'Only a currently actionable Appointment Reschedule Proposal may be accepted'
            using errcode = '23514';
    end if;

    if not (
        (
            new.state = 'PENDING'
            and new.non_actionable_at is not null
            and new.non_actionable_reason is not null
            and new.accepted_at is null
            and new.accepted_by_user_id is null
            and new.accepting_context is null
            and new.resulting_confirmed_revision_id is null
        )
        or
        (
            new.state = 'ACCEPTED'
            and new.non_actionable_at is null
            and new.non_actionable_reason is null
            and new.accepted_at is not null
            and new.accepted_by_user_id is not null
            and new.accepting_context is not null
            and new.resulting_confirmed_revision_id is not null
        )
    ) then
        raise exception 'A PENDING Appointment Reschedule Proposal may only become permanently non-actionable or ACCEPTED with complete transition facts'
            using errcode = '23514';
    end if;

    if new.state = 'PENDING' then
        if new.non_actionable_reason = 'BASE_REVISION_SUPERSEDED'
           and not exists (
               select 1
               from public.appointment_schedule_revisions as later_revision
               join public.appointment_schedule_revisions as base_revision
                 on base_revision.id = old.base_revision_id
               where later_revision.appointment_id = old.appointment_id
                 and later_revision.revision_context = 'CONFIRMED'
                 and later_revision.revision_sequence > base_revision.revision_sequence
           ) then
            raise exception 'Reschedule Proposal base revision has not been superseded'
                using errcode = '23514';
        elsif new.non_actionable_reason = 'PROPOSED_TIME_PASSED'
              and old.proposed_start_at > new.non_actionable_at then
            raise exception 'Reschedule Proposal time had not passed at the recorded resolution time'
                using errcode = '23514';
        elsif new.non_actionable_reason = 'PROPOSING_AUTHORITY_LOST'
              and exists (
                  select 1
                  from public.appointments as appointment
                  where appointment.id = old.appointment_id
                    and (
                        (
                            old.proposing_context = 'GUARDIAN'
                            and public.user_has_continuous_guardianship_since(
                                old.proposed_by_user_id,
                                appointment.pet_id,
                                old.created_at
                            )
                        )
                        or
                        (
                            old.proposing_context = 'CLINIC'
                            and public.user_has_continuous_clinic_reschedule_authority_since(
                                old.proposed_by_user_id,
                                appointment.clinic_id,
                                old.created_at
                            )
                        )
                    )
              ) then
            raise exception 'Reschedule Proposal proposing authority has remained continuous'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_reschedule_proposal_integrity()
from public, anon, authenticated;

create trigger appointment_reschedule_proposals_enforce_integrity
before insert or update or delete on public.appointment_reschedule_proposals
for each row
execute function public.enforce_appointment_reschedule_proposal_integrity();

create function public.enforce_appointment_reschedule_proposal_base_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    base_revision_record public.appointment_schedule_revisions%rowtype;
    latest_confirmed_revision_id uuid;
begin
    perform 1
    from public.appointments as appointment
    where appointment.id = new.appointment_id
    for update;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    select revision.*
    into base_revision_record
    from public.appointment_schedule_revisions as revision
    where revision.id = new.base_revision_id;

    if not found then
        raise exception 'Reschedule Proposal base revision does not exist'
            using errcode = '23503';
    end if;

    if base_revision_record.appointment_id <> new.appointment_id then
        raise exception 'Reschedule Proposal base revision must belong to the same Appointment'
            using errcode = '23514';
    end if;

    if base_revision_record.revision_context <> 'CONFIRMED' then
        raise exception 'Reschedule Proposal base revision must be CONFIRMED'
            using errcode = '23514';
    end if;

    select revision.id
    into latest_confirmed_revision_id
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = new.appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc
    limit 1;

    if latest_confirmed_revision_id is distinct from new.base_revision_id then
        raise exception 'Reschedule Proposal base revision must be the current confirmed scheduling context'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_reschedule_proposal_base_revision()
from public, anon, authenticated;

create trigger appointment_reschedule_proposals_validate_base_revision
before insert on public.appointment_reschedule_proposals
for each row
execute function public.enforce_appointment_reschedule_proposal_base_revision();

create function public.enforce_appointment_veterinarian_assignment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointment Veterinarian Assignments cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.appointment_id is distinct from new.appointment_id
       or old.veterinarian_clinic_assignment_id is distinct from new.veterinarian_clinic_assignment_id
       or old.effective_start is distinct from new.effective_start
       or old.assigned_by_user_id is distinct from new.assigned_by_user_id then
        raise exception 'Appointment Veterinarian Assignment identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.effective_end is not null and old.effective_end is distinct from new.effective_end then
        raise exception 'Ended Appointment Veterinarian Assignment facts are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_veterinarian_assignment_immutability()
from public, anon, authenticated;

create trigger appointment_veterinarian_assignments_preserve_history
before update or delete on public.appointment_veterinarian_assignments
for each row
execute function public.enforce_appointment_veterinarian_assignment_immutability();

create function public.assert_appointment_veterinarian_assignment_establishment(
    p_appointment_id uuid,
    p_veterinarian_clinic_assignment_id uuid,
    p_effective_start timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_clinic_id uuid;
    appointment_lifecycle_state text;
    assignment_clinic_id uuid;
    assignment_effective_start timestamptz;
    assignment_organization_id uuid;
begin
    -- Resolve immutable identifying context first, without write locks,
    -- so a Clinic-context mismatch is rejected before acquiring any
    -- aggregate lock.
    select appointment.clinic_id
    into appointment_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    select assignment.clinic_id, clinic.organization_id
    into assignment_clinic_id, assignment_organization_id
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_veterinarian_clinic_assignment_id;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if assignment_clinic_id <> appointment_clinic_id then
        raise exception 'Veterinarian Clinic Assignment must belong to the Appointment Clinic'
            using errcode = '23514';
    end if;

    -- Normal aggregate lock order: Organization -> Clinic -> Appointment
    -- -> Veterinarian Clinic Assignment. A trusted RPC that already holds
    -- some of these locks in the same transaction may safely reacquire
    -- them here.
    perform 1
    from public.veterinary_organizations as organization
    where organization.id = assignment_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = assignment_clinic_id
      and clinic.organization_id = assignment_organization_id
    for update;

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    select appointment.lifecycle_state
    into appointment_lifecycle_state
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if appointment_lifecycle_state not in ('REQUESTED', 'CONFIRMED') then
        raise exception 'Appointment Veterinarian Assignment requires a REQUESTED or CONFIRMED Appointment'
            using errcode = '23514';
    end if;

    select assignment.effective_start
    into assignment_effective_start
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
    for update;

    -- Re-evaluate all mutable establishment facts only after every lock
    -- in the aggregate is held.
    if not public.veterinarian_clinic_assignment_is_current(p_veterinarian_clinic_assignment_id) then
        raise exception 'Appointment Veterinarian Assignment requires a currently valid Clinic Assignment'
            using errcode = '23514';
    end if;

    if p_effective_start < assignment_effective_start then
        raise exception 'Appointment Veterinarian Assignment cannot start before its Clinic Assignment'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_veterinarian_assignment_establishment(uuid, uuid, timestamptz)
from public, anon, authenticated;

create function public.enforce_appointment_veterinarian_assignment_establishment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_appointment_veterinarian_assignment_establishment(
        new.appointment_id,
        new.veterinarian_clinic_assignment_id,
        new.effective_start
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_veterinarian_assignment_establishment()
from public, anon, authenticated;

create trigger appointment_veterinarian_assignments_establishment
before insert on public.appointment_veterinarian_assignments
for each row
execute function public.enforce_appointment_veterinarian_assignment_establishment();

-- ==================================================================
-- 6. Deferred cross-row integrity — lifecycle coherence and
--    consolidated Schedule Revision provenance. Each is independent
--    per table so a privileged write against any one of
--    appointments / appointment_lifecycle_events /
--    appointment_schedule_revisions cannot bypass the others.
-- ==================================================================

create function public.assert_appointment_lifecycle_coherence(
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    requested_revision_count integer;
    event_count integer;
    confirmed_revision_count integer;
begin
    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if not found then
        return;
    end if;

    if appointment_record.lifecycle_state = 'REQUESTED' then
        select count(*)
        into requested_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = p_appointment_id
          and revision.revision_context = 'REQUESTED'
          and revision.revision_sequence = 1;

        if requested_revision_count <> 1 then
            raise exception 'REQUESTED Appointment % requires exactly one initial REQUESTED Schedule Revision',
                p_appointment_id
                using errcode = '23514';
        end if;

        select count(*)
        into event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id;

        if event_count <> 0 then
            raise exception 'REQUESTED Appointment % must have zero Lifecycle Events',
                p_appointment_id
                using errcode = '23514';
        end if;

        return;
    end if;

    if appointment_record.lifecycle_state = 'CONFIRMED' then
        select count(*)
        into event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id
          and event_row.from_state = 'REQUESTED'
          and event_row.to_state = 'CONFIRMED';

        if event_count <> 1 then
            raise exception 'CONFIRMED Appointment % requires exactly one REQUESTED to CONFIRMED Lifecycle Event',
                p_appointment_id
                using errcode = '23514';
        end if;

        select count(*)
        into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = p_appointment_id
          and revision.revision_context = 'CONFIRMED';

        if confirmed_revision_count < 1 then
            raise exception 'CONFIRMED Appointment % requires an applicable CONFIRMED Schedule Revision',
                p_appointment_id
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_coherence(uuid)
from public, anon, authenticated;

create function public.enforce_appointment_lifecycle_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_appointment_lifecycle_coherence(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_lifecycle_coherence()
from public, anon, authenticated;

create constraint trigger appointments_enforce_lifecycle_coherence
after insert or update of lifecycle_state on public.appointments
deferrable initially deferred
for each row
execute function public.enforce_appointment_lifecycle_coherence();

create function public.assert_appointment_lifecycle_event_provenance(
    p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_appointment_id uuid;
    appointment_state text;
    confirmed_revision_count integer;
begin
    select event_row.appointment_id
    into target_appointment_id
    from public.appointment_lifecycle_events as event_row
    where event_row.id = p_event_id;

    if not found then
        return;
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = target_appointment_id
    for update;

    select appointment.lifecycle_state
    into appointment_state
    from public.appointments as appointment
    where appointment.id = target_appointment_id;

    if not found or appointment_state <> 'CONFIRMED' then
        raise exception 'Appointment confirmation Lifecycle Event % requires a CONFIRMED Appointment',
            p_event_id
            using errcode = '23514';
    end if;

    select count(*)
    into confirmed_revision_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = target_appointment_id
      and revision.revision_context = 'CONFIRMED';

    if confirmed_revision_count < 1 then
        raise exception 'Appointment confirmation Lifecycle Event % requires an applicable CONFIRMED Schedule Revision',
            p_event_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_event_provenance(uuid)
from public, anon, authenticated;

create function public.enforce_appointment_lifecycle_event_provenance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_appointment_lifecycle_event_provenance(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_lifecycle_event_provenance()
from public, anon, authenticated;

create constraint trigger appointment_lifecycle_events_enforce_provenance
after insert on public.appointment_lifecycle_events
deferrable initially deferred
for each row
execute function public.enforce_appointment_lifecycle_event_provenance();

create function public.assert_appointment_schedule_revision_provenance(
    p_revision_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    revision_record public.appointment_schedule_revisions%rowtype;
    appointment_record public.appointments%rowtype;
    preceding_requested_record public.appointment_schedule_revisions%rowtype;
    preceding_confirmed_record public.appointment_schedule_revisions%rowtype;
    proposal_record public.appointment_reschedule_proposals%rowtype;
    total_count integer;
    contiguous_count integer;
    first_context text;
    earlier_confirmed_count integer;
    confirmation_event_count integer;
begin
    select revision.*
    into revision_record
    from public.appointment_schedule_revisions as revision
    where revision.id = p_revision_id;

    if not found then
        return;
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = revision_record.appointment_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = revision_record.appointment_id;

    if not found then
        raise exception 'Appointment Schedule Revision % requires its Appointment',
            p_revision_id
            using errcode = '23514';
    end if;

    -- A. sequence contiguity {1..n}
    select count(*)
    into total_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id;

    select count(*)
    into contiguous_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_sequence between 1 and total_count;

    if contiguous_count <> total_count then
        raise exception 'Appointment % Schedule Revision sequence must be contiguous from 1',
            revision_record.appointment_id
            using errcode = '23514';
    end if;

    -- B. sequence 1 is always REQUESTED
    select revision.revision_context
    into first_context
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_sequence = 1;

    if first_context is distinct from 'REQUESTED' then
        raise exception 'Appointment % first Schedule Revision must be REQUESTED',
            revision_record.appointment_id
            using errcode = '23514';
    end if;

    -- C. context/lifecycle coherence for the newly inserted row only
    if revision_record.revision_context = 'REQUESTED' then
        if appointment_record.lifecycle_state <> 'REQUESTED' then
            raise exception 'REQUESTED Schedule Revision % requires a REQUESTED Appointment',
                p_revision_id
                using errcode = '23514';
        end if;

        return;
    end if;

    -- revision_context = 'CONFIRMED' from here on
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'CONFIRMED Schedule Revision % requires a CONFIRMED Appointment',
            p_revision_id
            using errcode = '23514';
    end if;

    select count(*)
    into confirmation_event_count
    from public.appointment_lifecycle_events as event_row
    where event_row.appointment_id = revision_record.appointment_id
      and event_row.from_state = 'REQUESTED'
      and event_row.to_state = 'CONFIRMED';

    if confirmation_event_count <> 1 then
        raise exception 'CONFIRMED Schedule Revision % requires exactly one confirmation Lifecycle Event',
            p_revision_id
            using errcode = '23514';
    end if;

    select count(*)
    into earlier_confirmed_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_context = 'CONFIRMED'
      and revision.revision_sequence < revision_record.revision_sequence;

    -- D. confirmed-revision provenance
    if earlier_confirmed_count = 0 then
        -- first CONFIRMED revision: must copy the immediately preceding
        -- REQUESTED context exactly, and must not reference a Proposal.
        if revision_record.source_proposal_id is not null then
            raise exception 'First CONFIRMED Schedule Revision % must not reference a Proposal',
                p_revision_id
                using errcode = '23514';
        end if;

        select revision.*
        into preceding_requested_record
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = revision_record.appointment_id
          and revision.revision_context = 'REQUESTED'
          and revision.revision_sequence < revision_record.revision_sequence
        order by revision.revision_sequence desc
        limit 1;

        if not found then
            raise exception 'First CONFIRMED Schedule Revision % requires a preceding REQUESTED Schedule Revision',
                p_revision_id
                using errcode = '23514';
        end if;

        if revision_record.scheduled_start_at <> preceding_requested_record.scheduled_start_at
           or revision_record.scheduled_end_at <> preceding_requested_record.scheduled_end_at
           or revision_record.establishment_timezone_name
                  <> preceding_requested_record.establishment_timezone_name then
            raise exception 'First CONFIRMED Schedule Revision % must exactly match the preceding REQUESTED context',
                p_revision_id
                using errcode = '23514';
        end if;

        return;
    end if;

    -- later CONFIRMED revision: must be sourced from an ACCEPTED Proposal
    -- whose base revision is the true immediately preceding confirmed
    -- context — this is what makes a stale Proposal's acceptance fail.
    if revision_record.source_proposal_id is null then
        raise exception 'Later CONFIRMED Schedule Revision % requires a source Proposal',
            p_revision_id
            using errcode = '23514';
    end if;

    select proposal.*
    into proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = revision_record.source_proposal_id;

    if not found then
        raise exception 'Later CONFIRMED Schedule Revision % requires its source Proposal',
            p_revision_id
            using errcode = '23514';
    end if;

    if proposal_record.appointment_id <> revision_record.appointment_id then
        raise exception 'Schedule Revision % source Proposal must belong to the same Appointment',
            p_revision_id
            using errcode = '23514';
    end if;

    if proposal_record.state <> 'ACCEPTED' then
        raise exception 'Schedule Revision % source Proposal must be ACCEPTED',
            p_revision_id
            using errcode = '23514';
    end if;

    if proposal_record.resulting_confirmed_revision_id <> p_revision_id then
        raise exception 'Proposal % must reference Schedule Revision % as its resulting confirmed revision',
            revision_record.source_proposal_id, p_revision_id
            using errcode = '23514';
    end if;

    if revision_record.scheduled_start_at <> proposal_record.proposed_start_at
       or revision_record.scheduled_end_at <> proposal_record.proposed_end_at
       or revision_record.establishment_timezone_name <> proposal_record.proposed_timezone_name then
        raise exception 'Schedule Revision % must exactly match its source Proposal proposed context',
            p_revision_id
            using errcode = '23514';
    end if;

    select revision.*
    into preceding_confirmed_record
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_context = 'CONFIRMED'
      and revision.revision_sequence < revision_record.revision_sequence
    order by revision.revision_sequence desc
    limit 1;

    if not found or proposal_record.base_revision_id <> preceding_confirmed_record.id then
        raise exception 'Schedule Revision % source Proposal base revision is no longer the current confirmed context',
            p_revision_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_schedule_revision_provenance(uuid)
from public, anon, authenticated;

create function public.enforce_appointment_schedule_revision_provenance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_appointment_schedule_revision_provenance(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_schedule_revision_provenance()
from public, anon, authenticated;

create constraint trigger appointment_schedule_revisions_enforce_provenance
after insert on public.appointment_schedule_revisions
deferrable initially deferred
for each row
execute function public.enforce_appointment_schedule_revision_provenance();

create function public.assert_appointment_reschedule_proposal_acceptance(
    p_proposal_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    proposal_record public.appointment_reschedule_proposals%rowtype;
    revision_record public.appointment_schedule_revisions%rowtype;
begin
    select proposal.*
    into proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    if not found or proposal_record.state <> 'ACCEPTED' then
        return;
    end if;

    select revision.*
    into revision_record
    from public.appointment_schedule_revisions as revision
    where revision.id = proposal_record.resulting_confirmed_revision_id;

    if not found then
        raise exception 'Accepted Reschedule Proposal % requires its resulting confirmed Schedule Revision',
            p_proposal_id
            using errcode = '23514';
    end if;

    if revision_record.appointment_id <> proposal_record.appointment_id then
        raise exception 'Accepted Reschedule Proposal % resulting revision must belong to the same Appointment',
            p_proposal_id
            using errcode = '23514';
    end if;

    if revision_record.revision_context <> 'CONFIRMED' then
        raise exception 'Accepted Reschedule Proposal % resulting revision must be CONFIRMED',
            p_proposal_id
            using errcode = '23514';
    end if;

    if revision_record.source_proposal_id is distinct from p_proposal_id then
        raise exception 'Accepted Reschedule Proposal % resulting revision must reference it as source',
            p_proposal_id
            using errcode = '23514';
    end if;

    if revision_record.scheduled_start_at <> proposal_record.proposed_start_at
       or revision_record.scheduled_end_at <> proposal_record.proposed_end_at
       or revision_record.establishment_timezone_name <> proposal_record.proposed_timezone_name then
        raise exception 'Accepted Reschedule Proposal % resulting revision must match its proposed context',
            p_proposal_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_reschedule_proposal_acceptance(uuid)
from public, anon, authenticated;

create function public.enforce_appointment_reschedule_proposal_acceptance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_appointment_reschedule_proposal_acceptance(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_reschedule_proposal_acceptance()
from public, anon, authenticated;

create constraint trigger appointment_reschedule_proposals_enforce_acceptance
after update of state on public.appointment_reschedule_proposals
deferrable initially deferred
for each row
execute function public.enforce_appointment_reschedule_proposal_acceptance();

-- ==================================================================
-- 7. Cross-Clinic same-Veterinarian conflict — anchored on
--    veterinarian_professional_profiles.id (never denormalized onto
--    appointment_veterinarian_assignments). Three independent deferred
--    entry points cover every authoritative way a confirmed commitment
--    can be created or changed: Assignment writes, CONFIRMED Revision
--    inserts, and Appointment lifecycle activation into CONFIRMED.
-- ==================================================================

create function public.assert_veterinarian_confirmed_commitment_conflict_free(
    p_professional_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.veterinarian_professional_profiles as profile
    where profile.id = p_professional_profile_id
    for update;

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.appointment_veterinarian_assignments as first_assignment
        join public.veterinarian_clinic_assignments as first_clinic_assignment
          on first_clinic_assignment.id = first_assignment.veterinarian_clinic_assignment_id
        join public.appointments as first_appointment
          on first_appointment.id = first_assignment.appointment_id
        join lateral (
            select revision.scheduled_start_at, revision.scheduled_end_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = first_appointment.id
              and revision.revision_context = 'CONFIRMED'
            order by revision.revision_sequence desc
            limit 1
        ) as first_revision on true
        join public.appointment_veterinarian_assignments as second_assignment
          on second_assignment.appointment_id <> first_assignment.appointment_id
        join public.veterinarian_clinic_assignments as second_clinic_assignment
          on second_clinic_assignment.id = second_assignment.veterinarian_clinic_assignment_id
         and second_clinic_assignment.professional_profile_id
                = first_clinic_assignment.professional_profile_id
        join public.appointments as second_appointment
          on second_appointment.id = second_assignment.appointment_id
        join lateral (
            select revision.scheduled_start_at, revision.scheduled_end_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = second_appointment.id
              and revision.revision_context = 'CONFIRMED'
            order by revision.revision_sequence desc
            limit 1
        ) as second_revision on true
        where first_clinic_assignment.professional_profile_id = p_professional_profile_id
          and first_assignment.effective_end is null
          and second_assignment.effective_end is null
          and first_appointment.lifecycle_state = 'CONFIRMED'
          and second_appointment.lifecycle_state = 'CONFIRMED'
          and first_appointment.id < second_appointment.id
          and first_revision.scheduled_start_at < second_revision.scheduled_end_at
          and second_revision.scheduled_start_at < first_revision.scheduled_end_at
    ) then
        raise exception 'Veterinarian Professional Profile % has conflicting confirmed Appointment commitments across Clinics',
            p_professional_profile_id
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_veterinarian_confirmed_commitment_conflict_free(uuid)
from public, anon, authenticated;

create function public.enforce_appointment_veterinarian_assignment_conflict()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_assignment_id uuid;
    target_profile_id uuid;
begin
    if tg_op = 'DELETE' then
        target_assignment_id := old.veterinarian_clinic_assignment_id;
    else
        target_assignment_id := new.veterinarian_clinic_assignment_id;
    end if;

    select assignment.professional_profile_id
    into target_profile_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = target_assignment_id;

    if found then
        perform public.assert_veterinarian_confirmed_commitment_conflict_free(target_profile_id);
    end if;

    if tg_op = 'UPDATE'
       and old.veterinarian_clinic_assignment_id is distinct from new.veterinarian_clinic_assignment_id then
        select assignment.professional_profile_id
        into target_profile_id
        from public.veterinarian_clinic_assignments as assignment
        where assignment.id = old.veterinarian_clinic_assignment_id;

        if found then
            perform public.assert_veterinarian_confirmed_commitment_conflict_free(target_profile_id);
        end if;
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_veterinarian_assignment_conflict()
from public, anon, authenticated;

create constraint trigger appointment_veterinarian_assignments_enforce_conflict
after insert or update or delete on public.appointment_veterinarian_assignments
deferrable initially deferred
for each row
execute function public.enforce_appointment_veterinarian_assignment_conflict();

create function public.enforce_appointment_schedule_revision_conflict()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_profile_id uuid;
begin
    if new.revision_context <> 'CONFIRMED' then
        return null;
    end if;

    select assignment.professional_profile_id
    into target_profile_id
    from public.appointment_veterinarian_assignments as appointment_assignment
    join public.veterinarian_clinic_assignments as assignment
      on assignment.id = appointment_assignment.veterinarian_clinic_assignment_id
    where appointment_assignment.appointment_id = new.appointment_id
      and appointment_assignment.effective_end is null;

    if found then
        perform public.assert_veterinarian_confirmed_commitment_conflict_free(target_profile_id);
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_schedule_revision_conflict()
from public, anon, authenticated;

create constraint trigger appointment_schedule_revisions_enforce_conflict
after insert on public.appointment_schedule_revisions
deferrable initially deferred
for each row
execute function public.enforce_appointment_schedule_revision_conflict();

create function public.enforce_appointment_lifecycle_conflict()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_profile_id uuid;
begin
    if new.lifecycle_state <> 'CONFIRMED' then
        return null;
    end if;

    select assignment.professional_profile_id
    into target_profile_id
    from public.appointment_veterinarian_assignments as appointment_assignment
    join public.veterinarian_clinic_assignments as assignment
      on assignment.id = appointment_assignment.veterinarian_clinic_assignment_id
    where appointment_assignment.appointment_id = new.id
      and appointment_assignment.effective_end is null;

    if found then
        perform public.assert_veterinarian_confirmed_commitment_conflict_free(target_profile_id);
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_lifecycle_conflict()
from public, anon, authenticated;

create constraint trigger appointments_enforce_veterinarian_conflict
after update of lifecycle_state on public.appointments
deferrable initially deferred
for each row
execute function public.enforce_appointment_lifecycle_conflict();

-- ==================================================================
-- 8. Capability extension — only the four capabilities Slice 9's own
--    RPCs consume (SPEC-ORG-005 §5). APPOINTMENT_CANCEL,
--    APPOINTMENT_COMPLETE, and APPOINTMENT_MARK_NO_SHOW are left for
--    the slices that implement their corresponding RPCs.
--    Per SPEC-ORG-005 §6: RECEPTIONIST receives every Appointment
--    capability within its scope; a plain VETERINARIAN responsibility
--    receives only APPOINTMENT_VIEW_SCHEDULE, and only where the User
--    also holds a current Veterinarian Clinic Assignment at that Clinic.
-- ==================================================================

create or replace function public.user_has_clinic_capability(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        coalesce(
            p_capability in (
                'CLINIC_MANAGE_LOCATION',
                'CLINIC_MANAGE_PUBLIC_PROFILE',
                'CLINIC_MANAGE_PUBLICATION',
                'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
                'CLINIC_MANAGE_SERVICES',
                'CLINIC_MANAGE_OPENING_HOURS',
                'APPOINTMENT_MANAGE_AVAILABILITY',
                'APPOINTMENT_VIEW_SCHEDULE',
                'APPOINTMENT_CONFIRM',
                'APPOINTMENT_RESCHEDULE',
                'APPOINTMENT_ASSIGN_VETERINARIAN'
            ),
            false
        )
        and (
            exists (
                select 1
                from public.clinics as clinic
                join public.organization_memberships as membership
                  on membership.organization_id = clinic.organization_id
                join public.organization_responsibility_grants as grant_record
                  on grant_record.membership_id = membership.id
                where clinic.id = p_clinic_id
                  and membership.user_id = p_user_id
                  and membership.effective_end is null
                  and grant_record.effective_end is null
                  and (
                      (
                          grant_record.scope_type = 'ORGANIZATION'
                          and grant_record.clinic_id is null
                          and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
                      )
                      or
                      (
                          grant_record.scope_type = 'CLINIC'
                          and grant_record.clinic_id = p_clinic_id
                          and grant_record.responsibility = 'ADMINISTRATOR'
                      )
                      or
                      (
                          grant_record.responsibility = 'RECEPTIONIST'
                          and p_capability in (
                              'APPOINTMENT_MANAGE_AVAILABILITY',
                              'APPOINTMENT_VIEW_SCHEDULE',
                              'APPOINTMENT_CONFIRM',
                              'APPOINTMENT_RESCHEDULE',
                              'APPOINTMENT_ASSIGN_VETERINARIAN'
                          )
                          and (
                              (
                                  grant_record.scope_type = 'ORGANIZATION'
                                  and grant_record.clinic_id is null
                              )
                              or
                              (
                                  grant_record.scope_type = 'CLINIC'
                                  and grant_record.clinic_id = p_clinic_id
                              )
                          )
                      )
                  )
            )
            or
            (
                p_capability = 'APPOINTMENT_VIEW_SCHEDULE'
                and exists (
                    select 1
                    from public.clinics as clinic
                    join public.organization_memberships as membership
                      on membership.organization_id = clinic.organization_id
                    join public.organization_responsibility_grants as grant_record
                      on grant_record.membership_id = membership.id
                    join public.veterinarian_professional_profiles as profile
                      on profile.user_id = p_user_id
                    join public.veterinarian_clinic_assignments as clinic_assignment
                      on clinic_assignment.professional_profile_id = profile.id
                     and clinic_assignment.clinic_id = p_clinic_id
                    where clinic.id = p_clinic_id
                      and membership.user_id = p_user_id
                      and membership.effective_end is null
                      and grant_record.effective_end is null
                      and grant_record.responsibility = 'VETERINARIAN'
                      and grant_record.scope_type = 'ORGANIZATION'
                      and grant_record.clinic_id is null
                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
                )
            )
        )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- A later Guardianship or professional grant must not revive a Proposal after
-- the proposing side lost authority. A Guardian Proposal remains tied to the
-- same still-current Guardianship period that covered creation. Clinic
-- authority may be continuously supplied by overlapping capability grants,
-- but a genuine temporal gap is permanent.
create function public.user_has_continuous_guardianship_since(
    p_user_id uuid,
    p_pet_id uuid,
    p_since timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.user_id = p_user_id
          and guardianship.pet_id = p_pet_id
          and guardianship.effective_start <= p_since
          and guardianship.effective_end is null
    )
$$;

revoke all privileges
on function public.user_has_continuous_guardianship_since(uuid, uuid, timestamptz)
from public, anon, authenticated;

create function public.user_has_continuous_clinic_reschedule_authority_since(
    p_user_id uuid,
    p_clinic_id uuid,
    p_since timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    with recursive authority_intervals as (
        select
            greatest(membership.effective_start, grant_record.effective_start) as interval_start,
            least(
                coalesce(membership.effective_end, 'infinity'::timestamptz),
                coalesce(grant_record.effective_end, 'infinity'::timestamptz)
            ) as interval_end
        from public.clinics as clinic
        join public.organization_memberships as membership
          on membership.organization_id = clinic.organization_id
        join public.organization_responsibility_grants as grant_record
          on grant_record.membership_id = membership.id
        where clinic.id = p_clinic_id
          and membership.user_id = p_user_id
          and (
              (
                  grant_record.scope_type = 'ORGANIZATION'
                  and grant_record.clinic_id is null
                  and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR', 'RECEPTIONIST')
              )
              or
              (
                  grant_record.scope_type = 'CLINIC'
                  and grant_record.clinic_id = p_clinic_id
                  and grant_record.responsibility in ('ADMINISTRATOR', 'RECEPTIONIST')
              )
          )
          and greatest(membership.effective_start, grant_record.effective_start)
              <= least(
                  coalesce(membership.effective_end, 'infinity'::timestamptz),
                  coalesce(grant_record.effective_end, 'infinity'::timestamptz)
              )
    ),
    continuous_coverage (covered_until) as (
        select authority_period.interval_end
        from authority_intervals as authority_period
        where authority_period.interval_start <= p_since
          and authority_period.interval_end >= p_since

        union

        select authority_period.interval_end
        from continuous_coverage as coverage
        join authority_intervals as authority_period
          on authority_period.interval_start <= coverage.covered_until
         and authority_period.interval_end > coverage.covered_until
    )
    select exists (
        select 1
        from continuous_coverage as coverage
        where coverage.covered_until = 'infinity'::timestamptz
    )
$$;

revoke all privileges
on function public.user_has_continuous_clinic_reschedule_authority_since(
    uuid, uuid, timestamptz
)
from public, anon, authenticated;

-- Read-time actionability is derived from authoritative present state so no
-- scheduler is needed to hide a stale Proposal. The persisted non-actionable
-- facts below preserve the first resolution observed by the creation workflow.
create function public.appointment_reschedule_proposal_is_actionable(
    p_proposal_id uuid,
    p_as_of timestamptz,
    p_ignored_resulting_revision_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.appointment_reschedule_proposals as proposal
        join public.appointments as appointment
          on appointment.id = proposal.appointment_id
        join public.appointment_schedule_revisions as base_revision
          on base_revision.id = proposal.base_revision_id
        where proposal.id = p_proposal_id
          and proposal.state = 'PENDING'
          and proposal.non_actionable_at is null
          and appointment.lifecycle_state = 'CONFIRMED'
          and base_revision.revision_context = 'CONFIRMED'
          and base_revision.scheduled_start_at > p_as_of
          and proposal.proposed_start_at > p_as_of
          and not exists (
              select 1
              from public.appointment_schedule_revisions as later_revision
              where later_revision.appointment_id = proposal.appointment_id
                and later_revision.revision_context = 'CONFIRMED'
                and later_revision.revision_sequence > base_revision.revision_sequence
                and later_revision.id is distinct from p_ignored_resulting_revision_id
          )
          and (
              (
                  proposal.proposing_context = 'GUARDIAN'
                  and public.user_has_continuous_guardianship_since(
                      proposal.proposed_by_user_id,
                      appointment.pet_id,
                      proposal.created_at
                  )
              )
              or
              (
                  proposal.proposing_context = 'CLINIC'
                  and public.user_has_continuous_clinic_reschedule_authority_since(
                      proposal.proposed_by_user_id,
                      appointment.clinic_id,
                      proposal.created_at
                  )
              )
          )
    )
$$;

revoke all privileges
on function public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz, uuid)
from public, anon, authenticated;

-- ==================================================================
-- 9. Authorization-before-Entitlement ordering, extending the exact
--    Slice 8 idiom (Organization lock -> Clinic lock -> capability ->
--    Entitlement). Two variants: one that requires both a Clinic
--    capability and an Entitlement (the normal professional path),
--    and one that requires only the Entitlement (used when the acting
--    side is a Guardian, who never holds a Clinic capability, but the
--    Organization's commercial gate still applies to the commitment
--    being established).
-- ==================================================================

create function public.assert_clinic_appointment_authorization_after_lock(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text,
    p_entitlement_identifier text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_organization_id uuid;
begin
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if not public.user_has_clinic_capability(p_user_id, p_clinic_id, p_capability) then
        raise exception 'Applicable Appointment-management capability is required'
            using errcode = '42501';
    end if;

    if not public.organization_has_professional_entitlement(
        target_organization_id, p_entitlement_identifier
    ) then
        raise exception 'Applicable professional Entitlement is required'
            using errcode = '42501';
    end if;

    return target_organization_id;
end;
$$;

revoke all privileges
on function public.assert_clinic_appointment_authorization_after_lock(uuid, uuid, text, text)
from public, anon, authenticated;

create function public.assert_clinic_organization_entitlement_after_lock(
    p_clinic_id uuid,
    p_entitlement_identifier text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_organization_id uuid;
begin
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if not public.organization_has_professional_entitlement(
        target_organization_id, p_entitlement_identifier
    ) then
        raise exception 'Applicable professional Entitlement is required'
            using errcode = '42501';
    end if;

    return target_organization_id;
end;
$$;

revoke all privileges
on function public.assert_clinic_organization_entitlement_after_lock(uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 10. RLS / privilege boundary.
-- ==================================================================

alter table public.appointments enable row level security;
alter table public.appointment_lifecycle_events enable row level security;
alter table public.appointment_schedule_revisions enable row level security;
alter table public.appointment_reschedule_proposals enable row level security;
alter table public.appointment_veterinarian_assignments enable row level security;

revoke all privileges on table public.appointments
from public, anon, authenticated;
revoke all privileges on table public.appointment_lifecycle_events
from public, anon, authenticated;
revoke all privileges on table public.appointment_schedule_revisions
from public, anon, authenticated;
revoke all privileges on table public.appointment_reschedule_proposals
from public, anon, authenticated;
revoke all privileges on table public.appointment_veterinarian_assignments
from public, anon, authenticated;

-- ==================================================================
-- 11. Mutation RPCs — exactly the six non-blocked Slice 9 operations.
--     request_appointment / cancel_appointment (Slice 10, Care
--     Authorization) and complete_appointment / mark_appointment_no_show
--     (Slice 12, Clinical Encounter) are not implemented here.
-- ==================================================================

create function public.confirm_appointment(
    p_appointment_id uuid
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
on function public.confirm_appointment(uuid)
from public, anon, authenticated;

grant execute
on function public.confirm_appointment(uuid)
to authenticated;

create function public.reschedule_requested_appointment(
    p_appointment_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_end_local_date date,
    p_end_local_time time,
    p_end_utc_offset_seconds integer
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
    resolved_interval record;
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

    -- Resolve the immutable Appointment -> Clinic identity without a write
    -- lock, then use Clinic as the scheduling-configuration serialization
    -- boundary. Guardian rescheduling intentionally acquires no Organization
    -- or Entitlement lock.
    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id
    for update;

    if not found then
        raise exception 'Appointment Clinic does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = resolved_clinic_id
    for update;

    if not found then
        raise exception 'Appointment does not exist in the expected Clinic'
            using errcode = '23503';
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = resolved_clinic_id;

    if appointment_record.lifecycle_state <> 'REQUESTED' then
        raise exception 'Only a REQUESTED Appointment may be rescheduled through this workflow'
            using errcode = '23514';
    end if;

    -- Lock and revalidate the exact current Guardianship row after the
    -- Appointment serialization point. A concurrent effective-end update
    -- therefore orders wholly before this mutation (and makes it fail) or
    -- after its commit.
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

    operation_timestamp := clock_timestamp();

    select * into resolved_interval
    from public.resolve_clinic_appointment_interval(
        resolved_clinic_id,
        p_start_local_date, p_start_local_time, p_start_utc_offset_seconds,
        p_end_local_date, p_end_local_time, p_end_utc_offset_seconds
    );

    if resolved_interval.resolved_start_at <= operation_timestamp then
        raise exception 'Rescheduled Appointment time must be in the future'
            using errcode = '22023';
    end if;

    if resolved_interval.resolved_start_at = latest_requested_revision.scheduled_start_at
       and resolved_interval.resolved_end_at = latest_requested_revision.scheduled_end_at then
        raise exception 'Rescheduled time must differ from the current requested time'
            using errcode = '22023';
    end if;

    if not public.clinic_appointment_interval_is_available(
        resolved_clinic_id,
        resolved_interval.resolved_start_at,
        resolved_interval.resolved_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the new requested interval'
            using errcode = '23514';
    end if;

    -- Re-evaluate any existing current Assignment against the NEW
    -- requested interval before committing to it; eligibility at the old
    -- requested time never carries forward automatically. The Appointment
    -- Assignment row prevents concurrent reassignment, and the referenced
    -- Clinic Assignment row serializes against Assignment ending and
    -- Veterinarian Availability replacement.
    select assignment.*
    into current_assignment_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null
    for update;

    if found then
        perform 1
        from public.veterinarian_clinic_assignments as clinic_assignment
        where clinic_assignment.id
                  = current_assignment_record.veterinarian_clinic_assignment_id
          and clinic_assignment.clinic_id = resolved_clinic_id
        for update;

        if not found then
            raise exception 'Current Appointment Veterinarian Assignment has no matching Clinic Assignment'
                using errcode = '23514';
        end if;

        if not public.veterinarian_clinic_assignment_is_current(
            current_assignment_record.veterinarian_clinic_assignment_id
        ) then
            raise exception 'Currently assigned Veterinarian no longer has a valid Clinic Assignment'
                using errcode = '23514';
        end if;

        if not public.veterinarian_availability_covers_interval(
            current_assignment_record.veterinarian_clinic_assignment_id,
            resolved_interval.resolved_start_at, resolved_interval.resolved_end_at
        ) then
            raise exception 'Currently assigned Veterinarian is not available for the new requested interval'
                using errcode = '23514';
        end if;
    end if;

    next_sequence := public.next_appointment_revision_sequence(p_appointment_id);

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        p_appointment_id, next_sequence, 'REQUESTED',
        resolved_interval.resolved_start_at, resolved_interval.resolved_end_at,
        resolved_interval.timezone_name, acting_user_id, null, operation_timestamp
    );

    return p_appointment_id;
end;
$$;

revoke all privileges
on function public.reschedule_requested_appointment(
    uuid, date, time, integer, date, time, integer
)
from public, anon, authenticated;

grant execute
on function public.reschedule_requested_appointment(
    uuid, date, time, integer, date, time, integer
)
to authenticated;

create function public.propose_confirmed_appointment_reschedule(
    p_appointment_id uuid,
    p_proposing_context text,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_end_local_date date,
    p_end_local_time time,
    p_end_utc_offset_seconds integer,
    p_reason text
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
    latest_confirmed_revision public.appointment_schedule_revisions%rowtype;
    existing_proposal_record public.appointment_reschedule_proposals%rowtype;
    resolved_interval record;
    normalized_reason text;
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

    if p_proposing_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Proposing context must be GUARDIAN or CLINIC'
            using errcode = '22023';
    end if;

    -- Resolve the immutable Appointment Clinic context without a write
    -- lock. A CLINIC-context proposal then acquires the normal aggregate
    -- Organization -> Clinic order BEFORE the Appointment lock, matching
    -- confirm/assign/reassign and avoiding the reverse-order deadlock
    -- risk. A GUARDIAN-context proposal needs no commercial locking at
    -- all to create a PENDING proposal and goes straight to the minimal
    -- Guardian/Appointment serialization path.
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
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may receive a reschedule Proposal'
            using errcode = '23514';
    end if;

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

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    if p_proposing_context = 'CLINIC' and normalized_reason is null then
        raise exception 'A meaningful reason is required for a Clinic-proposed reschedule'
            using errcode = '22023';
    end if;

    select revision.*
    into latest_confirmed_revision
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

    if latest_confirmed_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    -- Only an intrinsically actionable PENDING Proposal blocks a later
    -- negotiation. When this locked workflow first observes an approved
    -- permanent invalidation condition, it records that historical fact and
    -- releases the partial-unique slot atomically with the new Proposal.
    select proposal.*
    into existing_proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.appointment_id = p_appointment_id
      and proposal.state = 'PENDING'
      and proposal.non_actionable_at is null
    for update;

    if found then
        if existing_proposal_record.base_revision_id <> latest_confirmed_revision.id then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'BASE_REVISION_SUPERSEDED'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposed_start_at <= operation_timestamp then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'PROPOSED_TIME_PASSED'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'GUARDIAN'
              and not public.user_has_continuous_guardianship_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.pet_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'CLINIC'
              and not public.user_has_continuous_clinic_reschedule_authority_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.clinic_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        else
            raise exception 'Appointment % already has an actionable unresolved reschedule Proposal',
                p_appointment_id
                using errcode = '23505';
        end if;
    end if;

    select * into resolved_interval
    from public.resolve_clinic_appointment_interval(
        appointment_record.clinic_id,
        p_start_local_date, p_start_local_time, p_start_utc_offset_seconds,
        p_end_local_date, p_end_local_time, p_end_utc_offset_seconds
    );

    if resolved_interval.resolved_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must be in the future'
            using errcode = '22023';
    end if;

    if resolved_interval.resolved_start_at = latest_confirmed_revision.scheduled_start_at
       and resolved_interval.resolved_end_at = latest_confirmed_revision.scheduled_end_at then
        raise exception 'Proposed time must differ from the current confirmed time'
            using errcode = '22023';
    end if;

    insert into public.appointment_reschedule_proposals (
        appointment_id, base_revision_id,
        proposed_start_at, proposed_end_at, proposed_timezone_name,
        proposing_context, proposed_by_user_id, reason, created_at
    )
    values (
        p_appointment_id, latest_confirmed_revision.id,
        resolved_interval.resolved_start_at, resolved_interval.resolved_end_at,
        resolved_interval.timezone_name,
        p_proposing_context, acting_user_id, normalized_reason, operation_timestamp
    )
    returning id into created_proposal_id;

    return created_proposal_id;
end;
$$;

revoke all privileges
on function public.propose_confirmed_appointment_reschedule(
    uuid, text, date, time, integer, date, time, integer, text
)
from public, anon, authenticated;

grant execute
on function public.propose_confirmed_appointment_reschedule(
    uuid, text, date, time, integer, date, time, integer, text
)
to authenticated;

create function public.accept_appointment_reschedule_proposal(
    p_proposal_id uuid,
    p_accepting_context text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    initial_proposing_context text;
    resolved_appointment_id uuid;
    resolved_clinic_id uuid;
    proposal_record public.appointment_reschedule_proposals%rowtype;
    appointment_record public.appointments%rowtype;
    current_confirmed_revision public.appointment_schedule_revisions%rowtype;
    current_assignment_record public.appointment_veterinarian_assignments%rowtype;
    next_sequence integer;
    operation_timestamp timestamptz;
    created_revision_id uuid;
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

    if p_accepting_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Accepting context must be GUARDIAN or CLINIC'
            using errcode = '22023';
    end if;

    -- Resolve immutable Proposal -> Appointment -> Clinic context first,
    -- without acquiring a conflicting write lock, so we know which
    -- Organization/Clinic to lock before ever touching the Appointment.
    select proposal.appointment_id, proposal.proposing_context
    into resolved_appointment_id, initial_proposing_context
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    if not found then
        raise exception 'Reschedule Proposal does not exist'
            using errcode = '23503';
    end if;

    if initial_proposing_context = p_accepting_context then
        raise exception 'The proposing context cannot accept its own Proposal'
            using errcode = '42501';
    end if;

    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if p_accepting_context = 'GUARDIAN' then
        -- Guardian domain authority is proven before any commercial
        -- lock is taken; the commercial gate still applies to the
        -- Organization regardless of who accepts (see APPOINTMENT_MANAGEMENT
        -- below), but capability disclosure ordering only matters for
        -- the CLINIC path, where the acting User could otherwise learn
        -- Entitlement state before proving Clinic capability.
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

        perform public.assert_clinic_organization_entitlement_after_lock(
            resolved_clinic_id, 'APPOINTMENT_MANAGEMENT'
        );
    else
        perform public.assert_clinic_appointment_authorization_after_lock(
            acting_user_id, resolved_clinic_id,
            'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_MANAGEMENT'
        );
    end if;

    -- Appointment lock acquired only after Organization/Clinic, matching
    -- the normal aggregate order used everywhere else. Re-read both the
    -- Proposal and the Appointment now — never trust the pre-lock
    -- snapshot taken above.
    perform 1
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id
    for update;

    select proposal.*
    into proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Appointment must remain CONFIRMED to accept a reschedule Proposal'
            using errcode = '23514';
    end if;

    if proposal_record.state <> 'PENDING'
       or proposal_record.non_actionable_at is not null then
        raise exception 'Reschedule Proposal is no longer actionable'
            using errcode = '23514';
    end if;

    -- The pre-lock Guardian check above prevents commercial-state
    -- disclosure. This exact-row lock is the authoritative acceptance-time
    -- revalidation after Organization -> Clinic -> Appointment locking.
    if p_accepting_context = 'GUARDIAN' then
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

    -- Revalidate the authority of the proposing User from current domain
    -- truth. Guardian authority is serialized on the exact Guardianship
    -- row so a concurrent effective-end update either precedes this check
    -- (and makes it fail) or follows the committed acceptance. Clinic
    -- authority is evaluated while the established Organization -> Clinic
    -- locks remain held; Organization authority mutations use that same
    -- Organization serialization boundary.
    if proposal_record.proposing_context = 'GUARDIAN' then
        perform 1
        from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id
          and guardianship.user_id = proposal_record.proposed_by_user_id
          and guardianship.effective_end is null
        for update;

        if not found
           or not public.user_has_continuous_guardianship_since(
               proposal_record.proposed_by_user_id,
               appointment_record.pet_id,
               proposal_record.created_at
           ) then
            raise exception 'The Guardian Proposal is no longer actionable because proposing authority was lost'
                using errcode = '42501';
        end if;
    elsif not public.user_has_continuous_clinic_reschedule_authority_since(
        proposal_record.proposed_by_user_id,
        appointment_record.clinic_id,
        proposal_record.created_at
    ) then
        raise exception 'The Clinic Proposal is no longer actionable because proposing authority was lost'
            using errcode = '42501';
    end if;

    select revision.*
    into current_confirmed_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = appointment_record.id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc
    limit 1;

    if not found
       or current_confirmed_revision.id <> proposal_record.base_revision_id then
        raise exception 'Reschedule Proposal base revision is no longer the current confirmed context'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    if current_confirmed_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be future and actionable'
            using errcode = '23514';
    end if;

    if proposal_record.proposed_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    if not public.clinic_appointment_interval_is_available(
        appointment_record.clinic_id,
        proposal_record.proposed_start_at, proposal_record.proposed_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the proposed interval'
            using errcode = '23514';
    end if;

    select assignment.*
    into current_assignment_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = appointment_record.id
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
            proposal_record.proposed_start_at, proposal_record.proposed_end_at
        ) then
            raise exception 'Currently assigned Veterinarian is not available for the proposed interval'
                using errcode = '23514';
        end if;
    end if;

    next_sequence := public.next_appointment_revision_sequence(appointment_record.id);

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        appointment_record.id, next_sequence, 'CONFIRMED',
        proposal_record.proposed_start_at, proposal_record.proposed_end_at,
        proposal_record.proposed_timezone_name, acting_user_id, p_proposal_id, operation_timestamp
    )
    returning id into created_revision_id;

    update public.appointment_reschedule_proposals
    set state = 'ACCEPTED',
        accepted_at = operation_timestamp,
        accepted_by_user_id = acting_user_id,
        accepting_context = p_accepting_context,
        resulting_confirmed_revision_id = created_revision_id
    where id = p_proposal_id;

    return p_proposal_id;
end;
$$;

revoke all privileges
on function public.accept_appointment_reschedule_proposal(uuid, text)
from public, anon, authenticated;

grant execute
on function public.accept_appointment_reschedule_proposal(uuid, text)
to authenticated;

create function public.assign_veterinarian_to_appointment(
    p_appointment_id uuid,
    p_veterinarian_clinic_assignment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_record public.appointments%rowtype;
    latest_revision public.appointment_schedule_revisions%rowtype;
    operation_timestamp timestamptz;
    created_assignment_id uuid;
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

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform public.assert_clinic_appointment_authorization_after_lock(
        acting_user_id, appointment_record.clinic_id,
        'APPOINTMENT_ASSIGN_VETERINARIAN', 'PROFESSIONAL_SCHEDULING'
    );

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- Re-read after the lock — the pre-lock snapshot's lifecycle_state
    -- must not drive the scheduling-context decision below.
    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if exists (
        select 1
        from public.appointment_veterinarian_assignments as assignment
        where assignment.appointment_id = p_appointment_id
          and assignment.effective_end is null
    ) then
        raise exception 'Appointment already has a current Veterinarian Assignment; use reassignment'
            using errcode = '23505';
    end if;

    -- Applicable current scheduling context: latest REQUESTED revision
    -- while REQUESTED, latest CONFIRMED revision while CONFIRMED. The
    -- Veterinarian must satisfy Availability for it either way; only the
    -- cross-Clinic confirmed-commitment conflict check (a separate
    -- deferred trigger) is limited to the CONFIRMED case.
    select revision.*
    into latest_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = case
          when appointment_record.lifecycle_state = 'CONFIRMED' then 'CONFIRMED'
          else 'REQUESTED'
      end
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no applicable scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    if not public.veterinarian_availability_covers_interval(
        p_veterinarian_clinic_assignment_id,
        latest_revision.scheduled_start_at, latest_revision.scheduled_end_at
    ) then
        raise exception 'Veterinarian is not available for the Appointment scheduling context'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.appointment_veterinarian_assignments (
        appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id
    )
    values (
        p_appointment_id, p_veterinarian_clinic_assignment_id, operation_timestamp, acting_user_id
    )
    returning id into created_assignment_id;

    return created_assignment_id;
end;
$$;

revoke all privileges
on function public.assign_veterinarian_to_appointment(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.assign_veterinarian_to_appointment(uuid, uuid)
to authenticated;

create function public.reassign_veterinarian(
    p_appointment_id uuid,
    p_new_veterinarian_clinic_assignment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_record public.appointments%rowtype;
    current_assignment_record public.appointment_veterinarian_assignments%rowtype;
    latest_revision public.appointment_schedule_revisions%rowtype;
    old_profile_id uuid;
    new_profile_id uuid;
    first_lock_profile_id uuid;
    second_lock_profile_id uuid;
    operation_timestamp timestamptz;
    created_assignment_id uuid;
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

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform public.assert_clinic_appointment_authorization_after_lock(
        acting_user_id, appointment_record.clinic_id,
        'APPOINTMENT_ASSIGN_VETERINARIAN', 'PROFESSIONAL_SCHEDULING'
    );

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- Re-read after the lock — the pre-lock snapshot's lifecycle_state
    -- must not drive the scheduling-context decision below.
    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    select assignment.*
    into current_assignment_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null;

    if not found then
        raise exception 'Appointment has no current Veterinarian Assignment to reassign'
            using errcode = '23514';
    end if;

    if current_assignment_record.veterinarian_clinic_assignment_id
           = p_new_veterinarian_clinic_assignment_id then
        raise exception 'Reassignment to the same Veterinarian Clinic Assignment is a no-op'
            using errcode = '22023';
    end if;

    select assignment.professional_profile_id
    into old_profile_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = current_assignment_record.veterinarian_clinic_assignment_id;

    select assignment.professional_profile_id
    into new_profile_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_new_veterinarian_clinic_assignment_id;

    if new_profile_id is null then
        raise exception 'Replacement Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if old_profile_id is distinct from new_profile_id then
        first_lock_profile_id := least(old_profile_id, new_profile_id);
        second_lock_profile_id := greatest(old_profile_id, new_profile_id);

        perform 1
        from public.veterinarian_professional_profiles as profile
        where profile.id = first_lock_profile_id
        for update;

        perform 1
        from public.veterinarian_professional_profiles as profile
        where profile.id = second_lock_profile_id
        for update;
    else
        perform 1
        from public.veterinarian_professional_profiles as profile
        where profile.id = old_profile_id
        for update;
    end if;

    -- Applicable current scheduling context, same rule as assignment:
    -- latest REQUESTED revision while REQUESTED, latest CONFIRMED
    -- revision while CONFIRMED. If the replacement is unavailable,
    -- reassignment fails atomically here — before either the effective_end
    -- UPDATE or the new-row INSERT — so the original current Assignment
    -- remains exactly as it was; no schedule mutation occurs.
    select revision.*
    into latest_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = case
          when appointment_record.lifecycle_state = 'CONFIRMED' then 'CONFIRMED'
          else 'REQUESTED'
      end
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no applicable scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    if not public.veterinarian_availability_covers_interval(
        p_new_veterinarian_clinic_assignment_id,
        latest_revision.scheduled_start_at, latest_revision.scheduled_end_at
    ) then
        raise exception 'Replacement Veterinarian is not available for the Appointment scheduling context'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    update public.appointment_veterinarian_assignments
    set effective_end = operation_timestamp
    where id = current_assignment_record.id;

    insert into public.appointment_veterinarian_assignments (
        appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id
    )
    values (
        p_appointment_id, p_new_veterinarian_clinic_assignment_id, operation_timestamp, acting_user_id
    )
    returning id into created_assignment_id;

    return created_assignment_id;
end;
$$;

revoke all privileges
on function public.reassign_veterinarian(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.reassign_veterinarian(uuid, uuid)
to authenticated;

-- ==================================================================
-- 12. Bounded authenticated reads (SPEC-APT-007 / SPEC-APT-008 /
--     SPEC-APT-011 / SPEC-APT-012).
--     Neither requires professional Entitlement — SPEC-SUB-003 BR-26
--     and SPEC-SUB-004 §4 classify historical/operational read access
--     as distinct from normal paid activity.
-- ==================================================================

-- Schedule Revision history is one-to-many, so it has a dedicated
-- per-Appointment read instead of being embedded as an aggregate payload in
-- either list row. Accepted Proposal facts are projected only where needed
-- to interpret an accepted reschedule; raw Proposal identity/state and all
-- medical/commercial data remain private.
create function public.get_appointment_scheduling_history(
    p_appointment_id uuid
)
returns table (
    revision_sequence integer,
    revision_context text,
    scheduled_start_at timestamptz,
    scheduled_end_at timestamptz,
    establishment_timezone_name text,
    established_by_user_id uuid,
    established_at timestamptz,
    is_accepted_reschedule boolean,
    reschedule_proposing_context text,
    reschedule_proposed_by_user_id uuid,
    reschedule_reason text,
    reschedule_proposed_at timestamptz,
    reschedule_accepting_context text,
    reschedule_accepted_by_user_id uuid,
    reschedule_accepted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_pet_id uuid;
    appointment_clinic_id uuid;
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

    select appointment.pet_id, appointment.clinic_id
    into appointment_pet_id, appointment_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if not (
        exists (
            select 1
            from public.guardianships as guardianship
            where guardianship.pet_id = appointment_pet_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_end is null
        )
        or public.user_has_clinic_capability(
            acting_user_id,
            appointment_clinic_id,
            'APPOINTMENT_VIEW_SCHEDULE'
        )
    ) then
        raise exception 'Current Guardianship or applicable Clinic schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        revision.revision_sequence,
        revision.revision_context,
        revision.scheduled_start_at,
        revision.scheduled_end_at,
        revision.establishment_timezone_name,
        revision.established_by_user_id,
        revision.created_at,
        source_proposal.id is not null,
        source_proposal.proposing_context,
        source_proposal.proposed_by_user_id,
        source_proposal.reason,
        source_proposal.created_at,
        source_proposal.accepting_context,
        source_proposal.accepted_by_user_id,
        source_proposal.accepted_at
    from public.appointment_schedule_revisions as revision
    left join public.appointment_reschedule_proposals as source_proposal
      on source_proposal.id = revision.source_proposal_id
    where revision.appointment_id = p_appointment_id
    order by revision.revision_sequence;
end;
$$;

revoke all privileges
on function public.get_appointment_scheduling_history(uuid)
from public, anon, authenticated;

grant execute
on function public.get_appointment_scheduling_history(uuid)
to authenticated;

-- Veterinarian Assignment is independently temporal and may contain several
-- periods for one Appointment. Return only the stable Assignment identity,
-- Veterinarian identity, temporal facts, and assigning actor required by
-- SPEC-APT-007 BR-18/BR-24 and SPEC-APT-008 BR-2/BR-27.
create function public.get_appointment_veterinarian_assignment_history(
    p_appointment_id uuid
)
returns table (
    appointment_veterinarian_assignment_id uuid,
    veterinarian_professional_profile_id uuid,
    effective_start timestamptz,
    effective_end timestamptz,
    assigned_by_user_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_pet_id uuid;
    appointment_clinic_id uuid;
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

    select appointment.pet_id, appointment.clinic_id
    into appointment_pet_id, appointment_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if not (
        exists (
            select 1
            from public.guardianships as guardianship
            where guardianship.pet_id = appointment_pet_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_end is null
        )
        or public.user_has_clinic_capability(
            acting_user_id,
            appointment_clinic_id,
            'APPOINTMENT_VIEW_SCHEDULE'
        )
    ) then
        raise exception 'Current Guardianship or applicable Clinic schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        appointment_assignment.id,
        clinic_assignment.professional_profile_id,
        appointment_assignment.effective_start,
        appointment_assignment.effective_end,
        appointment_assignment.assigned_by_user_id
    from public.appointment_veterinarian_assignments as appointment_assignment
    join public.veterinarian_clinic_assignments as clinic_assignment
      on clinic_assignment.id = appointment_assignment.veterinarian_clinic_assignment_id
    where appointment_assignment.appointment_id = p_appointment_id
    order by appointment_assignment.effective_start, appointment_assignment.id;
end;
$$;

revoke all privileges
on function public.get_appointment_veterinarian_assignment_history(uuid)
from public, anon, authenticated;

grant execute
on function public.get_appointment_veterinarian_assignment_history(uuid)
to authenticated;

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
          and revision.revision_context = case
              when appointment.lifecycle_state = 'CONFIRMED' then 'CONFIRMED'
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

create function public.get_clinic_appointment_schedule(
    p_clinic_id uuid
)
returns table (
    id uuid,
    pet_id uuid,
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
          and revision.revision_context = case
              when appointment.lifecycle_state = 'CONFIRMED' then 'CONFIRMED'
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

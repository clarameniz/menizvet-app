begin;

-- ==================================================================
-- Slice 16 — Standard Appointment Duration & Guardian Requestable
-- Times (backend only).
--
-- Implements, in one forward-only migration:
--   A. clinics.standard_appointment_duration_minutes (SPEC-APT-013
--      BR-57/BR-61/BR-62).
--   B. set_clinic_standard_appointment_duration(...) management RPC
--      (SPEC-APT-013 BR-59), reusing the existing
--      assert_clinic_scheduling_authorization_after_lock(...) helper
--      unchanged.
--   C. get_requestable_appointment_start_times(...) Guardian-facing
--      read (SPEC-APT-014), following its exact three-step
--      validation ordering (structural -> uniform-empty eligibility
--      -> Clinic-relative horizon).
--   D. Two small reusable helpers for candidate generation
--      (SPEC-APT-013 BR-58): clinic_day_covered_civil_ranges(...) and
--      resolve_clinic_civil_candidate(...), plus
--      resolve_clinic_appointment_start(...) shared by (E) and (F).
--   E. request_appointment(...) forward-only breaking signature
--      change: drops Guardian-supplied end date/time/offset
--      (SPEC-APT-001 BR-29/BR-30/BR-31/BR-34).
--   F. reschedule_requested_appointment(...) forward-only breaking
--      signature change, same start-only/derived-end model
--      (SPEC-APT-004 BR-22/BR-23/BR-24).
--
-- This is Phase 1 development-only tooling with no external
-- installed client base; per explicit instruction this migration
-- performs a direct drop+recreate of both RPCs (matching the Slice 5
-- addendum's get_my_pets() precedent) rather than a versioned RPC
-- name or compatibility wrapper.
--
-- resolve_clinic_appointment_interval(...) (the existing two-endpoint
-- resolver) is deliberately left completely unchanged: it remains in
-- active use by propose_confirmed_appointment_reschedule (SPEC-APT-005,
-- out of scope for this Slice), so it must not be dropped or altered.
-- ==================================================================

-- ==================================================================
-- A. Clinic standard Appointment duration (SPEC-APT-013 BR-57/BR-61)
-- ==================================================================

alter table public.clinics
add column standard_appointment_duration_minutes integer;

alter table public.clinics
add constraint clinics_standard_appointment_duration_minutes_check
check (
    standard_appointment_duration_minutes is null
    or standard_appointment_duration_minutes between 10 and 240
);

-- ==================================================================
-- B. Management RPC (SPEC-APT-013 BR-59) — reuses the existing
--    scheduling-authorization helper unchanged; no new authorization
--    logic is introduced.
-- ==================================================================

create function public.set_clinic_standard_appointment_duration(
    p_clinic_id uuid,
    p_duration_minutes integer
)
returns uuid
language plpgsql
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

    perform public.assert_clinic_scheduling_authorization_after_lock(
        acting_user_id,
        p_clinic_id
    );

    if p_duration_minutes is not null
       and p_duration_minutes not between 10 and 240 then
        raise exception 'Clinic standard Appointment duration must be between 10 and 240 minutes'
            using errcode = '22023';
    end if;

    update public.clinics
    set standard_appointment_duration_minutes = p_duration_minutes
    where id = p_clinic_id;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.set_clinic_standard_appointment_duration(uuid, integer)
from public, anon, authenticated;

grant execute
on function public.set_clinic_standard_appointment_duration(uuid, integer)
to authenticated;

-- ==================================================================
-- D.1 Helper — maximal covered civil ranges per date (SPEC-APT-013
--     BR-58 "effective covered civil range"). This is a refactor of
--     the exact merge algorithm already inside
--     clinic_day_interval_is_covered(...): CLOSED exception excludes
--     the date entirely; an OPEN exception, if any, fully overrides
--     recurring periods for that date (BR-11); otherwise recurring
--     periods for the applicable iso_weekday are used. Overlapping or
--     touching source rows are merged into maximal ranges, exactly
--     matching the "covered_until" watermark semantics the boolean
--     helper already establishes. No new Availability business rule
--     is introduced here.
-- ==================================================================

create function public.clinic_day_covered_civil_ranges(
    p_clinic_id uuid,
    p_local_date date
)
returns table (
    range_start time,
    range_end time
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    has_closed_exception boolean;
    has_open_exception boolean;
    period_row record;
    current_start time;
    current_end time;
begin
    select exists (
        select 1
        from public.clinic_appointment_availability_exceptions as exception_record
        where exception_record.clinic_id = p_clinic_id
          and exception_record.local_date = p_local_date
          and exception_record.exception_kind = 'CLOSED'
    ) into has_closed_exception;

    if has_closed_exception then
        return;
    end if;

    select exists (
        select 1
        from public.clinic_appointment_availability_exceptions as exception_record
        where exception_record.clinic_id = p_clinic_id
          and exception_record.local_date = p_local_date
          and exception_record.exception_kind = 'OPEN'
    ) into has_open_exception;

    current_start := null;
    current_end := null;

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
            if current_start is null then
                current_start := period_row.period_start;
                current_end := period_row.period_end;
            elsif period_row.period_start > current_end then
                range_start := current_start;
                range_end := current_end;
                return next;
                current_start := period_row.period_start;
                current_end := period_row.period_end;
            elsif period_row.period_end > current_end then
                current_end := period_row.period_end;
            end if;
        end loop;
    else
        for period_row in
            select period.start_time as period_start, period.end_time as period_end
            from public.clinic_appointment_availability_periods as period
            where period.clinic_id = p_clinic_id
              and period.iso_weekday = extract(isodow from p_local_date)
            order by period.start_time
        loop
            if current_start is null then
                current_start := period_row.period_start;
                current_end := period_row.period_end;
            elsif period_row.period_start > current_end then
                range_start := current_start;
                range_end := current_end;
                return next;
                current_start := period_row.period_start;
                current_end := period_row.period_end;
            elsif period_row.period_end > current_end then
                current_end := period_row.period_end;
            end if;
        end loop;
    end if;

    if current_start is not null then
        range_start := current_start;
        range_end := current_end;
        return next;
    end if;

    return;
end;
$$;

revoke all privileges
on function public.clinic_day_covered_civil_ranges(uuid, date)
from public, anon, authenticated;

-- ==================================================================
-- D.2 Helper — resolve a bare Clinic civil (date, time) position with
--     no caller-supplied offset, distinguishing NONEXISTENT / UNIQUE /
--     AMBIGUOUS (SPEC-APT-013 BR-58). Every caller-facing resolver in
--     this domain (resolve_clinic_civil_instant) assumes the caller
--     already supplies a candidate offset to verify; candidate
--     generation has no such caller and must discover the offset(s)
--     itself.
--
--     Correctness argument: resolve_clinic_civil_instant already
--     requires |offset| <= 15:59:59. For any instant I that converts
--     to the requested civil (date, time) under some offset O(I),
--     I = anchor_instant - O(I), where anchor_instant is the civil
--     value read naively as if it were already a UTC instant.
--     Therefore every possible solution I lies within +/-16h of
--     anchor_instant, regardless of the zone's offset magnitude or
--     which local clock hour a transition falls on. Probing the
--     offset actually in effect at anchor_instant-16h and
--     anchor_instant+16h therefore correctly samples "the offset
--     immediately before" and "the offset immediately after" any
--     single transition capable of affecting this civil value — this
--     covers ordinary civil times, 1-hour and non-1-hour (e.g.
--     Australia/Lord_Howe's 30-minute) DST shifts, transitions at any
--     local clock hour including near local midnight, and exceptional
--     multi-hour historical changes (e.g. Pacific/Apia's 2011 24-hour
--     dateline jump) alike, none of which this window's derivation
--     depends on. It does not independently prove correctness for a
--     hypothetical zone with two or more distinct offset segments
--     inside one 32-hour window; no such case is known to exist in
--     the IANA database, and none was found while validating this
--     function, but it is called out here rather than left implicit.
--     An earlier version of this function anchored its probes to
--     neighboring calendar dates rather than to the civil value
--     itself, which does not carry this guarantee and was replaced.
--
--     The actual correctness test is always delegated to the existing
--     resolve_clinic_civil_instant(...) round-trip check — no new DST
--     rule is introduced.
-- ==================================================================

create function public.resolve_clinic_civil_candidate(
    p_timezone_name text,
    p_local_date date,
    p_local_time time,
    out resolution_kind text,
    out resolved_instant timestamptz,
    out resolved_utc_offset_seconds integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    anchor_instant timestamptz;
    probe_before timestamptz;
    probe_after timestamptz;
    offset_before integer;
    offset_after integer;
    instant_before timestamptz;
    instant_after timestamptz;
    found_before boolean := false;
    found_after boolean := false;
begin
    anchor_instant := (p_local_date::timestamp + p_local_time) at time zone 'UTC';
    probe_before := anchor_instant - interval '16 hours';
    probe_after  := anchor_instant + interval '16 hours';

    offset_before := extract(epoch from (
        (probe_before at time zone p_timezone_name) - (probe_before at time zone 'UTC')
    ))::integer;
    offset_after := extract(epoch from (
        (probe_after at time zone p_timezone_name) - (probe_after at time zone 'UTC')
    ))::integer;

    begin
        instant_before := public.resolve_clinic_civil_instant(
            p_timezone_name, p_local_date, p_local_time, offset_before
        );
        found_before := true;
    exception when sqlstate '22007' then
        found_before := false;
    end;

    if offset_after = offset_before then
        found_after := false;
    else
        begin
            instant_after := public.resolve_clinic_civil_instant(
                p_timezone_name, p_local_date, p_local_time, offset_after
            );
            found_after := true;
        exception when sqlstate '22007' then
            found_after := false;
        end;
    end if;

    if found_before and found_after and instant_before is distinct from instant_after then
        resolution_kind := 'AMBIGUOUS';
        return;
    end if;

    if found_before then
        resolution_kind := 'UNIQUE';
        resolved_instant := instant_before;
        resolved_utc_offset_seconds := offset_before;
        return;
    end if;

    if found_after then
        resolution_kind := 'UNIQUE';
        resolved_instant := instant_after;
        resolved_utc_offset_seconds := offset_after;
        return;
    end if;

    resolution_kind := 'NONEXISTENT';
    return;
end;
$$;

revoke all privileges
on function public.resolve_clinic_civil_candidate(text, date, time)
from public, anon, authenticated;

-- ==================================================================
-- D.3 Helper — resolve a single Guardian-supplied civil start to an
--     instant, shared by request_appointment and
--     reschedule_requested_appointment (E, F). Mirrors exactly the
--     validity-check-then-resolve shape of the existing
--     resolve_clinic_appointment_interval(...), narrowed to one
--     endpoint. resolve_clinic_appointment_interval(...) itself is
--     unchanged and remains in use by
--     propose_confirmed_appointment_reschedule (SPEC-APT-005).
-- ==================================================================

create function public.resolve_clinic_appointment_start(
    p_clinic_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer
)
returns table (
    resolved_start_at timestamptz,
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

    return query
    select computed_start_at, clinic_timezone_name;
end;
$$;

revoke all privileges
on function public.resolve_clinic_appointment_start(uuid, date, time, integer)
from public, anon, authenticated;

-- ==================================================================
-- C. Guardian-facing candidate read (SPEC-APT-014). Authenticated
--    only (no anon grant, no account-verification or Guardianship
--    precondition — SPEC-APT-014 BR-1). Validation ordering follows
--    BR-19 exactly: (1) structural checks with zero Clinic state, so
--    they behave identically for a real or fabricated clinic_id;
--    (2) a single eligibility lookup whose WHERE clause naturally
--    yields "not found" for every uniform-empty reason
--    indistinguishably (nonexistent, unpublished, no duration, no
--    Entitlement, invalid timezone) — mirroring exactly how
--    get_published_clinic_location already returns zero rows for
--    both nonexistent and unpublished Clinics; (3) the Clinic-relative
--    horizon check, reachable only once eligibility already
--    succeeded, whose failure returns the same empty result rather
--    than a distinguishable error.
-- ==================================================================

create function public.get_requestable_appointment_start_times(
    p_clinic_id uuid,
    p_start_date date,
    p_end_date date
)
returns table (
    candidate_local_date date,
    candidate_local_time time,
    utc_offset_seconds integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    clinic_timezone_name text;
    clinic_duration_minutes integer;
    current_local_date date;
    iter_date date;
    range_row record;
    range_start_minutes integer;
    range_end_minutes integer;
    candidate_start_minutes integer;
    candidate_local_time_value time;
    candidate_resolution record;
    candidate_end_instant timestamptz;
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

    -- 1. Structural validation (SPEC-APT-014 BR-10) — no Clinic state
    --    is consulted; identical for a real or nonexistent clinic_id.
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

    -- 2. Uniform-empty Clinic eligibility (SPEC-APT-014 BR-2/BR-3/BR-4/
    --    BR-5). A single lookup: any ineligible reason simply fails to
    --    match, with no distinguishable branch for "why".
    select clinic.scheduling_timezone_name, clinic.standard_appointment_duration_minutes
    into clinic_timezone_name, clinic_duration_minutes
    from public.clinics as clinic
    join public.veterinary_organizations as organization
      on organization.id = clinic.organization_id
    where clinic.id = p_clinic_id
      and clinic.is_published = true
      and clinic.standard_appointment_duration_minutes is not null
      and public.clinic_timezone_name_is_valid(clinic.scheduling_timezone_name)
      and public.organization_has_professional_entitlement(
          organization.id, 'APPOINTMENT_MANAGEMENT'
      );

    if not found then
        return;
    end if;

    -- 3. Clinic-relative horizon (SPEC-APT-014 BR-11), reachable only
    --    for an eligible Clinic. Failure returns the same empty
    --    result, never a distinguishable rejection (BR-19 step 3).
    operation_timestamp := clock_timestamp();
    current_local_date := (operation_timestamp at time zone clinic_timezone_name)::date;

    if p_start_date < current_local_date
       or p_end_date > current_local_date + 60 then
        return;
    end if;

    -- 4. Candidate generation (SPEC-APT-013 BR-58). Minutes-since-
    --    midnight integer arithmetic is used for all civil-time-of-day
    --    stepping to avoid `time` wraparound at/near the 24:00:00
    --    end-of-day sentinel already accepted elsewhere in this
    --    domain (parse_clinic_local_time).
    iter_date := p_start_date;
    while iter_date <= p_end_date loop
        for range_row in
            select covered.range_start, covered.range_end
            from public.clinic_day_covered_civil_ranges(p_clinic_id, iter_date) as covered
        loop
            range_start_minutes := extract(
                epoch from (range_row.range_start - time '00:00:00')
            )::integer / 60;
            range_end_minutes := extract(
                epoch from (range_row.range_end - time '00:00:00')
            )::integer / 60;

            candidate_start_minutes := range_start_minutes;

            while candidate_start_minutes + clinic_duration_minutes <= range_end_minutes loop
                candidate_local_time_value :=
                    time '00:00:00' + (candidate_start_minutes * interval '1 minute');

                select *
                into candidate_resolution
                from public.resolve_clinic_civil_candidate(
                    clinic_timezone_name, iter_date, candidate_local_time_value
                );

                if candidate_resolution.resolution_kind = 'UNIQUE'
                   and candidate_resolution.resolved_instant > operation_timestamp then
                    candidate_end_instant := candidate_resolution.resolved_instant
                        + (clinic_duration_minutes * interval '1 minute');

                    if public.clinic_appointment_interval_is_available(
                        p_clinic_id,
                        candidate_resolution.resolved_instant,
                        candidate_end_instant
                    ) then
                        candidate_local_date := iter_date;
                        candidate_local_time := candidate_local_time_value;
                        utc_offset_seconds := candidate_resolution.resolved_utc_offset_seconds;
                        return next;
                    end if;
                end if;

                -- Cadence is always anchored to range_start_minutes and
                -- whole multiples of the standard duration; an omitted
                -- (nonexistent/ambiguous/unavailable) candidate never
                -- shifts this position (SPEC-APT-013 BR-58).
                candidate_start_minutes := candidate_start_minutes + clinic_duration_minutes;
            end loop;
        end loop;

        iter_date := iter_date + 1;
    end loop;

    return;
end;
$$;

revoke all privileges
on function public.get_requestable_appointment_start_times(uuid, date, date)
from public, anon, authenticated;

grant execute
on function public.get_requestable_appointment_start_times(uuid, date, date)
to authenticated;

-- ==================================================================
-- E. request_appointment(...) — forward-only breaking signature
--    change (SPEC-APT-001 BR-29/BR-30/BR-31/BR-32/BR-33/BR-34).
--    Drops p_end_local_date/p_end_local_time/p_end_utc_offset_seconds.
--    Every other existing rule (authentication, email verification,
--    the Guardianship disclosure pre-check ordered strictly before
--    Entitlement evaluation, APPOINTMENT_MANAGEMENT, publication,
--    reason/notes normalization, atomic Appointment + Schedule
--    Revision + Care Authorization creation) is preserved unchanged
--    in position and behavior; only the end-time source changes.
-- ==================================================================

drop function public.request_appointment(
    uuid, uuid, date, time, integer, date, time, integer, text, text
);

create function public.request_appointment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_reason_for_visit text,
    p_guardian_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    clinic_is_published boolean;
    clinic_duration_minutes integer;
    guardianship_record public.guardianships%rowtype;
    resolved_start record;
    resolved_end_at timestamptz;
    normalized_reason text;
    normalized_notes text;
    operation_timestamp timestamptz;
    created_appointment_id uuid;
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
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = acting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The acting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    -- Disclosure pre-check: unchanged from the prior contract
    -- (SPEC-APT-001 BR-34) — proves Guardian domain authority for the
    -- exact Pet before any Organization/Clinic lock is taken or
    -- Entitlement/publication/duration state is evaluated, so a User
    -- without Guardianship cannot learn any of that state through this
    -- operation's error ordering.
    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    target_organization_id := public.assert_clinic_organization_entitlement_after_lock(
        p_clinic_id, 'APPOINTMENT_MANAGEMENT'
    );

    select clinic.is_published, clinic.standard_appointment_duration_minutes
    into clinic_is_published, clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not coalesce(clinic_is_published, false) then
        raise exception 'Appointment requests require a published Clinic'
            using errcode = '23514';
    end if;

    -- SPEC-APT-001 BR-31: an additional necessary condition alongside
    -- publication/Entitlement above; it does not reorder them.
    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    -- Authoritative, locked revalidation of the exact current
    -- Guardianship row, after Organization -> Clinic locking.
    select guardianship.*
    into guardianship_record
    from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;

    if not found then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    normalized_reason := btrim(p_reason_for_visit, E' \t\n\r\f\013');

    if normalized_reason is null or normalized_reason = '' then
        raise exception 'Appointment request requires a reason for visit'
            using errcode = '22023';
    end if;

    normalized_notes := case
        when p_guardian_notes is null then null
        else btrim(p_guardian_notes, E' \t\n\r\f\013')
    end;

    if normalized_notes = '' then
        raise exception 'Guardian notes must not be blank when supplied'
            using errcode = '22023';
    end if;

    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        p_clinic_id, p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    operation_timestamp := clock_timestamp();

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Requested Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- SPEC-APT-001 BR-30: end is derived as real elapsed time from the
    -- resolved start instant, never by independently deriving and
    -- resolving a second civil end.
    resolved_end_at := resolved_start.resolved_start_at
        + (clinic_duration_minutes * interval '1 minute');

    if not public.clinic_appointment_interval_is_available(
        p_clinic_id,
        resolved_start.resolved_start_at,
        resolved_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the requested interval'
            using errcode = '23514';
    end if;

    insert into public.appointments (
        pet_id, clinic_id, requesting_user_id, reason_for_visit, guardian_notes,
        lifecycle_state, created_at
    )
    values (
        p_pet_id, p_clinic_id, acting_user_id, normalized_reason, normalized_notes,
        'REQUESTED', operation_timestamp
    )
    returning id into created_appointment_id;

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        created_appointment_id, 1, 'REQUESTED',
        resolved_start.resolved_start_at, resolved_end_at,
        resolved_start.timezone_name, acting_user_id, null, operation_timestamp
    );

    insert into public.care_authorizations (
        pet_id, clinic_id, organization_id, granting_guardianship_id,
        granted_at, purpose, appointment_id, lifecycle_state
    )
    values (
        p_pet_id, p_clinic_id, target_organization_id, guardianship_record.id,
        operation_timestamp, 'APPOINTMENT_CARE', created_appointment_id, 'ACTIVE'
    );

    return created_appointment_id;
end;
$$;

revoke all privileges
on function public.request_appointment(
    uuid, uuid, date, time, integer, text, text
)
from public, anon, authenticated;

grant execute
on function public.request_appointment(
    uuid, uuid, date, time, integer, text, text
)
to authenticated;

-- ==================================================================
-- F. reschedule_requested_appointment(...) — forward-only breaking
--    signature change (SPEC-APT-004 BR-22/BR-23/BR-24). Drops
--    p_end_local_date/p_end_local_time/p_end_utc_offset_seconds.
--    REQUESTED-only restriction, current authorization/locking order,
--    Veterinarian Assignment revalidation, and the full-interval
--    no-op comparison are all preserved unchanged; only the end-time
--    source changes. The pre-existing REQUESTED-state check ordering
--    relative to the Guardianship check is intentionally left exactly
--    as it already was — unrelated to this Slice's scope.
-- ==================================================================

drop function public.reschedule_requested_appointment(
    uuid, date, time, integer, date, time, integer
);

create function public.reschedule_requested_appointment(
    p_appointment_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
    clinic_duration_minutes integer;
    appointment_record public.appointments%rowtype;
    latest_requested_revision public.appointment_schedule_revisions%rowtype;
    current_assignment_record public.appointment_veterinarian_assignments%rowtype;
    resolved_start record;
    resolved_end_at timestamptz;
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

    -- Resolve the immutable Appointment -> Clinic identity without a
    -- write lock, then use Clinic as the scheduling-configuration
    -- serialization boundary. Guardian rescheduling intentionally
    -- acquires no Organization or Entitlement lock (unchanged).
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
    -- Appointment serialization point (unchanged ordering).
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

    -- SPEC-APT-004 BR-24: an additional necessary condition alongside
    -- the existing REQUESTED-state/Guardianship preconditions above;
    -- it does not reorder them.
    select clinic.standard_appointment_duration_minutes
    into clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id;

    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
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

    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        resolved_clinic_id, p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Rescheduled Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- SPEC-APT-004 BR-23: current standard duration, as real elapsed
    -- time — not necessarily the duration that produced the previous
    -- revision.
    resolved_end_at := resolved_start.resolved_start_at
        + (clinic_duration_minutes * interval '1 minute');

    -- SPEC-APT-004 BR-19 (revised): "the same effective requested time"
    -- means the same full resolved interval, so a same-start
    -- resubmission after a duration change is correctly NOT a no-op.
    if resolved_start.resolved_start_at = latest_requested_revision.scheduled_start_at
       and resolved_end_at = latest_requested_revision.scheduled_end_at then
        raise exception 'Rescheduled time must differ from the current requested time'
            using errcode = '22023';
    end if;

    if not public.clinic_appointment_interval_is_available(
        resolved_clinic_id,
        resolved_start.resolved_start_at,
        resolved_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the new requested interval'
            using errcode = '23514';
    end if;

    -- Re-evaluate any existing current Assignment against the NEW
    -- requested interval before committing to it (unchanged).
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
            resolved_start.resolved_start_at, resolved_end_at
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
        resolved_start.resolved_start_at, resolved_end_at,
        resolved_start.timezone_name, acting_user_id, null, operation_timestamp
    );

    return p_appointment_id;
end;
$$;

revoke all privileges
on function public.reschedule_requested_appointment(uuid, date, time, integer)
from public, anon, authenticated;

grant execute
on function public.reschedule_requested_appointment(uuid, date, time, integer)
to authenticated;

commit;

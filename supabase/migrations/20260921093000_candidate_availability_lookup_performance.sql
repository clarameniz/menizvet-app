begin;

-- ==================================================================
-- Slice 16 performance correction — get_requestable_appointment_start_times
-- statement-timeout investigation (backend only, no product/behavior
-- change).
--
-- Measured root cause (local profiling against the Valverde fixture:
-- Europe/Madrid, 30-minute standard duration, 09:00-14:00 and
-- 16:00-20:00 Mon-Fri, 30-Clinic-local-day window, 395 candidates):
--
--   clinic_appointment_interval_is_available(...) is invoked once per
--   generated candidate by get_requestable_appointment_start_times(...).
--   On every single invocation it re-fetches the Clinic's scheduling
--   timezone name and re-validates it via clinic_timezone_name_is_valid(...),
--   which checks membership against pg_catalog.pg_timezone_names — a
--   set-returning system view with no usable index that recomputes the
--   current UTC offset for every IANA zone (~1200+ rows) on every call.
--   Measured cost: ~23ms per call, versus ~0.03ms for the actual
--   Availability-coverage check (clinic_day_interval_is_covered) it
--   guards. For 395 candidates this alone accounts for ~9.1s of the
--   measured ~9.2s total RPC runtime (EXPLAIN (ANALYZE, BUFFERS)),
--   comfortably explaining the 57014 "canceling statement due to
--   statement timeout" failures observed from the mobile client/
--   PostgREST while the same query completes in the SQL Editor (whose
--   session may use a different/no statement_timeout).
--
--   get_requestable_appointment_start_times(...) already resolves and
--   validates the Clinic's scheduling timezone exactly once, at its
--   uniform-empty eligibility step, before generating any candidate.
--   That value cannot change during the remainder of the call (the
--   whole RPC executes as a single top-level statement under one
--   MVCC snapshot), so re-fetching and re-validating it again for
--   every candidate is provably redundant work, not a correctness
--   requirement.
--
-- Fix: extract the existing segment-walking Availability-coverage loop
-- out of clinic_appointment_interval_is_available(...) into a new
-- internal helper, clinic_interval_is_covered_by_timezone(...), that
-- accepts an already-known-valid Clinic timezone name instead of
-- re-deriving it. clinic_appointment_interval_is_available(...) keeps
-- its exact existing signature and behavior (still independently
-- fetches and validates the Clinic's timezone itself) and simply
-- delegates to the new helper — every other caller
-- (request_appointment, reschedule_requested_appointment, the Slice 16
-- test suite, any direct caller) observes byte-identical behavior,
-- because the Availability-coverage logic itself is untouched, merely
-- relocated. get_requestable_appointment_start_times(...) is the only
-- caller changed to call the new helper directly with its
-- already-validated clinic_timezone_name, skipping the redundant
-- fetch + pg_timezone_names scan on every candidate.
--
-- No Availability semantics, capacity model, DST/civil-time rule, or
-- disclosure/eligibility ordering is changed. No new persisted or
-- materialized state is introduced. This is a forward-only correction
-- via CREATE OR REPLACE FUNCTION; the already-deployed migration
-- 20260920120000_standard_appointment_duration_and_candidate_times.sql
-- is left untouched.
-- ==================================================================

-- ==================================================================
-- New internal helper — identical Availability-coverage logic to the
-- segment-walking loop previously inlined in
-- clinic_appointment_interval_is_available(...), parameterized by an
-- already-resolved-and-validated Clinic timezone name so a repeat
-- caller (candidate generation) never re-pays the Clinic lookup or the
-- pg_timezone_names validation for a value it already knows is
-- current and valid for this call. Never granted to public/anon/
-- authenticated -- callable only from other SECURITY DEFINER functions
-- owned by the same privileged role, exactly like the existing
-- clinic_day_interval_is_covered(...) helper it delegates to.
-- ==================================================================

create function public.clinic_interval_is_covered_by_timezone(
    p_clinic_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_clinic_timezone_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    local_start timestamp;
    local_end timestamp;
    segment_cursor timestamp;
    segment_date date;
    next_midnight timestamp;
    segment_end timestamp;
    segment_start_time time;
    segment_end_time time;
begin
    local_start := p_start_at at time zone p_clinic_timezone_name;
    local_end := p_end_at at time zone p_clinic_timezone_name;

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
on function public.clinic_interval_is_covered_by_timezone(uuid, timestamptz, timestamptz, text)
from public, anon, authenticated;

-- ==================================================================
-- clinic_appointment_interval_is_available(...) — unchanged signature
-- and unchanged externally observable behavior (still independently
-- fetches and validates the Clinic's current scheduling timezone, still
-- returns false for a nonexistent Clinic or an invalid timezone). Its
-- body now delegates the actual segment-walking coverage check to the
-- shared helper above instead of inlining it, so behavior for every
-- existing caller is byte-identical.
-- ==================================================================

create or replace function public.clinic_appointment_interval_is_available(
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
begin
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        return false;
    end if;

    return public.clinic_interval_is_covered_by_timezone(
        p_clinic_id, p_start_at, p_end_at, clinic_timezone_name
    );
end;
$$;

-- ==================================================================
-- get_requestable_appointment_start_times(...) — unchanged signature,
-- unchanged validation ordering (BR-19), unchanged candidate-generation
-- rules (SPEC-APT-013 BR-58). The only change is the per-candidate
-- Availability check now calls the new helper directly with the
-- clinic_timezone_name already resolved and validated at the
-- eligibility step above, instead of clinic_appointment_interval_is_available(...)
-- re-deriving and re-validating it once per candidate.
-- ==================================================================

create or replace function public.get_requestable_appointment_start_times(
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

                    -- Timezone already resolved and validated in step 2
                    -- above and provably invariant for the remainder of
                    -- this call (single top-level statement, one MVCC
                    -- snapshot): calls the shared coverage helper
                    -- directly instead of clinic_appointment_interval_is_available(...),
                    -- which would otherwise redundantly re-fetch and
                    -- re-validate it against pg_catalog.pg_timezone_names
                    -- on every candidate.
                    if public.clinic_interval_is_covered_by_timezone(
                        p_clinic_id,
                        candidate_resolution.resolved_instant,
                        candidate_end_instant,
                        clinic_timezone_name
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

commit;

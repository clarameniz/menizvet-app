-- Guardian candidate grid anchored at the covered range's exact civil start
-- (SPEC-APT-013 BR-58, SPEC-APT-014 BR-6).
--
-- Forward-only correction of get_requestable_appointment_start_times
-- (last defined in 20260921093000_candidate_availability_lookup_performance.sql).
--
-- BR-58 lays candidate positions out at "the range's own local civil start
-- plus whole multiples of the standard duration". Availability is stored as
-- time(6) and the write RPCs accept second and microsecond precision, but this
-- read converted each covered range to whole minutes
-- (extract(epoch)::integer / 60, which rounds the epoch and then truncates the
-- minutes). For a range starting at 09:00:30 it anchored the grid at 09:00:
-- the 09:00 position failed Availability and was dropped, and every later
-- position (09:30, 10:00, …) was off the range's grid. The Professional
-- candidate reads (appointment_reschedule_candidate_positions) already step
-- in whole microseconds from the exact range start, so the Guardian and the
-- Professional reads offered different instants for the same Availability.
--
-- The grid now steps in whole microseconds from the exact range start and
-- end, exactly as appointment_reschedule_candidate_positions does. For
-- whole-minute Availability (everything the mobile editor writes) the
-- positions, and therefore the output, are identical to before.
--
-- Unchanged: signature, result columns, attributes, ACL, validation order
-- (BR-19), uniform-empty eligibility, the Clinic-relative horizon, civil-time
-- resolution, and the per-candidate Availability evaluation.

begin;

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
    duration_microseconds bigint;
    current_local_date date;
    iter_date date;
    range_row record;
    range_start_microseconds bigint;
    range_end_microseconds bigint;
    position_microseconds bigint;
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

    -- 4. Candidate generation (SPEC-APT-013 BR-58). Positions are the
    --    covered range's exact civil start plus whole multiples of the
    --    standard duration, in whole microseconds since local midnight (as
    --    in appointment_reschedule_candidate_positions), so a time(6) range
    --    start is never rounded and the 24:00:00 end sentinel never wraps.
    duration_microseconds := clinic_duration_minutes::bigint * 60000000;

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

            while position_microseconds + duration_microseconds <= range_end_microseconds loop
                candidate_local_time_value := time '00:00:00'
                    + position_microseconds * interval '1 microsecond';

                select *
                into candidate_resolution
                from public.resolve_clinic_civil_candidate(
                    clinic_timezone_name, iter_date, candidate_local_time_value
                );

                if candidate_resolution.resolution_kind = 'UNIQUE'
                   and candidate_resolution.resolved_instant > operation_timestamp then
                    candidate_end_instant := candidate_resolution.resolved_instant
                        + duration_microseconds * interval '1 microsecond';

                    -- The timezone was resolved and validated in step 2 and
                    -- cannot change within this call.
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

                -- An omitted (nonexistent/ambiguous/unavailable) position
                -- never shifts the grid (SPEC-APT-013 BR-58).
                position_microseconds := position_microseconds + duration_microseconds;
            end loop;
        end loop;

        iter_date := iter_date + 1;
    end loop;

    return;
end;
$$;

commit;

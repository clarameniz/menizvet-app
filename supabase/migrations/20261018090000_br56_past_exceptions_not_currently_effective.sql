-- BR-56: past Appointment Availability exceptions are not currently effective
-- (SPEC-APT-013 BR-56, Verification Note 39; SPEC-SUB-003 defers to BR-56).
--
-- Forward-only. set_clinic_scheduling_timezone (last defined in
-- 20260826140000_scheduling_configuration.sql) required PROFESSIONAL_SCHEDULING
-- whenever the Clinic had ANY Clinic exception, or any Veterinarian exception
-- of a currently valid Assignment, however old. A past exception cannot affect
-- prospective scheduling, and it cannot be cleared without the same
-- Entitlement, so it locked the timezone indefinitely.
--
-- Now an exception counts unless it is past: its local date is before the
-- Clinic-local current date under BOTH the Clinic's current scheduling
-- timezone and the requested timezone (a change can cross the date line, so
-- a date already past under one may be today under the other). An exception
-- for today under either counts. If the current timezone is not valid, every
-- exception counts (fail closed). Recurring periods always count; Veterinarian
-- Availability still counts only for a currently valid Assignment.
--
-- Intentional order change: the requested timezone is validated (22023)
-- before the gate (42501), because the gate needs its local date. Both still
-- run after the CLINIC_MANAGE_OPENING_HOURS capability under the existing
-- Organization -> Clinic lock.
--
-- Unchanged: signature, ACL, capability, locking, normalization, the denial
-- message, and the structural timezone dependency
-- (assert_clinic_timezone_dependency): past exceptions stay stored and still
-- require a valid scheduling timezone. No table or data change.

begin;

create or replace function public.set_clinic_scheduling_timezone(
    p_clinic_id uuid,
    p_timezone_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    normalized_timezone_name text;
    clinic_organization_id uuid;
    current_timezone_name text;
    operation_timestamp timestamptz;
    earliest_current_local_date date;
    availability_is_currently_effective boolean;
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

    perform public.assert_clinic_capability_after_lock(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_OPENING_HOURS'
    );

    normalized_timezone_name := btrim(
        p_timezone_name,
        E' \t\n\r\f\013'
    );

    if not public.clinic_timezone_name_is_valid(
        normalized_timezone_name
    ) then
        raise exception 'Clinic scheduling timezone must be a valid named timezone'
            using errcode = '22023';
    end if;

    select clinic.organization_id, clinic.scheduling_timezone_name
    into clinic_organization_id, current_timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    -- An exception is past only when its local date is before the current
    -- local date under both timezones; NULL (current timezone not valid)
    -- makes every exception count.
    operation_timestamp := clock_timestamp();

    if public.clinic_timezone_name_is_valid(current_timezone_name) then
        earliest_current_local_date := least(
            (operation_timestamp at time zone current_timezone_name)::date,
            (operation_timestamp at time zone normalized_timezone_name)::date
        );
    end if;

    availability_is_currently_effective := (
        exists (
            select 1
            from public.clinic_appointment_availability_periods as period
            where period.clinic_id = p_clinic_id
        )
        or exists (
            select 1
            from public.clinic_appointment_availability_exceptions as exception_record
            where exception_record.clinic_id = p_clinic_id
              and (earliest_current_local_date is null
                   or exception_record.local_date >= earliest_current_local_date)
        )
        or exists (
            select 1
            from public.veterinarian_availability_periods as period
            join public.veterinarian_clinic_assignments as assignment
              on assignment.id = period.veterinarian_clinic_assignment_id
            where assignment.clinic_id = p_clinic_id
              and public.veterinarian_clinic_assignment_is_current(assignment.id)
        )
        or exists (
            select 1
            from public.veterinarian_availability_exceptions as exception_record
            join public.veterinarian_clinic_assignments as assignment
              on assignment.id = exception_record.veterinarian_clinic_assignment_id
            where assignment.clinic_id = p_clinic_id
              and public.veterinarian_clinic_assignment_is_current(assignment.id)
              and (earliest_current_local_date is null
                   or exception_record.local_date >= earliest_current_local_date)
        )
    );

    if availability_is_currently_effective
       and not public.organization_has_professional_entitlement(
           clinic_organization_id,
           'PROFESSIONAL_SCHEDULING'
       ) then
        raise exception 'Professional scheduling Entitlement is required to change scheduling timezone while Appointment Availability is currently effective'
            using errcode = '42501';
    end if;

    update public.clinics
    set scheduling_timezone_name = normalized_timezone_name
    where id = p_clinic_id;

    return p_clinic_id;
end;
$$;

commit;

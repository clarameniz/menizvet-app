-- Professional management reads without write locking.
--
-- The four read-only Professional management RPCs
--
--   get_managed_clinic_appointment_availability(uuid)   APPOINTMENT_MANAGE_AVAILABILITY
--   get_managed_clinic_opening_hours(uuid)              CLINIC_MANAGE_OPENING_HOURS
--   get_managed_clinic_service_offerings(uuid)          CLINIC_MANAGE_SERVICES
--   get_managed_veterinarian_availability(uuid)         APPOINTMENT_MANAGE_AVAILABILITY
--                                                       (of the Assignment's Clinic)
--
-- authorized through assert_clinic_capability_after_lock(...), which takes
-- Organization -> Clinic FOR UPDATE row locks. A read decides nothing under
-- those locks, so they only made management reads queue behind (and block)
-- every configuration write in the same Organization. Each read now
-- authorizes with the same non-locking predicate the Clinic Appointment
-- schedule read uses, user_has_clinic_capability(...), and is STABLE: the
-- whole read, authorization included, sees one snapshot.
--
-- Unchanged, deliberately:
--   - the capability each read requires, its Clinic scoping, and the
--     responsibility semantics behind it (the same predicate the locking
--     helper evaluated after its locks);
--   - no Entitlement and no publication requirement;
--   - every payload: columns, members, values, and ordering. The
--     Veterinarian read still returns the Availability of the requested
--     Assignment, current or ended, with its Clinic's timezone;
--   - SECURITY DEFINER, empty search_path, and the authenticated-only ACL;
--   - assert_clinic_capability_after_lock(...) and every write RPC, which
--     keep their Organization -> Clinic locking.
--
-- Changed, deliberately (fail closed, no existence disclosure): an unknown
-- Clinic, or an unknown Veterinarian Clinic Assignment, is now reported
-- exactly like an inaccessible one — SQLSTATE 42501 "Applicable
-- Clinic-management capability is required" — instead of 23503. Previously
-- any authenticated caller could tell an existing Clinic or Assignment from
-- a nonexistent one, and the Veterinarian read did so before any
-- authorization. No consumer relies on the distinction (the mobile client
-- maps 42501 and 23503 to the same access-denied state).
--
-- Signatures and result types are unchanged, so the functions are replaced
-- in place. No table, column, constraint, index, write RPC, or data is
-- changed.

begin;

create or replace function public.get_managed_clinic_appointment_availability(
    p_clinic_id uuid
)
returns table (
    scheduling_timezone_name text,
    standard_appointment_duration_minutes integer,
    recurring_periods jsonb,
    exceptions jsonb
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

    -- False for an unknown Clinic as for an inaccessible one.
    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'APPOINTMENT_MANAGE_AVAILABILITY'
    ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        clinic.scheduling_timezone_name,
        clinic.standard_appointment_duration_minutes,
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'iso_weekday', period.iso_weekday,
                        'start_time', period.start_time,
                        'end_time', period.end_time
                    )
                    order by
                        period.iso_weekday,
                        period.start_time,
                        period.end_time
                )
                from public.clinic_appointment_availability_periods as period
                where period.clinic_id = clinic.id
            ),
            '[]'::jsonb
        ),
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'local_date', exception_record.local_date,
                        'exception_kind', exception_record.exception_kind,
                        'start_time', exception_record.start_time,
                        'end_time', exception_record.end_time
                    )
                    order by
                        exception_record.local_date,
                        exception_record.exception_kind,
                        exception_record.start_time,
                        exception_record.end_time
                )
                from public.clinic_appointment_availability_exceptions as exception_record
                where exception_record.clinic_id = clinic.id
            ),
            '[]'::jsonb
        )
    from public.clinics as clinic
    where clinic.id = p_clinic_id;
end;
$$;

revoke all privileges
on function public.get_managed_clinic_appointment_availability(uuid)
from public, anon, authenticated;

grant execute
on function public.get_managed_clinic_appointment_availability(uuid)
to authenticated;

create or replace function public.get_managed_clinic_opening_hours(
    p_clinic_id uuid
)
returns table (
    scheduling_timezone_name text,
    recurring_periods jsonb,
    exceptions jsonb
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

    -- False for an unknown Clinic as for an inaccessible one.
    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_OPENING_HOURS'
    ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        clinic.scheduling_timezone_name,
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'iso_weekday', period.iso_weekday,
                        'start_time', period.start_time,
                        'end_time', period.end_time
                    )
                    order by
                        period.iso_weekday,
                        period.start_time,
                        period.end_time
                )
                from public.clinic_opening_periods as period
                where period.clinic_id = clinic.id
            ),
            '[]'::jsonb
        ),
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'local_date', exception_record.local_date,
                        'exception_kind', exception_record.exception_kind,
                        'start_time', exception_record.start_time,
                        'end_time', exception_record.end_time
                    )
                    order by
                        exception_record.local_date,
                        exception_record.exception_kind,
                        exception_record.start_time,
                        exception_record.end_time
                )
                from public.clinic_opening_exceptions as exception_record
                where exception_record.clinic_id = clinic.id
            ),
            '[]'::jsonb
        )
    from public.clinics as clinic
    where clinic.id = p_clinic_id;
end;
$$;

revoke all privileges
on function public.get_managed_clinic_opening_hours(uuid)
from public, anon, authenticated;

grant execute
on function public.get_managed_clinic_opening_hours(uuid)
to authenticated;

create or replace function public.get_managed_clinic_service_offerings(
    p_clinic_id uuid
)
returns table (
    service_category text,
    public_description text
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

    -- False for an unknown Clinic as for an inaccessible one.
    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_SERVICES'
    ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        offering.service_category,
        offering.public_description
    from public.clinic_service_offerings as offering
    where offering.clinic_id = p_clinic_id
    order by offering.service_category;
end;
$$;

revoke all privileges
on function public.get_managed_clinic_service_offerings(uuid)
from public, anon, authenticated;

grant execute
on function public.get_managed_clinic_service_offerings(uuid)
to authenticated;

create or replace function public.get_managed_veterinarian_availability(
    p_veterinarian_clinic_assignment_id uuid
)
returns table (
    scheduling_timezone_name text,
    recurring_periods jsonb,
    exceptions jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
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

    select assignment.clinic_id
    into resolved_clinic_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id;

    -- An unknown Assignment fails exactly like an inaccessible one; the
    -- capability is evaluated for the Assignment's own Clinic.
    if resolved_clinic_id is null
       or not public.user_has_clinic_capability(
           acting_user_id,
           resolved_clinic_id,
           'APPOINTMENT_MANAGE_AVAILABILITY'
       ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        clinic.scheduling_timezone_name,
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'iso_weekday', period.iso_weekday,
                        'start_time', period.start_time,
                        'end_time', period.end_time
                    )
                    order by
                        period.iso_weekday,
                        period.start_time,
                        period.end_time
                )
                from public.veterinarian_availability_periods as period
                where period.veterinarian_clinic_assignment_id
                          = p_veterinarian_clinic_assignment_id
            ),
            '[]'::jsonb
        ),
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'local_date', exception_record.local_date,
                        'exception_kind', exception_record.exception_kind,
                        'start_time', exception_record.start_time,
                        'end_time', exception_record.end_time
                    )
                    order by
                        exception_record.local_date,
                        exception_record.exception_kind,
                        exception_record.start_time,
                        exception_record.end_time
                )
                from public.veterinarian_availability_exceptions as exception_record
                where exception_record.veterinarian_clinic_assignment_id
                          = p_veterinarian_clinic_assignment_id
            ),
            '[]'::jsonb
        )
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id;
end;
$$;

revoke all privileges
on function public.get_managed_veterinarian_availability(uuid)
from public, anon, authenticated;

grant execute
on function public.get_managed_veterinarian_availability(uuid)
to authenticated;

commit;

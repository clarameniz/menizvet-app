-- Clinic Appointment Hours — professional management read (SPEC-APT-013
-- BR-74).
--
-- Extends the existing professional management read
-- `get_managed_clinic_appointment_availability(uuid)` so that it exposes the
-- Clinic's complete current Appointment-scheduling configuration needed by
-- the professional mobile "Appointment hours" surface:
--
--   scheduling_timezone_name               text    (may be NULL)
--   standard_appointment_duration_minutes  integer (may be NULL, BR-62)
--   recurring_periods                      jsonb
--   exceptions                             jsonb
--
-- Adding an output column changes the function's result type, which
-- CREATE OR REPLACE cannot do, so the function is dropped and recreated with
-- the same name, argument, attributes, and ACL. It has no committed client
-- consumer, and no compatibility overload is kept (as in earlier forward-only
-- read changes).
--
-- Unchanged, deliberately:
--   - authorization: current APPOINTMENT_MANAGE_AVAILABILITY capability for
--     the Clinic, through assert_clinic_capability_after_lock(...), including
--     its existing Organization -> Clinic row locking;
--   - no PROFESSIONAL_SCHEDULING Entitlement and no publication requirement
--     (SPEC-SUB-003: understanding existing configuration is not new paid
--     scheduling activity);
--   - recurring_periods and exceptions: same members, values, and ordering;
--     every stored exception is returned, including past local dates.
--
-- No table, column, constraint, index, write RPC, or existing data is
-- changed.

begin;

drop function public.get_managed_clinic_appointment_availability(uuid);

create function public.get_managed_clinic_appointment_availability(
    p_clinic_id uuid
)
returns table (
    scheduling_timezone_name text,
    standard_appointment_duration_minutes integer,
    recurring_periods jsonb,
    exceptions jsonb
)
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

    perform public.assert_clinic_capability_after_lock(
        acting_user_id,
        p_clinic_id,
        'APPOINTMENT_MANAGE_AVAILABILITY'
    );

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

commit;

-- Professional calendar context (SPEC-APT-012 §14, BR-60).
--
-- Additive only. Every existing RPC keeps its signature, body, and grants.
--
--   1. clinic_calendar_context_at(uuid, timestamptz) — internal. The Clinic's
--      current valid scheduling timezone and the civil date of an instant in
--      it, or both null.
--   2. get_clinic_calendar_context(uuid) — the same for the statement
--      instant, for APPOINTMENT_VIEW_SCHEDULE holders (BR-60).
--
-- No table, column, constraint, capability, lifecycle state, transition, or
-- write contract changes.

begin;

-- ==================================================================
-- 1. Calendar context at an instant (SPEC-APT-012 BR-60). Internal.
-- ==================================================================

-- One row for an existing Clinic: its scheduling timezone when valid under
-- the rule the schedule projection uses (clinic_timezone_name_is_valid), and
-- the civil date of p_as_of in it — or both null, never an alternative zone.
-- `at time zone` with the zone name never depends on the session timezone.
-- Taking the instant as input lets the date rule be verified at chosen
-- instants (midnight, daylight-saving transitions).
create function public.clinic_calendar_context_at(
    p_clinic_id uuid,
    p_as_of timestamptz
)
returns table (
    clinic_local_today date,
    scheduling_timezone_name text
)
language sql
stable
security definer
set search_path = ''
as $$
    select (p_as_of at time zone valid_zone.timezone_name)::date,
           valid_zone.timezone_name
    from public.clinics as clinic
    cross join lateral (
        select case
                   when public.clinic_timezone_name_is_valid(clinic.scheduling_timezone_name)
                       then clinic.scheduling_timezone_name
               end as timezone_name
    ) as valid_zone
    where clinic.id = p_clinic_id;
$$;

revoke all privileges
on function public.clinic_calendar_context_at(uuid, timestamptz)
from public, anon, authenticated;

-- ==================================================================
-- 2. Calendar context now (SPEC-APT-012 BR-60).
-- ==================================================================

create function public.get_clinic_calendar_context(
    p_clinic_id uuid
)
returns table (
    clinic_local_today date,
    scheduling_timezone_name text
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

    -- Authorization first: nothing about the Clinic is read before it, and a
    -- missing Clinic fails exactly like missing authority (BR-54).
    if not public.user_has_clinic_capability(
        acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE'
    ) then
        raise exception 'Applicable Appointment schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    select context.clinic_local_today, context.scheduling_timezone_name
    from public.clinic_calendar_context_at(p_clinic_id, statement_timestamp()) as context;
end;
$$;

revoke all privileges
on function public.get_clinic_calendar_context(uuid)
from public, anon, authenticated;

grant execute
on function public.get_clinic_calendar_context(uuid)
to authenticated;

commit;

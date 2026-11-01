-- Clinic self-service Phase 1, Slice C: scheduling timezone, Publish, and
-- Unpublish (SPEC-APT-013 BR-56/BR-76; SPEC-CLI-003 BR-15–BR-20).
--
-- Forward-only.
--
-- 1. set_clinic_scheduling_timezone (last defined in
--    20261018090000_br56_past_exceptions_not_currently_effective.sql) is
--    replaced in place (same signature, result, attributes, ACL). It used the
--    shared assert_clinic_capability_after_lock, which reports an unknown
--    Clinic as 23503 "Clinic does not exist" before any capability check.
--    It now locks Organization -> Clinic itself and reports an unknown Clinic
--    exactly like an inaccessible one: 42501 "Applicable Clinic-management
--    capability is required" (SPEC-APT-013 BR-76). Everything after the
--    capability check is unchanged: timezone validation (22023) first, then
--    the BR-56 currently-effective-Availability gate (42501 with its distinct
--    Entitlement message), then the update. No clearing, last-write-wins.
--
-- 2. publish_clinic (last defined in
--    20260825150316_clinic_foundation_and_professional_context.sql) is
--    replaced in place: an unknown Clinic is now 42501 with the operation's
--    capability message instead of 23503 (SPEC-CLI-003 BR-20). Requirements
--    are unchanged and exactly SPEC-CLI-003 BR-15: a valid display name and a
--    stored location (23514 otherwise) — no timezone, duration, Availability,
--    Opening Hours, Services, or Entitlement. Idempotent.
--
-- 3. unpublish_clinic(p_clinic_id uuid) returns uuid is added
--    (SPEC-CLI-003 BR-16): CLINIC_MANAGE_PUBLICATION, the same
--    Organization -> Clinic lock order and fail-closed disclosure, no
--    Entitlement, idempotent, and it changes only clinics.is_published. It
--    deletes no configuration and touches no Appointment, Schedule Revision,
--    Reschedule Proposal, Care Authorization, or Communication; no
--    Communication is created (BR-16, BR-18).
--
-- The shared helper assert_clinic_capability_after_lock is NOT changed: it
-- backs many unrelated writes whose contracts stay as they are.

begin;

-- ==================================================================
-- 1. Scheduling timezone
-- ==================================================================

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
    target_organization_id uuid;
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

    -- Organization -> Clinic locks; an unknown Clinic is reported exactly
    -- like an inaccessible one (SPEC-APT-013 BR-76).
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found
       or not public.user_has_clinic_capability(
           acting_user_id,
           p_clinic_id,
           'CLINIC_MANAGE_OPENING_HOURS'
       ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    -- Unchanged from 20261018090000 from here on.
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

-- ==================================================================
-- 2. Publish
-- ==================================================================

create or replace function public.publish_clinic(
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
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

    -- Organization -> Clinic locks; an unknown Clinic is reported exactly
    -- like an inaccessible one (SPEC-CLI-003 BR-20).
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic publication-management capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found
       or not public.user_has_clinic_capability(
           acting_user_id,
           p_clinic_id,
           'CLINIC_MANAGE_PUBLICATION'
       ) then
        raise exception 'Clinic publication-management capability is required'
            using errcode = '42501';
    end if;

    -- Requirements, only for an authorized caller (SPEC-CLI-003 BR-15):
    -- exactly a stored location and a valid display name.
    if not exists (
        select 1
        from public.clinic_locations as location
        where location.clinic_id = p_clinic_id
    ) then
        raise exception 'Clinic publication requires a valid current Location'
            using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.clinic_public_profiles as profile
        where profile.clinic_id = p_clinic_id
          and profile.display_name is not null
          and profile.display_name = btrim(
              profile.display_name,
              E' \t\n\r\f\013'
          )
          and profile.display_name <> ''
    ) then
        raise exception 'Clinic publication requires a valid public display name'
            using errcode = '23514';
    end if;

    update public.clinics
    set is_published = true
    where id = p_clinic_id;

    return p_clinic_id;
end;
$$;

-- ==================================================================
-- 3. Unpublish
-- ==================================================================

create function public.unpublish_clinic(
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
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

    -- Organization -> Clinic locks, as Publish; an unknown Clinic is reported
    -- exactly like an inaccessible one (SPEC-CLI-003 BR-16, BR-20).
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic publication-management capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found
       or not public.user_has_clinic_capability(
           acting_user_id,
           p_clinic_id,
           'CLINIC_MANAGE_PUBLICATION'
       ) then
        raise exception 'Clinic publication-management capability is required'
            using errcode = '42501';
    end if;

    -- Only the publication state changes; already unpublished is a no-op.
    update public.clinics
    set is_published = false
    where id = p_clinic_id
      and is_published;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.unpublish_clinic(uuid)
from public, anon, authenticated;

grant execute
on function public.unpublish_clinic(uuid)
to authenticated;

commit;

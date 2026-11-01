-- Weekly Appointment Availability stale-edit protection (SPEC-APT-013 BR-74,
-- BR-75, Verification Notes 45-46).
--
-- Forward-only. A weekly replacement covers all seven days, so one prepared
-- from an outdated week silently undid another actor's change. The Clinic now
-- carries a revision of its stored recurring periods:
--
--   * clinics.weekly_appointment_availability_revision bigint not null
--     default 0, non-negative. Existing Clinics start at 0: the value is an
--     optimistic-concurrency token, not history, so no backfill is needed;
--   * get_managed_clinic_appointment_availability returns it with the periods
--     it identifies (one trailing column; the read is otherwise unchanged:
--     same authorization, STABLE, no lock, no Entitlement);
--   * replace_clinic_appointment_availability(uuid, jsonb) is replaced by
--     replace_clinic_appointment_availability(uuid, jsonb, bigint), with no
--     compatibility overload. Under the existing Organization -> Clinic lock
--     it rejects an outdated expected revision (P0001, nothing written),
--     validates the week exactly as before, leaves an identical set (in any
--     order) untouched with its revision, and otherwise replaces the set and
--     increments the revision by one.
--
-- Exceptions, standard duration, timezone, Opening Hours, and Veterinarian
-- Availability neither read nor change the revision; their RPCs are
-- untouched.

begin;

alter table public.clinics
    add column weekly_appointment_availability_revision bigint not null default 0,
    add constraint clinics_weekly_appointment_availability_revision_check
        check (weekly_appointment_availability_revision >= 0);

-- ==================================================================
-- Management read (SPEC-APT-013 BR-74): one trailing column.
-- ==================================================================

drop function public.get_managed_clinic_appointment_availability(uuid);

create function public.get_managed_clinic_appointment_availability(
    p_clinic_id uuid
)
returns table (
    scheduling_timezone_name text,
    standard_appointment_duration_minutes integer,
    recurring_periods jsonb,
    exceptions jsonb,
    weekly_appointment_availability_revision bigint
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

    -- One statement, one snapshot: the revision identifies exactly the
    -- recurring periods returned with it.
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
        ),
        clinic.weekly_appointment_availability_revision
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

-- ==================================================================
-- Stale-protected whole-week replacement (SPEC-APT-013 BR-75).
-- ==================================================================

drop function public.replace_clinic_appointment_availability(uuid, jsonb);

create function public.replace_clinic_appointment_availability(
    p_clinic_id uuid,
    p_periods jsonb,
    p_expected_weekly_availability_revision bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    clinic_timezone_name text;
    current_revision bigint;
    week_changes boolean;
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

    -- Structural input, before any Clinic state.
    if p_expected_weekly_availability_revision is null
       or p_expected_weekly_availability_revision < 0 then
        raise exception 'Expected weekly Appointment Availability revision must be a non-negative integer'
            using errcode = '22023';
    end if;

    -- Organization -> Clinic FOR UPDATE, capability, PROFESSIONAL_SCHEDULING.
    perform public.assert_clinic_scheduling_authorization_after_lock(
        acting_user_id,
        p_clinic_id
    );

    -- Read under the Clinic lock: a concurrent replacement of the same Clinic
    -- waits for this one and then sees its revision.
    select clinic.weekly_appointment_availability_revision
    into current_revision
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if current_revision <> p_expected_weekly_availability_revision then
        raise exception 'Stale weekly Clinic Appointment Availability revision';
    end if;

    if jsonb_typeof(p_periods) is distinct from 'array' then
        raise exception 'Clinic Appointment Availability must be a JSON array'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where jsonb_typeof(period.item) is distinct from 'object'
    ) then
        raise exception 'Every Clinic Appointment Availability Period must be a JSON object'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where not (period.item ? 'iso_weekday')
           or jsonb_typeof(period.item -> 'iso_weekday') is distinct from 'number'
           or not (period.item ? 'start_time')
           or jsonb_typeof(period.item -> 'start_time') is distinct from 'string'
           or not (period.item ? 'end_time')
           or jsonb_typeof(period.item -> 'end_time') is distinct from 'string'
    ) then
        raise exception 'Every Clinic Appointment Availability Period requires valid iso_weekday, start_time, and end_time members'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        cross join lateral jsonb_object_keys(period.item) as member(key)
        where member.key not in (
            'iso_weekday',
            'start_time',
            'end_time'
        )
    ) then
        raise exception 'Clinic Appointment Availability Period contains an unsupported member'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where period.item ->> 'iso_weekday' !~ '^[1-7]$'
    ) then
        raise exception 'Clinic Appointment Availability Period ISO weekday must be between 1 and 7'
            using errcode = '22023';
    end if;

    if jsonb_array_length(p_periods) > 0 then
        select clinic.scheduling_timezone_name
        into clinic_timezone_name
        from public.clinics as clinic
        where clinic.id = p_clinic_id;

        if not public.clinic_timezone_name_is_valid(
            clinic_timezone_name
        ) then
            raise exception 'Clinic Appointment Availability requires a valid scheduling timezone'
                using errcode = '23514';
        end if;
    end if;

    if exists (
        with parsed_periods as materialized (
            select
                (period.item ->> 'iso_weekday')::smallint as iso_weekday,
                public.parse_clinic_local_time(
                    period.item ->> 'start_time'
                ) as start_time,
                public.parse_clinic_local_time(
                    period.item ->> 'end_time'
                ) as end_time
            from jsonb_array_elements(p_periods) as period(item)
        )
        select 1
        from parsed_periods as parsed_period
        where parsed_period.start_time >= parsed_period.end_time
    ) then
        raise exception 'Clinic Appointment Availability Period must have start_time before end_time'
            using errcode = '22023';
    end if;

    if exists (
        with parsed_periods as materialized (
            select
                (period.item ->> 'iso_weekday')::smallint as iso_weekday,
                public.parse_clinic_local_time(
                    period.item ->> 'start_time'
                ) as start_time,
                public.parse_clinic_local_time(
                    period.item ->> 'end_time'
                ) as end_time
            from jsonb_array_elements(p_periods) as period(item)
        )
        select 1
        from parsed_periods as parsed_period
        group by
            parsed_period.iso_weekday,
            parsed_period.start_time,
            parsed_period.end_time
        having count(*) > 1
    ) then
        raise exception 'Clinic Appointment Availability Periods must not contain duplicates'
            using errcode = '23505';
    end if;

    if exists (
        with parsed_periods as materialized (
            select
                period.ordinality as period_number,
                (period.item ->> 'iso_weekday')::smallint as iso_weekday,
                public.parse_clinic_local_time(
                    period.item ->> 'start_time'
                ) as start_time,
                public.parse_clinic_local_time(
                    period.item ->> 'end_time'
                ) as end_time
            from jsonb_array_elements(p_periods)
                with ordinality as period(item, ordinality)
        )
        select 1
        from parsed_periods as first_period
        join parsed_periods as second_period
          on second_period.period_number > first_period.period_number
         and second_period.iso_weekday = first_period.iso_weekday
        where first_period.start_time < second_period.end_time
          and second_period.start_time < first_period.end_time
    ) then
        raise exception 'Clinic Appointment Availability Periods must not overlap'
            using errcode = '23P01';
    end if;

    -- Duplicates are rejected above, so set equality is exact: an identical
    -- week (in any order or time spelling) changes nothing, not even the
    -- revision.
    with parsed_periods as materialized (
        select
            (period.item ->> 'iso_weekday')::smallint as iso_weekday,
            public.parse_clinic_local_time(period.item ->> 'start_time') as start_time,
            public.parse_clinic_local_time(period.item ->> 'end_time') as end_time
        from jsonb_array_elements(p_periods) as period(item)
    ),
    stored_periods as (
        select stored.iso_weekday, stored.start_time, stored.end_time
        from public.clinic_appointment_availability_periods as stored
        where stored.clinic_id = p_clinic_id
    )
    select exists (select * from parsed_periods except select * from stored_periods)
        or exists (select * from stored_periods except select * from parsed_periods)
    into week_changes;

    if not week_changes then
        return p_clinic_id;
    end if;

    delete from public.clinic_appointment_availability_periods as existing_period
    where existing_period.clinic_id = p_clinic_id;

    insert into public.clinic_appointment_availability_periods (
        clinic_id,
        iso_weekday,
        start_time,
        end_time
    )
    select
        p_clinic_id,
        (period.item ->> 'iso_weekday')::smallint,
        public.parse_clinic_local_time(period.item ->> 'start_time'),
        public.parse_clinic_local_time(period.item ->> 'end_time')
    from jsonb_array_elements(p_periods) as period(item);

    update public.clinics
    set weekly_appointment_availability_revision = weekly_appointment_availability_revision + 1
    where id = p_clinic_id;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.replace_clinic_appointment_availability(uuid, jsonb, bigint)
from public, anon, authenticated;

grant execute
on function public.replace_clinic_appointment_availability(uuid, jsonb, bigint)
to authenticated;

commit;

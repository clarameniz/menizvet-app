begin;

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
                'CLINIC_MANAGE_OPENING_HOURS'
            ),
            false
        )
        and exists (
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
                      and grant_record.responsibility in (
                          'OWNER',
                          'ADMINISTRATOR'
                      )
                  )
                  or
                  (
                      grant_record.scope_type = 'CLINIC'
                      and grant_record.clinic_id = p_clinic_id
                      and grant_record.responsibility = 'ADMINISTRATOR'
                  )
              )
        )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

alter table public.clinics
add column scheduling_timezone_name text;

create function public.clinic_timezone_name_is_valid(
    p_timezone_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        p_timezone_name is not null
        and p_timezone_name = btrim(
            p_timezone_name,
            E' \t\n\r\f\013'
        )
        and p_timezone_name <> ''
        and exists (
            select 1
            from pg_catalog.pg_timezone_names as timezone_entry
            where timezone_entry.name = p_timezone_name
        )
$$;

revoke all privileges
on function public.clinic_timezone_name_is_valid(text)
from public, anon, authenticated;

create function public.normalize_clinic_scheduling_timezone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.scheduling_timezone_name is null then
        return new;
    end if;

    new.scheduling_timezone_name := btrim(
        new.scheduling_timezone_name,
        E' \t\n\r\f\013'
    );

    if not public.clinic_timezone_name_is_valid(
        new.scheduling_timezone_name
    ) then
        raise exception 'Clinic scheduling timezone must be a valid named timezone'
            using errcode = '22023';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.normalize_clinic_scheduling_timezone()
from public, anon, authenticated;

create trigger clinics_normalize_scheduling_timezone
before insert or update of scheduling_timezone_name on public.clinics
for each row
execute function public.normalize_clinic_scheduling_timezone();

create table public.clinic_service_offerings (
    clinic_id uuid not null,
    service_category text not null,
    public_description text,
    constraint clinic_service_offerings_pkey
        primary key (clinic_id, service_category),
    constraint clinic_service_offerings_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_service_offerings_category_check
        check (
            service_category in (
                'GENERAL_CONSULTATION',
                'VACCINATION',
                'SURGERY',
                'DENTISTRY',
                'DIAGNOSTIC_IMAGING',
                'LABORATORY',
                'EMERGENCY_CARE',
                'HOSPITALIZATION',
                'OTHER'
            )
        ),
    constraint clinic_service_offerings_description_check
        check (
            public_description is null
            or (
                public_description = btrim(
                    public_description,
                    E' \t\n\r\f\013'
                )
                and public_description <> ''
            )
        ),
    constraint clinic_service_offerings_other_description_check
        check (
            service_category <> 'OTHER'
            or public_description is not null
        )
);

create table public.clinic_opening_periods (
    clinic_id uuid not null,
    iso_weekday smallint not null,
    start_time time without time zone not null,
    end_time time without time zone not null,
    constraint clinic_opening_periods_pkey
        primary key (
            clinic_id,
            iso_weekday,
            start_time,
            end_time
        ),
    constraint clinic_opening_periods_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_opening_periods_iso_weekday_check
        check (iso_weekday between 1 and 7),
    constraint clinic_opening_periods_interval_check
        check (start_time < end_time)
);

create table public.clinic_opening_exceptions (
    id uuid not null default gen_random_uuid(),
    clinic_id uuid not null,
    local_date date not null,
    exception_kind text not null,
    start_time time without time zone,
    end_time time without time zone,
    constraint clinic_opening_exceptions_pkey primary key (id),
    constraint clinic_opening_exceptions_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_opening_exceptions_local_date_finite_check
        check (
            local_date <> 'infinity'::date
            and local_date <> '-infinity'::date
        ),
    constraint clinic_opening_exceptions_kind_check
        check (exception_kind in ('CLOSED', 'OPEN')),
    constraint clinic_opening_exceptions_shape_check
        check (
            (
                exception_kind = 'CLOSED'
                and start_time is null
                and end_time is null
            )
            or
            (
                exception_kind = 'OPEN'
                and start_time is not null
                and end_time is not null
                and start_time < end_time
            )
        )
);

create unique index clinic_opening_exceptions_closed_date_key
on public.clinic_opening_exceptions (clinic_id, local_date)
where exception_kind = 'CLOSED';

create unique index clinic_opening_exceptions_open_exact_key
on public.clinic_opening_exceptions (
    clinic_id,
    local_date,
    start_time,
    end_time
)
where exception_kind = 'OPEN';

create index clinic_opening_exceptions_clinic_date_idx
on public.clinic_opening_exceptions (clinic_id, local_date);

create trigger clinic_service_offerings_lock_context
before insert or update or delete on public.clinic_service_offerings
for each row
execute function public.lock_clinic_configuration_context();

create trigger clinic_opening_periods_lock_context
before insert or update or delete on public.clinic_opening_periods
for each row
execute function public.lock_clinic_configuration_context();

create trigger clinic_opening_exceptions_lock_context
before insert or update or delete on public.clinic_opening_exceptions
for each row
execute function public.lock_clinic_configuration_context();

create function public.assert_clinic_timezone_dependency(
    p_clinic_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    timezone_name text;
begin
    select clinic.scheduling_timezone_name
    into timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found then
        return;
    end if;

    if (
        exists (
            select 1
            from public.clinic_opening_periods as period
            where period.clinic_id = p_clinic_id
        )
        or exists (
            select 1
            from public.clinic_opening_exceptions as exception_record
            where exception_record.clinic_id = p_clinic_id
        )
    ) and not public.clinic_timezone_name_is_valid(timezone_name) then
        raise exception 'Clinic timezone-dependent configuration requires a valid scheduling timezone'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_timezone_dependency(uuid)
from public, anon, authenticated;

create function public.enforce_clinic_timezone_dependency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'clinics' then
        perform public.assert_clinic_timezone_dependency(new.id);
    elsif tg_op = 'INSERT' then
        perform public.assert_clinic_timezone_dependency(new.clinic_id);
    elsif tg_op = 'DELETE' then
        perform public.assert_clinic_timezone_dependency(old.clinic_id);
    elsif tg_op = 'UPDATE' then
        perform public.assert_clinic_timezone_dependency(old.clinic_id);
        if old.clinic_id is distinct from new.clinic_id then
            perform public.assert_clinic_timezone_dependency(new.clinic_id);
        end if;
    else
        raise exception 'Unexpected Clinic timezone-integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinic_timezone_dependency()
from public, anon, authenticated;

create function public.assert_clinic_opening_period_integrity(
    p_clinic_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.clinic_opening_periods as first_period
        join public.clinic_opening_periods as second_period
          on second_period.clinic_id = first_period.clinic_id
         and second_period.iso_weekday = first_period.iso_weekday
         and (
             first_period.start_time,
             first_period.end_time
         ) < (
             second_period.start_time,
             second_period.end_time
         )
        where first_period.clinic_id = p_clinic_id
          and first_period.start_time < second_period.end_time
          and second_period.start_time < first_period.end_time
    ) then
        raise exception 'Clinic Opening Periods must not overlap'
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_opening_period_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_clinic_opening_period_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        perform public.assert_clinic_opening_period_integrity(new.clinic_id);
    elsif tg_op = 'DELETE' then
        perform public.assert_clinic_opening_period_integrity(old.clinic_id);
    elsif tg_op = 'UPDATE' then
        perform public.assert_clinic_opening_period_integrity(old.clinic_id);
        if old.clinic_id is distinct from new.clinic_id then
            perform public.assert_clinic_opening_period_integrity(new.clinic_id);
        end if;
    else
        raise exception 'Unexpected Clinic Opening Period integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinic_opening_period_integrity()
from public, anon, authenticated;

create function public.assert_clinic_opening_exception_integrity(
    p_clinic_id uuid,
    p_local_date date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.clinic_opening_exceptions as closed_exception
        where closed_exception.clinic_id = p_clinic_id
          and closed_exception.local_date = p_local_date
          and closed_exception.exception_kind = 'CLOSED'
    ) and exists (
        select 1
        from public.clinic_opening_exceptions as open_exception
        where open_exception.clinic_id = p_clinic_id
          and open_exception.local_date = p_local_date
          and open_exception.exception_kind = 'OPEN'
    ) then
        raise exception 'Clinic Opening Exception cannot combine CLOSED and OPEN interpretations'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.clinic_opening_exceptions as first_exception
        join public.clinic_opening_exceptions as second_exception
          on second_exception.clinic_id = first_exception.clinic_id
         and second_exception.local_date = first_exception.local_date
         and second_exception.exception_kind = 'OPEN'
         and first_exception.id < second_exception.id
        where first_exception.clinic_id = p_clinic_id
          and first_exception.local_date = p_local_date
          and first_exception.exception_kind = 'OPEN'
          and first_exception.start_time < second_exception.end_time
          and second_exception.start_time < first_exception.end_time
    ) then
        raise exception 'Clinic Opening Exception periods must not overlap'
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_opening_exception_integrity(uuid, date)
from public, anon, authenticated;

create function public.enforce_clinic_opening_exception_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        perform public.assert_clinic_opening_exception_integrity(
            new.clinic_id,
            new.local_date
        );
    elsif tg_op = 'DELETE' then
        perform public.assert_clinic_opening_exception_integrity(
            old.clinic_id,
            old.local_date
        );
    elsif tg_op = 'UPDATE' then
        perform public.assert_clinic_opening_exception_integrity(
            old.clinic_id,
            old.local_date
        );
        if old.clinic_id is distinct from new.clinic_id
           or old.local_date is distinct from new.local_date then
            perform public.assert_clinic_opening_exception_integrity(
                new.clinic_id,
                new.local_date
            );
        end if;
    else
        raise exception 'Unexpected Clinic Opening Exception integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinic_opening_exception_integrity()
from public, anon, authenticated;

create constraint trigger clinics_enforce_timezone_dependency
after insert or update on public.clinics
deferrable initially deferred
for each row
execute function public.enforce_clinic_timezone_dependency();

create constraint trigger clinic_opening_periods_enforce_timezone_dependency
after insert or update or delete on public.clinic_opening_periods
deferrable initially deferred
for each row
execute function public.enforce_clinic_timezone_dependency();

create constraint trigger clinic_opening_exceptions_enforce_timezone_dependency
after insert or update or delete on public.clinic_opening_exceptions
deferrable initially deferred
for each row
execute function public.enforce_clinic_timezone_dependency();

create constraint trigger clinic_opening_periods_enforce_overlap
after insert or update or delete on public.clinic_opening_periods
deferrable initially deferred
for each row
execute function public.enforce_clinic_opening_period_integrity();

create constraint trigger clinic_opening_exceptions_enforce_coherence
after insert or update or delete on public.clinic_opening_exceptions
deferrable initially deferred
for each row
execute function public.enforce_clinic_opening_exception_integrity();

alter table public.clinic_service_offerings enable row level security;
alter table public.clinic_opening_periods enable row level security;
alter table public.clinic_opening_exceptions enable row level security;

revoke all privileges on table public.clinic_service_offerings
from public, anon, authenticated;
revoke all privileges on table public.clinic_opening_periods
from public, anon, authenticated;
revoke all privileges on table public.clinic_opening_exceptions
from public, anon, authenticated;

create function public.assert_clinic_capability_after_lock(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns void
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

    if not public.user_has_clinic_capability(
        p_user_id,
        p_clinic_id,
        p_capability
    ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_capability_after_lock(uuid, uuid, text)
from public, anon, authenticated;

create function public.parse_clinic_local_time(
    p_value text
)
returns time without time zone
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
    if p_value is null
       or p_value !~ '^(([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\.[0-9]{1,6})?)?|24:00(:00(\.0{1,6})?)?)$' then
        raise exception 'Clinic local time must use a valid ISO local-time representation'
            using errcode = '22007';
    end if;

    return p_value::time without time zone;
end;
$$;

revoke all privileges
on function public.parse_clinic_local_time(text)
from public, anon, authenticated;

create function public.set_clinic_scheduling_timezone(
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

    update public.clinics
    set scheduling_timezone_name = normalized_timezone_name
    where id = p_clinic_id;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.set_clinic_scheduling_timezone(uuid, text)
from public, anon, authenticated;

grant execute
on function public.set_clinic_scheduling_timezone(uuid, text)
to authenticated;

create function public.replace_clinic_service_offerings(
    p_clinic_id uuid,
    p_offerings jsonb
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

    perform public.assert_clinic_capability_after_lock(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_SERVICES'
    );

    if jsonb_typeof(p_offerings) is distinct from 'array' then
        raise exception 'Clinic Service Offerings must be a JSON array'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_offerings) as offering(item)
        where jsonb_typeof(offering.item) is distinct from 'object'
    ) then
        raise exception 'Every Clinic Service Offering must be a JSON object'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_offerings) as offering(item)
        where not (offering.item ? 'service_category')
           or jsonb_typeof(offering.item -> 'service_category') is distinct from 'string'
           or not (offering.item ? 'public_description')
           or jsonb_typeof(offering.item -> 'public_description') not in (
               'string',
               'null'
           )
    ) then
        raise exception 'Every Clinic Service Offering requires valid service_category and public_description members'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_offerings) as offering(item)
        cross join lateral jsonb_object_keys(offering.item) as member(key)
        where member.key not in (
            'service_category',
            'public_description'
        )
    ) then
        raise exception 'Clinic Service Offering contains an unsupported member'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_offerings) as offering(item)
        where offering.item ->> 'service_category' not in (
            'GENERAL_CONSULTATION',
            'VACCINATION',
            'SURGERY',
            'DENTISTRY',
            'DIAGNOSTIC_IMAGING',
            'LABORATORY',
            'EMERGENCY_CARE',
            'HOSPITALIZATION',
            'OTHER'
        )
    ) then
        raise exception 'Clinic Service Offering contains an unsupported category'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_offerings) as offering(item)
        where jsonb_typeof(offering.item -> 'public_description') = 'string'
          and nullif(
              btrim(
                  offering.item ->> 'public_description',
                  E' \t\n\r\f\013'
              ),
              ''
          ) is null
    ) then
        raise exception 'Clinic Service public description must not be blank'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_offerings) as offering(item)
        where offering.item ->> 'service_category' = 'OTHER'
          and (
              jsonb_typeof(offering.item -> 'public_description') = 'null'
              or nullif(
                  btrim(
                      offering.item ->> 'public_description',
                      E' \t\n\r\f\013'
                  ),
                  ''
              ) is null
          )
    ) then
        raise exception 'OTHER Clinic Service requires a meaningful public description'
            using errcode = '22023';
    end if;

    if exists (
        select offering.item ->> 'service_category'
        from jsonb_array_elements(p_offerings) as offering(item)
        group by offering.item ->> 'service_category'
        having count(*) > 1
    ) then
        raise exception 'Clinic Service Offering categories must not be duplicated'
            using errcode = '23505';
    end if;

    delete from public.clinic_service_offerings as existing_offering
    where existing_offering.clinic_id = p_clinic_id;

    insert into public.clinic_service_offerings (
        clinic_id,
        service_category,
        public_description
    )
    select
        p_clinic_id,
        offering.item ->> 'service_category',
        case
            when jsonb_typeof(
                offering.item -> 'public_description'
            ) = 'null' then null
            else btrim(
                offering.item ->> 'public_description',
                E' \t\n\r\f\013'
            )
        end
    from jsonb_array_elements(p_offerings) as offering(item);

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.replace_clinic_service_offerings(uuid, jsonb)
from public, anon, authenticated;

grant execute
on function public.replace_clinic_service_offerings(uuid, jsonb)
to authenticated;

create function public.replace_clinic_opening_hours(
    p_clinic_id uuid,
    p_periods jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    clinic_timezone_name text;
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

    if jsonb_typeof(p_periods) is distinct from 'array' then
        raise exception 'Clinic Opening Hours must be a JSON array'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where jsonb_typeof(period.item) is distinct from 'object'
    ) then
        raise exception 'Every Clinic Opening Period must be a JSON object'
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
        raise exception 'Every Clinic Opening Period requires valid iso_weekday, start_time, and end_time members'
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
        raise exception 'Clinic Opening Period contains an unsupported member'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where period.item ->> 'iso_weekday' !~ '^[1-7]$'
    ) then
        raise exception 'Clinic Opening Period ISO weekday must be between 1 and 7'
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
            raise exception 'Clinic Opening Hours require a valid scheduling timezone'
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
        raise exception 'Clinic Opening Period must have start_time before end_time'
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
        raise exception 'Clinic Opening Periods must not contain duplicates'
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
        raise exception 'Clinic Opening Periods must not overlap'
            using errcode = '23P01';
    end if;

    delete from public.clinic_opening_periods as existing_period
    where existing_period.clinic_id = p_clinic_id;

    insert into public.clinic_opening_periods (
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

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.replace_clinic_opening_hours(uuid, jsonb)
from public, anon, authenticated;

grant execute
on function public.replace_clinic_opening_hours(uuid, jsonb)
to authenticated;

create function public.set_clinic_opening_exception(
    p_clinic_id uuid,
    p_local_date date,
    p_exception_kind text,
    p_periods jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    clinic_timezone_name text;
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

    if p_local_date is null
       or p_local_date = 'infinity'::date
       or p_local_date = '-infinity'::date then
        raise exception 'Clinic Opening Exception local date must be a finite date'
            using errcode = '22023';
    end if;

    if p_exception_kind not in ('CLOSED', 'OPEN')
       or p_exception_kind is null then
        raise exception 'Clinic Opening Exception kind must be CLOSED or OPEN'
            using errcode = '22023';
    end if;

    if jsonb_typeof(p_periods) is distinct from 'array' then
        raise exception 'Clinic Opening Exception periods must be a JSON array'
            using errcode = '22023';
    end if;

    if p_exception_kind = 'CLOSED'
       and jsonb_array_length(p_periods) <> 0 then
        raise exception 'CLOSED Clinic Opening Exception must not contain periods'
            using errcode = '22023';
    end if;

    if p_exception_kind = 'OPEN'
       and jsonb_array_length(p_periods) = 0 then
        raise exception 'OPEN Clinic Opening Exception requires at least one period'
            using errcode = '22023';
    end if;

    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not public.clinic_timezone_name_is_valid(
        clinic_timezone_name
    ) then
        raise exception 'Clinic Opening Exception requires a valid scheduling timezone'
            using errcode = '23514';
    end if;

    if p_exception_kind = 'OPEN' then
        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            where jsonb_typeof(period.item) is distinct from 'object'
        ) then
            raise exception 'Every Clinic Opening Exception period must be a JSON object'
                using errcode = '22023';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            where not (period.item ? 'start_time')
               or jsonb_typeof(period.item -> 'start_time') is distinct from 'string'
               or not (period.item ? 'end_time')
               or jsonb_typeof(period.item -> 'end_time') is distinct from 'string'
        ) then
            raise exception 'Every Clinic Opening Exception period requires valid start_time and end_time members'
                using errcode = '22023';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            cross join lateral jsonb_object_keys(period.item) as member(key)
            where member.key not in ('start_time', 'end_time')
        ) then
            raise exception 'Clinic Opening Exception period contains an unsupported member'
                using errcode = '22023';
        end if;

        if exists (
            with parsed_periods as materialized (
                select
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
            raise exception 'Clinic Opening Exception period must have start_time before end_time'
                using errcode = '22023';
        end if;

        if exists (
            with parsed_periods as materialized (
                select
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
            group by parsed_period.start_time, parsed_period.end_time
            having count(*) > 1
        ) then
            raise exception 'Clinic Opening Exception periods must not contain duplicates'
                using errcode = '23505';
        end if;

        if exists (
            with parsed_periods as materialized (
                select
                    period.ordinality as period_number,
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
            where first_period.start_time < second_period.end_time
              and second_period.start_time < first_period.end_time
        ) then
            raise exception 'Clinic Opening Exception periods must not overlap'
                using errcode = '23P01';
        end if;
    end if;

    delete from public.clinic_opening_exceptions as existing_exception
    where existing_exception.clinic_id = p_clinic_id
      and existing_exception.local_date = p_local_date;

    if p_exception_kind = 'CLOSED' then
        insert into public.clinic_opening_exceptions (
            clinic_id,
            local_date,
            exception_kind
        )
        values (
            p_clinic_id,
            p_local_date,
            'CLOSED'
        );
    else
        insert into public.clinic_opening_exceptions (
            clinic_id,
            local_date,
            exception_kind,
            start_time,
            end_time
        )
        select
            p_clinic_id,
            p_local_date,
            'OPEN',
            public.parse_clinic_local_time(period.item ->> 'start_time'),
            public.parse_clinic_local_time(period.item ->> 'end_time')
        from jsonb_array_elements(p_periods) as period(item);
    end if;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.set_clinic_opening_exception(uuid, date, text, jsonb)
from public, anon, authenticated;

grant execute
on function public.set_clinic_opening_exception(uuid, date, text, jsonb)
to authenticated;

create function public.clear_clinic_opening_exception(
    p_clinic_id uuid,
    p_local_date date
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

    perform public.assert_clinic_capability_after_lock(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_OPENING_HOURS'
    );

    if p_local_date is null then
        raise exception 'Clinic Opening Exception local date is required'
            using errcode = '22023';
    end if;

    delete from public.clinic_opening_exceptions as existing_exception
    where existing_exception.clinic_id = p_clinic_id
      and existing_exception.local_date = p_local_date;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.clear_clinic_opening_exception(uuid, date)
from public, anon, authenticated;

grant execute
on function public.clear_clinic_opening_exception(uuid, date)
to authenticated;

create function public.get_managed_clinic_service_offerings(
    p_clinic_id uuid
)
returns table (
    service_category text,
    public_description text
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
        'CLINIC_MANAGE_SERVICES'
    );

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

create function public.get_managed_clinic_opening_hours(
    p_clinic_id uuid
)
returns table (
    scheduling_timezone_name text,
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
        'CLINIC_MANAGE_OPENING_HOURS'
    );

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

create function public.get_published_clinic_service_offerings(
    p_clinic_id uuid
)
returns table (
    service_category text,
    public_description text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        offering.service_category,
        offering.public_description
    from public.clinics as clinic
    join public.clinic_service_offerings as offering
      on offering.clinic_id = clinic.id
    where clinic.id = p_clinic_id
      and clinic.is_published = true
    order by offering.service_category
$$;

revoke all privileges
on function public.get_published_clinic_service_offerings(uuid)
from public, anon, authenticated;

grant execute
on function public.get_published_clinic_service_offerings(uuid)
to anon, authenticated;

create function public.get_published_clinic_opening_hours(
    p_clinic_id uuid
)
returns table (
    scheduling_timezone_name text,
    recurring_periods jsonb,
    exceptions jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
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
    where clinic.id = p_clinic_id
      and clinic.is_published = true
$$;

revoke all privileges
on function public.get_published_clinic_opening_hours(uuid)
from public, anon, authenticated;

grant execute
on function public.get_published_clinic_opening_hours(uuid)
to anon, authenticated;

commit;

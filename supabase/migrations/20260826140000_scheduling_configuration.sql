begin;

-- ==================================================================
-- 1. Extend Clinic capability evaluation with Appointment Availability
--    management, including scoped RECEPTIONIST authority (SPEC-ORG-005 §6).
--    Prior capability behavior (CLINIC_MANAGE_*) is preserved unchanged.
-- ==================================================================

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
                'CLINIC_MANAGE_OPENING_HOURS',
                'APPOINTMENT_MANAGE_AVAILABILITY'
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
                  or
                  (
                      p_capability = 'APPOINTMENT_MANAGE_AVAILABILITY'
                      and grant_record.responsibility = 'RECEPTIONIST'
                      and (
                          (
                              grant_record.scope_type = 'ORGANIZATION'
                              and grant_record.clinic_id is null
                          )
                          or
                          (
                              grant_record.scope_type = 'CLINIC'
                              and grant_record.clinic_id = p_clinic_id
                          )
                      )
                  )
              )
        )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 2. Authoritative Slice 8 tables
-- ==================================================================

create table public.clinic_appointment_availability_periods (
    clinic_id uuid not null,
    iso_weekday smallint not null,
    start_time time without time zone not null,
    end_time time without time zone not null,
    constraint clinic_appointment_availability_periods_pkey
        primary key (
            clinic_id,
            iso_weekday,
            start_time,
            end_time
        ),
    constraint clinic_appointment_availability_periods_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_appointment_availability_periods_iso_weekday_check
        check (iso_weekday between 1 and 7),
    constraint clinic_appointment_availability_periods_interval_check
        check (start_time < end_time)
);

create table public.clinic_appointment_availability_exceptions (
    id uuid not null default gen_random_uuid(),
    clinic_id uuid not null,
    local_date date not null,
    exception_kind text not null,
    start_time time without time zone,
    end_time time without time zone,
    constraint clinic_appointment_availability_exceptions_pkey
        primary key (id),
    constraint clinic_appointment_availability_exceptions_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_appointment_availability_exceptions_date_finite_check
        check (
            local_date <> 'infinity'::date
            and local_date <> '-infinity'::date
        ),
    constraint clinic_appointment_availability_exceptions_kind_check
        check (exception_kind in ('CLOSED', 'OPEN')),
    constraint clinic_appointment_availability_exceptions_shape_check
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

create unique index clinic_appointment_availability_exceptions_closed_date_key
on public.clinic_appointment_availability_exceptions (clinic_id, local_date)
where exception_kind = 'CLOSED';

create unique index clinic_appointment_availability_exceptions_open_exact_key
on public.clinic_appointment_availability_exceptions (
    clinic_id,
    local_date,
    start_time,
    end_time
)
where exception_kind = 'OPEN';

create index clinic_appointment_availability_exceptions_clinic_date_idx
on public.clinic_appointment_availability_exceptions (clinic_id, local_date);

create table public.veterinarian_availability_periods (
    veterinarian_clinic_assignment_id uuid not null,
    iso_weekday smallint not null,
    start_time time without time zone not null,
    end_time time without time zone not null,
    constraint veterinarian_availability_periods_pkey
        primary key (
            veterinarian_clinic_assignment_id,
            iso_weekday,
            start_time,
            end_time
        ),
    constraint veterinarian_availability_periods_assignment_id_fkey
        foreign key (veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint veterinarian_availability_periods_iso_weekday_check
        check (iso_weekday between 1 and 7),
    constraint veterinarian_availability_periods_interval_check
        check (start_time < end_time)
);

create table public.veterinarian_availability_exceptions (
    id uuid not null default gen_random_uuid(),
    veterinarian_clinic_assignment_id uuid not null,
    local_date date not null,
    exception_kind text not null,
    start_time time without time zone,
    end_time time without time zone,
    constraint veterinarian_availability_exceptions_pkey
        primary key (id),
    constraint veterinarian_availability_exceptions_assignment_id_fkey
        foreign key (veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint veterinarian_availability_exceptions_date_finite_check
        check (
            local_date <> 'infinity'::date
            and local_date <> '-infinity'::date
        ),
    constraint veterinarian_availability_exceptions_kind_check
        check (exception_kind in ('CLOSED', 'OPEN')),
    constraint veterinarian_availability_exceptions_shape_check
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

create unique index veterinarian_availability_exceptions_closed_date_key
on public.veterinarian_availability_exceptions (
    veterinarian_clinic_assignment_id,
    local_date
)
where exception_kind = 'CLOSED';

create unique index veterinarian_availability_exceptions_open_exact_key
on public.veterinarian_availability_exceptions (
    veterinarian_clinic_assignment_id,
    local_date,
    start_time,
    end_time
)
where exception_kind = 'OPEN';

create index veterinarian_availability_exceptions_assignment_date_idx
on public.veterinarian_availability_exceptions (
    veterinarian_clinic_assignment_id,
    local_date
);

-- ==================================================================
-- 3. Lock-context triggers
--    Clinic-scoped tables reuse the existing generic
--    lock_clinic_configuration_context() unmodified.
--    Assignment-scoped tables use a new analogous function.
-- ==================================================================

create trigger clinic_appointment_availability_periods_lock_context
before insert or update or delete on public.clinic_appointment_availability_periods
for each row
execute function public.lock_clinic_configuration_context();

create trigger clinic_appointment_availability_exceptions_lock_context
before insert or update or delete on public.clinic_appointment_availability_exceptions
for each row
execute function public.lock_clinic_configuration_context();

create function public.lock_veterinarian_availability_configuration_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_assignment_id uuid;
begin
    if tg_op = 'UPDATE'
       and old.veterinarian_clinic_assignment_id
           is distinct from new.veterinarian_clinic_assignment_id then
        raise exception 'Veterinarian Availability configuration cannot be reassigned to another Clinic Assignment'
            using errcode = '23514';
    end if;

    if tg_op = 'DELETE' then
        target_assignment_id := old.veterinarian_clinic_assignment_id;
    else
        target_assignment_id := new.veterinarian_clinic_assignment_id;
    end if;

    perform 1
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = target_assignment_id
    for update;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.lock_veterinarian_availability_configuration_context()
from public, anon, authenticated;

create trigger veterinarian_availability_periods_lock_context
before insert or update or delete on public.veterinarian_availability_periods
for each row
execute function public.lock_veterinarian_availability_configuration_context();

create trigger veterinarian_availability_exceptions_lock_context
before insert or update or delete on public.veterinarian_availability_exceptions
for each row
execute function public.lock_veterinarian_availability_configuration_context();

-- ==================================================================
-- 4. Establishment-time Veterinarian Clinic Assignment currentness
--    (immediate BEFORE INSERT trigger — not a permanent post-insert
--    invariant; ending an Assignment later never touches these rows).
-- ==================================================================

create function public.assert_veterinarian_availability_establishment(
    p_veterinarian_clinic_assignment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_clinic_id uuid;
    resolved_organization_id uuid;
begin
    select assignment.clinic_id, clinic.organization_id
    into resolved_clinic_id, resolved_organization_id
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_veterinarian_clinic_assignment_id;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = resolved_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id
      and clinic.organization_id = resolved_organization_id
    for update;

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
    for update;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if not public.veterinarian_clinic_assignment_is_current(
        p_veterinarian_clinic_assignment_id
    ) then
        raise exception 'New Veterinarian Availability requires a currently valid Clinic Assignment'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_veterinarian_availability_establishment(uuid)
from public, anon, authenticated;

create function public.enforce_veterinarian_availability_establishment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_veterinarian_availability_establishment(
        new.veterinarian_clinic_assignment_id
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_availability_establishment()
from public, anon, authenticated;

create trigger veterinarian_availability_periods_establishment
before insert on public.veterinarian_availability_periods
for each row
execute function public.enforce_veterinarian_availability_establishment();

create trigger veterinarian_availability_exceptions_establishment
before insert on public.veterinarian_availability_exceptions
for each row
execute function public.enforce_veterinarian_availability_establishment();

-- ==================================================================
-- 5. Overlap and exception-coherence integrity (deferred, reusing the
--    Slice 6 architecture: lock the owning row, then evaluate the
--    final committed set at commit time).
-- ==================================================================

create function public.assert_clinic_appointment_availability_period_integrity(
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
        from public.clinic_appointment_availability_periods as first_period
        join public.clinic_appointment_availability_periods as second_period
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
        raise exception 'Clinic Appointment Availability Periods must not overlap'
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_appointment_availability_period_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_clinic_appointment_availability_period_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        perform public.assert_clinic_appointment_availability_period_integrity(
            new.clinic_id
        );
    elsif tg_op = 'DELETE' then
        perform public.assert_clinic_appointment_availability_period_integrity(
            old.clinic_id
        );
    elsif tg_op = 'UPDATE' then
        perform public.assert_clinic_appointment_availability_period_integrity(
            old.clinic_id
        );
        if old.clinic_id is distinct from new.clinic_id then
            perform public.assert_clinic_appointment_availability_period_integrity(
                new.clinic_id
            );
        end if;
    else
        raise exception 'Unexpected Clinic Appointment Availability Period integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinic_appointment_availability_period_integrity()
from public, anon, authenticated;

create function public.assert_clinic_appointment_availability_exception_integrity(
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
        from public.clinic_appointment_availability_exceptions as closed_exception
        where closed_exception.clinic_id = p_clinic_id
          and closed_exception.local_date = p_local_date
          and closed_exception.exception_kind = 'CLOSED'
    ) and exists (
        select 1
        from public.clinic_appointment_availability_exceptions as open_exception
        where open_exception.clinic_id = p_clinic_id
          and open_exception.local_date = p_local_date
          and open_exception.exception_kind = 'OPEN'
    ) then
        raise exception 'Clinic Appointment Availability Exception cannot combine CLOSED and OPEN interpretations'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.clinic_appointment_availability_exceptions as first_exception
        join public.clinic_appointment_availability_exceptions as second_exception
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
        raise exception 'Clinic Appointment Availability Exception periods must not overlap'
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_appointment_availability_exception_integrity(uuid, date)
from public, anon, authenticated;

create function public.enforce_clinic_appointment_availability_exception_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        perform public.assert_clinic_appointment_availability_exception_integrity(
            new.clinic_id,
            new.local_date
        );
    elsif tg_op = 'DELETE' then
        perform public.assert_clinic_appointment_availability_exception_integrity(
            old.clinic_id,
            old.local_date
        );
    elsif tg_op = 'UPDATE' then
        perform public.assert_clinic_appointment_availability_exception_integrity(
            old.clinic_id,
            old.local_date
        );
        if old.clinic_id is distinct from new.clinic_id
           or old.local_date is distinct from new.local_date then
            perform public.assert_clinic_appointment_availability_exception_integrity(
                new.clinic_id,
                new.local_date
            );
        end if;
    else
        raise exception 'Unexpected Clinic Appointment Availability Exception integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinic_appointment_availability_exception_integrity()
from public, anon, authenticated;

create function public.assert_veterinarian_availability_period_integrity(
    p_veterinarian_clinic_assignment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
    for update;

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.veterinarian_availability_periods as first_period
        join public.veterinarian_availability_periods as second_period
          on second_period.veterinarian_clinic_assignment_id
             = first_period.veterinarian_clinic_assignment_id
         and second_period.iso_weekday = first_period.iso_weekday
         and (
             first_period.start_time,
             first_period.end_time
         ) < (
             second_period.start_time,
             second_period.end_time
         )
        where first_period.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and first_period.start_time < second_period.end_time
          and second_period.start_time < first_period.end_time
    ) then
        raise exception 'Veterinarian Availability Periods must not overlap'
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_veterinarian_availability_period_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_veterinarian_availability_period_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        perform public.assert_veterinarian_availability_period_integrity(
            new.veterinarian_clinic_assignment_id
        );
    elsif tg_op = 'DELETE' then
        perform public.assert_veterinarian_availability_period_integrity(
            old.veterinarian_clinic_assignment_id
        );
    elsif tg_op = 'UPDATE' then
        perform public.assert_veterinarian_availability_period_integrity(
            old.veterinarian_clinic_assignment_id
        );
        if old.veterinarian_clinic_assignment_id
           is distinct from new.veterinarian_clinic_assignment_id then
            perform public.assert_veterinarian_availability_period_integrity(
                new.veterinarian_clinic_assignment_id
            );
        end if;
    else
        raise exception 'Unexpected Veterinarian Availability Period integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_availability_period_integrity()
from public, anon, authenticated;

create function public.assert_veterinarian_availability_exception_integrity(
    p_veterinarian_clinic_assignment_id uuid,
    p_local_date date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
    for update;

    if not found then
        return;
    end if;

    if exists (
        select 1
        from public.veterinarian_availability_exceptions as closed_exception
        where closed_exception.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and closed_exception.local_date = p_local_date
          and closed_exception.exception_kind = 'CLOSED'
    ) and exists (
        select 1
        from public.veterinarian_availability_exceptions as open_exception
        where open_exception.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and open_exception.local_date = p_local_date
          and open_exception.exception_kind = 'OPEN'
    ) then
        raise exception 'Veterinarian Availability Exception cannot combine CLOSED and OPEN interpretations'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.veterinarian_availability_exceptions as first_exception
        join public.veterinarian_availability_exceptions as second_exception
          on second_exception.veterinarian_clinic_assignment_id
             = first_exception.veterinarian_clinic_assignment_id
         and second_exception.local_date = first_exception.local_date
         and second_exception.exception_kind = 'OPEN'
         and first_exception.id < second_exception.id
        where first_exception.veterinarian_clinic_assignment_id
                  = p_veterinarian_clinic_assignment_id
          and first_exception.local_date = p_local_date
          and first_exception.exception_kind = 'OPEN'
          and first_exception.start_time < second_exception.end_time
          and second_exception.start_time < first_exception.end_time
    ) then
        raise exception 'Veterinarian Availability Exception periods must not overlap'
            using errcode = '23P01';
    end if;
end;
$$;

revoke all privileges
on function public.assert_veterinarian_availability_exception_integrity(uuid, date)
from public, anon, authenticated;

create function public.enforce_veterinarian_availability_exception_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        perform public.assert_veterinarian_availability_exception_integrity(
            new.veterinarian_clinic_assignment_id,
            new.local_date
        );
    elsif tg_op = 'DELETE' then
        perform public.assert_veterinarian_availability_exception_integrity(
            old.veterinarian_clinic_assignment_id,
            old.local_date
        );
    elsif tg_op = 'UPDATE' then
        perform public.assert_veterinarian_availability_exception_integrity(
            old.veterinarian_clinic_assignment_id,
            old.local_date
        );
        if old.veterinarian_clinic_assignment_id
               is distinct from new.veterinarian_clinic_assignment_id
           or old.local_date is distinct from new.local_date then
            perform public.assert_veterinarian_availability_exception_integrity(
                new.veterinarian_clinic_assignment_id,
                new.local_date
            );
        end if;
    else
        raise exception 'Unexpected Veterinarian Availability Exception integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_availability_exception_integrity()
from public, anon, authenticated;

-- ==================================================================
-- 6. Timezone-dependency integrity — extend the actual deployed
--    assert_clinic_timezone_dependency(uuid) to include all four
--    Slice 8 structures. Opening Hours behavior is unchanged.
-- ==================================================================

create or replace function public.assert_clinic_timezone_dependency(
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
        or exists (
            select 1
            from public.clinic_appointment_availability_periods as period
            where period.clinic_id = p_clinic_id
        )
        or exists (
            select 1
            from public.clinic_appointment_availability_exceptions as exception_record
            where exception_record.clinic_id = p_clinic_id
        )
        or exists (
            select 1
            from public.veterinarian_availability_periods as period
            join public.veterinarian_clinic_assignments as assignment
              on assignment.id = period.veterinarian_clinic_assignment_id
            where assignment.clinic_id = p_clinic_id
        )
        or exists (
            select 1
            from public.veterinarian_availability_exceptions as exception_record
            join public.veterinarian_clinic_assignments as assignment
              on assignment.id = exception_record.veterinarian_clinic_assignment_id
            where assignment.clinic_id = p_clinic_id
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

create function public.enforce_veterinarian_availability_timezone_dependency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_assignment_id uuid;
    resolved_clinic_id uuid;
begin
    if tg_op = 'DELETE' then
        target_assignment_id := old.veterinarian_clinic_assignment_id;
    else
        target_assignment_id := new.veterinarian_clinic_assignment_id;
    end if;

    select assignment.clinic_id
    into resolved_clinic_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = target_assignment_id;

    if found then
        perform public.assert_clinic_timezone_dependency(resolved_clinic_id);
    end if;

    if tg_op = 'UPDATE'
       and old.veterinarian_clinic_assignment_id
           is distinct from new.veterinarian_clinic_assignment_id then
        select assignment.clinic_id
        into resolved_clinic_id
        from public.veterinarian_clinic_assignments as assignment
        where assignment.id = new.veterinarian_clinic_assignment_id;

        if found then
            perform public.assert_clinic_timezone_dependency(resolved_clinic_id);
        end if;
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_availability_timezone_dependency()
from public, anon, authenticated;

-- ==================================================================
-- 7. Deferred constraint triggers — timezone dependency and overlap
--    integrity for all four new tables.
-- ==================================================================

create constraint trigger clinic_appointment_availability_periods_tz_dependency
after insert or update or delete on public.clinic_appointment_availability_periods
deferrable initially deferred
for each row
execute function public.enforce_clinic_timezone_dependency();

create constraint trigger clinic_appointment_availability_exceptions_tz_dependency
after insert or update or delete on public.clinic_appointment_availability_exceptions
deferrable initially deferred
for each row
execute function public.enforce_clinic_timezone_dependency();

create constraint trigger veterinarian_availability_periods_tz_dependency
after insert or update or delete on public.veterinarian_availability_periods
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_availability_timezone_dependency();

create constraint trigger veterinarian_availability_exceptions_tz_dependency
after insert or update or delete on public.veterinarian_availability_exceptions
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_availability_timezone_dependency();

create constraint trigger clinic_appointment_availability_periods_overlap
after insert or update or delete on public.clinic_appointment_availability_periods
deferrable initially deferred
for each row
execute function public.enforce_clinic_appointment_availability_period_integrity();

create constraint trigger clinic_appointment_availability_exceptions_coherence
after insert or update or delete on public.clinic_appointment_availability_exceptions
deferrable initially deferred
for each row
execute function public.enforce_clinic_appointment_availability_exception_integrity();

create constraint trigger veterinarian_availability_periods_overlap
after insert or update or delete on public.veterinarian_availability_periods
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_availability_period_integrity();

create constraint trigger veterinarian_availability_exceptions_coherence
after insert or update or delete on public.veterinarian_availability_exceptions
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_availability_exception_integrity();

-- ==================================================================
-- 8. RLS / privilege boundary
-- ==================================================================

alter table public.clinic_appointment_availability_periods enable row level security;
alter table public.clinic_appointment_availability_exceptions enable row level security;
alter table public.veterinarian_availability_periods enable row level security;
alter table public.veterinarian_availability_exceptions enable row level security;

revoke all privileges on table public.clinic_appointment_availability_periods
from public, anon, authenticated;
revoke all privileges on table public.clinic_appointment_availability_exceptions
from public, anon, authenticated;
revoke all privileges on table public.veterinarian_availability_periods
from public, anon, authenticated;
revoke all privileges on table public.veterinarian_availability_exceptions
from public, anon, authenticated;

-- ==================================================================
-- 9. Shared mutation-authorization helpers (lock order:
--    Organization -> PROFESSIONAL_SCHEDULING -> Clinic ->
--    APPOINTMENT_MANAGE_AVAILABILITY -> [Assignment]).
-- ==================================================================

create function public.assert_clinic_scheduling_authorization_after_lock(
    p_user_id uuid,
    p_clinic_id uuid
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
        'APPOINTMENT_MANAGE_AVAILABILITY'
    ) then
        raise exception 'Applicable Appointment Availability-management capability is required'
            using errcode = '42501';
    end if;

    if not public.organization_has_professional_entitlement(
        target_organization_id,
        'PROFESSIONAL_SCHEDULING'
    ) then
        raise exception 'Professional scheduling Entitlement is required'
            using errcode = '42501';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_scheduling_authorization_after_lock(uuid, uuid)
from public, anon, authenticated;

create function public.assert_veterinarian_scheduling_authorization_after_lock(
    p_user_id uuid,
    p_veterinarian_clinic_assignment_id uuid,
    p_require_current boolean
)
returns table (
    target_clinic_id uuid,
    target_organization_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_clinic_id uuid;
    resolved_organization_id uuid;
begin
    select assignment.clinic_id, clinic.organization_id
    into resolved_clinic_id, resolved_organization_id
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_veterinarian_clinic_assignment_id;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = resolved_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id
      and clinic.organization_id = resolved_organization_id
    for update;

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if not public.user_has_clinic_capability(
        p_user_id,
        resolved_clinic_id,
        'APPOINTMENT_MANAGE_AVAILABILITY'
    ) then
        raise exception 'Applicable Appointment Availability-management capability is required'
            using errcode = '42501';
    end if;

    if not public.organization_has_professional_entitlement(
        resolved_organization_id,
        'PROFESSIONAL_SCHEDULING'
    ) then
        raise exception 'Professional scheduling Entitlement is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
    for update;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if p_require_current
       and not public.veterinarian_clinic_assignment_is_current(
           p_veterinarian_clinic_assignment_id
       ) then
        raise exception 'Veterinarian Clinic Assignment must be currently valid to establish new Availability'
            using errcode = '23514';
    end if;

    return query
    select resolved_clinic_id, resolved_organization_id;
end;
$$;

revoke all privileges
on function public.assert_veterinarian_scheduling_authorization_after_lock(uuid, uuid, boolean)
from public, anon, authenticated;

-- ==================================================================
-- 10. Timezone mutation — approved BR-56 conditional Entitlement gate.
--     Signature and prior CLINIC_MANAGE_OPENING_HOURS-only behavior are
--     preserved for Clinics with no currently effective Availability.
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
    normalized_timezone_name text;
    clinic_organization_id uuid;
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

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

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

-- ==================================================================
-- 11. Clinic Appointment Availability mutation RPCs
-- ==================================================================

create function public.replace_clinic_appointment_availability(
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

    perform public.assert_clinic_scheduling_authorization_after_lock(
        acting_user_id,
        p_clinic_id
    );

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

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.replace_clinic_appointment_availability(uuid, jsonb)
from public, anon, authenticated;

grant execute
on function public.replace_clinic_appointment_availability(uuid, jsonb)
to authenticated;

create function public.set_clinic_appointment_availability_exception(
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

    perform public.assert_clinic_scheduling_authorization_after_lock(
        acting_user_id,
        p_clinic_id
    );

    if p_local_date is null
       or p_local_date = 'infinity'::date
       or p_local_date = '-infinity'::date then
        raise exception 'Clinic Appointment Availability Exception local date must be a finite date'
            using errcode = '22023';
    end if;

    if p_exception_kind not in ('CLOSED', 'OPEN')
       or p_exception_kind is null then
        raise exception 'Clinic Appointment Availability Exception kind must be CLOSED or OPEN'
            using errcode = '22023';
    end if;

    if jsonb_typeof(p_periods) is distinct from 'array' then
        raise exception 'Clinic Appointment Availability Exception periods must be a JSON array'
            using errcode = '22023';
    end if;

    if p_exception_kind = 'CLOSED'
       and jsonb_array_length(p_periods) <> 0 then
        raise exception 'CLOSED Clinic Appointment Availability Exception must not contain periods'
            using errcode = '22023';
    end if;

    if p_exception_kind = 'OPEN'
       and jsonb_array_length(p_periods) = 0 then
        raise exception 'OPEN Clinic Appointment Availability Exception requires at least one period'
            using errcode = '22023';
    end if;

    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not public.clinic_timezone_name_is_valid(
        clinic_timezone_name
    ) then
        raise exception 'Clinic Appointment Availability Exception requires a valid scheduling timezone'
            using errcode = '23514';
    end if;

    if p_exception_kind = 'OPEN' then
        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            where jsonb_typeof(period.item) is distinct from 'object'
        ) then
            raise exception 'Every Clinic Appointment Availability Exception period must be a JSON object'
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
            raise exception 'Every Clinic Appointment Availability Exception period requires valid start_time and end_time members'
                using errcode = '22023';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            cross join lateral jsonb_object_keys(period.item) as member(key)
            where member.key not in ('start_time', 'end_time')
        ) then
            raise exception 'Clinic Appointment Availability Exception period contains an unsupported member'
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
            raise exception 'Clinic Appointment Availability Exception period must have start_time before end_time'
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
            raise exception 'Clinic Appointment Availability Exception periods must not contain duplicates'
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
            raise exception 'Clinic Appointment Availability Exception periods must not overlap'
                using errcode = '23P01';
        end if;
    end if;

    delete from public.clinic_appointment_availability_exceptions as existing_exception
    where existing_exception.clinic_id = p_clinic_id
      and existing_exception.local_date = p_local_date;

    if p_exception_kind = 'CLOSED' then
        insert into public.clinic_appointment_availability_exceptions (
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
        insert into public.clinic_appointment_availability_exceptions (
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
on function public.set_clinic_appointment_availability_exception(uuid, date, text, jsonb)
from public, anon, authenticated;

grant execute
on function public.set_clinic_appointment_availability_exception(uuid, date, text, jsonb)
to authenticated;

create function public.clear_clinic_appointment_availability_exception(
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

    perform public.assert_clinic_scheduling_authorization_after_lock(
        acting_user_id,
        p_clinic_id
    );

    if p_local_date is null then
        raise exception 'Clinic Appointment Availability Exception local date is required'
            using errcode = '22023';
    end if;

    delete from public.clinic_appointment_availability_exceptions as existing_exception
    where existing_exception.clinic_id = p_clinic_id
      and existing_exception.local_date = p_local_date;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.clear_clinic_appointment_availability_exception(uuid, date)
from public, anon, authenticated;

grant execute
on function public.clear_clinic_appointment_availability_exception(uuid, date)
to authenticated;

-- ==================================================================
-- 12. Veterinarian Availability mutation RPCs
-- ==================================================================

create function public.replace_veterinarian_availability(
    p_veterinarian_clinic_assignment_id uuid,
    p_periods jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
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

    select authorization_result.target_clinic_id
    into resolved_clinic_id
    from public.assert_veterinarian_scheduling_authorization_after_lock(
        acting_user_id,
        p_veterinarian_clinic_assignment_id,
        true
    ) as authorization_result;

    if jsonb_typeof(p_periods) is distinct from 'array' then
        raise exception 'Veterinarian Availability must be a JSON array'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where jsonb_typeof(period.item) is distinct from 'object'
    ) then
        raise exception 'Every Veterinarian Availability Period must be a JSON object'
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
        raise exception 'Every Veterinarian Availability Period requires valid iso_weekday, start_time, and end_time members'
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
        raise exception 'Veterinarian Availability Period contains an unsupported member'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_periods) as period(item)
        where period.item ->> 'iso_weekday' !~ '^[1-7]$'
    ) then
        raise exception 'Veterinarian Availability Period ISO weekday must be between 1 and 7'
            using errcode = '22023';
    end if;

    if jsonb_array_length(p_periods) > 0 then
        select clinic.scheduling_timezone_name
        into clinic_timezone_name
        from public.clinics as clinic
        where clinic.id = resolved_clinic_id;

        if not public.clinic_timezone_name_is_valid(
            clinic_timezone_name
        ) then
            raise exception 'Veterinarian Availability requires a valid Clinic scheduling timezone'
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
        raise exception 'Veterinarian Availability Period must have start_time before end_time'
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
        raise exception 'Veterinarian Availability Periods must not contain duplicates'
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
        raise exception 'Veterinarian Availability Periods must not overlap'
            using errcode = '23P01';
    end if;

    delete from public.veterinarian_availability_periods as existing_period
    where existing_period.veterinarian_clinic_assignment_id
              = p_veterinarian_clinic_assignment_id;

    insert into public.veterinarian_availability_periods (
        veterinarian_clinic_assignment_id,
        iso_weekday,
        start_time,
        end_time
    )
    select
        p_veterinarian_clinic_assignment_id,
        (period.item ->> 'iso_weekday')::smallint,
        public.parse_clinic_local_time(period.item ->> 'start_time'),
        public.parse_clinic_local_time(period.item ->> 'end_time')
    from jsonb_array_elements(p_periods) as period(item);

    return p_veterinarian_clinic_assignment_id;
end;
$$;

revoke all privileges
on function public.replace_veterinarian_availability(uuid, jsonb)
from public, anon, authenticated;

grant execute
on function public.replace_veterinarian_availability(uuid, jsonb)
to authenticated;

create function public.set_veterinarian_availability_exception(
    p_veterinarian_clinic_assignment_id uuid,
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
    resolved_clinic_id uuid;
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

    select authorization_result.target_clinic_id
    into resolved_clinic_id
    from public.assert_veterinarian_scheduling_authorization_after_lock(
        acting_user_id,
        p_veterinarian_clinic_assignment_id,
        true
    ) as authorization_result;

    if p_local_date is null
       or p_local_date = 'infinity'::date
       or p_local_date = '-infinity'::date then
        raise exception 'Veterinarian Availability Exception local date must be a finite date'
            using errcode = '22023';
    end if;

    if p_exception_kind not in ('CLOSED', 'OPEN')
       or p_exception_kind is null then
        raise exception 'Veterinarian Availability Exception kind must be CLOSED or OPEN'
            using errcode = '22023';
    end if;

    if jsonb_typeof(p_periods) is distinct from 'array' then
        raise exception 'Veterinarian Availability Exception periods must be a JSON array'
            using errcode = '22023';
    end if;

    if p_exception_kind = 'CLOSED'
       and jsonb_array_length(p_periods) <> 0 then
        raise exception 'CLOSED Veterinarian Availability Exception must not contain periods'
            using errcode = '22023';
    end if;

    if p_exception_kind = 'OPEN'
       and jsonb_array_length(p_periods) = 0 then
        raise exception 'OPEN Veterinarian Availability Exception requires at least one period'
            using errcode = '22023';
    end if;

    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = resolved_clinic_id;

    if not public.clinic_timezone_name_is_valid(
        clinic_timezone_name
    ) then
        raise exception 'Veterinarian Availability Exception requires a valid Clinic scheduling timezone'
            using errcode = '23514';
    end if;

    if p_exception_kind = 'OPEN' then
        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            where jsonb_typeof(period.item) is distinct from 'object'
        ) then
            raise exception 'Every Veterinarian Availability Exception period must be a JSON object'
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
            raise exception 'Every Veterinarian Availability Exception period requires valid start_time and end_time members'
                using errcode = '22023';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(p_periods) as period(item)
            cross join lateral jsonb_object_keys(period.item) as member(key)
            where member.key not in ('start_time', 'end_time')
        ) then
            raise exception 'Veterinarian Availability Exception period contains an unsupported member'
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
            raise exception 'Veterinarian Availability Exception period must have start_time before end_time'
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
            raise exception 'Veterinarian Availability Exception periods must not contain duplicates'
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
            raise exception 'Veterinarian Availability Exception periods must not overlap'
                using errcode = '23P01';
        end if;
    end if;

    delete from public.veterinarian_availability_exceptions as existing_exception
    where existing_exception.veterinarian_clinic_assignment_id
              = p_veterinarian_clinic_assignment_id
      and existing_exception.local_date = p_local_date;

    if p_exception_kind = 'CLOSED' then
        insert into public.veterinarian_availability_exceptions (
            veterinarian_clinic_assignment_id,
            local_date,
            exception_kind
        )
        values (
            p_veterinarian_clinic_assignment_id,
            p_local_date,
            'CLOSED'
        );
    else
        insert into public.veterinarian_availability_exceptions (
            veterinarian_clinic_assignment_id,
            local_date,
            exception_kind,
            start_time,
            end_time
        )
        select
            p_veterinarian_clinic_assignment_id,
            p_local_date,
            'OPEN',
            public.parse_clinic_local_time(period.item ->> 'start_time'),
            public.parse_clinic_local_time(period.item ->> 'end_time')
        from jsonb_array_elements(p_periods) as period(item);
    end if;

    return p_veterinarian_clinic_assignment_id;
end;
$$;

revoke all privileges
on function public.set_veterinarian_availability_exception(uuid, date, text, jsonb)
from public, anon, authenticated;

grant execute
on function public.set_veterinarian_availability_exception(uuid, date, text, jsonb)
to authenticated;

create function public.clear_veterinarian_availability_exception(
    p_veterinarian_clinic_assignment_id uuid,
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

    perform public.assert_veterinarian_scheduling_authorization_after_lock(
        acting_user_id,
        p_veterinarian_clinic_assignment_id,
        false
    );

    if p_local_date is null then
        raise exception 'Veterinarian Availability Exception local date is required'
            using errcode = '22023';
    end if;

    delete from public.veterinarian_availability_exceptions as existing_exception
    where existing_exception.veterinarian_clinic_assignment_id
              = p_veterinarian_clinic_assignment_id
      and existing_exception.local_date = p_local_date;

    return p_veterinarian_clinic_assignment_id;
end;
$$;

revoke all privileges
on function public.clear_veterinarian_availability_exception(uuid, date)
from public, anon, authenticated;

grant execute
on function public.clear_veterinarian_availability_exception(uuid, date)
to authenticated;

-- ==================================================================
-- 13. Authenticated management reads — no PROFESSIONAL_SCHEDULING
--     requirement (SPEC-SUB-003: safe understanding/resolution reads
--     are not new paid scheduling activity).
-- ==================================================================

create function public.get_managed_clinic_appointment_availability(
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
        'APPOINTMENT_MANAGE_AVAILABILITY'
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

create function public.get_managed_veterinarian_availability(
    p_veterinarian_clinic_assignment_id uuid
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

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    perform public.assert_clinic_capability_after_lock(
        acting_user_id,
        resolved_clinic_id,
        'APPOINTMENT_MANAGE_AVAILABILITY'
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

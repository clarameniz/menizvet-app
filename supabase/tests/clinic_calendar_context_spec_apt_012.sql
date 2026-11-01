-- Professional calendar context (SPEC-APT-012 §14, BR-60, Verification Notes
-- 80–82), migration 20261110090000_clinic_calendar_context.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deliberately minimal deterministic
-- context and to switch between impersonated Users (same rationale as
-- clinic_appointment_calendar_reads_spec_apt_012.sql).
--
-- Covers:
--   * contract, attributes and ACLs of the read and its internal helper;
--     earlier reads unchanged;
--   * authority: Owner, Administrators, Receptionists (Organization and
--     Clinic scope), a Veterinarian with a current Assignment, an unpublished
--     Clinic; uniform 42501 for every other actor, another Clinic or
--     Organization, an unknown or null Clinic; 28000; anon;
--   * the date: statement instant in the Clinic's valid timezone, around local
--     midnight east and west of UTC, a year change, both daylight-saving
--     transitions, independent of the session timezone; null and invalid
--     timezones give two nulls;
--   * no side effects.
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_error(
    p_statement text, p_expected_sqlstate text, p_expected_message_fragment text
)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected_sqlstate
           and (p_expected_message_fragment is null
                or position(p_expected_message_fragment in sqlerrm) > 0) then
            return;
        end if;
        raise exception 'Expected SQLSTATE % (%), received %: %',
            p_expected_sqlstate, p_expected_message_fragment, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected_sqlstate;
end;
$$;

create function pg_temp.id(p_kind text, p_n integer)
returns uuid language sql immutable as $$
    select ('c0ea0000-0000-4000-8000-000000000' || p_kind || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.act(p_subject integer)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id('1', p_subject)::text, true)
$$;

-- The read's rows for the impersonated actor, as text, e.g. {"(2035-03-10,Europe/Madrid)"}.
create function pg_temp.context(p_clinic_id uuid)
returns text[] language sql as $$
    select coalesce(array_agg(row(context.*)::text), '{}')
    from public.get_clinic_calendar_context(p_clinic_id) as context
$$;

-- What the read must return now for a valid timezone: the statement instant's
-- civil date there (same statement, so the same instant).
create function pg_temp.expected_now(p_timezone_name text)
returns text[] language sql stable as $$
    select array[row((statement_timestamp() at time zone p_timezone_name)::date, p_timezone_name)::text]
$$;

-- The internal helper at a chosen instant, as 'date|zone'.
create function pg_temp.at(p_clinic_id uuid, p_as_of timestamptz)
returns text language sql as $$
    select string_agg(coalesce(context.clinic_local_today::text, 'null') || '|'
                      || coalesce(context.scheduling_timezone_name, 'null'), ',')
    from public.clinic_calendar_context_at(p_clinic_id, p_as_of) as context
$$;

-- ===========================================================================
-- 1. Contract, attributes, ACLs.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_calendar_context(uuid)'::regprocedure)
    = 'TABLE(clinic_local_today date, scheduling_timezone_name text)'
    and pg_get_function_arguments('public.get_clinic_calendar_context(uuid)'::regprocedure)
    = 'p_clinic_id uuid'
    and (select count(*) = 1 from pg_proc where proname = 'get_clinic_calendar_context'),
    'Contract: one signature, only the local date and the timezone (BR-60)'
);

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""'])
     from pg_proc as proc
     where proc.oid in (
         'public.get_clinic_calendar_context(uuid)'::regprocedure,
         'public.clinic_calendar_context_at(uuid, timestamptz)'::regprocedure
     )),
    'Attributes: SECURITY DEFINER, STABLE, empty search_path'
);

select pg_temp.assert_true(
    (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                      order by acl_entry.grantee::regrole::text)
     from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
     where proc.oid = 'public.get_clinic_calendar_context(uuid)'::regprocedure
       and acl_entry.grantee <> proc.proowner)
    = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.get_clinic_calendar_context(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_clinic_calendar_context(uuid)', 'EXECUTE'),
    'ACL: executable only by authenticated (and service_role)'
);

select pg_temp.assert_true(
    not has_function_privilege('authenticated', 'public.clinic_calendar_context_at(uuid, timestamptz)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.clinic_calendar_context_at(uuid, timestamptz)', 'EXECUTE')
    and not has_function_privilege('public', 'public.clinic_calendar_context_at(uuid, timestamptz)', 'EXECUTE'),
    'ACL: the internal helper is not executable by clients'
);

-- Earlier reads keep one signature and their grants; the timezone rule stays
-- an internal helper with its signature.
select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc where proname = function_name)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.proname = function_name and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE'],
    'Compatibility: ' || function_name || ' keeps one signature and its grants'
)
from unnest(array[
    'get_clinic_appointment_schedule', 'get_clinic_appointment', 'get_clinic_appointment_month_counts',
    'get_clinic_appointment_day', 'get_clinic_appointment_pending',
    'get_clinic_appointment_pending_summary', 'get_clinic_appointment_history'
]) as function_name;

select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc where proname = 'clinic_timezone_name_is_valid')
    and pg_get_function_identity_arguments('public.clinic_timezone_name_is_valid(text)'::regprocedure) = 'p_timezone_name text'
    and not has_function_privilege('authenticated', 'public.clinic_timezone_name_is_valid(text)', 'EXECUTE'),
    'Compatibility: clinic_timezone_name_is_valid keeps its signature and stays internal'
);

-- ===========================================================================
-- Fixtures
--
-- Auth subjects …0001NN, domain Users …0002NN (the layout of the phase 1
-- suite):
--   01 Guardian                         06 OWNER (Organization) OrgA
--   07 ADMINISTRATOR (Organization)     08 ADMINISTRATOR (Clinic A1)
--   09 RECEPTIONIST (Organization)      10 RECEPTIONIST (Clinic A1)
--   11 VETERINARIAN, Assignment @ A1    12 VETERINARIAN, Assignment @ A2 only
--   13 VETERINARIAN, Assignment @ A1 ended
--   14 RECEPTIONIST (Clinic A2)         15 RECEPTIONIST (Organization), Membership ended
--   16 RECEPTIONIST (Clinic A1), Grant ended
--   17 ADMINISTRATOR (Organization) OrgB   18 bare OrgA Member
--   20 authenticated subject without domain User
-- OrgA (…0301) operates:
--   A1 (…0401) published,   Europe/Madrid
--   A2 (…0402) unpublished, America/New_York
--   A3 (…0403) unpublished, no timezone
--   A4 (…0404) unpublished, stored timezone 'Mars/Olympus' (invalid; a
--      fixture only — writes validate timezones)
--   A5 (…0405) unpublished, stored ' Europe/Madrid' (surrounding blank; invalid)
--   A6 (…0406) unpublished, Pacific/Kiritimati (UTC+14)
-- OrgB (…0302) operates B1 (…0411), Europe/Madrid.
-- ===========================================================================

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id('1', n), 'calendar-context' || n || '@example.test', '2020-01-01Z'
from generate_series(1, 20) as n
where n <> 19;

insert into public.users (id)
select pg_temp.id('2', n) from generate_series(1, 18) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id('2', n), pg_temp.id('1', n) from generate_series(1, 18) as n;

insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id('3', 1), 'Animalia Veterinary Group'),
    (pg_temp.id('3', 2), 'VetCare Group');

insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name) values
    (pg_temp.id('4', 1), pg_temp.id('3', 1), true, '2020-01-01Z', 'Europe/Madrid'),
    (pg_temp.id('4', 2), pg_temp.id('3', 1), false, '2020-01-01Z', 'America/New_York'),
    (pg_temp.id('4', 3), pg_temp.id('3', 1), false, '2020-01-01Z', null),
    (pg_temp.id('4', 4), pg_temp.id('3', 1), false, '2020-01-01Z', 'Mars/Olympus'),
    (pg_temp.id('4', 5), pg_temp.id('3', 1), false, '2020-01-01Z', ' Europe/Madrid'),
    (pg_temp.id('4', 6), pg_temp.id('3', 1), false, '2020-01-01Z', 'Pacific/Kiritimati'),
    (pg_temp.id('4', 11), pg_temp.id('3', 2), true, '2020-01-01Z', 'Europe/Madrid');

insert into public.organization_memberships (
    id, organization_id, user_id, effective_start, effective_end, ended_by_user_id
)
select pg_temp.id('5', n),
       case when n = 17 then pg_temp.id('3', 2) else pg_temp.id('3', 1) end,
       pg_temp.id('2', n),
       '2020-01-01Z',
       case when n = 15 then '2021-01-01Z'::timestamptz end,
       case when n = 15 then pg_temp.id('2', 6) end
from generate_series(6, 18) as n;

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
)
select pg_temp.id('6', grant_row.n), pg_temp.id('5', grant_row.n),
       grant_row.responsibility, grant_row.scope_type, grant_row.clinic_id,
       '2020-01-01Z', grant_row.effective_end::timestamptz, pg_temp.id('2', 6),
       case when grant_row.effective_end is not null then pg_temp.id('2', 6) end
from (values
    (6,  'OWNER',         'ORGANIZATION', null::uuid,         null),
    (7,  'ADMINISTRATOR', 'ORGANIZATION', null,               null),
    (8,  'ADMINISTRATOR', 'CLINIC',       pg_temp.id('4', 1), null),
    (9,  'RECEPTIONIST',  'ORGANIZATION', null,               null),
    (10, 'RECEPTIONIST',  'CLINIC',       pg_temp.id('4', 1), null),
    (11, 'VETERINARIAN',  'ORGANIZATION', null,               null),
    (12, 'VETERINARIAN',  'ORGANIZATION', null,               null),
    (13, 'VETERINARIAN',  'ORGANIZATION', null,               null),
    (14, 'RECEPTIONIST',  'CLINIC',       pg_temp.id('4', 2), null),
    (15, 'RECEPTIONIST',  'ORGANIZATION', null,               null),
    (16, 'RECEPTIONIST',  'CLINIC',       pg_temp.id('4', 1), '2021-01-01Z'),
    (17, 'ADMINISTRATOR', 'ORGANIZATION', null,               null)
) as grant_row (n, responsibility, scope_type, clinic_id, effective_end);

insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id('7', n), pg_temp.id('2', n) from generate_series(11, 13) as n;

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.id('8', 11), pg_temp.id('7', 11), pg_temp.id('5', 11), pg_temp.id('4', 1), '2020-01-01Z', null),
    (pg_temp.id('8', 12), pg_temp.id('7', 12), pg_temp.id('5', 12), pg_temp.id('4', 2), '2020-01-01Z', null),
    (pg_temp.id('8', 13), pg_temp.id('7', 13), pg_temp.id('5', 13), pg_temp.id('4', 1), '2020-01-01Z', '2021-01-01Z');

insert into public.pets (id, name, species, created_at)
values (pg_temp.id('9', 1), 'Luna', 'Dog', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end)
values (pg_temp.id('a', 1), pg_temp.id('2', 1), pg_temp.id('9', 1), '2020-01-01Z', null);

set local session_replication_role = origin;

create temporary table side_effect_baseline on commit drop as
select
    (select count(*) from public.clinics) as clinics,
    (select count(*) from public.transactional_communications) as communications,
    (select count(*) from public.medical_access_audit_events) as audit_events,
    (select count(*) from public.appointment_lifecycle_events) as lifecycle_events,
    (select string_agg(clinic.id::text || coalesce(clinic.scheduling_timezone_name, '∅'), ',' order by clinic.id)
     from public.clinics as clinic where clinic.organization_id in (pg_temp.id('3', 1), pg_temp.id('3', 2)))
        as clinic_timezones;

-- ===========================================================================
-- 2. Authority (VN 80).
-- ===========================================================================

-- Every schedule viewer of A1, Organization- and Clinic-scoped, and the
-- Veterinarian with a current Assignment there.
do $$
declare
    subject integer;
begin
    foreach subject in array array[6, 7, 8, 9, 10, 11] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        perform pg_temp.assert_true(
            pg_temp.context(pg_temp.id('4', 1)) = pg_temp.expected_now('Europe/Madrid'),
            'Authority: actor ' || subject || ' reads the A1 context: '
            || pg_temp.context(pg_temp.id('4', 1))::text
        );
        reset role;
    end loop;
end;
$$;

-- An unpublished Clinic: Organization-wide actors, its Clinic-scoped
-- Receptionist, and its assigned Veterinarian.
do $$
declare
    subject integer;
begin
    foreach subject in array array[6, 7, 9, 12, 14] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        perform pg_temp.assert_true(
            pg_temp.context(pg_temp.id('4', 2)) = pg_temp.expected_now('America/New_York'),
            'Authority: actor ' || subject || ' reads the unpublished A2 context'
        );
        reset role;
    end loop;
end;
$$;

-- Everyone else, for A1: a Veterinarian assigned elsewhere or no longer
-- assigned, another Clinic's Receptionist, ended Membership or Grant, another
-- Organization, a bare Member, a Guardian.
do $$
declare
    subject integer;
begin
    foreach subject in array array[12, 13, 14, 15, 16, 17, 18, 1] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        perform pg_temp.assert_error(
            format('select * from public.get_clinic_calendar_context(%L)', pg_temp.id('4', 1)),
            '42501', 'Applicable Appointment schedule-view capability is required'
        );
        reset role;
    end loop;
end;
$$;

-- Clinic-scoped actors of A1 are denied A2; an Owner is denied another
-- Organization's Clinic, an unknown Clinic and a null Clinic — one outcome.
do $$
declare
    case_row record;
begin
    for case_row in
        select * from (values
            (8, pg_temp.id('4', 2)), (10, pg_temp.id('4', 2)), (11, pg_temp.id('4', 2)),
            (6, pg_temp.id('4', 11)), (6, pg_temp.id('4', 99)), (6, null::uuid),
            (17, pg_temp.id('4', 99))
        ) as cases (subject, clinic_id)
    loop
        perform pg_temp.act(case_row.subject);
        set local role authenticated;
        perform pg_temp.assert_error(
            format('select * from public.get_clinic_calendar_context(%s)',
                   coalesce(quote_literal(case_row.clinic_id) || '::uuid', 'null::uuid')),
            '42501', 'Applicable Appointment schedule-view capability is required'
        );
        reset role;
    end loop;
end;
$$;

-- The denial carries no hint or detail.
do $$
declare
    error_hint text;
    error_detail text;
begin
    perform pg_temp.act(18);
    set local role authenticated;
    begin
        perform * from public.get_clinic_calendar_context(pg_temp.id('4', 1));
        raise exception 'Expected a denial';
    exception when insufficient_privilege then
        get stacked diagnostics error_hint = pg_exception_hint, error_detail = pg_exception_detail;
        perform pg_temp.assert_true(
            coalesce(error_hint, '') = '' and coalesce(error_detail, '') = '',
            'Authority: the uniform denial has no hint or detail'
        );
    end;
    reset role;
end;
$$;

-- No subject, no domain User, anon.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.get_clinic_calendar_context(%L)', pg_temp.id('4', 1)),
    '28000', 'Authentication is required'
);
reset role;

select pg_temp.act(20);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.get_clinic_calendar_context(%L)', pg_temp.id('4', 1)),
    '28000', 'No coherent domain User'
);
reset role;

select pg_temp.act(10);
set local role anon;
select pg_temp.assert_error(
    format('select * from public.get_clinic_calendar_context(%L)', pg_temp.id('4', 1)),
    '42501', 'permission denied'
);
reset role;

-- Clients cannot call the internal helper.
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.clinic_calendar_context_at(%L, now())', pg_temp.id('4', 1)),
    '42501', 'permission denied'
);
reset role;

-- ===========================================================================
-- 3. Null and invalid timezones (VN 81).
-- ===========================================================================

-- Exactly one row, both values null: no timezone, an unknown zone, and a zone
-- with surrounding blank (the validation rule is used unchanged).
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.context(clinic_id) = array['(,)'],
    'Timezone: Clinic ' || clinic_id || ' without a valid timezone gives one row of two nulls'
)
from unnest(array[pg_temp.id('4', 3), pg_temp.id('4', 4), pg_temp.id('4', 5)]) as clinic_id;
reset role;

select pg_temp.assert_true(
    pg_temp.at(pg_temp.id('4', 3), '2035-03-10T12:00:00Z') = 'null|null'
    and pg_temp.at(pg_temp.id('4', 4), '2035-03-10T12:00:00Z') = 'null|null'
    and pg_temp.at(pg_temp.id('4', 5), '2035-03-10T12:00:00Z') = 'null|null'
    and pg_temp.at(pg_temp.id('4', 99), '2035-03-10T12:00:00Z') is null,
    'Timezone: the helper gives two nulls without a valid timezone, and no row for an unknown Clinic'
);

-- ===========================================================================
-- 4. The local date (VN 81).
-- ===========================================================================

-- Local midnight east (Madrid, UTC+1 in winter; Kiritimati, UTC+14, including
-- a year change) and west (New York, UTC-5 in winter) of UTC.
select pg_temp.assert_true(
    pg_temp.at(pg_temp.id('4', 1), '2035-03-10T22:59:59Z') = '2035-03-10|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-03-10T23:00:00Z') = '2035-03-11|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 2), '2035-01-11T04:59:59Z') = '2035-01-10|America/New_York'
    and pg_temp.at(pg_temp.id('4', 2), '2035-01-11T05:00:00Z') = '2035-01-11|America/New_York'
    and pg_temp.at(pg_temp.id('4', 6), '2034-12-31T09:59:59Z') = '2034-12-31|Pacific/Kiritimati'
    and pg_temp.at(pg_temp.id('4', 6), '2034-12-31T10:00:00Z') = '2035-01-01|Pacific/Kiritimati',
    'Date: local midnight east and west of UTC, and a year change in UTC+14'
);

-- The same UTC instant is a different local date in different Clinics.
select pg_temp.assert_true(
    pg_temp.at(pg_temp.id('4', 1), '2035-01-10T23:30:00Z') = '2035-01-11|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 2), '2035-01-10T23:30:00Z') = '2035-01-10|America/New_York'
    and pg_temp.at(pg_temp.id('4', 6), '2035-01-10T23:30:00Z') = '2035-01-11|Pacific/Kiritimati',
    'Date: one instant, each Clinic''s own local date'
);

-- Daylight saving in Madrid, 2035: spring forward on Sunday 25 March (UTC+1
-- -> +2), fall back on Sunday 28 October (UTC+2 -> +1); New York springs
-- forward on Sunday 11 March (UTC-5 -> -4).
select pg_temp.assert_true(
    pg_temp.at(pg_temp.id('4', 1), '2035-03-24T22:59:59Z') = '2035-03-24|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-03-24T23:00:00Z') = '2035-03-25|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-03-25T21:59:59Z') = '2035-03-25|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-03-25T22:00:00Z') = '2035-03-26|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-10-27T21:59:59Z') = '2035-10-27|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-10-27T22:00:00Z') = '2035-10-28|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-10-28T22:59:59Z') = '2035-10-28|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 1), '2035-10-28T23:00:00Z') = '2035-10-29|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 2), '2035-03-11T04:59:59Z') = '2035-03-10|America/New_York'
    and pg_temp.at(pg_temp.id('4', 2), '2035-03-12T03:59:59Z') = '2035-03-11|America/New_York'
    and pg_temp.at(pg_temp.id('4', 2), '2035-03-12T04:00:00Z') = '2035-03-12|America/New_York',
    'Date: both daylight-saving transitions move local midnight by the offset'
);

-- The session timezone never changes the result, of the helper or the read.
set local timezone = 'Pacific/Kiritimati';
select pg_temp.assert_true(
    pg_temp.at(pg_temp.id('4', 1), '2035-03-10T22:59:59Z') = '2035-03-10|Europe/Madrid'
    and pg_temp.at(pg_temp.id('4', 2), '2035-01-11T04:59:59Z') = '2035-01-10|America/New_York',
    'Date: identical under a +14:00 session timezone'
);
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.context(pg_temp.id('4', 1)) = pg_temp.expected_now('Europe/Madrid')
    and pg_temp.context(pg_temp.id('4', 6)) = pg_temp.expected_now('Pacific/Kiritimati'),
    'Date: the read is identical under a +14:00 session timezone'
);
reset role;
set local timezone = 'America/Adak';
select pg_temp.assert_true(
    pg_temp.at(pg_temp.id('4', 6), '2034-12-31T10:00:00Z') = '2035-01-01|Pacific/Kiritimati',
    'Date: identical under a -10:00 session timezone'
);
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.context(pg_temp.id('4', 2)) = pg_temp.expected_now('America/New_York'),
    'Date: the read is identical under a -10:00 session timezone'
);
reset role;
reset timezone;

-- ===========================================================================
-- 5. No side effects (VN 82).
-- ===========================================================================

select pg_temp.assert_true(
    (select baseline.clinics = (select count(*) from public.clinics)
            and baseline.communications = (select count(*) from public.transactional_communications)
            and baseline.audit_events = (select count(*) from public.medical_access_audit_events)
            and baseline.lifecycle_events = (select count(*) from public.appointment_lifecycle_events)
            and baseline.clinic_timezones = (
                select string_agg(clinic.id::text || coalesce(clinic.scheduling_timezone_name, '∅'), ','
                                  order by clinic.id)
                from public.clinics as clinic
                where clinic.organization_id in (pg_temp.id('3', 1), pg_temp.id('3', 2)))
     from side_effect_baseline as baseline),
    'Side effects: no Clinic, timezone, Communication, Medical Access Audit Event or Lifecycle Event changes'
);

rollback;

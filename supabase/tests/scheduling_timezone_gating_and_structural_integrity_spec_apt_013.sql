-- Regression suite for scheduling-configuration behaviour that the
-- management-RPC suites do not reach:
--
--   A. SPEC-APT-013 BR-56 — changing the Clinic scheduling timezone through
--      set_clinic_scheduling_timezone(uuid, text) needs PROFESSIONAL_SCHEDULING
--      while Appointment Availability is "currently effective": any Clinic
--      recurring period; any Clinic exception that is not past; and, for a
--      currently valid Veterinarian Clinic Assignment, any recurring period or
--      exception that is not past. An exception is past only when its local
--      date is before the current local date under both the current and the
--      requested timezone (20261018090000); every exception counts while the
--      current timezone is not valid;
--   B. structural integrity of the Clinic Appointment Availability tables
--      when the RPC layer is bypassed (privileged direct writes): CHECK,
--      primary key / partial unique indexes, deferred overlap and exception
--      coherence triggers, and the deferred timezone dependency;
--   C. end to end: management writes (timezone, standard duration, weekly
--      hours, exceptions) are reflected by the Guardian candidate read
--      get_requestable_appointment_start_times (SPEC-APT-014).
--
-- Dates relative to "today" are computed when the suite runs, never
-- hard-coded; the date-line cases use Pacific/Kiritimati (UTC+14),
-- Pacific/Tongatapu (UTC+13), and Pacific/Pago_Pago (UTC-11), none of which
-- observes daylight saving.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required to load a deterministic context with establishment
-- triggers bypassed, to write protected tables directly in section B, and to
-- switch between impersonated Users. Deferred constraints are fired inside
-- each call (SET CONSTRAINTS ALL IMMEDIATE, then back to DEFERRED).
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
    raise exception 'Expected SQLSTATE %, but statement succeeded: %', p_expected_sqlstate, p_statement;
end;
$$;

create function pg_temp.domain_user(p_n integer) returns uuid language sql immutable as $$
    select ('a7140000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.act(p_n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',
                      'a7140000-0000-4000-8000-0000000001' || lpad(p_n::text, 2, '0'), true);
$$;
create function pg_temp.clinic(p_n integer) returns uuid language sql immutable as $$
    select ('a7140000-0000-4000-8000-0000000004' || lpad(p_n::text, 2, '0'))::uuid
$$;
create function pg_temp.assignment(p_n integer) returns uuid language sql immutable as $$
    select ('a7140000-0000-4000-8000-0000000008' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end;
$$;

-- A privileged direct write that bypasses every RPC, then every deferred
-- constraint, inside the caller's subtransaction.
create function pg_temp.direct(p_statement text) returns void language plpgsql as $$
begin
    execute p_statement;
    perform pg_temp.flush();
end;
$$;

create function pg_temp.set_timezone(p_clinic uuid, p_timezone text) returns void language plpgsql as $$
begin
    perform public.set_clinic_scheduling_timezone(p_clinic, p_timezone);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.replace(p_clinic uuid, p_periods text) returns void language plpgsql as $$
begin
    perform public.replace_clinic_appointment_availability(
        p_clinic, p_periods::jsonb,
        (select weekly_appointment_availability_revision from public.clinics where id = p_clinic));
    perform pg_temp.flush();
end;
$$;

create function pg_temp.set_exception(p_clinic uuid, p_date date, p_kind text, p_periods text)
returns void language plpgsql as $$
begin
    perform public.set_clinic_appointment_availability_exception(p_clinic, p_date, p_kind, p_periods::jsonb);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.clear_exception(p_clinic uuid, p_date date) returns void language plpgsql as $$
begin
    perform public.clear_clinic_appointment_availability_exception(p_clinic, p_date);
    perform pg_temp.flush();
end;
$$;

create function pg_temp.set_duration(p_clinic uuid, p_minutes integer) returns void language plpgsql as $$
begin
    perform public.set_clinic_standard_appointment_duration(p_clinic, p_minutes);
    perform pg_temp.flush();
end;
$$;

-- Every stored Appointment-scheduling and Opening Hours fact for one Clinic,
-- including Veterinarian Availability of every Assignment at it, excluding
-- the timezone itself (asserted separately).
create function pg_temp.availability_fingerprint(p_clinic uuid) returns text language sql as $$
    select md5(coalesce(string_agg(fact, '|' order by fact), ''))
    from (
        select 'cp' || (row_record.iso_weekday, row_record.start_time, row_record.end_time)::text as fact
        from public.clinic_appointment_availability_periods as row_record
        where row_record.clinic_id = p_clinic
        union all
        select 'ce' || (row_record.local_date, row_record.exception_kind, row_record.start_time, row_record.end_time)::text
        from public.clinic_appointment_availability_exceptions as row_record
        where row_record.clinic_id = p_clinic
        union all
        select 'vp' || (row_record.veterinarian_clinic_assignment_id, row_record.iso_weekday, row_record.start_time, row_record.end_time)::text
        from public.veterinarian_availability_periods as row_record
        join public.veterinarian_clinic_assignments as assignment on assignment.id = row_record.veterinarian_clinic_assignment_id
        where assignment.clinic_id = p_clinic
        union all
        select 've' || (row_record.veterinarian_clinic_assignment_id, row_record.local_date, row_record.exception_kind, row_record.start_time, row_record.end_time)::text
        from public.veterinarian_availability_exceptions as row_record
        join public.veterinarian_clinic_assignments as assignment on assignment.id = row_record.veterinarian_clinic_assignment_id
        where assignment.clinic_id = p_clinic
        union all
        select 'op' || (row_record.iso_weekday, row_record.start_time, row_record.end_time)::text
        from public.clinic_opening_periods as row_record
        where row_record.clinic_id = p_clinic
        union all
        select 'oe' || (row_record.local_date, row_record.exception_kind, row_record.start_time, row_record.end_time)::text
        from public.clinic_opening_exceptions as row_record
        where row_record.clinic_id = p_clinic
    ) as facts
$$;

create function pg_temp.timezone_of(p_clinic uuid) returns text language sql as $$
    select scheduling_timezone_name from public.clinics where id = p_clinic
$$;

create temporary table remembered (label text primary key, fingerprint text not null) on commit drop;

create function pg_temp.remember(p_label text, p_fingerprint text) returns void language sql as $$
    insert into remembered values (p_label, p_fingerprint)
    on conflict (label) do update set fingerprint = excluded.fingerprint
$$;

create function pg_temp.unchanged(p_label text, p_fingerprint text) returns boolean language sql as $$
    select p_fingerprint = fingerprint from remembered where label = p_label
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects a7140000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian-like User (no Membership; reads candidate times)
--   04 OWNER of OrgA (ACTIVE: holds PROFESSIONAL_SCHEDULING)
--   16 OWNER of OrgN (no Subscription: no PROFESSIONAL_SCHEDULING)
--   10 VETERINARIAN of OrgN with current Clinic Assignments at N5 and N6
--   11 VETERINARIAN of OrgN whose Clinic Assignment at N7 has ended
--   20 starts with nothing; builds its own Organization in section C
-- Clinics (Europe/Madrid unless noted):
--   OrgA: A1 (0401) Clinic period + exception; A3 (0403) no timezone;
--         A4 (0404) empty, for direct writes.
--   OrgN: N1 (0411) nothing; N2 (0412) Clinic recurring period; N3 (0413)
--         future Clinic exception only; N4 (0414) past-only Clinic
--         exception; N5 (0415) Veterinarian period, current Assignment;
--         N6 (0416) Veterinarian exception only, current Assignment;
--         N7 (0417) Veterinarian period + exception, ended Assignment only;
--         N8 (0418) public Opening Hours only;
--         N20 (0420) Clinic exception for Madrid-local today;
--         N21/N22 (Pacific/Kiritimati, change to Pacific/Pago_Pago) and
--         N23/N24 (Pacific/Pago_Pago, change to Pacific/Kiritimati): a Clinic
--         exception for Pago_Pago-local today TP (past under Kiritimati,
--         today under Pago_Pago) at N21/N23, and for TP - 1 (past under both)
--         at N22/N24;
--         N29 (Pacific/Kiritimati, change to Pacific/Tongatapu): a Clinic
--         exception for the day before the earlier of both local todays;
--         N25 (0425) Veterinarian exception for 2020-01-06 only, current
--         Assignment; N26 (0426) Veterinarian exception for Madrid-local
--         today only, current Assignment;
--         N27 (0427) stored timezone no longer valid + past-only Clinic
--         exception; N28 (0428) stored timezone no longer valid, nothing else;
--         N30 (0430) the UTC-date probe, chosen for the run instant (see
--         pg_temp.utc_probe).
-- Veterinarian Availability of the ended Assignment is loaded directly, as
-- if established while it was current (the establishment trigger is
-- bypassed by the replica role).
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('a7140000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 4, 10, 11, 16, 20]) as n;
insert into public.users (id)
select pg_temp.domain_user(n) from unnest(array[1, 4, 10, 11, 16, 20]) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), ('a7140000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from unnest(array[1, 4, 10, 11, 16, 20]) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('a7140000-0000-4000-8000-000000000301', 'Gating OrgA'),
    ('a7140000-0000-4000-8000-000000000302', 'Gating OrgN');

insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
select pg_temp.clinic(n), 'a7140000-0000-4000-8000-000000000301'::uuid, false,
       case when n = 3 then null else 'Europe/Madrid' end, 30
from unnest(array[1, 3, 4]) as n
union all
select pg_temp.clinic(n), 'a7140000-0000-4000-8000-000000000302'::uuid, false, 'Europe/Madrid', 30
from generate_series(11, 18) as n;

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('a7140000-0000-4000-8000-000000000504', 'a7140000-0000-4000-8000-000000000301', pg_temp.domain_user(4), '2020-01-01Z', null, null),
    ('a7140000-0000-4000-8000-000000000516', 'a7140000-0000-4000-8000-000000000302', pg_temp.domain_user(16), '2020-01-01Z', null, null),
    ('a7140000-0000-4000-8000-000000000510', 'a7140000-0000-4000-8000-000000000302', pg_temp.domain_user(10), '2020-01-01Z', null, null),
    ('a7140000-0000-4000-8000-000000000511', 'a7140000-0000-4000-8000-000000000302', pg_temp.domain_user(11), '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('a7140000-0000-4000-8000-000000000604', 'a7140000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(4), null),
    ('a7140000-0000-4000-8000-000000000616', 'a7140000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('a7140000-0000-4000-8000-000000000610', 'a7140000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null),
    ('a7140000-0000-4000-8000-000000000611', 'a7140000-0000-4000-8000-000000000511', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.domain_user(16), null);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('a7140000-0000-4000-8000-000000000710', pg_temp.domain_user(10)),
    ('a7140000-0000-4000-8000-000000000711', pg_temp.domain_user(11));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.assignment(15), 'a7140000-0000-4000-8000-000000000710', 'a7140000-0000-4000-8000-000000000510', pg_temp.clinic(15), '2020-01-01Z', null),
    (pg_temp.assignment(16), 'a7140000-0000-4000-8000-000000000710', 'a7140000-0000-4000-8000-000000000510', pg_temp.clinic(16), '2020-01-01Z', null),
    (pg_temp.assignment(17), 'a7140000-0000-4000-8000-000000000711', 'a7140000-0000-4000-8000-000000000511', pg_temp.clinic(17), '2020-01-01Z', '2021-01-01Z');

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('a7140000-0000-4000-8000-000000000901', 'a7140000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null, 'br56-test', 'a7140000-0000-4000-8000-000000000991');

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(1), 1, '09:00', '13:00'),
    (pg_temp.clinic(12), 1, '09:00', '13:00');
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.clinic(1), '2035-03-05', 'CLOSED', null, null),
    (pg_temp.clinic(13), '2035-03-05', 'CLOSED', null, null),
    (pg_temp.clinic(14), '2020-01-06', 'CLOSED', null, null);
insert into public.veterinarian_availability_periods (veterinarian_clinic_assignment_id, iso_weekday, start_time, end_time) values
    (pg_temp.assignment(15), 1, '09:00', '13:00'),
    (pg_temp.assignment(17), 1, '09:00', '13:00');
insert into public.veterinarian_availability_exceptions (veterinarian_clinic_assignment_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.assignment(16), '2035-03-05', 'OPEN', '10:00', '12:00'),
    (pg_temp.assignment(17), '2035-03-05', 'CLOSED', null, null);
insert into public.clinic_opening_periods (clinic_id, iso_weekday, start_time, end_time) values
    (pg_temp.clinic(18), 1, '09:00', '13:00');
insert into public.clinic_opening_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values
    (pg_temp.clinic(18), '2035-03-05', 'CLOSED', null, null);

-- Past-exception policy fixtures (20261018090000). Each case: the Clinic, the
-- timezone requested for it, and whether the change must be gated without
-- PROFESSIONAL_SCHEDULING.
create temporary table br56_cases (n integer primary key, requested text not null, gated boolean not null) on commit drop;

-- UTC-date probe. A rule that compared exceptions with the UTC date instead of
-- the local dates would agree with BR-56 at some UTC hours and not others, so
-- one fixed case cannot catch it at every hour. Pacific/Pago_Pago (UTC-11) and
-- Pacific/Tongatapu (UTC+13) are exactly 24 hours apart, so Tongatapu's date
-- is always Pago_Pago's + 1, and the UTC date is one of the two:
--   UTC date = Pago_Pago date + 1 (before 11:00 UTC): an exception on
--     Pago_Pago's today, changing Kiritimati -> Pago_Pago, is today under the
--     requested timezone (gated) but before the UTC date;
--   UTC date = Pago_Pago date (from 11:00 UTC): an exception on the day before
--     the earlier of Kiritimati's and Tongatapu's today (= the UTC date),
--     changing Kiritimati -> Tongatapu, is past under both (not gated) but not
--     before the UTC date.
-- pg_temp.utc_probe picks the case for an instant; the suite asserts below
-- that it separates the two rules at every half hour of a day, and the case
-- loop runs the picked case through set_clinic_scheduling_timezone.
create function pg_temp.local_today(p_instant timestamptz, p_timezone text) returns date
language sql stable as $$
    select (p_instant at time zone p_timezone)::date
$$;

-- BR-56 oracle: an exception counts unless before both current local dates.
create function pg_temp.counts_br56(p_instant timestamptz, p_exception date, p_current text, p_requested text)
returns boolean language sql stable as $$
    select p_exception >= least(pg_temp.local_today(p_instant, p_current), pg_temp.local_today(p_instant, p_requested))
$$;

-- The UTC-date fault.
create function pg_temp.counts_utc(p_instant timestamptz, p_exception date) returns boolean
language sql stable as $$
    select p_exception >= pg_temp.local_today(p_instant, 'UTC')
$$;

create function pg_temp.utc_probe(
    p_instant timestamptz,
    out current_timezone text, out requested_timezone text, out exception_date date, out gated boolean
)
language sql stable as $$
    select 'Pacific/Kiritimati',
           case when picks_pago then 'Pacific/Pago_Pago' else 'Pacific/Tongatapu' end,
           case when picks_pago then pago_today
                else least(pg_temp.local_today(p_instant, 'Pacific/Kiritimati'),
                           pg_temp.local_today(p_instant, 'Pacific/Tongatapu')) - 1 end,
           picks_pago
    from (select pg_temp.local_today(p_instant, 'Pacific/Pago_Pago') as pago_today,
                 pg_temp.local_today(p_instant, 'Pacific/Pago_Pago') < pg_temp.local_today(p_instant, 'UTC') as picks_pago) as choice
$$;

-- Proof over a whole day: at every half hour the probe's expected verdict is
-- the BR-56 one and differs from the UTC-date one, and the 24-hour offset the
-- argument relies on holds.
do $$
declare
    probe_instant timestamptz;
    probe record;
begin
    for probe_instant in
        select (date_trunc('day', clock_timestamp() at time zone 'UTC') at time zone 'UTC') + step * interval '30 minutes'
        from generate_series(0, 47) as step
    loop
        select * into probe from pg_temp.utc_probe(probe_instant);
        perform pg_temp.assert_true(
            pg_temp.local_today(probe_instant, 'Pacific/Tongatapu') = pg_temp.local_today(probe_instant, 'Pacific/Pago_Pago') + 1
            and pg_temp.counts_br56(probe_instant, probe.exception_date, probe.current_timezone, probe.requested_timezone) = probe.gated
            and pg_temp.counts_utc(probe_instant, probe.exception_date) <> probe.gated,
            format('UTC probe separates BR-56 from the UTC-date rule at %s', probe_instant));
    end loop;
end;
$$;

do $$
declare
    fixture_instant timestamptz := clock_timestamp();
    madrid_today date := pg_temp.local_today(fixture_instant, 'Europe/Madrid');
    pago_today date := pg_temp.local_today(fixture_instant, 'Pacific/Pago_Pago');
    kiritimati_today date := pg_temp.local_today(fixture_instant, 'Pacific/Kiritimati');
    tonga_today date := pg_temp.local_today(fixture_instant, 'Pacific/Tongatapu');
    probe record;
begin
    select * into probe from pg_temp.utc_probe(fixture_instant);
    insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
    values (pg_temp.clinic(30), 'a7140000-0000-4000-8000-000000000302', false, probe.current_timezone, 30);
    insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
    values (pg_temp.clinic(30), probe.exception_date, 'CLOSED');
    insert into br56_cases (n, requested, gated) values (30, probe.requested_timezone, probe.gated);
    perform pg_temp.assert_true(
        pg_temp.counts_utc(fixture_instant, probe.exception_date) <> probe.gated,
        'Fixture: the UTC probe (Clinic 30) separates BR-56 from the UTC-date rule now');

    insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
    select pg_temp.clinic(case_row.n), 'a7140000-0000-4000-8000-000000000302'::uuid, false, case_row.timezone_name, 30
    from (values
        (20, 'Europe/Madrid'), (21, 'Pacific/Kiritimati'), (22, 'Pacific/Kiritimati'),
        (23, 'Pacific/Pago_Pago'), (24, 'Pacific/Pago_Pago'), (25, 'Europe/Madrid'),
        (26, 'Europe/Madrid'), (27, 'Invalid/No_Such_Zone'), (28, 'Invalid/No_Such_Zone'),
        (29, 'Pacific/Kiritimati')
    ) as case_row(n, timezone_name);

    insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind) values
        (pg_temp.clinic(20), madrid_today, 'CLOSED'),
        (pg_temp.clinic(21), pago_today, 'CLOSED'),
        (pg_temp.clinic(22), pago_today - 1, 'CLOSED'),
        (pg_temp.clinic(23), pago_today, 'CLOSED'),
        (pg_temp.clinic(24), pago_today - 1, 'CLOSED'),
        (pg_temp.clinic(27), '2020-01-06', 'CLOSED'),
        (pg_temp.clinic(29), least(kiritimati_today, tonga_today) - 1, 'CLOSED');

    insert into public.veterinarian_clinic_assignments (
        id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
    ) values
        (pg_temp.assignment(25), 'a7140000-0000-4000-8000-000000000710', 'a7140000-0000-4000-8000-000000000510', pg_temp.clinic(25), '2020-01-01Z', null),
        (pg_temp.assignment(26), 'a7140000-0000-4000-8000-000000000710', 'a7140000-0000-4000-8000-000000000510', pg_temp.clinic(26), '2020-01-01Z', null);
    insert into public.veterinarian_availability_exceptions (veterinarian_clinic_assignment_id, local_date, exception_kind) values
        (pg_temp.assignment(25), '2020-01-06', 'CLOSED'),
        (pg_temp.assignment(26), madrid_today, 'CLOSED');

    -- The date-line fixtures only prove anything while Kiritimati is ahead
    -- of Pago_Pago (always: 25 hours apart).
    perform pg_temp.assert_true(kiritimati_today > pago_today,
        'Fixture: Kiritimati-local today is after Pago_Pago-local today');
end;
$$;

insert into br56_cases (n, requested, gated) values
    (12, 'Atlantic/Canary', true),      -- Clinic recurring period
    (13, 'Atlantic/Canary', true),      -- future Clinic exception
    (14, 'Atlantic/Canary', false),     -- past-only Clinic exception
    (15, 'Atlantic/Canary', true),      -- current Assignment, Veterinarian period
    (16, 'Atlantic/Canary', true),      -- current Assignment, future Veterinarian exception
    (20, 'Atlantic/Canary', true),      -- Clinic exception today
    (21, 'Pacific/Pago_Pago', true),    -- past under current, today under requested
    (22, 'Pacific/Pago_Pago', false),   -- past under both
    (23, 'Pacific/Kiritimati', true),   -- today under current, past under requested
    (24, 'Pacific/Kiritimati', false),  -- past under both
    (29, 'Pacific/Tongatapu', false),   -- past under both, on or after the UTC date
    (25, 'Atlantic/Canary', false),     -- current Assignment, past-only Veterinarian exception
    (26, 'Atlantic/Canary', true),      -- current Assignment, Veterinarian exception today
    (27, 'Atlantic/Canary', true),      -- current timezone not valid: every exception counts
    (11, 'Atlantic/Canary', false),     -- nothing
    (17, 'Atlantic/Canary', false),     -- ended Assignment's Veterinarian Availability only
    (18, 'Atlantic/Canary', false),     -- public Opening Hours only
    (28, 'Atlantic/Canary', false);     -- current timezone not valid, no Availability

set local session_replication_role = origin;

select pg_temp.assert_true(
    not public.organization_has_professional_entitlement('a7140000-0000-4000-8000-000000000302', 'PROFESSIONAL_SCHEDULING')
    and public.organization_has_professional_entitlement('a7140000-0000-4000-8000-000000000301', 'PROFESSIONAL_SCHEDULING')
    and public.veterinarian_clinic_assignment_is_current(pg_temp.assignment(15))
    and public.veterinarian_clinic_assignment_is_current(pg_temp.assignment(16))
    and not public.veterinarian_clinic_assignment_is_current(pg_temp.assignment(17))
    and (select local_date < current_date from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.clinic(14))
    and not exists (select 1 from public.clinic_appointment_availability_exceptions
                    where clinic_id = pg_temp.clinic(14) and local_date >= current_date),
    'Fixture: OrgN lacks and OrgA holds PROFESSIONAL_SCHEDULING; Assignments at N5/N6 are current and at N7 ended; N4 has only a past exception'
);

-- ===========================================================================
-- A. BR-56 — scheduling timezone gating
-- ===========================================================================

do $$
declare
    case_row record;
begin
    for case_row in select n from br56_cases loop
        perform pg_temp.remember('n' || case_row.n, pg_temp.availability_fingerprint(pg_temp.clinic(case_row.n)));
        perform pg_temp.remember('n' || case_row.n || '_timezone', pg_temp.timezone_of(pg_temp.clinic(case_row.n)));
    end loop;
end;
$$;

select pg_temp.act(16);

-- The requested timezone is validated before the gate (20261018090000): an
-- invalid one is 22023 even where the gate would deny, and changes nothing.
select pg_temp.assert_error(
    format('select pg_temp.set_timezone(%L, %L)', pg_temp.clinic(12), 'Not/A_Zone'),
    '22023', 'Clinic scheduling timezone must be a valid named timezone');
select pg_temp.assert_true(
    pg_temp.timezone_of(pg_temp.clinic(12)) = 'Europe/Madrid'
    and pg_temp.unchanged('n12', pg_temp.availability_fingerprint(pg_temp.clinic(12))),
    'BR-56: an invalid requested timezone is rejected as input before the Entitlement gate, with no change');

-- Every case, without PROFESSIONAL_SCHEDULING. Gated: the change is denied and
-- the timezone and every row stay as they were. Not gated: the change applies
-- (normalized) and no Availability, exception, or Opening Hours row changes —
-- past exceptions stay stored.
do $$
declare
    case_row record;
begin
    for case_row in select * from br56_cases order by n loop
        if case_row.gated then
            perform pg_temp.assert_error(
                format('select pg_temp.set_timezone(%L, %L)', pg_temp.clinic(case_row.n), case_row.requested),
                '42501',
                'Professional scheduling Entitlement is required to change scheduling timezone while Appointment Availability is currently effective');
            perform pg_temp.assert_true(
                pg_temp.unchanged('n' || case_row.n || '_timezone', pg_temp.timezone_of(pg_temp.clinic(case_row.n))),
                format('BR-56: the denied change at Clinic %s keeps its timezone', case_row.n));
        else
            begin
                perform pg_temp.set_timezone(pg_temp.clinic(case_row.n), ' ' || case_row.requested || ' ');
            exception when others then
                raise exception 'BR-56: the change at Clinic % to % must not be gated: % %',
                    case_row.n, case_row.requested, sqlstate, sqlerrm;
            end;
            perform pg_temp.assert_true(
                pg_temp.timezone_of(pg_temp.clinic(case_row.n)) = case_row.requested,
                format('BR-56: the allowed change at Clinic %s is applied, normalized', case_row.n));
        end if;
        perform pg_temp.assert_true(
            pg_temp.unchanged('n' || case_row.n, pg_temp.availability_fingerprint(pg_temp.clinic(case_row.n))),
            format('BR-56: the change at Clinic %s leaves every stored Availability and Opening Hours row unchanged', case_row.n));
    end loop;
end;
$$;
select pg_temp.assert_true(true,
    'BR-56 without PROFESSIONAL_SCHEDULING: gated by a Clinic recurring period, a Clinic exception that is today or later under either timezone (date-line crossings in both directions), a current Assignment''s Veterinarian period or not-past exception, and any exception while the current timezone is not valid; not gated by exceptions past under both timezones (Clinic or Veterinarian), an ended Assignment''s Availability, public Opening Hours, or nothing');

-- Past exceptions stay structural: the Clinic whose only exception is past
-- (N4, now Atlantic/Canary) still cannot lose its timezone.
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'update public.clinics set scheduling_timezone_name = null where id = %L', pg_temp.clinic(14))),
    '23514', 'Clinic timezone-dependent configuration requires a valid scheduling timezone');
set constraints all deferred;
select pg_temp.assert_true(
    pg_temp.timezone_of(pg_temp.clinic(14)) = 'Atlantic/Canary'
    and pg_temp.unchanged('n14', pg_temp.availability_fingerprint(pg_temp.clinic(14))),
    'Structure: a past-only exception still requires a valid scheduling timezone (unchanged dependency)');

-- With PROFESSIONAL_SCHEDULING the gate does not apply (A1: period and
-- exception), and the deferred timezone dependency still passes.
select pg_temp.act(4);
select pg_temp.remember('a1', pg_temp.availability_fingerprint(pg_temp.clinic(1)));
select pg_temp.set_timezone(pg_temp.clinic(1), 'Atlantic/Canary');
select pg_temp.assert_true(
    pg_temp.timezone_of(pg_temp.clinic(1)) = 'Atlantic/Canary'
    and pg_temp.unchanged('a1', pg_temp.availability_fingerprint(pg_temp.clinic(1))),
    'BR-56: with PROFESSIONAL_SCHEDULING the timezone of a Clinic with currently effective Availability changes, with its stored local Availability untouched'
);

-- The gate is evaluated after the capability: a Veterinarian of OrgN
-- (no CLINIC_MANAGE_OPENING_HOURS) is denied by capability first.
select pg_temp.act(10);
select pg_temp.assert_error(
    format('select pg_temp.set_timezone(%L, %L)', pg_temp.clinic(11), 'Europe/Madrid'),
    '42501', 'Applicable Clinic-management capability is required');

-- ===========================================================================
-- B. Structural integrity with the RPC layer bypassed
-- ===========================================================================
-- Every write below is a privileged direct INSERT/UPDATE: no RPC
-- pre-validation runs, so each rejection comes from the table's own CHECK,
-- key/partial unique index, or deferred constraint trigger. Messages the
-- RPCs also use ("must not overlap") are unambiguous here for that reason;
-- the timezone message is the structural trigger's own wording.

-- Accepted baseline rows at A4.
select pg_temp.direct(format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 2, %L, %L)',
    pg_temp.clinic(4), '09:00', '13:00'));
select pg_temp.direct(format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 2, %L, %L)',
    pg_temp.clinic(4), '13:00', '14:00'));
select pg_temp.direct(format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values (%L, %L, %L, %L, %L), (%L, %L, %L, %L, %L)',
    pg_temp.clinic(4), '2035-03-06', 'OPEN', '09:00', '11:00',
    pg_temp.clinic(4), '2035-03-06', 'OPEN', '11:00', '12:00'));
select pg_temp.direct(format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind) values (%L, %L, %L)',
    pg_temp.clinic(4), '2035-03-07', 'CLOSED'));
select pg_temp.assert_true(true,
    'Structure: touching recurring periods and touching OPEN exception periods are accepted by the structural layer');
select pg_temp.remember('a4', pg_temp.availability_fingerprint(pg_temp.clinic(4)));
select pg_temp.remember('a4_timezone', pg_temp.timezone_of(pg_temp.clinic(4)));

-- Recurring periods.
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 1, %L, %L), (%L, 1, %L, %L)',
    pg_temp.clinic(4), '09:00', '13:00', pg_temp.clinic(4), '12:00', '14:00')),
    '23P01', 'Clinic Appointment Availability Periods must not overlap');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 2, %L, %L)',
    pg_temp.clinic(4), '10:00', '11:00')),
    '23P01', 'Clinic Appointment Availability Periods must not overlap');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 2, %L, %L)',
    pg_temp.clinic(4), '09:00', '13:00')),
    '23505', 'clinic_appointment_availability_periods_pkey');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 3, %L, %L)',
    pg_temp.clinic(4), '13:00', '09:00')),
    '23514', 'clinic_appointment_availability_periods_interval_check');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 8, %L, %L)',
    pg_temp.clinic(4), '09:00', '13:00')),
    '23514', 'clinic_appointment_availability_periods_iso_weekday_check');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'update public.clinic_appointment_availability_periods set start_time = %L where clinic_id = %L and start_time = %L',
    '12:30', pg_temp.clinic(4), '13:00')),
    '23P01', 'Clinic Appointment Availability Periods must not overlap');
set constraints all deferred;
select pg_temp.assert_true(
    pg_temp.unchanged('a4', pg_temp.availability_fingerprint(pg_temp.clinic(4))),
    'Structure: overlapping recurring periods (in one statement, against a stored period, and by UPDATE), a duplicate exact period, start not before end, and an invalid weekday are each rejected by the table itself, leaving nothing behind'
);

-- Exceptions.
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values (%L, %L, %L, null, null), (%L, %L, %L, %L, %L)',
    pg_temp.clinic(4), '2035-03-08', 'CLOSED', pg_temp.clinic(4), '2035-03-08', 'OPEN', '09:00', '10:00')),
    '23514', 'Clinic Appointment Availability Exception cannot combine CLOSED and OPEN interpretations');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values (%L, %L, %L, %L, %L)',
    pg_temp.clinic(4), '2035-03-07', 'OPEN', '09:00', '10:00')),
    '23514', 'Clinic Appointment Availability Exception cannot combine CLOSED and OPEN interpretations');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind) values (%L, %L, %L)',
    pg_temp.clinic(4), '2035-03-07', 'CLOSED')),
    '23505', 'clinic_appointment_availability_exceptions_closed_date_key');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values (%L, %L, %L, %L, %L)',
    pg_temp.clinic(4), '2035-03-06', 'OPEN', '10:30', '11:30')),
    '23P01', 'Clinic Appointment Availability Exception periods must not overlap');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values (%L, %L, %L, %L, %L)',
    pg_temp.clinic(4), '2035-03-06', 'OPEN', '09:00', '11:00')),
    '23505', 'clinic_appointment_availability_exceptions_open_exact_key');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind, start_time, end_time) values (%L, %L, %L, %L, %L)',
    pg_temp.clinic(4), '2035-03-09', 'CLOSED', '09:00', '10:00')),
    '23514', 'clinic_appointment_availability_exceptions_shape_check');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind) values (%L, %L, %L)',
    pg_temp.clinic(4), '2035-03-09', 'OPEN')),
    '23514', 'clinic_appointment_availability_exceptions_shape_check');
set constraints all deferred;
select pg_temp.assert_true(
    pg_temp.unchanged('a4', pg_temp.availability_fingerprint(pg_temp.clinic(4))),
    'Structure: CLOSED and OPEN on one date (either order), a second CLOSED, overlapping or duplicate OPEN periods, and malformed CLOSED/OPEN shapes are each rejected by the table itself, leaving nothing behind'
);

-- Timezone dependency (deferred): Availability needs a valid Clinic
-- timezone, and a Clinic with Availability cannot lose its timezone.
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time) values (%L, 1, %L, %L)',
    pg_temp.clinic(3), '09:00', '13:00')),
    '23514', 'Clinic timezone-dependent configuration requires a valid scheduling timezone');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind) values (%L, %L, %L)',
    pg_temp.clinic(3), '2035-03-05', 'CLOSED')),
    '23514', 'Clinic timezone-dependent configuration requires a valid scheduling timezone');
set constraints all deferred;
select pg_temp.assert_error(format(
    'select pg_temp.direct(%L)', format(
    'update public.clinics set scheduling_timezone_name = null where id = %L', pg_temp.clinic(4))),
    '23514', 'Clinic timezone-dependent configuration requires a valid scheduling timezone');
set constraints all deferred;
select pg_temp.assert_true(
    pg_temp.timezone_of(pg_temp.clinic(3)) is null
    and not exists (select 1 from public.clinic_appointment_availability_periods where clinic_id = pg_temp.clinic(3))
    and not exists (select 1 from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.clinic(3))
    and pg_temp.timezone_of(pg_temp.clinic(4)) = (select fingerprint from remembered where label = 'a4_timezone')
    and pg_temp.unchanged('a4', pg_temp.availability_fingerprint(pg_temp.clinic(4))),
    'Structure: a direct period or exception at a Clinic without a timezone, and clearing the timezone of a Clinic with Availability, are rejected by the deferred timezone dependency'
);

-- ===========================================================================
-- C. End to end: management writes → Guardian candidate times
-- ===========================================================================
-- User 20 is established as Owner of an ACTIVE Organization through the
-- trusted establishment RPC and builds a published Clinic; every configuration step goes through the real management RPC; a
-- Guardian-like User reads candidates. The Clinic uses Atlantic/Reykjavik
-- (UTC all year) and dates 7 and 14 days ahead, so no DST transition or
-- horizon boundary is involved.

create temporary table e2e (clinic_id uuid, organization_id uuid, target_date date) on commit drop;

-- Trusted atomic establishment (ADR-009): Organization + Owner + ACTIVE
-- initial Subscription, called as the session role without impersonation.
insert into e2e (organization_id)
select (public.establish_veterinary_organization(pg_temp.domain_user(20), 'E2E Candidate Org', gen_random_uuid(),
    'ACTIVE', null, null, null, 'br56-e2e-test') ->> 'organization_id')::uuid;
select pg_temp.act(20);
update e2e set clinic_id = (public.create_clinic(organization_id, gen_random_uuid()) ->> 'clinic_id')::uuid;
select public.set_clinic_location((select clinic_id from e2e), 'Calle E2E 1, Reykjavik', 64.1466, -21.9426);
select public.set_clinic_public_profile((select clinic_id from e2e), 'E2E Candidate Clinic', null, null, null, null);
select public.publish_clinic((select clinic_id from e2e));
select pg_temp.flush();
update e2e set target_date = (clock_timestamp() at time zone 'Atlantic/Reykjavik')::date + 7;

create function pg_temp.candidates(p_days integer) returns text language sql as $$
    select coalesce(string_agg(
               (candidate.candidate_local_date - e2e.target_date)::text || '@' || to_char(candidate.candidate_local_time, 'HH24:MI'),
               ',' order by candidate.candidate_local_date, candidate.candidate_local_time), '')
    from e2e, public.get_requestable_appointment_start_times(e2e.clinic_id, e2e.target_date, e2e.target_date + p_days) as candidate
$$;

create function pg_temp.week_at(p_start text, p_end text) returns text language sql as $$
    select format('[{"iso_weekday": %s, "start_time": "%s", "end_time": "%s"}]',
                  extract(isodow from target_date)::integer, p_start, p_end)
    from e2e
$$;

-- No timezone, no duration, no Availability: nothing is requestable.
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '',
    'E2E: a published Clinic without timezone, duration, or Availability offers no candidate');

select pg_temp.act(20);
select pg_temp.set_timezone((select clinic_id from e2e), 'Atlantic/Reykjavik');
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '',
    'E2E: a timezone alone offers no candidate (no standard duration)');

select pg_temp.act(20);
select pg_temp.set_duration((select clinic_id from e2e), 30);
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '',
    'E2E: timezone and duration without Appointment Availability offer no candidate');

select pg_temp.act(20);
select pg_temp.replace((select clinic_id from e2e), pg_temp.week_at('09:00', '11:00'));
select pg_temp.act(1);
select pg_temp.assert_true(
    pg_temp.candidates(0) = '0@09:00,0@09:30,0@10:00,0@10:30'
    and pg_temp.candidates(7) = '0@09:00,0@09:30,0@10:00,0@10:30,7@09:00,7@09:30,7@10:00,7@10:30',
    'E2E: weekly hours 09:00–11:00 with a 30-minute duration produce four candidates on that weekday, every week'
);

select pg_temp.act(20);
select pg_temp.set_duration((select clinic_id from e2e), 60);
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(0) = '0@09:00,0@10:00',
    'E2E: changing the standard duration to 60 minutes changes the candidate cadence immediately');

select pg_temp.act(20);
select pg_temp.replace((select clinic_id from e2e), pg_temp.week_at('14:00', '15:00'));
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '0@14:00,7@14:00',
    'E2E: replacing the weekly hours replaces the candidates (the old hours offer nothing)');

select pg_temp.act(20);
select pg_temp.set_exception((select clinic_id from e2e), (select target_date from e2e), 'CLOSED', '[]');
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '7@14:00',
    'E2E: a CLOSED exception removes that date''s candidates only');

select pg_temp.act(20);
select pg_temp.set_exception((select clinic_id from e2e), (select target_date from e2e), 'OPEN',
    '[{"start_time": "08:00", "end_time": "09:00"}]');
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '0@08:00,7@14:00',
    'E2E: an OPEN exception replaces that date''s hours');

select pg_temp.act(20);
select pg_temp.clear_exception((select clinic_id from e2e), (select target_date from e2e));
select pg_temp.act(1);
select pg_temp.assert_true(pg_temp.candidates(7) = '0@14:00,7@14:00',
    'E2E: clearing the exception restores the weekly hours for that date');

do $$ begin raise notice 'scheduling_timezone_gating_and_structural_integrity_spec_apt_013.sql: all assertions passed'; end $$;

rollback;

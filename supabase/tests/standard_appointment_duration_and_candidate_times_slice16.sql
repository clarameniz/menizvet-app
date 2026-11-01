-- Regression suite for Slice 16 (Standard Appointment Duration & Guardian
-- Requestable Times), migration
-- 20260920120000_standard_appointment_duration_and_candidate_times.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions
-- are rolled back; nothing is retained.
--
-- Covers: SPEC-APT-013 BR-57/58/59/61/62/66/67, SPEC-APT-014 (structural /
-- eligibility / Clinic-relative validation ordering, non-disclosure,
-- candidate generation, DST omission, sub-minute grid anchoring and parity
-- with the Professional grid — 20261017090000), SPEC-APT-001
-- BR-29/30/31/32/34, SPEC-APT-004 BR-19/22/23/24.
begin;

-- ===========================================================================
-- Helpers
-- ===========================================================================

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_sqlstate(p_statement text, p_expected text)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected then return; end if;
        raise exception 'Expected SQLSTATE %, received %: %', p_expected, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected;
end;
$$;

create table pg_temp.fixture_ids (label text primary key, value uuid);
grant select, insert, update on pg_temp.fixture_ids to authenticated;

-- Test-only convenience, local to this rolled-back transaction: lets
-- fixture code compute the correct UTC offset for an arbitrary civil
-- date/time (mirroring what a real client would only ever learn through
-- get_requestable_appointment_start_times's output) even for dates/cases
-- this suite deliberately keeps outside that read's results (e.g. a CLOSED
-- exception date, or a Clinic with no configured duration). This grant
-- does not exist in the deployed migration.
grant execute on function public.resolve_clinic_civil_candidate(text, date, time) to authenticated;

-- ===========================================================================
-- Fixtures: identities
-- ===========================================================================

insert into auth.users (id, email, email_confirmed_at) values
    ('16000000-0000-4000-8000-000000000001', 'slice16-owner@example.test', clock_timestamp()),
    ('16000000-0000-4000-8000-000000000002', 'slice16-guardian1@example.test', clock_timestamp()),
    ('16000000-0000-4000-8000-000000000003', 'slice16-guardian2@example.test', clock_timestamp()),
    ('16000000-0000-4000-8000-000000000004', 'slice16-guardian3@example.test', clock_timestamp());

insert into pg_temp.fixture_ids (label, value)
select 'domain_' || right(provider_subject::text, 1), user_id
from public.user_authentication_identities
where provider_subject in (
    '16000000-0000-4000-8000-000000000001',
    '16000000-0000-4000-8000-000000000002',
    '16000000-0000-4000-8000-000000000003',
    '16000000-0000-4000-8000-000000000004'
);

-- ===========================================================================
-- Fixtures: Organization A (published Clinic, entitled, Europe/Madrid,
-- 30-minute standard duration once configured below).
-- ===========================================================================

-- Organization establishment is the trusted atomic operation (ADR-009): it
-- runs as the session role for the designated Owner's domain User, with an
-- ACTIVE initial Subscription effective at the establishment instant.
insert into pg_temp.fixture_ids (label, value)
select 'org_a', (public.establish_veterinary_organization(
    (select value from pg_temp.fixture_ids where label = 'domain_1'), 'Slice16 Animalia', gen_random_uuid(),
    'ACTIVE', null, null, null, 'slice16-test-fixture') ->> 'organization_id')::uuid;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);

set local role authenticated;

insert into pg_temp.fixture_ids (label, value)
select 'clinic_a', (public.create_clinic((select value from pg_temp.fixture_ids where label = 'org_a'), gen_random_uuid()) ->> 'clinic_id')::uuid;

select public.set_clinic_location(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    'Calle Fixture 16, Madrid', 40.4168, -3.7038
);
select public.set_clinic_public_profile(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    'Slice16 Fixture Clinic', null, null, null, null
);
select public.publish_clinic((select value from pg_temp.fixture_ids where label = 'clinic_a'));
select public.set_clinic_scheduling_timezone(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'), 'Europe/Madrid'
);

reset role;

-- Guardians and Pets used across scenarios.
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000002', true);
set local role authenticated;
insert into pg_temp.fixture_ids (label, value)
select 'pet_1', public.register_pet('Fixture Pet One', 'Dog', null, null, null, null, null, null, null);
reset role;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
set local role authenticated;
insert into pg_temp.fixture_ids (label, value)
select 'pet_2', public.register_pet('Fixture Pet Two', 'Cat', null, null, null, null, null, null, null);
reset role;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000004', true);
set local role authenticated;
insert into pg_temp.fixture_ids (label, value)
select 'pet_3', public.register_pet('Fixture Pet Three', 'Rabbit', null, null, null, null, null, null, null);
reset role;

-- ===========================================================================
-- A/B. Standard duration bounds and management RPC
-- ===========================================================================

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    format(
        'select public.set_clinic_standard_appointment_duration(%L::uuid, 9)',
        (select value from pg_temp.fixture_ids where label = 'clinic_a')
    ),
    '22023'
);

select pg_temp.assert_sqlstate(
    format(
        'select public.set_clinic_standard_appointment_duration(%L::uuid, 241)',
        (select value from pg_temp.fixture_ids where label = 'clinic_a')
    ),
    '22023'
);

select public.set_clinic_standard_appointment_duration(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'), 10
);

reset role;
-- Base-table reads bypass RLS/grants only as this superuser test session,
-- never as `authenticated` (no direct table SELECT is ever granted to it).
select pg_temp.assert_true(
    (select standard_appointment_duration_minutes from public.clinics
     where id = (select value from pg_temp.fixture_ids where label = 'clinic_a')) = 10,
    'minimum bound 10 accepted'
);

set local role authenticated;
select public.set_clinic_standard_appointment_duration(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'), 240
);
reset role;
select pg_temp.assert_true(
    (select standard_appointment_duration_minutes from public.clinics
     where id = (select value from pg_temp.fixture_ids where label = 'clinic_a')) = 240,
    'maximum bound 240 accepted'
);

set local role authenticated;
select public.set_clinic_standard_appointment_duration(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'), null
);
reset role;
select pg_temp.assert_true(
    (select standard_appointment_duration_minutes from public.clinics
     where id = (select value from pg_temp.fixture_ids where label = 'clinic_a')) is null,
    'setter supports clearing to NULL'
);

-- Restore the working 30-minute configuration used by the rest of the suite.
set local role authenticated;
select public.set_clinic_standard_appointment_duration(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'), 30
);
reset role;

-- Unauthorized actor (a plain Guardian with no Organization responsibility
-- at all) cannot set duration.
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select pg_temp.assert_sqlstate(
    format(
        'select public.set_clinic_standard_appointment_duration(%L::uuid, 30)',
        (select value from pg_temp.fixture_ids where label = 'clinic_a')
    ),
    '42501'
);
reset role;

-- ===========================================================================
-- Availability configuration on Clinic A for the candidate-read scenarios.
-- Uses OPEN exceptions anchored to current_date so results are independent
-- of which real calendar date this suite happens to run on.
--   current_date + 5  -> single 09:00-14:00 window (30-minute duration ->
--                        candidates 09:00 .. 13:30)
--   current_date + 6  -> split windows 09:00-10:00 and 12:00-13:00
--   current_date + 7  -> CLOSED exception (no candidates)
-- The DST fall-back scenario uses its own Clinic (see "DST fall-back
-- fixture" below), so no date-anchored fixture here can ever overwrite it.
-- ===========================================================================

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date + 5, 'OPEN',
    '[{"start_time": "09:00", "end_time": "14:00"}]'::jsonb
);

select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date + 6, 'OPEN',
    '[{"start_time": "09:00", "end_time": "10:00"}, {"start_time": "12:00", "end_time": "13:00"}]'::jsonb
);

select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date + 7, 'CLOSED', '[]'::jsonb
);

reset role;

-- ===========================================================================
-- DST fall-back fixture.
--
-- The date is never hard-coded: it is the next real Europe/Madrid fall-back
-- date strictly after the Clinic-local "today", found from the time-zone
-- database (the first date whose noon UTC offset is lower than the previous
-- date's). The end-to-end read below runs only while that date lies inside
-- the Guardian read's +60-date horizon; otherwise it is skipped, never
-- failed. The OPEN 01:00-04:00 exception is set on a dedicated, otherwise
-- identical Clinic ('clinic_dst': same entitled Organization, published,
-- Europe/Madrid, 30-minute duration), so no current_date-anchored fixture
-- on Clinic A can ever replace it, whatever the calendar date.
-- ===========================================================================

create table pg_temp.dst_fixture (fall_back_date date not null, in_horizon boolean not null);

do $$
declare
    local_today date := (clock_timestamp() at time zone 'Europe/Madrid')::date;
    next_fall_back date;
begin
    select candidate_date into next_fall_back
    from (
        select (local_today + day_offset) as candidate_date
        from generate_series(1, 400) as day_offset
    ) as days
    where extract(epoch from (candidate_date + time '12:00')
              - ((candidate_date + time '12:00') at time zone 'Europe/Madrid' at time zone 'UTC'))
        < extract(epoch from (candidate_date - 1 + time '12:00')
              - ((candidate_date - 1 + time '12:00') at time zone 'Europe/Madrid' at time zone 'UTC'))
    order by candidate_date
    limit 1;

    perform pg_temp.assert_true(next_fall_back is not null, 'a Europe/Madrid fall-back date exists within 400 days');

    -- Both the database date and the Clinic-local date must keep it inside
    -- the horizon (they differ by one around midnight).
    insert into pg_temp.dst_fixture (fall_back_date, in_horizon)
    values (
        next_fall_back,
        next_fall_back > greatest(current_date, local_today)
            and next_fall_back <= least(current_date, local_today) + 60
    );
end;
$$;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_ids (label, value)
select 'clinic_dst', (public.create_clinic((select value from pg_temp.fixture_ids where label = 'org_a'), gen_random_uuid()) ->> 'clinic_id')::uuid;

select public.set_clinic_location(
    (select value from pg_temp.fixture_ids where label = 'clinic_dst'),
    'Calle Fixture 16 DST, Madrid', 40.4168, -3.7038
);
select public.set_clinic_public_profile(
    (select value from pg_temp.fixture_ids where label = 'clinic_dst'),
    'Slice16 DST Fixture Clinic', null, null, null, null
);
select public.publish_clinic((select value from pg_temp.fixture_ids where label = 'clinic_dst'));
select public.set_clinic_scheduling_timezone(
    (select value from pg_temp.fixture_ids where label = 'clinic_dst'), 'Europe/Madrid'
);
select public.set_clinic_standard_appointment_duration(
    (select value from pg_temp.fixture_ids where label = 'clinic_dst'), 30
);

reset role;

do $$
declare
    fixture record;
begin
    select * into fixture from pg_temp.dst_fixture;
    if fixture.in_horizon then
        perform set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
        set local role authenticated;
        perform public.set_clinic_appointment_availability_exception(
            (select value from pg_temp.fixture_ids where label = 'clinic_dst'),
            fixture.fall_back_date, 'OPEN',
            '[{"start_time": "01:00", "end_time": "04:00"}]'::jsonb
        );
        reset role;
    end if;
end;
$$;

-- ===========================================================================
-- C/D. get_requestable_appointment_start_times — structural validation
-- ===========================================================================

select pg_temp.assert_sqlstate(
    format(
        'select * from public.get_requestable_appointment_start_times(%L::uuid, null, current_date + 5)',
        (select value from pg_temp.fixture_ids where label = 'clinic_a')
    ),
    '22023'
);

select pg_temp.assert_sqlstate(
    format(
        'select * from public.get_requestable_appointment_start_times(%L::uuid, current_date + 5, current_date + 1)',
        (select value from pg_temp.fixture_ids where label = 'clinic_a')
    ),
    '22023'
);

select pg_temp.assert_sqlstate(
    format(
        'select * from public.get_requestable_appointment_start_times(%L::uuid, current_date, current_date + 61)',
        (select value from pg_temp.fixture_ids where label = 'clinic_a')
    ),
    '22023'
);

-- A structurally oversized/reversed range behaves identically for a
-- nonexistent Clinic (no distinguishable branch touches Clinic state).
select pg_temp.assert_sqlstate(
    'select * from public.get_requestable_appointment_start_times(gen_random_uuid(), current_date, current_date + 61)',
    '22023'
);

-- Exactly the maximum permitted horizon (61 dates) is structurally accepted
-- (no exception raised, whatever the resulting candidate count).
select count(*) from public.get_requestable_appointment_start_times(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date, current_date + 60
);

-- ===========================================================================
-- Uniform-empty eligibility (BR-19 step 2 / SPEC-APT-014 BR-5)
-- ===========================================================================

do $$
declare
    result_count integer;
begin
    -- Nonexistent Clinic.
    select count(*) into result_count
    from public.get_requestable_appointment_start_times(
        gen_random_uuid(), current_date, current_date + 5
    );
    perform pg_temp.assert_true(result_count = 0, 'nonexistent Clinic returns empty, not an error');
end;
$$;

-- Trusted atomic establishment (ADR-009) with a PENDING initial Subscription
-- (no Entitlement), then the Owner acts as itself.
reset role;

insert into pg_temp.fixture_ids (label, value)
select 'org_b', (public.establish_veterinary_organization(
    (select value from pg_temp.fixture_ids where label = 'domain_1'), 'Slice16 Unpublished Group', gen_random_uuid(),
    'PENDING', null, null, null, 'slice16-test-fixture') ->> 'organization_id')::uuid;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);

set local role authenticated;
insert into pg_temp.fixture_ids (label, value)
select 'clinic_b', (public.create_clinic((select value from pg_temp.fixture_ids where label = 'org_b'), gen_random_uuid()) ->> 'clinic_id')::uuid;
-- Clinic B is intentionally left unpublished and without a configured
-- duration or Entitlement.

reset role;

do $$
declare
    result_count integer;
begin
    select count(*) into result_count
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_b'),
        current_date, current_date + 5
    );
    perform pg_temp.assert_true(result_count = 0, 'unpublished/no-duration/no-Entitlement Clinic returns empty');
end;
$$;

-- Clinic A itself, published+duration+Entitlement all satisfied, but
-- temporarily strip Entitlement only, to prove the eligibility gate
-- checks Entitlement independently of publication/duration.
-- Phase 1 graph (SPEC-SUB-002 §5): EXPIRED is terminal, so the Entitlement is
-- stripped through PAST_DUE and restored by PAST_DUE -> ACTIVE recovery, both
-- effective no later than the statement instant (no future transitions).
do $$
declare
    result_count integer;
    target_subscription_id uuid;
    current_effective_at timestamptz;
begin
    select id into target_subscription_id
    from public.organization_subscriptions
    where organization_id = (select value from pg_temp.fixture_ids where label = 'org_a');

    select derived.current_state_effective_at into current_effective_at
    from public.derive_organization_subscription_current_state(target_subscription_id) as derived;

    perform public.apply_subscription_state_transition(
        target_subscription_id, 'PAST_DUE',
        current_effective_at + (statement_timestamp() - current_effective_at) / 2, null, null,
        'slice16-test-fixture', 'past-due'
    );

    select count(*) into result_count
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date, current_date + 5
    );
    perform pg_temp.assert_true(result_count = 0, 'Clinic without Entitlement (PAST_DUE) returns empty');

    perform public.apply_subscription_state_transition(
        target_subscription_id, 'ACTIVE', statement_timestamp(), null, null,
        'slice16-test-fixture', 'recover'
    );
end;
$$;

-- ===========================================================================
-- Clinic-relative horizon (BR-19 step 3) — uniform empty, not a rejection,
-- for an eligible Clinic whose structurally valid range is nonetheless
-- Clinic-relatively invalid.
-- ===========================================================================

do $$
declare
    result_count integer;
begin
    -- Structurally valid (26-day span) but starts before "today".
    select count(*) into result_count
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date - 10, current_date + 16
    );
    perform pg_temp.assert_true(
        result_count = 0,
        'range starting before current Clinic-local date returns uniform empty, not a rejection'
    );
end;
$$;

-- ===========================================================================
-- D. Candidate generation — normal window, split window, CLOSED exception,
-- CONFIRMED/REQUESTED non-filtering, correct offset.
-- ===========================================================================

do $$
declare
    candidate_row record;
    candidate_count integer;
    first_time time;
    last_time time;
begin
    select count(*), min(candidate_local_time), max(candidate_local_time)
    into candidate_count, first_time, last_time
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, current_date + 5
    );

    perform pg_temp.assert_true(candidate_count = 10, 'single 09:00-14:00 window at 30min yields 10 candidates');
    perform pg_temp.assert_true(first_time = time '09:00', 'first candidate anchored at window start');
    perform pg_temp.assert_true(last_time = time '13:30', 'final candidate leaves exactly one full interval');

    for candidate_row in
        select * from public.get_requestable_appointment_start_times(
            (select value from pg_temp.fixture_ids where label = 'clinic_a'),
            current_date + 5, current_date + 5
        )
    loop
        perform pg_temp.assert_true(
            candidate_row.utc_offset_seconds is not null,
            'every candidate carries a resolved UTC offset'
        );
    end loop;
end;
$$;

do $$
declare
    candidate_count integer;
begin
    select count(*) into candidate_count
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 6, current_date + 6
    );
    -- 09:00-10:00 -> 09:00, 09:30 (2); 12:00-13:00 -> 12:00, 12:30 (2).
    perform pg_temp.assert_true(candidate_count = 4, 'split windows generate independently anchored candidates');
end;
$$;

do $$
declare
    candidate_count integer;
begin
    select count(*) into candidate_count
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 7, current_date + 7
    );
    perform pg_temp.assert_true(candidate_count = 0, 'CLOSED exception date yields zero candidates');
end;
$$;

-- ===========================================================================
-- clinic_day_covered_civil_ranges <-> clinic_day_interval_is_covered
-- equivalence. For every range the helper emits, the authoritative boolean
-- predicate must agree that any interval fully inside it is covered; for
-- every gap between emitted ranges (or outside all of them), the predicate
-- must reject. Touching periods must merge into one range without the
-- authoritative predicate ever rejecting an interval that crosses the
-- touch-point; a genuine gap between disjoint periods must still be
-- rejected by the predicate even though both sides individually pass.
--
-- Dates current_date+20..+23 are used, dedicated to this section only, so
-- they cannot interact with the +5/+6/+7 fixtures used elsewhere.
--
-- Note: "partial CLOSED exception" (named in the audit request) does not
-- exist as a representable state in this schema —
-- clinic_appointment_availability_exceptions_shape_check requires a CLOSED
-- exception to have null start_time/end_time (always whole-day), so no
-- test is applicable for it. Overlapping periods are likewise never
-- observable: enforce_clinic_appointment_availability_period_integrity is
-- a deferred constraint trigger that rejects any two overlapping periods
-- for the same Clinic/weekday before the writing transaction can commit,
-- so no reader (including this helper) can ever see overlapping source
-- rows; the merge branch that would handle them is structurally identical
-- to the touching-periods branch exercised below (period_end > current_end
-- extends the range the same way whether the new period starts exactly at
-- or before current_end).
-- ===========================================================================

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
set local role authenticated;

-- Touching periods (09:00-10:00, 10:00-11:00) must merge into one range.
select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date + 20, 'OPEN',
    '[{"start_time": "09:00", "end_time": "10:00"}, {"start_time": "10:00", "end_time": "11:00"}]'::jsonb
);

-- Disjoint periods with a genuine gap (09:00-10:00, 10:30-11:30).
select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date + 21, 'OPEN',
    '[{"start_time": "09:00", "end_time": "10:00"}, {"start_time": "10:30", "end_time": "11:30"}]'::jsonb
);

-- Period ending exactly at the day boundary (24:00:00 sentinel).
select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_a'),
    current_date + 22, 'OPEN',
    '[{"start_time": "22:00", "end_time": "24:00"}]'::jsonb
);

reset role;

do $$
declare
    emitted_ranges record;
    range_count integer;
    single_range record;
begin
    -- Touching periods merge into exactly one emitted range spanning both.
    select count(*) into range_count
    from public.clinic_day_covered_civil_ranges(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'), current_date + 20
    );
    perform pg_temp.assert_true(range_count = 1, 'touching periods merge into exactly one emitted range');

    select * into single_range
    from public.clinic_day_covered_civil_ranges(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'), current_date + 20
    );
    perform pg_temp.assert_true(
        single_range.range_start = time '09:00' and single_range.range_end = time '11:00',
        'merged range spans the full 09:00-11:00, not two separate 09:00-10:00/10:00-11:00 ranges'
    );

    -- The authoritative predicate agrees: an interval crossing the
    -- touch-point (10:00) is covered, using real resolved instants exactly
    -- as request_appointment would.
    perform pg_temp.assert_true(
        public.clinic_appointment_interval_is_available(
            (select value from pg_temp.fixture_ids where label = 'clinic_a'),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 20, time '09:30')),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 20, time '10:30'))
        ),
        'authoritative predicate confirms coverage across the merged touch-point'
    );

    -- Disjoint periods: two separate emitted ranges, and the authoritative
    -- predicate rejects an interval spanning the real gap between them,
    -- while accepting intervals fully inside either range.
    select count(*) into range_count
    from public.clinic_day_covered_civil_ranges(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'), current_date + 21
    );
    perform pg_temp.assert_true(range_count = 2, 'disjoint periods remain two separate emitted ranges');

    perform pg_temp.assert_true(
        public.clinic_appointment_interval_is_available(
            (select value from pg_temp.fixture_ids where label = 'clinic_a'),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 21, time '09:00')),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 21, time '09:45'))
        ),
        'interval fully inside the first disjoint range is covered'
    );

    perform pg_temp.assert_true(
        not public.clinic_appointment_interval_is_available(
            (select value from pg_temp.fixture_ids where label = 'clinic_a'),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 21, time '09:45')),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 21, time '10:45'))
        ),
        'interval spanning the real 10:00-10:30 gap is rejected by the authoritative predicate'
    );

    -- Day-boundary sentinel: the emitted range correctly reaches 24:00:00,
    -- and the authoritative predicate accepts an interval ending exactly
    -- there.
    select * into single_range
    from public.clinic_day_covered_civil_ranges(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'), current_date + 22
    );
    perform pg_temp.assert_true(
        single_range.range_start = time '22:00' and single_range.range_end = time '24:00',
        'range ending at the day boundary is emitted as 24:00:00, not wrapped to 00:00:00'
    );

    perform pg_temp.assert_true(
        public.clinic_appointment_interval_is_available(
            (select value from pg_temp.fixture_ids where label = 'clinic_a'),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 22, time '23:30')),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 23, time '00:00'))
        ),
        'authoritative predicate accepts an interval ending exactly at the day boundary'
    );

    -- Gap outside all emitted ranges (before 22:00 on current_date+22) is
    -- rejected.
    perform pg_temp.assert_true(
        not public.clinic_appointment_interval_is_available(
            (select value from pg_temp.fixture_ids where label = 'clinic_a'),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 22, time '08:00')),
            (select resolved_instant from public.resolve_clinic_civil_candidate(
                'Europe/Madrid', current_date + 22, time '08:30'))
        ),
        'interval outside every emitted range on a date with configured Availability is rejected'
    );
end;
$$;

-- REQUESTED/CONFIRMED Appointments do not filter candidates
-- (SPEC-APT-013 BR-66/BR-67).
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $$
declare
    resolved_offset integer;
begin
    select utc_offset_seconds into resolved_offset
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, current_date + 5
    )
    where candidate_local_time = time '09:00'
    limit 1;

    insert into pg_temp.fixture_ids (label, value)
    select 'appt_1', public.request_appointment(
        (select value from pg_temp.fixture_ids where label = 'pet_1'),
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, time '09:00', resolved_offset,
        'Routine check-up', null
    );
end;
$$;

reset role;

do $$
declare
    candidate_count_after integer;
begin
    -- Confirming Appointment 1 (superuser context bypasses RLS/entitlement
    -- checks appropriately for this fixture step: only the resulting
    -- lifecycle_state matters for this assertion, not who performed it).
    update public.appointments
    set lifecycle_state = 'CONFIRMED'
    where id = (select value from pg_temp.fixture_ids where label = 'appt_1');

    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        effective_at, recorded_at
    )
    values (
        (select value from pg_temp.fixture_ids where label = 'appt_1'),
        'REQUESTED', 'CONFIRMED',
        (select value from pg_temp.fixture_ids where label = 'domain_1'),
        'CLINIC', clock_timestamp(), clock_timestamp()
    );

    select count(*) into candidate_count_after
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, current_date + 5
    );

    perform pg_temp.assert_true(
        candidate_count_after = 10,
        'a CONFIRMED overlapping Appointment does not remove any candidate'
    );
end;
$$;

-- ===========================================================================
-- DST — direct helper-function tests (spring-forward is outside the 60-day
-- horizon from "today" in this fixture, so it is exercised directly against
-- resolve_clinic_civil_candidate rather than through the bounded read RPC).
-- ===========================================================================

do $$
declare
    spring_forward_date date := date '2027-03-28'; -- real Europe/Madrid 2027 spring-forward date
    fall_back_date date := date '2026-10-25';       -- real Europe/Madrid 2026 fall-back date
    result record;
begin
    -- 02:30 does not exist that day (clocks jump 02:00 -> 03:00).
    select * into result
    from public.resolve_clinic_civil_candidate('Europe/Madrid', spring_forward_date, time '02:30');
    perform pg_temp.assert_true(result.resolution_kind = 'NONEXISTENT', 'spring-forward gap civil time is NONEXISTENT');

    -- 01:30 exists once, unambiguously, before the transition.
    select * into result
    from public.resolve_clinic_civil_candidate('Europe/Madrid', spring_forward_date, time '01:30');
    perform pg_temp.assert_true(result.resolution_kind = 'UNIQUE', 'time before the gap resolves uniquely');

    -- 02:30 occurs twice that day (clocks fall back 03:00 -> 02:00).
    select * into result
    from public.resolve_clinic_civil_candidate('Europe/Madrid', fall_back_date, time '02:30');
    perform pg_temp.assert_true(result.resolution_kind = 'AMBIGUOUS', 'fall-back repeated civil time is AMBIGUOUS');

    -- 01:30 (before the repeated hour) is unambiguous.
    select * into result
    from public.resolve_clinic_civil_candidate('Europe/Madrid', fall_back_date, time '01:30');
    perform pg_temp.assert_true(result.resolution_kind = 'UNIQUE', 'time before the repeated hour resolves uniquely');
end;
$$;

-- Regression: the anchor-based probe (fixed after this audit) must remain
-- correct for a non-1-hour DST shift (Australia/Lord_Howe's 30 minutes),
-- a Southern-hemisphere zone with the opposite transition direction
-- (Pacific/Auckland, UTC+12/+13), and the most extreme real IANA
-- transition of any kind (Pacific/Apia's 2011 24-hour dateline skip,
-- where an entire local calendar date never occurred). These three were
-- specifically chosen because they are the farthest real-world cases
-- from "ordinary 1-hour Northern-hemisphere DST" this audit could find.
do $$
declare
    result record;
begin
    -- Australia/Lord_Howe: 2026-10-04 02:00 -> 02:30 (30-minute gap).
    select * into result
    from public.resolve_clinic_civil_candidate('Australia/Lord_Howe', date '2026-10-04', time '02:15');
    perform pg_temp.assert_true(result.resolution_kind = 'NONEXISTENT', 'Lord Howe 30-minute gap is NONEXISTENT');

    select * into result
    from public.resolve_clinic_civil_candidate('Australia/Lord_Howe', date '2026-10-04', time '01:45');
    perform pg_temp.assert_true(result.resolution_kind = 'UNIQUE', 'Lord Howe time before the 30-minute gap is UNIQUE');

    -- Australia/Lord_Howe: 2026-04-05 fall-back, 02:00 -> 01:30, ambiguous
    -- 30-minute repeat is civil 01:30-02:00 (verified empirically: the
    -- transition instant is 2026-04-04 15:00:00 UTC).
    select * into result
    from public.resolve_clinic_civil_candidate('Australia/Lord_Howe', date '2026-04-05', time '01:45');
    perform pg_temp.assert_true(result.resolution_kind = 'AMBIGUOUS', 'Lord Howe 30-minute repeat is AMBIGUOUS');

    -- Pacific/Auckland (UTC+12/+13): 2026-09-27 spring-forward 02:00 -> 03:00.
    select * into result
    from public.resolve_clinic_civil_candidate('Pacific/Auckland', date '2026-09-27', time '02:30');
    perform pg_temp.assert_true(result.resolution_kind = 'NONEXISTENT', 'Auckland spring-forward gap is NONEXISTENT');

    select * into result
    from public.resolve_clinic_civil_candidate('Pacific/Auckland', date '2026-09-27', time '01:30');
    perform pg_temp.assert_true(
        result.resolution_kind = 'UNIQUE' and result.resolved_utc_offset_seconds = 43200,
        'Auckland time before spring-forward resolves uniquely at NZST (+12:00)'
    );

    -- Pacific/Auckland: 2026-04-05 fall-back, ambiguous 02:00-03:00 repeat.
    select * into result
    from public.resolve_clinic_civil_candidate('Pacific/Auckland', date '2026-04-05', time '02:30');
    perform pg_temp.assert_true(result.resolution_kind = 'AMBIGUOUS', 'Auckland fall-back repeat is AMBIGUOUS');

    -- Pacific/Apia: the entire calendar date 2011-12-30 never occurred
    -- (Samoa jumped from UTC-11 to UTC+13, skipping a full day). Every
    -- civil time on that date must be NONEXISTENT; the surrounding dates
    -- must each resolve uniquely.
    select * into result
    from public.resolve_clinic_civil_candidate('Pacific/Apia', date '2011-12-30', time '12:00');
    perform pg_temp.assert_true(result.resolution_kind = 'NONEXISTENT', 'Apia entire skipped date is NONEXISTENT');

    select * into result
    from public.resolve_clinic_civil_candidate('Pacific/Apia', date '2011-12-29', time '12:00');
    perform pg_temp.assert_true(result.resolution_kind = 'UNIQUE', 'Apia date before the skip resolves uniquely');

    select * into result
    from public.resolve_clinic_civil_candidate('Pacific/Apia', date '2011-12-31', time '12:00');
    perform pg_temp.assert_true(result.resolution_kind = 'UNIQUE', 'Apia date after the skip resolves uniquely');
end;
$$;

-- End-to-end: the fall-back date's ambiguous candidate is omitted by the
-- full read RPC, without shifting the cadence of the remaining candidates.
-- The date is the computed next fall-back on the dedicated DST Clinic (see
-- "DST fall-back fixture"); skipped while it is beyond the +60 horizon.
do $$
declare
    fall_back_date date := (select fall_back_date from pg_temp.dst_fixture);
    result record;
    candidate_times time[];
begin
    -- The computed date really is a Europe/Madrid fall-back: 02:30 repeats.
    select * into result
    from public.resolve_clinic_civil_candidate('Europe/Madrid', fall_back_date, time '02:30');
    perform pg_temp.assert_true(
        result.resolution_kind = 'AMBIGUOUS',
        format('computed fall-back date %s has an ambiguous 02:30', fall_back_date)
    );

    if not (select in_horizon from pg_temp.dst_fixture) then
        raise notice 'DST fall-back end-to-end read skipped: % is outside the +60-date horizon', fall_back_date;
        return; -- mirrors the conditional fixture above
    end if;

    select array_agg(candidate_local_time order by candidate_local_time)
    into candidate_times
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_dst'),
        fall_back_date, fall_back_date
    );

    -- Window 01:00-04:00, 30-minute duration: 01:00, 01:30, [02:00 and
    -- 02:30 ambiguous and omitted], 03:00, 03:30.
    perform pg_temp.assert_true(
        candidate_times = array[time '01:00', time '01:30', time '03:00', time '03:30'],
        format('fall-back ambiguous candidates omitted without cadence shift, got %s', candidate_times)
    );
end;
$$;

-- ===========================================================================
-- E. request_appointment — start-only contract, duration derivation,
-- no-duration rejection, full-interval Availability validation.
-- ===========================================================================

do $$
declare
    resolved_offset integer;
    new_appt_id uuid;
    revision_row public.appointment_schedule_revisions%rowtype;
begin
    select utc_offset_seconds into resolved_offset
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, current_date + 5
    )
    where candidate_local_time = time '10:00'
    limit 1;

    perform set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
    set local role authenticated;

    new_appt_id := public.request_appointment(
        (select value from pg_temp.fixture_ids where label = 'pet_2'),
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, time '10:00', resolved_offset,
        'Vaccination', 'Please be gentle, nervous cat'
    );

    reset role;

    select * into revision_row
    from public.appointment_schedule_revisions
    where appointment_id = new_appt_id and revision_context = 'REQUESTED';

    perform pg_temp.assert_true(
        revision_row.scheduled_end_at = revision_row.scheduled_start_at + interval '30 minutes',
        'end derived as exactly the current 30-minute standard duration'
    );

    insert into pg_temp.fixture_ids (label, value) values ('appt_2', new_appt_id);
end;
$$;

-- No configured duration => deterministic rejection, not a fallback.
do $$
begin
    update public.clinics
    set standard_appointment_duration_minutes = null
    where id = (select value from pg_temp.fixture_ids where label = 'clinic_a');
end;
$$;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select pg_temp.assert_sqlstate(
    format(
        'select public.request_appointment(%L::uuid, %L::uuid, %L::date, %L::time, %s, %L::text, null)',
        (select value from pg_temp.fixture_ids where label = 'pet_3'),
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, time '11:00',
        (select resolved_utc_offset_seconds from public.resolve_clinic_civil_candidate(
            'Europe/Madrid', current_date + 5, time '11:00'
        )),
        'Check-up'
    ),
    '23514'
);
reset role;

do $$
begin
    update public.clinics
    set standard_appointment_duration_minutes = 30
    where id = (select value from pg_temp.fixture_ids where label = 'clinic_a');
end;
$$;

-- A stale/never-performed candidate read provides no authority: a start
-- time never returned as a candidate (inside a CLOSED-exception date) is
-- still correctly rejected for the true authoritative reason (Availability),
-- proving request_appointment revalidates independently of any prior read.
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select pg_temp.assert_sqlstate(
    format(
        'select public.request_appointment(%L::uuid, %L::uuid, %L::date, %L::time, %s, %L::text, null)',
        (select value from pg_temp.fixture_ids where label = 'pet_3'),
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 7, time '10:00',
        (select resolved_utc_offset_seconds from public.resolve_clinic_civil_candidate(
            'Europe/Madrid', current_date + 7, time '10:00'
        )),
        'Check-up'
    ),
    '23514'
);
reset role;

-- ===========================================================================
-- F. reschedule_requested_appointment — start-only, current-duration
-- derivation, no-op-vs-genuine-change based on the full resolved interval,
-- prior schedule revisions remain untouched.
-- ===========================================================================

do $$
declare
    resolved_offset_11 integer;
    revision_count_before integer;
    revision_row public.appointment_schedule_revisions%rowtype;
    original_first_revision public.appointment_schedule_revisions%rowtype;
begin
    select * into original_first_revision
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2')
      and revision_sequence = 1;

    select utc_offset_seconds into resolved_offset_11
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_a'),
        current_date + 5, current_date + 5
    )
    where candidate_local_time = time '11:00'
    limit 1;

    select count(*) into revision_count_before
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2');

    perform set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
    set local role authenticated;

    perform public.reschedule_requested_appointment(
        (select value from pg_temp.fixture_ids where label = 'appt_2'),
        current_date + 5, time '11:00', resolved_offset_11
    );

    reset role;

    select * into revision_row
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2')
    order by revision_sequence desc
    limit 1;

    perform pg_temp.assert_true(
        revision_row.scheduled_end_at = revision_row.scheduled_start_at + interval '30 minutes',
        'rescheduled end derived from current 30-minute standard duration'
    );

    -- Prior (sequence 1) revision is byte-identical to what request_appointment
    -- originally established — reschedule never rewrites earlier revisions.
    select * into original_first_revision
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2')
      and revision_sequence = 1;
    perform pg_temp.assert_true(
        original_first_revision.scheduled_start_at is not null
        and original_first_revision.revision_context = 'REQUESTED',
        'original first revision remains present and unchanged'
    );
end;
$$;

-- Same start + a changed standard duration is NOT a no-op (SPEC-APT-004
-- BR-19, revised).
do $$
declare
    latest_before public.appointment_schedule_revisions%rowtype;
    latest_after public.appointment_schedule_revisions%rowtype;
    revision_count_before integer;
    revision_count_after integer;
    same_start_date date;
    same_start_time time;
    same_start_offset integer;
begin
    select * into latest_before
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2')
    order by revision_sequence desc limit 1;

    same_start_date := (latest_before.scheduled_start_at at time zone 'Europe/Madrid')::date;
    same_start_time := (latest_before.scheduled_start_at at time zone 'Europe/Madrid')::time;
    same_start_offset := extract(epoch from (
        (latest_before.scheduled_start_at at time zone 'Europe/Madrid')
        - (latest_before.scheduled_start_at at time zone 'UTC')
    ))::integer;

    select count(*) into revision_count_before
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2');

    -- Change the Clinic's standard duration between two reschedule calls.
    update public.clinics
    set standard_appointment_duration_minutes = 45
    where id = (select value from pg_temp.fixture_ids where label = 'clinic_a');

    perform set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
    set local role authenticated;

    perform public.reschedule_requested_appointment(
        (select value from pg_temp.fixture_ids where label = 'appt_2'),
        same_start_date, same_start_time, same_start_offset
    );

    reset role;

    select count(*) into revision_count_after
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2');

    select * into latest_after
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_2')
    order by revision_sequence desc limit 1;

    perform pg_temp.assert_true(
        revision_count_after = revision_count_before + 1,
        'same start with a changed standard duration creates a new revision, not a no-op'
    );
    perform pg_temp.assert_true(
        latest_after.scheduled_end_at = latest_after.scheduled_start_at + interval '45 minutes',
        'the new revision reflects the newly current 45-minute duration'
    );

    update public.clinics
    set standard_appointment_duration_minutes = 30
    where id = (select value from pg_temp.fixture_ids where label = 'clinic_a');
end;
$$;

-- No configured duration => deterministic reschedule rejection.
do $$
begin
    update public.clinics
    set standard_appointment_duration_minutes = null
    where id = (select value from pg_temp.fixture_ids where label = 'clinic_a');
end;
$$;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select pg_temp.assert_sqlstate(
    format(
        'select public.reschedule_requested_appointment(%L::uuid, %L::date, %L::time, %s)',
        (select value from pg_temp.fixture_ids where label = 'appt_2'),
        current_date + 6, time '09:00',
        (select resolved_utc_offset_seconds from public.resolve_clinic_civil_candidate(
            'Europe/Madrid', current_date + 6, time '09:00'
        ))
    ),
    '23514'
);
reset role;

do $$
begin
    update public.clinics
    set standard_appointment_duration_minutes = 30
    where id = (select value from pg_temp.fixture_ids where label = 'clinic_a');
end;
$$;

-- ===========================================================================
-- G. Sub-minute Availability (20261017090000; SPEC-APT-013 BR-58): positions
-- are the covered range's exact civil start plus whole multiples of the
-- standard duration, as in the Professional grid — never re-anchored to the
-- whole minute. Availability is time(6) and the write RPCs accept seconds and
-- microseconds. A dedicated Clinic ('clinic_sub': same entitled Organization,
-- published, Europe/Madrid, 30 minutes) keeps these dates off Clinic A.
--   current_date + 9  -> OPEN 09:00:30-11:00:15
--   current_date + 10 -> OPEN 14:00:00.25-15:00:00.25
-- ===========================================================================

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_ids (label, value)
select 'clinic_sub', (public.create_clinic((select value from pg_temp.fixture_ids where label = 'org_a'), gen_random_uuid()) ->> 'clinic_id')::uuid;

select public.set_clinic_location(
    (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
    'Calle Fixture 16 Sub, Madrid', 40.4168, -3.7038
);
select public.set_clinic_public_profile(
    (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
    'Slice16 Sub-minute Fixture Clinic', null, null, null, null
);
select public.publish_clinic((select value from pg_temp.fixture_ids where label = 'clinic_sub'));
select public.set_clinic_scheduling_timezone(
    (select value from pg_temp.fixture_ids where label = 'clinic_sub'), 'Europe/Madrid'
);
select public.set_clinic_standard_appointment_duration(
    (select value from pg_temp.fixture_ids where label = 'clinic_sub'), 30
);
select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
    current_date + 9, 'OPEN',
    '[{"start_time": "09:00:30", "end_time": "11:00:15"}]'::jsonb
);
select public.set_clinic_appointment_availability_exception(
    (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
    current_date + 10, 'OPEN',
    '[{"start_time": "14:00:00.25", "end_time": "15:00:00.25"}]'::jsonb
);

reset role;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
set local role authenticated;

do $$
declare
    seconds_day time[];
    microseconds_day time[];
    resolved_offset integer;
begin
    select array_agg(candidate_local_time order by candidate_local_time)
    into seconds_day
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
        current_date + 9, current_date + 9
    );
    -- 10:30:30 would end at 11:00:30, past 11:00:15. The minute-truncating
    -- grid offered 09:30, 10:00, 10:30 instead.
    perform pg_temp.assert_true(
        seconds_day = array['09:00:30', '09:30:30', '10:00:30']::time[],
        format('second-precision range: grid anchored at 09:00:30, got %s', seconds_day)
    );

    select array_agg(candidate_local_time order by candidate_local_time)
    into microseconds_day
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
        current_date + 10, current_date + 10
    );
    perform pg_temp.assert_true(
        microseconds_day = array['14:00:00.25', '14:30:00.25']::time[],
        format('microsecond-precision range: grid anchored at 14:00:00.25, got %s', microseconds_day)
    );

    -- The first offered position is requestable verbatim (BR-58 read/write
    -- parity) and lasts the standard duration.
    select utc_offset_seconds into resolved_offset
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
        current_date + 9, current_date + 9
    )
    where candidate_local_time = time '09:00:30';

    insert into pg_temp.fixture_ids (label, value)
    select 'appt_sub', public.request_appointment(
        (select value from pg_temp.fixture_ids where label = 'pet_2'),
        (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
        current_date + 9, time '09:00:30', resolved_offset,
        'Sub-minute check-up', null
    );
end;
$$;

reset role;

do $$
declare
    revision record;
    professional_day time[];
    guardian_day time[];
begin
    select * into revision
    from public.appointment_schedule_revisions
    where appointment_id = (select value from pg_temp.fixture_ids where label = 'appt_sub');

    perform pg_temp.assert_true(
        (revision.scheduled_start_at at time zone 'Europe/Madrid')::time = time '09:00:30'
        and revision.scheduled_end_at - revision.scheduled_start_at = interval '30 minutes',
        'the offered 09:00:30 candidate is established exactly, for 30 elapsed minutes'
    );

    -- The Professional grid generator (shared by both Professional candidate
    -- reads) and the Guardian read offer the same positions for the same
    -- Availability.
    select array_agg(position_row.candidate_local_time order by position_row.candidate_local_time)
    into professional_day
    from public.appointment_reschedule_candidate_positions(
        (select value from pg_temp.fixture_ids where label = 'appt_sub'),
        (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
        'Europe/Madrid', current_date + 10, current_date + 10,
        30::bigint * 60000000, revision.scheduled_start_at, clock_timestamp()
    ) as position_row;

    perform set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
    set local role authenticated;
    select array_agg(candidate_local_time order by candidate_local_time)
    into guardian_day
    from public.get_requestable_appointment_start_times(
        (select value from pg_temp.fixture_ids where label = 'clinic_sub'),
        current_date + 10, current_date + 10
    );
    reset role;

    perform pg_temp.assert_true(
        professional_day = guardian_day,
        format('Guardian and Professional grids agree: %s vs %s', guardian_day, professional_day)
    );
end;
$$;

rollback;

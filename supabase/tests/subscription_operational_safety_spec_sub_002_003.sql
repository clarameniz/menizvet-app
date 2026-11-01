-- Subscription Operational Safety — Phase 1: SPEC-SUB-002 §5/§14/§15,
-- SPEC-SUB-003 BR-8–BR-14/§15, SPEC-SUB-004 §14, ADR-006 (amended).
-- Migration 20261031090000_subscription_operational_safety.sql.
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- Behaviour is exercised through the real trusted operations
-- (establish_organization_subscription, apply_subscription_state_transition),
-- the real Entitlement evaluation, and the real status read. Deferred
-- integrity is flushed inside each helper, as at commit. Multi-session races
-- are pinned by run_subscription_transition_concurrency.py and mutants by
-- run_subscription_safety_faults.py. Fixture prefix d0310000-.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0310000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end $$;
-- A synthetic Organization (kind 3) with actor 1 as its Owner. Fixture rows
-- bypass establishment triggers; every Subscription fact goes through the
-- real trusted operations afterwards.
create function pg_temp.org(n integer) returns uuid language plpgsql as $$
begin
    execute 'set local session_replication_role = replica';
    insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, n), 'Sub Org ' || n);
    insert into public.organization_memberships (id, organization_id, user_id, effective_start)
    values (pg_temp.id(5, n), pg_temp.id(3, n), pg_temp.id(2, 1), '2020-01-01Z');
    insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type,
        effective_start, granted_by_user_id)
    values (pg_temp.id(6, n), pg_temp.id(5, n), 'OWNER', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2, 1));
    execute 'set local session_replication_role = origin';
    return pg_temp.id(3, n);
end $$;
create function pg_temp.establish(organization uuid, state text, effective timestamptz,
    valid_from timestamptz, valid_until timestamptz, key_n integer) returns uuid language plpgsql as $$
declare created uuid; begin
    created := public.establish_organization_subscription(organization, null, state, effective,
        valid_from, valid_until, 'sub-safety-suite', pg_temp.id(20, key_n), null);
    perform pg_temp.flush();
    return created;
end $$;
-- 'OK:<to_state>:<transition id>' or 'ERR:<sqlstate>:<hint or message>'.
create function pg_temp.transition(subscription uuid, target text, effective timestamptz,
    valid_from timestamptz, valid_until timestamptz, event_key text default null) returns text
language plpgsql as $$
declare result record; failure_hint text; begin
    select * into result from public.apply_subscription_state_transition(subscription, target, effective,
        valid_from, valid_until, 'sub-safety-suite', event_key);
    perform pg_temp.flush();
    return 'OK:' || result.to_state || ':' || result.transition_id;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return 'ERR:' || sqlstate || ':' || coalesce(nullif(failure_hint, ''), sqlerrm);
end $$;
-- A Subscription in any state, reached only through allowed operations:
-- PENDING/ACTIVE are established directly (with the given validity); the
-- other states are established ACTIVE and transitioned once on 2020-06-01,
-- the transition carrying the given validity.
create function pg_temp.in_state(organization uuid, target text, valid_from timestamptz,
    valid_until timestamptz, key_n integer) returns uuid language plpgsql as $$
declare created uuid; outcome text; begin
    if target in ('PENDING', 'ACTIVE') then
        return pg_temp.establish(organization, target, '2020-01-01Z', valid_from, valid_until, key_n);
    end if;
    created := pg_temp.establish(organization, 'ACTIVE', '2020-01-01Z', null, null, key_n);
    outcome := pg_temp.transition(created, target, '2020-06-01Z', valid_from, valid_until);
    if outcome not like 'OK:%' then raise exception 'Fixture setup failed: %', outcome; end if;
    return created;
end $$;
-- 'OK:<subscription id>' or 'ERR:<sqlstate>:<hint or message>'.
create function pg_temp.try_establish(organization uuid, state text, effective timestamptz,
    valid_from timestamptz, valid_until timestamptz, key_n integer) returns text language plpgsql as $$
declare created uuid; failure_hint text; begin
    created := public.establish_organization_subscription(organization, null, state, effective,
        valid_from, valid_until, 'sub-safety-suite', pg_temp.id(20, key_n), null);
    perform pg_temp.flush();
    return 'OK:' || created;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return 'ERR:' || sqlstate || ':' || coalesce(nullif(failure_hint, ''), sqlerrm);
end $$;
create function pg_temp.state(subscription uuid) returns text language sql as $$
    select current_state from public.derive_organization_subscription_current_state(subscription)
$$;
create function pg_temp.transitions(subscription uuid) returns bigint language sql as $$
    select count(*) from public.subscription_state_transitions where subscription_id = subscription
$$;
-- The four Phase 1 Entitlements as 'TTTT'/'FFFF' (any mix is itself a defect).
create function pg_temp.ent(organization uuid) returns text language sql as $$
    select string_agg(case when public.organization_has_professional_entitlement(organization, identifier)
        then 'T' else 'F' end, '' order by ordinality)
    from unnest(array['APPOINTMENT_MANAGEMENT', 'PROFESSIONAL_SCHEDULING', 'CLINICAL_CARE',
        'CLINICAL_DOCUMENTATION']) with ordinality as identifier
$$;
create function pg_temp.status(actor integer, organization uuid) returns jsonb language plpgsql as $$
declare result jsonb; begin
    perform pg_temp.act(actor);
    result := public.get_organization_subscription_status(organization);
    return result;
exception when others then
    return jsonb_build_object('error', sqlstate || ':' || sqlerrm);
end $$;

-- ===========================================================================
-- Contract and ACLs
-- ===========================================================================

select pg_temp.assert_true(
    has_function_privilege('service_role', 'public.apply_subscription_state_transition(uuid, text, timestamptz, timestamptz, timestamptz, text, text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.apply_subscription_state_transition(uuid, text, timestamptz, timestamptz, timestamptz, text, text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.apply_subscription_state_transition(uuid, text, timestamptz, timestamptz, timestamptz, text, text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.establish_organization_subscription(uuid, uuid, text, timestamptz, timestamptz, timestamptz, text, uuid, jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.subscription_transition_is_allowed(text, text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.subscription_transition_is_allowed(text, text)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.subscription_transition_is_allowed(text, text)', 'EXECUTE'),
    'Transitions and establishment stay trusted; no client role can execute them'
);
select pg_temp.assert_true(
    has_function_privilege('authenticated', 'public.get_organization_subscription_status(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_organization_subscription_status(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_organization_subscription_status(uuid)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.get_organization_subscription_status(uuid)', 'EXECUTE')
    and (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
             and pg_get_function_result(p.oid) = 'jsonb'
         from pg_proc p where p.oid = 'public.get_organization_subscription_status(uuid)'::regprocedure),
    'Status read is authenticated-only, STABLE, SECURITY DEFINER with an empty search_path'
);

-- ===========================================================================
-- Fixture actors. Organization A (3,1) with published Clinic (4,1); B (3,2).
--  1 Owner of A        2 Organization Administrator of A
--  3 Clinic Administrator of A (Clinic 4,1)      4 Organization Receptionist of A
--  5 Veterinarian of A (Profile + Clinic Assignment)   6 Owner of B
--  7 authenticated User without Membership   8 subject without a domain User
--  9 former Administrator of A (ended)       10 Guardian
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'sub-' || n || '@example.test', '2020-01-01Z' from generate_series(1, 10) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 10) n where n <> 8;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 10) n where n <> 8;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Sub Org A'), (pg_temp.id(3, 2), 'Sub Org B');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.id(4, 1), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.id(4, 1), 'Sub Clinic A');
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)
values (pg_temp.id(4, 1), 'Calle Ficticia 1, Madrid', 40.4168, -3.7038);
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.id(4, 1), d, '00:00', '24:00' from generate_series(1, 7) d;
-- Clinic (4,2) of entitled Organization B: published and configured, but
-- with no Appointment availability at all.
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.id(4, 2), pg_temp.id(3, 2), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.id(4, 2), 'Sub Clinic B');
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)
values (pg_temp.id(4, 2), 'Calle Ficticia 2, Madrid', 40.4170, -3.7040);
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.id(5, 900 + n), pg_temp.id(3, case when n = 6 then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z',
    case when n = 9 then '2021-01-01Z'::timestamptz end, case when n = 9 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 9]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, 900 + n), pg_temp.id(5, 900 + n),
    case n when 1 then 'OWNER' when 6 then 'OWNER' when 2 then 'ADMINISTRATOR' when 9 then 'ADMINISTRATOR'
        when 3 then 'ADMINISTRATOR' when 4 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n = 3 then 'CLINIC' else 'ORGANIZATION' end, case when n = 3 then pg_temp.id(4, 1) end,
    '2020-01-01Z', case when n = 9 then '2021-01-01Z'::timestamptz end, pg_temp.id(2, 1),
    case when n = 9 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 9]) n;
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(7, 5), pg_temp.id(2, 5));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start)
values (pg_temp.id(8, 5), pg_temp.id(7, 5), pg_temp.id(5, 905), pg_temp.id(4, 1), '2020-01-01Z');
set local session_replication_role = origin;

-- Organization A: open-ended manual ACTIVE (the default Phase 1 model),
-- carrying provider references and an internal source that must never leak.
select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'operator-secret-source', pg_temp.id(20, 1),
    '[{"provider": "acme-billing", "reference_kind": "CUSTOMER", "opaque_reference": "cus_SECRET_REF"}]'::jsonb);
select public.establish_organization_subscription(pg_temp.id(3, 2), null, 'ACTIVE', '2020-01-01Z', null, null,
    'sub-safety-suite', pg_temp.id(20, 2), null);
select pg_temp.flush();

-- ===========================================================================
-- Open-ended manual ACTIVE: no silent lapse, explicit transitions only
-- ===========================================================================

do $$
declare sub uuid; org uuid := pg_temp.org(300); t timestamptz := statement_timestamp(); begin
    sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 300);
    perform pg_temp.assert_true(pg_temp.ent(org) = 'TTTT' and pg_temp.state(sub) = 'ACTIVE'
        and (select current_commercial_valid_until is null
             from public.derive_organization_subscription_current_state(sub)),
        'Open-ended ACTIVE keeps every Entitlement');
    perform pg_temp.assert_true(pg_temp.transitions(sub) = 0,
        'Open-ended ACTIVE needs no scheduler or implicit transition');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null) like 'OK:PAST_DUE:%'
        and pg_temp.ent(org) = 'FFFF', 'PAST_DUE grants no Entitlement');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'ACTIVE', '2022-01-01Z', null, null) like 'OK:ACTIVE:%'
        and pg_temp.ent(org) = 'TTTT', 'PAST_DUE recovers to ACTIVE with Entitlements restored');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'CANCELLED', '2023-01-01Z', null, t + interval '30 days')
            like 'OK:CANCELLED:%' and pg_temp.ent(org) = 'TTTT',
        'CANCELLED keeps Entitlement while its validity end is in the future');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'EXPIRED', '2024-01-01Z', null, null) like 'OK:EXPIRED:%'
        and pg_temp.ent(org) = 'FFFF', 'CANCELLED moves to EXPIRED and loses Entitlement');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'ACTIVE', '2025-01-01Z', null, null)
            = 'ERR:23514:SUBSCRIPTION_EXPIRED_TERMINAL'
        and pg_temp.transitions(sub) = 4 and pg_temp.state(sub) = 'EXPIRED', 'EXPIRED is terminal');
    -- A new Subscription period restarts service; the expired period is kept.
    perform pg_temp.establish(org, 'ACTIVE', '2025-02-01Z', null, null, 301);
    perform pg_temp.assert_true(pg_temp.ent(org) = 'TTTT' and pg_temp.state(sub) = 'EXPIRED'
        and pg_temp.transitions(sub) = 4
        and (select count(*) = 2 from public.organization_subscriptions where organization_id = org),
        'A new Subscription period after EXPIRED restores Entitlements and preserves the expired period');
end $$;

-- A second current relationship is never possible.
do $$
declare org uuid := pg_temp.org(302); failure text; begin
    perform pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 302);
    begin
        perform pg_temp.establish(org, 'ACTIVE', '2021-01-01Z', null, null, 303);
        failure := 'none';
    exception when others then failure := sqlstate;
    end;
    perform pg_temp.assert_true(failure = '23514',
        'A successor cannot be established while a non-EXPIRED Subscription occupies the relationship');
end $$;

-- ===========================================================================
-- Validity: per transition, never inherited
-- ===========================================================================

do $$
declare sub uuid; org uuid; t timestamptz := statement_timestamp(); begin
    org := pg_temp.org(310);
    sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', '2020-01-01Z', t + interval '10 days', 310);
    perform pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null);
    perform pg_temp.transition(sub, 'ACTIVE', '2022-01-01Z', null, null);
    perform pg_temp.assert_true(pg_temp.ent(org) = 'TTTT'
        and (select current_commercial_valid_from is null and current_commercial_valid_until is null
             from public.derive_organization_subscription_current_state(sub)),
        'Omitted validity is not inherited');
    org := pg_temp.org(311);
    sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, t + interval '10 days', 311);
    perform pg_temp.assert_true(pg_temp.transition(sub, 'CANCELLED', '2021-01-01Z', null, null) like 'OK:CANCELLED:%'
        and pg_temp.ent(org) = 'FFFF', 'CANCELLED without validity end grants no Entitlement');
end $$;

-- ===========================================================================
-- Entitlement boundaries, evaluated at the statement instant t
-- ===========================================================================

do $$
declare t timestamptz := statement_timestamp();
    cases constant jsonb := jsonb_build_array(
        jsonb_build_array('ACTIVE', 'from_after', 'FFFF', 'ACTIVE before valid_from'),
        jsonb_build_array('ACTIVE', 'from_now', 'TTTT', 'ACTIVE exactly at valid_from'),
        jsonb_build_array('ACTIVE', 'inside', 'TTTT', 'ACTIVE inside its validity'),
        jsonb_build_array('ACTIVE', 'until_now', 'FFFF', 'ACTIVE exactly at valid_until'),
        jsonb_build_array('ACTIVE', 'until_before', 'FFFF', 'ACTIVE after valid_until'),
        jsonb_build_array('ACTIVE', 'none', 'TTTT', 'ACTIVE with both bounds null'),
        jsonb_build_array('ACTIVE', 'until_after', 'TTTT', 'ACTIVE with only a future valid_until'),
        jsonb_build_array('CANCELLED', 'until_after', 'TTTT', 'CANCELLED before valid_until'),
        jsonb_build_array('CANCELLED', 'until_now', 'FFFF', 'CANCELLED exactly at valid_until'),
        jsonb_build_array('CANCELLED', 'until_before', 'FFFF', 'CANCELLED after valid_until'),
        jsonb_build_array('CANCELLED', 'none', 'FFFF', 'CANCELLED without valid_until'),
        jsonb_build_array('CANCELLED', 'from_after', 'FFFF', 'CANCELLED before valid_from'),
        jsonb_build_array('PENDING', 'inside', 'FFFF', 'PENDING'),
        jsonb_build_array('PAST_DUE', 'inside', 'FFFF', 'PAST_DUE'),
        jsonb_build_array('EXPIRED', 'inside', 'FFFF', 'EXPIRED'));
    item jsonb; i integer := 0; org uuid; valid_from timestamptz; valid_until timestamptz; begin
    for item in select value from jsonb_array_elements(cases) loop
        i := i + 1;
        org := pg_temp.org(400 + i);
        valid_from := case item ->> 1 when 'from_after' then t + interval '1 microsecond'
            when 'from_now' then t when 'inside' then t - interval '1 day' end;
        valid_until := case item ->> 1 when 'from_after' then t + interval '2 days'
            when 'inside' then t + interval '1 day' when 'until_now' then t
            when 'until_before' then t - interval '1 microsecond' when 'until_after' then t + interval '1 day' end;
        perform pg_temp.in_state(org, item ->> 0, valid_from, valid_until, 400 + i);
        perform pg_temp.assert_true(pg_temp.ent(org) = item ->> 2, 'Entitlement boundary: ' || (item ->> 3));
    end loop;
    perform pg_temp.assert_true(pg_temp.ent(pg_temp.org(499)) = 'FFFF', 'No Subscription grants no Entitlement');
end $$;

-- ===========================================================================
-- The Phase 1 transition graph: every pair, from an established state
-- ===========================================================================

do $$
declare states constant text[] := array['PENDING', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED'];
    allowed constant text[] := array['PENDING>ACTIVE', 'PENDING>EXPIRED', 'ACTIVE>PAST_DUE', 'ACTIVE>CANCELLED',
        'ACTIVE>EXPIRED', 'PAST_DUE>ACTIVE', 'PAST_DUE>EXPIRED', 'CANCELLED>EXPIRED'];
    from_state text; to_state text; i integer := 0; sub uuid; outcome text; accepted integer := 0;
    before_count bigint; begin
    foreach from_state in array states loop
        foreach to_state in array states loop
            i := i + 1;
            sub := pg_temp.in_state(pg_temp.org(500 + i), from_state, null, null, 500 + i);
            before_count := pg_temp.transitions(sub);
            outcome := pg_temp.transition(sub, to_state, '2021-01-01Z', null, null);
            if from_state || '>' || to_state = any(allowed) then
                accepted := accepted + 1;
                perform pg_temp.assert_true(outcome like 'OK:' || to_state || ':%' and pg_temp.state(sub) = to_state
                    and pg_temp.transitions(sub) = before_count + 1,
                    'Every allowed transition succeeds: ' || from_state || ' -> ' || to_state);
            elsif from_state = 'EXPIRED' then
                perform pg_temp.assert_true(outcome = 'ERR:23514:SUBSCRIPTION_EXPIRED_TERMINAL'
                    and pg_temp.transitions(sub) = before_count, 'EXPIRED is terminal');
            elsif from_state = to_state then
                perform pg_temp.assert_true(outcome = 'ERR:23514:SUBSCRIPTION_TRANSITION_NOT_ALLOWED'
                    and pg_temp.transitions(sub) = before_count, 'Same-state transitions are rejected');
            else
                perform pg_temp.assert_true(outcome = 'ERR:23514:SUBSCRIPTION_TRANSITION_NOT_ALLOWED'
                    and pg_temp.transitions(sub) = before_count and pg_temp.state(sub) = from_state,
                    'Every forbidden transition is rejected without writing');
            end if;
        end loop;
    end loop;
    perform pg_temp.assert_true(accepted = 8, 'Exactly the eight Phase 1 transitions are accepted');
end $$;

-- ===========================================================================
-- PENDING closure: a relationship that never became active
-- ===========================================================================

do $$
declare org uuid := pg_temp.org(620); sub uuid; begin
    sub := pg_temp.establish(org, 'PENDING', '2020-01-01Z', null, null, 620);
    perform pg_temp.assert_true(
        pg_temp.transition(sub, 'CANCELLED', '2021-01-01Z', null, null) = 'ERR:23514:SUBSCRIPTION_TRANSITION_NOT_ALLOWED'
        and pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null) = 'ERR:23514:SUBSCRIPTION_TRANSITION_NOT_ALLOWED'
        and pg_temp.transitions(sub) = 0,
        'PENDING cannot be cancelled or become past due');
    perform pg_temp.assert_true(
        pg_temp.transition(sub, 'EXPIRED', '2021-01-01Z', null, null) like 'OK:EXPIRED:%'
        and pg_temp.state(sub) = 'EXPIRED' and pg_temp.ent(org) = 'FFFF'
        and pg_temp.transition(sub, 'ACTIVE', '2022-01-01Z', null, null) = 'ERR:23514:SUBSCRIPTION_EXPIRED_TERMINAL',
        'PENDING closes permanently through EXPIRED');
    perform pg_temp.establish(org, 'ACTIVE', '2022-01-01Z', null, null, 621);
    perform pg_temp.assert_true(pg_temp.ent(org) = 'TTTT' and pg_temp.state(sub) = 'EXPIRED',
        'A closed PENDING period leaves room for a new Subscription period');
end $$;

-- ===========================================================================
-- Establishment: Phase 1 initial state
-- ===========================================================================

do $$
declare outcome text; first text; t timestamptz := statement_timestamp(); pending_ok text; active_ok text; begin
    -- Each call runs in its own statement so the checks below see its result.
    pending_ok := pg_temp.try_establish(pg_temp.org(630), 'PENDING', '2020-01-01Z', null, null, 630);
    active_ok := pg_temp.try_establish(pg_temp.org(631), 'ACTIVE', '2020-01-01Z', null, null, 631);
    perform pg_temp.assert_true(
        pending_ok like 'OK:%' and active_ok like 'OK:%'
        and (select current_state = 'ACTIVE' and current_commercial_valid_until is null
             from public.organization_subscriptions s
             cross join lateral public.derive_organization_subscription_current_state(s.id)
             where s.organization_id = pg_temp.id(3, 631)),
        'Establishment accepts PENDING and an open-ended ACTIVE');
    perform pg_temp.assert_true(
        pg_temp.try_establish(pg_temp.org(632), 'PAST_DUE', '2020-01-01Z', null, null, 632) = 'ERR:23514:INITIAL_STATE_NOT_ALLOWED'
        and pg_temp.try_establish(pg_temp.org(633), 'CANCELLED', '2020-01-01Z', null, t + interval '1 day', 633) = 'ERR:23514:INITIAL_STATE_NOT_ALLOWED'
        and pg_temp.try_establish(pg_temp.org(634), 'EXPIRED', '2020-01-01Z', null, null, 634) = 'ERR:23514:INITIAL_STATE_NOT_ALLOWED'
        and not exists (select 1 from public.organization_subscriptions
                        where organization_id in (pg_temp.id(3, 632), pg_temp.id(3, 633), pg_temp.id(3, 634))),
        'Establishment rejects PAST_DUE, CANCELLED and EXPIRED initial states');
    perform pg_temp.assert_true(
        pg_temp.try_establish(pg_temp.org(635), 'ACTIVE', t + interval '1 microsecond', null, null, 635) = 'ERR:23514:FUTURE_EFFECTIVE_AT'
        and pg_temp.try_establish(pg_temp.org(636), 'PENDING', t + interval '30 days', null, null, 636) = 'ERR:23514:FUTURE_EFFECTIVE_AT'
        and not exists (select 1 from public.organization_subscriptions
                        where organization_id in (pg_temp.id(3, 635), pg_temp.id(3, 636))),
        'Establishment rejects a future-dated initial state');
    outcome := pg_temp.try_establish(pg_temp.org(637), 'ACTIVE', t, null, null, 637);
    perform pg_temp.assert_true(
        outcome like 'OK:%'
        and (select initial_state_effective_at = t from public.organization_subscriptions
             where organization_id = pg_temp.id(3, 637)),
        'Establishment at exactly the current instant is accepted');
    first := pg_temp.try_establish(pg_temp.org(638), 'ACTIVE', '2020-01-01Z', null, null, 638);
    perform pg_temp.assert_true(first like 'OK:%'
        and pg_temp.try_establish(pg_temp.id(3, 638), 'ACTIVE', '2020-01-01Z', null, null, 638) = first
        and (select count(*) = 1 from public.organization_subscriptions where organization_id = pg_temp.id(3, 638)),
        'An exact establishment replay returns the same Subscription');
    outcome := pg_temp.try_establish(pg_temp.id(3, 638), 'PENDING', '2020-01-01Z', null, null, 638);
    perform pg_temp.assert_true(outcome like 'ERR:23505:%'
        and (select count(*) = 1 from public.organization_subscriptions where organization_id = pg_temp.id(3, 638)),
        'A contradictory establishment replay is rejected');
end $$;

-- ===========================================================================
-- Temporal rules
-- ===========================================================================

do $$
declare sub uuid; outcome text; begin
    sub := pg_temp.establish(pg_temp.org(600), 'ACTIVE', '2020-01-01Z', null, null, 600);
    perform pg_temp.assert_true(
        pg_temp.transition(sub, 'PAST_DUE', statement_timestamp() + interval '1 microsecond', null, null)
            = 'ERR:23514:FUTURE_EFFECTIVE_AT'
        and pg_temp.transition(sub, 'CANCELLED', statement_timestamp() + interval '30 days', null, null)
            = 'ERR:23514:FUTURE_EFFECTIVE_AT'
        and pg_temp.transitions(sub) = 0, 'A future-dated transition is rejected');
    perform pg_temp.assert_true(
        pg_temp.transition(sub, 'PAST_DUE', '2020-01-01Z', null, null) = 'ERR:23514:STALE_EFFECTIVE_AT'
        and pg_temp.transition(sub, 'PAST_DUE', '2019-01-01Z', null, null) = 'ERR:23514:STALE_EFFECTIVE_AT'
        and pg_temp.transitions(sub) = 0, 'A stale or equal effective time is rejected');
    outcome := pg_temp.transition(sub, 'PAST_DUE', statement_timestamp(), null, null);
    perform pg_temp.assert_true(outcome like 'OK:PAST_DUE:%'
        and (select effective_at = statement_timestamp() from public.subscription_state_transitions
             where subscription_id = sub),
        'A transition at exactly the current instant is accepted');
end $$;

-- The insert trigger enforces the same policy on any insert path.
do $$
declare sub uuid; expired_sub uuid; failure text; begin
    sub := pg_temp.establish(pg_temp.org(610), 'ACTIVE', '2020-01-01Z', null, null, 610);
    expired_sub := pg_temp.in_state(pg_temp.org(611), 'EXPIRED', null, null, 611);
    begin
        insert into public.subscription_state_transitions (subscription_id, from_state, to_state, effective_at,
            recorded_at, source_system) values (sub, 'ACTIVE', 'PENDING', '2021-01-01Z', clock_timestamp(), 'direct');
        failure := 'none';
    exception when others then get stacked diagnostics failure = pg_exception_hint;
    end;
    perform pg_temp.assert_true(failure = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED',
        'The insert trigger enforces the Phase 1 graph');
    begin
        insert into public.subscription_state_transitions (subscription_id, from_state, to_state, effective_at,
            recorded_at, source_system) values (sub, 'ACTIVE', 'PAST_DUE', statement_timestamp() + interval '1 day',
            clock_timestamp(), 'direct');
        failure := 'none';
    exception when others then get stacked diagnostics failure = pg_exception_hint;
    end;
    perform pg_temp.assert_true(failure = 'FUTURE_EFFECTIVE_AT', 'The insert trigger rejects future transitions');
    begin
        insert into public.subscription_state_transitions (subscription_id, from_state, to_state, effective_at,
            recorded_at, source_system) values (expired_sub, 'EXPIRED', 'ACTIVE', '2021-01-01Z', clock_timestamp(), 'direct');
        failure := 'none';
    exception when others then get stacked diagnostics failure = pg_exception_hint;
    end;
    perform pg_temp.assert_true(failure = 'SUBSCRIPTION_EXPIRED_TERMINAL', 'The insert trigger keeps EXPIRED terminal');
    perform pg_temp.assert_true(pg_temp.transitions(sub) = 0 and pg_temp.transitions(expired_sub) = 1,
        'Rejected direct inserts write nothing');
end $$;

-- ===========================================================================
-- Idempotency
-- ===========================================================================

do $$
declare sub uuid; first text; replay text; begin
    sub := pg_temp.establish(pg_temp.org(700), 'ACTIVE', '2020-01-01Z', null, null, 700);
    first := pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null, 'evt-1');
    replay := pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null, 'evt-1');
    perform pg_temp.assert_true(first like 'OK:PAST_DUE:%' and replay = first and pg_temp.transitions(sub) = 1,
        'The same source event reproduces the same accepted transition');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'EXPIRED', '2021-01-01Z', null, null, 'evt-1')
            = 'ERR:23505:' || 'Subscription source event evt-1 under sub-safety-suite was already recorded with different facts'
        and pg_temp.transitions(sub) = 1, 'Contradictory reuse of a source event is rejected');
    perform pg_temp.transition(sub, 'ACTIVE', '2022-01-01Z', null, null, 'evt-2');
    perform pg_temp.assert_true(pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null, 'evt-1') = first
        and pg_temp.transitions(sub) = 2 and pg_temp.state(sub) = 'ACTIVE',
        'An earlier accepted event is still recognized after later transitions');
    first := pg_temp.transition(sub, 'PAST_DUE', '2023-01-01Z', null, null);
    perform pg_temp.assert_true(first like 'OK:PAST_DUE:%' and pg_temp.transition(sub, 'PAST_DUE', '2023-01-01Z', null, null) = first
        and pg_temp.transitions(sub) = 3, 'A semantic replay without a source event key is recognized');
end $$;

-- ===========================================================================
-- Status read (SPEC-SUB-002 §15)
-- ===========================================================================

do $$
declare denied jsonb; result jsonb; begin
    denied := pg_temp.status(7, pg_temp.id(3, 1));
    perform pg_temp.assert_true(denied ->> 'error' like '42501:%', 'Users without Membership are denied');
    perform pg_temp.assert_true(
        pg_temp.status(3, pg_temp.id(3, 1)) = denied and pg_temp.status(4, pg_temp.id(3, 1)) = denied
        and pg_temp.status(5, pg_temp.id(3, 1)) = denied and pg_temp.status(9, pg_temp.id(3, 1)) = denied
        and pg_temp.status(10, pg_temp.id(3, 1)) = denied,
        'Only ORGANIZATION_MANAGE_SUBSCRIPTION holders read the status');
    perform pg_temp.assert_true(
        pg_temp.status(6, pg_temp.id(3, 1)) = denied and pg_temp.status(1, pg_temp.id(3, 2)) = denied
        and pg_temp.status(1, pg_temp.id(3, 999)) = denied and pg_temp.status(1, null) = denied,
        'Inaccessible and unknown Organizations fail identically');
    perform pg_temp.assert_true(
        pg_temp.status(0, pg_temp.id(3, 1)) ->> 'error' like '28000:%'
        and pg_temp.status(8, pg_temp.id(3, 1)) ->> 'error' like '28000:%',
        'Unauthenticated and incoherent callers are rejected with 28000');
    result := pg_temp.status(1, pg_temp.id(3, 1));
    perform pg_temp.assert_true(
        result::text not like '%SECRET%' and result::text not like '%acme-billing%'
        and result::text not like '%operator-secret-source%' and result::text not like '%' || pg_temp.id(20, 1) || '%'
        and result::text not like '%' || (select id from public.organization_subscriptions
            where organization_id = pg_temp.id(3, 1))::text || '%',
        'Status read exposes no provider or internal commercial data');
    perform pg_temp.assert_true(
        (select array_agg(k order by k) from jsonb_object_keys(result) k)
            = array['entitlements', 'organization_display_name', 'organization_id', 'subscription']
        and (select array_agg(k order by k) from jsonb_object_keys(result -> 'subscription') k)
            = array['state', 'state_effective_at', 'valid_from', 'valid_until']
        and (select array_agg(k order by k) from jsonb_object_keys(result -> 'entitlements') k)
            = array['APPOINTMENT_MANAGEMENT', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION', 'PROFESSIONAL_SCHEDULING']
        and result ->> 'organization_id' = pg_temp.id(3, 1)::text
        and result ->> 'organization_display_name' = 'Sub Org A'
        and result -> 'subscription' ->> 'state' = 'ACTIVE'
        and result -> 'subscription' -> 'valid_until' = 'null'::jsonb
        and pg_temp.status(2, pg_temp.id(3, 1)) = result,
        'Owner and Organization Administrator read the exact status envelope');
end $$;

do $$
declare t timestamptz := statement_timestamp(); org uuid; sub uuid; result jsonb;
    cases jsonb := '[]'::jsonb; item jsonb; begin
    -- (label, Organization, expected state, expected Entitlements, valid_until expected null?)
    org := pg_temp.org(800);
    cases := cases || jsonb_build_array(jsonb_build_array('no Subscription', org, null, false));
    org := pg_temp.org(801); perform pg_temp.establish(org, 'PENDING', '2020-01-01Z', null, null, 801);
    cases := cases || jsonb_build_array(jsonb_build_array('PENDING', org, 'PENDING', false));
    org := pg_temp.org(802); perform pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 802);
    cases := cases || jsonb_build_array(jsonb_build_array('ACTIVE open-ended', org, 'ACTIVE', true));
    org := pg_temp.org(803); perform pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', '2020-01-01Z', t + interval '5 days', 803);
    cases := cases || jsonb_build_array(jsonb_build_array('ACTIVE finite current', org, 'ACTIVE', true));
    org := pg_temp.org(804); perform pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', '2020-01-01Z', t - interval '1 day', 804);
    cases := cases || jsonb_build_array(jsonb_build_array('ACTIVE finite lapsed', org, 'ACTIVE', false));
    org := pg_temp.org(805); sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 805);
    perform pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null);
    cases := cases || jsonb_build_array(jsonb_build_array('PAST_DUE', org, 'PAST_DUE', false));
    org := pg_temp.org(806); sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 806);
    perform pg_temp.transition(sub, 'CANCELLED', '2021-01-01Z', null, t + interval '5 days');
    cases := cases || jsonb_build_array(jsonb_build_array('CANCELLED within validity', org, 'CANCELLED', true));
    org := pg_temp.org(807); sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 807);
    perform pg_temp.transition(sub, 'CANCELLED', '2021-01-01Z', null, t - interval '1 day');
    cases := cases || jsonb_build_array(jsonb_build_array('CANCELLED after validity', org, 'CANCELLED', false));
    org := pg_temp.org(808); sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 808);
    perform pg_temp.transition(sub, 'EXPIRED', '2021-01-01Z', null, null);
    cases := cases || jsonb_build_array(jsonb_build_array('EXPIRED', org, 'EXPIRED', false));
    -- Two expired periods, then the later one is described.
    org := pg_temp.org(809); sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 809);
    perform pg_temp.transition(sub, 'EXPIRED', '2021-01-01Z', null, null);
    sub := pg_temp.establish(org, 'PENDING', '2022-01-01Z', null, null, 810);
    perform pg_temp.transition(sub, 'ACTIVE', '2022-06-01Z', null, null);
    perform pg_temp.transition(sub, 'EXPIRED', '2023-01-01Z', null, null);
    cases := cases || jsonb_build_array(jsonb_build_array('latest EXPIRED period', org, 'EXPIRED', false));
    -- An expired period followed by a current one: the current one is described.
    org := pg_temp.org(811); sub := pg_temp.establish(org, 'ACTIVE', '2020-01-01Z', null, null, 811);
    perform pg_temp.transition(sub, 'EXPIRED', '2021-01-01Z', null, null);
    perform pg_temp.establish(org, 'ACTIVE', '2022-01-01Z', null, null, 812);
    cases := cases || jsonb_build_array(jsonb_build_array('current period after EXPIRED', org, 'ACTIVE', true));

    for item in select value from jsonb_array_elements(cases) loop
        result := pg_temp.status(1, (item ->> 1)::uuid);
        perform pg_temp.assert_true(
            result -> 'subscription' ->> 'state' is not distinct from item ->> 2
            and (item ->> 2 is not null or result -> 'subscription' = 'null'::jsonb)
            and (select bool_and(value::boolean = (item ->> 3)::boolean)
                 from jsonb_each_text(result -> 'entitlements')),
            'Status reports stored state and Entitlement availability');
    end loop;
    result := pg_temp.status(1, pg_temp.id(3, 804));
    perform pg_temp.assert_true(result -> 'subscription' ->> 'state' = 'ACTIVE'
        and (result -> 'subscription' ->> 'valid_until')::timestamptz < t,
        'A lapsed ACTIVE is reported as ACTIVE, never EXPIRED');
    result := pg_temp.status(1, pg_temp.id(3, 809));
    perform pg_temp.assert_true((result -> 'subscription' ->> 'state_effective_at')::timestamptz = '2023-01-01Z',
        'Without a current relationship the latest established period is described');
end $$;

-- ===========================================================================
-- Public / Guardian boundary after Entitlement loss (SPEC-SUB-003 §15)
-- ===========================================================================

do $$
declare sub uuid; before_count integer; after_count integer; public_payload text; begin
    perform pg_temp.act(10);
    select count(*) into before_count
    from public.get_requestable_appointment_start_times(pg_temp.id(4, 1), current_date + 1, current_date + 3);
    perform pg_temp.assert_true(before_count > 0, 'Positive control: an entitled published Clinic offers times');

    select id into sub from public.organization_subscriptions where organization_id = pg_temp.id(3, 1);
    perform pg_temp.transition(sub, 'PAST_DUE', '2021-01-01Z', null, null);
    perform pg_temp.act(10);
    select count(*) into after_count
    from public.get_requestable_appointment_start_times(pg_temp.id(4, 1), current_date + 1, current_date + 3);
    public_payload := coalesce((select jsonb_agg(l)::text from public.get_published_clinic_location(pg_temp.id(4, 1)) l), '')
        || coalesce((select jsonb_agg(p)::text from public.published_clinic_public_profiles p
                     where p.clinic_id = pg_temp.id(4, 1)), '')
        || coalesce(public.discover_clinics_in_viewport(40, 41, -4, -3, 100, null)::text, '');
    perform pg_temp.assert_true(after_count = 0
        and (select is_published from public.clinics where id = pg_temp.id(4, 1))
        and public_payload like '%' || pg_temp.id(4, 1) || '%'
        and public_payload like '%Sub Clinic A%',
        'A lapsed published Clinic stays published and discoverable but offers no times');
    -- The lapsed Clinic's empty result is indistinguishable from an entitled
    -- Clinic that simply has no availability (SPEC-APT-014 BR-4/BR-5).
    perform pg_temp.act(10);
    perform pg_temp.assert_true(
        public.organization_has_professional_entitlement(pg_temp.id(3, 2), 'APPOINTMENT_MANAGEMENT')
        and not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'APPOINTMENT_MANAGEMENT')
        and (select coalesce(jsonb_agg(c), '[]'::jsonb) from public.get_requestable_appointment_start_times(
                pg_temp.id(4, 1), current_date + 1, current_date + 3) c)
          = (select coalesce(jsonb_agg(c), '[]'::jsonb) from public.get_requestable_appointment_start_times(
                pg_temp.id(4, 2), current_date + 1, current_date + 3) c),
        'Empty requestable times do not reveal Entitlement loss');
    perform pg_temp.assert_true(public_payload not like '%PAST_DUE%' and public_payload not like '%ACTIVE%'
        and public_payload not ilike '%subscription%' and public_payload not ilike '%valid_until%'
        and public_payload not ilike '%entitlement%',
        'Public reads expose no commercial state');
    perform pg_temp.act(1);
    perform pg_temp.assert_true(public.get_my_professional_context()::text not ilike '%valid_until%'
        and public.get_my_professional_context()::text not like '%PAST_DUE%',
        'Professional context still excludes commercial state and dates');
end $$;

rollback;

-- Clinic creation self-service Phase 1: SPEC-CLI-001 §10 (BR-12–BR-16) and
-- Verification Notes 1–19, SPEC-ORG-005 capability catalog, SPEC-ORG-008
-- BR-3, SPEC-CLI-003/004/002/007 and SPEC-APT-013 compatibility.
-- Isolated LOCAL superuser only; fixtures, helper substitutions and assertions
-- are rollback-only. Behaviour is exercised through the real operations.
-- Multi-session races are pinned by run_clinic_creation_concurrency.py and
-- mutants by run_clinic_creation_faults.py.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0300000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.subject(n integer) returns uuid language sql immutable as $$
    select case when n = 0 then null else pg_temp.id(1, n) end
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(pg_temp.subject(n)::text, ''), true)
$$;
-- Creation keys are fixture identifiers too (prefix-checked for zero retention).
create function pg_temp.key(n integer) returns uuid language sql immutable as $$
    select pg_temp.id(20, n)
$$;
-- Deferred integrity triggers fire inside the call, as at commit.
create function pg_temp.create(actor integer, organization uuid, creation_key uuid) returns text language plpgsql as $$
declare result jsonb; begin
    perform pg_temp.act(actor);
    result := public.create_clinic(organization, creation_key);
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return result::text;
exception when others then
    return sqlstate || ':' || sqlerrm;
end $$;
create function pg_temp.create_json(actor integer, organization uuid, creation_key uuid) returns jsonb language sql as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
    from pg_temp.create(actor, organization, creation_key) result
$$;
create function pg_temp.clinic_count(organization uuid) returns bigint language sql as $$
    select count(*) from public.clinics where organization_id = organization
$$;
-- Every row that could configure, staff or schedule one Clinic.
create function pg_temp.clinic_rows(target uuid) returns bigint language sql as $$
    select (select count(*) from public.clinic_public_profiles where clinic_id = target)
        + (select count(*) from public.clinic_locations where clinic_id = target)
        + (select count(*) from public.clinic_service_offerings where clinic_id = target)
        + (select count(*) from public.clinic_opening_periods where clinic_id = target)
        + (select count(*) from public.clinic_opening_exceptions where clinic_id = target)
        + (select count(*) from public.clinic_appointment_availability_periods where clinic_id = target)
        + (select count(*) from public.clinic_appointment_availability_exceptions where clinic_id = target)
        + (select count(*) from public.veterinarian_clinic_assignments where clinic_id = target)
        + (select count(*) from public.organization_responsibility_grants where clinic_id = target)
        + (select count(*) from public.organization_invitation_responsibilities where clinic_id = target)
        + (select count(*) from public.appointments where clinic_id = target)
        + (select count(*) from public.care_authorizations where clinic_id = target)
        + (select count(*) from public.clinical_record_entries as entry_row
           join public.appointments as appointment on appointment.id = entry_row.appointment_id
           where appointment.clinic_id = target)
$$;
-- Everything creation must never touch.
create function pg_temp.untouched_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(o) order by o.id)::text from public.veterinary_organizations o), '')
        || coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), '')
        || coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), '')
        || coalesce((select jsonb_agg(to_jsonb(i) order by i.id)::text from public.organization_invitations i), '')
        || coalesce((select jsonb_agg(to_jsonb(s) order by s.id)::text from public.organization_subscriptions s), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a), '')
        || coalesce((select jsonb_agg(to_jsonb(p) order by p.id)::text from public.veterinarian_professional_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(u) order by u.id)::text from public.users u), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.transactional_communications c), ''))
$$;
create function pg_temp.existing_clinic_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.clinics c
            where c.id in (pg_temp.id(4, 1), pg_temp.id(4, 2))), '')
        || coalesce((select jsonb_agg(to_jsonb(p) order by p.clinic_id)::text from public.clinic_public_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(l) order by l.clinic_id)::text from public.clinic_locations l), ''))
$$;
create function pg_temp.professional_clinic_ids(actor integer) returns uuid[] language plpgsql as $$
declare result uuid[]; begin
    perform pg_temp.act(actor);
    select coalesce(array_agg((value ->> 'clinic_id')::uuid order by value ->> 'clinic_id'), '{}') into result
    from jsonb_array_elements(public.get_my_professional_clinics() -> 'clinics') value;
    return result;
end $$;
create function pg_temp.reports_create_capability(actor integer, organization uuid) returns boolean language plpgsql as $$
declare result boolean; begin
    perform pg_temp.act(actor);
    select exists (
        select 1
        from jsonb_array_elements(public.get_my_professional_context() -> 'organizations') org,
             jsonb_array_elements(org -> 'capabilities') capability
        where (org ->> 'organization_id')::uuid = organization
          and capability ->> 'capability' = 'ORGANIZATION_CREATE_CLINICS'
          and capability ->> 'scope_type' = 'ORGANIZATION'
    ) into result;
    return result;
end $$;
create function pg_temp.sqlstate_of(actor integer, statement text) returns text language plpgsql as $$
begin
    perform pg_temp.act(actor);
    execute statement;
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return '00000';
exception when others then return sqlstate; end $$;

set local session_replication_role = replica;
-- Actors (Auth subject n <-> domain User n). Organization A unless noted:
-- 1 Owner; 2 Organization Administrator; 3 Clinic Administrator (Clinic 1);
-- 4 Organization Receptionist; 5 Veterinarian (profile + Clinic 1 Assignment);
-- 6 Clinic Receptionist (Clinic 1); 7 Owner of B; 8 Administrator of B;
-- 9 former Administrator (Membership ended); 10 Owner of C (lock probe);
-- 15 no Membership; 16 authenticated subject without a domain User;
-- 18 Administrator whose Membership and Grant start tomorrow.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'create-' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 18]) n;
insert into public.users (id) select pg_temp.id(2, n)
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 18]) n;
insert into public.user_authentication_identities (user_id, provider_subject) select pg_temp.id(2, n), pg_temp.id(1, n)
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 18]) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Create Org A'), (pg_temp.id(3, 2), 'Create Org B'), (pg_temp.id(3, 3), 'Create Org C');
-- Clinic 1: published and configured in A. Clinic 2: unnamed in B.
insert into public.clinics (id, organization_id, is_published, created_at) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1), true, '2020-01-01Z'),
    (pg_temp.id(4, 2), pg_temp.id(3, 2), false, '2020-01-01Z');
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.id(4, 1), 'A Centro');
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)
values (pg_temp.id(4, 1), 'Calle Ficticia 1, Madrid', 40.4168, -3.7038);
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n in (7, 8) then 2 when n = 10 then 3 else 1 end), pg_temp.id(2, n),
    case when n = 18 then statement_timestamp() + interval '1 day' else '2020-01-01Z'::timestamptz end,
    case when n = 9 then '2021-01-01Z'::timestamptz end, case when n = 9 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 18]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case when n in (1, 7, 10) then 'OWNER' when n in (2, 3, 8, 9, 18) then 'ADMINISTRATOR'
         when n = 5 then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (3, 6) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (3, 6) then pg_temp.id(4, 1) end,
    case when n = 18 then statement_timestamp() + interval '1 day' else '2020-01-01Z'::timestamptz end,
    case when n = 9 then '2021-01-01Z'::timestamptz end, pg_temp.id(2, 1), case when n = 9 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 18]) n;
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(7, 5), pg_temp.id(2, 5));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values (pg_temp.id(8, 5), pg_temp.id(7, 5), pg_temp.id(5, 5), pg_temp.id(4, 1), '2020-01-01Z');
set local session_replication_role = origin;

create temporary table k_state (key text primary key, id uuid not null) on commit drop;

-- ---------------------------------------------------------------------------
-- Contract and ACL (BR-12, BR-14; Notes 19)
-- ---------------------------------------------------------------------------
select pg_temp.assert_true((select prosecdef and proconfig @> array['search_path=""'] and provolatile = 'v'
        and prorettype = 'jsonb'::regtype and proargnames = array['p_organization_id', 'p_idempotency_key']
        and pg_get_function_identity_arguments(oid) = 'p_organization_id uuid, p_idempotency_key uuid'
    from pg_proc where oid = 'public.create_clinic(uuid, uuid)'::regprocedure)
    and (select count(*) from pg_proc where proname = 'create_clinic' and pronamespace = 'public'::regnamespace) = 1,
    'Exact contract: SECURITY DEFINER, empty search_path, Organization and key only, jsonb result');
select pg_temp.assert_true(to_regprocedure('public.create_clinic(uuid)') is null,
    'The non-idempotent one-argument create_clinic is withdrawn');
select pg_temp.assert_true(has_function_privilege('authenticated', 'public.create_clinic(uuid, uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.create_clinic(uuid, uuid)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.create_clinic(uuid, uuid)', 'EXECUTE')
    and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = 'public.create_clinic(uuid, uuid)'::regprocedure)) acl
                    where acl.grantee = 0),
    'Create is executable by authenticated only');
select pg_temp.assert_true((select data_type = 'uuid' and is_nullable = 'YES' from information_schema.columns
        where table_schema = 'public' and table_name = 'clinics' and column_name = 'creation_idempotency_key')
    and (select contype = 'u' and pg_get_constraintdef(oid) = 'UNIQUE (organization_id, creation_idempotency_key)'
         from pg_constraint where conrelid = 'public.clinics'::regclass and conname = 'clinics_organization_creation_idempotency_key')
    and not has_table_privilege('authenticated', 'public.clinics', 'SELECT')
    and not has_table_privilege('anon', 'public.clinics', 'SELECT')
    and not has_column_privilege('authenticated', 'public.clinics', 'creation_idempotency_key', 'SELECT,UPDATE'),
    'Creation key is private, Organization-scoped operational metadata');

-- ---------------------------------------------------------------------------
-- Fixture positive controls
-- ---------------------------------------------------------------------------
select pg_temp.assert_true(not exists (select 1 from public.organization_subscriptions
        where organization_id in (pg_temp.id(3, 1), pg_temp.id(3, 2), pg_temp.id(3, 3)))
    and not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'APPOINTMENT_MANAGEMENT')
    and not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'PROFESSIONAL_SCHEDULING')
    and not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_CARE')
    and not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_DOCUMENTATION'),
    'Fixture: Organizations have no Subscription and no Entitlement');
select pg_temp.assert_true(public.user_has_organization_capability(pg_temp.id(2, 1), pg_temp.id(3, 1), 'ORGANIZATION_CREATE_CLINICS')
    and public.user_has_organization_capability(pg_temp.id(2, 2), pg_temp.id(3, 1), 'ORGANIZATION_CREATE_CLINICS')
    and public.user_has_clinic_capability(pg_temp.id(2, 3), pg_temp.id(4, 1), 'CLINIC_MANAGE_PUBLIC_PROFILE')
    and public.user_has_clinic_capability(pg_temp.id(2, 5), pg_temp.id(4, 1), 'CLINICAL_CARE')
    and public.user_has_clinic_capability(pg_temp.id(2, 6), pg_temp.id(4, 1), 'APPOINTMENT_VIEW_SCHEDULE'),
    'Fixture: every probed actor holds the authority it is meant to hold');

-- ---------------------------------------------------------------------------
-- Authentication and fail-closed authorization (BR-3, BR-13; Notes 11, 16)
-- ---------------------------------------------------------------------------
select pg_temp.assert_true(pg_temp.create(0, pg_temp.id(3, 1), pg_temp.key(1)) = '28000:Authentication is required'
    and pg_temp.create(16, pg_temp.id(3, 1), pg_temp.key(1)) = '28000:No coherent domain User exists for the authenticated subject',
    'Creation requires authentication and a coherent domain User');

do $$ declare denied text := '42501:Clinic-creation capability is required'; actor integer;
    before_a bigint := pg_temp.clinic_count(pg_temp.id(3, 1)); before_b bigint := pg_temp.clinic_count(pg_temp.id(3, 2));
    untouched text := pg_temp.untouched_state(); existing text := pg_temp.existing_clinic_state(); begin
    -- Clinic Administrator, Receptionists, Veterinarian, other Organization's
    -- Owner/Administrator, ended and not-yet-started authority, no Membership.
    foreach actor in array array[3, 4, 5, 6, 7, 8, 9, 15, 18] loop
        perform pg_temp.assert_true(pg_temp.create(actor, pg_temp.id(3, 1), pg_temp.key(1)) = denied
            and pg_temp.create(actor, pg_temp.id(3, 1), null) = denied,
            'Callers without ORGANIZATION_CREATE_CLINICS are denied uniformly');
    end loop;
    perform pg_temp.assert_true(pg_temp.create(1, pg_temp.id(3, 2), pg_temp.key(1)) = denied
        and pg_temp.create(1, pg_temp.id(3, 999), pg_temp.key(1)) = denied
        and pg_temp.create(1, null, pg_temp.key(1)) = denied
        and pg_temp.create(7, pg_temp.id(3, 1), pg_temp.key(1)) = denied,
        'Unknown and other-Organization targets fail identically');
    perform pg_temp.assert_true(pg_temp.clinic_count(pg_temp.id(3, 1)) = before_a
        and pg_temp.clinic_count(pg_temp.id(3, 2)) = before_b
        and pg_temp.untouched_state() = untouched and pg_temp.existing_clinic_state() = existing,
        'Denied attempts write nothing');
end $$;

select pg_temp.assert_true(pg_temp.create(1, pg_temp.id(3, 1), null) = '22023:Clinic creation key is required'
    and pg_temp.clinic_count(pg_temp.id(3, 1)) = 1,
    'An authorized creation without a key is rejected and writes nothing');

-- ---------------------------------------------------------------------------
-- Creation (BR-15; Notes 1, 3, 6–9, 12, 13)
-- ---------------------------------------------------------------------------
do $$ declare result jsonb; created uuid; untouched text := pg_temp.untouched_state();
    existing text := pg_temp.existing_clinic_state(); before_b bigint := pg_temp.clinic_count(pg_temp.id(3, 2)); begin
    result := pg_temp.create_json(1, pg_temp.id(3, 1), pg_temp.key(1));
    perform pg_temp.assert_true(result ->> 'outcome' = 'CREATED' and (result ->> 'clinic_id') is not null
        and (select count(*) from jsonb_object_keys(result)) = 3,
        'Owner creates a Clinic without any Subscription or Entitlement');
    created := (result ->> 'clinic_id')::uuid;
    perform pg_temp.assert_true((select organization_id = pg_temp.id(3, 1) from public.clinics where id = created)
        and (result ->> 'organization_id')::uuid = pg_temp.id(3, 1)
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 2 and pg_temp.clinic_count(pg_temp.id(3, 2)) = before_b,
        'The new Clinic belongs to exactly the target Organization');
    perform pg_temp.assert_true((select not is_published from public.clinics where id = created),
        'The new Clinic is unpublished');
    perform pg_temp.assert_true((select creation_idempotency_key = pg_temp.key(1) from public.clinics where id = created),
        'The new Clinic durably records its creation key');
    perform pg_temp.assert_true((select scheduling_timezone_name is null and standard_appointment_duration_minutes is null
            and weekly_appointment_availability_revision = 0 and created_at <= clock_timestamp()
        from public.clinics where id = created)
        and pg_temp.clinic_rows(created) = 0,
        'The new Clinic has no placeholder configuration');
    perform pg_temp.assert_true(pg_temp.untouched_state() = untouched,
        'Creation changes no Organization, Membership, Grant, Invitation, Subscription, Veterinarian or User');
    perform pg_temp.assert_true(pg_temp.existing_clinic_state() = existing, 'Existing Clinics are unaffected');
    insert into k_state values ('c1', created);
end $$;

-- ---------------------------------------------------------------------------
-- Idempotency (BR-14; Notes 14–16)
-- ---------------------------------------------------------------------------
do $$ declare c1 uuid := (select id from k_state where key = 'c1'); result jsonb; begin
    result := pg_temp.create_json(1, pg_temp.id(3, 1), pg_temp.key(1));
    perform pg_temp.assert_true(result = jsonb_build_object('clinic_id', c1, 'organization_id', pg_temp.id(3, 1),
            'outcome', 'ALREADY_CREATED')
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 2,
        'Replay with the same key returns the same Clinic and creates nothing');
    result := pg_temp.create_json(2, pg_temp.id(3, 1), pg_temp.key(1));
    perform pg_temp.assert_true((result ->> 'clinic_id')::uuid = c1 and result ->> 'outcome' = 'ALREADY_CREATED'
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 2,
        'Two authorized administrators with the same intent obtain one Clinic');
end $$;

do $$ declare c1 uuid := (select id from k_state where key = 'c1'); result jsonb; begin
    result := pg_temp.create_json(2, pg_temp.id(3, 1), pg_temp.key(2));
    perform pg_temp.assert_true(result ->> 'outcome' = 'CREATED' and (result ->> 'clinic_id')::uuid <> c1
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 3
        and (select creation_idempotency_key = pg_temp.key(2) and organization_id = pg_temp.id(3, 1)
             from public.clinics where id = (result ->> 'clinic_id')::uuid),
        'A different key creates another Clinic');
    insert into k_state values ('c2', (result ->> 'clinic_id')::uuid);
end $$;

do $$ declare c1 uuid := (select id from k_state where key = 'c1'); result jsonb; replay jsonb;
    c1_row text := (select to_jsonb(c)::text from public.clinics c where c.id = (select id from k_state where key = 'c1')); begin
    result := pg_temp.create_json(7, pg_temp.id(3, 2), pg_temp.key(1));
    replay := pg_temp.create_json(8, pg_temp.id(3, 2), pg_temp.key(1));
    perform pg_temp.assert_true(result ->> 'outcome' = 'CREATED' and (result ->> 'clinic_id')::uuid <> c1
        and (result ->> 'organization_id')::uuid = pg_temp.id(3, 2)
        and (select organization_id = pg_temp.id(3, 2) from public.clinics where id = (result ->> 'clinic_id')::uuid)
        and replay ->> 'outcome' = 'ALREADY_CREATED' and replay ->> 'clinic_id' = result ->> 'clinic_id'
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 3 and pg_temp.clinic_count(pg_temp.id(3, 2)) = 2
        and (select to_jsonb(c)::text from public.clinics c where c.id = c1) = c1_row,
        'The same key in another Organization creates a separate Clinic there and never returns A''s');
    insert into k_state values ('b1', (result ->> 'clinic_id')::uuid);
end $$;

do $$ declare denied text := '42501:Clinic-creation capability is required'; actor integer; begin
    foreach actor in array array[3, 4, 5, 6, 7, 8, 9, 15, 18] loop
        perform pg_temp.assert_true(pg_temp.create(actor, pg_temp.id(3, 1), pg_temp.key(1)) = denied
            and pg_temp.create(actor, pg_temp.id(3, 1), pg_temp.key(2)) = denied,
            'Lookup follows authorization: an unauthorized replay of a used key is denied without disclosure');
    end loop;
    perform pg_temp.assert_true(pg_temp.create(1, pg_temp.id(3, 2), pg_temp.key(1)) = denied
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 3 and pg_temp.clinic_count(pg_temp.id(3, 2)) = 2,
        'Lookup follows authorization: an unauthorized replay of a used key is denied without disclosure');
end $$;

-- A response lost after commit: the client never saw the id; the retry with
-- the same key recovers exactly that Clinic.
do $$ declare first_attempt text; retry jsonb; committed uuid; begin
    first_attempt := pg_temp.create(1, pg_temp.id(3, 1), pg_temp.key(3));
    select id into committed from public.clinics
    where organization_id = pg_temp.id(3, 1) and creation_idempotency_key = pg_temp.key(3);
    retry := pg_temp.create_json(1, pg_temp.id(3, 1), pg_temp.key(3));
    perform pg_temp.assert_true(first_attempt like '{%' and committed is not null
        and (retry ->> 'clinic_id')::uuid = committed and retry ->> 'outcome' = 'ALREADY_CREATED'
        and pg_temp.clinic_count(pg_temp.id(3, 1)) = 4,
        'A lost response is recovered by retrying the same key');
    insert into k_state values ('c3', committed);
end $$;

do $$ declare c1 uuid := (select id from k_state where key = 'c1'); outcomes text[]; begin
    outcomes := array[pg_temp.sqlstate_of(1, format(
        'update public.clinics set creation_idempotency_key = %L where id = %L', pg_temp.key(9), c1))];
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'update public.clinics set creation_idempotency_key = null where id = %L', c1));
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'update public.clinics set creation_idempotency_key = %L where id = %L', pg_temp.key(9), pg_temp.id(4, 1)));
    perform pg_temp.assert_true(outcomes = array['23514', '23514', '23514']
        and (select creation_idempotency_key = pg_temp.key(1) from public.clinics where id = c1)
        and (select creation_idempotency_key is null from public.clinics where id = pg_temp.id(4, 1)),
        'The creation key cannot be changed');
end $$;

-- ---------------------------------------------------------------------------
-- Reads (BR-15; SPEC-ORG-007, SPEC-ORG-008 BR-3; Notes 18, 19)
-- ---------------------------------------------------------------------------
do $$ declare c1 uuid := (select id from k_state where key = 'c1'); b1 uuid := (select id from k_state where key = 'b1');
    entry jsonb; begin
    perform pg_temp.act(1);
    select value into entry from jsonb_array_elements(public.get_my_professional_clinics() -> 'clinics') value
    where (value ->> 'clinic_id')::uuid = c1;
    perform pg_temp.assert_true(entry ->> 'clinic_display_name' is null
        and (entry ->> 'organization_id')::uuid = pg_temp.id(3, 1)
        and c1 = any(pg_temp.professional_clinic_ids(2))
        and c1 = any(pg_temp.professional_clinic_ids(4))
        and not c1 = any(pg_temp.professional_clinic_ids(3))
        and not c1 = any(pg_temp.professional_clinic_ids(6))
        and not c1 = any(pg_temp.professional_clinic_ids(7))
        and not c1 = any(pg_temp.professional_clinic_ids(9))
        and not b1 = any(pg_temp.professional_clinic_ids(1))
        and b1 = any(pg_temp.professional_clinic_ids(7)),
        'The new Clinic is immediately a Professional Clinic of its Organization only');
    perform pg_temp.assert_true(pg_temp.reports_create_capability(1, pg_temp.id(3, 1))
        and pg_temp.reports_create_capability(2, pg_temp.id(3, 1))
        and not pg_temp.reports_create_capability(3, pg_temp.id(3, 1))
        and not pg_temp.reports_create_capability(4, pg_temp.id(3, 1))
        and not pg_temp.reports_create_capability(5, pg_temp.id(3, 1))
        and not pg_temp.reports_create_capability(1, pg_temp.id(3, 2))
        and pg_temp.reports_create_capability(7, pg_temp.id(3, 2)),
        'Advisory ORGANIZATION_CREATE_CLINICS is reported only to Owners and Organization Administrators');
    perform pg_temp.act(1);
    perform pg_temp.assert_true((select public.get_managed_clinic_profile(c1)
            = jsonb_build_object('clinic_id', c1, 'is_published', false, 'scheduling_timezone_name', null,
                                 'public_profile', null, 'location', null))
        and not public.get_managed_clinic_profile(c1)::text like '%' || pg_temp.key(1)::text || '%'
        and not public.get_my_professional_clinics()::text like '%' || pg_temp.key(1)::text || '%'
        and not public.get_my_professional_context()::text like '%' || pg_temp.key(1)::text || '%',
        'Managed and professional reads show the new Clinic unconfigured and never expose the creation key');
    perform pg_temp.assert_true(not exists (select 1 from public.published_clinic_public_profiles where clinic_id = c1)
        and not exists (select 1 from public.get_published_clinic_location(c1))
        and not exists (select 1 from public.get_published_clinic_service_offerings(c1))
        and not exists (select 1 from public.get_published_clinic_opening_hours(c1))
        and exists (select 1 from public.published_clinic_public_profiles where clinic_id = pg_temp.id(4, 1)),
        'The new Clinic is absent from public Discovery');
end $$;

-- ---------------------------------------------------------------------------
-- Clinic settings compatibility (SPEC-CLI-002/003/004/007, SPEC-APT-013)
-- ---------------------------------------------------------------------------
-- Each step is its own statement: AND operands have no evaluation order.
do $$ declare c1 uuid := (select id from k_state where key = 'c1'); outcomes text[]; begin
    outcomes := array[
        pg_temp.sqlstate_of(1, format('select public.publish_clinic(%L)', c1))];
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'select public.set_clinic_public_profile(%L, ''Nueva Clínica'', null, null, null, null)', c1));
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'select public.set_clinic_location(%L, ''Calle Nueva 2, Madrid'', 40.42, -3.70)', c1));
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'select public.set_clinic_scheduling_timezone(%L, ''Europe/Madrid'')', c1));
    outcomes := outcomes || pg_temp.sqlstate_of(1, format('select public.publish_clinic(%L)', c1));
    perform pg_temp.assert_true(outcomes = array['23514', '00000', '00000', '00000', '00000']
        and (select is_published from public.clinics where id = c1)
        and exists (select 1 from public.published_clinic_public_profiles where clinic_id = c1 and display_name = 'Nueva Clínica')
        and exists (select 1 from public.get_published_clinic_location(c1)),
        'Clinic settings configure and publish the new Clinic without any Entitlement');
end $$;

do $$ declare c1 uuid := (select id from k_state where key = 'c1'); outcome text; begin
    outcome := pg_temp.sqlstate_of(1, format('select public.unpublish_clinic(%L)', c1));
    perform pg_temp.assert_true(outcome = '00000'
        and (select not is_published and scheduling_timezone_name = 'Europe/Madrid' from public.clinics where id = c1)
        and not exists (select 1 from public.published_clinic_public_profiles where clinic_id = c1)
        and (select count(*) from public.clinic_public_profiles where clinic_id = c1) = 1
        and (select count(*) from public.clinic_locations where clinic_id = c1) = 1,
        'Unpublish works on the new Clinic and keeps its configuration');
end $$;

-- Appointment configuration is a paid scheduling capability; it works on the
-- new Clinic once the Organization is entitled.
do $$ declare c1 uuid := (select id from k_state where key = 'c1'); revision bigint; outcomes text[];
    t timestamptz := statement_timestamp(); begin
    perform public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', t - interval '1 day', null,
        t + interval '30 days', 'clinic-creation-suite', pg_temp.id(21, 1), null);
    perform pg_temp.act(1);
    revision := (select managed.weekly_appointment_availability_revision
                 from public.get_managed_clinic_appointment_availability(c1) as managed);
    outcomes := array[pg_temp.sqlstate_of(1, format(
        'select public.set_clinic_standard_appointment_duration(%L, 30)', c1))];
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'select public.replace_clinic_appointment_availability(%L, %L, %s)', c1,
        '[{"iso_weekday":1,"start_time":"09:00","end_time":"13:00"}]', revision));
    outcomes := outcomes || pg_temp.sqlstate_of(1, format(
        'select public.set_clinic_appointment_availability_exception(%L, %L, ''CLOSED'', ''[]'')',
        c1, (t + interval '10 days')::date));
    perform pg_temp.assert_true(outcomes = array['00000', '00000', '00000']
        and (select standard_appointment_duration_minutes = 30 from public.clinics where id = c1)
        and (select count(*) from public.clinic_appointment_availability_periods where clinic_id = c1) = 1
        and (select count(*) from public.clinic_appointment_availability_exceptions where clinic_id = c1) = 1,
        'Appointment duration, weekly hours and exceptions work on the new Clinic once entitled');
end $$;

-- ---------------------------------------------------------------------------
-- Authenticated role and Organization serialization (BR-12, BR-14; Note 17)
-- ---------------------------------------------------------------------------
create extension pgrowlocks with schema extensions;
create function pg_temp.locked(relation regclass, row_id uuid, mode text) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return mode = any(coalesce(result, '{}'));
end $$;
create temporary table k_probe on commit drop as select pg_temp.id(3, 3) organization, pg_temp.key(4) creation_key;
grant select on k_probe to authenticated;
select pg_temp.assert_true(not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 3), 'For Update'),
    'Lock probe starts unlocked');
select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(public.create_clinic((select organization from k_probe), (select creation_key from k_probe)) ->> 'outcome' = 'CREATED',
    'Authenticated role executes create');
reset role;
select pg_temp.assert_true(pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 3), 'For Update')
    and pg_temp.clinic_count(pg_temp.id(3, 3)) = 1,
    'Creation serializes on the Organization row');

rollback;

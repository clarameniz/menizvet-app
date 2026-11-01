-- Staff Responsibility Editing + Veterinarian Enablement Phase 1:
-- SPEC-VET-001 §13/§14 (BR-17–BR-21) — self-service Professional Profile.
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The concurrent create/create race is pinned by run_staff_workforce_concurrency.py.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0331000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.create_profile(actor integer, identifier text, context text) returns text language plpgsql as $$
declare result jsonb; failure_hint text; begin
    perform pg_temp.act(actor);
    result := public.create_my_veterinarian_professional_profile(identifier, context);
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return result::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return sqlstate || ':' || coalesce(nullif(failure_hint, ''), '-') || ':' || sqlerrm;
end $$;
create function pg_temp.kind(result text) returns text language sql immutable as $$
    select case when result like '{%' then result::jsonb ->> 'outcome'
                else split_part(result, ':', 1) || ':' || split_part(result, ':', 2) end
$$;
-- A failure where success is expected becomes {"error": ...}, so assertions
-- (not casts) report it.
create function pg_temp.json(result text) returns jsonb language sql immutable as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
$$;
create function pg_temp.profile_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(p) order by p.id)::text from public.veterinarian_professional_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.veterinarian_professional_credentials c), ''))
$$;
create function pg_temp.relationship_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), '')
        || coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a), '')
        || coalesce((select jsonb_agg(to_jsonb(u) order by u.id)::text from public.users u), ''))
$$;

set local session_replication_role = replica;
-- 1 verified User without Profile; 2 verified User with a Profile; 3 unverified;
-- 4 Auth subject without a domain User; 5 verified Member holding VETERINARIAN;
-- 6 another verified User; 7 verified User used only by the lock probe.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'profile-' || n || '@example.test', case when n = 3 then null else '2020-01-01Z'::timestamptz end
from generate_series(1, 7) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 7) n where n <> 4;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 7) n where n <> 4;
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(7, 2), pg_temp.id(2, 2));
insert into public.veterinarian_professional_credentials (id, professional_profile_id, registration_identifier, issuing_context)
values (pg_temp.id(8, 2), pg_temp.id(7, 2), 'COL-0002', 'Colegio de Veterinarios de Madrid');
insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, 1), 'Profile Org');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
values (pg_temp.id(5, 5), pg_temp.id(3, 1), pg_temp.id(2, 5), '2020-01-01Z');
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
values (pg_temp.id(6, 5), pg_temp.id(5, 5), 'OWNER', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2, 5)),
       (pg_temp.id(6, 55), pg_temp.id(5, 5), 'VETERINARIAN', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2, 5));
set local session_replication_role = origin;

-- Contract and ACL (BR-17; Note 22).
select pg_temp.assert_true((select prosecdef and proconfig @> array['search_path=""'] and provolatile = 'v'
        and prorettype = 'jsonb'::regtype and proargnames = array['p_registration_identifier', 'p_issuing_context']
    from pg_proc where oid = 'public.create_my_veterinarian_professional_profile(text,text)'::regprocedure)
    and (select count(*) from pg_proc where proname = 'create_my_veterinarian_professional_profile') = 1,
    'Exact contract: SECURITY DEFINER, empty search_path, credential facts only (no User parameter)');
select pg_temp.assert_true(has_function_privilege('authenticated', 'public.create_my_veterinarian_professional_profile(text,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.create_my_veterinarian_professional_profile(text,text)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.create_my_veterinarian_professional_profile(text,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.create_veterinarian_professional_profile(text,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.create_veterinarian_professional_profile(text,text)', 'EXECUTE'),
    'Self Profile creation is executable by authenticated only; the generic writer is not a client path');

-- Authentication, verification, input (BR-19; Notes 15, 16).
do $$ declare before text := pg_temp.profile_state(); relationships text := pg_temp.relationship_state(); begin
    perform pg_temp.assert_true(pg_temp.create_profile(0, 'X', 'Y') = '28000:-:Authentication is required'
        and pg_temp.create_profile(4, 'X', 'Y') = '28000:-:No coherent domain User exists for the authenticated subject',
        'Creation requires authentication and a coherent domain User');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.create_profile(3, 'COL-3', 'Madrid')) = '42501:ACCOUNT_VERIFICATION_REQUIRED'
        and pg_temp.kind(pg_temp.create_profile(3, '', '')) = '42501:ACCOUNT_VERIFICATION_REQUIRED',
        'An unverified account is rejected before input');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.create_profile(1, '', 'Madrid')) = '22023:REGISTRATION_IDENTIFIER_REQUIRED'
        and pg_temp.kind(pg_temp.create_profile(1, E' \t ', 'Madrid')) = '22023:REGISTRATION_IDENTIFIER_REQUIRED'
        and pg_temp.kind(pg_temp.create_profile(1, null, 'Madrid')) = '22023:REGISTRATION_IDENTIFIER_REQUIRED'
        and pg_temp.kind(pg_temp.create_profile(1, 'COL-1', '   ')) = '22023:ISSUING_CONTEXT_REQUIRED'
        and pg_temp.kind(pg_temp.create_profile(1, 'COL-1', null)) = '22023:ISSUING_CONTEXT_REQUIRED',
        'Blank identifier or context is rejected');
    perform pg_temp.assert_true(pg_temp.profile_state() = before and pg_temp.relationship_state() = relationships,
        'Rejected attempts write nothing');
end $$;

-- CREATED (BR-20, BR-21; Notes 14, 20).
create temporary table p_state (key text primary key, value jsonb not null) on commit drop;
do $$ declare result jsonb; relationships text := pg_temp.relationship_state(); begin
    result := pg_temp.json(pg_temp.create_profile(1, '  COL-0001  ', E'\tColegio de Veterinarios de Madrid '));
    perform pg_temp.assert_true(result ->> 'outcome' = 'CREATED'
        and (select user_id = pg_temp.id(2, 1) from public.veterinarian_professional_profiles
             where id = (result ->> 'professional_profile_id')::uuid)
        and (select professional_profile_id = (result ->> 'professional_profile_id')::uuid
                and registration_identifier = 'COL-0001' and issuing_context = 'Colegio de Veterinarios de Madrid'
             from public.veterinarian_professional_credentials where id = (result ->> 'professional_credential_id')::uuid)
        and (select count(*) from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 1)) = 1,
        'The acting User gets exactly one Profile and one normalized Credential');
    perform pg_temp.assert_true(pg_temp.relationship_state() = relationships,
        'Creation writes no Membership, Grant, Assignment or User');
    insert into p_state values ('user_1', result);
end $$;

-- Exact replay and different requests (BR-20; Notes 17, 18).
do $$ declare first jsonb := (select value from p_state where key = 'user_1'); before text := pg_temp.profile_state(); begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.create_profile(1, 'COL-0001', 'Colegio de Veterinarios de Madrid'))
            = jsonb_build_object('outcome', 'ALREADY_EXISTS', 'professional_profile_id', first -> 'professional_profile_id',
                'professional_credential_id', first -> 'professional_credential_id')
        and pg_temp.json(pg_temp.create_profile(1, ' COL-0001 ', 'Colegio de Veterinarios de Madrid  ')) ->> 'professional_profile_id'
            = first ->> 'professional_profile_id',
        'An exact repeat, including surrounding whitespace, returns ALREADY_EXISTS with the same ids');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.create_profile(1, 'COL-9999', 'Colegio de Veterinarios de Madrid')) = '23514:PROFILE_CREDENTIAL_MISMATCH'
        and pg_temp.kind(pg_temp.create_profile(1, 'COL-0001', 'Colegio de Barcelona')) = '23514:PROFILE_CREDENTIAL_MISMATCH'
        and pg_temp.kind(pg_temp.create_profile(1, 'col-0001', 'Colegio de Veterinarios de Madrid')) = '23514:PROFILE_CREDENTIAL_MISMATCH',
        'A materially different identifier or context is a deterministic conflict');
    perform pg_temp.assert_true(pg_temp.profile_state() = before
        and (select registration_identifier = 'COL-0001' and issuing_context = 'Colegio de Veterinarios de Madrid'
             from public.veterinarian_professional_credentials where id = (first ->> 'professional_credential_id')::uuid),
        'Replays and conflicts never overwrite the stored Credential');
    perform pg_temp.assert_true(pg_temp.json(pg_temp.create_profile(2, 'COL-0002', 'Colegio de Veterinarios de Madrid'))
            = jsonb_build_object('outcome', 'ALREADY_EXISTS', 'professional_profile_id', pg_temp.id(7, 2),
                'professional_credential_id', pg_temp.id(8, 2))
        and pg_temp.kind(pg_temp.create_profile(2, 'COL-0001', 'Colegio de Veterinarios de Madrid')) = '23514:PROFILE_CREDENTIAL_MISMATCH',
        'An existing (pre-Phase-1) Profile reconciles the same way');
end $$;

-- Own Profile only; another User is unaffected (Note 19).
do $$ declare result jsonb; first jsonb := (select value from p_state where key = 'user_1');
    relationships text := pg_temp.relationship_state(); begin
    result := pg_temp.json(pg_temp.create_profile(6, 'COL-0001', 'Colegio de Veterinarios de Madrid'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'CREATED'
        and result ->> 'professional_profile_id' <> first ->> 'professional_profile_id'
        and (select user_id = pg_temp.id(2, 6) from public.veterinarian_professional_profiles where id = (result ->> 'professional_profile_id')::uuid)
        and (select count(*) from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 1)) = 1,
        'Each User creates only their own Profile; identifier text alone is not identity');
    result := pg_temp.json(pg_temp.create_profile(5, 'COL-0005', 'Colegio de Veterinarios de Toledo'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'CREATED' and pg_temp.relationship_state() = relationships,
        'A Member holding VETERINARIAN creates a Profile; Membership, Grants and Assignments are unchanged');
end $$;

-- Real authenticated role and per-User serialization.
create extension pgrowlocks with schema extensions;
create function pg_temp.locked(relation regclass, row_id uuid) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    -- The Profile foreign key alone takes For Key Share, which does not serialize.
    return 'For Update' = any(coalesce(result, '{}'));
end $$;
create function pg_temp.sqlstate_as_authenticated(statement text) returns text language plpgsql as $$ begin
    set local role authenticated;
    begin
        execute statement;
    exception when others then
        reset role;
        return sqlstate;
    end;
    reset role;
    return '00000';
end $$;
grant execute on function pg_temp.sqlstate_as_authenticated(text) to public;
-- User 1 already holds a Profile, so only the generic writer could add one.
do $$ declare before text := pg_temp.profile_state(); begin
    perform pg_temp.act(1);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(
            'select public.create_veterinarian_professional_profile(''X-1'', ''Y'')') = '42501'
        and pg_temp.profile_state() = before,
        'Authenticated clients cannot reach the generic Profile writer');
end $$;
select pg_temp.assert_true(not pg_temp.locked('public.users', pg_temp.id(2, 7)), 'Lock probe starts unlocked');
select pg_temp.act(7);
set local role authenticated;
select pg_temp.assert_true(public.create_my_veterinarian_professional_profile('COL-0007', 'Colegio de Veterinarios de Madrid')
    ->> 'outcome' = 'CREATED', 'Authenticated role executes self Profile creation');
reset role;
select pg_temp.assert_true(pg_temp.locked('public.users', pg_temp.id(2, 7)),
    'Creation serializes on the acting User');
select pg_temp.assert_true((select count(*) from public.veterinarian_professional_profiles p
        join public.veterinarian_professional_credentials c on c.professional_profile_id = p.id
        where p.user_id in (pg_temp.id(2, 1), pg_temp.id(2, 2), pg_temp.id(2, 5), pg_temp.id(2, 6), pg_temp.id(2, 7))) = 5
    and not exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 3)),
    'Exactly one Profile and Credential per creating User; none for the unverified User');

set constraints all immediate;
set constraints all deferred;
rollback;

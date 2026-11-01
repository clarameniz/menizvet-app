-- Staff Responsibility Editing + Veterinarian Enablement Phase 1:
-- SPEC-ORG-006 §14/§15 (BR-46–BR-57), SPEC-ORG-005 §11, SPEC-ORG-009 BR-1.
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- Behaviour is exercised through the real client-safe operations; multi-
-- session races are pinned by run_staff_workforce_concurrency.py.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0330000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
-- Runs one operation as actor; deferred integrity triggers fire inside.
create function pg_temp.call(actor integer, statement text) returns text language plpgsql as $$
declare result jsonb; failure_hint text; begin
    perform pg_temp.act(actor);
    execute statement into result;
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return result::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return sqlstate || ':' || coalesce(nullif(failure_hint, ''), '-') || ':' || sqlerrm;
end $$;
create function pg_temp.add(actor integer, org uuid, membership uuid, role text, scope text, clinic uuid) returns text
language sql as $$
    select pg_temp.call(actor, format('select public.add_staff_responsibility(%L, %L, %L, %L, %L)', org, membership, role, scope, clinic))
$$;
create function pg_temp.change(actor integer, org uuid, grant_id uuid, role text, scope text, clinic uuid) returns text
language sql as $$
    select pg_temp.call(actor, format('select public.replace_staff_responsibility(%L, %L, %L, %L, %L)', org, grant_id, role, scope, clinic))
$$;
create function pg_temp.finish(actor integer, org uuid, grant_id uuid) returns text language sql as $$
    select pg_temp.call(actor, format('select public.end_staff_responsibility(%L, %L)', org, grant_id))
$$;
-- 'OUTCOME' for a result, 'sqlstate:hint' for a failure.
create function pg_temp.kind(result text) returns text language sql immutable as $$
    select case when result like '{%' then result::jsonb ->> 'outcome'
                else split_part(result, ':', 1) || ':' || split_part(result, ':', 2) end
$$;
-- A failure where success is expected becomes {"error": ...}, so assertions
-- (not casts) report it.
create function pg_temp.json(result text) returns jsonb language sql immutable as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
$$;
create function pg_temp.grants_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), '')
        || coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), ''))
$$;
create function pg_temp.member_grants(membership uuid) returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
        where g.membership_id = membership), ''))
$$;
create function pg_temp.current_roles(membership uuid) returns text[] language sql as $$
    select coalesce(array_agg(g.responsibility || '@' || coalesce(g.clinic_id::text, 'ORG') order by g.responsibility, g.clinic_id), '{}')
    from public.organization_responsibility_grants g
    where g.membership_id = membership and g.effective_start <= statement_timestamp() and g.effective_end is null
$$;
-- Everything Responsibility management must never touch.
create function pg_temp.untouched_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a), '')
        || coalesce((select jsonb_agg(to_jsonb(p) order by p.id)::text from public.veterinarian_professional_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.veterinarian_professional_credentials c), '')
        || coalesce((select jsonb_agg(to_jsonb(i) order by i.id)::text from public.organization_invitations i), '')
        || coalesce((select jsonb_agg(to_jsonb(u) order by u.id)::text from public.users u), '')
        || coalesce((select jsonb_agg(to_jsonb(o) order by o.id)::text from public.veterinary_organizations o), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.clinics c), ''))
$$;

set local session_replication_role = replica;
-- Actors (Auth subject id(1,n) <-> domain User id(2,n), Membership id(5,n)):
-- Organization A id(3,1): Clinics A1 id(4,1), A2 id(4,2). Organization B id(3,2): Clinic B1 id(4,3).
-- 1 Owner; 2 Organization Administrator; 3 Clinic Administrator (A1);
-- 4 Organization Receptionist (single Grant); 5 Veterinarian (Profile, A1 Assignment);
-- 6 multi-Grant Member: RECEPTIONIST@A1, ADMINISTRATOR@A2, VETERINARIAN;
-- 7 Organization Receptionist; 8 co-Owner + Organization Receptionist;
-- 9 Administrator of B; 10 ended Member of A; 11 Receptionist of B;
-- 12 RECEPTIONIST@A1 (lost-response target); 13 ended VETERINARIAN + RECEPTIONIST;
-- 14 Auth subject without a domain User; 15 Guardian (no Membership);
-- 16 second Organization Administrator; 17 Owner of B.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'resp-' || n || '@example.test', '2020-01-01Z' from generate_series(1, 17) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 17) n where n <> 14;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 17) n where n <> 14;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Resp Org A'), (pg_temp.id(3, 2), 'Resp Org B');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 1)), (pg_temp.id(4, 3), pg_temp.id(3, 2));
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n in (9, 11, 17) then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z',
    case when n = 10 then '2021-01-01Z'::timestamptz end, case when n = 10 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 17]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, case when n > 100 then n / 10 else n end),
    case when n in (1, 8, 17) then 'OWNER' when n in (2, 3, 9, 16, 61) then 'ADMINISTRATOR'
         when n in (5, 62, 13) then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (3, 6, 61, 12) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (3, 6, 12) then pg_temp.id(4, 1) when n = 61 then pg_temp.id(4, 2) end,
    '2020-01-01Z', case when n in (10, 13) then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n in (10, 13) then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 17]) n;
-- Second Grants: 61/62 on Member 6, 81 on co-Owner 8, 131 on Member 13.
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id) values
    (pg_temp.id(6, 61), pg_temp.id(5, 6), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 2), '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 62), pg_temp.id(5, 6), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 81), pg_temp.id(5, 8), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 131), pg_temp.id(5, 13), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1));
insert into public.veterinarian_professional_profiles (id, user_id) values
    (pg_temp.id(7, 5), pg_temp.id(2, 5)), (pg_temp.id(7, 13), pg_temp.id(2, 13));
insert into public.veterinarian_professional_credentials (professional_profile_id, registration_identifier, issuing_context) values
    (pg_temp.id(7, 5), 'RESP-5', 'Colegio Madrid'), (pg_temp.id(7, 13), 'RESP-13', 'Colegio Madrid');
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start) values
    (pg_temp.id(8, 5), pg_temp.id(7, 5), pg_temp.id(5, 5), pg_temp.id(4, 1), '2020-01-01Z'),
    (pg_temp.id(8, 13), pg_temp.id(7, 13), pg_temp.id(5, 13), pg_temp.id(4, 1), '2020-01-01Z');
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Contract and ACL (BR-47; Note 43)
-- ---------------------------------------------------------------------------
do $$ declare signature text; begin
    foreach signature in array array['public.add_staff_responsibility(uuid,uuid,text,text,uuid)',
            'public.replace_staff_responsibility(uuid,uuid,text,text,uuid)', 'public.end_staff_responsibility(uuid,uuid)'] loop
        perform pg_temp.assert_true((select prosecdef and proconfig @> array['search_path=""'] and provolatile = 'v'
                and prorettype = 'jsonb'::regtype from pg_proc where oid = signature::regprocedure)
            and has_function_privilege('authenticated', signature, 'EXECUTE')
            and not has_function_privilege('anon', signature, 'EXECUTE')
            and not has_function_privilege('service_role', signature, 'EXECUTE'),
            'Client-safe Responsibility operation contract and ACL: ' || signature);
    end loop;
    perform pg_temp.assert_true((select count(*) from pg_proc where proname in ('add_staff_responsibility',
            'replace_staff_responsibility', 'end_staff_responsibility')) = 3,
        'Exactly one signature per client-safe Responsibility operation');
    foreach signature in array array['public.add_organization_responsibility(uuid,text)',
            'public.add_organization_responsibility(uuid,text,text,uuid)', 'public.replace_organization_responsibility(uuid,text)',
            'public.replace_organization_responsibility(uuid,text,text,uuid)', 'public.end_organization_responsibility(uuid)',
            'public.assign_veterinarian_to_clinic(uuid,uuid,uuid)', 'public.end_veterinarian_clinic_assignment(uuid)',
            'public.create_veterinarian_professional_profile(text,text)'] loop
        perform pg_temp.assert_true(not has_function_privilege('authenticated', signature, 'EXECUTE')
            and not has_function_privilege('anon', signature, 'EXECUTE')
            and not has_function_privilege('public', signature, 'EXECUTE')
            and has_function_privilege('service_role', signature, 'EXECUTE'),
            'Generic operation withdrawn from clients, kept for trusted compatibility: ' || signature);
    end loop;
    foreach signature in array array['public.staff_membership_holds_owner(uuid)',
            'public.membership_supports_current_veterinarian_assignment(uuid)',
            'public.staff_responsibility_scope_is_supported(text,text,uuid)',
            'public.user_manages_veterinarian_assignments_at(uuid,uuid,uuid)'] loop
        perform pg_temp.assert_true(not has_function_privilege('authenticated', signature, 'EXECUTE')
            and not has_function_privilege('anon', signature, 'EXECUTE')
            and not has_function_privilege('service_role', signature, 'EXECUTE'),
            'Private predicate executable by no role: ' || signature);
    end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Fail-closed authorization before input, target, or lifecycle (BR-48,
-- BR-55; Note 40)
-- ---------------------------------------------------------------------------
do $$ declare denied text := '42501:-:Organization Responsibilities unavailable'; actor integer; target uuid; grant_id uuid;
    before text := pg_temp.grants_state(); untouched text := pg_temp.untouched_state(); begin
    perform pg_temp.assert_true(pg_temp.add(0, pg_temp.id(3, 1), pg_temp.id(5, 7), 'OWNER', 'X', null) = '28000:-:Authentication is required'
        and pg_temp.finish(14, pg_temp.id(3, 1), pg_temp.id(6, 7)) = '28000:-:No coherent domain User exists for the authenticated subject',
        'Responsibility operations require authentication and a coherent domain User');
    -- Clinic Administrator, Receptionists, Veterinarians, ended Member,
    -- another Organization's Administrator/Member and a Guardian.
    foreach actor in array array[3, 4, 5, 6, 7, 9, 10, 11, 13, 15] loop
        foreach target in array array[pg_temp.id(5, 7), pg_temp.id(5, 1), pg_temp.id(5, 10), pg_temp.id(5, 999), pg_temp.id(5, 11)] loop
            perform pg_temp.assert_true(pg_temp.add(actor, pg_temp.id(3, 1), target, 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
                and pg_temp.add(actor, pg_temp.id(3, 1), target, 'OWNER', 'CLINIC', pg_temp.id(4, 3)) = denied,
                'Add without the capability fails uniformly, before input: ' || actor);
        end loop;
        foreach grant_id in array array[pg_temp.id(6, 7), pg_temp.id(6, 1), pg_temp.id(6, 10), pg_temp.id(6, 999), pg_temp.id(6, 11)] loop
            perform pg_temp.assert_true(pg_temp.change(actor, pg_temp.id(3, 1), grant_id, 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
                and pg_temp.change(actor, pg_temp.id(3, 1), grant_id, 'VETERINARIAN', 'CLINIC', pg_temp.id(4, 1)) = denied
                and pg_temp.finish(actor, pg_temp.id(3, 1), grant_id) = denied,
                'Change/End without the capability fail uniformly, before input or lifecycle: ' || actor);
        end loop;
    end loop;
    -- Authorized in A, but naming B, an unknown Organization, NULL, or a
    -- target of B through A.
    perform pg_temp.assert_true(pg_temp.add(2, pg_temp.id(3, 2), pg_temp.id(5, 11), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.add(2, pg_temp.id(3, 99), pg_temp.id(5, 7), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.add(2, null, pg_temp.id(5, 7), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.finish(1, pg_temp.id(3, 2), pg_temp.id(6, 11)) = denied
        and pg_temp.change(9, pg_temp.id(3, 1), pg_temp.id(6, 7), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied,
        'Another, unknown, or NULL Organization fails identically');
    perform pg_temp.assert_true(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 11), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 999), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.add(2, pg_temp.id(3, 1), null, 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 11), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 999), 'ADMINISTRATOR', 'ORGANIZATION', null) = denied
        and pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 11)) = denied
        and pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 999)) = denied
        and pg_temp.finish(2, pg_temp.id(3, 1), null) = denied,
        'Unknown and other-Organization targets fail exactly as an inaccessible Organization');
    perform pg_temp.assert_true(pg_temp.grants_state() = before and pg_temp.untouched_state() = untouched,
        'Denied attempts write nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Input (BR-49, BR-55 step 3; Note 35)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.grants_state(); begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'OWNER', 'ORGANIZATION', null)) = '22023:INVALID_SCOPE'
        and pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'VETERINARIAN', 'CLINIC', pg_temp.id(4, 1))) = '22023:INVALID_SCOPE'
        and pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', null)) = '22023:INVALID_SCOPE'
        and pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'RECEPTIONIST', 'ORGANIZATION', pg_temp.id(4, 1))) = '22023:INVALID_SCOPE'
        and pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', null, null)) = '22023:INVALID_SCOPE'
        and pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), null, 'ORGANIZATION', null)) = '22023:INVALID_SCOPE',
        'OWNER, Clinic-scoped VETERINARIAN and malformed scopes are rejected on Add');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 7), 'OWNER', 'ORGANIZATION', null)) = '22023:INVALID_SCOPE'
        and pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 7), 'VETERINARIAN', 'CLINIC', pg_temp.id(4, 1))) = '22023:INVALID_SCOPE',
        'OWNER and Clinic-scoped VETERINARIAN are rejected on Change');
    perform pg_temp.assert_true(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 3))
            = pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 999))
        and pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 3))) = '22023:INVALID_CLINIC'
        and pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 7), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 3))) = '22023:INVALID_CLINIC',
        'Another Organization''s Clinic and an unknown Clinic are one invalid-Clinic outcome');
    perform pg_temp.assert_true(pg_temp.grants_state() = before, 'Invalid input writes nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Add (BR-46, BR-49, BR-56, BR-57; Notes 33, 41)
-- ---------------------------------------------------------------------------
do $$ declare t timestamptz := statement_timestamp(); result jsonb; untouched text := pg_temp.untouched_state();
    others text := md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
        where g.membership_id <> pg_temp.id(5, 7)), '')); begin
    result := pg_temp.json(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ADDED' and (result ->> 'membership_id')::uuid = pg_temp.id(5, 7)
        and (result ->> 'effective_start')::timestamptz = t
        and (select membership_id = pg_temp.id(5, 7) and responsibility = 'ADMINISTRATOR' and scope_type = 'CLINIC'
                and clinic_id = pg_temp.id(4, 1) and effective_start = t and effective_end is null and granted_by_user_id = pg_temp.id(2, 2)
             from public.organization_responsibility_grants where id = (result ->> 'responsibility_grant_id')::uuid),
        'Add creates one current Grant at the statement instant, granted by the actor');
    perform pg_temp.assert_true(pg_temp.current_roles(pg_temp.id(5, 7)) = array['ADMINISTRATOR@' || pg_temp.id(4, 1), 'RECEPTIONIST@ORG'],
        'The existing Grant stays alongside the new one');
    perform pg_temp.assert_true(md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
        where g.membership_id <> pg_temp.id(5, 7)), '')) = others and pg_temp.untouched_state() = untouched,
        'Add changes no other Membership''s Grants, Profile, Assignment or Invitation');
end $$;
do $$ declare first jsonb := pg_temp.json(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)));
    before text := pg_temp.grants_state(); retry jsonb; begin
    retry := pg_temp.json(pg_temp.add(16, pg_temp.id(3, 1), pg_temp.id(5, 7), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)));
    perform pg_temp.assert_true(first ->> 'outcome' = 'ALREADY_PRESENT' and retry ->> 'outcome' = 'ALREADY_PRESENT'
        and retry ->> 'responsibility_grant_id' = first ->> 'responsibility_grant_id'
        and pg_temp.grants_state() = before,
        'Repeated Add reconciles to the existing Grant and writes nothing');
end $$;
do $$ declare result jsonb; untouched text := pg_temp.untouched_state(); begin
    result := pg_temp.json(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 7), 'VETERINARIAN', 'ORGANIZATION', null));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ADDED'
        and pg_temp.current_roles(pg_temp.id(5, 7)) = array['ADMINISTRATOR@' || pg_temp.id(4, 1), 'RECEPTIONIST@ORG', 'VETERINARIAN@ORG']
        and pg_temp.untouched_state() = untouched
        and not exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 7)),
        'Adding VETERINARIAN to an existing Member creates no Profile or Clinic Assignment');
end $$;

-- ---------------------------------------------------------------------------
-- Change exactly one Grant of a multi-Grant Member (BR-46, BR-57; Note 34)
-- ---------------------------------------------------------------------------
create temporary table r_state (key text primary key, id uuid not null) on commit drop;
do $$ declare t timestamptz := statement_timestamp(); result jsonb;
    kept text := md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
        where g.id in (pg_temp.id(6, 61), pg_temp.id(6, 62))), '')); begin
    result := pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 6), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'REPLACED' and (result ->> 'replaced_responsibility_grant_id')::uuid = pg_temp.id(6, 6)
        and (result ->> 'effective_instant')::timestamptz = t
        and (select effective_end = t and ended_by_user_id = pg_temp.id(2, 2) and effective_start = '2020-01-01Z'
                and responsibility = 'RECEPTIONIST' and clinic_id = pg_temp.id(4, 1)
             from public.organization_responsibility_grants where id = pg_temp.id(6, 6))
        and (select effective_start = t and effective_end is null and clinic_id = pg_temp.id(4, 2) and granted_by_user_id = pg_temp.id(2, 2)
             from public.organization_responsibility_grants where id = (result ->> 'responsibility_grant_id')::uuid),
        'Clinic A to Clinic B: the old Grant ends and the replacement starts at one instant; history is not rewritten');
    perform pg_temp.assert_true(md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
            where g.id in (pg_temp.id(6, 61), pg_temp.id(6, 62))), '')) = kept,
        'Unrelated Grants of the Member are untouched by Change');
    insert into r_state values ('m6_recep', (result ->> 'responsibility_grant_id')::uuid);
end $$;
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), (select id from r_state where key = 'm6_recep'), 'RECEPTIONIST', 'ORGANIZATION', null));
    perform pg_temp.assert_true(result ->> 'outcome' = 'REPLACED'
        and pg_temp.current_roles(pg_temp.id(5, 6)) = array['ADMINISTRATOR@' || pg_temp.id(4, 2), 'RECEPTIONIST@ORG', 'VETERINARIAN@ORG'],
        'Clinic to Organization scope');
    update r_state set id = (result ->> 'responsibility_grant_id')::uuid where key = 'm6_recep';
end $$;
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), (select id from r_state where key = 'm6_recep'), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'REPLACED'
        and pg_temp.current_roles(pg_temp.id(5, 6)) = array['ADMINISTRATOR@' || pg_temp.id(4, 1), 'ADMINISTRATOR@' || pg_temp.id(4, 2), 'VETERINARIAN@ORG'],
        'Role change with Organization to Clinic scope');
    update r_state set id = (result ->> 'responsibility_grant_id')::uuid where key = 'm6_recep';
end $$;
do $$ declare before text := pg_temp.grants_state(); begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), (select id from r_state where key = 'm6_recep'),
            'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 2))) = '23514:DUPLICATE'
        and pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 61), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 2))) = '23514:NO_OP'
        and pg_temp.grants_state() = before,
        'Change into an equivalent active Grant and a no-op Change are rejected without false history');
    perform pg_temp.assert_true((select count(*) from public.organization_responsibility_grants where membership_id = pg_temp.id(5, 6)) = 6
        and (select count(*) from public.organization_responsibility_grants where membership_id = pg_temp.id(5, 6) and effective_end is null) = 3
        and (select count(*) from public.organization_memberships where user_id = pg_temp.id(2, 6)) = 1,
        'Three Changes kept one Membership and created exactly three historical periods');
end $$;

-- Lost response: replay, then a stale request (BR-56; Note 41).
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.change(16, pg_temp.id(3, 1), pg_temp.id(6, 12), 'RECEPTIONIST', 'ORGANIZATION', null));
    perform pg_temp.assert_true(result ->> 'outcome' = 'REPLACED', 'Lost-response fixture: first Change');
    insert into r_state values ('m12_first', (result ->> 'responsibility_grant_id')::uuid);
end $$;
do $$ declare before text := pg_temp.grants_state(); retry jsonb;
    original timestamptz := (select effective_end from public.organization_responsibility_grants where id = pg_temp.id(6, 12)); begin
    retry := pg_temp.json(pg_temp.change(16, pg_temp.id(3, 1), pg_temp.id(6, 12), 'RECEPTIONIST', 'ORGANIZATION', null));
    perform pg_temp.assert_true(retry ->> 'outcome' = 'ALREADY_CHANGED'
        and (retry ->> 'responsibility_grant_id')::uuid = (select id from r_state where key = 'm12_first')
        and (retry ->> 'replaced_responsibility_grant_id')::uuid = pg_temp.id(6, 12)
        and (retry ->> 'effective_instant')::timestamptz = original
        and pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 12), 'RECEPTIONIST', 'ORGANIZATION', null)) ->> 'outcome' = 'ALREADY_CHANGED'
        and pg_temp.grants_state() = before,
        'Replaying a completed Change returns ALREADY_CHANGED with the same replacement and writes nothing');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.change(16, pg_temp.id(3, 1), pg_temp.id(6, 12), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:GRANT_ENDED'
        and pg_temp.grants_state() = before,
        'A different Change of an ended Grant is stale and writes nothing');
end $$;

-- ---------------------------------------------------------------------------
-- End one Grant; others remain (BR-46; Notes 33, 41)
-- ---------------------------------------------------------------------------
do $$ declare t timestamptz := statement_timestamp(); result jsonb;
    kept text := md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
        where g.membership_id = pg_temp.id(5, 6) and g.id <> pg_temp.id(6, 61)), '')); begin
    result := pg_temp.json(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 61)));
    perform pg_temp.assert_true(result = jsonb_build_object('outcome', 'ENDED', 'membership_id', pg_temp.id(5, 6),
            'responsibility_grant_id', pg_temp.id(6, 61), 'effective_end', t)
        and (select effective_end = t and ended_by_user_id = pg_temp.id(2, 2) from public.organization_responsibility_grants where id = pg_temp.id(6, 61))
        and md5(coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g
            where g.membership_id = pg_temp.id(5, 6) and g.id <> pg_temp.id(6, 61)), '')) = kept
        and (select effective_end is null from public.organization_memberships where id = pg_temp.id(5, 6)),
        'End ends exactly the named Grant at the statement instant; the Membership and other Grants stay');
end $$;
do $$ declare before text := pg_temp.grants_state(); first_end timestamptz :=
    (select effective_end from public.organization_responsibility_grants where id = pg_temp.id(6, 61)); begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.finish(16, pg_temp.id(3, 1), pg_temp.id(6, 61))) = jsonb_build_object('outcome', 'ALREADY_ENDED',
            'membership_id', pg_temp.id(5, 6), 'responsibility_grant_id', pg_temp.id(6, 61), 'effective_end', first_end)
        and pg_temp.grants_state() = before,
        'Repeated End returns ALREADY_ENDED with the original end and writes nothing');
end $$;

-- ---------------------------------------------------------------------------
-- OWNER Grants and Owner Memberships (BR-50, BR-51; Notes 35, 36)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.grants_state(); begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 1), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:OWNER_GRANT'
        and pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 1))) = '23514:OWNER_GRANT'
        and pg_temp.kind(pg_temp.change(1, pg_temp.id(3, 1), pg_temp.id(6, 1), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:OWNER_GRANT'
        and pg_temp.kind(pg_temp.finish(1, pg_temp.id(3, 1), pg_temp.id(6, 1))) = '23514:OWNER_GRANT'
        and pg_temp.kind(pg_temp.finish(8, pg_temp.id(3, 1), pg_temp.id(6, 1))) = '23514:OWNER_GRANT',
        'An OWNER Grant is never changed or ended, including by the Owner');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 1), 'VETERINARIAN', 'ORGANIZATION', null)) = '23514:OWNER_MEMBERSHIP'
        and pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 81), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:OWNER_MEMBERSHIP'
        and pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 81))) = '23514:OWNER_MEMBERSHIP'
        and pg_temp.kind(pg_temp.add(1, pg_temp.id(3, 1), pg_temp.id(5, 8), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:OWNER_MEMBERSHIP'
        and pg_temp.kind(pg_temp.finish(1, pg_temp.id(3, 1), pg_temp.id(6, 81))) = '23514:OWNER_MEMBERSHIP',
        'An Administrator, and another Owner, cannot Add, Change or End on an Owner Membership');
    perform pg_temp.assert_true(pg_temp.grants_state() = before, 'Protected Owner targets write nothing');
end $$;
-- The Owner manages their own non-OWNER Grants (BR-52).
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.add(1, pg_temp.id(3, 1), pg_temp.id(5, 1), 'VETERINARIAN', 'ORGANIZATION', null));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ADDED'
        and pg_temp.current_roles(pg_temp.id(5, 1)) = array['OWNER@ORG', 'VETERINARIAN@ORG'],
        'The Owner adds VETERINARIAN to their own Membership');
    insert into r_state values ('owner_vet', (result ->> 'responsibility_grant_id')::uuid);
end $$;
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.change(1, pg_temp.id(3, 1), (select id from r_state where key = 'owner_vet'), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'REPLACED'
        and pg_temp.current_roles(pg_temp.id(5, 1)) = array['ADMINISTRATOR@' || pg_temp.id(4, 1), 'OWNER@ORG'],
        'The Owner changes their own non-OWNER Grant');
    insert into r_state values ('owner_admin', (result ->> 'responsibility_grant_id')::uuid);
end $$;
do $$ declare outcome text; begin
    outcome := pg_temp.json(pg_temp.finish(1, pg_temp.id(3, 1), (select id from r_state where key = 'owner_admin'))) ->> 'outcome';
    perform pg_temp.assert_true(outcome = 'ENDED' and pg_temp.current_roles(pg_temp.id(5, 1)) = array['OWNER@ORG'],
        'The Owner ends their own non-OWNER Grant; OWNER remains');
    perform pg_temp.assert_true((select count(*) from public.organization_memberships m join public.organization_responsibility_grants g
            on g.membership_id = m.id where m.organization_id = pg_temp.id(3, 1) and m.effective_end is null
            and g.effective_end is null and g.responsibility = 'OWNER') = 2,
        'Ownership is never changed by Responsibility management');
end $$;

-- ---------------------------------------------------------------------------
-- Self-targeted changes by a non-Owner (BR-52; Note 37)
-- ---------------------------------------------------------------------------
do $$ declare result jsonb; before text; begin
    result := pg_temp.json(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 2), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 1)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ADDED', 'An Administrator may Add a Responsibility to themselves');
    before := pg_temp.grants_state();
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 2), 'RECEPTIONIST', 'ORGANIZATION', null)) = '23514:SELF_MEMBERSHIP'
        and pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 2))) = '23514:SELF_MEMBERSHIP'
        and pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), (result ->> 'responsibility_grant_id')::uuid)) = '23514:SELF_MEMBERSHIP'
        and pg_temp.grants_state() = before
        and public.user_has_organization_capability(pg_temp.id(2, 2), pg_temp.id(3, 1), 'ORGANIZATION_GRANT_RESPONSIBILITIES'),
        'An Administrator cannot Change or End their own Grants (no self-demotion or lockout)');
    perform pg_temp.assert_true(pg_temp.json(pg_temp.finish(16, pg_temp.id(3, 1), (result ->> 'responsibility_grant_id')::uuid)) ->> 'outcome' = 'ENDED',
        'Another Administrator may end that Grant');
end $$;

-- ---------------------------------------------------------------------------
-- Last Responsibility (BR-53; Note 38)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.grants_state(); begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 4))) = '23514:LAST_RESPONSIBILITY'
        and pg_temp.grants_state() = before
        and (select effective_end is null from public.organization_memberships where id = pg_temp.id(5, 4)),
        'Ending the last current Grant is rejected; the Membership stays');
end $$;
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 4), 'ADMINISTRATOR', 'ORGANIZATION', null));
    perform pg_temp.assert_true(result ->> 'outcome' = 'REPLACED'
        and pg_temp.current_roles(pg_temp.id(5, 4)) = array['ADMINISTRATOR@ORG']
        and (select count(*) from public.organization_memberships where user_id = pg_temp.id(2, 4)) = 1,
        'Changing the last Grant is allowed and keeps the one Membership');
end $$;

-- ---------------------------------------------------------------------------
-- VETERINARIAN with current Clinic Assignments (BR-54; Note 39)
-- ---------------------------------------------------------------------------
do $$ declare untouched text; before text; begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 5), 'RECEPTIONIST', 'ORGANIZATION', null)) ->> 'outcome' = 'ADDED',
        'Fixture: the Veterinarian also holds RECEPTIONIST, so VETERINARIAN is not the last Grant');
    untouched := pg_temp.untouched_state();
    before := pg_temp.grants_state();
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 5))) = '23514:VETERINARIAN_ASSIGNMENTS_ACTIVE'
        and pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 5), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:VETERINARIAN_ASSIGNMENTS_ACTIVE'
        and pg_temp.grants_state() = before and pg_temp.untouched_state() = untouched
        and public.veterinarian_clinic_assignment_is_current(pg_temp.id(8, 5)),
        'VETERINARIAN cannot be ended or changed away while a current Clinic Assignment exists; nothing is ended automatically');
end $$;
do $$ begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.end_staff_veterinarian_clinic_assignment(%L, %L, %L)',
            pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 5)))) ->> 'outcome' = 'ENDED',
        'Fixture: the administrator ends the Clinic Assignment first');
end $$;
do $$ declare result jsonb; begin
    result := pg_temp.json(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 5)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ENDED' and pg_temp.current_roles(pg_temp.id(5, 5)) = array['RECEPTIONIST@ORG']
        and exists (select 1 from public.veterinarian_professional_profiles where id = pg_temp.id(7, 5))
        and (select effective_end is not null from public.veterinarian_clinic_assignments where id = pg_temp.id(8, 5)),
        'After every Clinic Assignment ended, VETERINARIAN ends; the Profile and Assignment history remain');
end $$;
-- A VETERINARIAN Grant with no Assignment changes away normally.
do $$ begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 62), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2))) ->> 'outcome' = 'REPLACED',
        'VETERINARIAN without Clinic Assignments may be changed to another role');
end $$;

-- ---------------------------------------------------------------------------
-- Lifecycle of the target Membership (BR-55 step 6)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.grants_state(); begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.add(2, pg_temp.id(3, 1), pg_temp.id(5, 10), 'RECEPTIONIST', 'ORGANIZATION', null)) = '23514:MEMBERSHIP_INACTIVE'
        and pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 10))) = '23514:MEMBERSHIP_INACTIVE'
        and pg_temp.kind(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 10), 'ADMINISTRATOR', 'ORGANIZATION', null)) = '23514:MEMBERSHIP_INACTIVE'
        and pg_temp.grants_state() = before,
        'An ended Membership receives no Responsibility change (rejoining needs a new Membership)');
end $$;

-- ---------------------------------------------------------------------------
-- Authority ends at once; previously valid changes stay (BR-26, BR-39)
-- ---------------------------------------------------------------------------
do $$ begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.finish(2, pg_temp.id(3, 1), pg_temp.id(6, 16))) = '23514:LAST_RESPONSIBILITY',
        'Second Administrator holds a single Grant');
end $$;
do $$ declare outcome text; denied text; begin
    -- Separate statements: evaluation order inside one expression is not fixed.
    outcome := pg_temp.json(pg_temp.change(2, pg_temp.id(3, 1), pg_temp.id(6, 16), 'RECEPTIONIST', 'ORGANIZATION', null)) ->> 'outcome';
    denied := pg_temp.add(16, pg_temp.id(3, 1), pg_temp.id(5, 7), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2));
    perform pg_temp.assert_true(outcome = 'REPLACED'
        and not public.user_has_organization_capability(pg_temp.id(2, 16), pg_temp.id(3, 1), 'ORGANIZATION_GRANT_RESPONSIBILITIES')
        and denied = '42501:-:Organization Responsibilities unavailable',
        'A demoted Administrator loses Responsibility management in the same statement');
end $$;

-- ---------------------------------------------------------------------------
-- Real authenticated role (mobile path), no path around the operations, and
-- serialization on the Organization.
-- ---------------------------------------------------------------------------
create extension pgrowlocks with schema extensions;
create function pg_temp.locked(relation regclass, row_id uuid) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return cardinality(coalesce(result, '{}')) > 0;
end $$;
-- Organization B has not been written in this transaction, so its locks are fresh evidence.
create temporary table r_probe on commit drop as select pg_temp.id(3, 2) org, pg_temp.id(5, 11) membership;
grant select on r_probe to authenticated;
select pg_temp.assert_true(not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 2))
    and not pg_temp.locked('public.organization_memberships', pg_temp.id(5, 11)), 'Lock probe starts unlocked');
select pg_temp.act(9);
set local role authenticated;
select pg_temp.assert_true((public.add_staff_responsibility((select org from r_probe), (select membership from r_probe),
    'ADMINISTRATOR', 'ORGANIZATION', null)) ->> 'outcome' = 'ADDED', 'Authenticated role executes the client-safe Add');
reset role;
select pg_temp.assert_true(pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 2))
    and pg_temp.locked('public.organization_memberships', pg_temp.id(5, 11)),
    'Responsibility management serializes on the Organization and the target Membership');
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
do $$ declare before text := pg_temp.grants_state(); begin
    perform pg_temp.act(2);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.add_organization_responsibility(%L, ''RECEPTIONIST'')', pg_temp.id(5, 13))) = '42501'
        and pg_temp.sqlstate_as_authenticated(format('select public.add_organization_responsibility(%L, ''RECEPTIONIST'', ''CLINIC'', %L)', pg_temp.id(5, 13), pg_temp.id(4, 2))) = '42501'
        and pg_temp.sqlstate_as_authenticated(format('select public.replace_organization_responsibility(%L, ''ADMINISTRATOR'')', pg_temp.id(6, 7))) = '42501'
        and pg_temp.sqlstate_as_authenticated(format('select public.replace_organization_responsibility(%L, ''ADMINISTRATOR'', ''ORGANIZATION'', null)', pg_temp.id(6, 7))) = '42501'
        and pg_temp.sqlstate_as_authenticated(format('select public.end_organization_responsibility(%L)', pg_temp.id(6, 7))) = '42501',
        'Authenticated clients cannot reach any generic Responsibility operation');
    perform pg_temp.assert_true(pg_temp.grants_state() = before, 'The bypass attempts changed nothing');
end $$;

-- No active Grant under an ended Membership; Organization B untouched.
select pg_temp.assert_true(not exists (select 1 from public.organization_memberships m join public.organization_responsibility_grants g
        on g.membership_id = m.id where m.effective_end is not null and g.effective_end is null)
    and (select count(*) = 2 and bool_and(effective_end is null and effective_start = '2020-01-01Z')
        from public.organization_responsibility_grants where id in (pg_temp.id(6, 9), pg_temp.id(6, 11))),
    'Coherent history; the other Organization is untouched');

set constraints all immediate;
set constraints all deferred;
rollback;

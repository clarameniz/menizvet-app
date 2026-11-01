-- Staff Responsibility Editing + Veterinarian Enablement Phase 1:
-- SPEC-VET-006 (workforce read), SPEC-VET-004 §13/§14 and SPEC-VET-005
-- §13/§14 (client-safe Clinic Assignment establish/end).
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- Multi-session races are pinned by run_staff_workforce_concurrency.py.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0332000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
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
create function pg_temp.workforce(actor integer, org uuid) returns text language sql as $$
    select pg_temp.call(actor, format('select public.get_organization_veterinarian_workforce(%L)', org))
$$;
create function pg_temp.assign(actor integer, org uuid, membership uuid, clinic uuid) returns text language sql as $$
    select pg_temp.call(actor, format('select public.assign_staff_veterinarian_to_clinic(%L, %L, %L)', org, membership, clinic))
$$;
create function pg_temp.unassign(actor integer, org uuid, clinic uuid, assignment uuid) returns text language sql as $$
    select pg_temp.call(actor, format('select public.end_staff_veterinarian_clinic_assignment(%L, %L, %L)', org, clinic, assignment))
$$;
create function pg_temp.kind(result text) returns text language sql immutable as $$
    select case when result like '{%' then result::jsonb ->> 'outcome'
                else split_part(result, ':', 1) || ':' || split_part(result, ':', 2) end
$$;
-- A failure where success is expected becomes {"error": ...}, so assertions
-- (not casts) report it.
create function pg_temp.json(result text) returns jsonb language sql immutable as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
$$;
create function pg_temp.keys(raw jsonb) returns text[] language sql as $$
    select array_agg(key order by key) from jsonb_object_keys(raw) key
$$;
create function pg_temp.member(payload jsonb, n integer) returns jsonb language sql as $$
    select value from jsonb_array_elements(payload -> 'members') where value ->> 'membership_id' = pg_temp.id(5, n)::text
$$;
create function pg_temp.assignment_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a), ''))
$$;
-- Everything Assignment management must never touch.
create function pg_temp.untouched_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), '')
        || coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), '')
        || coalesce((select jsonb_agg(to_jsonb(p) order by p.id)::text from public.veterinarian_professional_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.veterinarian_professional_credentials c), '')
        || coalesce((select jsonb_agg(to_jsonb(v) order by v.id)::text from public.appointment_veterinarian_assignments v), '')
        || coalesce((select jsonb_agg(to_jsonb(v) order by to_jsonb(v)::text)::text from public.veterinarian_availability_periods v), '')
        || coalesce((select jsonb_agg(to_jsonb(v) order by to_jsonb(v)::text)::text from public.veterinarian_availability_exceptions v), '')
        || coalesce((select jsonb_agg(to_jsonb(e) order by e.id)::text from public.clinical_record_entries e), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.clinics c), ''))
$$;
create function pg_temp.fingerprint() returns text language sql as $$
    select pg_temp.assignment_state() || pg_temp.untouched_state()
$$;

set local session_replication_role = replica;
-- Organization A id(3,1): Clinics A1 id(4,1) 'Workforce Centro', A2 id(4,2)
-- 'Workforce Getafe', A3 id(4,4) (no display name). Organization B id(3,2):
-- Clinics B1 id(4,3), B2 id(4,5).
-- 1 Owner; 2 Organization Administrator; 3 Clinic Administrator (A1);
-- 4 Organization Receptionist; 5 VETERINARIAN without Profile;
-- 6 VETERINARIAN + Profile, current A1 Assignment, ended A2 Assignment;
-- 7 RECEPTIONIST + Profile (no VETERINARIAN); 8 ended VETERINARIAN + current
-- RECEPTIONIST + Profile + still-open A1 Assignment (stale); 9 RECEPTIONIST,
-- no Profile; 10 ended Member with Profile and an open A1 Assignment;
-- 11 Administrator of B; 12 VETERINARIAN of B, Profile, B1 Assignment;
-- 13 Owner of B; 14 VETERINARIAN + Profile, no Assignment; 16 Guardian;
-- 17 Auth subject without a domain User.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'workforce-' || n || '@example.test', '2020-01-01Z' from generate_series(1, 17) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 16) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 16) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Workforce Org A'), (pg_temp.id(3, 2), 'Workforce Org B');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 1)), (pg_temp.id(4, 4), pg_temp.id(3, 1)),
    (pg_temp.id(4, 3), pg_temp.id(3, 2)), (pg_temp.id(4, 5), pg_temp.id(3, 2));
insert into public.clinic_public_profiles (clinic_id, display_name) values
    (pg_temp.id(4, 1), 'Workforce Centro'), (pg_temp.id(4, 2), 'Workforce Getafe'), (pg_temp.id(4, 3), 'Workforce Toledo');
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n in (11, 12, 13) then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z',
    case when n = 10 then '2021-01-01Z'::timestamptz end, case when n = 10 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, case when n > 100 then n / 10 else n end),
    case when n in (1, 13) then 'OWNER' when n in (2, 3, 11) then 'ADMINISTRATOR'
         when n in (5, 6, 8, 10, 12, 14) then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n = 3 then 'CLINIC' else 'ORGANIZATION' end,
    case when n = 3 then pg_temp.id(4, 1) end,
    '2020-01-01Z', case when n in (8, 10) then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n in (8, 10) then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 81, 9, 10, 11, 12, 13, 14]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id(7, n), pg_temp.id(2, n) from unnest(array[6, 7, 8, 10, 12, 14]) n;
insert into public.veterinarian_professional_credentials (professional_profile_id, registration_identifier, issuing_context)
select pg_temp.id(7, n), 'SECRET-REG-' || n, 'SECRET-CONTEXT-' || n from unnest(array[6, 7, 8, 10, 12, 14]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start, effective_end) values
    (pg_temp.id(8, 6), pg_temp.id(7, 6), pg_temp.id(5, 6), pg_temp.id(4, 1), '2020-01-01Z', null),
    (pg_temp.id(8, 62), pg_temp.id(7, 6), pg_temp.id(5, 6), pg_temp.id(4, 2), '2020-01-01Z', '2021-01-01Z'),
    (pg_temp.id(8, 8), pg_temp.id(7, 8), pg_temp.id(5, 8), pg_temp.id(4, 1), '2020-01-01Z', null),
    (pg_temp.id(8, 10), pg_temp.id(7, 10), pg_temp.id(5, 10), pg_temp.id(4, 1), '2020-01-01Z', null),
    (pg_temp.id(8, 12), pg_temp.id(7, 12), pg_temp.id(5, 12), pg_temp.id(4, 3), '2020-01-01Z', null);
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Contract and ACL (SPEC-VET-006 BR-1/BR-7; SPEC-VET-004 BR-22; SPEC-VET-005 BR-25)
-- ---------------------------------------------------------------------------
select pg_temp.assert_true((select prosecdef and proconfig @> array['search_path=""'] and provolatile = 's'
        and prorettype = 'jsonb'::regtype and proargnames = array['p_organization_id']
    from pg_proc where oid = 'public.get_organization_veterinarian_workforce(uuid)'::regprocedure)
    and (select prosecdef and proconfig @> array['search_path=""'] and provolatile = 'v' and prorettype = 'jsonb'::regtype
        and proargnames = array['p_organization_id', 'p_membership_id', 'p_clinic_id']
        from pg_proc where oid = 'public.assign_staff_veterinarian_to_clinic(uuid,uuid,uuid)'::regprocedure)
    and (select prosecdef and proconfig @> array['search_path=""'] and provolatile = 'v' and prorettype = 'jsonb'::regtype
        and proargnames = array['p_organization_id', 'p_clinic_id', 'p_veterinarian_clinic_assignment_id']
        from pg_proc where oid = 'public.end_staff_veterinarian_clinic_assignment(uuid,uuid,uuid)'::regprocedure)
    and (select count(*) from pg_proc where proname in ('get_organization_veterinarian_workforce',
        'assign_staff_veterinarian_to_clinic', 'end_staff_veterinarian_clinic_assignment')) = 3,
    'Exact contracts: STABLE read, Membership-keyed Assign with no Profile parameter, Organization/Clinic-keyed End');
do $$ declare signature text; begin
    foreach signature in array array['public.get_organization_veterinarian_workforce(uuid)',
            'public.assign_staff_veterinarian_to_clinic(uuid,uuid,uuid)', 'public.end_staff_veterinarian_clinic_assignment(uuid,uuid,uuid)'] loop
        perform pg_temp.assert_true(has_function_privilege('authenticated', signature, 'EXECUTE')
            and not has_function_privilege('anon', signature, 'EXECUTE')
            and not has_function_privilege('service_role', signature, 'EXECUTE'),
            'Executable by authenticated only: ' || signature);
    end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Workforce read: authorization (SPEC-VET-006 BR-2; Notes 1, 2)
-- ---------------------------------------------------------------------------
do $$ declare denied text := '42501:-:Organization Veterinarian workforce unavailable'; actor integer; begin
    perform pg_temp.assert_true(pg_temp.workforce(0, pg_temp.id(3, 1)) = '28000:-:Authentication is required'
        and pg_temp.workforce(17, pg_temp.id(3, 1)) = '28000:-:No coherent domain User exists for the authenticated subject',
        'Workforce read requires authentication and a coherent domain User');
    foreach actor in array array[3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16] loop
        perform pg_temp.assert_true(pg_temp.workforce(actor, pg_temp.id(3, 1)) = denied,
            'Workforce read denied: ' || actor);
    end loop;
    perform pg_temp.assert_true(pg_temp.workforce(1, pg_temp.id(3, 2)) = denied and pg_temp.workforce(1, pg_temp.id(3, 99)) = denied
        and pg_temp.workforce(1, null) = denied,
        'Another, unknown or NULL Organization fails identically');
end $$;

-- ---------------------------------------------------------------------------
-- Workforce read: content (SPEC-VET-006 BR-1, BR-3–BR-6; Notes 3–9)
-- ---------------------------------------------------------------------------
do $$ declare a jsonb; b jsonb; m jsonb; entry jsonb; before text := pg_temp.fingerprint(); begin
    a := pg_temp.json(pg_temp.workforce(1, pg_temp.id(3, 1)));
    perform pg_temp.assert_true(pg_temp.json(pg_temp.workforce(2, pg_temp.id(3, 1))) = a, 'Owner and Organization Administrator read the same workforce');
    perform pg_temp.assert_true(pg_temp.keys(a) = array['members', 'organization_id'] and a ->> 'organization_id' = pg_temp.id(3, 1)::text,
        'Exact envelope');
    perform pg_temp.assert_true((select array_agg((value ->> 'membership_id')::uuid order by ord)
            from jsonb_array_elements(a -> 'members') with ordinality rows(value, ord))
        = array[pg_temp.id(5, 5), pg_temp.id(5, 6), pg_temp.id(5, 8), pg_temp.id(5, 14)],
        'Exactly current Members with VETERINARIAN or a current Assignment, ordered; others and ended Members absent');
    for m in select value from jsonb_array_elements(a -> 'members') loop
        perform pg_temp.assert_true(pg_temp.keys(m) = array['clinic_assignments', 'has_veterinarian_professional_profile', 'membership_id'],
            'Exact Member fields: no User, Auth, Profile or credential data');
        for entry in select value from jsonb_array_elements(m -> 'clinic_assignments') loop
            perform pg_temp.assert_true(pg_temp.keys(entry) = array['clinic', 'veterinarian_clinic_assignment_id']
                and pg_temp.keys(entry -> 'clinic') = array['clinic_display_name', 'clinic_id'], 'Exact Assignment fields');
        end loop;
    end loop;
    perform pg_temp.assert_true(pg_temp.member(a, 5) = jsonb_build_object('membership_id', pg_temp.id(5, 5),
            'has_veterinarian_professional_profile', false, 'clinic_assignments', '[]'::jsonb),
        'VETERINARIAN without Profile: Profile pending, no Assignment');
    perform pg_temp.assert_true(pg_temp.member(a, 6) -> 'clinic_assignments' = jsonb_build_array(jsonb_build_object(
            'veterinarian_clinic_assignment_id', pg_temp.id(8, 6),
            'clinic', jsonb_build_object('clinic_id', pg_temp.id(4, 1), 'clinic_display_name', 'Workforce Centro')))
        and (pg_temp.member(a, 6) ->> 'has_veterinarian_professional_profile')::boolean,
        'Profile present; only the current Assignment is listed, the ended one is not');
    perform pg_temp.assert_true(pg_temp.member(a, 8) -> 'clinic_assignments' -> 0 ->> 'veterinarian_clinic_assignment_id' = pg_temp.id(8, 8)::text,
        'A stale Assignment of a Member whose VETERINARIAN Grant ended stays visible for cleanup');
    perform pg_temp.assert_true(pg_temp.member(a, 14) = jsonb_build_object('membership_id', pg_temp.id(5, 14),
            'has_veterinarian_professional_profile', true, 'clinic_assignments', '[]'::jsonb),
        'VETERINARIAN with Profile and no Assignment');
    perform pg_temp.assert_true(a::text not like '%SECRET-%' and a::text not like '%' || pg_temp.id(7, 6)::text || '%'
        and a::text not like '%' || pg_temp.id(2, 6)::text || '%' and a::text not like '%' || pg_temp.id(1, 6)::text || '%'
        and a::text not like '%@example.test%' and a::text not like '%' || pg_temp.id(4, 3)::text || '%',
        'No credential, Profile id, User id, Auth id, email, or other-Organization Clinic');
    b := pg_temp.json(pg_temp.workforce(11, pg_temp.id(3, 2)));
    perform pg_temp.assert_true(jsonb_array_length(b -> 'members') = 1 and pg_temp.member(b, 12) -> 'clinic_assignments' -> 0 -> 'clinic'
            = jsonb_build_object('clinic_id', pg_temp.id(4, 3), 'clinic_display_name', 'Workforce Toledo')
        and b::text not like '%' || pg_temp.id(3, 1)::text || '%',
        'Organization B''s read contains only B');
    perform pg_temp.assert_true(pg_temp.fingerprint() = before, 'Workforce read writes nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Assign: fail-closed authorization (SPEC-VET-004 BR-24; Note 27)
-- ---------------------------------------------------------------------------
do $$ declare denied text := '42501:-:Veterinarian Clinic Assignment unavailable'; actor integer; before text := pg_temp.fingerprint(); begin
    perform pg_temp.assert_true(pg_temp.assign(0, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 1)) = '28000:-:Authentication is required'
        and pg_temp.unassign(17, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 6)) = '28000:-:No coherent domain User exists for the authenticated subject',
        'Assignment operations require authentication and a coherent domain User');
    foreach actor in array array[4, 5, 6, 7, 9, 11, 12, 14, 16] loop
        perform pg_temp.assert_true(pg_temp.assign(actor, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 1)) = denied
            and pg_temp.assign(actor, pg_temp.id(3, 1), pg_temp.id(5, 5), pg_temp.id(4, 1)) = denied
            and pg_temp.assign(actor, pg_temp.id(3, 1), pg_temp.id(5, 999), pg_temp.id(4, 1)) = denied
            and pg_temp.unassign(actor, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 6)) = denied
            and pg_temp.unassign(actor, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 62)) = denied
            and pg_temp.unassign(actor, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 999)) = denied,
            'Without CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS every target fails uniformly, before prerequisites or lifecycle: ' || actor);
    end loop;
    perform pg_temp.assert_true(pg_temp.assign(3, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 2)) = denied
        and pg_temp.unassign(3, pg_temp.id(3, 1), pg_temp.id(4, 2), pg_temp.id(8, 62)) = denied,
        'A Clinic-scoped Administrator is denied at another Clinic');
    perform pg_temp.assert_true(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 3)) = denied
        and pg_temp.assign(2, pg_temp.id(3, 2), pg_temp.id(5, 14), pg_temp.id(4, 1)) = denied
        and pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 999)) = denied
        and pg_temp.assign(2, pg_temp.id(3, 99), pg_temp.id(5, 14), pg_temp.id(4, 1)) = denied
        and pg_temp.assign(2, null, pg_temp.id(5, 14), pg_temp.id(4, 1)) = denied
        and pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 14), null) = denied,
        'A Clinic of another Organization, an unknown Clinic or Organization, and NULL fail identically');
    perform pg_temp.assert_true(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 12), pg_temp.id(4, 1)) = denied
        and pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 999), pg_temp.id(4, 1)) = denied
        and pg_temp.assign(2, pg_temp.id(3, 1), null, pg_temp.id(4, 1)) = denied,
        'Another Organization''s Membership and an unknown Membership fail exactly as an inaccessible Clinic');
    perform pg_temp.assert_true(pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 2), pg_temp.id(8, 6)) = denied
        and pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 12)) = denied
        and pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 3), pg_temp.id(8, 12)) = denied
        and pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 999)) = denied
        and pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 1), null) = denied,
        'End: an Assignment of another Clinic or Organization and an unknown Assignment fail uniformly');
    perform pg_temp.assert_true(pg_temp.fingerprint() = before, 'Denied attempts write nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Assign: prerequisites (SPEC-VET-004 BR-23/BR-24; Note 26)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.fingerprint(); begin
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 5), pg_temp.id(4, 1))) = '23514:PROFILE_REQUIRED'
        and pg_temp.kind(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 7), pg_temp.id(4, 1))) = '23514:VETERINARIAN_RESPONSIBILITY_REQUIRED'
        and pg_temp.kind(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 8), pg_temp.id(4, 2))) = '23514:VETERINARIAN_RESPONSIBILITY_REQUIRED'
        and pg_temp.kind(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 9), pg_temp.id(4, 1))) = '23514:VETERINARIAN_RESPONSIBILITY_REQUIRED'
        and pg_temp.kind(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 10), pg_temp.id(4, 2))) = '23514:MEMBERSHIP_INACTIVE',
        'Missing Profile, missing or ended VETERINARIAN, and an ended Membership are rejected');
    perform pg_temp.assert_true(pg_temp.fingerprint() = before, 'Rejected Assignments write nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Assign, repeat, several Clinics (SPEC-VET-004 BR-22, BR-25; Notes 24, 25, 29)
-- ---------------------------------------------------------------------------
create temporary table w_state (key text primary key, id uuid not null) on commit drop;
do $$ declare t timestamptz := statement_timestamp(); result jsonb; untouched text := pg_temp.untouched_state(); begin
    result := pg_temp.json(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 2)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ASSIGNED' and (result ->> 'effective_start')::timestamptz = t
        and (result ->> 'membership_id')::uuid = pg_temp.id(5, 14) and (result ->> 'clinic_id')::uuid = pg_temp.id(4, 2)
        and (select professional_profile_id = pg_temp.id(7, 14) and supporting_membership_id = pg_temp.id(5, 14)
                and clinic_id = pg_temp.id(4, 2) and effective_start = t and effective_end is null
             from public.veterinarian_clinic_assignments where id = (result ->> 'veterinarian_clinic_assignment_id')::uuid),
        'Assign establishes one Assignment at the statement instant with the server-derived Profile');
    perform pg_temp.assert_true(pg_temp.untouched_state() = untouched,
        'Assign changes no Membership, Grant, Profile, Appointment assignment, Availability or clinical record');
    insert into w_state values ('m14_a2', (result ->> 'veterinarian_clinic_assignment_id')::uuid);
end $$;
do $$ declare before text := pg_temp.fingerprint(); retry jsonb; begin
    retry := pg_temp.json(pg_temp.assign(1, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 2)));
    perform pg_temp.assert_true(retry ->> 'outcome' = 'ALREADY_ASSIGNED'
        and (retry ->> 'veterinarian_clinic_assignment_id')::uuid = (select id from w_state where key = 'm14_a2')
        and pg_temp.fingerprint() = before,
        'A repeat returns ALREADY_ASSIGNED with the same Assignment and writes nothing');
end $$;
do $$ declare result jsonb; unnamed jsonb; begin
    -- A Clinic-scoped Administrator keeps the domain capability for its Clinic.
    result := pg_temp.json(pg_temp.assign(3, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 1)));
    unnamed := pg_temp.json(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 4)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ASSIGNED' and unnamed ->> 'outcome' = 'ASSIGNED',
        'Several simultaneous Assignments; a Clinic-scoped Administrator assigns at its own Clinic');
    insert into w_state values ('m14_a1', (result ->> 'veterinarian_clinic_assignment_id')::uuid),
        ('m14_a3', (unnamed ->> 'veterinarian_clinic_assignment_id')::uuid);
end $$;
do $$ declare a jsonb := pg_temp.json(pg_temp.workforce(2, pg_temp.id(3, 1))); begin
    perform pg_temp.assert_true(pg_temp.member(a, 14) -> 'clinic_assignments' = (select jsonb_agg(entry order by entry -> 'clinic' ->> 'clinic_id') from (values
            (jsonb_build_object('veterinarian_clinic_assignment_id', (select id from w_state where key = 'm14_a1'),
                'clinic', jsonb_build_object('clinic_id', pg_temp.id(4, 1), 'clinic_display_name', 'Workforce Centro'))),
            (jsonb_build_object('veterinarian_clinic_assignment_id', (select id from w_state where key = 'm14_a2'),
                'clinic', jsonb_build_object('clinic_id', pg_temp.id(4, 2), 'clinic_display_name', 'Workforce Getafe'))),
            (jsonb_build_object('veterinarian_clinic_assignment_id', (select id from w_state where key = 'm14_a3'),
                'clinic', jsonb_build_object('clinic_id', pg_temp.id(4, 4), 'clinic_display_name', null)))) as rows(entry)),
        'The workforce read lists every current Assignment, ordered, with an unnamed Clinic still identified');
end $$;

-- ---------------------------------------------------------------------------
-- End, repeat, cleanup of stale states, re-assign (SPEC-VET-005 BR-26–BR-28;
-- Notes 24–26)
-- ---------------------------------------------------------------------------
do $$ declare t timestamptz := statement_timestamp(); result jsonb; untouched text := pg_temp.untouched_state();
    others text := md5(coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a
        where a.id <> (select id from w_state where key = 'm14_a1')), '')); begin
    result := pg_temp.json(pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 1), (select id from w_state where key = 'm14_a1')));
    perform pg_temp.assert_true(result = jsonb_build_object('outcome', 'ENDED',
            'veterinarian_clinic_assignment_id', (select id from w_state where key = 'm14_a1'), 'effective_end', t)
        and (select effective_end = t from public.veterinarian_clinic_assignments where id = (select id from w_state where key = 'm14_a1')),
        'End records the statement instant');
    perform pg_temp.assert_true(md5(coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a
            where a.id <> (select id from w_state where key = 'm14_a1')), '')) = others
        and pg_temp.untouched_state() = untouched,
        'Ending one Assignment leaves the others, the Grants, the Profile and history unchanged');
end $$;
do $$ declare before text := pg_temp.fingerprint();
    original timestamptz := (select effective_end from public.veterinarian_clinic_assignments where id = (select id from w_state where key = 'm14_a1')); begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.unassign(1, pg_temp.id(3, 1), pg_temp.id(4, 1), (select id from w_state where key = 'm14_a1')))
            = jsonb_build_object('outcome', 'ALREADY_ENDED', 'veterinarian_clinic_assignment_id', (select id from w_state where key = 'm14_a1'),
                'effective_end', original)
        and pg_temp.json(pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 2), pg_temp.id(8, 62))) ->> 'effective_end' = '2021-01-01T00:00:00+00:00'
        and pg_temp.fingerprint() = before,
        'A repeat or a historical Assignment returns ALREADY_ENDED with the original end and writes nothing');
end $$;
do $$ declare stale jsonb; departed jsonb; begin
    stale := pg_temp.json(pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 8)));
    departed := pg_temp.json(pg_temp.unassign(2, pg_temp.id(3, 1), pg_temp.id(4, 1), pg_temp.id(8, 10)));
    perform pg_temp.assert_true(stale ->> 'outcome' = 'ENDED' and departed ->> 'outcome' = 'ENDED'
        and (select effective_end is not null from public.organization_responsibility_grants where id = pg_temp.id(6, 8))
        and (select effective_end is null from public.organization_responsibility_grants where id = pg_temp.id(6, 81)),
        'Cleanup: an Assignment without a current VETERINARIAN Grant, or of an ended Membership, can still be ended');
    perform pg_temp.assert_true(pg_temp.member(pg_temp.json(pg_temp.workforce(2, pg_temp.id(3, 1))), 8) is null,
        'After cleanup the stale Member leaves the workforce read');
end $$;
do $$ declare result jsonb; first uuid := (select id from w_state where key = 'm14_a1'); begin
    result := pg_temp.json(pg_temp.assign(2, pg_temp.id(3, 1), pg_temp.id(5, 14), pg_temp.id(4, 1)));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ASSIGNED' and (result ->> 'veterinarian_clinic_assignment_id')::uuid <> first
        and (select effective_end is not null from public.veterinarian_clinic_assignments where id = first)
        and (select count(*) from public.veterinarian_clinic_assignments where supporting_membership_id = pg_temp.id(5, 14)
             and clinic_id = pg_temp.id(4, 1)) = 2,
        'Returning to a Clinic creates a new Assignment period; the ended one is never reactivated');
end $$;

-- ---------------------------------------------------------------------------
-- Real authenticated role, no path around the operations, serialization
-- ---------------------------------------------------------------------------
create extension pgrowlocks with schema extensions;
create function pg_temp.locked(relation regclass, row_id uuid) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return cardinality(coalesce(result, '{}')) > 0;
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
-- Organization B has only been read so far: its locks are fresh evidence.
select pg_temp.assert_true(not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 2))
    and not pg_temp.locked('public.clinics', pg_temp.id(4, 5)), 'Read took no lock; probes start unlocked');
create temporary table w_probe on commit drop as select pg_temp.id(3, 2) org, pg_temp.id(5, 12) membership, pg_temp.id(4, 5) clinic;
grant select on w_probe to authenticated;
select pg_temp.act(11);
set local role authenticated;
select pg_temp.assert_true(public.assign_staff_veterinarian_to_clinic((select org from w_probe), (select membership from w_probe),
    (select clinic from w_probe)) ->> 'outcome' = 'ASSIGNED', 'Authenticated role executes the client-safe Assign');
reset role;
select pg_temp.assert_true(pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 2))
    and pg_temp.locked('public.clinics', pg_temp.id(4, 5)) and pg_temp.locked('public.organization_memberships', pg_temp.id(5, 12)),
    'Assign serializes on the Organization, the Clinic and the Membership');
do $$ declare before text := pg_temp.fingerprint(); begin
    perform pg_temp.act(2);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.assign_veterinarian_to_clinic(%L, %L, %L)',
            pg_temp.id(7, 7), pg_temp.id(5, 7), pg_temp.id(4, 2))) = '42501'
        and pg_temp.sqlstate_as_authenticated(format('select public.end_veterinarian_clinic_assignment(%L)', pg_temp.id(8, 6))) = '42501',
        'Authenticated clients cannot reach the generic Assignment operations (no client-supplied Profile)');
    perform pg_temp.assert_true(pg_temp.fingerprint() = before, 'The bypass attempts changed nothing');
end $$;

select pg_temp.assert_true(not exists (select 1 from public.veterinarian_clinic_assignments a
        join public.organization_memberships m on m.id = a.supporting_membership_id
        join public.clinics c on c.id = a.clinic_id
        where c.organization_id <> m.organization_id or a.effective_end < a.effective_start),
    'Every Assignment stays within its Membership''s Organization with a coherent period');

set constraints all immediate;
set constraints all deferred;
rollback;

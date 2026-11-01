-- SPEC-ORG-009 §12 (BR-12–BR-16) / §13 Verification Notes 25–33.
-- Isolated LOCAL superuser only. Fixtures and assertions are rollback-only.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0120000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.members_outcome(organization uuid, after_start timestamptz default null,
    after_id uuid default null, page_size integer default 25) returns text language plpgsql as $$ begin
    perform * from public.get_organization_staff_members(organization, after_start, after_id, page_size);
    return 'SUCCEEDED';
exception when others then return sqlstate || ': ' || sqlerrm; end $$;
create function pg_temp.invitations_outcome(organization uuid, after_created timestamptz default null,
    after_id uuid default null, page_size integer default 20) returns text language plpgsql as $$ begin
    perform * from public.get_organization_pending_invitations(organization, after_created, after_id, page_size);
    return 'SUCCEEDED';
exception when others then return sqlstate || ': ' || sqlerrm; end $$;
-- Every page of the Members read, concatenated, for one page size.
create function pg_temp.members_paged(organization uuid, page_size integer) returns jsonb
language plpgsql as $$
declare result jsonb := '[]'; after_start timestamptz; after_id uuid; r record; n integer; ids uuid[] := '{}';
begin
    loop
        n := 0;
        for r in select * from public.get_organization_staff_members(organization, after_start, after_id, page_size) loop
            if r.membership_id = any(ids) then raise exception 'Member returned twice: %', r.membership_id; end if;
            ids := ids || r.membership_id;
            result := result || jsonb_build_array(to_jsonb(r));
            after_start := r.effective_start; after_id := r.membership_id; n := n + 1;
        end loop;
        exit when n < page_size;
    end loop;
    return result;
end $$;
create function pg_temp.invitations_paged(organization uuid, page_size integer) returns jsonb
language plpgsql as $$
declare result jsonb := '[]'; after_created timestamptz; after_id uuid; r record; n integer; ids uuid[] := '{}';
begin
    loop
        n := 0;
        for r in select * from public.get_organization_pending_invitations(organization, after_created, after_id, page_size) loop
            if r.invitation_id = any(ids) then raise exception 'Invitation returned twice: %', r.invitation_id; end if;
            ids := ids || r.invitation_id;
            result := result || jsonb_build_array(to_jsonb(r));
            after_created := r.created_at; after_id := r.invitation_id; n := n + 1;
        end loop;
        exit when n < page_size;
    end loop;
    return result;
end $$;
create function pg_temp.fingerprint() returns text language plpgsql as $$
declare table_name text; rows_json text; result text := ''; begin
    for table_name in select tablename from pg_tables where schemaname = 'public' order by tablename loop
        execute format('select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text, '''') from public.%I r', table_name)
        into rows_json;
        result := result || table_name || rows_json;
    end loop;
    return md5(result);
end $$;

-- Users 1–40 (40 has no domain User: unlinked subject).
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'auth-private-' || n || '@example.test', '2020-01-01Z' from generate_series(1, 40) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 39) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 39) n;
-- 9 and 15 share a name across pages; 7 (ended) and 12 share one, which only
-- the ended member makes "shared"; 8 (Org B) and 11 share one across
-- Organizations; 16 differs from 11 only by a trailing space.
insert into public.user_profiles (user_id, display_name) values
    (pg_temp.id(2, 1), 'Owner One'), (pg_temp.id(2, 7), 'Solo Name'), (pg_temp.id(2, 8), 'Luis'),
    (pg_temp.id(2, 9), 'Ana García'), (pg_temp.id(2, 11), 'Luis'), (pg_temp.id(2, 12), 'Solo Name'),
    (pg_temp.id(2, 15), 'Ana García'), (pg_temp.id(2, 16), 'Luis ');
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Paged Org A'), (pg_temp.id(3, 2), 'Paged Org B'), (pg_temp.id(3, 3), 'Volume Org');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 2));
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.id(4, 1), 'A Centro');

-- Invitations of A: 1–8 pending (1–4 share one created_at), 9 accepted by
-- member 9, 10 revoked, 11 expired, 12 rejected; 13 pending in B.
insert into public.organization_invitations (
    id, organization_id, inviting_user_id, recipient_email, created_at, expires_at,
    acceptance_secret_digest, revoked_at, revoked_by_user_id, rejected_at, rejected_by_user_id
)
select pg_temp.id(7, n), pg_temp.id(3, case when n = 13 then 2 else 1 end), pg_temp.id(2, 1),
    'Invite-' || n || '@Example.Test',
    case when n <= 4 then statement_timestamp() - interval '3 days'
         else statement_timestamp() - interval '2 days' + (n || ' minutes')::interval end,
    case when n = 11 then statement_timestamp() - interval '1 hour' else statement_timestamp() + interval '5 days' end,
    case when n = 9 then null else decode(repeat('ab', 32), 'hex') end,
    case when n = 10 then statement_timestamp() - interval '1 day' end,
    case when n = 10 then pg_temp.id(2, 1) end,
    case when n = 12 then statement_timestamp() - interval '1 day' end,
    case when n = 12 then pg_temp.id(2, 5) end
from generate_series(1, 13) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id)
select pg_temp.id(8, n), pg_temp.id(7, n),
    case when n % 3 = 0 then 'ADMINISTRATOR' when n % 3 = 1 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n in (3, 6) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (3, 6) then pg_temp.id(4, 1) end
from generate_series(1, 13) n;

-- Members of A: 1 Owner, 2 Org Administrator, 3 Clinic Administrator,
-- 4 Org Receptionist, 5 Veterinarian, 6 bare, 7 ended, 9–20 staff (9–14
-- share one effective_start), 21 future. 8 is B's Owner.
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end,
    ended_by_user_id, originating_invitation_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 8 then 2 else 1 end), pg_temp.id(2, n),
    case when n between 9 and 14 then '2021-06-01Z'::timestamptz
         when n = 21 then statement_timestamp() + interval '1 day'
         else ('2020-01-01Z'::timestamptz + (n || ' days')::interval) end,
    case when n = 7 then '2021-01-01Z'::timestamptz end,
    case when n = 7 then pg_temp.id(2, 1) end,
    case when n = 9 then pg_temp.id(7, 9) end
from generate_series(1, 21) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case when n in (1, 7, 8) then 'OWNER' when n in (2, 3, 12) then 'ADMINISTRATOR'
         when n in (5, 15) then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (3, 13) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (3, 13) then pg_temp.id(4, 1) end,
    '2020-01-01Z', case when n = 7 then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n = 7 then pg_temp.id(2, 1) end
from unnest(array[1,2,3,4,5,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21]) n;
-- Member 15 also holds an Organization Receptionist Grant (several Grants).
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type,
    effective_start, granted_by_user_id) values
    (pg_temp.id(6, 100), pg_temp.id(5, 15), 'RECEPTIONIST', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2, 1));
set local session_replication_role = origin;

-- VN 25: authorization equals get_organization_staff, for both reads.
do $$ declare n integer; denied text := '42501: Organization Staff unavailable'; begin
    foreach n in array array[1, 2] loop
        perform pg_temp.act(n);
        perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1)) = 'SUCCEEDED', 'Members: actor ' || n);
        perform pg_temp.assert_true(pg_temp.invitations_outcome(pg_temp.id(3, 1)) = 'SUCCEEDED', 'Invitations: actor ' || n);
    end loop;
    foreach n in array array[3, 4, 5, 6, 7, 8, 9, 21, 39] loop
        perform pg_temp.act(n);
        perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1)) = denied, 'Members denied ' || n);
        perform pg_temp.assert_true(pg_temp.invitations_outcome(pg_temp.id(3, 1)) = denied, 'Invitations denied ' || n);
    end loop;
    perform pg_temp.act(1);
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 99)) = denied
        and pg_temp.members_outcome(null) = denied
        and pg_temp.invitations_outcome(pg_temp.id(3, 99)) = denied
        and pg_temp.invitations_outcome(null) = denied, 'Unknown and null Organization parity');
    perform pg_temp.act(2);
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 2)) = denied
        and pg_temp.invitations_outcome(pg_temp.id(3, 2)) = denied, 'Another Organization is denied');
    perform pg_temp.act(40);
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1))
        = '28000: No coherent domain User exists for the authenticated subject', 'Unlinked subject');
    perform pg_temp.act(0);
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1)) = '28000: Authentication is required'
        and pg_temp.invitations_outcome(pg_temp.id(3, 99)) = '28000: Authentication is required',
        'Anonymous fails with 28000 first');
end $$;

-- VN 26: validation only after authorization.
do $$ declare invalid text := '22023: Staff page is invalid'; begin
    perform pg_temp.act(4);
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1), null, null, 0)
        = '42501: Organization Staff unavailable', 'Denied before validation');
    perform pg_temp.act(1);
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1), null, null, 0) = invalid
        and pg_temp.members_outcome(pg_temp.id(3, 1), null, null, 51) = invalid
        and pg_temp.members_outcome(pg_temp.id(3, 1), null, null, null) = invalid
        and pg_temp.members_outcome(pg_temp.id(3, 1), '2020-01-01Z', null) = invalid
        and pg_temp.members_outcome(pg_temp.id(3, 1), null, pg_temp.id(5, 1)) = invalid, 'Members validation');
    perform pg_temp.assert_true(pg_temp.invitations_outcome(pg_temp.id(3, 1), null, null, 0) = invalid
        and pg_temp.invitations_outcome(pg_temp.id(3, 1), null, null, 51) = invalid
        and pg_temp.invitations_outcome(pg_temp.id(3, 1), now(), null) = invalid
        and pg_temp.invitations_outcome(pg_temp.id(3, 1), null, pg_temp.id(7, 1)) = invalid, 'Invitations validation');
    perform pg_temp.assert_true(pg_temp.members_outcome(pg_temp.id(3, 1), null, null, 50) = 'SUCCEEDED'
        and pg_temp.invitations_outcome(pg_temp.id(3, 1), null, null, 1) = 'SUCCEEDED', 'Range bounds accepted');
end $$;

-- VN 27–30: every page size reproduces get_organization_staff exactly, plus BR-14.
do $$
declare
    full_staff jsonb;
    expected_members jsonb;
    expected_invitations jsonb;
    page_size integer;
    paged jsonb;
begin
    perform pg_temp.act(2);
    full_staff := public.get_organization_staff(pg_temp.id(3, 1));
    select jsonb_agg(member.value || jsonb_build_object('display_name_is_shared',
               member.value->>'display_name' is not null and (
                   select count(*) from jsonb_array_elements(full_staff->'members') as other
                   where other.value->>'display_name' = member.value->>'display_name') > 1)
           order by member.ordinality)
    into expected_members
    from jsonb_array_elements(full_staff->'members') with ordinality as member(value, ordinality);
    expected_invitations := full_staff->'pending_invitations';

    perform pg_temp.assert_true(jsonb_array_length(expected_members) = 18, 'Fixture: 18 current members of A');
    perform pg_temp.assert_true(jsonb_array_length(expected_invitations) = 8, 'Fixture: 8 pending Invitations of A');
    for page_size in 1 .. 19 loop
        paged := pg_temp.members_paged(pg_temp.id(3, 1), page_size);
        perform pg_temp.assert_true(paged = expected_members, 'Members equal the full read at page size ' || page_size);
    end loop;
    for page_size in 1 .. 9 loop
        paged := pg_temp.invitations_paged(pg_temp.id(3, 1), page_size);
        perform pg_temp.assert_true(paged = expected_invitations, 'Invitations equal the full read at page size ' || page_size);
    end loop;

    -- BR-14 by name: shared across pages; never through an ended member,
    -- another Organization, or a different spelling; never for no name.
    paged := pg_temp.members_paged(pg_temp.id(3, 1), 1);
    perform pg_temp.assert_true((
        select bool_and((m->>'display_name_is_shared')::boolean = (m->>'membership_id')::uuid in (pg_temp.id(5, 9), pg_temp.id(5, 15)))
        from jsonb_array_elements(paged) m), 'Only the two current "Ana García" are shared');
    perform pg_temp.assert_true((
        select count(*) from jsonb_array_elements(paged) m
        where m->>'display_name' is null and (m->>'display_name_is_shared')::boolean) = 0, 'No name is never shared');
    -- Member 9 joined through Invitation 9: its address is administrative context.
    perform pg_temp.assert_true((
        select m->>'invitation_recipient_email' from jsonb_array_elements(paged) m
        where (m->>'membership_id')::uuid = pg_temp.id(5, 9)) = 'invite-9@example.test', 'Invitation address');
    perform pg_temp.assert_true((
        select jsonb_array_length(m->'responsibilities') from jsonb_array_elements(paged) m
        where (m->>'membership_id')::uuid = pg_temp.id(5, 15)) = 2, 'Several Grants on one row');
end $$;

-- VN 29: ties are broken by id, and the cursor at the last row returns nothing.
do $$
declare tied uuid[]; last_member record; last_invitation record;
begin
    perform pg_temp.act(1);
    select array_agg(membership_id order by ordinality) into tied
    from public.get_organization_staff_members(pg_temp.id(3, 1), '2021-06-01Z', pg_temp.id(5, 9), 4) with ordinality;
    perform pg_temp.assert_true(tied = array[pg_temp.id(5, 10), pg_temp.id(5, 11), pg_temp.id(5, 12), pg_temp.id(5, 13)],
        'A cursor inside a tie continues by id');
    select * into last_member from public.get_organization_staff_members(pg_temp.id(3, 1), null, null, 50)
    order by effective_start desc, membership_id desc limit 1;
    perform pg_temp.assert_true(not exists (select 1 from public.get_organization_staff_members(
        pg_temp.id(3, 1), last_member.effective_start, last_member.membership_id, 50)), 'Members: past the end is empty');
    perform pg_temp.assert_true((select array_agg(invitation_id order by ordinality)
        from public.get_organization_pending_invitations(pg_temp.id(3, 1), null, null, 4) with ordinality)
        = array[pg_temp.id(7, 1), pg_temp.id(7, 2), pg_temp.id(7, 3), pg_temp.id(7, 4)], 'Invitation tie ordered by id');
    select * into last_invitation from public.get_organization_pending_invitations(pg_temp.id(3, 1), null, null, 50)
    order by created_at desc, invitation_id desc limit 1;
    perform pg_temp.assert_true(not exists (select 1 from public.get_organization_pending_invitations(
        pg_temp.id(3, 1), last_invitation.created_at, last_invitation.invitation_id, 50)), 'Invitations: past the end is empty');
end $$;

-- VN 32: nothing of another Organization, no forbidden column, no count.
do $$ begin
    perform pg_temp.act(1);
    perform pg_temp.assert_true(not exists (
        select 1 from public.get_organization_staff_members(pg_temp.id(3, 1), null, null, 50)
        where membership_id in (select id from public.organization_memberships where organization_id <> pg_temp.id(3, 1))),
        'Members of A only');
    perform pg_temp.assert_true(not exists (
        select 1 from public.get_organization_pending_invitations(pg_temp.id(3, 1), null, null, 50)
        where invitation_id = pg_temp.id(7, 13)), 'Invitations of A only');
    perform pg_temp.assert_true((
        select array_agg(parameter_name::text order by ordinal_position)
        from information_schema.parameters
        where specific_name = (select specific_name from information_schema.routines
                               where routine_schema = 'public' and routine_name = 'get_organization_staff_members')
          and parameter_mode = 'OUT')
        = array['membership_id','effective_start','is_self','display_name','invitation_recipient_email',
                'display_name_is_shared','responsibilities'], 'Members columns are exactly BR-13');
    perform pg_temp.assert_true((
        select array_agg(parameter_name::text order by ordinal_position)
        from information_schema.parameters
        where specific_name = (select specific_name from information_schema.routines
                               where routine_schema = 'public' and routine_name = 'get_organization_pending_invitations')
          and parameter_mode = 'OUT')
        = array['invitation_id','recipient_email','responsibilities','created_at','expires_at'],
        'Invitation columns are exactly BR-15');
    perform pg_temp.assert_true((
        select bool_and(to_jsonb(r)::text not like '%auth-private%' and to_jsonb(r)::text not like '%' || pg_temp.id(2, 9)::text || '%')
        from public.get_organization_staff_members(pg_temp.id(3, 1), null, null, 50) r), 'No Auth email or User id');
end $$;

-- VN 33: the reads write nothing; get_organization_staff and ACLs.
do $$ declare before text; begin
    perform pg_temp.act(1);
    before := pg_temp.fingerprint();
    perform pg_temp.members_paged(pg_temp.id(3, 1), 3);
    perform pg_temp.invitations_paged(pg_temp.id(3, 1), 3);
    perform pg_temp.assert_true(pg_temp.fingerprint() = before, 'Reads write nothing');
    perform pg_temp.assert_true(
        has_function_privilege('authenticated', 'public.get_organization_staff_members(uuid,timestamptz,uuid,integer)', 'execute')
        and has_function_privilege('authenticated', 'public.get_organization_pending_invitations(uuid,timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('anon', 'public.get_organization_staff_members(uuid,timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('anon', 'public.get_organization_pending_invitations(uuid,timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('service_role', 'public.get_organization_staff_members(uuid,timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('authenticated', 'public.organization_staff_reader(uuid)', 'execute')
        and not has_function_privilege('anon', 'public.organization_staff_reader(uuid)', 'execute')
        and not has_function_privilege('service_role', 'public.organization_staff_reader(uuid)', 'execute'),
        'Grants: authenticated only; the helper is executable by no client');
    perform pg_temp.assert_true(
        has_function_privilege('authenticated', 'public.get_organization_staff(uuid)', 'execute')
        and not has_function_privilege('anon', 'public.get_organization_staff(uuid)', 'execute')
        and (select prorettype = 'jsonb'::regtype from pg_proc where oid = 'public.get_organization_staff(uuid)'::regprocedure),
        'get_organization_staff unchanged');
end $$;

-- Exercise the real mobile SQL role.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.get_organization_staff_members(
    'd0120000-0000-4000-8000-000000003001', null, null, 25)) = 18, 'Authenticated role reads members');
select pg_temp.assert_true((select count(*) from public.get_organization_pending_invitations(
    'd0120000-0000-4000-8000-000000003001', null, null, 20)) = 8, 'Authenticated role reads invitations');
reset role;

-- VN 31: changes between pages neither repeat nor resurrect.
do $$
declare first_members uuid[]; first_invitations uuid[]; later_members uuid[]; later_invitations uuid[];
    cursor_member record; cursor_invitation record;
begin
    perform pg_temp.act(1);
    select array_agg(membership_id order by ordinality) into first_members
    from public.get_organization_staff_members(pg_temp.id(3, 1), null, null, 5) with ordinality;
    select * into cursor_member from public.get_organization_staff_members(pg_temp.id(3, 1), null, null, 5)
    order by effective_start desc, membership_id desc limit 1;
    select array_agg(invitation_id order by ordinality) into first_invitations
    from public.get_organization_pending_invitations(pg_temp.id(3, 1), null, null, 3) with ordinality;
    select * into cursor_invitation from public.get_organization_pending_invitations(pg_temp.id(3, 1), null, null, 3)
    order by created_at desc, invitation_id desc limit 1;

    set local session_replication_role = replica;
    -- A member after the cursor ends; an Invitation after the cursor is revoked;
    -- one already shown is revoked too.
    update public.organization_memberships set effective_end = statement_timestamp() - interval '1 second',
        ended_by_user_id = pg_temp.id(2, 1) where id = pg_temp.id(5, 17);
    update public.organization_invitations set revoked_at = statement_timestamp() - interval '1 second',
        revoked_by_user_id = pg_temp.id(2, 1) where id in (pg_temp.id(7, 6), pg_temp.id(7, 1));
    set local session_replication_role = origin;

    select array_agg(membership_id) into later_members from public.get_organization_staff_members(
        pg_temp.id(3, 1), cursor_member.effective_start, cursor_member.membership_id, 50);
    select array_agg(invitation_id) into later_invitations from public.get_organization_pending_invitations(
        pg_temp.id(3, 1), cursor_invitation.created_at, cursor_invitation.invitation_id, 50);
    perform pg_temp.assert_true(not (later_members && first_members) and not (pg_temp.id(5, 17) = any(later_members)),
        'Members: no repeat, ended member gone');
    perform pg_temp.assert_true(not (later_invitations && first_invitations) and not (pg_temp.id(7, 6) = any(later_invitations)),
        'Invitations: no repeat, revoked one gone');
    perform pg_temp.assert_true(cardinality(first_members) + cardinality(later_members) = 17
        and cardinality(first_invitations) + cardinality(later_invitations) = 7, 'Everything else still returned once');
end $$;

-- Volume: 3 000 members and 3 000 pending Invitations in one Organization;
-- first and deep pages are cut on the key without projecting the rest.
set local session_replication_role = replica;
insert into public.users (id) select pg_temp.id(20, n) from generate_series(1, 3000) n;
insert into public.user_profiles (user_id, display_name)
select pg_temp.id(20, n), 'Volume member ' || (n % 1500) from generate_series(1, 3000) n;
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(21, n), pg_temp.id(3, 3), pg_temp.id(20, n), '2020-01-01Z'::timestamptz + (n || ' minutes')::interval
from generate_series(1, 3000) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select pg_temp.id(22, n), pg_temp.id(21, n), case when n = 1 then 'OWNER' else 'RECEPTIONIST' end, 'ORGANIZATION',
    '2020-01-01Z', pg_temp.id(20, 1)
from generate_series(1, 3000) n;
insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email, created_at,
    expires_at, acceptance_secret_digest)
select pg_temp.id(23, n), pg_temp.id(3, 3), pg_temp.id(20, 1), 'volume-' || n || '@example.test',
    statement_timestamp() - interval '6 days' + (n || ' seconds')::interval, statement_timestamp() + interval '1 day',
    decode(repeat('cd', 32), 'hex')
from generate_series(1, 3000) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type)
select pg_temp.id(24, n), pg_temp.id(23, n), 'RECEPTIONIST', 'ORGANIZATION' from generate_series(1, 3000) n;
insert into auth.users (id, email, email_confirmed_at) values (pg_temp.id(1, 900), 'volume-owner@example.test', '2020-01-01Z');
insert into public.user_authentication_identities (user_id, provider_subject) values (pg_temp.id(20, 1), pg_temp.id(1, 900));
set local session_replication_role = origin;
analyze public.organization_memberships, public.organization_invitations, public.user_profiles,
    public.organization_responsibility_grants, public.organization_invitation_responsibilities;

do $$
declare started timestamptz; first_ms numeric; deep_ms numeric; invitations_first_ms numeric; invitations_deep_ms numeric;
    rows_seen integer;
begin
    perform set_config('request.jwt.claim.sub', pg_temp.id(1, 900)::text, true);
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_organization_staff_members(pg_temp.id(3, 3), null, null, 25);
    first_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 25, 'Volume: a first page of 25');
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_organization_staff_members(
        pg_temp.id(3, 3), '2020-01-01Z'::timestamptz + interval '2900 minutes', pg_temp.id(21, 2900), 25);
    deep_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 25, 'Volume: a deep page of 25');
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_organization_pending_invitations(pg_temp.id(3, 3), null, null, 20);
    invitations_first_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 20, 'Volume: a first Invitation page of 20');
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_organization_pending_invitations(
        pg_temp.id(3, 3),
        (select created_at from public.organization_invitations where id = pg_temp.id(23, 2900)),
        pg_temp.id(23, 2900), 20);
    invitations_deep_ms := extract(epoch from clock_timestamp() - started) * 1000;
    raise notice 'Volume (3000 members / 3000 invitations): members first % ms, deep % ms; invitations first % ms, deep % ms',
        round(first_ms, 1), round(deep_ms, 1), round(invitations_first_ms, 1), round(invitations_deep_ms, 1);
    perform pg_temp.assert_true(first_ms < 500 and deep_ms < 500 and invitations_first_ms < 500 and invitations_deep_ms < 500,
        'Volume: each page well under 500 ms');
end $$;

rollback;

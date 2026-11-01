-- SPEC-ORG-009 BR-1–BR-10 / Verification Notes; SPEC-ID-006 BR-40.
-- Isolated LOCAL superuser only. Fixtures, helper substitutions and assertions
-- are rollback-only. No Subscription fixture: Staff needs no Entitlement.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0090000-0000-4000-8000-' || lpad((kind * 100 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.outcome(organization uuid) returns text language plpgsql as $$ begin
    perform public.get_organization_staff(organization); return 'SUCCEEDED';
exception when others then return sqlstate || ': ' || sqlerrm; end $$;
create function pg_temp.fingerprint() returns text language plpgsql as $$
declare table_name text; rows_json text; result text := ''; begin
    -- Includes Communications: a read must not enqueue work or alter history.
    for table_name in select tablename from pg_tables where schemaname = 'public' order by tablename loop
        execute format('select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text, '''') from public.%I r', table_name)
        into rows_json;
        result := result || table_name || rows_json;
    end loop;
    return md5(result);
end $$;

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'auth-private-' || n || '@example.test', '2020-01-01Z' from generate_series(1, 18) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 17) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 17) n;
insert into public.user_profiles (user_id, display_name) values
    (pg_temp.id(2, 1), E'María  García'), (pg_temp.id(2, 4), 'Clinic admin');
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Staff Org A'), (pg_temp.id(3, 2), 'Staff Org B'), (pg_temp.id(3, 3), 'Empty Org');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 2)),
    (pg_temp.id(4, 3), pg_temp.id(3, 1));
insert into public.clinic_public_profiles (clinic_id, display_name) values
    (pg_temp.id(4, 1), 'A Centro'), (pg_temp.id(4, 2), 'B Norte');

-- Invitation 1 pending legacy multi-role; 2 accepted into current Membership;
-- 3 revoked; 4 rejected; 5 expired; 6 expired by a later read (its exact
-- read-instant boundary is pinned below); 7 accepted into an ended
-- Membership; 8 belongs to B; 9 second pending; 10 accepted into future Membership.
insert into public.organization_invitations (
    id, organization_id, inviting_user_id, recipient_email, created_at, expires_at,
    acceptance_secret_digest, revoked_at, revoked_by_user_id, rejected_at, rejected_by_user_id
)
select pg_temp.id(7, n), pg_temp.id(3, case when n = 8 then 2 else 1 end), pg_temp.id(2, 1),
    case when n = 2 then 'Invited.Work@Example.Test' else 'Pending-' || n || '@Example.Test' end,
    statement_timestamp() - interval '2 days',
    case when n = 5 then statement_timestamp() - interval '1 day'
         when n = 6 then statement_timestamp() else statement_timestamp() + interval '5 days' end,
    case when n in (2, 7, 10) then null else decode(repeat('ab', 32), 'hex') end,
    case when n = 3 then statement_timestamp() - interval '1 day' end,
    case when n = 3 then pg_temp.id(2, 1) end,
    case when n = 4 then statement_timestamp() - interval '1 day' end,
    case when n = 4 then pg_temp.id(2, 5) end
from generate_series(1, 10) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id)
select pg_temp.id(8, n), pg_temp.id(7, n), 'RECEPTIONIST', 'ORGANIZATION', null from generate_series(1, 10) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id) values
    (pg_temp.id(8, 20), pg_temp.id(7, 1), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)),
    (pg_temp.id(8, 21), pg_temp.id(7, 1), 'VETERINARIAN', 'ORGANIZATION', null);

-- 1 Owner, 2 Org Admin, 3 unnamed invited member, 4 Clinic Admin,
-- 5 Org Receptionist, 6 Veterinarian (+professional profile/assignment),
-- 7 ended member, 8 ended Admin grant, 9 bare member, 10 B Owner,
-- 11 future member/12 future Admin grant, 13 another Clinic Receptionist,
-- 14 member with several grants incl. ended/future, 15 fixture fallback,
-- 16 A-only member and 17 no Membership. Owner 1 also owns B and Empty Org.
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id, originating_invitation_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 10 then 2 else 1 end), pg_temp.id(2, n),
    case when n = 11 then statement_timestamp() + interval '1 day' else '2020-01-01Z'::timestamptz end,
    case when n = 7 then '2021-01-01Z'::timestamptz end,
    case when n = 7 then pg_temp.id(2, 1) end,
    case when n = 3 then pg_temp.id(7, 2) when n = 7 then pg_temp.id(7, 7) when n = 11 then pg_temp.id(7, 10) end
from generate_series(1, 16) n;
insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    (pg_temp.id(5, 20), pg_temp.id(3, 2), pg_temp.id(2, 1), '2020-01-01Z'),
    (pg_temp.id(5, 21), pg_temp.id(3, 3), pg_temp.id(2, 1), '2020-01-01Z'),
    (pg_temp.id(5, 22), pg_temp.id(3, 2), pg_temp.id(2, 14), '2020-01-01Z');
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case when n in (1, 10, 20, 21) then 'OWNER' when n in (2, 4, 7, 8, 11, 12) then 'ADMINISTRATOR'
         when n = 6 then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (4, 13, 14, 22) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (4, 14) then pg_temp.id(4, 1) when n = 13 then pg_temp.id(4, 3) when n = 22 then pg_temp.id(4, 2) end,
    case when n = 12 then statement_timestamp() + interval '1 day' else '2020-01-01Z'::timestamptz end,
    case when n = 8 then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n = 8 then pg_temp.id(2, 1) end
from unnest(array[1,2,3,4,5,6,7,8,11,12,13,14,15,16,20,21,22]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id) values
    (pg_temp.id(6, 30), pg_temp.id(5, 14), 'VETERINARIAN', 'ORGANIZATION', '2020-01-01Z', null, pg_temp.id(2, 1), null),
    (pg_temp.id(6, 31), pg_temp.id(5, 14), 'ADMINISTRATOR', 'ORGANIZATION', '2020-01-01Z', '2021-01-01Z', pg_temp.id(2, 1), pg_temp.id(2, 1)),
    (pg_temp.id(6, 32), pg_temp.id(5, 14), 'RECEPTIONIST', 'ORGANIZATION', statement_timestamp() + interval '1 day', null, pg_temp.id(2, 1), null);
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(9, 6), pg_temp.id(2, 6));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values (pg_temp.id(10, 6), pg_temp.id(9, 6), pg_temp.id(5, 6), pg_temp.id(4, 1), '2020-01-01Z');
set local session_replication_role = origin;

-- Real role matrix and indistinguishable denied outcomes, including NULL.
do $$ declare n integer; begin
    foreach n in array array[1,2] loop
        perform pg_temp.act(n);
        perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,1)) = 'SUCCEEDED', 'Owner/Org Administrator access');
    end loop;
    foreach n in array array[3,4,5,6,7,8,9,10,11,12,13,14,15,16,17] loop
        perform pg_temp.act(n);
        perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,1)) = '42501: Organization Staff unavailable',
            'Denied actor ' || n);
        perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,99)) = pg_temp.outcome(pg_temp.id(3,1)), 'Unknown/inaccessible parity');
    end loop;
    perform pg_temp.act(1);
    perform pg_temp.assert_true(pg_temp.outcome(null) = '42501: Organization Staff unavailable', 'NULL unavailable');
    perform pg_temp.act(18);
    perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,1)) = '28000: No coherent domain User exists for the authenticated subject', 'Unlinked subject authentication');
    perform pg_temp.act(0);
    perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,1)) = '28000: Authentication is required'
        and pg_temp.outcome(pg_temp.id(3,99)) = '28000: Authentication is required', 'Anonymous authentication first');
end $$;

-- Exercise the real mobile SQL role, not only superuser impersonation.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_true(public.get_organization_staff('d0090000-0000-4000-8000-000000000301')->>'organization_display_name' = 'Staff Org A', 'Authenticated role executes the protected read');
reset role;

-- Isolate each side of the OR using a temporary authoritative predicate.
create temporary table capability_backup as select pg_get_functiondef('public.user_has_organization_capability(uuid,uuid,text)'::regprocedure) definition;
create or replace function public.user_has_organization_capability(p_user_id uuid, p_organization_id uuid, p_capability text)
returns boolean language sql stable security definer set search_path = '' as $$
    select p_user_id = pg_temp.id(2,1) and p_organization_id = pg_temp.id(3,1)
        and p_capability = current_setting('staff_test.capability', true)
$$;
do $$ declare cap text; begin
    perform pg_temp.act(1);
    foreach cap in array array['ORGANIZATION_INVITE_MEMBERS','ORGANIZATION_END_MEMBERSHIPS'] loop
        perform set_config('staff_test.capability', cap, true);
        perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,1)) = 'SUCCEEDED', cap || ' alone');
    end loop;
    foreach cap in array array['ORGANIZATION_REVOKE_INVITATIONS','CLINIC_MANAGE_PUBLIC_PROFILE','APPOINTMENT_VIEW_SCHEDULE',''] loop
        perform set_config('staff_test.capability', cap, true);
        perform pg_temp.assert_true(pg_temp.outcome(pg_temp.id(3,1)) = '42501: Organization Staff unavailable', 'Unrelated capability denied');
    end loop;
end $$;
do $$ begin execute (select definition from capability_backup); end $$;
drop table capability_backup;

create function pg_temp.keys(raw jsonb) returns text[] language sql as $$
    select array_agg(key order by key) from jsonb_object_keys(raw) key
$$;
create function pg_temp.member(payload jsonb, n integer) returns jsonb language sql as $$
    select value from jsonb_array_elements(payload->'members') where value->>'membership_id' = pg_temp.id(5,n)::text
$$;
do $$ declare a jsonb; b jsonb; m jsonb; inv jsonb; roles jsonb; before_state text; begin
    perform pg_temp.act(1);
    before_state := pg_temp.fingerprint();
    a := public.get_organization_staff(pg_temp.id(3,1));
    b := public.get_organization_staff(pg_temp.id(3,2));
    perform pg_temp.assert_true(pg_temp.fingerprint() = before_state, 'Read changes no public rows, including Communications');
    perform pg_temp.assert_true(pg_temp.keys(a) = array['members','organization_display_name','organization_id','pending_invitations'], 'Exact envelope');
    perform pg_temp.assert_true(a->>'organization_id' = pg_temp.id(3,1)::text and a->>'organization_display_name' = 'Staff Org A', 'Organization identity');
    perform pg_temp.assert_true((select array_agg((value->>'membership_id')::uuid order by ord)
        from jsonb_array_elements(a->'members') with ordinality as rows(value,ord)) =
        array[pg_temp.id(5,1),pg_temp.id(5,2),pg_temp.id(5,3),pg_temp.id(5,4),pg_temp.id(5,5),pg_temp.id(5,6),
        pg_temp.id(5,8),pg_temp.id(5,9),pg_temp.id(5,12),pg_temp.id(5,13),pg_temp.id(5,14),pg_temp.id(5,15),pg_temp.id(5,16)],
        'Exactly current A Memberships in canonical order, ended/future/B absent');
    perform pg_temp.assert_true(jsonb_array_length(b->'members') = 3 and pg_temp.member(b,16) is null,
        'B read contains only B, A-only member absent');
    for m in select value from jsonb_array_elements(a->'members') loop
        perform pg_temp.assert_true(pg_temp.keys(m) = array['display_name','effective_start','invitation_recipient_email','is_self','membership_id','responsibilities'], 'Exact Member fields: no User id/Auth data');
        perform pg_temp.assert_true(m->>'effective_start' = '2020-01-01T00:00:00+00:00', 'Membership start');
        perform pg_temp.assert_true((m->>'is_self')::boolean = (m->>'membership_id' = pg_temp.id(5,1)::text), 'is_self');
        for roles in select value from jsonb_array_elements(m->'responsibilities') loop
            perform pg_temp.assert_true(pg_temp.keys(roles) = array['clinic','responsibility','responsibility_grant_id','scope_type'], 'Exact Grant fields');
            perform pg_temp.assert_true(exists (select 1 from public.organization_responsibility_grants g
                where g.id = (roles->>'responsibility_grant_id')::uuid and g.membership_id = (m->>'membership_id')::uuid
                  and g.responsibility = roles->>'responsibility' and g.scope_type = roles->>'scope_type'
                  and g.clinic_id is not distinct from (roles->'clinic'->>'clinic_id')::uuid
                  and g.effective_start <= statement_timestamp() and g.effective_end is null),
                'Grant id identifies exactly that current Grant of that Membership');
            if roles->>'scope_type' = 'CLINIC' then
                perform pg_temp.assert_true(pg_temp.keys(roles->'clinic') = array['clinic_display_name','clinic_id']
                    and roles->'clinic'->>'clinic_id' in (pg_temp.id(4,1)::text,pg_temp.id(4,3)::text), 'Only A Clinic identity');
            else
                perform pg_temp.assert_true(roles->'clinic' = 'null'::jsonb, 'Organization scope has no Clinic');
            end if;
        end loop;
    end loop;
    perform pg_temp.assert_true(pg_temp.member(a,1)->>'display_name' = E'María  García'
        and pg_temp.member(a,1)->'invitation_recipient_email' = 'null'::jsonb, 'Stored display name and provisioned identity');
    perform pg_temp.assert_true(pg_temp.member(a,3)->>'invitation_recipient_email' = 'invited.work@example.test'
        and pg_temp.member(a,3)->'display_name' = 'null'::jsonb, 'Originating normalized Invitation context');
    perform pg_temp.assert_true(pg_temp.member(a,15)->'display_name' = 'null'::jsonb
        and pg_temp.member(a,15)->'invitation_recipient_email' = 'null'::jsonb, 'Fixture identity safely absent');
    perform pg_temp.assert_true(a::text not like '%auth-private-%' and a::text not like '%ababaab%', 'No hidden Auth or secrets');
    perform pg_temp.assert_true(pg_temp.member(a,1)->'responsibilities'->0->>'responsibility' = 'OWNER'
        and pg_temp.member(a,6)->'responsibilities'->0->>'responsibility' = 'VETERINARIAN', 'OWNER and VETERINARIAN visible');
    perform pg_temp.assert_true(pg_temp.member(a,8)->'responsibilities' = '[]'::jsonb
        and pg_temp.member(a,9)->'responsibilities' = '[]'::jsonb
        and pg_temp.member(a,12)->'responsibilities' = '[]'::jsonb, 'Ended/future/no Grants return empty arrays');
    perform pg_temp.assert_true(pg_temp.member(a,14)->'responsibilities' = jsonb_build_array(
        jsonb_build_object('responsibility_grant_id',pg_temp.id(6,14),'responsibility','RECEPTIONIST','scope_type','CLINIC','clinic',jsonb_build_object('clinic_id',pg_temp.id(4,1),'clinic_display_name','A Centro')),
        jsonb_build_object('responsibility_grant_id',pg_temp.id(6,30),'responsibility','VETERINARIAN','scope_type','ORGANIZATION','clinic',null)), 'Multiple current Grants ordered, ended/future absent');
    perform pg_temp.assert_true(pg_temp.member(a,13)->'responsibilities'->0->'clinic' = jsonb_build_object('clinic_id',pg_temp.id(4,3),'clinic_display_name',null), 'Unnamed Clinic identity remains');
    perform pg_temp.assert_true((select array_agg(value->>'invitation_id' order by ord)
        from jsonb_array_elements(a->'pending_invitations') with ordinality rows(value,ord)) =
        array[pg_temp.id(7,1)::text, pg_temp.id(7,9)::text], 'Only pending A Invitations ordered: accepted/revoked/rejected/expired absent');
    for inv in select value from jsonb_array_elements(a->'pending_invitations') loop
        perform pg_temp.assert_true(pg_temp.keys(inv) = array['created_at','expires_at','invitation_id','recipient_email','responsibilities'], 'Exact Invitation fields, no secret/digest/envelope/Communication');
        perform pg_temp.assert_true(not exists (select 1 from jsonb_array_elements(inv->'responsibilities') r
            where pg_temp.keys(r) <> array['clinic','responsibility','scope_type']),
            'Invitation intended responsibilities carry no Grant identifier');
        perform pg_temp.assert_true(inv->>'recipient_email' = lower(inv->>'recipient_email')
            and (inv->>'expires_at')::timestamptz > statement_timestamp()
            and (inv->>'created_at')::timestamptz < statement_timestamp(), 'Normalized email and backend instants');
    end loop;
    inv := a->'pending_invitations'->0;
    perform pg_temp.assert_true(jsonb_array_length(inv->'responsibilities') = 3
        and inv->'responsibilities'->0->'clinic'->>'clinic_display_name' = 'A Centro'
        and inv->'responsibilities'->2->>'responsibility' = 'VETERINARIAN', 'Every legacy intended responsibility with Clinic');
    perform pg_temp.assert_true(jsonb_array_length(public.get_organization_staff(pg_temp.id(3,3))->'members') = 1
        and public.get_organization_staff(pg_temp.id(3,3))->'pending_invitations' = '[]'::jsonb, 'Empty Invitations');
end $$;

-- Expiry boundary at the read's own evaluation instant: the fixture update
-- and the read share this statement's statement_timestamp().
do $$ declare t timestamptz := statement_timestamp(); begin
    perform pg_temp.act(1);
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t where id = pg_temp.id(7,6);
    execute 'set local session_replication_role = origin';
    perform pg_temp.assert_true(not exists (select 1 from jsonb_array_elements(
        public.get_organization_staff(pg_temp.id(3,1))->'pending_invitations') i where i->>'invitation_id' = pg_temp.id(7,6)::text),
        'Invitation expiring exactly at the read instant is not pending');
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t + interval '1 microsecond' where id = pg_temp.id(7,6);
    execute 'set local session_replication_role = origin';
    perform pg_temp.assert_true(exists (select 1 from jsonb_array_elements(
        public.get_organization_staff(pg_temp.id(3,1))->'pending_invitations') i where i->>'invitation_id' = pg_temp.id(7,6)::text),
        'Invitation expiring just after the read instant is pending');
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t where id = pg_temp.id(7,6);
    execute 'set local session_replication_role = origin';
end $$;

-- A capability-only test can observe truly empty arrays, without inventing a
-- product mapping or an active Owner requirement exception in production.
create temporary table capability_backup as select pg_get_functiondef('public.user_has_organization_capability(uuid,uuid,text)'::regprocedure) definition;
set local session_replication_role = replica;
insert into public.veterinary_organizations (id,display_name) values (pg_temp.id(3,4),'Empty fixture');
set local session_replication_role = origin;
create or replace function public.user_has_organization_capability(p_user_id uuid,p_organization_id uuid,p_capability text)
returns boolean language sql stable security definer set search_path = '' as $$
    select p_user_id = pg_temp.id(2,1) and p_organization_id = pg_temp.id(3,4) and p_capability = 'ORGANIZATION_INVITE_MEMBERS'
$$;
select pg_temp.assert_true(public.get_organization_staff(pg_temp.id(3,4)) = jsonb_build_object(
    'organization_id',pg_temp.id(3,4),'organization_display_name','Empty fixture','members','[]'::jsonb,'pending_invitations','[]'::jsonb), 'Empty arrays, never missing');
do $$ begin execute (select definition from capability_backup); end $$;
drop table capability_backup;

-- Lock evidence uses a fresh Organization never read before in this
-- transaction, so the measurement isolates exactly the read below. Freshly
-- inserted rows carry no tuple locks; xmax proves the read adds none; the
-- control FOR UPDATE proves this measurement detects a real business lock.
set local session_replication_role = replica;
insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3,5), 'Lock probe Org');
insert into public.clinics (id, organization_id) values (pg_temp.id(4,5), pg_temp.id(3,5));
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
values (pg_temp.id(5,30), pg_temp.id(3,5), pg_temp.id(2,1), '2020-01-01Z');
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
values (pg_temp.id(6,40), pg_temp.id(5,30), 'OWNER', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2,1));
insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email, created_at, expires_at, acceptance_secret_digest)
values (pg_temp.id(7,30), pg_temp.id(3,5), pg_temp.id(2,1), 'lock-probe@example.test', statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '5 days', decode(repeat('cd', 32), 'hex'));
set local session_replication_role = origin;
create function pg_temp.lock_probe_rows_locked() returns boolean language sql as $$
    select exists(
        select 1 from public.veterinary_organizations where id = pg_temp.id(3,5) and xmax::text <> '0'
        union all select 1 from public.organization_memberships where organization_id = pg_temp.id(3,5) and xmax::text <> '0'
        union all select 1 from public.organization_invitations where organization_id = pg_temp.id(3,5) and xmax::text <> '0'
        union all select 1 from public.organization_responsibility_grants where membership_id in
            (select id from public.organization_memberships where organization_id = pg_temp.id(3,5)) and xmax::text <> '0'
        union all select 1 from public.clinics where organization_id = pg_temp.id(3,5) and xmax::text <> '0')
$$;
select pg_temp.assert_true(not pg_temp.lock_probe_rows_locked(), 'No business tuple locks before read');
select pg_temp.act(1);
select pg_temp.assert_true(jsonb_array_length(public.get_organization_staff(pg_temp.id(3,5))->'pending_invitations') = 1, 'Lock probe read succeeds');
select pg_temp.assert_true(not pg_temp.lock_probe_rows_locked(), 'Read acquires no business tuple locks');
select 1 from public.veterinary_organizations where id = pg_temp.id(3,2) for update;
select pg_temp.assert_true(exists(select 1 from public.veterinary_organizations where id = pg_temp.id(3,2) and xmax::text <> '0'), 'Lock measurement positive control');
-- Recorded future ends are terminal under Phase 1, not scheduled current
-- periods. Staff and the shared helpers use the same canonical predicate.
set local session_replication_role = replica;
update public.organization_memberships set effective_end=statement_timestamp()+interval '1 day',ended_by_user_id=pg_temp.id(2,1)
where id=pg_temp.id(5,16);
update public.organization_responsibility_grants set effective_end=statement_timestamp()+interval '1 day',ended_by_user_id=pg_temp.id(2,1)
where membership_id=pg_temp.id(5,13);
set local session_replication_role = origin;
select pg_temp.assert_true(pg_temp.member(public.get_organization_staff(pg_temp.id(3,1)),16) is null
    and pg_temp.member(public.get_organization_staff(pg_temp.id(3,1)),13)->'responsibilities'='[]'::jsonb,
    'Staff canonical currentness excludes every recorded Membership/Grant end');
set local session_replication_role = replica;
update public.organization_memberships set effective_end=null,ended_by_user_id=null where id=pg_temp.id(5,16);
update public.organization_responsibility_grants set effective_end=null,ended_by_user_id=null where membership_id=pg_temp.id(5,13);
set local session_replication_role = origin;

select pg_temp.assert_true((select provolatile = 's' and prosecdef and proconfig @> array['search_path=""'] from pg_proc
    where oid = 'public.get_organization_staff(uuid)'::regprocedure), 'STABLE SECURITY DEFINER empty search_path');
select pg_temp.assert_true(has_function_privilege('authenticated','public.get_organization_staff(uuid)','EXECUTE')
    and not has_function_privilege('anon','public.get_organization_staff(uuid)','EXECUTE')
    and not has_function_privilege('service_role','public.get_organization_staff(uuid)','EXECUTE'), 'Authenticated-only ACL');
select pg_temp.assert_true(not exists(select 1 from unnest(array['organization_memberships','organization_responsibility_grants',
    'organization_invitations','organization_invitation_responsibilities']) t
    where has_table_privilege('authenticated','public.' || t,'SELECT') or has_table_privilege('anon','public.' || t,'SELECT')), 'No client table reads');
rollback;

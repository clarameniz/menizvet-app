-- Staff Phase 1 Slice B1: SPEC-ORG-002 §10/§11 (BR-17–BR-23), SPEC-ORG-010,
-- SPEC-COM-001 BR-44–BR-46, SPEC-ORG-009 integration.
-- Isolated LOCAL superuser only. Fixtures, helper substitutions and assertions
-- are rollback-only. No Subscription fixture: invite/revoke need no Entitlement.
-- The Edge route is exercised separately (Deno); here its two service-role
-- commands are called exactly as the route calls them, with dummy envelope
-- bytes (the database cannot decrypt and never sees the secret).
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0270000-0000-4000-8000-' || lpad((kind * 100 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.subject(n integer) returns uuid language sql immutable as $$
    select case when n = 0 then null else pg_temp.id(1, n) end
$$;
create function pg_temp.bytes(n integer) returns bytea language sql volatile as $$
    select decode(substr(md5(random()::text) || md5(random()::text), 1, 2 * n), 'hex')
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(pg_temp.subject(n)::text, ''), true)
$$;
-- The Edge route: authorize (and fix T), then create with T. A NULL instant
-- means "call authorize"; deferred integrity triggers fire inside the call.
create function pg_temp.invite_full(actor integer, organization uuid, email text, role text,
    scope text, clinic uuid, digest bytea, instant timestamptz) returns text
language plpgsql as $$
declare created uuid; failure_hint text; begin
    if instant is null then
        instant := public.authorize_organization_invitation_creation(pg_temp.subject(actor), organization);
    end if;
    created := public.create_staff_organization_invitation_with_communication(
        pg_temp.subject(actor), organization, email, role, scope, clinic, instant,
        digest, 1, pg_temp.bytes(12), pg_temp.bytes(32));
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return created::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return sqlstate || ':' || coalesce(nullif(failure_hint, ''), '-') || ':' || sqlerrm;
end $$;
create function pg_temp.invite(actor integer, organization uuid, email text, role text,
    scope text, clinic uuid default null) returns text language sql as $$
    select pg_temp.invite_full(actor, organization, email, role, scope, clinic, pg_temp.bytes(32), null)
$$;
create function pg_temp.authorize(actor integer, organization uuid) returns text language plpgsql as $$
declare failure_hint text; begin
    return public.authorize_organization_invitation_creation(pg_temp.subject(actor), organization)::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return sqlstate || ':' || coalesce(nullif(failure_hint, ''), '-') || ':' || sqlerrm;
end $$;
-- Calls the create command directly, without the authorize preflight.
create function pg_temp.create_direct(actor integer, organization uuid, email text, role text,
    scope text, clinic uuid default null) returns text language plpgsql as $$
begin
    return pg_temp.invite_full(actor, organization, email, role, scope, clinic, pg_temp.bytes(32),
        date_trunc('milliseconds', statement_timestamp()));
end $$;
create function pg_temp.is_created(outcome text) returns boolean language sql as $$
    select outcome ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$$;
create function pg_temp.revoke(actor integer, invitation uuid) returns text language plpgsql as $$
begin
    perform pg_temp.act(actor);
    return public.revoke_organization_invitation(invitation)::text;
exception when others then return sqlstate || ':' || sqlerrm; end $$;
-- Errors become {"error": ...} so a faulty operation fails a named assertion.
create function pg_temp.revoke_json(actor integer, invitation uuid) returns jsonb language sql as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
    from pg_temp.revoke(actor, invitation) result
$$;
create function pg_temp.outcome_of(actor integer, invitation uuid) returns text language sql as $$
    select case when result like '{%' then result::jsonb ->> 'outcome' else result end
    from pg_temp.revoke(actor, invitation) result
$$;
create function pg_temp.accept(actor integer, invitation uuid, digest bytea) returns text language plpgsql as $$
begin
    return public.accept_organization_invitation(pg_temp.id(2, actor), invitation, digest)::text;
exception when others then return sqlstate || ':' || sqlerrm; end $$;
create function pg_temp.pending_ids(organization uuid, actor integer default 1) returns uuid[] language plpgsql as $$
declare result uuid[]; begin
    perform pg_temp.act(actor);
    select coalesce(array_agg((value ->> 'invitation_id')::uuid order by ord), '{}') into result
    from jsonb_array_elements(public.get_organization_staff(organization) -> 'pending_invitations')
        with ordinality as rows(value, ord);
    return result;
end $$;
create function pg_temp.invitation_state(invitation uuid) returns text language sql as $$
    select md5(coalesce((select to_jsonb(i)::text from public.organization_invitations i where i.id = invitation), '')
        || coalesce((select jsonb_agg(to_jsonb(r) order by r.id)::text
            from public.organization_invitation_responsibilities r where r.invitation_id = invitation), ''))
$$;
create function pg_temp.membership_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), '')
        || coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), ''))
$$;
create function pg_temp.communication_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.transactional_communications c), '')
        || coalesce((select jsonb_agg(to_jsonb(j) order by j.id)::text from public.communication_delivery_jobs j), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.communication_delivery_attempts a), ''))
$$;

set local session_replication_role = replica;
-- Actors: 1 Owner A, 2 Org Admin A, 3 Clinic Admin A, 4 Org Receptionist A,
-- 5 Veterinarian A, 6 Clinic Receptionist A, 7 bare Member A, 8 unverified Org
-- Admin A, 9 Org Admin A whose Grant ended (lost capability), 10 Owner B,
-- 11/12 recipients, 13 former Member of A (joined by Invitation 2),
-- 14 active Member of A (joined by Invitation 1), 15 no Membership,
-- 16 authenticated subject without a domain User.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'auth-private-' || n || '@example.test',
    case when n = 8 then null else '2020-01-01Z'::timestamptz end
from generate_series(1, 16) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 15) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 15) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Invite Org A'), (pg_temp.id(3, 2), 'Invite Org B');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 1)), (pg_temp.id(4, 3), pg_temp.id(3, 2));
insert into public.clinic_public_profiles (clinic_id, display_name) values
    (pg_temp.id(4, 1), 'A Centro'), (pg_temp.id(4, 3), 'B Norte');
-- Pre-existing Invitations: 1 accepted by 14 (active), 2 accepted by 13
-- (ended), 3 expired, 4 rejected, 5 pending in B, 6 pending (expiry boundary),
-- 7 pending created by the inviter who later lost capability.
insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email,
    created_at, expires_at, acceptance_secret_digest, rejected_at, rejected_by_user_id)
select pg_temp.id(7, n), pg_temp.id(3, case when n = 5 then 2 else 1 end),
    pg_temp.id(2, case when n = 7 then 9 when n = 5 then 10 else 1 end),
    (array['Active.Member@Example.Test', 'former@example.test', 'expired@example.test',
        'rejected@example.test', 'b.pending@example.test', 'boundary@example.test',
        'lost.inviter@example.test'])[n],
    case when n in (1, 2) then '2020-01-01Z'::timestamptz else statement_timestamp() - interval '10 days' end,
    case when n in (1, 2) then '2020-01-08Z'::timestamptz
         when n = 3 then statement_timestamp() - interval '3 days'
         else statement_timestamp() + interval '6 days' end,
    case when n in (1, 2) then null else decode(repeat('ab', 32), 'hex') end,
    case when n = 4 then statement_timestamp() - interval '1 hour' end,
    case when n = 4 then pg_temp.id(2, 11) end
from generate_series(1, 7) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type)
select pg_temp.id(8, n), pg_temp.id(7, n), 'RECEPTIONIST', 'ORGANIZATION' from generate_series(1, 7) n;
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end,
    ended_by_user_id, originating_invitation_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 10 then 2 else 1 end), pg_temp.id(2, n),
    case when n in (13, 14) then '2020-01-02Z'::timestamptz else '2020-01-01Z'::timestamptz end,
    case when n = 13 then '2021-01-01Z'::timestamptz end, case when n = 13 then pg_temp.id(2, 1) end,
    case when n = 14 then pg_temp.id(7, 1) when n = 13 then pg_temp.id(7, 2) end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id, originating_invitation_responsibility_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case when n in (1, 10) then 'OWNER' when n in (2, 3, 8, 9) then 'ADMINISTRATOR'
         when n = 5 then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (3, 6) then 'CLINIC' else 'ORGANIZATION' end,
    case when n = 3 then pg_temp.id(4, 1) when n = 6 then pg_temp.id(4, 2) end,
    case when n in (13, 14) then '2020-01-02Z'::timestamptz else '2020-01-01Z'::timestamptz end,
    case when n in (9, 13) then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n in (9, 13) then pg_temp.id(2, 1) end,
    case when n = 14 then pg_temp.id(8, 1) when n = 13 then pg_temp.id(8, 2) end
from unnest(array[1, 2, 3, 4, 5, 6, 8, 9, 10, 13, 14]) n;
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Invite: fail-closed authorization before any input (BR-1, BR-22, Notes 2, 21, 22)
-- ---------------------------------------------------------------------------
do $$ declare n integer; denied text := '42501:ORGANIZATION_UNAVAILABLE:Organization Invitation unavailable'; begin
    foreach n in array array[3, 4, 5, 6, 7, 9, 10, 15] loop
        perform pg_temp.assert_true(pg_temp.authorize(n, pg_temp.id(3, 1)) = denied
            and pg_temp.authorize(n, pg_temp.id(3, 99)) = denied, 'Denied inviter ' || n);
        perform pg_temp.assert_true(pg_temp.create_direct(n, pg_temp.id(3, 1), 'x@example.test', 'RECEPTIONIST', 'ORGANIZATION') = denied
            and pg_temp.create_direct(n, pg_temp.id(3, 1), '', 'OWNER', 'NOWHERE', pg_temp.id(4, 3)) = denied
            and pg_temp.invite(n, pg_temp.id(3, 1), '', 'OWNER', 'CLINIC', pg_temp.id(4, 99)) = denied,
            'Denied inviter fails before any input validation ' || n);
    end loop;
    perform pg_temp.assert_true(pg_temp.authorize(1, pg_temp.id(3, 99)) = denied
        and pg_temp.authorize(1, null) = denied
        and pg_temp.create_direct(1, pg_temp.id(3, 99), '', 'OWNER', 'CLINIC') = denied,
        'Unknown Organization indistinguishable from inaccessible');
    perform pg_temp.assert_true(pg_temp.authorize(8, pg_temp.id(3, 1)) = '42501:ACCOUNT_VERIFICATION_REQUIRED:A verified email address is required'
        and pg_temp.authorize(8, pg_temp.id(3, 99)) = pg_temp.authorize(8, pg_temp.id(3, 1))
        and pg_temp.create_direct(8, pg_temp.id(3, 1), 'x@example.test', 'RECEPTIONIST', 'ORGANIZATION') = pg_temp.authorize(8, pg_temp.id(3, 1)),
        'Unverified inviter rejected before the Organization is considered');
    perform pg_temp.assert_true(pg_temp.authorize(16, pg_temp.id(3, 1)) = '28000:-:A coherent acting domain User is required'
        and pg_temp.authorize(0, pg_temp.id(3, 1)) = '28000:-:A coherent acting domain User is required'
        and pg_temp.create_direct(0, pg_temp.id(3, 1), 'x@example.test', 'RECEPTIONIST', 'ORGANIZATION') = '28000:-:A coherent acting domain User is required',
        'Unauthenticated inviter');
    perform pg_temp.assert_true(not exists (select 1 from public.organization_invitations where id::text not like 'd0270000-%'),
        'Denied attempts create nothing');
end $$;

-- ---------------------------------------------------------------------------
-- The four Phase 1 combinations and the stored single-responsibility facts
-- (BR-17, BR-18, BR-23, Notes 11, 14, 15)
-- ---------------------------------------------------------------------------
create temporary table b1_created (label text primary key, id uuid not null) on commit drop;
do $$ declare outcome text; t timestamptz := statement_timestamp(); instant timestamptz; inv record; comm record; begin
    instant := public.authorize_organization_invitation_creation(pg_temp.subject(1), pg_temp.id(3, 1));
    perform pg_temp.assert_true(instant = date_trunc('milliseconds', t) and instant <= t,
        'Creation instant is this database''s statement time at millisecond precision');
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), E'  New.Admin@Example.Test \t', 'ADMINISTRATOR', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Owner invites Organization Administrator: ' || outcome);
    insert into b1_created values ('org_admin', outcome::uuid);
    outcome := pg_temp.invite(2, pg_temp.id(3, 1), 'org.recep@example.test', 'RECEPTIONIST', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Organization Administrator invites Organization Receptionist: ' || outcome);
    insert into b1_created values ('org_recep', outcome::uuid);
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), 'clinic.admin@example.test', 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1));
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Clinic Administrator Invitation: ' || outcome);
    insert into b1_created values ('clinic_admin', outcome::uuid);
    outcome := pg_temp.invite(2, pg_temp.id(3, 1), 'clinic.recep@example.test', 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2));
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Clinic Receptionist Invitation: ' || outcome);
    insert into b1_created values ('clinic_recep', outcome::uuid);

    for inv in select c.label, i.*, r.responsibility, r.scope_type, r.clinic_id,
            (select count(*) from public.organization_invitation_responsibilities x where x.invitation_id = i.id) role_count
        from b1_created c join public.organization_invitations i on i.id = c.id
        join public.organization_invitation_responsibilities r on r.invitation_id = i.id loop
        perform pg_temp.assert_true(inv.role_count = 1, 'Exactly one intended responsibility ' || inv.label);
        perform pg_temp.assert_true(inv.created_at = instant and inv.expires_at = inv.created_at + interval '168 hours'
            and extract(epoch from inv.expires_at - inv.created_at) = 604800,
            'Stored expiry is exactly 7 days after the trusted creation instant ' || inv.label);
        perform pg_temp.assert_true(inv.recipient_user_id is null and inv.organization_id = pg_temp.id(3, 1)
            and inv.revoked_at is null and inv.rejected_at is null and octet_length(inv.acceptance_secret_digest) = 32,
            'Pending email-addressed Invitation binds no recipient User ' || inv.label);
        perform pg_temp.assert_true(inv.inviting_user_id = pg_temp.id(2, case when inv.label in ('org_admin', 'clinic_admin') then 1 else 2 end),
            'Inviting User derived from the authenticated subject ' || inv.label);
        perform pg_temp.assert_true(jsonb_build_array(inv.label, inv.responsibility, inv.scope_type, inv.clinic_id) in (
            jsonb_build_array('org_admin', 'ADMINISTRATOR', 'ORGANIZATION', null), jsonb_build_array('org_recep', 'RECEPTIONIST', 'ORGANIZATION', null),
            jsonb_build_array('clinic_admin', 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)),
            jsonb_build_array('clinic_recep', 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2))),
            'Stored role/scope/Clinic equals the request ' || inv.label);
        select * into comm from public.transactional_communications where organization_invitation_id = inv.id;
        perform pg_temp.assert_true((select count(*) from public.transactional_communications where organization_invitation_id = inv.id) = 1
            and comm.communication_type = 'ORGANIZATION_INVITATION' and comm.recipient_email = inv.recipient_email
            and comm.recipient_user_id is null and comm.secret_consumed_at is null
            and comm.secret_aad_context = public.build_invitation_secret_aad('organization', inv.recipient_email,
                inv.created_at + interval '168 hours', inv.acceptance_secret_digest)
            and comm.secret_aad_context like '%|expires_at_ms=' || ((extract(epoch from instant + interval '7 days') * 1000)::bigint)::text || '|%',
            'One transactional Communication whose envelope context binds the derived expiry ' || inv.label);
    end loop;
    perform pg_temp.assert_true((select recipient_email from public.organization_invitations where id = (select id from b1_created where label = 'org_admin'))
        = 'New.Admin@Example.Test', 'Recipient address stored trimmed (normalized column lowercases)');
    perform pg_temp.assert_true(not exists (select 1 from public.organization_memberships where id::text not like 'd0270000-%')
        and not exists (select 1 from public.organization_responsibility_grants where id::text not like 'd0270000-%')
        and not exists (select 1 from public.users where id::text not like 'd0270000-%'),
        'Invitation creates no Membership, Grant, or User');
    perform pg_temp.assert_true(not exists (select 1 from public.communication_delivery_jobs),
        'Creation hands off to the outbox only; nothing is sent');
end $$;

-- Organization-scoped VETERINARIAN stays valid for the product contract
-- (SPEC-ORG-002 §10, BR-17); the mobile form simply does not offer it.
do $$ declare outcome text; begin
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), 'org.vet@example.test', 'VETERINARIAN', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Organization-scoped Veterinarian remains a valid backend shape: ' || outcome);
end $$;

-- ---------------------------------------------------------------------------
-- Input validation after authorization (BR-13, BR-17, BR-22.4, Notes 12, 13)
-- ---------------------------------------------------------------------------
do $$ declare invalid_role text := '22023:INVALID_ROLE_SCOPE:Organization Invitation role or scope is invalid';
    invalid_clinic text := '22023:INVALID_CLINIC:Organization Invitation Clinic is invalid';
    invalid_email text := '22023:INVALID_RECIPIENT:Organization Invitation recipient email is invalid';
    before_count bigint := (select count(*) from public.organization_invitations); email text; begin
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'owner.try@example.test', 'OWNER', 'ORGANIZATION') = invalid_role
        and pg_temp.invite(2, pg_temp.id(3, 1), 'owner.try@example.test', 'OWNER', 'CLINIC', pg_temp.id(4, 1)) = invalid_role,
        'OWNER rejected as invalid role/scope');
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'vet.clinic@example.test', 'VETERINARIAN', 'CLINIC', pg_temp.id(4, 1)) = invalid_role,
        'Clinic-scoped VETERINARIAN rejected');
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'MANAGER', 'ORGANIZATION') = invalid_role
        and pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', null, 'ORGANIZATION') = invalid_role
        and pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'administrator', 'ORGANIZATION') = invalid_role
        and pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'RECEPTIONIST', 'REGION') = invalid_role
        and pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'RECEPTIONIST', null) = invalid_role,
        'Unknown role or scope rejected');
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'RECEPTIONIST', 'ORGANIZATION', pg_temp.id(4, 1)) = invalid_role
        and pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'RECEPTIONIST', 'CLINIC', null) = invalid_role,
        'Clinic id only and always for Clinic scope');
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 3)) = invalid_clinic
        and pg_temp.invite(1, pg_temp.id(3, 1), 'r@example.test', 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 99)) = invalid_clinic,
        'Clinic of another Organization and nonexistent Clinic rejected identically');
    foreach email in array array['', E' \t ', 'no-at-sign', 'two@at@example.test', 'a b@example.test', '@example.test', 'local@'] loop
        perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), email, 'RECEPTIONIST', 'ORGANIZATION') = invalid_email,
            'Invalid recipient address rejected: ' || email);
    end loop;
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), null, 'RECEPTIONIST', 'ORGANIZATION') = invalid_email
        and pg_temp.invite(1, pg_temp.id(3, 1), repeat('a', 310) || '@example.test', 'RECEPTIONIST', 'ORGANIZATION') = invalid_email,
        'Missing or oversized recipient address rejected');
    perform pg_temp.assert_true((select count(*) from public.organization_invitations) = before_count,
        'Rejected inputs create nothing');
end $$;

-- The create command takes no client expiry and bounds the trusted instant.
do $$ declare t timestamptz := statement_timestamp(); bad text := '22023:CREATION_INSTANT_INVALID:Organization Invitation creation instant is invalid';
    before_count bigint := (select count(*) from public.organization_invitations); begin
    perform pg_temp.assert_true(not exists (select 1 from pg_proc p, unnest(p.proargnames) arg
        where p.oid = 'public.create_staff_organization_invitation_with_communication(uuid,uuid,text,text,text,uuid,timestamptz,bytea,integer,bytea,bytea)'::regprocedure
          and (arg like '%expir%' or arg like '%recipient_user%' or arg like '%responsibilities%')),
        'Product command accepts no expiry, recipient User, or responsibility array');
    perform pg_temp.assert_true(pg_temp.invite_full(1, pg_temp.id(3, 1), 'future@example.test', 'RECEPTIONIST', 'ORGANIZATION', null,
            pg_temp.bytes(32), date_trunc('milliseconds', t) + interval '1 day') = bad,
        'Future creation instant rejected');
    perform pg_temp.assert_true(pg_temp.invite_full(1, pg_temp.id(3, 1), 'stale@example.test', 'RECEPTIONIST', 'ORGANIZATION', null,
            pg_temp.bytes(32), date_trunc('milliseconds', t) - interval '2 minutes') = bad
        and pg_temp.invite_full(1, pg_temp.id(3, 1), 'stale@example.test', 'RECEPTIONIST', 'ORGANIZATION', null,
            pg_temp.bytes(32), date_trunc('milliseconds', t) - interval '7 days') = bad,
        'Stale creation instant rejected');
    perform pg_temp.assert_true(pg_temp.invite_full(1, pg_temp.id(3, 1), 'micro@example.test', 'RECEPTIONIST', 'ORGANIZATION', null,
            pg_temp.bytes(32), date_trunc('milliseconds', t) - interval '1 millisecond' + interval '1 microsecond') = bad,
        'Sub-millisecond creation instant rejected');
    perform pg_temp.assert_true(pg_temp.invite_full(1, pg_temp.id(3, 1), 'digest@example.test', 'RECEPTIONIST', 'ORGANIZATION', null,
            pg_temp.bytes(16), null) = '22023:CREDENTIAL_INVALID:Organization Invitation credential material is invalid',
        'Malformed credential digest rejected');
    perform pg_temp.assert_true((select count(*) from public.organization_invitations) = before_count,
        'Rejected trusted instants create nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Duplicate / former / active Member (BR-19, BR-20, Notes 16–20)
-- ---------------------------------------------------------------------------
do $$ declare conflict text := '23505:PENDING_INVITATION_EXISTS:An equivalent pending Organization Invitation already exists';
    original text := pg_temp.invitation_state((select id from b1_created where label = 'org_recep'));
    before_count bigint := (select count(*) from public.organization_invitations); outcome text; begin
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'org.recep@example.test', 'RECEPTIONIST', 'ORGANIZATION') = conflict,
        'Exact duplicate pending Invitation conflicts');
    perform pg_temp.assert_true(pg_temp.invite(2, pg_temp.id(3, 1), E' ORG.Recep@EXAMPLE.test\n', 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1)) = conflict,
        'Normalized duplicate conflicts regardless of role/scope');
    perform pg_temp.assert_true((select count(*) from public.organization_invitations) = before_count
        and pg_temp.invitation_state((select id from b1_created where label = 'org_recep')) = original,
        'Conflict creates nothing and leaves the pending Invitation unchanged');
    outcome := pg_temp.invite(10, pg_temp.id(3, 2), 'org.recep@example.test', 'RECEPTIONIST', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Same address may be pending in another Organization: ' || outcome);
    insert into b1_created values ('b_same_address', outcome::uuid);
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), 'FORMER@example.test', 'RECEPTIONIST', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Former Member may be invited again: ' || outcome);
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), ' active.member@EXAMPLE.test', 'ADMINISTRATOR', 'ORGANIZATION')
        = '23505:ACTIVE_MEMBER:The recipient address belongs to an active Member',
        'Address an active Member joined through is rejected');
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), 'expired@example.test', 'RECEPTIONIST', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Address of an expired Invitation may be invited again: ' || outcome);
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), 'rejected@example.test', 'RECEPTIONIST', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Address of a rejected Invitation may be invited again: ' || outcome);
end $$;

-- Active Member reached through another address: creation succeeds, the
-- (trusted, pre-B2) acceptance creates no second Membership, and the pending
-- Invitation remains revocable (BR-20, Note 20).
do $$ declare outcome text; digest bytea := pg_temp.bytes(32); memberships text := pg_temp.membership_state(); begin
    outcome := pg_temp.invite_full(1, pg_temp.id(3, 1), 'active.other@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, digest, null);
    perform pg_temp.assert_true(pg_temp.is_created(outcome), 'Active Member under another address is invitable: ' || outcome);
    perform pg_temp.assert_true(pg_temp.accept(14, outcome::uuid, digest) like '23505:%'
        and pg_temp.membership_state() = memberships, 'Already-a-Member acceptance creates no second Membership');
    perform pg_temp.assert_true(pg_temp.outcome_of(1, outcome::uuid) = 'REVOKED', 'Unaccepted Invitation of an active Member stays revocable');
end $$;

-- ---------------------------------------------------------------------------
-- Staff read integration (SPEC-ORG-009 BR-7) and Organization isolation
-- ---------------------------------------------------------------------------
do $$ declare a uuid[] := pg_temp.pending_ids(pg_temp.id(3, 1)); b uuid[] := pg_temp.pending_ids(pg_temp.id(3, 2), 10);
    item jsonb; begin
    perform pg_temp.assert_true((select bool_and(id = any(a)) from b1_created where label <> 'b_same_address'),
        'Created Invitations appear as pending on re-read');
    perform pg_temp.assert_true(not ((select id from b1_created where label = 'b_same_address') = any(a))
        and (select id from b1_created where label = 'b_same_address') = any(b)
        and not exists (select 1 from b1_created where label <> 'b_same_address' and id = any(b)),
        'Pending Invitations are Organization-isolated');
    perform pg_temp.act(1);
    select value into item from jsonb_array_elements(public.get_organization_staff(pg_temp.id(3, 1)) -> 'pending_invitations')
    where value ->> 'invitation_id' = (select id from b1_created where label = 'clinic_admin')::text;
    perform pg_temp.assert_true(item -> 'responsibilities' = jsonb_build_array(jsonb_build_object('responsibility', 'ADMINISTRATOR',
            'scope_type', 'CLINIC', 'clinic', jsonb_build_object('clinic_id', pg_temp.id(4, 1), 'clinic_display_name', 'A Centro')))
        and (item ->> 'expires_at')::timestamptz = (item ->> 'created_at')::timestamptz + interval '7 days'
        and item::text not like '%digest%' and item::text not like '%secret%',
        'Staff read reports the single role/scope and backend instants, never the credential');
end $$;

-- ---------------------------------------------------------------------------
-- Revoke (SPEC-ORG-010)
-- ---------------------------------------------------------------------------
do $$ declare target uuid := (select id from b1_created where label = 'org_admin'); result jsonb; inv record;
    t timestamptz := statement_timestamp(); communications text := pg_temp.communication_state();
    memberships text := pg_temp.membership_state(); other text := pg_temp.invitation_state((select id from b1_created where label = 'org_recep'));
    roles text := (select md5(jsonb_agg(to_jsonb(r))::text) from public.organization_invitation_responsibilities r where r.invitation_id = target);
    digest bytea := (select acceptance_secret_digest from public.organization_invitations where id = target); begin
    result := pg_temp.revoke_json(2, target);
    perform pg_temp.assert_true(result = jsonb_build_object('invitation_id', target, 'outcome', 'REVOKED'),
        'Pending Invitation revoked with the exact outcome envelope');
    select * into inv from public.organization_invitations where id = target;
    perform pg_temp.assert_true(inv.revoked_at = t and inv.revoked_by_user_id = pg_temp.id(2, 2) and inv.rejected_at is null,
        'Revocation records the authoritative instant and the revoking User');
    perform pg_temp.assert_true(inv.acceptance_secret_digest = digest, 'Revocation retains the acceptance digest');
    perform pg_temp.assert_true((select md5(jsonb_agg(to_jsonb(r))::text) from public.organization_invitation_responsibilities r
            where r.invitation_id = target) = roles and inv.expires_at = inv.created_at + interval '168 hours',
        'Revocation preserves intended responsibilities and validity as history');
    perform pg_temp.assert_true(pg_temp.communication_state() = communications,
        'Revocation creates no Communication and rewrites none');
    perform pg_temp.assert_true(pg_temp.membership_state() = memberships
        and pg_temp.invitation_state((select id from b1_created where label = 'org_recep')) = other,
        'Revocation changes no Membership, Grant, or other Invitation');
    perform pg_temp.assert_true(not (target = any(pg_temp.pending_ids(pg_temp.id(3, 1)))), 'Revoked Invitation leaves pending staff state');
end $$;
do $$ declare target uuid := (select id from b1_created where label = 'org_admin'); before text := pg_temp.invitation_state(target); begin
    perform pg_temp.assert_true(pg_temp.revoke_json(1, target) = jsonb_build_object('invitation_id', target, 'outcome', 'ALREADY_REVOKED')
        and pg_temp.revoke_json(2, target) ->> 'outcome' = 'ALREADY_REVOKED',
        'Retry by any authorized User returns ALREADY_REVOKED');
    perform pg_temp.assert_true(pg_temp.invitation_state(target) = before, 'Retry keeps the original revocation facts');
end $$;
do $$ declare outcome text; begin
    outcome := pg_temp.invite(1, pg_temp.id(3, 1), 'new.admin@example.test', 'RECEPTIONIST', 'ORGANIZATION');
    perform pg_temp.assert_true(pg_temp.is_created(outcome) and outcome::uuid <> (select id from b1_created where label = 'org_admin')
        and (select expires_at = created_at + interval '168 hours' and acceptance_secret_digest is distinct from
                (select acceptance_secret_digest from public.organization_invitations where id = (select id from b1_created where label = 'org_admin'))
            from public.organization_invitations where id = outcome::uuid),
        'A new Invitation with its own expiry and secret may follow revocation: ' || outcome);
end $$;

-- Terminal states are reported, never transformed (BR-7).
do $$ declare accepted text := pg_temp.invitation_state(pg_temp.id(7, 1)); expired text := pg_temp.invitation_state(pg_temp.id(7, 3));
    rejected text := pg_temp.invitation_state(pg_temp.id(7, 4)); memberships text := pg_temp.membership_state(); begin
    perform pg_temp.assert_true(pg_temp.revoke_json(1, pg_temp.id(7, 1)) = jsonb_build_object('invitation_id', pg_temp.id(7, 1), 'outcome', 'ACCEPTED')
        and pg_temp.invitation_state(pg_temp.id(7, 1)) = accepted and pg_temp.membership_state() = memberships,
        'Accepted Invitation reported ACCEPTED and unchanged');
    perform pg_temp.assert_true(pg_temp.outcome_of(2, pg_temp.id(7, 2)) = 'ACCEPTED', 'Invitation of an ended Membership remains ACCEPTED');
    perform pg_temp.assert_true(pg_temp.outcome_of(1, pg_temp.id(7, 3)) = 'EXPIRED' and pg_temp.invitation_state(pg_temp.id(7, 3)) = expired,
        'Expired Invitation reported EXPIRED and unchanged');
    perform pg_temp.assert_true(pg_temp.outcome_of(1, pg_temp.id(7, 4)) = 'REJECTED' and pg_temp.invitation_state(pg_temp.id(7, 4)) = rejected,
        'Rejected Invitation reported REJECTED and unchanged');
end $$;

-- Expiry boundary at the revocation instant (fixture update and the call share
-- this statement's statement_timestamp()).
do $$ declare t timestamptz := statement_timestamp(); before text; begin
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t where id = pg_temp.id(7, 6);
    execute 'set local session_replication_role = origin';
    before := pg_temp.invitation_state(pg_temp.id(7, 6));
    perform pg_temp.assert_true(pg_temp.outcome_of(1, pg_temp.id(7, 6)) = 'EXPIRED' and pg_temp.invitation_state(pg_temp.id(7, 6)) = before,
        'Invitation expiring exactly at the revocation instant is EXPIRED and unchanged');
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t + interval '1 microsecond' where id = pg_temp.id(7, 6);
    execute 'set local session_replication_role = origin';
    perform pg_temp.assert_true(pg_temp.outcome_of(1, pg_temp.id(7, 6)) = 'REVOKED',
        'Invitation expiring just after the revocation instant is REVOKED');
    perform pg_temp.assert_true((select revoked_at = t from public.organization_invitations where id = pg_temp.id(7, 6)),
        'Boundary revocation records the revocation instant');
end $$;

-- Fail-closed revoke authorization (BR-2, BR-3, Notes 7–9).
do $$ declare n integer; denied text := '42501:Organization Invitation unavailable'; pending text := pg_temp.invitation_state(pg_temp.id(7, 7)); begin
    foreach n in array array[3, 4, 5, 6, 7, 9, 10, 15] loop
        perform pg_temp.assert_true(pg_temp.revoke(n, pg_temp.id(7, 7)) = denied
            and pg_temp.revoke(n, pg_temp.id(7, 1)) = denied and pg_temp.revoke(n, pg_temp.id(7, 3)) = denied
            and pg_temp.revoke(n, pg_temp.id(7, 99)) = denied, 'Denied revoker ' || n);
    end loop;
    perform pg_temp.assert_true(pg_temp.invitation_state(pg_temp.id(7, 7)) = pending,
        'Inviter who lost capability cannot revoke; Invitation remains pending');
    perform pg_temp.assert_true(pg_temp.revoke(1, pg_temp.id(7, 5)) = denied and pg_temp.revoke(10, pg_temp.id(7, 7)) = denied,
        'Cross-Organization revocation denied');
    perform pg_temp.assert_true(pg_temp.revoke(1, pg_temp.id(7, 99)) = denied and pg_temp.revoke(1, null) = denied,
        'Unknown Invitation indistinguishable from inaccessible');
    perform pg_temp.assert_true(pg_temp.revoke(0, pg_temp.id(7, 7)) = '28000:Authentication is required'
        and pg_temp.revoke(16, pg_temp.id(7, 7)) = '28000:No coherent domain User exists for the authenticated subject',
        'Unauthenticated revoker');
    perform pg_temp.assert_true(pg_temp.outcome_of(10, pg_temp.id(7, 5)) = 'REVOKED' and pg_temp.outcome_of(1, pg_temp.id(7, 7)) = 'REVOKED',
        'Current capability holders revoke in their own Organization');
end $$;

-- Real authenticated role (mobile path).
create temporary table b1_role_probe on commit drop as
select (select id from b1_created where label = 'clinic_recep') id;
grant select on b1_role_probe to authenticated;
select pg_temp.act(2);
set local role authenticated;
select pg_temp.assert_true(public.revoke_organization_invitation((select id from b1_role_probe)) ->> 'outcome' = 'REVOKED',
    'Authenticated role executes the revoke operation');
reset role;

-- ---------------------------------------------------------------------------
-- Communication suppression (BR-9, SPEC-COM-001 BR-45/BR-46)
-- ---------------------------------------------------------------------------
do $$ declare ready_inv uuid; claimed_inv uuid; started_inv uuid; delivered_inv uuid; job record; lease uuid; context jsonb;
    history text; communications bigint; begin
    ready_inv := pg_temp.invite(1, pg_temp.id(3, 1), 'suppress.ready@example.test', 'RECEPTIONIST', 'ORGANIZATION')::uuid;
    claimed_inv := pg_temp.invite(1, pg_temp.id(3, 1), 'suppress.claimed@example.test', 'RECEPTIONIST', 'ORGANIZATION')::uuid;
    started_inv := pg_temp.invite(1, pg_temp.id(3, 1), 'suppress.context@example.test', 'RECEPTIONIST', 'ORGANIZATION')::uuid;
    delivered_inv := pg_temp.invite(1, pg_temp.id(3, 1), 'delivered@example.test', 'RECEPTIONIST', 'ORGANIZATION')::uuid;
    perform public.materialize_communication_delivery_jobs();
    perform pg_temp.assert_true((select count(*) from public.communication_delivery_jobs j join public.transactional_communications c
        on c.id = j.communication_id where c.organization_invitation_id in (ready_inv, claimed_inv, started_inv, delivered_inv)
        and j.state = 'READY' and j.channel = 'EMAIL') = 4, 'Pending Invitations are eligible for email delivery');

    -- Undelivered email after revocation is never claimed.
    perform pg_temp.assert_true(pg_temp.outcome_of(1, ready_inv) = 'REVOKED', 'Revoke READY-delivery Invitation');
    -- Claimed, and claimed-with-context, before revocation.
    perform count(*) from public.claim_communication_delivery_jobs(100, 120);
    perform pg_temp.assert_true((select j.state = 'SUPPRESSED' and j.last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE'
            and j.submission_count = 0 from public.communication_delivery_jobs j join public.transactional_communications c
            on c.id = j.communication_id where c.organization_invitation_id = ready_inv),
        'Undelivered email of a revoked Invitation is suppressed, never claimed');
    select j.* into job from public.communication_delivery_jobs j join public.transactional_communications c
        on c.id = j.communication_id where c.organization_invitation_id = claimed_inv;
    perform pg_temp.assert_true(job.state = 'CLAIMED', 'Live claim before revocation');
    perform pg_temp.assert_true(pg_temp.outcome_of(1, claimed_inv) = 'REVOKED', 'Revoke claimed-delivery Invitation');
    context := public.get_communication_delivery_context(job.id, job.lease_token);
    perform pg_temp.assert_true(context is null and (select state = 'SUPPRESSED' from public.communication_delivery_jobs where id = job.id),
        'Claimed email of a revoked Invitation is suppressed before its envelope is released');

    select j.* into job from public.communication_delivery_jobs j join public.transactional_communications c
        on c.id = j.communication_id where c.organization_invitation_id = started_inv;
    context := public.get_communication_delivery_context(job.id, job.lease_token);
    perform pg_temp.assert_true(context is not null, 'Envelope released to the dispatcher while pending');
    perform pg_temp.assert_true(pg_temp.outcome_of(1, started_inv) = 'REVOKED', 'Revoke Invitation between context and submission');
    perform pg_temp.assert_true(public.mark_communication_delivery_submission_started(job.id, job.lease_token) = 'SUPPRESSED',
        'Provider handoff is refused once the Invitation is revoked');
    perform pg_temp.assert_true((select state = 'SUPPRESSED' and submission_count = 0 and first_submitted_at is null
             from public.communication_delivery_jobs where id = job.id)
        and not exists (select 1 from public.communication_delivery_attempts where delivery_job_id = job.id),
        'Refused handoff records no submission or Attempt');

    -- Already accepted by the provider: history is retained and not recalled.
    select j.* into job from public.communication_delivery_jobs j join public.transactional_communications c
        on c.id = j.communication_id where c.organization_invitation_id = delivered_inv;
    perform public.get_communication_delivery_context(job.id, job.lease_token);
    perform pg_temp.assert_true(public.mark_communication_delivery_submission_started(job.id, job.lease_token) = 'STARTED',
        'Pending Invitation email handed to the provider');
    perform public.complete_communication_delivery_job(job.id, job.lease_token, 'ACCEPTED', 'provider-message-b1', 'sent', null, 60);
    history := pg_temp.communication_state();
    communications := (select count(*) from public.transactional_communications);
    perform pg_temp.assert_true(pg_temp.outcome_of(1, delivered_inv) = 'REVOKED', 'Revoke already-delivered Invitation');
    perform pg_temp.assert_true(pg_temp.communication_state() = history
        and (select secret_consumed_at is not null and secret_ciphertext is null from public.transactional_communications
             where organization_invitation_id = delivered_inv),
        'Delivered Invitation Communication history is retained unchanged');
    perform pg_temp.assert_true((select count(*) from public.transactional_communications) = communications,
        'Revoking a delivered Invitation creates no Communication');
end $$;

-- ---------------------------------------------------------------------------
-- Serialization (BR-11, SPEC-ORG-002 Note 25): lock evidence on fresh rows,
-- plus both sequential orders of each race through the real operations. The
-- multi-session races are pinned by run_staff_invitation_concurrency.py.
-- ---------------------------------------------------------------------------
set local session_replication_role = replica;
insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, 5), 'Lock probe create'),
    (pg_temp.id(3, 6), 'Lock probe revoke');
insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    (pg_temp.id(5, 50), pg_temp.id(3, 5), pg_temp.id(2, 1), '2020-01-01Z'), (pg_temp.id(5, 51), pg_temp.id(3, 6), pg_temp.id(2, 1), '2020-01-01Z');
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id) values
    (pg_temp.id(6, 50), pg_temp.id(5, 50), 'OWNER', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 51), pg_temp.id(5, 51), 'OWNER', 'ORGANIZATION', '2020-01-01Z', pg_temp.id(2, 1));
insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email, created_at, expires_at,
    acceptance_secret_digest, revoked_at, revoked_by_user_id) values
    (pg_temp.id(7, 60), pg_temp.id(3, 6), pg_temp.id(2, 1), 'probe.revoked@example.test', statement_timestamp() - interval '1 day',
        statement_timestamp() + interval '6 days', decode(repeat('cd', 32), 'hex'), statement_timestamp() - interval '1 hour', pg_temp.id(2, 1)),
    (pg_temp.id(7, 61), pg_temp.id(3, 6), pg_temp.id(2, 1), 'probe.handoff@example.test', statement_timestamp() - interval '1 day',
        statement_timestamp() + interval '6 days', decode(repeat('ce', 32), 'hex'), null, null);
insert into public.transactional_communications (id, communication_type, recipient_email, organization_invitation_id,
    secret_envelope_version, secret_key_version, secret_algorithm, secret_aad_context, secret_nonce, secret_ciphertext)
values (pg_temp.id(11, 61), 'ORGANIZATION_INVITATION', 'probe.handoff@example.test', pg_temp.id(7, 61), 1, 1, 'AES-256-GCM',
    public.build_invitation_secret_aad('organization', 'probe.handoff@example.test', statement_timestamp() + interval '6 days',
        decode(repeat('ce', 32), 'hex')), pg_temp.bytes(12), pg_temp.bytes(32));
insert into public.communication_delivery_jobs (id, communication_id, channel, provider, destination_key, destination_snapshot,
    state, lease_token, lease_expires_at) values
    (pg_temp.id(12, 61), pg_temp.id(11, 61), 'EMAIL', 'RESEND', 'EMAIL:probe.handoff@example.test', 'probe.handoff@example.test',
        'CLAIMED', pg_temp.id(13, 61), clock_timestamp() + interval '5 minutes');
set local session_replication_role = origin;
-- Exact row-lock modes (an FK insert alone key-share locks the Organization).
-- The inspection extension exists only inside this rolled-back transaction.
create extension pgrowlocks with schema extensions;
create function pg_temp.lock_modes(relation regclass, row_id uuid) returns text[] language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return coalesce(result, '{}');
end $$;
create function pg_temp.locked(relation regclass, row_id uuid, mode text default null) returns boolean language sql as $$
    select case when mode is null then cardinality(pg_temp.lock_modes(relation, row_id)) > 0
        else mode = any(pg_temp.lock_modes(relation, row_id)) end
$$;
select pg_temp.assert_true(not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 5))
    and not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 6))
    and not pg_temp.locked('public.organization_invitations', pg_temp.id(7, 60))
    and not pg_temp.locked('public.organization_invitations', pg_temp.id(7, 61)), 'Fresh lock probes are unlocked');
select public.create_staff_organization_invitation_with_communication(pg_temp.subject(1), pg_temp.id(3, 5), 'probe.create@example.test',
    'RECEPTIONIST', 'ORGANIZATION', null, public.authorize_organization_invitation_creation(pg_temp.subject(1), pg_temp.id(3, 5)),
    pg_temp.bytes(32), 1, pg_temp.bytes(12), pg_temp.bytes(32)) is not null;
select pg_temp.assert_true(pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 5), 'For Update'),
    'Creation serializes on the Organization row');
select pg_temp.assert_true(pg_temp.outcome_of(1, pg_temp.id(7, 60)) = 'ALREADY_REVOKED', 'Lock probe revoke is a no-op');
select pg_temp.assert_true(pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 6), 'For Update')
    and pg_temp.locked('public.organization_invitations', pg_temp.id(7, 60), 'For Update'),
    'Revocation takes the Organization then the Invitation lock even when it writes nothing');
select pg_temp.assert_true(not pg_temp.locked('public.organization_invitations', pg_temp.id(7, 61)), 'Handoff probe Invitation unlocked');
select pg_temp.assert_true(public.mark_communication_delivery_submission_started(pg_temp.id(12, 61), pg_temp.id(13, 61)) = 'STARTED',
    'Handoff probe starts');
select pg_temp.assert_true(pg_temp.locked('public.organization_invitations', pg_temp.id(7, 61), 'For Share'),
    'Provider handoff share-locks its Organization Invitation');

-- Sequential orders of each race.
do $$ declare first_id uuid; digest bytea := pg_temp.bytes(32); accept_first uuid; memberships text; result text; begin
    first_id := pg_temp.invite_full(1, pg_temp.id(3, 1), 'race.revoke-accept@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, digest, null)::uuid;
    perform pg_temp.assert_true(pg_temp.outcome_of(1, first_id) = 'REVOKED', 'Revoke first');
    memberships := pg_temp.membership_state();
    result := pg_temp.accept(11, first_id, digest);
    perform pg_temp.assert_true(result = '23514:Organization Invitation is no longer pending' and pg_temp.membership_state() = memberships,
        'Acceptance after revocation fails even with the valid secret');
    accept_first := pg_temp.invite_full(1, pg_temp.id(3, 1), 'race.accept-revoke@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, digest, null)::uuid;
    result := pg_temp.accept(12, accept_first, digest);
    perform pg_temp.assert_true(pg_temp.is_created(result), 'Accept first: ' || result);
    memberships := pg_temp.membership_state();
    perform pg_temp.assert_true(pg_temp.outcome_of(2, accept_first) = 'ACCEPTED' and pg_temp.membership_state() = memberships
        and (select revoked_at is null from public.organization_invitations where id = accept_first),
        'Revocation after acceptance reports ACCEPTED and leaves the Membership');
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    perform pg_temp.assert_true((select count(*) from public.organization_memberships where originating_invitation_id = accept_first) = 1
        and (select count(*) from public.organization_responsibility_grants g join public.organization_invitation_responsibilities r
             on r.id = g.originating_invitation_responsibility_id where r.invitation_id = accept_first) = 1,
        'One Membership and one Grant from the accepted Invitation');
    perform pg_temp.assert_true(pg_temp.invite(1, pg_temp.id(3, 1), 'race.duplicate@example.test', 'RECEPTIONIST', 'ORGANIZATION') ~ '^[0-9a-f-]{36}$'
        and pg_temp.invite(2, pg_temp.id(3, 1), 'Race.Duplicate@example.test', 'RECEPTIONIST', 'ORGANIZATION') like '23505:PENDING_INVITATION_EXISTS:%',
        'Serialized duplicate creation: second creation conflicts');
    perform pg_temp.assert_true((select count(*) from public.organization_invitations where recipient_email_normalized = 'race.duplicate@example.test') = 1
        and (select count(*) from public.transactional_communications where recipient_email ilike 'race.duplicate@example.test') = 1,
        'Serialized duplicate creation leaves exactly one pending Invitation and Communication');
end $$;

-- Every Invitation created here satisfies the deferred integrity triggers.
set constraints all immediate;
set constraints all deferred;

select pg_temp.assert_true((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
    where oid = 'public.revoke_organization_invitation(uuid)'::regprocedure)
    and (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
    where oid = 'public.create_staff_organization_invitation_with_communication(uuid,uuid,text,text,text,uuid,timestamptz,bytea,integer,bytea,bytea)'::regprocedure)
    and (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
    where oid = 'public.authorize_organization_invitation_creation(uuid,uuid)'::regprocedure),
    'SECURITY DEFINER with empty search_path');
select pg_temp.assert_true(has_function_privilege('authenticated', 'public.revoke_organization_invitation(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.revoke_organization_invitation(uuid)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.revoke_organization_invitation(uuid)', 'EXECUTE'),
    'Revoke is authenticated-only');
select pg_temp.assert_true((select bool_and(has_function_privilege('service_role', f, 'EXECUTE')
        and not has_function_privilege('authenticated', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE'))
    from unnest(array['public.authorize_organization_invitation_creation(uuid,uuid)',
        'public.create_staff_organization_invitation_with_communication(uuid,uuid,text,text,text,uuid,timestamptz,bytea,integer,bytea,bytea)']) f)
    and not has_function_privilege('service_role', 'public.assert_organization_invitation_authority(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.assert_organization_invitation_authority(uuid,uuid)', 'EXECUTE'),
    'Invite commands are service-role only; the authority helper is private');
select pg_temp.assert_true((select prorettype = 'uuid'::regtype from pg_proc
    where oid = 'public.create_staff_organization_invitation_with_communication(uuid,uuid,text,text,text,uuid,timestamptz,bytea,integer,bytea,bytea)'::regprocedure),
    'Create returns only the Invitation reference');
select pg_temp.assert_true(has_function_privilege('service_role',
    'public.create_scoped_organization_invitation_with_communication(uuid,uuid,uuid,text,jsonb,timestamptz,bytea,integer,bytea,bytea)', 'EXECUTE'),
    'Trusted legacy Invitation command remains available');
rollback;

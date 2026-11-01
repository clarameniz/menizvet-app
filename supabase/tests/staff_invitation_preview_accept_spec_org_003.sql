-- Staff Phase 1 Slice B2: SPEC-ORG-003 §10–§13 (BR-18–BR-25) preview and
-- authenticated acceptance, with SPEC-ORG-002 BR-20, SPEC-ORG-005, SPEC-ORG-007,
-- SPEC-ORG-009 and SPEC-ORG-010 integration.
-- Isolated LOCAL superuser only; fixtures, helper substitutions and assertions
-- are rollback-only. Behaviour is exercised through the real operations; the
-- Invitations under test are created by the real B1 commands (with the digest
-- the Communications Edge would store: SHA-256 of the UTF-8 secret) or, for
-- legacy/terminal shapes the product commands cannot produce, inserted
-- directly. Multi-session races are pinned by
-- run_staff_invitation_acceptance_concurrency.py.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0280000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.subject(n integer) returns uuid language sql immutable as $$
    select case when n = 0 then null else pg_temp.id(1, n) end
$$;
create function pg_temp.digest(secret text) returns bytea language sql immutable as $$
    select sha256(convert_to(secret, 'UTF8'))
$$;
create function pg_temp.bytes(n integer) returns bytea language sql volatile as $$
    select decode(substr(md5(random()::text) || md5(random()::text), 1, 2 * n), 'hex')
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(pg_temp.subject(n)::text, ''), true)
$$;
create function pg_temp.failure(failure_hint text, failure_detail text, message text) returns text
language sql immutable as $$
    select coalesce(nullif(failure_hint, ''), '-') || ':' || coalesce(nullif(failure_detail, ''), '-') || ':' || message
$$;
-- B1's two trusted commands exactly as the Edge route calls them, with the
-- digest of a known secret (the database never sees the secret at creation).
create function pg_temp.invite(email text, role text, scope text, clinic uuid, secret text,
    inviter integer default 1, organization uuid default null) returns uuid language plpgsql as $$
declare instant timestamptz; target uuid := coalesce(organization, pg_temp.id(3, 1)); begin
    instant := public.authorize_organization_invitation_creation(pg_temp.subject(inviter), target);
    return public.create_staff_organization_invitation_with_communication(pg_temp.subject(inviter), target,
        email, role, scope, clinic, instant, pg_temp.digest(secret), 1, pg_temp.bytes(12), pg_temp.bytes(32));
end $$;
create function pg_temp.preview(actor integer, invitation uuid, secret text) returns text language plpgsql as $$
declare failure_hint text; failure_detail text; begin
    perform pg_temp.act(actor);
    return public.preview_organization_invitation(invitation, secret)::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint, failure_detail = pg_exception_detail;
    return sqlstate || ':' || pg_temp.failure(failure_hint, failure_detail, sqlerrm);
end $$;
-- Errors become {"error": ...} so a faulty operation fails a named assertion.
create function pg_temp.preview_json(actor integer, invitation uuid, secret text) returns jsonb language sql as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
    from pg_temp.preview(actor, invitation, secret) result
$$;
create function pg_temp.state_of(actor integer, invitation uuid, secret text) returns text language sql as $$
    select coalesce(pg_temp.preview_json(actor, invitation, secret) ->> 'state',
        pg_temp.preview_json(actor, invitation, secret) ->> 'error')
$$;
-- Deferred integrity triggers fire inside the call, as at commit.
create function pg_temp.accept(actor integer, invitation uuid, secret text) returns text language plpgsql as $$
declare result jsonb; failure_hint text; failure_detail text; begin
    perform pg_temp.act(actor);
    result := public.accept_my_organization_invitation(invitation, secret);
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return result::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint, failure_detail = pg_exception_detail;
    return sqlstate || ':' || pg_temp.failure(failure_hint, failure_detail, sqlerrm);
end $$;
create function pg_temp.accept_json(actor integer, invitation uuid, secret text) returns jsonb language sql as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
    from pg_temp.accept(actor, invitation, secret) result
$$;
create function pg_temp.world_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(i) order by i.id)::text from public.organization_invitations i), '')
        || coalesce((select jsonb_agg(to_jsonb(r) order by r.id)::text from public.organization_invitation_responsibilities r), '')
        || coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), '')
        || coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a), '')
        || coalesce((select jsonb_agg(to_jsonb(p) order by p.id)::text from public.veterinarian_professional_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(u) order by u.id)::text from public.users u), ''))
$$;
create function pg_temp.communication_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.transactional_communications c), '')
        || coalesce((select jsonb_agg(to_jsonb(j) order by j.id)::text from public.communication_delivery_jobs j), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.communication_delivery_attempts a), ''))
$$;
create function pg_temp.accepted_membership(invitation uuid) returns public.organization_memberships language sql as $$
    select m from public.organization_memberships m where m.originating_invitation_id = invitation
$$;
create temporary table b2_invitation (label text primary key, id uuid not null, secret text not null) on commit drop;
create function pg_temp.inv(name text) returns uuid language sql as $$ select id from b2_invitation where label = name $$;
create function pg_temp.secret(name text) returns text language sql as $$ select secret from b2_invitation where label = name $$;

set local session_replication_role = replica;
-- Actors (Auth subject n <-> domain User n): 1 Owner A; 2 Owner B; 3 former
-- Administrator A (inviter who left); 10 Carlos (auth email equals the invited
-- address up to case/space); 11 Carlos on another verified address; 12 Laura;
-- 13 unverified; 14 active independent Member of A; 15 former Member of A;
-- 16 Member of B only; 17 authenticated subject without a domain User;
-- 20–31 fresh acceptors.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n),
    case n when 10 then '  Carlos.WORK@example.test ' when 11 then 'carlos.personal@example.test'
        when 12 then 'laura@example.test' else 'user-' || n || '@example.test' end,
    case when n = 13 then null else '2020-01-01Z'::timestamptz end
from unnest(array[1, 2, 3, 10, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]) n;
insert into public.users (id)
select pg_temp.id(2, n) from unnest(array[1, 2, 3, 10, 11, 12, 13, 14, 15, 16, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n)
from unnest(array[1, 2, 3, 10, 11, 12, 13, 14, 15, 16, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Animalia Group'), (pg_temp.id(3, 2), 'VetCare Group');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 1)), (pg_temp.id(4, 3), pg_temp.id(3, 2));
insert into public.clinic_public_profiles (clinic_id, display_name) values
    (pg_temp.id(4, 1), 'A Centro'), (pg_temp.id(4, 3), 'B Norte');
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n in (2, 16) then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z',
    case when n in (3, 15) then '2021-01-01Z'::timestamptz end, case when n in (3, 15) then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 14, 15, 16]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start,
    effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case when n in (1, 2) then 'OWNER' when n = 3 then 'ADMINISTRATOR' else 'RECEPTIONIST' end, 'ORGANIZATION',
    '2020-01-01Z', case when n in (3, 15) then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n in (3, 15) then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 14, 15, 16]) n;
-- Legacy/terminal Invitation shapes the product commands cannot create:
-- 50 expired, 51 rejected, 52 bound to Laura, 53 Clinic of another
-- Organization (responsibility no longer valid), 54 Organization-scoped
-- VETERINARIAN, 55 two responsibilities, 56 bound to acceptor 26, 57 created by
-- the inviter who later left, 58 expiry boundary, 59 two responsibilities for
-- the injected Grant failure.
insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_user_id, recipient_email,
    created_at, expires_at, acceptance_secret_digest, rejected_at, rejected_by_user_id)
select pg_temp.id(7, n), pg_temp.id(3, 1), pg_temp.id(2, case when n = 57 then 3 else 1 end),
    case n when 52 then pg_temp.id(2, 12) when 56 then pg_temp.id(2, 26) end,
    'legacy-' || n || '@example.test',
    statement_timestamp() - interval '10 days',
    case when n = 50 then statement_timestamp() - interval '3 days' else statement_timestamp() + interval '6 days' end,
    pg_temp.digest('legacy-secret-' || n),
    case when n = 51 then statement_timestamp() - interval '1 hour' end,
    case when n = 51 then pg_temp.id(2, 12) end
from generate_series(50, 59) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id)
select pg_temp.id(8, n), pg_temp.id(7, n),
    case when n = 54 then 'VETERINARIAN' when n in (55, 59) then 'ADMINISTRATOR' else 'RECEPTIONIST' end,
    case when n = 53 then 'CLINIC' else 'ORGANIZATION' end,
    case when n = 53 then pg_temp.id(4, 3) end
from generate_series(50, 59) n;
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id) values
    (pg_temp.id(8, 155), pg_temp.id(7, 55), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 1)),
    (pg_temp.id(8, 159), pg_temp.id(7, 59), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2));
insert into b2_invitation select 'legacy_' || n, pg_temp.id(7, n), 'legacy-secret-' || n from generate_series(50, 59) n;
set local session_replication_role = origin;

-- Product Invitations through the real B1 commands.
insert into b2_invitation values
    ('carlos', pg_temp.invite(' Carlos.Work@Example.Test ', 'RECEPTIONIST', 'ORGANIZATION', null,
        'Zk9yQ2FybG9zLW9ubHktYmFzZTY0dXJsLXNlY3JldF8x'), 'Zk9yQ2FybG9zLW9ubHktYmFzZTY0dXJsLXNlY3JldF8x'),
    ('other_address', pg_temp.invite('other.address@example.test', 'ADMINISTRATOR', 'ORGANIZATION', null, 'b3RoZXItYWRkcmVzcy1zZWNyZXQ'),
        'b3RoZXItYWRkcmVzcy1zZWNyZXQ'),
    ('org_admin', pg_temp.invite('org.admin@example.test', 'ADMINISTRATOR', 'ORGANIZATION', null, 'org-admin-secret'), 'org-admin-secret'),
    ('org_recep', pg_temp.invite('org.recep@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, 'org-recep-secret'), 'org-recep-secret'),
    ('clinic_admin', pg_temp.invite('clinic.admin@example.test', 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 1), 'clinic-admin-secret'),
        'clinic-admin-secret'),
    ('clinic_recep', pg_temp.invite('clinic.recep@example.test', 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 2), 'clinic-recep-secret'),
        'clinic-recep-secret'),
    ('revoked', pg_temp.invite('revoked@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, 'revoked-secret'), 'revoked-secret'),
    ('active_member', pg_temp.invite('active.other@example.test', 'ADMINISTRATOR', 'ORGANIZATION', null, 'active-member-secret'),
        'active-member-secret'),
    ('former_member', pg_temp.invite('former.member@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, 'former-member-secret'),
        'former-member-secret'),
    ('multi_org', pg_temp.invite('multi.org@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, 'multi-org-secret'), 'multi-org-secret'),
    ('unverified', pg_temp.invite('unverified@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, 'unverified-secret'), 'unverified-secret'),
    ('header', pg_temp.invite('header@example.test', 'RECEPTIONIST', 'ORGANIZATION', null, 'header-secret'), 'header-secret'),
    ('in_b', pg_temp.invite('in.b@example.test', 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 3), 'in-b-secret', 2, pg_temp.id(3, 2)),
        'in-b-secret');
set constraints all immediate;
set constraints all deferred;
select pg_temp.act(1);
select pg_temp.assert_true(public.revoke_organization_invitation(pg_temp.inv('revoked')) ->> 'outcome' = 'REVOKED',
    'Fixture: one Invitation revoked through SPEC-ORG-010');
select pg_temp.assert_true((select revoked_at is not null and acceptance_secret_digest = pg_temp.digest('revoked-secret')
    from public.organization_invitations where id = pg_temp.inv('revoked')), 'Fixture: revocation retained the digest');
create temporary table b2_baseline on commit drop as
select pg_temp.communication_state() communications, (select count(*) from public.transactional_communications) communication_count;

-- ---------------------------------------------------------------------------
-- Contract and ACL (BR-19, §10, §11, Note 18)
-- ---------------------------------------------------------------------------
select pg_temp.assert_true((select bool_and(prosecdef and proconfig @> array['search_path=""'])
    from pg_proc where oid in ('public.preview_organization_invitation(uuid,text)'::regprocedure,
        'public.accept_my_organization_invitation(uuid,text)'::regprocedure)),
    'SECURITY DEFINER with empty search_path');
select pg_temp.assert_true((select provolatile = 's' and prorettype = 'jsonb'::regtype
        and proargnames = array['p_invitation_id', 'p_acceptance_secret']
        from pg_proc where oid = 'public.preview_organization_invitation(uuid,text)'::regprocedure)
    and (select provolatile = 'v' and prorettype = 'jsonb'::regtype
        and proargnames = array['p_invitation_id', 'p_acceptance_secret']
        from pg_proc where oid = 'public.accept_my_organization_invitation(uuid,text)'::regprocedure)
    and (select count(*) from pg_proc where proname in ('preview_organization_invitation', 'accept_my_organization_invitation')) = 2,
    'Exact signatures: reference and secret only; no User, Membership, responsibility, Organization, Clinic or digest input');
select pg_temp.assert_true((select bool_and(has_function_privilege('authenticated', f, 'EXECUTE')
        and not has_function_privilege('anon', f, 'EXECUTE') and not has_function_privilege('service_role', f, 'EXECUTE'))
    from unnest(array['public.preview_organization_invitation(uuid,text)', 'public.accept_my_organization_invitation(uuid,text)']) f),
    'Preview and acceptance are executable by authenticated only');
select pg_temp.assert_true(has_function_privilege('service_role', 'public.accept_organization_invitation(uuid,uuid,bytea)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.accept_organization_invitation(uuid,uuid,bytea)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.accept_organization_invitation(uuid,uuid,bytea)', 'EXECUTE'),
    'Service-role acceptance command remains trusted-only; no client role executes it');
select pg_temp.assert_true((select bool_and(not has_function_privilege(r, f, 'EXECUTE'))
    from unnest(array['public.organization_invitation_responsibilities_are_acceptable(uuid,uuid)',
        'public.establish_membership_from_organization_invitation(uuid,uuid,uuid,uuid,timestamptz)',
        'public.mask_organization_invitation_recipient(text)']) f,
        unnest(array['anon', 'authenticated', 'service_role']) r),
    'Shared acceptance internals are private');

-- ---------------------------------------------------------------------------
-- Preview: authentication, then uniform failure before proof (BR-20, BR-22,
-- Notes 19, 20, 31)
-- ---------------------------------------------------------------------------
do $$ declare uniform text := '42501:-:-:Invitation unavailable'; before text := pg_temp.world_state();
    malformed text; target text; begin
    perform pg_temp.assert_true(pg_temp.preview(0, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '28000:-:-:Authentication is required'
        and pg_temp.preview(17, pg_temp.inv('carlos'), pg_temp.secret('carlos'))
            = '28000:-:-:No coherent domain User exists for the authenticated subject',
        'Preview requires authentication and a coherent domain User');
    foreach malformed in array array['', ' ', 'wrong-secret', upper(pg_temp.secret('carlos')), pg_temp.secret('carlos') || ' ',
        repeat('x', 4096), 'ñ#?&=/', encode(pg_temp.digest(pg_temp.secret('carlos')), 'hex')] loop
        perform pg_temp.assert_true(pg_temp.preview(12, pg_temp.inv('carlos'), malformed) = uniform,
            'Wrong or malformed secret previews uniformly: ' || left(malformed, 12));
    end loop;
    perform pg_temp.assert_true(pg_temp.preview(12, pg_temp.inv('carlos'), null) = uniform
        and pg_temp.preview(12, pg_temp.id(7, 999), pg_temp.secret('carlos')) = uniform
        and pg_temp.preview(12, null, pg_temp.secret('carlos')) = uniform,
        'Missing secret, unknown reference and missing reference preview uniformly');
    foreach target in array array['legacy_50', 'legacy_51', 'revoked', 'legacy_52', 'legacy_53', 'active_member'] loop
        perform pg_temp.assert_true(pg_temp.preview(14, pg_temp.inv(target), 'not-the-secret') = uniform,
            'Uniform failure hides the lifecycle before proof: ' || target);
    end loop;
    perform pg_temp.assert_true(pg_temp.world_state() = before, 'Failed previews write nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Preview payloads after proof (§10, Notes 22, 23, 31)
-- ---------------------------------------------------------------------------
do $$ declare result jsonb; inv record; before text := pg_temp.world_state(); begin
    select * into inv from public.organization_invitations where id = pg_temp.inv('carlos');
    result := pg_temp.preview_json(10, pg_temp.inv('carlos'), pg_temp.secret('carlos'));
    perform pg_temp.assert_true(result = jsonb_build_object('invitation_id', inv.id, 'state', 'PENDING',
            'organization_display_name', 'Animalia Group',
            'responsibilities', jsonb_build_array(jsonb_build_object('responsibility', 'RECEPTIONIST',
                'scope_type', 'ORGANIZATION', 'clinic', null)),
            'masked_recipient_email', 'c***@example.test', 'invited_email_matches_current_account', true,
            'expires_at', inv.expires_at),
        'PENDING preview: exact payload, masked address, matching account');
    result := pg_temp.preview_json(11, pg_temp.inv('carlos'), pg_temp.secret('carlos'));
    perform pg_temp.assert_true(result ->> 'state' = 'PENDING' and result -> 'invited_email_matches_current_account' = 'false'::jsonb
        and result ->> 'masked_recipient_email' = 'c***@example.test',
        'Different signed-in address previews PENDING and reports the mismatch');
    perform pg_temp.assert_true(result::text not ilike '%carlos.personal%' and result::text not ilike '%carlos.work%',
        'Preview echoes neither the invited nor the signed-in address in clear');
    perform pg_temp.assert_true((select array_agg(key order by key) from jsonb_object_keys(result) key)
            = array['expires_at', 'invitation_id', 'invited_email_matches_current_account', 'masked_recipient_email',
                'organization_display_name', 'responsibilities', 'state']
        and result::text not like '%' || encode(inv.acceptance_secret_digest, 'hex') || '%'
        and result::text not like '%' || pg_temp.secret('carlos') || '%'
        and result::text not like '%' || inv.organization_id::text || '%'
        and result::text not like '%' || inv.inviting_user_id::text || '%'
        and result::text not like '%' || pg_temp.id(2, 11)::text || '%'
        and result::text not ilike '%carlos.work@%',
        'Preview never returns secret, digest, Organization id, User ids or the unmasked address');
    result := pg_temp.preview_json(13, pg_temp.inv('unverified'), pg_temp.secret('unverified'));
    perform pg_temp.assert_true(result ->> 'state' = 'PENDING' and result ->> 'masked_recipient_email' = 'u***@example.test',
        'Unverified account can preview');
    result := pg_temp.preview_json(12, pg_temp.inv('clinic_admin'), pg_temp.secret('clinic_admin'));
    perform pg_temp.assert_true(result -> 'responsibilities' = jsonb_build_array(jsonb_build_object('responsibility', 'ADMINISTRATOR',
            'scope_type', 'CLINIC', 'clinic', jsonb_build_object('clinic_id', pg_temp.id(4, 1), 'clinic_display_name', 'A Centro'))),
        'Clinic-scoped preview identifies the Clinic');
    result := pg_temp.preview_json(12, pg_temp.inv('clinic_recep'), pg_temp.secret('clinic_recep'));
    perform pg_temp.assert_true(result -> 'responsibilities' -> 0 -> 'clinic' = jsonb_build_object('clinic_id', pg_temp.id(4, 2),
            'clinic_display_name', null),
        'Unnamed Clinic is identified with a null display name');
    result := pg_temp.preview_json(12, pg_temp.inv('legacy_55'), pg_temp.secret('legacy_55'));
    perform pg_temp.assert_true(jsonb_array_length(result -> 'responsibilities') = 2
        and result -> 'responsibilities' -> 0 ->> 'responsibility' = 'ADMINISTRATOR'
        and result -> 'responsibilities' -> 1 -> 'clinic' ->> 'clinic_display_name' = 'A Centro',
        'Legacy multi-responsibility preview lists every intended responsibility');

    perform pg_temp.assert_true(pg_temp.state_of(12, pg_temp.inv('legacy_50'), pg_temp.secret('legacy_50')) = 'EXPIRED'
        and pg_temp.state_of(12, pg_temp.inv('revoked'), pg_temp.secret('revoked')) = 'REVOKED'
        and pg_temp.state_of(14, pg_temp.inv('active_member'), pg_temp.secret('active_member')) = 'ALREADY_MEMBER',
        'Post-proof EXPIRED, REVOKED and ALREADY_MEMBER');
    result := pg_temp.preview_json(12, pg_temp.inv('revoked'), pg_temp.secret('revoked'));
    perform pg_temp.assert_true(result ->> 'organization_display_name' = 'Animalia Group'
        and result ->> 'masked_recipient_email' = 'r***@example.test',
        'Revoked preview identifies what was revoked');
    foreach result in array array[pg_temp.preview_json(12, pg_temp.inv('legacy_51'), pg_temp.secret('legacy_51')),
        pg_temp.preview_json(11, pg_temp.inv('legacy_52'), pg_temp.secret('legacy_52')),
        pg_temp.preview_json(12, pg_temp.inv('legacy_53'), pg_temp.secret('legacy_53'))] loop
        perform pg_temp.assert_true(result - 'invitation_id' = jsonb_build_object('state', 'UNAVAILABLE',
                'organization_display_name', null, 'responsibilities', '[]'::jsonb, 'masked_recipient_email', null,
                'invited_email_matches_current_account', null, 'expires_at', null),
            'UNAVAILABLE (rejected, bound to another User, invalid responsibility) discloses nothing else');
    end loop;
    perform pg_temp.assert_true(pg_temp.state_of(11, pg_temp.inv('legacy_52'), pg_temp.secret('legacy_52')) = 'UNAVAILABLE'
        and pg_temp.state_of(26, pg_temp.inv('legacy_56'), pg_temp.secret('legacy_56')) = 'PENDING',
        'Bound recipient User: unavailable to others, pending for that User');
    perform pg_temp.assert_true(pg_temp.world_state() = before
        and pg_temp.communication_state() = (select communications from b2_baseline),
        'Preview writes nothing');
end $$;

-- Masking rule (§10) on normal, short, mixed-case and unusual addresses.
select pg_temp.assert_true(public.mask_organization_invitation_recipient('carlos.work@example.com') = 'c***@example.com'
    and public.mask_organization_invitation_recipient('a@x.test') = 'a***@x.test'
    and public.mask_organization_invitation_recipient(lower(btrim(' Mixed.Case@Example.TEST '))) = 'm***@example.test'
    and public.mask_organization_invitation_recipient('first.last+tag@sub.example.co.uk') = 'f***@sub.example.co.uk'
    and public.mask_organization_invitation_recipient('ñandú@ejemplo.es') = 'ñ***@ejemplo.es'
    and public.mask_organization_invitation_recipient('"odd@local"@example.test') = '"***@example.test'
    and public.mask_organization_invitation_recipient('no-at-sign') = '***'
    and public.mask_organization_invitation_recipient('@example.test') = '***',
    'Recipient masking keeps the first character and the full domain');

-- ---------------------------------------------------------------------------
-- Acceptance: authentication, confirmed email, uniform failure (Notes 17–22)
-- ---------------------------------------------------------------------------
do $$ declare uniform text := '42501:-:-:Invitation unavailable';
    unverified text := '42501:ACCOUNT_VERIFICATION_REQUIRED:-:A verified email address is required';
    before text := pg_temp.world_state(); malformed text; target text; begin
    perform pg_temp.assert_true(pg_temp.accept(0, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '28000:-:-:Authentication is required'
        and pg_temp.accept(17, pg_temp.inv('carlos'), pg_temp.secret('carlos'))
            = '28000:-:-:No coherent domain User exists for the authenticated subject',
        'Acceptance requires authentication and a coherent domain User');
    perform pg_temp.assert_true(pg_temp.accept(13, pg_temp.inv('unverified'), pg_temp.secret('unverified')) = unverified
        and pg_temp.accept(13, pg_temp.inv('unverified'), 'wrong') = unverified
        and pg_temp.accept(13, pg_temp.id(7, 999), 'wrong') = unverified,
        'Unverified account cannot accept, before any Invitation fact is considered');
    foreach malformed in array array['', ' ', 'wrong-secret', upper(pg_temp.secret('carlos')),
        encode(pg_temp.digest(pg_temp.secret('carlos')), 'hex'), repeat('y', 4096)] loop
        perform pg_temp.assert_true(pg_temp.accept(12, pg_temp.inv('carlos'), malformed) = uniform,
            'Wrong secret fails uniformly and writes nothing: ' || left(malformed, 12));
    end loop;
    perform pg_temp.assert_true(pg_temp.accept(12, pg_temp.inv('carlos'), null) = uniform
        and pg_temp.accept(12, pg_temp.id(7, 999), pg_temp.secret('carlos')) = uniform
        and pg_temp.accept(12, null, pg_temp.secret('carlos')) = uniform,
        'Missing secret, unknown reference and missing reference fail uniformly');
    foreach target in array array['legacy_50', 'legacy_51', 'revoked', 'legacy_52', 'legacy_53', 'active_member'] loop
        perform pg_temp.assert_true(pg_temp.accept(14, pg_temp.inv(target), 'not-the-secret') = uniform,
            'Uniform failure hides the lifecycle before acceptance proof: ' || target);
    end loop;
    perform pg_temp.assert_true(pg_temp.world_state() = before, 'Failed acceptances write nothing');
end $$;

-- Post-proof lifecycle outcomes write nothing (Note 21).
do $$ declare before text := pg_temp.world_state(); begin
    perform pg_temp.assert_true(pg_temp.accept(12, pg_temp.inv('legacy_50'), pg_temp.secret('legacy_50'))
            = '23514:INVITATION_EXPIRED:-:Organization Invitation has expired',
        'Expired Invitation reported EXPIRED after proof and nothing written');
    perform pg_temp.assert_true(pg_temp.accept(12, pg_temp.inv('revoked'), pg_temp.secret('revoked'))
            = '23514:INVITATION_REVOKED:-:Organization Invitation has been revoked',
        'Revoked Invitation reported REVOKED after proof and nothing written');
    perform pg_temp.assert_true(pg_temp.accept(12, pg_temp.inv('legacy_51'), pg_temp.secret('legacy_51'))
            = '23514:INVITATION_UNAVAILABLE:-:Organization Invitation cannot be accepted'
        and pg_temp.accept(11, pg_temp.inv('legacy_52'), pg_temp.secret('legacy_52'))
            = '23514:INVITATION_UNAVAILABLE:-:Organization Invitation cannot be accepted'
        and pg_temp.accept(12, pg_temp.inv('legacy_53'), pg_temp.secret('legacy_53'))
            = '23514:INVITATION_UNAVAILABLE:-:Organization Invitation cannot be accepted',
        'Rejected, bound-to-another-User and no-longer-valid responsibilities reported unavailable');
    perform pg_temp.assert_true(pg_temp.accept(14, pg_temp.inv('active_member'), pg_temp.secret('active_member'))
            = '23505:ALREADY_MEMBER:-:User already has an active Organization Membership',
        'Already-a-Member acceptance reported and no second Membership');
    perform pg_temp.assert_true(pg_temp.world_state() = before
        and (select acceptance_secret_digest = pg_temp.digest('active-member-secret') and revoked_at is null
             from public.organization_invitations where id = pg_temp.inv('active_member'))
        and (select count(*) from public.organization_memberships where user_id = pg_temp.id(2, 14)
             and organization_id = pg_temp.id(3, 1) and effective_end is null) = 1,
        'Post-proof rejections write nothing; the Member keeps one Membership and the Invitation stays pending');
end $$;

-- ---------------------------------------------------------------------------
-- Successful acceptance (BR-3–BR-8, BR-11–BR-13, BR-19, BR-23, BR-24; Notes
-- 1–4, 9, 10, 12, 16, 17, 30)
-- ---------------------------------------------------------------------------
do $$ declare result jsonb; t timestamptz := statement_timestamp(); inv record; membership record; grant_row record;
    responsibilities text := (select md5(jsonb_agg(to_jsonb(r) order by r.id)::text) from public.organization_invitation_responsibilities r);
    users bigint := (select count(*) from public.users); begin
    select * into inv from public.organization_invitations where id = pg_temp.inv('carlos');
    result := pg_temp.accept_json(10, pg_temp.inv('carlos'), pg_temp.secret('carlos'));
    select * into membership from pg_temp.accepted_membership(pg_temp.inv('carlos'));
    perform pg_temp.assert_true(result = jsonb_build_object('invitation_id', inv.id, 'organization_id', pg_temp.id(3, 1),
            'membership_id', membership.id, 'outcome', 'ACCEPTED')
        and membership.user_id = pg_temp.id(2, 10) and membership.organization_id = pg_temp.id(3, 1)
        and (select acceptance_secret_digest is null and revoked_at is null and rejected_at is null
             from public.organization_invitations where id = inv.id),
        'Pending Organization Receptionist accepted: one Membership for the caller, digest erased');
    perform pg_temp.assert_true(membership.effective_start = t and membership.effective_end is null
        and membership.ended_by_user_id is null and membership.originating_invitation_id = inv.id,
        'Membership starts at the acceptance instant, has no end and records its originating Invitation');
    select * into grant_row from public.organization_responsibility_grants where membership_id = membership.id;
    perform pg_temp.assert_true((select count(*) from public.organization_responsibility_grants where membership_id = membership.id) = 1
        and grant_row.responsibility = 'RECEPTIONIST' and grant_row.scope_type = 'ORGANIZATION' and grant_row.clinic_id is null
        and grant_row.effective_start = membership.effective_start and grant_row.effective_end is null
        and grant_row.granted_by_user_id = inv.inviting_user_id
        and grant_row.originating_invitation_responsibility_id = (select id from public.organization_invitation_responsibilities
            where invitation_id = inv.id),
        'Exactly the intended Grant, at the Membership start, granted by the inviter, with its Invitation origin');
    perform pg_temp.assert_true((select md5(jsonb_agg(to_jsonb(r) order by r.id)::text) from public.organization_invitation_responsibilities r)
            = responsibilities
        and (select count(*) from public.organization_invitations where id = inv.id) = 1
        and (select (to_jsonb(i) - 'acceptance_secret_digest') = (to_jsonb(inv) - 'acceptance_secret_digest')
             from public.organization_invitations i where i.id = inv.id),
        'Invitation history and intended responsibilities are preserved');
    perform pg_temp.assert_true((select count(*) from public.users) = users
        and not exists (select 1 from public.veterinarian_clinic_assignments a
            join public.veterinarian_professional_profiles p on p.id = a.professional_profile_id where p.user_id = pg_temp.id(2, 10))
        and not exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 10)),
        'Acceptance creates no User, Clinic Assignment or veterinary qualification');
end $$;

-- Lost response, replay, provenance precedence (BR-21; Notes 24, 25, 26).
do $$ declare first jsonb; again jsonb; before text := pg_temp.world_state(); membership_id uuid :=
    (pg_temp.accepted_membership(pg_temp.inv('carlos'))).id; begin
    again := pg_temp.accept_json(10, pg_temp.inv('carlos'), pg_temp.secret('carlos'));
    perform pg_temp.assert_true(again = jsonb_build_object('invitation_id', pg_temp.inv('carlos'), 'organization_id', pg_temp.id(3, 1),
            'membership_id', membership_id, 'outcome', 'ALREADY_ACCEPTED'),
        'Lost-response retry returns ALREADY_ACCEPTED with the same Membership');
    first := pg_temp.accept_json(10, pg_temp.inv('carlos'), 'any-secret-after-erasure');
    perform pg_temp.assert_true(first = again, 'Same-User provenance precedes proof once the digest is erased');
    perform pg_temp.assert_true(pg_temp.world_state() = before, 'Repeated acceptance creates nothing');
    perform pg_temp.assert_true(pg_temp.accept(12, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '42501:-:-:Invitation unavailable'
        and pg_temp.accept(11, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '42501:-:-:Invitation unavailable',
        'Another User replay fails uniformly');
    perform pg_temp.assert_true(pg_temp.state_of(10, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = 'ACCEPTED_BY_YOU'
        and pg_temp.state_of(10, pg_temp.inv('carlos'), null) = 'ACCEPTED_BY_YOU',
        'Preview reports ACCEPTED_BY_YOU to the accepting User');
    perform pg_temp.assert_true(pg_temp.preview(12, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '42501:-:-:Invitation unavailable'
        and pg_temp.preview(14, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '42501:-:-:Invitation unavailable',
        'Another User preview of an accepted Invitation fails uniformly');
    perform pg_temp.assert_true(pg_temp.world_state() = before, 'Replays write nothing');
end $$;

-- Different signed-in address accepts with the secret (BR-15, BR-18; Note 23).
do $$ declare result jsonb; begin
    perform pg_temp.assert_true(pg_temp.preview_json(11, pg_temp.inv('other_address'), pg_temp.secret('other_address'))
        -> 'invited_email_matches_current_account' = 'false'::jsonb, 'Mismatch reported before acceptance');
    result := pg_temp.accept_json(11, pg_temp.inv('other_address'), pg_temp.secret('other_address'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (pg_temp.accepted_membership(pg_temp.inv('other_address'))).user_id = pg_temp.id(2, 11),
        'Different signed-in email accepts with the secret');
end $$;

-- Every Phase 1 role/scope, legacy shapes, and immediate authority in the same
-- statement and session (BR-25, SPEC-ORG-005, SPEC-ORG-007; Note 16).
do $$ declare result jsonb; context jsonb; entry jsonb; t timestamptz := statement_timestamp(); begin
    result := pg_temp.accept_json(20, pg_temp.inv('org_admin'), pg_temp.secret('org_admin'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED', 'Organization Administrator accepted');
    perform pg_temp.assert_true(public.user_has_organization_capability(pg_temp.id(2, 20), pg_temp.id(3, 1), 'ORGANIZATION_INVITE_MEMBERS')
        and public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 20), pg_temp.id(3, 1), 'CLINIC_MANAGE_PUBLIC_PROFILE'),
        'Accepted authority is current in the same statement');
    perform pg_temp.act(20);
    context := public.get_my_professional_context();
    select value into entry from jsonb_array_elements(context -> 'organizations') value
    where value ->> 'organization_id' = pg_temp.id(3, 1)::text;
    perform pg_temp.assert_true(entry ->> 'membership_id' = result ->> 'membership_id'
        and entry -> 'responsibilities' = jsonb_build_array(jsonb_build_object('responsibility', 'ADMINISTRATOR',
            'scope_type', 'ORGANIZATION', 'clinic', null))
        and entry -> 'capabilities' @> jsonb_build_array(jsonb_build_object('capability', 'ORGANIZATION_INVITE_MEMBERS',
            'scope_type', 'ORGANIZATION', 'clinic', null)),
        'Professional context reflects the new Membership immediately');
    perform pg_temp.assert_true((select bool_or((m ->> 'is_self')::boolean and m ->> 'membership_id' = result ->> 'membership_id'
            and m ->> 'invitation_recipient_email' = 'org.admin@example.test')
        from jsonb_array_elements(public.get_organization_staff(pg_temp.id(3, 1)) -> 'members') m),
        'New Organization Administrator reads Staff immediately and sees the invitation address as provenance');

    result := pg_temp.accept_json(21, pg_temp.inv('org_recep'), pg_temp.secret('org_recep'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 21), pg_temp.id(3, 1), 'APPOINTMENT_VIEW_SCHEDULE')
        and not public.user_has_organization_capability(pg_temp.id(2, 21), pg_temp.id(3, 1), 'ORGANIZATION_INVITE_MEMBERS'),
        'Organization Receptionist accepted with exactly Receptionist authority');
    perform pg_temp.act(21);
    begin
        perform public.get_organization_staff(pg_temp.id(3, 1));
        perform pg_temp.assert_true(false, 'Organization Receptionist must not read Staff');
    exception when insufficient_privilege then null; end;

    result := pg_temp.accept_json(22, pg_temp.inv('clinic_admin'), pg_temp.secret('clinic_admin'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (select clinic_id = pg_temp.id(4, 1) and scope_type = 'CLINIC' and responsibility = 'ADMINISTRATOR'
             from public.organization_responsibility_grants where membership_id = (result ->> 'membership_id')::uuid)
        and public.user_has_clinic_capability(pg_temp.id(2, 22), pg_temp.id(4, 1), 'CLINIC_MANAGE_PUBLIC_PROFILE')
        and not public.user_has_clinic_capability(pg_temp.id(2, 22), pg_temp.id(4, 2), 'CLINIC_MANAGE_PUBLIC_PROFILE')
        and not public.user_has_organization_capability(pg_temp.id(2, 22), pg_temp.id(3, 1), 'ORGANIZATION_INVITE_MEMBERS'),
        'Clinic Administrator accepted: authority at that Clinic only, immediately');
    perform pg_temp.act(22);
    perform pg_temp.assert_true((select bool_or(c ->> 'capability' = 'CLINIC_MANAGE_PUBLIC_PROFILE'
            and c -> 'clinic' ->> 'clinic_id' = pg_temp.id(4, 1)::text)
        from jsonb_array_elements(public.get_my_professional_context() -> 'organizations' -> 0 -> 'capabilities') c),
        'Professional context reflects the Clinic-scoped capability immediately');

    result := pg_temp.accept_json(23, pg_temp.inv('clinic_recep'), pg_temp.secret('clinic_recep'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and public.user_has_clinic_capability(pg_temp.id(2, 23), pg_temp.id(4, 2), 'APPOINTMENT_VIEW_SCHEDULE')
        and not public.user_has_clinic_capability(pg_temp.id(2, 23), pg_temp.id(4, 2), 'CLINIC_MANAGE_PUBLIC_PROFILE')
        and not public.user_has_clinic_capability(pg_temp.id(2, 23), pg_temp.id(4, 1), 'APPOINTMENT_VIEW_SCHEDULE'),
        'Clinic Receptionist accepted with Receptionist authority at that Clinic only');

    result := pg_temp.accept_json(24, pg_temp.inv('legacy_54'), pg_temp.secret('legacy_54'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (select responsibility = 'VETERINARIAN' and scope_type = 'ORGANIZATION' from public.organization_responsibility_grants
             where membership_id = (result ->> 'membership_id')::uuid)
        and not exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 24))
        and not public.user_has_clinic_capability(pg_temp.id(2, 24), pg_temp.id(4, 1), 'CLINICAL_CARE'),
        'Legacy Organization-scoped Veterinarian accepted without qualification, Assignment or clinical access');

    result := pg_temp.accept_json(25, pg_temp.inv('legacy_55'), pg_temp.secret('legacy_55'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (select count(*) from public.organization_responsibility_grants where membership_id = (result ->> 'membership_id')::uuid) = 2
        and (select array_agg(responsibility || ':' || scope_type || ':' || coalesce(clinic_id::text, '-') order by responsibility)
             from public.organization_responsibility_grants where membership_id = (result ->> 'membership_id')::uuid)
            = array['ADMINISTRATOR:ORGANIZATION:-', 'RECEPTIONIST:CLINIC:' || pg_temp.id(4, 1)]
        and (select count(distinct effective_start) = 1 and min(effective_start) = t
             from public.organization_responsibility_grants where membership_id = (result ->> 'membership_id')::uuid),
        'Legacy multi-responsibility Invitation accepted exactly as recorded');

    result := pg_temp.accept_json(26, pg_temp.inv('legacy_56'), pg_temp.secret('legacy_56'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED', 'Invitation bound to the caller is accepted');

    result := pg_temp.accept_json(27, pg_temp.inv('legacy_57'), pg_temp.secret('legacy_57'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (select granted_by_user_id = pg_temp.id(2, 3) from public.organization_responsibility_grants
             where membership_id = (result ->> 'membership_id')::uuid),
        'Invitation remains acceptable after its inviter left (BR-14)');

    result := pg_temp.accept_json(16, pg_temp.inv('multi_org'), pg_temp.secret('multi_org'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (select count(*) from public.organization_memberships where user_id = pg_temp.id(2, 16) and effective_end is null) = 2
        and (select effective_end is null from public.organization_memberships where id = pg_temp.id(5, 16)),
        'Membership in another Organization does not prevent acceptance; both stay independent (BR-16)');

    result := pg_temp.accept_json(15, pg_temp.inv('former_member'), pg_temp.secret('former_member'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (result ->> 'membership_id')::uuid <> pg_temp.id(5, 15)
        and (select effective_end = '2021-01-01Z' from public.organization_memberships where id = pg_temp.id(5, 15)),
        'Former Member accepts into a new Membership; the ended one is never reactivated');

    result := pg_temp.accept_json(1, pg_temp.inv('in_b'), pg_temp.secret('in_b'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED' and result ->> 'organization_id' = pg_temp.id(3, 2)::text
        and public.user_has_clinic_capability(pg_temp.id(2, 1), pg_temp.id(4, 3), 'CLINIC_MANAGE_PUBLIC_PROFILE')
        and public.user_has_organization_capability(pg_temp.id(2, 1), pg_temp.id(3, 1), 'ORGANIZATION_INVITE_MEMBERS')
        and not public.user_has_organization_capability(pg_temp.id(2, 1), pg_temp.id(3, 2), 'ORGANIZATION_INVITE_MEMBERS'),
        'Capabilities stay scoped to their own Organization (BR-11)');
end $$;

-- The accepting User is the authenticated subject, whatever else the request
-- carries (BR-19, Note 17).
do $$ declare result jsonb; begin
    perform set_config('request.headers', json_build_object('x-menizvet-user-id', pg_temp.id(2, 12),
        'x-user-id', pg_temp.id(2, 12))::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(1, 30), 'user_id', pg_temp.id(2, 12),
        'role', 'authenticated')::text, true);
    result := pg_temp.accept_json(30, pg_temp.inv('header'), pg_temp.secret('header'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (pg_temp.accepted_membership(pg_temp.inv('header'))).user_id = pg_temp.id(2, 30),
        'Accepting User derived from the authenticated subject only');
    perform set_config('request.headers', '', true);
    perform set_config('request.jwt.claims', '', true);
end $$;

-- Unverified account cannot accept but, once confirmed, can (Note 22).
do $$ declare result jsonb; begin
    perform pg_temp.assert_true(pg_temp.accept(13, pg_temp.inv('unverified'), pg_temp.secret('unverified'))
        = '42501:ACCOUNT_VERIFICATION_REQUIRED:-:A verified email address is required', 'Unverified account cannot accept');
    update auth.users set email_confirmed_at = statement_timestamp() where id = pg_temp.id(1, 13);
    result := pg_temp.accept_json(13, pg_temp.inv('unverified'), pg_temp.secret('unverified'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED', 'Confirmed account then accepts');
end $$;

-- Replay after the resulting Membership ended fails uniformly and never
-- reactivates it (BR-21; Note 26).
do $$ declare ended uuid := (pg_temp.accepted_membership(pg_temp.inv('carlos'))).id; before text; begin
    perform pg_temp.act(1);
    perform public.end_organization_membership(ended);
    before := pg_temp.world_state();
    perform pg_temp.assert_true(pg_temp.accept(10, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '42501:-:-:Invitation unavailable'
        and pg_temp.preview(10, pg_temp.inv('carlos'), pg_temp.secret('carlos')) = '42501:-:-:Invitation unavailable',
        'Replay after the resulting Membership ended fails uniformly');
    perform pg_temp.assert_true(pg_temp.world_state() = before
        and (select effective_end is not null from public.organization_memberships where id = ended),
        'Ended Membership is not reactivated');
end $$;

-- Expiry boundary at the acceptance instant (BR-9, BR-24; Note 28).
do $$ declare t timestamptz := statement_timestamp(); result jsonb; before text; begin
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t where id = pg_temp.inv('legacy_58');
    execute 'set local session_replication_role = origin';
    before := pg_temp.world_state();
    perform pg_temp.assert_true(pg_temp.accept(28, pg_temp.inv('legacy_58'), pg_temp.secret('legacy_58'))
            = '23514:INVITATION_EXPIRED:-:Organization Invitation has expired'
        and pg_temp.state_of(28, pg_temp.inv('legacy_58'), pg_temp.secret('legacy_58')) = 'EXPIRED'
        and pg_temp.world_state() = before,
        'Invitation expiring exactly at the acceptance instant is EXPIRED and unchanged');
    execute 'set local session_replication_role = replica';
    update public.organization_invitations set expires_at = t + interval '1 microsecond' where id = pg_temp.inv('legacy_58');
    execute 'set local session_replication_role = origin';
    perform pg_temp.assert_true(pg_temp.state_of(28, pg_temp.inv('legacy_58'), pg_temp.secret('legacy_58')) = 'PENDING',
        'Invitation expiring just after the instant previews PENDING');
    result := pg_temp.accept_json(28, pg_temp.inv('legacy_58'), pg_temp.secret('legacy_58'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (pg_temp.accepted_membership(pg_temp.inv('legacy_58'))).effective_start = t,
        'Invitation expiring just after the acceptance instant is accepted at that instant');
end $$;

-- A failure while creating any intended Grant leaves nothing (BR-7, BR-24;
-- Note 27).
create function pg_temp.reject_injected_grant() returns trigger language plpgsql as $$ begin
    if new.originating_invitation_responsibility_id = pg_temp.id(8, 159) then
        raise exception 'injected Grant failure';
    end if;
    return new;
end $$;
create trigger b2_injected_grant_failure before insert on public.organization_responsibility_grants
for each row execute function pg_temp.reject_injected_grant();
do $$ declare before text := pg_temp.world_state(); begin
    perform pg_temp.assert_true(pg_temp.accept(29, pg_temp.inv('legacy_59'), pg_temp.secret('legacy_59')) = 'P0001:-:-:injected Grant failure'
        and pg_temp.world_state() = before
        and not exists (select 1 from public.organization_memberships where user_id = pg_temp.id(2, 29))
        and (select acceptance_secret_digest = pg_temp.digest('legacy-secret-59') from public.organization_invitations
             where id = pg_temp.inv('legacy_59'))
        and pg_temp.state_of(29, pg_temp.inv('legacy_59'), pg_temp.secret('legacy_59')) = 'PENDING',
        'Injected Grant failure leaves no Membership, no Grant, and the Invitation pending with its digest');
end $$;
drop trigger b2_injected_grant_failure on public.organization_responsibility_grants;
do $$ declare result jsonb; begin
    result := pg_temp.accept_json(29, pg_temp.inv('legacy_59'), pg_temp.secret('legacy_59'));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ACCEPTED'
        and (select count(*) from public.organization_responsibility_grants where membership_id = (result ->> 'membership_id')::uuid) = 2,
        'After the injected failure is removed the same Invitation is accepted whole');
end $$;

-- Acceptance creates no Communication and changes none (BR-23; Note 30).
select pg_temp.assert_true(pg_temp.communication_state() = (select communications from b2_baseline)
    and (select count(*) from public.transactional_communications) = (select communication_count from b2_baseline),
    'Acceptance creates and changes no Communication');

-- Revocation after acceptance reports ACCEPTED and leaves the Membership
-- (SPEC-ORG-010); the Staff read no longer lists accepted Invitations.
do $$ declare memberships text; pending uuid[]; begin
    memberships := pg_temp.world_state();
    perform pg_temp.act(1);
    perform pg_temp.assert_true(public.revoke_organization_invitation(pg_temp.inv('org_admin')) ->> 'outcome' = 'ACCEPTED'
        and pg_temp.world_state() = memberships, 'Revoking an accepted Invitation reports ACCEPTED and writes nothing');
    select array_agg((value ->> 'invitation_id')::uuid) into pending
    from jsonb_array_elements(public.get_organization_staff(pg_temp.id(3, 1)) -> 'pending_invitations') value;
    perform pg_temp.assert_true(not (pg_temp.inv('org_admin') = any(pending)) and pg_temp.inv('active_member') = any(pending),
        'Accepted Invitations leave the pending Staff list; unaccepted ones stay');
end $$;

-- Trusted service-role command shares the writer: Clinic scope still accepted.
do $$ declare created uuid; accepted uuid; membership record; begin
    created := pg_temp.invite('legacy.path@example.test', 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 1), 'legacy-path-secret');
    accepted := public.accept_organization_invitation(pg_temp.id(2, 31), created, pg_temp.digest('legacy-path-secret'));
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    select * into membership from pg_temp.accepted_membership(created);
    perform pg_temp.assert_true(accepted = membership.id and membership.user_id = pg_temp.id(2, 31)
        and (select clinic_id = pg_temp.id(4, 1) and effective_start = membership.effective_start
             from public.organization_responsibility_grants where membership_id = membership.id),
        'Trusted service-role acceptance keeps working through the shared writer');
end $$;

-- ---------------------------------------------------------------------------
-- Serialization evidence (BR-24): Organization -> Invitation -> Clinic for
-- acceptance; the preview takes no lock.
-- ---------------------------------------------------------------------------
create extension pgrowlocks with schema extensions;
create function pg_temp.locked(relation regclass, row_id uuid, mode text) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return mode = any(coalesce(result, '{}'));
end $$;
-- Fresh rows of two more Organizations so earlier statements hold no lock:
-- probe 90 already accepted by acceptor 31 (the no-write ALREADY_ACCEPTED
-- path), probe 80 pending and Clinic-scoped (the writing path). A failed call
-- releases its row locks with its subtransaction, so the pre-proof Organization
-- lock under contention is pinned by the two-session runner instead.
set local session_replication_role = replica;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 9), 'Lock probe accepted'), (pg_temp.id(3, 8), 'Lock probe pending');
insert into public.clinics (id, organization_id) values (pg_temp.id(4, 9), pg_temp.id(3, 9)), (pg_temp.id(4, 8), pg_temp.id(3, 8));
insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email, created_at, expires_at,
    acceptance_secret_digest) values
    (pg_temp.id(7, 90), pg_temp.id(3, 9), pg_temp.id(2, 1), 'probe.accepted@example.test',
        statement_timestamp() - interval '1 day', statement_timestamp() + interval '6 days', null),
    (pg_temp.id(7, 80), pg_temp.id(3, 8), pg_temp.id(2, 1), 'probe.pending@example.test',
        statement_timestamp() - interval '1 day', statement_timestamp() + interval '6 days', pg_temp.digest('probe-secret'));
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id) values
    (pg_temp.id(8, 90), pg_temp.id(7, 90), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 9)),
    (pg_temp.id(8, 80), pg_temp.id(7, 80), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 8));
insert into public.organization_memberships (id, organization_id, user_id, effective_start, originating_invitation_id) values
    (pg_temp.id(5, 90), pg_temp.id(3, 9), pg_temp.id(2, 31), statement_timestamp() - interval '1 hour', pg_temp.id(7, 90)),
    (pg_temp.id(5, 91), pg_temp.id(3, 9), pg_temp.id(2, 1), '2020-01-01Z', null),
    (pg_temp.id(5, 81), pg_temp.id(3, 8), pg_temp.id(2, 1), '2020-01-01Z', null);
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id, effective_start,
    granted_by_user_id, originating_invitation_responsibility_id) values
    (pg_temp.id(6, 90), pg_temp.id(5, 90), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 9), statement_timestamp() - interval '1 hour',
        pg_temp.id(2, 1), pg_temp.id(8, 90)),
    (pg_temp.id(6, 91), pg_temp.id(5, 91), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1), null),
    (pg_temp.id(6, 81), pg_temp.id(5, 81), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1), null);
set local session_replication_role = origin;
select pg_temp.assert_true(pg_temp.preview_json(31, pg_temp.id(7, 90), null) ->> 'state' = 'ACCEPTED_BY_YOU'
    and pg_temp.preview_json(31, pg_temp.id(7, 80), 'probe-secret') ->> 'state' = 'PENDING'
    and not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 9), 'For Update')
    and not pg_temp.locked('public.organization_invitations', pg_temp.id(7, 90), 'For Update')
    and not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 8), 'For Update')
    and not pg_temp.locked('public.organization_invitations', pg_temp.id(7, 80), 'For Update')
    and not pg_temp.locked('public.clinics', pg_temp.id(4, 8), 'For Update'),
    'Preview takes no row lock');
select pg_temp.assert_true(pg_temp.accept_json(31, pg_temp.id(7, 90), null) ->> 'outcome' = 'ALREADY_ACCEPTED'
    and pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 9), 'For Update')
    and pg_temp.locked('public.organization_invitations', pg_temp.id(7, 90), 'For Update')
    and not pg_temp.locked('public.clinics', pg_temp.id(4, 9), 'For Update'),
    'Acceptance serializes on Organization then Invitation before provenance and proof');
select pg_temp.assert_true(pg_temp.accept_json(31, pg_temp.id(7, 80), 'probe-secret') ->> 'outcome' = 'ACCEPTED'
    and pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 8), 'For Update')
    and pg_temp.locked('public.organization_invitations', pg_temp.id(7, 80), 'For Update')
    and pg_temp.locked('public.clinics', pg_temp.id(4, 8), 'For Update'),
    'Acceptance locks the intended Clinic before writing');

-- Real authenticated role (mobile path).
create temporary table b2_role_probe on commit drop as
select pg_temp.inv('in_b') accepted, pg_temp.inv('active_member') pending, pg_temp.secret('active_member') secret;
grant select on b2_role_probe to authenticated;
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_true(public.preview_organization_invitation((select accepted from b2_role_probe), null) ->> 'state' = 'ACCEPTED_BY_YOU'
    and public.accept_my_organization_invitation((select accepted from b2_role_probe), null) ->> 'outcome' = 'ALREADY_ACCEPTED'
    and public.preview_organization_invitation((select pending from b2_role_probe), (select secret from b2_role_probe)) ->> 'state'
        = 'ALREADY_MEMBER',
    'Authenticated role executes preview and acceptance');
reset role;

set constraints all immediate;
set constraints all deferred;
rollback;

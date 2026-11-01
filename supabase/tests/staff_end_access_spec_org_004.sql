-- Staff Phase 1 Slice C: SPEC-ORG-004 §10/§11 (BR-20–BR-28), SPEC-ORG-005,
-- SPEC-ORG-009, SPEC-VET-005 BR-22, with B1/B2 integration for rejoining.
-- Isolated LOCAL superuser only; fixtures, helper substitutions and assertions
-- are rollback-only. Behaviour is exercised through the real operations.
-- Multi-session races are pinned by run_staff_end_access_concurrency.py.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0290000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.subject(n integer) returns uuid language sql immutable as $$
    select case when n = 0 then null else pg_temp.id(1, n) end
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(pg_temp.subject(n)::text, ''), true)
$$;
create function pg_temp.bytes(n integer) returns bytea language sql volatile as $$
    select decode(substr(md5(random()::text) || md5(random()::text), 1, 2 * n), 'hex')
$$;
-- Deferred integrity triggers fire inside the call, as at commit.
create function pg_temp.end_access(actor integer, membership uuid) returns text language plpgsql as $$
declare result jsonb; failure_hint text; begin
    perform pg_temp.act(actor);
    result := public.end_organization_staff_membership(membership);
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return result::text;
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return sqlstate || ':' || coalesce(nullif(failure_hint, ''), '-') || ':' || sqlerrm;
end $$;
create function pg_temp.end_json(actor integer, membership uuid) returns jsonb language sql as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
    from pg_temp.end_access(actor, membership) result
$$;
create function pg_temp.outcome_of(actor integer, membership uuid) returns text language sql as $$
    select coalesce(pg_temp.end_json(actor, membership) ->> 'outcome', pg_temp.end_json(actor, membership) ->> 'error')
$$;
create function pg_temp.membership_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(m) order by m.id)::text from public.organization_memberships m), '')
        || coalesce((select jsonb_agg(to_jsonb(g) order by g.id)::text from public.organization_responsibility_grants g), ''))
$$;
-- Everything Slice C must never touch.
create function pg_temp.untouched_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(i) order by i.id)::text from public.organization_invitations i), '')
        || coalesce((select jsonb_agg(to_jsonb(r) order by r.id)::text from public.organization_invitation_responsibilities r), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.transactional_communications c), '')
        || coalesce((select jsonb_agg(to_jsonb(j) order by j.id)::text from public.communication_delivery_jobs j), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.veterinarian_clinic_assignments a), '')
        || coalesce((select jsonb_agg(to_jsonb(p) order by p.id)::text from public.veterinarian_professional_profiles p), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.appointments a), '')
        || coalesce((select jsonb_agg(to_jsonb(v) order by v.id)::text from public.appointment_veterinarian_assignments v), '')
        || coalesce((select jsonb_agg(to_jsonb(u) order by u.id)::text from public.users u), '')
        || coalesce((select jsonb_agg(to_jsonb(u) order by u.user_id)::text from public.user_profiles u), '')
        || coalesce((select jsonb_agg(to_jsonb(o) order by o.id)::text from public.veterinary_organizations o), '')
        || coalesce((select jsonb_agg(to_jsonb(c) order by c.id)::text from public.clinics c), ''))
$$;
create function pg_temp.context_organizations(actor integer) returns uuid[] language plpgsql as $$
declare result uuid[]; begin
    perform pg_temp.act(actor);
    select coalesce(array_agg((value ->> 'organization_id')::uuid order by value ->> 'organization_id'), '{}') into result
    from jsonb_array_elements(public.get_my_professional_context() -> 'organizations') value;
    return result;
end $$;
create function pg_temp.staff_member_ids(actor integer, organization uuid) returns uuid[] language plpgsql as $$
declare result uuid[]; begin
    perform pg_temp.act(actor);
    select coalesce(array_agg((value ->> 'membership_id')::uuid), '{}') into result
    from jsonb_array_elements(public.get_organization_staff(organization) -> 'members') value;
    return result;
end $$;
create function pg_temp.sqlstate_of(actor integer, statement text) returns text language plpgsql as $$
begin
    perform pg_temp.act(actor);
    execute statement;
    return '00000';
exception when others then return sqlstate; end $$;
-- B1 creation and B2 acceptance exactly as the product paths call them.
create function pg_temp.invite(actor integer, email text, secret text) returns uuid language plpgsql as $$
declare instant timestamptz; begin
    instant := public.authorize_organization_invitation_creation(pg_temp.subject(actor), pg_temp.id(3, 1));
    return public.create_staff_organization_invitation_with_communication(pg_temp.subject(actor), pg_temp.id(3, 1),
        email, 'RECEPTIONIST', 'ORGANIZATION', null, instant, sha256(convert_to(secret, 'UTF8')), 1,
        pg_temp.bytes(12), pg_temp.bytes(32));
end $$;
create function pg_temp.accept(actor integer, invitation uuid, secret text) returns jsonb language plpgsql as $$
declare result jsonb; begin
    perform pg_temp.act(actor);
    result := public.accept_my_organization_invitation(invitation, secret);
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    return result;
end $$;

set local session_replication_role = replica;
-- Actors (Auth subject n <-> domain User n), Organization A unless noted:
-- 1 Owner; 2 Organization Administrator; 3 Clinic Administrator (Clinic 1);
-- 4 Organization Receptionist; 5 Veterinarian (profile + Clinic 1 Assignment);
-- 6 Clinic Receptionist (Clinic 2); 8 co-Owner; 9 Administrator of B;
-- 10 Owner of B; 11 Receptionist in A and in B; 12 Administrator + Clinic 1
-- Receptionist with an older ended Grant; 13 ended Member; 14 rejoiner (no
-- Membership yet); 15 no Membership (Guardian); 16 authenticated subject
-- without a domain User; 18 Administrator whose Grant starts tomorrow;
-- 20 Receptionist whose Grant starts in two days (clamp target).
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'end-' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20]) n;
insert into public.users (id) select pg_temp.id(2, n)
from unnest(array[1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 18, 20]) n;
insert into public.user_authentication_identities (user_id, provider_subject) select pg_temp.id(2, n), pg_temp.id(1, n)
from unnest(array[1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 18, 20]) n;
insert into public.user_profiles (user_id, display_name) values (pg_temp.id(2, 4), 'Recepción Ana');
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'End Org A'), (pg_temp.id(3, 2), 'End Org B');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 1)), (pg_temp.id(4, 3), pg_temp.id(3, 2));
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.id(4, 1), 'A Centro');
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.id(5, n), pg_temp.id(3, case when n in (9, 10, 111) then 2 else 1 end),
    pg_temp.id(2, case when n = 111 then 11 else n end), '2020-01-01Z',
    case when n = 13 then '2021-01-01Z'::timestamptz end, case when n = 13 then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 111, 12, 13, 18, 20]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, case when n in (112, 212) then 12 else n end),
    case when n in (1, 8, 10) then 'OWNER' when n in (2, 3, 9, 12, 18) then 'ADMINISTRATOR'
         when n = 5 then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (3, 6, 112) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (3, 112) then pg_temp.id(4, 1) when n = 6 then pg_temp.id(4, 2) end,
    case when n = 18 then statement_timestamp() + interval '1 day'
         when n = 20 then statement_timestamp() + interval '2 days' else '2020-01-01Z'::timestamptz end,
    case when n in (13, 212) then '2021-01-01Z'::timestamptz end,
    pg_temp.id(2, 1), case when n in (13, 212) then pg_temp.id(2, 1) end
from unnest(array[1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 111, 12, 112, 212, 13, 18, 20]) n;
-- Veterinarian 5: profile, current Clinic 1 Assignment, one Appointment with
-- an Appointment Veterinarian Assignment.
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(7, 5), pg_temp.id(2, 5));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values (pg_temp.id(8, 5), pg_temp.id(7, 5), pg_temp.id(5, 5), pg_temp.id(4, 1), '2020-01-01Z');
insert into public.pets (id, name, species, created_at) values (pg_temp.id(9, 1), 'Luna', 'DOG', '2020-01-01Z');
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, created_at)
values (pg_temp.id(10, 1), pg_temp.id(9, 1), pg_temp.id(4, 1), pg_temp.id(2, 15), 'Revisión', '2020-01-01Z');
insert into public.appointment_veterinarian_assignments (id, appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id)
values (pg_temp.id(11, 1), pg_temp.id(10, 1), pg_temp.id(8, 5), '2020-01-01Z', pg_temp.id(2, 1));
set local session_replication_role = origin;

-- A pending Invitation created by the Administrator who will be ended (BR-19).
create temporary table c_state (key text primary key, id uuid not null) on commit drop;
insert into c_state values ('pending_by_2', pg_temp.invite(2, 'pending.by.admin@example.test', 'pending-secret'));
set constraints all immediate;
set constraints all deferred;

-- ---------------------------------------------------------------------------
-- Contract and ACL (BR-20, BR-27; Notes 30)
-- ---------------------------------------------------------------------------
select pg_temp.assert_true((select prosecdef and proconfig @> array['search_path=""'] and provolatile = 'v'
        and prorettype = 'jsonb'::regtype and proargnames = array['p_membership_id']
    from pg_proc where oid = 'public.end_organization_staff_membership(uuid)'::regprocedure)
    and (select count(*) from pg_proc where proname = 'end_organization_staff_membership') = 1,
    'Exact contract: SECURITY DEFINER, empty search_path, Membership id only');
select pg_temp.assert_true(has_function_privilege('authenticated', 'public.end_organization_staff_membership(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.end_organization_staff_membership(uuid)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.end_organization_staff_membership(uuid)', 'EXECUTE'),
    'End access is executable by authenticated only');
select pg_temp.assert_true(not has_function_privilege('authenticated', 'public.end_organization_membership(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.end_organization_membership(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.end_organization_membership(uuid)', 'EXECUTE'),
    'No client role executes the permissive generic end operation');

-- ---------------------------------------------------------------------------
-- Fail-closed authorization before any lifecycle fact (BR-21, BR-23; Notes
-- 27, 28)
-- ---------------------------------------------------------------------------
do $$ declare denied text := '42501:-:Organization Membership unavailable'; actor integer; target uuid;
    before text := pg_temp.membership_state(); untouched text := pg_temp.untouched_state(); begin
    perform pg_temp.assert_true(pg_temp.end_access(0, pg_temp.id(5, 4)) = '28000:-:Authentication is required'
        and pg_temp.end_access(16, pg_temp.id(5, 4)) = '28000:-:No coherent domain User exists for the authenticated subject',
        'End access requires authentication and a coherent domain User');
    foreach actor in array array[3, 4, 5, 6, 9, 10, 11, 13, 15, 18] loop
        foreach target in array array[pg_temp.id(5, 4), pg_temp.id(5, 1), pg_temp.id(5, 13), pg_temp.id(5, 2),
                pg_temp.id(5, 999), pg_temp.id(5, 9)] loop
            -- Organization B's own Members are authorized there; not a denial case.
            continue when actor in (9, 10) and target = pg_temp.id(5, 9);
            perform pg_temp.assert_true(pg_temp.end_access(actor, target) = denied,
                'Caller without ORGANIZATION_END_MEMBERSHIPS fails uniformly: ' || actor);
        end loop;
    end loop;
    perform pg_temp.assert_true(pg_temp.end_access(1, pg_temp.id(5, 999)) = denied
        and pg_temp.end_access(1, null) = denied
        and pg_temp.end_access(1, pg_temp.id(5, 9)) = denied
        and pg_temp.end_access(1, pg_temp.id(5, 111)) = denied,
        'Unknown Membership and another Organization''s Membership fail identically');
    perform pg_temp.assert_true(pg_temp.end_access(9, pg_temp.id(5, 4)) = denied and pg_temp.end_access(10, pg_temp.id(5, 4)) = denied,
        'Member of another Organization is denied');
    perform pg_temp.assert_true(pg_temp.membership_state() = before and pg_temp.untouched_state() = untouched,
        'Denied attempts write nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Protected targets (BR-22; Notes 24, 25)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.membership_state();
    self_error text := '23514:SELF_MEMBERSHIP:Own Organization Membership cannot be ended through Staff';
    owner_error text := '23514:OWNER_MEMBERSHIP:An Owner Membership cannot be ended through Staff'; begin
    perform pg_temp.assert_true(pg_temp.end_access(2, pg_temp.id(5, 2)) = self_error
        and pg_temp.end_access(1, pg_temp.id(5, 1)) = self_error,
        'Own Membership is rejected even with the capability');
    perform pg_temp.assert_true(pg_temp.end_access(2, pg_temp.id(5, 1)) = owner_error
        and pg_temp.end_access(1, pg_temp.id(5, 8)) = owner_error
        and pg_temp.end_access(8, pg_temp.id(5, 1)) = owner_error,
        'A Membership holding an active OWNER Grant is rejected even when another Owner exists');
    perform pg_temp.assert_true(pg_temp.membership_state() = before
        and (select count(*) from public.organization_memberships m join public.organization_responsibility_grants g
             on g.membership_id = m.id where m.organization_id = pg_temp.id(3, 1) and m.effective_end is null
             and g.effective_end is null and g.responsibility = 'OWNER') = 2,
        'Protected targets write nothing and both Owners remain');
end $$;

-- Positive controls: the authority that ending must remove exists now.
do $$ begin
    perform pg_temp.assert_true(public.user_has_organization_capability(pg_temp.id(2, 2), pg_temp.id(3, 1), 'ORGANIZATION_INVITE_MEMBERS')
        and public.user_has_clinic_capability(pg_temp.id(2, 3), pg_temp.id(4, 1), 'CLINIC_MANAGE_PUBLIC_PROFILE')
        and public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 4), pg_temp.id(3, 1), 'APPOINTMENT_VIEW_SCHEDULE')
        and public.user_has_clinic_capability(pg_temp.id(2, 5), pg_temp.id(4, 1), 'CLINICAL_CARE')
        and public.veterinarian_clinic_assignment_is_current(pg_temp.id(8, 5))
        and public.user_has_clinic_capability(pg_temp.id(2, 6), pg_temp.id(4, 2), 'APPOINTMENT_VIEW_SCHEDULE')
        and public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 11), pg_temp.id(3, 1), 'APPOINTMENT_VIEW_SCHEDULE')
        and public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 11), pg_temp.id(3, 2), 'APPOINTMENT_VIEW_SCHEDULE')
        and public.user_has_organization_capability(pg_temp.id(2, 12), pg_temp.id(3, 1), 'ORGANIZATION_END_MEMBERSHIPS')
        and not public.user_has_organization_capability(pg_temp.id(2, 18), pg_temp.id(3, 1), 'ORGANIZATION_END_MEMBERSHIPS'),
        'Fixture: authority present before ending');
end $$;

-- ---------------------------------------------------------------------------
-- ENDED: one instant for the Membership and every active Grant, nothing else
-- changes (BR-24; Notes 17, 18, 22)
-- ---------------------------------------------------------------------------
do $$ declare t timestamptz := statement_timestamp(); result jsonb; untouched text := pg_temp.untouched_state();
    old_grant text := (select to_jsonb(g)::text from public.organization_responsibility_grants g where g.id = pg_temp.id(6, 212));
    others text := (select md5(jsonb_agg(to_jsonb(m) order by m.id)::text) from public.organization_memberships m
        where m.id <> pg_temp.id(5, 12));
    other_grants text := (select md5(jsonb_agg(to_jsonb(g) order by g.id)::text) from public.organization_responsibility_grants g
        where g.membership_id <> pg_temp.id(5, 12)); begin
    result := pg_temp.end_json(2, pg_temp.id(5, 12));
    perform pg_temp.assert_true(result = jsonb_build_object('membership_id', pg_temp.id(5, 12), 'effective_end', t, 'outcome', 'ENDED'),
        'Administrator ends a multi-Grant Member: exact ENDED result');
    perform pg_temp.assert_true((select effective_end = t and ended_by_user_id = pg_temp.id(2, 2) and effective_start = '2020-01-01Z'
            from public.organization_memberships where id = pg_temp.id(5, 12))
        and (select count(*) = 2 and bool_and(effective_end = t and ended_by_user_id = pg_temp.id(2, 2))
            from public.organization_responsibility_grants where id in (pg_temp.id(6, 12), pg_temp.id(6, 112))),
        'Every active Grant and the Membership end at the same instant, by the acting User');
    perform pg_temp.assert_true((select to_jsonb(g)::text from public.organization_responsibility_grants g where g.id = pg_temp.id(6, 212)) = old_grant
        and (select responsibility = 'RECEPTIONIST' and scope_type = 'CLINIC' and clinic_id = pg_temp.id(4, 1)
             from public.organization_responsibility_grants where id = pg_temp.id(6, 112)),
        'An already ended Grant is untouched and ended Grants keep role, scope and Clinic');
    perform pg_temp.assert_true((select md5(jsonb_agg(to_jsonb(m) order by m.id)::text) from public.organization_memberships m
            where m.id <> pg_temp.id(5, 12)) = others
        and (select md5(jsonb_agg(to_jsonb(g) order by g.id)::text) from public.organization_responsibility_grants g
            where g.membership_id <> pg_temp.id(5, 12)) = other_grants,
        'No other Membership or Grant changes');
    perform pg_temp.assert_true(pg_temp.untouched_state() = untouched,
        'Ending deletes nothing and changes no Invitation, Communication, Assignment, Appointment, User or Clinic');
    perform pg_temp.assert_true(not public.user_has_organization_capability(pg_temp.id(2, 12), pg_temp.id(3, 1), 'ORGANIZATION_END_MEMBERSHIPS')
        and not public.user_has_clinic_capability(pg_temp.id(2, 12), pg_temp.id(4, 1), 'APPOINTMENT_VIEW_SCHEDULE'),
        'Authority ends in the same statement');
end $$;

-- Every role, immediate authority loss (BR-25, BR-28; Notes 19, 20, 21, 23).
do $$ declare untouched text := pg_temp.untouched_state(); outcome text; begin
    outcome := pg_temp.outcome_of(1, pg_temp.id(5, 4));
    perform pg_temp.assert_true(outcome = 'ENDED'
        and not public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 4), pg_temp.id(3, 1), 'APPOINTMENT_VIEW_SCHEDULE'),
        'Organization Receptionist ended: Organization-scoped Appointment authority gone');
    outcome := pg_temp.outcome_of(1, pg_temp.id(5, 3));
    perform pg_temp.assert_true(outcome = 'ENDED'
        and not public.user_has_clinic_capability(pg_temp.id(2, 3), pg_temp.id(4, 1), 'CLINIC_MANAGE_PUBLIC_PROFILE'),
        'Clinic Administrator ended: Clinic authority gone');
    outcome := pg_temp.outcome_of(1, pg_temp.id(5, 6));
    perform pg_temp.assert_true(outcome = 'ENDED'
        and not public.user_has_clinic_capability(pg_temp.id(2, 6), pg_temp.id(4, 2), 'APPOINTMENT_VIEW_SCHEDULE'),
        'Clinic Receptionist ended: Appointment authority gone');
    outcome := pg_temp.outcome_of(1, pg_temp.id(5, 5));
    perform pg_temp.assert_true(outcome = 'ENDED'
        and not public.veterinarian_clinic_assignment_is_current(pg_temp.id(8, 5))
        and not public.user_has_clinic_capability(pg_temp.id(2, 5), pg_temp.id(4, 1), 'CLINICAL_CARE')
        and not public.user_has_clinic_capability(pg_temp.id(2, 5), pg_temp.id(4, 1), 'APPOINTMENT_VIEW_SCHEDULE'),
        'Veterinarian ended: the Clinic Assignment is no longer current and grants nothing');
    perform pg_temp.assert_true((select effective_end is null and supporting_membership_id = pg_temp.id(5, 5)
            from public.veterinarian_clinic_assignments where id = pg_temp.id(8, 5))
        and exists (select 1 from public.veterinarian_professional_profiles where id = pg_temp.id(7, 5))
        and exists (select 1 from public.appointment_veterinarian_assignments where id = pg_temp.id(11, 1)
            and veterinarian_clinic_assignment_id = pg_temp.id(8, 5)),
        'Assignment, Veterinarian profile and Appointment Veterinarian Assignment are kept');
    outcome := pg_temp.outcome_of(1, pg_temp.id(5, 2));
    perform pg_temp.assert_true(outcome = 'ENDED'
        and not public.user_has_organization_capability(pg_temp.id(2, 2), pg_temp.id(3, 1), 'ORGANIZATION_INVITE_MEMBERS')
        and not public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 2), pg_temp.id(3, 1), 'CLINIC_MANAGE_PUBLIC_PROFILE'),
        'Organization Administrator ended: every Organization capability gone');
    outcome := pg_temp.outcome_of(1, pg_temp.id(5, 11));
    perform pg_temp.assert_true(outcome = 'ENDED'
        and not public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 11), pg_temp.id(3, 1), 'APPOINTMENT_VIEW_SCHEDULE')
        and public.user_has_organization_scoped_clinic_capability(pg_temp.id(2, 11), pg_temp.id(3, 2), 'APPOINTMENT_VIEW_SCHEDULE')
        and (select effective_end is null from public.organization_memberships where id = pg_temp.id(5, 111))
        and (select effective_end is null from public.organization_responsibility_grants where id = pg_temp.id(6, 111)),
        'Ending access in A keeps the Membership, Grant and authority in B');
    perform pg_temp.assert_true(pg_temp.untouched_state() = untouched,
        'Ending every role changes no Invitation, Communication, Assignment, Appointment, User or Clinic');
end $$;

-- The former Members' still-valid identities: live reads deny or omit A.
do $$ begin
    perform pg_temp.assert_true(pg_temp.context_organizations(11) = array[pg_temp.id(3, 2)]
        and pg_temp.context_organizations(2) = '{}'::uuid[] and pg_temp.context_organizations(5) = '{}'::uuid[],
        'Professional context drops the ended Organization and keeps the other');
    perform pg_temp.assert_true(pg_temp.sqlstate_of(2, format('select public.get_organization_staff(%L)', pg_temp.id(3, 1))) = '42501'
        and pg_temp.sqlstate_of(3, format('select public.get_managed_clinic_profile(%L)', pg_temp.id(4, 1))) = '42501'
        and pg_temp.sqlstate_of(6, format('select public.get_clinic_appointment_schedule(%L)', pg_temp.id(4, 2))) = '42501'
        and pg_temp.sqlstate_of(4, format('select public.get_clinic_appointment_schedule(%L)', pg_temp.id(4, 1))) = '42501',
        'Former Members are denied protected reads with no sign-out or token change');
    perform pg_temp.assert_true(pg_temp.sqlstate_of(11, format('select public.get_clinic_appointment_schedule(%L)', pg_temp.id(4, 3))) = '00000',
        'The other Organization stays usable');
end $$;

-- ---------------------------------------------------------------------------
-- ALREADY_ENDED, retry by any authorized caller (BR-17, BR-26; Note 26)
-- ---------------------------------------------------------------------------
do $$ declare before text := pg_temp.membership_state(); first_end timestamptz :=
    (select effective_end from public.organization_memberships where id = pg_temp.id(5, 4)); begin
    perform pg_temp.assert_true(pg_temp.end_json(1, pg_temp.id(5, 4)) = jsonb_build_object('membership_id', pg_temp.id(5, 4),
            'effective_end', first_end, 'outcome', 'ALREADY_ENDED')
        and pg_temp.end_json(8, pg_temp.id(5, 4)) ->> 'outcome' = 'ALREADY_ENDED',
        'Retry returns ALREADY_ENDED with the original effective end');
    perform pg_temp.assert_true(pg_temp.end_json(1, pg_temp.id(5, 13)) = jsonb_build_object('membership_id', pg_temp.id(5, 13),
            'effective_end', '2021-01-01Z'::timestamptz, 'outcome', 'ALREADY_ENDED'),
        'An earlier ended Membership reports its own end');
    perform pg_temp.assert_true(pg_temp.end_access(2, pg_temp.id(5, 4)) = '42501:-:Organization Membership unavailable',
        'A caller who lost the capability cannot learn that the Membership ended');
    perform pg_temp.assert_true(pg_temp.membership_state() = before, 'Retries change nothing');
end $$;

-- ---------------------------------------------------------------------------
-- Temporal clamp: the end never precedes an active Grant's start (BR-14)
-- ---------------------------------------------------------------------------
do $$ declare later timestamptz := (select effective_start from public.organization_responsibility_grants where id = pg_temp.id(6, 20));
    result jsonb; begin
    result := pg_temp.end_json(1, pg_temp.id(5, 20));
    perform pg_temp.assert_true(result ->> 'outcome' = 'ENDED' and (result ->> 'effective_end')::timestamptz = later
        and (select effective_end = later from public.organization_memberships where id = pg_temp.id(5, 20))
        and (select effective_end = later from public.organization_responsibility_grants where id = pg_temp.id(6, 20)),
        'End instant never precedes the latest active Grant start');
end $$;

-- ---------------------------------------------------------------------------
-- Staff read integration, pending Invitations, Owner invariant (SPEC-ORG-009,
-- BR-12, BR-19)
-- ---------------------------------------------------------------------------
do $$ declare members uuid[] := pg_temp.staff_member_ids(1, pg_temp.id(3, 1)); staff jsonb; begin
    perform pg_temp.assert_true(pg_temp.id(5, 1) = any(members) and pg_temp.id(5, 8) = any(members) and pg_temp.id(5, 18) = any(members)
        and not (pg_temp.id(5, 2) = any(members) or pg_temp.id(5, 3) = any(members) or pg_temp.id(5, 4) = any(members)
            or pg_temp.id(5, 5) = any(members) or pg_temp.id(5, 6) = any(members) or pg_temp.id(5, 11) = any(members)
            or pg_temp.id(5, 12) = any(members)),
        'Staff read lists only active Members after ending');
    perform pg_temp.act(1);
    staff := public.get_organization_staff(pg_temp.id(3, 1));
    perform pg_temp.assert_true(exists (select 1 from jsonb_array_elements(staff -> 'pending_invitations') value
            where (value ->> 'invitation_id')::uuid = (select id from c_state where key = 'pending_by_2'))
        and (select revoked_at is null and acceptance_secret_digest is not null from public.organization_invitations
             where id = (select id from c_state where key = 'pending_by_2')),
        'A pending Invitation created by the ended Administrator stays pending');
    perform pg_temp.assert_true((select count(*) from public.organization_memberships m join public.organization_responsibility_grants g
            on g.membership_id = m.id where m.organization_id = pg_temp.id(3, 1) and m.effective_end is null
            and g.effective_end is null and g.responsibility = 'OWNER') = 2,
        'The Organization keeps its Owners after Staff offboarding');
    perform pg_temp.assert_true(not exists (select 1 from public.organization_memberships m join public.organization_responsibility_grants g
            on g.membership_id = m.id where m.effective_end is not null and (g.effective_end is null or g.effective_end > m.effective_end)),
        'No active Grant survives under an ended Membership');
end $$;

-- ---------------------------------------------------------------------------
-- Full lifecycle and rejoin: invite, accept, end, re-invite, accept again
-- (BR-15, BR-16; Notes 13, 14)
-- ---------------------------------------------------------------------------
do $$ declare first_invitation uuid; second_invitation uuid; first_membership uuid; second_membership uuid;
    first_period text; result jsonb; begin
    first_invitation := pg_temp.invite(1, 'rejoin@example.test', 'rejoin-secret-1');
    first_membership := (pg_temp.accept(14, first_invitation, 'rejoin-secret-1') ->> 'membership_id')::uuid;
    perform pg_temp.assert_true(first_membership = any(pg_temp.staff_member_ids(1, pg_temp.id(3, 1))),
        'Rejoin fixture: accepted Member is active Staff');
    result := pg_temp.end_json(1, first_membership);
    perform pg_temp.assert_true(result ->> 'outcome' = 'ENDED' and not (first_membership = any(pg_temp.staff_member_ids(1, pg_temp.id(3, 1))))
        and (select effective_end is not null and originating_invitation_id = first_invitation
             from public.organization_memberships where id = first_membership)
        and (select bool_and(effective_end is not null) from public.organization_responsibility_grants where membership_id = first_membership),
        'Accepted Member ended: absent from Staff, stored with its provenance and end');
    first_period := (select md5(to_jsonb(m)::text) from public.organization_memberships m where m.id = first_membership)
        || (select md5(jsonb_agg(to_jsonb(g) order by g.id)::text) from public.organization_responsibility_grants g where g.membership_id = first_membership);
    second_invitation := pg_temp.invite(1, 'rejoin@example.test', 'rejoin-secret-2');
    second_membership := (pg_temp.accept(14, second_invitation, 'rejoin-secret-2') ->> 'membership_id')::uuid;
    perform pg_temp.assert_true(second_membership is not null and second_membership <> first_membership
        and (select originating_invitation_id = second_invitation and effective_end is null
             from public.organization_memberships where id = second_membership)
        and (select count(*) from public.organization_memberships where user_id = pg_temp.id(2, 14)
             and organization_id = pg_temp.id(3, 1) and effective_end is null) = 1
        and second_membership = any(pg_temp.staff_member_ids(1, pg_temp.id(3, 1))),
        'Rejoining creates a new active Membership period with the new Invitation as provenance');
    perform pg_temp.assert_true((select md5(to_jsonb(m)::text) from public.organization_memberships m where m.id = first_membership)
            || (select md5(jsonb_agg(to_jsonb(g) order by g.id)::text) from public.organization_responsibility_grants g
                where g.membership_id = first_membership) = first_period,
        'The earlier period is never reactivated or rewritten');
end $$;

-- ---------------------------------------------------------------------------
-- Real authenticated role (mobile path), no path around the operation, and
-- serialization evidence on fresh rows.
-- ---------------------------------------------------------------------------
create extension pgrowlocks with schema extensions;
create function pg_temp.locked(relation regclass, row_id uuid, mode text) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return mode = any(coalesce(result, '{}'));
end $$;
-- Rows the operation updated report an update lock rather than For Update.
create function pg_temp.held(relation regclass, row_id uuid) returns boolean language plpgsql as $$
declare result text[]; begin
    execute format('select l.modes from extensions.pgrowlocks(%L) l join %s r on r.ctid = l.locked_row where r.id = $1',
        relation::text, relation) into result using row_id;
    return cardinality(coalesce(result, '{}')) > 0;
end $$;
create temporary table c_role_probe on commit drop as select pg_temp.id(5, 9) target;
grant select on c_role_probe to authenticated;
select pg_temp.assert_true(not pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 2), 'For Update')
    and not pg_temp.held('public.organization_memberships', pg_temp.id(5, 9))
    and not pg_temp.held('public.organization_responsibility_grants', pg_temp.id(6, 9)), 'Lock probes start unlocked');
select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(public.end_organization_staff_membership((select target from c_role_probe)) ->> 'outcome' = 'ENDED',
    'Authenticated role executes end access');
reset role;
select pg_temp.assert_true(pg_temp.locked('public.veterinary_organizations', pg_temp.id(3, 2), 'For Update')
    and pg_temp.held('public.organization_memberships', pg_temp.id(5, 9))
    and pg_temp.held('public.organization_responsibility_grants', pg_temp.id(6, 9)),
    'End access serializes on Organization, Membership and its active Grants');
select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(pg_temp.sqlstate_of(10, format('select public.end_organization_membership(%L)', pg_temp.id(5, 111))) = '42501',
    'Authenticated client cannot reach the generic end operation');
reset role;
select pg_temp.assert_true((select effective_end is null from public.organization_memberships where id = pg_temp.id(5, 111)),
    'The bypass attempt ended nothing');

set constraints all immediate;
set constraints all deferred;
rollback;

-- Regression suite for ADR-009 trusted Organization establishment
-- (SPEC-ORG-001 BR-5/BR-12/BR-14/BR-16 and §10, SPEC-SUB-001 §14),
-- migration 20261101090000_trusted_organization_establishment.sql.
--
-- Run only against an isolated database with all source-controlled migrations
-- applied. All fixtures (prefix d0320000-) and assertions are rolled back.
--
-- Covers: ACL and the removed create_veterinary_organization boundary; happy
-- paths (PENDING, open-ended ACTIVE, finite ACTIVE); Owner identity and BR-16
-- eligibility; input shape; initial Subscription policy; exact footprint and
-- one establishment instant; replay over requested inputs and contradictory
-- reuse of every material input; provider-reference replay of both
-- establishment operations; several Organizations per Owner and duplicate
-- names; legacy Organizations untouched; injected failure at every write step.
begin;
set local timezone = 'UTC';

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.subject(n integer) returns uuid language sql immutable as $$
    select ('d0320000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.key(n integer) returns uuid language sql immutable as $$
    select ('d0320000-0000-4000-8000-' || lpad((900 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.uid(n integer) returns uuid language sql stable as $$
    select identity_link.user_id from public.user_authentication_identities as identity_link
    where identity_link.provider_subject = pg_temp.subject(n)
$$;

-- Calls the trusted operation as the session role; an error is returned as
-- {error, hint, message} so every outcome is asserted by name.
create function pg_temp.establish(
    p_owner uuid, p_name text, p_key uuid, p_state text, p_effective timestamptz,
    p_from timestamptz, p_until timestamptz, p_source text, p_refs jsonb default null
) returns jsonb language plpgsql as $$
declare
    failure_state text; failure_hint text; failure_message text;
begin
    return public.establish_veterinary_organization(
        p_owner, p_name, p_key, p_state, p_effective, p_from, p_until, p_source, p_refs);
exception when others then
    get stacked diagnostics failure_state = returned_sqlstate, failure_hint = pg_exception_hint,
        failure_message = message_text;
    return jsonb_build_object('error', failure_state, 'hint', nullif(failure_hint, ''),
        'message', failure_message);
end;
$$;

create function pg_temp.is_error(p_result jsonb, p_state text, p_hint text default null)
returns boolean language sql immutable as $$
    select p_result ->> 'error' = p_state
       and (p_hint is null or p_result ->> 'hint' = p_hint)
       and p_result ->> 'organization_id' is null
$$;

-- Messages never carry an email, an Auth subject, an establishment key or a
-- provider reference.
create function pg_temp.is_quiet(p_result jsonb) returns boolean language sql immutable as $$
    select coalesce(p_result ->> 'message', '') !~ '(@|d0320000-|opaque-)'
$$;

create function pg_temp.footprint() returns bigint[] language sql as $$
    select array[
        (select count(*) from public.veterinary_organizations),
        (select count(*) from public.organization_memberships),
        (select count(*) from public.organization_responsibility_grants),
        (select count(*) from public.organization_subscriptions),
        (select count(*) from public.subscription_provider_references),
        (select count(*) from public.subscription_state_transitions),
        (select count(*) from public.clinics),
        (select count(*) from public.organization_invitations),
        (select count(*) from public.veterinarian_professional_profiles),
        (select count(*) from public.user_profiles)
    ]
$$;

-- Runs a statement as the given role and returns its SQLSTATE ('00000' on
-- success). The role is switched only inside the probe.
create function pg_temp.sqlstate_as(p_role text, p_statement text)
returns text language plpgsql as $$
begin
    execute format('set local role %I', p_role);
    begin
        execute p_statement;
    exception when others then
        reset role;
        return sqlstate;
    end;
    reset role;
    return '00000';
end;
$$;
grant execute on function pg_temp.sqlstate_as(text, text) to public;

create temporary table est_state (label text primary key, result jsonb not null) on commit drop;

-- 1 eligible (no Profile), 2 unconfirmed, 3 deleted, 4 anonymous,
-- 5 banned until the future, 6 ban already ended, 7 second eligible Owner,
-- 8 ban ending exactly at the establishment instant (set below),
-- 9 Owner of the legacy Organization.
insert into auth.users (id, email, email_confirmed_at, deleted_at, is_anonymous, banned_until) values
    (pg_temp.subject(1), 'est-1@example.test', '2020-01-01Z', null, false, null),
    (pg_temp.subject(2), 'est-2@example.test', null, null, false, null),
    (pg_temp.subject(3), 'est-3@example.test', '2020-01-01Z', '2025-01-01Z', false, null),
    (pg_temp.subject(4), null, '2020-01-01Z', null, true, null),
    (pg_temp.subject(5), 'est-5@example.test', '2020-01-01Z', null, false, '2999-01-01Z'),
    (pg_temp.subject(6), 'est-6@example.test', '2020-01-01Z', null, false, '2021-01-01Z'),
    (pg_temp.subject(7), 'est-7@example.test', '2020-01-01Z', null, false, null),
    (pg_temp.subject(8), 'est-8@example.test', '2020-01-01Z', null, false, null),
    (pg_temp.subject(9), 'est-9@example.test', '2020-01-01Z', null, false, null);

-- A domain User without any Auth mapping (incoherent identity).
insert into public.users (id) values ('d0320000-0000-4000-8000-000000000201');

-- A legacy Organization (no establishment key, no Subscription) with its
-- Owner, as created before this slice.
insert into public.veterinary_organizations (id, display_name)
values ('d0320000-0000-4000-8000-000000000301', 'EST Legacy Org');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
values ('d0320000-0000-4000-8000-000000000401', 'd0320000-0000-4000-8000-000000000301', pg_temp.uid(9), '2020-01-01Z');
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
values ('d0320000-0000-4000-8000-000000000501', 'd0320000-0000-4000-8000-000000000401', 'OWNER', 'ORGANIZATION', '2020-01-01Z', pg_temp.uid(9));

create temporary table legacy_before on commit drop as
select to_jsonb(organization.*) as organization_row,
    (select count(*) from public.organization_subscriptions where organization_id = organization.id) as subscriptions
from public.veterinary_organizations as organization
where organization.id = 'd0320000-0000-4000-8000-000000000301';

-- ===========================================================================
-- A. ACL and the removed boundary
-- ===========================================================================

select pg_temp.assert_true(
    has_function_privilege('service_role', 'public.establish_veterinary_organization(uuid,text,uuid,text,timestamptz,timestamptz,timestamptz,text,jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.establish_veterinary_organization(uuid,text,uuid,text,timestamptz,timestamptz,timestamptz,text,jsonb)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.establish_veterinary_organization(uuid,text,uuid,text,timestamptz,timestamptz,timestamptz,text,jsonb)', 'EXECUTE')
    and not has_function_privilege('public', 'public.establish_veterinary_organization(uuid,text,uuid,text,timestamptz,timestamptz,timestamptz,text,jsonb)', 'EXECUTE'),
    'EST:acl:service_role_only'
);

select pg_temp.assert_true(
    (select function_record.prosecdef
            and function_record.proconfig = array['search_path=""']
            and function_record.provolatile = 'v'
            and function_record.prorettype = 'jsonb'::regtype
     from pg_proc as function_record
     where function_record.oid = 'public.establish_veterinary_organization(uuid,text,uuid,text,timestamptz,timestamptz,timestamptz,text,jsonb)'::regprocedure),
    'EST:acl:security_definer_empty_search_path_volatile_jsonb'
);

select pg_temp.assert_true(
    to_regprocedure('public.create_veterinary_organization(text)') is null
    and not exists (select 1 from pg_proc where proname = 'create_veterinary_organization'),
    'EST:acl:former_boundary_removed'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from unnest(array[
            'public.canonical_subscription_provider_references(jsonb)',
            'public.stored_subscription_provider_references(uuid)',
            'public.assert_initial_owner_eligible(uuid,timestamptz)',
            'public.replay_veterinary_organization_establishment(public.veterinary_organizations,bytea)'
        ]) as helper(signature)
        cross join unnest(array['public', 'anon', 'authenticated', 'service_role']) as grantee(role_name)
        where has_function_privilege(grantee.role_name, helper.signature, 'EXECUTE')
    ),
    'EST:acl:private_helpers_not_executable'
);

select pg_temp.assert_true(
    has_function_privilege('service_role', 'public.establish_organization_subscription(uuid,uuid,text,timestamptz,timestamptz,timestamptz,text,uuid,jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.establish_organization_subscription(uuid,uuid,text,timestamptz,timestamptz,timestamptz,text,uuid,jsonb)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.establish_organization_subscription(uuid,uuid,text,timestamptz,timestamptz,timestamptz,text,uuid,jsonb)', 'EXECUTE'),
    'EST:acl:later_period_establishment_stays_service_role'
);

create temporary table acl_baseline on commit drop as select pg_temp.footprint() as value;

select set_config('request.jwt.claim.sub', pg_temp.subject(1)::text, true);
select pg_temp.assert_true(
    pg_temp.sqlstate_as('anon', format($$select public.establish_veterinary_organization(%L, 'EST Anon', %L, 'ACTIVE', null, null, null, 'est-suite')$$,
        pg_temp.uid(1), pg_temp.key(90))) = '42501'
    and pg_temp.sqlstate_as('authenticated', format($$select public.establish_veterinary_organization(%L, 'EST Authenticated', %L, 'ACTIVE', null, null, null, 'est-suite')$$,
        pg_temp.uid(1), pg_temp.key(91))) = '42501'
    and pg_temp.footprint() = (select value from acl_baseline),
    'EST:acl:client_roles_denied_without_writes'
);
select set_config('request.jwt.claim.sub', '', true);

select pg_temp.assert_true(
    pg_temp.sqlstate_as('service_role', format($$select public.establish_veterinary_organization(%L, 'EST Service Role Org', %L, 'PENDING', null, null, null, 'est-suite')$$,
        pg_temp.uid(7), pg_temp.key(92))) = '00000',
    'EST:acl:service_role_establishes'
);
-- Separate statement: an uncorrelated EXISTS in the expression above would be
-- evaluated before the call.
select pg_temp.assert_true(
    exists (select 1 from public.veterinary_organizations where establishment_idempotency_key = pg_temp.key(92)),
    'EST:acl:service_role_establishment_exists'
);

-- ===========================================================================
-- B. Happy paths, exact footprint and one establishment instant
-- ===========================================================================

do $$ declare
    t timestamptz := statement_timestamp();
    before bigint[] := pg_temp.footprint();
    r jsonb;
begin
    r := pg_temp.establish(pg_temp.uid(1), 'EST Pending Org', pg_temp.key(1), 'PENDING', null, null, null, 'est-suite');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED'
        and r ?& array['organization_id', 'owner_membership_id', 'subscription_id']
        and (select count(*) from jsonb_object_keys(r)) = 4,
        'EST:happy:pending_established');
    perform pg_temp.assert_true(pg_temp.footprint() = array[before[1] + 1, before[2] + 1, before[3] + 1, before[4] + 1,
            before[5], before[6], before[7], before[8], before[9], before[10]],
        'EST:footprint:exactly_one_organization_membership_grant_subscription');
    perform pg_temp.assert_true(
        (select display_name = 'EST Pending Org' and establishment_idempotency_key = pg_temp.key(1)
                and octet_length(establishment_request_digest) = 32
         from public.veterinary_organizations where id = (r ->> 'organization_id')::uuid),
        'EST:footprint:organization_records_name_and_key');
    perform pg_temp.assert_true(
        (select membership.organization_id = (r ->> 'organization_id')::uuid and membership.user_id = pg_temp.uid(1)
                and membership.effective_end is null and membership.originating_invitation_id is null
         from public.organization_memberships as membership where membership.id = (r ->> 'owner_membership_id')::uuid)
        and (select count(*) = 1 and bool_and(grant_record.responsibility = 'OWNER' and grant_record.scope_type = 'ORGANIZATION'
                and grant_record.clinic_id is null and grant_record.effective_end is null
                and grant_record.granted_by_user_id = pg_temp.uid(1))
             from public.organization_responsibility_grants as grant_record
             where grant_record.membership_id = (r ->> 'owner_membership_id')::uuid),
        'EST:footprint:owner_membership_and_single_active_owner_grant');
    perform pg_temp.assert_true(
        (select subscription.organization_id = (r ->> 'organization_id')::uuid and subscription.initial_state = 'PENDING'
                and subscription.initiated_by_user_id is null and subscription.establishment_source = 'est-suite'
                and subscription.establishment_idempotency_key = pg_temp.key(1)
                and subscription.initial_commercial_valid_from is null and subscription.initial_commercial_valid_until is null
         from public.organization_subscriptions as subscription where subscription.id = (r ->> 'subscription_id')::uuid),
        'EST:footprint:initial_subscription_as_requested');
    perform pg_temp.assert_true(
        (select membership.effective_start = t from public.organization_memberships as membership
         where membership.id = (r ->> 'owner_membership_id')::uuid)
        and (select bool_and(grant_record.effective_start = t) from public.organization_responsibility_grants as grant_record
             where grant_record.membership_id = (r ->> 'owner_membership_id')::uuid),
        'EST:temporal:membership_and_grant_share_t');
    perform pg_temp.assert_true(
        (select subscription.established_at = t and subscription.initial_state_effective_at = t
         from public.organization_subscriptions as subscription where subscription.id = (r ->> 'subscription_id')::uuid),
        'EST:temporal:subscription_established_at_t_and_omitted_effective_is_t');
    perform pg_temp.assert_true(
        not exists (select 1 from public.clinics where organization_id = (r ->> 'organization_id')::uuid)
        and not exists (select 1 from public.organization_responsibility_grants as grant_record
            join public.organization_memberships as membership on membership.id = grant_record.membership_id
            where membership.organization_id = (r ->> 'organization_id')::uuid and grant_record.responsibility <> 'OWNER')
        and not exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.uid(1))
        and not exists (select 1 from public.user_profiles where user_id = pg_temp.uid(1))
        and not exists (select 1 from public.organization_invitations where organization_id = (r ->> 'organization_id')::uuid),
        'EST:footprint:no_clinic_veterinarian_profile_or_invitation');
    perform pg_temp.assert_true(
        (select derived.current_state = 'PENDING'
         from public.derive_organization_subscription_current_state((r ->> 'subscription_id')::uuid) as derived)
        and not public.organization_has_professional_entitlement((r ->> 'organization_id')::uuid, 'APPOINTMENT_MANAGEMENT'),
        'EST:subscription:pending_grants_no_entitlement');
    perform pg_temp.assert_true(
        public.user_has_organization_capability(pg_temp.uid(1), (r ->> 'organization_id')::uuid, 'ORGANIZATION_CREATE_CLINICS')
        and public.user_has_organization_capability(pg_temp.uid(1), (r ->> 'organization_id')::uuid, 'ORGANIZATION_MANAGE_SUBSCRIPTION'),
        'EST:owner:capabilities_current_in_same_statement');
    insert into est_state values ('pending', r);
end $$;

do $$ declare
    t timestamptz := statement_timestamp();
    r jsonb;
begin
    r := pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, ' est-suite ',
        '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-c1"},
          {"provider":"billing-x","reference_kind":"SUBSCRIPTION","opaque_reference":" opaque-s1 "}]');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED'
        and (select initial_state = 'ACTIVE' and initial_commercial_valid_until is null and establishment_source = 'est-suite'
             from public.organization_subscriptions where id = (r ->> 'subscription_id')::uuid)
        and public.organization_has_professional_entitlement((r ->> 'organization_id')::uuid, 'APPOINTMENT_MANAGEMENT')
        and public.organization_has_professional_entitlement((r ->> 'organization_id')::uuid, 'CLINICAL_DOCUMENTATION'),
        'EST:happy:active_open_ended_established');
    perform pg_temp.assert_true(
        (select count(*) = 2
                and bool_and(reference.provider = 'billing-x' and reference.recorded_at = t)
                and array_agg(reference.reference_kind || ':' || reference.opaque_reference order by reference.reference_kind)
                    = array['CUSTOMER:opaque-c1', 'SUBSCRIPTION:opaque-s1']
         from public.subscription_provider_references as reference
         where reference.subscription_id = (r ->> 'subscription_id')::uuid),
        'EST:footprint:provider_references_as_requested');
    perform pg_temp.assert_true(
        not (r ?| array['establishment_idempotency_key', 'provider_references', 'state', 'establishment_source', 'email']),
        'EST:result:no_internal_commercial_data');
    insert into est_state values ('active_open', r);
end $$;

do $$ declare
    t timestamptz := statement_timestamp();
    r jsonb;
begin
    r := pg_temp.establish(pg_temp.uid(6), 'EST Active Finite Org', pg_temp.key(3), 'ACTIVE', t - interval '2 days',
        t - interval '2 days', t + interval '30 days', 'est-suite');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED'
        and (select initial_state_effective_at = t - interval '2 days' and established_at = t
                and initial_commercial_valid_from = t - interval '2 days'
                and initial_commercial_valid_until = t + interval '30 days'
             from public.organization_subscriptions where id = (r ->> 'subscription_id')::uuid)
        and public.organization_has_professional_entitlement((r ->> 'organization_id')::uuid, 'PROFESSIONAL_SCHEDULING'),
        'EST:happy:active_finite_with_earlier_effective_time');
    insert into est_state values ('active_finite', r);
end $$;

-- Explicit effective time equal to the establishment instant is accepted.
do $$ declare r jsonb; begin
    r := pg_temp.establish(pg_temp.uid(7), 'EST Exact Instant Org', pg_temp.key(4), 'ACTIVE', statement_timestamp(),
        null, null, 'est-suite');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED'
        and (select initial_state_effective_at = statement_timestamp()
             from public.organization_subscriptions where id = (r ->> 'subscription_id')::uuid),
        'EST:temporal:explicit_effective_at_t_accepted');
    insert into est_state values ('exact_instant', r);
end $$;

-- ===========================================================================
-- C. Owner identity and BR-16 eligibility
-- ===========================================================================

create temporary table identity_baseline on commit drop as select pg_temp.footprint() as value;

do $$ declare r jsonb; begin
    r := pg_temp.establish('d0320000-0000-4000-8000-0000000002ff', 'EST No User', pg_temp.key(10), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '28000', 'OWNER_IDENTITY_UNAVAILABLE') and pg_temp.is_quiet(r),
        'EST:identity:missing_domain_user_rejected');
    r := pg_temp.establish('d0320000-0000-4000-8000-000000000201', 'EST Unmapped', pg_temp.key(11), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '28000', 'OWNER_IDENTITY_UNAVAILABLE') and pg_temp.is_quiet(r),
        'EST:identity:incoherent_mapping_rejected');
    r := pg_temp.establish(pg_temp.uid(2), 'EST Unconfirmed', pg_temp.key(12), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '42501', 'OWNER_ACCOUNT_INELIGIBLE') and pg_temp.is_quiet(r),
        'EST:identity:unconfirmed_email_rejected');
    r := pg_temp.establish(pg_temp.uid(3), 'EST Deleted', pg_temp.key(13), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '42501', 'OWNER_ACCOUNT_INELIGIBLE') and pg_temp.is_quiet(r),
        'EST:identity:deleted_account_rejected');
    r := pg_temp.establish(pg_temp.uid(4), 'EST Anonymous', pg_temp.key(14), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '42501', 'OWNER_ACCOUNT_INELIGIBLE') and pg_temp.is_quiet(r),
        'EST:identity:anonymous_account_rejected');
    r := pg_temp.establish(pg_temp.uid(5), 'EST Banned', pg_temp.key(15), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '42501', 'OWNER_ACCOUNT_INELIGIBLE') and pg_temp.is_quiet(r),
        'EST:identity:currently_banned_account_rejected');
    perform pg_temp.assert_true(pg_temp.footprint() = (select value from identity_baseline),
        'EST:identity:rejections_write_nothing');
end $$;

-- A ban ending exactly at the establishment instant no longer disqualifies.
do $$ declare r jsonb; begin
    update auth.users set banned_until = statement_timestamp() where id = pg_temp.subject(8);
    r := pg_temp.establish(pg_temp.uid(8), 'EST Ban Ends Now', pg_temp.key(16), 'PENDING', null, null, null, 'est-suite');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED', 'EST:identity:ban_ending_at_t_accepted');
    update auth.users set banned_until = statement_timestamp() + interval '1 microsecond' where id = pg_temp.subject(8);
    r := pg_temp.establish(pg_temp.uid(8), 'EST Ban Ends Later', pg_temp.key(17), 'PENDING', null, null, null, 'est-suite');
    perform pg_temp.assert_true(pg_temp.is_error(r, '42501', 'OWNER_ACCOUNT_INELIGIBLE'),
        'EST:identity:ban_ending_after_t_rejected');
end $$;

-- Expired ban (Owner 6, section B) and no Profile (Owner 1) were accepted.
select pg_temp.assert_true(
    (select result ->> 'outcome' = 'ESTABLISHED' from est_state where label = 'active_finite')
    and not exists (select 1 from public.user_profiles where user_id in (pg_temp.uid(1), pg_temp.uid(6))),
    'EST:identity:expired_ban_and_absent_profile_accepted'
);

-- ===========================================================================
-- D. Input shape (22023) and initial Subscription policy (23514)
-- ===========================================================================

create temporary table shape_baseline on commit drop as select pg_temp.footprint() as value;

do $$ declare t timestamptz := statement_timestamp(); begin
    perform pg_temp.assert_true(
        pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', null, 'ACTIVE', null, null, null, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(null, 'EST Shape', pg_temp.key(20), 'ACTIVE', null, null, null, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), E' \t ', pg_temp.key(20), 'ACTIVE', null, null, null, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'TRIAL', null, null, null, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), null, null, null, null, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', '-infinity', null, null, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', null, t, t, 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', null, null, 'infinity', 'est-suite'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', null, null, null, ' '), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', null, null, null, 'est-suite',
            '{"provider":"p"}'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', null, null, null, 'est-suite',
            '[{"provider":"p","reference_kind":"PLAN","opaque_reference":"opaque-x"}]'), '22023')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Shape', pg_temp.key(20), 'ACTIVE', null, null, null, 'est-suite',
            '[{"provider":"p","reference_kind":"CUSTOMER","opaque_reference":"opaque-x"},
              {"provider":" p ","reference_kind":"CUSTOMER","opaque_reference":"opaque-x"}]'), '22023'),
        'EST:shape:invalid_inputs_rejected');
    perform pg_temp.assert_true(
        pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Policy', pg_temp.key(21), 'PAST_DUE', null, null, null, 'est-suite'), '23514', 'INITIAL_STATE_NOT_ALLOWED')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Policy', pg_temp.key(21), 'CANCELLED', null, null, null, 'est-suite'), '23514', 'INITIAL_STATE_NOT_ALLOWED')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Policy', pg_temp.key(21), 'EXPIRED', null, null, null, 'est-suite'), '23514', 'INITIAL_STATE_NOT_ALLOWED'),
        'EST:policy:invalid_initial_states_rejected');
    perform pg_temp.assert_true(
        pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Future', pg_temp.key(22), 'ACTIVE', t + interval '1 microsecond',
            null, null, 'est-suite'), '23514', 'FUTURE_EFFECTIVE_AT')
        and pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Future', pg_temp.key(22), 'PENDING', t + interval '1 day',
            null, null, 'est-suite'), '23514', 'FUTURE_EFFECTIVE_AT'),
        'EST:policy:future_initial_effective_time_rejected');
    perform pg_temp.assert_true(pg_temp.footprint() = (select value from shape_baseline)
        and not exists (select 1 from public.veterinary_organizations
                        where establishment_idempotency_key in (pg_temp.key(20), pg_temp.key(21), pg_temp.key(22))),
        'EST:shape:rejections_write_nothing');
end $$;

-- ===========================================================================
-- E. Idempotency: exact replay and contradictory reuse
-- ===========================================================================

create temporary table replay_baseline on commit drop as select pg_temp.footprint() as value;

-- A later statement is the lost-response retry.
select pg_temp.assert_true(
    (select pg_temp.establish(pg_temp.uid(1), '  EST Pending Org ', pg_temp.key(1), 'PENDING', null, null, null, 'est-suite')
        = jsonb_set(result, '{outcome}', '"ALREADY_ESTABLISHED"') from est_state where label = 'pending')
    and (select pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite',
            '[{"provider":"billing-x","reference_kind":"SUBSCRIPTION","opaque_reference":"opaque-s1"},
              {"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-c1"}]')
        = jsonb_set(result, '{outcome}', '"ALREADY_ESTABLISHED"') from est_state where label = 'active_open')
    and pg_temp.footprint() = (select value from replay_baseline),
    'EST:replay:exact_replay_returns_original_ids'
);

-- Replay supplying the requested explicit time (not "now") also matches.
select pg_temp.assert_true(
    (select pg_temp.establish(pg_temp.uid(6), 'EST Active Finite Org', pg_temp.key(3), 'ACTIVE',
            initial_state_effective_at, initial_commercial_valid_from, initial_commercial_valid_until, 'est-suite')
        ->> 'outcome' = 'ALREADY_ESTABLISHED'
     from public.organization_subscriptions where establishment_idempotency_key = pg_temp.key(3)),
    'EST:replay:explicit_effective_time_replays'
);

-- After a later transition the original establishment is still recognized.
do $$ declare r jsonb; begin
    perform public.apply_subscription_state_transition(
        ((select result from est_state where label = 'pending') ->> 'subscription_id')::uuid,
        'ACTIVE', statement_timestamp(), null, null, 'est-suite', 'activate-pending');
    r := pg_temp.establish(pg_temp.uid(1), 'EST Pending Org', pg_temp.key(1), 'PENDING', null, null, null, 'est-suite');
    perform pg_temp.assert_true(r = jsonb_set((select result from est_state where label = 'pending'), '{outcome}', '"ALREADY_ESTABLISHED"'),
        'EST:replay:after_later_transition_returns_original_result');
end $$;

do $$ declare
    refs constant jsonb := '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-c1"},
                             {"provider":"billing-x","reference_kind":"SUBSCRIPTION","opaque_reference":"opaque-s1"}]';
    stored_effective timestamptz;
    before bigint[] := pg_temp.footprint();
begin
    select initial_state_effective_at into stored_effective
    from public.organization_subscriptions where establishment_idempotency_key = pg_temp.key(2);

    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(7), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:different_owner');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Another Name', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:different_display_name');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'PENDING', null, null, null, 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:different_initial_state');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'EXPIRED', null, null, null, 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:disallowed_state_under_used_key_is_conflict');
    -- The stored effective time was resolved from an omitted request: an
    -- explicit value, even the identical instant, is a different request.
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', stored_effective, null, null, 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:explicit_versus_omitted_effective_time');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(6), 'EST Active Finite Org', pg_temp.key(3), 'ACTIVE', null,
            (select initial_commercial_valid_from from public.organization_subscriptions where establishment_idempotency_key = pg_temp.key(3)),
            (select initial_commercial_valid_until from public.organization_subscriptions where establishment_idempotency_key = pg_temp.key(3)),
            'est-suite'), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:omitted_versus_explicit_effective_time');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, '2020-01-01Z', null, 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:different_valid_from');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, '2999-01-01Z', 'est-suite', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:different_valid_until');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-other-source', refs), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:different_establishment_source');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite',
            '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-c1"}]'), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:provider_reference_removed');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite',
            refs || '[{"provider":"billing-y","reference_kind":"CUSTOMER","opaque_reference":"opaque-c2"}]'), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:provider_reference_added');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite',
            '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-c1"},
              {"provider":"billing-x","reference_kind":"SUBSCRIPTION","opaque_reference":"opaque-s9"}]'), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:provider_reference_changed');
    perform pg_temp.assert_true(pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite'), '23505', 'ESTABLISHMENT_KEY_CONFLICT'),
        'EST:conflict:provider_references_omitted');
    perform pg_temp.assert_true(pg_temp.is_quiet(pg_temp.establish(pg_temp.uid(7), 'EST Active Open Org', pg_temp.key(2), 'ACTIVE', null, null, null, 'est-suite', refs)),
        'EST:conflict:message_carries_no_key');
    perform pg_temp.assert_true(pg_temp.footprint() = before, 'EST:conflict:rejections_write_nothing');
end $$;

-- NULL and [] provider references are the same (empty) request.
select pg_temp.assert_true(
    pg_temp.establish(pg_temp.uid(1), 'EST Pending Org', pg_temp.key(1), 'PENDING', null, null, null, 'est-suite', '[]')
        ->> 'outcome' = 'ALREADY_ESTABLISHED',
    'EST:replay:empty_and_omitted_provider_references_match'
);

-- A key already used by a Subscription not established by this operation.
select public.establish_organization_subscription('d0320000-0000-4000-8000-000000000301', null, 'ACTIVE',
    statement_timestamp(), null, null, 'est-suite', pg_temp.key(50), null);
do $$ declare before bigint[] := pg_temp.footprint(); begin
    perform pg_temp.assert_true(
        pg_temp.is_error(pg_temp.establish(pg_temp.uid(1), 'EST Key Taken', pg_temp.key(50), 'ACTIVE', null, null, null, 'est-suite'),
            '23505', 'ESTABLISHMENT_KEY_CONFLICT')
        and pg_temp.footprint() = before,
        'EST:conflict:key_used_by_later_period_subscription');
end $$;

-- ===========================================================================
-- F. Later-period establishment: provider references join exact replay
-- ===========================================================================

do $$ declare
    t timestamptz := statement_timestamp();
    refs constant jsonb := '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-l1"},
                             {"provider":"billing-x","reference_kind":"SUBSCRIPTION","opaque_reference":"opaque-l2"}]';
    first_id uuid;
    failure_state text;
    accepted boolean;
begin
    -- The legacy Organization's period from section E is EXPIRED first, so a
    -- new period may be established.
    perform public.apply_subscription_state_transition(
        (select id from public.organization_subscriptions where establishment_idempotency_key = pg_temp.key(50)),
        'EXPIRED', t, null, null, 'est-suite', 'expire-legacy');
    first_id := public.establish_organization_subscription('d0320000-0000-4000-8000-000000000301', null, 'ACTIVE',
        t, null, null, 'est-suite', pg_temp.key(51), refs);
    perform pg_temp.assert_true(
        public.establish_organization_subscription('d0320000-0000-4000-8000-000000000301', null, 'ACTIVE',
            t, null, null, 'est-suite', pg_temp.key(51), refs) = first_id
        and public.establish_organization_subscription('d0320000-0000-4000-8000-000000000301', null, 'ACTIVE',
            t, null, null, 'est-suite', pg_temp.key(51),
            '[{"provider":" billing-x ","reference_kind":"SUBSCRIPTION","opaque_reference":"opaque-l2"},
              {"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-l1"}]') = first_id,
        'EST:later_period:identical_and_reordered_references_replay');
    foreach failure_state in array array['changed', 'added', 'removed', 'omitted'] loop
        begin
            perform public.establish_organization_subscription('d0320000-0000-4000-8000-000000000301', null, 'ACTIVE',
                t, null, null, 'est-suite', pg_temp.key(51),
                case failure_state
                    when 'changed' then '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-l1"},
                                          {"provider":"billing-x","reference_kind":"SUBSCRIPTION","opaque_reference":"opaque-l9"}]'::jsonb
                    when 'added' then refs || '[{"provider":"billing-y","reference_kind":"CUSTOMER","opaque_reference":"opaque-l3"}]'::jsonb
                    when 'removed' then '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-l1"}]'::jsonb
                    else null
                end);
            accepted := true;
        exception when unique_violation then
            accepted := false;
            perform pg_temp.assert_true(sqlerrm !~ 'd0320000-', 'EST:later_period:conflict_message_carries_no_key');
        end;
        perform pg_temp.assert_true(not accepted, 'EST:later_period:contradictory_references_rejected');
    end loop;
    perform pg_temp.assert_true(
        (select count(*) from public.subscription_provider_references where subscription_id = first_id) = 2,
        'EST:later_period:references_unchanged');
end $$;

-- ===========================================================================
-- G. Several Organizations per Owner, duplicate names, legacy untouched
-- ===========================================================================

do $$ declare r jsonb; begin
    r := pg_temp.establish(pg_temp.uid(1), 'EST Pending Org', pg_temp.key(5), 'ACTIVE', null, null, null, 'est-suite');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED'
        and r ->> 'organization_id' <> (select result ->> 'organization_id' from est_state where label = 'pending')
        and (select count(*) from public.veterinary_organizations where display_name = 'EST Pending Org') = 2,
        'EST:multiple:duplicate_display_name_is_a_distinct_organization');
    perform pg_temp.assert_true(
        (select count(distinct membership.organization_id) from public.organization_memberships as membership
         where membership.user_id = pg_temp.uid(1) and membership.effective_end is null) = 3
        and public.user_has_organization_capability(pg_temp.uid(1), (r ->> 'organization_id')::uuid, 'ORGANIZATION_CREATE_CLINICS')
        and public.user_has_organization_capability(pg_temp.uid(1),
            ((select result from est_state where label = 'pending') ->> 'organization_id')::uuid, 'ORGANIZATION_CREATE_CLINICS'),
        'EST:multiple:same_owner_owns_several_organizations');
end $$;

select pg_temp.assert_true(
    (select to_jsonb(organization.*) = (select organization_row from legacy_before)
            and organization.establishment_idempotency_key is null
     from public.veterinary_organizations as organization
     where organization.id = 'd0320000-0000-4000-8000-000000000301'),
    'EST:legacy:organization_row_untouched'
);

-- The establishment record is immutable; the display name is not part of it.
create function pg_temp.update_rejected(p_statement text) returns boolean language plpgsql as $$
begin
    execute p_statement;
    return false;
exception when check_violation then
    return true;
end;
$$;

select pg_temp.assert_true(pg_temp.update_rejected(format(
    'update public.veterinary_organizations set establishment_idempotency_key = %L where establishment_idempotency_key = %L',
    pg_temp.key(60), pg_temp.key(1))), 'EST:record:establishment_key_immutable');
select pg_temp.assert_true(pg_temp.update_rejected(format(
    'update public.veterinary_organizations set establishment_request_digest = sha256(''x''::bytea) where establishment_idempotency_key = %L',
    pg_temp.key(1))), 'EST:record:request_digest_immutable');
select pg_temp.assert_true(pg_temp.update_rejected(format(
    'update public.veterinary_organizations set establishment_idempotency_key = %L, establishment_request_digest = sha256(''x''::bytea) where id = %L',
    pg_temp.key(61), 'd0320000-0000-4000-8000-000000000301')), 'EST:record:legacy_organization_cannot_acquire_a_key');

-- ===========================================================================
-- H. Atomicity: an injected failure at any write step leaves nothing
-- ===========================================================================

create function pg_temp.inject_failure() returns trigger language plpgsql as $$
begin
    if current_setting('est.fail_at', true) = tg_table_name then
        raise exception 'EST injected failure' using errcode = 'P0901';
    end if;
    return new;
end;
$$;

create trigger est_fail_after_organization after insert on public.veterinary_organizations
    for each row execute function pg_temp.inject_failure();
create trigger est_fail_after_membership after insert on public.organization_memberships
    for each row execute function pg_temp.inject_failure();
create trigger est_fail_after_grant after insert on public.organization_responsibility_grants
    for each row execute function pg_temp.inject_failure();
create trigger est_fail_during_subscription before insert on public.organization_subscriptions
    for each row execute function pg_temp.inject_failure();
create trigger est_fail_during_references before insert on public.subscription_provider_references
    for each row execute function pg_temp.inject_failure();

do $$ declare
    step text;
    before bigint[] := pg_temp.footprint();
    r jsonb;
begin
    foreach step in array array['veterinary_organizations', 'organization_memberships',
            'organization_responsibility_grants', 'organization_subscriptions', 'subscription_provider_references'] loop
        perform set_config('est.fail_at', step, true);
        r := pg_temp.establish(pg_temp.uid(7), 'EST Atomic Org', pg_temp.key(70), 'ACTIVE', null, null, null, 'est-suite',
            '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-a1"}]');
        perform pg_temp.assert_true(pg_temp.is_error(r, 'P0901')
            and pg_temp.footprint() = before
            and not exists (select 1 from public.veterinary_organizations where establishment_idempotency_key = pg_temp.key(70))
            and not exists (select 1 from public.organization_subscriptions where establishment_idempotency_key = pg_temp.key(70)),
            'EST:atomicity:injected_failure_leaves_nothing:' || step);
    end loop;
    perform set_config('est.fail_at', '', true);
    -- Retrying the same key after the failures establishes normally.
    r := pg_temp.establish(pg_temp.uid(7), 'EST Atomic Org', pg_temp.key(70), 'ACTIVE', null, null, null, 'est-suite',
        '[{"provider":"billing-x","reference_kind":"CUSTOMER","opaque_reference":"opaque-a1"}]');
    perform pg_temp.assert_true(r ->> 'outcome' = 'ESTABLISHED'
        and pg_temp.footprint() = array[before[1] + 1, before[2] + 1, before[3] + 1, before[4] + 1, before[5] + 1,
            before[6], before[7], before[8], before[9], before[10]],
        'EST:atomicity:retry_after_failure_establishes_once');
end $$;

drop trigger est_fail_after_organization on public.veterinary_organizations;
drop trigger est_fail_after_membership on public.organization_memberships;
drop trigger est_fail_after_grant on public.organization_responsibility_grants;
drop trigger est_fail_during_subscription on public.organization_subscriptions;
drop trigger est_fail_during_references on public.subscription_provider_references;

-- Every Organization established by the operation has its Owner and initial
-- Subscription (the prospective BR-12 guarantee).
select pg_temp.assert_true(
    not exists (
        select 1 from public.veterinary_organizations as organization
        where organization.establishment_idempotency_key is not null
          and (not exists (select 1 from public.organization_subscriptions as subscription
                           where subscription.organization_id = organization.id
                             and subscription.establishment_idempotency_key = organization.establishment_idempotency_key)
               or not exists (select 1 from public.organization_memberships as membership
                              join public.organization_responsibility_grants as grant_record on grant_record.membership_id = membership.id
                              where membership.organization_id = organization.id and grant_record.responsibility = 'OWNER'
                                and grant_record.effective_end is null and membership.effective_end is null))
    ),
    'EST:invariant:every_established_organization_has_owner_and_subscription'
);

rollback;

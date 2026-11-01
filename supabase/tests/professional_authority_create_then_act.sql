-- Create-then-act regression for the shared professional-authority instant:
-- SPEC-ORG-001 BR-3, SPEC-ORG-003 BR-5 / section 10, SPEC-ORG-004 BR-13/BR-18,
-- SPEC-ORG-005 BR-25, SPEC-ORG-006; ADR-009 trusted establishment.
-- A Membership/Grant lifecycle change takes effect at its statement instant
-- (never earlier than the facts it supersedes), the same instant current
-- authority is evaluated against, so a relationship established earlier in a
-- statement is usable later in that statement. Real client-safe RPCs only
-- (SPEC-ORG-006 §14, SPEC-VET-001/004 §13, which delegate to the
-- statement-instant writers); fixture-only
-- states are limited to section H. Isolated LOCAL superuser, rollback-only.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.subject(n integer) returns uuid language sql immutable as $$
    select ('d0270000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;
create function pg_temp.uid(n integer) returns uuid language sql stable as $$
    select identity_link.user_id from public.user_authentication_identities as identity_link
    where identity_link.provider_subject = pg_temp.subject(n)
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.subject(n)::text, true),
           set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.subject(n), 'role', 'authenticated')::text, true)
$$;
-- SQLSTATE of a statement run as authenticated ('00000' on success).
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
create function pg_temp.footprint() returns bigint[] language sql as $$
    select array[
        (select count(*) from public.veterinary_organizations),
        (select count(*) from public.organization_memberships),
        (select count(*) from public.organization_responsibility_grants),
        (select count(*) from public.organization_subscriptions),
        (select count(*) from public.clinics),
        (select count(*) from public.clinic_public_profiles),
        (select count(*) from public.veterinarian_professional_profiles),
        (select count(*) from public.veterinarian_clinic_assignments)
    ]
$$;
create temporary table cta_state (key text primary key, id uuid not null) on commit drop;

-- 1 provisioning Owner, 2 invited Member X, 3 invited Member Y,
-- 4 Owner of the rolled-back establishment, 5 Owner of the split control.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.subject(n), 'cta-' || n || '@example.test', '2020-01-01Z' from generate_series(1, 5) n;

-- ===========================================================================
-- A. ADR-009 trusted establishment and provisioning in ONE top-level
--    statement: Organization + Owner + initial Subscription, then every next
--    authorized Organization/Clinic/Veterinarian step.
-- ===========================================================================
do $$ declare
    t timestamptz := statement_timestamp(); owner_id uuid := pg_temp.uid(1);
    v_org uuid; v_membership uuid; v_profile uuid; v_clinic uuid; v_assignment uuid; v_revision bigint;
    context jsonb;
begin
    -- Trusted atomic establishment (session role; no Owner impersonation).
    select (created ->> 'organization_id')::uuid, (created ->> 'owner_membership_id')::uuid into v_org, v_membership
    from public.establish_veterinary_organization(owner_id, 'CTA Provisioned Organization', pg_temp.subject(901),
        'ACTIVE', t - interval '1 day', null, t + interval '30 days', 'cta-suite', null) as created;
    perform pg_temp.act(1);
    perform pg_temp.assert_true(public.user_has_organization_capability(owner_id, v_org, 'ORGANIZATION_GRANT_RESPONSIBILITIES')
        and public.user_has_organization_capability(owner_id, v_org, 'ORGANIZATION_CREATE_CLINICS'),
        'CTA:provision:owner_current_in_same_statement');
    perform pg_temp.assert_true((select effective_start = t from public.organization_memberships where id = v_membership)
        and (select bool_and(effective_start = t) from public.organization_responsibility_grants where membership_id = v_membership),
        'CTA:provision:owner_effective_at_statement_instant');

    set local role authenticated;
    v_profile := public.create_my_veterinarian_professional_profile('CTA-CREDENTIAL-0001', 'CTA synthetic credential')
        ->> 'professional_profile_id';
    perform public.add_staff_responsibility(v_org, v_membership, 'VETERINARIAN', 'ORGANIZATION', null);
    reset role;
    perform pg_temp.assert_true(jsonb_array_length(public.get_my_professional_context()->'organizations'->0->'responsibilities') = 2,
        'CTA:provision:added_grant_current_in_same_statement');

    set local role authenticated;
    v_clinic := public.create_clinic(v_org, gen_random_uuid()) ->> 'clinic_id';
    perform public.set_clinic_location(v_clinic, 'Calle Ficticia 1, Madrid', 40.4168, -3.7038);
    perform public.set_clinic_public_profile(v_clinic, 'CTA Clinic', 'Synthetic create-then-act Clinic', null, null, null);
    perform public.set_clinic_scheduling_timezone(v_clinic, 'Europe/Madrid');
    perform public.publish_clinic(v_clinic);
    perform public.set_clinic_standard_appointment_duration(v_clinic, 30);
    perform public.replace_clinic_opening_hours(v_clinic, '[{"iso_weekday":1,"start_time":"09:00","end_time":"14:00"}]');
    select managed.weekly_appointment_availability_revision into v_revision
    from public.get_managed_clinic_appointment_availability(v_clinic) as managed;
    perform public.replace_clinic_appointment_availability(v_clinic,
        '[{"iso_weekday":1,"start_time":"09:00","end_time":"13:00"}]', v_revision);
    v_assignment := public.assign_staff_veterinarian_to_clinic(v_org, v_membership, v_clinic)
        ->> 'veterinarian_clinic_assignment_id';
    perform public.replace_veterinarian_availability(v_assignment,
        '[{"iso_weekday":1,"start_time":"09:00","end_time":"13:00"}]');
    reset role;

    perform pg_temp.assert_true((select bool_and(effective_start = t) from public.organization_responsibility_grants where membership_id = v_membership),
        'CTA:provision:veterinarian_grant_effective_at_statement_instant');
    perform pg_temp.assert_true(public.user_has_clinic_capability(owner_id, v_clinic, 'CLINICAL_CARE')
        and (select count(*) from public.find_current_veterinarian_context_after_lock(owner_id, v_clinic, 'CLINICAL_CARE')) = 1,
        'CTA:provision:veterinarian_context_current_in_same_statement');
    context := public.get_my_professional_context();
    perform pg_temp.assert_true(jsonb_array_length(context->'organizations') = 1
        and jsonb_array_length(context->'organizations'->0->'responsibilities') = 2
        and jsonb_array_length(context->'organizations'->0->'clinic_assignments') = 1
        and exists (select 1 from jsonb_array_elements(context->'organizations'->0->'capabilities') c
                    where c->>'capability' = 'ORGANIZATION_CREATE_CLINICS'),
        'CTA:provision:professional_context_in_same_statement');
    insert into cta_state values ('org', v_org), ('owner_membership', v_membership), ('clinic', v_clinic);
end $$;

-- ===========================================================================
-- B. The composite stays atomic: a late failure removes every step.
-- ===========================================================================
do $$ declare before bigint[] := pg_temp.footprint(); v_org uuid; v_membership uuid; begin
    begin
        select (created ->> 'organization_id')::uuid, (created ->> 'owner_membership_id')::uuid into v_org, v_membership
        from public.establish_veterinary_organization(pg_temp.uid(4), 'CTA Rolled Back Organization', pg_temp.subject(904),
            'PENDING', null, null, null, 'cta-suite', null) as created;
        perform pg_temp.act(4);
        set local role authenticated;
        perform public.create_my_veterinarian_professional_profile('CTA-CREDENTIAL-0004', 'CTA synthetic credential');
        perform public.add_staff_responsibility(v_org, v_membership, 'RECEPTIONIST', 'ORGANIZATION', null);
        perform public.set_clinic_public_profile((public.create_clinic(v_org, gen_random_uuid()) ->> 'clinic_id')::uuid, 'CTA Rolled Back Clinic', null, null, null, null);
        reset role;
        perform pg_temp.assert_true(pg_temp.footprint() <> before, 'CTA:atomicity:composite_wrote_before_failure');
        raise exception 'CTA injected late provisioning failure' using errcode = 'P0901';
    exception when sqlstate 'P0901' then
        null;
    end;
    perform pg_temp.assert_true(pg_temp.footprint() = before
        and not exists (select 1 from public.veterinary_organizations where display_name = 'CTA Rolled Back Organization'),
        'CTA:atomicity:injected_failure_rolls_back_every_step');
end $$;

-- ===========================================================================
-- C. Splitting equivalent work across statements behaves the same.
-- ===========================================================================
insert into cta_state select 'split_org', (public.establish_veterinary_organization(pg_temp.uid(5), 'CTA Split Organization',
    pg_temp.subject(905), 'PENDING', null, null, null, 'cta-suite', null) ->> 'organization_id')::uuid;
select pg_temp.act(5);
select pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.create_clinic(%L, gen_random_uuid())',
    (select id from cta_state where key = 'split_org'))) = '00000', 'CTA:split:later_statement_equivalent');

-- ===========================================================================
-- D. Invitation acceptance: the accepted Membership and Grants are usable in
--    the accepting statement (SPEC-ORG-003 BR-5: one acceptance instant).
-- ===========================================================================
insert into cta_state
select 'invitation_' || n, public.create_scoped_organization_invitation(
    pg_temp.uid(1), (select id from cta_state where key = 'org'), null, 'cta-' || n || '@example.test',
    '[{"responsibility":"RECEPTIONIST","scope_type":"ORGANIZATION","clinic_id":null}]'::jsonb,
    statement_timestamp() + interval '7 days', decode(repeat(lpad(n::text, 2, '0'), 32), 'hex'))
from generate_series(2, 3) n;

do $$ declare
    t timestamptz := statement_timestamp(); member_id uuid := pg_temp.uid(2);
    v_clinic uuid := (select id from cta_state where key = 'clinic'); v_membership uuid; context jsonb;
begin
    v_membership := public.accept_organization_invitation(member_id, (select id from cta_state where key = 'invitation_2'),
        decode(repeat('02', 32), 'hex'));
    perform pg_temp.assert_true(public.user_has_clinic_capability(member_id, v_clinic, 'APPOINTMENT_VIEW_SCHEDULE'),
        'CTA:accept:accepted_capability_current_in_same_statement');
    perform pg_temp.assert_true((select effective_start = t from public.organization_memberships where id = v_membership)
        and (select bool_and(effective_start = t) from public.organization_responsibility_grants where membership_id = v_membership),
        'CTA:accept:membership_and_grants_share_acceptance_instant');
    perform pg_temp.act(2);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.get_clinic_appointment_schedule(%L)', v_clinic)) = '00000',
        'CTA:accept:accepted_member_reads_schedule_in_same_statement');
    context := public.get_my_professional_context();
    perform pg_temp.assert_true(jsonb_array_length(context->'organizations') = 1
        and context->'organizations'->0->'responsibilities'->0->>'responsibility' = 'RECEPTIONIST',
        'CTA:accept:professional_context_in_same_statement');
    insert into cta_state values ('member_x', v_membership);
end $$;

-- ===========================================================================
-- E. Replacement: old Grant ends and the replacement starts at one instant,
--    and the replacement is usable in the same statement.
-- ===========================================================================
do $$ declare
    t timestamptz := statement_timestamp(); member_id uuid := pg_temp.uid(2);
    v_old uuid; v_new uuid; v_org uuid := (select id from cta_state where key = 'org');
begin
    select id into v_old from public.organization_responsibility_grants
    where membership_id = (select id from cta_state where key = 'member_x') and effective_end is null;
    perform pg_temp.act(1);
    set local role authenticated;
    v_new := public.replace_staff_responsibility(v_org, v_old, 'ADMINISTRATOR', 'ORGANIZATION', null)
        ->> 'responsibility_grant_id';
    reset role;
    perform pg_temp.assert_true(public.user_has_organization_capability(member_id, v_org, 'ORGANIZATION_CREATE_CLINICS'),
        'CTA:replace:replacement_current_in_same_statement');
    perform pg_temp.assert_true((select effective_end = t from public.organization_responsibility_grants where id = v_old)
        and (select effective_start = t and effective_end is null from public.organization_responsibility_grants where id = v_new),
        'CTA:replace:contiguous_at_statement_instant');
    perform pg_temp.act(2);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.create_clinic(%L, gen_random_uuid())', v_org)) = '00000',
        'CTA:replace:replacement_usable_in_same_statement');
    perform pg_temp.assert_true((select jsonb_agg(r->>'responsibility') from jsonb_array_elements(
        public.get_my_professional_context()->'organizations'->0->'responsibilities') r) = '["ADMINISTRATOR"]'::jsonb,
        'CTA:replace:superseded_grant_not_current');
end $$;

-- ===========================================================================
-- F. Acceptance then add Responsibility then use it, all in one statement.
-- ===========================================================================
do $$ declare
    t timestamptz := statement_timestamp(); member_id uuid := pg_temp.uid(3);
    v_org uuid := (select id from cta_state where key = 'org'); v_membership uuid; v_grant uuid;
begin
    v_membership := public.accept_organization_invitation(member_id, (select id from cta_state where key = 'invitation_3'),
        decode(repeat('03', 32), 'hex'));
    perform pg_temp.act(1);
    set local role authenticated;
    v_grant := public.add_staff_responsibility(v_org, v_membership, 'ADMINISTRATOR', 'ORGANIZATION', null)
        ->> 'responsibility_grant_id';
    reset role;
    perform pg_temp.assert_true((select effective_start = t from public.organization_responsibility_grants where id = v_grant),
        'CTA:add:grant_effective_at_statement_instant');
    perform pg_temp.act(3);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.create_clinic(%L, gen_random_uuid())', v_org)) = '00000',
        'CTA:add:added_grant_usable_in_same_statement');
    insert into cta_state values ('member_y', v_membership), ('member_y_admin', v_grant);
end $$;

-- ===========================================================================
-- G. Ending is immediate within the statement and records the same instant.
-- ===========================================================================
do $$ declare
    t timestamptz := statement_timestamp(); member_id uuid := pg_temp.uid(3);
    v_org uuid := (select id from cta_state where key = 'org'); v_membership uuid := (select id from cta_state where key = 'member_y');
    v_grant uuid := (select id from cta_state where key = 'member_y_admin');
begin
    perform pg_temp.act(1);
    set local role authenticated;
    perform public.end_staff_responsibility(v_org, v_grant);
    reset role;
    perform pg_temp.assert_true((select effective_end = t from public.organization_responsibility_grants where id = v_grant),
        'CTA:end_grant:effective_at_statement_instant');
    perform pg_temp.act(3);
    perform pg_temp.assert_true(pg_temp.sqlstate_as_authenticated(format('select public.create_clinic(%L, gen_random_uuid())', v_org)) = '42501',
        'CTA:end_grant:ended_grant_unusable_in_same_statement');
    perform pg_temp.act(1);
    set local role authenticated;
    perform public.end_organization_staff_membership(v_membership);
    reset role;
    perform pg_temp.assert_true((select effective_end = t from public.organization_memberships where id = v_membership)
        and (select bool_and(effective_end = t) from public.organization_responsibility_grants
             where membership_id = v_membership and effective_end >= t),
        'CTA:end_membership:membership_and_grants_end_at_statement_instant');
    perform pg_temp.act(3);
    perform pg_temp.assert_true(public.get_my_professional_context()->'organizations' = '[]'::jsonb
        and not public.user_has_clinic_capability(member_id, (select id from cta_state where key = 'clinic'), 'APPOINTMENT_VIEW_SCHEDULE'),
        'CTA:end_membership:no_authority_in_same_statement');
end $$;

-- ===========================================================================
-- H. Monotonic instant (fixture-only): a lifecycle change never records an
--    instant earlier than the start it supersedes, e.g. a row committed by a
--    concurrent statement that began later. Constraints therefore hold.
-- ===========================================================================
do $$ declare
    t timestamptz := statement_timestamp(); later timestamptz := statement_timestamp() + interval '1 day';
    v_membership uuid := (select id from cta_state where key = 'member_x'); v_old uuid; v_new uuid; outcome text;
begin
    select id into v_old from public.organization_responsibility_grants where membership_id = v_membership and effective_end is null;
    execute 'set local session_replication_role = replica';
    update public.organization_responsibility_grants set effective_start = later where id = v_old;
    execute 'set local session_replication_role = origin';
    perform pg_temp.act(1);
    outcome := pg_temp.sqlstate_as_authenticated(format(
        'select public.replace_staff_responsibility(%L, %L, ''RECEPTIONIST'', ''ORGANIZATION'', null)',
        (select id from cta_state where key = 'org'), v_old));
    select id into v_new from public.organization_responsibility_grants where membership_id = v_membership and effective_end is null;
    perform pg_temp.assert_true(outcome = '00000'
        and (select effective_end = later from public.organization_responsibility_grants where id = v_old)
        and (select effective_start = later from public.organization_responsibility_grants where id = v_new),
        'CTA:monotonic:replacement_never_precedes_superseded_grant');
    outcome := pg_temp.sqlstate_as_authenticated(format('select public.end_organization_staff_membership(%L)', v_membership));
    perform pg_temp.assert_true(outcome = '00000'
        and (select effective_end = later from public.organization_memberships where id = v_membership)
        and (select effective_end = later from public.organization_responsibility_grants where id = v_new),
        'CTA:monotonic:membership_end_never_precedes_active_grant');
end $$;

rollback;

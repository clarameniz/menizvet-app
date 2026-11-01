-- Cross-cutting regression independent of Staff: SPEC-ORG-005 BR-7/25,
-- ORG-007 BR-2/5, ORG-008 BR-2, ORG-004 BR-8/13, ORG-006 section 3,
-- VET-004 BR-3/18. Isolated LOCAL superuser, rollback-only.
-- Every exact-boundary check updates fixtures and invokes evaluators in the
-- SAME DO statement: t = statement_timestamp(), with no wall-clock window.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0260000-0000-4000-8000-' || lpad((kind * 100 + n)::text,12,'0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub',pg_temp.id(1,n)::text,true)
$$;
create function pg_temp.expect_denied(statement text, label text) returns void language plpgsql as $$ begin
    begin execute statement;
    exception when sqlstate '42501' then return;
    end;
    raise exception '%', label;
end $$;

set local session_replication_role = replica;
insert into auth.users (id,email,email_confirmed_at)
select pg_temp.id(1,n),'temporal-'||n||'@example.test','2020-01-01Z' from generate_series(1,8) n;
insert into public.users (id) select pg_temp.id(2,n) from generate_series(1,8) n;
insert into public.user_authentication_identities (user_id,provider_subject)
select pg_temp.id(2,n),pg_temp.id(1,n) from generate_series(1,8) n;
insert into public.veterinary_organizations (id,display_name) values
    (pg_temp.id(3,1),'Temporal authority'),(pg_temp.id(3,2),'Unrelated Organization');
insert into public.clinics (id,organization_id) values
    (pg_temp.id(4,1),pg_temp.id(3,1)),(pg_temp.id(4,2),pg_temp.id(3,1)),(pg_temp.id(4,3),pg_temp.id(3,2));
insert into public.organization_memberships (id,organization_id,user_id,effective_start)
select pg_temp.id(5,n),pg_temp.id(3,1),pg_temp.id(2,n),'2020-01-01Z' from generate_series(1,8) n;
insert into public.organization_responsibility_grants (id,membership_id,responsibility,scope_type,clinic_id,effective_start,granted_by_user_id)
select pg_temp.id(6,n),pg_temp.id(5,n),case n when 1 then 'OWNER' when 2 then 'ADMINISTRATOR'
    when 3 then 'RECEPTIONIST' when 4 then 'ADMINISTRATOR' when 5 then 'RECEPTIONIST'
    when 6 then 'VETERINARIAN' else 'RECEPTIONIST' end,
    case when n in (4,5) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (4,5) then pg_temp.id(4,1) end,'2020-01-01Z',pg_temp.id(2,1)
from generate_series(1,8) n;
insert into public.organization_responsibility_grants (id,membership_id,responsibility,scope_type,effective_start,granted_by_user_id)
values (pg_temp.id(6,17),pg_temp.id(5,7),'VETERINARIAN','ORGANIZATION','2020-01-01Z',pg_temp.id(2,1));
insert into public.veterinarian_professional_profiles (id,user_id) values (pg_temp.id(7,6),pg_temp.id(2,6));
insert into public.veterinarian_clinic_assignments (id,professional_profile_id,supporting_membership_id,clinic_id,effective_start)
values (pg_temp.id(8,6),pg_temp.id(7,6),pg_temp.id(5,6),pg_temp.id(4,1),'2020-01-01Z');
set local session_replication_role = origin;

-- All six role/scope paths, plus Membership/Grant combinations. Ends in the
-- future are structurally storable fixtures, not approved scheduled endings:
-- they MUST NOT count as current under Phase 1 (ORG-004 BR-13 / ORG-006 section 3).
do $$ declare
    t timestamptz := statement_timestamp(); n integer; scenario text; role text; scope text;
    member_current boolean; grant_current boolean; current_relationship boolean;
    organization_expected boolean; clinic_expected boolean; org_scoped_expected boolean;
    capability text; context jsonb; clinics jsonb; entry jsonb; label text;
begin
    execute 'set local session_replication_role = replica';
    for n in 1..6 loop
        select responsibility,scope_type into role,scope from public.organization_responsibility_grants where id=pg_temp.id(6,n);
        foreach scenario in array array['past','membership_boundary','grant_boundary','both_boundary','membership_future',
            'grant_future','both_future','membership_ended','grant_ended','membership_end_boundary','grant_end_boundary',
            'membership_end_future','grant_end_future'] loop
            update public.organization_memberships set
                effective_start=case when scenario in ('membership_boundary','both_boundary') then t
                    when scenario in ('membership_future','both_future') then t+interval '1 day' else t-interval '10 days' end,
                effective_end=case when scenario='membership_ended' then t-interval '1 day'
                    when scenario='membership_end_boundary' then t when scenario='membership_end_future' then t+interval '2 days' end,
                ended_by_user_id=case when scenario in ('membership_ended','membership_end_boundary','membership_end_future') then pg_temp.id(2,1) end
            where id=pg_temp.id(5,n);
            update public.organization_responsibility_grants set
                effective_start=case when scenario in ('grant_boundary','both_boundary') then t
                    when scenario in ('grant_future','both_future') then t+interval '1 day' else t-interval '10 days' end,
                effective_end=case when scenario='grant_ended' then t-interval '1 day'
                    when scenario='grant_end_boundary' then t when scenario='grant_end_future' then t+interval '2 days' end,
                ended_by_user_id=case when scenario in ('grant_ended','grant_end_boundary','grant_end_future') then pg_temp.id(2,1) end
            where id=pg_temp.id(6,n);
            member_current:=scenario not in ('membership_future','both_future','membership_ended','membership_end_boundary','membership_end_future');
            grant_current:=scenario not in ('grant_future','both_future','grant_ended','grant_end_boundary','grant_end_future');
            current_relationship:=member_current and grant_current;
            organization_expected:=current_relationship and n in (1,2);
            clinic_expected:=current_relationship;
            org_scoped_expected:=current_relationship and n in (1,2,3);
            label:='TA:matrix:'||role||':'||scope||':'||scenario||':';

            -- Every Organization catalog capability shares the corrected evaluator.
            for capability in select c.capability from public.professional_capability_catalog() c where capability_context='ORGANIZATION' loop
                perform pg_temp.assert_true(public.user_has_organization_capability(pg_temp.id(2,n),pg_temp.id(3,1),capability)=organization_expected,label||'organization');
            end loop;
            perform pg_temp.assert_true(public.user_has_organization_scoped_clinic_capability(pg_temp.id(2,n),pg_temp.id(3,1),'APPOINTMENT_VIEW_SCHEDULE')=org_scoped_expected,label||'clinic_org');
            perform pg_temp.assert_true(public.user_has_clinic_scoped_clinic_capability(pg_temp.id(2,n),pg_temp.id(4,1),'APPOINTMENT_VIEW_SCHEDULE')=(current_relationship and n in (4,5,6)),label||'clinic_scoped');
            perform pg_temp.assert_true(public.user_has_clinic_capability(pg_temp.id(2,n),pg_temp.id(4,1),'APPOINTMENT_VIEW_SCHEDULE')=clinic_expected,label||'clinic');
            perform pg_temp.assert_true(not public.user_has_clinic_capability(pg_temp.id(2,n),pg_temp.id(4,3),'APPOINTMENT_VIEW_SCHEDULE'),label||'cross_organization');
            perform pg_temp.assert_true(public.user_has_clinic_capability(pg_temp.id(2,n),pg_temp.id(4,2),'APPOINTMENT_VIEW_SCHEDULE')=org_scoped_expected,label||'second_clinic');
            perform pg_temp.assert_true(public.user_has_clinic_capability(pg_temp.id(2,n),pg_temp.id(4,1),'CLINIC_MANAGE_PUBLIC_PROFILE')=(current_relationship and n in (1,2,4)),label||'clinic_management');
            perform pg_temp.assert_true(public.user_has_clinic_capability(pg_temp.id(2,n),pg_temp.id(4,1),'CLINICAL_CARE')=(current_relationship and n=6),label||'clinical');
            perform pg_temp.assert_true(public.user_has_continuous_clinic_reschedule_authority_since(pg_temp.id(2,n),pg_temp.id(4,1),t)=(current_relationship and n<>6),label||'continuous');

            if n=6 then
                -- Assignment currentness depends on Membership, not on a
                -- VETERINARIAN Grant; actual capability additionally needs that Grant.
                perform pg_temp.assert_true(public.veterinarian_clinic_assignment_is_current(pg_temp.id(8,6))=member_current,label||'assignment_membership');
                perform pg_temp.assert_true((select count(*) from public.find_current_veterinarian_context_after_lock(pg_temp.id(2,n),pg_temp.id(4,1),'CLINICAL_CARE'))=case when current_relationship then 1 else 0 end,label||'find_veterinarian');
                if current_relationship then
                    perform pg_temp.assert_true((select organization_membership_id from public.resolve_current_veterinarian_context_after_lock(pg_temp.id(2,n),pg_temp.id(4,1),'CLINICAL_CARE'))=pg_temp.id(5,n),label||'resolve_veterinarian');
                else
                    perform pg_temp.expect_denied(format('select public.resolve_current_veterinarian_context_after_lock(%L,%L,''CLINICAL_CARE'')',pg_temp.id(2,n),pg_temp.id(4,1)),label||'resolve_veterinarian');
                end if;
            end if;

            perform pg_temp.act(n);
            context:=public.get_my_professional_context();
            entry:=context->'organizations'->0;
            if not member_current then
                perform pg_temp.assert_true(context->'organizations'='[]'::jsonb,label||'context_membership');
            else
                perform pg_temp.assert_true(jsonb_array_length(context->'organizations')=1,label||'context_membership');
                perform pg_temp.assert_true(jsonb_array_length(entry->'responsibilities')=case when grant_current then 1 else 0 end,label||'context_grant');
                perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(entry->'capabilities') c where c->>'capability' like 'ORGANIZATION_%')=organization_expected,label||'context_organization');
                perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(entry->'capabilities') c where c->>'capability'='APPOINTMENT_VIEW_SCHEDULE')=clinic_expected,label||'context_clinic');
                if n=6 then perform pg_temp.assert_true(jsonb_array_length(entry->'clinic_assignments')=case when member_current then 1 else 0 end,label||'context_assignment'); end if;
            end if;
            clinics:=public.get_my_professional_clinics();
            perform pg_temp.assert_true(jsonb_array_length(clinics->'clinics')=case when not current_relationship then 0 when org_scoped_expected then 2 else 1 end,label||'professional_clinics');
        end loop;
        update public.organization_memberships set effective_start='2020-01-01Z',effective_end=null,ended_by_user_id=null where id=pg_temp.id(5,n);
        update public.organization_responsibility_grants set effective_start='2020-01-01Z',effective_end=null,ended_by_user_id=null where id=pg_temp.id(6,n);
    end loop;
    execute 'set local session_replication_role = origin';
end $$;

-- Bare current Membership returns no capability/Clinic; independent Profile
-- existence remains visible by ORG-007, not treated as authority.
set local session_replication_role = replica;
delete from public.organization_responsibility_grants where membership_id=pg_temp.id(5,8);
set local session_replication_role = origin;
select pg_temp.act(8);
select pg_temp.assert_true(public.get_my_professional_context()->'organizations'->0->'capabilities'='[]'::jsonb
    and public.get_my_professional_clinics()->'clinics'='[]'::jsonb,'TA:bare_membership');

-- A separate current ADMINISTRATOR Grant may legitimately provide Appointment
-- capability, but it must never make a FUTURE VETERINARIAN Grant usable as the
-- professional context. Pin the resolvers' own Grant predicates independently
-- of the general capability gate (which intentionally succeeds in this case).
do $$ declare t timestamptz:=statement_timestamp(); begin
    execute 'set local session_replication_role = replica';
    update public.organization_responsibility_grants set effective_start=t+interval '1 day' where id=pg_temp.id(6,6);
    insert into public.organization_responsibility_grants (id,membership_id,responsibility,scope_type,effective_start,granted_by_user_id)
    values (pg_temp.id(6,26),pg_temp.id(5,6),'ADMINISTRATOR','ORGANIZATION',t-interval '1 day',pg_temp.id(2,1));
    perform pg_temp.assert_true(public.user_has_organization_capability(pg_temp.id(2,6),pg_temp.id(3,1),'ORGANIZATION_INVITE_MEMBERS')
        and public.user_has_clinic_capability(pg_temp.id(2,6),pg_temp.id(4,1),'APPOINTMENT_VIEW_SCHEDULE')
        and not public.user_has_clinic_capability(pg_temp.id(2,6),pg_temp.id(4,1),'CLINICAL_CARE'),'TA:mixed_grants_independent_capabilities');
    perform pg_temp.assert_true((select count(*) from public.find_current_veterinarian_context_after_lock(pg_temp.id(2,6),pg_temp.id(4,1),'APPOINTMENT_VIEW_SCHEDULE'))=0,'TA:mixed_future_veterinarian_find');
    perform pg_temp.expect_denied(format('select public.resolve_current_veterinarian_context_after_lock(%L,%L,''APPOINTMENT_VIEW_SCHEDULE'')',pg_temp.id(2,6),pg_temp.id(4,1)),'TA:mixed_future_veterinarian_resolve');
    update public.organization_responsibility_grants set effective_start='2020-01-01Z' where id=pg_temp.id(6,6);
    delete from public.organization_responsibility_grants where id=pg_temp.id(6,26);
    execute 'set local session_replication_role = origin';
end $$;

-- Historical continuity alone must not authorize a future actor, even when
-- the requested historical boundary is itself future. A current-at-t check
-- precedes the intentionally historical interval-coverage model.
do $$ declare t timestamptz:=statement_timestamp(); begin
    execute 'set local session_replication_role = replica';
    update public.organization_memberships set effective_start=t+interval '1 day' where id=pg_temp.id(5,3);
    perform pg_temp.assert_true(not public.user_has_continuous_clinic_reschedule_authority_since(pg_temp.id(2,3),pg_temp.id(4,1),t+interval '2 days'),'TA:continuous_future_actor');
    update public.organization_memberships set effective_start='2020-01-01Z' where id=pg_temp.id(5,3);
    execute 'set local session_replication_role = origin';
end $$;

-- Existing consumers: future actor Membership and future actor Grant must
-- both fail authorization with no successful operation. Inputs/targets are
-- coherent; errors from setup or other validation do not count as denials.
do $$ declare scenario text; statement text; label text; t timestamptz:=statement_timestamp(); begin
    perform pg_temp.act(1);
    foreach scenario in array array['membership_future','grant_future','membership_end_future','grant_end_future'] loop
        execute 'set local session_replication_role = replica';
        update public.organization_memberships set effective_start=case when scenario='membership_future' then t+interval '1 day' else '2020-01-01Z'::timestamptz end,
            effective_end=case when scenario='membership_end_future' then t+interval '2 days' end,
            ended_by_user_id=case when scenario='membership_end_future' then pg_temp.id(2,1) end where id=pg_temp.id(5,1);
        update public.organization_responsibility_grants set effective_start=case when scenario='grant_future' then t+interval '1 day' else '2020-01-01Z'::timestamptz end,
            effective_end=case when scenario='grant_end_future' then t+interval '2 days' end,
            ended_by_user_id=case when scenario='grant_end_future' then pg_temp.id(2,1) end where id=pg_temp.id(6,1);
        execute 'set local session_replication_role = origin';

        statement:=format('select public.create_scoped_organization_invitation(%L,%L,null,''temporal-invite@example.test'',''[{"responsibility":"RECEPTIONIST","scope_type":"ORGANIZATION","clinic_id":null}]''::jsonb,%L,decode(repeat(''ab'',32),''hex''))',pg_temp.id(2,1),pg_temp.id(3,1),t+interval '7 days');
        perform pg_temp.expect_denied(statement,'TA:write:invitation:'||scenario);
        perform pg_temp.expect_denied(format('select public.end_organization_membership(%L)',pg_temp.id(5,7)),'TA:write:end_membership:'||scenario);
        perform pg_temp.expect_denied(format('select public.add_organization_responsibility(%L,''ADMINISTRATOR'',''ORGANIZATION'',null)',pg_temp.id(5,7)),'TA:write:add_responsibility:'||scenario);
        perform pg_temp.expect_denied(format('select public.replace_organization_responsibility(%L,''ADMINISTRATOR'',''ORGANIZATION'',null)',pg_temp.id(6,7)),'TA:write:replace_responsibility:'||scenario);
        perform pg_temp.expect_denied(format('select public.end_organization_responsibility(%L)',pg_temp.id(6,7)),'TA:write:end_responsibility:'||scenario);
        perform pg_temp.expect_denied(format('select public.create_clinic(%L, gen_random_uuid())',pg_temp.id(3,1)),'TA:write:create_clinic:'||scenario);
        statement:=format('select public.establish_organization_subscription(%L,%L,''ACTIVE'',''2020-01-01Z'',null,null,''temporal-suite'',%L,null)',pg_temp.id(3,1),pg_temp.id(2,1),pg_temp.id(9,1));
        perform pg_temp.expect_denied(statement,'TA:write:subscription:'||scenario);
        perform pg_temp.expect_denied(format('select public.set_clinic_public_profile(%L,''Forbidden future edit'',null,null,null,null)',pg_temp.id(4,1)),'TA:write:clinic_profile:'||scenario);
        perform pg_temp.expect_denied(format('select public.get_managed_clinic_profile(%L)',pg_temp.id(4,1)),'TA:read:clinic_profile:'||scenario);
        perform pg_temp.expect_denied(format('select public.get_clinic_appointment_schedule(%L)',pg_temp.id(4,1)),'TA:read:appointment_schedule:'||scenario);
    end loop;
    execute 'set local session_replication_role = replica';
    update public.organization_memberships set effective_start='2020-01-01Z',effective_end=null,ended_by_user_id=null where id=pg_temp.id(5,1);
    update public.organization_responsibility_grants set effective_start='2020-01-01Z',effective_end=null,ended_by_user_id=null where id=pg_temp.id(6,1);
    execute 'set local session_replication_role = origin';
end $$;

-- Positive controls execute the SAME operations with the now-current Owner.
-- Each operation is isolated in a rolled-back subtransaction so target state
-- remains usable by subsequent controls (and no Communication is committed).
create function pg_temp.expect_success(statement text,label text) returns void language plpgsql as $$ begin
    begin
        execute statement;
        raise exception using errcode='Z0001';
    exception when sqlstate 'Z0001' then return;
    end;
    raise exception '%',label;
end $$;
select pg_temp.act(1);
select pg_temp.expect_success(format('select public.create_scoped_organization_invitation(%L,%L,null,''positive@example.test'',''[{"responsibility":"RECEPTIONIST","scope_type":"ORGANIZATION","clinic_id":null}]''::jsonb,%L,decode(repeat(''ab'',32),''hex''))',pg_temp.id(2,1),pg_temp.id(3,1),statement_timestamp()+interval '7 days'),'TA:positive:invitation');
select pg_temp.expect_success(format('select public.end_organization_membership(%L)',pg_temp.id(5,7)),'TA:positive:end_membership');
select pg_temp.expect_success(format('select public.add_organization_responsibility(%L,''ADMINISTRATOR'',''ORGANIZATION'',null)',pg_temp.id(5,7)),'TA:positive:add_responsibility');
select pg_temp.expect_success(format('select public.replace_organization_responsibility(%L,''ADMINISTRATOR'',''ORGANIZATION'',null)',pg_temp.id(6,7)),'TA:positive:replace_responsibility');
select pg_temp.expect_success(format('select public.end_organization_responsibility(%L)',pg_temp.id(6,7)),'TA:positive:end_responsibility');
select pg_temp.expect_success(format('select public.create_clinic(%L, gen_random_uuid())',pg_temp.id(3,1)),'TA:positive:create_clinic');
select pg_temp.expect_success(format('select public.establish_organization_subscription(%L,%L,''ACTIVE'',''2020-01-01Z'',null,null,''temporal-suite'',%L,null)',pg_temp.id(3,1),pg_temp.id(2,1),pg_temp.id(9,1)),'TA:positive:subscription');
select pg_temp.expect_success(format('select public.set_clinic_public_profile(%L,''Current edit'',null,null,null,null)',pg_temp.id(4,1)),'TA:positive:clinic_profile');
select pg_temp.expect_success(format('select public.get_managed_clinic_profile(%L)',pg_temp.id(4,1)),'TA:positive:clinic_profile_read');
select pg_temp.expect_success(format('select public.get_clinic_appointment_schedule(%L)',pg_temp.id(4,1)),'TA:positive:schedule_read');

-- Representative role breadth for the same consumer rule (not every consumer
-- for every role): Organization ADMINISTRATOR (2), Clinic-scoped
-- ADMINISTRATOR (4) and Clinic-scoped RECEPTIONIST (5) on Clinic 4/1.
create function pg_temp.role_operations(n integer) returns text[] language sql as $$
    select case n
        when 2 then array[format('select public.create_clinic(%L, gen_random_uuid())',pg_temp.id(3,1)),
            format('select public.create_scoped_organization_invitation(%L,%L,null,''temporal-role@example.test'',''[{"responsibility":"RECEPTIONIST","scope_type":"ORGANIZATION","clinic_id":null}]''::jsonb,%L,decode(repeat(''cd'',32),''hex''))',
                pg_temp.id(2,2),pg_temp.id(3,1),statement_timestamp()+interval '7 days')]
        when 4 then array[format('select public.set_clinic_public_profile(%L,''Clinic-scoped edit'',null,null,null,null)',pg_temp.id(4,1)),
            format('select public.get_managed_clinic_profile(%L)',pg_temp.id(4,1))]
        else array[format('select public.get_clinic_appointment_schedule(%L)',pg_temp.id(4,1))]
    end
$$;
do $$ declare n integer; scenario text; operation text; t timestamptz:=statement_timestamp(); begin
    foreach n in array array[2,4,5] loop
        perform pg_temp.act(n);
        foreach scenario in array array['membership_future','grant_future'] loop
            execute 'set local session_replication_role = replica';
            update public.organization_memberships set effective_start=case when scenario='membership_future' then t+interval '1 day' else '2020-01-01Z'::timestamptz end where id=pg_temp.id(5,n);
            update public.organization_responsibility_grants set effective_start=case when scenario='grant_future' then t+interval '1 day' else '2020-01-01Z'::timestamptz end where id=pg_temp.id(6,n);
            execute 'set local session_replication_role = origin';
            foreach operation in array pg_temp.role_operations(n) loop
                perform pg_temp.expect_denied(operation,'TA:role:'||n||':'||scenario||':'||split_part(split_part(operation,'public.',2),'(',1));
            end loop;
        end loop;
        execute 'set local session_replication_role = replica';
        update public.organization_memberships set effective_start='2020-01-01Z' where id=pg_temp.id(5,n);
        update public.organization_responsibility_grants set effective_start='2020-01-01Z' where id=pg_temp.id(6,n);
        execute 'set local session_replication_role = origin';
        foreach operation in array pg_temp.role_operations(n) loop
            perform pg_temp.expect_success(operation,'TA:role:'||n||':positive:'||split_part(split_part(operation,'public.',2),'(',1));
        end loop;
    end loop;
end $$;
rollback;

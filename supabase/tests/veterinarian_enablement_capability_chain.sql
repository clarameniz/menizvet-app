-- Staff Responsibility Editing + Veterinarian Enablement Phase 1: the full
-- workforce capability chain through the real client-safe operations
-- (SPEC-ORG-005 §6/§11, SPEC-ORG-002 BR-17, SPEC-ORG-006 §14, SPEC-VET-001
-- §13, SPEC-VET-004 §13, SPEC-VET-005 §13, SPEC-VET-006, SPEC-ORG-004 §10).
-- Veterinarian-derived capability exists exactly at Clinics with a current
-- Assignment, only while the Membership, the VETERINARIAN Grant and the
-- Profile are all present. Isolated LOCAL superuser; rollback-only.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0333000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(1, n)::text, true)
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
create function pg_temp.kind(result text) returns text language sql immutable as $$
    select case when result like '{%' then result::jsonb ->> 'outcome'
                else split_part(result, ':', 1) || ':' || split_part(result, ':', 2) end
$$;
-- A failure where success is expected becomes {"error": ...}, so assertions
-- (not casts) report it.
create function pg_temp.json(result text) returns jsonb language sql immutable as $$
    select case when result like '{%' then result::jsonb else jsonb_build_object('error', result) end
$$;
-- The Veterinarian-derived Clinic capabilities (SPEC-ORG-005 §6) held at a Clinic.
create function pg_temp.vet_caps(n integer, clinic uuid) returns text[] language sql as $$
    select coalesce(array_agg(capability order by capability), '{}')
    from unnest(array['APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION']) capability
    where public.user_has_clinic_capability(pg_temp.id(2, n), clinic, capability)
$$;
create function pg_temp.all_caps() returns text[] language sql immutable as $$
    select array['APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION']
$$;
-- The resolver the clinical operations (create_appointment_clinical_entry) use.
create function pg_temp.clinical_context(n integer, clinic uuid) returns bigint language sql as $$
    select count(*) from public.find_current_veterinarian_context_after_lock(pg_temp.id(2, n), clinic, 'CLINICAL_DOCUMENTATION')
$$;
create function pg_temp.workforce_member(n integer) returns jsonb language plpgsql as $$
declare payload jsonb; begin
    perform pg_temp.act(2);
    payload := public.get_organization_veterinarian_workforce(pg_temp.id(3, 1));
    return (select value from jsonb_array_elements(payload -> 'members') where value ->> 'membership_id' = pg_temp.id(5, n)::text);
end $$;
create function pg_temp.grant_of(n integer, role text) returns uuid language sql as $$
    select id from public.organization_responsibility_grants
    where membership_id = pg_temp.id(5, n) and responsibility = role and effective_end is null
$$;
create function pg_temp.untouched_state() returns text language sql as $$
    select md5(coalesce((select jsonb_agg(to_jsonb(v) order by v.id)::text from public.appointment_veterinarian_assignments v), '')
        || coalesce((select jsonb_agg(to_jsonb(a) order by a.id)::text from public.appointments a), '')
        || coalesce((select jsonb_agg(to_jsonb(v) order by to_jsonb(v)::text)::text from public.veterinarian_availability_periods v), '')
        || coalesce((select jsonb_agg(to_jsonb(e) order by e.id)::text from public.clinical_record_entries e), '')
        || coalesce((select jsonb_agg(to_jsonb(e) order by e.id)::text from public.clinical_record_entries e), ''))
$$;
create function pg_temp.bytes(n integer) returns bytea language sql volatile as $$
    select decode(substr(md5(random()::text) || md5(random()::text), 1, 2 * n), 'hex')
$$;

set local session_replication_role = replica;
-- Organization A id(3,1), Clinics A1 id(4,1), A2 id(4,2), A3 id(4,3).
-- 1 Owner; 2 Organization Administrator; 15 chain subject (ADMINISTRATOR@A3
-- only, so it never holds Veterinarian-derived capability at A1/A2 by
-- itself); 16 invitee who joins directly as VETERINARIAN; 17 RECEPTIONIST
-- with a Profile and a legacy A1 Assignment but no VETERINARIAN Grant.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'chain-' || n || '@example.test', '2020-01-01Z' from unnest(array[1, 2, 15, 16, 17]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 2, 15, 16, 17]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 2, 15, 16, 17]) n;
insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, 1), 'Chain Org');
insert into public.clinics (id, organization_id) values
    (pg_temp.id(4, 1), pg_temp.id(3, 1)), (pg_temp.id(4, 2), pg_temp.id(3, 1)), (pg_temp.id(4, 3), pg_temp.id(3, 1));
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n), pg_temp.id(3, 1), pg_temp.id(2, n), '2020-01-01Z' from unnest(array[1, 2, 15, 17]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id) values
    (pg_temp.id(6, 1), pg_temp.id(5, 1), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 2), pg_temp.id(5, 2), 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 15), pg_temp.id(5, 15), 'ADMINISTRATOR', 'CLINIC', pg_temp.id(4, 3), '2020-01-01Z', pg_temp.id(2, 1)),
    (pg_temp.id(6, 17), pg_temp.id(5, 17), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 1));
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(7, 17), pg_temp.id(2, 17));
insert into public.veterinarian_professional_credentials (professional_profile_id, registration_identifier, issuing_context)
values (pg_temp.id(7, 17), 'CHAIN-17', 'Colegio');
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values (pg_temp.id(8, 17), pg_temp.id(7, 17), pg_temp.id(5, 17), pg_temp.id(4, 1), '2020-01-01Z');
set local session_replication_role = origin;
create temporary table c_state (key text primary key, id uuid not null) on commit drop;
create temporary table c_untouched on commit drop as select pg_temp.untouched_state() state;

-- A legacy Assignment without a VETERINARIAN Grant grants no Veterinarian capability.
select pg_temp.assert_true(public.veterinarian_clinic_assignment_is_current(pg_temp.id(8, 17))
    and pg_temp.vet_caps(17, pg_temp.id(4, 1)) = array['APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE']
    and not public.user_has_clinic_capability(pg_temp.id(2, 17), pg_temp.id(4, 1), 'CLINICAL_CARE')
    and pg_temp.clinical_context(17, pg_temp.id(4, 1)) = 0,
    'Profile + Assignment without VETERINARIAN: no clinical capability (Receptionist Appointment capability only)');

-- ===========================================================================
-- A. Invite directly as VETERINARIAN (SPEC-ORG-002 BR-17, §11 Note 28)
-- ===========================================================================
do $$ declare instant timestamptz; invitation uuid; result jsonb; begin
    instant := public.authorize_organization_invitation_creation(pg_temp.id(1, 2), pg_temp.id(3, 1));
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.call(2, format(
            'select to_jsonb(public.create_staff_organization_invitation_with_communication(%L, %L, ''vet.clinic@example.test'', ''VETERINARIAN'', ''CLINIC'', %L, %L, %L, 1, %L, %L))',
            pg_temp.id(1, 2), pg_temp.id(3, 1), pg_temp.id(4, 1), instant, sha256('x'::bytea), pg_temp.bytes(12), pg_temp.bytes(32)))) = '22023:INVALID_ROLE_SCOPE',
        'A Clinic-scoped VETERINARIAN Invitation is rejected');
    invitation := public.create_staff_organization_invitation_with_communication(pg_temp.id(1, 2), pg_temp.id(3, 1),
        'new.vet@example.test', 'VETERINARIAN', 'ORGANIZATION', null, instant,
        sha256(convert_to('chain-vet-secret', 'UTF8')), 1, pg_temp.bytes(12), pg_temp.bytes(32));
    perform pg_temp.assert_true((select count(*) = 1 and bool_and(responsibility = 'VETERINARIAN' and scope_type = 'ORGANIZATION' and clinic_id is null)
            from public.organization_invitation_responsibilities where invitation_id = invitation),
        'The Invitation intends exactly one Organization-scoped VETERINARIAN Responsibility');
    perform pg_temp.act(16);
    result := public.accept_my_organization_invitation(invitation, 'chain-vet-secret');
    execute 'set constraints all immediate';
    execute 'set constraints all deferred';
    insert into c_state values ('m16', (result ->> 'membership_id')::uuid);
end $$;
do $$ declare membership uuid := (select id from c_state where key = 'm16'); member jsonb; begin
    perform pg_temp.assert_true((select array_agg(responsibility || '@' || scope_type) from public.organization_responsibility_grants
            where membership_id = membership and effective_end is null) = array['VETERINARIAN@ORGANIZATION']
        and not exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 16))
        and not exists (select 1 from public.veterinarian_clinic_assignments where supporting_membership_id = membership),
        'Acceptance establishes the Membership and the VETERINARIAN Grant only: no Profile, no Assignment');
    perform pg_temp.act(16);
    perform pg_temp.assert_true((public.get_my_professional_context() ->> 'has_veterinarian_professional_profile')::boolean = false
        and public.get_my_professional_context() -> 'organizations' -> 0 -> 'responsibilities' -> 0 ->> 'responsibility' = 'VETERINARIAN',
        'The professional context shows VETERINARIAN without a Profile (the Home prompt condition)');
    perform pg_temp.assert_true(pg_temp.vet_caps(16, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(16, pg_temp.id(4, 2)) = '{}',
        'A new Veterinarian has no Clinic capability yet');
    member := (select value from jsonb_array_elements(
        (select public.get_organization_veterinarian_workforce(pg_temp.id(3, 1)) from (select pg_temp.act(2)) actor) -> 'members') value
        where value ->> 'membership_id' = membership::text);
    perform pg_temp.assert_true(member ->> 'has_veterinarian_professional_profile' = 'false'
        and member -> 'clinic_assignments' = '[]'::jsonb,
        'The administrator sees the Profile pending');
    perform pg_temp.assert_true(pg_temp.kind(pg_temp.call(2, format('select public.assign_staff_veterinarian_to_clinic(%L, %L, %L)',
            pg_temp.id(3, 1), membership, pg_temp.id(4, 1)))) = '23514:PROFILE_REQUIRED',
        'No Assignment before the professional completes the Profile');
end $$;
do $$ declare membership uuid := (select id from c_state where key = 'm16'); begin
    perform pg_temp.assert_true(pg_temp.json(pg_temp.call(16, 'select public.create_my_veterinarian_professional_profile(''CHAIN-16'', ''Colegio de Madrid'')'))
        ->> 'outcome' = 'CREATED', 'The invited Veterinarian creates their own Profile');
    perform pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.assign_staff_veterinarian_to_clinic(%L, %L, %L)',
            pg_temp.id(3, 1), membership, pg_temp.id(4, 1)))) ->> 'outcome' = 'ASSIGNED',
        'The administrator assigns Clinic A1');
end $$;
select pg_temp.assert_true(pg_temp.vet_caps(16, pg_temp.id(4, 1)) = pg_temp.all_caps() and pg_temp.vet_caps(16, pg_temp.id(4, 2)) = '{}'
    and pg_temp.clinical_context(16, pg_temp.id(4, 1)) = 1,
    'Invite as VETERINARIAN -> Profile -> Assignment: clinical authority at A1 only');

-- ===========================================================================
-- B. Existing Member, step by step (§19 chain)
-- ===========================================================================
-- Membership only.
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = '{}'
    and pg_temp.workforce_member(15) is null,
    'Chain 1: Membership only -> no Veterinarian capability, not in the workforce');
-- + VETERINARIAN Grant.
select pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.add_staff_responsibility(%L, %L, ''VETERINARIAN'', ''ORGANIZATION'', null)',
    pg_temp.id(3, 1), pg_temp.id(5, 15)))) ->> 'outcome' = 'ADDED', 'Chain 2: VETERINARIAN added');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = '{}'
    and pg_temp.workforce_member(15) ->> 'has_veterinarian_professional_profile' = 'false'
    and pg_temp.clinical_context(15, pg_temp.id(4, 1)) = 0,
    'Chain 2: + VETERINARIAN -> still no capability without Profile and Assignment');
-- + Profile.
select pg_temp.assert_true(pg_temp.json(pg_temp.call(15, 'select public.create_my_veterinarian_professional_profile(''CHAIN-15'', ''Colegio de Madrid'')'))
    ->> 'outcome' = 'CREATED', 'Chain 3: Profile created by the professional');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = '{}'
    and pg_temp.workforce_member(15) ->> 'has_veterinarian_professional_profile' = 'true'
    and pg_temp.clinical_context(15, pg_temp.id(4, 1)) = 0,
    'Chain 3: + Profile -> still no capability without an Assignment');
-- + Assignment at A1.
insert into c_state select 'a1', (pg_temp.json(pg_temp.call(2, format('select public.assign_staff_veterinarian_to_clinic(%L, %L, %L)',
    pg_temp.id(3, 1), pg_temp.id(5, 15), pg_temp.id(4, 1)))) ->> 'veterinarian_clinic_assignment_id')::uuid;
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = pg_temp.all_caps() and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = '{}'
    and pg_temp.clinical_context(15, pg_temp.id(4, 1)) = 1 and pg_temp.clinical_context(15, pg_temp.id(4, 2)) = 0,
    'Chain 4: + Assignment A1 -> CLINICAL_CARE/CLINICAL_DOCUMENTATION at A1 only');
-- + Assignment at A2.
insert into c_state select 'a2', (pg_temp.json(pg_temp.call(2, format('select public.assign_staff_veterinarian_to_clinic(%L, %L, %L)',
    pg_temp.id(3, 1), pg_temp.id(5, 15), pg_temp.id(4, 2)))) ->> 'veterinarian_clinic_assignment_id')::uuid;
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = pg_temp.all_caps() and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = pg_temp.all_caps()
    and jsonb_array_length(pg_temp.workforce_member(15) -> 'clinic_assignments') = 2,
    'Chain 5: + Assignment A2 -> capability at both Clinics');
do $$ begin
    perform pg_temp.act(15);
    perform pg_temp.assert_true(jsonb_array_length(public.get_my_professional_context() -> 'organizations' -> 0 -> 'clinic_assignments') = 2,
        'Chain 5: the professional context shows both current Assignments');
end $$;
-- VETERINARIAN cannot end while Assignments are current.
select pg_temp.assert_true(pg_temp.kind(pg_temp.call(2, format('select public.end_staff_responsibility(%L, %L)',
        pg_temp.id(3, 1), pg_temp.grant_of(15, 'VETERINARIAN')))) = '23514:VETERINARIAN_ASSIGNMENTS_ACTIVE'
    and pg_temp.vet_caps(15, pg_temp.id(4, 1)) = pg_temp.all_caps(),
    'Chain 6: ending VETERINARIAN is blocked while Assignments are current; nothing changes');
-- End A1.
select pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.end_staff_veterinarian_clinic_assignment(%L, %L, %L)',
    pg_temp.id(3, 1), pg_temp.id(4, 1), (select id from c_state where key = 'a1')))) ->> 'outcome' = 'ENDED', 'Chain 7: A1 ended');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = pg_temp.all_caps()
    and pg_temp.clinical_context(15, pg_temp.id(4, 1)) = 0 and pg_temp.clinical_context(15, pg_temp.id(4, 2)) = 1,
    'Chain 7: ending A1 removes capability at A1 only');
-- End A2.
select pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.end_staff_veterinarian_clinic_assignment(%L, %L, %L)',
    pg_temp.id(3, 1), pg_temp.id(4, 2), (select id from c_state where key = 'a2')))) ->> 'outcome' = 'ENDED', 'Chain 8: A2 ended');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = '{}',
    'Chain 8: no Clinic capability after every Assignment ended');
-- End VETERINARIAN.
select pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.end_staff_responsibility(%L, %L)',
    pg_temp.id(3, 1), pg_temp.grant_of(15, 'VETERINARIAN')))) ->> 'outcome' = 'ENDED', 'Chain 9: VETERINARIAN ended');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.vet_caps(15, pg_temp.id(4, 2)) = '{}'
    and pg_temp.workforce_member(15) is null
    and exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 15))
    and (select count(*) = 2 and bool_and(effective_end is not null) from public.veterinarian_clinic_assignments
         where supporting_membership_id = pg_temp.id(5, 15))
    and pg_temp.grant_of(15, 'ADMINISTRATOR') = pg_temp.id(6, 15),
    'Chain 9: no Veterinarian capability; Profile, Assignment history and the unrelated Grant remain');
-- Add VETERINARIAN again to the same Member: a new period, no capability without a current Assignment.
select pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.add_staff_responsibility(%L, %L, ''VETERINARIAN'', ''ORGANIZATION'', null)',
        pg_temp.id(3, 1), pg_temp.id(5, 15)))) ->> 'outcome' = 'ADDED', 'Chain 10: VETERINARIAN added again');
select pg_temp.assert_true((select count(*) from public.organization_responsibility_grants where membership_id = pg_temp.id(5, 15)
        and responsibility = 'VETERINARIAN') = 2,
    'Chain 10: re-adding VETERINARIAN creates a new period; the ended one is kept');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}',
    'Chain 10: an ended Assignment never revives capability');
insert into c_state select 'a1_again', (pg_temp.json(pg_temp.call(2, format('select public.assign_staff_veterinarian_to_clinic(%L, %L, %L)',
    pg_temp.id(3, 1), pg_temp.id(5, 15), pg_temp.id(4, 1)))) ->> 'veterinarian_clinic_assignment_id')::uuid;
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = pg_temp.all_caps(), 'Chain 11: a new A1 Assignment restores A1 capability');
-- End the Membership (End access).
select pg_temp.assert_true(pg_temp.json(pg_temp.call(2, format('select public.end_organization_staff_membership(%L)', pg_temp.id(5, 15))))
    ->> 'outcome' = 'ENDED', 'Chain 12: Membership ended through End access');
select pg_temp.assert_true(pg_temp.vet_caps(15, pg_temp.id(4, 1)) = '{}' and pg_temp.clinical_context(15, pg_temp.id(4, 1)) = 0
    and not public.veterinarian_clinic_assignment_is_current((select id from c_state where key = 'a1_again'))
    and (select effective_end is null from public.veterinarian_clinic_assignments where id = (select id from c_state where key = 'a1_again'))
    and exists (select 1 from public.veterinarian_professional_profiles where user_id = pg_temp.id(2, 15))
    and not exists (select 1 from public.organization_responsibility_grants where membership_id = pg_temp.id(5, 15) and effective_end is null)
    and (select count(*) from public.organization_responsibility_grants where membership_id = pg_temp.id(5, 15)) = 3
    and (select count(*) from public.veterinarian_clinic_assignments where supporting_membership_id = pg_temp.id(5, 15)) = 3,
    'Chain 12: no Veterinarian capability; the Assignment row is kept but not current; Profile and every Grant period preserved');

-- Nothing in the chain touched Appointments, Appointment Veterinarian
-- Assignments, Availability, or clinical records (SPEC-ORG-006 BR-29/30).
select pg_temp.assert_true(pg_temp.untouched_state() = (select state from c_untouched),
    'No Appointment assignment, Availability, or clinical record is created or required');

set constraints all immediate;
set constraints all deferred;
rollback;

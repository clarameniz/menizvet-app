-- Regression suite for SPEC-ORG-008 — View My Professional Clinics, migration
-- 20261001150000_professional_clinics_read.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions are
-- rolled back; superuser test execution is required solely to bypass
-- unrelated establishment triggers/foreign keys while loading a deliberately
-- minimal deterministic context, and to switch between impersonated Users
-- (same rationale as professional_context_spec_org_007.sql).
--
-- Covers SPEC-ORG-008 BR-1..BR-18 and Verification Notes 1–23, including:
--   * the authoritative-parity guarantee: for every fixture User × fixture
--     Clinic × Clinic-context catalog capability, the capability is returned
--     for that Clinic if and only if user_has_clinic_capability holds, and no
--     Clinic is returned without one (VN 16);
--   * consistency with get_my_professional_context() (BR-18, VN 17);
--   * payload shape, data minimization, ACL, and no-write guarantees.
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_error(
    p_statement text, p_expected_sqlstate text, p_expected_message_fragment text
)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected_sqlstate
           and (p_expected_message_fragment is null
                or position(p_expected_message_fragment in sqlerrm) > 0) then
            return;
        end if;
        raise exception 'Expected SQLSTATE % (%), received %: %',
            p_expected_sqlstate, p_expected_message_fragment, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected_sqlstate;
end;
$$;

-- Ordered Clinic ids of a result.
create function pg_temp.clinic_ids(p_result jsonb)
returns uuid[] language sql as $$
    select coalesce(array_agg((clinic_entry ->> 'clinic_id')::uuid order by ordinality), '{}')
    from jsonb_array_elements(p_result -> 'clinics') with ordinality as entry (clinic_entry, ordinality)
$$;

-- Clinic entry of a result.
create function pg_temp.clinic_entry(p_result jsonb, p_clinic_id uuid)
returns jsonb language sql as $$
    select clinic_entry
    from jsonb_array_elements(p_result -> 'clinics') as clinic_entry
    where (clinic_entry ->> 'clinic_id')::uuid = p_clinic_id
$$;

-- Capabilities of a Clinic entry, in returned order.
create function pg_temp.clinic_caps(p_result jsonb, p_clinic_id uuid)
returns text[] language sql as $$
    select coalesce(array_agg(capability order by ordinality), '{}')
    from jsonb_array_elements_text(pg_temp.clinic_entry(p_result, p_clinic_id) -> 'capabilities')
         with ordinality as entry (capability, ordinality)
$$;

-- ===========================================================================
-- Expected capability sets, transcribed from SPEC-ORG-005 §5/§6 (not from
-- SQL), ordered by identifier in binary collation.
-- ===========================================================================

create temporary table expected_capability_set (
    set_name text primary key,
    capabilities text[] not null
) on commit drop;

insert into expected_capability_set values
    ('CLINIC_ADMINISTRATION_AND_APPOINTMENTS', array[
        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL', 'APPOINTMENT_COMPLETE',
        'APPOINTMENT_CONFIRM', 'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_MARK_NO_SHOW',
        'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_VIEW_SCHEDULE',
        'CLINIC_MANAGE_LOCATION', 'CLINIC_MANAGE_OPENING_HOURS', 'CLINIC_MANAGE_PUBLICATION',
        'CLINIC_MANAGE_PUBLIC_PROFILE', 'CLINIC_MANAGE_SERVICES',
        'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'
    ]),
    ('APPOINTMENT_OPERATIONS', array[
        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL', 'APPOINTMENT_COMPLETE',
        'APPOINTMENT_CONFIRM', 'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_MARK_NO_SHOW',
        'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_VIEW_SCHEDULE'
    ]),
    ('VETERINARIAN', array[
        'APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
    ]),
    -- RECEPTIONIST Appointment operations ∪ VETERINARIAN at the same Clinic.
    ('APPOINTMENT_OPERATIONS_AND_VETERINARIAN', array[
        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL', 'APPOINTMENT_COMPLETE',
        'APPOINTMENT_CONFIRM', 'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_MARK_NO_SHOW',
        'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
    ]);

grant select on expected_capability_set to authenticated;

create function pg_temp.expected_caps(p_set_name text)
returns text[] language sql as $$
    select capabilities from expected_capability_set where set_name = p_set_name
$$;

-- The transcription must agree with the catalog's Clinic-context partition.
select pg_temp.assert_true(
    (select array_agg(capability order by capability collate "C")
     from public.professional_capability_catalog()
     where capability_context = 'CLINIC' and capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'))
    = pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS')
    and (select count(*) from public.professional_capability_catalog() where capability_context = 'CLINIC') = 16,
    'Setup: SPEC-ORG-005 Clinic-context transcription must match professional_capability_catalog()'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects 18100000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian only (with a Pet)            10 VETERINARIAN + Profile, no Assignment
--   02 Profile only, no Membership           11 current Assignment @ A1, VETERINARIAN grant ended
--   03 bare OrgA Membership                  12 OWNER on an ENDED OrgB Membership
--   04 OrgA OWNER                            13 OrgA ADMINISTRATOR grant ended
--   05 OrgA ADMINISTRATOR (Org)              14 VETERINARIAN, Assignment @ A1 ended
--   06 ADMINISTRATOR @ A2 (Clinic)           15 pending Invitation (RECEPTIONIST @ A1) only
--   07 OrgA RECEPTIONIST (Org)               16 OrgA RECEPTIONIST + ADMINISTRATOR @ A2
--   08 RECEPTIONIST @ A3 (Clinic)               + VETERINARIAN assigned @ A1
--   09 VETERINARIAN + Profile, assigned @ A1 17 RECEPTIONIST @ A5, OrgB OWNER, OrgC
--                                               ADMINISTRATOR, OWNER of Clinic-less OrgE
--                                            18 authenticated subject without domain User
--
-- Organizations (…03NN): OrgA "Animalia Veterinary Group", OrgB "VetCare
-- Group", OrgC "Animalia Veterinary Group" (same display name as OrgA, larger
-- id), OrgE "Empty Org" (no Clinics). OrgB has no Subscription; no
-- Subscription exists for any Organization (Entitlement must not matter).
--
-- Clinics (…04NN): A1 "Animalia Madrid Centro" published; A2 "Animalia
-- Getafe" unpublished; A3 no public profile; A4 public profile without a
-- display name; A5 "Animalia Getafe" (same display name as A2, larger id);
-- B1 "VetCare Toledo"; C1 "Zeta Clinic".
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('18100000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 18) as n;

insert into public.users (id)
select ('18100000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 17) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select
    ('18100000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
    ('18100000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 17) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('18100000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('18100000-0000-4000-8000-000000000302', 'VetCare Group'),
    ('18100000-0000-4000-8000-000000000303', 'Animalia Veterinary Group'),
    ('18100000-0000-4000-8000-000000000305', 'Empty Org');

insert into public.clinics (id, organization_id, is_published) values
    ('18100000-0000-4000-8000-000000000401', '18100000-0000-4000-8000-000000000301', true),
    ('18100000-0000-4000-8000-000000000402', '18100000-0000-4000-8000-000000000301', false),
    ('18100000-0000-4000-8000-000000000403', '18100000-0000-4000-8000-000000000301', false),
    ('18100000-0000-4000-8000-000000000404', '18100000-0000-4000-8000-000000000301', false),
    ('18100000-0000-4000-8000-000000000405', '18100000-0000-4000-8000-000000000301', true),
    ('18100000-0000-4000-8000-000000000411', '18100000-0000-4000-8000-000000000302', true),
    ('18100000-0000-4000-8000-000000000421', '18100000-0000-4000-8000-000000000303', true);

insert into public.clinic_public_profiles (clinic_id, display_name, description, public_phone) values
    ('18100000-0000-4000-8000-000000000401', 'Animalia Madrid Centro', 'Private description must not leak', '+34 900 000 001'),
    ('18100000-0000-4000-8000-000000000402', 'Animalia Getafe', null, null),
    ('18100000-0000-4000-8000-000000000404', null, 'Description of an unnamed Clinic', null),
    ('18100000-0000-4000-8000-000000000405', 'Animalia Getafe', null, null),
    ('18100000-0000-4000-8000-000000000411', 'VetCare Toledo', null, null),
    ('18100000-0000-4000-8000-000000000421', 'Zeta Clinic', null, null);

-- Memberships (…05NN; U17 also …0571–0573).
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('18100000-0000-4000-8000-000000000503', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000203', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000504', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000204', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000505', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000205', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000506', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000206', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000507', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000207', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000508', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000208', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000509', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000209', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000510', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000210', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000511', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000211', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000512', '18100000-0000-4000-8000-000000000302', '18100000-0000-4000-8000-000000000212', '2020-01-01Z', '2021-01-01Z', '18100000-0000-4000-8000-000000000212'),
    ('18100000-0000-4000-8000-000000000513', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000213', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000514', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000214', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000516', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000216', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000517', '18100000-0000-4000-8000-000000000301', '18100000-0000-4000-8000-000000000217', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000571', '18100000-0000-4000-8000-000000000302', '18100000-0000-4000-8000-000000000217', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000572', '18100000-0000-4000-8000-000000000303', '18100000-0000-4000-8000-000000000217', '2020-01-01Z', null, null),
    ('18100000-0000-4000-8000-000000000573', '18100000-0000-4000-8000-000000000305', '18100000-0000-4000-8000-000000000217', '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('18100000-0000-4000-8000-000000000604', '18100000-0000-4000-8000-000000000504', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000605', '18100000-0000-4000-8000-000000000505', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000606', '18100000-0000-4000-8000-000000000506', 'ADMINISTRATOR', 'CLINIC', '18100000-0000-4000-8000-000000000402', '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000607', '18100000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000608', '18100000-0000-4000-8000-000000000508', 'RECEPTIONIST', 'CLINIC', '18100000-0000-4000-8000-000000000403', '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000609', '18100000-0000-4000-8000-000000000509', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000610', '18100000-0000-4000-8000-000000000510', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    -- U11: VETERINARIAN grant ended; Clinic Assignment stays current (SPEC-ORG-006 BR-30).
    ('18100000-0000-4000-8000-000000000611', '18100000-0000-4000-8000-000000000511', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', '18100000-0000-4000-8000-000000000204', '18100000-0000-4000-8000-000000000204'),
    -- U12: open OWNER grant on an ended Membership.
    ('18100000-0000-4000-8000-000000000612', '18100000-0000-4000-8000-000000000512', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000212', null),
    -- U13: ADMINISTRATOR grant ended.
    ('18100000-0000-4000-8000-000000000613', '18100000-0000-4000-8000-000000000513', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', '18100000-0000-4000-8000-000000000204', '18100000-0000-4000-8000-000000000204'),
    ('18100000-0000-4000-8000-000000000614', '18100000-0000-4000-8000-000000000514', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    -- U16: three overlapping bases.
    ('18100000-0000-4000-8000-000000000661', '18100000-0000-4000-8000-000000000516', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000662', '18100000-0000-4000-8000-000000000516', 'ADMINISTRATOR', 'CLINIC', '18100000-0000-4000-8000-000000000402', '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000663', '18100000-0000-4000-8000-000000000516', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    -- U17: four Organizations.
    ('18100000-0000-4000-8000-000000000671', '18100000-0000-4000-8000-000000000517', 'RECEPTIONIST', 'CLINIC', '18100000-0000-4000-8000-000000000405', '2020-01-01Z', null, '18100000-0000-4000-8000-000000000204', null),
    ('18100000-0000-4000-8000-000000000672', '18100000-0000-4000-8000-000000000571', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000217', null),
    ('18100000-0000-4000-8000-000000000673', '18100000-0000-4000-8000-000000000572', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000217', null),
    ('18100000-0000-4000-8000-000000000674', '18100000-0000-4000-8000-000000000573', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18100000-0000-4000-8000-000000000217', null);

-- Professional Profiles (…07NN) and Clinic Assignments (…08NN).
insert into public.veterinarian_professional_profiles (id, user_id) values
    ('18100000-0000-4000-8000-000000000702', '18100000-0000-4000-8000-000000000202'),
    ('18100000-0000-4000-8000-000000000709', '18100000-0000-4000-8000-000000000209'),
    ('18100000-0000-4000-8000-000000000710', '18100000-0000-4000-8000-000000000210'),
    ('18100000-0000-4000-8000-000000000711', '18100000-0000-4000-8000-000000000211'),
    ('18100000-0000-4000-8000-000000000712', '18100000-0000-4000-8000-000000000212'),
    ('18100000-0000-4000-8000-000000000714', '18100000-0000-4000-8000-000000000214'),
    ('18100000-0000-4000-8000-000000000716', '18100000-0000-4000-8000-000000000216');

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('18100000-0000-4000-8000-000000000809', '18100000-0000-4000-8000-000000000709', '18100000-0000-4000-8000-000000000509', '18100000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    ('18100000-0000-4000-8000-000000000811', '18100000-0000-4000-8000-000000000711', '18100000-0000-4000-8000-000000000511', '18100000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    -- U12: open Assignment row supported by an ENDED Membership (not current).
    ('18100000-0000-4000-8000-000000000812', '18100000-0000-4000-8000-000000000712', '18100000-0000-4000-8000-000000000512', '18100000-0000-4000-8000-000000000411', '2020-01-01Z', null),
    ('18100000-0000-4000-8000-000000000814', '18100000-0000-4000-8000-000000000714', '18100000-0000-4000-8000-000000000514', '18100000-0000-4000-8000-000000000401', '2020-01-01Z', '2021-01-01Z'),
    ('18100000-0000-4000-8000-000000000816', '18100000-0000-4000-8000-000000000716', '18100000-0000-4000-8000-000000000516', '18100000-0000-4000-8000-000000000401', '2020-01-01Z', null);

-- U15: pending, unexpired Invitation proposing RECEPTIONIST @ A1.
insert into public.organization_invitations (
    id, organization_id, inviting_user_id, recipient_user_id, recipient_email, created_at, expires_at
) values (
    '18100000-0000-4000-8000-000000000c15', '18100000-0000-4000-8000-000000000301',
    '18100000-0000-4000-8000-000000000204', '18100000-0000-4000-8000-000000000215',
    'u15@example.test', '2020-01-01Z', statement_timestamp() + interval '30 days'
);
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id)
values (
    '18100000-0000-4000-8000-000000000c16', '18100000-0000-4000-8000-000000000c15',
    'RECEPTIONIST', 'CLINIC', '18100000-0000-4000-8000-000000000401'
);

-- Guardian data that must never appear.
insert into public.pets (id, name, species, created_at)
values ('18100000-0000-4000-8000-000000000b01', 'Luna', 'canine', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values ('18100000-0000-4000-8000-000000000b02', '18100000-0000-4000-8000-000000000201', '18100000-0000-4000-8000-000000000b01', '2020-01-01Z');

set local session_replication_role = origin;

-- ===========================================================================
-- A. ACL / function attributes (VN 22).
-- ===========================================================================

select pg_temp.assert_true(
    has_function_privilege('authenticated', 'public.get_my_professional_clinics()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_my_professional_clinics()', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_my_professional_clinics()', 'EXECUTE'),
    'A: only authenticated (not anon/public) may execute get_my_professional_clinics()'
);
select pg_temp.assert_true(
    (select prosecdef and provolatile = 's' and pronargs = 0
            and proconfig @> array['search_path=""']
            and prorettype = 'jsonb'::regtype
     from pg_proc where oid = 'public.get_my_professional_clinics()'::regprocedure),
    'A: get_my_professional_clinics() must be a zero-argument STABLE SECURITY DEFINER jsonb function with an empty search_path'
);
select pg_temp.assert_true(
    (select count(*) from pg_proc
     where proname = 'get_my_professional_clinics' and pronamespace = 'public'::regnamespace) = 1,
    'A: exactly one get_my_professional_clinics overload exists (no input-parameter variant)'
);
select pg_temp.assert_true(
    (select bool_and(
        not has_table_privilege(role_name, table_name, 'SELECT')
     )
     from unnest(array['anon', 'authenticated']) as role_name,
          unnest(array[
              'public.clinics', 'public.clinic_public_profiles', 'public.veterinary_organizations',
              'public.organization_memberships', 'public.organization_responsibility_grants',
              'public.veterinarian_professional_profiles', 'public.veterinarian_clinic_assignments',
              'public.organization_invitations', 'public.organization_subscriptions'
          ]) as table_name),
    'A: no direct table SELECT is granted to anon/authenticated'
);
select pg_temp.assert_true(
    (select bool_and(
        not has_function_privilege('authenticated', signature, 'EXECUTE')
        and not has_function_privilege('anon', signature, 'EXECUTE')
     )
     from unnest(array[
        'public.professional_capability_catalog()',
        'public.user_has_clinic_capability(uuid,uuid,text)',
        'public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)',
        'public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)'
     ]) as signature),
    'A: capability helpers remain non-executable by client roles'
);
-- The read delegates to the authoritative predicate and restates no mapping.
select pg_temp.assert_true(
    (select prosrc like '%user_has_clinic_capability%'
            and prosrc like '%professional_capability_catalog%'
            and prosrc not like '%''OWNER''%'
            and prosrc not like '%''ADMINISTRATOR''%'
            and prosrc not like '%''RECEPTIONIST''%'
            and prosrc not like '%''VETERINARIAN''%'
            and prosrc not like '%''APPOINTMENT\_%'
            and prosrc not like '%''CLINICAL\_%'
            and prosrc not like '%''CLINIC\_MANAGE%'
            and prosrc not like '%is_published%'
            and prosrc not like '%entitlement%'
            and prosrc not like '%subscription%'
     from pg_proc where oid = 'public.get_my_professional_clinics()'::regprocedure),
    'A: the read must delegate to user_has_clinic_capability and contain no responsibility/capability mapping, publication, or Entitlement logic'
);

-- ===========================================================================
-- B. Authentication (VN 1).
-- ===========================================================================

set local role anon;
select pg_temp.assert_error('select public.get_my_professional_clinics()', '42501', null);
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error('select public.get_my_professional_clinics()', '28000', 'Authentication is required');
reset role;

select set_config('request.jwt.claim.sub', '18100000-0000-4000-8000-000000000118', true);
set local role authenticated;
select pg_temp.assert_error('select public.get_my_professional_clinics()', '28000', 'No coherent domain User');
reset role;

-- ===========================================================================
-- C. Collect every fixture User's ORG-008 and ORG-007 results, and prove the
--    read writes nothing (VN 21).
-- ===========================================================================

create temporary table fixture_result (
    user_number integer primary key,
    user_id uuid not null,
    clinics_result jsonb not null,
    context_result jsonb not null
) on commit drop;

do $$
declare
    user_number integer;
    clinics_value jsonb;
    context_value jsonb;
    writes_before bigint;
    writes_after bigint;
begin
    select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) into writes_before
    from pg_stat_xact_user_tables;

    for user_number in 1..17 loop
        perform set_config(
            'request.jwt.claim.sub',
            '18100000-0000-4000-8000-0000000001' || lpad(user_number::text, 2, '0'),
            true
        );
        set local role authenticated;
        clinics_value := public.get_my_professional_clinics();
        context_value := public.get_my_professional_context();
        perform pg_temp.assert_true(
            clinics_value = public.get_my_professional_clinics(),
            format('C: repeated reads must be identical for U%s', user_number)
        );
        reset role;

        insert into fixture_result values (
            user_number,
            ('18100000-0000-4000-8000-0000000002' || lpad(user_number::text, 2, '0'))::uuid,
            clinics_value,
            context_value
        );
    end loop;

    select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) into writes_after
    from pg_stat_xact_user_tables;

    -- Exactly the 17 fixture_result inserts above are the only writes.
    perform pg_temp.assert_true(
        writes_after - writes_before = 17,
        format('C: reading Professional Clinics must write nothing (observed %s writes besides the 17 harness inserts)',
               writes_after - writes_before - 17)
    );
end;
$$;

create function pg_temp.result_of(p_user_number integer)
returns jsonb language sql as $$
    select clinics_result from fixture_result where user_number = p_user_number
$$;

-- ===========================================================================
-- D. Behavior.
-- ===========================================================================

-- D1. Empty results: Guardian-only, Profile only, bare Membership,
--     VETERINARIAN without Assignment, Assignment without VETERINARIAN,
--     ended Membership, ended Responsibility, ended Assignment, pending
--     Invitation (VN 2, 8–11).
select pg_temp.assert_true(
    pg_temp.result_of(n) = '{"clinics": []}'::jsonb,
    format('D1: U%s must receive exactly {"clinics": []}, got %s', n, pg_temp.result_of(n))
)
from unnest(array[1, 2, 3, 10, 11, 12, 13, 14, 15]) as n;

-- D1b. U11 is the Assignment-without-VETERINARIAN case: SPEC-ORG-007 still
--      reports the current Clinic Assignment, ORG-008 excludes the Clinic.
select pg_temp.assert_true(
    (select jsonb_array_length(organization_entry -> 'clinic_assignments') = 1
            and organization_entry -> 'capabilities' = '[]'::jsonb
     from fixture_result,
          jsonb_array_elements(context_result -> 'organizations') as organization_entry
     where user_number = 11),
    'D1b: SPEC-ORG-007 reports U11''s current Clinic Assignment with no capability'
);

-- D2. Organization OWNER: every OrgA Clinic (published, unpublished, no
--     profile, unnamed profile), ordered by display name nulls last then id,
--     each with the 14 Clinic-administration/Appointment capabilities and no
--     CLINICAL_* capability (VN 3, 14, 15).
select pg_temp.assert_true(
    pg_temp.clinic_ids(pg_temp.result_of(4)) = array[
        '18100000-0000-4000-8000-000000000402',  -- Animalia Getafe (smaller id)
        '18100000-0000-4000-8000-000000000405',  -- Animalia Getafe (larger id)
        '18100000-0000-4000-8000-000000000401',  -- Animalia Madrid Centro
        '18100000-0000-4000-8000-000000000403',  -- no public profile
        '18100000-0000-4000-8000-000000000404'   -- profile without display name
    ]::uuid[],
    format('D2: OWNER Clinic order incorrect: %s', pg_temp.result_of(4))
);
select pg_temp.assert_true(
    pg_temp.clinic_caps(pg_temp.result_of(4), clinic_id) = pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS'),
    format('D2: OWNER capabilities incorrect at %s', clinic_id)
)
from unnest(pg_temp.clinic_ids(pg_temp.result_of(4))) as clinic_id;
select pg_temp.assert_true(
    pg_temp.clinic_entry(pg_temp.result_of(4), '18100000-0000-4000-8000-000000000403')
        = jsonb_build_object(
            'clinic_id', '18100000-0000-4000-8000-000000000403',
            'clinic_display_name', null,
            'organization_id', '18100000-0000-4000-8000-000000000301',
            'organization_display_name', 'Animalia Veterinary Group',
            'capabilities', to_jsonb(pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS')))
    and jsonb_typeof(pg_temp.clinic_entry(pg_temp.result_of(4), '18100000-0000-4000-8000-000000000404') -> 'clinic_display_name') = 'null'
    and pg_temp.clinic_entry(pg_temp.result_of(4), '18100000-0000-4000-8000-000000000402') ->> 'clinic_display_name' = 'Animalia Getafe',
    'D2: unpublished and unnamed Clinics are returned with exact identity and a JSON null display name'
);

-- D3. Organization ADMINISTRATOR: identical to OWNER (VN 4).
select pg_temp.assert_true(
    pg_temp.result_of(5) = pg_temp.result_of(4),
    'D3: Organization ADMINISTRATOR must receive the same result as Organization OWNER'
);

-- D4. Clinic-scoped ADMINISTRATOR @ A2 only (VN 5).
select pg_temp.assert_true(
    pg_temp.clinic_ids(pg_temp.result_of(6)) = array['18100000-0000-4000-8000-000000000402']::uuid[]
    and pg_temp.clinic_caps(pg_temp.result_of(6), '18100000-0000-4000-8000-000000000402')
        = pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS')
    and 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS' = any (pg_temp.clinic_caps(pg_temp.result_of(6), '18100000-0000-4000-8000-000000000402')),
    format('D4: Clinic ADMINISTRATOR must receive only A2, got %s', pg_temp.result_of(6))
);

-- D5. Organization RECEPTIONIST: every OrgA Clinic, Appointment operations
--     only; Clinic RECEPTIONIST @ A3 only (VN 6).
select pg_temp.assert_true(
    pg_temp.clinic_ids(pg_temp.result_of(7)) = pg_temp.clinic_ids(pg_temp.result_of(4))
    and (select bool_and(pg_temp.clinic_caps(pg_temp.result_of(7), clinic_id) = pg_temp.expected_caps('APPOINTMENT_OPERATIONS'))
         from unnest(pg_temp.clinic_ids(pg_temp.result_of(7))) as clinic_id)
    and position('CLINIC_MANAGE' in pg_temp.result_of(7)::text) = 0,
    format('D5: Organization RECEPTIONIST incorrect: %s', pg_temp.result_of(7))
);
select pg_temp.assert_true(
    pg_temp.result_of(8) = jsonb_build_object('clinics', jsonb_build_array(jsonb_build_object(
        'clinic_id', '18100000-0000-4000-8000-000000000403',
        'clinic_display_name', null,
        'organization_id', '18100000-0000-4000-8000-000000000301',
        'organization_display_name', 'Animalia Veterinary Group',
        'capabilities', to_jsonb(pg_temp.expected_caps('APPOINTMENT_OPERATIONS'))))),
    format('D5: Clinic RECEPTIONIST must receive only A3, got %s', pg_temp.result_of(8))
);

-- D6. VETERINARIAN with Profile and current Assignment @ A1 (VN 7).
select pg_temp.assert_true(
    pg_temp.result_of(9) = jsonb_build_object('clinics', jsonb_build_array(jsonb_build_object(
        'clinic_id', '18100000-0000-4000-8000-000000000401',
        'clinic_display_name', 'Animalia Madrid Centro',
        'organization_id', '18100000-0000-4000-8000-000000000301',
        'organization_display_name', 'Animalia Veterinary Group',
        'capabilities', to_jsonb(pg_temp.expected_caps('VETERINARIAN'))))),
    format('D6: VETERINARIAN must receive only A1 with the four Veterinarian capabilities, got %s', pg_temp.result_of(9))
);

-- D7. Overlapping bases produce one row per Clinic with the union of
--     capabilities and no duplicate identifier (VN 13).
select pg_temp.assert_true(
    pg_temp.clinic_ids(pg_temp.result_of(16)) = pg_temp.clinic_ids(pg_temp.result_of(4))
    and pg_temp.clinic_caps(pg_temp.result_of(16), '18100000-0000-4000-8000-000000000401')
        = pg_temp.expected_caps('APPOINTMENT_OPERATIONS_AND_VETERINARIAN')
    and pg_temp.clinic_caps(pg_temp.result_of(16), '18100000-0000-4000-8000-000000000402')
        = pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS')
    and pg_temp.clinic_caps(pg_temp.result_of(16), '18100000-0000-4000-8000-000000000403')
        = pg_temp.expected_caps('APPOINTMENT_OPERATIONS'),
    format('D7: overlapping bases incorrect: %s', pg_temp.result_of(16))
);

-- D8. Several Organizations in one call; tied Organization display names
--     ordered by Organization id; a Clinic-less Organization contributes
--     nothing; cross-Organization isolation (VN 12, 14).
select pg_temp.assert_true(
    pg_temp.clinic_ids(pg_temp.result_of(17)) = array[
        '18100000-0000-4000-8000-000000000405',  -- OrgA (Animalia…, smaller id): A5 via Clinic RECEPTIONIST
        '18100000-0000-4000-8000-000000000421',  -- OrgC (Animalia…, larger id): C1 via ADMINISTRATOR
        '18100000-0000-4000-8000-000000000411'   -- OrgB VetCare: B1 via OWNER
    ]::uuid[]
    and pg_temp.clinic_caps(pg_temp.result_of(17), '18100000-0000-4000-8000-000000000405') = pg_temp.expected_caps('APPOINTMENT_OPERATIONS')
    and pg_temp.clinic_caps(pg_temp.result_of(17), '18100000-0000-4000-8000-000000000421') = pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS')
    and pg_temp.clinic_caps(pg_temp.result_of(17), '18100000-0000-4000-8000-000000000411') = pg_temp.expected_caps('CLINIC_ADMINISTRATION_AND_APPOINTMENTS')
    and position('18100000-0000-4000-8000-000000000305' in pg_temp.result_of(17)::text) = 0,
    format('D8: multi-Organization result incorrect: %s', pg_temp.result_of(17))
);
select pg_temp.assert_true(
    position('18100000-0000-4000-8000-000000000302' in pg_temp.result_of(n)::text) = 0
    and position('18100000-0000-4000-8000-000000000411' in pg_temp.result_of(n)::text) = 0,
    format('D8: OrgA-only U%s must not receive any OrgB Clinic', n)
)
from unnest(array[4, 5, 6, 7, 8, 9, 16]) as n;

-- D9. Exact payload shape and data minimization for every fixture result
--     (VN 15, 18, 19).
select pg_temp.assert_true(
    (select array_agg(key order by key) from jsonb_object_keys(clinics_result) as key) = array['clinics']
    and jsonb_typeof(clinics_result -> 'clinics') = 'array',
    format('D9: U%s top-level keys must be exactly {clinics}', user_number)
)
from fixture_result;
select pg_temp.assert_true(
    (select array_agg(key order by key) from jsonb_object_keys(clinic_entry) as key)
        = array['capabilities', 'clinic_display_name', 'clinic_id', 'organization_display_name', 'organization_id']
    and jsonb_typeof(clinic_entry -> 'capabilities') = 'array'
    and jsonb_array_length(clinic_entry -> 'capabilities') > 0
    and jsonb_typeof(clinic_entry -> 'clinic_display_name') in ('string', 'null')
    and jsonb_typeof(clinic_entry -> 'organization_display_name') = 'string',
    format('D9: U%s Clinic entry shape incorrect: %s', user_number, clinic_entry)
)
from fixture_result, jsonb_array_elements(clinics_result -> 'clinics') as clinic_entry;
select pg_temp.assert_true(
    (select array_agg(capability order by capability collate "C") from jsonb_array_elements_text(clinic_entry -> 'capabilities') as capability)
        = (select array_agg(capability order by ordinality)
           from jsonb_array_elements_text(clinic_entry -> 'capabilities') with ordinality as entry (capability, ordinality))
    and (select count(*) from jsonb_array_elements_text(clinic_entry -> 'capabilities'))
        = (select count(distinct capability) from jsonb_array_elements_text(clinic_entry -> 'capabilities') as capability)
    and not exists (
        select 1 from jsonb_array_elements_text(clinic_entry -> 'capabilities') as capability
        where capability not in (
            select catalog_entry.capability from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability_context = 'CLINIC'
        )
    ),
    format('D9: U%s capabilities must be distinct, binary-ordered, Clinic-context identifiers: %s', user_number, clinic_entry)
)
from fixture_result, jsonb_array_elements(clinics_result -> 'clinics') as clinic_entry;
select pg_temp.assert_true(
    position('ORGANIZATION_' in clinics_result::text) = 0
    and position('is_published' in clinics_result::text) = 0
    and position('Private description' in clinics_result::text) = 0
    and position('Description of an unnamed Clinic' in clinics_result::text) = 0
    and position('+34 900' in clinics_result::text) = 0
    and position('Luna' in clinics_result::text) = 0
    and position('membership' in clinics_result::text) = 0
    and position('assignment' in clinics_result::text) = 0
    and position('entitlement' in lower(clinics_result::text)) = 0
    and position('APPOINTMENT_MANAGEMENT' in clinics_result::text) = 0
    and position('PROFESSIONAL_SCHEDULING' in clinics_result::text) = 0
    and position('u15@example.test' in clinics_result::text) = 0,
    format('D9: U%s result leaks non-approved data: %s', user_number, clinics_result)
)
from fixture_result;

-- D10. Entitlement does not affect inclusion: no fixture Organization has a
--      Subscription, yet OWNER/ADMINISTRATOR/RECEPTIONIST/VETERINARIAN Clinics
--      are returned (BR-11).
select pg_temp.assert_true(
    not exists (
        select 1 from public.organization_subscriptions
        where organization_id::text like '18100000-%'
    )
    and jsonb_array_length(pg_temp.result_of(4) -> 'clinics') = 5,
    'D10: Clinic inclusion must not depend on Subscription or Entitlement'
);

-- ===========================================================================
-- E. Authoritative parity (VN 16) — the regression guarantee.
--
-- For every fixture User × every fixture Clinic (including Clinics of
-- Organizations the User does not belong to) × every Clinic-context catalog
-- capability: the capability is returned for that Clinic if and only if
-- user_has_clinic_capability holds. This proves both directions:
--   * nothing is returned that the authoritative predicate denies;
--   * no Clinic or capability the predicate grants is missing — including any
--     Clinic outside the read's candidate bound.
-- ===========================================================================

create temporary table parity_case on commit drop as
select
    fixture_result.user_number,
    fixture_result.user_id,
    clinic.id as clinic_id,
    catalog_entry.capability,
    public.user_has_clinic_capability(fixture_result.user_id, clinic.id, catalog_entry.capability) as authoritative,
    exists (
        select 1
        from jsonb_array_elements(fixture_result.clinics_result -> 'clinics') as clinic_entry,
             jsonb_array_elements_text(clinic_entry -> 'capabilities') as returned_capability
        where (clinic_entry ->> 'clinic_id')::uuid = clinic.id
          and returned_capability = catalog_entry.capability
    ) as returned
from fixture_result
cross join public.clinics as clinic
cross join public.professional_capability_catalog() as catalog_entry
where clinic.id::text like '18100000-%'
  and catalog_entry.capability_context = 'CLINIC';

select pg_temp.assert_true(
    not exists (select 1 from parity_case where authoritative is distinct from returned),
    format('E: parity violated: %s',
        (select string_agg(format('U%s %s %s authoritative=%s returned=%s',
                                  user_number, clinic_id, capability, authoritative, returned), '; ')
         from parity_case where authoritative is distinct from returned))
);
select pg_temp.assert_true(
    (select count(*) from parity_case) = 17 * 7 * 16
    and (select count(*) from parity_case where authoritative) > 150
    and (select count(*) from parity_case where not authoritative) > 150
    and (select count(distinct user_number) from parity_case where authoritative) >= 7,
    'E: the parity matrix must be complete and exercise both granted and denied capabilities across several Users'
);
-- No returned Clinic falls outside the fixture Clinics, and every returned
-- Clinic has a granting predicate (a returned Clinic is never empty).
select pg_temp.assert_true(
    not exists (
        select 1
        from fixture_result, jsonb_array_elements(clinics_result -> 'clinics') as clinic_entry
        where not exists (
            select 1 from parity_case
            where parity_case.user_number = fixture_result.user_number
              and parity_case.clinic_id = (clinic_entry ->> 'clinic_id')::uuid
              and parity_case.authoritative
        )
    ),
    'E: every returned Clinic must have at least one authoritative Clinic-context capability'
);

-- ===========================================================================
-- F. Consistency with SPEC-ORG-007 (BR-18, VN 17): the returned Clinic set
--    equals the Clinics with an ORG-007 Clinic-scoped capability, plus every
--    Clinic of each Organization with an ORG-007 Organization-scoped
--    Clinic-context capability.
-- ===========================================================================

create temporary table org007_derived_clinic on commit drop as
select fixture_result.user_number, (capability_entry #>> '{clinic,clinic_id}')::uuid as clinic_id
from fixture_result,
     jsonb_array_elements(context_result -> 'organizations') as organization_entry,
     jsonb_array_elements(organization_entry -> 'capabilities') as capability_entry
where capability_entry ->> 'scope_type' = 'CLINIC'
union
select fixture_result.user_number, clinic.id
from fixture_result,
     jsonb_array_elements(context_result -> 'organizations') as organization_entry,
     jsonb_array_elements(organization_entry -> 'capabilities') as capability_entry,
     public.clinics as clinic
where capability_entry ->> 'scope_type' = 'ORGANIZATION'
  and capability_entry ->> 'capability' in (
      select catalog_entry.capability from public.professional_capability_catalog() as catalog_entry
      where catalog_entry.capability_context = 'CLINIC'
  )
  and clinic.organization_id = (organization_entry ->> 'organization_id')::uuid;

create temporary table org008_returned_clinic on commit drop as
select fixture_result.user_number, (clinic_entry ->> 'clinic_id')::uuid as clinic_id
from fixture_result, jsonb_array_elements(clinics_result -> 'clinics') as clinic_entry;

select pg_temp.assert_true(
    not exists (
        (select user_number, clinic_id from org007_derived_clinic
         except select user_number, clinic_id from org008_returned_clinic)
        union all
        (select user_number, clinic_id from org008_returned_clinic
         except select user_number, clinic_id from org007_derived_clinic)
    )
    and (select count(*) from org008_returned_clinic) > 20,
    'F: Professional Clinics must equal the Clinic set derivable from SPEC-ORG-007 (BR-18)'
);
-- Each returned Clinic appears exactly once (BR-8).
select pg_temp.assert_true(
    (select count(*) from org008_returned_clinic)
    = (select count(*) from (select distinct user_number, clinic_id from org008_returned_clinic) as distinct_clinic),
    'F: every Clinic appears at most once per result'
);

-- ===========================================================================
-- G. A Clinic created after the responsibility was granted is included
--    (BR-3), and a relationship ending removes the Clinic so that a listed
--    Clinic does not authorize a later operation (VN 20).
-- ===========================================================================

set local session_replication_role = replica;
insert into public.clinics (id, organization_id, is_published)
values ('18100000-0000-4000-8000-000000000406', '18100000-0000-4000-8000-000000000301', false);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', '18100000-0000-4000-8000-000000000104', true);
set local role authenticated;
select pg_temp.assert_true(
    '18100000-0000-4000-8000-000000000406'::uuid = any (pg_temp.clinic_ids(public.get_my_professional_clinics()))
    and (pg_temp.clinic_ids(public.get_my_professional_clinics()))[6] = '18100000-0000-4000-8000-000000000406'::uuid,
    'G: a Clinic created after the OWNER grant is returned (unnamed, ordered last)'
);
reset role;

-- U08 (Clinic RECEPTIONIST @ A3) can view A3's schedule while the grant is current.
select set_config('request.jwt.claim.sub', '18100000-0000-4000-8000-000000000108', true);
set local role authenticated;
select pg_temp.assert_true(
    (select count(*) from public.get_clinic_appointment_schedule('18100000-0000-4000-8000-000000000403')) = 0,
    'G: listed Clinic schedule is readable while the grant is current'
);
reset role;

set local session_replication_role = replica;
update public.organization_responsibility_grants
set effective_end = statement_timestamp(), ended_by_user_id = '18100000-0000-4000-8000-000000000204'
where id = '18100000-0000-4000-8000-000000000608';
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', '18100000-0000-4000-8000-000000000108', true);
set local role authenticated;
select pg_temp.assert_true(
    public.get_my_professional_clinics() = '{"clinics": []}'::jsonb,
    'G: ending the only grant removes the Clinic'
);
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''18100000-0000-4000-8000-000000000403'')',
    '42501',
    'schedule-view capability is required'
);
reset role;

rollback;

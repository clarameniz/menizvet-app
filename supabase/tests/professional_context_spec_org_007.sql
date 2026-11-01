-- Regression suite for SPEC-ORG-007 — View My Professional Context, migration
-- 20261001120000_professional_context_read.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions are
-- rolled back; superuser test execution is required solely to bypass
-- unrelated establishment triggers/foreign keys while loading a deliberately
-- minimal deterministic context (same rationale as
-- guardian_medical_history_provenance_names.sql).
--
-- Covers:
--   * capability-catalog parity and drift guards (SPEC-ORG-005 §5, VN 35);
--   * behavioral equivalence of the refactored capability helpers with their
--     previously deployed definitions;
--   * SPEC-ORG-007 BR-1..BR-11 and Verification Notes, including
--     SPEC-ORG-005 VN 29–34 for CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS;
--   * SPEC-SUB-003 Entitlement availability states;
--   * ACL / SECURITY DEFINER boundary.
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

-- Organization entry for an Organization within a context result.
create function pg_temp.org_entry(p_result jsonb, p_organization_id uuid)
returns jsonb language sql as $$
    select organization_entry
    from jsonb_array_elements(p_result -> 'organizations') as organization_entry
    where (organization_entry ->> 'organization_id')::uuid = p_organization_id
$$;

-- Sorted capability identifiers of one scope (and Clinic, for CLINIC scope).
create function pg_temp.caps(p_entry jsonb, p_scope text, p_clinic_id uuid)
returns text[] language sql as $$
    select coalesce(array_agg(capability_entry ->> 'capability' order by capability_entry ->> 'capability'), '{}')
    from jsonb_array_elements(p_entry -> 'capabilities') as capability_entry
    where capability_entry ->> 'scope_type' = p_scope
      and (
        (p_scope = 'ORGANIZATION' and jsonb_typeof(capability_entry -> 'clinic') = 'null')
        or (p_scope = 'CLINIC' and (capability_entry #>> '{clinic,clinic_id}')::uuid = p_clinic_id)
      )
$$;

create function pg_temp.sorted(p_values text[])
returns text[] language sql as $$
    select coalesce(array_agg(value order by value), '{}') from unnest(p_values) as value
$$;

-- ===========================================================================
-- A. Capability-catalog parity and drift guards.
--
-- A1. The SQL catalog must equal the Phase 1 catalog of SPEC-ORG-005 §5,
--     transcribed here. Adding, removing, or re-classifying a capability in
--     SQL without updating SPEC-ORG-005 (and this expectation) fails.
-- ===========================================================================

create temporary table expected_capability_catalog (
    capability text primary key,
    capability_context text not null
) on commit drop;

insert into expected_capability_catalog values
    -- SPEC-ORG-005 §5 — Organization administration
    ('ORGANIZATION_INVITE_MEMBERS', 'ORGANIZATION'),
    ('ORGANIZATION_REVOKE_INVITATIONS', 'ORGANIZATION'),
    ('ORGANIZATION_END_MEMBERSHIPS', 'ORGANIZATION'),
    ('ORGANIZATION_GRANT_RESPONSIBILITIES', 'ORGANIZATION'),
    ('ORGANIZATION_CREATE_CLINICS', 'ORGANIZATION'),
    ('ORGANIZATION_MANAGE_SUBSCRIPTION', 'ORGANIZATION'),
    -- SPEC-ORG-005 §5 — Clinic administration
    ('CLINIC_MANAGE_LOCATION', 'CLINIC'),
    ('CLINIC_MANAGE_PUBLICATION', 'CLINIC'),
    ('CLINIC_MANAGE_PUBLIC_PROFILE', 'CLINIC'),
    ('CLINIC_MANAGE_SERVICES', 'CLINIC'),
    ('CLINIC_MANAGE_OPENING_HOURS', 'CLINIC'),
    ('CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS', 'CLINIC'),
    -- SPEC-ORG-005 §5 — Appointment operations
    ('APPOINTMENT_VIEW_SCHEDULE', 'CLINIC'),
    ('APPOINTMENT_CONFIRM', 'CLINIC'),
    ('APPOINTMENT_CANCEL', 'CLINIC'),
    ('APPOINTMENT_RESCHEDULE', 'CLINIC'),
    ('APPOINTMENT_ASSIGN_VETERINARIAN', 'CLINIC'),
    ('APPOINTMENT_COMPLETE', 'CLINIC'),
    ('APPOINTMENT_MARK_NO_SHOW', 'CLINIC'),
    ('APPOINTMENT_MANAGE_AVAILABILITY', 'CLINIC'),
    -- SPEC-ORG-005 §5 — Clinical professional operations
    ('CLINICAL_CARE', 'CLINIC'),
    ('CLINICAL_DOCUMENTATION', 'CLINIC');

select pg_temp.assert_true(
    not exists (
        (select capability, capability_context from public.professional_capability_catalog()
         except
         select capability, capability_context from expected_capability_catalog)
        union all
        (select capability, capability_context from expected_capability_catalog
         except
         select capability, capability_context from public.professional_capability_catalog())
    )
    and (select count(*) from public.professional_capability_catalog()) = 22,
    'A1: professional_capability_catalog() must equal the SPEC-ORG-005 §5 Phase 1 catalog'
);

-- Expected capability sets derived from the SPEC-ORG-005 transcription above
-- (not from SQL), readable by the impersonated `authenticated` role.
create temporary table expected_capability_set (
    set_name text primary key,
    capabilities text[] not null
) on commit drop;

insert into expected_capability_set
select 'ORGANIZATION_ADMINISTRATION_ALL', array_agg(capability order by capability)
from expected_capability_catalog
where capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
union all
select 'CLINIC_ADMINISTRATOR', array_agg(capability order by capability)
from expected_capability_catalog
where capability_context = 'CLINIC' and capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
union all
select 'APPOINTMENT_OPERATIONS', array_agg(capability order by capability)
from expected_capability_catalog
where capability like 'APPOINTMENT\_%';

grant select on expected_capability_set to authenticated;

create function pg_temp.expected_caps(p_set_name text)
returns text[] language sql as $$
    select capabilities from expected_capability_set where set_name = p_set_name
$$;

select pg_temp.assert_true(
    cardinality(pg_temp.expected_caps('ORGANIZATION_ADMINISTRATION_ALL')) = 20
    and cardinality(pg_temp.expected_caps('CLINIC_ADMINISTRATOR')) = 14
    and cardinality(pg_temp.expected_caps('APPOINTMENT_OPERATIONS')) = 8,
    'Expected capability sets must match SPEC-ORG-005 §6 sizes'
);

-- A2. Every capability-identifier literal passed to a capability or
--     Entitlement helper by any public function must be a catalog capability
--     or a SPEC-SUB-003 Entitlement identifier. This catches a protected
--     operation (or a helper) using an undocumented capability identifier,
--     which is how CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS originally entered
--     SQL. The guard also requires every call site to be parseable, so a call
--     shape it cannot inspect fails loudly instead of being skipped.
create temporary table capability_helper_call on commit drop as
select
    procedure_record.proname as caller,
    call_match[1] as helper,
    call_match[2] as arguments
from pg_proc as procedure_record
cross join lateral regexp_matches(
    procedure_record.prosrc,
    '(user_has_clinic_capability|user_has_organization_capability|user_has_organization_scoped_clinic_capability|user_has_clinic_scoped_clinic_capability|assert_clinic_capability_after_lock|assert_clinic_appointment_authorization_after_lock|assert_clinic_organization_entitlement_after_lock|resolve_current_veterinarian_context_after_lock|find_current_veterinarian_context_after_lock|organization_has_professional_entitlement)\s*\(([^()]*)\)',
    'g'
) as call_match
where procedure_record.pronamespace = 'public'::regnamespace;

select pg_temp.assert_true(
    (select count(*) from capability_helper_call)
    = (
        select count(*)
        from pg_proc as procedure_record
        cross join lateral regexp_matches(
            procedure_record.prosrc,
            '(user_has_clinic_capability|user_has_organization_capability|user_has_organization_scoped_clinic_capability|user_has_clinic_scoped_clinic_capability|assert_clinic_capability_after_lock|assert_clinic_appointment_authorization_after_lock|assert_clinic_organization_entitlement_after_lock|resolve_current_veterinarian_context_after_lock|find_current_veterinarian_context_after_lock|organization_has_professional_entitlement)\s*\(',
            'g'
        ) as call_match
        where procedure_record.pronamespace = 'public'::regnamespace
    )
    and (select count(*) from capability_helper_call) > 40,
    'A2: every capability/Entitlement helper call site must be parseable by the drift guard'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from capability_helper_call
        cross join lateral regexp_matches(capability_helper_call.arguments, '''([A-Z][A-Z_]*)''', 'g') as literal_match
        where literal_match[1] not in (select capability from expected_capability_catalog)
          and literal_match[1] not in (
              'APPOINTMENT_MANAGEMENT', 'PROFESSIONAL_SCHEDULING',
              'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
          )
    ),
    'A2: a capability helper is called with an identifier outside the SPEC-ORG-005 catalog and SPEC-SUB-003 Entitlements'
);

-- A3. The complete identifier set must come from the catalog: the
--     Organization helper and both scoped Clinic helpers consult
--     professional_capability_catalog() rather than a complete inline list,
--     and the Clinic helper is exactly the disjunction of the two scoped
--     predicates. The scoped helpers legitimately keep responsibility-specific
--     capability subsets (for example RECEPTIONIST and VETERINARIAN); those
--     subsets are the authoritative responsibility-to-capability mapping.
select pg_temp.assert_true(
    (select prosrc from pg_proc where oid = 'public.user_has_organization_capability(uuid,uuid,text)'::regprocedure)
        like '%professional_capability_catalog%'
    and (select prosrc from pg_proc where oid = 'public.user_has_organization_capability(uuid,uuid,text)'::regprocedure)
        not like '%''ORGANIZATION\_%'
    and (select prosrc from pg_proc where oid = 'public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)
        like '%user_has_organization_scoped_clinic_capability%'
    and (select prosrc from pg_proc where oid = 'public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)
        like '%user_has_clinic_scoped_clinic_capability%'
    and (select prosrc from pg_proc where oid = 'public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)
        not like '%''CLINIC\_%'
    and (select prosrc from pg_proc where oid = 'public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)
        not like '%''APPOINTMENT\_%'
    and (select prosrc from pg_proc where oid = 'public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)
        like '%professional_capability_catalog%'
    and (select prosrc from pg_proc where oid = 'public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)
        like '%professional_capability_catalog%',
    'A3: capability helpers must derive their identifier set from professional_capability_catalog()'
);

-- ===========================================================================
-- B. Legacy reference definitions (verbatim bodies deployed before
--    20261001120000) used to prove the refactor changed no authorization.
-- ===========================================================================

create function pg_temp.legacy_user_has_organization_capability(
    p_user_id uuid, p_organization_id uuid, p_capability text
)
returns boolean language sql stable as $$
    select
        coalesce(
            p_capability in (
                'ORGANIZATION_INVITE_MEMBERS',
                'ORGANIZATION_REVOKE_INVITATIONS',
                'ORGANIZATION_END_MEMBERSHIPS',
                'ORGANIZATION_GRANT_RESPONSIBILITIES',
                'ORGANIZATION_CREATE_CLINICS',
                'ORGANIZATION_MANAGE_SUBSCRIPTION'
            ),
            false
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as grant_record
              on grant_record.membership_id = membership.id
            where membership.user_id = p_user_id
              and membership.organization_id = p_organization_id
              and membership.effective_end is null
              and grant_record.effective_end is null
              and grant_record.scope_type = 'ORGANIZATION'
              and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
        )
$$;

create function pg_temp.legacy_user_has_clinic_capability(
    p_user_id uuid, p_clinic_id uuid, p_capability text
)
returns boolean language sql stable as $$
    select coalesce(
        p_capability in (
            'CLINIC_MANAGE_LOCATION', 'CLINIC_MANAGE_PUBLIC_PROFILE',
            'CLINIC_MANAGE_PUBLICATION', 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
            'CLINIC_MANAGE_SERVICES', 'CLINIC_MANAGE_OPENING_HOURS',
            'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
            'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
            'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
            'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW',
            'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
        )
        and (
            exists (
                select 1
                from public.clinics as clinic
                join public.organization_memberships as membership
                  on membership.organization_id = clinic.organization_id
                join public.organization_responsibility_grants as responsibility_grant
                  on responsibility_grant.membership_id = membership.id
                where clinic.id = p_clinic_id
                  and membership.user_id = p_user_id
                  and membership.effective_end is null
                  and responsibility_grant.effective_end is null
                  and (
                    (
                      responsibility_grant.scope_type = 'ORGANIZATION'
                      and responsibility_grant.clinic_id is null
                      and responsibility_grant.responsibility in ('OWNER', 'ADMINISTRATOR')
                      and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                    )
                    or (
                      responsibility_grant.scope_type = 'CLINIC'
                      and responsibility_grant.clinic_id = p_clinic_id
                      and responsibility_grant.responsibility = 'ADMINISTRATOR'
                      and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                    )
                    or (
                      responsibility_grant.responsibility = 'RECEPTIONIST'
                      and p_capability in (
                        'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
                        'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
                        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
                        'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW'
                      )
                      and (
                        (responsibility_grant.scope_type = 'ORGANIZATION' and responsibility_grant.clinic_id is null)
                        or (responsibility_grant.scope_type = 'CLINIC' and responsibility_grant.clinic_id = p_clinic_id)
                      )
                    )
                  )
            )
            or (
                p_capability in (
                    'APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE',
                    'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
                )
                and exists (
                    select 1
                    from public.clinics as clinic
                    join public.organization_memberships as membership
                      on membership.organization_id = clinic.organization_id
                    join public.organization_responsibility_grants as responsibility_grant
                      on responsibility_grant.membership_id = membership.id
                    join public.veterinarian_clinic_assignments as clinic_assignment
                      on clinic_assignment.supporting_membership_id = membership.id
                     and clinic_assignment.clinic_id = p_clinic_id
                    join public.veterinarian_professional_profiles as profile
                      on profile.id = clinic_assignment.professional_profile_id
                     and profile.user_id = p_user_id
                    where clinic.id = p_clinic_id
                      and membership.user_id = p_user_id
                      and membership.effective_end is null
                      and responsibility_grant.effective_end is null
                      and responsibility_grant.membership_id = membership.id
                      and responsibility_grant.responsibility = 'VETERINARIAN'
                      and responsibility_grant.scope_type = 'ORGANIZATION'
                      and responsibility_grant.clinic_id is null
                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
                )
            )
        ), false
    )
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects 18000000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian only                 08 VETERINARIAN, Clinic Assignment ended
--   02 OrgA OWNER                    09 Profile only; ended OrgB Membership
--   03 OrgA ADMINISTRATOR (Org)      10 OrgA Member whose ADMINISTRATOR grant ended
--   04 ADMINISTRATOR @ A2 (Clinic)   11 OrgB OWNER + VETERINARIAN assigned @ B1
--   05 RECEPTIONIST @ A3 (Clinic)    12 OWNER of six commercially distinct Orgs
--   06 OrgA RECEPTIONIST (Org)       13 authenticated subject without domain User
--   07 VETERINARIAN assigned @ A1
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('18000000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 13) as n;

insert into public.users (id)
select ('18000000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 12) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select
    ('18000000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
    ('18000000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 12) as n;

-- Organizations.
insert into public.veterinary_organizations (id, display_name) values
    ('18000000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'), -- OrgA, ACTIVE
    ('18000000-0000-4000-8000-000000000302', 'VetCare Group'),             -- OrgB, no Subscription
    ('18000000-0000-4000-8000-000000000303', 'Org 1 Pending'),             -- PENDING
    ('18000000-0000-4000-8000-000000000304', 'Org 2 Expired'),             -- EXPIRED
    ('18000000-0000-4000-8000-000000000305', 'Org 3 Past Due'),            -- PAST_DUE
    ('18000000-0000-4000-8000-000000000306', 'Org 4 Cancelled Valid'),     -- CANCELLED, still valid
    ('18000000-0000-4000-8000-000000000307', 'Org 5 Cancelled Lapsed'),    -- CANCELLED, validity ended
    ('18000000-0000-4000-8000-000000000308', 'Org 6 Active Lapsed');       -- ACTIVE, validity ended

-- Clinics: A1 published+named, A2 unpublished+named, A3 unpublished without
-- any public profile (no display name), B1 in OrgB, P1 in the PENDING Org.
insert into public.clinics (id, organization_id, is_published) values
    ('18000000-0000-4000-8000-000000000401', '18000000-0000-4000-8000-000000000301', true),
    ('18000000-0000-4000-8000-000000000402', '18000000-0000-4000-8000-000000000301', false),
    ('18000000-0000-4000-8000-000000000403', '18000000-0000-4000-8000-000000000301', false),
    ('18000000-0000-4000-8000-000000000404', '18000000-0000-4000-8000-000000000302', true),
    ('18000000-0000-4000-8000-000000000405', '18000000-0000-4000-8000-000000000303', false);
insert into public.clinic_public_profiles (clinic_id, display_name, description) values
    ('18000000-0000-4000-8000-000000000401', 'Animalia Madrid Centro', 'Private description must not leak'),
    ('18000000-0000-4000-8000-000000000402', 'Animalia Getafe', null),
    ('18000000-0000-4000-8000-000000000404', 'VetCare Centro', null),
    ('18000000-0000-4000-8000-000000000405', 'Pending Clinic', null);

-- Memberships (…05NN) and grants (…06NN).
insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    ('18000000-0000-4000-8000-000000000502', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000202', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000503', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000203', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000504', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000204', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000505', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000205', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000506', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000206', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000507', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000207', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000508', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000208', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000509', '18000000-0000-4000-8000-000000000302', '18000000-0000-4000-8000-000000000209', '2020-01-01Z', '2021-01-01Z', '18000000-0000-4000-8000-000000000209'),
    ('18000000-0000-4000-8000-000000000510', '18000000-0000-4000-8000-000000000301', '18000000-0000-4000-8000-000000000210', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000511', '18000000-0000-4000-8000-000000000302', '18000000-0000-4000-8000-000000000211', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000513', '18000000-0000-4000-8000-000000000303', '18000000-0000-4000-8000-000000000212', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000514', '18000000-0000-4000-8000-000000000304', '18000000-0000-4000-8000-000000000212', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000515', '18000000-0000-4000-8000-000000000305', '18000000-0000-4000-8000-000000000212', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000516', '18000000-0000-4000-8000-000000000306', '18000000-0000-4000-8000-000000000212', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000517', '18000000-0000-4000-8000-000000000307', '18000000-0000-4000-8000-000000000212', '2020-01-01Z', null, null),
    ('18000000-0000-4000-8000-000000000518', '18000000-0000-4000-8000-000000000308', '18000000-0000-4000-8000-000000000212', '2020-01-01Z', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('18000000-0000-4000-8000-000000000602', '18000000-0000-4000-8000-000000000502', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000603', '18000000-0000-4000-8000-000000000503', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000604', '18000000-0000-4000-8000-000000000504', 'ADMINISTRATOR', 'CLINIC', '18000000-0000-4000-8000-000000000402', '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000605', '18000000-0000-4000-8000-000000000505', 'RECEPTIONIST', 'CLINIC', '18000000-0000-4000-8000-000000000403', '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000606', '18000000-0000-4000-8000-000000000506', 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000607', '18000000-0000-4000-8000-000000000507', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000608', '18000000-0000-4000-8000-000000000508', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000202', null),
    ('18000000-0000-4000-8000-000000000609', '18000000-0000-4000-8000-000000000509', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000209', null),
    ('18000000-0000-4000-8000-000000000610', '18000000-0000-4000-8000-000000000510', 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', '18000000-0000-4000-8000-000000000202', '18000000-0000-4000-8000-000000000202'),
    ('18000000-0000-4000-8000-000000000611', '18000000-0000-4000-8000-000000000511', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000211', null),
    ('18000000-0000-4000-8000-000000000612', '18000000-0000-4000-8000-000000000511', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000211', null),
    ('18000000-0000-4000-8000-000000000613', '18000000-0000-4000-8000-000000000513', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000212', null),
    ('18000000-0000-4000-8000-000000000614', '18000000-0000-4000-8000-000000000514', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000212', null),
    ('18000000-0000-4000-8000-000000000615', '18000000-0000-4000-8000-000000000515', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000212', null),
    ('18000000-0000-4000-8000-000000000616', '18000000-0000-4000-8000-000000000516', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000212', null),
    ('18000000-0000-4000-8000-000000000617', '18000000-0000-4000-8000-000000000517', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000212', null),
    ('18000000-0000-4000-8000-000000000618', '18000000-0000-4000-8000-000000000518', 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, '18000000-0000-4000-8000-000000000212', null);

-- Professional Profiles (…07NN) and Clinic Assignments (…08NN).
insert into public.veterinarian_professional_profiles (id, user_id) values
    ('18000000-0000-4000-8000-000000000707', '18000000-0000-4000-8000-000000000207'),
    ('18000000-0000-4000-8000-000000000708', '18000000-0000-4000-8000-000000000208'),
    ('18000000-0000-4000-8000-000000000709', '18000000-0000-4000-8000-000000000209'),
    ('18000000-0000-4000-8000-000000000711', '18000000-0000-4000-8000-000000000211');

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    -- U07: current @ A1.
    ('18000000-0000-4000-8000-000000000807', '18000000-0000-4000-8000-000000000707', '18000000-0000-4000-8000-000000000507', '18000000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    -- U08: ended @ A1.
    ('18000000-0000-4000-8000-000000000808', '18000000-0000-4000-8000-000000000708', '18000000-0000-4000-8000-000000000508', '18000000-0000-4000-8000-000000000401', '2020-01-01Z', '2021-01-01Z'),
    -- U09: open row supported by an ENDED Membership (not current).
    ('18000000-0000-4000-8000-000000000809', '18000000-0000-4000-8000-000000000709', '18000000-0000-4000-8000-000000000509', '18000000-0000-4000-8000-000000000404', '2020-01-01Z', null),
    -- U11: current @ B1.
    ('18000000-0000-4000-8000-000000000811', '18000000-0000-4000-8000-000000000711', '18000000-0000-4000-8000-000000000511', '18000000-0000-4000-8000-000000000404', '2020-01-01Z', null);

-- Subscriptions (…09NN). OrgB has none.
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values
    ('18000000-0000-4000-8000-000000000901', '18000000-0000-4000-8000-000000000301', '2020-01-01Z', 'ACTIVE',    '2020-01-01Z', null, null,                              'spec-org-007-test', '18000000-0000-4000-8000-000000000a01'),
    ('18000000-0000-4000-8000-000000000903', '18000000-0000-4000-8000-000000000303', '2020-01-01Z', 'PENDING',   '2020-01-01Z', null, null,                              'spec-org-007-test', '18000000-0000-4000-8000-000000000a03'),
    ('18000000-0000-4000-8000-000000000904', '18000000-0000-4000-8000-000000000304', '2020-01-01Z', 'EXPIRED',   '2020-01-01Z', null, null,                              'spec-org-007-test', '18000000-0000-4000-8000-000000000a04'),
    ('18000000-0000-4000-8000-000000000905', '18000000-0000-4000-8000-000000000305', '2020-01-01Z', 'PAST_DUE',  '2020-01-01Z', null, null,                              'spec-org-007-test', '18000000-0000-4000-8000-000000000a05'),
    ('18000000-0000-4000-8000-000000000906', '18000000-0000-4000-8000-000000000306', '2020-01-01Z', 'CANCELLED', '2020-01-01Z', null, statement_timestamp() + interval '365 days', 'spec-org-007-test', '18000000-0000-4000-8000-000000000a06'),
    ('18000000-0000-4000-8000-000000000907', '18000000-0000-4000-8000-000000000307', '2020-01-01Z', 'CANCELLED', '2020-01-01Z', null, '2021-01-01Z',                     'spec-org-007-test', '18000000-0000-4000-8000-000000000a07'),
    ('18000000-0000-4000-8000-000000000908', '18000000-0000-4000-8000-000000000308', '2020-01-01Z', 'ACTIVE',    '2020-01-01Z', null, '2021-01-01Z',                     'spec-org-007-test', '18000000-0000-4000-8000-000000000a08');

-- Guardian data that must never appear in a professional context.
insert into public.pets (id, name, species, created_at)
values ('18000000-0000-4000-8000-000000000b01', 'Luna', 'canine', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values ('18000000-0000-4000-8000-000000000b02', '18000000-0000-4000-8000-000000000201', '18000000-0000-4000-8000-000000000b01', '2020-01-01Z');

-- Fixture loading is complete. All following equivalence, ACL, and
-- behavioral assertions run under normal trigger behavior.
set local session_replication_role = origin;

-- ===========================================================================
-- B1. Refactored helpers are behaviorally identical to the legacy
--     definitions across every fixture User × Clinic/Organization ×
--     identifier (catalog, unknown, Entitlement identifier, empty, null).
-- ===========================================================================

create temporary table probe_identifier on commit drop as
select capability as identifier from public.professional_capability_catalog()
union all select 'UNKNOWN_CAPABILITY'
union all select 'APPOINTMENT_MANAGEMENT'
union all select ''
union all select null;

create temporary table probe_user on commit drop as
select id as user_id from public.users where id::text like '18000000-%'
union all select null
union all select '18000000-0000-4000-8000-0000000002ff'::uuid;

create temporary table probe_clinic on commit drop as
select id as clinic_id from public.clinics where id::text like '18000000-%'
union all select null
union all select '18000000-0000-4000-8000-0000000004ff'::uuid;

create temporary table probe_organization on commit drop as
select id as organization_id from public.veterinary_organizations where id::text like '18000000-%'
union all select null;

select pg_temp.assert_true(
    not exists (
        select 1
        from probe_user, probe_clinic, probe_identifier
        where public.user_has_clinic_capability(probe_user.user_id, probe_clinic.clinic_id, probe_identifier.identifier)
              is distinct from
              pg_temp.legacy_user_has_clinic_capability(probe_user.user_id, probe_clinic.clinic_id, probe_identifier.identifier)
    ),
    'B1: user_has_clinic_capability must be behaviorally identical to its previous definition'
);
select pg_temp.assert_true(
    (select count(*) from probe_user, probe_clinic, probe_identifier
     where public.user_has_clinic_capability(probe_user.user_id, probe_clinic.clinic_id, probe_identifier.identifier)) > 50,
    'B1: the equivalence matrix must include granted capabilities, not only denials'
);
select pg_temp.assert_true(
    not exists (
        select 1
        from probe_user, probe_organization, probe_identifier
        where public.user_has_organization_capability(probe_user.user_id, probe_organization.organization_id, probe_identifier.identifier)
              is distinct from
              pg_temp.legacy_user_has_organization_capability(probe_user.user_id, probe_organization.organization_id, probe_identifier.identifier)
    ),
    'B1: user_has_organization_capability must be behaviorally identical to its previous definition'
);
select pg_temp.assert_true(
    (select count(*) from probe_user, probe_organization, probe_identifier
     where public.user_has_organization_capability(probe_user.user_id, probe_organization.organization_id, probe_identifier.identifier)) > 10,
    'B1: the Organization equivalence matrix must include granted capabilities'
);

-- B2. Every catalog capability is provided by at least one current
--     responsibility in the fixture (no dead catalog entries).
select pg_temp.assert_true(
    not exists (
        select 1
        from public.professional_capability_catalog() as catalog_entry
        where not exists (
            select 1 from probe_user, probe_clinic
            where catalog_entry.capability_context = 'CLINIC'
              and public.user_has_clinic_capability(probe_user.user_id, probe_clinic.clinic_id, catalog_entry.capability)
        )
        and not exists (
            select 1 from probe_user, probe_organization
            where catalog_entry.capability_context = 'ORGANIZATION'
              and public.user_has_organization_capability(probe_user.user_id, probe_organization.organization_id, catalog_entry.capability)
        )
    ),
    'B2: every catalog capability must be reachable through some current responsibility'
);

-- ===========================================================================
-- C. ACL / SECURITY DEFINER boundary.
-- ===========================================================================

select pg_temp.assert_true(
    has_function_privilege('authenticated', 'public.get_my_professional_context()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_my_professional_context()', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_my_professional_context()', 'EXECUTE'),
    'C: only authenticated (not anon/public) may execute get_my_professional_context()'
);
select pg_temp.assert_true(
    (select bool_and(
        not has_function_privilege('authenticated', signature, 'EXECUTE')
        and not has_function_privilege('anon', signature, 'EXECUTE')
        and not has_function_privilege('public', signature, 'EXECUTE')
     )
     from unnest(array[
        'public.professional_capability_catalog()',
        'public.user_has_organization_capability(uuid,uuid,text)',
        'public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)',
        'public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)',
        'public.user_has_clinic_capability(uuid,uuid,text)'
     ]) as signature),
    'C: capability helpers must remain non-executable by authenticated/anon/public'
);
select pg_temp.assert_true(
    (select prosecdef and provolatile = 's'
            and proconfig @> array['search_path=""']
     from pg_proc where oid = 'public.get_my_professional_context()'::regprocedure),
    'C: get_my_professional_context() must be STABLE SECURITY DEFINER with an empty search_path'
);
select pg_temp.assert_true(
    not has_table_privilege('authenticated', 'public.organization_memberships', 'SELECT')
    and not has_table_privilege('authenticated', 'public.organization_responsibility_grants', 'SELECT')
    and not has_table_privilege('authenticated', 'public.veterinarian_clinic_assignments', 'SELECT')
    and not has_table_privilege('authenticated', 'public.clinic_public_profiles', 'SELECT')
    and not has_table_privilege('authenticated', 'public.organization_subscriptions', 'SELECT'),
    'C: no direct table SELECT was granted to authenticated'
);

-- C2. anon is denied; an authenticated call without a subject, or with a
--     subject that has no domain User, is rejected (28000).
set local role anon;
select pg_temp.assert_error('select public.get_my_professional_context()', '42501', null);
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error('select public.get_my_professional_context()', '28000', 'Authentication is required');
reset role;

select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000113', true);
set local role authenticated;
select pg_temp.assert_error('select public.get_my_professional_context()', '28000', 'No coherent domain User');
reset role;

-- ===========================================================================
-- D. Behavior (SPEC-ORG-007), evaluated as `authenticated`.
-- ===========================================================================

-- D1. Guardian-only User: exact empty context; no Pet/Guardianship data.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000101', true);
set local role authenticated;
do $$
declare result jsonb := public.get_my_professional_context();
begin
    perform pg_temp.assert_true(
        result = '{"has_veterinarian_professional_profile": false, "organizations": []}'::jsonb,
        format('D1: Guardian-only User must receive the exact empty context, got %s', result)
    );
end;
$$;
reset role;

-- D2. Organization OWNER.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000102', true);
set local role authenticated;
do $$
declare
    result jsonb := public.get_my_professional_context();
    org jsonb := pg_temp.org_entry(result, '18000000-0000-4000-8000-000000000301');
    expected_admin text[] := pg_temp.expected_caps('ORGANIZATION_ADMINISTRATION_ALL');
begin
    perform pg_temp.assert_true(jsonb_array_length(result -> 'organizations') = 1, 'D2: OWNER sees exactly one Organization');
    perform pg_temp.assert_true(
        (select array_agg(key order by key) from jsonb_object_keys(result) as key) = array['has_veterinarian_professional_profile', 'organizations']
        and (select array_agg(key order by key) from jsonb_object_keys(org) as key)
            = array['capabilities', 'clinic_assignments', 'entitlements', 'membership_id', 'organization_display_name', 'organization_id', 'responsibilities'],
        'D2: result and Organization entry expose only the approved keys'
    );
    perform pg_temp.assert_true(
        org ->> 'membership_id' = '18000000-0000-4000-8000-000000000502'
        and org ->> 'organization_display_name' = 'Animalia Veterinary Group',
        'D2: Membership and Organization identity returned'
    );
    perform pg_temp.assert_true(
        org -> 'responsibilities' = '[{"responsibility": "OWNER", "scope_type": "ORGANIZATION", "clinic": null}]'::jsonb,
        'D2: only the OWNER responsibility of the caller is returned'
    );
    perform pg_temp.assert_true(
        pg_temp.caps(org, 'ORGANIZATION', null) = expected_admin
        and 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS' = any (pg_temp.caps(org, 'ORGANIZATION', null))
        and jsonb_array_length(org -> 'capabilities') = 20,
        'D2: OWNER receives exactly the 20 Organization-scoped non-clinical capabilities'
    );
    perform pg_temp.assert_true(
        not (org -> 'capabilities')::text like '%CLINICAL_%',
        'D2: OWNER receives no CLINICAL_* capability'
    );
    perform pg_temp.assert_true(
        org -> 'clinic_assignments' = '[]'::jsonb
        and (result ->> 'has_veterinarian_professional_profile')::boolean = false,
        'D2: OWNER without Profile/Assignment'
    );
    perform pg_temp.assert_true(
        org -> 'entitlements' = '{"APPOINTMENT_MANAGEMENT": true, "PROFESSIONAL_SCHEDULING": true, "CLINICAL_CARE": true, "CLINICAL_DOCUMENTATION": true}'::jsonb,
        'D2: ACTIVE Subscription makes all four Entitlements available'
    );
    -- Privacy: no other Member's Membership, no Pet/medical/commercial data.
    perform pg_temp.assert_true(
        position('18000000-0000-4000-8000-000000000503' in result::text) = 0
        and position('18000000-0000-4000-8000-000000000507' in result::text) = 0
        and position('18000000-0000-4000-8000-000000000302' in result::text) = 0
        and position('Luna' in result::text) = 0
        and position('Private description' in result::text) = 0
        and position('spec-org-007-test' in result::text) = 0
        and position('valid_until' in result::text) = 0,
        'D2: no other User, other Organization, Pet, Clinic configuration, or commercial data is exposed'
    );
end;
$$;
reset role;

-- D3. Organization ADMINISTRATOR has the same Organization-scoped mapping.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000103', true);
set local role authenticated;
do $$
declare
    org jsonb := pg_temp.org_entry(public.get_my_professional_context(), '18000000-0000-4000-8000-000000000301');
begin
    perform pg_temp.assert_true(
        org -> 'responsibilities' = '[{"responsibility": "ADMINISTRATOR", "scope_type": "ORGANIZATION", "clinic": null}]'::jsonb
        and pg_temp.caps(org, 'ORGANIZATION', null) = pg_temp.expected_caps('ORGANIZATION_ADMINISTRATION_ALL')
        and jsonb_array_length(org -> 'capabilities') = 20,
        'D3: Organization ADMINISTRATOR receives the 20 Organization-scoped non-clinical capabilities'
    );
end;
$$;
reset role;

-- D4. Clinic-scoped ADMINISTRATOR at the unpublished Clinic A2.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000104', true);
set local role authenticated;
do $$
declare
    org jsonb := pg_temp.org_entry(public.get_my_professional_context(), '18000000-0000-4000-8000-000000000301');
    a2 uuid := '18000000-0000-4000-8000-000000000402';
begin
    perform pg_temp.assert_true(
        org -> 'responsibilities' = jsonb_build_array(jsonb_build_object(
            'responsibility', 'ADMINISTRATOR', 'scope_type', 'CLINIC',
            'clinic', jsonb_build_object('clinic_id', a2, 'clinic_display_name', 'Animalia Getafe'))),
        'D4: Clinic-scoped responsibility carries the unpublished Clinic identity'
    );
    perform pg_temp.assert_true(
        pg_temp.caps(org, 'ORGANIZATION', null) = '{}'
        and pg_temp.caps(org, 'CLINIC', a2) = pg_temp.expected_caps('CLINIC_ADMINISTRATOR')
        and jsonb_array_length(org -> 'capabilities') = 14,
        'D4: Clinic ADMINISTRATOR receives only the 14 Clinic-scoped capabilities for A2'
    );
    perform pg_temp.assert_true(
        (select count(*) from jsonb_array_elements(org -> 'capabilities') as capability_entry
         where capability_entry ->> 'capability' = 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS') = 1
        and 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS' = any (pg_temp.caps(org, 'CLINIC', a2)),
        'D4: CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS only at A2'
    );
    perform pg_temp.assert_true(
        (select bool_and(capability_entry #>> '{clinic,clinic_display_name}' = 'Animalia Getafe'
                         and (select count(*) from jsonb_object_keys(capability_entry -> 'clinic')) = 2)
         from jsonb_array_elements(org -> 'capabilities') as capability_entry),
        'D4: Clinic identity is exactly {clinic_id, clinic_display_name}'
    );
end;
$$;
reset role;

-- D5. Clinic-scoped RECEPTIONIST at A3 (no display name).
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000105', true);
set local role authenticated;
do $$
declare
    org jsonb := pg_temp.org_entry(public.get_my_professional_context(), '18000000-0000-4000-8000-000000000301');
    a3 uuid := '18000000-0000-4000-8000-000000000403';
    appointment_caps text[] := pg_temp.expected_caps('APPOINTMENT_OPERATIONS');
begin
    perform pg_temp.assert_true(
        org -> 'responsibilities' = jsonb_build_array(jsonb_build_object(
            'responsibility', 'RECEPTIONIST', 'scope_type', 'CLINIC',
            'clinic', jsonb_build_object('clinic_id', a3, 'clinic_display_name', null))),
        'D5: Clinic without a display name is returned by id with a null display name'
    );
    perform pg_temp.assert_true(
        pg_temp.caps(org, 'CLINIC', a3) = appointment_caps
        and pg_temp.caps(org, 'ORGANIZATION', null) = '{}'
        and jsonb_array_length(org -> 'capabilities') = 8,
        'D5: Clinic RECEPTIONIST receives only the 8 Appointment capabilities for A3'
    );
    perform pg_temp.assert_true(
        not (org -> 'capabilities')::text like '%CLINIC_MANAGE_%'
        and not (org -> 'capabilities')::text like '%ORGANIZATION_%',
        'D5: RECEPTIONIST receives no Clinic administration or Assignment-management capability'
    );
end;
$$;
reset role;

-- D6. Organization-scoped RECEPTIONIST.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000106', true);
set local role authenticated;
do $$
declare
    org jsonb := pg_temp.org_entry(public.get_my_professional_context(), '18000000-0000-4000-8000-000000000301');
begin
    perform pg_temp.assert_true(
        pg_temp.caps(org, 'ORGANIZATION', null) = pg_temp.expected_caps('APPOINTMENT_OPERATIONS')
        and jsonb_array_length(org -> 'capabilities') = 8
        and not (org -> 'capabilities')::text like '%CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS%',
        'D6: Organization RECEPTIONIST receives only Organization-scoped Appointment capabilities'
    );
end;
$$;
reset role;

-- D7. VETERINARIAN with Profile and current Assignment @ A1; capability
--     absent while Entitlement is available.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000107', true);
set local role authenticated;
do $$
declare
    result jsonb := public.get_my_professional_context();
    org jsonb := pg_temp.org_entry(result, '18000000-0000-4000-8000-000000000301');
    a1 uuid := '18000000-0000-4000-8000-000000000401';
begin
    perform pg_temp.assert_true((result ->> 'has_veterinarian_professional_profile')::boolean, 'D7: Profile reported');
    perform pg_temp.assert_true(
        org -> 'responsibilities' = '[{"responsibility": "VETERINARIAN", "scope_type": "ORGANIZATION", "clinic": null}]'::jsonb,
        'D7: VETERINARIAN responsibility returned'
    );
    perform pg_temp.assert_true(
        pg_temp.caps(org, 'ORGANIZATION', null) = '{}'
        and pg_temp.caps(org, 'CLINIC', a1) = array['APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION']
        and jsonb_array_length(org -> 'capabilities') = 4,
        'D7: only the four Veterinarian capabilities, scoped to the assigned Clinic A1'
    );
    perform pg_temp.assert_true(
        org -> 'clinic_assignments' = jsonb_build_array(jsonb_build_object(
            'veterinarian_clinic_assignment_id', '18000000-0000-4000-8000-000000000807',
            'clinic', jsonb_build_object('clinic_id', a1, 'clinic_display_name', 'Animalia Madrid Centro'))),
        'D7: current Clinic Assignment with Clinic identity'
    );
    perform pg_temp.assert_true(
        (org #>> '{entitlements,APPOINTMENT_MANAGEMENT}')::boolean
        and not 'APPOINTMENT_CONFIRM' = any (pg_temp.caps(org, 'CLINIC', a1))
        and not (org -> 'capabilities')::text like '%CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS%',
        'D7: Entitlement available while the capability is absent (independence); no Assignment management'
    );
end;
$$;
reset role;

-- D8. VETERINARIAN whose Clinic Assignment ended: no clinical capability.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000108', true);
set local role authenticated;
do $$
declare
    org jsonb := pg_temp.org_entry(public.get_my_professional_context(), '18000000-0000-4000-8000-000000000301');
begin
    perform pg_temp.assert_true(
        org -> 'responsibilities' = '[{"responsibility": "VETERINARIAN", "scope_type": "ORGANIZATION", "clinic": null}]'::jsonb
        and org -> 'capabilities' = '[]'::jsonb
        and org -> 'clinic_assignments' = '[]'::jsonb,
        'D8: ended Clinic Assignment is excluded and provides no clinical capability'
    );
end;
$$;
reset role;

-- D9. Profile only; ended Membership (and an open Assignment row supported by
--     it) excluded; no Organization context fabricated.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000109', true);
set local role authenticated;
do $$
declare result jsonb := public.get_my_professional_context();
begin
    perform pg_temp.assert_true(
        result = '{"has_veterinarian_professional_profile": true, "organizations": []}'::jsonb,
        format('D9: ended Membership excluded; Profile reported without Organization context, got %s', result)
    );
end;
$$;
reset role;

-- D10. Ended Responsibility Grant excluded; Membership still returned.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000110', true);
set local role authenticated;
do $$
declare
    org jsonb := pg_temp.org_entry(public.get_my_professional_context(), '18000000-0000-4000-8000-000000000301');
begin
    perform pg_temp.assert_true(
        org is not null
        and org -> 'responsibilities' = '[]'::jsonb
        and org -> 'capabilities' = '[]'::jsonb,
        'D10: ended Responsibility Grant contributes no responsibility or capability'
    );
end;
$$;
reset role;

-- D11. OrgB OWNER who is also an assigned VETERINARIAN: Clinic-scoped
--      entries only where not already Organization-scoped; no Subscription.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000111', true);
set local role authenticated;
do $$
declare
    result jsonb := public.get_my_professional_context();
    org jsonb := pg_temp.org_entry(result, '18000000-0000-4000-8000-000000000302');
    b1 uuid := '18000000-0000-4000-8000-000000000404';
begin
    perform pg_temp.assert_true(
        jsonb_array_length(result -> 'organizations') = 1
        and pg_temp.org_entry(result, '18000000-0000-4000-8000-000000000301') is null,
        'D11: another Organization does not leak'
    );
    perform pg_temp.assert_true(
        jsonb_array_length(org -> 'capabilities') = 22
        and pg_temp.caps(org, 'CLINIC', b1) = array['CLINICAL_CARE', 'CLINICAL_DOCUMENTATION']
        and 'APPOINTMENT_VIEW_SCHEDULE' = any (pg_temp.caps(org, 'ORGANIZATION', null)),
        'D11: Organization-scoped capabilities are not repeated per Clinic; clinical capabilities scoped to B1'
    );
    perform pg_temp.assert_true(
        org -> 'entitlements' = '{"APPOINTMENT_MANAGEMENT": false, "PROFESSIONAL_SCHEDULING": false, "CLINICAL_CARE": false, "CLINICAL_DOCUMENTATION": false}'::jsonb,
        'D11: no current Subscription → no Entitlement available'
    );
end;
$$;
reset role;

-- D12. Entitlement availability per SPEC-SUB-003 for six Organizations; the
--      OWNER capabilities stay present regardless (capability ≠ Entitlement).
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000112', true);
set local role authenticated;
do $$
declare
    result jsonb := public.get_my_professional_context();
    expected record;
begin
    perform pg_temp.assert_true(
        jsonb_array_length(result -> 'organizations') = 6
        and (select array_agg(organization_entry ->> 'organization_display_name')
             from jsonb_array_elements(result -> 'organizations') as organization_entry)
            = array['Org 1 Pending', 'Org 2 Expired', 'Org 3 Past Due', 'Org 4 Cancelled Valid', 'Org 5 Cancelled Lapsed', 'Org 6 Active Lapsed'],
        'D12: all six current Memberships returned in deterministic display-name order'
    );
    for expected in
        select * from (values
            ('18000000-0000-4000-8000-000000000303'::uuid, false, 'PENDING'),
            ('18000000-0000-4000-8000-000000000304'::uuid, false, 'EXPIRED'),
            ('18000000-0000-4000-8000-000000000305'::uuid, false, 'PAST_DUE'),
            ('18000000-0000-4000-8000-000000000306'::uuid, true,  'CANCELLED within validity'),
            ('18000000-0000-4000-8000-000000000307'::uuid, false, 'CANCELLED after validity'),
            ('18000000-0000-4000-8000-000000000308'::uuid, false, 'ACTIVE after validity')
        ) as expectation (organization_id, entitled, label)
    loop
        perform pg_temp.assert_true(
            pg_temp.org_entry(result, expected.organization_id) -> 'entitlements'
                = jsonb_build_object(
                    'APPOINTMENT_MANAGEMENT', expected.entitled,
                    'PROFESSIONAL_SCHEDULING', expected.entitled,
                    'CLINICAL_CARE', expected.entitled,
                    'CLINICAL_DOCUMENTATION', expected.entitled),
            format('D12: Entitlement availability incorrect for %s', expected.label)
        );
        perform pg_temp.assert_true(
            jsonb_array_length(pg_temp.org_entry(result, expected.organization_id) -> 'capabilities') = 20
            and 'APPOINTMENT_MANAGE_AVAILABILITY' = any (pg_temp.caps(pg_temp.org_entry(result, expected.organization_id), 'ORGANIZATION', null)),
            format('D12: OWNER capabilities must be returned independently of Entitlement (%s)', expected.label)
        );
    end loop;
end;
$$;

-- D13. A reported capability does not make a paid operation succeed: the
--      PENDING Organization's OWNER holds APPOINTMENT_MANAGE_AVAILABILITY but
--      the operation is denied for lack of PROFESSIONAL_SCHEDULING.
select pg_temp.assert_error(
    'select public.set_clinic_standard_appointment_duration(''18000000-0000-4000-8000-000000000405'', 30)',
    '42501',
    'Professional scheduling Entitlement is required'
);
reset role;

-- D14. Reading persists nothing (no flag/snapshot): the read is STABLE and
--      a repeated read is identical.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000102', true);
set local role authenticated;
do $$
begin
    perform pg_temp.assert_true(
        public.get_my_professional_context() = public.get_my_professional_context(),
        'D14: repeated reads are identical'
    );
end;
$$;
reset role;

rollback;

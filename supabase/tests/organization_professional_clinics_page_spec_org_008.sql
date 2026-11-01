-- Regression suite for SPEC-ORG-008 §11–§12 — Organization Professional
-- Clinics page (Punto 10), migration
-- 20261119090000_organization_professional_clinics_page.sql.
--
-- Run only against an isolated LOCAL database with every source-controlled
-- migration applied. All fixtures and assertions are rolled back (prefix
-- d0150000-). Superuser execution is required solely to load a deliberately
-- minimal deterministic context with establishment triggers bypassed and to
-- impersonate Users (same rationale as professional_clinics_spec_org_008.sql).
--
-- Covers BR-19..BR-25 and Verification Notes 24–37:
--   A  contract, ACL, helper ACL, delegation, ORG-008 read unchanged (24, 36, 37)
--   B  authentication before validation (24)
--   C  input validation, identical for every Organization (25)
--   D  parity with get_my_professional_clinics() restricted to the
--      Organization, for every fixture User × Organization × page size (26–28)
--   E  completeness of the candidate bound per inclusion basis (27)
--   F  isolation and cursors that name non-included Clinics (29, 34)
--   G  order, ties, unnamed Clinics, cursor boundaries (30)
--   H  search before the limit, and search parity for every page size (31)
--   I  normalization and matching with literal expectations (32, 33)
--   J  changes between pages (35)
--   K  no writes, no row locks (37)
--   V  volume: 3 000 Clinics, first / deep / search pages
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

-- 'OK', or the SQLSTATE and message a statement fails with.
create function pg_temp.sqlstate_of(p_statement text)
returns text language plpgsql as $$
begin
    execute p_statement;
    return 'OK';
exception when others then
    return sqlstate || ': ' || sqlerrm;
end;
$$;

-- Fixture identifiers: d0150000-0000-4000-8000-<12 hex digits>.
create function pg_temp.fx(p_suffix text)
returns uuid language sql immutable as $$
    select ('d0150000-0000-4000-8000-' || lpad(p_suffix, 12, '0'))::uuid
$$;

-- Search Organization Clinic n (1–37).
create function pg_temp.s(p_number integer)
returns uuid language sql immutable as $$
    select pg_temp.fx('45' || lpad(p_number::text, 2, '0'))
$$;

create function pg_temp.act_as(p_user_number integer)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.fx('1' || lpad(p_user_number::text, 2, '0'))::text, true)
$$;

-- Every page of the read for one Organization, search and page size, as the
-- current role, from an optional starting cursor, concatenated as
-- [{clinic_id, clinic_display_name}, ...]. Fails if a page exceeds its size,
-- repeats a Clinic within itself, or the list does not end.
create function pg_temp.read_pages(
    p_organization_id uuid, p_search text, p_page_size integer,
    p_after_name text default null, p_after_id uuid default null
)
returns jsonb language plpgsql as $$
declare
    all_rows jsonb := '[]'::jsonb;
    page_rows jsonb;
    page_count integer;
    page_distinct integer;
    after_name text := p_after_name;
    after_id uuid := p_after_id;
    pages integer := 0;
begin
    loop
        pages := pages + 1;
        perform pg_temp.assert_true(pages <= 200, 'Pages: the list ends');
        begin
            select coalesce(jsonb_agg(jsonb_build_object(
                       'clinic_id', page.clinic_id::text,
                       'clinic_display_name', page.clinic_display_name) order by page.ordinality), '[]'::jsonb),
                   count(*), count(distinct page.clinic_id)
            into page_rows, page_count, page_distinct
            from public.get_my_organization_professional_clinics(
                p_organization_id, p_search, after_name, after_id, p_page_size
            ) with ordinality as page;
        exception when others then
            raise notice 'read_pages failed: % %', sqlstate, sqlerrm;
            page_count := -1;
        end;
        perform pg_temp.assert_true(page_count >= 0, 'Pages: the read never fails for valid input');
        perform pg_temp.assert_true(page_count <= p_page_size and page_distinct = page_count,
                                    'Pages: no page exceeds its limit or repeats a Clinic');
        all_rows := all_rows || page_rows;
        exit when page_count < p_page_size;
        after_id := (page_rows -> -1 ->> 'clinic_id')::uuid;
        after_name := page_rows -> -1 ->> 'clinic_display_name';
    end loop;
    return all_rows;
end;
$$;

-- One page as an ordered uuid array.
create function pg_temp.page_ids(
    p_organization_id uuid, p_search text, p_after_name text, p_after_id uuid, p_limit integer
)
returns uuid[] language sql as $$
    select coalesce(array_agg(page.clinic_id order by page.ordinality), '{}')
    from public.get_my_organization_professional_clinics(
        p_organization_id, p_search, p_after_name, p_after_id, p_limit
    ) with ordinality as page
$$;

-- ORG-008 oracle: the §4 result restricted to one Organization and, when the
-- search normalizes to something, narrowed by BR-22. Run as the superuser
-- (the helper is executable by no client).
create function pg_temp.oracle(p_clinics jsonb, p_organization_id uuid, p_search text)
returns jsonb language sql as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'clinic_id', entry ->> 'clinic_id',
               'clinic_display_name', entry -> 'clinic_display_name') order by ordinality), '[]'::jsonb)
    from jsonb_array_elements(p_clinics -> 'clinics') with ordinality as listed (entry, ordinality)
    where (entry ->> 'organization_id')::uuid = p_organization_id
      and (nullif(public.professional_clinic_search_key(p_search), '') is null
           or (jsonb_typeof(entry -> 'clinic_display_name') = 'string'
               and strpos(public.professional_clinic_search_key(entry ->> 'clinic_display_name'),
                          public.professional_clinic_search_key(p_search)) > 0))
$$;

create function pg_temp.sorted(p_ids uuid[])
returns uuid[] language sql immutable as $$
    select coalesce(array_agg(id order by id), '{}') from unnest(p_ids) as id
$$;

create function pg_temp.json_ids(p_rows jsonb)
returns uuid[] language sql immutable as $$
    select coalesce(array_agg((row_entry ->> 'clinic_id')::uuid order by ordinality), '{}')
    from jsonb_array_elements(p_rows) with ordinality as listed (row_entry, ordinality)
$$;

create temporary table violation (section text not null, detail text not null) on commit drop;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures.
--
-- Auth subjects …-0000000001NN, domain Users …-0000000002NN (U18 has no
-- domain User):
--   01 Guardian only                       12 OWNER on an ENDED OrgB Membership
--   02 Profile only, no Membership         13 OrgA ADMINISTRATOR grant ended
--   03 bare OrgA Membership                14 VETERINARIAN, Assignment @ A1 ended
--   04 OrgA OWNER                          15 pending Invitation only
--   05 OrgA ADMINISTRATOR (Org)            16 OrgA RECEPTIONIST + ADMINISTRATOR @ A2
--   06 ADMINISTRATOR @ A2 (Clinic)            + VETERINARIAN assigned @ A1
--   07 OrgA RECEPTIONIST (Org)             17 RECEPTIONIST @ A5, OrgB OWNER, OrgC
--   08 RECEPTIONIST @ A3 (Clinic)             ADMINISTRATOR, OWNER of Clinic-less OrgE
--   09 VETERINARIAN assigned @ A1          19 OrgS OWNER
--   10 VETERINARIAN, no Assignment         20 RECEPTIONIST @ S13, S20, S34 (Clinic)
--   11 Assignment @ A1, VETERINARIAN ended 21 VETERINARIAN assigned @ S21
--                                          22 OrgS OWNER whose Membership starts later
--
-- Organizations …03NN: A "Animalia Veterinary Group", B "VetCare Group",
-- C "Animalia Veterinary Group" (same name, larger id), E "Empty Org"
-- (no Clinic), S "Search Org". …03FF is unknown.
--
-- OrgA Clinics …04NN: A1 "Animalia Madrid Centro", A2 "Animalia Getafe",
-- A3 no profile, A4 profile without display name, A5 "Animalia Getafe".
-- OrgB: B1 "VetCare Toledo", B2 "Clínica Centro". OrgC: C1 "Zeta Clinic".
-- OrgS Clinics S01–S36 (…45NN), names below.
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select pg_temp.fx('1' || lpad(n::text, 2, '0')), '2020-01-01Z'
from generate_series(1, 22) as n;

insert into public.users (id)
select pg_temp.fx('2' || lpad(n::text, 2, '0'))
from generate_series(1, 22) as n where n <> 18;

insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.fx('2' || lpad(n::text, 2, '0')), pg_temp.fx('1' || lpad(n::text, 2, '0'))
from generate_series(1, 22) as n where n <> 18;

insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.fx('301'), 'Animalia Veterinary Group'),
    (pg_temp.fx('302'), 'VetCare Group'),
    (pg_temp.fx('303'), 'Animalia Veterinary Group'),
    (pg_temp.fx('305'), 'Empty Org'),
    (pg_temp.fx('306'), 'Search Org');

insert into public.clinics (id, organization_id, is_published) values
    (pg_temp.fx('401'), pg_temp.fx('301'), true),
    (pg_temp.fx('402'), pg_temp.fx('301'), false),
    (pg_temp.fx('403'), pg_temp.fx('301'), false),
    (pg_temp.fx('404'), pg_temp.fx('301'), false),
    (pg_temp.fx('405'), pg_temp.fx('301'), true),
    (pg_temp.fx('411'), pg_temp.fx('302'), true),
    (pg_temp.fx('412'), pg_temp.fx('302'), true),
    (pg_temp.fx('421'), pg_temp.fx('303'), true);

insert into public.clinics (id, organization_id, is_published)
select pg_temp.s(n), pg_temp.fx('306'), n % 2 = 0
from generate_series(1, 36) as n;

insert into public.clinic_public_profiles (clinic_id, display_name, description) values
    (pg_temp.fx('401'), 'Animalia Madrid Centro', 'Private description must not leak'),
    (pg_temp.fx('402'), 'Animalia Getafe', null),
    (pg_temp.fx('404'), null, 'Description of an unnamed Clinic'),
    (pg_temp.fx('405'), 'Animalia Getafe', null),
    (pg_temp.fx('411'), 'VetCare Toledo', null),
    (pg_temp.fx('412'), 'Clínica Centro', null),
    (pg_temp.fx('421'), 'Zeta Clinic', null);

-- S01–S12 sort before every match of "clinica" and outnumber small limits.
insert into public.clinic_public_profiles (clinic_id, display_name)
select pg_temp.s(n), 'Aaa Filler ' || lpad(n::text, 2, '0')
from generate_series(1, 12) as n;

insert into public.clinic_public_profiles (clinic_id, display_name, description) values
    (pg_temp.s(13), 'Clínica Centro', null),
    (pg_temp.s(14), 'Clínica Centro', null),
    (pg_temp.s(15), 'Clínica Centro', null),
    (pg_temp.s(16), 'Clinica Centro', null),
    (pg_temp.s(17), 'Cli' || U&'\0301' || 'nica Centro', null),
    (pg_temp.s(18), 'Clínica  Centro', null),
    (pg_temp.s(19), 'Clínica' || U&'\00A0' || 'Centro', null),
    (pg_temp.s(20), 'Peña Vet', null),
    (pg_temp.s(21), 'PEÑA', null),
    (pg_temp.s(22), 'Pena', null),
    (pg_temp.s(23), 'Tasa 50% Centro', null),
    (pg_temp.s(24), 'Ab_C', null),
    (pg_temp.s(25), 'X [x] a\b', null),
    (pg_temp.s(26), 'Straße', null),
    (pg_temp.s(27), 'ØSTER Vet', null),
    (pg_temp.s(28), 'finca', null),
    (pg_temp.s(29), U&'\FF23\FF4C\FF49\FF4E\FF49\FF43\FF41', null),
    (pg_temp.s(30), 'Clínica Veterinaria Peña', null),
    (pg_temp.s(31), 'ŒUVRE Clinic', null),
    (pg_temp.s(32), U&'\0130' || 'stanbul Vet', null),
    (pg_temp.s(33), 'Zero' || U&'\200B' || 'Width', null),
    -- S34 and S36 have no profile; S35 has a profile without a display name.
    (pg_temp.s(35), null, 'Unnamed Clinic description');

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id) values
    (pg_temp.fx('503'), pg_temp.fx('301'), pg_temp.fx('203'), '2020-01-01Z', null, null),
    (pg_temp.fx('504'), pg_temp.fx('301'), pg_temp.fx('204'), '2020-01-01Z', null, null),
    (pg_temp.fx('505'), pg_temp.fx('301'), pg_temp.fx('205'), '2020-01-01Z', null, null),
    (pg_temp.fx('506'), pg_temp.fx('301'), pg_temp.fx('206'), '2020-01-01Z', null, null),
    (pg_temp.fx('507'), pg_temp.fx('301'), pg_temp.fx('207'), '2020-01-01Z', null, null),
    (pg_temp.fx('508'), pg_temp.fx('301'), pg_temp.fx('208'), '2020-01-01Z', null, null),
    (pg_temp.fx('509'), pg_temp.fx('301'), pg_temp.fx('209'), '2020-01-01Z', null, null),
    (pg_temp.fx('510'), pg_temp.fx('301'), pg_temp.fx('210'), '2020-01-01Z', null, null),
    (pg_temp.fx('511'), pg_temp.fx('301'), pg_temp.fx('211'), '2020-01-01Z', null, null),
    (pg_temp.fx('512'), pg_temp.fx('302'), pg_temp.fx('212'), '2020-01-01Z', '2021-01-01Z', pg_temp.fx('212')),
    (pg_temp.fx('513'), pg_temp.fx('301'), pg_temp.fx('213'), '2020-01-01Z', null, null),
    (pg_temp.fx('514'), pg_temp.fx('301'), pg_temp.fx('214'), '2020-01-01Z', null, null),
    (pg_temp.fx('516'), pg_temp.fx('301'), pg_temp.fx('216'), '2020-01-01Z', null, null),
    (pg_temp.fx('517'), pg_temp.fx('301'), pg_temp.fx('217'), '2020-01-01Z', null, null),
    (pg_temp.fx('571'), pg_temp.fx('302'), pg_temp.fx('217'), '2020-01-01Z', null, null),
    (pg_temp.fx('572'), pg_temp.fx('303'), pg_temp.fx('217'), '2020-01-01Z', null, null),
    (pg_temp.fx('573'), pg_temp.fx('305'), pg_temp.fx('217'), '2020-01-01Z', null, null),
    (pg_temp.fx('519'), pg_temp.fx('306'), pg_temp.fx('219'), '2020-01-01Z', null, null),
    (pg_temp.fx('520'), pg_temp.fx('306'), pg_temp.fx('220'), '2020-01-01Z', null, null),
    (pg_temp.fx('521'), pg_temp.fx('306'), pg_temp.fx('221'), '2020-01-01Z', null, null),
    (pg_temp.fx('522'), pg_temp.fx('306'), pg_temp.fx('222'), statement_timestamp() + interval '30 days', null, null);

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    (pg_temp.fx('604'), pg_temp.fx('504'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('605'), pg_temp.fx('505'), 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('606'), pg_temp.fx('506'), 'ADMINISTRATOR', 'CLINIC', pg_temp.fx('402'), '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('607'), pg_temp.fx('507'), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('608'), pg_temp.fx('508'), 'RECEPTIONIST', 'CLINIC', pg_temp.fx('403'), '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('609'), pg_temp.fx('509'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('610'), pg_temp.fx('510'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('611'), pg_temp.fx('511'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', pg_temp.fx('204'), pg_temp.fx('204')),
    (pg_temp.fx('612'), pg_temp.fx('512'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('212'), null),
    (pg_temp.fx('613'), pg_temp.fx('513'), 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', '2021-01-01Z', pg_temp.fx('204'), pg_temp.fx('204')),
    (pg_temp.fx('614'), pg_temp.fx('514'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('661'), pg_temp.fx('516'), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('662'), pg_temp.fx('516'), 'ADMINISTRATOR', 'CLINIC', pg_temp.fx('402'), '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('663'), pg_temp.fx('516'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('671'), pg_temp.fx('517'), 'RECEPTIONIST', 'CLINIC', pg_temp.fx('405'), '2020-01-01Z', null, pg_temp.fx('204'), null),
    (pg_temp.fx('672'), pg_temp.fx('571'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('217'), null),
    (pg_temp.fx('673'), pg_temp.fx('572'), 'ADMINISTRATOR', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('217'), null),
    (pg_temp.fx('674'), pg_temp.fx('573'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('217'), null),
    (pg_temp.fx('619'), pg_temp.fx('519'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('219'), null),
    (pg_temp.fx('6a0'), pg_temp.fx('520'), 'RECEPTIONIST', 'CLINIC', pg_temp.s(13), '2020-01-01Z', null, pg_temp.fx('219'), null),
    (pg_temp.fx('6a1'), pg_temp.fx('520'), 'RECEPTIONIST', 'CLINIC', pg_temp.s(20), '2020-01-01Z', null, pg_temp.fx('219'), null),
    (pg_temp.fx('6a2'), pg_temp.fx('520'), 'RECEPTIONIST', 'CLINIC', pg_temp.s(34), '2020-01-01Z', null, pg_temp.fx('219'), null),
    (pg_temp.fx('621'), pg_temp.fx('521'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('219'), null),
    (pg_temp.fx('622'), pg_temp.fx('522'), 'OWNER', 'ORGANIZATION', null, statement_timestamp() + interval '30 days', null, pg_temp.fx('222'), null);

insert into public.veterinarian_professional_profiles (id, user_id) values
    (pg_temp.fx('702'), pg_temp.fx('202')),
    (pg_temp.fx('709'), pg_temp.fx('209')),
    (pg_temp.fx('710'), pg_temp.fx('210')),
    (pg_temp.fx('711'), pg_temp.fx('211')),
    (pg_temp.fx('712'), pg_temp.fx('212')),
    (pg_temp.fx('714'), pg_temp.fx('214')),
    (pg_temp.fx('716'), pg_temp.fx('216')),
    (pg_temp.fx('721'), pg_temp.fx('221'));

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.fx('809'), pg_temp.fx('709'), pg_temp.fx('509'), pg_temp.fx('401'), '2020-01-01Z', null),
    (pg_temp.fx('811'), pg_temp.fx('711'), pg_temp.fx('511'), pg_temp.fx('401'), '2020-01-01Z', null),
    (pg_temp.fx('812'), pg_temp.fx('712'), pg_temp.fx('512'), pg_temp.fx('411'), '2020-01-01Z', null),
    (pg_temp.fx('814'), pg_temp.fx('714'), pg_temp.fx('514'), pg_temp.fx('401'), '2020-01-01Z', '2021-01-01Z'),
    (pg_temp.fx('816'), pg_temp.fx('716'), pg_temp.fx('516'), pg_temp.fx('401'), '2020-01-01Z', null),
    (pg_temp.fx('821'), pg_temp.fx('721'), pg_temp.fx('521'), pg_temp.s(21), '2020-01-01Z', null);

insert into public.organization_invitations (
    id, organization_id, inviting_user_id, recipient_user_id, recipient_email, created_at, expires_at
) values (
    pg_temp.fx('c15'), pg_temp.fx('301'), pg_temp.fx('204'), pg_temp.fx('215'),
    'u15@example.test', '2020-01-01Z', statement_timestamp() + interval '30 days'
);
insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type, clinic_id)
values (pg_temp.fx('c16'), pg_temp.fx('c15'), 'RECEPTIONIST', 'CLINIC', pg_temp.fx('401'));

insert into public.pets (id, name, species, created_at)
values (pg_temp.fx('b01'), 'Luna', 'canine', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (pg_temp.fx('b02'), pg_temp.fx('201'), pg_temp.fx('b01'), '2020-01-01Z');

set local session_replication_role = origin;

-- ===========================================================================
-- A. Contract and ACL (VN 24, 36, 37).
-- ===========================================================================

select pg_temp.assert_true(
    (select count(*) from pg_proc
     where proname = 'get_my_organization_professional_clinics' and pronamespace = 'public'::regnamespace) = 1
    and (select prosecdef and provolatile = 's' and proconfig = array['search_path=""']
                and pg_get_function_identity_arguments(oid)
                    = 'p_organization_id uuid, p_search text, p_after_display_name text, p_after_clinic_id uuid, p_limit integer'
                and pg_get_function_result(oid) = 'TABLE(clinic_id uuid, clinic_display_name text)'
                and pronargdefaults = 4
         from pg_proc where oid = 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)'::regprocedure),
    'Contract: one STABLE SECURITY DEFINER overload with the BR-19 arguments and two columns'
);

select pg_temp.assert_true(
    has_function_privilege('authenticated', 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)', 'EXECUTE')
    and not exists (select 1 from aclexplode((select proacl from pg_proc
                    where oid = 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)'::regprocedure)) as acl
                    where acl.grantee = 0)
    and not has_function_privilege('anon', 'public.professional_clinic_search_key(text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.professional_clinic_search_key(text)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.professional_clinic_search_key(text)', 'EXECUTE')
    and not exists (select 1 from aclexplode((select proacl from pg_proc
                    where oid = 'public.professional_clinic_search_key(text)'::regprocedure)) as acl
                    where acl.grantee = 0),
    'Grants: authenticated only; the search helper is executable by no client'
);

select pg_temp.assert_true(
    (select prosrc like '%public.user_has_clinic_capability(%'
            and prosrc like '%public.user_has_organization_scoped_clinic_capability(%'
            and prosrc like '%professional_capability_catalog%'
            and prosrc not like '%''OWNER''%'
            and prosrc not like '%''ADMINISTRATOR''%'
            and prosrc not like '%''RECEPTIONIST''%'
            and prosrc not like '%''VETERINARIAN''%'
            and prosrc not like '%''APPOINTMENT\_%'
            and prosrc not like '%''CLINICAL\_%'
            and prosrc not like '%''CLINIC\_MANAGE%'
            and prosrc not like '%responsibility in%'
            and prosrc not like '%is_published%'
            and prosrc not like '%entitlement%'
            and prosrc not like '%subscription%'
            and lower(prosrc) not like '%for update%'
            and lower(prosrc) not like '%for share%'
            and lower(prosrc) not like '%for no key update%'
            and lower(prosrc) not like '%for key share%'
            and lower(prosrc) not like '%insert into%'
            and lower(prosrc) not like '%update public.%'
            and lower(prosrc) not like '%delete from%'
     from pg_proc where oid = 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)'::regprocedure),
    'Delegation: inclusion only through user_has_clinic_capability, no mapping, no lock, no write'
);

-- The candidate bound relies on user_has_clinic_capability being exactly the
-- disjunction of its Organization-scoped and Clinic-scoped predicates, as
-- defined today. A change to any of them must re-review BR-21's bound.
select pg_temp.assert_true(
    md5(pg_get_functiondef('public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)) = 'd103cf2610269b393b39c1eece8d23df'
    and md5(pg_get_functiondef('public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)) = '51fa265e96c1ab4c9f3f2184514fedd9'
    and md5(pg_get_functiondef('public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)) = 'a40be5366d9df872e79b12dfe2daf1dc',
    'Authoritative predicates unchanged since the candidate bound was reviewed'
);

-- get_my_professional_clinics() is unchanged (definition and grants).
select pg_temp.assert_true(
    md5(pg_get_functiondef('public.get_my_professional_clinics()'::regprocedure)) = '59b52cc2edf15927003c535c6dbad585'
    and (select proacl::text from pg_proc where oid = 'public.get_my_professional_clinics()'::regprocedure)
        = '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    'ORG-008 complete read unchanged'
);

-- ===========================================================================
-- B. Authentication before validation (VN 24).
-- ===========================================================================

set local role anon;
select pg_temp.assert_true(
    pg_temp.sqlstate_of('select * from public.get_my_organization_professional_clinics(null)') like '42501:%',
    'Authentication: anon cannot execute the read'
);
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.sqlstate_of('select * from public.get_my_organization_professional_clinics(null)')
        = '28000: Authentication is required'
    -- 28000 wins over an invalid input.
    and pg_temp.sqlstate_of('select * from public.get_my_organization_professional_clinics(null, repeat(''x'', 101), ''n'', null, 0)')
        = '28000: Authentication is required',
    'Authentication: 28000 before validation'
);
reset role;

select pg_temp.act_as(18);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.sqlstate_of('select * from public.get_my_organization_professional_clinics(null, null, null, null, 0)')
        = '28000: No coherent domain User exists for the authenticated subject',
    'Authentication: no coherent domain User'
);
reset role;

-- ===========================================================================
-- C. Input validation, identical for every Organization (VN 25).
-- ===========================================================================

select pg_temp.act_as(19);
set local role authenticated;
do $$
declare
    organization uuid;
    statement_template text;
begin
    foreach organization in array array[
        pg_temp.fx('306'), pg_temp.fx('301'), pg_temp.fx('3ff'), null
    ] loop
        foreach statement_template in array array[
            'select * from public.get_my_organization_professional_clinics(%L, null, null, null, null)',
            'select * from public.get_my_organization_professional_clinics(%L, null, null, null, 0)',
            'select * from public.get_my_organization_professional_clinics(%L, null, null, null, 51)',
            'select * from public.get_my_organization_professional_clinics(%L, null, ''Clínica Centro'', null, 20)',
            'select * from public.get_my_organization_professional_clinics(%L, repeat(''á'', 101), null, null, 20)'
        ] loop
            perform pg_temp.assert_true(
                pg_temp.sqlstate_of(format(statement_template, organization)) = '22023: Professional Clinics page is invalid',
                'Validation: 22023 for every invalid input and every Organization');
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    pg_temp.sqlstate_of(format(
        'select * from public.get_my_organization_professional_clinics(%L, repeat(''á'', 100), null, null, 50)',
        pg_temp.fx('306'))) = 'OK'
    and pg_temp.sqlstate_of(format(
        'select * from public.get_my_organization_professional_clinics(%L, null, null, null, 50)',
        pg_temp.fx('306'))) = 'OK'
    and (select count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('306'), repeat('á', 100), null, null, 50)) = 0
    and (select count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('306'), null, null, null, 1)) = 1
    and (select count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('306'), null, null, null, 50)) = 36
    and (select count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('306'))) = 20,
    'Validation accepts a 100-character search, limits 1 and 50, and defaults to 20'
);
reset role;

-- ===========================================================================
-- D. Parity without a search (VN 26, 28): for every fixture User, every
--    Organization (and unknown, null), every page size 1..n+1, the pages
--    concatenate to the ORG-008 result restricted to that Organization.
-- ===========================================================================

create temporary table fixture_clinics (user_number integer primary key, clinics jsonb not null) on commit drop;

do $$
declare
    user_number integer;
    clinics_value jsonb;
begin
    foreach user_number in array array[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,19,20,21,22] loop
        perform pg_temp.act_as(user_number);
        set local role authenticated;
        clinics_value := public.get_my_professional_clinics();
        reset role;
        insert into fixture_clinics values (user_number, clinics_value);
    end loop;
end;
$$;

do $$
declare
    fixture record;
    organization uuid;
    expected jsonb;
    actual jsonb;
    page_size integer;
begin
    for fixture in select * from fixture_clinics order by user_number loop
        foreach organization in array array[
            pg_temp.fx('301'), pg_temp.fx('302'), pg_temp.fx('303'), pg_temp.fx('305'),
            pg_temp.fx('306'), pg_temp.fx('3ff'), null
        ] loop
            expected := pg_temp.oracle(fixture.clinics, organization, null);
            for page_size in 1..least(jsonb_array_length(expected) + 1, 50) loop
                perform pg_temp.act_as(fixture.user_number);
                set local role authenticated;
                actual := pg_temp.read_pages(organization, null, page_size);
                reset role;
                if actual is distinct from expected then
                    insert into violation values ('D', format('U%s org %s size %s: expected %s got %s',
                        fixture.user_number, organization, page_size, expected, actual));
                end if;
            end loop;
        end loop;
    end loop;
end;
$$;

select pg_temp.assert_true(
    not exists (select 1 from violation where section = 'D'),
    'Parity: pages equal the ORG-008 result of the Organization for every User and page size'
);

-- The parity matrix is not vacuous.
select pg_temp.assert_true(
    jsonb_array_length(pg_temp.oracle((select clinics from fixture_clinics where user_number = 19), pg_temp.fx('306'), null)) = 36
    and jsonb_array_length(pg_temp.oracle((select clinics from fixture_clinics where user_number = 4), pg_temp.fx('301'), null)) = 5
    and jsonb_array_length(pg_temp.oracle((select clinics from fixture_clinics where user_number = 20), pg_temp.fx('306'), null)) = 3
    and jsonb_array_length(pg_temp.oracle((select clinics from fixture_clinics where user_number = 17), pg_temp.fx('302'), null)) = 2,
    'Parity fixtures: the Owner sees 36 Search Org Clinics, the Clinic Receptionist 3'
);

-- VN 28: every non-including case is the same empty page, without error.
do $$
declare
    probe record;
begin
    for probe in
        select * from (values
            (19, pg_temp.fx('3ff')), (19, null::uuid), (19, pg_temp.fx('301')), (19, pg_temp.fx('305')),
            (17, pg_temp.fx('305')), (12, pg_temp.fx('302')), (15, pg_temp.fx('301')), (3, pg_temp.fx('301')),
            (11, pg_temp.fx('301')), (13, pg_temp.fx('301')), (14, pg_temp.fx('301')), (10, pg_temp.fx('301')),
            (22, pg_temp.fx('306')), (1, pg_temp.fx('301')), (2, pg_temp.fx('301')), (4, pg_temp.fx('302'))
        ) as cases (user_number, organization_id)
    loop
        perform pg_temp.act_as(probe.user_number);
        set local role authenticated;
        if (select count(*) from public.get_my_organization_professional_clinics(probe.organization_id, null, null, null, 50)) <> 0
           or (select count(*) from public.get_my_organization_professional_clinics(probe.organization_id, 'a', null, null, 50)) <> 0 then
            reset role;
            insert into violation values ('D28', format('U%s org %s', probe.user_number, probe.organization_id));
        else
            reset role;
        end if;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (select 1 from violation where section = 'D28'),
    'Empty page for unknown, null, unrelated, ended, pending, not-yet-started and Clinic-less cases'
);

-- ===========================================================================
-- E. Completeness per inclusion basis and authoritative parity (VN 27).
-- ===========================================================================

do $$
declare
    fixture record;
    organization uuid;
    granted uuid[];
    returned uuid[];
begin
    for fixture in select user_number from fixture_clinics order by user_number loop
        foreach organization in array array[
            pg_temp.fx('301'), pg_temp.fx('302'), pg_temp.fx('303'), pg_temp.fx('305'), pg_temp.fx('306')
        ] loop
            select pg_temp.sorted(coalesce(array_agg(clinic.id), '{}')) into granted
            from public.clinics as clinic
            where clinic.organization_id = organization
              and exists (
                  select 1 from public.professional_capability_catalog() as catalog_entry
                  where catalog_entry.capability_context = 'CLINIC'
                    and public.user_has_clinic_capability(
                        pg_temp.fx('2' || lpad(fixture.user_number::text, 2, '0')), clinic.id, catalog_entry.capability));
            perform pg_temp.act_as(fixture.user_number);
            set local role authenticated;
            returned := pg_temp.sorted(pg_temp.json_ids(pg_temp.read_pages(organization, null, 50)));
            reset role;
            if granted is distinct from returned then
                insert into violation values ('E', format('U%s org %s granted %s returned %s',
                    fixture.user_number, organization, granted, returned));
            end if;
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (select 1 from violation where section = 'E'),
    'Completeness: a Clinic is returned if and only if user_has_clinic_capability grants a Clinic-context capability'
);

-- Each basis alone includes its Clinic.
select pg_temp.act_as(6);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('301'), null, null, null, 50) = array[pg_temp.fx('402')],
    'Basis: a Clinic-scoped Administrator sees only the covered Clinic'
);
reset role;
select pg_temp.act_as(9);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('301'), null, null, null, 50) = array[pg_temp.fx('401')],
    'Basis: a Veterinarian sees only the currently assigned Clinic'
);
reset role;
select pg_temp.act_as(21);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('306'), null, null, null, 50) = array[pg_temp.s(21)],
    'Basis: a Veterinarian of the Search Org sees only S21'
);
reset role;
select pg_temp.act_as(7);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.sorted(pg_temp.page_ids(pg_temp.fx('301'), null, null, null, 50))
        = pg_temp.sorted(array[pg_temp.fx('401'), pg_temp.fx('402'), pg_temp.fx('403'), pg_temp.fx('404'), pg_temp.fx('405')]),
    'Basis: an Organization-scoped Receptionist sees every Clinic of the Organization'
);
reset role;

-- ===========================================================================
-- F. Isolation and cursors that name non-included Clinics (VN 29, 34).
-- ===========================================================================

select pg_temp.act_as(19);
set local role authenticated;
select pg_temp.assert_true(
    not (pg_temp.fx('412') = any (pg_temp.page_ids(pg_temp.fx('306'), 'clinica', null, null, 50)))
    and pg_temp.page_ids(pg_temp.fx('302'), 'clinica', null, null, 50) = '{}'
    and pg_temp.page_ids(pg_temp.fx('302'), null, 'Animalia', pg_temp.fx('411'), 50) = '{}',
    'Isolation: another Organization''s Clinic is never returned'
);
reset role;

select pg_temp.act_as(17);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('301'), null, null, null, 50) = array[pg_temp.fx('405')]
    and pg_temp.page_ids(pg_temp.fx('302'), null, null, null, 50) = array[pg_temp.fx('412'), pg_temp.fx('411')]
    and pg_temp.page_ids(pg_temp.fx('303'), null, null, null, 50) = array[pg_temp.fx('421')]
    and pg_temp.page_ids(pg_temp.fx('306'), null, null, null, 50) = '{}',
    'Isolation: each Organization returns only that Organization''s Professional Clinics'
);
reset role;

select pg_temp.act_as(20);
set local role authenticated;
select pg_temp.assert_true(
    -- A cursor naming a non-included Clinic (S14) only positions.
    pg_temp.page_ids(pg_temp.fx('306'), null, 'Clínica Centro', pg_temp.s(14), 50) = array[pg_temp.s(20), pg_temp.s(34)]
    -- A cursor from another search returns only rows matching this search.
    and pg_temp.page_ids(pg_temp.fx('306'), 'pena', 'Aaa Filler 01', pg_temp.s(1), 50) = array[pg_temp.s(20)]
    and pg_temp.page_ids(pg_temp.fx('306'), 'clinica', 'Peña Vet', pg_temp.s(20), 50) = '{}'
    and pg_temp.page_ids(pg_temp.fx('306'), null, null, pg_temp.s(1), 50) = array[pg_temp.s(34)],
    'Cursor: any cursor returns only included rows matching the search of the call'
);
reset role;

select pg_temp.act_as(6);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('301'), null, 'Animalia Getafe', pg_temp.fx('405'), 50) = '{}'
    and pg_temp.page_ids(pg_temp.fx('301'), null, 'A', pg_temp.fx('401'), 50) = array[pg_temp.fx('402')],
    'Cursor: a cursor naming a sibling Clinic reveals nothing'
);
reset role;

-- ===========================================================================
-- G. Order, ties, unnamed Clinics, cursor boundaries (VN 30).
-- ===========================================================================

select pg_temp.act_as(19);
set local role authenticated;

create temporary table owner_order on commit drop as
select ordinality, clinic_id, clinic_display_name
from public.get_my_organization_professional_clinics(pg_temp.fx('306'), null, null, null, 50) with ordinality;
reset role;

select pg_temp.assert_true(
    (select array_agg(clinic_id order by ordinality) from owner_order where ordinality > 33)
        = array[pg_temp.s(34), pg_temp.s(35), pg_temp.s(36)]
    and (select bool_and(clinic_display_name is null) from owner_order where ordinality > 33)
    and (select bool_and(clinic_display_name is not null) from owner_order where ordinality <= 33),
    'Order: unnamed Clinics last, in clinic_id order'
);
select pg_temp.assert_true(
    (select array_agg(clinic_id order by ordinality) from owner_order where clinic_display_name = 'Clínica Centro')
        = array[pg_temp.s(13), pg_temp.s(14), pg_temp.s(15)]
    and (select max(ordinality) - min(ordinality) from owner_order where clinic_display_name = 'Clínica Centro') = 2
    and (select array_agg(clinic_id order by ordinality) from owner_order where ordinality <= 12)
        = (select array_agg(pg_temp.s(n) order by n) from generate_series(1, 12) as n),
    'Order: identical display names are consecutive in clinic_id order'
);
select pg_temp.assert_true(
    (select array_agg(clinic_display_name order by ordinality) from owner_order where ordinality <= 33)
        = (select array_agg(clinic_display_name order by clinic_display_name, clinic_id) from owner_order where ordinality <= 33),
    'Order: display names follow the database default collation'
);

set local role authenticated;
select pg_temp.assert_true(
    -- After the last named row: every unnamed row.
    pg_temp.page_ids(pg_temp.fx('306'), null,
        (select clinic_display_name from owner_order where ordinality = 33),
        (select clinic_id from owner_order where ordinality = 33), 50)
        = array[pg_temp.s(34), pg_temp.s(35), pg_temp.s(36)]
    -- After an unnamed cursor: only unnamed rows with a greater id.
    and pg_temp.page_ids(pg_temp.fx('306'), null, null, pg_temp.s(34), 50) = array[pg_temp.s(35), pg_temp.s(36)]
    -- After the last row: empty.
    and pg_temp.page_ids(pg_temp.fx('306'), null, null, pg_temp.s(36), 50) = '{}'
    -- Inside a run of identical names the id breaks the tie.
    and pg_temp.page_ids(pg_temp.fx('306'), null, 'Clínica Centro', pg_temp.s(13), 2) = array[pg_temp.s(14), pg_temp.s(15)]
    and pg_temp.page_ids(pg_temp.fx('306'), null, 'Clínica Centro', pg_temp.s(15), 1)
        = array[(select clinic_id from owner_order
                 where ordinality = (select ordinality + 1 from owner_order where clinic_id = pg_temp.s(15)))],
    'Cursor: named, unnamed and last-row boundaries'
);
reset role;

-- ===========================================================================
-- H. Search before the limit and search parity for every page size (VN 31).
-- ===========================================================================

select pg_temp.act_as(19);
set local role authenticated;
select pg_temp.assert_true(
    -- Twelve fillers precede every "clinica" match; a page of 5 still holds matches.
    (select count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('306'), 'clinica', null, null, 5)) = 5
    and not exists (
        select 1 from public.get_my_organization_professional_clinics(pg_temp.fx('306'), 'clinica', null, null, 5) as page
        where page.clinic_display_name like 'Aaa Filler%'),
    'Search before limit: the first page holds matches when non-matching rows precede them'
);
reset role;

create temporary table search_term (label text primary key, term text) on commit drop;
insert into search_term values
    ('null', null), ('empty', ''), ('spaces', E'  \t '), ('clinica', 'clinica'), ('CLÍNICA', 'CLÍNICA'),
    ('pena', 'pena'), ('peña', 'peña'), ('decomposed PEÑA', 'PEN' || U&'\0303' || 'A'),
    ('veterinaria peña', 'veterinaria   peña'), ('vet', '  vet  '), ('clinica centro', 'clinica centro'),
    ('ligature', U&'\FB01' || 'nca'), ('fullwidth', U&'\FF23\FF4C\FF49\FF4E\FF49\FF43\FF41'),
    ('percent', '%'), ('underscore', '_'), ('backslash', '\'), ('bracket', '['),
    ('øster', 'øster'), ('oster', 'oster'), ('strasse', 'strasse'), ('straße', 'STRASSE'),
    ('œuvre', 'œuvre'), ('istanbul', 'ISTANBUL'), ('zero', 'zero'), ('zerowidth', 'zerowidth'),
    ('filler 1', 'FILLER 1'), ('a', 'a'), ('no match', 'zz no match'), ('max length', repeat('clínica ', 12) || 'clín');

do $$
declare
    fixture record;
    organization uuid;
    search record;
    expected jsonb;
    actual jsonb;
    page_size integer;
begin
    for fixture in select * from fixture_clinics where user_number in (4, 6, 17, 19, 20, 21) order by user_number loop
        foreach organization in array array[pg_temp.fx('301'), pg_temp.fx('302'), pg_temp.fx('306')] loop
            for search in select * from search_term order by label loop
                expected := pg_temp.oracle(fixture.clinics, organization, search.term);
                for page_size in 1..least(jsonb_array_length(expected) + 1, 50) loop
                    perform pg_temp.act_as(fixture.user_number);
                    set local role authenticated;
                    actual := pg_temp.read_pages(organization, search.term, page_size);
                    reset role;
                    if actual is distinct from expected then
                        insert into violation values ('H', format('U%s org %s search %s size %s: expected %s got %s',
                            fixture.user_number, organization, search.label, page_size, expected, actual));
                    end if;
                end loop;
            end loop;
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (select 1 from violation where section = 'H'),
    'Search parity: pages equal the narrowed ORG-008 result for every search and page size'
);

-- ===========================================================================
-- I. Normalization and matching, literal expectations (VN 32, 33).
-- ===========================================================================

-- I1. N(text) literal values, also under collation "C" and a libc collation.
select pg_temp.assert_true(
    public.professional_clinic_search_key(input) is not distinct from expected
    and public.professional_clinic_search_key(input collate "C") is not distinct from expected
    and public.professional_clinic_search_key(input collate "en_US.utf8") is not distinct from expected,
    'Normalization ' || label
)
from (values
    ('acute upper', 'CLÍNICA', 'clinica'),
    ('enye', 'Peña', 'pena'),
    ('decomposed', 'PEN' || U&'\0303' || 'A', 'pena'),
    ('diaeresis', 'Pingüino', 'pinguino'),
    ('o-stroke upper', 'ØSTER', 'øster'),
    ('oe upper', 'ŒUVRE', 'œuvre'),
    ('ae upper', 'ÆGIR', 'ægir'),
    ('l-stroke upper', 'ŁÓDŹ', 'łodz'),
    ('dotted capital I', U&'\0130' || 'STANBUL', 'istanbul'),
    ('cyrillic', 'ПРИВЕТ', 'привет'),
    ('sharp s kept', 'STRAßE', 'straße'),
    ('ligature', U&'\FB01' || 'NCA', 'finca'),
    ('fullwidth', U&'\FF23\FF2C\FF29\FF2E\FF29\FF23\FF21', 'clinica'),
    ('nbsp', 'A' || U&'\00A0' || 'B', 'a b'),
    ('narrow nbsp', 'A' || U&'\202F' || 'B', 'a b'),
    ('ideographic space', 'A' || U&'\3000' || 'B', 'a b'),
    ('em space', 'A' || U&'\2003' || 'B', 'a b'),
    ('line separator', 'A' || U&'\2028' || 'B', 'a b'),
    ('next line', 'A' || U&'\0085' || 'B', 'a b'),
    ('ogham space', 'A' || U&'\1680' || 'B', 'a b'),
    ('controls', E'A\t\n\r\f\u000bB', 'a b'),
    ('runs and ends', E'  Clínica \t  Centro  ', 'clinica centro'),
    ('zero width kept', 'A' || U&'\200B' || 'B', 'a' || U&'\200B' || 'b'),
    ('literals', '50% [A]_\*', '50% [a]_\*'),
    ('empty', '', ''),
    ('only spaces', E' \t' || U&'\00A0', ''),
    ('null', null, null)
) as cases (label, input, expected);

-- I2. Matching through the read, as the Owner of the Search Org.
create function pg_temp.match_set(p_term text)
returns uuid[] language sql as $$
    select pg_temp.sorted(pg_temp.page_ids(pg_temp.fx('306'), p_term, null, null, 50))
$$;

select pg_temp.act_as(19);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.match_set(term) = pg_temp.sorted(array(select pg_temp.s(n) from unnest(expected) as n)),
    'Search ' || label
)
from (values
    ('clinica', 'clinica', array[13,14,15,16,17,18,19,29,30]),
    ('Clínica', 'Clínica', array[13,14,15,16,17,18,19,29,30]),
    ('CLÍNICA', 'CLÍNICA', array[13,14,15,16,17,18,19,29,30]),
    ('fullwidth', U&'\FF23\FF4C\FF49\FF4E\FF49\FF43\FF41', array[13,14,15,16,17,18,19,29,30]),
    ('pena', 'pena', array[20,21,22,30]),
    ('peña', 'peña', array[20,21,22,30]),
    ('decomposed PEÑA', 'PEN' || U&'\0303' || 'A', array[20,21,22,30]),
    ('veterinaria peña', 'veterinaria   peña', array[30]),
    ('vet', '  vet  ', array[20,27,30,32]),
    ('clinica centro', 'clinica centro', array[13,14,15,16,17,18,19]),
    ('clinica nbsp centro', 'clinica' || U&'\00A0' || 'centro', array[13,14,15,16,17,18,19]),
    ('ligature', U&'\FB01' || 'nca', array[28]),
    ('percent', '%', array[23]),
    ('underscore', '_', array[24]),
    ('backslash', '\', array[25]),
    ('bracket', '[', array[25]),
    ('øster', 'øster', array[27]),
    ('ØSTER', 'ØSTER', array[27]),
    ('oster', 'oster', array[]::integer[]),
    ('strasse', 'strasse', array[]::integer[]),
    ('straße', 'STRAßE', array[26]),
    ('œuvre', 'œuvre', array[31]),
    ('istanbul', 'istanbul', array[32]),
    ('zero', 'zero', array[33]),
    ('zerowidth', 'zerowidth', array[]::integer[]),
    ('filler 1', 'FILLER 1', array[10,11,12]),
    ('no match', 'zz no match', array[]::integer[])
) as cases (label, term, expected);

select pg_temp.assert_true(
    pg_temp.match_set(term) = pg_temp.sorted(array(select pg_temp.s(n) from generate_series(1, 36) as n)),
    'Search without narrowing ' || label
)
from (values ('null', null), ('empty', ''), ('spaces', E' \t '), ('nbsp', U&'\00A0\3000')) as cases (label, term);

select pg_temp.assert_true(
    not (pg_temp.s(34) = any (pg_temp.match_set('a')) or pg_temp.s(35) = any (pg_temp.match_set('a'))
         or pg_temp.s(36) = any (pg_temp.match_set('a')))
    and cardinality(pg_temp.match_set('a')) > 10,
    'Search: an unnamed Clinic never matches a non-empty search'
);

-- I3. VN 33: a search carrying collation "C" or a libc collation behaves the same.
select pg_temp.assert_true(
    pg_temp.sorted(pg_temp.page_ids(pg_temp.fx('306'), 'ØSTER' collate "C", null, null, 50)) = array[pg_temp.s(27)]
    and pg_temp.sorted(pg_temp.page_ids(pg_temp.fx('306'), 'CLÍNICA' collate "C", null, null, 50))
        = pg_temp.match_set('clinica')
    and pg_temp.sorted(pg_temp.page_ids(pg_temp.fx('306'), 'ŒUVRE' collate "en_US.utf8", null, null, 50)) = array[pg_temp.s(31)],
    'Search independent of the input collation'
);
reset role;

-- Display names normalize identically whatever collation they carry.
select pg_temp.assert_true(
    not exists (
        select 1 from public.clinic_public_profiles as profile
        where profile.clinic_id::text like 'd0150000-%' and profile.display_name is not null
          and (public.professional_clinic_search_key(profile.display_name collate "C")
                   is distinct from public.professional_clinic_search_key(profile.display_name)
               or public.professional_clinic_search_key(profile.display_name collate "en_US.utf8")
                   is distinct from public.professional_clinic_search_key(profile.display_name))),
    'Normalization of stored names independent of their collation'
);

-- ===========================================================================
-- J. Changes between pages (VN 35).
-- ===========================================================================

-- J1. A supporting relationship ending between pages.
select pg_temp.act_as(20);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('306'), null, null, null, 1) = array[pg_temp.s(13)],
    'Between pages: the Clinic Receptionist''s first page'
);
reset role;
update public.organization_responsibility_grants
set effective_end = statement_timestamp(), ended_by_user_id = pg_temp.fx('219')
where id = pg_temp.fx('6a1');
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.page_ids(pg_temp.fx('306'), null, 'Clínica Centro', pg_temp.s(13), 50) = array[pg_temp.s(34)],
    'Between pages: a Clinic whose grant ended is not returned later'
);
reset role;

-- J2. Renames and a new Clinic between pages of one search.
select pg_temp.act_as(19);
set local role authenticated;
create temporary table first_search_page on commit drop as
select ordinality, clinic_id, clinic_display_name
from public.get_my_organization_professional_clinics(pg_temp.fx('306'), 'clinica', null, null, 4) with ordinality;
reset role;

-- S30 no longer matches; the first row of page 1 moves after the cursor; a
-- new matching Clinic sorts after the cursor.
update public.clinic_public_profiles set display_name = 'Veterinaria Peña' where clinic_id = pg_temp.s(30);
update public.clinic_public_profiles set display_name = 'Zzz Clínica Renamed'
where clinic_id = (select clinic_id from first_search_page where ordinality = 1);
set local session_replication_role = replica;
insert into public.clinics (id, organization_id, is_published) values (pg_temp.s(37), pg_temp.fx('306'), false);
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.s(37), 'Zz Nueva Clínica');
set local session_replication_role = origin;

set local role authenticated;
create temporary table later_search_pages on commit drop as
select ordinality, (row_entry ->> 'clinic_id')::uuid as clinic_id
from jsonb_array_elements(pg_temp.read_pages(pg_temp.fx('306'), 'clinica', 3,
    (select clinic_display_name from first_search_page where ordinality = 4),
    (select clinic_id from first_search_page where ordinality = 4))) with ordinality as listed (row_entry, ordinality);
reset role;

select pg_temp.assert_true(
    (select count(*) from first_search_page) = 4
    and not exists (select 1 from later_search_pages where clinic_id = pg_temp.s(30))
    and (select count(*) from later_search_pages where clinic_id = pg_temp.s(37)) = 1
    -- Accepted (BR-24): the renamed first row moved across the cursor and is returned again, once.
    and (select count(*) from later_search_pages
         where clinic_id = (select clinic_id from first_search_page where ordinality = 1)) = 1
    and not exists (select 1 from later_search_pages
                    where clinic_id in (select clinic_id from first_search_page where ordinality between 2 and 4))
    and (select count(*) from later_search_pages) = (select count(distinct clinic_id) from later_search_pages),
    'Between pages: no-longer-matching and new Clinics, a rename across the cursor, nothing repeated'
);

-- A refresh (new first read) is authoritative.
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.sorted(pg_temp.json_ids(pg_temp.read_pages(pg_temp.fx('306'), 'clinica', 50)))
        = pg_temp.sorted(array[pg_temp.s(13), pg_temp.s(14), pg_temp.s(15), pg_temp.s(16), pg_temp.s(17),
                               pg_temp.s(18), pg_temp.s(19), pg_temp.s(29), pg_temp.s(37)]),
    'Between pages: a new first read reflects the current state'
);
reset role;

-- ===========================================================================
-- K. No writes, no row locks (VN 37).
-- ===========================================================================

do $$
declare
    writes_before bigint;
    writes_after bigint;
    user_number integer;
begin
    select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) into writes_before from pg_stat_xact_user_tables;
    foreach user_number in array array[4, 6, 9, 17, 19, 20, 21] loop
        perform pg_temp.act_as(user_number);
        set local role authenticated;
        perform count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('306'), 'clinica', null, null, 50);
        perform count(*) from public.get_my_organization_professional_clinics(pg_temp.fx('301'), null, 'A', pg_temp.fx('401'), 50);
        reset role;
    end loop;
    select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) into writes_after from pg_stat_xact_user_tables;
    perform pg_temp.assert_true(writes_after = writes_before, 'No writes: the read writes no row');
end;
$$;

-- ===========================================================================
-- V. Volume: 3 000 Clinics in one Organization (5% unnamed). The read is
--    bounded by the Organization's Clinics; no index is added.
-- ===========================================================================

set local session_replication_role = replica;

-- U23 Owner, U24 Receptionist @ 3 Clinics, U25 Veterinarian assigned @ 2
-- Clinics, U26 Organization-scoped Receptionist.
insert into auth.users (id, email_confirmed_at)
select pg_temp.fx('1' || n), '2020-01-01Z' from generate_series(23, 26) as n;
insert into public.users (id)
select pg_temp.fx('2' || n) from generate_series(23, 26) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.fx('2' || n), pg_temp.fx('1' || n) from generate_series(23, 26) as n;
insert into public.veterinary_organizations (id, display_name) values (pg_temp.fx('307'), 'Volume Org');

insert into public.clinics (id, organization_id, is_published)
select pg_temp.fx('7' || lpad(n::text, 5, '0')), pg_temp.fx('307'), n % 3 = 0
from generate_series(1, 3000) as n;
insert into public.clinic_public_profiles (clinic_id, display_name)
select pg_temp.fx('7' || lpad(n::text, 5, '0')),
       'Clínica ' || (array['Norte', 'Sur', 'Peña', 'Centro', 'Ávila'])[n % 5 + 1] || ' ' || lpad(n::text, 4, '0')
from generate_series(1, 3000) as n
where n % 20 <> 0;

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
select pg_temp.fx('5' || n), pg_temp.fx('307'), pg_temp.fx('2' || n), '2020-01-01Z', null, null
from generate_series(23, 26) as n;
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    (pg_temp.fx('623'), pg_temp.fx('523'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('223'), null),
    (pg_temp.fx('6b0'), pg_temp.fx('524'), 'RECEPTIONIST', 'CLINIC', pg_temp.fx('700010'), '2020-01-01Z', null, pg_temp.fx('223'), null),
    (pg_temp.fx('6b1'), pg_temp.fx('524'), 'RECEPTIONIST', 'CLINIC', pg_temp.fx('701500'), '2020-01-01Z', null, pg_temp.fx('223'), null),
    (pg_temp.fx('6b2'), pg_temp.fx('524'), 'RECEPTIONIST', 'CLINIC', pg_temp.fx('702990'), '2020-01-01Z', null, pg_temp.fx('223'), null),
    (pg_temp.fx('625'), pg_temp.fx('525'), 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('223'), null),
    (pg_temp.fx('626'), pg_temp.fx('526'), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('223'), null);
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.fx('725'), pg_temp.fx('225'));
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.fx('825'), pg_temp.fx('725'), pg_temp.fx('525'), pg_temp.fx('700007'), '2020-01-01Z', null),
    (pg_temp.fx('826'), pg_temp.fx('725'), pg_temp.fx('525'), pg_temp.fx('702222'), '2020-01-01Z', null),
    (pg_temp.fx('827'), pg_temp.fx('725'), pg_temp.fx('525'), pg_temp.fx('702223'), '2020-01-01Z', '2021-01-01Z');

set local session_replication_role = origin;
analyze public.clinics, public.clinic_public_profiles, public.organization_memberships,
        public.organization_responsibility_grants, public.veterinarian_clinic_assignments;

-- V1. Correctness at volume. Organization-wide actors: every page of 50
-- concatenates to the Clinics of the Organization for which
-- user_has_clinic_capability grants a Clinic-context capability, in BR-23
-- order, with and without a search. Clinic-bound actors: their exact Clinics
-- (their completeness over every Clinic is section E's).
create function pg_temp.volume_oracle(p_user_id uuid, p_search text)
returns jsonb language sql as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'clinic_id', clinic.id::text, 'clinic_display_name', profile.display_name)
               order by profile.display_name nulls last, clinic.id), '[]'::jsonb)
    from public.clinics as clinic
    left join public.clinic_public_profiles as profile on profile.clinic_id = clinic.id
    where clinic.organization_id = pg_temp.fx('307')
      and (nullif(public.professional_clinic_search_key(p_search), '') is null
           or strpos(public.professional_clinic_search_key(profile.display_name),
                     public.professional_clinic_search_key(p_search)) > 0)
      and exists (
          select 1 from public.professional_capability_catalog() as catalog_entry
          where catalog_entry.capability_context = 'CLINIC'
            and public.user_has_clinic_capability(p_user_id, clinic.id, catalog_entry.capability))
$$;

create temporary table volume_complete (user_number integer, search text, pages jsonb) on commit drop;
grant insert on volume_complete to authenticated;
do $$
declare
    user_number integer;
    search text;
begin
    foreach user_number in array array[23, 24, 25, 26] loop
        foreach search in array array[null, 'PEÑA', 'centro 22'] loop
            perform pg_temp.act_as(user_number);
            set local role authenticated;
            insert into volume_complete values (user_number, search, pg_temp.read_pages(pg_temp.fx('307'), search, 50));
            reset role;
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (
        select 1 from volume_complete
        where user_number in (23, 26)
          and pages is distinct from pg_temp.volume_oracle(pg_temp.fx('2' || user_number), search))
    and (select jsonb_array_length(pages) from volume_complete where user_number = 23 and search is null) = 3000
    and (select jsonb_array_length(pages) from volume_complete where user_number = 26 and search is null) = 3000
    and (select jsonb_array_length(pages) from volume_complete where user_number = 23 and search = 'PEÑA') = 600
    -- U24: S10 "Clínica Norte 0010", S2990 "Clínica Norte 2990", S1500 unnamed.
    and (select pg_temp.json_ids(pages) from volume_complete where user_number = 24 and search is null)
        = array[pg_temp.fx('700010'), pg_temp.fx('702990'), pg_temp.fx('701500')]
    and (select pg_temp.json_ids(pages) from volume_complete where user_number = 24 and search = 'PEÑA') = '{}'
    -- U25: S0007 "Clínica Peña 0007", S2222 "Clínica Peña 2222" (S2223 ended).
    and (select pg_temp.json_ids(pages) from volume_complete where user_number = 25 and search is null)
        = array[pg_temp.fx('700007'), pg_temp.fx('702222')]
    and (select pg_temp.json_ids(pages) from volume_complete where user_number = 25 and search = 'PEÑA')
        = array[pg_temp.fx('700007'), pg_temp.fx('702222')]
    and (select pg_temp.json_ids(pages) from volume_complete where user_number = 25 and search = 'centro 22') = '{}',
    'Volume: every actor''s pages equal the authoritative Clinics of the Organization'
);

-- V2. Timings of single pages.
create temporary table volume_timing (scenario text primary key, milliseconds numeric not null, rows_returned integer not null) on commit drop;
grant insert on volume_timing to authenticated;

do $$
declare
    probe record;
    started timestamptz;
    returned integer;
    repetition integer;
    best numeric;
begin
    for probe in
        select * from (values
            ('owner first page', 23, null::text, null::text, null::uuid),
            ('owner deep page', 23, null, 'Clínica Norte 2990', pg_temp.fx('702990')),
            ('owner unnamed tail', 23, null, null, pg_temp.fx('702900')),
            ('owner common search', 23, 'peña', null, null),
            ('owner rare search', 23, 'clinica centro 2993', null, null),
            ('owner no-match search', 23, 'zz no match', null, null),
            ('clinic receptionist first page', 24, null, null, null),
            ('clinic receptionist search', 24, 'clinica', null, null),
            ('veterinarian first page', 25, null, null, null),
            ('organization receptionist first page', 26, null, null, null),
            ('organization receptionist deep page', 26, null, 'Clínica Norte 2990', pg_temp.fx('702990')),
            ('organization receptionist search', 26, 'peña', null, null),
            ('non-member', 19, null, null, null)
        ) as cases (scenario, user_number, search, after_name, after_id)
    loop
        best := null;
        for repetition in 1..3 loop
            perform pg_temp.act_as(probe.user_number);
            set local role authenticated;
            started := clock_timestamp();
            select count(*) into returned
            from public.get_my_organization_professional_clinics(
                pg_temp.fx('307'), probe.search, probe.after_name, probe.after_id, 20);
            best := least(coalesce(best, 1e9), extract(epoch from clock_timestamp() - started) * 1000);
            reset role;
        end loop;
        insert into volume_timing values (probe.scenario, round(best, 1), returned);
        raise notice 'volume % : % ms, % rows', probe.scenario, round(best, 1), returned;
    end loop;
end;
$$;

select pg_temp.assert_true(
    (select rows_returned from volume_timing where scenario = 'owner first page') = 20
    and (select rows_returned from volume_timing where scenario = 'owner deep page') = 20
    and (select rows_returned from volume_timing where scenario = 'owner unnamed tail') = 5
    and (select rows_returned from volume_timing where scenario = 'owner common search') = 20
    and (select rows_returned from volume_timing where scenario = 'owner rare search') = 1
    and (select rows_returned from volume_timing where scenario = 'owner no-match search') = 0
    and (select rows_returned from volume_timing where scenario = 'clinic receptionist first page') = 3
    and (select rows_returned from volume_timing where scenario = 'clinic receptionist search') = 2
    and (select rows_returned from volume_timing where scenario = 'veterinarian first page') = 2
    and (select rows_returned from volume_timing where scenario = 'organization receptionist first page') = 20
    and (select rows_returned from volume_timing where scenario = 'organization receptionist deep page') = 20
    and (select rows_returned from volume_timing where scenario = 'organization receptionist search') = 20
    and (select rows_returned from volume_timing where scenario = 'non-member') = 0,
    'Volume: page contents'
);

select pg_temp.assert_true(
    not exists (select 1 from volume_timing where milliseconds > 250),
    'Volume: every single page is read within the time budget'
);

rollback;

-- Appointment Requester Contact — Phase 1 (SPEC-ID-006 BR-42, SPEC-APT-012
-- BR-49/BR-50, Verification Notes 53–60), migration
-- 20261107090000_appointment_requester_contact.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deliberately minimal deterministic
-- context and to switch between impersonated Users (same rationale as
-- clinic_appointment_schedule_pet_name_spec_apt_012.sql).
--
-- Covers:
--   * contract, attributes and ACL of the contact read; no client privilege
--     on auth.users; user_profiles still own-row only;
--   * requester_display_name in the schedule and the contact read for OWNER,
--     ADMINISTRATOR (Organization and Clinic scope), RECEPTIONIST
--     (Organization and Clinic scope) and the assigned VETERINARIAN;
--   * the original requester in every lifecycle state, also after their
--     Guardianship ended, never a co-Guardian;
--   * blank/missing display name and unverified email as NULL;
--   * one uniform 42501 without hint for other-Clinic actors, an unassigned
--     Veterinarian, ended Membership/Grant/Assignment, another Organization, a
--     bare Member, Guardians (including the requester), unknown or foreign
--     Clinic/Appointment; 28000 without subject or domain User; anon denied;
--   * later name/email changes and loss of verification are reflected;
--   * reads create nothing.
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

-- The uniform contact denial: exactly this SQLSTATE and message, no hint, no
-- detail.
create function pg_temp.assert_contact_denied(p_clinic_id text, p_appointment_id text)
returns void language plpgsql as $$
declare
    error_hint text;
    error_detail text;
begin
    begin
        execute format(
            'select * from public.get_clinic_appointment_requester_contact(%s, %s)',
            coalesce(quote_literal(p_clinic_id) || '::uuid', 'null::uuid'),
            coalesce(quote_literal(p_appointment_id) || '::uuid', 'null::uuid')
        );
    exception when others then
        get stacked diagnostics error_hint = pg_exception_hint, error_detail = pg_exception_detail;
        if sqlstate = '42501'
           and sqlerrm = 'Appointment requester contact unavailable'
           and coalesce(error_hint, '') = ''
           and coalesce(error_detail, '') = '' then
            return;
        end if;
        raise exception 'Expected uniform contact denial for (%, %), received %: % (hint %)',
            p_clinic_id, p_appointment_id, sqlstate, sqlerrm, error_hint;
    end;
    raise exception 'Expected contact denial for (%, %), but it succeeded', p_clinic_id, p_appointment_id;
end;
$$;

create temporary table contact_snapshot (
    label text not null,
    appointment_id uuid not null,
    requester_display_name text,
    requester_email text,
    row_count integer not null,
    primary key (label, appointment_id)
) on commit drop;

create temporary table schedule_names (
    label text not null,
    appointment_id uuid not null,
    requester_display_name text,
    primary key (label, appointment_id)
) on commit drop;

grant select, insert on contact_snapshot, schedule_names to authenticated;

-- A1's Appointments, in fixture order.
create function pg_temp.a1_appointments()
returns uuid[] language sql as $$
    select array(
        select ('c0e70000-0000-4000-8000-000000000b' || lpad(n::text, 2, '0'))::uuid
        from generate_series(1, 9) as n
        order by n
    )
$$;

create function pg_temp.capture_contacts(p_label text)
returns void language plpgsql as $$
declare
    appointment_id uuid;
    returned_rows integer;
    returned_name text;
    returned_email text;
begin
    foreach appointment_id in array pg_temp.a1_appointments() loop
        select count(*), max(contact.requester_display_name), max(contact.requester_email)
        into returned_rows, returned_name, returned_email
        from public.get_clinic_appointment_requester_contact(
            'c0e70000-0000-4000-8000-000000000401', appointment_id
        ) as contact;
        insert into contact_snapshot
        values (p_label, appointment_id, returned_name, returned_email, returned_rows);
    end loop;
end;
$$;

create function pg_temp.capture_schedule_names(p_label text)
returns void language sql as $$
    insert into schedule_names
    select p_label, schedule.id, schedule.requester_display_name
    from public.get_clinic_appointment_schedule('c0e70000-0000-4000-8000-000000000401') as schedule
$$;

create function pg_temp.contacts(p_label text)
returns text[] language sql as $$
    select coalesce(array_agg(row(
        snapshot.appointment_id, snapshot.requester_display_name,
        snapshot.requester_email, snapshot.row_count
    )::text order by snapshot.appointment_id), '{}')
    from contact_snapshot as snapshot
    where snapshot.label = p_label
$$;

create function pg_temp.names(p_label text)
returns text[] language sql as $$
    select coalesce(array_agg(row(
        snapshot.appointment_id, snapshot.requester_display_name
    )::text order by snapshot.appointment_id), '{}')
    from schedule_names as snapshot
    where snapshot.label = p_label
$$;

-- ===========================================================================
-- 1. Contract, attributes, ACL, and unchanged Auth/Profile security.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result(
        'public.get_clinic_appointment_requester_contact(uuid, uuid)'::regprocedure
    ) = 'TABLE(requester_display_name text, requester_email text)',
    'Contract: the contact read returns exactly requester_display_name and requester_email'
);

select pg_temp.assert_true(
    (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.get_clinic_appointment_requester_contact(uuid, uuid)'::regprocedure),
    'Attributes: SECURITY DEFINER, STABLE, empty search_path'
);

select pg_temp.assert_true(
    (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                      order by acl_entry.grantee::regrole::text)
     from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
     where proc.oid = 'public.get_clinic_appointment_requester_contact(uuid, uuid)'::regprocedure
       and acl_entry.grantee <> proc.proowner)
    = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', 'public.get_clinic_appointment_requester_contact(uuid, uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_clinic_appointment_requester_contact(uuid, uuid)', 'EXECUTE'),
    'ACL: EXECUTE only for authenticated (and service_role by platform default)'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from pg_proc as proc, unnest(proc.proargnames) as argument_name
        where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure
          and argument_name ~ '(email|phone|guardianship|auth)'
    ),
    'Schedule: no email, phone, Guardianship, or auth field (the email is per-Appointment only)'
);

select pg_temp.assert_true(
    not has_table_privilege('authenticated', 'auth.users', 'SELECT')
    and not has_table_privilege('anon', 'auth.users', 'SELECT')
    and not has_table_privilege('authenticated', 'public.user_authentication_identities', 'SELECT')
    and (select array_agg(policy.policyname::text order by policy.policyname)
         from pg_policies as policy
         where policy.schemaname = 'public' and policy.tablename = 'user_profiles')
        = array['user_profiles_insert_own', 'user_profiles_select_own', 'user_profiles_update_own'],
    'Auth/Profile security unchanged: no client read of auth.users or identities; own-row user_profiles policies only'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects c0e70000-…-0000000001NN, domain Users …-0000000002NN:
--   01 María — Guardian of Luna, requester of b01–b06, b10, b11;
--      display name '  María López  ', verified maria@example.test
--   02 Carlos — current co-Guardian of Luna and current Guardian of Toby
--   03 Ana — former Guardian of Toby (ended), requester of b07
--   04 blank display name, unverified email — Guardian of Kira, requester of b08
--   05 no user_profiles row, verified email — Guardian of Kira, requester of b09
--   06 OWNER (Organization) OrgA          07 ADMINISTRATOR (Organization) OrgA
--   08 ADMINISTRATOR (Clinic A1)           09 RECEPTIONIST (Organization) OrgA
--   10 RECEPTIONIST (Clinic A1)            11 VETERINARIAN, current Assignment @ A1
--   12 VETERINARIAN, Assignment @ A2 only  13 VETERINARIAN, Assignment @ A1 ended
--   14 RECEPTIONIST (Clinic A2)            15 RECEPTIONIST (Organization), Membership ended
--   16 RECEPTIONIST (Clinic A1), Grant ended
--   17 ADMINISTRATOR (Organization) OrgB   18 bare OrgA Member
--   20 authenticated subject without domain User
--
-- OrgA (…0301) operates A1 (…0401) and A2 (…0402); OrgB (…0302) operates B1 (…0411).
-- Appointments at A1: b01 REQUESTED, b02 CONFIRMED, b03 COMPLETED, b04 CANCELLED,
-- b05 NO_SHOW, b06 EXPIRED (Luna, María); b07 CONFIRMED (Toby, Ana);
-- b08 REQUESTED (Kira, 04); b09 CONFIRMED (Kira, 05).
-- b10 REQUESTED at A2 and b11 REQUESTED at B1 (Luna, María).
-- ===========================================================================

insert into auth.users (id, email, email_confirmed_at)
select ('c0e70000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       case n
           when 1 then 'maria@example.test'
           when 2 then 'carlos@example.test'
           when 3 then 'ana@example.test'
           when 4 then 'unverified@example.test'
           when 5 then 'noprofile@example.test'
           else 'staff' || n || '@example.test'
       end,
       case when n = 4 then null else '2020-01-01Z'::timestamptz end
from generate_series(1, 20) as n
where n <> 19;

insert into public.users (id)
select ('c0e70000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 18) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select ('c0e70000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       ('c0e70000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 18) as n;

insert into public.user_profiles (user_id, display_name) values
    ('c0e70000-0000-4000-8000-000000000201', '  María López  '),
    ('c0e70000-0000-4000-8000-000000000202', 'Carlos Ruiz'),
    ('c0e70000-0000-4000-8000-000000000203', 'Ana Gil'),
    ('c0e70000-0000-4000-8000-000000000204', '   ');

insert into public.veterinary_organizations (id, display_name) values
    ('c0e70000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('c0e70000-0000-4000-8000-000000000302', 'VetCare Group');

insert into public.clinics (id, organization_id, is_published) values
    ('c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000301', true),
    ('c0e70000-0000-4000-8000-000000000402', 'c0e70000-0000-4000-8000-000000000301', true),
    ('c0e70000-0000-4000-8000-000000000411', 'c0e70000-0000-4000-8000-000000000302', true);

insert into public.organization_memberships (
    id, organization_id, user_id, effective_start, effective_end, ended_by_user_id
)
select ('c0e70000-0000-4000-8000-0000000005' || lpad(n::text, 2, '0'))::uuid,
       case when n = 17 then 'c0e70000-0000-4000-8000-000000000302'::uuid
            else 'c0e70000-0000-4000-8000-000000000301'::uuid end,
       ('c0e70000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       '2020-01-01Z',
       case when n = 15 then '2021-01-01Z'::timestamptz end,
       case when n = 15 then 'c0e70000-0000-4000-8000-000000000206'::uuid end
from generate_series(6, 18) as n;

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
)
select ('c0e70000-0000-4000-8000-0000000006' || lpad(grant_row.n::text, 2, '0'))::uuid,
       ('c0e70000-0000-4000-8000-0000000005' || lpad(grant_row.n::text, 2, '0'))::uuid,
       grant_row.responsibility, grant_row.scope_type, grant_row.clinic_id::uuid,
       '2020-01-01Z', grant_row.effective_end::timestamptz,
       'c0e70000-0000-4000-8000-000000000206',
       case when grant_row.effective_end is not null then 'c0e70000-0000-4000-8000-000000000206'::uuid end
from (values
    (6,  'OWNER',         'ORGANIZATION', null,                                   null),
    (7,  'ADMINISTRATOR', 'ORGANIZATION', null,                                   null),
    (8,  'ADMINISTRATOR', 'CLINIC',       'c0e70000-0000-4000-8000-000000000401', null),
    (9,  'RECEPTIONIST',  'ORGANIZATION', null,                                   null),
    (10, 'RECEPTIONIST',  'CLINIC',       'c0e70000-0000-4000-8000-000000000401', null),
    (11, 'VETERINARIAN',  'ORGANIZATION', null,                                   null),
    (12, 'VETERINARIAN',  'ORGANIZATION', null,                                   null),
    (13, 'VETERINARIAN',  'ORGANIZATION', null,                                   null),
    (14, 'RECEPTIONIST',  'CLINIC',       'c0e70000-0000-4000-8000-000000000402', null),
    (15, 'RECEPTIONIST',  'ORGANIZATION', null,                                   null),
    (16, 'RECEPTIONIST',  'CLINIC',       'c0e70000-0000-4000-8000-000000000401', '2021-01-01Z'),
    (17, 'ADMINISTRATOR', 'ORGANIZATION', null,                                   null)
) as grant_row (n, responsibility, scope_type, clinic_id, effective_end);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('c0e70000-0000-4000-8000-000000000711', 'c0e70000-0000-4000-8000-000000000211'),
    ('c0e70000-0000-4000-8000-000000000712', 'c0e70000-0000-4000-8000-000000000212'),
    ('c0e70000-0000-4000-8000-000000000713', 'c0e70000-0000-4000-8000-000000000213');

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('c0e70000-0000-4000-8000-000000000811', 'c0e70000-0000-4000-8000-000000000711', 'c0e70000-0000-4000-8000-000000000511', 'c0e70000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    ('c0e70000-0000-4000-8000-000000000812', 'c0e70000-0000-4000-8000-000000000712', 'c0e70000-0000-4000-8000-000000000512', 'c0e70000-0000-4000-8000-000000000402', '2020-01-01Z', null),
    ('c0e70000-0000-4000-8000-000000000813', 'c0e70000-0000-4000-8000-000000000713', 'c0e70000-0000-4000-8000-000000000513', 'c0e70000-0000-4000-8000-000000000401', '2020-01-01Z', '2021-01-01Z');

insert into public.pets (id, name, species, created_at) values
    ('c0e70000-0000-4000-8000-000000000901', 'Luna', 'Dog', '2020-01-01Z'),
    ('c0e70000-0000-4000-8000-000000000902', 'Toby', 'Dog', '2020-01-01Z'),
    ('c0e70000-0000-4000-8000-000000000903', 'Kira', 'Cat', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    ('c0e70000-0000-4000-8000-000000000a01', 'c0e70000-0000-4000-8000-000000000201', 'c0e70000-0000-4000-8000-000000000901', '2020-01-01Z', null),
    ('c0e70000-0000-4000-8000-000000000a02', 'c0e70000-0000-4000-8000-000000000202', 'c0e70000-0000-4000-8000-000000000901', '2020-01-01Z', null),
    ('c0e70000-0000-4000-8000-000000000a03', 'c0e70000-0000-4000-8000-000000000203', 'c0e70000-0000-4000-8000-000000000902', '2020-01-01Z', '2026-01-01Z'),
    ('c0e70000-0000-4000-8000-000000000a04', 'c0e70000-0000-4000-8000-000000000202', 'c0e70000-0000-4000-8000-000000000902', '2026-01-01Z', null),
    ('c0e70000-0000-4000-8000-000000000a05', 'c0e70000-0000-4000-8000-000000000204', 'c0e70000-0000-4000-8000-000000000903', '2020-01-01Z', null),
    ('c0e70000-0000-4000-8000-000000000a06', 'c0e70000-0000-4000-8000-000000000205', 'c0e70000-0000-4000-8000-000000000903', '2020-01-01Z', null);

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at
)
select appointment_row.id::uuid, appointment_row.pet_id::uuid, appointment_row.clinic_id::uuid,
       appointment_row.requester::uuid, 'Check-up', appointment_row.state,
       '2026-09-01T08:00:00Z'::timestamptz + make_interval(mins => appointment_row.n)
from (values
    (1,  'c0e70000-0000-4000-8000-000000000b01', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000201', 'REQUESTED'),
    (2,  'c0e70000-0000-4000-8000-000000000b02', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000201', 'CONFIRMED'),
    (3,  'c0e70000-0000-4000-8000-000000000b03', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000201', 'COMPLETED'),
    (4,  'c0e70000-0000-4000-8000-000000000b04', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000201', 'CANCELLED'),
    (5,  'c0e70000-0000-4000-8000-000000000b05', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000201', 'NO_SHOW'),
    (6,  'c0e70000-0000-4000-8000-000000000b06', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000201', 'EXPIRED'),
    (7,  'c0e70000-0000-4000-8000-000000000b07', 'c0e70000-0000-4000-8000-000000000902', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000203', 'CONFIRMED'),
    (8,  'c0e70000-0000-4000-8000-000000000b08', 'c0e70000-0000-4000-8000-000000000903', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000204', 'REQUESTED'),
    (9,  'c0e70000-0000-4000-8000-000000000b09', 'c0e70000-0000-4000-8000-000000000903', 'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000205', 'CONFIRMED'),
    (10, 'c0e70000-0000-4000-8000-000000000b10', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000402', 'c0e70000-0000-4000-8000-000000000201', 'REQUESTED'),
    (11, 'c0e70000-0000-4000-8000-000000000b11', 'c0e70000-0000-4000-8000-000000000901', 'c0e70000-0000-4000-8000-000000000411', 'c0e70000-0000-4000-8000-000000000201', 'REQUESTED')
) as appointment_row (n, id, pet_id, clinic_id, requester, state);

set local session_replication_role = origin;

-- Side-effect baseline.
create temporary table side_effect_baseline on commit drop as
select
    (select count(*) from public.transactional_communications) as communications,
    (select count(*) from public.medical_access_audit_events) as audit_events,
    (select count(*) from public.appointment_lifecycle_events) as lifecycle_events,
    (select count(*) from public.user_profiles) as profiles;

-- Expected values, transcribed from the fixtures above.
insert into contact_snapshot values
    ('expected', 'c0e70000-0000-4000-8000-000000000b01', 'María López', 'maria@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b02', 'María López', 'maria@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b03', 'María López', 'maria@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b04', 'María López', 'maria@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b05', 'María López', 'maria@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b06', 'María López', 'maria@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b07', 'Ana Gil', 'ana@example.test', 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b08', null, null, 1),
    ('expected', 'c0e70000-0000-4000-8000-000000000b09', null, 'noprofile@example.test', 1);

insert into schedule_names
select 'expected', snapshot.appointment_id, snapshot.requester_display_name
from contact_snapshot as snapshot
where snapshot.label = 'expected';

-- ===========================================================================
-- 2. Authorized actors: schedule name and contact read (VN 53, 54, 57, 58).
-- ===========================================================================

do $$
declare
    subject_suffix text;
begin
    foreach subject_suffix in array array['06', '07', '08', '09', '10', '11'] loop
        perform set_config(
            'request.jwt.claim.sub', 'c0e70000-0000-4000-8000-0000000001' || subject_suffix, true
        );
        set local role authenticated;
        perform pg_temp.capture_contacts('actor_' || subject_suffix);
        perform pg_temp.capture_schedule_names('actor_' || subject_suffix);
        reset role;
    end loop;
end;
$$;

select pg_temp.assert_true(
    pg_temp.contacts('actor_' || suffix) = pg_temp.contacts('expected'),
    'Contact: actor ' || suffix || ' reads the original requester''s current name and verified email '
    'for every A1 Appointment, in every lifecycle state'
)
from unnest(array['06', '07', '08', '09', '10', '11']) as suffix;

select pg_temp.assert_true(
    pg_temp.names('actor_' || suffix) = pg_temp.names('expected'),
    'Schedule: actor ' || suffix || ' sees requester_display_name (trimmed, NULL when blank or missing)'
)
from unnest(array['06', '07', '08', '09', '10', '11']) as suffix;

select pg_temp.assert_true(
    not exists (
        select 1 from contact_snapshot
        where requester_display_name = 'Carlos Ruiz' or requester_email = 'carlos@example.test'
    )
    and not exists (select 1 from schedule_names where requester_display_name = 'Carlos Ruiz'),
    'Multi-Guardian: the current co-Guardian (Luna) and current Guardian (Toby) never appear'
);

select pg_temp.assert_true(
    exists (
        select 1 from contact_snapshot
        where label = 'actor_10'
          and appointment_id = 'c0e70000-0000-4000-8000-000000000b07'
          and requester_display_name = 'Ana Gil'
          and requester_email = 'ana@example.test'
    ),
    'Former Guardian: the requester whose Guardianship ended is still the Appointment contact'
);

-- The A2 Appointment through its own Clinic, for an Organization-wide actor.
select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000106', true);
set local role authenticated;
select pg_temp.assert_true(
    (select count(*) = 1 and bool_and(contact.requester_email = 'maria@example.test')
     from public.get_clinic_appointment_requester_contact(
         'c0e70000-0000-4000-8000-000000000402', 'c0e70000-0000-4000-8000-000000000b10'
     ) as contact),
    'Owner: an Appointment of A2 is read through A2'
);
reset role;

-- ===========================================================================
-- 3. Uniform denial (VN 59).
-- ===========================================================================

-- Other-Clinic actors, unassigned/ended Veterinarians, ended Membership or
-- Grant, other Organization, bare Member, Guardians (including the requester).
do $$
declare
    subject_suffix text;
begin
    foreach subject_suffix in array array['12', '13', '14', '15', '16', '17', '18', '01', '02'] loop
        perform set_config(
            'request.jwt.claim.sub', 'c0e70000-0000-4000-8000-0000000001' || subject_suffix, true
        );
        set local role authenticated;
        perform pg_temp.assert_contact_denied(
            'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000b01'
        );
        reset role;
    end loop;
end;
$$;

-- Authorized at A1 but asking about another Clinic's Appointment, an unknown
-- Appointment, an unknown Clinic, another Organization's Clinic, or nulls.
select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000106', true);
set local role authenticated;
select pg_temp.assert_contact_denied('c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000b10');
select pg_temp.assert_contact_denied('c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000bff');
select pg_temp.assert_contact_denied('c0e70000-0000-4000-8000-0000000004ff', 'c0e70000-0000-4000-8000-000000000b01');
select pg_temp.assert_contact_denied('c0e70000-0000-4000-8000-000000000411', 'c0e70000-0000-4000-8000-000000000b11');
select pg_temp.assert_contact_denied(null, null);
reset role;

-- A Clinic-scoped Receptionist of A1 asking through A2.
select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_contact_denied('c0e70000-0000-4000-8000-000000000402', 'c0e70000-0000-4000-8000-000000000b10');
reset role;

-- No subject; subject without a coherent domain User; anon.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_requester_contact(''c0e70000-0000-4000-8000-000000000401'', ''c0e70000-0000-4000-8000-000000000b01'')',
    '28000', 'Authentication is required'
);
reset role;

select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000120', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_requester_contact(''c0e70000-0000-4000-8000-000000000401'', ''c0e70000-0000-4000-8000-000000000b01'')',
    '28000', 'No coherent domain User'
);
reset role;

select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000110', true);
set local role anon;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_requester_contact(''c0e70000-0000-4000-8000-000000000401'', ''c0e70000-0000-4000-8000-000000000b01'')',
    '42501', 'permission denied'
);
reset role;

-- An authorized actor still has no direct read of Auth data or another
-- User's Profile.
select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_error('select email from auth.users', '42501', 'permission denied');
select pg_temp.assert_true(
    (select count(*) = 0 from public.user_profiles
     where user_id = 'c0e70000-0000-4000-8000-000000000201'),
    'Profile: an authorized schedule viewer still cannot read the requester''s user_profiles row'
);
reset role;

-- ===========================================================================
-- 4. Later changes are reflected; no snapshot (VN 55, 58).
-- ===========================================================================

update public.user_profiles
set display_name = 'María L.'
where user_id = 'c0e70000-0000-4000-8000-000000000201';

update auth.users
set email = 'maria.new@example.test'
where id = 'c0e70000-0000-4000-8000-000000000101';

select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.capture_contacts('after_change');
select pg_temp.capture_schedule_names('after_change');
reset role;

select pg_temp.assert_true(
    (select bool_and(requester_display_name = 'María L.' and requester_email = 'maria.new@example.test')
     from contact_snapshot
     where label = 'after_change'
       and appointment_id::text ~ '-000000000b0[1-6]$')
    and (select bool_and(requester_display_name = 'María L.')
         from schedule_names
         where label = 'after_change'
           and appointment_id::text ~ '-000000000b0[1-6]$'),
    'Changes: the new display name and email appear on active and historical Appointments'
);

update auth.users
set email_confirmed_at = null
where id = 'c0e70000-0000-4000-8000-000000000101';

select set_config('request.jwt.claim.sub', 'c0e70000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_true(
    (select count(*) = 1
            and bool_and(contact.requester_display_name = 'María L.')
            and bool_and(contact.requester_email is null)
     from public.get_clinic_appointment_requester_contact(
         'c0e70000-0000-4000-8000-000000000401', 'c0e70000-0000-4000-8000-000000000b02'
     ) as contact),
    'Unverified: an address that is no longer verified is NULL; the name remains'
);
reset role;

-- ===========================================================================
-- 5. Reads create or change nothing (VN 60).
-- ===========================================================================

select pg_temp.assert_true(
    (select baseline.communications = (select count(*) from public.transactional_communications)
            and baseline.audit_events = (select count(*) from public.medical_access_audit_events)
            and baseline.lifecycle_events = (select count(*) from public.appointment_lifecycle_events)
            and baseline.profiles = (select count(*) from public.user_profiles)
     from side_effect_baseline as baseline),
    'Side effects: no Communication, Medical Access Audit Event, Lifecycle Event, or Profile is created'
);

rollback;

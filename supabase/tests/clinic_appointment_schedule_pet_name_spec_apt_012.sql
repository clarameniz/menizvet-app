-- Regression suite for the SPEC-APT-012 Pet current-name amendment (BR-41,
-- BR-42, Verification Notes 21–26), migration
-- 20261001170000_clinic_appointment_schedule_pet_name.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions are
-- rolled back; superuser test execution is required solely to bypass
-- unrelated establishment triggers/foreign keys while loading a deliberately
-- minimal deterministic context, and to switch between impersonated Users
-- (same rationale as professional_clinics_spec_org_008.sql).
--
-- Covers:
--   * authorized Receptionist and assigned Veterinarian receive `pet_id` and
--     the Pet's current `pet_name` (VN 21);
--   * a rename through `update_pet_profile` changes `pet_name` on active and
--     historical rows and nothing else (VN 22);
--   * unchanged denial behavior: other Clinic, bare Member, ended
--     Responsibility Grant, ended Clinic Assignment, no subject, no domain
--     User, anon/public (VN 23, VN 26);
--   * exact result contract with `pet_name` as the only addition and no other
--     Pet Profile, Guardianship, or Guardian field (VN 24);
--   * same-named Pets remain distinct by `pet_id` (VN 25);
--   * unchanged row set, ordering, scheduling, current Veterinarian
--     Assignment, and pending-reschedule fields, empty schedule, function
--     attributes, function ACL, and Pet table security (VN 26).
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

-- Captured schedule results, keyed by label, in returned order. Expected rows
-- are stored under the label 'expected'.
create temporary table schedule_snapshot (
    label text not null,
    ord bigint not null,
    id uuid,
    pet_id uuid,
    pet_name text,
    requesting_user_id uuid,
    reason_for_visit text,
    guardian_notes text,
    lifecycle_state text,
    created_at timestamptz,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text,
    primary key (label, ord)
) on commit drop;

grant select, insert on schedule_snapshot to authenticated;

create function pg_temp.capture(p_label text, p_clinic_id uuid)
returns void language sql as $$
    insert into schedule_snapshot
    select p_label, schedule.ordinality, schedule.id, schedule.pet_id, schedule.pet_name,
           schedule.requesting_user_id, schedule.reason_for_visit, schedule.guardian_notes,
           schedule.lifecycle_state, schedule.created_at, schedule.current_scheduled_start_at,
           schedule.current_scheduled_end_at, schedule.current_scheduling_timezone_name,
           schedule.current_veterinarian_clinic_assignment_id, schedule.pending_reschedule_proposal_id,
           schedule.pending_reschedule_proposal_state, schedule.pending_reschedule_proposing_context,
           schedule.pending_reschedule_proposed_start_at, schedule.pending_reschedule_proposed_end_at,
           schedule.pending_reschedule_proposed_timezone_name, schedule.pending_reschedule_reason
    from public.get_clinic_appointment_schedule(p_clinic_id) with ordinality as schedule
$$;

-- Ordered rows of a snapshot, optionally without `pet_name`.
create function pg_temp.snapshot_rows(p_label text, p_include_pet_name boolean)
returns text[] language sql as $$
    select coalesce(array_agg(row(
        snapshot.id, snapshot.pet_id,
        case when p_include_pet_name then snapshot.pet_name end,
        snapshot.requesting_user_id, snapshot.reason_for_visit, snapshot.guardian_notes,
        snapshot.lifecycle_state, snapshot.created_at, snapshot.current_scheduled_start_at,
        snapshot.current_scheduled_end_at, snapshot.current_scheduling_timezone_name,
        snapshot.current_veterinarian_clinic_assignment_id, snapshot.pending_reschedule_proposal_id,
        snapshot.pending_reschedule_proposal_state, snapshot.pending_reschedule_proposing_context,
        snapshot.pending_reschedule_proposed_start_at, snapshot.pending_reschedule_proposed_end_at,
        snapshot.pending_reschedule_proposed_timezone_name, snapshot.pending_reschedule_reason
    )::text order by snapshot.ord), '{}')
    from schedule_snapshot as snapshot
    where snapshot.label = p_label
$$;

-- ===========================================================================
-- 1. Contract, attributes, ACL, and Pet table security (VN 24, VN 26).
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)
    = 'TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, '
      -- 20261107090000 (SPEC-APT-012 BR-49): the requester's current display name.
      'requester_display_name text, reason_for_visit text, '
      'guardian_notes text, lifecycle_state text, created_at timestamp with time zone, '
      'current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, '
      'current_scheduling_timezone_name text, current_schedule_revision_sequence integer, '
      'current_veterinarian_clinic_assignment_id uuid, '
      'pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, '
      'pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, '
      'pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, '
      'pending_reschedule_reason text, '
      -- 20261010090000 (SPEC-APT-012 BR-45): provenance of the relevant interval.
      'current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, '
      -- 20261022090000: the recorded reason of a CANCELLED Appointment.
      'cancellation_reason text, '
      -- 20261113090000 (SPEC-MED-010): whether clinical documentation exists.
      'has_clinical_record boolean)',
    'Contract: result is the previous 18 columns with pet_name added after pet_id and, since '
    '20261003090000 (SPEC-APT-012 BR-43), current_schedule_revision_sequence after the interval'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from pg_proc as proc, unnest(proc.proargnames) as argument_name
        where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure
          and (
              argument_name in (
                  'species', 'breed', 'sex', 'date_of_birth', 'approximate_date_of_birth',
                  'microchip_identifier', 'profile_image_reference', 'behavioral_safety_information',
                  'profile_revision'
              )
              or argument_name ~ '(species|breed|birth|microchip|image|behavio|guardianship|guardian_id|guardian_user|email|phone|contact|clinical|medical|encounter|diagnos)'
          )
          -- SPEC-APT-012 BR-48 (20261103090000): existence only, no clinical information.
          and argument_name <> 'has_clinical_record'
    ),
    'Contract: no other Pet Profile, Guardianship, Guardian, or medical field is returned (has_clinical_record is existence-only, SPEC-MED-010)'
);

select pg_temp.assert_true(
    (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
     from pg_proc as proc
     where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure),
    'Attributes: SECURITY DEFINER, STABLE, empty search_path are preserved'
);

select pg_temp.assert_true(
    has_function_privilege('authenticated', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.get_clinic_appointment_schedule(uuid)', 'EXECUTE'),
    'ACL: EXECUTE only for authenticated'
);

-- service_role receives EXECUTE through the platform's default privileges,
-- exactly as for every other client read (e.g. get_my_professional_clinics).
select pg_temp.assert_true(
    (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                      order by acl_entry.grantee::regrole::text)
     from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
     where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure
       and acl_entry.grantee <> proc.proowner)
    = array['authenticated:EXECUTE', 'service_role:EXECUTE'],
    'ACL: non-owner grantees are exactly authenticated and service_role (platform default)'
);

select pg_temp.assert_true(
    not has_table_privilege('authenticated', 'public.pets', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
    and not has_table_privilege('anon', 'public.pets', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
    and not has_column_privilege('authenticated', 'public.pets', 'name', 'SELECT')
    and not has_column_privilege('anon', 'public.pets', 'name', 'SELECT')
    and not has_table_privilege('authenticated', 'public.guardianships', 'SELECT')
    and not has_table_privilege('anon', 'public.guardianships', 'SELECT'),
    'Pet security: no client-role privilege on pets (including pets.name) or guardianships'
);

select pg_temp.assert_true(
    (select relation.relrowsecurity and not relation.relforcerowsecurity
     from pg_class as relation where relation.oid = 'public.pets'::regclass)
    and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pets'),
    'Pet security: Row Level Security still enabled on pets with no policy'
);

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures
--
-- Auth subjects 12a00000-…-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian of Luna, Luna (second Pet), and Toby
--   02 RECEPTIONIST @ A1 (Clinic)
--   03 VETERINARIAN + Profile, current Clinic Assignment @ A1
--   04 bare OrgA Membership
--   05 RECEPTIONIST @ A1 (Clinic), grant ended
--   06 VETERINARIAN + Profile, Clinic Assignment @ A1 ended
--   07 RECEPTIONIST @ A2 (Clinic)
--   08 authenticated subject without domain User
--
-- OrgA (…0301) operates A1 (…0401) and A2 (…0402, no Appointments). OrgB
-- (…0302) operates B1 (…0411).
--
-- Pets (…09NN): 01 "Luna", 02 "Luna" (a different Pet), 03 "Toby".
--
-- Appointments (…0bNN) at A1, in expected returned order (created_at, id):
--   b4 Luna#2 CANCELLED  08:00  REQUESTED revision only
--   b1 Luna   REQUESTED  09:00
--   b2 Luna   CONFIRMED  10:00  current Veterinarian Assignment, pending
--                               actionable CLINIC reschedule proposal
--   b3 Luna   COMPLETED  10:00  (created_at tie with b2; broken by id) ended
--                               Veterinarian Assignment only
--   b5 Toby   NO_SHOW    11:00
--   b6 Luna#2 CONFIRMED  12:00  no Veterinarian Assignment
-- and b7 Luna REQUESTED at B1 (must never appear in A1's schedule).
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select ('12a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '2020-01-01Z'
from generate_series(1, 8) as n;

insert into public.users (id)
select ('12a00000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 7) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select
    ('12a00000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
    ('12a00000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid
from generate_series(1, 7) as n;

insert into public.veterinary_organizations (id, display_name) values
    ('12a00000-0000-4000-8000-000000000301', 'Animalia Veterinary Group'),
    ('12a00000-0000-4000-8000-000000000302', 'VetCare Group');

insert into public.clinics (id, organization_id, is_published) values
    ('12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000301', true),
    ('12a00000-0000-4000-8000-000000000402', '12a00000-0000-4000-8000-000000000301', true),
    ('12a00000-0000-4000-8000-000000000411', '12a00000-0000-4000-8000-000000000302', true);

insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    ('12a00000-0000-4000-8000-000000000502', '12a00000-0000-4000-8000-000000000301', '12a00000-0000-4000-8000-000000000202', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000503', '12a00000-0000-4000-8000-000000000301', '12a00000-0000-4000-8000-000000000203', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000504', '12a00000-0000-4000-8000-000000000301', '12a00000-0000-4000-8000-000000000204', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000505', '12a00000-0000-4000-8000-000000000301', '12a00000-0000-4000-8000-000000000205', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000506', '12a00000-0000-4000-8000-000000000301', '12a00000-0000-4000-8000-000000000206', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000507', '12a00000-0000-4000-8000-000000000301', '12a00000-0000-4000-8000-000000000207', '2020-01-01Z');

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values
    ('12a00000-0000-4000-8000-000000000602', '12a00000-0000-4000-8000-000000000502', 'RECEPTIONIST', 'CLINIC', '12a00000-0000-4000-8000-000000000401', '2020-01-01Z', null, '12a00000-0000-4000-8000-000000000202', null),
    ('12a00000-0000-4000-8000-000000000603', '12a00000-0000-4000-8000-000000000503', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '12a00000-0000-4000-8000-000000000202', null),
    ('12a00000-0000-4000-8000-000000000605', '12a00000-0000-4000-8000-000000000505', 'RECEPTIONIST', 'CLINIC', '12a00000-0000-4000-8000-000000000401', '2020-01-01Z', '2021-01-01Z', '12a00000-0000-4000-8000-000000000202', '12a00000-0000-4000-8000-000000000202'),
    ('12a00000-0000-4000-8000-000000000606', '12a00000-0000-4000-8000-000000000506', 'VETERINARIAN', 'ORGANIZATION', null, '2020-01-01Z', null, '12a00000-0000-4000-8000-000000000202', null),
    ('12a00000-0000-4000-8000-000000000607', '12a00000-0000-4000-8000-000000000507', 'RECEPTIONIST', 'CLINIC', '12a00000-0000-4000-8000-000000000402', '2020-01-01Z', null, '12a00000-0000-4000-8000-000000000202', null);

insert into public.veterinarian_professional_profiles (id, user_id) values
    ('12a00000-0000-4000-8000-000000000703', '12a00000-0000-4000-8000-000000000203'),
    ('12a00000-0000-4000-8000-000000000706', '12a00000-0000-4000-8000-000000000206');

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    ('12a00000-0000-4000-8000-000000000803', '12a00000-0000-4000-8000-000000000703', '12a00000-0000-4000-8000-000000000503', '12a00000-0000-4000-8000-000000000401', '2020-01-01Z', null),
    ('12a00000-0000-4000-8000-000000000806', '12a00000-0000-4000-8000-000000000706', '12a00000-0000-4000-8000-000000000506', '12a00000-0000-4000-8000-000000000401', '2020-01-01Z', '2021-01-01Z');

insert into public.pets (id, name, species, created_at) values
    ('12a00000-0000-4000-8000-000000000901', 'Luna', 'Dog', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000902', 'Luna', 'Cat', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000903', 'Toby', 'Dog', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start) values
    ('12a00000-0000-4000-8000-000000000a01', '12a00000-0000-4000-8000-000000000201', '12a00000-0000-4000-8000-000000000901', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000a02', '12a00000-0000-4000-8000-000000000201', '12a00000-0000-4000-8000-000000000902', '2020-01-01Z'),
    ('12a00000-0000-4000-8000-000000000a03', '12a00000-0000-4000-8000-000000000201', '12a00000-0000-4000-8000-000000000903', '2020-01-01Z');

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit, guardian_notes, lifecycle_state, created_at
) values
    ('12a00000-0000-4000-8000-000000000b01', '12a00000-0000-4000-8000-000000000901', '12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000201', 'Vaccination', 'Shy with strangers', 'REQUESTED', '2026-09-01T09:00:00Z'),
    ('12a00000-0000-4000-8000-000000000b02', '12a00000-0000-4000-8000-000000000901', '12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000201', 'Limping', null, 'CONFIRMED', '2026-09-01T10:00:00Z'),
    ('12a00000-0000-4000-8000-000000000b03', '12a00000-0000-4000-8000-000000000901', '12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000201', 'Check-up', null, 'COMPLETED', '2026-09-01T10:00:00Z'),
    ('12a00000-0000-4000-8000-000000000b04', '12a00000-0000-4000-8000-000000000902', '12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000201', 'Dental', null, 'CANCELLED', '2026-09-01T08:00:00Z'),
    ('12a00000-0000-4000-8000-000000000b05', '12a00000-0000-4000-8000-000000000903', '12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000201', 'Skin rash', null, 'NO_SHOW', '2026-09-01T11:00:00Z'),
    ('12a00000-0000-4000-8000-000000000b06', '12a00000-0000-4000-8000-000000000902', '12a00000-0000-4000-8000-000000000401', '12a00000-0000-4000-8000-000000000201', 'Follow-up', null, 'CONFIRMED', '2026-09-01T12:00:00Z'),
    ('12a00000-0000-4000-8000-000000000b07', '12a00000-0000-4000-8000-000000000901', '12a00000-0000-4000-8000-000000000411', '12a00000-0000-4000-8000-000000000201', 'Second opinion', null, 'REQUESTED', '2026-09-01T09:30:00Z');

insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name,
    established_by_user_id, created_at
) values
    ('12a00000-0000-4000-8000-000000000c11', '12a00000-0000-4000-8000-000000000b01', 1, 'REQUESTED', '2035-03-01T09:00:00Z', '2035-03-01T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T09:00:00Z'),
    ('12a00000-0000-4000-8000-000000000c21', '12a00000-0000-4000-8000-000000000b02', 1, 'REQUESTED', '2035-03-02T09:00:00Z', '2035-03-02T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T10:00:00Z'),
    ('12a00000-0000-4000-8000-000000000c22', '12a00000-0000-4000-8000-000000000b02', 2, 'CONFIRMED', '2035-03-02T10:00:00Z', '2035-03-02T10:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000202', '2026-09-01T10:05:00Z'),
    ('12a00000-0000-4000-8000-000000000c31', '12a00000-0000-4000-8000-000000000b03', 1, 'REQUESTED', '2026-09-05T09:00:00Z', '2026-09-05T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T10:00:00Z'),
    ('12a00000-0000-4000-8000-000000000c32', '12a00000-0000-4000-8000-000000000b03', 2, 'CONFIRMED', '2026-09-05T11:00:00Z', '2026-09-05T11:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000202', '2026-09-01T10:05:00Z'),
    ('12a00000-0000-4000-8000-000000000c41', '12a00000-0000-4000-8000-000000000b04', 1, 'REQUESTED', '2035-03-04T09:00:00Z', '2035-03-04T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T08:00:00Z'),
    ('12a00000-0000-4000-8000-000000000c51', '12a00000-0000-4000-8000-000000000b05', 1, 'REQUESTED', '2026-09-06T09:00:00Z', '2026-09-06T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T11:00:00Z'),
    ('12a00000-0000-4000-8000-000000000c52', '12a00000-0000-4000-8000-000000000b05', 2, 'CONFIRMED', '2026-09-06T09:00:00Z', '2026-09-06T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000202', '2026-09-01T11:05:00Z'),
    ('12a00000-0000-4000-8000-000000000c61', '12a00000-0000-4000-8000-000000000b06', 1, 'REQUESTED', '2035-03-06T09:00:00Z', '2035-03-06T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T12:00:00Z'),
    ('12a00000-0000-4000-8000-000000000c62', '12a00000-0000-4000-8000-000000000b06', 2, 'CONFIRMED', '2035-03-06T09:00:00Z', '2035-03-06T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000202', '2026-09-01T12:05:00Z'),
    ('12a00000-0000-4000-8000-000000000c71', '12a00000-0000-4000-8000-000000000b07', 1, 'REQUESTED', '2035-03-07T09:00:00Z', '2035-03-07T09:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000201', '2026-09-01T09:30:00Z');

insert into public.appointment_veterinarian_assignments (
    id, appointment_id, veterinarian_clinic_assignment_id, effective_start, effective_end, assigned_by_user_id
) values
    ('12a00000-0000-4000-8000-000000000d21', '12a00000-0000-4000-8000-000000000b02', '12a00000-0000-4000-8000-000000000803', '2026-09-01T10:10:00Z', null, '12a00000-0000-4000-8000-000000000202'),
    ('12a00000-0000-4000-8000-000000000d31', '12a00000-0000-4000-8000-000000000b03', '12a00000-0000-4000-8000-000000000803', '2026-09-01T10:10:00Z', '2026-09-02T10:00:00Z', '12a00000-0000-4000-8000-000000000202');

insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
) values (
    '12a00000-0000-4000-8000-000000000e21', '12a00000-0000-4000-8000-000000000b02',
    '12a00000-0000-4000-8000-000000000c22', 'CONFIRMED', '2035-03-09T10:00:00Z', '2035-03-09T10:30:00Z',
    'Europe/Madrid', 'CLINIC', '12a00000-0000-4000-8000-000000000202', 'Veterinarian unavailable',
    '2026-09-01T13:00:00Z'
);

set local session_replication_role = origin;

-- Expected A1 schedule, transcribed from the fixtures above.
insert into schedule_snapshot values
    ('expected', 1, '12a00000-0000-4000-8000-000000000b04', '12a00000-0000-4000-8000-000000000902', 'Luna', '12a00000-0000-4000-8000-000000000201', 'Dental', null, 'CANCELLED', '2026-09-01T08:00:00Z', '2035-03-04T09:00:00Z', '2035-03-04T09:30:00Z', 'Europe/Madrid', null, null, null, null, null, null, null, null),
    ('expected', 2, '12a00000-0000-4000-8000-000000000b01', '12a00000-0000-4000-8000-000000000901', 'Luna', '12a00000-0000-4000-8000-000000000201', 'Vaccination', 'Shy with strangers', 'REQUESTED', '2026-09-01T09:00:00Z', '2035-03-01T09:00:00Z', '2035-03-01T09:30:00Z', 'Europe/Madrid', null, null, null, null, null, null, null, null),
    ('expected', 3, '12a00000-0000-4000-8000-000000000b02', '12a00000-0000-4000-8000-000000000901', 'Luna', '12a00000-0000-4000-8000-000000000201', 'Limping', null, 'CONFIRMED', '2026-09-01T10:00:00Z', '2035-03-02T10:00:00Z', '2035-03-02T10:30:00Z', 'Europe/Madrid', '12a00000-0000-4000-8000-000000000803', '12a00000-0000-4000-8000-000000000e21', 'PENDING', 'CLINIC', '2035-03-09T10:00:00Z', '2035-03-09T10:30:00Z', 'Europe/Madrid', 'Veterinarian unavailable'),
    ('expected', 4, '12a00000-0000-4000-8000-000000000b03', '12a00000-0000-4000-8000-000000000901', 'Luna', '12a00000-0000-4000-8000-000000000201', 'Check-up', null, 'COMPLETED', '2026-09-01T10:00:00Z', '2026-09-05T11:00:00Z', '2026-09-05T11:30:00Z', 'Europe/Madrid', null, null, null, null, null, null, null, null),
    ('expected', 5, '12a00000-0000-4000-8000-000000000b05', '12a00000-0000-4000-8000-000000000903', 'Toby', '12a00000-0000-4000-8000-000000000201', 'Skin rash', null, 'NO_SHOW', '2026-09-01T11:00:00Z', '2026-09-06T09:00:00Z', '2026-09-06T09:30:00Z', 'Europe/Madrid', null, null, null, null, null, null, null, null),
    ('expected', 6, '12a00000-0000-4000-8000-000000000b06', '12a00000-0000-4000-8000-000000000902', 'Luna', '12a00000-0000-4000-8000-000000000201', 'Follow-up', null, 'CONFIRMED', '2026-09-01T12:00:00Z', '2035-03-06T09:00:00Z', '2035-03-06T09:30:00Z', 'Europe/Madrid', null, null, null, null, null, null, null, null);

-- ===========================================================================
-- 2. Authorized reads (VN 21, VN 25, VN 26).
-- ===========================================================================

-- Clinic-scoped RECEPTIONIST @ A1.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000102', true);
set local role authenticated;
select pg_temp.capture('receptionist', '12a00000-0000-4000-8000-000000000401');
reset role;

select pg_temp.assert_true(
    pg_temp.snapshot_rows('receptionist', true) = pg_temp.snapshot_rows('expected', true),
    'Receptionist: every A1 row, in (created_at, id) order, with the correct pet_id, current pet_name, '
    'scheduling, current Veterinarian Assignment, and pending-reschedule fields'
);

select pg_temp.assert_true(
    not exists (select 1 from schedule_snapshot where label = 'receptionist' and pet_name is null)
    and not exists (
        select 1 from schedule_snapshot as snapshot
        join public.pets as pet on pet.id = snapshot.pet_id
        where snapshot.label = 'receptionist' and snapshot.pet_name is distinct from pet.name
    ),
    'Receptionist: pet_name is non-null and equals the current pets.name of each row''s pet_id'
);

select pg_temp.assert_true(
    (select array_agg(id order by ord) from schedule_snapshot where label = 'receptionist')
    = (select array_agg(appointment.id order by appointment.created_at, appointment.id)
       from public.appointments as appointment
       where appointment.clinic_id = '12a00000-0000-4000-8000-000000000401')
    and not exists (
        select 1 from schedule_snapshot
        where label = 'receptionist' and id = '12a00000-0000-4000-8000-000000000b07'
    ),
    'Row set and order: exactly A1''s Appointments ordered by (created_at, id); the B1 Appointment is absent'
);

select pg_temp.assert_true(
    (select count(distinct pet_id) = 2 and bool_and(pet_name = 'Luna')
     from schedule_snapshot where label = 'receptionist' and pet_name = 'Luna')
    and (select count(*) = 5 from schedule_snapshot where label = 'receptionist' and pet_name = 'Luna'),
    'Same-named Pets: two distinct pet_id values share pet_name ''Luna'' without merging Appointments'
);

-- VETERINARIAN with a current Clinic Assignment @ A1.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000103', true);
set local role authenticated;
select pg_temp.capture('veterinarian', '12a00000-0000-4000-8000-000000000401');
reset role;

select pg_temp.assert_true(
    pg_temp.snapshot_rows('veterinarian', true) = pg_temp.snapshot_rows('expected', true),
    'Assigned Veterinarian: identical schedule, including pet_id and pet_name'
);

-- Empty Clinic schedule (RECEPTIONIST @ A2).
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000107', true);
set local role authenticated;
select pg_temp.assert_true(
    (select count(*) = 0 from public.get_clinic_appointment_schedule('12a00000-0000-4000-8000-000000000402')),
    'Empty Clinic schedule succeeds with zero rows'
);
reset role;

-- ===========================================================================
-- 3. Denied callers receive no Pet name (VN 23, VN 26).
-- ===========================================================================

-- RECEPTIONIST @ A2 reading A1.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000107', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

-- Bare Member, ended RECEPTIONIST grant, ended Veterinarian Clinic Assignment, Guardian of the Pets.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000104', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000105', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000106', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000101', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

-- Nonexistent Clinic: same denial as an unauthorized Clinic.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000102', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-0000000004ff'')',
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

-- No authenticated subject; subject without a coherent domain User.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '28000', 'Authentication is required'
);
reset role;

select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000108', true);
set local role authenticated;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '28000', 'No coherent domain User'
);
reset role;

-- anon cannot execute.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000102', true);
set local role anon;
select pg_temp.assert_error(
    'select * from public.get_clinic_appointment_schedule(''12a00000-0000-4000-8000-000000000401'')',
    '42501', 'permission denied'
);
reset role;

-- No direct Pet read for an authorized schedule viewer.
select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000102', true);
set local role authenticated;
select pg_temp.assert_error('select name from public.pets', '42501', 'permission denied');
reset role;

-- ===========================================================================
-- 4. Pet rename through the supported Pet Profile operation (VN 22).
-- ===========================================================================

select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000101', true);
set local role authenticated;
select pg_temp.assert_true(
    public.update_pet_profile(
        '12a00000-0000-4000-8000-000000000901', 0, 'Luna María', 'Dog',
        null, null, null, null, null, null, null
    ) = 1,
    'Rename: current Guardian renames Luna through update_pet_profile'
);
reset role;

select set_config('request.jwt.claim.sub', '12a00000-0000-4000-8000-000000000102', true);
set local role authenticated;
select pg_temp.capture('after_rename', '12a00000-0000-4000-8000-000000000401');
reset role;

select pg_temp.assert_true(
    (select array_agg(pet_name order by ord) from schedule_snapshot where label = 'after_rename')
    = array['Luna', 'Luna María', 'Luna María', 'Luna María', 'Toby', 'Luna'],
    'Rename: REQUESTED, CONFIRMED, and COMPLETED rows of the renamed Pet show the new name; '
    'the other Pet named Luna and Toby are unaffected'
);

select pg_temp.assert_true(
    pg_temp.snapshot_rows('after_rename', false) = pg_temp.snapshot_rows('receptionist', false),
    'Rename: ids, pet_ids, lifecycle states, scheduling, Assignment, proposal fields, and order are unchanged'
);

select pg_temp.assert_true(
    (select count(*) = 11 from public.appointment_schedule_revisions as revision
     where revision.appointment_id::text like '12a00000-0000-4000-8000-000000000b%')
    and (select count(*) = 0 from public.appointment_lifecycle_events as lifecycle_event
         where lifecycle_event.appointment_id::text like '12a00000-0000-4000-8000-000000000b%'),
    'Rename: no scheduling revision or lifecycle event is created for any fixture Appointment'
);

rollback;

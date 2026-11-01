-- Professional calendar reads — Phase 1 (SPEC-APT-012 §14, BR-51–BR-55,
-- Verification Notes 62–68), migration
-- 20261108090000_clinic_appointment_read_and_month_counts.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deliberately minimal deterministic
-- context and to switch between impersonated Users (same rationale as
-- appointment_requester_contact_spec_apt_012_id_006.sql).
--
-- Covers:
--   * contracts, attributes and ACLs of the two reads and the two internal
--     helpers; get_clinic_appointment_schedule unchanged;
--   * get_clinic_appointment equals the schedule row column for column, for
--     every A1 Appointment and every authorized actor;
--   * uniform 42501 for unauthorized actors and foreign/unknown targets,
--     28000 without subject or domain User, anon denied;
--   * month counts: counted states, latest revision only, pending proposals
--     never add a date, establishment timezone, midnight, both DST
--     transitions, month lengths, year change, empty month, invalid input,
--     session timezone independence;
--   * each day's count equals the shared day definition (planned day read);
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

-- The uniform single-Appointment denial: exactly this SQLSTATE and message,
-- no hint, no detail.
create function pg_temp.assert_appointment_denied(p_clinic_id text, p_appointment_id text)
returns void language plpgsql as $$
declare
    error_hint text;
    error_detail text;
begin
    begin
        execute format(
            'select * from public.get_clinic_appointment(%s, %s)',
            coalesce(quote_literal(p_clinic_id) || '::uuid', 'null::uuid'),
            coalesce(quote_literal(p_appointment_id) || '::uuid', 'null::uuid')
        );
    exception when others then
        get stacked diagnostics error_hint = pg_exception_hint, error_detail = pg_exception_detail;
        if sqlstate = '42501'
           and sqlerrm = 'Clinic Appointment unavailable'
           and coalesce(error_hint, '') = ''
           and coalesce(error_detail, '') = '' then
            return;
        end if;
        raise exception 'Expected uniform denial for (%, %), received %: % (hint %)',
            p_clinic_id, p_appointment_id, sqlstate, sqlerrm, error_hint;
    end;
    raise exception 'Expected denial for (%, %), but it succeeded', p_clinic_id, p_appointment_id;
end;
$$;

create function pg_temp.id(p_kind text, p_n integer)
returns uuid language sql immutable as $$
    select ('c0e80000-0000-4000-8000-000000000' || p_kind || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.a1() returns uuid language sql immutable as $$ select pg_temp.id('4', 1) $$;

-- Month counts of A1 as one text value, e.g. {"(2035-03-10,1)",…}.
create function pg_temp.counts(p_year integer, p_month integer)
returns text[] language sql as $$
    select coalesce(array_agg(row(month_count.day, month_count.appointment_count)::text
                              order by month_count.day), '{}')
    from public.get_clinic_appointment_month_counts(pg_temp.a1(), p_year, p_month) as month_count
$$;

create temporary table read_snapshot (
    label text not null,
    appointment_id uuid not null,
    row_json jsonb not null,
    row_count integer not null,
    primary key (label, appointment_id)
) on commit drop;

grant select, insert on read_snapshot to authenticated;

-- Every A1 Appointment as read through get_clinic_appointment and as found in
-- the schedule, for the impersonated actor.
create function pg_temp.capture_reads(p_label text)
returns void language plpgsql as $$
declare
    appointment_id uuid;
begin
    for appointment_id in
        select appointment.id from public.get_clinic_appointment_schedule(pg_temp.a1()) as appointment
    loop
        insert into read_snapshot
        select p_label || ':single', appointment_id,
               coalesce(jsonb_agg(to_jsonb(single_row)), '[]'), count(*)
        from public.get_clinic_appointment(pg_temp.a1(), appointment_id) as single_row;
    end loop;
    insert into read_snapshot
    select p_label || ':schedule', schedule_row.id, jsonb_build_array(to_jsonb(schedule_row)), 1
    from public.get_clinic_appointment_schedule(pg_temp.a1()) as schedule_row;
end;
$$;

-- ===========================================================================
-- 1. Contracts, attributes, ACLs.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment(uuid, uuid)'::regprocedure)
    = pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure),
    'Contract: get_clinic_appointment returns exactly the schedule row columns (BR-51)'
);

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_month_counts(uuid, integer, integer)'::regprocedure)
    = 'TABLE(day date, appointment_count integer)',
    'Contract: month counts return only day and appointment_count'
);

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""'])
     from pg_proc as proc
     where proc.oid in (
         'public.get_clinic_appointment(uuid, uuid)'::regprocedure,
         'public.get_clinic_appointment_month_counts(uuid, integer, integer)'::regprocedure,
         'public.project_clinic_appointments(uuid, uuid[])'::regprocedure,
         'public.clinic_calendar_appointments(uuid, date, date)'::regprocedure
     )),
    'Attributes: SECURITY DEFINER, STABLE, empty search_path'
);

select pg_temp.assert_true(
    (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                      order by acl_entry.grantee::regrole::text)
     from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
     where proc.oid = signature::regprocedure
       and acl_entry.grantee <> proc.proowner)
    = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and not has_function_privilege('anon', signature, 'EXECUTE')
    and not has_function_privilege('public', signature, 'EXECUTE'),
    'ACL: ' || signature || ' is executable only by authenticated (and service_role)'
)
from unnest(array[
    'public.get_clinic_appointment(uuid, uuid)',
    'public.get_clinic_appointment_month_counts(uuid, integer, integer)'
]) as signature;

select pg_temp.assert_true(
    not has_function_privilege('authenticated', signature, 'EXECUTE')
    and not has_function_privilege('anon', signature, 'EXECUTE')
    and not has_function_privilege('public', signature, 'EXECUTE'),
    'ACL: internal helper ' || signature || ' is not executable by clients'
)
from unnest(array[
    'public.project_clinic_appointments(uuid, uuid[])',
    'public.clinic_calendar_appointments(uuid, date, date)'
]) as signature;

-- The installed clients' read keeps its signature and grants.
select pg_temp.assert_true(
    (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                      order by acl_entry.grantee::regrole::text)
     from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
     where proc.oid = 'public.get_clinic_appointment_schedule(uuid)'::regprocedure
       and acl_entry.grantee <> proc.proowner)
    = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure) like 'TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, %has_clinical_record boolean)'
    and (select count(*) = 1 from pg_proc where proname = 'get_clinic_appointment_schedule'),
    'Compatibility: get_clinic_appointment_schedule(uuid) keeps its contract and grants (VN 68)'
);

-- ===========================================================================
-- Fixtures
--
-- Auth subjects …0001NN, domain Users …0002NN:
--   01 Guardian and requester           06 OWNER (Organization) OrgA
--   07 ADMINISTRATOR (Organization)     08 ADMINISTRATOR (Clinic A1)
--   09 RECEPTIONIST (Organization)      10 RECEPTIONIST (Clinic A1)
--   11 VETERINARIAN, Assignment @ A1    12 VETERINARIAN, Assignment @ A2 only
--   13 VETERINARIAN, Assignment @ A1 ended
--   14 RECEPTIONIST (Clinic A2)         15 RECEPTIONIST (Organization), Membership ended
--   16 RECEPTIONIST (Clinic A1), Grant ended
--   17 ADMINISTRATOR (Organization) OrgB   18 bare OrgA Member
--   20 authenticated subject without domain User
-- OrgA (…0301) operates A1 (…0401, Europe/Madrid) and A2 (…0402); OrgB (…0302)
-- operates B1 (…0411).
--
-- A1 Appointments (local times in the establishment timezone):
--   d01 REQUESTED   2035-03-10 10:00 Madrid
--   d02 CONFIRMED   requested 2035-03-11 10:00, confirmed 2035-03-12 09:00
--   d03 COMPLETED   2035-03-12 12:00, with a Clinical Record Entry
--   d04 CANCELLED   2035-03-12 13:00, Clinic reason
--   d05 NO_SHOW     2035-03-13 10:00
--   d06 EXPIRED     2035-03-13 11:00
--   d07 REQUESTED   2026-01-15 10:00 — past, expiry not materialized
--   d08 CONFIRMED   2035-03-14 10:00, pending Clinic reschedule to 2035-03-20
--   d09 REQUESTED   2035-03-15 10:00, pending Clinic alternative to 2035-03-21
--   d10 CONFIRMED   2035-03-16 23:30 America/New_York (= 03-17 04:30 Madrid)
--   d11 CONFIRMED   2035-03-25 00:30 Madrid, DST spring day (= 03-24 23:30Z)
--   d12 CONFIRMED   2035-03-31 23:30 Madrid (= 21:30Z)
--   d13 CONFIRMED   2035-04-01 00:30 Madrid (= 03-31 22:30Z)
--   d14 CONFIRMED   2035-10-28 00:30 Madrid +02 (= 10-27 22:30Z), DST autumn day
--   d15 CONFIRMED   2035-10-28 23:59 Madrid +01 (= 22:59Z)
--   d16 CONFIRMED   2035-12-31 23:30 Madrid (= 22:30Z)
--   d17 CONFIRMED   2036-01-01 00:30 Madrid (= 2035-12-31 23:30Z)
--   d18 REQUESTED   2036-02-29 10:00 Madrid (leap day)
-- d20 REQUESTED 2035-03-12 at A2; d21 REQUESTED 2035-03-12 at B1.
-- ===========================================================================

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id('1', n), 'calendar' || n || '@example.test', '2020-01-01Z'
from generate_series(1, 20) as n
where n <> 19;

insert into public.users (id)
select pg_temp.id('2', n) from generate_series(1, 18) as n;

insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id('2', n), pg_temp.id('1', n) from generate_series(1, 18) as n;

insert into public.user_profiles (user_id, display_name)
values (pg_temp.id('2', 1), 'Marta Ruiz');

insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id('3', 1), 'Animalia Veterinary Group'),
    (pg_temp.id('3', 2), 'VetCare Group');

insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes) values
    (pg_temp.id('4', 1), pg_temp.id('3', 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
    (pg_temp.id('4', 2), pg_temp.id('3', 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
    (pg_temp.id('4', 11), pg_temp.id('3', 2), true, '2020-01-01Z', 'Europe/Madrid', 30);

insert into public.organization_memberships (
    id, organization_id, user_id, effective_start, effective_end, ended_by_user_id
)
select pg_temp.id('5', n),
       case when n = 17 then pg_temp.id('3', 2) else pg_temp.id('3', 1) end,
       pg_temp.id('2', n),
       '2020-01-01Z',
       case when n = 15 then '2021-01-01Z'::timestamptz end,
       case when n = 15 then pg_temp.id('2', 6) end
from generate_series(6, 18) as n;

insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
)
select pg_temp.id('6', grant_row.n), pg_temp.id('5', grant_row.n),
       grant_row.responsibility, grant_row.scope_type, grant_row.clinic_id,
       '2020-01-01Z', grant_row.effective_end::timestamptz, pg_temp.id('2', 6),
       case when grant_row.effective_end is not null then pg_temp.id('2', 6) end
from (values
    (6,  'OWNER',         'ORGANIZATION', null::uuid,         null),
    (7,  'ADMINISTRATOR', 'ORGANIZATION', null,               null),
    (8,  'ADMINISTRATOR', 'CLINIC',       pg_temp.id('4', 1), null),
    (9,  'RECEPTIONIST',  'ORGANIZATION', null,               null),
    (10, 'RECEPTIONIST',  'CLINIC',       pg_temp.id('4', 1), null),
    (11, 'VETERINARIAN',  'ORGANIZATION', null,               null),
    (12, 'VETERINARIAN',  'ORGANIZATION', null,               null),
    (13, 'VETERINARIAN',  'ORGANIZATION', null,               null),
    (14, 'RECEPTIONIST',  'CLINIC',       pg_temp.id('4', 2), null),
    (15, 'RECEPTIONIST',  'ORGANIZATION', null,               null),
    (16, 'RECEPTIONIST',  'CLINIC',       pg_temp.id('4', 1), '2021-01-01Z'),
    (17, 'ADMINISTRATOR', 'ORGANIZATION', null,               null)
) as grant_row (n, responsibility, scope_type, clinic_id, effective_end);

insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id('7', n), pg_temp.id('2', n) from generate_series(11, 13) as n;

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values
    (pg_temp.id('8', 11), pg_temp.id('7', 11), pg_temp.id('5', 11), pg_temp.id('4', 1), '2020-01-01Z', null),
    (pg_temp.id('8', 12), pg_temp.id('7', 12), pg_temp.id('5', 12), pg_temp.id('4', 2), '2020-01-01Z', null),
    (pg_temp.id('8', 13), pg_temp.id('7', 13), pg_temp.id('5', 13), pg_temp.id('4', 1), '2020-01-01Z', '2021-01-01Z');

insert into public.pets (id, name, species, created_at)
values (pg_temp.id('9', 1), 'Luna', 'Dog', '2020-01-01Z');

insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end)
values (pg_temp.id('a', 1), pg_temp.id('2', 1), pg_temp.id('9', 1), '2020-01-01Z', null);

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at
)
select pg_temp.id('d', fixture.n), pg_temp.id('9', 1), fixture.clinic_id, pg_temp.id('2', 1),
       'Check-up', fixture.state,
       '2026-01-01T08:00:00Z'::timestamptz + make_interval(mins => fixture.n)
from (values
    (1, 'REQUESTED', pg_temp.id('4', 1)), (2, 'CONFIRMED', pg_temp.id('4', 1)),
    (3, 'COMPLETED', pg_temp.id('4', 1)), (4, 'CANCELLED', pg_temp.id('4', 1)),
    (5, 'NO_SHOW', pg_temp.id('4', 1)),   (6, 'EXPIRED', pg_temp.id('4', 1)),
    (7, 'REQUESTED', pg_temp.id('4', 1)), (8, 'CONFIRMED', pg_temp.id('4', 1)),
    (9, 'REQUESTED', pg_temp.id('4', 1)), (10, 'CONFIRMED', pg_temp.id('4', 1)),
    (11, 'CONFIRMED', pg_temp.id('4', 1)), (12, 'CONFIRMED', pg_temp.id('4', 1)),
    (13, 'CONFIRMED', pg_temp.id('4', 1)), (14, 'CONFIRMED', pg_temp.id('4', 1)),
    (15, 'CONFIRMED', pg_temp.id('4', 1)), (16, 'CONFIRMED', pg_temp.id('4', 1)),
    (17, 'CONFIRMED', pg_temp.id('4', 1)), (18, 'REQUESTED', pg_temp.id('4', 1)),
    (20, 'REQUESTED', pg_temp.id('4', 2)), (21, 'REQUESTED', pg_temp.id('4', 11))
) as fixture (n, state, clinic_id);

-- Schedule Revisions. Starts are given as civil time in the revision's own
-- timezone; every interval lasts 30 minutes. Terminal and CONFIRMED
-- Appointments carry a CONFIRMED latest revision, REQUESTED ones a REQUESTED
-- one; d02 also keeps its superseded requested time.
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
)
select pg_temp.id('d', revision_row.n), revision_row.sequence_number, revision_row.context,
       revision_row.local_start::timestamp at time zone revision_row.timezone_name,
       (revision_row.local_start::timestamp at time zone revision_row.timezone_name) + interval '30 minutes',
       revision_row.timezone_name, pg_temp.id('2', 1), null,
       '2026-01-01T09:00:00Z'::timestamptz + make_interval(mins => revision_row.n * 10 + revision_row.sequence_number)
from (values
    (1,  1, 'REQUESTED', '2035-03-10 10:00', 'Europe/Madrid'),
    (2,  1, 'REQUESTED', '2035-03-11 10:00', 'Europe/Madrid'),
    (2,  2, 'CONFIRMED', '2035-03-12 09:00', 'Europe/Madrid'),
    (3,  1, 'CONFIRMED', '2035-03-12 12:00', 'Europe/Madrid'),
    (4,  1, 'CONFIRMED', '2035-03-12 13:00', 'Europe/Madrid'),
    (5,  1, 'CONFIRMED', '2035-03-13 10:00', 'Europe/Madrid'),
    (6,  1, 'REQUESTED', '2035-03-13 11:00', 'Europe/Madrid'),
    (7,  1, 'REQUESTED', '2026-01-15 10:00', 'Europe/Madrid'),
    (8,  1, 'CONFIRMED', '2035-03-14 10:00', 'Europe/Madrid'),
    (9,  1, 'REQUESTED', '2035-03-15 10:00', 'Europe/Madrid'),
    (10, 1, 'CONFIRMED', '2035-03-16 23:30', 'America/New_York'),
    (11, 1, 'CONFIRMED', '2035-03-25 00:30', 'Europe/Madrid'),
    (12, 1, 'CONFIRMED', '2035-03-31 23:30', 'Europe/Madrid'),
    (13, 1, 'CONFIRMED', '2035-04-01 00:30', 'Europe/Madrid'),
    (15, 1, 'CONFIRMED', '2035-10-28 23:59', 'Europe/Madrid'),
    (16, 1, 'CONFIRMED', '2035-12-31 23:30', 'Europe/Madrid'),
    (17, 1, 'CONFIRMED', '2036-01-01 00:30', 'Europe/Madrid'),
    (18, 1, 'REQUESTED', '2036-02-29 10:00', 'Europe/Madrid'),
    (20, 1, 'REQUESTED', '2035-03-12 10:00', 'Europe/Madrid'),
    (21, 1, 'REQUESTED', '2035-03-12 10:00', 'Europe/Madrid')
) as revision_row (n, sequence_number, context, local_start, timezone_name);

-- d14: 00:30 on the autumn transition day is unambiguous (+02), so it is given
-- as an instant to pin it.
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
) values (pg_temp.id('d', 14), 1, 'CONFIRMED', '2035-10-27T22:30:00Z', '2035-10-27T23:00:00Z',
          'Europe/Madrid', pg_temp.id('2', 1), null, '2026-01-01T12:00:00Z');

-- Pending Clinic proposals on d08 (confirmed reschedule) and d09 (alternative
-- time for the request), both onto other dates.
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
)
select pg_temp.id('e', proposal_row.n), pg_temp.id('d', proposal_row.n), revision.id, revision.revision_context,
       proposal_row.proposed_start::timestamptz, proposal_row.proposed_start::timestamptz + interval '30 minutes',
       'Europe/Madrid', 'CLINIC', pg_temp.id('2', 6), 'Clinic needs to move it', '2026-02-01Z'
from (values
    (8, '2035-03-20T09:00:00Z'),
    (9, '2035-03-21T09:00:00Z')
) as proposal_row (n, proposed_start)
join public.appointment_schedule_revisions as revision
  on revision.appointment_id = pg_temp.id('d', proposal_row.n) and revision.revision_sequence = 1;

-- d04's Clinic cancellation reason and d03's Clinical Record Entry (projection
-- parity for cancellation_reason and has_clinical_record).
insert into public.appointment_lifecycle_events (
    appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
) values (pg_temp.id('d', 4), 'CONFIRMED', 'CANCELLED', pg_temp.id('2', 6), 'CLINIC',
          'Clinic closed that day', '2026-03-01Z', '2026-03-01Z');

insert into public.clinical_record_entries (
    appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at,
    category, clinical_content, creation_idempotency_key, creation_request_digest
) values (pg_temp.id('d', 3), pg_temp.id('2', 11), pg_temp.id('8', 11), '2035-03-12T11:05:00Z',
          'CLINICAL_NOTE', 'Fixture note', gen_random_uuid(), sha256(gen_random_uuid()::text::bytea));

set local session_replication_role = origin;

create temporary table side_effect_baseline on commit drop as
select
    (select count(*) from public.transactional_communications) as communications,
    (select count(*) from public.medical_access_audit_events) as audit_events,
    (select count(*) from public.appointment_lifecycle_events) as lifecycle_events,
    (select count(*) from public.appointment_schedule_revisions) as revisions,
    (select count(*) from public.appointment_reschedule_proposals) as proposals;

-- ===========================================================================
-- 2. Single read = schedule row, for every authorized actor (VN 62, 63).
-- ===========================================================================

do $$
declare
    subject_suffix text;
begin
    foreach subject_suffix in array array['06', '07', '08', '09', '10', '11'] loop
        perform set_config(
            'request.jwt.claim.sub', 'c0e80000-0000-4000-8000-0000000001' || subject_suffix, true
        );
        set local role authenticated;
        perform pg_temp.capture_reads('actor_' || subject_suffix);
        reset role;
    end loop;
end;
$$;

select pg_temp.assert_true(
    (select count(*) = 18 and bool_and(single_read.row_count = 1)
            and bool_and(single_read.row_json = schedule_read.row_json)
     from read_snapshot as single_read
     join read_snapshot as schedule_read
       on schedule_read.label = 'actor_' || suffix || ':schedule'
      and schedule_read.appointment_id = single_read.appointment_id
     where single_read.label = 'actor_' || suffix || ':single')
    and (select count(*) = 18 from read_snapshot where label = 'actor_' || suffix || ':schedule'),
    'Single read: actor ' || suffix || ' reads each of the 18 A1 Appointments as exactly one row '
    'equal, column for column, to its schedule row'
)
from unnest(array['06', '07', '08', '09', '10', '11']) as suffix;

-- The parity covers the interesting projections, not only plain rows.
select pg_temp.assert_true(
    (select (row_json -> 0 ->> 'pending_reschedule_proposal_id') is not null
            and (row_json -> 0 ->> 'pending_reschedule_proposing_context') = 'CLINIC'
     from read_snapshot where label = 'actor_10:single' and appointment_id = pg_temp.id('d', 8))
    and (select (row_json -> 0 ->> 'pending_reschedule_proposal_id') is not null
         from read_snapshot where label = 'actor_10:single' and appointment_id = pg_temp.id('d', 9))
    and (select row_json -> 0 ->> 'cancellation_reason' = 'Clinic closed that day'
         from read_snapshot where label = 'actor_10:single' and appointment_id = pg_temp.id('d', 4))
    and (select (row_json -> 0 ->> 'has_clinical_record')::boolean
         from read_snapshot where label = 'actor_10:single' and appointment_id = pg_temp.id('d', 3))
    and (select (row_json -> 0 ->> 'current_schedule_revision_sequence')::integer = 2
                and row_json -> 0 ->> 'requester_display_name' = 'Marta Ruiz'
         from read_snapshot where label = 'actor_10:single' and appointment_id = pg_temp.id('d', 2)),
    'Single read: pending proposals of both workflows, cancellation reason, clinical record flag, '
    'latest revision and requester name are projected'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from read_snapshot, jsonb_object_keys(row_json -> 0) as column_name
        where label like '%:single' and column_name ~ '(email|phone|guardianship|auth)'
    ),
    'Single read: no email, phone, Guardianship, or auth field (the email stays per-Appointment, BR-50)'
);

-- An Organization-wide actor reads an A2 Appointment through A2.
select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000106', true);
set local role authenticated;
select pg_temp.assert_true(
    (select count(*) = 1 from public.get_clinic_appointment(pg_temp.id('4', 2), pg_temp.id('d', 20))),
    'Single read: an Owner reads an A2 Appointment through A2'
);
reset role;

-- ===========================================================================
-- 3. Uniform denial (VN 63).
-- ===========================================================================

do $$
declare
    subject_suffix text;
begin
    foreach subject_suffix in array array['12', '13', '14', '15', '16', '17', '18', '01'] loop
        perform set_config(
            'request.jwt.claim.sub', 'c0e80000-0000-4000-8000-0000000001' || subject_suffix, true
        );
        set local role authenticated;
        perform pg_temp.assert_appointment_denied(pg_temp.a1()::text, pg_temp.id('d', 1)::text);
        reset role;
    end loop;
end;
$$;

select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000106', true);
set local role authenticated;
-- Another Clinic's Appointment, an unknown Appointment, an unknown Clinic,
-- another Organization's Clinic, nulls.
select pg_temp.assert_appointment_denied(pg_temp.a1()::text, pg_temp.id('d', 20)::text);
select pg_temp.assert_appointment_denied(pg_temp.a1()::text, pg_temp.id('d', 99)::text);
select pg_temp.assert_appointment_denied(pg_temp.id('4', 99)::text, pg_temp.id('d', 1)::text);
select pg_temp.assert_appointment_denied(pg_temp.id('4', 11)::text, pg_temp.id('d', 21)::text);
select pg_temp.assert_appointment_denied(null, null);
select pg_temp.assert_appointment_denied(pg_temp.a1()::text, null);
reset role;

-- A Clinic-scoped Receptionist of A1 asking through A2.
select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_appointment_denied(pg_temp.id('4', 2)::text, pg_temp.id('d', 20)::text);
reset role;

-- No subject, no domain User, anon — for both reads.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment(%L, %L)', pg_temp.a1(), pg_temp.id('d', 1)),
    '28000', 'Authentication is required'
);
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 3)', pg_temp.a1()),
    '28000', 'Authentication is required'
);
reset role;

select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000120', true);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment(%L, %L)', pg_temp.a1(), pg_temp.id('d', 1)),
    '28000', 'No coherent domain User'
);
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 3)', pg_temp.a1()),
    '28000', 'No coherent domain User'
);
reset role;

select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000110', true);
set local role anon;
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment(%L, %L)', pg_temp.a1(), pg_temp.id('d', 1)),
    '42501', 'permission denied'
);
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 3)', pg_temp.a1()),
    '42501', 'permission denied'
);
reset role;

-- Clients cannot call the internal helpers directly.
select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000106', true);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.project_clinic_appointments(%L, array[%L]::uuid[])', pg_temp.a1(), pg_temp.id('d', 1)),
    '42501', 'permission denied'
);
select pg_temp.assert_error(
    format('select * from public.clinic_calendar_appointments(%L, %L, %L)', pg_temp.a1(), '2035-03-01', '2035-03-31'),
    '42501', 'permission denied'
);
reset role;

-- ===========================================================================
-- 4. Month counts: authority (VN 63, 66).
-- ===========================================================================

do $$
declare
    subject_suffix text;
begin
    foreach subject_suffix in array array['06', '07', '08', '09', '10', '11'] loop
        perform set_config(
            'request.jwt.claim.sub', 'c0e80000-0000-4000-8000-0000000001' || subject_suffix, true
        );
        set local role authenticated;
        perform pg_temp.assert_true(
            pg_temp.counts(2035, 3) = array[
                '(2035-03-10,1)', '(2035-03-12,2)', '(2035-03-13,1)', '(2035-03-14,1)',
                '(2035-03-15,1)', '(2035-03-16,1)', '(2035-03-25,1)', '(2035-03-31,1)'
            ],
            'Counts: actor ' || subject_suffix || ' reads the A1 March 2035 counts'
        );
        reset role;
    end loop;

    foreach subject_suffix in array array['12', '13', '14', '15', '16', '17', '18', '01'] loop
        perform set_config(
            'request.jwt.claim.sub', 'c0e80000-0000-4000-8000-0000000001' || subject_suffix, true
        );
        set local role authenticated;
        perform pg_temp.assert_error(
            format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 3)', pg_temp.a1()),
            '42501', 'Applicable Appointment schedule-view capability is required'
        );
        reset role;
    end loop;
end;
$$;

select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000106', true);
set local role authenticated;
-- Unknown Clinic and another Organization's Clinic: the schedule read's outcome.
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 3)', pg_temp.id('4', 99)),
    '42501', 'Applicable Appointment schedule-view capability is required'
);
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 3)', pg_temp.id('4', 11)),
    '42501', 'Applicable Appointment schedule-view capability is required'
);
-- Invalid input, only after authorization.
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, %s, %s)', pg_temp.a1(), year_value, month_value),
    '22023', 'Calendar month is invalid'
)
from (values ('2035', '0'), ('2035', '13'), ('2035', 'null'), ('null', '3'),
             ('1999', '3'), ('3000', '3'), ('2035', '-1')) as bad (year_value, month_value);
reset role;

select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000118', true);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_month_counts(%L, 2035, 13)', pg_temp.a1()),
    '42501', 'Applicable Appointment schedule-view capability is required'
);
reset role;

-- ===========================================================================
-- 5. Month counts: semantics (VN 64–67).
-- ===========================================================================

select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000110', true);
set local role authenticated;

-- March 2035: d01; d02 on its confirmed date only (not 03-11); d03 COMPLETED;
-- d04 CANCELLED and d06 EXPIRED excluded; d05 NO_SHOW; d08 and d09 on their
-- current dates only (not 03-20/03-21); d10 on its New York date (not 03-17);
-- d11 on 03-25 although its instant is 03-24 UTC; d12 on 03-31; d13 not here
-- (April 1 locally although 03-31 UTC); A2/B1 Appointments never counted.
select pg_temp.assert_true(
    pg_temp.counts(2035, 3) = array[
        '(2035-03-10,1)', '(2035-03-12,2)', '(2035-03-13,1)', '(2035-03-14,1)',
        '(2035-03-15,1)', '(2035-03-16,1)', '(2035-03-25,1)', '(2035-03-31,1)'
    ],
    'Counts: March 2035 follows states, latest revision, establishment timezone, midnight and DST'
);

select pg_temp.assert_true(
    pg_temp.counts(2035, 4) = array['(2035-04-01,1)'],
    'Counts: a 30-day month; 00:30 on April 1 in Madrid is April although it is March in UTC'
);

select pg_temp.assert_true(
    pg_temp.counts(2035, 10) = array['(2035-10-28,2)'],
    'Counts: both instants of the autumn DST day are counted on that day'
);

select pg_temp.assert_true(
    pg_temp.counts(2035, 12) = array['(2035-12-31,1)']
    and pg_temp.counts(2036, 1) = array['(2036-01-01,1)'],
    'Counts: year change — 23:30 on Dec 31 stays in 2035, 00:30 on Jan 1 is 2036'
);

select pg_temp.assert_true(
    pg_temp.counts(2036, 2) = array['(2036-02-29,1)'] and pg_temp.counts(2035, 2) = '{}',
    'Counts: a leap-day Appointment in a 29-day February; an empty 28-day February returns no rows'
);

select pg_temp.assert_true(
    pg_temp.counts(2026, 1) = array['(2026-01-15,1)'],
    'Counts: a past REQUESTED whose expiry is not materialized keeps its real state and is counted'
);

select pg_temp.assert_true(
    pg_temp.counts(2040, 7) = '{}',
    'Counts: a month without Appointments returns no rows'
);

reset role;

-- The session timezone never moves a date.
set local timezone = 'Pacific/Kiritimati';
select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.counts(2035, 3) = array[
        '(2035-03-10,1)', '(2035-03-12,2)', '(2035-03-13,1)', '(2035-03-14,1)',
        '(2035-03-15,1)', '(2035-03-16,1)', '(2035-03-25,1)', '(2035-03-31,1)'
    ]
    and pg_temp.counts(2035, 4) = array['(2035-04-01,1)'],
    'Counts: identical under a +14:00 session timezone'
);
reset role;
set local timezone = 'America/Adak';
select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.counts(2035, 12) = array['(2035-12-31,1)'] and pg_temp.counts(2036, 1) = array['(2036-01-01,1)'],
    'Counts: identical under a -10:00 session timezone'
);
reset role;
reset timezone;

-- The day definition shared with the planned day read: for every date of the
-- tested months, the per-day membership equals that date's count (absent = 0),
-- and no Appointment is on two dates.
select pg_temp.assert_true(
    not exists (
        select 1
        from (values (2035, 3), (2035, 4), (2035, 10), (2035, 12), (2036, 1), (2036, 2), (2026, 1))
             as tested (year_value, month_value),
             generate_series(
                 make_date(tested.year_value, tested.month_value, 1),
                 (make_date(tested.year_value, tested.month_value, 1) + interval '1 month' - interval '1 day'),
                 interval '1 day'
             ) as calendar_day
        where (select count(*) from public.clinic_calendar_appointments(pg_temp.a1(), calendar_day::date, calendar_day::date))
              is distinct from coalesce((
                  select month_count.appointment_count
                  from public.get_clinic_appointment_month_counts(pg_temp.a1(), tested.year_value, tested.month_value)
                       as month_count
                  where month_count.day = calendar_day::date
              ), 0)
    ),
    'Correspondence: each day''s count equals the shared day definition (planned day read)'
);

select pg_temp.assert_true(
    (select count(*) = count(distinct calendar.appointment_id)
     from public.clinic_calendar_appointments(pg_temp.a1(), '2026-01-01', '2036-12-31') as calendar)
    and (select array_agg(calendar.appointment_id order by calendar.appointment_id)
         from public.clinic_calendar_appointments(pg_temp.a1(), '2026-01-01', '2036-12-31') as calendar)
        = (select array_agg(appointment.id order by appointment.id)
           from public.appointments as appointment
           where appointment.clinic_id = pg_temp.a1()
             and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW')),
    'Calendar: every calendar Appointment of A1 appears exactly once; CANCELLED and EXPIRED never'
);

-- The count follows the stored state: a fixture that turns d01 into CANCELLED
-- (a fixture change, not the cancellation workflow) removes it from its day.
set local session_replication_role = replica;
update public.appointments set lifecycle_state = 'CANCELLED' where id = pg_temp.id('d', 1);
set local session_replication_role = origin;
select set_config('request.jwt.claim.sub', 'c0e80000-0000-4000-8000-000000000110', true);
set local role authenticated;
select pg_temp.assert_true(
    not exists (select 1 from public.get_clinic_appointment_month_counts(pg_temp.a1(), 2035, 3)
                where day = '2035-03-10'),
    'Counts: a CANCELLED Appointment leaves its day'
);
reset role;

-- ===========================================================================
-- 6. Reads create or change nothing (VN 68).
-- ===========================================================================

select pg_temp.assert_true(
    (select baseline.communications = (select count(*) from public.transactional_communications)
            and baseline.audit_events = (select count(*) from public.medical_access_audit_events)
            and baseline.lifecycle_events = (select count(*) from public.appointment_lifecycle_events)
            and baseline.revisions = (select count(*) from public.appointment_schedule_revisions)
            and baseline.proposals = (select count(*) from public.appointment_reschedule_proposals)
     from side_effect_baseline as baseline),
    'Side effects: no Communication, Medical Access Audit Event, Lifecycle Event, Revision or Proposal'
);

rollback;

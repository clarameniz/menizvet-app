-- Professional Longitudinal / Cross-Clinic Medical History — Phase 1:
-- SPEC-MED-005 §15/§16 as amended by SPEC-MED-010 BR-14/BR-22, SPEC-ID-006
-- BR-41, SPEC-ACC-003 BR-49/BR-55. Migrations
-- 20261105090000_professional_longitudinal_history.sql and
-- 20261113090000_appointment_owned_clinical_documentation.sql.
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The organizational context, the historical clinical record of other Clinics
-- and Organizations, and offboarding facts are loaded as data with triggers
-- bypassed (as in appointment_clinical_record_spec_med_010.sql); the current
-- visit is documented through the client record operation as the impersonated
-- assigned Veterinarian under the authenticated role. Mutants are pinned by
-- run_professional_history_faults.py. Fixture prefix d0360000-.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0360000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.clinic(n integer) returns uuid language sql immutable as $$ select pg_temp.id(4, n) $$;
create function pg_temp.appt(n integer) returns uuid language sql immutable as $$ select pg_temp.id(11, n) $$;
create function pg_temp.ca(n integer) returns uuid language sql immutable as $$ select pg_temp.id(12, n) $$;
create function pg_temp.ent(n integer) returns uuid language sql immutable as $$ select pg_temp.id(14, n) $$;
create function pg_temp.amd(n integer) returns uuid language sql immutable as $$ select pg_temp.id(15, n) $$;
create function pg_temp.luna() returns uuid language sql immutable as $$ select pg_temp.id(9, 1) $$;
create function pg_temp.toby() returns uuid language sql immutable as $$ select pg_temp.id(9, 2) $$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end $$;
-- 'OK:<value>' or 'ERR:<sqlstate>:<hint or ->:<message>'; a failure leaves nothing behind.
create function pg_temp.call(actor integer, statement text) returns text language plpgsql as $$
declare result text; hint_text text; begin
    perform pg_temp.act(actor);
    execute 'set local role authenticated';
    execute statement into result;
    perform pg_temp.flush();
    execute 'reset role';
    return 'OK:' || coalesce(result, 'null');
exception when others then
    get stacked diagnostics hint_text = pg_exception_hint;
    return 'ERR:' || sqlstate || ':' || coalesce(nullif(hint_text, ''), '-') || ':' || sqlerrm;
end $$;
create function pg_temp.j(outcome text) returns jsonb language sql immutable as $$
    select case when outcome like 'OK:%' then substr(outcome, 4)::jsonb end
$$;
-- The client history read, with explicit Clinic and Appointment.
create function pg_temp.raw_hist(actor integer, clinic uuid, appointment uuid, page_limit integer default 50,
    before_at timestamptz default null, before_id uuid default null) returns text language sql as $$
    select pg_temp.call(actor, format(
        'select public.view_appointment_professional_medical_history(%L, %L, %s, %L, %L)::text',
        clinic, appointment, coalesce(page_limit::text, 'null'), before_at, before_id))
$$;
create function pg_temp.hist_at(actor integer, clinic uuid, appointment uuid) returns jsonb language sql as $$
    select pg_temp.j(pg_temp.raw_hist(actor, clinic, appointment))
$$;
create function pg_temp.hist(actor integer, appointment_n integer) returns jsonb language sql as $$
    select pg_temp.hist_at(actor, pg_temp.clinic(1), pg_temp.appt(appointment_n))
$$;
create function pg_temp.denied(payload jsonb) returns boolean language sql immutable as $$
    select payload = '{"status": "DENIED"}'::jsonb
$$;
create function pg_temp.ids(payload jsonb) returns uuid[] language sql immutable as $$
    select coalesce(array_agg((item ->> 'entry_id')::uuid order by ordinality), '{}')
    from jsonb_array_elements(payload -> 'entries') with ordinality as elements(item, ordinality)
$$;
create function pg_temp.item(payload jsonb, entry uuid) returns jsonb language sql immutable as $$
    select item from jsonb_array_elements(payload -> 'entries') as item where item ->> 'entry_id' = entry::text
$$;
create function pg_temp.guardian() returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(1, format('select public.view_guardian_pet_medical_history(%L)::text', pg_temp.luna())))
$$;
create function pg_temp.guardian_item(entry uuid) returns jsonb language sql as $$
    select item from jsonb_array_elements(pg_temp.guardian() #> '{payload,entries}') as item
    where item ->> 'id' = entry::text
$$;
create function pg_temp.record(actor integer, appointment_n integer) returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(actor, format('select public.view_appointment_clinical_record(%L, %L)::text',
        pg_temp.clinic(1), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.audits() returns bigint language sql as $$
    select count(*) from public.medical_access_audit_events where pet_id = pg_temp.luna()
$$;
create function pg_temp.last_audit() returns public.medical_access_audit_events language sql as $$
    select * from public.medical_access_audit_events where pet_id = pg_temp.luna()
    order by recorded_at desc, occurred_at desc limit 1
$$;
-- Every uuid in a payload must be one of the given Entry / Amendment ids.
create function pg_temp.only_ids(payload jsonb, allowed uuid[]) returns boolean language sql immutable as $$
    select coalesce(bool_and(match[1]::uuid = any(allowed)), true)
    from regexp_matches(payload::text,
        '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', 'g') as match
$$;
create function pg_temp.clinical_facts() returns text language sql as $$
    select md5(coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.clinical_record_entries t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.clinical_amendments t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.care_authorizations t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.appointments t), ''))
$$;
create temporary table remembered (label text primary key, value text) on commit drop;
create function pg_temp.remember(label text, value text) returns void language sql as $$
    insert into remembered values (label, value)
$$;
create function pg_temp.recalled(label text) returns text language sql as $$
    select value from remembered where remembered.label = recalled.label
$$;
create temporary table snapshots (label text primary key, payload jsonb) on commit drop;
create function pg_temp.snap(label text, payload jsonb) returns jsonb language sql as $$
    insert into snapshots values (label, payload) returning payload
$$;
create function pg_temp.snapped(label text) returns jsonb language sql as $$
    select payload from snapshots where snapshots.label = snapped.label
$$;

-- ===========================================================================
-- Fixture (data load, triggers bypassed)
--  Org X (3,1): Clinic 1 "Clínica Norte", Clinic 2 "Clínica Sur".
--  Org Y (3,2): Clinic 3 "VetCare Toledo" (unpublished).
--  1 Guardian of Luna and Toby   5 Administrator X   6 Owner X (no VETERINARIAN)
--  8 Receptionist of Clinic 1
--  10 Ana García, Veterinarian at Clinic 1 (the acting Veterinarian)
--  11 Carlos Ruiz, Veterinarian at Clinic 1
--  12 Elena Vidal, Veterinarian at Clinic 1, historical author, offboarded
--  13 Veterinarian at Clinic 1 with a blank display name
--  17 Diego Ortega, Veterinarian of Org Y at Clinic 3
--  18 Beatriz Sanz, Veterinarian at Clinic 2
--  19 Fernando Gil, Veterinarian at Clinics 1 and 2
--  20 Gloria Paz, Veterinarian whose Clinic 1 Assignment has ended
--  22 Veterinarian at Clinic 2 with no User Profile
-- Clinic 1 Appointments for Luna, each with an ACTIVE Appointment Care
-- Authorization unless noted:
--   1 REQUESTED, start 2099      2 REQUESTED, start passed   3 CONFIRMED
--   4 CONFIRMED with the current Entry E4 (Ana assigned)
--   5 CONFIRMED, Ana assigned, no Entry
--   6 COMPLETED, Ana assigned, no Entry   7 COMPLETED
--   8 CONFIRMED (revoked after assignment)   9 CONFIRMED (revoked before any record)
--  10 CANCELLED (Authorization ENDED)        11 CONFIRMED for Toby
--  12 CONFIRMED at Clinic 2              13 CONFIRMED (Entitlement lapse)
--  14 CONFIRMED whose Authorization is ENDED (loaded as data to pin the window)
-- Historical record (COMPLETED Appointments 50 at Clinic 1, 51 at Clinic 2, 52
-- at Clinic 3, and 54 for Toby at Clinic 1):
--   eA1 (Clinic 1) by Elena, two Amendments, no event time
--   eA3 (Clinic 1) by vet 13, same chronology as eA1
--   eB1 (Clinic 2) by Beatriz, event before its Appointment
--   eC1 (Clinic 3, Org Y) by Diego, its Care Authorization REVOKED
--   eT1 Toby's
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'hist-' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 5, 6, 8, 10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 5, 6, 8, 10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 5, 6, 8, 10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.user_profiles (user_id, display_name) values
    (pg_temp.id(2, 10), 'Ana García'), (pg_temp.id(2, 11), 'Carlos Ruiz'), (pg_temp.id(2, 12), 'Elena Vidal'),
    (pg_temp.id(2, 13), E'  \t '), (pg_temp.id(2, 17), 'Diego Ortega'), (pg_temp.id(2, 18), 'Beatriz Sanz'),
    (pg_temp.id(2, 19), 'Fernando Gil'), (pg_temp.id(2, 20), 'Gloria Paz'), (pg_temp.id(2, 1), 'Maria Guardian');
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Org X Veterinaria'), (pg_temp.id(3, 2), 'Org Y Group');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.clinic(1), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(2), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(3), pg_temp.id(3, 2), false, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.clinic_public_profiles (clinic_id, display_name) values
    (pg_temp.clinic(1), 'Clínica Norte'), (pg_temp.clinic(2), 'Clínica Sur'), (pg_temp.clinic(3), 'VetCare Toledo');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 17 then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z'
from unnest(array[5, 6, 8, 10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case n when 5 then 'ADMINISTRATOR' when 6 then 'OWNER' when 8 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n = 8 then 'CLINIC' else 'ORGANIZATION' end, case when n = 8 then pg_temp.clinic(1) end,
    '2020-01-01Z', pg_temp.id(2, 6)
from unnest(array[5, 6, 8, 10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id(7, n), pg_temp.id(2, n) from unnest(array[10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start, effective_end)
select pg_temp.id(8, n), pg_temp.id(7, n), pg_temp.id(5, n),
    case when n = 17 then pg_temp.clinic(3) when n in (18, 22) then pg_temp.clinic(2) else pg_temp.clinic(1) end,
    '2020-01-01Z', case when n = 20 then '2026-03-01Z'::timestamptz end
from unnest(array[10, 11, 12, 13, 17, 18, 19, 20, 22]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start)
values (pg_temp.id(8, 119), pg_temp.id(7, 19), pg_temp.id(5, 19), pg_temp.clinic(2), '2020-01-01Z');
insert into public.pets (id, name, species, created_at) values
    (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z'), (pg_temp.toby(), 'Toby', 'Cat', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values
    (pg_temp.id(9, 11), pg_temp.id(2, 1), pg_temp.luna(), '2020-01-01Z'),
    (pg_temp.id(9, 12), pg_temp.id(2, 1), pg_temp.toby(), '2020-01-01Z');

-- Current Appointments 1–13.
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.appt(n), case when n = 11 then pg_temp.toby() else pg_temp.luna() end,
    case when n = 12 then pg_temp.clinic(2) else pg_temp.clinic(1) end, pg_temp.id(2, 1), 'Visit ' || n,
    case when n in (1, 2) then 'REQUESTED' when n = 10 then 'CANCELLED' else 'CONFIRMED' end,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 14) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select pg_temp.appt(n), r, case r when 1 then 'REQUESTED' else 'CONFIRMED' end,
    case n when 1 then '2099-01-01T10:00Z'::timestamptz when 2 then '2026-01-15T10:00Z'::timestamptz
           else '2026-06-01T10:00Z'::timestamptz end,
    case n when 1 then '2099-01-01T10:30Z'::timestamptz when 2 then '2026-01-15T10:30Z'::timestamptz
           else '2026-06-01T10:30Z'::timestamptz end,
    'Europe/Madrid', pg_temp.id(2, case r when 1 then 1 else 8 end), null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from generate_series(1, 14) n, unnest(array[1, 2]) r
where r = 1 or n not in (1, 2);
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state, ended_at, ended_reason)
select pg_temp.ca(n), case when n = 11 then pg_temp.toby() else pg_temp.luna() end,
    case when n = 12 then pg_temp.clinic(2) else pg_temp.clinic(1) end, pg_temp.id(3, 1),
    case when n = 11 then pg_temp.id(9, 12) else pg_temp.id(9, 11) end,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE', pg_temp.appt(n),
    case when n in (10, 14) then 'ENDED' else 'ACTIVE' end,
    case when n in (10, 14) then '2026-02-15Z'::timestamptz end,
    case when n in (10, 14) then 'APPOINTMENT_CANCELLED' end
from generate_series(1, 14) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select pg_temp.appt(n), 'REQUESTED', 'CONFIRMED', pg_temp.id(2, 8), 'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(3, 14) n where n <> 10;

-- Historical COMPLETED Appointments 50 (Clinic 1), 51 (Clinic 2), 52 (Clinic 3)
-- and 54 (Toby, Clinic 1).
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
values (pg_temp.appt(50), pg_temp.luna(), pg_temp.clinic(1), pg_temp.id(2, 1), 'Old A', 'COMPLETED', '2025-02-01Z'),
       (pg_temp.appt(51), pg_temp.luna(), pg_temp.clinic(2), pg_temp.id(2, 1), 'Old B', 'COMPLETED', '2025-05-01Z'),
       (pg_temp.appt(52), pg_temp.luna(), pg_temp.clinic(3), pg_temp.id(2, 1), 'Old C', 'COMPLETED', '2025-08-01Z'),
       (pg_temp.appt(54), pg_temp.toby(), pg_temp.clinic(1), pg_temp.id(2, 1), 'Old T', 'COMPLETED', '2025-02-01Z');
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state, revoked_at, revoking_user_id)
values (pg_temp.ca(50), pg_temp.luna(), pg_temp.clinic(1), pg_temp.id(3, 1), pg_temp.id(9, 11), '2025-02-01Z',
        'APPOINTMENT_CARE', pg_temp.appt(50), 'ACTIVE', null, null),
       (pg_temp.ca(51), pg_temp.luna(), pg_temp.clinic(2), pg_temp.id(3, 1), pg_temp.id(9, 11), '2025-05-01Z',
        'APPOINTMENT_CARE', pg_temp.appt(51), 'ACTIVE', null, null),
       (pg_temp.ca(52), pg_temp.luna(), pg_temp.clinic(3), pg_temp.id(3, 2), pg_temp.id(9, 11), '2025-08-01Z',
        'APPOINTMENT_CARE', pg_temp.appt(52), 'REVOKED', '2025-10-01Z', pg_temp.id(2, 1)),
       (pg_temp.ca(54), pg_temp.toby(), pg_temp.clinic(1), pg_temp.id(3, 1), pg_temp.id(9, 12), '2025-02-01Z',
        'APPOINTMENT_CARE', pg_temp.appt(54), 'ACTIVE', null, null);
insert into public.clinical_record_entries (id, appointment_id, created_by_user_id,
    creator_veterinarian_clinic_assignment_id, created_at, clinical_content, category, clinical_event_at,
    creation_idempotency_key, creation_request_digest)
values
    -- eA1: Elena authored; no event time, so its recording time orders it.
    (pg_temp.ent(1), pg_temp.appt(50), pg_temp.id(2, 12), pg_temp.id(8, 12), '2025-03-01T09:00Z',
     'Dose 50 mg', 'TREATMENT', null, gen_random_uuid(), sha256('eA1'::bytea)),
    -- eA3: same chronology as eA1 (tie broken by Entry identity), blank author name.
    (pg_temp.ent(3), pg_temp.appt(50), pg_temp.id(2, 13), pg_temp.id(8, 13), '2025-03-01T09:45Z',
     'Weight 12 kg', 'EXAMINATION', '2025-03-01T09:00Z', gen_random_uuid(), sha256('eA3'::bytea)),
    -- eB1: Clinic 2; event time before its Appointment.
    (pg_temp.ent(4), pg_temp.appt(51), pg_temp.id(2, 18), pg_temp.id(8, 18), '2025-06-01T09:30Z',
     'Lab result: normal', 'LABORATORY_RESULT', '2025-05-20T08:00Z', gen_random_uuid(), sha256('eB1'::bytea)),
    -- eC1: Clinic 3 of Org Y, whose Care Authorization is REVOKED.
    (pg_temp.ent(5), pg_temp.appt(52), pg_temp.id(2, 17), pg_temp.id(8, 17), '2025-09-01T09:30Z',
     'Surgery: spay', 'PROCEDURE', null, gen_random_uuid(), sha256('eC1'::bytea)),
    -- eT1: Toby's.
    (pg_temp.ent(6), pg_temp.appt(54), pg_temp.id(2, 11), pg_temp.id(8, 11), '2025-02-15T09:30Z',
     'Toby only', 'EXAMINATION', null, gen_random_uuid(), sha256('eT1'::bytea));
-- Historical reason-and-addition corrections (kind ADDENDUM, SPEC-MED-010
-- BR-18): loaded as data, as recorded before stage M5.
insert into public.clinical_amendments (id, original_clinical_record_entry_id, change_kind, reason, amendment_content,
    amending_user_id, amending_veterinarian_clinic_assignment_id, created_at, idempotency_key)
values (pg_temp.amd(1), pg_temp.ent(1), 'ADDENDUM', 'Incorrect dose', 'Correct dose is 5 mg', pg_temp.id(2, 11), pg_temp.id(8, 11),
        '2025-12-05Z', gen_random_uuid()),
       (pg_temp.amd(2), pg_temp.ent(1), 'ADDENDUM', 'Clarification', 'Given with food', pg_temp.id(2, 12), pg_temp.id(8, 12),
        '2025-12-06Z', gen_random_uuid());
-- Elena is offboarded: Membership, VETERINARIAN Grant and Clinic Assignment ended.
update public.organization_memberships set effective_end = '2026-01-01Z', ended_by_user_id = pg_temp.id(2, 5)
where id = pg_temp.id(5, 12);
update public.organization_responsibility_grants set effective_end = '2026-01-01Z', ended_by_user_id = pg_temp.id(2, 5)
where id = pg_temp.id(6, 12);
update public.veterinarian_clinic_assignments set effective_end = '2026-01-01Z' where id = pg_temp.id(8, 12);
set local session_replication_role = origin;

select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'history-suite', pg_temp.id(21, 1), null) is not null as established_x,
       public.establish_organization_subscription(pg_temp.id(3, 2), null, 'ACTIVE', '2020-01-01Z', null, null,
    'history-suite', pg_temp.id(21, 2), null) is not null as established_y;
select pg_temp.flush();

-- The current visit: Ana is the assigned Veterinarian of 4, 5, 6 and 8 and
-- records E4 through the client operation; 6 and 7 are completed. The
-- Appointments share one slot, so the periods are data (no commitment check).
set local session_replication_role = replica;
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select pg_temp.appt(n), pg_temp.id(8, 10), clock_timestamp(), pg_temp.id(2, 8) from unnest(array[4, 5, 6, 8]) n;
set local session_replication_role = origin;
create temporary table current_entries (label text primary key, id uuid) on commit drop;
insert into current_entries values
    ('E4', (pg_temp.j(pg_temp.call(10, format(
        'select public.create_appointment_clinical_entry(%L, %L, %L, %L, %L, null)::text',
        pg_temp.clinic(1), pg_temp.appt(4), pg_temp.id(16, 1), 'EXAMINATION', 'Current visit exam'))) ->> 'entry_id')::uuid);
create function pg_temp.e4() returns uuid language sql as $$ select id from current_entries where label = 'E4' $$;
select pg_temp.call(5, format('select public.complete_appointment(%L, 2)::text', pg_temp.appt(n)))
from unnest(array[6, 7]) n;

select pg_temp.assert_true(
    (select appointment_id = pg_temp.appt(4) from public.clinical_record_entries where id = pg_temp.e4())
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(6))
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(7))
    and not exists (select 1 from public.clinical_record_entries where appointment_id in (pg_temp.appt(5), pg_temp.appt(6)))
    and not exists (select 1 from public.veterinarian_availability_periods
                    where veterinarian_clinic_assignment_id = pg_temp.id(8, 10)),
    'HIST precondition: the visit states are as intended, with no Veterinarian Availability'
);

-- ===========================================================================
-- 1. Contract and ACL (BR-38)
-- ===========================================================================

select pg_temp.assert_true(
    (select proc.prosecdef and proc.proconfig = array['search_path=""'] and proc.provolatile = 'v'
            and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
            and not has_function_privilege('anon', proc.oid, 'EXECUTE')
            and not has_function_privilege('service_role', proc.oid, 'EXECUTE')
            and not has_function_privilege('public', proc.oid, 'EXECUTE')
     from pg_proc as proc
     where proc.oid = 'public.view_appointment_professional_medical_history(uuid,uuid,integer,timestamptz,uuid)'::regprocedure)
    and (select count(*) = 1 from pg_proc
         where pronamespace = 'public'::regnamespace and proname = 'view_appointment_professional_medical_history')
    -- Structural pin: VETERINARIAN always carries both clinical capabilities, so
    -- the CLINICAL_CARE requirement (BR-37) is not behaviourally separable here.
    and (select position('''CLINICAL_CARE''' in def) > 0 and position('CLINICAL_DOCUMENTATION' in def) = 0
         from pg_get_functiondef('public.view_appointment_professional_medical_history(uuid,uuid,integer,timestamptz,uuid)'::regprocedure) as def),
    'HIST contract: the read is SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only, one signature'
);

select pg_temp.assert_true(
    (select bool_and(not has_function_privilege(role_name, helper, 'EXECUTE'))
     from unnest(array['public', 'anon', 'authenticated', 'service_role']) as role_name,
          unnest(array['public.clinical_history_page(uuid,integer,timestamptz,uuid)',
                       'public.clinical_history_amendments(uuid)',
                       'public.clinical_entry_versions(uuid)',
                       'public.clinical_entry_current(uuid)',
                       'public.clinical_entry_previous_versions(uuid)',
                       'public.clinical_provenance_display_name(uuid)',
                       'public.appointment_professional_history_accessible(uuid,timestamptz)']) as helper)
    and (select bool_and(proc.prosecdef and proc.proconfig = array['search_path=""'])
         from pg_proc as proc
         where proc.pronamespace = 'public'::regnamespace
           and proc.proname in ('clinical_history_page', 'clinical_history_amendments', 'clinical_entry_versions',
                                'clinical_entry_current', 'clinical_entry_previous_versions',
                                'clinical_provenance_display_name', 'appointment_professional_history_accessible')),
    'HIST contract: the shared projection, display-name and window helpers are private'
);

select pg_temp.assert_true(
    to_regprocedure('public.view_professional_pet_medical_history(uuid,uuid,uuid,uuid,integer,timestamptz,uuid)') is null
    and pg_temp.call(10, format('select public.view_professional_pet_medical_history(%L, %L, %L)::text',
        pg_temp.luna(), pg_temp.clinic(1), pg_temp.ca(3))) like 'ERR:42883:%'
    and has_function_privilege('authenticated', 'public.view_guardian_pet_medical_history(uuid,integer,timestamptz,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.view_guardian_pet_medical_history(uuid,integer,timestamptz,uuid)', 'EXECUTE')
    and not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                    and proname in ('slice12_view_guardian_pet_medical_history', 'slice13_view_guardian_pet_medical_history',
                                    'decorate_guardian_medical_history_provenance_names')),
    'HIST contract: the legacy Pet-keyed read no longer exists (SPEC-MED-010 BR-25); the Guardian read stays; its old chain is gone'
);

-- ===========================================================================
-- 2. History window (SPEC-MED-010 BR-14)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.hist(10, 1) ->> 'status' = 'PERMITTED'
    and pg_temp.denied(pg_temp.hist(10, 2))
    and pg_temp.hist(10, 3) ->> 'status' = 'PERMITTED'
    and pg_temp.hist(10, 4) ->> 'status' = 'PERMITTED'
    and pg_temp.hist(10, 5) ->> 'status' = 'PERMITTED',
    'HIST window: REQUESTED (future start) and CONFIRMED with an ACTIVE authorization are permitted, documented or not; a passed REQUESTED start is not'
);

-- Documentation access never opens prior history (BR-15).
select pg_temp.assert_true(
    pg_temp.denied(pg_temp.hist(10, 6))
    and pg_temp.denied(pg_temp.hist(10, 7))
    and pg_temp.record(10, 6) ->> 'status' = 'PERMITTED'
    and pg_temp.record(10, 6) #>> '{documentation,can_record}' = 'true',
    'HIST window: a COMPLETED Appointment is denied, although its assigned Veterinarian may still document it'
);

-- Guardian revocation, before any record and after assignment.
select pg_temp.call(1, format('select public.revoke_my_appointment_care_authorization(%L)::text', pg_temp.appt(n)))
from unnest(array[8, 9]) n;
select pg_temp.assert_true(
    (select bool_and(lifecycle_state = 'REVOKED') from public.care_authorizations where id in (pg_temp.ca(8), pg_temp.ca(9)))
    and pg_temp.denied(pg_temp.hist(10, 9))
    and pg_temp.denied(pg_temp.hist(10, 8))
    and pg_temp.record(10, 8) ->> 'status' = 'PERMITTED'
    and pg_temp.record(10, 8) #>> '{documentation,can_record}' = 'true',
    'HIST window: revocation denies history immediately; documentation access to the Appointment''s own record stays'
);
select pg_temp.assert_true(pg_temp.denied(pg_temp.hist(10, 10)) and pg_temp.denied(pg_temp.hist(10, 14)),
    'HIST window: an ENDED Care Authorization is denied, for a cancelled and for a still CONFIRMED Appointment');

-- ===========================================================================
-- 3. Authority before existence (BR-39)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.denied(pg_temp.hist(8, 3))
    and pg_temp.denied(pg_temp.hist(5, 3))
    and pg_temp.denied(pg_temp.hist(6, 3))
    and pg_temp.denied(pg_temp.hist(1, 3))
    and pg_temp.denied(pg_temp.hist(20, 3))
    and pg_temp.denied(pg_temp.hist(12, 3))
    and pg_temp.raw_hist(0, pg_temp.clinic(1), pg_temp.appt(3)) like 'ERR:28000:%',
    'HIST authority: Receptionist, Administrator, Owner, Guardian, ended Clinic Assignment and offboarded Veterinarian are refused uniformly'
);

select pg_temp.assert_true(
    -- Another Organization, with its own Clinic and with ours.
    pg_temp.denied(pg_temp.hist_at(17, pg_temp.clinic(3), pg_temp.appt(3)))
    and pg_temp.denied(pg_temp.hist_at(17, pg_temp.clinic(1), pg_temp.appt(3)))
    -- Same Organization, another Clinic, with its own Clinic and with ours.
    and pg_temp.denied(pg_temp.hist_at(18, pg_temp.clinic(2), pg_temp.appt(3)))
    and pg_temp.denied(pg_temp.hist_at(18, pg_temp.clinic(1), pg_temp.appt(3)))
    -- A Veterinarian of both Clinics acting through Clinic 2 for a Clinic 1 Appointment.
    and pg_temp.denied(pg_temp.hist_at(19, pg_temp.clinic(2), pg_temp.appt(3)))
    -- Our Veterinarian naming Clinic 2 (no Assignment there), an unknown Clinic,
    -- an unknown Appointment, and an Appointment of Clinic 2 under Clinic 1.
    and pg_temp.denied(pg_temp.hist_at(10, pg_temp.clinic(2), pg_temp.appt(12)))
    and pg_temp.denied(pg_temp.hist_at(10, pg_temp.id(4, 999), pg_temp.appt(3)))
    and pg_temp.denied(pg_temp.hist_at(10, pg_temp.clinic(1), pg_temp.id(11, 999)))
    and pg_temp.denied(pg_temp.hist_at(10, pg_temp.clinic(1), pg_temp.appt(12)))
    and pg_temp.denied(pg_temp.hist_at(5, pg_temp.clinic(1), pg_temp.id(11, 999)))
    and pg_temp.denied(pg_temp.hist_at(10, pg_temp.clinic(1), null)),
    'HIST authority: wrong Clinic, wrong Organization, unknown and foreign targets are indistinguishable from no authority'
);

select pg_temp.assert_true(
    pg_temp.hist_at(19, pg_temp.clinic(1), pg_temp.appt(3)) ->> 'status' = 'PERMITTED'
    and pg_temp.hist_at(18, pg_temp.clinic(2), pg_temp.appt(12)) ->> 'status' = 'PERMITTED'
    and pg_temp.hist(11, 3) ->> 'status' = 'PERMITTED',
    'HIST authority: any current Veterinarian of the Appointment''s Clinic reads, without Appointment Assignment or Availability'
);

select pg_temp.assert_true(
    pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 0) like 'ERR:22023:INVALID_LIMIT:%'
    and pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), null) like 'ERR:22023:INVALID_LIMIT:%'
    and pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 10, '2026-01-01Z', null) like 'ERR:22023:INVALID_CURSOR:%'
    and pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 10, null, pg_temp.ent(1)) like 'ERR:22023:INVALID_CURSOR:%'
    and pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 10, 'infinity', pg_temp.ent(1)) like 'ERR:22023:INVALID_CURSOR:%'
    and pg_temp.raw_hist(8, pg_temp.id(4, 999), pg_temp.id(11, 999), 0) like 'ERR:22023:INVALID_LIMIT:%',
    'HIST arguments: a bad limit or cursor is rejected by shape alone, the same for every caller and target'
);

-- ===========================================================================
-- 4. Cross-Clinic content (BR-41) and ordering (BR-42)
-- ===========================================================================

select pg_temp.snap('full', pg_temp.hist(10, 3));
select pg_temp.assert_true(
    pg_temp.ids(pg_temp.snapped('full'))
        = array[pg_temp.e4(), pg_temp.ent(5), pg_temp.ent(4), pg_temp.ent(3), pg_temp.ent(1)]
    and pg_temp.snapped('full') -> 'cursor' = 'null'::jsonb,
    'HIST content: every recorded Entry of the Pet from every Clinic and Organization, newest clinical occurrence first'
);

select pg_temp.assert_true(
    not (pg_temp.ids(pg_temp.snapped('full')) && array[pg_temp.ent(6)])
    and pg_temp.snapped('full')::text not like '%Toby only%',
    'HIST content: no other Pet'
);

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(5)) ->> 'clinic_display_name' = 'VetCare Toledo'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(5)) ->> 'organization_display_name' = 'Org Y Group'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(4)) ->> 'clinic_display_name' = 'Clínica Sur'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(4)) ->> 'organization_display_name' = 'Org X Veterinaria'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'clinic_display_name' = 'Clínica Norte'
    and (select lifecycle_state = 'REVOKED' from public.care_authorizations where id = pg_temp.ca(52))
    and (select not is_published from public.clinics where id = pg_temp.clinic(3)),
    'HIST content: each Entry keeps its originating Clinic and Organization, also when that Clinic is unpublished and its old Authorization REVOKED'
);

select pg_temp.assert_true(
    pg_temp.ids(pg_temp.hist_at(18, pg_temp.clinic(2), pg_temp.appt(12))) = pg_temp.ids(pg_temp.snapped('full'))
    and pg_temp.ids(pg_temp.hist(10, 1)) = pg_temp.ids(pg_temp.snapped('full'))
    and pg_temp.ids(pg_temp.hist(10, 4)) = pg_temp.ids(pg_temp.snapped('full')),
    'HIST content: the same complete history through any permitted Appointment or Clinic context'
);

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'clinical_event_at' is null
    and (pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'history_order_at')::timestamptz = '2025-03-01T09:00Z'
    and (pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'finalized_at')::timestamptz = '2025-03-01T09:00Z'
    and (pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(4)) ->> 'history_order_at')::timestamptz = '2025-05-20T08:00Z'
    and (pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(4)) ->> 'finalized_at')::timestamptz = '2025-06-01T09:30Z'
    and (pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(3)) ->> 'history_order_at')::timestamptz = '2025-03-01T09:00Z',
    'HIST ordering: the clinical event time, else the recording time, drives chronology (SPEC-MED-010 BR-22); recording is publication'
);

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.e4()) ->> 'is_this_appointment' = 'false'
    and pg_temp.item(pg_temp.hist(10, 4), pg_temp.e4()) ->> 'is_this_appointment' = 'true'
    and pg_temp.item(pg_temp.hist(10, 4), pg_temp.ent(5)) ->> 'is_this_appointment' = 'false',
    'HIST content: an Entry of the reading Appointment is marked as such, others are not'
);

-- ===========================================================================
-- 5. Payload (BR-43)
-- ===========================================================================

select pg_temp.assert_true(
    (select array_agg(key order by key collate "C") = array['cursor', 'entries', 'status']
     from jsonb_object_keys(pg_temp.snapped('full')) as key)
    and (select bool_and((select array_agg(key order by key collate "C") from jsonb_object_keys(item) as key)
            = array['amendment_count', 'amendments', 'amendments_truncated', 'author', 'category', 'clinic_display_name',
                    'clinical_content', 'clinical_event_at', 'edited_at', 'entry_id', 'finalized_at',
                    'finalizer', 'history_order_at', 'is_this_appointment', 'organization_display_name',
                    'other_category_context', 'previous_versions', 'previous_versions_truncated', 'version'])
         from jsonb_array_elements(pg_temp.snapped('full') -> 'entries') as item)
    and (select array_agg(key order by key collate "C") = array['display_name', 'is_me']
         from jsonb_object_keys(pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) -> 'author') as key)
    and (select array_agg(key order by key collate "C") = array['amendment_content', 'amendment_id', 'author', 'created_at', 'reason']
         from jsonb_object_keys(pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) #> '{amendments,0}') as key),
    'HIST payload: exactly the allowed keys'
);

select pg_temp.assert_true(
    pg_temp.only_ids(pg_temp.snapped('full'),
        array[pg_temp.e4(), pg_temp.ent(5), pg_temp.ent(4), pg_temp.ent(3), pg_temp.ent(1), pg_temp.amd(1), pg_temp.amd(2)])
    and pg_temp.snapped('full')::text !~ '(user_id|assignment|care_authorization|membership|grant|encounter_id|clinic_id|organization_id|appointment_id|draft_revision|last_modified|email|registration)'
    and pg_temp.snapped('full')::text not like '%@example.test%',
    'HIST payload: no User, Membership, Assignment, Care Authorization, Encounter, Clinic, Organization or Appointment identifier'
);

-- ===========================================================================
-- 6. Veterinarian provenance (BR-44, SPEC-ID-006 BR-41)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) -> 'author' = '{"display_name": "Elena Vidal", "is_me": false}'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) -> 'finalizer' = 'null'::jsonb
    and exists (select 1 from public.organization_memberships where id = pg_temp.id(5, 12) and effective_end is not null)
    and exists (select 1 from public.veterinarian_clinic_assignments where id = pg_temp.id(8, 12) and effective_end is not null),
    'HIST provenance: an offboarded author keeps her name; an Entry is published by its own author (no finalizer)'
);

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(3)) -> 'author' = '{"display_name": null, "is_me": false}'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(3)) -> 'finalizer' = 'null'::jsonb
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(4)) -> 'author' = '{"display_name": "Beatriz Sanz", "is_me": false}'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(4)) -> 'finalizer' = 'null'::jsonb
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(5)) -> 'author' = '{"display_name": "Diego Ortega", "is_me": false}'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(5)) -> 'finalizer' = 'null'::jsonb,
    'HIST provenance: a blank or missing name is null; the finalizer is always null'
);

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.e4()) -> 'author' = '{"display_name": "Ana García", "is_me": true}'
    and pg_temp.item(pg_temp.hist(11, 3), pg_temp.e4()) -> 'author' = '{"display_name": "Ana García", "is_me": false}'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.e4()) -> 'finalizer' = 'null'::jsonb,
    'HIST provenance: the reader''s own name is shown, with is_me relative to the reader'
);

select pg_temp.assert_true(
    pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) -> 'amendments' = jsonb_build_array(
        jsonb_build_object('amendment_id', pg_temp.amd(1), 'reason', 'Incorrect dose', 'amendment_content', 'Correct dose is 5 mg',
            'created_at', '2025-12-05T00:00:00+00:00'::timestamptz,
            'author', jsonb_build_object('display_name', 'Carlos Ruiz', 'is_me', false)),
        jsonb_build_object('amendment_id', pg_temp.amd(2), 'reason', 'Clarification', 'amendment_content', 'Given with food',
            'created_at', '2025-12-06T00:00:00+00:00'::timestamptz,
            'author', jsonb_build_object('display_name', 'Elena Vidal', 'is_me', false)))
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'clinical_content' = 'Dose 50 mg'
    and (pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'amendment_count')::integer = 2
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(1)) ->> 'amendments_truncated' = 'false'
    and pg_temp.item(pg_temp.snapped('full'), pg_temp.ent(3)) -> 'amendments' = '[]'::jsonb,
    'HIST amendments: the original stays unchanged and its Amendments follow oldest first, each with its own author'
);

set local session_replication_role = replica;
update public.user_profiles set display_name = 'Carlos Ruiz Pérez' where user_id = pg_temp.id(2, 11);
set local session_replication_role = origin;
select pg_temp.assert_true(
    pg_temp.item(pg_temp.hist(10, 3), pg_temp.ent(1)) #>> '{amendments,0,author,display_name}' = 'Carlos Ruiz Pérez'
    and (select amending_user_id = pg_temp.id(2, 11) from public.clinical_amendments where id = pg_temp.amd(1)),
    'HIST provenance: a renamed User shows the current name; attribution is unchanged'
);

-- ===========================================================================
-- 7. Pagination (BR-42)
-- ===========================================================================

select pg_temp.snap('p1', pg_temp.j(pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 2)));
select pg_temp.snap('p2', pg_temp.j(pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 2,
    (pg_temp.snapped('p1') #>> '{cursor,before_history_order_at}')::timestamptz,
    (pg_temp.snapped('p1') #>> '{cursor,before_entry_id}')::uuid)));
select pg_temp.snap('p3', pg_temp.j(pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 2,
    (pg_temp.snapped('p2') #>> '{cursor,before_history_order_at}')::timestamptz,
    (pg_temp.snapped('p2') #>> '{cursor,before_entry_id}')::uuid)));
select pg_temp.assert_true(
    pg_temp.ids(pg_temp.snapped('p1')) = array[pg_temp.e4(), pg_temp.ent(5)]
    and pg_temp.ids(pg_temp.snapped('p2')) = array[pg_temp.ent(4), pg_temp.ent(3)]
    and pg_temp.ids(pg_temp.snapped('p3')) = array[pg_temp.ent(1)]
    and pg_temp.snapped('p1') #>> '{cursor,before_entry_id}' = pg_temp.ent(5)::text
    and pg_temp.snapped('p3') -> 'cursor' = 'null'::jsonb
    and pg_temp.ids(pg_temp.snapped('p1')) || pg_temp.ids(pg_temp.snapped('p2')) || pg_temp.ids(pg_temp.snapped('p3'))
        = pg_temp.ids(pg_temp.snapped('full')),
    'HIST pagination: keyset pages neither duplicate nor skip, and the last page has no cursor'
);

select pg_temp.assert_true(
    pg_temp.ids(pg_temp.j(pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 1000))) = pg_temp.ids(pg_temp.snapped('full'))
    and pg_temp.denied(pg_temp.j(pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(7), 2,
        (pg_temp.snapped('p1') #>> '{cursor,before_history_order_at}')::timestamptz,
        (pg_temp.snapped('p1') #>> '{cursor,before_entry_id}')::uuid))),
    'HIST pagination: a large limit is capped, and a cursor grants nothing where the window is closed'
);

-- An edit of a page-one Entry between pages (SPEC-MED-010 BR-18, BR-22):
-- later pages are unchanged and the next read of page one shows the current
-- version, with the original kept as an earlier version and the recording
-- time, author and order unchanged.
select pg_temp.remember('e4_before_edit', pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4())::text);
select pg_temp.call(10, format('select public.edit_appointment_clinical_entry(%L, %L, %L, %L, 1, %L, %L, null)::text',
    pg_temp.clinic(1), pg_temp.appt(4), pg_temp.e4(), pg_temp.id(17, 1), 'DIAGNOSIS', 'Otitis, left ear'));
select pg_temp.assert_true(
    pg_temp.ids(pg_temp.j(pg_temp.raw_hist(10, pg_temp.clinic(1), pg_temp.appt(3), 2,
        (pg_temp.snapped('p1') #>> '{cursor,before_history_order_at}')::timestamptz,
        (pg_temp.snapped('p1') #>> '{cursor,before_entry_id}')::uuid))) = pg_temp.ids(pg_temp.snapped('p2'))
    and pg_temp.ids(pg_temp.hist(10, 3)) = pg_temp.ids(pg_temp.snapped('full'))
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) ->> 'category' = 'DIAGNOSIS'
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) ->> 'clinical_content' = 'Otitis, left ear'
    and (pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) ->> 'version')::integer = 2
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) ->> 'edited_at' is not null
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) -> 'previous_versions' = jsonb_build_array(jsonb_build_object(
            'version', 1, 'category', 'EXAMINATION', 'other_category_context', null,
            'clinical_content', 'Current visit exam',
            'created_at', (select created_at from public.clinical_record_entries where id = pg_temp.e4())))
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) -> 'amendments' = '[]'::jsonb
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) ->> 'finalized_at'
        = pg_temp.recalled('e4_before_edit')::jsonb ->> 'finalized_at'
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) ->> 'history_order_at'
        = pg_temp.recalled('e4_before_edit')::jsonb ->> 'history_order_at'
    and pg_temp.item(pg_temp.hist(10, 3), pg_temp.e4()) #>> '{author,display_name}' = 'Ana García',
    'HIST pagination: an edit between pages never duplicates or moves its Entry; the current version is shown and the original is kept'
);

-- ===========================================================================
-- 8. Audit (BR-45)
-- ===========================================================================

select pg_temp.remember('facts_before_audit', pg_temp.clinical_facts());
create temporary table audit_mark (label text primary key, n bigint) on commit drop;
insert into audit_mark values ('before_page', pg_temp.audits());
select pg_temp.hist(10, 3);
select pg_temp.assert_true(
    pg_temp.audits() = (select n from audit_mark where label = 'before_page') + 1
    and (pg_temp.last_audit()).operation = 'VIEW_PET_MEDICAL_HISTORY'
    and (pg_temp.last_audit()).outcome = 'PERMITTED'
    and (pg_temp.last_audit()).actor_context = 'PROFESSIONAL_CLINICAL'
    and (pg_temp.last_audit()).protected_resource_scope = 'LONGITUDINAL_MEDICAL_HISTORY'
    and (pg_temp.last_audit()).acting_user_id = pg_temp.id(2, 10)
    and (pg_temp.last_audit()).care_authorization_id = pg_temp.ca(3)
    and (pg_temp.last_audit()).accessing_clinic_id = pg_temp.clinic(1)
    and (pg_temp.last_audit()).accessing_organization_id = pg_temp.id(3, 1)
    and (pg_temp.last_audit()).appointment_id = pg_temp.appt(3)
    and (pg_temp.last_audit()).organization_membership_id = pg_temp.id(5, 10)
    and (pg_temp.last_audit()).organization_responsibility_grant_id = pg_temp.id(6, 10)
    and (pg_temp.last_audit()).veterinarian_clinic_assignment_id = pg_temp.id(8, 10)
    and (pg_temp.last_audit()).clinical_record_entry_id is null,
    'HIST audit: one PERMITTED event per page, with the current access context, never one per Entry'
);

insert into audit_mark values ('before_active', pg_temp.audits());
select pg_temp.hist(10, 4);
select pg_temp.assert_true(
    pg_temp.audits() = (select n from audit_mark where label = 'before_active') + 1
    and (pg_temp.last_audit()).appointment_id = pg_temp.appt(4)
    and (pg_temp.last_audit()).clinical_record_entry_id is null
    and (pg_temp.last_audit()).veterinarian_clinic_assignment_id = pg_temp.id(8, 10),
    'HIST audit: through a documented Appointment the event names that Appointment and the reader, never an Entry or a historical author'
);

insert into audit_mark values ('before_denied', pg_temp.audits());
select pg_temp.hist(10, 7);
select pg_temp.assert_true(
    pg_temp.audits() = (select n from audit_mark where label = 'before_denied') + 1
    and (pg_temp.last_audit()).outcome = 'DENIED'
    and (pg_temp.last_audit()).operation = 'VIEW_PET_MEDICAL_HISTORY'
    and (pg_temp.last_audit()).appointment_id = pg_temp.appt(7)
    and (pg_temp.last_audit()).veterinarian_clinic_assignment_id = pg_temp.id(8, 10),
    'HIST audit: a closed window is audited DENIED with the professional context'
);

insert into audit_mark values ('before_unauthorized', pg_temp.audits());
select pg_temp.hist(8, 3);
select pg_temp.assert_true(
    pg_temp.audits() = (select n from audit_mark where label = 'before_unauthorized') + 1
    and (pg_temp.last_audit()).outcome = 'DENIED'
    and (pg_temp.last_audit()).acting_user_id = pg_temp.id(2, 8)
    and (pg_temp.last_audit()).organization_membership_id is null
    and (pg_temp.last_audit()).veterinarian_clinic_assignment_id is null,
    'HIST audit: an unauthorized attempt on a Clinic Appointment is audited DENIED without professional context'
);

insert into audit_mark values ('before_unknown', pg_temp.audits());
select pg_temp.hist_at(10, pg_temp.clinic(1), pg_temp.id(11, 999)), pg_temp.hist_at(10, pg_temp.clinic(1), pg_temp.appt(12)),
       pg_temp.hist_at(18, pg_temp.clinic(1), pg_temp.appt(12));
select pg_temp.assert_true(
    pg_temp.audits() = (select n from audit_mark where label = 'before_unknown')
    and (select count(*) = 0 from public.medical_access_audit_events where pet_id = pg_temp.luna()
         and appointment_id = pg_temp.appt(12) and accessing_clinic_id = pg_temp.clinic(1)),
    'HIST audit: an unknown Appointment or one of another Clinic establishes no Pet context and is not audited'
);

select pg_temp.assert_true(
    pg_temp.clinical_facts() = pg_temp.recalled('facts_before_audit'),
    'HIST read only: reads change no Entry, Amendment, Care Authorization or Appointment'
);

-- ===========================================================================
-- 9. Guardian history payload (BR-46)
-- ===========================================================================

select pg_temp.snap('guardian', pg_temp.guardian());
select pg_temp.assert_true(
    (select array_agg((item ->> 'id')::uuid order by ordinality) from jsonb_array_elements(pg_temp.snapped('guardian') #> '{payload,entries}')
         with ordinality as entries(item, ordinality))
        = array[pg_temp.e4(), pg_temp.ent(5), pg_temp.ent(4), pg_temp.ent(3), pg_temp.ent(1)]
    and (select bool_and((select array_agg(key order by key collate "C") from jsonb_object_keys(item) as key)
            = array['amendment_count', 'amendments', 'amendments_truncated', 'attachments', 'category', 'clinic_display_name',
                    'clinical_content', 'clinical_event_at', 'edited_at', 'finalized_at', 'history_order_at',
                    'id', 'organization_display_name', 'other_category_context', 'previous_versions',
                    'previous_versions_truncated', 'version'])
         from jsonb_array_elements(pg_temp.snapped('guardian') #> '{payload,entries}') as item)
    and (select array_agg(key order by key collate "C") = array['amendment_content', 'created_at', 'id', 'reason']
         from jsonb_object_keys(pg_temp.guardian_item(pg_temp.ent(1)) #> '{amendments,0}') as key),
    'HIST guardian: the same Entries in the same order, carrying exactly the allowed keys'
);

select pg_temp.assert_true(
    pg_temp.only_ids(pg_temp.snapped('guardian'),
        array[pg_temp.e4(), pg_temp.ent(5), pg_temp.ent(4), pg_temp.ent(3), pg_temp.ent(1), pg_temp.amd(1), pg_temp.amd(2),
              (select id from public.clinical_amendments where original_clinical_record_entry_id = pg_temp.e4())])
    and pg_temp.snapped('guardian')::text !~ '(user_id|assignment|care_authorization|membership|encounter_id|clinic_id|organization_id|appointment_id|draft_revision|last_modified|display_name": "(Ana|Elena|Carlos|Beatriz|Diego))'
    and pg_temp.snapped('guardian')::text not like '%Elena Vidal%'
    and pg_temp.snapped('guardian')::text not like '%Carlos Ruiz%'
    and pg_temp.snapped('guardian')::text not like '%Ana García%',
    'HIST guardian: no internal identifier and no Veterinarian name reaches the Guardian'
);

select pg_temp.assert_true(
    pg_temp.guardian_item(pg_temp.ent(1)) ->> 'clinical_content' = 'Dose 50 mg'
    and pg_temp.guardian_item(pg_temp.e4()) ->> 'category' = 'DIAGNOSIS'
    and pg_temp.guardian_item(pg_temp.e4()) ->> 'clinical_content' = 'Otitis, left ear'
    and pg_temp.guardian_item(pg_temp.e4()) #>> '{previous_versions,0,clinical_content}' = 'Current visit exam'
    and pg_temp.guardian_item(pg_temp.e4()) ->> 'edited_at' is not null
    and pg_temp.guardian_item(pg_temp.ent(1)) ->> 'edited_at' is null
    and pg_temp.guardian_item(pg_temp.ent(1)) -> 'previous_versions' = '[]'::jsonb
    and pg_temp.guardian_item(pg_temp.ent(1)) #>> '{amendments,0,amendment_content}' = 'Correct dose is 5 mg'
    and pg_temp.guardian_item(pg_temp.ent(1)) #>> '{amendments,1,reason}' = 'Clarification'
    and (pg_temp.guardian_item(pg_temp.ent(1)) ->> 'amendment_count')::integer = 2
    and pg_temp.guardian_item(pg_temp.ent(5)) ->> 'clinic_display_name' = 'VetCare Toledo'
    and pg_temp.guardian_item(pg_temp.ent(5)) ->> 'organization_display_name' = 'Org Y Group'
    and pg_temp.guardian_item(pg_temp.ent(1)) -> 'attachments' = '[]'::jsonb
    and pg_temp.guardian_item(pg_temp.ent(6)) is null
    and pg_temp.snapped('guardian') -> 'cursor' = 'null'::jsonb,
    'HIST guardian: content, Amendments, Clinic / Organization names and Attachments are unchanged; another Pet stays hidden'
);

-- ===========================================================================
-- 10. Entitlement lapse (BR-37, BR-40)
-- ===========================================================================

select public.apply_subscription_state_transition(
    (select id from public.organization_subscriptions where organization_id = pg_temp.id(3, 1)),
    'PAST_DUE', statement_timestamp(), null, null, 'history-suite', null);
select pg_temp.flush();

select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_CARE')
    and pg_temp.denied(pg_temp.hist(10, 13))
    and pg_temp.denied(pg_temp.hist(10, 4))
    and pg_temp.record(10, 4) ->> 'status' = 'PERMITTED'
    and pg_temp.guardian() ->> 'status' = 'PERMITTED',
    'HIST lapse: Entitlement loss denies history, also through a documented Appointment, while its own record and Guardian history stay'
);

rollback;

-- Zero retained fixture rows after rollback.
do $$
declare t record; n bigint; begin
    for t in select table_schema, table_name from information_schema.columns
             where table_schema in ('public', 'auth') and column_name = 'id' loop
        execute format('select count(*) from %I.%I where id::text like %L', t.table_schema, t.table_name, 'd0360000-%')
        into n;
        if n <> 0 then raise exception 'Retained fixtures in %.%', t.table_schema, t.table_name; end if;
    end loop;
end $$;

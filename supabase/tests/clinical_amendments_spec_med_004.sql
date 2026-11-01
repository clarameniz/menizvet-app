-- Editing a Clinical Record Entry with preserved versions — SPEC-MED-010
-- BR-18 (only the Entry's own author edits, independent of the Care
-- Authorization), BR-20 (current version and earlier versions in the
-- Appointment clinical record), BR-22 (Guardian history), BR-23b (the edit
-- operation), BR-25 (retired reason-and-addition operations), SPEC-MED-004 as
-- superseded by them, SPEC-SUB-004 BR-20. Migrations
-- 20261104090000_clinical_amendments.sql,
-- 20261113090000_appointment_owned_clinical_documentation.sql and
-- 20261116090000_editable_clinical_record_versions.sql.
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The organizational and scheduling context is loaded as data with triggers
-- bypassed (as in appointment_clinical_record_spec_med_010.sql), and so are
-- the Appointment Veterinarian periods (the Appointments share one slot), the
-- historical offboarding facts of the original authors and one historical
-- reason-and-addition correction; every clinical call goes through the client
-- operations as the impersonated User under the authenticated role, and
-- deferred integrity is flushed after each call. Mutants are pinned by
-- run_clinical_amendment_faults.py; the same-version race by
-- run_clinical_amendment_concurrency.py. Fixture prefix d0350000-.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0350000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.clinic(n integer) returns uuid language sql immutable as $$ select pg_temp.id(4, n) $$;
create function pg_temp.appt(n integer) returns uuid language sql immutable as $$ select pg_temp.id(11, n) $$;
create function pg_temp.ca(n integer) returns uuid language sql immutable as $$ select pg_temp.id(12, n) $$;
create function pg_temp.akey(n integer) returns uuid language sql immutable as $$ select pg_temp.id(20, n) $$;
create function pg_temp.luna() returns uuid language sql immutable as $$ select pg_temp.id(9, 1) $$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end $$;
-- Runs one statement as the impersonated User under the authenticated role:
-- 'OK:<value>' or 'ERR:<sqlstate>:<hint or ->:<message>'. A failure leaves
-- nothing behind (subtransaction).
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
-- "Guardar registro" (SPEC-MED-010 BR-23): no clinical time is sent.
create function pg_temp.record_raw(actor integer, appointment_n integer, key_n integer, content text,
    category text default 'TREATMENT') returns text language sql as $$
    select pg_temp.call(actor, format(
        'select public.create_appointment_clinical_entry(%L, %L, %L, %L, %L, null)::text',
        pg_temp.clinic(1), pg_temp.appt(appointment_n), pg_temp.id(13, key_n), category, content))
$$;
create function pg_temp.record(actor integer, appointment_n integer, key_n integer, content text,
    category text default 'TREATMENT') returns uuid language sql as $$
    select (pg_temp.j(pg_temp.record_raw(actor, appointment_n, key_n, content, category)) ->> 'entry_id')::uuid
$$;
-- "Guardar cambios" (BR-23b), with explicit Clinic, Appointment and Entry and
-- the version the editor was opened on.
create function pg_temp.edit_at(actor integer, clinic uuid, appointment uuid, entry uuid, key uuid,
    expected integer, category text, content text, context text) returns text language sql as $$
    select pg_temp.call(actor, format(
        'select public.edit_appointment_clinical_entry(%L, %L, %L, %L, %L, %L, %L, %L)::text',
        clinic, appointment, entry, key, expected, category, content, context))
$$;
create function pg_temp.edit(actor integer, appointment_n integer, entry uuid, key_n integer, expected integer,
    category text, content text, context text default null) returns text language sql as $$
    select pg_temp.edit_at(actor, pg_temp.clinic(1), pg_temp.appt(appointment_n), entry, pg_temp.akey(key_n),
        expected, category, content, context)
$$;
create function pg_temp.read(actor integer, appointment_n integer) returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(actor, format('select public.view_appointment_clinical_record(%L, %L)::text',
        pg_temp.clinic(1), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.read_entry(payload jsonb, entry uuid) returns jsonb language sql immutable as $$
    select item from jsonb_array_elements(payload -> 'entries') as item
    where item ->> 'entry_id' = entry::text
$$;
create function pg_temp.guardian_entry(entry uuid) returns jsonb language sql as $$
    select item
    from jsonb_array_elements(pg_temp.j(pg_temp.call(1, format(
        'select public.view_guardian_pet_medical_history(%L)::text', pg_temp.luna()))) #> '{payload,entries}') as item
    where item ->> 'id' = entry::text
$$;
create function pg_temp.audits() returns bigint language sql as $$
    select count(*) from public.medical_access_audit_events where pet_id = pg_temp.luna()
$$;
-- Stored versions after the first (kind EDIT) of one Entry.
create function pg_temp.edits(entry uuid) returns bigint language sql as $$
    select count(*) from public.clinical_amendments
    where original_clinical_record_entry_id = entry and change_kind = 'EDIT'
$$;
create function pg_temp.luna_rows() returns bigint language sql as $$
    select count(*) from public.clinical_amendments a
    join public.clinical_record_entries e on e.id = a.original_clinical_record_entry_id
    join public.appointments p on p.id = e.appointment_id where p.pet_id = pg_temp.luna()
$$;
create function pg_temp.version_row(entry uuid, n integer) returns public.clinical_amendments language sql as $$
    select * from public.clinical_amendments
    where original_clinical_record_entry_id = entry and version_number = n
$$;
create function pg_temp.version_facts(entry uuid, n integer) returns text language sql as $$
    select md5(to_jsonb(a)::text) from public.clinical_amendments a
    where a.original_clinical_record_entry_id = entry and a.version_number = n
$$;
create function pg_temp.entry(entry uuid) returns public.clinical_record_entries language sql as $$
    select * from public.clinical_record_entries where id = entry
$$;
-- Every stored fact of one row, for "unchanged" checks.
create function pg_temp.entry_facts(entry uuid) returns text language sql as $$
    select md5((select to_jsonb(e)::text from public.clinical_record_entries e where e.id = entry))
$$;
create function pg_temp.care_facts(appointment_n integer) returns text language sql as $$
    select md5((select to_jsonb(a)::text from public.appointments a where a.id = pg_temp.appt(appointment_n))
        || (select to_jsonb(k)::text from public.care_authorizations k where k.appointment_id = pg_temp.appt(appointment_n))
        || (select count(*)::text from public.clinical_record_entries e where e.appointment_id = pg_temp.appt(appointment_n))
        || coalesce((select string_agg(to_jsonb(v)::text, '|' order by v.id) from public.appointment_veterinarian_assignments v
                     where v.appointment_id = pg_temp.appt(appointment_n)), '')
        || (select count(*)::text from public.appointment_lifecycle_events l where l.appointment_id = pg_temp.appt(appointment_n)))
$$;
create function pg_temp.reassign(appointment_n integer, vet integer) returns text language sql as $$
    select pg_temp.call(8, format(
        'select public.assign_appointment_veterinarian(%L, %L, %L, %L)::text', pg_temp.clinic(1),
        pg_temp.appt(appointment_n), pg_temp.id(8, vet),
        (select id from public.appointment_veterinarian_assignments
         where appointment_id = pg_temp.appt(appointment_n) and effective_end is null)))
$$;
create temporary table facts (label text primary key, outcome text) on commit drop;
create function pg_temp.keep(label text, outcome text) returns text language sql as $$
    insert into facts values (label, outcome) returning outcome
$$;
create function pg_temp.fact(label text) returns jsonb language sql as $$
    select pg_temp.j(outcome) from facts where facts.label = fact.label
$$;
create function pg_temp.raw(label text) returns text language sql as $$
    select outcome from facts where facts.label = raw.label
$$;
create temporary table entries (label text primary key, id uuid) on commit drop;
create function pg_temp.e(label text) returns uuid language sql as $$
    select id from entries where entries.label = e.label
$$;
create temporary table remembered (label text primary key, value text) on commit drop;
create function pg_temp.remember(label text, value text) returns void language sql as $$
    insert into remembered values (label, value)
$$;
create function pg_temp.recalled(label text) returns text language sql as $$
    select value from remembered where remembered.label = recalled.label
$$;

-- ===========================================================================
-- Fixture (data load, triggers bypassed)
--  1 Guardian of Luna     5 Administrator of A     6 Owner of A (no VETERINARIAN)
--  8 Receptionist of Clinic 1
-- 10 Veterinarian at Clinic 1 (original author of most Entries)
-- 11 second Veterinarian at Clinic 1 (never an original author before section 6)
-- 12, 13, 14 Veterinarians at Clinic 1, original authors later offboarded
--    (Membership, VETERINARIAN Grant, Clinic Assignment ended respectively)
-- 15, 16 Veterinarians at Clinic 1: 15 authors on Appointment 6 in section 6,
--    which is then reassigned to 16
-- 17 Veterinarian of Organization B (Clinic 3)   18 Veterinarian at Clinic 2 of A
-- Appointments 1–12 at Clinic 1, CONFIRMED (confirmed 2026-02-01, scheduled
-- 2026-06-01T10:00Z), each with an ACTIVE Appointment Care Authorization.
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'amend-c-' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 5, 6, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 5, 6, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 5, 6, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Amend Client Org A'), (pg_temp.id(3, 2), 'Amend Client Org B');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.clinic(1), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(2), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(3), pg_temp.id(3, 2), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 17 then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z'
from unnest(array[5, 6, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case n when 5 then 'ADMINISTRATOR' when 6 then 'OWNER' when 8 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n = 8 then 'CLINIC' else 'ORGANIZATION' end, case when n = 8 then pg_temp.clinic(1) end,
    '2020-01-01Z', pg_temp.id(2, 6)
from unnest(array[5, 6, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id(7, n), pg_temp.id(2, n) from unnest(array[10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start)
select pg_temp.id(8, n), pg_temp.id(7, n), pg_temp.id(5, n),
    case n when 17 then pg_temp.clinic(3) when 18 then pg_temp.clinic(2) else pg_temp.clinic(1) end, '2020-01-01Z'
from unnest(array[10, 11, 12, 13, 14, 15, 16, 17, 18]) n;
insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (pg_temp.id(9, 11), pg_temp.id(2, 1), pg_temp.luna(), '2020-01-01Z');
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.appt(n), pg_temp.luna(), pg_temp.clinic(1), pg_temp.id(2, 1), 'Visit ' || n, 'CONFIRMED',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 12) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select pg_temp.appt(n), r, case r when 1 then 'REQUESTED' else 'CONFIRMED' end, '2026-06-01T10:00Z',
    '2026-06-01T10:30Z', 'Europe/Madrid', pg_temp.id(2, case r when 1 then 1 else 8 end), null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from generate_series(1, 12) n, unnest(array[1, 2]) r;
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select pg_temp.ca(n), pg_temp.luna(), pg_temp.clinic(1), pg_temp.id(3, 1), pg_temp.id(9, 11),
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE', pg_temp.appt(n), 'ACTIVE'
from generate_series(1, 12) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select pg_temp.appt(n), 'REQUESTED', 'CONFIRMED', pg_temp.id(2, 8), 'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(1, 12) n;
set local session_replication_role = origin;

select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'amendment-client-suite', pg_temp.id(21, 1), null) is not null as established_a,
       public.establish_organization_subscription(pg_temp.id(3, 2), null, 'ACTIVE', '2020-01-01Z', null, null,
    'amendment-client-suite', pg_temp.id(21, 2), null) is not null as established_b;
select pg_temp.flush();

-- Clinical work through the client operations. Assigned Veterinarians (data):
-- 10 on 1, 2, 7, 8, 9, 10, 11, 12; 12 on 3; 13 on 4; 14 on 5; 15 on 6.
--   1: E1 (vet 10, Vaccination "Rabies vaccine, annual")
--   2: E3, Appointment COMPLETED       3/4/5: E4/E5/E6 by vets 12/13/14
--   8: E7 (revoked in section 5)       9: E8, Appointment COMPLETED
--  10: E9                            11: E10 (ENDED in section 5)
--  12: E11 (revoked in section 5)      6: E12 in section 6    7: no Entry.
set local session_replication_role = replica;
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select pg_temp.appt(n), pg_temp.id(8, case n when 3 then 12 when 4 then 13 when 5 then 14 when 6 then 15 else 10 end),
    clock_timestamp(), pg_temp.id(2, 8)
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]) n;
set local session_replication_role = origin;
insert into entries values
    ('E1', pg_temp.record(10, 1, 1, 'Rabies vaccine, annual', 'VACCINATION')),
    ('E3', pg_temp.record(10, 2, 3, 'Ear drops')),
    ('E4', pg_temp.record(12, 3, 4, 'Vet 12 note')),
    ('E5', pg_temp.record(13, 4, 5, 'Vet 13 note')),
    ('E6', pg_temp.record(14, 5, 6, 'Vet 14 note')),
    ('E7', pg_temp.record(10, 8, 7, 'Before revocation')),
    ('E8', pg_temp.record(10, 9, 8, 'Completed visit')),
    ('E9', pg_temp.record(10, 10, 9, 'Documented visit')),
    ('E10', pg_temp.record(10, 11, 10, 'Before the end')),
    ('E11', pg_temp.record(10, 12, 11, 'Care underway'));
select pg_temp.call(5, format('select public.complete_appointment(%L, 2)::text', pg_temp.appt(n)))
from unnest(array[2, 9]) n;

select pg_temp.assert_true(
    (select count(*) = 10 from entries where id is not null)
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(2))
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(9))
    and (select lifecycle_state = 'CONFIRMED' from public.appointments where id = pg_temp.appt(10))
    and (select bool_and(lifecycle_state = 'ACTIVE') from public.care_authorizations
         where id in (pg_temp.ca(8), pg_temp.ca(10), pg_temp.ca(11), pg_temp.ca(12)))
    -- SPEC-MED-010 BR-16: completion ended the authorizations of 2 and 9.
    and (select bool_and(lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_COMPLETED')
         from public.care_authorizations where id in (pg_temp.ca(2), pg_temp.ca(9))),
    'EDT precondition: the clinical work is in the intended states'
);

-- BR-5: the server's recording time is the only date of a new Entry.
select pg_temp.assert_true(
    (select bool_and(e.clinical_event_at is null and e.created_at >= now() and e.created_at <= clock_timestamp())
     from public.clinical_record_entries e join entries on entries.id = e.id),
    'EDT record: a new Entry carries no clinical event time; its only date is the server recording time'
);

select pg_temp.remember('E1', pg_temp.entry_facts(pg_temp.e('E1')));
select pg_temp.remember('care_1', pg_temp.care_facts(1));

-- ===========================================================================
-- 1. Contract and ACL (BR-23b, BR-25)
-- ===========================================================================

select pg_temp.assert_true(
    (select proc.prosecdef and proc.proconfig = array['search_path=""'] and proc.provolatile = 'v'
            and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
            and not has_function_privilege('anon', proc.oid, 'EXECUTE')
            and not has_function_privilege('service_role', proc.oid, 'EXECUTE')
            and not has_function_privilege('public', proc.oid, 'EXECUTE')
     from pg_proc as proc
     where proc.oid = 'public.edit_appointment_clinical_entry(uuid,uuid,uuid,uuid,integer,text,text,text)'::regprocedure)
    and (select count(*) = 1 from pg_proc
         where pronamespace = 'public'::regnamespace and proname = 'edit_appointment_clinical_entry')
    and (select bool_and(not has_function_privilege(role_name, helper, 'EXECUTE'))
         from unnest(array['public.clinical_entry_versions(uuid)', 'public.clinical_entry_current(uuid)',
                           'public.clinical_entry_previous_versions(uuid)']) as helper,
              unnest(array['anon', 'authenticated', 'service_role']) as role_name)
    and has_function_privilege('authenticated', 'public.view_appointment_clinical_record(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.view_appointment_clinical_record(uuid,uuid)', 'EXECUTE')
    -- The SPEC-MED-009 Encounter-based access predicate no longer exists.
    and to_regprocedure('public.appointment_clinical_record_accessible(uuid)') is null,
    'EDT contract: the edit operation is SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only, one signature; the version helpers are internal'
);

select pg_temp.assert_true(
    not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('create_appointment_clinical_amendment', 'create_clinical_amendment'))
    and pg_temp.call(10, format('select public.create_appointment_clinical_amendment(%L, %L, %L, %L, %L, %L)::text',
        pg_temp.clinic(1), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(99), 'Old path', 'Old path')) like 'ERR:42883:%'
    and pg_temp.call(10, format('select public.create_clinical_amendment(%L, %L, %L, %L)::text',
        pg_temp.e('E1'), 'Old path', 'Old path', pg_temp.akey(99))) like 'ERR:42883:%'
    and pg_temp.luna_rows() = 0,
    'EDT contract: the reason-and-addition operations are retired for every role (BR-25)'
);

-- ===========================================================================
-- 2. Editing, idempotency and stale versions (BR-18, BR-23b)
-- ===========================================================================

-- The typing-error example: a Vaccination recorded on the wrong visit becomes
-- the Clinical note of what was actually done.
select pg_temp.keep('v2', pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 1, 'CLINICAL_NOTE',
    E'  Only a nail trim was performed \n'));
select pg_temp.assert_true(
    pg_temp.raw('v2') = 'OK:{"outcome": "EDITED", "version": 2}'
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).change_kind = 'EDIT'
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).reason is null
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).category = 'CLINICAL_NOTE'
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).other_category_context is null
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).amendment_content = 'Only a nail trim was performed'
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).amending_user_id = pg_temp.id(2, 10)
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).amending_veterinarian_clinic_assignment_id = pg_temp.id(8, 10)
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).created_at >= (pg_temp.entry(pg_temp.e('E1'))).created_at
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).created_at <= clock_timestamp()
    and (pg_temp.version_row(pg_temp.e('E1'), 2)).idempotency_key = pg_temp.akey(1),
    'EDT edit: the author edits category and content; the next version is appended at the server time with its own provenance'
);

select pg_temp.assert_true(
    pg_temp.entry_facts(pg_temp.e('E1')) = pg_temp.recalled('E1')
    and (pg_temp.entry(pg_temp.e('E1'))).category = 'VACCINATION'
    and (pg_temp.entry(pg_temp.e('E1'))).clinical_content = 'Rabies vaccine, annual'
    and pg_temp.care_facts(1) = pg_temp.recalled('care_1'),
    'EDT edit: the original version, its Appointment, assignment and Care Authorization are unchanged'
);

create temporary table after_edit on commit drop as
select pg_temp.read_entry(pg_temp.read(10, 1), pg_temp.e('E1')) as item;
select pg_temp.assert_true(
    (select item ->> 'category' = 'CLINICAL_NOTE'
            and item ->> 'clinical_content' = 'Only a nail trim was performed'
            and item -> 'other_category_context' = 'null'::jsonb
            and (item ->> 'version')::integer = 2
            and (item ->> 'edited_at')::timestamptz = (pg_temp.version_row(pg_temp.e('E1'), 2)).created_at
            and (item ->> 'recorded_at')::timestamptz = (pg_temp.entry(pg_temp.e('E1'))).created_at
            and item -> 'clinical_event_at' = 'null'::jsonb
            and item -> 'previous_versions' = jsonb_build_array(jsonb_build_object(
                'version', 1, 'category', 'VACCINATION', 'other_category_context', null,
                'clinical_content', 'Rabies vaccine, annual',
                'created_at', (pg_temp.entry(pg_temp.e('E1'))).created_at))
     from after_edit),
    'EDT read: the record shows the current version (Clinical note, corrected text), the original recording time and the earlier version'
);

-- BR-18: another current Veterinarian of the Clinic never edits an Entry they
-- did not author.
select pg_temp.keep('a_other', pg_temp.edit(11, 1, pg_temp.e('E1'), 2, 2, 'DIAGNOSIS', 'Given with food'));
select pg_temp.assert_true(
    pg_temp.raw('a_other') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.edits(pg_temp.e('E1')) = 1
    and pg_temp.entry_facts(pg_temp.e('E1')) = pg_temp.recalled('E1'),
    'EDT edit: another current Veterinarian receives ENTRY_AUTHOR_REQUIRED and writes nothing'
);

select pg_temp.remember('v2_row', pg_temp.version_facts(pg_temp.e('E1'), 2));
select pg_temp.assert_true(
    pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 1, 'CLINICAL_NOTE', 'Only a nail trim was performed')
        = 'OK:{"outcome": "ALREADY_EDITED", "version": 2}'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 1, 'CLINICAL_NOTE', E'\tOnly a nail trim was performed  ')
        = 'OK:{"outcome": "ALREADY_EDITED", "version": 2}'
    and pg_temp.edits(pg_temp.e('E1')) = 1
    and pg_temp.version_facts(pg_temp.e('E1'), 2) = pg_temp.recalled('v2_row'),
    'EDT idempotency: an exact repeat, including after a lost response, is ALREADY_EDITED with the same version'
);

select pg_temp.keep('conflict_content', pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 1, 'CLINICAL_NOTE', 'A nail trim and a bath'));
select pg_temp.keep('conflict_category', pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 1, 'PROCEDURE', 'Only a nail trim was performed'));
select pg_temp.keep('conflict_version', pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 2, 'CLINICAL_NOTE', 'Only a nail trim was performed'));
select pg_temp.keep('conflict_entry', pg_temp.edit(10, 2, pg_temp.e('E3'), 1, 1, 'CLINICAL_NOTE', 'Only a nail trim was performed'));
select pg_temp.assert_true(
    (select bool_and(outcome like 'ERR:23505:KEY_CONFLICT:%') from facts where label like 'conflict_%')
    and (select count(*) = 4 from facts where label like 'conflict_%')
    and (select bool_and(outcome not like '%' || pg_temp.akey(1)::text || '%') from facts
         where label like 'conflict_%')
    and pg_temp.edits(pg_temp.e('E1')) = 1 and pg_temp.edits(pg_temp.e('E3')) = 0
    and pg_temp.version_facts(pg_temp.e('E1'), 2) = pg_temp.recalled('v2_row'),
    'EDT idempotency: the same key with a different request is KEY_CONFLICT, writes nothing and never echoes the key'
);

select pg_temp.keep('stale_earlier', pg_temp.edit(10, 1, pg_temp.e('E1'), 3, 1, 'DIAGNOSIS', 'Opened on the original'));
select pg_temp.keep('stale_unknown', pg_temp.edit(10, 1, pg_temp.e('E1'), 4, 7, 'DIAGNOSIS', 'Opened on a future version'));
select pg_temp.assert_true(
    pg_temp.raw('stale_earlier') like 'ERR:P0001:STALE_VERSION:%'
    and pg_temp.raw('stale_unknown') like 'ERR:P0001:STALE_VERSION:%'
    and (select bool_and(outcome not like '%Opened on%' and outcome not like '%nail%') from facts
         where label like 'stale_%')
    and pg_temp.edits(pg_temp.e('E1')) = 1,
    'EDT stale: an edit opened on an earlier or unknown version is STALE_VERSION, echoes no content and writes nothing'
);

select pg_temp.assert_true(
    pg_temp.edit(10, 1, pg_temp.e('E1'), 5, 2, 'CLINICAL_NOTE', ' Only a nail trim was performed')
        = 'OK:{"outcome": "UNCHANGED", "version": 2}'
    and pg_temp.edits(pg_temp.e('E1')) = 1,
    'EDT unchanged: saving the current version without a change writes nothing'
);

select pg_temp.keep('v3', pg_temp.edit(10, 1, pg_temp.e('E1'), 6, 2, 'OTHER', 'Nail trim and ear cleaning', ' Grooming '));
select pg_temp.keep('v4', pg_temp.edit(10, 1, pg_temp.e('E1'), 7, 3, 'CLINICAL_NOTE', 'Nail trim and ear cleaning'));
select pg_temp.assert_true(
    pg_temp.raw('v3') = 'OK:{"outcome": "EDITED", "version": 3}'
    and pg_temp.raw('v4') = 'OK:{"outcome": "EDITED", "version": 4}'
    and (pg_temp.version_row(pg_temp.e('E1'), 3)).category = 'OTHER'
    and (pg_temp.version_row(pg_temp.e('E1'), 3)).other_category_context = 'Grooming'
    and (pg_temp.version_row(pg_temp.e('E1'), 4)).other_category_context is null
    and (select array_agg(version_number order by version_number) = array[2, 3, 4]
         from public.clinical_amendments where original_clinical_record_entry_id = pg_temp.e('E1'))
    and pg_temp.version_facts(pg_temp.e('E1'), 2) = pg_temp.recalled('v2_row')
    and pg_temp.entry_facts(pg_temp.e('E1')) = pg_temp.recalled('E1')
    -- A retry of the first save whose response was lost still reconciles.
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 1, 1, 'CLINICAL_NOTE', 'Only a nail trim was performed')
        = 'OK:{"outcome": "ALREADY_EDITED", "version": 2}'
    and pg_temp.edits(pg_temp.e('E1')) = 3,
    'EDT multiple: successive edits append versions 2, 3, 4 without gaps; earlier versions are unchanged and a late retry still reconciles'
);

-- Two editors opened on version 4 (sequentially here; the true race is
-- pinned by run_clinical_amendment_concurrency.py).
select pg_temp.keep('race_first', pg_temp.edit(10, 1, pg_temp.e('E1'), 8, 4, 'CLINICAL_NOTE', 'Nail trim, ears cleaned'));
select pg_temp.keep('race_second', pg_temp.edit(10, 1, pg_temp.e('E1'), 9, 4, 'CLINICAL_NOTE', 'Nail trim only'));
select pg_temp.assert_true(
    pg_temp.raw('race_first') = 'OK:{"outcome": "EDITED", "version": 5}'
    and pg_temp.raw('race_second') like 'ERR:P0001:STALE_VERSION:%'
    and pg_temp.edits(pg_temp.e('E1')) = 4
    and (pg_temp.version_row(pg_temp.e('E1'), 5)).amendment_content = 'Nail trim, ears cleaned',
    'EDT stale: of two edits opened on the same version the second is STALE_VERSION and the first stays current'
);

-- ===========================================================================
-- 3. Authority before existence (BR-17, BR-23b)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.edit(5, 1, pg_temp.e('E1'), 30, 5, 'CLINICAL_NOTE', 'Admin') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(8, 1, pg_temp.e('E1'), 31, 5, 'CLINICAL_NOTE', 'Reception') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(6, 1, pg_temp.e('E1'), 32, 5, 'CLINICAL_NOTE', 'Owner') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(1, 1, pg_temp.e('E1'), 33, 5, 'CLINICAL_NOTE', 'Guardian') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(0, 1, pg_temp.e('E1'), 35, 5, 'CLINICAL_NOTE', 'Anonymous') like 'ERR:28000:%'
    -- Authority comes before any request check.
    and pg_temp.edit_at(5, pg_temp.clinic(1), pg_temp.appt(1), pg_temp.e('E1'), null, null, null, null, null)
        = 'ERR:42501:-:Clinical record unavailable',
    'EDT authority: Administrator, Receptionist, Owner without Veterinarian context and Guardian are refused uniformly, before any request check'
);

select pg_temp.assert_true(
    -- Another Organization, with its own Clinic and with ours.
    pg_temp.edit_at(17, pg_temp.clinic(3), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(40), 5, 'CLINICAL_NOTE', 'B', null) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit_at(17, pg_temp.clinic(1), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(41), 5, 'CLINICAL_NOTE', 'B', null) = 'ERR:42501:-:Clinical record unavailable'
    -- A Veterinarian of another Clinic of the same Organization, with its own Clinic and with ours.
    and pg_temp.edit_at(18, pg_temp.clinic(2), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(42), 5, 'CLINICAL_NOTE', 'C2', null) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit_at(18, pg_temp.clinic(1), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(43), 5, 'CLINICAL_NOTE', 'C2', null) = 'ERR:42501:-:Clinical record unavailable'
    -- Our Veterinarian naming a Clinic where they hold no Assignment, or an unknown Clinic.
    and pg_temp.edit_at(10, pg_temp.clinic(2), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(44), 5, 'CLINICAL_NOTE', 'W', null) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit_at(10, pg_temp.id(4, 999), pg_temp.appt(1), pg_temp.e('E1'), pg_temp.akey(45), 5, 'CLINICAL_NOTE', 'W', null) = 'ERR:42501:-:Clinical record unavailable'
    -- Unknown Appointment, an Appointment without Entries, unknown Entry, Entry of another Appointment.
    and pg_temp.edit_at(10, pg_temp.clinic(1), pg_temp.id(11, 999), pg_temp.e('E1'), pg_temp.akey(46), 5, 'CLINICAL_NOTE', 'U', null) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(10, 6, pg_temp.e('E1'), 47, 5, 'CLINICAL_NOTE', 'U') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(10, 1, pg_temp.id(14, 999), 48, 5, 'CLINICAL_NOTE', 'U') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(10, 1, pg_temp.e('E3'), 49, 1, 'CLINICAL_NOTE', 'U') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(5, 1, pg_temp.id(14, 999), 50, 1, 'CLINICAL_NOTE', 'U') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.luna_rows() = 4,
    'EDT authority: wrong Clinic, wrong Organization, unknown and foreign targets are indistinguishable from no authority'
);

-- ===========================================================================
-- 4. Request rules (BR-5, BR-23b)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.edit_at(10, pg_temp.clinic(1), pg_temp.appt(1), pg_temp.e('E1'), null, 5, 'CLINICAL_NOTE', 'x', null) like 'ERR:22023:KEY_REQUIRED:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 60, null, 'CLINICAL_NOTE', 'x') like 'ERR:22023:INVALID_VERSION:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 61, 0, 'CLINICAL_NOTE', 'x') like 'ERR:22023:INVALID_VERSION:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 62, 5, null, 'x') like 'ERR:22023:CATEGORY_REQUIRED:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 63, 5, 'SURGERY', 'x') like 'ERR:22023:INVALID_CATEGORY:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 64, 5, 'CLINICAL_NOTE', E'\n  ') like 'ERR:22023:CONTENT_REQUIRED:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 65, 5, 'CLINICAL_NOTE', null) like 'ERR:22023:CONTENT_REQUIRED:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 66, 5, 'OTHER', 'x', E' \t') like 'ERR:22023:OTHER_CONTEXT_REQUIRED:%'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 67, 5, 'DIAGNOSIS', 'x', 'Grooming') like 'ERR:22023:OTHER_CONTEXT_NOT_ALLOWED:%'
    and pg_temp.edits(pg_temp.e('E1')) = 4,
    'EDT request: a missing key or version, a missing or invalid category, empty content or misplaced OTHER context is rejected with its stable hint and writes nothing'
);

-- ===========================================================================
-- 5. Appointment state and Care Authorization (BR-11, BR-18)
-- ===========================================================================

select pg_temp.remember('care_10', pg_temp.care_facts(10));
select pg_temp.keep('e9_v2', pg_temp.edit(10, 10, pg_temp.e('E9'), 70, 1, 'LABORATORY_RESULT', 'Culture negative'));
select pg_temp.assert_true(
    pg_temp.raw('e9_v2') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.care_facts(10) = pg_temp.recalled('care_10'),
    'EDT lifecycle: a CONFIRMED Appointment''s Entry is edited without changing the Appointment'
);

select pg_temp.remember('care_9', pg_temp.care_facts(9));
select pg_temp.keep('e8_v2', pg_temp.edit(10, 9, pg_temp.e('E8'), 71, 1, 'TREATMENT', 'Ointment, not drops'));
select pg_temp.assert_true(
    pg_temp.raw('e8_v2') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.care_facts(9) = pg_temp.recalled('care_9'),
    'EDT lifecycle: a COMPLETED Appointment is edited without any state change'
);

select pg_temp.remember('care_2', pg_temp.care_facts(2));
select pg_temp.keep('e3_v2', pg_temp.edit(10, 2, pg_temp.e('E3'), 72, 1, 'TREATMENT', 'Ear drops, left ear'));
select pg_temp.assert_true(
    pg_temp.raw('e3_v2') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.care_facts(2) = pg_temp.recalled('care_2')
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(2))
    and (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_COMPLETED' from public.care_authorizations where id = pg_temp.ca(2))
    and pg_temp.read_entry(pg_temp.read(10, 2), pg_temp.e('E3')) ->> 'may_edit' = 'true'
    and pg_temp.read_entry(pg_temp.read(10, 2), pg_temp.e('E3')) ->> 'clinical_content' = 'Ear drops, left ear'
    and pg_temp.read_entry(pg_temp.read(11, 2), pg_temp.e('E3')) ->> 'may_edit' = 'false',
    'EDT lifecycle: a COMPLETED Appointment''s Entry is edited by its author after completion ended the authorization; may_edit is true only for the author'
);

-- Revocation never removes the author's editing (BR-11, BR-18).
select pg_temp.keep('e7_v2', pg_temp.edit(10, 8, pg_temp.e('E7'), 73, 1, 'EXAMINATION', 'Weight 12 kg'));
select pg_temp.remember('E7', pg_temp.entry_facts(pg_temp.e('E7')));
select pg_temp.remember('e7_v2_row', pg_temp.version_facts(pg_temp.e('E7'), 2));
select pg_temp.call(1, format('select public.revoke_my_appointment_care_authorization(%L)::text', pg_temp.appt(n)))
from unnest(array[8, 12]) n;
create temporary table revoked_audits on commit drop as select pg_temp.audits() as n;
select pg_temp.keep('revoked_e7_author', pg_temp.edit(10, 8, pg_temp.e('E7'), 76, 2, 'EXAMINATION', 'Weight 12 kg, fasting confirmed'));
select pg_temp.keep('revoked_e7_replay', pg_temp.edit(10, 8, pg_temp.e('E7'), 73, 1, 'EXAMINATION', 'Weight 12 kg'));
select pg_temp.keep('revoked_e7_other', pg_temp.edit(11, 8, pg_temp.e('E7'), 75, 3, 'EXAMINATION', 'x'));
select pg_temp.keep('revoked_e11', pg_temp.edit(10, 12, pg_temp.e('E11'), 77, 1, 'TREATMENT', 'Care continued after revocation'));
select pg_temp.remember('audits_after_edits', pg_temp.audits()::text);
select pg_temp.assert_true(
    (select bool_and(lifecycle_state = 'REVOKED') from public.care_authorizations where id in (pg_temp.ca(8), pg_temp.ca(12)))
    and pg_temp.raw('e7_v2') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.raw('revoked_e7_author') = 'OK:{"outcome": "EDITED", "version": 3}'
    and pg_temp.raw('revoked_e7_replay') = 'OK:{"outcome": "ALREADY_EDITED", "version": 2}'
    and pg_temp.raw('revoked_e7_other') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.raw('revoked_e11') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.read(10, 8) ->> 'status' = 'PERMITTED'
    and pg_temp.read(11, 12) ->> 'status' = 'PERMITTED'
    and pg_temp.edits(pg_temp.e('E7')) = 2
    and pg_temp.edits(pg_temp.e('E11')) = 1,
    'EDT access: after Guardian revocation the author still edits and replays, the record stays readable, and non-authors are still refused'
);

-- ENDED (loaded as data with an existing reason value, purely to pin the
-- predicate): editing does not depend on the authorization either.
set local session_replication_role = replica;
update public.care_authorizations
set lifecycle_state = 'ENDED', ended_at = clock_timestamp(), ended_reason = 'APPOINTMENT_CANCELLED'
where id = pg_temp.ca(11);
set local session_replication_role = origin;
select pg_temp.keep('ended_e10', pg_temp.edit(10, 11, pg_temp.e('E10'), 80, 1, 'TREATMENT', 'Follow-up booked'));
select pg_temp.assert_true(
    pg_temp.read(10, 11) ->> 'status' = 'PERMITTED'
    and pg_temp.raw('ended_e10') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.edits(pg_temp.e('E10')) = 1,
    'EDT access: under an ENDED Care Authorization the author edits alike'
);

select pg_temp.assert_true(
    -- Edits are not reads: no clinical content, no audit of their own (BR-21).
    (select bool_and(outcome not like '%Weight%' and outcome not like '%Before revocation%'
                     and outcome not like '%Follow-up%') from facts
     where label like 'revoked_%' or label = 'ended_e10')
    and pg_temp.recalled('audits_after_edits') = (select n from revoked_audits)::text
    and pg_temp.entry_facts(pg_temp.e('E7')) = pg_temp.recalled('E7')
    and pg_temp.version_facts(pg_temp.e('E7'), 2) = pg_temp.recalled('e7_v2_row')
    and (pg_temp.version_row(pg_temp.e('E7'), 3)).amending_user_id = pg_temp.id(2, 10)
    and (pg_temp.entry(pg_temp.e('E7'))).created_by_user_id = pg_temp.id(2, 10),
    'EDT access: edits leak nothing, create no audit, and leave the original Entry, earlier versions and provenance intact'
);

-- ===========================================================================
-- 6. Authorship, offboarding and reassignment (BR-18, SPEC-MED-004 §10)
-- ===========================================================================

set local session_replication_role = replica;
update public.organization_memberships set effective_end = clock_timestamp(), ended_by_user_id = pg_temp.id(2, 5)
where id = pg_temp.id(5, 12);
update public.organization_responsibility_grants set effective_end = clock_timestamp(), ended_by_user_id = pg_temp.id(2, 5)
where id = pg_temp.id(6, 13);
update public.veterinarian_clinic_assignments set effective_end = clock_timestamp() where id = pg_temp.id(8, 14);
set local session_replication_role = origin;
select pg_temp.remember('E4', pg_temp.entry_facts(pg_temp.e('E4')));
select pg_temp.remember('E5', pg_temp.entry_facts(pg_temp.e('E5')));
select pg_temp.remember('E6', pg_temp.entry_facts(pg_temp.e('E6')));

select pg_temp.assert_true(
    pg_temp.edit(12, 3, pg_temp.e('E4'), 81, 1, 'CLINICAL_NOTE', 'Own entry') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(13, 4, pg_temp.e('E5'), 82, 1, 'CLINICAL_NOTE', 'Own entry') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(14, 5, pg_temp.e('E6'), 83, 1, 'CLINICAL_NOTE', 'Own entry') = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edits(pg_temp.e('E4')) + pg_temp.edits(pg_temp.e('E5')) + pg_temp.edits(pg_temp.e('E6')) = 0,
    'EDT offboarding: historical authorship alone grants no editing once the Veterinarian context ended'
);

select pg_temp.assert_true(
    pg_temp.edit(11, 3, pg_temp.e('E4'), 84, 1, 'CLINICAL_NOTE', 'Membership ended') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.edit(11, 4, pg_temp.e('E5'), 85, 1, 'CLINICAL_NOTE', 'Grant ended') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.edit(11, 5, pg_temp.e('E6'), 86, 1, 'CLINICAL_NOTE', 'Assignment ended') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.edits(pg_temp.e('E4')) + pg_temp.edits(pg_temp.e('E5')) + pg_temp.edits(pg_temp.e('E6')) = 0,
    'EDT offboarding: no other Veterinarian edits a departed author''s Entry'
);

-- The clarification is a new Entry by the Appointment's new assignee; the
-- original stays unchanged and attributed.
select pg_temp.keep('reassign_3', pg_temp.reassign(3, 11));
select pg_temp.keep('clarification_3', pg_temp.record_raw(11, 3, 87, 'Clarification of the earlier note'));
select pg_temp.assert_true(
    pg_temp.fact('reassign_3') ->> 'outcome' = 'REASSIGNED'
    and pg_temp.fact('clarification_3') ->> 'outcome' = 'CREATED'
    and pg_temp.edit(11, 3, pg_temp.e('E4'), 88, 1, 'CLINICAL_NOTE', 'As assignee') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.edits(pg_temp.e('E4')) = 0
    and pg_temp.entry_facts(pg_temp.e('E4')) = pg_temp.recalled('E4')
    and pg_temp.entry_facts(pg_temp.e('E5')) = pg_temp.recalled('E5')
    and pg_temp.entry_facts(pg_temp.e('E6')) = pg_temp.recalled('E6')
    and (pg_temp.entry(pg_temp.e('E4'))).created_by_user_id = pg_temp.id(2, 12)
    and (pg_temp.entry(pg_temp.e('E5'))).creator_veterinarian_clinic_assignment_id = pg_temp.id(8, 13)
    and (pg_temp.entry(pg_temp.e('E6'))).creator_veterinarian_clinic_assignment_id = pg_temp.id(8, 14)
    and exists (select 1 from public.organization_memberships where id = pg_temp.id(5, 12) and effective_end is not null)
    and exists (select 1 from public.organization_responsibility_grants where id = pg_temp.id(6, 13) and effective_end is not null)
    and exists (select 1 from public.veterinarian_clinic_assignments where id = pg_temp.id(8, 14) and effective_end is not null),
    'EDT offboarding: the new assignee clarifies with an Entry of their own; authorship and history are preserved'
);

-- A current author whose Appointment is reassigned keeps editing their Entry;
-- the new assignee adds a clarifying Entry and never edits the author's.
insert into entries values ('E12', pg_temp.record(15, 6, 12, 'Skin scraping taken'));
select pg_temp.keep('reassign_6', pg_temp.reassign(6, 16));
select pg_temp.keep('e12_after_reassign', pg_temp.edit(15, 6, pg_temp.e('E12'), 78, 1, 'LABORATORY_RESULT', 'Skin scraping negative'));
select pg_temp.keep('clarification_6', pg_temp.record_raw(16, 6, 89, 'Owner informed of the scraping result'));
select pg_temp.assert_true(
    pg_temp.e('E12') is not null
    and pg_temp.fact('reassign_6') ->> 'outcome' = 'REASSIGNED'
    and pg_temp.raw('e12_after_reassign') = 'OK:{"outcome": "EDITED", "version": 2}'
    and (pg_temp.version_row(pg_temp.e('E12'), 2)).amending_user_id = pg_temp.id(2, 15)
    and pg_temp.edit(16, 6, pg_temp.e('E12'), 79, 2, 'CLINICAL_NOTE', 'As assignee') like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.fact('clarification_6') ->> 'outcome' = 'CREATED'
    and pg_temp.record_raw(15, 6, 92, 'No longer assigned') like 'ERR:23514:NOT_ASSIGNED_VETERINARIAN:%'
    and (pg_temp.entry(pg_temp.e('E12'))).created_by_user_id = pg_temp.id(2, 15)
    and pg_temp.read_entry(pg_temp.read(15, 6), pg_temp.e('E12')) ->> 'may_edit' = 'true'
    and pg_temp.read_entry(pg_temp.read(16, 6), pg_temp.e('E12')) ->> 'may_edit' = 'false'
    and pg_temp.edits(pg_temp.e('E12')) = 1,
    'EDT reassignment: the author still edits after the Appointment is reassigned; the new assignee clarifies with an Entry of their own and never edits the author''s'
);

-- ===========================================================================
-- 7. Appointment clinical record with versions (BR-20)
-- ===========================================================================

-- A historical reason-and-addition correction (kind ADDENDUM), loaded as data
-- as recorded before M5.
set local session_replication_role = replica;
insert into public.clinical_amendments (original_clinical_record_entry_id, change_kind, reason, amendment_content,
    amending_user_id, amending_veterinarian_clinic_assignment_id, created_at, idempotency_key)
values (pg_temp.e('E8'), 'ADDENDUM', 'Typo', 'Ointment twice daily', pg_temp.id(2, 10), pg_temp.id(8, 10),
        clock_timestamp(), pg_temp.akey(500));
set local session_replication_role = origin;

create temporary table audit_mark (label text primary key, n bigint) on commit drop;
insert into audit_mark values ('before_read', pg_temp.audits());
create temporary table work_read on commit drop as select pg_temp.read(10, 1) as payload;

select pg_temp.assert_true(
    (select payload::text !~ '(user_id|clinic_assignment|care_authorization|membership|responsibility_grant|auth_|idempotency)'
            and payload::text not like '%' || pg_temp.id(2, 10)::text || '%'
            and payload::text not like '%' || pg_temp.id(2, 11)::text || '%'
            and payload::text not like '%' || pg_temp.id(8, 10)::text || '%'
            and payload::text not like '%' || pg_temp.id(8, 11)::text || '%'
            and payload::text not like '%' || pg_temp.akey(1)::text || '%'
            and payload::text not like '%' || pg_temp.akey(8)::text || '%'
     from work_read),
    'EDT read: versions carry no User, Clinic Assignment or key identifier'
);

select pg_temp.assert_true(
    (select (select array_agg(key order by key) from jsonb_object_keys(pg_temp.read_entry(payload, pg_temp.e('E1'))) as key)
                = array['amendments', 'amendments_truncated', 'category', 'clinical_content', 'clinical_event_at',
                        'edited_at', 'entry_id', 'may_edit', 'other_category_context', 'previous_versions',
                        'previous_versions_truncated', 'recorded_at', 'recorded_by_me', 'version']
            and pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'may_edit' = 'true'
            and pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'recorded_by_me' = 'true'
            and pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'category' = 'CLINICAL_NOTE'
            and pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'clinical_content' = 'Nail trim, ears cleaned'
            and (pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'version')::integer = 5
            and (pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'edited_at')::timestamptz
                = (pg_temp.version_row(pg_temp.e('E1'), 5)).created_at
            and (pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'recorded_at')::timestamptz
                = (pg_temp.entry(pg_temp.e('E1'))).created_at
            and (select array_agg((earlier.value ->> 'version')::integer order by earlier.ordinality)
                 from jsonb_array_elements(pg_temp.read_entry(payload, pg_temp.e('E1')) -> 'previous_versions')
                      with ordinality as earlier(value, ordinality)) = array[1, 2, 3, 4]
            and pg_temp.read_entry(payload, pg_temp.e('E1')) -> 'previous_versions' -> 2 = jsonb_build_object(
                'version', 3, 'category', 'OTHER', 'other_category_context', 'Grooming',
                'clinical_content', 'Nail trim and ear cleaning',
                'created_at', (pg_temp.version_row(pg_temp.e('E1'), 3)).created_at)
            and pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'previous_versions_truncated' = 'false'
            and pg_temp.read_entry(payload, pg_temp.e('E1')) -> 'amendments' = '[]'::jsonb
            and pg_temp.read_entry(payload, pg_temp.e('E1')) ->> 'amendments_truncated' = 'false'
     from work_read),
    'EDT read: each Entry shows its current version with every earlier version oldest first, beside its original recording time'
);

select pg_temp.assert_true(
    pg_temp.audits() = (select n from audit_mark where label = 'before_read') + 1,
    'EDT read: one audit event per read, not one per version'
);

select pg_temp.assert_true(
    pg_temp.read_entry(pg_temp.read(11, 1), pg_temp.e('E1')) ->> 'may_edit' = 'false'
    and pg_temp.read_entry(pg_temp.read(11, 1), pg_temp.e('E1')) ->> 'recorded_by_me' = 'false'
    and pg_temp.read_entry(pg_temp.read(11, 1), pg_temp.e('E1')) -> 'previous_versions'
        = pg_temp.read_entry((select payload from work_read), pg_temp.e('E1')) -> 'previous_versions'
    and pg_temp.read(5, 1) = '{"status": "DENIED"}'
    and pg_temp.read(12, 3) = '{"status": "DENIED"}',
    'EDT read: authorship is relative to the reader; the change history is visible exactly to those who may read the record'
);

select pg_temp.assert_true(
    (pg_temp.read_entry(pg_temp.read(10, 9), pg_temp.e('E8')) ->> 'version')::integer = 2
    and pg_temp.read_entry(pg_temp.read(10, 9), pg_temp.e('E8')) ->> 'clinical_content' = 'Ointment, not drops'
    and jsonb_array_length(pg_temp.read_entry(pg_temp.read(10, 9), pg_temp.e('E8')) -> 'previous_versions') = 1
    and jsonb_array_length(pg_temp.read_entry(pg_temp.read(10, 9), pg_temp.e('E8')) -> 'amendments') = 1
    and pg_temp.read_entry(pg_temp.read(10, 9), pg_temp.e('E8')) #>> '{amendments,0,reason}' = 'Typo'
    and pg_temp.read_entry(pg_temp.read(10, 9), pg_temp.e('E8')) #>> '{amendments,0,amended_by_me}' = 'true',
    'EDT read: a historical reason-and-addition correction is still shown as such and is never a version'
);

-- ===========================================================================
-- 8. Guardian history (BR-22, SPEC-MED-005)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'category' = 'CLINICAL_NOTE'
    and pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'clinical_content' = 'Nail trim, ears cleaned'
    and (pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'version')::integer = 5
    and pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'edited_at' is not null
    and jsonb_array_length(pg_temp.guardian_entry(pg_temp.e('E1')) -> 'previous_versions') = 4
    and pg_temp.guardian_entry(pg_temp.e('E1')) #>> '{previous_versions,0,clinical_content}' = 'Rabies vaccine, annual'
    and pg_temp.guardian_entry(pg_temp.e('E1')) #>> '{previous_versions,0,category}' = 'VACCINATION'
    and (pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'amendment_count')::integer = 0
    and (pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'history_order_at')::timestamptz
        = (pg_temp.entry(pg_temp.e('E1'))).created_at
    and (pg_temp.guardian_entry(pg_temp.e('E1')) ->> 'finalized_at')::timestamptz
        = (pg_temp.entry(pg_temp.e('E1'))).created_at
    and pg_temp.guardian_entry(pg_temp.e('E1'))::text not like '%' || pg_temp.id(2, 10)::text || '%'
    and pg_temp.guardian_entry(pg_temp.e('E7')) ->> 'clinical_content' = 'Weight 12 kg, fasting confirmed'
    and (pg_temp.guardian_entry(pg_temp.e('E7')) ->> 'version')::integer = 3
    and (pg_temp.guardian_entry(pg_temp.e('E8')) ->> 'amendment_count')::integer = 1,
    'EDT guardian: the Guardian sees the current version and every earlier one, also edits made after revocation, in the original order'
);

-- ===========================================================================
-- 9. Subscription continuity (SPEC-SUB-004 BR-20)
-- ===========================================================================

select public.apply_subscription_state_transition(
    (select id from public.organization_subscriptions where organization_id = pg_temp.id(3, 1)),
    'PAST_DUE', statement_timestamp(), null, null, 'amendment-client-suite', null);
select pg_temp.flush();

select pg_temp.keep('a_lapse', pg_temp.edit(10, 1, pg_temp.e('E1'), 90, 5, 'CLINICAL_NOTE', 'Nail trim, ears cleaned, owner informed'));
select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_CARE')
    and pg_temp.raw('a_lapse') = 'OK:{"outcome": "EDITED", "version": 6}'
    and pg_temp.edit(10, 1, pg_temp.e('E1'), 90, 5, 'CLINICAL_NOTE', 'Nail trim, ears cleaned, owner informed')
        = 'OK:{"outcome": "ALREADY_EDITED", "version": 6}'
    and pg_temp.record_raw(10, 7, 91, 'New care') like 'ERR:42501:CLINICAL_SERVICE_UNAVAILABLE:%'
    and pg_temp.edit(8, 1, pg_temp.e('E1'), 92, 6, 'CLINICAL_NOTE', 'x') = 'ERR:42501:-:Clinical record unavailable',
    'EDT lapse: an Entitlement lapse does not block an edit; new Entries stay unavailable and authority still applies'
);

-- ===========================================================================
-- 10. Immutability and version structure (BR-4, BR-5, BR-18)
-- ===========================================================================

do $$
declare update_error text := 'none'; delete_error text := 'none'; entry_error text := 'none';
        entry_delete_error text := 'none'; begin
    begin update public.clinical_amendments set amendment_content = 'Rewritten'
          where original_clinical_record_entry_id = pg_temp.e('E1') and version_number = 2;
    exception when others then update_error := sqlstate; end;
    begin delete from public.clinical_amendments
          where original_clinical_record_entry_id = pg_temp.e('E1') and version_number = 2;
    exception when others then delete_error := sqlstate; end;
    begin update public.clinical_record_entries set clinical_content = 'Rewritten' where id = pg_temp.e('E1');
    exception when others then entry_error := sqlstate; end;
    begin delete from public.clinical_record_entries where id = pg_temp.e('E1');
    exception when others then entry_delete_error := sqlstate; end;
    perform pg_temp.assert_true(
        update_error = '23514' and delete_error = '23514' and entry_error = '23514' and entry_delete_error = '23514'
        and pg_temp.version_facts(pg_temp.e('E1'), 2) = pg_temp.recalled('v2_row')
        and pg_temp.entry_facts(pg_temp.e('E1')) = pg_temp.recalled('E1'),
        'EDT immutability: versions and the recorded Entry cannot be updated or deleted');
end $$;

-- Even the trusted owner can only append the next version, by the author.
create function pg_temp.insert_version(kind text, version integer, author integer, reason text) returns text
language plpgsql as $$ begin
    insert into public.clinical_amendments (original_clinical_record_entry_id, change_kind, version_number, reason,
        category, amendment_content, amending_user_id, amending_veterinarian_clinic_assignment_id, created_at,
        idempotency_key)
    values (pg_temp.e('E1'), kind, version, reason, case when kind = 'EDIT' then 'CLINICAL_NOTE' end, 'Direct',
            pg_temp.id(2, author), pg_temp.id(8, author), clock_timestamp(), gen_random_uuid());
    return 'OK';
exception when others then
    return sqlstate || ':' || sqlerrm;
end $$;
create function pg_temp.insert_timed_entry() returns text language plpgsql as $$ begin
    insert into public.clinical_record_entries (appointment_id, category, clinical_content, clinical_event_at,
        created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at, creation_idempotency_key,
        creation_request_digest)
    values (pg_temp.appt(7), 'CLINICAL_NOTE', 'Direct', '2026-06-01T10:05Z', pg_temp.id(2, 10), pg_temp.id(8, 10),
            clock_timestamp(), gen_random_uuid(), '\x00'::bytea);
    return 'OK';
exception when others then
    return sqlstate || ':' || sqlerrm;
end $$;
select pg_temp.assert_true(
    pg_temp.insert_version('ADDENDUM', null, 10, 'Old style') like '23514:Only EDIT versions%'
    and pg_temp.insert_version('EDIT', 9, 10, null) like '23514:%follow its current version%'
    and pg_temp.insert_version('EDIT', 6, 10, null) like '23514:%follow its current version%'
    and pg_temp.insert_version('EDIT', 7, 11, null) like '23514:Only the original author%'
    and pg_temp.insert_timed_entry() like '22023:%no clinical event time%'
    and pg_temp.edits(pg_temp.e('E1')) = 5
    and (select count(*) = 0 from public.clinical_record_entries where appointment_id = pg_temp.appt(7)),
    'EDT structure: only the author''s next EDIT version can be appended, without gaps or duplicates; no reason-and-addition row and no Entry with an event time can be written'
);

select pg_temp.assert_true(
    not has_table_privilege('authenticated', 'public.clinical_amendments', 'INSERT')
    and not has_table_privilege('authenticated', 'public.clinical_amendments', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.clinical_amendments', 'DELETE')
    and not has_table_privilege('anon', 'public.clinical_amendments', 'SELECT')
    and not has_table_privilege('authenticated', 'public.clinical_record_entries', 'INSERT')
    and not has_table_privilege('authenticated', 'public.clinical_record_entries', 'UPDATE'),
    'EDT immutability: no client role writes versions or Entries directly'
);

rollback;

-- Zero retained fixture rows after rollback.
do $$
declare t record; n bigint; begin
    for t in select table_schema, table_name from information_schema.columns
             where table_schema in ('public', 'auth') and column_name = 'id' loop
        execute format('select count(*) from %I.%I where id::text like %L', t.table_schema, t.table_name, 'd0350000-%')
        into n;
        if n <> 0 then raise exception 'Retained fixtures in %.%', t.table_schema, t.table_name; end if;
    end loop;
end $$;

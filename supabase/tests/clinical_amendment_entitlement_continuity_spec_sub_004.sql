-- Correction continuity after Entitlement loss: SPEC-SUB-004 BR-20 / BR-21,
-- SPEC-MED-010 BR-13 (every new Entry requires CLINICAL_CARE) and BR-18 (the
-- author edits without an Entitlement). Migrations
-- 20261031090000_subscription_operational_safety.sql,
-- 20261113090000_appointment_owned_clinical_documentation.sql and
-- 20261116090000_editable_clinical_record_versions.sql.
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The clinical context is loaded as data with establishment triggers bypassed
-- (as in appointment_clinical_record_spec_med_010.sql); every
-- behavioural call goes through the real operations as the impersonated
-- User, and deferred integrity is flushed after each call. Commercial state
-- changes go through the real trusted transition operation. Mutants are
-- pinned by run_subscription_safety_faults.py. Fixture prefix d0311000-.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0311000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end $$;
-- Runs one statement as the impersonated User: 'OK:<value>' or
-- 'ERR:<sqlstate>:<message>'.
create function pg_temp.attempt(actor integer, statement text) returns text language plpgsql as $$
declare result text; begin
    perform pg_temp.act(actor);
    execute 'set local role authenticated';
    execute statement into result;
    perform pg_temp.flush();
    execute 'reset role';
    return 'OK:' || coalesce(result, 'null');
exception when others then
    return 'ERR:' || sqlstate || ':' || sqlerrm;
end $$;
-- An edit through the client operation (SPEC-MED-010 BR-23b), on the version
-- the editor was opened on.
create function pg_temp.edit(actor integer, entry uuid, content text, key_n integer, expected integer)
returns text language sql as $$
    select pg_temp.attempt(actor, format(
        'select public.edit_appointment_clinical_entry(%L, %L, %L, %L, %s, %L, %L, null)::text',
        pg_temp.id(4, 1), pg_temp.id(11, 1), entry, pg_temp.id(20, key_n), expected, 'EXAMINATION', content))
$$;
-- A new Entry through the client record operation (SPEC-MED-010 BR-23).
create function pg_temp.new_entry(actor integer, appointment_n integer, key_n integer) returns text language sql as $$
    select pg_temp.attempt(actor, format(
        'select public.create_appointment_clinical_entry(%L, %L, %L, %L, %L, null)::text',
        pg_temp.id(4, 1), pg_temp.id(11, appointment_n), pg_temp.id(21, key_n), 'EXAMINATION', 'Weight 12 kg'))
$$;
create function pg_temp.lapse(target text, effective timestamptz) returns void language plpgsql as $$
declare sub uuid; begin
    select id into sub from public.organization_subscriptions where organization_id = pg_temp.id(3, 1);
    perform public.apply_subscription_state_transition(sub, target, effective, null, null, 'amendment-suite', null);
    perform pg_temp.flush();
end $$;
-- Every fact of the original Entry and of its Appointment.
create function pg_temp.history_facts(entry uuid) returns text language sql as $$
    select md5(
        (select to_jsonb(e)::text from public.clinical_record_entries e where e.id = entry)
        || (select to_jsonb(a)::text from public.appointments a
            where a.id = (select appointment_id from public.clinical_record_entries where id = entry)))
$$;

-- ===========================================================================
-- Fixtures. Organization A (3,1) Clinic 1 (4,1); Organization B (3,2) Clinic 3 (4,3).
--  1 Guardian of Luna            5 Organization Administrator of A
--  8 Clinic Receptionist of A    10 Veterinarian, current Assignment at Clinic 1
-- 14 Veterinarian whose Clinic 1 Assignment ended   16 Receptionist with a Profile
--    and a Clinic 1 Assignment (no VETERINARIAN responsibility)
-- 17 Veterinarian of Organization B (Clinic 3)
-- Appointments 1 and 2: COMPLETED at Clinic 1 with ACTIVE Care Authorizations.
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'amend-' || n || '@example.test', '2020-01-01Z' from unnest(array[1, 5, 8, 10, 14, 16, 17]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 5, 8, 10, 14, 16, 17]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 5, 8, 10, 14, 16, 17]) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'Amend Org A'), (pg_temp.id(3, 2), 'Amend Org B');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.id(4, 1), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.id(4, 3), pg_temp.id(3, 2), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 17 then 2 else 1 end), pg_temp.id(2, n), '2020-01-01Z'
from unnest(array[5, 8, 10, 14, 16, 17]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case n when 5 then 'ADMINISTRATOR' when 8 then 'RECEPTIONIST' when 16 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n = 8 then 'CLINIC' else 'ORGANIZATION' end, case when n = 8 then pg_temp.id(4, 1) end,
    '2020-01-01Z', pg_temp.id(2, 5)
from unnest(array[5, 8, 10, 14, 16, 17]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id(7, n), pg_temp.id(2, n) from unnest(array[10, 14, 16, 17]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start, effective_end)
values (pg_temp.id(8, 10), pg_temp.id(7, 10), pg_temp.id(5, 10), pg_temp.id(4, 1), '2020-01-01Z', null),
       (pg_temp.id(8, 14), pg_temp.id(7, 14), pg_temp.id(5, 14), pg_temp.id(4, 1), '2020-01-01Z', '2026-06-10Z'),
       (pg_temp.id(8, 16), pg_temp.id(7, 16), pg_temp.id(5, 16), pg_temp.id(4, 1), '2020-01-01Z', null),
       (pg_temp.id(8, 17), pg_temp.id(7, 17), pg_temp.id(5, 17), pg_temp.id(4, 3), '2020-01-01Z', null);
insert into public.pets (id, name, species, created_at) values (pg_temp.id(9, 1), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (pg_temp.id(9, 11), pg_temp.id(2, 1), pg_temp.id(9, 1), '2020-01-01Z');
-- Completed Appointments, as Lightweight Complete leaves them (MED-001 suite).
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.id(11, n), pg_temp.id(9, 1), pg_temp.id(4, 1), pg_temp.id(2, 1), 'Visit ' || n, 'COMPLETED',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from unnest(array[1, 2]) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select pg_temp.id(11, n), r, case r when 1 then 'REQUESTED' else 'CONFIRMED' end, '2026-06-01T10:00Z',
    '2026-06-01T10:30Z', 'Europe/Madrid', pg_temp.id(2, case r when 1 then 1 else 8 end), null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from unnest(array[1, 2]) n, unnest(array[1, 2]) r;
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select pg_temp.id(12, n), pg_temp.id(9, 1), pg_temp.id(4, 1), pg_temp.id(3, 1), pg_temp.id(9, 11),
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE', pg_temp.id(11, n), 'ACTIVE'
from unnest(array[1, 2]) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select pg_temp.id(11, n), f, t, pg_temp.id(2, 8), 'CLINIC', null, e, e
from unnest(array[1, 2]) n,
     (values ('REQUESTED', 'CONFIRMED', '2026-02-01T00:00:00Z'::timestamptz),
             ('CONFIRMED', 'COMPLETED', '2026-06-01T11:00Z'::timestamptz)) as event(f, t, e);
set local session_replication_role = origin;

select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'amendment-suite', pg_temp.id(20, 1), null) is not null as established_a,
       public.establish_organization_subscription(pg_temp.id(3, 2), null, 'ACTIVE', '2020-01-01Z', null, null,
    'amendment-suite', pg_temp.id(20, 2), null) is not null as established_b;
select pg_temp.flush();

-- ===========================================================================
-- While entitled: a recorded Entry and a baseline Amendment
-- ===========================================================================

-- Veterinarian 10 is the assigned Veterinarian of both COMPLETED Appointments
-- (SPEC-APT-007 §13 accepts COMPLETED).
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select pg_temp.id(11, n), pg_temp.id(8, 10), clock_timestamp(), pg_temp.id(2, 8) from unnest(array[1, 2]) n;
select pg_temp.flush();

create temporary table clinical (label text primary key, value uuid) on commit drop;
grant all on clinical to authenticated;
do $$
declare outcome text; begin
    outcome := pg_temp.new_entry(10, 1, 1);
    perform pg_temp.assert_true(outcome like 'OK:%' and (substr(outcome, 4)::jsonb ->> 'outcome') = 'CREATED',
        'Positive control: an entitled assigned Veterinarian records an Entry: ' || outcome);
    insert into clinical values ('entry', (substr(outcome, 4)::jsonb ->> 'entry_id')::uuid);
    outcome := pg_temp.edit(10, (select value from clinical where label = 'entry'), 'Weight 12.4 kg', 1, 1);
    perform pg_temp.assert_true(outcome = 'OK:{"outcome": "EDITED", "version": 2}',
        'Positive control: an entitled author edits: ' || outcome);
end $$;

create temporary table remembered on commit drop as
    select pg_temp.history_facts((select value from clinical where label = 'entry')) as facts;

-- ===========================================================================
-- After Entitlement loss (PAST_DUE)
-- ===========================================================================

select pg_temp.lapse('PAST_DUE', statement_timestamp());

do $$
declare entry uuid := (select value from clinical where label = 'entry'); outcome text; replay text; begin
    perform pg_temp.assert_true(
        not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_DOCUMENTATION')
        and not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_CARE'),
        'Precondition: the Organization has lost its clinical Entitlements');

    outcome := pg_temp.new_entry(10, 2, 2);
    perform pg_temp.assert_true(outcome = 'ERR:42501:Clinical care is currently unavailable for this Organization'
        and not exists (select 1 from public.clinical_record_entries where appointment_id = pg_temp.id(11, 2)),
        'Lapse cannot record a new Entry (SPEC-MED-010 BR-13)');
    perform pg_temp.assert_true(
        pg_temp.new_entry(10, 1, 3) = 'ERR:42501:Clinical care is currently unavailable for this Organization'
        and (select count(*) = 1 from public.clinical_record_entries where appointment_id = pg_temp.id(11, 1)),
        'Lapse cannot record a further Entry on an already documented Appointment (BR-13 supersedes SPEC-SUB-004 BR-17/BR-18)');

    outcome := pg_temp.edit(10, entry, 'Weight 12.6 kg after recalibration', 2, 2);
    perform pg_temp.assert_true(outcome = 'OK:{"outcome": "EDITED", "version": 3}',
        'An authorized author edits after Entitlement loss');
    perform pg_temp.assert_true(
        (select a.original_clinical_record_entry_id = entry and a.amending_user_id = pg_temp.id(2, 10)
                and a.amending_veterinarian_clinic_assignment_id = pg_temp.id(8, 10)
                and a.change_kind = 'EDIT' and a.version_number = 3
                and a.amendment_content = 'Weight 12.6 kg after recalibration'
         from public.clinical_amendments a
         where a.original_clinical_record_entry_id = entry and a.idempotency_key = pg_temp.id(20, 2))
        and pg_temp.history_facts(entry) = (select facts from remembered)
        and (select count(*) = 2 from public.clinical_amendments where original_clinical_record_entry_id = entry),
        'The edit is appended as the next version with its own provenance and the original history is unchanged');

    replay := pg_temp.edit(10, entry, 'Weight 12.6 kg after recalibration', 2, 2);
    perform pg_temp.assert_true(replay = 'OK:{"outcome": "ALREADY_EDITED", "version": 3}'
        and (select count(*) = 2 from public.clinical_amendments where original_clinical_record_entry_id = entry),
        'Edit idempotency is unchanged after Entitlement loss');
    perform pg_temp.assert_true(pg_temp.edit(10, entry, 'Different content', 2, 2) like 'ERR:23505:%',
        'Contradictory edit key reuse is still rejected');

    perform pg_temp.assert_true(
        pg_temp.edit(14, entry, 'Ended assignment', 3, 3) like 'ERR:42501:%'
        and pg_temp.edit(16, entry, 'Receptionist', 4, 3) like 'ERR:42501:%'
        and pg_temp.edit(17, entry, 'Other Organization', 5, 3) like 'ERR:42501:%'
        and pg_temp.edit(5, entry, 'Administrator', 6, 3) like 'ERR:42501:%'
        and pg_temp.edit(1, entry, 'Guardian', 7, 3) like 'ERR:42501:%'
        and pg_temp.edit(0, entry, 'Anonymous', 8, 3) like 'ERR:28000:%'
        and (select count(*) = 2 from public.clinical_amendments where original_clinical_record_entry_id = entry),
        'Edit continuity still requires a current Veterinarian context');
end $$;

-- EXPIRED: editing survives; new care still does not.
select pg_temp.lapse('EXPIRED', statement_timestamp());

do $$
declare entry uuid := (select value from clinical where label = 'entry'); history jsonb; begin
    perform pg_temp.assert_true(pg_temp.edit(10, entry, 'Weight 12.5 kg confirmed', 9, 3) = 'OK:{"outcome": "EDITED", "version": 4}'
        and pg_temp.new_entry(10, 2, 4) = 'ERR:42501:Clinical care is currently unavailable for this Organization'
        and pg_temp.history_facts(entry) = (select facts from remembered),
        'After EXPIRED an edit is still possible and a new Entry is not');

    perform pg_temp.act(1);
    history := public.view_guardian_pet_medical_history(pg_temp.id(9, 1));
    perform pg_temp.assert_true(history ->> 'status' = 'PERMITTED'
        and (history -> 'payload' -> 'entries' -> 0 ->> 'id')::uuid = entry
        and history -> 'payload' -> 'entries' -> 0 ->> 'clinical_content' = 'Weight 12.5 kg confirmed'
        and (history -> 'payload' -> 'entries' -> 0 ->> 'version')::integer = 4
        and jsonb_array_length(history -> 'payload' -> 'entries' -> 0 -> 'previous_versions') = 3
        and (history -> 'payload' -> 'entries' -> 0 ->> 'amendment_count')::integer = 0
        and history::text not like '%EXPIRED%',
        'Guardian history shows the current version with every earlier one after the lapse');
end $$;

rollback;

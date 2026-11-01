-- Appointment-owned clinical documentation: SPEC-MED-010 §12 Verification
-- Notes 1–27, BR-18/BR-23b editing, SPEC-APT-007 §13 authorship. Migrations
-- 20261113090000_appointment_owned_clinical_documentation.sql (M2),
-- 20261114090000_appointment_completion_ends_care_authorization.sql (M3) and
-- 20261116090000_editable_clinical_record_versions.sql (M5).
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The organizational and scheduling context is loaded as data with triggers
-- bypassed; every behavioural call goes through the client operations as the
-- impersonated User under the authenticated role, and deferred integrity is
-- flushed after each call. Genuine two-session races are covered by
-- run_clinical_record_concurrency.py; mutants by
-- run_appointment_clinical_record_faults.py. Fixture prefix d0400000-.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0400000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.clinic(n integer) returns uuid language sql immutable as $$ select pg_temp.id(4, n) $$;
create function pg_temp.appt(n integer) returns uuid language sql immutable as $$ select pg_temp.id(11, n) $$;
create function pg_temp.ca(n integer) returns uuid language sql immutable as $$ select pg_temp.id(12, n) $$;
create function pg_temp.vca(n integer) returns uuid language sql immutable as $$ select pg_temp.id(8, n) $$;
create function pg_temp.domain_user(n integer) returns uuid language sql immutable as $$ select pg_temp.id(2, n) $$;
create function pg_temp.key(n integer) returns uuid language sql immutable as $$ select pg_temp.id(13, n) $$;
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
-- "Guardar registro": the canonical record operation; no clinical time is sent.
create function pg_temp.record(actor integer, appointment_n integer, key_n integer,
    category text default 'CLINICAL_NOTE', content text default 'Healthy, routine check',
    other_context text default null, clinic_n integer default 1) returns text language sql as $$
    select pg_temp.call(actor, format(
        'select public.create_appointment_clinical_entry(%L, %L, %L, %L, %L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n), pg_temp.key(key_n), category, content,
        other_context))
$$;
-- "Guardar cambios" (BR-23b) on the version the editor was opened on.
create function pg_temp.edit(actor integer, appointment_n integer, entry uuid, key_n integer,
    expected integer default 1, category text default 'CLINICAL_NOTE', content text default 'Corrected dose',
    clinic_n integer default 1) returns text language sql as $$
    select pg_temp.call(actor, format(
        'select public.edit_appointment_clinical_entry(%L, %L, %L, %L, %L, %L, %L, null)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n), entry, pg_temp.id(14, key_n), expected,
        category, content))
$$;
-- Stored versions after the first (kind EDIT) of one Entry.
create function pg_temp.edits(entry uuid) returns bigint language sql as $$
    select count(*) from public.clinical_amendments
    where original_clinical_record_entry_id = entry and change_kind = 'EDIT'
$$;
create function pg_temp.read(actor integer, appointment_n integer, clinic_n integer default 1) returns jsonb
language sql as $$
    select pg_temp.j(pg_temp.call(actor, format('select public.view_appointment_clinical_record(%L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.history(actor integer, appointment_n integer, clinic_n integer default 1) returns jsonb
language sql as $$
    select pg_temp.j(pg_temp.call(actor, format(
        'select public.view_appointment_professional_medical_history(%L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.guardian_history(actor integer) returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(actor, format('select public.view_guardian_pet_medical_history(%L)::text',
        pg_temp.luna())))
$$;
-- Trusted fixture (security definer): the current assignment of Appointment
-- n becomes the given Clinic Assignment. The client paths are covered by
-- appointment_veterinarian_assignment_spec_apt_007.sql.
create function pg_temp.assign(appointment_n integer, vca_n integer) returns void
language plpgsql security definer as $$
declare current_id uuid; current_vca uuid; begin
    select id, veterinarian_clinic_assignment_id into current_id, current_vca
    from public.appointment_veterinarian_assignments
    where appointment_id = pg_temp.appt(appointment_n) and effective_end is null;
    perform public.establish_appointment_veterinarian_period(
        pg_temp.appt(appointment_n), (select lifecycle_state from public.appointments where id = pg_temp.appt(appointment_n)),
        current_id, current_vca, pg_temp.vca(vca_n), pg_temp.domain_user(8));
    perform pg_temp.flush();
end $$;
create function pg_temp.audits() returns bigint language sql as $$
    select count(*) from public.medical_access_audit_events where pet_id = pg_temp.luna()
$$;
create function pg_temp.entries(appointment_n integer) returns bigint language sql as $$
    select count(*) from public.clinical_record_entries where appointment_id = pg_temp.appt(appointment_n)
$$;
create function pg_temp.entries_by_id(appointment uuid) returns bigint language sql as $$
    select count(*) from public.clinical_record_entries where appointment_id = appointment
$$;
create function pg_temp.entry(entry uuid) returns public.clinical_record_entries language sql as $$
    select * from public.clinical_record_entries where id = entry
$$;
create function pg_temp.state(appointment_n integer) returns text language sql as $$
    select lifecycle_state from public.appointments where id = pg_temp.appt(appointment_n)
$$;
create temporary table facts (label text primary key, outcome text, at timestamptz) on commit drop;
create function pg_temp.keep(label text, outcome text) returns text language sql as $$
    insert into facts values (label, outcome, statement_timestamp()) returning outcome
$$;
create function pg_temp.fact(label text) returns jsonb language sql as $$
    select pg_temp.j(outcome) from facts where facts.label = fact.label
$$;
create function pg_temp.raw(label text) returns text language sql as $$
    select outcome from facts where facts.label = raw.label
$$;
create function pg_temp.entry_id(label text) returns uuid language sql as $$
    select (pg_temp.fact(label) ->> 'entry_id')::uuid
$$;
-- Every clinical fact, for "nothing is written" assertions.
create function pg_temp.clinical_facts() returns text language sql as $$
    select md5(
        coalesce((select string_agg(to_jsonb(e)::text, '|' order by e.id) from public.clinical_record_entries e), '')
        || '#' || coalesce((select string_agg(to_jsonb(a)::text, '|' order by a.id) from public.clinical_amendments a), '')
        || '#' || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.clinical_attachments t), ''))
$$;
create function pg_temp.appointment_facts(appointment_n integer) returns text language sql as $$
    select md5(
        (select to_jsonb(a)::text from public.appointments a where a.id = pg_temp.appt(appointment_n))
        || '#' || coalesce((select string_agg(to_jsonb(r)::text, '|' order by r.id) from public.appointment_schedule_revisions r
                            where r.appointment_id = pg_temp.appt(appointment_n)), '')
        || '#' || coalesce((select string_agg(to_jsonb(e)::text, '|' order by e.id) from public.appointment_lifecycle_events e
                            where e.appointment_id = pg_temp.appt(appointment_n)), '')
        || '#' || coalesce((select string_agg(to_jsonb(c)::text, '|' order by c.id) from public.care_authorizations c
                            where c.appointment_id = pg_temp.appt(appointment_n)), '')
        || '#' || coalesce((select string_agg(to_jsonb(v)::text, '|' order by v.id) from public.appointment_veterinarian_assignments v
                            where v.appointment_id = pg_temp.appt(appointment_n)), ''))
$$;

-- ===========================================================================
-- Fixture (data load, triggers bypassed)
--  1 Guardian of Luna      5 Administrator of A      8 Receptionist of Clinic 1
-- 10 Veterinarian A at Clinic 1     11 Veterinarian B at Clinic 1
-- 12 Veterinarian C at Clinic 1 (offboarded in-suite)
-- 17 Veterinarian of Organization B (Clinic 3)   18 Veterinarian at Clinic 2
-- Appointments at Clinic 1 unless noted, one per day from 2026-06-01T10:00Z
-- (Appointment 2 on 2035-06-02), confirmed 2026-02-01; COMPLETED ones
-- completed one hour after their start:
--   CONFIRMED 1 2 8* 10 12 13 14 17 18 19 20 21   COMPLETED 3
--   REQUESTED 4 (future)   CANCELLED 5   NO_SHOW 6   EXPIRED 7
--   8*: CONFIRMED without its REQUESTED -> CONFIRMED Event (never confirmed)
--   9: CONFIRMED at Clinic 2.  15: CONFIRMED at Clinic 3 (Organization B).
--   10: its Care Authorization is revoked before any record.
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'acr-' || n || '@example.test', '2020-01-01Z' from unnest(array[1, 5, 8, 10, 11, 12, 17, 18]) n;
insert into public.users (id) select pg_temp.domain_user(n) from unnest(array[1, 5, 8, 10, 11, 12, 17, 18]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.domain_user(n), pg_temp.id(1, n) from unnest(array[1, 5, 8, 10, 11, 12, 17, 18]) n;
insert into public.user_profiles (user_id, display_name)
select pg_temp.domain_user(n), 'Vet ' || n from unnest(array[10, 11, 12]) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'ACR Org A'), (pg_temp.id(3, 2), 'ACR Org B');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.clinic(1), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(2), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(3), pg_temp.id(3, 2), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.clinic_public_profiles (clinic_id, display_name) values
    (pg_temp.clinic(1), 'Clinic One'), (pg_temp.clinic(2), 'Clinic Two'), (pg_temp.clinic(3), 'Clinic Three');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n), pg_temp.id(3, case when n = 17 then 2 else 1 end), pg_temp.domain_user(n), '2020-01-01Z'
from unnest(array[5, 8, 10, 11, 12, 17, 18]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case n when 5 then 'ADMINISTRATOR' when 8 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n = 8 then 'CLINIC' else 'ORGANIZATION' end, case when n = 8 then pg_temp.clinic(1) end,
    '2020-01-01Z', pg_temp.domain_user(5)
from unnest(array[5, 8, 10, 11, 12, 17, 18]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id(7, n), pg_temp.domain_user(n) from unnest(array[10, 11, 12, 17, 18]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start, effective_end)
values (pg_temp.vca(10), pg_temp.id(7, 10), pg_temp.id(5, 10), pg_temp.clinic(1), '2020-01-01Z', null),
       (pg_temp.vca(11), pg_temp.id(7, 11), pg_temp.id(5, 11), pg_temp.clinic(1), '2020-01-01Z', null),
       (pg_temp.vca(12), pg_temp.id(7, 12), pg_temp.id(5, 12), pg_temp.clinic(1), '2020-01-01Z', null),
       (pg_temp.vca(17), pg_temp.id(7, 17), pg_temp.id(5, 17), pg_temp.clinic(3), '2020-01-01Z', null),
       (pg_temp.vca(18), pg_temp.id(7, 18), pg_temp.id(5, 18), pg_temp.clinic(2), '2020-01-01Z', null);
insert into public.pets (id, name, species, created_at) values (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (pg_temp.id(9, 11), pg_temp.domain_user(1), pg_temp.luna(), '2020-01-01Z');
create temporary table seed (n integer primary key, state text, clinic_n integer, start_at timestamptz) on commit drop;
insert into seed
select n,
       case when n = 3 then 'COMPLETED' when n = 4 then 'REQUESTED' when n = 5 then 'CANCELLED'
            when n = 6 then 'NO_SHOW' when n = 7 then 'EXPIRED' else 'CONFIRMED' end,
       case when n = 9 then 2 when n = 15 then 3 else 1 end,
       case when n = 2 then '2035-06-02T10:00Z'::timestamptz
            when n = 4 then '2035-06-04T10:00Z'::timestamptz
            else '2026-06-01T10:00Z'::timestamptz + make_interval(days => n - 1) end
from generate_series(1, 21) n;
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.appt(n), pg_temp.luna(), pg_temp.clinic(clinic_n), pg_temp.domain_user(1), 'Visit ' || n, state,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from seed;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select pg_temp.appt(n), r, case r when 1 then 'REQUESTED' else 'CONFIRMED' end, start_at,
    start_at + interval '30 minutes', 'Europe/Madrid', pg_temp.domain_user(case r when 1 then 1 else 8 end), null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from seed, unnest(array[1, 2]) r
where r = 1 or seed.state not in ('REQUESTED', 'EXPIRED');
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state, ended_at, ended_reason)
select pg_temp.ca(n), pg_temp.luna(), pg_temp.clinic(clinic_n), pg_temp.id(3, case when clinic_n = 3 then 2 else 1 end),
    pg_temp.id(9, 11), '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE', pg_temp.appt(n),
    -- Every terminal Appointment, COMPLETED included (M3), ended its
    -- authorization at its terminal Event.
    case when state in ('CANCELLED', 'NO_SHOW', 'EXPIRED', 'COMPLETED') then 'ENDED' else 'ACTIVE' end,
    case when state = 'EXPIRED' then start_at
         when state in ('CANCELLED', 'NO_SHOW', 'COMPLETED') then start_at + interval '1 hour' end,
    case state when 'CANCELLED' then 'APPOINTMENT_CANCELLED' when 'NO_SHOW' then 'APPOINTMENT_NO_SHOW'
               when 'EXPIRED' then 'APPOINTMENT_EXPIRED' when 'COMPLETED' then 'APPOINTMENT_COMPLETED' end
from seed;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select pg_temp.appt(n), 'REQUESTED', 'CONFIRMED', pg_temp.domain_user(8), 'CLINIC', null::text,
    '2026-02-01Z'::timestamptz, '2026-02-01Z'::timestamptz
from seed where state not in ('REQUESTED', 'EXPIRED') and n <> 8
union all
select pg_temp.appt(n), 'CONFIRMED', to_state, pg_temp.domain_user(8), 'CLINIC',
    case when to_state = 'CANCELLED' then 'Clinic closed' end, start_at + interval '1 hour', start_at + interval '1 hour'
from (select n, start_at, state as to_state from seed where state in ('COMPLETED', 'CANCELLED', 'NO_SHOW')) as terminal
union all
select pg_temp.appt(n), 'REQUESTED', 'EXPIRED', null, 'SYSTEM', null::text, start_at, start_at
from seed where state = 'EXPIRED';
set local session_replication_role = origin;

select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'appointment-clinical-record-suite', pg_temp.id(20, 1), null) is not null as established_a,
       public.establish_organization_subscription(pg_temp.id(3, 2), null, 'ACTIVE', '2020-01-01Z', null, null,
    'appointment-clinical-record-suite', pg_temp.id(20, 2), null) is not null as established_b;
select pg_temp.flush();
-- 10: a current Guardian revoked the Appointment Care Authorization before any record.
select pg_temp.call(1, format('select public.revoke_my_appointment_care_authorization(%L)::text', pg_temp.appt(10)));
select pg_temp.assert_true(
    (select lifecycle_state = 'REVOKED' from public.care_authorizations where id = pg_temp.ca(10)),
    'Fixture: Appointment 10 Care Authorization is REVOKED'
);
-- Assignments: Veterinarian A on 1 2 3 8 10 12 17 18 19 20 21; C on 13; 9 and 15
-- to their own Clinic's Veterinarian; 14 has none.
select pg_temp.assign(n, 10) from unnest(array[1, 2, 3, 10, 12, 17, 18, 19, 20, 21]) n;
select pg_temp.assign(13, 12);
select pg_temp.assign(9, 18);
select pg_temp.assign(15, 17);
-- 4/5/6/7/8: assignments never establish a documentable state; 8 is assigned
-- as data to show that only the confirmation history decides.
set local session_replication_role = replica;
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select pg_temp.appt(n), pg_temp.vca(10), '2026-03-01Z', pg_temp.domain_user(8) from unnest(array[4, 5, 6, 7, 8]) n;
set local session_replication_role = origin;

-- ===========================================================================
-- 1. Contract, ACL, schema, retired model (notes 1, 21)
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.proconfig = array['search_path=""']
                     and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                     and not has_function_privilege('anon', proc.oid, 'EXECUTE')
                     and not has_function_privilege('service_role', proc.oid, 'EXECUTE'))
       and count(*) = 3
     from pg_proc as proc
     where proc.oid in ('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text)'::regprocedure,
                        'public.view_appointment_clinical_record(uuid,uuid)'::regprocedure,
                        'public.edit_appointment_clinical_entry(uuid,uuid,uuid,uuid,integer,text,text,text)'::regprocedure)),
    'Contract: record, read and edit are SECURITY DEFINER, empty search_path, authenticated-only'
);

select pg_temp.assert_true(
    (select pg_get_function_result(oid) = 'jsonb' and pronargdefaults = 0
            and not exists (select 1 from unnest(proargnames) as name where name like '%event%')
     from pg_proc where oid = 'public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text)'::regprocedure)
    and (select count(*) = 1 from pg_proc where pronamespace = 'public'::regnamespace
         and proname = 'create_appointment_clinical_entry'),
    'Contract: one record operation returning jsonb, without defaults; it accepts no clinical time (BR-5)'
);

-- Note 21: no retired operation exists or is executable by any client role.
select pg_temp.assert_true(
    (select bool_and(to_regprocedure(signature) is null)
     from unnest(array[
        'public.start_appointment_clinical_encounter(uuid,uuid,timestamptz)',
        'public.conclude_appointment_clinical_encounter(uuid,uuid)',
        'public.create_appointment_clinical_draft(uuid,uuid,uuid,text,text,text,timestamptz)',
        'public.update_appointment_clinical_draft(uuid,uuid,uuid,bigint,text,text,text,timestamptz)',
        'public.finalize_appointment_clinical_entry(uuid,uuid,uuid,bigint)',
        'public.create_clinical_encounter(uuid,timestamptz,uuid)',
        'public.conclude_clinical_encounter(uuid)',
        'public.create_draft_clinical_record_entry(uuid,text,text,text,timestamptz)',
        'public.update_draft_clinical_record_entry(uuid,bigint,text,text,text,timestamptz)',
        'public.finalize_clinical_record_entry(uuid,bigint)',
        'public.view_care_authorization_clinical_work_context(uuid,uuid,integer,timestamptz,uuid)',
        'public.view_professional_pet_medical_history(uuid,uuid,uuid,uuid,integer,timestamptz,uuid)',
        'public.view_clinical_record_entry(uuid)',
        'public.appointment_clinical_care_window(uuid)',
        'public.assert_clinical_draft_fields(text,text,timestamptz)',
        'public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)',
        'public.create_appointment_clinical_amendment(uuid,uuid,uuid,uuid,text,text)',
        'public.create_clinical_amendment(uuid,text,text,uuid)'
     ]) as signature)
    and not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                    and (proname like '%encounter%' or proname like '%clinical_draft%'
                         or proname like '%draft_clinical_record%' or proname like 'slice12_view%'))
    and not has_function_privilege('authenticated', 'public.get_professional_pet_active_care_authorizations(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.get_professional_pet_active_care_authorizations(uuid,uuid)', 'EXECUTE'),
    'Note 21: every retired Encounter, Draft and Finalize operation, the Encounter-keyed reads, the timed record operation and the reason-and-addition operations are gone; the active-authorization list is no client path'
);

select pg_temp.assert_true(
    (select bool_and(not has_function_privilege(role_name, signature::regprocedure, 'EXECUTE'))
     from unnest(array[
        'public.appointment_accepts_clinical_documentation(uuid,text)',
        'public.assert_clinical_entry_fields(text,text,text,timestamptz)',
        'public.clinical_history_page(uuid,integer,timestamptz,uuid)',
        'public.establish_medical_access_audit_event(uuid,uuid,text,text,text,text,timestamptz,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid)',
        'public.appointment_veterinarian_is_eligible(uuid,uuid)',
        'public.establish_appointment_veterinarian_period(uuid,text,uuid,uuid,uuid,uuid)',
        'public.lock_clinical_actor_context(uuid,uuid,text)',
        'public.clinical_actor_context_at(uuid,uuid,text)',
        'public.clinical_entry_versions(uuid)',
        'public.clinical_entry_current(uuid)',
        'public.clinical_entry_previous_versions(uuid)'
     ]) as signature, unnest(array['anon', 'authenticated']) as role_name)
    and not has_function_privilege('authenticated', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'EXECUTE'),
    'Contract: private helpers and trusted writers are not client-executable'
);

-- Note 1 (BR-1): no Encounter exists anywhere in the schema.
select pg_temp.assert_true(
    to_regclass('public.clinical_encounters') is null
    and to_regclass('public.clinical_record_entry_contributors') is null
    and not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and column_name like '%encounter%')
    and (select is_nullable = 'NO' from information_schema.columns
         where table_schema = 'public' and table_name = 'clinical_record_entries' and column_name = 'appointment_id')
    and not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'clinical_record_entries'
                      and column_name in ('lifecycle_state', 'draft_revision', 'finalized_at', 'finalized_by_user_id',
                                          'finalizer_veterinarian_clinic_assignment_id', 'last_modified_at'))
    and exists (select 1 from pg_constraint where conrelid = 'public.clinical_record_entries'::regclass
                and contype = 'u' and pg_get_constraintdef(oid) = 'UNIQUE (created_by_user_id, creation_idempotency_key)'),
    'Note 1: Entries reference their Appointment (NOT NULL); no Encounter, Draft, finalization or contributor fact remains'
);

-- Note 21: an Encounter can no longer be created by any path.
select pg_temp.assert_true(
    pg_temp.call(10, 'select public.start_appointment_clinical_encounter(null, null, null)::text') like 'ERR:42883:%'
    and pg_temp.call(10, 'select public.create_clinical_encounter(null, null, null)::text') like 'ERR:42883:%',
    'Note 21: the Encounter operations do not exist for clients'
);

-- ===========================================================================
-- 2. Recording (notes 1, 4, 6, 7, 14, 18; BR-8)
-- ===========================================================================

create temporary table baseline_1 on commit drop as select pg_temp.appointment_facts(1) as facts, pg_temp.audits() as audits;
select pg_temp.keep('e1', pg_temp.record(10, 1, 1, 'DIAGNOSIS', '  Otitis externa  '));
select pg_temp.assert_true(
    pg_temp.fact('e1') ->> 'outcome' = 'CREATED'
    and (select array_agg(key order by key) from jsonb_object_keys(pg_temp.fact('e1')) as key) = array['entry_id', 'outcome']
    and (pg_temp.entry(pg_temp.entry_id('e1'))).appointment_id = pg_temp.appt(1)
    and (pg_temp.entry(pg_temp.entry_id('e1'))).created_by_user_id = pg_temp.domain_user(10)
    and (pg_temp.entry(pg_temp.entry_id('e1'))).creator_veterinarian_clinic_assignment_id = pg_temp.vca(10)
    and (pg_temp.entry(pg_temp.entry_id('e1'))).clinical_content = 'Otitis externa'
    and (pg_temp.entry(pg_temp.entry_id('e1'))).category = 'DIAGNOSIS'
    and (pg_temp.entry(pg_temp.entry_id('e1'))).clinical_event_at is null
    and (pg_temp.entry(pg_temp.entry_id('e1'))).created_at between (select at from facts where label = 'e1') and clock_timestamp()
    and (pg_temp.entry(pg_temp.entry_id('e1'))).creation_idempotency_key = pg_temp.key(1),
    'Notes 1/BR-5/BR-6a: the assigned Veterinarian records a CONFIRMED Appointment after its start; authorship, trimmed content and the server recording time, with no event time, are stored; the result carries only outcome and entry_id'
);
select pg_temp.assert_true(
    pg_temp.appointment_facts(1) = (select facts from baseline_1)
    and pg_temp.audits() = (select audits from baseline_1),
    'BR-8/BR-21: recording changes no Appointment, schedule, Lifecycle, Care Authorization or assignment fact and creates no audit event'
);

-- Before the scheduled start (2035) and on a COMPLETED Appointment.
select pg_temp.keep('e2', pg_temp.record(10, 2, 2));
select pg_temp.keep('e3', pg_temp.record(10, 3, 3, 'TREATMENT', 'Ear drops'));
select pg_temp.assert_true(
    pg_temp.fact('e2') ->> 'outcome' = 'CREATED' and pg_temp.state(2) = 'CONFIRMED'
    and (pg_temp.entry(pg_temp.entry_id('e2'))).clinical_event_at is null
    and pg_temp.fact('e3') ->> 'outcome' = 'CREATED' and pg_temp.state(3) = 'COMPLETED',
    'Note 1: a CONFIRMED Appointment is documentable before its scheduled start and a COMPLETED one after completion; no event time is recorded'
);

-- Note 6: field rules, each writing nothing.
create temporary table baseline_fields on commit drop as select pg_temp.clinical_facts() as facts;
select pg_temp.assert_true(
    pg_temp.record(10, 1, 900, null) like 'ERR:22023:CATEGORY_REQUIRED:%'
    and pg_temp.record(10, 1, 900, 'SURGERY') like 'ERR:22023:INVALID_CATEGORY:%'
    and pg_temp.record(10, 1, 900, 'CLINICAL_NOTE', '   ') like 'ERR:22023:CONTENT_REQUIRED:%'
    and pg_temp.record(10, 1, 900, 'CLINICAL_NOTE', null) like 'ERR:22023:CONTENT_REQUIRED:%'
    and pg_temp.record(10, 1, 900, 'OTHER', 'Text', '  ') like 'ERR:22023:OTHER_CONTEXT_REQUIRED:%'
    and pg_temp.record(10, 1, 900, 'CLINICAL_NOTE', 'Text', 'Context') like 'ERR:22023:OTHER_CONTEXT_NOT_ALLOWED:%'
    and pg_temp.call(10, format('select public.create_appointment_clinical_entry(%L, %L, null, %L, %L, null)::text',
        pg_temp.clinic(1), pg_temp.appt(1), 'CLINICAL_NOTE', 'Text')) like 'ERR:22023:KEY_REQUIRED:%'
    -- BR-5: a clinical time cannot be sent at all.
    and pg_temp.call(10, format('select public.create_appointment_clinical_entry(%L, %L, %L, %L, %L, null, %L)::text',
        pg_temp.clinic(1), pg_temp.appt(1), pg_temp.key(900), 'CLINICAL_NOTE', 'Text', '2026-06-01T10:00Z')) like 'ERR:42883:%'
    and pg_temp.clinical_facts() = (select facts from baseline_fields),
    'Note 6: missing category or content, invalid OTHER combinations and a missing key are rejected with stable hints; no clinical time can be sent; nothing is written'
);

-- OTHER keeps its normalized context; the only time is the recording time.
select pg_temp.keep('e_now', pg_temp.record(10, 1, 4, 'OTHER', 'Behaviour note', '  Grooming  '));
select pg_temp.assert_true(
    pg_temp.fact('e_now') ->> 'outcome' = 'CREATED'
    and (pg_temp.entry(pg_temp.entry_id('e_now'))).clinical_event_at is null
    and (pg_temp.entry(pg_temp.entry_id('e_now'))).created_at between (select at from facts where label = 'e_now') and clock_timestamp()
    and (pg_temp.entry(pg_temp.entry_id('e_now'))).other_category_context = 'Grooming',
    'Note 6: the OTHER context is normalized; the Entry carries only the server recording time'
);

-- Note 7: idempotency.
select pg_temp.assert_true(
    pg_temp.j(pg_temp.record(10, 1, 1, 'DIAGNOSIS', 'Otitis externa'))
        = jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', pg_temp.entry_id('e1'))
    and pg_temp.j(pg_temp.record(10, 1, 4, 'OTHER', 'Behaviour note', 'Grooming'))
        = jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', pg_temp.entry_id('e_now'))
    and pg_temp.record(10, 1, 1, 'DIAGNOSIS', 'Otitis media') like 'ERR:23505:KEY_CONFLICT:%'
    and pg_temp.record(10, 1, 1, 'CLINICAL_NOTE', 'Otitis externa') like 'ERR:23505:KEY_CONFLICT:%'
    and pg_temp.record(10, 2, 1, 'DIAGNOSIS', 'Otitis externa') like 'ERR:23505:KEY_CONFLICT:%'
    and pg_temp.entries(1) = 2 and pg_temp.entries(2) = 1,
    'Note 7: an exact replay returns ALREADY_CREATED with the same entry; different facts or another Appointment are KEY_CONFLICT; nothing is written'
);
select pg_temp.keep('e1b', pg_temp.record(10, 1, 5, 'DIAGNOSIS', 'Otitis externa'));
select pg_temp.assert_true(
    pg_temp.fact('e1b') ->> 'outcome' = 'CREATED' and pg_temp.entry_id('e1b') <> pg_temp.entry_id('e1')
    and pg_temp.entries(1) = 3,
    'Note 7: a distinct key with identical facts creates a distinct Entry'
);

-- ===========================================================================
-- 3. Documentable state, structurally (notes 2, 3)
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(pg_temp.record(10, n, 100 + n) like 'ERR:23514:APPOINTMENT_STATE_INVALID:%')
     from unnest(array[4, 5, 6, 7, 8]) n)
    and (select bool_and(pg_temp.entries(n) = 0) from unnest(array[4, 5, 6, 7, 8]) n),
    'Note 2: REQUESTED, CANCELLED, NO_SHOW, EXPIRED and never-confirmed Appointments are APPOINTMENT_STATE_INVALID even with an assignment'
);

create function pg_temp.direct_insert(appointment_n integer, vca_n integer, user_n integer) returns text
language plpgsql as $$ begin
    insert into public.clinical_record_entries (appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id,
        created_at, category, clinical_content, creation_idempotency_key, creation_request_digest)
    values (pg_temp.appt(appointment_n), pg_temp.domain_user(user_n), pg_temp.vca(vca_n), clock_timestamp(),
        'CLINICAL_NOTE', 'Direct', gen_random_uuid(), sha256('x'::bytea));
    return 'OK';
exception when others then
    return 'ERR:' || sqlstate || ':' || sqlerrm;
end $$;
select pg_temp.assert_true(
    (select bool_and(pg_temp.direct_insert(n, 10, 10) like 'ERR:23514:A Clinical Record Entry requires a legitimately confirmed%')
     from unnest(array[4, 5, 6, 7, 8]) n)
    and pg_temp.direct_insert(1, 11, 11) like 'ERR:23514:A Clinical Record Entry must be recorded by the Appointment''s current eligible assigned Veterinarian%'
    and pg_temp.direct_insert(14, 10, 10) like 'ERR:23514:A Clinical Record Entry must be recorded by the Appointment''s current eligible assigned Veterinarian%'
    and pg_temp.direct_insert(1, 10, 11) like 'ERR:23514:%'
    and pg_temp.direct_insert(1, 18, 18) like 'ERR:23514:%'
    and pg_temp.entries(14) = 0 and pg_temp.entries(1) = 3,
    'Notes 2/8: a direct insertion outside the operation is rejected for undocumentable Appointments, for a non-assignee or an unassigned Appointment, and for a Clinic Assignment of another User or Clinic'
);

create function pg_temp.direct_change(statement text) returns text language plpgsql as $$ begin
    execute statement;
    return 'OK';
exception when others then
    return 'ERR:' || sqlstate || ':' || sqlerrm;
end $$;
select pg_temp.assert_true(
    pg_temp.direct_change(format('update public.clinical_record_entries set appointment_id = %L where id = %L',
        pg_temp.appt(2), pg_temp.entry_id('e1'))) like 'ERR:23514:A recorded Clinical Record Entry is immutable%'
    and pg_temp.direct_change(format('update public.clinical_record_entries set clinical_content = ''Edited'' where id = %L',
        pg_temp.entry_id('e1'))) like 'ERR:23514:A recorded Clinical Record Entry is immutable%'
    and pg_temp.direct_change(format('delete from public.clinical_record_entries where id = %L',
        pg_temp.entry_id('e1'))) like 'ERR:23514:Clinical Record Entries cannot be deleted%'
    and (pg_temp.entry(pg_temp.entry_id('e1'))).appointment_id = pg_temp.appt(1)
    and (pg_temp.entry(pg_temp.entry_id('e1'))).clinical_content = 'Otitis externa',
    'Note 3: an Entry''s Appointment cannot change and the Entry cannot be updated or deleted'
);

-- ===========================================================================
-- 4. Who records (notes 8, 9)
-- ===========================================================================

create temporary table baseline_who on commit drop as select pg_temp.clinical_facts() as facts;
select pg_temp.assert_true(
    pg_temp.record(11, 1, 200) like 'ERR:23514:NOT_ASSIGNED_VETERINARIAN:%'
    and pg_temp.record(10, 14, 201) like 'ERR:23514:NO_VETERINARIAN_ASSIGNED:%'
    and pg_temp.record(11, 14, 202) like 'ERR:23514:NO_VETERINARIAN_ASSIGNED:%'
    and pg_temp.clinical_facts() = (select facts from baseline_who),
    'Note 8: another Veterinarian of the Clinic is NOT_ASSIGNED_VETERINARIAN; an unassigned Appointment is NO_VETERINARIAN_ASSIGNED'
);

select pg_temp.assert_true(
    pg_temp.record(5, 1, 210) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(8, 1, 211) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(1, 1, 212) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(17, 1, 213) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(18, 1, 214) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(10, 9, 215) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(18, 9, 216, clinic_n => 1) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(10, 15, 217, clinic_n => 3) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.call(10, format('select public.create_appointment_clinical_entry(%L, %L, %L, ''CLINICAL_NOTE'', ''x'', null)::text',
        pg_temp.clinic(1), pg_temp.id(11, 999), pg_temp.key(218))) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.call(10, format('select public.create_appointment_clinical_entry(%L, %L, %L, ''CLINICAL_NOTE'', ''x'', null)::text',
        pg_temp.id(4, 999), pg_temp.appt(1), pg_temp.key(219))) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.call(10, format('select public.create_appointment_clinical_entry(%L, %L, null, null, null, null)::text',
        pg_temp.clinic(1), pg_temp.id(11, 999))) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(0, 1, 220) like 'ERR:28000:%'
    and pg_temp.clinical_facts() = (select facts from baseline_who),
    'Note 9: Administrator, Receptionist, Guardian, other-Organization and other-Clinic Veterinarians, foreign or unknown Appointments and unknown Clinics receive one uniform 42501 before any validation; unauthenticated is 28000'
);

-- 15 and 9: each Clinic's own assigned Veterinarian records its Appointment.
select pg_temp.keep('e15', pg_temp.record(17, 15, 15, clinic_n => 3));
select pg_temp.keep('e9', pg_temp.record(18, 9, 9, clinic_n => 2));
select pg_temp.assert_true(
    pg_temp.fact('e15') ->> 'outcome' = 'CREATED' and pg_temp.fact('e9') ->> 'outcome' = 'CREATED',
    'Note 9: isolation is by Clinic, not by Veterinarian: each Clinic''s assignee records its own Appointment'
);

-- Stale assignee (BR-6): Veterinarian C leaves Clinic 1 while assigned to 13.
select pg_temp.keep('e13_before', pg_temp.record(12, 13, 13));
set local session_replication_role = replica;
update public.veterinarian_clinic_assignments set effective_end = clock_timestamp() where id = pg_temp.vca(12);
set local session_replication_role = origin;
select pg_temp.assert_true(
    pg_temp.fact('e13_before') ->> 'outcome' = 'CREATED'
    and pg_temp.record(12, 13, 130) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.record(10, 13, 131) like 'ERR:23514:NOT_ASSIGNED_VETERINARIAN:%'
    and pg_temp.read(10, 13) #>> '{documentation,unavailable_reason}' = 'NOT_ASSIGNED_VETERINARIAN'
    and pg_temp.read(12, 13) = '{"status": "DENIED"}'::jsonb
    and pg_temp.edit(12, 13, pg_temp.entry_id('e13_before'), 130) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.entries(13) = 1 and pg_temp.edits(pg_temp.entry_id('e13_before')) = 0,
    'Notes 8/9: a stale assignment authorizes no write; the departed Veterinarian loses documentation access, including editing, and other Veterinarians stay non-assignees'
);
-- After reassignment to an eligible Veterinarian, the new assignee records.
select pg_temp.assign(13, 11);
select pg_temp.keep('e13_after', pg_temp.record(11, 13, 132));
select pg_temp.assert_true(
    pg_temp.fact('e13_after') ->> 'outcome' = 'CREATED'
    and (pg_temp.entry(pg_temp.entry_id('e13_before'))).created_by_user_id = pg_temp.domain_user(12),
    'Note 23: after reassignment the new assignee records; the departed author stays the author of the earlier Entry'
);

-- ===========================================================================
-- 5. Reassignment and authorship (notes 19, 22, 23, 24)
-- ===========================================================================

select pg_temp.keep('e12', pg_temp.record(10, 12, 12, 'PRESCRIPTION', 'Amoxicillin 250 mg'));
select pg_temp.keep('reassign_12', pg_temp.call(8, format(
    'select public.assign_appointment_veterinarian(%L, %L, %L, %L)::text', pg_temp.clinic(1), pg_temp.appt(12), pg_temp.vca(11),
    (select id from public.appointment_veterinarian_assignments where appointment_id = pg_temp.appt(12) and effective_end is null))));
select pg_temp.assert_true(
    pg_temp.fact('reassign_12') ->> 'outcome' = 'REASSIGNED'
    and pg_temp.j(pg_temp.record(10, 12, 12, 'PRESCRIPTION', 'Amoxicillin 250 mg'))
        = jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', pg_temp.entry_id('e12'))
    and pg_temp.record(10, 12, 120) like 'ERR:23514:NOT_ASSIGNED_VETERINARIAN:%'
    and pg_temp.entries(12) = 1,
    'Note 24: after a reassignment the former assignee''s exact replay returns ALREADY_CREATED, while a new key is NOT_ASSIGNED_VETERINARIAN'
);
select pg_temp.keep('e12_b', pg_temp.record(11, 12, 121, 'CLINICAL_NOTE', 'Follow-up by B'));
select pg_temp.keep('a12_own', pg_temp.edit(10, 12, pg_temp.entry_id('e12'), 1, 1, 'PRESCRIPTION', 'Amoxicillin 500 mg'));
select pg_temp.assert_true(
    pg_temp.fact('e12_b') ->> 'outcome' = 'CREATED'
    and pg_temp.edit(11, 12, pg_temp.entry_id('e12'), 2, 2) like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.fact('a12_own') ->> 'outcome' = 'EDITED'
    and (select amending_user_id = pg_temp.domain_user(10) and amending_veterinarian_clinic_assignment_id = pg_temp.vca(10)
         from public.clinical_amendments
         where original_clinical_record_entry_id = pg_temp.entry_id('e12') and version_number = 2)
    and (pg_temp.entry(pg_temp.entry_id('e12'))).created_by_user_id = pg_temp.domain_user(10)
    and (pg_temp.entry(pg_temp.entry_id('e12'))).creator_veterinarian_clinic_assignment_id = pg_temp.vca(10)
    and (pg_temp.entry(pg_temp.entry_id('e12_b'))).created_by_user_id = pg_temp.domain_user(11),
    'Notes 19/23: the new assignee records its own Entry and cannot edit the former assignee''s; the original author still edits after reassignment; authorship is unchanged'
);

-- The read presents authorship only as "mine" / "another" (BR-20, note 18).
create temporary table read_12 on commit drop as select pg_temp.read(11, 12) as payload;
select pg_temp.assert_true(
    (select payload ->> 'status' = 'PERMITTED'
            and payload #>> '{documentation,can_record}' = 'true'
            and jsonb_array_length(payload -> 'entries') = 2
            and (payload #>> '{entries,0,recorded_by_me}')::boolean = false
            and (payload #>> '{entries,0,may_edit}')::boolean = false
            and (payload #>> '{entries,1,recorded_by_me}')::boolean = true
            and (payload #>> '{entries,1,may_edit}')::boolean = true
            and payload #>> '{entries,0,clinical_content}' = 'Amoxicillin 500 mg'
            and (payload #>> '{entries,0,version}')::integer = 2
            and payload #>> '{entries,0,previous_versions,0,clinical_content}' = 'Amoxicillin 250 mg'
            and payload -> 'entries' -> 0 -> 'amendments' = '[]'::jsonb
            and (select array_agg(key order by key) from jsonb_object_keys(payload -> 'entries' -> 0) as key)
                = array['amendments', 'amendments_truncated', 'category', 'clinical_content', 'clinical_event_at',
                        'edited_at', 'entry_id', 'may_edit', 'other_category_context', 'previous_versions',
                        'previous_versions_truncated', 'recorded_at', 'recorded_by_me', 'version']
            and (select array_agg(key order by key) from jsonb_object_keys(payload) as key)
                = array['appointment', 'documentation', 'entries', 'entries_truncated', 'status']
            and position(pg_temp.domain_user(10)::text in payload::text) = 0
            and position(pg_temp.vca(10)::text in payload::text) = 0
            and position(pg_temp.ca(12)::text in payload::text) = 0
            and position('Vet 10' in payload::text) = 0
     from read_12),
    'Note 18/BR-20: the read lists every Entry oldest first with its current version, mine/another authorship and may_edit = recorded_by_me, and carries no User, Clinic Assignment, Care Authorization identifier or Veterinarian name'
);

-- ===========================================================================
-- 6. Read, audit and its advisory documentation state (notes 17, 18)
-- ===========================================================================

create temporary table audit_baseline on commit drop as select pg_temp.audits() as n, pg_temp.clinical_facts() as facts;
select pg_temp.keep('read_14', pg_temp.call(10, format('select public.view_appointment_clinical_record(%L, %L)::text',
    pg_temp.clinic(1), pg_temp.appt(14))));
select pg_temp.assert_true(
    pg_temp.fact('read_14') ->> 'status' = 'PERMITTED'
    and pg_temp.fact('read_14') -> 'entries' = '[]'::jsonb
    and pg_temp.fact('read_14') #>> '{documentation,unavailable_reason}' = 'NO_VETERINARIAN_ASSIGNED'
    and pg_temp.audits() = (select n from audit_baseline),
    'Note 17: a read of an Appointment without Entries returns no medical information and creates no audit event'
);
select pg_temp.keep('read_1', pg_temp.call(10, format('select public.view_appointment_clinical_record(%L, %L)::text',
    pg_temp.clinic(1), pg_temp.appt(1))));
select pg_temp.assert_true(
    jsonb_array_length(pg_temp.fact('read_1') -> 'entries') = 3
    and pg_temp.audits() = (select n from audit_baseline) + 1
    and (select count(*) = 1 from public.medical_access_audit_events
         where pet_id = pg_temp.luna() and operation = 'VIEW_APPOINTMENT_CLINICAL_RECORD' and outcome = 'PERMITTED'
           and protected_resource_scope = 'APPOINTMENT_CLINICAL_RECORD' and actor_context = 'PROFESSIONAL_CLINICAL'
           and acting_user_id = pg_temp.domain_user(10) and appointment_id = pg_temp.appt(1)
           and accessing_clinic_id = pg_temp.clinic(1) and accessing_organization_id = pg_temp.id(3, 1)
           and organization_membership_id = pg_temp.id(5, 10) and organization_responsibility_grant_id = pg_temp.id(6, 10)
           and veterinarian_clinic_assignment_id = pg_temp.vca(10) and care_authorization_id = pg_temp.ca(1)
           and clinical_record_entry_id is null),
    'Note 17: a permitted read with three Entries creates exactly one typed VIEW_APPOINTMENT_CLINICAL_RECORD event'
);
create temporary table denied_reads on commit drop as
select pg_temp.read(8, 1) as receptionist, pg_temp.read(5, 1) as administrator, pg_temp.read(18, 1) as other_clinic,
       pg_temp.read(10, 9) as foreign_appointment, pg_temp.read(10, 15, 3) as other_organization;
select pg_temp.assert_true(
    (select receptionist = '{"status": "DENIED"}'::jsonb and administrator = '{"status": "DENIED"}'::jsonb
            and other_clinic = '{"status": "DENIED"}'::jsonb and foreign_appointment = '{"status": "DENIED"}'::jsonb
            and other_organization = '{"status": "DENIED"}'::jsonb
     from denied_reads)
    and (select count(*) = 3 from public.medical_access_audit_events
         where pet_id = pg_temp.luna() and operation = 'VIEW_APPOINTMENT_CLINICAL_RECORD' and outcome = 'DENIED'
           and appointment_id = pg_temp.appt(1))
    and (select count(*) = 1 from public.medical_access_audit_events
         where operation = 'VIEW_APPOINTMENT_CLINICAL_RECORD' and outcome = 'DENIED' and appointment_id = pg_temp.appt(15)
           and acting_user_id = pg_temp.domain_user(10)),
    'Note 17: Receptionist, Administrator and other-Clinic reads of a documented Appointment are uniform DENIED with one DENIED event each; a foreign Appointment named under the wrong Clinic is DENIED without audit'
);
select pg_temp.assert_true(
    pg_temp.clinical_facts() = (select facts from audit_baseline),
    'Note 18: reading writes no clinical information'
);
select pg_temp.assert_true(
    pg_temp.read(10, 4) #>> '{documentation,unavailable_reason}' = 'APPOINTMENT_STATE'
    and pg_temp.read(10, 5) #>> '{documentation,unavailable_reason}' = 'APPOINTMENT_STATE'
    and pg_temp.read(11, 1) #>> '{documentation,unavailable_reason}' = 'NOT_ASSIGNED_VETERINARIAN'
    and pg_temp.read(11, 1) #>> '{documentation,can_record}' = 'false'
    and pg_temp.read(10, 1) #>> '{documentation,can_record}' = 'true'
    and pg_temp.read(10, 3) #>> '{appointment,lifecycle_state}' = 'COMPLETED'
    and pg_temp.read(10, 3) #>> '{documentation,can_record}' = 'true',
    'BR-20: the advisory documentation state reports APPOINTMENT_STATE, NOT_ASSIGNED_VETERINARIAN or can_record, also on a COMPLETED Appointment'
);

-- ===========================================================================
-- 7. Editing (notes 9, 19; BR-18, BR-23b)
-- ===========================================================================

select pg_temp.keep('a1', pg_temp.edit(10, 1, pg_temp.entry_id('e1'), 10, 1, 'DIAGNOSIS', '  Otitis externa, left ear  '));
select pg_temp.assert_true(
    pg_temp.raw('a1') = 'OK:{"outcome": "EDITED", "version": 2}'
    and (select change_kind = 'EDIT' and version_number = 2 and reason is null and category = 'DIAGNOSIS'
                and amendment_content = 'Otitis externa, left ear'
         from public.clinical_amendments where original_clinical_record_entry_id = pg_temp.entry_id('e1'))
    and (pg_temp.entry(pg_temp.entry_id('e1'))).clinical_content = 'Otitis externa'
    and pg_temp.edit(10, 1, pg_temp.entry_id('e1'), 10, 1, 'DIAGNOSIS', 'Otitis externa, left ear')
        = 'OK:{"outcome": "ALREADY_EDITED", "version": 2}'
    and pg_temp.edit(10, 1, pg_temp.entry_id('e1'), 10, 1, 'DIAGNOSIS', 'Different') like 'ERR:23505:KEY_CONFLICT:%'
    and pg_temp.edit(10, 1, pg_temp.entry_id('e1'), 11, 1, 'DIAGNOSIS', 'Opened on version 1') like 'ERR:P0001:STALE_VERSION:%'
    and pg_temp.edit(10, 1, pg_temp.entry_id('e1'), 11, 2, 'DIAGNOSIS', ' ') like 'ERR:22023:CONTENT_REQUIRED:%'
    and pg_temp.call(10, format('select public.edit_appointment_clinical_entry(%L, %L, %L, null, 2, ''DIAGNOSIS'', ''c'', null)::text',
        pg_temp.clinic(1), pg_temp.appt(1), pg_temp.entry_id('e1'))) like 'ERR:22023:KEY_REQUIRED:%'
    and pg_temp.edits(pg_temp.entry_id('e1')) = 1,
    'Note 19: the author edits; normalization, replay, KEY_CONFLICT, STALE_VERSION and field rules apply, and the recorded Entry is unchanged'
);
select pg_temp.assert_true(
    pg_temp.edit(11, 1, pg_temp.entry_id('e1'), 20, 2) like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%'
    and pg_temp.edit(8, 1, pg_temp.entry_id('e1'), 21, 2) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(5, 1, pg_temp.entry_id('e1'), 22, 2) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(17, 1, pg_temp.entry_id('e1'), 23, 2) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(10, 2, pg_temp.entry_id('e1'), 24, 2) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(10, 1, pg_temp.id(15, 999), 25, 2) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(10, 1, pg_temp.entry_id('e1'), 26, 2, clinic_n => 2) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edit(17, 15, pg_temp.entry_id('e1'), 27, 2, clinic_n => 3) = 'ERR:42501:-:Clinical record unavailable'
    and pg_temp.edits(pg_temp.entry_id('e1')) = 1,
    'Notes 9/19: a non-author Veterinarian is ENTRY_AUTHOR_REQUIRED; non-Veterinarians, other Organizations, an Entry of another Appointment, an unknown Entry, and another Clinic are the uniform 42501'
);
-- After completion (3) and after revocation (10, below): the author still edits.
select pg_temp.keep('a3', pg_temp.edit(10, 3, pg_temp.entry_id('e3'), 30));
select pg_temp.assert_true(
    pg_temp.fact('a3') ->> 'outcome' = 'EDITED',
    'Note 19: the author edits an Entry of a COMPLETED Appointment'
);
create function pg_temp.direct_version_insert(entry uuid, user_n integer, vca_n integer, version integer) returns text
language plpgsql as $$ begin
    insert into public.clinical_amendments (original_clinical_record_entry_id, change_kind, version_number, category,
        amendment_content, amending_user_id, amending_veterinarian_clinic_assignment_id, created_at, idempotency_key)
    values (entry, 'EDIT', version, 'CLINICAL_NOTE', 'c', pg_temp.domain_user(user_n), pg_temp.vca(vca_n),
            clock_timestamp(), gen_random_uuid());
    return 'OK';
exception when others then
    return 'ERR:' || sqlstate || ':' || sqlerrm;
end $$;
select pg_temp.assert_true(
    pg_temp.direct_version_insert(pg_temp.entry_id('e1'), 11, 11, 3) like 'ERR:23514:Only the original author may amend%'
    and pg_temp.direct_version_insert(pg_temp.entry_id('e1'), 10, 10, 2) like 'ERR:23514:A Clinical Record Entry version must follow%'
    and pg_temp.direct_change(format('update public.clinical_amendments set amendment_content = ''x'' where original_clinical_record_entry_id = %L',
        pg_temp.entry_id('e1'))) like 'ERR:23514:Clinical Amendments are append-only%'
    and pg_temp.direct_change(format('delete from public.clinical_amendments where original_clinical_record_entry_id = %L',
        pg_temp.entry_id('e1'))) like 'ERR:23514:Clinical Amendments are append-only%',
    'Note 19: structurally, only the author adds the next version and versions are append-only'
);

-- ===========================================================================
-- 8. Revocation and completion leave documentation access (notes 11, 12)
-- ===========================================================================

-- 10: revoked before any record; the assigned Veterinarian still documents.
select pg_temp.keep('e10', pg_temp.record(10, 10, 10, 'EXAMINATION', 'Revocation-time exam'));
select pg_temp.keep('a10', pg_temp.edit(10, 10, pg_temp.entry_id('e10'), 40));
select pg_temp.assert_true(
    pg_temp.fact('e10') ->> 'outcome' = 'CREATED'
    and pg_temp.fact('a10') ->> 'outcome' = 'EDITED'
    and pg_temp.read(10, 10) ->> 'status' = 'PERMITTED'
    and jsonb_array_length(pg_temp.read(10, 10) -> 'entries') = 1
    and (select lifecycle_state = 'REVOKED' from public.care_authorizations where id = pg_temp.ca(10)),
    'Notes 11/BR-12: Guardian revocation before any record does not prevent recording, editing or reading the Appointment''s own record, and documenting never restores the authorization'
);
-- 1: revoked after documentation began.
select pg_temp.call(1, format('select public.revoke_my_appointment_care_authorization(%L)::text', pg_temp.appt(21)));
select pg_temp.keep('e21_first', pg_temp.record(10, 21, 2101));
select pg_temp.assert_true(
    pg_temp.fact('e21_first') ->> 'outcome' = 'CREATED'
    and (select lifecycle_state = 'REVOKED' from public.care_authorizations where id = pg_temp.ca(21)),
    'Note 11: documentation access is independent of the Care Authorization state'
);

-- Note 12: prior-history access only under BR-14.
select pg_temp.assert_true(
    pg_temp.history(10, 1) ->> 'status' = 'PERMITTED'
    and pg_temp.history(11, 1) ->> 'status' = 'PERMITTED'
    and pg_temp.history(10, 2) ->> 'status' = 'PERMITTED'
    and pg_temp.history(10, 4) ->> 'status' = 'PERMITTED'
    and pg_temp.history(10, 14) ->> 'status' = 'PERMITTED'
    and pg_temp.history(10, 10) ->> 'status' = 'DENIED'
    and pg_temp.history(10, 21) ->> 'status' = 'DENIED'
    and pg_temp.history(10, 3) ->> 'status' = 'DENIED'
    and pg_temp.history(10, 5) ->> 'status' = 'DENIED'
    and pg_temp.history(10, 6) ->> 'status' = 'DENIED'
    and pg_temp.history(10, 7) ->> 'status' = 'DENIED'
    and pg_temp.history(8, 1) ->> 'status' = 'DENIED'
    and pg_temp.history(5, 1) ->> 'status' = 'DENIED'
    and pg_temp.history(18, 1) ->> 'status' = 'DENIED'
    and pg_temp.history(10, 9) ->> 'status' = 'DENIED',
    'Note 12: prior history opens through ACTIVE CONFIRMED or future REQUESTED Appointments for any Veterinarian of the Clinic, assigned or not, and is denied after revocation, after completion, for terminal Appointments, to non-Veterinarians and across Clinics, although documentation access persists there'
);

-- ===========================================================================
-- 9. Lifecycle interactions (notes 14, 15, 16)
-- ===========================================================================

-- 17: Entry first, then cancellation and NO_SHOW are refused; completion succeeds.
select pg_temp.keep('e17', pg_temp.record(10, 17, 17));
select pg_temp.assert_true(
    pg_temp.call(8, format('select public.cancel_appointment(%L, ''CLINIC'', ''Closed'', 2)::text', pg_temp.appt(17)))
        like 'ERR:23514:%Appointment with clinical documentation cannot be cancelled'
    -- 2 is documented and still before its start, where a Guardian may cancel.
    and pg_temp.call(1, format('select public.cancel_appointment(%L, ''GUARDIAN'', null, null)::text', pg_temp.appt(2)))
        = 'ERR:23514:-:Appointment with clinical documentation cannot be cancelled'
    and pg_temp.state(2) = 'CONFIRMED'
    and pg_temp.call(8, format('select public.mark_appointment_no_show(%L, 2)::text', pg_temp.appt(17)))
        like 'ERR:23514:%Appointment with clinical documentation cannot be marked no-show'
    and pg_temp.state(17) = 'CONFIRMED',
    'Notes 15/16: with an Entry, Clinic and Guardian cancellation and NO_SHOW are rejected'
);
select pg_temp.keep('complete_17', pg_temp.call(8, format('select public.complete_appointment(%L, 2)::text', pg_temp.appt(17))));
select pg_temp.keep('e17_after', pg_temp.record(10, 17, 1701));
select pg_temp.assert_true(
    pg_temp.raw('complete_17') like 'OK:%' and pg_temp.state(17) = 'COMPLETED'
    and pg_temp.fact('e17_after') ->> 'outcome' = 'CREATED',
    'Notes 1/15: completion succeeds with an Entry and the assignee keeps documenting the COMPLETED Appointment'
);

-- Note 13 (M3): completion ended the ACTIVE authorization at its Event time.
select pg_temp.assert_true(
    (select care_auth.lifecycle_state = 'ENDED' and care_auth.ended_reason = 'APPOINTMENT_COMPLETED'
            and care_auth.ended_at = (select effective_at from public.appointment_lifecycle_events
                                      where appointment_id = pg_temp.appt(17) and to_state = 'COMPLETED')
            and care_auth.revoked_at is null
     from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(17))
    and (select count(*) = 1 from public.care_authorizations where appointment_id = pg_temp.appt(17)),
    'Note 13: completion ends the ACTIVE Care Authorization with APPOINTMENT_COMPLETED at the completion time; none is created'
);
-- After completion the author reads, records and edits; reading writes
-- nothing and grants nothing; prior history stays closed.
create temporary table after_completion on commit drop as
    select pg_temp.clinical_facts() as facts,
           (select to_jsonb(care_auth) from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(17)) as care_auth,
           pg_temp.audits() as audits;
create temporary table after_completion_reads on commit drop as
    select pg_temp.read(10, 17) as record_read, pg_temp.read(11, 17) as other_read, pg_temp.history(10, 17) as history_read;
select pg_temp.assert_true(
    (select record_read ->> 'status' = 'PERMITTED'
            and record_read #>> '{appointment,lifecycle_state}' = 'COMPLETED'
            and record_read #>> '{documentation,can_record}' = 'true'
            and jsonb_array_length(record_read -> 'entries') = 2
            and other_read #>> '{documentation,unavailable_reason}' = 'NOT_ASSIGNED_VETERINARIAN'
            and history_read = '{"status": "DENIED"}'::jsonb
     from after_completion_reads)
    and pg_temp.clinical_facts() = (select facts from after_completion)
    and (select to_jsonb(care_auth) from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(17))
        = (select care_auth from after_completion)
    and pg_temp.audits() = (select audits from after_completion) + 3,
    'Notes 11/12/18 after completion: the record stays readable and documentable, prior history is denied, and reads write no clinical fact and change no authorization (only their audit events)'
);
select pg_temp.keep('a17_after', pg_temp.edit(10, 17, pg_temp.entry_id('e17'), 1700));
select pg_temp.assert_true(
    pg_temp.fact('a17_after') ->> 'outcome' = 'EDITED'
    and pg_temp.edit(11, 17, pg_temp.entry_id('e17'), 1702, 2) like 'ERR:23514:ENTRY_AUTHOR_REQUIRED:%',
    'Note 19 after completion: the author edits an Entry of the COMPLETED Appointment; others still cannot'
);
-- 21 was revoked after documentation began: completion keeps the revocation,
-- and the assignee keeps documenting (SPEC-ACC-002 BR-46, SPEC-MED-010 BR-11).
create temporary table revoked_21 on commit drop as
    select to_jsonb(care_auth) as row_value from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(21);
select pg_temp.keep('complete_21', pg_temp.call(8, format('select public.complete_appointment(%L, 2)::text', pg_temp.appt(21))));
select pg_temp.keep('e21_after', pg_temp.record(10, 21, 2102));
select pg_temp.assert_true(
    pg_temp.raw('complete_21') like 'OK:%' and pg_temp.state(21) = 'COMPLETED'
    and (select to_jsonb(care_auth) = (select row_value from revoked_21)
         from public.care_authorizations as care_auth where care_auth.id = pg_temp.ca(21))
    and pg_temp.fact('e21_after') ->> 'outcome' = 'CREATED'
    and pg_temp.read(10, 21) ->> 'status' = 'PERMITTED',
    'Note 13: completing after a Guardian revocation keeps the REVOKED authorization unchanged, and documentation continues'
);
-- 18: cancellation first, then the Entry is refused (BR-26 serialization).
select pg_temp.call(8, format('select public.cancel_appointment(%L, ''CLINIC'', ''Closed'', 2)::text', pg_temp.appt(18)));
select pg_temp.assert_true(
    pg_temp.state(18) = 'CANCELLED'
    and pg_temp.record(10, 18, 18) like 'ERR:23514:APPOINTMENT_STATE_INVALID:%'
    and pg_temp.entries(18) = 0,
    'Note 16: a cancellation that wins first makes the Entry APPOINTMENT_STATE_INVALID; exactly one coherent outcome'
);
-- 19: NO_SHOW first, then the Entry is refused.
select pg_temp.call(8, format('select public.mark_appointment_no_show(%L, 2)::text', pg_temp.appt(19)));
select pg_temp.assert_true(
    pg_temp.state(19) = 'NO_SHOW'
    and pg_temp.record(10, 19, 19) like 'ERR:23514:APPOINTMENT_STATE_INVALID:%'
    and pg_temp.entries(19) = 0,
    'Note 16: a NO_SHOW that wins first makes the Entry APPOINTMENT_STATE_INVALID'
);
-- Note 14: the first Entry voids a pending Reschedule Proposal (20).
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
) select pg_temp.id(16, 20), pg_temp.appt(20), revision.id, 'CONFIRMED', '2035-08-01T08:00Z', '2035-08-01T08:30Z',
         'Europe/Madrid', 'GUARDIAN', pg_temp.domain_user(1), 'Need another day', clock_timestamp()
  from public.appointment_schedule_revisions as revision
  where revision.appointment_id = pg_temp.appt(20) and revision.revision_sequence = 2;
select pg_temp.flush();
select pg_temp.keep('e20', pg_temp.record(10, 20, 20));
select pg_temp.assert_true(
    pg_temp.fact('e20') ->> 'outcome' = 'CREATED'
    and (select state = 'VOID' and void_reason = 'CLINICAL_DOCUMENTATION_STARTED'
         from public.appointment_reschedule_proposals where id = pg_temp.id(16, 20)),
    'Note 14: the first Entry voids a pending Reschedule Proposal with CLINICAL_DOCUMENTATION_STARTED in the same transaction'
);

-- ===========================================================================
-- 10. Longitudinal and Guardian history (notes 4, 5, 25)
-- ===========================================================================

-- An Entry recorded with a clinical event time before M5, loaded as data:
-- its event time still orders the history (BR-5).
set local session_replication_role = replica;
insert into public.clinical_record_entries (id, appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id,
    created_at, category, clinical_content, clinical_event_at, creation_idempotency_key, creation_request_digest)
values (pg_temp.id(15, 500), pg_temp.appt(3), pg_temp.domain_user(10), pg_temp.vca(10), clock_timestamp(),
    'EXAMINATION', 'Historical exam', '2026-06-03T10:05Z', gen_random_uuid(), sha256('x'::bytea));
set local session_replication_role = origin;
create temporary table guardian_read on commit drop as select pg_temp.guardian_history(1) as payload;
select pg_temp.assert_true(
    (select payload ->> 'status' = 'PERMITTED' from guardian_read)
    and (select count(*) from guardian_read, jsonb_array_elements(payload #> '{payload,entries}'))
        = (select count(*) from public.clinical_record_entries e join public.appointments a on a.id = e.appointment_id
           where a.pet_id = pg_temp.luna())
    and (select bool_and(entry_row ->> 'clinic_display_name' = 'Clinic One' and entry_row ->> 'organization_display_name' = 'ACR Org A')
         from guardian_read, jsonb_array_elements(payload #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid in (pg_temp.entry_id('e1'), pg_temp.entry_id('e3'), pg_temp.entry_id('e10'), pg_temp.entry_id('e21_first')))
    and (select entry_row ->> 'clinic_display_name' = 'Clinic Two'
         from guardian_read, jsonb_array_elements(payload #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid = pg_temp.entry_id('e9'))
    and (select entry_row ->> 'clinic_display_name' = 'Clinic Three' and entry_row ->> 'organization_display_name' = 'ACR Org B'
         from guardian_read, jsonb_array_elements(payload #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid = pg_temp.entry_id('e15'))
    and (select entry_row ->> 'clinical_content' = 'Otitis externa, left ear'
                and (entry_row ->> 'version')::integer = 2
                and entry_row #>> '{previous_versions,0,clinical_content}' = 'Otitis externa'
                and entry_row -> 'amendments' = '[]'::jsonb
                and (entry_row ->> 'history_order_at')::timestamptz = (pg_temp.entry(pg_temp.entry_id('e1'))).created_at
                and entry_row -> 'clinical_event_at' = 'null'::jsonb
                and not entry_row ? 'encounter_started_at'
         from guardian_read, jsonb_array_elements(payload #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid = pg_temp.entry_id('e1'))
    and (select (entry_row ->> 'history_order_at')::timestamptz = '2026-06-03T10:05Z'
                and (entry_row ->> 'clinical_event_at')::timestamptz = '2026-06-03T10:05Z'
         from guardian_read, jsonb_array_elements(payload #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid = pg_temp.id(15, 500))
    and (select (entry_row ->> 'history_order_at')::timestamptz = (pg_temp.entry(pg_temp.entry_id('e2'))).created_at
         from guardian_read, jsonb_array_elements(payload #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid = pg_temp.entry_id('e2')),
    'Notes 4/5/25: every recorded Entry is immediately in the Guardian history with its current and earlier versions, Clinic and Organization provenance derived from its Appointment, ordered by its recording time (or a historical event time), including Entries of revoked and completed Appointments'
);

create temporary table professional_read on commit drop as select pg_temp.history(11, 1) as payload;
select pg_temp.assert_true(
    (select bool_or((entry_row ->> 'entry_id')::uuid = pg_temp.entry_id('e3'))
            and bool_or((entry_row ->> 'entry_id')::uuid = pg_temp.entry_id('e10'))
            and bool_or((entry_row ->> 'entry_id')::uuid = pg_temp.entry_id('e21_first'))
            and bool_or((entry_row ->> 'entry_id')::uuid = pg_temp.entry_id('e15'))
            and bool_and(((entry_row ->> 'is_this_appointment')::boolean)
                         = ((entry_row ->> 'entry_id')::uuid in (select id from public.clinical_record_entries
                                                                  where appointment_id = pg_temp.appt(1))))
            and bool_and(not entry_row ? 'encounter_started_at')
     from professional_read, jsonb_array_elements(payload -> 'entries') as entry_row),
    'Note 25: through another permitted Appointment, the history includes Entries of COMPLETED and revoked Appointments and of other Organizations; is_this_appointment marks the rooting Appointment'
);

-- SPEC-APT-012 BR-48 per SPEC-MED-010 §9: the schedule reports existence only,
-- without audit.
create temporary table schedule_read (id uuid, has_clinical_record boolean) on commit drop;
grant select, insert on schedule_read to authenticated;
create temporary table schedule_audits on commit drop as select pg_temp.audits() as n;
select pg_temp.call(8, format('insert into schedule_read select id, has_clinical_record from public.get_clinic_appointment_schedule(%L) returning null::text',
    pg_temp.clinic(1)));
select pg_temp.assert_true(
    (select bool_and(has_clinical_record = (pg_temp.entries_by_id(id) > 0)) and count(*) >= 17 from schedule_read)
    and (select has_clinical_record from schedule_read where id = pg_temp.appt(1))
    and not (select has_clinical_record from schedule_read where id = pg_temp.appt(14))
    and pg_temp.audits() = (select n from schedule_audits),
    'SPEC-APT-012 BR-48: has_clinical_record reports whether the Appointment has an Entry, without audit'
);

-- ===========================================================================
-- 11. Attachments (notes 10, 20). Stage M4 retired every professional
--     Attachment operation (SPEC-MED-010 BR-19: no professional client
--     workflow ships); the structural rules still bind any future one.
-- ===========================================================================

select pg_temp.assert_true(
    to_regprocedure('public.initiate_clinical_attachment_upload(uuid,uuid,uuid,uuid,text)') is null
    and to_regprocedure('public.resolve_clinical_attachment_completion_target(uuid,uuid)') is null
    and to_regprocedure('public.remove_draft_clinical_attachment(uuid,uuid)') is null
    and to_regprocedure('public.authorize_clinical_attachment_download(uuid,uuid,text,text,uuid,uuid,uuid)') is null,
    'Note 20 (M4): no professional operation adds, completes, removes or downloads an Attachment'
);
-- The Entry's author may still hold a PENDING row written by a trusted
-- process (here directly, as the owner); anyone else may not.
select pg_temp.assert_true(
    pg_temp.direct_change(format(
        'insert into public.clinical_attachments (clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id, upload_idempotency_key, upload_stale_after, original_filename) values (%L, %L, %L, %L, clock_timestamp() + interval ''1 hour'', ''report.pdf'')',
        pg_temp.entry_id('e1'), pg_temp.domain_user(10), pg_temp.vca(10), pg_temp.id(17, 1))) = 'OK'
    and pg_temp.direct_change(format(
        'insert into public.clinical_attachments (clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id, upload_idempotency_key, upload_stale_after) values (%L, %L, %L, gen_random_uuid(), clock_timestamp() + interval ''1 hour'')',
        pg_temp.entry_id('e1'), pg_temp.domain_user(11), pg_temp.vca(11)))
        like 'ERR:23514:A new Attachment must begin PENDING/AWAITING_UPLOAD and be added by the Entry author%',
    'Note 20: structurally, only the Entry''s author adds an Attachment'
);
select pg_temp.flush();
select pg_temp.assert_true(
    public.clinical_attachment_metadata_for_entry(pg_temp.entry_id('e1'), false) = '[]'::jsonb
    and (select bool_and(entry_row -> 'attachments' = '[]'::jsonb)
         from jsonb_array_elements(pg_temp.guardian_history(1) #> '{payload,entries}') as entry_row
         where (entry_row ->> 'id')::uuid = pg_temp.entry_id('e1')),
    'Note 20: a PENDING Attachment is never shown'
);
set local session_replication_role = replica;
update public.clinical_attachments set validation_state = 'AVAILABLE', object_state = 'STORED',
    trusted_media_type = 'application/pdf', trusted_byte_size = 1024, integrity_algorithm = 'SHA-256',
    integrity_value = sha256('pdf'::bytea), validation_policy_version = 'phase1-pdf-v1', validation_completed_at = clock_timestamp()
where clinical_record_entry_id = pg_temp.entry_id('e1') and upload_idempotency_key = pg_temp.id(17, 1);
set local session_replication_role = origin;
select pg_temp.assert_true(
    pg_temp.direct_change(format('update public.clinical_attachments set removed_at = clock_timestamp(), removed_by_user_id = %L, removed_by_vca_id = %L where clinical_record_entry_id = %L',
        pg_temp.domain_user(10), pg_temp.vca(10), pg_temp.entry_id('e1')))
        like 'ERR:23514:A current AVAILABLE Attachment is immutable%'
    and jsonb_array_length(public.clinical_attachment_metadata_for_entry(pg_temp.entry_id('e1'), false)) = 1,
    'Note 20: an AVAILABLE Attachment is visible, immutable and cannot be removed'
);

-- ===========================================================================
-- 12. Commercial gate (notes 10, 11). Last: Organization A loses CLINICAL_CARE.
-- ===========================================================================

select public.apply_subscription_state_transition(
    (select id from public.organization_subscriptions where organization_id = pg_temp.id(3, 1)),
    'PAST_DUE', statement_timestamp(), null, null, 'appointment-clinical-record-suite', null);
select pg_temp.flush();
create temporary table lapse_baseline on commit drop as select pg_temp.clinical_facts() as facts;
select pg_temp.assert_true(
    not public.organization_has_professional_entitlement(pg_temp.id(3, 1), 'CLINICAL_CARE')
    and pg_temp.record(10, 1, 300) like 'ERR:42501:CLINICAL_SERVICE_UNAVAILABLE:%'
    and pg_temp.record(10, 2, 301) like 'ERR:42501:CLINICAL_SERVICE_UNAVAILABLE:%'
    and pg_temp.clinical_facts() = (select facts from lapse_baseline),
    'Note 10: without CLINICAL_CARE every new Entry (also on Appointments that already have Entries) is CLINICAL_SERVICE_UNAVAILABLE; nothing is written (no Attachment operation exists since M4)'
);
select pg_temp.assert_true(
    pg_temp.j(pg_temp.record(10, 1, 1, 'DIAGNOSIS', 'Otitis externa')) ->> 'outcome' = 'ALREADY_CREATED'
    and pg_temp.edit(10, 1, pg_temp.entry_id('e1b'), 50) = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.read(10, 1) ->> 'status' = 'PERMITTED'
    and pg_temp.read(10, 1) #>> '{documentation,unavailable_reason}' = 'CLINICAL_SERVICE_UNAVAILABLE'
    and pg_temp.record(11, 1, 302) like 'ERR:23514:NOT_ASSIGNED_VETERINARIAN:%',
    'Note 10: an exact replay, edits and the read still succeed without the Entitlement; domain rejections precede the commercial gate'
);

rollback;

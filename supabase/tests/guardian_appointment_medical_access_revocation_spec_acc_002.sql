-- Guardian Appointment Medical Access Revocation — Phase 1:
-- SPEC-ACC-002 §16/§17 (BR-56–BR-63), SPEC-APT-011 BR-35.
-- Migration 20261106090000_guardian_appointment_medical_access_revocation.sql.
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The organizational context and Appointments are loaded as data with
-- triggers bypassed (as in professional_medical_history_spec_med_005.sql);
-- care, documentation, Appointment resolution and revocation run through the
-- client operations as the impersonated User under the authenticated role.
-- Mutants are pinned by run_care_authorization_revocation_faults.py.
-- Fixture prefix d0370000-.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0370000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.clinic() returns uuid language sql immutable as $$ select pg_temp.id(4, 1) $$;
create function pg_temp.appt(n integer) returns uuid language sql immutable as $$ select pg_temp.id(11, n) $$;
create function pg_temp.ca(n integer) returns uuid language sql immutable as $$ select pg_temp.id(12, n) $$;
create function pg_temp.luna() returns uuid language sql immutable as $$ select pg_temp.id(9, 1) $$;
create function pg_temp.toby() returns uuid language sql immutable as $$ select pg_temp.id(9, 2) $$;
create function pg_temp.rex() returns uuid language sql immutable as $$ select pg_temp.id(9, 3) $$;
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
-- The client revoke, keyed only by the Appointment.
create function pg_temp.revoke_raw(actor integer, appointment uuid) returns text language sql as $$
    select pg_temp.call(actor, format('select public.revoke_my_appointment_care_authorization(%L)::text', appointment))
$$;
create function pg_temp.revoke(actor integer, appointment_n integer) returns text language sql as $$
    select pg_temp.revoke_raw(actor, pg_temp.appt(appointment_n))
$$;
create function pg_temp.ca_state(n integer) returns text language sql as $$
    select lifecycle_state from public.care_authorizations where id = pg_temp.ca(n)
$$;
create function pg_temp.ca_row(n integer) returns text language sql as $$
    select md5(to_jsonb(ca)::text) from public.care_authorizations as ca where ca.id = pg_temp.ca(n)
$$;
-- The Guardian read, as Guardian 1 for Luna unless named.
create function pg_temp.guardian_rows(actor integer, pet uuid) returns jsonb language plpgsql as $$
declare result jsonb; begin
    perform pg_temp.act(actor);
    execute 'set local role authenticated';
    select coalesce(jsonb_agg(to_jsonb(read_row) order by read_row.created_at, read_row.id), '[]'::jsonb)
    into result from public.get_pet_appointments(pet) as read_row;
    execute 'reset role';
    return result;
end $$;
create function pg_temp.access_state(appointment_n integer) returns text language sql as $$
    select item ->> 'medical_access_state'
    from jsonb_array_elements(pg_temp.guardian_rows(1, pg_temp.luna())) as item
    where (item ->> 'id')::uuid = pg_temp.appt(appointment_n)
$$;
create function pg_temp.hist(actor integer, appointment_n integer) returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(actor, format(
        'select public.view_appointment_professional_medical_history(%L, %L)::text',
        pg_temp.clinic(), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.record(actor integer, appointment_n integer) returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(actor, format('select public.view_appointment_clinical_record(%L, %L)::text',
        pg_temp.clinic(), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.denied(payload jsonb) returns boolean language sql immutable as $$
    select payload = '{"status": "DENIED"}'::jsonb
$$;
-- "Guardar y publicar registro" as Ana, the assigned Veterinarian (SPEC-MED-010 BR-23).
create function pg_temp.record_raw(appointment_n integer, key_n integer, content text) returns text language sql as $$
    select pg_temp.call(10, format(
        'select public.create_appointment_clinical_entry(%L, %L, %L, %L, %L, null)::text',
        pg_temp.clinic(), pg_temp.appt(appointment_n), pg_temp.id(16, key_n), 'CLINICAL_NOTE', content))
$$;
create function pg_temp.entry(appointment_n integer, key_n integer, content text) returns uuid language sql as $$
    select (pg_temp.j(pg_temp.record_raw(appointment_n, key_n, content)) ->> 'entry_id')::uuid
$$;
-- Ana edits her own Entry, on the version the editor was opened on (BR-23b).
create function pg_temp.edit(appointment_n integer, entry uuid, key_n integer, expected integer, content text)
returns text language sql as $$
    select pg_temp.call(10, format(
        'select public.edit_appointment_clinical_entry(%L, %L, %L, %L, %s, %L, %L, null)::text',
        pg_temp.clinic(), pg_temp.appt(appointment_n), entry, pg_temp.id(17, key_n), expected, 'CLINICAL_NOTE', content))
$$;
create function pg_temp.guardian_history() returns jsonb language sql as $$
    select pg_temp.j(pg_temp.call(1, format('select public.view_guardian_pet_medical_history(%L)::text', pg_temp.luna())))
$$;
-- Everything an Appointment is made of, and everything clinical.
create function pg_temp.appointment_facts() returns text language sql as $$
    select md5(coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.appointments t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.appointment_lifecycle_events t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.appointment_id, t.revision_sequence)
                     from public.appointment_schedule_revisions t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.appointment_reschedule_proposals t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.appointment_veterinarian_assignments t), ''))
$$;
create function pg_temp.clinical_facts() returns text language sql as $$
    select md5(coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.clinical_record_entries t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.clinical_amendments t), '')
        || coalesce((select string_agg(to_jsonb(t)::text, '|' order by t.id) from public.medical_access_audit_events t), ''))
$$;
create temporary table remembered (label text primary key, value text) on commit drop;
create function pg_temp.remember(label text, value text) returns void language sql as $$
    insert into remembered values (label, value) on conflict (label) do update set value = excluded.value
$$;
create function pg_temp.recalled(label text) returns text language sql as $$
    select value from remembered where remembered.label = recalled.label
$$;
-- Every uuid in a payload must be one of the given ids.
create function pg_temp.only_ids(payload text, allowed uuid[]) returns boolean language sql immutable as $$
    select coalesce(bool_and(match[1]::uuid = any(allowed)), true)
    from regexp_matches(payload, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', 'g') as match
$$;

-- ===========================================================================
-- Fixture (data load, triggers bypassed)
--  Org (3,1) with Clinic 1 "Clínica Norte".
--  1 Maria, Guardian of Luna and Toby   2 Pablo, current co-Guardian of Luna
--  3 former Guardian of Luna            4 Guardian of Rex only
--  5 Administrator   8 Receptionist   10 Ana, Veterinarian at Clinic 1
-- Clinic 1 Appointments, each with an ACTIVE Appointment Care Authorization:
--   1 REQUESTED, 2099              2 CONFIRMED, 2099 (before its start)
--   3 CONFIRMED, start passed      4 CONFIRMED → COMPLETED, no Entry
--   5 CONFIRMED with Entry E5      6 CONFIRMED with Entry E6 and Amendment A6
--   7 CONFIRMED 2099 → cancelled by the Clinic
--   8 CONFIRMED, start passed → no-show
--   9 REQUESTED, start passed → expired
--  10 CONFIRMED 2099 for Toby     11 CONFIRMED 2099 for Rex
--  13 CONFIRMED with Entry E13 → COMPLETED
--  Ana is the assigned Veterinarian of 5, 6 and 13.
--  14 CONFIRMED 2099, untouched by every refused caller
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'revoke-' || n || '@example.test', '2020-01-01Z' from unnest(array[1, 2, 3, 4, 5, 8, 10]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 2, 3, 4, 5, 8, 10]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 2, 3, 4, 5, 8, 10]) n;
insert into public.user_profiles (user_id, display_name) values (pg_temp.id(2, 10), 'Ana García');
insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, 1), 'Org Revoke');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.clinic(), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.clinic(), 'Clínica Norte');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n), pg_temp.id(3, 1), pg_temp.id(2, n), '2020-01-01Z' from unnest(array[5, 8, 10]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case n when 5 then 'ADMINISTRATOR' when 8 then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n = 8 then 'CLINIC' else 'ORGANIZATION' end, case when n = 8 then pg_temp.clinic() end,
    '2020-01-01Z', pg_temp.id(2, 5)
from unnest(array[5, 8, 10]) n;
insert into public.veterinarian_professional_profiles (id, user_id) values (pg_temp.id(7, 10), pg_temp.id(2, 10));
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start)
values (pg_temp.id(8, 10), pg_temp.id(7, 10), pg_temp.id(5, 10), pg_temp.clinic(), '2020-01-01Z');
insert into public.pets (id, name, species, created_at) values
    (pg_temp.luna(), 'Luna', 'Dog', '2020-01-01Z'), (pg_temp.toby(), 'Toby', 'Cat', '2020-01-01Z'),
    (pg_temp.rex(), 'Rex', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    (pg_temp.id(9, 11), pg_temp.id(2, 1), pg_temp.luna(), '2020-01-01Z', null),
    (pg_temp.id(9, 12), pg_temp.id(2, 1), pg_temp.toby(), '2020-01-01Z', null),
    (pg_temp.id(9, 21), pg_temp.id(2, 2), pg_temp.luna(), '2021-01-01Z', null),
    (pg_temp.id(9, 31), pg_temp.id(2, 3), pg_temp.luna(), '2020-01-01Z', '2025-12-01Z'),
    (pg_temp.id(9, 43), pg_temp.id(2, 4), pg_temp.rex(), '2020-01-01Z', null);

insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.appt(n),
    case n when 10 then pg_temp.toby() when 11 then pg_temp.rex() else pg_temp.luna() end,
    pg_temp.clinic(), case when n = 11 then pg_temp.id(2, 4) else pg_temp.id(2, 1) end, 'Visit ' || n,
    case when n in (1, 9) then 'REQUESTED' else 'CONFIRMED' end,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14]) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select pg_temp.appt(n), r, case r when 1 then 'REQUESTED' else 'CONFIRMED' end,
    case when n in (1, 2, 7, 10, 11, 14) then '2099-01-01T10:00Z'::timestamptz
         when n = 9 then '2026-01-15T10:00Z'::timestamptz else '2026-06-01T10:00Z'::timestamptz end,
    case when n in (1, 2, 7, 10, 11, 14) then '2099-01-01T10:30Z'::timestamptz
         when n = 9 then '2026-01-15T10:30Z'::timestamptz else '2026-06-01T10:30Z'::timestamptz end,
    'Europe/Madrid', case r when 1 then pg_temp.id(2, 1) else pg_temp.id(2, 5) end, null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14]) n, unnest(array[1, 2]) r
where r = 1 or n not in (1, 9);
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select pg_temp.ca(n),
    case n when 10 then pg_temp.toby() when 11 then pg_temp.rex() else pg_temp.luna() end,
    pg_temp.clinic(), pg_temp.id(3, 1),
    case n when 10 then pg_temp.id(9, 12) when 11 then pg_temp.id(9, 43) else pg_temp.id(9, 11) end,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE', pg_temp.appt(n), 'ACTIVE'
from unnest(array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14]) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select pg_temp.appt(n), 'REQUESTED', 'CONFIRMED', pg_temp.id(2, 5), 'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from unnest(array[2, 3, 4, 5, 6, 7, 8, 10, 11, 13, 14]) n;
set local session_replication_role = origin;

select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'revoke-suite', pg_temp.id(21, 1), null) is not null as established;
select pg_temp.flush();

-- Documentation and Appointment resolution through the client operations.
-- The documented Appointments share one slot, so Ana's periods are data.
set local session_replication_role = replica;
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select pg_temp.appt(n), pg_temp.id(8, 10), clock_timestamp(), pg_temp.id(2, 5) from unnest(array[5, 6, 13]) n;
set local session_replication_role = origin;
select pg_temp.remember('E5', pg_temp.entry(5, 1, 'Exam during care')::text);
select pg_temp.remember('E6', pg_temp.entry(6, 3, 'Visit note')::text);
select pg_temp.remember('E13', pg_temp.entry(13, 4, 'Completed visit note')::text);
select pg_temp.remember('A6', pg_temp.edit(6, pg_temp.recalled('E6')::uuid, 1, 1, 'Earlier correction'));
select pg_temp.call(5, format('select public.complete_appointment(%L, 2)::text', pg_temp.appt(n))) from unnest(array[4, 13]) n;

select pg_temp.assert_true(
    (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(4))
    and not exists (select 1 from public.clinical_record_entries where appointment_id = pg_temp.appt(4))
    and (select appointment_id = pg_temp.appt(5) from public.clinical_record_entries where id = pg_temp.recalled('E5')::uuid)
    and (select appointment_id = pg_temp.appt(6) from public.clinical_record_entries where id = pg_temp.recalled('E6')::uuid)
    and pg_temp.j(pg_temp.recalled('A6')) ->> 'outcome' = 'EDITED'
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(13))
    and (select bool_and(lifecycle_state = 'ACTIVE') from public.care_authorizations
         where id::text like 'd0370000-%' and id not in (pg_temp.ca(4), pg_temp.ca(13)))
    -- SPEC-MED-010 BR-16: completion ended the authorizations of 4 and 13.
    and (select bool_and(lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_COMPLETED')
         from public.care_authorizations where id in (pg_temp.ca(4), pg_temp.ca(13)))
    and pg_temp.hist(10, 2) ->> 'status' = 'PERMITTED'
    and pg_temp.hist(10, 3) ->> 'status' = 'PERMITTED'
    and pg_temp.hist(10, 5) ->> 'status' = 'PERMITTED'
    and pg_temp.record(10, 6) ->> 'status' = 'PERMITTED'
    and pg_temp.record(10, 13) ->> 'status' = 'PERMITTED',
    'REV precondition: the documentation states are as intended, every authorization ACTIVE except those ended by completion'
);

-- ===========================================================================
-- 1. Contract and ACL (BR-56, BR-62)
-- ===========================================================================

select pg_temp.assert_true(
    (select proc.prosecdef and proc.proconfig = array['search_path=""'] and proc.provolatile = 'v'
            and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
            and not has_function_privilege('anon', proc.oid, 'EXECUTE')
            and not has_function_privilege('service_role', proc.oid, 'EXECUTE')
            and not has_function_privilege('public', proc.oid, 'EXECUTE')
     from pg_proc as proc
     where proc.oid = 'public.revoke_my_appointment_care_authorization(uuid)'::regprocedure)
    and (select count(*) = 1 from pg_proc
         where pronamespace = 'public'::regnamespace and proname = 'revoke_my_appointment_care_authorization'),
    'REV contract: the revoke is SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only, one signature'
);

select pg_temp.assert_true(
    (select bool_and(not has_function_privilege(role_name, signature, 'EXECUTE'))
     from unnest(array['anon', 'authenticated']) as role_name,
          unnest(array['public.revoke_pet_care_authorization(uuid,text)',
                       'public.revoke_appointment_care_authorization(uuid,text)',
                       'public.grant_pet_care_authorization(uuid,uuid)']) as signature)
    and (select bool_and(has_function_privilege('service_role', signature, 'EXECUTE'))
         from unnest(array['public.revoke_pet_care_authorization(uuid,text)',
                           'public.revoke_appointment_care_authorization(uuid,text)',
                           'public.grant_pet_care_authorization(uuid,uuid)']) as signature)
    and pg_temp.call(1, format('select public.revoke_appointment_care_authorization(%L, null)::text', pg_temp.appt(14)))
        like 'ERR:42501:%'
    and pg_temp.call(1, format('select public.revoke_pet_care_authorization(%L, null)::text', pg_temp.ca(14)))
        like 'ERR:42501:%'
    and pg_temp.call(1, format('select public.grant_pet_care_authorization(%L, %L)::text', pg_temp.luna(), pg_temp.clinic()))
        like 'ERR:42501:%'
    and not exists (select 1 from public.care_authorizations
                    where pet_id = pg_temp.luna() and purpose = 'CLINICAL_INTAKE')
    and pg_temp.ca_state(14) = 'ACTIVE',
    'REV contract: the generic revoke operations and the CLINICAL_INTAKE grant are not client-executable; service_role keeps them'
);

select pg_temp.assert_true(
    pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure)
        like '%pending_reschedule_currently_acceptable boolean, medical_access_state text)'
    and (select proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""']
         from pg_proc as proc where proc.oid = 'public.get_pet_appointments(uuid)'::regprocedure)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.oid = 'public.get_pet_appointments(uuid)'::regprocedure and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE']
    and pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure) not like '%medical_access%',
    'REV contract: the Guardian read exposes medical_access_state last with its ACL unchanged; the Clinic schedule does not'
);

-- ===========================================================================
-- 2. Read state before any revocation (SPEC-APT-011 BR-35)
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(pg_temp.access_state(n) = 'ACTIVE') from unnest(array[1, 2, 3, 5, 6, 7, 8, 9, 14]) n)
    and pg_temp.access_state(4) = 'INACTIVE' and pg_temp.access_state(13) = 'INACTIVE'
    and (select item ->> 'medical_access_state' from jsonb_array_elements(pg_temp.guardian_rows(1, pg_temp.toby())) as item)
        = 'ACTIVE'
    and (select count(*) = 2 and bool_and(item ->> 'medical_access_state' = 'INACTIVE')
         from jsonb_array_elements(pg_temp.guardian_rows(2, pg_temp.luna())) as item
         where item ->> 'lifecycle_state' = 'COMPLETED')
    and (select bool_and(item ->> 'medical_access_state' = 'ACTIVE')
         from jsonb_array_elements(pg_temp.guardian_rows(2, pg_temp.luna())) as item
         where item ->> 'lifecycle_state' <> 'COMPLETED'),
    'REV read: medical_access_state is ACTIVE in every lifecycle while the authorization is ACTIVE and INACTIVE once completion ended it, for every current Guardian'
);

-- ===========================================================================
-- 3. Authority before existence (BR-57)
-- ===========================================================================

select pg_temp.remember('facts_before_refusals', pg_temp.appointment_facts() || pg_temp.clinical_facts());
select pg_temp.assert_true(
    pg_temp.revoke(4, 14) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke(3, 14) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke_raw(1, pg_temp.id(11, 999)) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke_raw(4, pg_temp.id(11, 999)) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke(1, 11) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke(2, 10) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke(8, 14) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke(10, 14) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.revoke(5, 14) = 'ERR:42501:-:Appointment medical access unavailable'
    and pg_temp.ca_state(14) = 'ACTIVE' and pg_temp.ca_state(11) = 'ACTIVE' and pg_temp.ca_state(10) = 'ACTIVE'
    and pg_temp.appointment_facts() || pg_temp.clinical_facts() = pg_temp.recalled('facts_before_refusals'),
    'REV authority: another Pet''s Guardian, a former Guardian, staff, an unknown and a foreign Appointment are refused alike'
);

select pg_temp.assert_true(
    pg_temp.revoke(0, 14) like 'ERR:28000:%'
    and pg_temp.revoke_raw(1, null) like 'ERR:22023:INVALID_APPOINTMENT:%'
    and pg_temp.revoke_raw(4, null) like 'ERR:22023:INVALID_APPOINTMENT:%'
    and pg_temp.ca_state(14) = 'ACTIVE',
    'REV arguments: an unauthenticated caller is 28000 and a missing Appointment is rejected by shape alone'
);

-- ===========================================================================
-- 4. Revocation, Appointment integrity and replay (BR-58–BR-60)
-- ===========================================================================

select pg_temp.remember('appointments_before', pg_temp.appointment_facts());
select pg_temp.remember('first', pg_temp.revoke(1, 2));
select pg_temp.assert_true(
    pg_temp.recalled('first') = 'OK:{"outcome": "REVOKED"}'
    and pg_temp.ca_state(2) = 'REVOKED'
    and (select revoking_user_id = pg_temp.id(2, 1) and revoked_at is not null and revocation_reason is null
                and ended_at is null
         from public.care_authorizations where id = pg_temp.ca(2)),
    'REV revoke: a current Guardian revokes a confirmed Appointment''s authorization by the Appointment alone'
);
select pg_temp.assert_true(
    pg_temp.appointment_facts() = pg_temp.recalled('appointments_before')
    and (select lifecycle_state = 'CONFIRMED' from public.appointments where id = pg_temp.appt(2)),
    'REV revoke: the Appointment, its schedule and lifecycle history are unchanged'
);
select pg_temp.assert_true(
    (select array_agg(key) = array['outcome'] from jsonb_object_keys(pg_temp.j(pg_temp.recalled('first'))) as key)
    and pg_temp.only_ids(pg_temp.recalled('first'), '{}'),
    'REV payload: the result carries only the outcome'
);

select pg_temp.remember('ca2_row', pg_temp.ca_row(2));
select pg_temp.assert_true(
    pg_temp.revoke(1, 2) = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and pg_temp.revoke(2, 2) = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and pg_temp.ca_row(2) = pg_temp.recalled('ca2_row'),
    'REV replay: an exact retry reconciles to ALREADY_INACTIVE and rewrites nothing'
);

-- Every lifecycle with an ACTIVE authorization, also by the co-Guardian.
-- State-changing calls run as their own statements: a boolean chain has no
-- guaranteed evaluation order.
select pg_temp.remember('appointments_before', pg_temp.appointment_facts());
select pg_temp.remember('revoked_1', pg_temp.revoke(2, 1));
select pg_temp.remember('revoked_3', pg_temp.revoke(1, 3));
select pg_temp.remember('revoked_4', pg_temp.revoke(1, 4));
select pg_temp.assert_true(
    pg_temp.recalled('revoked_1') = 'OK:{"outcome": "REVOKED"}'
    and (select revoking_user_id = pg_temp.id(2, 2) from public.care_authorizations where id = pg_temp.ca(1))
    and pg_temp.recalled('revoked_3') = 'OK:{"outcome": "REVOKED"}'
    and pg_temp.recalled('revoked_4') = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_COMPLETED' and revoked_at is null
         from public.care_authorizations where id = pg_temp.ca(4))
    and pg_temp.appointment_facts() = pg_temp.recalled('appointments_before')
    and (select array_agg(lifecycle_state order by id) from public.appointments
         where id in (pg_temp.appt(1), pg_temp.appt(3), pg_temp.appt(4))) = array['REQUESTED', 'CONFIRMED', 'COMPLETED'],
    'REV lifecycle: REQUESTED and CONFIRMED-after-start authorizations are revocable by any current Guardian; a COMPLETED one was already ended and reconciles to ALREADY_INACTIVE (SPEC-MED-010 BR-16); the lifecycle stays'
);
select pg_temp.assert_true(
    pg_temp.denied(pg_temp.hist(10, 1)) and pg_temp.denied(pg_temp.hist(10, 2)) and pg_temp.denied(pg_temp.hist(10, 3)),
    'REV lifecycle: no prior history is readable after revocation (SPEC-MED-010 BR-14)'
);

-- Already ENDED through cancellation, no-show and expiry.
select pg_temp.call(5, format('select public.cancel_appointment(%L, %L, %L, 2)::text', pg_temp.appt(7), 'CLINIC', 'Clinic closed'));
select pg_temp.call(5, format('select public.mark_appointment_no_show(%L, 2)::text', pg_temp.appt(8)));
select public.expire_lapsed_appointment_requests(clock_timestamp());
select pg_temp.flush();
select pg_temp.remember('ended_rows', pg_temp.ca_row(7) || pg_temp.ca_row(8) || pg_temp.ca_row(9));
select pg_temp.assert_true(
    (select array_agg(lifecycle_state order by id) from public.appointments
     where id in (pg_temp.appt(7), pg_temp.appt(8), pg_temp.appt(9))) = array['CANCELLED', 'NO_SHOW', 'EXPIRED']
    and pg_temp.ca_state(7) = 'ENDED' and pg_temp.ca_state(8) = 'ENDED' and pg_temp.ca_state(9) = 'ENDED'
    and pg_temp.revoke(1, 7) = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and pg_temp.revoke(1, 8) = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and pg_temp.revoke(2, 9) = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and pg_temp.ca_row(7) || pg_temp.ca_row(8) || pg_temp.ca_row(9) = pg_temp.recalled('ended_rows')
    and (select bool_and(revoked_at is null and revoking_user_id is null) from public.care_authorizations
         where id in (pg_temp.ca(7), pg_temp.ca(8), pg_temp.ca(9))),
    'REV replay: an authorization ended by cancellation, no-show or expiry reconciles to ALREADY_INACTIVE and stays ENDED'
);

-- A cancellation after revocation leaves the revocation as it was.
select pg_temp.call(1, format('select public.cancel_appointment(%L, %L, null, null)::text', pg_temp.appt(2), 'GUARDIAN'));
select pg_temp.assert_true(
    (select lifecycle_state = 'CANCELLED' from public.appointments where id = pg_temp.appt(2))
    and pg_temp.ca_row(2) = pg_temp.recalled('ca2_row'),
    'REV replay: cancelling after revocation keeps the authorization REVOKED with its original actor and time'
);

-- ===========================================================================
-- 5. Guardian read after revocation (SPEC-APT-011 BR-35)
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.access_state(1) = 'REVOKED' and pg_temp.access_state(2) = 'REVOKED'
    and pg_temp.access_state(3) = 'REVOKED' and pg_temp.access_state(4) = 'INACTIVE'
    and pg_temp.access_state(7) = 'INACTIVE' and pg_temp.access_state(8) = 'INACTIVE'
    and pg_temp.access_state(9) = 'INACTIVE' and pg_temp.access_state(14) = 'ACTIVE'
    and jsonb_array_length(pg_temp.guardian_rows(1, pg_temp.luna())) = 11
    and pg_temp.guardian_rows(2, pg_temp.luna()) = pg_temp.guardian_rows(1, pg_temp.luna())
    and position(pg_temp.ca(1)::text in pg_temp.guardian_rows(1, pg_temp.luna())::text) = 0
    and position(pg_temp.ca(14)::text in pg_temp.guardian_rows(1, pg_temp.luna())::text) = 0
    and (select bool_and(item ->> 'medical_access_state' in ('ACTIVE', 'REVOKED', 'INACTIVE'))
         from jsonb_array_elements(pg_temp.guardian_rows(1, pg_temp.luna())) as item),
    'REV read: revoked Appointments stay visible as REVOKED, ended ones are INACTIVE, the same for every Guardian, with no authorization id'
);

-- ===========================================================================
-- 6. Clinical effects (BR-61)
-- ===========================================================================

select pg_temp.remember('guardian_history', (pg_temp.guardian_history() #> '{payload,entries}')::text);
select pg_temp.remember('clinical_before', pg_temp.clinical_facts());
select pg_temp.remember('revoked_5', pg_temp.revoke(1, 5));
select pg_temp.remember('revoked_6', pg_temp.revoke(1, 6));
select pg_temp.remember('revoked_13', pg_temp.revoke(2, 13));
select pg_temp.assert_true(
    pg_temp.recalled('revoked_5') = 'OK:{"outcome": "REVOKED"}'
    and pg_temp.recalled('revoked_6') = 'OK:{"outcome": "REVOKED"}'
    and pg_temp.recalled('revoked_13') = 'OK:{"outcome": "ALREADY_INACTIVE"}'
    and pg_temp.clinical_facts() = pg_temp.recalled('clinical_before'),
    'REV clinical: revocation deletes and rewrites no Entry, Amendment or audit event'
);
select pg_temp.assert_true(
    pg_temp.denied(pg_temp.hist(10, 5))
    and pg_temp.denied(pg_temp.hist(10, 3))
    and pg_temp.denied(pg_temp.hist(10, 1)),
    'REV clinical: professional longitudinal history is denied after revocation, before and after documentation began'
);

-- Documentation access does not depend on the Care Authorization
-- (SPEC-MED-010 BR-11, BR-12): the assigned Veterinarian keeps reading,
-- recording and editing the Appointment's own record after revocation,
-- for CONFIRMED and COMPLETED Appointments alike.
select pg_temp.remember('continuity_read_5', (pg_temp.record(10, 5) ->> 'status'));
select pg_temp.remember('continuity_record_5', pg_temp.record_raw(5, 2, 'Pending note, completed'));
select pg_temp.remember('continuity_amend_5', pg_temp.edit(5, pg_temp.recalled('E5')::uuid, 2, 1, 'During care'));
select pg_temp.remember('continuity_amend_6', pg_temp.edit(6, pg_temp.recalled('E6')::uuid, 4, 2, 'After revocation'));
select pg_temp.remember('continuity_amend_13', pg_temp.edit(13, pg_temp.recalled('E13')::uuid, 5, 1, 'After completion'));
select pg_temp.remember('continuity_record_13', pg_temp.record_raw(13, 6, 'Late result'));
select pg_temp.assert_true(
    pg_temp.recalled('continuity_read_5') = 'PERMITTED'
    and pg_temp.j(pg_temp.recalled('continuity_record_5')) ->> 'outcome' = 'CREATED'
    and pg_temp.recalled('continuity_amend_5') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.recalled('continuity_amend_6') = 'OK:{"outcome": "EDITED", "version": 3}'
    and pg_temp.recalled('continuity_amend_13') = 'OK:{"outcome": "EDITED", "version": 2}'
    and pg_temp.j(pg_temp.recalled('continuity_record_13')) ->> 'outcome' = 'CREATED'
    and pg_temp.record(10, 6) ->> 'status' = 'PERMITTED'
    and pg_temp.record(10, 13) ->> 'status' = 'PERMITTED'
    and pg_temp.ca_state(5) = 'REVOKED' and pg_temp.ca_state(6) = 'REVOKED' and pg_temp.ca_state(13) = 'ENDED'
    and (select lifecycle_state = 'COMPLETED' from public.appointments where id = pg_temp.appt(13)),
    'REV clinical: revocation removes no documentation access; recording and editing never restore the authorization'
);
select pg_temp.assert_true(
    pg_temp.denied(pg_temp.hist(10, 5)) and pg_temp.denied(pg_temp.hist(10, 6)),
    'REV clinical: documenting after revocation never reopens prior history'
);

select pg_temp.assert_true(
    pg_temp.guardian_history() ->> 'status' = 'PERMITTED'
    and (select bool_and(position(original.item ->> 'id' in (pg_temp.guardian_history() #> '{payload,entries}')::text) > 0)
         from jsonb_array_elements(pg_temp.recalled('guardian_history')::jsonb) as original(item))
    and jsonb_array_length(pg_temp.recalled('guardian_history')::jsonb) = 3
    and jsonb_array_length(pg_temp.guardian_history() #> '{payload,entries}') = 5,
    'REV guardian: the Guardian''s medical history keeps every Entry after revocation, and shows those recorded after it'
);

rollback;

-- Zero retained fixture rows after rollback.
do $$
declare t record; n bigint; begin
    for t in select table_schema, table_name from information_schema.columns
             where table_schema in ('public', 'auth') and column_name = 'id' loop
        execute format('select count(*) from %I.%I where id::text like %L', t.table_schema, t.table_name, 'd0370000-%')
        into n;
        if n <> 0 then raise exception 'Retained fixtures in %.%', t.table_schema, t.table_name; end if;
    end loop;
end $$;

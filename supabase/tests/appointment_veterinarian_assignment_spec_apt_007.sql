-- Appointment Veterinarian assignment contract — Punto 8, stage M1:
-- SPEC-APT-007 §13/§14 (Verification Notes 21–33), SPEC-APT-008, ADR-011 §5.
-- Migration 20261112090000_appointment_veterinarian_assignment_contract.sql.
--
-- Isolated LOCAL superuser only; fixtures and assertions are rollback-only.
-- The organizational and scheduling context is loaded as data with triggers
-- bypassed (as in appointment_clinical_record_spec_med_010.sql); every
-- behavioural call goes through the client operations as the impersonated User
-- under the authenticated role, and deferred integrity is flushed after each
-- call. Fixture prefix d0350000-.
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
create function pg_temp.vca(n integer) returns uuid language sql immutable as $$ select pg_temp.id(8, n) $$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end $$;
-- 'OK:<value>' or 'ERR:<sqlstate>:<hint or ->:<message>'. A failure leaves
-- nothing behind (subtransaction), deferred integrity included.
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
create function pg_temp.assign(actor integer, appointment_n integer, vca uuid, token uuid, clinic_n integer default 1)
returns text language sql as $$
    select pg_temp.call(actor, format('select public.assign_appointment_veterinarian(%L, %L, %L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n), vca, token))
$$;
create function pg_temp.me(actor integer, appointment_n integer, clinic_n integer default 1) returns text
language sql as $$
    select pg_temp.call(actor, format('select public.assign_me_to_appointment(%L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n)))
$$;
create function pg_temp.view(actor integer, appointment_n integer, clinic_n integer default 1) returns text
language sql as $$
    select pg_temp.call(actor, format('select public.get_appointment_veterinarian_assignment(%L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n)))
$$;
create function pg_temp.candidates(actor integer, appointment_n integer, clinic_n integer default 1) returns jsonb
language sql as $$
    select pg_temp.j(pg_temp.call(actor, format('select public.get_appointment_veterinarian_candidates(%L, %L)::text',
        pg_temp.clinic(clinic_n), pg_temp.appt(appointment_n))))
$$;
create function pg_temp.current_vca(appointment_n integer) returns uuid language sql as $$
    select veterinarian_clinic_assignment_id from public.appointment_veterinarian_assignments
    where appointment_id = pg_temp.appt(appointment_n) and effective_end is null
$$;
create function pg_temp.token(appointment_n integer) returns uuid language sql as $$
    select id from public.appointment_veterinarian_assignments
    where appointment_id = pg_temp.appt(appointment_n) and effective_end is null
$$;
create function pg_temp.periods(appointment_n integer) returns bigint language sql as $$
    select count(*) from public.appointment_veterinarian_assignments where appointment_id = pg_temp.appt(appointment_n)
$$;
create function pg_temp.hint(outcome text) returns text language sql immutable as $$
    select split_part(outcome, ':', 3)
$$;
create temporary table facts (label text primary key, outcome text) on commit drop;
create function pg_temp.keep(label text, outcome text) returns text language sql as $$
    insert into facts values (label, outcome) returning outcome
$$;
create function pg_temp.fact(label text) returns text language sql as $$
    select outcome from facts where facts.label = fact.label
$$;

-- ===========================================================================
-- Fixture (data load, triggers bypassed)
--  1 Guardian of Luna      5 Administrator of Org A     8 Receptionist of Clinic 1
-- 10, 11 Veterinarians at Clinic 1
-- 13 Veterinarian whose Clinic 1 Assignment ended (stale assignee)
-- 17 Veterinarian of Org B (Clinic 3)     18 Veterinarian at Clinic 2 (Org A)
-- 19 Receptionist of Clinic 1 with a Veterinarian profile and Clinic Assignment
--    but no VETERINARIAN Responsibility
-- 20 Receptionist of Clinic 4 (Org C, no Subscription)   21 Veterinarian at Clinic 4
-- Appointments (Luna), each on its own day unless stated:
--   CONFIRMED 1–8, 18 (18 overlaps 1)     COMPLETED 9, 10 (10 overlaps 1)
--   REQUESTED 11   CANCELLED 12   NO_SHOW 13   EXPIRED 14
--   15: CONFIRMED at Clinic 2.  16: CONFIRMED and 17: COMPLETED at Clinic 4.
--    3: current assignment to Veterinarian 13 (stale).
-- No Veterinarian Availability exists anywhere.
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'ava-' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 5, 8, 10, 11, 13, 17, 18, 19, 20, 21]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 5, 8, 10, 11, 13, 17, 18, 19, 20, 21]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 5, 8, 10, 11, 13, 17, 18, 19, 20, 21]) n;
insert into public.user_profiles (user_id, display_name)
select pg_temp.id(2, n), 'Person ' || n from unnest(array[5, 8, 10, 11, 13, 17, 18, 19, 20, 21]) n;
insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.id(3, 1), 'AVA Org A'), (pg_temp.id(3, 2), 'AVA Org B'), (pg_temp.id(3, 3), 'AVA Org C');
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes)
values (pg_temp.clinic(1), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(2), pg_temp.id(3, 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(3), pg_temp.id(3, 2), true, '2020-01-01Z', 'Europe/Madrid', 30),
       (pg_temp.clinic(4), pg_temp.id(3, 3), true, '2020-01-01Z', 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select pg_temp.id(5, n),
       pg_temp.id(3, case when n = 17 then 2 when n in (20, 21) then 3 else 1 end),
       pg_temp.id(2, n), '2020-01-01Z'
from unnest(array[5, 8, 10, 11, 13, 17, 18, 19, 20, 21]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, granted_by_user_id)
select pg_temp.id(6, n), pg_temp.id(5, n),
    case when n = 5 then 'ADMINISTRATOR' when n in (8, 19, 20) then 'RECEPTIONIST' else 'VETERINARIAN' end,
    case when n in (8, 19, 20) then 'CLINIC' else 'ORGANIZATION' end,
    case when n in (8, 19) then pg_temp.clinic(1) when n = 20 then pg_temp.clinic(4) end,
    '2020-01-01Z', pg_temp.id(2, 5)
from unnest(array[5, 8, 10, 11, 13, 17, 18, 19, 20, 21]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select pg_temp.id(7, n), pg_temp.id(2, n) from unnest(array[10, 11, 13, 17, 18, 19, 21]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start, effective_end)
values (pg_temp.vca(10), pg_temp.id(7, 10), pg_temp.id(5, 10), pg_temp.clinic(1), '2020-01-01Z', null),
       (pg_temp.vca(11), pg_temp.id(7, 11), pg_temp.id(5, 11), pg_temp.clinic(1), '2020-01-01Z', null),
       (pg_temp.vca(13), pg_temp.id(7, 13), pg_temp.id(5, 13), pg_temp.clinic(1), '2020-01-01Z', '2026-01-01Z'),
       (pg_temp.vca(17), pg_temp.id(7, 17), pg_temp.id(5, 17), pg_temp.clinic(3), '2020-01-01Z', null),
       (pg_temp.vca(18), pg_temp.id(7, 18), pg_temp.id(5, 18), pg_temp.clinic(2), '2020-01-01Z', null),
       (pg_temp.vca(19), pg_temp.id(7, 19), pg_temp.id(5, 19), pg_temp.clinic(1), '2020-01-01Z', null),
       (pg_temp.vca(21), pg_temp.id(7, 21), pg_temp.id(5, 21), pg_temp.clinic(4), '2020-01-01Z', null);
insert into public.pets (id, name, species, created_at) values (pg_temp.id(9, 1), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (pg_temp.id(9, 11), pg_temp.id(2, 1), pg_temp.id(9, 1), '2020-01-01Z');
create temporary table seed (n integer primary key, state text, clinic_n integer, day_n integer) on commit drop;
insert into seed
select n,
       case when n in (9, 10, 17) then 'COMPLETED' when n = 11 then 'REQUESTED' when n = 12 then 'CANCELLED'
            when n = 13 then 'NO_SHOW' when n = 14 then 'EXPIRED' else 'CONFIRMED' end,
       case when n = 15 then 2 when n in (16, 17) then 4 else 1 end,
       case when n in (10, 18) then 1 else n end
from generate_series(1, 18) n;
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.appt(n), pg_temp.id(9, 1), pg_temp.clinic(clinic_n), pg_temp.id(2, 1), 'Visit ' || n, state,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from seed;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select pg_temp.appt(n), r, case r when 1 then 'REQUESTED' else 'CONFIRMED' end,
    '2026-06-01T10:00Z'::timestamptz + make_interval(days => day_n),
    '2026-06-01T10:30Z'::timestamptz + make_interval(days => day_n),
    'Europe/Madrid', pg_temp.id(2, case r when 1 then 1 else 8 end), null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from seed, unnest(array[1, 2]) r
where r = 1 or seed.state not in ('REQUESTED', 'EXPIRED');
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select pg_temp.id(12, n), pg_temp.id(9, 1), pg_temp.clinic(clinic_n),
    pg_temp.id(3, case when clinic_n = 4 then 3 else 1 end), pg_temp.id(9, 11),
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE', pg_temp.appt(n), 'ACTIVE'
from seed;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select pg_temp.appt(n), 'REQUESTED', 'CONFIRMED', pg_temp.id(2, 8), 'CLINIC', null::text, '2026-02-01Z'::timestamptz, '2026-02-01Z'::timestamptz
from seed where state not in ('REQUESTED', 'EXPIRED')
union all
select pg_temp.appt(n), 'CONFIRMED', 'COMPLETED', pg_temp.id(2, 8), 'CLINIC', null::text, '2026-06-20Z'::timestamptz, '2026-06-20Z'::timestamptz
from seed where state = 'COMPLETED';
insert into public.appointment_veterinarian_assignments (id, appointment_id, veterinarian_clinic_assignment_id,
    effective_start, effective_end, assigned_by_user_id)
values (pg_temp.id(14, 3), pg_temp.appt(3), pg_temp.vca(13), '2025-12-01Z', null, pg_temp.id(2, 8));
set local session_replication_role = origin;

select public.establish_organization_subscription(pg_temp.id(3, 1), null, 'ACTIVE', '2020-01-01Z', null, null,
    'assignment-suite', pg_temp.id(20, 1), null) is not null as established_a,
       public.establish_organization_subscription(pg_temp.id(3, 2), null, 'ACTIVE', '2020-01-01Z', null, null,
    'assignment-suite', pg_temp.id(20, 2), null) is not null as established_b;
select pg_temp.flush();

create temporary table before_state on commit drop as
select appointment.id, appointment.lifecycle_state, care_auth.lifecycle_state as authorization_state,
       (select count(*) from public.appointment_lifecycle_events as event where event.appointment_id = appointment.id) as events,
       (select count(*) from public.appointment_schedule_revisions as revision where revision.appointment_id = appointment.id) as revisions
from public.appointments as appointment
join public.care_authorizations as care_auth on care_auth.appointment_id = appointment.id
where appointment.id in (select pg_temp.appt(n) from seed);

-- ===========================================================================
-- 1. Contract and ACL (Note 33)
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.proconfig = array['search_path=""']
                     and has_function_privilege('authenticated', proc.oid, 'EXECUTE')
                     and not has_function_privilege('anon', proc.oid, 'EXECUTE')
                     and not has_function_privilege('service_role', proc.oid, 'EXECUTE'))
       and count(*) = 4
     from pg_proc as proc
     where proc.pronamespace = 'public'::regnamespace
       and proc.proname in ('get_appointment_veterinarian_assignment', 'assign_appointment_veterinarian',
                            'assign_me_to_appointment', 'get_appointment_veterinarian_candidates')),
    'AVA contract: client operations are SECURITY DEFINER, empty search_path, authenticated-only'
);
select pg_temp.assert_true(
    not has_function_privilege('authenticated', 'public.assign_veterinarian_to_appointment(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.reassign_veterinarian(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.assign_veterinarian_to_appointment(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.reassign_veterinarian(uuid,uuid)', 'EXECUTE'),
    'Note 33: the withdrawn assignment operations are not client-executable'
);
select pg_temp.assert_true(
    (select bool_and(not has_function_privilege(role_name, signature::regprocedure, 'EXECUTE'))
     from unnest(array[
        'public.appointment_veterinarian_is_eligible(uuid,uuid)',
        'public.appointment_accepts_veterinarian_assignment(uuid,text)',
        'public.veterinarian_clinic_assignment_display_name(uuid)',
        'public.establish_appointment_veterinarian_period(uuid,text,uuid,uuid,uuid,uuid)'
     ]) as signature, unnest(array['anon', 'authenticated', 'service_role']) as role_name),
    'AVA contract: private helpers are executable by no client role'
);

-- ===========================================================================
-- 2. Managed assignment and reassignment (Notes 21, 26, 28, 29)
-- ===========================================================================

select pg_temp.keep('assign_1', pg_temp.assign(8, 1, pg_temp.vca(10), null));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('assign_1')) ->> 'outcome' = 'ASSIGNED'
    and (pg_temp.j(pg_temp.fact('assign_1')) ->> 'assignment_token')::uuid = pg_temp.token(1)
    and pg_temp.current_vca(1) = pg_temp.vca(10),
    'Note 21/29: a Receptionist assigns an eligible Veterinarian to a CONFIRMED Appointment with no Availability: ' || pg_temp.fact('assign_1')
);
select pg_temp.assert_true(
    pg_temp.j(pg_temp.assign(8, 1, pg_temp.vca(10), null)) ->> 'outcome' = 'ALREADY_ASSIGNED'
    and pg_temp.periods(1) = 1,
    'Note 21: repeating the same assignment returns ALREADY_ASSIGNED and writes nothing'
);
select pg_temp.assert_true(
    pg_temp.hint(pg_temp.assign(5, 1, pg_temp.vca(11), null)) = 'STALE_ASSIGNMENT'
    and pg_temp.assign(5, 1, pg_temp.vca(11), null) like 'ERR:P0001:%'
    and pg_temp.current_vca(1) = pg_temp.vca(10) and pg_temp.periods(1) = 1,
    'Note 26: a reassignment from an outdated view is STALE_ASSIGNMENT (P0001) and writes nothing'
);
select pg_temp.keep('reassign_1', pg_temp.assign(5, 1, pg_temp.vca(11), pg_temp.token(1)));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('reassign_1')) ->> 'outcome' = 'REASSIGNED'
    and pg_temp.current_vca(1) = pg_temp.vca(11)
    and pg_temp.periods(1) = 2
    and (select count(*) = 1 from public.appointment_veterinarian_assignments
         where appointment_id = pg_temp.appt(1) and effective_end is null)
    and exists (
        select 1
        from public.appointment_veterinarian_assignments as ended
        join public.appointment_veterinarian_assignments as successor
          on successor.appointment_id = ended.appointment_id
         and successor.effective_start = ended.effective_end
        where ended.appointment_id = pg_temp.appt(1)
          and ended.veterinarian_clinic_assignment_id = pg_temp.vca(10)
          and successor.veterinarian_clinic_assignment_id = pg_temp.vca(11)
          and successor.assigned_by_user_id = pg_temp.id(2, 5)),
    'Note 21/28: an Administrator reassigns; the previous period ends when the next starts, recording the actor: ' || pg_temp.fact('reassign_1')
);
select pg_temp.keep('assign_9', pg_temp.assign(8, 9, pg_temp.vca(10), null));
select pg_temp.keep('reassign_9', pg_temp.assign(8, 9, pg_temp.vca(11), pg_temp.token(9)));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('assign_9')) ->> 'outcome' = 'ASSIGNED'
    and pg_temp.j(pg_temp.fact('reassign_9')) ->> 'outcome' = 'REASSIGNED'
    and pg_temp.current_vca(9) = pg_temp.vca(11),
    'Note 21: a COMPLETED Appointment is assigned and reassigned'
);
select pg_temp.assert_true(
    pg_temp.assign(10, 4, pg_temp.vca(10), null) like 'ERR:42501:-:%'
    and pg_temp.periods(4) = 0,
    'Note 21: a Veterinarian without APPOINTMENT_ASSIGN_VETERINARIAN cannot use the managed operation'
);

-- 29: overlap rule for CONFIRMED only. 18 and 10 overlap 1 (assigned to 11).
select pg_temp.assert_true(
    pg_temp.hint(pg_temp.assign(8, 18, pg_temp.vca(11), null)) = 'VETERINARIAN_SCHEDULE_CONFLICT'
    and pg_temp.assign(8, 18, pg_temp.vca(11), null) like 'ERR:23514:%'
    and pg_temp.periods(18) = 0,
    'Note 29: an overlapping confirmed commitment is rejected with VETERINARIAN_SCHEDULE_CONFLICT'
);
select pg_temp.keep('assign_10', pg_temp.assign(8, 10, pg_temp.vca(11), null));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('assign_10')) ->> 'outcome' = 'ASSIGNED',
    'Note 29: a COMPLETED Appointment is not a future commitment and is not checked for overlap'
);

-- ===========================================================================
-- 3. Self-assignment (Notes 22, 27)
-- ===========================================================================

select pg_temp.keep('me_2', pg_temp.me(11, 2));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('me_2')) ->> 'outcome' = 'ASSIGNED'
    and pg_temp.current_vca(2) = pg_temp.vca(11)
    and (select assigned_by_user_id from public.appointment_veterinarian_assignments
         where id = pg_temp.token(2)) = pg_temp.id(2, 11),
    'Note 22: an eligible Veterinarian assigns themselves to an unassigned Appointment'
);
select pg_temp.assert_true(
    pg_temp.j(pg_temp.me(11, 2)) ->> 'outcome' = 'ALREADY_ASSIGNED' and pg_temp.periods(2) = 1,
    'Note 22: repeating self-assignment returns ALREADY_ASSIGNED'
);
select pg_temp.assert_true(
    pg_temp.hint(pg_temp.me(10, 2)) = 'ASSIGNED_TO_ANOTHER_VETERINARIAN'
    and pg_temp.current_vca(2) = pg_temp.vca(11) and pg_temp.periods(2) = 1,
    'Note 22/27: self-assignment never displaces an eligible colleague'
);
select pg_temp.keep('me_3', pg_temp.me(10, 3));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('me_3')) ->> 'outcome' = 'ASSIGNED'
    and pg_temp.current_vca(3) = pg_temp.vca(10)
    and (select effective_end from public.appointment_veterinarian_assignments where id = pg_temp.id(14, 3))
        = (select effective_start from public.appointment_veterinarian_assignments where id = pg_temp.token(3)),
    'Note 22: a stale assignment (ended Clinic Assignment) is replaced by self-assignment, preserving its history'
);
select pg_temp.keep('me_5', pg_temp.me(10, 5));
select pg_temp.keep('stale_5', pg_temp.assign(8, 5, pg_temp.vca(11), null));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('me_5')) ->> 'outcome' = 'ASSIGNED'
    and pg_temp.hint(pg_temp.fact('stale_5')) = 'STALE_ASSIGNMENT'
    and pg_temp.current_vca(5) = pg_temp.vca(10),
    'Note 27: a managed assignment from a view taken before a self-assignment is stale; one assignee remains'
);
select pg_temp.assert_true(
    pg_temp.me(19, 6) like 'ERR:42501:-:%' and pg_temp.me(8, 6) like 'ERR:42501:-:%'
    and pg_temp.me(5, 6) like 'ERR:42501:-:%' and pg_temp.periods(6) = 0,
    'Note 22: a Receptionist, an Administrator, and a profiled non-Veterinarian cannot self-assign'
);

-- ===========================================================================
-- 4. Lifecycle states (Note 23)
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(pg_temp.hint(pg_temp.assign(8, n, pg_temp.vca(10), null)) = 'APPOINTMENT_STATE_INVALID'
                     and pg_temp.hint(pg_temp.me(10, n)) = 'APPOINTMENT_STATE_INVALID'
                     and pg_temp.periods(n) = 0)
     from unnest(array[11, 12, 13, 14]) n),
    'Note 23: REQUESTED, CANCELLED, NO_SHOW, and EXPIRED Appointments are APPOINTMENT_STATE_INVALID'
);

-- ===========================================================================
-- 5. Eligibility and uniform denial (Notes 24, 25)
-- ===========================================================================

select pg_temp.assert_true(
    (select bool_and(pg_temp.hint(pg_temp.assign(8, 7, target, null)) = 'VETERINARIAN_NOT_ELIGIBLE')
     from unnest(array[pg_temp.vca(18), pg_temp.vca(13), pg_temp.vca(19), pg_temp.vca(17),
                       'd0350000-0000-4000-8000-000000999999'::uuid]) target)
    and pg_temp.periods(7) = 0,
    'Note 24: another Clinic''s, an ended, a non-Veterinarian, another Organization''s, and an unknown Clinic Assignment are VETERINARIAN_NOT_ELIGIBLE'
);
select pg_temp.assert_true(
    pg_temp.assign(8, 7, null, null) like 'ERR:22023:VETERINARIAN_REQUIRED:%',
    'Note 25: a missing Veterinarian is an argument error'
);
select pg_temp.assert_true(
    (select count(distinct split_part(outcome, ':', 2) || split_part(outcome, ':', 3) || split_part(outcome, ':', 4)) = 1
            and bool_and(outcome like 'ERR:42501:-:%')
     from unnest(array[
        pg_temp.assign(17, 7, pg_temp.vca(10), null),
        pg_temp.assign(1, 7, pg_temp.vca(10), null),
        pg_temp.assign(8, 15, pg_temp.vca(10), null),
        pg_temp.call(8, format('select public.assign_appointment_veterinarian(%L, %L, %L, null)::text',
            pg_temp.clinic(1), 'd0350000-0000-4000-8000-000000888888'::uuid, pg_temp.vca(10))),
        pg_temp.me(17, 7), pg_temp.me(1, 7), pg_temp.me(18, 15, 1)
     ]) as outcome),
    'Note 25: another Organization''s Veterinarian, a Guardian, a foreign or unknown Appointment receive the same 42501'
);
select pg_temp.assert_true(
    pg_temp.call(0, format('select public.assign_me_to_appointment(%L, %L)::text', pg_temp.clinic(1), pg_temp.appt(7)))
        like 'ERR:28000:%',
    'Note 25: an unauthenticated caller is rejected with 28000'
);

-- ===========================================================================
-- 6. Entitlement (Note 30): Org C has no Subscription.
-- ===========================================================================

select pg_temp.assert_true(
    pg_temp.hint(pg_temp.assign(20, 16, pg_temp.vca(21), null, 4)) = 'SCHEDULING_SERVICE_UNAVAILABLE'
    and pg_temp.hint(pg_temp.me(21, 16, 4)) = 'SCHEDULING_SERVICE_UNAVAILABLE'
    and pg_temp.periods(16) = 0,
    'Note 30: PROFESSIONAL_SCHEDULING is required for a CONFIRMED Appointment'
);
select pg_temp.keep('me_17', pg_temp.me(21, 17, 4));
select pg_temp.assert_true(
    pg_temp.j(pg_temp.fact('me_17')) ->> 'outcome' = 'ASSIGNED',
    'Note 30: no Entitlement is required for a COMPLETED Appointment'
);

-- ===========================================================================
-- 7. Reads (Note 32)
-- ===========================================================================

select pg_temp.assert_true(
    (select array_agg(key order by key) from jsonb_object_keys(pg_temp.j(pg_temp.view(8, 1))) as key)
        = array['assignment_token', 'display_name', 'is_eligible', 'is_me', 'may_assign_me', 'may_manage', 'status']
    and pg_temp.j(pg_temp.view(8, 1)) @> jsonb_build_object(
        'status', 'ASSIGNED', 'display_name', 'Person 11', 'is_me', false, 'is_eligible', true,
        'may_assign_me', false, 'may_manage', true)
    and (pg_temp.j(pg_temp.view(8, 1)) ->> 'assignment_token')::uuid = pg_temp.token(1),
    'Note 32: the assignment read returns exactly the BR-37 fields for a Receptionist'
);
select pg_temp.assert_true(
    pg_temp.j(pg_temp.view(11, 1)) @> '{"is_me": true, "may_assign_me": false, "may_manage": false}'
    and pg_temp.j(pg_temp.view(10, 4)) = '{"status": "UNASSIGNED", "may_assign_me": true, "may_manage": false}'::jsonb
    and pg_temp.j(pg_temp.view(10, 11)) = '{"status": "UNASSIGNED", "may_assign_me": false, "may_manage": false}'::jsonb,
    'Note 32: is_me and the advisory actions follow the actor and the Appointment state'
);
select pg_temp.assert_true(
    pg_temp.view(17, 1) like 'ERR:42501:-:Clinic Appointment unavailable%'
    and pg_temp.view(1, 1) like 'ERR:42501:-:Clinic Appointment unavailable%'
    and pg_temp.view(8, 15) like 'ERR:42501:-:Clinic Appointment unavailable%',
    'Note 32: the assignment read has the uniform denial of get_clinic_appointment'
);
select pg_temp.assert_true(
    pg_temp.candidates(8, 1) ->> 'status' = 'PERMITTED'
    and (select array_agg((candidate ->> 'veterinarian_clinic_assignment_id')::uuid order by candidate ->> 'display_name')
         from jsonb_array_elements(pg_temp.candidates(8, 1) -> 'candidates') as candidate)
        = array[pg_temp.vca(10), pg_temp.vca(11)]
    and (select bool_and((select array_agg(key order by key) from jsonb_object_keys(candidate) as key)
                         = array['display_name', 'is_current_assignee', 'is_me', 'veterinarian_clinic_assignment_id'])
         from jsonb_array_elements(pg_temp.candidates(8, 1) -> 'candidates') as candidate)
    and pg_temp.candidates(8, 1) -> 'history' @> jsonb_build_array(
        jsonb_build_object('veterinarian_display_name', 'Person 10', 'assigned_by_display_name', 'Person 8'),
        jsonb_build_object('veterinarian_display_name', 'Person 11', 'assigned_by_display_name', 'Person 5', 'ended_at', null))
    and jsonb_array_length(pg_temp.candidates(8, 1) -> 'history') = 2,
    'Note 32: candidates are the eligible Veterinarians only, with history and no other identifier'
);
select pg_temp.assert_true(
    pg_temp.candidates(10, 1) = '{"status": "DENIED"}'::jsonb
    and pg_temp.candidates(17, 1) = '{"status": "DENIED"}'::jsonb
    and pg_temp.candidates(8, 15) = '{"status": "DENIED"}'::jsonb,
    'Note 32: the candidates read is denied without APPOINTMENT_ASSIGN_VETERINARIAN or for a foreign Appointment'
);

-- ===========================================================================
-- 8. Effects (Note 31) and structural succession (BR-36)
-- ===========================================================================

select pg_temp.assert_true(
    not exists (
        select 1
        from before_state
        join public.appointments as appointment on appointment.id = before_state.id
        join public.care_authorizations as care_auth on care_auth.appointment_id = appointment.id
        where appointment.lifecycle_state is distinct from before_state.lifecycle_state
           or care_auth.lifecycle_state is distinct from before_state.authorization_state
           or (select count(*) from public.appointment_lifecycle_events as event
               where event.appointment_id = appointment.id) <> before_state.events
           or (select count(*) from public.appointment_schedule_revisions as revision
               where revision.appointment_id = appointment.id) <> before_state.revisions)
    and not exists (select 1 from public.clinical_record_entries where appointment_id in (select pg_temp.appt(n) from seed))
    and not exists (select 1 from public.transactional_communications where appointment_id in (select pg_temp.appt(n) from seed)),
    'Note 31: assignment changes no lifecycle, Care Authorization, scheduling, clinical record, or Communication'
);
reset role;
select pg_temp.assert_true(
    (select coalesce(bool_and(false), true) from (
        select 1
        from public.appointment_veterinarian_assignments as ended
        where ended.appointment_id in (select pg_temp.appt(n) from seed)
          and ended.effective_end is not null
          and not exists (select 1 from public.appointment_veterinarian_assignments as next_period
                          where next_period.appointment_id = ended.appointment_id
                            and next_period.effective_start = ended.effective_end)) as orphan),
    'BR-36: every ended period has a same-instant successor'
);
do $$
begin
    begin
        update public.appointment_veterinarian_assignments
        set effective_end = clock_timestamp()
        where appointment_id = pg_temp.appt(1) and effective_end is null;
        set constraints all immediate;
        raise exception 'succession rule did not fire';
    exception when sqlstate '23514' then
        if position('requires a successor' in sqlerrm) = 0 then raise; end if;
    end;
end $$;
set constraints all deferred;

rollback;

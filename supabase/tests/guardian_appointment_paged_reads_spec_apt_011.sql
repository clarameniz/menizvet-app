-- SPEC-APT-011 §13 (BR-36–BR-40) / §14 Verification Notes 38–46, as extended by
-- 20261118090000 (awaiting_clinic_confirmation; its transitions are covered by
-- guardian_appointment_awaiting_confirmation_spec_apt_011_019.sql).
-- Isolated LOCAL superuser only. Fixtures and assertions are rollback-only.
begin;
set local timezone = 'UTC';
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0130000-0000-4000-8000-' || lpad((kind * 100000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.appt(n integer) returns uuid language sql immutable as $$
    select pg_temp.id(9, n)
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', case when n = 0 then '' else pg_temp.id(1, n)::text end, true)
$$;
create function pg_temp.active_outcome(after_rank integer default null, after_start timestamptz default null,
    after_id uuid default null, page_size integer default 20) returns text language plpgsql as $$ begin
    perform * from public.get_guardian_active_appointments(after_rank, after_start, after_id, page_size);
    return 'SUCCEEDED';
exception when others then return sqlstate || ': ' || sqlerrm; end $$;
create function pg_temp.history_outcome(before_start timestamptz default null, before_id uuid default null,
    page_size integer default 20) returns text language plpgsql as $$ begin
    perform * from public.get_guardian_appointment_history(before_start, before_id, page_size);
    return 'SUCCEEDED';
exception when others then return sqlstate || ': ' || sqlerrm; end $$;
-- Every page of each read, concatenated, for one page size; a repeated row fails.
create function pg_temp.active_paged(page_size integer) returns jsonb language plpgsql as $$
declare result jsonb := '[]'; after_rank integer; after_start timestamptz; after_id uuid; r record; n integer;
    ids uuid[] := '{}';
begin
    loop
        n := 0;
        for r in select * from public.get_guardian_active_appointments(after_rank, after_start, after_id, page_size) loop
            perform pg_temp.assert_true(not (r.id = any(ids)), 'Active Appointment returned twice');
            ids := ids || r.id;
            result := result || jsonb_build_array(to_jsonb(r));
            after_rank := r.active_rank; after_start := r.current_scheduled_start_at; after_id := r.id; n := n + 1;
        end loop;
        exit when n < page_size;
    end loop;
    return result;
end $$;
create function pg_temp.history_paged(page_size integer) returns jsonb language plpgsql as $$
declare result jsonb := '[]'; before_start timestamptz; before_id uuid; r record; n integer; ids uuid[] := '{}';
begin
    loop
        n := 0;
        for r in select * from public.get_guardian_appointment_history(before_start, before_id, page_size) loop
            perform pg_temp.assert_true(not (r.id = any(ids)), 'History Appointment returned twice');
            ids := ids || r.id;
            result := result || jsonb_build_array(to_jsonb(r));
            before_start := r.current_scheduled_start_at; before_id := r.id; n := n + 1;
        end loop;
        exit when n < page_size;
    end loop;
    return result;
end $$;
-- The oracle (VN 39, 42): the union of get_pet_appointments, called as the
-- User, over the Pets the User currently guards, in BR-38 / BR-39 order.
create function pg_temp.expected(user_n integer, tab text) returns jsonb language plpgsql as $$
declare result jsonb;
begin
    perform pg_temp.act(user_n);
    with guarded as (
        select guardianship.pet_id
        from public.guardianships as guardianship
        where guardianship.user_id = pg_temp.id(2, user_n) and guardianship.effective_end is null
    ),
    guarded_read as (
        select read_row.*, pet.id as the_pet_id, pet.name as the_pet_name,
               case when read_row.current_scheduled_start_at > statement_timestamp() then 1 else 2 end as the_rank
        from guarded
        cross join lateral public.get_pet_appointments(guarded.pet_id) as read_row
        join public.pets as pet on pet.id = guarded.pet_id
        where (tab = 'active') = (read_row.lifecycle_state in ('REQUESTED', 'CONFIRMED'))
    )
    select coalesce(jsonb_agg(
               jsonb_build_object(
                   'id', guarded_read.id,
                   'pet_id', guarded_read.the_pet_id,
                   'pet_name', guarded_read.the_pet_name,
                   'clinic_id', guarded_read.clinic_id,
                   'lifecycle_state', guarded_read.lifecycle_state,
                   'current_scheduled_start_at', guarded_read.current_scheduled_start_at,
                   'current_scheduled_end_at', guarded_read.current_scheduled_end_at,
                   'current_scheduling_timezone_name', guarded_read.current_scheduling_timezone_name,
                   'pending_reschedule_proposing_context', guarded_read.pending_reschedule_proposing_context,
                   -- BR-33 on get_pet_appointments' own provenance column.
                   'awaiting_clinic_confirmation', guarded_read.lifecycle_state = 'REQUESTED'
                       and guarded_read.current_schedule_source_proposing_context is not distinct from 'CLINIC'
               ) || case when tab = 'active' then jsonb_build_object('active_rank', guarded_read.the_rank) else '{}' end
               order by
                   case when tab = 'active' then guarded_read.the_rank end,
                   case when tab = 'active' and guarded_read.the_rank = 1 then guarded_read.current_scheduled_start_at end,
                   case when tab = 'active' and guarded_read.the_rank = 1 then guarded_read.id end,
                   case when tab <> 'active' or guarded_read.the_rank = 2 then guarded_read.current_scheduled_start_at end desc,
                   case when tab <> 'active' or guarded_read.the_rank = 2 then guarded_read.id end desc
           ), '[]')
    into result
    from guarded_read;
    return result;
end $$;
create function pg_temp.ids_of(rows jsonb) returns uuid[] language sql immutable as $$
    select coalesce(array_agg((r->>'id')::uuid order by o), '{}') from jsonb_array_elements(rows) with ordinality as e(r, o)
$$;
create function pg_temp.fingerprint() returns text language plpgsql as $$
declare table_name text; rows_json text; result text := ''; begin
    for table_name in select tablename from pg_tables where schemaname = 'public' order by tablename loop
        execute format('select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text, '''') from public.%I r', table_name)
        into rows_json;
        result := result || table_name || rows_json;
    end loop;
    return md5(result);
end $$;

-- ===========================================================================
-- Fixtures
--
-- Users (auth id(1, n), domain id(2, n)):
--   1 Maria — current Guardian of Luna and Toby
--   2 Carlos — current co-Guardian of Luna only; requested some of Luna's
--     Appointments and proposed one new time
--   3 former Guardian of Luna (ended 2024)
--   4 current Guardian of Kira only (an unrelated Guardianship)
--   5 Organization Owner, 6 Organization Receptionist (Clinic proposer)
--   7 no Guardianship at all; 40 an Auth subject with no domain User
-- Clinics: A1 Europe/Madrid, A2 America/New_York.
-- Maria sees 21 active (16 not yet started, 5 started) and 21 terminal.
-- ===========================================================================

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'guardian-paged-' || n || '@example.test', '2020-01-01Z'
from unnest(array[1, 2, 3, 4, 5, 6, 7, 40]) n;
insert into public.users (id) select pg_temp.id(2, n) from generate_series(1, 7) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from generate_series(1, 7) n;

insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, 1), 'Guardian Paged Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.id(4, 1), pg_temp.id(3, 1), true, 'Europe/Madrid', 30),
       (pg_temp.id(4, 2), pg_temp.id(3, 1), true, 'America/New_York', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    (pg_temp.id(5, 5), pg_temp.id(3, 1), pg_temp.id(2, 5), '2020-01-01Z'),
    (pg_temp.id(5, 6), pg_temp.id(3, 1), pg_temp.id(2, 6), '2020-01-01Z');
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values
    (pg_temp.id(6, 5), pg_temp.id(5, 5), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 5)),
    (pg_temp.id(6, 6), pg_temp.id(5, 6), 'RECEPTIONIST', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 5));
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values (pg_temp.id(13, 1), pg_temp.id(3, 1), '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null,
          'guardian-paged-test', pg_temp.id(13, 2));

insert into public.pets (id, name, species, created_at) values
    (pg_temp.id(7, 1), 'Luna', 'Dog', '2020-01-01Z'),
    (pg_temp.id(7, 2), 'Toby with a very long name that does not fit', 'Cat', '2020-01-01Z'),
    (pg_temp.id(7, 3), 'Kira', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start, effective_end) values
    (pg_temp.id(8, 1), pg_temp.id(2, 1), pg_temp.id(7, 1), '2020-01-01Z', null),
    (pg_temp.id(8, 2), pg_temp.id(2, 1), pg_temp.id(7, 2), '2020-01-01Z', null),
    (pg_temp.id(8, 3), pg_temp.id(2, 2), pg_temp.id(7, 1), '2021-01-01Z', null),
    (pg_temp.id(8, 4), pg_temp.id(2, 3), pg_temp.id(7, 1), '2020-01-01Z', '2024-01-01Z'),
    (pg_temp.id(8, 5), pg_temp.id(2, 4), pg_temp.id(7, 3), '2020-01-01Z', null);

-- One Appointment: a requested revision and, once it had been confirmed, a
-- confirmed revision with the same interval, in the Clinic's timezone.
create function pg_temp.seed(n integer, pet integer, clinic integer, requester integer, state text,
    start_at timestamptz, was_confirmed boolean default null) returns void language plpgsql as $$
declare zone text := case clinic when 2 then 'America/New_York' else 'Europe/Madrid' end;
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(n), pg_temp.id(7, pet), pg_temp.id(4, clinic), pg_temp.id(2, requester),
            'Private reason ' || n, state, '2023-01-01Z'::timestamptz + make_interval(mins => n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, created_at
    ) values (pg_temp.appt(n), 1, 'REQUESTED', start_at, start_at + interval '30 minutes', zone,
              pg_temp.id(2, requester), '2023-01-01Z'::timestamptz + make_interval(mins => n));
    if coalesce(was_confirmed, state in ('CONFIRMED', 'COMPLETED', 'NO_SHOW')) then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, created_at
        ) values (pg_temp.appt(n), 2, 'CONFIRMED', start_at, start_at + interval '30 minutes', zone,
                  pg_temp.id(2, 6), '2023-02-01Z'::timestamptz + make_interval(mins => n));
    end if;
end $$;

-- Active, not yet started (rank 1).
select pg_temp.seed(1, 1, 1, 1, 'REQUESTED', '2035-03-01T09:00Z');       -- Clinic alternative time
select pg_temp.seed(2, 2, 2, 1, 'CONFIRMED', '2035-03-02T14:00Z');       -- Clinic reschedule, New York
select pg_temp.seed(3, 1, 1, 2, 'CONFIRMED', '2035-03-03T10:00Z');       -- 3–5 tie; requested by Carlos
select pg_temp.seed(4, 1, 1, 2, 'CONFIRMED', '2035-03-03T10:00Z');
select pg_temp.seed(5, 1, 1, 1, 'CONFIRMED', '2035-03-03T10:00Z');
select pg_temp.seed(6, 2, 1, 1, 'CONFIRMED', '2035-03-04T10:00Z');       -- lapsed Clinic proposal
select pg_temp.seed(7, 1, 1, 2, 'CONFIRMED', '2035-03-05T10:00Z');       -- Guardian (Carlos) proposal
select pg_temp.seed(n, case when n % 2 = 0 then 1 else 2 end, case when n % 3 = 0 then 2 else 1 end, 1,
                    case when n % 2 = 0 then 'REQUESTED' else 'CONFIRMED' end,
                    '2035-03-06T10:00Z'::timestamptz + make_interval(days => n - 8))
from generate_series(8, 15) n;
-- 16: rescheduled from February to May — the latest revision decides.
select pg_temp.seed(16, 1, 1, 1, 'CONFIRMED', '2035-02-01T10:00Z');
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, created_at
) values (pg_temp.appt(16), 3, 'CONFIRMED', '2035-05-01T10:00Z', '2035-05-01T10:30Z', 'Europe/Madrid',
          pg_temp.id(2, 1), '2026-09-01Z');
-- Active, start reached (rank 2): still CONFIRMED or not yet EXPIRED.
select pg_temp.seed(17, 1, 1, 1, 'CONFIRMED', '2025-06-01T10:00Z');
select pg_temp.seed(18, 2, 2, 1, 'CONFIRMED', '2025-05-01T15:00Z');      -- 18–19 tie
select pg_temp.seed(19, 2, 2, 1, 'CONFIRMED', '2025-05-01T15:00Z');
select pg_temp.seed(20, 1, 1, 2, 'REQUESTED', '2025-04-01T10:00Z');
select pg_temp.seed(21, 2, 1, 1, 'CONFIRMED', '2020-01-01T10:00Z');
-- Terminal: every outcome, a tie (40–41), a New York one (33), one cancelled
-- before its future start (50), and one rescheduled before it ended (31).
select pg_temp.seed(n, case when n % 2 = 0 then 1 else 2 end, case when n = 33 then 2 else 1 end,
                    case when n % 5 = 0 then 2 else 1 end,
                    case when n = 31 then 'COMPLETED' else (array['COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'])[n % 4 + 1] end,
                    case when n = 41 then '2024-01-01T10:00Z'::timestamptz + make_interval(days => 40)
                         when n = 50 then '2035-06-01T10:00Z'::timestamptz
                         else '2024-01-01T10:00Z'::timestamptz + make_interval(days => n) end)
from generate_series(31, 51) n;
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, created_at
) values (pg_temp.appt(31), 3, 'CONFIRMED', '2024-12-31T10:00Z', '2024-12-31T10:30Z', 'Europe/Madrid',
          pg_temp.id(2, 1), '2024-06-01Z');
-- Kira's (another Guardianship).
select pg_temp.seed(61, 3, 1, 4, 'REQUESTED', '2035-03-01T09:00Z');
select pg_temp.seed(62, 3, 1, 4, 'COMPLETED', '2024-02-01T10:00Z');
select pg_temp.seed(63, 3, 2, 4, 'CONFIRMED', '2025-01-01T10:00Z');

insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
)
select pg_temp.id(11, proposal.n), pg_temp.appt(proposal.n), base.id, base.revision_context,
       proposal.start_at, proposal.start_at + interval '30 minutes', proposal.zone, proposal.context,
       pg_temp.id(2, proposal.proposer), proposal.reason, '2026-09-01Z'
from (values
    (1, '2035-03-01T12:00Z'::timestamptz, 'Europe/Madrid', 'CLINIC', 6, 'No veterinarian free'),
    (2, '2035-03-09T14:00Z'::timestamptz, 'America/New_York', 'CLINIC', 6, 'Room unavailable'),
    (6, '2026-01-01T10:00Z'::timestamptz, 'Europe/Madrid', 'CLINIC', 6, 'Long ago'),
    (7, '2035-03-12T10:00Z'::timestamptz, 'Europe/Madrid', 'GUARDIAN', 2, null)
) as proposal(n, start_at, zone, context, proposer, reason)
cross join lateral (
    select revision.id, revision.revision_context
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = pg_temp.appt(proposal.n)
    order by revision.revision_sequence desc limit 1
) as base;
set local session_replication_role = origin;

-- ===========================================================================
-- VN 45, 46: contract, ACLs, get_pet_appointments unchanged.
-- ===========================================================================
do $$ begin
    perform pg_temp.assert_true((
        select array_agg(parameter_name::text order by ordinal_position)
        from information_schema.parameters
        where specific_name = (select specific_name from information_schema.routines
                               where routine_schema = 'public' and routine_name = 'get_guardian_active_appointments')
          and parameter_mode = 'OUT')
        = array['id','pet_id','pet_name','clinic_id','lifecycle_state','current_scheduled_start_at',
                'current_scheduled_end_at','current_scheduling_timezone_name',
                'pending_reschedule_proposing_context','awaiting_clinic_confirmation','active_rank'],
        'Active columns are exactly BR-37 plus active_rank');
    perform pg_temp.assert_true((
        select array_agg(parameter_name::text order by ordinal_position)
        from information_schema.parameters
        where specific_name = (select specific_name from information_schema.routines
                               where routine_schema = 'public' and routine_name = 'get_guardian_appointment_history')
          and parameter_mode = 'OUT')
        = array['id','pet_id','pet_name','clinic_id','lifecycle_state','current_scheduled_start_at',
                'current_scheduled_end_at','current_scheduling_timezone_name',
                'pending_reschedule_proposing_context','awaiting_clinic_confirmation'], 'History columns are exactly BR-37');
    perform pg_temp.assert_true((
        select bool_and(proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""'])
        from pg_proc as proc
        where proc.oid in ('public.get_guardian_active_appointments(integer,timestamptz,uuid,integer)'::regprocedure,
                           'public.get_guardian_appointment_history(timestamptz,uuid,integer)'::regprocedure,
                           'public.project_guardian_appointments(uuid[])'::regprocedure)),
        'Reads and helper are STABLE SECURITY DEFINER with an empty search_path');
    perform pg_temp.assert_true(
        has_function_privilege('authenticated', 'public.get_guardian_active_appointments(integer,timestamptz,uuid,integer)', 'execute')
        and has_function_privilege('authenticated', 'public.get_guardian_appointment_history(timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('anon', 'public.get_guardian_active_appointments(integer,timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('anon', 'public.get_guardian_appointment_history(timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('service_role', 'public.get_guardian_active_appointments(integer,timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('service_role', 'public.get_guardian_appointment_history(timestamptz,uuid,integer)', 'execute')
        and not has_function_privilege('authenticated', 'public.project_guardian_appointments(uuid[])', 'execute')
        and not has_function_privilege('anon', 'public.project_guardian_appointments(uuid[])', 'execute')
        and not has_function_privilege('service_role', 'public.project_guardian_appointments(uuid[])', 'execute'),
        'Grants: authenticated only; the projection is executable by no client');
    perform pg_temp.assert_true(
        pg_get_function_arguments('public.get_pet_appointments(uuid)'::regprocedure) = 'p_pet_id uuid'
        and pg_get_function_result('public.get_pet_appointments(uuid)'::regprocedure)
            like 'TABLE(id uuid, clinic_id uuid, requesting_user_id uuid, reason_for_visit text, %, pending_reschedule_currently_acceptable boolean, medical_access_state text)'
        and has_function_privilege('authenticated', 'public.get_pet_appointments(uuid)', 'execute')
        and not has_function_privilege('anon', 'public.get_pet_appointments(uuid)', 'execute'),
        'get_pet_appointments unchanged');
end $$;

-- ===========================================================================
-- VN 38: authentication first, then validation; no denial outcome.
-- ===========================================================================
do $$ declare invalid text := '22023: Guardian appointment page is invalid'; begin
    perform pg_temp.act(0);
    perform pg_temp.assert_true(pg_temp.active_outcome() = '28000: Authentication is required'
        and pg_temp.history_outcome() = '28000: Authentication is required'
        and pg_temp.active_outcome(null, null, null, 0) = '28000: Authentication is required',
        'Anonymous fails with 28000 before validation');
    perform pg_temp.act(40);
    perform pg_temp.assert_true(pg_temp.active_outcome() = '28000: No coherent domain User exists for the authenticated subject'
        and pg_temp.history_outcome() = '28000: No coherent domain User exists for the authenticated subject',
        'Unlinked subject fails with 28000');
    perform pg_temp.act(1);
    perform pg_temp.assert_true(pg_temp.active_outcome(null, null, null, 0) = invalid
        and pg_temp.active_outcome(null, null, null, 51) = invalid
        and pg_temp.active_outcome(null, null, null, null) = invalid
        and pg_temp.active_outcome(1, '2035-01-01Z', null) = invalid
        and pg_temp.active_outcome(null, '2035-01-01Z', pg_temp.appt(1)) = invalid
        and pg_temp.active_outcome(1, null, pg_temp.appt(1)) = invalid
        and pg_temp.active_outcome(3, '2035-01-01Z', pg_temp.appt(1)) = invalid
        and pg_temp.active_outcome(0, '2035-01-01Z', pg_temp.appt(1)) = invalid, 'Active validation');
    perform pg_temp.assert_true(pg_temp.history_outcome(null, null, 0) = invalid
        and pg_temp.history_outcome(null, null, 51) = invalid
        and pg_temp.history_outcome(null, null, null) = invalid
        and pg_temp.history_outcome('2024-01-01Z', null) = invalid
        and pg_temp.history_outcome(null, pg_temp.appt(31)) = invalid, 'History validation');
    perform pg_temp.assert_true(pg_temp.active_outcome(null, null, null, 1) = 'SUCCEEDED'
        and pg_temp.active_outcome(2, '2035-01-01Z', pg_temp.appt(1), 50) = 'SUCCEEDED'
        and pg_temp.history_outcome(null, null, 50) = 'SUCCEEDED', 'Range bounds accepted');
    perform pg_temp.act(7);
    perform pg_temp.assert_true(pg_temp.active_outcome() = 'SUCCEEDED' and pg_temp.history_outcome() = 'SUCCEEDED',
        'No Guardianship is not a denial');
end $$;

-- ===========================================================================
-- VN 39–42: each read equals the union of get_pet_appointments over the
-- User's currently guarded Pets, page by page, for every page size.
-- ===========================================================================
do $$
declare expected_active jsonb; expected_history jsonb; page_size integer; user_n integer;
begin
    expected_active := pg_temp.expected(1, 'active');
    expected_history := pg_temp.expected(1, 'history');
    perform pg_temp.assert_true(jsonb_array_length(expected_active) = 21, 'Fixture: Maria has 21 active');
    perform pg_temp.assert_true(jsonb_array_length(expected_history) = 21, 'Fixture: Maria has 21 terminal');
    perform pg_temp.act(1);
    for page_size in 1 .. 22 loop
        perform pg_temp.assert_true(pg_temp.active_paged(page_size) = expected_active,
            'Active equals the guarded union at page size ' || page_size);
        perform pg_temp.assert_true(pg_temp.history_paged(page_size) = expected_history,
            'History equals the guarded union at page size ' || page_size);
    end loop;
    foreach user_n in array array[2, 3, 4, 7] loop
        expected_active := pg_temp.expected(user_n, 'active');
        expected_history := pg_temp.expected(user_n, 'history');
        perform pg_temp.act(user_n);
        foreach page_size in array array[1, 2, 20] loop
            perform pg_temp.assert_true(pg_temp.active_paged(page_size) = expected_active
                and pg_temp.history_paged(page_size) = expected_history,
                'User ' || user_n || ' equals the guarded union at page size ' || page_size);
        end loop;
    end loop;
end $$;

-- VN 39 explicitly: shared, former, unrelated and unguarded Users.
do $$
declare maria_active jsonb; maria_history jsonb; carlos_active jsonb; carlos_history jsonb;
begin
    perform pg_temp.act(1);
    maria_active := pg_temp.active_paged(50);
    maria_history := pg_temp.history_paged(50);
    perform pg_temp.act(2);
    carlos_active := pg_temp.active_paged(50);
    carlos_history := pg_temp.history_paged(50);
    perform pg_temp.assert_true(
        carlos_active = (select jsonb_agg(r order by o) from jsonb_array_elements(maria_active) with ordinality e(r, o)
                         where (r->>'pet_id')::uuid = pg_temp.id(7, 1))
        and carlos_history = (select jsonb_agg(r order by o) from jsonb_array_elements(maria_history) with ordinality e(r, o)
                              where (r->>'pet_id')::uuid = pg_temp.id(7, 1)),
        'A co-Guardian sees exactly the primary Guardian''s rows of the shared Pet');
    perform pg_temp.assert_true(pg_temp.appt(3) = any(pg_temp.ids_of(maria_active))
        and pg_temp.appt(20) = any(pg_temp.ids_of(maria_active)),
        'Appointments requested by the other Guardian are visible');
    perform pg_temp.assert_true(not exists (
        select 1 from jsonb_array_elements(carlos_active || carlos_history) r
        where (r->>'pet_id')::uuid <> pg_temp.id(7, 1)), 'Guarding one of two Pets shows only that Pet');
    perform pg_temp.assert_true(not exists (
        select 1 from jsonb_array_elements(maria_active || maria_history) r
        where (r->>'pet_id')::uuid = pg_temp.id(7, 3)), 'Another Guardianship''s Pet never appears');
    perform pg_temp.act(3);
    perform pg_temp.assert_true(pg_temp.active_paged(50) = '[]' and pg_temp.history_paged(50) = '[]',
        'A former Guardian sees nothing, including history');
    perform pg_temp.act(7);
    perform pg_temp.assert_true(pg_temp.active_paged(50) = '[]' and pg_temp.history_paged(50) = '[]',
        'No Guardianship: empty pages');
    perform pg_temp.act(4);
    perform pg_temp.assert_true(pg_temp.ids_of(pg_temp.active_paged(50)) = array[pg_temp.appt(61), pg_temp.appt(63)]
        and pg_temp.ids_of(pg_temp.history_paged(50)) = array[pg_temp.appt(62)], 'Kira''s Guardian sees only Kira''s');
end $$;

-- VN 40, 42, 43: tab membership, values, and the Active order.
do $$
declare active jsonb; history jsonb; row_of jsonb;
begin
    perform pg_temp.act(1);
    active := pg_temp.active_paged(50);
    history := pg_temp.history_paged(50);
    perform pg_temp.assert_true((select bool_and(r->>'lifecycle_state' in ('REQUESTED', 'CONFIRMED'))
        from jsonb_array_elements(active) r), 'Active holds only REQUESTED and CONFIRMED');
    perform pg_temp.assert_true((select bool_and(r->>'lifecycle_state' in ('COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'))
        from jsonb_array_elements(history) r)
        and (select count(distinct r->>'lifecycle_state') from jsonb_array_elements(history) r) = 4,
        'History holds every terminal outcome and nothing else');
    perform pg_temp.assert_true(not (pg_temp.ids_of(active) && pg_temp.ids_of(history)), 'No Appointment in both tabs');
    perform pg_temp.assert_true(pg_temp.ids_of(active) = array[
        pg_temp.appt(1), pg_temp.appt(2), pg_temp.appt(3), pg_temp.appt(4), pg_temp.appt(5), pg_temp.appt(6),
        pg_temp.appt(7), pg_temp.appt(8), pg_temp.appt(9), pg_temp.appt(10), pg_temp.appt(11), pg_temp.appt(12),
        pg_temp.appt(13), pg_temp.appt(14), pg_temp.appt(15), pg_temp.appt(16),
        pg_temp.appt(17), pg_temp.appt(19), pg_temp.appt(18), pg_temp.appt(20), pg_temp.appt(21)],
        'Active: not yet started ascending (ties by id), then started descending (ties by id descending)');
    perform pg_temp.assert_true((select array_agg((r->>'active_rank')::integer order by o)
        from jsonb_array_elements(active) with ordinality e(r, o)) = array_fill(1, array[16]) || array_fill(2, array[5]),
        'active_rank reports the group');
    perform pg_temp.assert_true((pg_temp.ids_of(history))[1:3] = array[pg_temp.appt(50), pg_temp.appt(31), pg_temp.appt(51)]
        and pg_temp.ids_of(history) @> array[pg_temp.appt(40), pg_temp.appt(41)]
        and array_position(pg_temp.ids_of(history), pg_temp.appt(41)) + 1 = array_position(pg_temp.ids_of(history), pg_temp.appt(40)),
        'History: newest start first, the tie by id descending');

    select r into row_of from jsonb_array_elements(active) r where (r->>'id')::uuid = pg_temp.appt(16);
    perform pg_temp.assert_true((row_of->>'current_scheduled_start_at')::timestamptz = '2035-05-01T10:00Z',
        'A rescheduled Appointment uses its latest revision');
    select r into row_of from jsonb_array_elements(history) r where (r->>'id')::uuid = pg_temp.appt(31);
    perform pg_temp.assert_true((row_of->>'current_scheduled_start_at')::timestamptz = '2024-12-31T10:00Z',
        'A rescheduled terminal Appointment uses its latest revision');
    select r into row_of from jsonb_array_elements(active) r where (r->>'id')::uuid = pg_temp.appt(2);
    perform pg_temp.assert_true(row_of->>'current_scheduling_timezone_name' = 'America/New_York'
        and (row_of->>'current_scheduled_start_at')::timestamptz = '2035-03-02T14:00Z'
        and row_of->>'pet_name' = 'Toby with a very long name that does not fit'
        and (row_of->>'clinic_id')::uuid = pg_temp.id(4, 2),
        'Interval, establishment timezone, Pet and Clinic as stored, never converted');
    perform pg_temp.assert_true((select jsonb_object_agg(r->>'id', coalesce(r->>'pending_reschedule_proposing_context', 'null'))
        from jsonb_array_elements(active) r
        where (r->>'id')::uuid in (pg_temp.appt(1), pg_temp.appt(2), pg_temp.appt(6), pg_temp.appt(7), pg_temp.appt(8)))
        = jsonb_build_object(pg_temp.appt(1), 'CLINIC', pg_temp.appt(2), 'CLINIC', pg_temp.appt(6), 'null',
                             pg_temp.appt(7), 'GUARDIAN', pg_temp.appt(8), 'null'),
        'Proposing context: Clinic proposals on both bases, the Guardian proposal, none when lapsed or absent');
    perform pg_temp.assert_true((select bool_and(r->'pending_reschedule_proposing_context' = 'null'::jsonb)
        from jsonb_array_elements(history) r), 'History never carries a proposal');
    perform pg_temp.assert_true((select bool_and(r::text not like '%Private reason%' and r::text not like '%No veterinarian free%'
            and r::text not like '%' || pg_temp.id(2, 2)::text || '%' and r::text not like '%' || pg_temp.id(11, 1)::text || '%')
        from jsonb_array_elements(active || history) r),
        'No reason for visit, proposal reason or identity, or requester');
end $$;

-- VN 41: full pages, exact boundaries, ties, and the end of each list.
do $$
declare first_page uuid[]; boundary_page uuid[]; last_active record; last_history record; n integer;
begin
    perform pg_temp.act(1);
    select array_agg(id order by ordinality) into first_page
    from public.get_guardian_active_appointments(null, null, null, 20) with ordinality;
    perform pg_temp.assert_true(cardinality(first_page) = 20, 'Active: a full first page of 20');
    perform pg_temp.assert_true((select array_agg(id) from public.get_guardian_active_appointments(
        2, '2025-04-01T10:00Z', pg_temp.appt(20), 20)) = array[pg_temp.appt(21)], 'Active: the 21st row alone on page 2');
    select array_agg(id order by ordinality) into first_page
    from public.get_guardian_appointment_history(null, null, 20) with ordinality;
    perform pg_temp.assert_true(cardinality(first_page) = 20, 'History: a full first page of 20');
    select * into last_history from public.get_guardian_appointment_history(null, null, 50)
    order by current_scheduled_start_at, id limit 1;
    perform pg_temp.assert_true((select count(*) from public.get_guardian_appointment_history(
        last_history.current_scheduled_start_at, last_history.id, 20)) = 0, 'History: past the end is empty');
    select count(*) into n from public.get_guardian_active_appointments(null, null, null, 21);
    perform pg_temp.assert_true(n = 21 and (select count(*) from public.get_guardian_active_appointments(
        2, '2020-01-01T10:00Z', pg_temp.appt(21), 21)) = 0, 'Active: an exactly full page, then an empty one');
    perform pg_temp.assert_true((select count(*) from public.get_guardian_appointment_history(null, null, 21)) = 21
        and (select count(*) from public.get_guardian_appointment_history(last_history.current_scheduled_start_at,
            last_history.id, 21)) = 0, 'History: an exactly full page, then an empty one');
    select array_agg(id order by ordinality) into boundary_page
    from public.get_guardian_active_appointments(1, '2035-03-03T10:00Z', pg_temp.appt(3), 2) with ordinality;
    perform pg_temp.assert_true(boundary_page = array[pg_temp.appt(4), pg_temp.appt(5)], 'A cursor inside a tie continues by id');
    select array_agg(id order by ordinality) into boundary_page
    from public.get_guardian_active_appointments(1, '2035-05-01T10:00Z', pg_temp.appt(16), 2) with ordinality;
    perform pg_temp.assert_true(boundary_page = array[pg_temp.appt(17), pg_temp.appt(19)],
        'After the last not-yet-started row the started ones follow');
    select array_agg(id order by ordinality) into boundary_page
    from public.get_guardian_active_appointments(2, '2025-05-01T15:00Z', pg_temp.appt(19), 5) with ordinality;
    perform pg_temp.assert_true(boundary_page = array[pg_temp.appt(18), pg_temp.appt(20), pg_temp.appt(21)],
        'A cursor inside a started tie continues by id descending');
    -- A rank-1 cursor later than every row still returns every started row.
    perform pg_temp.assert_true((select count(*) from public.get_guardian_active_appointments(
        1, '2099-01-01Z', pg_temp.appt(1), 50)) = 5, 'A rank-1 cursor past every future row continues into rank 2');
end $$;

-- VN 46: the reads write nothing.
do $$ declare before text; begin
    perform pg_temp.act(1);
    before := pg_temp.fingerprint();
    perform pg_temp.active_paged(3);
    perform pg_temp.history_paged(3);
    perform pg_temp.assert_true(pg_temp.fingerprint() = before, 'Reads write nothing');
end $$;

-- The real mobile SQL role.
select pg_temp.act(1);
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.get_guardian_active_appointments(null, null, null, 20)) = 20
    and (select count(*) from public.get_guardian_appointment_history(null, null, 20)) = 20,
    'Authenticated role reads both tabs');
reset role;

-- VN 44 and VN 39 (ending a Guardianship): changes between pages.
do $$
declare first_ids uuid[]; later_ids uuid[]; cursor_row record; history_ids uuid[];
begin
    perform pg_temp.act(1);
    select array_agg(id order by ordinality) into first_ids
    from public.get_guardian_active_appointments(null, null, null, 5) with ordinality;
    select * into cursor_row from public.get_guardian_active_appointments(null, null, null, 5)
    order by current_scheduled_start_at desc, id desc limit 1;
    perform pg_temp.assert_true(cursor_row.id = pg_temp.appt(5), 'Fixture: page 1 ends at Appointment 5');

    set local session_replication_role = replica;
    -- One shown and one not yet shown are cancelled; one is completed.
    update public.appointments set lifecycle_state = 'CANCELLED' where id in (pg_temp.appt(4), pg_temp.appt(9));
    update public.appointments set lifecycle_state = 'COMPLETED' where id = pg_temp.appt(17);
    set local session_replication_role = origin;

    select array_agg(id order by ordinality) into later_ids from public.get_guardian_active_appointments(
        cursor_row.active_rank, cursor_row.current_scheduled_start_at, cursor_row.id, 50) with ordinality;
    perform pg_temp.assert_true(not (later_ids && first_ids)
        and not (later_ids && array[pg_temp.appt(9), pg_temp.appt(17)])
        and cardinality(later_ids) = 21 - 5 - 2, 'Active: no repeat, cancelled and completed ones gone, the rest once');
    history_ids := pg_temp.ids_of(pg_temp.history_paged(50));
    perform pg_temp.assert_true(history_ids @> array[pg_temp.appt(4), pg_temp.appt(9), pg_temp.appt(17)]
        and cardinality(history_ids) = 24, 'History: they appear where their key sorts');
    perform pg_temp.assert_true(history_ids[1:5]
        = array[pg_temp.appt(50), pg_temp.appt(9), pg_temp.appt(4), pg_temp.appt(17), pg_temp.appt(31)],
        'Newly terminal Appointments sort by their start');

    set local session_replication_role = replica;
    update public.guardianships set effective_end = statement_timestamp() where id = pg_temp.id(8, 3);
    set local session_replication_role = origin;
    perform pg_temp.act(2);
    perform pg_temp.assert_true(pg_temp.active_paged(20) = '[]' and pg_temp.history_paged(20) = '[]',
        'Ending a Guardianship removes its Pet from the next read');
    perform pg_temp.act(1);
    perform pg_temp.assert_true(jsonb_array_length(pg_temp.active_paged(20)) = 18,
        'The other Guardian is unaffected');
end $$;

-- ===========================================================================
-- Volume (VN 46): one Guardian with 3 Pets, 3 000 terminal and 300 active
-- Appointments, among 20 000 Appointments of Pets nobody here guards.
-- ===========================================================================
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at) values (pg_temp.id(1, 8), 'guardian-paged-8@example.test', '2020-01-01Z');
insert into public.users (id) values (pg_temp.id(2, 8));
insert into public.user_authentication_identities (user_id, provider_subject) values (pg_temp.id(2, 8), pg_temp.id(1, 8));
insert into public.pets (id, name, species, created_at)
select pg_temp.id(30, n), 'Volume pet ' || n, 'Dog', '2020-01-01Z' from generate_series(1, 4) n;
insert into public.guardianships (id, user_id, pet_id, effective_start)
select pg_temp.id(8, 100 + n), pg_temp.id(2, 8), pg_temp.id(30, n), '2020-01-01Z' from generate_series(1, 3) n;
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select pg_temp.id(31, n),
       pg_temp.id(30, case when n <= 3300 then n % 3 + 1 else 4 end),
       pg_temp.id(4, n % 2 + 1), pg_temp.id(2, 8), 'Volume ' || n,
       case when n <= 3000 then (array['COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'])[n % 4 + 1]
            when n <= 3300 then case when n % 2 = 0 then 'REQUESTED' else 'CONFIRMED' end
            else (array['COMPLETED', 'CONFIRMED', 'REQUESTED', 'CANCELLED'])[n % 4 + 1] end,
       '2023-01-01Z'
from generate_series(1, 23300) n;
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, created_at
)
select pg_temp.id(31, n), 1, 'REQUESTED', start_at, start_at + interval '30 minutes', 'Europe/Madrid', pg_temp.id(2, 8), '2023-01-01Z'
from (select n, case when n between 3001 and 3200 then '2035-01-01Z'::timestamptz + make_interval(hours => n)
                     else '2020-01-01Z'::timestamptz + make_interval(hours => n) end as start_at
      from generate_series(1, 23300) n) as seeded;
set local session_replication_role = origin;
analyze public.appointments, public.appointment_schedule_revisions, public.guardianships, public.pets;

do $$
declare started timestamptz; active_first_ms numeric; active_deep_ms numeric; history_first_ms numeric;
    history_deep_ms numeric; rows_seen integer; deep_start timestamptz;
begin
    perform pg_temp.act(8);
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_guardian_active_appointments(null, null, null, 20);
    active_first_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 20, 'Volume: a first Active page of 20');
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_guardian_active_appointments(
        2, '2020-01-01Z'::timestamptz + make_interval(hours => 3290), pg_temp.id(31, 3290), 20);
    active_deep_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 20, 'Volume: a deep Active page of 20');
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_guardian_appointment_history(null, null, 20);
    history_first_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 20, 'Volume: a first History page of 20');
    deep_start := '2020-01-01Z'::timestamptz + make_interval(hours => 100);
    started := clock_timestamp();
    select count(*) into rows_seen from public.get_guardian_appointment_history(deep_start, pg_temp.id(31, 100), 20);
    history_deep_ms := extract(epoch from clock_timestamp() - started) * 1000;
    perform pg_temp.assert_true(rows_seen = 20, 'Volume: a deep History page of 20');
    raise notice 'Volume (3 300 own / 23 300 overall): active first % ms, deep % ms; history first % ms, deep % ms',
        round(active_first_ms, 1), round(active_deep_ms, 1), round(history_first_ms, 1), round(history_deep_ms, 1);
    perform pg_temp.assert_true(active_first_ms < 500 and active_deep_ms < 500
        and history_first_ms < 500 and history_deep_ms < 500, 'Volume: each page well under 500 ms');
end $$;

rollback;

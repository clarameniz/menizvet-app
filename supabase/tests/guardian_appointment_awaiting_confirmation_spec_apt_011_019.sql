-- SPEC-APT-011 BR-37/BR-40 awaiting_clinic_confirmation (migration
-- 20261118090000) and SPEC-APT-019 §5 "Appointment list": when the paged
-- Guardian reads report that a REQUESTED Appointment carries the Clinic's
-- alternative time accepted by a Guardian and still awaits the Clinic's
-- confirmation (SPEC-APT-011 BR-33), driven through the real trusted
-- operations as the `authenticated` role. Verification Notes 47–50.
--
-- Isolated LOCAL superuser only. Fixtures and assertions are rollback-only;
-- triggers are bypassed only to load fixtures and to materialize EXPIRED.
begin;
set local timezone = 'UTC';

create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$ begin
    if value is distinct from true then raise exception '%', message; end if;
end $$;
create function pg_temp.id(kind integer, n integer) returns uuid language sql immutable as $$
    select ('d0140000-0000-4000-8000-' || lpad((kind * 1000 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.appt(n integer) returns uuid language sql immutable as $$
    select pg_temp.id(9, n)
$$;
create function pg_temp.act(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(1, n)::text, true)
$$;
create function pg_temp.flush() returns void language plpgsql as $$
begin
    set constraints all immediate;
    set constraints all deferred;
end $$;
create temporary table ids (name text primary key, id uuid not null) on commit drop;
grant select, insert, update on ids to authenticated;
create function pg_temp.keep(p_name text, p_id uuid) returns uuid language sql as $$
    insert into ids values (p_name, p_id) on conflict (name) do update set id = excluded.id returning id
$$;
create function pg_temp.named(p_name text) returns uuid language sql as $$
    select id from ids where name = p_name
$$;

-- Trusted operations, followed by every pending deferred trigger.
create function pg_temp.alt_propose(p_user integer, p_n integer, p_date date, p_time time, p_sequence integer)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_requested_appointment_alternative_time(
        pg_temp.appt(p_n), p_date, p_time, 3600, 'No veterinarian free', p_sequence);
    perform pg_temp.flush();
    return created;
end $$;
create function pg_temp.alt_accept(p_user integer, p_proposal uuid) returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.accept_requested_appointment_alternative_time(p_proposal);
    perform pg_temp.flush();
end $$;
create function pg_temp.withdraw(p_user integer, p_proposal uuid) returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.withdraw_appointment_reschedule_proposal(p_proposal);
    perform pg_temp.flush();
end $$;
create function pg_temp.confirm(p_user integer, p_n integer, p_sequence integer) returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.confirm_appointment(pg_temp.appt(p_n), p_sequence);
    perform pg_temp.flush();
end $$;
create function pg_temp.guardian_reschedule(p_user integer, p_n integer, p_date date, p_time time)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.reschedule_requested_appointment(pg_temp.appt(p_n), p_date, p_time, 3600);
    perform pg_temp.flush();
end $$;
create function pg_temp.cancel(p_user integer, p_n integer, p_context text, p_sequence integer)
returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.cancel_appointment(pg_temp.appt(p_n), p_context,
        case when p_context = 'CLINIC' then 'Clinic closed that day' end, p_sequence);
    perform pg_temp.flush();
end $$;
create function pg_temp.confirmed_propose(p_user integer, p_n integer, p_date date, p_time time, p_sequence integer)
returns uuid language plpgsql as $$
declare created uuid;
begin
    perform pg_temp.act(p_user);
    created := public.propose_confirmed_appointment_reschedule(
        pg_temp.appt(p_n), 'CLINIC', p_date, p_time, 3600, 'Room unavailable', p_sequence);
    perform pg_temp.flush();
    return created;
end $$;
create function pg_temp.confirmed_accept(p_user integer, p_proposal uuid) returns void language plpgsql as $$
begin
    perform pg_temp.act(p_user);
    perform public.accept_appointment_reschedule_proposal(p_proposal, 'GUARDIAN');
    perform pg_temp.flush();
end $$;

-- What the paged reads say about Appointment n, for User u:
-- 'TAB|STATE|proposing context|awaiting', or 'absent'.
create function pg_temp.listed(u integer, n integer) returns text language plpgsql as $$
declare result text;
begin
    perform pg_temp.act(u);
    select 'ACTIVE|' || r.lifecycle_state || '|' || coalesce(r.pending_reschedule_proposing_context, '-') || '|'
           || r.awaiting_clinic_confirmation
    into result
    from public.get_guardian_active_appointments(null, null, null, 50) as r where r.id = pg_temp.appt(n);
    if result is null then
        select 'HISTORY|' || r.lifecycle_state || '|' || coalesce(r.pending_reschedule_proposing_context, '-') || '|'
               || r.awaiting_clinic_confirmation
        into result
        from public.get_guardian_appointment_history(null, null, 50) as r where r.id = pg_temp.appt(n);
    end if;
    return coalesce(result, 'absent');
end $$;
-- The oracle: BR-33 evaluated on get_pet_appointments for the same User.
create function pg_temp.oracle(u integer, n integer) returns text language plpgsql as $$
declare result text;
begin
    perform pg_temp.act(u);
    select case when r.lifecycle_state in ('REQUESTED', 'CONFIRMED') then 'ACTIVE|' else 'HISTORY|' end
           || r.lifecycle_state || '|' || coalesce(r.pending_reschedule_proposing_context, '-') || '|'
           || (r.lifecycle_state = 'REQUESTED' and r.current_schedule_source_proposing_context is not distinct from 'CLINIC')
    into result
    from public.get_pet_appointments(pg_temp.id(7, 1)) as r where r.id = pg_temp.appt(n);
    return coalesce(result, 'absent');
end $$;
-- Both Guardians see `expected`, which is also the oracle's answer.
create function pg_temp.check_listed(n integer, expected text, message text) returns void language plpgsql as $$
begin
    perform pg_temp.assert_true(pg_temp.listed(1, n) = expected and pg_temp.listed(2, n) = expected
        and pg_temp.oracle(1, n) = expected, message);
end $$;

-- ===========================================================================
-- Fixtures. Users: 1 Maria and 2 Carlos, current Guardians of Luna; 4 Owner;
-- 8 Receptionist @ A1. A1 is published, Europe/Madrid, 30-minute standard
-- duration, Appointment Availability 08:00–20:00 every day; Organization
-- ACTIVE. Every Appointment is Luna's, requested by Maria; March 2035 is CET.
-- ===========================================================================
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id(1, n), 'awaiting-' || n || '@example.test', '2020-01-01Z' from unnest(array[1, 2, 4, 8]) n;
insert into public.users (id) select pg_temp.id(2, n) from unnest(array[1, 2, 4, 8]) n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.id(2, n), pg_temp.id(1, n) from unnest(array[1, 2, 4, 8]) n;
insert into public.veterinary_organizations (id, display_name) values (pg_temp.id(3, 1), 'Awaiting Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values (pg_temp.id(4, 1), pg_temp.id(3, 1), true, 'Europe/Madrid', 30);
insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.id(4, 1), weekday, '08:00', '20:00' from generate_series(1, 7) weekday;
insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    (pg_temp.id(5, 4), pg_temp.id(3, 1), pg_temp.id(2, 4), '2020-01-01Z'),
    (pg_temp.id(5, 8), pg_temp.id(3, 1), pg_temp.id(2, 8), '2020-01-01Z');
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id, effective_start, granted_by_user_id
) values
    (pg_temp.id(6, 4), pg_temp.id(5, 4), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', pg_temp.id(2, 4)),
    (pg_temp.id(6, 8), pg_temp.id(5, 8), 'RECEPTIONIST', 'CLINIC', pg_temp.id(4, 1), '2020-01-01Z', pg_temp.id(2, 4));
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until, establishment_source, establishment_idempotency_key
) values (pg_temp.id(13, 1), pg_temp.id(3, 1), '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null,
          'awaiting-test', pg_temp.id(13, 2));
insert into public.pets (id, name, species, created_at) values (pg_temp.id(7, 1), 'Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values
    (pg_temp.id(8, 1), pg_temp.id(2, 1), pg_temp.id(7, 1), '2020-01-01Z'),
    (pg_temp.id(8, 2), pg_temp.id(2, 2), pg_temp.id(7, 1), '2020-01-01Z');

create function pg_temp.seed(n integer, start_at timestamptz, state text) returns void language plpgsql as $$
begin
    insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
    values (pg_temp.appt(n), pg_temp.id(7, 1), pg_temp.id(4, 1), pg_temp.id(2, 1), 'Visit ' || n, state,
            '2026-01-01Z'::timestamptz + make_interval(mins => n));
    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
        establishment_timezone_name, established_by_user_id, created_at
    ) values (pg_temp.appt(n), 1, 'REQUESTED', start_at, start_at + interval '30 minutes', 'Europe/Madrid',
              pg_temp.id(2, 1), '2026-01-01Z'::timestamptz + make_interval(mins => n));
    insert into public.care_authorizations (
        id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at, purpose, appointment_id, lifecycle_state
    ) values (pg_temp.id(12, n), pg_temp.id(7, 1), pg_temp.id(4, 1), pg_temp.id(3, 1), pg_temp.id(8, 1),
              '2026-01-01Z', 'APPOINTMENT_CARE', pg_temp.appt(n), 'ACTIVE');
    if state = 'CONFIRMED' then
        insert into public.appointment_schedule_revisions (
            appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
            establishment_timezone_name, established_by_user_id, created_at
        ) values (pg_temp.appt(n), 2, 'CONFIRMED', start_at, start_at + interval '30 minutes', 'Europe/Madrid',
                  pg_temp.id(2, 8), '2026-02-01Z');
        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
        ) values (pg_temp.appt(n), 'REQUESTED', 'CONFIRMED', pg_temp.id(2, 8), 'CLINIC', null, '2026-02-01Z', '2026-02-01Z');
    end if;
end $$;
select pg_temp.seed(1, '2035-03-05T09:00Z', 'REQUESTED');  -- accept, propose again, accept again, confirm
select pg_temp.seed(2, '2035-03-05T10:00Z', 'REQUESTED');  -- accept, then a Guardian reschedule
select pg_temp.seed(3, '2035-03-05T11:00Z', 'REQUESTED');  -- accept, then a Guardian cancellation
select pg_temp.seed(4, '2035-03-05T12:00Z', 'REQUESTED');  -- accept, then a Clinic cancellation
select pg_temp.seed(5, '2035-03-05T13:00Z', 'REQUESTED');  -- proposed, then withdrawn (never accepted)
select pg_temp.seed(6, '2035-03-05T14:00Z', 'REQUESTED');  -- no proposal at all
select pg_temp.seed(7, '2035-03-05T15:00Z', 'CONFIRMED');  -- accepted Clinic reschedule of a CONFIRMED one
select pg_temp.seed(8, '2035-03-05T16:00Z', 'REQUESTED');  -- accept, then EXPIRED
set local session_replication_role = origin;

-- VN 47: nothing is awaiting before an acceptance — a plain request, a
-- pending Clinic alternative (the Guardian must answer), a withdrawn one.
set local role authenticated;
select pg_temp.check_listed(6, 'ACTIVE|REQUESTED|-|false', 'A plain request is not awaiting');
select pg_temp.keep('p1', pg_temp.alt_propose(8, 1, '2035-03-06', '10:00', 1));
select pg_temp.check_listed(1, 'ACTIVE|REQUESTED|CLINIC|false',
    'A pending Clinic alternative needs the Guardian''s answer and is not awaiting the Clinic');
select pg_temp.keep('p5', pg_temp.alt_propose(8, 5, '2035-03-06', '13:00', 1));
select pg_temp.withdraw(8, pg_temp.named('p5'));
select pg_temp.check_listed(5, 'ACTIVE|REQUESTED|-|false', 'A withdrawn alternative leaves nothing awaiting');

-- VN 48: accepting it — by either Guardian — makes the request await the
-- Clinic for every current Guardian, and the pending proposal is gone.
select pg_temp.alt_accept(2, pg_temp.named('p1'));
select pg_temp.check_listed(1, 'ACTIVE|REQUESTED|-|true',
    'After the co-Guardian accepts, both Guardians see the request awaiting the Clinic');

-- VN 49: a new Clinic alternative on top of the accepted one is a separate
-- signal: the request is still awaiting AND a new answer is due; withdrawing
-- it keeps the awaiting state; accepting a second one keeps it too.
select pg_temp.keep('p1b', pg_temp.alt_propose(8, 1, '2035-03-07', '10:00', 2));
select pg_temp.check_listed(1, 'ACTIVE|REQUESTED|CLINIC|true',
    'A new pending alternative after an accepted one: both signals, never merged');
select pg_temp.withdraw(8, pg_temp.named('p1b'));
select pg_temp.check_listed(1, 'ACTIVE|REQUESTED|-|true', 'Withdrawing the new alternative keeps the accepted one awaiting');
select pg_temp.keep('p1c', pg_temp.alt_propose(8, 1, '2035-03-07', '11:00', 2));
select pg_temp.alt_accept(1, pg_temp.named('p1c'));
select pg_temp.check_listed(1, 'ACTIVE|REQUESTED|-|true', 'A second accepted alternative still awaits the Clinic');

-- VN 50: every way out ends it.
select pg_temp.confirm(8, 1, 3);
select pg_temp.check_listed(1, 'ACTIVE|CONFIRMED|-|false', 'Clinic confirmation ends it');

select pg_temp.keep('p2', pg_temp.alt_propose(8, 2, '2035-03-06', '11:00', 1));
select pg_temp.alt_accept(1, pg_temp.named('p2'));
select pg_temp.check_listed(2, 'ACTIVE|REQUESTED|-|true', 'Accepted alternative awaits (2)');
select pg_temp.guardian_reschedule(1, 2, '2035-03-08', '11:00');
select pg_temp.check_listed(2, 'ACTIVE|REQUESTED|-|false', 'A later Guardian reschedule ends it');

select pg_temp.keep('p3', pg_temp.alt_propose(8, 3, '2035-03-06', '12:00', 1));
select pg_temp.alt_accept(1, pg_temp.named('p3'));
select pg_temp.cancel(1, 3, 'GUARDIAN', null);
select pg_temp.check_listed(3, 'HISTORY|CANCELLED|-|false', 'A Guardian cancellation ends it and moves it to History');

select pg_temp.keep('p4', pg_temp.alt_propose(8, 4, '2035-03-06', '14:00', 1));
select pg_temp.alt_accept(2, pg_temp.named('p4'));
select pg_temp.cancel(8, 4, 'CLINIC', 2);
select pg_temp.check_listed(4, 'HISTORY|CANCELLED|-|false', 'A Clinic cancellation ends it');

select pg_temp.keep('p7', pg_temp.confirmed_propose(8, 7, '2035-03-09', '16:00', 2));
select pg_temp.check_listed(7, 'ACTIVE|CONFIRMED|CLINIC|false', 'A pending Clinic reschedule of a CONFIRMED one is not awaiting');
select pg_temp.confirmed_accept(1, pg_temp.named('p7'));
select pg_temp.check_listed(7, 'ACTIVE|CONFIRMED|-|false',
    'An accepted Clinic reschedule of a CONFIRMED Appointment is confirmed, never awaiting');

select pg_temp.keep('p8', pg_temp.alt_propose(8, 8, '2035-03-06', '15:00', 1));
select pg_temp.alt_accept(1, pg_temp.named('p8'));
select pg_temp.check_listed(8, 'ACTIVE|REQUESTED|-|true', 'Accepted alternative awaits (8)');
reset role;
set local session_replication_role = replica;
update public.appointments set lifecycle_state = 'EXPIRED' where id = pg_temp.appt(8);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.check_listed(8, 'HISTORY|EXPIRED|-|false', 'Expiry ends it and moves it to History');

-- The History read never reports it, whatever the provenance of the interval.
select pg_temp.act(1);
select pg_temp.assert_true(
    (select bool_and(not awaiting_clinic_confirmation) from public.get_guardian_appointment_history(null, null, 50))
    and (select count(*) from public.get_guardian_appointment_history(null, null, 50)) = 3,
    'History rows are never awaiting');
-- Exactly the awaiting set, across the whole Active list.
select pg_temp.assert_true(
    (select coalesce(array_agg(id order by id) filter (where awaiting_clinic_confirmation), '{}')
     from public.get_guardian_active_appointments(null, null, null, 50)) = '{}'::uuid[],
    'Nothing else awaits at the end');
reset role;

rollback;

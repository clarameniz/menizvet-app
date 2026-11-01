-- Professional calendar reads — day, Pending and History (SPEC-APT-012 §14,
-- BR-56–BR-59, Verification Notes 69–79), migration
-- 20261109090000_clinic_appointment_day_pending_history.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied. All fixtures and assertions are rolled back; superuser
-- execution is required solely to load a deliberately minimal deterministic
-- context and to switch between impersonated Users (same rationale as
-- clinic_appointment_calendar_reads_spec_apt_012.sql).
--
-- Covers:
--   * contracts, attributes and ACLs of the four reads and the internal
--     classification; earlier reads unchanged;
--   * day read: membership and parity with the month counts, states, latest
--     revision, establishment timezone, order, projection parity;
--   * Pending: every reason and its precedence, categories, ranks, actor
--     capabilities (OWNER, ADMINISTRATOR, RECEPTIONIST, VETERINARIAN),
--     non-actionable proposals, feasibility changing rank, order and page
--     membership, keyset pages with ties, changes between pages, summary =
--     classified rows;
--   * the classification's totals on every Pending row, independent of
--     cursor and limit, equal to the summary; empty pages;
--   * the conditional evaluation of proposal facts gives the same result as
--     the previous classification (a verbatim reference copy) for every
--     User at every fixture Clinic, across fixture changes;
--   * History: terminal states only, keyset pages with ties, deep cursors,
--     changes between pages;
--   * uniform 42501, 28000, anon, validation after authorization, no
--     cross-Clinic rows, no extra requester data, no side effects.
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

create function pg_temp.id(p_kind text, p_n integer)
returns uuid language sql immutable as $$
    select ('c0e90000-0000-4000-8000-000000000' || p_kind || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.a1() returns uuid language sql immutable as $$ select pg_temp.id('4', 1) $$;

-- 'dNN' for an Appointment id.
create function pg_temp.label(p_id uuid)
returns text language sql immutable as $$ select 'd' || right(p_id::text, 2) $$;

create function pg_temp.act(p_subject integer)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id('1', p_subject)::text, true)
$$;

-- The day read of A1 as 'dNN' labels, in returned order.
create function pg_temp.day(p_day date)
returns text[] language sql as $$
    select coalesce(array_agg(pg_temp.label(day_row.id) order by day_row.ordinality), '{}')
    from public.get_clinic_appointment_day(pg_temp.a1(), p_day) with ordinality as day_row
$$;

-- Every Pending row of a Clinic, read page by page with p_limit, as
-- 'dNN:REASON:CATEGORY:RANK' in returned order.
create function pg_temp.pending_walk(p_clinic_id uuid, p_limit integer)
returns text[] language plpgsql as $$
declare
    result text[] := '{}';
    pending_row record;
    after_rank integer;
    after_start timestamptz;
    after_id uuid;
    page_rows integer;
    pages integer := 0;
begin
    loop
        page_rows := 0;
        for pending_row in
            select * from public.get_clinic_appointment_pending(
                p_clinic_id, after_rank, after_start, after_id, p_limit
            )
        loop
            result := result || (pg_temp.label(pending_row.id) || ':' || pending_row.pending_reason
                                 || ':' || pending_row.pending_category || ':' || pending_row.pending_rank);
            after_rank := pending_row.pending_rank;
            after_start := pending_row.current_scheduled_start_at;
            after_id := pending_row.id;
            page_rows := page_rows + 1;
        end loop;
        pages := pages + 1;
        exit when page_rows < p_limit or pages > 100;
    end loop;
    return result;
end;
$$;

create function pg_temp.pending(p_limit integer default 100)
returns text[] language sql as $$ select pg_temp.pending_walk(pg_temp.a1(), p_limit) $$;

create function pg_temp.summary(p_clinic_id uuid default null)
returns text language sql as $$
    select summary_row.action_required_count || '/' || summary_row.awaiting_guardian_count
           || '/' || summary_row.informational_count
    from public.get_clinic_appointment_pending_summary(coalesce(p_clinic_id, pg_temp.a1())) as summary_row
$$;

-- The distinct totals carried by the Pending rows, read page by page with
-- p_limit, as 'action/awaiting/informational' (one entry when every page
-- agrees).
create function pg_temp.pending_totals_walk(p_clinic_id uuid, p_limit integer)
returns text[] language plpgsql as $$
declare
    result text[] := '{}';
    pending_row record;
    after_rank integer;
    after_start timestamptz;
    after_id uuid;
    page_rows integer;
    pages integer := 0;
    entry text;
begin
    loop
        page_rows := 0;
        for pending_row in
            select * from public.get_clinic_appointment_pending(
                p_clinic_id, after_rank, after_start, after_id, p_limit
            )
        loop
            entry := pending_row.action_required_count || '/' || pending_row.awaiting_guardian_count
                     || '/' || pending_row.informational_count;
            if not entry = any(result) then result := result || entry; end if;
            after_rank := pending_row.pending_rank;
            after_start := pending_row.current_scheduled_start_at;
            after_id := pending_row.id;
            page_rows := page_rows + 1;
        end loop;
        pages := pages + 1;
        exit when page_rows < p_limit or pages > 100;
    end loop;
    return result;
end;
$$;

-- Optimization equivalence (SPEC-APT-012 BR-57). The classification as it
-- was before the conditional evaluation of proposal facts, copied verbatim
-- from the reviewed version as a test oracle: every non-terminal Appointment
-- evaluated its actionable proposal and, for any proposal, its feasibility.
create function pg_temp.reference_pending_appointments(
    p_clinic_id uuid,
    p_acting_user_id uuid
)
returns table (
    appointment_id uuid,
    scheduled_start_at timestamptz,
    pending_reason text,
    pending_category text,
    pending_rank integer
)
language sql
stable
as $$
    with actor as materialized (
        select
            public.user_has_clinic_capability(p_acting_user_id, p_clinic_id, 'APPOINTMENT_CONFIRM') as can_confirm,
            public.user_has_clinic_capability(p_acting_user_id, p_clinic_id, 'APPOINTMENT_CANCEL') as can_cancel,
            public.user_has_clinic_capability(p_acting_user_id, p_clinic_id, 'APPOINTMENT_RESCHEDULE') as can_reschedule,
            public.user_has_clinic_capability(p_acting_user_id, p_clinic_id, 'APPOINTMENT_COMPLETE') as can_complete,
            public.user_has_clinic_capability(p_acting_user_id, p_clinic_id, 'APPOINTMENT_MARK_NO_SHOW') as can_mark_no_show
    ),
    clinic_context as materialized (
        select clinic.scheduling_timezone_name,
               -- Confirmation and Clinic proposals also require the
               -- Organization's Entitlement; cancellation, completion,
               -- No-show and withdrawal do not.
               coalesce(public.organization_has_professional_entitlement(
                   clinic.organization_id, 'APPOINTMENT_MANAGEMENT'
               ), false) as has_appointment_management
        from public.clinics as clinic
        where clinic.id = p_clinic_id
    ),
    -- The validated timezone, as in the schedule projection. Validation reads
    -- the timezone catalog and is costly, so it runs only when a feasibility
    -- is actually needed (first read of this CTE).
    clinic_timezone as materialized (
        select case
                   when public.clinic_timezone_name_is_valid(context_row.scheduling_timezone_name)
                       then context_row.scheduling_timezone_name
               end as valid_timezone_name
        from clinic_context as context_row
    ),
    -- Materialized so each proposal's actionability and feasibility are
    -- evaluated once, not once per CASE arm that reads them.
    candidate as materialized (
        select appointment.id,
               appointment.lifecycle_state,
               current_revision.scheduled_start_at,
               exists (
                   select 1
                   from public.clinical_record_entries as entry_row
                   where entry_row.appointment_id = appointment.id
               ) as has_encounter,
               pending_proposal.proposing_context,
               case
                   when pending_proposal.id is not null
                       then public.appointment_reschedule_proposal_is_currently_feasible(
                                pending_proposal.id,
                                (select timezone_row.valid_timezone_name from clinic_timezone as timezone_row)
                            )
               end as currently_feasible
        from public.appointments as appointment
        cross join lateral (
            select revision.scheduled_start_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
            order by revision.revision_sequence desc
            limit 1
        ) as current_revision
        left join lateral (
            select open_proposal.id, open_proposal.proposing_context
            from public.appointment_reschedule_proposals as open_proposal
            where open_proposal.appointment_id = appointment.id
              and open_proposal.state = 'PENDING'
              -- Cheap necessary conditions of actionability (a PENDING
              -- proposal's base is the current revision), so lapsed proposals
              -- skip the costly authority check; the helper still decides.
              and open_proposal.proposed_start_at > statement_timestamp()
              and current_revision.scheduled_start_at > statement_timestamp()
              and public.appointment_reschedule_proposal_is_actionable(
                  open_proposal.id,
                  statement_timestamp()
              )
            limit 1
        ) as pending_proposal on true
        where appointment.clinic_id = p_clinic_id
          and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED')
    ),
    classified as (
        select candidate.id,
               candidate.scheduled_start_at,
               -- Precedence: the first matching reason wins (BR-57).
               case
                   -- A visit whose start was reached and that this actor can
                   -- resolve: Complete (no Encounter condition), No-show or
                   -- Clinic cancellation (only without an Encounter).
                   when candidate.lifecycle_state = 'CONFIRMED'
                        and candidate.scheduled_start_at <= statement_timestamp()
                        and (actor.can_complete
                             or (not candidate.has_encounter
                                 and (actor.can_mark_no_show or actor.can_cancel)))
                       then 'ATTENDANCE_OUTCOME'
                   -- A request still in the future with no open proposal:
                   -- Confirm, propose an alternative, or cancel.
                   when candidate.lifecycle_state = 'REQUESTED'
                        and candidate.scheduled_start_at > statement_timestamp()
                        and candidate.proposing_context is null
                        and ((clinic_context.has_appointment_management
                              and (actor.can_confirm or actor.can_reschedule))
                             or (actor.can_cancel and not candidate.has_encounter))
                       then 'REQUEST_DECISION'
                   -- A Clinic proposal that is no longer feasible: withdraw it.
                   when candidate.proposing_context = 'CLINIC'
                        and candidate.currently_feasible is false
                        and actor.can_reschedule
                       then 'PROPOSAL_NOT_FEASIBLE'
                   -- A Guardian proposal: informational; the Professional app
                   -- offers no operation for it yet.
                   when candidate.proposing_context = 'GUARDIAN'
                        and actor.can_reschedule
                       then 'GUARDIAN_PROPOSAL'
                   -- A feasible Clinic proposal awaiting the Guardian.
                   when candidate.proposing_context = 'CLINIC'
                        and candidate.currently_feasible is true
                        and actor.can_reschedule
                       then 'AWAITING_GUARDIAN'
               end as pending_reason
        from candidate
        cross join actor
        cross join clinic_context
    )
    select classified.id,
           classified.scheduled_start_at,
           classified.pending_reason,
           case classified.pending_reason
               when 'GUARDIAN_PROPOSAL' then 'INFORMATIONAL'
               when 'AWAITING_GUARDIAN' then 'AWAITING_GUARDIAN'
               else 'ACTION_REQUIRED'
           end,
           case classified.pending_reason
               when 'ATTENDANCE_OUTCOME' then 1
               when 'REQUEST_DECISION' then 2
               when 'PROPOSAL_NOT_FEASIBLE' then 3
               when 'GUARDIAN_PROPOSAL' then 4
               else 5
           end
    from classified
    where classified.pending_reason is not null;
$$;

-- For every domain User (with or without any capability) and every fixture
-- Clinic, the new classification equals the reference row for row. Run as
-- the test superuser; returns how many (User, Clinic) pairs had Pending rows,
-- so the comparison is known not to be vacuous.
create function pg_temp.assert_equivalent(p_label text)
returns integer language plpgsql as $$
declare
    user_number integer;
    clinic_id uuid;
    new_rows text[];
    reference_rows text[];
    non_empty integer := 0;
begin
    foreach user_number in array array[1, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18] loop
        foreach clinic_id in array array[pg_temp.id('4', 1), pg_temp.id('4', 2), pg_temp.id('4', 3),
                                          pg_temp.id('4', 11), pg_temp.id('4', 12)] loop
            select coalesce(array_agg(row(pending.*)::text order by pending.appointment_id), '{}')
            into new_rows
            from public.clinic_pending_appointments(clinic_id, pg_temp.id('2', user_number)) as pending;
            select coalesce(array_agg(row(reference.*)::text order by reference.appointment_id), '{}')
            into reference_rows
            from pg_temp.reference_pending_appointments(clinic_id, pg_temp.id('2', user_number)) as reference;
            if new_rows is distinct from reference_rows then
                raise exception 'Equivalence (%): User % at Clinic % differs: % vs reference %',
                    p_label, user_number, clinic_id, new_rows, reference_rows;
            end if;
            if cardinality(new_rows) > 0 then non_empty := non_empty + 1; end if;
        end loop;
    end loop;
    return non_empty;
end;
$$;

-- Every History row of A1, page by page, as 'dNN' labels in returned order.
create function pg_temp.history(p_limit integer default 50)
returns text[] language plpgsql as $$
declare
    result text[] := '{}';
    history_row record;
    before_start timestamptz;
    before_id uuid;
    page_rows integer;
    pages integer := 0;
begin
    loop
        page_rows := 0;
        for history_row in
            select * from public.get_clinic_appointment_history(pg_temp.a1(), before_start, before_id, p_limit)
        loop
            result := result || pg_temp.label(history_row.id);
            before_start := history_row.current_scheduled_start_at;
            before_id := history_row.id;
            page_rows := page_rows + 1;
        end loop;
        pages := pages + 1;
        exit when page_rows < p_limit or pages > 100;
    end loop;
    return result;
end;
$$;

-- ===========================================================================
-- 1. Contracts, attributes, ACLs.
-- ===========================================================================

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_day(uuid, date)'::regprocedure)
    = pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)
    and pg_get_function_result('public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)'::regprocedure)
    = pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure),
    'Contract: the day read and History return exactly the BR-51 columns'
);

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)'::regprocedure)
    = left(pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure),
           length(pg_get_function_result('public.get_clinic_appointment_schedule(uuid)'::regprocedure)) - 1)
      || ', pending_reason text, pending_category text, pending_rank integer'
      || ', action_required_count integer, awaiting_guardian_count integer, informational_count integer)',
    'Contract: Pending returns the BR-51 columns plus reason, category, rank and the three totals'
);

select pg_temp.assert_true(
    pg_get_function_result('public.get_clinic_appointment_pending_summary(uuid)'::regprocedure)
    = 'TABLE(action_required_count integer, awaiting_guardian_count integer, informational_count integer)',
    'Contract: the summary returns only the three counts'
);

select pg_temp.assert_true(
    pg_get_function_arguments('public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)'::regprocedure)
    = 'p_clinic_id uuid, p_after_rank integer DEFAULT NULL::integer, p_after_start_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_after_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50'
    and pg_get_function_arguments('public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)'::regprocedure)
    = 'p_clinic_id uuid, p_before_start_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30',
    'Contract: cursor parameters and default limits (Pending 50, History 30)'
);

select pg_temp.assert_true(
    (select bool_and(proc.prosecdef and proc.provolatile = 's' and proc.proconfig = array['search_path=""'])
     from pg_proc as proc
     where proc.oid in (
         'public.get_clinic_appointment_day(uuid, date)'::regprocedure,
         'public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)'::regprocedure,
         'public.get_clinic_appointment_pending_summary(uuid)'::regprocedure,
         'public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)'::regprocedure,
         'public.clinic_pending_appointments(uuid, uuid)'::regprocedure
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
    'public.get_clinic_appointment_day(uuid, date)',
    'public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)',
    'public.get_clinic_appointment_pending_summary(uuid)',
    'public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)'
]) as signature;

select pg_temp.assert_true(
    not has_function_privilege('authenticated', 'public.clinic_pending_appointments(uuid, uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.clinic_pending_appointments(uuid, uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.clinic_pending_appointments(uuid, uuid)', 'EXECUTE'),
    'ACL: the internal classification is not executable by clients'
);

-- Earlier reads keep their single signature and grants (VN 68).
select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc where proname = function_name)
    and (select array_agg(acl_entry.grantee::regrole::text || ':' || acl_entry.privilege_type
                          order by acl_entry.grantee::regrole::text)
         from pg_proc as proc, aclexplode(proc.proacl) as acl_entry
         where proc.proname = function_name and acl_entry.grantee <> proc.proowner)
        = array['authenticated:EXECUTE', 'service_role:EXECUTE'],
    'Compatibility: ' || function_name || ' keeps one signature and its grants'
)
from unnest(array[
    'get_clinic_appointment_schedule', 'get_clinic_appointment', 'get_clinic_appointment_month_counts'
]) as function_name;

select pg_temp.assert_true(
    (select count(*) = 1 from pg_proc where proname = function_name)
    and not has_function_privilege('authenticated', proc_signature, 'EXECUTE'),
    'Compatibility: internal helper ' || function_name || ' unchanged and still internal'
)
from (values
    ('project_clinic_appointments', 'public.project_clinic_appointments(uuid, uuid[])'),
    ('clinic_calendar_appointments', 'public.clinic_calendar_appointments(uuid, date, date)')
) as helper (function_name, proc_signature);

-- ===========================================================================
-- Fixtures
--
-- Auth subjects …0001NN, domain Users …0002NN (the layout of the phase 1
-- suite):
--   01 Guardian and requester           06 OWNER (Organization) OrgA
--   07 ADMINISTRATOR (Organization)     08 ADMINISTRATOR (Clinic A1)
--   09 RECEPTIONIST (Organization)      10 RECEPTIONIST (Clinic A1)
--   11 VETERINARIAN, Assignment @ A1    12 VETERINARIAN, Assignment @ A2 only
--   13 VETERINARIAN, Assignment @ A1 ended
--   14 RECEPTIONIST (Clinic A2)         15 RECEPTIONIST (Organization), Membership ended
--   16 RECEPTIONIST (Clinic A1), Grant ended
--   17 ADMINISTRATOR (Organization) OrgB   18 bare OrgA Member
--   20 authenticated subject without domain User
-- OrgA (…0301, ACTIVE Subscription) operates A1 (…0401, Europe/Madrid, open
-- 08:00–20:00 every day) and A2 (…0402); OrgB (…0302, no Subscription)
-- operates B1 (…0411).
--
-- A1 non-terminal Appointments (Madrid civil time; "now" is the statement
-- instant, after 2026-01-20 and before 2035):
--   d01 CONFIRMED 2026-01-10 10:00                  -> ATTENDANCE_OUTCOME
--   d02 CONFIRMED 2026-01-10 10:00, Encounter       -> ATTENDANCE_OUTCOME (tie with d01)
--   d03 CONFIRMED 2026-01-05 10:00                  -> ATTENDANCE_OUTCOME
--   d04 REQUESTED 2035-05-01 10:00                  -> REQUEST_DECISION
--   d05 REQUESTED 2035-05-01 10:00                  -> REQUEST_DECISION (tie with d04)
--   d06 REQUESTED 2026-01-15 10:00 (expiry not materialized) -> not Pending
--   d07 CONFIRMED 2035-05-02 10:00                  -> not Pending
--   d08 CONFIRMED 2035-05-03 10:00 (requested 2035-04-20), feasible Clinic
--       proposal                                    -> AWAITING_GUARDIAN
--   d09 REQUESTED 2035-05-04 10:00, feasible Clinic alternative on
--       2035-05-11                                  -> AWAITING_GUARDIAN
--   d10 CONFIRMED 2035-05-05 10:00, Clinic proposal at 21:30 (closed)
--                                                   -> PROPOSAL_NOT_FEASIBLE
--   d11 CONFIRMED 2035-05-06 10:00, Guardian proposal -> GUARDIAN_PROPOSAL
--   d12 REQUESTED 2035-05-07 10:00, PENDING Clinic proposal whose proposer
--       lost authority (not actionable)             -> REQUEST_DECISION
--   d13 CONFIRMED 2026-01-20 10:00, PENDING Clinic proposal lapsed with the
--       base start                                  -> ATTENDANCE_OUTCOME
-- A1 terminal Appointments:
--   d14 COMPLETED 2025-06-10 10:00 (earlier revision 2025-07-01)
--   d15 NO_SHOW   2025-06-10 10:00
--   d16 CANCELLED 2025-06-10 10:00
--   d17 EXPIRED   2025-06-09 10:00
--   d18 COMPLETED 2025-06-10 23:30 (= 21:30Z)
--   d19 COMPLETED 2025-06-11 00:30 (= 06-10 22:30Z)
-- d20 REQUESTED 2035-05-01 and d22 COMPLETED 2025-06-10 at A2;
-- d21 REQUESTED 2035-05-01 at B1.
-- d30–d40 at A3 and d41–d45 at B2: proposal and Encounter combinations for
-- the optimization equivalence (described where they are inserted).
-- ===========================================================================

set local session_replication_role = replica;

insert into auth.users (id, email, email_confirmed_at)
select pg_temp.id('1', n), 'pending' || n || '@example.test', '2020-01-01Z'
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

insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values (pg_temp.id('f', 1), pg_temp.id('3', 1), '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null,
          'pending-test', pg_temp.id('f', 91));

insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes) values
    (pg_temp.id('4', 1), pg_temp.id('3', 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
    (pg_temp.id('4', 2), pg_temp.id('3', 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
    (pg_temp.id('4', 11), pg_temp.id('3', 2), true, '2020-01-01Z', 'Europe/Madrid', 30);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.a1(), weekday, '08:00', '20:00' from generate_series(1, 7) as weekday;

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
       '2025-01-01T08:00:00Z'::timestamptz + make_interval(mins => fixture.n)
from (values
    (1, 'CONFIRMED', pg_temp.id('4', 1)),  (2, 'CONFIRMED', pg_temp.id('4', 1)),
    (3, 'CONFIRMED', pg_temp.id('4', 1)),  (4, 'REQUESTED', pg_temp.id('4', 1)),
    (5, 'REQUESTED', pg_temp.id('4', 1)),  (6, 'REQUESTED', pg_temp.id('4', 1)),
    (7, 'CONFIRMED', pg_temp.id('4', 1)),  (8, 'CONFIRMED', pg_temp.id('4', 1)),
    (9, 'REQUESTED', pg_temp.id('4', 1)),  (10, 'CONFIRMED', pg_temp.id('4', 1)),
    (11, 'CONFIRMED', pg_temp.id('4', 1)), (12, 'REQUESTED', pg_temp.id('4', 1)),
    (13, 'CONFIRMED', pg_temp.id('4', 1)), (14, 'COMPLETED', pg_temp.id('4', 1)),
    (15, 'NO_SHOW', pg_temp.id('4', 1)),   (16, 'CANCELLED', pg_temp.id('4', 1)),
    (17, 'EXPIRED', pg_temp.id('4', 1)),   (18, 'COMPLETED', pg_temp.id('4', 1)),
    (19, 'COMPLETED', pg_temp.id('4', 1)), (20, 'REQUESTED', pg_temp.id('4', 2)),
    (21, 'REQUESTED', pg_temp.id('4', 11)), (22, 'COMPLETED', pg_temp.id('4', 2))
) as fixture (n, state, clinic_id);

insert into public.appointment_schedule_revisions (
    id, appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, source_proposal_id, created_at
)
select pg_temp.id(case revision_row.sequence_number when 1 then 'b' else 'c' end, revision_row.n),
       pg_temp.id('d', revision_row.n), revision_row.sequence_number, revision_row.context,
       revision_row.local_start::timestamp at time zone 'Europe/Madrid',
       (revision_row.local_start::timestamp at time zone 'Europe/Madrid') + interval '30 minutes',
       'Europe/Madrid', pg_temp.id('2', 1), null,
       '2025-01-01T09:00:00Z'::timestamptz + make_interval(mins => revision_row.n * 10 + revision_row.sequence_number)
from (values
    (1,  1, 'CONFIRMED', '2026-01-10 10:00'),
    (2,  1, 'CONFIRMED', '2026-01-10 10:00'),
    (3,  1, 'CONFIRMED', '2026-01-05 10:00'),
    (4,  1, 'REQUESTED', '2035-05-01 10:00'),
    (5,  1, 'REQUESTED', '2035-05-01 10:00'),
    (6,  1, 'REQUESTED', '2026-01-15 10:00'),
    (7,  1, 'CONFIRMED', '2035-05-02 10:00'),
    (8,  1, 'REQUESTED', '2035-04-20 10:00'),
    (8,  2, 'CONFIRMED', '2035-05-03 10:00'),
    (9,  1, 'REQUESTED', '2035-05-04 10:00'),
    (10, 1, 'CONFIRMED', '2035-05-05 10:00'),
    (11, 1, 'CONFIRMED', '2035-05-06 10:00'),
    (12, 1, 'REQUESTED', '2035-05-07 10:00'),
    (13, 1, 'CONFIRMED', '2026-01-20 10:00'),
    (14, 1, 'CONFIRMED', '2025-07-01 10:00'),
    (14, 2, 'CONFIRMED', '2025-06-10 10:00'),
    (15, 1, 'CONFIRMED', '2025-06-10 10:00'),
    (16, 1, 'CONFIRMED', '2025-06-10 10:00'),
    (17, 1, 'REQUESTED', '2025-06-09 10:00'),
    (18, 1, 'CONFIRMED', '2025-06-10 23:30'),
    (19, 1, 'CONFIRMED', '2025-06-11 00:30'),
    (20, 1, 'REQUESTED', '2035-05-01 10:00'),
    (21, 1, 'REQUESTED', '2035-05-01 10:00'),
    (22, 1, 'CONFIRMED', '2025-06-10 10:00')
) as revision_row (n, sequence_number, context, local_start);

-- PENDING proposals, each on its Appointment's current revision. Madrid is
-- UTC+2 in May 2035: 09:00Z = 11:00 (open), 19:30Z = 21:30 (closed).
insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
)
select pg_temp.id('e', proposal_row.n), pg_temp.id('d', proposal_row.n), revision.id, revision.revision_context,
       proposal_row.proposed_start::timestamptz, proposal_row.proposed_start::timestamptz + interval '30 minutes',
       'Europe/Madrid', proposal_row.context, pg_temp.id('2', proposal_row.proposer), 'Move it',
       '2025-12-01Z'
from (values
    (8,  '2035-05-10T09:00:00Z', 'CLINIC',   6),
    (9,  '2035-05-11T09:00:00Z', 'CLINIC',   6),
    (10, '2035-05-12T19:30:00Z', 'CLINIC',   6),
    (11, '2035-05-13T09:00:00Z', 'GUARDIAN', 1),
    (12, '2035-05-14T09:00:00Z', 'CLINIC',   16),
    (13, '2035-05-15T09:00:00Z', 'CLINIC',   6)
) as proposal_row (n, proposed_start, context, proposer)
join lateral (
    select candidate_revision.id, candidate_revision.revision_context
    from public.appointment_schedule_revisions as candidate_revision
    where candidate_revision.appointment_id = pg_temp.id('d', proposal_row.n)
    order by candidate_revision.revision_sequence desc
    limit 1
) as revision on true;

insert into public.appointment_lifecycle_events (
    appointment_id, from_state, to_state, actor_user_id, actor_context, reason, effective_at, recorded_at
) values (pg_temp.id('d', 16), 'CONFIRMED', 'CANCELLED', pg_temp.id('2', 6), 'CLINIC',
          'Clinic closed that day', '2025-06-01Z', '2025-06-01Z');

insert into public.clinical_record_entries (
    appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at,
    category, clinical_content, creation_idempotency_key, creation_request_digest
) values (pg_temp.id('d', 2), pg_temp.id('2', 11), pg_temp.id('8', 11), '2026-01-10T09:05:00Z',
          'CLINICAL_NOTE', 'Fixture note', gen_random_uuid(), sha256(gen_random_uuid()::text::bytea));

-- Equivalence Clinics for the conditional proposal evaluation: A3 (OrgA,
-- Entitlement, open 08:00–20:00; Veterinarian 12 also assigned) and B2 (OrgB,
-- no Entitlement, no Appointment availability, so every Clinic proposal is
-- infeasible). June 2035 in Madrid is UTC+2.
insert into public.clinics (id, organization_id, is_published, created_at, scheduling_timezone_name,
    standard_appointment_duration_minutes) values
    (pg_temp.id('4', 3), pg_temp.id('3', 1), true, '2020-01-01Z', 'Europe/Madrid', 30),
    (pg_temp.id('4', 12), pg_temp.id('3', 2), true, '2020-01-01Z', 'Europe/Madrid', 30);

insert into public.clinic_appointment_availability_periods (clinic_id, iso_weekday, start_time, end_time)
select pg_temp.id('4', 3), weekday, '08:00', '20:00' from generate_series(1, 7) as weekday;

insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id, effective_start, effective_end
) values (pg_temp.id('8', 14), pg_temp.id('7', 12), pg_temp.id('5', 12), pg_temp.id('4', 3), '2020-01-01Z', null);

insert into public.appointments (
    id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at
)
select pg_temp.id('d', fixture.n), pg_temp.id('9', 1), fixture.clinic_id, pg_temp.id('2', 1),
       'Check-up', fixture.state, '2025-01-01T08:00:00Z'
from (values
    (30, 'CONFIRMED', pg_temp.id('4', 3)),  (31, 'CONFIRMED', pg_temp.id('4', 3)),
    (32, 'REQUESTED', pg_temp.id('4', 3)),  (33, 'REQUESTED', pg_temp.id('4', 3)),
    (34, 'REQUESTED', pg_temp.id('4', 3)),  (35, 'REQUESTED', pg_temp.id('4', 3)),
    (36, 'CONFIRMED', pg_temp.id('4', 3)),  (37, 'CONFIRMED', pg_temp.id('4', 3)),
    (38, 'REQUESTED', pg_temp.id('4', 3)),  (39, 'REQUESTED', pg_temp.id('4', 3)),
    (40, 'CONFIRMED', pg_temp.id('4', 3)),
    (41, 'REQUESTED', pg_temp.id('4', 12)), (42, 'REQUESTED', pg_temp.id('4', 12)),
    (43, 'REQUESTED', pg_temp.id('4', 12)), (44, 'REQUESTED', pg_temp.id('4', 12)),
    (45, 'CONFIRMED', pg_temp.id('4', 12))
) as fixture (n, state, clinic_id);

insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, created_at
)
select pg_temp.id('d', revision_row.n), 1, revision_row.context,
       revision_row.local_start::timestamp at time zone 'Europe/Madrid',
       (revision_row.local_start::timestamp at time zone 'Europe/Madrid') + interval '30 minutes',
       'Europe/Madrid', pg_temp.id('2', 1), '2025-01-01T09:00:00Z'
from (values
    (30, 'CONFIRMED', '2035-06-01 10:00'), (31, 'CONFIRMED', '2035-06-02 10:00'),
    (32, 'REQUESTED', '2035-06-03 10:00'), (33, 'REQUESTED', '2035-06-04 10:00'),
    (34, 'REQUESTED', '2035-06-05 10:00'), (35, 'REQUESTED', '2035-06-06 10:00'),
    (36, 'CONFIRMED', '2035-06-07 10:00'), (37, 'CONFIRMED', '2026-02-01 10:00'),
    (38, 'REQUESTED', '2035-06-08 10:00'), (39, 'REQUESTED', '2035-06-09 10:00'),
    (40, 'CONFIRMED', '2026-02-02 10:00'),
    (41, 'REQUESTED', '2035-06-11 10:00'), (42, 'REQUESTED', '2035-06-12 10:00'),
    (43, 'REQUESTED', '2035-06-13 10:00'), (44, 'REQUESTED', '2035-06-14 10:00'),
    (45, 'CONFIRMED', '2035-06-15 10:00')
) as revision_row (n, context, local_start);

insert into public.appointment_reschedule_proposals (
    id, appointment_id, base_revision_id, base_revision_context, proposed_start_at, proposed_end_at,
    proposed_timezone_name, proposing_context, proposed_by_user_id, reason, created_at
)
select pg_temp.id('e', proposal_row.n), pg_temp.id('d', proposal_row.n), revision.id, revision.revision_context,
       proposal_row.proposed_start::timestamptz, proposal_row.proposed_start::timestamptz + interval '30 minutes',
       'Europe/Madrid', proposal_row.context, pg_temp.id('2', proposal_row.proposer), 'Move it',
       '2025-12-01Z'
from (values
    (30, '2035-06-20T19:30:00Z', 'GUARDIAN', 1),   -- Guardian, infeasible
    (31, '2035-06-21T09:00:00Z', 'GUARDIAN', 1),   -- Guardian, feasible
    (32, '2035-06-22T09:00:00Z', 'CLINIC',   6),   -- Clinic, feasible
    (33, '2035-06-23T19:30:00Z', 'CLINIC',   6),   -- Clinic, infeasible
    (34, '2026-01-01T09:00:00Z', 'CLINIC',   6),   -- proposed start passed: lapsed
    (35, '2035-06-24T09:00:00Z', 'CLINIC',   16),  -- proposer's authority ended
    (36, '2035-06-25T09:00:00Z', 'CLINIC',   16),  -- proposer's authority ended
    (37, '2035-06-26T09:00:00Z', 'CLINIC',   6),   -- base start passed: lapsed
    (38, '2035-06-27T09:00:00Z', 'CLINIC',   6),   -- feasible, on a request with an Encounter
    (41, '2035-06-28T09:00:00Z', 'CLINIC',   17),  -- B2: infeasible (no availability)
    (44, '2035-06-29T09:00:00Z', 'CLINIC',   17),  -- B2: infeasible, request with an Encounter
    (45, '2035-06-30T09:00:00Z', 'GUARDIAN', 1)    -- B2: Guardian
) as proposal_row (n, proposed_start, context, proposer)
join public.appointment_schedule_revisions as revision
  on revision.appointment_id = pg_temp.id('d', proposal_row.n) and revision.revision_sequence = 1;

-- Fixture-only clinical documentation (an Appointment with an Entry cannot
-- be cancelled). On a request it is structurally impossible since SPEC-MED-010;
-- it is kept to exercise the read's defensive classification.
insert into public.clinical_record_entries (
    appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at,
    category, clinical_content, creation_idempotency_key, creation_request_digest
)
select pg_temp.id('d', entry_row.n), pg_temp.id('2', 12), pg_temp.id('8', 14), '2026-02-01T09:05:00Z',
       'CLINICAL_NOTE', 'Fixture note', gen_random_uuid(), sha256(gen_random_uuid()::text::bytea)
from (values (37), (38), (39), (42), (44)) as entry_row (n);

set local session_replication_role = origin;

create temporary table side_effect_baseline on commit drop as
select
    (select count(*) from public.transactional_communications) as communications,
    (select count(*) from public.medical_access_audit_events) as audit_events,
    (select count(*) from public.appointment_lifecycle_events) as lifecycle_events,
    (select count(*) from public.appointment_schedule_revisions) as revisions,
    (select count(*) from public.appointment_reschedule_proposals) as proposals;

-- ===========================================================================
-- 2. Uniform denial, authentication, validation after authorization.
-- ===========================================================================

do $$
declare
    subject integer;
    statement_text text;
begin
    foreach subject in array array[12, 13, 14, 15, 16, 17, 18, 1] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        foreach statement_text in array array[
            format('select * from public.get_clinic_appointment_day(%L, %L)', pg_temp.a1(), '2025-06-10'),
            format('select * from public.get_clinic_appointment_pending(%L)', pg_temp.a1()),
            format('select * from public.get_clinic_appointment_pending_summary(%L)', pg_temp.a1()),
            format('select * from public.get_clinic_appointment_history(%L)', pg_temp.a1()),
            -- Invalid input never reveals more than the denial.
            format('select * from public.get_clinic_appointment_day(%L, null)', pg_temp.a1()),
            format('select * from public.get_clinic_appointment_pending(%L, p_limit => 0)', pg_temp.a1()),
            format('select * from public.get_clinic_appointment_history(%L, p_limit => 0)', pg_temp.a1())
        ] loop
            perform pg_temp.assert_error(statement_text, '42501',
                                         'Applicable Appointment schedule-view capability is required');
        end loop;
        reset role;
    end loop;
end;
$$;

-- Unknown Clinic, another Organization's Clinic, null Clinic: the same denial.
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_error(statement_text, '42501', 'Applicable Appointment schedule-view capability is required')
from (values
    (format('select * from public.get_clinic_appointment_day(%L, %L)', pg_temp.id('4', 99), '2025-06-10')),
    (format('select * from public.get_clinic_appointment_pending(%L)', pg_temp.id('4', 11))),
    (format('select * from public.get_clinic_appointment_pending_summary(%L)', pg_temp.id('4', 11))),
    ('select * from public.get_clinic_appointment_history(null)')
) as bad (statement_text);

-- Validation, after authorization.
select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_day(%L, %s)', pg_temp.a1(), day_value),
    '22023', 'Calendar day is invalid'
)
from (values ('null'), ('''1999-12-31'''), ('''3000-01-01''')) as bad (day_value);

select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_pending(%L, %s)', pg_temp.a1(), arguments),
    '22023', 'Pending page is invalid'
)
from (values
    ('p_limit => 0'), ('p_limit => 101'), ('p_limit => null'), ('p_limit => -1'),
    ('1, null, null'), ('null, ''2035-01-01Z'', null'), ('null, null, ''' || pg_temp.id('d', 1) || ''''),
    ('1, ''2035-01-01Z'', null'), ('null, ''2035-01-01Z'', ''' || pg_temp.id('d', 1) || ''''),
    ('0, ''2035-01-01Z'', ''' || pg_temp.id('d', 1) || ''''),
    ('6, ''2035-01-01Z'', ''' || pg_temp.id('d', 1) || '''')
) as bad (arguments);

select pg_temp.assert_error(
    format('select * from public.get_clinic_appointment_history(%L, %s)', pg_temp.a1(), arguments),
    '22023', 'History page is invalid'
)
from (values
    ('p_limit => 0'), ('p_limit => 51'), ('p_limit => null'),
    ('''2025-06-10Z'', null'), ('null, ''' || pg_temp.id('d', 1) || '''')
) as bad (arguments);

-- The limits' bounds are accepted.
select pg_temp.assert_true(
    (select count(*) = 1 from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 1))
    and (select count(*) = 11 from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 100))
    and (select count(*) = 1 from public.get_clinic_appointment_history(pg_temp.a1(), p_limit => 1))
    and (select count(*) = 6 from public.get_clinic_appointment_history(pg_temp.a1(), p_limit => 50))
    and (select count(*) = 6 from public.get_clinic_appointment_history(pg_temp.a1())),
    'Validation: limits 1 and 100 (Pending), 1, 50 and the default (History) are accepted'
);
reset role;

-- Clients cannot call the internal classification.
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_error(
    format('select * from public.clinic_pending_appointments(%L, %L)', pg_temp.a1(), pg_temp.id('2', 6)),
    '42501', 'permission denied'
);
reset role;

-- No subject, no domain User, anon.
do $$
declare
    statement_text text;
begin
    foreach statement_text in array array[
        format('select * from public.get_clinic_appointment_day(%L, %L)', pg_temp.a1(), '2025-06-10'),
        format('select * from public.get_clinic_appointment_pending(%L)', pg_temp.a1()),
        format('select * from public.get_clinic_appointment_pending_summary(%L)', pg_temp.a1()),
        format('select * from public.get_clinic_appointment_history(%L)', pg_temp.a1())
    ] loop
        perform set_config('request.jwt.claim.sub', '', true);
        set local role authenticated;
        perform pg_temp.assert_error(statement_text, '28000', 'Authentication is required');
        reset role;
        perform pg_temp.act(20);
        set local role authenticated;
        perform pg_temp.assert_error(statement_text, '28000', 'No coherent domain User');
        reset role;
        perform pg_temp.act(10);
        set local role anon;
        perform pg_temp.assert_error(statement_text, '42501', 'permission denied');
        reset role;
    end loop;
end;
$$;

-- ===========================================================================
-- 3. Day read (BR-56).
-- ===========================================================================

select pg_temp.act(10);
set local role authenticated;

-- 2025-06-10 in Madrid: d14 (latest revision; not 07-01), d15 NO_SHOW, both
-- 10:00 and ordered by id, then d18 at 23:30. d16 CANCELLED excluded; d19 is
-- 00:30 on 06-11 locally although 06-10 in UTC; d22 is A2's.
select pg_temp.assert_true(
    pg_temp.day('2025-06-10') = array['d14', 'd15', 'd18']
    and pg_temp.day('2025-06-11') = array['d19']
    and pg_temp.day('2025-06-09') = '{}'
    and pg_temp.day('2025-07-01') = '{}',
    'Day: terminal states, latest revision, CANCELLED/EXPIRED excluded, local midnight, order (start, id)'
);

select pg_temp.assert_true(
    pg_temp.day('2026-01-10') = array['d01', 'd02']
    and pg_temp.day('2026-01-15') = array['d06']
    and pg_temp.day('2035-05-03') = array['d08']
    and pg_temp.day('2035-04-20') = '{}'
    and pg_temp.day('2035-05-10') = '{}'
    and pg_temp.day('2035-05-11') = '{}'
    and pg_temp.day('2035-05-01') = array['d04', 'd05'],
    'Day: non-terminal states on their current date only; a proposal never adds its date; no other Clinic'
);

-- Exact parity with the month counts for every day of the tested months.
select pg_temp.assert_true(
    not exists (
        select 1
        from (values (2025, 6), (2025, 7), (2026, 1), (2035, 4), (2035, 5)) as tested (year_value, month_value),
             generate_series(
                 make_date(tested.year_value, tested.month_value, 1),
                 make_date(tested.year_value, tested.month_value, 1) + interval '1 month' - interval '1 day',
                 interval '1 day'
             ) as calendar_day
        where (select count(*) from public.get_clinic_appointment_day(pg_temp.a1(), calendar_day::date))
              is distinct from coalesce((
                  select month_count.appointment_count
                  from public.get_clinic_appointment_month_counts(pg_temp.a1(), tested.year_value, tested.month_value)
                       as month_count
                  where month_count.day = calendar_day::date
              ), 0)
    ),
    'Day: each day''s row count equals that day''s month count (absent = 0)'
);

-- Each day row is, column for column, the single-Appointment read.
select pg_temp.assert_true(
    not exists (
        select 1
        from (values ('2025-06-10'::date), ('2026-01-10'), ('2035-05-03')) as tested (day_value),
             public.get_clinic_appointment_day(pg_temp.a1(), tested.day_value) as day_row
        where to_jsonb(day_row) is distinct from (
            select to_jsonb(single_row) from public.get_clinic_appointment(pg_temp.a1(), day_row.id) as single_row
        )
    ),
    'Day: every row equals get_clinic_appointment for the same Appointment'
);

select pg_temp.assert_true(
    (select requester_display_name = 'Marta Ruiz' and has_clinical_record
     from public.get_clinic_appointment_day(pg_temp.a1(), '2026-01-10') where id = pg_temp.id('d', 2))
    and not exists (
        select 1
        from public.get_clinic_appointment_day(pg_temp.a1(), '2025-06-10') as day_row,
             jsonb_object_keys(to_jsonb(day_row)) as column_name
        where column_name ~ '(email|phone|guardianship|auth)'
    ),
    'Day: requester display name, never email, phone, Guardianship or auth data'
);
reset role;

-- The session timezone never moves a day.
set local timezone = 'Pacific/Kiritimati';
select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.day('2025-06-10') = array['d14', 'd15', 'd18'] and pg_temp.day('2025-06-11') = array['d19'],
    'Day: identical under a +14:00 session timezone'
);
reset role;
reset timezone;

-- A Veterinarian with a current Assignment and an Organization-wide Owner
-- read the same day.
do $$
declare
    subject integer;
begin
    foreach subject in array array[6, 7, 8, 9, 11] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        perform pg_temp.assert_true(pg_temp.day('2025-06-10') = array['d14', 'd15', 'd18'],
                                    'Day: actor ' || subject || ' reads the day');
        reset role;
    end loop;
end;
$$;

-- ===========================================================================
-- 3b. Conditional proposal evaluation: same result as before (BR-57).
-- ===========================================================================

-- The new classification equals the reference for every domain User at every
-- fixture Clinic.
select pg_temp.assert_true(
    pg_temp.assert_equivalent('initial fixtures') >= 10,
    'Equivalence: initial fixtures compared with Pending rows for at least 10 (User, Clinic) pairs'
);

-- A3, for every manager with Organization scope: Guardian proposals are
-- informational whether feasible (d31) or not (d30); a feasible Clinic
-- proposal awaits the Guardian, also on a request with an Encounter (d38); an
-- infeasible one is actionable (d33); a lapsed proposal (d34) or one whose
-- proposer lost authority (d35) leaves the request to decide, and on a
-- confirmed visit (d36) leaves nothing; a reached visit with a lapsed proposal
-- is an attendance outcome (d37); a request with an Encounter is still decided
-- by confirmation with the Entitlement (d39).
do $$
declare
    subject integer;
begin
    foreach subject in array array[6, 7, 9] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        perform pg_temp.assert_true(
            pg_temp.pending_walk(pg_temp.id('4', 3), 3) = array[
                'd37:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
                'd40:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
                'd34:REQUEST_DECISION:ACTION_REQUIRED:2',
                'd35:REQUEST_DECISION:ACTION_REQUIRED:2',
                'd39:REQUEST_DECISION:ACTION_REQUIRED:2',
                'd33:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
                'd30:GUARDIAN_PROPOSAL:INFORMATIONAL:4',
                'd31:GUARDIAN_PROPOSAL:INFORMATIONAL:4',
                'd32:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5',
                'd38:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5'
            ]
            and pg_temp.summary(pg_temp.id('4', 3)) = '6/2/2'
            and pg_temp.pending_totals_walk(pg_temp.id('4', 3), 3) = array['6/2/2'],
            'Equivalence: actor ' || subject || ' classifies A3 as before: '
            || pg_temp.pending_walk(pg_temp.id('4', 3), 3)::text
        );
        reset role;
    end loop;
end;
$$;

-- The Veterinarian assigned at A3 only completes: proposals never matter.
select pg_temp.act(12);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 3), 50) = array[
        'd37:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd40:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1'
    ]
    and pg_temp.summary(pg_temp.id('4', 3)) = '2/0/0',
    'Equivalence: a Veterinarian sees the same attendance outcomes without proposal evaluation'
);

-- A first page that is empty means every total is zero (A2 has a request the
-- Veterinarian cannot decide); the summary says so.
select pg_temp.assert_true(
    not exists (select 1 from public.get_clinic_appointment_pending(pg_temp.id('4', 2)))
    and pg_temp.summary(pg_temp.id('4', 2)) = '0/0/0',
    'Totals: an empty first page corresponds to an all-zero summary'
);
reset role;

-- B2 without the Entitlement: withdrawal needs none, so infeasible Clinic
-- proposals are actionable (d41, also with an Encounter, d44); a request
-- without an Encounter is decided by cancellation (d43); one with an Encounter
-- has no available operation (d42); the Guardian proposal is informational.
select pg_temp.act(17);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 12), 2) = array[
        'd43:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd41:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd44:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd45:GUARDIAN_PROPOSAL:INFORMATIONAL:4'
    ]
    and pg_temp.summary(pg_temp.id('4', 12)) = '3/0/1'
    and pg_temp.pending_totals_walk(pg_temp.id('4', 12), 2) = array['3/0/1'],
    'Equivalence: B2 without the Entitlement classifies as before'
);
reset role;

-- ===========================================================================
-- 4. Pending classification and order (BR-57, BR-58).
-- ===========================================================================

create temporary table expected_pending (expected text[]) on commit drop;
insert into expected_pending values (array[
    'd03:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
    'd01:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
    'd02:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
    'd13:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
    'd04:REQUEST_DECISION:ACTION_REQUIRED:2',
    'd05:REQUEST_DECISION:ACTION_REQUIRED:2',
    'd12:REQUEST_DECISION:ACTION_REQUIRED:2',
    'd10:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
    'd11:GUARDIAN_PROPOSAL:INFORMATIONAL:4',
    'd08:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5',
    'd09:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5'
]);
grant select on expected_pending to authenticated;

-- Every Clinic manager (Owner, Administrators, Receptionists, Organization- or
-- Clinic-scoped) holds every Appointment capability: the full classification,
-- for every page size, and a summary equal to the classified rows.
do $$
declare
    subject integer;
    page_size integer;
begin
    foreach subject in array array[6, 7, 8, 9, 10] loop
        perform pg_temp.act(subject);
        set local role authenticated;
        foreach page_size in array array[1, 2, 3, 4, 7, 10, 11, 50, 100] loop
            perform pg_temp.assert_true(
                pg_temp.pending(page_size) = (select expected from expected_pending),
                'Pending: actor ' || subject || ', pages of ' || page_size || ': ' || pg_temp.pending(page_size)::text
            );
            -- Every row of every page carries the whole classification's
            -- totals, whatever the cursor and the limit.
            perform pg_temp.assert_true(
                pg_temp.pending_totals_walk(pg_temp.a1(), page_size) = array['8/2/1'],
                'Totals: actor ' || subject || ', pages of ' || page_size || ' all carry 8/2/1: '
                || pg_temp.pending_totals_walk(pg_temp.a1(), page_size)::text
            );
        end loop;
        perform pg_temp.assert_true(
            pg_temp.summary() = '8/2/1',
            'Summary: actor ' || subject || ' counts 8 actionable, 2 awaiting the Guardian, 1 informational'
        );
        reset role;
    end loop;
end;
$$;

select pg_temp.act(10);
set local role authenticated;

-- The default page is 50 rows: one page here.
select pg_temp.assert_true(
    (select array_agg(pg_temp.label(pending_row.id) || ':' || pending_row.pending_reason || ':'
                      || pending_row.pending_category || ':' || pending_row.pending_rank
                      order by pending_row.ordinality)
     from public.get_clinic_appointment_pending(pg_temp.a1()) with ordinality as pending_row)
    = (select expected from expected_pending),
    'Pending: the first page with defaults returns the whole classification in order'
);

-- The summary equals the classified rows, category by category.
select pg_temp.assert_true(
    pg_temp.summary() = (
        select count(*) filter (where entry like '%:ACTION_REQUIRED:%') || '/'
               || count(*) filter (where entry like '%:AWAITING_GUARDIAN:%') || '/'
               || count(*) filter (where entry like '%:INFORMATIONAL:%')
        from unnest(pg_temp.pending()) as entry
    ),
    'Summary: equals the classified Pending rows'
);

-- In one call, the totals equal the categories of the rows that same call
-- returns when the page holds everything, and a single deep page (after the
-- cursor of rank 4) carries the same totals.
select pg_temp.assert_true(
    (select bool_and(page_row.action_required_count = totals.action_required
                     and page_row.awaiting_guardian_count = totals.awaiting_guardian
                     and page_row.informational_count = totals.informational)
     from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 100) as page_row
     cross join (
         select count(*) filter (where counted.pending_category = 'ACTION_REQUIRED') as action_required,
                count(*) filter (where counted.pending_category = 'AWAITING_GUARDIAN') as awaiting_guardian,
                count(*) filter (where counted.pending_category = 'INFORMATIONAL') as informational
         from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 100) as counted
     ) as totals)
    and (select array_agg(distinct deep_row.action_required_count || '/' || deep_row.awaiting_guardian_count
                          || '/' || deep_row.informational_count)
         from public.get_clinic_appointment_pending(
             pg_temp.a1(), 4, 'infinity', 'ffffffff-ffff-4fff-bfff-ffffffffffff', 1) as deep_row)
        = array['8/2/1'],
    'Totals: equal the rows of the same call, and a deep page of one row carries the global totals'
);

-- Each Pending row is, column for column, the single-Appointment read, and the
-- category agrees with the projected feasibility.
select pg_temp.assert_true(
    not exists (
        select 1
        from public.get_clinic_appointment_pending(pg_temp.a1()) as pending_row
        where (to_jsonb(pending_row) - array['pending_reason', 'pending_category', 'pending_rank',
                                             'action_required_count', 'awaiting_guardian_count',
                                             'informational_count'])
              is distinct from (
                  select to_jsonb(single_row)
                  from public.get_clinic_appointment(pg_temp.a1(), pending_row.id) as single_row
              )
           or (pending_row.pending_reason = 'AWAITING_GUARDIAN'
               and pending_row.pending_reschedule_currently_feasible is not true)
           or (pending_row.pending_reason = 'PROPOSAL_NOT_FEASIBLE'
               and pending_row.pending_reschedule_currently_feasible is not false)
           or (pending_row.pending_reason in ('ATTENDANCE_OUTCOME', 'REQUEST_DECISION')
               and pending_row.pending_reschedule_proposal_id is not null)
    ),
    'Pending: rows equal get_clinic_appointment; categories agree with the projected proposal and feasibility'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from public.get_clinic_appointment_pending(pg_temp.a1()) as pending_row,
             jsonb_object_keys(to_jsonb(pending_row)) as column_name
        where column_name ~ '(email|phone|guardianship|auth)'
    ),
    'Pending: no email, phone, Guardianship or auth data'
);
reset role;

-- A Veterinarian with a current Assignment can only complete: only reached
-- CONFIRMED visits, with or without an Encounter.
select pg_temp.act(11);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending(1) = array[
        'd03:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd01:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd02:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd13:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1'
    ]
    and pg_temp.summary() = '4/0/0',
    'Pending: a Veterinarian sees only the attendance outcomes it can record'
);
reset role;

-- Other Clinics never leak in: A2 and B1 have their own Pending work.
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 2), 50) = array['d20:REQUEST_DECISION:ACTION_REQUIRED:2']
    and pg_temp.summary(pg_temp.id('4', 2)) = '1/0/0',
    'Pending: A2 shows only its own request'
);
reset role;

-- B1's Organization has no APPOINTMENT_MANAGEMENT Entitlement: confirmation
-- and Clinic proposals are unavailable, but cancellation still is.
select pg_temp.act(17);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 11), 50) = array['d21:REQUEST_DECISION:ACTION_REQUIRED:2']
    and pg_temp.summary(pg_temp.id('4', 11)) = '1/0/0',
    'Pending: without the Entitlement a future request stays actionable through cancellation'
);
reset role;

-- The Entitlement matters when cancellation is impossible. A fixture-only
-- Encounter on B1's request (cancellation then refused) leaves no operation
-- without the Entitlement; with it, confirmation remains.
set local session_replication_role = replica;
insert into public.clinical_record_entries (
    appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id, created_at,
    category, clinical_content, creation_idempotency_key, creation_request_digest
) values (pg_temp.id('d', 21), pg_temp.id('2', 11), pg_temp.id('8', 11), '2026-01-10T09:05:00Z',
          'CLINICAL_NOTE', 'Fixture note', gen_random_uuid(), sha256(gen_random_uuid()::text::bytea));
set local session_replication_role = origin;
select pg_temp.act(17);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 11), 50) = '{}' and pg_temp.summary(pg_temp.id('4', 11)) = '0/0/0',
    'Pending: no capability is invented — without the Entitlement and without cancellation nothing is actionable'
);
reset role;
select pg_temp.assert_true(
    pg_temp.assert_equivalent('B1 Encounter') >= 10,
    'Equivalence: after the B1 Encounter'
);
set local session_replication_role = replica;
insert into public.organization_subscriptions (
    id, organization_id, established_at, initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values (pg_temp.id('f', 2), pg_temp.id('3', 2), '2020-01-01Z', 'ACTIVE', '2020-01-01Z', null, null,
          'pending-test', pg_temp.id('f', 92));
set local session_replication_role = origin;
select pg_temp.act(17);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 11), 50) = array['d21:REQUEST_DECISION:ACTION_REQUIRED:2'],
    'Pending: with the Entitlement the request can be confirmed'
);
-- With the Entitlement, B2's request with an Encounter (d42) becomes
-- decidable by confirmation; the rest is unchanged.
select pg_temp.assert_true(
    pg_temp.pending_walk(pg_temp.id('4', 12), 3) = array[
        'd42:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd43:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd41:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd44:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd45:GUARDIAN_PROPOSAL:INFORMATIONAL:4'
    ]
    and pg_temp.pending_totals_walk(pg_temp.id('4', 12), 3) = array['4/0/1']
    and pg_temp.summary(pg_temp.id('4', 12)) = '4/0/1',
    'Equivalence: with the Entitlement, B2 adds the confirmable request'
);
reset role;
select pg_temp.assert_true(
    pg_temp.assert_equivalent('OrgB Entitlement') >= 10,
    'Equivalence: after OrgB gains the Entitlement'
);

-- ===========================================================================
-- 5. Feasibility decides rank, order and page membership (BR-57).
-- ===========================================================================

-- Before: d09's alternative is feasible, so d09 is the last row (rank 5) and
-- not on a first page of 9.
select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(
    not exists (select 1 from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 9)
                where id = pg_temp.id('d', 9)),
    'Feasibility: a feasible Clinic proposal is ranked after every actionable row'
);
reset role;

-- A CLOSED exception on 2035-05-11 makes d09's alternative infeasible: it
-- becomes actionable (withdraw), moves to rank 3 before d10 (earlier start),
-- enters the first page of 9, and the counts follow.
set local session_replication_role = replica;
insert into public.clinic_appointment_availability_exceptions (clinic_id, local_date, exception_kind)
values (pg_temp.a1(), '2035-05-11', 'CLOSED');
set local session_replication_role = origin;

select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending(4) = array[
        'd03:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd01:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd02:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd13:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd04:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd05:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd12:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd09:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd10:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd11:GUARDIAN_PROPOSAL:INFORMATIONAL:4',
        'd08:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5'
    ]
    and exists (select 1 from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 9)
                where id = pg_temp.id('d', 9) and pending_rank = 3)
    and pg_temp.summary() = '9/1/1'
    and pg_temp.pending_totals_walk(pg_temp.a1(), 4) = array['9/1/1'],
    'Feasibility: an infeasible Clinic proposal moves to rank 3, into the first page, and into the totals'
);
reset role;
select pg_temp.assert_true(
    pg_temp.assert_equivalent('A1 CLOSED exception') >= 10,
    'Equivalence: with a feasibility change'
);

set local session_replication_role = replica;
delete from public.clinic_appointment_availability_exceptions where clinic_id = pg_temp.a1();
set local session_replication_role = origin;

-- ===========================================================================
-- 6. Keyset pages with changes between pages (BR-57).
-- ===========================================================================

create temporary table pending_pages (page integer, entry text, appointment_id uuid) on commit drop;
grant select, insert on pending_pages to authenticated;

select pg_temp.act(10);
set local role authenticated;
insert into pending_pages
select 1, pg_temp.label(pending_row.id) || ':' || pending_row.pending_rank, pending_row.id
from public.get_clinic_appointment_pending(pg_temp.a1(), p_limit => 3) as pending_row;
reset role;

select pg_temp.assert_true(
    (select array_agg(entry order by entry) from pending_pages where page = 1) = array['d01:1', 'd02:1', 'd03:1'],
    'Pages: the first page of 3 is d03, d01, d02'
);

-- Between pages: d01 (already read) is completed, d13 (not yet read) is
-- completed, d05 (not yet read) is cancelled, and a new reached CONFIRMED
-- visit d23 appears before the cursor. (Fixture changes, not the workflows.)
set local session_replication_role = replica;
update public.appointments set lifecycle_state = 'COMPLETED' where id in (pg_temp.id('d', 1), pg_temp.id('d', 13));
update public.appointments set lifecycle_state = 'CANCELLED' where id = pg_temp.id('d', 5);
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
values (pg_temp.id('d', 23), pg_temp.id('9', 1), pg_temp.a1(), pg_temp.id('2', 1), 'Check-up', 'CONFIRMED', '2025-01-01Z');
insert into public.appointment_schedule_revisions (
    appointment_id, revision_sequence, revision_context, scheduled_start_at, scheduled_end_at,
    establishment_timezone_name, established_by_user_id, created_at
) values (pg_temp.id('d', 23), 1, 'CONFIRMED', '2026-01-01T09:00:00Z', '2026-01-01T09:30:00Z',
          'Europe/Madrid', pg_temp.id('2', 1), '2025-01-01Z');
set local session_replication_role = origin;

-- Continue from the last row of page 1 (d02, rank 1).
select pg_temp.act(10);
set local role authenticated;
insert into pending_pages
select 2, pg_temp.label(pending_row.id) || ':' || pending_row.pending_rank, pending_row.id
from public.get_clinic_appointment_pending(
    pg_temp.a1(), 1,
    (select current_scheduled_start_at from public.get_clinic_appointment(pg_temp.a1(), pg_temp.id('d', 2))),
    pg_temp.id('d', 2), 100
) as pending_row;
reset role;

select pg_temp.assert_true(
    (select array_agg(entry order by entry) from pending_pages where page = 2)
    = array['d04:2', 'd08:5', 'd09:5', 'd10:3', 'd11:4', 'd12:2'],
    'Pages: after changes, page 2 continues from the cursor — completed and cancelled rows leave, '
    'an earlier new row is not inserted behind the cursor'
);

select pg_temp.assert_true(
    (select count(*) = count(distinct appointment_id) from pending_pages),
    'Pages: no Appointment is returned twice across pages'
);

-- A fresh first read reflects the new state, including d23 first.
select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.pending(2) = array[
        'd23:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd03:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd02:ATTENDANCE_OUTCOME:ACTION_REQUIRED:1',
        'd04:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd12:REQUEST_DECISION:ACTION_REQUIRED:2',
        'd10:PROPOSAL_NOT_FEASIBLE:ACTION_REQUIRED:3',
        'd11:GUARDIAN_PROPOSAL:INFORMATIONAL:4',
        'd08:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5',
        'd09:AWAITING_GUARDIAN:AWAITING_GUARDIAN:5'
    ]
    and pg_temp.summary() = '6/2/1'
    and pg_temp.pending_totals_walk(pg_temp.a1(), 2) = array['6/2/1'],
    'Pages: a new first read, its totals and the summary reflect the current state'
);

-- A cursor naming a row that no longer exists (d05, now CANCELLED) still
-- continues strictly after its position.
select pg_temp.assert_true(
    (select array_agg(pg_temp.label(pending_row.id) order by pending_row.ordinality)
     from public.get_clinic_appointment_pending(pg_temp.a1(), 2, '2035-05-01T08:00:00Z', pg_temp.id('d', 5), 2)
          with ordinality as pending_row) = array['d12', 'd10'],
    'Pages: a cursor of a vanished row continues after its key'
);

-- A cursor beyond every row returns an empty page: it carries no totals
-- although they are not zero; the summary still reports them.
select pg_temp.assert_true(
    not exists (
        select 1 from public.get_clinic_appointment_pending(pg_temp.a1(), 5, 'infinity', pg_temp.id('d', 99), 50)
    )
    and pg_temp.summary() = '6/2/1',
    'Pages: a cursor past the last row returns no rows; the summary keeps the non-zero totals'
);
reset role;
select pg_temp.assert_true(
    pg_temp.assert_equivalent('after changes between pages') >= 10,
    'Equivalence: after Appointments changed between pages'
);

-- ===========================================================================
-- 7. History (BR-59).
-- ===========================================================================

-- After section 6, d01 and d13 are COMPLETED (starts 2026-01-10 and
-- 2026-01-20) and d05 is CANCELLED (2035): they are History now.
select pg_temp.act(10);
set local role authenticated;

-- Descending (start, id): d05 (2035-05-01), d13 (2026-01-20), d01
-- (2026-01-10), d19 (06-10 22:30Z), d18 (21:30Z), the 10:00 tie d16, d15, d14
-- by id descending, then d17 EXPIRED (06-09). d22 is A2's.
select pg_temp.assert_true(
    pg_temp.history(size) = array['d05', 'd13', 'd01', 'd19', 'd18', 'd16', 'd15', 'd14', 'd17'],
    'History: pages of ' || size || ' return every terminal Appointment once, in (start, id) descending order'
)
from unnest(array[1, 2, 3, 4, 8, 9, 30, 50]) as size;

-- Deep cursor inside the tie: after d16 comes d15, d14, d17.
select pg_temp.assert_true(
    (select array_agg(pg_temp.label(history_row.id) order by history_row.ordinality)
     from public.get_clinic_appointment_history(pg_temp.a1(), '2025-06-10T08:00:00Z', pg_temp.id('d', 16), 30)
          with ordinality as history_row) = array['d15', 'd14', 'd17'],
    'History: a cursor inside a tie continues with the lower ids, then earlier starts'
);

select pg_temp.assert_true(
    not exists (
        select 1 from public.get_clinic_appointment_history(pg_temp.a1(), '2025-06-09T08:00:00Z', pg_temp.id('d', 17), 30)
    )
    and not exists (
        select 1 from public.get_clinic_appointment_history(pg_temp.a1(), '2000-01-01Z', pg_temp.id('d', 99), 30)
    ),
    'History: a cursor at or before the oldest row returns no rows'
);

select pg_temp.assert_true(
    not exists (
        select 1
        from public.get_clinic_appointment_history(pg_temp.a1(), p_limit => 50) as history_row
        where to_jsonb(history_row) is distinct from (
            select to_jsonb(single_row) from public.get_clinic_appointment(pg_temp.a1(), history_row.id) as single_row
        )
           or history_row.lifecycle_state not in ('COMPLETED', 'NO_SHOW', 'CANCELLED', 'EXPIRED')
    )
    and (select cancellation_reason = 'Clinic closed that day'
         from public.get_clinic_appointment_history(pg_temp.a1(), p_limit => 50) where id = pg_temp.id('d', 16)),
    'History: rows equal get_clinic_appointment, terminal states only, cancellation reason projected'
);
reset role;

-- An Appointment becoming terminal while paging: one later than the cursor
-- never appears behind it; one earlier appears in its place.
create temporary table history_page_one (id uuid, current_scheduled_start_at timestamptz) on commit drop;
grant select, insert on history_page_one to authenticated;
select pg_temp.act(10);
set local role authenticated;
insert into history_page_one
select history_row.id, history_row.current_scheduled_start_at
from public.get_clinic_appointment_history(pg_temp.a1(), p_limit => 4) as history_row;
reset role;

set local session_replication_role = replica;
update public.appointments set lifecycle_state = 'EXPIRED' where id = pg_temp.id('d', 4);  -- 2035
update public.appointments set lifecycle_state = 'EXPIRED' where id = pg_temp.id('d', 6);  -- 2026-01-15
set local session_replication_role = origin;

select pg_temp.act(10);
set local role authenticated;
select pg_temp.assert_true(
    (select array_agg(pg_temp.label(id) order by current_scheduled_start_at desc, id desc) from history_page_one)
        = array['d05', 'd13', 'd01', 'd19']
    and (select array_agg(pg_temp.label(history_row.id) order by history_row.ordinality)
         from public.get_clinic_appointment_history(pg_temp.a1(), '2025-06-10T22:30:00Z', pg_temp.id('d', 19), 30)
              with ordinality as history_row) = array['d18', 'd16', 'd15', 'd14', 'd17']
    -- d04 shares d05's start and follows it by id.
    and pg_temp.history(4) = array['d05', 'd04', 'd13', 'd06', 'd01', 'd19', 'd18', 'd16', 'd15', 'd14', 'd17'],
    'History: continuing from the cursor is stable; a fresh read includes newly terminal Appointments'
);
reset role;

-- Veterinarians and Organization-wide actors read the History; A2's is its own.
select pg_temp.act(11);
set local role authenticated;
select pg_temp.assert_true(
    (select count(*) = 11 from public.get_clinic_appointment_history(pg_temp.a1(), p_limit => 50)),
    'History: a Veterinarian with a current Assignment reads it'
);
reset role;
select pg_temp.act(6);
set local role authenticated;
select pg_temp.assert_true(
    (select array_agg(pg_temp.label(id)) from public.get_clinic_appointment_history(pg_temp.id('4', 2))) = array['d22'],
    'History: A2 shows only its own Appointments'
);
reset role;

-- ===========================================================================
-- 8. Reads create or change nothing.
-- ===========================================================================

select pg_temp.assert_true(
    (select baseline.communications = (select count(*) from public.transactional_communications)
            and baseline.audit_events = (select count(*) from public.medical_access_audit_events)
            and baseline.lifecycle_events = (select count(*) from public.appointment_lifecycle_events)
            and baseline.revisions + 1 = (select count(*) from public.appointment_schedule_revisions)
            and baseline.proposals = (select count(*) from public.appointment_reschedule_proposals)
     from side_effect_baseline as baseline),
    'Side effects: no Communication, Medical Access Audit Event, Lifecycle Event, Revision or Proposal '
    '(beyond the one fixture revision)'
);

rollback;

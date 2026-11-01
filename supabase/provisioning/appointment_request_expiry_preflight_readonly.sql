-- ============================================================================
-- MenizVet — REQUESTED Appointment pending-request / expiry preflight (READ-ONLY)
--
-- Protects: 20261004090000_appointment_request_expiry_and_pending_policy.sql
-- and the later activation of the expiry scheduler
-- (appointment_request_expiry_scheduler.sql). Run it twice:
--   1. before `supabase db push` while 20261004090000 is pending
--      (PRODUCTION_DEPLOYMENT.md §21.2 gate: zero conflicting pending requests);
--   2. again immediately before provisioning the expiry scheduler.
--
-- * Strictly read-only: one SELECT inside a READ ONLY transaction that is
--   rolled back. It never calls expire_lapsed_appointment_requests, never
--   cancels, confirms or transitions anything, and creates no object.
--   Rerunning it is harmless.
-- * Uses only tables and columns present since the Production baseline
--   (20260921170000), so it runs before and after 20261004090000. pg_cron and
--   the migration ledger are read only when present.
-- * Definitions follow SPEC-APT-001 BR-35 and SPEC-APT-015 BR-4/BR-17:
--   a pending request is REQUESTED with its latest REQUESTED Schedule
--   Revision start strictly after the check time; a REQUESTED Appointment
--   whose latest requested start has passed is logically expired (it never
--   blocks a request and is materialized as EXPIRED by the scheduler).
--   Requests at another Clinic, for another Pet, CONFIRMED and terminal
--   Appointments are never duplicates. No stricter rule is applied.
-- * Reports opaque Appointment ids only; no names, reasons, notes or
--   clinical content.
--
-- Run:
--   psql "<connection>" -v ON_ERROR_STOP=1 -f supabase/provisioning/appointment_request_expiry_preflight_readonly.sql
--   Supabase SQL Editor: paste the whole file. If the editor shows only the
--   ROLLBACK result, select the single SELECT statement and run the
--   selection: it is read-only by itself.
--
-- Result: one row per check, ordered BLOCK, WARN, INFO, PASS, then
-- EXP_SUMMARY:
--   BLOCK -> STOP (before the migration: do not db push; before the
--            scheduler: do not provision it). Resolve only through normal
--            product workflows or an explicit decision; never edit rows.
--   WARN  -> investigate before proceeding.
--   INFO / PASS -> nothing to do.
-- Interpretation: docs/PRODUCTION_DEPLOYMENT.md §22.
-- ============================================================================

begin transaction read only;

set local statement_timeout = '120s';

with stage as (
    select
        statement_timestamp() as checked_at,
        to_regprocedure('public.expire_lapsed_appointment_requests(timestamptz)') is not null
            as expiry_operation_present,
        case
            when to_regclass('supabase_migrations.schema_migrations') is null then null
            else (xpath('/row/n/text()', query_to_xml(
                $q$select count(*) as n from supabase_migrations.schema_migrations
                   where version = '20261004090000'$q$, false, true, '')))[1]::text::integer > 0
        end as migration_recorded,
        exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') as pg_cron_installed,
        case
            when to_regclass('cron.job') is null then null
            else (xpath('/row/n/text()', query_to_xml(
                $q$select count(*) as n from cron.job
                   where jobname = 'petcare-appointment-request-expiry-v1'$q$, false, true, '')))[1]::text::integer
        end as expiry_job_count
),
requested as (
    select
        appointment.id,
        appointment.pet_id,
        appointment.clinic_id,
        latest.scheduled_start_at as latest_requested_start_at,
        care_auth.id as care_authorization_id,
        care_auth.lifecycle_state as care_authorization_state,
        care_auth.granted_at as care_authorization_granted_at
    from public.appointments as appointment
    left join lateral (
        select revision.scheduled_start_at
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
          and revision.revision_context = 'REQUESTED'
        order by revision.revision_sequence desc
        limit 1
    ) as latest on true
    left join public.care_authorizations as care_auth
      on care_auth.appointment_id = appointment.id
    where appointment.lifecycle_state = 'REQUESTED'
),
classified_requests as (
    select
        requested.*,
        requested.latest_requested_start_at > (select checked_at from stage) as is_pending,
        requested.latest_requested_start_at <= (select checked_at from stage) as is_lapsed
    from requested
),
pet_clinic_groups as (
    select
        pet_id,
        clinic_id,
        count(*) filter (where is_pending) as pending_count,
        count(*) as requested_count,
        array_agg(id order by id) filter (where is_pending) as pending_ids
    from classified_requests
    group by pet_id, clinic_id
),
checks as (
    -- B01: the documented operational gate (SPEC-APT-001 BR-35 at rest).
    select 'EXP_B01_CONFLICTING_PENDING_REQUESTS' as check_code, 'BLOCK' as on_finding,
        count(pending_id) as affected_count,
        (array_agg(pending_id order by pending_id))[1:20] as sample_ids,
        count(distinct (pet_clinic_groups.pet_id, pet_clinic_groups.clinic_id))
            || ' Pet+Clinic pair(s) with more than one pending (future) REQUESTED Appointment.' as detail
    from pet_clinic_groups
    left join lateral unnest(pet_clinic_groups.pending_ids) as pending_id on true
    where pet_clinic_groups.pending_count > 1

    union all
    -- B02..B06: rows the expiry operation cannot materialize. One failing
    -- candidate aborts the whole expire_lapsed_appointment_requests run, so
    -- every scheduler run would fail. Impossible through supported workflows.
    select 'EXP_B02_REQUESTED_WITHOUT_CARE_AUTHORIZATION', 'BLOCK', count(*),
        (array_agg(id order by id))[1:20],
        'REQUESTED Appointment with no Appointment-derived Care Authorization (expiry raises 23514).'
    from classified_requests
    where care_authorization_id is null

    union all
    select 'EXP_B03_REQUESTED_WITH_CLINICAL_ENCOUNTER', 'BLOCK', count(*),
        (array_agg(classified_requests.id order by classified_requests.id))[1:20],
        'REQUESTED Appointment with a Clinical Encounter (EXPIRED cannot coexist with an Encounter).'
    from classified_requests
    where exists (
        select 1 from public.clinical_encounters as encounter_row
        where encounter_row.appointment_id = classified_requests.id
    )

    union all
    select 'EXP_B04_REQUESTED_WITH_CONFIRMED_REVISION_OR_EVENTS', 'BLOCK', count(*),
        (array_agg(classified_requests.id order by classified_requests.id))[1:20],
        'REQUESTED Appointment with a CONFIRMED Schedule Revision or any Lifecycle Event (incoherent history).'
    from classified_requests
    where exists (
        select 1 from public.appointment_schedule_revisions as revision
        where revision.appointment_id = classified_requests.id
          and revision.revision_context = 'CONFIRMED'
    )
       or exists (
        select 1 from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = classified_requests.id
    )

    union all
    select 'EXP_B05_REQUESTED_WITHOUT_INITIAL_REQUESTED_REVISION', 'BLOCK', count(*),
        (array_agg(classified_requests.id order by classified_requests.id))[1:20],
        'REQUESTED Appointment without exactly one initial REQUESTED revision (sequence 1); it can never expire coherently.'
    from classified_requests
    where classified_requests.latest_requested_start_at is null
       or (
        select count(*) from public.appointment_schedule_revisions as revision
        where revision.appointment_id = classified_requests.id
          and revision.revision_context = 'REQUESTED'
          and revision.revision_sequence = 1
       ) <> 1

    union all
    select 'EXP_B06_ACTIVE_AUTHORIZATION_GRANTED_AFTER_EXPIRY_INSTANT', 'BLOCK', count(*),
        (array_agg(id order by id))[1:20],
        'ACTIVE Care Authorization granted after the logical expiry instant (ended_at >= granted_at would fail).'
    from classified_requests
    where care_authorization_state = 'ACTIVE'
      and care_authorization_granted_at > latest_requested_start_at

    union all
    -- B07: a provisioned job before the expiry operation exists fails every run.
    select 'EXP_B07_SCHEDULER_WITHOUT_EXPIRY_OPERATION', 'BLOCK',
        case when coalesce(stage.expiry_job_count, 0) > 0 and not stage.expiry_operation_present
             then stage.expiry_job_count else 0 end,
        null::uuid[],
        'Expiry cron job provisioned while expire_lapsed_appointment_requests does not exist.'
    from stage

    union all
    -- W01: the scheduler is already provisioned; SPEC-APT-015 §7 requires
    -- that every client app in use can parse and present EXPIRED.
    select 'EXP_W01_SCHEDULER_ALREADY_PROVISIONED', 'WARN',
        case when coalesce(stage.expiry_job_count, 0) > 0 and stage.expiry_operation_present
             then stage.expiry_job_count else 0 end,
        null::uuid[],
        'petcare-appointment-request-expiry-v1 already exists: confirm it was intended and that the installed app understands EXPIRED.'
    from stage

    union all
    select 'EXP_W02_MIGRATION_HISTORY_SCHEMA_MISMATCH', 'WARN',
        case when stage.migration_recorded is not null
                  and stage.migration_recorded <> stage.expiry_operation_present then 1 else 0 end,
        null::uuid[],
        'supabase_migrations.schema_migrations and the expiry operation disagree about 20261004090000.'
    from stage

    union all
    select 'EXP_I01_PENDING_REQUESTS', 'INFO', count(*), null::uuid[],
        'Future REQUESTED Appointments (pending); unaffected by expiry until their requested start.'
    from classified_requests
    where is_pending

    union all
    select 'EXP_I02_LAPSED_REQUESTS_TO_EXPIRE', 'INFO', count(*), null::uuid[],
        'Logically expired REQUESTED Appointments (SPEC-APT-015 BR-17): the first scheduler run materializes EXPIRED; '
        || count(*) filter (where care_authorization_state = 'ACTIVE')
        || ' ACTIVE Care Authorization(s) end with APPOINTMENT_EXPIRED; no Communication.'
    from classified_requests
    where is_lapsed

    union all
    select 'EXP_I03_ACCEPTABLE_HISTORICAL_REQUEST_GROUPS', 'INFO', count(*), null::uuid[],
        'Pet+Clinic pairs with several REQUESTED Appointments but at most one pending: allowed (lapsed requests never block, BR-35).'
    from pet_clinic_groups
    where requested_count > 1 and pending_count <= 1

    union all
    select 'EXP_I04_TERMINAL_OR_CONFIRMED_APPOINTMENTS', 'INFO', count(*), null::uuid[],
        coalesce((select string_agg(lifecycle_state || '=' || n, ', ' order by lifecycle_state)
                  from (select appointment.lifecycle_state, count(*) as n
                        from public.appointments as appointment
                        where appointment.lifecycle_state <> 'REQUESTED'
                        group by appointment.lifecycle_state) as by_state), 'None.')
        || ' (never duplicates; no action).'
    from public.appointments as appointment
    where appointment.lifecycle_state <> 'REQUESTED'
),
classified as (
    select
        checks.check_code,
        case
            when checks.on_finding = 'INFO' then 'INFO'
            when checks.affected_count > 0 then checks.on_finding
            else 'PASS'
        end as result,
        checks.affected_count,
        checks.sample_ids,
        checks.detail
    from checks
)
select check_code, result, affected_count, sample_ids, detail
from (
    select classified.*, 1 as section from classified
    union all
    select
        'EXP_SUMMARY',
        case
            when bool_or(classified.result = 'BLOCK') then 'BLOCK'
            when bool_or(classified.result = 'WARN') then 'WARN'
            else 'PASS'
        end,
        count(*) filter (where classified.result in ('BLOCK', 'WARN')),
        null::uuid[],
        'Stage: ' || case when (select expiry_operation_present from stage)
                          then '20261004090000 applied' else '20261004090000 pending' end
        || '; recorded: ' || coalesce((select migration_recorded from stage)::text, 'unknown')
        || '; pg_cron: ' || (select pg_cron_installed from stage)::text
        || '; expiry job: ' || coalesce((select expiry_job_count from stage)::text, 'n/a')
        || '; checked at ' || (select checked_at from stage)::text
        || '. Scheduler gate not checkable in SQL: the installed app must understand EXPIRED (SPEC-APT-015 §7).',
        2
    from classified
) as report
order by section,
    case result when 'BLOCK' then 1 when 'WARN' then 2 when 'INFO' then 3 when 'PASS' then 4 else 5 end,
    check_code;

rollback;

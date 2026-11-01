-- ============================================================================
-- MenizVet — Reschedule Proposal normalization preflight (READ-ONLY)
--
-- Protects: 20261009090000_reschedule_proposal_normalization.sql (and the
-- CONFIRMED-base guard of 20261010090000_requested_appointment_alternative_time.sql).
-- Run BEFORE `supabase db push` in any environment where 20261009090000 is
-- still pending (Production baseline: 20260921170000).
--
-- * Strictly read-only: one SELECT inside a READ ONLY transaction that is
--   rolled back. No table, function, temporary object, RPC or state change.
--   Rerunning it is harmless.
-- * Compatible with every pre-normalization schema: the Production baseline
--   (before 20261008090000, no withdrawal columns) and DEVELOPMENT-like
--   databases that already have 20261008090000. Columns that exist only in
--   some stages are read through to_jsonb(row), so the script never fails to
--   parse. On an already normalized schema every check reports NOT_APPLICABLE.
-- * Mirrors the migration's own guard (section A) and postflight, plus the
--   constraints the migration adds, so a BLOCK here predicts an aborted
--   migration (the migration is transactional and aborts cleanly, but a
--   mid-`db push` abort leaves the earlier pending migrations applied).
-- * Reports opaque Proposal / Schedule Revision / Appointment ids only; no
--   names, reasons, notes or clinical content.
--
-- Run:
--   psql "<connection>" -v ON_ERROR_STOP=1 -f supabase/provisioning/reschedule_proposal_normalization_preflight_readonly.sql
--   Supabase SQL Editor: paste the whole file. If the editor shows only the
--   ROLLBACK result, select the single SELECT statement and run the
--   selection: it is read-only by itself.
--
-- Result: one row per check, ordered BLOCK, WARN, INFO, PASS, NOT_APPLICABLE,
-- then RSN_SUMMARY with the overall result:
--   BLOCK          -> STOP. Do not run db push. Investigate as an explicit
--                     decision; never correct rows by hand.
--   WARN           -> the migration will succeed, but it changes existing
--                     rows in a way the operator must acknowledge.
--   INFO / PASS    -> nothing to do.
--   NOT_APPLICABLE -> already normalized; nothing to check.
-- Interpretation: docs/PRODUCTION_DEPLOYMENT.md §22.
-- ============================================================================

begin transaction read only;

set local statement_timeout = '120s';

with stage as (
    select
        exists (
            select 1 from pg_catalog.pg_attribute as attribute
            where attribute.attrelid = 'public.appointment_reschedule_proposals'::regclass
              and attribute.attname = 'base_revision_context'
              and not attribute.attisdropped
        ) as normalized,
        exists (
            select 1 from pg_catalog.pg_attribute as attribute
            where attribute.attrelid = 'public.appointment_reschedule_proposals'::regclass
              and attribute.attname = 'withdrawn_at'
              and not attribute.attisdropped
        ) as has_withdrawal,
        case
            when to_regclass('supabase_migrations.schema_migrations') is null then null
            else (xpath('/row/n/text()', query_to_xml(
                $q$select count(*) as n from supabase_migrations.schema_migrations
                   where version = '20261009090000'$q$, false, true, '')))[1]::text::integer > 0
        end as migration_recorded,
        statement_timestamp() as checked_at
),
proposal as (
    select
        row_source.id,
        row_source.appointment_id,
        row_source.base_revision_id,
        row_source.proposed_start_at,
        row_source.proposed_end_at,
        row_source.proposed_timezone_name,
        row_source.proposing_context,
        row_source.state,
        row_source.created_at,
        (row_json.j ->> 'accepted_at')::timestamptz as accepted_at,
        (row_json.j ->> 'accepted_by_user_id')::uuid as accepted_by_user_id,
        row_json.j ->> 'accepting_context' as accepting_context,
        (row_json.j ->> 'resulting_confirmed_revision_id')::uuid as resulting_confirmed_revision_id,
        (row_json.j ->> 'non_actionable_at')::timestamptz as non_actionable_at,
        row_json.j ->> 'non_actionable_reason' as non_actionable_reason,
        (row_json.j ->> 'withdrawn_at')::timestamptz as withdrawn_at,
        (row_json.j ->> 'withdrawn_by_user_id')::uuid as withdrawn_by_user_id
    from public.appointment_reschedule_proposals as row_source
    cross join lateral (select to_jsonb(row_source.*) as j) as row_json
    where not (select normalized from stage)
),
-- Open PENDING rows (no recorded non-actionable fact) and the first
-- applicable reason the migration would use to make them VOID now.
open_pending as (
    select
        proposal.id,
        proposal.appointment_id,
        proposal.proposing_context,
        proposal.proposed_start_at,
        base_revision.scheduled_start_at as base_start_at,
        case
            when exists (
                select 1 from public.appointment_schedule_revisions as later_revision
                where later_revision.appointment_id = proposal.appointment_id
                  and later_revision.revision_sequence > base_revision.revision_sequence
            ) then 'BASE_REVISION_SUPERSEDED'
            when appointment.lifecycle_state <> base_revision.revision_context
                then 'APPOINTMENT_LIFECYCLE_CHANGED'
            when exists (
                select 1 from public.clinical_encounters as encounter_row
                where encounter_row.appointment_id = proposal.appointment_id
            ) then 'CLINICAL_ENCOUNTER_STARTED'
        end as void_reason_at_migration
    from proposal
    join public.appointments as appointment
      on appointment.id = proposal.appointment_id
    join public.appointment_schedule_revisions as base_revision
      on base_revision.id = proposal.base_revision_id
    where proposal.state = 'PENDING'
      and proposal.non_actionable_at is null
),
checks as (
    -- B01: migration guard 1 (also 20261010090000 guard A).
    select 'RSN_B01_BASE_REVISION_FOREIGN_OR_NOT_CONFIRMED' as check_code, 'BLOCK' as on_finding,
        count(*) as affected_count,
        (array_agg(proposal.id order by proposal.id))[1:20] as sample_ids,
        'Proposal base revision missing, of another Appointment, or not CONFIRMED (guard 1).' as detail
    from proposal
    left join public.appointment_schedule_revisions as base_revision
      on base_revision.id = proposal.base_revision_id
    where base_revision.id is null
       or base_revision.appointment_id <> proposal.appointment_id
       or base_revision.revision_context <> 'CONFIRMED'

    union all
    -- B02: migration guard 2 (acceptance facts equal the resulting revision).
    select 'RSN_B02_ACCEPTED_FACTS_DISAGREE', 'BLOCK', count(*),
        (array_agg(proposal.id order by proposal.id))[1:20],
        'ACCEPTED Proposal whose acceptance facts disagree with its resulting revision (guard 2).'
    from proposal
    left join public.appointment_schedule_revisions as resulting_revision
      on resulting_revision.id = proposal.resulting_confirmed_revision_id
    left join public.appointment_schedule_revisions as base_revision
      on base_revision.id = proposal.base_revision_id
    where proposal.state = 'ACCEPTED'
      and (
          resulting_revision.id is null
          or base_revision.id is null
          or resulting_revision.source_proposal_id is distinct from proposal.id
          or resulting_revision.appointment_id <> proposal.appointment_id
          or resulting_revision.revision_context <> 'CONFIRMED'
          or resulting_revision.created_at is distinct from proposal.accepted_at
          or resulting_revision.established_by_user_id is distinct from proposal.accepted_by_user_id
          or proposal.accepting_context is distinct from
             case proposal.proposing_context when 'GUARDIAN' then 'CLINIC' else 'GUARDIAN' end
          or resulting_revision.revision_sequence <> base_revision.revision_sequence + 1
          or resulting_revision.scheduled_start_at <> proposal.proposed_start_at
          or resulting_revision.scheduled_end_at <> proposal.proposed_end_at
          or resulting_revision.establishment_timezone_name <> proposal.proposed_timezone_name
      )

    union all
    -- B03: migration guard 3 (every sourced revision has its ACCEPTED Proposal).
    select 'RSN_B03_SOURCED_REVISION_UNMATCHED', 'BLOCK', count(*),
        (array_agg(revision.id order by revision.id))[1:20],
        'Schedule Revision with source_proposal_id not matched by an ACCEPTED Proposal naming it (guard 3); ids are revision ids.'
    from public.appointment_schedule_revisions as revision
    left join proposal
      on proposal.id = revision.source_proposal_id
    where not (select normalized from stage)
      and revision.source_proposal_id is not null
      and (
          proposal.id is null
          or proposal.state <> 'ACCEPTED'
          or proposal.resulting_confirmed_revision_id is distinct from revision.id
      )

    union all
    -- B04: migration guard 4, made null-safe, plus the VOID shape the
    -- recorded facts are copied into (void_shape / void_reason / voided_at).
    select 'RSN_B04_NON_ACTIONABLE_FACT_SHAPE', 'BLOCK', count(*),
        (array_agg(proposal.id order by proposal.id))[1:20],
        'Recorded non-actionable fact on a non-PENDING row, with an unknown or missing reason, or before created_at (guard 4).'
    from proposal
    where (proposal.non_actionable_at is not null or proposal.non_actionable_reason is not null)
      and (
          proposal.state <> 'PENDING'
          or proposal.non_actionable_at is null
          or proposal.non_actionable_reason is null
          or proposal.non_actionable_reason not in (
              'BASE_REVISION_SUPERSEDED', 'PROPOSED_TIME_PASSED', 'PROPOSING_AUTHORITY_LOST'
          )
          or proposal.non_actionable_at < proposal.created_at
      )

    union all
    -- B05: migration guard 5 (VOID observed now must not precede created_at).
    select 'RSN_B05_PENDING_CREATED_IN_FUTURE', 'BLOCK', count(*),
        (array_agg(proposal.id order by proposal.id))[1:20],
        'PENDING Proposal created after the check time (guard 5).'
    from proposal
    where proposal.state = 'PENDING'
      and proposal.created_at > (select checked_at from stage)

    union all
    -- B06: migration postflight 1 (one PENDING per Appointment after the
    -- transformation).
    select 'RSN_B06_MULTIPLE_PENDING_AFTER_NORMALIZATION', 'BLOCK', count(*),
        (array_agg(duplicated.appointment_id order by duplicated.appointment_id))[1:20],
        'Appointment that would keep more than one PENDING Proposal (postflight 1); ids are Appointment ids.'
    from (
        select open_pending.appointment_id
        from open_pending
        where open_pending.void_reason_at_migration is null
        group by open_pending.appointment_id
        having count(*) > 1
    ) as duplicated

    union all
    -- B07: the rebuilt state CHECK and the WITHDRAWN shape CHECK.
    select 'RSN_B07_STATE_OR_WITHDRAWAL_SHAPE', 'BLOCK', count(*),
        (array_agg(proposal.id order by proposal.id))[1:20],
        'Unknown state, or WITHDRAWN facts inconsistent with the state (rebuilt CHECKs).'
    from proposal
    where proposal.state not in ('PENDING', 'ACCEPTED', 'WITHDRAWN')
       or (proposal.state = 'WITHDRAWN') <> (proposal.withdrawn_at is not null)
       or (proposal.withdrawn_at is null) <> (proposal.withdrawn_by_user_id is null)
       or (proposal.state = 'WITHDRAWN' and not (select has_withdrawal from stage))

    union all
    -- B08: migration history and schema must agree.
    select 'RSN_B08_MIGRATION_HISTORY_SCHEMA_MISMATCH', 'BLOCK',
        case when stage.migration_recorded is not null
                  and stage.migration_recorded <> stage.normalized then 1 else 0 end,
        null::uuid[],
        'supabase_migrations.schema_migrations and the Proposal columns disagree about 20261009090000.'
    from stage

    union all
    -- W01: open PENDING rows the migration makes VOID with voided_at = the
    -- migration instant (acknowledge; expected behaviour).
    select 'RSN_W01_OPEN_PENDING_VOIDED_AT_MIGRATION', 'WARN', count(*),
        (array_agg(open_pending.id order by open_pending.id))[1:20],
        coalesce('Becomes VOID observed at migration time: ' || string_agg(distinct open_pending.void_reason_at_migration, ', '), 'None.')
    from open_pending
    where open_pending.void_reason_at_migration is not null

    union all
    select 'RSN_I01_PROPOSALS_BY_STATE', 'INFO', count(*), null::uuid[],
        coalesce((select string_agg(state || '=' || n, ', ' order by state)
                  from (select proposal.state, count(*) as n from proposal group by proposal.state) as by_state), 'No Proposals.')
    from proposal

    union all
    select 'RSN_I02_RECORDED_NON_ACTIONABLE_TO_VOID', 'INFO', count(*), null::uuid[],
        'PENDING with a recorded non-actionable fact: becomes VOID keeping its recorded reason and time.'
    from proposal
    where proposal.state = 'PENDING' and proposal.non_actionable_at is not null

    union all
    select 'RSN_I03_OPEN_PENDING_REMAINING', 'INFO', count(*), null::uuid[],
        'Stays PENDING; ' || count(*) filter (
            where open_pending.proposed_start_at <= (select checked_at from stage)
               or open_pending.base_start_at <= (select checked_at from stage)
        ) || ' already lapsed (derived, not stored; shown as not actionable). Guardian-originated: '
        || count(*) filter (where open_pending.proposing_context = 'GUARDIAN') || '.'
    from open_pending
    where open_pending.void_reason_at_migration is null
),
classified as (
    select
        checks.check_code,
        case
            when (select normalized from stage) and checks.check_code <> 'RSN_B08_MIGRATION_HISTORY_SCHEMA_MISMATCH'
                then 'NOT_APPLICABLE'
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
        'RSN_SUMMARY',
        case
            when bool_or(classified.result = 'BLOCK') then 'BLOCK'
            when bool_or(classified.result = 'WARN') then 'WARN'
            when (select normalized from stage) then 'NOT_APPLICABLE'
            else 'PASS'
        end,
        count(*) filter (where classified.result in ('BLOCK', 'WARN')),
        null::uuid[],
        'Stage: ' || case
            when (select normalized from stage) then 'ALREADY_NORMALIZED'
            when (select has_withdrawal from stage) then 'PRE_NORMALIZATION (20261008090000 present)'
            else 'PRE_20261008090000 (Production baseline shape)'
        end || '; 20261009090000 recorded: ' || coalesce((select migration_recorded from stage)::text, 'unknown')
        || '; checked at ' || (select checked_at from stage)::text,
        2
    from classified
) as report
order by section,
    case result when 'BLOCK' then 1 when 'WARN' then 2 when 'INFO' then 3 when 'PASS' then 4 else 5 end,
    check_code;

rollback;

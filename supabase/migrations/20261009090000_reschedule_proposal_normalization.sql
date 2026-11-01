-- Reschedule Proposal normalization — behaviour-preserving generalization of
-- the Reschedule Proposal entity (SPEC-APT-005 BR-31, BR-33; SPEC-APT-006
-- BR-34; SPEC-APT-016; docs/RELATIONAL_MODEL.md). No product change: the only
-- approved workflows still create Proposals for CONFIRMED bases only.
--
-- A Reschedule Proposal is a frozen interval proposed to supersede one
-- specific current Schedule Revision of its Appointment. This forward-only
-- migration:
--
--   A. preflights the existing data and aborts unless every fact this
--      migration removes or transforms agrees with what replaces it;
--   B. adds base_revision_context, and the composite foreign keys that make
--      the Proposal's Appointment, base revision, and base context — and a
--      sourced revision's Appointment and context — impossible to disagree;
--   C. replaces the PENDING + "non-actionable fact" representation with four
--      final states PENDING | ACCEPTED | WITHDRAWN | VOID: existing
--      non-actionable rows become VOID with their recorded reason and time;
--      existing PENDING rows already permanently dead (superseded base,
--      lifecycle no longer CONFIRMED, Clinical Encounter) become VOID,
--      observed now;
--   D. removes the acceptance facts duplicated on the Proposal
--      (accepted_at, accepted_by_user_id, accepting_context,
--      resulting_confirmed_revision_id): they are those of the resulting
--      revision (created_at, established_by_user_id, source_proposal_id) and
--      of the counterparty rule;
--   E. replaces the pending uniqueness with UNIQUE (appointment_id) WHERE
--      state = 'PENDING', now a true statement of "one open Proposal per
--      Appointment" because a PENDING Proposal's base is always current;
--   F. makes permanent invalidation eager: one internal operation,
--      void_open_reschedule_proposal, invoked by AFTER row triggers on
--      Schedule Revision insert, lifecycle change, and Clinical Encounter
--      insert; proposal creation keeps the lazy VOID for a passed proposed
--      time or lost proposer authority; reads never write;
--   G. reduces actionability to the derived lapse (PENDING, base and proposed
--      start in the future, continuous proposer authority) and drops its
--      p_ignored_resulting_revision_id workaround: acceptance now marks the
--      Proposal ACCEPTED before inserting its resulting revision;
--   H. generalizes revision provenance to "a sourced revision is the
--      immediately following revision of an ACCEPTED Proposal's base, with
--      exactly its frozen interval", in either context (the Proposal FK and
--      the CONFIRMED-only base CHECK keep REQUESTED sourcing impossible today);
--   I. moves APPOINTMENT_RESCHEDULE_ACCEPTED enqueueing from the Proposal
--      update to the resulting CONFIRMED revision insert (same recipients,
--      same created_at, same uniqueness) and keeps the Communication origin
--      check equivalent;
--   J. keeps get_appointment_scheduling_history's output contract, deriving
--      the acceptance columns from the resulting revision;
--   K. removes proven-obsolete debt: the source-Proposal context trigger and
--      the REQUESTED-no-proposal CHECK (both now implied by constraints), the
--      redundant appointment_schedule_revisions_latest_idx (a backward scan of
--      the (appointment_id, revision_sequence) unique index serves the same
--      lookups), and resolve_clinic_appointment_interval (no caller).
--
--   L. looks up the open Proposal per Appointment in get_pet_appointments and
--      get_clinic_appointment_schedule (same output, otherwise same bodies),
--      so actionability is evaluated only for that Proposal instead of being
--      pushed down to every PENDING Proposal in the database.
--
-- Unchanged: every RPC signature and every read's output columns;
-- withdraw_appointment_reschedule_proposal, communication_delivery_is_currently_eligible,
-- and get_communication_delivery_context keep their bodies (their 2-argument
-- actionability calls bind to the new function).
-- user_has_continuous_clinic_reschedule_authority_since keeps its hard-coded
-- responsibility list (separate cleanup; authorization is not changed here).

begin;

-- ==================================================================
-- A. Preflight. Abort unless the data agrees with every assumption the
--    normalization relies on. Nothing has been changed yet.
-- ==================================================================

do $$
declare
    violation_count integer;
begin
    -- Every Proposal's base belongs to its Appointment and is CONFIRMED.
    select count(*) into violation_count
    from public.appointment_reschedule_proposals as proposal
    join public.appointment_schedule_revisions as base_revision
      on base_revision.id = proposal.base_revision_id
    where base_revision.appointment_id <> proposal.appointment_id
       or base_revision.revision_context <> 'CONFIRMED';
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization preflight: % Proposal(s) with a base revision of another Appointment or not CONFIRMED',
            violation_count;
    end if;

    -- Every ACCEPTED Proposal's duplicated acceptance facts equal those of
    -- the revision that names it as source, which is the immediately
    -- following CONFIRMED revision with exactly the frozen interval.
    select count(*) into violation_count
    from public.appointment_reschedule_proposals as proposal
    left join public.appointment_schedule_revisions as resulting_revision
      on resulting_revision.id = proposal.resulting_confirmed_revision_id
    left join public.appointment_schedule_revisions as base_revision
      on base_revision.id = proposal.base_revision_id
    where proposal.state = 'ACCEPTED'
      and (
          resulting_revision.id is null
          or resulting_revision.source_proposal_id is distinct from proposal.id
          or resulting_revision.appointment_id <> proposal.appointment_id
          or resulting_revision.revision_context <> 'CONFIRMED'
          or resulting_revision.created_at <> proposal.accepted_at
          or resulting_revision.established_by_user_id <> proposal.accepted_by_user_id
          or proposal.accepting_context is distinct from
             case proposal.proposing_context when 'GUARDIAN' then 'CLINIC' else 'GUARDIAN' end
          or resulting_revision.revision_sequence <> base_revision.revision_sequence + 1
          or resulting_revision.scheduled_start_at <> proposal.proposed_start_at
          or resulting_revision.scheduled_end_at <> proposal.proposed_end_at
          or resulting_revision.establishment_timezone_name <> proposal.proposed_timezone_name
      );
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization preflight: % ACCEPTED Proposal(s) whose acceptance facts disagree with their resulting revision',
            violation_count;
    end if;

    -- Every sourced revision is the resulting revision of an ACCEPTED Proposal.
    select count(*) into violation_count
    from public.appointment_schedule_revisions as revision
    left join public.appointment_reschedule_proposals as proposal
      on proposal.id = revision.source_proposal_id
    where revision.source_proposal_id is not null
      and (
          proposal.id is null
          or proposal.state <> 'ACCEPTED'
          or proposal.resulting_confirmed_revision_id is distinct from revision.id
      );
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization preflight: % sourced revision(s) not matched by their ACCEPTED Proposal',
            violation_count;
    end if;

    -- Recorded non-actionable facts carry a known reason and a valid time.
    select count(*) into violation_count
    from public.appointment_reschedule_proposals as proposal
    where proposal.non_actionable_at is not null
      and (
          proposal.state <> 'PENDING'
          or proposal.non_actionable_reason not in (
              'BASE_REVISION_SUPERSEDED', 'PROPOSED_TIME_PASSED', 'PROPOSING_AUTHORITY_LOST'
          )
          or proposal.non_actionable_at < proposal.created_at
      );
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization preflight: % non-actionable Proposal(s) with an unexpected shape',
            violation_count;
    end if;

    -- A PENDING Proposal that will be voided as observed now must not have
    -- been created in the future.
    select count(*) into violation_count
    from public.appointment_reschedule_proposals as proposal
    where proposal.state = 'PENDING'
      and proposal.created_at > clock_timestamp();
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization preflight: % PENDING Proposal(s) created in the future',
            violation_count;
    end if;
end;
$$;

-- ==================================================================
-- B/C. New columns and the state transformation. The Proposal triggers are
--      disabled only while existing rows are transformed; the replaced
--      functions and the rebuilt constraints are in place before they are
--      re-enabled.
-- ==================================================================

alter table public.appointment_reschedule_proposals
    add column base_revision_context text,
    add column voided_at timestamptz,
    add column void_reason text;

alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_shape_check,
    drop constraint appointment_reschedule_proposals_state_check,
    drop constraint appointment_reschedule_proposals_non_actionable_at_check,
    drop constraint appointment_reschedule_proposals_non_actionable_reason_check,
    drop constraint appointment_reschedule_proposals_accepting_context_check,
    drop constraint appointment_reschedule_proposals_counterparty_context_check;

drop index public.appointment_reschedule_proposals_pending_key;

alter table public.appointment_reschedule_proposals disable trigger user;

update public.appointment_reschedule_proposals as proposal
set base_revision_context = base_revision.revision_context
from public.appointment_schedule_revisions as base_revision
where base_revision.id = proposal.base_revision_id;

-- A recorded non-actionable fact becomes VOID with the same reason and time.
update public.appointment_reschedule_proposals
set state = 'VOID',
    voided_at = non_actionable_at,
    void_reason = non_actionable_reason
where state = 'PENDING'
  and non_actionable_at is not null;

-- An open Proposal that is already permanently dead becomes VOID, observed
-- now, with the first applicable reason.
update public.appointment_reschedule_proposals as proposal
set state = 'VOID',
    voided_at = clock_timestamp(),
    void_reason = case
        when exists (
            select 1
            from public.appointment_schedule_revisions as later_revision
            join public.appointment_schedule_revisions as base_revision
              on base_revision.id = proposal.base_revision_id
            where later_revision.appointment_id = proposal.appointment_id
              and later_revision.revision_sequence > base_revision.revision_sequence
        ) then 'BASE_REVISION_SUPERSEDED'
        when appointment.lifecycle_state <> proposal.base_revision_context
            then 'APPOINTMENT_LIFECYCLE_CHANGED'
        else 'CLINICAL_ENCOUNTER_STARTED'
    end
from public.appointments as appointment
where appointment.id = proposal.appointment_id
  and proposal.state = 'PENDING'
  and (
      exists (
          select 1
          from public.appointment_schedule_revisions as later_revision
          join public.appointment_schedule_revisions as base_revision
            on base_revision.id = proposal.base_revision_id
          where later_revision.appointment_id = proposal.appointment_id
            and later_revision.revision_sequence > base_revision.revision_sequence
      )
      or appointment.lifecycle_state <> proposal.base_revision_context
      or exists (
          select 1
          from public.clinical_encounters as encounter_row
          where encounter_row.appointment_id = proposal.appointment_id
      )
  );

-- Postflight of the transformation: at most one PENDING Proposal per
-- Appointment, and every PENDING Proposal satisfies the stored invariant.
do $$
declare
    violation_count integer;
begin
    select count(*) into violation_count
    from (
        select proposal.appointment_id
        from public.appointment_reschedule_proposals as proposal
        where proposal.state = 'PENDING'
        group by proposal.appointment_id
        having count(*) > 1
    ) as duplicated;
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization: % Appointment(s) with more than one PENDING Proposal',
            violation_count;
    end if;

    select count(*) into violation_count
    from public.appointment_reschedule_proposals as proposal
    join public.appointments as appointment
      on appointment.id = proposal.appointment_id
    join public.appointment_schedule_revisions as base_revision
      on base_revision.id = proposal.base_revision_id
    where proposal.state = 'PENDING'
      and (
          appointment.lifecycle_state <> proposal.base_revision_context
          or exists (
              select 1
              from public.appointment_schedule_revisions as later_revision
              where later_revision.appointment_id = proposal.appointment_id
                and later_revision.revision_sequence > base_revision.revision_sequence
          )
          or exists (
              select 1
              from public.clinical_encounters as encounter_row
              where encounter_row.appointment_id = proposal.appointment_id
          )
      );
    if violation_count > 0 then
        raise exception 'Reschedule Proposal normalization: % PENDING Proposal(s) violate the stored PENDING invariant',
            violation_count;
    end if;
end;
$$;

-- ==================================================================
-- D. Remove the duplicated acceptance and non-actionable facts.
-- ==================================================================

alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_resulting_revision_id_fkey,
    drop constraint appointment_reschedule_proposals_resulting_revision_key,
    drop constraint appointment_reschedule_proposals_accepted_by_user_id_fkey,
    drop column accepted_at,
    drop column accepted_by_user_id,
    drop column accepting_context,
    drop column resulting_confirmed_revision_id,
    drop column non_actionable_at,
    drop column non_actionable_reason;

-- ==================================================================
-- B/E. Final Proposal constraints, composite integrity, and indexes.
-- ==================================================================

alter table public.appointment_reschedule_proposals
    alter column base_revision_context set not null,
    add constraint appointment_reschedule_proposals_state_check
        check (state in ('PENDING', 'ACCEPTED', 'WITHDRAWN', 'VOID')),
    -- Widened by the approved REQUESTED workflow when it exists; until then
    -- only a CONFIRMED scheduling context can be proposed against.
    add constraint appointment_reschedule_proposals_base_revision_context_check
        check (base_revision_context = 'CONFIRMED'),
    add constraint appointment_reschedule_proposals_withdrawn_shape_check
        check (
            (state = 'WITHDRAWN') = (withdrawn_at is not null)
            and (withdrawn_at is null) = (withdrawn_by_user_id is null)
        ),
    add constraint appointment_reschedule_proposals_void_shape_check
        check (
            (state = 'VOID') = (voided_at is not null)
            and (voided_at is null) = (void_reason is null)
        ),
    add constraint appointment_reschedule_proposals_void_reason_check
        check (
            void_reason is null
            or void_reason in (
                'BASE_REVISION_SUPERSEDED', 'APPOINTMENT_LIFECYCLE_CHANGED',
                'CLINICAL_ENCOUNTER_STARTED', 'PROPOSED_TIME_PASSED',
                'PROPOSING_AUTHORITY_LOST'
            )
        ),
    add constraint appointment_reschedule_proposals_voided_at_check
        check (
            voided_at is null
            or (isfinite(voided_at) and voided_at >= created_at)
        ),
    -- Superkey referenced by a sourced revision.
    add constraint appointment_reschedule_proposals_appointment_context_key
        unique (id, appointment_id, base_revision_context);

-- Superkey referenced by a Proposal's base.
alter table public.appointment_schedule_revisions
    add constraint appointment_schedule_revisions_appointment_context_key
        unique (id, appointment_id, revision_context);

alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_base_revision_id_fkey,
    add constraint appointment_reschedule_proposals_base_revision_fkey
        foreign key (base_revision_id, appointment_id, base_revision_context)
        references public.appointment_schedule_revisions (id, appointment_id, revision_context)
        on update no action
        on delete restrict;

-- A sourced revision belongs to its Proposal's Appointment and has its base
-- context. With the CONFIRMED-only base CHECK this also makes a REQUESTED
-- sourced revision impossible, so the REQUESTED-no-proposal CHECK is implied.
alter table public.appointment_schedule_revisions
    drop constraint appointment_schedule_revisions_source_proposal_id_fkey,
    drop constraint appointment_schedule_revisions_requested_no_proposal_check,
    add constraint appointment_schedule_revisions_source_proposal_fkey
        foreign key (source_proposal_id, appointment_id, revision_context)
        references public.appointment_reschedule_proposals (id, appointment_id, base_revision_context)
        on update no action
        on delete restrict;

-- One open Proposal per Appointment (SPEC-APT-005 BR-14).
create unique index appointment_reschedule_proposals_pending_key
on public.appointment_reschedule_proposals (appointment_id)
where state = 'PENDING';

-- Redundant with appointment_schedule_revisions_appointment_sequence_key,
-- whose (appointment_id, revision_sequence) btree serves latest-revision
-- lookups by a backward scan.
drop index public.appointment_schedule_revisions_latest_idx;

-- Same Appointment and Proposal origin are now foreign keys.
drop trigger appointment_schedule_revisions_validate_source_proposal
on public.appointment_schedule_revisions;
drop function public.enforce_appointment_schedule_revision_source_proposal_context();

-- No remaining caller since 20261008090000.
drop function public.resolve_clinic_appointment_interval(
    uuid, date, time, integer, date, time, integer
);

-- ==================================================================
-- G. Actionability: the derived lapse only. PENDING already guarantees a
--    current base, a lifecycle state equal to the base context, and no
--    Clinical Encounter.
-- ==================================================================

drop function public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz, uuid);

create function public.appointment_reschedule_proposal_is_actionable(
    p_proposal_id uuid,
    p_as_of timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.appointment_reschedule_proposals as proposal
        join public.appointments as appointment
          on appointment.id = proposal.appointment_id
        join public.appointment_schedule_revisions as base_revision
          on base_revision.id = proposal.base_revision_id
        where proposal.id = p_proposal_id
          and proposal.state = 'PENDING'
          and base_revision.scheduled_start_at > p_as_of
          and proposal.proposed_start_at > p_as_of
          and (
              (
                  proposal.proposing_context = 'GUARDIAN'
                  and public.user_has_continuous_guardianship_since(
                      proposal.proposed_by_user_id,
                      appointment.pet_id,
                      proposal.created_at
                  )
              )
              or
              (
                  proposal.proposing_context = 'CLINIC'
                  and public.user_has_continuous_clinic_reschedule_authority_since(
                      proposal.proposed_by_user_id,
                      appointment.clinic_id,
                      proposal.created_at
                  )
              )
          )
    )
$$;

revoke all privileges
on function public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz)
from public, anon, authenticated;

-- ==================================================================
-- Proposal integrity: establishment, transitions, and VOID justification.
-- ==================================================================

create or replace function public.enforce_appointment_reschedule_proposal_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointment Reschedule Proposals cannot be deleted'
            using errcode = '23514';
    end if;

    if tg_op = 'INSERT' then
        -- The state CHECKs then require every resolution fact to be absent.
        if new.state <> 'PENDING' then
            raise exception 'Appointment Reschedule Proposal must be established as PENDING'
                using errcode = '23514';
        end if;

        return new;
    end if;

    -- tg_op = 'UPDATE': only PENDING -> ACCEPTED | WITHDRAWN | VOID.
    if old.state <> 'PENDING' then
        raise exception 'Accepted, withdrawn, and void Appointment Reschedule Proposals are immutable'
            using errcode = '23514';
    end if;

    if new.state = 'PENDING' then
        raise exception 'A PENDING Appointment Reschedule Proposal may only become ACCEPTED, WITHDRAWN, or VOID'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.appointment_id is distinct from new.appointment_id
       or old.base_revision_id is distinct from new.base_revision_id
       or old.base_revision_context is distinct from new.base_revision_context
       or old.proposed_start_at is distinct from new.proposed_start_at
       or old.proposed_end_at is distinct from new.proposed_end_at
       or old.proposed_timezone_name is distinct from new.proposed_timezone_name
       or old.proposing_context is distinct from new.proposing_context
       or old.proposed_by_user_id is distinct from new.proposed_by_user_id
       or old.reason is distinct from new.reason
       or old.created_at is distinct from new.created_at then
        raise exception 'Appointment Reschedule Proposal context is immutable'
            using errcode = '23514';
    end if;

    -- Resolution times are observed database facts, not caller-authored.
    if new.state = 'WITHDRAWN' then
        new.withdrawn_at := clock_timestamp();
    elsif new.state = 'VOID' then
        new.voided_at := clock_timestamp();
    end if;

    if new.state = 'ACCEPTED'
       and not public.appointment_reschedule_proposal_is_actionable(old.id, clock_timestamp()) then
        raise exception 'Only a currently actionable Appointment Reschedule Proposal may be accepted'
            using errcode = '23514';
    end if;

    if new.state = 'WITHDRAWN' then
        if old.proposing_context <> 'CLINIC' then
            raise exception 'Only a Clinic-originated Reschedule Proposal may be withdrawn'
                using errcode = '23514';
        end if;

        if not public.appointment_reschedule_proposal_is_actionable(old.id, clock_timestamp()) then
            raise exception 'Only a currently actionable Appointment Reschedule Proposal may be withdrawn'
                using errcode = '23514';
        end if;
    end if;

    -- Every VOID reason must be true when it is recorded.
    if new.state = 'VOID' then
        if new.void_reason = 'BASE_REVISION_SUPERSEDED' then
            if not exists (
                select 1
                from public.appointment_schedule_revisions as later_revision
                join public.appointment_schedule_revisions as base_revision
                  on base_revision.id = old.base_revision_id
                where later_revision.appointment_id = old.appointment_id
                  and later_revision.revision_sequence > base_revision.revision_sequence
            ) then
                raise exception 'Reschedule Proposal base revision has not been superseded'
                    using errcode = '23514';
            end if;
        elsif new.void_reason = 'APPOINTMENT_LIFECYCLE_CHANGED' then
            if exists (
                select 1
                from public.appointments as appointment
                where appointment.id = old.appointment_id
                  and appointment.lifecycle_state = old.base_revision_context
            ) then
                raise exception 'Appointment lifecycle state still matches the Reschedule Proposal base context'
                    using errcode = '23514';
            end if;
        elsif new.void_reason = 'CLINICAL_ENCOUNTER_STARTED' then
            if not exists (
                select 1
                from public.clinical_encounters as encounter_row
                where encounter_row.appointment_id = old.appointment_id
            ) then
                raise exception 'No Clinical Encounter exists for the Reschedule Proposal Appointment'
                    using errcode = '23514';
            end if;
        elsif new.void_reason = 'PROPOSED_TIME_PASSED' then
            if old.proposed_start_at > new.voided_at then
                raise exception 'Reschedule Proposal time had not passed at the recorded resolution time'
                    using errcode = '23514';
            end if;
        elsif new.void_reason = 'PROPOSING_AUTHORITY_LOST' then
            if exists (
                select 1
                from public.appointments as appointment
                where appointment.id = old.appointment_id
                  and (
                      (
                          old.proposing_context = 'GUARDIAN'
                          and public.user_has_continuous_guardianship_since(
                              old.proposed_by_user_id, appointment.pet_id, old.created_at
                          )
                      )
                      or
                      (
                          old.proposing_context = 'CLINIC'
                          and public.user_has_continuous_clinic_reschedule_authority_since(
                              old.proposed_by_user_id, appointment.clinic_id, old.created_at
                          )
                      )
                  )
            ) then
                raise exception 'Reschedule Proposal proposing authority has remained continuous'
                    using errcode = '23514';
            end if;
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_reschedule_proposal_integrity()
from public, anon, authenticated;

-- Establishes the stored PENDING invariant. Same Appointment and base context
-- are the composite foreign key; this checks what a key cannot: the base is
-- the Appointment's current revision, the lifecycle state equals the base
-- context, and no Clinical Encounter exists.
create or replace function public.enforce_appointment_reschedule_proposal_base_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    base_revision_sequence integer;
    appointment_state text;
begin
    select appointment.lifecycle_state
    into appointment_state
    from public.appointments as appointment
    where appointment.id = new.appointment_id
    for update;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    select revision.revision_sequence
    into base_revision_sequence
    from public.appointment_schedule_revisions as revision
    where revision.id = new.base_revision_id
      and revision.appointment_id = new.appointment_id;

    if not found then
        raise exception 'Reschedule Proposal base revision does not exist for the Appointment'
            using errcode = '23503';
    end if;

    if exists (
        select 1
        from public.appointment_schedule_revisions as later_revision
        where later_revision.appointment_id = new.appointment_id
          and later_revision.revision_sequence > base_revision_sequence
    ) then
        raise exception 'Reschedule Proposal base revision must be the current scheduling context'
            using errcode = '23514';
    end if;

    if appointment_state <> new.base_revision_context then
        raise exception 'Reschedule Proposal base context must match the Appointment lifecycle state'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.clinical_encounters as encounter_row
        where encounter_row.appointment_id = new.appointment_id
    ) then
        raise exception 'Appointment with a Clinical Encounter cannot be rescheduled'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_reschedule_proposal_base_revision()
from public, anon, authenticated;

-- ACCEPTED <=> exactly one revision names the Proposal as its source. The
-- revision side (context, Appointment, interval, sequence) is the revision
-- provenance assertion below.
create or replace function public.assert_appointment_reschedule_proposal_acceptance(
    p_proposal_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    proposal_state text;
    resulting_revision_count integer;
begin
    select proposal.state
    into proposal_state
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    if not found or proposal_state <> 'ACCEPTED' then
        return;
    end if;

    select count(*)
    into resulting_revision_count
    from public.appointment_schedule_revisions as revision
    where revision.source_proposal_id = p_proposal_id;

    if resulting_revision_count <> 1 then
        raise exception 'Accepted Reschedule Proposal % requires exactly one resulting Schedule Revision',
            p_proposal_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_reschedule_proposal_acceptance(uuid)
from public, anon, authenticated;

-- ==================================================================
-- H. Revision provenance, state-neutral for sourced revisions.
-- ==================================================================

create or replace function public.assert_appointment_schedule_revision_provenance(
    p_revision_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    revision_record public.appointment_schedule_revisions%rowtype;
    appointment_record public.appointments%rowtype;
    preceding_requested_record public.appointment_schedule_revisions%rowtype;
    proposal_record public.appointment_reschedule_proposals%rowtype;
    base_revision_sequence integer;
    total_count integer;
    contiguous_count integer;
    first_context text;
    earlier_confirmed_count integer;
    confirmation_event_count integer;
begin
    select revision.*
    into revision_record
    from public.appointment_schedule_revisions as revision
    where revision.id = p_revision_id;

    if not found then
        return;
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = revision_record.appointment_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = revision_record.appointment_id;

    if not found then
        raise exception 'Appointment Schedule Revision % requires its Appointment',
            p_revision_id
            using errcode = '23514';
    end if;

    -- A. sequence contiguity {1..n}
    select count(*)
    into total_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id;

    select count(*)
    into contiguous_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_sequence between 1 and total_count;

    if contiguous_count <> total_count then
        raise exception 'Appointment % Schedule Revision sequence must be contiguous from 1',
            revision_record.appointment_id
            using errcode = '23514';
    end if;

    -- B. sequence 1 is always REQUESTED
    select revision.revision_context
    into first_context
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_sequence = 1;

    if first_context is distinct from 'REQUESTED' then
        raise exception 'Appointment % first Schedule Revision must be REQUESTED',
            revision_record.appointment_id
            using errcode = '23514';
    end if;

    -- C. context/lifecycle coherence for the newly inserted row
    if revision_record.revision_context = 'REQUESTED' then
        if appointment_record.lifecycle_state <> 'REQUESTED' then
            raise exception 'REQUESTED Schedule Revision % requires a REQUESTED Appointment',
                p_revision_id
                using errcode = '23514';
        end if;
    else
        if appointment_record.lifecycle_state <> 'CONFIRMED' then
            raise exception 'CONFIRMED Schedule Revision % requires a CONFIRMED Appointment',
                p_revision_id
                using errcode = '23514';
        end if;

        select count(*)
        into confirmation_event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = revision_record.appointment_id
          and event_row.from_state = 'REQUESTED'
          and event_row.to_state = 'CONFIRMED';

        if confirmation_event_count <> 1 then
            raise exception 'CONFIRMED Schedule Revision % requires exactly one confirmation Lifecycle Event',
                p_revision_id
                using errcode = '23514';
        end if;

        select count(*)
        into earlier_confirmed_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = revision_record.appointment_id
          and revision.revision_context = 'CONFIRMED'
          and revision.revision_sequence < revision_record.revision_sequence;
    end if;

    -- D. Proposal-sourced revision, in either context. Same Appointment and
    --    same context as the Proposal's base are the composite foreign key.
    if revision_record.source_proposal_id is not null then
        if revision_record.revision_context = 'CONFIRMED' and earlier_confirmed_count = 0 then
            raise exception 'First CONFIRMED Schedule Revision % must not reference a Proposal',
                p_revision_id
                using errcode = '23514';
        end if;

        select proposal.*
        into proposal_record
        from public.appointment_reschedule_proposals as proposal
        where proposal.id = revision_record.source_proposal_id;

        if proposal_record.state <> 'ACCEPTED' then
            raise exception 'Schedule Revision % source Proposal must be ACCEPTED',
                p_revision_id
                using errcode = '23514';
        end if;

        if revision_record.scheduled_start_at <> proposal_record.proposed_start_at
           or revision_record.scheduled_end_at <> proposal_record.proposed_end_at
           or revision_record.establishment_timezone_name <> proposal_record.proposed_timezone_name then
            raise exception 'Schedule Revision % must exactly match its source Proposal proposed context',
                p_revision_id
                using errcode = '23514';
        end if;

        select revision.revision_sequence
        into base_revision_sequence
        from public.appointment_schedule_revisions as revision
        where revision.id = proposal_record.base_revision_id;

        -- The immediately following revision of its base: the base was still
        -- current when the Proposal was accepted.
        if revision_record.revision_sequence <> base_revision_sequence + 1 then
            raise exception 'Schedule Revision % source Proposal base revision is no longer the current scheduling context',
                p_revision_id
                using errcode = '23514';
        end if;

        return;
    end if;

    -- E. Unsourced revisions: an initial or Guardian-requested REQUESTED
    --    revision, or the first CONFIRMED revision (the confirmation).
    if revision_record.revision_context = 'REQUESTED' then
        return;
    end if;

    if earlier_confirmed_count > 0 then
        raise exception 'Later CONFIRMED Schedule Revision % requires a source Proposal',
            p_revision_id
            using errcode = '23514';
    end if;

    select revision.*
    into preceding_requested_record
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = revision_record.appointment_id
      and revision.revision_context = 'REQUESTED'
      and revision.revision_sequence < revision_record.revision_sequence
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'First CONFIRMED Schedule Revision % requires a preceding REQUESTED Schedule Revision',
            p_revision_id
            using errcode = '23514';
    end if;

    if revision_record.scheduled_start_at <> preceding_requested_record.scheduled_start_at
       or revision_record.scheduled_end_at <> preceding_requested_record.scheduled_end_at
       or revision_record.establishment_timezone_name
              <> preceding_requested_record.establishment_timezone_name then
        raise exception 'First CONFIRMED Schedule Revision % must exactly match the preceding REQUESTED context',
            p_revision_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_schedule_revision_provenance(uuid)
from public, anon, authenticated;

-- ==================================================================
-- F. Eager permanent invalidation (SPEC-APT-005 BR-33).
-- ==================================================================

-- The single place a PENDING Proposal is invalidated by an Appointment event.
-- The integrity trigger records voided_at and verifies the reason.
create function public.void_open_reschedule_proposal(
    p_appointment_id uuid,
    p_reason text
)
returns void
language sql
security definer
set search_path = ''
as $$
    update public.appointment_reschedule_proposals
    set state = 'VOID',
        void_reason = p_reason
    where appointment_id = p_appointment_id
      and state = 'PENDING'
$$;

revoke all privileges
on function public.void_open_reschedule_proposal(uuid, text)
from public, anon, authenticated;

create function public.enforce_reschedule_proposal_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'appointment_schedule_revisions' then
        -- Any later revision supersedes the open Proposal's base. Acceptance
        -- marks its Proposal ACCEPTED before inserting the resulting revision,
        -- so the accepted Proposal is never PENDING here.
        perform public.void_open_reschedule_proposal(
            new.appointment_id, 'BASE_REVISION_SUPERSEDED'
        );
    elsif tg_table_name = 'appointments' then
        if exists (
            select 1
            from public.appointment_reschedule_proposals as proposal
            where proposal.appointment_id = new.id
              and proposal.state = 'PENDING'
              and proposal.base_revision_context <> new.lifecycle_state
        ) then
            perform public.void_open_reschedule_proposal(
                new.id, 'APPOINTMENT_LIFECYCLE_CHANGED'
            );
        end if;
    elsif tg_table_name = 'clinical_encounters' then
        perform public.void_open_reschedule_proposal(
            new.appointment_id, 'CLINICAL_ENCOUNTER_STARTED'
        );
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_reschedule_proposal_invalidation()
from public, anon, authenticated;

create trigger appointment_schedule_revisions_invalidate_reschedule_proposal
after insert on public.appointment_schedule_revisions
for each row
execute function public.enforce_reschedule_proposal_invalidation();

create trigger appointments_invalidate_reschedule_proposal
after update of lifecycle_state on public.appointments
for each row
when (old.lifecycle_state is distinct from new.lifecycle_state)
execute function public.enforce_reschedule_proposal_invalidation();

create trigger clinical_encounters_invalidate_reschedule_proposal
after insert on public.clinical_encounters
for each row
when (new.appointment_id is not null)
execute function public.enforce_reschedule_proposal_invalidation();

-- ==================================================================
-- Proposal creation (SPEC-APT-005). Signature and behaviour unchanged; the
-- base context is recorded, and the lazy VOID covers only what is not
-- eagerly invalidated: a passed proposed time or lost proposer authority.
-- ==================================================================

create or replace function public.propose_confirmed_appointment_reschedule(
    p_appointment_id uuid,
    p_proposing_context text,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_reason text default null,
    p_expected_confirmed_revision_sequence integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    base_revision public.appointment_schedule_revisions%rowtype;
    existing_proposal_record public.appointment_reschedule_proposals%rowtype;
    resolved_start record;
    normalized_reason text;
    duration_microseconds bigint;
    proposed_end_at timestamptz;
    operation_timestamp timestamptz;
    created_proposal_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- BR-27 step 2: structural input, before any Appointment state.
    if p_proposing_context is null
       or p_proposing_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Proposing context must be GUARDIAN or CLINIC'
            using errcode = '22023';
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    if p_proposing_context = 'GUARDIAN' then
        if p_expected_confirmed_revision_sequence is not null then
            raise exception 'Guardian reschedule proposal does not accept an expected confirmed revision sequence'
                using errcode = '22023';
        end if;
    else
        if p_expected_confirmed_revision_sequence is null
           or p_expected_confirmed_revision_sequence <= 0 then
            raise exception 'Expected confirmed revision sequence must be a positive integer'
                using errcode = '22023';
        end if;

        if normalized_reason is null then
            raise exception 'A meaningful reason is required for a Clinic-proposed reschedule'
                using errcode = '22023';
        end if;
    end if;

    -- BR-27 step 3: authority under the existing lock order (Organization ->
    -- Clinic before the Appointment for the CLINIC context).
    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if p_proposing_context = 'CLINIC' then
        perform public.assert_clinic_appointment_authorization_after_lock(
            acting_user_id, resolved_clinic_id,
            'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_MANAGEMENT'
        );
    else
        -- GUARDIAN: prove current Guardianship before any lifecycle state is
        -- disclosed (BR-27 step 3 before step 4), as acceptance does. The
        -- authoritative check is the locked revalidation below.
        if not exists (
            select 1
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = p_appointment_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_end is null
        ) then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- BR-27 step 4.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may receive a reschedule Proposal'
            using errcode = '23514';
    end if;

    -- Authoritative, locked revalidation of the exact current Guardianship row
    -- after the Appointment lock.
    if p_proposing_context = 'GUARDIAN' then
        perform 1
        from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
        for update;

        if not found then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    end if;

    -- BR-27 step 5: the base confirmed scheduling context and, for CLINIC,
    -- the reviewed-context check — before any write (including the lazy VOID
    -- below).
    select revision.*
    into base_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc
    limit 1;

    if not found then
        raise exception 'Appointment % has no confirmed scheduling context',
            p_appointment_id
            using errcode = '23514';
    end if;

    if p_proposing_context = 'CLINIC'
       and base_revision.revision_sequence <> p_expected_confirmed_revision_sequence then
        raise exception 'Stale confirmed Appointment schedule revision for reschedule proposal';
    end if;

    -- BR-27 step 6.
    operation_timestamp := clock_timestamp();

    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.clinical_encounters as encounter_row
        where encounter_row.appointment_id = p_appointment_id
    ) then
        raise exception 'Appointment with a Clinical Encounter cannot be rescheduled'
            using errcode = '23514';
    end if;

    -- The open Proposal, if any, is on this same current base (BR-33 makes a
    -- superseded, lifecycle-changed, or Encounter-blocked one VOID eagerly).
    -- Only an actionable one blocks a new negotiation; a lapsed one is made
    -- VOID here, releasing the slot atomically with the new Proposal.
    select proposal.*
    into existing_proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.appointment_id = p_appointment_id
      and proposal.state = 'PENDING'
    for update;

    if found then
        if existing_proposal_record.proposed_start_at <= operation_timestamp then
            update public.appointment_reschedule_proposals
            set state = 'VOID',
                void_reason = 'PROPOSED_TIME_PASSED'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'GUARDIAN'
              and not public.user_has_continuous_guardianship_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.pet_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set state = 'VOID',
                void_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'CLINIC'
              and not public.user_has_continuous_clinic_reschedule_authority_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.clinic_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set state = 'VOID',
                void_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        else
            raise exception 'Appointment % already has an actionable unresolved reschedule Proposal',
                p_appointment_id
                using errcode = '23505';
        end if;
    end if;

    -- BR-23: only the new start is resolved, in the Clinic's authoritative
    -- timezone (validated once here).
    select * into resolved_start
    from public.resolve_clinic_appointment_start(
        appointment_record.clinic_id,
        p_start_local_date, p_start_local_time, p_start_utc_offset_seconds
    );

    if resolved_start.resolved_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must be in the future'
            using errcode = '22023';
    end if;

    -- BR-25: the same start instant is never a reschedule.
    if resolved_start.resolved_start_at = base_revision.scheduled_start_at then
        raise exception 'Proposed time must differ from the current confirmed time'
            using errcode = '22023';
    end if;

    -- BR-24: preserve the base confirmed elapsed duration; the Clinic's
    -- standard duration is never read.
    duration_microseconds := public.appointment_interval_duration_microseconds(
        base_revision.scheduled_start_at, base_revision.scheduled_end_at
    );
    proposed_end_at := resolved_start.resolved_start_at
        + duration_microseconds * interval '1 microsecond';

    -- BR-28.
    perform public.assert_appointment_reschedule_interval_feasible(
        p_appointment_id, appointment_record.clinic_id,
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name
    );

    insert into public.appointment_reschedule_proposals (
        appointment_id, base_revision_id, base_revision_context,
        proposed_start_at, proposed_end_at, proposed_timezone_name,
        proposing_context, proposed_by_user_id, reason, created_at
    )
    values (
        p_appointment_id, base_revision.id, base_revision.revision_context,
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name,
        p_proposing_context, acting_user_id, normalized_reason, operation_timestamp
    )
    returning id into created_proposal_id;

    return created_proposal_id;
end;
$$;

revoke all privileges
on function public.propose_confirmed_appointment_reschedule(
    uuid, text, date, time, integer, text, integer
)
from public, anon, authenticated;

grant execute
on function public.propose_confirmed_appointment_reschedule(
    uuid, text, date, time, integer, text, integer
)
to authenticated;

-- ==================================================================
-- Acceptance (SPEC-APT-006). Signature and observable outcomes unchanged.
-- The Proposal becomes ACCEPTED before its resulting revision is inserted;
-- the deferred acceptance and provenance assertions prove the pair at commit
-- and any failure rolls both back.
-- ==================================================================

create or replace function public.accept_appointment_reschedule_proposal(
    p_proposal_id uuid,
    p_accepting_context text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    initial_proposing_context text;
    resolved_appointment_id uuid;
    resolved_clinic_id uuid;
    proposal_record public.appointment_reschedule_proposals%rowtype;
    appointment_record public.appointments%rowtype;
    base_revision public.appointment_schedule_revisions%rowtype;
    clinic_timezone_name text;
    next_sequence integer;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if p_accepting_context is null
       or p_accepting_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Accepting context must be GUARDIAN or CLINIC'
            using errcode = '22023';
    end if;

    -- Resolve immutable Proposal -> Appointment -> Clinic context first,
    -- without acquiring a conflicting write lock, so we know which
    -- Organization/Clinic to lock before ever touching the Appointment.
    select proposal.appointment_id, proposal.proposing_context
    into resolved_appointment_id, initial_proposing_context
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    if not found then
        raise exception 'Reschedule Proposal does not exist'
            using errcode = '23503';
    end if;

    if initial_proposing_context = p_accepting_context then
        raise exception 'The proposing context cannot accept its own Proposal'
            using errcode = '42501';
    end if;

    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if p_accepting_context = 'GUARDIAN' then
        -- Guardian domain authority is proven before any commercial lock is
        -- taken, so Entitlement state is never disclosed to a non-Guardian.
        if not exists (
            select 1
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = resolved_appointment_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_end is null
        ) then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;

        perform public.assert_clinic_organization_entitlement_after_lock(
            resolved_clinic_id, 'APPOINTMENT_MANAGEMENT'
        );
    else
        perform public.assert_clinic_appointment_authorization_after_lock(
            acting_user_id, resolved_clinic_id,
            'APPOINTMENT_RESCHEDULE', 'APPOINTMENT_MANAGEMENT'
        );
    end if;

    -- Appointment lock acquired only after Organization/Clinic. Re-read both
    -- the Proposal and the Appointment now.
    perform 1
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id
    for update;

    select proposal.*
    into proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Appointment must remain CONFIRMED to accept a reschedule Proposal'
            using errcode = '23514';
    end if;

    -- A VOID Proposal keeps the specific outcome its invalidation stands for.
    if proposal_record.state = 'VOID'
       and proposal_record.void_reason = 'CLINICAL_ENCOUNTER_STARTED' then
        raise exception 'Appointment with a Clinical Encounter cannot be rescheduled'
            using errcode = '23514';
    elsif proposal_record.state = 'VOID'
          and proposal_record.void_reason = 'BASE_REVISION_SUPERSEDED' then
        raise exception 'Reschedule Proposal base revision is no longer the current confirmed context'
            using errcode = '23514';
    elsif proposal_record.state <> 'PENDING' then
        raise exception 'Reschedule Proposal is no longer actionable'
            using errcode = '23514';
    end if;

    if p_accepting_context = 'GUARDIAN' then
        perform 1
        from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
        for update;

        if not found then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    end if;

    if proposal_record.proposing_context = 'GUARDIAN' then
        perform 1
        from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id
          and guardianship.user_id = proposal_record.proposed_by_user_id
          and guardianship.effective_end is null
        for update;

        if not found
           or not public.user_has_continuous_guardianship_since(
               proposal_record.proposed_by_user_id,
               appointment_record.pet_id,
               proposal_record.created_at
           ) then
            raise exception 'The Guardian Proposal is no longer actionable because proposing authority was lost'
                using errcode = '42501';
        end if;
    elsif not public.user_has_continuous_clinic_reschedule_authority_since(
        proposal_record.proposed_by_user_id,
        appointment_record.clinic_id,
        proposal_record.created_at
    ) then
        raise exception 'The Clinic Proposal is no longer actionable because proposing authority was lost'
            using errcode = '42501';
    end if;

    -- PENDING guarantees the base is the current revision.
    select revision.*
    into base_revision
    from public.appointment_schedule_revisions as revision
    where revision.id = proposal_record.base_revision_id;

    operation_timestamp := clock_timestamp();

    if base_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be future and actionable'
            using errcode = '23514';
    end if;

    if proposal_record.proposed_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    -- Authoritative actionability (SPEC-APT-005 BR-31), after the specific
    -- checks above so their messages stay distinguishable.
    if not public.appointment_reschedule_proposal_is_actionable(
        p_proposal_id, operation_timestamp
    ) then
        raise exception 'Reschedule Proposal is no longer actionable'
            using errcode = '23514';
    end if;

    -- BR-30: revalidate feasibility of the exact stored interval against the
    -- Clinic's current timezone and configuration.
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Clinic Appointment Availability does not cover the proposed interval'
            using errcode = '23514';
    end if;

    perform public.assert_appointment_reschedule_interval_feasible(
        appointment_record.id, appointment_record.clinic_id,
        proposal_record.proposed_start_at, proposal_record.proposed_end_at,
        clinic_timezone_name
    );

    -- 1. The Proposal is accepted (the integrity trigger re-checks
    --    actionability); 2. its single resulting revision is the stored
    --    interval, unchanged, in the base context (BR-28, BR-34). Acceptance
    --    time and User are the revision's created_at and
    --    established_by_user_id. The deferred Veterinarian conflict
    --    constraint remains authoritative at commit.
    update public.appointment_reschedule_proposals
    set state = 'ACCEPTED'
    where id = p_proposal_id;

    next_sequence := public.next_appointment_revision_sequence(appointment_record.id);

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        appointment_record.id, next_sequence, proposal_record.base_revision_context,
        proposal_record.proposed_start_at, proposal_record.proposed_end_at,
        proposal_record.proposed_timezone_name, acting_user_id, p_proposal_id, operation_timestamp
    );

    return p_proposal_id;
end;
$$;

revoke all privileges
on function public.accept_appointment_reschedule_proposal(uuid, text)
from public, anon, authenticated;

grant execute
on function public.accept_appointment_reschedule_proposal(uuid, text)
to authenticated;

-- ==================================================================
-- J. Scheduling history: same output contract; acceptance columns derived
--    from the resulting revision and the counterparty rule (SPEC-APT-006
--    BR-34).
-- ==================================================================

create or replace function public.get_appointment_scheduling_history(
    p_appointment_id uuid
)
returns table (
    revision_sequence integer,
    revision_context text,
    scheduled_start_at timestamptz,
    scheduled_end_at timestamptz,
    establishment_timezone_name text,
    established_by_user_id uuid,
    established_at timestamptz,
    is_accepted_reschedule boolean,
    reschedule_proposing_context text,
    reschedule_proposed_by_user_id uuid,
    reschedule_reason text,
    reschedule_proposed_at timestamptz,
    reschedule_accepting_context text,
    reschedule_accepted_by_user_id uuid,
    reschedule_accepted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_pet_id uuid;
    appointment_clinic_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select appointment.pet_id, appointment.clinic_id
    into appointment_pet_id, appointment_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if not (
        exists (
            select 1
            from public.guardianships as guardianship
            where guardianship.pet_id = appointment_pet_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_end is null
        )
        or public.user_has_clinic_capability(
            acting_user_id,
            appointment_clinic_id,
            'APPOINTMENT_VIEW_SCHEDULE'
        )
    ) then
        raise exception 'Current Guardianship or applicable Clinic schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        revision.revision_sequence,
        revision.revision_context,
        revision.scheduled_start_at,
        revision.scheduled_end_at,
        revision.establishment_timezone_name,
        revision.established_by_user_id,
        revision.created_at,
        source_proposal.id is not null,
        source_proposal.proposing_context,
        source_proposal.proposed_by_user_id,
        source_proposal.reason,
        source_proposal.created_at,
        case source_proposal.proposing_context
            when 'GUARDIAN' then 'CLINIC'
            when 'CLINIC' then 'GUARDIAN'
        end,
        case when source_proposal.id is not null then revision.established_by_user_id end,
        case when source_proposal.id is not null then revision.created_at end
    from public.appointment_schedule_revisions as revision
    left join public.appointment_reschedule_proposals as source_proposal
      on source_proposal.id = revision.source_proposal_id
    where revision.appointment_id = p_appointment_id
    order by revision.revision_sequence;
end;
$$;

revoke all privileges
on function public.get_appointment_scheduling_history(uuid)
from public, anon, authenticated;

grant execute
on function public.get_appointment_scheduling_history(uuid)
to authenticated;

-- ==================================================================
-- Pending-proposal reads: same output contracts and bodies (latest in
-- 20261007090000 and 20261003090000), except that the open Proposal is looked
-- up per Appointment through the PENDING unique index and actionability is
-- evaluated only for it. A plain join let the planner push the actionability
-- call down to every PENDING Proposal in the database; LIMIT 1 (exact: one
-- PENDING Proposal per Appointment) keeps the lookup per Appointment.
-- ==================================================================

create or replace function public.get_pet_appointments(
    p_pet_id uuid
)
returns table (
    id uuid,
    clinic_id uuid,
    requesting_user_id uuid,
    reason_for_visit text,
    guardian_notes text,
    lifecycle_state text,
    created_at timestamptz,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text,
    cancellation_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    return query
    select
        appointment.id,
        appointment.clinic_id,
        appointment.requesting_user_id,
        appointment.reason_for_visit,
        appointment.guardian_notes,
        appointment.lifecycle_state,
        appointment.created_at,
        current_revision.scheduled_start_at,
        current_revision.scheduled_end_at,
        current_revision.establishment_timezone_name,
        current_assignment.veterinarian_clinic_assignment_id,
        pending_proposal.id,
        pending_proposal.state,
        pending_proposal.proposing_context,
        pending_proposal.proposed_start_at,
        pending_proposal.proposed_end_at,
        pending_proposal.proposed_timezone_name,
        pending_proposal.reason,
        cancellation_event.reason
    from public.appointments as appointment
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at, revision.establishment_timezone_name
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason
        from public.appointment_reschedule_proposals as open_proposal
        where open_proposal.appointment_id = appointment.id
          and open_proposal.state = 'PENDING'
          and public.appointment_reschedule_proposal_is_actionable(
              open_proposal.id,
              statement_timestamp()
          )
        limit 1
    ) as pending_proposal on true
    -- SPEC-APT-011 BR-31: only a CANCELLED Appointment carries a cancellation
    -- reason, from its single CANCELLED Lifecycle Event.
    left join public.appointment_lifecycle_events as cancellation_event
      on cancellation_event.appointment_id = appointment.id
     and cancellation_event.to_state = 'CANCELLED'
     and appointment.lifecycle_state = 'CANCELLED'
    where appointment.pet_id = p_pet_id
    order by appointment.created_at, appointment.id;
end;
$$;

revoke all privileges
on function public.get_pet_appointments(uuid)
from public, anon, authenticated;

grant execute
on function public.get_pet_appointments(uuid)
to authenticated;

create or replace function public.get_clinic_appointment_schedule(
    p_clinic_id uuid
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    requesting_user_id uuid,
    reason_for_visit text,
    guardian_notes text,
    lifecycle_state text,
    created_at timestamptz,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_schedule_revision_sequence integer,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not public.user_has_clinic_capability(
        acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE'
    ) then
        raise exception 'Applicable Appointment schedule-view capability is required'
            using errcode = '42501';
    end if;

    return query
    select
        appointment.id,
        appointment.pet_id,
        pet.name,
        appointment.requesting_user_id,
        appointment.reason_for_visit,
        appointment.guardian_notes,
        appointment.lifecycle_state,
        appointment.created_at,
        current_revision.scheduled_start_at,
        current_revision.scheduled_end_at,
        current_revision.establishment_timezone_name,
        current_revision.revision_sequence,
        current_assignment.veterinarian_clinic_assignment_id,
        pending_proposal.id,
        pending_proposal.state,
        pending_proposal.proposing_context,
        pending_proposal.proposed_start_at,
        pending_proposal.proposed_end_at,
        pending_proposal.proposed_timezone_name,
        pending_proposal.reason
    from public.appointments as appointment
    join public.pets as pet
      on pet.id = appointment.pet_id
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at,
               revision.establishment_timezone_name, revision.revision_sequence
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason
        from public.appointment_reschedule_proposals as open_proposal
        where open_proposal.appointment_id = appointment.id
          and open_proposal.state = 'PENDING'
          and public.appointment_reschedule_proposal_is_actionable(
              open_proposal.id,
              statement_timestamp()
          )
        limit 1
    ) as pending_proposal on true
    where appointment.clinic_id = p_clinic_id
    order by appointment.created_at, appointment.id;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_schedule(uuid)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_schedule(uuid)
to authenticated;

-- ==================================================================
-- I. Communications. APPOINTMENT_RESCHEDULE_ACCEPTED is enqueued by the
--    resulting CONFIRMED revision (same recipients, created_at = the former
--    accepted_at, same uniqueness); APPOINTMENT_RESCHEDULE_PROPOSED is
--    unchanged. The origin check verifies the accepted revision through its
--    source Proposal instead of the removed duplicate pointer.
-- ==================================================================

create or replace function public.enqueue_appointment_communications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_type text;
begin
    if tg_table_name = 'appointment_schedule_revisions' then
        if new.revision_context = 'REQUESTED'
           and new.revision_sequence = 1 then
            resolved_type := 'APPOINTMENT_REQUESTED';

            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_schedule_revision_id, locale, created_at
            )
            select resolved_type, guardianship.user_id, appointment.id,
                   new.id, 'es-ES', new.created_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.created_at
              and guardianship.effective_end is null
            on conflict do nothing;
        elsif new.revision_context = 'CONFIRMED'
              and new.source_proposal_id is not null then
            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_reschedule_proposal_id,
                appointment_schedule_revision_id, locale, created_at
            )
            select 'APPOINTMENT_RESCHEDULE_ACCEPTED', guardianship.user_id,
                   appointment.id, new.source_proposal_id, new.id,
                   'es-ES', new.created_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.created_at
              and guardianship.effective_end is null
            on conflict do nothing;
        end if;

    elsif tg_table_name = 'appointment_lifecycle_events' then
        resolved_type := case new.to_state
            when 'CONFIRMED' then 'APPOINTMENT_CONFIRMED'
            when 'CANCELLED' then 'APPOINTMENT_CANCELLED'
            when 'COMPLETED' then 'APPOINTMENT_COMPLETED'
            when 'NO_SHOW' then 'APPOINTMENT_NO_SHOW'
            else null
        end;

        if resolved_type is not null then
            insert into public.transactional_communications (
                communication_type, recipient_user_id, appointment_id,
                appointment_lifecycle_event_id, locale, created_at
            )
            select resolved_type, guardianship.user_id, appointment.id,
                   new.id, 'es-ES', new.recorded_at
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = new.appointment_id
              and guardianship.effective_start <= new.recorded_at
              and guardianship.effective_end is null
            on conflict do nothing;
        end if;

    elsif tg_table_name = 'appointment_reschedule_proposals' then
        insert into public.transactional_communications (
            communication_type, recipient_user_id, appointment_id,
            appointment_reschedule_proposal_id, locale, created_at
        )
        select 'APPOINTMENT_RESCHEDULE_PROPOSED', guardianship.user_id,
               appointment.id, new.id, 'es-ES', new.created_at
        from public.appointments as appointment
        join public.guardianships as guardianship
          on guardianship.pet_id = appointment.pet_id
        where appointment.id = new.appointment_id
          and new.state = 'PENDING'
          and new.proposing_context = 'CLINIC'
          and guardianship.effective_start <= new.created_at
          and guardianship.effective_end is null
        on conflict do nothing;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enqueue_appointment_communications()
from public, anon, authenticated;

-- Proposal-side enqueueing is establishment only now.
drop trigger appointment_reschedule_proposals_enqueue_communication
on public.appointment_reschedule_proposals;

create trigger appointment_reschedule_proposals_enqueue_communication
after insert on public.appointment_reschedule_proposals
for each row execute function public.enqueue_appointment_communications();

create or replace function public.enforce_transactional_communication_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.organization_invitation_id is not null
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = new.organization_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'organization', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Organization Invitation'
            using errcode = '23514';
    end if;

    if new.guardianship_invitation_id is not null
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = new.guardianship_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'guardianship', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Guardianship Invitation'
            using errcode = '23514';
    end if;

    if new.appointment_lifecycle_event_id is not null
       and not exists (
           select 1 from public.appointment_lifecycle_events as event_record
           where event_record.id = new.appointment_lifecycle_event_id
             and event_record.appointment_id = new.appointment_id
             and (
                 (new.communication_type = 'APPOINTMENT_CONFIRMED' and event_record.to_state = 'CONFIRMED')
                 or (new.communication_type = 'APPOINTMENT_CANCELLED' and event_record.to_state = 'CANCELLED')
                 or (new.communication_type = 'APPOINTMENT_COMPLETED' and event_record.to_state = 'COMPLETED')
                 or (new.communication_type = 'APPOINTMENT_NO_SHOW' and event_record.to_state = 'NO_SHOW')
             )
       ) then
        raise exception 'Communication lifecycle origin does not match its Appointment and type'
            using errcode = '23514';
    end if;

    if new.appointment_reschedule_proposal_id is not null
       and not exists (
           select 1 from public.appointment_reschedule_proposals as proposal
           where proposal.id = new.appointment_reschedule_proposal_id
             and proposal.appointment_id = new.appointment_id
              and (
                  new.appointment_schedule_revision_id is null
                  or exists (
                      select 1
                      from public.appointment_schedule_revisions as resulting_revision
                      where resulting_revision.id = new.appointment_schedule_revision_id
                        and resulting_revision.source_proposal_id = proposal.id
                  )
              )
              and (
                  new.communication_type <> 'APPOINTMENT_RESCHEDULE_PROPOSED'
                  or proposal.proposing_context = 'CLINIC'
              )
       ) then
        raise exception 'Communication Proposal origin does not match its Appointment or revision'
            using errcode = '23514';
    end if;

    if new.appointment_schedule_revision_id is not null
       and not exists (
           select 1 from public.appointment_schedule_revisions as revision
           where revision.id = new.appointment_schedule_revision_id
             and revision.appointment_id = new.appointment_id
             and revision.revision_context = case
                 when new.communication_type = 'APPOINTMENT_REQUESTED'
                     then 'REQUESTED'
                 else 'CONFIRMED'
             end
       ) then
        raise exception 'Communication Schedule Revision origin does not match its Appointment'
            using errcode = '23514';
    end if;

    -- Establishment-time invariant only. A Communication created for a
    -- then-current Guardian stays valid historical intent after the
    -- Guardianship ends; later delivery eligibility is governed by
    -- communication_delivery_is_currently_eligible and the suppression sweeps.
    -- Re-checking here on an immutable-row bookkeeping UPDATE (for example the
    -- fanout_materialized_at freeze) would abort dispatch instead of suppressing
    -- the former-Guardian destination.
    if tg_op = 'INSERT'
       and new.recipient_user_id is not null
       and new.appointment_id is not null
       and not exists (
           select 1
           from public.appointments as appointment
           join public.guardianships as guardianship
             on guardianship.pet_id = appointment.pet_id
           where appointment.id = new.appointment_id
             and guardianship.user_id = new.recipient_user_id
             and guardianship.effective_start <= new.created_at
             and guardianship.effective_end is null
       ) then
        raise exception 'Appointment Communication recipient must be a current Guardian'
            using errcode = '23514';
    end if;

    if tg_op = 'UPDATE' then
        if old.id is distinct from new.id
           or old.communication_type is distinct from new.communication_type
           or old.recipient_user_id is distinct from new.recipient_user_id
           or old.recipient_email is distinct from new.recipient_email
           or old.locale is distinct from new.locale
           or old.organization_invitation_id is distinct from new.organization_invitation_id
           or old.guardianship_invitation_id is distinct from new.guardianship_invitation_id
           or old.appointment_id is distinct from new.appointment_id
           or old.appointment_lifecycle_event_id is distinct from new.appointment_lifecycle_event_id
           or old.appointment_reschedule_proposal_id is distinct from new.appointment_reschedule_proposal_id
           or old.appointment_schedule_revision_id is distinct from new.appointment_schedule_revision_id
           or old.secret_envelope_version is distinct from new.secret_envelope_version
           or old.secret_key_version is distinct from new.secret_key_version
           or old.secret_algorithm is distinct from new.secret_algorithm
           or old.secret_aad_context is distinct from new.secret_aad_context
           or old.created_at is distinct from new.created_at
           or (
               old.fanout_materialized_at is not null
               and new.fanout_materialized_at is distinct from
                   old.fanout_materialized_at
           )
           or (old.secret_consumed_at is not null and new.secret_consumed_at is distinct from old.secret_consumed_at)
           or (old.secret_consumed_at is null and new.secret_consumed_at is null and (
               old.secret_nonce is distinct from new.secret_nonce
               or old.secret_ciphertext is distinct from new.secret_ciphertext
           )) then
            raise exception 'Communication identity, origin, recipient, and encrypted handoff are immutable'
                using errcode = '23514';
        end if;

        if old.secret_consumed_at is null and new.secret_consumed_at is not null
           and (new.secret_nonce is not null or new.secret_ciphertext is not null) then
            raise exception 'Consuming an Invitation secret must erase its encrypted payload'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_transactional_communication_integrity()
from public, anon, authenticated;

alter table public.appointment_reschedule_proposals enable trigger user;

commit;

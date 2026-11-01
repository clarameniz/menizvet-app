-- Professional calendar reads — Phase 1, second part (SPEC-APT-012 §14,
-- BR-56–BR-59).
--
-- Additive only. Every existing RPC keeps its signature, body, and grants.
--
--   1. appointments_active_clinic_idx — partial index on the non-terminal
--      Appointments of a Clinic (justified in §1).
--   2. clinic_pending_appointments(uuid, uuid) — internal. The one
--      classification of a Clinic's Pending work for one acting User, at the
--      statement instant (BR-57). Shared by the Pending page and its summary.
--   3. get_clinic_appointment_day(uuid, date) — the calendar Appointments of
--      one Clinic-local date (BR-56).
--   4. get_clinic_appointment_pending(uuid, integer, timestamptz, uuid,
--      integer) — one page of classified Pending work, each row carrying the
--      whole classification's per-category totals (BR-57).
--   5. get_clinic_appointment_pending_summary(uuid) — the per-category counts
--      of that same classification (BR-58).
--   6. get_clinic_appointment_history(uuid, timestamptz, uuid, integer) —
--      one keyset page of terminal Appointments (BR-59).
--
-- No table, column, constraint, capability, lifecycle state, transition, or
-- write contract changes.

begin;

-- ==================================================================
-- 1. Non-terminal Appointments of a Clinic.
-- ==================================================================

-- The Pending reads start from a Clinic's REQUESTED and CONFIRMED
-- Appointments. Measured locally (rolled back) on a Clinic with 100 000
-- terminal and 3 000 open Appointments (233 000 overall): selecting the
-- candidates fell from a parallel sequential scan (~16 ms) to an index scan
-- (<1 ms), and the complete Pending page and summary by ~10–15 %
-- (~103 -> ~90 ms with 100 open proposals). Only state changes touch it.
create index appointments_active_clinic_idx
on public.appointments (clinic_id)
where lifecycle_state in ('REQUESTED', 'CONFIRMED');

-- ==================================================================
-- 2. Pending classification (SPEC-APT-012 BR-57). Internal.
-- ==================================================================

-- Classifies EVERY non-terminal Appointment of the Clinic for the acting
-- User at statement_timestamp(), so reason, category, rank, order and
-- membership never depend on which page is read. The derived proposal facts
-- it needs — whether the actionable PENDING proposal exists, its proposing
-- context, and its current feasibility — are computed with exactly the
-- predicates of the schedule projection, and only where they can change the
-- acting User's result.
create function public.clinic_pending_appointments(
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
security definer
set search_path = ''
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
    -- Every non-terminal Appointment with the facts that need no proposal.
    base_candidate as materialized (
        select appointment.id,
               appointment.lifecycle_state,
               current_revision.scheduled_start_at,
               encounter.has_encounter,
               -- REQUEST_DECISION's actor condition, stated once: on a
               -- REQUESTED Appointment this actor could confirm or propose an
               -- alternative (with the Entitlement) or cancel (without an
               -- Encounter), were no actionable proposal open.
               appointment.lifecycle_state = 'REQUESTED'
               and ((context_row.has_appointment_management
                     and (actor.can_confirm or actor.can_reschedule))
                    or (actor.can_cancel and not encounter.has_encounter)) as can_decide_request
        from public.appointments as appointment
        cross join actor
        cross join clinic_context as context_row
        cross join lateral (
            select revision.scheduled_start_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
            order by revision.revision_sequence desc
            limit 1
        ) as current_revision
        cross join lateral (
            select exists (
                select 1
                from public.clinical_encounters as encounter_row
                where encounter_row.appointment_id = appointment.id
            ) as has_encounter
        ) as encounter
        where appointment.clinic_id = p_clinic_id
          and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED')
    ),
    -- The proposal facts, evaluated only where they can change this actor's
    -- result. Materialized so each is evaluated once, not once per CASE arm.
    candidate as materialized (
        select base_row.*,
               pending_proposal.proposing_context,
               -- Feasibility decides only PROPOSAL_NOT_FEASIBLE versus
               -- AWAITING_GUARDIAN: Clinic proposals, actors who may withdraw.
               case
                   when pending_proposal.proposing_context = 'CLINIC' and actor.can_reschedule
                       then public.appointment_reschedule_proposal_is_currently_feasible(
                                pending_proposal.id,
                                (select timezone_row.valid_timezone_name from clinic_timezone as timezone_row)
                            )
               end as currently_feasible
        from base_candidate as base_row
        cross join actor
        left join lateral (
            select open_proposal.id, open_proposal.proposing_context
            from public.appointment_reschedule_proposals as open_proposal
            where open_proposal.appointment_id = base_row.id
              and open_proposal.state = 'PENDING'
              -- An actionable proposal matters only for the proposal reasons
              -- (APPOINTMENT_RESCHEDULE) or by withholding REQUEST_DECISION;
              -- otherwise this actor's result is the same with or without it.
              and (actor.can_reschedule or base_row.can_decide_request)
              -- Cheap necessary conditions of actionability (a PENDING
              -- proposal's base is the current revision), so lapsed proposals
              -- skip the costly authority check; the helper still decides.
              and open_proposal.proposed_start_at > statement_timestamp()
              and base_row.scheduled_start_at > statement_timestamp()
              and public.appointment_reschedule_proposal_is_actionable(
                  open_proposal.id,
                  statement_timestamp()
              )
            limit 1
        ) as pending_proposal on true
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
                        and candidate.can_decide_request
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

revoke all privileges
on function public.clinic_pending_appointments(uuid, uuid)
from public, anon, authenticated;

-- ==================================================================
-- 3. Calendar Appointments of one day (SPEC-APT-012 BR-56).
-- ==================================================================

create function public.get_clinic_appointment_day(
    p_clinic_id uuid,
    p_day date
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    requesting_user_id uuid,
    requester_display_name text,
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
    pending_reschedule_reason text,
    current_schedule_source_proposal_id uuid,
    current_schedule_source_proposing_context text,
    pending_reschedule_currently_feasible boolean,
    cancellation_reason text,
    has_clinical_encounter boolean
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

    if p_day is null or extract(year from p_day) not between 2000 and 2999 then
        raise exception 'Calendar day is invalid'
            using errcode = '22023';
    end if;

    -- The same membership definition as the month counts (BR-53), projected
    -- only for that day's Appointments.
    return query
    select projected.*
    from public.project_clinic_appointments(
        p_clinic_id,
        array(
            select calendar.appointment_id
            from public.clinic_calendar_appointments(p_clinic_id, p_day, p_day) as calendar
        )
    ) as projected
    order by projected.current_scheduled_start_at, projected.id;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_day(uuid, date)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_day(uuid, date)
to authenticated;

-- ==================================================================
-- 4. One page of Pending work (SPEC-APT-012 BR-57).
-- ==================================================================

create function public.get_clinic_appointment_pending(
    p_clinic_id uuid,
    p_after_rank integer default null,
    p_after_start_at timestamptz default null,
    p_after_id uuid default null,
    p_limit integer default 50
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    requesting_user_id uuid,
    requester_display_name text,
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
    pending_reschedule_reason text,
    current_schedule_source_proposal_id uuid,
    current_schedule_source_proposing_context text,
    pending_reschedule_currently_feasible boolean,
    cancellation_reason text,
    has_clinical_encounter boolean,
    pending_reason text,
    pending_category text,
    pending_rank integer,
    action_required_count integer,
    awaiting_guardian_count integer,
    informational_count integer
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

    -- The cursor is the complete (rank, start, id) of the last row of the
    -- previous page, or entirely absent for the first page.
    if p_limit is null or p_limit not between 1 and 100
       or num_nulls(p_after_rank, p_after_start_at, p_after_id) not in (0, 3)
       or (p_after_rank is not null and p_after_rank not between 1 and 5) then
        raise exception 'Pending page is invalid'
            using errcode = '22023';
    end if;

    -- 1) classify every candidate once, 2) count its categories and order and
    -- cut the page on that same classification, 3) project the full rows of
    -- the page only — all in one statement, so one instant decides everything.
    -- Every row carries the totals of the whole classification, independent
    -- of cursor and limit; an empty page carries none (BR-57).
    return query
    with classified as materialized (
        select pending.*
        from public.clinic_pending_appointments(p_clinic_id, acting_user_id) as pending
    ),
    totals as materialized (
        select (count(*) filter (where classified.pending_category = 'ACTION_REQUIRED'))::integer as action_required,
               (count(*) filter (where classified.pending_category = 'AWAITING_GUARDIAN'))::integer as awaiting_guardian,
               (count(*) filter (where classified.pending_category = 'INFORMATIONAL'))::integer as informational
        from classified
    ),
    page as materialized (
        select classified.*
        from classified
        where p_after_rank is null
           or (classified.pending_rank, classified.scheduled_start_at, classified.appointment_id)
              > (p_after_rank, p_after_start_at, p_after_id)
        order by classified.pending_rank, classified.scheduled_start_at, classified.appointment_id
        limit p_limit
    )
    select projected.*, page.pending_reason, page.pending_category, page.pending_rank,
           totals.action_required, totals.awaiting_guardian, totals.informational
    from public.project_clinic_appointments(
        p_clinic_id,
        array(select page_row.appointment_id from page as page_row)
    ) as projected
    join page
      on page.appointment_id = projected.id
    cross join totals
    order by page.pending_rank, page.scheduled_start_at, page.appointment_id;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)
to authenticated;

-- ==================================================================
-- 5. Pending summary (SPEC-APT-012 BR-58).
-- ==================================================================

create function public.get_clinic_appointment_pending_summary(
    p_clinic_id uuid
)
returns table (
    action_required_count integer,
    awaiting_guardian_count integer,
    informational_count integer
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
    select (count(*) filter (where pending.pending_category = 'ACTION_REQUIRED'))::integer,
           (count(*) filter (where pending.pending_category = 'AWAITING_GUARDIAN'))::integer,
           (count(*) filter (where pending.pending_category = 'INFORMATIONAL'))::integer
    from public.clinic_pending_appointments(p_clinic_id, acting_user_id) as pending;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_pending_summary(uuid)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_pending_summary(uuid)
to authenticated;

-- ==================================================================
-- 6. One keyset page of the History (SPEC-APT-012 BR-59).
-- ==================================================================

create function public.get_clinic_appointment_history(
    p_clinic_id uuid,
    p_before_start_at timestamptz default null,
    p_before_id uuid default null,
    p_limit integer default 30
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    requesting_user_id uuid,
    requester_display_name text,
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
    pending_reschedule_reason text,
    current_schedule_source_proposal_id uuid,
    current_schedule_source_proposing_context text,
    pending_reschedule_currently_feasible boolean,
    cancellation_reason text,
    has_clinical_encounter boolean
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

    if p_limit is null or p_limit not between 1 and 50
       or num_nulls(p_before_start_at, p_before_id) not in (0, 2) then
        raise exception 'History page is invalid'
            using errcode = '22023';
    end if;

    -- Keyset on (relevant scheduled start, id), descending. A terminal
    -- Appointment's relevant scheduled interval never changes (§4), so the key
    -- is stable. The start bound is a plain range condition so the
    -- start-time index can serve it; the tie on the cursor's start is
    -- resolved by id. Only the page's Appointments are projected.
    return query
    with page as materialized (
        select appointment.id as appointment_id,
               current_revision.scheduled_start_at
        from public.appointment_schedule_revisions as current_revision
        join public.appointments as appointment
          on appointment.id = current_revision.appointment_id
        where appointment.clinic_id = p_clinic_id
          and appointment.lifecycle_state in ('COMPLETED', 'NO_SHOW', 'CANCELLED', 'EXPIRED')
          and not exists (
              select 1
              from public.appointment_schedule_revisions as newer_revision
              where newer_revision.appointment_id = current_revision.appointment_id
                and newer_revision.revision_sequence > current_revision.revision_sequence
          )
          and current_revision.scheduled_start_at <= coalesce(p_before_start_at, 'infinity'::timestamptz)
          and (
              p_before_start_at is null
              or current_revision.scheduled_start_at < p_before_start_at
              or appointment.id < p_before_id
          )
        order by current_revision.scheduled_start_at desc, appointment.id desc
        limit p_limit
    )
    select projected.*
    from public.project_clinic_appointments(
        p_clinic_id,
        array(select page_row.appointment_id from page as page_row)
    ) as projected
    join page
      on page.appointment_id = projected.id
    order by page.scheduled_start_at desc, page.appointment_id desc;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)
to authenticated;

commit;

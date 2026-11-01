-- Paged Guardian Appointment reads — awaiting Clinic confirmation
-- (SPEC-APT-011 BR-37, BR-40; SPEC-APT-019 §5 "Appointment list").
--
-- The "My appointments" row gains one trailing column of BR-37:
--
--   awaiting_clinic_confirmation boolean — true exactly when the Appointment
--   is REQUESTED and the Schedule Revision that supplies its relevant
--   scheduled interval was established by accepting a Clinic proposal
--   (SPEC-APT-011 BR-33): the Guardian accepted the Clinic's alternative time
--   and the Clinic has not confirmed it yet. Derived from the revision's
--   normalized source-proposal provenance; never stored.
--
-- A function's result type cannot be changed in place, so the internal
-- projection and both reads of 20261117090000 are dropped and re-created
-- with their grants. Their parameters, authorization, order, keyset cursors,
-- limits, errors and every other column are unchanged. get_pet_appointments,
-- the detail and every Guardian operation are untouched. No table, column,
-- index, constraint, lifecycle state, transition or write contract changes.

begin;

drop function public.get_guardian_active_appointments(integer, timestamptz, uuid, integer);
drop function public.get_guardian_appointment_history(timestamptz, uuid, integer);
drop function public.project_guardian_appointments(uuid[]);

-- ==================================================================
-- 1. Compact Guardian Appointment row (SPEC-APT-011 BR-37). Internal.
-- ==================================================================

-- Projects only the columns the "My appointments" list needs, each with
-- exactly the value get_pet_appointments gives the same Appointment: the
-- relevant scheduled interval in its own establishment timezone, and the
-- proposing context of the actionable PENDING proposal (same predicate).
-- awaiting_clinic_confirmation applies BR-33 to the same current revision's
-- source proposal that get_pet_appointments exposes as
-- current_schedule_source_proposing_context.
-- It authorizes nothing: callers pass only Appointments they have already
-- restricted to the acting User's current Guardianships.
create function public.project_guardian_appointments(
    p_appointment_ids uuid[]
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    clinic_id uuid,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    pending_reschedule_proposing_context text,
    awaiting_clinic_confirmation boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        appointment.id,
        appointment.pet_id,
        pet.name,
        appointment.clinic_id,
        appointment.lifecycle_state,
        current_revision.scheduled_start_at,
        current_revision.scheduled_end_at,
        current_revision.establishment_timezone_name,
        pending_proposal.proposing_context,
        appointment.lifecycle_state = 'REQUESTED'
            and source_proposal.proposing_context is not distinct from 'CLINIC'
    from public.appointments as appointment
    join public.pets as pet
      on pet.id = appointment.pet_id
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at,
               revision.establishment_timezone_name, revision.source_proposal_id
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_reschedule_proposals as source_proposal
      on source_proposal.id = current_revision.source_proposal_id
    left join lateral (
        select open_proposal.proposing_context
        from public.appointment_reschedule_proposals as open_proposal
        where open_proposal.appointment_id = appointment.id
          and open_proposal.state = 'PENDING'
          and public.appointment_reschedule_proposal_is_actionable(
              open_proposal.id,
              statement_timestamp()
          )
        limit 1
    ) as pending_proposal on true
    where appointment.id = any (p_appointment_ids);
$$;

revoke all privileges
on function public.project_guardian_appointments(uuid[])
from public, anon, authenticated, service_role;

-- ==================================================================
-- 2. One page of Active Appointments (SPEC-APT-011 BR-38). Unchanged
--    except for the trailing BR-37 column before active_rank.
-- ==================================================================

create function public.get_guardian_active_appointments(
    p_after_rank integer default null,
    p_after_start_at timestamptz default null,
    p_after_id uuid default null,
    p_limit integer default 20
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    clinic_id uuid,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    pending_reschedule_proposing_context text,
    awaiting_clinic_confirmation boolean,
    active_rank integer
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

    -- The cursor is the complete (rank, start, id) of the last row of the
    -- previous page, or entirely absent for the first page.
    if p_limit is null or p_limit not between 1 and 50
       or num_nulls(p_after_rank, p_after_start_at, p_after_id) not in (0, 3)
       or (p_after_rank is not null and p_after_rank not in (1, 2)) then
        raise exception 'Guardian appointment page is invalid'
            using errcode = '22023';
    end if;

    -- 1) restrict to the Pets the acting User currently guards — the
    -- Guardianship condition of get_pet_appointments — before anything is
    -- ordered or cut; 2) rank against one instant: start not yet reached (1,
    -- ascending) before reached (2, descending); 3) cut the page on the key;
    -- 4) project only the page.
    return query
    with ranked as materialized (
        select appointment.id as appointment_id,
               current_revision.scheduled_start_at,
               case
                   when current_revision.scheduled_start_at > statement_timestamp() then 1
                   else 2
               end as rank
        from public.appointments as appointment
        cross join lateral (
            select revision.scheduled_start_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
            order by revision.revision_sequence desc
            limit 1
        ) as current_revision
        where appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED')
          and appointment.pet_id in (
              select guardianship.pet_id
              from public.guardianships as guardianship
              where guardianship.user_id = acting_user_id
                and guardianship.effective_end is null
          )
    ),
    page as materialized (
        select ranked.*
        from ranked
        where p_after_rank is null
           or (p_after_rank = 1
               and (ranked.rank = 2
                    or (ranked.rank = 1
                        and (ranked.scheduled_start_at, ranked.appointment_id)
                            > (p_after_start_at, p_after_id))))
           or (p_after_rank = 2
               and ranked.rank = 2
               and (ranked.scheduled_start_at, ranked.appointment_id)
                   < (p_after_start_at, p_after_id))
        order by ranked.rank,
                 case when ranked.rank = 1 then ranked.scheduled_start_at end,
                 case when ranked.rank = 1 then ranked.appointment_id end,
                 case when ranked.rank = 2 then ranked.scheduled_start_at end desc,
                 case when ranked.rank = 2 then ranked.appointment_id end desc
        limit p_limit
    )
    select projected.*, page.rank
    from public.project_guardian_appointments(
        array(select page_row.appointment_id from page as page_row)
    ) as projected
    join page
      on page.appointment_id = projected.id
    order by page.rank,
             case when page.rank = 1 then page.scheduled_start_at end,
             case when page.rank = 1 then page.appointment_id end,
             case when page.rank = 2 then page.scheduled_start_at end desc,
             case when page.rank = 2 then page.appointment_id end desc;
end;
$$;

revoke all privileges
on function public.get_guardian_active_appointments(integer, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;

grant execute
on function public.get_guardian_active_appointments(integer, timestamptz, uuid, integer)
to authenticated;

-- ==================================================================
-- 3. One page of the Guardian History (SPEC-APT-011 BR-39). Unchanged
--    except for the trailing BR-37 column (always false here).
-- ==================================================================

create function public.get_guardian_appointment_history(
    p_before_start_at timestamptz default null,
    p_before_id uuid default null,
    p_limit integer default 20
)
returns table (
    id uuid,
    pet_id uuid,
    pet_name text,
    clinic_id uuid,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    pending_reschedule_proposing_context text,
    awaiting_clinic_confirmation boolean
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

    if p_limit is null or p_limit not between 1 and 50
       or num_nulls(p_before_start_at, p_before_id) not in (0, 2) then
        raise exception 'Guardian appointment page is invalid'
            using errcode = '22023';
    end if;

    -- Keyset on (relevant scheduled start, id), descending, over the terminal
    -- Appointments of the Pets the acting User currently guards. A terminal
    -- Appointment's relevant interval never changes (§4), so the key is
    -- stable. Only the page's Appointments are projected.
    return query
    with page as materialized (
        select appointment.id as appointment_id,
               current_revision.scheduled_start_at
        from public.appointments as appointment
        cross join lateral (
            select revision.scheduled_start_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
            order by revision.revision_sequence desc
            limit 1
        ) as current_revision
        where appointment.lifecycle_state in ('COMPLETED', 'NO_SHOW', 'CANCELLED', 'EXPIRED')
          and appointment.pet_id in (
              select guardianship.pet_id
              from public.guardianships as guardianship
              where guardianship.user_id = acting_user_id
                and guardianship.effective_end is null
          )
          and (
              p_before_start_at is null
              or (current_revision.scheduled_start_at, appointment.id)
                 < (p_before_start_at, p_before_id)
          )
        order by current_revision.scheduled_start_at desc, appointment.id desc
        limit p_limit
    )
    select projected.*
    from public.project_guardian_appointments(
        array(select page_row.appointment_id from page as page_row)
    ) as projected
    join page
      on page.appointment_id = projected.id
    order by page.scheduled_start_at desc, page.appointment_id desc;
end;
$$;

revoke all privileges
on function public.get_guardian_appointment_history(timestamptz, uuid, integer)
from public, anon, authenticated, service_role;

grant execute
on function public.get_guardian_appointment_history(timestamptz, uuid, integer)
to authenticated;

commit;

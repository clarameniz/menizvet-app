-- Professional calendar reads — Phase 1 (SPEC-APT-012 §14, BR-51–BR-55).
--
-- Additive only. get_clinic_appointment_schedule(uuid) is NOT changed: the
-- installed Android versions keep depending on it.
--
--   1. project_clinic_appointments(uuid, uuid[]) — internal. The one
--      projection of Clinic Appointment rows for the new professional reads,
--      column for column the contract of get_clinic_appointment_schedule
--      (BR-41–BR-49), restricted to the given Appointments of one Clinic. Not
--      executable by clients.
--   2. clinic_calendar_appointments(uuid, date, date) — internal. The single
--      definition of which Appointments belong to which Clinic-local calendar
--      day (BR-53): the month counts use it now and the planned day read will
--      use it, so a day's count always equals that day's list.
--   3. get_clinic_appointment(uuid, uuid) — one Appointment of one Clinic
--      (BR-52), resolved in SQL, with the same authority as the schedule.
--   4. get_clinic_appointment_month_counts(uuid, integer, integer) — the number
--      of calendar Appointments per Clinic-local day of one month (BR-54).
--
-- One index is added (appointment_schedule_revisions_start_idx, justified in
-- §2). No table, column, constraint, capability, state, transition, or write
-- contract changes.

begin;

-- ==================================================================
-- 1. Internal projection (same columns and semantics as the schedule).
-- ==================================================================

create function public.project_clinic_appointments(
    p_clinic_id uuid,
    p_appointment_ids uuid[]
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
language sql
stable
security definer
set search_path = ''
as $$
    -- The Clinic's current timezone, validated once (NULL when invalid). It is
    -- only consumed by the pending-proposal feasibility below, exactly as in
    -- get_clinic_appointment_schedule.
    with clinic_timezone as materialized (
        select case
                   when public.clinic_timezone_name_is_valid(clinic.scheduling_timezone_name)
                       then clinic.scheduling_timezone_name
               end as valid_timezone_name
        from public.clinics as clinic
        where clinic.id = p_clinic_id
    )
    select
        appointment.id,
        appointment.pet_id,
        pet.name,
        appointment.requesting_user_id,
        -- SPEC-APT-012 BR-49: the original requester's current display name.
        nullif(btrim(requester_profile.display_name, E' \t\n\r\f\013'), ''),
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
        pending_proposal.reason,
        source_proposal.id,
        source_proposal.proposing_context,
        pending_proposal.currently_feasible,
        cancellation_event.reason,
        -- SPEC-APT-012 BR-48: existence only, whatever the Encounter state.
        exists (
            select 1
            from public.clinical_encounters as encounter_row
            where encounter_row.appointment_id = appointment.id
        )
    from public.appointments as appointment
    join public.pets as pet
      on pet.id = appointment.pet_id
    left join public.user_profiles as requester_profile
      on requester_profile.user_id = appointment.requesting_user_id
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at,
               revision.establishment_timezone_name, revision.revision_sequence,
               revision.source_proposal_id
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_reschedule_proposals as source_proposal
      on source_proposal.id = current_revision.source_proposal_id
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason,
               public.appointment_reschedule_proposal_is_currently_feasible(
                   open_proposal.id,
                   (select timezone_row.valid_timezone_name from clinic_timezone as timezone_row)
               ) as currently_feasible
        from public.appointment_reschedule_proposals as open_proposal
        where open_proposal.appointment_id = appointment.id
          and open_proposal.state = 'PENDING'
          and public.appointment_reschedule_proposal_is_actionable(
              open_proposal.id,
              statement_timestamp()
          )
        limit 1
    ) as pending_proposal on true
    left join public.appointment_lifecycle_events as cancellation_event
      on cancellation_event.appointment_id = appointment.id
     and cancellation_event.to_state = 'CANCELLED'
     and appointment.lifecycle_state = 'CANCELLED'
    where appointment.clinic_id = p_clinic_id
      and appointment.id = any(p_appointment_ids)
    order by appointment.created_at, appointment.id;
$$;

revoke all privileges
on function public.project_clinic_appointments(uuid, uuid[])
from public, anon, authenticated;

-- ==================================================================
-- 2. Internal calendar membership (SPEC-APT-012 BR-53).
-- ==================================================================

-- Lets a calendar window read only the Schedule Revisions that start inside
-- it instead of every Appointment the Clinic ever had. Measured locally with
-- 20 000 Appointments in one Clinic and 110 000 overall: a one-month count
-- fell from ~50 ms (clinic-driven, one lookup per active Appointment) to
-- ~5 ms (≈600 revisions in the window). Revisions are written rarely, so the
-- write cost is negligible.
create index appointment_schedule_revisions_start_idx
on public.appointment_schedule_revisions (scheduled_start_at);

-- An Appointment is on the calendar of the Clinic-local date on which its
-- relevant scheduled interval (§4) starts, read in the timezone that interval
-- was established in (SPEC-APT-013 BR-47–BR-49) — the date the Professional
-- client shows for it. Only REQUESTED, CONFIRMED, COMPLETED and NO_SHOW are
-- calendar Appointments; CANCELLED and EXPIRED are not. The stored state is
-- used as is: a past REQUESTED that expiry has not materialized yet stays a
-- REQUESTED calendar Appointment. A pending proposal never moves or adds a day.
-- p_from_date and p_to_date are inclusive.
create function public.clinic_calendar_appointments(
    p_clinic_id uuid,
    p_from_date date,
    p_to_date date
)
returns table (
    appointment_id uuid,
    local_date date
)
language sql
stable
security definer
set search_path = ''
as $$
    select calendar_row.appointment_id, calendar_row.local_date
    from (
        select appointment.id as appointment_id,
               (current_revision.scheduled_start_at
                   at time zone current_revision.establishment_timezone_name)::date as local_date
        from public.appointment_schedule_revisions as current_revision
        join public.appointments as appointment
          on appointment.id = current_revision.appointment_id
        where appointment.clinic_id = p_clinic_id
          and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW')
          -- The relevant scheduled interval is the latest Schedule Revision
          -- (§4); (appointment_id, revision_sequence) is unique, so exactly one
          -- revision per Appointment qualifies. Written as an anti-join so the
          -- planner may start from the Clinic or from the start-time window.
          and not exists (
              select 1
              from public.appointment_schedule_revisions as newer_revision
              where newer_revision.appointment_id = current_revision.appointment_id
                and newer_revision.revision_sequence > current_revision.revision_sequence
          )
          -- Coarse instant window: every civil UTC offset lies within
          -- -12:00…+14:00, so a start whose local date is in the range lies
          -- within one day either side of the range read as UTC.
          and current_revision.scheduled_start_at
              >= (p_from_date - 1)::timestamp at time zone 'UTC'
          and current_revision.scheduled_start_at
              < (p_to_date + 2)::timestamp at time zone 'UTC'
    ) as calendar_row
    where calendar_row.local_date between p_from_date and p_to_date;
$$;

revoke all privileges
on function public.clinic_calendar_appointments(uuid, date, date)
from public, anon, authenticated;

-- ==================================================================
-- 3. One Appointment of one Clinic (SPEC-APT-012 BR-52).
-- ==================================================================

create function public.get_clinic_appointment(
    p_clinic_id uuid,
    p_appointment_id uuid
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

    -- One uniform outcome for a missing or foreign Clinic, missing authority,
    -- an unknown Appointment, and an Appointment of another Clinic.
    if not public.user_has_clinic_capability(
           acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE'
       )
       or not exists (
           select 1
           from public.appointments as appointment
           where appointment.id = p_appointment_id
             and appointment.clinic_id = p_clinic_id
       ) then
        raise exception 'Clinic Appointment unavailable'
            using errcode = '42501';
    end if;

    return query
    select projected.*
    from public.project_clinic_appointments(p_clinic_id, array[p_appointment_id]) as projected;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment(uuid, uuid)
to authenticated;

-- ==================================================================
-- 4. Calendar Appointments per day of one month (SPEC-APT-012 BR-54).
-- ==================================================================

create function public.get_clinic_appointment_month_counts(
    p_clinic_id uuid,
    p_year integer,
    p_month integer
)
returns table (
    day date,
    appointment_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    month_start date;
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

    if p_year is null or p_year not between 2000 and 2999
       or p_month is null or p_month not between 1 and 12 then
        raise exception 'Calendar month is invalid'
            using errcode = '22023';
    end if;

    month_start := make_date(p_year, p_month, 1);

    return query
    select calendar.local_date, count(*)::integer
    from public.clinic_calendar_appointments(
        p_clinic_id,
        month_start,
        (month_start + interval '1 month')::date - 1
    ) as calendar
    group by calendar.local_date
    order by calendar.local_date;
end;
$$;

revoke all privileges
on function public.get_clinic_appointment_month_counts(uuid, integer, integer)
from public, anon, authenticated;

grant execute
on function public.get_clinic_appointment_month_counts(uuid, integer, integer)
to authenticated;

commit;

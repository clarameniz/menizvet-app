-- Confirmed Appointment reschedule — SPEC-APT-005 BR-23–BR-32,
-- SPEC-APT-006 BR-28–BR-33, SPEC-APT-016 (Clinic withdrawal),
-- SPEC-APT-017 (professional candidate times), SPEC-APT-013 BR-68–BR-70,
-- SPEC-COM-003 BR-70.
--
-- Slice 9 (20260826163000) created propose/accept with a caller-supplied end,
-- no reviewed-context token, no creation-time feasibility, no Clinical
-- Encounter rule, and no withdrawal. This forward-only migration:
--
--   A. extends appointment_reschedule_proposals with the WITHDRAWN state and
--      its withdrawn_at / withdrawn_by_user_id facts, rebuilds the shape
--      constraint, and extends the integrity trigger (PENDING -> WITHDRAWN only
--      for an actionable CLINIC proposal; withdrawn_at is database-observed);
--      the partial unique index (state = 'PENDING' and non_actionable_at is
--      null) already frees the slot for WITHDRAWN rows and is unchanged;
--   B. adds "no Clinical Encounter" to appointment_reschedule_proposal_is_actionable
--      (signature unchanged), so reads, the ACCEPTED/WITHDRAWN trigger checks,
--      and Communication delivery all inherit it;
--   C. adds shared internal feasibility helpers used by propose, accept, and
--      the candidate read: a timezone-parameterized Veterinarian coverage
--      helper (veterinarian_availability_covers_interval keeps its signature
--      and behavior and delegates to it, mirroring
--      20260921093000_candidate_availability_lookup_performance.sql), a known
--      confirmed-commitment conflict predicate identical to the deferred
--      assert_veterinarian_confirmed_commitment_conflict_free overlap rule but
--      excluding the Appointment being rescheduled, and one infeasibility
--      classifier whose Veterinarian outcomes are deliberately generic;
--   D. replaces the 9-argument propose_confirmed_appointment_reschedule with a
--      start-only form: the end is the resolved start plus the elapsed
--      duration D of the base CONFIRMED revision, applied in whole
--      microseconds so no calendar-day arithmetic can occur; the Clinic's
--      standard duration is never read; CLINIC calls carry the expected
--      confirmed revision sequence (stale -> plain P0001, zero writes);
--   E. re-creates accept_appointment_reschedule_proposal (same signature) with
--      an explicit Clinical Encounter rejection, the shared feasibility
--      preflight, and a final authoritative actionability guard; the stored
--      interval is used unchanged and the deferred Veterinarian conflict
--      constraint remains authoritative at commit;
--   F. adds withdraw_appointment_reschedule_proposal (SPEC-APT-016);
--   G. adds get_appointment_reschedule_candidate_start_times (SPEC-APT-017);
--   H. makes APPOINTMENT_RESCHEDULE_PROPOSED delivery eligibility use the
--      authoritative actionability predicate.
--
-- resolve_clinic_appointment_interval(...) is no longer called by any
-- function; it is left in place (forward-only, no dependency on it).
-- get_pet_appointments and get_clinic_appointment_schedule are unchanged: they
-- already project only actionable proposals through
-- appointment_reschedule_proposal_is_actionable.
-- No existing row is changed: existing proposals are PENDING or ACCEPTED and
-- satisfy the rebuilt constraints with NULL withdrawn facts.

begin;

-- ==================================================================
-- A. WITHDRAWN proposal state (SPEC-APT-016 BR-5, BR-6).
-- ==================================================================

alter table public.appointment_reschedule_proposals
    add column withdrawn_at timestamptz,
    add column withdrawn_by_user_id uuid;

alter table public.appointment_reschedule_proposals
    add constraint appointment_reschedule_proposals_withdrawn_by_user_id_fkey
        foreign key (withdrawn_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict;

alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_state_check;

alter table public.appointment_reschedule_proposals
    add constraint appointment_reschedule_proposals_state_check
        check (state in ('PENDING', 'ACCEPTED', 'WITHDRAWN'));

alter table public.appointment_reschedule_proposals
    add constraint appointment_reschedule_proposals_withdrawn_at_check
        check (
            withdrawn_at is null
            or (isfinite(withdrawn_at) and withdrawn_at >= created_at)
        );

-- SPEC-APT-016 BR-1: Phase 1 withdrawal is Clinic-originated only.
alter table public.appointment_reschedule_proposals
    add constraint appointment_reschedule_proposals_withdrawal_context_check
        check (state <> 'WITHDRAWN' or proposing_context = 'CLINIC');

alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_shape_check;

-- Establishment-shape backstop; the authoritative transition guard is the
-- enforce_appointment_reschedule_proposal_integrity() trigger below.
alter table public.appointment_reschedule_proposals
    add constraint appointment_reschedule_proposals_shape_check
        check (
            (
                state = 'PENDING'
                and accepted_at is null
                and accepted_by_user_id is null
                and accepting_context is null
                and resulting_confirmed_revision_id is null
                and withdrawn_at is null
                and withdrawn_by_user_id is null
                and (
                    (non_actionable_at is null and non_actionable_reason is null)
                    or
                    (non_actionable_at is not null and non_actionable_reason is not null)
                )
            )
            or
            (
                state = 'ACCEPTED'
                and accepted_at is not null
                and accepted_by_user_id is not null
                and accepting_context is not null
                and resulting_confirmed_revision_id is not null
                and non_actionable_at is null
                and non_actionable_reason is null
                and withdrawn_at is null
                and withdrawn_by_user_id is null
            )
            or
            (
                state = 'WITHDRAWN'
                and accepted_at is null
                and accepted_by_user_id is null
                and accepting_context is null
                and resulting_confirmed_revision_id is null
                and non_actionable_at is null
                and non_actionable_reason is null
                and withdrawn_at is not null
                and withdrawn_by_user_id is not null
            )
        );

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
        if new.state <> 'PENDING'
           or new.non_actionable_at is not null
           or new.non_actionable_reason is not null
           or new.accepted_at is not null
           or new.accepted_by_user_id is not null
           or new.accepting_context is not null
           or new.resulting_confirmed_revision_id is not null
           or new.withdrawn_at is not null
           or new.withdrawn_by_user_id is not null then
            raise exception 'Appointment Reschedule Proposal must be established as PENDING with no acceptance facts'
                using errcode = '23514';
        end if;

        return new;
    end if;

    -- tg_op = 'UPDATE'. ACCEPTED, WITHDRAWN, and permanently non-actionable
    -- PENDING rows are all final.
    if old.state <> 'PENDING' or old.non_actionable_at is not null then
        raise exception 'Accepted and non-actionable Appointment Reschedule Proposals are immutable'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.appointment_id is distinct from new.appointment_id
       or old.base_revision_id is distinct from new.base_revision_id
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

    -- Resolution times are observed database facts, not caller-authored
    -- history.
    if new.state = 'PENDING' and new.non_actionable_reason is not null then
        new.non_actionable_at := clock_timestamp();
    end if;

    if new.state = 'WITHDRAWN' then
        new.withdrawn_at := clock_timestamp();
    end if;

    if new.state = 'ACCEPTED'
       and not public.appointment_reschedule_proposal_is_actionable(
           old.id,
           clock_timestamp(),
           new.resulting_confirmed_revision_id
       ) then
        raise exception 'Only a currently actionable Appointment Reschedule Proposal may be accepted'
            using errcode = '23514';
    end if;

    if new.state = 'WITHDRAWN' then
        if old.proposing_context <> 'CLINIC' then
            raise exception 'Only a Clinic-originated Reschedule Proposal may be withdrawn'
                using errcode = '23514';
        end if;

        if not public.appointment_reschedule_proposal_is_actionable(
            old.id, clock_timestamp()
        ) then
            raise exception 'Only a currently actionable Appointment Reschedule Proposal may be withdrawn'
                using errcode = '23514';
        end if;
    end if;

    if not (
        (
            new.state = 'PENDING'
            and new.non_actionable_at is not null
            and new.non_actionable_reason is not null
            and new.accepted_at is null
            and new.accepted_by_user_id is null
            and new.accepting_context is null
            and new.resulting_confirmed_revision_id is null
            and new.withdrawn_at is null
            and new.withdrawn_by_user_id is null
        )
        or
        (
            new.state = 'ACCEPTED'
            and new.non_actionable_at is null
            and new.non_actionable_reason is null
            and new.accepted_at is not null
            and new.accepted_by_user_id is not null
            and new.accepting_context is not null
            and new.resulting_confirmed_revision_id is not null
            and new.withdrawn_at is null
            and new.withdrawn_by_user_id is null
        )
        or
        (
            new.state = 'WITHDRAWN'
            and new.non_actionable_at is null
            and new.non_actionable_reason is null
            and new.accepted_at is null
            and new.accepted_by_user_id is null
            and new.accepting_context is null
            and new.resulting_confirmed_revision_id is null
            and new.withdrawn_at is not null
            and new.withdrawn_by_user_id is not null
        )
    ) then
        raise exception 'A PENDING Appointment Reschedule Proposal may only become permanently non-actionable, ACCEPTED, or WITHDRAWN with complete transition facts'
            using errcode = '23514';
    end if;

    if new.state = 'PENDING' then
        if new.non_actionable_reason = 'BASE_REVISION_SUPERSEDED'
           and not exists (
               select 1
               from public.appointment_schedule_revisions as later_revision
               join public.appointment_schedule_revisions as base_revision
                 on base_revision.id = old.base_revision_id
               where later_revision.appointment_id = old.appointment_id
                 and later_revision.revision_context = 'CONFIRMED'
                 and later_revision.revision_sequence > base_revision.revision_sequence
           ) then
            raise exception 'Reschedule Proposal base revision has not been superseded'
                using errcode = '23514';
        elsif new.non_actionable_reason = 'PROPOSED_TIME_PASSED'
              and old.proposed_start_at > new.non_actionable_at then
            raise exception 'Reschedule Proposal time had not passed at the recorded resolution time'
                using errcode = '23514';
        elsif new.non_actionable_reason = 'PROPOSING_AUTHORITY_LOST'
              and exists (
                  select 1
                  from public.appointments as appointment
                  where appointment.id = old.appointment_id
                    and (
                        (
                            old.proposing_context = 'GUARDIAN'
                            and public.user_has_continuous_guardianship_since(
                                old.proposed_by_user_id,
                                appointment.pet_id,
                                old.created_at
                            )
                        )
                        or
                        (
                            old.proposing_context = 'CLINIC'
                            and public.user_has_continuous_clinic_reschedule_authority_since(
                                old.proposed_by_user_id,
                                appointment.clinic_id,
                                old.created_at
                            )
                        )
                    )
              ) then
            raise exception 'Reschedule Proposal proposing authority has remained continuous'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_reschedule_proposal_integrity()
from public, anon, authenticated;

-- ==================================================================
-- B. Actionability (SPEC-APT-005 BR-29, BR-31). Signature and every
--    existing condition unchanged; a Clinical Encounter for the Appointment
--    now makes the proposal non-actionable. Nothing is materialized for it:
--    an Encounter is permanent and propose rejects such Appointments, so the
--    derived outcome is final.
-- ==================================================================

create or replace function public.appointment_reschedule_proposal_is_actionable(
    p_proposal_id uuid,
    p_as_of timestamptz,
    p_ignored_resulting_revision_id uuid default null
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
          and proposal.non_actionable_at is null
          and appointment.lifecycle_state = 'CONFIRMED'
          and base_revision.revision_context = 'CONFIRMED'
          and base_revision.scheduled_start_at > p_as_of
          and proposal.proposed_start_at > p_as_of
          and not exists (
              select 1
              from public.clinical_encounters as encounter_row
              where encounter_row.appointment_id = proposal.appointment_id
          )
          and not exists (
              select 1
              from public.appointment_schedule_revisions as later_revision
              where later_revision.appointment_id = proposal.appointment_id
                and later_revision.revision_context = 'CONFIRMED'
                and later_revision.revision_sequence > base_revision.revision_sequence
                and later_revision.id is distinct from p_ignored_resulting_revision_id
          )
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
on function public.appointment_reschedule_proposal_is_actionable(uuid, timestamptz, uuid)
from public, anon, authenticated;

-- ==================================================================
-- C. Shared feasibility helpers (SPEC-APT-005 BR-28, SPEC-APT-006 BR-30,
--    SPEC-APT-017 BR-6). Internal only.
-- ==================================================================

-- Veterinarian Availability coverage with an already-validated Clinic
-- timezone: the exact segment-walking loop of
-- veterinarian_availability_covers_interval, relocated so repeat callers
-- (candidate generation) never re-scan pg_timezone_names per candidate.
create function public.veterinarian_interval_is_covered_by_timezone(
    p_veterinarian_clinic_assignment_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_clinic_timezone_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    local_start timestamp;
    local_end timestamp;
    segment_cursor timestamp;
    segment_date date;
    next_midnight timestamp;
    segment_end timestamp;
    segment_start_time time;
    segment_end_time time;
begin
    local_start := p_start_at at time zone p_clinic_timezone_name;
    local_end := p_end_at at time zone p_clinic_timezone_name;

    if local_start >= local_end then
        return false;
    end if;

    segment_cursor := local_start;

    while segment_cursor < local_end loop
        segment_date := segment_cursor::date;
        next_midnight := (segment_date + 1)::timestamp;
        segment_end := least(local_end, next_midnight);

        segment_start_time := segment_cursor::time;
        segment_end_time := case
            when segment_end = next_midnight then '24:00:00'::time
            else segment_end::time
        end;

        if not public.veterinarian_day_interval_is_covered(
            p_veterinarian_clinic_assignment_id, segment_date,
            segment_start_time, segment_end_time
        ) then
            return false;
        end if;

        segment_cursor := segment_end;
    end loop;

    return true;
end;
$$;

revoke all privileges
on function public.veterinarian_interval_is_covered_by_timezone(uuid, timestamptz, timestamptz, text)
from public, anon, authenticated;

-- Unchanged signature and externally observable behavior.
create or replace function public.veterinarian_availability_covers_interval(
    p_veterinarian_clinic_assignment_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    clinic_timezone_name text;
begin
    select clinic.scheduling_timezone_name
    into clinic_timezone_name
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_veterinarian_clinic_assignment_id;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        return false;
    end if;

    return public.veterinarian_interval_is_covered_by_timezone(
        p_veterinarian_clinic_assignment_id, p_start_at, p_end_at, clinic_timezone_name
    );
end;
$$;

revoke all privileges
on function public.veterinarian_availability_covers_interval(uuid, timestamptz, timestamptz)
from public, anon, authenticated;

-- A currently known CONFIRMED commitment of the same Veterinarian
-- Professional Profile (at any Clinic) overlapping [p_start_at, p_end_at),
-- other than p_excluding_appointment_id. Same overlap rule as the deferred,
-- authoritative assert_veterinarian_confirmed_commitment_conflict_free
-- (current Assignments, CONFIRMED Appointments, latest CONFIRMED revision,
-- strict half-open overlap); this preflight never replaces it.
create function public.veterinarian_has_known_confirmed_commitment_conflict(
    p_professional_profile_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_excluding_appointment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.appointment_veterinarian_assignments as other_assignment
        join public.veterinarian_clinic_assignments as other_clinic_assignment
          on other_clinic_assignment.id = other_assignment.veterinarian_clinic_assignment_id
        join public.appointments as other_appointment
          on other_appointment.id = other_assignment.appointment_id
        join lateral (
            select revision.scheduled_start_at, revision.scheduled_end_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = other_appointment.id
              and revision.revision_context = 'CONFIRMED'
            order by revision.revision_sequence desc
            limit 1
        ) as other_revision on true
        where other_clinic_assignment.professional_profile_id = p_professional_profile_id
          and other_assignment.effective_end is null
          and other_appointment.lifecycle_state = 'CONFIRMED'
          and other_appointment.id <> p_excluding_appointment_id
          and other_revision.scheduled_start_at < p_end_at
          and p_start_at < other_revision.scheduled_end_at
    )
$$;

revoke all privileges
on function public.veterinarian_has_known_confirmed_commitment_conflict(uuid, timestamptz, timestamptz, uuid)
from public, anon, authenticated;

-- NULL when the interval is feasible for the Appointment's reschedule;
-- otherwise one of CLINIC_AVAILABILITY, VETERINARIAN_ASSIGNMENT,
-- VETERINARIAN_UNAVAILABLE. Missing Veterinarian Availability and a known
-- conflict share VETERINARIAN_UNAVAILABLE so no conflict is ever disclosed
-- (SPEC-APT-005 BR-28, SPEC-APT-017 BR-9).
create function public.appointment_reschedule_interval_infeasibility(
    p_appointment_id uuid,
    p_clinic_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_clinic_timezone_name text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    assigned_clinic_assignment_id uuid;
    assigned_profile_id uuid;
begin
    if not public.clinic_interval_is_covered_by_timezone(
        p_clinic_id, p_start_at, p_end_at, p_clinic_timezone_name
    ) then
        return 'CLINIC_AVAILABILITY';
    end if;

    select appointment_assignment.veterinarian_clinic_assignment_id,
           clinic_assignment.professional_profile_id
    into assigned_clinic_assignment_id, assigned_profile_id
    from public.appointment_veterinarian_assignments as appointment_assignment
    join public.veterinarian_clinic_assignments as clinic_assignment
      on clinic_assignment.id = appointment_assignment.veterinarian_clinic_assignment_id
    where appointment_assignment.appointment_id = p_appointment_id
      and appointment_assignment.effective_end is null;

    if not found then
        return null;
    end if;

    if not public.veterinarian_clinic_assignment_is_current(assigned_clinic_assignment_id) then
        return 'VETERINARIAN_ASSIGNMENT';
    end if;

    if not public.veterinarian_interval_is_covered_by_timezone(
        assigned_clinic_assignment_id, p_start_at, p_end_at, p_clinic_timezone_name
    ) then
        return 'VETERINARIAN_UNAVAILABLE';
    end if;

    if public.veterinarian_has_known_confirmed_commitment_conflict(
        assigned_profile_id, p_start_at, p_end_at, p_appointment_id
    ) then
        return 'VETERINARIAN_UNAVAILABLE';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.appointment_reschedule_interval_infeasibility(uuid, uuid, timestamptz, timestamptz, text)
from public, anon, authenticated;

create function public.assert_appointment_reschedule_interval_feasible(
    p_appointment_id uuid,
    p_clinic_id uuid,
    p_start_at timestamptz,
    p_end_at timestamptz,
    p_clinic_timezone_name text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    infeasibility text;
begin
    infeasibility := public.appointment_reschedule_interval_infeasibility(
        p_appointment_id, p_clinic_id, p_start_at, p_end_at, p_clinic_timezone_name
    );

    if infeasibility = 'CLINIC_AVAILABILITY' then
        raise exception 'Clinic Appointment Availability does not cover the proposed interval'
            using errcode = '23514';
    elsif infeasibility = 'VETERINARIAN_ASSIGNMENT' then
        raise exception 'Currently assigned Veterinarian no longer has a valid Clinic Assignment'
            using errcode = '23514';
    elsif infeasibility = 'VETERINARIAN_UNAVAILABLE' then
        raise exception 'Currently assigned Veterinarian is not available for the proposed interval'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_reschedule_interval_feasible(uuid, uuid, timestamptz, timestamptz, text)
from public, anon, authenticated;

-- Elapsed duration of a scheduling context in whole microseconds. Exact:
-- extract(epoch from timestamptz) is numeric, and applying the result as
-- p_microseconds * interval '1 microsecond' yields a time-only interval, so no
-- day or month component (calendar arithmetic in the session timezone) is
-- ever involved (SPEC-APT-005 BR-24).
create function public.appointment_interval_duration_microseconds(
    p_start_at timestamptz,
    p_end_at timestamptz
)
returns bigint
language sql
immutable
security definer
set search_path = ''
as $$
    select round((extract(epoch from p_end_at) - extract(epoch from p_start_at)) * 1000000)::bigint
$$;

revoke all privileges
on function public.appointment_interval_duration_microseconds(timestamptz, timestamptz)
from public, anon, authenticated;

-- ==================================================================
-- D. Start-only, stale-safe proposal creation (SPEC-APT-005 BR-23–BR-30).
-- ==================================================================

drop function public.propose_confirmed_appointment_reschedule(
    uuid, text, date, time, integer, date, time, integer, text
);

create function public.propose_confirmed_appointment_reschedule(
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
    -- the reviewed-context check — before any write (including the lazy
    -- non-actionable materialization below).
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

    -- Only an intrinsically actionable PENDING Proposal blocks a later
    -- negotiation. When this locked workflow first observes an approved
    -- permanent invalidation condition, it records that historical fact and
    -- releases the partial-unique slot atomically with the new Proposal.
    select proposal.*
    into existing_proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.appointment_id = p_appointment_id
      and proposal.state = 'PENDING'
      and proposal.non_actionable_at is null
    for update;

    if found then
        if existing_proposal_record.base_revision_id <> base_revision.id then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'BASE_REVISION_SUPERSEDED'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposed_start_at <= operation_timestamp then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'PROPOSED_TIME_PASSED'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'GUARDIAN'
              and not public.user_has_continuous_guardianship_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.pet_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'PROPOSING_AUTHORITY_LOST'
            where id = existing_proposal_record.id;
        elsif existing_proposal_record.proposing_context = 'CLINIC'
              and not public.user_has_continuous_clinic_reschedule_authority_since(
                  existing_proposal_record.proposed_by_user_id,
                  appointment_record.clinic_id,
                  existing_proposal_record.created_at
              ) then
            update public.appointment_reschedule_proposals
            set non_actionable_at = operation_timestamp,
                non_actionable_reason = 'PROPOSING_AUTHORITY_LOST'
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
        appointment_id, base_revision_id,
        proposed_start_at, proposed_end_at, proposed_timezone_name,
        proposing_context, proposed_by_user_id, reason, created_at
    )
    values (
        p_appointment_id, base_revision.id,
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
-- E. Acceptance (SPEC-APT-006 BR-28–BR-33). Signature unchanged.
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
    current_confirmed_revision public.appointment_schedule_revisions%rowtype;
    clinic_timezone_name text;
    next_sequence integer;
    operation_timestamp timestamptz;
    created_revision_id uuid;
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
    where proposal.id = p_proposal_id;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Appointment must remain CONFIRMED to accept a reschedule Proposal'
            using errcode = '23514';
    end if;

    if proposal_record.state <> 'PENDING'
       or proposal_record.non_actionable_at is not null then
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

    select revision.*
    into current_confirmed_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = appointment_record.id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc
    limit 1;

    if not found
       or current_confirmed_revision.id <> proposal_record.base_revision_id then
        raise exception 'Reschedule Proposal base revision is no longer the current confirmed context'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    if current_confirmed_revision.scheduled_start_at <= operation_timestamp then
        raise exception 'The current confirmed Appointment time must still be future and actionable'
            using errcode = '23514';
    end if;

    if proposal_record.proposed_start_at <= operation_timestamp then
        raise exception 'Proposed Appointment time must still be in the future'
            using errcode = '23514';
    end if;

    -- BR-31.
    if exists (
        select 1
        from public.clinical_encounters as encounter_row
        where encounter_row.appointment_id = appointment_record.id
    ) then
        raise exception 'Appointment with a Clinical Encounter cannot be rescheduled'
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

    -- BR-28: the stored interval, unchanged. The deferred Veterinarian
    -- conflict constraint remains authoritative at commit.
    next_sequence := public.next_appointment_revision_sequence(appointment_record.id);

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        appointment_record.id, next_sequence, 'CONFIRMED',
        proposal_record.proposed_start_at, proposal_record.proposed_end_at,
        proposal_record.proposed_timezone_name, acting_user_id, p_proposal_id, operation_timestamp
    )
    returning id into created_revision_id;

    update public.appointment_reschedule_proposals
    set state = 'ACCEPTED',
        accepted_at = operation_timestamp,
        accepted_by_user_id = acting_user_id,
        accepting_context = p_accepting_context,
        resulting_confirmed_revision_id = created_revision_id
    where id = p_proposal_id;

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
-- F. Clinic withdrawal (SPEC-APT-016).
-- ==================================================================

create function public.withdraw_appointment_reschedule_proposal(
    p_proposal_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    resolved_appointment_id uuid;
    resolved_clinic_id uuid;
    proposal_record public.appointment_reschedule_proposals%rowtype;
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

    select proposal.appointment_id
    into resolved_appointment_id
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id;

    if not found then
        raise exception 'Reschedule Proposal does not exist'
            using errcode = '23503';
    end if;

    select appointment.clinic_id
    into resolved_clinic_id
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id;

    -- BR-2/BR-3: current APPOINTMENT_RESCHEDULE for this Clinic, no
    -- Entitlement; same Organization -> Clinic -> Appointment lock order as
    -- acceptance, so withdrawal and acceptance are serialized (BR-9).
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, resolved_clinic_id, 'APPOINTMENT_RESCHEDULE'
    );

    perform 1
    from public.appointments as appointment
    where appointment.id = resolved_appointment_id
    for update;

    select proposal.*
    into proposal_record
    from public.appointment_reschedule_proposals as proposal
    where proposal.id = p_proposal_id
    for update;

    -- BR-1.
    if proposal_record.proposing_context <> 'CLINIC' then
        raise exception 'Only a Clinic-originated Reschedule Proposal may be withdrawn'
            using errcode = '42501';
    end if;

    -- BR-4.
    if not public.appointment_reschedule_proposal_is_actionable(
        p_proposal_id, clock_timestamp()
    ) then
        raise exception 'Reschedule Proposal is no longer actionable'
            using errcode = '23514';
    end if;

    -- BR-5/BR-6: withdrawn_at is set by the integrity trigger.
    update public.appointment_reschedule_proposals
    set state = 'WITHDRAWN',
        withdrawn_by_user_id = acting_user_id
    where id = p_proposal_id;

    return p_proposal_id;
end;
$$;

revoke all privileges
on function public.withdraw_appointment_reschedule_proposal(uuid)
from public, anon, authenticated;

grant execute
on function public.withdraw_appointment_reschedule_proposal(uuid)
to authenticated;

-- ==================================================================
-- G. Professional reschedule candidate times (SPEC-APT-017).
--
-- SPEC-APT-013 BR-58 grid with the base confirmed elapsed duration D in
-- place of the standard duration, as both length and cadence, in whole
-- microseconds of civil time-of-day. A position must fit within its covered
-- civil range (so D >= 24h, or D longer than every range, yields nothing —
-- SPEC-APT-017 §4). Each resolved candidate is checked with exactly the
-- feasibility classifier propose uses, so read/write parity is exact for
-- unchanged state (BR-7).
-- ==================================================================

create function public.get_appointment_reschedule_candidate_start_times(
    p_appointment_id uuid,
    p_start_date date,
    p_end_date date
)
returns table (
    candidate_local_date date,
    candidate_local_time time,
    utc_offset_seconds integer,
    candidate_end_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_record public.appointments%rowtype;
    target_organization_id uuid;
    base_revision public.appointment_schedule_revisions%rowtype;
    clinic_timezone_name text;
    duration_microseconds bigint;
    operation_timestamp timestamptz;
    iter_date date;
    range_row record;
    range_start_microseconds bigint;
    range_end_microseconds bigint;
    position_microseconds bigint;
    position_time time;
    candidate_resolution record;
    candidate_end_instant timestamptz;
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

    -- BR-4: structural span validation (a safety bound, not a horizon).
    if p_start_date is null or p_end_date is null then
        raise exception 'A start date and end date are required'
            using errcode = '22023';
    end if;

    if p_end_date < p_start_date then
        raise exception 'End date must not precede start date'
            using errcode = '22023';
    end if;

    if p_end_date - p_start_date > 60 then
        raise exception 'Requested range must not span more than 60 days'
            using errcode = '22023';
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    -- BR-1: the same capability and Entitlement as a Clinic proposal.
    if not public.user_has_clinic_capability(
        acting_user_id, appointment_record.clinic_id, 'APPOINTMENT_RESCHEDULE'
    ) then
        raise exception 'Applicable Appointment-management capability is required'
            using errcode = '42501';
    end if;

    select clinic.organization_id, clinic.scheduling_timezone_name
    into target_organization_id, clinic_timezone_name
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if not public.organization_has_professional_entitlement(
        target_organization_id, 'APPOINTMENT_MANAGEMENT'
    ) then
        raise exception 'Applicable professional Entitlement is required'
            using errcode = '42501';
    end if;

    -- BR-2.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may receive a reschedule Proposal'
            using errcode = '23514';
    end if;

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

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Appointment scheduling requires a valid Clinic scheduling timezone'
            using errcode = '23514';
    end if;

    -- BR-5: D from the base confirmed revision; the standard duration is never
    -- read.
    duration_microseconds := public.appointment_interval_duration_microseconds(
        base_revision.scheduled_start_at, base_revision.scheduled_end_at
    );

    iter_date := p_start_date;
    while iter_date <= p_end_date loop
        for range_row in
            select covered.range_start, covered.range_end
            from public.clinic_day_covered_civil_ranges(
                appointment_record.clinic_id, iter_date
            ) as covered
        loop
            range_start_microseconds := round(
                extract(epoch from range_row.range_start) * 1000000
            )::bigint;
            range_end_microseconds := round(
                extract(epoch from range_row.range_end) * 1000000
            )::bigint;

            position_microseconds := range_start_microseconds;

            while position_microseconds + duration_microseconds <= range_end_microseconds loop
                position_time := time '00:00:00'
                    + position_microseconds * interval '1 microsecond';

                select *
                into candidate_resolution
                from public.resolve_clinic_civil_candidate(
                    clinic_timezone_name, iter_date, position_time
                );

                if candidate_resolution.resolution_kind = 'UNIQUE'
                   and candidate_resolution.resolved_instant > operation_timestamp
                   and candidate_resolution.resolved_instant <> base_revision.scheduled_start_at then
                    candidate_end_instant := candidate_resolution.resolved_instant
                        + duration_microseconds * interval '1 microsecond';

                    if public.appointment_reschedule_interval_infeasibility(
                        p_appointment_id, appointment_record.clinic_id,
                        candidate_resolution.resolved_instant, candidate_end_instant,
                        clinic_timezone_name
                    ) is null then
                        candidate_local_date := iter_date;
                        candidate_local_time := position_time;
                        utc_offset_seconds := candidate_resolution.resolved_utc_offset_seconds;
                        candidate_end_at := candidate_end_instant;
                        return next;
                    end if;
                end if;

                -- The grid stays anchored to the range start; an omitted
                -- position never shifts it (SPEC-APT-013 BR-58).
                position_microseconds := position_microseconds + duration_microseconds;
            end loop;
        end loop;

        iter_date := iter_date + 1;
    end loop;

    return;
end;
$$;

revoke all privileges
on function public.get_appointment_reschedule_candidate_start_times(uuid, date, date)
from public, anon, authenticated;

grant execute
on function public.get_appointment_reschedule_candidate_start_times(uuid, date, date)
to authenticated;

-- ==================================================================
-- H. Communication delivery eligibility (SPEC-COM-003 BR-70). Unchanged
--    except that APPOINTMENT_RESCHEDULE_PROPOSED now uses the authoritative
--    actionability predicate instead of a partial copy of it.
-- ==================================================================

create or replace function public.communication_delivery_is_currently_eligible(
    p_communication_id uuid,
    p_channel text,
    p_push_registration_id uuid default null,
    p_destination_snapshot text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    communication_record public.transactional_communications%rowtype;
begin
    select communication.* into communication_record
    from public.transactional_communications as communication
    where communication.id = p_communication_id;

    if not found or p_channel is null or p_channel not in ('EMAIL', 'PUSH') then
        return false;
    end if;

    if communication_record.communication_type in (
        'ORGANIZATION_INVITATION', 'GUARDIANSHIP_INVITATION'
    ) and p_channel <> 'EMAIL' then
        return false;
    end if;

    if communication_record.communication_type = 'ORGANIZATION_INVITATION'
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = communication_record.organization_invitation_id
             and invitation.revoked_at is null
             and invitation.rejected_at is null
             and invitation.expires_at > clock_timestamp()
             and invitation.acceptance_secret_digest is not null
             and not exists (
                 select 1 from public.organization_memberships as membership
                 where membership.originating_invitation_id = invitation.id
             )
       ) then return false;
    end if;

    if communication_record.communication_type = 'GUARDIANSHIP_INVITATION'
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = communication_record.guardianship_invitation_id
             and invitation.revoked_at is null
             and invitation.expires_at > clock_timestamp()
             and invitation.acceptance_secret_digest is not null
             and not exists (
                 select 1 from public.guardianships as guardianship
                 where guardianship.originating_invitation_id = invitation.id
             )
       ) then return false;
    end if;

    if communication_record.appointment_id is not null then
        if not exists (
            select 1
            from public.appointments as appointment
            join public.guardianships as guardianship
              on guardianship.pet_id = appointment.pet_id
            where appointment.id = communication_record.appointment_id
              and guardianship.user_id = communication_record.recipient_user_id
              and guardianship.effective_start <= clock_timestamp()
              and guardianship.effective_end is null
        ) then return false; end if;

        if communication_record.communication_type = 'APPOINTMENT_REMINDER'
           and not exists (
               select 1
               from public.appointments as appointment
               join public.appointment_schedule_revisions as revision
                 on revision.id = communication_record.appointment_schedule_revision_id
                and revision.appointment_id = appointment.id
               where appointment.id = communication_record.appointment_id
                 and appointment.lifecycle_state = 'CONFIRMED'
                 and revision.revision_context = 'CONFIRMED'
                 and revision.scheduled_start_at > clock_timestamp()
                 and revision.id = (
                     select latest.id
                     from public.appointment_schedule_revisions as latest
                     where latest.appointment_id = appointment.id
                       and latest.revision_context = 'CONFIRMED'
                     order by latest.revision_sequence desc
                     limit 1
                 )
           ) then return false; end if;

        if communication_record.communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
           and not exists (
               select 1 from public.appointment_reschedule_proposals as proposal
                where proposal.id = communication_record.appointment_reschedule_proposal_id
                  and proposal.proposing_context = 'CLINIC'
                  and public.appointment_reschedule_proposal_is_actionable(
                      proposal.id, clock_timestamp()
                  )
           ) then return false; end if;
    end if;

    if p_channel = 'EMAIL'
       and communication_record.recipient_email is not null
       and p_destination_snapshot is distinct from
           communication_record.recipient_email then
        return false;
    end if;

    if p_channel = 'EMAIL'
       and communication_record.recipient_email is null
       and not exists (
           select 1
           from public.user_authentication_identities as identity_record
           join auth.users as auth_user
             on auth_user.id = identity_record.provider_subject
           where identity_record.user_id = communication_record.recipient_user_id
             and identity_record.provider = 'supabase_auth'
             and identity_record.issuer = 'primary'
             and auth_user.email_confirmed_at is not null
             and auth_user.email is not null
             and (
                 p_destination_snapshot is null
                 or auth_user.email = p_destination_snapshot
             )
       ) then return false; end if;

    if p_channel = 'PUSH' and not exists (
        select 1
        from public.push_registrations as registration
        join public.user_authentication_identities as identity_record
          on identity_record.user_id = registration.user_id
         and identity_record.provider = 'supabase_auth'
         and identity_record.issuer = 'primary'
        join auth.sessions as auth_session
          on auth_session.id = registration.auth_session_id
         and auth_session.user_id = identity_record.provider_subject
        where registration.id = p_push_registration_id
          and registration.user_id = communication_record.recipient_user_id
          and registration.invalidated_at is null
          and p_destination_snapshot = 'sha256:' ||
              encode(registration.provider_token_digest, 'hex')
    ) then return false; end if;

    return true;
end;
$$;

revoke all privileges on function public.communication_delivery_is_currently_eligible(
    uuid, text, uuid, text
) from public, anon, authenticated;

commit;

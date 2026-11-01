-- Completion ends the Appointment Care Authorization — Punto 8, stage M3
-- (ADR-011; SPEC-MED-010 BR-16 and §6; SPEC-APT-009 as superseded by it;
-- SPEC-ACC-002 BR-46; docs/CLINICAL_DOCUMENTATION_TRANSITION.md §5.2).
--
-- Requires M2 (20261113090000). Prior-history access already excludes
-- COMPLETED Appointments (SPEC-MED-010 BR-14); this stage aligns the
-- persisted authorization state with that meaning. Clinical documentation is
-- unaffected: it never depended on the Care Authorization (BR-11).
--
--   0. Fail-closed guard over the existing data: every COMPLETED Appointment
--      has exactly one Appointment-derived Care Authorization and exactly one
--      CONFIRMED -> COMPLETED Lifecycle Event; none of those authorizations is
--      already ENDED; every ACTIVE one was granted no later than its
--      completion. Anything else aborts with 55000 and changes nothing.
--   1. The ending context APPOINTMENT_COMPLETED.
--   2. Coherence: an authorization ENDED with APPOINTMENT_COMPLETED belongs to
--      a COMPLETED Appointment and ends exactly at its completion Event; a
--      COMPLETED Appointment never retains an ACTIVE authorization.
--   3. complete_appointment locks the authorization after the Appointment (the
--      cancellation and no-show order) and ends an ACTIVE one at the completion
--      instant, atomically; REVOKED and other inactive states are unchanged.
--   4. Reconciliation: every ACTIVE authorization of a COMPLETED Appointment
--      ends at that Appointment's recorded completion time. REVOKED
--      authorizations are untouched; no authorization is created or
--      reactivated; no clinical row is read or written.
--
-- No table loses data. No DROP ... CASCADE is used.
begin;

-- ==================================================================
-- 0. Fail-closed guard.
-- ==================================================================

do $guard$
begin
    if exists (
        select 1 from public.appointments as appointment
        where appointment.lifecycle_state = 'COMPLETED'
          and (select count(*) from public.care_authorizations as care_auth
               where care_auth.appointment_id = appointment.id
                 and care_auth.purpose = 'APPOINTMENT_CARE') <> 1
    ) then
        raise exception 'M3 refused: a COMPLETED Appointment does not have exactly one Appointment Care Authorization'
            using errcode = '55000';
    end if;
    if exists (
        select 1 from public.appointments as appointment
        where appointment.lifecycle_state = 'COMPLETED'
          and (select count(*) from public.appointment_lifecycle_events as completion
               where completion.appointment_id = appointment.id
                 and completion.from_state = 'CONFIRMED'
                 and completion.to_state = 'COMPLETED') <> 1
    ) then
        raise exception 'M3 refused: a COMPLETED Appointment does not have exactly one completion Lifecycle Event'
            using errcode = '55000';
    end if;
    if exists (
        select 1 from public.care_authorizations as care_auth
        join public.appointments as appointment on appointment.id = care_auth.appointment_id
        where appointment.lifecycle_state = 'COMPLETED'
          and care_auth.lifecycle_state = 'ENDED'
    ) then
        raise exception 'M3 refused: a COMPLETED Appointment already has an ENDED Care Authorization'
            using errcode = '55000';
    end if;
    if exists (
        select 1 from public.care_authorizations as care_auth
        join public.appointments as appointment on appointment.id = care_auth.appointment_id
        join public.appointment_lifecycle_events as completion
          on completion.appointment_id = appointment.id
         and completion.from_state = 'CONFIRMED' and completion.to_state = 'COMPLETED'
        where appointment.lifecycle_state = 'COMPLETED'
          and care_auth.lifecycle_state = 'ACTIVE'
          and (completion.effective_at < care_auth.granted_at
               or not isfinite(completion.effective_at)
               or completion.effective_at > clock_timestamp())
    ) then
        raise exception 'M3 refused: a completion time cannot end its Care Authorization coherently'
            using errcode = '55000';
    end if;
end
$guard$;

-- ==================================================================
-- 1. Ending context (SPEC-MED-010 BR-16).
-- ==================================================================

alter table public.care_authorizations
    drop constraint care_authorizations_ended_reason_check;
alter table public.care_authorizations
    add constraint care_authorizations_ended_reason_check
        check (ended_reason is null or ended_reason in (
            'APPOINTMENT_CANCELLED', 'APPOINTMENT_NO_SHOW', 'APPOINTMENT_EXPIRED', 'APPOINTMENT_COMPLETED'
        ));

-- ==================================================================
-- 2. Coherence (SPEC-MED-010 §6; RELATIONAL_MODEL §14).
-- ==================================================================

-- An ENDED authorization matches its terminal Appointment state and Event time.
create or replace function public.assert_care_authorization_appointment_coherence(p_care_authorization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    care_auth_record public.care_authorizations%rowtype;
    expected_appointment_state text;
    expected_terminal_state text;
    terminal_effective_at timestamptz;
begin
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;
    if not found then return; end if;

    if care_auth_record.lifecycle_state <> 'ENDED'
       or care_auth_record.ended_reason not in (
           'APPOINTMENT_CANCELLED', 'APPOINTMENT_NO_SHOW', 'APPOINTMENT_EXPIRED', 'APPOINTMENT_COMPLETED') then
        return;
    end if;

    expected_appointment_state := case care_auth_record.ended_reason
        when 'APPOINTMENT_CANCELLED' then 'CANCELLED'
        when 'APPOINTMENT_EXPIRED' then 'EXPIRED'
        when 'APPOINTMENT_COMPLETED' then 'COMPLETED'
        else 'NO_SHOW'
    end;
    expected_terminal_state := expected_appointment_state;

    select appointment.lifecycle_state into expected_appointment_state
    from public.appointments as appointment
    where appointment.id = care_auth_record.appointment_id
    for update;

    if not found or expected_appointment_state <> expected_terminal_state then
        raise exception 'Ended Care Authorization % requires its matching terminal Appointment state', p_care_authorization_id
            using errcode = '23514';
    end if;

    select lifecycle_event.effective_at into terminal_effective_at
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = care_auth_record.appointment_id
      and lifecycle_event.to_state = expected_terminal_state;

    if not found or terminal_effective_at is distinct from care_auth_record.ended_at then
        raise exception 'Ended Care Authorization % must match its terminal Appointment Event time', p_care_authorization_id
            using errcode = '23514';
    end if;
end;
$$;

-- A terminal Appointment, now including COMPLETED, retains no ACTIVE authority.
create or replace function public.assert_appointment_care_authorization_coherence(p_appointment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    linked_count integer;
    linked_state text;
begin
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;
    if not found then return; end if;

    select count(*), min(care_auth.lifecycle_state)
    into linked_count, linked_state
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id;

    if linked_count <> 1 then
        raise exception 'Appointment % requires exactly one Appointment-derived Care Authorization', p_appointment_id
            using errcode = '23514';
    end if;

    if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED', 'COMPLETED')
       and linked_state = 'ACTIVE' then
        raise exception 'Terminal Appointment % must not retain ACTIVE care authority', p_appointment_id
            using errcode = '23514';
    end if;
end;
$$;

-- ==================================================================
-- 3. Completion ends the authorization (SPEC-MED-010 BR-16).
-- ==================================================================

create or replace function public.complete_appointment(
    p_appointment_id uuid,
    p_expected_confirmed_revision_sequence integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    latest_confirmed_revision public.appointment_schedule_revisions%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    -- BR-8: structurally invalid input, rejected before any Appointment state
    -- is consulted. Distinct from a stale (well-formed but superseded)
    -- expected sequence.
    if p_expected_confirmed_revision_sequence is null
       or p_expected_confirmed_revision_sequence <= 0 then
        raise exception 'Expected confirmed revision sequence must be a positive integer'
            using errcode = '22023';
    end if;

    select appointment.clinic_id into appointment_clinic_id from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;

    -- BR-3/BR-6: Organization -> Clinic capability lock, no Entitlement gate.
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, appointment_clinic_id, 'APPOINTMENT_COMPLETE'
    );
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;

    -- BR-8/BR-11: lifecycle precedes staleness. An Appointment that is no
    -- longer CONFIRMED is an invalid transition, never a stale request.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may be completed' using errcode = '23514';
    end if;

    select revision.* into latest_confirmed_revision
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc limit 1;
    if not found then
        raise exception 'Appointment % has no confirmed scheduling context', p_appointment_id
            using errcode = '23514';
    end if;

    -- BR-9/BR-10: the revision sequence alone decides staleness, never the
    -- scheduled values. Deterministic client-input mismatch: plain P0001.
    if latest_confirmed_revision.revision_sequence <> p_expected_confirmed_revision_sequence then
        raise exception 'Stale confirmed Appointment schedule revision';
    end if;

    operation_timestamp := clock_timestamp();
    -- BR-7: permitted once the reviewed (and current) confirmed start has
    -- been reached; the scheduled end is not required.
    if latest_confirmed_revision.scheduled_start_at > operation_timestamp then
        raise exception 'Appointment cannot be completed before its confirmed scheduled start' using errcode = '23514';
    end if;

    -- SPEC-MED-010 BR-16: the Appointment-derived Care Authorization, locked
    -- after the Appointment as cancellation and no-show do, so a concurrent
    -- Guardian revocation either precedes (REVOKED stays) or follows
    -- (ALREADY_INACTIVE). No clinical record or Veterinarian Assignment is
    -- read or written (BR-12).
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id for update;
    if not found then raise exception 'Appointment has no Care Authorization' using errcode = '23514'; end if;

    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at
    ) values (
        p_appointment_id, 'CONFIRMED', 'COMPLETED', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp
    );
    update public.appointments set lifecycle_state = 'COMPLETED' where id = p_appointment_id;
    if care_auth_record.lifecycle_state = 'ACTIVE' then
        update public.care_authorizations
        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_COMPLETED'
        where id = care_auth_record.id;
    end if;
    return p_appointment_id;
end;
$$;

-- ==================================================================
-- 4. Reconciliation of existing COMPLETED Appointments.
-- ==================================================================

do $reconcile$
declare
    ended_count integer;
begin
    update public.care_authorizations as care_auth
    set lifecycle_state = 'ENDED',
        ended_at = completion.effective_at,
        ended_reason = 'APPOINTMENT_COMPLETED'
    from public.appointments as appointment,
         public.appointment_lifecycle_events as completion
    where appointment.id = care_auth.appointment_id
      and appointment.lifecycle_state = 'COMPLETED'
      and completion.appointment_id = appointment.id
      and completion.from_state = 'CONFIRMED'
      and completion.to_state = 'COMPLETED'
      and care_auth.purpose = 'APPOINTMENT_CARE'
      and care_auth.lifecycle_state = 'ACTIVE';
    get diagnostics ended_count = row_count;
    raise notice 'M3 reconciliation: % ACTIVE Care Authorization(s) of COMPLETED Appointments ended with APPOINTMENT_COMPLETED', ended_count;
end
$reconcile$;

-- Deferred coherence of every reconciled row runs here, before commit.
set constraints all immediate;

commit;

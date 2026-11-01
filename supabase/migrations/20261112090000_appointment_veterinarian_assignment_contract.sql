-- Appointment Veterinarian assignment contract — Punto 8, stage M1
-- (SPEC-APT-007 §13/§14, SPEC-APT-008, SPEC-MED-010 BR-6, ADR-011 §5;
-- CLINICAL_DOCUMENTATION_TRANSITION.md §5.2).
--
-- The current Appointment Veterinarian Assignment designates the Veterinarian
-- responsible for the visit. This stage only establishes the assignment
-- contract; clinical documentation keeps following the deployed Encounter
-- model until stage M2, so no clinical, Care Authorization, or completion
-- behavior changes here.
--
--   1. Establishment of an Appointment Veterinarian Assignment also accepts a
--      COMPLETED Appointment (SPEC-APT-007 BR-30; supersedes SPEC-APT-008
--      BR-25 for assignment). Body otherwise that of
--      20260826163000_appointment_schema_and_scheduling_history.sql.
--   2. Deferred succession rule: an ended period always has a successor
--      starting at the same instant (BR-36), so "who reassigned, when, from
--      whom to whom" stays derivable. Existing data satisfies it: only
--      reassign_veterinarian ever ends a period, and it starts the next one at
--      the same instant (inventory I-16 = 0 in LOCAL and DEVELOPMENT).
--   3. Private helpers: Veterinarian eligibility (BR-31) and the Appointment
--      states that accept an assignment through the client (BR-30).
--   4. Client operations, authenticated only, authority before any target:
--        get_appointment_veterinarian_assignment    (BR-37)
--        assign_appointment_veterinarian             (BR-32) ASSIGNED | REASSIGNED | ALREADY_ASSIGNED
--        assign_me_to_appointment                    (BR-33) ASSIGNED | ALREADY_ASSIGNED
--        get_appointment_veterinarian_candidates     (BR-38)
--      Locks follow reassign_veterinarian: Organization -> Clinic ->
--      Appointment -> current assignment -> Veterinarian Professional Profiles
--      (identity order) -> Veterinarian Clinic Assignment (establishment
--      trigger). Veterinarian Availability is not required (BR-35); the
--      confirmed-commitment overlap rule applies to CONFIRMED Appointments
--      and is reported with a stable hint.
--   5. ACL: authenticated EXECUTE is withdrawn from
--      assign_veterinarian_to_appointment and reassign_veterinarian (BR-40);
--      no client calls them. get_clinic_appointment and the BR-51 projection
--      are unchanged.
--
-- No table, column, index, capability, or Entitlement is added, and no row is
-- written by this migration.
begin;

-- ==================================================================
-- 1. Establishment accepts a COMPLETED Appointment.
-- ==================================================================

create or replace function public.assert_appointment_veterinarian_assignment_establishment(
    p_appointment_id uuid,
    p_veterinarian_clinic_assignment_id uuid,
    p_effective_start timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_clinic_id uuid;
    appointment_lifecycle_state text;
    assignment_clinic_id uuid;
    assignment_effective_start timestamptz;
    assignment_organization_id uuid;
begin
    -- Resolve immutable identifying context first, without write locks,
    -- so a Clinic-context mismatch is rejected before acquiring any
    -- aggregate lock.
    select appointment.clinic_id
    into appointment_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    select assignment.clinic_id, clinic.organization_id
    into assignment_clinic_id, assignment_organization_id
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_veterinarian_clinic_assignment_id;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if assignment_clinic_id <> appointment_clinic_id then
        raise exception 'Veterinarian Clinic Assignment must belong to the Appointment Clinic'
            using errcode = '23514';
    end if;

    -- Normal aggregate lock order: Organization -> Clinic -> Appointment
    -- -> Veterinarian Clinic Assignment. A trusted RPC that already holds
    -- some of these locks in the same transaction may safely reacquire
    -- them here.
    perform 1
    from public.veterinary_organizations as organization
    where organization.id = assignment_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = assignment_clinic_id
      and clinic.organization_id = assignment_organization_id
    for update;

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    select appointment.lifecycle_state
    into appointment_lifecycle_state
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- COMPLETED: assignment of the Veterinarian who documents the visit
    -- that took place (SPEC-APT-007 BR-30).
    if appointment_lifecycle_state not in ('REQUESTED', 'CONFIRMED', 'COMPLETED') then
        raise exception 'Appointment Veterinarian Assignment requires a REQUESTED, CONFIRMED, or COMPLETED Appointment'
            using errcode = '23514';
    end if;

    select assignment.effective_start
    into assignment_effective_start
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
    for update;

    -- Re-evaluate all mutable establishment facts only after every lock
    -- in the aggregate is held.
    if not public.veterinarian_clinic_assignment_is_current(p_veterinarian_clinic_assignment_id) then
        raise exception 'Appointment Veterinarian Assignment requires a currently valid Clinic Assignment'
            using errcode = '23514';
    end if;

    if p_effective_start < assignment_effective_start then
        raise exception 'Appointment Veterinarian Assignment cannot start before its Clinic Assignment'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_veterinarian_assignment_establishment(uuid, uuid, timestamptz)
from public, anon, authenticated;

-- ==================================================================
-- 2. Every ended period has a same-instant successor (BR-36).
-- ==================================================================

create function public.enforce_appointment_veterinarian_assignment_succession()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.effective_end is not null
       and old.effective_end is null
       and not exists (
           select 1
           from public.appointment_veterinarian_assignments as successor
           where successor.appointment_id = new.appointment_id
             and successor.id <> new.id
             and successor.effective_start = new.effective_end
       ) then
        raise exception 'An ended Appointment Veterinarian Assignment requires a successor starting at the same instant'
            using errcode = '23514';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_veterinarian_assignment_succession()
from public, anon, authenticated;

create constraint trigger appointment_veterinarian_assignments_enforce_succession
after update of effective_end on public.appointment_veterinarian_assignments
deferrable initially deferred
for each row
execute function public.enforce_appointment_veterinarian_assignment_succession();

-- ==================================================================
-- 3. Private helpers.
-- ==================================================================

-- SPEC-APT-007 BR-31: the Clinic Assignment is current and belongs to a
-- current exact-Clinic Veterinarian context holding CLINICAL_DOCUMENTATION
-- (current Membership, current Organization-scoped VETERINARIAN Grant, own
-- Professional Profile) — the same context as clinical_actor_context_at.
create function public.appointment_veterinarian_is_eligible(
    p_veterinarian_clinic_assignment_id uuid,
    p_clinic_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.veterinarian_clinic_assignments as assignment
        join public.clinics as clinic
          on clinic.id = assignment.clinic_id
        join public.organization_memberships as membership
          on membership.id = assignment.supporting_membership_id
         and membership.organization_id = clinic.organization_id
         and membership.effective_start <= statement_timestamp()
         and membership.effective_end is null
        join public.organization_responsibility_grants as grant_record
          on grant_record.membership_id = membership.id
         and grant_record.responsibility = 'VETERINARIAN'
         and grant_record.scope_type = 'ORGANIZATION'
         and grant_record.clinic_id is null
         and grant_record.effective_start <= statement_timestamp()
         and grant_record.effective_end is null
        join public.veterinarian_professional_profiles as profile
          on profile.id = assignment.professional_profile_id
         and profile.user_id = membership.user_id
        where assignment.id = p_veterinarian_clinic_assignment_id
          and assignment.clinic_id = p_clinic_id
          and public.veterinarian_clinic_assignment_is_current(assignment.id)
          and public.user_has_clinic_capability(membership.user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION')
    )
$$;

revoke all privileges
on function public.appointment_veterinarian_is_eligible(uuid, uuid)
from public, anon, authenticated, service_role;

-- SPEC-APT-007 BR-30: exactly one REQUESTED -> CONFIRMED Lifecycle Event and
-- currently CONFIRMED or COMPLETED. p_lifecycle_state is the state read under
-- the caller's lock.
create function public.appointment_accepts_veterinarian_assignment(
    p_appointment_id uuid,
    p_lifecycle_state text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select p_lifecycle_state in ('CONFIRMED', 'COMPLETED')
       and (select count(*)
            from public.appointment_lifecycle_events as confirmation
            where confirmation.appointment_id = p_appointment_id
              and confirmation.from_state = 'REQUESTED'
              and confirmation.to_state = 'CONFIRMED') = 1
$$;

revoke all privileges
on function public.appointment_accepts_veterinarian_assignment(uuid, text)
from public, anon, authenticated, service_role;

-- The current display name of the User behind a Veterinarian Clinic
-- Assignment (SPEC-ID-006), or NULL when absent or blank.
create function public.veterinarian_clinic_assignment_display_name(
    p_veterinarian_clinic_assignment_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select nullif(btrim(user_profile.display_name, E' \t\n\r\f\013'), '')
    from public.veterinarian_clinic_assignments as assignment
    join public.organization_memberships as membership
      on membership.id = assignment.supporting_membership_id
    left join public.user_profiles as user_profile
      on user_profile.user_id = membership.user_id
    where assignment.id = p_veterinarian_clinic_assignment_id
$$;

revoke all privileges
on function public.veterinarian_clinic_assignment_display_name(uuid)
from public, anon, authenticated, service_role;

-- Ends the current period (when any) and starts the new one at the same
-- instant, then applies the confirmed-commitment overlap rule immediately so
-- that its rejection carries a stable hint (BR-35). The caller holds the
-- Organization, Clinic, and Appointment locks.
create function public.establish_appointment_veterinarian_period(
    p_appointment_id uuid,
    p_lifecycle_state text,
    p_current_assignment_id uuid,
    p_current_veterinarian_clinic_assignment_id uuid,
    p_new_veterinarian_clinic_assignment_id uuid,
    p_acting_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    old_profile_id uuid;
    new_profile_id uuid;
    operation_timestamp timestamptz;
    created_assignment_id uuid;
begin
    select assignment.professional_profile_id into old_profile_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_current_veterinarian_clinic_assignment_id;

    select assignment.professional_profile_id into new_profile_id
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_new_veterinarian_clinic_assignment_id;

    -- Profiles in identity order, as reassign_veterinarian does.
    perform 1
    from public.veterinarian_professional_profiles as profile
    where profile.id in (old_profile_id, new_profile_id)
    order by profile.id
    for update;

    operation_timestamp := clock_timestamp();

    if p_current_assignment_id is not null then
        update public.appointment_veterinarian_assignments
        set effective_end = operation_timestamp
        where id = p_current_assignment_id;
    end if;

    insert into public.appointment_veterinarian_assignments (
        appointment_id, veterinarian_clinic_assignment_id, effective_start, assigned_by_user_id
    )
    values (
        p_appointment_id, p_new_veterinarian_clinic_assignment_id, operation_timestamp, p_acting_user_id
    )
    returning id into created_assignment_id;

    if p_lifecycle_state = 'CONFIRMED' then
        begin
            perform public.assert_veterinarian_confirmed_commitment_conflict_free(new_profile_id);
        exception when sqlstate '23P01' then
            raise exception 'The Veterinarian has an overlapping confirmed Appointment'
                using errcode = '23514', hint = 'VETERINARIAN_SCHEDULE_CONFLICT';
        end;
    end if;

    return created_assignment_id;
end;
$$;

revoke all privileges
on function public.establish_appointment_veterinarian_period(uuid, text, uuid, uuid, uuid, uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 4a. Read the assignment of one Appointment (SPEC-APT-007 BR-37).
-- ==================================================================

create function public.get_appointment_veterinarian_assignment(
    p_clinic_id uuid,
    p_appointment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_record public.appointments%rowtype;
    current_record public.appointment_veterinarian_assignments%rowtype;
    assignee_user_id uuid;
    actor_assignment_id uuid;
    accepts_assignment boolean;
    current_is_eligible boolean;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- The authority and uniform outcome of get_clinic_appointment.
    if not public.user_has_clinic_capability(acting_user_id, p_clinic_id, 'APPOINTMENT_VIEW_SCHEDULE') then
        raise exception 'Clinic Appointment unavailable' using errcode = '42501';
    end if;
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        raise exception 'Clinic Appointment unavailable' using errcode = '42501';
    end if;

    select assignment.* into current_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null;

    select context.veterinarian_clinic_assignment_id into actor_assignment_id
    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION') as context;

    accepts_assignment := public.appointment_accepts_veterinarian_assignment(
        appointment_record.id, appointment_record.lifecycle_state
    );

    if current_record.id is null then
        return jsonb_build_object(
            'status', 'UNASSIGNED',
            'may_assign_me', accepts_assignment and actor_assignment_id is not null,
            'may_manage', accepts_assignment and public.user_has_clinic_capability(
                acting_user_id, p_clinic_id, 'APPOINTMENT_ASSIGN_VETERINARIAN')
        );
    end if;

    select membership.user_id into assignee_user_id
    from public.veterinarian_clinic_assignments as assignment
    join public.organization_memberships as membership
      on membership.id = assignment.supporting_membership_id
    where assignment.id = current_record.veterinarian_clinic_assignment_id;

    current_is_eligible := public.appointment_veterinarian_is_eligible(
        current_record.veterinarian_clinic_assignment_id, p_clinic_id
    );

    return jsonb_build_object(
        'status', 'ASSIGNED',
        'display_name', public.veterinarian_clinic_assignment_display_name(
            current_record.veterinarian_clinic_assignment_id),
        'is_me', assignee_user_id = acting_user_id,
        'is_eligible', current_is_eligible,
        'assignment_token', current_record.id,
        'may_assign_me', accepts_assignment and actor_assignment_id is not null
            and not current_is_eligible,
        'may_manage', accepts_assignment and public.user_has_clinic_capability(
            acting_user_id, p_clinic_id, 'APPOINTMENT_ASSIGN_VETERINARIAN')
    );
end;
$$;

revoke all privileges
on function public.get_appointment_veterinarian_assignment(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.get_appointment_veterinarian_assignment(uuid, uuid)
to authenticated;

-- ==================================================================
-- 4b. Managed assignment and reassignment (SPEC-APT-007 BR-32, BR-34).
-- ==================================================================

create function public.assign_appointment_veterinarian(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_veterinarian_clinic_assignment_id uuid,
    p_expected_assignment_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    clinic_organization_id uuid;
    appointment_record public.appointments%rowtype;
    current_record public.appointment_veterinarian_assignments%rowtype;
    created_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Argument shape only.
    if p_veterinarian_clinic_assignment_id is null then
        raise exception 'A Veterinarian is required'
            using errcode = '22023', hint = 'VETERINARIAN_REQUIRED';
    end if;

    -- 3–4. Authority, then the Appointment of that Clinic.
    select clinic.organization_id into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;
    if not found
       or not public.user_has_clinic_capability(acting_user_id, p_clinic_id, 'APPOINTMENT_ASSIGN_VETERINARIAN')
       or not exists (
           select 1 from public.appointments as appointment
           where appointment.id = p_appointment_id and appointment.clinic_id = p_clinic_id
       ) then
        raise exception 'Appointment unavailable' using errcode = '42501';
    end if;

    -- 5. Locks, then authority again under them.
    perform 1 from public.veterinary_organizations as organization
    where organization.id = clinic_organization_id for update;
    perform 1 from public.clinics as clinic
    where clinic.id = p_clinic_id for update;
    if not public.user_has_clinic_capability(acting_user_id, p_clinic_id, 'APPOINTMENT_ASSIGN_VETERINARIAN') then
        raise exception 'Appointment unavailable' using errcode = '42501';
    end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    select assignment.* into current_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null
    for update;

    -- 6. Lifecycle.
    if not public.appointment_accepts_veterinarian_assignment(
           appointment_record.id, appointment_record.lifecycle_state) then
        raise exception 'The Appointment cannot receive a Veterinarian assignment'
            using errcode = '23514', hint = 'APPOINTMENT_STATE_INVALID';
    end if;

    -- 7. Replay of the same eligible assignment, then the reviewed state.
    if current_record.veterinarian_clinic_assignment_id = p_veterinarian_clinic_assignment_id
       and public.appointment_veterinarian_is_eligible(p_veterinarian_clinic_assignment_id, p_clinic_id) then
        return jsonb_build_object('outcome', 'ALREADY_ASSIGNED', 'assignment_token', current_record.id);
    end if;

    -- Deterministic client-input mismatch: plain P0001, never 40001/409.
    if current_record.id is distinct from p_expected_assignment_token then
        raise exception 'The Veterinarian assignment changed since it was read'
            using hint = 'STALE_ASSIGNMENT';
    end if;

    -- 8. Target eligibility, uniform for unknown, foreign, and ineligible.
    if not public.appointment_veterinarian_is_eligible(p_veterinarian_clinic_assignment_id, p_clinic_id) then
        raise exception 'The Veterinarian cannot be assigned to this Appointment'
            using errcode = '23514', hint = 'VETERINARIAN_NOT_ELIGIBLE';
    end if;

    -- 9. Commercial availability of scheduling for a future commitment only.
    if appointment_record.lifecycle_state = 'CONFIRMED'
       and not public.organization_has_professional_entitlement(clinic_organization_id, 'PROFESSIONAL_SCHEDULING') then
        raise exception 'Scheduling is currently unavailable for this Organization'
            using errcode = '42501', hint = 'SCHEDULING_SERVICE_UNAVAILABLE';
    end if;

    -- 10–11. Profiles, writes, overlap rule.
    created_assignment_id := public.establish_appointment_veterinarian_period(
        appointment_record.id, appointment_record.lifecycle_state,
        current_record.id, current_record.veterinarian_clinic_assignment_id,
        p_veterinarian_clinic_assignment_id, acting_user_id
    );

    return jsonb_build_object(
        'outcome', case when current_record.id is null then 'ASSIGNED' else 'REASSIGNED' end,
        'assignment_token', created_assignment_id
    );
end;
$$;

revoke all privileges
on function public.assign_appointment_veterinarian(uuid, uuid, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.assign_appointment_veterinarian(uuid, uuid, uuid, uuid)
to authenticated;

-- ==================================================================
-- 4c. Self-assignment (SPEC-APT-007 BR-33, BR-34).
-- ==================================================================

create function public.assign_me_to_appointment(
    p_clinic_id uuid,
    p_appointment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor_assignment_id uuid;
    clinic_organization_id uuid;
    appointment_record public.appointments%rowtype;
    current_record public.appointment_veterinarian_assignments%rowtype;
    created_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 3–4. The actor's own eligibility (BR-31), then the Appointment.
    select context.veterinarian_clinic_assignment_id, context.organization_id
    into actor_assignment_id, clinic_organization_id
    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION') as context;
    if actor_assignment_id is null
       or not exists (
           select 1 from public.appointments as appointment
           where appointment.id = p_appointment_id and appointment.clinic_id = p_clinic_id
       ) then
        raise exception 'Appointment unavailable' using errcode = '42501';
    end if;

    -- 5. The assignment lock order; the actor's context is re-verified after
    --    its Clinic Assignment is locked by the establishment rule.
    perform 1 from public.veterinary_organizations as organization
    where organization.id = clinic_organization_id for update;
    perform 1 from public.clinics as clinic
    where clinic.id = p_clinic_id for update;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    -- The actor's context may have ended while this call waited for the locks.
    if not public.appointment_veterinarian_is_eligible(actor_assignment_id, p_clinic_id) then
        raise exception 'Appointment unavailable' using errcode = '42501';
    end if;

    select assignment.* into current_record
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null
    for update;

    -- 6. Lifecycle.
    if not public.appointment_accepts_veterinarian_assignment(
           appointment_record.id, appointment_record.lifecycle_state) then
        raise exception 'The Appointment cannot receive a Veterinarian assignment'
            using errcode = '23514', hint = 'APPOINTMENT_STATE_INVALID';
    end if;

    -- 7. Never displace an eligible colleague.
    if current_record.id is not null
       and public.appointment_veterinarian_is_eligible(current_record.veterinarian_clinic_assignment_id, p_clinic_id) then
        if current_record.veterinarian_clinic_assignment_id = actor_assignment_id then
            return jsonb_build_object('outcome', 'ALREADY_ASSIGNED', 'assignment_token', current_record.id);
        end if;
        raise exception 'Another Veterinarian is assigned to this Appointment'
            using errcode = '23514', hint = 'ASSIGNED_TO_ANOTHER_VETERINARIAN';
    end if;

    -- 9. Commercial availability of scheduling for a future commitment only.
    if appointment_record.lifecycle_state = 'CONFIRMED'
       and not public.organization_has_professional_entitlement(clinic_organization_id, 'PROFESSIONAL_SCHEDULING') then
        raise exception 'Scheduling is currently unavailable for this Organization'
            using errcode = '42501', hint = 'SCHEDULING_SERVICE_UNAVAILABLE';
    end if;

    -- 10–11.
    created_assignment_id := public.establish_appointment_veterinarian_period(
        appointment_record.id, appointment_record.lifecycle_state,
        current_record.id, current_record.veterinarian_clinic_assignment_id,
        actor_assignment_id, acting_user_id
    );

    if not public.appointment_veterinarian_is_eligible(actor_assignment_id, p_clinic_id) then
        raise exception 'Appointment unavailable' using errcode = '42501';
    end if;

    return jsonb_build_object('outcome', 'ASSIGNED', 'assignment_token', created_assignment_id);
end;
$$;

revoke all privileges
on function public.assign_me_to_appointment(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.assign_me_to_appointment(uuid, uuid)
to authenticated;

-- ==================================================================
-- 4d. Candidates and history (SPEC-APT-007 BR-38).
-- ==================================================================

create function public.get_appointment_veterinarian_candidates(
    p_clinic_id uuid,
    p_appointment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    current_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not public.user_has_clinic_capability(acting_user_id, p_clinic_id, 'APPOINTMENT_ASSIGN_VETERINARIAN')
       or not exists (
           select 1 from public.appointments as appointment
           where appointment.id = p_appointment_id and appointment.clinic_id = p_clinic_id
       ) then
        return jsonb_build_object('status', 'DENIED');
    end if;

    select assignment.veterinarian_clinic_assignment_id into current_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = p_appointment_id
      and assignment.effective_end is null;

    return jsonb_build_object(
        'status', 'PERMITTED',
        'candidates', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'veterinarian_clinic_assignment_id', candidate.id,
                       'display_name', candidate.display_name,
                       'is_me', candidate.user_id = acting_user_id,
                       'is_current_assignee', candidate.id is not distinct from current_assignment_id
                   ) order by candidate.display_name nulls last, candidate.id)
            from (
                select assignment.id, membership.user_id,
                       public.veterinarian_clinic_assignment_display_name(assignment.id) as display_name
                from public.veterinarian_clinic_assignments as assignment
                join public.organization_memberships as membership
                  on membership.id = assignment.supporting_membership_id
                where assignment.clinic_id = p_clinic_id
                  and public.appointment_veterinarian_is_eligible(assignment.id, p_clinic_id)
            ) as candidate
        ), '[]'::jsonb),
        'history', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'veterinarian_display_name',
                           public.veterinarian_clinic_assignment_display_name(period.veterinarian_clinic_assignment_id),
                       'assigned_at', period.effective_start,
                       'ended_at', period.effective_end,
                       'assigned_by_display_name',
                           nullif(btrim(assigning_profile.display_name, E' \t\n\r\f\013'), '')
                   ) order by period.effective_start, period.id)
            from public.appointment_veterinarian_assignments as period
            left join public.user_profiles as assigning_profile
              on assigning_profile.user_id = period.assigned_by_user_id
            where period.appointment_id = p_appointment_id
        ), '[]'::jsonb)
    );
end;
$$;

revoke all privileges
on function public.get_appointment_veterinarian_candidates(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.get_appointment_veterinarian_candidates(uuid, uuid)
to authenticated;

-- ==================================================================
-- 5. Withdrawn client paths (SPEC-APT-007 BR-40).
-- ==================================================================

revoke execute
on function public.assign_veterinarian_to_appointment(uuid, uuid)
from authenticated;

revoke execute
on function public.reassign_veterinarian(uuid, uuid)
from authenticated;

commit;

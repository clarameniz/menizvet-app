-- Minimal Clinical Record — Phase 1
-- (SPEC-MED-001 §15, SPEC-MED-002 §14, SPEC-MED-003 §15, SPEC-MED-008 §15,
-- SPEC-MED-009, SPEC-APT-012 BR-48; REQ-MED-003/007/013, REQ-ACC-002).
--
-- Appointment-keyed, client-safe clinical operations so the Professional
-- client can start an Appointment-backed Clinical Encounter, document it in
-- several Clinical Record Entries, finalize them (Guardian publication) and
-- mark care as finished, without ever handling a Care Authorization id.
--
--   1. One Encounter per Care Authorization becomes structural: the
--      non-unique clinical_encounters_care_authorization_idx is replaced by
--      the unique constraint clinical_encounters_care_authorization_key
--      (SPEC-MED-001 BR-34 rule 5 / BR-38). No workflow ever permitted a
--      second Encounter; existing data is checked by the constraint itself.
--   2. Draft creation record (SPEC-MED-002 BR-34): nullable
--      creation_idempotency_key + creation_request_digest (SHA-256 of the
--      canonical requested creation facts), both or neither, unique per
--      creating User, immutable through the existing Entry integrity trigger.
--      Rows created through any other path keep both NULL.
--   3. Private helpers: the acting Veterinarian's current exact-Clinic
--      clinical context (non-locking and locking forms, same lock order as
--      resolve_current_veterinarian_context_after_lock), the Appointment's
--      confirmation/completion facts, and the Draft field rules.
--   4. Client operations, authenticated only, authority before any target:
--        start_appointment_clinical_encounter     CREATED | ALREADY_EXISTS
--        create_appointment_clinical_draft        CREATED | ALREADY_CREATED
--        update_appointment_clinical_draft        UPDATED | UNCHANGED
--        finalize_appointment_clinical_entry      FINALIZED | ALREADY_FINALIZED
--        conclude_appointment_clinical_encounter  CONCLUDED | ALREADY_CONCLUDED
--      Unknown/foreign Clinic, Appointment or Entry and missing authority are
--      one uniform 42501 'Clinical record unavailable' (no hint); every other
--      rejection carries a stable hint. Writes delegate to the existing
--      trusted writers where one exists (Encounter establishment, Draft
--      update, finalization); Draft creation writes the creation record
--      itself and Conclude records the statement instant. Lock order is the
--      existing one: Organization -> Clinic -> Membership/Grant/Assignment
--      -> Appointment (Start only) -> Care Authorization -> Encounter ->
--      Entry -> Attachments.
--   5. view_appointment_clinical_record: one audited read of the Encounter's
--      clinical work (one Medical Access Audit Event per read, never one per
--      Entry), or operational start context with no audit before an
--      Encounter exists. Non-locking. No Care Authorization, User, Auth,
--      Membership, Grant or Clinic Assignment id is returned.
--   6. get_clinic_appointment_schedule gains has_clinical_encounter (dropped
--      and recreated; body, attributes and ACL otherwise those of
--      20261022090000).
--   7. ACL: authenticated EXECUTE is withdrawn from the generic clinical
--      writers (create_clinical_encounter, create_draft_clinical_record_entry,
--      update_draft_clinical_record_entry, finalize_clinical_record_entry,
--      conclude_clinical_encounter) and from the superseded
--      view_care_authorization_clinical_work_context; service_role keeps them
--      for trusted compatibility. Guardian history, professional longitudinal
--      history, view_clinical_record_entry, the Care Authorization reads and
--      create_clinical_amendment are unchanged.
begin;

-- ==================================================================
-- 1. Structural one-Encounter-per-Care-Authorization backstop.
-- ==================================================================

drop index public.clinical_encounters_care_authorization_idx;

alter table public.clinical_encounters
    add constraint clinical_encounters_care_authorization_key
        unique (care_authorization_id);

-- ==================================================================
-- 2. Draft creation record (SPEC-MED-002 BR-34).
-- ==================================================================

alter table public.clinical_record_entries
    add column creation_idempotency_key uuid,
    add column creation_request_digest bytea;

alter table public.clinical_record_entries
    add constraint clinical_record_entries_creation_key
        unique (created_by_user_id, creation_idempotency_key),
    add constraint clinical_record_entries_creation_record_check
        check (
            (creation_idempotency_key is null) = (creation_request_digest is null)
            and (creation_request_digest is null
                 or octet_length(creation_request_digest) = 32)
        );

-- Body of 20260829120000_clinical_care.sql, plus the creation record among the
-- immutable identity facts.
create or replace function public.enforce_clinical_record_entry_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    encounter_record public.clinical_encounters%rowtype;
    clinical_fields_changed boolean;
begin
    if tg_op = 'DELETE' then
        raise exception 'Clinical Record Entries cannot be deleted'
            using errcode = '23514';
    end if;

    if tg_op = 'INSERT' then
        if new.lifecycle_state <> 'DRAFT'
           or new.draft_revision <> 0
           or new.finalized_at is not null
           or new.finalized_by_user_id is not null
           or new.finalizer_veterinarian_clinic_assignment_id is not null then
            raise exception 'Clinical Record Entry must be established as revision-zero DRAFT'
                using errcode = '23514';
        end if;

        if new.created_at > clock_timestamp()
           or new.last_modified_at > clock_timestamp()
           or new.clinical_event_at > clock_timestamp() then
            raise exception 'Clinical Record Entry cannot be established with a future timestamp'
                using errcode = '22023';
        end if;

        select encounter_record_row.*
        into encounter_record
        from public.clinical_encounters as encounter_record_row
        where encounter_record_row.id = new.clinical_encounter_id;

        if not found then
            raise exception 'Clinical Record Entry requires its Clinical Encounter'
                using errcode = '23503';
        end if;

        if new.creator_veterinarian_clinic_assignment_id is distinct from
           encounter_record.responsible_veterinarian_clinic_assignment_id then
            raise exception 'Clinical Record Entry creator must be the Encounter responsible Veterinarian Clinic Assignment'
                using errcode = '23514';
        end if;

        perform public.assert_vca_user_provider_context(
            new.creator_veterinarian_clinic_assignment_id,
            new.created_by_user_id,
            encounter_record.clinic_id,
            encounter_record.organization_id
        );

        return new;
    end if;

    if old.id is distinct from new.id
       or old.clinical_encounter_id is distinct from new.clinical_encounter_id
       or old.created_by_user_id is distinct from new.created_by_user_id
       or old.creator_veterinarian_clinic_assignment_id is distinct from
          new.creator_veterinarian_clinic_assignment_id
       or old.created_at is distinct from new.created_at
       or old.creation_idempotency_key is distinct from new.creation_idempotency_key
       or old.creation_request_digest is distinct from new.creation_request_digest then
        raise exception 'Clinical Record Entry identity and original authorship are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state = 'FINALIZED' then
        raise exception 'Finalized Clinical Record Entry cannot be modified'
            using errcode = '23514';
    end if;

    clinical_fields_changed :=
        old.clinical_content is distinct from new.clinical_content
        or old.category is distinct from new.category
        or old.other_category_context is distinct from new.other_category_context
        or old.clinical_event_at is distinct from new.clinical_event_at;

    if new.lifecycle_state = 'DRAFT' then
        if new.finalized_at is not null
           or new.finalized_by_user_id is not null
           or new.finalizer_veterinarian_clinic_assignment_id is not null then
            raise exception 'Draft Clinical Record Entry cannot carry finalization facts'
                using errcode = '23514';
        end if;

        if clinical_fields_changed then
            if new.draft_revision <> old.draft_revision + 1
               or new.last_modified_at <= old.last_modified_at
               or new.last_modified_at > clock_timestamp() then
                raise exception 'Material Draft update requires one revision increment and a valid modification time'
                    using errcode = '23514';
            end if;
        elsif new.draft_revision is distinct from old.draft_revision
              or new.last_modified_at is distinct from old.last_modified_at then
            raise exception 'No-op Draft update cannot change revision or modification time'
                using errcode = '23514';
        end if;

        if new.clinical_event_at > clock_timestamp() then
            raise exception 'Clinical event time cannot be in the future'
                using errcode = '22023';
        end if;

        return new;
    end if;

    if new.lifecycle_state <> 'FINALIZED' then
        raise exception 'Clinical Record Entry supports only DRAFT to FINALIZED transition'
            using errcode = '23514';
    end if;

    if clinical_fields_changed
       or new.draft_revision is distinct from old.draft_revision
       or new.last_modified_at is distinct from old.last_modified_at then
        raise exception 'Finalization cannot silently replace Draft clinical content or revision'
            using errcode = '23514';
    end if;

    if new.finalized_at > clock_timestamp() then
        raise exception 'Clinical Record Entry finalization time cannot be in the future'
            using errcode = '22023';
    end if;

    select encounter_record_row.*
    into encounter_record
    from public.clinical_encounters as encounter_record_row
    where encounter_record_row.id = new.clinical_encounter_id;

    perform public.assert_vca_user_provider_context(
        new.finalizer_veterinarian_clinic_assignment_id,
        new.finalized_by_user_id,
        encounter_record.clinic_id,
        encounter_record.organization_id
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinical_record_entry_integrity()
from public, anon, authenticated;

-- ==================================================================
-- 3. Private helpers.
-- ==================================================================

-- The acting User's current exact-Clinic Veterinarian context holding the
-- capability (SPEC-MED-001 BR-37): current Membership, current
-- Organization-scoped VETERINARIAN Grant, own Profile, current Clinic
-- Assignment. No row when any part is missing or the Clinic is unknown.
create function public.clinical_actor_context_at(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns table (
    organization_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid,
    assignment_effective_start timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select clinic.organization_id,
           membership.id,
           grant_record.id,
           assignment.id,
           assignment.effective_start
    from public.clinics as clinic
    join public.organization_memberships as membership
      on membership.organization_id = clinic.organization_id
     and membership.user_id = p_user_id
     and membership.effective_start <= statement_timestamp()
     and membership.effective_end is null
    join public.organization_responsibility_grants as grant_record
      on grant_record.membership_id = membership.id
     and grant_record.responsibility = 'VETERINARIAN'
     and grant_record.scope_type = 'ORGANIZATION'
     and grant_record.clinic_id is null
     and grant_record.effective_start <= statement_timestamp()
     and grant_record.effective_end is null
    join public.veterinarian_clinic_assignments as assignment
      on assignment.supporting_membership_id = membership.id
     and assignment.clinic_id = clinic.id
     and public.veterinarian_clinic_assignment_is_current(assignment.id)
    join public.veterinarian_professional_profiles as profile
      on profile.id = assignment.professional_profile_id
     and profile.user_id = p_user_id
    where clinic.id = p_clinic_id
      and p_capability in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
      and public.user_has_clinic_capability(p_user_id, p_clinic_id, p_capability)
    order by assignment.id
    limit 1
$$;

revoke all privileges
on function public.clinical_actor_context_at(uuid, uuid, text)
from public, anon, authenticated, service_role;

-- The same context for a write, decided before and again under the
-- Organization and Clinic locks, with the Membership, Grant and Assignment
-- locked (lock order of resolve_current_veterinarian_context_after_lock).
create function public.lock_clinical_actor_context(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns table (
    organization_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid,
    assignment_effective_start timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_organization_id uuid;
begin
    select context.organization_id
    into resolved_organization_id
    from public.clinical_actor_context_at(p_user_id, p_clinic_id, p_capability) as context;

    if not found then
        return;
    end if;

    perform 1
    from public.veterinary_organizations as organization_record
    where organization_record.id = resolved_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = resolved_organization_id
    for update;

    return query
    select resolved_organization_id,
           membership.id,
           grant_record.id,
           assignment.id,
           assignment.effective_start
    from public.organization_memberships as membership
    join public.organization_responsibility_grants as grant_record
      on grant_record.membership_id = membership.id
    join public.veterinarian_clinic_assignments as assignment
      on assignment.supporting_membership_id = membership.id
     and assignment.clinic_id = p_clinic_id
    join public.veterinarian_professional_profiles as profile
      on profile.id = assignment.professional_profile_id
    where membership.organization_id = resolved_organization_id
      and membership.user_id = p_user_id
      and membership.effective_start <= statement_timestamp()
      and membership.effective_end is null
      and grant_record.responsibility = 'VETERINARIAN'
      and grant_record.scope_type = 'ORGANIZATION'
      and grant_record.clinic_id is null
      and grant_record.effective_start <= statement_timestamp()
      and grant_record.effective_end is null
      and public.veterinarian_clinic_assignment_is_current(assignment.id)
      and profile.user_id = p_user_id
      and public.user_has_clinic_capability(p_user_id, p_clinic_id, p_capability)
    order by assignment.id
    limit 1
    for update of membership, grant_record, assignment;
end;
$$;

revoke all privileges
on function public.lock_clinical_actor_context(uuid, uuid, text)
from public, anon, authenticated, service_role;

-- The lifecycle facts bounding an Appointment-backed care start
-- (SPEC-MED-001 BR-34 rules 7, 8, 10).
create function public.appointment_clinical_care_window(p_appointment_id uuid)
returns table (
    confirmation_count integer,
    confirmed_at timestamptz,
    completion_count integer,
    completed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        (select count(*)::integer
         from public.appointment_lifecycle_events as confirmation
         where confirmation.appointment_id = p_appointment_id
           and confirmation.from_state = 'REQUESTED'
           and confirmation.to_state = 'CONFIRMED'),
        (select min(confirmation.effective_at)
         from public.appointment_lifecycle_events as confirmation
         where confirmation.appointment_id = p_appointment_id
           and confirmation.from_state = 'REQUESTED'
           and confirmation.to_state = 'CONFIRMED'),
        (select count(*)::integer
         from public.appointment_lifecycle_events as completion
         where completion.appointment_id = p_appointment_id
           and completion.from_state = 'CONFIRMED'
           and completion.to_state = 'COMPLETED'),
        (select min(completion.effective_at)
         from public.appointment_lifecycle_events as completion
         where completion.appointment_id = p_appointment_id
           and completion.from_state = 'CONFIRMED'
           and completion.to_state = 'COMPLETED')
$$;

revoke all privileges
on function public.appointment_clinical_care_window(uuid)
from public, anon, authenticated, service_role;

-- Draft field rules shared by creation and update (SPEC-MED-002 BR-33).
-- p_other_category_context is already normalized (trimmed, blank -> NULL).
create function public.assert_clinical_draft_fields(
    p_category text,
    p_other_category_context text,
    p_clinical_event_at timestamptz
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if p_category is not null and p_category not in (
        'EXAMINATION', 'DIAGNOSIS', 'TREATMENT', 'PROCEDURE', 'VACCINATION',
        'PRESCRIPTION', 'LABORATORY_RESULT', 'IMAGING_RESULT', 'CLINICAL_NOTE', 'OTHER'
    ) then
        raise exception 'Unsupported clinical event category'
            using errcode = '22023', hint = 'INVALID_CATEGORY';
    end if;

    if p_other_category_context is not null and p_category is distinct from 'OTHER' then
        raise exception 'OTHER context is accepted only with the OTHER category'
            using errcode = '22023', hint = 'OTHER_CONTEXT_NOT_ALLOWED';
    end if;

    if p_clinical_event_at is not null and not isfinite(p_clinical_event_at) then
        raise exception 'Clinical event time must be finite'
            using errcode = '22023', hint = 'INVALID_EVENT_TIME';
    end if;

    if p_clinical_event_at > statement_timestamp() then
        raise exception 'Clinical event time cannot be in the future'
            using errcode = '22023', hint = 'EVENT_TIME_IN_FUTURE';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinical_draft_fields(text, text, timestamptz)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 4a. Start Encounter (SPEC-MED-001 BR-39–BR-42).
-- ==================================================================

create function public.start_appointment_clinical_encounter(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_started_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    window_record record;
    requested_start timestamptz;
    created_encounter_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 1. Authority before any target, then the Appointment of that Clinic.
    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_CARE');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id
    for update;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = appointment_record.id
    for update;

    -- 2. Reconciliation with an existing Encounter (BR-42).
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.appointment_id = appointment_record.id;
    if found then
        if encounter_record.responsible_veterinarian_clinic_assignment_id
               = actor.veterinarian_clinic_assignment_id
           and (p_started_at is null or p_started_at = encounter_record.started_at) then
            return jsonb_build_object(
                'outcome', 'ALREADY_EXISTS',
                'encounter_id', encounter_record.id,
                'lifecycle_state', encounter_record.lifecycle_state,
                'started_at', encounter_record.started_at
            );
        end if;
        raise exception 'A Clinical Encounter already exists for this Appointment'
            using errcode = '23514', hint = 'ENCOUNTER_EXISTS';
    end if;

    -- 3. Commercial availability of new clinical care (SPEC-SUB-004 BR-14).
    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then
        raise exception 'Clinical care is currently unavailable for this Organization'
            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';
    end if;

    -- 4. Appointment lifecycle with its legitimate confirmation/completion.
    select * into window_record
    from public.appointment_clinical_care_window(appointment_record.id);
    if appointment_record.lifecycle_state not in ('CONFIRMED', 'COMPLETED')
       or window_record.confirmation_count <> 1
       or (appointment_record.lifecycle_state = 'COMPLETED'
           and window_record.completion_count <> 1) then
        raise exception 'The Appointment cannot back a Clinical Encounter'
            using errcode = '23514', hint = 'APPOINTMENT_STATE_INVALID';
    end if;

    -- 5. The Appointment-derived Care Authorization.
    if care_auth_record.id is null
       or care_auth_record.lifecycle_state <> 'ACTIVE'
       or care_auth_record.purpose <> 'APPOINTMENT_CARE' then
        raise exception 'The Appointment Care Authorization is not active'
            using errcode = '23514', hint = 'CARE_AUTHORIZATION_INACTIVE';
    end if;

    -- 6. Care start (BR-40). NULL means "Start now": the statement instant.
    if p_started_at is null then
        if appointment_record.lifecycle_state = 'COMPLETED' then
            raise exception 'The care start is required for a completed Appointment'
                using errcode = '22023', hint = 'START_TIME_REQUIRED';
        end if;
        requested_start := statement_timestamp();
    else
        if not isfinite(p_started_at) then
            raise exception 'The care start must be finite'
                using errcode = '22023', hint = 'INVALID_START_TIME';
        end if;
        requested_start := p_started_at;
    end if;

    if requested_start < greatest(
            window_record.confirmed_at,
            care_auth_record.granted_at,
            actor.assignment_effective_start
        )
       or requested_start > statement_timestamp()
       or (appointment_record.lifecycle_state = 'COMPLETED'
           and requested_start > window_record.completed_at) then
        raise exception 'The care start is outside the permitted window'
            using errcode = '23514', hint = 'START_TIME_OUT_OF_BOUNDS';
    end if;

    -- 7. The trusted writer applies the same establishment rules again.
    created_encounter_id := public.create_clinical_encounter(
        care_auth_record.id, requested_start, appointment_record.id
    );

    return jsonb_build_object(
        'outcome', 'CREATED',
        'encounter_id', created_encounter_id,
        'lifecycle_state', 'ACTIVE',
        'started_at', requested_start
    );
end;
$$;

revoke all privileges
on function public.start_appointment_clinical_encounter(uuid, uuid, timestamptz)
from public, anon, authenticated, service_role;
grant execute
on function public.start_appointment_clinical_encounter(uuid, uuid, timestamptz)
to authenticated;

-- ==================================================================
-- 4b. Create Draft (SPEC-MED-002 BR-33/BR-34).
-- ==================================================================

create function public.create_appointment_clinical_draft(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_creation_idempotency_key uuid,
    p_category text,
    p_clinical_content text,
    p_other_category_context text,
    p_clinical_event_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    existing_entry public.clinical_record_entries%rowtype;
    normalized_content text;
    normalized_other_context text;
    requested_digest bytea;
    operation_timestamp timestamptz;
    created_entry_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.appointment_id = p_appointment_id;
    if not found then
        raise exception 'No Clinical Encounter exists for this Appointment'
            using errcode = '23514', hint = 'ENCOUNTER_NOT_STARTED';
    end if;

    if p_creation_idempotency_key is null then
        raise exception 'A creation key is required'
            using errcode = '22023', hint = 'KEY_REQUIRED';
    end if;

    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');
    perform public.assert_clinical_draft_fields(p_category, normalized_other_context, p_clinical_event_at);

    -- The requested creation facts, canonical and timezone-independent.
    requested_digest := sha256(convert_to(jsonb_build_object(
        'clinical_encounter_id', encounter_record.id,
        'category', p_category,
        'clinical_content', normalized_content,
        'other_category_context', normalized_other_context,
        'clinical_event_at', extract(epoch from p_clinical_event_at)
    )::text, 'UTF8'));

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id
    for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id
    for update;

    -- Exact replay or contradictory reuse of this User's key (BR-34).
    select entry.* into existing_entry
    from public.clinical_record_entries as entry
    where entry.created_by_user_id = acting_user_id
      and entry.creation_idempotency_key = p_creation_idempotency_key;
    if found then
        if existing_entry.creation_request_digest = requested_digest then
            return jsonb_build_object(
                'outcome', 'ALREADY_CREATED',
                'entry_id', existing_entry.id,
                'revision_sequence', existing_entry.draft_revision
            );
        end if;
        raise exception 'The creation key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    if actor.veterinarian_clinic_assignment_id is distinct from
       encounter_record.responsible_veterinarian_clinic_assignment_id then
        raise exception 'Only the responsible Veterinarian may add an entry'
            using errcode = '23514', hint = 'RESPONSIBLE_VETERINARIAN_REQUIRED';
    end if;

    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'The Care Authorization no longer permits documentation'
            using errcode = '23514', hint = 'CARE_AUTHORIZATION_INACTIVE';
    end if;

    operation_timestamp := clock_timestamp();
    insert into public.clinical_record_entries (
        clinical_encounter_id, created_by_user_id,
        creator_veterinarian_clinic_assignment_id, created_at, lifecycle_state,
        clinical_content, category, other_category_context, clinical_event_at,
        draft_revision, last_modified_at,
        creation_idempotency_key, creation_request_digest
    ) values (
        encounter_record.id, acting_user_id,
        actor.veterinarian_clinic_assignment_id, operation_timestamp, 'DRAFT',
        normalized_content, p_category, normalized_other_context, p_clinical_event_at,
        0, operation_timestamp,
        p_creation_idempotency_key, requested_digest
    ) returning id into created_entry_id;

    return jsonb_build_object(
        'outcome', 'CREATED',
        'entry_id', created_entry_id,
        'revision_sequence', 0
    );
end;
$$;

revoke all privileges
on function public.create_appointment_clinical_draft(uuid, uuid, uuid, text, text, text, timestamptz)
from public, anon, authenticated, service_role;
grant execute
on function public.create_appointment_clinical_draft(uuid, uuid, uuid, text, text, text, timestamptz)
to authenticated;

-- ==================================================================
-- 4c. Update Draft (SPEC-MED-002 BR-35).
-- ==================================================================

create function public.update_appointment_clinical_draft(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_entry_id uuid,
    p_expected_revision bigint,
    p_category text,
    p_clinical_content text,
    p_other_category_context text,
    p_clinical_event_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    entry_record public.clinical_record_entries%rowtype;
    normalized_content text;
    normalized_other_context text;
    new_revision bigint;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.appointment_id = p_appointment_id;
    if not found then
        raise exception 'No Clinical Encounter exists for this Appointment'
            using errcode = '23514', hint = 'ENCOUNTER_NOT_STARTED';
    end if;

    perform 1
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id
      and entry.clinical_encounter_id = encounter_record.id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    if p_expected_revision is null or p_expected_revision < 0 then
        raise exception 'The expected revision must be a non-negative integer'
            using errcode = '22023', hint = 'INVALID_REVISION';
    end if;

    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');
    perform public.assert_clinical_draft_fields(p_category, normalized_other_context, p_clinical_event_at);

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id
    for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id
    for update;
    select entry.* into entry_record
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id
    for update;

    if entry_record.lifecycle_state <> 'DRAFT' then
        raise exception 'A finalized entry cannot be edited'
            using errcode = '23514', hint = 'ENTRY_FINALIZED';
    end if;

    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'The Care Authorization no longer permits documentation'
            using errcode = '23514', hint = 'CARE_AUTHORIZATION_INACTIVE';
    end if;

    -- Deterministic client-input mismatch: plain P0001, never 40001/409.
    if entry_record.draft_revision <> p_expected_revision then
        raise exception 'The entry changed since it was read'
            using hint = 'STALE_REVISION';
    end if;

    new_revision := public.update_draft_clinical_record_entry(
        p_entry_id, p_expected_revision, normalized_content, p_category,
        normalized_other_context, p_clinical_event_at
    );

    return jsonb_build_object(
        'outcome', case when new_revision > p_expected_revision then 'UPDATED' else 'UNCHANGED' end,
        'entry_id', p_entry_id,
        'revision_sequence', new_revision
    );
end;
$$;

revoke all privileges
on function public.update_appointment_clinical_draft(uuid, uuid, uuid, bigint, text, text, text, timestamptz)
from public, anon, authenticated, service_role;
grant execute
on function public.update_appointment_clinical_draft(uuid, uuid, uuid, bigint, text, text, text, timestamptz)
to authenticated;

-- ==================================================================
-- 4d. Finalize Entry (SPEC-MED-003 BR-37/BR-38).
-- ==================================================================

create function public.finalize_appointment_clinical_entry(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_entry_id uuid,
    p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    entry_record public.clinical_record_entries%rowtype;
    attachment_record public.clinical_attachments%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.appointment_id = p_appointment_id;
    if not found then
        raise exception 'No Clinical Encounter exists for this Appointment'
            using errcode = '23514', hint = 'ENCOUNTER_NOT_STARTED';
    end if;

    perform 1
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id
      and entry.clinical_encounter_id = encounter_record.id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    if p_expected_revision is null or p_expected_revision < 0 then
        raise exception 'The expected revision must be a non-negative integer'
            using errcode = '22023', hint = 'INVALID_REVISION';
    end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id
    for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id
    for update;
    select entry.* into entry_record
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id
    for update;

    -- Repeated finalization keeps the first one (BR-36).
    if entry_record.lifecycle_state = 'FINALIZED' then
        return jsonb_build_object(
            'outcome', 'ALREADY_FINALIZED',
            'entry_id', entry_record.id,
            'finalized_at', entry_record.finalized_at
        );
    end if;

    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'The Care Authorization no longer permits documentation'
            using errcode = '23514', hint = 'CARE_AUTHORIZATION_INACTIVE';
    end if;

    if entry_record.draft_revision <> p_expected_revision then
        raise exception 'The entry changed since it was read'
            using hint = 'STALE_REVISION';
    end if;

    if entry_record.clinical_content is null
       or entry_record.category is null
       or (entry_record.category = 'OTHER' and entry_record.other_category_context is null) then
        raise exception 'The entry is not complete enough to finalize'
            using errcode = '23514', hint = 'ENTRY_INCOMPLETE';
    end if;

    for attachment_record in
        select attachment.*
        from public.clinical_attachments as attachment
        where attachment.clinical_record_entry_id = p_entry_id
          and attachment.removed_at is null
        order by attachment.id
        for update
    loop
        if attachment_record.validation_state = 'PENDING' then
            raise exception 'An attachment of the entry is still pending'
                using errcode = '23514', hint = 'PENDING_ATTACHMENT';
        end if;
        if attachment_record.validation_state = 'AVAILABLE' and not exists (
            select 1
            from storage.objects as object_record
            where object_record.bucket_id = 'clinical-attachments'
              and object_record.name = 'v1/' || attachment_record.storage_object_id::text
        ) then
            raise exception 'An attachment of the entry is unavailable'
                using errcode = '23514', hint = 'ATTACHMENT_UNAVAILABLE';
        end if;
    end loop;

    perform public.finalize_clinical_record_entry(p_entry_id, p_expected_revision);

    select entry.* into entry_record
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id;

    return jsonb_build_object(
        'outcome', 'FINALIZED',
        'entry_id', entry_record.id,
        'finalized_at', entry_record.finalized_at
    );
end;
$$;

revoke all privileges
on function public.finalize_appointment_clinical_entry(uuid, uuid, uuid, bigint)
from public, anon, authenticated, service_role;
grant execute
on function public.finalize_appointment_clinical_entry(uuid, uuid, uuid, bigint)
to authenticated;

-- ==================================================================
-- 4e. Conclude Encounter (SPEC-MED-008 BR-36).
-- ==================================================================

create function public.conclude_appointment_clinical_encounter(
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
    actor record;
    encounter_record public.clinical_encounters%rowtype;
    conclusion_instant timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_CARE');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.appointment_id = p_appointment_id;
    if not found then
        raise exception 'No Clinical Encounter exists for this Appointment'
            using errcode = '23514', hint = 'ENCOUNTER_NOT_STARTED';
    end if;

    perform 1
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id
    for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id
    for update;

    -- Repeated conclusion keeps the first one (BR-31).
    if encounter_record.lifecycle_state = 'CONCLUDED' then
        return jsonb_build_object(
            'outcome', 'ALREADY_CONCLUDED',
            'encounter_id', encounter_record.id,
            'concluded_at', encounter_record.concluded_at
        );
    end if;

    -- The statement instant, never earlier than the care start.
    conclusion_instant := greatest(statement_timestamp(), encounter_record.started_at);

    update public.clinical_encounters
    set lifecycle_state = 'CONCLUDED',
        concluded_at = conclusion_instant,
        concluded_by_user_id = acting_user_id,
        concluding_veterinarian_clinic_assignment_id = actor.veterinarian_clinic_assignment_id
    where id = encounter_record.id;

    return jsonb_build_object(
        'outcome', 'CONCLUDED',
        'encounter_id', encounter_record.id,
        'concluded_at', conclusion_instant
    );
end;
$$;

revoke all privileges
on function public.conclude_appointment_clinical_encounter(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.conclude_appointment_clinical_encounter(uuid, uuid)
to authenticated;

-- ==================================================================
-- 5. Appointment clinical record read (SPEC-MED-009).
-- ==================================================================

create function public.view_appointment_clinical_record(
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
    actor record;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    window_record record;
    audit_operation text;
    can_start boolean := false;
    unavailable_reason text;
    window_from timestamptz;
    window_until timestamptz;
    entries_payload jsonb;
    entry_count integer;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select * into actor
    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');

    if not found then
        -- A denied attempt on an Appointment of that Clinic that has an
        -- Encounter is a denied clinical-content access (SPEC-MED-009 BR-5).
        select encounter_row.* into encounter_record
        from public.appointments as appointment
        join public.clinical_encounters as encounter_row
          on encounter_row.appointment_id = appointment.id
        where appointment.id = p_appointment_id
          and appointment.clinic_id = p_clinic_id;
        if found then
            perform public.establish_medical_access_audit_event(
                p_acting_user_id => acting_user_id,
                p_pet_id => encounter_record.pet_id,
                p_operation => case when encounter_record.lifecycle_state = 'ACTIVE'
                                    then 'ACCESS_FOR_CLINICAL_CARE'
                                    else 'ACCESS_FOR_POST_CARE_DOCUMENTATION' end,
                p_outcome => 'DENIED',
                p_actor_context => 'PROFESSIONAL_CLINICAL',
                p_protected_resource_scope => 'ENCOUNTER_MEDICAL_INFORMATION',
                p_occurred_at => clock_timestamp(),
                p_care_authorization_id => encounter_record.care_authorization_id,
                p_accessing_clinic_id => encounter_record.clinic_id,
                p_accessing_organization_id => encounter_record.organization_id,
                p_appointment_id => encounter_record.appointment_id,
                p_clinical_encounter_id => encounter_record.id
            );
        end if;
        return jsonb_build_object('status', 'DENIED');
    end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        return jsonb_build_object('status', 'DENIED');
    end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = appointment_record.id;

    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.appointment_id = appointment_record.id;

    if not found then
        -- Operational start context only; no medical information, no audit.
        select * into window_record
        from public.appointment_clinical_care_window(appointment_record.id);

        if not public.user_has_clinic_capability(acting_user_id, p_clinic_id, 'CLINICAL_CARE') then
            unavailable_reason := 'CLINICAL_CARE_NOT_PERMITTED';
        elsif appointment_record.lifecycle_state not in ('CONFIRMED', 'COMPLETED')
              or window_record.confirmation_count <> 1
              or (appointment_record.lifecycle_state = 'COMPLETED'
                  and window_record.completion_count <> 1) then
            unavailable_reason := 'APPOINTMENT_STATE';
        elsif care_auth_record.id is null
              or care_auth_record.lifecycle_state <> 'ACTIVE'
              or care_auth_record.purpose <> 'APPOINTMENT_CARE' then
            unavailable_reason := 'CARE_AUTHORIZATION_INACTIVE';
        elsif not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then
            unavailable_reason := 'CLINICAL_SERVICE_UNAVAILABLE';
        else
            window_from := greatest(
                window_record.confirmed_at,
                care_auth_record.granted_at,
                actor.assignment_effective_start
            );
            window_until := case when appointment_record.lifecycle_state = 'COMPLETED'
                                 then window_record.completed_at end;
            if window_from > coalesce(window_until, statement_timestamp()) then
                unavailable_reason := 'NO_VALID_CARE_START';
            else
                can_start := true;
            end if;
        end if;

        return jsonb_build_object(
            'status', 'PERMITTED',
            'appointment', jsonb_build_object(
                'appointment_id', appointment_record.id,
                'lifecycle_state', appointment_record.lifecycle_state
            ),
            'start', jsonb_build_object(
                'can_start', can_start,
                'start_now_allowed', can_start and appointment_record.lifecycle_state = 'CONFIRMED',
                'care_start_required', appointment_record.lifecycle_state = 'COMPLETED',
                'care_start_from', case when can_start then window_from end,
                'care_start_until', case when can_start then window_until end,
                'unavailable_reason', unavailable_reason
            ),
            'encounter', null
        );
    end if;

    audit_operation := case when encounter_record.lifecycle_state = 'ACTIVE'
                            then 'ACCESS_FOR_CLINICAL_CARE'
                            else 'ACCESS_FOR_POST_CARE_DOCUMENTATION' end;

    -- Active care (including revocation-safe continuity) or post-care
    -- documentation under an ACTIVE Authorization (SPEC-MED-009 BR-4).
    if not (encounter_record.lifecycle_state = 'ACTIVE'
            or care_auth_record.lifecycle_state = 'ACTIVE') then
        perform public.establish_medical_access_audit_event(
            p_acting_user_id => acting_user_id,
            p_pet_id => encounter_record.pet_id,
            p_operation => audit_operation,
            p_outcome => 'DENIED',
            p_actor_context => 'PROFESSIONAL_CLINICAL',
            p_protected_resource_scope => 'ENCOUNTER_MEDICAL_INFORMATION',
            p_occurred_at => clock_timestamp(),
            p_care_authorization_id => encounter_record.care_authorization_id,
            p_accessing_clinic_id => encounter_record.clinic_id,
            p_accessing_organization_id => encounter_record.organization_id,
            p_appointment_id => encounter_record.appointment_id,
            p_organization_membership_id => actor.organization_membership_id,
            p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
            p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id,
            p_clinical_encounter_id => encounter_record.id
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    select count(*)::integer
    into entry_count
    from public.clinical_record_entries as entry
    where entry.clinical_encounter_id = encounter_record.id;

    select coalesce(jsonb_agg(jsonb_build_object(
               'entry_id', page.id,
               'lifecycle_state', page.lifecycle_state,
               'revision_sequence', page.draft_revision,
               'category', page.category,
               'other_category_context', page.other_category_context,
               'clinical_content', page.clinical_content,
               'clinical_event_at', page.clinical_event_at,
               'created_at', page.created_at,
               'finalized_at', page.finalized_at,
               'created_by_me', page.created_by_user_id = acting_user_id
           ) order by page.created_at, page.id), '[]'::jsonb)
    into entries_payload
    from (
        select entry.*
        from public.clinical_record_entries as entry
        where entry.clinical_encounter_id = encounter_record.id
        order by entry.created_at, entry.id
        limit 100
    ) as page;

    -- One meaningful protected access, however many Entries (SPEC-MED-009 BR-5).
    perform public.establish_medical_access_audit_event(
        p_acting_user_id => acting_user_id,
        p_pet_id => encounter_record.pet_id,
        p_operation => audit_operation,
        p_outcome => 'PERMITTED',
        p_actor_context => 'PROFESSIONAL_CLINICAL',
        p_protected_resource_scope => 'ENCOUNTER_MEDICAL_INFORMATION',
        p_occurred_at => clock_timestamp(),
        p_care_authorization_id => encounter_record.care_authorization_id,
        p_accessing_clinic_id => encounter_record.clinic_id,
        p_accessing_organization_id => encounter_record.organization_id,
        p_appointment_id => encounter_record.appointment_id,
        p_organization_membership_id => actor.organization_membership_id,
        p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id,
        p_clinical_encounter_id => encounter_record.id
    );

    return jsonb_build_object(
        'status', 'PERMITTED',
        'appointment', jsonb_build_object(
            'appointment_id', appointment_record.id,
            'lifecycle_state', appointment_record.lifecycle_state
        ),
        'start', null,
        'encounter', jsonb_build_object(
            'encounter_id', encounter_record.id,
            'lifecycle_state', encounter_record.lifecycle_state,
            'started_at', encounter_record.started_at,
            'concluded_at', encounter_record.concluded_at,
            'is_mine_responsible',
                encounter_record.responsible_veterinarian_clinic_assignment_id
                    = actor.veterinarian_clinic_assignment_id,
            'may_create_draft',
                encounter_record.responsible_veterinarian_clinic_assignment_id
                    = actor.veterinarian_clinic_assignment_id,
            'may_edit', true,
            'may_finalize', true,
            'may_conclude',
                encounter_record.lifecycle_state = 'ACTIVE'
                and public.user_has_clinic_capability(acting_user_id, p_clinic_id, 'CLINICAL_CARE'),
            'entries', entries_payload,
            'entries_truncated', entry_count > 100
        )
    );
end;
$$;

revoke all privileges
on function public.view_appointment_clinical_record(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.view_appointment_clinical_record(uuid, uuid)
to authenticated;

-- ==================================================================
-- 6. Clinic Appointment Schedule: has_clinical_encounter (SPEC-APT-012 BR-48).
-- ==================================================================

drop function public.get_clinic_appointment_schedule(uuid);

create function public.get_clinic_appointment_schedule(
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

    return query
    -- The Clinic's current timezone, validated once and only when the Clinic
    -- has a PENDING proposal (NULL when absent or invalid).
    with pending_clinic_timezone as materialized (
        select case
                   when public.clinic_timezone_name_is_valid(clinic.scheduling_timezone_name)
                       then clinic.scheduling_timezone_name
               end as valid_timezone_name
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and exists (
              select 1
              from public.appointments as pending_appointment
              join public.appointment_reschedule_proposals as pending
                on pending.appointment_id = pending_appointment.id
               and pending.state = 'PENDING'
              where pending_appointment.clinic_id = p_clinic_id
          )
    )
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
    -- The derived value is computed only for the projected actionable PENDING
    -- proposal; an infeasible proposal is still projected.
    left join lateral (
        select open_proposal.id, open_proposal.state, open_proposal.proposing_context,
               open_proposal.proposed_start_at, open_proposal.proposed_end_at,
               open_proposal.proposed_timezone_name, open_proposal.reason,
               public.appointment_reschedule_proposal_is_currently_feasible(
                   open_proposal.id,
                   (select timezone_row.valid_timezone_name from pending_clinic_timezone as timezone_row)
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
    -- SPEC-APT-012 §4 (terminal outcome), SPEC-APT-003 BR-8/BR-9: only a
    -- CANCELLED Appointment carries a cancellation reason, from its single
    -- CANCELLED Lifecycle Event — the same source as get_pet_appointments.
    left join public.appointment_lifecycle_events as cancellation_event
      on cancellation_event.appointment_id = appointment.id
     and cancellation_event.to_state = 'CANCELLED'
     and appointment.lifecycle_state = 'CANCELLED'
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
-- 7. Generic clinical writers and the superseded work read leave the
--    client surface; service_role keeps them for trusted compatibility.
-- ==================================================================

revoke execute on function public.create_clinical_encounter(uuid, timestamptz, uuid)
from authenticated;
revoke execute on function public.create_draft_clinical_record_entry(uuid, text, text, text, timestamptz)
from authenticated;
revoke execute on function public.update_draft_clinical_record_entry(uuid, bigint, text, text, text, timestamptz)
from authenticated;
revoke execute on function public.finalize_clinical_record_entry(uuid, bigint)
from authenticated;
revoke execute on function public.conclude_clinical_encounter(uuid)
from authenticated;
revoke execute on function public.view_care_authorization_clinical_work_context(uuid, uuid, integer, timestamptz, uuid)
from authenticated;

commit;

-- Appointment-owned clinical documentation — Punto 8, stage M2
-- (ADR-011; SPEC-MED-010; SPEC-APT-007 §13; SPEC-ACC-003; SPEC-MED-004 §15;
-- SPEC-MED-005 §15; docs/CLINICAL_DOCUMENTATION_TRANSITION.md §5.2).
--
-- Clinical Encounter is removed from the model and the database. A Clinical
-- Record Entry belongs to exactly one Appointment, is recorded once as clinical
-- history (no Draft, no separate finalization), and only by the Appointment's
-- current eligible assigned Veterinarian. Documentation access no longer
-- depends on the Care Authorization; prior-history access no longer depends on
-- an Encounter and never applies to a COMPLETED Appointment.
--
--   0. Fail-closed guard: aborts unless every clinical table is empty and no
--      audit, Lifecycle Event, or Reschedule Proposal row still references the
--      retired model (the DEVELOPMENT cleanup of §3 ran before; LOCAL starts
--      empty). Real clinical documentation can never be discarded here.
--   1. Retired operations dropped by exact signature (no CASCADE): Start,
--      Conclude, Draft create/update, Finalize (client and trusted writers),
--      the generic Encounter-keyed reads, and their private helpers;
--      get_professional_pet_active_care_authorizations loses client EXECUTE.
--   2. Schema: appointment_lifecycle_events.clinical_encounter_id and
--      medical_access_audit_events.clinical_encounter_id dropped; audit
--      operation/scope sets gain VIEW_APPOINTMENT_CLINICAL_RECORD /
--      APPOINTMENT_CLINICAL_RECORD and lose ACCESS_FOR_POST_CARE_DOCUMENTATION /
--      ENCOUNTER_MEDICAL_INFORMATION; the void reason CLINICAL_ENCOUNTER_STARTED
--      becomes CLINICAL_DOCUMENTATION_STARTED; clinical_record_entries gains
--      appointment_id (NOT NULL, FK, immutable) and loses the Encounter, Draft,
--      and finalization columns; category, content, creation key and digest
--      become NOT NULL; clinical_record_entry_contributors and
--      clinical_encounters are dropped with their trigger functions.
--   3. Audit: establish_medical_access_audit_event without an Encounter
--      reference; typed coherence correlates Entries through their Appointment.
--   4. Appointment operations and reads derived from their deployed bodies:
--      the "Encounter exists" conditions read "a Clinical Record Entry exists",
--      completion/cancellation/no-show/expiry Events carry no Encounter column,
--      legacy Encounter branches of the Lifecycle coherence rules are removed,
--      and the schedule reads expose has_clinical_record instead of
--      has_clinical_encounter (dropped and recreated with their ACLs).
--   5. Clinical record: structural Entry integrity (documentable Appointment,
--      current eligible assignee, provenance, immutability) and author-only
--      Amendments and Attachments; the first Entry voids a pending Reschedule
--      Proposal; create_appointment_clinical_entry (BR-23),
--      view_appointment_clinical_record (BR-20/21),
--      create_appointment_clinical_amendment (BR-18), history projection and
--      reads (BR-14, BR-22), Attachment operations (BR-19).
--
-- No table outside the clinical model loses data. No DROP ... CASCADE is used.
begin;

-- ==================================================================
-- 0. Fail-closed guard.
-- ==================================================================

do $guard$
begin
    if exists (select 1 from public.clinical_encounters)
       or exists (select 1 from public.clinical_record_entries)
       or exists (select 1 from public.clinical_amendments)
       or exists (select 1 from public.clinical_attachments)
       or exists (select 1 from public.clinical_record_entry_contributors) then
        raise exception 'M2 refused: clinical documentation of the retired model exists (see CLINICAL_DOCUMENTATION_TRANSITION.md §3)'
            using errcode = '55000';
    end if;
    if exists (
        select 1 from public.medical_access_audit_events
        where clinical_encounter_id is not null or clinical_record_entry_id is not null
           or clinical_amendment_id is not null or clinical_attachment_id is not null
           or operation in ('ACCESS_FOR_CLINICAL_CARE', 'ACCESS_FOR_POST_CARE_DOCUMENTATION',
                            'VIEW_CLINICAL_RECORD_ENTRY', 'VIEW_CLINICAL_ATTACHMENT')
           or protected_resource_scope in ('ENCOUNTER_MEDICAL_INFORMATION', 'CLINICAL_RECORD_ENTRY',
                                           'CLINICAL_AMENDMENT', 'CLINICAL_ATTACHMENT')
    ) then
        raise exception 'M2 refused: clinical audit evidence of the retired model exists'
            using errcode = '55000';
    end if;
    if exists (select 1 from public.appointment_lifecycle_events where clinical_encounter_id is not null)
       or exists (select 1 from public.appointment_reschedule_proposals
                  where void_reason = 'CLINICAL_ENCOUNTER_STARTED') then
        raise exception 'M2 refused: Appointment history still references Clinical Encounters'
            using errcode = '55000';
    end if;
end
$guard$;

-- ==================================================================
-- 1. Retired operations (SPEC-MED-010 BR-25) and private helpers.
-- ==================================================================

drop function public.start_appointment_clinical_encounter(uuid, uuid, timestamptz);
drop function public.conclude_appointment_clinical_encounter(uuid, uuid);
drop function public.create_appointment_clinical_draft(uuid, uuid, uuid, text, text, text, timestamptz);
drop function public.update_appointment_clinical_draft(uuid, uuid, uuid, bigint, text, text, text, timestamptz);
drop function public.finalize_appointment_clinical_entry(uuid, uuid, uuid, bigint);
drop function public.create_clinical_encounter(uuid, timestamptz, uuid);
drop function public.conclude_clinical_encounter(uuid);
drop function public.create_draft_clinical_record_entry(uuid, text, text, text, timestamptz);
drop function public.update_draft_clinical_record_entry(uuid, bigint, text, text, text, timestamptz);
drop function public.finalize_clinical_record_entry(uuid, bigint);
drop function public.view_care_authorization_clinical_work_context(uuid, uuid, integer, timestamptz, uuid);
drop function public.slice12_view_care_authorization_clinical_work_context(uuid, uuid, integer, timestamptz, uuid);
drop function public.view_professional_pet_medical_history(uuid, uuid, uuid, uuid, integer, timestamptz, uuid);
drop function public.slice12_view_professional_pet_medical_history(uuid, uuid, uuid, uuid, integer, timestamptz, uuid);
drop function public.view_clinical_record_entry(uuid);
drop function public.slice12_view_clinical_record_entry(uuid);
drop function public.decorate_clinical_attachment_read(jsonb, text);
drop function public.appointment_clinical_record_accessible(uuid);
drop function public.appointment_clinical_care_window(uuid);
drop function public.assert_clinical_draft_fields(text, text, timestamptz);

revoke execute
on function public.get_professional_pet_active_care_authorizations(uuid, uuid)
from authenticated;

-- ==================================================================
-- 2. Schema.
-- ==================================================================

-- 2a. Appointment Lifecycle Events: no legacy Encounter reference.
drop trigger appointment_lifecycle_events_no_new_encounter_reference on public.appointment_lifecycle_events;
drop function public.enforce_appointment_lifecycle_event_no_new_encounter_reference();
alter table public.appointment_lifecycle_events
    drop constraint appointment_lifecycle_events_encounter_shape_check,
    drop constraint appointment_lifecycle_events_clinical_encounter_id_fkey,
    drop column clinical_encounter_id;

-- 2b. Medical Access Audit Events (SPEC-ACC-003 per SPEC-MED-010 BR-21).
alter table public.medical_access_audit_events
    drop constraint medical_access_audit_events_operation_check,
    drop constraint medical_access_audit_events_protected_resource_scope_check,
    drop constraint medical_access_audit_events_operation_scope_pinning_check,
    drop constraint medical_access_audit_events_clinical_encounter_id_fkey,
    drop column clinical_encounter_id;
alter table public.medical_access_audit_events
    add constraint medical_access_audit_events_operation_check
        check (operation in (
            'VIEW_PET_MEDICAL_HISTORY',
            'VIEW_CLINICAL_RECORD_ENTRY',
            'VIEW_CLINICAL_ATTACHMENT',
            'VIEW_APPOINTMENT_CLINICAL_RECORD',
            'ACCESS_FOR_APPOINTMENT_OPERATIONS',
            'ACCESS_FOR_CLINICAL_CARE'
        )),
    add constraint medical_access_audit_events_protected_resource_scope_check
        check (protected_resource_scope in (
            'LONGITUDINAL_MEDICAL_HISTORY',
            'CLINICAL_RECORD_ENTRY',
            'CLINICAL_AMENDMENT',
            'CLINICAL_ATTACHMENT',
            'APPOINTMENT_CLINICAL_RECORD'
        )),
    add constraint medical_access_audit_events_operation_scope_pinning_check
        check (
            (operation = 'VIEW_PET_MEDICAL_HISTORY' and protected_resource_scope = 'LONGITUDINAL_MEDICAL_HISTORY')
            or (operation = 'VIEW_CLINICAL_RECORD_ENTRY' and protected_resource_scope = 'CLINICAL_RECORD_ENTRY')
            or (operation = 'VIEW_CLINICAL_ATTACHMENT' and protected_resource_scope = 'CLINICAL_ATTACHMENT')
            or (operation = 'VIEW_APPOINTMENT_CLINICAL_RECORD' and protected_resource_scope = 'APPOINTMENT_CLINICAL_RECORD')
            or operation in ('ACCESS_FOR_APPOINTMENT_OPERATIONS', 'ACCESS_FOR_CLINICAL_CARE')
        );

-- 2c. Reschedule Proposal void reason (SPEC-MED-010 BR-8).
alter table public.appointment_reschedule_proposals
    drop constraint appointment_reschedule_proposals_void_reason_check;
alter table public.appointment_reschedule_proposals
    add constraint appointment_reschedule_proposals_void_reason_check
        check (void_reason is null or void_reason in (
            'BASE_REVISION_SUPERSEDED', 'APPOINTMENT_LIFECYCLE_CHANGED', 'CLINICAL_DOCUMENTATION_STARTED',
            'PROPOSED_TIME_PASSED', 'PROPOSING_AUTHORITY_LOST'
        ));

-- 2d. Clinical Record Entries belong to the Appointment (SPEC-MED-010 BR-1–BR-7).
drop trigger clinical_record_entries_integrity on public.clinical_record_entries;
drop trigger clinical_record_entries_attachment_finalization_guard on public.clinical_record_entries;
drop function public.enforce_clinical_attachment_parent_finalization();
drop index public.clinical_record_entries_encounter_work_idx;
drop index public.clinical_record_entries_finalized_history_idx;
alter table public.clinical_record_entries
    drop constraint clinical_record_entries_encounter_id_fkey,
    drop constraint clinical_record_entries_finalized_by_user_id_fkey,
    drop constraint clinical_record_entries_finalizer_vca_id_fkey,
    drop constraint clinical_record_entries_lifecycle_state_check,
    drop constraint clinical_record_entries_lifecycle_shape_check,
    drop constraint clinical_record_entries_revision_check,
    drop constraint clinical_record_entries_modification_order_check,
    drop constraint clinical_record_entries_finalization_order_check,
    drop constraint clinical_record_entries_finalized_at_finite_check,
    drop constraint clinical_record_entries_last_modified_at_finite_check,
    drop constraint clinical_record_entries_creation_record_check,
    drop column clinical_encounter_id,
    drop column lifecycle_state,
    drop column draft_revision,
    drop column last_modified_at,
    drop column finalized_at,
    drop column finalized_by_user_id,
    drop column finalizer_veterinarian_clinic_assignment_id;
alter table public.clinical_record_entries
    add column appointment_id uuid not null,
    alter column category set not null,
    alter column clinical_content set not null,
    alter column creation_idempotency_key set not null,
    alter column creation_request_digest set not null,
    add constraint clinical_record_entries_appointment_id_fkey
        foreign key (appointment_id) references public.appointments (id)
        on update no action on delete restrict,
    add constraint clinical_record_entries_creation_digest_check
        check (octet_length(creation_request_digest) = 32);
create index clinical_record_entries_appointment_idx
on public.clinical_record_entries (appointment_id, created_at, id);

-- 2e. Contributor attribution only existed for Draft edits.
drop table public.clinical_record_entry_contributors;
drop function public.enforce_clinical_record_entry_contributor_integrity();

-- 2f. Clinical Encounter (ADR-011 §1).
drop table public.clinical_encounters;
drop function public.enforce_clinical_encounter_appointment_coherence();
drop function public.enforce_clinical_encounter_establishment();
drop function public.enforce_clinical_encounter_immutability();
drop function public.assert_clinical_encounter_appointment_coherence(uuid);
drop function public.assert_clinical_encounter_establishment(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz);

-- ==================================================================
-- 3. Medical Access Audit (SPEC-ACC-003, SPEC-MED-010 BR-21).
-- ==================================================================

drop function public.establish_medical_access_audit_event(
    uuid, uuid, text, text, text, text, timestamptz, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid);

create function public.establish_medical_access_audit_event(
    p_acting_user_id uuid,
    p_pet_id uuid,
    p_operation text,
    p_outcome text,
    p_actor_context text,
    p_protected_resource_scope text,
    p_occurred_at timestamptz,
    p_guardianship_id uuid default null,
    p_care_authorization_id uuid default null,
    p_accessing_clinic_id uuid default null,
    p_accessing_organization_id uuid default null,
    p_appointment_id uuid default null,
    p_organization_membership_id uuid default null,
    p_organization_responsibility_grant_id uuid default null,
    p_veterinarian_clinic_assignment_id uuid default null,
    p_clinical_record_entry_id uuid default null,
    p_clinical_amendment_id uuid default null,
    p_clinical_attachment_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_event_id uuid;
begin
    insert into public.medical_access_audit_events (
        occurred_at, operation, outcome, actor_context, protected_resource_scope,
        acting_user_id, pet_id, guardianship_id, care_authorization_id,
        accessing_clinic_id, accessing_organization_id, appointment_id,
        organization_membership_id, organization_responsibility_grant_id,
        veterinarian_clinic_assignment_id,
        clinical_record_entry_id, clinical_amendment_id, clinical_attachment_id
    ) values (
        p_occurred_at, p_operation, p_outcome, p_actor_context, p_protected_resource_scope,
        p_acting_user_id, p_pet_id, p_guardianship_id, p_care_authorization_id,
        p_accessing_clinic_id, p_accessing_organization_id, p_appointment_id,
        p_organization_membership_id, p_organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id,
        p_clinical_record_entry_id, p_clinical_amendment_id, p_clinical_attachment_id
    ) returning id into new_event_id;
    return new_event_id;
end;
$$;

revoke all privileges
on function public.establish_medical_access_audit_event(
    uuid, uuid, text, text, text, text, timestamptz, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
from public, anon, authenticated;

drop function public.assert_medical_access_audit_typed_resource_coherence(uuid, text, uuid, uuid, uuid, uuid, uuid, uuid);

create function public.assert_medical_access_audit_typed_resource_coherence(
    p_pet_id uuid,
    p_operation text,
    p_appointment_id uuid,
    p_clinical_record_entry_id uuid,
    p_clinical_amendment_id uuid,
    p_clinical_attachment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_pet_id uuid;
    entry_appointment_id uuid;
    entry_pet_id uuid;
    amendment_original_entry_id uuid;
    attachment_entry_id uuid;
begin
    if p_operation = 'VIEW_CLINICAL_RECORD_ENTRY' and p_clinical_record_entry_id is null then
        raise exception 'VIEW_CLINICAL_RECORD_ENTRY Audit Event requires a typed Entry reference'
            using errcode = '23514';
    end if;
    if p_operation = 'VIEW_CLINICAL_ATTACHMENT'
       and (p_clinical_attachment_id is null or p_clinical_record_entry_id is null) then
        raise exception 'VIEW_CLINICAL_ATTACHMENT Audit Event requires typed Attachment and Entry references'
            using errcode = '23514';
    end if;
    if p_clinical_attachment_id is not null and p_operation <> 'VIEW_CLINICAL_ATTACHMENT' then
        raise exception 'Only VIEW_CLINICAL_ATTACHMENT may carry an Attachment reference'
            using errcode = '23514';
    end if;
    if p_operation = 'VIEW_APPOINTMENT_CLINICAL_RECORD' and p_appointment_id is null then
        raise exception 'VIEW_APPOINTMENT_CLINICAL_RECORD Audit Event requires its Appointment'
            using errcode = '23514';
    end if;
    if p_appointment_id is not null then
        select appointment.pet_id into appointment_pet_id
        from public.appointments as appointment where appointment.id = p_appointment_id;
        if not found then raise exception 'Referenced Appointment does not exist' using errcode = '23503'; end if;
        if appointment_pet_id is distinct from p_pet_id then
            raise exception 'Audit Event Appointment must concern its Pet' using errcode = '23514';
        end if;
    end if;
    if p_clinical_record_entry_id is not null then
        select entry_row.appointment_id, appointment.pet_id
        into entry_appointment_id, entry_pet_id
        from public.clinical_record_entries as entry_row
        join public.appointments as appointment on appointment.id = entry_row.appointment_id
        where entry_row.id = p_clinical_record_entry_id;
        if not found then raise exception 'Referenced Clinical Record Entry does not exist' using errcode = '23503'; end if;
        if entry_pet_id is distinct from p_pet_id then
            raise exception 'Audit Event Entry must concern its Pet' using errcode = '23514';
        end if;
        if p_appointment_id is not null and entry_appointment_id is distinct from p_appointment_id then
            raise exception 'Audit Event Entry must belong to its supplied Appointment' using errcode = '23514';
        end if;
    end if;
    if p_clinical_amendment_id is not null then
        if p_clinical_record_entry_id is null then
            raise exception 'Typed Amendment audit provenance requires its original Entry' using errcode = '23514';
        end if;
        select amendment.original_clinical_record_entry_id into amendment_original_entry_id
        from public.clinical_amendments as amendment where amendment.id = p_clinical_amendment_id;
        if not found then raise exception 'Referenced Clinical Amendment does not exist' using errcode = '23503'; end if;
        if amendment_original_entry_id is distinct from p_clinical_record_entry_id then
            raise exception 'Audit Event Amendment must belong to its supplied original Entry' using errcode = '23514';
        end if;
    end if;
    if p_clinical_attachment_id is not null then
        select attachment.clinical_record_entry_id into attachment_entry_id
        from public.clinical_attachments as attachment where attachment.id = p_clinical_attachment_id;
        if not found then raise exception 'Referenced Clinical Attachment does not exist' using errcode = '23503'; end if;
        if attachment_entry_id is distinct from p_clinical_record_entry_id then
            raise exception 'Audit Event Attachment must belong to its supplied Entry' using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_medical_access_audit_typed_resource_coherence(uuid, text, uuid, uuid, uuid, uuid)
from public, anon, authenticated;

create or replace function public.enforce_medical_access_audit_typed_resource_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_medical_access_audit_typed_resource_coherence(
        new.pet_id, new.operation, new.appointment_id,
        new.clinical_record_entry_id, new.clinical_amendment_id, new.clinical_attachment_id
    );
    return new;
end;
$$;

-- ==================================================================
-- 4. Appointment operations and reads (bodies derived from the deployed
--    definitions; only the Clinical Encounter dependencies change).
-- ==================================================================

-- accept_appointment_reschedule_proposal: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.accept_appointment_reschedule_proposal(p_proposal_id uuid, p_accepting_context text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
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
       and proposal_record.void_reason = 'CLINICAL_DOCUMENTATION_STARTED' then
        raise exception 'Appointment with clinical documentation cannot be rescheduled'
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
$function$;


-- cancel_appointment: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.cancel_appointment(p_appointment_id uuid, p_cancelling_context text, p_reason text DEFAULT NULL::text, p_expected_schedule_revision_sequence integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_pet_id uuid;
    normalized_reason text;
    appointment_record public.appointments%rowtype;
    current_revision public.appointment_schedule_revisions%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_cancelling_context is null or p_cancelling_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Cancelling context must be GUARDIAN or CLINIC' using errcode = '22023';
    end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    -- SPEC-APT-003 BR-24/BR-25 step 2 and BR-29: structurally invalid input,
    -- rejected before any Appointment state is consulted.
    if p_cancelling_context = 'GUARDIAN' then
        if p_expected_schedule_revision_sequence is not null then
            raise exception 'Guardian cancellation does not accept an expected schedule revision sequence'
                using errcode = '22023';
        end if;
    else
        if p_expected_schedule_revision_sequence is null
           or p_expected_schedule_revision_sequence <= 0 then
            raise exception 'Expected schedule revision sequence must be a positive integer'
                using errcode = '22023';
        end if;
        if normalized_reason is null then
            raise exception 'A meaningful reason is required for a Clinic cancellation' using errcode = '22023';
        end if;
    end if;

    select appointment.pet_id, appointment.clinic_id into appointment_pet_id, appointment_clinic_id
    from public.appointments as appointment where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    if p_cancelling_context = 'GUARDIAN' then
        if not exists (
            select 1 from public.guardianships as guardianship
            where guardianship.pet_id = appointment_pet_id and guardianship.user_id = acting_user_id
              and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
        ) then raise exception 'Current Guardianship of the Appointment Pet is required' using errcode = '42501'; end if;
    else
        perform public.assert_clinic_capability_after_lock(
            acting_user_id, appointment_clinic_id, 'APPOINTMENT_CANCEL'
        );
    end if;
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;
    if appointment_record.lifecycle_state not in ('REQUESTED', 'CONFIRMED') then
        raise exception 'Only a REQUESTED or CONFIRMED Appointment may be cancelled' using errcode = '23514';
    end if;

    -- SPEC-APT-003 BR-25 steps 5–7 / BR-26 / BR-27: the revision sequence of
    -- the current scheduling context for the locked lifecycle state alone
    -- decides staleness, never the scheduled values. Deterministic
    -- client-input mismatch: plain P0001.
    if p_cancelling_context = 'CLINIC' then
        select revision.* into current_revision
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = p_appointment_id
          and revision.revision_context = appointment_record.lifecycle_state
        order by revision.revision_sequence desc limit 1;
        if not found then
            raise exception 'Appointment % has no current scheduling context', p_appointment_id
                using errcode = '23514';
        end if;
        if current_revision.revision_sequence <> p_expected_schedule_revision_sequence then
            raise exception 'Stale Appointment schedule revision for cancellation';
        end if;
    end if;

    -- SPEC-APT-003 BR-23 / SPEC-APT-015 BR-18: a logically expired request
    -- is never cancelled, whether or not EXPIRED has been materialized.
    if appointment_record.lifecycle_state = 'REQUESTED'
       and not public.appointment_is_pending_request(p_appointment_id, clock_timestamp()) then
        raise exception 'A REQUESTED Appointment whose requested time has passed cannot be cancelled' using errcode = '23514';
    end if;
    -- SPEC-APT-003 BR-31: Guardian cancellation of a CONFIRMED Appointment
    -- closes at its latest confirmed start, read here under the Appointment
    -- lock and compared with backend time. Clinic cancellation is unaffected.
    if p_cancelling_context = 'GUARDIAN'
       and appointment_record.lifecycle_state = 'CONFIRMED'
       and not public.appointment_confirmed_start_is_in_future(p_appointment_id, clock_timestamp()) then
        raise exception 'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached'
            using errcode = '23514';
    end if;
    if exists (select 1 from public.clinical_record_entries as clinical_record
               where clinical_record.appointment_id = p_appointment_id) then
        raise exception 'Appointment with clinical documentation cannot be cancelled' using errcode = '23514';
    end if;
    if p_cancelling_context = 'GUARDIAN' then
        perform 1 from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
        for update;
        if not found then raise exception 'Current Guardianship of the Appointment Pet is required' using errcode = '42501'; end if;
    end if;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id for update;
    if not found then raise exception 'Appointment has no Appointment-derived Care Authorization' using errcode = '23514'; end if;
    operation_timestamp := clock_timestamp();
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at
    ) values (
        p_appointment_id, appointment_record.lifecycle_state, 'CANCELLED',
        acting_user_id, p_cancelling_context, normalized_reason,
        operation_timestamp, operation_timestamp
    );
    update public.appointments set lifecycle_state = 'CANCELLED' where id = p_appointment_id;
    if care_auth_record.lifecycle_state = 'ACTIVE' then
        update public.care_authorizations
        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_CANCELLED'
        where id = care_auth_record.id;
    end if;
    return p_appointment_id;
end;
$function$;


-- mark_appointment_no_show: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.mark_appointment_no_show(p_appointment_id uuid, p_expected_confirmed_revision_sequence integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
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

    -- BR-41: structurally invalid input, rejected before any Appointment
    -- state is consulted. Distinct from a stale (well-formed but superseded)
    -- expected sequence.
    if p_expected_confirmed_revision_sequence is null
       or p_expected_confirmed_revision_sequence <= 0 then
        raise exception 'Expected confirmed revision sequence must be a positive integer'
            using errcode = '22023';
    end if;

    select appointment.clinic_id into appointment_clinic_id from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, appointment_clinic_id, 'APPOINTMENT_MARK_NO_SHOW'
    );
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;

    -- Lifecycle precedes staleness: an Appointment that is no longer
    -- CONFIRMED is an invalid transition, never a stale request.
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may be marked no-show' using errcode = '23514';
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

    -- BR-42/BR-43: the revision sequence alone decides staleness, never the
    -- scheduled values. Deterministic client-input mismatch: plain P0001.
    if latest_confirmed_revision.revision_sequence <> p_expected_confirmed_revision_sequence then
        raise exception 'Stale confirmed Appointment schedule revision';
    end if;

    if exists (select 1 from public.clinical_record_entries as clinical_record
               where clinical_record.appointment_id = p_appointment_id) then
        raise exception 'Appointment with clinical documentation cannot be marked no-show' using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();
    -- BR-44: permitted once the reviewed (and current) confirmed start has
    -- been reached; the scheduled end is not required.
    if latest_confirmed_revision.scheduled_start_at > operation_timestamp then
        raise exception 'Appointment cannot be marked no-show before its confirmed scheduled start' using errcode = '23514';
    end if;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id for update;
    if not found then raise exception 'Appointment has no Care Authorization' using errcode = '23514'; end if;
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at
    ) values (
        p_appointment_id, 'CONFIRMED', 'NO_SHOW', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp
    );
    update public.appointments set lifecycle_state = 'NO_SHOW' where id = p_appointment_id;
    if care_auth_record.lifecycle_state = 'ACTIVE' then
        update public.care_authorizations
        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_NO_SHOW'
        where id = care_auth_record.id;
    end if;
    return p_appointment_id;
end;
$function$;


-- complete_appointment: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.complete_appointment(p_appointment_id uuid, p_expected_confirmed_revision_sequence integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    latest_confirmed_revision public.appointment_schedule_revisions%rowtype;
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

    -- BR-12/BR-15: no clinical record, Veterinarian Assignment, or Care
    -- Authorization is read or written.
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at
    ) values (
        p_appointment_id, 'CONFIRMED', 'COMPLETED', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp
    );
    update public.appointments set lifecycle_state = 'COMPLETED' where id = p_appointment_id;
    return p_appointment_id;
end;
$function$;


-- expire_lapsed_appointment_requests: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.expire_lapsed_appointment_requests(p_reference_time timestamp with time zone DEFAULT clock_timestamp())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    candidate record;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    logical_expiry_at timestamptz;
    expired_count integer := 0;
begin
    if p_reference_time is null or not isfinite(p_reference_time) then
        raise exception 'Expiry reference time must be finite'
            using errcode = '22023';
    end if;

    if p_reference_time > clock_timestamp() then
        raise exception 'Expiry reference time must not be in the future'
            using errcode = '22023';
    end if;

    for candidate in
        select appointment.id as appointment_id,
               appointment.clinic_id,
               clinic.organization_id
        from public.appointments as appointment
        join public.clinics as clinic
          on clinic.id = appointment.clinic_id
        where appointment.lifecycle_state = 'REQUESTED'
          and public.appointment_latest_requested_start_at(appointment.id) <= p_reference_time
        order by clinic.organization_id, appointment.clinic_id, appointment.id
    loop
        perform 1
        from public.veterinary_organizations as organization
        where organization.id = candidate.organization_id
        for update;

        perform 1
        from public.clinics as clinic
        where clinic.id = candidate.clinic_id
        for update;

        select appointment.*
        into appointment_record
        from public.appointments as appointment
        where appointment.id = candidate.appointment_id
        for update;

        if appointment_record.lifecycle_state <> 'REQUESTED' then
            continue;
        end if;

        logical_expiry_at := public.appointment_latest_requested_start_at(candidate.appointment_id);

        if logical_expiry_at is null or logical_expiry_at > p_reference_time then
            continue;
        end if;

        select care_auth.*
        into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = candidate.appointment_id
        for update;

        if not found then
            raise exception 'Appointment % has no Appointment-derived Care Authorization',
                candidate.appointment_id
                using errcode = '23514';
        end if;

        insert into public.appointment_lifecycle_events (
            appointment_id, from_state, to_state, actor_user_id, actor_context,
            reason, effective_at, recorded_at
        ) values (
            candidate.appointment_id, 'REQUESTED', 'EXPIRED', null, 'SYSTEM',
            null, logical_expiry_at, clock_timestamp()
        );

        update public.appointments
        set lifecycle_state = 'EXPIRED'
        where id = candidate.appointment_id;

        if care_auth_record.lifecycle_state = 'ACTIVE' then
            update public.care_authorizations
            set lifecycle_state = 'ENDED',
                ended_at = logical_expiry_at,
                ended_reason = 'APPOINTMENT_EXPIRED'
            where id = care_auth_record.id;
        end if;

        expired_count := expired_count + 1;
    end loop;

    return expired_count;
end;
$function$;


-- enforce_appointment_reschedule_proposal_base_revision: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.enforce_appointment_reschedule_proposal_base_revision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
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
        from public.clinical_record_entries as clinical_record
        where clinical_record.appointment_id = new.appointment_id
    ) then
        raise exception 'Appointment with clinical documentation cannot be rescheduled'
            using errcode = '23514';
    end if;

    return new;
end;
$function$;


-- propose_confirmed_appointment_reschedule: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.propose_confirmed_appointment_reschedule(p_appointment_id uuid, p_proposing_context text, p_start_local_date date, p_start_local_time time without time zone, p_start_utc_offset_seconds integer, p_reason text DEFAULT NULL::text, p_expected_confirmed_revision_sequence integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    resolved_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    base_revision public.appointment_schedule_revisions%rowtype;
    existing_proposal_record public.appointment_reschedule_proposals%rowtype;
    clinic_duration_minutes integer;
    resolved_start record;
    normalized_reason text;
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
        from public.clinical_record_entries as clinical_record
        where clinical_record.appointment_id = p_appointment_id
    ) then
        raise exception 'Appointment with clinical documentation cannot be rescheduled'
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

    -- BR-24: the current standard duration, required, no fallback; the base
    -- confirmed duration is not used.
    select clinic.standard_appointment_duration_minutes
    into clinic_duration_minutes
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;

    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
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

    -- BR-25: the same start instant is never a reschedule, whatever the
    -- duration.
    if resolved_start.resolved_start_at = base_revision.scheduled_start_at then
        raise exception 'Proposed time must differ from the current confirmed time'
            using errcode = '22023';
    end if;

    proposed_end_at := resolved_start.resolved_start_at
        + clinic_duration_minutes * interval '1 minute';

    -- BR-28.
    perform public.assert_appointment_reschedule_interval_feasible(
        p_appointment_id, appointment_record.clinic_id,
        resolved_start.resolved_start_at, proposed_end_at,
        resolved_start.timezone_name
    );

    -- The interval is frozen here (§6).
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
$function$;


-- get_appointment_reschedule_candidate_start_times: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.get_appointment_reschedule_candidate_start_times(p_appointment_id uuid, p_start_date date, p_end_date date)
 RETURNS TABLE(candidate_local_date date, candidate_local_time time without time zone, utc_offset_seconds integer, candidate_end_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    appointment_record public.appointments%rowtype;
    target_organization_id uuid;
    base_revision public.appointment_schedule_revisions%rowtype;
    clinic_timezone_name text;
    clinic_duration_minutes integer;
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

    select clinic.organization_id, clinic.scheduling_timezone_name,
           clinic.standard_appointment_duration_minutes
    into target_organization_id, clinic_timezone_name, clinic_duration_minutes
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
        from public.clinical_record_entries as clinical_record
        where clinical_record.appointment_id = p_appointment_id
    ) then
        raise exception 'Appointment with clinical documentation cannot be rescheduled'
            using errcode = '23514';
    end if;

    -- BR-5: the current standard duration is required, as for proposing.
    if clinic_duration_minutes is null then
        raise exception 'Clinic has no currently configured standard Appointment duration'
            using errcode = '23514';
    end if;

    if clinic_timezone_name is null
       or not public.clinic_timezone_name_is_valid(clinic_timezone_name) then
        raise exception 'Appointment scheduling requires a valid Clinic scheduling timezone'
            using errcode = '23514';
    end if;

    -- BR-5–BR-7: standard duration as length and cadence; the current
    -- confirmed start is excluded whatever its duration.
    return query
    select *
    from public.appointment_reschedule_candidate_positions(
        p_appointment_id, appointment_record.clinic_id, clinic_timezone_name,
        p_start_date, p_end_date,
        clinic_duration_minutes::bigint * 60000000,
        base_revision.scheduled_start_at, operation_timestamp
    );
end;
$function$;


-- enforce_appointment_reschedule_proposal_integrity: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.enforce_appointment_reschedule_proposal_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
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
        elsif new.void_reason = 'CLINICAL_DOCUMENTATION_STARTED' then
            if not exists (
                select 1
                from public.clinical_record_entries as clinical_record
                where clinical_record.appointment_id = old.appointment_id
            ) then
                raise exception 'No Clinical Record Entry exists for the Reschedule Proposal Appointment'
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
$function$;


-- enforce_reschedule_proposal_invalidation: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.enforce_reschedule_proposal_invalidation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
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
    elsif tg_table_name = 'clinical_record_entries' then
        perform public.void_open_reschedule_proposal(
            new.appointment_id, 'CLINICAL_DOCUMENTATION_STARTED'
        );
    end if;

    return null;
end;
$function$;


-- clinic_pending_appointments: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.clinic_pending_appointments(p_clinic_id uuid, p_acting_user_id uuid)
 RETURNS TABLE(appointment_id uuid, scheduled_start_at timestamp with time zone, pending_reason text, pending_category text, pending_rank integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
               documentation.has_clinical_record,
               -- REQUEST_DECISION's actor condition, stated once: on a
               -- REQUESTED Appointment this actor could confirm or propose an
               -- alternative (with the Entitlement) or cancel (without
               -- clinical documentation), were no actionable proposal open.
               appointment.lifecycle_state = 'REQUESTED'
               and ((context_row.has_appointment_management
                     and (actor.can_confirm or actor.can_reschedule))
                    or (actor.can_cancel and not documentation.has_clinical_record)) as can_decide_request
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
                from public.clinical_record_entries as clinical_record
                where clinical_record.appointment_id = appointment.id
            ) as has_clinical_record
        ) as documentation
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
                   -- resolve: Complete (no clinical documentation condition), No-show or
                   -- Clinic cancellation (only without clinical documentation).
                   when candidate.lifecycle_state = 'CONFIRMED'
                        and candidate.scheduled_start_at <= statement_timestamp()
                        and (actor.can_complete
                             or (not candidate.has_clinical_record
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
$function$;


-- assert_appointment_lifecycle_coherence: deployed body; legacy Encounter branches removed.
CREATE OR REPLACE FUNCTION public.assert_appointment_lifecycle_coherence(p_appointment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    appointment_record public.appointments%rowtype;
    requested_revision_count integer;
    confirmed_revision_count integer;
    confirmation_event_count integer;
    terminal_event_count integer;
    lifecycle_event_record public.appointment_lifecycle_events%rowtype;
    confirmation_effective_at timestamptz;
    latest_confirmed_scheduled_start_at timestamptz;
begin
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if not found then return; end if;

    select count(*) into requested_revision_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'REQUESTED'
      and revision.revision_sequence = 1;

    if requested_revision_count <> 1 then
        raise exception 'Appointment % requires exactly one initial REQUESTED Schedule Revision', p_appointment_id
            using errcode = '23514';
    end if;

    select count(*) into confirmation_event_count
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.from_state = 'REQUESTED'
      and lifecycle_event.to_state = 'CONFIRMED';

    select count(*) into terminal_event_count
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED');

    select count(*) into confirmed_revision_count
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED';

    if appointment_record.lifecycle_state = 'REQUESTED' then
        if confirmation_event_count <> 0 or terminal_event_count <> 0 then
            raise exception 'REQUESTED Appointment % must have zero Lifecycle Events', p_appointment_id
                using errcode = '23514';
        end if;
        return;
    end if;

    if appointment_record.lifecycle_state = 'CONFIRMED' then
        if confirmation_event_count <> 1 or terminal_event_count <> 0 or confirmed_revision_count < 1 then
            raise exception 'CONFIRMED Appointment % has incoherent confirmation history', p_appointment_id
                using errcode = '23514';
        end if;
        return;
    end if;

    if terminal_event_count <> 1 then
        raise exception 'Terminal Appointment % requires exactly one terminal Lifecycle Event', p_appointment_id
            using errcode = '23514';
    end if;

    select lifecycle_event.* into lifecycle_event_record
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED');

    if lifecycle_event_record.to_state <> appointment_record.lifecycle_state then
        raise exception 'Appointment % terminal Event must match its lifecycle state', p_appointment_id
            using errcode = '23514';
    end if;

    if lifecycle_event_record.from_state = 'REQUESTED' then
        if appointment_record.lifecycle_state not in ('CANCELLED', 'EXPIRED')
           or confirmation_event_count <> 0 then
            raise exception 'Only cancellation or expiry may terminate an unconfirmed Appointment %', p_appointment_id
                using errcode = '23514';
        end if;
        if appointment_record.lifecycle_state = 'EXPIRED' and confirmed_revision_count <> 0 then
            raise exception 'EXPIRED Appointment % must not have a CONFIRMED Schedule Revision', p_appointment_id
                using errcode = '23514';
        end if;
    else
        if confirmation_event_count <> 1 or confirmed_revision_count < 1 then
            raise exception 'Appointment % terminated from CONFIRMED requires confirmation history', p_appointment_id
                using errcode = '23514';
        end if;

        select lifecycle_event.effective_at into confirmation_effective_at
        from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = p_appointment_id
          and lifecycle_event.from_state = 'REQUESTED'
          and lifecycle_event.to_state = 'CONFIRMED';

        if lifecycle_event_record.effective_at < confirmation_effective_at then
            raise exception 'Appointment % terminal Event cannot precede confirmation', p_appointment_id
                using errcode = '23514';
        end if;
    end if;

    if appointment_record.lifecycle_state = 'COMPLETED' then
        -- Completion carries no clinical evidence (ADR-011).
        null;
    else
        if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED')
           and exists (
               select 1 from public.clinical_record_entries as clinical_record
               where clinical_record.appointment_id = p_appointment_id
           ) then
            raise exception 'CANCELLED, NO_SHOW, or EXPIRED Appointment % cannot coexist with clinical documentation', p_appointment_id
                using errcode = '23514';
        end if;

        if appointment_record.lifecycle_state = 'NO_SHOW' then
            select revision.scheduled_start_at
            into latest_confirmed_scheduled_start_at
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = p_appointment_id
              and revision.revision_context = 'CONFIRMED'
            order by revision.revision_sequence desc
            limit 1;

            if not found then
                raise exception 'NO_SHOW Appointment % requires its latest CONFIRMED Schedule Revision', p_appointment_id
                    using errcode = '23514';
            end if;

            if lifecycle_event_record.effective_at < latest_confirmed_scheduled_start_at then
                raise exception 'NO_SHOW Appointment % Event cannot precede its latest confirmed scheduled start', p_appointment_id
                    using errcode = '23514';
            end if;
        end if;
    end if;
end;
$function$;


-- assert_appointment_lifecycle_event_provenance: deployed body; legacy Encounter branches removed.
CREATE OR REPLACE FUNCTION public.assert_appointment_lifecycle_event_provenance(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    lifecycle_event_record public.appointment_lifecycle_events%rowtype;
    appointment_record public.appointments%rowtype;
    confirmed_revision_count integer;
    latest_confirmed_scheduled_start_at timestamptz;
begin
    select lifecycle_event.* into lifecycle_event_record
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.id = p_event_id;
    if not found then return; end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = lifecycle_event_record.appointment_id
    for update;

    if not found or appointment_record.lifecycle_state <> lifecycle_event_record.to_state then
        raise exception 'Appointment Lifecycle Event % requires a matching Appointment state', p_event_id
            using errcode = '23514';
    end if;

    if lifecycle_event_record.from_state = 'CONFIRMED'
       or lifecycle_event_record.to_state = 'CONFIRMED' then
        select count(*) into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED';
        if confirmed_revision_count < 1 then
            raise exception 'Lifecycle Event % requires a CONFIRMED Schedule Revision', p_event_id
                using errcode = '23514';
        end if;
    end if;

    if lifecycle_event_record.to_state = 'EXPIRED' then
        select count(*) into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED';
        if confirmed_revision_count <> 0 then
            raise exception 'Expiry Event % requires a never-confirmed Appointment', p_event_id
                using errcode = '23514';
        end if;
        if lifecycle_event_record.effective_at is distinct from
           public.appointment_latest_requested_start_at(appointment_record.id) then
            raise exception 'Expiry Event % must take effect at the latest requested scheduled start', p_event_id
                using errcode = '23514';
        end if;
    end if;

    if lifecycle_event_record.to_state = 'COMPLETED' then

        -- SPEC-APT-009 BR-7: completion is permitted from the latest
        -- confirmed start. Encounter-backed completion previously enforced an
        -- equivalent bound through the Encounter; this keeps the time rule
        -- structural for Encounter-less completion.
        select revision.scheduled_start_at
        into latest_confirmed_scheduled_start_at
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED'
        order by revision.revision_sequence desc
        limit 1;

        if not found then
            raise exception 'Completion Event % requires its latest CONFIRMED Schedule Revision', p_event_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < latest_confirmed_scheduled_start_at then
            raise exception 'Completion Event % cannot precede its latest confirmed scheduled start', p_event_id
                using errcode = '23514';
        end if;
    elsif lifecycle_event_record.to_state = 'NO_SHOW' then
        select revision.scheduled_start_at
        into latest_confirmed_scheduled_start_at
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment_record.id
          and revision.revision_context = 'CONFIRMED'
        order by revision.revision_sequence desc
        limit 1;

        if not found then
            raise exception 'NO_SHOW Event % requires its latest CONFIRMED Schedule Revision', p_event_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < latest_confirmed_scheduled_start_at then
            raise exception 'NO_SHOW Event % cannot precede its latest confirmed scheduled start', p_event_id
                using errcode = '23514';
        end if;
    end if;
end;
$function$;


-- project_clinic_appointments: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
drop function public.project_clinic_appointments(uuid, uuid[]);

CREATE OR REPLACE FUNCTION public.project_clinic_appointments(p_clinic_id uuid, p_appointment_ids uuid[])
 RETURNS TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, reason_for_visit text, guardian_notes text, lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, current_schedule_revision_sequence integer, current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
        -- SPEC-APT-012 BR-48 / SPEC-MED-010 BR-9: a Clinical Record Entry exists.
        exists (
            select 1
            from public.clinical_record_entries as clinical_record
            where clinical_record.appointment_id = appointment.id
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
$function$;
revoke all privileges
on function public.project_clinic_appointments(uuid, uuid[])
from public, anon, authenticated, service_role;
grant execute
on function public.project_clinic_appointments(uuid, uuid[])
to service_role;


-- get_clinic_appointment_schedule: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
drop function public.get_clinic_appointment_schedule(uuid);

CREATE OR REPLACE FUNCTION public.get_clinic_appointment_schedule(p_clinic_id uuid)
 RETURNS TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, reason_for_visit text, guardian_notes text, lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, current_schedule_revision_sequence integer, current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
        -- SPEC-APT-012 BR-48: a Clinical Record Entry exists (SPEC-MED-010 BR-9).
        exists (
            select 1
            from public.clinical_record_entries as clinical_record
            where clinical_record.appointment_id = appointment.id
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
$function$;
revoke all privileges
on function public.get_clinic_appointment_schedule(uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.get_clinic_appointment_schedule(uuid)
to service_role;
grant execute
on function public.get_clinic_appointment_schedule(uuid)
to authenticated;


-- get_clinic_appointment: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
drop function public.get_clinic_appointment(uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_clinic_appointment(p_clinic_id uuid, p_appointment_id uuid)
 RETURNS TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, reason_for_visit text, guardian_notes text, lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, current_schedule_revision_sequence integer, current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
$function$;
revoke all privileges
on function public.get_clinic_appointment(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.get_clinic_appointment(uuid, uuid)
to service_role;
grant execute
on function public.get_clinic_appointment(uuid, uuid)
to authenticated;


-- get_clinic_appointment_day: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
drop function public.get_clinic_appointment_day(uuid, date);

CREATE OR REPLACE FUNCTION public.get_clinic_appointment_day(p_clinic_id uuid, p_day date)
 RETURNS TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, reason_for_visit text, guardian_notes text, lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, current_schedule_revision_sequence integer, current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
$function$;
revoke all privileges
on function public.get_clinic_appointment_day(uuid, date)
from public, anon, authenticated, service_role;
grant execute
on function public.get_clinic_appointment_day(uuid, date)
to service_role;
grant execute
on function public.get_clinic_appointment_day(uuid, date)
to authenticated;


-- get_clinic_appointment_history: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
drop function public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer);

CREATE OR REPLACE FUNCTION public.get_clinic_appointment_history(p_clinic_id uuid, p_before_start_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30)
 RETURNS TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, reason_for_visit text, guardian_notes text, lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, current_schedule_revision_sequence integer, current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
$function$;
revoke all privileges
on function public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)
to service_role;
grant execute
on function public.get_clinic_appointment_history(uuid, timestamptz, uuid, integer)
to authenticated;


-- get_clinic_appointment_pending: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
drop function public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer);

CREATE OR REPLACE FUNCTION public.get_clinic_appointment_pending(p_clinic_id uuid, p_after_rank integer DEFAULT NULL::integer, p_after_start_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_after_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, pet_id uuid, pet_name text, requesting_user_id uuid, requester_display_name text, reason_for_visit text, guardian_notes text, lifecycle_state text, created_at timestamp with time zone, current_scheduled_start_at timestamp with time zone, current_scheduled_end_at timestamp with time zone, current_scheduling_timezone_name text, current_schedule_revision_sequence integer, current_veterinarian_clinic_assignment_id uuid, pending_reschedule_proposal_id uuid, pending_reschedule_proposal_state text, pending_reschedule_proposing_context text, pending_reschedule_proposed_start_at timestamp with time zone, pending_reschedule_proposed_end_at timestamp with time zone, pending_reschedule_proposed_timezone_name text, pending_reschedule_reason text, current_schedule_source_proposal_id uuid, current_schedule_source_proposing_context text, pending_reschedule_currently_feasible boolean, cancellation_reason text, has_clinical_record boolean, pending_reason text, pending_category text, pending_rank integer, action_required_count integer, awaiting_guardian_count integer, informational_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
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
$function$;
revoke all privileges
on function public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)
to service_role;
grant execute
on function public.get_clinic_appointment_pending(uuid, integer, timestamptz, uuid, integer)
to authenticated;


-- ==================================================================
-- 5. Clinical record.
-- ==================================================================

-- 5a. Shared private helpers.

-- SPEC-MED-010 BR-3: the documentable Appointment is exactly the one that
-- accepts a Veterinarian assignment (SPEC-APT-007 BR-30): one
-- REQUESTED -> CONFIRMED Event and currently CONFIRMED or COMPLETED.
create function public.appointment_accepts_clinical_documentation(
    p_appointment_id uuid,
    p_lifecycle_state text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select public.appointment_accepts_veterinarian_assignment(p_appointment_id, p_lifecycle_state)
$$;

revoke all privileges
on function public.appointment_accepts_clinical_documentation(uuid, text)
from public, anon, authenticated, service_role;

-- SPEC-MED-010 BR-5. p_clinical_content and p_other_category_context are
-- already normalized (trimmed, blank -> NULL).
create function public.assert_clinical_entry_fields(
    p_category text,
    p_clinical_content text,
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
    if p_category is null then
        raise exception 'A category is required' using errcode = '22023', hint = 'CATEGORY_REQUIRED';
    end if;
    if p_category not in (
        'EXAMINATION', 'DIAGNOSIS', 'TREATMENT', 'PROCEDURE', 'VACCINATION',
        'PRESCRIPTION', 'LABORATORY_RESULT', 'IMAGING_RESULT', 'CLINICAL_NOTE', 'OTHER'
    ) then
        raise exception 'Unsupported clinical event category' using errcode = '22023', hint = 'INVALID_CATEGORY';
    end if;
    if p_clinical_content is null then
        raise exception 'Clinical content is required' using errcode = '22023', hint = 'CONTENT_REQUIRED';
    end if;
    if p_category = 'OTHER' and p_other_category_context is null then
        raise exception 'The OTHER category requires its context'
            using errcode = '22023', hint = 'OTHER_CONTEXT_REQUIRED';
    end if;
    if p_other_category_context is not null and p_category <> 'OTHER' then
        raise exception 'OTHER context is accepted only with the OTHER category'
            using errcode = '22023', hint = 'OTHER_CONTEXT_NOT_ALLOWED';
    end if;
    if p_clinical_event_at is not null and not isfinite(p_clinical_event_at) then
        raise exception 'Clinical event time must be finite' using errcode = '22023', hint = 'INVALID_EVENT_TIME';
    end if;
    if p_clinical_event_at > statement_timestamp() then
        raise exception 'Clinical event time cannot be in the future'
            using errcode = '22023', hint = 'EVENT_TIME_IN_FUTURE';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinical_entry_fields(text, text, text, timestamptz)
from public, anon, authenticated, service_role;

-- SPEC-MED-010 BR-14: prior-history access through an Appointment. An ACTIVE
-- Appointment-derived Care Authorization and a CONFIRMED Appointment, or a
-- REQUESTED one whose latest requested start is still in the future. No
-- Clinical Record Entry or assignment condition; COMPLETED never qualifies.
create or replace function public.appointment_professional_history_accessible(
    p_appointment_id uuid,
    p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((
        select care_auth.lifecycle_state = 'ACTIVE'
               and public.appointment_permits_pre_care_access(appointment.id, p_reference_time)
        from public.appointments as appointment
        join public.care_authorizations as care_auth
          on care_auth.appointment_id = appointment.id
         and care_auth.purpose = 'APPOINTMENT_CARE'
         and care_auth.pet_id = appointment.pet_id
         and care_auth.clinic_id = appointment.clinic_id
        where appointment.id = p_appointment_id
    ), false)
$$;

-- 5b. Structural Entry integrity (SPEC-MED-010 BR-1–BR-6, invariants §6).
create or replace function public.enforce_clinical_record_entry_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    clinic_organization_id uuid;
    assigned_clinic_assignment_id uuid;
begin
    if tg_op = 'DELETE' then
        raise exception 'Clinical Record Entries cannot be deleted' using errcode = '23514';
    end if;
    if tg_op = 'UPDATE' then
        raise exception 'A recorded Clinical Record Entry is immutable' using errcode = '23514';
    end if;

    if new.created_at > clock_timestamp() or new.clinical_event_at > clock_timestamp() then
        raise exception 'Clinical Record Entry cannot be recorded with a future timestamp'
            using errcode = '22023';
    end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = new.appointment_id;
    if not found then
        raise exception 'Clinical Record Entry requires its Appointment' using errcode = '23503';
    end if;
    if not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state) then
        raise exception 'A Clinical Record Entry requires a legitimately confirmed CONFIRMED or COMPLETED Appointment'
            using errcode = '23514';
    end if;

    select clinic.organization_id into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;
    perform public.assert_vca_user_provider_context(
        new.creator_veterinarian_clinic_assignment_id, new.created_by_user_id,
        appointment_record.clinic_id, clinic_organization_id
    );

    select assignment.veterinarian_clinic_assignment_id into assigned_clinic_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = new.appointment_id
      and assignment.effective_end is null;
    if assigned_clinic_assignment_id is distinct from new.creator_veterinarian_clinic_assignment_id
       or not public.appointment_veterinarian_is_eligible(
           new.creator_veterinarian_clinic_assignment_id, appointment_record.clinic_id) then
        raise exception 'A Clinical Record Entry must be recorded by the Appointment''s current eligible assigned Veterinarian'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinical_record_entry_integrity()
from public, anon, authenticated;

create trigger clinical_record_entries_integrity
before insert or update or delete on public.clinical_record_entries
for each row
execute function public.enforce_clinical_record_entry_integrity();

-- The first Entry makes a pending Reschedule Proposal VOID (BR-8).
create trigger clinical_record_entries_invalidate_reschedule_proposal
after insert on public.clinical_record_entries
for each row
execute function public.enforce_reschedule_proposal_invalidation();

-- 5c. Author-only, append-only Amendments (SPEC-MED-010 BR-18).
create or replace function public.enforce_clinical_amendment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    record_entry public.clinical_record_entries%rowtype;
    entry_clinic_id uuid;
    entry_organization_id uuid;
begin
    if tg_op in ('UPDATE', 'DELETE') then
        raise exception 'Clinical Amendments are append-only' using errcode = '23514';
    end if;

    select entry_row.* into record_entry
    from public.clinical_record_entries as entry_row
    where entry_row.id = new.original_clinical_record_entry_id
    for share;
    if not found then
        raise exception 'Clinical Amendment requires its original Clinical Record Entry' using errcode = '23503';
    end if;

    if new.amending_user_id is distinct from record_entry.created_by_user_id then
        raise exception 'Only the original author may amend a Clinical Record Entry' using errcode = '23514';
    end if;

    if new.created_at < record_entry.created_at or new.created_at > clock_timestamp() then
        raise exception 'Clinical Amendment time must follow the Entry and not be in the future'
            using errcode = '23514';
    end if;

    select appointment.clinic_id, clinic.organization_id
    into entry_clinic_id, entry_organization_id
    from public.appointments as appointment
    join public.clinics as clinic on clinic.id = appointment.clinic_id
    where appointment.id = record_entry.appointment_id;
    perform public.assert_vca_user_provider_context(
        new.amending_veterinarian_clinic_assignment_id, new.amending_user_id,
        entry_clinic_id, entry_organization_id
    );

    return new;
end;
$$;

-- enforce_clinical_attachment_integrity: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.enforce_clinical_attachment_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    parent_entry public.clinical_record_entries%rowtype;
    parent_clinic_id uuid;
    parent_organization_id uuid;
    provenance_user_id uuid;
begin
    select entry_row.* into parent_entry
    from public.clinical_record_entries as entry_row
    where entry_row.id = new.clinical_record_entry_id
    for share;
    if not found then
        raise exception 'Clinical Record Entry does not exist' using errcode = '23503';
    end if;

    select membership.user_id into provenance_user_id
    from public.veterinarian_clinic_assignments as assignment
    join public.organization_memberships as membership
      on membership.id = assignment.supporting_membership_id
    where assignment.id = new.uploader_vca_id;
    if provenance_user_id is distinct from new.uploaded_by_user_id then
        raise exception 'Attachment uploader VCA supporting Membership must belong to uploader User'
            using errcode = '23514';
    end if;
    select appointment.clinic_id, clinic.organization_id into parent_clinic_id, parent_organization_id
    from public.appointments as appointment
    join public.clinics as clinic on clinic.id = appointment.clinic_id
    where appointment.id = parent_entry.appointment_id;
    perform public.assert_vca_user_provider_context(
        new.uploader_vca_id, new.uploaded_by_user_id,
        parent_clinic_id, parent_organization_id
    );
    if new.removed_at is not null then
        perform public.assert_vca_user_provider_context(
            new.removed_by_vca_id, new.removed_by_user_id,
            parent_clinic_id, parent_organization_id
        );
    end if;

    if tg_op = 'INSERT' then
        if new.uploaded_by_user_id is distinct from parent_entry.created_by_user_id
           or new.validation_state <> 'PENDING'
           or new.object_state <> 'AWAITING_UPLOAD'
           or new.removed_at is not null then
            raise exception 'A new Attachment must begin PENDING/AWAITING_UPLOAD and be added by the Entry author'
                using errcode = '23514';
        end if;
    else
        if new.clinical_record_entry_id is distinct from old.clinical_record_entry_id
           or new.uploaded_by_user_id is distinct from old.uploaded_by_user_id
           or new.uploader_vca_id is distinct from old.uploader_vca_id
           or new.created_at is distinct from old.created_at
           or new.upload_idempotency_key is distinct from old.upload_idempotency_key
           or new.storage_object_id is distinct from old.storage_object_id
           or new.original_filename is distinct from old.original_filename then
            raise exception 'Attachment identity, parent, uploader, object, and filename facts are immutable'
                using errcode = '23514';
        end if;
        if old.validation_state in ('AVAILABLE', 'REJECTED')
           and new.validation_state is distinct from old.validation_state then
            raise exception 'Terminal Attachment validation state is immutable' using errcode = '23514';
        end if;
        if old.validation_state in ('AVAILABLE', 'REJECTED') and (
            new.trusted_media_type, new.trusted_byte_size, new.integrity_algorithm,
            new.integrity_value, new.validation_policy_version,
            new.validation_completed_at, new.rejection_code
        ) is distinct from (
            old.trusted_media_type, old.trusted_byte_size, old.integrity_algorithm,
            old.integrity_value, old.validation_policy_version,
            old.validation_completed_at, old.rejection_code
        ) then
            raise exception 'Terminal Attachment validation facts are immutable' using errcode = '23514';
        end if;
        if new.upload_stale_after is distinct from old.upload_stale_after
           and not (
               old.validation_state = 'PENDING' and old.object_state = 'AWAITING_UPLOAD'
               and old.removed_at is null and new.upload_stale_after > old.upload_stale_after
               and new.upload_stale_after <= clock_timestamp() + interval '3 hours'
           ) then
            raise exception 'Attachment upload stale horizon may advance only for an eligible token reissue'
                using errcode = '23514';
        end if;
        if old.removed_at is not null
           and (new.removed_at, new.removed_by_user_id, new.removed_by_vca_id)
               is distinct from (old.removed_at, old.removed_by_user_id, old.removed_by_vca_id) then
            raise exception 'Attachment removal is terminal and its provenance is immutable'
                using errcode = '23514';
        end if;
        if old.object_state = 'DELETED' and new.object_state <> 'DELETED' then
            raise exception 'A deleted Attachment object cannot be resurrected' using errcode = '23514';
        end if;
        if old.object_state = 'DELETE_PENDING' and new.object_state not in ('DELETE_PENDING', 'DELETED') then
            raise exception 'Attachment object cleanup cannot move backwards' using errcode = '23514';
        end if;
        if old.object_state = 'STORED' and new.object_state not in ('STORED', 'DELETE_PENDING', 'DELETED') then
            raise exception 'A stored Attachment object cannot move back to awaiting upload'
                using errcode = '23514';
        end if;
        if old.removed_at is null
           and old.validation_state = 'AVAILABLE'
           and new is distinct from old then
            raise exception 'A current AVAILABLE Attachment is immutable and cannot be removed'
                using errcode = '23514';
        end if;
    end if;
    return new;
end;
$function$;


-- initiate_clinical_attachment_upload: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.initiate_clinical_attachment_upload(p_auth_subject uuid, p_entry_id uuid, p_uploader_vca_id uuid, p_upload_idempotency_key uuid, p_original_filename text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    entry_clinic_id uuid;
    professional_context record;
    existing_attachment public.clinical_attachments%rowtype;
    created_attachment public.clinical_attachments%rowtype;
    current_count integer;
    operation_timestamp timestamptz := clock_timestamp();
begin
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth'
      and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_upload_idempotency_key is null or p_uploader_vca_id is null then
        raise exception 'Uploader VCA and upload idempotency key are required' using errcode = '22023';
    end if;
    if p_original_filename is not null and (
        p_original_filename = '' or p_original_filename <> btrim(p_original_filename, E' \t\n\r\f\013')
        or char_length(p_original_filename) > 255 or p_original_filename ~ '[[:cntrl:]/\\]'
    ) then raise exception 'Original filename is not normalized' using errcode = '22023'; end if;

    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = p_entry_id;
    if not found then raise exception 'Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select appointment.clinic_id into entry_clinic_id from public.appointments as appointment
    where appointment.id = record_entry.appointment_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, entry_clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    if professional_context.veterinarian_clinic_assignment_id is distinct from p_uploader_vca_id then
        raise exception 'Uploader VCA must be the current exact professional context' using errcode = '42501';
    end if;
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = p_entry_id for share;
    -- SPEC-MED-010 BR-19: only the Entry's author adds Attachments, and every
    -- new Attachment requires the CLINICAL_CARE Entitlement (BR-13).
    if record_entry.created_by_user_id is distinct from acting_user_id then
        raise exception 'Only the Entry author may add Attachments' using errcode = '42501';
    end if;
    if not public.organization_has_professional_entitlement(professional_context.organization_id, 'CLINICAL_CARE') then
        raise exception 'Clinical care is currently unavailable for this Organization'
            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';
    end if;

    select attachment.* into existing_attachment
    from public.clinical_attachments as attachment
    where attachment.uploaded_by_user_id = acting_user_id
      and attachment.upload_idempotency_key = p_upload_idempotency_key
    for update;
    if found then
        if existing_attachment.clinical_record_entry_id is distinct from p_entry_id
           or existing_attachment.original_filename is distinct from p_original_filename
           or existing_attachment.uploader_vca_id is distinct from p_uploader_vca_id then
            raise exception 'Upload idempotency key was already used for different Attachment facts'
                using errcode = '23514';
        end if;
        if existing_attachment.validation_state = 'PENDING'
           and existing_attachment.removed_at is null
           and existing_attachment.object_state = 'AWAITING_UPLOAD' then
            update public.clinical_attachments
            set upload_stale_after = operation_timestamp + interval '3 hours'
            where id = existing_attachment.id
            returning * into existing_attachment;
        end if;
        return jsonb_build_object(
            'attachment_id', existing_attachment.id,
            'storage_object_id', existing_attachment.storage_object_id,
            'can_issue_upload', existing_attachment.validation_state = 'PENDING'
                and existing_attachment.removed_at is null
                and existing_attachment.object_state = 'AWAITING_UPLOAD',
            'idempotent_retry', true,
            'upload_stale_after', existing_attachment.upload_stale_after
        );
    end if;

    select count(*) into current_count from public.clinical_attachments as attachment
    where attachment.clinical_record_entry_id = p_entry_id and attachment.removed_at is null;
    if current_count >= 5 then
        raise exception 'A Clinical Record Entry may have at most five current Attachments'
            using errcode = '23514';
    end if;
    insert into public.clinical_attachments (
        clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id, created_at,
        upload_idempotency_key, upload_stale_after, original_filename
    ) values (
        p_entry_id, acting_user_id, p_uploader_vca_id, operation_timestamp,
        p_upload_idempotency_key, operation_timestamp + interval '3 hours', p_original_filename
    ) returning * into created_attachment;
    return jsonb_build_object(
        'attachment_id', created_attachment.id,
        'storage_object_id', created_attachment.storage_object_id,
        'can_issue_upload', true,
        'idempotent_retry', false,
        'upload_stale_after', created_attachment.upload_stale_after
    );
end;
$function$;


-- remove_draft_clinical_attachment: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.remove_draft_clinical_attachment(p_auth_subject uuid, p_attachment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    attachment_record public.clinical_attachments%rowtype;
    record_entry public.clinical_record_entries%rowtype;
    entry_clinic_id uuid;
    professional_context record;
    operation_timestamp timestamptz := clock_timestamp();
begin
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth' and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id;
    if not found then raise exception 'Clinical Attachment does not exist' using errcode = '23503'; end if;
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = attachment_record.clinical_record_entry_id;
    select appointment.clinic_id into entry_clinic_id from public.appointments as appointment
    where appointment.id = record_entry.appointment_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, entry_clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = record_entry.id for share;
    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id for update;
    if attachment_record.removed_at is not null then
        return jsonb_build_object('attachment_id', attachment_record.id,
            'storage_object_id', attachment_record.storage_object_id,
            'object_state', attachment_record.object_state, 'idempotent_retry', true);
    end if;
    -- SPEC-MED-010 BR-19: only the Entry's author, and never an AVAILABLE one.
    if record_entry.created_by_user_id is distinct from acting_user_id
       or professional_context.veterinarian_clinic_assignment_id is null then
        raise exception 'Only the Entry author may remove its Attachments' using errcode = '42501';
    end if;
    if attachment_record.validation_state = 'AVAILABLE' then
        raise exception 'An AVAILABLE Attachment cannot be removed' using errcode = '23514';
    end if;
    update public.clinical_attachments set
        removed_at = operation_timestamp,
        removed_by_user_id = acting_user_id,
        removed_by_vca_id = professional_context.veterinarian_clinic_assignment_id,
        object_state = case when object_state = 'DELETED' then 'DELETED' else 'DELETE_PENDING' end,
        object_state_changed_at = operation_timestamp
    where id = p_attachment_id returning * into attachment_record;
    return jsonb_build_object('attachment_id', attachment_record.id,
        'storage_object_id', attachment_record.storage_object_id,
        'object_state', attachment_record.object_state, 'idempotent_retry', false);
end;
$function$;


-- create_clinical_amendment: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.create_clinical_amendment(p_original_clinical_record_entry_id uuid, p_reason text, p_amendment_content text, p_idempotency_key uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    entry_clinic_id uuid;
    professional_context record;
    normalized_reason text;
    normalized_content text;
    amendment_record public.clinical_amendments%rowtype;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    normalized_content := nullif(btrim(p_amendment_content, E' \t\n\r\f\013'), '');
    if normalized_reason is null or normalized_content is null or p_idempotency_key is null then
        raise exception 'Amendment reason, content, and idempotency key are required' using errcode = '22023';
    end if;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_original_clinical_record_entry_id;
    if not found then raise exception 'Original Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select appointment.clinic_id into entry_clinic_id from public.appointments as appointment
    where appointment.id = record_entry.appointment_id;
    -- SPEC-SUB-004 BR-20: commercial loss never blocks a necessary correction;
    -- the current Veterinarian context and capability are still required.
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, entry_clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_original_clinical_record_entry_id for share;

    insert into public.clinical_amendments (
        original_clinical_record_entry_id, reason, amendment_content,
        amending_user_id, amending_veterinarian_clinic_assignment_id,
        created_at, idempotency_key
    ) values (
        p_original_clinical_record_entry_id, normalized_reason, normalized_content,
        acting_user_id, professional_context.veterinarian_clinic_assignment_id,
        clock_timestamp(), p_idempotency_key
    ) on conflict (amending_user_id, idempotency_key) do nothing;

    select clinical_amendment.* into amendment_record
    from public.clinical_amendments as clinical_amendment
    where clinical_amendment.amending_user_id = acting_user_id
      and clinical_amendment.idempotency_key = p_idempotency_key;
    if amendment_record.original_clinical_record_entry_id is distinct from p_original_clinical_record_entry_id
       or amendment_record.reason is distinct from normalized_reason
       or amendment_record.amendment_content is distinct from normalized_content
       or amendment_record.amending_veterinarian_clinic_assignment_id is distinct from
          professional_context.veterinarian_clinic_assignment_id then
        raise exception 'Idempotency key was already used with a different Amendment request' using errcode = '23505';
    end if;
    return amendment_record.id;
end;
$function$;


-- 5d. Record a Clinical Record Entry (SPEC-MED-010 BR-23).
create function public.create_appointment_clinical_entry(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_idempotency_key uuid,
    p_category text,
    p_clinical_content text,
    p_other_category_context text,
    p_clinical_event_at timestamptz,
    p_clinical_event_now boolean default false
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
    assigned_clinic_assignment_id uuid;
    normalized_content text;
    normalized_other_context text;
    requested_event_at timestamptz;
    requested_digest bytea;
    existing_entry public.clinical_record_entries%rowtype;
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

    -- 1. Authority before any target (BR-17), in the clinical lock order:
    --    Organization -> Clinic -> Membership/Grant/Assignment -> Appointment.
    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id
    for share;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 2. Key.
    if p_idempotency_key is null then
        raise exception 'A creation key is required' using errcode = '22023', hint = 'KEY_REQUIRED';
    end if;

    -- 3. Field rules (BR-5). "Now" is an explicit choice resolved by the server.
    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');
    if coalesce(p_clinical_event_now, false) and p_clinical_event_at is not null then
        raise exception 'An explicit event time and Now cannot be combined'
            using errcode = '22023', hint = 'INVALID_EVENT_TIME';
    end if;
    perform public.assert_clinical_entry_fields(
        p_category, normalized_content, normalized_other_context, p_clinical_event_at
    );
    requested_event_at := case when coalesce(p_clinical_event_now, false)
                               then statement_timestamp() else p_clinical_event_at end;

    -- 4. Reconciliation (BR-7). The digest records the requested facts, so a
    --    retried "Now" request is the same request.
    requested_digest := sha256(convert_to(jsonb_build_object(
        'appointment_id', appointment_record.id,
        'category', p_category,
        'clinical_content', normalized_content,
        'other_category_context', normalized_other_context,
        'clinical_event_at', extract(epoch from p_clinical_event_at),
        'clinical_event_now', coalesce(p_clinical_event_now, false)
    )::text, 'UTF8'));
    select entry.* into existing_entry
    from public.clinical_record_entries as entry
    where entry.created_by_user_id = acting_user_id
      and entry.creation_idempotency_key = p_idempotency_key;
    if found then
        if existing_entry.creation_request_digest = requested_digest then
            return jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', existing_entry.id);
        end if;
        raise exception 'The creation key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    -- 5. Documentable Appointment (BR-3).
    if not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state) then
        raise exception 'The Appointment cannot be documented'
            using errcode = '23514', hint = 'APPOINTMENT_STATE_INVALID';
    end if;

    -- 6. Current eligible assignee, read under the Appointment lock (BR-6).
    select assignment.veterinarian_clinic_assignment_id into assigned_clinic_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = appointment_record.id
      and assignment.effective_end is null;
    if assigned_clinic_assignment_id is null then
        raise exception 'No Veterinarian is assigned to this Appointment'
            using errcode = '23514', hint = 'NO_VETERINARIAN_ASSIGNED';
    end if;
    if assigned_clinic_assignment_id <> actor.veterinarian_clinic_assignment_id
       or not public.appointment_veterinarian_is_eligible(assigned_clinic_assignment_id, p_clinic_id) then
        raise exception 'Only the assigned Veterinarian can add records to this Appointment'
            using errcode = '23514', hint = 'NOT_ASSIGNED_VETERINARIAN';
    end if;

    -- 7. Commercial gate for every new Entry (BR-13).
    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then
        raise exception 'Clinical care is currently unavailable for this Organization'
            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';
    end if;

    -- 8. Recording; a concurrent request with the same key reconciles above
    --    on retry and is rejected by the unique key here.
    insert into public.clinical_record_entries (
        appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id,
        created_at, category, clinical_content, other_category_context, clinical_event_at,
        creation_idempotency_key, creation_request_digest
    ) values (
        appointment_record.id, acting_user_id, actor.veterinarian_clinic_assignment_id,
        clock_timestamp(), p_category, normalized_content, normalized_other_context, requested_event_at,
        p_idempotency_key, requested_digest
    )
    on conflict (created_by_user_id, creation_idempotency_key) do nothing
    returning id into created_entry_id;

    if created_entry_id is null then
        select entry.* into existing_entry
        from public.clinical_record_entries as entry
        where entry.created_by_user_id = acting_user_id
          and entry.creation_idempotency_key = p_idempotency_key;
        if existing_entry.creation_request_digest = requested_digest then
            return jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', existing_entry.id);
        end if;
        raise exception 'The creation key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id);
end;
$$;

revoke all privileges
on function public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean)
from public, anon, authenticated, service_role;
grant execute
on function public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean)
to authenticated;

-- 5e. Appointment clinical record read (SPEC-MED-010 BR-20, BR-21).
create or replace function public.view_appointment_clinical_record(
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
    actor_found boolean := false;
    appointment_record public.appointments%rowtype;
    care_auth_id uuid;
    clinic_organization_id uuid;
    assigned_clinic_assignment_id uuid;
    has_entries boolean;
    unavailable_reason text;
    entries_payload jsonb;
    entries_truncated boolean;
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
    actor_found := found;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        return jsonb_build_object('status', 'DENIED');
    end if;

    select clinic.organization_id into clinic_organization_id
    from public.clinics as clinic where clinic.id = appointment_record.clinic_id;
    select care_auth.id into care_auth_id
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = appointment_record.id
      and care_auth.purpose = 'APPOINTMENT_CARE';
    has_entries := exists (
        select 1 from public.clinical_record_entries as entry
        where entry.appointment_id = appointment_record.id
    );

    if not actor_found then
        if has_entries then
            perform public.establish_medical_access_audit_event(
                p_acting_user_id => acting_user_id,
                p_pet_id => appointment_record.pet_id,
                p_operation => 'VIEW_APPOINTMENT_CLINICAL_RECORD',
                p_outcome => 'DENIED',
                p_actor_context => 'PROFESSIONAL_CLINICAL',
                p_protected_resource_scope => 'APPOINTMENT_CLINICAL_RECORD',
                p_occurred_at => clock_timestamp(),
                p_care_authorization_id => care_auth_id,
                p_accessing_clinic_id => appointment_record.clinic_id,
                p_accessing_organization_id => clinic_organization_id,
                p_appointment_id => appointment_record.id
            );
        end if;
        return jsonb_build_object('status', 'DENIED');
    end if;

    -- Advisory documentation state (BR-20); every write re-validates.
    select assignment.veterinarian_clinic_assignment_id into assigned_clinic_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = appointment_record.id
      and assignment.effective_end is null;
    unavailable_reason := case
        when not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state)
            then 'APPOINTMENT_STATE'
        when assigned_clinic_assignment_id is null
            then 'NO_VETERINARIAN_ASSIGNED'
        when assigned_clinic_assignment_id <> actor.veterinarian_clinic_assignment_id
             or not public.appointment_veterinarian_is_eligible(assigned_clinic_assignment_id, p_clinic_id)
            then 'NOT_ASSIGNED_VETERINARIAN'
        when not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE')
            then 'CLINICAL_SERVICE_UNAVAILABLE'
    end;

    select coalesce(jsonb_agg(jsonb_build_object(
               'entry_id', page.id,
               'category', page.category,
               'other_category_context', page.other_category_context,
               'clinical_content', page.clinical_content,
               'clinical_event_at', page.clinical_event_at,
               'recorded_at', page.created_at,
               'recorded_by_me', page.created_by_user_id = acting_user_id,
               'may_amend', page.created_by_user_id = acting_user_id,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'amendment_id', amendment.id,
                       'reason', amendment.reason,
                       'amendment_content', amendment.amendment_content,
                       'created_at', amendment.created_at,
                       'amended_by_me', amendment.amending_user_id = acting_user_id
                   ) order by amendment.created_at, amendment.id)
                   from (
                       select candidate.*
                       from public.clinical_amendments as candidate
                       where candidate.original_clinical_record_entry_id = page.id
                       order by candidate.created_at, candidate.id
                       limit 100
                   ) as amendment
               ), '[]'::jsonb),
               'amendments_truncated', (
                   select count(*) > 100 from public.clinical_amendments as counted
                   where counted.original_clinical_record_entry_id = page.id)
           ) order by page.created_at, page.id), '[]'::jsonb)
    into entries_payload
    from (
        select entry.*
        from public.clinical_record_entries as entry
        where entry.appointment_id = appointment_record.id
        order by entry.created_at, entry.id
        limit 100
    ) as page;
    entries_truncated := (
        select count(*) > 100 from public.clinical_record_entries as entry
        where entry.appointment_id = appointment_record.id
    );

    -- One audit event per read that returns medical information, written
    -- before release (ADR-004).
    if has_entries then
        perform public.establish_medical_access_audit_event(
            p_acting_user_id => acting_user_id,
            p_pet_id => appointment_record.pet_id,
            p_operation => 'VIEW_APPOINTMENT_CLINICAL_RECORD',
            p_outcome => 'PERMITTED',
            p_actor_context => 'PROFESSIONAL_CLINICAL',
            p_protected_resource_scope => 'APPOINTMENT_CLINICAL_RECORD',
            p_occurred_at => clock_timestamp(),
            p_care_authorization_id => care_auth_id,
            p_accessing_clinic_id => p_clinic_id,
            p_accessing_organization_id => actor.organization_id,
            p_appointment_id => appointment_record.id,
            p_organization_membership_id => actor.organization_membership_id,
            p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
            p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id
        );
    end if;

    return jsonb_build_object(
        'status', 'PERMITTED',
        'appointment', jsonb_build_object(
            'appointment_id', appointment_record.id,
            'lifecycle_state', appointment_record.lifecycle_state),
        'documentation', jsonb_build_object(
            'can_record', unavailable_reason is null,
            'unavailable_reason', unavailable_reason),
        'entries', entries_payload,
        'entries_truncated', entries_truncated
    );
end;
$$;

-- 5f. Author-only client Amendment (SPEC-MED-010 BR-18, SPEC-MED-004 §15).
create or replace function public.create_appointment_clinical_amendment(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_entry_id uuid,
    p_idempotency_key uuid,
    p_reason text,
    p_amendment_content text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    entry_record public.clinical_record_entries%rowtype;
    existing_amendment public.clinical_amendments%rowtype;
    normalized_reason text;
    normalized_content text;
    created_amendment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 1. Authority before any target; no Entitlement (SPEC-SUB-004 BR-20).
    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 2. The Entry of that Appointment of that Clinic; independent of the
    --    Care Authorization (BR-11).
    select entry.* into entry_record
    from public.clinical_record_entries as entry
    join public.appointments as appointment on appointment.id = entry.appointment_id
    where entry.id = p_entry_id
      and appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id
    for share of entry;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 3. Only the Entry's own author rectifies it (BR-18).
    if entry_record.created_by_user_id is distinct from acting_user_id then
        raise exception 'Only the author of the record can add a rectification'
            using errcode = '23514', hint = 'ENTRY_AUTHOR_REQUIRED';
    end if;

    -- 4. The request.
    if p_idempotency_key is null then
        raise exception 'An Amendment key is required' using errcode = '22023', hint = 'KEY_REQUIRED';
    end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    if normalized_reason is null then
        raise exception 'An Amendment reason is required' using errcode = '22023', hint = 'REASON_REQUIRED';
    end if;
    normalized_content := nullif(btrim(p_amendment_content, E' \t\n\r\f\013'), '');
    if normalized_content is null then
        raise exception 'Amendment content is required' using errcode = '22023', hint = 'CONTENT_REQUIRED';
    end if;

    -- 5. Creation, or exact replay / contradictory reuse of this User's key.
    insert into public.clinical_amendments (
        original_clinical_record_entry_id, reason, amendment_content,
        amending_user_id, amending_veterinarian_clinic_assignment_id,
        created_at, idempotency_key
    ) values (
        entry_record.id, normalized_reason, normalized_content,
        acting_user_id, actor.veterinarian_clinic_assignment_id,
        clock_timestamp(), p_idempotency_key
    )
    on conflict (amending_user_id, idempotency_key) do nothing
    returning id into created_amendment_id;

    if created_amendment_id is not null then
        return jsonb_build_object('outcome', 'CREATED', 'amendment_id', created_amendment_id);
    end if;

    select amendment.* into existing_amendment
    from public.clinical_amendments as amendment
    where amendment.amending_user_id = acting_user_id
      and amendment.idempotency_key = p_idempotency_key;
    if existing_amendment.original_clinical_record_entry_id = entry_record.id
       and existing_amendment.reason = normalized_reason
       and existing_amendment.amendment_content = normalized_content
       and existing_amendment.amending_veterinarian_clinic_assignment_id
           = actor.veterinarian_clinic_assignment_id then
        return jsonb_build_object('outcome', 'ALREADY_CREATED', 'amendment_id', existing_amendment.id);
    end if;

    raise exception 'The Amendment key was already used for a different request'
        using errcode = '23505', hint = 'KEY_CONFLICT';
end;
$$;

-- 5g. History projection shared by the Guardian and professional reads
--     (SPEC-MED-010 BR-22): provenance through the Entry's Appointment and its
--     Clinic, order coalesce(clinical_event_at, recorded time), never filtered
--     by any Care Authorization state.
drop function public.clinical_history_page(uuid, integer, timestamptz, uuid);

create function public.clinical_history_page(
    p_pet_id uuid,
    p_limit integer,
    p_before_history_order_at timestamptz,
    p_before_entry_id uuid
)
returns table (
    entry_id uuid,
    history_order_at timestamptz,
    category text,
    other_category_context text,
    clinical_content text,
    clinical_event_at timestamptz,
    finalized_at timestamptz,
    clinic_display_name text,
    organization_display_name text,
    appointment_id uuid,
    created_by_user_id uuid,
    amendment_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
    select record_entry.id,
           coalesce(record_entry.clinical_event_at, record_entry.created_at),
           record_entry.category,
           record_entry.other_category_context,
           record_entry.clinical_content,
           record_entry.clinical_event_at,
           -- Recording is publication (BR-4): the publication time is the
           -- recording time.
           record_entry.created_at,
           (select profile.display_name
            from public.clinic_public_profiles as profile
            where profile.clinic_id = appointment.clinic_id),
           (select organization.display_name
            from public.veterinary_organizations as organization
            where organization.id = clinic.organization_id),
           record_entry.appointment_id,
           record_entry.created_by_user_id,
           (select count(*)::integer
            from public.clinical_amendments as amendment
            where amendment.original_clinical_record_entry_id = record_entry.id)
    from public.clinical_record_entries as record_entry
    join public.appointments as appointment
      on appointment.id = record_entry.appointment_id
    join public.clinics as clinic
      on clinic.id = appointment.clinic_id
    where appointment.pet_id = p_pet_id
      and (p_before_history_order_at is null
           or (coalesce(record_entry.clinical_event_at, record_entry.created_at), record_entry.id)
              < (p_before_history_order_at, p_before_entry_id))
    order by coalesce(record_entry.clinical_event_at, record_entry.created_at) desc,
             record_entry.id desc
    limit p_limit + 1
$$;

revoke all privileges
on function public.clinical_history_page(uuid, integer, timestamptz, uuid)
from public, anon, authenticated, service_role;

-- view_guardian_pet_medical_history: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.view_guardian_pet_medical_history(p_pet_id uuid, p_limit integer DEFAULT 50, p_before_history_order_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_entry_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    guardianship_record public.guardianships%rowtype;
    bounded_limit integer;
    result_payload jsonb;
    has_more boolean;
    next_order_at timestamptz;
    next_entry_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_limit is null or p_limit < 1 then raise exception 'Page limit must be positive' using errcode = '22023'; end if;
    if (p_before_history_order_at is null) <> (p_before_entry_id is null) then
        raise exception 'History cursor components must be supplied together' using errcode = '22023';
    end if;
    if p_before_history_order_at is not null and not isfinite(p_before_history_order_at) then
        raise exception 'History cursor timestamp must be finite' using errcode = '22023';
    end if;
    bounded_limit := least(p_limit, 100);
    if not exists (select 1 from public.pets as pet where pet.id = p_pet_id) then
        return jsonb_build_object('status', 'DENIED');
    end if;
    select guardianship.* into guardianship_record
    from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
    for share;
    if not found then
        select guardianship.* into guardianship_record
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
        order by guardianship.effective_start desc, guardianship.id desc
        limit 1;
        perform public.establish_medical_access_audit_event(
            acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'DENIED',
            'GUARDIAN', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
            guardianship_record.id, null, null, null, null, null, null, null, null, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    with page as (
        select *
        from public.clinical_history_page(p_pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id)
    ), visible as (
        select * from page
        order by page.history_order_at desc, page.entry_id desc
        limit bounded_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', visible.entry_id,
               'category', visible.category,
               'other_category_context', visible.other_category_context,
               'clinical_content', visible.clinical_content,
               'clinical_event_at', visible.clinical_event_at,
               'history_order_at', visible.history_order_at,
               'finalized_at', visible.finalized_at,
               'clinic_display_name', visible.clinic_display_name,
               'organization_display_name', visible.organization_display_name,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'id', amendment.amendment_id,
                       'reason', amendment.reason,
                       'amendment_content', amendment.amendment_content,
                       'created_at', amendment.created_at
                   ) order by amendment.created_at, amendment.amendment_id)
                   from public.clinical_history_amendments(visible.entry_id) as amendment
               ), '[]'::jsonb),
               'amendment_count', visible.amendment_count,
               'amendments_truncated', visible.amendment_count > 100,
               'attachments', public.clinical_attachment_metadata_for_entry(visible.entry_id, false)
           ) order by visible.history_order_at desc, visible.entry_id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page),
           (array_agg(visible.history_order_at order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit],
           (array_agg(visible.entry_id order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit]
    into result_payload, has_more, next_order_at, next_entry_id
    from visible;

    perform public.establish_medical_access_audit_event(
        acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'PERMITTED',
        'GUARDIAN', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
        guardianship_record.id, null, null, null, null, null, null, null, null, null
    );
    return jsonb_build_object(
        'status', 'PERMITTED', 'payload', jsonb_build_object('entries', result_payload),
        'cursor', case when has_more then jsonb_build_object(
            'before_history_order_at', next_order_at, 'before_entry_id', next_entry_id
        ) else null end
    );
end;
$function$;


-- view_appointment_professional_medical_history: deployed body; Clinical Encounter dependency replaced (SPEC-MED-010).
CREATE OR REPLACE FUNCTION public.view_appointment_professional_medical_history(p_clinic_id uuid, p_appointment_id uuid, p_limit integer DEFAULT 50, p_before_history_order_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_entry_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
declare
    acting_user_id uuid;
    actor record;
    locked_actor record;
    actor_found boolean := false;
    authorized boolean := false;
    bounded_limit integer;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    entries_payload jsonb;
    has_more boolean;
    next_order_at timestamptz;
    next_entry_id uuid;
begin
    -- 1. Authentication.
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Argument shape only; no stored data is consulted.
    if p_limit is null or p_limit < 1 then
        raise exception 'Page limit must be positive' using errcode = '22023', hint = 'INVALID_LIMIT';
    end if;
    if (p_before_history_order_at is null) <> (p_before_entry_id is null)
       or (p_before_history_order_at is not null and not isfinite(p_before_history_order_at)) then
        raise exception 'History cursor is invalid' using errcode = '22023', hint = 'INVALID_CURSOR';
    end if;
    bounded_limit := least(p_limit, 100);

    -- 3. Authority before any target: the current exact-Clinic Veterinarian
    --    context holding CLINICAL_CARE, share-locked so offboarding either
    --    precedes this read or waits for it, then decided again.
    select * into actor
    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_CARE');
    if found then
        perform 1 from public.organization_memberships as membership
        where membership.id = actor.organization_membership_id for share;
        perform 1 from public.organization_responsibility_grants as grant_record
        where grant_record.id = actor.organization_responsibility_grant_id for share;
        perform 1 from public.veterinarian_clinic_assignments as assignment
        where assignment.id = actor.veterinarian_clinic_assignment_id for share;
        select context.* into locked_actor
        from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_CARE') as context
        where context.organization_membership_id = actor.organization_membership_id
          and context.organization_responsibility_grant_id = actor.organization_responsibility_grant_id
          and context.veterinarian_clinic_assignment_id = actor.veterinarian_clinic_assignment_id;
        actor_found := found;
    end if;
    authorized := actor_found
        and public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE');

    -- 4. The Appointment of the named Clinic. Unknown or foreign: no Pet
    --    context, nothing audited, the same denial.
    if authorized then
        select appointment.* into appointment_record
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and appointment.clinic_id = p_clinic_id
        for share;
    else
        select appointment.* into appointment_record
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and appointment.clinic_id = p_clinic_id;
    end if;
    if not found then
        return jsonb_build_object('status', 'DENIED');
    end if;

    -- 5. Its Appointment-derived Care Authorization.
    if authorized then
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = appointment_record.id
          and care_auth.purpose = 'APPOINTMENT_CARE'
        for share;
    else
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = appointment_record.id
          and care_auth.purpose = 'APPOINTMENT_CARE';
    end if;

    -- 6. The history window; any refusal is one audited, uniform denial.
    if not authorized
       or not public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp()) then
        perform public.establish_medical_access_audit_event(
            p_acting_user_id => acting_user_id,
            p_pet_id => appointment_record.pet_id,
            p_operation => 'VIEW_PET_MEDICAL_HISTORY',
            p_outcome => 'DENIED',
            p_actor_context => 'PROFESSIONAL_CLINICAL',
            p_protected_resource_scope => 'LONGITUDINAL_MEDICAL_HISTORY',
            p_occurred_at => clock_timestamp(),
            p_care_authorization_id => care_auth_record.id,
            p_accessing_clinic_id => appointment_record.clinic_id,
            p_accessing_organization_id => (
                select clinic.organization_id from public.clinics as clinic
                where clinic.id = appointment_record.clinic_id),
            p_appointment_id => appointment_record.id,
            p_organization_membership_id =>
                case when actor_found then actor.organization_membership_id end,
            p_organization_responsibility_grant_id =>
                case when actor_found then actor.organization_responsibility_grant_id end,
            p_veterinarian_clinic_assignment_id =>
                case when actor_found then actor.veterinarian_clinic_assignment_id end
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    -- 7. The Pet's complete finalized history, from every Clinic and
    --    Organization, assembled in one statement (one snapshot).
    with page as (
        select *
        from public.clinical_history_page(
            appointment_record.pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id
        )
    ), visible as (
        select * from page
        order by page.history_order_at desc, page.entry_id desc
        limit bounded_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
               'entry_id', visible.entry_id,
               'category', visible.category,
               'other_category_context', visible.other_category_context,
               'clinical_content', visible.clinical_content,
               'clinical_event_at', visible.clinical_event_at,
               'history_order_at', visible.history_order_at,
               'finalized_at', visible.finalized_at,
               'clinic_display_name', visible.clinic_display_name,
               'organization_display_name', visible.organization_display_name,
               'is_this_appointment', visible.appointment_id is not distinct from appointment_record.id,
               'author', jsonb_build_object(
                   'display_name', public.clinical_provenance_display_name(visible.created_by_user_id),
                   'is_me', visible.created_by_user_id = acting_user_id),
               -- An Entry is published by its own author when recorded.
               'finalizer', null,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'amendment_id', amendment.amendment_id,
                       'reason', amendment.reason,
                       'amendment_content', amendment.amendment_content,
                       'created_at', amendment.created_at,
                       'author', jsonb_build_object(
                           'display_name', public.clinical_provenance_display_name(amendment.amending_user_id),
                           'is_me', amendment.amending_user_id = acting_user_id)
                   ) order by amendment.created_at, amendment.amendment_id)
                   from public.clinical_history_amendments(visible.entry_id) as amendment
               ), '[]'::jsonb),
               'amendment_count', visible.amendment_count,
               'amendments_truncated', visible.amendment_count > 100
           ) order by visible.history_order_at desc, visible.entry_id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page),
           (array_agg(visible.history_order_at order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit],
           (array_agg(visible.entry_id order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit]
    into entries_payload, has_more, next_order_at, next_entry_id
    from visible;

    -- 8. One meaningful protected access per page, before release, with the
    --    current access context (SPEC-MED-005 BR-45).
    perform public.establish_medical_access_audit_event(
        p_acting_user_id => acting_user_id,
        p_pet_id => appointment_record.pet_id,
        p_operation => 'VIEW_PET_MEDICAL_HISTORY',
        p_outcome => 'PERMITTED',
        p_actor_context => 'PROFESSIONAL_CLINICAL',
        p_protected_resource_scope => 'LONGITUDINAL_MEDICAL_HISTORY',
        p_occurred_at => clock_timestamp(),
        p_care_authorization_id => care_auth_record.id,
        p_accessing_clinic_id => p_clinic_id,
        p_accessing_organization_id => actor.organization_id,
        p_appointment_id => appointment_record.id,
        p_organization_membership_id => actor.organization_membership_id,
        p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id
    );

    return jsonb_build_object(
        'status', 'PERMITTED',
        'entries', entries_payload,
        'cursor', case when has_more then jsonb_build_object(
            'before_history_order_at', next_order_at,
            'before_entry_id', next_entry_id
        ) end
    );
end;
$function$;


-- 5h. Attachment download authorization (SPEC-MED-010 BR-19; keeps the
--     signature the deployed Edge Function calls). Guardian: current
--     Guardianship. Professional LONGITUDINAL: prior-history access through
--     the named Appointment Care Authorization (BR-14). Professional
--     EXACT_RESOURCE: documentation access to the Entry's Appointment (BR-11).
--     The former Encounter parameter is accepted only as NULL.
create or replace function public.authorize_clinical_attachment_download(
    p_auth_subject uuid,
    p_attachment_id uuid,
    p_access_context text,
    p_professional_scope text default null,
    p_accessing_clinic_id uuid default null,
    p_care_authorization_id uuid default null,
    p_accessing_clinical_encounter_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    attachment_record public.clinical_attachments%rowtype;
    record_entry public.clinical_record_entries%rowtype;
    origin_appointment public.appointments%rowtype;
    origin_organization_id uuid;
    access_care_auth public.care_authorizations%rowtype;
    guardianship_record public.guardianships%rowtype;
    professional_context record;
    accessing_organization_id uuid;
    audit_organization_membership_id uuid := null;
    audit_organization_responsibility_grant_id uuid := null;
    audit_veterinarian_clinic_assignment_id uuid := null;
    audit_care_authorization_id uuid := null;
    audit_appointment_id uuid := null;
    permitted boolean := false;
begin
    if p_access_context is null or p_access_context not in ('GUARDIAN', 'PROFESSIONAL') then
        raise exception 'Access context must be GUARDIAN or PROFESSIONAL' using errcode = '22023';
    end if;
    if p_accessing_clinical_encounter_id is not null then
        raise exception 'Clinical Encounters no longer exist' using errcode = '22023';
    end if;
    if p_access_context = 'GUARDIAN' and (
        p_professional_scope is not null or p_accessing_clinic_id is not null or p_care_authorization_id is not null
    ) then
        raise exception 'Guardian access cannot carry professional context' using errcode = '22023';
    end if;
    if p_access_context = 'PROFESSIONAL'
       and (p_professional_scope is null or p_professional_scope not in ('LONGITUDINAL', 'EXACT_RESOURCE')) then
        raise exception 'Professional scope must be explicit' using errcode = '22023';
    end if;
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth' and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id;
    if not found then return jsonb_build_object('status', 'DENIED'); end if;
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = attachment_record.clinical_record_entry_id;
    select appointment.* into origin_appointment from public.appointments as appointment
    where appointment.id = record_entry.appointment_id;
    select clinic.organization_id into origin_organization_id
    from public.clinics as clinic where clinic.id = origin_appointment.clinic_id;

    if p_access_context = 'GUARDIAN' then
        select guardianship.* into guardianship_record from public.guardianships as guardianship
        where guardianship.pet_id = origin_appointment.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
        for share;
        if not found then
            select guardianship.* into guardianship_record from public.guardianships as guardianship
            where guardianship.pet_id = origin_appointment.pet_id and guardianship.user_id = acting_user_id
            order by guardianship.effective_start desc, guardianship.id desc limit 1;
        end if;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
        permitted := guardianship_record.id is not null
            and guardianship_record.effective_start <= clock_timestamp()
            and guardianship_record.effective_end is null;
    elsif p_professional_scope = 'LONGITUDINAL' then
        select clinic.organization_id into accessing_organization_id
        from public.clinics as clinic where clinic.id = p_accessing_clinic_id;
        select * into professional_context
        from public.find_current_veterinarian_context_after_lock(
            acting_user_id, p_accessing_clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
        );
        if found then
            audit_organization_membership_id := professional_context.organization_membership_id;
            audit_organization_responsibility_grant_id := professional_context.organization_responsibility_grant_id;
            audit_veterinarian_clinic_assignment_id := professional_context.veterinarian_clinic_assignment_id;
            select care_auth.* into access_care_auth from public.care_authorizations as care_auth
            where care_auth.id = p_care_authorization_id
              and care_auth.pet_id = origin_appointment.pet_id
              and care_auth.clinic_id = p_accessing_clinic_id
              and care_auth.organization_id = professional_context.organization_id
              and care_auth.purpose = 'APPOINTMENT_CARE';
            if found then
                perform 1 from public.appointments as appointment
                where appointment.id = access_care_auth.appointment_id for share;
                perform 1 from public.care_authorizations as care_auth
                where care_auth.id = access_care_auth.id for share;
                permitted := public.appointment_professional_history_accessible(
                    access_care_auth.appointment_id, clock_timestamp());
            end if;
        end if;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
    else
        select clinic.organization_id into accessing_organization_id
        from public.clinics as clinic where clinic.id = p_accessing_clinic_id;
        if p_accessing_clinic_id is not distinct from origin_appointment.clinic_id then
            select * into professional_context
            from public.find_current_veterinarian_context_after_lock(
                acting_user_id, origin_appointment.clinic_id, 'CLINICAL_DOCUMENTATION', null
            );
            if found then
                audit_organization_membership_id := professional_context.organization_membership_id;
                audit_organization_responsibility_grant_id := professional_context.organization_responsibility_grant_id;
                audit_veterinarian_clinic_assignment_id := professional_context.veterinarian_clinic_assignment_id;
                select care_auth.id into audit_care_authorization_id from public.care_authorizations as care_auth
                where care_auth.appointment_id = origin_appointment.id and care_auth.purpose = 'APPOINTMENT_CARE';
                permitted := p_care_authorization_id is null
                    or p_care_authorization_id is not distinct from audit_care_authorization_id;
                audit_appointment_id := origin_appointment.id;
            end if;
        end if;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
    end if;

    permitted := permitted
        and attachment_record.removed_at is null
        and attachment_record.validation_state = 'AVAILABLE'
        and attachment_record.object_state = 'STORED';

    if permitted and not exists (
        select 1 from storage.objects as object_record
        where object_record.bucket_id = 'clinical-attachments'
          and object_record.name = 'v1/' || attachment_record.storage_object_id::text
    ) then
        raise exception 'Authorized Clinical Attachment Storage object is missing' using errcode = 'XX001';
    end if;

    perform public.establish_medical_access_audit_event(
        p_acting_user_id => acting_user_id,
        p_pet_id => origin_appointment.pet_id,
        p_operation => 'VIEW_CLINICAL_ATTACHMENT',
        p_outcome => case when permitted then 'PERMITTED' else 'DENIED' end,
        p_actor_context => case when p_access_context = 'GUARDIAN' then 'GUARDIAN' else 'PROFESSIONAL_CLINICAL' end,
        p_protected_resource_scope => 'CLINICAL_ATTACHMENT',
        p_occurred_at => clock_timestamp(),
        p_guardianship_id => case when p_access_context = 'GUARDIAN' then guardianship_record.id end,
        p_care_authorization_id => audit_care_authorization_id,
        p_accessing_clinic_id => case when p_access_context = 'PROFESSIONAL' and accessing_organization_id is not null
                                      then p_accessing_clinic_id end,
        p_accessing_organization_id => case when p_access_context = 'PROFESSIONAL' then accessing_organization_id end,
        p_appointment_id => audit_appointment_id,
        p_organization_membership_id => audit_organization_membership_id,
        p_organization_responsibility_grant_id => audit_organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id => audit_veterinarian_clinic_assignment_id,
        p_clinical_record_entry_id => record_entry.id,
        p_clinical_attachment_id => attachment_record.id
    );
    if not permitted then return jsonb_build_object('status', 'DENIED'); end if;
    return jsonb_build_object(
        'status', 'PERMITTED',
        'attachment_id', attachment_record.id,
        'storage_object_id', attachment_record.storage_object_id,
        'original_filename', attachment_record.original_filename
    );
end;
$$;

commit;

-- Clinical Amendments — Phase 1
-- (SPEC-MED-004 §15, SPEC-MED-009 BR-4; REQ-MED-004/005/008/009).
--
-- The Appointment-keyed client path for amending a FINALIZED Clinical Record
-- Entry, and the Amendments in the Appointment clinical record. The Amendment
-- model (20260829120000_clinical_care.sql) is unchanged: an additive,
-- append-only record (reason + amendment content + amending User/Clinic
-- Assignment + creation time) referencing the original Entry, with the
-- existing per-User idempotency key. No table, constraint, or trigger changes.
--
--   1. appointment_clinical_record_accessible(encounter): the single private
--      predicate of the SPEC-MED-009 BR-4 clinical-content basis — the
--      Encounter is ACTIVE (revocation-safe active-care continuity) or its
--      Care Authorization is ACTIVE (post-care documentation). Shared by the
--      read and the Amendment write so the two cannot drift.
--   2. create_appointment_clinical_amendment: authenticated only, authority
--      before any target. Missing authority, an unknown/foreign Clinic,
--      Appointment, Encounter or Entry, and an Encounter whose clinical record
--      is no longer accessible (predicate 1, decided under the Care
--      Authorization and Encounter locks) are one uniform 42501 'Clinical
--      record unavailable' (no hint); every other rejection carries a stable
--      hint (ENTRY_NOT_FINALIZED, KEY_REQUIRED, REASON_REQUIRED,
--      CONTENT_REQUIRED, KEY_CONFLICT). Outcome CREATED | ALREADY_CREATED
--      with amendment_id. Authority is the current exact-Clinic Veterinarian
--      context holding CLINICAL_DOCUMENTATION (lock_clinical_actor_context),
--      with no Entitlement (SPEC-SUB-004 BR-20) and no original-author,
--      responsible-Veterinarian, Appointment Assignment or Availability
--      dependency; Encounter CONCLUDED and Appointment COMPLETED are allowed
--      while the record stays accessible. Semantic identity of a key:
--      original Entry, trimmed reason, trimmed content, amending Clinic
--      Assignment — exactly that of create_clinical_amendment. Lock order:
--      Organization -> Clinic -> Membership/Grant/Assignment -> Care
--      Authorization -> Encounter -> Entry (all share after the context).
--   3. view_appointment_clinical_record: each Entry gains `amendments` (oldest
--      first, at most 100: amendment_id, reason, amendment_content,
--      created_at, amended_by_me) and `amendments_truncated`; the Encounter
--      gains `may_amend`; the BR-4 basis is predicate 1. Still one audit
--      event per read. Otherwise the body of
--      20261103090000_minimal_clinical_record.sql.
--   4. ACL: authenticated EXECUTE is withdrawn from create_clinical_amendment
--      (it revealed the Entry before authority, returned a bare id and does
--      not apply the clinical-record basis); service_role keeps it as the
--      trusted writer.
begin;

-- ==================================================================
-- 1. The Appointment clinical-record basis (SPEC-MED-009 BR-4).
-- ==================================================================

create function public.appointment_clinical_record_accessible(p_clinical_encounter_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((
        select encounter_row.lifecycle_state = 'ACTIVE'
               or care_auth.lifecycle_state = 'ACTIVE'
        from public.clinical_encounters as encounter_row
        left join public.care_authorizations as care_auth
          on care_auth.id = encounter_row.care_authorization_id
        where encounter_row.id = p_clinical_encounter_id
    ), false)
$$;

revoke all privileges
on function public.appointment_clinical_record_accessible(uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 2. Create Amendment (SPEC-MED-004 BR-39–BR-44).
-- ==================================================================

create function public.create_appointment_clinical_amendment(
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
    target_encounter_id uuid;
    target_care_authorization_id uuid;
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

    -- 2. The Entry of that Appointment's Encounter, in that Clinic.
    select encounter_row.id, encounter_row.care_authorization_id
    into target_encounter_id, target_care_authorization_id
    from public.appointments as appointment
    join public.clinical_encounters as encounter_row
      on encounter_row.appointment_id = appointment.id
     and encounter_row.clinic_id = appointment.clinic_id
    join public.clinical_record_entries as entry
      on entry.clinical_encounter_id = encounter_row.id
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id
      and entry.id = p_entry_id;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 3. The record must still be reachable through the SPEC-MED-009 basis,
    --    decided under the existing lock order so a concurrent revocation is
    --    either seen or waits (SPEC-MED-004 BR-41). A cached Entry id grants
    --    nothing once access has ended.
    perform 1 from public.care_authorizations as care_auth
    where care_auth.id = target_care_authorization_id
    for share;
    perform 1 from public.clinical_encounters as encounter_row
    where encounter_row.id = target_encounter_id
    for share;
    select entry.* into entry_record
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id
    for share;
    if not public.appointment_clinical_record_accessible(target_encounter_id) then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 4. Only finalized clinical information is amended (BR-1, BR-24).
    if entry_record.lifecycle_state <> 'FINALIZED' then
        raise exception 'Only a finalized entry can be amended'
            using errcode = '23514', hint = 'ENTRY_NOT_FINALIZED';
    end if;

    -- 5. The request (BR-4, BR-5, BR-25).
    if p_idempotency_key is null then
        raise exception 'An Amendment key is required'
            using errcode = '22023', hint = 'KEY_REQUIRED';
    end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    if normalized_reason is null then
        raise exception 'An Amendment reason is required'
            using errcode = '22023', hint = 'REASON_REQUIRED';
    end if;
    normalized_content := nullif(btrim(p_amendment_content, E' \t\n\r\f\013'), '');
    if normalized_content is null then
        raise exception 'Amendment content is required'
            using errcode = '22023', hint = 'CONTENT_REQUIRED';
    end if;

    -- 6. Creation, or exact replay / contradictory reuse of this User's key
    --    (BR-38, BR-42). A concurrent same-key insert is reconciled the same way.
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

revoke all privileges
on function public.create_appointment_clinical_amendment(uuid, uuid, uuid, uuid, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.create_appointment_clinical_amendment(uuid, uuid, uuid, uuid, text, text)
to authenticated;

-- ==================================================================
-- 3. Appointment clinical record read with Amendments (SPEC-MED-009 BR-4).
--    Body of 20261103090000_minimal_clinical_record.sql plus `amendments`,
--    `amendments_truncated` per Entry and `may_amend`; the BR-4 basis is the
--    shared predicate of section 1.
-- ==================================================================

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
    -- documentation under an ACTIVE Authorization (SPEC-MED-009 BR-4); the
    -- same predicate gates the Amendment write.
    if not public.appointment_clinical_record_accessible(encounter_record.id) then
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
               'created_by_me', page.created_by_user_id = acting_user_id,
               -- SPEC-MED-004 BR-21: the Amendment chain, oldest first.
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'amendment_id', amendment_page.id,
                       'reason', amendment_page.reason,
                       'amendment_content', amendment_page.amendment_content,
                       'created_at', amendment_page.created_at,
                       'amended_by_me', amendment_page.amending_user_id = acting_user_id
                   ) order by amendment_page.created_at, amendment_page.id)
                   from (
                       select amendment.*
                       from public.clinical_amendments as amendment
                       where amendment.original_clinical_record_entry_id = page.id
                       order by amendment.created_at, amendment.id
                       limit 100
                   ) as amendment_page
               ), '[]'::jsonb),
               'amendments_truncated', (
                   select count(*) > 100
                   from public.clinical_amendments as amendment
                   where amendment.original_clinical_record_entry_id = page.id
               )
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
            'may_amend', true,
            'entries', entries_payload,
            'entries_truncated', entry_count > 100
        )
    );
end;
$$;

-- ==================================================================
-- 4. The generic Amendment writer leaves the client surface.
-- ==================================================================

revoke execute on function public.create_clinical_amendment(uuid, text, text, uuid)
from authenticated;

commit;

-- Professional Longitudinal / Cross-Clinic Medical History — Phase 1
-- (SPEC-MED-005 §15/§16, SPEC-ID-006 BR-41; REQ-MED-001/002/004/005,
-- REQ-ACC-002/003/005, REQ-ACC-007).
--
-- The Appointment-keyed client read of a Pet's longitudinal finalized history
-- for a Veterinarian, with meaningful Veterinarian provenance, and the
-- Guardian history built from the same private projection without internal
-- identifiers. No table, constraint, trigger or column changes.
--
--   1. clinical_history_page(pet, limit, cursor): the single private
--      finalized-history projection — every FINALIZED Entry of the Pet from
--      every Clinic and Organization, ordered by
--      coalesce(clinical_event_at, Encounter started_at) desc, Entry id desc,
--      keyset after the cursor, at most limit + 1 rows, with the originating
--      Clinic / Organization display names (independent of publication), the
--      historical author and finalizer User and the Amendment count. Shared by
--      the Guardian and the professional read so content, ordering and paging
--      cannot drift. clinical_history_amendments(entry): the Amendments of one
--      Entry, oldest first, at most 100. Both STABLE, so a read assembling a
--      page in one statement sees one snapshot (no Amendment without its
--      Entry, no count/list mismatch).
--   2. clinical_provenance_display_name(user): the User Profile display name
--      of a historically attributed User, trimmed, NULL when absent/blank
--      (SPEC-ID-006 BR-41). No Membership, Grant, Assignment or Profile
--      currency is consulted, so offboarding never removes it.
--   3. appointment_professional_history_accessible(appointment, at): the single
--      private SPEC-MED-005 BR-40 window predicate — the Appointment-derived
--      APPOINTMENT_CARE Care Authorization is ACTIVE and either no Encounter
--      exists and the Appointment permits pre-care access
--      (appointment_permits_pre_care_access: CONFIRMED, or REQUESTED with a
--      future latest requested start), or its Encounter is ACTIVE. Exactly the
--      window the legacy read enforced (the unresolved past-CONFIRMED case is
--      preserved, not solved).
--   4. view_appointment_professional_medical_history(clinic, appointment,
--      limit, cursor): authenticated only. Order: authenticate -> argument
--      shape (INVALID_LIMIT / INVALID_CURSOR) -> current exact-Clinic
--      Veterinarian context holding CLINICAL_CARE (clinical_actor_context_at),
--      share-locked (Membership, Grant, Assignment) and re-decided, plus the
--      Organization's CLINICAL_CARE Entitlement -> the Appointment of that
--      Clinic -> its Care Authorization and Encounter (share-locked) -> the
--      window predicate. Every failure from the context on is the same
--      {"status":"DENIED"}. One VIEW_PET_MEDICAL_HISTORY audit event per
--      permitted page (current access context only); a denial of an
--      Appointment of the named Clinic is audited DENIED; an unknown or
--      foreign Appointment establishes no Pet and is not audited. Lock order:
--      Membership/Grant/Assignment -> Appointment -> Care Authorization ->
--      Encounter (FOR SHARE throughout; no Organization/Clinic FOR UPDATE).
--   5. view_guardian_pet_medical_history: same signature, Guardianship
--      authorization, audit, ordering and cursor (authorization copied
--      verbatim from 20260829120000_clinical_care.sql); content now from the
--      shared projection; each Entry carries no User, Clinic Assignment,
--      Encounter, Clinic or Organization id, no draft_revision /
--      last_modified_at / created_at, and no Veterinarian name (SPEC-MED-005
--      BR-46). The superseded private chain
--      (slice12_view_guardian_pet_medical_history,
--      slice13_view_guardian_pet_medical_history,
--      decorate_guardian_medical_history_provenance_names) is dropped.
--   6. ACL: authenticated EXECUTE is withdrawn from the legacy
--      view_professional_pet_medical_history (client-supplied Pet / Care
--      Authorization / Encounter ids, internal ids in its result). It stays
--      as a trusted internal function; no client calls it.
begin;

-- ==================================================================
-- 1. Shared private finalized-history projection.
-- ==================================================================

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
    encounter_started_at timestamptz,
    clinic_display_name text,
    organization_display_name text,
    appointment_id uuid,
    created_by_user_id uuid,
    finalized_by_user_id uuid,
    amendment_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
    select record_entry.id,
           coalesce(record_entry.clinical_event_at, encounter_row.started_at),
           record_entry.category,
           record_entry.other_category_context,
           record_entry.clinical_content,
           record_entry.clinical_event_at,
           record_entry.finalized_at,
           encounter_row.started_at,
           (select profile.display_name
            from public.clinic_public_profiles as profile
            where profile.clinic_id = encounter_row.clinic_id),
           (select organization.display_name
            from public.veterinary_organizations as organization
            where organization.id = encounter_row.organization_id),
           encounter_row.appointment_id,
           record_entry.created_by_user_id,
           record_entry.finalized_by_user_id,
           (select count(*)::integer
            from public.clinical_amendments as amendment
            where amendment.original_clinical_record_entry_id = record_entry.id)
    from public.clinical_record_entries as record_entry
    join public.clinical_encounters as encounter_row
      on encounter_row.id = record_entry.clinical_encounter_id
    where encounter_row.pet_id = p_pet_id
      and record_entry.lifecycle_state = 'FINALIZED'
      and (p_before_history_order_at is null
           or (coalesce(record_entry.clinical_event_at, encounter_row.started_at), record_entry.id)
              < (p_before_history_order_at, p_before_entry_id))
    order by coalesce(record_entry.clinical_event_at, encounter_row.started_at) desc,
             record_entry.id desc
    limit p_limit + 1
$$;

revoke all privileges
on function public.clinical_history_page(uuid, integer, timestamptz, uuid)
from public, anon, authenticated, service_role;

create function public.clinical_history_amendments(p_entry_id uuid)
returns table (
    amendment_id uuid,
    reason text,
    amendment_content text,
    created_at timestamptz,
    amending_user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
    select amendment.id, amendment.reason, amendment.amendment_content,
           amendment.created_at, amendment.amending_user_id
    from public.clinical_amendments as amendment
    where amendment.original_clinical_record_entry_id = p_entry_id
    order by amendment.created_at, amendment.id
    limit 100
$$;

revoke all privileges
on function public.clinical_history_amendments(uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 2. Historical Veterinarian display name (SPEC-ID-006 BR-41).
-- ==================================================================

create function public.clinical_provenance_display_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select nullif(btrim(profile.display_name, E' \t\n\r\f\013'), '')
    from public.user_profiles as profile
    where profile.user_id = p_user_id
$$;

revoke all privileges
on function public.clinical_provenance_display_name(uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 3. The professional history window (SPEC-MED-005 BR-40).
-- ==================================================================

create function public.appointment_professional_history_accessible(
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
               and case
                   when encounter_row.id is null
                   then public.appointment_permits_pre_care_access(appointment.id, p_reference_time)
                   else encounter_row.lifecycle_state = 'ACTIVE'
               end
        from public.appointments as appointment
        join public.care_authorizations as care_auth
          on care_auth.appointment_id = appointment.id
         and care_auth.purpose = 'APPOINTMENT_CARE'
         and care_auth.pet_id = appointment.pet_id
         and care_auth.clinic_id = appointment.clinic_id
        left join public.clinical_encounters as encounter_row
          on encounter_row.care_authorization_id = care_auth.id
        where appointment.id = p_appointment_id
    ), false)
$$;

revoke all privileges
on function public.appointment_professional_history_accessible(uuid, timestamptz)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 4. Appointment-keyed professional history (SPEC-MED-005 BR-38–BR-47).
-- ==================================================================

create function public.view_appointment_professional_medical_history(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    locked_actor record;
    actor_found boolean := false;
    authorized boolean := false;
    bounded_limit integer;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    encounter_record public.clinical_encounters%rowtype;
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

    -- 5. Its Appointment-derived Care Authorization and Encounter.
    if authorized then
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = appointment_record.id
          and care_auth.purpose = 'APPOINTMENT_CARE'
        for share;
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.care_authorization_id = care_auth_record.id
        for share;
    else
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = appointment_record.id
          and care_auth.purpose = 'APPOINTMENT_CARE';
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.care_authorization_id = care_auth_record.id;
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
                case when actor_found then actor.veterinarian_clinic_assignment_id end,
            p_clinical_encounter_id => encounter_record.id
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
               'encounter_started_at', visible.encounter_started_at,
               'clinic_display_name', visible.clinic_display_name,
               'organization_display_name', visible.organization_display_name,
               'is_this_appointment', visible.appointment_id is not distinct from appointment_record.id,
               'author', jsonb_build_object(
                   'display_name', public.clinical_provenance_display_name(visible.created_by_user_id),
                   'is_me', visible.created_by_user_id = acting_user_id),
               'finalizer', case when visible.finalized_by_user_id is distinct from visible.created_by_user_id
                   then jsonb_build_object(
                       'display_name', public.clinical_provenance_display_name(visible.finalized_by_user_id),
                       'is_me', visible.finalized_by_user_id = acting_user_id)
                   end,
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
        p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id,
        p_clinical_encounter_id => encounter_record.id
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
$$;

revoke all privileges
on function public.view_appointment_professional_medical_history(uuid, uuid, integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.view_appointment_professional_medical_history(uuid, uuid, integer, timestamptz, uuid)
to authenticated;

-- ==================================================================
-- 5. Guardian history from the shared projection (SPEC-MED-005 BR-46).
--    Authorization, audit, ordering and cursor are those of
--    20260829120000_clinical_care.sql; the Attachment metadata is the
--    existing Guardian projection (clinical_attachment_metadata_for_entry,
--    non-workflow); the Clinic / Organization names those of
--    20260921160000_guardian_medical_history_provenance_names.sql.
-- ==================================================================

create or replace function public.view_guardian_pet_medical_history(
    p_pet_id uuid,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
            guardianship_record.id, null, null, null, null, null, null, null, null, null, null
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
               'encounter_started_at', visible.encounter_started_at,
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
        guardianship_record.id, null, null, null, null, null, null, null, null, null, null
    );
    return jsonb_build_object(
        'status', 'PERMITTED', 'payload', jsonb_build_object('entries', result_payload),
        'cursor', case when has_more then jsonb_build_object(
            'before_history_order_at', next_order_at, 'before_entry_id', next_entry_id
        ) else null end
    );
end;
$$;

revoke all privileges
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
to authenticated;

-- The superseded private Guardian chain has no remaining caller.
drop function public.slice13_view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid);
drop function public.decorate_guardian_medical_history_provenance_names(jsonb);
drop function public.slice12_view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid);

-- ==================================================================
-- 6. The legacy professional history read leaves the client surface.
-- ==================================================================

revoke execute
on function public.view_professional_pet_medical_history(uuid, uuid, uuid, uuid, integer, timestamptz, uuid)
from authenticated;

commit;

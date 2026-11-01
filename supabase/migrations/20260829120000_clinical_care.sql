begin;

-- ==================================================================
-- SLICE 12 — CLINICAL CARE
--
-- This migration introduces the Phase 1 Clinical Encounter, Draft /
-- Finalized Clinical Record Entry, material-contributor, Amendment,
-- Appointment completion/no-show, and protected medical-read models.
-- It deliberately excludes Slice 13 Clinical Attachments and generic
-- normal Care Authorization ending.
-- ==================================================================

-- ==================================================================
-- 1. Care Authorization purpose and deterministic-ending extension.
-- ==================================================================

alter table public.care_authorizations
drop constraint care_authorizations_purpose_check;

alter table public.care_authorizations
drop constraint care_authorizations_appointment_care_requires_appointment_check;

alter table public.care_authorizations
drop constraint care_authorizations_ended_reason_check;

alter table public.care_authorizations
add constraint care_authorizations_purpose_check
check (purpose in ('APPOINTMENT_CARE', 'CLINICAL_INTAKE'));

alter table public.care_authorizations
add constraint care_authorizations_purpose_appointment_shape_check
check (
    (purpose = 'APPOINTMENT_CARE' and appointment_id is not null)
    or (purpose = 'CLINICAL_INTAKE' and appointment_id is null)
);

alter table public.care_authorizations
add constraint care_authorizations_ended_reason_check
check (
    ended_reason is null
    or ended_reason in ('APPOINTMENT_CANCELLED', 'APPOINTMENT_NO_SHOW')
);

create or replace function public.assert_care_authorization_establishment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_organization_id uuid,
    p_granting_guardianship_id uuid,
    p_granted_at timestamptz,
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    clinic_organization_id uuid;
    guardianship_record public.guardianships%rowtype;
    appointment_record public.appointments%rowtype;
begin
    if p_granted_at is null or not isfinite(p_granted_at) then
        raise exception 'Care Authorization grant time must be finite'
            using errcode = '22023';
    end if;

    if p_granted_at > clock_timestamp() then
        raise exception 'Care Authorization cannot be granted at a future time'
            using errcode = '22023';
    end if;

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    if clinic_organization_id <> p_organization_id then
        raise exception 'Care Authorization Organization must match the target Clinic Organization'
            using errcode = '23514';
    end if;

    select guardianship.*
    into guardianship_record
    from public.guardianships as guardianship
    where guardianship.id = p_granting_guardianship_id
    for update;

    if not found then
        raise exception 'Granting Guardianship does not exist'
            using errcode = '23503';
    end if;

    if guardianship_record.pet_id <> p_pet_id then
        raise exception 'Granting Guardianship must concern the Care Authorization Pet'
            using errcode = '23514';
    end if;

    if guardianship_record.effective_end is not null then
        raise exception 'Care Authorization establishment requires a currently active granting Guardianship'
            using errcode = '23514';
    end if;

    if guardianship_record.effective_start > p_granted_at then
        raise exception 'Granting Guardianship must have started before the Care Authorization grant time'
            using errcode = '23514';
    end if;

    -- A non-null Appointment is the APPOINTMENT_CARE shape. The table
    -- constraint pins the purpose; this boundary preserves the deployed
    -- request provenance checks. A null Appointment is CLINICAL_INTAKE
    -- and intentionally has no scheduling/requester requirement.
    if p_appointment_id is not null then
        select appointment.*
        into appointment_record
        from public.appointments as appointment
        where appointment.id = p_appointment_id;

        if not found then
            raise exception 'Appointment-linked Care Authorization requires its Appointment'
                using errcode = '23503';
        end if;

        if appointment_record.pet_id <> p_pet_id then
            raise exception 'Appointment-linked Care Authorization must match the Appointment Pet'
                using errcode = '23514';
        end if;

        if appointment_record.clinic_id <> p_clinic_id then
            raise exception 'Appointment-linked Care Authorization must match the Appointment Clinic'
                using errcode = '23514';
        end if;

        if appointment_record.requesting_user_id <> guardianship_record.user_id then
            raise exception 'Appointment-linked Care Authorization granting Guardianship User must match the Appointment requesting User'
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_care_authorization_establishment(
    uuid, uuid, uuid, uuid, timestamptz, uuid
)
from public, anon, authenticated;

-- Non-raising current-professional resolver used only by structured protected
-- reads. An empty result is an ordinary authorization denial.
create function public.find_current_veterinarian_context_after_lock(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text,
    p_entitlement_identifier text default null
)
returns table (
    organization_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare resolved_organization_id uuid;
begin
    select clinic.organization_id into resolved_organization_id
    from public.clinics as clinic where clinic.id = p_clinic_id;
    if not found then return; end if;
    perform 1 from public.veterinary_organizations as organization_record
    where organization_record.id = resolved_organization_id for update;
    perform 1 from public.clinics as clinic
    where clinic.id = p_clinic_id and clinic.organization_id = resolved_organization_id for update;
    return query
    select resolved_organization_id, membership.id, responsibility_grant.id, clinic_assignment.id
    from public.organization_memberships as membership
    join public.organization_responsibility_grants as responsibility_grant
      on responsibility_grant.membership_id = membership.id
    join public.veterinarian_clinic_assignments as clinic_assignment
      on clinic_assignment.supporting_membership_id = membership.id
     and clinic_assignment.clinic_id = p_clinic_id
    join public.veterinarian_professional_profiles as professional_profile
      on professional_profile.id = clinic_assignment.professional_profile_id
     and professional_profile.user_id = p_user_id
    where membership.organization_id = resolved_organization_id
      and membership.user_id = p_user_id and membership.effective_end is null
      and responsibility_grant.responsibility = 'VETERINARIAN'
      and responsibility_grant.scope_type = 'ORGANIZATION'
      and responsibility_grant.clinic_id is null
      and responsibility_grant.effective_end is null
      and clinic_assignment.effective_end is null
      and public.user_has_clinic_capability(p_user_id, p_clinic_id, p_capability)
      and (
        p_entitlement_identifier is null
        or public.organization_has_professional_entitlement(
            resolved_organization_id, p_entitlement_identifier
        )
      )
    for update of membership, responsibility_grant, clinic_assignment;
end;
$$;

revoke all privileges
on function public.find_current_veterinarian_context_after_lock(uuid, uuid, text, text)
from public, anon, authenticated;

create function public.view_guardian_pet_medical_history(
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

    with page_rows as (
        select record_entry.*, encounter_row.pet_id, encounter_row.clinic_id,
               encounter_row.organization_id, encounter_row.started_at,
               encounter_row.lifecycle_state as encounter_lifecycle_state,
               encounter_row.concluded_at as encounter_concluded_at,
               encounter_row.responsible_veterinarian_clinic_assignment_id,
               coalesce(record_entry.clinical_event_at, encounter_row.started_at) as history_order_at,
               row_number() over (order by coalesce(record_entry.clinical_event_at, encounter_row.started_at) desc,
                                            record_entry.id desc) as page_number
        from public.clinical_record_entries as record_entry
        join public.clinical_encounters as encounter_row
          on encounter_row.id = record_entry.clinical_encounter_id
        where encounter_row.pet_id = p_pet_id and record_entry.lifecycle_state = 'FINALIZED'
          and (p_before_history_order_at is null or
               (coalesce(record_entry.clinical_event_at, encounter_row.started_at), record_entry.id)
                 < (p_before_history_order_at, p_before_entry_id))
        order by history_order_at desc, record_entry.id desc
        limit bounded_limit + 1
    ), visible_rows as (select * from page_rows where page_number <= bounded_limit)
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', visible_record.id,
               'clinical_encounter_id', visible_record.clinical_encounter_id,
               'clinic_id', visible_record.clinic_id,
               'organization_id', visible_record.organization_id,
               'encounter_started_at', visible_record.started_at,
               'encounter_lifecycle_state', visible_record.encounter_lifecycle_state,
               'encounter_concluded_at', visible_record.encounter_concluded_at,
               'responsible_veterinarian_clinic_assignment_id', visible_record.responsible_veterinarian_clinic_assignment_id,
               'created_by_user_id', visible_record.created_by_user_id,
               'creator_veterinarian_clinic_assignment_id', visible_record.creator_veterinarian_clinic_assignment_id,
               'created_at', visible_record.created_at,
               'draft_revision', visible_record.draft_revision,
               'last_modified_at', visible_record.last_modified_at,
               'clinical_content', visible_record.clinical_content,
               'category', visible_record.category,
               'other_category_context', visible_record.other_category_context,
               'clinical_event_at', visible_record.clinical_event_at,
               'history_order_at', visible_record.history_order_at,
               'finalized_at', visible_record.finalized_at,
               'finalized_by_user_id', visible_record.finalized_by_user_id,
               'finalizer_veterinarian_clinic_assignment_id', visible_record.finalizer_veterinarian_clinic_assignment_id,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'id', clinical_amendment.id, 'reason', clinical_amendment.reason,
                       'amendment_content', clinical_amendment.amendment_content,
                       'amending_user_id', clinical_amendment.amending_user_id,
                       'amending_veterinarian_clinic_assignment_id', clinical_amendment.amending_veterinarian_clinic_assignment_id,
                       'created_at', clinical_amendment.created_at
                   ) order by clinical_amendment.created_at, clinical_amendment.id)
                   from (
                       select amendment_source.*
                       from public.clinical_amendments as amendment_source
                       where amendment_source.original_clinical_record_entry_id = visible_record.id
                       order by amendment_source.created_at, amendment_source.id
                       limit 100
                   ) as clinical_amendment
               ), '[]'::jsonb),
               'amendment_count', (
                   select count(*) from public.clinical_amendments as amendment_count_source
                   where amendment_count_source.original_clinical_record_entry_id = visible_record.id
               ),
               'amendments_truncated', (
                   select count(*) > 100 from public.clinical_amendments as amendment_count_source
                   where amendment_count_source.original_clinical_record_entry_id = visible_record.id
               )
           ) order by visible_record.history_order_at desc, visible_record.id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page_rows),
           (array_agg(visible_record.history_order_at order by visible_record.history_order_at desc, visible_record.id desc))[bounded_limit],
           (array_agg(visible_record.id order by visible_record.history_order_at desc, visible_record.id desc))[bounded_limit]
    into result_payload, has_more, next_order_at, next_entry_id
    from visible_rows as visible_record;

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
from public, anon, authenticated;
grant execute
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
to authenticated;

-- ==================================================================
-- 2. Core clinical tables.
-- ==================================================================

create table public.clinical_encounters (
    id uuid not null default gen_random_uuid(),
    pet_id uuid not null,
    clinic_id uuid not null,
    organization_id uuid not null,
    responsible_veterinarian_clinic_assignment_id uuid not null,
    created_by_user_id uuid not null,
    care_authorization_id uuid not null,
    appointment_id uuid,
    started_at timestamptz not null,
    created_at timestamptz not null,
    lifecycle_state text not null default 'ACTIVE',
    concluded_at timestamptz,
    concluded_by_user_id uuid,
    concluding_veterinarian_clinic_assignment_id uuid,
    constraint clinical_encounters_pkey primary key (id),
    constraint clinical_encounters_pet_id_fkey
        foreign key (pet_id)
        references public.pets (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_organization_id_fkey
        foreign key (organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_responsible_vca_id_fkey
        foreign key (responsible_veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_created_by_user_id_fkey
        foreign key (created_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_care_authorization_id_fkey
        foreign key (care_authorization_id)
        references public.care_authorizations (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_concluded_by_user_id_fkey
        foreign key (concluded_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_concluding_vca_id_fkey
        foreign key (concluding_veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint clinical_encounters_lifecycle_state_check
        check (lifecycle_state in ('ACTIVE', 'CONCLUDED')),
    constraint clinical_encounters_started_at_finite_check
        check (isfinite(started_at)),
    constraint clinical_encounters_created_at_finite_check
        check (isfinite(created_at)),
    constraint clinical_encounters_concluded_at_finite_check
        check (concluded_at is null or isfinite(concluded_at)),
    constraint clinical_encounters_start_creation_order_check
        check (started_at <= created_at),
    constraint clinical_encounters_conclusion_order_check
        check (concluded_at is null or concluded_at >= started_at),
    constraint clinical_encounters_lifecycle_shape_check
        check (
            (
                lifecycle_state = 'ACTIVE'
                and concluded_at is null
                and concluded_by_user_id is null
                and concluding_veterinarian_clinic_assignment_id is null
            )
            or
            (
                lifecycle_state = 'CONCLUDED'
                and concluded_at is not null
                and concluded_by_user_id is not null
                and concluding_veterinarian_clinic_assignment_id is not null
            )
        )
);

create index clinical_encounters_care_authorization_idx
on public.clinical_encounters (care_authorization_id);

create index clinical_encounters_appointment_idx
on public.clinical_encounters (appointment_id)
where appointment_id is not null;

create index clinical_encounters_pet_history_idx
on public.clinical_encounters (pet_id, id);

create table public.clinical_record_entries (
    id uuid not null default gen_random_uuid(),
    clinical_encounter_id uuid not null,
    created_by_user_id uuid not null,
    creator_veterinarian_clinic_assignment_id uuid not null,
    created_at timestamptz not null,
    lifecycle_state text not null default 'DRAFT',
    clinical_content text,
    category text,
    other_category_context text,
    clinical_event_at timestamptz,
    draft_revision bigint not null default 0,
    last_modified_at timestamptz not null,
    finalized_at timestamptz,
    finalized_by_user_id uuid,
    finalizer_veterinarian_clinic_assignment_id uuid,
    constraint clinical_record_entries_pkey primary key (id),
    constraint clinical_record_entries_encounter_id_fkey
        foreign key (clinical_encounter_id)
        references public.clinical_encounters (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entries_created_by_user_id_fkey
        foreign key (created_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entries_creator_vca_id_fkey
        foreign key (creator_veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entries_finalized_by_user_id_fkey
        foreign key (finalized_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entries_finalizer_vca_id_fkey
        foreign key (finalizer_veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entries_lifecycle_state_check
        check (lifecycle_state in ('DRAFT', 'FINALIZED')),
    constraint clinical_record_entries_category_check
        check (
            category is null
            or category in (
                'EXAMINATION',
                'DIAGNOSIS',
                'TREATMENT',
                'PROCEDURE',
                'VACCINATION',
                'PRESCRIPTION',
                'LABORATORY_RESULT',
                'IMAGING_RESULT',
                'CLINICAL_NOTE',
                'OTHER'
            )
        ),
    constraint clinical_record_entries_content_check
        check (
            clinical_content is null
            or (
                clinical_content = btrim(clinical_content, E' \t\n\r\f\013')
                and clinical_content <> ''
            )
        ),
    constraint clinical_record_entries_other_context_check
        check (
            other_category_context is null
            or (
                other_category_context = btrim(other_category_context, E' \t\n\r\f\013')
                and other_category_context <> ''
            )
        ),
    constraint clinical_record_entries_category_context_shape_check
        check (category = 'OTHER' or other_category_context is null),
    constraint clinical_record_entries_created_at_finite_check
        check (isfinite(created_at)),
    constraint clinical_record_entries_last_modified_at_finite_check
        check (isfinite(last_modified_at)),
    constraint clinical_record_entries_clinical_event_at_finite_check
        check (clinical_event_at is null or isfinite(clinical_event_at)),
    constraint clinical_record_entries_finalized_at_finite_check
        check (finalized_at is null or isfinite(finalized_at)),
    constraint clinical_record_entries_modification_order_check
        check (last_modified_at >= created_at),
    constraint clinical_record_entries_finalization_order_check
        check (finalized_at is null or finalized_at >= created_at),
    constraint clinical_record_entries_revision_check
        check (draft_revision >= 0),
    constraint clinical_record_entries_lifecycle_shape_check
        check (
            (
                lifecycle_state = 'DRAFT'
                and finalized_at is null
                and finalized_by_user_id is null
                and finalizer_veterinarian_clinic_assignment_id is null
            )
            or
            (
                lifecycle_state = 'FINALIZED'
                and clinical_content is not null
                and category is not null
                and (category <> 'OTHER' or other_category_context is not null)
                and finalized_at is not null
                and finalized_by_user_id is not null
                and finalizer_veterinarian_clinic_assignment_id is not null
            )
        )
);

create index clinical_record_entries_encounter_work_idx
on public.clinical_record_entries (clinical_encounter_id, created_at, id);

create index clinical_record_entries_finalized_history_idx
on public.clinical_record_entries (
    clinical_encounter_id,
    clinical_event_at desc,
    id desc
)
where lifecycle_state = 'FINALIZED';

create table public.clinical_record_entry_contributors (
    clinical_record_entry_id uuid not null,
    veterinarian_clinic_assignment_id uuid not null,
    first_contributed_at timestamptz not null,
    constraint clinical_record_entry_contributors_pkey
        primary key (
            clinical_record_entry_id,
            veterinarian_clinic_assignment_id
        ),
    constraint clinical_record_entry_contributors_entry_id_fkey
        foreign key (clinical_record_entry_id)
        references public.clinical_record_entries (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entry_contributors_vca_id_fkey
        foreign key (veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint clinical_record_entry_contributors_time_finite_check
        check (isfinite(first_contributed_at))
);

create table public.clinical_amendments (
    id uuid not null default gen_random_uuid(),
    original_clinical_record_entry_id uuid not null,
    reason text not null,
    amendment_content text not null,
    amending_user_id uuid not null,
    amending_veterinarian_clinic_assignment_id uuid not null,
    created_at timestamptz not null,
    idempotency_key uuid not null,
    constraint clinical_amendments_pkey primary key (id),
    constraint clinical_amendments_original_entry_id_fkey
        foreign key (original_clinical_record_entry_id)
        references public.clinical_record_entries (id)
        on update no action
        on delete restrict,
    constraint clinical_amendments_amending_user_id_fkey
        foreign key (amending_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint clinical_amendments_amending_vca_id_fkey
        foreign key (amending_veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,
    constraint clinical_amendments_user_idempotency_key
        unique (amending_user_id, idempotency_key),
    constraint clinical_amendments_reason_check
        check (
            reason = btrim(reason, E' \t\n\r\f\013')
            and reason <> ''
        ),
    constraint clinical_amendments_content_check
        check (
            amendment_content = btrim(amendment_content, E' \t\n\r\f\013')
            and amendment_content <> ''
        ),
    constraint clinical_amendments_created_at_finite_check
        check (isfinite(created_at))
);

create index clinical_amendments_original_entry_history_idx
on public.clinical_amendments (
    original_clinical_record_entry_id,
    created_at,
    id
);

-- ==================================================================
-- 3. Shared professional-context and clinical integrity helpers.
-- ==================================================================

create function public.assert_vca_user_provider_context(
    p_veterinarian_clinic_assignment_id uuid,
    p_user_id uuid,
    p_clinic_id uuid,
    p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_user_id uuid;
    resolved_clinic_id uuid;
    resolved_organization_id uuid;
begin
    -- Immutable VCA -> supporting Membership -> User is the historical
    -- identity bridge. professional_profile.user_id is intentionally not
    -- used as provenance proof.
    select membership.user_id,
           clinic_assignment.clinic_id,
           membership.organization_id
    into resolved_user_id,
         resolved_clinic_id,
         resolved_organization_id
    from public.veterinarian_clinic_assignments as clinic_assignment
    join public.organization_memberships as membership
      on membership.id = clinic_assignment.supporting_membership_id
    where clinic_assignment.id = p_veterinarian_clinic_assignment_id;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    if resolved_user_id <> p_user_id then
        raise exception 'Veterinarian Clinic Assignment supporting Membership must belong to the recorded User'
            using errcode = '23514';
    end if;

    if resolved_clinic_id <> p_clinic_id
       or resolved_organization_id <> p_organization_id then
        raise exception 'Veterinarian Clinic Assignment must match the recorded Clinic and Organization context'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_vca_user_provider_context(uuid, uuid, uuid, uuid)
from public, anon, authenticated;

create function public.resolve_current_veterinarian_context_after_lock(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text,
    p_entitlement_identifier text default null
)
returns table (
    organization_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_organization_id uuid;
    resolved_membership_id uuid;
    resolved_responsibility_grant_id uuid;
    resolved_clinic_assignment_id uuid;
begin
    select clinic.organization_id
    into resolved_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
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

    select membership.id,
           responsibility_grant.id,
           clinic_assignment.id
    into resolved_membership_id,
         resolved_responsibility_grant_id,
         resolved_clinic_assignment_id
    from public.organization_memberships as membership
    join public.organization_responsibility_grants as responsibility_grant
      on responsibility_grant.membership_id = membership.id
    join public.veterinarian_clinic_assignments as clinic_assignment
      on clinic_assignment.supporting_membership_id = membership.id
     and clinic_assignment.clinic_id = p_clinic_id
    join public.veterinarian_professional_profiles as professional_profile
      on professional_profile.id = clinic_assignment.professional_profile_id
    where membership.organization_id = resolved_organization_id
      and membership.user_id = p_user_id
      and membership.effective_end is null
      and responsibility_grant.responsibility = 'VETERINARIAN'
      and responsibility_grant.scope_type = 'ORGANIZATION'
      and responsibility_grant.clinic_id is null
      and responsibility_grant.effective_end is null
      and clinic_assignment.effective_end is null
      -- Current Profile ownership is an independent current authorization
      -- requirement; it is not used as the historical VCA/User proof.
      and professional_profile.user_id = p_user_id
    for update of membership, responsibility_grant, clinic_assignment;

    if not found then
        raise exception 'Current exact-Clinic Veterinarian professional context is required'
            using errcode = '42501';
    end if;

    if not public.user_has_clinic_capability(
        p_user_id,
        p_clinic_id,
        p_capability
    ) then
        raise exception 'Applicable clinical or Appointment capability is required'
            using errcode = '42501';
    end if;

    if p_entitlement_identifier is not null
       and not public.organization_has_professional_entitlement(
           resolved_organization_id,
           p_entitlement_identifier
       ) then
        raise exception 'Applicable professional Entitlement is required'
            using errcode = '42501';
    end if;

    return query
    select resolved_organization_id,
           resolved_membership_id,
           resolved_responsibility_grant_id,
           resolved_clinic_assignment_id;
end;
$$;

revoke all privileges
on function public.resolve_current_veterinarian_context_after_lock(
    uuid, uuid, text, text
)
from public, anon, authenticated;

create function public.assert_clinical_encounter_establishment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_organization_id uuid,
    p_responsible_veterinarian_clinic_assignment_id uuid,
    p_created_by_user_id uuid,
    p_care_authorization_id uuid,
    p_appointment_id uuid,
    p_started_at timestamptz,
    p_created_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    clinic_organization_id uuid;
    care_auth_record public.care_authorizations%rowtype;
    appointment_record public.appointments%rowtype;
    confirmation_event_count integer;
    confirmation_effective_at timestamptz;
begin
    if p_started_at is null or not isfinite(p_started_at)
       or p_created_at is null or not isfinite(p_created_at) then
        raise exception 'Clinical Encounter timestamps must be finite'
            using errcode = '22023';
    end if;

    if p_started_at > clock_timestamp()
       or p_created_at > clock_timestamp() then
        raise exception 'Clinical Encounter cannot be established with a future timestamp'
            using errcode = '22023';
    end if;

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found or clinic_organization_id <> p_organization_id then
        raise exception 'Clinical Encounter Clinic and Organization must agree'
            using errcode = '23514';
    end if;

    select care_auth.*
    into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;

    if not found then
        raise exception 'Clinical Encounter requires its Care Authorization'
            using errcode = '23503';
    end if;

    if care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'A new Clinical Encounter requires an ACTIVE Care Authorization'
            using errcode = '23514';
    end if;

    if care_auth_record.pet_id <> p_pet_id
       or care_auth_record.clinic_id <> p_clinic_id
       or care_auth_record.organization_id <> p_organization_id then
        raise exception 'Clinical Encounter must match its Care Authorization Pet and provider context'
            using errcode = '23514';
    end if;

    if p_started_at < care_auth_record.granted_at then
        raise exception 'Clinical Encounter cannot begin before its Care Authorization was granted'
            using errcode = '23514';
    end if;

    perform public.assert_vca_user_provider_context(
        p_responsible_veterinarian_clinic_assignment_id,
        p_created_by_user_id,
        p_clinic_id,
        p_organization_id
    );

    if care_auth_record.purpose = 'CLINICAL_INTAKE' then
        if p_appointment_id is not null
           or care_auth_record.appointment_id is not null then
            raise exception 'CLINICAL_INTAKE Encounter must not reference an Appointment'
                using errcode = '23514';
        end if;

        return;
    end if;

    if care_auth_record.purpose <> 'APPOINTMENT_CARE'
       or p_appointment_id is null
       or care_auth_record.appointment_id is distinct from p_appointment_id then
        raise exception 'Appointment-backed Encounter requires the exact APPOINTMENT_CARE Authorization Appointment'
            using errcode = '23514';
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment-backed Clinical Encounter requires its Appointment'
            using errcode = '23503';
    end if;

    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Appointment-backed Clinical Encounter requires a CONFIRMED Appointment at establishment'
            using errcode = '23514';
    end if;

    if appointment_record.pet_id <> p_pet_id
       or appointment_record.clinic_id <> p_clinic_id then
        raise exception 'Clinical Encounter and Appointment Pet and Clinic must agree'
            using errcode = '23514';
    end if;

    select count(*), min(lifecycle_event.effective_at)
    into confirmation_event_count, confirmation_effective_at
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.from_state = 'REQUESTED'
      and lifecycle_event.to_state = 'CONFIRMED';

    if confirmation_event_count <> 1 then
        raise exception 'Appointment-backed Clinical Encounter requires exactly one confirmation Lifecycle Event'
            using errcode = '23514';
    end if;

    if p_started_at < confirmation_effective_at then
        raise exception 'Appointment-backed Clinical Encounter cannot begin before Appointment confirmation'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinical_encounter_establishment(
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz
)
from public, anon, authenticated;

create function public.enforce_clinical_encounter_establishment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.lifecycle_state <> 'ACTIVE'
       or new.concluded_at is not null
       or new.concluded_by_user_id is not null
       or new.concluding_veterinarian_clinic_assignment_id is not null then
        raise exception 'Clinical Encounter must be established as ACTIVE without conclusion facts'
            using errcode = '23514';
    end if;

    perform public.assert_clinical_encounter_establishment(
        new.pet_id,
        new.clinic_id,
        new.organization_id,
        new.responsible_veterinarian_clinic_assignment_id,
        new.created_by_user_id,
        new.care_authorization_id,
        new.appointment_id,
        new.started_at,
        new.created_at
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinical_encounter_establishment()
from public, anon, authenticated;

create trigger clinical_encounters_establishment
before insert on public.clinical_encounters
for each row
execute function public.enforce_clinical_encounter_establishment();

create function public.enforce_clinical_encounter_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Clinical Encounters cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.clinic_id is distinct from new.clinic_id
       or old.organization_id is distinct from new.organization_id
       or old.responsible_veterinarian_clinic_assignment_id is distinct from
          new.responsible_veterinarian_clinic_assignment_id
       or old.created_by_user_id is distinct from new.created_by_user_id
       or old.care_authorization_id is distinct from new.care_authorization_id
       or old.appointment_id is distinct from new.appointment_id
       or old.started_at is distinct from new.started_at
       or old.created_at is distinct from new.created_at then
        raise exception 'Clinical Encounter identity and care provenance are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state = 'CONCLUDED' then
        raise exception 'A concluded Clinical Encounter cannot be modified or reopened'
            using errcode = '23514';
    end if;

    if new.lifecycle_state <> 'CONCLUDED' then
        raise exception 'Clinical Encounter supports only ACTIVE to CONCLUDED transition'
            using errcode = '23514';
    end if;

    if new.concluded_at > clock_timestamp() then
        raise exception 'Clinical Encounter conclusion time cannot be in the future'
            using errcode = '22023';
    end if;

    perform public.assert_vca_user_provider_context(
        new.concluding_veterinarian_clinic_assignment_id,
        new.concluded_by_user_id,
        new.clinic_id,
        new.organization_id
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinical_encounter_immutability()
from public, anon, authenticated;

create trigger clinical_encounters_preserve_history
before update or delete on public.clinical_encounters
for each row
execute function public.enforce_clinical_encounter_immutability();

create function public.enforce_clinical_record_entry_integrity()
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
       or old.created_at is distinct from new.created_at then
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

create trigger clinical_record_entries_integrity
before insert or update or delete on public.clinical_record_entries
for each row
execute function public.enforce_clinical_record_entry_integrity();

create function public.enforce_clinical_record_entry_contributor_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    contributor_user_id uuid;
begin
    if tg_op in ('UPDATE', 'DELETE') then
        raise exception 'Clinical Record Entry contributors are append-only'
            using errcode = '23514';
    end if;

    select record_entry_row.*
    into record_entry
    from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = new.clinical_record_entry_id
    for update;

    if not found then
        raise exception 'Contributor attribution requires its Clinical Record Entry'
            using errcode = '23503';
    end if;

    if record_entry.lifecycle_state <> 'DRAFT' then
        raise exception 'Contributor attribution cannot be inserted after Entry finalization'
            using errcode = '23514';
    end if;

    if new.veterinarian_clinic_assignment_id =
       record_entry.creator_veterinarian_clinic_assignment_id then
        raise exception 'Original creator VCA must not be duplicated as a contributor'
            using errcode = '23514';
    end if;

    select encounter_record_row.*
    into encounter_record
    from public.clinical_encounters as encounter_record_row
    where encounter_record_row.id = record_entry.clinical_encounter_id;

    select membership.user_id
    into contributor_user_id
    from public.veterinarian_clinic_assignments as clinic_assignment
    join public.organization_memberships as membership
      on membership.id = clinic_assignment.supporting_membership_id
    where clinic_assignment.id = new.veterinarian_clinic_assignment_id;

    if not found then
        raise exception 'Contributor Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    perform public.assert_vca_user_provider_context(
        new.veterinarian_clinic_assignment_id,
        contributor_user_id,
        encounter_record.clinic_id,
        encounter_record.organization_id
    );

    if new.first_contributed_at < record_entry.created_at
       or new.first_contributed_at > clock_timestamp() then
        raise exception 'Contributor time must follow Entry creation and not be in the future'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinical_record_entry_contributor_integrity()
from public, anon, authenticated;

create trigger clinical_record_entry_contributors_integrity
before insert or update or delete on public.clinical_record_entry_contributors
for each row
execute function public.enforce_clinical_record_entry_contributor_integrity();

create function public.enforce_clinical_amendment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
begin
    if tg_op in ('UPDATE', 'DELETE') then
        raise exception 'Clinical Amendments are append-only'
            using errcode = '23514';
    end if;

    select record_entry_row.*
    into record_entry
    from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = new.original_clinical_record_entry_id
    for share;

    if not found then
        raise exception 'Clinical Amendment requires its original Clinical Record Entry'
            using errcode = '23503';
    end if;

    if record_entry.lifecycle_state <> 'FINALIZED' then
        raise exception 'Clinical Amendment requires an already FINALIZED original Entry'
            using errcode = '23514';
    end if;

    if new.created_at < record_entry.finalized_at
       or new.created_at > clock_timestamp() then
        raise exception 'Clinical Amendment time must follow finalization and not be in the future'
            using errcode = '23514';
    end if;

    select encounter_record_row.*
    into encounter_record
    from public.clinical_encounters as encounter_record_row
    where encounter_record_row.id = record_entry.clinical_encounter_id;

    perform public.assert_vca_user_provider_context(
        new.amending_veterinarian_clinic_assignment_id,
        new.amending_user_id,
        encounter_record.clinic_id,
        encounter_record.organization_id
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinical_amendment_integrity()
from public, anon, authenticated;

create trigger clinical_amendments_integrity
before insert or update or delete on public.clinical_amendments
for each row
execute function public.enforce_clinical_amendment_integrity();

-- ==================================================================
-- Appointment terminal states and their Clinical Encounter evidence.
-- ==================================================================

alter table public.appointments
drop constraint appointments_lifecycle_state_check;

alter table public.appointments
add constraint appointments_lifecycle_state_check
check (lifecycle_state in (
    'REQUESTED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW'
));

create or replace function public.enforce_appointment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointments cannot be deleted' using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.clinic_id is distinct from new.clinic_id
       or old.requesting_user_id is distinct from new.requesting_user_id
       or old.reason_for_visit is distinct from new.reason_for_visit
       or old.guardian_notes is distinct from new.guardian_notes
       or old.created_at is distinct from new.created_at then
        raise exception 'Appointment identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state = new.lifecycle_state then
        return new;
    end if;

    if not (
        (old.lifecycle_state = 'REQUESTED' and new.lifecycle_state = 'CONFIRMED')
        or (old.lifecycle_state in ('REQUESTED', 'CONFIRMED') and new.lifecycle_state = 'CANCELLED')
        or (old.lifecycle_state = 'CONFIRMED' and new.lifecycle_state in ('COMPLETED', 'NO_SHOW'))
    ) then
        raise exception 'Unsupported Appointment lifecycle transition'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_immutability()
from public, anon, authenticated;

alter table public.appointment_lifecycle_events
add column clinical_encounter_id uuid,
add constraint appointment_lifecycle_events_clinical_encounter_id_fkey
    foreign key (clinical_encounter_id)
    references public.clinical_encounters (id)
    on update no action
    on delete restrict;

alter table public.appointment_lifecycle_events
drop constraint appointment_lifecycle_events_transition_check;

alter table public.appointment_lifecycle_events
add constraint appointment_lifecycle_events_transition_check
check (
    (from_state = 'REQUESTED' and to_state = 'CONFIRMED')
    or (from_state in ('REQUESTED', 'CONFIRMED') and to_state = 'CANCELLED')
    or (from_state = 'CONFIRMED' and to_state in ('COMPLETED', 'NO_SHOW'))
),
add constraint appointment_lifecycle_events_terminal_actor_context_check
check (
    to_state not in ('COMPLETED', 'NO_SHOW')
    or (actor_context is not null and actor_context = 'CLINIC')
),
add constraint appointment_lifecycle_events_encounter_shape_check
check (
    (to_state = 'COMPLETED' and clinical_encounter_id is not null)
    or (to_state <> 'COMPLETED' and clinical_encounter_id is null)
);

drop index public.appointment_lifecycle_events_cancellation_key;

create unique index appointment_lifecycle_events_terminal_key
on public.appointment_lifecycle_events (appointment_id)
where to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW');

create or replace function public.assert_appointment_lifecycle_coherence(
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    requested_revision_count integer;
    confirmed_revision_count integer;
    confirmation_event_count integer;
    terminal_event_count integer;
    lifecycle_event_record public.appointment_lifecycle_events%rowtype;
    confirmation_effective_at timestamptz;
    latest_confirmed_scheduled_start_at timestamptz;
    encounter_record public.clinical_encounters%rowtype;
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
      and lifecycle_event.to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW');

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
      and lifecycle_event.to_state in ('CANCELLED', 'COMPLETED', 'NO_SHOW');

    if lifecycle_event_record.to_state <> appointment_record.lifecycle_state then
        raise exception 'Appointment % terminal Event must match its lifecycle state', p_appointment_id
            using errcode = '23514';
    end if;

    if lifecycle_event_record.from_state = 'REQUESTED' then
        if appointment_record.lifecycle_state <> 'CANCELLED' or confirmation_event_count <> 0 then
            raise exception 'Only cancellation may terminate an unconfirmed Appointment %', p_appointment_id
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
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = lifecycle_event_record.clinical_encounter_id;

        if not found
           or encounter_record.appointment_id is distinct from appointment_record.id
           or encounter_record.pet_id is distinct from appointment_record.pet_id
           or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
            raise exception 'COMPLETED Appointment % requires compatible Clinical Encounter evidence', p_appointment_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < encounter_record.started_at then
            raise exception 'COMPLETED Appointment % Event cannot precede its supporting Clinical Encounter', p_appointment_id
                using errcode = '23514';
        end if;
    else
        if lifecycle_event_record.clinical_encounter_id is not null then
            raise exception 'Only COMPLETED Appointment Events may reference a Clinical Encounter'
                using errcode = '23514';
        end if;
        if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW')
           and exists (
               select 1 from public.clinical_encounters as encounter_row
               where encounter_row.appointment_id = p_appointment_id
           ) then
            raise exception 'CANCELLED or NO_SHOW Appointment % cannot coexist with a Clinical Encounter', p_appointment_id
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
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_coherence(uuid)
from public, anon, authenticated;

create or replace function public.assert_appointment_lifecycle_event_provenance(
    p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    lifecycle_event_record public.appointment_lifecycle_events%rowtype;
    appointment_record public.appointments%rowtype;
    encounter_record public.clinical_encounters%rowtype;
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

    if lifecycle_event_record.to_state = 'COMPLETED' then
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = lifecycle_event_record.clinical_encounter_id;
        if not found
           or encounter_record.appointment_id is distinct from appointment_record.id
           or encounter_record.pet_id is distinct from appointment_record.pet_id
           or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
            raise exception 'Completion Event % requires compatible Clinical Encounter evidence', p_event_id
                using errcode = '23514';
        end if;

        if lifecycle_event_record.effective_at < encounter_record.started_at then
            raise exception 'Completion Event % cannot precede its supporting Clinical Encounter', p_event_id
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
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_event_provenance(uuid)
from public, anon, authenticated;

create or replace function public.assert_appointment_care_authorization_coherence(
    p_appointment_id uuid
)
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

    if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW')
       and linked_state = 'ACTIVE' then
        raise exception 'Cancelled or no-show Appointment % must not retain ACTIVE care authority', p_appointment_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_care_authorization_coherence(uuid)
from public, anon, authenticated;

create or replace function public.assert_care_authorization_appointment_coherence(
    p_care_authorization_id uuid
)
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
       or care_auth_record.ended_reason not in ('APPOINTMENT_CANCELLED', 'APPOINTMENT_NO_SHOW') then
        return;
    end if;

    expected_appointment_state := case care_auth_record.ended_reason
        when 'APPOINTMENT_CANCELLED' then 'CANCELLED'
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

revoke all privileges
on function public.assert_care_authorization_appointment_coherence(uuid)
from public, anon, authenticated;

create function public.assert_clinical_encounter_appointment_coherence(
    p_clinical_encounter_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    encounter_record public.clinical_encounters%rowtype;
    appointment_state text;
    completion_count integer;
begin
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id;
    if not found or encounter_record.appointment_id is null then return; end if;

    select appointment.lifecycle_state into appointment_state
    from public.appointments as appointment
    where appointment.id = encounter_record.appointment_id
    for update;

    if appointment_state not in ('CONFIRMED', 'COMPLETED') then
        raise exception 'Appointment-derived Clinical Encounter % requires a CONFIRMED or COMPLETED Appointment', p_clinical_encounter_id
            using errcode = '23514';
    end if;

    if appointment_state = 'COMPLETED' then
        select count(*) into completion_count
        from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = encounter_record.appointment_id
          and lifecycle_event.to_state = 'COMPLETED'
          and lifecycle_event.clinical_encounter_id = encounter_record.id;
        if completion_count <> 1 then
            raise exception 'Completed Appointment must identify Clinical Encounter % as its evidence', p_clinical_encounter_id
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinical_encounter_appointment_coherence(uuid)
from public, anon, authenticated;

create function public.enforce_clinical_encounter_appointment_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_clinical_encounter_appointment_coherence(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinical_encounter_appointment_coherence()
from public, anon, authenticated;

create constraint trigger clinical_encounters_enforce_appointment_coherence
after insert or update on public.clinical_encounters
deferrable initially deferred
for each row
execute function public.enforce_clinical_encounter_appointment_coherence();

-- Capability mapping approved by SPEC-ORG-005. Clinical capabilities
-- additionally require current professional context; Appointment completion
-- is available to current Veterinarians, while no-show remains administrative.
create or replace function public.user_has_clinic_capability(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(
        p_capability in (
            'CLINIC_MANAGE_LOCATION', 'CLINIC_MANAGE_PUBLIC_PROFILE',
            'CLINIC_MANAGE_PUBLICATION', 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
            'CLINIC_MANAGE_SERVICES', 'CLINIC_MANAGE_OPENING_HOURS',
            'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
            'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
            'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
            'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW',
            'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
        )
        and (
            exists (
                select 1
                from public.clinics as clinic
                join public.organization_memberships as membership
                  on membership.organization_id = clinic.organization_id
                join public.organization_responsibility_grants as responsibility_grant
                  on responsibility_grant.membership_id = membership.id
                where clinic.id = p_clinic_id
                  and membership.user_id = p_user_id
                  and membership.effective_end is null
                  and responsibility_grant.effective_end is null
                  and (
                    (
                      responsibility_grant.scope_type = 'ORGANIZATION'
                      and responsibility_grant.clinic_id is null
                      and responsibility_grant.responsibility in ('OWNER', 'ADMINISTRATOR')
                      and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                    )
                    or (
                      responsibility_grant.scope_type = 'CLINIC'
                      and responsibility_grant.clinic_id = p_clinic_id
                      and responsibility_grant.responsibility = 'ADMINISTRATOR'
                      and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                    )
                    or (
                      responsibility_grant.responsibility = 'RECEPTIONIST'
                      and p_capability in (
                        'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
                        'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
                        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
                        'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW'
                      )
                      and (
                        (responsibility_grant.scope_type = 'ORGANIZATION' and responsibility_grant.clinic_id is null)
                        or (responsibility_grant.scope_type = 'CLINIC' and responsibility_grant.clinic_id = p_clinic_id)
                      )
                    )
                  )
            )
            or (
                p_capability in (
                    'APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE',
                    'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
                )
                and exists (
                    select 1
                    from public.clinics as clinic
                    join public.organization_memberships as membership
                      on membership.organization_id = clinic.organization_id
                    join public.organization_responsibility_grants as responsibility_grant
                      on responsibility_grant.membership_id = membership.id
                    join public.veterinarian_clinic_assignments as clinic_assignment
                      on clinic_assignment.supporting_membership_id = membership.id
                     and clinic_assignment.clinic_id = p_clinic_id
                    join public.veterinarian_professional_profiles as profile
                      on profile.id = clinic_assignment.professional_profile_id
                     and profile.user_id = p_user_id
                    where clinic.id = p_clinic_id
                      and membership.user_id = p_user_id
                      and membership.effective_end is null
                      and responsibility_grant.effective_end is null
                      and responsibility_grant.membership_id = membership.id
                      and responsibility_grant.responsibility = 'VETERINARIAN'
                      and responsibility_grant.scope_type = 'ORGANIZATION'
                      and responsibility_grant.clinic_id is null
                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
                )
            )
        ), false
    )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- Slice 12 terminal Appointments preserve their latest CONFIRMED schedule.
-- CANCELLED deliberately retains the deployed Slice 9/10 selection behavior.
create or replace function public.get_pet_appointments(
    p_pet_id uuid
)
returns table (
    id uuid,
    clinic_id uuid,
    requesting_user_id uuid,
    reason_for_visit text,
    guardian_notes text,
    lifecycle_state text,
    created_at timestamptz,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text
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

    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    return query
    select
        appointment.id,
        appointment.clinic_id,
        appointment.requesting_user_id,
        appointment.reason_for_visit,
        appointment.guardian_notes,
        appointment.lifecycle_state,
        appointment.created_at,
        current_revision.scheduled_start_at,
        current_revision.scheduled_end_at,
        current_revision.establishment_timezone_name,
        current_assignment.veterinarian_clinic_assignment_id,
        pending_proposal.id,
        pending_proposal.state,
        pending_proposal.proposing_context,
        pending_proposal.proposed_start_at,
        pending_proposal.proposed_end_at,
        pending_proposal.proposed_timezone_name,
        pending_proposal.reason
    from public.appointments as appointment
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at, revision.establishment_timezone_name
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
          and revision.revision_context = case
              when appointment.lifecycle_state in ('CONFIRMED', 'COMPLETED', 'NO_SHOW') then 'CONFIRMED'
              else 'REQUESTED'
          end
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    left join public.appointment_reschedule_proposals as pending_proposal
      on pending_proposal.appointment_id = appointment.id
     and pending_proposal.state = 'PENDING'
     and public.appointment_reschedule_proposal_is_actionable(
         pending_proposal.id,
         statement_timestamp()
     )
    where appointment.pet_id = p_pet_id
    order by appointment.created_at, appointment.id;
end;
$$;

revoke all privileges
on function public.get_pet_appointments(uuid)
from public, anon, authenticated;

grant execute
on function public.get_pet_appointments(uuid)
to authenticated;

create or replace function public.get_clinic_appointment_schedule(
    p_clinic_id uuid
)
returns table (
    id uuid,
    pet_id uuid,
    requesting_user_id uuid,
    reason_for_visit text,
    guardian_notes text,
    lifecycle_state text,
    created_at timestamptz,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    current_veterinarian_clinic_assignment_id uuid,
    pending_reschedule_proposal_id uuid,
    pending_reschedule_proposal_state text,
    pending_reschedule_proposing_context text,
    pending_reschedule_proposed_start_at timestamptz,
    pending_reschedule_proposed_end_at timestamptz,
    pending_reschedule_proposed_timezone_name text,
    pending_reschedule_reason text
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
    select
        appointment.id,
        appointment.pet_id,
        appointment.requesting_user_id,
        appointment.reason_for_visit,
        appointment.guardian_notes,
        appointment.lifecycle_state,
        appointment.created_at,
        current_revision.scheduled_start_at,
        current_revision.scheduled_end_at,
        current_revision.establishment_timezone_name,
        current_assignment.veterinarian_clinic_assignment_id,
        pending_proposal.id,
        pending_proposal.state,
        pending_proposal.proposing_context,
        pending_proposal.proposed_start_at,
        pending_proposal.proposed_end_at,
        pending_proposal.proposed_timezone_name,
        pending_proposal.reason
    from public.appointments as appointment
    left join lateral (
        select revision.scheduled_start_at, revision.scheduled_end_at, revision.establishment_timezone_name
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = appointment.id
          and revision.revision_context = case
              when appointment.lifecycle_state in ('CONFIRMED', 'COMPLETED', 'NO_SHOW') then 'CONFIRMED'
              else 'REQUESTED'
          end
        order by revision.revision_sequence desc
        limit 1
    ) as current_revision on true
    left join public.appointment_veterinarian_assignments as current_assignment
      on current_assignment.appointment_id = appointment.id
     and current_assignment.effective_end is null
    left join public.appointment_reschedule_proposals as pending_proposal
      on pending_proposal.appointment_id = appointment.id
     and pending_proposal.state = 'PENDING'
     and public.appointment_reschedule_proposal_is_actionable(
         pending_proposal.id,
         statement_timestamp()
     )
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
-- Guardian Care Authorization operations and narrow ID projections.
-- ==================================================================

create function public.grant_pet_care_authorization(
    p_pet_id uuid,
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    guardianship_record public.guardianships%rowtype;
    operation_timestamp timestamptz;
    created_care_authorization_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject' using errcode = '28000';
    end if;

    if not exists (
        select 1 from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required' using errcode = '42501';
    end if;

    select clinic.organization_id into target_organization_id
    from public.clinics as clinic where clinic.id = p_clinic_id;
    if not found then
        raise exception 'Clinic does not exist' using errcode = '23503';
    end if;

    perform 1 from public.veterinary_organizations as organization_record
    where organization_record.id = target_organization_id for update;
    perform 1 from public.clinics as clinic
    where clinic.id = p_clinic_id and clinic.organization_id = target_organization_id for update;

    select guardianship.* into guardianship_record
    from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;
    if not found then
        raise exception 'Current Guardianship of the Pet is required' using errcode = '42501';
    end if;

    operation_timestamp := clock_timestamp();
    insert into public.care_authorizations (
        pet_id, clinic_id, organization_id, granting_guardianship_id,
        granted_at, purpose, appointment_id, lifecycle_state
    ) values (
        p_pet_id, p_clinic_id, target_organization_id, guardianship_record.id,
        operation_timestamp, 'CLINICAL_INTAKE', null, 'ACTIVE'
    ) returning id into created_care_authorization_id;

    return created_care_authorization_id;
end;
$$;

revoke all privileges on function public.grant_pet_care_authorization(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.grant_pet_care_authorization(uuid, uuid) to authenticated;

create function public.revoke_care_authorization_after_guardianship_lock(
    p_care_authorization_id uuid,
    p_acting_user_id uuid,
    p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_pet_id uuid;
    care_auth_record public.care_authorizations%rowtype;
    normalized_reason text;
begin
    select care_auth.pet_id into target_pet_id
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;
    if not found then
        raise exception 'Care Authorization does not exist' using errcode = '23503';
    end if;

    perform 1 from public.guardianships as guardianship
    where guardianship.pet_id = target_pet_id
      and guardianship.user_id = p_acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;
    if not found then
        raise exception 'Current Guardianship of the Pet is required' using errcode = '42501';
    end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id
    for update;
    if care_auth_record.pet_id is distinct from target_pet_id then
        raise exception 'Care Authorization Pet changed during revocation' using errcode = '40001';
    end if;
    if care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Only an ACTIVE Care Authorization may be revoked' using errcode = '23514';
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    update public.care_authorizations
    set lifecycle_state = 'REVOKED',
        revoked_at = clock_timestamp(),
        revoking_user_id = p_acting_user_id,
        revocation_reason = normalized_reason
    where id = p_care_authorization_id;
    return p_care_authorization_id;
end;
$$;

revoke all privileges
on function public.revoke_care_authorization_after_guardianship_lock(uuid, uuid, text)
from public, anon, authenticated;

create function public.revoke_pet_care_authorization(
    p_care_authorization_id uuid,
    p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject' using errcode = '28000';
    end if;
    return public.revoke_care_authorization_after_guardianship_lock(
        p_care_authorization_id, acting_user_id, p_reason
    );
end;
$$;

revoke all privileges on function public.revoke_pet_care_authorization(uuid, text)
from public, anon, authenticated;
grant execute on function public.revoke_pet_care_authorization(uuid, text) to authenticated;

create or replace function public.revoke_appointment_care_authorization(
    p_appointment_id uuid,
    p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_care_authorization_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject' using errcode = '28000';
    end if;
    perform 1 from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then
        raise exception 'Appointment does not exist' using errcode = '23503';
    end if;
    select care_auth.id into target_care_authorization_id
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id
      and care_auth.purpose = 'APPOINTMENT_CARE';
    if not found then
        raise exception 'Appointment-derived Care Authorization does not exist' using errcode = '23503';
    end if;
    perform public.revoke_care_authorization_after_guardianship_lock(
        target_care_authorization_id, acting_user_id, p_reason
    );
    return target_care_authorization_id;
end;
$$;

revoke all privileges on function public.revoke_appointment_care_authorization(uuid, text)
from public, anon, authenticated;
grant execute on function public.revoke_appointment_care_authorization(uuid, text) to authenticated;

create function public.get_guardian_pet_active_care_authorizations(p_pet_id uuid)
returns table (
    id uuid, clinic_id uuid, organization_id uuid, purpose text,
    granted_at timestamptz, appointment_id uuid, lifecycle_state text
)
language plpgsql
security definer
set search_path = ''
as $$
declare acting_user_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    perform 1 from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
    for share;
    if not found then raise exception 'Current Guardianship of the Pet is required' using errcode = '42501'; end if;
    return query select care_auth.id, care_auth.clinic_id, care_auth.organization_id,
        care_auth.purpose, care_auth.granted_at, care_auth.appointment_id, care_auth.lifecycle_state
    from public.care_authorizations as care_auth
    where care_auth.pet_id = p_pet_id and care_auth.lifecycle_state = 'ACTIVE'
    order by care_auth.granted_at desc, care_auth.id desc limit 100;
end;
$$;

revoke all privileges on function public.get_guardian_pet_active_care_authorizations(uuid)
from public, anon, authenticated;
grant execute on function public.get_guardian_pet_active_care_authorizations(uuid) to authenticated;

create function public.get_professional_pet_active_care_authorizations(
    p_pet_id uuid,
    p_clinic_id uuid
)
returns table (
    id uuid, clinic_id uuid, organization_id uuid, purpose text,
    granted_at timestamptz, appointment_id uuid, lifecycle_state text
)
language plpgsql
security definer
set search_path = ''
as $$
declare acting_user_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    perform 1 from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, p_clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
    );
    return query select care_auth.id, care_auth.clinic_id, care_auth.organization_id,
        care_auth.purpose, care_auth.granted_at, care_auth.appointment_id, care_auth.lifecycle_state
    from public.care_authorizations as care_auth
    where care_auth.pet_id = p_pet_id and care_auth.clinic_id = p_clinic_id
      and care_auth.lifecycle_state = 'ACTIVE'
    order by care_auth.granted_at desc, care_auth.id desc limit 100;
end;
$$;

revoke all privileges on function public.get_professional_pet_active_care_authorizations(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_professional_pet_active_care_authorizations(uuid, uuid) to authenticated;

-- ==================================================================
-- Clinical mutation boundary.
-- ==================================================================

create function public.create_clinical_encounter(
    p_care_authorization_id uuid,
    p_started_at timestamptz,
    p_appointment_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    operation_timestamp timestamptz;
    created_clinical_encounter_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;
    if not found then raise exception 'Care Authorization does not exist' using errcode = '23503'; end if;

    select * into professional_context
    from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, care_auth_record.clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
    );

    if p_appointment_id is not null then
        perform 1 from public.appointments as appointment
        where appointment.id = p_appointment_id for update;
        if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id
    for update;

    if care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Clinical Encounter requires an ACTIVE Care Authorization' using errcode = '23514';
    end if;
    if care_auth_record.appointment_id is distinct from p_appointment_id then
        raise exception 'Encounter Appointment must exactly match the Care Authorization' using errcode = '23514';
    end if;
    if exists (
        select 1 from public.clinical_encounters as encounter_row
        where encounter_row.care_authorization_id = p_care_authorization_id
    ) then
        raise exception 'This Care Authorization already established a Clinical Encounter' using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();
    if p_started_at is null or not isfinite(p_started_at) or p_started_at > operation_timestamp then
        raise exception 'Encounter start must be finite and not in the future' using errcode = '22023';
    end if;

    insert into public.clinical_encounters (
        pet_id, clinic_id, organization_id,
        responsible_veterinarian_clinic_assignment_id, created_by_user_id,
        care_authorization_id, appointment_id, started_at, created_at, lifecycle_state
    ) values (
        care_auth_record.pet_id, care_auth_record.clinic_id, care_auth_record.organization_id,
        professional_context.veterinarian_clinic_assignment_id, acting_user_id,
        care_auth_record.id, p_appointment_id, p_started_at, operation_timestamp, 'ACTIVE'
    ) returning id into created_clinical_encounter_id;
    return created_clinical_encounter_id;
end;
$$;

revoke all privileges on function public.create_clinical_encounter(uuid, timestamptz, uuid)
from public, anon, authenticated;
grant execute on function public.create_clinical_encounter(uuid, timestamptz, uuid) to authenticated;

create function public.create_draft_clinical_record_entry(
    p_clinical_encounter_id uuid,
    p_clinical_content text default null,
    p_category text default null,
    p_other_category_context text default null,
    p_clinical_event_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    operation_timestamp timestamptz;
    created_entry_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id;
    if not found then raise exception 'Clinical Encounter does not exist' using errcode = '23503'; end if;

    select * into professional_context
    from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id for update;

    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care Draft creation requires the existing Care Authorization to remain ACTIVE'
            using errcode = '42501';
    end if;

    if professional_context.veterinarian_clinic_assignment_id is distinct from
       encounter_record.responsible_veterinarian_clinic_assignment_id then
        raise exception 'Only the responsible Veterinarian may create a Phase-1 Draft' using errcode = '42501';
    end if;

    operation_timestamp := clock_timestamp();
    insert into public.clinical_record_entries (
        clinical_encounter_id, created_by_user_id,
        creator_veterinarian_clinic_assignment_id, created_at, lifecycle_state,
        clinical_content, category, other_category_context, clinical_event_at,
        draft_revision, last_modified_at
    ) values (
        encounter_record.id, acting_user_id,
        professional_context.veterinarian_clinic_assignment_id, operation_timestamp, 'DRAFT',
        nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), ''), p_category,
        nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), ''), p_clinical_event_at,
        0, operation_timestamp
    ) returning id into created_entry_id;
    return created_entry_id;
end;
$$;

revoke all privileges on function public.create_draft_clinical_record_entry(uuid, text, text, text, timestamptz)
from public, anon, authenticated;
grant execute on function public.create_draft_clinical_record_entry(uuid, text, text, text, timestamptz) to authenticated;

create function public.update_draft_clinical_record_entry(
    p_entry_id uuid,
    p_expected_draft_revision bigint,
    p_clinical_content text,
    p_category text,
    p_other_category_context text,
    p_clinical_event_at timestamptz
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    normalized_content text;
    normalized_other_context text;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id;
    if not found then raise exception 'Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;

    select * into professional_context
    from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id for update;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id for update;

    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care Draft update requires the existing Care Authorization to remain ACTIVE'
            using errcode = '42501';
    end if;

    if record_entry.lifecycle_state <> 'DRAFT' then raise exception 'Only a DRAFT Entry may be updated' using errcode = '23514'; end if;
    if record_entry.draft_revision <> p_expected_draft_revision then raise exception 'Stale Draft revision' using errcode = '40001'; end if;
    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');

    if record_entry.clinical_content is not distinct from normalized_content
       and record_entry.category is not distinct from p_category
       and record_entry.other_category_context is not distinct from normalized_other_context
       and record_entry.clinical_event_at is not distinct from p_clinical_event_at then
        return record_entry.draft_revision;
    end if;

    operation_timestamp := clock_timestamp();
    update public.clinical_record_entries
    set clinical_content = normalized_content, category = p_category,
        other_category_context = normalized_other_context,
        clinical_event_at = p_clinical_event_at,
        draft_revision = record_entry.draft_revision + 1,
        last_modified_at = operation_timestamp
    where id = p_entry_id;

    if professional_context.veterinarian_clinic_assignment_id is distinct from
       record_entry.creator_veterinarian_clinic_assignment_id then
        insert into public.clinical_record_entry_contributors (
            clinical_record_entry_id, veterinarian_clinic_assignment_id, first_contributed_at
        ) values (
            p_entry_id, professional_context.veterinarian_clinic_assignment_id, operation_timestamp
        ) on conflict do nothing;
    end if;
    return record_entry.draft_revision + 1;
end;
$$;

revoke all privileges on function public.update_draft_clinical_record_entry(uuid, bigint, text, text, text, timestamptz)
from public, anon, authenticated;
grant execute on function public.update_draft_clinical_record_entry(uuid, bigint, text, text, text, timestamptz) to authenticated;

create function public.finalize_clinical_record_entry(
    p_entry_id uuid,
    p_expected_draft_revision bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id;
    if not found then raise exception 'Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id for update;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id for update;
    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care finalization requires the existing Care Authorization to remain ACTIVE'
            using errcode = '42501';
    end if;
    if record_entry.lifecycle_state <> 'DRAFT' then raise exception 'Only a DRAFT Entry may be finalized' using errcode = '23514'; end if;
    if record_entry.draft_revision <> p_expected_draft_revision then raise exception 'Stale Draft revision' using errcode = '40001'; end if;
    if record_entry.clinical_content is null or record_entry.category is null
       or (record_entry.category = 'OTHER' and record_entry.other_category_context is null) then
        raise exception 'Clinical Record Entry is not finalizable' using errcode = '23514';
    end if;
    update public.clinical_record_entries
    set lifecycle_state = 'FINALIZED', finalized_at = clock_timestamp(),
        finalized_by_user_id = acting_user_id,
        finalizer_veterinarian_clinic_assignment_id = professional_context.veterinarian_clinic_assignment_id
    where id = p_entry_id;
    return p_entry_id;
end;
$$;

revoke all privileges on function public.finalize_clinical_record_entry(uuid, bigint)
from public, anon, authenticated;
grant execute on function public.finalize_clinical_record_entry(uuid, bigint) to authenticated;

create function public.create_clinical_amendment(
    p_original_clinical_record_entry_id uuid,
    p_reason text,
    p_amendment_content text,
    p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
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
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', 'CLINICAL_DOCUMENTATION'
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
$$;

revoke all privileges on function public.create_clinical_amendment(uuid, text, text, uuid)
from public, anon, authenticated;
grant execute on function public.create_clinical_amendment(uuid, text, text, uuid) to authenticated;

create function public.conclude_clinical_encounter(p_clinical_encounter_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    encounter_record public.clinical_encounters%rowtype;
    professional_context record;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id;
    if not found then raise exception 'Clinical Encounter does not exist' using errcode = '23503'; end if;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_CARE', null
    );
    perform 1 from public.care_authorizations as care_auth where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id for update;
    if encounter_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Only an ACTIVE Clinical Encounter may be concluded' using errcode = '23514';
    end if;
    update public.clinical_encounters
    set lifecycle_state = 'CONCLUDED', concluded_at = clock_timestamp(),
        concluded_by_user_id = acting_user_id,
        concluding_veterinarian_clinic_assignment_id = professional_context.veterinarian_clinic_assignment_id
    where id = p_clinical_encounter_id;
    return p_clinical_encounter_id;
end;
$$;

revoke all privileges on function public.conclude_clinical_encounter(uuid)
from public, anon, authenticated;
grant execute on function public.conclude_clinical_encounter(uuid) to authenticated;

-- ==================================================================
-- Appointment terminal workflows.
-- ==================================================================

create function public.complete_appointment(
    p_appointment_id uuid,
    p_clinical_encounter_id uuid
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
    encounter_record public.clinical_encounters%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select appointment.clinic_id into appointment_clinic_id from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, appointment_clinic_id, 'APPOINTMENT_COMPLETE'
    );
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may be completed' using errcode = '23514';
    end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = p_clinical_encounter_id for update;
    if not found
       or encounter_record.appointment_id is distinct from appointment_record.id
       or encounter_record.pet_id is distinct from appointment_record.pet_id
       or encounter_record.clinic_id is distinct from appointment_record.clinic_id then
        raise exception 'Completion requires compatible Clinical Encounter evidence' using errcode = '23514';
    end if;
    operation_timestamp := clock_timestamp();
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at, clinical_encounter_id
    ) values (
        p_appointment_id, 'CONFIRMED', 'COMPLETED', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp, p_clinical_encounter_id
    );
    update public.appointments set lifecycle_state = 'COMPLETED' where id = p_appointment_id;
    return p_appointment_id;
end;
$$;

revoke all privileges on function public.complete_appointment(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.complete_appointment(uuid, uuid) to authenticated;

create function public.mark_appointment_no_show(p_appointment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_record public.appointments%rowtype;
    latest_scheduled_start_at timestamptz;
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select appointment.clinic_id into appointment_clinic_id from public.appointments as appointment
    where appointment.id = p_appointment_id;
    if not found then raise exception 'Appointment does not exist' using errcode = '23503'; end if;
    perform public.assert_clinic_capability_after_lock(
        acting_user_id, appointment_clinic_id, 'APPOINTMENT_MARK_NO_SHOW'
    );
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;
    if appointment_record.lifecycle_state <> 'CONFIRMED' then
        raise exception 'Only a CONFIRMED Appointment may be marked no-show' using errcode = '23514';
    end if;
    if exists (select 1 from public.clinical_encounters as encounter_row
               where encounter_row.appointment_id = p_appointment_id) then
        raise exception 'Appointment with a Clinical Encounter cannot be marked no-show' using errcode = '23514';
    end if;
    select revision.scheduled_start_at into latest_scheduled_start_at
    from public.appointment_schedule_revisions as revision
    where revision.appointment_id = p_appointment_id
      and revision.revision_context = 'CONFIRMED'
    order by revision.revision_sequence desc limit 1;
    operation_timestamp := clock_timestamp();
    if not found or latest_scheduled_start_at > operation_timestamp then
        raise exception 'Appointment cannot be marked no-show before its confirmed scheduled start' using errcode = '23514';
    end if;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id for update;
    if not found then raise exception 'Appointment has no Care Authorization' using errcode = '23514'; end if;
    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at, clinical_encounter_id
    ) values (
        p_appointment_id, 'CONFIRMED', 'NO_SHOW', acting_user_id, 'CLINIC',
        null, operation_timestamp, operation_timestamp, null
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
$$;

revoke all privileges on function public.mark_appointment_no_show(uuid)
from public, anon, authenticated;
grant execute on function public.mark_appointment_no_show(uuid) to authenticated;

create or replace function public.cancel_appointment(
    p_appointment_id uuid,
    p_cancelling_context text,
    p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_pet_id uuid;
    normalized_reason text;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_cancelling_context is null or p_cancelling_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Cancelling context must be GUARDIAN or CLINIC' using errcode = '22023';
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
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    if p_cancelling_context = 'CLINIC' and normalized_reason is null then
        raise exception 'A meaningful reason is required for a Clinic cancellation' using errcode = '22023';
    end if;
    select appointment.* into appointment_record from public.appointments as appointment
    where appointment.id = p_appointment_id for update;
    if appointment_record.lifecycle_state not in ('REQUESTED', 'CONFIRMED') then
        raise exception 'Only a REQUESTED or CONFIRMED Appointment may be cancelled' using errcode = '23514';
    end if;
    if exists (select 1 from public.clinical_encounters as encounter_row
               where encounter_row.appointment_id = p_appointment_id) then
        raise exception 'Appointment with a Clinical Encounter cannot be cancelled' using errcode = '23514';
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
        reason, effective_at, recorded_at, clinical_encounter_id
    ) values (
        p_appointment_id, appointment_record.lifecycle_state, 'CANCELLED',
        acting_user_id, p_cancelling_context, normalized_reason,
        operation_timestamp, operation_timestamp, null
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
$$;

revoke all privileges on function public.cancel_appointment(uuid, text, text)
from public, anon, authenticated;
grant execute on function public.cancel_appointment(uuid, text, text) to authenticated;

-- ==================================================================
-- Typed Medical Access Audit references and trusted capture extension.
-- ==================================================================

alter table public.medical_access_audit_events
add column clinical_encounter_id uuid,
add column clinical_record_entry_id uuid,
add column clinical_amendment_id uuid,
add constraint medical_access_audit_events_clinical_encounter_id_fkey
    foreign key (clinical_encounter_id) references public.clinical_encounters (id)
    on update no action on delete restrict,
add constraint medical_access_audit_events_clinical_record_entry_id_fkey
    foreign key (clinical_record_entry_id) references public.clinical_record_entries (id)
    on update no action on delete restrict,
add constraint medical_access_audit_events_clinical_amendment_id_fkey
    foreign key (clinical_amendment_id) references public.clinical_amendments (id)
    on update no action on delete restrict;

create function public.assert_medical_access_audit_typed_resource_coherence(
    p_pet_id uuid,
    p_operation text,
    p_care_authorization_id uuid,
    p_appointment_id uuid,
    p_clinical_encounter_id uuid,
    p_clinical_record_entry_id uuid,
    p_clinical_amendment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    encounter_pet_id uuid;
    encounter_care_authorization_id uuid;
    encounter_appointment_id uuid;
    record_entry_encounter_id uuid;
    amendment_original_entry_id uuid;
begin
    if p_operation = 'VIEW_CLINICAL_RECORD_ENTRY'
       and (
           p_clinical_encounter_id is null
           or p_clinical_record_entry_id is null
       ) then
        raise exception 'VIEW_CLINICAL_RECORD_ENTRY Audit Event requires typed Encounter and Entry references'
            using errcode = '23514';
    end if;

    if p_clinical_encounter_id is not null then
        select encounter_row.pet_id,
               encounter_row.care_authorization_id,
               encounter_row.appointment_id
        into encounter_pet_id,
             encounter_care_authorization_id,
             encounter_appointment_id
        from public.clinical_encounters as encounter_row
        where encounter_row.id = p_clinical_encounter_id;
        if not found then raise exception 'Referenced Clinical Encounter does not exist' using errcode = '23503'; end if;
        if encounter_pet_id is distinct from p_pet_id then
            raise exception 'Audit Event Clinical Encounter must concern its Pet' using errcode = '23514';
        end if;
        if p_care_authorization_id is not null
           and encounter_care_authorization_id is distinct from p_care_authorization_id then
            raise exception 'Audit Event Clinical Encounter must match its supplied Care Authorization'
                using errcode = '23514';
        end if;
        if p_appointment_id is not null
           and encounter_appointment_id is distinct from p_appointment_id then
            raise exception 'Audit Event Clinical Encounter must match its supplied Appointment'
                using errcode = '23514';
        end if;
    end if;

    if p_clinical_record_entry_id is not null then
        if p_clinical_encounter_id is null then
            raise exception 'Typed Entry audit provenance requires its Clinical Encounter' using errcode = '23514';
        end if;
        select record_entry.clinical_encounter_id into record_entry_encounter_id
        from public.clinical_record_entries as record_entry
        where record_entry.id = p_clinical_record_entry_id;
        if not found then raise exception 'Referenced Clinical Record Entry does not exist' using errcode = '23503'; end if;
        if record_entry_encounter_id is distinct from p_clinical_encounter_id then
            raise exception 'Audit Event Entry must belong to its supplied Encounter' using errcode = '23514';
        end if;
    end if;

    if p_clinical_amendment_id is not null then
        if p_clinical_record_entry_id is null then
            raise exception 'Typed Amendment audit provenance requires its original Entry' using errcode = '23514';
        end if;
        select clinical_amendment.original_clinical_record_entry_id into amendment_original_entry_id
        from public.clinical_amendments as clinical_amendment
        where clinical_amendment.id = p_clinical_amendment_id;
        if not found then raise exception 'Referenced Clinical Amendment does not exist' using errcode = '23503'; end if;
        if amendment_original_entry_id is distinct from p_clinical_record_entry_id then
            raise exception 'Audit Event Amendment must belong to its supplied original Entry' using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_medical_access_audit_typed_resource_coherence(
    uuid, text, uuid, uuid, uuid, uuid, uuid
)
from public, anon, authenticated;

create function public.enforce_medical_access_audit_typed_resource_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_medical_access_audit_typed_resource_coherence(
        new.pet_id, new.operation,
        new.care_authorization_id, new.appointment_id,
        new.clinical_encounter_id,
        new.clinical_record_entry_id, new.clinical_amendment_id
    );
    return new;
end;
$$;

revoke all privileges on function public.enforce_medical_access_audit_typed_resource_coherence()
from public, anon, authenticated;

create trigger medical_access_audit_events_typed_resource_coherence
before insert on public.medical_access_audit_events
for each row execute function public.enforce_medical_access_audit_typed_resource_coherence();

drop function public.establish_medical_access_audit_event(
    uuid, uuid, text, text, text, text, timestamptz,
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
);

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
    p_clinical_encounter_id uuid default null,
    p_clinical_record_entry_id uuid default null,
    p_clinical_amendment_id uuid default null
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
        veterinarian_clinic_assignment_id, clinical_encounter_id,
        clinical_record_entry_id, clinical_amendment_id
    ) values (
        p_occurred_at, p_operation, p_outcome, p_actor_context, p_protected_resource_scope,
        p_acting_user_id, p_pet_id, p_guardianship_id, p_care_authorization_id,
        p_accessing_clinic_id, p_accessing_organization_id, p_appointment_id,
        p_organization_membership_id, p_organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id, p_clinical_encounter_id,
        p_clinical_record_entry_id, p_clinical_amendment_id
    ) returning id into new_event_id;
    return new_event_id;
end;
$$;

revoke all privileges
on function public.establish_medical_access_audit_event(
    uuid, uuid, text, text, text, text, timestamptz,
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
)
from public, anon, authenticated;

create function public.view_professional_pet_medical_history(
    p_pet_id uuid,
    p_accessing_clinic_id uuid,
    p_care_authorization_id uuid,
    p_clinical_encounter_id uuid default null,
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
    target_organization_id uuid;
    professional_context record;
    care_auth_record public.care_authorizations%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    bounded_limit integer;
    permitted boolean := false;
    professional_context_available boolean := false;
    care_auth_context_available boolean := false;
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
    select clinic.organization_id into target_organization_id
    from public.clinics as clinic where clinic.id = p_accessing_clinic_id;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id
      and care_auth.pet_id = p_pet_id
      and care_auth.clinic_id = p_accessing_clinic_id
      and care_auth.organization_id = target_organization_id;
    care_auth_context_available := found;

    select * into professional_context
    from public.find_current_veterinarian_context_after_lock(
        acting_user_id, p_accessing_clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
    );
    professional_context_available := found;
    if professional_context_available then
        if care_auth_record.appointment_id is not null then
            perform 1 from public.appointments as appointment
            where appointment.id = care_auth_record.appointment_id
            for share;
        end if;

        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.id = p_care_authorization_id
          and care_auth.pet_id = p_pet_id
          and care_auth.clinic_id = p_accessing_clinic_id
          and care_auth.organization_id = professional_context.organization_id
        for share;
        care_auth_context_available := found;
        if found and care_auth_record.lifecycle_state = 'ACTIVE' then
            if p_clinical_encounter_id is null
               and care_auth_record.purpose = 'APPOINTMENT_CARE'
               and exists (
                   select 1 from public.appointments as appointment
                   where appointment.id = care_auth_record.appointment_id
                     and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED')
               )
               and not exists (
                   select 1 from public.clinical_encounters as encounter_row
                   where encounter_row.care_authorization_id = care_auth_record.id
               ) then
                permitted := true;
            elsif p_clinical_encounter_id is not null then
                select encounter_row.* into encounter_record
                from public.clinical_encounters as encounter_row
                where encounter_row.id = p_clinical_encounter_id
                  and encounter_row.care_authorization_id = care_auth_record.id
                  and encounter_row.pet_id = p_pet_id
                  and encounter_row.clinic_id = p_accessing_clinic_id
                  and encounter_row.organization_id = professional_context.organization_id
                for share;
                permitted := found and encounter_record.lifecycle_state = 'ACTIVE';
            end if;
        end if;
    end if;

    if not permitted then
        perform public.establish_medical_access_audit_event(
            acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'DENIED',
            'PROFESSIONAL_CLINICAL', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
            null,
            case when care_auth_context_available then care_auth_record.id else null end,
            case when target_organization_id is not null then p_accessing_clinic_id else null end,
            target_organization_id,
            case when care_auth_context_available then care_auth_record.appointment_id else null end,
            case when professional_context_available then professional_context.organization_membership_id else null end,
            case when professional_context_available then professional_context.organization_responsibility_grant_id else null end,
            case when professional_context_available then professional_context.veterinarian_clinic_assignment_id else null end,
            case when encounter_record.id is not null then encounter_record.id else null end,
            null, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    with page_rows as (
        select record_entry.*, encounter_row.clinic_id, encounter_row.organization_id,
               encounter_row.started_at,
               encounter_row.lifecycle_state as encounter_lifecycle_state,
               encounter_row.concluded_at as encounter_concluded_at,
               encounter_row.responsible_veterinarian_clinic_assignment_id,
               coalesce(record_entry.clinical_event_at, encounter_row.started_at) as history_order_at,
               row_number() over (order by coalesce(record_entry.clinical_event_at, encounter_row.started_at) desc,
                                            record_entry.id desc) as page_number
        from public.clinical_record_entries as record_entry
        join public.clinical_encounters as encounter_row
          on encounter_row.id = record_entry.clinical_encounter_id
        where encounter_row.pet_id = p_pet_id and record_entry.lifecycle_state = 'FINALIZED'
          and (p_before_history_order_at is null or
               (coalesce(record_entry.clinical_event_at, encounter_row.started_at), record_entry.id)
                 < (p_before_history_order_at, p_before_entry_id))
        order by history_order_at desc, record_entry.id desc limit bounded_limit + 1
    ), visible_rows as (select * from page_rows where page_number <= bounded_limit)
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', visible_record.id, 'clinical_encounter_id', visible_record.clinical_encounter_id,
               'clinic_id', visible_record.clinic_id, 'organization_id', visible_record.organization_id,
               'encounter_started_at', visible_record.started_at,
               'encounter_lifecycle_state', visible_record.encounter_lifecycle_state,
               'encounter_concluded_at', visible_record.encounter_concluded_at,
               'responsible_veterinarian_clinic_assignment_id', visible_record.responsible_veterinarian_clinic_assignment_id,
               'created_by_user_id', visible_record.created_by_user_id,
               'creator_veterinarian_clinic_assignment_id', visible_record.creator_veterinarian_clinic_assignment_id,
               'created_at', visible_record.created_at,
               'draft_revision', visible_record.draft_revision,
               'last_modified_at', visible_record.last_modified_at,
               'clinical_content', visible_record.clinical_content, 'category', visible_record.category,
               'other_category_context', visible_record.other_category_context,
               'clinical_event_at', visible_record.clinical_event_at,
               'history_order_at', visible_record.history_order_at,
               'finalized_at', visible_record.finalized_at,
               'finalized_by_user_id', visible_record.finalized_by_user_id,
               'finalizer_veterinarian_clinic_assignment_id', visible_record.finalizer_veterinarian_clinic_assignment_id,
               'amendments', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', clinical_amendment.id, 'reason', clinical_amendment.reason,
                   'amendment_content', clinical_amendment.amendment_content,
                   'amending_user_id', clinical_amendment.amending_user_id,
                   'amending_veterinarian_clinic_assignment_id', clinical_amendment.amending_veterinarian_clinic_assignment_id,
                   'created_at', clinical_amendment.created_at
               ) order by clinical_amendment.created_at, clinical_amendment.id)
               from (
                   select amendment_source.*
                   from public.clinical_amendments as amendment_source
                   where amendment_source.original_clinical_record_entry_id = visible_record.id
                   order by amendment_source.created_at, amendment_source.id
                   limit 100
               ) as clinical_amendment), '[]'::jsonb),
               'amendment_count', (
                   select count(*) from public.clinical_amendments as amendment_count_source
                   where amendment_count_source.original_clinical_record_entry_id = visible_record.id
               ),
               'amendments_truncated', (
                   select count(*) > 100 from public.clinical_amendments as amendment_count_source
                   where amendment_count_source.original_clinical_record_entry_id = visible_record.id
               )
           ) order by visible_record.history_order_at desc, visible_record.id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page_rows),
           (array_agg(visible_record.history_order_at order by visible_record.history_order_at desc, visible_record.id desc))[bounded_limit],
           (array_agg(visible_record.id order by visible_record.history_order_at desc, visible_record.id desc))[bounded_limit]
    into result_payload, has_more, next_order_at, next_entry_id
    from visible_rows as visible_record;

    perform public.establish_medical_access_audit_event(
        acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'PERMITTED',
        'PROFESSIONAL_CLINICAL', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
        null, care_auth_record.id, p_accessing_clinic_id, professional_context.organization_id,
        care_auth_record.appointment_id, professional_context.organization_membership_id,
        professional_context.organization_responsibility_grant_id,
        professional_context.veterinarian_clinic_assignment_id,
        p_clinical_encounter_id, null, null
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
on function public.view_professional_pet_medical_history(uuid, uuid, uuid, uuid, integer, timestamptz, uuid)
from public, anon, authenticated;
grant execute
on function public.view_professional_pet_medical_history(uuid, uuid, uuid, uuid, integer, timestamptz, uuid)
to authenticated;

create function public.view_care_authorization_clinical_work_context(
    p_care_authorization_id uuid,
    p_clinical_encounter_id uuid default null,
    p_limit integer default 50,
    p_before_created_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    care_auth_record public.care_authorizations%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    professional_context record;
    bounded_limit integer;
    normal_entitlement boolean := false;
    permitted boolean := false;
    professional_context_available boolean := false;
    audit_operation text;
    result_payload jsonb;
    has_more boolean;
    next_created_at timestamptz;
    next_entry_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_limit is null or p_limit < 1 then raise exception 'Page limit must be positive' using errcode = '22023'; end if;
    if (p_before_created_at is null) <> (p_before_entry_id is null) then
        raise exception 'Work cursor components must be supplied together' using errcode = '22023';
    end if;
    if p_before_created_at is not null and not isfinite(p_before_created_at) then
        raise exception 'Work cursor timestamp must be finite' using errcode = '22023';
    end if;
    bounded_limit := least(p_limit, 100);
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;
    if not found then return jsonb_build_object('status', 'DENIED'); end if;

    if p_clinical_encounter_id is not null then
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = p_clinical_encounter_id
          and encounter_row.care_authorization_id = care_auth_record.id
          and encounter_row.pet_id = care_auth_record.pet_id
          and encounter_row.clinic_id = care_auth_record.clinic_id
          and encounter_row.organization_id = care_auth_record.organization_id;
    end if;

    select * into professional_context
    from public.find_current_veterinarian_context_after_lock(
        acting_user_id, care_auth_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    professional_context_available := found;
    if professional_context_available then
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.id = p_care_authorization_id
        for share;
        normal_entitlement := public.organization_has_professional_entitlement(
            professional_context.organization_id, 'CLINICAL_DOCUMENTATION'
        );
        if p_clinical_encounter_id is not null then
            select encounter_row.* into encounter_record
            from public.clinical_encounters as encounter_row
            where encounter_row.id = p_clinical_encounter_id
              and encounter_row.care_authorization_id = care_auth_record.id
              and encounter_row.pet_id = care_auth_record.pet_id
              and encounter_row.clinic_id = care_auth_record.clinic_id
              and encounter_row.organization_id = care_auth_record.organization_id
            for share;
            permitted := found and (
                care_auth_record.lifecycle_state = 'ACTIVE'
                or encounter_record.lifecycle_state = 'ACTIVE'
            );
        else
            permitted := care_auth_record.lifecycle_state = 'ACTIVE' and normal_entitlement;
        end if;
    end if;

    -- Exact active Encounter work (including revocation-safe active-care
    -- continuity), or pre-Encounter work under an ACTIVE Authorization, is
    -- ACCESS_FOR_CLINICAL_CARE. A concluded exact Encounter is narrow
    -- ACCESS_FOR_POST_CARE_DOCUMENTATION; it never becomes longitudinal access.
    audit_operation := case
        when (p_clinical_encounter_id is null and care_auth_record.lifecycle_state = 'ACTIVE')
             or encounter_record.lifecycle_state = 'ACTIVE'
          then 'ACCESS_FOR_CLINICAL_CARE'
        else 'ACCESS_FOR_POST_CARE_DOCUMENTATION'
    end;

    if not permitted then
        perform public.establish_medical_access_audit_event(
            acting_user_id, care_auth_record.pet_id, audit_operation, 'DENIED',
            'PROFESSIONAL_CLINICAL', 'ENCOUNTER_MEDICAL_INFORMATION', clock_timestamp(),
            null, care_auth_record.id, care_auth_record.clinic_id, care_auth_record.organization_id,
            care_auth_record.appointment_id,
            case when professional_context_available then professional_context.organization_membership_id else null end,
            case when professional_context_available then professional_context.organization_responsibility_grant_id else null end,
            case when professional_context_available then professional_context.veterinarian_clinic_assignment_id else null end,
            case when encounter_record.id is not null then encounter_record.id else null end,
            null, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    with page_rows as (
        select record_entry.id, record_entry.clinical_encounter_id,
               record_entry.lifecycle_state, record_entry.created_at,
               record_entry.draft_revision, record_entry.last_modified_at,
               record_entry.finalized_at, record_entry.created_by_user_id,
               record_entry.creator_veterinarian_clinic_assignment_id,
               record_entry.finalized_by_user_id,
               record_entry.finalizer_veterinarian_clinic_assignment_id,
               row_number() over (order by record_entry.created_at desc, record_entry.id desc) as page_number
        from public.clinical_record_entries as record_entry
        join public.clinical_encounters as encounter_row
          on encounter_row.id = record_entry.clinical_encounter_id
        where encounter_row.care_authorization_id = care_auth_record.id
          and (p_clinical_encounter_id is null or encounter_row.id = p_clinical_encounter_id)
          and (p_before_created_at is null or
               (record_entry.created_at, record_entry.id) < (p_before_created_at, p_before_entry_id))
        order by record_entry.created_at desc, record_entry.id desc limit bounded_limit + 1
    ), visible_rows as (select * from page_rows where page_number <= bounded_limit)
    select coalesce(jsonb_agg(to_jsonb(visible_record) - 'page_number'
               order by visible_record.created_at desc, visible_record.id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page_rows),
           (array_agg(visible_record.created_at order by visible_record.created_at desc, visible_record.id desc))[bounded_limit],
           (array_agg(visible_record.id order by visible_record.created_at desc, visible_record.id desc))[bounded_limit]
    into result_payload, has_more, next_created_at, next_entry_id
    from visible_rows as visible_record;

    perform public.establish_medical_access_audit_event(
        acting_user_id, care_auth_record.pet_id, audit_operation, 'PERMITTED',
        'PROFESSIONAL_CLINICAL', 'ENCOUNTER_MEDICAL_INFORMATION', clock_timestamp(),
        null, care_auth_record.id, care_auth_record.clinic_id, care_auth_record.organization_id,
        care_auth_record.appointment_id, professional_context.organization_membership_id,
        professional_context.organization_responsibility_grant_id,
        professional_context.veterinarian_clinic_assignment_id,
        p_clinical_encounter_id, null, null
    );
    return jsonb_build_object(
        'status', 'PERMITTED',
        'payload', jsonb_build_object(
            'care_authorization', jsonb_build_object(
                'id', care_auth_record.id, 'purpose', care_auth_record.purpose,
                'lifecycle_state', care_auth_record.lifecycle_state,
                'appointment_id', care_auth_record.appointment_id
            ),
            'encounters', coalesce((
                select jsonb_agg(jsonb_build_object(
                    'id', encounter_row.id,
                    'lifecycle_state', encounter_row.lifecycle_state,
                    'started_at', encounter_row.started_at,
                    'concluded_at', encounter_row.concluded_at,
                    'responsible_veterinarian_clinic_assignment_id',
                        encounter_row.responsible_veterinarian_clinic_assignment_id
                ) order by encounter_row.started_at, encounter_row.id)
                from (
                    select encounter_source.id, encounter_source.lifecycle_state,
                           encounter_source.started_at, encounter_source.concluded_at,
                           encounter_source.responsible_veterinarian_clinic_assignment_id
                    from public.clinical_encounters as encounter_source
                    where encounter_source.care_authorization_id = care_auth_record.id
                      and (p_clinical_encounter_id is null or encounter_source.id = p_clinical_encounter_id)
                    order by encounter_source.started_at, encounter_source.id
                    limit 100
                ) as encounter_row
            ), '[]'::jsonb),
            'encounter_count', (
                select count(*) from public.clinical_encounters as encounter_count_source
                where encounter_count_source.care_authorization_id = care_auth_record.id
                  and (p_clinical_encounter_id is null or encounter_count_source.id = p_clinical_encounter_id)
            ),
            'encounters_truncated', (
                select count(*) > 100 from public.clinical_encounters as encounter_count_source
                where encounter_count_source.care_authorization_id = care_auth_record.id
                  and (p_clinical_encounter_id is null or encounter_count_source.id = p_clinical_encounter_id)
            ),
            'clinical_encounter', case when p_clinical_encounter_id is null then null else jsonb_build_object(
                'id', encounter_record.id, 'lifecycle_state', encounter_record.lifecycle_state,
                'started_at', encounter_record.started_at, 'concluded_at', encounter_record.concluded_at,
                'responsible_veterinarian_clinic_assignment_id', encounter_record.responsible_veterinarian_clinic_assignment_id
            ) end,
            'entries', result_payload
        ),
        'cursor', case when has_more then jsonb_build_object(
            'before_created_at', next_created_at, 'before_entry_id', next_entry_id
        ) else null end
    );
end;
$$;

revoke all privileges
on function public.view_care_authorization_clinical_work_context(uuid, uuid, integer, timestamptz, uuid)
from public, anon, authenticated;
grant execute
on function public.view_care_authorization_clinical_work_context(uuid, uuid, integer, timestamptz, uuid)
to authenticated;

create function public.view_clinical_record_entry(p_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    normal_entitlement boolean := false;
    permitted boolean := false;
    professional_context_available boolean := false;
    entry_payload jsonb;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id;
    if not found then return jsonb_build_object('status', 'DENIED'); end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id;

    select * into professional_context
    from public.find_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    professional_context_available := found;
    if professional_context_available then
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.id = encounter_record.care_authorization_id
        for share;
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = record_entry.clinical_encounter_id
          and encounter_row.care_authorization_id = care_auth_record.id
        for share;
        select record_entry_row.* into record_entry
        from public.clinical_record_entries as record_entry_row
        where record_entry_row.id = p_entry_id
          and record_entry_row.clinical_encounter_id = encounter_record.id
        for share;
        if not found then
            raise exception 'Clinical resource changed during exact Entry access' using errcode = '40001';
        end if;
        normal_entitlement := public.organization_has_professional_entitlement(
            professional_context.organization_id, 'CLINICAL_DOCUMENTATION'
        );
        permitted := (
            care_auth_record.lifecycle_state = 'ACTIVE' and normal_entitlement
        ) or encounter_record.lifecycle_state = 'ACTIVE'
          or (
              encounter_record.lifecycle_state = 'CONCLUDED'
              and care_auth_record.lifecycle_state = 'ACTIVE'
          );
    end if;

    if not permitted then
        perform public.establish_medical_access_audit_event(
            acting_user_id, encounter_record.pet_id, 'VIEW_CLINICAL_RECORD_ENTRY', 'DENIED',
            'PROFESSIONAL_CLINICAL', 'CLINICAL_RECORD_ENTRY', clock_timestamp(),
            null, care_auth_record.id, encounter_record.clinic_id, encounter_record.organization_id,
            encounter_record.appointment_id,
            case when professional_context_available then professional_context.organization_membership_id else null end,
            case when professional_context_available then professional_context.organization_responsibility_grant_id else null end,
            case when professional_context_available then professional_context.veterinarian_clinic_assignment_id else null end,
            encounter_record.id, record_entry.id, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    select jsonb_build_object(
        'id', record_entry.id,
        'clinical_encounter_id', record_entry.clinical_encounter_id,
        'lifecycle_state', record_entry.lifecycle_state,
        'clinical_content', record_entry.clinical_content,
        'category', record_entry.category,
        'other_category_context', record_entry.other_category_context,
        'clinical_event_at', record_entry.clinical_event_at,
        'draft_revision', record_entry.draft_revision,
        'created_at', record_entry.created_at,
        'last_modified_at', record_entry.last_modified_at,
        'created_by_user_id', record_entry.created_by_user_id,
        'creator_veterinarian_clinic_assignment_id', record_entry.creator_veterinarian_clinic_assignment_id,
        'finalized_at', record_entry.finalized_at,
        'finalized_by_user_id', record_entry.finalized_by_user_id,
        'finalizer_veterinarian_clinic_assignment_id', record_entry.finalizer_veterinarian_clinic_assignment_id,
        'encounter', jsonb_build_object(
            'pet_id', encounter_record.pet_id, 'clinic_id', encounter_record.clinic_id,
            'organization_id', encounter_record.organization_id,
            'responsible_veterinarian_clinic_assignment_id', encounter_record.responsible_veterinarian_clinic_assignment_id,
            'started_at', encounter_record.started_at, 'lifecycle_state', encounter_record.lifecycle_state,
            'concluded_at', encounter_record.concluded_at
        ),
        'contributors', coalesce((select jsonb_agg(jsonb_build_object(
            'veterinarian_clinic_assignment_id', contributor.veterinarian_clinic_assignment_id,
            'first_contributed_at', contributor.first_contributed_at
        ) order by contributor.first_contributed_at, contributor.veterinarian_clinic_assignment_id)
        from (
            select contributor_source.*
            from public.clinical_record_entry_contributors as contributor_source
            where contributor_source.clinical_record_entry_id = record_entry.id
            order by contributor_source.first_contributed_at,
                     contributor_source.veterinarian_clinic_assignment_id
            limit 100
        ) as contributor), '[]'::jsonb),
        'contributor_count', (
            select count(*) from public.clinical_record_entry_contributors as contributor_count_source
            where contributor_count_source.clinical_record_entry_id = record_entry.id
        ),
        'contributors_truncated', (
            select count(*) > 100 from public.clinical_record_entry_contributors as contributor_count_source
            where contributor_count_source.clinical_record_entry_id = record_entry.id
        ),
        'amendments', case when record_entry.lifecycle_state = 'FINALIZED' then coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', clinical_amendment.id, 'reason', clinical_amendment.reason,
                'amendment_content', clinical_amendment.amendment_content,
                'amending_user_id', clinical_amendment.amending_user_id,
                'amending_veterinarian_clinic_assignment_id', clinical_amendment.amending_veterinarian_clinic_assignment_id,
                'created_at', clinical_amendment.created_at
            ) order by clinical_amendment.created_at, clinical_amendment.id)
            from (
                select amendment_source.*
                from public.clinical_amendments as amendment_source
                where amendment_source.original_clinical_record_entry_id = record_entry.id
                order by amendment_source.created_at, amendment_source.id
                limit 100
            ) as clinical_amendment
        ), '[]'::jsonb) else '[]'::jsonb end,
        'amendment_count', (
            select count(*) from public.clinical_amendments as amendment_count_source
            where amendment_count_source.original_clinical_record_entry_id = record_entry.id
        ),
        'amendments_truncated', (
            select count(*) > 100 from public.clinical_amendments as amendment_count_source
            where amendment_count_source.original_clinical_record_entry_id = record_entry.id
        )
    ) into entry_payload;

    perform public.establish_medical_access_audit_event(
        acting_user_id, encounter_record.pet_id, 'VIEW_CLINICAL_RECORD_ENTRY', 'PERMITTED',
        'PROFESSIONAL_CLINICAL', 'CLINICAL_RECORD_ENTRY', clock_timestamp(),
        null, care_auth_record.id, encounter_record.clinic_id, encounter_record.organization_id,
        encounter_record.appointment_id, professional_context.organization_membership_id,
        professional_context.organization_responsibility_grant_id,
        professional_context.veterinarian_clinic_assignment_id,
        encounter_record.id, record_entry.id, null
    );
    return jsonb_build_object('status', 'PERMITTED', 'payload', entry_payload);
end;
$$;

revoke all privileges on function public.view_clinical_record_entry(uuid)
from public, anon, authenticated;
grant execute on function public.view_clinical_record_entry(uuid) to authenticated;

-- The mobile/API roles receive no direct clinical-table access. All protected
-- content flows through the audited SECURITY DEFINER operations above.
alter table public.clinical_encounters enable row level security;
alter table public.clinical_record_entries enable row level security;
alter table public.clinical_record_entry_contributors enable row level security;
alter table public.clinical_amendments enable row level security;

revoke all privileges on table public.clinical_encounters from public, anon, authenticated;
revoke all privileges on table public.clinical_record_entries from public, anon, authenticated;
revoke all privileges on table public.clinical_record_entry_contributors from public, anon, authenticated;
revoke all privileges on table public.clinical_amendments from public, anon, authenticated;

commit;

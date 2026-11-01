begin;

-- Guardian Attachment authorization never resolves a professional context.
-- Keep professional audit provenance explicitly nullable so the Guardian audit
-- path cannot dereference an unassigned PL/pgSQL record.
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
    origin_encounter public.clinical_encounters%rowtype;
    origin_care_auth public.care_authorizations%rowtype;
    access_care_auth public.care_authorizations%rowtype;
    access_encounter public.clinical_encounters%rowtype;
    guardianship_record public.guardianships%rowtype;
    professional_context record;
    accessing_organization_id uuid;
    professional_context_available boolean := false;
    audit_organization_membership_id uuid := null;
    audit_organization_responsibility_grant_id uuid := null;
    audit_veterinarian_clinic_assignment_id uuid := null;
    permitted boolean := false;
    exact_context_matches boolean := false;
    audit_care_authorization_id uuid;
    audit_appointment_id uuid;
begin
    if p_access_context is null
       or p_access_context not in ('GUARDIAN', 'PROFESSIONAL') then
        raise exception 'Access context must be GUARDIAN or PROFESSIONAL' using errcode = '22023';
    end if;
    if p_access_context = 'GUARDIAN' and (
        p_professional_scope is not null or p_accessing_clinic_id is not null
        or p_care_authorization_id is not null or p_accessing_clinical_encounter_id is not null
    ) then raise exception 'Guardian access cannot carry professional context' using errcode = '22023'; end if;
    if p_access_context = 'PROFESSIONAL'
       and (
           p_professional_scope is null
           or p_professional_scope not in ('LONGITUDINAL', 'EXACT_RESOURCE')
       ) then
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
    select encounter_row.* into origin_encounter from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select care_auth.* into origin_care_auth from public.care_authorizations as care_auth
    where care_auth.id = origin_encounter.care_authorization_id;
    if p_access_context = 'GUARDIAN' then
        select guardianship.* into guardianship_record from public.guardianships as guardianship
        where guardianship.pet_id = origin_encounter.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
        for share;
        if not found then
            select guardianship.* into guardianship_record from public.guardianships as guardianship
            where guardianship.pet_id = origin_encounter.pet_id and guardianship.user_id = acting_user_id
            order by guardianship.effective_start desc, guardianship.id desc limit 1;
        end if;
        perform 1 from public.clinical_encounters as encounter_row
        where encounter_row.id = origin_encounter.id for share;
        select entry_row.* into record_entry from public.clinical_record_entries as entry_row
        where entry_row.id = record_entry.id for share;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
        permitted := guardianship_record.id is not null
            and guardianship_record.effective_start <= clock_timestamp()
            and guardianship_record.effective_end is null
            and record_entry.lifecycle_state = 'FINALIZED'
            and attachment_record.removed_at is null
            and attachment_record.validation_state = 'AVAILABLE'
            and attachment_record.object_state = 'STORED';
    elsif p_professional_scope = 'LONGITUDINAL' then
        select clinic.organization_id into accessing_organization_id
        from public.clinics as clinic where clinic.id = p_accessing_clinic_id;
        select * into professional_context
        from public.find_current_veterinarian_context_after_lock(
            acting_user_id, p_accessing_clinic_id, 'CLINICAL_CARE', 'CLINICAL_CARE'
        );
        professional_context_available := found;
        if professional_context_available then
            audit_organization_membership_id := professional_context.organization_membership_id;
            audit_organization_responsibility_grant_id :=
                professional_context.organization_responsibility_grant_id;
            audit_veterinarian_clinic_assignment_id :=
                professional_context.veterinarian_clinic_assignment_id;
            select care_auth.* into access_care_auth from public.care_authorizations as care_auth
            where care_auth.id = p_care_authorization_id
              and care_auth.pet_id = origin_encounter.pet_id
              and care_auth.clinic_id = p_accessing_clinic_id
              and care_auth.organization_id = professional_context.organization_id;
            if found and access_care_auth.appointment_id is not null then
                perform 1 from public.appointments as appointment
                where appointment.id = access_care_auth.appointment_id for share;
            end if;
            select care_auth.* into access_care_auth from public.care_authorizations as care_auth
            where care_auth.id = p_care_authorization_id
              and care_auth.pet_id = origin_encounter.pet_id
              and care_auth.clinic_id = p_accessing_clinic_id
              and care_auth.organization_id = professional_context.organization_id
            for share;
            if found and access_care_auth.lifecycle_state = 'ACTIVE' then
                if p_accessing_clinical_encounter_id is null
                   and access_care_auth.purpose = 'APPOINTMENT_CARE'
                   and exists (select 1 from public.appointments as appointment
                               where appointment.id = access_care_auth.appointment_id
                                 and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED'))
                   and not exists (select 1 from public.clinical_encounters as encounter_row
                                   where encounter_row.care_authorization_id = access_care_auth.id) then
                    permitted := true;
                elsif p_accessing_clinical_encounter_id is not null then
                    select encounter_row.* into access_encounter from public.clinical_encounters as encounter_row
                    where encounter_row.id = p_accessing_clinical_encounter_id
                      and encounter_row.care_authorization_id = access_care_auth.id
                      and encounter_row.pet_id = origin_encounter.pet_id
                      and encounter_row.clinic_id = p_accessing_clinic_id
                      and encounter_row.organization_id = professional_context.organization_id
                    for share;
                    permitted := found and access_encounter.lifecycle_state = 'ACTIVE';
                end if;
            end if;
        end if;
        perform 1 from public.clinical_record_entries as entry_row
        where entry_row.id = record_entry.id for share;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = p_attachment_id for share;
        permitted := permitted and record_entry.lifecycle_state = 'FINALIZED'
            and attachment_record.removed_at is null
            and attachment_record.validation_state = 'AVAILABLE'
            and attachment_record.object_state = 'STORED';
        -- Longitudinal authority may be based on a different care episode.
        -- The typed resource chain therefore records the origin Encounter while
        -- leaving the optional origin Care Authorization/Appointment slots null.
        audit_care_authorization_id := null;
        audit_appointment_id := null;
    else
        select clinic.organization_id into accessing_organization_id
        from public.clinics as clinic where clinic.id = p_accessing_clinic_id;
        exact_context_matches := p_accessing_clinic_id is not distinct from origin_encounter.clinic_id
            and (p_care_authorization_id is null
                 or p_care_authorization_id is not distinct from origin_care_auth.id)
            and (p_accessing_clinical_encounter_id is null
                 or p_accessing_clinical_encounter_id is not distinct from origin_encounter.id);
        if not exact_context_matches then
            permitted := false;
        else
            select * into professional_context
            from public.find_current_veterinarian_context_after_lock(
                acting_user_id, origin_encounter.clinic_id, 'CLINICAL_DOCUMENTATION', null
            );
            professional_context_available := found;
            if professional_context_available then
                audit_organization_membership_id := professional_context.organization_membership_id;
                audit_organization_responsibility_grant_id :=
                    professional_context.organization_responsibility_grant_id;
                audit_veterinarian_clinic_assignment_id :=
                    professional_context.veterinarian_clinic_assignment_id;
                select care_auth.* into origin_care_auth from public.care_authorizations as care_auth
                where care_auth.id = origin_encounter.care_authorization_id for share;
                select encounter_row.* into origin_encounter from public.clinical_encounters as encounter_row
                where encounter_row.id = origin_encounter.id for share;
                select entry_row.* into record_entry from public.clinical_record_entries as entry_row
                where entry_row.id = record_entry.id for share;
                select attachment.* into attachment_record from public.clinical_attachments as attachment
                where attachment.id = p_attachment_id for share;
                permitted := (
                    (origin_care_auth.lifecycle_state = 'ACTIVE'
                     and public.organization_has_professional_entitlement(
                         professional_context.organization_id, 'CLINICAL_DOCUMENTATION'))
                    or origin_encounter.lifecycle_state = 'ACTIVE'
                    or (origin_encounter.lifecycle_state = 'CONCLUDED'
                        and origin_care_auth.lifecycle_state = 'ACTIVE')
                ) and attachment_record.removed_at is null
                  and attachment_record.validation_state = 'AVAILABLE'
                  and attachment_record.object_state = 'STORED';
            end if;
        end if;
        audit_care_authorization_id := case when exact_context_matches then origin_care_auth.id else null end;
        audit_appointment_id := case when exact_context_matches then origin_encounter.appointment_id else null end;
    end if;

    if permitted and not exists (
        select 1 from storage.objects as object_record
        where object_record.bucket_id = 'clinical-attachments'
          and object_record.name = 'v1/' || attachment_record.storage_object_id::text
    ) then
        raise exception 'Authorized Clinical Attachment Storage object is missing'
            using errcode = 'XX001';
    end if;

    perform public.establish_medical_access_audit_event(
        acting_user_id, origin_encounter.pet_id, 'VIEW_CLINICAL_ATTACHMENT',
        case when permitted then 'PERMITTED' else 'DENIED' end,
        case when p_access_context = 'GUARDIAN' then 'GUARDIAN' else 'PROFESSIONAL_CLINICAL' end,
        'CLINICAL_ATTACHMENT', clock_timestamp(),
        case when p_access_context = 'GUARDIAN' then guardianship_record.id else null end,
        audit_care_authorization_id,
        case when p_access_context = 'PROFESSIONAL' and accessing_organization_id is not null
             then p_accessing_clinic_id else null end,
        case when p_access_context = 'PROFESSIONAL' then accessing_organization_id else null end,
        audit_appointment_id,
        audit_organization_membership_id,
        audit_organization_responsibility_grant_id,
        audit_veterinarian_clinic_assignment_id,
        origin_encounter.id, record_entry.id, null, attachment_record.id
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

revoke all privileges
on function public.authorize_clinical_attachment_download(
    uuid, uuid, text, text, uuid, uuid, uuid
)
from public, anon, authenticated;

grant execute
on function public.authorize_clinical_attachment_download(
    uuid, uuid, text, text, uuid, uuid, uuid
)
to service_role;

commit;

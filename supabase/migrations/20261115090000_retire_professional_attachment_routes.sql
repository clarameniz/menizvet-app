-- Retire the professional Clinical Attachment routes — Punto 8, stage M4
-- (ADR-011; SPEC-MED-010 BR-19, BR-24, BR-25; SPEC-MED-007 as narrowed by it;
-- docs/CLINICAL_DOCUMENTATION_TRANSITION.md §5.2).
--
-- Requires M2 (20261113090000) and M3 (20261114090000). SPEC-MED-010 ships no
-- professional client Attachment workflow (BR-19), and no client calls the
-- professional routes of the clinical-attachments Edge Function. Their SQL
-- operations still accepted authority identifiers from the client (the
-- uploader's Veterinarian Clinic Assignment, the accessing Clinic, a Care
-- Authorization) and the former Encounter parameter, and the upload route
-- would publish an Attachment to Guardians with no Draft review left. They are
-- retired, not re-keyed: a later professional workflow must be specified and
-- built on SPEC-MED-010 BR-19 from scratch.
--
--   0. Fail-closed guard: the M2 documentation contract is present.
--   1. Retired (service_role-only operations behind the Edge routes
--      initiate, complete, remove, and professional-download):
--      initiate_clinical_attachment_upload, resolve_clinical_attachment_completion_target,
--      remove_draft_clinical_attachment, and the multi-context
--      authorize_clinical_attachment_download.
--   2. authorize_guardian_clinical_attachment_download(p_auth_subject,
--      p_attachment_id): exactly the Guardian branch of the retired download
--      authorization — current Guardianship of the Attachment's Pet, an
--      AVAILABLE and STORED current Attachment, the missing-object integrity
--      check, and one VIEW_CLINICAL_ATTACHMENT audit event per request. It
--      takes no professional context, no Clinic, no Care Authorization, and no
--      Encounter.
--
-- Unchanged: the Storage validation pipeline used by the maintenance route
-- (claim_clinical_attachment_maintenance, mark_clinical_attachment_object_stored,
-- complete_clinical_attachment_validation, expire_missing_stale_clinical_attachment_upload,
-- mark_clinical_attachment_object_deleted), the Guardian history read and its
-- Attachment metadata, and every table. No row is read or written, and no
-- DROP ... CASCADE is used.
begin;

-- ==================================================================
-- 0. Fail-closed guard.
-- ==================================================================

do $guard$
begin
    if to_regprocedure('public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean)') is null
       or to_regclass('public.clinical_encounters') is not null then
        raise exception 'M4 refused: the appointment-owned documentation contract (M2) is not in place'
            using errcode = '55000';
    end if;
end;
$guard$;

-- ==================================================================
-- 1. Retired professional Attachment operations.
-- ==================================================================

drop function public.initiate_clinical_attachment_upload(uuid, uuid, uuid, uuid, text);
drop function public.resolve_clinical_attachment_completion_target(uuid, uuid);
drop function public.remove_draft_clinical_attachment(uuid, uuid);
drop function public.authorize_clinical_attachment_download(uuid, uuid, text, text, uuid, uuid, uuid);

-- ==================================================================
-- 2. Guardian Attachment download authorization.
-- ==================================================================

create function public.authorize_guardian_clinical_attachment_download(
    p_auth_subject uuid,
    p_attachment_id uuid
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
    guardianship_record public.guardianships%rowtype;
    permitted boolean;
begin
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

    -- Current Guardianship of the Attachment's own Pet, held for the decision;
    -- otherwise the latest ended one, for audit provenance only.
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
        and guardianship_record.effective_end is null
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
        p_actor_context => 'GUARDIAN',
        p_protected_resource_scope => 'CLINICAL_ATTACHMENT',
        p_occurred_at => clock_timestamp(),
        p_guardianship_id => guardianship_record.id,
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

revoke all privileges
on function public.authorize_guardian_clinical_attachment_download(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.authorize_guardian_clinical_attachment_download(uuid, uuid)
to service_role;

commit;

begin;

-- Slice 13: Clinical Attachments. PostgreSQL remains the domain-metadata
-- authority; the private Storage bucket is declared separately in config.toml.

create table public.clinical_attachments (
    id uuid not null default gen_random_uuid(),
    clinical_record_entry_id uuid not null,
    uploaded_by_user_id uuid not null,
    uploader_vca_id uuid not null,
    created_at timestamptz not null default clock_timestamp(),
    upload_idempotency_key uuid not null,
    storage_object_id uuid not null default gen_random_uuid(),
    upload_stale_after timestamptz not null,
    original_filename text,
    validation_state text not null default 'PENDING',
    object_state text not null default 'AWAITING_UPLOAD',
    object_state_changed_at timestamptz not null default clock_timestamp(),
    trusted_media_type text,
    trusted_byte_size bigint,
    integrity_algorithm text,
    integrity_value bytea,
    validation_policy_version text,
    validation_completed_at timestamptz,
    rejection_code text,
    removed_at timestamptz,
    removed_by_user_id uuid,
    removed_by_vca_id uuid,
    constraint clinical_attachments_pkey primary key (id),
    constraint clinical_attachments_entry_id_fkey
        foreign key (clinical_record_entry_id)
        references public.clinical_record_entries (id)
        on update no action on delete restrict,
    constraint clinical_attachments_uploaded_by_user_id_fkey
        foreign key (uploaded_by_user_id)
        references public.users (id)
        on update no action on delete restrict,
    constraint clinical_attachments_uploader_vca_id_fkey
        foreign key (uploader_vca_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action on delete restrict,
    constraint clinical_attachments_removed_by_user_id_fkey
        foreign key (removed_by_user_id)
        references public.users (id)
        on update no action on delete restrict,
    constraint clinical_attachments_removed_by_vca_id_fkey
        foreign key (removed_by_vca_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action on delete restrict,
    constraint clinical_attachments_storage_object_id_key unique (storage_object_id),
    constraint clinical_attachments_uploader_idempotency_key
        unique (uploaded_by_user_id, upload_idempotency_key),
    constraint clinical_attachments_validation_state_check
        check (validation_state in ('PENDING', 'AVAILABLE', 'REJECTED')),
    constraint clinical_attachments_object_state_check
        check (object_state in ('AWAITING_UPLOAD', 'STORED', 'DELETE_PENDING', 'DELETED')),
    constraint clinical_attachments_original_filename_check
        check (
            original_filename is null
            or (
                original_filename = btrim(original_filename, E' \t\n\r\f\013')
                and original_filename <> ''
                and char_length(original_filename) <= 255
                and original_filename !~ '[[:cntrl:]/\\]'
            )
        ),
    constraint clinical_attachments_created_at_finite_check check (isfinite(created_at)),
    constraint clinical_attachments_upload_stale_after_finite_check check (isfinite(upload_stale_after)),
    constraint clinical_attachments_object_changed_at_finite_check check (isfinite(object_state_changed_at)),
    constraint clinical_attachments_validation_completed_at_finite_check
        check (validation_completed_at is null or isfinite(validation_completed_at)),
    constraint clinical_attachments_removed_at_finite_check
        check (removed_at is null or isfinite(removed_at)),
    constraint clinical_attachments_upload_window_check check (upload_stale_after > created_at),
    constraint clinical_attachments_object_change_order_check
        check (object_state_changed_at >= created_at),
    constraint clinical_attachments_validation_order_check
        check (validation_completed_at is null or validation_completed_at >= created_at),
    constraint clinical_attachments_removal_shape_check
        check (
            (removed_at is null and removed_by_user_id is null and removed_by_vca_id is null)
            or
            (removed_at is not null and removed_by_user_id is not null and removed_by_vca_id is not null)
        ),
    constraint clinical_attachments_removal_order_check
        check (removed_at is null or removed_at >= created_at),
    constraint clinical_attachments_removal_after_validation_check
        check (
            removed_at is null
            or validation_completed_at is null
            or removed_at >= validation_completed_at
        ),
    constraint clinical_attachments_removal_cleanup_state_check
        check (removed_at is null or object_state in ('DELETE_PENDING', 'DELETED')),
    constraint clinical_attachments_pending_shape_check
        check (
            validation_state <> 'PENDING'
            or (
                trusted_media_type is null
                and trusted_byte_size is null
                and integrity_algorithm is null
                and integrity_value is null
                and validation_policy_version is null
                and validation_completed_at is null
                and rejection_code is null
                and (removed_at is not null or object_state in ('AWAITING_UPLOAD', 'STORED'))
            )
        ),
    constraint clinical_attachments_available_shape_check
        check (
            validation_state <> 'AVAILABLE'
            or (
                trusted_media_type is not null
                and trusted_byte_size is not null
                and integrity_algorithm is not null
                and integrity_value is not null
                and validation_policy_version is not null
                and validation_completed_at is not null
                and trusted_media_type = 'application/pdf'
                and trusted_byte_size between 1 and 10485760
                and integrity_algorithm = 'SHA-256'
                and octet_length(integrity_value) = 32
                and validation_policy_version = 'phase1-pdf-v1'
                and rejection_code is null
                and (removed_at is not null or object_state = 'STORED')
            )
        ),
    constraint clinical_attachments_rejected_shape_check
        check (
            validation_state <> 'REJECTED'
            or (
                trusted_media_type is null
                and trusted_byte_size is null
                and integrity_algorithm is null
                and integrity_value is null
                and validation_policy_version is not null
                and validation_completed_at is not null
                and rejection_code is not null
                and validation_policy_version = 'phase1-pdf-v1'
                and object_state in ('DELETE_PENDING', 'DELETED')
                and rejection_code in (
                    'UPLOAD_STALE', 'PDF_EMPTY', 'PDF_TOO_LARGE', 'PDF_ENCRYPTED',
                    'PDF_PARSE_INVALID', 'PDF_UNRESOLVED_REFERENCE', 'PDF_JAVASCRIPT',
                    'PDF_XFA', 'PDF_EMBEDDED_FILE', 'PDF_LAUNCH',
                    'PDF_ACTION_UNSUPPORTED', 'PDF_RICH_MEDIA',
                    'PDF_MULTIMEDIA_UNSUPPORTED', 'PDF_ACTIVE_FEATURE_UNSUPPORTED',
                    'PDF_UNSUPPORTED_STRUCTURE', 'PDF_RESOURCE_LIMIT',
                    'MEDIA_TYPE_MISMATCH', 'STORAGE_SIZE_INVALID',
                    'STORAGE_OBJECT_EMPTY',
                    'STORAGE_OBJECT_TOO_LARGE', 'STORAGE_CONTENT_TYPE_MISMATCH',
                    'STORAGE_CACHE_CONTROL_MISMATCH'
                )
            )
        )
);

create index clinical_attachments_current_by_entry_idx
on public.clinical_attachments (clinical_record_entry_id, id)
where removed_at is null;

create index clinical_attachments_maintenance_idx
on public.clinical_attachments (upload_stale_after, id)
where object_state <> 'DELETED'
  and (validation_state <> 'AVAILABLE' or removed_at is not null);

create function public.enforce_clinical_attachment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    parent_entry public.clinical_record_entries%rowtype;
    parent_encounter public.clinical_encounters%rowtype;
    provenance_user_id uuid;
begin
    select entry_row.* into parent_entry
    from public.clinical_record_entries as entry_row
    where entry_row.id = new.clinical_record_entry_id
    for update;
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
    select encounter_row.* into parent_encounter
    from public.clinical_encounters as encounter_row
    where encounter_row.id = parent_entry.clinical_encounter_id;
    perform public.assert_vca_user_provider_context(
        new.uploader_vca_id, new.uploaded_by_user_id,
        parent_encounter.clinic_id, parent_encounter.organization_id
    );
    if new.removed_at is not null then
        perform public.assert_vca_user_provider_context(
            new.removed_by_vca_id, new.removed_by_user_id,
            parent_encounter.clinic_id, parent_encounter.organization_id
        );
    end if;

    if tg_op = 'INSERT' then
        if parent_entry.lifecycle_state <> 'DRAFT'
           or new.validation_state <> 'PENDING'
           or new.object_state <> 'AWAITING_UPLOAD'
           or new.removed_at is not null then
            raise exception 'A new Attachment must begin PENDING/AWAITING_UPLOAD on a DRAFT Entry'
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
        if parent_entry.lifecycle_state = 'FINALIZED'
           and old.removed_at is null
           and old.validation_state = 'AVAILABLE'
           and new is distinct from old then
            raise exception 'Current AVAILABLE Attachment metadata is immutable after Entry finalization'
                using errcode = '23514';
        end if;
    end if;
    return new;
end;
$$;

revoke all privileges on function public.enforce_clinical_attachment_integrity()
from public, anon, authenticated;

create trigger a_clinical_attachments_integrity
before insert or update on public.clinical_attachments
for each row execute function public.enforce_clinical_attachment_integrity();

create function public.prevent_clinical_attachment_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'Clinical Attachment metadata is historically retained; delete is not permitted'
        using errcode = '23514';
end;
$$;

revoke all privileges on function public.prevent_clinical_attachment_deletion()
from public, anon, authenticated;

create trigger clinical_attachments_prevent_delete
before delete on public.clinical_attachments
for each row execute function public.prevent_clinical_attachment_deletion();

create function public.enforce_clinical_attachment_current_cap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare current_count integer;
begin
    if new.removed_at is not null then return new; end if;
    perform 1 from public.clinical_record_entries as entry_row
    where entry_row.id = new.clinical_record_entry_id for update;
    select count(*) into current_count
    from public.clinical_attachments as attachment
    where attachment.clinical_record_entry_id = new.clinical_record_entry_id
      and attachment.removed_at is null
      and (tg_op = 'INSERT' or attachment.id <> new.id);
    if current_count >= 5 then
        raise exception 'A Clinical Record Entry may have at most five current Attachments'
            using errcode = '23514';
    end if;
    return new;
end;
$$;

revoke all privileges on function public.enforce_clinical_attachment_current_cap()
from public, anon, authenticated;

create trigger b_clinical_attachments_current_cap
before insert or update of removed_at, clinical_record_entry_id on public.clinical_attachments
for each row execute function public.enforce_clinical_attachment_current_cap();

create function public.enforce_clinical_attachment_parent_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare attachment_record public.clinical_attachments%rowtype;
begin
    if old.lifecycle_state = 'DRAFT' and new.lifecycle_state = 'FINALIZED' then
        for attachment_record in
            select attachment.*
            from public.clinical_attachments as attachment
            where attachment.clinical_record_entry_id = new.id
              and attachment.removed_at is null
            order by attachment.id
            for update
        loop
            if attachment_record.validation_state = 'PENDING' then
                raise exception 'A Clinical Record Entry with a current PENDING Attachment cannot be finalized'
                    using errcode = '23514';
            end if;
            if attachment_record.validation_state = 'AVAILABLE'
               and not exists (
                   select 1
                   from storage.objects as object_record
                   where object_record.bucket_id = 'clinical-attachments'
                     and object_record.name = 'v1/' || attachment_record.storage_object_id::text
               ) then
                raise exception 'A current AVAILABLE Attachment is missing its Storage object'
                    using errcode = '23514';
            end if;
        end loop;
    end if;
    return new;
end;
$$;

revoke all privileges on function public.enforce_clinical_attachment_parent_finalization()
from public, anon, authenticated;

create trigger clinical_record_entries_attachment_finalization_guard
before update of lifecycle_state on public.clinical_record_entries
for each row execute function public.enforce_clinical_attachment_parent_finalization();

create function public.initiate_clinical_attachment_upload(
    p_auth_subject uuid,
    p_entry_id uuid,
    p_uploader_vca_id uuid,
    p_upload_idempotency_key uuid,
    p_original_filename text
)
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
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    if professional_context.veterinarian_clinic_assignment_id is distinct from p_uploader_vca_id then
        raise exception 'Uploader VCA must be the current exact professional context' using errcode = '42501';
    end if;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id for update;
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = p_entry_id for update;
    if record_entry.lifecycle_state <> 'DRAFT' then
        raise exception 'Attachments may be initiated only on a DRAFT Entry' using errcode = '23514';
    end if;
    if encounter_record.lifecycle_state = 'CONCLUDED' and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care Attachment initiation requires the Care Authorization to remain ACTIVE'
            using errcode = '42501';
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
$$;

revoke all privileges on function public.initiate_clinical_attachment_upload(uuid, uuid, uuid, uuid, text)
from public, anon, authenticated;
grant execute on function public.initiate_clinical_attachment_upload(uuid, uuid, uuid, uuid, text)
to service_role;

create function public.mark_clinical_attachment_object_stored(
    p_attachment_id uuid,
    p_storage_object_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare attachment_record public.clinical_attachments%rowtype;
begin
    perform 1 from public.clinical_record_entries as entry_row
    join public.clinical_attachments as attachment on attachment.clinical_record_entry_id = entry_row.id
    where attachment.id = p_attachment_id for update of entry_row;
    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id for update;
    if not found then raise exception 'Clinical Attachment does not exist' using errcode = '23503'; end if;
    if attachment_record.storage_object_id is distinct from p_storage_object_id then
        raise exception 'Storage object identity does not match Attachment' using errcode = '23514';
    end if;
    if attachment_record.removed_at is not null then
        return jsonb_build_object('status', 'REMOVED', 'object_state', attachment_record.object_state);
    end if;
    if attachment_record.validation_state <> 'PENDING' then
        return jsonb_build_object('status', attachment_record.validation_state, 'object_state', attachment_record.object_state);
    end if;
    if attachment_record.object_state = 'AWAITING_UPLOAD' then
        update public.clinical_attachments set object_state = 'STORED', object_state_changed_at = clock_timestamp()
        where id = p_attachment_id returning * into attachment_record;
    elsif attachment_record.object_state <> 'STORED' then
        raise exception 'Attachment object is not in a storable state' using errcode = '23514';
    end if;
    return jsonb_build_object('status', 'PENDING', 'object_state', attachment_record.object_state);
end;
$$;

revoke all privileges on function public.mark_clinical_attachment_object_stored(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.mark_clinical_attachment_object_stored(uuid, uuid) to service_role;

create function public.complete_clinical_attachment_validation(
    p_attachment_id uuid,
    p_storage_object_id uuid,
    p_outcome text,
    p_trusted_media_type text,
    p_trusted_byte_size bigint,
    p_integrity_value bytea,
    p_validation_policy_version text,
    p_rejection_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    attachment_record public.clinical_attachments%rowtype;
    completed_at timestamptz := clock_timestamp();
begin
    if p_outcome is null
       or p_outcome not in ('AVAILABLE', 'REJECTED')
       or p_validation_policy_version is distinct from 'phase1-pdf-v1' then
        raise exception 'Invalid Attachment validation callback shape' using errcode = '22023';
    end if;
    if p_outcome = 'AVAILABLE' then
        if p_trusted_media_type is distinct from 'application/pdf'
           or p_trusted_byte_size is null
           or p_trusted_byte_size not between 1 and 10485760
           or p_integrity_value is null
           or octet_length(p_integrity_value) <> 32
           or p_rejection_code is not null then
            raise exception 'Trusted AVAILABLE facts do not satisfy phase1-pdf-v1'
                using errcode = '22023';
        end if;
    elsif p_trusted_media_type is not null
       or p_trusted_byte_size is not null
       or p_integrity_value is not null
       or p_rejection_code is null
       or p_rejection_code not in (
           'UPLOAD_STALE', 'PDF_EMPTY', 'PDF_TOO_LARGE', 'PDF_ENCRYPTED',
           'PDF_PARSE_INVALID', 'PDF_UNRESOLVED_REFERENCE', 'PDF_JAVASCRIPT',
           'PDF_XFA', 'PDF_EMBEDDED_FILE', 'PDF_LAUNCH',
           'PDF_ACTION_UNSUPPORTED', 'PDF_RICH_MEDIA',
           'PDF_MULTIMEDIA_UNSUPPORTED', 'PDF_ACTIVE_FEATURE_UNSUPPORTED',
           'PDF_UNSUPPORTED_STRUCTURE', 'PDF_RESOURCE_LIMIT',
           'MEDIA_TYPE_MISMATCH', 'STORAGE_SIZE_INVALID',
           'STORAGE_OBJECT_EMPTY',
           'STORAGE_OBJECT_TOO_LARGE', 'STORAGE_CONTENT_TYPE_MISMATCH',
           'STORAGE_CACHE_CONTROL_MISMATCH'
       ) then
        raise exception 'Trusted REJECTED facts are malformed' using errcode = '22023';
    end if;
    perform 1 from public.clinical_record_entries as entry_row
    join public.clinical_attachments as attachment on attachment.clinical_record_entry_id = entry_row.id
    where attachment.id = p_attachment_id for update of entry_row;
    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id for update;
    if not found then raise exception 'Clinical Attachment does not exist' using errcode = '23503'; end if;
    if attachment_record.storage_object_id is distinct from p_storage_object_id then
        raise exception 'Storage object identity does not match Attachment' using errcode = '23514';
    end if;
    if attachment_record.removed_at is not null then
        return jsonb_build_object('status', 'REMOVED');
    end if;
    if attachment_record.validation_state <> 'PENDING' then
        if attachment_record.validation_state = p_outcome
           and attachment_record.validation_policy_version is not distinct from p_validation_policy_version
           and attachment_record.trusted_media_type is not distinct from p_trusted_media_type
           and attachment_record.trusted_byte_size is not distinct from p_trusted_byte_size
           and attachment_record.integrity_value is not distinct from p_integrity_value
           and attachment_record.rejection_code is not distinct from p_rejection_code then
            return jsonb_build_object('status', attachment_record.validation_state, 'idempotent_retry', true);
        end if;
        raise exception 'Conflicting terminal Attachment validation callback' using errcode = '23514';
    end if;
    if attachment_record.object_state <> 'STORED' then
        raise exception 'Only a stored pending Attachment can complete validation' using errcode = '23514';
    end if;

    if p_outcome = 'AVAILABLE' then
        update public.clinical_attachments set
            validation_state = 'AVAILABLE', trusted_media_type = p_trusted_media_type,
            trusted_byte_size = p_trusted_byte_size, integrity_algorithm = 'SHA-256',
            integrity_value = p_integrity_value, validation_policy_version = p_validation_policy_version,
            validation_completed_at = completed_at, rejection_code = null
        where id = p_attachment_id;
    else
        update public.clinical_attachments set
            validation_state = 'REJECTED', validation_policy_version = p_validation_policy_version,
            validation_completed_at = completed_at, rejection_code = p_rejection_code,
            object_state = 'DELETE_PENDING', object_state_changed_at = completed_at
        where id = p_attachment_id;
    end if;
    return jsonb_build_object('status', p_outcome, 'idempotent_retry', false);
end;
$$;

revoke all privileges
on function public.complete_clinical_attachment_validation(uuid, uuid, text, text, bigint, bytea, text, text)
from public, anon, authenticated;
grant execute
on function public.complete_clinical_attachment_validation(uuid, uuid, text, text, bigint, bytea, text, text)
to service_role;

create function public.resolve_clinical_attachment_completion_target(
    p_auth_subject uuid,
    p_attachment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare acting_user_id uuid;
declare attachment_record public.clinical_attachments%rowtype;
begin
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth' and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select attachment.* into attachment_record
    from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id
      and attachment.uploaded_by_user_id = acting_user_id;
    if not found then return jsonb_build_object('status', 'DENIED'); end if;
    return jsonb_build_object(
        'status', 'PERMITTED',
        'attachment_id', attachment_record.id,
        'storage_object_id', attachment_record.storage_object_id,
        'validation_state', attachment_record.validation_state,
        'object_state', attachment_record.object_state,
        'removed', attachment_record.removed_at is not null
    );
end;
$$;

revoke all privileges
on function public.resolve_clinical_attachment_completion_target(uuid, uuid)
from public, anon, authenticated;
grant execute
on function public.resolve_clinical_attachment_completion_target(uuid, uuid)
to service_role;

create function public.remove_draft_clinical_attachment(
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
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
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
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id for update;
    select entry_row.* into record_entry from public.clinical_record_entries as entry_row
    where entry_row.id = record_entry.id for update;
    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id for update;
    if attachment_record.removed_at is not null then
        return jsonb_build_object('attachment_id', attachment_record.id,
            'storage_object_id', attachment_record.storage_object_id,
            'object_state', attachment_record.object_state, 'idempotent_retry', true);
    end if;
    if record_entry.lifecycle_state <> 'DRAFT' then
        raise exception 'Only a DRAFT Entry Attachment may be removed' using errcode = '23514';
    end if;
    if encounter_record.lifecycle_state = 'CONCLUDED' and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care Attachment removal requires the Care Authorization to remain ACTIVE'
            using errcode = '42501';
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
$$;

revoke all privileges on function public.remove_draft_clinical_attachment(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.remove_draft_clinical_attachment(uuid, uuid) to service_role;

create function public.claim_clinical_attachment_maintenance(p_limit integer default 25)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    bounded_limit integer;
    candidate record;
    attachment_record public.clinical_attachments%rowtype;
    result_payload jsonb := '[]'::jsonb;
    operation_timestamp timestamptz := clock_timestamp();
begin
    if p_limit is null or p_limit < 1 then raise exception 'Maintenance limit must be positive' using errcode = '22023'; end if;
    bounded_limit := least(p_limit, 50);
    for candidate in
        select attachment.id, attachment.clinical_record_entry_id
        from public.clinical_attachments as attachment
        where attachment.object_state <> 'DELETED'
          and (
              (attachment.validation_state = 'PENDING' and attachment.object_state = 'STORED')
              or (attachment.validation_state = 'PENDING' and attachment.upload_stale_after <= operation_timestamp)
              or attachment.validation_state = 'REJECTED'
              or attachment.removed_at is not null
          )
        order by attachment.upload_stale_after, attachment.id
        limit bounded_limit
    loop
        perform 1 from public.clinical_record_entries as entry_row
        where entry_row.id = candidate.clinical_record_entry_id for update;
        select attachment.* into attachment_record from public.clinical_attachments as attachment
        where attachment.id = candidate.id for update skip locked;
        if not found then continue; end if;
        if attachment_record.validation_state = 'PENDING'
           and attachment_record.object_state = 'STORED'
           and attachment_record.removed_at is null then
            result_payload := result_payload || jsonb_build_array(jsonb_build_object(
                'action', 'VALIDATE', 'attachment_id', attachment_record.id,
                'storage_object_id', attachment_record.storage_object_id));
        elsif attachment_record.validation_state = 'PENDING'
           and attachment_record.object_state = 'AWAITING_UPLOAD'
           and attachment_record.removed_at is null
           and attachment_record.upload_stale_after <= operation_timestamp then
            result_payload := result_payload || jsonb_build_array(jsonb_build_object(
                'action', 'RECONCILE', 'attachment_id', attachment_record.id,
                'storage_object_id', attachment_record.storage_object_id));
        elsif attachment_record.removed_at is not null
           or attachment_record.validation_state = 'REJECTED' then
            if attachment_record.object_state <> 'DELETE_PENDING' then
                update public.clinical_attachments set object_state = 'DELETE_PENDING',
                    object_state_changed_at = operation_timestamp
                where id = attachment_record.id returning * into attachment_record;
            end if;
            result_payload := result_payload || jsonb_build_array(jsonb_build_object(
                'action', 'DELETE', 'attachment_id', attachment_record.id,
                'storage_object_id', attachment_record.storage_object_id));
        end if;
    end loop;
    return result_payload;
end;
$$;

revoke all privileges on function public.claim_clinical_attachment_maintenance(integer)
from public, anon, authenticated;
grant execute on function public.claim_clinical_attachment_maintenance(integer) to service_role;

-- Called only after trusted Edge maintenance has checked the exact private
-- Storage path and established that no object exists. PostgreSQL deliberately
-- does not inspect Storage when making this stale-upload transition.
create function public.expire_missing_stale_clinical_attachment_upload(
    p_attachment_id uuid,
    p_storage_object_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    attachment_record public.clinical_attachments%rowtype;
    operation_timestamp timestamptz := clock_timestamp();
begin
    perform 1 from public.clinical_record_entries as entry_row
    join public.clinical_attachments as attachment
      on attachment.clinical_record_entry_id = entry_row.id
    where attachment.id = p_attachment_id
    for update of entry_row;
    select attachment.* into attachment_record
    from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id
    for update;
    if not found then
        raise exception 'Clinical Attachment does not exist' using errcode = '23503';
    end if;
    if attachment_record.storage_object_id is distinct from p_storage_object_id then
        raise exception 'Storage object identity does not match Attachment' using errcode = '23514';
    end if;
    if attachment_record.validation_state = 'REJECTED'
       and attachment_record.rejection_code = 'UPLOAD_STALE'
       and attachment_record.object_state = 'DELETED' then
        return jsonb_build_object('status', 'REJECTED', 'idempotent_retry', true);
    end if;
    if attachment_record.validation_state is distinct from 'PENDING'
       or attachment_record.object_state is distinct from 'AWAITING_UPLOAD'
       or attachment_record.removed_at is not null
       or attachment_record.upload_stale_after > operation_timestamp then
        raise exception 'Attachment is not an eligible missing stale upload'
            using errcode = '23514';
    end if;
    update public.clinical_attachments set
        validation_state = 'REJECTED',
        validation_policy_version = 'phase1-pdf-v1',
        validation_completed_at = operation_timestamp,
        rejection_code = 'UPLOAD_STALE',
        object_state = 'DELETED',
        object_state_changed_at = operation_timestamp
    where id = p_attachment_id;
    return jsonb_build_object('status', 'REJECTED', 'idempotent_retry', false);
end;
$$;

revoke all privileges
on function public.expire_missing_stale_clinical_attachment_upload(uuid, uuid)
from public, anon, authenticated;
grant execute
on function public.expire_missing_stale_clinical_attachment_upload(uuid, uuid)
to service_role;

create function public.mark_clinical_attachment_object_deleted(
    p_attachment_id uuid,
    p_storage_object_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare attachment_record public.clinical_attachments%rowtype;
begin
    perform 1 from public.clinical_record_entries as entry_row
    join public.clinical_attachments as attachment on attachment.clinical_record_entry_id = entry_row.id
    where attachment.id = p_attachment_id for update of entry_row;
    select attachment.* into attachment_record from public.clinical_attachments as attachment
    where attachment.id = p_attachment_id for update;
    if not found then raise exception 'Clinical Attachment does not exist' using errcode = '23503'; end if;
    if attachment_record.storage_object_id is distinct from p_storage_object_id then
        raise exception 'Storage object identity does not match Attachment' using errcode = '23514';
    end if;
    if attachment_record.object_state = 'DELETED' then return; end if;
    if attachment_record.object_state <> 'DELETE_PENDING'
       or (attachment_record.removed_at is null and attachment_record.validation_state <> 'REJECTED') then
        raise exception 'Only inaccessible cleanup-pending Attachment objects may be marked deleted'
            using errcode = '23514';
    end if;
    update public.clinical_attachments set object_state = 'DELETED', object_state_changed_at = clock_timestamp()
    where id = p_attachment_id;
end;
$$;

revoke all privileges on function public.mark_clinical_attachment_object_deleted(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.mark_clinical_attachment_object_deleted(uuid, uuid) to service_role;

-- Direct finalization and the existing client finalizer share the same trigger
-- guard. The function body is retained verbatim except for stable Attachment
-- locking and explicit pending/missing-object checks before the state update.
create or replace function public.finalize_clinical_record_entry(
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
    attachment_record public.clinical_attachments%rowtype;
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
    for attachment_record in
        select attachment.* from public.clinical_attachments as attachment
        where attachment.clinical_record_entry_id = p_entry_id and attachment.removed_at is null
        order by attachment.id for update
    loop
        if attachment_record.validation_state = 'PENDING' then
            raise exception 'A Clinical Record Entry with a current PENDING Attachment cannot be finalized'
                using errcode = '23514';
        end if;
        if attachment_record.validation_state = 'AVAILABLE' and not exists (
            select 1 from storage.objects as object_record
            where object_record.bucket_id = 'clinical-attachments'
              and object_record.name = 'v1/' || attachment_record.storage_object_id::text
        ) then
            raise exception 'A current AVAILABLE Attachment is missing its Storage object'
                using errcode = '23514';
        end if;
    end loop;
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

-- Extend the typed medical-audit chain through Attachment -> Entry -> Encounter.
alter table public.medical_access_audit_events
add column clinical_attachment_id uuid,
add constraint medical_access_audit_events_clinical_attachment_id_fkey
    foreign key (clinical_attachment_id) references public.clinical_attachments (id)
    on update no action on delete restrict,
add constraint medical_access_audit_events_attachment_operation_shape_check
    check (
        (operation = 'VIEW_CLINICAL_ATTACHMENT' and clinical_attachment_id is not null)
        or (operation <> 'VIEW_CLINICAL_ATTACHMENT' and clinical_attachment_id is null)
    );

drop trigger medical_access_audit_events_typed_resource_coherence
on public.medical_access_audit_events;

drop function public.enforce_medical_access_audit_typed_resource_coherence();
drop function public.assert_medical_access_audit_typed_resource_coherence(
    uuid, text, uuid, uuid, uuid, uuid, uuid
);

create function public.assert_medical_access_audit_typed_resource_coherence(
    p_pet_id uuid,
    p_operation text,
    p_care_authorization_id uuid,
    p_appointment_id uuid,
    p_clinical_encounter_id uuid,
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
    encounter_pet_id uuid;
    encounter_care_authorization_id uuid;
    encounter_appointment_id uuid;
    record_entry_encounter_id uuid;
    amendment_original_entry_id uuid;
    attachment_entry_id uuid;
begin
    if p_operation = 'VIEW_CLINICAL_RECORD_ENTRY'
       and (p_clinical_encounter_id is null or p_clinical_record_entry_id is null) then
        raise exception 'VIEW_CLINICAL_RECORD_ENTRY Audit Event requires typed Encounter and Entry references'
            using errcode = '23514';
    end if;
    if p_operation = 'VIEW_CLINICAL_ATTACHMENT'
       and (p_clinical_attachment_id is null
            or p_clinical_record_entry_id is null
            or p_clinical_encounter_id is null) then
        raise exception 'VIEW_CLINICAL_ATTACHMENT Audit Event requires typed Attachment, Entry, and Encounter references'
            using errcode = '23514';
    end if;
    if p_clinical_attachment_id is not null and p_operation <> 'VIEW_CLINICAL_ATTACHMENT' then
        raise exception 'Only VIEW_CLINICAL_ATTACHMENT may carry an Attachment reference'
            using errcode = '23514';
    end if;

    if p_clinical_encounter_id is not null then
        select encounter_row.pet_id, encounter_row.care_authorization_id, encounter_row.appointment_id
        into encounter_pet_id, encounter_care_authorization_id, encounter_appointment_id
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
        select entry_row.clinical_encounter_id into record_entry_encounter_id
        from public.clinical_record_entries as entry_row
        where entry_row.id = p_clinical_record_entry_id;
        if not found then raise exception 'Referenced Clinical Record Entry does not exist' using errcode = '23503'; end if;
        if record_entry_encounter_id is distinct from p_clinical_encounter_id then
            raise exception 'Audit Event Entry must belong to its supplied Encounter' using errcode = '23514';
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
on function public.assert_medical_access_audit_typed_resource_coherence(
    uuid, text, uuid, uuid, uuid, uuid, uuid, uuid
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
        new.pet_id, new.operation, new.care_authorization_id, new.appointment_id,
        new.clinical_encounter_id, new.clinical_record_entry_id,
        new.clinical_amendment_id, new.clinical_attachment_id
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
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
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
        veterinarian_clinic_assignment_id, clinical_encounter_id,
        clinical_record_entry_id, clinical_amendment_id, clinical_attachment_id
    ) values (
        p_occurred_at, p_operation, p_outcome, p_actor_context, p_protected_resource_scope,
        p_acting_user_id, p_pet_id, p_guardianship_id, p_care_authorization_id,
        p_accessing_clinic_id, p_accessing_organization_id, p_appointment_id,
        p_organization_membership_id, p_organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id, p_clinical_encounter_id,
        p_clinical_record_entry_id, p_clinical_amendment_id, p_clinical_attachment_id
    ) returning id into new_event_id;
    return new_event_id;
end;
$$;

revoke all privileges
on function public.establish_medical_access_audit_event(
    uuid, uuid, text, text, text, text, timestamptz,
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
)
from public, anon, authenticated;

create function public.authorize_clinical_attachment_download(
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
        case when professional_context_available then professional_context.organization_membership_id else null end,
        case when professional_context_available then professional_context.organization_responsibility_grant_id else null end,
        case when professional_context_available then professional_context.veterinarian_clinic_assignment_id else null end,
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
on function public.authorize_clinical_attachment_download(uuid, uuid, text, text, uuid, uuid, uuid)
from public, anon, authenticated;
grant execute
on function public.authorize_clinical_attachment_download(uuid, uuid, text, text, uuid, uuid, uuid)
to service_role;

-- Narrow metadata projection used only after an existing protected read has
-- already authorized and audited the enclosing clinical information.
create function public.clinical_attachment_metadata_for_entry(
    p_entry_id uuid,
    p_include_workflow boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(
        case when p_include_workflow then jsonb_build_object(
            'id', attachment.id,
            'original_filename', attachment.original_filename,
            'created_at', attachment.created_at,
            'validation_state', attachment.validation_state,
            'object_state', attachment.object_state,
            'validation_completed_at', attachment.validation_completed_at,
            'rejection_code', attachment.rejection_code
        ) else jsonb_build_object(
            'id', attachment.id,
            'original_filename', attachment.original_filename,
            'created_at', attachment.created_at,
            'trusted_media_type', attachment.trusted_media_type,
            'trusted_byte_size', attachment.trusted_byte_size,
            'validation_completed_at', attachment.validation_completed_at
        ) end order by attachment.created_at, attachment.id
    ), '[]'::jsonb)
    from public.clinical_attachments as attachment
    where attachment.clinical_record_entry_id = p_entry_id
      and attachment.removed_at is null
      and (p_include_workflow or (
          attachment.validation_state = 'AVAILABLE' and attachment.object_state = 'STORED'
      ));
$$;

revoke all privileges on function public.clinical_attachment_metadata_for_entry(uuid, boolean)
from public, anon, authenticated;

create function public.decorate_clinical_attachment_read(
    p_result jsonb,
    p_read_kind text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare decorated_entries jsonb;
declare payload jsonb;
begin
    if p_result ->> 'status' <> 'PERMITTED' then return p_result; end if;
    if p_read_kind in ('HISTORY', 'WORK') then
        select coalesce(jsonb_agg(entry_value || jsonb_build_object(
            'attachments', public.clinical_attachment_metadata_for_entry(
                (entry_value ->> 'id')::uuid, p_read_kind = 'WORK'
            )
        ) order by ordinal), '[]'::jsonb)
        into decorated_entries
        from jsonb_array_elements(p_result #> '{payload,entries}') with ordinality as item(entry_value, ordinal);
        return jsonb_set(p_result, '{payload,entries}', decorated_entries, false);
    elsif p_read_kind = 'ENTRY' then
        payload := p_result -> 'payload';
        return jsonb_set(p_result, '{payload}', payload || jsonb_build_object(
            'attachments', public.clinical_attachment_metadata_for_entry(
                (payload ->> 'id')::uuid, payload ->> 'lifecycle_state' = 'DRAFT'
            )
        ), false);
    end if;
    raise exception 'Unknown Attachment read decoration kind' using errcode = '22023';
end;
$$;

revoke all privileges on function public.decorate_clinical_attachment_read(jsonb, text)
from public, anon, authenticated;

-- Preserve the exact deployed Slice-12 read implementations as private bases;
-- the same public signatures add only an `attachments` JSON property.
alter function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
rename to slice12_view_guardian_pet_medical_history;
revoke all privileges
on function public.slice12_view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
from public, anon, authenticated;

create function public.view_guardian_pet_medical_history(
    p_pet_id uuid,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb language sql security definer set search_path = ''
as $$
    select public.decorate_clinical_attachment_read(
        public.slice12_view_guardian_pet_medical_history(
            p_pet_id, p_limit, p_before_history_order_at, p_before_entry_id
        ), 'HISTORY'
    );
$$;
revoke all privileges
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
from public, anon, authenticated;
grant execute
on function public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)
to authenticated;

alter function public.view_professional_pet_medical_history(
    uuid, uuid, uuid, uuid, integer, timestamptz, uuid
) rename to slice12_view_professional_pet_medical_history;
revoke all privileges
on function public.slice12_view_professional_pet_medical_history(
    uuid, uuid, uuid, uuid, integer, timestamptz, uuid
) from public, anon, authenticated;

create function public.view_professional_pet_medical_history(
    p_pet_id uuid,
    p_accessing_clinic_id uuid,
    p_care_authorization_id uuid,
    p_clinical_encounter_id uuid default null,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb language sql security definer set search_path = ''
as $$
    select public.decorate_clinical_attachment_read(
        public.slice12_view_professional_pet_medical_history(
            p_pet_id, p_accessing_clinic_id, p_care_authorization_id,
            p_clinical_encounter_id, p_limit, p_before_history_order_at, p_before_entry_id
        ), 'HISTORY'
    );
$$;
revoke all privileges
on function public.view_professional_pet_medical_history(
    uuid, uuid, uuid, uuid, integer, timestamptz, uuid
) from public, anon, authenticated;
grant execute
on function public.view_professional_pet_medical_history(
    uuid, uuid, uuid, uuid, integer, timestamptz, uuid
) to authenticated;

alter function public.view_care_authorization_clinical_work_context(
    uuid, uuid, integer, timestamptz, uuid
) rename to slice12_view_care_authorization_clinical_work_context;
revoke all privileges
on function public.slice12_view_care_authorization_clinical_work_context(
    uuid, uuid, integer, timestamptz, uuid
) from public, anon, authenticated;

create function public.view_care_authorization_clinical_work_context(
    p_care_authorization_id uuid,
    p_clinical_encounter_id uuid default null,
    p_limit integer default 50,
    p_before_created_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb language sql security definer set search_path = ''
as $$
    select public.decorate_clinical_attachment_read(
        public.slice12_view_care_authorization_clinical_work_context(
            p_care_authorization_id, p_clinical_encounter_id, p_limit,
            p_before_created_at, p_before_entry_id
        ), 'WORK'
    );
$$;
revoke all privileges
on function public.view_care_authorization_clinical_work_context(
    uuid, uuid, integer, timestamptz, uuid
) from public, anon, authenticated;
grant execute
on function public.view_care_authorization_clinical_work_context(
    uuid, uuid, integer, timestamptz, uuid
) to authenticated;

alter function public.view_clinical_record_entry(uuid)
rename to slice12_view_clinical_record_entry;
revoke all privileges on function public.slice12_view_clinical_record_entry(uuid)
from public, anon, authenticated;

create function public.view_clinical_record_entry(p_entry_id uuid)
returns jsonb language sql security definer set search_path = ''
as $$
    select public.decorate_clinical_attachment_read(
        public.slice12_view_clinical_record_entry(p_entry_id), 'ENTRY'
    );
$$;
revoke all privileges on function public.view_clinical_record_entry(uuid)
from public, anon, authenticated;
grant execute on function public.view_clinical_record_entry(uuid) to authenticated;

alter table public.clinical_attachments enable row level security;
revoke all privileges on table public.clinical_attachments from public, anon, authenticated;

commit;

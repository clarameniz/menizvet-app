-- Run only against an isolated database with all source-controlled migrations
-- applied. Fixtures and assertions are rolled back; superuser test execution
-- is required solely to bypass unrelated establishment triggers while loading
-- deliberately minimal deterministic context. Since
-- 20261113090000_appointment_owned_clinical_documentation.sql the Attachment's
-- Entry belongs to an Appointment (SPEC-MED-010 BR-1, BR-19); since
-- 20261115090000_retire_professional_attachment_routes.sql (stage M4) the only
-- download authorization is the Guardian one, and the professional upload,
-- completion, removal, and download operations no longer exist.
begin;

create function pg_temp.assert_sqlstate(p_statement text, p_expected text)
returns void
language plpgsql
as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected then return; end if;
        raise exception 'Expected SQLSTATE %, received %: %', p_expected, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected;
end;
$$;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

set local session_replication_role = replica;

insert into auth.users (id, email_confirmed_at) values
    ('13000000-0000-4000-8000-000000000001', '2020-01-01Z'),
    ('13000000-0000-4000-8000-000000000101', '2020-01-01Z');
insert into public.users (id) values
    ('13000000-0000-4000-8000-000000000002'),
    ('13000000-0000-4000-8000-000000000003');
insert into public.user_authentication_identities (user_id, provider_subject) values
    (
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-000000000001'
    ),
    (
        '13000000-0000-4000-8000-000000000003',
        '13000000-0000-4000-8000-000000000101'
    );
insert into public.veterinary_organizations (id, display_name)
values ('13000000-0000-4000-8000-000000000004', 'Slice 13 Test Organization');
insert into public.clinics (id, organization_id)
values (
    '13000000-0000-4000-8000-000000000005',
    '13000000-0000-4000-8000-000000000004'
);
insert into public.organization_memberships (
    id, organization_id, user_id, effective_start
) values
    (
        '13000000-0000-4000-8000-000000000006',
        '13000000-0000-4000-8000-000000000004',
        '13000000-0000-4000-8000-000000000002', '2020-01-01Z'
    ),
    (
        '13000000-0000-4000-8000-000000000007',
        '13000000-0000-4000-8000-000000000004',
        '13000000-0000-4000-8000-000000000003', '2020-01-01Z'
    );
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, effective_start,
    granted_by_user_id
) values (
    '13000000-0000-4000-8000-000000000018',
    '13000000-0000-4000-8000-000000000006',
    'VETERINARIAN', 'ORGANIZATION', '2020-01-01Z',
    '13000000-0000-4000-8000-000000000002'
);
insert into public.organization_subscriptions (
    id, organization_id, established_at, initiated_by_user_id,
    initial_state, initial_state_effective_at,
    initial_commercial_valid_from, initial_commercial_valid_until,
    establishment_source, establishment_idempotency_key
) values (
    '13000000-0000-4000-8000-000000000019',
    '13000000-0000-4000-8000-000000000004',
    '2020-01-01Z', '13000000-0000-4000-8000-000000000002',
    'ACTIVE', '2020-01-01Z', '2020-01-01Z', '2099-01-01Z',
    'slice13-guardian-download-hotfix', gen_random_uuid()
);
insert into public.veterinarian_professional_profiles (id, user_id) values
    ('13000000-0000-4000-8000-000000000008', '13000000-0000-4000-8000-000000000002'),
    ('13000000-0000-4000-8000-000000000009', '13000000-0000-4000-8000-000000000003');
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start
) values
    (
        '13000000-0000-4000-8000-00000000000a',
        '13000000-0000-4000-8000-000000000008',
        '13000000-0000-4000-8000-000000000006',
        '13000000-0000-4000-8000-000000000005', '2020-01-01Z'
    ),
    (
        '13000000-0000-4000-8000-00000000000b',
        '13000000-0000-4000-8000-000000000009',
        '13000000-0000-4000-8000-000000000007',
        '13000000-0000-4000-8000-000000000005', '2020-01-01Z'
    );
insert into public.pets (id, name, species, created_at) values
    ('13000000-0000-4000-8000-00000000000c', 'Patient', 'canine', '2020-01-01Z'),
    ('13000000-0000-4000-8000-00000000000f', 'Other Patient', 'feline', '2020-01-01Z');
-- User ...002 guards the Patient. User ...003, a Veterinarian of the same
-- Clinic, guards only another Pet: neither standing reaches the Patient's
-- Attachments through the Guardian route.
insert into public.guardianships (id, user_id, pet_id, effective_start) values
    (
        '13000000-0000-4000-8000-00000000000d',
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-00000000000c', '2020-01-01Z'
    ),
    (
        '13000000-0000-4000-8000-00000000001b',
        '13000000-0000-4000-8000-000000000003',
        '13000000-0000-4000-8000-00000000000f', '2020-01-01Z'
    );
insert into public.care_authorizations (
    id, pet_id, clinic_id, organization_id, granting_guardianship_id,
    granted_at, purpose, appointment_id, lifecycle_state
) values (
    '13000000-0000-4000-8000-00000000000e',
    '13000000-0000-4000-8000-00000000000c',
    '13000000-0000-4000-8000-000000000005',
    '13000000-0000-4000-8000-000000000004',
    '13000000-0000-4000-8000-00000000000d', '2020-01-01Z',
    'APPOINTMENT_CARE', '13000000-0000-4000-8000-000000000100', 'ACTIVE'
);
-- The CONFIRMED Appointment the Entries belong to (its Care Authorization
-- is ACTIVE, so it also roots LONGITUDINAL access, SPEC-MED-010 BR-14).
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
values (
    '13000000-0000-4000-8000-000000000100',
    '13000000-0000-4000-8000-00000000000c',
    '13000000-0000-4000-8000-000000000005',
    '13000000-0000-4000-8000-000000000002', 'Check-up', 'CONFIRMED', '2020-01-01Z'
);
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context,
    scheduled_start_at, scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
values
    ('13000000-0000-4000-8000-000000000100', 1, 'REQUESTED', '2020-01-05T10:00Z', '2020-01-05T10:30Z', 'Europe/Madrid',
     '13000000-0000-4000-8000-000000000002', null, '2020-01-01Z'),
    ('13000000-0000-4000-8000-000000000100', 2, 'CONFIRMED', '2020-01-05T10:00Z', '2020-01-05T10:30Z', 'Europe/Madrid',
     '13000000-0000-4000-8000-000000000002', null, '2020-01-02Z');
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
values ('13000000-0000-4000-8000-000000000100', 'REQUESTED', 'CONFIRMED', '13000000-0000-4000-8000-000000000002',
        'CLINIC', null, '2020-01-02Z', '2020-01-02Z');
insert into public.clinical_record_entries (
    id, appointment_id, created_by_user_id,
    creator_veterinarian_clinic_assignment_id, created_at,
    clinical_content, category, creation_idempotency_key, creation_request_digest
) values (
    '13000000-0000-4000-8000-000000000010',
    '13000000-0000-4000-8000-000000000100',
    '13000000-0000-4000-8000-000000000002',
    '13000000-0000-4000-8000-00000000000a',
    '2020-01-01Z', 'Note with pending uploads', 'CLINICAL_NOTE', gen_random_uuid(), sha256('e10'::bytea)
);
insert into public.clinical_record_entries (
    id, appointment_id, created_by_user_id,
    creator_veterinarian_clinic_assignment_id, created_at,
    clinical_content, category, creation_idempotency_key, creation_request_digest
) values (
    '13000000-0000-4000-8000-000000000011',
    '13000000-0000-4000-8000-000000000100',
    '13000000-0000-4000-8000-000000000002',
    '13000000-0000-4000-8000-00000000000a',
    '2020-01-01Z', 'Final note', 'CLINICAL_NOTE', gen_random_uuid(), sha256('e11'::bytea)
);

insert into public.clinical_attachments (
    id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id,
    created_at, upload_idempotency_key, storage_object_id,
    upload_stale_after, validation_state, object_state
) values
    (
        '13000000-0000-4000-8000-000000000012',
        '13000000-0000-4000-8000-000000000010',
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
        gen_random_uuid(), '13000000-0000-4000-8000-000000000112',
        '2021-01-01Z', 'PENDING', 'STORED'
    ),
    (
        '13000000-0000-4000-8000-000000000013',
        '13000000-0000-4000-8000-000000000010',
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
        gen_random_uuid(), '13000000-0000-4000-8000-000000000113',
        '2021-01-01Z', 'PENDING', 'STORED'
    ),
    (
        '13000000-0000-4000-8000-000000000014',
        '13000000-0000-4000-8000-000000000010',
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
        gen_random_uuid(), '13000000-0000-4000-8000-000000000114',
        '2020-01-02Z', 'PENDING', 'AWAITING_UPLOAD'
    ),
    (
        '13000000-0000-4000-8000-000000000015',
        '13000000-0000-4000-8000-000000000010',
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
        gen_random_uuid(), '13000000-0000-4000-8000-000000000115',
        '2020-01-02Z', 'PENDING', 'AWAITING_UPLOAD'
    ),
    (
        '13000000-0000-4000-8000-000000000016',
        '13000000-0000-4000-8000-000000000010',
        '13000000-0000-4000-8000-000000000002',
        '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
        gen_random_uuid(), '13000000-0000-4000-8000-000000000116',
        '2099-01-01Z', 'PENDING', 'AWAITING_UPLOAD'
    );
insert into public.clinical_attachments (
    id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id,
    created_at, upload_idempotency_key, storage_object_id,
    upload_stale_after, validation_state, object_state,
    trusted_media_type, trusted_byte_size, integrity_algorithm,
    integrity_value, validation_policy_version, validation_completed_at
) values (
    '13000000-0000-4000-8000-000000000017',
    '13000000-0000-4000-8000-000000000011',
    '13000000-0000-4000-8000-000000000002',
    '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
    gen_random_uuid(), '13000000-0000-4000-8000-000000000117',
    '2021-01-01Z', 'AVAILABLE', 'STORED', 'application/pdf', 42,
    'SHA-256', decode(repeat('ab', 32), 'hex'), 'phase1-pdf-v1', '2020-01-02Z'
);
insert into public.clinical_attachments (
    id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id,
    created_at, upload_idempotency_key, storage_object_id,
    upload_stale_after, original_filename, validation_state, object_state,
    trusted_media_type, trusted_byte_size, integrity_algorithm,
    integrity_value, validation_policy_version, validation_completed_at
) values (
    '13000000-0000-4000-8000-00000000001a',
    '13000000-0000-4000-8000-000000000011',
    '13000000-0000-4000-8000-000000000002',
    '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
    gen_random_uuid(), '13000000-0000-4000-8000-00000000011a',
    '2021-01-01Z', 'guardian-download.pdf', 'AVAILABLE', 'STORED',
    'application/pdf', 42, 'SHA-256', decode(repeat('ab', 32), 'hex'),
    'phase1-pdf-v1', '2020-01-02Z'
);
-- A PENDING upload whose object is already stored: never released.
insert into public.clinical_attachments (
    id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id,
    created_at, upload_idempotency_key, storage_object_id,
    upload_stale_after, validation_state, object_state
) values (
    '13000000-0000-4000-8000-00000000001c',
    '13000000-0000-4000-8000-000000000011',
    '13000000-0000-4000-8000-000000000002',
    '13000000-0000-4000-8000-00000000000a', '2020-01-01Z',
    gen_random_uuid(), '13000000-0000-4000-8000-00000000011c',
    '2099-01-01Z', 'PENDING', 'STORED'
);
insert into storage.objects (id, bucket_id, name, metadata) values
    (
        '13000000-0000-4000-8000-00000000021a',
        'clinical-attachments',
        'v1/13000000-0000-4000-8000-00000000011a',
        jsonb_build_object('mimetype', 'application/pdf', 'size', 42)
    ),
    (
        '13000000-0000-4000-8000-00000000021c',
        'clinical-attachments',
        'v1/13000000-0000-4000-8000-00000000011c',
        jsonb_build_object('mimetype', 'application/pdf', 'size', 42)
    );

set local session_replication_role = origin;

select pg_temp.assert_sqlstate($statement$
    select public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000012',
        '13000000-0000-4000-8000-000000000112', null, null, null, null,
        'phase1-pdf-v1', 'PDF_PARSE_INVALID'
    )
$statement$, '22023');
select pg_temp.assert_sqlstate($statement$
    select public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000012',
        '13000000-0000-4000-8000-000000000112', 'REJECTED', null, null, null,
        null, 'PDF_PARSE_INVALID'
    )
$statement$, '22023');

select public.complete_clinical_attachment_validation(
    '13000000-0000-4000-8000-000000000012',
    '13000000-0000-4000-8000-000000000112', 'REJECTED', null, null, null,
    'phase1-pdf-v1', 'PDF_PARSE_INVALID'
);
select pg_temp.assert_sqlstate($statement$
    select public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000012',
        '13000000-0000-4000-8000-000000000112', 'REJECTED',
        'application/pdf', 42, decode(repeat('ab', 32), 'hex'),
        'phase1-pdf-v1', 'PDF_PARSE_INVALID'
    )
$statement$, '22023');
select pg_temp.assert_true(
    (public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000012',
        '13000000-0000-4000-8000-000000000112', 'REJECTED', null, null, null,
        'phase1-pdf-v1', 'PDF_PARSE_INVALID'
    ) ->> 'idempotent_retry')::boolean,
    'Exact REJECTED retry must be idempotent'
);
select pg_temp.assert_sqlstate($statement$
    select public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000012',
        '13000000-0000-4000-8000-000000000112', 'REJECTED', null, null, null,
        'phase1-pdf-v1', 'PDF_ENCRYPTED'
    )
$statement$, '23514');

select public.complete_clinical_attachment_validation(
    '13000000-0000-4000-8000-000000000013',
    '13000000-0000-4000-8000-000000000113', 'AVAILABLE',
    'application/pdf', 42, decode(repeat('ab', 32), 'hex'),
    'phase1-pdf-v1', null
);
select pg_temp.assert_true(
    (public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000013',
        '13000000-0000-4000-8000-000000000113', 'AVAILABLE',
        'application/pdf', 42, decode(repeat('ab', 32), 'hex'),
        'phase1-pdf-v1', null
    ) ->> 'idempotent_retry')::boolean,
    'Exact AVAILABLE retry must be idempotent'
);
select pg_temp.assert_sqlstate($statement$
    select public.complete_clinical_attachment_validation(
        '13000000-0000-4000-8000-000000000013',
        '13000000-0000-4000-8000-000000000113', 'AVAILABLE',
        'application/pdf', 42, decode(repeat('cd', 32), 'hex'),
        'phase1-pdf-v1', null
    )
$statement$, '23514');

select pg_temp.assert_true(
    exists (
        select 1
        from jsonb_array_elements(public.claim_clinical_attachment_maintenance(25)) as task
        where task ->> 'action' = 'RECONCILE'
          and task ->> 'attachment_id' = '13000000-0000-4000-8000-000000000014'
    ),
    'Stale uploaded object must be claimed for reconciliation without mutation'
);
select pg_temp.assert_true(
    exists (
        select 1 from public.clinical_attachments
        where id = '13000000-0000-4000-8000-000000000014'
          and validation_state = 'PENDING' and object_state = 'AWAITING_UPLOAD'
    ),
    'Reconciliation claim must not reject a stale upload'
);
select public.mark_clinical_attachment_object_stored(
    '13000000-0000-4000-8000-000000000014',
    '13000000-0000-4000-8000-000000000114'
);
select public.complete_clinical_attachment_validation(
    '13000000-0000-4000-8000-000000000014',
    '13000000-0000-4000-8000-000000000114', 'AVAILABLE',
    'application/pdf', 42, decode(repeat('ab', 32), 'hex'),
    'phase1-pdf-v1', null
);
select pg_temp.assert_true(
    (select validation_state = 'AVAILABLE' from public.clinical_attachments
     where id = '13000000-0000-4000-8000-000000000014'),
    'Uploaded object with lost completion must validate, not delete'
);

select public.expire_missing_stale_clinical_attachment_upload(
    '13000000-0000-4000-8000-000000000015',
    '13000000-0000-4000-8000-000000000115'
);
select pg_temp.assert_true(
    exists (
        select 1 from public.clinical_attachments
        where id = '13000000-0000-4000-8000-000000000015'
          and validation_state = 'REJECTED' and rejection_code = 'UPLOAD_STALE'
          and object_state = 'DELETED'
    ),
    'Confirmed missing stale upload must establish exact terminal state'
);

select pg_temp.assert_sqlstate($statement$
    update public.clinical_attachments set
        removed_at = clock_timestamp(),
        removed_by_user_id = '13000000-0000-4000-8000-000000000003',
        removed_by_vca_id = '13000000-0000-4000-8000-00000000000a',
        object_state = 'DELETE_PENDING', object_state_changed_at = clock_timestamp()
    where id = '13000000-0000-4000-8000-000000000016'
$statement$, '23514');

do $$
declare
    audit_count_before bigint;
    audit_count_after bigint;
begin
    select count(*) into audit_count_before from public.medical_access_audit_events;
    perform pg_temp.assert_sqlstate($statement$
        select public.authorize_guardian_clinical_attachment_download(
            '13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000017'
        )
    $statement$, 'XX001');
    select count(*) into audit_count_after from public.medical_access_audit_events;
    perform pg_temp.assert_true(
        audit_count_after = audit_count_before,
        'Missing AVAILABLE object must not create a false DENIED audit'
    );
end;
$$;

-- Guardian PERMITTED must audit without inventing professional provenance.
do $$
declare
    result jsonb;
    audit_count_before bigint;
begin
    select count(*) into audit_count_before
    from public.medical_access_audit_events
    where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
      and acting_user_id = '13000000-0000-4000-8000-000000000002';

    result := public.authorize_guardian_clinical_attachment_download(
        '13000000-0000-4000-8000-000000000001',
        '13000000-0000-4000-8000-00000000001a'
    );

    perform pg_temp.assert_true(
        result = jsonb_build_object(
            'status', 'PERMITTED',
            'attachment_id', '13000000-0000-4000-8000-00000000001a'::uuid,
            'storage_object_id', '13000000-0000-4000-8000-00000000011a'::uuid,
            'original_filename', 'guardian-download.pdf'
        ),
        'Current Guardian must receive exactly the structured PERMITTED result'
    );
    perform pg_temp.assert_true(
        (select count(*) from public.medical_access_audit_events
         where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
           and acting_user_id = '13000000-0000-4000-8000-000000000002')
            = audit_count_before + 1,
        'Guardian PERMITTED access must establish exactly one Attachment audit'
    );
    perform pg_temp.assert_true(
        exists (
            select 1 from public.medical_access_audit_events
            where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
              and clinical_record_entry_id = '13000000-0000-4000-8000-000000000011'
              and appointment_id is null
              and pet_id = '13000000-0000-4000-8000-00000000000c'
              and acting_user_id = '13000000-0000-4000-8000-000000000002'
              and operation = 'VIEW_CLINICAL_ATTACHMENT'
              and outcome = 'PERMITTED'
              and actor_context = 'GUARDIAN'
              and guardianship_id = '13000000-0000-4000-8000-00000000000d'
              and care_authorization_id is null
              and organization_membership_id is null
              and organization_responsibility_grant_id is null
              and veterinarian_clinic_assignment_id is null
              and accessing_clinic_id is null
              and accessing_organization_id is null
        ),
        'Guardian PERMITTED audit provenance must be exact and non-professional'
    );
end;
$$;

-- A Guardian of another Pet - here also a Veterinarian of the Entry's own
-- Clinic, with a current Clinic Assignment - is DENIED, with one durable
-- audit and no fabricated Guardian or professional provenance: neither a
-- Guardianship of another Pet nor professional standing reaches this Pet's
-- Attachments through the Guardian route.
do $$
declare
    result jsonb;
    audit_count_before bigint;
begin
    select count(*) into audit_count_before
    from public.medical_access_audit_events
    where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
      and acting_user_id = '13000000-0000-4000-8000-000000000003';

    result := public.authorize_guardian_clinical_attachment_download(
        '13000000-0000-4000-8000-000000000101',
        '13000000-0000-4000-8000-00000000001a'
    );

    perform pg_temp.assert_true(
        result = jsonb_build_object('status', 'DENIED'),
        'A Guardian of another Pet must receive only structured DENIED'
    );
    perform pg_temp.assert_true(
        (select count(*) from public.medical_access_audit_events
         where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
           and acting_user_id = '13000000-0000-4000-8000-000000000003')
            = audit_count_before + 1,
        'Guardian DENIED access must establish exactly one durable audit'
    );
    perform pg_temp.assert_true(
        exists (
            select 1 from public.medical_access_audit_events
            where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
              and clinical_record_entry_id = '13000000-0000-4000-8000-000000000011'
              and appointment_id is null
              and pet_id = '13000000-0000-4000-8000-00000000000c'
              and acting_user_id = '13000000-0000-4000-8000-000000000003'
              and operation = 'VIEW_CLINICAL_ATTACHMENT'
              and outcome = 'DENIED'
              and actor_context = 'GUARDIAN'
              and guardianship_id is null
              and organization_membership_id is null
              and organization_responsibility_grant_id is null
              and veterinarian_clinic_assignment_id is null
              and accessing_clinic_id is null
              and accessing_organization_id is null
        ),
        'Guardian DENIED audit must not fabricate Guardian or professional provenance'
    );
end;
$$;

-- Only AVAILABLE, STORED, current Attachments are released, even to the
-- current Guardian; an unknown Attachment is DENIED.
do $$
begin
    perform pg_temp.assert_true(
        public.authorize_guardian_clinical_attachment_download(
            '13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-000000000012'
        ) = jsonb_build_object('status', 'DENIED'),
        'A REJECTED Attachment must never be released to a Guardian'
    );
    perform pg_temp.assert_true(
        public.authorize_guardian_clinical_attachment_download(
            '13000000-0000-4000-8000-000000000001',
            '13000000-0000-4000-8000-00000000001c'
        ) = jsonb_build_object('status', 'DENIED'),
        'A PENDING Attachment must never be released to a Guardian, even with its object stored'
    );
    perform pg_temp.assert_true(
        public.authorize_guardian_clinical_attachment_download(
            '13000000-0000-4000-8000-000000000001',
            gen_random_uuid()
        ) = jsonb_build_object('status', 'DENIED'),
        'An unknown Attachment must be DENIED'
    );
end;
$$;

-- A Guardianship that has ended no longer releases anything; the ended one
-- is kept only as audit provenance.
set local session_replication_role = replica;
update public.guardianships set effective_end = clock_timestamp() - interval '1 second'
where id = '13000000-0000-4000-8000-00000000000d';
set local session_replication_role = origin;
do $$
declare result jsonb;
begin
    result := public.authorize_guardian_clinical_attachment_download(
        '13000000-0000-4000-8000-000000000001',
        '13000000-0000-4000-8000-00000000001a'
    );
    perform pg_temp.assert_true(
        result = jsonb_build_object('status', 'DENIED'),
        'An ended Guardianship must not release the Attachment'
    );
    perform pg_temp.assert_true(
        exists (
            select 1 from public.medical_access_audit_events
            where clinical_attachment_id = '13000000-0000-4000-8000-00000000001a'
              and acting_user_id = '13000000-0000-4000-8000-000000000002'
              and outcome = 'DENIED'
              and guardianship_id = '13000000-0000-4000-8000-00000000000d'
        ),
        'The ended Guardianship must be recorded as DENIED audit provenance'
    );
end;
$$;

-- An unknown authentication subject is refused before anything is read.
select pg_temp.assert_sqlstate($statement$
    select public.authorize_guardian_clinical_attachment_download(
        gen_random_uuid(), '13000000-0000-4000-8000-00000000001a'
    )
$statement$, '28000');

-- Stage M4: the professional operations are gone, under every signature.
select pg_temp.assert_true(
    not exists (
        select 1 from pg_proc as procedure_record
        join pg_namespace as namespace_record on namespace_record.oid = procedure_record.pronamespace
        where namespace_record.nspname = 'public'
          and procedure_record.proname in (
              'authorize_clinical_attachment_download', 'initiate_clinical_attachment_upload',
              'resolve_clinical_attachment_completion_target', 'remove_draft_clinical_attachment'
          )
    ),
    'The retired professional Attachment operations must not exist under any signature'
);

-- Exact Guardian signature and trust boundary: no professional context, no
-- Clinic, no Care Authorization, no Encounter.
select pg_temp.assert_true(
    (select count(*) = 1
            and bool_and(pg_get_function_identity_arguments(procedure_record.oid)
                = 'p_auth_subject uuid, p_attachment_id uuid')
     from pg_proc as procedure_record
     join pg_namespace as namespace_record on namespace_record.oid = procedure_record.pronamespace
     where namespace_record.nspname = 'public'
       and procedure_record.proname = 'authorize_guardian_clinical_attachment_download'),
    'Exactly one two-argument Guardian Attachment download authorizer must exist'
);
select pg_temp.assert_true(
    (select procedure_record.prosecdef
            and coalesce(array_to_string(procedure_record.proconfig, ','), '') like '%search_path=%'
            and procedure_record.prosrc !~* 'encounter|care_authorization|professional_scope|accessing_clinic'
     from pg_proc as procedure_record
     where procedure_record.oid = to_regprocedure(
         'public.authorize_guardian_clinical_attachment_download(uuid,uuid)'
     )),
    'The Guardian authorizer must be SECURITY DEFINER, pin its search_path, and take no professional or Encounter input'
);
select pg_temp.assert_true(
    not has_function_privilege('anon', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'execute'),
    'Only service_role may execute the Guardian Attachment download authorizer'
);

rollback;

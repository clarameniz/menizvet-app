-- Regression suite for the Guardian medical-history provenance-names
-- addendum, migration
-- 20260921160000_guardian_medical_history_provenance_names.sql.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied through that migration. All fixtures and assertions are
-- rolled back; superuser test execution is required solely to bypass
-- unrelated establishment triggers/foreign keys while loading a deliberately
-- minimal deterministic context (same rationale as
-- clinical_attachments_slice13_corrections.sql).
--
-- Covers: SPEC-MED-005 BR-5/BR-7/BR-29, confirming
-- public.view_guardian_pet_medical_history now embeds clinic_display_name
-- and organization_display_name per Entry without weakening current-
-- Guardianship authorization, DENIED/non-disclosure behavior, pagination/
-- cursor semantics, amendments, or attachment
-- decoration.
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures: identities
-- ===========================================================================

insert into auth.users (id, email_confirmed_at) values
    ('17000000-0000-4000-8000-000000000001', '2020-01-01Z'), -- Clinic-side author
    ('17000000-0000-4000-8000-000000000002', '2020-01-01Z'), -- Guardian (current)
    ('17000000-0000-4000-8000-000000000003', '2020-01-01Z'); -- Stranger (no Guardianship)
insert into public.users (id) values
    ('17000000-0000-4000-8000-000000000004'),
    ('17000000-0000-4000-8000-000000000005'),
    ('17000000-0000-4000-8000-000000000006');
insert into public.user_authentication_identities (user_id, provider_subject) values
    ('17000000-0000-4000-8000-000000000004', '17000000-0000-4000-8000-000000000001'),
    ('17000000-0000-4000-8000-000000000005', '17000000-0000-4000-8000-000000000002'),
    ('17000000-0000-4000-8000-000000000006', '17000000-0000-4000-8000-000000000003');

-- ===========================================================================
-- Fixtures: Organization, Clinic, and its public profile
-- (display_name lives independently of is_published throughout).
-- ===========================================================================

insert into public.veterinary_organizations (id, display_name)
values ('17000000-0000-4000-8000-000000000007', 'Provenance Test Organization');

insert into public.clinics (id, organization_id, is_published)
values (
    '17000000-0000-4000-8000-000000000008',
    '17000000-0000-4000-8000-000000000007',
    true
);
insert into public.clinic_public_profiles (clinic_id, display_name)
values ('17000000-0000-4000-8000-000000000008', 'Provenance Test Clinic');

insert into public.organization_memberships (
    id, organization_id, user_id, effective_start
) values (
    '17000000-0000-4000-8000-000000000009',
    '17000000-0000-4000-8000-000000000007',
    '17000000-0000-4000-8000-000000000004', '2020-01-01Z'
);
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, effective_start,
    granted_by_user_id
) values (
    '17000000-0000-4000-8000-00000000000a',
    '17000000-0000-4000-8000-000000000009',
    'VETERINARIAN', 'ORGANIZATION', '2020-01-01Z',
    '17000000-0000-4000-8000-000000000004'
);
insert into public.veterinarian_professional_profiles (id, user_id)
values ('17000000-0000-4000-8000-00000000000b', '17000000-0000-4000-8000-000000000004');
insert into public.veterinarian_clinic_assignments (
    id, professional_profile_id, supporting_membership_id, clinic_id,
    effective_start
) values (
    '17000000-0000-4000-8000-00000000000c',
    '17000000-0000-4000-8000-00000000000b',
    '17000000-0000-4000-8000-000000000009',
    '17000000-0000-4000-8000-000000000008', '2020-01-01Z'
);

-- ===========================================================================
-- Fixtures: Pet, Guardianship, Care Authorization
-- ===========================================================================

insert into public.pets (id, name, species, created_at)
values ('17000000-0000-4000-8000-00000000000d', 'Patient', 'canine', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (
    '17000000-0000-4000-8000-00000000000e',
    '17000000-0000-4000-8000-000000000005',
    '17000000-0000-4000-8000-00000000000d', '2020-01-01Z'
);
insert into public.care_authorizations (
    id, pet_id, clinic_id, organization_id, granting_guardianship_id,
    granted_at, purpose, appointment_id, lifecycle_state
) values (
    '17000000-0000-4000-8000-00000000000f',
    '17000000-0000-4000-8000-00000000000d',
    '17000000-0000-4000-8000-000000000008',
    '17000000-0000-4000-8000-000000000007',
    '17000000-0000-4000-8000-00000000000e', '2020-01-01Z',
    'APPOINTMENT_CARE', '17000000-0000-4000-8000-000000000100', 'ACTIVE'
);

-- ===========================================================================
-- Fixtures: two recorded Entries (older/newer, for pagination) of the
-- Appointment, one with an Amendment, one with an AVAILABLE+STORED Attachment
-- and one not-yet-available Attachment (must not appear).
-- ===========================================================================

-- The Appointment the Entries belong to (SPEC-MED-010 BR-1, BR-22).
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
values (
    '17000000-0000-4000-8000-000000000100',
    '17000000-0000-4000-8000-00000000000d',
    '17000000-0000-4000-8000-000000000008',
    '17000000-0000-4000-8000-000000000005', 'Check-up', 'COMPLETED', '2020-01-01Z'
);

-- Older Entry (2020-01-02), with a Clinical Amendment.
insert into public.clinical_record_entries (
    id, appointment_id, created_by_user_id,
    creator_veterinarian_clinic_assignment_id, created_at,
    clinical_content, category, clinical_event_at,
    creation_idempotency_key, creation_request_digest
) values (
    '17000000-0000-4000-8000-000000000011',
    '17000000-0000-4000-8000-000000000100',
    '17000000-0000-4000-8000-000000000004',
    '17000000-0000-4000-8000-00000000000c',
    '2020-01-02Z', 'Older recorded note', 'CLINICAL_NOTE',
    '2020-01-02Z', gen_random_uuid(), sha256('older'::bytea)
);
-- A historical reason-and-addition correction (kind ADDENDUM).
insert into public.clinical_amendments (
    id, original_clinical_record_entry_id, change_kind, reason, amendment_content,
    amending_user_id, amending_veterinarian_clinic_assignment_id, created_at,
    idempotency_key
) values (
    '17000000-0000-4000-8000-000000000012',
    '17000000-0000-4000-8000-000000000011',
    'ADDENDUM', 'Documentation error', 'Corrected content',
    '17000000-0000-4000-8000-000000000004',
    '17000000-0000-4000-8000-00000000000c', '2020-01-03Z',
    gen_random_uuid()
);

-- Newer Entry (2020-02-01), with one visible and one not-yet-available Attachment.
insert into public.clinical_record_entries (
    id, appointment_id, created_by_user_id,
    creator_veterinarian_clinic_assignment_id, created_at,
    clinical_content, category, clinical_event_at,
    creation_idempotency_key, creation_request_digest
) values (
    '17000000-0000-4000-8000-000000000013',
    '17000000-0000-4000-8000-000000000100',
    '17000000-0000-4000-8000-000000000004',
    '17000000-0000-4000-8000-00000000000c',
    '2020-02-01Z', 'Newer recorded note', 'EXAMINATION',
    '2020-02-01Z', gen_random_uuid(), sha256('newer'::bytea)
);
insert into public.clinical_attachments (
    id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id,
    created_at, upload_idempotency_key, storage_object_id,
    upload_stale_after, original_filename, validation_state, object_state,
    trusted_media_type, trusted_byte_size, integrity_algorithm,
    integrity_value, validation_policy_version, validation_completed_at
) values (
    '17000000-0000-4000-8000-000000000014',
    '17000000-0000-4000-8000-000000000013',
    '17000000-0000-4000-8000-000000000004',
    '17000000-0000-4000-8000-00000000000c', '2020-01-01Z',
    gen_random_uuid(), '17000000-0000-4000-8000-000000000114',
    '2021-01-01Z', 'result.pdf', 'AVAILABLE', 'STORED',
    'application/pdf', 42, 'SHA-256', decode(repeat('ab', 32), 'hex'),
    'phase1-pdf-v1', '2020-01-02Z'
);
insert into public.clinical_attachments (
    id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id,
    created_at, upload_idempotency_key, storage_object_id,
    upload_stale_after, validation_state, object_state
) values (
    '17000000-0000-4000-8000-000000000015',
    '17000000-0000-4000-8000-000000000013',
    '17000000-0000-4000-8000-000000000004',
    '17000000-0000-4000-8000-00000000000c', '2020-01-01Z',
    gen_random_uuid(), '17000000-0000-4000-8000-000000000115',
    '2099-01-01Z', 'PENDING', 'AWAITING_UPLOAD'
);

set local session_replication_role = origin;

-- ===========================================================================
-- 1/2/6/7. Permitted Guardian: Clinic + Organization display name present,
-- amendments unchanged, attachment decoration unchanged.
-- ===========================================================================

select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $$
declare
    result jsonb;
    entries jsonb;
    newer_entry jsonb;
    older_entry jsonb;
begin
    result := public.view_guardian_pet_medical_history(
        '17000000-0000-4000-8000-00000000000d', 50, null, null
    );
    perform pg_temp.assert_true(
        result ->> 'status' = 'PERMITTED', 'Expected PERMITTED for the current Guardian'
    );
    entries := result #> '{payload,entries}';
    perform pg_temp.assert_true(jsonb_array_length(entries) = 2, 'Expected exactly two Entries');

    newer_entry := entries -> 0;
    older_entry := entries -> 1;

    perform pg_temp.assert_true(
        newer_entry ->> 'id' = '17000000-0000-4000-8000-000000000013',
        'Expected the newer Entry first (history_order_at desc)'
    );
    perform pg_temp.assert_true(
        newer_entry ->> 'clinic_display_name' = 'Provenance Test Clinic',
        'Expected the Clinic display name on the newer Entry'
    );
    perform pg_temp.assert_true(
        newer_entry ->> 'organization_display_name' = 'Provenance Test Organization',
        'Expected the Organization display name on the newer Entry'
    );
    -- The merge must not clobber pre-existing fields, including ones the
    -- Slice 13 attachment decorator itself added.
    perform pg_temp.assert_true(
        newer_entry ->> 'clinical_content' = 'Newer recorded note',
        'Expected clinical_content to survive the provenance-name merge'
    );
    perform pg_temp.assert_true(
        jsonb_array_length(newer_entry -> 'attachments') = 1,
        'Expected exactly one visible Attachment (AVAILABLE+STORED only)'
    );
    perform pg_temp.assert_true(
        (newer_entry -> 'attachments' -> 0 ->> 'original_filename') = 'result.pdf',
        'Expected the visible Attachment to be the AVAILABLE+STORED one'
    );

    perform pg_temp.assert_true(
        older_entry ->> 'clinic_display_name' = 'Provenance Test Clinic',
        'Expected the Clinic display name on the older Entry too'
    );
    perform pg_temp.assert_true(
        older_entry ->> 'organization_display_name' = 'Provenance Test Organization',
        'Expected the Organization display name on the older Entry too'
    );
    perform pg_temp.assert_true(
        jsonb_array_length(older_entry -> 'amendments') = 1,
        'Expected the Amendment on the older Entry to remain present'
    );
    perform pg_temp.assert_true(
        (older_entry -> 'amendments' -> 0 ->> 'amendment_content') = 'Corrected content',
        'Expected the Amendment content unchanged'
    );
end;
$$;

-- ===========================================================================
-- 5. Pagination/cursor unchanged: p_limit=1 pages through both Entries with
-- the exact same cursor contract as before this migration.
-- ===========================================================================

do $$
declare
    first_page jsonb;
    second_page jsonb;
    cursor_value jsonb;
begin
    first_page := public.view_guardian_pet_medical_history(
        '17000000-0000-4000-8000-00000000000d', 1, null, null
    );
    perform pg_temp.assert_true(
        first_page ->> 'status' = 'PERMITTED', 'Expected PERMITTED on the first page'
    );
    perform pg_temp.assert_true(
        jsonb_array_length(first_page #> '{payload,entries}') = 1,
        'Expected exactly one Entry on the first bounded page'
    );
    perform pg_temp.assert_true(
        (first_page #> '{payload,entries}' -> 0 ->> 'id') = '17000000-0000-4000-8000-000000000013',
        'Expected the newer Entry on the first page'
    );
    perform pg_temp.assert_true(
        (first_page #> '{payload,entries}' -> 0 ->> 'clinic_display_name') = 'Provenance Test Clinic',
        'Expected the Clinic display name on the paginated first page too'
    );
    cursor_value := first_page -> 'cursor';
    -- A JSON `null` cursor is still a non-SQL-NULL jsonb value (`'null'::jsonb`),
    -- so the presence check must test its JSON type, not `IS NOT NULL`.
    perform pg_temp.assert_true(
        jsonb_typeof(cursor_value) = 'object', 'Expected a cursor object for the remaining page'
    );

    second_page := public.view_guardian_pet_medical_history(
        '17000000-0000-4000-8000-00000000000d', 1,
        (cursor_value ->> 'before_history_order_at')::timestamptz,
        (cursor_value ->> 'before_entry_id')::uuid
    );
    perform pg_temp.assert_true(
        jsonb_array_length(second_page #> '{payload,entries}') = 1,
        'Expected exactly one Entry on the second page'
    );
    perform pg_temp.assert_true(
        (second_page #> '{payload,entries}' -> 0 ->> 'id') = '17000000-0000-4000-8000-000000000011',
        'Expected the older Entry on the second page'
    );
    -- Same JSON-null-vs-SQL-null distinction as above: the RPC always
    -- includes the `cursor` key (jsonb_build_object never omits it), so
    -- "no further page" is the JSON null literal, not an absent key.
    perform pg_temp.assert_true(
        (second_page -> 'cursor') = 'null'::jsonb, 'Expected no further page after the second one'
    );
end;
$$;

reset role;

-- ===========================================================================
-- 3. Clinic later unpublished: the historical Entry still returns its Clinic
-- display name (BR-29 — Discovery publication and historical provenance are
-- separate concerns).
-- ===========================================================================

update public.clinics set is_published = false
where id = '17000000-0000-4000-8000-000000000008';

select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $$
declare
    result jsonb;
begin
    result := public.view_guardian_pet_medical_history(
        '17000000-0000-4000-8000-00000000000d', 50, null, null
    );
    perform pg_temp.assert_true(
        result ->> 'status' = 'PERMITTED',
        'Expected PERMITTED unchanged after Clinic unpublication'
    );
    perform pg_temp.assert_true(
        (result #> '{payload,entries}' -> 0 ->> 'clinic_display_name') = 'Provenance Test Clinic',
        'Expected the Clinic display name to survive Clinic unpublication'
    );
end;
$$;

reset role;

-- ===========================================================================
-- 4. DENIED caller (no Guardianship at all) gets only DENIED — no payload,
-- no provenance data, no attachments, nothing beyond the status.
-- ===========================================================================

select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000003', true);
set local role authenticated;

do $$
declare
    result jsonb;
begin
    result := public.view_guardian_pet_medical_history(
        '17000000-0000-4000-8000-00000000000d', 50, null, null
    );
    perform pg_temp.assert_true(result = jsonb_build_object('status', 'DENIED'), 'Expected exactly {"status":"DENIED"} for a Stranger');
end;
$$;

reset role;

rollback;

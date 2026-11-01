-- ============================================================================
-- MenizVet — Punto 8 DEVELOPMENT clinical cleanup: READ-ONLY preflight
--
-- Read-only. Reports the target identity and the exact fingerprint of the rows
-- that punto8_dev_clinical_cleanup.sql would remove, so the operator can
-- compare it with the expected values hard-coded there before running it.
-- Plan: docs/CLINICAL_DOCUMENTATION_TRANSITION.md §3.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto8_dev_clinical_cleanup_preflight_readonly.sql
--
-- Never part of supabase/migrations.
-- ============================================================================

with scope_audit as (
    select id from public.medical_access_audit_events
    where clinical_encounter_id is not null or clinical_record_entry_id is not null
       or clinical_amendment_id is not null or clinical_attachment_id is not null
       or operation in ('ACCESS_FOR_CLINICAL_CARE', 'ACCESS_FOR_POST_CARE_DOCUMENTATION',
                        'VIEW_CLINICAL_RECORD_ENTRY', 'VIEW_CLINICAL_ATTACHMENT')
       or protected_resource_scope in ('ENCOUNTER_MEDICAL_INFORMATION', 'CLINICAL_RECORD_ENTRY',
                                       'CLINICAL_AMENDMENT', 'CLINICAL_ATTACHMENT')
)
select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'encounters', (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
                   from public.clinical_encounters),
    'entries', (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
                from public.clinical_record_entries),
    'amendments', (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
                   from public.clinical_amendments),
    'contributors', (select count(*) from public.clinical_record_entry_contributors),
    'attachments', (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')),
                                              'storage_paths', coalesce(jsonb_agg('v1/' || storage_object_id::text), '[]'))
                    from public.clinical_attachments),
    'clinical_audit_events', (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
                              from scope_audit),
    'audit_events_total', (select count(*) from public.medical_access_audit_events),
    'lifecycle_events_with_encounter', (select count(*) from public.appointment_lifecycle_events
                                        where clinical_encounter_id is not null),
    'storage_objects', (select coalesce(jsonb_agg(name order by name), '[]')
                        from storage.objects where bucket_id = 'clinical-attachments'),
    'retained', jsonb_build_object(
        'users', (select count(*) from public.users),
        'pets', (select count(*) from public.pets),
        'guardianships', (select count(*) from public.guardianships),
        'organizations', (select count(*) from public.veterinary_organizations),
        'clinics', (select count(*) from public.clinics),
        'appointments', (select count(*) from public.appointments),
        'lifecycle_events', (select count(*) from public.appointment_lifecycle_events),
        'schedule_revisions', (select count(*) from public.appointment_schedule_revisions),
        'reschedule_proposals', (select count(*) from public.appointment_reschedule_proposals),
        'veterinarian_assignments', (select count(*) from public.appointment_veterinarian_assignments),
        'care_authorizations', (select count(*) from public.care_authorizations),
        'communications', (select count(*) from public.transactional_communications))
)) as preflight;

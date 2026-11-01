-- ============================================================================
-- MenizVet — Punto 8 stage M5 (20261116090000, editable Clinical Record
-- Entries with preserved versions): READ-ONLY preflight for DEVELOPMENT
--
-- Read-only. Run before `db push`. Reports the target identity, the migration
-- position, the M5 guard conditions and the documentation M5 must preserve:
--   - `m4_contract_present` must be true and `m5_applied` false;
--   - `m5_guard_amendments_not_by_author` must be 0 (M5 refuses otherwise);
--   - the counts are recorded so the postdeploy check can show that nothing
--     was rewritten: every existing Amendment becomes kind ADDENDUM unchanged,
--     every Entry keeps its recorded fields and its clinical event time.
-- Plan: docs/CLINICAL_DOCUMENTATION_TRANSITION.md §15.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto8_dev_m5_preflight_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing. Reports no clinical
-- content: only counts and fingerprints.
-- ============================================================================

select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'm4_contract_present',
        to_regprocedure('public.authorize_guardian_clinical_attachment_download(uuid, uuid)') is not null
        and to_regprocedure('public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean)') is not null,
    'm5_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261116090000')
        or exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'clinical_amendments' and column_name = 'change_kind'),
    -- M5 guard (must be 0).
    'm5_guard_amendments_not_by_author', (
        select count(*) from public.clinical_amendments as amendment
        join public.clinical_record_entries as entry on entry.id = amendment.original_clinical_record_entry_id
        where amendment.amending_user_id <> entry.created_by_user_id),
    -- Preserved documentation (compare with the postdeploy check).
    'entries', (select count(*) from public.clinical_record_entries),
    'entries_with_event_time', (select count(*) from public.clinical_record_entries where clinical_event_at is not null),
    'amendments', (select count(*) from public.clinical_amendments),
    'entries_fingerprint', (select md5(coalesce(string_agg(to_jsonb(entry)::text, '|' order by entry.id), ''))
        from public.clinical_record_entries as entry),
    'amendments_fingerprint', (select md5(coalesce(string_agg(jsonb_build_object(
            'id', amendment.id, 'entry', amendment.original_clinical_record_entry_id, 'reason', amendment.reason,
            'content', amendment.amendment_content, 'user', amendment.amending_user_id,
            'vca', amendment.amending_veterinarian_clinic_assignment_id, 'created_at', amendment.created_at,
            'key', amendment.idempotency_key)::text, '|' order by amendment.id), ''))
        from public.clinical_amendments as amendment),
    'medical_access_audit_events', (select count(*) from public.medical_access_audit_events)
));

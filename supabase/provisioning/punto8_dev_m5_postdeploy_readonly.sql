-- ============================================================================
-- MenizVet — Punto 8 stage M5 (20261116090000): READ-ONLY postdeploy check
-- for DEVELOPMENT
--
-- Read-only. Run after `db push`. Every `*_ok` must be true, and the counts
-- and fingerprints must equal the preflight's
-- (punto8_dev_m5_preflight_readonly.sql): M5 rewrites no Entry and no
-- Amendment, and writes no audit event. `amendments_fingerprint` is computed
-- over the same pre-M5 columns as the preflight. Plan:
-- docs/CLINICAL_DOCUMENTATION_TRANSITION.md §15.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto8_dev_m5_postdeploy_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing. Reports no clinical
-- content: only counts, fingerprints and catalog facts.
-- ============================================================================

select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'm5_recorded_ok', exists (select 1 from supabase_migrations.schema_migrations where version = '20261116090000'),
    -- The client contract: the six-argument record operation and the edit
    -- operation, authenticated only; the timed and reason-and-addition
    -- operations gone; the version helpers internal.
    'contract_ok',
        has_function_privilege('authenticated', 'public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)', 'EXECUTE')
        and has_function_privilege('authenticated', 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)', 'EXECUTE')
        and not has_function_privilege('service_role', 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)', 'EXECUTE')
        and to_regprocedure('public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean)') is null
        and not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                        and proname in ('create_appointment_clinical_amendment', 'create_clinical_amendment')),
    'helpers_private_ok', (
        select bool_and(not has_function_privilege(role_name, helper::regprocedure, 'EXECUTE'))
        from unnest(array['public.clinical_entry_versions(uuid)', 'public.clinical_entry_current(uuid)',
                          'public.clinical_entry_previous_versions(uuid)']) as helper,
             unnest(array['anon', 'authenticated', 'service_role']) as role_name),
    -- Every pre-M5 Amendment is a legacy ADDENDUM; no version exists yet.
    'amendments_all_addendum_ok', not exists (
        select 1 from public.clinical_amendments
        where change_kind <> 'ADDENDUM' or version_number is not null or category is not null),
    -- Compare with the preflight.
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

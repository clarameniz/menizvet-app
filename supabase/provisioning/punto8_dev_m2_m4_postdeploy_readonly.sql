-- ============================================================================
-- MenizVet — Punto 8 M2/M3/M4: READ-ONLY post-deployment verification for
-- DEVELOPMENT
--
-- Read-only. Run right after `db push` and `functions deploy
-- clinical-attachments`. Every `expect_*` value must be true. Plan:
-- docs/CLINICAL_DOCUMENTATION_TRANSITION.md §13.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto8_dev_m2_m4_postdeploy_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing.
-- ============================================================================

select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'expect_stages_applied', (select count(*) = 3 from supabase_migrations.schema_migrations
        where version in ('20261113090000', '20261114090000', '20261115090000')),
    'expect_no_encounter_table', to_regclass('public.clinical_encounters') is null,
    'expect_record_operations_client_only', (select bool_and(
            has_function_privilege('authenticated', signature::regprocedure, 'EXECUTE')
            and not has_function_privilege('anon', signature::regprocedure, 'EXECUTE'))
        from unnest(array[
            'public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)',
            'public.view_appointment_clinical_record(uuid,uuid)',
            'public.create_appointment_clinical_amendment(uuid,uuid,uuid,uuid,text,text)',
            'public.get_appointment_veterinarian_assignment(uuid,uuid)',
            'public.assign_me_to_appointment(uuid,uuid)',
            'public.get_appointment_veterinarian_candidates(uuid,uuid)',
            'public.assign_appointment_veterinarian(uuid,uuid,uuid,uuid)']) as signature),
    'expect_retired_operations_absent', not exists (
        select 1 from pg_proc as p join pg_namespace as n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('start_appointment_clinical_encounter', 'conclude_appointment_clinical_encounter',
                            'create_appointment_clinical_draft', 'update_appointment_clinical_draft',
                            'finalize_appointment_clinical_entry', 'initiate_clinical_attachment_upload',
                            'resolve_clinical_attachment_completion_target', 'remove_draft_clinical_attachment',
                            'authorize_clinical_attachment_download')),
    'expect_guardian_authorizer_service_role_only',
        not has_function_privilege('anon', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'EXECUTE')
        and not has_function_privilege('authenticated', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'EXECUTE')
        and has_function_privilege('service_role', 'public.authorize_guardian_clinical_attachment_download(uuid,uuid)', 'EXECUTE'),
    'expect_no_completed_appointment_with_active_authorization', not exists (
        select 1 from public.appointments as appointment
        join public.care_authorizations as care_auth
          on care_auth.appointment_id = appointment.id and care_auth.purpose = 'APPOINTMENT_CARE'
        where appointment.lifecycle_state = 'COMPLETED' and care_auth.lifecycle_state = 'ACTIVE'),
    'ended_by_completion', (select count(*) from public.care_authorizations
        where ended_reason = 'APPOINTMENT_COMPLETED'),
    'expect_schedule_flag_renamed', exists (
        select 1 from pg_proc as p join pg_namespace as n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'get_clinic_appointment'
          and pg_get_function_result(p.oid) like '%has_clinical_record%'
          and pg_get_function_result(p.oid) not like '%has_clinical_encounter%')
));

-- ============================================================================
-- MenizVet — Punto 8 coordinated deployment of M2 (20261113090000), M3
-- (20261114090000) and M4 (20261115090000): READ-ONLY preflight for
-- DEVELOPMENT
--
-- Read-only. Run before `db push`. Reports the target identity, the migration
-- position, every M2 guard condition (each must be 0), the M3 guard and
-- reconciliation summary (guards 0; `m3_to_end` is the number of ACTIVE Care
-- Authorizations of COMPLETED Appointments that M3 will end), and the M4
-- preconditions (no Attachment row, no Attachment Storage object; the retired
-- operations still present before M4). Plan:
-- docs/CLINICAL_DOCUMENTATION_TRANSITION.md §13. The full M3 row list is in
-- punto8_dev_m3_reconciliation_preflight_readonly.sql.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto8_dev_m2_m4_deploy_preflight_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing.
-- ============================================================================

with completed as (
    select appointment.id as appointment_id,
           care_auth.lifecycle_state,
           care_auth.granted_at,
           (select count(*) from public.care_authorizations as linked
            where linked.appointment_id = appointment.id and linked.purpose = 'APPOINTMENT_CARE') as authorizations,
           (select count(*) from public.appointment_lifecycle_events as completion
            where completion.appointment_id = appointment.id
              and completion.from_state = 'CONFIRMED' and completion.to_state = 'COMPLETED') as completion_events,
           (select max(completion.effective_at) from public.appointment_lifecycle_events as completion
            where completion.appointment_id = appointment.id
              and completion.from_state = 'CONFIRMED' and completion.to_state = 'COMPLETED') as completed_at
    from public.appointments as appointment
    left join public.care_authorizations as care_auth
      on care_auth.appointment_id = appointment.id and care_auth.purpose = 'APPOINTMENT_CARE'
    where appointment.lifecycle_state = 'COMPLETED'
)
select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'pending_punto8_migrations', (select coalesce(jsonb_agg(version order by version), '[]'::jsonb)
        from (values ('20261113090000'), ('20261114090000'), ('20261115090000')) as stage(version)
        where not exists (select 1 from supabase_migrations.schema_migrations as applied
                          where applied.version = stage.version)),
    -- M2 guard (each must be 0).
    'm2_clinical_encounters', (select count(*) from public.clinical_encounters),
    'm2_clinical_record_entries', (select count(*) from public.clinical_record_entries),
    'm2_clinical_amendments', (select count(*) from public.clinical_amendments),
    'm2_clinical_attachments', (select count(*) from public.clinical_attachments),
    'm2_entry_contributors', (select count(*) from public.clinical_record_entry_contributors),
    'm2_retired_clinical_audit_events', (select count(*) from public.medical_access_audit_events
        where clinical_encounter_id is not null or clinical_record_entry_id is not null
           or clinical_amendment_id is not null or clinical_attachment_id is not null
           or operation in ('ACCESS_FOR_CLINICAL_CARE', 'ACCESS_FOR_POST_CARE_DOCUMENTATION',
                            'VIEW_CLINICAL_RECORD_ENTRY', 'VIEW_CLINICAL_ATTACHMENT')
           or protected_resource_scope in ('ENCOUNTER_MEDICAL_INFORMATION', 'CLINICAL_RECORD_ENTRY',
                                           'CLINICAL_AMENDMENT', 'CLINICAL_ATTACHMENT')),
    'm2_lifecycle_events_with_encounter', (select count(*) from public.appointment_lifecycle_events
        where clinical_encounter_id is not null),
    'm2_proposals_voided_by_encounter', (select count(*) from public.appointment_reschedule_proposals
        where void_reason = 'CLINICAL_ENCOUNTER_STARTED'),
    -- M3 guard (each must be 0) and reconciliation size.
    'm3_completed_appointments', (select count(*) from completed),
    'm3_guard_without_exactly_one_authorization', (select count(*) from completed where authorizations <> 1),
    'm3_guard_without_exactly_one_completion_event', (select count(*) from completed where completion_events <> 1),
    'm3_guard_already_ended', (select count(*) from completed where lifecycle_state = 'ENDED'),
    'm3_guard_incoherent_completion_time', (select count(*) from completed
        where lifecycle_state = 'ACTIVE'
          and (completed_at < granted_at or not isfinite(completed_at) or completed_at > clock_timestamp())),
    'm3_to_end', (select count(*) from completed where lifecycle_state = 'ACTIVE'),
    'm3_revoked_kept', (select count(*) from completed where lifecycle_state = 'REVOKED'),
    -- M4 preconditions: nothing for the retired routes to strand.
    'm4_attachment_storage_objects', (select count(*) from storage.objects where bucket_id = 'clinical-attachments'),
    'm4_retired_operations_present', (select coalesce(jsonb_agg(p.proname order by p.proname), '[]'::jsonb)
        from pg_proc as p join pg_namespace as n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('initiate_clinical_attachment_upload', 'resolve_clinical_attachment_completion_target',
                            'remove_draft_clinical_attachment', 'authorize_clinical_attachment_download')),
    'm4_guardian_authorizer_present', to_regprocedure(
        'public.authorize_guardian_clinical_attachment_download(uuid,uuid)') is not null
));

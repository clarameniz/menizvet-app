-- ============================================================================
-- MenizVet — Punto 8 stage M3 (20261114090000): READ-ONLY reconciliation
-- preflight for DEVELOPMENT
--
-- Read-only. Reports the target identity, every guard condition of M3 (each
-- must be 0 for M3 to apply), and the exact Care Authorizations that M3's
-- reconciliation would end with APPOINTMENT_COMPLETED, with the completion
-- time each would receive. REVOKED authorizations are listed separately: M3
-- leaves them unchanged. Plan: docs/CLINICAL_DOCUMENTATION_TRANSITION.md §5.2.
-- Requires M2 to be applied first (M3 must not precede M2).
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto8_dev_m3_reconciliation_preflight_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing.
-- ============================================================================

with completed as (
    select appointment.id as appointment_id,
           care_auth.id as care_authorization_id,
           care_auth.lifecycle_state,
           care_auth.granted_at,
           (select count(*) from public.care_authorizations as linked
            where linked.appointment_id = appointment.id and linked.purpose = 'APPOINTMENT_CARE') as authorizations,
           (select count(*) from public.appointment_lifecycle_events as completion
            where completion.appointment_id = appointment.id
              and completion.from_state = 'CONFIRMED' and completion.to_state = 'COMPLETED') as completion_events,
           (select completion.effective_at from public.appointment_lifecycle_events as completion
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
    'm2_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261113090000'),
    'm3_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261114090000'),
    'completed_appointments', (select count(*) from completed),
    'guard_without_exactly_one_authorization', (select count(*) from completed where authorizations <> 1),
    'guard_without_exactly_one_completion_event', (select count(*) from completed where completion_events <> 1),
    'guard_already_ended', (select count(*) from completed where lifecycle_state = 'ENDED'),
    'guard_incoherent_completion_time', (select count(*) from completed
        where lifecycle_state = 'ACTIVE'
          and (completed_at < granted_at or not isfinite(completed_at) or completed_at > clock_timestamp())),
    'to_end', (select jsonb_build_object(
                   'n', count(*),
                   'md5', md5(coalesce(string_agg(care_authorization_id::text, ',' order by care_authorization_id), '')),
                   'rows', coalesce(jsonb_agg(jsonb_build_object(
                       'care_authorization_id', care_authorization_id,
                       'appointment_id', appointment_id,
                       'ended_at', completed_at) order by care_authorization_id), '[]'::jsonb))
               from completed where lifecycle_state = 'ACTIVE'),
    'revoked_kept', (select jsonb_build_object(
                         'n', count(*),
                         'md5', md5(coalesce(string_agg(care_authorization_id::text, ',' order by care_authorization_id), '')))
                     from completed where lifecycle_state = 'REVOKED'),
    'care_authorizations_by_state', (select jsonb_object_agg(state_key, n) from (
        select lifecycle_state || coalesce(':' || ended_reason, '') as state_key, count(*) as n
        from public.care_authorizations group by 1) as counts)
));

-- ============================================================================
-- MenizVet — Punto 8 DEVELOPMENT clinical cleanup (DESTRUCTIVE, ONE-OFF)
--
-- INTENTIONAL DEVELOPMENT-ONLY SCRIPT. READ BEFORE RUNNING.
--
-- * Removes the disposable clinical test data of the linked DEVELOPMENT project
--   (eqvlydfflfvltprkwcxx, "MenizVet Dev") before migration M2 retires the
--   Clinical Encounter (ADR-011; docs/CLINICAL_DOCUMENTATION_TRANSITION.md §3).
-- * This is NOT a migration and must never be moved into supabase/migrations.
--   It is never auto-run. It can only succeed on DEVELOPMENT with exactly the
--   inventoried rows: the target identity and every row-set fingerprint below
--   are hard-coded and checked before anything is written.
-- * Run, after punto8_dev_clinical_cleanup_preflight_readonly.sql matches:
--       npx supabase db query --linked -f supabase/provisioning/punto8_dev_clinical_cleanup.sql
-- * One DO block = one atomic statement. Any failed check raises and nothing
--   is written. Triggers are never disabled globally: only the five named
--   deletion guards are disabled, inside this statement, while their tables
--   are held under the ACCESS EXCLUSIVE lock that ALTER TABLE takes, and they
--   are re-enabled and verified before the statement ends.
-- * Storage is not transactional: the single Attachment object
--   (clinical-attachments/v1/9bc0625f-ceaf-4c61-8562-0eda1134552f) is removed
--   AFTER this script succeeds, through the Storage API:
--       npx supabase storage rm --linked --experimental \
--         ss:///clinical-attachments/v1/9bc0625f-ceaf-4c61-8562-0eda1134552f
--   then the preflight must report storage_objects = [].
--
-- Removed: 100 clinical-scoped Medical Access Audit Events, 1 Clinical
-- Attachment row, 3 Clinical Amendments, 9 Clinical Record Entries, 8 Clinical
-- Encounters. Retained: everything else, verified unchanged below.
-- ============================================================================

do $cleanup$
declare
    expected_ref constant text := 'eqvlydfflfvltprkwcxx';
    guards constant text[] := array[
        'public.medical_access_audit_events:medical_access_audit_events_preserve_history',
        'public.clinical_attachments:clinical_attachments_prevent_delete',
        'public.clinical_amendments:clinical_amendments_integrity',
        'public.clinical_record_entries:clinical_record_entries_integrity',
        'public.clinical_encounters:clinical_encounters_preserve_history'
    ];
    guard text;
    retained_before jsonb;
    retained_after jsonb;
    authorization_states_before jsonb;
    authorization_states_after jsonb;
    deleted integer;

    -- Fingerprints captured read-only on 2026-10-23 after M1 (md5 of the
    -- comma-joined ordered identifiers, as the preflight computes them).
    expected_encounters constant jsonb := '{"n": 8, "md5": "8ad3b6e90194756708cc9ad92b15509e"}';
    expected_entries constant jsonb := '{"n": 9, "md5": "c09a01bc5945798d6616123ebde290c2"}';
    expected_amendments constant jsonb := '{"n": 3, "md5": "c4eec7d926e3ab59073f9b025c2e3cfb"}';
    expected_attachments constant jsonb := '{"n": 1, "md5": "90c995a2f883248545187fded615ab69"}';
    expected_audit constant jsonb := '{"n": 100, "md5": "b19ef1eeb6770225abd07d742331d658"}';
    expected_retained constant jsonb := '{"users": 24, "pets": 5, "guardianships": 5, "organizations": 6,
        "clinics": 24, "appointments": 25, "lifecycle_events": 35, "schedule_revisions": 59,
        "reschedule_proposals": 21, "veterinarian_assignments": 0, "care_authorizations": 26,
        "communications": 93, "audit_events_kept": 36}';
begin
    -- 1. Target identity ---------------------------------------------------------
    if not exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://' || expected_ref || '.supabase.co/%'
    ) then
        raise exception 'Refusing to run: this database is not DEVELOPMENT project %', expected_ref;
    end if;

    if (select max(version) from supabase_migrations.schema_migrations) <> '20261112090000' then
        raise exception 'Refusing to run: expected last migration 20261112090000 (M1)';
    end if;

    -- 2. Exact scope ---------------------------------------------------------------
    create temporary table punto8_scope_audit on commit drop as
    select id from public.medical_access_audit_events
    where clinical_encounter_id is not null or clinical_record_entry_id is not null
       or clinical_amendment_id is not null or clinical_attachment_id is not null
       or operation in ('ACCESS_FOR_CLINICAL_CARE', 'ACCESS_FOR_POST_CARE_DOCUMENTATION',
                        'VIEW_CLINICAL_RECORD_ENTRY', 'VIEW_CLINICAL_ATTACHMENT')
       or protected_resource_scope in ('ENCOUNTER_MEDICAL_INFORMATION', 'CLINICAL_RECORD_ENTRY',
                                       'CLINICAL_AMENDMENT', 'CLINICAL_ATTACHMENT');

    if (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
        from public.clinical_encounters) <> expected_encounters
       or (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
           from public.clinical_record_entries) <> expected_entries
       or (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
           from public.clinical_amendments) <> expected_amendments
       or (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
           from public.clinical_attachments) <> expected_attachments
       or (select jsonb_build_object('n', count(*), 'md5', md5(coalesce(string_agg(id::text, ',' order by id), '')))
           from punto8_scope_audit) <> expected_audit
       or (select count(*) from public.clinical_record_entry_contributors) <> 0
       or (select count(*) from public.appointment_lifecycle_events where clinical_encounter_id is not null) <> 0
    then
        raise exception 'Refusing to run: the clinical data differs from the inventoried scope';
    end if;

    retained_before := jsonb_build_object(
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
        'communications', (select count(*) from public.transactional_communications),
        'audit_events_kept', (select count(*) from public.medical_access_audit_events
                              where id not in (select id from punto8_scope_audit)));
    if retained_before <> expected_retained then
        raise exception 'Refusing to run: retained data differs from the inventory: %', retained_before;
    end if;
    select jsonb_object_agg(lifecycle_state || ':' || coalesce(ended_reason, '-'), n)
    into authorization_states_before
    from (select lifecycle_state, ended_reason, count(*) n from public.care_authorizations group by 1, 2) x;

    -- 3. Disable only the deletion guards, inside this statement -----------------
    foreach guard in array guards loop
        execute format('alter table %s disable trigger %I',
                       split_part(guard, ':', 1), split_part(guard, ':', 2));
    end loop;

    -- 4. Delete in foreign-key order, checking every count -----------------------
    delete from public.medical_access_audit_events where id in (select id from punto8_scope_audit);
    get diagnostics deleted = row_count;
    if deleted <> 100 then raise exception 'Audit deletion removed % rows, expected 100', deleted; end if;

    delete from public.clinical_attachments;
    get diagnostics deleted = row_count;
    if deleted <> 1 then raise exception 'Attachment deletion removed % rows, expected 1', deleted; end if;

    delete from public.clinical_amendments;
    get diagnostics deleted = row_count;
    if deleted <> 3 then raise exception 'Amendment deletion removed % rows, expected 3', deleted; end if;

    delete from public.clinical_record_entries;
    get diagnostics deleted = row_count;
    if deleted <> 9 then raise exception 'Entry deletion removed % rows, expected 9', deleted; end if;

    delete from public.clinical_encounters;
    get diagnostics deleted = row_count;
    if deleted <> 8 then raise exception 'Encounter deletion removed % rows, expected 8', deleted; end if;

    -- 5. Re-enable exactly the same guards and verify them ----------------------
    foreach guard in array guards loop
        execute format('alter table %s enable trigger %I',
                       split_part(guard, ':', 1), split_part(guard, ':', 2));
    end loop;
    if exists (
        select 1 from pg_trigger
        where not tgisinternal
          and tgrelid in ('public.medical_access_audit_events'::regclass, 'public.clinical_attachments'::regclass,
                          'public.clinical_amendments'::regclass, 'public.clinical_record_entries'::regclass,
                          'public.clinical_encounters'::regclass, 'public.clinical_record_entry_contributors'::regclass)
          and tgenabled <> 'O'
    ) then
        raise exception 'A clinical trigger is not enabled after the cleanup';
    end if;

    -- 6. Post-state ------------------------------------------------------------------
    if exists (select 1 from public.clinical_encounters)
       or exists (select 1 from public.clinical_record_entries)
       or exists (select 1 from public.clinical_amendments)
       or exists (select 1 from public.clinical_attachments)
       or exists (select 1 from public.clinical_record_entry_contributors)
       or exists (select 1 from public.medical_access_audit_events
                  where clinical_encounter_id is not null or clinical_record_entry_id is not null
                     or clinical_amendment_id is not null or clinical_attachment_id is not null) then
        raise exception 'Clinical rows remain after the cleanup';
    end if;

    retained_after := jsonb_build_object(
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
        'communications', (select count(*) from public.transactional_communications),
        'audit_events_kept', (select count(*) from public.medical_access_audit_events));
    select jsonb_object_agg(lifecycle_state || ':' || coalesce(ended_reason, '-'), n)
    into authorization_states_after
    from (select lifecycle_state, ended_reason, count(*) n from public.care_authorizations group by 1, 2) x;

    if retained_after <> retained_before or authorization_states_after <> authorization_states_before then
        raise exception 'Retained data changed: before % / %, after % / %',
            retained_before, authorization_states_before, retained_after, authorization_states_after;
    end if;

    raise notice 'Punto 8 DEVELOPMENT cleanup committed: % retained, Care Authorizations %',
        retained_after, authorization_states_after;
end
$cleanup$;

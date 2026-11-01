-- ============================================================================
-- MenizVet — Punto 10 (20261119090000, Organization Professional Clinics
-- page, SPEC-ORG-008 §11): READ-ONLY preflight for DEVELOPMENT
--
-- Read-only (one READ ONLY transaction, rolled back). Run before `db push`.
-- Reports the target identity, the migration position, that neither new
-- function exists yet, the objects the migration relies on, and fingerprints
-- the postdeploy check must reproduce unchanged:
--   - `is_development` true, `last_migration` 20261118090000,
--     `new_functions_absent` true;
--   - `expect_*` all true;
--   - `fingerprints`: every public function except the two new ones
--     (definition + ACL), table columns and ACLs, indexes, constraints,
--     triggers, policies, and the data of the tables the read touches —
--     hashes and counts only, no content.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto10_dev_clinics_page_preflight_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing.
-- ============================================================================

begin transaction read only;

select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'migration_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261119090000'),
    'new_functions_absent', not exists (
        select 1 from pg_proc
        where pronamespace = 'public'::regnamespace
          and proname in ('get_my_organization_professional_clinics', 'professional_clinic_search_key')),
    'server_version', current_setting('server_version'),
    -- Objects the migration depends on.
    'expect_und_icu_collation', exists (select 1 from pg_collation where collname = 'und-x-icu' and collprovider = 'i'),
    'expect_dependencies_present',
        to_regprocedure('public.current_domain_user_id()') is not null
        and to_regprocedure('public.professional_capability_catalog()') is not null
        and to_regprocedure('public.user_has_clinic_capability(uuid,uuid,text)') is not null
        and to_regprocedure('public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)') is not null
        and to_regclass('public.clinics') is not null
        and to_regclass('public.clinic_public_profiles') is not null
        and to_regclass('public.organization_memberships') is not null
        and to_regclass('public.organization_responsibility_grants') is not null
        and to_regclass('public.veterinarian_clinic_assignments') is not null,
    -- The reviewed definitions (same fingerprints as LOCAL and the suite).
    'expect_org008_read_as_reviewed',
        md5(pg_get_functiondef('public.get_my_professional_clinics()'::regprocedure)) = '59b52cc2edf15927003c535c6dbad585'
        and (select proacl::text from pg_proc where oid = 'public.get_my_professional_clinics()'::regprocedure)
            = '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    'expect_predicates_as_reviewed',
        md5(pg_get_functiondef('public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)) = 'd103cf2610269b393b39c1eece8d23df'
        and md5(pg_get_functiondef('public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)) = '51fa265e96c1ab4c9f3f2184514fedd9'
        and md5(pg_get_functiondef('public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)) = 'a40be5366d9df872e79b12dfe2daf1dc',
    'expect_catalog_clinic_capabilities_16',
        (select count(*) from public.professional_capability_catalog() where capability_context = 'CLINIC') = 16,
    -- Data shape available for the postdeploy behaviour checks (counts only).
    'data', jsonb_build_object(
        'domain_users', (select count(*) from public.users),
        'linked_auth_identities', (select count(*) from public.user_authentication_identities),
        'organizations', (select count(*) from public.veterinary_organizations),
        'clinics', (select count(*) from public.clinics),
        'unnamed_clinics', (select count(*) from public.clinics as clinic
                            left join public.clinic_public_profiles as profile on profile.clinic_id = clinic.id
                            where profile.display_name is null),
        'current_memberships', (select count(*) from public.organization_memberships where effective_end is null),
        'current_clinic_scoped_grants', (select count(*) from public.organization_responsibility_grants
                                         where effective_end is null and scope_type = 'CLINIC'),
        'current_assignments', (select count(*) from public.veterinarian_clinic_assignments where effective_end is null),
        'users_without_current_membership', (select count(*) from public.users as domain_user
            where not exists (select 1 from public.organization_memberships as membership
                              where membership.user_id = domain_user.id and membership.effective_end is null))
    ),
    'fingerprints', jsonb_build_object(
        'functions', (select md5(string_agg(p.oid::regprocedure::text || '=' || md5(pg_get_functiondef(p.oid))
                                            || '/' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
                      from pg_proc as p
                      where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
                        and p.proname not in ('get_my_organization_professional_clinics', 'professional_clinic_search_key')),
        'function_count', (select count(*) from pg_proc as p
                           where p.pronamespace = 'public'::regnamespace
                             and p.proname not in ('get_my_organization_professional_clinics', 'professional_clinic_search_key')),
        'columns', (select md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' || is_nullable
                                          || ':' || coalesce(column_default, ''), '|' order by table_name, ordinal_position))
                    from information_schema.columns where table_schema = 'public'),
        'table_acls', (select md5(string_agg(relname || '=' || coalesce(relacl::text, ''), '|' order by relname))
                       from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r', 'p', 'v', 'm')),
        'indexes', (select md5(string_agg(indexdef, '|' order by indexname)) from pg_indexes where schemaname = 'public'),
        'constraints', (select md5(string_agg(conrelid::regclass::text || '.' || conname || '=' || pg_get_constraintdef(oid),
                                              '|' order by conrelid::regclass::text, conname))
                        from pg_constraint where connamespace = 'public'::regnamespace),
        'triggers', (select md5(string_agg(tgrelid::regclass::text || '.' || tgname || '=' || pg_get_triggerdef(oid),
                                           '|' order by tgrelid::regclass::text, tgname))
                     from pg_trigger where not tgisinternal
                       and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
        'policies', (select md5(coalesce(string_agg(tablename || '.' || policyname || '=' || coalesce(qual, '') || '/'
                                                    || coalesce(with_check, ''), '|' order by tablename, policyname), ''))
                     from pg_policies where schemaname = 'public'),
        'data_clinics', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), '')) from public.clinics as t),
        'data_clinic_public_profiles', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.clinic_id), ''))
                                        from public.clinic_public_profiles as t),
        'data_organizations', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), ''))
                               from public.veterinary_organizations as t),
        'data_memberships', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), ''))
                             from public.organization_memberships as t),
        'data_grants', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), ''))
                        from public.organization_responsibility_grants as t),
        'data_assignments', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), ''))
                             from public.veterinarian_clinic_assignments as t)
    )
));

rollback;

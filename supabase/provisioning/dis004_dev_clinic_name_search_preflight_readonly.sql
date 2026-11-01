-- ============================================================================
-- MenizVet — SPEC-DIS-004 (20261120090000, Search Published Clinics by Name):
-- READ-ONLY preflight for DEVELOPMENT
--
-- Read-only (one READ ONLY transaction, rolled back). Run before `db push`.
-- Reports the target identity, the migration position, that neither new
-- function exists yet, the objects and collation the migration relies on,
-- that the helper's normalization expression gives the LOCAL results here,
-- the default function privileges the migration's grants build on, the
-- existing Discovery reads as reviewed, the data shape available to the
-- postdeploy check (counts only), and fingerprints the postdeploy check must
-- reproduce unchanged:
--   - `is_development` true, `last_migration` 20261119090000,
--     `new_functions_absent` true;
--   - `expect_*` all true;
--   - `fingerprints`: every public function except the two new ones
--     (definition + ACL), table columns and ACLs, indexes, constraints,
--     triggers, policies, and the data of the tables the read touches —
--     hashes and counts only, no content.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/dis004_dev_clinic_name_search_preflight_readonly.sql
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
    'migration_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261120090000'),
    'new_functions_absent', not exists (
        select 1 from pg_proc
        where pronamespace = 'public'::regnamespace
          and proname in ('discover_published_clinics', 'clinic_display_name_search_key')),
    'server_version', current_setting('server_version'),
    'database_collation', (select datcollate || '/' || datctype || '/' || pg_encoding_to_char(encoding)
                           from pg_database where datname = current_database()),
    -- Objects and collation the migration depends on (LOCAL: ICU 153.121).
    'expect_und_icu_collation', exists (select 1 from pg_collation where collname = 'und-x-icu' and collprovider = 'i'),
    'und_icu_version', (select collversion from pg_collation where collname = 'und-x-icu'),
    'expect_dependencies_present',
        to_regclass('public.clinics') is not null
        and to_regclass('public.clinic_public_profiles') is not null
        and to_regclass('public.clinic_locations') is not null
        and to_regclass('public.published_clinic_public_profiles') is not null,
    -- One Location and one public profile per Clinic, structurally.
    'expect_one_location_and_profile_per_clinic',
        exists (select 1 from pg_constraint where conrelid = 'public.clinic_locations'::regclass and contype = 'p'
                and pg_get_constraintdef(oid) = 'PRIMARY KEY (clinic_id)')
        and exists (select 1 from pg_constraint where conrelid = 'public.clinic_public_profiles'::regclass and contype = 'p'
                    and pg_get_constraintdef(oid) = 'PRIMARY KEY (clinic_id)'),
    -- The helper's exact expression, evaluated inline, gives the LOCAL results.
    'expect_normalization_expression_as_local', (
        select array_agg(pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.regexp_replace(
                   pg_catalog.normalize(sample, 'NFKD'), '[\u0300-\u036f]', '', 'g') collate pg_catalog."und-x-icu"),
                   '[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+', ' ', 'g'), ' ')
                   order by position)
        from unnest(array['CLÍNICA  Peña', U&'\FB01nca\3000\00A0X', 'ØSTER' collate "C", U&'\0130stanbul', '50% [A]_'])
             with ordinality as samples (sample, position)
    ) = array['clinica pena', 'finca x', 'øster', 'istanbul', '50% [a]_'],
    -- New public functions receive these privileges before the migration's
    -- revoke/grant (LOCAL: postgres, anon, authenticated, service_role).
    'default_function_privileges', (select defaclacl::text from pg_default_acl
                                    where defaclnamespace = 'public'::regnamespace and defaclobjtype = 'f'
                                      and defaclrole = 'postgres'::regrole),
    -- The reviewed definitions (same fingerprints as LOCAL and the suite).
    'expect_professional_helper_as_reviewed',
        md5(pg_get_functiondef('public.professional_clinic_search_key(text)'::regprocedure)) = '53cc64a22c3c1b31ecd3a106116bbc58'
        and (select proacl::text from pg_proc where oid = 'public.professional_clinic_search_key(text)'::regprocedure)
            = '{postgres=X/postgres}',
    'expect_discovery_reads_as_reviewed',
        md5(pg_get_functiondef('public.get_published_clinic_location(uuid)'::regprocedure)) = 'a6cb0b1ce427ea49c9cfac71126c66b2'
        and md5(pg_get_functiondef('public.discover_nearby_clinics(double precision,double precision,double precision,integer,double precision,uuid)'::regprocedure)) = 'ea1eddd8d37697ee872a8bf7c585964b'
        and md5(pg_get_functiondef('public.discover_clinics_in_viewport(double precision,double precision,double precision,double precision,integer,uuid)'::regprocedure)) = '15c682253cc4ceaac79270e49815ae1b'
        and md5(pg_get_functiondef('public.get_published_clinic_service_offerings(uuid)'::regprocedure)) = '8cbda91bc08628db0fcb70d8235f6af1'
        and md5(pg_get_functiondef('public.get_published_clinic_opening_hours(uuid)'::regprocedure)) = '73758916b2b48985f2689cebb75764ff'
        and (select bool_and(proacl::text = '{postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres}')
             from pg_proc where oid in (
                 'public.get_published_clinic_location(uuid)'::regprocedure,
                 'public.discover_nearby_clinics(double precision,double precision,double precision,integer,double precision,uuid)'::regprocedure,
                 'public.discover_clinics_in_viewport(double precision,double precision,double precision,double precision,integer,uuid)'::regprocedure)),
    'expect_discovery_view_and_tables_as_reviewed',
        md5(pg_get_viewdef('public.published_clinic_public_profiles'::regclass)) = '5fa07dcf12a9097d54de0cf723aa2517'
        and (select relacl::text from pg_class where oid = 'public.published_clinic_public_profiles'::regclass)
            = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
        and (select bool_and(relacl::text = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}')
             from pg_class where oid in ('public.clinics'::regclass, 'public.clinic_locations'::regclass,
                                         'public.clinic_public_profiles'::regclass)),
    -- Data shape available for the postdeploy behaviour checks (counts only).
    'data', jsonb_build_object(
        'clinics', (select count(*) from public.clinics),
        'published_clinics', (select count(*) from public.clinics where is_published),
        'unpublished_clinics', (select count(*) from public.clinics where not is_published),
        'published_without_profile', (select count(*) from public.clinics as clinic
                                      where clinic.is_published
                                        and not exists (select 1 from public.clinic_public_profiles as profile
                                                        where profile.clinic_id = clinic.id)),
        'basic_discovery_rows', (select count(*) from public.published_clinic_public_profiles),
        'basic_discovery_unnamed', (select count(*) from public.published_clinic_public_profiles where display_name is null),
        'basic_discovery_with_location', (select count(*) from public.published_clinic_public_profiles as listed
                                          where exists (select 1 from public.clinic_locations as location
                                                        where location.clinic_id = listed.clinic_id)),
        'basic_discovery_without_location', (select count(*) from public.published_clinic_public_profiles as listed
                                             where not exists (select 1 from public.clinic_locations as location
                                                               where location.clinic_id = listed.clinic_id)),
        'basic_discovery_repeated_names', (select count(*) from (
                                               select display_name from public.published_clinic_public_profiles
                                               where display_name is not null
                                               group by display_name having count(*) > 1) as repeated),
        'basic_discovery_non_ascii_names', (select count(*) from public.published_clinic_public_profiles
                                            where display_name !~ '^[ -~]*$'),
        'unpublished_with_location', (select count(*) from public.clinics as clinic
                                      join public.clinic_locations as location on location.clinic_id = clinic.id
                                      where not clinic.is_published)
    ),
    'fingerprints', jsonb_build_object(
        'functions', (select md5(string_agg(p.oid::regprocedure::text || '=' || md5(pg_get_functiondef(p.oid))
                                            || '/' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
                      from pg_proc as p
                      where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
                        and p.proname not in ('discover_published_clinics', 'clinic_display_name_search_key')),
        'function_count', (select count(*) from pg_proc as p
                           where p.pronamespace = 'public'::regnamespace
                             and p.proname not in ('discover_published_clinics', 'clinic_display_name_search_key')),
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
        'data_clinic_locations', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.clinic_id), ''))
                                  from public.clinic_locations as t),
        'data_organizations', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), ''))
                               from public.veterinary_organizations as t)
    )
));

rollback;

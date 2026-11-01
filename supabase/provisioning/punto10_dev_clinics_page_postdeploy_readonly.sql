-- ============================================================================
-- MenizVet — Punto 10 (20261119090000, Organization Professional Clinics
-- page, SPEC-ORG-008 §11): READ-ONLY postdeploy check for DEVELOPMENT
--
-- Read-only (one READ ONLY transaction, rolled back). Run after `db push`.
--   - `expect_*` must all be true;
--   - `fingerprints` must equal the preflight's values;
--   - `behaviour` impersonates every existing domain User (session settings
--     only: request.jwt.claim.sub and SET LOCAL ROLE authenticated) and
--     compares the new read, page by page, with get_my_professional_clinics()
--     restricted to the Organization — for each of the User's current
--     Organizations, one Organization without their Membership, an unknown
--     id and null, with and without searches, at several page sizes — and
--     re-checks every returned Clinic against user_has_clinic_capability.
--     Only counts are reported: no id, name or other content.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/punto10_dev_clinics_page_postdeploy_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing.
-- ============================================================================

begin transaction read only;

do $$
declare
    subject record;
    organization_ids uuid[];
    target_organization_id uuid;
    search text;
    page_size integer;
    all_clinics jsonb;
    expected jsonb;
    actual jsonb;
    page_rows jsonb;
    page_count integer;
    page_distinct integer;
    after_name text;
    after_id uuid;
    pages integer;
    failure text;
    returned record;
    result jsonb := jsonb_build_object(
        'users_checked', 0, 'users_with_membership', 0, 'users_without_membership', 0,
        'cases_checked', 0, 'cases_own_organization', 0, 'cases_foreign_organization', 0,
        'cases_unknown_or_null', 0, 'cases_nonempty', 0, 'cases_with_search_nonempty', 0,
        'cases_multi_page', 0, 'mismatches', 0, 'oversized_or_duplicate_pages', 0,
        'read_failures', 0, 'rows_rechecked', 0, 'rows_not_authorized', 0,
        'organizations_completeness_checked', 0, 'organizations_incomplete', 0,
        'nonmember_nonempty', 0);

begin
    -- Authentication and validation boundaries (no data involved).
    begin
        set local role anon;
        perform * from public.get_my_organization_professional_clinics(null);
        failure := 'OK';
    exception when others then
        failure := sqlstate;
    end;
    reset role;
    result := result || jsonb_build_object('anon_denied_42501', failure = '42501');

    perform set_config('request.jwt.claim.sub', '', true);
    begin
        set local role authenticated;
        perform * from public.get_my_organization_professional_clinics(null, null, null, null, 0);
        failure := 'OK';
    exception when others then
        failure := sqlstate;
    end;
    reset role;
    result := result || jsonb_build_object('no_subject_28000_before_validation', failure = '28000');

    for subject in
        select domain_user.id as user_id, identity.provider_subject,
               exists (select 1 from public.organization_memberships as membership
                       where membership.user_id = domain_user.id and membership.effective_end is null) as has_membership
        from public.users as domain_user
        join public.user_authentication_identities as identity on identity.user_id = domain_user.id
        order by domain_user.id
        limit 500
    loop
        perform set_config('request.jwt.claim.sub', subject.provider_subject::text, true);
        result := jsonb_set(result, '{users_checked}', to_jsonb((result ->> 'users_checked')::int + 1));
        result := jsonb_set(result, case when subject.has_membership then array['users_with_membership']
                                         else array['users_without_membership'] end,
                            to_jsonb((result ->> case when subject.has_membership then 'users_with_membership'
                                                      else 'users_without_membership' end)::int + 1));

        -- Invalid input is rejected for an authenticated User.
        if (result ->> 'users_checked')::int = 1 then
            begin
                set local role authenticated;
                perform * from public.get_my_organization_professional_clinics(null, repeat('x', 101), null, null, 20);
                failure := 'OK';
            exception when others then
                failure := sqlstate;
            end;
            reset role;
            result := result || jsonb_build_object('invalid_input_22023', failure = '22023');
        end if;

        set local role authenticated;
        all_clinics := public.get_my_professional_clinics();
        reset role;

        organization_ids := array(
            select membership.organization_id from public.organization_memberships as membership
            where membership.user_id = subject.user_id and membership.effective_end is null
            order by membership.organization_id);
        organization_ids := organization_ids || array(
            select organization.id from public.veterinary_organizations as organization
            where not exists (select 1 from public.organization_memberships as membership
                              where membership.user_id = subject.user_id
                                and membership.organization_id = organization.id
                                and membership.effective_end is null)
            order by organization.id limit 1);
        organization_ids := organization_ids || array['00000000-0000-4000-8000-000000000000'::uuid, null::uuid];

        foreach target_organization_id in array organization_ids loop
            foreach search in array array[null, 'a', 'e', 'clinica', 'vet', '%', '_', 'zz no match'] loop
                select coalesce(jsonb_agg(jsonb_build_object(
                           'clinic_id', entry ->> 'clinic_id',
                           'clinic_display_name', entry -> 'clinic_display_name') order by ordinality), '[]'::jsonb)
                into expected
                from jsonb_array_elements(all_clinics -> 'clinics') with ordinality as listed (entry, ordinality)
                where (entry ->> 'organization_id')::uuid = target_organization_id
                  and (nullif(public.professional_clinic_search_key(search), '') is null
                       or (jsonb_typeof(entry -> 'clinic_display_name') = 'string'
                           and strpos(public.professional_clinic_search_key(entry ->> 'clinic_display_name'),
                                      public.professional_clinic_search_key(search)) > 0));

                foreach page_size in array array[1, 2, 3, 20, 50] loop
                    actual := '[]'::jsonb;
                    after_name := null;
                    after_id := null;
                    pages := 0;
                    failure := null;
                    begin
                        set local role authenticated;
                        loop
                            pages := pages + 1;
                            select coalesce(jsonb_agg(jsonb_build_object(
                                       'clinic_id', page.clinic_id::text,
                                       'clinic_display_name', page.clinic_display_name) order by page.ordinality), '[]'::jsonb),
                                   count(*), count(distinct page.clinic_id)
                            into page_rows, page_count, page_distinct
                            from public.get_my_organization_professional_clinics(
                                target_organization_id, search, after_name, after_id, page_size) with ordinality as page;
                            if page_count > page_size or page_distinct <> page_count then
                                failure := 'oversized_or_duplicate_pages';
                                exit;
                            end if;
                            actual := actual || page_rows;
                            exit when page_count < page_size or pages > 200;
                            after_id := (page_rows -> -1 ->> 'clinic_id')::uuid;
                            after_name := page_rows -> -1 ->> 'clinic_display_name';
                        end loop;
                        reset role;
                    exception when others then
                        reset role;
                        failure := 'read_failures';
                    end;

                    result := jsonb_set(result, '{cases_checked}', to_jsonb((result ->> 'cases_checked')::int + 1));
                    if failure is not null then
                        result := jsonb_set(result, array[failure], to_jsonb((result ->> failure)::int + 1));
                    elsif actual is distinct from expected then
                        result := jsonb_set(result, '{mismatches}', to_jsonb((result ->> 'mismatches')::int + 1));
                    end if;
                    if target_organization_id is null or target_organization_id = '00000000-0000-4000-8000-000000000000' then
                        result := jsonb_set(result, '{cases_unknown_or_null}', to_jsonb((result ->> 'cases_unknown_or_null')::int + 1));
                    elsif target_organization_id = any (array(
                            select membership.organization_id from public.organization_memberships as membership
                            where membership.user_id = subject.user_id and membership.effective_end is null)) then
                        result := jsonb_set(result, '{cases_own_organization}', to_jsonb((result ->> 'cases_own_organization')::int + 1));
                    else
                        result := jsonb_set(result, '{cases_foreign_organization}', to_jsonb((result ->> 'cases_foreign_organization')::int + 1));
                    end if;
                    if jsonb_array_length(actual) > 0 then
                        result := jsonb_set(result, '{cases_nonempty}', to_jsonb((result ->> 'cases_nonempty')::int + 1));
                        if search is not null then
                            result := jsonb_set(result, '{cases_with_search_nonempty}',
                                                to_jsonb((result ->> 'cases_with_search_nonempty')::int + 1));
                        end if;
                        if not subject.has_membership then
                            result := jsonb_set(result, '{nonmember_nonempty}', to_jsonb((result ->> 'nonmember_nonempty')::int + 1));
                        end if;
                    end if;
                    if pages > 1 then
                        result := jsonb_set(result, '{cases_multi_page}', to_jsonb((result ->> 'cases_multi_page')::int + 1));
                    end if;

                    -- Every returned row is authorized by the authoritative
                    -- predicate (evaluated as the owner, never as a client).
                    if page_size = 50 and failure is null then
                        for returned in
                            select (row_entry ->> 'clinic_id')::uuid as clinic_id
                            from jsonb_array_elements(actual) as row_entry
                        loop
                            result := jsonb_set(result, '{rows_rechecked}', to_jsonb((result ->> 'rows_rechecked')::int + 1));
                            if not exists (
                                select 1
                                from public.clinics as clinic
                                cross join public.professional_capability_catalog() as catalog_entry
                                where clinic.id = returned.clinic_id
                                  and clinic.organization_id = target_organization_id
                                  and catalog_entry.capability_context = 'CLINIC'
                                  and public.user_has_clinic_capability(subject.user_id, clinic.id, catalog_entry.capability)
                            ) then
                                result := jsonb_set(result, '{rows_not_authorized}',
                                                    to_jsonb((result ->> 'rows_not_authorized')::int + 1));
                            end if;
                        end loop;
                        -- Completeness without a search: every authorized Clinic is listed.
                        if search is null and target_organization_id is not null then
                            result := jsonb_set(result, '{organizations_completeness_checked}',
                                                to_jsonb((result ->> 'organizations_completeness_checked')::int + 1));
                            if (select count(*) from public.clinics as clinic
                                where clinic.organization_id = target_organization_id
                                  and exists (select 1 from public.professional_capability_catalog() as catalog_entry
                                              where catalog_entry.capability_context = 'CLINIC'
                                                and public.user_has_clinic_capability(subject.user_id, clinic.id, catalog_entry.capability)))
                               <> jsonb_array_length(actual) then
                                result := jsonb_set(result, '{organizations_incomplete}',
                                                    to_jsonb((result ->> 'organizations_incomplete')::int + 1));
                            end if;
                        end if;
                    end if;
                end loop;
            end loop;
        end loop;
    end loop;

    perform set_config('punto10.behaviour', result::text, true);
end;
$$;

select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'expect_migration_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261119090000'),
    'expect_read_contract',
        (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                and proname = 'get_my_organization_professional_clinics') = 1
        and (select prosecdef and provolatile = 's' and proconfig = array['search_path=""']
                    and pg_get_function_identity_arguments(oid)
                        = 'p_organization_id uuid, p_search text, p_after_display_name text, p_after_clinic_id uuid, p_limit integer'
                    and pg_get_function_result(oid) = 'TABLE(clinic_id uuid, clinic_display_name text)'
             from pg_proc where oid = to_regprocedure('public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)')),
    'expect_read_definition_as_local',
        md5(pg_get_functiondef(to_regprocedure('public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)')))
            = 'dab124804ba60d52f13c7600989a8ef6',
    'expect_helper_definition_as_local',
        md5(pg_get_functiondef(to_regprocedure('public.professional_clinic_search_key(text)'))) = '53cc64a22c3c1b31ecd3a106116bbc58'
        and (select not prosecdef and provolatile = 'i' and proconfig = array['search_path=""']
             from pg_proc where oid = to_regprocedure('public.professional_clinic_search_key(text)')),
    'expect_read_delegates_to_predicate',
        (select prosrc like '%public.user_has_clinic_capability(%'
                and prosrc like '%public.user_has_organization_scoped_clinic_capability(%'
                and prosrc not like '%''OWNER''%' and prosrc not like '%''ADMINISTRATOR''%'
                and prosrc not like '%''RECEPTIONIST''%' and prosrc not like '%''VETERINARIAN''%'
         from pg_proc where oid = to_regprocedure('public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)')),
    'expect_read_grants',
        has_function_privilege('authenticated', 'public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)', 'EXECUTE')
        and not has_function_privilege('service_role', 'public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)', 'EXECUTE')
        and not exists (select 1 from aclexplode((select proacl from pg_proc
                        where oid = to_regprocedure('public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)'))) as acl
                        where acl.grantee = 0),
    'read_acl', (select proacl::text from pg_proc
                 where oid = to_regprocedure('public.get_my_organization_professional_clinics(uuid,text,text,uuid,integer)')),
    'expect_helper_not_client_executable',
        not has_function_privilege('anon', 'public.professional_clinic_search_key(text)', 'EXECUTE')
        and not has_function_privilege('authenticated', 'public.professional_clinic_search_key(text)', 'EXECUTE')
        and not has_function_privilege('service_role', 'public.professional_clinic_search_key(text)', 'EXECUTE')
        and not exists (select 1 from aclexplode((select proacl from pg_proc
                        where oid = to_regprocedure('public.professional_clinic_search_key(text)'))) as acl
                        where acl.grantee = 0),
    'helper_acl', (select proacl::text from pg_proc where oid = to_regprocedure('public.professional_clinic_search_key(text)')),
    'expect_org008_read_unchanged',
        md5(pg_get_functiondef('public.get_my_professional_clinics()'::regprocedure)) = '59b52cc2edf15927003c535c6dbad585'
        and (select proacl::text from pg_proc where oid = 'public.get_my_professional_clinics()'::regprocedure)
            = '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    'expect_predicates_unchanged',
        md5(pg_get_functiondef('public.user_has_clinic_capability(uuid,uuid,text)'::regprocedure)) = 'd103cf2610269b393b39c1eece8d23df'
        and md5(pg_get_functiondef('public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)) = '51fa265e96c1ab4c9f3f2184514fedd9'
        and md5(pg_get_functiondef('public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)'::regprocedure)) = 'a40be5366d9df872e79b12dfe2daf1dc',
    'expect_search_key_samples',
        public.professional_clinic_search_key('CLÍNICA  Peña') = 'clinica pena'
        and public.professional_clinic_search_key(U&'\FB01nca\3000\00A0X') = 'finca x'
        and public.professional_clinic_search_key('ØSTER' collate "C") = 'øster'
        and public.professional_clinic_search_key('50% [A]_') = '50% [a]_',
    'behaviour', current_setting('punto10.behaviour')::jsonb,
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

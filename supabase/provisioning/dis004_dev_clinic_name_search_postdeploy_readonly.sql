-- ============================================================================
-- MenizVet — SPEC-DIS-004 (20261120090000, Search Published Clinics by Name):
-- READ-ONLY postdeploy check for DEVELOPMENT
--
-- Read-only (one READ ONLY transaction, rolled back). Run after `db push`.
--   - `expect_*` must all be true;
--   - `fingerprints` must equal the preflight's values;
--   - `behaviour` calls the new read as anon, as an authenticated session
--     without a subject, and as every domain User with a linked
--     authentication identity (session settings only: request.jwt.claim.sub
--     and SET LOCAL ROLE), page by page for several searches and page sizes,
--     and compares it with the existing basic Discovery surface
--     (published_clinic_public_profiles, each row with the address of
--     get_published_clinic_location), narrowed by the same normalization, in
--     display-name order. Every published name is also searched in
--     upper case without accents. Only counts are reported: no id, name,
--     address or other content.
--
--   npx supabase db query --linked \
--     -f supabase/provisioning/dis004_dev_clinic_name_search_postdeploy_readonly.sql
--
-- Never part of supabase/migrations. Writes nothing.
-- ============================================================================

begin transaction read only;

do $$
declare
    caller record;
    search text;
    page_size integer;
    expected jsonb;
    actual jsonb;
    envelope jsonb;
    page_rows jsonb;
    page_count integer;
    previous_has_more boolean;
    after_name text;
    after_id uuid;
    pages integer;
    failure text;
    listed record;
    named_search text;
    hit boolean;
    result jsonb := jsonb_build_object(
        'callers_checked', 0, 'cases_checked', 0, 'cases_nonempty', 0, 'cases_with_search_nonempty', 0,
        'cases_multi_page', 0, 'mismatches', 0, 'read_failures', 0, 'malformed_pages', 0,
        'rows_returned_unpublished', 0, 'rows_address_not_public', 0, 'rows_rechecked', 0,
        'name_searches_checked', 0, 'name_searches_missing', 0, 'callers_differing_from_anon', 0);
    anon_baseline jsonb;
    searches text[] := array[null, '', 'a', 'e', 'clinica', 'CLÍNICA', 'vet', 'veterinaria', 'centro',
                             '%', '_', 'zz no match'];
begin
    -- Validation boundaries (no data involved), for anon.
    set local role anon;
    foreach search in array array[
        'select public.discover_published_clinics(null, null, null, 0)',
        'select public.discover_published_clinics(null, null, null, 51)',
        'select public.discover_published_clinics(null, ''x'', null, 20)',
        'select public.discover_published_clinics(repeat(''x'', 101), null, null, 20)'
    ] loop
        begin
            execute search;
            failure := 'OK';
        exception when others then
            failure := sqlstate;
        end;
        result := result || jsonb_build_object('invalid_input_22023',
            coalesce((result ->> 'invalid_input_22023')::boolean, true) and failure = '22023');
    end loop;
    -- The helper is not callable by a client.
    begin
        perform public.clinic_display_name_search_key('x');
        failure := 'OK';
    exception when others then
        failure := sqlstate;
    end;
    reset role;
    result := result || jsonb_build_object('anon_helper_denied_42501', failure = '42501');

    perform set_config('request.jwt.claim.sub', '', true);
    set local role authenticated;
    begin
        perform public.clinic_display_name_search_key('x');
        failure := 'OK';
    exception when others then
        failure := sqlstate;
    end;
    reset role;
    result := result || jsonb_build_object('authenticated_helper_denied_42501', failure = '42501');

    for caller in
        select 0 as position, 'anon' as role_name, '' as subject
        union all
        select 1, 'authenticated', ''
        union all
        select 2, 'authenticated', identity.provider_subject::text
        from (select identity.provider_subject from public.users as domain_user
              join public.user_authentication_identities as identity on identity.user_id = domain_user.id
              order by domain_user.id limit 500) as identity
        order by 1, 3
    loop
        result := jsonb_set(result, '{callers_checked}', to_jsonb((result ->> 'callers_checked')::int + 1));
        foreach search in array searches loop
            -- The oracle, as the owner.
            select coalesce(jsonb_agg(jsonb_build_object(
                       'clinic_id', basic.clinic_id,
                       'display_name', basic.display_name,
                       'description', basic.description,
                       'address_text', (select location.address_text
                                        from public.get_published_clinic_location(basic.clinic_id) as location))
                       order by basic.display_name nulls last, basic.clinic_id), '[]'::jsonb)
            into expected
            from public.published_clinic_public_profiles as basic
            where nullif(public.clinic_display_name_search_key(search), '') is null
               or (basic.display_name is not null
                   and strpos(public.clinic_display_name_search_key(basic.display_name),
                              public.clinic_display_name_search_key(search)) > 0);

            foreach page_size in array array[1, 2, 3, 20, 50] loop
                actual := '[]'::jsonb;
                after_name := null;
                after_id := null;
                pages := 0;
                previous_has_more := false;
                failure := null;
                perform set_config('request.jwt.claim.sub', caller.subject, true);
                begin
                    execute format('set local role %I', caller.role_name);
                    loop
                        pages := pages + 1;
                        envelope := public.discover_published_clinics(search, after_name, after_id, page_size);
                        page_rows := envelope -> 'clinics';
                        page_count := jsonb_array_length(page_rows);
                        if page_count > page_size
                           or page_count <> (select count(distinct row_entry ->> 'clinic_id')
                                             from jsonb_array_elements(page_rows) as row_entry)
                           or envelope -> 'next_after_clinic_id' is distinct from coalesce(page_rows -> -1 -> 'clinic_id', 'null'::jsonb)
                           or envelope -> 'next_after_display_name' is distinct from coalesce(page_rows -> -1 -> 'display_name', 'null'::jsonb)
                           or ((envelope ->> 'has_more')::boolean and page_count <> page_size)
                           or (previous_has_more and page_count = 0) then
                            failure := 'malformed_pages';
                            exit;
                        end if;
                        actual := actual || page_rows;
                        previous_has_more := (envelope ->> 'has_more')::boolean;
                        exit when not previous_has_more or pages > 200;
                        after_id := (envelope ->> 'next_after_clinic_id')::uuid;
                        after_name := envelope ->> 'next_after_display_name';
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
                if jsonb_array_length(actual) > 0 then
                    result := jsonb_set(result, '{cases_nonempty}', to_jsonb((result ->> 'cases_nonempty')::int + 1));
                    if search is not null and search <> '' then
                        result := jsonb_set(result, '{cases_with_search_nonempty}',
                                            to_jsonb((result ->> 'cases_with_search_nonempty')::int + 1));
                    end if;
                end if;
                if pages > 1 then
                    result := jsonb_set(result, '{cases_multi_page}', to_jsonb((result ->> 'cases_multi_page')::int + 1));
                end if;

                -- Every returned row re-checked against the tables, as the owner.
                if page_size = 50 and failure is null then
                    if caller.position = 0 and search is null then
                        anon_baseline := actual;
                    elsif search is null and actual is distinct from anon_baseline then
                        result := jsonb_set(result, '{callers_differing_from_anon}',
                                            to_jsonb((result ->> 'callers_differing_from_anon')::int + 1));
                    end if;
                    for listed in
                        select (row_entry ->> 'clinic_id')::uuid as clinic_id, row_entry ->> 'address_text' as address_text
                        from jsonb_array_elements(actual) as row_entry
                    loop
                        result := jsonb_set(result, '{rows_rechecked}', to_jsonb((result ->> 'rows_rechecked')::int + 1));
                        if not exists (select 1 from public.clinics as clinic
                                       join public.clinic_public_profiles as profile on profile.clinic_id = clinic.id
                                       where clinic.id = listed.clinic_id and clinic.is_published) then
                            result := jsonb_set(result, '{rows_returned_unpublished}',
                                                to_jsonb((result ->> 'rows_returned_unpublished')::int + 1));
                        end if;
                        if listed.address_text is distinct from (
                               select location.address_text from public.clinic_locations as location
                               join public.clinics as clinic on clinic.id = location.clinic_id
                               where location.clinic_id = listed.clinic_id and clinic.is_published) then
                            result := jsonb_set(result, '{rows_address_not_public}',
                                                to_jsonb((result ->> 'rows_address_not_public')::int + 1));
                        end if;
                    end loop;
                end if;
            end loop;
        end loop;
    end loop;

    -- Every published name finds its Clinic when searched without accents
    -- (lower case) and in upper case with its accents. Upper case is skipped
    -- for a name with "ß": upper() spells it "SS", which SPEC-DIS-004 BR-5
    -- documents as not folded.
    result := result || jsonb_build_object('name_searches_skipped_sharp_s', 0);
    for listed in select clinic_id, display_name from public.published_clinic_public_profiles
                  where display_name is not null order by clinic_id loop
        if listed.display_name like '%ß%' then
            result := jsonb_set(result, '{name_searches_skipped_sharp_s}',
                                to_jsonb((result ->> 'name_searches_skipped_sharp_s')::int + 1));
        end if;
        foreach named_search in array array[
            left(public.clinic_display_name_search_key(listed.display_name), 100),
            case when listed.display_name not like '%ß%' then left(upper(listed.display_name), 100) end
        ] loop
            continue when named_search is null;
            set local role anon;
            select exists (
                select 1 from jsonb_array_elements(public.discover_published_clinics(named_search, null, null, 50) -> 'clinics') as row_entry
                where row_entry ->> 'clinic_id' = listed.clinic_id::text) into hit;
            reset role;
            result := jsonb_set(result, '{name_searches_checked}', to_jsonb((result ->> 'name_searches_checked')::int + 1));
            if not hit then
                result := jsonb_set(result, '{name_searches_missing}', to_jsonb((result ->> 'name_searches_missing')::int + 1));
            end if;
        end loop;
    end loop;

    perform set_config('dis004.behaviour', result::text, true);
end;
$$;

select jsonb_pretty(jsonb_build_object(
    'is_development', exists (
        select 1 from vault.decrypted_secrets
        where name = 'communications_dispatch_url'
          and decrypted_secret like 'https://eqvlydfflfvltprkwcxx.supabase.co/%'),
    'last_migration', (select max(version) from supabase_migrations.schema_migrations),
    'expect_migration_applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20261120090000'),
    'expect_read_contract',
        (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                and proname = 'discover_published_clinics') = 1
        and (select prosecdef and provolatile = 's' and proconfig = array['search_path=""']
                    and pg_get_function_identity_arguments(oid)
                        = 'p_search text, p_after_display_name text, p_after_clinic_id uuid, p_limit integer'
                    and pg_get_function_result(oid) = 'jsonb' and pronargdefaults = 4
             from pg_proc where oid = to_regprocedure('public.discover_published_clinics(text,text,uuid,integer)')),
    'expect_read_definition_as_local',
        md5(pg_get_functiondef(to_regprocedure('public.discover_published_clinics(text,text,uuid,integer)')))
            = '4e7078108c7c2c163ed4d38509252608',
    'expect_helper_definition_as_local',
        md5(pg_get_functiondef(to_regprocedure('public.clinic_display_name_search_key(text)'))) = '7dfcae2987bb74df0efe9d76a738fa69'
        and (select not prosecdef and provolatile = 'i' and proconfig = array['search_path=""']
             from pg_proc where oid = to_regprocedure('public.clinic_display_name_search_key(text)')),
    'expect_helper_body_equals_professional',
        (select prosrc from pg_proc where oid = to_regprocedure('public.clinic_display_name_search_key(text)'))
        = (select prosrc from pg_proc where oid = to_regprocedure('public.professional_clinic_search_key(text)')),
    'expect_read_grants',
        (select proacl::text from pg_proc where oid = to_regprocedure('public.discover_published_clinics(text,text,uuid,integer)'))
            = '{postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres}'
        and not exists (select 1 from aclexplode((select proacl from pg_proc
                        where oid = to_regprocedure('public.discover_published_clinics(text,text,uuid,integer)'))) as acl
                        where acl.grantee = 0),
    'read_acl', (select proacl::text from pg_proc
                 where oid = to_regprocedure('public.discover_published_clinics(text,text,uuid,integer)')),
    'expect_helper_not_client_executable',
        (select proacl::text from pg_proc where oid = to_regprocedure('public.clinic_display_name_search_key(text)'))
            = '{postgres=X/postgres}'
        and not has_function_privilege('anon', 'public.clinic_display_name_search_key(text)', 'EXECUTE')
        and not has_function_privilege('authenticated', 'public.clinic_display_name_search_key(text)', 'EXECUTE')
        and not has_function_privilege('service_role', 'public.clinic_display_name_search_key(text)', 'EXECUTE'),
    'helper_acl', (select proacl::text from pg_proc where oid = to_regprocedure('public.clinic_display_name_search_key(text)')),
    'expect_existing_reads_unchanged',
        md5(pg_get_functiondef('public.professional_clinic_search_key(text)'::regprocedure)) = '53cc64a22c3c1b31ecd3a106116bbc58'
        and (select proacl::text from pg_proc where oid = 'public.professional_clinic_search_key(text)'::regprocedure) = '{postgres=X/postgres}'
        and md5(pg_get_functiondef('public.get_published_clinic_location(uuid)'::regprocedure)) = 'a6cb0b1ce427ea49c9cfac71126c66b2'
        and md5(pg_get_functiondef('public.discover_nearby_clinics(double precision,double precision,double precision,integer,double precision,uuid)'::regprocedure)) = 'ea1eddd8d37697ee872a8bf7c585964b'
        and md5(pg_get_functiondef('public.discover_clinics_in_viewport(double precision,double precision,double precision,double precision,integer,uuid)'::regprocedure)) = '15c682253cc4ceaac79270e49815ae1b'
        and md5(pg_get_viewdef('public.published_clinic_public_profiles'::regclass)) = '5fa07dcf12a9097d54de0cf723aa2517',
    'expect_search_key_samples',
        public.clinic_display_name_search_key('CLÍNICA  Peña') = 'clinica pena'
        and public.clinic_display_name_search_key(U&'\FB01nca\3000\00A0X') = 'finca x'
        and public.clinic_display_name_search_key('ØSTER' collate "C") = 'øster'
        and public.clinic_display_name_search_key('50% [A]_') = '50% [a]_',
    'data', jsonb_build_object(
        'basic_discovery_rows', (select count(*) from public.published_clinic_public_profiles),
        'basic_discovery_without_location', (select count(*) from public.published_clinic_public_profiles as basic
                                             where not exists (select 1 from public.clinic_locations as location
                                                               where location.clinic_id = basic.clinic_id)),
        'basic_discovery_unnamed', (select count(*) from public.published_clinic_public_profiles where display_name is null),
        'basic_discovery_repeated_names', (select count(*) from (
                                               select display_name from public.published_clinic_public_profiles
                                               where display_name is not null
                                               group by display_name having count(*) > 1) as repeated),
        'unpublished_clinics', (select count(*) from public.clinics where not is_published)
    ),
    'behaviour', current_setting('dis004.behaviour')::jsonb,
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

-- Regression suite for SPEC-DIS-004 — Search Published Clinics by Name,
-- migration 20261120090000_published_clinic_name_search.sql.
--
-- Run only against an isolated LOCAL database with every source-controlled
-- migration applied. All fixtures and assertions are rolled back (prefix
-- d1040000-). Superuser execution is required solely to load a deliberately
-- minimal deterministic context with establishment triggers bypassed, to
-- mutate it between pages, and to act as anon / authenticated.
--
-- Covers BR-1..BR-9, §4 and Verification Notes 1–11:
--   A  contract, ACL, helper ACL, independence, existing reads unchanged (1, 10)
--   B  input validation, identical for anon and authenticated (9)
--   C  parity with published_clinic_public_profiles + get_published_clinic_location,
--      for every caller × search × page size (1, 2, 3, 4, 7)
--   D  address: public only, no Location ⇒ null, never repeated (3, 4)
--   E  order, identical names, unnamed rows, cursor boundaries (6, 7)
--   F  cursors naming unpublished or unknown Clinics (8)
--   G  normalization and matching with literal expectations (5)
--   H  changes between pages (BR-8)
--   I  no writes (11)
--   V  volume: 6 000 Clinics (5 000 published), full traversals and timings
begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

-- 'OK', or the SQLSTATE and message a statement fails with.
create function pg_temp.sqlstate_of(p_statement text)
returns text language plpgsql as $$
begin
    execute p_statement;
    return 'OK';
exception when others then
    return sqlstate || ': ' || sqlerrm;
end;
$$;

-- Fixture identifiers: d1040000-0000-4000-8000-<12 hex digits>.
create function pg_temp.fx(p_suffix text)
returns uuid language sql immutable as $$
    select ('d1040000-0000-4000-8000-' || lpad(p_suffix, 12, '0'))::uuid
$$;

-- Clinic n (1–99).
create function pg_temp.c(p_number integer)
returns uuid language sql immutable as $$
    select pg_temp.fx('4' || lpad(p_number::text, 3, '0'))
$$;

-- One envelope of the read as the current role.
create function pg_temp.page(
    p_search text, p_after_name text, p_after_id uuid, p_limit integer
)
returns jsonb language sql as $$
    select public.discover_published_clinics(p_search, p_after_name, p_after_id, p_limit)
$$;

-- One page as an ordered uuid array.
create function pg_temp.page_ids(
    p_search text, p_after_name text, p_after_id uuid, p_limit integer
)
returns uuid[] language sql as $$
    select coalesce(array_agg((row_entry ->> 'clinic_id')::uuid order by ordinality), '{}')
    from jsonb_array_elements(
        public.discover_published_clinics(p_search, p_after_name, p_after_id, p_limit) -> 'clinics'
    ) with ordinality as listed (row_entry, ordinality)
$$;

-- Every page for one search and page size, as the current role, from an
-- optional starting cursor, concatenated. Fails if a page exceeds its size,
-- repeats a Clinic, carries a cursor other than its last row, announces more
-- rows that do not follow, or the list does not end.
create function pg_temp.read_pages(
    p_search text, p_page_size integer,
    p_after_name text default null, p_after_id uuid default null
)
returns jsonb language plpgsql as $$
declare
    all_rows jsonb := '[]'::jsonb;
    envelope jsonb;
    page_rows jsonb;
    page_count integer;
    previous_has_more boolean := false;
    after_name text := p_after_name;
    after_id uuid := p_after_id;
    pages integer := 0;
begin
    loop
        pages := pages + 1;
        perform pg_temp.assert_true(pages <= 400, 'Pages: the list ends');
        begin
            envelope := public.discover_published_clinics(p_search, after_name, after_id, p_page_size);
        exception when others then
            raise notice 'read_pages failed: % %', sqlstate, sqlerrm;
            envelope := null;
        end;
        perform pg_temp.assert_true(envelope is not null, 'Pages: the read never fails for valid input');
        page_rows := envelope -> 'clinics';
        page_count := jsonb_array_length(page_rows);
        perform pg_temp.assert_true(
            (select array_agg(envelope_key order by envelope_key collate "C") from jsonb_object_keys(envelope) as envelope_key)
                = array['clinics', 'has_more', 'next_after_clinic_id', 'next_after_display_name']
            and page_count <= p_page_size
            and page_count = (select count(distinct row_entry ->> 'clinic_id') from jsonb_array_elements(page_rows) as row_entry)
            and envelope -> 'next_after_clinic_id' = coalesce(page_rows -> -1 -> 'clinic_id', 'null'::jsonb)
            and envelope -> 'next_after_display_name' = coalesce(page_rows -> -1 -> 'display_name', 'null'::jsonb)
            and (not (envelope ->> 'has_more')::boolean or page_count = p_page_size),
            'Pages: no page exceeds its limit or repeats a Clinic, and its cursor is its last row'
        );
        perform pg_temp.assert_true(
            not (previous_has_more and page_count = 0),
            'Pages: has_more announces a further row'
        );
        perform pg_temp.assert_true(
            not exists (
                select 1 from jsonb_array_elements(page_rows) as row_entry
                where (select array_agg(row_key order by row_key collate "C") from jsonb_object_keys(row_entry) as row_key)
                      is distinct from array['address_text', 'clinic_id', 'description', 'display_name']),
            'Rows: only clinic_id, display_name, description and address_text'
        );
        all_rows := all_rows || page_rows;
        previous_has_more := (envelope ->> 'has_more')::boolean;
        exit when not previous_has_more;
        after_id := (envelope ->> 'next_after_clinic_id')::uuid;
        after_name := envelope ->> 'next_after_display_name';
    end loop;
    return all_rows;
end;
$$;

-- Oracle, as the superuser: the Clinics the existing basic Discovery surface
-- shows (published_clinic_public_profiles), each with the address of the
-- existing public Location read, narrowed by BR-5, in BR-6 order, strictly
-- after an optional cursor.
create function pg_temp.oracle(
    p_search text, p_after_name text default null, p_after_id uuid default null
)
returns jsonb language sql as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'clinic_id', listed.clinic_id,
               'display_name', listed.display_name,
               'description', listed.description,
               'address_text', (select location.address_text
                                from public.get_published_clinic_location(listed.clinic_id) as location))
               order by listed.display_name nulls last, listed.clinic_id), '[]'::jsonb)
    from public.published_clinic_public_profiles as listed
    where (nullif(public.clinic_display_name_search_key(p_search), '') is null
           or (listed.display_name is not null
               and strpos(public.clinic_display_name_search_key(listed.display_name),
                          public.clinic_display_name_search_key(p_search)) > 0))
      and (p_after_id is null
           or case when p_after_name is null
                   then listed.display_name is null and listed.clinic_id > p_after_id
                   else listed.display_name is null
                        or listed.display_name > p_after_name
                        or (listed.display_name = p_after_name and listed.clinic_id > p_after_id)
              end)
$$;

create function pg_temp.sorted(p_ids uuid[])
returns uuid[] language sql immutable as $$
    select coalesce(array_agg(id order by id), '{}') from unnest(p_ids) as id
$$;

create function pg_temp.json_ids(p_rows jsonb)
returns uuid[] language sql immutable as $$
    select coalesce(array_agg((row_entry ->> 'clinic_id')::uuid order by ordinality), '{}')
    from jsonb_array_elements(p_rows) with ordinality as listed (row_entry, ordinality)
$$;

create temporary table violation (section text not null, detail text not null) on commit drop;

set local session_replication_role = replica;

-- ===========================================================================
-- Fixtures.
--
-- Auth subjects …-0000000001NN, domain Users …-0000000002NN:
--   01 Guardian of a Pet   02 OrgA OWNER   03 subject without a domain User
--
-- Organizations …03NN: A "Animalia Group", B "Search Group".
--
-- Clinics …04NN (P = published, L = has a Location):
--   01 P L "Animalia Madrid Centro"      05   L "Animalia Alcobendas" (unpublished)
--   02 P L "Animalia Getafe"             06 P   no public profile
--   03 P   "Animalia Getafe"             07 P   profile without a display name
--   04 P   "Animalia Getafe"             08 P L profile without a display name
--   09     unnamed, unpublished          29     "Clínica Oculta" (unpublished)
--   10 P L "Clínica Centro" (description and address only searchable by name)
--   11–28, 30, 31 P — normalization names below; 41–52 P "Aaa Filler NN".
-- ===========================================================================

insert into auth.users (id, email_confirmed_at)
select pg_temp.fx('1' || lpad(n::text, 2, '0')), '2020-01-01Z' from generate_series(1, 3) as n;
insert into public.users (id)
select pg_temp.fx('2' || lpad(n::text, 2, '0')) from generate_series(1, 2) as n;
insert into public.user_authentication_identities (user_id, provider_subject)
select pg_temp.fx('2' || lpad(n::text, 2, '0')), pg_temp.fx('1' || lpad(n::text, 2, '0'))
from generate_series(1, 2) as n;

insert into public.veterinary_organizations (id, display_name) values
    (pg_temp.fx('301'), 'Animalia Group'),
    (pg_temp.fx('302'), 'Search Group');

insert into public.clinics (id, organization_id, is_published)
select pg_temp.c(n), case when n < 10 then pg_temp.fx('301') else pg_temp.fx('302') end,
       n not in (5, 9, 29)
from generate_series(1, 31) as n;
insert into public.clinics (id, organization_id, is_published)
select pg_temp.c(n), pg_temp.fx('302'), true from generate_series(41, 52) as n;

insert into public.clinic_public_profiles (clinic_id, display_name, description, public_phone, public_email, website) values
    (pg_temp.c(1), 'Animalia Madrid Centro', 'Centro de Madrid', '+34 600 000 001', 'centro@example.test', 'https://centro.example.test'),
    (pg_temp.c(2), 'Animalia Getafe', null, null, null, null),
    (pg_temp.c(3), 'Animalia Getafe', 'Segunda de Getafe', null, null, null),
    (pg_temp.c(4), 'Animalia Getafe', null, null, null, null),
    (pg_temp.c(5), 'Animalia Alcobendas', 'Unpublished description must not leak', null, null, null),
    (pg_temp.c(7), null, 'Unnamed published Clinic', null, null, null),
    (pg_temp.c(8), null, null, '+34 600 000 008', null, null),
    (pg_temp.c(9), null, 'Unnamed unpublished Clinic', null, null, null),
    (pg_temp.c(10), 'Clínica Centro', 'zzdesc only here', null, null, null),
    (pg_temp.c(11), 'Clinica Centro', null, null, null, null),
    (pg_temp.c(12), 'Cli' || U&'\0301' || 'nica Centro', null, null, null, null),
    (pg_temp.c(13), 'Clínica  Centro', null, null, null, null),
    (pg_temp.c(14), 'Clínica' || U&'\00A0' || 'Centro', null, null, null, null),
    (pg_temp.c(15), 'Peña Vet', null, null, null, null),
    (pg_temp.c(16), 'PEÑA', null, null, null, null),
    (pg_temp.c(17), 'Pena', null, null, null, null),
    (pg_temp.c(18), 'Tasa 50% Centro', null, null, null, null),
    (pg_temp.c(19), 'Ab_C', null, null, null, null),
    (pg_temp.c(20), 'X [x] a\b', null, null, null, null),
    (pg_temp.c(21), 'Straße', null, null, null, null),
    (pg_temp.c(22), 'ØSTER Vet', null, null, null, null),
    (pg_temp.c(23), 'finca', null, null, null, null),
    (pg_temp.c(24), U&'\FF23\FF4C\FF49\FF4E\FF49\FF43\FF41', null, null, null, null),
    (pg_temp.c(25), 'Clínica Veterinaria Peña', null, null, null, null),
    (pg_temp.c(26), 'ŒUVRE Clinic', null, null, null, null),
    (pg_temp.c(27), U&'\0130' || 'stanbul Vet', null, null, null, null),
    (pg_temp.c(28), 'Zero' || U&'\200B' || 'Width', null, null, null, null),
    (pg_temp.c(29), 'Clínica Oculta', null, null, null, null),
    (pg_temp.c(30), 'AbXC', null, null, null, null),
    (pg_temp.c(31), 'Tasa 50 Centro', null, null, null, null);
insert into public.clinic_public_profiles (clinic_id, display_name)
select pg_temp.c(n), 'Aaa Filler ' || lpad((n - 40)::text, 2, '0') from generate_series(41, 52) as n;

insert into public.clinic_locations (clinic_id, address_text, latitude, longitude) values
    (pg_temp.c(1), 'Calle Mayor 1, Madrid', 40.4168, -3.7038),
    (pg_temp.c(2), 'Avenida de España 2, Getafe', 40.3057, -3.7329),
    (pg_temp.c(5), 'Secret Street 99, Alcobendas', 40.5475, -3.6420),
    (pg_temp.c(8), 'Calle Sin Nombre 8, Madrid', 40.4200, -3.7000),
    (pg_temp.c(10), 'zzaddr only here', 40.4300, -3.6900);

insert into public.organization_memberships (id, organization_id, user_id, effective_start, effective_end, ended_by_user_id)
values (pg_temp.fx('502'), pg_temp.fx('301'), pg_temp.fx('202'), '2020-01-01Z', null, null);
insert into public.organization_responsibility_grants (
    id, membership_id, responsibility, scope_type, clinic_id,
    effective_start, effective_end, granted_by_user_id, ended_by_user_id
) values (pg_temp.fx('602'), pg_temp.fx('502'), 'OWNER', 'ORGANIZATION', null, '2020-01-01Z', null, pg_temp.fx('202'), null);

insert into public.pets (id, name, species, created_at)
values (pg_temp.fx('b01'), 'Luna', 'canine', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start)
values (pg_temp.fx('b02'), pg_temp.fx('201'), pg_temp.fx('b01'), '2020-01-01Z');

set local session_replication_role = origin;

-- The callers of section C: anon, a Guardian, an Organization Owner, and an
-- authenticated subject without a domain User. The read never consults them.
create temporary table caller (label text primary key, role_name text not null, subject uuid) on commit drop;
insert into caller values
    ('anon', 'anon', null),
    ('guardian', 'authenticated', pg_temp.fx('101')),
    ('owner', 'authenticated', pg_temp.fx('102')),
    ('no domain user', 'authenticated', pg_temp.fx('103'));

-- ===========================================================================
-- A. Contract and ACL (VN 1, 10).
-- ===========================================================================

select pg_temp.assert_true(
    (select count(*) from pg_proc
     where proname = 'discover_published_clinics' and pronamespace = 'public'::regnamespace) = 1
    and (select prosecdef and provolatile = 's' and proconfig = array['search_path=""']
                and pg_get_function_identity_arguments(oid)
                    = 'p_search text, p_after_display_name text, p_after_clinic_id uuid, p_limit integer'
                and pg_get_function_result(oid) = 'jsonb'
                and pronargdefaults = 4
         from pg_proc where oid = 'public.discover_published_clinics(text, text, uuid, integer)'::regprocedure)
    and (select not prosecdef and provolatile = 'i' and proconfig = array['search_path=""']
         from pg_proc where oid = 'public.clinic_display_name_search_key(text)'::regprocedure),
    'Contract: one STABLE SECURITY DEFINER overload with the §4 arguments, returning jsonb'
);

select pg_temp.assert_true(
    (select proacl::text from pg_proc where oid = 'public.discover_published_clinics(text, text, uuid, integer)'::regprocedure)
        = '{postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres}'
    and has_function_privilege('anon', 'public.discover_published_clinics(text, text, uuid, integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.discover_published_clinics(text, text, uuid, integer)', 'EXECUTE')
    and not exists (select 1 from aclexplode((select proacl from pg_proc
                    where oid = 'public.discover_published_clinics(text, text, uuid, integer)'::regprocedure)) as acl
                    where acl.grantee = 0)
    and (select proacl::text from pg_proc where oid = 'public.clinic_display_name_search_key(text)'::regprocedure)
        = '{postgres=X/postgres}'
    and not has_function_privilege('anon', 'public.clinic_display_name_search_key(text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.clinic_display_name_search_key(text)', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.clinic_display_name_search_key(text)', 'EXECUTE'),
    'Grants: the read as every Discovery read (anon, authenticated); the search helper executable by no client'
);

-- No client privilege on the underlying tables; the existing view unchanged.
select pg_temp.assert_true(
    (select relacl::text from pg_class where oid = 'public.clinics'::regclass)
        = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
    and (select relacl::text from pg_class where oid = 'public.clinic_locations'::regclass)
        = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
    and (select relacl::text from pg_class where oid = 'public.clinic_public_profiles'::regclass)
        = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
    and (select relacl::text from pg_class where oid = 'public.published_clinic_public_profiles'::regclass)
        = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres}'
    and md5(pg_get_viewdef('public.published_clinic_public_profiles'::regclass)) = '5fa07dcf12a9097d54de0cf723aa2517',
    'Tables: no client privilege added; the basic Discovery view unchanged'
);

-- The professional normalization and every existing Discovery read keep
-- their definition and grants.
select pg_temp.assert_true(
    md5(pg_get_functiondef('public.professional_clinic_search_key(text)'::regprocedure)) = '53cc64a22c3c1b31ecd3a106116bbc58'
    and (select proacl::text from pg_proc where oid = 'public.professional_clinic_search_key(text)'::regprocedure) = '{postgres=X/postgres}'
    and md5(pg_get_functiondef('public.get_published_clinic_location(uuid)'::regprocedure)) = 'a6cb0b1ce427ea49c9cfac71126c66b2'
    and md5(pg_get_functiondef('public.discover_nearby_clinics(double precision,double precision,double precision,integer,double precision,uuid)'::regprocedure)) = 'ea1eddd8d37697ee872a8bf7c585964b'
    and md5(pg_get_functiondef('public.discover_clinics_in_viewport(double precision,double precision,double precision,double precision,integer,uuid)'::regprocedure)) = '15c682253cc4ceaac79270e49815ae1b'
    and md5(pg_get_functiondef('public.get_published_clinic_service_offerings(uuid)'::regprocedure)) = '8cbda91bc08628db0fcb70d8235f6af1'
    and md5(pg_get_functiondef('public.get_published_clinic_opening_hours(uuid)'::regprocedure)) = '73758916b2b48985f2689cebb75764ff',
    'Existing reads unchanged: professional normalization and Discovery reads'
);

-- Independence (BR-2): no identity, professional helper, authorization
-- predicate, lock or write; one statement over the published Clinics, with no
-- per-Clinic read.
select pg_temp.assert_true(
    (select prosrc like '%clinic.is_published = true%'
            and prosrc like '%public.clinic_display_name_search_key(%'
            and prosrc not like '%auth.%'
            and prosrc not like '%current_domain_user_id%'
            and prosrc not like '%professional%'
            and prosrc not like '%user_has_%'
            and prosrc not like '%capabilit%'
            and prosrc not like '%membership%'
            and prosrc not like '%guardianship%'
            and prosrc not like '%entitlement%'
            and prosrc not like '%subscription%'
            and prosrc not like '%get_published_clinic_%'
            and prosrc not like '%service_offering%'
            and prosrc not like '%opening%'
            and (length(prosrc) - length(replace(prosrc, 'from public.clinics', ''))) / length('from public.clinics') = 1
            and lower(prosrc) not like '%for update%'
            and lower(prosrc) not like '%for share%'
            and lower(prosrc) not like '%for no key update%'
            and lower(prosrc) not like '%for key share%'
            and lower(prosrc) not like '%insert into%'
            and lower(prosrc) not like '%update public.%'
            and lower(prosrc) not like '%delete from%'
            and lower(prosrc) not like '%loop%'
     from pg_proc where oid = 'public.discover_published_clinics(text, text, uuid, integer)'::regprocedure),
    'Independence: no identity, professional helper, per-Clinic read, lock or write'
);

-- Direct client access stays denied.
set local role anon;
select pg_temp.assert_true(
    pg_temp.sqlstate_of('select public.clinic_display_name_search_key(''x'')') like '42501:%'
    and pg_temp.sqlstate_of('select * from public.clinics') like '42501:%'
    and pg_temp.sqlstate_of('select * from public.clinic_locations') like '42501:%'
    and pg_temp.sqlstate_of('select * from public.clinic_public_profiles') like '42501:%',
    'Direct access: anon cannot call the helper or read the tables'
);
reset role;
select set_config('request.jwt.claim.sub', pg_temp.fx('101')::text, true);
set local role authenticated;
select pg_temp.assert_true(
    pg_temp.sqlstate_of('select public.clinic_display_name_search_key(''x'')') like '42501:%'
    and pg_temp.sqlstate_of('select * from public.clinic_locations') like '42501:%',
    'Direct access: authenticated cannot call the helper or read the tables'
);
reset role;

-- ===========================================================================
-- B. Input validation (VN 9), identical for every caller.
-- ===========================================================================

do $$
declare
    who record;
    statement text;
begin
    for who in select * from caller order by label loop
        perform set_config('request.jwt.claim.sub', coalesce(who.subject::text, ''), true);
        execute format('set local role %I', who.role_name);
        foreach statement in array array[
            'select public.discover_published_clinics(null, null, null, null)',
            'select public.discover_published_clinics(null, null, null, 0)',
            'select public.discover_published_clinics(null, null, null, -1)',
            'select public.discover_published_clinics(null, null, null, 51)',
            'select public.discover_published_clinics(null, null, null, 1000)',
            'select public.discover_published_clinics(null, ''Animalia Getafe'', null, 20)',
            'select public.discover_published_clinics(repeat(''a'', 101), null, null, 20)',
            'select public.discover_published_clinics(repeat(''á'', 101), null, null, 20)'
        ] loop
            perform pg_temp.assert_true(
                pg_temp.sqlstate_of(statement) = '22023: Published Clinics page is invalid',
                'Validation: 22023 for every invalid input'
            );
        end loop;
        reset role;
    end loop;
end;
$$;

set local role anon;
select pg_temp.assert_true(
    pg_temp.sqlstate_of('select public.discover_published_clinics(repeat(''á'', 100), null, null, 20)') = 'OK'
    and pg_temp.sqlstate_of('select public.discover_published_clinics(null, null, null, 1)') = 'OK'
    and pg_temp.sqlstate_of('select public.discover_published_clinics(null, null, null, 50)') = 'OK'
    and pg_temp.sqlstate_of(format('select public.discover_published_clinics(null, null, %L::uuid, 20)', pg_temp.c(1))) = 'OK'
    and public.discover_published_clinics() = pg_temp.page(null, null, null, 20),
    'Validation accepts a 100-character search, limits 1 and 50, an id-only cursor, and defaults to 20'
);
reset role;

-- ===========================================================================
-- C. Parity with the existing basic Discovery surface (VN 1, 2, 3, 4, 7):
--    every caller × search × page size reads exactly the oracle.
-- ===========================================================================

create temporary table search_term (label text primary key, term text) on commit drop;
insert into search_term values
    ('none', null), ('empty', ''), ('animalia', 'animalia'), ('getafe', 'GETAFE'),
    ('clinica', 'clinica'), ('pena', 'peña'), ('centro', 'centro'), ('filler', 'filler'),
    ('unpublished name', 'alcobendas'), ('description', 'zzdesc'), ('address', 'zzaddr'),
    ('no match', 'zz no match');

do $$
declare
    search record;
    who record;
    expected jsonb;
    actual jsonb;
    page_size integer;
begin
    for search in select * from search_term order by label loop
        expected := pg_temp.oracle(search.term);
        for who in select * from caller order by label loop
            for page_size in 1..least(jsonb_array_length(expected) + 1, 50) loop
                perform set_config('request.jwt.claim.sub', coalesce(who.subject::text, ''), true);
                execute format('set local role %I', who.role_name);
                actual := pg_temp.read_pages(search.term, page_size);
                reset role;
                if actual is distinct from expected then
                    insert into violation values ('C', format('%s search %s size %s: expected %s got %s',
                        who.label, search.label, page_size, expected, actual));
                end if;
            end loop;
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (select 1 from violation where section = 'C'),
    'Parity: pages equal the published Clinics of basic Discovery for every caller, search and page size'
);

-- The oracle itself is the documented eligible set (BR-1).
select pg_temp.assert_true(
    pg_temp.sorted(pg_temp.json_ids(pg_temp.oracle(null)))
        = pg_temp.sorted(array(select pg_temp.c(n) from generate_series(1, 52) as n
                               where n not in (5, 6, 9, 29) and (n <= 31 or n >= 41))),
    'Eligibility: published Clinics with a public profile, nothing else'
);

-- ===========================================================================
-- D. Address (VN 3, 4).
-- ===========================================================================

create temporary table everything (ordinality bigint, row_entry jsonb) on commit drop;
grant insert, select on everything to anon;
set local role anon;
insert into everything
select ordinality, row_entry
from jsonb_array_elements(pg_temp.read_pages(null, 50)) with ordinality as listed (row_entry, ordinality);
reset role;

select pg_temp.assert_true(
    (select row_entry ->> 'address_text' from everything where row_entry ->> 'clinic_id' = pg_temp.c(1)::text)
        = 'Calle Mayor 1, Madrid'
    and (select row_entry ->> 'address_text' from everything where row_entry ->> 'clinic_id' = pg_temp.c(8)::text)
        = 'Calle Sin Nombre 8, Madrid'
    and (select row_entry -> 'address_text' from everything where row_entry ->> 'clinic_id' = pg_temp.c(3)::text)
        = 'null'::jsonb
    and (select row_entry -> 'address_text' from everything where row_entry ->> 'clinic_id' = pg_temp.c(7)::text)
        = 'null'::jsonb
    and (select row_entry -> 'description' from everything where row_entry ->> 'clinic_id' = pg_temp.c(3)::text)
        = '"Segunda de Getafe"'::jsonb,
    'Address: the public Location address when present, null without a Location'
);

select pg_temp.assert_true(
    (select count(*) from everything) = (select count(distinct row_entry ->> 'clinic_id') from everything)
    and (select string_agg(row_entry::text, ' ') from everything) not like '%Secret Street%'
    and (select string_agg(row_entry::text, ' ') from everything) not like '%Unpublished description%'
    and (select string_agg(row_entry::text, ' ') from everything) not like '%Alcobendas%'
    and (select string_agg(row_entry::text, ' ') from everything) not like '%Oculta%'
    and (select string_agg(row_entry::text, ' ') from everything) not like '%+34%'
    and (select string_agg(row_entry::text, ' ') from everything) not like '%example.test%'
    and (select string_agg(row_entry::text, ' ') from everything) not like '%40.4%',
    'Address: no unpublished Clinic, contact detail or coordinate is ever returned, and no Clinic twice'
);

-- Exactly the Locations the Map read exposes, with the same address.
create temporary table viewport_rows (clinic_id text, address_text text) on commit drop;
grant insert on viewport_rows to anon;
set local role anon;
insert into viewport_rows
select row_entry ->> 'clinic_id' as clinic_id, row_entry ->> 'address_text' as address_text
from jsonb_array_elements(public.discover_clinics_in_viewport(-90, 90, -180, 180, 100, null) -> 'clinics') as row_entry
where row_entry ->> 'clinic_id' like 'd1040000-%';
reset role;
select pg_temp.assert_true(
    (select array_agg(clinic_id || '|' || address_text order by clinic_id) from viewport_rows)
        = (select array_agg((row_entry ->> 'clinic_id') || '|' || (row_entry ->> 'address_text') order by row_entry ->> 'clinic_id')
           from everything where row_entry ->> 'address_text' is not null),
    'Address: located rows equal the Map read''s published Locations'
);

-- ===========================================================================
-- E. Order, identical names, unnamed rows, cursor boundaries (VN 6, 7).
-- ===========================================================================

set local role anon;
select pg_temp.assert_true(
    pg_temp.page_ids('getafe', null, null, 1) = array[pg_temp.c(2)]
    and pg_temp.page_ids('getafe', 'Animalia Getafe', pg_temp.c(2), 1) = array[pg_temp.c(3)]
    and pg_temp.page_ids('getafe', 'Animalia Getafe', pg_temp.c(3), 1) = array[pg_temp.c(4)]
    and pg_temp.page_ids('getafe', 'Animalia Getafe', pg_temp.c(4), 1) = '{}'
    and (pg_temp.page('getafe', 'Animalia Getafe', pg_temp.c(3), 1) ->> 'has_more')::boolean is false
    and pg_temp.page_ids('getafe', null, null, 3) = array[pg_temp.c(2), pg_temp.c(3), pg_temp.c(4)],
    'Order: identical names are told apart by clinic_id'
);

select pg_temp.assert_true(
    (select array_agg((row_entry ->> 'clinic_id')::uuid order by ordinality) from everything where ordinality > 37)
        = array[pg_temp.c(7), pg_temp.c(8)]
    and (select bool_and(row_entry -> 'display_name' <> 'null'::jsonb) from everything where ordinality <= 37)
    and pg_temp.page_ids(null, null, pg_temp.c(7), 20) = array[pg_temp.c(8)]
    and pg_temp.page_ids(null, null, pg_temp.c(8), 20) = '{}'
    and pg_temp.page_ids(null, null, pg_temp.fx('3fff'), 20) = array[pg_temp.c(7), pg_temp.c(8)]
    and pg_temp.page_ids(null, (select row_entry ->> 'display_name' from everything where ordinality = 37),
                         (select (row_entry ->> 'clinic_id')::uuid from everything where ordinality = 37), 20)
        = array[pg_temp.c(7), pg_temp.c(8)]
    and pg_temp.page(null, null, pg_temp.c(7), 1) -> 'next_after_display_name' = 'null'::jsonb
    and pg_temp.page(null, null, pg_temp.c(7), 1) ->> 'next_after_clinic_id' = pg_temp.c(8)::text,
    'Order: unnamed Clinics last, by clinic_id, reachable after a named or an unnamed cursor'
);
reset role;

-- The order is the database default collation of the display name, not the
-- normalized key.
select pg_temp.assert_true(
    (select array_agg(row_entry ->> 'display_name' order by ordinality) from everything where ordinality <= 37)
        = (select array_agg(profile.display_name order by profile.display_name, profile.clinic_id)
           from public.clinic_public_profiles as profile
           join public.clinics as clinic on clinic.id = profile.clinic_id
           where profile.clinic_id::text like 'd1040000-%' and clinic.is_published and profile.display_name is not null),
    'Order: display name in the default collation'
);

-- A cursor between rows: a name that no Clinic has.
set local role anon;
select pg_temp.assert_true(
    pg_temp.page_ids(null, 'Animalia H', pg_temp.fx('4fff'), 1) = array[pg_temp.c(1)]
    and pg_temp.page_ids(null, 'Animalia Getafe', pg_temp.fx('4fff'), 1) = array[pg_temp.c(1)],
    'Cursor: a position between rows continues with the next row'
);
reset role;

-- ===========================================================================
-- F. Cursors naming unpublished or unknown Clinics (VN 8).
-- ===========================================================================

do $$
declare
    probe record;
    who record;
    actual jsonb;
begin
    for probe in select * from (values
        ('unpublished named', 'Animalia Alcobendas', pg_temp.c(5), null::text),
        ('unpublished unnamed', null, pg_temp.c(9), null),
        ('unpublished matching', 'Clínica Oculta', pg_temp.c(29), 'clinica'),
        ('unknown id', 'Animalia Getafe', pg_temp.fx('4ffe'), null),
        ('unknown unnamed', null, pg_temp.fx('4ffe'), null),
        ('no-profile Clinic', null, pg_temp.c(6), null)
    ) as cases (label, after_name, after_id, search) loop
        for who in select * from caller order by label loop
            perform set_config('request.jwt.claim.sub', coalesce(who.subject::text, ''), true);
            execute format('set local role %I', who.role_name);
            actual := pg_temp.read_pages(probe.search, 3, probe.after_name, probe.after_id);
            reset role;
            if actual is distinct from pg_temp.oracle(probe.search, probe.after_name, probe.after_id) then
                insert into violation values ('F', format('%s as %s: %s', probe.label, who.label, actual));
            end if;
        end loop;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (select 1 from violation where section = 'F'),
    'Cursor: any cursor returns only eligible rows strictly after its position'
);

-- ===========================================================================
-- G. Normalization and matching, literal expectations (VN 5).
-- ===========================================================================

-- G1. N(text) literal values, also under collation "C" and a libc collation.
select pg_temp.assert_true(
    public.clinic_display_name_search_key(input) is not distinct from expected
    and public.clinic_display_name_search_key(input collate "C") is not distinct from expected
    and public.clinic_display_name_search_key(input collate "en_US.utf8") is not distinct from expected,
    'Normalization ' || label
)
from (values
    ('acute upper', 'CLÍNICA', 'clinica'),
    ('enye', 'Peña', 'pena'),
    ('decomposed', 'PEN' || U&'\0303' || 'A', 'pena'),
    ('diaeresis', 'Pingüino', 'pinguino'),
    ('o-stroke upper', 'ØSTER', 'øster'),
    ('oe upper', 'ŒUVRE', 'œuvre'),
    ('ae upper', 'ÆGIR', 'ægir'),
    ('l-stroke upper', 'ŁÓDŹ', 'łodz'),
    ('dotted capital I', U&'\0130' || 'STANBUL', 'istanbul'),
    ('cyrillic', 'ПРИВЕТ', 'привет'),
    ('sharp s kept', 'STRAßE', 'straße'),
    ('ligature', U&'\FB01' || 'NCA', 'finca'),
    ('fullwidth', U&'\FF23\FF2C\FF29\FF2E\FF29\FF23\FF21', 'clinica'),
    ('nbsp', 'A' || U&'\00A0' || 'B', 'a b'),
    ('narrow nbsp', 'A' || U&'\202F' || 'B', 'a b'),
    ('ideographic space', 'A' || U&'\3000' || 'B', 'a b'),
    ('em space', 'A' || U&'\2003' || 'B', 'a b'),
    ('line separator', 'A' || U&'\2028' || 'B', 'a b'),
    ('next line', 'A' || U&'\0085' || 'B', 'a b'),
    ('ogham space', 'A' || U&'\1680' || 'B', 'a b'),
    ('controls', E'A\t\n\r\f\u000bB', 'a b'),
    ('runs and ends', E'  Clínica \t  Centro  ', 'clinica centro'),
    ('zero width kept', 'A' || U&'\200B' || 'B', 'a' || U&'\200B' || 'b'),
    ('literals', '50% [A]_\*', '50% [a]_\*'),
    ('empty', '', ''),
    ('only spaces', E' \t' || U&'\00A0', ''),
    ('null', null, null)
) as cases (label, input, expected);

-- G2. The same function as SPEC-ORG-008 BR-22 today, on every fixture name.
select pg_temp.assert_true(
    not exists (
        select 1 from public.clinic_public_profiles as profile
        where profile.clinic_id::text like 'd1040000-%'
          and public.clinic_display_name_search_key(profile.display_name)
              is distinct from public.professional_clinic_search_key(profile.display_name)),
    'Normalization: identical to SPEC-ORG-008 BR-22 on every fixture name'
);

-- G3. Matching through the read, as anon.
create function pg_temp.match_set(p_term text)
returns uuid[] language sql as $$
    select pg_temp.sorted(pg_temp.page_ids(p_term, null, null, 50))
$$;

set local role anon;
select pg_temp.assert_true(
    pg_temp.match_set(term) = pg_temp.sorted(array(select pg_temp.c(n) from unnest(expected) as n)),
    'Search ' || label
)
from (values
    ('clinica', 'clinica', array[10,11,12,13,14,24,25]),
    ('Clínica', 'Clínica', array[10,11,12,13,14,24,25]),
    ('CLÍNICA', 'CLÍNICA', array[10,11,12,13,14,24,25]),
    ('fullwidth', U&'\FF23\FF4C\FF49\FF4E\FF49\FF43\FF41', array[10,11,12,13,14,24,25]),
    ('pena', 'pena', array[15,16,17,25]),
    ('peña', 'peña', array[15,16,17,25]),
    ('decomposed PEÑA', 'PEN' || U&'\0303' || 'A', array[15,16,17,25]),
    ('veterinaria peña', 'veterinaria   peña', array[25]),
    ('vet', '  vet  ', array[15,22,25,27]),
    ('clinica centro', 'clinica centro', array[10,11,12,13,14]),
    ('clinica nbsp centro', 'clinica' || U&'\00A0' || 'centro', array[10,11,12,13,14]),
    ('animalia getafe', 'animalia getafe', array[2,3,4]),
    ('ligature', U&'\FB01' || 'nca', array[23]),
    ('percent', '%', array[18]),
    ('percent centro', '50% centro', array[18]),
    ('underscore', '_', array[19]),
    ('underscore pattern', 'ab_c', array[19]),
    ('backslash', '\', array[20]),
    ('bracket', '[', array[20]),
    ('øster', 'øster', array[22]),
    ('ØSTER', 'ØSTER', array[22]),
    ('oster', 'oster', array[]::integer[]),
    ('strasse', 'strasse', array[]::integer[]),
    ('straße', 'STRAßE', array[21]),
    ('œuvre', 'œuvre', array[26]),
    ('istanbul', 'istanbul', array[27]),
    ('zero', 'zero', array[28]),
    ('zerowidth', 'zerowidth', array[]::integer[]),
    ('filler 1', 'FILLER 1', array[50,51,52]),
    ('unpublished', 'oculta', array[]::integer[]),
    ('unpublished name', 'alcobendas', array[]::integer[]),
    ('description only', 'zzdesc', array[]::integer[]),
    ('address only', 'zzaddr', array[]::integer[]),
    ('organization only', 'search group', array[]::integer[]),
    ('no match', 'zz no match', array[]::integer[])
) as cases (label, term, expected);

select pg_temp.assert_true(
    pg_temp.match_set(term) = pg_temp.match_set(null)
    and cardinality(pg_temp.match_set(null)) = 39,
    'Search without narrowing ' || label
)
from (values ('empty', ''), ('spaces', E' \t '), ('nbsp', U&'\00A0\3000')) as cases (label, term);

select pg_temp.assert_true(
    not (pg_temp.c(7) = any (pg_temp.match_set('a')) or pg_temp.c(8) = any (pg_temp.match_set('a')))
    and cardinality(pg_temp.match_set('a')) > 10,
    'Search: an unnamed Clinic never matches a non-empty search'
);

-- G4. A search carrying collation "C" or a libc collation behaves the same.
select pg_temp.assert_true(
    pg_temp.sorted(pg_temp.page_ids('ØSTER' collate "C", null, null, 50)) = array[pg_temp.c(22)]
    and pg_temp.sorted(pg_temp.page_ids('CLÍNICA' collate "C", null, null, 50)) = pg_temp.match_set('clinica')
    and pg_temp.sorted(pg_temp.page_ids('ŒUVRE' collate "en_US.utf8", null, null, 50)) = array[pg_temp.c(26)],
    'Search independent of the input collation'
);
reset role;

-- ===========================================================================
-- H. Changes between pages (BR-8).
-- ===========================================================================

-- First page of "animalia", two rows: Getafe 02, Getafe 03.
create temporary table first_page (envelope jsonb) on commit drop;
grant insert on first_page to anon;
set local role anon;
insert into first_page select pg_temp.page('animalia', null, null, 2);
reset role;

select pg_temp.assert_true(
    pg_temp.json_ids((select envelope -> 'clinics' from first_page)) = array[pg_temp.c(2), pg_temp.c(3)],
    'Between pages: the first page'
);

set local session_replication_role = replica;
-- Unpublished after the cursor; published before the cursor; a new Clinic
-- after the cursor; a rename moving 02 across the cursor; a Location removed
-- and one added after the cursor; a description changed.
update public.clinics set is_published = false where id = pg_temp.c(4);
update public.clinics set is_published = true where id = pg_temp.c(5);
insert into public.clinics (id, organization_id, is_published) values (pg_temp.c(60), pg_temp.fx('301'), true);
insert into public.clinic_public_profiles (clinic_id, display_name) values (pg_temp.c(60), 'Animalia Zaragoza');
update public.clinic_public_profiles set display_name = 'Animalia Zz' where clinic_id = pg_temp.c(2);
update public.clinic_public_profiles set display_name = 'Animalia Toledo', description = 'Ahora en Toledo'
where clinic_id = pg_temp.c(1);
delete from public.clinic_locations where clinic_id = pg_temp.c(1);
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)
values (pg_temp.c(60), 'Paseo Independencia 60, Zaragoza', 41.65, -0.88);
set local session_replication_role = origin;

create temporary table later_pages (ordinality bigint, row_entry jsonb) on commit drop;
grant insert on later_pages to anon;
grant select on first_page to anon;
set local role anon;
insert into later_pages
select ordinality, row_entry
from jsonb_array_elements(pg_temp.read_pages('animalia', 2,
    (select envelope ->> 'next_after_display_name' from first_page),
    (select (envelope ->> 'next_after_clinic_id')::uuid from first_page))) with ordinality as listed (row_entry, ordinality);
reset role;

select pg_temp.assert_true(
    (select array_agg((row_entry ->> 'clinic_id')::uuid order by ordinality) from later_pages)
        = array[pg_temp.c(1), pg_temp.c(60), pg_temp.c(2)]
    and (select row_entry -> 'address_text' from later_pages where row_entry ->> 'clinic_id' = pg_temp.c(1)::text) = 'null'::jsonb
    and (select row_entry ->> 'description' from later_pages where row_entry ->> 'clinic_id' = pg_temp.c(1)::text) = 'Ahora en Toledo'
    and (select row_entry ->> 'address_text' from later_pages where row_entry ->> 'clinic_id' = pg_temp.c(60)::text)
        = 'Paseo Independencia 60, Zaragoza',
    'Between pages: unpublished and earlier Clinics absent, new and renamed ones once, current addresses'
);

create temporary table fresh_read (pages jsonb) on commit drop;
grant insert on fresh_read to anon;
set local role anon;
insert into fresh_read select pg_temp.read_pages('animalia', 50);
reset role;
select pg_temp.assert_true(
    pg_temp.json_ids((select pages from fresh_read))
        = array[pg_temp.c(5), pg_temp.c(3), pg_temp.c(1), pg_temp.c(60), pg_temp.c(2)]
    and (select pages from fresh_read) = pg_temp.oracle('animalia'),
    'Between pages: a new first read reflects the current state'
);

-- ===========================================================================
-- I. No writes (VN 11).
-- ===========================================================================

do $$
declare
    writes_before bigint;
    writes_after bigint;
    who record;
begin
    select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) into writes_before from pg_stat_xact_user_tables;
    for who in select * from caller order by label loop
        perform set_config('request.jwt.claim.sub', coalesce(who.subject::text, ''), true);
        execute format('set local role %I', who.role_name);
        perform public.discover_published_clinics('clinica', null, null, 50);
        perform public.discover_published_clinics(null, 'Animalia', pg_temp.c(1), 50);
        reset role;
    end loop;
    select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) into writes_after from pg_stat_xact_user_tables;
    perform pg_temp.assert_true(writes_after = writes_before, 'No writes: the read writes no row');
end;
$$;

-- ===========================================================================
-- V. Volume: 6 000 Clinics, 5 000 published (200 of them unnamed), 70 % with
--    a Location. No index is added.
-- ===========================================================================

set local session_replication_role = replica;
insert into public.veterinary_organizations (id, display_name) values (pg_temp.fx('309'), 'Volume Org');
insert into public.clinics (id, organization_id, is_published)
select pg_temp.fx('7' || lpad(n::text, 5, '0')), pg_temp.fx('309'), n % 6 <> 0
from generate_series(1, 6000) as n;
insert into public.clinic_public_profiles (clinic_id, display_name, description)
select pg_temp.fx('7' || lpad(n::text, 5, '0')),
       case when n % 20 <> 0
            then 'Clínica ' || (array['Norte', 'Sur', 'Peña', 'Centro', 'Ávila'])[n % 5 + 1] || ' ' || lpad(n::text, 4, '0')
       end,
       'Descripción ' || n
from generate_series(1, 6000) as n;
insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)
select pg_temp.fx('7' || lpad(n::text, 5, '0')), 'Calle ' || n, 40 + n / 10000.0, -3 - n / 10000.0
from generate_series(1, 6000) as n
where n % 10 < 7;
set local session_replication_role = origin;
analyze public.clinics, public.clinic_public_profiles, public.clinic_locations;

-- V1. Correctness at volume: full traversals equal the oracle.
create temporary table volume_complete (search text, page_size integer, pages jsonb) on commit drop;
grant insert on volume_complete to anon;
do $$
declare
    search text;
begin
    foreach search in array array[null, 'PEÑA', 'centro 22', 'zz no match'] loop
        set local role anon;
        insert into volume_complete values (search, 50, pg_temp.read_pages(search, 50));
        reset role;
    end loop;
end;
$$;
select pg_temp.assert_true(
    not exists (select 1 from volume_complete where pages is distinct from pg_temp.oracle(search))
    and (select jsonb_array_length(pages) from volume_complete where search is null)
        = (select count(*) from public.published_clinic_public_profiles)
    and (select count(*) from jsonb_array_elements((select pages from volume_complete where search is null)) as row_entry
         where row_entry ->> 'clinic_id' like 'd1040000-0000-4000-8000-0000007%') = 5000
    and (select count(*) from jsonb_array_elements((select pages from volume_complete where search is null)) as row_entry
         where row_entry ->> 'clinic_id' like 'd1040000-0000-4000-8000-0000007%'
           and row_entry -> 'display_name' = 'null'::jsonb) = 200
    and (select count(*) from jsonb_array_elements((select pages from volume_complete where search = 'PEÑA')) as row_entry
         where row_entry ->> 'clinic_id' like 'd1040000-0000-4000-8000-0000007%') = 1000
    and (select jsonb_array_length(pages) from volume_complete where search = 'zz no match') = 0,
    'Volume: every page of every search equals the published Clinics of basic Discovery'
);

-- V2. Timings of single pages, as anon (best of three).
create temporary table volume_timing (scenario text primary key, milliseconds numeric not null, rows_returned integer not null) on commit drop;
grant insert on volume_timing to anon;

create temporary table volume_cursor on commit drop as
select row_entry ->> 'display_name' as after_name, (row_entry ->> 'clinic_id')::uuid as after_id, ordinality
from jsonb_array_elements((select pages from volume_complete where search is null)) with ordinality as listed (row_entry, ordinality);
grant select on volume_cursor to anon;

do $$
declare
    probe record;
    started timestamptz;
    returned integer;
    repetition integer;
    best numeric;
    unnamed_start integer := (select min(ordinality) from volume_cursor where after_name is null);
begin
    for probe in
        select * from (values
            ('first page', null::text, 0, 20),
            ('deep page', null, 4900, 20),
            ('unnamed tail', null, unnamed_start, 20),
            ('largest page', null, 0, 50),
            ('common search', 'peña', 0, 20),
            ('rare search', 'clinica centro 4993', 0, 20),
            ('no-match search', 'zz no match', 0, 20)
        ) as cases (scenario, search, after_position, page_size)
    loop
        best := null;
        for repetition in 1..3 loop
            set local role anon;
            started := clock_timestamp();
            select jsonb_array_length(public.discover_published_clinics(
                       probe.search,
                       (select after_name from volume_cursor where ordinality = probe.after_position),
                       (select after_id from volume_cursor where ordinality = probe.after_position),
                       probe.page_size) -> 'clinics')
            into returned;
            best := least(coalesce(best, 1e9), extract(epoch from clock_timestamp() - started) * 1000);
            reset role;
        end loop;
        insert into volume_timing values (probe.scenario, round(best, 1), returned);
        raise notice 'volume % : % ms, % rows', probe.scenario, round(best, 1), returned;
    end loop;
end;
$$;

select pg_temp.assert_true(
    (select rows_returned from volume_timing where scenario = 'first page') = 20
    and (select rows_returned from volume_timing where scenario = 'deep page') = 20
    and (select rows_returned from volume_timing where scenario = 'unnamed tail') = 20
    and (select rows_returned from volume_timing where scenario = 'largest page') = 50
    and (select rows_returned from volume_timing where scenario = 'common search') = 20
    and (select rows_returned from volume_timing where scenario = 'rare search') = 1
    and (select rows_returned from volume_timing where scenario = 'no-match search') = 0,
    'Volume: page contents'
);

select pg_temp.assert_true(
    not exists (select 1 from volume_timing where milliseconds > 250),
    'Volume: every single page is read within the time budget'
);

rollback;

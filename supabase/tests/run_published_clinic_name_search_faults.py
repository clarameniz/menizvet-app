"""Reproducible LOCAL-only SPEC-DIS-004 (Search Published Clinics by Name) mutation regression.
Run from repository root after a clean local reset (all suites are run by
run_all_sql_suites.py). Named assertion failures are required; infrastructure
errors never count as caught mutants. Session rollback/restoration is verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

MIGRATION = 'supabase/migrations/20261120090000_published_clinic_name_search.sql'
SUITE = 'supabase/tests/published_clinic_name_search_spec_dis_004.sql'


def definition(migration, name):
    """One function of the migration, as a `create or replace` candidate."""
    start = migration.index(f'create function public.{name}(')
    body = migration[start:]
    body = body[:body.index('\n$$;\n') + len('\n$$;\n')]
    return body.replace('create function', 'create or replace function', 1)


READ = 'discover_published_clinics'
KEY = 'clinic_display_name_search_key'

PARITY = 'Parity: pages equal the published Clinics of basic Discovery for every caller, search and page size'
VALIDATION = 'Validation: 22023 for every invalid input'
ACCEPTS = 'Validation accepts a 100-character search, limits 1 and 50, an id-only cursor, and defaults to 20'
INDEPENDENCE = 'Independence: no identity, professional helper, per-Clinic read, lock or write'
PAGES = 'Pages: no page exceeds its limit or repeats a Clinic, and its cursor is its last row'

# (function, name, before, after, first failing assertion)
FAULTS = [
    # Validation (VN 9).
    (READ, 'accept a limit of 51',
     "or p_limit not between 1 and 50", "or p_limit not between 1 and 51",
     VALIDATION),
    (READ, 'accept any positive limit (no rejection above 50)',
     "or p_limit not between 1 and 50", "or p_limit < 1",
     VALIDATION),
    (READ, 'reject a limit of 50',
     "or p_limit not between 1 and 50", "or p_limit not between 1 and 49",
     ACCEPTS),
    (READ, 'accept a name cursor without an id',
     "or (p_after_display_name is not null and p_after_clinic_id is null)", "or false",
     VALIDATION),
    (READ, 'accept a 101-character search',
     "or char_length(p_search) > 100 then", "or char_length(p_search) > 101 then",
     VALIDATION),
    (READ, 'reject a 100-character search',
     "or char_length(p_search) > 100 then", "or char_length(p_search) > 99 then",
     ACCEPTS),
    # Eligibility, callers and address (VN 1–4).
    (READ, 'unpublished Clinics included',
     "        where clinic.is_published = true\n",
     "        where (clinic.is_published = true or clinic.is_published = false)\n",
     PARITY),
    (READ, 'Clinics without a Location excluded',
     "        left join public.clinic_locations as location",
     "        join public.clinic_locations as location",
     PARITY),
    (READ, 'Clinics without a public profile included',
     "        join public.clinic_public_profiles as profile",
     "        left join public.clinic_public_profiles as profile",
     PARITY),
    (READ, 'results depend on the caller',
     "        where clinic.is_published = true\n",
     "        where clinic.is_published = true\n"
     "          and pg_catalog.current_setting('request.jwt.claim.sub', true) is distinct from ''\n",
     PARITY),
    (READ, 'identity consulted',
     "        where clinic.is_published = true\n",
     "        where clinic.is_published = true and (auth.uid() is null or auth.uid() is not null)\n",
     INDEPENDENCE),
    (READ, 'address read per Clinic',
     "            location.address_text\n        from public.clinics as clinic",
     "            (select published.address_text from public.get_published_clinic_location(clinic.id) as published)"
     " as address_text\n        from public.clinics as clinic",
     INDEPENDENCE),
    # Search (VN 5).
    (READ, 'ignore the search',
     "              search_key is null\n              or (", "              true\n              or (",
     PARITY),
    (READ, 'unnamed Clinics match a search',
     "                  profile.display_name is not null\n                  and pg_catalog.strpos(",
     "                  profile.display_name is null\n                  or pg_catalog.strpos(",
     PARITY),
    (READ, 'search the description too',
     "                      search_key\n                  ) > 0\n",
     "                      search_key\n                  ) > 0\n"
     "                  or pg_catalog.strpos(public.clinic_display_name_search_key(profile.description), search_key) > 0\n",
     PARITY),
    (READ, 'pattern matching with LIKE',
     "pg_catalog.strpos(\n"
     "                      public.clinic_display_name_search_key(profile.display_name),\n"
     "                      search_key\n"
     "                  ) > 0",
     "public.clinic_display_name_search_key(profile.display_name) like '%' || search_key || '%'",
     'Search percent'),
    # Order, cursor and pages (VN 6, 7).
    (READ, 'drop the id tie-breaker',
     "                          profile.display_name = p_after_display_name\n"
     "                          and clinic.id > p_after_clinic_id\n",
     "                          false\n",
     'Pages: has_more announces a further row'),
    (READ, 'unnamed rows not after a named cursor',
     "                      profile.display_name is null\n"
     "                      or profile.display_name > p_after_display_name\n",
     "                      profile.display_name > p_after_display_name\n",
     'Pages: has_more announces a further row'),
    (READ, 'unnamed cursor ignores the id',
     "                      profile.display_name is null\n"
     "                      and clinic.id > p_after_clinic_id\n",
     "                      profile.display_name is null\n",
     'Pages: the list ends'),
    (READ, 'unnamed Clinics first',
     "            profile.display_name nulls last,\n            clinic.id",
     "            profile.display_name nulls first,\n            clinic.id",
     PARITY),
    (READ, 'order by the normalized name',
     "            profile.display_name nulls last,\n            clinic.id",
     "            public.clinic_display_name_search_key(profile.display_name) nulls last,\n            clinic.id",
     PARITY),
    (READ, 'no probe row',
     "        limit p_limit + 1", "        limit p_limit",
     PARITY),
    (READ, 'probe row returned',
     "        page_rows := page_rows - p_limit;\n", "        null;\n",
     PAGES),
    (READ, 'has_more for a page that ends the list',
     "jsonb_array_length(page_rows) > p_limit;", "jsonb_array_length(page_rows) >= p_limit;",
     'Pages: has_more announces a further row'),
    (READ, 'cursor taken from the first row',
     "'next_after_clinic_id', last_row -> 'clinic_id'",
     "'next_after_clinic_id', page_rows -> 0 -> 'clinic_id'",
     PAGES),
    # Normalization (VN 5).
    (KEY, 'canonical instead of compatibility decomposition',
     "'NFKD'", "'NFD'",
     'Normalization ligature'),
    (KEY, 'keep the combining marks',
     "'[\\u0300-\\u036f]', '', 'g'", "'[\\u2400-\\u2400]', '', 'g'",
     'Normalization acute upper'),
    (KEY, 'lowercase in the input collation',
     ' collate pg_catalog."und-x-icu"', '',
     'Normalization o-stroke upper'),
    (KEY, 'ASCII space only',
     "'[\\t\\n\\v\\f\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]+'",
     "'[ ]+'",
     'Normalization line separator'),
    (KEY, 'trim only the end',
     "pg_catalog.btrim(", "pg_catalog.rtrim(",
     'Normalization runs and ends'),
]

READ_SIGNATURE = 'public.discover_published_clinics(text, text, uuid, integer)'
KEY_SIGNATURE = 'public.clinic_display_name_search_key(text)'
GRANTS = 'Grants: the read as every Discovery read (anon, authenticated); the search helper executable by no client'


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(ROOT / SUITE)
        migration = (ROOT / MIGRATION).read_text(encoding='utf-8')
        candidates = [
            Fault(f'{function}: {name}', replace_once(definition(migration, function), before, after), assertion)
            for function, name, before, after, assertion in FAULTS
        ]
        candidates += [
            Fault('revoke the read from anon', f'revoke execute on function {READ_SIGNATURE} from anon;', GRANTS),
            Fault('grant the read to PUBLIC', f'grant execute on function {READ_SIGNATURE} to public;', GRANTS),
            Fault('grant the search helper to anon', f'grant execute on function {KEY_SIGNATURE} to anon;', GRANTS),
            Fault('grant the search helper to service_role',
                  f'grant execute on function {KEY_SIGNATURE} to service_role;', GRANTS),
            Fault('grant table read to anon', 'grant select on public.clinic_locations to anon;',
                  'Tables: no client privilege added; the basic Discovery view unchanged'),
        ]
        client.faults(source, candidates)
        client.suite(ROOT / SUITE)
        client.verify_zero_fixtures(['d1040000-'])


if __name__ == '__main__':
    main()

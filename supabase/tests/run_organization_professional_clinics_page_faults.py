"""Reproducible LOCAL-only SPEC-ORG-008 §11 (Organization Professional Clinics page) mutation regression.
Run from repository root after a clean local reset (all suites are run by
run_all_sql_suites.py). Named assertion failures are required; infrastructure
errors never count as caught mutants. Session rollback/restoration is verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

MIGRATION = 'supabase/migrations/20261119090000_organization_professional_clinics_page.sql'
SUITE = 'supabase/tests/organization_professional_clinics_page_spec_org_008.sql'


def definition(migration, name):
    """One function of the migration, as a `create or replace` candidate."""
    start = migration.index(f'create function public.{name}(')
    body = migration[start:]
    body = body[:body.index('\n$$;\n') + len('\n$$;\n')]
    return body.replace('create function', 'create or replace function', 1)


READ = 'get_my_organization_professional_clinics'
KEY = 'professional_clinic_search_key'

PARITY = 'Parity: pages equal the ORG-008 result of the Organization for every User and page size'
CURSOR = 'Cursor: any cursor returns only included rows matching the search of the call'
# Section C reads the Search Org as its Owner (36 Clinics) with a 100-character search.
ACCEPTS = 'Validation accepts a 100-character search, limits 1 and 50, and defaults to 20'

# (function, name, before, after, first failing assertion)
FAULTS = [
    # Authentication and validation (VN 24, 25).
    (READ, 'skip the authentication check',
     "    if auth.uid() is null then", "    if false then",
     'Authentication: 28000 before validation'),
    (READ, 'accept a limit of 51',
     "or p_limit not between 1 and 50", "or p_limit not between 1 and 51",
     'Validation: 22023 for every invalid input and every Organization'),
    (READ, 'accept a name cursor without an id',
     "or (p_after_display_name is not null and p_after_clinic_id is null)", "or false",
     'Validation: 22023 for every invalid input and every Organization'),
    (READ, 'accept a 101-character search',
     "or char_length(p_search) > 100 then", "or char_length(p_search) > 101 then",
     'Validation: 22023 for every invalid input and every Organization'),
    (READ, 'reject a 100-character search',
     "or char_length(p_search) > 100 then", "or char_length(p_search) > 99 then",
     ACCEPTS),
    (READ, 'raise for an Organization without Membership',
     "    ) then\n        return;\n    end if;",
     "    ) then\n        raise exception 'Organization unavailable' using errcode = '42501';\n    end if;",
     'Pages: the read never fails for valid input'),
    # Inclusion (VN 26–29).
    (READ, 'drop the Organization filter',
     "        where clinic.organization_id = p_organization_id\n", "        where true\n",
     PARITY),
    (READ, 'include every candidate (Membership instead of the predicate)',
     "acting_user_id, candidate.candidate_clinic_id, clinic_capability.capability\n            )\n",
     "acting_user_id, candidate.candidate_clinic_id, clinic_capability.capability\n            ) or true\n",
     PARITY),
    (READ, 'role shortcut: Organization-scoped predicate only',
     "            where public.user_has_clinic_capability(\n"
     "                acting_user_id, candidate.candidate_clinic_id, clinic_capability.capability\n",
     "            where public.user_has_organization_scoped_clinic_capability(\n"
     "                acting_user_id, p_organization_id, clinic_capability.capability\n",
     'Delegation: inclusion only through user_has_clinic_capability, no mapping, no lock, no write'),
    (READ, 'candidate bound drops Clinic-scoped Grants',
     "and grant_record.scope_type = 'CLINIC'", "and false",
     PARITY),
    (READ, 'candidate bound drops Veterinarian Clinic Assignments',
     "and assignment.effective_end is null", "and false",
     PARITY),
    (READ, 'candidate bound never Organization-wide',
     "    organization_wide := exists (", "    organization_wide := false and exists (",
     ACCEPTS),
    (READ, 'candidate bound requires an Organization-scoped Grant for Clinic-bound actors',
     "                    and grant_record.scope_type = 'CLINIC'\n",
     "                    and grant_record.scope_type = 'ORGANIZATION'\n",
     PARITY),
    # Search (VN 22, 31, 32).
    (READ, 'ignore the search',
     "              search_key is null\n              or (", "              true\n              or (",
     ACCEPTS),
    (READ, 'unnamed Clinics match a search',
     "                  profile.display_name is not null\n                  and pg_catalog.strpos(",
     "                  profile.display_name is null\n                  or pg_catalog.strpos(",
     ACCEPTS),
    (READ, 'pattern matching with LIKE',
     "pg_catalog.strpos(\n"
     "                      public.professional_clinic_search_key(profile.display_name),\n"
     "                      search_key\n"
     "                  ) > 0",
     "public.professional_clinic_search_key(profile.display_name) like '%' || search_key || '%'",
     'Search parity: pages equal the narrowed ORG-008 result for every search and page size'),
    # Order and cursor (VN 30).
    (READ, 'drop the id tie-breaker',
     "                          profile.display_name = p_after_display_name\n"
     "                          and clinic.id > p_after_clinic_id\n",
     "                          false\n",
     PARITY),
    (READ, 'unnamed rows not after a named cursor',
     "                      profile.display_name is null\n"
     "                      or profile.display_name > p_after_display_name\n",
     "                      profile.display_name > p_after_display_name\n",
     PARITY),
    (READ, 'unnamed cursor ignores the id',
     "                      profile.display_name is null\n"
     "                      and clinic.id > p_after_clinic_id\n",
     "                      profile.display_name is null\n",
     'Pages: the list ends'),
    (READ, 'unnamed Clinics first',
     "            profile.display_name nulls last,", "            profile.display_name nulls first,",
     PARITY),
    (READ, 'order by the normalized name',
     "            profile.display_name nulls last,",
     "            public.professional_clinic_search_key(profile.display_name) nulls last,",
     PARITY),
    (READ, 'page longer than its limit',
     "exit when returned_count = p_limit;", "exit when returned_count = p_limit + 1;",
     ACCEPTS),
    # Normalization (VN 32, 33).
    (KEY, 'canonical instead of compatibility decomposition',
     "'NFKD'", "'NFD'",
     'Normalization ligature'),
    (KEY, 'keep the combining marks',
     "'[\\u0300-\\u036f]', '', 'g'", "'[\\u2400-\\u2400]', '', 'g'",
     CURSOR),
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

READ_SIGNATURE = 'public.get_my_organization_professional_clinics(uuid, text, text, uuid, integer)'
GRANTS = 'Grants: authenticated only; the search helper is executable by no client'


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
            Fault('grant the read to anon', f'grant execute on function {READ_SIGNATURE} to anon;', GRANTS),
            Fault('grant the read to service_role', f'grant execute on function {READ_SIGNATURE} to service_role;', GRANTS),
            Fault('grant the search helper to authenticated',
                  'grant execute on function public.professional_clinic_search_key(text) to authenticated;', GRANTS),
        ]
        client.faults(source, candidates)
        client.suite(ROOT / SUITE)
        client.verify_zero_fixtures(['d0150000-'])


if __name__ == '__main__':
    main()

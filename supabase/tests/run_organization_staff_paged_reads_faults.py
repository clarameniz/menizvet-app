"""Reproducible LOCAL-only SPEC-ORG-009 §12 (paged Staff reads) mutation regression.
Run from repository root after a clean local reset (all suites are run by
run_all_sql_suites.py). Named assertion failures are required; infrastructure
errors never count as caught mutants. Session rollback/restoration is verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

MIGRATION = 'supabase/migrations/20261111090000_organization_staff_paged_reads.sql'
SUITE = 'supabase/tests/organization_staff_paged_reads_spec_org_009.sql'


def definition(migration, name):
    """One function of the migration, as a `create or replace` candidate."""
    start = migration.index(f'create function public.{name}(')
    body = migration[start:]
    body = body[:body.index('\n$$;\n') + len('\n$$;\n')]
    return body.replace('create function', 'create or replace function', 1)


# (function, name, before, after, first failing assertion)
FAULTS = [
    ('organization_staff_reader', 'remove the capability gate',
     "       or not (\n           public.user_has_organization_capability(", "       or false and (\n           public.user_has_organization_capability(",
     'Members denied 3'),
    ('get_organization_staff_members', 'accept a partial cursor',
     "or num_nulls(p_after_effective_start, p_after_membership_id) not in (0, 2)", "or false",
     'Members validation'),
    ('get_organization_staff_members', 'include ended Memberships',
     "        where membership.organization_id = p_organization_id\n          and membership.effective_end is null\n          and membership.effective_start <= evaluation.instant\n          and membership.effective_start >= coalesce",
     "        where membership.organization_id = p_organization_id\n          and true\n          and membership.effective_start <= evaluation.instant\n          and membership.effective_start >= coalesce",
     'Members equal the full read at page size 1'),
    ('get_organization_staff_members', 'drop the id tie-breaker',
     "or membership.id > p_after_membership_id", "or false",
     'Members equal the full read at page size 1'),
    ('get_organization_staff_members', 'count ended members as namesakes',
     "        join public.user_profiles as profile\n          on profile.user_id = membership.user_id\n        where membership.organization_id = p_organization_id\n          and membership.effective_end is null",
     "        join public.user_profiles as profile\n          on profile.user_id = membership.user_id\n        where membership.organization_id = p_organization_id\n          and true",
     'Members equal the full read at page size 1'),
    ('get_organization_staff_members', 'decide namesakes on the page only',
     "        where membership.organization_id = p_organization_id\n          and membership.effective_end is null\n          and membership.effective_start <= evaluation.instant\n          and profile.display_name in (",
     "        where membership.id in (select page_row.page_membership_id from page as page_row)\n          and profile.display_name in (",
     'Members equal the full read at page size 1'),
    ('get_organization_pending_invitations', 'include revoked Invitations',
     "and invitation.revoked_at is null", "and true",
     'Invitations equal the full read at page size 1'),
    ('get_organization_pending_invitations', 'leak another Organization',
     "where invitation.organization_id = p_organization_id", "where true",
     'Invitations equal the full read at page size 1'),
    ('get_organization_pending_invitations', 'drop the id tie-breaker',
     "or invitation.id > p_after_invitation_id", "or false",
     'Invitations equal the full read at page size 1'),
]


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(ROOT / SUITE)
        migration = (ROOT / MIGRATION).read_text(encoding='utf-8')
        candidates = [
            Fault(name, replace_once(definition(migration, function), before, after), assertion)
            for function, name, before, after, assertion in FAULTS
        ]
        candidates.append(Fault(
            'grant the Members read to anon',
            'grant execute on function public.get_organization_staff_members(uuid, timestamptz, uuid, integer) to anon;',
            'Grants: authenticated only; the helper is executable by no client',
        ))
        candidates.append(Fault(
            'grant the helper to authenticated',
            'grant execute on function public.organization_staff_reader(uuid) to authenticated;',
            'Grants: authenticated only; the helper is executable by no client',
        ))
        client.faults(source, candidates)
        client.suite(ROOT / SUITE)
        client.verify_zero_fixtures(['d0120000-'])


if __name__ == '__main__':
    main()

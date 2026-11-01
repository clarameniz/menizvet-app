"""Reproducible LOCAL-only SPEC-ORG-009 mutation regression.
Run from repository root after a clean local reset (all suites are run by
run_all_sql_suites.py). Named assertion failures are required; infrastructure
errors never count as caught mutants. Session rollback/restoration is verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

FAULTS = [
    ("remove authorization", "public.user_has_organization_capability(\n                  acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'\n              )", "true"),
    ("allow Clinic Administrator", "and (\n              public.user_has_organization_capability", "and (exists (select 1 from public.organization_memberships m join public.organization_responsibility_grants g on g.membership_id=m.id where m.user_id=acting_user_id and m.organization_id=p_organization_id and g.responsibility='ADMINISTRATOR') or\n              public.user_has_organization_capability"),
    ("leak another Organization Member", "where membership.organization_id = organization.id", "where true"),
    ("include ended Membership", "and membership.effective_end is null", "and true"),
    ("include future Membership", "and membership.effective_start <= evaluation.instant", "and true"),
    ("include ended Grant", "and grant_record.effective_end is null", "and true"),
    ("include future Grant", "and grant_record.effective_start <= evaluation.instant", "and true"),
    ("expose Auth email", "'display_name', profile.display_name", "'display_name', (select au.email from auth.users au join public.user_authentication_identities ai on ai.provider_subject=au.id where ai.user_id=membership.user_id)"),
    ("expose User id", "'membership_id', membership.id", "'user_id', membership.user_id, 'membership_id', membership.id"),
    ("include accepted Invitation", "and not exists (\n                  select 1 from public.organization_memberships as accepted\n                  where accepted.originating_invitation_id = invitation.id\n              )", "and true"),
    ("include expired Invitation", "and invitation.expires_at > evaluation.instant", "and true"),
    ("treat Invitation expiring at the read instant as pending", "and invitation.expires_at > evaluation.instant", "and invitation.expires_at >= evaluation.instant"),
    ("include revoked Invitation", "and invitation.revoked_at is null", "and true"),
    ("include rejected Invitation", "and invitation.rejected_at is null", "and true"),
    ("expose invitation digest", "'invitation_id', invitation.id", "'acceptance_secret_digest', invitation.acceptance_secret_digest, 'invitation_id', invitation.id"),
    ("omit Member Clinic scope/name", "'clinic_display_name', clinic_profile.display_name)", "'clinic_display_name', null)"),
    ("omit Invitation Clinic scope/name", "'clinic_display_name', clinic_profile.display_name)", "'clinic_display_name', null)"),
    ("Grant id names the Membership", "'responsibility_grant_id', grant_record.id,", "'responsibility_grant_id', membership.id,"),
    ("Grant id omitted", "                        'responsibility_grant_id', grant_record.id,\n", ""),
    ("Grant id leaks into pending Invitations", "'responsibility', intended.responsibility,", "'responsibility_grant_id', intended.id, 'responsibility', intended.responsibility,"),
]

EXPECTED_ASSERTIONS = ['Denied actor 3', 'Denied actor 4', 'Exactly current A Memberships in canonical order, ended/future/B absent', 'Exactly current A Memberships in canonical order, ended/future/B absent', 'Exactly current A Memberships in canonical order, ended/future/B absent', 'Grant id identifies exactly that current Grant of that Membership', 'Grant id identifies exactly that current Grant of that Membership', 'Stored display name and provisioned identity', 'Exact Member fields: no User id/Auth data', 'Only pending A Invitations ordered: accepted/revoked/rejected/expired absent', 'Only pending A Invitations ordered: accepted/revoked/rejected/expired absent', 'Invitation expiring exactly at the read instant is not pending', 'Only pending A Invitations ordered: accepted/revoked/rejected/expired absent', 'Only pending A Invitations ordered: accepted/revoked/rejected/expired absent', 'Exact Invitation fields, no secret/digest/envelope/Communication', 'Multiple current Grants ordered, ended/future absent', 'Every legacy intended responsibility with Clinic', 'Grant id identifies exactly that current Grant of that Membership', 'Exact Grant fields', 'Invitation intended responsibilities carry no Grant identifier']

def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(ROOT / 'supabase/tests/organization_staff_spec_org_009.sql')
        # The current definition: Grant identifiers (SPEC-ORG-009 BR-1) were
        # added by the workforce migration.
        migration = (ROOT / 'supabase/migrations/20261102090000_staff_responsibility_and_veterinarian_workforce.sql').read_text(encoding='utf-8')
        base = migration[migration.index('create or replace function public.get_organization_staff'):]
        base = base[:base.index('\n$$;\n') + len('\n$$;\n')]
        candidates = []
        for (name, before, after), assertion in zip(FAULTS, EXPECTED_ASSERTIONS, strict=True):
            if name.startswith('omit Member'):
                candidate = base.replace(before, after, 1)
            elif name.startswith('omit Invitation'):
                pos = base.rindex(before)
                candidate = base[:pos] + base[pos:].replace(before, after, 1)
            else:
                candidate = replace_once(base, before, after)
            candidates.append(Fault(name,candidate,assertion))
        # Neither side effect is visible in the payload: the mutation touches
        # other Organizations and the lock changes no row content, so only the
        # dedicated fingerprint and lock-evidence assertions can catch them.
        for name, operation, assertion in [
            ('mutate during read', "update public.veterinary_organizations set display_name=display_name || ' MUTATED' where id<>p_organization_id;", 'Read changes no public rows, including Communications'),
            ('lock during read', 'perform 1 from public.veterinary_organizations where id=p_organization_id for update;', 'Read acquires no business tuple locks'),
        ]:
            candidate = replace_once(base,'language plpgsql stable','language plpgsql volatile')
            candidate = replace_once(candidate,'    return staff_result;',f'    {operation}\n    return staff_result;')
            candidates.append(Fault(name,candidate,assertion))
        client.faults(source,candidates)
        client.suite(ROOT / 'supabase/tests/organization_staff_spec_org_009.sql')
        client.verify_zero_fixtures(['d0090000-','d0260000-'])
    client.verify_interruption()


if __name__ == '__main__':
    main()

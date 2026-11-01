"""Reproducible LOCAL-only Staff Slice B1 mutation regression (SPEC-ORG-002 §10,
SPEC-ORG-010, SPEC-COM-001 BR-45/BR-46).

Run from repository root after a clean local reset. Each behavioural mutant
replaces one trusted function inside the rollback-only suite transaction and
must be caught by its named assertion; infrastructure errors never count.
Session rollback/restoration and zero retained fixtures are verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/staff_invitation_invite_revoke_spec_org_002_010.sql'
MIGRATION = ROOT / 'supabase/migrations/20261027090000_staff_invitation_invite_and_revoke.sql'
REVOKE_CAPABILITY = re.compile(
    r"public\.user_has_organization_capability\(\s*acting_user_id, target_organization_id, "
    r"'ORGANIZATION_REVOKE_INVITATIONS'\s*\)")
FIRST_ACTIVE_ORGANIZATION = ("(select m.organization_id from public.organization_memberships m "
                             "where m.user_id = acting_user_id and m.effective_end is null "
                             "order by m.effective_start, m.id limit 1)")

AUTHORITY = 'assert_organization_invitation_authority'
CREATE = 'create_staff_organization_invitation_with_communication'
REVOKE = 'revoke_organization_invitation'
HANDOFF = 'mark_communication_delivery_submission_started'
ELIGIBILITY = 'communication_delivery_is_currently_eligible'

# (name, function, before, after, expected assertion)
FAULTS = [
    # Invite
    ('remove invite capability', AUTHORITY,
     "or not public.user_has_organization_capability(\n        acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'\n    ) then",
     'or false then', 'Denied inviter 3'),
    ('skip inviter account verification', AUTHORITY,
     "    if not exists (\n        select 1\n        from auth.users as auth_user",
     "    if false and not exists (\n        select 1\n        from auth.users as auth_user",
     'Unverified inviter rejected before the Organization is considered'),
    ('validate input before authorization', CREATE,
     '    -- 1–3: authentication, verification, Organization + capability.',
     "    if p_responsibility = 'OWNER' then\n        raise exception 'Organization Invitation role or scope is invalid'\n"
     "            using errcode = '22023', hint = 'INVALID_ROLE_SCOPE';\n    end if;",
     'Denied inviter fails before any input validation 3'),
    ('product command offers OWNER', CREATE,
     "p_responsibility not in ('ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN')",
     "p_responsibility not in ('OWNER', 'ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN')",
     'OWNER rejected as invalid role/scope'),
    ('product command offers Clinic-scoped VETERINARIAN', CREATE,
     "or p_responsibility not in ('ADMINISTRATOR', 'RECEPTIONIST')\n",
     "or p_responsibility not in ('ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN')\n",
     'Clinic-scoped VETERINARIAN rejected'),
    ('Clinic scope skips Organization ownership', CREATE,
     '          and clinic.organization_id = p_organization_id\n        for update;',
     '        for update;',
     'Clinic of another Organization and nonexistent Clinic rejected identically'),
    ('expiry not exactly 7 days', CREATE, "interval '168 hours'", "interval '167 hours'",
     'Stored expiry is exactly 7 days after the trusted creation instant org_admin'),
    ('created_at from a second clock', CREATE,
     '        p_created_at,\n        p_created_at + validity,',
     '        clock_timestamp(),\n        p_created_at + validity,',
     'Stored expiry is exactly 7 days after the trusted creation instant org_admin'),
    ('caller-supplied creation instant unbounded', CREATE,
     "       or p_created_at > operation_instant\n       or p_created_at <= operation_instant - interval '1 minute' then",
     ' then', 'Future creation instant rejected'),
    ('envelope context bound to another expiry', CREATE,
     "'organization', invited_email, p_created_at + validity,",
     "'organization', invited_email, p_created_at + validity + interval '1 second',",
     'Owner invites Organization Administrator: 23514:-:Communication recipient does not match its Organization Invitation'),
    ('Communication not created', CREATE,
     '    -- The integrity trigger rejects an envelope context that does not bind\n',
     '    return created_invitation_id;\n    -- The integrity trigger rejects an envelope context that does not bind\n',
     'Owner invites Organization Administrator: 23514:-:A new Organization Invitation requires its exact Communication at commit'),
    ('product command binds a recipient User', CREATE,
     '        null,\n        invited_email,', '        acting_user_id,\n        invited_email,',
     'Owner invites Organization Administrator: 23514:-:Communication recipient does not match its Organization Invitation'),
    ('duplicate pending allowed', CREATE,
     "        raise exception 'An equivalent pending Organization Invitation already exists'",
     "        perform 1;\n    end if;\n    if false then\n        raise exception 'An equivalent pending Organization Invitation already exists'",
     'Exact duplicate pending Invitation conflicts'),
    ('normalized email duplicate bypassed', CREATE,
     '          and invitation.recipient_email_normalized = lower(invited_email)',
     '          and invitation.recipient_email = invited_email',
     'Normalized duplicate conflicts regardless of role/scope'),
    ('active Member provenance ignored', CREATE,
     "        raise exception 'The recipient address belongs to an active Member'",
     "        perform 1;\n    end if;\n    if false then\n        raise exception 'The recipient address belongs to an active Member'",
     'Address an active Member joined through is rejected'),
    ('creation without Organization lock', CREATE,
     '    perform 1\n    from public.veterinary_organizations as organization\n    where organization.id = p_organization_id\n    for update;',
     '', 'Creation serializes on the Organization row'),
    # Revoke
    ('revoke authorization removed', REVOKE, None, 'true', 'Denied revoker 3'),
    ('cross-Organization revoke allowed', REVOKE, None, None, 'Denied revoker 10'),
    ('unknown Invitation distinguishable', REVOKE,
     '    if target_organization_id is null\n       or not',
     "    if target_organization_id is null then\n        raise exception 'Organization Invitation does not exist' using errcode = '42501';\n"
     '    end if;\n    if not',
     'Denied revoker 3'),
    ('revoke after accept not reported ACCEPTED', REVOKE,
     "    if exists (\n        select 1\n        from public.organization_memberships as accepted\n"
     "        where accepted.originating_invitation_id = p_invitation_id\n    ) then",
     '    if false then', 'Accepted Invitation reported ACCEPTED and unchanged'),
    ('revoke at the expiry instant writes state', REVOKE,
     'elsif revocation_instant >= invitation_record.expires_at then',
     'elsif revocation_instant > invitation_record.expires_at then',
     'Invitation expiring exactly at the revocation instant is EXPIRED and unchanged'),
    ('revoke after expiry writes state', REVOKE,
     "    elsif revocation_instant >= invitation_record.expires_at then\n        revocation_outcome := 'EXPIRED';\n",
     '', 'Expired Invitation reported EXPIRED and unchanged'),
    ('digest erased on revoke', REVOKE,
     '        set revoked_at = revocation_instant,',
     '        set revoked_at = revocation_instant, acceptance_secret_digest = null,',
     'Revocation retains the acceptance digest'),
    ('repeat revoke not idempotent', REVOKE,
     "revocation_outcome := 'ALREADY_REVOKED';", "revocation_outcome := 'REVOKED';",
     'Retry by any authorized User returns ALREADY_REVOKED'),
    ('retry rewrites revocation facts', REVOKE,
     "    elsif invitation_record.revoked_at is not null then\n        revocation_outcome := 'ALREADY_REVOKED';\n",
     '', 'Retry by any authorized User returns ALREADY_REVOKED'),
    ('revoke result exposes the digest', REVOKE,
     "        'outcome', revocation_outcome\n",
     "        'outcome', revocation_outcome,\n        'acceptance_secret_digest', encode(invitation_record.acceptance_secret_digest, 'hex')\n",
     'Pending Invitation revoked with the exact outcome envelope'),
    ('revoke rewrites Communication history', REVOKE,
     '        revocation_outcome := \'REVOKED\';',
     "        update public.transactional_communications set secret_nonce = null, secret_ciphertext = null,\n"
     "            secret_consumed_at = clock_timestamp() where organization_invitation_id = p_invitation_id\n"
     "            and secret_consumed_at is null;\n        revocation_outcome := 'REVOKED';",
     'Revocation creates no Communication and rewrites none'),
    ('revoke without Organization lock', REVOKE,
     '    perform 1\n    from public.veterinary_organizations as organization\n    where organization.id = target_organization_id\n    for update;',
     '', 'Revocation takes the Organization then the Invitation lock even when it writes nothing'),
    # Communication suppression
    ('undelivered Communication of a revoked Invitation still eligible', ELIGIBILITY,
     '             and invitation.revoked_at is null\n             and invitation.rejected_at is null',
     '             and true\n             and invitation.rejected_at is null',
     'Undelivered email of a revoked Invitation is suppressed, never claimed'),
    ('provider handoff ignores current eligibility', HANDOFF,
     '    if not public.communication_delivery_is_currently_eligible(',
     '    if false and not public.communication_delivery_is_currently_eligible(',
     'Provider handoff is refused once the Invitation is revoked'),
    ('provider handoff not serialized with revocation', HANDOFF,
     '    for share of invitation;', '    ;', 'Provider handoff share-locks its Organization Invitation'),
]


def migration_function(source, name):
    match = re.search(r"^create (or replace )?function public\." + name + r"\(.*?^\$\$;\n", source, re.M | re.S)
    if not match:
        raise HarnessFailure(f'Function {name} not found in migration')
    return re.sub(r'^create (or replace )?function', 'create or replace function', match.group(0), count=1)


def mutate(base, name, before, after):
    if name == 'revoke authorization removed':
        candidate, count = REVOKE_CAPABILITY.subn('true', base)
    elif name == 'cross-Organization revoke allowed':
        candidate, count = REVOKE_CAPABILITY.subn(
            "public.user_has_organization_capability(acting_user_id, " + FIRST_ACTIVE_ORGANIZATION +
            ", 'ORGANIZATION_REVOKE_INVITATIONS')", base)
    else:
        return replace_once(base, before, after)
    if count != 2:
        raise HarnessFailure(f'{name}: expected both revoke capability checks')
    return candidate


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        migration = MIGRATION.read_text(encoding='utf-8')
        bases = {name: migration_function(migration, name) for name in (AUTHORITY, CREATE, REVOKE, HANDOFF)}
        bases[ELIGIBILITY] = client.definition(f'public.{ELIGIBILITY}(uuid, text, uuid, text)')
        candidates = [Fault(name, mutate(bases[function], name, before, after), assertion)
                      for name, function, before, after, assertion in FAULTS]
        client.faults(source, candidates)
        client.suite(SUITE)
        client.verify_zero_fixtures(['d0270000-'])


if __name__ == '__main__':
    main()

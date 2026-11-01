"""Reproducible LOCAL-only Staff Slice B2 mutation regression (SPEC-ORG-003
§10–§13, BR-18–BR-25).

Run from repository root after a clean local reset. Each behavioural mutant
replaces one trusted function inside the rollback-only B2 suite transaction and
must be caught by its named assertion; infrastructure errors never count.
Session rollback/restoration and zero retained fixtures are verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/staff_invitation_preview_accept_spec_org_003.sql'
MIGRATION = ROOT / 'supabase/migrations/20261028090000_staff_invitation_preview_and_accept.sql'

PREVIEW = 'preview_organization_invitation'
ACCEPT = 'accept_my_organization_invitation'
WRITER = 'establish_membership_from_organization_invitation'
SHAPE = 'organization_invitation_responsibilities_are_acceptable'
MASK = 'mask_organization_invitation_recipient'

ACCEPT_PROOF = ("    if invitation_record.acceptance_secret_digest is null\n"
                "       or p_acceptance_secret is null\n"
                "       or sha256(convert_to(p_acceptance_secret, 'UTF8'))\n"
                "           is distinct from invitation_record.acceptance_secret_digest then")
PREVIEW_PROOF = ("       or p_acceptance_secret is null\n"
                 "       or sha256(convert_to(p_acceptance_secret, 'UTF8'))\n"
                 "           is distinct from invitation_record.acceptance_secret_digest then\n"
                 "        -- 3. Proof")
REVOKED_CHECK = ("    if invitation_record.revoked_at is not null then\n"
                 "        raise exception 'Organization Invitation has been revoked'\n"
                 "            using errcode = '23514', hint = 'INVITATION_REVOKED';\n"
                 "    end if;\n")
EXPIRY_CHECK = ("    if effective_instant >= invitation_record.expires_at then\n"
                "        raise exception 'Organization Invitation has expired'\n"
                "            using errcode = '23514', hint = 'INVITATION_EXPIRED';\n"
                "    end if;\n")
MEMBER_CHECK = ("    if exists (\n"
                "        select 1\n"
                "        from public.organization_memberships as membership\n"
                "        where membership.organization_id = invitation_record.organization_id\n"
                "          and membership.user_id = acting_user_id\n"
                "          and membership.effective_end is null\n"
                "    ) then\n"
                "        raise exception 'User already has an active Organization Membership'\n"
                "            using errcode = '23505', hint = 'ALREADY_MEMBER';\n"
                "    end if;\n")
GRANTS = ("    insert into public.organization_responsibility_grants (\n"
          "        membership_id,\n"
          "        responsibility,\n"
          "        scope_type,\n"
          "        clinic_id,\n"
          "        effective_start,\n"
          "        granted_by_user_id,\n"
          "        originating_invitation_responsibility_id\n"
          "    )\n"
          "    select\n"
          "        created_membership_id,\n"
          "        intended.responsibility,\n"
          "        intended.scope_type,\n"
          "        intended.clinic_id,\n"
          "        p_effective_instant,\n"
          "        p_inviting_user_id,\n"
          "        intended.id\n"
          "    from public.organization_invitation_responsibilities as intended\n"
          "    where intended.invitation_id = p_invitation_id;\n")

# (name, function, before, after, expected assertion)
FAULTS = [
    # Proof and its ordering (BR-18, BR-20, BR-22)
    ('acceptance secret check removed', ACCEPT, ACCEPT_PROOF, '    if false then',
     'Wrong secret fails uniformly and writes nothing: '),
    ('preview secret check removed', PREVIEW, PREVIEW_PROOF, '       or false then\n        -- 3. Proof',
     'Wrong or malformed secret previews uniformly: '),
    ('acceptance lifecycle checked before proof', ACCEPT, '    -- 5. Proof (BR-18)',
     REVOKED_CHECK + '    -- 5. Proof (BR-18)',
     'Uniform failure hides the lifecycle before acceptance proof: revoked'),
    ('preview lifecycle checked before proof', PREVIEW,
     '    elsif not found\n       or invitation_record.acceptance_secret_digest is null',
     "    elsif found and invitation_record.expires_at <= statement_timestamp() then\n"
     "        preview_state := 'EXPIRED';\n"
     '    elsif not found\n       or invitation_record.acceptance_secret_digest is null',
     'Uniform failure hides the lifecycle before proof: legacy_50'),
    ('caller-supplied User id trusted', ACCEPT,
     '    acting_user_id := public.current_domain_user_id();',
     "    acting_user_id := coalesce(nullif(current_setting('request.headers', true), '')::jsonb\n"
     "        ->> 'x-menizvet-user-id', public.current_domain_user_id()::text)::uuid;",
     'Accepting User derived from the authenticated subject only'),
    ('confirmed-email requirement removed', ACCEPT,
     '    if not exists (\n        select 1\n        from auth.users as auth_user\n'
     '        where auth_user.id = authenticated_subject_id\n          and auth_user.email_confirmed_at is not null\n    ) then',
     '    if false then',
     'Unverified account cannot accept, before any Invitation fact is considered'),
    ('preview requires a confirmed email', PREVIEW,
     '    select invitation.*\n    into invitation_record',
     "    if not exists (select 1 from auth.users as auth_user where auth_user.id = auth.uid()\n"
     "        and auth_user.email_confirmed_at is not null) then\n"
     "        raise exception 'A verified email address is required' using errcode = '42501';\n"
     '    end if;\n    select invitation.*\n    into invitation_record',
     'Unverified account can preview'),
    # Lifecycle after proof (BR-9, BR-10, BR-20)
    ('expiry ignored', ACCEPT, EXPIRY_CHECK, '',
     'Expired Invitation reported EXPIRED after proof and nothing written'),
    ('acceptance at the expiry instant allowed', ACCEPT,
     '    if effective_instant >= invitation_record.expires_at then',
     '    if effective_instant > invitation_record.expires_at then',
     'Invitation expiring exactly at the acceptance instant is EXPIRED and unchanged'),
    ('revoked Invitation accepted', ACCEPT, REVOKED_CHECK, '',
     'Revoked Invitation reported REVOKED after proof and nothing written'),
    ('revoked Invitation previews as pending', PREVIEW,
     "        if invitation_record.revoked_at is not null then\n            preview_state := 'REVOKED';\n        elsif",
     '        if', 'Post-proof EXPIRED, REVOKED and ALREADY_MEMBER'),
    ('already-a-Member check removed', ACCEPT, MEMBER_CHECK, '',
     'Already-a-Member acceptance reported and no second Membership'),
    ('foreign Clinic responsibility treated as valid', SHAPE,
     '                      or clinic.organization_id is distinct from p_organization_id\n', '',
     'UNAVAILABLE (rejected, bound to another User, invalid responsibility) discloses nothing else'),
    ('different signed-in email rejected', ACCEPT, '    -- 7. Clinics in id order',
     "    if not exists (select 1 from auth.users as auth_user where auth_user.id = authenticated_subject_id\n"
     "        and lower(btrim(auth_user.email)) = invitation_record.recipient_email_normalized) then\n"
     "        raise exception 'Invitation unavailable' using errcode = '42501';\n"
     '    end if;\n    -- 7. Clinics in id order',
     'Different signed-in email accepts with the secret'),
    # Idempotency and provenance (BR-21)
    ('same-User retry not idempotent', ACCEPT, '    if found then\n        return jsonb_build_object(',
     '    if false then\n        return jsonb_build_object(',
     'Lost-response retry returns ALREADY_ACCEPTED with the same Membership'),
    ('another User sees the accepted state', ACCEPT, '      and accepted.user_id = acting_user_id\n', '',
     'Another User replay fails uniformly'),
    ('another User previews ACCEPTED_BY_YOU', PREVIEW, '          and accepted.user_id = acting_user_id\n', '',
     'Another User preview of an accepted Invitation fails uniformly'),
    ('ended Membership still resolves as accepted', ACCEPT,
     '      and accepted.user_id = acting_user_id\n      and accepted.effective_end is null;',
     '      and accepted.user_id = acting_user_id;',
     'Replay after the resulting Membership ended fails uniformly'),
    # Atomic creation (BR-5, BR-7, BR-24, BR-25)
    ('digest not erased after success', WRITER,
     '    update public.organization_invitations\n    set acceptance_secret_digest = null\n    where id = p_invitation_id;\n', '',
     'Pending Organization Receptionist accepted: one Membership for the caller, digest erased'),
    ('only the first Responsibility granted', WRITER,
     '    where intended.invitation_id = p_invitation_id;\n\n    update',
     '    where intended.invitation_id = p_invitation_id\n    order by intended.id\n    limit 1;\n\n    update',
     'Legacy multi-responsibility Invitation accepted exactly as recorded'),
    ('partial Membership survives a Grant failure', WRITER, GRANTS,
     '    begin\n' + GRANTS + '    exception when others then\n        null;\n    end;\n',
     'Injected Grant failure leaves no Membership, no Grant, and the Invitation pending with its digest'),
    ('Membership provenance omitted', WRITER,
     '        p_invitation_id\n    )\n    returning id into created_membership_id;',
     '        null\n    )\n    returning id into created_membership_id;',
     'Pending Organization Receptionist accepted: one Membership for the caller, digest erased'),
    ('immediate temporal authority broken', ACCEPT,
     '    effective_instant := greatest(statement_timestamp(), invitation_record.created_at);',
     '    effective_instant := clock_timestamp();',
     'Membership starts at the acceptance instant, has no end and records its originating Invitation'),
    # Communications are immutable and unique per Invitation, so the only
    # reachable way for acceptance to "send" is to queue delivery work.
    ('acceptance queues the Invitation email again', WRITER, '    return created_membership_id;',
     '    insert into public.communication_delivery_jobs (communication_id, channel, provider, destination_key,\n'
     '        destination_snapshot, state)\n'
     "    select communication.id, 'EMAIL', 'RESEND', 'EMAIL:' || lower(communication.recipient_email),\n"
     "        lower(communication.recipient_email), 'READY'\n"
     '    from public.transactional_communications as communication\n'
     '    where communication.organization_invitation_id = p_invitation_id;\n'
     '    return created_membership_id;',
     'Acceptance creates and changes no Communication'),
    # Serialization (BR-24)
    ('acceptance without the Organization lock', ACCEPT,
     '    perform 1\n    from public.veterinary_organizations as organization\n'
     '    where organization.id = target_organization_id\n    for update;\n', '',
     'Acceptance serializes on Organization then Invitation before provenance and proof'),
    ('intended Clinic not locked', WRITER, '    order by clinic.id\n    for update of clinic;', '    order by clinic.id;',
     'Acceptance locks the intended Clinic before writing'),
    # Preview disclosure (§10)
    ('mask exposes the local part', MASK, "left(p_normalized_email, 1) || '***@'",
     "split_part(p_normalized_email, '@', 1) || '***@'",
     'PENDING preview: exact payload, masked address, matching account'),
    ('email match not normalized', PREVIEW,
     "            select lower(btrim(auth_user.email, E' \\t\\n\\r\\f\\013'))\n"
     "                = invitation_record.recipient_email_normalized",
     '            select auth_user.email = invitation_record.recipient_email',
     'PENDING preview: exact payload, masked address, matching account'),
    ('preview discloses the Organization id', PREVIEW,
     "        'state', preview_state,\n        'organization_display_name', (",
     "        'state', preview_state,\n        'organization_id', invitation_record.organization_id,\n"
     "        'organization_display_name', (",
     'PENDING preview: exact payload, masked address, matching account'),
]


def migration_function(source, name):
    match = re.search(r"^create (or replace )?function public\." + name + r"\(.*?^\$\$;\n", source, re.M | re.S)
    if not match:
        raise HarnessFailure(f'Function {name} not found in migration')
    return re.sub(r'^create (or replace )?function', 'create or replace function', match.group(0), count=1)


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        migration = MIGRATION.read_text(encoding='utf-8')
        bases = {name: migration_function(migration, name) for name in (PREVIEW, ACCEPT, WRITER, SHAPE, MASK)}
        candidates = [Fault(name, replace_once(bases[function], before, after), assertion)
                      for name, function, before, after, assertion in FAULTS]
        client.faults(source, candidates)
        client.suite(SUITE)
        client.verify_zero_fixtures(['d0280000-'])


if __name__ == '__main__':
    main()

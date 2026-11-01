"""Reproducible LOCAL-only Staff Slice C mutation regression (SPEC-ORG-004 §10,
§11; SPEC-ORG-005; SPEC-VET-005 BR-22).

Run from repository root after a clean local reset. Each behavioural mutant
replaces one function (or one grant) inside the rollback-only Slice C suite
transaction and must be caught by its named assertion; infrastructure errors
never count. Session rollback/restoration and zero retained fixtures are
verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/staff_end_access_spec_org_004.sql'
MIGRATION = ROOT / 'supabase/migrations/20261029090000_staff_end_access.sql'
B2_MIGRATION = ROOT / 'supabase/migrations/20261028090000_staff_invitation_preview_and_accept.sql'

END = 'end_organization_staff_membership'
WRITER = 'establish_membership_from_organization_invitation'
CAPABILITY = 'user_has_organization_capability'

FIRST_CAPABILITY = ("       or not public.user_has_organization_capability(\n"
                    "           acting_user_id, target_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'\n"
                    "       ) then")
SECOND_CAPABILITY = ("    if not found or not public.user_has_organization_capability(\n"
                     "        acting_user_id, target_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'\n"
                     "    ) then")
AFTER_TARGET_LOOKUP = "    where membership.id = p_membership_id;\n\n    if target_organization_id is null"
SELF_CHECK = ("    if membership_record.user_id = acting_user_id then\n"
              "        raise exception 'Own Organization Membership cannot be ended through Staff'\n"
              "            using errcode = '23514', hint = 'SELF_MEMBERSHIP';\n"
              "    end if;\n")
OWNER_CHECK = ("    if exists (\n"
               "        select 1\n"
               "        from public.organization_responsibility_grants as grant_record\n"
               "        where grant_record.membership_id = p_membership_id\n"
               "          and grant_record.effective_end is null\n"
               "          and grant_record.responsibility = 'OWNER'\n"
               "    ) then\n"
               "        raise exception 'An Owner Membership cannot be ended through Staff'\n"
               "            using errcode = '23514', hint = 'OWNER_MEMBERSHIP';\n"
               "    end if;\n")
END_GRANTS = ("    update public.organization_responsibility_grants\n"
              "    set effective_end = effective_instant,\n"
              "        ended_by_user_id = acting_user_id\n"
              "    where membership_id = p_membership_id\n"
              "      and effective_end is null;\n")
END_MEMBERSHIP = ("    update public.organization_memberships\n"
                  "    set effective_end = effective_instant,\n"
                  "        ended_by_user_id = acting_user_id\n"
                  "    where id = p_membership_id;\n")
CLAMP = ("    effective_instant := greatest(\n"
         "        statement_timestamp(),\n"
         "        membership_record.effective_start,\n")
ALREADY_ENDED = ("    if membership_record.effective_end is not null then\n"
                 "        return jsonb_build_object(\n"
                 "            'membership_id', membership_record.id,\n"
                 "            'effective_end', membership_record.effective_end,\n"
                 "            'outcome', 'ALREADY_ENDED'\n"
                 "        );\n"
                 "    end if;\n")
ORGANIZATION_LOCK = ("    perform 1\n"
                     "    from public.veterinary_organizations as organization\n"
                     "    where organization.id = target_organization_id\n"
                     "    for update;\n")
BEFORE_RETURN = "    return jsonb_build_object(\n        'membership_id', membership_record.id,\n        'effective_end', effective_instant,"

# (name, function, edits [(before, after)], expected assertion)
FAULTS = [
    ('authorization removed', END, [(FIRST_CAPABILITY, '       or false then'),
                                    (SECOND_CAPABILITY, '    if not found then')],
     'Caller without ORGANIZATION_END_MEMBERSHIPS fails uniformly: 3'),
    ('unknown target leaks 23503', END,
     [(AFTER_TARGET_LOOKUP, "    where membership.id = p_membership_id;\n\n"
       "    if target_organization_id is null then\n"
       "        raise exception 'Organization Membership does not exist' using errcode = '23503';\n"
       "    end if;\n\n    if target_organization_id is null")],
     'Caller without ORGANIZATION_END_MEMBERSHIPS fails uniformly: 3'),
    ('ended state disclosed before authorization', END,
     [(AFTER_TARGET_LOOKUP, "    where membership.id = p_membership_id;\n\n"
       "    if exists (select 1 from public.organization_memberships as ended\n"
       "        where ended.id = p_membership_id and ended.effective_end is not null) then\n"
       "        return jsonb_build_object('membership_id', p_membership_id, 'outcome', 'ALREADY_ENDED');\n"
       "    end if;\n\n    if target_organization_id is null")],
     'Caller without ORGANIZATION_END_MEMBERSHIPS fails uniformly: 3'),
    ('self-end allowed', END, [(SELF_CHECK, '')], 'Own Membership is rejected even with the capability'),
    ('Owner end allowed while another Owner exists', END, [(OWNER_CHECK, '')],
     'A Membership holding an active OWNER Grant is rejected even when another Owner exists'),
    ('Membership ended, Grants left active', END, [(END_GRANTS, '')],
     'Administrator ends a multi-Grant Member: exact ENDED result'),
    ('only the first Grant ended', END,
     [(END_GRANTS, END_GRANTS.replace("      and effective_end is null;\n",
       "      and effective_end is null\n      and id = (select min(first_grant.id) from public.organization_responsibility_grants as first_grant\n"
       "          where first_grant.membership_id = p_membership_id and first_grant.effective_end is null);\n"))],
     'Administrator ends a multi-Grant Member: exact ENDED result'),
    ('Membership and Grant ends differ', END,
     [(END_MEMBERSHIP, END_MEMBERSHIP.replace('set effective_end = effective_instant,',
                                              "set effective_end = effective_instant + interval '1 millisecond',"))],
     'Every active Grant and the Membership end at the same instant, by the acting User'),
    ('temporal clamp removed', END,
     [(CLAMP, "    effective_instant := greatest(\n        statement_timestamp(),\n        statement_timestamp(),\n"),
      ("            where grant_record.membership_id = p_membership_id\n              and grant_record.effective_end is null\n        )\n    );",
       "            where false\n        )\n    );")],
     'End instant never precedes the latest active Grant start'),
    ('already ended not idempotent', END, [(ALREADY_ENDED, '')],
     'Retry returns ALREADY_ENDED with the original effective end'),
    ('Veterinarian Clinic Assignment ended', END,
     [(BEFORE_RETURN, "    update public.veterinarian_clinic_assignments\n"
       "    set effective_end = effective_instant\n"
       "    where supporting_membership_id = p_membership_id and effective_end is null;\n\n" + BEFORE_RETURN)],
     'Assignment, Veterinarian profile and Appointment Veterinarian Assignment are kept'),
    ('Appointment Veterinarian Assignment ended', END,
     [(BEFORE_RETURN, "    update public.appointment_veterinarian_assignments as appointment_assignment\n"
       "    set effective_end = effective_instant\n"
       "    from public.veterinarian_clinic_assignments as clinic_assignment\n"
       "    where clinic_assignment.id = appointment_assignment.veterinarian_clinic_assignment_id\n"
       "      and clinic_assignment.supporting_membership_id = p_membership_id\n"
       "      and appointment_assignment.effective_end is null;\n\n" + BEFORE_RETURN)],
     # Since 20261112090000 an ended Appointment Veterinarian Assignment needs a
     # same-instant successor (SPEC-APT-007 BR-36), so the mutated operation
     # itself fails and the first scenario assertion observes it.
     'Veterinarian ended: the Clinic Assignment is no longer current and grants nothing'),
    ("departing inviter's pending Invitations revoked", END,
     [(BEFORE_RETURN, "    update public.organization_invitations as invitation\n"
       "    set revoked_at = effective_instant, revoked_by_user_id = acting_user_id\n"
       "    where invitation.inviting_user_id = membership_record.user_id\n"
       "      and invitation.organization_id = target_organization_id\n"
       "      and invitation.revoked_at is null and invitation.rejected_at is null\n"
       "      and invitation.expires_at > effective_instant\n"
       "      and not exists (select 1 from public.organization_memberships as accepted\n"
       "          where accepted.originating_invitation_id = invitation.id);\n\n" + BEFORE_RETURN)],
     'Ending every role changes no Invitation, Communication, Assignment, Appointment, User or Clinic'),
    ('offboarding queues email delivery', END,
     [(BEFORE_RETURN, "    insert into public.communication_delivery_jobs (communication_id, channel, provider,\n"
       "        destination_key, destination_snapshot, state)\n"
       "    select communication.id, 'EMAIL', 'RESEND', 'EMAIL:offboarding:' || communication.id,\n"
       "        lower(communication.recipient_email), 'READY'\n"
       "    from public.transactional_communications as communication\n"
       "    join public.organization_invitations as invitation on invitation.id = communication.organization_invitation_id\n"
       "    where invitation.organization_id = target_organization_id;\n\n" + BEFORE_RETURN)],
     'Ending deletes nothing and changes no Invitation, Communication, Assignment, Appointment, User or Clinic'),
    ('ending also ends other Organizations', END,
     [(END_GRANTS, "    update public.organization_responsibility_grants\n"
       "    set effective_end = effective_instant,\n        ended_by_user_id = acting_user_id\n"
       "    where membership_id in (select every_membership.id from public.organization_memberships as every_membership\n"
       "        where every_membership.user_id = membership_record.user_id and every_membership.effective_end is null)\n"
       "      and effective_end is null;\n"),
      (END_MEMBERSHIP, "    update public.organization_memberships\n"
       "    set effective_end = effective_instant,\n        ended_by_user_id = acting_user_id\n"
       "    where user_id = membership_record.user_id and effective_end is null;\n")],
     'Ending access in A keeps the Membership, Grant and authority in B'),
    ('end access without the Organization lock', END, [(ORGANIZATION_LOCK, '')],
     'End access serializes on Organization, Membership and its active Grants'),
    ('Organization authority ignores ended Membership and Grant', CAPABILITY,
     [('              and membership.effective_end is null\n', ''),
      ('              and grant_record.effective_end is null\n', '')],
     'Authority ends in the same statement'),
    ('rejoin reuses the ended Membership', WRITER,
     [('    perform 1\n    from public.clinics as clinic\n',
       "    select previous.id into created_membership_id\n"
       "    from public.organization_memberships as previous\n"
       "    where previous.user_id = p_accepting_user_id and previous.organization_id = p_organization_id\n"
       "    order by previous.effective_start desc\n    limit 1;\n"
       "    if found then\n        return created_membership_id;\n    end if;\n\n"
       "    perform 1\n    from public.clinics as clinic\n")],
     'Rejoining creates a new active Membership period with the new Invitation as provenance'),
]
ACL_FAULT = Fault('permissive generic end operation executable by authenticated',
                  'grant execute on function public.end_organization_membership(uuid) to authenticated;\n',
                  'No client role executes the permissive generic end operation')


def migration_function(source, name):
    match = re.search(r"^create (or replace )?function public\." + name + r"\(.*?^\$\$;\n", source, re.M | re.S)
    if not match:
        raise HarnessFailure(f'Function {name} not found in migration')
    return re.sub(r'^create (or replace )?function', 'create or replace function', match.group(0), count=1)


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        bases = {
            END: migration_function(MIGRATION.read_text(encoding='utf-8'), END),
            WRITER: migration_function(B2_MIGRATION.read_text(encoding='utf-8'), WRITER),
            CAPABILITY: client.definition(f'public.{CAPABILITY}(uuid, uuid, text)'),
        }
        candidates = []
        for name, function, edits, assertion in FAULTS:
            candidate = bases[function]
            for before, after in edits:
                candidate = replace_once(candidate, before, after)
            candidates.append(Fault(name, candidate, assertion))
        candidates.append(ACL_FAULT)
        client.faults(source, candidates)
        client.suite(SUITE)
        client.verify_zero_fixtures(['d0290000-'])


if __name__ == '__main__':
    main()

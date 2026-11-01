"""Reproducible LOCAL-only mutation regression for Staff Responsibility Editing
+ Veterinarian Enablement Phase 1 (SPEC-ORG-006 §14/§15, SPEC-VET-001 §13/§14,
SPEC-VET-004 §13/§14, SPEC-VET-005 §13/§14, SPEC-VET-006, SPEC-ORG-005 §6).

Run from the repository root after a clean local reset. Each behavioural
mutant replaces one function (or one grant) inside a rollback-only suite
transaction and must be caught by its named assertion; infrastructure errors
never count. Session rollback/restoration and zero retained fixtures are
verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

MIGRATION = ROOT / 'supabase/migrations/20261102090000_staff_responsibility_and_veterinarian_workforce.sql'
SUITES = {
    'RESP': ROOT / 'supabase/tests/staff_responsibility_management_spec_org_006.sql',
    'PROF': ROOT / 'supabase/tests/veterinarian_profile_self_service_spec_vet_001.sql',
    'WF': ROOT / 'supabase/tests/veterinarian_workforce_assignment_spec_vet_004_005_006.sql',
    'CHAIN': ROOT / 'supabase/tests/veterinarian_enablement_capability_chain.sql',
}

ADD, REPLACE, END = 'add_staff_responsibility', 'replace_staff_responsibility', 'end_staff_responsibility'
SCOPE = 'staff_responsibility_scope_is_supported'
PROFILE = 'create_my_veterinarian_professional_profile'
WORKFORCE = 'get_organization_veterinarian_workforce'
ASSIGN, UNASSIGN = 'assign_staff_veterinarian_to_clinic', 'end_staff_veterinarian_clinic_assignment'
MANAGES = 'user_manages_veterinarian_assignments_at'
CLINIC_CAPABILITY = 'user_has_clinic_scoped_clinic_capability'
CURRENT = 'veterinarian_clinic_assignment_is_current'

STEP_2 = '    -- 2. Organization and capability, re-decided under the Organization lock.\n'
TARGET_IN_ORG = ('    where grant_record.id = p_responsibility_grant_id\n'
                 '      and membership.organization_id = p_organization_id;\n')
MEMBERSHIP_LOCK_IN_ORG = ('    where membership.id = target_membership_id\n'
                          '      and membership.organization_id = p_organization_id\n    for update;\n')
OWNER_MEMBERSHIP_ADD = ("    if membership_record.user_id <> acting_user_id\n"
                        "       and public.staff_membership_holds_owner(membership_record.id) then\n"
                        "        raise exception 'An Owner Membership cannot be changed through Staff'\n"
                        "            using errcode = '23514', hint = 'OWNER_MEMBERSHIP';\n    end if;\n")
OWNER_GRANT_END = ("    if source_grant.responsibility = 'OWNER' then\n"
                   "        raise exception 'An OWNER Responsibility cannot be ended through Staff'\n"
                   "            using errcode = '23514', hint = 'OWNER_GRANT';\n    end if;\n")
SELF_CHECK = ("    if membership_record.user_id = acting_user_id and not target_is_owner then\n"
              "        raise exception 'Own Responsibilities cannot be changed through Staff'\n"
              "            using errcode = '23514', hint = 'SELF_MEMBERSHIP';\n    end if;\n")
INACTIVE = ("    if not (\n        membership_record.effective_start <= statement_timestamp()\n"
            "        and membership_record.effective_end is null\n    ) then\n"
            "        raise exception 'Organization Membership is not current'\n"
            "            using errcode = '23514', hint = 'MEMBERSHIP_INACTIVE';\n    end if;\n")
VET_ACTIVE_END = ("    if source_grant.responsibility = 'VETERINARIAN'\n"
                  "       and public.membership_supports_current_veterinarian_assignment(membership_record.id) then\n"
                  "        raise exception 'Current Veterinarian Clinic Assignments must be ended first'\n"
                  "            using errcode = '23514', hint = 'VETERINARIAN_ASSIGNMENTS_ACTIVE';\n    end if;\n")
REPLACE_WRITE = ("    created_grant_id := public.replace_organization_responsibility(\n"
                 "        source_grant.id, p_responsibility, p_scope_type, p_clinic_id\n    );\n")
PROFILE_WRITE = ("    select created.professional_profile_id, created.professional_credential_id\n"
                 "    into created_profile_id, created_credential_id\n"
                 "    from public.create_veterinarian_professional_profile(\n"
                 "        normalized_registration_identifier,\n        normalized_issuing_context\n    ) as created;\n")
EXACT_REPLAY = ("        if existing_registration_identifier is not distinct from normalized_registration_identifier\n"
                "           and existing_issuing_context is not distinct from normalized_issuing_context then")
ASSIGN_STEP_2 = '    -- 2. Clinic of the Organization and capability, re-decided under the\n'

# (suite, name, function, edits [(before, after)], expected assertion)
FAULTS = [
    ('RESP', 'Add reports target existence before authorization', ADD,
     [(STEP_2, "    if not exists (select 1 from public.organization_memberships as leaked where leaked.id = p_membership_id) then\n"
               "        raise exception 'Organization Membership does not exist' using errcode = '23503';\n    end if;\n" + STEP_2)],
     'Add without the capability fails uniformly, before input: 3'),
    ('RESP', 'Change validates input before authorization', REPLACE,
     [(STEP_2, "    if not public.staff_responsibility_scope_is_supported(p_responsibility, p_scope_type, p_clinic_id) then\n"
               "        raise exception 'Responsibility role or scope is not supported' using errcode = '22023', hint = 'INVALID_SCOPE';\n"
               "    end if;\n" + STEP_2)],
     'Change/End without the capability fail uniformly, before input or lifecycle: 3'),
    ('RESP', 'End reaches a Grant of another Organization', END,
     [(TARGET_IN_ORG, '    where grant_record.id = p_responsibility_grant_id;\n'),
      (MEMBERSHIP_LOCK_IN_ORG, '    where membership.id = target_membership_id\n    for update;\n')],
     'Unknown and other-Organization targets fail exactly as an inaccessible Organization'),
    ('RESP', 'Change also ends unrelated Grants', REPLACE,
     [(REPLACE_WRITE, REPLACE_WRITE + "\n    update public.organization_responsibility_grants\n"
       "    set effective_end = statement_timestamp(), ended_by_user_id = acting_user_id\n"
       "    where membership_id = membership_record.id and effective_end is null and id <> created_grant_id;\n")],
     'Unrelated Grants of the Member are untouched by Change'),
    ('RESP', 'OWNER Grant endable', END, [(OWNER_GRANT_END, '')],
     'An OWNER Grant is never changed or ended, including by the Owner'),
    ('RESP', 'Administrator adds to an Owner Membership', ADD, [(OWNER_MEMBERSHIP_ADD, '')],
     'An Administrator, and another Owner, cannot Add, Change or End on an Owner Membership'),
    ('RESP', 'Administrator self-demotion allowed', REPLACE, [(SELF_CHECK, '')],
     'An Administrator cannot Change or End their own Grants (no self-demotion or lockout)'),
    ('RESP', 'last Grant ended', END,
     [("        raise exception 'The last current Responsibility is ended through End access'\n"
       "            using errcode = '23514', hint = 'LAST_RESPONSIBILITY';", '        null;')],
     'Ending the last current Grant is rejected; the Membership stays'),
    ('RESP', 'VETERINARIAN Clinic scope accepted', SCOPE,
     [("            and p_responsibility in ('ADMINISTRATOR', 'RECEPTIONIST')\n        ),\n        false",
       "            and p_responsibility in ('ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN')\n        ),\n        false")],
     'OWNER, Clinic-scoped VETERINARIAN and malformed scopes are rejected on Add'),
    ('RESP', 'VETERINARIAN ended with an open Assignment', END, [(VET_ACTIVE_END, '')],
     'VETERINARIAN cannot be ended or changed away while a current Clinic Assignment exists; nothing is ended automatically'),
    ('RESP', 'VETERINARIAN end cascades Assignment ends', END,
     [(VET_ACTIVE_END, "    update public.veterinarian_clinic_assignments set effective_end = statement_timestamp()\n"
                       "    where supporting_membership_id = membership_record.id and effective_end is null;\n")],
     'VETERINARIAN cannot be ended or changed away while a current Clinic Assignment exists; nothing is ended automatically'),
    ('RESP', 'stale Change reported as completed', REPLACE,
     [("        raise exception 'Organization Responsibility Grant has already ended'\n"
       "            using errcode = '23514', hint = 'GRANT_ENDED';",
       "        return jsonb_build_object('outcome', 'ALREADY_CHANGED');")],
     'A different Change of an ended Grant is stale and writes nothing'),
    ('RESP', 'repeated End not idempotent', END,
     [("    if source_grant.effective_end is not null then\n        return jsonb_build_object(\n            'outcome', 'ALREADY_ENDED',",
       "    if false then\n        return jsonb_build_object(\n            'outcome', 'ALREADY_ENDED',")],
     'Repeated End returns ALREADY_ENDED with the original end and writes nothing'),
    ('RESP', 'repeated Add not reconciled', ADD,
     [("    if found then\n        return jsonb_build_object(\n            'outcome', 'ALREADY_PRESENT',",
       "    if false then\n        return jsonb_build_object(\n            'outcome', 'ALREADY_PRESENT',")],
     'Repeated Add reconciles to the existing Grant and writes nothing'),
    ('RESP', 'ended Membership treated current on Add', ADD, [(INACTIVE, '')],
     'An ended Membership receives no Responsibility change (rejoining needs a new Membership)'),

    ('PROF', 'Profile created for another User', PROFILE,
     [(PROFILE_WRITE, "    insert into public.veterinarian_professional_profiles (user_id)\n"
       "    select min(other.id::text)::uuid from public.users as other where other.id <> acting_user_id\n"
       "      and not exists (select 1 from public.veterinarian_professional_profiles as held where held.user_id = other.id)\n"
       "    returning id into created_profile_id;\n"
       "    insert into public.veterinarian_professional_credentials (professional_profile_id, registration_identifier, issuing_context)\n"
       "    values (created_profile_id, normalized_registration_identifier, normalized_issuing_context)\n"
       "    returning id into created_credential_id;\n")],
     'The acting User gets exactly one Profile and one normalized Credential'),
    ('PROF', 'different credential replay ignored', PROFILE,
     [("        raise exception 'A Veterinarian Professional Profile already exists with different details'\n"
       "            using errcode = '23514', hint = 'PROFILE_CREDENTIAL_MISMATCH';",
       "        return jsonb_build_object('outcome', 'ALREADY_EXISTS', 'professional_profile_id', existing_profile_id,\n"
       "            'professional_credential_id', existing_credential_id);")],
     'A materially different identifier or context is a deterministic conflict'),
    ('PROF', 'credential replay compared case-insensitively', PROFILE,
     [(EXACT_REPLAY, "        if lower(existing_registration_identifier) = lower(normalized_registration_identifier)\n"
                     "           and lower(existing_issuing_context) = lower(normalized_issuing_context) then")],
     'A materially different identifier or context is a deterministic conflict'),
    ('PROF', 'exact replay not reconciled', PROFILE, [(EXACT_REPLAY, '        if false then')],
     'An exact repeat, including surrounding whitespace, returns ALREADY_EXISTS with the same ids'),
    ('PROF', 'unverified account accepted', PROFILE, [('          and auth_user.email_confirmed_at is not null\n', '')],
     'An unverified account is rejected before input'),
    ('PROF', 'creation not serialized on the User', PROFILE,
     [('    perform 1\n    from public.users as domain_user\n    where domain_user.id = acting_user_id\n    for update;\n', '')],
     'Creation serializes on the acting User'),

    ('WF', 'workforce leaks the registration identifier', WORKFORCE,
     [("                'membership_id', listed.id,\n",
       "                'membership_id', listed.id,\n                'registration_identifier', (select credential.registration_identifier\n"
       "                    from public.veterinarian_professional_credentials as credential\n"
       "                    join public.veterinarian_professional_profiles as held on held.id = credential.professional_profile_id\n"
       "                    where held.user_id = listed.user_id),\n")],
     'Exact Member fields: no User, Auth, Profile or credential data'),
    ('WF', 'workforce leaks the domain User id', WORKFORCE,
     [("                'membership_id', listed.id,\n", "                'membership_id', listed.id,\n                'user_id', listed.user_id,\n")],
     'Exact Member fields: no User, Auth, Profile or credential data'),
    ('WF', "workforce includes another Organization's Members", WORKFORCE,
     [('        join authorized_organization as organization\n          on organization.id = membership.organization_id\n',
       '        cross join authorized_organization as organization\n')],
     'Exactly current Members with VETERINARIAN or a current Assignment, ordered; others and ended Members absent'),
    ('WF', 'workforce hides a stale Assignment', WORKFORCE,
     [('           or exists (\n                select 1\n                from current_assignment\n'
       '                where current_assignment.supporting_membership_id = current_membership.id\n            )\n', '')],
     'Exactly current Members with VETERINARIAN or a current Assignment, ordered; others and ended Members absent'),
    ('WF', 'workforce lists ended Assignments', WORKFORCE,
     [('        where assignment.effective_end is null\n          and public.veterinarian_clinic_assignment_is_current(assignment.id)\n',
       '        where true\n')],
     'Profile present; only the current Assignment is listed, the ended one is not'),
    ('WF', 'workforce authorization removed', WORKFORCE,
     [("          and public.user_has_organization_capability(\n"
       "              acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'\n          )\n    ), current_membership",
       '    ), current_membership')],
     'Workforce read denied: 3'),
    ('WF', 'Assign without a Profile', ASSIGN,
     [("    if not found then\n        raise exception 'A Veterinarian Professional Profile is required'\n"
       "            using errcode = '23514', hint = 'PROFILE_REQUIRED';\n    end if;\n", '')],
     'Missing Profile, missing or ended VETERINARIAN, and an ended Membership are rejected'),
    ('WF', 'Assign without a VETERINARIAN Grant', ASSIGN,
     [("    if not exists (\n        select 1\n        from public.organization_responsibility_grants as grant_record\n"
       "        where grant_record.membership_id = membership_record.id\n          and grant_record.responsibility = 'VETERINARIAN'",
       "    if false and not exists (\n        select 1\n        from public.organization_responsibility_grants as grant_record\n"
       "        where grant_record.membership_id = membership_record.id\n          and grant_record.responsibility = 'VETERINARIAN'")],
     'Missing Profile, missing or ended VETERINARIAN, and an ended Membership are rejected'),
    ('WF', 'Assign treats an ended Membership as current', ASSIGN,
     [("        membership_record.effective_start <= statement_timestamp()\n        and membership_record.effective_end is null\n",
       "        membership_record.effective_start <= statement_timestamp()\n")],
     'Missing Profile, missing or ended VETERINARIAN, and an ended Membership are rejected'),
    ('WF', "Assign accepts another Organization's Membership", ASSIGN,
     [('    where membership.id = p_membership_id\n      and membership.organization_id = p_organization_id\n    for update;',
       '    where membership.id = p_membership_id\n    for update;')],
     "Another Organization's Membership and an unknown Membership fail exactly as an inaccessible Clinic"),
    ('WF', 'Assign reports Membership existence before authorization', ASSIGN,
     [(ASSIGN_STEP_2, "    if not exists (select 1 from public.organization_memberships as leaked where leaked.id = p_membership_id) then\n"
                      "        raise exception 'Supporting Organization Membership does not exist' using errcode = '23503';\n"
                      "    end if;\n\n" + ASSIGN_STEP_2)],
     'Without CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS every target fails uniformly, before prerequisites or lifecycle: 4'),
    ('WF', 'Assignment authorization removed', MANAGES,
     [("          and public.user_has_clinic_capability(\n"
       "              p_user_id, p_clinic_id, 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'\n          )\n", '')],
     'Without CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS every target fails uniformly, before prerequisites or lifecycle: 4'),
    ('WF', 'Assign stamps a later clock instant', ASSIGN,
     [('        greatest(statement_timestamp(), membership_record.effective_start)\n    )\n    returning * into created_assignment;',
       '        clock_timestamp()\n    )\n    returning * into created_assignment;')],
     'Assign establishes one Assignment at the statement instant with the server-derived Profile'),
    ('WF', 'End ignores the named Clinic (cross-Clinic/Organization end)', UNASSIGN,
     [('    where assignment.id = p_veterinarian_clinic_assignment_id\n      and assignment.clinic_id = p_clinic_id\n    for update;',
       '    where assignment.id = p_veterinarian_clinic_assignment_id\n    for update;')],
     'End: an Assignment of another Clinic or Organization and an unknown Assignment fail uniformly'),
    ('WF', 'End stamps a later clock instant', UNASSIGN,
     [('    effective_instant := greatest(statement_timestamp(), assignment_record.effective_start);',
       '    effective_instant := clock_timestamp();')],
     'End records the statement instant'),
    ('WF', 'End requires a VETERINARIAN Grant (blocks cleanup)', UNASSIGN,
     [('    -- 4. Lifecycle: an ended Assignment is reported, never rewritten.\n',
       "    if not exists (select 1 from public.organization_responsibility_grants as held\n"
       "        where held.membership_id = assignment_record.supporting_membership_id\n"
       "          and held.responsibility = 'VETERINARIAN' and held.effective_end is null) then\n"
       "        raise exception 'A current VETERINARIAN Responsibility is required'\n"
       "            using errcode = '23514', hint = 'VETERINARIAN_RESPONSIBILITY_REQUIRED';\n    end if;\n\n"
       '    -- 4. Lifecycle: an ended Assignment is reported, never rewritten.\n')],
     'Cleanup: an Assignment without a current VETERINARIAN Grant, or of an ended Membership, can still be ended'),
    ('WF', 'ended Assignment re-ended (history rewritten)', UNASSIGN,
     [("    if assignment_record.effective_end is not null then\n        return jsonb_build_object(\n            'outcome', 'ALREADY_ENDED',",
       "    if false then\n        return jsonb_build_object(\n            'outcome', 'ALREADY_ENDED',")],
     'A repeat or a historical Assignment returns ALREADY_ENDED with the original end and writes nothing'),

    ('CHAIN', 'capability granted without a VETERINARIAN Grant', CLINIC_CAPABILITY,
     [("                      and responsibility_grant.responsibility = 'VETERINARIAN'\n", '')],
     'Profile + Assignment without VETERINARIAN: no clinical capability (Receptionist Appointment capability only)'),
    ('CHAIN', 'capability granted from an ended Assignment', CLINIC_CAPABILITY,
     [('                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)\n', '')],
     'Chain 7: ending A1 removes capability at A1 only'),
    ('CHAIN', 'Assignment current under an ended Membership', CURRENT,
     [('          and membership.effective_end is null\n', '')],
     'Chain 12: no Veterinarian capability; the Assignment row is kept but not current; Profile and every Grant period preserved'),
]

# Definitions that are not edits of one function.
EXTRA = [
    ('RESP', Fault('generic Responsibility writer executable by authenticated',
                   'grant execute on function public.add_organization_responsibility(uuid, text, text, uuid) to authenticated;\n',
                   'Generic operation withdrawn from clients, kept for trusted compatibility: '
                   'public.add_organization_responsibility(uuid,text,text,uuid)')),
    ('PROF', Fault('generic Profile writer executable by authenticated',
                   'grant execute on function public.create_veterinarian_professional_profile(text, text) to authenticated;\n',
                   'Self Profile creation is executable by authenticated only; the generic writer is not a client path')),
    ('WF', Fault('Assign accepts a client Profile identifier',
                 'create function public.assign_staff_veterinarian_to_clinic(p_organization_id uuid, p_membership_id uuid,\n'
                 '    p_clinic_id uuid, p_professional_profile_id uuid) returns jsonb language sql as $f$ select null::jsonb $f$;\n'
                 'grant execute on function public.assign_staff_veterinarian_to_clinic(uuid, uuid, uuid, uuid) to authenticated;\n',
                 'Exact contracts: STABLE read, Membership-keyed Assign with no Profile parameter, Organization/Clinic-keyed End')),
    ('WF', Fault('generic Assignment writer executable by authenticated',
                 'grant execute on function public.assign_veterinarian_to_clinic(uuid, uuid, uuid) to authenticated;\n',
                 'Authenticated clients cannot reach the generic Assignment operations (no client-supplied Profile)')),
]


def migration_function(source, name):
    match = re.search(r"^create (or replace )?function public\." + name + r"\(.*?^\$\$;\n", source, re.M | re.S)
    if not match:
        raise HarnessFailure(f'Function {name} not found in migration')
    return re.sub(r'^create (or replace )?function', 'create or replace function', match.group(0), count=1)


def main():
    client = LocalSql()
    migration = MIGRATION.read_text(encoding='utf-8')
    with client.restored():
        sources = {key: client.suite(path) for key, path in SUITES.items()}
        bases = {name: migration_function(migration, name)
                 for name in (ADD, REPLACE, END, SCOPE, PROFILE, WORKFORCE, ASSIGN, UNASSIGN, MANAGES)}
        bases[CLINIC_CAPABILITY] = client.definition(f'public.{CLINIC_CAPABILITY}(uuid, uuid, text)')
        bases[CURRENT] = client.definition(f'public.{CURRENT}(uuid)')
        total = 0
        for key in SUITES:
            candidates = []
            for suite, name, function, edits, assertion in FAULTS:
                if suite != key:
                    continue
                candidate = bases[function]
                for before, after in edits:
                    candidate = replace_once(candidate, before, after)
                candidates.append(Fault(name, candidate, assertion))
            candidates.extend(fault for suite, fault in EXTRA if suite == key)
            client.faults(sources[key], candidates)
            total += len(candidates)
            client.suite(SUITES[key])
        print(f'{total}/{total} workforce mutation assertions observed across {len(SUITES)} suites', flush=True)
        client.verify_zero_fixtures(['d0330000-', 'd0331000-', 'd0332000-', 'd0333000-'])


if __name__ == '__main__':
    main()

"""Reproducible LOCAL-only Clinic creation mutation regression (SPEC-CLI-001
§10 BR-12–BR-16, Verification Notes 11–19).

Run from repository root after a clean local reset. Each behavioural mutant
replaces one function (or one grant) inside the rollback-only Clinic creation
suite transaction and must be caught by its named assertion; infrastructure
errors never count. Session rollback/restoration and zero retained fixtures
are verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/clinic_creation_spec_cli_001.sql'
MIGRATION = ROOT / 'supabase/migrations/20261030090000_idempotent_clinic_creation.sql'

CREATE = 'create_clinic'
IMMUTABILITY = 'enforce_clinic_immutability'

FIRST_CHECK = ("    if not public.user_has_organization_capability(\n"
               "        acting_user_id, p_organization_id, 'ORGANIZATION_CREATE_CLINICS'\n"
               "    ) then")
LOCKED_CHECK = ("    if not found or not public.user_has_organization_capability(\n"
                "        acting_user_id, p_organization_id, 'ORGANIZATION_CREATE_CLINICS'\n"
                "    ) then")
LOCK = ("    perform 1\n"
        "    from public.veterinary_organizations as organization\n"
        "    where organization.id = p_organization_id\n"
        "    for update;\n")
KEY_CHECK = ("    if p_idempotency_key is null then\n"
             "        raise exception 'Clinic creation key is required'\n"
             "            using errcode = '22023';\n"
             "    end if;\n")
LOOKUP = ("    select clinic.id\n"
          "    into created_clinic_id\n"
          "    from public.clinics as clinic\n"
          "    where clinic.organization_id = p_organization_id\n"
          "      and clinic.creation_idempotency_key = p_idempotency_key;\n"
          "\n"
          "    if found then\n"
          "        return jsonb_build_object(\n"
          "            'clinic_id', created_clinic_id,\n"
          "            'organization_id', p_organization_id,\n"
          "            'outcome', 'ALREADY_CREATED'\n"
          "        );\n"
          "    end if;\n")
ORGANIZATION_SCOPED_LOOKUP = ("    where clinic.organization_id = p_organization_id\n"
                              "      and clinic.creation_idempotency_key = p_idempotency_key;")
REPLAYED_ID = ("            'clinic_id', created_clinic_id,\n"
               "            'organization_id', p_organization_id,\n"
               "            'outcome', 'ALREADY_CREATED'")
INSERT = ("    insert into public.clinics (\n"
          "        organization_id,\n"
          "        created_at,\n"
          "        creation_idempotency_key\n"
          "    )\n"
          "    values (\n"
          "        p_organization_id,\n"
          "        clock_timestamp(),\n"
          "        p_idempotency_key\n"
          "    )\n"
          "    returning id into created_clinic_id;\n")
RETURN_CREATED = ("    return jsonb_build_object(\n"
                  "        'clinic_id', created_clinic_id,\n"
                  "        'organization_id', p_organization_id,\n"
                  "        'outcome', 'CREATED'\n"
                  "    );")
KEY_IMMUTABLE = "       or old.creation_idempotency_key is distinct from new.creation_idempotency_key then"

OWNER_CREATES = 'Owner creates a Clinic without any Subscription or Entitlement'
TARGET_ORGANIZATION = 'The new Clinic belongs to exactly the target Organization'
NO_PLACEHOLDERS = 'The new Clinic has no placeholder configuration'
REPLAY = 'Replay with the same key returns the same Clinic and creates nothing'


def published_insert(with_placeholders):
    published = INSERT.replace("        creation_idempotency_key\n    )\n",
                               "        creation_idempotency_key,\n        is_published\n    )\n")
    published = published.replace("        p_idempotency_key\n    )\n", "        p_idempotency_key,\n        true\n    )\n")
    if not with_placeholders:
        return published
    # Inserted unpublished, then given what publication needs and published.
    return (INSERT +
            "    insert into public.clinic_public_profiles (clinic_id, display_name) values (created_clinic_id, 'Nueva clínica');\n"
            "    insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)\n"
            "    values (created_clinic_id, 'Sin dirección', 40.0, -3.0);\n"
            "    update public.clinics set is_published = true where id = created_clinic_id;\n")


# (name, function, edits [(before, after)], expected assertion)
FAULTS = [
    ('authorization removed', CREATE,
     [(FIRST_CHECK, '    if false then'), (LOCKED_CHECK, '    if not found then')],
     'Callers without ORGANIZATION_CREATE_CLINICS are denied uniformly'),
    ('unknown Organization disclosed before authorization', CREATE,
     [(FIRST_CHECK, "    if not exists (select 1 from public.veterinary_organizations as known\n"
                    "        where known.id = p_organization_id) then\n"
                    "        raise exception 'Veterinary Organization does not exist' using errcode = '23503';\n"
                    "    end if;\n\n" + FIRST_CHECK)],
     'Unknown and other-Organization targets fail identically'),
    ('creation key not required', CREATE, [(KEY_CHECK, '')],
     'An authorized creation without a key is rejected and writes nothing'),
    ('Entitlement incorrectly required', CREATE,
     [(KEY_CHECK, KEY_CHECK + "\n    if not public.organization_has_professional_entitlement(\n"
                              "        p_organization_id, 'PROFESSIONAL_SCHEDULING'\n    ) then\n"
                              "        raise exception 'Professional Entitlement is required' using errcode = '42501';\n"
                              "    end if;\n")],
     OWNER_CREATES),
    ('published by default', CREATE, [(INSERT, published_insert(False))], OWNER_CREATES),
    ('Clinic created in the wrong Organization', CREATE,
     [(INSERT, INSERT.replace("    values (\n        p_organization_id,\n",
                              "    values (\n        (select other.id from public.veterinary_organizations as other\n"
                              "         where other.id <> p_organization_id order by other.id limit 1),\n"))],
     TARGET_ORGANIZATION),
    ('result returned without a durable Clinic', CREATE,
     [(INSERT, '    created_clinic_id := gen_random_uuid();\n')], TARGET_ORGANIZATION),
    ('published by default with placeholder name and Location', CREATE,
     [(INSERT, published_insert(True))], 'The new Clinic is unpublished'),
    ('Clinic committed without its durable creation key', CREATE,
     [(INSERT, INSERT.replace("        clock_timestamp(),\n        p_idempotency_key\n",
                              "        clock_timestamp(),\n        null\n"))],
     'The new Clinic durably records its creation key'),
    ('placeholder public profile inserted', CREATE,
     [(RETURN_CREATED, "    insert into public.clinic_public_profiles (clinic_id, display_name)\n"
                       "    values (created_clinic_id, 'Nueva clínica');\n\n" + RETURN_CREATED)],
     NO_PLACEHOLDERS),
    ('placeholder Location inserted', CREATE,
     [(RETURN_CREATED, "    insert into public.clinic_locations (clinic_id, address_text, latitude, longitude)\n"
                       "    values (created_clinic_id, 'Sin dirección', 0, 0);\n\n" + RETURN_CREATED)],
     NO_PLACEHOLDERS),
    ('placeholder scheduling timezone set', CREATE,
     [(RETURN_CREATED, "    update public.clinics set scheduling_timezone_name = 'Europe/Madrid'\n"
                       "    where id = created_clinic_id;\n\n" + RETURN_CREATED)],
     NO_PLACEHOLDERS),
    ('same key creates a duplicate Clinic', CREATE, [(LOOKUP, '')], REPLAY),
    ('replay returns the wrong Clinic', CREATE,
     [(REPLAYED_ID, REPLAYED_ID.replace(
         "'clinic_id', created_clinic_id,",
         "'clinic_id', (select other.id from public.clinics as other\n"
         "                where other.organization_id = p_organization_id order by other.created_at limit 1),"))],
     REPLAY),
    ('key is global rather than Organization-scoped', CREATE,
     [(ORGANIZATION_SCOPED_LOOKUP, "    where clinic.creation_idempotency_key = p_idempotency_key;")],
     "The same key in another Organization creates a separate Clinic there and never returns A's"),
    ('key lookup precedes authorization and leaks the Clinic', CREATE,
     [(LOOKUP, ''), (FIRST_CHECK, LOOKUP + '\n' + FIRST_CHECK)],
     'Lookup follows authorization: an unauthorized replay of a used key is denied without disclosure'),
    ('Organization lock removed', CREATE,
     [(LOCK, LOCK.replace("    where organization.id = p_organization_id\n    for update;\n",
                          "    where organization.id = p_organization_id;\n"))],
     'Creation serializes on the Organization row'),
    ('creation key mutable', IMMUTABILITY, [(KEY_IMMUTABLE, '       then')], 'The creation key cannot be changed'),
]
GRANT_FAULTS = [
    Fault('create executable by anon',
          'grant execute on function public.create_clinic(uuid, uuid) to anon;\n',
          'Create is executable by authenticated only'),
    Fault('non-idempotent one-argument form restored for clients',
          "create function public.create_clinic(p_organization_id uuid) returns uuid language sql\n"
          "security definer set search_path = '' as $f$ select null::uuid $f$;\n"
          "grant execute on function public.create_clinic(uuid) to authenticated;\n",
          'Exact contract: SECURITY DEFINER, empty search_path, Organization and key only, jsonb result'),
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
        bases = {name: migration_function(migration, name) for name in (CREATE, IMMUTABILITY)}
        candidates = []
        for name, function, edits, assertion in FAULTS:
            candidate = bases[function]
            for before, after in edits:
                candidate = replace_once(candidate, before, after)
            candidates.append(Fault(name, candidate, assertion))
        candidates.extend(GRANT_FAULTS)
        client.faults(source, candidates)
        client.suite(SUITE)
        client.verify_zero_fixtures(['d0300000-'])


if __name__ == '__main__':
    main()

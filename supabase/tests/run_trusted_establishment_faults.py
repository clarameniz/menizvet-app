"""Reproducible LOCAL-only mutation regression for ADR-009 trusted Organization
establishment (SPEC-ORG-001 BR-16 / §10, SPEC-SUB-001 §14).

Run from repository root after a clean local reset. Each behavioural mutant
replaces one or more functions (or one grant) inside the rollback-only suite
transaction and must be caught by its named assertion; infrastructure errors
never count. Session rollback/restoration and zero retained fixtures are
verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/trusted_organization_establishment_adr_009.sql'
MIGRATION = ROOT / 'supabase/migrations/20261101090000_trusted_organization_establishment.sql'

ESTABLISH = 'establish_veterinary_organization'
REPLAY = 'replay_veterinary_organization_establishment'
ELIGIBLE = 'assert_initial_owner_eligible'
LATER = 'establish_organization_subscription'
IMMUTABILITY = 'enforce_veterinary_organization_immutability'

LOOKUP = ("    select organization.*\n"
          "    into existing_organization\n"
          "    from public.veterinary_organizations as organization\n"
          "    where organization.establishment_idempotency_key = p_establishment_idempotency_key;\n"
          "\n"
          "    if found then\n"
          "        return public.replay_veterinary_organization_establishment(\n"
          "            existing_organization, requested_digest\n"
          "        );\n"
          "    end if;\n")
SUBSCRIPTION_KEY_CHECK = ("    if exists (\n"
                          "        select 1\n"
                          "        from public.organization_subscriptions as subscription\n"
                          "        where subscription.establishment_idempotency_key = p_establishment_idempotency_key\n"
                          "    ) then\n"
                          "        raise exception 'Organization establishment key was already used with different facts'\n"
                          "            using errcode = '23505',\n"
                          "                  hint = 'ESTABLISHMENT_KEY_CONFLICT';\n"
                          "    end if;\n")
ON_CONFLICT = "    on conflict (establishment_idempotency_key) do nothing\n"
NAME_ANCHOR = ("    where organization.establishment_idempotency_key = p_establishment_idempotency_key;\n"
               "\n"
               "    if found then\n")
GRANT_INSERT_START = "    insert into public.organization_responsibility_grants (\n"
GRANT_INSERT = (GRANT_INSERT_START +
                "        membership_id,\n"
                "        responsibility,\n"
                "        scope_type,\n"
                "        clinic_id,\n"
                "        effective_start,\n"
                "        granted_by_user_id\n"
                "    )\n"
                "    values (\n"
                "        created_membership_id,\n"
                "        'OWNER',\n"
                "        'ORGANIZATION',\n"
                "        null,\n"
                "        establishment_instant,\n"
                "        p_owner_user_id\n"
                "    );\n")
SUBSCRIPTION_INSERT_START = "    insert into public.organization_subscriptions (\n"
REFERENCES_END = ("        from jsonb_array_elements(p_provider_references) as reference_payload;\n"
                  "    end if;\n"
                  "\n"
                  "    -- Surface the deferred invariants")
SURFACE_START = "    set constraints\n"
RETURN_ESTABLISHED = "    return jsonb_build_object(\n        'organization_id', created_organization_id,\n"
STATE_POLICY = ("    if p_initial_subscription_state not in ('PENDING', 'ACTIVE') then\n"
                "        raise exception 'A Subscription can only be established as PENDING or ACTIVE in Phase 1'\n"
                "            using errcode = '23514',\n"
                "                  hint = 'INITIAL_STATE_NOT_ALLOWED';\n"
                "    end if;\n")
FUTURE_POLICY = ("    if p_initial_state_effective_at > establishment_instant then\n"
                 "        raise exception 'A Subscription cannot be established with a future-dated initial state'\n"
                 "            using errcode = '23514',\n"
                 "                  hint = 'FUTURE_EFFECTIVE_AT';\n"
                 "    end if;\n")
DIGEST_UNTIL = "        'commercial_valid_until', extract(epoch from p_commercial_valid_until),\n"
DIGEST_SOURCE = "        'establishment_source', normalized_establishment_source,\n"
DIGEST_REFERENCES = ("        'establishment_source', normalized_establishment_source,\n"
                     "        'provider_references', public.canonical_subscription_provider_references(p_provider_references)\n")
DIGEST_EFFECTIVE = "        'initial_state_effective_at', extract(epoch from p_initial_state_effective_at),\n"
SUBSCRIPTION_ESTABLISHED_AT = ("        created_organization_id,\n"
                               "        establishment_instant,\n"
                               "        null,\n")
REPLAY_DIGEST = "    if p_organization.establishment_request_digest is distinct from p_requested_digest then\n"
REPLAY_OUTCOME = "        'outcome', 'ALREADY_ESTABLISHED'\n"
UNCONFIRMED = "    if owner_account.email_confirmed_at is null\n       or owner_account.deleted_at is not null\n"
DELETED = "       or owner_account.deleted_at is not null\n"
ANONYMOUS = "       or owner_account.is_anonymous is distinct from false\n"
BANNED = ("       or (owner_account.banned_until is not null\n"
          "           and owner_account.banned_until > p_instant) then\n")
LATER_REFERENCES = ("           or public.canonical_subscription_provider_references(p_provider_references)\n"
                    "               is distinct from public.stored_subscription_provider_references(existing_subscription_record.id) then\n")
KEY_IMMUTABLE = ("    if old.establishment_idempotency_key is distinct from new.establishment_idempotency_key\n"
                 "       or old.establishment_request_digest is distinct from new.establishment_request_digest then\n")


def establish_edits_partial_survives(base):
    """Transaction split: the Subscription and its references become a
    best-effort step whose failure no longer undoes the Organization."""
    start = base.index(SUBSCRIPTION_INSERT_START)
    end = base.index(REFERENCES_END) + len("        from jsonb_array_elements(p_provider_references) as reference_payload;\n"
                                           "    end if;\n")
    return base[:start] + "    begin\n" + base[start:end] + \
        "    exception when others then\n        null;\n    end;\n" + base[end:]


def without_surfacing(base):
    start = base.index(SURFACE_START)
    end = base.index(RETURN_ESTABLISHED)
    return base[:start] + base[end:]


# (name, [(function, edits [(before, after)])], expected assertion)
FAULTS = [
    ('Organization idempotency removed',
     [(ESTABLISH, [(LOOKUP, ''), (SUBSCRIPTION_KEY_CHECK, ''), (ON_CONFLICT, '')])],
     'EST:replay:exact_replay_returns_original_ids'),
    ('display name used as the anchor',
     [(ESTABLISH, [(NAME_ANCHOR, "    where organization.display_name = normalized_display_name;\n\n    if found then\n")])],
     'EST:multiple:duplicate_display_name_is_a_distinct_organization'),
    ('initial Subscription omitted',
     [(ESTABLISH, [(SUBSCRIPTION_INSERT_START, "    if false then\n" + SUBSCRIPTION_INSERT_START),
                   ("    returning id into created_subscription_id;\n", "    returning id into created_subscription_id;\n    end if;\n")])],
     'EST:footprint:exactly_one_organization_membership_grant_subscription'),
    ('OWNER Grant omitted (deferred invariant surfaced)',
     [(ESTABLISH, [(GRANT_INSERT, '')])],
     'EST:acl:service_role_establishes'),
    ('OWNER Grant omitted and invariants not surfaced',
     [(ESTABLISH, [(GRANT_INSERT, ''), ('__SURFACING__', '')])],
     'EST:footprint:exactly_one_organization_membership_grant_subscription'),
    ('Owner email verification removed',
     [(ELIGIBLE, [(UNCONFIRMED, "    if owner_account.deleted_at is not null\n")])],
     'EST:identity:unconfirmed_email_rejected'),
    ('deleted account accepted', [(ELIGIBLE, [(DELETED, '')])], 'EST:identity:deleted_account_rejected'),
    ('anonymous account accepted', [(ELIGIBLE, [(ANONYMOUS, '')])], 'EST:identity:anonymous_account_rejected'),
    ('banned account accepted', [(ELIGIBLE, [(BANNED, '       then\n')])], 'EST:identity:currently_banned_account_rejected'),
    ('ban ending at t still disqualifies',
     [(ELIGIBLE, [(BANNED, BANNED.replace('banned_until > p_instant', 'banned_until >= p_instant'))])],
     'EST:identity:ban_ending_at_t_accepted'),
    ('future initial effective time accepted', [(ESTABLISH, [(FUTURE_POLICY, '')])],
     'EST:policy:future_initial_effective_time_rejected'),
    ('invalid initial state accepted', [(ESTABLISH, [(STATE_POLICY, '')])],
     'EST:policy:invalid_initial_states_rejected'),
    ('fingerprint omits valid_until', [(ESTABLISH, [(DIGEST_UNTIL, '')])], 'EST:conflict:different_valid_until'),
    ('fingerprint ignores provider references',
     [(ESTABLISH, [(DIGEST_REFERENCES, DIGEST_SOURCE.rstrip(',\n') + '\n')])],
     'EST:conflict:provider_reference_removed'),
    ('fingerprint uses the resolved effective time',
     [(ESTABLISH, [(DIGEST_EFFECTIVE, "        'initial_state_effective_at', extract(epoch from coalesce(p_initial_state_effective_at, establishment_instant)),\n")])],
     'EST:replay:exact_replay_returns_original_ids'),
    ('contradictory replay accepted', [(REPLAY, [(REPLAY_DIGEST, '    if false then\n')])], 'EST:conflict:different_owner'),
    ('replay reports ESTABLISHED', [(REPLAY, [(REPLAY_OUTCOME, "        'outcome', 'ESTABLISHED'\n")])],
     'EST:replay:exact_replay_returns_original_ids'),
    ('key shared with a later-period Subscription not detected', [(ESTABLISH, [(SUBSCRIPTION_KEY_CHECK, '')])],
     'EST:conflict:key_used_by_later_period_subscription'),
    ('Subscription established at a later clock instant',
     [(ESTABLISH, [(SUBSCRIPTION_ESTABLISHED_AT, "        created_organization_id,\n        clock_timestamp(),\n        null,\n")])],
     'EST:temporal:subscription_established_at_t_and_omitted_effective_is_t'),
    ('transaction split: partial footprint survives', [(ESTABLISH, [('__PARTIAL__', '')])],
     'EST:atomicity:injected_failure_leaves_nothing:organization_subscriptions'),
    ('later-period replay ignores provider references', [(LATER, [(LATER_REFERENCES, '           then\n')])],
     'EST:later_period:contradictory_references_rejected'),
    ('establishment record mutable', [(IMMUTABILITY, [(KEY_IMMUTABLE, '    if false then\n')])],
     'EST:record:establishment_key_immutable'),
]
GRANT_FAULTS = [
    Fault('old create_veterinary_organization still service_role-executable',
          "create function public.create_veterinary_organization(p_display_name text)\n"
          "returns table (organization_id uuid, membership_id uuid) language sql security definer\n"
          "set search_path = '' as $f$ select null::uuid, null::uuid $f$;\n"
          "grant execute on function public.create_veterinary_organization(text) to service_role;\n",
          'EST:acl:former_boundary_removed'),
    Fault('establishment executable by authenticated',
          'grant execute on function public.establish_veterinary_organization('
          'uuid, text, uuid, text, timestamptz, timestamptz, timestamptz, text, jsonb) to authenticated;\n',
          'EST:acl:service_role_only'),
    Fault('private eligibility helper executable by service_role',
          'grant execute on function public.assert_initial_owner_eligible(uuid, timestamptz) to service_role;\n',
          'EST:acl:private_helpers_not_executable'),
]


def migration_function(source, name):
    match = re.search(r"^create (or replace )?function public\." + name + r"\(.*?^\$\$;\n", source, re.M | re.S)
    if not match:
        raise HarnessFailure(f'Function {name} not found in migration')
    return re.sub(r'^create (or replace )?function', 'create or replace function', match.group(0), count=1)


def edited(base, edits):
    for before, after in edits:
        if before == '__SURFACING__':
            base = without_surfacing(base)
        elif before == '__PARTIAL__':
            base = establish_edits_partial_survives(base)
        else:
            base = replace_once(base, before, after)
    return base


def main():
    migration = MIGRATION.read_text(encoding='utf-8')
    bases = {name: migration_function(migration, name)
             for name in (ESTABLISH, REPLAY, ELIGIBLE, LATER, IMMUTABILITY)}
    faults = []
    for name, changes, assertion in FAULTS:
        definitions = ''.join(edited(bases[function], edits) for function, edits in changes)
        faults.append(Fault(name, definitions, assertion))
    faults.extend(GRANT_FAULTS)

    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        client.faults(source, faults)
        client.suite(SUITE)
        client.verify_zero_fixtures(['d0320000-'])
    print(f'{len(faults)}/{len(faults)} trusted establishment mutants caught', flush=True)


if __name__ == '__main__':
    main()

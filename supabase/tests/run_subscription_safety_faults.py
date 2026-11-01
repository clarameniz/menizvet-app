"""Reproducible LOCAL-only Subscription Operational Safety mutation regression
(SPEC-SUB-002 §5/§14/§15, SPEC-SUB-003 §15, SPEC-SUB-004 BR-20, ADR-006;
SPEC-MED-010 BR-13 for new clinical content). The clinical mutants are built
from the deployed definitions (20261113090000 redefined them).

Run from repository root after a clean local reset. Each behavioural mutant
replaces one function (or one grant/view) inside a rollback-only suite
transaction and must be caught by its named assertion; infrastructure errors
never count. Session rollback/restoration and zero retained fixtures are
verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT, replace_once

SUBSCRIPTION_SUITE = ROOT / 'supabase/tests/subscription_operational_safety_spec_sub_002_003.sql'
AMENDMENT_SUITE = ROOT / 'supabase/tests/clinical_amendment_entitlement_continuity_spec_sub_004.sql'
SAFETY = ROOT / 'supabase/migrations/20261031090000_subscription_operational_safety.sql'
SUBSCRIPTIONS = ROOT / 'supabase/migrations/20260826113000_subscription_and_commercial_history.sql'
GUARDIAN_CANDIDATES = ROOT / 'supabase/migrations/20261017090000_guardian_candidate_grid_sub_minute_anchor.sql'

APPLY = 'apply_subscription_state_transition'
TRIGGER = 'enforce_subscription_state_transition_sequence'
GRAPH = 'subscription_transition_is_allowed'
STATUS = 'get_organization_subscription_status'
EDIT = 'edit_appointment_clinical_entry'
ENTITLEMENT = 'organization_has_professional_entitlement'
DERIVE = 'derive_organization_subscription_current_state'
ENTRY = 'create_appointment_clinical_entry'
DEPLOYED = {
    EDIT: 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)',
    ENTRY: 'public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)',
}
ESTABLISH = 'establish_organization_subscription'
CANDIDATES = 'get_requestable_appointment_start_times'

APPLY_TERMINAL = ("    if derived_current_state = 'EXPIRED' then\n"
                  "        raise exception 'An EXPIRED Subscription period is terminal; establish a new Subscription period instead'\n"
                  "            using errcode = '23514',\n"
                  "                  hint = 'SUBSCRIPTION_EXPIRED_TERMINAL';\n"
                  "    end if;\n")
TRIGGER_TERMINAL = ("    if derived_current_state = 'EXPIRED' then\n"
                    "        raise exception 'An EXPIRED Subscription period is terminal'\n"
                    "            using errcode = '23514',\n"
                    "                  hint = 'SUBSCRIPTION_EXPIRED_TERMINAL';\n"
                    "    end if;\n")
APPLY_FUTURE = ("    if p_effective_at > statement_timestamp() then\n"
                "        raise exception 'Future-dated Subscription transitions are not supported'\n"
                "            using errcode = '23514',\n"
                "                  hint = 'FUTURE_EFFECTIVE_AT';\n"
                "    end if;\n")
TRIGGER_FUTURE = APPLY_FUTURE.replace('p_effective_at', 'new.effective_at')
APPLY_STALE = ("    if p_effective_at <= derived_current_effective_at then\n"
               "        raise exception 'Subscription state transition effective time must be strictly later than the current accepted state'\n"
               "            using errcode = '23514',\n"
               "                  hint = 'STALE_EFFECTIVE_AT';\n"
               "    end if;\n")
TRIGGER_STALE = ("    if new.effective_at <= derived_current_effective_at then\n"
                 "        raise exception 'Subscription Transition effective time must be strictly later than the current accepted state'\n"
                 "            using errcode = '23514',\n"
                 "                  hint = 'STALE_EFFECTIVE_AT';\n"
                 "    end if;\n")
APPLY_SAME = ("    if normalized_to_state = derived_current_state then\n"
              "        raise exception 'Subscription state transition target must differ from the current accepted state'\n"
              "            using errcode = '23514',\n"
              "                  hint = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED';\n"
              "    end if;\n")
TRIGGER_SAME = ("    if new.to_state = derived_current_state then\n"
                "        raise exception 'Subscription Transition target must differ from the current accepted state'\n"
                "            using errcode = '23514',\n"
                "                  hint = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED';\n"
                "    end if;\n")
TRIGGER_GRAPH = "    if not public.subscription_transition_is_allowed(new.from_state, new.to_state) then\n"
GRAPH_BODY = "    select (p_from_state, p_to_state) in (\n"
GRAPH_LAST_EDGE = "        ('CANCELLED', 'EXPIRED')\n"
CANDIDATES_EMPTY = "    if not found then\n        return;\n    end if;\n"
GRAPH_PENDING_EXPIRED = "        ('PENDING', 'EXPIRED'),\n"
EST_STATE = ("    if normalized_initial_state not in ('PENDING', 'ACTIVE') then\n"
             "        raise exception 'A Subscription can only be established as PENDING or ACTIVE in Phase 1'\n"
             "            using errcode = '23514',\n"
             "                  hint = 'INITIAL_STATE_NOT_ALLOWED';\n"
             "    end if;\n")
EST_FUTURE = ("    if p_initial_state_effective_at > statement_timestamp() then\n"
              "        raise exception 'A Subscription cannot be established with a future-dated initial state'\n"
              "            using errcode = '23514',\n"
              "                  hint = 'FUTURE_EFFECTIVE_AT';\n"
              "    end if;\n")
EVENT_REPLAY_MATCH = "            if existing_transition_record.effective_at = p_effective_at\n"
STATUS_CHECK = ("       or not public.user_has_organization_capability(\n"
                "           acting_user_id, p_organization_id, 'ORGANIZATION_MANAGE_SUBSCRIPTION'\n"
                "       ) then")
STATUS_STATE = "        'state', derived.current_state,\n"
STATUS_RESULT = "        'subscription', status_subscription,\n"
EDIT_REQUEST = '    -- 5. The request.\n'
EDIT_ACTOR = ("    select * into actor\n"
              "    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');\n")
EDIT_REPLAY = "    if found then\n        if existing_version.change_kind = 'EDIT'\n"
OPEN_ENDED = "                and (current_valid_until is null or evaluation_time < current_valid_until)\n"
CASE_ACTIVE = "        when 'ACTIVE' then\n"
CANCELLED_BOUND = ("                current_valid_until is not null\n"
                   "                and evaluation_time < current_valid_until\n")
DERIVE_UNTIL = "            when latest_transition.id is not null then latest_transition.commercial_valid_until\n"
DERIVE_FROM = "            when latest_transition.id is not null then latest_transition.commercial_valid_from\n"
ENTRY_GATE = "    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then\n"

PUBLIC_VIEW_LEAK = """create or replace view public.published_clinic_public_profiles as
select clinic.id as clinic_id, profile.display_name, profile.description, profile.public_phone,
    profile.public_email, profile.website,
    (select derived.current_state from public.organization_subscriptions as subscription
     cross join lateral public.derive_organization_subscription_current_state(subscription.id) as derived
     where subscription.organization_id = clinic.organization_id
     order by (derived.current_state = 'EXPIRED') limit 1) as subscription_state
from public.clinics as clinic join public.clinic_public_profiles as profile on profile.clinic_id = clinic.id
where clinic.is_published = true;
"""

# (suite, name, function, edits [(before, after)], expected assertion)
FAULTS = [
    (SUBSCRIPTION_SUITE, 'arbitrary transition graph restored', GRAPH,
     [(GRAPH_BODY, "    select p_from_state <> p_to_state or (p_from_state, p_to_state) in (\n")],
     'Every forbidden transition is rejected without writing'),
    (SUBSCRIPTION_SUITE, 'PENDING -> EXPIRED closure removed', GRAPH, [(GRAPH_PENDING_EXPIRED, '')],
     'Every allowed transition succeeds: PENDING -> EXPIRED'),
    (SUBSCRIPTION_SUITE, 'PENDING -> CANCELLED allowed', GRAPH,
     [(GRAPH_PENDING_EXPIRED, GRAPH_PENDING_EXPIRED + "        ('PENDING', 'CANCELLED'),\n")],
     'Every forbidden transition is rejected without writing'),
    (SUBSCRIPTION_SUITE, 'candidate read distinguishes Entitlement loss', CANDIDATES,
     [(CANDIDATES_EMPTY, "    if not found then\n"
                         "        if exists (select 1 from public.clinics as lapsed where lapsed.id = p_clinic_id\n"
                         "            and lapsed.is_published and not public.organization_has_professional_entitlement(\n"
                         "                lapsed.organization_id, 'APPOINTMENT_MANAGEMENT')) then\n"
                         "            return query select '1970-01-01'::date, '00:00'::time, 0;\n"
                         "        end if;\n"
                         "        return;\n"
                         "    end if;\n")],
     'A lapsed published Clinic stays published and discoverable but offers no times'),
    (SUBSCRIPTION_SUITE, 'establishment accepts any initial state', ESTABLISH, [(EST_STATE, '')],
     'Establishment rejects PAST_DUE, CANCELLED and EXPIRED initial states'),
    (SUBSCRIPTION_SUITE, 'establishment accepts a future-dated initial state', ESTABLISH, [(EST_FUTURE, '')],
     'Establishment rejects a future-dated initial state'),
    (SUBSCRIPTION_SUITE, 'EXPIRED -> ACTIVE allowed', APPLY, [(APPLY_TERMINAL, '')], None),
    (SUBSCRIPTION_SUITE, 'future-dated transition allowed', APPLY, [(APPLY_FUTURE, '')], None),
    (SUBSCRIPTION_SUITE, 'same-state transition allowed', APPLY, [(APPLY_SAME, '')], None),
    (SUBSCRIPTION_SUITE, 'stale transition accepted', APPLY, [(APPLY_STALE, '')], None),
    (SUBSCRIPTION_SUITE, 'exact source-event replay rejected as contradictory', APPLY,
     [(EVENT_REPLAY_MATCH, "            if existing_transition_record.effective_at <> p_effective_at\n")],
     'The same source event reproduces the same accepted transition'),
    (SUBSCRIPTION_SUITE, 'insert trigger graph backstop removed', TRIGGER,
     [(TRIGGER_GRAPH, "    if false then\n")], 'The insert trigger enforces the Phase 1 graph'),
    (SUBSCRIPTION_SUITE, 'open-ended ACTIVE loses Entitlement', ENTITLEMENT,
     [(OPEN_ENDED, "                and (current_valid_until is not null and evaluation_time < current_valid_until)\n")],
     'Open-ended ACTIVE keeps every Entitlement'),
    (SUBSCRIPTION_SUITE, 'PAST_DUE keeps Entitlement', ENTITLEMENT,
     [(CASE_ACTIVE, "        when 'PAST_DUE' then\n            return true;\n" + CASE_ACTIVE)],
     'PAST_DUE grants no Entitlement'),
    (SUBSCRIPTION_SUITE, 'CANCELLED without validity end keeps Entitlement', ENTITLEMENT,
     [(CANCELLED_BOUND, "                (current_valid_until is null or evaluation_time < current_valid_until)\n")],
     'CANCELLED without validity end grants no Entitlement'),
    (SUBSCRIPTION_SUITE, 'omitted validity inherited', DERIVE,
     [(DERIVE_UNTIL, "            when latest_transition.id is not null then coalesce(latest_transition.commercial_valid_until, subscription.initial_commercial_valid_until)\n"),
      (DERIVE_FROM, "            when latest_transition.id is not null then coalesce(latest_transition.commercial_valid_from, subscription.initial_commercial_valid_from)\n")],
     'Omitted validity is not inherited'),
    (SUBSCRIPTION_SUITE, 'status read leaks an inaccessible Organization', STATUS,
     [(STATUS_CHECK, "       or not exists (select 1 from public.veterinary_organizations as any_organization\n"
                     "           where public.user_has_organization_capability(\n"
                     "               acting_user_id, any_organization.id, 'ORGANIZATION_MANAGE_SUBSCRIPTION')) then")],
     'Inaccessible and unknown Organizations fail identically'),
    (SUBSCRIPTION_SUITE, 'status read lacks the capability check', STATUS,
     [(STATUS_CHECK, "       or not exists (select 1 from public.organization_memberships as membership\n"
                     "           where membership.user_id = acting_user_id\n"
                     "             and membership.organization_id = p_organization_id\n"
                     "             and membership.effective_end is null) then")],
     'Only ORGANIZATION_MANAGE_SUBSCRIPTION holders read the status'),
    (SUBSCRIPTION_SUITE, 'status read leaks provider references', STATUS,
     [(STATUS_RESULT, STATUS_RESULT + "        'provider_references', (select jsonb_agg(reference.opaque_reference)\n"
                      "            from public.subscription_provider_references as reference\n"
                      "            join public.organization_subscriptions as owned on owned.id = reference.subscription_id\n"
                      "            where owned.organization_id = p_organization_id),\n")],
     'Status read exposes no provider or internal commercial data'),
    (SUBSCRIPTION_SUITE, 'status read infers EXPIRED for a lapsed ACTIVE', STATUS,
     [(STATUS_STATE, "        'state', case when derived.current_state = 'ACTIVE'\n"
                     "            and derived.current_commercial_valid_until <= statement_timestamp()\n"
                     "            then 'EXPIRED' else derived.current_state end,\n")],
     'Status reports stored state and Entitlement availability'),
    (AMENDMENT_SUITE, 'edit still blocked by Entitlement loss', EDIT,
     [(EDIT_REQUEST, ENTRY_GATE + "        raise exception 'Clinical care is currently unavailable for this Organization'\n"
                     "            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';\n    end if;\n"
                     + EDIT_REQUEST)],
     'An authorized author edits after Entitlement loss'),
    (AMENDMENT_SUITE, 'edit exception opens new Entries', ENTRY,
     [(ENTRY_GATE, '    if false then\n')], 'Lapse cannot record a new Entry (SPEC-MED-010 BR-13)'),
    (AMENDMENT_SUITE, 'Entitlement gate applies only to the first Entry', ENTRY,
     [(ENTRY_GATE, '    if not exists (select 1 from public.clinical_record_entries as earlier\n'
                   '                   where earlier.appointment_id = appointment_record.id)\n'
                   "       and not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then\n")],
     'Lapse cannot record a further Entry on an already documented Appointment (BR-13 supersedes SPEC-SUB-004 BR-17/BR-18)'),
    (AMENDMENT_SUITE, 'edit exception drops the Veterinarian context', EDIT,
     [(EDIT_ACTOR, "    select null::uuid as organization_id, null::uuid as organization_membership_id,\n"
                   "        null::uuid as organization_responsibility_grant_id, assignment.id as veterinarian_clinic_assignment_id\n"
                   "    into actor from public.veterinarian_clinic_assignments as assignment\n"
                   "    join public.veterinarian_professional_profiles as profile on profile.id = assignment.professional_profile_id\n"
                   "    where assignment.clinic_id = p_clinic_id and profile.user_id = acting_user_id\n"
                   "    order by assignment.effective_start desc limit 1;\n")],
     'Edit continuity still requires a current Veterinarian context'),
    (AMENDMENT_SUITE, 'edit idempotency broken', EDIT,
     [(EDIT_REPLAY, "    if false then\n        if existing_version.change_kind = 'EDIT'\n")],
     'Edit idempotency is unchanged after Entitlement loss'),
]
# Paired edits that span two functions (the trusted operation and its trigger
# backstop) are expressed as two definitions in one mutant.
PAIRED = {
    'EXPIRED -> ACTIVE allowed': ((TRIGGER, [(TRIGGER_TERMINAL, '')]),
                                  (GRAPH, [(GRAPH_LAST_EDGE, GRAPH_LAST_EDGE.rstrip('\n') + ",\n        ('EXPIRED', 'ACTIVE')\n")]),
                                  'EXPIRED is terminal'),
    'future-dated transition allowed': ((TRIGGER, [(TRIGGER_FUTURE, '')]), None, 'A future-dated transition is rejected'),
    'same-state transition allowed': ((TRIGGER, [(TRIGGER_SAME, '')]),
                                      (GRAPH, [(GRAPH_BODY, "    select p_from_state = p_to_state or (p_from_state, p_to_state) in (\n")]),
                                      'Same-state transitions are rejected'),
    'stale transition accepted': ((TRIGGER, [(TRIGGER_STALE, '')]), None, 'A stale or equal effective time is rejected'),
}
EXTRA_FAULTS = [
    (SUBSCRIPTION_SUITE, Fault('status read executable by anon',
        'grant execute on function public.get_organization_subscription_status(uuid) to anon;\n',
        'Status read is authenticated-only, STABLE, SECURITY DEFINER with an empty search_path')),
    (SUBSCRIPTION_SUITE, Fault('transitions executable by authenticated',
        'grant execute on function public.apply_subscription_state_transition(uuid, text, timestamptz, timestamptz, timestamptz, text, text) to authenticated;\n',
        'Transitions and establishment stay trusted; no client role can execute them')),
    (SUBSCRIPTION_SUITE, Fault('public Clinic read exposes commercial state', PUBLIC_VIEW_LEAK,
        'Public reads expose no commercial state')),
]


def migration_function(source, name):
    match = re.search(r"^create (or replace )?function public\." + name + r"\(.*?^\$\$;\n", source, re.M | re.S)
    if not match:
        raise HarnessFailure(f'Function {name} not found in migration')
    return re.sub(r'^create (or replace )?function', 'create or replace function', match.group(0), count=1)


def edited(base, edits):
    for before, after in edits:
        base = replace_once(base, before, after)
    return base


def main():
    client = LocalSql()
    safety = SAFETY.read_text(encoding='utf-8')
    subscriptions = SUBSCRIPTIONS.read_text(encoding='utf-8')
    bases = {name: migration_function(safety, name)
             for name in (APPLY, TRIGGER, GRAPH, STATUS, ESTABLISH)}
    bases.update({name: migration_function(subscriptions, name) for name in (ENTITLEMENT, DERIVE)})
    bases.update({name: client.definition(signature) for name, signature in DEPLOYED.items()})
    bases[CANDIDATES] = migration_function(GUARDIAN_CANDIDATES.read_text(encoding='utf-8'), CANDIDATES)

    by_suite = {SUBSCRIPTION_SUITE: [], AMENDMENT_SUITE: []}
    for suite, name, function, edits, assertion in FAULTS:
        definitions = edited(bases[function], edits)
        if name in PAIRED:
            (second_function, second_edits), third, assertion = PAIRED[name]
            definitions += edited(bases[second_function], second_edits)
            if third is not None:
                third_function, third_edits = third
                definitions += edited(bases[third_function], third_edits)
        by_suite[suite].append(Fault(name, definitions, assertion))
    for suite, fault in EXTRA_FAULTS:
        by_suite[suite].append(fault)

    total = 0
    with client.restored():
        for suite, faults in by_suite.items():
            source = client.suite(suite)
            client.faults(source, faults)
            client.suite(suite)
            total += len(faults)
        client.verify_zero_fixtures(['d0310000-', 'd0311000-'])
    print(f'{total}/{total} Subscription Operational Safety mutants caught', flush=True)


if __name__ == '__main__':
    main()

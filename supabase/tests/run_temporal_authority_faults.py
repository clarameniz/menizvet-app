"""Permanent LOCAL temporal-authority mutation regression, independent of Staff:
shared evaluators (temporal_professional_authority.sql) and lifecycle writers
(professional_authority_create_then_act.sql).
Run after local reset: python supabase/tests/run_temporal_authority_faults.py.
Exact named assertions, isolated rollback transactions, restoration verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(ROOT / "supabase/tests/temporal_professional_authority.sql")
        org = client.definition("public.user_has_organization_capability(uuid,uuid,text)")
        clinic = client.definition("public.user_has_organization_scoped_clinic_capability(uuid,uuid,text)")
        clinic_scoped = client.definition("public.user_has_clinic_scoped_clinic_capability(uuid,uuid,text)")
        context = client.definition("public.get_my_professional_context()")
        assignment = client.definition("public.veterinarian_clinic_assignment_is_current(uuid)")
        find = client.definition("public.find_current_veterinarian_context_after_lock(uuid,uuid,text,text)")
        resolve = client.definition("public.resolve_current_veterinarian_context_after_lock(uuid,uuid,text,text)")
        continuous = client.definition("public.user_has_continuous_clinic_reschedule_authority_since(uuid,uuid,timestamptz)")
        create_clinic = client.definition("public.create_clinic(uuid,uuid)")
        prefix = "TA:matrix:OWNER:ORGANIZATION:"
        faults = [
            Fault("Organization Membership start ignored", replace_once(org,
                "and membership.effective_start <= statement_timestamp()", "and true"), prefix + "membership_future:organization"),
            Fault("Organization Grant start ignored", replace_once(org,
                "and grant_record.effective_start <= statement_timestamp()", "and true"), prefix + "grant_future:organization"),
            Fault("Organization fixed but Clinic evaluator permissive", replace_once(replace_once(clinic,
                "and membership.effective_start <= statement_timestamp()", "and true"),
                "and responsibility_grant.effective_start <= statement_timestamp()", "and true"), prefix + "membership_future:clinic_org"),
        ]
        org_call = """public.user_has_organization_capability(
                    acting_user_id, current_membership.organization_id, catalog_entry.capability
                )"""
        legacy_org = """exists (select 1 from public.organization_memberships m
            join public.organization_responsibility_grants g on g.membership_id=m.id
            where m.user_id=acting_user_id and m.organization_id=current_membership.organization_id
            and m.effective_end is null and g.effective_end is null
            and g.scope_type='ORGANIZATION' and g.responsibility in ('OWNER','ADMINISTRATOR'))"""
        faults.append(Fault("Context exposes future Organization capability",
            replace_once(context,org_call,"("+org_call+" or "+legacy_org+")"),prefix+"grant_future:context_organization"))
        clinic_call = """public.user_has_organization_scoped_clinic_capability(
                    acting_user_id, current_membership.organization_id, catalog_entry.capability
                )"""
        legacy_clinic = """exists (select 1 from public.organization_memberships m
            join public.organization_responsibility_grants g on g.membership_id=m.id
            where m.user_id=acting_user_id and m.organization_id=current_membership.organization_id
            and m.effective_end is null and g.effective_end is null
            and g.scope_type='ORGANIZATION' and g.responsibility in ('OWNER','ADMINISTRATOR','RECEPTIONIST')
            and catalog_entry.capability='APPOINTMENT_VIEW_SCHEDULE')"""
        faults.append(Fault("Context exposes future Clinic capability",
            replace_once(context,clinic_call,"("+clinic_call+" or "+legacy_clinic+")"),prefix+"grant_future:context_clinic"))
        # The idempotent create_clinic (SPEC-CLI-001 §10) checks before and
        # under the Organization lock; the mutant disables both.
        guard = """if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_CREATE_CLINICS'
    ) then"""
        locked_guard = """if not found or not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_CREATE_CLINICS'
    ) then"""
        faults.append(Fault("Existing create_clinic authorizes future actor",
            replace_once(replace_once(create_clinic,locked_guard,"if not found then"),"    "+guard,"    if false then"),
            "TA:write:create_clinic:membership_future","expect_denied"))
        faults.append(Fault("Future recorded end incorrectly grants authority",
            replace_once(org,"and membership.effective_end is null",
                         "and (membership.effective_end is null or membership.effective_end > statement_timestamp())"),
            prefix+"membership_end_future:organization"))
        faults.append(Fault("Veterinarian Assignment ignores future Membership",
            replace_once(assignment,"and membership.effective_start <= statement_timestamp()","and true"),
            "TA:matrix:VETERINARIAN:ORGANIZATION:membership_future:assignment_membership"))
        current_gate = """public.user_has_clinic_capability(
        p_user_id, p_clinic_id, 'APPOINTMENT_RESCHEDULE'
    )"""
        faults.append(Fault("Historical continuity bypasses current authority",
            replace_once(continuous,current_gate,"true"),"TA:continuous_future_actor"))
        faults.append(Fault("Finder chooses future Veterinarian Grant through current Administrator capability",
            replace_once(find,"and responsibility_grant.effective_start <= statement_timestamp()","and true"),
            "TA:mixed_future_veterinarian_find"))
        faults.append(Fault("Resolver chooses future Veterinarian Grant through current Administrator capability",
            replace_once(resolve,"and responsibility_grant.effective_start <= statement_timestamp()","and true"),
            "TA:mixed_future_veterinarian_resolve","expect_denied"))
        # Clinic-scoped branch only (the Veterinarian branch is indented deeper).
        faults.append(Fault("Clinic-scoped evaluator allows future authority",
            replace_once(replace_once(clinic_scoped,
                "\n                  and membership.effective_start <= statement_timestamp()", ""),
                "\n                  and responsibility_grant.effective_start <= statement_timestamp()", ""),
            "TA:matrix:ADMINISTRATOR:CLINIC:membership_future:clinic_scoped"))
        faults.append(Fault("Professional Context Membership CTE omits start",
            replace_once(context,"""where membership.user_id = acting_user_id
          and membership.effective_start <= statement_timestamp()""","where membership.user_id = acting_user_id"),
            prefix+"membership_future:context_membership"))
        faults.append(Fault("Professional Context Grant CTE omits start",
            replace_once(context,"where responsibility_grant.effective_start <= statement_timestamp()","where true"),
            prefix+"grant_future:context_grant"))
        client.faults(source,faults)
        client.suite(ROOT / "supabase/tests/temporal_professional_authority.sql")

        # Lifecycle writers must record the statement instant used for
        # evaluation (create-then-act) and never precede superseded starts.
        cta = client.suite(ROOT / "supabase/tests/professional_authority_create_then_act.sql")
        establish = client.definition("public.establish_veterinary_organization("
            "uuid,text,uuid,text,timestamptz,timestamptz,timestamptz,text,jsonb)")
        accept = client.definition("public.accept_organization_invitation(uuid,uuid,bytea)")
        add = client.definition("public.add_organization_responsibility(uuid,text,text,uuid)")
        replace = client.definition("public.replace_organization_responsibility(uuid,text,text,uuid)")
        replace_instant = """greatest(
        statement_timestamp(),
        membership_record.effective_start,
        grant_record.effective_start
    )"""
        writer_faults = [
            Fault("Establishment stamps a later clock instant",
                replace_once(establish,"establishment_instant constant timestamptz := statement_timestamp();",
                    "establishment_instant constant timestamptz := clock_timestamp();"),
                "CTA:provision:owner_current_in_same_statement"),
            Fault("Acceptance stamps a later clock instant",
                replace_once(accept,"greatest(statement_timestamp(), invitation_record.created_at)","clock_timestamp()"),
                "CTA:accept:accepted_capability_current_in_same_statement"),
            Fault("Added Grant stamps a later clock instant",
                replace_once(add,"greatest(statement_timestamp(), membership_record.effective_start)","clock_timestamp()"),
                "CTA:provision:added_grant_current_in_same_statement"),
            Fault("Replacement stamps a later clock instant",
                replace_once(replace,replace_instant,"clock_timestamp()"),
                "CTA:replace:replacement_current_in_same_statement"),
            Fault("Replacement precedes the superseded Grant start",
                replace_once(replace,replace_instant,"statement_timestamp()"),
                "CTA:monotonic:replacement_never_precedes_superseded_grant"),
        ]
        client.faults(cta,writer_faults)
        client.suite(ROOT / "supabase/tests/professional_authority_create_then_act.sql")
        client.verify_zero_fixtures(["d0260000-","d0090000-","d0270000-"])


if __name__ == "__main__":
    main()

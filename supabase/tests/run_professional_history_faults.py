"""Reproducible LOCAL-only mutation regression for Professional Longitudinal /
Cross-Clinic Medical History (SPEC-MED-005 §15/§16 as amended by SPEC-MED-010
BR-14/BR-15/BR-22, SPEC-ID-006 BR-41). Mutants are built from the deployed
definitions (20261113090000 redefined every function under test).

Run from the repository root after a clean local reset. Each behavioural
mutant replaces one function (or one grant) inside the rollback-only suite
transaction and must be caught by its named assertion; infrastructure errors
never count. Session rollback/restoration and zero retained fixtures are
verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/professional_medical_history_spec_med_005.sql'

READ = 'view_appointment_professional_medical_history'
PAGE = 'clinical_history_page'
NAME = 'clinical_provenance_display_name'
WINDOW = 'appointment_professional_history_accessible'
GUARDIAN = 'view_guardian_pet_medical_history'
SIGNATURES = {
    READ: 'public.view_appointment_professional_medical_history(uuid, uuid, integer, timestamptz, uuid)',
    PAGE: 'public.clinical_history_page(uuid, integer, timestamptz, uuid)',
    NAME: 'public.clinical_provenance_display_name(uuid)',
    WINDOW: 'public.appointment_professional_history_accessible(uuid, timestamptz)',
    GUARDIAN: 'public.view_guardian_pet_medical_history(uuid, integer, timestamptz, uuid)',
}

UNIFORM = ('HIST authority: wrong Clinic, wrong Organization, unknown and foreign targets are '
           'indistinguishable from no authority')
CONTENT = ('HIST content: every recorded Entry of the Pet from every Clinic and Organization, '
           'newest clinical occurrence first')
WINDOW_OPEN = ('HIST window: REQUESTED (future start) and CONFIRMED with an ACTIVE authorization are permitted, '
               'documented or not; a passed REQUESTED start is not')
WINDOW_COMPLETED = ('HIST window: a COMPLETED Appointment is denied, although its assigned Veterinarian may still '
                    'document it')
ORDERING = ('HIST ordering: the clinical event time, else the recording time, drives chronology (SPEC-MED-010 '
            'BR-22); recording is publication')
PAYLOAD_KEYS = 'HIST payload: exactly the allowed keys'
PAYLOAD_IDS = ('HIST payload: no User, Membership, Assignment, Care Authorization, Encounter, Clinic, '
               'Organization or Appointment identifier')
AMENDMENTS_SHOWN = ('HIST amendments: the original stays unchanged and its Amendments follow oldest first, '
                    'each with its own author')
EDIT_SHOWN = ('HIST pagination: an edit between pages never duplicates or moves its Entry; the current version is '
              'shown and the original is kept')
GUARDIAN_CONTENT = ('HIST guardian: content, Amendments, Clinic / Organization names and Attachments are unchanged; '
                    'another Pet stays hidden')
OFFBOARDED = 'HIST provenance: an offboarded author keeps her name; an Entry is published by its own author (no finalizer)'
AUDIT_ONE = 'HIST audit: one PERMITTED event per page, with the current access context, never one per Entry'
GUARDIAN_KEYS = 'HIST guardian: the same Entries in the same order, carrying exactly the allowed keys'
GUARDIAN_PRIVATE = 'HIST guardian: no internal identifier and no Veterinarian name reaches the Guardian'
CONTRACT = 'HIST contract: the read is SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only, one signature'

AUTHORITY_STEP = '    -- 3. Authority before any target: the current exact-Clinic Veterinarian\n'
WINDOW_STEP = '    -- 6. The history window; any refusal is one audited, uniform denial.\n'
ENTITLEMENT = ("    authorized := actor_found\n"
               "        and public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE');\n")
APPOINTMENT_IN_CLINIC = ('          and appointment.clinic_id = p_clinic_id\n'
                         '        for share;\n')
PAGE_CTE = ('        select *\n'
            '        from public.clinical_history_page(\n'
            '            appointment_record.pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id\n'
            '        )\n')
AUTHOR_NAME = "                   'display_name', public.clinical_provenance_display_name(visible.created_by_user_id),\n"
AMENDMENT_AUTHOR = ("                           'display_name', public.clinical_provenance_display_name("
                    "amendment.amending_user_id),\n")
AMENDMENT_SOURCE = '                   from public.clinical_history_amendments(visible.entry_id) as amendment\n'
ENTRY_ID = "               'entry_id', visible.entry_id,\n"
AUDIT_STEP = '    -- 8. One meaningful protected access per page, before release, with the\n'
PERMITTED_RETURN = "    return jsonb_build_object(\n        'status', 'PERMITTED',\n        'entries', entries_payload,\n"
DENIED_OUTCOME = "            p_outcome => 'DENIED',\n"

PAGE_PET = '    where appointment.pet_id = p_pet_id\n'
PAGE_ORDER_VALUE = ('           coalesce(record_entry.clinical_event_at, record_entry.created_at),\n'
                    '           current_version.category,\n')
PAGE_CURRENT = ('           current_version.category,\n'
                '           current_version.other_category_context,\n'
                '           current_version.clinical_content,\n')
PREVIOUS_VERSIONS = "               'previous_versions', public.clinical_entry_previous_versions(visible.entry_id),\n"
PAGE_KEYSET = ('           or (coalesce(record_entry.clinical_event_at, record_entry.created_at), record_entry.id)\n'
               '              < (p_before_history_order_at, p_before_entry_id))\n')

WINDOW_ACTIVE = "        select care_auth.lifecycle_state = 'ACTIVE'\n"
WINDOW_PRE_CARE = '               and public.appointment_permits_pre_care_access(appointment.id, p_reference_time)\n'
READ_WINDOW = '       or not public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp()) then\n'

NAME_SOURCE = '    where profile.user_id = p_user_id\n'
GUARDIAN_ENTRY_ID = "               'id', visible.entry_id,\n"

EXISTENCE_FIRST = """    if not exists (select 1 from public.appointments as leaked where leaked.id = p_appointment_id) then
        raise exception 'Appointment does not exist' using errcode = '23503';
    end if;
"""
PET_ORACLE = """    if not exists (select 1 from public.appointments as leaked
                   join public.pets as leaked_pet on leaked_pet.id = leaked.pet_id
                   where leaked.id = p_appointment_id) then
        return jsonb_build_object('status', 'DENIED', 'reason', 'UNKNOWN_PET');
    end if;
"""
ASSIGNMENT_REQUIRED = """    if not exists (select 1 from public.appointment_veterinarian_assignments as required
                   where required.appointment_id = appointment_record.id and required.effective_end is null) then
        authorized := false;
    end if;
"""
DOCUMENTATION_OPENS_HISTORY = """       or not (public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp())
               or exists (select 1 from public.appointment_veterinarian_assignments as own_period
                          where own_period.appointment_id = appointment_record.id
                            and own_period.effective_end is null
                            and own_period.veterinarian_clinic_assignment_id = actor.veterinarian_clinic_assignment_id)) then
"""
ENTRY_REQUIRED = """       or not (public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp())
               and exists (select 1 from public.clinical_record_entries as required
                           where required.appointment_id = appointment_record.id)) then
"""
AVAILABILITY_REQUIRED = """    if not exists (select 1 from public.veterinarian_availability_periods as required
                   where required.veterinarian_clinic_assignment_id = actor.veterinarian_clinic_assignment_id) then
        authorized := false;
    end if;
"""
CLINIC_FILTER = """        select page_row.*
        from public.clinical_history_page(
            appointment_record.pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id
        ) as page_row
        join public.clinical_record_entries as filtered_entry on filtered_entry.id = page_row.entry_id
        join public.appointments as filtered_appointment on filtered_appointment.id = filtered_entry.appointment_id
        where filtered_appointment.clinic_id = p_clinic_id
"""
ORGANIZATION_FILTER = """        select page_row.*
        from public.clinical_history_page(
            appointment_record.pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id
        ) as page_row
        join public.clinical_record_entries as filtered_entry on filtered_entry.id = page_row.entry_id
        join public.appointments as filtered_appointment on filtered_appointment.id = filtered_entry.appointment_id
        join public.clinics as filtered_clinic on filtered_clinic.id = filtered_appointment.clinic_id
        where filtered_clinic.organization_id = actor.organization_id
"""
HIDDEN_ORIGINAL = """      and not exists (select 1 from public.clinical_amendments as hidden
                      where hidden.original_clinical_record_entry_id = record_entry.id)
"""
NAME_CURRENT_MEMBERSHIP = """    where profile.user_id = p_user_id
      and exists (select 1 from public.organization_memberships as current_membership
                  where current_membership.user_id = p_user_id and current_membership.effective_end is null)
"""
PER_ENTRY_AUDIT = """    perform public.establish_medical_access_audit_event(
        p_acting_user_id => acting_user_id, p_pet_id => appointment_record.pet_id,
        p_operation => 'VIEW_PET_MEDICAL_HISTORY', p_outcome => 'PERMITTED',
        p_actor_context => 'PROFESSIONAL_CLINICAL', p_protected_resource_scope => 'LONGITUDINAL_MEDICAL_HISTORY',
        p_occurred_at => clock_timestamp(), p_care_authorization_id => care_auth_record.id,
        p_accessing_clinic_id => p_clinic_id, p_accessing_organization_id => actor.organization_id,
        p_appointment_id => appointment_record.id)
    from jsonb_array_elements(entries_payload) as per_entry;
"""
USER_ID_LEAK = ENTRY_ID + "               'author_user_id', visible.created_by_user_id,\n"
ASSIGNMENT_LEAK = ENTRY_ID + """               'creator_veterinarian_clinic_assignment_id', (
                   select leaked.creator_veterinarian_clinic_assignment_id
                   from public.clinical_record_entries as leaked where leaked.id = visible.entry_id),
"""
GUARDIAN_ID_LEAK = GUARDIAN_ENTRY_ID + "               'created_by_user_id', visible.created_by_user_id,\n"
GUARDIAN_NAME_LEAK = GUARDIAN_ENTRY_ID + ("               'author_display_name', "
                                          "public.clinical_provenance_display_name(visible.created_by_user_id),\n")

# (name, function, [(before, after)], expected assertion)
FAULTS = [
    ('Appointment existence checked before authority', READ,
     [(AUTHORITY_STEP, EXISTENCE_FIRST + AUTHORITY_STEP)], UNIFORM),
    ('Pet existence oracle (distinct denial for an unknown target)', READ,
     [(AUTHORITY_STEP, PET_ORACLE + AUTHORITY_STEP)], UNIFORM),
    ('Care Authorization widened across Clinics (Appointment of any Clinic)', READ,
     [(APPOINTMENT_IN_CLINIC, '        for share;\n')], UNIFORM),
    ('current-Clinic filter on content', READ, [(PAGE_CTE, CLINIC_FILTER)], CONTENT),
    ('current-Organization filter on content', READ, [(PAGE_CTE, ORGANIZATION_FILTER)], CONTENT),
    ('REVOKED Care Authorization allowed', WINDOW,
     [(WINDOW_ACTIVE, "        select care_auth.lifecycle_state in ('ACTIVE', 'REVOKED')\n")],
     "HIST window: revocation denies history immediately; documentation access to the Appointment's own record stays"),
    ('ENDED Care Authorization allowed', WINDOW,
     [(WINDOW_ACTIVE, "        select care_auth.lifecycle_state in ('ACTIVE', 'ENDED')\n")],
     'HIST window: an ENDED Care Authorization is denied, for a cancelled and for a still CONFIRMED Appointment'),
    ('documentation access opens prior history (BR-15)', READ, [(READ_WINDOW, DOCUMENTATION_OPENS_HISTORY)],
     WINDOW_COMPLETED),
    ('prior history requires an existing Entry', READ, [(READ_WINDOW, ENTRY_REQUIRED)], WINDOW_OPEN),
    # Since M3 a COMPLETED Appointment never keeps an ACTIVE authorization, so the
    # fault is opening history through it whatever its authorization state.
    ('COMPLETED Appointment allowed', WINDOW,
     [(WINDOW_ACTIVE + WINDOW_PRE_CARE,
       "        select appointment.lifecycle_state = 'COMPLETED'\n"
       "               or (care_auth.lifecycle_state = 'ACTIVE'\n"
       '                   and public.appointment_permits_pre_care_access(appointment.id, p_reference_time))\n')],
     WINDOW_COMPLETED),
    ('pre-care window ignores the requested start', WINDOW,
     [(WINDOW_PRE_CARE, "               and appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED')\n")],
     WINDOW_OPEN),
    ('Entitlement omitted', READ, [(ENTITLEMENT, '    authorized := actor_found;\n')],
     'HIST lapse: Entitlement loss denies history, also through a documented Appointment, while its own record and '
     'Guardian history stay'),
    ('CLINICAL_DOCUMENTATION used instead of CLINICAL_CARE', READ,
     [("    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_CARE');\n",
       "    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');\n")],
     CONTRACT),
    ('Appointment Veterinarian Assignment required', READ,
     [(WINDOW_STEP, ASSIGNMENT_REQUIRED + WINDOW_STEP)], WINDOW_OPEN),
    ('Veterinarian Availability required', READ,
     [(WINDOW_STEP, AVAILABILITY_REQUIRED + WINDOW_STEP)], WINDOW_OPEN),
    ('User id leaked', READ, [(ENTRY_ID, USER_ID_LEAK)], PAYLOAD_KEYS),
    ('Clinic Assignment id leaked', READ, [(ENTRY_ID, ASSIGNMENT_LEAK)], PAYLOAD_KEYS),
    ("offboarded author's name disappears", NAME, [(NAME_SOURCE, NAME_CURRENT_MEMBERSHIP)], OFFBOARDED),
    ('reader substituted for author', READ,
     [(AUTHOR_NAME, "                   'display_name', public.clinical_provenance_display_name("
                    "acting_user_id),\n")], OFFBOARDED),
    ('wrong Veterinarian resolved for an Amendment (the Entry author)', READ,
     [(AMENDMENT_AUTHOR, "                           'display_name', public.clinical_provenance_display_name("
                         "visible.created_by_user_id),\n")], AMENDMENTS_SHOWN),
    ('Amendments omitted', READ,
     [(AMENDMENT_SOURCE, AMENDMENT_SOURCE + '                   where false\n')], PAYLOAD_KEYS),
    ('original hidden after correction', PAGE, [(PAGE_PET, PAGE_PET + HIDDEN_ORIGINAL)], CONTENT),
    ('history ordered by recording time only', PAGE,
     [(PAGE_ORDER_VALUE, '           record_entry.created_at,\n           current_version.category,\n')], ORDERING),
    # SPEC-MED-010 BR-22 (M5): every read presents the current version with its history.
    ('history shows the original instead of the current version', PAGE,
     [(PAGE_CURRENT, '           record_entry.category,\n'
                     '           record_entry.other_category_context,\n'
                     '           record_entry.clinical_content,\n')], EDIT_SHOWN),
    ('earlier versions omitted from the professional history', READ,
     [(PREVIOUS_VERSIONS, "               'previous_versions', '[]'::jsonb,\n")], EDIT_SHOWN),
    ('earlier versions omitted from the Guardian history', GUARDIAN,
     [(PREVIOUS_VERSIONS, "               'previous_versions', '[]'::jsonb,\n")], GUARDIAN_CONTENT),
    ('Entries of COMPLETED Appointments dropped from history', PAGE,
     [(PAGE_PET, PAGE_PET + "      and appointment.lifecycle_state <> 'COMPLETED'\n")], CONTENT),
    ('another Pet leaked into history', PAGE,
     [(PAGE_PET, '    where appointment.pet_id is not null\n')], CONTENT),
    ('cursor ignored (pages repeat)', PAGE, [(PAGE_KEYSET, '           or true)\n')],
     'HIST pagination: keyset pages neither duplicate nor skip, and the last page has no cursor'),
    ('audit removed', READ,
     [(AUDIT_STEP, '    if false then\n'), (PERMITTED_RETURN, '    end if;\n' + PERMITTED_RETURN)], AUDIT_ONE),
    ('audit per Entry', READ, [(AUDIT_STEP, PER_ENTRY_AUDIT + AUDIT_STEP)], AUDIT_ONE),
    ('denial recorded as permitted', READ, [(DENIED_OUTCOME, "            p_outcome => 'PERMITTED',\n")],
     'HIST audit: a closed window is audited DENIED with the professional context'),
    ('Guardian internal User id remains', GUARDIAN, [(GUARDIAN_ENTRY_ID, GUARDIAN_ID_LEAK)], GUARDIAN_KEYS),
    ('Guardian receives a Veterinarian name', GUARDIAN, [(GUARDIAN_ENTRY_ID, GUARDIAN_NAME_LEAK)], GUARDIAN_KEYS),
]

EXTRA = [
    Fault('history read executable by anon',
          'grant execute on function public.view_appointment_professional_medical_history'
          '(uuid, uuid, integer, timestamptz, uuid) to anon;\n', CONTRACT),
    Fault('history window predicate executable by authenticated',
          'grant execute on function public.appointment_professional_history_accessible(uuid, timestamptz) '
          'to authenticated;\n',
          'HIST contract: the shared projection, display-name and window helpers are private'),
    Fault('legacy Pet-keyed read reappears',
          "create function public.view_professional_pet_medical_history(p_pet_id uuid, p_clinic_id uuid,\n"
          "    p_care_authorization_id uuid, p_clinical_encounter_id uuid, p_limit integer default 50,\n"
          "    p_before_history_order_at timestamptz default null, p_before_entry_id uuid default null) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n",
          'HIST contract: the legacy Pet-keyed read no longer exists (SPEC-MED-010 BR-25); the Guardian read stays; '
          'its old chain is gone'),
]


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        bases = {name: client.definition(signature) for name, signature in SIGNATURES.items()}
        candidates = []
        for name, function, edits, assertion in FAULTS:
            candidate = bases[function]
            for before, after in edits:
                candidate = replace_once(candidate, before, after)
            candidates.append(Fault(name, candidate, assertion))
        candidates.extend(EXTRA)
        client.faults(source, candidates)
        client.suite(SUITE)
        print(f'{len(candidates)}/{len(candidates)} professional history mutation assertions observed', flush=True)
        client.verify_zero_fixtures(['d0360000-'])


if __name__ == '__main__':
    main()

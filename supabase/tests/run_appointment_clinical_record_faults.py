"""Reproducible LOCAL-only mutation regression for appointment-owned clinical
documentation (SPEC-MED-010 §12, BR-18/BR-23b editing, SPEC-APT-012 BR-48). Replaces run_clinical_record_faults.py, whose Encounter, Draft and
finalization mutants no longer have a subject (ADR-011).

Run from the repository root after a clean local reset. Each behavioural
mutant replaces one deployed function (or one grant, trigger or constraint)
inside the rollback-only suite transaction and must be caught by its named
assertion; infrastructure errors never count. Session rollback/restoration and
zero retained fixtures are verified.
"""
import re
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT

SUITE = ROOT / 'supabase/tests/appointment_clinical_record_spec_med_010.sql'

SIGNATURES = {
    'ENTRY': 'public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)',
    'FIELDS': 'public.assert_clinical_entry_fields(text, text, text, timestamptz)',
    'INTEGRITY': 'public.enforce_clinical_record_entry_integrity()',
    'READ': 'public.view_appointment_clinical_record(uuid, uuid)',
    'EDIT': 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)',
    'AMD_INTEGRITY': 'public.enforce_clinical_amendment_integrity()',
    'ATT_INTEGRITY': 'public.enforce_clinical_attachment_integrity()',
    'ACCEPTS': 'public.appointment_accepts_veterinarian_assignment(uuid, text)',
    'HISTORY_ACCESS': 'public.appointment_professional_history_accessible(uuid, timestamptz)',
    'HISTORY_PAGE': 'public.clinical_history_page(uuid, integer, timestamptz, uuid)',
    'PROF_HISTORY': 'public.view_appointment_professional_medical_history(uuid, uuid, integer, timestamptz, uuid)',
    'CANCEL': 'public.cancel_appointment(uuid, text, text, integer)',
    'NO_SHOW': 'public.mark_appointment_no_show(uuid, integer)',
    'INVALIDATION': 'public.enforce_reschedule_proposal_invalidation()',
    'SCHEDULE': 'public.get_clinic_appointment_schedule(uuid)',
}

# Assertion messages of the suite, as raised (doubled quotes undone).
A_CONTRACT = 'Contract: record, read and edit are SECURITY DEFINER, empty search_path, authenticated-only'
A_RECORD_SIGNATURE = ('Contract: one record operation returning jsonb, without defaults; it accepts no clinical time '
                      '(BR-5)')
A_PRIVATE = 'Contract: private helpers and trusted writers are not client-executable'
A_N21 = ('Note 21: every retired Encounter, Draft and Finalize operation, the Encounter-keyed reads, the timed record '
         'operation and the reason-and-addition operations are gone; the active-authorization list is no client path')
A_N1 = 'Note 1: Entries reference their Appointment (NOT NULL); no Encounter, Draft, finalization or contributor fact remains'
A_REC = ('Notes 1/BR-5/BR-6a: the assigned Veterinarian records a CONFIRMED Appointment after its start; authorship, '
         'trimmed content and the server recording time, with no event time, are stored; the result carries only outcome '
         'and entry_id')
A_BR8 = ('BR-8/BR-21: recording changes no Appointment, schedule, Lifecycle, Care Authorization or assignment fact and '
         'creates no audit event')
A_N6 = ('Note 6: missing category or content, invalid OTHER combinations and a missing key are rejected with stable '
        'hints; no clinical time can be sent; nothing is written')
A_N7 = ('Note 7: an exact replay returns ALREADY_CREATED with the same entry; different facts or another Appointment are '
        'KEY_CONFLICT; nothing is written')
A_N2 = ('Note 2: REQUESTED, CANCELLED, NO_SHOW, EXPIRED and never-confirmed Appointments are APPOINTMENT_STATE_INVALID '
        'even with an assignment')
A_DIRECT = ('Notes 2/8: a direct insertion outside the operation is rejected for undocumentable Appointments, for a '
            'non-assignee or an unassigned Appointment, and for a Clinic Assignment of another User or Clinic')
A_N3 = "Note 3: an Entry's Appointment cannot change and the Entry cannot be updated or deleted"
A_N8 = ('Note 8: another Veterinarian of the Clinic is NOT_ASSIGNED_VETERINARIAN; an unassigned Appointment is '
        'NO_VETERINARIAN_ASSIGNED')
A_N9 = ('Note 9: Administrator, Receptionist, Guardian, other-Organization and other-Clinic Veterinarians, foreign or '
        'unknown Appointments and unknown Clinics receive one uniform 42501 before any validation; unauthenticated is 28000')
A_N24 = ("Note 24: after a reassignment the former assignee's exact replay returns ALREADY_CREATED, while a new key is "
         'NOT_ASSIGNED_VETERINARIAN')
A_N19_23 = ("Notes 19/23: the new assignee records its own Entry and cannot edit the former assignee's; the original "
            'author still edits after reassignment; authorship is unchanged')
A_N18 = ('Note 18/BR-20: the read lists every Entry oldest first with its current version, mine/another authorship and '
         'may_edit = recorded_by_me, and carries no User, Clinic Assignment, Care Authorization identifier or Veterinarian '
         'name')
A_N17_EMPTY = 'Note 17: a read of an Appointment without Entries returns no medical information and creates no audit event'
A_N17_ONE = 'Note 17: a permitted read with three Entries creates exactly one typed VIEW_APPOINTMENT_CLINICAL_RECORD event'
A_N17_DENIED = ('Note 17: Receptionist, Administrator and other-Clinic reads of a documented Appointment are uniform DENIED '
                'with one DENIED event each; a foreign Appointment named under the wrong Clinic is DENIED without audit')
A_BR20 = ('BR-20: the advisory documentation state reports APPOINTMENT_STATE, NOT_ASSIGNED_VETERINARIAN or can_record, '
          'also on a COMPLETED Appointment')
A_AMD_AUTH = ('Notes 9/19: a non-author Veterinarian is ENTRY_AUTHOR_REQUIRED; non-Veterinarians, other Organizations, an '
              'Entry of another Appointment, an unknown Entry, and another Clinic are the uniform 42501')
A_EDIT = ('Note 19: the author edits; normalization, replay, KEY_CONFLICT, STALE_VERSION and field rules apply, and '
          'the recorded Entry is unchanged')
A_AMD_STRUCT = 'Note 19: structurally, only the author adds the next version and versions are append-only'
A_N11 = ("Notes 11/BR-12: Guardian revocation before any record does not prevent recording, editing or reading the "
         "Appointment's own record, and documenting never restores the authorization")
A_N12 = ('Note 12: prior history opens through ACTIVE CONFIRMED or future REQUESTED Appointments for any Veterinarian of '
         'the Clinic, assigned or not, and is denied after revocation, after completion, for terminal Appointments, to '
         'non-Veterinarians and across Clinics, although documentation access persists there')
A_N15 = 'Notes 15/16: with an Entry, Clinic and Guardian cancellation and NO_SHOW are rejected'
A_N14 = ('Note 14: the first Entry voids a pending Reschedule Proposal with CLINICAL_DOCUMENTATION_STARTED in the same '
         'transaction')
A_N25G = ('Notes 4/5/25: every recorded Entry is immediately in the Guardian history with its current and earlier '
          'versions, Clinic and Organization provenance derived from its Appointment, ordered by its recording time (or a '
          'historical event time), including Entries of revoked and completed Appointments')
A_BR48 = 'SPEC-APT-012 BR-48: has_clinical_record reports whether the Appointment has an Entry, without audit'
A_ATT_M4 = 'Note 20 (M4): no professional operation adds, completes, removes or downloads an Attachment'
A_ATT_STRUCT = "Note 20: structurally, only the Entry's author adds an Attachment"
A_ATT_AVAIL = 'Note 20: an AVAILABLE Attachment is visible, immutable and cannot be removed'
A_N10 = ('Note 10: without CLINICAL_CARE every new Entry (also on Appointments that already have Entries) is '
         'CLINICAL_SERVICE_UNAVAILABLE; nothing is written (no Attachment operation exists since M4)')
A_N10B = ('Note 10: an exact replay, edits and the read still succeed without the Entitlement; domain rejections '
          'precede the commercial gate')

ENTITLEMENT_ERROR = ("        raise exception 'Clinical care is currently unavailable for this Organization'\n"
                     "            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';\n")
READ_AUDIT_FIELDS = """            p_acting_user_id => acting_user_id,
            p_pet_id => appointment_record.pet_id,
            p_operation => 'VIEW_APPOINTMENT_CLINICAL_RECORD',
            p_outcome => 'PERMITTED',
            p_actor_context => 'PROFESSIONAL_CLINICAL',
            p_protected_resource_scope => 'APPOINTMENT_CLINICAL_RECORD',
            p_occurred_at => clock_timestamp(),
            p_care_authorization_id => care_auth_id,
            p_accessing_clinic_id => p_clinic_id,
            p_accessing_organization_id => actor.organization_id,
            p_appointment_id => appointment_record.id,
            p_organization_membership_id => actor.organization_membership_id,
            p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
            p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id
"""
RECORD_AUDIT = ("    perform public.establish_medical_access_audit_event(\n"
                + READ_AUDIT_FIELDS.replace('care_auth_id', 'null') + "    );\n")
PER_ENTRY_AUDIT = ("    perform public.establish_medical_access_audit_event(\n" + READ_AUDIT_FIELDS + "    )\n"
                   "    from public.clinical_record_entries as entry where entry.appointment_id = appointment_record.id;\n")
LIFECYCLE_BLOCK = ("    if exists (select 1 from public.clinical_record_entries as clinical_record\n"
                   "               where clinical_record.appointment_id = p_appointment_id) then\n")

# (name, function, edits [(before, after[, count])], expected assertion)
FAULTS = [
    # --- Record operation (BR-3, BR-5–BR-7, BR-13, BR-17, BR-23)
    ('Record reveals the Appointment before authority', 'ENTRY',
     [('    -- 1. Authority before any target (BR-17), in the clinical lock order:\n',
       "    if not exists (select 1 from public.appointments as leaked where leaked.id = p_appointment_id) then\n"
       "        raise exception 'Appointment does not exist' using errcode = '23503';\n    end if;\n"
       '    -- 1. Authority before any target (BR-17), in the clinical lock order:\n')], A_N9),
    ('Record accepts an Appointment of another Clinic', 'ENTRY',
     [('      and appointment.clinic_id = p_clinic_id\n    for share;\n', '    for share;\n')], A_N9),
    ('Record key no longer required', 'ENTRY', [('    if p_idempotency_key is null then\n', '    if false then\n')], A_N6),
    # BR-5: the structural rule refuses the stamped time, so the record fails.
    ('Record stamps a clinical event time', 'ENTRY',
     [('        creation_idempotency_key, creation_request_digest\n    ) values (\n',
       '        creation_idempotency_key, creation_request_digest, clinical_event_at\n    ) values (\n'),
      ('        p_idempotency_key, requested_digest\n    )\n',
       '        p_idempotency_key, requested_digest, statement_timestamp()\n    )\n')], A_REC),
    ('Record OTHER context not normalized', 'ENTRY',
     [("    normalized_other_context := nullif(btrim(p_other_category_context, E' \\t\\n\\r\\f\\013'), '');\n",
       '    normalized_other_context := p_other_category_context;\n')], A_N6),
    ('Record content not normalized', 'ENTRY',
     [("    normalized_content := nullif(btrim(p_clinical_content, E' \\t\\n\\r\\f\\013'), '');\n",
       '    normalized_content := p_clinical_content;\n')], A_REC),
    ('Record result leaks the authoring Clinic Assignment', 'ENTRY',
     [("    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id);\n",
       "    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id,\n"
       "        'creator_veterinarian_clinic_assignment_id', actor.veterinarian_clinic_assignment_id);\n")], A_REC),
    ('Recording audits itself as a medical-access read', 'ENTRY',
     [("    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id);\n",
       RECORD_AUDIT.replace('appointment_record.pet_id', 'appointment_record.pet_id')
       + "    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id);\n")], A_BR8),
    ('Record reconciliation skipped (replay re-validated as new)', 'ENTRY',
     [('    if found then\n        if existing_entry.creation_request_digest = requested_digest then\n',
       '    if false then\n        if existing_entry.creation_request_digest = requested_digest then\n')], A_N24),
    ('Same key accepts a changed request', 'ENTRY',
     [('if existing_entry.creation_request_digest = requested_digest then', 'if true then', 2)], A_N7),
    ('Digest ignores the Appointment', 'ENTRY', [("        'appointment_id', appointment_record.id,\n", '')], A_N7),
    ('Digest ignores the category', 'ENTRY', [("        'category', p_category,\n", '')], A_N7),
    ('Documentable-state check removed from the operation', 'ENTRY',
     [('    if not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state) then\n'
       "        raise exception 'The Appointment cannot be documented'\n",
       "    if false then\n        raise exception 'The Appointment cannot be documented'\n")], A_N2),
    ('NO_VETERINARIAN_ASSIGNED outcome removed', 'ENTRY',
     [('    if assigned_clinic_assignment_id is null then\n', '    if false then\n')], A_N8),
    ('Assignee rule removed from the operation', 'ENTRY',
     [('    if assigned_clinic_assignment_id <> actor.veterinarian_clinic_assignment_id\n'
       '       or not public.appointment_veterinarian_is_eligible(assigned_clinic_assignment_id, p_clinic_id) then\n',
       '    if false then\n')], A_N8),
    ('CLINICAL_CARE gate removed for new Entries', 'ENTRY',
     [("    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then\n"
       + ENTITLEMENT_ERROR, '    if false then\n' + ENTITLEMENT_ERROR)], A_N10),
    ('CLINICAL_CARE gate only for the first Entry', 'ENTRY',
     [("    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then\n"
       + ENTITLEMENT_ERROR,
       '    if not exists (select 1 from public.clinical_record_entries as earlier\n'
       '                   where earlier.appointment_id = appointment_record.id)\n'
       "       and not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then\n"
       + ENTITLEMENT_ERROR)], A_N10),
    # --- Field rules (BR-5)
    ('Category no longer required', 'FIELDS', [('    if p_category is null then\n', '    if false then\n')], A_N6),
    ('Unsupported category accepted', 'FIELDS',
     [('    if p_category not in (\n', '    if false and p_category not in (\n')], A_N6),
    ('OTHER without its context accepted', 'FIELDS',
     [("    if p_category = 'OTHER' and p_other_category_context is null then\n", '    if false then\n')], A_N6),
    ('OTHER context accepted with another category', 'FIELDS',
     [("    if p_other_category_context is not null and p_category <> 'OTHER' then\n", '    if false then\n')], A_N6),
    # --- Structural integrity (BR-1, BR-3, BR-4, BR-6, invariants)
    ('Structural documentable-state check removed', 'INTEGRITY',
     [('    if not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state) then\n',
       '    if false then\n')], A_DIRECT),
    ('Structural assignee rule removed', 'INTEGRITY',
     [('    if assigned_clinic_assignment_id is distinct from new.creator_veterinarian_clinic_assignment_id\n       or not',
       '    if false\n       or not')], A_DIRECT),
    ('Structural provider context check removed', 'INTEGRITY',
     [('    perform public.assert_vca_user_provider_context(\n'
       '        new.creator_veterinarian_clinic_assignment_id, new.created_by_user_id,\n'
       '        appointment_record.clinic_id, clinic_organization_id\n    );\n', '')], A_DIRECT),
    ('Recorded Entry updatable (Appointment reference mutable)', 'INTEGRITY',
     [("    if tg_op = 'UPDATE' then\n", '    if false then\n')], A_N3),
    ('Recorded Entry deletable', 'INTEGRITY',
     [("    if tg_op = 'DELETE' then\n        raise exception 'Clinical Record Entries cannot be deleted' using errcode = '23514';\n",
       "    if tg_op = 'DELETE' then\n        return old;\n")], A_N3),
    ('Never-confirmed Appointment accepted as documentable', 'ACCEPTS',
     [("              and confirmation.to_state = 'CONFIRMED') = 1\n",
       "              and confirmation.to_state = 'CONFIRMED') >= 0\n")], A_N2),
    # --- Editing (BR-18, BR-23b)
    ('Edit author rule removed from the operation', 'EDIT',
     [('    if entry_record.created_by_user_id is distinct from acting_user_id then\n', '    if false then\n')], A_N19_23),
    ('Edit accepts an Entry of another Appointment', 'EDIT',
     [('      and appointment.id = p_appointment_id\n', '')], A_AMD_AUTH),
    ('Edit accepts a stale version', 'EDIT',
     [('    if p_expected_version <> current_version.version_number then\n', '    if false then\n')], A_EDIT),
    ('Edit requires the Entitlement', 'EDIT',
     [("    -- 4. Only the Entry's own author edits it (BR-18).\n",
       "    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then\n"
       + ENTITLEMENT_ERROR + '    end if;\n'
       "    -- 4. Only the Entry's own author edits it (BR-18).\n")], A_N10B),
    ('Structural version author rule removed', 'AMD_INTEGRITY',
     [('    if new.amending_user_id is distinct from record_entry.created_by_user_id then\n', '    if false then\n')],
     A_AMD_STRUCT),
    ('Versions updatable', 'AMD_INTEGRITY',
     [("    if tg_op in ('UPDATE', 'DELETE') then\n", '    if false then\n')], A_AMD_STRUCT),
    # --- Appointment clinical record read (BR-20, BR-21)
    ('Read reveals an Appointment of another Clinic', 'READ',
     [('    where appointment.id = p_appointment_id\n      and appointment.clinic_id = p_clinic_id;\n'
       '    if not found then\n',
       '    where appointment.id = p_appointment_id;\n    if not found then\n')], A_N17_DENIED),
    ('Denied read of a documented Appointment not audited', 'READ',
     [('        if has_entries then\n            perform public.establish_medical_access_audit_event(\n',
       '        if false then\n            perform public.establish_medical_access_audit_event(\n')], A_N17_DENIED),
    ('Read without Entries audited', 'READ',
     [('    -- before release (ADR-004).\n    if has_entries then\n', '    -- before release (ADR-004).\n    if true then\n')],
     A_N17_EMPTY),
    ('Read audits each Entry separately', 'READ',
     [('    -- One audit event per read that returns medical information, written\n',
       PER_ENTRY_AUDIT + '    -- One audit event per read that returns medical information, written\n')], A_N17_ONE),
    ('Read leaks the author User id', 'READ',
     [("               'recorded_by_me', page.created_by_user_id = acting_user_id,\n",
       "               'recorded_by_me', page.created_by_user_id = acting_user_id,\n"
       "               'created_by_user_id', page.created_by_user_id,\n")], A_N18),
    ('Read offers editing on every Entry', 'READ',
     [("               'may_edit', page.created_by_user_id = acting_user_id,\n", "               'may_edit', true,\n")],
     A_N18),
    ('Read returns other Appointments of the Pet', 'READ',
     [('        where entry.appointment_id = appointment_record.id\n        order by entry.created_at, entry.id\n',
       '        join public.appointments as pet_appointment on pet_appointment.id = entry.appointment_id\n'
       '        where pet_appointment.pet_id = appointment_record.pet_id\n        order by entry.created_at, entry.id\n')],
     A_N18),
    ('Read depends on the Care Authorization', 'READ',
     [('    -- Advisory documentation state (BR-20); every write re-validates.\n',
       "    if (select care_auth.lifecycle_state from public.care_authorizations as care_auth where care_auth.id = care_auth_id)\n"
       "       is distinct from 'ACTIVE' then\n        return jsonb_build_object('status', 'DENIED');\n    end if;\n"
       '    -- Advisory documentation state (BR-20); every write re-validates.\n')], A_BR20),
    ('Advisory state ignores the documentable state', 'READ',
     [('        when not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state)\n'
       "            then 'APPOINTMENT_STATE'\n", '')], A_BR20),
    ('Advisory state ignores the Entitlement', 'READ',
     [("        when not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE')\n"
       "            then 'CLINICAL_SERVICE_UNAVAILABLE'\n", '')], A_N10B),
    # --- Attachments (BR-19; the professional operations are retired by M4)
    ('AVAILABLE Attachment mutable', 'ATT_INTEGRITY',
     [("        if old.removed_at is null\n           and old.validation_state = 'AVAILABLE'\n           and new is distinct from old then\n",
       '        if false then\n')], A_ATT_AVAIL),
    ('Structural author-only Attachment rule removed', 'ATT_INTEGRITY',
     [('        if new.uploaded_by_user_id is distinct from parent_entry.created_by_user_id\n           or ',
       '        if false\n           or ')], A_ATT_STRUCT),
    # --- Lifecycle interactions (BR-8, BR-9)
    ('Documented Appointment cancellable', 'CANCEL', [(LIFECYCLE_BLOCK, LIFECYCLE_BLOCK.replace('if exists', 'if false and exists'))],
     A_N15),
    ('Documented Appointment marked no-show', 'NO_SHOW',
     [(LIFECYCLE_BLOCK, LIFECYCLE_BLOCK.replace('if exists', 'if false and exists'))], A_N15),
    ('First Entry leaves the Reschedule Proposal pending', 'INVALIDATION',
     [("    elsif tg_table_name = 'clinical_record_entries' then\n        perform public.void_open_reschedule_proposal(\n"
       "            new.appointment_id, 'CLINICAL_DOCUMENTATION_STARTED'\n        );\n",
       "    elsif tg_table_name = 'clinical_record_entries' then\n        null;\n")], A_N14),
    ('Schedule flag removed', 'SCHEDULE',
     [('        exists (\n            select 1\n            from public.clinical_record_entries as clinical_record\n'
       '            where clinical_record.appointment_id = appointment.id\n        )\n', '        false\n')], A_BR48),
    # --- Prior-history access and projection (BR-14, BR-15, BR-16, BR-22)
    # Since M3 a COMPLETED Appointment never keeps an ACTIVE authorization, so
    # admitting COMPLETED to the window alone is unobservable; the fault is
    # opening history through a COMPLETED Appointment whatever its authorization.
    ('Prior history opened by a COMPLETED Appointment', 'HISTORY_ACCESS',
     [("        select care_auth.lifecycle_state = 'ACTIVE'\n"
       '               and public.appointment_permits_pre_care_access(appointment.id, p_reference_time)\n',
       "        select appointment.lifecycle_state = 'COMPLETED'\n"
       "               or (care_auth.lifecycle_state = 'ACTIVE'\n"
       '                   and public.appointment_permits_pre_care_access(appointment.id, p_reference_time))\n')], A_N12),
    ('Prior history ignores revocation', 'HISTORY_ACCESS',
     [("        select care_auth.lifecycle_state = 'ACTIVE'\n", '        select true\n')], A_N12),
    ('Prior history opened by documentation access', 'PROF_HISTORY',
     [('       or not public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp()) then\n',
       '       or not (public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp())\n'
       '               or exists (select 1 from public.clinical_record_entries as own\n'
       '                          where own.appointment_id = appointment_record.id\n'
       '                            and own.created_by_user_id = acting_user_id)) then\n')], A_N12),
    ('History filtered by the Care Authorization of the Entry\'s Appointment', 'HISTORY_PAGE',
     [('    where appointment.pet_id = p_pet_id\n',
       '    where appointment.pet_id = p_pet_id\n'
       '      and exists (select 1 from public.care_authorizations as entry_authorization\n'
       '                  where entry_authorization.appointment_id = appointment.id\n'
       "                    and entry_authorization.lifecycle_state = 'ACTIVE')\n")], A_N25G),
    ('History ordered by recording time only', 'HISTORY_PAGE',
     [('           coalesce(record_entry.clinical_event_at, record_entry.created_at),\n           current_version.category,\n',
       '           record_entry.created_at,\n           current_version.category,\n')], A_N25G),
]

# Definitions that are not edits of one function.
EXTRA = [
    Fault('record operation executable by anon',
          'grant execute on function public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text) to anon;\n',
          A_CONTRACT),
    Fault('edit operation executable by service_role',
          'grant execute on function public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text) to service_role;\n',
          A_CONTRACT),
    Fault('the timed record operation reappears',
          "create function public.create_appointment_clinical_entry(p_clinic_id uuid, p_appointment_id uuid,\n"
          "    p_idempotency_key uuid, p_category text, p_clinical_content text, p_other_category_context text,\n"
          "    p_clinical_event_at timestamptz, p_clinical_event_now boolean default false) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n",
          A_RECORD_SIGNATURE),
    Fault('private actor lock executable by authenticated',
          'grant execute on function public.lock_clinical_actor_context(uuid, uuid, text) to authenticated;\n', A_PRIVATE),
    Fault('version helper executable by authenticated',
          'grant execute on function public.clinical_entry_previous_versions(uuid) to authenticated;\n', A_PRIVATE),
    Fault('a reason-and-addition operation reappears',
          "create function public.create_appointment_clinical_amendment(p_clinic_id uuid, p_appointment_id uuid,\n"
          "    p_entry_id uuid, p_idempotency_key uuid, p_reason text, p_amendment_content text) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n", A_N21),
    Fault('Guardian Attachment download authorizer executable by authenticated',
          'grant execute on function public.authorize_guardian_clinical_attachment_download(uuid, uuid) to authenticated;\n',
          A_PRIVATE),
    Fault('a retired professional Attachment operation reappears',
          "create function public.initiate_clinical_attachment_upload(p_auth_subject uuid, p_entry_id uuid,\n"
          "    p_uploader_vca_id uuid, p_upload_idempotency_key uuid, p_original_filename text) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n", A_ATT_M4),
    Fault('the multi-context download authorizer reappears',
          "create function public.authorize_clinical_attachment_download(p_auth_subject uuid, p_attachment_id uuid,\n"
          "    p_access_context text, p_professional_scope text, p_accessing_clinic_id uuid,\n"
          "    p_care_authorization_id uuid, p_accessing_clinical_encounter_id uuid) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n", A_ATT_M4),
    Fault('a retired Encounter operation reappears',
          "create function public.start_appointment_clinical_encounter(p_clinic_id uuid, p_appointment_id uuid,\n"
          "    p_started_at timestamptz) returns jsonb language sql security definer set search_path = ''\n"
          "    as $f$ select null::jsonb $f$;\n", A_N21),
    Fault('active-authorization list executable by authenticated',
          'grant execute on function public.get_professional_pet_active_care_authorizations(uuid, uuid) to authenticated;\n',
          A_N21),
    Fault('an Encounter table reappears', 'create table public.clinical_encounters (id uuid primary key);\n', A_N1),
    Fault('per-User creation key dropped',
          'alter table public.clinical_record_entries drop constraint clinical_record_entries_creation_key;\n', A_N1),
    Fault('Entry Appointment reference optional',
          'alter table public.clinical_record_entries alter column appointment_id drop not null;\n', A_N1),
    Fault('structural Entry trigger dropped',
          'drop trigger clinical_record_entries_integrity on public.clinical_record_entries;\n', A_DIRECT),
    Fault('Reschedule invalidation trigger dropped',
          'drop trigger clinical_record_entries_invalidate_reschedule_proposal on public.clinical_record_entries;\n', A_N14),
]


def edit(source, before, after, count=1):
    found = source.count(before)
    if found != count:
        raise HarnessFailure(f'Fault anchor must occur exactly {count} time(s), found {found}: {before!r}')
    return source.replace(before, after)


def definition(client, signature):
    # The harness reader does not accept array argument types (uuid[]).
    if not re.fullmatch(r"public\.\w+\([\w, \[\]]*\)", signature):
        raise HarnessFailure('Invalid repository function signature')
    text = client.require_success(f"select pg_get_functiondef('{signature}'::regprocedure);", 'Read original definition')
    return text.rstrip().rstrip(';') + ';\n'


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        bases = {key: definition(client, signature) for key, signature in SIGNATURES.items()}
        candidates = []
        for name, function, edits, assertion in FAULTS:
            candidate = bases[function]
            for change in edits:
                candidate = edit(candidate, *change)
            candidates.append(Fault(name, candidate, assertion))
        candidates.extend(EXTRA)
        client.faults(source, candidates)
        client.suite(SUITE)
        print(f'{len(candidates)}/{len(candidates)} appointment clinical record mutation assertions observed', flush=True)
        client.verify_zero_fixtures(['d0400000-'])


if __name__ == '__main__':
    main()

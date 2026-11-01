"""Reproducible LOCAL-only mutation regression for stage M4: the Guardian
Clinical Attachment download authorization (SPEC-MED-010 BR-19, BR-24, BR-25;
SPEC-MED-007 download rules) and the retirement of every professional
Attachment operation.

Run from the repository root after a clean local reset. Each behavioural
mutant replaces the deployed Guardian authorizer (or adds a grant or a retired
operation) inside the rollback-only suite transaction and must be caught by its
named assertion; infrastructure errors never count. Session
rollback/restoration and zero retained fixtures are verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT

SUITE = ROOT / 'supabase/tests/clinical_attachments_slice13_corrections.sql'
GUARDIAN = 'public.authorize_guardian_clinical_attachment_download(uuid, uuid)'
# The audit establishment backstop rejects a Guardianship of another Pet at
# write time; the decision mutant is paired with it so the authorizer's own
# observable outcome is what the assertion catches. The backstop alone is an
# equivalent mutant here: the authorizer never passes another Pet's Guardianship.
AUDIT_BACKSTOP = ('public.assert_medical_access_audit_event_establishment('
                  'uuid, uuid, timestamptz, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)')
PAIRED = ' (decision and audit backstop)'

OTHER_PET = 'A Guardian of another Pet must receive only structured DENIED'
ENDED = 'An ended Guardianship must not release the Attachment'
PENDING = "A PENDING Attachment must never be released to a Guardian, even with its object stored"
AUDIT = 'Guardian PERMITTED access must establish exactly one Attachment audit'
PROVENANCE = 'Guardian PERMITTED audit provenance must be exact and non-professional'
RESULT = 'Current Guardian must receive exactly the structured PERMITTED result'
SIGNATURE = 'Exactly one two-argument Guardian Attachment download authorizer must exist'
ACL = 'Only service_role may execute the Guardian Attachment download authorizer'
RETIRED = 'The retired professional Attachment operations must not exist under any signature'
MISSING_OBJECT = 'Expected SQLSTATE XX001, but statement succeeded'

# (name, [(before, after)], expected assertion, assertion helper)
FAULTS = [
    ("any of the User's Guardianships releases any Pet's Attachment" + PAIRED,
     [('    where guardianship.pet_id = origin_appointment.pet_id\n      and guardianship.user_id = acting_user_id\n'
       '      and guardianship.effective_start <= clock_timestamp()\n',
       '    where guardianship.user_id = acting_user_id\n'
       '      and guardianship.effective_start <= clock_timestamp()\n')], OTHER_PET, 'assert_true'),
    ('an ended Guardianship still releases the Attachment',
     [('        and guardianship_record.effective_end is null\n', '')], ENDED, 'assert_true'),
    ('a PENDING Attachment is released',
     [("        and attachment_record.validation_state = 'AVAILABLE'\n", '')], PENDING, 'assert_true'),
    ('the download is not audited',
     [("    perform public.establish_medical_access_audit_event(\n", "    perform 1;\n    /*\n"),
       ("        p_clinical_attachment_id => attachment_record.id\n    );\n",
        "        p_clinical_attachment_id => attachment_record.id\n    );\n    */\n")],
     AUDIT, 'assert_true'),
    # Auditing it as a professional access is rejected by the audit table's
    # context-shape constraint, so the observable provenance fault is this one.
    ('the Guardianship that released the Attachment is not recorded',
     [('        p_guardianship_id => guardianship_record.id,\n', '        p_guardianship_id => null,\n')],
     PROVENANCE, 'assert_true'),
    ('the result leaks the Entry identifier',
     [("        'original_filename', attachment_record.original_filename\n",
       "        'original_filename', attachment_record.original_filename,\n"
       "        'clinical_record_entry_id', record_entry.id\n")], RESULT, 'assert_true'),
    ('a missing Storage object is released',
     [('    if permitted and not exists (\n', '    if false and not exists (\n')], MISSING_OBJECT, 'assert_sqlstate'),
]

EXTRA = [
    Fault('Guardian authorizer executable by authenticated',
          f'grant execute on function {GUARDIAN} to authenticated;\n', ACL),
    Fault('a professional overload of the Guardian authorizer',
          "create function public.authorize_guardian_clinical_attachment_download(p_auth_subject uuid,\n"
          "    p_attachment_id uuid, p_care_authorization_id uuid) returns jsonb language sql security definer\n"
          "    set search_path = '' as $f$ select null::jsonb $f$;\n", SIGNATURE),
    Fault('the multi-context download authorizer reappears',
          "create function public.authorize_clinical_attachment_download(p_auth_subject uuid, p_attachment_id uuid,\n"
          "    p_access_context text, p_professional_scope text, p_accessing_clinic_id uuid,\n"
          "    p_care_authorization_id uuid, p_accessing_clinical_encounter_id uuid) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n", RETIRED),
    Fault('the professional upload operation reappears',
          "create function public.initiate_clinical_attachment_upload(p_auth_subject uuid, p_entry_id uuid,\n"
          "    p_uploader_vca_id uuid, p_upload_idempotency_key uuid, p_original_filename text) returns jsonb\n"
          "    language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n", RETIRED),
    Fault('the professional removal operation reappears',
          "create function public.remove_draft_clinical_attachment(p_auth_subject uuid, p_attachment_id uuid)\n"
          "    returns jsonb language sql security definer set search_path = '' as $f$ select null::jsonb $f$;\n",
          RETIRED),
]


def edit(source, before, after):
    if source.count(before) != 1:
        raise HarnessFailure(f'Fault anchor must occur exactly once: {before!r}')
    return source.replace(before, after)


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        base = client.definition(GUARDIAN)
        backstop = edit(client.definition(AUDIT_BACKSTOP),
                        '        if guardianship_row.pet_id <> p_pet_id then\n', '        if false then\n')
        candidates = []
        for name, edits, assertion, helper in FAULTS:
            candidate = base
            for before, after in edits:
                candidate = edit(candidate, before, after)
            if name.endswith(PAIRED):
                candidate += backstop
            candidates.append(Fault(name, candidate, assertion, helper))
        candidates.extend(EXTRA)
        client.faults(source, candidates)
        client.suite(SUITE)
        print(f'{len(candidates)}/{len(candidates)} Guardian Attachment download mutation assertions observed', flush=True)
        client.verify_zero_fixtures(['13000000-'])


if __name__ == '__main__':
    main()

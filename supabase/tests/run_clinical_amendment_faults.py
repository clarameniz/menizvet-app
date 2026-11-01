"""Reproducible LOCAL-only mutation regression for editing Clinical Record
Entries with preserved versions (SPEC-MED-010 BR-18, BR-20, BR-22, BR-23b,
BR-25; SPEC-MED-004 as superseded by them; SPEC-SUB-004 BR-20).

Run from the repository root after a clean local reset. Each behavioural
mutant replaces one deployed function (or two, or one grant) inside the
rollback-only suite transaction and must be caught by its named assertion;
infrastructure errors never count. Session rollback/restoration and zero
retained fixtures are verified. The insert-time race of two edits is pinned by
run_clinical_amendment_concurrency.py.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT

SUITE = ROOT / 'supabase/tests/clinical_amendments_spec_med_004.sql'

SIGNATURES = {
    'EDIT': 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)',
    'READ': 'public.view_appointment_clinical_record(uuid, uuid)',
    'AMENDMENT_TRIGGER': 'public.enforce_clinical_amendment_integrity()',
    'ENTRY_TRIGGER': 'public.enforce_clinical_record_entry_integrity()',
    'VERSIONS': 'public.clinical_entry_versions(uuid)',
    'PREVIOUS': 'public.clinical_entry_previous_versions(uuid)',
    'LEGACY': 'public.clinical_history_amendments(uuid)',
    'PAGE': 'public.clinical_history_page(uuid, integer, timestamptz, uuid)',
}

UNIFORM = 'EDT authority: wrong Clinic, wrong Organization, unknown and foreign targets are indistinguishable from no authority'
REPLAY = 'EDT idempotency: an exact repeat, including after a lost response, is ALREADY_EDITED with the same version'
CONFLICT = 'EDT idempotency: the same key with a different request is KEY_CONFLICT, writes nothing and never echoes the key'
CREATE = ('EDT edit: the author edits category and content; the next version is appended at the server time with '
          'its own provenance')
UNCHANGED = 'EDT edit: the original version, its Appointment, assignment and Care Authorization are unchanged'
READ_EDIT = ('EDT read: the record shows the current version (Clinical note, corrected text), the original recording '
             'time and the earlier version')
OTHER = 'EDT edit: another current Veterinarian receives ENTRY_AUTHOR_REQUIRED and writes nothing'
STALE = 'EDT stale: an edit opened on an earlier or unknown version is STALE_VERSION, echoes no content and writes nothing'
UNCHANGED_SAVE = 'EDT unchanged: saving the current version without a change writes nothing'
MULTIPLE = ('EDT multiple: successive edits append versions 2, 3, 4 without gaps; earlier versions are unchanged and a '
            'late retry still reconciles')
REQUEST = ('EDT request: a missing key or version, a missing or invalid category, empty content or misplaced OTHER '
           'context is rejected with its stable hint and writes nothing')
COMPLETED_AUTHOR = ("EDT lifecycle: a COMPLETED Appointment's Entry is edited by its author after completion ended "
                    'the authorization; may_edit is true only for the author')
ASSIGNEE = 'EDT offboarding: the new assignee clarifies with an Entry of their own; authorship and history are preserved'
READ_IDS = 'EDT read: versions carry no User, Clinic Assignment or key identifier'
READ_VERSIONS = ('EDT read: each Entry shows its current version with every earlier version oldest first, beside its '
                 'original recording time')
READ_AUDIT = 'EDT read: one audit event per read, not one per version'
GUARDIAN = ('EDT guardian: the Guardian sees the current version and every earlier one, also edits made after '
            'revocation, in the original order')
LAPSE = ('EDT lapse: an Entitlement lapse does not block an edit; new Entries stay unavailable and authority still '
         'applies')
IMMUTABLE = 'EDT immutability: versions and the recorded Entry cannot be updated or deleted'
STRUCTURE = ("EDT structure: only the author's next EDIT version can be appended, without gaps or duplicates; no "
             'reason-and-addition row and no Entry with an event time can be written')
CONTRACT = ('EDT contract: the edit operation is SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only, '
            'one signature; the version helpers are internal')
RETIRED = 'EDT contract: the reason-and-addition operations are retired for every role (BR-25)'
NO_DIRECT_WRITE = 'EDT immutability: no client role writes versions or Entries directly'

AUTHORITY_STEP = '    -- 2. Authority before any target; no Entitlement (SPEC-SUB-004 BR-20).\n'
TARGET_CLINIC = '      and appointment.clinic_id = p_clinic_id\n    for update of entry;\n'
TARGET_APPOINTMENT = '      and appointment.id = p_appointment_id\n'
AUTHOR_CHECK = '    if entry_record.created_by_user_id is distinct from acting_user_id then\n'
REQUEST_STEP = '    -- 5. The request.\n'
RECONCILE_STEP = "    -- 7. Reconciliation of this User's key (unique across all Amendments).\n"
KEY_CHECK = '    if p_idempotency_key is null then\n'
VERSION_CHECK = '    if p_expected_version is null or p_expected_version < 1 then\n'
FIELD_RULES = ('    perform public.assert_clinical_entry_fields(\n'
               '        p_category, normalized_content, normalized_other_context, null\n'
               '    );\n')
CONTENT_NORMALIZED = "    normalized_content := nullif(btrim(p_clinical_content, E' \\t\\n\\r\\f\\013'), '');\n"
CONTEXT_NORMALIZED = "    normalized_other_context := nullif(btrim(p_other_category_context, E' \\t\\n\\r\\f\\013'), '');\n"
REPLAY_FOUND = "    if found then\n        if existing_version.change_kind = 'EDIT'\n"
REPLAY_IDENTITY = ("    if found then\n"
                   "        if existing_version.change_kind = 'EDIT'\n"
                   "           and existing_version.original_clinical_record_entry_id = entry_record.id\n"
                   "           and existing_version.version_number = p_expected_version + 1\n")
STALE_CHECK = '    if p_expected_version <> current_version.version_number then\n'
UNCHANGED_CHECK = '    if current_version.category = p_category\n'
PROVENANCE = '        acting_user_id, actor.veterinarian_clinic_assignment_id,\n'
EDITED_RETURN = "    return jsonb_build_object('outcome', 'EDITED', 'version', created_version);\n"

READ_PAGE = '        where entry.appointment_id = appointment_record.id\n        order by entry.created_at, entry.id\n'
READ_CATEGORY = "               'category', current_version.category,\n"
READ_CONTENT = "               'clinical_content', current_version.clinical_content,\n"
READ_PREVIOUS = "               'previous_versions', public.clinical_entry_previous_versions(page.id),\n"
READ_EDITED_AT = "               'edited_at', current_version.edited_at,\n"
READ_RECORDED_AT = "               'recorded_at', page.created_at,\n"
READ_BY_ME = "               'recorded_by_me', page.created_by_user_id = acting_user_id,\n"
READ_MAY_EDIT = "               'may_edit', page.created_by_user_id = acting_user_id,\n"
READ_ONE_AUDIT = '    -- One audit event per read that returns medical information, written\n'

VERSIONS_EDIT_ONLY = "      and amendment.change_kind = 'EDIT'\n"
PREVIOUS_BELOW_CURRENT = '        where version.version_number < (\n'
PREVIOUS_ORDER = "           ) order by earlier.version_number), '[]'::jsonb)\n"
LEGACY_ADDENDUM_ONLY = "      and amendment.change_kind = 'ADDENDUM'\n"
PAGE_CURRENT = ('           current_version.category,\n'
                '           current_version.other_category_context,\n'
                '           current_version.clinical_content,\n')
PAGE_ORDER = ('           coalesce(record_entry.clinical_event_at, record_entry.created_at),\n'
              '           current_version.category,\n')

TRIGGER_APPEND_ONLY = "    if tg_op in ('UPDATE', 'DELETE') then\n"
TRIGGER_EDIT_ONLY = "    if new.change_kind is distinct from 'EDIT' then\n"
TRIGGER_GAPLESS = '    if new.version_number is distinct from current_version + 1 then\n'
TRIGGER_AUTHOR = '    if new.amending_user_id is distinct from record_entry.created_by_user_id then\n'
ENTRY_UPDATE_GUARD = "    if tg_op = 'UPDATE' then\n"
ENTRY_NO_EVENT_TIME = '    if new.clinical_event_at is not null then\n'

EXISTENCE_FIRST = """    if not exists (select 1 from public.clinical_record_entries as leaked where leaked.id = p_entry_id) then
        raise exception 'Clinical Record Entry does not exist' using errcode = '23503';
    end if;
"""
ORIGINAL_MUTATED = """    update public.clinical_record_entries set clinical_content = normalized_content where id = entry_record.id;
"""
ASSIGNEE_EDITS = """    if entry_record.created_by_user_id is distinct from acting_user_id
       and not exists (select 1 from public.appointment_veterinarian_assignments as current_period
                       where current_period.appointment_id = p_appointment_id
                         and current_period.effective_end is null
                         and current_period.veterinarian_clinic_assignment_id = actor.veterinarian_clinic_assignment_id) then
"""
APPOINTMENT_CONFIRMED = """    if exists (select 1 from public.appointments as required
               where required.id = p_appointment_id and required.lifecycle_state <> 'CONFIRMED') then
        raise exception 'The Appointment is not open' using errcode = '23514', hint = 'APPOINTMENT_NOT_CONFIRMED';
    end if;
"""
AUTHORIZATION_ACTIVE = """    if not exists (select 1 from public.care_authorizations as required
                   where required.appointment_id = p_appointment_id and required.lifecycle_state = 'ACTIVE') then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;
"""
AUTHORIZATION_NOT_ENDED = """    if exists (select 1 from public.care_authorizations as required
               where required.appointment_id = p_appointment_id and required.lifecycle_state = 'ENDED') then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;
"""
ENTITLEMENT_REQUIRED = """    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then
        raise exception 'Clinical care is currently unavailable for this Organization'
            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';
    end if;
"""
PER_VERSION_AUDIT = """    perform public.establish_medical_access_audit_event(
        p_acting_user_id => acting_user_id, p_pet_id => appointment_record.pet_id,
        p_operation => 'VIEW_APPOINTMENT_CLINICAL_RECORD', p_outcome => 'PERMITTED',
        p_actor_context => 'PROFESSIONAL_CLINICAL', p_protected_resource_scope => 'APPOINTMENT_CLINICAL_RECORD',
        p_occurred_at => clock_timestamp(), p_care_authorization_id => care_auth_id,
        p_accessing_clinic_id => p_clinic_id, p_accessing_organization_id => actor.organization_id,
        p_appointment_id => appointment_record.id,
        p_organization_membership_id => actor.organization_membership_id,
        p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id)
    from public.clinical_amendments as amendment
    join public.clinical_record_entries as entry on entry.id = amendment.original_clinical_record_entry_id
    where entry.appointment_id = appointment_record.id;
"""
RETIRED_WRITER = """create function public.create_clinical_amendment(p_entry_id uuid, p_reason text, p_content text, p_key uuid)
returns jsonb language sql security definer set search_path = '' as $f$ select null::jsonb $f$;
"""

# (name, [(function, [(before, after)])], expected assertion)
FAULTS = [
    ('target existence checked before authority',
     [('EDIT', [(AUTHORITY_STEP, EXISTENCE_FIRST + AUTHORITY_STEP)])], UNIFORM),
    ('Entry of another Clinic accepted', [('EDIT', [(TARGET_CLINIC, '    for update of entry;\n')])], UNIFORM),
    ('Entry of another Appointment accepted', [('EDIT', [(TARGET_APPOINTMENT, '')])], UNIFORM),
    ('author rule removed from the operation', [('EDIT', [(AUTHOR_CHECK, '    if false then\n')])], OTHER),
    ("current assignee edits another Veterinarian's Entry (operation and trigger)",
     [('EDIT', [(AUTHOR_CHECK, ASSIGNEE_EDITS)]),
      ('AMENDMENT_TRIGGER', [(TRIGGER_AUTHOR, '    if false then\n')])], ASSIGNEE),
    ('original Entry overwritten by the edit (operation and Entry backstop)',
     [('EDIT', [(EDITED_RETURN, ORIGINAL_MUTATED + EDITED_RETURN)]),
      ('ENTRY_TRIGGER', [(ENTRY_UPDATE_GUARD, '    if false then\n')])], UNCHANGED),
    ('editing Clinic Assignment not recorded',
     [('EDIT', [(PROVENANCE, '        acting_user_id, null,\n')])], CREATE),
    ('content not normalized', [('EDIT', [(CONTENT_NORMALIZED, '    normalized_content := p_clinical_content;\n')])],
     CREATE),
    ('OTHER context not normalized',
     [('EDIT', [(CONTEXT_NORMALIZED, '    normalized_other_context := p_other_category_context;\n')])], MULTIPLE),
    ('Appointment required CONFIRMED', [('EDIT', [(RECONCILE_STEP, APPOINTMENT_CONFIRMED + RECONCILE_STEP)])],
     CONFLICT),
    ('edit depends on an ACTIVE Care Authorization',
     # Caught first by the KEY_CONFLICT probe on a COMPLETED Appointment, whose
     # authorization completion ended.
     [('EDIT', [(RECONCILE_STEP, AUTHORIZATION_ACTIVE + RECONCILE_STEP)])], CONFLICT),
    ('ENDED Care Authorization closes editing',
     [('EDIT', [(RECONCILE_STEP, AUTHORIZATION_NOT_ENDED + RECONCILE_STEP)])], CONFLICT),
    ('Entitlement incorrectly required', [('EDIT', [(REQUEST_STEP, ENTITLEMENT_REQUIRED + REQUEST_STEP)])], LAPSE),
    ('replay not reconciled (a lost response becomes STALE_VERSION)',
     [('EDIT', [(REPLAY_FOUND, "    if false then\n        if existing_version.change_kind = 'EDIT'\n")])], REPLAY),
    ('replay ignores the version it was opened on',
     [('EDIT', [(REPLAY_IDENTITY, REPLAY_IDENTITY.replace(
         '           and existing_version.version_number = p_expected_version + 1\n', ''))])], CONFLICT),
    ('key conflict ignored',
     [('EDIT', [(REPLAY_FOUND, "    if found then\n        if true or existing_version.change_kind = 'EDIT'\n")])],
     CONFLICT),
    ('key requirement removed', [('EDIT', [(KEY_CHECK, '    if false then\n')])], REQUEST),
    ('version requirement removed', [('EDIT', [(VERSION_CHECK, '    if false then\n')])], REQUEST),
    ('field rules removed', [('EDIT', [(FIELD_RULES, '')])], REQUEST),
    ('stale version accepted', [('EDIT', [(STALE_CHECK, '    if false then\n')])], STALE),
    ('a version newer than the current one accepted',
     [('EDIT', [(STALE_CHECK, '    if p_expected_version < current_version.version_number then\n')])], STALE),
    ('unchanged save writes a version', [('EDIT', [(UNCHANGED_CHECK, '    if false and current_version.category = p_category\n')])],
     UNCHANGED_SAVE),
    ('original Entry hidden after an edit (professional read)',
     [('READ', [(READ_PAGE, '        where entry.appointment_id = appointment_record.id\n'
                            '          and not exists (select 1 from public.clinical_amendments as hidden\n'
                            '                          where hidden.original_clinical_record_entry_id = entry.id)\n'
                            '        order by entry.created_at, entry.id\n')])], READ_EDIT),
    ('original version shown instead of the current one',
     [('READ', [(READ_CATEGORY, "               'category', page.category,\n"),
                (READ_CONTENT, "               'clinical_content', page.clinical_content,\n")])], READ_EDIT),
    ('earlier versions hidden', [('READ', [(READ_PREVIOUS, "               'previous_versions', '[]'::jsonb,\n")])],
     READ_EDIT),
    ('edit time omitted', [('READ', [(READ_EDITED_AT, "               'edited_at', null,\n")])], READ_EDIT),
    ('recording time replaced by the edit time',
     [('READ', [(READ_RECORDED_AT, "               'recorded_at', coalesce(current_version.edited_at, page.created_at),\n")])],
     READ_EDIT),
    ('editing offered on every Entry', [('READ', [(READ_MAY_EDIT, "               'may_edit', true,\n")])],
     COMPLETED_AUTHOR),
    ('internal author id leaked',
     [('READ', [(READ_BY_ME, READ_BY_ME + "               'author_user_id', page.created_by_user_id,\n")])], READ_IDS),
    ('read audits each version separately',
     [('READ', [(READ_ONE_AUDIT, PER_VERSION_AUDIT + READ_ONE_AUDIT)])], READ_AUDIT),
    ('edits dropped from the versions', [('VERSIONS', [(VERSIONS_EDIT_ONLY, '      and false\n')])], READ_EDIT),
    ('current version listed among the earlier ones',
     [('PREVIOUS', [(PREVIOUS_BELOW_CURRENT, '        where version.version_number <= (\n')])], READ_EDIT),
    ('earlier versions newest first',
     [('PREVIOUS', [(PREVIOUS_ORDER, "           ) order by earlier.version_number desc), '[]'::jsonb)\n")])],
     READ_VERSIONS),
    ('versions also listed as legacy corrections', [('LEGACY', [(LEGACY_ADDENDUM_ONLY, '')])], READ_VERSIONS),
    ('Guardian history shows the original version',
     [('PAGE', [(PAGE_CURRENT, '           record_entry.category,\n'
                               '           record_entry.other_category_context,\n'
                               '           record_entry.clinical_content,\n')])], GUARDIAN),
    ('an edit moves the Entry in the history',
     [('PAGE', [(PAGE_ORDER, '           coalesce(current_version.edited_at, record_entry.created_at),\n'
                             '           current_version.category,\n')])], GUARDIAN),
    ('versions deletable',
     [('AMENDMENT_TRIGGER', [(TRIGGER_APPEND_ONLY, "    if tg_op = 'DELETE' then\n        return old;\n    end if;\n"
                                                   + TRIGGER_APPEND_ONLY)])], IMMUTABLE),
    # The gapless-version rule below would refuse an update on its own, so the
    # mutant lets updates bypass the trigger, as the deletion mutant does.
    ('versions updatable',
     [('AMENDMENT_TRIGGER', [(TRIGGER_APPEND_ONLY, "    if tg_op = 'UPDATE' then\n        return new;\n    end if;\n"
                                                   + TRIGGER_APPEND_ONLY)])], IMMUTABLE),
    ('reason-and-addition rows writable again',
     [('AMENDMENT_TRIGGER', [(TRIGGER_EDIT_ONLY, '    if false then\n')])], STRUCTURE),
    ('version gaps accepted',
     [('AMENDMENT_TRIGGER', [(TRIGGER_GAPLESS, '    if new.version_number <= current_version then\n')])], STRUCTURE),
    ('author backstop removed', [('AMENDMENT_TRIGGER', [(TRIGGER_AUTHOR, '    if false then\n')])], STRUCTURE),
    ('new Entries accept an event time', [('ENTRY_TRIGGER', [(ENTRY_NO_EVENT_TIME, '    if false then\n')])], STRUCTURE),
]

EXTRA = [
    Fault('edit operation executable by anon',
          'grant execute on function public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text) to anon;\n',
          CONTRACT),
    Fault('version helper client-executable',
          'grant execute on function public.clinical_entry_versions(uuid) to authenticated;\n', CONTRACT),
    Fault('Encounter-based access predicate reappears',
          "create function public.appointment_clinical_record_accessible(p_encounter_id uuid) returns boolean\n"
          "    language sql stable security definer set search_path = '' as $f$ select true $f$;\n", CONTRACT),
    Fault('reason-and-addition writer reappears', RETIRED_WRITER, RETIRED),
    Fault('versions directly insertable by clients',
          'grant insert on public.clinical_amendments to authenticated;\n', NO_DIRECT_WRITE),
    Fault('Entries directly updatable by clients',
          'grant update on public.clinical_record_entries to authenticated;\n', NO_DIRECT_WRITE),
]


def edit(source, before, after):
    if source.count(before) != 1:
        raise HarnessFailure(f'Fault anchor must occur exactly once: {before!r}')
    return source.replace(before, after)


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(SUITE)
        bases = {key: client.definition(signature) for key, signature in SIGNATURES.items()}
        candidates = []
        for name, functions, assertion in FAULTS:
            definitions = ''
            for function, edits in functions:
                candidate = bases[function]
                for before, after in edits:
                    candidate = edit(candidate, before, after)
                definitions += candidate
            candidates.append(Fault(name, definitions, assertion))
        candidates.extend(EXTRA)
        client.faults(source, candidates)
        client.suite(SUITE)
        print(f'{len(candidates)}/{len(candidates)} clinical edit mutation assertions observed', flush=True)
        client.verify_zero_fixtures(['d0350000-'])


if __name__ == '__main__':
    main()

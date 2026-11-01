"""LOCAL-only verification that migration 20261113090000 (Punto 8, stage M2)
refuses to run while documentation of the retired Clinical Encounter model
exists (SPEC-MED-010 BR-25; docs/CLINICAL_DOCUMENTATION_TRANSITION.md §3).

DESTRUCTIVE FOR THE LOCAL DATABASE ONLY: it resets the local database to the
version before M2 (`supabase db reset --local --version 20261112090000`). For
each guard criterion it plants one row of retired documentation, runs the whole
M2 body inside one transaction and requires the guard's 55000 refusal; the
transaction is always rolled back, and the pre-M2 schema must still be intact.
A clean run of the same body must succeed (and is rolled back too). Finally
the pending migration is applied with `supabase migration up --local`. Never
point this at a shared database: there is no remote option.
"""
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql, ROOT

M2 = ROOT / 'supabase/migrations/20261113090000_appointment_owned_clinical_documentation.sql'
PRE_M2_VERSION = '20261112090000'
U = 'd0450000-0000-4000-8000-'  # planted identifiers; nothing is committed


def uid(n):
    return f'{U}{n:012d}'


REFUSED_DOCUMENTATION = 'M2 refused: clinical documentation of the retired model exists'
REFUSED_AUDIT = 'M2 refused: clinical audit evidence of the retired model exists'
REFUSED_HISTORY = 'M2 refused: Appointment history still references Clinical Encounters'

ENCOUNTER = (f"insert into public.clinical_encounters (id, pet_id, clinic_id, organization_id, "
             f"responsible_veterinarian_clinic_assignment_id, created_by_user_id, care_authorization_id, appointment_id, "
             f"started_at, created_at, lifecycle_state) values ('{uid(1)}', '{uid(2)}', '{uid(3)}', '{uid(4)}', '{uid(5)}', "
             f"'{uid(6)}', '{uid(7)}', null, '2026-01-01Z', '2026-01-01Z', 'ACTIVE');\n")
DRAFT = (f"insert into public.clinical_record_entries (id, clinical_encounter_id, created_by_user_id, "
         f"creator_veterinarian_clinic_assignment_id, created_at, lifecycle_state, last_modified_at) values "
         f"('{uid(10)}', '{uid(1)}', '{uid(6)}', '{uid(5)}', '2026-01-01Z', 'DRAFT', '2026-01-01Z');\n")
FINALIZED = (f"insert into public.clinical_record_entries (id, clinical_encounter_id, created_by_user_id, "
             f"creator_veterinarian_clinic_assignment_id, created_at, lifecycle_state, clinical_content, category, "
             f"last_modified_at, finalized_at, finalized_by_user_id, finalizer_veterinarian_clinic_assignment_id) values "
             f"('{uid(11)}', '{uid(1)}', '{uid(6)}', '{uid(5)}', '2026-01-01Z', 'FINALIZED', 'Old note', 'CLINICAL_NOTE', "
             f"'2026-01-01Z', '2026-01-02Z', '{uid(6)}', '{uid(5)}');\n")
AMENDMENT = (f"insert into public.clinical_amendments (id, original_clinical_record_entry_id, reason, amendment_content, "
             f"amending_user_id, amending_veterinarian_clinic_assignment_id, created_at, idempotency_key) values "
             f"('{uid(12)}', '{uid(11)}', 'Old reason', 'Old correction', '{uid(6)}', '{uid(5)}', '2026-01-03Z', '{uid(13)}');\n")
ATTACHMENT = (f"insert into public.clinical_attachments (id, clinical_record_entry_id, uploaded_by_user_id, uploader_vca_id, "
              f"created_at, upload_idempotency_key, storage_object_id, upload_stale_after, validation_state, object_state) "
              f"values ('{uid(14)}', '{uid(11)}', '{uid(6)}', '{uid(5)}', '2026-01-01Z', '{uid(15)}', '{uid(16)}', "
              f"'2026-01-02Z', 'PENDING', 'AWAITING_UPLOAD');\n")
CONTRIBUTOR = (f"insert into public.clinical_record_entry_contributors (clinical_record_entry_id, "
               f"veterinarian_clinic_assignment_id, first_contributed_at) values "
               f"('{uid(10)}', '{uid(5)}', '2026-01-01Z');\n")


def audit(operation, scope, reference=''):
    columns, values = '', ''
    if reference:
        columns, values = f', {reference}', f", '{uid(20)}'"
    return (f"insert into public.medical_access_audit_events (id, occurred_at, operation, outcome, actor_context, "
            f"protected_resource_scope, acting_user_id, pet_id{columns}) values ('{uid(21)}', '2026-01-01Z', "
            f"'{operation}', 'PERMITTED', 'PROFESSIONAL_CLINICAL', '{scope}', '{uid(6)}', '{uid(2)}'{values});\n")


LIFECYCLE_REFERENCE = (f"insert into public.appointment_lifecycle_events (id, appointment_id, from_state, to_state, "
                       f"actor_user_id, actor_context, reason, effective_at, recorded_at, clinical_encounter_id) values "
                       f"('{uid(30)}', '{uid(31)}', 'CONFIRMED', 'COMPLETED', '{uid(6)}', 'CLINIC', null, '2026-01-01Z', "
                       f"'2026-01-01Z', '{uid(1)}');\n")
VOIDED_PROPOSAL = (f"insert into public.appointment_reschedule_proposals (id, appointment_id, base_revision_id, "
                   f"base_revision_context, proposed_start_at, proposed_end_at, proposed_timezone_name, proposing_context, "
                   f"proposed_by_user_id, reason, created_at, state, void_reason, voided_at) values ('{uid(40)}', '{uid(31)}', "
                   f"'{uid(41)}', 'CONFIRMED', '2035-01-01T10:00Z', '2035-01-01T10:30Z', 'Europe/Madrid', 'CLINIC', "
                   f"'{uid(6)}', 'Move', '2026-01-01Z', 'VOID', 'CLINICAL_ENCOUNTER_STARTED', '2026-01-02Z');\n")

# (label, planted rows, expected refusal)
CASES = [
    ('a Clinical Encounter', ENCOUNTER, REFUSED_DOCUMENTATION),
    ('a Draft Entry', DRAFT, REFUSED_DOCUMENTATION),
    ('a finalized Entry', FINALIZED, REFUSED_DOCUMENTATION),
    ('an Amendment', AMENDMENT, REFUSED_DOCUMENTATION),
    ('an Attachment', ATTACHMENT, REFUSED_DOCUMENTATION),
    ('a contributor attribution', CONTRIBUTOR, REFUSED_DOCUMENTATION),
    ('an Encounter-referencing audit event', audit('VIEW_PET_MEDICAL_HISTORY', 'LONGITUDINAL_MEDICAL_HISTORY',
                                                   'clinical_encounter_id'), REFUSED_AUDIT),
    ('an Entry-referencing audit event', audit('VIEW_PET_MEDICAL_HISTORY', 'LONGITUDINAL_MEDICAL_HISTORY',
                                               'clinical_record_entry_id'), REFUSED_AUDIT),
    ('a care-access audit event', audit('ACCESS_FOR_CLINICAL_CARE', 'ENCOUNTER_MEDICAL_INFORMATION'), REFUSED_AUDIT),
    ('a post-care documentation audit event', audit('ACCESS_FOR_POST_CARE_DOCUMENTATION', 'ENCOUNTER_MEDICAL_INFORMATION'),
     REFUSED_AUDIT),
    ('an Entry read audit event', audit('VIEW_CLINICAL_RECORD_ENTRY', 'CLINICAL_RECORD_ENTRY'), REFUSED_AUDIT),
    ('an Attachment read audit event', audit('VIEW_CLINICAL_ATTACHMENT', 'CLINICAL_ATTACHMENT', 'clinical_attachment_id'),
     REFUSED_AUDIT),
    ('a Lifecycle Event referencing an Encounter', LIFECYCLE_REFERENCE, REFUSED_HISTORY),
    ('a proposal voided by an Encounter', VOIDED_PROPOSAL, REFUSED_HISTORY),
]

PRE_M2_INTACT = """select (to_regclass('public.clinical_encounters') is not null
    and to_regclass('public.clinical_record_entry_contributors') is not null
    and to_regprocedure('public.start_appointment_clinical_encounter(uuid,uuid,timestamptz)') is not null
    and to_regprocedure('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)') is null
    and exists (select 1 from information_schema.columns where table_schema = 'public'
                and table_name = 'clinical_record_entries' and column_name = 'clinical_encounter_id')
    and not exists (select 1 from public.clinical_encounters)
    and not exists (select 1 from public.clinical_record_entries))::text;"""
# `migration up` applies every pending stage: since M5 the record operation
# takes no clinical time (20261116090000_editable_clinical_record_versions.sql).
M2_APPLIED = """select (to_regclass('public.clinical_encounters') is null
    and (to_regprocedure('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)') is not null
         or to_regprocedure('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text)') is not null)
    and exists (select 1 from supabase_migrations.schema_migrations where version = '20261113090000'))::text;"""


def supabase(*arguments):
    command = ['npx', 'supabase', *arguments]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=900, shell=sys.platform == 'win32')
    if completed.returncode:
        raise HarnessFailure(f"{' '.join(command)} failed:\n{completed.stdout}\n{completed.stderr}")
    print(f"OK {' '.join(command)}", flush=True)


def m2_body():
    source = M2.read_text(encoding='utf-8')
    if not re.search(r'^begin;$', source, re.M) or not re.search(r'^commit;\s*\Z', source, re.M):
        raise HarnessFailure('M2 must be one explicit transaction')
    return re.sub(r'^commit;\s*\Z', '', re.sub(r'^begin;$', '', source, count=1, flags=re.M), flags=re.M)


def main():
    supabase('db', 'reset', '--local', '--version', PRE_M2_VERSION)
    client = LocalSql()
    if client.require_success(PRE_M2_INTACT, 'Pre-M2 schema') != 'true':
        raise HarnessFailure('The local database is not at the pre-M2 state')
    body = m2_body()
    for label, rows, refusal in CASES:
        statement = ('begin;\nset local session_replication_role = replica;\n' + rows
                     + 'set local session_replication_role = origin;\n' + body + '\nrollback;\n')
        result = client.execute(statement)
        if result.returncode == 0 or not re.search(r'^ERROR:\s+55000:\s+' + re.escape(refusal), result.stderr, re.M):
            raise HarnessFailure(f'M2 did not refuse {label}:\n{result.stderr}')
        if client.require_success(PRE_M2_INTACT, f'Pre-M2 schema after {label}') != 'true':
            raise HarnessFailure(f'The refused M2 changed the schema ({label})')
        print(f'REFUSED {label}: {refusal}', flush=True)
    clean = client.execute('begin;\n' + body + '\nrollback;\n')
    if clean.returncode or 'ERROR' in clean.stderr:
        raise HarnessFailure('M2 failed on a clean pre-M2 database:\n' + clean.stderr)
    print('PASS a clean pre-M2 database accepts the M2 body (rolled back)', flush=True)
    if client.require_success(PRE_M2_INTACT, 'Pre-M2 schema after the clean run') != 'true':
        raise HarnessFailure('The rolled-back clean run changed the schema')
    supabase('migration', 'up', '--local')
    if client.require_success(M2_APPLIED, 'M2 applied') != 'true':
        raise HarnessFailure('M2 was not applied by migration up')
    print(f'{len(CASES)}/{len(CASES)} retired-documentation criteria refused; M2 applied afterwards', flush=True)


if __name__ == '__main__':
    main()

"""LOCAL-only verification of the preservation and fail-closed guard of
migration 20261116090000 (Punto 8, stage M5; SPEC-MED-010 BR-5, BR-18, BR-25;
docs/CLINICAL_DOCUMENTATION_TRANSITION.md).

DESTRUCTIVE FOR THE LOCAL DATABASE ONLY: it resets the local database to M4
(`supabase db reset --local --version 20261115090000`). Every scenario plants
rows, runs the whole M5 body inside one transaction and inspects the result
before rolling back:

- preservation: an Entry recorded with a clinical event time and a historical
  reason-and-addition Amendment by its author are kept unchanged; the
  Amendment becomes kind ADDENDUM, is shown as a legacy correction and is never
  a version; the Entry stays version 1 and keeps its event time;
- every unexpected state aborts with 55000 and changes nothing.

Finally the pending migration is applied with `supabase migration up --local`.
Never point this at a shared database: there is no remote option.
"""
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql, ROOT

M5 = ROOT / 'supabase/migrations/20261116090000_editable_clinical_record_versions.sql'
M4_VERSION = '20261115090000'
U = 'd0470000-0000-4000-8000-'  # planted identifiers; nothing is committed


def uid(n):
    return f'{U}{n:012d}'


ENTRY = (f"insert into public.clinical_record_entries (id, appointment_id, created_by_user_id, "
         f"creator_veterinarian_clinic_assignment_id, created_at, category, clinical_content, clinical_event_at, "
         f"creation_idempotency_key, creation_request_digest) values ('{uid(10)}', '{uid(11)}', '{uid(3)}', '{uid(5)}', "
         f"'2026-06-01T10:20Z', 'VACCINATION', 'Rabies vaccine, annual', '2026-06-01T10:05Z', '{uid(12)}', "
         f"sha256('x'::bytea));\n")


def amendment(author):
    return (f"insert into public.clinical_amendments (id, original_clinical_record_entry_id, reason, amendment_content, "
            f"amending_user_id, amending_veterinarian_clinic_assignment_id, created_at, idempotency_key) values "
            f"('{uid(20)}', '{uid(10)}', 'Typo', 'Booster due in 2027', '{uid(author)}', '{uid(5)}', "
            f"'2026-06-02T08:00Z', '{uid(21)}');\n")


PRESERVED = f"""select (
    (select change_kind = 'ADDENDUM' and reason = 'Typo' and amendment_content = 'Booster due in 2027'
            and version_number is null and category is null and other_category_context is null
            and amending_user_id = '{uid(3)}' and created_at = '2026-06-02T08:00Z'
     from public.clinical_amendments where id = '{uid(20)}')
    and (select category = 'VACCINATION' and clinical_content = 'Rabies vaccine, annual'
            and clinical_event_at = '2026-06-01T10:05Z' and created_at = '2026-06-01T10:20Z'
     from public.clinical_record_entries where id = '{uid(10)}')
    and (select version_number = 1 and edited_at is null and clinical_content = 'Rabies vaccine, annual'
     from public.clinical_entry_current('{uid(10)}'))
    and public.clinical_entry_previous_versions('{uid(10)}') = '[]'::jsonb
    and (select count(*) = 1 from public.clinical_history_amendments('{uid(10)}'))
    and (select count(*) = 1 from public.clinical_amendments where id::text like '{U}%')
    and (select count(*) = 1 from public.clinical_record_entries where id::text like '{U}%')
)::text as preserved;
"""

NOT_AUTHOR = "M5 refused: an existing Amendment is not by its Entry's author"
NO_M4 = 'M5 refused: the M2–M4 documentation contract is not in place'

# (label, planted statements, expected refusal)
GUARD_CASES = [
    ('a historical Amendment by someone other than the author', ENTRY + amendment(4), NOT_AUTHOR),
    ('the M4 contract missing',
     'drop function public.authorize_guardian_clinical_attachment_download(uuid, uuid);\n', NO_M4),
]

AT_M4 = """select (to_regprocedure('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)') is not null
    and to_regprocedure('public.edit_appointment_clinical_entry(uuid,uuid,uuid,uuid,integer,text,text,text)') is null
    and not exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'clinical_amendments' and column_name = 'change_kind')
    and not exists (select 1 from supabase_migrations.schema_migrations where version = '20261116090000'))::text;"""
M5_APPLIED = """select (to_regprocedure('public.edit_appointment_clinical_entry(uuid,uuid,uuid,uuid,integer,text,text,text)') is not null
    and to_regprocedure('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)') is null
    and exists (select 1 from supabase_migrations.schema_migrations where version = '20261116090000'))::text;"""


def supabase(*arguments):
    command = ['npx', 'supabase', *arguments]
    completed_run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=900,
                                   shell=sys.platform == 'win32')
    if completed_run.returncode:
        raise HarnessFailure(f"{' '.join(command)} failed:\n{completed_run.stdout}\n{completed_run.stderr}")
    print(f"OK {' '.join(command)}", flush=True)


def m5_body():
    source = M5.read_text(encoding='utf-8')
    if not re.search(r'^begin;$', source, re.M) or not re.search(r'^commit;\s*\Z', source, re.M):
        raise HarnessFailure('M5 must be one explicit transaction')
    return re.sub(r'^commit;\s*\Z', '', re.sub(r'^begin;$', '', source, count=1, flags=re.M), flags=re.M)


# Rows are loaded as data with triggers bypassed, as recorded before M5.
def planted(rows):
    return 'begin;\nset local session_replication_role = replica;\n' + rows + 'set local session_replication_role = origin;\n'


def main():
    supabase('db', 'reset', '--local', '--version', M4_VERSION)
    client = LocalSql()
    if client.require_success(AT_M4, 'M4 state') != 'true':
        raise HarnessFailure('The local database is not at the M4 state')
    body = m5_body()

    result = client.execute(planted(ENTRY + amendment(3)) + body + '\n' + PRESERVED + 'rollback;\n')
    if result.returncode or 'ERROR' in result.stderr:
        raise HarnessFailure('M5 failed on historical documentation:\n' + result.stderr)
    if result.stdout.strip().splitlines()[-1] != 'true':
        raise HarnessFailure('M5 changed historical documentation:\n' + result.stdout)
    print('PASS preservation: the timed Entry and the author\'s historical Amendment are unchanged; the Amendment is '
          'a legacy ADDENDUM, never a version', flush=True)

    for label, rows, refusal in GUARD_CASES:
        result = client.execute(planted(rows) + body + '\nrollback;\n')
        if result.returncode == 0 or not re.search(r'^ERROR:\s+55000:\s+' + re.escape(refusal), result.stderr, re.M):
            raise HarnessFailure(f'M5 did not refuse {label}:\n{result.stderr}')
        if client.require_success(AT_M4, f'M4 state after {label}') != 'true':
            raise HarnessFailure(f'The refused M5 changed the schema ({label})')
        print(f'REFUSED {label}: {refusal}', flush=True)

    clean = client.execute('begin;\n' + body + '\nrollback;\n')
    if clean.returncode or 'ERROR' in clean.stderr:
        raise HarnessFailure('M5 failed on a clean M4 database:\n' + clean.stderr)
    print('PASS a clean M4 database accepts the M5 body (rolled back)', flush=True)

    supabase('migration', 'up', '--local')
    if client.require_success(M5_APPLIED, 'M5 applied') != 'true':
        raise HarnessFailure('M5 was not applied by migration up')
    print(f'preservation verified; {len(GUARD_CASES)}/{len(GUARD_CASES)} unexpected states refused; M5 applied afterwards',
          flush=True)


if __name__ == '__main__':
    main()

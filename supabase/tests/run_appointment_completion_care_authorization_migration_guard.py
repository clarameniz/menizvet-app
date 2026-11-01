"""LOCAL-only verification of the data reconciliation and fail-closed guard of
migration 20261114090000 (Punto 8, stage M3; SPEC-MED-010 BR-16;
docs/CLINICAL_DOCUMENTATION_TRANSITION.md §5.2).

DESTRUCTIVE FOR THE LOCAL DATABASE ONLY: it resets the local database to M2
(`supabase db reset --local --version 20261113090000`). Every scenario plants
rows, runs the whole M3 body inside one transaction and inspects the result
before rolling back:

- reconciliation: only ACTIVE authorizations of COMPLETED Appointments end,
  with APPOINTMENT_COMPLETED at each recorded completion time; REVOKED
  authorizations, ACTIVE authorizations of open Appointments and authorizations
  ended by other outcomes are untouched; nothing is created;
- every unexpected state aborts with 55000 and changes nothing.

Finally the pending migration is applied with `supabase migration up --local`.
Never point this at a shared database: there is no remote option.
"""
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql, ROOT

M3 = ROOT / 'supabase/migrations/20261114090000_appointment_completion_ends_care_authorization.sql'
M2_VERSION = '20261113090000'
U = 'd0460000-0000-4000-8000-'  # planted identifiers; nothing is committed


def uid(n):
    return f'{U}{n:012d}'


def appointment(n, state):
    return (f"insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, "
            f"created_at) values ('{uid(100 + n)}', '{uid(1)}', '{uid(2)}', '{uid(3)}', 'Visit {n}', '{state}', '2026-01-01Z');\n")


def authorization(n, state='ACTIVE', granted='2026-01-01Z'):
    extra_columns, extra_values = '', ''
    if state == 'REVOKED':
        extra_columns, extra_values = ', revoked_at, revoking_user_id', f", '2026-05-01Z', '{uid(3)}'"
    if state == 'ENDED':
        extra_columns, extra_values = ', ended_at, ended_reason', ", '2026-06-01T11:00Z', 'APPOINTMENT_NO_SHOW'"
    return (f"insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, "
            f"granted_at, purpose, appointment_id, lifecycle_state{extra_columns}) values ('{uid(200 + n)}', '{uid(1)}', "
            f"'{uid(2)}', '{uid(4)}', '{uid(5)}', '{granted}', 'APPOINTMENT_CARE', '{uid(100 + n)}', '{state}'{extra_values});\n")


def event(n, to_state, at='2026-06-01T11:00Z', key=0):
    return (f"insert into public.appointment_lifecycle_events (id, appointment_id, from_state, to_state, actor_user_id, "
            f"actor_context, reason, effective_at, recorded_at) values ('{uid(300 + 10 * n + key)}', '{uid(100 + n)}', "
            f"'CONFIRMED', '{to_state}', '{uid(3)}', 'CLINIC', null, '{at}', '{at}');\n")


def completed(n, ca_state='ACTIVE', at='2026-06-01T11:00Z'):
    return appointment(n, 'COMPLETED') + authorization(n, ca_state) + event(n, 'COMPLETED', at)


RECONCILIATION_ROWS = (
    completed(1, at='2026-06-01T11:00Z')
    + completed(2, at='2026-07-02T09:30Z')
    + completed(3, ca_state='REVOKED')
    + appointment(4, 'CONFIRMED') + authorization(4)
    + appointment(5, 'NO_SHOW') + authorization(5, 'ENDED') + event(5, 'NO_SHOW')
)
RECONCILIATION_CHECK = f"""select (
    (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_COMPLETED' and ended_at = '2026-06-01T11:00Z'
            and revoked_at is null from public.care_authorizations where id = '{uid(201)}')
    and (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_COMPLETED' and ended_at = '2026-07-02T09:30Z'
         from public.care_authorizations where id = '{uid(202)}')
    and (select lifecycle_state = 'REVOKED' and revoked_at = '2026-05-01Z' and ended_at is null and ended_reason is null
         from public.care_authorizations where id = '{uid(203)}')
    and (select lifecycle_state = 'ACTIVE' and ended_at is null from public.care_authorizations where id = '{uid(204)}')
    and (select lifecycle_state = 'ENDED' and ended_reason = 'APPOINTMENT_NO_SHOW' and ended_at = '2026-06-01T11:00Z'
         from public.care_authorizations where id = '{uid(205)}')
    and (select count(*) = 5 from public.care_authorizations where id::text like '{U}%')
    and (select count(*) = 4 from public.appointment_lifecycle_events where id::text like '{U}%')
    and (select bool_and(lifecycle_state = case id when '{uid(104)}'::uuid then 'CONFIRMED'
                                                    when '{uid(105)}'::uuid then 'NO_SHOW' else 'COMPLETED' end)
         from public.appointments where id::text like '{U}%')
)::text as reconciled;
"""

NO_AUTHORIZATION = 'M3 refused: a COMPLETED Appointment does not have exactly one Appointment Care Authorization'
NO_EVENT = 'M3 refused: a COMPLETED Appointment does not have exactly one completion Lifecycle Event'
ALREADY_ENDED = 'M3 refused: a COMPLETED Appointment already has an ENDED Care Authorization'
INCOHERENT_TIME = 'M3 refused: a completion time cannot end its Care Authorization coherently'

# (label, planted rows, expected refusal). Two terminal Events for one
# Appointment cannot exist (appointment_lifecycle_events_terminal_key).
GUARD_CASES = [
    ('a COMPLETED Appointment without authorization', appointment(1, 'COMPLETED') + event(1, 'COMPLETED'), NO_AUTHORIZATION),
    ('a COMPLETED Appointment without completion Event', appointment(1, 'COMPLETED') + authorization(1), NO_EVENT),
    ('a COMPLETED Appointment whose authorization is already ENDED', completed(1, ca_state='ENDED'), ALREADY_ENDED),
    ('a completion before the grant',
     appointment(1, 'COMPLETED') + authorization(1, granted='2026-07-01Z') + event(1, 'COMPLETED', '2026-06-01T11:00Z'),
     INCOHERENT_TIME),
    ('a completion in the future', completed(1, at='2099-01-01Z'), INCOHERENT_TIME),
]

AT_M2 = """select (to_regprocedure('public.create_appointment_clinical_entry(uuid,uuid,uuid,text,text,text,timestamptz,boolean)') is not null
    and (select pg_get_constraintdef(oid) not like '%APPOINTMENT_COMPLETED%' from pg_constraint
         where conname = 'care_authorizations_ended_reason_check')
    and not exists (select 1 from supabase_migrations.schema_migrations where version = '20261114090000'))::text;"""
M3_APPLIED = """select ((select pg_get_constraintdef(oid) like '%APPOINTMENT_COMPLETED%' from pg_constraint
         where conname = 'care_authorizations_ended_reason_check')
    and exists (select 1 from supabase_migrations.schema_migrations where version = '20261114090000'))::text;"""


def supabase(*arguments):
    command = ['npx', 'supabase', *arguments]
    completed_run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=900,
                                   shell=sys.platform == 'win32')
    if completed_run.returncode:
        raise HarnessFailure(f"{' '.join(command)} failed:\n{completed_run.stdout}\n{completed_run.stderr}")
    print(f"OK {' '.join(command)}", flush=True)


def m3_body():
    source = M3.read_text(encoding='utf-8')
    if not re.search(r'^begin;$', source, re.M) or not re.search(r'^commit;\s*\Z', source, re.M):
        raise HarnessFailure('M3 must be one explicit transaction')
    return re.sub(r'^commit;\s*\Z', '', re.sub(r'^begin;$', '', source, count=1, flags=re.M), flags=re.M)


# The referenced rows exist: the reconciliation updates planted authorizations,
# and an update re-checks the foreign keys of rows inserted in the same
# transaction.
BASE = (f"insert into public.users (id) values ('{uid(3)}');\n"
        f"insert into public.veterinary_organizations (id, display_name) values ('{uid(4)}', 'M3 guard Org');\n"
        f"insert into public.clinics (id, organization_id) values ('{uid(2)}', '{uid(4)}');\n"
        f"insert into public.pets (id, name, species, created_at) values ('{uid(1)}', 'M3 guard Pet', 'Dog', '2020-01-01Z');\n"
        f"insert into public.guardianships (id, user_id, pet_id, effective_start) values "
        f"('{uid(5)}', '{uid(3)}', '{uid(1)}', '2020-01-01Z');\n")


def planted(rows):
    return ('begin;\nset local session_replication_role = replica;\n' + BASE + rows
            + 'set local session_replication_role = origin;\n')


def main():
    supabase('db', 'reset', '--local', '--version', M2_VERSION)
    client = LocalSql()
    if client.require_success(AT_M2, 'M2 state') != 'true':
        raise HarnessFailure('The local database is not at the M2 state')
    body = m3_body()

    result = client.execute(planted(RECONCILIATION_ROWS) + body + '\n' + RECONCILIATION_CHECK + 'rollback;\n')
    if result.returncode or 'ERROR' in result.stderr:
        raise HarnessFailure('M3 reconciliation failed:\n' + result.stderr)
    if result.stdout.strip().splitlines()[-1] != 'true':
        raise HarnessFailure('M3 reconciliation produced unexpected rows:\n' + result.stdout)
    if 'M3 reconciliation: 2 ACTIVE Care Authorization(s)' not in result.stderr:
        raise HarnessFailure('M3 reconciliation did not report exactly two ended authorizations:\n' + result.stderr)
    print('PASS reconciliation: only the two ACTIVE authorizations of COMPLETED Appointments ended, at their '
          'completion times; REVOKED, open and NO_SHOW-ended ones untouched; nothing created', flush=True)

    for label, rows, refusal in GUARD_CASES:
        result = client.execute(planted(rows) + body + '\nrollback;\n')
        if result.returncode == 0 or not re.search(r'^ERROR:\s+55000:\s+' + re.escape(refusal), result.stderr, re.M):
            raise HarnessFailure(f'M3 did not refuse {label}:\n{result.stderr}')
        if client.require_success(AT_M2, f'M2 state after {label}') != 'true':
            raise HarnessFailure(f'The refused M3 changed the schema ({label})')
        print(f'REFUSED {label}: {refusal}', flush=True)

    clean = client.execute('begin;\n' + body + '\nrollback;\n')
    if clean.returncode or 'ERROR' in clean.stderr or 'M3 reconciliation: 0 ACTIVE' not in clean.stderr:
        raise HarnessFailure('M3 failed on a clean M2 database:\n' + clean.stderr)
    print('PASS a clean M2 database accepts the M3 body with nothing to reconcile (rolled back)', flush=True)

    supabase('migration', 'up', '--local')
    if client.require_success(M3_APPLIED, 'M3 applied') != 'true':
        raise HarnessFailure('M3 was not applied by migration up')
    print(f'reconciliation verified; {len(GUARD_CASES)}/{len(GUARD_CASES)} unexpected states refused; M3 applied afterwards',
          flush=True)


if __name__ == '__main__':
    main()

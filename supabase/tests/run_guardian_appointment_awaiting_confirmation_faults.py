"""Reproducible LOCAL-only SPEC-APT-011 BR-37/BR-40 awaiting_clinic_confirmation mutation regression.
Run from repository root after a clean local reset (all suites are run by
run_all_sql_suites.py). Named assertion failures are required; infrastructure
errors never count as caught mutants. Session rollback/restoration is verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

MIGRATION = 'supabase/migrations/20261118090000_guardian_appointment_awaiting_clinic_confirmation.sql'
SUITE = 'supabase/tests/guardian_appointment_awaiting_confirmation_spec_apt_011_019.sql'


def definition(migration, name):
    """One function of the migration, as a `create or replace` candidate."""
    start = migration.index(f'create function public.{name}(')
    body = migration[start:]
    body = body[:body.index('\n$$;\n') + len('\n$$;\n')]
    return body.replace('create function', 'create or replace function', 1)


PROJECTION = 'project_guardian_appointments'
AWAITING = ("        appointment.lifecycle_state = 'REQUESTED'\n"
            "            and source_proposal.proposing_context is not distinct from 'CLINIC'\n")

# (name, replacement of the awaiting expression, first failing assertion)
FAULTS = [
    ('awaiting whatever the lifecycle state',
     "        true\n            and source_proposal.proposing_context is not distinct from 'CLINIC'\n",
     'A Guardian cancellation ends it and moves it to History'),
    ('awaiting for every request',
     "        appointment.lifecycle_state = 'REQUESTED'\n",
     'A plain request is not awaiting'),
    ('awaiting while a Clinic proposal is pending',
     "        appointment.lifecycle_state = 'REQUESTED'\n"
     "            and pending_proposal.proposing_context is not distinct from 'CLINIC'\n",
     "A pending Clinic alternative needs the Guardian's answer and is not awaiting the Clinic"),
    ('never awaiting',
     "        false\n",
     'After the co-Guardian accepts, both Guardians see the request awaiting the Clinic'),
]


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(ROOT / SUITE)
        migration = (ROOT / MIGRATION).read_text(encoding='utf-8')
        projection = definition(migration, PROJECTION)
        candidates = [
            Fault(name, replace_once(projection, AWAITING, after), assertion)
            for name, after, assertion in FAULTS
        ]
        candidates.append(Fault(
            'awaiting from the first revision',
            replace_once(projection, 'order by revision.revision_sequence desc',
                         'order by revision.revision_sequence'),
            'After the co-Guardian accepts, both Guardians see the request awaiting the Clinic',
        ))
        client.faults(source, candidates)
        client.suite(ROOT / SUITE)
        client.verify_zero_fixtures(['d0140000-'])


if __name__ == '__main__':
    main()

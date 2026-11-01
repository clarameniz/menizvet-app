"""Reproducible LOCAL-only SPEC-APT-011 §13 (paged Guardian Appointment reads) mutation regression.
Run from repository root after a clean local reset (all suites are run by
run_all_sql_suites.py). Named assertion failures are required; infrastructure
errors never count as caught mutants. Session rollback/restoration is verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

# The deployed definitions: 20261118090000 re-created all three functions.
MIGRATION = 'supabase/migrations/20261118090000_guardian_appointment_awaiting_clinic_confirmation.sql'
SUITE = 'supabase/tests/guardian_appointment_paged_reads_spec_apt_011.sql'


def definition(migration, name):
    """One function of the migration, as a `create or replace` candidate."""
    start = migration.index(f'create function public.{name}(')
    body = migration[start:]
    body = body[:body.index('\n$$;\n') + len('\n$$;\n')]
    return body.replace('create function', 'create or replace function', 1)


ACTIVE = 'get_guardian_active_appointments'
HISTORY = 'get_guardian_appointment_history'
PROJECTION = 'project_guardian_appointments'

# (function, name, before, after, first failing assertion)
FAULTS = [
    (ACTIVE, 'skip the authentication check',
     "    if auth.uid() is null then", "    if false then",
     'Anonymous fails with 28000 before validation'),
    (ACTIVE, 'accept an unknown Active rank',
     "or (p_after_rank is not null and p_after_rank not in (1, 2))", "or false",
     'Active validation'),
    (HISTORY, 'accept a partial cursor',
     "or num_nulls(p_before_start_at, p_before_id) not in (0, 2)", "or false",
     'History validation'),
    (ACTIVE, 'ignore whose Guardianship it is',
     "where guardianship.user_id = acting_user_id", "where true",
     'Active equals the guarded union at page size 1'),
    (ACTIVE, 'keep ended Guardianships',
     "where guardianship.user_id = acting_user_id\n                and guardianship.effective_end is null",
     "where guardianship.user_id = acting_user_id\n                and true",
     'User 3 equals the guarded union at page size 1'),
    (HISTORY, 'ignore whose Guardianship it is',
     "where guardianship.user_id = acting_user_id", "where true",
     'History equals the guarded union at page size 1'),
    (ACTIVE, 'include a terminal state',
     "where appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED')",
     "where appointment.lifecycle_state in ('REQUESTED', 'CONFIRMED', 'CANCELLED')",
     'Active equals the guarded union at page size 1'),
    (ACTIVE, 'rank by the first revision',
     "order by revision.revision_sequence desc", "order by revision.revision_sequence",
     'Active equals the guarded union at page size 1'),
    (ACTIVE, 'drop the id tie-breaker among future rows',
     "(ranked.scheduled_start_at, ranked.appointment_id)\n                            > (p_after_start_at, p_after_id)",
     "ranked.scheduled_start_at > p_after_start_at",
     'Active equals the guarded union at page size 1'),
    (ACTIVE, 'drop the id tie-breaker among started rows',
     "(ranked.scheduled_start_at, ranked.appointment_id)\n                   < (p_after_start_at, p_after_id)",
     "ranked.scheduled_start_at < p_after_start_at",
     'Active equals the guarded union at page size 1'),
    (ACTIVE, 'cut started rows oldest first',
     "case when ranked.rank = 2 then ranked.scheduled_start_at end desc,",
     "case when ranked.rank = 2 then ranked.scheduled_start_at end,",
     'Active equals the guarded union at page size 1'),
    (HISTORY, 'drop the id tie-breaker',
     "(current_revision.scheduled_start_at, appointment.id)\n                 < (p_before_start_at, p_before_id)",
     "current_revision.scheduled_start_at < p_before_start_at",
     'History equals the guarded union at page size 1'),
    (PROJECTION, 'project the first revision',
     "order by revision.revision_sequence desc", "order by revision.revision_sequence",
     'Active Appointment returned twice'),
    (PROJECTION, 'project a non-actionable proposal',
     "          and public.appointment_reschedule_proposal_is_actionable(\n              open_proposal.id,\n              statement_timestamp()\n          )\n",
     "\n",
     'Active equals the guarded union at page size 1'),
]


def main():
    client = LocalSql()
    with client.restored():
        source = client.suite(ROOT / SUITE)
        migration = (ROOT / MIGRATION).read_text(encoding='utf-8')
        candidates = [
            Fault(f'{function}: {name}', replace_once(definition(migration, function), before, after), assertion)
            for function, name, before, after, assertion in FAULTS
        ]
        candidates.append(Fault(
            'grant the Active read to anon',
            'grant execute on function public.get_guardian_active_appointments(integer, timestamptz, uuid, integer) to anon;',
            'Grants: authenticated only; the projection is executable by no client',
        ))
        candidates.append(Fault(
            'grant the projection to authenticated',
            'grant execute on function public.project_guardian_appointments(uuid[]) to authenticated;',
            'Grants: authenticated only; the projection is executable by no client',
        ))
        client.faults(source, candidates)
        client.suite(ROOT / SUITE)
        client.verify_zero_fixtures(['d0130000-'])


if __name__ == '__main__':
    main()

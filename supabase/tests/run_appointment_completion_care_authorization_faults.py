"""Reproducible LOCAL-only mutation regression for stage M3: completion ends
the Appointment Care Authorization (SPEC-MED-010 BR-16 and §6, SPEC-APT-009 as
superseded by it, SPEC-ACC-002 BR-46).

Run from the repository root after a clean local reset. Each behavioural
mutant replaces deployed definitions (or one constraint) inside the
rollback-only suite transaction and must be caught by its named assertion;
infrastructure errors never count. A mutant of the operation is paired with the
structural backstop that would otherwise reject it at commit, so the
operation's own observable outcome is what the assertion catches; each
backstop is also mutated alone. Session rollback/restoration and zero retained
fixtures are verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, HarnessFailure, LocalSql, ROOT

SUITE = ROOT / 'supabase/tests/appointment_completion_spec_apt_009.sql'
SIGNATURES = {
    'COMPLETE': 'public.complete_appointment(uuid, integer)',
    'CA_COHERENCE': 'public.assert_care_authorization_appointment_coherence(uuid)',
    'APPOINTMENT_COHERENCE': 'public.assert_appointment_care_authorization_coherence(uuid)',
    'IMMUTABILITY': 'public.enforce_care_authorization_immutability()',
}

ENDED_BY_COMPLETION = ('Case 40: a current Veterinarian Assignment neither blocks nor changes with completion')
REVOKED_KEPT = 'Case 67: completing an Appointment whose authorization is REVOKED keeps the revocation, its actor, time and reason'
STRUCTURAL = ('Cases 71–75: a COMPLETED Appointment never keeps an ACTIVE authorization; APPOINTMENT_COMPLETED requires '
              'the COMPLETED state and the completion time; an ended authorization is never reactivated or re-labelled')

ENDING = ("    if care_auth_record.lifecycle_state = 'ACTIVE' then\n"
          "        update public.care_authorizations\n"
          "        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,\n"
          "            ended_reason = 'APPOINTMENT_COMPLETED'\n"
          "        where id = care_auth_record.id;\n"
          "    end if;\n")
ACTIVE_RULE = "    if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED', 'COMPLETED')\n"
TIME_RULE = '    if not found or terminal_effective_at is distinct from care_auth_record.ended_at then\n'
STATE_RULE = '    if not found or expected_appointment_state <> expected_terminal_state then\n'
TERMINAL_RULE = "    if old.lifecycle_state <> 'ACTIVE' then\n"

REVOCATION_REWRITTEN = """    if care_auth_record.lifecycle_state in ('ACTIVE', 'REVOKED') then
        update public.care_authorizations
        set lifecycle_state = 'ENDED', ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_COMPLETED',
            revoked_at = null, revoking_user_id = null, revocation_reason = null
        where id = care_auth_record.id;
    end if;
"""

# (name, [(function, [(before, after)])], expected assertion)
FAULTS = [
    ('completion leaves the authorization ACTIVE (operation and backstop)',
     [('COMPLETE', [(ENDING, '')]),
      ('APPOINTMENT_COHERENCE', [(ACTIVE_RULE, "    if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED')\n")])],
     ENDED_BY_COMPLETION),
    ('authorization ended at a time other than the completion (operation and backstop)',
     [('COMPLETE', [(ENDING, ENDING.replace('ended_at = operation_timestamp', "ended_at = operation_timestamp + interval '1 second'"))]),
      ('CA_COHERENCE', [(TIME_RULE, '    if false then\n')])],
     ENDED_BY_COMPLETION),
    ('authorization ended with another context (operation and backstop)',
     [('COMPLETE', [(ENDING, ENDING.replace("ended_reason = 'APPOINTMENT_COMPLETED'", "ended_reason = 'APPOINTMENT_CANCELLED'"))]),
      ('CA_COHERENCE', [(STATE_RULE, '    if false then\n'), (TIME_RULE, '    if false then\n')])],
     ENDED_BY_COMPLETION),
    ('completion rewrites a revocation as a normal end (operation and immutability)',
     [('COMPLETE', [(ENDING, REVOCATION_REWRITTEN)]),
      ('IMMUTABILITY', [(TERMINAL_RULE, "    if old.lifecycle_state not in ('ACTIVE', 'REVOKED') then\n")])],
     REVOKED_KEPT),
    ('COMPLETED may keep an ACTIVE authorization (backstop alone)',
     [('APPOINTMENT_COHERENCE', [(ACTIVE_RULE, "    if appointment_record.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED')\n")])],
     STRUCTURAL),
    ('completion ending time not checked (backstop alone)',
     [('CA_COHERENCE', [(TIME_RULE, '    if false then\n')])], STRUCTURAL),
    ('APPOINTMENT_COMPLETED accepted in any Appointment state (backstop alone)',
     [('CA_COHERENCE', [(STATE_RULE, '    if false then\n')])], STRUCTURAL),
    ('ended authorization modifiable (immutability alone)',
     [('IMMUTABILITY', [(TERMINAL_RULE, '    if false then\n')])], STRUCTURAL),
]

EXTRA = [
    Fault('ending context constraint dropped',
          'alter table public.care_authorizations drop constraint care_authorizations_ended_reason_check;\n', STRUCTURAL),
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
        print(f'{len(candidates)}/{len(candidates)} completion Care Authorization mutation assertions observed', flush=True)
        client.verify_zero_fixtures(['c0a90000-'])


if __name__ == '__main__':
    main()

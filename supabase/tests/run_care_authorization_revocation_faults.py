"""Reproducible LOCAL-only mutation regression for Guardian Appointment Medical
Access Revocation (SPEC-ACC-002 §16/§17, SPEC-APT-011 BR-35) and its clinical
effects under SPEC-MED-010 BR-11, BR-12 and BR-14 (revocation ends prior-history
access only; documentation access is independent of the Care Authorization).

Run from the repository root after a clean local reset. Each behavioural
mutant replaces one deployed function (or one grant) inside the rollback-only
suite transaction and must be caught by its named assertion; infrastructure
errors never count. Session rollback/restoration and zero retained fixtures are
verified.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import Fault, LocalSql, ROOT, replace_once

SUITE = ROOT / 'supabase/tests/guardian_appointment_medical_access_revocation_spec_acc_002.sql'

REVOKE = 'revoke_my_appointment_care_authorization'
READ = 'get_pet_appointments'
RECORD_READ = 'view_appointment_clinical_record'
ENTRY = 'create_appointment_clinical_entry'
EDIT = 'edit_appointment_clinical_entry'
WINDOW = 'appointment_professional_history_accessible'
HISTORY = 'view_appointment_professional_medical_history'
SIGNATURES = {
    REVOKE: 'public.revoke_my_appointment_care_authorization(uuid)',
    READ: 'public.get_pet_appointments(uuid)',
    RECORD_READ: 'public.view_appointment_clinical_record(uuid, uuid)',
    ENTRY: 'public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)',
    EDIT: 'public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)',
    WINDOW: 'public.appointment_professional_history_accessible(uuid, timestamptz)',
    HISTORY: 'public.view_appointment_professional_medical_history(uuid, uuid, integer, timestamptz, uuid)',
}

CONTRACT = 'REV contract: the revoke is SECURITY DEFINER, VOLATILE, empty search_path, authenticated-only, one signature'
GENERIC = ('REV contract: the generic revoke operations and the CLINICAL_INTAKE grant are not client-executable; '
           'service_role keeps them')
UNIFORM = ("REV authority: another Pet's Guardian, a former Guardian, staff, an unknown and a foreign Appointment "
           'are refused alike')
REVOKED_BY_APPOINTMENT = "REV revoke: a current Guardian revokes a confirmed Appointment's authorization by the Appointment alone"
APPOINTMENT_UNCHANGED = 'REV revoke: the Appointment, its schedule and lifecycle history are unchanged'
EXACT_REPLAY = 'REV replay: an exact retry reconciles to ALREADY_INACTIVE and rewrites nothing'
PRECONDITION = ('REV precondition: the documentation states are as intended, every authorization ACTIVE except '
                'those ended by completion')
COMPLETED_RECONCILED = ('REV lifecycle: REQUESTED and CONFIRMED-after-start authorizations are revocable by any '
                        'current Guardian; a COMPLETED one was already ended and reconciles to ALREADY_INACTIVE '
                        '(SPEC-MED-010 BR-16); the lifecycle stays')
ENDED_REPLAY = ('REV replay: an authorization ended by cancellation, no-show or expiry reconciles to ALREADY_INACTIVE '
                'and stays ENDED')
NO_PRIOR_HISTORY = 'REV lifecycle: no prior history is readable after revocation (SPEC-MED-010 BR-14)'
READ_ACTIVE = ('REV read: medical_access_state is ACTIVE in every lifecycle while the authorization is ACTIVE '
               'and INACTIVE once completion ended it, for every current Guardian')
READ_AFTER = ('REV read: revoked Appointments stay visible as REVOKED, ended ones are INACTIVE, the same for every '
              'Guardian, with no authorization id')
CLINICAL_UNCHANGED = 'REV clinical: revocation deletes and rewrites no Entry, Amendment or audit event'
HISTORY_DENIED = ('REV clinical: professional longitudinal history is denied after revocation, before and after '
                  'documentation began')
CONTINUITY = ('REV clinical: revocation removes no documentation access; recording and editing never restore the '
              'authorization')

AUTHORITY_STEP = '    -- 3. Guardian authority before any target: the Appointment is resolved\n'
EXISTENCE_FIRST = """    if not exists (select 1 from public.appointments as leaked where leaked.id = p_appointment_id) then
        raise exception 'Appointment does not exist' using errcode = '23503';
    end if;
"""
JOIN_PET = '      on guardianship.pet_id = appointment.pet_id\n'
LOCK_PET = '    where guardianship.pet_id = target_pet_id\n'
JOIN_CURRENT = '     and guardianship.effective_end is null\n    where appointment.id = p_appointment_id\n'
LOCK_CURRENT = '      and guardianship.effective_end is null\n    for update;\n'
REVOKED_RETURN = "    return jsonb_build_object('outcome', 'REVOKED');\n"
RECONCILE = ("    if care_auth_record.lifecycle_state <> 'ACTIVE' then\n"
             "        return jsonb_build_object('outcome', 'ALREADY_INACTIVE');\n"
             "    end if;\n")
WRITER = ("    perform public.revoke_care_authorization_after_guardianship_lock(\n"
          "        care_auth_record.id, acting_user_id, null\n"
          "    );\n")
CANCEL_TOO = "    perform public.cancel_appointment(target_appointment_id, 'GUARDIAN', null, null);\n"
# Either the change is applied (and the clinical facts differ) or the integrity
# triggers refuse it (and the revocation of a documented Appointment fails):
# the same named assertion must catch both.
ENTRIES_DELETED = """    delete from public.clinical_record_entries as doomed
    where doomed.appointment_id = target_appointment_id;
"""
ENTRIES_REWRITTEN = """    update public.clinical_record_entries as rewritten
    set clinical_content = 'Access withdrawn'
    where rewritten.appointment_id = target_appointment_id;
"""
ASSIGNMENT_ENDED = """    update public.appointment_veterinarian_assignments as stopped
    set effective_end = clock_timestamp()
    where stopped.appointment_id = target_appointment_id and stopped.effective_end is null;
    set constraints all immediate;
"""
READ_STATE = ("        case appointment_care_auth.lifecycle_state\n"
              "            when 'ACTIVE' then 'ACTIVE'\n"
              "            when 'REVOKED' then 'REVOKED'\n"
              "            else 'INACTIVE'\n"
              "        end\n")
READ_REVOKED = "            when 'REVOKED' then 'REVOKED'\n"
WINDOW_ACTIVE = "        select care_auth.lifecycle_state = 'ACTIVE'\n"
HISTORY_WINDOW = '       or not public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp()) then\n'
DOCUMENTATION_REOPENS = """       or not (public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp())
               or exists (select 1 from public.clinical_record_entries as own
                          where own.appointment_id = appointment_record.id
                            and own.created_by_user_id = acting_user_id)) then
"""
RECORD_READ_STEP = '    -- Advisory documentation state (BR-20); every write re-validates.\n'
ENTRY_KEY_STEP = '    -- 2. Key.\n'
EDIT_AUTHOR_STEP = "    -- 4. Only the Entry's own author edits it (BR-18).\n"
ENTRY_CREATED = "    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id);\n"


def requires_active(appointment):
    return (f"    if exists (select 1 from public.care_authorizations as required\n"
            f"               where required.appointment_id = {appointment} and required.lifecycle_state <> 'ACTIVE') then\n"
            f"        raise exception 'Clinical record unavailable' using errcode = '42501';\n"
            f"    end if;\n")


READ_REQUIRES_ACTIVE = """    if exists (select 1 from public.care_authorizations as required
               where required.appointment_id = appointment_record.id and required.lifecycle_state <> 'ACTIVE') then
        return jsonb_build_object('status', 'DENIED');
    end if;
"""
RESTORES_AUTHORIZATION = """    update public.care_authorizations
    set lifecycle_state = 'ACTIVE', revoked_at = null, revoking_user_id = null, revocation_reason = null
    where appointment_id = appointment_record.id and lifecycle_state = 'REVOKED';
"""

# (name, function, [(before, after)], expected assertion)
FAULTS = [
    ('Appointment existence checked before Guardian authority', REVOKE,
     [(AUTHORITY_STEP, EXISTENCE_FIRST + AUTHORITY_STEP)], UNIFORM),
    ('foreign Guardian accepted (Guardianship of any Pet)', REVOKE,
     [(JOIN_PET, '      on true\n'), (LOCK_PET, '    where true\n')], UNIFORM),
    ('former Guardian accepted (ended Guardianship)', REVOKE,
     [(JOIN_CURRENT, '    where appointment.id = p_appointment_id\n'), (LOCK_CURRENT, '    for update;\n')], UNIFORM),
    ('Appointment cancelled during revoke', REVOKE, [(REVOKED_RETURN, CANCEL_TOO + REVOKED_RETURN)],
     APPOINTMENT_UNCHANGED),
    ('revocation reported but not written', REVOKE, [(WRITER, '')], REVOKED_BY_APPOINTMENT),
    ('Care Authorization id leaked in the result', REVOKE,
     [(REVOKED_RETURN, "    return jsonb_build_object('outcome', 'REVOKED', 'care_authorization_id', "
                       "care_auth_record.id);\n")], REVOKED_BY_APPOINTMENT),
    ('replay raises instead of reconciling', REVOKE, [(RECONCILE, '')], EXACT_REPLAY),
    ('ENDED authorization not reconciled', REVOKE,
     # Caught first since M3: the COMPLETED Appointment's authorization is
     # already ENDED with APPOINTMENT_COMPLETED when the Guardian revokes.
     [(RECONCILE, RECONCILE.replace("<> 'ACTIVE' then", "= 'REVOKED' then"))], COMPLETED_RECONCILED),
    ('Entries deleted on revocation', REVOKE, [(REVOKED_RETURN, ENTRIES_DELETED + REVOKED_RETURN)], CLINICAL_UNCHANGED),
    ('Entries rewritten on revocation', REVOKE, [(REVOKED_RETURN, ENTRIES_REWRITTEN + REVOKED_RETURN)], CLINICAL_UNCHANGED),
    ('Veterinarian assignment ended on revocation', REVOKE,
     [(REVOKED_RETURN, ASSIGNMENT_ENDED + REVOKED_RETURN)], CLINICAL_UNCHANGED),
    ('Care Authorization id leaked in the Guardian read', READ,
     [(READ_STATE, '        appointment_care_auth.id::text\n')], READ_ACTIVE),
    ('revocation hidden in the Guardian read (reported INACTIVE)', READ, [(READ_REVOKED, '')], READ_AFTER),
    # Caught first since M3: the precondition reads the record of a COMPLETED
    # Appointment, whose authorization completion already ended.
    ('clinical record read closed by revocation', RECORD_READ,
     [(RECORD_READ_STEP, READ_REQUIRES_ACTIVE + RECORD_READ_STEP)], PRECONDITION),
    ('recording closed by revocation', ENTRY,
     [(ENTRY_KEY_STEP, requires_active('appointment_record.id') + ENTRY_KEY_STEP)], CONTINUITY),
    ('editing closed by revocation', EDIT,
     [(EDIT_AUTHOR_STEP, requires_active('p_appointment_id') + EDIT_AUTHOR_STEP)], CONTINUITY),
    ('recording restores the revoked authorization', ENTRY,
     [(ENTRY_CREATED, RESTORES_AUTHORIZATION + ENTRY_CREATED)], CONTINUITY),
    ('professional history readable after revocation', WINDOW,
     [(WINDOW_ACTIVE, "        select care_auth.lifecycle_state in ('ACTIVE', 'REVOKED')\n")], NO_PRIOR_HISTORY),
    ('documenting after revocation reopens prior history', HISTORY,
     [(HISTORY_WINDOW, DOCUMENTATION_REOPENS)], HISTORY_DENIED),
]

EXTRA = [
    Fault('generic Appointment revoke still client-executable',
          'grant execute on function public.revoke_appointment_care_authorization(uuid, text) to authenticated;\n',
          GENERIC),
    Fault('generic Care Authorization revoke still client-executable',
          'grant execute on function public.revoke_pet_care_authorization(uuid, text) to authenticated;\n', GENERIC),
    Fault('deferred CLINICAL_INTAKE grant still client-executable',
          'grant execute on function public.grant_pet_care_authorization(uuid, uuid) to authenticated;\n', GENERIC),
    Fault('revoke executable by anon',
          'grant execute on function public.revoke_my_appointment_care_authorization(uuid) to anon;\n', CONTRACT),
    Fault('revoke executable by service_role',
          'grant execute on function public.revoke_my_appointment_care_authorization(uuid) to service_role;\n', CONTRACT),
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
        print(f'{len(candidates)}/{len(candidates)} medical access revocation mutation assertions observed', flush=True)
        client.verify_zero_fixtures(['d0370000-'])


if __name__ == '__main__':
    main()

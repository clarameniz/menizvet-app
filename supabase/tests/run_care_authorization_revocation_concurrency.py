"""LOCAL-only multi-session races for Guardian Appointment Medical Access
Revocation (SPEC-ACC-002 BR-46, BR-51, BR-54, BR-57–BR-61; SPEC-MED-010 BR-11,
BR-16, BR-26: documentation and revocation do not interact; completion ends an
ACTIVE authorization and keeps a REVOKED one).

Same discipline as run_professional_history_concurrency.py, whose race
primitives this reuses: a synthetic fixture (prefix d0372000-) is committed to
the isolated local database, the real Guardian revoke races a real reader or
writer in two psql sessions (the first observed holding its locks, the second
observed blocked on a lock before the first commits), and every fixture row
and every row the operations created is always deleted afterwards, with
restoration and zero retained fixture rows verified. A deadlock would surface
as ERR:40P01 and fail the exact outcome checks. Each race must end in one
coherent serial outcome: no resurrection, no duplicate Lifecycle Event, and
the clinical record preserved. Recording and editing take no lock that the
revocation takes; those pairs run as overlapping transactions that must not
block each other. Never point this at a shared database.
"""
import json
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql
from run_staff_invitation_concurrency import check, race
from run_clinical_record_concurrency import overlap


def fid(kind, n):
    return f'd0372000-0000-4000-8000-{kind * 100 + n:012d}'


ORG, CLINIC = fid(3, 1), fid(4, 1)
PET, GUARDIANSHIP, CO_GUARDIANSHIP = fid(9, 1), fid(9, 2), fid(9, 3)
GUARDIAN, CO_GUARDIAN, ADMIN, VET = fid(1, 1), fid(1, 2), fid(1, 5), fid(1, 10)  # Auth subjects
FUTURE = [7, 8, 9, 10, 13, 14]        # CONFIRMED, start 2099
LAPSED = {15: '2026-01-15T10:00Z', 16: '2026-03-15T10:00Z'}  # REQUESTED, start passed
APPOINTMENTS = range(1, 20)


def appt(n):
    return fid(11, n)


def ca(n):
    return fid(12, n)


def start_of(n):
    if n in FUTURE:
        return '2099-01-01T10:00Z'
    return LAPSED.get(n, '2026-06-01T10:00Z')


REVISIONS = ',\n'.join(
    f"('{appt(n)}', {r}, '{'REQUESTED' if r == 1 else 'CONFIRMED'}', '{start_of(n)}', "
    f"'{start_of(n)}'::timestamptz + interval '30 minutes', 'Europe/Madrid', "
    f"'{fid(2, 1) if r == 1 else fid(2, 5)}', null, "
    f"'{'2026-01-01T00:00Z' if r == 1 else '2026-02-01T00:00Z'}')"
    for n in APPOINTMENTS for r in (1, 2) if r == 1 or n not in LAPSED)

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0372000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'revoke-race-' || n || '@example.test', now()
from unnest(array[1, 2, 5, 10]) n;
insert into public.users (id)
select ('d0372000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 2, 5, 10]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0372000-0000-4000-8000-' || lpad((1900 + n)::text, 12, '0'))::uuid,
    ('d0372000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0372000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, 5, 10]) n;
insert into public.user_profiles (user_id, display_name) values ('{fid(2, 10)}', 'Race Ana');
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'Revoke Race Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values ('{CLINIC}', '{ORG}', true, 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0372000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{ORG}',
    ('d0372000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[5, 10]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0372000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0372000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 5 then 'ADMINISTRATOR' else 'VETERINARIAN' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 5)}'
from unnest(array[5, 10]) n;
insert into public.veterinarian_professional_profiles (id, user_id) values ('{fid(7, 10)}', '{fid(2, 10)}');
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values ('{fid(8, 10)}', '{fid(7, 10)}', '{fid(5, 10)}', '{CLINIC}', '2020-01-01Z');
insert into public.pets (id, name, species, created_at) values ('{PET}', 'Revoke Race Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values
    ('{GUARDIANSHIP}', '{fid(2, 1)}', '{PET}', '2020-01-01Z'), ('{CO_GUARDIANSHIP}', '{fid(2, 2)}', '{PET}', '2020-01-01Z');
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select ('d0372000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{fid(2, 1)}',
    'Revoke race visit ' || n, case when n in (15, 16) then 'REQUESTED' else 'CONFIRMED' end,
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 19) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at,
    scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
values {REVISIONS};
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select ('d0372000-0000-4000-8000-' || lpad((1200 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{ORG}', '{GUARDIANSHIP}',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE',
    ('d0372000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'ACTIVE'
from generate_series(1, 19) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select ('d0372000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'REQUESTED', 'CONFIRMED', '{fid(2, 5)}',
    'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(1, 19) n where n not in (15, 16);
-- Ana is the assigned Veterinarian of 3–6 (one slot, so the periods are data).
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select ('d0372000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{fid(8, 10)}', '2026-03-01Z', '{fid(2, 5)}'
from generate_series(3, 6) n;
set local session_replication_role = origin;
select public.establish_organization_subscription('{ORG}', null, 'ACTIVE', '2020-01-01Z', null, null,
    'revoke-race', '{fid(20, 1)}', null);
commit;
"""

APPOINTMENT_FILTER = "appointment_id::text like 'd0372000-%'"
ENTRY_FILTER = (f"clinical_record_entry_id in (select e.id from public.clinical_record_entries e "
                f"join public.appointments a on a.id = e.appointment_id where a.pet_id = '{PET}')")
CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.medical_access_audit_events where pet_id = '{PET}';
delete from public.clinical_amendments where original_{ENTRY_FILTER};
delete from public.clinical_attachments where {ENTRY_FILTER};
delete from public.clinical_record_entries where {APPOINTMENT_FILTER};
delete from public.communication_delivery_attempts where communication_id in
    (select id from public.transactional_communications where {APPOINTMENT_FILTER});
delete from public.communication_delivery_jobs where communication_id in
    (select id from public.transactional_communications where {APPOINTMENT_FILTER});
delete from public.transactional_communications where {APPOINTMENT_FILTER};
delete from public.appointment_lifecycle_events where {APPOINTMENT_FILTER};
delete from public.appointment_veterinarian_assignments where {APPOINTMENT_FILTER};
delete from public.appointment_reschedule_proposals where {APPOINTMENT_FILTER};
delete from public.appointment_schedule_revisions where {APPOINTMENT_FILTER};
delete from public.care_authorizations where pet_id = '{PET}';
delete from public.appointments where pet_id = '{PET}';
delete from public.subscription_state_transitions where subscription_id in
    (select id from public.organization_subscriptions where organization_id = '{ORG}');
delete from public.subscription_provider_references where subscription_id in
    (select id from public.organization_subscriptions where organization_id = '{ORG}');
delete from public.organization_subscriptions where organization_id = '{ORG}';
delete from public.guardianships where pet_id = '{PET}';
delete from public.pets where id = '{PET}';
delete from public.veterinarian_clinic_assignments where clinic_id = '{CLINIC}';
delete from public.veterinarian_professional_profiles where user_id::text like 'd0372000-%';
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.clinics where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_profiles where user_id::text like 'd0372000-%';
delete from public.user_authentication_identities where id::text like 'd0372000-%';
delete from public.users where id::text like 'd0372000-%';
delete from auth.users where id::text like 'd0372000-%';
commit;
"""


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def revoke_call(subject, n):
    return as_subject(subject, f"select public.revoke_my_appointment_care_authorization('{appt(n)}')::text")


def history_call(n):
    return as_subject(VET, f"select public.view_appointment_professional_medical_history('{CLINIC}', '{appt(n)}')::text")


def record_call(n, key, content):
    return as_subject(VET, f"select public.create_appointment_clinical_entry('{CLINIC}', '{appt(n)}', '{key}', "
                           f"'CLINICAL_NOTE', '{content}', null)::text")


def edit_call(n, entry, key):
    return as_subject(VET, f"select public.edit_appointment_clinical_entry('{CLINIC}', '{appt(n)}', '{entry}', "
                           f"'{key}', 1, 'CLINICAL_NOTE', 'Corrected during the race', null)::text")


def clinic_cancel_call(n):
    return as_subject(ADMIN, f"select public.cancel_appointment('{appt(n)}', 'CLINIC', 'Clinic closed', 2)::text")


def guardian_cancel_call(n):
    return as_subject(GUARDIAN, f"select public.cancel_appointment('{appt(n)}', 'GUARDIAN', null, null)::text")


def no_show_call(n):
    return as_subject(ADMIN, f"select public.mark_appointment_no_show('{appt(n)}', 2)::text")


def complete_call(n):
    return as_subject(ADMIN, f"select public.complete_appointment('{appt(n)}', 2)::text")


def expiry_call(reference):
    return as_subject(ADMIN, f"select public.expire_lapsed_appointment_requests({reference})::text")


def outcome(result, label):
    if not result.startswith('OK:'):
        raise HarnessFailure(f'{label}: the revoke failed instead of answering: {result}')
    return json.loads(result[3:]).get('outcome')


def committed(observer, subject, statement, label):
    return observer.require_success(
        f"begin;\nselect set_config('request.jwt.claim.sub', '{subject}', true);\n{statement};\ncommit;", label
    ).splitlines()[-1].strip()


def record(observer, n, key):
    return committed(observer, VET, f"select (public.create_appointment_clinical_entry('{CLINIC}', '{appt(n)}', "
                                    f"'{key}', 'CLINICAL_NOTE', 'Visit {n} note', null) ->> 'entry_id')",
                     f'Record Entry {n}')


def state(n):
    return f"(select lifecycle_state from public.care_authorizations where id = '{ca(n)}')"


def appointment_state(n):
    return f"(select lifecycle_state from public.appointments where id = '{appt(n)}')"


def one_event(n, to_state):
    return (f"(select count(*) = 1 from public.appointment_lifecycle_events "
            f"where appointment_id = '{appt(n)}' and to_state = '{to_state}')")


def clinical_rows():
    """The Entries recorded before the races."""
    return (f"(select md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) "
            f"from public.clinical_record_entries e where e.appointment_id in ('{appt(5)}', '{appt(6)}'))")


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')
            # Appointments 3, 4: recorded during the races; 5, 6: Entries to edit.
            entries = {5: record(observer, 5, fid(16, 5)), 6: record(observer, 6, fid(16, 6))}
            finalized_before = observer.require_success(f'select {clinical_rows()};', 'Recorded Entry fingerprint')

            # 1. Guardian revoke vs professional history read, both orders.
            first, second = race(observer, history_call(1), revoke_call(GUARDIAN, 1), 'history read vs revoke')
            if json.loads(first[3:]).get('status') != 'PERMITTED' or outcome(second, 'read vs revoke') != 'REVOKED':
                raise HarnessFailure('history read vs revoke: expected a permitted page, then the revocation')
            check(observer, f"{state(1)} = 'REVOKED'", 'history read vs revoke: the revocation waits for the read and commits')
            first, second = race(observer, revoke_call(GUARDIAN, 2), history_call(2), 'revoke vs history read')
            if outcome(first, 'revoke vs read') != 'REVOKED' or json.loads(second[3:]) != {'status': 'DENIED'}:
                raise HarnessFailure('revoke vs history read: the read must wait and then be exactly DENIED')
            print('PASS revoke vs history read: the read waits, sees the revocation and is exactly DENIED', flush=True)

            # 2. Guardian revoke with "Guardar y publicar registro", both orders (BR-11, BR-26).
            first, second = overlap(observer, record_call(3, fid(16, 3), 'Recorded during revocation'),
                                    revoke_call(GUARDIAN, 3), 'Record with revoke')
            if json.loads(first[3:]).get('outcome') != 'CREATED' or outcome(second, 'record with revoke') != 'REVOKED':
                raise HarnessFailure('Record with revoke: both must succeed without waiting')
            first, second = overlap(observer, revoke_call(GUARDIAN, 4),
                                    record_call(4, fid(16, 4), 'Recorded after revocation'), 'revoke with Record')
            if outcome(first, 'revoke with record') != 'REVOKED' or json.loads(second[3:]).get('outcome') != 'CREATED':
                raise HarnessFailure('revoke with Record: documentation does not depend on the authorization')
            check(observer, f"{state(3)} = 'REVOKED' and {state(4)} = 'REVOKED' "
                  f"and (select count(*) = 2 from public.clinical_record_entries "
                  f"where appointment_id in ('{appt(3)}', '{appt(4)}'))",
                  'revoke with Record: both Entries recorded, both authorizations REVOKED')

            # 3. Guardian revoke with an edit, both orders: the author keeps editing.
            first, second = overlap(observer, edit_call(5, entries[5], fid(17, 5)), revoke_call(GUARDIAN, 5),
                                    'edit with revoke')
            if json.loads(first[3:]).get('outcome') != 'EDITED' or outcome(second, 'edit with revoke') != 'REVOKED':
                raise HarnessFailure('edit with revoke: both must succeed without waiting')
            first, second = overlap(observer, revoke_call(GUARDIAN, 6), edit_call(6, entries[6], fid(17, 6)),
                                    'revoke with edit')
            if outcome(first, 'revoke with edit') != 'REVOKED' or json.loads(second[3:]).get('outcome') != 'EDITED':
                raise HarnessFailure('revoke with edit: the author still edits after the revocation')
            check(observer, f"(select count(*) = 1 and bool_and(version_number = 2) from public.clinical_amendments "
                  f"where original_clinical_record_entry_id = '{entries[5]}') and (select count(*) = 1 and "
                  f"bool_and(version_number = 2) from public.clinical_amendments where "
                  f"original_clinical_record_entry_id = '{entries[6]}')",
                  'revoke with edit: each Entry carries exactly its one new version')

            # 4. Guardian revoke vs Clinic cancellation, both orders.
            first, second = race(observer, clinic_cancel_call(7), revoke_call(GUARDIAN, 7), 'Clinic cancel vs revoke')
            if not first.startswith('OK:') or outcome(second, 'cancel vs revoke') != 'ALREADY_INACTIVE':
                raise HarnessFailure('Clinic cancel vs revoke: cancellation ends the authorization; the revoke reconciles')
            first, second = race(observer, revoke_call(GUARDIAN, 8), clinic_cancel_call(8), 'revoke vs Clinic cancel')
            if outcome(first, 'revoke vs cancel') != 'REVOKED' or not second.startswith('OK:'):
                raise HarnessFailure('revoke vs Clinic cancel: both succeed in order')
            check(observer, f"{state(7)} = 'ENDED' and {state(8)} = 'REVOKED' "
                  f"and {appointment_state(7)} = 'CANCELLED' and {appointment_state(8)} = 'CANCELLED' "
                  f"and {one_event(7, 'CANCELLED')} and {one_event(8, 'CANCELLED')}",
                  'revoke vs Clinic cancel: one terminal authorization history and one cancellation event each')

            # 5. Guardian revoke vs the same Guardian's cancellation, both orders.
            first, second = race(observer, guardian_cancel_call(9), revoke_call(GUARDIAN, 9), 'Guardian cancel vs revoke')
            if not first.startswith('OK:') or outcome(second, 'guardian cancel vs revoke') != 'ALREADY_INACTIVE':
                raise HarnessFailure('Guardian cancel vs revoke: cancellation first, then ALREADY_INACTIVE')
            first, second = race(observer, revoke_call(GUARDIAN, 10), guardian_cancel_call(10), 'revoke vs Guardian cancel')
            if outcome(first, 'revoke vs guardian cancel') != 'REVOKED' or not second.startswith('OK:'):
                raise HarnessFailure('revoke vs Guardian cancel: both succeed in order, no deadlock')
            check(observer, f"{state(9)} = 'ENDED' and {state(10)} = 'REVOKED' "
                  f"and {one_event(9, 'CANCELLED')} and {one_event(10, 'CANCELLED')}",
                  'revoke vs Guardian cancel: coherent terminal histories, no deadlock')

            # 6. Guardian revoke vs NO_SHOW, both orders.
            first, second = race(observer, no_show_call(11), revoke_call(GUARDIAN, 11), 'no-show vs revoke')
            if not first.startswith('OK:') or outcome(second, 'no-show vs revoke') != 'ALREADY_INACTIVE':
                raise HarnessFailure('no-show vs revoke: no-show ends the authorization; the revoke reconciles')
            first, second = race(observer, revoke_call(GUARDIAN, 12), no_show_call(12), 'revoke vs no-show')
            if outcome(first, 'revoke vs no-show') != 'REVOKED' or not second.startswith('OK:'):
                raise HarnessFailure('revoke vs no-show: both succeed in order')
            check(observer, f"{state(11)} = 'ENDED' and {state(12)} = 'REVOKED' "
                  f"and {one_event(11, 'NO_SHOW')} and {one_event(12, 'NO_SHOW')}",
                  'revoke vs no-show: coherent terminal histories and one NO_SHOW event each')

            # 7. Two simultaneous revocations: two Guardians, and one Guardian twice.
            first, second = race(observer, revoke_call(GUARDIAN, 13), revoke_call(CO_GUARDIAN, 13), 'revoke vs co-Guardian revoke')
            if outcome(first, 'two Guardians') != 'REVOKED' or outcome(second, 'two Guardians') != 'ALREADY_INACTIVE':
                raise HarnessFailure('revoke vs co-Guardian revoke: one REVOKED, one ALREADY_INACTIVE')
            first, second = race(observer, revoke_call(GUARDIAN, 14), revoke_call(GUARDIAN, 14), 'revoke vs repeated revoke')
            if outcome(first, 'repeated') != 'REVOKED' or outcome(second, 'repeated') != 'ALREADY_INACTIVE':
                raise HarnessFailure('revoke vs repeated revoke: one REVOKED, one ALREADY_INACTIVE')
            check(observer, f"(select revoking_user_id = '{fid(2, 1)}' from public.care_authorizations where id = '{ca(13)}') "
                  f"and {state(14)} = 'REVOKED'",
                  'simultaneous revocations: the first revocation and its actor stay')

            # 8. Guardian revoke vs request expiry, both orders (15 lapses first, 16 later).
            first, second = race(observer, expiry_call("'2026-02-01T00:00Z'"), revoke_call(GUARDIAN, 15), 'expiry vs revoke')
            if first != 'OK:1' or outcome(second, 'expiry vs revoke') != 'ALREADY_INACTIVE':
                raise HarnessFailure('expiry vs revoke: expiry ends the authorization; the revoke reconciles')
            first, second = race(observer, revoke_call(GUARDIAN, 16), expiry_call('clock_timestamp()'), 'revoke vs expiry')
            if outcome(first, 'revoke vs expiry') != 'REVOKED' or second != 'OK:1':
                raise HarnessFailure('revoke vs expiry: both succeed in order')
            check(observer, f"{state(15)} = 'ENDED' and {state(16)} = 'REVOKED' "
                  f"and {appointment_state(15)} = 'EXPIRED' and {appointment_state(16)} = 'EXPIRED' "
                  f"and {one_event(15, 'EXPIRED')} and {one_event(16, 'EXPIRED')}",
                  'revoke vs expiry: coherent terminal histories and one EXPIRED event each')

            # 9. Completion vs Guardian revoke, both orders, and a concurrent retry
            #    (SPEC-MED-010 BR-16, SPEC-ACC-002 BR-46).
            first, second = race(observer, complete_call(17), revoke_call(GUARDIAN, 17), 'complete vs revoke')
            if not first.startswith('OK:') or outcome(second, 'complete vs revoke') != 'ALREADY_INACTIVE':
                raise HarnessFailure('complete vs revoke: completion ends the authorization; the revoke reconciles')
            check(observer, f"{state(17)} = 'ENDED' and {appointment_state(17)} = 'COMPLETED' "
                  f"and (select ended_reason = 'APPOINTMENT_COMPLETED' and revoked_at is null "
                  f"and ended_at = (select effective_at from public.appointment_lifecycle_events "
                  f"where appointment_id = '{appt(17)}' and to_state = 'COMPLETED') "
                  f"from public.care_authorizations where id = '{ca(17)}') and {one_event(17, 'COMPLETED')}",
                  'complete vs revoke: the revoke waits and finds the authorization ENDED at the completion time')
            first, second = race(observer, revoke_call(GUARDIAN, 18), complete_call(18), 'revoke vs complete')
            if outcome(first, 'revoke vs complete') != 'REVOKED' or not second.startswith('OK:'):
                raise HarnessFailure('revoke vs complete: both succeed in order')
            check(observer, f"{state(18)} = 'REVOKED' and {appointment_state(18)} = 'COMPLETED' "
                  f"and (select ended_at is null and ended_reason is null and revoking_user_id = '{fid(2, 1)}' "
                  f"from public.care_authorizations where id = '{ca(18)}') and {one_event(18, 'COMPLETED')}",
                  'revoke vs complete: the completion waits and keeps the revocation, its actor and time')
            first, second = race(observer, complete_call(19), complete_call(19), 'complete vs repeated complete')
            if not first.startswith('OK:') or second != 'ERR:23514:Only a CONFIRMED Appointment may be completed':
                raise HarnessFailure('complete vs repeated complete: one completion, one lifecycle rejection')
            check(observer, f"{state(19)} = 'ENDED' and {one_event(19, 'COMPLETED')} "
                  f"and (select count(*) = 1 from public.care_authorizations where appointment_id = '{appt(19)}')",
                  'complete vs repeated complete: the retry writes nothing; the authorization ended once')

            # Nothing resurrected, nothing clinical lost.
            check(observer, f"(select count(*) = 0 from public.care_authorizations where pet_id = '{PET}' "
                  f"and lifecycle_state = 'ACTIVE') "
                  f"and (select count(*) = 0 from public.care_authorizations where pet_id = '{PET}' "
                  f"and lifecycle_state = 'REVOKED' and (revoked_at is null or ended_at is not null)) "
                  f"and {clinical_rows()} = '{finalized_before}'",
                  'all races: no resurrection, no mixed terminal state, recorded clinical record unchanged')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0372000-'])


if __name__ == '__main__':
    main()

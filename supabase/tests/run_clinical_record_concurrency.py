"""LOCAL-only multi-session races for appointment-owned clinical documentation
(SPEC-MED-010 BR-7, BR-9, BR-26 and §12 Notes 16, 22, 24; SPEC-APT-007 BR-34).

Same discipline as run_staff_workforce_concurrency.py, whose race primitives
this reuses: a synthetic fixture (prefix d0341000-) is committed to the
isolated local database, the real client operations race in two psql sessions
(the first observed holding its locks, the second observed blocked on a lock
before the first commits), and every fixture row and every row the operations
created is always deleted afterwards, with restoration and zero retained
fixture rows verified. A deadlock would surface as ERR:40P01 and fail the exact
outcome checks. Recording and Guardian revocation take no conflicting locks
(BR-26); those pairs are run as overlapping transactions instead and must not
block each other. Never point this at a shared database.
"""
import sys
from concurrent.futures import ThreadPoolExecutor
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql
from run_staff_invitation_concurrency import check, race, result_of, session_sql, wait_for


def fid(kind, n):
    return f'd0341000-0000-4000-8000-{kind * 100 + n:012d}'


ORG, CLINIC, PET, GUARDIANSHIP = fid(3, 1), fid(4, 1), fid(9, 1), fid(9, 2)
GUARDIAN, ADMIN, VET, VET2 = fid(1, 1), fid(1, 5), fid(1, 10), fid(1, 11)  # Auth subjects
VCA, VCA2 = fid(8, 10), fid(8, 11)

# Appointments 1–20, CONFIRMED, one per day from 2026-06-01 (start reached);
# Veterinarian 10 is assigned to all but 18, which Veterinarian 11 holds.
FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0341000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'clinical-race-' || n || '@example.test', now()
from unnest(array[1, 5, 10, 11]) n;
insert into public.users (id)
select ('d0341000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 5, 10, 11]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0341000-0000-4000-8000-' || lpad((1900 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 5, 10, 11]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'Clinical Race Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values ('{CLINIC}', '{ORG}', true, 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0341000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{ORG}',
    ('d0341000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[5, 10, 11]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0341000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 5 then 'ADMINISTRATOR' else 'VETERINARIAN' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 5)}'
from unnest(array[5, 10, 11]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select ('d0341000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array[10, 11]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
select ('d0341000-0000-4000-8000-' || lpad((800 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{CLINIC}', '2020-01-01Z'
from unnest(array[10, 11]) n;
insert into public.pets (id, name, species, created_at) values ('{PET}', 'Race Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values ('{GUARDIANSHIP}', '{fid(2, 1)}', '{PET}', '2020-01-01Z');
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select ('d0341000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{fid(2, 1)}',
    'Race visit ' || n, 'CONFIRMED', '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 20) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at,
    scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select ('d0341000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, r,
    case r when 1 then 'REQUESTED' else 'CONFIRMED' end,
    '2026-06-01T10:00Z'::timestamptz + make_interval(days => n), '2026-06-01T10:30Z'::timestamptz + make_interval(days => n),
    'Europe/Madrid', case r when 1 then '{fid(2, 1)}'::uuid else '{fid(2, 5)}'::uuid end, null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from generate_series(1, 20) n, unnest(array[1, 2]) r;
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select ('d0341000-0000-4000-8000-' || lpad((1200 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{ORG}', '{GUARDIANSHIP}',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE',
    ('d0341000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'ACTIVE'
from generate_series(1, 20) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select ('d0341000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'REQUESTED', 'CONFIRMED', '{fid(2, 5)}',
    'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(1, 20) n;
insert into public.appointment_veterinarian_assignments (id, appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select ('d0341000-0000-4000-8000-' || lpad((1300 + n)::text, 12, '0'))::uuid,
    ('d0341000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid,
    case when n = 18 then '{VCA2}'::uuid else '{VCA}'::uuid end, '2026-03-01Z', '{fid(2, 5)}'
from generate_series(1, 20) n;
set local session_replication_role = origin;
select public.establish_organization_subscription('{ORG}', null, 'ACTIVE', '2020-01-01Z', null, null,
    'clinical-race', '{fid(20, 1)}', null);
commit;
"""

APPOINTMENT_FILTER = "appointment_id::text like 'd0341000-%'"
ENTRY_FILTER = (f"clinical_record_entry_id in (select e.id from public.clinical_record_entries e "
                f"join public.appointments a on a.id = e.appointment_id where a.pet_id = '{PET}')")
COMMUNICATIONS = f"(select id from public.transactional_communications where {APPOINTMENT_FILTER})"
CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.communication_delivery_attempts where communication_id in {COMMUNICATIONS};
delete from public.communication_delivery_jobs where communication_id in {COMMUNICATIONS};
delete from public.transactional_communications where {APPOINTMENT_FILTER};
delete from public.medical_access_audit_events where pet_id = '{PET}';
delete from public.clinical_amendments where original_{ENTRY_FILTER};
delete from public.clinical_attachments where {ENTRY_FILTER};
delete from public.clinical_record_entries where {APPOINTMENT_FILTER};
delete from public.appointment_lifecycle_events where {APPOINTMENT_FILTER};
delete from public.appointment_reschedule_proposals where {APPOINTMENT_FILTER};
delete from public.appointment_veterinarian_assignments where {APPOINTMENT_FILTER};
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
delete from public.veterinarian_professional_profiles where user_id::text like 'd0341000-%';
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.clinics where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0341000-%';
delete from public.users where id::text like 'd0341000-%';
delete from auth.users where id::text like 'd0341000-%';
commit;
"""


def appt(n):
    return fid(11, n)


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def record_call(subject, n, key, content='Race note'):
    return as_subject(subject, f"select public.create_appointment_clinical_entry('{CLINIC}', '{appt(n)}', '{key}', "
                               f"'CLINICAL_NOTE', '{content}', null)::text")


def reassign_call(n, vca):
    return as_subject(ADMIN, f"select public.assign_appointment_veterinarian('{CLINIC}', '{appt(n)}', '{vca}', "
                             f"(select current_period.id from public.appointment_veterinarian_assignments as current_period "
                             f"where current_period.appointment_id = '{appt(n)}' and current_period.effective_end is null))::text")


def cancel_call(n):
    return as_subject(ADMIN, f"select public.cancel_appointment('{appt(n)}', 'CLINIC', 'Clinic closed', 2)::text")


def no_show_call(n):
    return as_subject(ADMIN, f"select public.mark_appointment_no_show('{appt(n)}', 2)::text")


def complete_call(n):
    return as_subject(ADMIN, f"select public.complete_appointment('{appt(n)}', 2)::text")


def revoke_call(n):
    return as_subject(GUARDIAN, f"select public.revoke_my_appointment_care_authorization('{appt(n)}')::text")


def end_assignment_call(vca):
    return as_subject(ADMIN, f"select public.end_staff_veterinarian_clinic_assignment('{ORG}', '{CLINIC}', '{vca}')::text")


def outcome(result):
    return f"('{result[3:]}'::jsonb ->> 'outcome')" if result.startswith('OK:{') else 'null'


def field(result, name):
    return f"('{result[3:]}'::jsonb ->> '{name}')" if result.startswith('OK:{') else 'null'


def state(n):
    return f"(select lifecycle_state from public.appointments where id = '{appt(n)}')"


def entries(n):
    return f"(select count(*) from public.clinical_record_entries where appointment_id = '{appt(n)}')"


def assignee(n):
    return (f"(select veterinarian_clinic_assignment_id from public.appointment_veterinarian_assignments "
            f"where appointment_id = '{appt(n)}' and effective_end is null)")


def committed(observer, subject, statement, label):
    """One committed setup call as the impersonated User; returns its text."""
    return observer.require_success(
        f"begin;\nselect set_config('request.jwt.claim.sub', '{subject}', true);\n{statement};\ncommit;", label
    ).splitlines()[-1]


def overlap(observer, first_call, second_call, label):
    """First holds its transaction open; second must complete without waiting on a lock."""
    first, second = LocalSql(), LocalSql()
    with ThreadPoolExecutor(max_workers=2) as executor:
        try:
            pending_first = executor.submit(first.execute, session_sql(first_call, True))
            wait_for(first, observer, "wait_event = 'PgSleep'", label + ': first holds')
            second_result = result_of(second.execute(session_sql(second_call, False)))
            if observer.require_success("select exists(select 1 from pg_stat_activity where application_name = "
                                        f"'{first.application_name}' and wait_event = 'PgSleep');",
                                        label + ': first still open') != 't':
                raise HarnessFailure(f'{label}: the second operation waited for the first')
            outcome_pair = result_of(pending_first.result(timeout=60)), second_result
        finally:
            first.terminate_sessions()
            second.terminate_sessions()
    print(f'OVERLAP {label}: first={outcome_pair[0]} second={outcome_pair[1]}', flush=True)
    return outcome_pair


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            # BR-7: a lost response is retried with the same key.
            first, second = race(observer, record_call(VET, 1, fid(13, 1)), record_call(VET, 1, fid(13, 1)),
                                 'Record vs Record (same key)')
            check(observer, f"{outcome(first)} = 'CREATED' and {outcome(second)} = 'ALREADY_CREATED' "
                  f"and {field(first, 'entry_id')} = {field(second, 'entry_id')} and {entries(1)} = 1",
                  'Record vs Record (same key): one Entry; the retry reconciles to it')

            first, second = race(observer, record_call(VET, 2, fid(13, 2)), record_call(VET, 2, fid(13, 3)),
                                 'Record vs Record (different keys)')
            check(observer, f"{outcome(first)} = 'CREATED' and {outcome(second)} = 'CREATED' "
                  f"and {field(first, 'entry_id')} <> {field(second, 'entry_id')} and {entries(2)} = 2",
                  'Record vs Record (different keys): two independent Entries')

            first, second = race(observer, record_call(VET, 3, fid(13, 4)), record_call(VET2, 3, fid(13, 5)),
                                 'Record vs Record (two Veterinarians)')
            check(observer, f"{outcome(first)} = 'CREATED' and '{second}' = 'ERR:23514:NOT_ASSIGNED_VETERINARIAN' "
                  f"and {entries(3)} = 1",
                  'Record vs Record (two Veterinarians): only the assignee records; the other writes nothing')

            # BR-26 / Note 16: a first Entry and a non-attendance outcome serialize.
            first, second = race(observer, record_call(VET, 4, fid(13, 6)), cancel_call(4), 'Record vs Cancel')
            check(observer, f"{outcome(first)} = 'CREATED' and '{second}' like 'ERR:23514:%clinical documentation cannot be cancelled' "
                  f"and {state(4)} = 'CONFIRMED' and {entries(4)} = 1",
                  'Record vs Cancel: the cancellation waits and is refused; the Entry stands')

            first, second = race(observer, cancel_call(5), record_call(VET, 5, fid(13, 7)), 'Cancel vs Record')
            check(observer, f"'{first}' like 'OK:%' and '{second}' = 'ERR:23514:APPOINTMENT_STATE_INVALID' "
                  f"and {state(5)} = 'CANCELLED' and {entries(5)} = 0",
                  'Cancel vs Record: the save waits and finds the Appointment cancelled; nothing is written')

            first, second = race(observer, record_call(VET, 6, fid(13, 8)), no_show_call(6), 'Record vs No-show')
            check(observer, f"{outcome(first)} = 'CREATED' and '{second}' like 'ERR:23514:%clinical documentation cannot be marked no-show' "
                  f"and {state(6)} = 'CONFIRMED' and {entries(6)} = 1",
                  'Record vs No-show: the no-show waits and is refused; the Entry stands')

            first, second = race(observer, no_show_call(7), record_call(VET, 7, fid(13, 9)), 'No-show vs Record')
            check(observer, f"'{first}' like 'OK:%' and '{second}' = 'ERR:23514:APPOINTMENT_STATE_INVALID' "
                  f"and {state(7)} = 'NO_SHOW' and {entries(7)} = 0",
                  'No-show vs Record: the save waits and finds NO_SHOW; nothing is written')

            # Recording and completion are compatible in either order.
            first, second = race(observer, record_call(VET, 8, fid(13, 10)), complete_call(8), 'Record vs Complete')
            check(observer, f"{outcome(first)} = 'CREATED' and '{second}' like 'OK:%' and {state(8)} = 'COMPLETED' "
                  f"and {entries(8)} = 1",
                  'Record vs Complete: both succeed; the Appointment is COMPLETED with its Entry')

            first, second = race(observer, complete_call(9), record_call(VET, 9, fid(13, 11)), 'Complete vs Record')
            check(observer, f"'{first}' like 'OK:%' and {outcome(second)} = 'CREATED' and {state(9)} = 'COMPLETED' "
                  f"and {entries(9)} = 1",
                  'Complete vs Record: the save waits and documents the COMPLETED Appointment')

            # Note 22: a save racing a reassignment.
            first, second = race(observer, record_call(VET, 10, fid(13, 12)), reassign_call(10, VCA2),
                                 'Record vs Reassign')
            check(observer, f"{outcome(first)} = 'CREATED' and {outcome(second)} = 'REASSIGNED' "
                  f"and {assignee(10)} = '{VCA2}' "
                  f"and (select created_by_user_id = '{fid(2, 10)}' and creator_veterinarian_clinic_assignment_id = '{VCA}' "
                  f"from public.clinical_record_entries where id = {field(first, 'entry_id')}::uuid)",
                  'Record vs Reassign: the Entry is recorded by the assignee of that instant, then the reassignment follows; authorship stays')

            first, second = race(observer, reassign_call(11, VCA2), record_call(VET, 11, fid(13, 13)),
                                 'Reassign vs Record')
            check(observer, f"{outcome(first)} = 'REASSIGNED' and '{second}' = 'ERR:23514:NOT_ASSIGNED_VETERINARIAN' "
                  f"and {entries(11)} = 0 and {assignee(11)} = '{VCA2}'",
                  'Reassign vs Record: the save waits and is rejected with NOT_ASSIGNED_VETERINARIAN; nothing is written')

            # Note 24: an exact replay by the former assignee after a reassignment.
            original = committed(observer, VET, f"select (public.create_appointment_clinical_entry('{CLINIC}', '{appt(12)}', "
                                                f"'{fid(13, 14)}', 'CLINICAL_NOTE', 'Race note', null) ->> 'entry_id')",
                                 'Record before the replay race').strip()
            first, second = race(observer, reassign_call(12, VCA2), record_call(VET, 12, fid(13, 14)),
                                 'Reassign vs exact replay')
            check(observer, f"{outcome(first)} = 'REASSIGNED' and {outcome(second)} = 'ALREADY_CREATED' "
                  f"and {field(second, 'entry_id')} = '{original}' and {entries(12)} = 1",
                  'Reassign vs exact replay: the replay reconciles to the original Entry; nothing new is written')

            # BR-26: recording and Guardian revocation do not interact.
            first, second = overlap(observer, record_call(VET, 13, fid(13, 15)), revoke_call(13), 'Record with Revoke')
            check(observer, f"{outcome(first)} = 'CREATED' and {outcome(second)} = 'REVOKED' and {entries(13)} = 1 "
                  f"and (select lifecycle_state = 'REVOKED' from public.care_authorizations where appointment_id = '{appt(13)}')",
                  'Record with Revoke: neither waits; the Entry stands and the authorization is REVOKED')

            first, second = overlap(observer, revoke_call(14), record_call(VET, 14, fid(13, 16)), 'Revoke with Record')
            check(observer, f"{outcome(first)} = 'REVOKED' and {outcome(second)} = 'CREATED' and {entries(14)} = 1",
                  'Revoke with Record: neither waits; documentation does not depend on the authorization')

            # The end of the author's Clinic Assignment serializes with recording.
            first, second = race(observer, record_call(VET2, 18, fid(13, 17)), end_assignment_call(VCA2),
                                 'Record vs Assignment end')
            check(observer, f"{outcome(first)} = 'CREATED' and {outcome(second)} = 'ENDED' and {entries(18)} = 1",
                  'Record vs Assignment end: the end waits for the save; the Entry stands')
            # After the end commits, the stale assignment authorizes nothing; the
            # call fails before taking any lock, so it is not a race.
            after = result_of(LocalSql().execute(session_sql(record_call(VET2, 18, fid(13, 18)), False)))
            check(observer, f"'{after}' = 'ERR:42501:Clinical record unavailable' and {entries(18)} = 1 "
                  f"and {assignee(18)} = '{VCA2}'",
                  'Former assignee after offboarding: the stale assignment authorizes nothing')

            check(observer, f"not exists (select 1 from public.clinical_record_entries e join public.appointments a on a.id = e.appointment_id "
                  f"where a.pet_id = '{PET}' and a.lifecycle_state not in ('CONFIRMED', 'COMPLETED')) "
                  f"and not exists (select 1 from public.clinical_record_entries e join public.appointments a on a.id = e.appointment_id "
                  f"where a.pet_id = '{PET}' and not exists (select 1 from public.appointment_veterinarian_assignments p "
                  f"where p.appointment_id = e.appointment_id and p.veterinarian_clinic_assignment_id = e.creator_veterinarian_clinic_assignment_id "
                  f"and p.effective_start <= e.created_at and (p.effective_end is null or p.effective_end > e.created_at))) "
                  f"and (select count(*) from public.appointment_veterinarian_assignments where {APPOINTMENT_FILTER} "
                  f"and effective_end is null) = 20",
                  'coherent state: no Entry on a cancelled or no-show Appointment; every Entry recorded by the assignee of '
                  'its instant; one current assignment per Appointment')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0341000-'])


if __name__ == '__main__':
    main()

"""LOCAL-only multi-session races for the Appointment Veterinarian assignment
contract (SPEC-APT-007 §13 BR-32–BR-36, §14 Notes 26–28; migration
20261112090000_appointment_veterinarian_assignment_contract.sql).

Same discipline as run_clinical_record_concurrency.py, whose race primitives
this reuses: a synthetic fixture (prefix d0351000-) is committed to the
isolated local database, the real client operations race in two psql sessions
(the first observed holding its locks, the second observed blocked on a lock
before the first commits), and every fixture row and every row the operations
created is always deleted afterwards, with restoration and zero retained
fixture rows verified. A deadlock would surface as ERR:40P01 and fail the exact
outcome checks. Never point this at a shared database.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import LocalSql
from run_staff_invitation_concurrency import check, race


def fid(kind, n):
    return f'd0351000-0000-4000-8000-{kind * 100 + n:012d}'


ORG, CLINIC, PET, GUARDIANSHIP = fid(3, 1), fid(4, 1), fid(9, 1), fid(9, 2)
GUARDIAN, ADMIN, VET, VET2 = fid(1, 1), fid(1, 5), fid(1, 10), fid(1, 11)  # Auth subjects
VCA, VCA2 = fid(8, 10), fid(8, 11)

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0351000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'assignment-race-' || n || '@example.test', now()
from unnest(array[1, 5, 10, 11]) n;
insert into public.users (id)
select ('d0351000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 5, 10, 11]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0351000-0000-4000-8000-' || lpad((1900 + n)::text, 12, '0'))::uuid,
    ('d0351000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0351000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 5, 10, 11]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'Assignment Race Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values ('{CLINIC}', '{ORG}', true, 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0351000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{ORG}',
    ('d0351000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[5, 10, 11]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0351000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0351000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 5 then 'ADMINISTRATOR' else 'VETERINARIAN' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 5)}'
from unnest(array[5, 10, 11]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select ('d0351000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0351000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array[10, 11]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
select ('d0351000-0000-4000-8000-' || lpad((800 + n)::text, 12, '0'))::uuid,
    ('d0351000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0351000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{CLINIC}', '2020-01-01Z'
from unnest(array[10, 11]) n;
insert into public.pets (id, name, species, created_at) values ('{PET}', 'Race Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values ('{GUARDIANSHIP}', '{fid(2, 1)}', '{PET}', '2020-01-01Z');
-- One Appointment per day, so that no two confirmed commitments overlap.
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select ('d0351000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{fid(2, 1)}',
    'Race visit ' || n, 'CONFIRMED', '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 10) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at,
    scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select ('d0351000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, r,
    case r when 1 then 'REQUESTED' else 'CONFIRMED' end,
    '2026-06-01T10:00Z'::timestamptz + make_interval(days => n),
    '2026-06-01T10:30Z'::timestamptz + make_interval(days => n), 'Europe/Madrid',
    case r when 1 then '{fid(2, 1)}'::uuid else '{fid(2, 5)}'::uuid end, null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from generate_series(1, 10) n, unnest(array[1, 2]) r;
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select ('d0351000-0000-4000-8000-' || lpad((1200 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{ORG}', '{GUARDIANSHIP}',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE',
    ('d0351000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'ACTIVE'
from generate_series(1, 10) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select ('d0351000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'REQUESTED', 'CONFIRMED', '{fid(2, 5)}',
    'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(1, 10) n;
set local session_replication_role = origin;
select public.establish_organization_subscription('{ORG}', null, 'ACTIVE', '2020-01-01Z', null, null,
    'assignment-race', '{fid(20, 1)}', null);
commit;
"""

APPOINTMENT_FILTER = "appointment_id::text like 'd0351000-%'"
COMMUNICATIONS = f"(select id from public.transactional_communications where {APPOINTMENT_FILTER})"
CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.communication_delivery_attempts where communication_id in {COMMUNICATIONS};
delete from public.communication_delivery_jobs where communication_id in {COMMUNICATIONS};
delete from public.transactional_communications where {APPOINTMENT_FILTER};
delete from public.medical_access_audit_events where pet_id = '{PET}';
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
delete from public.veterinarian_professional_profiles where user_id::text like 'd0351000-%';
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.clinics where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0351000-%';
delete from public.users where id::text like 'd0351000-%';
delete from auth.users where id::text like 'd0351000-%';
commit;
"""


def appt(n):
    return fid(11, n)


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def assign_call(n, vca, token='null'):
    return as_subject(ADMIN, f"select public.assign_appointment_veterinarian('{CLINIC}', '{appt(n)}', '{vca}', {token})::text")


def me_call(subject, n):
    return as_subject(subject, f"select public.assign_me_to_appointment('{CLINIC}', '{appt(n)}')::text")


def cancel_call(n):
    return as_subject(ADMIN, f"select public.cancel_appointment('{appt(n)}', 'CLINIC', 'Clinic closed', 2)::text")


def complete_call(n):
    return as_subject(ADMIN, f"select public.complete_appointment('{appt(n)}', 2)::text")


def end_assignment_call(vca):
    return as_subject(ADMIN, f"select public.end_staff_veterinarian_clinic_assignment('{ORG}', '{CLINIC}', '{vca}')::text")


def outcome(result):
    return f"('{result[3:]}'::jsonb ->> 'outcome')" if result.startswith('OK:{') else 'null'


def current(n):
    return (f"(select veterinarian_clinic_assignment_id::text from public.appointment_veterinarian_assignments "
            f"where appointment_id = '{appt(n)}' and effective_end is null)")


def currents(n):
    return (f"(select count(*) from public.appointment_veterinarian_assignments "
            f"where appointment_id = '{appt(n)}' and effective_end is null)")


def periods(n):
    return f"(select count(*) from public.appointment_veterinarian_assignments where appointment_id = '{appt(n)}')"


def state(n):
    return f"(select lifecycle_state from public.appointments where id = '{appt(n)}')"


def token(observer, n):
    return "'" + observer.require_success(
        f"select id::text from public.appointment_veterinarian_assignments "
        f"where appointment_id = '{appt(n)}' and effective_end is null;", f'Token of {n}').strip() + "'"


def committed(observer, subject, statement, label):
    observer.require_success(
        f"begin;\nselect set_config('request.jwt.claim.sub', '{subject}', true);\n{statement};\ncommit;", label)


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, assign_call(1, VCA), assign_call(1, VCA2), 'Assign vs Assign (same view)')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and '{second}' = 'ERR:P0001:STALE_ASSIGNMENT' "
                  f"and {current(1)} = '{VCA}' and {currents(1)} = 1 and {periods(1)} = 1",
                  'Assign vs Assign: one assignment; the other is stale and writes nothing')

            first, second = race(observer, me_call(VET, 2), assign_call(2, VCA2), 'Self vs Managed')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and '{second}' = 'ERR:P0001:STALE_ASSIGNMENT' "
                  f"and {current(2)} = '{VCA}' and {currents(2)} = 1",
                  'Self vs Managed: the managed assignment from the unassigned view is stale')

            first, second = race(observer, assign_call(3, VCA2), me_call(VET, 3), 'Managed vs Self')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and '{second}' = 'ERR:23514:ASSIGNED_TO_ANOTHER_VETERINARIAN' "
                  f"and {current(3)} = '{VCA2}' and {currents(3)} = 1",
                  'Managed vs Self: self-assignment never displaces the eligible colleague')

            first, second = race(observer, me_call(VET, 4), me_call(VET2, 4), 'Self vs Self')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and '{second}' = 'ERR:23514:ASSIGNED_TO_ANOTHER_VETERINARIAN' "
                  f"and {current(4)} = '{VCA}' and {currents(4)} = 1",
                  'Self vs Self: exactly one assignee')

            committed(observer, ADMIN, f"select public.assign_appointment_veterinarian('{CLINIC}', '{appt(5)}', '{VCA}', null)",
                      'Assign 5')
            reviewed = token(observer, 5)
            first, second = race(observer, assign_call(5, VCA2, reviewed), assign_call(5, VCA2, reviewed),
                                 'Reassign vs Reassign (same token)')
            check(observer, f"{outcome(first)} = 'REASSIGNED' and {outcome(second)} = 'ALREADY_ASSIGNED' "
                  f"and {current(5)} = '{VCA2}' and {periods(5)} = 2",
                  'Reassign vs Reassign: one reassignment; the replay reconciles to it')

            committed(observer, ADMIN, f"select public.assign_appointment_veterinarian('{CLINIC}', '{appt(6)}', '{VCA}', null)",
                      'Assign 6')
            reviewed = token(observer, 6)
            first, second = race(observer, assign_call(6, VCA2, reviewed), complete_call(6), 'Reassign vs Complete')
            check(observer, f"{outcome(first)} = 'REASSIGNED' and '{second}' like 'OK:%' "
                  f"and {state(6)} = 'COMPLETED' and {current(6)} = '{VCA2}'",
                  'Reassign vs Complete: both succeed; the Appointment is completed with the new assignee')

            first, second = race(observer, complete_call(7), me_call(VET, 7), 'Complete vs Self')
            check(observer, f"'{first}' like 'OK:%' and {outcome(second)} = 'ASSIGNED' "
                  f"and {state(7)} = 'COMPLETED' and {current(7)} = '{VCA}'",
                  'Complete vs Self: the completed Appointment may still be assigned for documentation')

            first, second = race(observer, cancel_call(8), assign_call(8, VCA), 'Cancel vs Assign')
            check(observer, f"'{first}' like 'OK:%' and '{second}' = 'ERR:23514:APPOINTMENT_STATE_INVALID' "
                  f"and {state(8)} = 'CANCELLED' and {periods(8)} = 0",
                  'Cancel vs Assign: the assignment waits and finds the Appointment cancelled')

            first, second = race(observer, end_assignment_call(VCA2), me_call(VET2, 9), 'Clinic Assignment end vs Self')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = 'ERR:42501:Appointment unavailable' "
                  f"and {periods(9)} = 0",
                  'Clinic Assignment end vs Self: the former Veterinarian cannot self-assign')

            check(observer, f"not exists (select 1 from public.appointment_veterinarian_assignments ended "
                  f"where ended.{APPOINTMENT_FILTER} and ended.effective_end is not null and not exists ("
                  f"select 1 from public.appointment_veterinarian_assignments successor "
                  f"where successor.appointment_id = ended.appointment_id and successor.effective_start = ended.effective_end)) "
                  f"and (select max(c) from (select count(*) c from public.appointment_veterinarian_assignments "
                  f"where {APPOINTMENT_FILTER} and effective_end is null group by appointment_id) x) = 1",
                  'coherent state: at most one current assignee and every ended period has a successor')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0351000-'])


if __name__ == '__main__':
    main()

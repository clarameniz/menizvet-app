"""LOCAL-only multi-session races for Staff Responsibility Editing +
Veterinarian Enablement Phase 1 (SPEC-ORG-006 BR-44/BR-57, SPEC-VET-001
BR-19/BR-20, SPEC-VET-004 BR-25, SPEC-VET-005 BR-28).

Same discipline as run_staff_invitation_concurrency.py, whose race primitives
this reuses: a synthetic fixture (prefix d0334000-) is committed to the
isolated local database, real client-safe operations race in two psql
sessions (the first observed holding its locks, the second observed blocked on
a lock before the first commits), and every fixture row is always deleted
afterwards, with restoration and zero retained fixture rows verified. A
deadlock would surface as ERR:40P01 and fail the exact outcome checks. Never
point this at a shared database.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import LocalSql
from run_staff_invitation_concurrency import check, race


def fid(kind, n):
    return f'd0334000-0000-4000-8000-{kind * 100 + n:012d}'


ORG = fid(3, 1)
A1, A2 = fid(4, 1), fid(4, 2)
OWNER, ADMIN, ADMIN2 = fid(1, 1), fid(1, 2), fid(1, 3)  # Auth subjects
# Targets (User/Membership n): 11 RECEPTIONIST; 12-14 RECEPTIONIST + ADMINISTRATOR;
# 15 VETERINARIAN + Profile; 16-19 VETERINARIAN + RECEPTIONIST + Profile;
# 20 VETERINARIAN + Profile + open A1 Assignment; 21 verified User without Profile.
VETS = [15, 16, 17, 18, 19, 20]

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0334000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'w-race-' || n || '@example.test', now()
from unnest(array[1, 2, 3, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]) n;
insert into public.users (id)
select ('d0334000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, 3, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0334000-0000-4000-8000-' || lpad((900 + n)::text, 12, '0'))::uuid,
    ('d0334000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0334000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, 3, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'Workforce Race Org');
insert into public.clinics (id, organization_id) values ('{A1}', '{ORG}'), ('{A2}', '{ORG}');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0334000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{ORG}',
    ('d0334000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 2, 3, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]) n;
-- Grant fid(6, n) is the first Grant of Membership n; fid(7, n) a second one.
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0334000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0334000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 1 then 'OWNER' when n in (2, 3) then 'ADMINISTRATOR' when n >= 15 then 'VETERINARIAN' else 'RECEPTIONIST' end,
    'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}'
from unnest(array[1, 2, 3, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0334000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0334000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n <= 14 then 'ADMINISTRATOR' else 'RECEPTIONIST' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}'
from unnest(array[12, 13, 14, 16, 17, 18, 19]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select ('d0334000-0000-4000-8000-' || lpad((800 + n)::text, 12, '0'))::uuid,
    ('d0334000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array{VETS}) n;
insert into public.veterinarian_professional_credentials (id, professional_profile_id, registration_identifier, issuing_context)
select ('d0334000-0000-4000-8000-' || lpad((1000 + n)::text, 12, '0'))::uuid,
    ('d0334000-0000-4000-8000-' || lpad((800 + n)::text, 12, '0'))::uuid, 'W-RACE-' || n, 'Colegio'
from unnest(array{VETS}) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
values ('{fid(11, 20)}', '{fid(8, 20)}', '{fid(5, 20)}', '{A1}', '2020-01-01Z');
commit;
"""

CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.veterinarian_clinic_assignments where clinic_id in ('{A1}', '{A2}');
delete from public.veterinarian_professional_credentials where professional_profile_id in
    (select id from public.veterinarian_professional_profiles where user_id::text like 'd0334000-%');
delete from public.veterinarian_professional_profiles where user_id::text like 'd0334000-%';
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.clinics where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0334000-%';
delete from public.users where id::text like 'd0334000-%';
delete from auth.users where id::text like 'd0334000-%';
commit;
"""


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def add_call(subject, member):
    return as_subject(subject, f"select public.add_staff_responsibility('{ORG}', '{fid(5, member)}', "
                               "'ADMINISTRATOR', 'CLINIC', '" + A1 + "')::text")


def replace_call(subject, grant, clinic):
    return as_subject(subject, f"select public.replace_staff_responsibility('{ORG}', '{grant}', "
                               f"'RECEPTIONIST', 'CLINIC', '{clinic}')::text")


def end_grant_call(subject, grant):
    return as_subject(subject, f"select public.end_staff_responsibility('{ORG}', '{grant}')::text")


def assign_call(subject, member, clinic):
    return as_subject(subject, f"select public.assign_staff_veterinarian_to_clinic('{ORG}', '{fid(5, member)}', '{clinic}')::text")


def unassign_call(subject, clinic, assignment):
    return as_subject(subject, f"select public.end_staff_veterinarian_clinic_assignment('{ORG}', '{clinic}', '{assignment}')::text")


def end_membership_call(subject, member):
    return as_subject(subject, f"select public.end_organization_staff_membership('{fid(5, member)}')::text")


def profile_call(user):
    return as_subject(fid(1, user), "select public.create_my_veterinarian_professional_profile('W-RACE-21', 'Colegio')::text")


def outcome(result):
    return f"('{result[3:]}'::jsonb ->> 'outcome')" if result.startswith('OK:{') else 'null'


def field(result, name):
    return f"('{result[3:]}'::jsonb ->> '{name}')" if result.startswith('OK:{') else 'null'


def active(member, role, clinic=None):
    clinic_filter = f"clinic_id = '{clinic}'" if clinic else 'clinic_id is null'
    return (f"(select count(*) from public.organization_responsibility_grants where membership_id = '{fid(5, member)}' "
            f"and responsibility = '{role}' and {clinic_filter} and effective_end is null)")


def open_assignments(member, clinic):
    return (f"(select count(*) from public.veterinarian_clinic_assignments where supporting_membership_id = '{fid(5, member)}' "
            f"and clinic_id = '{clinic}' and effective_end is null)")


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, add_call(ADMIN, 11), add_call(ADMIN2, 11), 'add vs add (same Responsibility)')
            check(observer, f"{outcome(first)} = 'ADDED' and {outcome(second)} = 'ALREADY_PRESENT' "
                  f"and {field(first, 'responsibility_grant_id')} = {field(second, 'responsibility_grant_id')} "
                  f"and {active(11, 'ADMINISTRATOR', A1)} = 1 and {active(11, 'RECEPTIONIST')} = 1",
                  'add vs add: one ADDED, one ALREADY_PRESENT for the same Grant; no duplicate')

            first, second = race(observer, replace_call(ADMIN, fid(6, 12), A1), end_grant_call(ADMIN2, fid(6, 12)),
                                 'replace vs end (same Grant)')
            check(observer, f"{outcome(first)} = 'REPLACED' and {outcome(second)} = 'ALREADY_ENDED' "
                  f"and {field(second, 'effective_end')}::timestamptz = {field(first, 'effective_instant')}::timestamptz "
                  f"and {active(12, 'RECEPTIONIST', A1)} = 1 and {active(12, 'RECEPTIONIST')} = 0 and {active(12, 'ADMINISTRATOR')} = 1",
                  'replace vs end: the end waits and reports the replacement end; replacement and unrelated Grant stay')

            first, second = race(observer, replace_call(ADMIN, fid(6, 13), A1), replace_call(ADMIN2, fid(6, 13), A2),
                                 'replace vs replace (different targets)')
            check(observer, f"{outcome(first)} = 'REPLACED' and '{second}' = 'ERR:23514:GRANT_ENDED' "
                  f"and {active(13, 'RECEPTIONIST', A1)} = 1 and {active(13, 'RECEPTIONIST', A2)} = 0 and {active(13, 'ADMINISTRATOR')} = 1",
                  'replace vs replace: one replacement; the stale one is GRANT_ENDED and writes nothing')

            first, second = race(observer, replace_call(ADMIN, fid(6, 14), A1), replace_call(ADMIN2, fid(6, 14), A1),
                                 'replace vs replace (identical)')
            check(observer, f"{outcome(first)} = 'REPLACED' and {outcome(second)} = 'ALREADY_CHANGED' "
                  f"and {field(first, 'responsibility_grant_id')} = {field(second, 'responsibility_grant_id')} "
                  f"and {active(14, 'RECEPTIONIST', A1)} = 1",
                  'identical replace vs replace: one REPLACED, one ALREADY_CHANGED naming the same replacement')

            first, second = race(observer, assign_call(ADMIN, 15, A1), assign_call(ADMIN2, 15, A1), 'assign vs assign (same Clinic)')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and {outcome(second)} = 'ALREADY_ASSIGNED' "
                  f"and {field(first, 'veterinarian_clinic_assignment_id')} = {field(second, 'veterinarian_clinic_assignment_id')} "
                  f"and {open_assignments(15, A1)} = 1",
                  'assign vs assign: one ASSIGNED, one ALREADY_ASSIGNED; one open Assignment')

            first, second = race(observer, assign_call(ADMIN, 16, A1), end_membership_call(OWNER, 16), 'assign vs Membership end')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and {outcome(second)} = 'ENDED' and {open_assignments(16, A1)} = 1 "
                  f"and not public.veterinarian_clinic_assignment_is_current({field(first, 'veterinarian_clinic_assignment_id')}::uuid)",
                  'assign vs Membership end: the end waits; the Assignment row stays but is no longer current')

            first, second = race(observer, end_membership_call(OWNER, 17), assign_call(ADMIN, 17, A1), 'Membership end vs assign')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = 'ERR:23514:MEMBERSHIP_INACTIVE' and {open_assignments(17, A1)} = 0",
                  'Membership end vs assign: the assign waits, then finds the Membership ended and writes nothing')

            first, second = race(observer, end_grant_call(ADMIN, fid(6, 18)), assign_call(ADMIN2, 18, A1), 'VETERINARIAN end vs assign')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = 'ERR:23514:VETERINARIAN_RESPONSIBILITY_REQUIRED' "
                  f"and {open_assignments(18, A1)} = 0",
                  'VETERINARIAN end vs assign: the assign waits, then finds no VETERINARIAN Grant')

            first, second = race(observer, assign_call(ADMIN, 19, A1), end_grant_call(ADMIN2, fid(6, 19)), 'assign vs VETERINARIAN end')
            check(observer, f"{outcome(first)} = 'ASSIGNED' and '{second}' = 'ERR:23514:VETERINARIAN_ASSIGNMENTS_ACTIVE' "
                  f"and {active(19, 'VETERINARIAN')} = 1 and {open_assignments(19, A1)} = 1",
                  'assign vs VETERINARIAN end: the end waits, then is blocked by the new current Assignment')

            first, second = race(observer, unassign_call(ADMIN, A1, fid(11, 20)), assign_call(ADMIN2, 20, A1),
                                 'end Assignment vs re-assign')
            check(observer, f"{outcome(first)} = 'ENDED' and {outcome(second)} = 'ASSIGNED' "
                  f"and {field(second, 'veterinarian_clinic_assignment_id')} <> '{fid(11, 20)}' and {open_assignments(20, A1)} = 1 "
                  f"and (select effective_end is not null from public.veterinarian_clinic_assignments where id = '{fid(11, 20)}')",
                  'end Assignment vs re-assign: the old period ends, a new one begins; never reactivated')

            first, second = race(observer, profile_call(21), profile_call(21), 'Profile create vs create')
            check(observer, f"{outcome(first)} = 'CREATED' and {outcome(second)} = 'ALREADY_EXISTS' "
                  f"and {field(first, 'professional_profile_id')} = {field(second, 'professional_profile_id')} "
                  f"and {field(first, 'professional_credential_id')} = {field(second, 'professional_credential_id')} "
                  f"and (select count(*) from public.veterinarian_professional_profiles where user_id = '{fid(2, 21)}') = 1",
                  'Profile create vs create: one Profile; the second reconciles with the same ids')

            check(observer, f"not exists (select 1 from public.organization_responsibility_grants g "
                  f"join public.organization_memberships m on m.id = g.membership_id where m.organization_id = '{ORG}' "
                  "and ((m.effective_end is not null and g.effective_end is null) or g.effective_end < g.effective_start)) "
                  f"and not exists (select g.membership_id from public.organization_responsibility_grants g "
                  f"join public.organization_memberships m on m.id = g.membership_id where m.organization_id = '{ORG}' "
                  "and g.effective_end is null group by g.membership_id, g.responsibility, g.scope_type, g.clinic_id having count(*) > 1)",
                  'coherent history: no duplicate active Grant, no active Grant under an ended Membership')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0334000-'])


if __name__ == '__main__':
    main()

"""LOCAL-only multi-session races for Staff Slice C (SPEC-ORG-004 BR-18, BR-24,
BR-26, §5 "Concurrent termination attempts"; SPEC-ORG-009 one-snapshot read).

Same discipline as run_staff_invitation_concurrency.py, whose race primitives
this reuses: a synthetic fixture (prefix d0291000-) is committed to the
isolated local database, real operations race in two psql sessions (the first
observed holding its locks, the second observed blocked on a lock before the
first commits), and every fixture row is always deleted afterwards, with
restoration and zero retained fixture rows verified. Never point this at a
shared database.
"""
from concurrent.futures import ThreadPoolExecutor
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql
from run_staff_invitation_concurrency import ATTEMPT, check, race, wait_for

HOLD_SECONDS = 6


def fid(kind, n):
    return f'd0291000-0000-4000-8000-{kind * 100 + n:012d}'


ORG = fid(3, 1)
OWNER, ADMIN = fid(1, 1), fid(1, 2)  # Auth subjects
MEMBERS = range(11, 18)  # target Users 11..17, Membership fid(5, n), Grant fid(6, n)

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0291000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'c-race-' || n || '@example.test', now()
from unnest(array[1, 2, 11, 12, 13, 14, 15, 16, 17]) n;
insert into public.users (id)
select ('d0291000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 2, 11, 12, 13, 14, 15, 16, 17]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0291000-0000-4000-8000-' || lpad((900 + n)::text, 12, '0'))::uuid,
    ('d0291000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0291000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, 11, 12, 13, 14, 15, 16, 17]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'C Race Org');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0291000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{ORG}',
    ('d0291000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 2, 11, 12, 13, 14, 15, 16, 17]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0291000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0291000-0000-4000-8000-' || lpad((500 + case when n = 66 then 16 else n end)::text, 12, '0'))::uuid,
    case when n = 1 then 'OWNER' when n in (2, 66) then 'ADMINISTRATOR' else 'RECEPTIONIST' end,
    'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}'
from unnest(array[1, 2, 11, 12, 13, 14, 15, 16, 66, 17]) n;
commit;
"""

CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0291000-%';
delete from public.users where id::text like 'd0291000-%';
delete from auth.users where id::text like 'd0291000-%';
commit;
"""


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def end_call(subject, member):
    return as_subject(subject, f"select public.end_organization_staff_membership('{fid(5, member)}')::text")


def add_call(subject, member):
    return as_subject(subject, f"select public.add_organization_responsibility('{fid(5, member)}', "
                               "'ADMINISTRATOR', 'ORGANIZATION', null)::text")


def replace_call(subject, grant):
    return as_subject(subject, f"select public.replace_organization_responsibility('{fid(6, grant)}', "
                               "'ADMINISTRATOR', 'ORGANIZATION', null)::text")


def end_grant_call(subject, grant):
    return as_subject(subject, f"select public.end_organization_responsibility('{fid(6, grant)}')::text")


def outcome(result):
    return f"('{result[3:]}'::jsonb ->> 'outcome')" if result.startswith('OK:{') else 'null'


def ended_coherently(member):
    """Membership ended; every Grant ended no later than it; none starts after it."""
    membership = f"(select effective_end from public.organization_memberships where id = '{fid(5, member)}')"
    return (f"{membership} is not null and not exists (select 1 from public.organization_responsibility_grants "
            f"where membership_id = '{fid(5, member)}' and (effective_end is null or effective_end > {membership} "
            f"or effective_start > {membership}))")


INACTIVE = "'ERR:23514:Responsibilities require an active Organization Membership'"


def staff_read_during_end(observer):
    """A Staff read issued while an end is in flight is not blocked and shows
    the Member whole; after commit the Member is gone."""
    member = 17
    read = (f"select set_config('request.jwt.claim.sub', '{OWNER}', false); "
            f"select (select count(*) from jsonb_array_elements(public.get_organization_staff('{ORG}') -> 'members') m "
            f"where m ->> 'membership_id' = '{fid(5, member)}' and jsonb_array_length(m -> 'responsibilities') = 1)::text;")
    first = LocalSql()
    with ThreadPoolExecutor(max_workers=1) as executor:
        try:
            pending = executor.submit(first.execute, ATTEMPT + 'begin;\n' + f"select set_config('request.jwt.claim.sub', '{OWNER}', false);\n"
                                      f"select public.end_organization_staff_membership('{fid(5, member)}');\n"
                                      f"select pg_sleep({HOLD_SECONDS});\ncommit;\n")
            wait_for(first, observer, "wait_event = 'PgSleep'", 'end in flight holds its locks')
            during = observer.require_success(read, 'Staff read during end').splitlines()[-1]
            still_holding = observer.require_success(
                "select exists(select 1 from pg_stat_activity where application_name = "
                f"'{first.application_name}' and wait_event = 'PgSleep');", 'end still in flight')
            completed = pending.result(timeout=60)
            if completed.returncode:
                raise HarnessFailure('In-flight end failed:\n' + completed.stderr)
        finally:
            first.terminate_sessions()
    after = observer.require_success(read, 'Staff read after end').splitlines()[-1]
    print(f'READ during end: member rows={during} (end still in flight: {still_holding}); after commit: {after}', flush=True)
    if not (during == '1' and still_holding == 't' and after == '0'):
        raise HarnessFailure('Staff read is not one coherent, non-blocking snapshot')
    print('PASS Staff read during an in-flight end is not blocked and shows the whole Member; gone after commit', flush=True)


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, end_call(OWNER, 11), end_call(ADMIN, 11), 'end vs end')
            check(observer, f"{outcome(first)} = 'ENDED' and {outcome(second)} = 'ALREADY_ENDED' "
                  f"and ('{first[3:]}'::jsonb ->> 'effective_end') = ('{second[3:]}'::jsonb ->> 'effective_end') "
                  f"and ('{first[3:]}'::jsonb ->> 'effective_end')::timestamptz = (select effective_end from "
                  f"public.organization_memberships where id = '{fid(5, 11)}') and {ended_coherently(11)}",
                  'end vs end: one ENDED, one ALREADY_ENDED with the same single effective end')

            first, second = race(observer, end_call(OWNER, 12), add_call(ADMIN, 12), 'end vs add Responsibility')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = {INACTIVE} and {ended_coherently(12)} "
                  f"and (select count(*) from public.organization_responsibility_grants where membership_id = '{fid(5, 12)}') = 1",
                  'end vs add: the add waits, then finds the Membership ended and adds nothing')

            first, second = race(observer, add_call(ADMIN, 13), end_call(OWNER, 13), 'add Responsibility vs end')
            check(observer, f"'{first}' ~ '^OK:[0-9a-f-]{{36}}$' and {outcome(second)} = 'ENDED' and {ended_coherently(13)} "
                  f"and (select count(*) from public.organization_responsibility_grants where membership_id = '{fid(5, 13)}') = 2",
                  'add vs end: the end waits and ends the added Grant too')

            first, second = race(observer, end_call(OWNER, 14), replace_call(ADMIN, 14), 'end vs replace Responsibility')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = {INACTIVE} and {ended_coherently(14)} "
                  f"and (select count(*) from public.organization_responsibility_grants where membership_id = '{fid(5, 14)}') = 1",
                  'end vs replace: the replacement waits, then finds the Membership ended and changes nothing')

            first, second = race(observer, replace_call(ADMIN, 15), end_call(OWNER, 15), 'replace Responsibility vs end')
            check(observer, f"'{first}' ~ '^OK:[0-9a-f-]{{36}}$' and {outcome(second)} = 'ENDED' and {ended_coherently(15)} "
                  f"and (select count(*) from public.organization_responsibility_grants where membership_id = '{fid(5, 15)}') = 2",
                  'replace vs end: the end waits and ends the replacement Grant; the superseded one keeps its end')

            first, second = race(observer, end_grant_call(ADMIN, 66), end_call(OWNER, 16), 'end Responsibility vs end')
            check(observer, f"'{first}' like 'OK:%' and {outcome(second)} = 'ENDED' and {ended_coherently(16)} "
                  f"and (select effective_end < (select effective_end from public.organization_memberships where id = '{fid(5, 16)}') "
                  f"or effective_end = (select effective_end from public.organization_memberships where id = '{fid(5, 16)}') "
                  f"from public.organization_responsibility_grants where id = '{fid(6, 66)}')",
                  'end Responsibility vs end: the earlier Grant end is kept, the remaining Grant ends with the Membership')

            observer.require_success(f"""begin; set local session_replication_role = replica;
                insert into public.organization_memberships (id, organization_id, user_id, effective_start)
                values ('{fid(5, 18)}', '{ORG}', '{fid(2, 11)}', '2020-01-01Z');
                insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type,
                    effective_start, granted_by_user_id)
                values ('{fid(6, 18)}', '{fid(5, 18)}', 'RECEPTIONIST', 'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}');
                commit;""", 'Commit a rejoined period for User 11')
            first, second = race(observer, end_call(OWNER, 18), end_grant_call(ADMIN, 18), 'end vs end Responsibility')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = {INACTIVE} and {ended_coherently(18)}",
                  'end vs end Responsibility: the Grant end waits, then finds the Membership ended')

            staff_read_during_end(observer)

            check(observer, f"not exists (select 1 from public.organization_memberships m join "
                  f"public.organization_responsibility_grants g on g.membership_id = m.id where m.organization_id = '{ORG}' "
                  "and m.effective_end is not null and (g.effective_end is null or g.effective_end > m.effective_end "
                  "or g.effective_start > m.effective_end))",
                  'no active Grant, and no Grant starting or ending after the end, under any ended Membership')
            check(observer, f"(select count(*) from public.organization_memberships where organization_id = '{ORG}' "
                  f"and user_id = '{fid(2, 1)}' and effective_end is null) = 1",
                  'the Owner remains active')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0291000-'])


if __name__ == '__main__':
    main()

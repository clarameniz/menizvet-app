"""LOCAL-only multi-session races for Clinic creation (SPEC-CLI-001 §10 BR-14,
Verification Note 17).

Same discipline as run_staff_end_access_concurrency.py: a synthetic fixture
(prefix d0301000-) is committed to the isolated local database, real
create_clinic calls race in two psql sessions, and every fixture row is always
deleted afterwards (in replica mode, because Clinics are undeletable by
ordinary operations), with restoration and zero retained fixture rows
verified. Never point this at a shared database.
"""
from concurrent.futures import ThreadPoolExecutor
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql
from run_staff_invitation_concurrency import ATTEMPT, check, race, result_of, session_sql, wait_for

HOLD_SECONDS = 6


def fid(kind, n):
    return f'd0301000-0000-4000-8000-{kind * 100 + n:012d}'


ORG_A, ORG_B = fid(3, 1), fid(3, 2)
OWNER_A, ADMIN_A, OWNER_B = fid(1, 1), fid(1, 2), fid(1, 3)  # Auth subjects


def key(n):
    return fid(20, n)


FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0301000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'k-race-' || n || '@example.test', now()
from unnest(array[1, 2, 3]) n;
insert into public.users (id)
select ('d0301000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 2, 3]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0301000-0000-4000-8000-' || lpad((900 + n)::text, 12, '0'))::uuid,
    ('d0301000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0301000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, 3]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG_A}', 'K Race Org A'), ('{ORG_B}', 'K Race Org B');
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0301000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 3 then '{ORG_B}'::uuid else '{ORG_A}'::uuid end,
    ('d0301000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[1, 2, 3]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0301000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0301000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 2 then 'ADMINISTRATOR' else 'OWNER' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}'
from unnest(array[1, 2, 3]) n;
commit;
"""

CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.clinics where organization_id in ('{ORG_A}', '{ORG_B}');
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id in ('{ORG_A}', '{ORG_B}'));
delete from public.organization_memberships where organization_id in ('{ORG_A}', '{ORG_B}');
delete from public.veterinary_organizations where id in ('{ORG_A}', '{ORG_B}');
delete from public.user_authentication_identities where id::text like 'd0301000-%';
delete from public.users where id::text like 'd0301000-%';
delete from auth.users where id::text like 'd0301000-%';
commit;
"""


def create_call(subject, organization, creation_key):
    return (f"select set_config('request.jwt.claim.sub', '{subject}', false); "
            f"select public.create_clinic('{organization}', '{creation_key}')::text")


def field(result, name):
    if not result.startswith('OK:{'):
        return 'null'
    return f"('{result[3:]}'::jsonb ->> '{name}')"


def clinics_with(organization, creation_key):
    return (f"(select count(*) from public.clinics where organization_id = '{organization}' "
            f"and creation_idempotency_key = '{creation_key}')")


def parallel(observer, first_call, second_call, label):
    """First holds its transaction open; second completes without ever waiting
    on a lock while first is still holding."""
    first, second = LocalSql(), LocalSql()
    with ThreadPoolExecutor(max_workers=1) as executor:
        try:
            pending_first = executor.submit(first.execute, session_sql(first_call, True))
            wait_for(first, observer, "wait_event = 'PgSleep'", label + ': first holds')
            completed = second.execute(session_sql(second_call, False))
            still_holding = observer.require_success(
                "select exists(select 1 from pg_stat_activity where application_name = "
                f"'{first.application_name}' and wait_event = 'PgSleep');", label + ': first still holding')
            outcome = result_of(pending_first.result(timeout=60)), result_of(completed)
        finally:
            first.terminate_sessions()
            second.terminate_sessions()
    print(f'PARALLEL {label}: first={outcome[0]} second={outcome[1]} (second finished while first held: {still_holding})',
          flush=True)
    if still_holding != 't':
        raise HarnessFailure(f'{label}: the second creation waited for the first')
    return outcome


def rolled_back_first(observer, first_call, second_call, label):
    """First creates and holds, then rolls back (a failed request); second,
    blocked meanwhile, then creates the Clinic itself."""
    first, second = LocalSql(), LocalSql()
    *setup, operation = [part.strip() for part in first_call.split('; ') if part.strip()]
    first_sql = (ATTEMPT + 'begin;\n' + ''.join(f'{statement};\n' for statement in setup) +
                 f"select 'RESULT=' || pg_temp.attempt($q${operation}$q$);\n"
                 f"select pg_sleep({HOLD_SECONDS});\nrollback;\n")
    with ThreadPoolExecutor(max_workers=2) as executor:
        try:
            pending_first = executor.submit(first.execute, first_sql)
            wait_for(first, observer, "wait_event = 'PgSleep'", label + ': first holds')
            pending_second = executor.submit(second.execute, session_sql(second_call, False))
            wait_for(second, observer, "wait_event_type = 'Lock'", label + ': second blocked')
            outcome = result_of(pending_first.result(timeout=60)), result_of(pending_second.result(timeout=60))
        finally:
            first.terminate_sessions()
            second.terminate_sessions()
    print(f'RACE {label}: first (rolled back)={outcome[0]} second={outcome[1]}', flush=True)
    return outcome


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, create_call(OWNER_A, ORG_A, key(1)), create_call(ADMIN_A, ORG_A, key(1)),
                                 'same key, same Organization, two administrators')
            check(observer, f"{field(first, 'outcome')} = 'CREATED' and {field(second, 'outcome')} = 'ALREADY_CREATED' "
                  f"and {field(first, 'clinic_id')} = {field(second, 'clinic_id')} and {clinics_with(ORG_A, key(1))} = 1 "
                  f"and (select organization_id = '{ORG_A}' and not is_published from public.clinics "
                  f"where id = {field(first, 'clinic_id')}::uuid)",
                  'same key, same Organization: exactly one Clinic; the waiting administrator receives it')

            first, second = race(observer, create_call(ADMIN_A, ORG_A, key(2)), create_call(OWNER_A, ORG_A, key(3)),
                                 'different keys, same Organization')
            check(observer, f"{field(first, 'outcome')} = 'CREATED' and {field(second, 'outcome')} = 'CREATED' "
                  f"and {field(first, 'clinic_id')} <> {field(second, 'clinic_id')} "
                  f"and {clinics_with(ORG_A, key(2))} = 1 and {clinics_with(ORG_A, key(3))} = 1",
                  'different keys, same Organization: serialized, two distinct Clinics')

            first, second = parallel(observer, create_call(OWNER_A, ORG_A, key(4)), create_call(OWNER_B, ORG_B, key(4)),
                                     'same key, different Organizations')
            check(observer, f"{field(first, 'outcome')} = 'CREATED' and {field(second, 'outcome')} = 'CREATED' "
                  f"and {field(first, 'clinic_id')} <> {field(second, 'clinic_id')} "
                  f"and {field(first, 'organization_id')} = '{ORG_A}' and {field(second, 'organization_id')} = '{ORG_B}' "
                  f"and {clinics_with(ORG_A, key(4))} = 1 and {clinics_with(ORG_B, key(4))} = 1",
                  'same key, different Organizations: independent intents, no waiting, one Clinic in each')

            first, second = rolled_back_first(observer, create_call(OWNER_A, ORG_A, key(5)),
                                              create_call(ADMIN_A, ORG_A, key(5)), 'same key, first request fails')
            check(observer, f"{field(first, 'outcome')} = 'CREATED' and {field(second, 'outcome')} = 'CREATED' "
                  f"and {clinics_with(ORG_A, key(5))} = 1 "
                  f"and (select id from public.clinics where organization_id = '{ORG_A}' "
                  f"and creation_idempotency_key = '{key(5)}') = {field(second, 'clinic_id')}::uuid",
                  'same key after a failed first request: no partial result; the retry creates exactly one Clinic')

            check(observer, f"(select count(*) from public.clinics where organization_id in ('{ORG_A}', '{ORG_B}')) = 6 "
                  f"and not exists (select 1 from public.clinics where organization_id in ('{ORG_A}', '{ORG_B}') "
                  "and creation_idempotency_key is null) "
                  f"and (select count(*) = count(distinct (organization_id, creation_idempotency_key)) from public.clinics "
                  f"where organization_id in ('{ORG_A}', '{ORG_B}')) "
                  f"and not exists (select 1 from public.clinics c where c.organization_id in ('{ORG_A}', '{ORG_B}') "
                  "and (exists (select 1 from public.clinic_public_profiles p where p.clinic_id = c.id) "
                  "or exists (select 1 from public.clinic_locations l where l.clinic_id = c.id) or c.is_published))",
                  'every raced Clinic has its key, no duplicate key per Organization, no placeholder or publication')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0301000-'])


if __name__ == '__main__':
    main()

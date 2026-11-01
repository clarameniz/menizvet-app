"""LOCAL-only multi-session races for trusted Subscription transitions
(SPEC-SUB-002 §5/§14, BR-12/BR-13/BR-30, ADR-006).

Same discipline as run_clinic_creation_concurrency.py: a synthetic fixture
(prefix d0312000-) is committed to the isolated local database, real
apply_subscription_state_transition calls race in two psql sessions (the first
is observed holding its locks, the second observed blocked on a lock), and
every fixture row is always deleted afterwards in replica mode, because
Subscriptions and transitions are undeletable by ordinary operations.
Restoration and zero retained fixture rows are verified. Never point this at a
shared database.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql
from run_staff_invitation_concurrency import check, race


def fid(kind, n):
    return f'd0312000-0000-4000-8000-{kind * 100 + n:012d}'


def org(n):
    return fid(3, n)


def sub(n):
    return f"(select id from public.organization_subscriptions where organization_id = '{org(n)}')"


# Organizations 1-5 start ACTIVE (open-ended); 6-7 are PAST_DUE since 2021;
# 8 is PENDING.
FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into public.veterinary_organizations (id, display_name)
select ('d0312000-0000-4000-8000-' || lpad((300 + n)::text, 12, '0'))::uuid, 'Race Sub Org ' || n
from generate_series(1, 8) n;
set local session_replication_role = origin;
select public.establish_organization_subscription(
    ('d0312000-0000-4000-8000-' || lpad((300 + n)::text, 12, '0'))::uuid, null, 'ACTIVE', '2020-01-01Z',
    null, null, 'race-fixture', ('d0312000-0000-4000-8000-' || lpad((2000 + n)::text, 12, '0'))::uuid, null)
from generate_series(1, 7) n;
select public.establish_organization_subscription(
    'd0312000-0000-4000-8000-000000000308', null, 'PENDING', '2020-01-01Z', null, null, 'race-fixture',
    'd0312000-0000-4000-8000-000000002008', null);
select public.apply_subscription_state_transition(
    (select id from public.organization_subscriptions
     where organization_id = ('d0312000-0000-4000-8000-' || lpad((300 + n)::text, 12, '0'))::uuid),
    'PAST_DUE', '2021-01-01Z', null, null, 'race-fixture', null)
from generate_series(6, 7) n;
commit;
"""

CLEANUP = """
begin;
set local session_replication_role = replica;
delete from public.subscription_state_transitions where subscription_id in
    (select id from public.organization_subscriptions where organization_id::text like 'd0312000-%');
delete from public.organization_subscriptions where organization_id::text like 'd0312000-%';
delete from public.veterinary_organizations where id::text like 'd0312000-%';
commit;
"""


def transition_call(n, target, effective='statement_timestamp()', event_key='null'):
    return (f"select (select transition_id || '|' || from_state || '>' || to_state "
            f"from public.apply_subscription_state_transition({sub(n)}, '{target}', {effective}, null, null, "
            f"'race', {event_key}))")


def history(n):
    return (f"(select string_agg(from_state || '>' || to_state, ',' order by effective_at) "
            f"from public.subscription_state_transitions where subscription_id = {sub(n)})")


def state(n):
    return f"(select current_state from public.derive_organization_subscription_current_state({sub(n)}))"


def coherent(n):
    """One current relationship, strictly increasing effective times, and each
    from_state equal to the previous to_state."""
    return (f"(select count(*) <= 1 from public.organization_subscriptions s "
            f"cross join lateral public.derive_organization_subscription_current_state(s.id) d "
            f"where s.organization_id = '{org(n)}' and d.current_state <> 'EXPIRED') "
            f"and not exists (select 1 from (select from_state, effective_at, "
            f"lag(to_state) over (order by effective_at) as previous_to, "
            f"lag(effective_at) over (order by effective_at) as previous_at "
            f"from public.subscription_state_transitions where subscription_id = {sub(n)}) h "
            f"where h.previous_to is not null and (h.from_state <> h.previous_to or h.effective_at <= h.previous_at))")


def no_deadlock(*outcomes):
    if any('40P01' in outcome for outcome in outcomes):
        raise HarnessFailure('Deadlock observed: ' + ' / '.join(outcomes))


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, transition_call(1, 'PAST_DUE'), transition_call(1, 'CANCELLED'),
                                 'ACTIVE: PAST_DUE first, CANCELLED second')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|ACTIVE>PAST_DUE' "
                  f"and '{second}' = 'ERR:23514:SUBSCRIPTION_TRANSITION_NOT_ALLOWED' "
                  f"and {history(1)} = 'ACTIVE>PAST_DUE' and {state(1)} = 'PAST_DUE' and {coherent(1)}",
                  'competing PAST_DUE vs CANCELLED: one coherent history; the stale caller is rejected deterministically')

            first, second = race(observer, transition_call(2, 'CANCELLED'), transition_call(2, 'PAST_DUE'),
                                 'ACTIVE: CANCELLED first, PAST_DUE second')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|ACTIVE>CANCELLED' "
                  f"and '{second}' = 'ERR:23514:SUBSCRIPTION_TRANSITION_NOT_ALLOWED' "
                  f"and {history(2)} = 'ACTIVE>CANCELLED' and {coherent(2)}",
                  'competing CANCELLED vs PAST_DUE: the waiting transition is judged against the committed state')

            first, second = race(observer, transition_call(3, 'EXPIRED'), transition_call(3, 'PAST_DUE'),
                                 'ACTIVE: two transitions, EXPIRED first')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|ACTIVE>EXPIRED' "
                  f"and '{second}' = 'ERR:23514:SUBSCRIPTION_EXPIRED_TERMINAL' "
                  f"and {history(3)} = 'ACTIVE>EXPIRED' and {coherent(3)}",
                  'a transition racing an expiry meets a terminal period')

            duplicate = transition_call(4, 'PAST_DUE', "'2022-01-01Z'", "'evt-duplicate'")
            first, second = race(observer, duplicate, duplicate, 'same source event delivered twice')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|ACTIVE>PAST_DUE' and '{second}' = '{first}' "
                  f"and {history(4)} = 'ACTIVE>PAST_DUE' and {coherent(4)}",
                  'duplicate source event: exactly one transition; the waiting delivery receives the same result')

            first, second = race(observer, transition_call(6, 'ACTIVE'), transition_call(6, 'EXPIRED'),
                                 'PAST_DUE: recovery first, EXPIRED second')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|PAST_DUE>ACTIVE' and '{second}' like 'OK:%|ACTIVE>EXPIRED' "
                  f"and {history(6)} = 'ACTIVE>PAST_DUE,PAST_DUE>ACTIVE,ACTIVE>EXPIRED' "
                  f"and {state(6)} = 'EXPIRED' and {coherent(6)}",
                  'recovery then expiry: serialized into one ordered history ending EXPIRED')

            first, second = race(observer, transition_call(7, 'EXPIRED'), transition_call(7, 'ACTIVE'),
                                 'PAST_DUE: EXPIRED first, recovery second')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|PAST_DUE>EXPIRED' "
                  f"and '{second}' = 'ERR:23514:SUBSCRIPTION_EXPIRED_TERMINAL' "
                  f"and {history(7)} = 'ACTIVE>PAST_DUE,PAST_DUE>EXPIRED' and {state(7)} = 'EXPIRED' and {coherent(7)}",
                  'expiry then recovery: the late recovery cannot reopen the terminal period')

            first, second = race(observer, transition_call(8, 'EXPIRED'), transition_call(8, 'ACTIVE'),
                                 'PENDING: closure first, activation second')
            no_deadlock(first, second)
            check(observer, f"'{first}' like 'OK:%|PENDING>EXPIRED' "
                  f"and '{second}' = 'ERR:23514:SUBSCRIPTION_EXPIRED_TERMINAL' "
                  f"and {history(8)} = 'PENDING>EXPIRED' and {state(8)} = 'EXPIRED' and {coherent(8)}",
                  'a PENDING closed by EXPIRED cannot then be activated')

            check(observer, "not exists (select 1 from public.veterinary_organizations o "
                  "where o.id::text like 'd0312000-%' and (select count(*) from public.organization_subscriptions s "
                  "cross join lateral public.derive_organization_subscription_current_state(s.id) d "
                  "where s.organization_id = o.id and d.current_state <> 'EXPIRED') > 1)",
                  'no Organization ever holds two current Subscription relationships')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0312000-'])


if __name__ == '__main__':
    main()

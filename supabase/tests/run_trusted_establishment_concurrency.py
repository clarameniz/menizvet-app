"""LOCAL-only two-session races for ADR-009 trusted Organization establishment
(SPEC-ORG-001 §10, Verification Note 17).

Same discipline as run_clinic_creation_concurrency.py: a synthetic fixture
(prefix d0321000-) is committed to the isolated local database, real
establish_veterinary_organization calls race in two psql sessions, and every
fixture row is always deleted afterwards (in replica mode, because
Organizations, Memberships, Grants and Subscriptions are undeletable by
ordinary operations), with restoration and zero retained fixture rows
verified. Never point this at a shared database.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import LocalSql
from run_staff_invitation_concurrency import check, race
from run_clinic_creation_concurrency import parallel, rolled_back_first


def fid(kind, n):
    return f'd0321000-0000-4000-8000-{kind * 100 + n:012d}'


OWNER_A, OWNER_B = fid(2, 1), fid(2, 2)  # domain Users


def key(n):
    return fid(20, n)


FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0321000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'est-race-' || n || '@example.test', now()
from unnest(array[1, 2]) n;
insert into public.users (id)
select ('d0321000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 2]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0321000-0000-4000-8000-' || lpad((900 + n)::text, 12, '0'))::uuid,
    ('d0321000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0321000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2]) n;
commit;
"""

RACE_ORGANIZATIONS = "(select id from public.veterinary_organizations where establishment_idempotency_key::text like 'd0321000-%')"
CLEANUP = f"""
begin;
set local session_replication_role = replica;
create temporary table race_subscriptions on commit drop as
    select id from public.organization_subscriptions where organization_id in {RACE_ORGANIZATIONS};
delete from public.subscription_provider_references where subscription_id in (select id from race_subscriptions);
delete from public.subscription_state_transitions where subscription_id in (select id from race_subscriptions);
delete from public.organization_subscriptions where id in (select id from race_subscriptions);
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id in {RACE_ORGANIZATIONS});
delete from public.organization_memberships where organization_id in {RACE_ORGANIZATIONS};
delete from public.veterinary_organizations where id in {RACE_ORGANIZATIONS};
delete from public.user_authentication_identities where id::text like 'd0321000-%';
delete from public.users where id::text like 'd0321000-%';
delete from auth.users where id::text like 'd0321000-%';
commit;
"""


def establish_call(owner, name, establishment_key, state='ACTIVE', refs='null'):
    return (f"select public.establish_veterinary_organization('{owner}', '{name}', '{establishment_key}', "
            f"'{state}', null, null, null, 'race-suite', {refs})::text")


def field(result, name):
    if not result.startswith('OK:{'):
        return 'null'
    return f"('{result[3:]}'::jsonb ->> '{name}')"


def footprint_is_one(establishment_key):
    """Exactly one Organization, Owner Membership, OWNER Grant and initial
    Subscription for the key."""
    organization = f"(select id from public.veterinary_organizations where establishment_idempotency_key = '{establishment_key}')"
    return (f"(select count(*) from public.veterinary_organizations where establishment_idempotency_key = '{establishment_key}') = 1 "
            f"and (select count(*) from public.organization_memberships where organization_id = {organization}) = 1 "
            f"and (select count(*) from public.organization_responsibility_grants g join public.organization_memberships m "
            f"on m.id = g.membership_id where m.organization_id = {organization} and g.responsibility = 'OWNER') = 1 "
            f"and (select count(*) from public.organization_subscriptions where organization_id = {organization} "
            f"and establishment_idempotency_key = '{establishment_key}') = 1")


def same_ids(first, second):
    return ' and '.join(f"{field(first, name)} = {field(second, name)}"
                        for name in ('organization_id', 'owner_membership_id', 'subscription_id'))


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, establish_call(OWNER_A, 'Race Org', key(1)),
                                 establish_call(OWNER_A, 'Race Org', key(1)), 'identical establishment')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and {field(second, 'outcome')} = 'ALREADY_ESTABLISHED' "
                  f"and {same_ids(first, second)} and {footprint_is_one(key(1))}",
                  'identical: one footprint; the waiting caller receives the same ids')

            first, second = race(observer, establish_call(OWNER_A, 'Race Owner', key(2)),
                                 establish_call(OWNER_B, 'Race Owner', key(2)), 'same key, different Owner')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and '{second}' = 'ERR:23505:ESTABLISHMENT_KEY_CONFLICT' "
                  f"and {footprint_is_one(key(2))} and (select user_id = '{OWNER_A}' from public.organization_memberships "
                  f"where id = {field(first, 'owner_membership_id')}::uuid)",
                  'same key, different Owner: one establishment, one deterministic conflict')

            first, second = race(observer, establish_call(OWNER_A, 'Race Name One', key(3)),
                                 establish_call(OWNER_A, 'Race Name Two', key(3)), 'same key, different display name')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and '{second}' = 'ERR:23505:ESTABLISHMENT_KEY_CONFLICT' "
                  f"and {footprint_is_one(key(3))}",
                  'same key, different display name: one establishment, one deterministic conflict')

            first, second = race(observer, establish_call(OWNER_A, 'Race Facts', key(4), 'ACTIVE'),
                                 establish_call(OWNER_A, 'Race Facts', key(4), 'PENDING'), 'same key, different Subscription facts')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and '{second}' = 'ERR:23505:ESTABLISHMENT_KEY_CONFLICT' "
                  f"and {footprint_is_one(key(4))} and (select initial_state = 'ACTIVE' from public.organization_subscriptions "
                  f"where id = {field(first, 'subscription_id')}::uuid)",
                  'same key, different Subscription facts: one establishment, one deterministic conflict')

            refs_a = "'[{\"provider\":\"race\",\"reference_kind\":\"CUSTOMER\",\"opaque_reference\":\"race-a\"}]'"
            refs_b = "'[{\"provider\":\"race\",\"reference_kind\":\"CUSTOMER\",\"opaque_reference\":\"race-b\"}]'"
            first, second = race(observer, establish_call(OWNER_A, 'Race Refs', key(5), refs=refs_a),
                                 establish_call(OWNER_A, 'Race Refs', key(5), refs=refs_b), 'same key, different provider references')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and '{second}' = 'ERR:23505:ESTABLISHMENT_KEY_CONFLICT' "
                  f"and {footprint_is_one(key(5))} and (select array_agg(opaque_reference) = array['race-a'] "
                  f"from public.subscription_provider_references where subscription_id = {field(first, 'subscription_id')}::uuid)",
                  'same key, different provider references: one establishment with the first set, one conflict')

            first, second = parallel(observer, establish_call(OWNER_A, 'Race Parallel', key(6)),
                                     establish_call(OWNER_A, 'Race Parallel', key(7)), 'different keys, same Owner')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and {field(second, 'outcome')} = 'ESTABLISHED' "
                  f"and {field(first, 'organization_id')} <> {field(second, 'organization_id')} "
                  f"and {footprint_is_one(key(6))} and {footprint_is_one(key(7))}",
                  'different keys, same Owner: independent intents, no waiting, two Organizations')

            first, second = rolled_back_first(observer, establish_call(OWNER_A, 'Race Retry', key(8)),
                                              establish_call(OWNER_A, 'Race Retry', key(8)), 'same key, first request fails')
            check(observer, f"{field(first, 'outcome')} = 'ESTABLISHED' and {field(second, 'outcome')} = 'ESTABLISHED' "
                  f"and {footprint_is_one(key(8))} and (select id from public.veterinary_organizations "
                  f"where establishment_idempotency_key = '{key(8)}') = {field(second, 'organization_id')}::uuid",
                  'same key after a failed first request: nothing partial; the retry establishes exactly once')

            check(observer, f"(select count(*) from {RACE_ORGANIZATIONS} as raced) = 8 "
                  f"and not exists (select 1 from public.veterinary_organizations o where o.id in {RACE_ORGANIZATIONS} "
                  "and (select count(*) from public.organization_subscriptions s where s.organization_id = o.id) <> 1) "
                  f"and not exists (select 1 from public.clinics where organization_id in {RACE_ORGANIZATIONS})",
                  'every raced Organization has exactly one initial Subscription, its Owner, and no Clinic')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0321000-'])


if __name__ == '__main__':
    main()

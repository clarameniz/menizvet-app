"""LOCAL-only multi-session races for Staff Slice B2 (SPEC-ORG-003 BR-21, BR-24,
Notes 28, 29; SPEC-ORG-010 BR-11).

Same discipline as run_staff_invitation_concurrency.py, whose race primitives
this reuses: a small synthetic fixture (prefix d0281000-) is committed to the
isolated local database, real operations race in two psql sessions (the first
is observed holding its locks, the second observed blocked on a lock before the
first commits), and every fixture row is always deleted afterwards, with
restoration and zero retained fixture rows verified. Never point this at a
shared database.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import LocalSql
from run_staff_invitation_concurrency import check, race


def fid(kind, n):
    return f'd0281000-0000-4000-8000-{kind * 100 + n:012d}'


ORG = fid(3, 1)
OWNER, ADMIN = fid(1, 1), fid(1, 2)  # Auth subjects
# One fresh acceptor per race that must not already be a Member.
CARLOS, LAURA, ANA, BEA, DANI = (fid(1, n) for n in (11, 12, 13, 14, 15))
ACCEPTORS = (11, 12, 13, 14, 15)
UNIFORM = 'ERR:42501:Invitation unavailable'

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0281000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'b2-race-' || n || '@example.test', now()
from unnest(array[1, 2, {', '.join(map(str, ACCEPTORS))}]) n;
insert into public.users (id)
select ('d0281000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, {', '.join(map(str, ACCEPTORS))}]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0281000-0000-4000-8000-' || lpad((900 + n)::text, 12, '0'))::uuid,
    ('d0281000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0281000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 2, {', '.join(map(str, ACCEPTORS))}]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'B2 Race Org');
insert into public.clinics (id, organization_id) values ('{fid(4, 1)}', '{ORG}');
insert into public.organization_memberships (id, organization_id, user_id, effective_start) values
    ('{fid(5, 1)}', '{ORG}', '{fid(2, 1)}', '2020-01-01Z'), ('{fid(5, 2)}', '{ORG}', '{fid(2, 2)}', '2020-01-01Z');
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id) values
    ('{fid(6, 1)}', '{fid(5, 1)}', 'OWNER', 'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}'),
    ('{fid(6, 2)}', '{fid(5, 2)}', 'ADMINISTRATOR', 'ORGANIZATION', '2020-01-01Z', '{fid(2, 1)}');
commit;
"""

CLEANUP = f"""
begin;
set local session_replication_role = replica;
create temporary table race_invitations on commit drop as
    select id from public.organization_invitations where organization_id = '{ORG}';
create temporary table race_communications on commit drop as
    select id from public.transactional_communications where organization_invitation_id in (select id from race_invitations);
delete from public.communication_delivery_attempts where communication_id in (select id from race_communications);
delete from public.communication_delivery_jobs where communication_id in (select id from race_communications);
delete from public.transactional_communications where id in (select id from race_communications);
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.organization_invitation_responsibilities where invitation_id in (select id from race_invitations);
delete from public.organization_invitations where id in (select id from race_invitations);
delete from public.clinics where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0281000-%';
delete from public.users where id::text like 'd0281000-%';
delete from auth.users where id::text like 'd0281000-%';
commit;
"""


def invitation(email):
    return f"(select id from public.organization_invitations where organization_id = '{ORG}' and recipient_email = '{email}')"


def create(observer, email, secret, scope='ORGANIZATION'):
    clinic = f"'{fid(4, 1)}'" if scope == 'CLINIC' else 'null'
    observer.require_success(f"""begin;
        select public.create_staff_organization_invitation_with_communication('{OWNER}', '{ORG}', '{email}',
            'RECEPTIONIST', '{scope}', {clinic}, public.authorize_organization_invitation_creation('{OWNER}', '{ORG}'),
            sha256(convert_to('{secret}', 'UTF8')), 1, decode(repeat('0b', 12), 'hex'), decode(repeat('0c', 32), 'hex'));
        commit;""", 'Create race Invitation')


def accept_call(subject, email, secret):
    return (f"select set_config('request.jwt.claim.sub', '{subject}', false); "
            f"select public.accept_my_organization_invitation({invitation(email)}, '{secret}')::text")


def revoke_call(subject, email):
    return (f"select set_config('request.jwt.claim.sub', '{subject}', false); "
            f"select public.revoke_organization_invitation({invitation(email)}) ->> 'outcome'")


def outcome(result):
    """`OK:<json>` -> SQL expression for its `outcome` member."""
    return f"('{result[3:]}'::jsonb ->> 'outcome')" if result.startswith('OK:{') else 'null'


def accepted_counts(email):
    return (f"(select count(*) from public.organization_memberships where originating_invitation_id = {invitation(email)}) = 1 "
            f"and (select count(*) from public.organization_responsibility_grants g join public.organization_invitation_responsibilities r "
            f"on r.id = g.originating_invitation_responsibility_id where r.invitation_id = {invitation(email)}) = 1 "
            f"and (select acceptance_secret_digest is null and revoked_at is null from public.organization_invitations "
            f"where id = {invitation(email)})")


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            create(observer, 'same-user@race.test', 'same-user-secret', 'CLINIC')
            first, second = race(observer, accept_call(CARLOS, 'same-user@race.test', 'same-user-secret'),
                                 accept_call(CARLOS, 'same-user@race.test', 'same-user-secret'), 'accept vs accept, same User')
            check(observer, f"{outcome(first)} = 'ACCEPTED' and {outcome(second)} = 'ALREADY_ACCEPTED' "
                  f"and ('{first[3:]}'::jsonb ->> 'membership_id') = ('{second[3:]}'::jsonb ->> 'membership_id') "
                  f"and {accepted_counts('same-user@race.test')}",
                  'accept vs accept, same User: one Membership, the second resolves as ALREADY_ACCEPTED with it')

            create(observer, 'two-users@race.test', 'two-users-secret')
            first, second = race(observer, accept_call(LAURA, 'two-users@race.test', 'two-users-secret'),
                                 accept_call(ANA, 'two-users@race.test', 'two-users-secret'), 'accept by A vs accept by B')
            check(observer, f"{outcome(first)} = 'ACCEPTED' and '{second}' = '{UNIFORM}' "
                  f"and (select user_id = '{fid(2, 12)}' from public.organization_memberships "
                  f"where originating_invitation_id = {invitation('two-users@race.test')}) and {accepted_counts('two-users@race.test')}",
                  'accept by A vs B: A accepted once; B gets the uniform failure and learns nothing')

            create(observer, 'accept-first@race.test', 'accept-first-secret')
            first, second = race(observer, accept_call(ANA, 'accept-first@race.test', 'accept-first-secret'),
                                 revoke_call(ADMIN, 'accept-first@race.test'), 'accept vs revoke')
            check(observer, f"{outcome(first)} = 'ACCEPTED' and '{second}' = 'OK:ACCEPTED' and {accepted_counts('accept-first@race.test')}",
                  'accept vs revoke: acceptance wins, revocation reports ACCEPTED and records nothing')

            create(observer, 'revoke-first@race.test', 'revoke-first-secret')
            first, second = race(observer, revoke_call(OWNER, 'revoke-first@race.test'),
                                 accept_call(CARLOS, 'revoke-first@race.test', 'revoke-first-secret'), 'revoke vs accept')
            check(observer, f"'{first}' = 'OK:REVOKED' and '{second}' = 'ERR:23514:INVITATION_REVOKED' and not exists "
                  f"(select 1 from public.organization_memberships where originating_invitation_id = {invitation('revoke-first@race.test')}) "
                  f"and (select acceptance_secret_digest is not null from public.organization_invitations "
                  f"where id = {invitation('revoke-first@race.test')})",
                  'revoke vs accept: revocation wins, acceptance reports REVOKED after proof, digest retained')

            # Wrong-secret acceptance is serialized on the Organization before
            # proof, then fails uniformly.
            create(observer, 'holder-1@race.test', 'holder-1-secret')
            create(observer, 'unproven@race.test', 'unproven-secret')
            first, second = race(observer, revoke_call(OWNER, 'holder-1@race.test'),
                                 accept_call(CARLOS, 'unproven@race.test', 'not-the-secret'), 'revoke vs unproven accept')
            check(observer, f"'{first}' = 'OK:REVOKED' and '{second}' = '{UNIFORM}' and (select acceptance_secret_digest is not null "
                  f"from public.organization_invitations where id = {invitation('unproven@race.test')})",
                  'unproven acceptance waits for the Organization lock, then fails uniformly without writing')

            # Same User, two Invitations to two addresses of the same
            # Organization: the second sees the first's Membership.
            create(observer, 'address-one@race.test', 'address-one-secret')
            create(observer, 'address-two@race.test', 'address-two-secret')
            first, second = race(observer, accept_call(BEA, 'address-one@race.test', 'address-one-secret'),
                                 accept_call(BEA, 'address-two@race.test', 'address-two-secret'),
                                 'accept vs independently-created Membership')
            check(observer, f"{outcome(first)} = 'ACCEPTED' and '{second}' = 'ERR:23505:ALREADY_MEMBER' and (select count(*) "
                  f"from public.organization_memberships where organization_id = '{ORG}' and user_id = '{fid(2, 14)}' "
                  f"and effective_end is null) = 1 and (select acceptance_secret_digest is not null and revoked_at is null "
                  f"from public.organization_invitations where id = {invitation('address-two@race.test')})",
                  'concurrent second Membership for the same User: ALREADY_MEMBER, one active Membership, other Invitation pending')

            # Expiry boundary: the blocked acceptance decides at its own
            # statement instant (before expiry), which is also the Membership
            # start; an acceptance started after expiry is EXPIRED.
            observer.require_success(f"""begin; set local session_replication_role = replica;
                insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email,
                    created_at, expires_at, acceptance_secret_digest) values
                    ('{fid(7, 1)}', '{ORG}', '{fid(2, 1)}', 'expiring@race.test', clock_timestamp() - interval '1 day',
                        clock_timestamp() + interval '3 seconds', sha256(convert_to('expiring-secret', 'UTF8'))),
                    ('{fid(7, 2)}', '{ORG}', '{fid(2, 1)}', 'expiring-later@race.test', clock_timestamp() - interval '1 day',
                        clock_timestamp() + interval '3 seconds', sha256(convert_to('expiring-later-secret', 'UTF8')));
                insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type) values
                    ('{fid(8, 1)}', '{fid(7, 1)}', 'RECEPTIONIST', 'ORGANIZATION'),
                    ('{fid(8, 2)}', '{fid(7, 2)}', 'RECEPTIONIST', 'ORGANIZATION');
                commit;""", 'Commit expiring Invitations')
            create(observer, 'holder-2@race.test', 'holder-2-secret')
            first, second = race(observer, revoke_call(OWNER, 'holder-2@race.test'),
                                 accept_call(DANI, 'expiring@race.test', 'expiring-secret'), 'accept across the expiry boundary')
            check(observer, f"{outcome(second)} = 'ACCEPTED' and (select m.effective_start < i.expires_at "
                  f"from public.organization_memberships m join public.organization_invitations i on i.id = m.originating_invitation_id "
                  f"where i.id = '{fid(7, 1)}') and clock_timestamp() > (select expires_at from public.organization_invitations "
                  f"where id = '{fid(7, 1)}')",
                  'accept blocked across expiry decides at its own instant, before expiry, and starts the Membership there')
            # A real rejected call (not a mutant): only the reported outcome is used.
            result = observer.execute(f"select set_config('request.jwt.claim.sub', '{LAURA}', false);\n"
                                      f"select public.accept_my_organization_invitation('{fid(7, 2)}', 'expiring-later-secret');")
            check(observer, f"{'true' if 'INVITATION_EXPIRED' in result.stderr and result.returncode else 'false'} "
                  f"and not exists (select 1 from public.organization_memberships where originating_invitation_id = '{fid(7, 2)}')",
                  'accept started after expiry: EXPIRED, nothing written')

            check(observer, f"(select count(*) from public.transactional_communications c join public.organization_invitations i "
                  f"on i.id = c.organization_invitation_id where i.organization_id = '{ORG}') = (select count(*) from "
                  f"public.organization_invitations where organization_id = '{ORG}' and id::text not like 'd0281000-%') "
                  "and not exists (select 1 from public.communication_delivery_jobs j join public.transactional_communications c "
                  f"on c.id = j.communication_id join public.organization_invitations i on i.id = c.organization_invitation_id "
                  f"where i.organization_id = '{ORG}')",
                  'races created no Communication or delivery work beyond one Communication per created Invitation')
            check(observer, f"(select count(*) from (select user_id from public.organization_memberships where organization_id = '{ORG}' "
                  "and effective_end is null group by user_id having count(*) > 1) duplicate) = 0",
                  'no User holds two active Memberships in the Organization')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0281000-'])


if __name__ == '__main__':
    main()

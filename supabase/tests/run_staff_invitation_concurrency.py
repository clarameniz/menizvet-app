"""LOCAL-only multi-session races for Staff Slice B1 (SPEC-ORG-002 Note 25,
SPEC-ORG-010 BR-11, SPEC-COM-001 BR-45).

Unlike the rollback-only suites, a second backend can only observe committed
rows, so this runner commits a small synthetic fixture (prefix d0271000-) to
the isolated local database, races real operations in two psql sessions, and
always deletes every fixture row afterwards. Each race is deterministic: the
first session is observed holding its locks (pg_sleep) and the second is
observed blocked on a lock before the first commits. Cleanup runs on success,
failure and interruption; restoration of public/Auth row counts and function
definitions plus zero retained fixture rows are verified. Never point this at
a shared database.
"""
from concurrent.futures import ThreadPoolExecutor
import sys
import time
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql

HOLD_SECONDS = 6


def fid(kind, n):
    return f'd0271000-0000-4000-8000-{kind * 100 + n:012d}'


ORG = fid(3, 1)
OWNER, ADMIN = fid(1, 1), fid(1, 2)  # Auth subjects
RECIPIENT_A, RECIPIENT_B = fid(2, 11), fid(2, 12)  # domain Users

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at) values
    ('{fid(1, 1)}', 'race-owner@example.test', now()), ('{fid(1, 2)}', 'race-admin@example.test', now()),
    ('{fid(1, 11)}', 'race-r1@example.test', now()), ('{fid(1, 12)}', 'race-r2@example.test', now());
insert into public.users (id) values ('{fid(2, 1)}'), ('{fid(2, 2)}'), ('{fid(2, 11)}'), ('{fid(2, 12)}');
insert into public.user_authentication_identities (id, user_id, provider_subject) values
    ('{fid(9, 1)}', '{fid(2, 1)}', '{fid(1, 1)}'), ('{fid(9, 2)}', '{fid(2, 2)}', '{fid(1, 2)}'),
    ('{fid(9, 11)}', '{fid(2, 11)}', '{fid(1, 11)}'), ('{fid(9, 12)}', '{fid(2, 12)}', '{fid(1, 12)}');
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'Race Org');
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
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0271000-%';
delete from public.users where id::text like 'd0271000-%';
delete from auth.users where id::text like 'd0271000-%';
commit;
"""

# Each session runs exactly one operation through this capture helper, so an
# expected domain rejection is an observable outcome rather than an abort.
ATTEMPT = """create function pg_temp.attempt(statement text) returns text language plpgsql as $f$
declare result text; failure_hint text; begin
    execute statement into result;
    return 'OK:' || coalesce(result, 'null');
exception when others then
    get stacked diagnostics failure_hint = pg_exception_hint;
    return 'ERR:' || sqlstate || ':' || coalesce(nullif(failure_hint, ''), sqlerrm);
end $f$;
"""


def create_call(subject, email, digest='aa'):
    return (f"select public.create_staff_organization_invitation_with_communication('{subject}', '{ORG}', "
            f"'{email}', 'RECEPTIONIST', 'ORGANIZATION', null, "
            f"public.authorize_organization_invitation_creation('{subject}', '{ORG}'), "
            f"decode(repeat('{digest}', 32), 'hex'), 1, decode(repeat('0b', 12), 'hex'), "
            f"decode(repeat('0c', 32), 'hex'))::text")


def revoke_call(subject, email):
    return (f"select set_config('request.jwt.claim.sub', '{subject}', false); "
            f"select public.revoke_organization_invitation((select id from public.organization_invitations "
            f"where organization_id = '{ORG}' and recipient_email = '{email}')) ->> 'outcome'")


def accept_call(user, email, digest):
    return (f"select public.accept_organization_invitation('{user}', (select id from public.organization_invitations "
            f"where organization_id = '{ORG}' and recipient_email = '{email}'), decode(repeat('{digest}', 32), 'hex'))::text")


def handoff_call(job):
    return f"select public.mark_communication_delivery_submission_started('{job}', '{fid(14, int(job[-2:]))}')"


def session_sql(call, hold):
    # A setup statement (set_config) may precede the operation inside `call`.
    *setup, operation = [part.strip() for part in call.split('; ') if part.strip()]
    statements = ''.join(f'{statement};\n' for statement in setup)
    sleep = f'select pg_sleep({HOLD_SECONDS});\n' if hold else ''
    return (ATTEMPT + 'begin;\n' + statements +
            f"select 'RESULT=' || pg_temp.attempt($q${operation}$q$);\n" + sleep + 'commit;\n')


def result_of(completed):
    if completed.returncode:
        raise HarnessFailure('Race session failed:\n' + completed.stderr)
    lines = [line for line in completed.stdout.splitlines() if line.startswith('RESULT=')]
    if len(lines) != 1:
        raise HarnessFailure('Race session produced no single result:\n' + completed.stdout)
    return lines[0][len('RESULT='):]


def wait_for(client, observer, condition, label):
    deadline = time.monotonic() + HOLD_SECONDS - 1
    while time.monotonic() < deadline:
        if observer.require_success(
                "select exists(select 1 from pg_stat_activity where application_name = "
                f"'{client.application_name}' and {condition});", label) == 't':
            return
        time.sleep(0.05)
    raise HarnessFailure(f'Race not established: {label}')


def race(observer, first_call, second_call, label):
    """First holds its locks; second is observed blocked; first commits."""
    first, second = LocalSql(), LocalSql()
    with ThreadPoolExecutor(max_workers=2) as executor:
        try:
            pending_first = executor.submit(first.execute, session_sql(first_call, True))
            wait_for(first, observer, "wait_event = 'PgSleep'", label + ': first holds')
            pending_second = executor.submit(second.execute, session_sql(second_call, False))
            wait_for(second, observer, "wait_event_type = 'Lock'", label + ': second blocked')
            outcome = result_of(pending_first.result(timeout=60)), result_of(pending_second.result(timeout=60))
        finally:
            first.terminate_sessions()
            second.terminate_sessions()
    print(f'RACE {label}: first={outcome[0]} second={outcome[1]}', flush=True)
    return outcome


def check(observer, condition, label):
    if observer.require_success(f'select ({condition})::text;', label) != 'true':
        raise HarnessFailure('Race assertion failed: ' + label)
    print('PASS ' + label, flush=True)


def invitation(email):
    return f"(select id from public.organization_invitations where organization_id = '{ORG}' and recipient_email = '{email}')"


def setup_invitation(observer, email, digest, job=None):
    observer.require_success(f"begin;\n{create_call(OWNER, email, digest)};\ncommit;", 'Create race Invitation')
    if job is not None:
        observer.require_success(f"""begin;
            set local session_replication_role = replica;
            insert into public.communication_delivery_jobs (id, communication_id, channel, provider, destination_key,
                destination_snapshot, state, lease_token, lease_expires_at)
            select '{job}', c.id, 'EMAIL', 'RESEND', 'EMAIL:{email}', '{email}', 'CLAIMED',
                '{fid(14, int(job[-2:]))}', clock_timestamp() + interval '5 minutes'
            from public.transactional_communications c where c.organization_invitation_id = {invitation(email)};
            commit;""", 'Claim race delivery Job')


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')

            first, second = race(observer, create_call(OWNER, 'dup@race.test', 'a1'),
                                 create_call(ADMIN, 'DUP@race.test', 'a2'), 'duplicate invite')
            check(observer, f"'{first}' ~ '^OK:[0-9a-f-]{{36}}$' and '{second}' = 'ERR:23505:PENDING_INVITATION_EXISTS'",
                  'duplicate invite race: one creation, one calm conflict')
            check(observer, f"(select count(*) from public.organization_invitations where organization_id = '{ORG}' "
                  "and recipient_email_normalized = 'dup@race.test') = 1 and (select count(*) from "
                  "public.transactional_communications where lower(recipient_email) = 'dup@race.test') = 1",
                  'duplicate invite race: exactly one pending Invitation and one Communication')

            setup_invitation(observer, 'twice@race.test', 'b1')
            first, second = race(observer, revoke_call(OWNER, 'twice@race.test'),
                                 revoke_call(ADMIN, 'twice@race.test'), 'revoke vs revoke')
            check(observer, f"'{first}' = 'OK:REVOKED' and '{second}' = 'OK:ALREADY_REVOKED' and (select "
                  f"revoked_by_user_id = '{fid(2, 1)}' and revoked_at is not null from public.organization_invitations "
                  f"where id = {invitation('twice@race.test')})", 'revoke vs revoke: one REVOKED, one ALREADY_REVOKED, one record')

            setup_invitation(observer, 'revoke-first@race.test', 'c1')
            first, second = race(observer, revoke_call(OWNER, 'revoke-first@race.test'),
                                 accept_call(RECIPIENT_A, 'revoke-first@race.test', 'c1'), 'revoke vs accept')
            check(observer, f"'{first}' = 'OK:REVOKED' and '{second}' like 'ERR:23514:%' and not exists (select 1 from "
                  f"public.organization_memberships where originating_invitation_id = {invitation('revoke-first@race.test')})",
                  'revoke vs accept: revocation wins, no Membership')

            setup_invitation(observer, 'accept-first@race.test', 'd1')
            first, second = race(observer, accept_call(RECIPIENT_B, 'accept-first@race.test', 'd1'),
                                 revoke_call(ADMIN, 'accept-first@race.test'), 'accept vs revoke')
            check(observer, f"'{first}' ~ '^OK:[0-9a-f-]{{36}}$' and '{second}' = 'OK:ACCEPTED' and (select "
                  "revoked_at is null and acceptance_secret_digest is null from public.organization_invitations where id = "
                  f"{invitation('accept-first@race.test')}) and (select count(*) from public.organization_memberships where "
                  f"originating_invitation_id = {invitation('accept-first@race.test')}) = 1 and (select count(*) from "
                  "public.organization_responsibility_grants g join public.organization_invitation_responsibilities r on "
                  f"r.id = g.originating_invitation_responsibility_id where r.invitation_id = {invitation('accept-first@race.test')}) = 1",
                  'accept vs revoke: acceptance wins, ACCEPTED, one Membership and Grant')

            # Expiry boundary: the blocked revocation's instant is its statement
            # instant (before expiry); a revocation started after expiry is EXPIRED.
            observer.require_success(f"""begin; set local session_replication_role = replica;
                insert into public.organization_invitations (id, organization_id, inviting_user_id, recipient_email,
                    created_at, expires_at, acceptance_secret_digest) values
                    ('{fid(7, 1)}', '{ORG}', '{fid(2, 1)}', 'expiring@race.test', clock_timestamp() - interval '1 day',
                        clock_timestamp() + interval '3 seconds', decode(repeat('e1', 32), 'hex')),
                    ('{fid(7, 2)}', '{ORG}', '{fid(2, 1)}', 'expiring-later@race.test', clock_timestamp() - interval '1 day',
                        clock_timestamp() + interval '3 seconds', decode(repeat('e2', 32), 'hex'));
                insert into public.organization_invitation_responsibilities (id, invitation_id, responsibility, scope_type) values
                    ('{fid(8, 1)}', '{fid(7, 1)}', 'RECEPTIONIST', 'ORGANIZATION'), ('{fid(8, 2)}', '{fid(7, 2)}', 'RECEPTIONIST', 'ORGANIZATION');
                commit;""", 'Commit expiring Invitations')
            setup_invitation(observer, 'holder@race.test', 'f1')
            first, second = race(observer, revoke_call(OWNER, 'holder@race.test'),
                                 revoke_call(ADMIN, 'expiring@race.test'), 'revoke across the expiry boundary')
            check(observer, f"'{second}' = 'OK:REVOKED' and (select revoked_at < expires_at from public.organization_invitations "
                  f"where id = '{fid(7, 1)}') and clock_timestamp() > (select expires_at from public.organization_invitations "
                  f"where id = '{fid(7, 1)}')", 'revoke blocked across expiry decides at its own instant, before expiry')
            late = observer.require_success(f"select set_config('request.jwt.claim.sub', '{OWNER}', false); "
                                            f"select public.revoke_organization_invitation('{fid(7, 2)}') ->> 'outcome';",
                                            'Revoke after expiry').splitlines()[-1]
            check(observer, f"'{late}' = 'EXPIRED' and (select revoked_at is null from public.organization_invitations "
                  f"where id = '{fid(7, 2)}')", 'revoke started after expiry: EXPIRED, nothing recorded')

            setup_invitation(observer, 'handoff-late@race.test', '11', job=fid(13, 1))
            first, second = race(observer, revoke_call(OWNER, 'handoff-late@race.test'), handoff_call(fid(13, 1)),
                                 'revoke vs provider handoff')
            check(observer, f"'{first}' = 'OK:REVOKED' and '{second}' = 'OK:SUPPRESSED' and (select state = 'SUPPRESSED' "
                  f"and submission_count = 0 from public.communication_delivery_jobs where id = '{fid(13, 1)}') and not exists "
                  f"(select 1 from public.communication_delivery_attempts where delivery_job_id = '{fid(13, 1)}')",
                  'revoke vs handoff: revocation committed first, email never handed to the provider')

            setup_invitation(observer, 'handoff-first@race.test', '12', job=fid(13, 2))
            first, second = race(observer, handoff_call(fid(13, 2)), revoke_call(ADMIN, 'handoff-first@race.test'),
                                 'provider handoff vs revoke')
            check(observer, f"'{first}' = 'OK:STARTED' and '{second}' = 'OK:REVOKED' and (select state = 'CLAIMED' and "
                  f"submission_count = 1 from public.communication_delivery_jobs where id = '{fid(13, 2)}')",
                  'handoff vs revoke: handoff started first, revocation then recorded without recall')
            check(observer, f"(select count(*) from public.transactional_communications c join public.organization_invitations i "
                  f"on i.id = c.organization_invitation_id where i.organization_id = '{ORG}') = (select count(*) from "
                  f"public.organization_invitations where organization_id = '{ORG}' and id::text not like 'd0271000-%')",
                  'races created no Communication beyond one per created Invitation')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0271000-'])


if __name__ == '__main__':
    main()

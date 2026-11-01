"""LOCAL-only multi-session races for editing Clinical Record Entries
(SPEC-MED-010 BR-18 and BR-23b: author only, idempotent, stale-version safe;
SPEC-SUB-004 BR-20; SPEC-MED-010 BR-26: edits and Guardian revocation do not
interact). Versions are stored as Clinical Amendments of kind EDIT.

Same discipline as run_clinical_record_concurrency.py, whose race primitives
this reuses: a synthetic fixture (prefix d0352000-) is committed to the
isolated local database, the real client operation races in two psql sessions
(the first observed holding its locks, the second observed blocked on a lock
before the first commits), and every fixture row and every row the operations
created is always deleted afterwards, with restoration and zero retained
fixture rows verified. A deadlock would surface as ERR:40P01 and fail the exact
outcome checks. Pairs that take no conflicting locks run as overlapping
transactions that must not block each other. Never point this at a shared
database.
"""
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import LocalSql
from run_staff_invitation_concurrency import check, race, result_of, session_sql
from run_clinical_record_concurrency import overlap


def fid(kind, n):
    return f'd0352000-0000-4000-8000-{kind * 100 + n:012d}'


ORG, CLINIC, PET, GUARDIANSHIP = fid(3, 1), fid(4, 1), fid(9, 1), fid(9, 2)
GUARDIAN, ADMIN, VET, VET2, VET3 = fid(1, 1), fid(1, 5), fid(1, 10), fid(1, 11), fid(1, 12)  # Auth subjects

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0352000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'amendment-race-' || n || '@example.test', now()
from unnest(array[1, 5, 10, 11, 12]) n;
insert into public.users (id)
select ('d0352000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 5, 10, 11, 12]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0352000-0000-4000-8000-' || lpad((1900 + n)::text, 12, '0'))::uuid,
    ('d0352000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0352000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 5, 10, 11, 12]) n;
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'Amendment Race Org');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values ('{CLINIC}', '{ORG}', true, 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0352000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{ORG}',
    ('d0352000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[5, 10, 11, 12]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0352000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0352000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 5 then 'ADMINISTRATOR' else 'VETERINARIAN' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 5)}'
from unnest(array[5, 10, 11, 12]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select ('d0352000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0352000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array[10, 11, 12]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
select ('d0352000-0000-4000-8000-' || lpad((800 + n)::text, 12, '0'))::uuid,
    ('d0352000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0352000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, '{CLINIC}', '2020-01-01Z'
from unnest(array[10, 11, 12]) n;
insert into public.pets (id, name, species, created_at) values ('{PET}', 'Amendment Race Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values ('{GUARDIANSHIP}', '{fid(2, 1)}', '{PET}', '2020-01-01Z');
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select ('d0352000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{fid(2, 1)}',
    'Amendment race visit ' || n, 'CONFIRMED', '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 4) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at,
    scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select ('d0352000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, r,
    case r when 1 then 'REQUESTED' else 'CONFIRMED' end, '2026-06-01T10:00Z'::timestamptz + make_interval(days => n),
    '2026-06-01T10:30Z'::timestamptz + make_interval(days => n), 'Europe/Madrid',
    case r when 1 then '{fid(2, 1)}'::uuid else '{fid(2, 5)}'::uuid end, null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from generate_series(1, 4) n, unnest(array[1, 2]) r;
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select ('d0352000-0000-4000-8000-' || lpad((1200 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{ORG}', '{GUARDIANSHIP}',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE',
    ('d0352000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'ACTIVE'
from generate_series(1, 4) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select ('d0352000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'REQUESTED', 'CONFIRMED', '{fid(2, 5)}',
    'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(1, 4) n;
-- Veterinarian 10 is assigned to 1, 3 and 4; Veterinarian 12 to 2.
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select ('d0352000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid,
    case when n = 2 then '{fid(8, 12)}'::uuid else '{fid(8, 10)}'::uuid end, '2026-03-01Z', '{fid(2, 5)}'
from generate_series(1, 4) n;
set local session_replication_role = origin;
select public.establish_organization_subscription('{ORG}', null, 'ACTIVE', '2020-01-01Z', null, null,
    'amendment-race', '{fid(20, 1)}', null);
commit;
"""

APPOINTMENT_FILTER = "appointment_id::text like 'd0352000-%'"
ENTRY_FILTER = (f"clinical_record_entry_id in (select e.id from public.clinical_record_entries e "
                f"join public.appointments a on a.id = e.appointment_id where a.pet_id = '{PET}')")
CLEANUP = f"""
begin;
set local session_replication_role = replica;
delete from public.medical_access_audit_events where pet_id = '{PET}';
delete from public.clinical_amendments where original_{ENTRY_FILTER};
delete from public.clinical_attachments where {ENTRY_FILTER};
delete from public.clinical_record_entries where {APPOINTMENT_FILTER};
delete from public.appointment_lifecycle_events where {APPOINTMENT_FILTER};
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
delete from public.veterinarian_professional_profiles where user_id::text like 'd0352000-%';
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id = '{ORG}');
delete from public.organization_memberships where organization_id = '{ORG}';
delete from public.clinics where organization_id = '{ORG}';
delete from public.veterinary_organizations where id = '{ORG}';
delete from public.user_authentication_identities where id::text like 'd0352000-%';
delete from public.users where id::text like 'd0352000-%';
delete from auth.users where id::text like 'd0352000-%';
commit;
"""


def appt(n):
    return fid(11, n)


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def edit_call(subject, n, entry, key, expected, content, category='TREATMENT'):
    """"Guardar cambios" on the version the editor was opened on (SPEC-MED-010 BR-23b)."""
    return as_subject(subject, f"select public.edit_appointment_clinical_entry('{CLINIC}', '{appt(n)}', '{entry}', "
                               f"'{key}', {expected}, '{category}', '{content}', null)::text")


def end_assignment_call(assignment):
    return as_subject(ADMIN, f"select public.end_staff_veterinarian_clinic_assignment('{ORG}', '{CLINIC}', '{assignment}')::text")


def revoke_call(n):
    return as_subject(GUARDIAN, f"select public.revoke_my_appointment_care_authorization('{appt(n)}')::text")


def lapse_call():
    return (f"select public.apply_subscription_state_transition((select id from public.organization_subscriptions "
            f"where organization_id = '{ORG}'), 'PAST_DUE', statement_timestamp(), null, null, 'amendment-race', null)::text")


def outcome(result):
    return f"('{result[3:]}'::jsonb ->> 'outcome')" if result.startswith('OK:{') else 'null'


def field(result, name):
    return f"('{result[3:]}'::jsonb ->> '{name}')" if result.startswith('OK:{') else 'null'


def versions(entry):
    """Stored versions after the first (kind EDIT)."""
    return (f"(select count(*) from public.clinical_amendments where original_clinical_record_entry_id = '{entry}' "
            f"and change_kind = 'EDIT')")


def edited(result, version):
    return f"'{result}' = 'OK:{{\"outcome\": \"EDITED\", \"version\": {version}}}'"


def entries_fingerprint():
    return (f"(select md5(string_agg(to_jsonb(e)::text, '|' order by e.id)) from public.clinical_record_entries e "
            f"join public.appointments a on a.id = e.appointment_id where a.pet_id = '{PET}')")


def committed(observer, subject, statement, label):
    """One committed setup call as the impersonated User; returns its text result."""
    return observer.require_success(
        f"begin;\nselect set_config('request.jwt.claim.sub', '{subject}', true);\n{statement};\ncommit;", label
    ).splitlines()[-1].strip()


def setup_entry(observer, subject, n, key):
    """"Guardar registro" as the assigned Veterinarian (SPEC-MED-010 BR-23)."""
    return committed(observer, subject, f"select (public.create_appointment_clinical_entry('{CLINIC}', '{appt(n)}', "
                                        f"'{key}', 'TREATMENT', 'Dose 50 mg', null) ->> 'entry_id')",
                     f'Record Entry {n}')


def single(call):
    """One uncontended call in its own committed session."""
    return result_of(LocalSql().execute(session_sql(call, False)))


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')
            entry = setup_entry(observer, VET, 1, fid(13, 1))
            authored_by_vet3 = setup_entry(observer, VET3, 2, fid(13, 2))
            # Entries of Appointments whose authorization is revoked during the races.
            revoked_entries = {n: setup_entry(observer, VET, n, fid(13, n)) for n in (3, 4)}
            original = observer.require_success(f'select {entries_fingerprint()};', 'Fingerprint recorded Entries')

            first, second = race(observer, edit_call(VET, 1, entry, fid(20, 1), 1, 'Dose 5 mg'),
                                 edit_call(VET, 1, entry, fid(20, 1), 1, 'Dose 5 mg'), 'same key, same request')
            check(observer, f"{edited(first, 2)} "
                  f"and '{second}' = 'OK:{{\"outcome\": \"ALREADY_EDITED\", \"version\": 2}}' and {versions(entry)} = 1",
                  'same key, same request: one EDITED, one ALREADY_EDITED for the same version; no duplicate')

            first, second = race(observer, edit_call(VET, 1, entry, fid(20, 2), 2, 'Dose 5 mg twice daily'),
                                 edit_call(VET, 1, entry, fid(20, 2), 2, 'Dose 6 mg'), 'same key, conflicting request')
            check(observer, f"{edited(first, 3)} and '{second}' = 'ERR:23505:KEY_CONFLICT' and {versions(entry)} = 2 "
                  f"and (select amendment_content = 'Dose 5 mg twice daily' from public.clinical_amendments "
                  f"where idempotency_key = '{fid(20, 2)}')",
                  'same key, conflicting request: the first stands; the second is a deterministic KEY_CONFLICT')

            first, second = race(observer, edit_call(VET, 1, entry, fid(20, 3), 3, 'With food'),
                                 edit_call(VET, 1, entry, fid(20, 4), 3, 'Morning dose'), 'two edits of the same version')
            check(observer, f"{edited(first, 4)} and '{second}' = 'ERR:P0001:STALE_VERSION' and {versions(entry)} = 3 "
                  f"and not exists (select 1 from public.clinical_amendments where idempotency_key = '{fid(20, 4)}') "
                  f"and (select amendment_content = 'With food' from public.clinical_amendments "
                  f"where original_clinical_record_entry_id = '{entry}' and version_number = 4)",
                  'two edits opened on the same version: the first becomes version 4; the second waits and is STALE_VERSION')

            first, second = race(observer, edit_call(VET, 1, entry, fid(20, 11), 4, 'Evening dose'),
                                 edit_call(VET2, 1, entry, fid(20, 12), 4, 'Not my Entry'), 'author vs another Veterinarian')
            check(observer, f"{edited(first, 5)} and '{second}' = 'ERR:23514:ENTRY_AUTHOR_REQUIRED' "
                  f"and {versions(entry)} = 4",
                  'author vs another Veterinarian: the author edits; the other waits and is refused (BR-18)')

            first, second = race(observer, lapse_call(), edit_call(VET, 1, entry, fid(20, 5), 5, 'After lapse'),
                                 'Subscription lapse vs edit')
            check(observer, f"'{first}' like 'OK:%' and {edited(second, 6)} and {versions(entry)} = 5 "
                  f"and not public.organization_has_professional_entitlement('{ORG}', 'CLINICAL_CARE')",
                  'Subscription lapse vs edit: the edit waits and still succeeds without Entitlement')

            first, second = overlap(observer, revoke_call(3),
                                    edit_call(VET, 3, revoked_entries[3], fid(20, 9), 1, 'After revocation'),
                                    'Guardian revoke with edit')
            check(observer, f"{outcome(first)} = 'REVOKED' and {edited(second, 2)} "
                  f"and {versions(revoked_entries[3])} = 1 "
                  f"and (select lifecycle_state = 'REVOKED' from public.care_authorizations where appointment_id = '{appt(3)}')",
                  'Guardian revoke with edit: neither waits; the author keeps editing (BR-11, BR-18)')

            first, second = overlap(observer, edit_call(VET, 4, revoked_entries[4], fid(20, 10), 1, 'Before revocation'),
                                    revoke_call(4), 'edit with Guardian revoke')
            check(observer, f"{edited(first, 2)} and {outcome(second)} = 'REVOKED' "
                  f"and {versions(revoked_entries[4])} = 1",
                  'edit with Guardian revoke: neither waits; both stand')

            first, second = race(observer, end_assignment_call(fid(8, 12)),
                                 edit_call(VET3, 2, authored_by_vet3, fid(20, 6), 1, 'After my offboarding'),
                                 'author offboarding vs own edit')
            check(observer, f"{outcome(first)} = 'ENDED' and '{second}' = 'ERR:42501:Clinical record unavailable' "
                  f"and {versions(authored_by_vet3)} = 0",
                  'author offboarding vs own edit: the edit waits, then the former Veterinarian is refused')
            other = single(edit_call(VET2, 2, authored_by_vet3, fid(20, 13), 1, 'Author left'))
            check(observer, f"'{other}' = 'ERR:23514:ENTRY_AUTHOR_REQUIRED' and {versions(authored_by_vet3)} = 0 "
                  f"and (select created_by_user_id = '{fid(2, 12)}' and creator_veterinarian_clinic_assignment_id = '{fid(8, 12)}' "
                  f"from public.clinical_record_entries where id = '{authored_by_vet3}')",
                  "after the author's offboarding no other Veterinarian edits; authorship unchanged")

            first, second = race(observer, edit_call(VET, 1, entry, fid(20, 7), 6, 'Before my offboarding'),
                                 end_assignment_call(fid(8, 10)), 'edit vs own Assignment end')
            check(observer, f"{edited(first, 7)} and {outcome(second)} = 'ENDED' "
                  f"and (select amending_veterinarian_clinic_assignment_id = '{fid(8, 10)}' from public.clinical_amendments "
                  f"where idempotency_key = '{fid(20, 7)}')",
                  'edit vs own Assignment end: the edit commits first under the Assignment it used')
            after = single(edit_call(VET, 1, entry, fid(20, 8), 7, 'After my offboarding'))
            check(observer, f"'{after}' = 'ERR:42501:Clinical record unavailable' "
                  f"and not exists (select 1 from public.clinical_amendments where idempotency_key = '{fid(20, 8)}')",
                  'after the own Assignment end the former Veterinarian is refused')

            check(observer, f"{entries_fingerprint()} = '{original}' "
                  f"and (select count(*) = count(distinct (amending_user_id, idempotency_key)) from public.clinical_amendments "
                  f"where original_{ENTRY_FILTER}) and {versions(entry)} = 6 "
                  f"and (select array_agg(version_number order by version_number) = array[2, 3, 4, 5, 6, 7] "
                  f"from public.clinical_amendments where original_clinical_record_entry_id = '{entry}') "
                  f"and not exists (select 1 from public.clinical_amendments a join public.clinical_record_entries e "
                  f"on e.id = a.original_clinical_record_entry_id where a.original_{ENTRY_FILTER} "
                  f"and a.amending_user_id <> e.created_by_user_id)",
                  'coherent state: the original Entries never changed, versions are gapless, no edit intent is '
                  'duplicated, every version is by its author')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0352000-'])


if __name__ == '__main__':
    main()

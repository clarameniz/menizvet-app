"""LOCAL-only multi-session races for Professional Longitudinal / Cross-Clinic
Medical History (SPEC-MED-005 BR-39/BR-42/BR-45 with the SPEC-MED-010 BR-14
window and BR-22 projection, SPEC-ACC-002 BR-54, SPEC-ACC-003 BR-41).

Same discipline as run_clinical_amendment_concurrency.py, whose race primitives
this reuses: a synthetic fixture (prefix d0362000-) is committed to the
isolated local database, the real client read races a real writer in two psql
sessions (the first observed holding its locks, the second observed blocked on
a lock before the first commits), and every fixture row and every row the
operations created is always deleted afterwards, with restoration and zero
retained fixture rows verified. A deadlock would surface as ERR:40P01 and fail
the exact outcome checks. Every history result must be a complete coherent
page or exactly DENIED: never a version without its Entry or a partial
version history, never an Entry recorded after the page's snapshot.
Never point this at a shared database.
"""
import json
import sys
sys.dont_write_bytecode = True
from sql_fault_harness import HarnessFailure, LocalSql
from run_staff_invitation_concurrency import check, race


def fid(kind, n):
    return f'd0362000-0000-4000-8000-{kind * 100 + n:012d}'


ORG, CLINIC, ORG2, CLINIC2 = fid(3, 1), fid(4, 1), fid(3, 2), fid(4, 2)
PET, GUARDIANSHIP = fid(9, 1), fid(9, 2)
GUARDIAN, ADMIN, VET, VET2, VET3 = fid(1, 1), fid(1, 5), fid(1, 10), fid(1, 11), fid(1, 12)  # Auth subjects
HISTORICAL_ENTRY = fid(14, 1)

FIXTURE = f"""
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at)
select ('d0362000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid, 'history-race-' || n || '@example.test', now()
from unnest(array[1, 5, 10, 11, 12, 19]) n;
insert into public.users (id)
select ('d0362000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid from unnest(array[1, 5, 10, 11, 12, 19]) n;
insert into public.user_authentication_identities (id, user_id, provider_subject)
select ('d0362000-0000-4000-8000-' || lpad((1900 + n)::text, 12, '0'))::uuid,
    ('d0362000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
    ('d0362000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid
from unnest(array[1, 5, 10, 11, 12, 19]) n;
insert into public.user_profiles (user_id, display_name) values ('{fid(2, 10)}', 'Race Ana'), ('{fid(2, 19)}', 'Race Diego');
insert into public.veterinary_organizations (id, display_name) values ('{ORG}', 'History Race Org'), ('{ORG2}', 'History Race Org 2');
insert into public.clinics (id, organization_id, is_published, scheduling_timezone_name, standard_appointment_duration_minutes)
values ('{CLINIC}', '{ORG}', true, 'Europe/Madrid', 30), ('{CLINIC2}', '{ORG2}', true, 'Europe/Madrid', 30);
insert into public.organization_memberships (id, organization_id, user_id, effective_start)
select ('d0362000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid, case when n = 19 then '{ORG2}' else '{ORG}' end::uuid,
    ('d0362000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid, '2020-01-01Z'
from unnest(array[5, 10, 11, 12, 19]) n;
insert into public.organization_responsibility_grants (id, membership_id, responsibility, scope_type, effective_start, granted_by_user_id)
select ('d0362000-0000-4000-8000-' || lpad((600 + n)::text, 12, '0'))::uuid,
    ('d0362000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 5 then 'ADMINISTRATOR' else 'VETERINARIAN' end, 'ORGANIZATION', '2020-01-01Z', '{fid(2, 5)}'
from unnest(array[5, 10, 11, 12, 19]) n;
insert into public.veterinarian_professional_profiles (id, user_id)
select ('d0362000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0362000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid
from unnest(array[10, 11, 12, 19]) n;
insert into public.veterinarian_clinic_assignments (id, professional_profile_id, supporting_membership_id, clinic_id, effective_start)
select ('d0362000-0000-4000-8000-' || lpad((800 + n)::text, 12, '0'))::uuid,
    ('d0362000-0000-4000-8000-' || lpad((700 + n)::text, 12, '0'))::uuid,
    ('d0362000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
    case when n = 19 then '{CLINIC2}' else '{CLINIC}' end::uuid, '2020-01-01Z'
from unnest(array[10, 11, 12, 19]) n;
insert into public.pets (id, name, species, created_at) values ('{PET}', 'History Race Luna', 'Dog', '2020-01-01Z');
insert into public.guardianships (id, user_id, pet_id, effective_start) values ('{GUARDIANSHIP}', '{fid(2, 1)}', '{PET}', '2020-01-01Z');
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
select ('d0362000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{fid(2, 1)}',
    'History race visit ' || n, 'CONFIRMED', '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n)
from generate_series(1, 6) n;
insert into public.appointment_schedule_revisions (appointment_id, revision_sequence, revision_context, scheduled_start_at,
    scheduled_end_at, establishment_timezone_name, established_by_user_id, source_proposal_id, created_at)
select ('d0362000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, r,
    case r when 1 then 'REQUESTED' else 'CONFIRMED' end, '2026-06-01T10:00Z', '2026-06-01T10:30Z', 'Europe/Madrid',
    case r when 1 then '{fid(2, 1)}'::uuid else '{fid(2, 5)}'::uuid end, null,
    case r when 1 then '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n) else '2026-02-01T00:00:00Z' end
from generate_series(1, 6) n, unnest(array[1, 2]) r;
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
select ('d0362000-0000-4000-8000-' || lpad((1200 + n)::text, 12, '0'))::uuid, '{PET}', '{CLINIC}', '{ORG}', '{GUARDIANSHIP}',
    '2026-01-01T00:00:00Z'::timestamptz + make_interval(mins => n), 'APPOINTMENT_CARE',
    ('d0362000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'ACTIVE'
from generate_series(1, 6) n;
insert into public.appointment_lifecycle_events (appointment_id, from_state, to_state, actor_user_id, actor_context,
    reason, effective_at, recorded_at)
select ('d0362000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, 'REQUESTED', 'CONFIRMED', '{fid(2, 5)}',
    'CLINIC', null, '2026-02-01Z', '2026-02-01Z'
from generate_series(1, 6) n;
-- Veterinarian 10 is the assigned Veterinarian of Appointments 1 and 2.
insert into public.appointment_veterinarian_assignments (appointment_id, veterinarian_clinic_assignment_id,
    effective_start, assigned_by_user_id)
select ('d0362000-0000-4000-8000-' || lpad((1100 + n)::text, 12, '0'))::uuid, '{fid(8, 10)}', '2026-03-01Z', '{fid(2, 5)}'
from unnest(array[1, 2]) n;
-- One recorded Entry of another Organization, on its own COMPLETED Appointment.
insert into public.appointments (id, pet_id, clinic_id, requesting_user_id, reason_for_visit, lifecycle_state, created_at)
values ('{fid(11, 50)}', '{PET}', '{CLINIC2}', '{fid(2, 1)}', 'Historical visit', 'COMPLETED', '2024-12-01Z');
insert into public.care_authorizations (id, pet_id, clinic_id, organization_id, granting_guardianship_id, granted_at,
    purpose, appointment_id, lifecycle_state)
values ('{fid(12, 50)}', '{PET}', '{CLINIC2}', '{ORG2}', '{GUARDIANSHIP}', '2024-12-01Z', 'APPOINTMENT_CARE', '{fid(11, 50)}', 'ACTIVE');
insert into public.clinical_record_entries (id, appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id,
    created_at, clinical_content, category, clinical_event_at, creation_idempotency_key, creation_request_digest)
values ('{HISTORICAL_ENTRY}', '{fid(11, 50)}', '{fid(2, 19)}', '{fid(8, 19)}', '2025-01-01T09:30Z',
        'Historical note', 'CLINICAL_NOTE', null, gen_random_uuid(), sha256('historical'::bytea));
set local session_replication_role = origin;
select public.establish_organization_subscription('{ORG}', null, 'ACTIVE', '2020-01-01Z', null, null,
    'history-race', '{fid(20, 1)}', null);
commit;
"""

APPOINTMENT_FILTER = "appointment_id::text like 'd0362000-%'"
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
    (select id from public.organization_subscriptions where organization_id in ('{ORG}', '{ORG2}'));
delete from public.subscription_provider_references where subscription_id in
    (select id from public.organization_subscriptions where organization_id in ('{ORG}', '{ORG2}'));
delete from public.organization_subscriptions where organization_id in ('{ORG}', '{ORG2}');
delete from public.guardianships where pet_id = '{PET}';
delete from public.pets where id = '{PET}';
delete from public.veterinarian_clinic_assignments where clinic_id in ('{CLINIC}', '{CLINIC2}');
delete from public.veterinarian_professional_profiles where user_id::text like 'd0362000-%';
delete from public.organization_responsibility_grants where membership_id in
    (select id from public.organization_memberships where organization_id in ('{ORG}', '{ORG2}'));
delete from public.organization_memberships where organization_id in ('{ORG}', '{ORG2}');
delete from public.clinics where organization_id in ('{ORG}', '{ORG2}');
delete from public.veterinary_organizations where id in ('{ORG}', '{ORG2}');
delete from public.user_profiles where user_id::text like 'd0362000-%';
delete from public.user_authentication_identities where id::text like 'd0362000-%';
delete from public.users where id::text like 'd0362000-%';
delete from auth.users where id::text like 'd0362000-%';
commit;
"""


def appt(n):
    return fid(11, n)


def as_subject(subject, statement):
    return f"select set_config('request.jwt.claim.sub', '{subject}', false); {statement}"


def history_call(subject, n, limit=50, before_at=None, before_id=None):
    cursor = (f"'{before_at}'::timestamptz, '{before_id}'::uuid" if before_at else 'null, null')
    return as_subject(subject, f"select public.view_appointment_professional_medical_history('{CLINIC}', '{appt(n)}', "
                               f"{limit}, {cursor})::text")


def edit_call(subject, n, entry, key, expected, content):
    return as_subject(subject, f"select public.edit_appointment_clinical_entry('{CLINIC}', '{appt(n)}', '{entry}', "
                               f"'{key}', {expected}, 'TREATMENT', '{content}', null)::text")


def record_call(subject, n, key, content):
    return as_subject(subject, f"select public.create_appointment_clinical_entry('{CLINIC}', '{appt(n)}', '{key}', "
                               f"'TREATMENT', '{content}', null)::text")


def revoke_call(n):
    return as_subject(GUARDIAN, f"select public.revoke_my_appointment_care_authorization('{appt(n)}')::text")


def end_assignment_call(assignment):
    return as_subject(ADMIN, f"select public.end_staff_veterinarian_clinic_assignment('{ORG}', '{CLINIC}', '{assignment}')::text")


def page(result):
    """A permitted page, or None for exactly DENIED; anything else fails the race."""
    if not result.startswith('OK:'):
        raise HarnessFailure('History read failed instead of answering: ' + result)
    payload = json.loads(result[3:])
    if payload == {'status': 'DENIED'}:
        return None
    if payload.get('status') != 'PERMITTED' or set(payload) != {'status', 'entries', 'cursor'}:
        raise HarnessFailure('History read returned an incoherent payload: ' + result)
    return payload


def coherent(observer, payload, label):
    """Every returned Entry is recorded, its current version comes with every
    earlier one, and each legacy correction belongs to it."""
    for entry in payload['entries']:
        version = entry['version']
        if [earlier['version'] for earlier in entry['previous_versions']] != list(range(1, version)):
            raise HarnessFailure(f"{label}: Entry {entry['entry_id']} has a partial version history")
        amendments = [amendment['amendment_id'] for amendment in entry['amendments']]
        listed = "array[" + ",".join(f"'{a}'::uuid" for a in amendments) + "]::uuid[]"
        check(observer, f"exists (select 1 from public.clinical_record_entries where id = '{entry['entry_id']}') "
              f"and (select count(*) = {version - 1} from public.clinical_amendments "
              f"where original_clinical_record_entry_id = '{entry['entry_id']}' and change_kind = 'EDIT' "
              f"and version_number <= {version}) "
              f"and (select count(*) = {len(amendments)} from public.clinical_amendments where id = any({listed}) "
              f"and original_clinical_record_entry_id = '{entry['entry_id']}' and change_kind = 'ADDENDUM') "
              f"and {len(amendments)} = {entry['amendment_count']}",
              f"{label}: Entry {entry['entry_id']} is recorded with exactly its own versions")


def ids(payload):
    return [entry['entry_id'] for entry in payload['entries']]


def committed(observer, subject, statement, label):
    return observer.require_success(
        f"begin;\nselect set_config('request.jwt.claim.sub', '{subject}', true);\n{statement};\ncommit;", label
    ).splitlines()[-1].strip()


def record(observer, subject, n, key, content):
    return committed(observer, subject, f"select (public.create_appointment_clinical_entry('{CLINIC}', '{appt(n)}', "
                                        f"'{key}', 'TREATMENT', '{content}', null) ->> 'entry_id')",
                     f'Record Entry {n}')


def read_now(observer, subject, n, limit=50):
    """One committed, unraced history read; returns 'OK:<json>'."""
    statement = history_call(subject, n, limit).split('; ')[1]
    return 'OK:' + observer.require_success(
        f"begin;\nselect set_config('request.jwt.claim.sub', '{subject}', true);\n{statement};\ncommit;",
        f'History read {n}').splitlines()[-1].strip()


def audits(outcome):
    return (f"(select count(*) from public.medical_access_audit_events where pet_id = '{PET}' "
            f"and operation = 'VIEW_PET_MEDICAL_HISTORY' and outcome = '{outcome}')")


def main():
    observer = LocalSql()
    with observer.restored():
        try:
            observer.require_success(FIXTURE, 'Commit race fixture')
            # Appointment 1: one recorded Entry (edit races); Appointment 2
            # receives Entries during the record races.
            finalized = record(observer, VET, 1, fid(16, 1), 'Dose 50 mg')

            # 1. History read vs Guardian revoke, both orders.
            first, second = race(observer, history_call(VET, 3), revoke_call(3), 'history read vs Guardian revoke')
            payload = page(first)
            if payload is None or ids(payload) != [finalized, HISTORICAL_ENTRY] or not second.startswith('OK:'):
                raise HarnessFailure('history read vs Guardian revoke: expected a full page, then the revocation')
            coherent(observer, payload, 'read before revoke')
            check(observer, f"(select lifecycle_state = 'REVOKED' from public.care_authorizations where appointment_id = '{appt(3)}')",
                  'history read vs Guardian revoke: the revocation waits for the read and then commits')
            if page(read_now(observer, VET, 3)) is not None:
                raise HarnessFailure('history read vs Guardian revoke: a later read must be denied')
            print('PASS history read vs Guardian revoke: a later read is denied', flush=True)

            first, second = race(observer, revoke_call(4), history_call(VET, 4), 'Guardian revoke vs history read')
            if not first.startswith('OK:') or page(second) is not None:
                raise HarnessFailure('Guardian revoke vs history read: the read must wait and then be exactly DENIED')
            print('PASS Guardian revoke vs history read: the read waits, sees the revocation and is exactly DENIED', flush=True)

            # 2. History read vs current Veterinarian offboarding, both orders.
            first, second = race(observer, history_call(VET2, 5), end_assignment_call(fid(8, 11)),
                                 'history read vs own Assignment end')
            payload = page(first)
            if payload is None or ids(payload) != [finalized, HISTORICAL_ENTRY] or json.loads(second[3:]).get('outcome') != 'ENDED':
                raise HarnessFailure('history read vs own Assignment end: expected a full page, then the Assignment end')
            coherent(observer, payload, 'read before offboarding')
            print('PASS history read vs own Assignment end: the read completes, then the Assignment ends', flush=True)

            first, second = race(observer, end_assignment_call(fid(8, 12)), history_call(VET3, 5),
                                 'own Assignment end vs history read')
            if json.loads(first[3:]).get('outcome') != 'ENDED' or page(second) is not None:
                raise HarnessFailure('own Assignment end vs history read: the read must wait and be exactly DENIED')
            print('PASS own Assignment end vs history read: the former Veterinarian waits and is exactly DENIED', flush=True)

            # 3. History read vs edit, both orders.
            first, second = race(observer, history_call(VET, 1), edit_call(VET, 1, finalized, fid(20, 1), 1, 'Dose 5 mg'),
                                 'history read vs edit')
            payload = page(first)
            if payload is None or payload['entries'][0]['version'] != 1 \
                    or payload['entries'][0]['clinical_content'] != 'Dose 50 mg' \
                    or json.loads(second[3:]).get('outcome') != 'EDITED':
                raise HarnessFailure('history read vs edit: the read shows the Entry as it was, then the edit')
            coherent(observer, payload, 'read before edit')
            print('PASS history read vs edit: the edit waits; the page was coherent without it', flush=True)

            first, second = race(observer, edit_call(VET, 1, finalized, fid(20, 2), 2, 'With food'), history_call(VET, 1),
                                 'edit vs history read')
            payload = page(second)
            if json.loads(first[3:]).get('outcome') != 'EDITED' or payload is None \
                    or payload['entries'][0]['clinical_content'] != 'With food' \
                    or [v['clinical_content'] for v in payload['entries'][0]['previous_versions']] != ['Dose 50 mg', 'Dose 5 mg']:
                raise HarnessFailure('edit vs history read: the read must show the current version above both earlier ones')
            coherent(observer, payload, 'read after edit')
            print('PASS edit vs history read: the read waits and shows the current version with both earlier ones', flush=True)

            # 4. History read vs "Guardar y publicar registro", both orders.
            first, second = race(observer, history_call(VET, 2), record_call(VET, 2, fid(16, 2), 'New note'),
                                 'history read vs Record')
            payload = page(first)
            if payload is None or json.loads(second[3:]).get('outcome') != 'CREATED' \
                    or json.loads(second[3:])['entry_id'] in ids(payload) or ids(payload) != [finalized, HISTORICAL_ENTRY]:
                raise HarnessFailure('history read vs Record: the page must not show the Entry recorded after it')
            coherent(observer, payload, 'read before Record')
            recorded = json.loads(second[3:])['entry_id']
            print('PASS history read vs Record: the save waits; the page is coherent without the new Entry', flush=True)

            first, second = race(observer, record_call(VET, 2, fid(16, 3), 'Second note'), history_call(VET, 2),
                                 'Record vs history read')
            payload = page(second)
            if json.loads(first[3:]).get('outcome') != 'CREATED' or payload is None \
                    or json.loads(first[3:])['entry_id'] not in ids(payload) or recorded not in ids(payload):
                raise HarnessFailure('Record vs history read: the read must include the newly recorded Entry')
            coherent(observer, payload, 'read after Record')
            print('PASS Record vs history read: the read waits and includes the recorded Entry immediately', flush=True)

            # 5. Load more vs an edit of an Entry already on screen.
            full = page(read_now(observer, VET, 6))
            first_page = page(read_now(observer, VET, 6, 1))
            cursor = first_page['cursor']
            first, second = race(observer,
                                 history_call(VET, 6, 50, cursor['before_history_order_at'], cursor['before_entry_id']),
                                 edit_call(VET, 1, finalized, fid(20, 3), 3, 'Twice daily'), 'load more vs edit')
            rest = page(first)
            if rest is None or json.loads(second[3:]).get('outcome') != 'EDITED' \
                    or ids(first_page) + ids(rest) != ids(full) or len(set(ids(first_page) + ids(rest))) != len(ids(full)):
                raise HarnessFailure('load more vs edit: pages must neither duplicate nor skip')
            coherent(observer, rest, 'load more before edit')
            print('PASS load more vs edit: no duplicate, no skip, coherent versions', flush=True)

            check(observer, f"{audits('PERMITTED')} >= 7 and {audits('DENIED')} >= 3 "
                  f"and (select count(*) = 0 from public.medical_access_audit_events where pet_id = '{PET}' "
                  f"and clinical_record_entry_id is not null)",
                  'audit: one event per read, never one per Entry')
        finally:
            observer.require_success(CLEANUP, 'Delete race fixture')
        observer.verify_zero_fixtures(['d0362000-'])


if __name__ == '__main__':
    main()

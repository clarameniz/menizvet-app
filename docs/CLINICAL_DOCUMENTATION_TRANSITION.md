# Clinical Documentation Transition (ADR-011)

**Status:** APPROVED (2026-10-23) — transition plan for
[ADR-011](decisions/ADR-011-appointment-owned-clinical-documentation.md) and
[SPEC-MED-010](../specs/medical-records/SPEC-MED-010-document-appointment-clinical-record.md).
Execution state is recorded in §9.

It defines the read-only inventory, the exact disposable-data cleanup for LOCAL
and DEVELOPMENT, the final schema, the migration stages, the mobile plan, and
the regression verification. It contains no migration.

## 1. Environment policy

| Environment | Data | Treatment |
| --- | --- | --- |
| LOCAL | Rebuilt from migrations; no seed file exists | `npx supabase db reset` after the new migrations; no cleanup needed |
| DEVELOPMENT (linked project) | Disposable test data of a single developer | Inventory → operator cleanup (§3) → migrations (§5) |
| Production | Not inspected | **Not touched.** No inventory, cleanup, or migration without explicit authorization. The migrations are fail-closed (§5) so that applying them to an environment with clinical documentation aborts instead of discarding it. |

The cleanup is an operator procedure, not a migration: a forward-only
migration would also run in Production.

## 2. Read-only inventory

Run in DEVELOPMENT (and LOCAL for parity) inside a read-only transaction.
Record every result before any cleanup.

```sql
begin transaction read only;

-- I-0 Retained-data baseline (must be identical after cleanup)
select 'users' as t, count(*) from public.users
union all select 'pets', count(*) from public.pets
union all select 'guardianships', count(*) from public.guardianships
union all select 'veterinary_organizations', count(*) from public.veterinary_organizations
union all select 'clinics', count(*) from public.clinics
union all select 'appointments', count(*) from public.appointments
union all select 'appointment_lifecycle_events', count(*) from public.appointment_lifecycle_events
union all select 'appointment_schedule_revisions', count(*) from public.appointment_schedule_revisions
union all select 'appointment_reschedule_proposals', count(*) from public.appointment_reschedule_proposals
union all select 'appointment_veterinarian_assignments', count(*) from public.appointment_veterinarian_assignments
union all select 'care_authorizations', count(*) from public.care_authorizations
union all select 'transactional_communications', count(*) from public.transactional_communications;

-- I-1 Encounters by Appointment state, Encounter state, Care Authorization state and purpose
select a.lifecycle_state as appointment_state, e.lifecycle_state as encounter_state,
       ca.lifecycle_state as authorization_state, ca.purpose, count(*)
from public.clinical_encounters e
join public.care_authorizations ca on ca.id = e.care_authorization_id
left join public.appointments a on a.id = e.appointment_id
group by 1, 2, 3, 4 order by 1, 2, 3, 4;

-- I-2 Encounters without Appointment (Clinical Intake)
select count(*) from public.clinical_encounters where appointment_id is null;

-- I-3 Encounters without Entries, by Appointment state
select a.lifecycle_state, count(*)
from public.clinical_encounters e
left join public.appointments a on a.id = e.appointment_id
where not exists (select 1 from public.clinical_record_entries r where r.clinical_encounter_id = e.id)
group by 1;

-- I-4 Provenance agreement Encounter vs Appointment and Clinic (expected 0)
select count(*)
from public.clinical_encounters e
join public.appointments a on a.id = e.appointment_id
join public.clinics c on c.id = a.clinic_id
where e.pet_id <> a.pet_id or e.clinic_id <> a.clinic_id or e.organization_id <> c.organization_id;

-- I-5 Entries by lifecycle and Appointment state
select r.lifecycle_state, a.lifecycle_state as appointment_state, count(*)
from public.clinical_record_entries r
join public.clinical_encounters e on e.id = r.clinical_encounter_id
left join public.appointments a on a.id = e.appointment_id
group by 1, 2 order by 1, 2;

-- I-6 Documentation dependents
select 'amendments' as t, count(*) from public.clinical_amendments
union all select 'contributors', count(*) from public.clinical_record_entry_contributors
union all select 'attachments', count(*) from public.clinical_attachments;

select validation_state, object_state, (removed_at is not null) as removed, count(*)
from public.clinical_attachments group by 1, 2, 3 order by 1, 2, 3;

-- I-7 Storage objects of the clinical bucket vs Attachment rows
select count(*) as objects,
       count(*) filter (where not exists (
           select 1 from public.clinical_attachments x
           where 'v1/' || x.storage_object_id::text = o.name)) as orphan_objects
from storage.objects o where o.bucket_id = 'clinical-attachments';

-- I-8 Medical Access Audit Events: to delete vs to keep
select (clinical_encounter_id is not null or clinical_record_entry_id is not null
        or clinical_amendment_id is not null
        or clinical_attachment_id is not null
        or operation in ('ACCESS_FOR_CLINICAL_CARE', 'ACCESS_FOR_POST_CARE_DOCUMENTATION',
                         'VIEW_CLINICAL_RECORD_ENTRY', 'VIEW_CLINICAL_ATTACHMENT')
        or protected_resource_scope in ('ENCOUNTER_MEDICAL_INFORMATION', 'CLINICAL_RECORD_ENTRY',
                                        'CLINICAL_AMENDMENT', 'CLINICAL_ATTACHMENT')) as to_delete,
       operation, protected_resource_scope, outcome, count(*)
from public.medical_access_audit_events
group by 1, 2, 3, 4 order by 1, 2, 3, 4;

-- I-9 Legacy Encounter references on Lifecycle Events
select count(*) from public.appointment_lifecycle_events where clinical_encounter_id is not null;

-- I-10 Care Authorizations of COMPLETED Appointments, and REVOKED with an ACTIVE Encounter
select ca.lifecycle_state, ca.ended_reason, count(*)
from public.care_authorizations ca
join public.appointments a on a.id = ca.appointment_id
where a.lifecycle_state = 'COMPLETED'
group by 1, 2;

select count(*)
from public.clinical_encounters e
join public.care_authorizations ca on ca.id = e.care_authorization_id
where ca.lifecycle_state = 'REVOKED' and e.lifecycle_state = 'ACTIVE';

-- I-11 Non-attendance Appointments with Encounters (expected 0)
select a.lifecycle_state, count(*)
from public.clinical_encounters e
join public.appointments a on a.id = e.appointment_id
where a.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED', 'REQUESTED')
group by 1;

-- I-12 Appointments with more than one confirmation Event (expected 0)
select count(*) from (
    select appointment_id from public.appointment_lifecycle_events
    where from_state = 'REQUESTED' and to_state = 'CONFIRMED'
    group by appointment_id having count(*) > 1) x;

-- I-13 Reschedule Proposals voided by an Encounter
select count(*) from public.appointment_reschedule_proposals
where void_reason = 'CLINICAL_ENCOUNTER_STARTED';

-- I-14 Clinical Intake Care Authorizations
select lifecycle_state, count(*) from public.care_authorizations
where purpose = 'CLINICAL_INTAKE' group by 1;

-- I-15 Current Veterinarian Assignments by Appointment state and staleness
select a.lifecycle_state,
       public.veterinarian_clinic_assignment_is_current(ava.veterinarian_clinic_assignment_id) as clinic_assignment_current,
       count(*)
from public.appointment_veterinarian_assignments ava
join public.appointments a on a.id = ava.appointment_id
where ava.effective_end is null
group by 1, 2 order by 1, 2;

-- I-16 Ended periods without a successor starting at the same instant (expected 0)
select count(*)
from public.appointment_veterinarian_assignments ended
where ended.effective_end is not null
  and not exists (
      select 1 from public.appointment_veterinarian_assignments next_period
      where next_period.appointment_id = ended.appointment_id
        and next_period.effective_start = ended.effective_end);

-- I-17 Assignments on non-documentable Appointments
select a.lifecycle_state, count(*)
from public.appointment_veterinarian_assignments ava
join public.appointments a on a.id = ava.appointment_id
where ava.effective_end is null
  and a.lifecycle_state in ('CANCELLED', 'NO_SHOW', 'EXPIRED')
group by 1;

rollback;
```

Expected-zero results (I-4, I-11, I-12, I-16) that are not zero must be
reported before continuing. I-15 and I-17 describe existing Appointment data,
which is retained unchanged: a current period on a terminal Appointment stays
historical and simply authorizes nothing.

## 3. DEVELOPMENT cleanup scope

### 3.1 Deleted

Only clinical documentation and the audit evidence that references it, exactly
the inventoried rows (fingerprints in the script):

| Data | Rows in DEVELOPMENT |
| --- | --- |
| `medical_access_audit_events` with any clinical reference (`clinical_encounter_id`, `clinical_record_entry_id`, `clinical_amendment_id`, `clinical_attachment_id`) or a clinical operation or scope | 100 |
| `clinical_attachments` | 1 |
| `clinical_amendments` | 3 |
| `clinical_record_entry_contributors` | 0 |
| `clinical_record_entries` | 9 |
| `clinical_encounters` | 8 |
| Storage object `clinical-attachments/v1/9bc0625f-ceaf-4c61-8562-0eda1134552f` | 1, through the Storage API |

The real foreign keys into these tables (read from the DEVELOPMENT catalog) are
only: audit events → Encounter, Entry, Amendment, Attachment; Entries →
Encounter; Amendments, Attachments, contributors → Entry; Lifecycle Events →
Encounter (0 rows use it). Deleting in that order leaves no reference that
could block M2. The Encounters are deleted here, so M2 runs on empty clinical
tables.

### 3.2 Retained

Users and authentication identities, Pets, Guardianships and invitations,
Organizations, Memberships, Responsibility Grants, Clinics and their
configuration, Veterinarian profiles and Clinic Assignments, Subscriptions,
Appointments (25), Schedule Revisions (59), Lifecycle Events (35), Reschedule
Proposals (21), Appointment Veterinarian Assignments (0), Care Authorizations
(26, states unchanged, including the Clinical Intake one), Communications (93)
and their delivery history, and the 36 non-clinical audit events.

No Appointment is deleted, so no Communication evidence is affected.

### 3.3 Procedure

Scripts (never migrations, never auto-run):
`supabase/provisioning/punto8_dev_clinical_cleanup_preflight_readonly.sql` and
`supabase/provisioning/punto8_dev_clinical_cleanup.sql`.

1. Confirm `supabase/.temp/project-ref` and `npx supabase projects list`
   show exactly `eqvlydfflfvltprkwcxx` linked.
2. Run the preflight (`npx supabase db query --linked -f …preflight_readonly.sql`)
   and compare it with the fingerprints hard-coded in the cleanup script:
   `is_development = true`, last migration `20261112090000`, the five row-set
   fingerprints, 0 contributors, 0 Lifecycle Events with an Encounter, and the
   retained counts.
3. Run the cleanup (`npx supabase db query --linked -f …cleanup.sql`). It is one
   DO statement: it re-checks the target identity (Vault dispatch URL of
   `eqvlydfflfvltprkwcxx`), the last migration, every fingerprint, and the
   retained baseline, and refuses on any difference. It then disables only
   `medical_access_audit_events_preserve_history`,
   `clinical_attachments_prevent_delete`, `clinical_amendments_integrity`,
   `clinical_record_entries_integrity`, and
   `clinical_encounters_preserve_history` (ALTER TABLE holds those tables under
   ACCESS EXCLUSIVE), deletes in foreign-key order with an exact count check
   for each table, re-enables the same triggers, verifies every clinical
   trigger is enabled, and verifies empty clinical tables and an unchanged
   retained baseline including Care Authorization states. Any failure rolls
   back the whole statement. `session_replication_role` is never used.
4. Only after step 3 commits, remove the Storage object:
   `npx supabase storage rm --linked --experimental ss:///clinical-attachments/v1/9bc0625f-ceaf-4c61-8562-0eda1134552f`.
   Storage is outside the SQL transaction; if this step fails the object is an
   orphan (no row references it) and the step is repeated.
5. Re-run the preflight: every clinical row set is `n = 0`, `storage_objects`
   is `[]`, audit events total 36, retained counts unchanged.

Rehearsed in LOCAL on 2026-10-23 inside a rolled-back transaction with a
synthetic set of the same shape (8/9/3/1/100 plus 36 kept): the production text
of the script (only the identity guard and the fingerprints substituted)
removed exactly the scope, re-enabled the guards (a later audit deletion was
again refused), and refused with no write when one fingerprint differed. On
LOCAL itself the unmodified script refuses: "this database is not DEVELOPMENT".

## 4. Final schema

Defined in [RELATIONAL_MODEL.md §14](RELATIONAL_MODEL.md#14-target-revision-appointment-owned-clinical-documentation-adr-011).

- `clinical_record_entries`: `id`, `appointment_id` (not null, FK, immutable),
  `created_by_user_id`, `creator_veterinarian_clinic_assignment_id`,
  `created_at` (recording time), `category` (not null), `clinical_content`
  (not null), `other_category_context`, `clinical_event_at`,
  `creation_idempotency_key` (not null), `creation_request_digest` (not null);
  unique (`created_by_user_id`, `creation_idempotency_key`); index
  (`appointment_id`, `created_at`, `id`). Removed: `clinical_encounter_id`,
  `lifecycle_state`, `draft_revision`, `last_modified_at`, `finalized_at`,
  `finalized_by_user_id`, `finalizer_veterinarian_clinic_assignment_id`.
- `clinical_amendments`, `clinical_attachments`: unchanged columns; integrity
  triggers derive Clinic and Organization through the Entry's Appointment.
- `medical_access_audit_events`: `clinical_encounter_id` dropped; controlled
  operation and scope sets updated (`VIEW_APPOINTMENT_CLINICAL_RECORD`,
  `APPOINTMENT_CLINICAL_RECORD`; `ACCESS_FOR_POST_CARE_DOCUMENTATION` and
  `ENCOUNTER_MEDICAL_INFORMATION` removed).
- `appointment_lifecycle_events`: `clinical_encounter_id`, its shape check,
  and the no-new-reference trigger dropped.
- `care_authorizations`: ending context `APPOINTMENT_COMPLETED` added.
- `appointment_reschedule_proposals`: void reason
  `CLINICAL_DOCUMENTATION_STARTED` replaces `CLINICAL_ENCOUNTER_STARTED`.
- `appointment_veterinarian_assignments`: **no column change**. Its
  establishment rule additionally accepts `COMPLETED`; a structural rule makes
  every ended period have a same-instant successor; the Entry insertion rule
  references its current period.
- Dropped: `clinical_encounters`, `clinical_record_entry_contributors`, and
  every function of `SPEC-MED-010` BR-25 together with the Encounter
  establishment, immutability, and coherence triggers and helpers.

## 5. Migration stages

All migrations are new, forward-only files; no applied migration is edited.

### 5.1 Why ending the Care Authorization cannot come first

In the deployed model the Care Authorization is still part of the
documentation basis: the Appointment clinical record, client Amendments, Draft
work, and Attachment work on a `CONCLUDED` Encounter require an `ACTIVE`
authorization, and establishing an Encounter for a `COMPLETED` Appointment
requires one too. Ending the authorization at completion before the
independent documentation access of `SPEC-MED-010` BR-11 exists would
immediately make the records of every completed visit unreadable and
uncorrectable through the client, and would block documenting completed
visits. In DEVELOPMENT today that would hit 5 `CONCLUDED` Encounters and 1
`ACTIVE` one, all on `COMPLETED` Appointments with an `ACTIVE` authorization.
The earlier order (authorization first) is therefore withdrawn.

### 5.2 Definitive order

Every stage is a new forward-only migration, and every intermediate state is
coherent: each operation is governed by exactly one access rule set.

| Stage | Content | Guard | Behavior after the stage |
| --- | --- | --- | --- |
| **M1 — Appointment Veterinarian assignment contract** | `SPEC-APT-007` §13: establishment accepts `COMPLETED`; deferred same-instant successor rule; eligibility helper; `assign_appointment_veterinarian`, `assign_me_to_appointment`, `get_appointment_veterinarian_candidates`; `get_appointment_veterinarian_assignment` (BR-37; `get_clinic_appointment` unchanged); `authenticated` `EXECUTE` withdrawn from `assign_veterinarian_to_appointment` and `reassign_veterinarian` (no client calls them). No column change, no Encounter or Care Authorization dependency, no data change. | I-16 = 0 | Assignment can be recorded and read; it is metadata only. Clinical documentation still follows the deployed Encounter model unchanged; completion, revocation, and history unchanged. |
| *DEV cleanup* | §3, operator procedure, after M1 and before M2. LOCAL needs none: `db reset` starts empty. | fingerprints | No clinical documentation, Encounter, or clinical audit row exists. |
| **M2 — Appointment-owned documentation (the cut)** | Abort unless every clinical table (Encounters included) is empty and no I-8 `to_delete` audit row exists. Then, in one transaction: drop Encounter-dependent functions, triggers, and checks; drop `appointment_lifecycle_events.clinical_encounter_id` and `medical_access_audit_events.clinical_encounter_id`; drop contributors; reshape `clinical_record_entries`; drop `clinical_encounters`; rename the proposal void reason; new structural triggers (documentable Appointment, assignee rule, author-only Amendments and Attachments); the two access predicates — documentation access (BR-11) and prior-history access (BR-14, `COMPLETED` excluded, no Encounter condition); `CLINICAL_CARE` Entitlement on every new Entry and Attachment; blocks and `has_clinical_record`; `create_appointment_clinical_entry`, the new `view_appointment_clinical_record`, the Amendment basis; SQL Attachment functions re-keyed through the Entry's Appointment while `authorize_clinical_attachment_download` keeps its signature so the deployed Guardian download route keeps working; audit controlled values; retired operations dropped. | clinical rows, Encounters, and clinical audit rows absent | Documentation is independent of the Care Authorization; history excludes `COMPLETED` Appointments even though their authorization is still `ACTIVE`, so that state grants nothing. Revocation stops history only. The old mobile build no longer works (reinstall the new build, §6). Professional Attachment routes are unavailable until M4 (no client uses them). |
| **M3 — Completion ends the Care Authorization** | `APPOINTMENT_COMPLETED` ending context and coherence; `complete_appointment` locks and ends the authorization at the completion time; existing `ACTIVE` authorizations of `COMPLETED` Appointments are ended at their completion time. | none | Authorization state matches its meaning: a Guardian revocation after completion returns `ALREADY_INACTIVE`; nothing a professional can do changes. |
| **M4 — Retire the professional Attachment routes** | The professional routes of the `clinical-attachments` Edge Function (`initiate`, `complete`, `remove`, `professional-download`) and their operations are retired, not re-keyed (`SPEC-MED-010` BR-19 ships no professional client workflow); the Guardian download keeps its contract through the Guardian-only `authorize_guardian_clinical_attachment_download`; Edge Function deployed with it (§13). | M2 contract present | No professional client reaches an Attachment; the Guardian download and the `maintenance` pass are the only routes. |
| **M5 — Editable Entries with preserved versions** | `SPEC-MED-010` BR-5, BR-18, BR-20, BR-22, BR-23b, BR-25: Clinical Amendments become the version log (existing rows kind `ADDENDUM`, unchanged; new rows kind `EDIT` carrying the complete next version, author-only, gapless, append-only); new Entries carry no clinical event time (structural); every read presents the current version with `version`, `edited_at` and every earlier version; `create_appointment_clinical_entry` without time arguments; `edit_appointment_clinical_entry` (idempotent, `STALE_VERSION`, no Entitlement, independent of the Care Authorization); `create_appointment_clinical_amendment` and `create_clinical_amendment` dropped (§15). | M4 contract present; every existing Amendment by its Entry's author | The author edits; nothing is overwritten; the old mobile build's record and rectification calls fail (install the M5 bundle). |

M2 is one migration because function bodies are not dependency-tracked:
dropping the Encounter table while any function still names it would leave
broken operations. M3 may be applied in the same deployment as M2 or later; it
must not precede M2. M5 follows M4 and is deployed together with the mobile
bundle that edits instead of rectifying (§15).

## 6. Mobile transition

The only installed build is the developer's Android development build. No
functional compatibility with older builds is required, and no build is
expected to keep showing errors:

1. Implement the assignment row and actions (`SPEC-APT-007` §13) and the new
   Appointment clinical record screen (`SPEC-MED-010` Part F) against M1–M3 in
   LOCAL. The assignment UI can ship after M1, since the deployed client keeps
   working with M1.
2. Before applying M2 to DEVELOPMENT, uninstall or stop using the old build.
3. Apply M2–M3 to DEVELOPMENT, then install the new development build.
4. Remove the old screens (`clinical.tsx` start/conclude panels,
   `completed-care-start-panel.tsx`, Draft and Finalize flows) and their data
   and helper modules in the same mobile change.

No device stores Encounter or Entry identifiers persistently, so no device
migration is needed.

## 7. Regression verification

### Database (`supabase/tests`)

- Replace `minimal_clinical_record_spec_med_001_009.sql` and
  `clinical_encounter_after_completion_spec_med_001.sql` with a
  `SPEC-MED-010` suite covering Verification Notes 1–21.
- Update `clinical_amendments_spec_med_004.sql`,
  `clinical_amendment_entitlement_continuity_spec_sub_004.sql`,
  `professional_medical_history_spec_med_005.sql`,
  `guardian_appointment_medical_access_revocation_spec_acc_002.sql`,
  `guardian_medical_history_provenance_names.sql`,
  `clinical_attachments_slice13_corrections.sql`,
  `appointment_completion_spec_apt_009.sql`,
  `appointment_cancellation_spec_apt_003.sql`,
  `appointment_no_show_spec_apt_010.sql`,
  `confirmed_appointment_reschedule_spec_apt_005_006_016_017.sql`, and the
  clinic schedule read suites for `has_clinical_record`.
- New suite for `SPEC-APT-007` §14 (Verification Notes 21–33); update
  `veterinarian_workforce_assignment_spec_vet_004_005_006.sql` and the
  Appointment suites that use the withdrawn assignment operations.
- Concurrency and fault runners: replace `run_clinical_record_*` with
  first-Entry vs cancellation / `NO_SHOW`, save vs reassignment, save vs end
  of the author's Clinic Assignment, two managed assignments with one token,
  self-assignment vs managed assignment, replay after lost response; keep `run_clinical_amendment_*`,
  `run_care_authorization_revocation_*` (revocation vs history reads and vs
  completion), and `run_professional_history_*` with the new window.
- Structural checks: no Entry for a non-documentable Appointment through a
  direct insert; Entry, Amendment, and `AVAILABLE` Attachment immutability;
  no retired function executable by `authenticated`; every remaining function
  body compiles against the final schema.

### Fault runners — validity before M2 is approved

1. **Restore a green baseline now (pre-M2, test-only change).** In
   `run_clinical_record_faults.py`, source `get_clinic_appointment_schedule`
   from its latest definition (`20261107090000_appointment_requester_contact.sql`)
   instead of `20261103090000`, adapting the `SCHEDULE_FLAG` anchor to that
   body; re-run the runner until every mutant is caught on the current schema.
   This proves the clinical fault baseline is valid before the cut.
2. **Guard against stale mutants.** Add to `sql_fault_harness.py` a check that
   the definition a runner extracts from a migration file equals the deployed
   `pg_get_functiondef` of that function in LOCAL (modulo whitespace), and fail
   with "stale fault source" otherwise. Run every `run_*_faults.py` once with
   the check to find other stale sources.
3. **With M2.** Retire `run_clinical_record_faults.py` and
   `minimal_clinical_record_spec_med_001_009.sql` together with the operations
   they target, and add `run_appointment_clinical_record_faults.py` sourcing the
   M2 migration, with mutants for: documentable-state check removed, assignee
   rule removed or reading a stale assignment, `CLINICAL_CARE` gate skipped for
   a later Entry or an Attachment, Amendment by a non-author, Entry updatable
   or deletable, Appointment reference mutable, history projection filtered by
   Care Authorization state, history opened by documentation access, audit
   written per Entry, and the non-attendance blocks removed. Update
   `run_clinical_amendment_faults.py` and `run_professional_history_faults.py`
   to the M2 sources in the same change.
4. M2 is proposed for approval only when every SQL suite, every race runner,
   and every fault runner passes in LOCAL with no stale source reported.

### Mobile (`apps/mobile`)

- Data-layer tests for `create_appointment_clinical_entry` and the new read
  payload; removal of Encounter, Draft, and Finalize parsing.
- Route tests: opening the detail or the record writes nothing; the
  Veterinarian row for unassigned, assigned, own, and stale assignments;
  **Assign to me** and **Assign / Change** visibility; `STALE_ASSIGNMENT`
  re-read; **Add record** only for the assignee and **Add amendment** only on
  own Entries; one call per save under repeated taps; retry only with the same key; unsaved text kept on
  `APPOINTMENT_STATE_INVALID` or denial; No-show and cancellation hidden once
  Entries exist; history action visibility.
- Guardian revocation copy (`SPEC-ACC-002` §16 replacement) and history
  ordering without `encounter_started_at`.

## 8. Recorded pending findings

- **Guardian assignment read exposes internal identifiers.** The Guardian
  Appointment detail calls `get_appointment_veterinarian_assignment_history`
  only to know whether a Veterinarian is assigned, but the read returns
  Veterinarian Professional Profile and assigning User identifiers to
  Guardians. It must be replaced by a minimal Guardian-safe indicator in the
  Guardian Appointment read (`SPEC-APT-011`). Not part of M1–M4; tracked here
  and in the `SPEC-APT-011` notice.
- **`CLINICAL_DOCUMENTATION` Entitlement identifier.** `SPEC-SUB-003` defines a
  commercial Entitlement with the same name as the professional capability.
  Clinical documentation evaluates only the capability and the
  `CLINICAL_CARE` Entitlement (`SPEC-MED-010` BR-13); the unused Entitlement
  identifier should be reviewed separately.

- **Stale mutant in `run_clinical_record_faults.py`.** Its "Schedule flag removed" mutant
  rebuilds `get_clinic_appointment_schedule` from `20261103090000`, whose return
  type `20261107090000` later changed, so the runner fails with `42P13`
  independently of this transition (pre-existing since commit `9e9f076`). The
  runner is rewritten with M2 anyway, because it targets the retired Encounter
  operations. **Repaired 2026-10-23 (test harness only):** the mutant is now
  built from the deployed definition (`pg_get_functiondef`), like the
  `complete_appointment` and `clinical_history_page` mutants; the runner
  passes with 42/42 mutation assertions observed and no mutant removed.

## 9. Execution state

| Step | LOCAL | DEVELOPMENT (`eqvlydfflfvltprkwcxx`, "MenizVet Dev") | Production (`okapsgpltcutinefjrua`) |
| --- | --- | --- | --- |
| Inventory §2 (read-only) | Done 2026-10-23: no rows in any inventoried table; last migration `20261111090000` | Done 2026-10-23 through the Management API, linked project verified; results below | Not inspected; not linked |
| M1 | Applied 2026-10-23 (`20261112090000`); rebuilt from migrations with `db reset` (LOCAL held no rows); 51/51 SQL suites, the new assignment race runner (9 races), and the related race runners and `run_staff_end_access_faults` / `run_professional_history_faults` pass; `run_clinical_record_faults` repaired (42/42 mutants caught, §8) | Applied 2026-10-23 with `db push` after a dry run listing only `20261112090000`; history, catalog, ACLs, withdrawn operations, and an always-aborted permission matrix verified; inventory identical before and after | Not applied |
| Cleanup §3 | Not needed; rehearsed in a rolled-back transaction | **Executed 2026-10-23** with explicit authorization; result in §10 | — |
| M2 | Written and applied 2026-10-23 (`20261113090000`), committed in `a587562`; rebuilt from migrations with `db reset`; guard verified by `run_appointment_clinical_record_migration_guard.py` (14/14 retired-documentation criteria refused, pre-M2 schema intact, clean body accepted); full regression in §11 | Applied 2026-10-24 in the coordinated M2–M4 deployment, after `punto8_dev_m2_m4_deploy_preflight_readonly.sql`; verified with `punto8_dev_m2_m4_postdeploy_readonly.sql` | Not applied |
| M3 | Written and applied 2026-10-23 (`20261114090000`), committed in `9a22458`; reconciliation and guard verified by `run_appointment_completion_care_authorization_migration_guard.py`; full regression in §12 | Applied 2026-10-24 in the same deployment; verified by the same postdeploy check | Not applied |
| M4 | Written and applied 2026-10-24 (`20261115090000`) with the Edge Function change, committed in `cd94703`; full regression and a local end-to-end Edge check in §13 | Applied 2026-10-24 in the same deployment, with the `clinical-attachments` Edge Function deployed | Not applied |
| M5 | Written and applied 2026-10-24 (`20261116090000`), not committed; preservation and guard verified by `run_editable_clinical_record_versions_migration_guard.py`; full regression in §15 | Not applied; read-only `punto8_dev_m5_preflight_readonly.sql` and `punto8_dev_m5_postdeploy_readonly.sql` prepared, not run | Not applied |
| Mobile §6 steps 1 and 4 | Implemented 2026-10-23 against the M1–M3 contract, committed in `864a9fe`: assignment row and actions, the Appointment clinical record section with the inline editor, author rectification and clarifying records on the professional Appointment detail; Encounter, Draft, and Finalize screens and modules removed. Moved to the M5 contract 2026-10-24, not committed (§15): no clinical time, compact category selector, "Edit" with versions, "View changes", the rectification screen removed. Verified only with mocked data modules (Jest, TypeScript, ESLint, Prettier); no real integration test | The M1–M4 client works against DEVELOPMENT today; the M5 client needs M5 applied there (§15); no build made | — |

DEVELOPMENT inventory (2026-10-23, last migration `20261111090000`):

- retained baseline: 24 Users, 5 Pets, 5 Guardianships, 6 Organizations,
  24 Clinics, 25 Appointments (8 `COMPLETED`, 3 `CONFIRMED`, 1 `REQUESTED`,
  6 `CANCELLED`, 1 `NO_SHOW`, 6 `EXPIRED`), 35 Lifecycle Events,
  59 Schedule Revisions, 21 Reschedule Proposals, 26 Care Authorizations,
  93 Communications, 0 Appointment Veterinarian Assignments;
- 8 Clinical Encounters: 1 `ACTIVE` and 5 `CONCLUDED` on `COMPLETED`
  Appointments with an `ACTIVE` authorization, 1 `CONCLUDED` on a `CONFIRMED`
  Appointment whose authorization is `REVOKED`, and 1 `ACTIVE` Clinical
  Intake Encounter without an Appointment; 3 Encounters have no Entries;
- 9 Clinical Record Entries: 4 `FINALIZED` and 1 `DRAFT` on `COMPLETED`
  Appointments, 1 `FINALIZED` on the `CONFIRMED` one, 3 `FINALIZED` on the
  Intake Encounter; 3 Amendments; 0 contributors; 1 `AVAILABLE` Attachment with
  1 stored object and no orphan object;
- 136 Medical Access Audit Events: 100 clinical-scoped to delete (49
  `ACCESS_FOR_CLINICAL_CARE`, 38 `ACCESS_FOR_POST_CARE_DOCUMENTATION`, 9
  `VIEW_CLINICAL_ATTACHMENT`, 4 history reads that reference an Encounter) and
  36 history reads to keep;
- all 8 `COMPLETED` Appointments keep an `ACTIVE` Care Authorization (ended by
  M3); 1 `ACTIVE` Clinical Intake authorization;
- expected-zero checks (I-4, I-9, I-10 revoked-with-active, I-11, I-12, I-13,
  I-16, I-17) are all 0.

What the DEVELOPMENT cleanup and M2 would remove: the 9 Entries (one of them a
Draft), 3 Amendments, 1 Attachment and its Storage object, 100 audit events,
and the 8 Encounters. Every other row listed above is retained. Afterwards the
`CONFIRMED` Appointment whose Encounter is removed has no clinical record, so
cancellation and `NO_SHOW` become possible for it again, and the Pets' Guardian
histories no longer show the 9 test Entries.

## 10. DEVELOPMENT cleanup result (2026-10-23)

Executed with the explicit authorization of 2026-10-23, after the
`run_clinical_record_faults` repair.

**Immediately before.** Branch `dev`; linked project `eqvlydfflfvltprkwcxx`
("MenizVet Dev", the only linked project; Production not linked); last
migration `20261112090000`. The preflight matched every fingerprint of the
script exactly (Encounters 8 `8ad3b6e9…`, Entries 9 `c09a01bc…`, Amendments 3
`c4eec7d9…`, Attachments 1 `90c995a2…`, clinical audit events 100
`b19ef1ee…`), 0 contributors, 0 Lifecycle Events with an Encounter, 136 audit
events, the retained counts of §3.2, and one Storage object, also listed by the
Storage API. The nine foreign keys into the clinical tables were those of §3.1.
The Git index held only this transition's files, identical to the working tree
except later edits by the same work; it was not modified.

**SQL step.** `supabase/provisioning/punto8_dev_clinical_cleanup.sql` ran as one
statement and committed without error. Afterwards: 0 Encounters, 0 Entries, 0
Amendments, 0 Attachments, 0 contributors, 0 clinical audit events, 0 audit
events with any clinical reference, 36 audit events kept; all 14 non-internal
triggers of the clinical and audit tables enabled (`tgenabled = 'O'`).

**Storage step.** After the commit, exactly
`clinical-attachments/v1/9bc0625f-ceaf-4c61-8562-0eda1134552f` was removed
through the Storage API of the linked project (`deleted` reported that one
path). The bucket listing is empty and the preflight reports
`storage_objects = []`. No incident.

**Retained, unchanged** (full inventory compared before and after): 25
Appointments (8 `COMPLETED`, 3 `CONFIRMED`, 1 `REQUESTED`, 6 `CANCELLED`, 1
`NO_SHOW`, 6 `EXPIRED`), 35 Lifecycle Events, 59 Schedule Revisions, 21
Reschedule Proposals with unchanged states, 26 Care Authorizations with
unchanged states and ending contexts (10 `ACTIVE` Appointment Care, including
the 8 of `COMPLETED` Appointments that M3 will end, 1 `ACTIVE` Clinical Intake,
2 `REVOKED`, 13 `ENDED`), 93 Communications, 24 Users, 5 Pets, 5
Guardianships, 6 Organizations, 24 Clinics, 0 Appointment Veterinarian
Assignments. Only the clinical inventory items changed.

**Readiness for M2.** No row references `clinical_encounters`,
`clinical_record_entries`, `clinical_amendments`, or `clinical_attachments`;
every clinical table is empty, so M2's fail-closed guard is satisfied in
DEVELOPMENT. M2 is not written or applied.

## 11. M2 LOCAL verification (2026-10-23)

LOCAL only; not committed; DEVELOPMENT and Production untouched.

- `npx supabase db reset --local` from scratch with
  `20261113090000_appointment_owned_clinical_documentation.sql` applied.
- Catalog scan: no function, view, trigger or column references a retired
  object; no retired operation is executable by `authenticated`.
- `run_all_sql_suites.py`: 50/50 SQL suites pass, zero public/Auth rows
  afterwards (new `appointment_clinical_record_spec_med_010.sql`; retired
  `minimal_clinical_record_spec_med_001_009.sql` and
  `clinical_encounter_after_completion_spec_med_001.sql`).
- Fault runners: `run_appointment_clinical_record_faults.py` 70/70 (replaces
  `run_clinical_record_faults.py`, 42), `run_clinical_amendment_faults.py`
  32/32, `run_professional_history_faults.py` 34/34,
  `run_care_authorization_revocation_faults.py` 24/24,
  `run_subscription_safety_faults.py` 28/28; every other fault runner passes
  unchanged.
- Race runners: `run_clinical_record_concurrency.py` (14 races, 2 overlaps),
  `run_clinical_amendment_concurrency.py`, `run_professional_history_concurrency.py`,
  `run_care_authorization_revocation_concurrency.py` rewritten for the new
  model; every race runner passes with restoration and zero retained fixtures.
- `run_appointment_clinical_record_migration_guard.py`: 14/14 retired
  documentation criteria refused with `55000`, pre-M2 schema intact after each
  attempt, clean body accepted, M2 then applied with `migration up --local`.

## 12. M3 LOCAL implementation and verification (2026-10-23)

LOCAL only; not committed; DEVELOPMENT and Production untouched; no cleanup.

**Migration** `20261114090000_appointment_completion_ends_care_authorization.sql`
(forward-only, requires M2):

- guard (55000, nothing changed) unless every `COMPLETED` Appointment has
  exactly one Appointment Care Authorization and exactly one
  `CONFIRMED → COMPLETED` Event, none of those authorizations is already
  `ENDED`, and every `ACTIVE` one was granted no later than a finite,
  non-future completion time;
- ending context `APPOINTMENT_COMPLETED`;
- coherence: an authorization ended with `APPOINTMENT_COMPLETED` belongs to a
  `COMPLETED` Appointment and ends exactly at its completion Event; a
  `COMPLETED` Appointment never retains an `ACTIVE` authorization (deferred,
  like the other terminal states);
- `complete_appointment` (same signature, result and ACL) locks the
  authorization after the Appointment, as cancellation and no-show do, and ends
  an `ACTIVE` one at the completion instant in the same transaction; `REVOKED`
  (and any other inactive state) is unchanged; nothing is created or
  reactivated; no clinical row is read or written;
- reconciliation: every `ACTIVE` authorization of a `COMPLETED` Appointment
  ends with `APPOINTMENT_COMPLETED` at that Appointment's recorded completion
  Event time; the count is reported as a notice.

**DEVELOPMENT** (not run): the 8 `ACTIVE` authorizations of `COMPLETED`
Appointments recorded in §9/§10 are exactly what the reconciliation would end;
the 2 `REVOKED` ones stay. Run the read-only preflight before applying M2+M3:
every `guard_*` value must be 0 and `to_end.n` must be 8.

**Verification (LOCAL, from `db reset`):** see the delivery report of this
date; all SQL suites, every fault runner and every race runner pass, including
`run_appointment_completion_care_authorization_faults.py` (9/9) and the
completion races in `run_care_authorization_revocation_concurrency.py`.
Four mutants of earlier runners are now caught by an earlier assertion
(their probes target `COMPLETED` Appointments, whose authorization M3 ends);
the "history opened by a `COMPLETED` Appointment" mutants became equivalent
under M3 and were replaced by the observable fault (history opened through a
`COMPLETED` Appointment whatever its authorization state). No mutant was
removed without replacement.

## 13. M4 LOCAL implementation and verification (2026-10-24)

LOCAL only; not committed; DEVELOPMENT and Production untouched; nothing
deployed.

**Finding.** After M2 the deployed `clinical-attachments` Edge Function still
exposed four professional routes with no client consumer: `initiate` (accepted
a client `uploader_vca_id`, cross-checked, and would publish a validated
Attachment to Guardians at once, with no Draft review left), `complete`,
`remove`, and `professional-download` (accepted a client `accessing_clinic_id`
and `care_authorization_id`, cross-checked, plus the former Encounter
parameter, accepted only as NULL). Their SQL operations were `service_role`
only and re-validated authority, so no bypass of SPEC-MED-010 was found, but
they contradicted BR-24 (no client-supplied Care Authorization or Clinic
Assignment) and offered an unspecified professional upload path. They are
retired rather than re-keyed (SPEC-MED-010 BR-19, BR-25).

**Migration** `20261115090000_retire_professional_attachment_routes.sql`
(forward-only, requires M2 and M3; guard 55000 otherwise): drops
`initiate_clinical_attachment_upload`, `resolve_clinical_attachment_completion_target`,
`remove_draft_clinical_attachment` and the seven-argument
`authorize_clinical_attachment_download`; creates
`authorize_guardian_clinical_attachment_download(p_auth_subject, p_attachment_id)`,
exactly the former Guardian branch (current Guardianship of the Attachment's
own Pet, `AVAILABLE`/`STORED`/current Attachment, missing-object `XX001`, one
Guardian `VIEW_CLINICAL_ATTACHMENT` audit), `service_role` only. No row is read
or written; no table changes.

**Edge Function:** routes `guardian-download` (reads only `attachment_id`) and
`maintenance` (secret only); every other name, including the four retired
routes, is `404 NOT_FOUND` before authentication or body parsing. Upload-only
shared code (`access-context.ts`, `filename.ts`, signed-upload options, the
signed-upload validity constant) is removed. Retained, with no client
authority: the Storage validation and cleanup pass behind `maintenance`
(`claim_clinical_attachment_maintenance`, `mark_clinical_attachment_object_stored`,
`complete_clinical_attachment_validation`, `expire_missing_stale_clinical_attachment_upload`,
`mark_clinical_attachment_object_deleted`) — it is the integrity pipeline any
later BR-19 workflow needs and is reachable only with the maintenance secret.

**Verification (LOCAL, from `db reset`):** 49/50 SQL suites with zero retained
rows; the remaining one, `requested_appointment_alternative_time_spec_apt_018_019_020.sql`,
fails identically with M4 absent (rebuilt at `20261114090000`) because it
assumes 48 half-hour positions tomorrow and 2026-10-25 has 25 hours in
Europe/Madrid — a pre-existing date dependency, not an M4 effect. Every fault,
race, and Edge runner passes, including the new
`run_guardian_attachment_download_faults.py` (12/12) and
`run_edge_clinical_attachment_faults.py` (9/9);
`run_appointment_clinical_record_faults.py` is 68/68 (its four mutants of the
retired operations are replaced by two "retired operation reappears" and one
grant mutant). Deno `clinical-attachments` tests 49/49 with type checking (the
pre-existing `Uint8Array`/`BufferSource` error in `integrity.ts` is fixed by
digesting an `ArrayBuffer`-backed copy). A local end-to-end check through
`supabase functions serve` with real Auth users, JWTs and a stored PDF passed
23/23: the four retired routes are `NOT_FOUND` for a Veterinarian, a Guardian
and an anonymous caller and change nothing; the current Guardian receives a
signed URL that serves the exact PDF; a Guardian of another Pet (even sending
Care Authorization, Clinic, Encounter, Pet and User identifiers) and a
Veterinarian of the Entry's Clinic are `DENIED`; every decision is audited as a
Guardian access with no professional provenance; `maintenance` refuses
without the secret. All fixtures were removed afterwards.

**Coordinated DEVELOPMENT deployment of M2, M3 and M4** (each step needs
explicit authorization; Production is out of scope):

1. Stop using the old Android build (§6 step 2).
2. Read-only preflights against DEVELOPMENT (`supabase/.temp/project-ref` is
   `eqvlydfflfvltprkwcxx`):
   `npx supabase db query --linked -f supabase/provisioning/punto8_dev_m2_m4_deploy_preflight_readonly.sql`
   must report `is_development: true`, `last_migration: 20261112090000`, the
   three Punto 8 migrations pending, every `m2_*` and `m3_guard_*` value 0,
   `m3_to_end: 8` (`m3_revoked_kept` equals `revoked_kept.n` of the M3
   preflight), and `m4_attachment_storage_objects: 0`;
   `punto8_dev_m3_reconciliation_preflight_readonly.sql` lists the 8 rows.
3. `npx supabase db push --dry-run` lists exactly `20261113090000`,
   `20261114090000`, `20261115090000`, in that order.
4. `npx supabase db push`: M2, M3 and M4 apply in order, each in its own
   transaction; a refused guard stops the push before later stages.
5. Immediately
   `npx supabase functions deploy clinical-attachments --project-ref eqvlydfflfvltprkwcxx`
   (`verify_jwt = false` from `config.toml`, as deployed today; no new or
   changed secrets — `npx supabase secrets list --project-ref eqvlydfflfvltprkwcxx`
   still shows `CLINICAL_ATTACHMENTS_MAINTENANCE_SECRET`). Between steps 4 and 5 the previously deployed function
   fails closed: its professional routes and its Guardian download call
   dropped operations and return `500`; with no Attachment in DEVELOPMENT no
   Guardian is affected. Deploying the function first would also fail closed
   (`guardian-download` would call an operation that does not exist yet), so
   the database goes first.
6. Post-checks: `npx supabase migration list` ends at `20261115090000`;
   `npx supabase db query --linked -f supabase/provisioning/punto8_dev_m2_m4_postdeploy_readonly.sql`
   reports every `expect_*` true and `ended_by_completion: 8`; over HTTP, each
   retired route answers `404 NOT_FOUND`, `guardian-download` without a token
   `401`, and `maintenance` without the secret `401`.
7. Install the new development build and validate with Metro (§6 step 3).

## 14. Pre-deployment validation (2026-10-24)

**Calendar-independent alternative-time suite.**
`requested_appointment_alternative_time_spec_apt_018_019_020.sql` §12c read
real "today" and "tomorrow" in the first of three zones with time left today
and asserted 48 half-hour positions per day; on 2026-10-24 tomorrow is the
25-hour fall-back day in Europe/Madrid, so the count was 46. §12c now also
requires today and tomorrow to be regular days (local midnight to the midnight
after tomorrow is exactly 48 elapsed hours); a simulation every 30 minutes over
2026–2028 always finds such a zone. Transition days are covered
deterministically in §12b on the next real Europe/Madrid transition dates: the
30-minute grid has exactly the 46 existing positions on both days (02:00 and
02:30 are nonexistent at spring-forward and ambiguous, hence omitted
fail-closed, at fall-back — SPEC-APT-013 BR-52, BR-58), summer offsets before
the repeated hour and winter offsets after it, 30 elapsed minutes per
candidate, 01:30 ending at the first 02:00, and a request on the fall-back day
keeping its other 45 positions. No production SQL changed.

**Finding, not fixed (pre-existing, outside Punto 8).**
`clinic_interval_is_covered_by_timezone` compares the interval's Clinic-local
civil start and end and rejects it when the local end is not after the local
start. An interval that starts in the first occurrence of the repeated
fall-back hour therefore reads as uncovered: proposing 02:30 with offset
+02:00 on the fall-back day is rejected with "Clinic Appointment Availability
does not cover the proposed interval" although the Clinic is open 00:00–24:00,
while 02:30 with +01:00 is accepted. It fails closed and no product client can
reach it, because every candidate read omits the ambiguous positions; it
affects only a direct call that supplies the first-occurrence offset.
Recorded for a later scheduling fix.

**Mutation inventory.** `run_appointment_clinical_record_faults.py` went
from 70 to 68. Removed, because they mutated operations M4 deleted:
"CLINICAL_CARE gate removed for new Attachments" and "Non-author adds an
Attachment" (`initiate_clinical_attachment_upload`), "Non-author abandons an
Attachment" and "AVAILABLE Attachment removable through the operation"
(`remove_draft_clinical_attachment`). Replaced: the grant fault "Attachment
initiation executable by authenticated" became "Guardian Attachment download
authorizer executable by authenticated". Added: "a retired professional
Attachment operation reappears" and "the multi-context download authorizer
reappears". The structural rules stay mutated ("AVAILABLE Attachment mutable",
"Structural author-only Attachment rule removed"), and the Guardian download
gained `run_guardian_attachment_download_faults.py` (12) and the Edge routes
`run_edge_clinical_attachment_faults.py` (9).

## 15. M5 LOCAL implementation and verification (2026-10-24)

**What changes for the Veterinarian.** A new record asks for a category (a
compact selector, nothing preselected), the clinical text and, only for
`OTHER`, its context — no clinical time: the server records its own, shown as
"Registrado el …". The author's own record offers **Editar**: the same inline
editor, filled with the current version, saved with **Guardar cambios**,
without a reason or a second confirmation. The record then shows the current
version, its original recording date, a discreet "Editado el …", and **Ver
cambios** with every earlier version (what, when, by whom). Another
Veterinarian never edits it; the assignee may add a clarifying record. While an
editor is open, Complete is not shown. The Appointment detail reads, in order:
Pet, status, one date-and-time row and the reason; the Veterinarian; **Ver
antecedentes**; the Clinical record; Complete; the contact and the other
actions. The Guardian history and the professional history show the current
version with the same "Editado" and "Ver cambios".

**Persistence (migration `20261116090000_editable_clinical_record_versions.sql`).**
Nothing is overwritten. The recorded Entry stays version 1, immutable; an edit
appends one Clinical Amendment of kind `EDIT` with the complete next version
(`version_number`, category, OTHER context, content, the author and their
current Clinic Assignment, the server's time), numbered without gaps and unique
per Entry. Existing Amendments become kind `ADDENDUM` with their facts
unchanged (adding a column with a default fires no trigger) and are shown as
earlier corrections; no new one can be written. `clinical_event_at` stays on
Entries recorded before M5 and still orders the history; a new Entry with an
event time is refused structurally. No row is updated or deleted.

**Contract.** `create_appointment_clinical_entry(p_clinic_id, p_appointment_id,
p_idempotency_key, p_category, p_clinical_content, p_other_category_context)`
replaces the eight-argument form; its request digest keeps the former shape
with an absent event time. `edit_appointment_clinical_entry(p_clinic_id,
p_appointment_id, p_entry_id, p_idempotency_key, p_expected_version,
p_category, p_clinical_content, p_other_category_context)` returns
`EDITED` / `ALREADY_EDITED` / `UNCHANGED` with the version, and refuses with
the uniform `42501` (no documentation access, unknown or foreign target),
`ENTRY_AUTHOR_REQUIRED`, `KEY_REQUIRED`, `INVALID_VERSION`, the BR-5 field
hints, `KEY_CONFLICT` and `STALE_VERSION`; it locks the Entry, so two edits of
one version serialize and the second is `STALE_VERSION`. It needs no
Entitlement and no Care Authorization. The three reads carry `version`,
`edited_at`, `previous_versions` (oldest first, at most 100) and
`previous_versions_truncated`; `amendments` lists only `ADDENDUM` rows. The
version helpers are internal. `create_appointment_clinical_amendment` and
`create_clinical_amendment` are dropped.

**Verification (LOCAL).** The full battery (§25 of `docs/TESTING.md` plus the
three migration guards and the assignment race runner) — 36 steps:

| Step | Result |
| --- | --- |
| `run_all_sql_suites.py` | 50/50 suites pass; zero retained rows |
| `run_clinical_amendment_faults.py` (rewritten for edits) | 48/48 mutants caught (was 30) |
| `run_clinical_amendment_concurrency.py` (rewritten) | every race as expected, including two edits of one version (`EDITED` / `STALE_VERSION`) |
| `run_appointment_clinical_record_faults.py` | 70/70 (was 68): the "Now" and event-time mutants replaced by a stamped event time, OTHER-context normalization, digest scope, a stale version accepted, and the retired operations reappearing |
| `run_professional_history_faults.py` | 37/37 (was 33): the original shown instead of the current version, earlier versions omitted from the professional and the Guardian reads |
| `run_care_authorization_revocation_faults.py` | 24/24 (the Amendment mutant now an edit mutant) |
| `run_subscription_safety_faults.py` | 28/28 (the three continuity mutants rewritten for the edit operation) |
| `run_editable_clinical_record_versions_migration_guard.py` (new) | historical timed Entry and author Amendment preserved; 2/2 unexpected states refused; M5 applied afterwards |
| Every other runner, guard and race runner | pass |

Mobile (`apps/mobile`): TypeScript, ESLint and Prettier clean; Jest 126
suites, 2644 tests, all with mocked data modules — no real integration test.
No native dependency was added and `app.json` is unchanged, so the existing
Android development build only needs the new JavaScript bundle from Metro.

**DEVELOPMENT deployment plan (not executed; needs explicit authorization).**
The DEVELOPMENT data read before M5 held 2 Entries, both with a clinical event
time, and 1 Amendment by its Entry's author: M5's guard passes and both stay
unchanged (the Amendment becomes an `ADDENDUM`).

1. Stop using the installed client against DEVELOPMENT: after M5 its record
   call (eight arguments) and rectification fail.
2. `npx supabase db query --linked -f supabase/provisioning/punto8_dev_m5_preflight_readonly.sql`:
   `is_development` true, `m4_contract_present` true, `m5_applied` false,
   `m5_guard_amendments_not_by_author` 0; keep the counts and fingerprints.
3. `npx supabase db push --dry-run` must list only `20261116090000`; then
   `npx supabase db push`. No Edge Function changes.
4. `npx supabase db query --linked -f supabase/provisioning/punto8_dev_m5_postdeploy_readonly.sql`:
   every `*_ok` true; counts and fingerprints equal to the preflight; no new
   audit event.
5. Reload the development build from Metro (no new build needed).

If any check differs, stop without repairing data or guards; there is no
automatic rollback of M5 (its effect is additive and its retired operations
would have to be restored by a new forward migration).

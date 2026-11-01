# Testing Strategy

## 1. Purpose

This document defines the testing principles used to verify the behavior,
security, integrity, and critical workflows of the system.

Testing follows the project's specification-driven approach:

    Requirement
        ↓
    Specification
        ↓
    Business Rules
        ↓
    Scenarios
        ↓
    Verification Notes
        ↓
    Automated Tests

Approved Specifications are the primary behavioral source for test design.

Tests must verify domain behavior rather than reproduce implementation details.

---

## 2. Testing Principles

### Specifications drive verification

Every approved Specification contains Verification Notes describing the
behavior that must be demonstrably correct.

Those Verification Notes should be converted into automated tests at the most
appropriate testing level.

The test suite must not rely only on manually checking application screens.

---

### Test behavior, not implementation details

Tests should primarily verify observable domain behavior.

For example:

    Given an Appointment is CONFIRMED
    When it is cancelled
    Then it becomes CANCELLED

is preferred over asserting internal implementation details such as:

    function X called function Y three times

unless those implementation details are themselves required for correctness.

---

### Critical authorization must be tested outside the client

Client-side UI restrictions are not sufficient verification of authorization.

Tests must demonstrate that unauthorized operations fail when attempted
directly through trusted backend or data-access boundaries.

A manipulated or alternative client must not be able to bypass domain
permissions.

---

### Domain invariants require explicit verification

Critical invariants must be verified independently from ordinary happy-path
workflow tests.

Examples include:

- one Pet may have multiple Guardians;
- one User may belong to multiple Organizations;
- Organization Membership is temporal;
- historical clinical provenance is preserved;
- Veterinarian status does not grant arbitrary medical access;
- subscription termination does not erase history;
- private operations require authenticated identity.

---

### Historical integrity requires regression protection

Tests must verify not only that new operations succeed, but also that later
domain changes do not rewrite established historical truth.

For example:

    Veterinarian leaves Organization
        ↓
    old clinical record provenance remains unchanged

or:

    Organization Subscription expires
        ↓
    historical medical records remain unchanged

---

## 3. Testing Levels

Different behaviors should be verified at different levels.

No single test level is expected to prove the entire system.

### Domain and unit tests

Use focused tests for deterministic domain behavior such as:

- lifecycle transition eligibility;
- authorization decision logic;
- availability calculations;
- time-interval overlap;
- entitlement evaluation;
- controlled taxonomy validation;
- profile validation;
- state-transition rules.

These tests should be fast and isolated where practical.

---

### Database integration tests

Use database-level integration tests for behavior involving:

- foreign-key integrity;
- unique constraints;
- temporal relationship constraints;
- transaction boundaries;
- concurrent updates;
- migration correctness;
- persistence of historical information;
- database authorization policies where applicable.

A domain rule enforced by the database must be tested against the real database
behavior rather than only through mocks.

---

### Authorization and security integration tests

Critical protected operations require explicit tests demonstrating both:

    authorized context
    → operation succeeds

and:

    unauthorized context
    → operation fails

These tests should include attempts that bypass the normal mobile UI.

Examples include:

- Guardian attempts access to unrelated Pet;
- former Guardian attempts Pet access;
- Veterinarian attempts arbitrary medical-history access;
- Organization Member attempts another Organization's operation;
- Clinic actor attempts another Clinic's schedule;
- expired Entitlement attempts normal paid professional activity;
- signed-out session attempts private operation.

---

### Workflow integration tests

Use workflow tests where several domain components must interact.

Examples include:

    Appointment request
        ↓
    Care Authorization
        ↓
    Clinic triage
        ↓
    Appointment confirmation

or:

    Clinical Encounter
        ↓
    Draft Clinical Record Entry
        ↓
    Finalization
        ↓
    Amendment

These tests verify collaboration between domain components without requiring
full end-user interface automation.

---

### End-to-end tests

End-to-end tests should be reserved for critical user journeys and integration
boundaries where confidence cannot be obtained efficiently from lower-level
tests.

Examples may include:

- registration → verification → authentication;
- Guardian registers Pet → invites another Guardian → invitation accepted;
- Guardian requests Appointment → Clinic confirms → Guardian sees update;
- Veterinarian accesses authorized Pet history → provides care → record is
  finalized;
- account recovery restores access to the same domain User.

The end-to-end suite should remain smaller than lower-level test suites.

---

## 4. Specification Verification

Each approved Specification should have automated coverage derived from its
Verification Notes.

For example:

    SPEC-PET-003
    Verification Note:
    "Invitation acceptance creates an active Guardianship."

should produce a corresponding test demonstrating that behavior.

Where one Verification Note requires several test cases, multiple tests may be
used.

Where several Verification Notes can safely be verified through one scenario,
a single test may cover them together.

The important requirement is demonstrable behavioral coverage, not a strict
one-test-per-note ratio.

---

## 5. Positive and Negative Testing

Critical workflows require both successful and denied behavior.

For example:

### Positive

    Given Maria is Luna's active Guardian
    When Maria views Luna's Appointments
    Then access succeeds

### Negative

    Given Carlos is not Luna's Guardian
    When Carlos views Luna's Appointments
    Then access is denied

Testing only successful paths is insufficient for authorization-sensitive
behavior.

---

## 6. Lifecycle Testing

Entities with explicit lifecycle state must be tested for:

- valid transitions;
- invalid transitions;
- terminal-state behavior;
- repeated operations;
- historical preservation.

For example:

    REQUESTED
        ↓
    CONFIRMED
        ↓
    COMPLETED

must be tested alongside invalid transitions such as:

    COMPLETED
        ↓
    REQUESTED

which must fail through the ordinary workflow.

Applicable entities include:

- Organization Invitations;
- Organization Memberships;
- Guardianship Invitations;
- Appointments;
- Care Authorizations;
- Clinical Record Entries;
- Subscriptions;
- other entities with controlled lifecycle state.

---

## 7. Temporal Relationship Testing

Temporal domain relationships require tests demonstrating both current and
historical behavior.

Examples include:

    Organization Membership
    effective_start
    effective_end

    Clinic Assignment
    effective_start
    effective_end

Tests should verify:

- current relationship grants applicable capability;
- ended relationship no longer grants current capability;
- historical relationship remains identifiable;
- rejoining creates a new relationship period rather than rewriting the old
  one.

---

## 8. Multi-Context Testing

The system deliberately supports Users participating in several independent
contexts.

Tests must therefore include scenarios such as:

    Dr. Garcia
    ├── Animalia Membership
    └── VetCare Membership

and:

    Dr. Garcia
    ├── Animalia Madrid Clinic Assignment
    └── VetCare Toledo Clinic Assignment

Verification must demonstrate that authorization and Entitlements remain scoped
to the relevant Organization and Clinic.

Success in one context must not grant access in another.

---

## 9. Shared Guardian Testing

Because multiple Guardians may share responsibility for one Pet, tests must
avoid assuming one User owns one private copy of a Pet.

Important scenarios include:

- two Guardians see the same Pet;
- both may maintain the shared Pet Profile;
- both may see the Pet's Appointments;
- material Appointment notifications may target both current Guardians;
- one Guardian leaving does not remove the other;
- former Guardians lose current access;
- historical requester attribution remains unchanged.

---

## 10. Clinical History Testing

Medical Record tests require strong historical-integrity guarantees.

Tests must demonstrate that:

- medical history follows the Pet;
- Entries from several Clinics coexist;
- finalized information is not silently rewritten;
- Amendments preserve original information;
- authorship remains traceable;
- provider provenance survives professional changes;
- provider provenance survives Organization changes;
- Subscription termination does not erase clinical history.

Clinical tests must distinguish:

    Appointment scheduling history

from:

    actual Clinical Encounter

and:

    finalized Medical Record

These concepts must not be treated as interchangeable.

---

## 11. Medical Access Control Testing

Medical access requires explicit authorization testing.

The suite must include cases demonstrating that:

    Veterinarian status alone
        ≠
    access to arbitrary Pet medical information

Tests should cover:

- active Care Authorization;
- revoked Care Authorization;
- cross-clinic medical history;
- Clinic and Organization context;
- least privilege;
- active-care continuity where applicable;
- former Guardian behavior;
- denied access auditing.

---

## 12. Audit Testing

Audit tests should verify meaningful domain-level accountability.

Tests should demonstrate that relevant Medical Access Audit Events preserve
information such as:

- acting User;
- Pet;
- Clinic or Organization context where applicable;
- access basis;
- resource scope;
- outcome;
- timestamp.

Tests must not require one domain Audit Event for every internal technical
query.

Technical logging and domain auditing remain separate.

See:

- ADR-002 — Use Domain-Level Medical Access Auditing

---

## 13. Subscription and Entitlement Testing

Commercial tests must preserve the distinction between:

    Subscription state

and:

    professional Entitlement

Tests should cover:

- active commercial validity;
- pending Subscription;
- past-due policy;
- cancellation before commercial expiration;
- expired Subscription;
- Organization-specific Entitlements;
- Entitlement denial despite User authorization;
- User authorization denial despite valid Entitlement;
- safe resolution of existing obligations after Entitlement loss;
- preservation of historical data.

---

## 14. Appointment Scheduling and Availability Testing

Scheduling tests should include:

- Clinic availability;
- Veterinarian availability;
- recurring availability;
- date-specific exceptions;
- Appointment duration;
- overlapping intervals;
- cross-Clinic Veterinarian conflicts;
- re-evaluation at confirmation;
- re-evaluation during rescheduling;
- concurrent attempts to consume the same scheduling capacity.

Tests must verify that stale client availability cannot force an unsupported
confirmed Appointment.

---

## 15. Communication Testing

Communication tests must preserve the distinction between:

    domain event

and:

    communication delivery

For example:

    Appointment CONFIRMED
        ↓
    notification fails
        ↓
    Appointment remains CONFIRMED

Tests should verify:

- transactional email failure does not repeat the domain operation;
- push delivery is not treated as acknowledgement;
- one User may have several Push Registrations;
- signed-out device contexts no longer receive private User push;
- stale notification links load current authoritative state;
- reminders are suppressed for Appointments that are no longer eligible;
- rescheduled Appointment reminders follow the new confirmed time.

External providers should be isolated where practical while preserving
integration coverage for provider boundaries.

---

## 16. Concurrency Testing

Concurrency-sensitive workflows require explicit testing where competing
operations could violate domain integrity.

Examples include:

- two Guardians updating the same Pet Profile;
- simultaneous Appointment confirmations;
- two operations attempting to assign the same Veterinarian to overlapping
  Appointments;
- repeated Membership termination;
- duplicate Invitation acceptance;
- duplicate provider callbacks.

The final committed state must remain coherent.

---

## 17. Migration Testing

Database evolution must be reproducible.

Migration testing should demonstrate that:

- migrations apply successfully to the expected previous schema state;
- required constraints are created;
- migrations do not silently destroy required historical information;
- the resulting schema supports the approved domain model.

Where practical, the database should be constructible from source-controlled
migrations rather than manual schema configuration.

---

## 18. External Integration Testing

External providers may include:

- authentication provider;
- email provider;
- push provider;
- object storage;
- subscription or billing provider.

The system should test integration boundaries without making the entire test
suite dependent on live third-party services.

Provider-specific failures must not corrupt domain state.

Important integration behavior includes:

- retries;
- duplicate callbacks;
- invalid destinations;
- stale events;
- temporary provider unavailability.

---

## 19. Test Data

Test data must be deterministic and intentionally constructed.

Tests involving authorization should clearly establish the relationships
required for the scenario.

For example:

    Maria → Guardian → Luna
    Carlos → not Guardian → Luna

is preferable to relying on large shared fixtures whose permissions are
difficult to understand.

Sensitive production data must not be copied casually into development or test
environments.

---

## 20. Regression Testing

Every confirmed defect affecting a critical domain rule should result in an
automated regression test where practical.

The regression test should reproduce the violated business behavior and remain
in the suite after the defect is corrected.

---

## 21. Continuous Integration

Critical automated tests should run through the project's continuous
integration workflow.

Changes that violate approved critical Specifications should not be considered
ready for integration.

The exact CI provider and workflow configuration are implementation decisions.

---

## 22. Traceability

Testing should preserve traceability conceptually equivalent to:

    REQ-APT-005
        ↓
    SPEC-APT-009
        ↓
    Verification Note 1
        ↓
    automated test(s)

Exact test naming does not need to encode every identifier, but the repository
should make it reasonably possible to determine which Specification behavior a
test verifies.

---

## 23. Coverage Philosophy

Numeric code coverage alone is not sufficient evidence of domain correctness.

A codebase may reach high line coverage while failing to verify critical
authorization or lifecycle rules.

Priority should be given to:

- requirement coverage;
- Specification behavior coverage;
- invariant coverage;
- authorization boundaries;
- historical-integrity behavior;
- failure cases.

Code coverage metrics may still be used as supporting diagnostic information.

---

## 24. Phase 1 Testing Priorities

Phase 1 places highest verification priority on:

1. authentication and authorization boundaries;
2. Guardianship and Organization relationship isolation;
3. medical-access control;
4. clinical-history integrity;
5. Appointment lifecycle and scheduling conflicts;
6. Subscription Entitlements;
7. protected file access;
8. auditability;
9. migrations and database integrity;
10. reliable communication behavior.

Lower-risk presentation details may rely more heavily on focused UI and manual
verification where automation provides limited value.

---

## 25. Local SQL regression and professional-authority mutation tooling

Run these commands from the repository root against **isolated LOCAL Supabase**
with Docker available. A clean reset is required for the all-suites zero-data
check. These commands never use a linked project or remote connection URL:

```powershell
npx supabase db reset --local
python supabase/tests/run_all_sql_suites.py
python supabase/tests/run_temporal_authority_faults.py
python supabase/tests/run_organization_staff_faults.py
python supabase/tests/run_organization_staff_paged_reads_faults.py
python supabase/tests/run_guardian_appointment_paged_reads_faults.py
python supabase/tests/run_guardian_appointment_awaiting_confirmation_faults.py
python supabase/tests/run_organization_professional_clinics_page_faults.py
python supabase/tests/run_published_clinic_name_search_faults.py
python supabase/tests/run_staff_invitation_faults.py
python supabase/tests/run_staff_invitation_concurrency.py
python supabase/tests/run_staff_invitation_acceptance_faults.py
python supabase/tests/run_staff_invitation_acceptance_concurrency.py
python supabase/tests/run_staff_end_access_faults.py
python supabase/tests/run_staff_end_access_concurrency.py
python supabase/tests/run_clinic_creation_faults.py
python supabase/tests/run_clinic_creation_concurrency.py
python supabase/tests/run_subscription_safety_faults.py
python supabase/tests/run_subscription_transition_concurrency.py
python supabase/tests/run_trusted_establishment_faults.py
python supabase/tests/run_trusted_establishment_concurrency.py
python supabase/tests/run_staff_workforce_faults.py
python supabase/tests/run_staff_workforce_concurrency.py
python supabase/tests/run_appointment_clinical_record_faults.py
python supabase/tests/run_appointment_completion_care_authorization_faults.py
python supabase/tests/run_guardian_attachment_download_faults.py
python supabase/tests/run_clinical_record_concurrency.py
python supabase/tests/run_clinical_amendment_faults.py
python supabase/tests/run_clinical_amendment_concurrency.py
python supabase/tests/run_professional_history_faults.py
python supabase/tests/run_professional_history_concurrency.py
python supabase/tests/run_care_authorization_revocation_faults.py
python supabase/tests/run_care_authorization_revocation_concurrency.py
python supabase/tests/run_edge_invitation_faults.py
python supabase/tests/run_edge_clinical_attachment_faults.py
python -B -m unittest discover -s supabase/tests -p test_sql_fault_harness.py
```

`run_all_sql_suites.py` runs every `supabase/tests/*.sql` suite (each must be
explicitly rollback-only), then requires zero rows in every public/Auth data
table (Auth's own migration ledger excluded) and unchanged public function
definitions/ACLs. The Python files are tooling, not SQL regression suites.

Professional-authority suites:

- `temporal_professional_authority.sql` — shared evaluators, professional
  reads, Veterinarian Membership dependency, the historical-continuity /
  current-authority boundary, and existing Organization, Clinic and
  Appointment consumers, including a representative Organization
  Administrator / Clinic Administrator / Clinic Receptionist sample;
- `professional_authority_create_then_act.sql` — ADR-009 trusted
  establishment followed by the provisioning composite in one statement (and
  its rollback on a late failure), acceptance, add, replace and end used in
  the statement that made them, and the monotonic instant;
- `organization_staff_spec_org_009.sql` — the Staff read contract;
- `staff_invitation_invite_revoke_spec_org_002_010.sql` — Staff Slice B1: the
  invite commands exactly as the Communications route calls them (fail-closed
  ordering, the four role/scope combinations, one trusted creation instant and
  the exact 7-day expiry bound into the envelope context, duplicate / former /
  active-Member rules, Staff read integration), revocation outcomes and
  authorization, Communication suppression at every pre-provider checkpoint,
  and serialization evidence. Exact row-lock modes come from the `pgrowlocks`
  extension, created only inside the suite's rolled-back transaction, because
  an FK insert alone key-share locks the Organization row;
- `staff_invitation_preview_accept_spec_org_003.sql` — Staff Slice B2
  (SPEC-ORG-003 §10–§13): the authenticated preview and acceptance through the
  real operations, on Invitations created by the real B1 commands with the
  SHA-256 digest of a known secret (legacy/terminal shapes inserted directly):
  contract and ACLs, authentication, the confirmed-email rule (acceptance
  only), the uniform `42501` failure for every unproven case and before every
  lifecycle state, post-proof outcomes writing nothing, masking, the
  email-match boolean, every Phase 1 role/scope plus legacy Organization
  Veterinarian and multi-responsibility shapes, exact Membership/Grant
  provenance and effective start, digest erasure, same-User `ALREADY_ACCEPTED`
  and `ACCEPTED_BY_YOU`, other-User and ended-Membership replay, the expiry
  boundary, an injected Grant failure, immediate authority in the same
  statement and session, no Communication, and lock evidence (a failed call
  releases its row locks with its subtransaction, so pre-proof locking under
  contention is pinned by the B2 race runner).

`run_staff_invitation_acceptance_faults.py` mutates the B2 operations and their
shared internals inside that suite's transaction (proof removed or reordered,
caller-supplied User id, confirmed-email rule, expiry/revocation/membership
checks, idempotency and provenance, digest erasure, partial Grant creation,
statement-instant authority, Communication delivery, locking, masking and
disclosure). Communications are immutable and unique per Invitation, so the
only reachable "acceptance sends email" mutant queues delivery work.

`staff_end_access_spec_org_004.sql` — Staff Slice C (SPEC-ORG-004 §10/§11):
`end_organization_staff_membership` through the real operation — contract and
ACLs (including no client `EXECUTE` on the generic `end_organization_membership`
and a real authenticated attempt on it), the uniform `42501` for unknown,
inaccessible and already ended targets, self and Owner rejection, one end
instant for the Membership and every active Grant, the temporal clamp,
`ALREADY_ENDED`, immediate loss of Organization, Clinic, Appointment and
Veterinarian Clinic Assignment authority, other-Organization isolation, Staff
read integration, untouched Invitations/Communications/Assignments/Appointments,
and a full invite → accept → end → re-invite → accept lifecycle proving a new
Membership period. `run_staff_end_access_faults.py` mutates the operation, the
shared Organization capability evaluator, the B2 acceptance writer (rejoin) and
the legacy ACL inside that suite's transaction.

`clinic_creation_spec_cli_001.sql` — Clinic creation self-service Phase 1
(SPEC-CLI-001 §10): `create_clinic(p_organization_id, p_idempotency_key)`
through the real operation — contract and ACLs (the one-argument form is
withdrawn), the uniform `42501` for every caller without
`ORGANIZATION_CREATE_CLINICS` (Clinic Administrator, Receptionists,
Veterinarian, other Organization, ended and not-yet-started authority, no
Membership) and for unknown Organizations, the required key, creation without
any Subscription, an unpublished Clinic with no configuration rows, same-key
replay (same and second administrator), a different key, the same key in
another Organization, unauthorized replay without disclosure, a lost-response
retry, key immutability, Professional Clinics / context / managed / public
reads, Clinic settings and Appointment configuration on the new Clinic, and
Organization-row serialization (via `pgrowlocks`). `run_clinic_creation_faults.py`
mutates the operation, the Clinic immutability trigger and the ACLs inside that
suite's transaction.

Staff Slices B1, B2 and C, and Clinic creation, also have runners outside the
rollback-only suites:

- `run_staff_invitation_concurrency.py` races real operations in two local
  sessions (duplicate invite, revoke vs revoke, revoke vs accept in both
  orders, revocation blocked across the expiry boundary, revoke vs provider
  handoff in both orders). A second backend only sees committed rows, so it
  commits a small synthetic fixture (prefix `d0271000-`) and always deletes it
  again; restored row counts and zero retained fixtures are verified;
- `run_staff_invitation_acceptance_concurrency.py` uses the same primitives
  (fixture prefix `d0281000-`) for B2: accept vs accept by the same User, by
  two Users, accept vs revoke in both orders, an unproven acceptance waiting
  for the Organization lock, a concurrent second Membership for the same User,
  and acceptance blocked across the expiry boundary;
- `run_staff_end_access_concurrency.py` (fixture prefix `d0291000-`) races end
  access against end access, and against add, replace and end Responsibility in
  both orders where both orders are meaningful, and proves a Staff read issued
  during an in-flight end is not blocked and sees the whole Member;
- `run_clinic_creation_concurrency.py` (fixture prefix `d0301000-`) races
  same-key creation by two administrators, different keys in one Organization,
  the same key in two Organizations (proved not to wait on each other), and a
  same-key retry after a rolled-back first request;
- `run_edge_invitation_faults.py` copies `supabase/functions` to a temporary
  directory and requires each behavioural mutant of the invite route to fail
  the Deno `organization-invitation` tests. It needs Deno only, never a
  database, network or provider.

Temporal invariant under test. Each top-level statement has one instant
`t = statement_timestamp()`. A Membership or Responsibility Grant is current at
`t` iff `effective_start <= t` and `effective_end is null`. Lifecycle writes
(establish, accept, add, replace, end) record `t` as the effective start/end,
never earlier than the start of what they extend or supersede. A relationship
created earlier in a statement is therefore usable later in the same
statement, and a replacement is contiguous at one instant. Exact boundaries
are deterministic because fixture updates and evaluator calls share one DO
statement; past/future fixtures use day-sized offsets. Structurally storable
future-end fixtures exercise fail-closed Phase 1 currentness; they do not
authorize scheduled termination. Historical provenance and interval coverage
keep their separate semantics. Approved meaning: SPEC-ORG-001 BR-3,
SPEC-ORG-003 BR-5, SPEC-ORG-004 BR-13/BR-18, SPEC-ORG-005 BR-7/BR-25,
SPEC-ORG-006, SPEC-ORG-007 BR-2/BR-5, SPEC-ORG-009 BR-4/BR-5/BR-9 and
SPEC-VET-004 BR-3/BR-18.

The permanent mutation runners share `sql_fault_harness.py`. A mutant counts
as caught only when its named test assertion raises SQLSTATE P0001 from the
designated assertion helper. A survivor, syntax error, wrong assertion,
unexpected operation failure, missing mutation anchor or Docker/psql failure
aborts the run. All suites and candidates execute in rollback-only
transactions; migration source is never rewritten. Unique application names
identify harness sessions; cleanup terminates those sessions on success,
failure or interruption and verifies original public function
definitions/ACLs and public/Auth row counts. The Staff runner additionally
exercises recovery from a simulated interruption while a real backend holds an
uncommitted mutant. Negative unit controls pin evidence classification and
cleanup failures. Each mutation runner verifies zero retained fixture rows.

Subscription Operational Safety (SPEC-SUB-002 §5/§14/§15, SPEC-SUB-003 §15,
SPEC-SUB-004 BR-20, ADR-006 amended):

- `subscription_operational_safety_spec_sub_002_003.sql` — the Phase 1
  transition graph over all 25 state pairs (each reached only through allowed
  operations), `PENDING → EXPIRED` closure, establishment only as
  `PENDING`/`ACTIVE` and never future-dated (with replay and contradictory
  reuse), EXPIRED terminal, no future-dated
  transitions (exact current instant accepted), stale/equal effective times,
  the insert-trigger backstop, source-event and semantic idempotency,
  validity never inherited, open-ended ACTIVE without silent lapse, exact
  Entitlement boundaries (`>=` valid_from, `<` valid_until) for every state,
  a new Subscription period after EXPIRED, the status read (ACL, envelope,
  identical `42501` for unknown and inaccessible Organizations, stored state
  versus Entitlement availability for every case, no provider or internal
  data), and the public/Guardian boundary after Entitlement loss (published
  and discoverable, no candidate times, an empty result identical to an
  entitled Clinic without availability, no commercial state);
- `clinical_amendment_entitlement_continuity_spec_sub_004.sql` — through the
  client edit operation (SPEC-MED-010 BR-23b, stage M5): after `PAST_DUE` and
  `EXPIRED`, the author, still a current Veterinarian, can edit an existing
  Entry (each edit the next version with its own provenance, idempotent,
  `KEY_CONFLICT` on contradictory reuse, the original history unchanged, the
  current version with every earlier one in the Guardian history) while a new
  Entry is refused and every non-Veterinarian, ended, or other-Organization
  caller is rejected;
- `run_subscription_safety_faults.py` — 28 mutants across both suites (graph,
  `PENDING → EXPIRED` removed, `PENDING → CANCELLED` added, establishment
  initial state and future time, candidate read distinguishing Entitlement
  loss, terminal, future, same-state, stale, replay, trigger backstop, Entitlement
  evaluation, validity inheritance, status-read authorization and leakage,
  lapsed-ACTIVE inference, ACLs, public commercial exposure, edit continuity
  — Entitlement wrongly required, the Veterinarian context dropped, the replay
  reconciliation removed — and the new-Entry gate);
- `run_subscription_transition_concurrency.py` — real two-session races
  (prefix `d0312000-`): competing PAST_DUE/CANCELLED in both orders, a
  transition racing an expiry, a duplicate source event, recovery versus
  expiry in both orders, and a `PENDING` closure racing an activation.

Trusted Organization establishment (ADR-009, SPEC-ORG-001 BR-16/§10,
SPEC-SUB-001 §14):

- `trusted_organization_establishment_adr_009.sql` (prefix `d0320000-`) —
  `establish_veterinary_organization` ACL (`service_role` only; anon and
  authenticated denied without writes), the removed
  `create_veterinary_organization`, private helpers; `PENDING`, open-ended
  `ACTIVE` and finite `ACTIVE` establishment with the exact footprint (one
  Organization, Membership, `OWNER` Grant, Subscription, requested provider
  references; no Clinic, other responsibility, Profile or Invitation); one
  establishment instant for Membership, Grant and Subscription; Owner identity
  and BR-16 eligibility (missing User, incoherent mapping, unconfirmed,
  deleted, anonymous, currently banned, a ban ending exactly at `t` accepted
  and one microsecond later rejected, no Profile needed); input shape and
  initial-state/future-time policy; exact replay (lost-response retry,
  normalized name, reordered and empty provider references, after a later
  transition) and contradictory reuse of every material input, including
  explicit versus omitted initial effective time and a key already used by a
  later-period Subscription; provider-reference replay of
  `establish_organization_subscription`; several Organizations per Owner and
  duplicate names; legacy Organizations untouched; establishment record
  immutability; and an injected failure after the Organization, Membership and
  Grant and during the Subscription and provider references, each leaving
  nothing;
- `run_trusted_establishment_faults.py` — 25 mutants (Organization
  idempotency removed, display-name anchor, Subscription or `OWNER` Grant
  omitted with and without deferred-invariant surfacing, each eligibility rule,
  ban boundary, future time, initial state, incomplete fingerprint, provider
  references ignored, resolved-default fingerprint, contradictory replay,
  replay reporting `ESTABLISHED`, shared-key detection, establishment instant,
  partial footprint surviving, later-period reference replay, record
  mutability, the former boundary restored, and ACLs);
- `run_trusted_establishment_concurrency.py` — real two-session races (prefix
  `d0321000-`): identical establishment, same key with a different Owner,
  display name, Subscription facts or provider references, different keys for
  the same Owner (proved not to wait), and a same-key retry after a
  rolled-back first request.

Staff Responsibility Editing + Veterinarian Enablement Phase 1 (SPEC-ORG-006
§14/§15, SPEC-ORG-009 BR-1, SPEC-ORG-002 BR-17, SPEC-VET-001 §13/§14,
SPEC-VET-004/005 §13/§14, SPEC-VET-006):

- `staff_responsibility_management_spec_org_006.sql` (prefix `d0330000-`) —
  the client-safe `add_/replace_/end_staff_responsibility`: contracts and
  ACLs (authenticated only; every generic Responsibility, Assignment and
  Profile writer withdrawn from clients and kept for `service_role`; private
  predicates executable by no role), the uniform `42501` for every caller
  without `ORGANIZATION_GRANT_RESPONSIBILITIES` and for unknown, NULL and
  other-Organization Organizations and targets before any input or lifecycle
  fact, `INVALID_SCOPE` / `INVALID_CLINIC` (OWNER, Clinic-scoped VETERINARIAN),
  Add with `ALREADY_PRESENT`, Change of exactly one Grant of a multi-Grant
  Member (Clinic A → B, Clinic → Organization, role + Organization → Clinic)
  with unrelated Grants byte-identical, `DUPLICATE` and `NO_OP`,
  `ALREADY_CHANGED` replay versus a stale `GRANT_ENDED`, End with
  `ALREADY_ENDED`, OWNER Grants and other actors' Owner Memberships protected
  while the Owner manages their own non-OWNER Grants, a non-Owner's self Add
  allowed and self Change/End denied, `LAST_RESPONSIBILITY` (Change of the
  last Grant allowed), `VETERINARIAN_ASSIGNMENTS_ACTIVE` until the Clinic
  Assignment is ended, `MEMBERSHIP_INACTIVE`, same-statement authority loss,
  the real authenticated role, no path around the operations, and
  Organization/Membership lock evidence (`pgrowlocks`);
- `veterinarian_profile_self_service_spec_vet_001.sql` (prefix `d0331000-`) —
  `create_my_veterinarian_professional_profile`: contract (no User
  parameter), authentication, verified account, blank inputs, `CREATED` with a
  normalized Credential, exact and whitespace-only replay `ALREADY_EXISTS`
  with the same ids, `PROFILE_CREDENTIAL_MISMATCH` (identifier, context, case)
  without overwrite, a pre-existing Profile, per-User isolation, no
  Membership/Grant/Assignment written, the generic writer unreachable, and the
  `For Update` lock on the acting User (a Profile foreign key alone only takes
  `For Key Share`);
- `veterinarian_workforce_assignment_spec_vet_004_005_006.sql` (prefix
  `d0332000-`) — the workforce read (authorization matrix, unknown/other
  Organization parity, exact envelope and Member/Assignment fields, Profile
  pending/present, current-only Assignments, a stale Assignment after
  VETERINARIAN ended still listed, ended Members absent, no credential,
  Profile, User or Auth id, email or other-Organization Clinic, Organization
  isolation, no writes) and `assign_/end_staff_veterinarian_clinic_assignment`
  (fail-closed authorization before prerequisites, Clinic-scoped
  Administrator only at its Clinic, prerequisites `PROFILE_REQUIRED`,
  `VETERINARIAN_RESPONSIBILITY_REQUIRED`, `MEMBERSHIP_INACTIVE`, server-derived
  Profile, statement-instant start/end, `ALREADY_ASSIGNED`, several Clinics,
  `ALREADY_ENDED` including historical rows, cleanup of stale and
  ended-Membership Assignments, a new period on return, no other row touched,
  lock evidence, generic operations unreachable);
- `veterinarian_enablement_capability_chain.sql` (prefix `d0333000-`) — invite
  directly as Organization-scoped VETERINARIAN (Clinic-scoped rejected),
  acceptance creating no Profile or Assignment, Profile pending in the
  workforce read and blocking Assignment, then the full chain Membership →
  + VETERINARIAN → + Profile → + A1 → + A2 → blocked VETERINARIAN end → end A1
  → end A2 → end VETERINARIAN → re-add → re-assign → End access, checking the
  four Veterinarian-derived capabilities and the clinical context resolver at
  each step, a legacy Assignment without VETERINARIAN granting nothing
  clinical, and no Appointment, Appointment Veterinarian Assignment,
  Availability or clinical row created or required;
- `run_staff_workforce_faults.py` — 45 mutants across those four suites
  (authorization ordering, cross-Organization targets, unrelated Grants ended,
  OWNER and Owner-Membership protection, self-demotion, last Grant,
  VETERINARIAN Clinic scope, VETERINARIAN end with or cascading over
  Assignments, stale Change and replay reconciliation, ACLs, Profile for
  another User, credential replay leniency, verification, serialization,
  workforce leakage and listing, Assignment prerequisites, client Profile id,
  wrong Organization/Clinic, ended relations treated current, clock instants,
  cleanup blocked, history rewritten, and capability without VETERINARIAN or a
  current Assignment);
- `run_staff_workforce_concurrency.py` (prefix `d0334000-`) — real two-session
  races: Add vs Add, Change vs End, Change vs Change (different and identical
  targets), Assign vs Assign, Assign vs Membership end in both orders,
  VETERINARIAN end vs Assign in both orders, End Assignment vs re-Assign, and
  Profile create vs create; a deadlock would surface as `40P01` and fail the
  exact outcome checks.

`organization_staff_spec_org_009.sql` and `run_organization_staff_faults.py`
also pin the per-Grant `responsibility_grant_id` (the Staff read definition is
now taken from the workforce migration). `professional_authority_create_then_act.sql`
uses the client-safe Responsibility, Profile and Assignment operations, so the
temporal writer mutants still reach the shared writers.

Appointment-owned clinical documentation (SPEC-MED-010 §12, SPEC-MED-004 §15
under BR-18, SPEC-APT-012 BR-48; migration
`20261113090000_appointment_owned_clinical_documentation.sql`, which retired
Clinical Encounter, Drafts and separate finalization and replaced
`minimal_clinical_record_spec_med_001_009.sql`,
`clinical_encounter_after_completion_spec_med_001.sql` and
`run_clinical_record_faults.py`):

- `appointment_clinical_record_spec_med_010.sql` (prefix `d0400000-`) — the
  Appointment-keyed client operations under the real authenticated role, for
  Verification Notes 1–12 and 14–25 (Note 13, completion ending the Care
  Authorization, belongs to stage M3): contracts and ACLs, every retired
  Encounter, Draft and Finalize operation absent, private helpers and trusted
  writers withheld; "Guardar registro" on CONFIRMED (before and after
  the scheduled start) and COMPLETED Appointments with authorship, normalized
  content and only the server recording time (no event time can be sent since
  stage M5); every field rule and `KEY_REQUIRED`; idempotency (`ALREADY_CREATED`, `KEY_CONFLICT` for
  other facts or another Appointment, distinct keys); `APPOINTMENT_STATE_INVALID`
  for REQUESTED, CANCELLED, NO_SHOW, EXPIRED and never-confirmed Appointments,
  also structurally on direct insertion; immutable, undeletable Entries;
  `NOT_ASSIGNED_VETERINARIAN` / `NO_VETERINARIAN_ASSIGNED`, the uniform `42501`
  for every other actor and target, a stale assignee refused; reassignment
  keeping authorship and the exact replay; the read (mine/another authorship,
  no internal ids, one audit event per read, none without Entries, one DENIED
  event per denied read, advisory state, each Entry in its current version
  with `may_edit`); author-only edits (`ENTRY_AUTHOR_REQUIRED`,
  `STALE_VERSION`, append-only versions); documentation access unchanged by
  revocation and completion while prior history is denied there;
  non-attendance blocks, completion with Entries, the Reschedule Proposal
  voided with `CLINICAL_DOCUMENTATION_STARTED`; Guardian and longitudinal
  history provenance and ordering (a historical event time still orders the
  history), including Entries of revoked and completed Appointments; the
  schedule flag without audit; author-only Attachments (PENDING hidden,
  AVAILABLE immutable); the `CLINICAL_CARE` gate for every new Entry while
  replays, edits and reads continue;
- `run_appointment_clinical_record_faults.py` — 70 mutants built from the
  deployed definitions (authority after existence, other-Clinic Appointments,
  key and field rules, a stamped event time, normalization of the content and
  the OTHER context, extra result fields, recording
  audited, reconciliation and digest scope (Appointment, category),
  documentable state in the
  operation and structurally, never-confirmed Appointments, assignee and
  NO_VETERINARIAN outcomes, the `CLINICAL_CARE` gate for every and for later
  Entries and for Attachments, mutable or deletable Entries, provider context,
  author-only edits and Attachments in the operations and triggers, a stale
  version accepted, AVAILABLE Attachments mutable, the read's other-Clinic leak,
  denied/empty/per-Entry audit, id leak, may_edit for everyone, other
  Appointments' Entries, dependence on the Care Authorization, advisory state,
  cancellation/no-show blocks, proposal invalidation, the schedule flag, prior
  history opened by completion, revocation or documentation access, history
  filtered by authorization state or ordered by recording time, and client
  ACLs, retired operations — Encounter, the timed record operation and the
  reason-and-addition operations reappearing — the Encounter table, the
  creation key, the NOT NULL Appointment reference and the dropped triggers);
- `run_clinical_record_concurrency.py` (prefix `d0341000-`) — 14 real
  two-session races and 2 non-blocking overlaps: save vs save (same key, other
  key, two Veterinarians), save vs cancellation, no-show and completion in both
  orders, save vs reassignment in both orders, reassignment vs the exact
  replay, save with Guardian revocation in both orders (neither waits), save vs
  the assignee's Assignment end, the former assignee afterwards, followed by a
  coherence check (no Entry on a cancelled or no-show Appointment, every Entry
  recorded by the assignee of its instant).
- `run_appointment_clinical_record_migration_guard.py` — LOCAL only and
  destructive for LOCAL: resets to `20261112090000`, plants one row for each
  of the 14 guard criteria (Encounter, Draft and finalized Entries, Amendment,
  Attachment, contributor, Encounter/Entry/Attachment-referencing and retired
  operation audit events, a Lifecycle Event referencing an Encounter, a
  proposal voided by an Encounter), requires the `55000` refusal with the
  pre-M2 schema intact after each rolled-back attempt, checks that a clean
  database accepts the body, and then applies M2 with `migration up --local`.
  Run it before the clean reset of the list above.
- Completion ends the Care Authorization (stage M3, migration
  `20261114090000_appointment_completion_ends_care_authorization.sql`,
  SPEC-MED-010 BR-16): `appointment_completion_spec_apt_009.sql` cases 67–75
  (ACTIVE ended with `APPOINTMENT_COMPLETED` at the completion Event time,
  REVOKED kept with its history, retry after a lost response writes nothing,
  rejected completions keep ACTIVE, a later Guardian revocation is
  `ALREADY_INACTIVE`, structural coherence and immutability), and
  `appointment_clinical_record_spec_med_010.sql` Note 13 with reading,
  recording and editing after completion; `run_appointment_completion_care_authorization_faults.py`
  — 9 mutants (operation paired with its backstop: ACTIVE left, wrong time,
  wrong context, revocation rewritten; each backstop alone; the ending-context
  constraint); `run_care_authorization_revocation_concurrency.py` adds
  complete vs revoke in both orders and complete vs repeated complete;
  `run_appointment_completion_care_authorization_migration_guard.py` (LOCAL
  only, resets to `20261113090000`) verifies the reconciliation (only ACTIVE
  authorizations of COMPLETED Appointments end, at their completion times) and
  5 refused unexpected states, then applies M3.
- Professional Attachment routes retired (stage M4, migration
  `20261115090000_retire_professional_attachment_routes.sql`, SPEC-MED-010
  BR-19/BR-25): `clinical_attachments_slice13_corrections.sql` (prefix
  `13000000-`) covers the Guardian authorizer — exact PERMITTED result and one
  Guardian audit, DENIED for a Guardian of another Pet who is also a
  Veterinarian of the Entry's Clinic, for an ended Guardianship, for PENDING
  (even with a stored object), REJECTED and unknown Attachments, the
  missing-object `XX001`, `28000` for an unknown subject — and that the retired
  operations exist under no signature; `appointment_clinical_record_spec_med_010.sql`
  §11 keeps the structural Attachment rules (Note 20).
  `run_guardian_attachment_download_faults.py` — 12 mutants (another Pet's
  Guardianship, paired with the audit backstop that otherwise rejects it;
  ended Guardianship; PENDING released; no audit; Guardianship provenance
  dropped; Entry id leaked; missing object released; grant to
  `authenticated`; a professional overload; each retired operation
  reappearing). `run_edge_clinical_attachment_faults.py` copies
  `supabase/functions` (with `config.toml` and the migrations the parity tests
  read) to a temporary directory and requires each of 9 mutants of the route
  table or the Guardian route — a retired route back, case-insensitive,
  query-string or substring matching, a client Care Authorization, Clinic or
  Encounter forwarded, the retired authorizer called — to fail the Deno
  `clinical-attachments` tests. It needs Deno only.
- Editable Entries with preserved versions (stage M5, migration
  `20261116090000_editable_clinical_record_versions.sql`, SPEC-MED-010 BR-5,
  BR-18, BR-20, BR-22, BR-23b, BR-25). An edit appends one Clinical Amendment of
  kind `EDIT` carrying the complete next version; nothing is overwritten.
  `clinical_amendments_spec_med_004.sql` (prefix `d0350000-`, rewritten for the
  edit contract) — contract and ACL (the edit operation SECURITY DEFINER,
  VOLATILE, authenticated-only, one signature; the version helpers internal;
  the reason-and-addition operations absent for every role); the
  typing-error example (a Vaccination edited to a Clinical note: next version
  at the server time with its own provenance, the Entry, its Appointment,
  assignment and Care Authorization unchanged, the read showing the current
  version, the original recording time and the earlier version); another
  Veterinarian `ENTRY_AUTHOR_REQUIRED`; exact and whitespace-variant replay
  `ALREADY_EDITED`, also after later edits; `KEY_CONFLICT` for other content,
  category, version or Entry without echoing the key; `STALE_VERSION` for an
  earlier or unknown version without echoing content; `UNCHANGED`; three
  successive gapless versions; two edits of the same version; uniform
  refusals for every other actor, Clinic, Organization and target, before any
  request check; every request rule with its hint; CONFIRMED and COMPLETED
  Appointments, Guardian revocation and an ENDED authorization; edits leak
  nothing and create no audit; offboarded authors refused; reassignment (the
  author keeps editing, the new assignee clarifies with an Entry of their own);
  the record read (exact keys, no identifiers, earlier versions oldest first,
  one audit per read, authorship relative to the reader, the history visible
  exactly to those who may read the record, a historical ADDENDUM still shown
  and never a version); the Guardian history (current version, every earlier
  one, original order); Entitlement lapse; immutability and structure (only
  the author's next EDIT version, no gap or duplicate, no ADDENDUM, no Entry
  with an event time, no client write).
  `run_clinical_amendment_faults.py` — 48 mutants (authority and target scope,
  the author rule alone and with its backstop, the Entry overwritten,
  provenance, normalization of content and OTHER context, Appointment state,
  Care Authorization and Entitlement wrongly required, replay reconciliation
  removed or ignoring the version, key conflicts ignored, key, version and field
  rules removed, stale and newer versions accepted, unchanged saves written,
  the read hiding the Entry, showing the original, omitting earlier versions,
  edit or recording time, may_edit for everyone, author id leaked, per-version
  audit, the version helpers dropping edits, including the current version or
  reversing the order, versions listed as legacy corrections, the Guardian page
  showing the original or reordered by edit time, versions deletable or
  updatable, ADDENDUM rows writable, version gaps, the author backstop, Entries
  with an event time, and six ACL or reappearance faults).
  `run_clinical_amendment_concurrency.py` (prefix `d0352000-`) — same key/same
  request (`EDITED` then `ALREADY_EDITED`), same key/conflicting request
  (`KEY_CONFLICT`), two edits opened on the same version (one `EDITED`, the
  other waits on the Entry lock and is `STALE_VERSION`), author vs another
  Veterinarian, Subscription lapse vs edit, Guardian revoke with edit in both
  orders (neither waits), author offboarding vs own edit, edit vs own
  Assignment end, followed by a coherence check (original Entries unchanged,
  gapless versions, no duplicated intent, every version by its author).
  `run_editable_clinical_record_versions_migration_guard.py` — LOCAL only and
  destructive for LOCAL: resets to `20261115090000`, runs the M5 body over an
  Entry recorded with an event time and the author's historical Amendment
  (both kept unchanged; the Amendment becomes a legacy `ADDENDUM`, never a
  version), requires the `55000` refusal for a historical Amendment by someone
  other than the author and for a missing M4 contract with the M4 schema
  intact, accepts a clean body, and then applies M5 with `migration up
  --local`. Run it before the clean reset of the list above. The revocation,
  professional history and Subscription continuity suites and their runners
  call the edit operation where they called the Amendment operations.

Professional Longitudinal / Cross-Clinic Medical History Phase 1
(SPEC-MED-005 §15/§16, SPEC-ID-006 BR-41, SPEC-ACC-003 BR-49/BR-55):

- `professional_medical_history_spec_med_005.sql` (prefix `d0360000-`) —
  `view_appointment_professional_medical_history` and the rebuilt Guardian
  read under the real authenticated role, with a historical record of three
  Clinics in two Organizations loaded as data: contract and ACL (one
  signature, SECURITY DEFINER, VOLATILE, authenticated-only; the shared
  projection, display-name and window helpers private; the legacy Pet-keyed
  read no longer client-executable; the old private Guardian chain dropped;
  a structural pin that the read requires `CLINICAL_CARE`, not
  `CLINICAL_DOCUMENTATION`); the window — future `REQUESTED`, `CONFIRMED`
  pre-care and an `ACTIVE` Encounter permitted, a passed `REQUESTED` start,
  `CONCLUDED` (also with `COMPLETED`), `COMPLETED` without Encounter, `REVOKED`
  before care and during an `ACTIVE` Encounter, and `ENDED` denied, a
  retrospective Encounter gaining history while `ACTIVE` and losing it once
  concluded; the uniform `{"status":"DENIED"}` for Receptionist,
  Administrator, Owner, Guardian, an ended Clinic Assignment, an offboarded
  Veterinarian, another Organization, another Clinic of the same Organization,
  a dual-Clinic Veterinarian acting through the wrong Clinic, unknown Clinic,
  unknown Appointment and an Appointment of another Clinic; argument-shape
  hints; no Appointment Assignment or Veterinarian Availability needed; the
  complete cross-Clinic content (A + B + C, no Draft, no Draft-only Encounter,
  no other Pet), names surviving unpublication and a REVOKED old Authorization,
  the same content through any permitted Appointment or Clinic, chronology by
  event time else Encounter start (never finalization), deterministic
  tie-break, `is_this_appointment`; the exact key allow-list and no identifier
  other than Entry and Amendment ids, and since M5 each Entry in its current
  version with `version`, `edited_at` and every earlier version; provenance (offboarded author keeps her
  name, distinct finalizer, blank or missing name `null`, `is_me` relative to
  the reader, rename shows the current name, each Amendment's own author);
  keyset pages without duplicates or skips, the limit cap, a cursor granting
  nothing in a closed window, an edit between pages (current version shown,
  original kept, order unchanged); exactly one audit
  event per page with the current access context, `DENIED` audited for a
  closed window and an unauthorized actor, none for an unknown or foreign
  Appointment; reads change nothing; the Guardian payload (same Entries and
  order, exact keys, no identifier, no Veterinarian name, content,
  Amendments, names, Attachments and cursor unchanged); Entitlement lapse
  denying history also during an `ACTIVE` Encounter while its own record and
  Guardian history stay;
- `run_professional_history_faults.py` — 37 mutants (existence before
  authority, distinct denial for an unknown target, Care Authorization widened
  across Clinics, current-Clinic and current-Organization content filters,
  REVOKED / ENDED / CONCLUDED / COMPLETED-without-Encounter allowed, the
  requested start ignored, Entitlement omitted, `CLINICAL_DOCUMENTATION` used,
  Appointment Assignment or Availability required, User and Assignment ids
  leaked, offboarded author's name lost, finalizer as author, wrong Amendment
  author, Amendments omitted, original hidden after correction, ordering by
  finalization, Draft and other-Pet leaks, cursor ignored, audit removed,
  per-Entry audit, denial recorded as permitted, Guardian id and Veterinarian
  name leaks, the original version shown instead of the current one, earlier
  versions omitted from the professional and the Guardian reads, and three
  ACLs);
- `run_professional_history_concurrency.py` (prefix `d0362000-`) — 9 real
  two-session races: history read vs Guardian revoke in both orders, read vs
  the reader's own Assignment end in both orders, read vs edit in both
  orders, read vs a new recorded Entry in both orders, and load more vs an
  edit; every result is a complete coherent page or exactly `DENIED`, never a
  version without its Entry or a partial version history, no duplicate or
  skipped Entry.

`run_appointment_clinical_record_faults.py` and `run_clinical_amendment_faults.py`
mutate the shared projection (`clinical_history_page`,
`clinical_history_amendments`) for their Guardian mutants. Since
`20261113090000` every clinical mutation runner builds its mutants from the
deployed definitions, and the legacy Pet-keyed read no longer exists.

Guardian Appointment Medical Access Revocation Phase 1 (SPEC-ACC-002 §16/§17,
SPEC-APT-011 BR-35):

- `guardian_appointment_medical_access_revocation_spec_acc_002.sql` (prefix
  `d0370000-`) — `revoke_my_appointment_care_authorization` and the extended
  Guardian read under the real authenticated role: contract and ACL (one
  signature, SECURITY DEFINER, VOLATILE, authenticated-only; the generic
  `revoke_pet_care_authorization` / `revoke_appointment_care_authorization`
  and the deferred `CLINICAL_INTAKE` `grant_pet_care_authorization` no longer
  client-executable, `service_role` keeping them; `medical_access_state` last in
  the Guardian read with its ACL unchanged and absent from the Clinic
  schedule); `ACTIVE` in every lifecycle before revocation for every current
  Guardian; one uniform `42501` with no hint for another Pet's Guardian, a
  former Guardian, Receptionist, Veterinarian and Administrator, an unknown
  and a foreign Appointment, with nothing written; `28000` and the
  `INVALID_APPOINTMENT` shape check; revocation by the Appointment alone
  (`REVOKED`, actor and time, no reason, only the outcome in the result) with
  the Appointment, schedule and lifecycle history unchanged; `REQUESTED`,
  `CONFIRMED` before and after its start and `COMPLETED` revocable, also by
  the co-Guardian; no Encounter and no pre-care history afterwards; exact
  retry, second Guardian, cancellation, no-show and expiry reconciling to
  `ALREADY_INACTIVE` with the authorization row unchanged; a later
  cancellation keeping the revocation; the Guardian read `REVOKED` /
  `INACTIVE` with no authorization id; clinical effects — no Encounter, Entry,
  Draft, Amendment or audit event changed by revocation, longitudinal history
  denied before care and during an `ACTIVE` Encounter, the `ACTIVE`
  Encounter's own read, Draft update, Finalize, Amendment and Conclude still
  working, then its record and client Amendments denied once concluded,
  already `CONCLUDED` Encounters (`CONFIRMED` and `COMPLETED`) denied, and the
  Guardian's medical history keeping every finalized Entry;
- `run_care_authorization_revocation_faults.py` — 22 mutants (existence before
  authority, foreign and former Guardian accepted, Appointment cancelled
  during revoke, revocation reported but not written, Care Authorization id in
  the result and in the Guardian read, replay raising, `ENDED` not reconciled,
  Draft deleted, Draft rewritten, `ACTIVE` Encounter aborted, revocation hidden
  in the read, `ACTIVE` Encounter continuity blocked, `CONCLUDED` record
  readable, client Amendment allowed after conclusion and revocation,
  professional history readable after revocation, and five ACLs);
- `run_care_authorization_revocation_concurrency.py` (prefix `d0372000-`) — 16
  real two-session races, each pair in both orders: revoke vs professional
  history read, vs Draft update during an `ACTIVE` Encounter, vs post-care
  Amendment, vs Clinic cancellation, vs the same Guardian's cancellation, vs
  `NO_SHOW`, vs request expiry, and two simultaneous revocations (two
  Guardians; one Guardian twice); one coherent terminal history each, one
  Lifecycle Event per transition, no resurrection, no deadlock, finalized
  record unchanged.

Callers migrated: the MED-001 after-completion, Minimal Clinical Record,
Amendment and Professional history suites revoke through the new client
operation; four suites pin the extended `get_pet_appointments` signature;
`appointment_request_expiry_spec_apt_015.sql` grants its Clinical Intake
authorization as the owner. The existing race runners keep calling the generic
revoke as the local superuser, which is unaffected by the withdrawn client
grant.

Paged Guardian Appointment reads Phase 1 (SPEC-APT-011 §13/§14, Punto 9):

- `guardian_appointment_paged_reads_spec_apt_011.sql` (prefix `d0130000-`) —
  `get_guardian_active_appointments` and `get_guardian_appointment_history`
  (VN 38–46): contract and ACL (exact columns, SECURITY DEFINER, STABLE,
  authenticated-only; the internal projection executable by no client;
  `get_pet_appointments` unchanged); `28000` before validation and `22023` for
  limits, partial cursors and unknown Active ranks; an oracle equal to the
  union of `get_pet_appointments` over the caller's currently guarded Pets,
  page by page for every page size 1–22 (primary Guardian, co-Guardian, former
  Guardian, unrelated Guardian, no Guardianship); tab membership for every
  state, including `CONFIRMED`/`REQUESTED` with a reached start; Active order
  (future ascending, then reached descending) and History order with ties;
  exact 20 + 1 and exactly-full-then-empty pages; latest-revision intervals and
  establishment timezones unconverted; Clinic proposals on both bases, a
  Guardian proposal, a lapsed proposal; no private column; changes between
  pages (cancelled, completed, Guardianship ended) never repeated; no writes;
  the real authenticated role; and a 3 300 / 23 300 Appointment volume check
  (~3–5 ms per first or deep page, no new index);
- `run_guardian_appointment_paged_reads_faults.py` — 16 mutants (authentication
  skipped, unknown rank and partial cursor accepted, Guardianship owner
  ignored in each read, ended Guardianships kept, a terminal state in Active,
  ranking and projecting the first revision, each tie-breaker dropped, started
  rows cut oldest first, a non-actionable proposal projected, and two ACLs);
  since `20261118090000` it builds its mutants from that migration, which
  re-created the three functions, and the oracle includes
  `awaiting_clinic_confirmation` (BR-33 on `get_pet_appointments`);
- `guardian_appointment_awaiting_confirmation_spec_apt_011_019.sql` (prefix
  `d0140000-`) — `awaiting_clinic_confirmation` (SPEC-APT-011 VN 47–50,
  SPEC-APT-019 §5) through the real trusted operations as `authenticated`, for
  both current Guardians and against the `get_pet_appointments` oracle: false
  for a plain request, a pending Clinic alternative and a withdrawn one; true
  after either Guardian accepts; both signals when a new Clinic alternative
  follows an accepted one, kept after withdrawing or accepting it; false after
  Clinic confirmation, a Guardian reschedule, Guardian and Clinic
  cancellation, expiry, and for an accepted Clinic reschedule of a `CONFIRMED`
  Appointment; never in History;
- `run_guardian_appointment_awaiting_confirmation_faults.py` — 5 mutants
  (awaiting whatever the state, for every request, while a Clinic proposal is
  pending, never, and from the first revision).

Organization Professional Clinics page Phase 1 (SPEC-ORG-008 §11/§12, Punto 10):

- `organization_professional_clinics_page_spec_org_008.sql` (prefix
  `d0150000-`) — `get_my_organization_professional_clinics` (VN 24–37):
  contract and ACL (one STABLE SECURITY DEFINER overload, authenticated
  only, not `service_role`; the search helper executable by no client);
  delegation to `user_has_clinic_capability` with no role or capability
  literal; the three authoritative predicates and
  `get_my_professional_clinics()` pinned by fingerprint (a change to the
  predicates must re-review the BR-21 candidate bound); `28000` before
  validation and `22023` identical for every Organization; an oracle equal to
  the ORG-008 result restricted to the Organization, page by page for every
  page size, for 21 actors (every role and scope, ended, pending,
  not-yet-started, multi-Organization) and every Organization, including
  unknown and `null`; completeness per inclusion basis; isolation; cursors
  that name non-included Clinics or come from another search; ties, unnamed
  Clinics last and cursor boundaries; the search applied before the limit,
  with search parity for 29 terms at every page size; literal normalization
  and matching expectations (accents, `ñ`, Unicode uppercase, ligatures,
  full-width, Unicode spaces, NFKD, `%` `_` `\` `[` literal, the documented
  limits), also under collation `"C"` and libc; renames, ended grants and new
  Clinics between pages; no writes; and a 3 000-Clinic volume check for an
  Owner, an Organization-scoped and a Clinic-scoped Receptionist, a
  Veterinarian and a non-member (≤ ~20 ms per first, deep or search page, no
  new index);
- `run_organization_professional_clinics_page_faults.py` — 30 mutants
  (authentication, every validation bound, raising for an inaccessible
  Organization, the Organization filter, inclusion without the predicate, an
  Organization-scoped-only shortcut, each candidate-bound branch dropped or
  tightened, the search ignored, unnamed Clinics matching, LIKE patterns, each
  cursor and order rule, an over-long page, each normalization step, and three
  grants).

Search Published Clinics by Name Phase 1 (SPEC-DIS-004):

- `published_clinic_name_search_spec_dis_004.sql` (prefix `d1040000-`) —
  `discover_published_clinics` (VN 1–11): contract and ACL (one STABLE
  SECURITY DEFINER overload, granted like every Discovery read; the
  normalization helper executable by no client; no table privilege; the basic
  Discovery view, `professional_clinic_search_key` and every existing
  Discovery read pinned by fingerprint); independence (no identity,
  professional helper, per-Clinic read, lock or write); `22023` for every
  invalid input, identical for anon and authenticated; an oracle built from
  `published_clinic_public_profiles` and `get_published_clinic_location`,
  page by page for every page size, for anon, a Guardian, an Organization
  Owner and a subject without a domain User, and 12 searches; addresses only
  from published Locations, `null` without one, equal to the Map read's;
  identical names, unnamed Clinics last and cursor boundaries; cursors naming
  unpublished, unknown or profile-less Clinics; literal normalization and
  matching (accents, `ñ`, Unicode uppercase, ligatures, full-width, Unicode
  spaces, `%` `_` `\` `[` literal, description, address and Organization not
  searched), also under collation `"C"` and libc, and equality with the
  SPEC-ORG-008 normalization; unpublishing, publishing, new Clinics, renames,
  Location and description changes between pages; no writes; and a
  6 000-Clinic volume check (5 000 published) with full traversals equal to
  the oracle and single pages within 250 ms (~1–2 ms unsearched, ~22 ms
  searched in LOCAL, no new index);
- `run_published_clinic_name_search_faults.py` — 35 mutants (every validation
  bound, unpublished or profile-less Clinics, an inner Location join, caller-
  or identity-dependent results, a per-Clinic address read, the search
  ignored, unnamed Clinics matching, the description searched, LIKE patterns,
  each cursor and order rule, the probe row, `has_more` and the next cursor,
  each normalization step, four grants and a table privilege).

`supabase/provisioning/subscription_inventory_readonly.sql` is a read-only
operational diagnostic, not a regression suite.

These fixtures bypass establishment triggers only for controlled setup, and
therefore require the repository's local privileged database context. Do not
run them against shared databases.

---

## 26. Related Requirements

This strategy primarily supports:

- REQ-NFR-003 — Data integrity
- REQ-NFR-004 — Medical history durability
- REQ-NFR-005 — Auditability
- REQ-NFR-008 — Automated verification
- REQ-NFR-009 — Migration-based database evolution

It also supports verification of all approved functional Requirements and
Specifications.

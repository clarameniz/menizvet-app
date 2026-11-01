# SPEC-APT-009 — Complete Appointment

**Status:** APPROVED  
**Requirements:** REQ-APT-005, REQ-APT-006, REQ-APT-008  
**Domain:** Appointments  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): completion ends the `ACTIVE` Appointment-derived Care Authorization with `APPOINTMENT_COMPLETED` at the completion time (SPEC-MED-010 BR-16), replacing BR-14, BR-21, §4 step 9 ("no step reads or writes a Care Authorization"), and Verification Note 18. BR-12–BR-15 and §7 read as Clinical Record Entries, which neither block nor depend on completion; documentation after completion has no care-start bound. Legacy Encounter references on completion Lifecycle Events are removed (BR-15). BR-19 is superseded for Veterinarian assignment: a `COMPLETED` Appointment may be assigned or reassigned to document the care (SPEC-APT-007 §13); completion still requires no assignment. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Clinic actor to mark a confirmed Appointment as `COMPLETED`
once its scheduled start has been reached.

Completion is the Clinic's administrative assertion that the scheduled visit
occurred.

It is a lifecycle resolution of the Appointment, not a clinical statement.
It deliberately requires no clinical tooling: a Clinic that uses the platform
only for Guardian-facing scheduling and communication must be able to resolve
its Appointments without assigning a Veterinarian, opening a Clinical
Encounter, or recording clinical documentation.

The following core lifecycle is valid on its own:

    REQUESTED
        ↓ confirm
    CONFIRMED
        ↓ complete
    COMPLETED

with no Veterinarian Assignment, no Clinical Encounter, and no clinical report.

Optional clinical tooling remains independent of completion and keeps its own
strict rules (`SPEC-MED-001`).

Appointment completion must not:

- create, require, consume, or conclude a Clinical Encounter;
- create or finalize clinical documentation;
- delete the Appointment;
- rewrite previous scheduling history;
- erase Veterinarian Assignment history.

---

## 2. Preconditions

- The Appointment exists.
- The Appointment is currently `CONFIRMED`.
- The Appointment belongs to a Pet.
- The Appointment belongs to a Clinic.
- The scheduled start of the Appointment's latest confirmed scheduling context
  has been reached (BR-7).
- The caller identifies the confirmed scheduling context it reviewed, by its
  schedule revision sequence, and that context is still the Appointment's
  latest confirmed scheduling context (BR-8).
- The acting User exists.
- The acting User is authenticated.
- The acting User has current authorization to manage Appointment completion
  for the relevant Clinic (`APPOINTMENT_COMPLETE`).

No Veterinarian Assignment, Clinical Encounter, clinical documentation, or
professional Entitlement is a precondition.

---

## 3. Business Rules

### BR-1 — Completion is the Clinic's assertion that the visit occurred

An Appointment becomes `COMPLETED` when an authorized Clinic actor asserts that
the scheduled visit took place.

The assertion is administrative. It records the Appointment outcome; it does
not record what veterinary care was provided. Clinical truth, where the Clinic
chooses to record it, belongs to the Clinical Encounter and Clinical Record
(`SPEC-MED-001`).

Completion must not be used merely because:

- the scheduled time passed;
- the Appointment was confirmed;
- a Veterinarian was assigned;
- the Clinic wishes to remove the Appointment from its active schedule.

If the Pet did not attend, the applicable outcome is `NO_SHOW`
(`SPEC-APT-010`), not `COMPLETED`.

---

### BR-2 — Completion requires no clinical tooling

Completion must not require:

- a current or historical Veterinarian Assignment;
- a Clinical Encounter;
- a Clinical Record Entry, diagnosis, note, report, or any other clinical
  content;
- the identity of any Veterinarian.

The absence of any of these must not prevent, delay, or alter completion.

---

### BR-3 — Only authorized Clinic actors may complete an Appointment

Completion is a Clinic-context operation.

The acting User must have the current responsibility-derived
`APPOINTMENT_COMPLETE` capability at the Appointment's Clinic
(`SPEC-ORG-005`).

Authentication or Organization Membership alone is insufficient.

Capabilities in another Clinic or Organization do not authorize completion.

---

### BR-4 — Guardian cannot complete an Appointment

A Guardian must not mark their own Pet's Appointment as completed.

Guardian participation in the Appointment does not establish Clinic
operational authority.

---

### BR-5 — Veterinarian status alone does not grant completion authority

A Veterinarian Professional Profile, Clinic Assignment, or Appointment
Veterinarian Assignment alone must not allow a User to complete an
Appointment.

The User must hold `APPOINTMENT_COMPLETE` through their current
responsibilities.

---

### BR-6 — Completion has no commercial Entitlement gate

Completion resolves an existing confirmed obligation. It must not require a
professional Entitlement.

An authorized Clinic actor may therefore complete an existing `CONFIRMED`
Appointment after the Organization has lost normal professional Entitlement,
where doing so accurately records that the visit occurred
(`SPEC-SUB-004` safe resolution).

Completion must not authorize new paid professional activity.

---

### BR-7 — Completion is permitted from the latest confirmed start

An Appointment may be completed only once the scheduled start of its latest
confirmed scheduling context has been reached, according to authoritative
backend time:

- before that start, the operation is rejected;
- at that start, it is permitted;
- after that start, it is permitted.

The scheduled end is not a requirement.

The start is taken from the very confirmed Schedule Revision that passed the
staleness check (BR-8), so the operation cannot switch to another confirmed
revision after that check.

The system must not automatically complete an Appointment because its
scheduled time passed (BR-1).

This rule applies whether or not a Clinical Encounter exists. Care that began
before the scheduled start does not allow earlier completion; the Clinic
completes the Appointment once the start has been reached.

---

### BR-8 — Completion is bound to the reviewed confirmed scheduling context

Every confirmed scheduling context of an Appointment is established as a
Schedule Revision identified within that Appointment by its revision sequence.
A confirmed Appointment may receive later confirmed scheduling contexts through
an accepted reschedule (`SPEC-APT-005`, `SPEC-APT-006`).

The caller must supply the expected confirmed revision sequence: the revision
sequence of the confirmed scheduling context it reviewed, as exposed by the
Clinic Appointment Schedule for a `CONFIRMED` Appointment (`SPEC-APT-012`
BR-43).

The expected confirmed revision sequence is required. A missing or non-positive
value is an invalid request and is rejected before any Appointment state is
consulted or disclosed.

Within the same serialized operation, after authorization has been evaluated
and the Appointment is protected against concurrent modification under the
existing lock order:

1. the Appointment must still be `CONFIRMED` (BR-11);
2. the revision sequence of the Appointment's latest confirmed scheduling
   context must equal the expected confirmed revision sequence;
3. only then is the time rule (BR-7) evaluated.

Because the lifecycle check precedes the revision check, an Appointment that is
no longer `CONFIRMED` — for example already `COMPLETED`, `NO_SHOW`, or
`CANCELLED` — is rejected as an invalid lifecycle transition, not as a stale
request.

---

### BR-9 — Stale completion fails without side effects

If the expected confirmed revision sequence differs from the revision sequence
of the Appointment's current latest confirmed scheduling context, completion
must fail.

A stale attempt must not create:

- a `COMPLETED` Lifecycle Event;
- any Appointment lifecycle change;
- any Reschedule Proposal change;
- any Care Authorization change;
- an Appointment Communication.

The caller must re-read the Appointment and review its current confirmed
scheduling context before attempting the operation again.

The stale outcome follows the repository's established optimistic-concurrency
convention for a deterministic client-input revision mismatch: an ordinary
raised exception (SQLSTATE `P0001`) with the stable message
`Stale confirmed Appointment schedule revision` — the same message used by
`SPEC-APT-010` BR-42. It must not use a SQLSTATE or HTTP status that PostgREST
or the client library treats as transient and retries automatically.

---

### BR-10 — Revision sequence, not presented time, determines staleness

Staleness is determined only by comparing revision sequences.

A completion attempt made with a superseded expected confirmed revision
sequence must fail even when the current confirmed scheduling context has:

- the same start instant;
- the same formatted local date and time;
- only a different end instant, duration, or scheduling timezone;
- a start that, like the superseded one, is already in the past.

The caller does not supply an authoritative interval.

---

### BR-11 — Only confirmed Appointments may be completed

The completion transition is:

    CONFIRMED
        ↓
    COMPLETED

The existing Appointment remains the same domain entity.

An Appointment that is:

- `REQUESTED`;
- `CANCELLED`;
- `NO_SHOW`;
- `EXPIRED` (`SPEC-APT-015`);
- already `COMPLETED`;

must not transition to `COMPLETED` through this operation.

A `REQUESTED` Appointment has no confirmed attendance commitment to fulfil.

---

### BR-12 — An existing Clinical Encounter does not block completion

If a Clinical Encounter already exists for the Appointment, completion
proceeds exactly as if it did not.

Completion neither reads, requires, references, nor modifies any Clinical
Encounter. An existing Encounter keeps its own lifecycle (`ACTIVE` or
`CONCLUDED`) and its own documentation lifecycle.

This differs intentionally from `NO_SHOW` and cancellation, which an existing
Encounter blocks (`SPEC-APT-010` BR-5, `SPEC-APT-003`): an Encounter
contradicts non-attendance and cancellation, but is consistent with a visit
that occurred.

---

### BR-13 — Completion does not create or conclude clinical information

Completing an Appointment must not:

- create a Clinical Encounter;
- conclude a Clinical Encounter (`SPEC-MED-008` BR-13);
- create a Clinical Record Entry, diagnosis, Treatment, or other clinical
  statement;
- finalize Draft Clinical Record Entries;
- create Clinical Amendments;
- infer clinical content.

Conversely, concluding a Clinical Encounter does not complete the Appointment
(`SPEC-MED-008` BR-12).

---

### BR-14 — Clinical documentation may be established after completion

Completion does not close the door on optional clinical tooling.

An authorized Veterinarian may establish the Appointment-backed Clinical
Encounter that documents the visit after the Appointment became `COMPLETED`,
under the bounds of `SPEC-MED-001` BR-34 — in particular, the Encounter's care
start must not be later than the completion.

Completion therefore must not end the Appointment-derived Care Authorization
(BR-21).

---

### BR-15 — Completion Lifecycle Event carries no Encounter reference

A completion records one Appointment Lifecycle Event `CONFIRMED → COMPLETED`
with:

- the Clinic actor context;
- the acting User;
- effective time and recorded time equal to the operation time;
- no Clinical Encounter reference.

The authoritative relationship between an Appointment and its clinical care is
the Clinical Encounter's own reference to the Appointment and to its
Appointment-derived Care Authorization (`SPEC-MED-001` BR-35). The completion
event is not clinical evidence and must not duplicate that relationship.

Historical `COMPLETED` Lifecycle Events established before this rule may
reference a Clinical Encounter. They remain valid historical provenance and
must remain consistent: the referenced Encounter concerns the same Appointment,
Pet, and Clinic, and its care start does not follow the completion.

---

### BR-16 — Completion preserves Appointment history

Completion must not change or erase:

- the Pet;
- the Clinic;
- the original requesting User;
- original requested time;
- confirmed time;
- accepted reschedule history;
- scheduling proposals;
- current or historical Veterinarian Assignments.

The relevant scheduled interval of the Appointment (`SPEC-APT-011`,
`SPEC-APT-012` §4) is unchanged by completion.

---

### BR-17 — Completion records when and by whom

The system must preserve:

- the time at which the Appointment was marked `COMPLETED`;
- the User who completed it.

The completion time is distinct from requested time, confirmed time, actual
clinical occurrence time, and Clinical Record finalization time.

The completing User may differ from the requesting Guardian, any assigned
Veterinarian, and any clinical author.

---

### BR-18 — COMPLETED is terminal

`COMPLETED` is a terminal Appointment lifecycle state.

The Appointment must not transition back to `REQUESTED` or `CONFIRMED`, or to
`CANCELLED` or `NO_SHOW`.

Repeated completion must not create another completion, overwrite the original
completion time, replace the original completing User, or duplicate
Appointment history.

Correction of an incorrectly completed Appointment is not supported in Phase 1.

---

### BR-19 — Completed Appointment cannot be rescheduled or reassigned

A `COMPLETED` Appointment must not enter the requested-time or confirmed
rescheduling workflows, receive a Clinic alternative time, or receive a new
current Veterinarian through Appointment Veterinarian assignment or
reassignment.

---

### BR-20 — Pending Reschedule Proposal becomes VOID

A pending Reschedule Proposal on the Appointment becomes `VOID` with
`APPOINTMENT_LIFECYCLE_CHANGED` in the same operation, through the existing
lifecycle invalidation behavior (`SPEC-APT-005` BR-33). Completion does not
need a dedicated proposal rule.

---

### BR-21 — Completion does not change medical access

Completing an Appointment must not:

- grant new medical-access rights to the Clinic, the completing User, a
  Veterinarian, or another professional;
- end, revoke, or otherwise rewrite the Appointment-derived Care
  Authorization (`SPEC-ACC-002` BR-38).

For a `COMPLETED` Appointment, the Care Authorization supports only what
`SPEC-ACC-001` BR-42 permits.

---

### BR-22 — Completion is communicated without clinical implication

A successful completion establishes the existing `APPOINTMENT_COMPLETED`
Appointment Communication for current Guardians (`SPEC-COM-003` BR-19).

That Communication must not imply that a Clinical Encounter or medical record
exists, or that clinical documentation is complete.

Communication delivery failure must not reverse a valid completion.

---

### BR-23 — Completed Appointment remains historical and visible

A `COMPLETED` Appointment is no longer an active upcoming Appointment.

It remains identifiable to authorized Guardians (`SPEC-APT-011`) and authorized
Clinic actors (`SPEC-APT-012`) as historical Appointment information,
distinguishable from `CANCELLED`, `NO_SHOW`, and `EXPIRED`.

Subscription deterioration, cancellation, or expiration must not delete or
rewrite it.

---

### BR-24 — Completion is atomic

A successful completion atomically establishes:

- the `COMPLETED` lifecycle state;
- the completion Lifecycle Event with its time and acting User;
- invalidation of any pending Reschedule Proposal;
- the `APPOINTMENT_COMPLETED` Communication intents.

If completion cannot be validly performed, the Appointment remains in its
previous valid state and no partial completion information is exposed.

---

### BR-25 — Completion and NO_SHOW are symmetric resolutions

Completion and `NO_SHOW` (`SPEC-APT-010`) are both Clinic lifecycle
resolutions of a `CONFIRMED` Appointment after its scheduled start.

They share:

- Clinic context and responsibility-derived capability;
- no commercial Entitlement gate;
- the required expected confirmed revision sequence and stale rejection;
- the same time rule (start reached; end not required);
- terminal outcome.

They differ in meaning:

- `COMPLETED` — the Clinic asserts the visit occurred;
- `NO_SHOW` — the Clinic asserts the visit did not occur because the Pet did
  not attend.

Only `NO_SHOW` is blocked by an existing Clinical Encounter.

---

## 4. Operation Contract

    complete_appointment(
        p_appointment_id uuid,
        p_expected_confirmed_revision_sequence integer
    ) returns uuid

The operation returns the Appointment identifier.

Evaluation order:

1. Authenticated domain User required.
2. `p_expected_confirmed_revision_sequence` NULL or not positive → invalid
   input, SQLSTATE `22023`, before any Appointment state is consulted.
3. Nonexistent Appointment → rejected.
4. `APPOINTMENT_COMPLETE` for the Appointment's Clinic, evaluated under the
   existing Organization → Clinic lock order. No Entitlement is evaluated.
5. Appointment row protected against concurrent modification.
6. Appointment not `CONFIRMED` → invalid lifecycle transition.
7. Latest confirmed revision sequence ≠ expected → `P0001`
   `Stale confirmed Appointment schedule revision`.
8. That revision's scheduled start later than the operation time → rejected
   (BR-7).
9. Writes: the `CONFIRMED → COMPLETED` Lifecycle Event (Clinic actor, acting
   User, effective and recorded at the operation time, no Clinical Encounter
   reference) and the `COMPLETED` state, with proposal invalidation and
   Communication intents following from existing lifecycle behavior.

No step reads or writes a Clinical Encounter, Veterinarian Assignment, or Care
Authorization.

### Contract compatibility

This contract replaces the earlier
`complete_appointment(p_appointment_id uuid, p_clinical_encounter_id uuid)`
form, which required Clinical Encounter evidence. The change must be introduced
through a forward-only migration. The earlier form must not remain executable
by authenticated callers alongside the new form, because it would bypass
BR-8 to BR-10 and preserve the obsolete evidence requirement.

---

## 5. Completed Appointment Information

A completed Appointment preserves its existing Appointment information and
enough completion information to reconstruct its lifecycle.

### Existing historical information

- Appointment identity;
- Pet;
- Clinic;
- requesting User;
- requested and confirmed scheduling information;
- rescheduling history;
- Veterinarian Assignment history.

### Completion information

- `COMPLETED` state;
- completion time;
- completing User.

### Not part of completion

- Clinical Encounter;
- clinical content.

A Clinical Encounter, if one exists or is later established, is related to the
Appointment through the Encounter's own Appointment reference (BR-15), not
through the completion.

---

## 6. Scenarios

### Scenario: Reception completes an Appointment without clinical tooling

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro for 10:00
And its latest confirmed scheduling context has revision sequence N
And no Veterinarian is assigned
And no Clinical Encounter exists
And Carlos is a Receptionist with `APPOINTMENT_COMPLETE` at the Clinic

When Carlos completes the Appointment at 11:00 with expected confirmed revision
sequence N

Then the Appointment becomes `COMPLETED`
And the completion time and Carlos are recorded
And no Clinical Encounter or clinical information is created
And the Guardians receive the `APPOINTMENT_COMPLETED` Communication

---

### Scenario: Completion without professional Entitlement

Given Luna's Appointment is `CONFIRMED` and its start has passed
And Animalia currently lacks normal professional Entitlement
And Carlos has `APPOINTMENT_COMPLETE` at the Clinic

When Carlos completes it with the current confirmed revision sequence

Then the Appointment becomes `COMPLETED`
And no new paid professional activity is enabled

---

### Scenario: Existing Clinical Encounter does not block completion

Given Luna's `CONFIRMED` Appointment has an `ACTIVE` Clinical Encounter started
at 10:05
And its start has passed

When Carlos completes the Appointment with the current confirmed revision
sequence

Then the Appointment becomes `COMPLETED`
And the Encounter remains `ACTIVE` and unchanged
And the completion Lifecycle Event does not reference the Encounter

---

### Scenario: Veterinarian documents the visit after completion

Given Carlos completed Luna's Appointment at 11:00
And no Clinical Encounter existed

When Dr. Garcia later establishes the Appointment-backed Clinical Encounter
with care start 10:07 under `SPEC-MED-001` BR-34

Then the Encounter is created and references the Appointment
And the Appointment remains `COMPLETED` with its original completion
information

---

### Scenario: Completion before the scheduled start is rejected

Given Luna's `CONFIRMED` Appointment starts at 10:00

When Carlos attempts completion at 09:55 with the current revision sequence

Then the operation is rejected
And the Appointment remains `CONFIRMED`

---

### Scenario: Completion at the scheduled start is permitted

Given Luna's `CONFIRMED` Appointment starts at 10:00

When Carlos completes it at exactly 10:00 with the current revision sequence

Then the Appointment becomes `COMPLETED`

---

### Scenario: Missing or invalid revision sequence

When a completion is submitted with no expected confirmed revision sequence, or
with zero or a negative value

Then it is rejected as invalid input before any Appointment state is consulted
And nothing changes

---

### Scenario: Accepted reschedule makes the reviewed context stale

Given Carlos reviewed Luna's `CONFIRMED` Appointment at revision N
And a reschedule was then accepted, establishing confirmed revision N+1

When Carlos completes the Appointment with expected confirmed revision
sequence N

Then the operation is rejected with `Stale confirmed Appointment schedule
revision`
And the Appointment remains `CONFIRMED` at revision N+1
And no Lifecycle Event, proposal change, Care Authorization change, or
Communication is created

---

### Scenario: Superseded revision with the same start is still stale

Given Luna's confirmed revision N was replaced by revision N+1 with the same
start but a different end
And both starts are in the past

When Carlos completes the Appointment with expected confirmed revision
sequence N

Then the operation is rejected as stale

---

### Scenario: Pending Reschedule Proposal is invalidated by completion

Given Luna's `CONFIRMED` Appointment has a pending Reschedule Proposal
And its start has passed

When Carlos completes the Appointment with the current revision sequence

Then the Appointment becomes `COMPLETED`
And the proposal becomes `VOID` with `APPOINTMENT_LIFECYCLE_CHANGED`
And it can no longer be accepted or withdrawn

---

### Scenario: Requested Appointment cannot be completed

Given Luna's Appointment remains `REQUESTED`

When an authorized Clinic actor attempts completion

Then the operation is denied as an invalid lifecycle transition
And the Appointment remains `REQUESTED`

---

### Scenario: Cancelled, no-show, or expired Appointment cannot be completed

Given Luna's Appointment is `CANCELLED`, `NO_SHOW`, or `EXPIRED`

When completion is attempted

Then the operation is denied
And the Appointment keeps its existing outcome

---

### Scenario: Appointment cannot be completed twice

Given Luna's Appointment is already `COMPLETED`

When completion is attempted again, including with the revision sequence that
was just completed

Then it is rejected as an invalid lifecycle transition
And the original completion time and completing User remain unchanged

---

### Scenario: Guardian cannot complete Appointment

Given Maria is Luna's active Guardian
And Maria has no Clinic Appointment-management capability

When Maria attempts to complete Luna's Appointment

Then the operation is denied

---

### Scenario: Veterinarian without completion capability cannot complete

Given Dr. Garcia has a current Clinic Assignment at Animalia Madrid Centro
And Dr. Garcia does not hold `APPOINTMENT_COMPLETE`

When Dr. Garcia attempts to complete Luna's Appointment

Then the operation is denied

---

### Scenario: Two Clinic actors complete the same Appointment

Given Carlos and Jorge both reviewed Luna's `CONFIRMED` Appointment at
revision N
And its start has passed

When Carlos completes it with revision N
And Jorge then completes it with revision N

Then Carlos's operation succeeds
And Jorge's is rejected because the Appointment is no longer `CONFIRMED`
And exactly one completion Lifecycle Event and one Communication set exist

---

### Scenario: No-show or cancellation wins a race

Given Luna's `CONFIRMED` Appointment at revision N is shown to Carlos
And, before Carlos submits, the Appointment is marked `NO_SHOW` or cancelled
(by the Clinic, or by a Guardian before the latest confirmed start,
`SPEC-APT-003` BR-31)

When Carlos completes it with revision N

Then the operation is rejected as an invalid lifecycle transition
And the Appointment keeps its existing outcome

---

### Scenario: Completed Appointment remains historical

Given Luna's Appointment was completed

When an authorized Guardian or Clinic actor views Luna's Appointments

Then the Appointment is shown as historical `COMPLETED`
And its relevant scheduled interval is unchanged

---

## 7. Appointment Completion vs Clinical Care

Appointment and Clinical Encounter answer different questions.

    Appointment COMPLETED
    "Did the Clinic resolve the scheduled visit as having occurred?"

    Clinical Encounter
    "What veterinary care was actually provided, by whom, and when?"

The two lifecycles are independent. All three paths are valid:

    CONFIRMED
        ↓ complete
    COMPLETED

    CONFIRMED
        ↓ Encounter established
    CONFIRMED + Encounter
        ↓ complete
    COMPLETED + Encounter

    CONFIRMED
        ↓ complete
    COMPLETED
        ↓ Encounter established later for the care that already occurred
    COMPLETED + Encounter

In every path, any Appointment-backed Encounter's care start lies between the
Appointment's confirmation and, once completed, its completion
(`SPEC-MED-001` BR-34).

Appointment completion does not imply:

- that a Clinical Encounter exists;
- that a Clinical Encounter has concluded;
- that any medical record exists or is complete.

Clinical Encounter conclusion does not imply Appointment completion.

The Appointment must not become the source of clinical truth.

---

## 8. Terminal Appointment State

`COMPLETED` is a terminal state. A completed Appointment is:

- no longer an upcoming scheduling obligation;
- not reschedulable;
- not reassignable;
- historically identifiable.

`COMPLETED`, `CANCELLED`, `NO_SHOW`, and `EXPIRED` describe materially
different outcomes and must remain distinguishable.

---

## 9. Edge Cases

### Care begins earlier than scheduled

A Clinical Encounter may begin before the scheduled start (`SPEC-MED-001`
BR-24). The Appointment is completed once the scheduled start has been reached
(BR-7).

### Clinic completes prematurely

If the Clinic completes the Appointment before care actually begins, an
Appointment-backed Encounter can no longer be established for care starting
after the completion (`SPEC-MED-001` BR-34). The completion is not reversible
in Phase 1.

### Clinical documentation completed later

Documentation of an existing Encounter, or establishment of the Encounter
itself, may happen after Appointment completion under the Medical Records
Specifications. A later documentation timestamp does not rewrite the
Appointment or clinical occurrence time.

### Completion recorded some time after the visit

Because completion is an administrative assertion that may be recorded after
the visit, a `CONFIRMED` Appointment may remain unresolved for a while after
its start. During that time a Guardian can no longer cancel it
(`SPEC-APT-003` BR-31): Guardian cancellation is permitted only before the
latest confirmed start, and completion only from it (BR-7), so the two are
never valid at the same instant. This rule changes nothing in completion.

### Veterinarian Assignment exists but was never used

An existing Veterinarian Assignment neither helps nor hinders completion and
remains historical information.

### Incorrect completion discovered later

A completed Appointment must not be silently returned to `CONFIRMED` or
changed to another terminal state. A controlled correction workflow may be
introduced later.

---

## 10. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-003 — Cancel Appointment
- SPEC-APT-005 — Propose Confirmed Appointment Reschedule
- SPEC-APT-006 — Accept Appointment Reschedule Proposal
- SPEC-APT-010 — Mark Appointment No-Show
- SPEC-APT-012 — View Clinic Appointment Schedule
- SPEC-APT-015 — Expire Unconfirmed Appointment Request
- SPEC-COM-003 — Send Appointment Notifications
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ID-003 — Authenticate User

Optional clinical tooling that may coexist with completion:

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-008 — Conclude Clinical Encounter
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke or End Pet Care Authorization

Loss-of-Entitlement safe-resolution behavior is additionally governed by:

- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-SUB-004 — Handle Loss of Professional Entitlements

---

## 12. Out of Scope

This Specification does not define:

- marking an Appointment as `NO_SHOW`;
- Clinical Encounter creation or conclusion;
- clinical report or documentation requirements;
- correction of an incorrectly completed Appointment;
- normal ending of the Care Authorization;
- Veterinarian Assignment hygiene;
- exposing Veterinarian identity to Guardians;
- billing, invoicing, or payment;
- Guardian confirmation that care occurred;
- satisfaction or review workflows.

---

## 13. Verification Notes

Verification must demonstrate that:

### Contract and authorization

1. only the `(uuid, integer)` contract is executable by authenticated callers;
   the earlier Encounter-evidence form is not;
2. a NULL, zero, or negative expected confirmed revision sequence is rejected
   with SQLSTATE `22023` before any Appointment state is consulted, with no
   state change;
3. `APPOINTMENT_COMPLETE` is required: Receptionist, Administrator, Owner, and
   Veterinarian responsibilities succeed where they grant it for the Clinic;
   Guardians, members without the capability, and actors of another Clinic are
   denied with no state change;
4. completion succeeds without any professional Entitlement.

### Core behavior

5. a `CONFIRMED` Appointment with no Veterinarian Assignment and no Clinical
   Encounter is completed successfully;
6. an Appointment with a current Veterinarian Assignment is completed
   identically, and its Assignment history is unchanged;
7. an Appointment with an existing `ACTIVE` or `CONCLUDED` Clinical Encounter
   is completed successfully, and the Encounter is unchanged;
8. completion with the current confirmed revision sequence succeeds when every
   other rule holds;
9. a superseded expected confirmed revision sequence is rejected with
   SQLSTATE `P0001` and the message
   `Stale confirmed Appointment schedule revision`, including when the
   superseded and current contexts share the same start, differ only in end,
   duration, or timezone, or both have already started;
10. a stale rejection creates no Lifecycle Event, lifecycle change, proposal
    change, Care Authorization change, or Communication;
11. after a stale rejection, the freshly read current revision sequence
    succeeds;
12. completion is rejected before the latest confirmed start, permitted at and
    after it, with no requirement on the scheduled end;
13. a successful completion creates exactly one `CONFIRMED → COMPLETED`
    Lifecycle Event with the Clinic actor context, the acting User, effective
    and recorded times equal to the operation time, and no Clinical Encounter
    reference;
14. the Appointment becomes `COMPLETED` and its relevant scheduled interval is
    unchanged;
15. a pending Reschedule Proposal becomes `VOID` with
    `APPOINTMENT_LIFECYCLE_CHANGED` in the same operation;
16. the `APPOINTMENT_COMPLETED` Communication is established for current
    Guardians;
17. completion creates no Clinical Encounter, Clinical Record Entry, or
    Amendment, and does not conclude an Encounter or finalize a Draft;
18. the Appointment-derived Care Authorization is unchanged by completion.

### Lifecycle and terminal behavior

19. `REQUESTED`, `CANCELLED`, `NO_SHOW`, `EXPIRED`, and already `COMPLETED`
    Appointments are rejected as invalid lifecycle transitions, including when
    the submitted revision sequence matches;
20. a `COMPLETED` Appointment cannot be rescheduled, receive a Clinic
    alternative time, be cancelled, be marked `NO_SHOW`, or receive a
    Veterinarian Assignment or reassignment;
21. repeated completion does not change the original completion time or
    completing User;
22. completed Appointments remain historically identifiable to authorized
    Guardians and Clinic actors;
23. failed completion preserves the previous valid state atomically.

### Provenance

24. historical `COMPLETED` Lifecycle Events that reference a Clinical
    Encounter remain valid, and their consistency (same Appointment, Pet, and
    Clinic; Encounter care start not after completion) remains enforced.

### Concurrency

25. completion and Clinical Encounter establishment for the same Appointment
    are serialized in either order, and both outcomes satisfy `SPEC-MED-001`
    BR-34;
26. completion racing an accepted reschedule is either applied to the reviewed
    revision before the reschedule, or rejected as stale after it;
27. completion racing `NO_SHOW` or cancellation leaves exactly one terminal
    outcome and one terminal Lifecycle Event;
28. two concurrent completions produce exactly one completion.

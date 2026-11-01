# SPEC-APT-002 — Confirm Appointment

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-008, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Allow an authorized Clinic professional to confirm a previously requested Appointment when the Clinic can commit to providing care at the requested time.

Confirmation represents the Clinic's acceptance of the Appointment request.

A confirmed Appointment establishes a stronger scheduling commitment than a requested Appointment.

Confirmation does not itself create clinical information or require that veterinary care has already occurred.

---

## 2. Preconditions

* The Appointment exists.
* The Appointment is currently in `REQUESTED` state.
* The Appointment identifies a Pet.
* The Appointment identifies a Clinic.
* The requested Appointment time remains in the future.
* The acting User exists.
* The acting User is authenticated.
* The acting User has an active professional context that grants the capability to manage Appointments for the Appointment's Clinic.
* The caller identifies the requested scheduling context it reviewed, by its schedule revision sequence (BR-21).
* That reviewed requested scheduling context is still the Appointment's latest requested scheduling context.
* The requested time can still be validly committed by the Clinic.

---

## 3. Business Rules

### BR-1 — Only authorized Clinic actors may confirm an Appointment

An Appointment may be confirmed only by a User whose current professional context grants the capability to manage Appointments for the relevant Clinic.

Authentication alone is insufficient.

Capabilities in another Clinic or Organization do not authorize confirmation.

---

### BR-2 — Only requested Appointments may be confirmed

The standard confirmation workflow applies only to Appointments currently in `REQUESTED` state.

An Appointment that is already:

* confirmed;
* cancelled;
* completed;
* marked as no-show;
* expired (`SPEC-APT-015`);
* or otherwise outside the request state

must not transition to `CONFIRMED` through this operation.

---

### BR-3 — Confirmation transitions the Appointment to CONFIRMED

Successful confirmation must transition the Appointment from:

```text
REQUESTED → CONFIRMED
```

The Appointment remains the same domain entity.

Confirmation must not create a second Appointment.

---

### BR-4 — Confirmation represents Clinic commitment

A `CONFIRMED` Appointment represents that the Clinic has accepted the Appointment and committed to the scheduled veterinary visit according to the applicable scheduling rules.

The system must not mark an Appointment as confirmed merely because a request exists.

---

### BR-5 — Confirmation requires current scheduling validity

The requested time must still satisfy the Clinic's scheduling and availability constraints when confirmation occurs.

If the Clinic can no longer validly commit to the requested time, the Appointment must not be confirmed at that time.

---

### BR-6 — Confirmation must not silently change the requested time

If the originally requested time is no longer available, confirming the Appointment must not silently move it to another time.

Changing the scheduled time requires an explicit rescheduling or alternative-time workflow.

Confirmation also must not commit the Clinic to a requested time other than the
one the confirming actor reviewed (BR-21).

---

### BR-7 — Veterinarian assignment is not required for confirmation

A Clinic may confirm an Appointment without assigning a specific Veterinarian if the Clinic workflow permits professional assignment later.

Therefore:

```text
Appointment
state: CONFIRMED
veterinarian: not yet assigned
```

may be a valid state.

---

### BR-8 — Existing Veterinarian assignment must remain valid

If a Veterinarian has already been associated with the Appointment before confirmation, the assignment must satisfy the applicable professional and scheduling rules.

Confirmation must not preserve an invalid professional assignment merely because it already exists.

Detailed Veterinarian assignment behavior is governed separately.

---

### BR-9 — Confirmation preserves the Pet

Confirming an Appointment must not change which Pet the Appointment concerns.

The Appointment continues to reference the same Pet domain entity.

---

### BR-10 — Confirmation preserves the Clinic

Confirming an Appointment must not move the Appointment to another Clinic.

Changing Clinic requires a separate workflow.

---

### BR-11 — Confirmation preserves the original requester

The User who originally requested the Appointment must remain historically identifiable after confirmation.

The Clinic professional who confirms the Appointment is a different actor and must not replace the requesting User.

---

### BR-12 — Confirmation must preserve who performed the confirmation

The system must be capable of establishing which authorized User confirmed the Appointment and when confirmation occurred.

This information is relevant to Appointment traceability.

---

### BR-13 — Confirmation does not create medical history

Confirming an Appointment must not automatically create:

* a Medical Record Entry;
* a diagnosis;
* a Treatment;
* a clinical observation;
* a prescription;
* any other medical statement.

The Appointment concerns planned care, not completed clinical activity.

---

### BR-14 — Confirmation does not imply Appointment completion

A confirmed Appointment represents scheduled future care.

It must not be treated as completed until the applicable completion workflow succeeds.

---

### BR-15 — Confirmation does not grant unrestricted medical access

Confirmation of an Appointment must not automatically grant arbitrary or permanent access to the Pet's entire medical history.

Any medical access associated with the upcoming veterinary visit must follow the Access Control Specifications.

---

### BR-16 — Confirmation must prevent invalid scheduling conflicts

The system must not confirm an Appointment if doing so would violate applicable scheduling constraints such as an unsupported Clinic or professional conflict.

The exact availability model and conflict rules are defined separately.

---

### BR-17 — Confirmation and scheduling commitment are atomic

The system must not expose an Appointment as `CONFIRMED` unless the corresponding scheduling commitment has been validly established.

Likewise, the scheduling capacity must not be committed while the Appointment remains `REQUESTED`.

Confirmation must behave as one logical domain operation.

---

### BR-18 — Repeated confirmation is idempotent with respect to domain identity

Attempting to confirm an Appointment that is already confirmed must not:

* create another Appointment;
* duplicate scheduling commitment;
* duplicate confirmation history;
* grant additional capabilities.

Whether the operation returns the existing confirmed state or reports an invalid transition is an application/API concern, but domain state must remain consistent.

---

### BR-19 — Confirmation of a past Appointment is not allowed

A requested Appointment whose intended time has already passed must not be confirmed through the normal confirmation workflow.

Historical correction or administrative reconciliation, if ever required, must be handled separately.

Such a request is logically expired and later becomes `EXPIRED`
(`SPEC-APT-015`). The rejection depends only on the latest requested scheduled
start and authoritative backend time, not on whether `EXPIRED` has already been
materialized.

As a presentation consequence only, a client may stop offering confirmation
once the displayed requested start is no longer in the future. That is
advisory; the backend remains authoritative.

---

### BR-20 — Requester identity does not grant permanent Appointment access

The User who originally requested an Appointment must remain historically
identifiable.

However, requester status alone must not grant permanent access to the Pet
or its Appointments.

Guardian-facing Appointment access must depend on the User's current
authorization relationship with the Pet.

---

### BR-21 — Confirmation is bound to the reviewed requested scheduling context

Every requested scheduling context of an Appointment is established as a
Schedule Revision identified within that Appointment by its revision sequence.
A requested Appointment may receive several requested scheduling contexts, for
example through `SPEC-APT-004`.

The confirming caller must supply the expected requested revision sequence: the
revision sequence of the requested scheduling context it reviewed, as exposed
by the Clinic Appointment Schedule (`SPEC-APT-012` BR-43).

The expected requested revision sequence is required. A missing or non-positive
value is an invalid request and is rejected before any state is changed.

Within the same serialized confirmation operation, after the Appointment is
protected against concurrent modification and only after authorization and
Entitlement have been evaluated:

1. the Appointment must still be `REQUESTED` (BR-2);
2. the revision sequence of the Appointment's latest requested scheduling
   context must equal the expected requested revision sequence;
3. only then are the remaining confirmation rules evaluated, unchanged:
   future time (BR-19), current scheduling validity (BR-5, BR-16), and any
   existing Veterinarian Assignment (BR-8).

Because the lifecycle check precedes the revision check, an Appointment that is
no longer `REQUESTED` is rejected as an invalid lifecycle transition, not as a
stale confirmation.

The confirmed scheduling commitment is established from exactly the reviewed
requested scheduling context.

---

### BR-22 — Stale confirmation fails without side effects

If the expected requested revision sequence differs from the revision sequence
of the Appointment's current latest requested scheduling context, confirmation
must fail.

A stale confirmation must not:

* create a confirmed scheduling commitment or Schedule Revision;
* change the Appointment lifecycle state, which remains `REQUESTED`;
* create an Appointment Lifecycle Event;
* establish any Appointment Communication;
* change the current requested scheduling context or Veterinarian Assignment.

The caller must re-read the Appointment and explicitly review its current
requested scheduling context before attempting confirmation again.

The stale outcome follows the repository's established optimistic-concurrency
convention for a deterministic client-input revision mismatch: an ordinary
raised exception (SQLSTATE `P0001`) with a stable, distinct message. It must not
use a SQLSTATE or HTTP status that PostgREST or the client library treats as
transient and retries automatically, because retrying with the same stale
expected sequence can never succeed.

---

### BR-23 — Revision sequence, not presented time, determines staleness

Staleness is determined only by comparing revision sequences.

A confirmation made with a superseded expected requested revision sequence must
fail even when the current requested scheduling context has:

* the same start instant;
* the same formatted local date and time;
* only a different end instant, duration, or scheduling timezone.

The confirmation operation must not compare presented or client-supplied
scheduling values in place of the revision sequence, and the caller does not
supply an authoritative interval.

---

### BR-24 — Confirmation while a Clinic alternative time is pending

A `REQUESTED` Appointment may have a pending Clinic Alternative Time proposal
(`SPEC-APT-018`). Confirmation remains allowed; the Clinic does not have to
withdraw the proposal first.

Confirmation confirms the Appointment's current requested scheduling context —
the time the Guardian requested — and never the proposed alternative.

The new confirmed scheduling context supersedes the proposal's base, so the
pending proposal becomes `VOID` (`BASE_REVISION_SUPERSEDED`) in the same
operation (`SPEC-APT-005` BR-33, `SPEC-APT-018` BR-18). It can never be
accepted afterwards, and an undelivered
`APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication for it is suppressed
(`SPEC-COM-003` BR-72).

The confirmation's authorization, Entitlement, stale-safety, future-time,
availability, and Veterinarian rules are unchanged by the pending proposal.

Before confirming in this situation the Professional client must warn that
confirmation confirms the currently requested time and discards the pending
alternative proposal (`SPEC-APT-018` §5).

---

### BR-25 — Confirmation after a Guardian accepted a Clinic alternative

When a Guardian accepts a Clinic Alternative Time proposal (`SPEC-APT-019`),
the accepted interval becomes a new requested scheduling context N+1 whose
source is that proposal, and the Appointment remains `REQUESTED`.

Confirmation then follows this Specification unchanged:

* the caller supplies N+1 as the expected requested revision sequence;
* the confirmed scheduling commitment equals exactly the accepted interval;
* a caller that reviewed N before the acceptance is rejected as stale
  (BR-22).

Guardian acceptance never confirms the Appointment by itself.

---

## 4. Scenarios

### Scenario: Confirm a requested Appointment successfully

Given Luna has an Appointment at Animalia Madrid Centro
And the Appointment is in `REQUESTED` state
And the requested time is still valid and available
And Maria is authorized to manage Appointments for Animalia Madrid Centro

When Maria confirms the Appointment

Then the Appointment state becomes `CONFIRMED`
And the Appointment remains associated with Luna
And the Appointment remains associated with Animalia Madrid Centro
And the original requesting User remains recorded
And Maria is recorded as the confirming User
And the confirmation time is preserved

---

### Scenario: Confirm Appointment without assigned Veterinarian

Given Luna has a requested Appointment at Animalia Madrid Centro
And no Veterinarian has yet been assigned
And the requested time can be validly committed
And Maria is authorized to confirm Appointments

When Maria confirms the Appointment

Then the Appointment becomes `CONFIRMED`
And the Appointment may remain without an assigned Veterinarian
And the absence of a Veterinarian does not by itself invalidate confirmation

---

### Scenario: Unauthorized Organization Member attempts confirmation

Given Luna has a requested Appointment at Animalia Madrid Centro
And Maria has an active Organization Membership
And Maria's responsibilities do not grant the capability to manage Appointments for that Clinic

When Maria attempts to confirm the Appointment

Then the operation is denied
And the Appointment remains `REQUESTED`

---

### Scenario: Professional from another Clinic attempts confirmation

Given Luna has a requested Appointment at Animalia Madrid Centro
And Maria is authorized to manage Appointments at Animalia Getafe
And Maria has no applicable Appointment-management capability for Animalia Madrid Centro

When Maria attempts to confirm Luna's Madrid Appointment

Then the operation is denied
And the Appointment remains `REQUESTED`

---

### Scenario: Requested time is no longer available

Given Luna has an Appointment in `REQUESTED` state
And the requested time was available when the request was submitted
And the Clinic can no longer validly commit to that time

When an authorized User attempts to confirm the Appointment

Then confirmation is rejected
And the Appointment remains `REQUESTED`
And the Appointment is not silently moved to another time

---

### Scenario: Confirmation does not silently reschedule

Given Luna requested an Appointment for 10:00
And 10:00 can no longer be confirmed
And 11:00 is available

When an authorized User attempts to confirm the Appointment

Then the Appointment is not automatically changed to 11:00
And the Appointment is not confirmed at 11:00
And changing to 11:00 requires an explicit scheduling workflow

---

### Scenario: Already confirmed Appointment is not confirmed again

Given Luna's Appointment is already `CONFIRMED`

When confirmation is attempted again

Then no second Appointment is created
And no duplicate scheduling commitment is created
And the Appointment remains `CONFIRMED`

---

### Scenario: Cancelled Appointment cannot be confirmed

Given Luna's Appointment is `CANCELLED`

When an authorized User attempts to confirm it

Then the operation is denied
And the Appointment remains `CANCELLED`

---

### Scenario: Appointment in the past cannot be confirmed

Given Luna's Appointment is `REQUESTED`
And its requested time has already passed

When an authorized User attempts to confirm it

Then confirmation is rejected
And the Appointment does not become `CONFIRMED`

---

### Scenario: Confirmation preserves original requester

Given Carlos requested an Appointment for Luna
And Maria is authorized to manage Appointments at the Clinic

When Maria confirms the Appointment

Then Carlos remains recorded as the requesting User
And Maria is recorded as the confirming User
And the two roles remain distinguishable

---

### Scenario: Confirmation does not create clinical information

Given Luna has a requested Appointment

When an authorized User confirms the Appointment

Then the Appointment becomes `CONFIRMED`
And no Medical Record Entry is created solely because of confirmation
And no diagnosis is created
And no Treatment is created

---

### Scenario: Scheduling conflict prevents confirmation

Given Luna has a requested Appointment
And confirming the Appointment would violate an applicable scheduling constraint

When an authorized User attempts confirmation

Then the operation is rejected
And the Appointment remains `REQUESTED`
And no invalid scheduling commitment is created

---

### Scenario: Confirm the reviewed requested scheduling context

Given Luna's Appointment is `REQUESTED` for 10:00
And its latest requested scheduling context has revision sequence N
And Maria reads the Clinic Appointment Schedule and reviews revision N
And Maria is authorized to confirm Appointments at the Clinic

When Maria confirms the Appointment with expected requested revision sequence N

Then the Appointment becomes `CONFIRMED`
And the confirmed scheduling commitment equals the requested context of revision N

---

### Scenario: Guardian reschedules before stale confirmation

Given Maria reviewed Luna's `REQUESTED` Appointment at revision N for 10:00
And Carlos, a current Guardian, then reschedules it to 11:00
And the latest requested scheduling context is now revision N+1

When Maria confirms the Appointment with expected requested revision sequence N

Then confirmation is rejected as stale
And the Appointment remains `REQUESTED` at 11:00 with revision N+1
And no confirmed scheduling commitment, Lifecycle Event, or Appointment Communication is created

---

### Scenario: Clinic re-reads and confirms the current requested context

Given Maria's confirmation with expected revision N was rejected as stale
And Maria re-reads the Clinic Appointment Schedule
And she reviews revision N+1 for 11:00

When Maria confirms the Appointment with expected requested revision sequence N+1

Then the Appointment becomes `CONFIRMED` for 11:00

---

### Scenario: Superseded revision with the same visible start time

Given Maria reviewed Luna's `REQUESTED` Appointment at revision N, 10:00–10:30
And the Clinic's standard duration later changes to 45 minutes
And a Guardian reschedules to the same 10:00 start, establishing revision N+1, 10:00–10:45 (`SPEC-APT-004` BR-19)

When Maria confirms the Appointment with expected requested revision sequence N

Then confirmation is rejected as stale
And the equal start time does not make revision N current
And the Appointment remains `REQUESTED`

---

### Scenario: Two Clinic actors confirm the same reviewed revision

Given Maria and Jorge are both authorized to confirm Appointments at the Clinic
And both reviewed Luna's `REQUESTED` Appointment at revision N

When Maria confirms with expected requested revision sequence N
And Jorge then confirms with expected requested revision sequence N

Then Maria's confirmation succeeds
And Jorge's confirmation is rejected because the Appointment is no longer `REQUESTED`
And exactly one confirmation Lifecycle Event and one confirmed scheduling commitment exist

---

### Scenario: Fresh confirmation without assigned Veterinarian

Given Luna's `REQUESTED` Appointment has no current Veterinarian Assignment
And Maria reviewed its current requested revision N
And the requested time can be validly committed

When Maria confirms with expected requested revision sequence N

Then the Appointment becomes `CONFIRMED`
And it may remain without an assigned Veterinarian (BR-7)

---

### Scenario: Fresh confirmation keeps Veterinarian validation

Given Luna's `REQUESTED` Appointment has a current Veterinarian Assignment
And Maria reviewed its current requested revision N
And the assigned Veterinarian no longer satisfies the applicable professional or scheduling rules for that interval

When Maria confirms with expected requested revision sequence N

Then confirmation is rejected under BR-8
And a matching expected requested revision sequence does not bypass any other confirmation rule

---

### Scenario: Confirmation discards a pending Clinic alternative

Given Luna's Appointment is `REQUESTED` for 10:00 as revision 1
And the Clinic proposed 12:00 as an alternative time, still pending
When an authorized Clinic actor confirms with expected requested revision sequence 1
Then the Appointment becomes `CONFIRMED` for 10:00
And the alternative proposal becomes `VOID` with `BASE_REVISION_SUPERSEDED`
And the proposal can no longer be accepted

---

### Scenario: Confirmation of an accepted alternative

Given the Guardian accepted the Clinic's 12:00–12:30 alternative, creating revision 2
When an authorized Clinic actor confirms with expected requested revision sequence 2
Then the Appointment becomes `CONFIRMED` for 12:00–12:30

---

## 5. Appointment State Transition

This Specification establishes the transition:

```text
REQUESTED
    │
    │ confirm
    ▼
CONFIRMED
```

The transition is one-way within this Specification.

Other transitions such as:

```text
REQUESTED → CANCELLED

CONFIRMED → CANCELLED

CONFIRMED → COMPLETED

CONFIRMED → NO_SHOW
```

require separate Specifications.

---

## 6. Scheduling Commitment

Confirmation establishes a scheduling commitment.

The exact technical representation of that commitment is not defined here.

The implementation must nevertheless guarantee that an Appointment cannot be considered successfully confirmed when the applicable scheduling constraints reject the requested time.

### Reviewed requested scheduling context

The confirmation request identifies the Appointment and the expected requested
revision sequence (BR-21). The revision sequence is domain concurrency/version
information within one Appointment; it is not a presentation identity and does
not expose the Appointment's complete scheduling history.

### Contract compatibility

Adding the required expected requested revision sequence changes the
confirmation operation's request contract and is a breaking change to any
existing caller of the identifier-only form.

The change must be introduced through a forward-only migration that replaces
the identifier-only operation. The identifier-only form must not remain
executable by authenticated callers alongside the new form, because it would
bypass BR-21 to BR-23, unless an approved compatibility rule explicitly
requires it.

Scheduling rules may later include:

* Clinic operating hours;
* Appointment availability;
* professional availability;
* Appointment duration;
* overlapping Appointment constraints;
* resource availability.

Each rule must be introduced through approved Specifications rather than assumed.

---

## 7. Edge Cases

### Availability changes between request and confirmation

A requested Appointment may remain pending while availability changes.

The Clinic must evaluate current scheduling validity at confirmation time rather than assuming that availability at request time remains valid.

---

### Requested time changes while the Clinic reviews it

A current Guardian may reschedule a requested Appointment (`SPEC-APT-004`)
after a Clinic actor has read it and before that actor confirms it.

The confirmation request then carries a superseded expected requested revision
sequence and is rejected as stale (BR-22). The Clinic must not become committed
to a requested time its actor did not review.

---

### Guardian accepts a Clinic alternative while the Clinic reviews the request

If a Guardian accepts a Clinic Alternative Time proposal (`SPEC-APT-019`)
after a Clinic actor has read the Appointment and before that actor confirms
it, the confirmation carries the superseded sequence and is rejected as stale
(BR-22). After re-reading, the actor sees the accepted interval and may
confirm it.

---

### Confirmation outcome is not received by the caller

If the caller does not receive the outcome of a successful confirmation and
repeats it, the repeated request is rejected because the Appointment is no
longer `REQUESTED` (BR-2, BR-18). Re-reading the Appointment shows its
authoritative state.

---

### Two Appointments compete for the same remaining capacity

Two requested Appointments may be eligible for the same limited scheduling capacity.

At most the Appointment that successfully acquires the valid scheduling commitment may be confirmed when the applicable capacity allows only one.

The exact concurrency-control mechanism is architectural.

---

### Clinic becomes unpublished after request

A Clinic may become unpublished after receiving an Appointment request.

Unpublishing affects public visibility and the ability to receive new
Guardian-facing Appointment requests.

Unpublishing alone does not remove the Clinic's internal capability to manage
existing Appointment requests.

Confirmation of an existing Appointment remains subject to the Organization's
current professional entitlements and all applicable scheduling and
authorization rules.

---

### Requesting Guardian later loses Guardianship

The requesting User may cease to have an active Guardianship relationship
with the Pet after validly requesting the Appointment.

The Appointment must remain historically valid and must not be deleted solely
because the requesting User's Guardianship later ends.

Loss of Guardianship removes Pet-related access derived from that
Guardianship.

The requesting User must not retain access to the Pet's Appointment solely
because they originally created it.

Current Appointment visibility and management permissions are determined by
the applicable current Guardianship and Clinic authorization rules.

---

### Confirmation notification fails

Failure to deliver an email or push notification must not automatically reverse an otherwise valid Appointment confirmation.

Communication delivery and Appointment state are separate concerns.

Retry behavior for transactional communication is defined separately.

---

## 8. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 9. Dependencies

* SPEC-APT-001 — Request Appointment
* SPEC-APT-004 — Reschedule Requested Appointment
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-015 — Expire Unconfirmed Appointment Request
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-APT-019 — Accept Requested Appointment Alternative Time
* SPEC-ID-003 — Authenticate User
* SPEC-ORG-003 — Accept Organization Invitation
* SPEC-CLI-001 — Create Clinic

Professional Clinic authority will depend on the applicable Clinic Assignment Specifications once introduced.

---

## 10. Out of Scope

This Specification does not define:

* Appointment rejection;
* Appointment cancellation;
* Appointment rescheduling, including Clinic-proposed alternative times
  (`SPEC-APT-018`);
* confirm-on-accept of a Clinic alternative time;
* Appointment completion;
* no-show behavior;
* exact Clinic availability model;
* exact Veterinarian availability model;
* Appointment duration rules;
* Veterinarian assignment;
* appointment-resource allocation;
* Clinic operating hours;
* automatic confirmation;
* waitlists;
* confirmation notifications;
* medical-record access resulting from confirmation;
* internal Clinic-created Appointments.

---

## 11. Verification Notes

Verification must demonstrate that:

1. only an authorized Clinic actor can confirm an Appointment;
2. only `REQUESTED` Appointments may transition through this confirmation workflow;
3. successful confirmation transitions the Appointment to `CONFIRMED`;
4. the same Appointment domain entity is preserved;
5. confirmation requires current scheduling validity;
6. an unavailable requested time cannot be confirmed;
7. confirmation never silently changes the requested time;
8. a Veterinarian is not required for confirmation;
9. Pet, Clinic, and original requester remain unchanged;
10. confirming User and confirmation time are traceable;
11. confirmation does not create clinical information;
12. confirmation does not imply completion;
13. invalid scheduling conflicts prevent confirmation;
14. confirmation and scheduling commitment behave atomically;
15. repeated confirmation cannot create duplicate domain state;
16. past requested Appointments cannot be confirmed;
17. confirmation requires an expected requested revision sequence, and a
    missing or non-positive value is rejected with no state change;
18. confirmation with the revision sequence of the current latest requested
    scheduling context succeeds, and the confirmed scheduling commitment equals
    exactly that requested context;
19. confirmation with a superseded expected requested revision sequence is
    rejected as stale with SQLSTATE `P0001` and a stable distinct message;
20. a stale rejection creates no confirmed Schedule Revision, no Lifecycle
    Event, and no Appointment Communication, and leaves the lifecycle state,
    current requested context, and Veterinarian Assignment unchanged;
21. a stale rejection occurs even when the superseded and current requested
    contexts share the same start instant, and when only end, duration, or
    timezone differ;
22. after a stale rejection, confirming with the freshly read current revision
    sequence succeeds;
23. a confirmation attempt on an Appointment that is no longer `REQUESTED` is
    rejected as an invalid lifecycle transition, including when it carries the
    revision sequence that was confirmed;
24. authorization, Entitlement, future-time, Availability, Veterinarian
    Assignment, conflict, lifecycle-transition, and post-confirmation
    Communication behavior are unchanged by the expected requested revision
    sequence;
25. the identifier-only confirmation form is not executable by authenticated
    callers after the contract change;
26. an `EXPIRED` Appointment cannot be confirmed;
27. a `REQUESTED` Appointment whose latest requested start has passed cannot be
    confirmed before its `EXPIRED` outcome is materialized;
28. confirmation succeeds while a Clinic Alternative Time proposal is pending,
    confirms exactly the current Guardian-requested context, and makes the
    proposal `VOID` with `BASE_REVISION_SUPERSEDED` in the same operation;
29. after a Guardian accepted a Clinic alternative, confirmation with sequence
    N+1 confirms exactly the accepted interval, and confirmation with N is
    rejected as stale with no write;
30. Guardian acceptance of a Clinic alternative alone never makes the
    Appointment `CONFIRMED`.

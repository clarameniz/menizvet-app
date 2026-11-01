# SPEC-APT-018 — Propose Alternative Time for Requested Appointment

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-007, REQ-APT-008, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Allow the Clinic to answer a Guardian's Appointment request with a different
time, instead of only confirming or cancelling it.

"Alternative Time" is the name of this `REQUESTED` workflow. It is not a
separate persistent concept: an Alternative Time proposal is a Reschedule
Proposal (`docs/DOMAIN.md` §16.5) whose base is the Appointment's current
`REQUESTED` Schedule Revision. It uses the same entity, the same proposal
states, the same one-open-proposal rule, and the same permanent-invalidation
machinery as the confirmed reschedule workflow (`SPEC-APT-005`).

The workflow is:

```text
Guardian requests 10:00
        ↓
Appointment = REQUESTED
current REQUESTED revision N = 10:00

Clinic proposes 12:00                       (this Specification)
        ↓
Appointment remains REQUESTED
revision N remains authoritative
Reschedule Proposal P is PENDING

Guardian accepts P                          (SPEC-APT-019)
        ↓
new REQUESTED revision N+1 = proposed interval
P becomes ACCEPTED
Appointment remains REQUESTED

Clinic later confirms N+1                   (SPEC-APT-002)
        ↓
Appointment becomes CONFIRMED
```

The Clinic proposal never replaces the Guardian's requested time before the
Guardian accepts it, and acceptance never confirms the Appointment.

This Specification defines creation of the proposal. Acceptance is defined by
`SPEC-APT-019`, withdrawal by `SPEC-APT-016`, the candidate-time read by
`SPEC-APT-020`, and the Guardian notification by `SPEC-COM-003`.

---

## 2. Preconditions

* The Appointment exists and is `REQUESTED`.
* The Appointment is a pending request: the start of its latest requested
  scheduling context is still in the future (`SPEC-APT-015` BR-4).
* The acting User exists and is authenticated.
* The acting User currently holds `APPOINTMENT_RESCHEDULE` for the
  Appointment's Clinic.
* The Clinic's Organization currently holds the `APPOINTMENT_MANAGEMENT`
  Entitlement.
* The caller identifies the requested scheduling context it reviewed by its
  revision sequence (BR-8).
* The Clinic has a currently configured standard Appointment duration
  (`SPEC-APT-013` BR-57).
* The Appointment has no actionable pending Reschedule Proposal (BR-16).

---

## 3. Business Rules

### BR-1 — An Alternative Time proposal is a Reschedule Proposal on a requested base

An Alternative Time proposal is a frozen proposed scheduling interval intended
to supersede one specific current `REQUESTED` Schedule Revision if the
Guardian accepts it.

It is stored as a Reschedule Proposal whose base is the Appointment's current
requested scheduling context (base context `REQUESTED`). No second proposal
entity, table, or state model exists for this workflow.

The base context determines the workflow semantics:

| Base context | Workflow | Who may propose | Acceptance |
| --- | --- | --- | --- |
| `CONFIRMED` | Confirmed reschedule (`SPEC-APT-005`) | Guardian or Clinic | `SPEC-APT-006`; the Appointment stays `CONFIRMED` |
| `REQUESTED` | Alternative Time (this Specification) | Clinic only | `SPEC-APT-019`; the Appointment stays `REQUESTED` |

The confirmed reschedule workflow is unchanged by this Specification.

---

### BR-2 — Only the Clinic context may propose an alternative time

In Phase 1 only the Clinic context may create a proposal on a `REQUESTED`
base.

A Guardian who wants another requested time changes the request directly
through `SPEC-APT-004`; there is no Guardian-originated proposal on a
`REQUESTED` base.

---

### BR-3 — Clinic authority is `APPOINTMENT_RESCHEDULE` for the Appointment's Clinic

The acting User must currently hold `APPOINTMENT_RESCHEDULE` for the
Appointment's Clinic (`SPEC-ORG-005`).

`APPOINTMENT_CONFIRM` is neither required nor sufficient: proposing another
time is a scheduling negotiation, not a confirmation.

Authority in another Clinic or Organization is insufficient. Authority is
evaluated at the moment of the proposal.

The proposal represents the Clinic context, not only the individual who
created it.

---

### BR-4 — The `APPOINTMENT_MANAGEMENT` Entitlement is required

Creating an Alternative Time proposal requires that the Clinic's Organization
currently holds the `APPOINTMENT_MANAGEMENT` Entitlement, the same Entitlement
required to create a Clinic proposal for a confirmed Appointment
(`SPEC-APT-005`, `SPEC-SUB-003`).

Without it, the proposal is denied and nothing is written.

---

### BR-5 — Clinic publication is irrelevant

An unpublished Clinic may still manage its existing Appointments. Publication
is neither required nor evaluated (`SPEC-APT-002` §7, `SPEC-APT-005` §8).

---

### BR-6 — A meaningful reason is required and is visible to Guardians

The Clinic must provide a meaningful reason: a missing reason, or one that is
blank after trimming whitespace, is invalid input.

The reason is shown to the Appointment's current Guardians together with the
proposal (`SPEC-APT-011` BR-32). The Clinic actor must be able to understand
this before submitting.

The reason is scheduling information. It is distinct from the reason for
visit, Guardian notes, and any cancellation reason, and must not be treated as
clinical information.

---

### BR-7 — The proposal does not change the request

Creating the proposal must not change:

* the Appointment's lifecycle state, which remains `REQUESTED`;
* its current requested scheduling context (revision N), which remains the
  authoritative requested time;
* the Pet, the Clinic, the original requesting User, the reason for visit, or
  Guardian notes;
* the current Veterinarian Assignment;
* the Appointment-derived Care Authorization.

No Schedule Revision and no Lifecycle Event are created. The proposed interval
is not a scheduling commitment, a reservation, or a hold.

---

### BR-8 — The proposal is bound to the reviewed requested scheduling context

The Clinic caller must supply `p_expected_requested_revision_sequence`: the
revision sequence of the requested scheduling context it reviewed, as exposed
by the Clinic Appointment Schedule (`current_schedule_revision_sequence`,
`SPEC-APT-012` BR-43).

The value is required. A missing or non-positive value is invalid input and is
rejected before any Appointment state is consulted.

The proposal binds to exactly the requested scheduling context that passed
this check; that revision becomes the proposal's base.

The expected requested revision sequence is domain concurrency/version
information within one Appointment. It is not persisted on the proposal.

---

### BR-9 — Evaluation order and stale failure

A proposal is evaluated in this order, within one serialized operation, following
the project's established authorization → lock → lifecycle → stale pattern
(`SPEC-APT-002` BR-21, `SPEC-APT-003` BR-25, `SPEC-APT-005` BR-27):

1. the acting User must be authenticated and resolve to a domain User;
2. structurally invalid input is rejected before any Appointment state is
   consulted: a missing or non-positive expected requested revision sequence
   (BR-8) and a missing or meaningless reason (BR-6);
3. the acting User's current `APPOINTMENT_RESCHEDULE` authority for the
   Appointment's Clinic and the Organization's `APPOINTMENT_MANAGEMENT`
   Entitlement are evaluated (BR-3, BR-4), and the Appointment is protected
   against concurrent modification under the existing lock order
   (Organization → Clinic → Appointment);
4. the Appointment must be `REQUESTED`; otherwise the operation fails as an
   invalid lifecycle state, not as stale;
5. the Appointment's latest requested scheduling context is loaded and its
   revision sequence must equal the expected requested revision sequence;
   otherwise the proposal is stale;
6. only then are the remaining rules evaluated: the base requested start is
   still in the future (BR-23), no other actionable proposal exists (BR-16),
   a standard Appointment duration is configured (BR-11), the new start
   resolves and is in the future (BR-14), it differs from the base start
   (BR-13), and the derived interval is feasible (BR-15).

A stale proposal fails with an ordinary raised exception (SQLSTATE `P0001`)
and the stable message
`Stale requested Appointment schedule revision for alternative time proposal`.
It must not use a SQLSTATE or HTTP status that PostgREST or the client library
treats as transient and retries automatically.

A stale proposal writes nothing: no proposal, no lazy `VOID` of an earlier
proposal (BR-16), no Communication, and no change to the Appointment. The
Clinic actor must re-read the Appointment and review its current requested
scheduling context before proposing again.

Because the lifecycle check precedes the revision check, an Appointment that
was meanwhile confirmed, cancelled, or expired is rejected as an invalid
lifecycle state even when the supplied sequence was current when reviewed.

Any failure at any step leaves no write behind.

---

### BR-10 — The Clinic supplies only the new start

The proposal supplies only the new start: a local start date, a local start
time, and the UTC offset needed to resolve that civil time unambiguously in the
Clinic's authoritative scheduling timezone (`SPEC-APT-013` BR-52).

The caller never supplies, and the system never trusts, an end date, end time,
end offset, or duration.

---

### BR-11 — The end is derived from the current standard duration at creation

The proposed end is derived by the system:

```text
proposed end = resolved proposed start instant + current standard Appointment duration
```

The duration is the Clinic's currently configured standard Appointment
duration at the moment the proposal is created (`SPEC-APT-013` BR-57, BR-61),
applied as a fixed elapsed-time interval, never as a calendar quantity and never
as a difference of wall-clock times, consistent with `SPEC-APT-001` BR-30 and
`SPEC-APT-004` BR-23.

A configured standard duration is required. When none is configured the
proposal is rejected deterministically, distinguishably from other rejections,
and nothing is written. There is no fallback or implicit default duration, and
the duration of the base requested context is not used instead.

An Alternative Time proposal constructs a new scheduled interval, so it
follows the single rule for every new interval (`SPEC-APT-013` BR-68), exactly
as a confirmed-reschedule proposal does (`SPEC-APT-005` BR-24).

---

### BR-12 — The proposed interval is frozen at creation

The proposal stores its exact resulting interval: the start instant, the end
instant, and the Clinic scheduling timezone used to resolve it.

It is never recomputed. A later change to the Clinic's standard duration,
timezone, or Availability neither alters nor invalidates the pending proposal
(`SPEC-APT-013` BR-70). Guardian acceptance establishes exactly the stored
interval (`SPEC-APT-019`).

---

### BR-13 — The same resolved start is not an alternative time

A proposal whose resolved start instant equals the start instant of the base
requested scheduling context is a no-op and is rejected without creating a
proposal — even when the current standard duration differs from the base's
duration, so that the derived interval would differ.

The Alternative Time workflow is never a way to change only the duration of a
request.

This deliberately differs from `SPEC-APT-004` BR-19, where a Guardian's
same-start reschedule after a standard-duration change is a genuine change.

The comparison is between instants: the same local civil time that resolves to
a different instant (for example after a Clinic timezone change) is a genuine
change.

---

### BR-14 — The proposed start must be valid and in the future

The proposed start must resolve to exactly one instant in the Clinic's
scheduling timezone and that instant must be in the future.

No business horizon limits how far in the future the Clinic may propose.

---

### BR-15 — The proposed interval must be feasible at creation

The system must not create a proposal that is already known to be impossible.
The derived interval must, at creation:

* be covered by the Clinic's Appointment Availability (`SPEC-APT-013`);
* where the Appointment has a current Veterinarian Assignment: belong to a
  Veterinarian whose Clinic Assignment is still current, be covered by that
  Veterinarian's Availability at the Clinic, and not overlap another currently
  known `CONFIRMED` commitment of the same Veterinarian at any Clinic,
  excluding this Appointment (`SPEC-APT-013` BR-22, BR-23).

These are the same feasibility rules as `SPEC-APT-005` BR-28.

A failure must not disclose the identity, Clinic, Organization, time, or any
other detail of a conflicting commitment. A Veterinarian conflict and missing
Veterinarian Availability are reported identically, as a generic
unavailability.

Feasibility is not a proposal state. Availability, Veterinarian feasibility,
and Entitlement can change and are revalidated at acceptance
(`SPEC-APT-019`).

---

### BR-16 — One open scheduling proposal per Appointment

An Appointment has at most one `PENDING` Reschedule Proposal, whatever its base
context. A `REQUESTED` Appointment therefore never has a pending Alternative
Time proposal together with any other pending proposal.

When the Appointment already has a `PENDING` proposal:

* if it is actionable (BR-17), the new proposal is rejected and the existing
  one remains the open negotiation;
* if it is pending but no longer actionable because its proposed time has
  passed or its proposing User lost continuous authority, it becomes `VOID`
  (`PROPOSED_TIME_PASSED` or `PROPOSING_AUTHORITY_LOST`) in the same operation
  that creates the new proposal (`SPEC-APT-005` BR-33).

This lazy `VOID` happens only after the stale check has passed (BR-9) and is
rolled back with the operation if any later rule fails.

Concurrent proposal attempts never produce more than one `PENDING` proposal
for the Appointment.

---

### BR-17 — Actionability

An Alternative Time proposal is actionable only while all of the following
hold (the single authoritative definition of `SPEC-APT-005` BR-31, applied to
a `REQUESTED` base):

* the proposal is `PENDING`, which guarantees that its base is still the
  Appointment's current Schedule Revision and that the Appointment is still
  `REQUESTED`;
* the base requested start is still in the future;
* the proposed start is still in the future;
* the proposing User has held `APPOINTMENT_RESCHEDULE` for the Appointment's
  Clinic continuously since the proposal was created.

The last three conditions are a derived lapse evaluated from authoritative
present state; no scheduled job is required. Only an actionable proposal is
shown as pending, can be accepted (`SPEC-APT-019`), can be withdrawn
(`SPEC-APT-016`), and has its Communication delivered (`SPEC-COM-003`).

Clinic or Veterinarian Availability, a Veterinarian conflict, the Clinic's
current scheduling timezone, and the Organization's Entitlement are not part of
actionability and are never recorded as proposal state. Reads expose them only
as the derived current scheduling feasibility and Guardian current
acceptability (`SPEC-APT-005` BR-34, BR-35).

---

### BR-18 — Interactions that end the proposal

The normalized permanent-invalidation machinery (`SPEC-APT-005` BR-33) applies
unchanged. For a `REQUESTED` base:

| Event while the proposal is pending | Allowed? | Effect on the proposal |
| --- | --- | --- |
| Guardian reschedules the request (`SPEC-APT-004`) | Yes | The new Guardian-authored `REQUESTED` revision supersedes the base: `VOID` (`BASE_REVISION_SUPERSEDED`) in the same operation. |
| Clinic confirms the request (`SPEC-APT-002`) | Yes, without withdrawing first | Confirmation confirms the current Guardian-requested revision, not the proposal. The new confirmed revision supersedes the base: `VOID` (`BASE_REVISION_SUPERSEDED`) in the same operation; the subsequent lifecycle change finds no pending proposal. |
| Guardian or Clinic cancels (`SPEC-APT-003`) | Yes | `VOID` (`APPOINTMENT_LIFECYCLE_CHANGED`) in the same operation. |
| The base requested start passes | — | Non-actionable at once (BR-17); the request is logically expired (`SPEC-APT-015` BR-4) and can no longer be accepted. When `EXPIRED` is materialized: `VOID` (`APPOINTMENT_LIFECYCLE_CHANGED`). |
| The proposed start passes | — | Non-actionable at once; stays `PENDING` until a new proposal needs the slot, then `VOID` (`PROPOSED_TIME_PASSED`). |
| The proposing User loses continuous Clinic authority | — | Non-actionable at once; stays `PENDING` until a new proposal needs the slot, then `VOID` (`PROPOSING_AUTHORITY_LOST`). |
| A Clinic actor withdraws it (`SPEC-APT-016`) | Yes | `WITHDRAWN`. |
| A Guardian accepts it (`SPEC-APT-019`) | Yes | `ACCEPTED`. |

A Clinical Encounter cannot exist for a `REQUESTED` Appointment
(`SPEC-MED-001`), so `CLINICAL_ENCOUNTER_STARTED` does not arise for this
workflow.

Clinic or Veterinarian Availability changes, Veterinarian conflicts, and
Entitlement loss do not end the proposal; they are revalidated at acceptance.

Reading proposals never changes them.

---

### BR-19 — Withdrawal

A pending Alternative Time proposal may be withdrawn through the Clinic context
exactly as defined by `SPEC-APT-016`. Withdrawal frees the one-open-proposal
slot immediately.

---

### BR-20 — Guardians are notified

Creating the proposal establishes an `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED`
Communication for the Appointment's current Guardians, delivered only while
the proposal remains actionable (`SPEC-COM-003` BR-71, BR-72). It never uses
`APPOINTMENT_RESCHEDULE_PROPOSED`.

---

### BR-21 — The proposal does not extend the request

The proposal does not change when the request expires. Until a Guardian
accepts it, the request's deadline remains the start of the base requested
scheduling context (`SPEC-APT-015` BR-3), even when the proposed start is
later.

If the Guardian does not accept before the base requested start, the proposal
lapses with the request.

---

### BR-22 — Creating the proposal is atomic

The system must not expose a partially created proposal. The proposal, any
lazy `VOID` it requires (BR-16), and its Communication intent (BR-20) are
established together or not at all.

---

### BR-23 — Only a pending request may receive a proposal

A `REQUESTED` Appointment whose latest requested start is no longer in the
future is logically expired (`SPEC-APT-015` BR-4) and cannot receive a
proposal, whether or not `EXPIRED` has been materialized.

---

### BR-24 — The proposal does not create clinical information

Creating the proposal must not create a Medical Record Entry, diagnosis,
Treatment, clinical observation, or other medical information.

---

## 4. Proposal Information

The proposal preserves (`SPEC-APT-005` §6, `docs/RELATIONAL_MODEL.md`):

* the Appointment;
* the base Schedule Revision and its context, `REQUESTED`;
* the proposed start instant, end instant, and scheduling timezone, frozen at
  creation;
* the proposing context, `CLINIC`;
* the proposing User;
* the reason;
* the creation time, recorded by the system;
* the state, `PENDING` at creation.

The proposal request identifies the Appointment, the new local start date,
local start time and UTC offset, the reason, and the expected requested
revision sequence. It carries no proposing context (it is always `CLINIC`), no
end, and no duration.

A conceptual trusted operation is:

```text
propose_requested_appointment_alternative_time(
    p_appointment_id,
    p_start_local_date,
    p_start_local_time,
    p_start_utc_offset_seconds,
    p_reason,
    p_expected_requested_revision_sequence
) → proposal identity
```

The exact technical signature is an implementation decision within these
constraints. The confirmed-reschedule operation (`SPEC-APT-005`) must continue
to reject a `REQUESTED` Appointment.

---

## 5. Professional Presentation Contract

This section defines the Professional client behavior required for the
workflow to be understood correctly. It adds no backend authority: every rule
above is enforced by the trusted operations.

### Future `REQUESTED` Appointment, no pending proposal

When the actor holds `APPOINTMENT_RESCHEDULE` for the Clinic, the
Organization's `APPOINTMENT_MANAGEMENT` is available (`SPEC-APT-012` BR-61),
and the Appointment is a pending request with no pending proposal, the
Appointment detail offers **Propose another time**:

* times are chosen from the Professional candidate read (`SPEC-APT-020`);
* a reason is required, with helper text stating that Guardians will see it;
* a confirmation dialog shows the currently requested interval, the proposed
  alternative interval (the server-returned end), and states that the
  Appointment remains `REQUESTED` until the Clinic confirms it;
* the request carries the `current_schedule_revision_sequence` the actor
  reviewed; a stale rejection re-reads the Appointment and asks the actor to
  review it again.

### Pending proposal

The detail shows the current requested interval, the proposed alternative
interval, the Clinic's reason, the status "awaiting Guardian response", and a
**Withdraw** action (`SPEC-APT-016`). **Propose another time** is not offered
while a proposal is pending.

**Confirm** remains available, subject to `SPEC-APT-012` BR-61. Before
confirming, the client must warn that
confirmation confirms the currently requested time and discards the pending
alternative proposal (`SPEC-APT-002` BR-24).

When the schedule reports the pending alternative as not currently feasible
(`SPEC-APT-012` BR-44), the detail keeps the pending card and **Withdraw**, and
may state generically: **This proposed time is no longer available.**
**Propose another time** is still not offered until the proposal is
withdrawn.

### After Guardian acceptance

When the Appointment is still `REQUESTED` and its current requested scheduling
context came from a Clinic proposal (`SPEC-APT-012` BR-45), the detail shows
the new requested interval with **Guardian accepted your proposed time —
awaiting confirmation**. The existing **Confirm** action remains available,
subject to `SPEC-APT-012` BR-61, and carries the new revision sequence.

### List

No list-level mutation action is added for this workflow.

---

## 6. Scenarios

### Scenario: Clinic proposes an alternative time

Given Luna's Appointment is `REQUESTED` for 10:00 as revision 1
And the Clinic's standard duration is 30 minutes
And Ana holds `APPOINTMENT_RESCHEDULE` for the Clinic
And the Organization holds `APPOINTMENT_MANAGEMENT`
When Ana proposes 12:00 with reason "No veterinarian free at 10:00" and expected requested revision sequence 1
Then a `PENDING` Reschedule Proposal is created on base revision 1 with context `REQUESTED`
And its interval is 12:00–12:30 in the Clinic timezone
And the Appointment remains `REQUESTED` for 10:00
And no Schedule Revision or Lifecycle Event is created
And current Guardians receive `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED`

---

### Scenario: Stale requested revision

Given the Clinic reviewed revision 1 at 10:00
And a Guardian then rescheduled the request to 11:00 as revision 2
When Ana proposes 12:00 with expected requested revision sequence 1
Then the proposal fails with `P0001` and `Stale requested Appointment schedule revision for alternative time proposal`
And no proposal, `VOID`, or Communication is written

---

### Scenario: Guardian context cannot propose

Given Maria is a current Guardian of Luna
When Maria attempts to create a proposal on Luna's `REQUESTED` Appointment
Then no such operation is available to the Guardian context
And Maria may instead reschedule the request through `SPEC-APT-004`

---

### Scenario: Missing capability, other Clinic, or Entitlement

Given an actor lacks `APPOINTMENT_RESCHEDULE` for the Appointment's Clinic, or holds it only at another Clinic, or the Organization lacks `APPOINTMENT_MANAGEMENT`
When the actor proposes an alternative time
Then the operation is denied and nothing is written

---

### Scenario: `APPOINTMENT_CONFIRM` alone is insufficient

Given Carlos holds `APPOINTMENT_CONFIRM` but not `APPOINTMENT_RESCHEDULE` for the Clinic
When Carlos proposes an alternative time
Then the operation is denied

---

### Scenario: Reason required

When a Clinic actor proposes without a reason, or with only whitespace
Then the proposal is rejected as invalid input before any Appointment state is consulted

---

### Scenario: Unpublished Clinic

Given the Clinic is not published
When an authorized Clinic actor proposes a feasible alternative time
Then the proposal is created

---

### Scenario: No configured standard duration

Given the Clinic has no configured standard Appointment duration
When an authorized Clinic actor proposes an alternative time
Then the proposal is rejected deterministically and nothing is written

---

### Scenario: Standard duration changes after the proposal

Given a pending proposal for 12:00–12:30 created under a 30-minute standard duration
When the Clinic changes its standard duration to 45 minutes
Then the proposal still proposes 12:00–12:30
And Guardian acceptance establishes 12:00–12:30

---

### Scenario: Same start rejected even with a changed duration

Given the request is 10:00–10:30 and the standard duration is now 45 minutes
When the Clinic proposes 10:00
Then the proposal is rejected as a no-op

---

### Scenario: Infeasible interval

Given the proposed interval is outside Clinic Availability, or the assigned Veterinarian's Clinic Assignment has ended, or the interval is outside that Veterinarian's Availability, or it overlaps another known confirmed commitment of that Veterinarian
When the Clinic proposes it
Then the proposal is rejected with a generic unavailability outcome
And no detail of any other Appointment, Clinic, or Organization is disclosed

---

### Scenario: Second pending proposal rejected

Given an actionable Alternative Time proposal is pending
When another authorized Clinic actor proposes another time
Then the second proposal is rejected
And the existing proposal remains pending

---

### Scenario: Lapsed proposal is replaced

Given a pending proposal whose proposed start has passed while the request is still pending
When an authorized Clinic actor proposes a new feasible time with the current revision sequence
Then the old proposal becomes `VOID` with `PROPOSED_TIME_PASSED`
And the new proposal is `PENDING`

---

### Scenario: Guardian reschedule supersedes the proposal

Given a pending Alternative Time proposal on revision 1
When a Guardian reschedules the request to 16:00 through `SPEC-APT-004`
Then revision 2 is created by the Guardian
And the proposal becomes `VOID` with `BASE_REVISION_SUPERSEDED`

---

### Scenario: Clinic confirms while the proposal is pending

Given the request is 10:00 (revision 1) and a Clinic proposal for 12:00 is pending
When a Clinic actor confirms with expected requested revision sequence 1
Then the Appointment becomes `CONFIRMED` for 10:00
And the proposal becomes `VOID` with `BASE_REVISION_SUPERSEDED`
And the undelivered proposal Communication is suppressed

---

### Scenario: Cancellation voids the proposal

Given a pending Alternative Time proposal
When a Guardian or the Clinic cancels the Appointment
Then the proposal becomes `VOID` with `APPOINTMENT_LIFECYCLE_CHANGED`

---

### Scenario: Request expires with the proposal pending

Given the request is 10:00 and a proposal for 12:00 is pending
When 10:00 passes without acceptance
Then the proposal is no longer actionable and cannot be accepted
And when `EXPIRED` is materialized the proposal becomes `VOID` with `APPOINTMENT_LIFECYCLE_CHANGED`

---

### Scenario: Proposer loses authority

Given Ana created a pending proposal
When Ana no longer holds `APPOINTMENT_RESCHEDULE` for the Clinic
Then the proposal is no longer actionable, is not shown as pending, and cannot be accepted

---

## 7. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 8. Dependencies

* SPEC-APT-002 — Confirm Appointment
* SPEC-APT-003 — Cancel Appointment
* SPEC-APT-004 — Reschedule Requested Appointment
* SPEC-APT-005 — Propose Confirmed Appointment Reschedule (proposal entity, actionability, `VOID`)
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-APT-015 — Expire Unconfirmed Appointment Request
* SPEC-APT-016 — Withdraw Clinic Reschedule Proposal
* SPEC-APT-019 — Accept Requested Appointment Alternative Time
* SPEC-APT-020 — View Professional Requested-Alternative Candidate Times
* SPEC-COM-003 — Send Appointment Notifications
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
* SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 9. Out of Scope

Explicitly deferred beyond Phase 1:

* a Guardian reject action;
* Guardian withdrawal;
* a counterproposal state or workflow;
* a combined withdraw-and-replace operation;
* confirm-on-accept;
* Clinic-side notification of Guardian acceptance;
* an acceptance Communication to Guardians;
* proposal-history UI for proposals that were never accepted;
* a multi-session concurrency harness;
* any change to the Guardian +60-day candidate horizon (`SPEC-APT-014`);
* a write-side Guardian scheduling horizon;
* Veterinarian reassignment suggestions.

Also not defined here:

* Guardian-originated proposals on a `REQUESTED` base;
* changing only the duration of a request;
* temporary scheduling holds;
* changing the Appointment's Pet or Clinic.

---

## 10. Verification Notes

Verification must demonstrate that:

1. an authorized Clinic actor with `APPOINTMENT_RESCHEDULE` and the
   `APPOINTMENT_MANAGEMENT` Entitlement creates a `PENDING` proposal whose
   base is the current `REQUESTED` revision and whose proposing context is
   `CLINIC`;
2. no Guardian path creates a proposal on a `REQUESTED` base;
3. an actor without the capability, with it only at another Clinic, with only
   `APPOINTMENT_CONFIRM`, or whose Organization lacks the Entitlement is
   denied with no write;
4. a missing or blank reason, and a missing or non-positive expected requested
   revision sequence, are rejected as invalid input before Appointment state
   is consulted;
5. an unpublished Clinic may propose;
6. a stale expected requested revision sequence fails with `P0001` and the
   stable message, writing no proposal, no lazy `VOID`, no Communication, and
   no Appointment change, and a retry with the freshly read sequence succeeds;
7. a non-`REQUESTED` Appointment is rejected as an invalid lifecycle state, not
   as stale, even with the previously current sequence;
8. a logically expired request cannot receive a proposal;
9. the proposal fails deterministically without a configured standard
   duration, and its end equals the resolved start plus the current standard
   duration as elapsed time, including across a daylight-saving transition;
10. the stored interval is unchanged by a later standard-duration, timezone,
    or Availability change;
11. a proposal with the same resolved start as the base is rejected, including
    after a standard-duration change;
12. a past proposed start is rejected;
13. Clinic Availability, the assigned Veterinarian's current Clinic Assignment
    and Availability, and known confirmed Veterinarian conflicts (excluding
    this Appointment) are enforced, without disclosing the conflict;
14. a second actionable proposal is rejected, a lapsed one is made `VOID` with
    its reason atomically with the new proposal, and concurrent attempts yield
    at most one `PENDING` proposal;
15. creating the proposal changes no Schedule Revision, lifecycle state,
    Lifecycle Event, Veterinarian Assignment, Care Authorization, reason for
    visit, or Guardian notes;
16. a Guardian requested reschedule and a Clinic confirmation each make the
    pending proposal `VOID` with `BASE_REVISION_SUPERSEDED`, and Guardian or
    Clinic cancellation and `EXPIRED` materialization each make it `VOID` with
    `APPOINTMENT_LIFECYCLE_CHANGED`, in the same operation;
17. a proposal is non-actionable once the base requested start, the proposed
    start, or the proposer's continuous authority lapses;
18. reads never change proposal state;
19. exactly one `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication is
    established per current Guardian, and none of type
    `APPOINTMENT_RESCHEDULE_PROPOSED`;
20. the confirmed-reschedule operation still rejects a `REQUESTED`
    Appointment, and confirmed-reschedule behavior is unchanged;
21. an alternative that becomes infeasible after creation stays `PENDING`,
    actionable, projected, and withdrawable, and its acceptance is rejected
    until it is feasible again (`SPEC-APT-005` BR-34).

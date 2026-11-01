# SPEC-APT-005 — Propose Confirmed Appointment Reschedule

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-007, REQ-APT-008, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): BR-27, BR-29, and BR-31 condition on Clinical Record Entries instead of an Encounter, and the BR-33 void reason `CLINICAL_ENCOUNTER_STARTED` becomes `CLINICAL_DOCUMENTATION_STARTED`, triggered by the first Entry (SPEC-MED-010 BR-8, BR-9). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow either side of a `CONFIRMED` Appointment to propose a different date and time without unilaterally modifying the existing scheduling commitment.

A reschedule proposal represents a request to replace the currently confirmed time with a proposed alternative.

The current confirmed Appointment remains unchanged until the counterparty explicitly accepts the proposal through the applicable acceptance workflow.

---

## 2. Preconditions

* The Appointment exists.
* The Appointment is currently in `CONFIRMED` state.
* The currently confirmed Appointment time is still in the future.
* The acting User exists.
* The acting User is authenticated.
* The acting User is authorized to act through either:

  * a current Guardianship relationship with the Pet; or
  * an applicable professional context for the Appointment's Clinic.
* The proposed new time is valid.
* The proposed new time is in the future.
* The proposed new time differs from the currently confirmed time.
* The Clinic has a currently configured standard Appointment duration
  (`SPEC-APT-013` BR-57, BR-62).
* No equivalent unresolved reschedule proposal already exists for the Appointment.

---

## 3. Business Rules

### BR-1 — Confirmed Appointment time cannot be changed unilaterally

Once an Appointment is `CONFIRMED`, neither a Guardian nor the Clinic may directly replace the agreed date and time through a unilateral scheduling operation.

Changing the confirmed time requires agreement from the counterparty.

---

### BR-2 — Either side may propose a new time

A reschedule proposal may be initiated by:

* a current authorized Guardian of the Pet; or
* an authorized professional actor for the Appointment's Clinic.

The proposer must have valid current authorization in the context from which they act.

---

### BR-3 — A proposal does not modify the confirmed Appointment

Creating a reschedule proposal must not change:

* the Appointment's current confirmed date and time;
* the Appointment's `CONFIRMED` state;
* the Pet;
* the Clinic;
* the original requesting User.

The existing confirmed scheduling commitment remains valid while the proposal is unresolved.

---

### BR-4 — The counterparty must explicitly accept the proposal

A proposed time must not become the new confirmed Appointment time merely because the proposal exists.

Acceptance must occur through a separate explicit workflow.

Conceptually:

```text
CONFIRMED
10:00
   │
   │ propose 17:00
   ▼
CONFIRMED
10:00
+
Pending proposal
17:00
   │
   │ counterparty accepts
   ▼
CONFIRMED
17:00
```

The final transition is defined separately.

---

### BR-5 — Acceptance must occur through the counterparty context

A proposal created through the Guardian context must require acceptance through an authorized Clinic context.

A proposal created through the Clinic context must require acceptance through an authorized Guardian context.

The same authorization context that created the proposal must not be sufficient to approve its own proposal.

Where a User legitimately holds both personal and professional relationships, authorization must still be evaluated according to the distinct domain context in which each action is performed.

---

### BR-6 — The proposal must preserve its origin

The system must preserve:

* the Appointment;
* the proposed date and time;
* the proposing User;
* whether the proposal originated from the Guardian or Clinic context;
* when the proposal was created.

Proposal history must remain distinguishable from the Appointment's original request and confirmation history.

---

### BR-7 — Guardian proposal requires current Guardianship

A User proposing a new time through the Guardian workflow must currently have an active Guardianship relationship with the Appointment's Pet.

Being the original requesting User alone is insufficient.

---

### BR-8 — Any current Phase 1 Guardian may propose

The Guardian proposing the change does not need to be the User who originally requested the Appointment.

Any current Phase 1 Guardian of the Pet may propose a reschedule where the applicable Appointment rules permit it.

---

### BR-9 — Clinic proposal requires current Clinic authority

A User proposing a new time through the Clinic workflow must currently have a professional context that grants the capability to manage Appointments for the relevant Clinic.

Authority in another Clinic or Organization is insufficient.

---

### BR-10 — A proposal preserves the existing scheduling commitment

Creating a reschedule proposal must not release the scheduling capacity associated with the currently confirmed Appointment.

Until the proposal is accepted or the Appointment otherwise changes lifecycle state, the existing confirmed time remains the active commitment.

---

### BR-11 — The proposed time is not yet a scheduling commitment

Creating a proposal does not itself guarantee that the proposed time will ultimately be available.

The proposed time must be revalidated as required when acceptance is processed.

A future architecture may introduce temporary capacity holds, but this Specification does not assume them.

---

### BR-12 — Proposed time must be in the future

A reschedule proposal must not target a time that has already passed.

---

### BR-13 — Proposed time must differ from the current confirmed time

A proposal for the same effective confirmed date and time does not represent a scheduling change and must not create misleading reschedule history.

---

### BR-14 — Only one unresolved reschedule proposal is supported per Appointment in Phase 1

A `CONFIRMED` Appointment may have at most one active unresolved reschedule proposal at a time.

A second proposal must not be created while another valid proposal remains unresolved.

Rejecting, withdrawing, invalidating, or otherwise resolving a proposal may allow a later proposal to be created through the applicable workflow.

This rule keeps the Phase 1 negotiation model unambiguous.

---

### BR-15 — Counterproposals require a separate proposal lifecycle

The counterparty must not silently modify the proposed time while accepting it.

If the counterparty prefers another time, the existing proposal must first be resolved according to the applicable workflow and a new proposal must then be created.

---

### BR-16 — Proposal reason depends on the proposing context

The system must support recording a reason for a reschedule proposal.

When the Clinic proposes changing a confirmed Appointment, a meaningful reason is required.

When a Guardian proposes changing the Appointment, providing a reason is optional.

A reschedule reason is scheduling information and must not be treated as clinical information.

---

### BR-17 — Proposal does not modify the reason for visit

Creating a reschedule proposal must not change or remove:

* the Appointment's reason for visit;
* existing Guardian-provided notes;
* other Appointment information unrelated to scheduling.

---

### BR-18 — Proposal does not create medical information

Creating a reschedule proposal must not create:

* a Medical Record Entry;
* a diagnosis;
* a Treatment;
* a clinical observation;
* another medical event.

---

### BR-19 — Proposal validity depends on the Appointment remaining reschedulable

A pending proposal must not remain actionable if the Appointment leaves the state in which the proposal can validly be accepted.

For example, a pending proposal must no longer be acceptable if the Appointment becomes:

* `CANCELLED`;
* `COMPLETED`;
* `NO_SHOW`;
* otherwise no longer eligible for confirmed-time rescheduling.

---

### BR-20 — A past scheduling context cannot become the new confirmed time

A pending proposal must not be accepted after its proposed time has passed.

Likewise, the acceptance workflow must account for the current confirmed Appointment time remaining meaningful at the moment the proposal is resolved.

---

### BR-21 — Creating a proposal is atomic

The system must not expose a partially created proposal without its required:

* Appointment;
* proposed time;
* proposer;
* proposer context;
* creation time;
* proposal state.

---

### BR-22 — Existing Veterinarian Assignment does not guarantee eligibility for the proposed time

If the confirmed Appointment already has an assigned Veterinarian, creating a
reschedule proposal must not assume that the professional will remain eligible
for the proposed time.

The proposed scheduling context must be capable of determining whether the
existing Veterinarian Assignment remains compatible with the proposed time.

A proposal must not represent an incompatible professional Assignment as
already valid for the proposed schedule.

---

### BR-23 — The proposer supplies only the new start

A reschedule proposal, from either the Guardian or the Clinic context,
supplies only the new start: a local start date, a local start time, and the
UTC offset needed to resolve that civil time unambiguously in the Clinic's
authoritative scheduling timezone (`SPEC-APT-013` BR-52).

The proposer never supplies, and the system never trusts, an end date, end
time, end offset, or duration.

This supersedes any earlier contract of this workflow that accepted a
caller-supplied end.

---

### BR-24 — The proposed end is derived from the current standard duration at creation

A reschedule proposal proposes a new scheduled interval. Its end is derived by
the system, for the Guardian and the Clinic context alike:

```text
proposed end = resolved proposed start instant + current standard Appointment duration
```

The duration is the Clinic's configured standard Appointment duration current
at the moment the proposal is created (`SPEC-APT-013` BR-57, BR-61, BR-68,
BR-69). It is applied as a fixed elapsed-time interval, never as a calendar
quantity and never as a difference of wall-clock times, so a proposed interval
that crosses a Clinic civil-time transition (for example a daylight-saving
change) lasts exactly the standard duration of real time, consistent with
`SPEC-APT-001` BR-30, `SPEC-APT-004` BR-23, and `SPEC-APT-018` BR-11.

The elapsed duration of the base confirmed scheduling context is not used. A
Schedule Revision stores an interval, not an Appointment-owned duration, so
the proposed interval may be longer or shorter than the confirmed interval it
would replace when the standard duration has changed since that context was
established.

A configured standard duration is required. When none is configured the
proposal is rejected deterministically, distinguishably from other
rejections, and nothing is written (`SPEC-APT-013` BR-62). There is no
fallback or implicit default duration, and the duration of the base confirmed
scheduling context is not used instead.

The proposed interval is frozen at creation (§6): a later change or removal of
the standard duration neither alters nor invalidates the pending proposal, and
acceptance establishes exactly the stored interval (`SPEC-APT-006` BR-28,
BR-29; `SPEC-APT-013` BR-70).

For a Clinic proposal, the base confirmed scheduling context is the one that
passed the reviewed-context check (BR-26). For a Guardian proposal, it is the
Appointment's latest confirmed scheduling context at the moment the proposal
is processed.

---

### BR-25 — The same resolved start is not a reschedule

Refining BR-13: a proposal whose resolved start instant equals the start
instant of the base confirmed scheduling context is not a scheduling change
and must be rejected without creating a proposal — even when the current
standard duration differs from the base's duration, so that the derived
interval would differ.

A reschedule proposal is never a way to change only the duration of an
Appointment, consistent with the Alternative Time workflow (`SPEC-APT-018`
BR-13).

This deliberately differs from `SPEC-APT-004` BR-19, where a Guardian's
unilateral requested reschedule to the same start after a standard-duration
change is a genuine change; that workflow needs no counterparty acceptance.

The comparison is between instants: the same local civil time that resolves
to a different instant (for example after a Clinic timezone change) is a
genuine change.

---

### BR-26 — A Clinic proposal is bound to the reviewed confirmed scheduling context

A Clinic proposal must replace only the confirmed scheduling context its actor
reviewed.

The Clinic caller must therefore supply the expected confirmed revision
sequence: the revision sequence of the confirmed scheduling context it
reviewed, as exposed by the Clinic Appointment Schedule
(`current_schedule_revision_sequence`, `SPEC-APT-012` BR-43).

A missing or non-positive expected confirmed revision sequence is an invalid
Clinic request and is rejected before any state is consulted.

A Guardian proposal does not carry an expected confirmed revision sequence;
supplying one is an invalid request.

---

### BR-27 — Proposal evaluation order and stale failure

A proposal is evaluated in this order, within one serialized operation:

1. the acting User must be authenticated and resolve to a domain User;
2. structurally invalid input is rejected before any Appointment state is
   consulted: an unknown proposing context; for a Clinic proposal a missing or
   non-positive expected confirmed revision sequence (BR-26) or a missing or
   meaningless reason (BR-16); for a Guardian proposal a supplied expected
   confirmed revision sequence;
3. the acting User's current authority in the proposing context is evaluated
   (BR-7, BR-9), including the professional Entitlement required for a Clinic
   proposal, and the Appointment is protected against concurrent modification
   under the existing lock order;
4. the Appointment must be `CONFIRMED`;
5. the latest confirmed scheduling context is loaded; for a Clinic proposal
   its revision sequence must equal the expected confirmed revision sequence,
   otherwise the proposal is stale;
6. only then are the remaining rules evaluated: the current confirmed time is
   still in the future, no Clinical Encounter exists (BR-29), no other
   actionable proposal exists (BR-14), a standard Appointment duration is
   configured (BR-24), the new start resolves and is in the future (BR-12),
   it differs from the base start (BR-25), and the derived interval is
   feasible (BR-28).

A stale Clinic proposal must fail without creating a proposal, voiding an
earlier proposal (BR-33), or creating any Communication.
The stale outcome follows the repository's optimistic-concurrency convention:
an ordinary raised exception (SQLSTATE `P0001`) with the stable message
`Stale confirmed Appointment schedule revision for reschedule proposal`. It
must not use a SQLSTATE or status that the client stack retries
automatically.

The Clinic actor must re-read the Appointment and review its current
confirmed scheduling context before proposing again.

---

### BR-28 — The proposed interval must be feasible when the proposal is created

Refining BR-11: a proposal is not a reservation and does not guarantee
acceptance, but the system must not create a proposal that is already known
to be impossible.

The derived proposed interval must, at creation:

* be covered by the Clinic's Appointment Availability (`SPEC-APT-013`);
* where the Appointment has a current Veterinarian Assignment, belong to a
  Veterinarian whose Clinic Assignment is still current, be covered by that
  Veterinarian's Availability at the Clinic, and not overlap another
  currently known `CONFIRMED` commitment of the same Veterinarian (at any
  Clinic), excluding the Appointment being rescheduled (`SPEC-APT-013`
  BR-22, BR-23).

A failure must not disclose the identity, Clinic, Organization, time, or any
other detail of a conflicting commitment. A Veterinarian conflict and missing
Veterinarian Availability are reported identically.

These checks apply to Guardian and Clinic proposals alike. The acceptance
workflow revalidates them (`SPEC-APT-006`).

---

### BR-29 — A Clinical Encounter prevents rescheduling

Once a Clinical Encounter exists for the Appointment, care has started and the
Appointment can only be completed (`SPEC-APT-009`).

A proposal must not be created for an Appointment that has a Clinical
Encounter, and an existing pending proposal becomes non-actionable as soon as
the Encounter exists (BR-31).

---

### BR-30 — A Clinic proposal reason is visible to Guardians

The meaningful reason a Clinic provides for its proposal (BR-16) is shown to
the Appointment's current Guardians together with the pending proposal
(`SPEC-APT-011`). The Clinic actor must be able to understand this before
submitting.

It remains scheduling information, separate from the reason for visit,
Guardian notes, and any cancellation reason.

---

### BR-31 — Proposal actionability

A pending proposal is actionable only while all of the following hold:

* the proposal is `PENDING` (BR-33), which guarantees that the Appointment is
  still `CONFIRMED`, that no Clinical Encounter exists for it, and that the
  proposal's base confirmed scheduling context is still the Appointment's
  latest scheduling context;
* the base confirmed start and the proposed start are both still in the
  future;
* the proposing User has held the authority of the proposing context
  continuously since the proposal was created (`SPEC-APT-006` BR-24).

The last two conditions are a derived lapse evaluated from authoritative
present state; no scheduled job is required and a lapsed proposal remains
`PENDING`. Only an actionable proposal is shown as pending, can be accepted,
and can be withdrawn. The single pending-proposal slot (BR-14) is held by the
`PENDING` proposal; a lapsed one is made `VOID` when a new proposal needs the
slot (BR-33).

Transient conditions — Clinic or Veterinarian Availability, a Veterinarian
conflict, the Clinic's current scheduling timezone, or the Organization's current
Entitlement — are not part of actionability; they are evaluated by the
acceptance workflow. Reads expose them only as derived values: current
scheduling feasibility (BR-34) and, to Guardians, current acceptability
(BR-35). Neither changes actionability or proposal state.

This definition is independent of the base context. It is the single
authoritative actionability definition for every Reschedule Proposal,
including a Clinic Alternative Time proposal on a `REQUESTED` base
(`SPEC-APT-018` BR-17), where "the Appointment is still `CONFIRMED`" reads as
"still `REQUESTED`".

---

### BR-32 — Withdrawal resolves a Clinic proposal

A Clinic-originated proposal may be withdrawn through the Clinic context
(`SPEC-APT-016`). A withdrawn proposal is no longer actionable, remains
historically identifiable, and frees the single pending-proposal slot, so a
new proposal may then be created.

---

### BR-33 — Permanent invalidation makes a proposal VOID

A `PENDING` proposal that can never again be accepted becomes `VOID`, recording
when the system observed it and why. `VOID` is final and the proposal remains
historically identifiable.

It becomes `VOID` in the same operation that causes the invalidation when:

* a later scheduling context is established for the Appointment other than by
  accepting this proposal (`BASE_REVISION_SUPERSEDED`);
* the Appointment leaves the lifecycle state of the base scheduling context,
  for example by cancellation, completion, or `NO_SHOW`
  (`APPOINTMENT_LIFECYCLE_CHANGED`);
* a Clinical Encounter is established for the Appointment
  (`CLINICAL_ENCOUNTER_STARTED`).

A proposal whose proposed time has passed, or whose proposing User has lost
continuous authority, is non-actionable while still `PENDING` (BR-31). It
becomes `VOID` (`PROPOSED_TIME_PASSED` or `PROPOSING_AUTHORITY_LOST`) when a new
proposal for the same Appointment needs the slot.

Availability, Veterinarian feasibility, and Entitlement can change back and are
never recorded as proposal state; acceptance evaluates them (`SPEC-APT-006`).

Reading proposals never changes them.

The same permanent-invalidation rules apply to a proposal on a `REQUESTED`
base (`SPEC-APT-018` BR-18): a Guardian requested reschedule or a confirmation
supersedes its base, and cancellation or expiry changes the lifecycle
state.

---

### BR-34 — Current scheduling feasibility is derived, reversible, and never proposal state

Current scheduling feasibility answers whether an actionable `PENDING`
proposal's frozen interval could be established right now under the Clinic's
current scheduling constraints. It applies to a proposal on either base
(`SPEC-APT-018`).

An actionable proposal is currently feasible exactly when, at the moment of
evaluation:

1. the Appointment's Clinic has a current scheduling timezone and that
   timezone is valid; and
2. the frozen interval `[proposed start, proposed end)`, evaluated in that
   current Clinic scheduling timezone, satisfies every feasibility rule of
   BR-28: Clinic Appointment Availability (including exceptions) and, where the
   Appointment has a current Veterinarian Assignment, a still-current Clinic
   Assignment, that Veterinarian's Availability at the Clinic, and no other
   known overlapping `CONFIRMED` commitment of that Veterinarian at any Clinic,
   excluding this Appointment.

This is exactly the scheduling evaluation the acceptance workflows apply before
writing (`SPEC-APT-006` BR-30, `SPEC-APT-019` BR-6), so for unchanged state a
read and an acceptance reach the same scheduling conclusion.

* **Frozen interval, current constraints.** The proposal's start and end
  instants are never recomputed. The Clinic's *current* scheduling timezone is
  used, not the timezone stored with the proposal. When the current timezone is
  absent or invalid, the proposal is not currently feasible; its state and
  actionability do not change.
* **No standard duration.** The standard Appointment duration is not read: a
  standard-duration change after creation does not affect feasibility
  (`SPEC-APT-013` BR-70).
* **No Entitlement.** Entitlement is not part of scheduling feasibility
  (see BR-35).
* **Reversible.** Availability, the scheduling timezone, the Veterinarian
  Assignment and Availability, and other Veterinarian commitments can change in
  either direction, so a proposal may become infeasible and later feasible
  again.
* **Never state, never actionability.** Feasibility is never stored, never
  changes the proposal state, and never makes a proposal non-actionable (BR-31,
  BR-33). An infeasible proposal stays `PENDING`, keeps the single
  pending-proposal slot (BR-14) until it is withdrawn, lapses, or is otherwise
  invalidated under the existing rules, may still be withdrawn (`SPEC-APT-016`
  BR-4), and may be accepted if it becomes feasible again before it lapses. No
  `VOID` reason represents temporary infeasibility.
* **Lifecycle boundary.** Permanent invalidation (BR-33: a superseded base; a
  lifecycle change such as cancellation, completion, `NO_SHOW`, or expiry; a
  Clinical Encounter) and derived lapses (BR-31: a passed base or proposed
  start, lost proposer authority) remain actionability. A non-actionable
  proposal is not projected at all; it is never projected as merely
  infeasible. Current scheduling feasibility covers only the reversible
  scheduling constraints listed above.
* **Not a delivery condition.** Feasibility does not affect Communication
  delivery (`SPEC-COM-003` BR-70, BR-72).
* **Exposure.** The Clinic Appointment Schedule exposes it as a generic boolean
  for the projected proposal, without a reason (`SPEC-APT-012` BR-44).
  Presentation based on it is advisory; acceptance remains authoritative and
  revalidates everything.

Existing proposals need no migration or backfill: feasibility is derived from
data every proposal already stores, and their state, start, and end are
unchanged.

---

### BR-35 — Guardian current acceptability is derived and generic

Guardian current acceptability answers whether a current Guardian could accept
an actionable `PENDING` proposal right now. The Guardian Appointment view
exposes it (`SPEC-APT-011` BR-32), and it decides whether the Guardian client
offers acceptance (`SPEC-APT-006` BR-36, `SPEC-APT-019` §5).

For an actionable proposal:

* a `CLINIC` proposal on a `REQUESTED` base (Alternative Time) is currently
  acceptable exactly when it is currently feasible (BR-34); Guardian acceptance
  of an alternative time requires no Entitlement (`SPEC-APT-019` BR-4);
* a `CLINIC` proposal on a `CONFIRMED` base is currently acceptable exactly
  when it is currently feasible (BR-34) **and** the Clinic's Organization
  currently holds the `APPOINTMENT_MANAGEMENT` Entitlement. The Entitlement rule
  of `SPEC-APT-006` BR-26 is unchanged: Guardian acceptance establishes a new
  confirmed commitment, which `SPEC-SUB-003` and `SPEC-SUB-004` BR-38 gate at
  the moment it is established;
* a `GUARDIAN` proposal is never currently acceptable by a Guardian, because
  only the Clinic context may accept it (`SPEC-APT-006` BR-5).

Acceptability is generic. It never reveals whether a negative value results
from scheduling feasibility, the Organization's Entitlement, or the proposing
context, and it exposes no Veterinarian, conflict, availability, or
subscription detail.

Like feasibility, it is derived at read time and reversible (feasibility or the
Entitlement may return while the proposal is still actionable). It is never
stored, never proposal state, never part of actionability, and not a
Communication-delivery condition (`SPEC-COM-003` BR-70, BR-72). Acceptance
remains authoritative.

---

## 4. Proposal State

A newly created reschedule proposal begins conceptually as:

```text
PENDING
```

Future workflows may transition it to states such as:

```text
ACCEPTED
REJECTED
WITHDRAWN
EXPIRED
```

This Specification defines creation of the `PENDING` proposal only.

`ACCEPTED` is defined by `SPEC-APT-006`, `WITHDRAWN` (Clinic-originated
proposals only in Phase 1) by `SPEC-APT-016`, and `VOID` (system-observed
permanent invalidation) by BR-33. `ACCEPTED`, `WITHDRAWN`, and `VOID` are final.
`REJECTED` and `EXPIRED` are not Phase 1 states; a proposal whose time lapses
remains `PENDING` but is non-actionable (BR-31).

The exact persistence representation is not defined here.

---

## 5. Scenarios

### Scenario: Guardian proposes a new time

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro for 10:00
And Maria has an active Guardianship relationship with Luna
And 17:00 is a valid future proposed time

When Maria proposes rescheduling the Appointment to 17:00

Then a `PENDING` reschedule proposal is created
And the proposal identifies 17:00 as the proposed time
And Maria is recorded as the proposing User
And the proposal is identified as Guardian-originated
And the Appointment remains `CONFIRMED` for 10:00

---

### Scenario: Another current Guardian may propose

Given Carlos originally requested Luna's Appointment
And Maria also has an active Guardianship relationship with Luna
And the Appointment is `CONFIRMED`

When Maria validly proposes a different future time

Then the proposal may be created
And Carlos remains historically identifiable as the original requester
And Maria is recorded as the proposer
And the Appointment remains confirmed at its existing time

---

### Scenario: Former Guardian cannot propose solely because they requested the Appointment

Given Carlos originally requested Luna's Appointment
And Carlos no longer has an active Guardianship relationship with Luna
And Carlos has no other applicable authorization

When Carlos attempts to propose a new Appointment time

Then the operation is denied
And no reschedule proposal is created
And the confirmed Appointment remains unchanged

---

### Scenario: Clinic proposes a new time

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro for 10:00
And Maria has a valid professional context for Animalia Madrid Centro
And Maria's responsibilities grant Appointment-management capability
And Maria provides a meaningful reason for the Clinic-initiated change

When Maria proposes moving the Appointment to 17:00

Then a `PENDING` reschedule proposal is created
And the proposal is identified as Clinic-originated
And Maria is recorded as the proposing User
And the Appointment remains `CONFIRMED` for 10:00

---

### Scenario: Clinic proposal without reason is rejected

Given Luna has a `CONFIRMED` Appointment
And Maria is authorized to manage the Appointment through the Clinic context

When Maria attempts to propose a new time without providing a meaningful reason

Then the proposal is rejected
And no reschedule proposal is created
And the Appointment remains unchanged

---

### Scenario: Guardian proposal does not require a reason

Given Luna has a `CONFIRMED` Appointment
And Maria is an active Guardian of Luna

When Maria proposes a valid new time without providing a reason

Then the proposal may be created
And the absence of a reason does not prevent the Guardian-originated proposal

---

### Scenario: Professional from another Clinic cannot propose

Given Luna has a confirmed Appointment at Animalia Madrid Centro
And Maria may manage Appointments at Animalia Getafe
And Maria has no applicable Appointment-management authority at Animalia Madrid Centro

When Maria attempts to propose a new time for Luna's Madrid Appointment

Then the operation is denied
And no reschedule proposal is created

---

### Scenario: Requested Appointment cannot use confirmed-reschedule proposal workflow

Given Luna's Appointment is still `REQUESTED`

When a Guardian or Clinic actor attempts to create a confirmed-reschedule proposal

Then the operation is denied
And no confirmed-reschedule proposal is created

---

### Scenario: Proposal does not change current confirmed time

Given Luna has a `CONFIRMED` Appointment for 10:00

When an authorized actor proposes 17:00

Then the Appointment remains `CONFIRMED` for 10:00
And 17:00 exists only as a pending proposal
And the existing 10:00 scheduling commitment remains active

---

### Scenario: Proposal for same confirmed time is not created

Given Luna has a `CONFIRMED` Appointment for 10:00

When an authorized actor proposes rescheduling the Appointment to the same effective 10:00 time

Then no reschedule proposal is created
And no false scheduling-history event is recorded

---

### Scenario: Proposal for a past time is rejected

Given Luna has a `CONFIRMED` Appointment

When an authorized actor proposes a time that has already passed

Then the proposal is rejected
And the confirmed Appointment remains unchanged

---

### Scenario: Second unresolved proposal is rejected

Given Luna has a `CONFIRMED` Appointment
And a valid `PENDING` reschedule proposal already exists

When an authorized actor attempts to create another reschedule proposal

Then the second proposal is not created
And the existing pending proposal remains the active negotiation

---

### Scenario: Proposal does not modify reason for visit

Given Luna has a confirmed Appointment
And its reason for visit is "Luna has been limping since yesterday"

When an authorized actor creates a reschedule proposal

Then the reason for visit remains unchanged
And the reschedule reason, if present, remains separate from the reason for visit

---

### Scenario: Proposal does not create clinical information

Given Luna has a confirmed Appointment

When an authorized actor creates a valid reschedule proposal

Then no Medical Record Entry is created
And no diagnosis is created
And no Treatment is created

---

### Scenario: Appointment cancellation invalidates pending proposal

Given Luna has a confirmed Appointment
And a `PENDING` reschedule proposal exists

When the Appointment is validly cancelled

Then the Appointment becomes `CANCELLED`
And the pending reschedule proposal can no longer be accepted
And the proposal remains historically distinguishable from an accepted proposal

---

### Scenario: A longer standard duration produces a longer proposal

Given Luna's `CONFIRMED` Appointment is 10:00–10:30, established under a 30-minute standard duration
And the Clinic's standard duration is now 45 minutes
When an authorized actor proposes 15:00
Then the proposal's interval is 15:00–15:45
And the Appointment remains `CONFIRMED` for 10:00–10:30

---

### Scenario: A shorter standard duration produces a shorter proposal

Given Luna's `CONFIRMED` Appointment is 10:00–11:00, established under a 60-minute standard duration
And the Clinic's standard duration is now 30 minutes
When an authorized actor proposes 15:00
Then the proposal's interval is 15:00–15:30

---

### Scenario: No configured standard duration

Given Luna has a `CONFIRMED` Appointment
And the Clinic has no configured standard Appointment duration
When a Guardian or an authorized Clinic actor proposes a new time
Then the proposal is rejected deterministically and nothing is written

---

### Scenario: Standard duration changes after the proposal

Given a pending proposal for 15:00–15:45 created under a 45-minute standard duration
When the Clinic changes its standard duration to 30 minutes, or removes it
Then the proposal still proposes 15:00–15:45
And acceptance establishes 15:00–15:45

---

### Scenario: Same start rejected even with a changed duration

Given Luna's `CONFIRMED` Appointment is 10:00–10:30 and the standard duration is now 45 minutes
When an authorized actor proposes 10:00
Then the proposal is rejected as a no-op

---

### Scenario: Accepted reschedule does not rewrite history

Given revision N is `CONFIRMED` 10:00–10:30
And the Clinic later changes its standard duration to 45 minutes
When a proposal for 15:00 is created and accepted
Then revision N+1 is `CONFIRMED` 15:00–15:45
And revision N still records 10:00–10:30

---

## 6. Reschedule Proposal Information

The domain must support enough information to understand the proposed scheduling change.

At minimum:

* Appointment;
* currently confirmed scheduling context;
* proposed date and time;
* proposing User;
* proposer context (`Guardian` or `Clinic`);
* proposal creation time;
* proposal state;
* proposal reason where required.

The proposed interval is stored exactly as derived at creation (BR-24): its
start instant, its end instant, and the Clinic scheduling timezone used to
resolve it. It is never recomputed later (`SPEC-APT-006`).

The proposal must reference the existing Appointment rather than create an alternative Appointment entity.

### Proposal request

A proposal request identifies the Appointment, the proposing context, the new
local start date, local start time and UTC offset, the reason (required for
the Clinic context), and — for the Clinic context only — the expected
confirmed revision sequence (BR-26). It never carries an end or a duration
(BR-23).

The expected confirmed revision sequence is domain concurrency/version
information within one Appointment; it is not persisted as part of the
proposal.

### Contract compatibility

The start-only, reviewed-context contract replaces the earlier contract that
accepted a caller-supplied end. It must be introduced through a forward-only
migration, and no form of the operation that accepts a caller-supplied end or
lets a Clinic proposal omit the expected confirmed revision sequence may
remain executable by authenticated callers. The exact technical signature is
an implementation decision within these constraints.

### Duration-rule compatibility

The current-standard-duration rule of BR-24 replaces the earlier rule under
which the proposed end preserved the elapsed duration of the base confirmed
scheduling context. It applies only to proposals created after it is
implemented, through a forward-only change. Proposals created earlier keep
their frozen start and end, remain valid, and may be accepted unchanged; no
backfill or recomputation is performed. The request contract (start only) is
unchanged.

---

## 7. Historical Traceability

A reschedule proposal becomes part of the Appointment's scheduling history even if it is not ultimately accepted.

Conceptually:

```text
Appointment A
Confirmed:
10 September, 10:00

11 August
Clinic proposed:
10 September, 17:00
Reason:
Veterinarian unavailable

Proposal:
PENDING
```

If later rejected or withdrawn, the proposal may remain historically identifiable without changing the confirmed Appointment time.

This Specification does not require event sourcing or any specific persistence model.

---

## 8. Edge Cases

### Guardian loses Guardianship while proposal is pending

Creating the proposal while authorized does not grant permanent Appointment authority.

Acceptance must evaluate the current authorization required from the Guardian side.

The detailed acceptance behavior is defined by the acceptance Specification.

---

### Clinic proposer later loses professional authority

The proposal's historical authorship remains valid.

Whether the proposal may still be accepted depends on the Appointment, proposal, and current counterparty authorization rules rather than granting ongoing authority to the former professional.

---

### Proposed time becomes unavailable

A proposed time may cease to satisfy scheduling constraints before acceptance.

The proposal must not force acceptance of an invalid scheduling commitment.

Current scheduling validity must be evaluated by the acceptance workflow.

---

### Current Appointment is cancelled while proposal is pending

Cancellation supersedes the scheduling negotiation.

The proposal must no longer be actionable but should remain historically distinguishable.

---

### Clinic becomes unpublished

Clinic unpublication does not by itself invalidate an existing confirmed Appointment or a pending reschedule proposal.

Public visibility and internal management of existing Appointments are separate concerns.

Professional operations remain subject to applicable current entitlements.

---

### Concurrent proposal creation

Concurrent attempts to create proposals must not result in more than one active unresolved proposal for the Appointment in Phase 1.

The concurrency-control mechanism is architectural.

---

## 9. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 10. Dependencies

* SPEC-APT-001 — Request Appointment
* SPEC-APT-002 — Confirm Appointment
* SPEC-APT-003 — Cancel Appointment
* SPEC-APT-004 — Reschedule Requested Appointment
* SPEC-APT-009 — Complete Appointment
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-APT-016 — Withdraw Clinic Reschedule Proposal
* SPEC-APT-017 — View Professional Reschedule Candidate Times
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-ID-003 — Authenticate User
* SPEC-PET-003 — Accept Guardianship Invitation

Professional Clinic authorization follows the applicable Organization and Clinic Assignment Specifications.

---

## 11. Out of Scope

This Specification does not define:

* acceptance of a reschedule proposal (`SPEC-APT-006`);
* rejection of a reschedule proposal;
* withdrawal of a reschedule proposal (`SPEC-APT-016`; Guardian withdrawal is
  not part of Phase 1);
* changing only an Appointment's duration (BR-25);
* a per-proposal, Appointment-specific, or service-specific duration, or any
  caller-supplied duration (BR-23, BR-24);
* proposal-expiration duration;
* counterproposal workflow beyond requiring a separate proposal;
* temporary scheduling holds;
* automatic acceptance;
* changing the Appointment's Pet;
* changing the Appointment's Clinic;
* Appointment cancellation;
* Appointment completion;
* no-show behavior;
* reschedule notifications;
* rescheduling fees;
* exact availability implementation.

---

## 12. Verification Notes

Verification must demonstrate that:

1. an authorized current Guardian may propose a new time for a `CONFIRMED` Appointment;
2. an authorized Clinic actor may propose a new time;
3. requester status alone does not grant permanent proposal authority;
4. Clinic authority is scoped to the relevant Clinic;
5. proposal creation does not modify the current confirmed time;
6. the existing scheduling commitment remains active while the proposal is pending;
7. proposals begin in `PENDING` state;
8. proposer, proposer context, proposed time, and creation time remain traceable;
9. Clinic-originated proposals require a meaningful reason;
10. Guardian-originated proposals do not require a reason;
11. a proposal for the current confirmed time is not created;
12. proposed times must be in the future;
13. only `CONFIRMED` Appointments use this workflow;
14. only one unresolved proposal exists per Appointment in Phase 1;
15. a proposal does not modify the reason for visit or other unrelated Appointment information;
16. a proposal does not create medical information;
17. Appointment cancellation makes the pending proposal non-actionable;
18. proposed scheduling availability is not treated as guaranteed until acceptance;
19. no form of the operation accepts a caller-supplied end, for either context
    (BR-23);
20. the proposed end equals the resolved start plus the standard duration
    current at creation, as elapsed time, for both contexts, including across
    daylight-saving transitions, and not the elapsed duration of the base
    confirmed scheduling context — so a 30 → 45 minute change yields a
    45-minute proposal and a 60 → 30 minute change a 30-minute proposal
    (BR-24);
21. without a configured standard duration a proposal is rejected
    deterministically in both contexts, with no proposal, lazy `VOID`, or
    Communication written; a later standard-duration change or removal
    neither alters nor invalidates a pending proposal (BR-24);
22. after an accepted proposal, the earlier confirmed Schedule Revision keeps
    its original interval and the new revision has exactly the proposed
    interval, even when their durations differ (BR-24, `SPEC-APT-006` BR-28);
23. a proposal with the same resolved start is rejected, including after a
    standard-duration change (BR-25);
24. a Clinic proposal without a positive expected confirmed revision sequence,
    and a Guardian proposal with one, are rejected as invalid input (BR-26);
25. a stale Clinic proposal fails with `P0001` and the stable message, with no
    proposal, non-actionable fact, or Communication written, and succeeds
    after re-reading (BR-27);
26. a proposal outside Clinic Availability, for an assigned Veterinarian whose
    Clinic Assignment ended, outside that Veterinarian's Availability, or
    overlapping another known confirmed commitment of that Veterinarian is
    rejected without disclosing the conflict, while the Appointment's own
    interval never conflicts with itself (BR-28);
27. a proposal is rejected when a Clinical Encounter exists, and an existing
    proposal stops being actionable once one exists (BR-29, BR-31);
28. proposal actionability follows BR-31 in the Guardian and Clinic reads and
    in Communication delivery;
29. a withdrawn proposal frees the pending-proposal slot (BR-32);
30. a superseded base, a lifecycle change, and a Clinical Encounter each make
    the pending proposal `VOID` with its reason in the same operation, and
    acceptance never voids the proposal being accepted (BR-33);
31. a lapsed proposal stays `PENDING` and non-actionable, and is made `VOID`
    with its reason only when a new proposal needs the slot (BR-33);
32. reads never change proposal state (BR-33);
33. current scheduling feasibility, for a proposal on either base, is true for
    a newly created proposal; becomes false after a `CLOSED` exception covering
    its interval, a loss of the assigned Veterinarian's Availability, a new
    overlapping `CONFIRMED` commitment of that Veterinarian, an ended Clinic
    Assignment of that Veterinarian, or a missing or invalid current Clinic
    timezone; and becomes true again when the exception is cleared or the
    conflicting commitment is cancelled (BR-34);
34. a standard-duration change after creation does not change current
    scheduling feasibility (BR-34);
35. while infeasible, the proposal stays `PENDING` and actionable, is still
    projected by both reads, can be withdrawn, keeps the pending-proposal slot,
    and acceptance is rejected authoritatively with no write; once feasible
    again before it lapses, acceptance succeeds (BR-34);
36. a lapsed or otherwise non-actionable proposal is absent from both
    projections rather than projected as infeasible (BR-34);
37. Guardian current acceptability of a `CONFIRMED`-base Clinic proposal is
    true when it is feasible and the Organization holds
    `APPOINTMENT_MANAGEMENT`, false when it is feasible but the Entitlement is
    lost, and true again when the Entitlement returns while the proposal is
    still actionable and feasible; for a `REQUESTED`-base Clinic proposal it
    equals current scheduling feasibility; for a Guardian proposal it is false
    (BR-35);
38. neither derived value exposes a reason, a Veterinarian conflict, or
    subscription state, and neither is persisted (BR-34, BR-35);
39. an actionable proposal that is not currently feasible or not currently
    acceptable remains eligible for Communication delivery under
    `SPEC-COM-003` (BR-34, BR-35).

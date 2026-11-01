# SPEC-APT-016 — Withdraw Clinic Reschedule Proposal

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-006, REQ-APT-007, REQ-APT-008
**Domain:** Appointments
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): Encounter conditions read as Clinical Record Entry conditions (SPEC-MED-010 BR-9). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow the Clinic to withdraw its own pending Reschedule Proposal, whatever the
proposal's base context:

* a reschedule proposal for a `CONFIRMED` Appointment (`SPEC-APT-005`);
* an Alternative Time proposal for a `REQUESTED` Appointment
  (`SPEC-APT-018`).

Both are the same Reschedule Proposal entity, and withdrawal is the same
domain operation for both. This Specification therefore governs both instead
of duplicating the operation per workflow.

Without withdrawal, a Clinic-originated proposal that turns out to be wrong —
a mistyped time, or a time that became impossible after it was proposed —
blocks every further proposal for the Appointment until its time lapses
(one open proposal per Appointment, `SPEC-APT-005` BR-14, `SPEC-APT-018`
BR-16), while the Guardian may still try to accept it.

Withdrawal resolves that proposal explicitly so the Appointment's current
scheduling context — the confirmed time, or the Guardian's requested time —
remains authoritative and a new proposal may be made.

---

## 2. Preconditions

* The proposal exists.
* The proposal was created through the Clinic context.
* The proposal is currently actionable (`SPEC-APT-005` BR-31; for a
  `REQUESTED` base, `SPEC-APT-018` BR-17).
* The acting User exists and is authenticated.
* The acting User currently holds `APPOINTMENT_RESCHEDULE` for the
  Appointment's Clinic.

---

## 3. Business Rules

### BR-1 — Only Clinic-originated proposals may be withdrawn in Phase 1

Phase 1 supports withdrawal of Clinic-originated proposals through the Clinic
context only, for either base context.

A Guardian-originated proposal cannot be withdrawn through this workflow.
Guardian withdrawal and Guardian rejection are not part of Phase 1.

---

### BR-2 — Any currently authorized Clinic actor may withdraw

A Clinic proposal represents the Clinic context, not only the individual who
created it (`SPEC-APT-005` BR-5).

Any User who currently holds `APPOINTMENT_RESCHEDULE` for the Appointment's
Clinic may withdraw it. The original proposing User is not required.

Authority in another Clinic or Organization is insufficient. Authority is
evaluated at the moment of withdrawal.

---

### BR-3 — Withdrawal requires no professional Entitlement

Withdrawal establishes no new scheduling commitment and no new requested
scheduling context; it only resolves an outstanding proposal. Like safe cancellation (`SPEC-APT-003` BR-19,
`SPEC-SUB-004`), it does not require the `APPOINTMENT_MANAGEMENT`
Entitlement.

---

### BR-4 — Only an actionable proposal may be withdrawn

A proposal that is already `ACCEPTED`, already `WITHDRAWN`, `VOID`
(`SPEC-APT-005` BR-33), or no longer actionable for any reason in
`SPEC-APT-005` BR-31 or `SPEC-APT-018` BR-17 (including a Clinical Encounter,
a lapsed base or proposed time, a superseded base, a confirmation of the
request, a cancelled, expired, or terminal Appointment, or loss of the
proposer's authority) cannot be withdrawn.

Such an attempt fails without effect.

Current scheduling feasibility is not part of actionability (`SPEC-APT-005`
BR-34): an actionable proposal whose interval is no longer currently feasible
may be withdrawn (see "Proposed time became impossible").

---

### BR-5 — Withdrawal is a final, immutable proposal state

A successful withdrawal transitions the proposal:

```text
PENDING → WITHDRAWN
```

A withdrawn proposal can never be accepted, withdrawn again, voided, or
changed.

---

### BR-6 — Withdrawal preserves who withdrew and when

The system must preserve:

* the User who withdrew the proposal;
* the moment of withdrawal, recorded by the system.

The withdrawing context is always the proposing context and is not recorded
separately.

The proposal's original facts — Appointment, base scheduling context and its
context (`CONFIRMED` or `REQUESTED`), proposed interval, proposing User,
proposing context, reason, creation time — remain unchanged.

---

### BR-7 — Withdrawal does not change the Appointment

Withdrawal must not change the Appointment's lifecycle state, any of its
Schedule Revisions, its Veterinarian Assignment, its Care Authorization, or
any other Appointment information.

For a `CONFIRMED` Appointment the existing confirmed time remains the active
commitment. For a `REQUESTED` Appointment the Guardian's current requested
time remains the authoritative request, the Appointment remains `REQUESTED`,
and the request's deadline is unchanged.

---

### BR-8 — Withdrawal frees the pending-proposal slot

A withdrawn proposal no longer occupies the single pending-proposal slot of
the Appointment (`SPEC-APT-005` BR-14, `SPEC-APT-018` BR-16). A new proposal
may be created immediately afterwards through the workflow for the
Appointment's current lifecycle state: `SPEC-APT-005` for `CONFIRMED`,
`SPEC-APT-018` for `REQUESTED`.

---

### BR-9 — Withdrawal and acceptance are serialized

Withdrawal and acceptance of the same proposal cannot both succeed. Whichever
completes first determines the outcome; the other fails without effect
(`SPEC-APT-006` BR-32, `SPEC-APT-019` BR-11).

---

### BR-10 — Withdrawal carries no reason and creates no Communication in Phase 1

Phase 1 withdrawal records no withdrawal reason.

Withdrawal creates no Communication. A not-yet-delivered
`APPOINTMENT_RESCHEDULE_PROPOSED` or `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED`
Communication for the withdrawn proposal is suppressed because the proposal is
no longer actionable (`SPEC-COM-003` BR-70, BR-72). The Guardian's current
Appointment view no longer shows the proposal and continues to show the
existing confirmed time, or the existing requested time.

---

### BR-11 — Withdrawal does not create clinical information

Withdrawal must not create any Medical Record Entry, diagnosis, Treatment,
clinical observation, or other medical information.

---

## 4. Scenarios

### Scenario: Clinic withdraws a mistaken proposal

Given Luna has a `CONFIRMED` Appointment for 10:00
And a Clinic receptionist proposed 17:00 by mistake
When a Clinic actor with `APPOINTMENT_RESCHEDULE` withdraws the proposal
Then the proposal becomes `WITHDRAWN`
And the withdrawing User and time are recorded
And the Appointment remains `CONFIRMED` for 10:00
And a new proposal may be created

---

### Scenario: Clinic withdraws an alternative time for a request

Given Luna's Appointment is `REQUESTED` for 10:00
And the Clinic proposed 12:00 as an alternative time
When a Clinic actor with `APPOINTMENT_RESCHEDULE` withdraws the proposal
Then the proposal becomes `WITHDRAWN`
And the Appointment remains `REQUESTED` for 10:00
And no Schedule Revision is created
And the Clinic may propose another alternative time, or confirm 10:00

---

### Scenario: A voided alternative cannot be withdrawn

Given a Clinic alternative was pending for a `REQUESTED` Appointment
And the Clinic then confirmed the Guardian's requested time, making the proposal `VOID`
When a Clinic actor attempts to withdraw the proposal
Then the operation fails because the proposal is no longer actionable

---

### Scenario: Another authorized Clinic actor withdraws

Given Carlos proposed a new time through the Clinic context
And Ana also holds `APPOINTMENT_RESCHEDULE` for that Clinic
When Ana withdraws the proposal
Then the withdrawal succeeds
And Ana is recorded as the withdrawing User
And Carlos remains recorded as the proposing User

---

### Scenario: Proposed time became impossible

Given a Clinic proposal for 17:00 is pending
And the Clinic later closed its Availability at 17:00
When a Clinic actor withdraws the proposal
Then the proposal becomes `WITHDRAWN`
And the Clinic may propose another time

---

### Scenario: Actor without Clinic authority cannot withdraw

Given a Clinic proposal is pending
When a User without `APPOINTMENT_RESCHEDULE` at that Clinic attempts to withdraw it
Then the operation is denied
And the proposal remains pending

---

### Scenario: Withdrawal without the professional Entitlement

Given the Organization no longer holds `APPOINTMENT_MANAGEMENT`
When an authorized Clinic actor withdraws a pending Clinic proposal
Then the withdrawal succeeds

---

### Scenario: Guardian proposal cannot be withdrawn here

Given a Guardian-originated proposal is pending
When a Clinic actor attempts to withdraw it through this workflow
Then the operation is denied

---

### Scenario: Accepted proposal cannot be withdrawn

Given a Guardian accepted the Clinic proposal
When a Clinic actor attempts to withdraw it
Then the operation fails
And the accepted confirmed time remains

---

### Scenario: Clinical Encounter prevents withdrawal

Given a Clinic proposal is pending
And a Clinical Encounter is then established for the Appointment
When a Clinic actor attempts to withdraw the proposal
Then the operation fails because the proposal is no longer actionable

---

## 5. Edge Cases

### Withdrawal outcome is not received

If the caller cannot tell whether withdrawal succeeded, a repeated attempt
fails because the proposal is no longer actionable. The caller must re-read
the Appointment to learn its authoritative state.

### Guardian opens an old proposal notification

The Guardian's current Appointment view is authoritative and no longer shows
the withdrawn proposal (`SPEC-COM-003` BR-45).

---

## 6. Relevant Invariants

* **INV-015 — Private operations require an authenticated identity.**

---

## 7. Dependencies

* SPEC-APT-005 — Propose Confirmed Appointment Reschedule
* SPEC-APT-006 — Accept Appointment Reschedule Proposal
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-APT-019 — Accept Requested Appointment Alternative Time
* SPEC-COM-003 — Send Appointment Notifications
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities

---

## 8. Out of Scope

* Guardian withdrawal of a Guardian-originated proposal;
* Guardian rejection of a proposal;
* counterproposals;
* a withdrawal reason;
* a withdrawal Communication;
* a combined withdraw-and-replace operation;
* reading the history of proposals that were never accepted.

---

## 9. Verification Notes

Verification must demonstrate that:

1. the proposing Clinic actor may withdraw an actionable Clinic proposal;
2. another current Clinic actor with `APPOINTMENT_RESCHEDULE` may withdraw it;
3. an actor of another Clinic, or without the capability, is denied;
4. withdrawal succeeds without the `APPOINTMENT_MANAGEMENT` Entitlement;
5. the proposal becomes `WITHDRAWN` with the withdrawing User and a
   system-recorded time, and is immutable afterwards;
6. the Appointment and its current scheduling context are unchanged, for a
   `CONFIRMED` base and for a `REQUESTED` base; a withdrawn `REQUESTED`-base
   proposal leaves the Appointment `REQUESTED` with no new Schedule Revision;
7. the pending-proposal slot is freed and a new proposal may be created;
8. the withdrawn proposal no longer appears as pending in the Guardian and
   Clinic reads;
9. a Guardian-originated proposal cannot be withdrawn through this workflow;
10. an accepted, already withdrawn, or otherwise non-actionable proposal
    cannot be withdrawn;
11. withdrawal and acceptance are serialized;
12. withdrawal creates no Communication and suppresses an undelivered
    `APPOINTMENT_RESCHEDULE_PROPOSED` or
    `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` notification;
13. after withdrawing a `REQUESTED`-base proposal a new Alternative Time
    proposal may be created at once, and after withdrawing a `CONFIRMED`-base
    proposal a new confirmed-reschedule proposal may be created at once.

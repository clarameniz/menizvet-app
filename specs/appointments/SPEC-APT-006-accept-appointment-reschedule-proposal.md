# SPEC-APT-006 — Accept Appointment Reschedule Proposal

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-007, REQ-APT-008, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): BR-31 conditions on Clinical Record Entries instead of an Encounter (SPEC-MED-010 BR-9). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow the counterparty of a pending reschedule proposal to explicitly accept the proposed date and time for a `CONFIRMED` Appointment.

Successful acceptance updates the confirmed scheduling commitment of the existing Appointment.

The Appointment remains the same domain entity.

The previous confirmed time and the complete rescheduling negotiation must remain historically traceable.

---

## 2. Preconditions

* The Appointment exists.
* The Appointment is currently in `CONFIRMED` state.
* A `PENDING` reschedule proposal exists for the Appointment.
* The proposal has not expired, been rejected, withdrawn, or otherwise become non-actionable.
* The proposed time is still in the future.
* The Appointment remains eligible for confirmed-time rescheduling.
* The acting User exists.
* The acting User is authenticated.
* The acting User acts through the counterparty context required by the proposal.
* The acting User has the current authorization required by that context.
* The proposed scheduling context remains valid and available at acceptance time.
* The Clinic has the current professional entitlement required to establish the new scheduling commitment where applicable.

---

## 3. Business Rules

### BR-1 — Only the counterparty may accept

A reschedule proposal must be accepted through the domain context opposite to the one that created it.

For a Guardian-originated proposal:

```text
Guardian proposes
        ↓
authorized Clinic context accepts
```

For a Clinic-originated proposal:

```text
Clinic proposes
        ↓
authorized Guardian context accepts
```

The proposing context must not approve its own proposal.

---

### BR-2 — Counterparty context does not necessarily require a different User identity

Authorization is determined by domain context rather than solely by User identity.

A User who legitimately holds both a Guardianship relationship and a professional Clinic relationship may act through either context where authorized.

However, proposal and acceptance must still represent the two distinct required domain contexts.

The same context must not both propose and accept.

---

### BR-3 — Guardian acceptance requires current Guardianship

When accepting a Clinic-originated proposal, the acting User must currently have an active Guardianship relationship with the Appointment's Pet.

Being the original requesting User is not sufficient.

---

### BR-4 — Any current Phase 1 Guardian may accept a Clinic proposal

The Guardian accepting a Clinic-originated proposal does not need to be the User who originally requested the Appointment.

Any current Phase 1 Guardian of the Pet may accept where the applicable Appointment rules permit it.

---

### BR-5 — Clinic acceptance requires current Clinic authority

When accepting a Guardian-originated proposal, the acting User must currently have a professional context that grants the capability to manage Appointments for the relevant Clinic.

Authority in another Clinic or Organization is insufficient.

---

### BR-6 — Acceptance updates the existing Appointment

Successful acceptance must change the confirmed scheduling context of the existing Appointment.

It must not cancel the Appointment and create another Appointment solely to represent the new agreed time.

Conceptually:

```text
Appointment A
CONFIRMED
10:00

Pending proposal
17:00

        ↓ accepted

Appointment A
CONFIRMED
17:00
```

There remains exactly one Appointment domain entity.

---

### BR-7 — Appointment remains CONFIRMED

Successful acceptance changes the confirmed scheduling context but does not change the Appointment lifecycle state.

The Appointment remains:

`CONFIRMED`

---

### BR-8 — Previous confirmed scheduling context must remain historically traceable

Acceptance must not silently overwrite the previous confirmed time.

The system must preserve enough information to establish:

* the previous confirmed time;
* the new confirmed time;
* who proposed the change;
* which context originated the proposal;
* when the proposal was created;
* who accepted it;
* through which context it was accepted;
* when acceptance occurred;
* the proposal reason where one existed.

---

### BR-9 — Proposal becomes ACCEPTED

Once successfully applied, the reschedule proposal must transition from:

```text
PENDING → ACCEPTED
```

An accepted proposal must no longer remain actionable.

---

### BR-10 — Acceptance requires current scheduling validity

The proposed time must be revalidated when acceptance occurs.

The fact that a time was valid when proposed must not guarantee that it remains valid later.

---

### BR-11 — Unavailable proposed time cannot be accepted

If the Clinic can no longer validly commit to the proposed time, acceptance must fail.

The Appointment must remain confirmed at its existing time.

The proposal must not be marked `ACCEPTED`.

---

### BR-12 — Acceptance must not silently choose another time

If the proposed time is unavailable, the system must not:

* choose another available time;
* modify the proposal;
* partially accept it;
* silently create a counterproposal.

A different time requires another explicit rescheduling negotiation.

---

### BR-13 — Proposed time must still be in the future

A proposal whose proposed Appointment time has already passed must not be accepted.

---

### BR-14 — Appointment must still be validly reschedulable

A proposal must not be accepted if the Appointment has become:

* `CANCELLED`;
* `COMPLETED`;
* `NO_SHOW`;
* or otherwise ineligible for confirmed-time rescheduling.

---

### BR-15 — Acceptance must be based on the scheduling context the proposal was created against

A reschedule proposal conceptually proposes replacing a specific confirmed scheduling context.

If the Appointment's confirmed time has already changed through another valid workflow, a stale proposal must not later overwrite that newer agreement.

Acceptance must verify that the Appointment still represents the confirmed scheduling context to which the proposal applies.

---

### BR-16 — Acceptance moves the scheduling commitment atomically

Successful acceptance must:

1. establish the new scheduling commitment;
2. release the previous scheduling commitment;
3. update the Appointment's current confirmed time;
4. mark the proposal as accepted;
5. preserve the scheduling history.

These effects form one logical domain operation.

---

### BR-17 — Failure to establish the new commitment preserves the old commitment

If the proposed time cannot be committed, the existing confirmed scheduling commitment must remain valid.

The system must never release the current confirmed time before the new scheduling commitment can be established successfully.

---

### BR-18 — Acceptance does not modify Appointment identity or parties

Accepting a reschedule proposal must not change:

* the Pet;
* the Clinic;
* the original requesting User;
* existing Guardianship relationships.

---

### BR-19 — Acceptance preserves the reason for visit

Rescheduling must not alter or remove the Appointment's reason for visit.

A reschedule reason and the veterinary reason for visit are separate concepts.

---

### BR-20 — Acceptance preserves unrelated Appointment information

Existing Guardian-provided notes and other Appointment information unrelated to scheduling must remain unchanged unless modified through another authorized workflow.

---

### BR-21 — Acceptance does not create clinical information

Accepting a reschedule proposal must not create:

* a Medical Record Entry;
* a diagnosis;
* a Treatment;
* a clinical observation;
* any other clinical statement.

---

### BR-22 — An accepted proposal cannot be accepted again

Repeated acceptance attempts must not:

* perform another scheduling change;
* create another Appointment;
* duplicate scheduling history;
* duplicate scheduling commitments;
* overwrite original acceptance information.

---

### BR-23 — Current authorization is evaluated at acceptance time

Authorization that existed when the proposal was created does not grant permanent authority to complete the scheduling change.

The accepting actor must satisfy the relevant current authorization rules when acceptance is processed.

---

### BR-24 — Loss of proposing authority makes the outstanding proposal non-actionable

A pending reschedule proposal represents an outstanding scheduling proposal from an authorized domain context.

If the proposing User no longer holds the authority required to represent that side before the proposal is accepted, the proposal must no longer be actionable.

Its historical existence must remain traceable.

For example:

* a Guardian-originated proposal becomes non-actionable if that User is no longer an authorized Guardian;
* a Clinic-originated proposal becomes non-actionable if the professional no longer holds the relevant Clinic authority.

A new authorized actor may create a new proposal where appropriate.

---

### BR-25 — Clinic unpublication does not by itself prevent acceptance

A Clinic becoming unpublished does not automatically invalidate an existing confirmed Appointment or its pending reschedule proposal.

Public visibility and internal management of existing Appointments are separate concerns.

Acceptance remains subject to current Clinic authority, scheduling validity, and professional entitlements.

---

### BR-26 — Lack of required professional entitlement prevents new scheduling commitment

Where the applicable Subscription rules require an active professional entitlement to establish or modify scheduling commitments, a proposal must not be accepted when that entitlement is absent.

This is deliberate: accepting a confirmed reschedule establishes a new confirmed
future commitment, and `SPEC-SUB-003` (`APPOINTMENT_MANAGEMENT`) and
`SPEC-SUB-004` BR-38 evaluate the Organization's `APPOINTMENT_MANAGEMENT`
Entitlement at the moment that commitment is established, whoever acts. It
differs from accepting a Clinic alternative time for a request, which creates
only another requested context (`SPEC-APT-019` BR-4). The Guardian client
learns of it only through the generic current acceptability (BR-36).

Safe cancellation of existing obligations remains a separate continuity capability and does not imply permission to create a new confirmed scheduling commitment.

---

### BR-27 — Existing Veterinarian Assignment must be valid for the newly accepted time

If the Appointment has a current assigned Veterinarian, acceptance of a
reschedule proposal must validate that the Veterinarian remains professionally
eligible under the scheduling constraints applicable to the proposed new time.

The system must not complete a reschedule while preserving a Veterinarian
Assignment that is invalid for the new confirmed scheduling context.

If the existing Veterinarian cannot validly remain assigned, the professional
Assignment must be explicitly resolved before or as part of the rescheduling
workflow according to the applicable Specifications.

---

### BR-28 — Acceptance establishes exactly the stored proposed interval

The proposal's interval is frozen when the proposal is created
(`SPEC-APT-005` BR-24). Acceptance establishes exactly that stored start
instant, end instant, and scheduling timezone as the new confirmed scheduling
context.

Acceptance never re-derives, extends, shortens, or otherwise recomputes the
proposed interval. The accepting party accepts precisely the interval that
was presented.

---

### BR-29 — Standard duration changes do not affect a pending proposal

The proposal's interval was derived from the Clinic's standard Appointment
duration current when the proposal was created (`SPEC-APT-005` BR-24) and was
frozen then. Acceptance adopts that interval: it does not read the current
standard duration and does not require one to be configured.

A change or removal of the Clinic's standard Appointment duration after the
proposal was created neither alters nor invalidates it (`SPEC-APT-013` BR-63,
BR-70), and acceptance still establishes the stored interval (BR-28) if every
other rule is satisfied. Proposals created under any earlier duration rule
are accepted in the same way, with their stored interval unchanged.

---

### BR-30 — Acceptance revalidates feasibility of the stored interval

Refining BR-10, BR-11 and BR-27, acceptance revalidates the stored proposed
interval with the same feasibility rules applied at creation
(`SPEC-APT-005` BR-28):

* Clinic Appointment Availability;
* where the Appointment has a current Veterinarian Assignment: a still-current
  Clinic Assignment, that Veterinarian's Availability, and no other currently
  known overlapping `CONFIRMED` commitment of that Veterinarian, excluding
  this Appointment.

A failure leaves the existing confirmed scheduling context unchanged, does not
mark the proposal `ACCEPTED`, and does not disclose details of a conflicting
commitment.

The authoritative protection against incompatible confirmed commitments of
the same Veterinarian, evaluated when the new commitment is established,
remains in force; the feasibility check never replaces it.

---

### BR-31 — A Clinical Encounter makes the proposal non-actionable

Once a Clinical Encounter exists for the Appointment, a pending proposal is no
longer actionable (`SPEC-APT-005` BR-29, BR-31) and must not be accepted.

---

### BR-32 — A withdrawn proposal cannot be accepted

A proposal withdrawn through `SPEC-APT-016` is no longer actionable and must
not be accepted. Withdrawal and acceptance are serialized: whichever
completes first decides the outcome, and the other fails without effect.

---

### BR-33 — Repeated or late acceptance never duplicates effects

Refining BR-22: a repeated acceptance attempt for a proposal that is already
`ACCEPTED`, `WITHDRAWN`, `VOID` (`SPEC-APT-005` BR-33), or otherwise
non-actionable fails without creating a Schedule Revision, changing the
proposal, or creating a Communication. A caller that cannot tell whether an
earlier attempt succeeded must re-read the Appointment to learn its
authoritative state.

---

### BR-34 — Acceptance facts are those of the resulting scheduling context

Refining BR-8: the acceptance of a proposal is recorded once, by the new
confirmed scheduling context it establishes. That scheduling context
identifies its source proposal, and:

* the acceptance time is the time the new scheduling context was established;
* the accepting User is the User who established it;
* the accepting context is the counterparty of the proposing context (BR-1).

These facts are not recorded a second time on the proposal, so they cannot
disagree. A proposal is the source of at most one scheduling context, and a
scheduling context has at most one source proposal.

---

### BR-35 — Only proposals on a confirmed base are accepted here

This workflow accepts only a proposal whose base is a `CONFIRMED` scheduling
context. A Clinic Alternative Time proposal on a `REQUESTED` base is accepted
only through `SPEC-APT-019`, which keeps the Appointment `REQUESTED`; an
attempt to accept it here fails without effect.

---

### BR-36 — Guardian presentation follows current acceptability

The Guardian client offers acceptance of a Clinic proposal only while the
Guardian Appointment view reports it currently acceptable (`SPEC-APT-005`
BR-35, `SPEC-APT-011` BR-32).

When the proposal is projected but not currently acceptable:

* the proposal remains visible, with the current confirmed interval, the
  proposed interval, and the Clinic's reason;
* no acceptance action is offered;
* calm, generic copy conveys: **This proposed time can't be accepted right
  now. The Appointment keeps its confirmed time.**
* the copy reveals no reason (scheduling feasibility, Veterinarian, or
  Entitlement) and does not promise that the Clinic will propose another time,
  because the condition may recover and the proposal may become acceptable
  again.

This is advisory presentation. Acceptance remains authoritative and revalidates
everything (BR-26, BR-30); after any failed attempt the client re-reads and
presents the result under this rule.

---

## 4. State Effects

Successful acceptance produces:

```text
Appointment

CONFIRMED at 10:00
        │
        │ pending proposal: 17:00
        │
        │ accepted
        ▼
CONFIRMED at 17:00
```

while the proposal transitions:

```text
PENDING → ACCEPTED
```

The Appointment remains the same domain entity.

The scheduling history preserves both confirmed contexts.

---

## 5. Scenarios

### Scenario: Clinic accepts a Guardian-originated proposal

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro for 10:00
And Maria is an active Guardian of Luna
And Maria validly proposed moving the Appointment to 17:00
And the proposal is `PENDING`
And 17:00 remains valid and available
And Carlos has current authority to manage Appointments for Animalia Madrid Centro

When Carlos accepts the proposal through the Clinic context

Then the same Appointment remains `CONFIRMED`
And its current confirmed time becomes 17:00
And the previous 10:00 confirmed time remains historically traceable
And the proposal becomes `ACCEPTED`
And Carlos is recorded as the accepting User
And the acceptance context is recorded as Clinic

---

### Scenario: Guardian accepts a Clinic-originated proposal

Given Luna has a `CONFIRMED` Appointment for 10:00
And Animalia Madrid Centro validly proposed moving it to 17:00
And Maria has an active Guardianship relationship with Luna
And the proposal is `PENDING`
And 17:00 remains valid

When Maria accepts the proposal through the Guardian context

Then the same Appointment remains `CONFIRMED`
And its current confirmed time becomes 17:00
And the previous confirmed time remains historically traceable
And the proposal becomes `ACCEPTED`
And Maria is recorded as the accepting User

---

### Scenario: Another current Guardian may accept a Clinic proposal

Given Carlos originally requested Luna's Appointment
And Animalia Madrid Centro has proposed a new time
And Maria also has an active Guardianship relationship with Luna

When Maria validly accepts the Clinic-originated proposal

Then the proposal may be accepted
And Carlos remains historically identifiable as the original requester
And Maria is recorded as the accepting Guardian
And the same Appointment receives the newly agreed confirmed time

---

### Scenario: Guardian cannot accept Guardian-originated proposal

Given Maria proposed a new Appointment time through her Guardian context
And the proposal is `PENDING`

When Maria attempts to accept the proposal through the Guardian context

Then the operation is denied
And the proposal remains unaccepted
And the current confirmed Appointment time remains unchanged

---

### Scenario: Clinic cannot accept its own Clinic-originated proposal

Given an authorized Clinic actor created a Clinic-originated reschedule proposal

When another User attempts to accept it solely through the Clinic context

Then the operation is denied
And acceptance through an authorized Guardian context is still required

---

### Scenario: Same User holds both contexts

Given Maria is an active Guardian of Luna
And Maria also has professional Appointment-management authority at Animalia Madrid Centro
And Maria created a reschedule proposal through the Clinic context

When Maria explicitly acts through her Guardian context and satisfies all Guardian authorization requirements to accept it

Then the two actions are evaluated as distinct domain contexts
And User identity alone neither grants nor prevents acceptance

---

### Scenario: Former Guardian cannot accept

Given Animalia Madrid Centro proposed a new time
And Carlos was previously a Guardian of Luna
And Carlos no longer has an active Guardianship relationship with Luna

When Carlos attempts to accept the proposal

Then the operation is denied
And the Appointment remains at its current confirmed time

---

### Scenario: Professional from another Clinic cannot accept Guardian proposal

Given Maria proposed a new time for Luna through the Guardian context
And Carlos may manage Appointments at Animalia Getafe
And Carlos has no applicable authority at Animalia Madrid Centro

When Carlos attempts to accept Maria's proposal

Then the operation is denied
And the current confirmed time remains unchanged

---

### Scenario: Proposed time is no longer available

Given Luna's Appointment is confirmed for 10:00
And a pending proposal exists for 17:00
And 17:00 is no longer validly available

When the authorized counterparty attempts to accept the proposal

Then acceptance is rejected
And the proposal does not become `ACCEPTED`
And the Appointment remains confirmed for 10:00
And the 10:00 scheduling commitment remains valid

---

### Scenario: Acceptance does not silently choose another time

Given a pending proposal exists for 17:00
And 17:00 is no longer available
And 18:00 is available

When acceptance is attempted

Then the Appointment remains confirmed at its existing time
And it is not moved to 18:00
And no proposal for 18:00 is created automatically

---

### Scenario: Proposed time has passed

Given a pending reschedule proposal exists
And the proposed Appointment time has already passed

When the counterparty attempts to accept it

Then acceptance is rejected
And the Appointment's current confirmed scheduling context remains unchanged

---

### Scenario: Appointment was cancelled while proposal was pending

Given Luna has a pending reschedule proposal
And the Appointment is subsequently validly cancelled

When acceptance of the proposal is attempted

Then the operation is denied
And the Appointment remains `CANCELLED`
And the proposal does not become `ACCEPTED`

---

### Scenario: Stale proposal cannot overwrite a newer confirmed time

Given a proposal was created to replace a confirmed 10:00 Appointment with 17:00
And the Appointment's confirmed scheduling context has subsequently validly changed through another workflow

When acceptance of the older proposal is attempted

Then the operation is denied
And the newer confirmed scheduling context remains unchanged
And the stale proposal does not overwrite it

---

### Scenario: Successful acceptance releases old commitment

Given Luna's Appointment is confirmed for 10:00
And a valid pending proposal exists for 17:00
And 17:00 can be validly committed

When the authorized counterparty accepts the proposal

Then 17:00 becomes the current scheduling commitment
And 10:00 is released from the current scheduling commitment
And the Appointment remains `CONFIRMED`
And both scheduling contexts remain historically traceable

---

### Scenario: Failed acceptance preserves old commitment

Given Luna's Appointment is confirmed for 10:00
And a pending proposal exists for 17:00

When establishing the 17:00 commitment fails

Then the Appointment remains confirmed for 10:00
And the 10:00 scheduling commitment is not released
And the proposal does not become `ACCEPTED`

---

### Scenario: Accepted proposal cannot be reused

Given a reschedule proposal has already been successfully accepted

When acceptance of the same proposal is attempted again

Then no scheduling change occurs
And no duplicate scheduling history is created
And no additional Appointment is created

---

### Scenario: Guardian proposer loses Guardianship before acceptance

Given Maria validly proposed a new time through her Guardian context
And the proposal remains pending
And Maria later ceases to have an active Guardianship relationship with Luna

When an authorized Clinic actor attempts to accept Maria's previous proposal

Then the proposal is no longer actionable
And the Appointment remains at its current confirmed time
And Maria's historical proposal remains traceable

---

### Scenario: Clinic proposer loses professional authority before acceptance

Given Carlos validly proposed a new time through the Clinic context
And the proposal remains pending
And Carlos later loses the professional authority required to manage Appointments at that Clinic

When an authorized Guardian attempts to accept Carlos's previous proposal

Then the proposal is no longer actionable
And the current confirmed Appointment time remains unchanged
And Carlos's historical proposal remains traceable

---

### Scenario: Clinic is unpublished before acceptance

Given Animalia Madrid Centro has a confirmed Appointment for Luna
And a valid pending reschedule proposal exists
And the Clinic is subsequently unpublished
And the Clinic remains operational with the required professional entitlements

When the authorized counterparty accepts the proposal

Then unpublication alone does not prevent acceptance
And all other scheduling and authorization rules still apply

---

### Scenario: Required professional entitlement is no longer active

Given a pending reschedule proposal exists for an Appointment
And the Organization no longer has the professional entitlement required to establish a new scheduling commitment

When acceptance is attempted

Then the proposal is not accepted
And the current confirmed Appointment remains unchanged
And safe cancellation capabilities remain governed separately

---

### Scenario: Assigned Veterinarian is unavailable at proposed new time

Given Luna has a `CONFIRMED` Appointment for 10:00
And Dr. Garcia is the current assigned Veterinarian
And a valid reschedule proposal exists for 17:00
And Dr. Garcia is not professionally available or eligible for 17:00

When the counterparty attempts to accept the reschedule proposal

Then the system must not establish a confirmed 17:00 Appointment while
silently preserving Dr. Garcia as its valid assigned Veterinarian
And the professional Assignment incompatibility must be explicitly resolved
before the rescheduling operation can reach a valid final state

---

## 6. Rescheduling History

Successful acceptance must allow the Appointment's scheduling history to be understood conceptually as:

```text
Appointment A

Original request:
10 September, 10:00
Requested by: Maria

Confirmed:
10 September, 10:00
Confirmed by: Carlos

Reschedule proposal:
10 September, 17:00
Proposed by: Maria
Context: Guardian

Accepted:
12 August, 11:42
Accepted by: Carlos
Context: Clinic

Current confirmed time:
10 September, 17:00
```

The exact persistence model is not defined by this Specification.

The requirement is historical traceability.

---

## 7. Atomicity

Acceptance involves several related effects:

```text
validate proposal
        ↓
validate counterparty authorization
        ↓
validate current Appointment context
        ↓
validate proposed scheduling capacity
        ↓
acquire new commitment
        ↓
release previous commitment
        ↓
update Appointment time
        ↓
accept proposal
        ↓
preserve history
```

From the domain perspective, this behaves as one logical operation.

Partial success must not be externally observable as a valid final state.

---

## 8. Edge Cases

### Scheduling capacity changes during acceptance

Availability may change while acceptance is being processed.

The operation must either establish one coherent new scheduling commitment or leave the existing confirmed commitment unchanged.

The concurrency-control mechanism is architectural.

---

### Guardian authorization changes during acceptance

Current Guardianship must be evaluated as part of the acceptance operation.

Stale client state must not authorize acceptance after Guardianship has ceased.

---

### Professional authorization changes during acceptance

Current Clinic authority must be evaluated as part of the operation.

Historical authority must not grant current acceptance capabilities.

---

### Communication delivery fails

Failure to send a rescheduling confirmation email or push notification must not undo an otherwise valid accepted reschedule.

Appointment state and communication delivery remain separate concerns.

---

### Proposal remains visible historically after becoming non-actionable

A proposal that can no longer be accepted may remain part of the Appointment's scheduling history.

Historical visibility must not be confused with current actionability.

---

## 9. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-013 — Subscription termination does not erase history.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 10. Dependencies

* SPEC-APT-002 — Confirm Appointment
* SPEC-APT-003 — Cancel Appointment
* SPEC-APT-005 — Propose Confirmed Appointment Reschedule
* SPEC-ID-003 — Authenticate User
* SPEC-PET-003 — Accept Guardianship Invitation

Professional Clinic authorization follows the applicable Organization and Clinic Assignment Specifications.

Professional entitlement behavior is refined by the Subscription Specifications.

---

## 11. Out of Scope

This Specification does not define:

* rejecting a reschedule proposal;
* withdrawing a proposal (`SPEC-APT-016`);
* proposal expiration duration;
* automatic acceptance;
* temporary scheduling holds;
* notifications;
* rescheduling fees;
* changing the Appointment's Pet;
* changing the Appointment's Clinic;
* Appointment cancellation;
* Appointment completion;
* no-show classification;
* exact scheduling-capacity implementation;
* exact subscription-entitlement implementation.

---

## 12. Verification Notes

Verification must demonstrate that:

1. only the required counterparty context may accept a proposal;
2. current authorization is required at acceptance time;
3. any current Guardian may accept a valid Clinic-originated proposal in Phase 1;
4. Clinic acceptance requires current authority for the Appointment's Clinic;
5. proposal and acceptance contexts remain distinguishable even if the same User holds both;
6. the existing Appointment is updated rather than replaced;
7. the Appointment remains `CONFIRMED`;
8. previous and new confirmed scheduling contexts remain historically traceable;
9. successful acceptance changes the proposal from `PENDING` to `ACCEPTED`;
10. proposed scheduling validity is re-evaluated at acceptance time;
11. unavailable or past proposed times cannot be accepted;
12. failed acceptance preserves the previous confirmed scheduling commitment;
13. acceptance never silently selects another time;
14. stale proposals cannot overwrite a newer scheduling context;
15. acquiring the new commitment, releasing the old one, updating the Appointment, and accepting the proposal behave atomically;
16. Pet, Clinic, requester, reason for visit, and unrelated Appointment information remain unchanged;
17. accepted proposals cannot be reused;
18. proposals become non-actionable if the authority of the proposing context is lost before acceptance;
19. Clinic unpublication alone does not prevent rescheduling existing Appointments;
20. absence of a required professional entitlement prevents creation of the new scheduling commitment without erasing the existing Appointment;
21. the new confirmed scheduling context equals the stored proposed interval
    exactly (BR-28);
22. acceptance does not read the standard duration: a standard-duration
    change or removal after proposal creation neither changes nor invalidates
    acceptance, which establishes the exact frozen interval (BR-29);
23. acceptance revalidates Clinic Availability, the assigned Veterinarian's
    Clinic Assignment and Availability, and known Veterinarian conflicts,
    failing atomically without disclosing the conflict (BR-30);
24. acceptance is rejected once a Clinical Encounter exists (BR-31);
25. a withdrawn proposal cannot be accepted, and acceptance and withdrawal are
    serialized (BR-32);
26. a repeated acceptance creates no duplicate revision or Communication
    (BR-33);
27. the acceptance time, accepting User, and accepting context are exactly
    reconstructible from the resulting scheduling context, and an accepted
    proposal is the source of exactly one scheduling context (BR-34);
28. a proposal on a `REQUESTED` base cannot be accepted through this workflow
    (BR-35);
29. the Guardian client offers acceptance only while the proposal is reported
    currently acceptable; otherwise the proposal stays visible with generic
    copy and no acceptance action, and the copy reveals no reason (BR-36);
30. the acceptance-time `APPOINTMENT_MANAGEMENT` requirement is unchanged and
    remains authoritative whatever the read reported (BR-26, BR-36).

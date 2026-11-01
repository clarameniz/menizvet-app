# SPEC-APT-003 — Cancel Appointment

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-006, REQ-APT-008, REQ-SUB-004
**Domain:** Appointments
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the Clinical Encounter prohibition reads as "at least one Clinical Record Entry exists for the Appointment" (SPEC-MED-010 BR-9). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized actor to cancel an existing Appointment while preserving the Appointment as historical information.

Cancellation represents that the planned veterinary visit will no longer take place under the current Appointment.

Cancelling an Appointment must not delete it.

---

## 2. Preconditions

* The Appointment exists.
* The Appointment is in a cancellable lifecycle state.
* The acting User exists.
* The acting User is authenticated.
* The acting User is authorized to cancel the Appointment through either:

  * a current Guardianship relationship with the Pet; or
  * an applicable professional Clinic context.
* The Appointment has not already reached a terminal state that prevents normal cancellation.
* For a Guardian cancellation of a `CONFIRMED` Appointment only: the latest
  confirmed scheduled start is still strictly in the future, according to
  authoritative backend time (BR-31).
* For a Clinic cancellation only: the caller identifies the scheduling context
  it reviewed, by its schedule revision sequence (BR-24), and that reviewed
  context is still the Appointment's current scheduling context.

---

## 3. Business Rules

### BR-1 — Cancellation preserves the Appointment

Cancelling an Appointment must transition its lifecycle state rather than delete the Appointment.

The Appointment must remain historically identifiable.

---

### BR-2 — Requested and confirmed Appointments may be cancelled

The standard cancellation workflow applies to Appointments in:

* `REQUESTED`, only while it remains a pending request (BR-23);
* `CONFIRMED` — by an authorized Clinic actor at any time while it remains
  `CONFIRMED` (BR-24 to BR-28), and by a Guardian only while its latest
  confirmed scheduled start is still in the future (BR-31).

Successful cancellation transitions the Appointment to:

```text
CANCELLED
```

---

### BR-3 — Cancellation is a terminal transition for the current Appointment

A cancelled Appointment must not later be restored to `REQUESTED` or `CONFIRMED` through this workflow.

If veterinary care is later rescheduled, the applicable rescheduling or new-Appointment workflow must be used.

---

### BR-4 — Current Guardians may cancel Guardian-managed Appointments

An active Guardian of the Pet may cancel an Appointment when the applicable Guardian-facing Appointment rules permit it, including the pending-request rule (BR-23) and the confirmed-start cutoff (BR-31).

The Guardian does not need to be the User who originally requested the Appointment.

---

### BR-5 — Requester status alone does not grant cancellation authority

The User who originally requested the Appointment remains historically identifiable.

However, being the original requester does not grant permanent cancellation authority.

If that User no longer has the required current Guardianship relationship with the Pet, requester status alone must not allow them to cancel the Appointment.

---

### BR-6 — Authorized Clinic actors may cancel Appointments

A User acting within an authorized professional context for the Appointment's Clinic may cancel the Appointment when their assigned responsibilities grant that capability.

Authentication or Organization Membership alone is insufficient.

---

### BR-7 — Capabilities in another Clinic do not grant cancellation authority

Professional Appointment-management capabilities are scoped to the relevant Clinic context.

Authorization in another Clinic or Organization does not allow cancellation of the Appointment.

---

### BR-8 — Cancellation must preserve who cancelled the Appointment

The system must preserve:

* the cancelling User;
* the cancellation time;
* the context in which cancellation occurred.

Guardian cancellation and Clinic cancellation must remain distinguishable where relevant.

---

### BR-9 — Cancellation reason depends on cancellation context

The system must support recording a reason for cancellation.

When an Appointment is cancelled by an authorized Clinic actor, a meaningful
cancellation reason is required.

When an Appointment is cancelled by an authorized Guardian, a cancellation
reason is optional.

A cancellation reason must not be treated as clinical information or as a
Medical Record Entry.

A recorded cancellation reason, whether given by a Guardian or by the Clinic,
is part of the cancelled Appointment's history that its current Guardians may
see (`SPEC-APT-011` BR-31).

---

### BR-10 — Cancellation preserves original Appointment context

Cancellation must not change:

* the Pet;
* the Clinic;
* the original requesting User;
* the originally requested scheduling context;
* historical confirmation information where applicable.

These remain part of the Appointment's history.

---

### BR-11 — Cancellation does not delete or modify Guardianship

Cancelling an Appointment must not:

* create Guardianship;
* remove Guardianship;
* change Guardian permissions.

---

### BR-12 — Cancellation does not create clinical information

Cancelling an Appointment must not automatically create:

* a Medical Record Entry;
* a diagnosis;
* a Treatment;
* another clinical event.

---

### BR-13 — An already cancelled Appointment cannot be cancelled again

Repeated cancellation attempts must not:

* create another Appointment;
* create duplicate cancellation history;
* overwrite the original cancellation actor or time;
* change the Appointment back into another lifecycle state.

---

### BR-14 — Completed Appointments cannot be cancelled through the normal workflow

An Appointment that has already been completed must not transition to `CANCELLED`.

Administrative correction of incorrectly recorded historical state, if required, must use a separate explicit workflow.

---

### BR-15 — No-show Appointments cannot be cancelled through the normal workflow

Once an Appointment has been validly classified as `NO_SHOW`, normal cancellation must no longer apply.

---

### BR-16 — Cancellation releases future scheduling commitment

When a confirmed Appointment is cancelled, scheduling capacity reserved exclusively for that Appointment must no longer remain committed to it.

The exact availability representation is an architectural concern.

---

### BR-17 — Cancellation state and scheduling release are atomic

The system must not expose a state where:

* the Appointment is `CANCELLED` but still consumes exclusive scheduling capacity; or
* scheduling capacity has been released while the Appointment remains validly `CONFIRMED`.

The cancellation and scheduling-release effects form one logical domain operation.

---

### BR-18 — Clinic unpublication does not prevent cancellation of existing Appointments

A Clinic that has been unpublished may still cancel existing Appointments through an authorized internal professional context.

Public visibility and internal Appointment management are separate concerns.

---

### BR-19 — Subscription loss must not prevent safe cancellation of existing Appointments

An Organization that no longer has normal paid professional entitlements must still be able to perform the limited actions necessary to safely cancel existing Appointments when applicable.

Subscription loss must not force the Clinic to leave a Guardian with an Appointment that it can no longer honor and cannot cancel.

This limited continuity capability does not imply continued access to normal paid professional functionality.

Detailed subscription-expiration behavior is defined by the Subscription Specifications.

---

### BR-20 — Cancellation does not imply deletion of Appointment communication history

Where Appointment-related transactional communications exist, cancellation must not require historical communication records to be erased.

Communication history and Appointment state remain separate concerns.

---

### BR-21 — Expired Appointments cannot be cancelled

An Appointment that is `EXPIRED` (`SPEC-APT-015`) must not transition to
`CANCELLED`.

`EXPIRED` is already a terminal outcome.

---

### BR-22 — Expiry is not cancellation

An unconfirmed request whose requested time has passed is expired by the
system (`SPEC-APT-015`); it is not cancelled.

The system must not record expiry as `CANCELLED`, must not create a
cancellation actor, context, or reason for it, and must not send an
`APPOINTMENT_CANCELLED` Communication because a request expired.

---

### BR-23 — A requested Appointment may be cancelled only while it is pending

A `REQUESTED` Appointment may be cancelled only while its latest requested
scheduled start instant is still strictly in the future, according to
authoritative backend time.

Once that instant is no longer in the future, the request is logically expired
(`SPEC-APT-015` BR-4, BR-18). Cancellation must then be rejected, even if the
Appointment's persisted lifecycle state has not yet been updated to `EXPIRED`.

This applies equally to Guardian cancellation and Clinic cancellation.

A cancellation rejected under this rule must not create:

* a cancellation Lifecycle Event;
* any Appointment lifecycle change;
* a Care Authorization ending;
* an `APPOINTMENT_CANCELLED` Communication.

The scheduled expiry process later records the `EXPIRED` outcome. Its timing
never decides whether such a request ends as `CANCELLED` or `EXPIRED`.

This rule does not change cancellation of `CONFIRMED` Appointments.

---

### BR-24 — Clinic cancellation is bound to the reviewed scheduling context

Every requested or confirmed scheduling context of an Appointment is
established as a Schedule Revision identified within that Appointment by its
revision sequence. A requested Appointment may receive later requested contexts
(`SPEC-APT-004`), and a confirmed Appointment may receive later confirmed
contexts through an accepted reschedule (`SPEC-APT-005`, `SPEC-APT-006`).

A Clinic cancellation must cancel only the scheduling context the cancelling
actor reviewed. The Clinic caller must therefore supply the expected schedule
revision sequence: the revision sequence of the scheduling context it
reviewed, as exposed by the Clinic Appointment Schedule
(`current_schedule_revision_sequence`, `SPEC-APT-012` BR-43).

The reviewed scheduling context is the one that supplies the Appointment's
relevant scheduled interval (`SPEC-APT-012` §4):

* for a `REQUESTED` Appointment, its latest requested scheduling context;
* for a `CONFIRMED` Appointment, its latest confirmed scheduling context.

The expected schedule revision sequence is required for every Clinic
cancellation. A missing or non-positive value is an invalid request and is
rejected before any state is changed. No Clinic cancellation path may omit it.

This rule applies only to Clinic cancellation. Guardian cancellation is
governed by BR-29.

---

### BR-25 — Clinic cancellation evaluation order

A Clinic cancellation is evaluated in this order, within one serialized
operation:

1. the acting User must be authenticated and resolve to a domain User;
2. structurally invalid input is rejected before any Appointment state is
   consulted: a missing or non-positive expected schedule revision sequence
   (BR-24), and a missing or meaningless Clinic cancellation reason (BR-9);
3. the acting User's current Clinic cancellation authority is evaluated
   (BR-6, BR-7), and the Appointment is protected against concurrent
   modification under the existing lock order;
4. the Appointment must still be in a cancellable lifecycle state, `REQUESTED`
   or `CONFIRMED` (BR-2, BR-13 to BR-15, BR-21);
5. the Appointment's current scheduling context for that lifecycle state is
   loaded: its latest requested scheduling context while `REQUESTED`, its
   latest confirmed scheduling context while `CONFIRMED`;
6. that context's revision sequence is compared with the expected schedule
   revision sequence;
7. if they differ, the cancellation is rejected as stale (BR-26);
8. only then are the remaining cancellation rules evaluated, unchanged: a
   `REQUESTED` Appointment must still be pending (BR-23, `SPEC-APT-015`), no
   Clinical Encounter may exist for the Appointment, and the
   Appointment-derived Care Authorization must be coherent with the
   Appointment;
9. the cancellation effects are established exactly as without this rule
   (BR-1, BR-8, BR-16, BR-17, and the Care Authorization and Communication
   effects of `SPEC-ACC-001` and `SPEC-COM-003`).

Because the lifecycle check precedes the revision check, an Appointment that
another actor or process has already made `CANCELLED`, `COMPLETED`, `NO_SHOW`,
or `EXPIRED` is rejected as an invalid lifecycle transition, not as a stale
cancellation, even when the supplied sequence was current when reviewed.

A matching expected schedule revision sequence never bypasses any rule in
step 8.

---

### BR-26 — Stale Clinic cancellation fails without side effects

If the expected schedule revision sequence differs from the revision sequence
of the Appointment's current scheduling context (BR-25 steps 5 to 7), the
Clinic cancellation must fail.

A stale Clinic cancellation must not create or change:

* a cancellation Lifecycle Event;
* the Appointment lifecycle state;
* the cancelling User, context, or reason;
* the Appointment-derived Care Authorization;
* an `APPOINTMENT_CANCELLED` Communication;
* any Schedule Revision, reschedule Proposal, or Veterinarian Assignment.

The Clinic actor must re-read the Appointment and explicitly review its current
scheduling context before attempting cancellation again.

The stale outcome follows the repository's established optimistic-concurrency
convention for a deterministic client-input revision mismatch: an ordinary
raised exception (SQLSTATE `P0001`) with the stable, distinct message
`Stale Appointment schedule revision for cancellation`. It must not use a
SQLSTATE or HTTP status that PostgREST or the client library treats as
transient and retries automatically, such as `40001` or `PT409`, because
retrying with the same stale expected sequence can never succeed.

---

### BR-27 — Revision sequence, not presented time, determines staleness

Staleness of a Clinic cancellation is determined only by comparing revision
sequences.

A Clinic cancellation made with a superseded expected schedule revision
sequence must fail even when the current scheduling context has:

* the same start instant;
* the same formatted local date and time;
* only a different end instant, duration, or scheduling timezone.

The cancellation operation must not compare presented or client-supplied
scheduling values in place of the revision sequence, and the caller does not
supply an authoritative interval.

---

### BR-28 — Stale safety does not change what may be cancelled

The expected schedule revision sequence only binds a Clinic cancellation to the
reviewed scheduling context. It does not change:

* the `APPOINTMENT_CANCEL` capability requirement (BR-6, BR-7);
* the absence of a professional Entitlement requirement for safe cancellation
  (BR-19, `SPEC-SUB-004`);
* the Clinic cancellation reason requirement (BR-9);
* the cancellable lifecycle states and terminal-state rules (BR-2, BR-13 to
  BR-15, BR-21);
* the pending-request rule for `REQUESTED` Appointments (BR-22, BR-23);
* the prohibition on cancelling an Appointment with a Clinical Encounter;
* the ending of the Appointment-derived Care Authorization with
  `APPOINTMENT_CANCELLED`;
* the `APPOINTMENT_CANCELLED` Communication.

Whether a `CONFIRMED` Appointment whose latest confirmed scheduled start has
been reached may be cancelled is decided by BR-31, not by the expected schedule
revision sequence: a Clinic actor may still cancel it; a Guardian may not.

---

### BR-29 — Guardian cancellation is unchanged by Clinic stale safety

BR-24 to BR-27 apply only to Clinic cancellation.

Guardian cancellation keeps its existing behavior and contract: it does not
supply an expected schedule revision sequence, and its authorization, optional
reason, lifecycle, pending-request, Care Authorization, and Communication rules
are unchanged.

Guardian cancellation of a `CONFIRMED` Appointment is additionally subject to
the confirmed-start cutoff (BR-31). That rule is independent of BR-24 to BR-27:
it adds no expected revision sequence to the Guardian contract.

---

### BR-30 — Cancellation ends a pending Reschedule Proposal

Cancelling an Appointment that has a pending Reschedule Proposal — a confirmed
reschedule (`SPEC-APT-005`) or a Clinic Alternative Time for a request
(`SPEC-APT-018`) — makes that proposal `VOID` (`APPOINTMENT_LIFECYCLE_CHANGED`)
in the same operation (`SPEC-APT-005` BR-33). The proposal does not need to be
withdrawn first and can never be accepted afterwards. An undelivered proposal
Communication is suppressed (`SPEC-COM-003` BR-70, BR-72).

This applies equally to Guardian and Clinic cancellation. A rejected or stale
cancellation changes no proposal (BR-26).

---

### BR-31 — Guardian cancellation of a confirmed Appointment closes at its scheduled start

A Guardian may cancel a `CONFIRMED` Appointment only while the scheduled start
of its latest confirmed scheduling context is strictly in the future, according
to authoritative backend time.

Boundary:

* latest confirmed start later than the evaluation instant — the Guardian
  cancellation may proceed, subject to every other rule;
* latest confirmed start equal to or earlier than the evaluation instant — the
  Guardian cancellation is rejected.

Exactly at the scheduled start, Guardian cancellation is closed.

Once the start has been reached, the outcome belongs to the Clinic, which
resolves the Appointment as:

* `COMPLETED`, when the visit took place (`SPEC-APT-009`);
* `NO_SHOW`, when the Pet did not attend (`SPEC-APT-010`);
* `CANCELLED` through Clinic cancellation, when the Clinic itself called the
  visit off (BR-6, BR-9, BR-24 to BR-28).

Until the Clinic resolves it, the Appointment remains `CONFIRMED`. The
absence of an immediate `COMPLETED` state does not reopen Guardian
cancellation: completion is the Clinic's administrative assertion and may be
recorded after the visit (`SPEC-APT-009` BR-1, BR-2). No Veterinarian
Assignment, Clinical Encounter, or clinical documentation is required for the
Clinic's resolution.

#### Rationale

`CANCELLED` means the Appointment was intentionally ended before normal
fulfillment (`SPEC-APT-010` §6, §7). After the scheduled start, a Guardian
cancellation could rewrite an outcome that is the Clinic's to record: it could
pre-empt a `NO_SHOW` (`SPEC-APT-010` BR-25) or win a race against a
completion for a visit that actually took place. Closing Guardian cancellation
at the start keeps `CANCELLED`, `COMPLETED`, and `NO_SHOW` historically
meaningful.

#### Which start

The start is that of the Appointment's latest confirmed scheduling context,
read within the serialized cancellation operation — the same context that
supplies the Appointment's relevant scheduled interval (`SPEC-APT-011` §4,
`SPEC-APT-012` §4). In particular:

* an accepted confirmed reschedule (`SPEC-APT-006`) moves the cutoff to the
  new confirmed start, earlier or later;
* the proposed interval of a pending, unaccepted Reschedule Proposal never
  moves the cutoff;
* a Guardian cancellation carries no expected schedule revision sequence
  (BR-29), so the cutoff never depends on the interval the client displayed:
  a client that displays a superseded confirmed interval cannot cancel on the
  basis of it.

#### Authoritative time

The rule is enforced by the cancellation operation itself, using
authoritative backend time evaluated within the serialized operation — after
the Appointment is protected against concurrent modification — not the
client's clock and not a time captured before waiting for that protection.

A client may hide or disable Guardian cancellation using its own clock for
usability (`SPEC-APT-011` BR-34); that is advisory only and never replaces the
backend rule.

#### Evaluation position

For a Guardian cancellation, the cutoff is evaluated after the Guardian's
current authority (BR-4, BR-5) and the cancellable lifecycle state (BR-2,
BR-13 to BR-15, BR-21) have been established, in the same position as the
pending-request rule (BR-23) for a `REQUESTED` Appointment, and before the
Clinical Encounter prohibition and the cancellation effects.

An Appointment already given a terminal outcome is therefore rejected as an
invalid lifecycle transition, not under this rule.

The rejection must be distinguishable by the client from an invalid lifecycle
transition and from any other cancellation failure, and must not use a
SQLSTATE or HTTP status that PostgREST or the client library treats as
transient and retries automatically, such as `40001` or `PT409`: retrying can
never succeed once the start has been reached. The exact SQLSTATE and message
are an implementation decision within these constraints.

#### Zero writes

A Guardian cancellation rejected under this rule must not create or change:

* a cancellation Lifecycle Event;
* the Appointment lifecycle state;
* the cancelling User, context, or reason;
* the Appointment-derived Care Authorization;
* any Reschedule Proposal;
* any Schedule Revision or Veterinarian Assignment;
* any Communication, including `APPOINTMENT_CANCELLED`.

The Clinic's later resolution applies its own existing effects (Care
Authorization, Communications, proposal invalidation) under `SPEC-APT-009`,
`SPEC-APT-010`, or this Specification.

#### Scope of the rule

This rule applies only to Guardian cancellation of a `CONFIRMED` Appointment.
It must not be applied to:

* Clinic cancellation, which remains permitted after the scheduled start under
  BR-6, BR-9, and BR-24 to BR-28, with the Clinical Encounter prohibition
  unchanged;
* a `REQUESTED` Appointment, which remains governed by BR-23 for both actors.

No grace period exists before or after the scheduled start. Clinic-specific
cancellation deadlines remain out of scope (§10).

---

## 4. Appointment State Transitions

This Specification establishes:

```text
REQUESTED
    │
    └── cancel ──→ CANCELLED

CONFIRMED
    │
    └── cancel ──→ CANCELLED
```

A Guardian may take the `CONFIRMED → CANCELLED` transition only while the
latest confirmed scheduled start is in the future (BR-31); a Clinic actor may
take it while the Appointment remains `CONFIRMED` (BR-24 to BR-28). A
`REQUESTED` Appointment may be cancelled only while it is pending (BR-23).

It does not establish:

```text
COMPLETED → CANCELLED
NO_SHOW   → CANCELLED
CANCELLED → CONFIRMED
CANCELLED → REQUESTED
```

---

## 5. Scenarios

### Scenario: Guardian cancels a requested Appointment

Given Maria has an active Guardianship relationship with Luna
And Luna has an Appointment in `REQUESTED` state
And Maria is authorized to manage Luna's Appointment

When Maria cancels the Appointment

Then the Appointment state becomes `CANCELLED`
And the Appointment remains historically identifiable
And Maria is recorded as the cancelling User
And the cancellation time is preserved

---

### Scenario: Requested Appointment whose time has passed cannot be cancelled

Given Luna's Appointment is `REQUESTED` for 10:00
And it was never confirmed
And 10:00 has passed
And its `EXPIRED` outcome has not yet been materialized

When a current Guardian attempts to cancel it
Or an authorized Clinic actor attempts to cancel it with a reason

Then both attempts are rejected
And no cancellation Lifecycle Event is created
And the Care Authorization is not ended by the attempt
And no `APPOINTMENT_CANCELLED` Communication is created

When the expiry process later runs

Then the Appointment becomes `EXPIRED`
And the outcome is the same as if expiry had run before the attempt

---

### Scenario: Guardian cancels a confirmed Appointment

Given Maria has an active Guardianship relationship with Luna
And Luna has an Appointment in `CONFIRMED` state
And its latest confirmed scheduled start is still in the future

When Maria validly cancels the Appointment

Then the Appointment becomes `CANCELLED`
And the previous confirmation remains historically identifiable
And the Appointment no longer consumes its exclusive scheduling commitment

---

### Scenario: Another current Guardian cancels the Appointment

Given Carlos originally requested an Appointment for Luna
And Maria also has an active Guardianship relationship with Luna
And the Appointment is cancellable

When Maria validly cancels the Appointment

Then the Appointment becomes `CANCELLED`
And Carlos remains recorded as the original requesting User
And Maria is recorded as the cancelling User

---

### Scenario: Former Guardian cannot cancel solely because they requested the Appointment

Given Carlos originally requested an Appointment for Luna
And Carlos no longer has an active Guardianship relationship with Luna
And Carlos has no other applicable authorization

When Carlos attempts to cancel the Appointment

Then the operation is denied
And requester status alone does not authorize cancellation
And the Appointment remains unchanged

---

### Scenario: Authorized Clinic actor cancels an Appointment

Given Luna has a confirmed Appointment at Animalia Madrid Centro
And Maria has an active professional context for Animalia Madrid Centro
And Maria's responsibilities grant the capability to manage Appointments

When Maria cancels Luna's Appointment

Then the Appointment becomes `CANCELLED`
And Maria is recorded as the cancelling User
And the Clinic cancellation context remains identifiable

---

### Scenario: Professional from another Clinic cannot cancel

Given Luna has an Appointment at Animalia Madrid Centro
And Maria may manage Appointments at Animalia Getafe
And Maria has no applicable Appointment-management capability at Animalia Madrid Centro

When Maria attempts to cancel Luna's Madrid Appointment

Then the operation is denied
And the Appointment remains unchanged

---

### Scenario: Already cancelled Appointment is not cancelled again

Given Luna's Appointment is already `CANCELLED`

When cancellation is attempted again

Then the Appointment remains `CANCELLED`
And no duplicate cancellation history is created
And the original cancellation information remains unchanged

---

### Scenario: Completed Appointment cannot be cancelled

Given Luna's Appointment is `COMPLETED`

When cancellation is attempted through the normal cancellation workflow

Then the operation is denied
And the Appointment remains `COMPLETED`

---

### Scenario: No-show Appointment cannot be cancelled

Given Luna's Appointment is `NO_SHOW`

When cancellation is attempted through the normal cancellation workflow

Then the operation is denied
And the Appointment remains `NO_SHOW`

---

### Scenario: Cancellation preserves Pet and Clinic

Given Luna has a confirmed Appointment at Animalia Madrid Centro

When the Appointment is validly cancelled

Then the Appointment remains associated with Luna
And the Appointment remains associated with Animalia Madrid Centro
And neither domain identity is changed

---

### Scenario: Cancellation does not create clinical information

Given Luna has a cancellable Appointment

When the Appointment is cancelled

Then no Medical Record Entry is created solely because of cancellation
And no diagnosis is created
And no Treatment is created

---

### Scenario: Unpublished Clinic cancels an existing Appointment

Given Animalia Madrid Centro has been unpublished
And Luna has an existing cancellable Appointment at that Clinic
And Maria remains authorized to manage existing Appointments for the Clinic

When Maria cancels Luna's Appointment

Then the Appointment may be cancelled
And Clinic unpublication does not prevent the safe management of the existing Appointment

---

### Scenario: Organization without normal paid entitlements cancels an existing Appointment

Given Animalia Veterinary Group no longer has normal paid professional entitlements
And Luna has an existing confirmed Appointment that Animalia can no longer honor
And Maria has the limited authorization required to safely manage that existing Appointment

When Maria cancels the Appointment

Then the Appointment becomes `CANCELLED`
And the Guardian is not left with an Appointment that the Clinic cannot honor
And Animalia does not gain normal paid professional capabilities solely because cancellation was permitted

---

### Scenario: Clinic cancellation requires a reason

Given Luna has a cancellable Appointment at Animalia Madrid Centro
And Maria is authorized to manage Appointments for the Clinic

When Maria attempts to cancel the Appointment without providing a cancellation reason

Then the cancellation is rejected
And the Appointment remains unchanged

---

### Scenario: Guardian may cancel without providing a reason

Given Carlos has an active Guardianship relationship with Luna
And Luna has a cancellable Appointment

When Carlos cancels the Appointment without providing a cancellation reason

Then the Appointment becomes `CANCELLED`
And the absence of a cancellation reason does not prevent the cancellation

---

### Scenario: Clinic cancels a pending request it reviewed

Given Luna's Appointment is `REQUESTED` for a future 10:00
And its latest requested scheduling context has revision sequence N
And Maria, authorized to cancel Appointments at the Clinic, reviews revision N
in the Clinic Appointment Schedule

When Maria cancels the Appointment with a reason and expected schedule revision
sequence N

Then the Appointment becomes `CANCELLED`
And Maria is recorded as the cancelling User in the Clinic context with her
reason
And the Appointment-derived Care Authorization is ended with
`APPOINTMENT_CANCELLED`
And the current Guardians may receive the `APPOINTMENT_CANCELLED` Communication

---

### Scenario: Guardian reschedules a request while the Clinic reviews it

Given Maria reviewed Luna's `REQUESTED` Appointment at revision N for 10:00
And Carlos, a current Guardian, then reschedules it to 11:00
And the latest requested scheduling context is now revision N+1

When Maria cancels the Appointment with a reason and expected schedule revision
sequence N

Then the cancellation is rejected as stale
And the Appointment remains `REQUESTED` at 11:00 with revision N+1
And no cancellation Lifecycle Event, Care Authorization ending, or
`APPOINTMENT_CANCELLED` Communication is created

---

### Scenario: Clinic re-reads and cancels the current request

Given Maria's cancellation with expected revision N was rejected as stale
And Maria re-reads the Clinic Appointment Schedule and reviews revision N+1 for
11:00
And 11:00 is still in the future

When Maria cancels the Appointment with a reason and expected schedule revision
sequence N+1

Then the Appointment becomes `CANCELLED`

If 11:00 is no longer in the future, the cancellation is instead rejected under
BR-23 and the request later becomes `EXPIRED`.

---

### Scenario: Clinic cancels a future confirmed Appointment it reviewed

Given Luna's Appointment is `CONFIRMED` for a future 10:00
And its latest confirmed scheduling context has revision sequence N
And Maria reviews revision N in the Clinic Appointment Schedule

When Maria cancels the Appointment with a reason and expected schedule revision
sequence N

Then the Appointment becomes `CANCELLED`
And its confirmed scheduling commitment is released

---

### Scenario: Accepted confirmed reschedule makes the reviewed context stale

Given Maria reviewed Luna's `CONFIRMED` Appointment at revision N for 10:00
And a reschedule proposal is then accepted, establishing confirmed revision N+1
for 17:00

When Maria cancels the Appointment with a reason and expected schedule revision
sequence N

Then the cancellation is rejected as stale
And the Appointment remains `CONFIRMED` for 17:00 with revision N+1
And no cancellation Lifecycle Event, Care Authorization ending, or
`APPOINTMENT_CANCELLED` Communication is created

---

### Scenario: Superseded revision with the same visible start is still stale

Given Maria reviewed Luna's Appointment at revision N, 10:00–10:30
And a newer scheduling context, revision N+1, keeps the 10:00 start but differs
only in its end, duration, or scheduling timezone

When Maria cancels the Appointment with expected schedule revision sequence N

Then the cancellation is rejected as stale
And the equal start does not make revision N current

---

### Scenario: Another actor resolves the Appointment first

Given Maria and Jorge both reviewed Luna's Appointment at revision N
And Jorge cancels it, or a current Guardian cancels it, or it is otherwise
given a terminal outcome before Maria submits

When Maria cancels the Appointment with expected schedule revision sequence N

Then the cancellation is rejected as an invalid lifecycle transition, not as
stale
And the Appointment keeps its existing terminal outcome
And no second cancellation history is created

---

### Scenario: Clinical Encounter still prevents Clinic cancellation

Given Luna's Appointment is `CONFIRMED` at revision N
And a Clinical Encounter has been established for the Appointment
And Maria reviewed revision N

When Maria cancels the Appointment with a reason and expected schedule revision
sequence N

Then the cancellation is rejected
And a matching expected schedule revision sequence does not bypass the
Clinical Encounter rule

---

### Scenario: Clinic cancellation without the reviewed revision is invalid

Given Luna's Appointment is cancellable
And Maria is authorized to cancel Appointments at the Clinic

When Maria attempts a Clinic cancellation without an expected schedule revision
sequence, or with a non-positive one

Then the request is rejected as invalid before any Appointment state is
consulted
And the Appointment remains unchanged

---

### Scenario: Guardian cancellation is unchanged by Clinic stale safety

Given Carlos is a current Guardian of Luna
And Luna's Appointment is cancellable by a Guardian

When Carlos cancels the Appointment without supplying any schedule revision
sequence, with or without a reason

Then the Guardian cancellation is not affected by BR-24 to BR-27
And it remains subject to the pending-request rule (BR-23) and the
confirmed-start cutoff (BR-31)

---

### Scenario: Guardian cancels a confirmed Appointment shortly before its start

Given Luna's Appointment is `CONFIRMED` for 10:00
And Maria is a current Guardian of Luna

When Maria cancels the Appointment and the backend evaluates the cutoff at
09:59

Then the Appointment becomes `CANCELLED`
And the existing cancellation effects apply, including the Care Authorization
ending and the `APPOINTMENT_CANCELLED` Communication

---

### Scenario: Guardian cannot cancel a confirmed Appointment at its start

Given Luna's Appointment is `CONFIRMED` for 10:00

When Maria attempts to cancel it and the backend evaluates the cutoff at
exactly 10:00

Then the cancellation is rejected under BR-31
And the Appointment remains `CONFIRMED`

---

### Scenario: Guardian cannot cancel a confirmed Appointment after its start

Given Luna's Appointment is `CONFIRMED` for 10:00
And it is now 10:05 and the Clinic has not yet resolved it
And Maria's app still displays the Appointment as `CONFIRMED`

When Maria attempts to cancel it

Then the cancellation is rejected under BR-31
And no cancellation Lifecycle Event is created
And the Appointment remains `CONFIRMED`
And the Care Authorization is not ended or changed by the attempt
And no Reschedule Proposal changes
And no Communication is created

When the Clinic later records that the visit took place

Then the Appointment becomes `COMPLETED` under `SPEC-APT-009`

---

### Scenario: Accepted reschedule moves the Guardian cutoff

Given Luna's Appointment was `CONFIRMED` for 10:00
And a reschedule to 16:00 the same day was accepted
And Maria's app still displays the earlier 10:00 time

When Maria attempts to cancel at 12:00

Then the cutoff is evaluated against the latest confirmed start, 16:00
And the cancellation may proceed

Given instead the accepted reschedule moved the Appointment from 16:00 to 10:00
And Maria's app still displays the earlier 16:00 time

When Maria attempts to cancel at 12:00

Then the cutoff is evaluated against the latest confirmed start, 10:00
And the cancellation is rejected under BR-31

---

### Scenario: Pending proposal does not move the Guardian cutoff

Given Luna's Appointment is `CONFIRMED` for 10:00
And a pending, unaccepted Reschedule Proposal proposes 16:00

When Maria attempts to cancel at 10:30

Then the cutoff is evaluated against the confirmed start, 10:00
And the cancellation is rejected under BR-31

---

### Scenario: Guardian cancellation racing Clinic completion or no-show

Given Luna's Appointment is `CONFIRMED` for 10:00

When Maria's cancellation and a Clinic completion or no-show are submitted
around 10:00

Then the operations are serialized under the existing Appointment protection
And a Guardian cancellation evaluated before 10:00 may succeed only if it is
serialized first, after which the Clinic operation is rejected as an invalid
lifecycle transition
And a Guardian cancellation evaluated at or after 10:00 is rejected — under
BR-31 if the Appointment is still `CONFIRMED`, or as an invalid lifecycle
transition if the Clinic resolved it first
And because completion and no-show are permitted only from the start
(`SPEC-APT-009` BR-7, `SPEC-APT-010`), a Guardian cancellation and a Clinic
resolution are never both valid at the same evaluation instant

---

### Scenario: Clinic cancels a confirmed Appointment after its start

Given Luna's Appointment is `CONFIRMED` for 10:00 at revision N
And at 09:30 the Clinic's veterinarian became unavailable and the Clinic
called the visit off by phone
And the Clinic records it at 11:00

When Maria, an authorized Clinic actor, cancels the Appointment with a reason
and expected schedule revision sequence N

Then the Appointment becomes `CANCELLED`
And BR-31 does not apply, because it governs only Guardian cancellation
And the Clinical Encounter prohibition still applies

---

## 6. Cancellation Information

Cancellation must preserve sufficient information to explain the lifecycle transition.

At minimum, the domain must support:

* cancellation state;
* cancellation timestamp;
* cancelling User;
* cancellation context;
* cancellation reason where required.

The exact persistence representation is not defined by this Specification.

### Reviewed scheduling context

A Clinic cancellation request identifies the Appointment, the Clinic context,
the cancellation reason, and the expected schedule revision sequence (BR-24).
The revision sequence is domain concurrency/version information within one
Appointment; it is not a presentation identity, is not persisted as part of the
cancellation, and does not expose the Appointment's complete scheduling
history.

A Guardian cancellation request does not carry it (BR-29).

### Contract compatibility

Requiring the expected schedule revision sequence changes the Clinic
cancellation request contract. The change must be introduced through a
forward-only migration, and no form of the operation may remain executable by
authenticated callers that lets a Clinic cancellation omit the expected
schedule revision sequence, because it would bypass BR-24 to BR-27.

The Guardian cancellation contract must remain usable without change. The exact
technical signature is an implementation decision within these constraints.

---

## 7. Edge Cases

### Guardian and Clinic attempt cancellation concurrently

Concurrent cancellation attempts must result in one consistent terminal cancellation state.

The Appointment must not contain contradictory cancellation histories.

The exact concurrency-control mechanism is architectural.

---

### Guardian loses Guardianship during cancellation

Authorization must be evaluated as part of the cancellation operation.

A User whose required authorization is no longer valid when cancellation is processed must not succeed solely because authorization existed earlier.

---

### Clinic subscription expires immediately before cancellation

Safe continuity behavior must allow authorized cancellation where required to prevent an unserviceable existing Appointment from remaining active.

Normal professional capabilities remain subject to Subscription Specifications.

---

### Appointment time has already passed

A `REQUESTED` Appointment whose requested time has passed reaches the terminal
outcome `EXPIRED` through `SPEC-APT-015`, not through cancellation. It cannot be
cancelled by a Guardian or by the Clinic, whether or not its `EXPIRED` outcome
has already been materialized (BR-21, BR-23).

A `CONFIRMED` Appointment whose latest confirmed scheduled start has been
reached:

* cannot be cancelled by a Guardian (BR-31); the Guardian-facing cancellation
  workflow is not used to rewrite the outcome after the visit's scheduled
  start;
* may still be cancelled by an authorized Clinic actor, with a reason and the
  reviewed revision sequence (BR-9, BR-24 to BR-28), when the Clinic itself
  called the visit off;
* otherwise remains `CONFIRMED` until the Clinic resolves it as `COMPLETED`
  (`SPEC-APT-009`) or `NO_SHOW` (`SPEC-APT-010`). No outcome is recorded
  automatically.

Whether a Clinic client offers Clinic cancellation for such an Appointment is
a presentation choice; the backend remains authoritative.

---

### Clinic actor reviewed an older scheduling context

A current Guardian may reschedule a requested Appointment (`SPEC-APT-004`) or
accept a Clinic alternative time for it (`SPEC-APT-019`), or a reschedule
proposal may be accepted for a confirmed Appointment (`SPEC-APT-006`), after a
Clinic actor has read the Appointment and before that actor cancels it.

The Clinic cancellation then carries a superseded expected schedule revision
sequence and is rejected as stale (BR-26). The Clinic must not cancel a
scheduling context its actor did not review.

---

### Clinic cancellation outcome is not received by the caller

If the caller does not receive the outcome of a successful Clinic cancellation
and repeats it, the repeated request is rejected because the Appointment is no
longer cancellable (BR-13, BR-25). Re-reading the Appointment shows its
authoritative state.

---

### Cancellation notification fails

Failure to deliver a cancellation notification must not undo an otherwise valid cancellation.

Appointment state and communication delivery are separate concerns.

---

## 8. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-013 — Subscription termination does not erase history.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 9. Dependencies

* SPEC-APT-001 — Request Appointment
* SPEC-APT-002 — Confirm Appointment
* SPEC-APT-004 — Reschedule Requested Appointment
* SPEC-APT-005 — Propose Confirmed Appointment Reschedule
* SPEC-APT-006 — Accept Appointment Reschedule Proposal
* SPEC-APT-011 — View Guardian Appointments
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-015 — Expire Unconfirmed Appointment Request
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-APT-019 — Accept Requested Appointment Alternative Time
* SPEC-ID-003 — Authenticate User
* SPEC-PET-003 — Accept Guardianship Invitation

Professional Clinic authorization follows the applicable Organization and Clinic Assignment Specifications.

Subscription-related continuity behavior will be refined by the applicable Subscription Specifications.

---

## 10. Out of Scope

This Specification does not define:

* Appointment rescheduling;
* Appointment rejection;
* Appointment completion;
* no-show classification;
* Clinic-specific cancellation deadlines;
* any grace period for Guardian cancellation around the confirmed scheduled
  start (BR-31 defines a single cutoff at the start);
* cancellation fees;
* refund behavior;
* veterinary-service payment;
* automatic cancellation;
* waitlist promotion;
* notification-delivery implementation;
* detailed Subscription expiration behavior;
* historical administrative correction of terminal Appointment states.

---

## 11. Verification Notes

Verification must demonstrate that:

1. a current authorized Guardian may cancel a cancellable Appointment;
2. the original requester does not retain permanent cancellation authority;
3. another current Guardian may cancel where applicable;
4. an authorized Clinic actor may cancel;
5. professional authority is scoped to the relevant Clinic;
6. cancellation preserves the Appointment rather than deleting it;
7. requested and confirmed Appointments may become `CANCELLED`;
8. completed and no-show Appointments cannot use normal cancellation;
9. cancellation actor and time remain traceable;
10. Pet, Clinic, and original requester remain historically identifiable;
11. confirmed Appointment cancellation releases its scheduling commitment;
12. cancellation and scheduling release behave atomically;
13. repeated cancellation does not duplicate historical state;
14. cancellation does not create clinical information;
15. Clinic unpublication does not prevent safe cancellation of existing Appointments;
16. loss of normal subscription entitlements does not prevent limited cancellation required to safely close existing obligations.
17. Clinic-initiated cancellation requires a cancellation reason;
18. Guardian-initiated cancellation does not require a cancellation reason;
19. an `EXPIRED` Appointment cannot be cancelled;
20. expiry never produces `CANCELLED` state, cancellation history, or an
    `APPOINTMENT_CANCELLED` Communication;
21. a `REQUESTED` Appointment whose latest requested start is still in the
    future can still be cancelled normally by a Guardian or the Clinic;
22. a Guardian cancellation of a logically expired `REQUESTED` Appointment is
    rejected before its `EXPIRED` outcome is materialized;
23. a Clinic cancellation of a logically expired `REQUESTED` Appointment is
    rejected before its `EXPIRED` outcome is materialized;
24. such a rejection creates no Lifecycle Event, lifecycle change, Care
    Authorization ending, or Communication;
25. running expiry after a rejected cancellation produces `EXPIRED`;
26. the outcome of a logically expired request is identical whether or not the
    expiry process has already run when cancellation is attempted;
27. a Clinic cancellation requires an expected schedule revision sequence, and
    a missing or non-positive value is rejected as invalid input before any
    Appointment state is consulted, with no state change;
28. no executable form of the operation lets a Clinic cancellation omit the
    expected schedule revision sequence;
29. for a `REQUESTED` Appointment the expected sequence is compared with its
    latest requested scheduling context, and for a `CONFIRMED` Appointment with
    its latest confirmed scheduling context — the context whose interval and
    `current_schedule_revision_sequence` the Clinic Appointment Schedule
    returns;
30. a Clinic cancellation with the current sequence succeeds for a future
    pending `REQUESTED` Appointment and for a future `CONFIRMED` Appointment
    when every other rule holds;
31. a Clinic cancellation with a superseded sequence — after a Guardian
    requested-time reschedule or after an accepted confirmed reschedule — is
    rejected with SQLSTATE `P0001` and the stable message
    `Stale Appointment schedule revision for cancellation`, never with `40001`
    or `PT409`;
32. a stale rejection creates no cancellation Lifecycle Event, lifecycle change,
    Care Authorization ending, or `APPOINTMENT_CANCELLED` Communication, and
    changes no Schedule Revision, reschedule Proposal, or Veterinarian
    Assignment;
33. a stale rejection occurs even when the superseded and current scheduling
    contexts share the same start instant, or differ only in end, duration, or
    scheduling timezone;
34. after a stale rejection, a Clinic cancellation with the freshly read
    current sequence succeeds where the Appointment is otherwise cancellable;
35. a Clinic cancellation of an Appointment that is no longer `REQUESTED` or
    `CONFIRMED` is rejected as an invalid lifecycle transition, not as stale,
    including when it carries the sequence that was current when reviewed;
36. a matching sequence does not bypass the pending-request rule, the
    Clinical Encounter prohibition, the reason requirement, or the capability
    requirement, and Clinic cancellation still requires no professional
    Entitlement;
37. Guardian cancellation keeps its existing contract, supplies no schedule
    revision sequence, and is unaffected by BR-24 to BR-27;
38. whether a `CONFIRMED` Appointment whose scheduled start has been reached
    may be cancelled is decided by BR-31, not by the expected schedule
    revision sequence (BR-28);
39. Guardian and Clinic cancellation of a `REQUESTED` Appointment with a
    pending Clinic Alternative Time proposal makes the proposal `VOID` with
    `APPOINTMENT_LIFECYCLE_CHANGED` in the same operation, without prior
    withdrawal, and the proposal can no longer be accepted;
40. a Clinic cancellation carrying the requested revision sequence that was
    current before a Guardian accepted a Clinic alternative is rejected as
    stale and changes no proposal;
41. a current Guardian may cancel a `CONFIRMED` Appointment whose latest
    confirmed scheduled start is strictly later than the backend evaluation
    instant, with the existing effects: Lifecycle Event, `CANCELLED`, Care
    Authorization ended with `APPOINTMENT_CANCELLED`, pending proposal `VOID`,
    and `APPOINTMENT_CANCELLED` Communications (BR-31);
42. a Guardian cancellation evaluated exactly at the latest confirmed start is
    rejected (BR-31);
43. a Guardian cancellation evaluated after the latest confirmed start is
    rejected (BR-31);
44. a rejection under BR-31 creates or changes no Lifecycle Event, lifecycle
    state, cancelling actor, context, or reason, Care Authorization, Reschedule
    Proposal, Schedule Revision, Veterinarian Assignment, or Communication;
45. a rejection under BR-31 is distinguishable from an invalid lifecycle
    transition and from other cancellation failures, and is never signalled as
    a transient, automatically retried error (`40001`, `PT409`);
46. the cutoff uses the latest confirmed scheduling context at evaluation: after
    an accepted reschedule to a later start the Guardian may cancel until that
    later start, after an accepted reschedule to an earlier start that has been
    reached the Guardian is rejected, and the proposed interval of a pending
    unaccepted proposal never moves the cutoff;
47. the Guardian cancellation contract carries no expected schedule revision
    sequence; a client displaying a superseded confirmed interval cannot cancel
    on the basis of that interval;
48. the cutoff is evaluated with authoritative backend time inside the
    serialized operation, not with client-supplied or pre-lock time;
49. an Appointment already `COMPLETED`, `NO_SHOW`, or `CANCELLED` is rejected
    as an invalid lifecycle transition when a Guardian attempts cancellation,
    not under BR-31;
50. in a race with a Clinic completion or no-show, the operations are
    serialized under the existing Appointment protection; a Guardian
    cancellation can succeed only when it is evaluated before the latest
    confirmed start and serialized first, and the later Clinic operation is
    then rejected as an invalid lifecycle transition;
51. an authorized Clinic actor may still cancel a `CONFIRMED` Appointment whose
    latest confirmed start has been reached, with a reason and the current
    revision sequence, and the Clinical Encounter prohibition still applies
    (BR-31 does not apply to Clinic cancellation);
52. completion and no-show behaviour, their time rules, and their effects are
    unchanged by BR-31;
53. `REQUESTED` cancellation is unchanged and remains governed by BR-23 for
    both actors;
54. a Guardian cancellation attempt for a `CONFIRMED` Appointment with a
    Clinical Encounter is still rejected; before the start, by the Clinical
    Encounter prohibition, and from the start, under BR-31.

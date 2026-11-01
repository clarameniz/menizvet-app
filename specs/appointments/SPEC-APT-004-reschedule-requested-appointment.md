# SPEC-APT-004 — Reschedule Requested Appointment

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-007
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Allow an authorized current Guardian to change the requested date and time of an Appointment that is still in `REQUESTED` state.

Rescheduling a requested Appointment changes the requested scheduling context while preserving the identity and history of the existing Appointment.

The operation must not cancel the existing Appointment and create a replacement solely to represent a scheduling change.

---

## 2. Preconditions

* The Appointment exists.
* The Appointment is currently in `REQUESTED` state.
* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies any account verification requirement applicable to Appointment management.
* The acting User has an active Guardianship relationship with the Appointment's Pet.
* The new requested start time is valid.
* The new requested start time is in the future.
* The Appointment's Clinic remains eligible to manage the existing request.
* The Appointment's Clinic has a currently configured standard Appointment
  duration (see `SPEC-APT-013`).

---

## 3. Business Rules

### BR-1 — Rescheduling preserves Appointment identity

Changing the requested time must modify the scheduling context of the existing Appointment.

It must not create a second Appointment solely to represent the new requested time.

Conceptually:

```text
Appointment A

Requested:
2026-09-10 10:00

        ↓ reschedule

Appointment A

Requested:
2026-09-11 16:00
```

The Appointment remains the same domain entity.

---

### BR-2 — Previous requested times must remain historically traceable

Rescheduling must not silently overwrite the previous requested time in a way that destroys scheduling history.

The system must be capable of establishing:

* the previous requested time;
* the new requested time;
* who requested the change;
* when the change occurred.

The exact persistence representation is an architectural concern.

---

### BR-3 — Only REQUESTED Appointments use this workflow

This Specification applies only to Appointments in `REQUESTED` state.

A `CONFIRMED` Appointment must not have its agreed time changed through this workflow.

Changing the time of a confirmed Appointment requires separate behavior.

An `EXPIRED` Appointment (`SPEC-APT-015`) must not be rescheduled.

---

### BR-4 — Current Guardianship is required

A User may reschedule a requested Appointment only when they currently have an active Guardianship relationship with the Pet.

Being the original requesting User is not sufficient.

---

### BR-5 — Another current Guardian may reschedule

The User rescheduling the Appointment does not need to be the User who originally created it.

Any active Phase 1 Guardian of the Pet may perform this operation where the applicable Appointment rules allow it.

---

### BR-6 — Former Guardian cannot reschedule solely because they created the Appointment

The original requesting User remains historically identifiable.

However, requester status does not grant permanent Appointment-management authority.

If the User no longer has an active Guardianship relationship with the Pet, they must not be able to reschedule solely because they created the Appointment.

---

### BR-7 — Rescheduling preserves the original requester

Changing the requested time must not replace the User who originally submitted the Appointment.

The system must distinguish between:

* the original requesting User;
* the User who later requested a scheduling change.

---

### BR-8 — Rescheduling preserves the Pet

Changing the requested time must not change which Pet the Appointment concerns.

Changing the Pet requires a separate Appointment workflow.

---

### BR-9 — Rescheduling preserves the Clinic

This workflow changes the requested date and time only.

It must not move the Appointment to another Clinic.

Changing Clinic requires a separate workflow.

---

### BR-10 — Rescheduling keeps the Appointment in REQUESTED state

A successfully rescheduled requested Appointment remains:

`REQUESTED`

Changing the requested time does not constitute Clinic confirmation.

---

### BR-11 — Rescheduling does not imply availability

Accepting a new requested time does not mean the Clinic has committed to that time.

The Clinic must still confirm the Appointment through `SPEC-APT-002`.

---

### BR-12 — New requested time must be in the future

A requested Appointment must not be rescheduled to a time that has already passed.

---

### BR-13 — Requested time must satisfy applicable request constraints

The new requested time must satisfy any Appointment-request constraints applicable to the Clinic and scheduling workflow.

The exact availability and scheduling model is defined separately.

---

### BR-14 — Rescheduling does not create clinical information

Changing an Appointment's requested time must not create:

* a Medical Record Entry;
* a diagnosis;
* a Treatment;
* a clinical observation.

Scheduling activity is not clinical activity.

---

### BR-15 — Reason for visit is preserved

Rescheduling the requested time must not silently remove or replace the existing reason for visit.

Changing the reason for visit is a separate Appointment-information operation unless explicitly combined by a later Specification.

---

### BR-16 — Additional Guardian notes are preserved

Existing Guardian-provided Appointment notes must remain associated with the Appointment unless explicitly changed through an authorized workflow.

---

### BR-17 — Rescheduling must be atomic

The system must not expose an Appointment with an ambiguous or partially updated scheduling state.

The new requested time and the corresponding scheduling-history information must be established as one logical operation.

---

### BR-18 — Rescheduling the same Appointment multiple times is allowed

A requested Appointment may be rescheduled more than once before confirmation.

Each successful change must preserve the sequence of previous requested scheduling contexts.

Example:

```text
09:00
  ↓
11:00
  ↓
16:30
```

The Appointment remains one domain entity throughout.

---

### BR-19 — A no-op reschedule must not create false history

Attempting to reschedule an Appointment to the same effective requested date and time must not create a misleading scheduling-history entry representing a change that did not occur.

Because the requested end time is derived rather than Guardian-supplied
(BR-22/BR-23), "the same effective requested date and time" means the same
full resolved interval — the same start instant and the same derived end
instant. If the Clinic's configured standard duration has changed since the
Appointment's current requested scheduling context was established,
submitting the same start time again produces a genuinely different
resolved interval and is not a no-op.

---

### BR-20 — Rescheduling does not affect Guardianship

Changing the requested time must not:

* create Guardianship;
* remove Guardianship;
* modify Guardianship relationships.

---

### BR-21 — Existing Veterinarian Assignment must be revalidated after requested-time changes

If a Veterinarian is already assigned to the Appointment when the requested
time changes, the Assignment must remain current only if the Veterinarian
continues to satisfy the applicable professional and scheduling constraints
for the new requested time.

The system must not assume that eligibility for the previous requested time
implies eligibility for the new requested time.

If the existing Veterinarian Assignment is no longer valid for the new
requested time, the incompatibility must be resolved through the applicable
professional Assignment workflow.

The Appointment must not silently preserve an invalid current Veterinarian
Assignment.

---

### BR-22 — Guardian selects only the new requested start time

The Guardian-facing reschedule workflow requires the Guardian to provide a
single new requested local start date, local start time, and the UTC offset
needed to resolve that civil time unambiguously.

The Guardian does not provide, and the system does not trust, any
Guardian-supplied end date, time, or UTC offset.

This supersedes any earlier version of this workflow that required the
Guardian to also supply an authoritative end date, time, and UTC offset.

---

### BR-23 — New end time is derived from the Clinic's current standard duration as elapsed real time

The new requested end time is established by the system, not the Guardian,
from the target Clinic's currently configured standard Appointment duration,
as defined by `SPEC-APT-013`.

The Guardian-supplied new civil start is first resolved to one unambiguous
concrete instant using the Clinic's authoritative scheduling timezone,
exactly as for an initial request (`SPEC-APT-001` BR-30). The new end is
then derived by adding the configured standard duration to that resolved
start instant as a fixed elapsed-time interval.

The duration applied is the Clinic's current standard duration at the
moment of the reschedule. It is not necessarily the duration that produced
the Appointment's previous requested or confirmed scheduling context, and a
change to the Clinic's configured duration between two rescheduling
operations does not retroactively alter any earlier
`appointment_schedule_revisions` row (`SPEC-APT-013` BR-63).

The Guardian never supplies, and the system never trusts, a
Guardian-provided end date, time, or UTC offset (BR-22).

---

### BR-24 — Rescheduling requires a Clinic with a currently configured standard duration

A reschedule request must not succeed when the Appointment's Clinic has no
currently configured standard Appointment duration.

This is an additional necessary condition alongside the existing
preconditions of this Specification (current `REQUESTED` state, current
Guardianship, a future valid time, and the Clinic's eligibility to manage
the existing request); it does not reorder or replace any of them.

Rejection for this reason is a deterministic business-rule outcome, not a
transient or retryable failure, and remains distinguishable from other
rejection reasons defined by this Specification (for example an unavailable
time, a past time, or a no-op same-time attempt).

There is no fallback or implicit default standard duration; the system must
not substitute one.

---

### BR-25 — A previously displayed candidate start time carries no authority for rescheduling

Where a Guardian-facing candidate Appointment start-time read (`SPEC-APT-014`)
has been used before submitting a reschedule request, that prior read is
advisory only and is not a precondition of this workflow.

This Specification's reschedule operation independently and authoritatively
re-reads the Clinic's current standard Appointment duration and current
Appointment Availability at the moment of the reschedule.

A Guardian may submit a reschedule request for a start time even when no
prior candidate read was performed, or when a prior candidate read is
stale. A previously displayed candidate provides no guarantee and does not
exempt the reschedule request from full revalidation.

---

### BR-26 — Duration-based rescheduling does not introduce Clinic capacity or professional selection

Deriving the new end from the Clinic's standard duration does not change
any other rule of this Specification.

In particular, it does not:

- require or introduce Veterinarian selection as part of rescheduling; the
  existing Assignment-revalidation behavior of BR-21 applies unchanged;
- treat another Appointment's `REQUESTED` or `CONFIRMED` state at the same
  Clinic as blocking this reschedule beyond the existing Clinic Appointment
  Availability check;
- assume or introduce a Clinic-level numerical scheduling capacity.

---

### BR-27 — A request whose requested time has passed cannot be revived

A `REQUESTED` Appointment whose latest requested scheduled start instant is no
longer in the future must not be rescheduled, even to a future time.

Such a request is logically expired (`SPEC-APT-015`). If the Guardian still
wants care, a new Appointment request is required (`SPEC-APT-001`).

This rule is evaluated with authoritative backend time and must hold whether or
not the `EXPIRED` outcome has already been materialized. It does not change the
rescheduling of a request whose latest requested start is still in the future.

---

### BR-28 — Guardian rescheduling supersedes a pending Clinic alternative time

A Guardian may reschedule a `REQUESTED` Appointment while a Clinic Alternative
Time proposal is pending (`SPEC-APT-018`). Rescheduling remains a unilateral
Guardian right and is not blocked by the proposal.

The new Guardian-authored requested scheduling context supersedes the
proposal's base, so the pending proposal becomes `VOID`
(`BASE_REVISION_SUPERSEDED`) in the same operation (`SPEC-APT-005` BR-33). It
can never be accepted afterwards, and an undelivered
`APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication for it is suppressed.

The reschedule's own rules are unchanged by the pending proposal.

When a Clinic alternative is pending, the Guardian reschedule screen must warn
that changing the requested time will discard the Clinic's proposed
alternative (`SPEC-APT-019` §5).

---

### BR-29 — Rescheduling is not acceptance of a Clinic alternative

Rescheduling never accepts a Clinic proposal, even when the Guardian chooses
the same start the Clinic proposed. Such a reschedule follows this
Specification: its end derives from the current standard duration, its
revision has no source proposal, and the proposal becomes `VOID` (BR-28).

To take the Clinic's proposed interval exactly, the Guardian accepts the
proposal through `SPEC-APT-019`.

---

## 4. Appointment State Transition

This Specification establishes:

```text
REQUESTED
    │
    │ change requested time
    ▼
REQUESTED
```

The Appointment's lifecycle state does not change.

Its scheduling history does.

---

## 5. Scenarios

### Scenario: Original Guardian reschedules requested Appointment

Given Maria has an active Guardianship relationship with Luna
And Maria requested an Appointment for Luna at Animalia Madrid Centro
And the Appointment is `REQUESTED` for 2026-09-10 at 10:00

When Maria reschedules the request to 2026-09-11 at 16:00

Then the Appointment remains the same domain entity
And the current requested time becomes 2026-09-11 at 16:00
And the previous requested time remains historically traceable
And the Appointment remains `REQUESTED`

---

### Scenario: Another current Guardian reschedules the Appointment

Given Carlos originally requested an Appointment for Luna
And Maria also has an active Guardianship relationship with Luna
And the Appointment is `REQUESTED`

When Maria validly changes the requested time

Then the Appointment remains the same domain entity
And Carlos remains recorded as the original requesting User
And Maria is recorded as the User who requested the scheduling change
And the Appointment remains `REQUESTED`

---

### Scenario: Former Guardian cannot reschedule

Given Carlos originally requested an Appointment for Luna
And Carlos no longer has an active Guardianship relationship with Luna
And Carlos has no other applicable authorization

When Carlos attempts to reschedule the Appointment

Then the operation is denied
And the current requested time remains unchanged

---

### Scenario: Confirmed Appointment cannot use requested-reschedule workflow

Given Luna's Appointment is `CONFIRMED`

When a Guardian attempts to change its time through this workflow

Then the operation is denied
And the confirmed Appointment remains unchanged

---

### Scenario: Requested Appointment cannot be moved to the past

Given Luna's Appointment is `REQUESTED`

When an authorized Guardian attempts to reschedule it to a time that has already passed

Then the operation is rejected
And the existing requested time remains unchanged

---

### Scenario: Passed request cannot be revived by rescheduling

Given Luna's Appointment is `REQUESTED` for 10:00
And it was never confirmed
And 10:00 has passed
And its `EXPIRED` outcome has not yet been materialized

When an authorized Guardian attempts to reschedule it to tomorrow at 10:00

Then the operation is rejected
And no new scheduling history is created
And the Guardian must create a new Appointment request to seek care

---

### Scenario: Reschedule preserves reason for visit

Given Luna has a requested Appointment
And the reason for visit is "Luna has been limping since yesterday"

When an authorized Guardian changes the requested Appointment time

Then the reason for visit remains unchanged
And no clinical diagnosis is created

---

### Scenario: Reschedule does not confirm Appointment

Given Luna has an Appointment in `REQUESTED` state

When an authorized Guardian validly changes the requested time

Then the Appointment remains `REQUESTED`
And the Clinic has not yet committed to the new time

---

### Scenario: Appointment is rescheduled several times

Given Luna has a requested Appointment originally requested for 09:00
And an authorized Guardian previously changed the requested time to 11:00

When an authorized Guardian changes the requested time to 16:30

Then the current requested time becomes 16:30
And the previous 09:00 and 11:00 scheduling contexts remain historically traceable
And only one Appointment domain entity exists

---

### Scenario: Reschedule to the same time does not create false history

Given Luna has a requested Appointment for 10:00

When an authorized Guardian submits a reschedule operation for the same effective time

Then no additional scheduling-history change is created
And the Appointment remains unchanged

---

### Scenario: Rescheduling does not affect Pet or Clinic

Given Luna has a requested Appointment at Animalia Madrid Centro

When an authorized Guardian changes the requested time

Then the Appointment remains associated with Luna
And the Appointment remains associated with Animalia Madrid Centro

---

### Scenario: Rescheduling does not create clinical information

Given Luna has a requested Appointment

When the requested time is validly changed

Then no Medical Record Entry is created
And no diagnosis is created
And no Treatment is created

---

### Scenario: Requested-time change makes assigned Veterinarian unavailable

Given Luna has a `REQUESTED` Appointment
And Dr. Garcia is currently assigned to the Appointment
And Dr. Garcia was eligible for the existing requested time
And Dr. Garcia is not eligible for the proposed new requested time

When an authorized Guardian attempts to reschedule the Appointment

Then the system must not silently preserve Dr. Garcia as a valid current
Veterinarian for the new requested time
And the professional Assignment incompatibility must be resolved according to
the applicable Appointment Assignment workflow

---

### Scenario: Guardian reschedules by selecting only a new start time

Given Maria has an active Guardianship relationship with Luna
And Luna's Appointment is `REQUESTED`
And Animalia Madrid Centro has a currently configured standard Appointment duration of 30 minutes

When Maria reschedules the request to a new start time, providing only a local start date, time, and UTC offset

Then the new requested interval is the new start time plus 30 minutes
And Maria did not provide an end date, time, or UTC offset

---

### Scenario: Reschedule rejected when Clinic has no configured standard duration

Given Luna's Appointment is `REQUESTED` at Animalia Madrid Centro
And Animalia Madrid Centro has no currently configured standard Appointment duration

When an authorized Guardian attempts to reschedule the Appointment

Then the request is rejected
And the existing requested time remains unchanged

---

### Scenario: Prior candidate read does not exempt a reschedule from revalidation

Given Maria previously viewed candidate Appointment start times for Animalia Madrid Centro
And the Clinic's Availability or standard duration has since changed

When Maria reschedules Luna's Appointment to a start time shown in that earlier read

Then the reschedule is evaluated against the Clinic's current Availability and current standard duration
And the previously displayed candidate does not guarantee acceptance

---

### Scenario: Same start time with a changed standard duration is not a no-op

Given Luna's Appointment is `REQUESTED` with a current interval established under a 30-minute standard duration
And Animalia Madrid Centro's standard duration is later changed to 45 minutes

When an authorized Guardian reschedules the Appointment to the same start time as its current requested context

Then a new scheduling-history entry is created reflecting the new 45-minute derived interval
And this is not treated as a no-op

---

## 6. Scheduling History

The Appointment domain must support reconstructing meaningful scheduling changes.

For a requested Appointment, the system should be capable of establishing a history conceptually equivalent to:

```text
Appointment A

2026-08-20 14:03
Requested for:
2026-09-10 10:00
By: Carlos

2026-08-21 09:15
Requested time changed to:
2026-09-11 16:00
By: Maria
```

This Specification does not require a specific event-sourcing architecture or database representation.

It requires preservation of meaningful scheduling history.

---

## 7. Edge Cases

### Concurrent rescheduling

Two Guardians may attempt to change the same requested Appointment concurrently.

The resulting Appointment must have one consistent current requested time and must not contain contradictory scheduling history.

The concurrency-control mechanism is architectural.

---

### Clinic confirms while Guardian attempts reschedule

Confirmation and Guardian rescheduling may occur concurrently.

The system must not produce an Appointment whose lifecycle state and scheduling commitment refer to different effective times.

The applicable operation must observe a consistent Appointment state.

The exact concurrency mechanism is architectural.

---

### Clinic alternative accepted while another Guardian reschedules

One Guardian may accept a Clinic alternative (`SPEC-APT-019`) while another
Guardian reschedules the same request. The operations are serialized: if the
reschedule completes first, the proposal is `VOID` and acceptance fails; if the
acceptance completes first, the reschedule creates a further requested context
after the accepted one.

---

### Clinic becomes unpublished

A Clinic becoming unpublished does not automatically delete an existing requested Appointment.

This operation is not gated by Clinic publication: after unpublication the Guardian may still reschedule an existing request, subject to every other rule of this Specification, including the standard duration and current Appointment Availability (`SPEC-CLI-003` BR-18).

The Guardian-facing candidate read (`SPEC-APT-014` BR-2) does require a published Clinic, so a Guardian surface that offers only candidate times from that read presents no new time for an unpublished Clinic. The Clinic may instead propose an Alternative Time (`SPEC-APT-018`). Changing either rule requires a separate approved change.

---

### Appointment request has expired

A request that was not confirmed before its latest requested start becomes
`EXPIRED` under `SPEC-APT-015`, and from that start instant it can no longer be
rescheduled (BR-27).

Other limits on how long a request may remain pending, such as Clinic response
deadlines, are outside this Specification.

---

## 8. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 9. Dependencies

* SPEC-APT-001 — Request Appointment
* SPEC-APT-002 — Confirm Appointment
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-APT-015 — Expire Unconfirmed Appointment Request
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-APT-019 — Accept Requested Appointment Alternative Time
* SPEC-ID-003 — Authenticate User
* SPEC-PET-003 — Accept Guardianship Invitation

Where a Guardian-facing candidate Appointment start-time read informs this
workflow:

- SPEC-APT-014 — View Guardian Requestable Appointment Times

---

## 10. Out of Scope

This Specification does not define:

* rescheduling a `CONFIRMED` Appointment;
* Clinic-proposed alternative times (`SPEC-APT-018`);
* Guardian acceptance of Clinic-proposed times (`SPEC-APT-019`);
* changing the Appointment's Clinic;
* changing the Appointment's Pet;
* changing the reason for visit;
* Appointment cancellation;
* Appointment confirmation;
* Veterinarian assignment;
* exact availability rules;
* the exact standard Appointment duration value or how it is configured (governed by `SPEC-APT-013`);
* the Guardian-facing candidate Appointment start-time read (governed by `SPEC-APT-014`);
* waitlists;
* rescheduling notifications;
* rescheduling fees;
* cancellation policies.

---

## 11. Verification Notes

Verification must demonstrate that:

1. a current authorized Guardian may reschedule a `REQUESTED` Appointment;
2. requester status alone does not provide permanent rescheduling authority;
3. another current Guardian may change the requested time;
4. the Appointment remains the same domain entity;
5. previous requested times remain historically traceable;
6. the original requester remains identifiable;
7. the User performing each scheduling change is traceable;
8. the Pet and Clinic remain unchanged;
9. the Appointment remains `REQUESTED`;
10. rescheduling does not imply Clinic confirmation;
11. past times cannot be requested;
12. confirmed Appointments cannot use this workflow;
13. reason for visit and existing notes are preserved;
14. multiple scheduling changes preserve meaningful history;
15. a no-op change does not create false history;
16. scheduling changes do not create clinical information;
17. concurrent operations cannot leave contradictory Appointment state;
18. the Guardian provides only a new requested start date, time, and UTC
    offset — no end date, time, or offset is accepted as authoritative;
19. the new end time is correctly derived from the Clinic's *current*
    standard Appointment duration as real elapsed time, and is not
    influenced by the duration that produced any earlier scheduling
    context for the same Appointment;
20. a reschedule request is rejected, deterministically and
    distinguishably from other rejection reasons, when the Appointment's
    Clinic has no currently configured standard Appointment duration;
21. a reschedule request is evaluated against current Availability and
    current standard duration regardless of whether, or how recently, a
    candidate Appointment start-time read was performed;
22. resubmitting the same start time after the Clinic's standard duration
    has changed produces a new scheduling-history entry rather than being
    treated as a no-op;
23. a `REQUESTED` Appointment whose latest requested start is still in the
    future may still be rescheduled;
24. a `REQUESTED` Appointment whose latest requested start is no longer in the
    future cannot be rescheduled to any time, before or after its `EXPIRED`
    outcome is materialized, and the rejection creates no scheduling history;
25. an `EXPIRED` Appointment cannot be rescheduled;
26. a Guardian may reschedule while a Clinic Alternative Time proposal is
    pending, and the proposal becomes `VOID` with `BASE_REVISION_SUPERSEDED`
    in the same operation;
27. rescheduling to the start the Clinic proposed creates an unsourced
    revision derived from the current standard duration and never accepts the
    proposal.

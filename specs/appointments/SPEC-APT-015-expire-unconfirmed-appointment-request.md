# SPEC-APT-015 — Expire Unconfirmed Appointment Request

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-006, REQ-ACC-002
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Give every Appointment request a definite outcome when the Clinic does not
confirm it before the requested time arrives.

A `REQUESTED` Appointment can only be confirmed while its requested time is
still in the future (`SPEC-APT-002` BR-19). Without an explicit outcome, a
request that was never confirmed would remain `REQUESTED` indefinitely: shown
as an active obligation, still carrying its Appointment-derived Care
Authorization, and impossible to confirm.

This Specification introduces the terminal Appointment lifecycle state
`EXPIRED`, meaning:

```text
The Clinic did not confirm this Appointment request before the requested
time arrived.
```

`EXPIRED` is not a cancellation, not a no-show, not a completion, and not a
decision by the Clinic or by a Guardian. It is the absence of confirmation
within the request's own time.

---

## 2. Preconditions

For an Appointment to become `EXPIRED`:

- the Appointment exists;
- the Appointment is currently `REQUESTED`;
- the Appointment has never been confirmed;
- the scheduled start instant of the Appointment's latest requested scheduling
  context is no longer in the future according to authoritative backend time.

No acting User, Guardianship, Clinic capability, or professional Entitlement is
a precondition: expiry is a system lifecycle transition (BR-8).

---

## 3. Business Rules

### BR-1 — EXPIRED means the request was not confirmed in time

An Appointment becomes `EXPIRED` when it is still `REQUESTED`, has never been
confirmed, and the scheduled start instant of its latest requested scheduling
context is no longer in the future.

`EXPIRED` records that the Clinic did not confirm the request before the
requested time arrived. It does not record why.

---

### BR-2 — Only REQUESTED may become EXPIRED

The only transition into `EXPIRED` is:

```text
REQUESTED
    │
    │ expire
    ▼
EXPIRED
```

No other lifecycle state transitions to `EXPIRED`. In particular, a
`CONFIRMED` Appointment whose time has passed is never expired: its outcome is
established through completion (`SPEC-APT-009`), no-show (`SPEC-APT-010`), or
cancellation (`SPEC-APT-003`).

---

### BR-3 — Expiry occurs at the latest requested scheduled start instant

The expiry point is the resolved absolute scheduled start instant of the
Appointment's latest requested scheduling context.

The latest requested scheduling context is the one most recently established
for the Appointment while it is `REQUESTED`, including any Guardian
rescheduling (`SPEC-APT-004`). An earlier requested time that was replaced by
rescheduling does not determine expiry.

Expiry must not be evaluated against:

- the scheduled end;
- device-local time;
- a Clinic wall-clock time reconstructed by a client.

The comparison uses authoritative backend time. Because the scheduled start is
an absolute instant, daylight-saving transitions and later Clinic timezone
configuration changes do not move the expiry point.

---

### BR-4 — A past request is logically expired before EXPIRED is materialized

Once the latest requested scheduled start instant is no longer in the future, a
still-`REQUESTED` Appointment is logically expired, whether or not the `EXPIRED`
outcome has been materialized yet (BR-5).

Every rule whose correctness or security matters at that moment must evaluate
the time condition directly and must not depend on materialization having
already happened. This includes at least:

- confirmation is rejected (`SPEC-APT-002` BR-19);
- Guardian cancellation and Clinic cancellation are rejected
  (`SPEC-APT-003` BR-23);
- Guardian rescheduling is rejected (`SPEC-APT-004`);
- the request no longer counts as a pending request, so a new request may be
  created subject to the pending-request rule (`SPEC-APT-001`);
- the Appointment-derived Care Authorization no longer provides pre-care
  medical access (`SPEC-ACC-001`).

---

### BR-5 — EXPIRED is materialized by an authoritative backend process

`EXPIRED` is a persisted lifecycle outcome, not only a derived presentation.

It is materialized by an authoritative backend scheduled process. The exact
mechanism and frequency are implementation concerns.

- The mobile application is never responsible for expiry.
- Read operations must not change Appointment state.
- Materialization may occur some time after the expiry point; BR-4 keeps the
  intervening period correct.

---

### BR-6 — Materialization is one coherent operation

Materializing expiry establishes together:

- the Appointment lifecycle state `EXPIRED`;
- exactly one `REQUESTED → EXPIRED` Lifecycle Event (BR-8, BR-11);
- the ending of the Appointment-derived Care Authorization (BR-12).

The system must not expose an `EXPIRED` Appointment whose Care Authorization
still provides normal current access, nor an ended Care Authorization whose
Appointment remains `REQUESTED` because of expiry.

---

### BR-7 — Materialization is idempotent and wins at most once

An Appointment expires at most once.

Repeated or overlapping expiry processing must not:

- create a second `EXPIRED` Lifecycle Event;
- end the Care Authorization again or change its ending context;
- change an Appointment that is no longer `REQUESTED`.

When expiry processing and another Appointment operation (confirmation,
cancellation, or rescheduling) concern the same Appointment concurrently,
exactly one coherent outcome is established, and every operation re-evaluates
the Appointment's current state and the time condition at execution time. Once
the logical expiry instant has been reached, that outcome is `EXPIRED`
(BR-18).

---

### BR-8 — Expiry is a SYSTEM lifecycle transition

Expiry is performed by the system, not by a User.

The `EXPIRED` Lifecycle Event:

- is distinguishable from Guardian and Clinic actor events;
- identifies the system as its actor context;
- does not identify any User as its actor.

No fabricated domain User, service User, or placeholder User may be created or
used merely to satisfy actor storage. The lifecycle actor model must represent
system-performed transitions explicitly (see `docs/RELATIONAL_MODEL.md`).

---

### BR-9 — EXPIRED is terminal

Once `EXPIRED`, an Appointment cannot be:

- confirmed;
- rescheduled;
- cancelled;
- completed;
- marked `NO_SHOW`;
- returned to `REQUESTED` or any other state.

If the Guardian still wants care, a new Appointment request is required
(`SPEC-APT-001`).

---

### BR-10 — EXPIRED is not cancellation, no-show, or completion

Expiry must not be represented, recorded, reported, or communicated as:

- `CANCELLED` — no Guardian or Clinic decided to cancel the request;
- `NO_SHOW` — no attendance commitment existed (`SPEC-APT-010` BR-2);
- `COMPLETED` — no veterinary care occurred through the Appointment.

Expiry must not create cancellation, no-show, or completion history, actor, or
reason.

---

### BR-11 — Expiry preserves Appointment and scheduling history

Expiry must not change:

- the Pet;
- the Clinic;
- the original requesting User;
- the reason for visit or Guardian notes;
- any Schedule Revision;
- Veterinarian Assignment history.

Expiry creates no Schedule Revision.

The `EXPIRED` Lifecycle Event preserves:

- the instant at which the request logically expired — the scheduled start
  instant of its latest requested scheduling context (BR-3);
- the time at which the system recorded the outcome.

These two times may differ when materialization runs after the expiry point,
including for existing data (BR-17). The relevant scheduled interval shown by
the Appointment reads is unchanged (`SPEC-APT-011` §4, `SPEC-APT-012` §4).

---

### BR-12 — Expiry ends the Appointment-derived Care Authorization

Materializing `EXPIRED` ends the Appointment-derived Care Authorization
(`ACTIVE → ENDED`) with the distinct normal-ending context
`APPOINTMENT_EXPIRED`, as defined by `SPEC-ACC-001`.

The ending context must not reuse the cancellation or no-show ending contexts.

A Care Authorization that was already `REVOKED` or `ENDED` is left unchanged.

Access already stopped at the expiry point under BR-4; materialization records
the formal ending.

---

### BR-13 — Expiry produces no Communication in Phase 1

Phase 1 does not notify anyone because an Appointment request expired.

- No Guardian or Clinic transactional Communication is created merely because
  an Appointment becomes `EXPIRED`.
- Expiry must never reuse the `APPOINTMENT_CANCELLED` Communication or any
  other existing Appointment Communication type.
- Upcoming-Appointment reminders apply only to confirmed Appointments
  (`SPEC-COM-003`), so expiry neither creates nor suppresses a reminder.

A future expiry notification requires its own approved Specification and
recipient policy.

---

### BR-14 — EXPIRED is historical

`EXPIRED` is a historical, terminal Appointment outcome alongside
`COMPLETED`, `CANCELLED`, and `NO_SHOW`.

It is not an active scheduling obligation in Guardian or Clinic Appointment
views (`SPEC-APT-011`, `SPEC-APT-012`).

---

### BR-15 — Expiry does not create or conflict with clinical care

Expiry must not create a Clinical Encounter, Medical Record Entry, or any
clinical statement.

An Appointment-backed Clinical Encounter requires a `CONFIRMED` Appointment
(`SPEC-MED-001`), so a `REQUESTED` Appointment never has Appointment-backed
clinical care that expiry could contradict. Care that occurs without
confirmation uses the independent Clinical Intake path and does not depend on
the expired request.

---

### BR-16 — An expired or past request never blocks a new request

Neither an `EXPIRED` Appointment nor a logically expired `REQUESTED`
Appointment counts as a pending request for the purpose of `SPEC-APT-001`.

A Guardian is never prevented from requesting care because an earlier request
expired, including before its expiry has been materialized.

---

### BR-17 — Existing past requests are expired the same way

When this behavior is introduced, every existing `REQUESTED` Appointment whose
latest requested scheduled start is already in the past is eligible for the
same expiry materialization.

For such Appointments:

- the same `REQUESTED → EXPIRED` transition, SYSTEM actor semantics, and
  history rules apply;
- the Lifecycle Event preserves the original logical expiry instant and the
  later recording time (BR-11);
- their Appointment-derived Care Authorization is ended with
  `APPOINTMENT_EXPIRED` (BR-12);
- no cancellation, no-show, or completion history is fabricated;
- existing Schedule Revisions and other history remain intact;
- no Communication is created (BR-13).

No destructive data rewrite is permitted.

---

### BR-18 — Logical expiry fixes the outcome; materialization only records it

Once the logical expiry instant — the latest requested scheduled start — has
been reached, `EXPIRED` is the only applicable terminal outcome for an
Appointment that is still `REQUESTED`.

From that instant:

- no Guardian or Clinic operation may give the Appointment any other terminal
  outcome; in particular, cancellation cannot produce `CANCELLED`
  (`SPEC-APT-003` BR-23);
- the timing of the scheduled materialization process must never determine
  whether the same logical situation ends as `CANCELLED` or `EXPIRED`;
- the materialization process records the already-logical `EXPIRED` outcome; it
  does not decide it.

Only a pending `REQUESTED` Appointment — one whose latest requested start is
still strictly in the future — may be cancelled.

The logical expiry instant and the time the outcome is recorded remain distinct
facts (BR-11).

---

### BR-19 — A pending Clinic alternative time does not extend the request

A pending Clinic Alternative Time proposal (`SPEC-APT-018`) does not change the
expiry instant. Until a Guardian accepts it, the latest requested scheduling
context is still the proposal's base, so the request expires at the base
requested start even when the proposed start is later.

Once the base requested start has passed, the proposal is no longer actionable
and can no longer be accepted (`SPEC-APT-018` BR-17), before or after `EXPIRED`
is materialized. Materializing `EXPIRED` makes the pending proposal `VOID`
(`APPOINTMENT_LIFECYCLE_CHANGED`) in the same operation (`SPEC-APT-005`
BR-33).

If a Guardian accepted the proposal in time, the accepted interval is the
latest requested scheduling context (`SPEC-APT-019` BR-10), and the request
expires at the accepted start if it is not confirmed before then. Acceptance
never makes the request `CONFIRMED`.

---

## 4. EXPIRED vs other Appointment outcomes

| Outcome | From | Meaning | Actor |
| --- | --- | --- | --- |
| `CANCELLED` | `REQUESTED` while pending, `CONFIRMED` | An authorized Guardian or Clinic actor decided the visit will not happen. | Guardian or Clinic User |
| `NO_SHOW` | `CONFIRMED` | The Pet did not attend a confirmed visit. | Clinic User |
| `COMPLETED` | `CONFIRMED` | The Clinic asserts the confirmed visit occurred; no Clinical Encounter is required (`SPEC-APT-009`). | Clinic User |
| `EXPIRED` | `REQUESTED` | The Clinic did not confirm the request before the requested time arrived. | System |

---

## 5. Scenarios

### Scenario: Unconfirmed request expires at its requested start

Given Luna has a `REQUESTED` Appointment at Animalia Madrid Centro for 10:00
And it has never been confirmed
And 10:00 has passed

When expiry is materialized

Then the Appointment becomes `EXPIRED`
And exactly one `REQUESTED → EXPIRED` Lifecycle Event exists with the system as
its actor context and no User actor
And the event preserves 10:00 as the logical expiry instant and the recording
time
And the Appointment-derived Care Authorization is `ENDED` with
`APPOINTMENT_EXPIRED`
And no Schedule Revision is created
And no Communication is created

---

### Scenario: Future request is untouched

Given Luna has a `REQUESTED` Appointment whose requested start is in the future

When expiry processing runs

Then the Appointment remains `REQUESTED`
And nothing is recorded for it

---

### Scenario: The latest requested time determines expiry

Given Luna's request was for 10:00
And a current Guardian rescheduled it to 16:00 the same day
And it is now 12:00

When expiry processing runs

Then the Appointment remains `REQUESTED`
And it expires only once 16:00 has passed without confirmation

---

### Scenario: Confirmed Appointment is never expired

Given Luna's Appointment was confirmed for 10:00
And 10:00 has passed

When expiry processing runs

Then the Appointment remains `CONFIRMED`
And its outcome must be established through completion, no-show, or
cancellation

---

### Scenario: Terminal Appointments are untouched

Given Luna has `CANCELLED`, `COMPLETED`, `NO_SHOW`, and `EXPIRED` Appointments
whose times have passed

When expiry processing runs

Then none of them changes
And no Lifecycle Event is added

---

### Scenario: Repeated expiry processing is idempotent

Given Luna's past request was already materialized as `EXPIRED`

When expiry processing runs again

Then no second `EXPIRED` Lifecycle Event is created
And the Care Authorization ending is unchanged

---

### Scenario: Pre-care access stops at the requested start before materialization

Given Luna's request for 10:00 was never confirmed
And it is now 10:01
And expiry has not been materialized yet

When a Veterinarian at the Clinic attempts pre-care access to Luna's medical
history through that Appointment's Care Authorization

Then access is denied
And the Appointment still appears `REQUESTED` until materialization

---

### Scenario: Past request cannot be confirmed or revived

Given Luna's request for 10:00 was never confirmed
And 10:00 has passed

When an authorized Clinic actor attempts to confirm it
Or a current Guardian attempts to reschedule it to tomorrow

Then both attempts are rejected
And the Guardian must create a new Appointment request

---

### Scenario: Passed request cannot be cancelled before materialization

Given Luna's request for 10:00 was never confirmed
And 10:00 has passed
And expiry has not been materialized yet

When a current Guardian attempts to cancel it
Or an authorized Clinic actor attempts to cancel it with a reason

Then both attempts are rejected
And no cancellation Lifecycle Event, Care Authorization ending, or
`APPOINTMENT_CANCELLED` Communication is created

When expiry is later materialized

Then the Appointment becomes `EXPIRED`
And its outcome is identical to that of a request for which no cancellation was
attempted

---

### Scenario: Outcome does not depend on when expiry processing runs

Given two otherwise identical requests whose requested start has passed without
confirmation
And expiry has already been materialized for the first but not yet for the
second

When cancellation is attempted for both

Then both attempts are rejected
And both Appointments end as `EXPIRED`

---

### Scenario: Expired Appointment is terminal

Given Luna's Appointment is `EXPIRED`

When confirmation, rescheduling, cancellation, completion, or no-show is
attempted

Then every attempt is rejected
And the Appointment remains `EXPIRED`

---

### Scenario: Expiry does not block a new request

Given Luna's earlier request at Animalia Madrid Centro is `EXPIRED`
Or its requested start has passed but expiry has not been materialized

When a current Guardian requests a new Appointment for Luna at the same Clinic

Then the earlier request does not block the new request

---

### Scenario: Existing past requests are reconciled

Given an existing `REQUESTED` Appointment's requested start passed before this
behavior was introduced
And its Care Authorization is still `ACTIVE`

When expiry is materialized for it

Then the Appointment becomes `EXPIRED`
And the Lifecycle Event preserves the original requested start as the logical
expiry instant and the later recording time
And its Care Authorization is `ENDED` with `APPOINTMENT_EXPIRED`
And its Schedule Revisions are unchanged
And no cancellation or no-show history is created

---

## 6. Edge Cases

### Materialization runs late

Expiry processing may run some time after the requested start. Until it runs,
the Appointment is `REQUESTED` but logically expired, and the rules listed in
BR-4 already apply.

### Clinic changes after the request

Clinic unpublication, loss of professional Entitlement, or later Clinic
timezone configuration changes do not prevent or move expiry. Expiry is a
system outcome and requires no Clinic capability or Entitlement.

### Guardianship changes after the request

Expiry does not depend on the requesting User or any other Guardian remaining a
current Guardian.

### Veterinarian assigned to the request

A Veterinarian Assignment on an expired request remains historical
information. It never becomes a confirmed scheduling commitment.

### Cancellation attempted after the requested start but before materialization

The request is already logically expired. Guardian and Clinic cancellation are
rejected (BR-18, `SPEC-APT-003` BR-23): no cancellation Lifecycle Event, Care
Authorization ending, or `APPOINTMENT_CANCELLED` Communication is produced, and
the Appointment later becomes `EXPIRED` through materialization exactly as if
no cancellation had been attempted.

---

## 7. Compatibility and deployment sequencing

Existing client applications may treat the Appointment lifecycle state as a
closed set and reject a payload containing an unknown value such as `EXPIRED`.

Therefore the backend must not begin materializing `EXPIRED` in an environment
until client applications used in that environment can parse and present
`EXPIRED`.

This is a deployment-sequencing constraint only. It does not weaken the
lifecycle model, and BR-4 rules that do not write `EXPIRED` (confirmation,
cancellation, rescheduling, pending-request evaluation, and pre-care access) do
not depend on it.

---

## 8. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**

---

## 9. Dependencies

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-003 — Cancel Appointment
- SPEC-APT-004 — Reschedule Requested Appointment
- SPEC-APT-009 — Complete Appointment
- SPEC-APT-010 — Mark Appointment No-Show
- SPEC-APT-011 — View Guardian Appointments
- SPEC-APT-012 — View Clinic Appointment Schedule
- SPEC-APT-018 — Propose Alternative Time for Requested Appointment
- SPEC-APT-019 — Accept Requested Appointment Alternative Time
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-MED-001 — Create Clinical Encounter
- SPEC-COM-003 — Send Appointment Notifications

---

## 10. Out of Scope

This Specification does not define:

- Appointment expiry notifications;
- configurable grace periods or Clinic-defined response deadlines;
- automatic rescheduling or system-generated alternative-time suggestions
  (Clinic-proposed alternative times are defined by `SPEC-APT-018`);
- waitlists;
- expiry of `CONFIRMED` Appointments;
- administrative correction of terminal Appointment states;
- the scheduling frequency or mechanism of expiry processing;
- reporting or analytics on expired requests.

---

## 11. Verification Notes

Verification must demonstrate that:

1. a `REQUESTED` Appointment whose latest requested start is in the future is
   not expired;
2. a never-confirmed `REQUESTED` Appointment whose latest requested start is no
   longer in the future becomes `EXPIRED` exactly once;
3. the latest requested scheduling context, not an earlier replaced one,
   determines expiry, and a request rescheduled into the future is not
   expired;
4. `CONFIRMED`, `CANCELLED`, `COMPLETED`, and `NO_SHOW` Appointments are never
   changed by expiry processing;
5. repeated or overlapping expiry processing is idempotent;
6. expiry creates exactly one `REQUESTED → EXPIRED` Lifecycle Event with a
   system actor context and no User actor, preserving the logical expiry
   instant and the recording time, and no fabricated User exists;
7. expiry creates no Schedule Revision and leaves the Pet, Clinic, requester,
   reason, Schedule Revisions, and Veterinarian Assignment history unchanged;
8. expiry creates no cancellation, no-show, or completion history;
9. materialized expiry ends an `ACTIVE` Appointment-derived Care Authorization
   with `APPOINTMENT_EXPIRED`, and leaves an already `REVOKED` or `ENDED` one
   unchanged;
10. expiry creates no Communication and never an `APPOINTMENT_CANCELLED`
    Communication;
11. a logically expired request no longer provides pre-care medical access
    before `EXPIRED` is materialized;
12. a logically expired request cannot be confirmed or rescheduled before or
    after materialization;
13. an `EXPIRED` Appointment cannot be confirmed, rescheduled, cancelled,
    completed, or marked `NO_SHOW`;
14. neither an `EXPIRED` nor a logically expired `REQUESTED` Appointment blocks
    a new request for the same Pet and Clinic;
15. Guardian and Clinic Appointment reads present `EXPIRED` as historical and
    never as an active obligation, with the relevant scheduled interval
    unchanged;
16. existing past `REQUESTED` Appointments can be reconciled by the same
    materialization, with their history intact and their Care Authorization
    ended with `APPOINTMENT_EXPIRED`;
17. read operations never change Appointment state;
18. Guardian and Clinic cancellation of a logically expired `REQUESTED`
    Appointment are rejected before materialization, with no Lifecycle Event,
    Care Authorization change, or Communication;
19. a logically expired `REQUESTED` Appointment always ends as `EXPIRED`, and
    the outcome is identical whether expiry processing runs before or after an
    attempted cancellation, confirmation, or rescheduling;
20. a pending Clinic Alternative Time proposal never moves the expiry instant
    beyond the base requested start, and cannot be accepted once that start
    has passed;
21. materializing `EXPIRED` makes a pending proposal `VOID` with
    `APPOINTMENT_LIFECYCLE_CHANGED` and creates no Communication;
22. after a Guardian accepted a Clinic alternative, expiry uses the accepted
    start.

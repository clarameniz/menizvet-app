# SPEC-APT-017 — View Professional Reschedule Candidate Times

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-008, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the "without an Encounter" condition reads as "without a Clinical Record Entry" (SPEC-MED-010 BR-9). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Clinic actor to see candidate new start times for one
existing `CONFIRMED` Appointment before proposing a reschedule
(`SPEC-APT-005`).

Each candidate describes exactly the interval a proposal for that start would
store, so the actor proposes only times the system currently considers
feasible.

This read is advisory. It creates no hold or reservation, and the proposal
operation independently revalidates everything (`SPEC-APT-005` BR-27,
BR-28).

It is distinct from the Guardian-facing requestable-times read
(`SPEC-APT-014`), whose publication and +60-day horizon rules do not apply
here. Like that read and every other read offering starts for a new scheduled
interval, it uses the Clinic's current standard Appointment duration
(`SPEC-APT-013` BR-68).

---

## 2. Preconditions

* The acting User exists and is authenticated.
* The Appointment exists.
* The acting User currently holds `APPOINTMENT_RESCHEDULE` for the
  Appointment's Clinic.
* The Organization currently holds the professional Entitlement required to
  create a Clinic proposal (`APPOINTMENT_MANAGEMENT`).
* The Clinic has a currently configured standard Appointment duration.

---

## 3. Business Rules

### BR-1 — Same authority as proposing

The read requires the same Clinic capability and the same professional
Entitlement as creating a Clinic proposal. An actor who could not propose
cannot read candidates.

---

### BR-2 — Only an Appointment that could receive a proposal

The read applies only to an Appointment that is `CONFIRMED`, whose current
confirmed start is still in the future, and that has no Clinical Encounter
(`SPEC-APT-005` BR-29). Otherwise the read fails with a lifecycle error rather
than returning an empty result.

---

### BR-3 — No publication requirement

Clinic unpublication does not prevent managing existing Appointments
(`SPEC-APT-005` §8). The read does not require the Clinic to be published.

---

### BR-4 — Bounded query span, no business horizon

Each read covers an inclusive range of Clinic-local calendar dates whose end
is no more than 60 days after its start. A missing range, a reversed range, or
a longer span is invalid input.

This bound protects the system; it is not a business scheduling horizon. The
range may lie anywhere in the future. A range entirely in the past simply
yields no candidates.

---

### BR-5 — Length and step come from the current standard duration

Every candidate interval lasts the Clinic's current standard Appointment
duration, applied as real elapsed time — the same duration a proposal for
that start would use (`SPEC-APT-005` BR-24). The same duration is the grid
step: candidate positions follow `SPEC-APT-013` BR-58 exactly — within each
maximal covered civil range of each date, positions are the range's local
civil start plus whole multiples of the standard duration; an excluded
position never shifts the grid.

The elapsed duration of the Appointment's current confirmed scheduling
context is not used.

Without a configured standard duration the read fails with the same
deterministic, distinguishable outcome as proposal creation
(`SPEC-APT-005` BR-24); it does not return an empty result and does not
substitute any other duration.

---

### BR-6 — Candidate validity

A position is returned only when:

* it resolves to exactly one instant in the Clinic's scheduling timezone
  (nonexistent and ambiguous civil times are omitted, `SPEC-APT-013` BR-58);
* that instant is in the future;
* it is not the current confirmed start instant (`SPEC-APT-005` BR-25),
  whatever the duration;
* its civil interval fits within the covered civil range it was generated
  from;
* the resolved interval `[start, start + standard duration)` satisfies every
  feasibility rule
  of `SPEC-APT-005` BR-28: Clinic Appointment Availability and, where a
  Veterinarian is currently assigned, a current Clinic Assignment, that
  Veterinarian's Availability, and no other known overlapping `CONFIRMED`
  commitment of that Veterinarian excluding this Appointment.

If the assigned Veterinarian's Clinic Assignment is no longer current, no
candidate is returned.

---

### BR-7 — Read/write parity

For unchanged state, every returned candidate, submitted as a Clinic proposal
with its local date, local time, and UTC offset, is accepted and stores
exactly the returned start and end.

---

### BR-8 — Response information

Each candidate includes:

* its Clinic-local date and local time;
* the UTC offset used to resolve it, so it can be resubmitted unambiguously;
* its end instant.

Clients present the returned end; they never compute an end or a duration.

---

### BR-9 — No disclosure of other commitments

A position excluded because of a Veterinarian conflict is simply absent. The
read never reveals that a conflict exists, nor any detail of another
Appointment, Clinic, or Organization.

---

### BR-10 — The read does not modify state

Reading candidates creates no proposal, hold, reservation, or other domain
state.

---

## 4. Phase 1 Limitations

Following the existing candidate generator, a candidate interval must fit
within one covered civil range of one calendar date, exactly as for the other
candidate reads (`SPEC-APT-014`, `SPEC-APT-020`).

---

## 5. Scenarios

### Scenario: Candidates use the current standard duration

Given Luna's confirmed Appointment is 10:00–10:30, established under a 30-minute standard duration
And the Clinic's standard duration is now 45 minutes
When an authorized Clinic actor reads candidates for that Appointment
Then every candidate interval lasts 45 minutes
And candidate starts follow a 45-minute cadence within each covered range
And no candidate starts at 10:00

---

### Scenario: Shorter standard duration

Given Luna's confirmed Appointment is 10:00–11:00, established under a 60-minute standard duration
And the Clinic's standard duration is now 30 minutes
When an authorized Clinic actor reads candidates
Then every candidate interval lasts 30 minutes
And candidate starts follow a 30-minute cadence within each covered range

---

### Scenario: No standard duration

Given the Clinic has no configured standard duration
When an authorized Clinic actor reads candidates for a confirmed Appointment
Then the read fails deterministically

---

### Scenario: Unpublished Clinic

Given the Clinic is not published
When an authorized Clinic actor reads candidates
Then candidates are returned normally

---

### Scenario: Assigned Veterinarian is busy elsewhere

Given the Appointment's assigned Veterinarian has a confirmed commitment at
another Clinic from 12:00 to 13:00
When candidates are read for that day
Then no candidate overlapping 12:00–13:00 is returned
And nothing reveals why

---

### Scenario: Span too long

When a Clinic actor requests a range spanning more than 60 days
Then the read is rejected as invalid input

---

## 6. Dependencies

* SPEC-APT-005 — Propose Confirmed Appointment Reschedule
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
* SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 7. Out of Scope

* Guardian-facing candidates (`SPEC-APT-014`);
* suggesting another Veterinarian;
* a professional business scheduling horizon;
* candidates that cross a covered civil range or a calendar date;
* capacity modelling (`SPEC-APT-013` BR-66).

---

## 8. Verification Notes

Verification must demonstrate that:

1. the read requires `APPOINTMENT_RESCHEDULE` and the proposal Entitlement;
2. an unpublished Clinic still returns candidates;
3. a span over 60 days is rejected and a past range returns nothing;
4. the Appointment must be `CONFIRMED`, future, and without an Encounter;
5. candidate length and cadence equal the current standard duration, not the
   duration of the current confirmed scheduling context (including after a
   30 → 45 and a 60 → 30 minute change), and without a configured standard
   duration the read fails deterministically;
6. the current confirmed start is never returned, whatever the duration;
7. Clinic Availability, the assigned Veterinarian's Availability, and known
   Veterinarian conflicts exclude positions without disclosure;
8. every returned candidate round-trips through the proposal operation with an
   identical start and end;
9. the read completes within the project's performance expectations for a
   60-day range.

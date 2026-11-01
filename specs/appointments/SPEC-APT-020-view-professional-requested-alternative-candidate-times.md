# SPEC-APT-020 — View Professional Requested-Alternative Candidate Times

**Status:** APPROVED
**Requirements:** REQ-APT-008, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Allow an authorized Clinic actor to see candidate start times for one existing
`REQUESTED` Appointment before proposing an alternative time
(`SPEC-APT-018`).

Each candidate describes exactly the interval a proposal for that start would
store, so the actor proposes only times the system currently considers
feasible.

The read is advisory. It creates no hold or reservation, and the proposal
operation independently revalidates everything (`SPEC-APT-018` BR-9, BR-15).

It is distinct from:

* the Guardian-facing requestable-times read (`SPEC-APT-014`), whose
  publication and +60-day horizon rules do not apply here, and which must not
  be reused directly for this purpose;
* the confirmed-reschedule candidate read (`SPEC-APT-017`), which applies to a
  `CONFIRMED` Appointment and uses the same current standard duration
  (`SPEC-APT-013` BR-71).

Internal reuse of candidate-generation helpers is an implementation choice and
does not change either contract.

---

## 2. Preconditions

* The acting User exists and is authenticated.
* The Appointment exists.
* The acting User currently holds `APPOINTMENT_RESCHEDULE` for the
  Appointment's Clinic.
* The Organization currently holds the `APPOINTMENT_MANAGEMENT` Entitlement.
* The Clinic has a currently configured standard Appointment duration.

---

## 3. Business Rules

### BR-1 — Same authority as proposing

The read requires the same Clinic capability and the same professional
Entitlement as creating an Alternative Time proposal (`SPEC-APT-018` BR-3,
BR-4). An actor who could not propose cannot read candidates. Authority in
another Clinic is insufficient.

---

### BR-2 — Only a future actionable request

The read applies only to an Appointment that is `REQUESTED` and whose latest
requested start is still in the future (a pending request, `SPEC-APT-015`
BR-4). Otherwise the read fails with a lifecycle error rather than returning an
empty result.

The presence of a pending proposal does not prevent the read. It does prevent
proposal creation (`SPEC-APT-018` BR-16), so clients offer candidate selection
only when no proposal is pending.

---

### BR-3 — No publication requirement

The read does not require the Clinic to be published.

---

### BR-4 — Bounded query span, no business horizon

Each read covers an inclusive range of Clinic-local calendar dates whose end is
no more than 60 days after its start. A missing range, a reversed range, or a
longer span is invalid input.

This bound protects the system; it is not a business scheduling horizon. The
range may lie anywhere in the future, and a client may page indefinitely
through successive future windows. A range entirely in the past yields no
candidates.

The Guardian +60-day horizon of `SPEC-APT-014` does not apply.

---

### BR-5 — Length and step come from the current standard duration

Every candidate interval lasts the Clinic's current standard Appointment
duration, applied as real elapsed time. The same duration is the grid step:
candidate positions follow `SPEC-APT-013` BR-58 exactly — within each maximal
covered civil range of each date, positions are the range's local civil start
plus whole multiples of the standard duration; an excluded position never
shifts the grid.

Without a configured standard duration the read fails with the same
deterministic, distinguishable outcome as proposal creation
(`SPEC-APT-018` BR-11); it does not return an empty result and does not
substitute any other duration.

---

### BR-6 — Candidate validity

A position is returned only when:

* it resolves to exactly one instant in the Clinic's scheduling timezone
  (nonexistent and ambiguous civil times are omitted, `SPEC-APT-013` BR-58);
* that instant is in the future;
* it is not the start instant of the current requested scheduling context
  (`SPEC-APT-018` BR-13), whatever the duration;
* its civil interval fits within the covered civil range it was generated
  from;
* the resolved interval `[start, start + standard duration)` satisfies every
  feasibility rule of `SPEC-APT-018` BR-15: Clinic Appointment Availability
  and, where a Veterinarian is currently assigned, a current Clinic
  Assignment, that Veterinarian's Availability at the Clinic, and no other
  known overlapping `CONFIRMED` commitment of that Veterinarian at any Clinic,
  excluding this Appointment.

If the assigned Veterinarian's Clinic Assignment is no longer current, no
candidate is returned.

Without an assigned Veterinarian, candidates are not filtered by other
Appointments at the Clinic (`SPEC-APT-013` BR-66, BR-67).

---

### BR-7 — Read/write parity

For unchanged state in which the Appointment has no actionable pending
proposal, every returned candidate, submitted to `SPEC-APT-018` with its local
date, local time, and UTC offset and the current requested revision sequence,
is accepted and stores exactly the returned start and end.

---

### BR-8 — Response information

Each candidate includes:

* its Clinic-local date and local time;
* the UTC offset used to resolve it, so it can be resubmitted unambiguously;
* its server-authored end instant.

Clients present the returned end; they never compute an end or a duration.

---

### BR-9 — No disclosure of other commitments

A position excluded because of a Veterinarian conflict is simply absent. The
read never reveals that a conflict exists, nor any detail of another
Appointment, Clinic, or Organization.

---

### BR-10 — The read does not modify state

Reading candidates creates no proposal, hold, reservation, `VOID`, or other
domain state.

---

## 4. Trusted Read

A conceptual trusted read is:

```text
get_requested_appointment_alternative_candidate_start_times(
    p_appointment_id,
    p_start_date,
    p_end_date
) → (candidate_local_date, candidate_local_time, utc_offset_seconds, candidate_end_at)
```

The exact technical signature is an implementation decision within these
constraints.

---

## 5. Phase 1 Limitations

Following the existing candidate generator, a candidate interval must fit
within one covered civil range of one calendar date.

---

## 6. Scenarios

### Scenario: Candidates use the current standard duration

Given Luna's request is 10:00–10:30, established under a 30-minute standard duration
And the Clinic's standard duration is now 45 minutes
When an authorized Clinic actor reads candidates
Then every candidate lasts 45 minutes
And candidate starts follow a 45-minute cadence within each covered range
And no candidate starts at 10:00

---

### Scenario: Far-future window

Given today is 2026-10-02
When an authorized Clinic actor reads candidates for 2027-03-01 to 2027-04-30
Then candidates in that window are returned
And no business horizon rejects the range

---

### Scenario: Span too long

When a Clinic actor requests a range spanning more than 60 days
Then the read is rejected as invalid input

---

### Scenario: Unpublished Clinic

Given the Clinic is not published
When an authorized Clinic actor reads candidates
Then candidates are returned normally

---

### Scenario: Assigned Veterinarian is busy elsewhere

Given the request's assigned Veterinarian has a confirmed commitment at another Clinic from 12:00 to 13:00
When candidates are read for that day
Then no candidate overlapping 12:00–13:00 is returned
And nothing reveals why

---

### Scenario: Not a pending request

Given the Appointment is `CONFIRMED`, `CANCELLED`, `EXPIRED`, or a `REQUESTED` Appointment whose requested start has passed
When candidates are read
Then the read fails with a lifecycle error

---

### Scenario: No standard duration

Given the Clinic has no configured standard duration
When candidates are read
Then the read fails deterministically

---

## 7. Dependencies

* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-APT-015 — Expire Unconfirmed Appointment Request
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
* SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 8. Out of Scope

* Guardian-facing candidates (`SPEC-APT-014`) and any change to their horizon;
* confirmed-reschedule candidates (`SPEC-APT-017`);
* suggesting another Veterinarian;
* a professional business scheduling horizon;
* candidates that cross a covered civil range or a calendar date;
* capacity modelling (`SPEC-APT-013` BR-66).

---

## 9. Verification Notes

Verification must demonstrate that:

1. the read requires `APPOINTMENT_RESCHEDULE` for the Appointment's Clinic and
   the `APPOINTMENT_MANAGEMENT` Entitlement;
2. an unpublished Clinic still returns candidates;
3. a span over 60 days is rejected, a past range returns nothing, and a range
   beyond 60 days from today is accepted;
4. the Appointment must be a future pending `REQUESTED` Appointment;
5. without a configured standard duration the read fails deterministically;
6. candidate length and cadence equal the current standard duration, not the
   duration of the current requested context;
7. the current requested start instant is never returned;
8. Clinic Availability, the assigned Veterinarian's current Clinic Assignment
   and Availability, and known Veterinarian conflicts exclude positions without
   disclosure;
9. every returned candidate round-trips through `SPEC-APT-018` with an
   identical start and end;
10. the read writes nothing;
11. the read completes within the project's performance expectations for a
    60-day range.

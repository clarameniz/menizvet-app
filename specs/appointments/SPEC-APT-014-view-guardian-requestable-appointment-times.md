# SPEC-APT-014 — View Guardian Requestable Appointment Times

**Status:** APPROVED
**Requirements:** REQ-APT-009
**Domain:** Appointments
**Priority:** P1

## 1. Intent

Allow an authenticated Guardian to view candidate Appointment start times that
a Clinic currently supports, before submitting a Guardian-facing Appointment
request under `SPEC-APT-001`.

This Specification defines a read-only, informational projection of:

* current Clinic Appointment Availability;
* the Clinic's current standard Appointment duration;
* the Clinic's authoritative scheduling timezone;
* the existing Phase 1 civil-time and daylight-saving rules.

It is not:

* a reservation, hold, or booking of any kind;
* a guarantee that a candidate will be confirmed;
* a Clinic-capacity or numerical-capacity model;
* a Veterinarian free/busy surface;
* a direct view of Availability configuration tables.

The authoritative write operation remains `request_appointment`
(`SPEC-APT-001`). This Specification only helps a Guardian avoid an
obviously unsupported request; it does not change what makes a request
succeed.

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.
* A target Clinic and a requested Clinic-local calendar date range are
  supplied.
* The target Clinic may or may not currently be published, have a
  configured standard Appointment duration, hold the commercial Entitlement
  required by `SPEC-APT-001`, or have any currently covered Appointment
  Availability. Every combination is a valid state for this read; a result
  with zero candidates is not an error.

---

## 3. Business Rules

### BR-1 — Candidate read requires an authenticated User

The read requires the acting User to exist and be authenticated.

No account verification, specific Pet, or Guardianship relationship is
required — this matches the established precondition for analogous
authenticated scheduling reads (`SPEC-APT-011`, `SPEC-APT-012`), which
require authentication alone. Candidate Appointment start times are
Clinic-level, not Pet-specific, and nothing about a particular Pet or a
Guardian's verification state affects Availability or the standard
duration.

---

### BR-2 — Candidate read is Clinic-scoped and requires a published Clinic

Candidates are returned for exactly one identified Clinic.

An unpublished or nonexistent Clinic returns no candidates, with no
distinguishing behavior between the two, consistent with how other public
Clinic reads in this domain already behave (for example
`get_published_clinic_location`).

---

### BR-3 — Candidate read requires the Clinic's current standard Appointment duration

Candidates are returned only when the target Clinic currently has a
configured standard Appointment duration (`SPEC-APT-013` BR-57, BR-61,
BR-62).

A Clinic with no currently configured standard duration returns no
candidates, indistinguishably from an unpublished Clinic.

---

### BR-4 — Candidate read requires the Clinic's Organization to currently hold the required commercial Entitlement

Candidates are returned only when the target Clinic's Veterinary
Organization currently holds the `APPOINTMENT_MANAGEMENT` professional
Entitlement required by `SPEC-APT-001` BR-28.

A Clinic whose Organization currently lacks that Entitlement returns no
candidates, indistinguishably from the other reasons in this section. This
read must never become a way to probe an Organization's commercial
Entitlement state.

---

### BR-5 — Unpublished, no-duration, and no-Entitlement all produce one uniform empty outcome

This read must not allow a caller to distinguish, from its outcome alone,
whether a Clinic currently has no candidates because it does not exist, is
unpublished, has no configured standard duration, lacks the required
Entitlement, or genuinely has no covered Appointment Availability during the
requested range.

All of these produce the same result: an empty candidate list for the
affected dates.

Clients present that empty result with one generic, reason-agnostic message
and must not infer or display a cause, in particular not commercial state
(`SPEC-SUB-003` §15).

---

### BR-6 — Candidate generation follows SPEC-APT-013 BR-58

Candidate positions, their resolution to concrete instants, their derived
elapsed-real-time interval, and their validation against current Clinic
Appointment Availability are governed entirely by `SPEC-APT-013` BR-58.

This Specification defines only this read's authorization, range, and
response contract; it does not restate or duplicate the candidate-generation
rules themselves.

---

### BR-7 — Only candidates whose resolved start remains in the future are returned

Consistent with `SPEC-APT-001` BR-14, a candidate whose resolved start
instant is not strictly in the future at the moment of the read is not
returned.

---

### BR-8 — REQUESTED and CONFIRMED Appointments do not filter candidates

Consistent with `SPEC-APT-013` BR-66 and BR-67, this read must not exclude a
candidate merely because it overlaps an existing `REQUESTED` or `CONFIRMED`
Appointment at the Clinic.

This Specification does not introduce a Clinic-level numerical scheduling
capacity model. A future Specification may change this; only that future
Specification may do so.

---

### BR-9 — No Veterinarian selection or exposure

This read is Clinic-level only. It must not accept, require, or expose any
Veterinarian selection, identity, assignment, or availability information.

---

### BR-10 — Structural range validity is independent of Clinic state

The caller supplies a start date and an end date.

The following are structural defects, identifiable without reference to
any Clinic, and are rejected as invalid input rather than treated as an
empty result:

* a missing start date or end date;
* an end date before the start date;
* a requested span of more than 60 days between the start date and the
  end date (that is, more than 61 inclusive calendar dates), because no
  such range could ever satisfy this Specification's maximum horizon
  regardless of which Clinic's timezone applies or whether that Clinic is
  eligible under BR-2–BR-5.

A structurally valid range is necessary but not sufficient: it does not
by itself establish that the range is acceptable relative to any specific
Clinic's current local date. That further, Clinic-relative determination
is governed by BR-11 and BR-19 — and, unlike the structural defects
above, its failure does not produce a distinguishable rejection.

---

### BR-11 — Clinic-relative horizon is evaluated only for an eligible Clinic

For a Clinic established as eligible under BR-2–BR-5, the start date and
end date are interpreted as Clinic-local calendar dates using that
Clinic's authoritative scheduling timezone. The requested range is fully
supported only when:

```text
clinic_local_today <= start_date <= end_date <= clinic_local_today + 60 days
```

The current Clinic-local date, and every date up to and including 60
calendar days after it, may therefore be queried against an eligible
Clinic — a maximum span of 61 distinct Clinic-local calendar dates (the
current date through the current date plus 60, both inclusive).

For example, if the current Clinic-local date is `2026-11-01`, the latest
date an eligible Clinic can support is `2026-12-31`.

This Clinic-relative determination requires knowing the Clinic's current
authoritative local date and therefore cannot be evaluated, and must not
be attempted, for a Clinic that is not eligible under BR-2–BR-5 (BR-19).

---

### BR-12 — Phone timezone is never authoritative for range or candidate interpretation

"Current Clinic-local date," every queried date, and every candidate date
and time are always determined using the Clinic's authoritative scheduling
timezone, never the caller's device timezone.

---

### BR-13 — Each candidate preserves enough information for unambiguous later submission

Each returned candidate includes its Clinic-local date, its Clinic-local
time, and the resolved UTC offset (or equivalent disambiguating
information) used to resolve it, so that a subsequent `SPEC-APT-001`
request for that exact candidate can supply the same identification BR-29
requires.

A local civil date and time alone must not be treated as sufficient to
identify a candidate.

---

### BR-14 — The response supports distinguishing dates with candidates from dates without

The response must allow the caller to determine, for every date in the
requested range, whether at least one candidate exists on that date,
without requiring the caller to independently evaluate Availability,
duration, or civil-time rules.

---

### BR-15 — The read exposes no private operational information

The response must not include:

* Appointment identities;
* other Guardians' Appointment or scheduling data;
* Veterinarian identity, assignment, or availability;
* raw Clinic Appointment Availability periods or exceptions;
* any commercial or internal Organization information, including which of
  the reasons in BR-5 caused an absence of candidates.

The Clinic's configured standard duration itself is not private information
under this rule; it may be exposed where it helps the Guardian understand a
candidate's length.

---

### BR-16 — Reading candidates does not create a hold, lock, or reservation

Returning a candidate does not reserve, hold, or otherwise commit any
scheduling capacity. `SPEC-APT-013` BR-34 and BR-40 continue to apply
unchanged to this read.

---

### BR-17 — The read is advisory; `request_appointment` remains independently authoritative

Consistent with `SPEC-APT-001` BR-32, a candidate returned by this read
carries no guarantee. `request_appointment` independently and
authoritatively re-reads the Clinic's current standard duration and current
Appointment Availability at the moment of the request.

Given the same authoritative Clinic state, this read and `request_appointment`
reach the same Availability conclusion (`SPEC-APT-013` BR-58). If that state
changes between the read and the request, the request may still be rejected
even though the candidate was shown.

---

### BR-18 — This read does not modify any domain state

This is a pure read operation. It must not create, modify, or delete any
Appointment, Care Authorization, Availability configuration, standard
duration configuration, or any other domain entity.

---

### BR-19 — Validation and disclosure ordering

Validation and Clinic-eligibility determination for this read must occur
in the following order, and no step may be skipped, reordered, or
short-circuited in a way that changes what a caller can observe:

1. **Structural validation (BR-10).** A structurally invalid request is
   rejected as a distinct error. This step requires no Clinic state and
   is identical for every Clinic, including a nonexistent one.
2. **Clinic eligibility (BR-2–BR-5).** For a structurally valid request,
   whether the target Clinic is nonexistent, unpublished, has no
   currently configured standard duration, or belongs to an Organization
   that does not currently hold the required `APPOINTMENT_MANAGEMENT`
   Entitlement is determined without reference to the Clinic's scheduling
   timezone or current local date. An ineligible Clinic — for any of
   these reasons, indistinguishably — produces the uniform empty result
   required by BR-5, regardless of the specific structurally valid range
   requested.
3. **Clinic-relative horizon validation (BR-11).** Only for a Clinic
   established as eligible in step 2 is the requested range further
   evaluated against that Clinic's current local date and scheduling
   timezone. A range that fails this Clinic-relative check produces the
   same uniform empty result as step 2 — not a distinguishable rejection
   — so that a caller cannot use an out-of-horizon or otherwise
   Clinic-relatively invalid range as a probe to infer that a Clinic
   passed the eligibility gate in step 2.

A structurally invalid request (step 1) and a Clinic-relative temporal
failure (step 3) must never be reported through the same mechanism as
each other's opposite: step 1 failures are always a distinguishable
rejection, and step 3 failures are always the uniform empty result,
regardless of which specific eligibility or horizon condition actually
caused it.

---

## 4. Candidate Representation

The response should support enough information for the Guardian-facing
candidate-selection UI and for a subsequent `SPEC-APT-001` request.

### Core information, per candidate

- Clinic-local date;
- Clinic-local time;
- resolved UTC offset (or equivalent disambiguating information).

### Where useful

- the Clinic's current standard Appointment duration, or the candidate's
  derived end time.

### Not included

- Appointment identity;
- Veterinarian identity or availability;
- raw Availability period or exception data;
- the specific reason a date or range has no candidates.

The exact response schema, field naming, and whether candidates are grouped
by date or returned as a flat list are architectural decisions not defined
by this Specification, provided the information above is present and BR-14
is satisfied.

---

## 5. Scenarios

### Scenario: Guardian views candidates for an eligible published Clinic

Given Animalia Madrid Centro is published
And it has a currently configured standard Appointment duration
And its Veterinary Organization currently holds `APPOINTMENT_MANAGEMENT`
And it has covered Appointment Availability on the requested date

When Maria requests candidate Appointment start times for that date

Then one or more candidates are returned
And each candidate includes a Clinic-local date, time, and disambiguating offset

---

### Scenario: Unpublished Clinic returns no candidates

Given Animalia Madrid Centro is not published

When Maria requests candidate Appointment start times for it

Then the result is an empty candidate list
And no error distinguishes this from any other reason for absence

---

### Scenario: Clinic with no configured standard duration returns no candidates

Given Animalia Madrid Centro is published
And it has no currently configured standard Appointment duration

When Maria requests candidate Appointment start times for it

Then the result is an empty candidate list
And no fallback duration is used to generate candidates

---

### Scenario: Clinic whose Organization lacks the required Entitlement returns no candidates

Given Animalia Madrid Centro is published and has a configured standard duration
And its Veterinary Organization does not currently hold `APPOINTMENT_MANAGEMENT`

When Maria requests candidate Appointment start times for it

Then the result is an empty candidate list
And the result does not reveal that the reason is Entitlement loss

---

### Scenario: Candidate overlapping a CONFIRMED Appointment is still returned

Given Animalia Madrid Centro has a CONFIRMED Appointment from 10:15 to 10:45
And the standard duration is 30 minutes

When Maria requests candidate Appointment start times

Then a candidate beginning at 10:00 and a candidate beginning at 10:30 are both returned
And neither is excluded merely because it overlaps the CONFIRMED Appointment

---

### Scenario: Candidate overlapping a REQUESTED Appointment is still returned

Given another Guardian has a REQUESTED Appointment overlapping a candidate interval

When Maria requests candidate Appointment start times for the same Clinic

Then that candidate is still returned to Maria
And its existence does not guarantee that Maria's later request will succeed

---

### Scenario: Nonexistent local start is omitted

Given a Clinic date includes a civil-time gap caused by a spring-forward transition
And a candidate civil position would fall inside that gap

When candidates are generated for that date

Then that candidate position is not exposed

---

### Scenario: Ambiguous local start is omitted

Given a Clinic date includes a repeated local hour caused by a fall-back transition
And a candidate civil position falls within that repeated hour

When candidates are generated for that date

Then that candidate position is not exposed in Phase 1

---

### Scenario: Structurally oversized range is rejected

Given a caller requests candidates with a start date and an end date more
than 60 days apart

When the request is evaluated

Then the request is rejected as structurally invalid
And this rejection occurs identically regardless of which Clinic was
targeted, including a nonexistent one

---

### Scenario: End date before start date is rejected

Given a caller supplies an end date earlier than the supplied start date

When the request is evaluated

Then the request is rejected as structurally invalid
And no Clinic state is consulted to produce this rejection

---

### Scenario: Clinic-relative out-of-horizon range for an eligible Clinic returns a uniform empty result

Given Animalia Madrid Centro is published, has a configured standard
duration, and its Organization holds `APPOINTMENT_MANAGEMENT`
And the current Clinic-local date is 2026-11-01
And Maria requests a structurally valid range from 2026-12-15 to
2027-01-10 (a 26-day span, but ending beyond 2026-12-31)

When the request is evaluated

Then the result is an empty candidate list
And no distinguishable rejection is returned
And this outcome is identical to what an ineligible Clinic would return
for the same range

---

### Scenario: Range starting before the current Clinic-local date returns a uniform empty result for an eligible Clinic

Given Animalia Madrid Centro is published, has a configured standard
duration, and its Organization holds `APPOINTMENT_MANAGEMENT`
And the current Clinic-local date is 2026-11-01
And Maria requests a structurally valid range from 2026-10-31 to
2026-11-05

When the request is evaluated

Then the result is an empty candidate list
And no distinguishable rejection is returned

---

### Scenario: A previously shown candidate is later rejected due to changed state

Given Maria viewed a candidate at 10:00 for a Clinic
And the Clinic's Availability or standard duration changes before Maria requests it

When Maria submits a request for that exact start

Then `request_appointment` independently re-evaluates current state
And the request may be rejected even though the candidate was previously shown

---

### Scenario: Dates without candidates remain distinguishable

Given a requested range includes a date with covered Availability and a date fully closed by an exception

When Maria requests candidates for that range

Then the closed date is identifiable as having no candidates
And the other date's candidates remain available

---

### Scenario: Veterinarian information is never exposed

Given Animalia Madrid Centro has several Veterinarians with different individual availability

When Maria requests candidate Appointment start times

Then no Veterinarian identity, assignment, or availability is present in the result

---

## 6. Candidate Read vs. Reservation

A candidate is current scheduling information, not a commitment.

Conceptually:

```text
candidate shown at 10:00
        ↓
Guardian submits request_appointment for 10:00
        ↓
request_appointment independently re-reads current duration and Availability
        ↓
success only if current authoritative state still supports 10:00
```

Showing a candidate never reserves it, and a Guardian's request may still be
rejected even when it targets a start time this read most recently returned.

---

## 7. Edge Cases

### Clinic configuration changes between two reads

Each read reflects only the Clinic's state at the moment it executes. This
Specification does not require or imply any caching guarantee across calls.

### A day with multiple disjoint covered ranges

Where a Clinic's Appointment Availability for a date consists of several
separated covered ranges (for example a morning and an evening range),
candidate generation restarts independently for each range, per
`SPEC-APT-013` BR-58.

### A date fully closed by an exception

A date with an applicable `CLOSED` exception produces zero candidates for
that date, indistinguishable in kind from any other date with zero
candidates.

### Smallest and largest permitted ranges

A single-day range and the maximum 61-day range are both fully supported;
no minimum range size is required.

### Clinic has no Appointment Availability configured at all

A Clinic with a configured standard duration but no Appointment Availability
periods or exceptions produces zero candidates for every requested date,
consistent with BR-5's uniform empty-result treatment.

---

## 8. Relevant Invariants

* **INV-015 — Private operations require an authenticated identity.**

---

## 9. Dependencies

* SPEC-ID-003 — Authenticate User
* SPEC-CLI-003 — Publish Clinic
* SPEC-APT-001 — Request Appointment
* SPEC-APT-013 — Manage Appointment Availability

The commercial Entitlement referenced by this workflow is evaluated through:

- SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 10. Out of Scope

This Specification does not define:

* the candidate-generation algorithm itself (governed entirely by
  `SPEC-APT-013` BR-58);
* Appointment creation or any other write behavior (governed by
  `SPEC-APT-001`);
* Veterinarian-specific candidate times or Veterinarian availability;
* any Clinic-level numerical scheduling capacity or filtering by existing
  Appointments (`SPEC-APT-013` BR-66/BR-67 apply unchanged; a future
  Specification may revisit this);
* service- or reason-specific durations;
* pagination or cursor protocols beyond the fixed bounded date range;
* the exact response schema, field naming, or grouping;
* calendar UI implementation, caching, or offline behavior;
* holds, locks, or temporary reservations of any kind;
* notification or reminder behavior.

---

## 11. Verification Notes

Verification must demonstrate that:

1. an authenticated User may perform this read without account
   verification, without Guardianship of any specific Pet, and without
   identifying any Pet at all;
2. an unpublished or nonexistent Clinic returns an empty result, not an
   error, indistinguishable from any other uniform-empty reason;
3. a Clinic with no currently configured standard duration returns an
   empty result, with no fallback duration ever applied;
4. a Clinic whose Organization lacks the required Entitlement returns an
   empty result indistinguishable from the reasons above;
5. candidate positions, resolution, and Availability validation exactly
   follow `SPEC-APT-013` BR-58, with no independent or simplified
   Availability logic introduced by this read;
6. a candidate whose resolved start is not strictly in the future is not
   returned;
7. a candidate overlapping an existing `REQUESTED` Appointment is still
   returned;
8. a candidate overlapping an existing `CONFIRMED` Appointment is still
   returned;
9. no Veterinarian identity, assignment, or availability is ever present
   in the result;
10. a request with a missing start or end date, an end date before the
    start date, or a span of more than 60 days between the two supplied
    dates is rejected as a distinguishable, structural error, identically
    for every Clinic including a nonexistent one;
11. for an eligible Clinic, a structurally valid range whose start
    precedes the current Clinic-local date, or whose end exceeds 60
    calendar days after the current Clinic-local date, produces the
    uniform empty result required by BR-5 — never a distinguishable
    rejection;
12. for an eligible Clinic, the maximum Clinic-relative range that can
    return candidates spans exactly 61 Clinic-local calendar dates
    (current date through current date plus 60, inclusive);
13. a caller cannot use a structurally valid but Clinic-relatively
    out-of-horizon or past-relative-to-today range as a probe to
    determine whether a Clinic passed the eligibility gate (BR-2–BR-5),
    because an ineligible Clinic and an eligible Clinic with such a range
    produce the identical uniform empty result;
14. structural validation, Clinic eligibility determination, and
    Clinic-relative horizon validation are applied in that fixed order
    (BR-19), and no step is skipped, reordered, or short-circuited in a
    way that changes what a caller can observe;
15. all range and candidate interpretation uses the Clinic's authoritative
    scheduling timezone regardless of device timezone;
16. every returned candidate carries sufficient information (Clinic-local
    date, time, and resolved offset) to be resubmitted unambiguously under
    `SPEC-APT-001` BR-29;
17. the response allows determining, for every requested date, whether at
    least one candidate exists;
18. no Appointment identity, other Guardian's data, raw Availability
    configuration, or commercial/internal Organization information is
    exposed;
19. reading candidates creates no hold, lock, or reservation;
20. a candidate shown by this read may still be legitimately rejected by
    `request_appointment` if authoritative state changed afterward;
21. this read never creates, modifies, or deletes any domain entity.

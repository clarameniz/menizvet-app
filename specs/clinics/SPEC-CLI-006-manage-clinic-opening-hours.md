# SPEC-CLI-006 — Manage Clinic Opening Hours

**Status:** APPROVED  
**Requirements:** REQ-CLI-005  
**Domain:** Clinics  
**Priority:** P1

## 1. Intent

Allow an authorized Organization actor to maintain the normal operating hours
of a Clinic.

Clinic Opening Hours describe when the Clinic ordinarily operates and may be
presented as public operating information.

Opening Hours must remain distinct from:

- Appointment availability;
- Veterinarian availability;
- employee shifts;
- emergency-service availability;
- temporary scheduling capacity;
- Clinical Encounter occurrence.

A Clinic being open does not necessarily mean that an Appointment can be
booked at that time.

---

## 2. Preconditions

- The Clinic exists.
- The Clinic belongs to a Veterinary Organization.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a current Organization or Clinic responsibility granting
  capability to manage Clinic operating information.
- Submitted Opening Hours are valid within the Clinic's applicable timezone.
- The resulting Opening Hours configuration is internally coherent.

---

## 3. Business Rules

### BR-1 — Opening Hours belong to a specific Clinic

Opening Hours must be associated with one specific Clinic.

An Organization operating several Clinics may define different Opening Hours
for each location.

For example:

    Animalia Madrid Centro
    Monday–Friday
    09:00–20:00

    Animalia Getafe
    Monday–Friday
    08:00–18:00

The Organization relationship must not cause Opening Hours to be shared
automatically.

---

### BR-2 — Opening Hours describe ordinary Clinic operation

Opening Hours represent when the Clinic normally operates.

They may communicate information such as:

    Monday
    09:00–20:00

    Saturday
    10:00–14:00

They do not represent detailed staff scheduling or Appointment capacity.

---

### BR-3 — Opening Hours and Appointment availability are distinct

A Clinic may be open during a period in which no Appointment may currently be
booked.

For example:

    Clinic Opening Hours:
    09:00–20:00

    Appointment Availability:
    10:00–13:00
    16:00–19:00

This is valid.

Appointment availability remains governed by `SPEC-APT-013`.

---

### BR-4 — Appointment availability must not automatically rewrite Opening Hours

Changing Appointment availability must not implicitly modify Clinic Opening
Hours.

The two concepts have different meanings and sources of truth.

---

### BR-5 — Opening Hours do not guarantee Appointment availability

A time falling within Clinic Opening Hours must not automatically be treated as
bookable.

Scheduling must still satisfy the applicable Appointment availability rules.

---

### BR-6 — Opening Hours are not an integrity boundary for Appointment availability in Phase 1

Normal Appointment availability is expected to operate within the Clinic's
applicable operating context, and an authorized actor remains responsible for
keeping the two configurations sensible.

However, in Phase 1 Clinic Opening Hours are public, informational Clinic
configuration. They are not an integrity boundary for Appointment
availability:

- configuring, changing, or clearing Appointment availability
  (`SPEC-APT-013`) must not be rejected because it falls outside the Clinic's
  current Opening Hours;
- configuring, changing, or clearing Opening Hours must not be rejected
  because existing Appointment availability falls outside them;
- neither configuration silently rewrites, restricts, or extends the other
  (BR-3, BR-4, BR-5);
- whether a time is bookable is determined solely by Appointment availability
  and the other rules of `SPEC-APT-013`.

A Clinic without any configured Opening Hours may therefore still define
Appointment availability.

A future approved Specification may introduce a non-blocking warning when the
two configurations diverge. Introducing enforcement requires a separate
approved Specification and must not be inferred from this rule.

---

### BR-7 — Opening Hours may contain more than one period per day

A Clinic may have several operating periods on the same day.

For example:

    Monday
    09:00–14:00
    16:00–20:00

The model must not assume one continuous period per day.

---

### BR-8 — Clinic may be closed on a normal weekday

A Clinic may have no regular Opening Hours for a particular day.

For example:

    Sunday
    CLOSED

Absence of an operating period for a day may represent normal closure.

---

### BR-9 — Opening Hours may be recurring

Phase 1 may represent normal weekly recurrence.

For example:

    Monday → 09:00–20:00
    Tuesday → 09:00–20:00
    Wednesday → 09:00–20:00

The exact persistence representation is architectural.

---

### BR-10 — Specific-date exceptions may override regular Opening Hours

The system must be capable of representing exceptions where ordinary recurring
hours do not apply.

Examples include:

- public holiday closure;
- exceptional early closing;
- exceptional opening;
- temporary local operating change.

The specific applicable exception takes precedence over the normal recurring
Opening Hours for that date.

---

### BR-11 — Phase 1 does not require full holiday-management functionality

Specific-date exceptions may support operational needs without requiring a
complete holiday calendar or workforce leave system.

National or regional holiday data does not need to be modeled automatically.

---

### BR-12 — Opening Hours require Clinic timezone context

Clinic Opening Hours must be interpreted using the Clinic's applicable
timezone.

The system must not depend exclusively on the viewing User's device timezone.

---

### BR-13 — Timezone changes must not change Clinic identity

Changing or correcting the applicable timezone information must not create a
new Clinic.

The Clinic remains the same domain entity.

---

### BR-14 — Opening Hours management requires explicit authorization

Only an actor whose current responsibilities grant capability to manage Clinic
operating information may modify Opening Hours.

Authentication or Organization Membership alone is insufficient.

---

### BR-15 — Authority in another Organization is insufficient

A User authorized to manage Clinic operating information for VetCare Group must
not modify Animalia Veterinary Group's Clinic Opening Hours without an
applicable Animalia authorization context.

---

### BR-16 — Veterinarian status alone does not grant Opening Hours management

A Veterinarian Professional Profile or Clinic Assignment alone must not
automatically grant authority to modify the Clinic's general Opening Hours.

Operational responsibility must authorize the action.

---

### BR-17 — Opening Hours may be configured while Clinic is unpublished

A Clinic may define its Opening Hours before becoming publicly visible.

This supports preparation of operating information before publication.

---

### BR-18 — Configuring Opening Hours does not publish Clinic

Adding or changing Opening Hours must not automatically change Clinic
publication state.

Publication remains governed by `SPEC-CLI-003`.

---

### BR-19 — Opening Hours are optional for current Phase 1 publication unless publication requirements change

The current publication model requires the information explicitly defined by
`SPEC-CLI-003`.

Opening Hours are operating information but must not silently become mandatory
for publication unless an approved Specification explicitly establishes that
rule.

---

### BR-20 — Published Clinic may expose current Opening Hours

When a Clinic is published, its current Opening Hours may be exposed as public
Clinic operating information.

Only current approved public operating information must be exposed.

---

### BR-21 — Opening Hours are public operational information where exposed

Opening Hours exposed through the published Clinic profile must not reveal:

- private employee schedules;
- internal staffing notes;
- payroll information;
- private Organization information.

Public Clinic hours and internal workforce information remain separate.

---

### BR-22 — Opening Hours do not expose which professional is working

A public statement such as:

    Monday
    09:00–20:00

must not imply which specific Veterinarians or staff are present during that
period.

Professional availability remains independently governed.

---

### BR-23 — Opening Hours do not create Veterinarian availability

Adding Clinic Opening Hours must not automatically create availability for any
assigned Veterinarian.

For example:

    Clinic open 09:00–20:00

does not imply:

    Dr. Garcia available 09:00–20:00

---

### BR-24 — Veterinarian availability does not modify Opening Hours

Changing the availability of one or more Veterinarians must not silently change
the Clinic's public operating hours.

---

### BR-25 — Clinic may be open without a currently available Veterinarian

A Clinic may remain operational for reasons other than normal bookable
consultations.

For example:

- administrative activity;
- inpatient care;
- medication or document collection;
- internal operations.

Therefore, Opening Hours must not be inferred solely from Veterinarian
availability.

---

### BR-26 — Opening Hours do not prove availability of a specific Service

A Clinic being open must not imply that every Service listed under
`SPEC-CLI-005` is available throughout the entire operating period.

For example:

    Clinic open 09:00–20:00
    SURGERY offered

does not imply:

    surgery available at 19:30.

Service-specific availability may be introduced later.

---

### BR-27 — Service configuration does not rewrite Opening Hours

Adding or removing Clinic Services must not automatically modify operating
hours.

---

### BR-28 — Opening Hours changes do not rewrite existing Appointments

Changing future Clinic Opening Hours must not:

- delete confirmed Appointments;
- cancel Appointments;
- reschedule Appointments;
- rewrite historical Appointment times.

Existing Appointment obligations must be resolved explicitly if a new
operating-hours configuration creates a conflict.

---

### BR-29 — Closing a period does not silently cancel affected Appointment

If an authorized actor changes future Opening Hours so that an already
confirmed Appointment now falls outside normal operating hours, the Appointment
must remain unchanged until explicitly resolved through the applicable
Appointment workflow.

---

### BR-30 — Historical Appointments do not depend on current Opening Hours

A historical Appointment may have occurred at a time no longer represented by
the Clinic's current Opening Hours.

Current operating information must not rewrite historical scheduling truth.

---

### BR-31 — Opening Hours changes do not rewrite medical history

Changing Clinic Opening Hours must not alter:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- clinical occurrence times;
- provider provenance.

---

### BR-32 — Opening Hours changes do not modify Clinic physical location

Operating hours and physical geographic location are separate Clinic
properties.

Changing one must not implicitly change the other.

---

### BR-33 — Opening Hours changes do not modify public contact information

Changing operating hours must not alter:

- public phone number;
- public email address;
- website;
- public display name.

These remain governed by `SPEC-CLI-004`.

---

### BR-34 — Opening Hours changes do not modify Clinic Services

Operating hours and offered veterinary Services remain separate concepts.

---

### BR-35 — Opening Hours do not create or modify Appointment lifecycle

Changing Opening Hours must not automatically:

- request Appointments;
- confirm Appointments;
- cancel Appointments;
- complete Appointments;
- create `NO_SHOW` outcomes.

---

### BR-36 — Invalid operating periods must be rejected

An Opening Hours period must have a valid start and end.

Within one ordinary same-day period:

    end time > start time

must hold.

Invalid intervals must not become current Clinic operating information.

---

### BR-37 — Overnight operating periods must be represented explicitly

If the Clinic operates across midnight, the model must not ambiguously treat:

    20:00–02:00

as an invalid ordinary same-day interval.

The system must provide an explicit representation for cross-day operating
periods if such behavior is supported.

Phase 1 may instead model the period as two adjacent daily intervals.

For example:

    Monday
    20:00–24:00

    Tuesday
    00:00–02:00

The chosen implementation must remain unambiguous.

---

### BR-38 — Overlapping periods must not create duplicate operating capacity

If two configured periods overlap, the system must not interpret the overlap as
multiple units of capacity.

For example:

    09:00–14:00
    12:00–18:00

does not mean the Clinic is "twice open" between 12:00 and 14:00.

The configuration should be normalized or rejected according to architectural
rules.

---

### BR-39 — Opening Hours may be changed without creating a new Clinic

An authorized update modifies the operating information of the existing Clinic.

Clinic identity remains stable.

---

### BR-40 — Subscription loss does not erase Opening Hours

Loss of professional Entitlement or Subscription expiration must not
destructively delete the Clinic's configured Opening Hours.

Commercial state and operating-information persistence remain separate.

---

### BR-41 — Subscription policy may affect public exposure or modification

A later or applicable Entitlement policy may determine whether an Organization
without normal professional Entitlement may:

- modify Opening Hours;
- continue exposing current Opening Hours publicly.

Such commercial rules must not rewrite the stored historical Clinic identity or
Appointments.

---

### BR-42 — Opening Hours update is atomic

A successful update must leave the Clinic with one coherent Opening Hours
configuration.

A failed update must preserve the previous valid configuration.

---

## 4. Opening Hours Information

The Clinic operating-hours model should support:

### Recurring operating periods

- Clinic;
- applicable day of week;
- start time;
- end time;
- applicable timezone.

### Specific-date exceptions where applicable

- Clinic;
- specific date;
- closed status or exceptional operating period;
- applicable timezone.

The exact persistence representation is architectural.

---

## 5. Scenarios

### Scenario: Authorized actor configures weekday Opening Hours

Given Animalia Madrid Centro exists
And Maria is authorized to manage its operating information

When Maria configures Monday Opening Hours from 09:00 to 20:00

Then the Clinic's Monday Opening Hours are stored
And the Clinic remains the same domain entity

---

### Scenario: Clinic has split Opening Hours

Given Maria is authorized to manage Animalia Madrid Centro

When Maria configures Monday:

    09:00–14:00
    16:00–20:00

Then both operating periods may be represented
And the gap from 14:00 to 16:00 is not represented as normal Opening Hours

---

### Scenario: Clinic is normally closed Sunday

Given Animalia Madrid Centro has no normal Sunday operating period

When its weekly Opening Hours are evaluated

Then Sunday may be represented as closed
And the Clinic remains a valid domain entity

---

### Scenario: Opening Hours differ from Appointment availability

Given Animalia Madrid Centro is open Monday from 09:00 to 20:00
And its Appointment availability is Monday from 10:00 to 18:00

When Appointment scheduling is evaluated at 09:30

Then the Clinic may be open
And the time may still be unavailable for Appointment booking

---

### Scenario: Available Appointment time outside normal hours is not silently accepted

Given Animalia Madrid Centro normally closes at 20:00
And a scheduling configuration attempts to expose normal Appointment
availability at 22:00

When the configuration is validated

Then the system must not silently treat 22:00 as ordinary supported booking
time without an applicable explicit operating exception

---

### Scenario: Specific holiday closure overrides recurring hours

Given Animalia Madrid Centro is normally open Monday from 09:00 to 20:00
And the Clinic has a specific closure exception for Monday 2026-12-07

When public operating information for that date is evaluated

Then the Clinic is represented as closed for that date
And the ordinary recurring Monday hours do not override the exception

---

### Scenario: Exceptional opening overrides normal closure

Given Animalia Madrid Centro is normally closed Sunday
And an authorized actor configures a one-off opening on Sunday from 10:00 to
14:00

When operating information for that date is evaluated

Then the Clinic may be represented as open from 10:00 to 14:00
And the normal recurring Sunday closure remains unchanged for other Sundays

---

### Scenario: Unauthorized Member cannot change Opening Hours

Given Maria has an active Membership in Animalia Veterinary Group
And Maria lacks operating-information management capability

When Maria attempts to change Animalia Madrid Centro's Opening Hours

Then the operation is denied
And the existing Opening Hours remain unchanged

---

### Scenario: Veterinarian status alone cannot change Opening Hours

Given Dr. Garcia has a Veterinarian Professional Profile
And a valid Clinic Assignment at Animalia Madrid Centro
And no operating-information management capability

When Dr. Garcia attempts to change the Clinic's Opening Hours

Then the operation is denied
And professional status alone is insufficient

---

### Scenario: Opening Hours may be configured before publication

Given Animalia Madrid Centro is unpublished
And Maria is authorized to manage its operating information

When Maria configures the Clinic's Opening Hours

Then the configuration may be stored
And the Clinic remains unpublished

---

### Scenario: Opening Hours update does not publish Clinic

Given Animalia Madrid Centro is unpublished
And Maria configures complete Opening Hours

When the update succeeds

Then the Clinic remains unpublished
And publication still requires the explicit workflow defined by
`SPEC-CLI-003`

---

### Scenario: Published Clinic exposes Opening Hours

Given Animalia Madrid Centro is published
And it has current Opening Hours

When an Anonymous Visitor views applicable public Clinic information

Then the current Opening Hours may be presented
And internal staff schedules are not exposed

---

### Scenario: Clinic Open Hours do not expose Veterinarian schedule

Given Animalia Madrid Centro is open from 09:00 to 20:00
And Dr. Garcia is available only from 09:00 to 13:00

When an Anonymous Visitor views Clinic Opening Hours

Then the Clinic may be shown as open until 20:00
And Dr. Garcia's professional availability is not inferred from those hours

---

### Scenario: Opening Hours do not imply Service availability

Given Animalia Madrid Centro is open from 09:00 to 20:00
And the Clinic offers `SURGERY`

When operating information is evaluated

Then the system does not infer that surgery is available throughout the full
09:00–20:00 period

---

### Scenario: Opening Hours change does not cancel existing Appointment

Given Luna has a confirmed Appointment at Animalia Madrid Centro at 19:00
And the Clinic currently closes at 20:00

When Maria changes future normal Opening Hours to close at 18:00

Then Luna's Appointment remains `CONFIRMED`
And it must be resolved explicitly if the Clinic can no longer honor it

---

### Scenario: Historical Appointment remains valid after hours change

Given Luna completed an Appointment at Animalia Madrid Centro at 19:00 in 2026
And the Clinic later changes its current Closing Hours to 18:00

When Luna's historical Appointment is viewed

Then the Appointment remains recorded at its historical time
And current Opening Hours do not rewrite that history

---

### Scenario: Opening Hours change does not alter medical history

Given Luna has finalized medical history from Animalia Madrid Centro

When Maria changes the Clinic's Opening Hours

Then Luna's Clinical Record remains unchanged
And the historical Clinic provenance remains intact

---

### Scenario: Opening Hours use Clinic timezone

Given Animalia Madrid Centro has an applicable Clinic timezone
And Maria views the Clinic from a device using another timezone

When public Opening Hours are interpreted

Then the Clinic's operating periods remain based on the Clinic scheduling
timezone
And the device timezone does not redefine the stored operating meaning

---

### Scenario: Invalid operating period is rejected

Given Maria is authorized to manage Opening Hours

When Maria attempts to configure an invalid same-day interval whose end occurs
before its start without using a supported overnight representation

Then the update is rejected
And the previous valid Opening Hours remain unchanged

---

### Scenario: Subscription expiration does not delete Opening Hours

Given Animalia Madrid Centro has configured Opening Hours
And Animalia Veterinary Group's Subscription later becomes `EXPIRED`

When the Clinic domain information is evaluated

Then its Opening Hours configuration remains preserved
And commercial expiration does not destructively delete operating information

---

### Scenario: Failed update preserves previous configuration

Given Animalia Madrid Centro has a valid Opening Hours configuration

When an attempted update fails

Then the existing configuration remains valid
And no partial operating schedule is exposed

---

## 6. Opening Hours vs Appointment Availability

These concepts answer different questions.

Opening Hours:

    "When does this Clinic ordinarily operate?"

Appointment Availability:

    "When can an Appointment currently be scheduled?"

For example:

    Opening Hours
    09:00–20:00

    Appointment Availability
    10:00–13:00
    16:00–19:00

This separation must be preserved in both domain and implementation.

---

## 7. Opening Hours vs Veterinarian Availability

Clinic Opening Hours do not define professional presence.

For example:

    Clinic
    09:00–20:00

    Dr. Garcia
    09:00–13:00

    Dr. Lopez
    13:00–20:00

The Clinic may remain continuously open while individual Veterinarian
availability differs.

Phase 1 does not require Opening Hours to be calculated dynamically from
professional schedules.

---

## 8. Public Operating Information

Opening Hours may form part of a published Clinic's public operating
information.

Conceptually:

    Clinic Public Information

    Display name
    Public phone
    Public email
    Website
    Opening Hours
    Services
    Physical location

These concepts may be presented together publicly while remaining separate
domain sources of truth.

This avoids embedding all Clinic behavior into one mutable public-profile
record.

---

## 9. Edge Cases

### Clinic operates 24 hours

The model must be capable of representing continuous daily operation without
requiring an ambiguous interval.

The exact representation may be architectural.

---

### Clinic operates across midnight

Cross-midnight operation must be modeled unambiguously.

Phase 1 may represent the operating period as adjacent periods on two calendar
days.

---

### Temporary closure

A specific-date closure exception may override ordinary recurring hours.

This does not require changing the permanent weekly schedule.

---

### Permanent change in operating schedule

An authorized actor may replace the Clinic's current recurring Opening Hours.

Historical Appointments and clinical care remain unchanged.

---

### Clinic has no configured Opening Hours

The Clinic remains a valid domain entity.

Unless publication requirements explicitly change, absence of Opening Hours
does not automatically destroy Clinic publication eligibility.

Public presentation must not invent operating hours.

---

### Appointment exists outside newly configured hours

The Appointment must not be silently changed.

Operational resolution occurs through Appointment lifecycle behavior.

---

## 10. Relevant Invariants

- **INV-005 — Organization and Clinic are different concepts.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-014 — Anonymous public discovery is allowed.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-CLI-001 — Create Clinic
- SPEC-CLI-003 — Publish Clinic
- SPEC-CLI-004 — Manage Clinic Public Profile
- SPEC-ID-003 — Authenticate User
- SPEC-ORG-003 — Accept Organization Invitation

Clinic Services are governed by:

- SPEC-CLI-005 — Manage Clinic Services

Appointment scheduling availability is governed by:

- SPEC-APT-013 — Manage Appointment Availability

Authorization follows the Organization responsibility-derived capability
model.

---

## 12. Out of Scope

This Specification does not define:

- employee shifts;
- payroll;
- staff attendance;
- Veterinarian availability;
- Appointment availability;
- Appointment capacity;
- Service-specific operating hours;
- Service-specific availability;
- emergency on-call schedules;
- public holiday data provider;
- automatic national holiday calendars;
- room or equipment availability;
- historical versioning of every Opening Hours configuration;
- Appointment cancellation caused by operating-hour changes;
- public Clinic publication requirements beyond current approved rules.

---

## 13. Verification Notes

Verification must demonstrate that:

1. authorized actors may manage Opening Hours for a specific Clinic;
2. Opening Hours remain Clinic-specific;
3. Organization Membership or Veterinarian status alone is insufficient to
   modify Opening Hours;
4. Opening Hours and Appointment availability remain distinct;
5. public Opening Hours do not automatically create bookable Appointment
   capacity;
6. multiple operating periods may exist for one day;
7. Clinics may be regularly closed on particular days;
8. recurring Opening Hours and specific-date exceptions may coexist;
9. specific-date exceptions take precedence over ordinary recurrence;
10. Clinic timezone governs operating-hour interpretation;
11. Opening Hours may be configured before publication;
12. configuring Opening Hours does not publish the Clinic;
13. published Clinics may expose current Opening Hours;
14. Opening Hours do not expose staff schedules or imply professional
    availability;
15. Opening Hours do not imply availability of every Clinic Service;
16. Opening Hours changes do not alter physical location, public contact
    information, or Clinic Services;
17. Opening Hours changes do not silently cancel or rewrite Appointments;
18. current Opening Hours do not rewrite historical Appointment or clinical
    information;
19. invalid or contradictory periods are not accepted;
20. cross-midnight operation remains unambiguous where supported;
21. Subscription loss does not erase Opening Hours configuration;
22. failed updates preserve the previous coherent configuration;
23. successful updates preserve Clinic identity and behave atomically;
24. in Phase 1, Opening Hours neither restrict nor are restricted by
    Appointment availability configuration (BR-6).
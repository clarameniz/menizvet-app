# SPEC-APT-013 — Manage Appointment Availability

**Status:** APPROVED  
**Requirements:** REQ-APT-009  
**Domain:** Appointments  
**Priority:** P1

## 1. Intent

Provide sufficient Clinic and Veterinarian availability information to prevent
Appointments from being confirmed or scheduled at unsupported times.

Phase 1 availability represents bookable veterinary scheduling capacity.

It is not intended to model a complete workforce-management or staff rota
system.

Availability must support determining whether an Appointment can reasonably be
scheduled at a particular Clinic, time, and, where applicable, with a specific
Veterinarian.

---

## 2. Preconditions

- The Clinic exists.
- The Clinic belongs to a Veterinary Organization.
- The acting User exists for availability-management operations.
- The acting User is authenticated for private management operations.
- The acting User has the applicable current capability to manage scheduling
  availability for the target Clinic.
- Where Veterinarian-specific availability is managed:
  - the Veterinarian exists;
  - the Veterinarian has a current valid Clinic Assignment at the target Clinic.
- The relevant scheduling timezone can be determined.

---

## 3. Phase 1 Availability Model

Phase 1 availability is conceptually derived from:

    Clinic bookable availability
              ∩
    Veterinarian availability
    when a specific Veterinarian is required
              -
    conflicting confirmed commitments
              ↓
    supported Appointment time

The model must provide enough information to determine whether a requested or
proposed Appointment time is supported.

It does not require a complete employee scheduling system.

---

## 4. Business Rules

### BR-1 — Clinic availability represents bookable operating capacity

A Clinic may define periods during which veterinary Appointments may normally
be scheduled.

These periods represent scheduling availability.

They do not necessarily represent:

- employee clock-in periods;
- payroll hours;
- all building opening hours;
- every operational activity performed by the Clinic.

---

### BR-2 — Public opening hours and Appointment availability are distinct concepts

Clinic public opening information may help Users understand when the Clinic
operates.

Appointment availability represents when the Clinic accepts Appointment
scheduling.

The two may overlap but must not be assumed to be identical.

For example:

    Public opening hours:
    09:00–20:00

    Bookable Appointment availability:
    09:30–13:30
    16:00–19:30

may be valid.

---

### BR-3 — Availability is Clinic-specific

Availability for one Clinic must not automatically apply to another Clinic,
even when both belong to the same Veterinary Organization.

For example:

    Animalia Madrid Centro
        availability A

    Animalia Getafe
        availability B

Each Clinic has its own scheduling context.

---

### BR-4 — Veterinarian availability is optional unless professional-specific scheduling requires it

A Clinic may support Appointment scheduling without selecting a specific
Veterinarian.

In that workflow, Clinic-level availability may be sufficient to establish a
supported Appointment time.

Where a specific Veterinarian is selected or required, that Veterinarian's
availability must also be considered.

---

### BR-5 — Veterinarian availability is Clinic-context-specific

A Veterinarian practicing at several Clinics may have different availability at
each Clinic.

For example:

    Dr. Garcia

    Animalia Madrid
    Monday morning

    Animalia Getafe
    Monday afternoon

Availability must therefore not be modeled as one global professional schedule
independent from Clinic context.

---

### BR-6 — Veterinarian availability requires current Clinic Assignment

A Veterinarian may have bookable availability at a Clinic only while they have
a current valid professional Assignment to that Clinic.

Historical Clinic Assignment must not establish current availability.

---

### BR-7 — Availability does not create Clinic Assignment

Adding availability for a Veterinarian must not:

- create a Clinic Assignment;
- reactivate an ended Clinic Assignment;
- move the Veterinarian to another Clinic.

Professional relationship and scheduling availability are separate concepts.

---

### BR-8 — Availability must preserve timezone context

Clinic and Appointment scheduling times must be interpreted using an explicit
applicable timezone.

The system must not depend solely on the mobile device timezone for determining
whether an Appointment time is valid.

---

### BR-9 — Availability may be recurring

Phase 1 may support recurring bookable periods.

For example:

    Monday
    09:00–14:00

    Tuesday
    09:00–14:00

    Wednesday
    16:00–20:00

The exact persistence representation is architectural.

---

### BR-10 — Availability may support exceptions

The system must be capable of representing exceptions to normal recurring
availability where required to prevent unsupported bookings.

Examples may include:

- Clinic closure on a specific date;
- Veterinarian unavailable for a specific period;
- one-off additional availability.

Phase 1 does not require a full leave-management system.

---

### BR-11 — Exception availability overrides ordinary recurrence where applicable

When a specific-date availability exception conflicts with normal recurring
availability, the more specific applicable scheduling information must
determine whether the period is bookable.

The system must not offer a time merely because a recurring rule exists when a
specific valid exception makes that time unavailable.

---

### BR-12 — Existing confirmed Appointment consumes scheduling capacity

A `CONFIRMED` Appointment must be considered when determining whether the same
scheduling capacity remains available.

The system must prevent incompatible overlapping confirmed commitments.

---

### BR-13 — REQUESTED Appointment does not necessarily consume confirmed capacity

A `REQUESTED` Appointment represents a request rather than a confirmed
scheduling commitment.

Phase 1 must not automatically treat every requested Appointment as permanently
blocking the requested time.

However, confirmation must evaluate current availability at the time the
Appointment is confirmed.

---

### BR-14 — Availability must be re-evaluated during confirmation

The fact that a requested time appeared available when a Guardian submitted an
Appointment request does not guarantee that it remains available later.

When the Clinic confirms the Appointment, current scheduling availability must
be evaluated again.

---

### BR-15 — Availability must be re-evaluated during accepted rescheduling

When a confirmed Appointment is moved to a new time, the proposed new time must
satisfy current scheduling availability before the reschedule becomes
effective.

---

### BR-16 — Veterinarian Assignment requires professional availability when time-specific

When a specific Veterinarian is assigned to an Appointment at a defined time,
the system must verify that the Veterinarian is available at that Clinic for
that scheduling context.

---

### BR-17 — Veterinarian reassignment requires current availability

Reassigning an Appointment to another Veterinarian must not create a scheduling
conflict.

The replacement professional must satisfy:

- valid Clinic Assignment;
- applicable professional availability;
- absence of incompatible confirmed commitments.

---

### BR-18 — Appointment duration must be considered when evaluating conflicts

Scheduling compatibility must consider the relevant Appointment duration or
reserved time interval.

The system must not evaluate only whether the Appointment start time is free.

For example:

    Appointment A
    10:00–10:30

and:

    Appointment B
    10:15–10:45

represent an overlap.

---

### BR-19 — Phase 1 may use a standard Appointment duration

Where the product has not yet introduced service-specific durations, Phase 1
may use a configured standard Appointment duration for availability
calculation.

The exact duration is an architectural or product configuration decision.

The domain must not permanently assume that every future veterinary service has
the same duration.

---

### BR-20 — Availability does not infer veterinary service capability

A free time period does not prove that the Clinic or Veterinarian can provide
every possible veterinary service.

For example:

    time available

does not imply:

    Clinic can perform surgery

Service capability remains governed separately.

---

### BR-21 — Appointment reason does not automatically determine duration in Phase 1

Phase 1 does not require a sophisticated service-duration engine.

Appointment reason or clinical triage information may later influence required
duration or resources.

That behavior must be introduced explicitly when needed.

---

### BR-22 — Availability must prevent double booking of the same Veterinarian

A Veterinarian must not be assigned to overlapping confirmed Appointments at
the same time when the applicable scheduling model requires exclusive
professional attendance.

---

### BR-23 — Multi-Clinic Veterinarian commitments must be considered

A Veterinarian practicing at several Clinics must not be booked into
incompatible overlapping confirmed Appointments across those Clinics.

For example:

    Dr. Garcia
    Animalia Madrid
    10:00–10:30

must conflict with:

    Dr. Garcia
    VetCare Centro
    10:15–10:45

where both commitments require her attendance.

---

### BR-24 — Clinic-level capacity may exist without assigned Veterinarian

A Clinic may confirm an Appointment without assigning a specific Veterinarian
where the applicable Appointment workflow permits later Assignment.

In that case, the Clinic must still have applicable bookable capacity.

---

### BR-25 — Phase 1 does not require room or equipment scheduling

Availability does not need to model individual:

- examination rooms;
- surgery rooms;
- imaging equipment;
- kennels;
- operating theatres;
- other physical resources.

Such resource scheduling may be introduced later if product requirements
justify it.

---

### BR-26 — Phase 1 does not require employee shift management

Veterinarian availability must not be treated as a complete employment rota.

The system does not need to model:

- payroll;
- clock-in or clock-out;
- contracted hours;
- overtime;
- holiday balances;
- staff attendance.

Only information required for supported Appointment scheduling is in scope.

---

### BR-27 — Availability management requires explicit authorization

Only an actor with the applicable Clinic or Organization scheduling-management
capability may create or modify Clinic availability.

Professional status or Organization Membership alone is insufficient.

---

### BR-28 — Veterinarian may not arbitrarily modify Clinic availability

Having a Veterinarian Professional Profile or Clinic Assignment does not
automatically grant authority to modify the Clinic's general scheduling
availability.

The applicable operational responsibility must authorize the change.

---

### BR-29 — Availability changes do not rewrite existing Appointment history

Changing future availability must not alter historical:

- completed Appointments;
- cancelled Appointments;
- no-show Appointments;
- previous scheduling history.

---

### BR-30 — Availability change must not silently cancel confirmed Appointment

If future availability is changed after an Appointment has already been
confirmed, the Appointment must not silently disappear or become cancelled.

The scheduling conflict must be explicitly resolved through the applicable
Appointment lifecycle.

---

### BR-31 — Removing Veterinarian availability does not erase Assignment history

Changing a Veterinarian's future availability must not erase historical
Appointment Assignments.

---

### BR-32 — Ending Clinic Assignment makes future Veterinarian availability ineffective

If a Veterinarian's Clinic Assignment ends, their future availability at that
Clinic must no longer provide a basis for new scheduling.

Historical availability need not be destructively rewritten.

---

### BR-33 — Availability does not itself create Appointment

Creating or modifying availability must not create:

- Appointment;
- Appointment request;
- Veterinarian Assignment;
- Clinical Encounter.

Availability defines supported scheduling capacity.

---

### BR-34 — Availability does not guarantee future booking

A time displayed as available represents current scheduling information.

It does not create a reservation or guarantee that the time will remain free
until an Appointment is successfully confirmed.

---

### BR-35 — Concurrent booking attempts must not produce incompatible confirmed commitments

If multiple Appointment operations compete for the same scheduling capacity,
the system must prevent final committed state from containing incompatible
confirmed bookings.

The exact locking or concurrency-control mechanism is architectural.

---

### BR-36 — Availability evaluation must occur through trusted infrastructure

The client application must not be authoritative for determining scheduling
availability.

A manipulated or stale client must not be able to force confirmation of an
unsupported Appointment.

---

### BR-37 — Subscription Entitlement may gate normal scheduling operations

Where availability management or professional scheduling is a paid capability,
the Veterinary Organization must have the applicable professional Entitlement
for normal new scheduling operations.

Entitlement loss must not delete existing availability information or
Appointment history.

---

### BR-38 — Entitlement loss does not erase availability configuration

Existing Clinic or Veterinarian availability configuration must not be deleted
solely because the Organization loses professional Entitlement.

Whether it may be modified or used for new activity depends on the applicable
Entitlement policy.

---

### BR-39 — Safe resolution after Entitlement loss remains separate

Availability information may still be required to understand or safely resolve
existing Appointment obligations after normal professional Entitlement is lost.

This must not enable new paid booking activity.

---

### BR-40 — Availability evaluation is read-only

Checking whether a time is available must not itself:

- create an Appointment;
- reserve capacity permanently;
- modify Clinic availability;
- modify Veterinarian availability.

---

### BR-41 — Availability configuration must be internally coherent

A bookable period must have a valid start and end.

The end must occur after the start within the applicable scheduling context.

Invalid or contradictory periods must not become active availability.

---

### BR-42 — Overlapping availability periods must not create duplicate capacity accidentally

Where availability rules overlap, the system must not infer multiple units of
capacity merely because several rules describe the same time period.

Phase 1 Clinic availability represents whether scheduling is supported, not an
automatic numerical staffing capacity model.

---

### BR-43 — Clinic owns the scheduling timezone

Each Clinic that participates in Appointment scheduling must have one current
scheduling timezone.

The Clinic scheduling timezone determines the civil-time context used to
interpret:

- Clinic Appointment availability;
- Veterinarian availability at that Clinic;
- requested Appointment times;
- confirmed Appointment times;
- rescheduling proposals;
- scheduling exceptions.

The scheduling timezone belongs to the Clinic context.

It must not depend on the timezone currently configured on a User's mobile
device.

---

### BR-44 — Scheduling timezone uses a named timezone

The scheduling timezone must be represented using a stable named timezone
capable of applying the applicable civil-time rules.

For example:

    Europe/Madrid

A fixed UTC offset such as:

    UTC+01:00

must not be treated as a sufficient long-term replacement for the Clinic
timezone because civil-time offsets may change through daylight-saving or
other timezone rules.

The exact timezone library and persistence representation are architectural.

---

### BR-45 — Geographic location may inform but does not silently define timezone

A Clinic's physical geographic location may be used to suggest or validate an
appropriate scheduling timezone.

However, changes to:

- address;
- latitude;
- longitude;
- geocoding-provider information

must not silently change the Clinic scheduling timezone.

Timezone is authoritative scheduling configuration once established.

---

### BR-46 — Veterinarian availability uses the Clinic scheduling timezone

Veterinarian availability defined for a specific Clinic must be interpreted
using that Clinic's scheduling timezone.

A Veterinarian practicing at several Clinics therefore does not have one
global scheduling timezone.

For example:

    Dr. Garcia
      ├── Clinic A → Europe/Madrid
      └── Clinic B → Europe/Lisbon

each Clinic context is interpreted according to its applicable timezone.

---

### BR-47 — Appointment scheduling context preserves its timezone

When a requested, confirmed, or rescheduled Appointment time is established,
the applicable scheduling timezone must remain historically identifiable as
part of that scheduling context.

A later change to the Clinic's current timezone must not make it impossible to
determine what scheduled time was originally established.

---

### BR-48 — Clinic timezone changes are prospective

Changing the Clinic's current scheduling timezone affects future scheduling
evaluation from the effective change onward.

It must not silently reinterpret previously established Appointment scheduling
history.

---

### BR-49 — Existing Appointment times must not silently move

Changing a Clinic's scheduling timezone must not automatically shift the
scheduled time of an existing Appointment.

For example, changing Clinic timezone configuration must not silently turn:

    Appointment
    10:00 Europe/Madrid

into:

    Appointment
    10:00 Europe/Lisbon

or into another instant without an explicit scheduling operation.

Where an existing future Appointment must genuinely change, the applicable
rescheduling workflow must be used.

---

### BR-50 — Historical Appointment scheduling remains stable

Timezone changes must not rewrite the scheduling context of historical:

- completed Appointments;
- cancelled Appointments;
- no-show Appointments;
- superseded requested times;
- previous confirmed times;
- accepted reschedule history.

Historical schedule interpretation must remain reconstructable.

---

### BR-51 — Recurring availability represents local Clinic time

Recurring availability rules represent local civil time in the applicable
Clinic timezone.

For example:

    Monday 09:00–14:00
    Europe/Madrid

means Monday from 09:00 to 14:00 according to the civil-time rules applicable
to `Europe/Madrid` on the relevant date.

A seasonal UTC-offset change must not automatically turn the Clinic's local
09:00 opening into local 08:00 or 10:00.

---

### BR-52 — Concrete Appointment intervals must resolve unambiguously

Before a specific Appointment scheduling commitment is established, its local
date and time must resolve to a valid concrete time interval.

The system must not silently guess when a local time is:

- nonexistent because of a civil-time clock transition; or
- ambiguous because the same local clock time occurs more than once.

The exact user-facing resolution mechanism is architectural.

---

### BR-53 — Cross-Clinic conflict detection compares actual time intervals

When a Veterinarian practices at Clinics with different scheduling timezones,
professional conflict detection must compare the actual resulting time
intervals rather than merely comparing local clock values.

For example:

    Clinic A
    10:00 Europe/Madrid

and:

    Clinic B
    10:00 America/New_York

must not be assumed to represent the same instant merely because both display
`10:00`.

---

### BR-54 — Timezone change does not rewrite availability history or Appointment history

Changing the current Clinic timezone must not:

- delete Appointment history;
- rewrite previous scheduling revisions;
- fabricate Appointment transitions;
- cancel confirmed Appointments automatically;
- create additional scheduling capacity.

Existing future scheduling conflicts created or discovered by a configuration
change require explicit operational resolution.

---

### BR-55 — Failed timezone change preserves previous scheduling configuration

If a timezone change cannot be applied coherently, the previous valid Clinic
scheduling timezone must remain authoritative.

The system must not expose partially updated scheduling configuration.

---

### BR-56 — Changing Clinic timezone while Availability is currently effective requires PROFESSIONAL_SCHEDULING

Changing the Clinic's current scheduling timezone remains an ordinary Clinic
configuration operation.

However, where the Clinic has currently effective Appointment Availability,
changing the timezone prospectively changes the actual-time interpretation of
that Availability without altering its stored local values. For this reason,
the change additionally requires the Organization's current
`PROFESSIONAL_SCHEDULING` Entitlement, evaluated as defined by `SPEC-SUB-003`.

Currently effective Appointment Availability means, for the Clinic:

- any Clinic Appointment Availability recurring period;
- any Clinic Appointment Availability exception that is not past (below);
- any Veterinarian Availability recurring period whose referenced
  Veterinarian Clinic Assignment is currently valid; or
- any Veterinarian Availability exception that is not past and whose
  referenced Veterinarian Clinic Assignment is currently valid.

An exception is past only when its local date is before the Clinic-local
current date under both the Clinic's current scheduling timezone and the
requested scheduling timezone. An exception for the current local date under
either timezone is not past, even if part of that day has already elapsed.
Both timezones are considered because a timezone change can cross the date
line and turn a date that has passed under one timezone into the current date
under the other. If the Clinic's current scheduling timezone is not valid, no
exception is past.

A past exception can no longer affect prospective scheduling, so it does not
by itself trigger this requirement. It remains stored as history, unchanged,
and — like all Availability — still requires the Clinic to keep a valid
scheduling timezone so that its local date stays interpretable. Recurring
periods have no date and always count while stored.

Veterinarian Availability referencing an ended Clinic Assignment is not
currently effective and does not by itself trigger this requirement, because
it cannot establish current professional scheduling eligibility.

The requested timezone is validated before this requirement is evaluated,
because evaluating it needs the requested timezone's current local date.

A Clinic with no currently effective Appointment Availability may have its
timezone changed under the ordinary `CLINIC_MANAGE_OPENING_HOURS` capability
alone, unchanged from prior Slice behavior.

Denial of a timezone change under this rule must not delete, rewrite, or
otherwise alter existing Availability.

---

### BR-57 — Clinic may configure a standard Appointment duration

A Clinic may configure a single current standard Appointment duration.

This duration is Clinic-level.

It is not service-specific, and it is not derived from the Clinic's current
Service offering (`SPEC-CLI-005`).

This fulfills the architectural/product configuration decision anticipated by
BR-19: Phase 1 uses a single configured standard Appointment duration rather
than a service-duration engine.

---

### BR-58 — Standard duration determines Appointment length and candidate start-time cadence, evaluated with the same Availability semantics as an actual request

The Clinic's configured standard Appointment duration determines both:

- the length of a requested Appointment interval (`SPEC-APT-001` BR-30),
  always as real elapsed time;
- the cadence of candidate Appointment start positions considered within an
  effective available civil range.

**Candidate positioning (civil grid)**

For a given calendar date, each maximal contiguous civil range of covered
Appointment Availability on that date (from the applicable recurring
periods and any applicable exceptions) is considered independently. Within
such a range, candidate positions are laid out at the range's own local
civil start plus whole multiples of the standard duration, expressed in
ordinary local civil time-of-day arithmetic (BR-51) — the same way the
underlying Availability periods and exceptions are themselves expressed.

This civil grid only determines *which* candidate positions are
considered. It does not by itself determine whether a candidate is valid
or how long its resulting Appointment would actually be.

**Candidate resolution and validity**

Each candidate civil position (a specific local date and local time) must
be resolved to a concrete instant exactly as any other Clinic civil time
in this domain (BR-52; `SPEC-APT-001` BR-29/BR-30):

- if the candidate civil position is nonexistent under the Clinic's
  authoritative timezone, it is not exposed as a candidate;
- if the candidate civil position is ambiguous under the Clinic's
  authoritative timezone, it is not exposed as a candidate in Phase 1,
  consistent with BR-52's fail-closed treatment of ambiguous Clinic civil
  time;
- otherwise the candidate civil position resolves to exactly one instant
  and may be exposed, subject to the validation below.

For each resolved candidate start instant, the candidate's full Appointment
interval is the same real elapsed interval `SPEC-APT-001` BR-30 would
establish for it: from that instant to that instant plus the standard
duration.

A candidate is supported only when that exact resolved interval satisfies
Clinic Appointment Availability under the same evaluation this Specification
applies to any other proposed Appointment interval — the same recurring
periods, the same exceptions, and the same day-boundary handling. Candidate
generation must not substitute a simplified check of whether the candidate's
*civil* interval falls within the *civil* boundaries of the range identified
above; only the fully resolved, real-elapsed-time interval's Availability
outcome is authoritative.

Candidate generation must use the same authoritative Availability evaluation
semantics that `request_appointment` applies to the resulting resolved
interval. Given the same Clinic configuration and Availability state, the
candidate read and request operation must reach the same Availability
conclusion. A later request may still be rejected if authoritative state has
changed since the candidate was read.

**Cadence stability**

Excluding a nonexistent, ambiguous, or otherwise unsupported candidate does
not shift the civil grid. Subsequent candidate positions remain anchored to
the covered range's own local civil start and to whole multiples of the
standard duration; they are never recomputed relative to the previous
supported candidate.

Candidate generation restarts independently for each maximal covered civil
range and for each calendar date; it must not be computed from an
independent global time grid (for example, a fixed 00:00-anchored 15- or
30-minute grid) that ignores where the covered range itself begins.

**Disambiguating information**

Even though Phase 1 does not expose an ambiguous candidate, a local civil
date and time alone are still not sufficient to identify an exposed
candidate for resubmission, because `SPEC-APT-001` BR-29 requires an
explicit UTC offset (or equivalent) to resolve a civil start unambiguously.
For every exposed candidate, the resolved UTC offset used to resolve it (or
equivalent disambiguating information) must also be returned, so that a
subsequent request for that exact candidate can supply the same
identification BR-29 requires. The exact response representation is defined
by `SPEC-APT-014`.

For example:

```text
Effective covered range: 09:00–14:00 (Clinic local time, no DST transition)
Standard duration: 30 minutes

Candidate civil positions: 09:00, 09:30, 10:00, ..., 13:30
Each resolves to exactly one instant and each resolved 30-minute
elapsed interval is fully supported by this range.
```

```text
Effective covered range: 01:30–04:00 (Clinic local time), a date on
which the Clinic's civil clock skips 02:00–02:59 (spring-forward)
Standard duration: 60 minutes

Candidate civil positions: 01:30, 02:30, 03:30
- 01:30 resolves to one instant; its 60-minute elapsed interval ends
  at local 03:30 (the clock having advanced) and is fully supported.
- 02:30 is nonexistent that day and is not a candidate.
- 03:30 resolves to one instant; its 60-minute elapsed interval ends
  at local 04:30, which exceeds the covered range, so it is not
  supported.
- The grid is not shifted to compensate for the excluded 02:30
  position.
```

---

### BR-59 — Standard duration management requires the same authorization as Availability management

Only an actor with the applicable current `APPOINTMENT_MANAGE_AVAILABILITY`
capability for the target Clinic, where the Veterinary Organization currently
holds the `PROFESSIONAL_SCHEDULING` Entitlement, may configure or change the
Clinic's standard Appointment duration.

Authentication or Organization Membership alone is insufficient, consistent
with BR-27.

---

### BR-60 — Standard duration remains Clinic-level for this phase

The standard Appointment duration does not vary by Clinic Service, Appointment
reason, or any other classification.

Introducing a service-specific or reason-specific duration requires a
separate approved Specification and must not be inferred from this rule.

---

### BR-61 — Valid duration is a whole number of minutes between 10 and 240

A configured standard Appointment duration, once configured, must be
expressed as a whole number of minutes no less than 10 and no greater than
240.

Configuration outside this range must not become active standard duration
configuration.

There is no implicit or default standard duration for Guardian-facing
Appointment requests in this phase: a Clinic without an explicitly configured
standard duration has no standard duration to apply, not an assumed fallback
value (see BR-62).

The exact persistence representation and constraint mechanism (for example
a `CHECK` constraint) remain an implementation step for a later migration
and are not otherwise defined by this Specification.

---

### BR-62 — Absence of a configured standard duration is a valid Clinic state, but no new scheduled interval can be constructed

A Clinic may exist, and may remain published, without a currently configured
standard Appointment duration.

This does not affect Clinic identity, publication, Services, or Opening
Hours.

However, a Clinic with no currently configured standard Appointment duration
cannot construct a new scheduled interval (BR-68). It:

- must not expose any candidate Appointment start times through the
  read-visibility contract defined by `SPEC-APT-014`;
- must not accept new Guardian-facing Appointment requests (`SPEC-APT-001`
  BR-31) or Guardian requested reschedules (`SPEC-APT-004` BR-24);
- must not create a Clinic Alternative Time proposal for a requested
  Appointment (`SPEC-APT-018` BR-11) or return Professional alternative-time
  candidates (`SPEC-APT-020` BR-5);
- must not create a confirmed-reschedule proposal from either the Guardian or
  the Clinic context (`SPEC-APT-005` BR-24) or return Professional reschedule
  candidates (`SPEC-APT-017` BR-5).

Each of these operations fails, or returns no candidates, exactly as its own
Specification defines.

Operations that adopt an existing interval are unaffected: confirmation of a
requested Appointment (`SPEC-APT-002`) and acceptance of an already pending
Reschedule Proposal on either base (`SPEC-APT-006` BR-29, `SPEC-APT-019` BR-6)
still establish the stored interval.

A Clinic actor can restore interval construction by configuring a standard
duration (BR-59, BR-74).

---

### BR-63 — Standard duration changes are prospective

Changing the Clinic's current standard Appointment duration affects every new
scheduled interval constructed, and every candidate read for such an
interval, from the effective change onward (BR-68). It does not alter an
already pending Reschedule Proposal (BR-70).

It must not retroactively change the `scheduled_start_at`/`scheduled_end_at`
of any Appointment Schedule Revision already established, consistent with
BR-29 and BR-30.

---

### BR-64 — Standard duration changes do not silently cancel or move existing Appointments

If a change to the Clinic's standard Appointment duration would have produced
a different interval for an existing `REQUESTED` or `CONFIRMED` Appointment,
the existing Appointment is not silently updated, moved, or cancelled.

Any necessary resolution follows the applicable Appointment lifecycle
Specifications, consistent with BR-30.

---

### BR-65 — Candidate Appointment start times are a derived, non-persisted, informational projection, read fresh each time

A candidate Appointment start time is computed from the Clinic Availability
and standard duration that are current at the moment the read occurs.

It is not a persisted entity, and displaying it does not create a
reservation, hold, or guarantee, consistent with §9.

The candidate read does not freeze, cache as authoritative, or carry forward
any configuration state. `request_appointment` (`SPEC-APT-001`) must
independently read and revalidate the Clinic's authoritative current standard
duration and Availability at the moment of the write; it must not trust or
reuse a previously read candidate as evidence that the interval remains
valid.

The read-visibility contract for candidate Appointment start times is defined
by `SPEC-APT-014`.

---

### BR-66 — Candidate generation is not filtered by existing CONFIRMED Appointments in this phase

Phase 1 does not model Clinic-level numerical scheduling capacity (BR-42):
several concurrent `CONFIRMED` Appointments may coexist at one Clinic,
including without any assigned Veterinarian.

For this reason, candidate Appointment start-time generation defined by
`SPEC-APT-014` must not exclude a candidate merely because it overlaps an
existing `CONFIRMED` Appointment at the Clinic.

This is a deliberate Phase 1 product decision, not an oversight: excluding
such candidates would silently assert a Clinic-level capacity of one, which
this Specification does not otherwise establish.

A future Specification may introduce an explicit Clinic or professional
capacity model; only that future Specification may change this rule.

---

### BR-67 — Candidate generation is not filtered by REQUESTED Appointments

Consistent with BR-13, a `REQUESTED` Appointment does not consume confirmed
scheduling capacity.

Candidate Appointment start-time generation defined by `SPEC-APT-014` must
not exclude a candidate merely because another Appointment already requests
an overlapping time.

Multiple Guardians may see and request the same candidate start time; only
`request_appointment` and the applicable confirmation workflow determine
which request, if any, is ultimately honored.

---

### BR-68 — Standard duration constructs every new scheduled interval

The standard Appointment duration is the Clinic policy used whenever a new
scheduled interval is constructed.

Every operation that constructs a new scheduled interval from an
actor-selected start derives its end as that resolved start plus the Clinic's
standard Appointment duration current at that operation, applied as real
elapsed time (`SPEC-APT-001` BR-30). These operations are:

- a Guardian Appointment request (`SPEC-APT-001` BR-30);
- a Guardian reschedule of a `REQUESTED` Appointment (`SPEC-APT-004` BR-23);
- a Clinic Alternative Time proposal for a `REQUESTED` Appointment
  (`SPEC-APT-018` BR-11);
- a Guardian or Clinic reschedule proposal for a `CONFIRMED` Appointment
  (`SPEC-APT-005` BR-24).

A configured standard duration is required for each of them (BR-62). Every
candidate read that offers starts for one of them uses the same current
standard duration as both length and cadence (BR-58, BR-71; `SPEC-APT-014`,
`SPEC-APT-017`, `SPEC-APT-020`).

The resulting interval is frozen in the Schedule Revision or Reschedule
Proposal the operation creates.

Operations that adopt an interval that already exists — confirmation of a
requested Appointment (`SPEC-APT-002`), Guardian acceptance of an Alternative
Time (`SPEC-APT-019`), and acceptance of a confirmed-reschedule proposal
(`SPEC-APT-006`) — establish exactly that interval and do not read the
standard duration.

A configuration change never rewrites an existing Schedule Revision or a
pending Reschedule Proposal (BR-63, BR-64, BR-70).

No proposal, Appointment, or caller supplies its own duration: Phase 1 has no
Appointment-specific, per-proposal, or service-specific duration (BR-60).

---

### BR-69 — Confirmed rescheduling uses the standard duration

A reschedule proposal for a `CONFIRMED` Appointment, from either the Guardian
or the Clinic context, proposes a new scheduled interval. It follows BR-68
like every other new interval: its length, and the length and cadence of the
Professional candidate times for it (`SPEC-APT-017`), are the Clinic's current
standard duration, and a configured standard duration is required (BR-62).

The elapsed duration of the confirmed scheduling context being replaced is
not used. A Schedule Revision stores an interval; it does not give the
Appointment an immutable duration of its own. For example:

```text
Revision N:     CONFIRMED 10:00–10:30   (standard duration then 30 minutes)
The Clinic later changes its standard duration to 45 minutes.
Revision N+1:   CONFIRMED 15:00–15:45   (accepted reschedule proposal)
```

Revision N remains immutable historical truth; Revision N+1 is a different
interval established by a later scheduling decision. Both are valid history.

This supersedes the earlier rule under which a confirmed reschedule preserved
the elapsed duration of its base confirmed scheduling context.

---

### BR-70 — Pending reschedule proposals are not affected by standard duration changes

A pending Reschedule Proposal, on either a `CONFIRMED` or a `REQUESTED` base,
stores its exact proposed interval, derived from the standard duration
current when it was created. A later standard-duration change or removal
neither alters nor invalidates it, and its acceptance establishes the stored
interval (`SPEC-APT-006` BR-28, BR-29; `SPEC-APT-018` BR-12; `SPEC-APT-019`
BR-7).

---

### BR-71 — Professional proposal candidate reads use the standard duration

Both Professional candidate reads — for a confirmed-reschedule proposal
(`SPEC-APT-017`) and for a requested Alternative Time (`SPEC-APT-020`) — use
the current standard duration as both length and cadence, with exactly the
Availability evaluation, civil-time resolution, and grid anchoring of BR-58,
and require a configured standard duration (BR-62).

Unlike the Guardian-facing read (`SPEC-APT-014`), they require no
publication, apply no +60-day business horizon (only a 60-day span per read),
and, where a Veterinarian is currently assigned, filter by that
Veterinarian's current Clinic Assignment, Availability, and known confirmed
conflicts. BR-66 and BR-67 still apply to Appointments without an assigned
Veterinarian.

A Reschedule Proposal on either base is never a way to change only the
duration of an Appointment: the same resolved start as its base scheduling
context is never proposed or offered, even when the standard duration has
changed since that context was established (`SPEC-APT-005` BR-25,
`SPEC-APT-018` BR-13). This differs deliberately from the Guardian's
unilateral requested reschedule, for which the same start with a different
standard duration is a genuine change (`SPEC-APT-004` BR-19).

---

### BR-72 — Appointment availability is independent of public Opening Hours in Phase 1

Clinic Appointment availability is configured independently of the Clinic's
public Opening Hours (`SPEC-CLI-006`).

In Phase 1, Opening Hours are not an integrity boundary for Appointment
availability (`SPEC-CLI-006` BR-6): Appointment availability configuration is
not rejected, restricted, or extended because of the Clinic's current Opening
Hours, and Opening Hours changes do not modify Appointment availability.

Whether a time is bookable is determined only by the rules of this
Specification.

---

### BR-73 — A Clinic availability exception replaces the whole local date

A Clinic Appointment availability exception applies to one Clinic-local
calendar date and has exactly one of two kinds:

- `CLOSED` — the Clinic has no Appointment availability on that date. It
  carries no periods.
- `OPEN` — the Clinic's Appointment availability on that date is exactly the
  one or more periods it carries. The periods must each have a start before
  their end and must not overlap or duplicate one another; touching periods
  are allowed.

Either kind fully replaces the recurring availability for that date (BR-11).
A date has at most one exception: establishing an exception for a date
replaces any exception already established for that date, and clearing a
date's exception restores the recurring availability for that date.

Phase 1 has no partial-day `CLOSED` exception. A partial-day closure is
represented as an `OPEN` exception containing the hours that remain
available. For example:

    Tuesdays normally: 09:00–20:00
    Next Tuesday the Clinic closes from 14:00

    → OPEN exception for that Tuesday: 09:00–14:00

A one-off opening on a normally unavailable day is likewise an `OPEN`
exception for that date (see "One-off additional availability is
supported").

The presentation of an exception (for example "closed all day", "open
exceptionally", or "custom hours") is a client concern and does not create
additional exception kinds.

---

### BR-74 — Professional management read exposes the Clinic's current Appointment-scheduling configuration

An actor with the current `APPOINTMENT_MANAGE_AVAILABILITY` capability for a
Clinic may read that Clinic's current Appointment-scheduling configuration:

- the Clinic's current scheduling timezone (BR-43), which may be absent if it
  has not yet been configured;
- the Clinic's current standard Appointment duration (BR-57), which may be
  absent (BR-62);
- the recurring Clinic Appointment availability periods, by ISO weekday, as
  stored local times;
- the weekly availability revision of exactly those recurring periods
  (BR-75);
- the Clinic Appointment availability exceptions, by local date, as stored.

The read returns stored configuration exactly; it does not derive candidate
times, merge touching periods, or evaluate Availability. It may return
exceptions for local dates that have already passed; consumers decide which
dates to present.

Consistent with `SPEC-SUB-003`, this read is understanding of existing
configuration rather than new paid scheduling activity: it does not require
the `PROFESSIONAL_SCHEDULING` Entitlement, and it remains available after
Entitlement loss (BR-38, BR-39). It does not depend on Clinic publication.

The read does not authorize changes: every configuration change is
re-authorized by its own operation.

Professional status, Clinic Assignment, or Organization Membership alone does
not grant this read (BR-27, BR-28).

---

### BR-75 — Clinic availability management operations replace configuration as a whole

Phase 1 Clinic availability management uses replacement semantics:

- recurring Clinic Appointment availability is replaced as one complete
  weekly set; submitting an empty set leaves the Clinic with no recurring
  availability;
- establishing an exception for a date replaces that date's exception
  (BR-73);
- clearing a date's exception succeeds whether or not an exception exists.

Each operation requires the current `APPOINTMENT_MANAGE_AVAILABILITY`
capability and the Organization's current `PROFESSIONAL_SCHEDULING`
Entitlement (BR-27, BR-37), and does not depend on Clinic publication.

Non-empty recurring availability and any exception require a valid Clinic
scheduling timezone (BR-43).

Concurrent management operations for the same Clinic are serialized.

A weekly replacement covers all seven days at once, so one prepared from an
outdated week would silently undo another actor's change to days its author
never touched. Whole-week replacement is therefore stale-protected:

- the Clinic has a weekly availability revision, a non-negative integer that
  identifies its stored recurring periods; it starts at 0 and increases by
  exactly one whenever a weekly replacement actually changes the stored set;
- a weekly replacement carries the revision of the week it was prepared from;
  if that is no longer the current revision, the replacement is rejected as
  stale and changes nothing; the actor must review the current week and
  submit again — the system never merges the two;
- a replacement whose set of periods equals the stored set, in any order,
  succeeds without changing the stored periods or the revision.

The revision covers only the recurring weekly periods. Exceptions, the
standard Appointment duration, and the scheduling timezone do not change it
and are not stale-protected: each replaces one date or one value the actor
sees when changing it, and the last committed change determines the result.

Clients must present the authoritative configuration after each change.

Configuration changes never rewrite established Appointment Schedule
Revisions, pending Reschedule Proposals, or Appointment lifecycle state
(BR-29, BR-30, BR-63, BR-64, BR-70).

---

### BR-76 — Setting the Clinic scheduling timezone is a Clinic self-service operation

The Clinic's current scheduling timezone (BR-43) is set through the operation

    set_clinic_scheduling_timezone(p_clinic_id uuid, p_timezone_name text) returns uuid

which is part of Clinic self-service (`SPEC-CLI-007`).

- **Capability:** the acting User's current `CLINIC_MANAGE_OPENING_HOURS`
  capability for the target Clinic. `APPOINTMENT_MANAGE_AVAILABILITY` alone
  does not authorize it; in particular a `RECEPTIONIST` who manages
  Appointment Availability cannot set the timezone.
- **Value:** the requested timezone, after removing leading and trailing
  whitespace, must be a valid named IANA timezone known to the platform
  (BR-44). Otherwise the change is rejected as invalid input (`22023`) and
  nothing changes.
- **No clearing:** the operation always sets a timezone. Phase 1 provides no
  way to remove a configured scheduling timezone.
- **Entitlement:** BR-56 remains authoritative. `PROFESSIONAL_SCHEDULING` is
  required only when the Clinic has currently effective Appointment
  Availability as defined there; otherwise no Entitlement is required.
- **Effect:** only the current scheduling timezone changes. Stored Clinic and
  Veterinarian Availability keep exactly their local wall-clock values and are
  interpreted under the new timezone from the change onward (BR-48, BR-51,
  BR-56). Existing Appointment Schedule Revisions and Reschedule Proposals keep
  their frozen timezone and intervals (BR-47, BR-49, BR-50, BR-54). Location,
  profile, and publication are unchanged, and a location change never changes
  the timezone (BR-45).
- **Concurrency:** last-write-wins with no revision token (BR-75). A change is
  serialized with other Clinic configuration writes by locking the Clinic's
  Organization and then the Clinic.
- **Ordering and disclosure:** an unauthenticated caller is rejected as
  unauthenticated; a nonexistent Clinic and a Clinic the caller may not manage
  are rejected with the same insufficient-capability outcome (`42501`); only
  then is the requested timezone validated (`22023`), and only then is the
  BR-56 Entitlement gate evaluated (`42501` with its distinct Entitlement
  message). The original implementation reported a nonexistent Clinic with a
  distinct existence error before evaluating capability; Clinic self-service
  Slice C closed this gap
  (`20261025090000_clinic_timezone_publication_self_service.sql`; see
  `docs/IMPLEMENTATION_STATUS.md`).

**Professional timezone editor (Phase 1)**

- It shows the current timezone, or that none is configured.
- It may offer the device's timezone as a suggestion. A suggestion is applied
  only when the actor explicitly selects it and saves.
- It provides an explicit, searchable choice among named IANA timezones.
- The timezone is never changed silently: not from the device timezone, not
  from the Clinic's location, and not as a side effect of any other edit.
  Phase 1 has no location-derived timezone lookup and no geocoding.
- When the Clinic has Appointment Availability, the editor may explain before
  saving that Appointment hours keep their local times in the new timezone.
- When BR-56 would require `PROFESSIONAL_SCHEDULING` and the Organization lacks
  it, the editor presents calm guidance using the existing Entitlement notice
  language rather than a generic error, and the denial changes nothing (BR-56).

**Professionals who cannot set the timezone**

A professional who can manage Appointment hours but lacks
`CLINIC_MANAGE_OPENING_HOURS` (for example a Receptionist) sees the timezone
read-only. When no timezone is configured, Appointment hours explains calmly
that a Clinic administrator must set the scheduling timezone before weekly
hours and exceptions can be edited, instead of a dead-end or generic error.

---

## 5. Availability Information

The scheduling domain must support enough information to evaluate whether a
proposed Appointment time is supported.

### Clinic availability

Where applicable:

- Clinic;
- applicable day or date;
- available start time;
- available end time;
- timezone;
- recurrence information;
- specific-date exceptions.

### Veterinarian availability

Where applicable:

- Veterinarian;
- Clinic;
- applicable day or date;
- available start time;
- available end time;
- timezone;
- recurrence information;
- specific-date exceptions.

### Scheduling context

Availability evaluation may additionally consider:

- Appointment duration;
- existing confirmed Appointments;
- current Veterinarian Assignment;
- current Clinic Assignment.

The exact persistence representation is not defined by this Specification.

---

## 6. Scenarios

### Scenario: Clinic defines recurring Appointment availability

Given Animalia Madrid Centro exists
And Carlos is authorized to manage its scheduling availability

When Carlos defines Monday bookable availability from 09:00 to 14:00

Then the Clinic may accept supported Appointment scheduling during that period
And the availability belongs specifically to Animalia Madrid Centro

---

### Scenario: Public opening hours differ from bookable hours

Given Animalia Madrid Centro publicly opens from 09:00 to 20:00
And its Appointment availability is configured from 10:00 to 18:00

When Appointment availability is evaluated

Then times before 10:00 or after 18:00 are not considered bookable solely
because the Clinic is publicly open

---

### Scenario: Specific Veterinarian availability is considered

Given Dr. Garcia has a valid Clinic Assignment at Animalia Madrid Centro
And Dr. Garcia is available Monday from 09:00 to 13:00
And the Clinic is available Monday from 09:00 to 18:00

When an Appointment specifically requiring Dr. Garcia is evaluated for Monday
at 12:00

Then the professional availability condition may be satisfied

When the same Appointment is evaluated for Monday at 16:00

Then Dr. Garcia's availability condition is not satisfied

---

### Scenario: Appointment without selected Veterinarian uses Clinic availability

Given Animalia Madrid Centro has bookable availability at 10:00
And the Appointment workflow does not require a specific Veterinarian at
request time

When Maria requests an Appointment for Luna at 10:00

Then Clinic availability may be sufficient for the initial scheduling request
And no Veterinarian Assignment is fabricated

---

### Scenario: Requested Appointment does not permanently reserve the time

Given Maria requests 10:00 for Luna
And the Appointment remains `REQUESTED`

When another scheduling operation is later evaluated

Then the existence of Maria's request does not necessarily represent a
confirmed capacity commitment
And current availability must be re-evaluated before confirmation

---

### Scenario: Confirmation detects time no longer available

Given Maria requested 10:00 for Luna
And the time was available when she submitted the request
And another valid confirmed commitment later consumes the applicable capacity

When Animalia attempts to confirm Luna's Appointment at 10:00

Then confirmation at that time is denied
And stale request-time availability does not override current scheduling truth

---

### Scenario: Confirmed Appointment consumes professional time

Given Dr. Garcia has a confirmed Appointment from 10:00 to 10:30

When another Appointment requiring Dr. Garcia is evaluated from 10:15 to 10:45

Then the second Appointment conflicts
And it must not be confirmed with Dr. Garcia for that interval

---

### Scenario: Adjacent Appointments do not overlap

Given Dr. Garcia has an Appointment from 10:00 to 10:30

When another Appointment is evaluated from 10:30 to 11:00

Then the two intervals do not overlap solely because one ends when the other
begins
And the second may remain scheduling-compatible if all other requirements are
satisfied

---

### Scenario: Veterinarian cannot be double-booked across Clinics

Given Dr. Garcia practices at Animalia Madrid Centro and VetCare Toledo
And she has a confirmed Animalia Appointment from 10:00 to 10:30

When VetCare attempts to confirm another Appointment requiring Dr. Garcia from
10:15 to 10:45

Then the scheduling conflict is detected
And the VetCare Appointment must not be confirmed with Dr. Garcia for that
interval

---

### Scenario: Ended Clinic Assignment removes future availability basis

Given Dr. Garcia previously had availability at Animalia Madrid Centro
And her Clinic Assignment later ends

When a future Appointment is evaluated for Dr. Garcia at Animalia Madrid Centro

Then the historical availability does not establish current scheduling
eligibility
And the ended Assignment prevents new professional scheduling through that
Clinic context

---

### Scenario: Specific closure overrides recurring availability

Given Animalia Madrid Centro normally has Monday availability from 09:00 to
18:00
And the Clinic has a valid closure exception for Monday 2026-12-07

When an Appointment is evaluated on 2026-12-07 at 11:00

Then the recurring Monday availability does not make that time bookable
And the specific closure exception applies

---

### Scenario: One-off additional availability is supported

Given Animalia Madrid Centro is normally unavailable on Sunday
And an authorized actor creates a one-off Sunday availability period from 10:00
to 13:00

When an Appointment is evaluated within that specific period

Then the one-off availability may support scheduling
And the normal recurring Sunday rule remains unchanged

---

### Scenario: Outdated weekly replacement is rejected

Given two actors read Animalia Madrid Centro's weekly availability at the same
revision, with Monday and Friday 09:00–13:00
And the first actor changes Monday to 10:00–14:00 and saves

When the second actor saves a week prepared from the earlier revision, with
Friday changed to 10:00–14:00

Then the second replacement is rejected as stale and changes nothing
And Monday stays 10:00–14:00 and Friday 09:00–13:00
And the second actor is shown the current week to review before saving again

---

### Scenario: Unrelated configuration does not make a weekly edit stale

Given an actor is editing Animalia Madrid Centro's weekly availability
And meanwhile another actor changes the standard Appointment duration, sets or
clears an exception, or changes the scheduling timezone

When the first actor saves the weekly availability

Then the replacement is not rejected as stale

---

### Scenario: Availability change does not silently cancel Appointment

Given Luna has a confirmed Appointment at 16:00
And an authorized actor later changes the Clinic's future general availability
so that 16:00 is no longer normally bookable

When the availability configuration changes

Then Luna's confirmed Appointment remains intact
And it must be explicitly resolved if the Clinic can no longer honor it

---

### Scenario: Availability does not infer service capability

Given Animalia Madrid Centro has free scheduling capacity at 17:00
And Animalia does not provide the veterinary service required by the requested
care

When the Appointment is evaluated

Then availability alone is insufficient to establish that the Clinic can
provide that service

---

### Scenario: Veterinarian status alone cannot modify availability

Given Dr. Garcia has a Veterinarian Professional Profile
And a valid Clinic Assignment at Animalia Madrid Centro
And she does not have scheduling-management authority

When Dr. Garcia attempts to change the Clinic's general Appointment
availability

Then the operation is denied
And professional status alone is insufficient

---

### Scenario: Authorized scheduling actor modifies availability

Given Carlos has the applicable scheduling-management responsibility at
Animalia Madrid Centro

When Carlos modifies the Clinic's future availability

Then the scheduling configuration may be updated
And historical Appointment data remains unchanged

---

### Scenario: Empty availability prevents unsupported confirmation

Given Animalia Madrid Centro has no applicable bookable availability at 03:00

When an Appointment confirmation is attempted for 03:00

Then the scheduling availability requirement is not satisfied
And the Appointment must not be confirmed at that time

---

### Scenario: Concurrent confirmations cannot double-book professional

Given Dr. Garcia has one remaining compatible time interval
And two confirmation operations concurrently attempt to assign her to
overlapping Appointments

When both operations are processed

Then the final committed state must not contain both incompatible confirmed
Appointments
And at most the valid scheduling capacity may be committed

---

### Scenario: Entitlement loss preserves availability configuration

Given Animalia Madrid Centro has configured Clinic and Veterinarian
availability
And Animalia Veterinary Group later loses normal professional Entitlement

When the availability information is evaluated historically or for safe
resolution

Then the configuration is not deleted
And it must not be used to bypass Entitlement requirements for new normal paid
scheduling activity

---

### Scenario: Clinic scheduling uses its own timezone

Given Animalia Madrid Centro uses `Europe/Madrid`
And Maria's mobile device uses another timezone

When Appointment availability is evaluated for Animalia Madrid Centro

Then the Clinic scheduling rules are interpreted using `Europe/Madrid`
And Maria's device timezone is not authoritative

---

### Scenario: Veterinarian works in Clinics with different timezones

Given Dr. Garcia practices at Clinic A using `Europe/Madrid`
And Dr. Garcia practices at Clinic B using `Europe/Lisbon`

When her availability is evaluated at each Clinic

Then each availability context uses that Clinic's timezone
And no global Veterinarian timezone is inferred

---

### Scenario: Clinic timezone change does not move confirmed Appointment

Given Luna has a confirmed Appointment at 10:00 using `Europe/Madrid`
And that scheduling context has already been established

When the Clinic's current scheduling timezone is later changed

Then Luna's existing confirmed scheduling context is not silently shifted
And changing Luna's Appointment requires the applicable explicit rescheduling
workflow

---

### Scenario: Historical Appointment preserves original timezone context

Given Luna previously completed an Appointment scheduled under
`Europe/Madrid`

When the Clinic later changes its current scheduling timezone

Then Luna's historical Appointment remains interpretable using the original
scheduling context
And its historical time is not rewritten

---

### Scenario: Address correction does not silently change scheduling timezone

Given Animalia Madrid Centro has a configured scheduling timezone
And an authorized User corrects its geographic address

When the location update succeeds

Then the existing scheduling timezone does not change solely because the
address changed

---

### Scenario: Timezone change is gated when Availability is currently effective

Given Animalia Madrid Centro has currently effective Clinic or Veterinarian
Appointment Availability
And Animalia Veterinary Group does not currently have `PROFESSIONAL_SCHEDULING`

When an authorized actor attempts to change the Clinic's scheduling timezone

Then the timezone change is denied
And the existing Availability configuration remains unchanged

---

### Scenario: Inactive Veterinarian Availability does not gate timezone change

Given Dr. Garcia's Clinic Assignment at Animalia Madrid Centro has ended
And her Veterinarian Availability rows tied to that ended Assignment remain
stored but ineffective
And no other currently effective Clinic or Veterinarian Availability exists at
Animalia Madrid Centro

When an authorized actor changes the Clinic's scheduling timezone without
`PROFESSIONAL_SCHEDULING`

Then the timezone change is not denied solely because of the inactive
Veterinarian Availability

---

### Scenario: Past exceptions do not gate timezone change

Given Animalia Madrid Centro has no recurring Appointment Availability
And its only Clinic and Veterinarian Availability exceptions are for local
dates before the current local date under both its current scheduling
timezone and the requested timezone
And Animalia Veterinary Group does not currently have `PROFESSIONAL_SCHEDULING`

When an authorized actor changes the Clinic's scheduling timezone

Then the timezone change is not denied because of those past exceptions
And the past exceptions remain stored unchanged

---

### Scenario: An exception that is current under the requested timezone still gates

Given Animalia Madrid Centro's only Appointment Availability exception is for
a local date that has passed under its current scheduling timezone but is the
current local date under the requested timezone
And Animalia Veterinary Group does not currently have `PROFESSIONAL_SCHEDULING`

When an authorized actor attempts to change the Clinic's scheduling timezone

Then the timezone change is denied
And the existing Availability configuration remains unchanged

---

### Scenario: Daylight-saving transition preserves local recurring availability

Given a Clinic has recurring availability:

    Monday 09:00–14:00
    Europe/Madrid

And the applicable UTC offset changes because of daylight-saving rules

When a Monday after that transition is evaluated

Then the Clinic remains locally available from 09:00 to 14:00
And the corresponding actual instants use the applicable timezone rules

---

### Scenario: Ambiguous scheduling time is not guessed

Given a requested local Appointment time falls within a clock transition where
the local time is ambiguous

When the system attempts to establish a concrete scheduling commitment

Then it must not silently select one possible instant
And the scheduling context must be resolved unambiguously before commitment

---

### Scenario: Cross-Clinic professional conflicts use actual instants

Given Dr. Garcia practices at Clinics using different timezones
And two proposed Appointments have different displayed local times
And those local times resolve to overlapping actual intervals

When professional availability is evaluated

Then the Appointments conflict
And both incompatible commitments must not be confirmed for Dr. Garcia

---

## 7. Phase 1 Scheduling Boundary

Phase 1 availability intentionally models:

    When may an Appointment be scheduled?

It does not model:

    Who is clocked in?
    How many hours did an employee work?
    Who is on paid leave?
    Which examination room is free?
    Which ultrasound machine is available?
    What is the payroll implication?
    Which nurse is assigned?

Those concerns require separate requirements if the product later needs them.

---

## 8. Clinic and Veterinarian Availability

The scheduling relationship can be understood as:

    Clinic bookable period
              ↓
    09:00 ───────────── 18:00

    Dr. Garcia availability
              ↓
    09:00 ─── 13:00

Therefore:

    Appointment requiring Dr. Garcia

    supported interval:
    09:00 ─── 13:00

subject also to existing confirmed commitments.

If no Veterinarian is selected:

    Clinic availability

may provide the initial scheduling boundary.

---

## 9. Availability vs Appointment Reservation

Availability represents current capacity information.

It is not itself a reservation.

Conceptually:

    available at 10:00
            ↓
    request created
            ↓
    availability may change
            ↓
    confirmation rechecks availability
            ↓
    confirmed commitment consumes capacity

This prevents request-time observations from becoming stale guarantees.

---

## 10. Edge Cases

### Daylight saving time change

Availability must remain interpretable through the applicable Clinic timezone.

The architecture must handle local clock transitions consistently.

---

### Appointment crosses availability boundary

An Appointment whose start time is within availability but whose required end
time exceeds the available interval must not be considered fully supported.

---

### Appointment duration later changes

If future product behavior introduces service-specific durations, availability
evaluation may become more precise.

The Phase 1 model must not prevent that evolution.

---

### Clinic has several simultaneous Veterinarians

Phase 1 Clinic-level availability is not necessarily a numerical capacity
model.

Where no specific Veterinarian is selected, the initial product may use
simplified Clinic scheduling rules.

A future capacity model may explicitly represent several simultaneous
Appointment slots.

---

### Veterinarian is unavailable but Clinic can assign another professional

Where the Guardian did not require a specific Veterinarian, one professional's
unavailability does not necessarily make the Clinic unavailable.

The Clinic may assign another eligible professional according to the applicable
Appointment Assignment rules.

---

### Requested time becomes unavailable before confirmation

The Clinic may decline the request by cancelling it (`SPEC-APT-003`), or
propose an alternative time for the `REQUESTED` Appointment
(`SPEC-APT-018`). A Guardian may accept that Clinic Alternative Time
(`SPEC-APT-019`); the Appointment then remains `REQUESTED` at the accepted
time until the Clinic confirms it (`SPEC-APT-002`), and confirmation
re-evaluates current availability (BR-14). Independently, the Guardian may
reschedule the request (`SPEC-APT-004`). Confirmed-reschedule proposals
(`SPEC-APT-005`) apply only to `CONFIRMED` Appointments.

The original request remains historically identifiable.

---

### Existing Appointment conflicts after availability configuration error is discovered

The system must not silently delete either Appointment.

The conflict requires explicit operational resolution.

---

## 11. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-CLI-001 — Create Clinic
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-004 — Reschedule Requested Appointment
- SPEC-APT-005 — Propose Confirmed Appointment Reschedule
- SPEC-APT-006 — Accept Appointment Reschedule Proposal
- SPEC-APT-017 — View Professional Reschedule Candidate Times
- SPEC-APT-018 — Propose Alternative Time for Requested Appointment
- SPEC-APT-019 — Accept Requested Appointment Alternative Time
- SPEC-APT-020 — View Professional Requested-Alternative Candidate Times
- SPEC-APT-007 — Assign Veterinarian to Appointment
- SPEC-APT-008 — Reassign Veterinarian
- SPEC-APT-012 — View Clinic Appointment Schedule
- SPEC-CLI-006 — Manage Clinic Opening Hours
- SPEC-CLI-007 — View Managed Clinic Configuration
- SPEC-ID-003 — Authenticate User

Where scheduling operations require paid professional capability:

- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-SUB-004 — Handle Loss of Professional Entitlements

---

## 13. Out of Scope

This Specification does not define:

- employee shift management;
- payroll;
- time tracking;
- holiday or leave balances;
- room scheduling;
- equipment scheduling;
- surgical resource scheduling;
- nurse scheduling;
- advanced capacity planning;
- service-specific Appointment durations;
- travel time between Clinics;
- automatic optimization of schedules;
- waiting lists;
- overbooking policy;
- no-show prediction;
- emergency scheduling;
- exact calendar UI;
- notification behavior.

---

## 14. Verification Notes

Verification must demonstrate that:

1. Clinic bookable availability is independently representable;
2. public opening hours and Appointment availability remain distinct;
3. availability is Clinic-specific;
4. Veterinarian availability is considered when professional-specific
   scheduling requires it;
5. Veterinarian availability is Clinic-context-specific;
6. current Clinic Assignment is required for professional availability;
7. recurring availability and specific exceptions may coexist;
8. specific applicable exceptions override ordinary recurring availability;
9. confirmed Appointments consume relevant scheduling capacity;
10. requested Appointments do not become permanent confirmed reservations;
11. current availability is re-evaluated at confirmation;
12. accepted rescheduling re-evaluates scheduling compatibility;
13. Veterinarian Assignment and reassignment detect professional conflicts;
14. Appointment duration is considered when detecting overlap;
15. overlapping confirmed Appointments for the same required Veterinarian are
    prevented;
16. multi-Clinic professional conflicts are detected;
17. Clinic-level availability may support Appointment scheduling without an
    assigned Veterinarian where permitted;
18. availability does not infer clinical service capability;
19. authorized scheduling capability is required to modify availability;
20. changing availability does not rewrite or silently cancel existing
    Appointments;
21. ending Clinic Assignment removes that relationship as a basis for future
    Veterinarian availability;
22. availability management does not create Appointments or clinical
    information;
23. concurrent scheduling operations cannot commit incompatible confirmed
    professional bookings;
24. trusted backend infrastructure enforces availability;
25. Entitlement loss does not delete scheduling configuration;
26. Phase 1 does not require workforce, room, equipment, or payroll scheduling.
27. each Clinic has an explicit current scheduling timezone;
28. the Clinic timezone does not depend on the mobile-device timezone;
29. a stable named timezone is used rather than relying only on a fixed UTC
    offset;
30. Veterinarian availability at a Clinic uses that Clinic's timezone;
31. geographic location changes do not silently change scheduling timezone;
32. Appointment scheduling contexts preserve the timezone under which they were
    established;
33. changing current Clinic timezone does not silently move existing
    Appointments;
34. historical Appointment scheduling remains interpretable after later
    timezone changes;
35. recurring availability preserves local Clinic wall-clock meaning through
    daylight-saving changes;
36. ambiguous or nonexistent civil times are not silently guessed when
    establishing concrete scheduling commitments;
37. cross-Clinic professional conflicts are evaluated using actual resolved
    intervals;
38. failed timezone changes preserve the previous valid scheduling
    configuration;
39. changing Clinic timezone while currently effective Clinic or Veterinarian
    Appointment Availability exists requires current `PROFESSIONAL_SCHEDULING`,
    while Veterinarian Availability tied only to an ended Clinic Assignment
    does not by itself impose that requirement; recurring periods always
    count, an exception counts unless its local date is before the current
    local date under both the current and the requested timezone (an
    exception for today under either counts), every exception counts when the
    current timezone is not valid, the requested timezone is validated first,
    and past exceptions stay stored unchanged and still require a valid
    scheduling timezone (BR-56);
40. every operation that constructs a new scheduled interval — Guardian
    request, Guardian requested reschedule, Clinic Alternative Time proposal,
    and Guardian or Clinic confirmed-reschedule proposal — derives its end
    from the standard duration current at that operation and is rejected
    without one, while confirmation and both acceptance operations adopt the
    stored interval without reading the standard duration (BR-62, BR-68,
    BR-69);
41. a later standard-duration change or removal neither alters nor
    invalidates a pending Reschedule Proposal on either base, and its
    acceptance establishes the stored interval (BR-70);
42. both Professional proposal candidate reads use the current standard
    duration as length and cadence, fail without one, need no publication,
    and have no +60-day horizon (BR-71);
43. Appointment availability configuration is neither restricted by nor
    restricts public Opening Hours (BR-72);
44. an exception replaces the whole local date, a date holds at most one
    exception, establishing another replaces it, clearing restores the
    recurring availability, and a partial-day closure is an `OPEN` exception
    with the remaining hours (BR-73);
45. the professional management read returns the scheduling timezone,
    standard duration, recurring periods with their weekly availability
    revision, and exceptions exactly as stored, requires
    `APPOINTMENT_MANAGE_AVAILABILITY`, and does not require
    `PROFESSIONAL_SCHEDULING` or publication (BR-74);
46. weekly availability is replaced as a whole, clearing an exception is
    idempotent, and configuration changes do not rewrite Appointment Schedule
    Revisions (BR-75); a weekly replacement prepared from an outdated
    revision is rejected with no change, a real change increments the
    revision by one, an identical set leaves it unchanged, and exceptions,
    the standard duration, and the timezone never change it (BR-75);
47. after a standard-duration change, an earlier Schedule Revision keeps its
    original interval while a later revision established from a new
    interval may have a different duration (BR-69);
48. setting the scheduling timezone requires `CLINIC_MANAGE_OPENING_HOURS`:
    Owner, Organization Administrator, and Clinic Administrator (own Clinic)
    succeed; a Receptionist, a Veterinarian, another Organization's members,
    and anonymous callers are denied with no change (BR-76);
49. a valid named timezone is stored trimmed; an invalid or blank timezone is
    rejected with `22023` and no change; no operation clears the timezone
    (BR-76);
50. the BR-56 gate applies exactly as defined there, after capability and
    timezone validation, and a denial changes nothing (BR-56, BR-76);
51. after a timezone change, stored Availability keeps its local values and
    existing Schedule Revisions and Reschedule Proposals keep their frozen
    timezone and intervals (BR-76);
52. a nonexistent Clinic and an inaccessible Clinic produce the same `42501`
    outcome (BR-76);
53. a later timezone change overwrites an earlier one without stale
    detection (BR-75, BR-76);
54. the professional editor never applies the device timezone or any
    location-derived value without an explicit selection and save, and a
    professional without `CLINIC_MANAGE_OPENING_HOURS` sees the timezone
    read-only, with guidance to ask a Clinic administrator when it is
    missing (BR-76).

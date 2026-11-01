# SPEC-APT-008 — Reassign Veterinarian

**Status:** APPROVED  
**Requirements:** REQ-APT-004, REQ-APT-005, REQ-APT-008, REQ-APT-009  
**Domain:** Appointments  
**Priority:** P1

> **Revised — Punto 8 (`APPROVED` 2026-10-23).** [SPEC-APT-007 §13](SPEC-APT-007-assign-veterinarian-to-appointment.md) (`APPROVED` 2026-10-23) replaces the client path of this Specification with `assign_appointment_veterinarian` (expected-token reassignment). BR-6 (Veterinarian Availability) no longer applies to that contract, BR-15 is superseded by self-assignment of an unassigned or stale Appointment, and BR-25 is superseded so that a `COMPLETED` Appointment may be reassigned for documentation. Reassignment never changes the authorship of existing clinical records. Until transition stage M1 is deployed this Specification describes the current implementation.

## 1. Intent

Allow an authorized Clinic actor to replace the current assigned Veterinarian
of an existing Appointment with another eligible Veterinarian while preserving
the professional Assignment history.

Reassignment changes the Veterinarian currently expected to provide care.

It must not:

- create another Appointment;
- change the Appointment's Pet;
- change the Appointment's Clinic;
- silently change the Appointment time;
- erase the previous Veterinarian Assignment.

---

## 2. Preconditions

- The Appointment exists.
- The Appointment is currently in `REQUESTED` or `CONFIRMED` state.
- The Appointment currently has an assigned Veterinarian.
- The replacement User exists.
- The replacement User has a Veterinarian Professional Profile.
- The replacement Veterinarian has a current valid Clinic Assignment at the
  Appointment's Clinic.
- The replacement Veterinarian is eligible under the scheduling constraints
  applicable to the Appointment's current scheduling context.
- The acting User exists.
- The acting User is authenticated.
- The acting User has current authorization to manage Veterinarian Assignment
  for Appointments at the relevant Clinic.
- The replacement Veterinarian is not already the current assigned
  Veterinarian.

---

## 3. Business Rules

### BR-1 — Reassignment preserves Appointment identity

Replacing the current Veterinarian must update the professional Assignment of
the existing Appointment.

It must not create a replacement Appointment.

---

### BR-2 — Previous Veterinarian Assignment must remain historical

Reassignment must not silently overwrite the previous Veterinarian.

The system must preserve enough information to establish:

- the previously assigned Veterinarian;
- when that Assignment began;
- when it ceased to be current;
- the replacement Veterinarian;
- who performed the reassignment;
- when reassignment occurred.

---

### BR-3 — Exactly one current responsible Veterinarian remains

Phase 1 supports at most one current responsible Veterinarian per Appointment.

Successful reassignment must therefore transition conceptually from:

    Dr. Garcia → current

to:

    Dr. Garcia → historical
    Dr. Lopez  → current

The system must not expose two simultaneous current responsible
Veterinarians through this workflow.

---

### BR-4 — Replacement Veterinarian must have current Clinic Assignment

The replacement Veterinarian must have a current valid Clinic Assignment at
the Appointment's Clinic.

Assignment to another Clinic is insufficient.

---

### BR-5 — Historical Clinic Assignment is insufficient

A Veterinarian whose Clinic Assignment has ended must not be selected as the
new current Veterinarian through that historical professional relationship.

---

### BR-6 — Replacement must be eligible for the Appointment's current time

The replacement Veterinarian must satisfy the professional and scheduling
constraints applicable to the Appointment's current scheduling context.

For a `REQUESTED` Appointment, eligibility applies to the current requested
time where scheduling constraints are applicable.

For a `CONFIRMED` Appointment, eligibility applies to the current confirmed
time.

---

### BR-7 — Reassignment must not silently change Appointment time

If the replacement Veterinarian is unavailable at the Appointment's current
time, reassignment must not silently move the Appointment.

A scheduling change requires the applicable Appointment rescheduling
workflow.

---

### BR-8 — Reassignment does not change Appointment lifecycle state

For a requested Appointment:

    REQUESTED + reassignment → REQUESTED

For a confirmed Appointment:

    CONFIRMED + reassignment → CONFIRMED

Professional Assignment and Appointment lifecycle remain separate concerns.

---

### BR-9 — Reassignment preserves the Pet

Replacing the Veterinarian must not change which Pet the Appointment concerns.

---

### BR-10 — Reassignment preserves the Clinic

Replacing the Veterinarian must not move the Appointment to another Clinic.

If another professional works only at another Clinic, that fact must not be
used to implicitly relocate the Appointment.

---

### BR-11 — Reassignment preserves the original requester

The User who originally requested the Appointment remains historically
identifiable.

Professional reassignment must not replace requester information.

---

### BR-12 — Reassignment preserves scheduling history

Changing the assigned Veterinarian must not rewrite:

- requested Appointment times;
- confirmed Appointment times;
- accepted reschedule history;
- scheduling proposals.

Professional Assignment history and scheduling history are separate but may
refer to the same Appointment.

---

### BR-13 — Only authorized Clinic actors may reassign

The acting User must have current responsibility-derived capability to manage
Veterinarian Assignment for Appointments at the relevant Clinic.

Authentication, Organization Membership, or Veterinarian status alone is
insufficient.

---

### BR-14 — Current Veterinarian cannot self-select their replacement without authority

The currently assigned Veterinarian must not gain reassignment authority
solely because they are assigned to the Appointment.

They may perform reassignment only when their independent professional
responsibilities grant the required capability.

---

### BR-15 — Replacement Veterinarian cannot self-assign without authority

The replacement Veterinarian must not be able to make themselves the current
responsible Veterinarian solely because they practice at the Clinic.

The authorization requirements of the Assignment-management workflow still
apply.

---

### BR-16 — Guardian preference does not perform reassignment

A Guardian may express a professional preference if future product behavior
permits it.

That preference must not directly replace the current assigned Veterinarian.

Actual reassignment remains a Clinic professional operation.

---

### BR-17 — Reassignment does not create or modify Clinic Assignment

Appointment reassignment uses existing professional Clinic relationships.

It must not:

- create a Clinic Assignment;
- reactivate an ended Clinic Assignment;
- modify Organization Membership;
- alter professional verification.

---

### BR-18 — Reassignment does not create clinical information

Replacing the assigned Veterinarian must not automatically create:

- a Medical Record Entry;
- a diagnosis;
- a Treatment;
- a clinical observation;
- a prescription.

---

### BR-19 — Reassignment does not grant unrestricted medical access

Becoming the current assigned Veterinarian must not independently grant
arbitrary or permanent access to the Pet's complete medical history.

Medical access remains governed by the applicable Access Control
Specifications.

---

### BR-20 — Professional credential verification remains independent

Phase 1 reassignment follows the same professional-verification requirements
as initial Appointment Veterinarian Assignment.

Replacing one Veterinarian with another must not be represented as evidence
that the replacement professional's credentials have been platform-verified.

---

### BR-21 — Reassignment is atomic

Successful reassignment must atomically:

1. end the previous current Appointment Veterinarian Assignment;
2. establish the replacement as the new current Veterinarian;
3. preserve the historical professional Assignment;
4. preserve the Appointment's existing lifecycle and scheduling state.

The system must not expose a valid final state containing:

- no current Veterinarian because only the first half succeeded; or
- two current responsible Veterinarians because only the second half succeeded.

---

### BR-22 — Failure to establish replacement preserves current Assignment

If the replacement Veterinarian cannot be validly assigned, the existing
current Veterinarian Assignment must remain unchanged.

The system must not remove the current professional before the replacement
can be validly established.

---

### BR-23 — Reassigning to the same Veterinarian creates no history

Attempting to replace the current assigned Veterinarian with that same
Veterinarian does not represent a meaningful reassignment.

It must not create misleading professional Assignment history.

---

### BR-24 — Cancelled Appointments cannot be reassigned through this workflow

An Appointment in `CANCELLED` state must not receive a new current
Veterinarian through normal reassignment.

---

### BR-25 — Completed Appointments cannot be reassigned

An Appointment in `COMPLETED` state represents historical care.

Its responsible Veterinarian must not be rewritten through the normal
reassignment workflow.

Historical correction, if ever required, needs a dedicated auditable
workflow.

---

### BR-26 — No-show Appointments cannot be reassigned through this workflow

An Appointment already classified as `NO_SHOW` must not receive a new current
responsible Veterinarian through normal scheduling behavior.

---

### BR-27 — Ending the previous Veterinarian's Clinic Assignment does not erase Appointment history

If reassignment occurs because the previous Veterinarian no longer practices
at the Clinic, their historical Appointment Assignment must remain
identifiable.

The end of current professional eligibility must not erase the fact that they
were previously assigned.

---

### BR-28 — Clinic unpublication does not prevent internal reassignment

An unpublished Clinic may continue managing existing Appointments internally
when it remains operational and has the required professional entitlements.

Unpublication alone must not prevent reassignment.

---

### BR-29 — Professional entitlements may restrict reassignment

Where active Subscription entitlements are required for normal professional
Appointment management, reassignment must satisfy those entitlement rules.

Safe cancellation capabilities during subscription wind-down do not imply
permission to continue normal scheduling or professional reassignment.

---

## 4. Appointment Veterinarian Assignment History

The domain must support a professional Assignment history conceptually
equivalent to:

    Appointment A

    2026-08-20
    Assigned Veterinarian:
    Dr. Garcia

    2026-08-26
    Reassigned from:
    Dr. Garcia

    Reassigned to:
    Dr. Lopez

    Changed by:
    Carlos

The exact persistence model is not defined by this Specification.

The requirement is that the previous professional Assignment must remain
historically reconstructable.

---

## 5. Scenarios

### Scenario: Reassign Veterinarian on requested Appointment

Given Luna has a `REQUESTED` Appointment at Animalia Madrid Centro
And Dr. Garcia is the current assigned Veterinarian
And Dr. Lopez has a valid current Clinic Assignment at Animalia Madrid Centro
And Dr. Lopez is eligible for the requested Appointment time
And Carlos is authorized to manage Veterinarian Assignments

When Carlos replaces Dr. Garcia with Dr. Lopez

Then Dr. Lopez becomes the current assigned Veterinarian
And Dr. Garcia's previous Assignment remains historically identifiable
And the Appointment remains `REQUESTED`
And the requested time remains unchanged

---

### Scenario: Reassign Veterinarian on confirmed Appointment

Given Luna has a `CONFIRMED` Appointment for 10:00
And Dr. Garcia is the current assigned Veterinarian
And Dr. Lopez is eligible at Animalia Madrid Centro for 10:00
And Carlos is authorized to manage Veterinarian Assignments

When Carlos reassigns the Appointment to Dr. Lopez

Then Dr. Lopez becomes the current assigned Veterinarian
And Dr. Garcia becomes the historically previous assigned Veterinarian
And the Appointment remains `CONFIRMED`
And the confirmed time remains 10:00

---

### Scenario: Replacement Veterinarian works only at another Clinic

Given Luna has an Appointment at Animalia Madrid Centro
And Dr. Lopez has an active Clinic Assignment at Animalia Getafe
And Dr. Lopez has no current Assignment at Animalia Madrid Centro

When an authorized User attempts to reassign Luna's Appointment to Dr. Lopez

Then the operation is denied
And the current Veterinarian Assignment remains unchanged

---

### Scenario: Replacement Veterinarian has historical Assignment only

Given Dr. Lopez previously practiced at Animalia Madrid Centro
And Dr. Lopez's Clinic Assignment there has ended

When an authorized User attempts to reassign Luna's current Appointment to
Dr. Lopez

Then the operation is denied
And the historical Clinic relationship is insufficient

---

### Scenario: Replacement Veterinarian is unavailable at confirmed time

Given Luna has a `CONFIRMED` Appointment for 10:00
And Dr. Garcia is the current assigned Veterinarian
And Dr. Lopez has a valid Clinic Assignment at the Clinic
And Dr. Lopez is not eligible or available at 10:00

When an authorized actor attempts to reassign the Appointment to Dr. Lopez

Then the reassignment is rejected
And Dr. Garcia remains the current assigned Veterinarian
And the Appointment remains confirmed for 10:00
And the system does not silently change the Appointment time

---

### Scenario: Reassignment preserves original requester

Given Maria originally requested Luna's Appointment
And Dr. Garcia is currently assigned

When Carlos validly reassigns the Appointment to Dr. Lopez

Then Maria remains historically identifiable as the requesting User
And Carlos is identifiable as the User who performed the reassignment
And Dr. Garcia remains identifiable as the previous Veterinarian
And Dr. Lopez becomes the current Veterinarian

---

### Scenario: Unauthorized actor cannot reassign

Given Luna has an Appointment at Animalia Madrid Centro
And Dr. Garcia is currently assigned
And Carlos does not have the capability to manage Appointment Veterinarian
Assignments for that Clinic

When Carlos attempts to replace Dr. Garcia with Dr. Lopez

Then the operation is denied
And Dr. Garcia remains the current assigned Veterinarian

---

### Scenario: Current Veterinarian cannot choose replacement without authority

Given Dr. Garcia is the current assigned Veterinarian
And Dr. Garcia does not have Appointment Assignment-management capability

When Dr. Garcia attempts to replace herself with Dr. Lopez

Then the operation is denied
And being the current Veterinarian alone is insufficient

---

### Scenario: Replacement Veterinarian cannot self-assign without authority

Given Dr. Garcia is currently assigned
And Dr. Lopez practices at the Clinic
And Dr. Lopez lacks Appointment Assignment-management capability

When Dr. Lopez attempts to replace Dr. Garcia with herself

Then the operation is denied
And Dr. Garcia remains assigned

---

### Scenario: Reassignment to same Veterinarian creates no change

Given Dr. Garcia is already the current assigned Veterinarian

When an authorized actor attempts to reassign the Appointment to Dr. Garcia

Then no professional reassignment occurs
And no misleading Assignment-history entry is created

---

### Scenario: Reassignment failure preserves previous Veterinarian

Given Dr. Garcia is the current assigned Veterinarian
And an attempted replacement with Dr. Lopez cannot be validly completed

When the reassignment operation fails

Then Dr. Garcia remains the current assigned Veterinarian
And the Appointment does not enter a partial Assignment state

---

### Scenario: Reassignment creates no clinical information

Given Luna has an Appointment
And Dr. Garcia is replaced by Dr. Lopez

When reassignment succeeds

Then no Medical Record Entry is created
And no diagnosis is created
And no Treatment is created

---

### Scenario: Cancelled Appointment cannot be reassigned

Given Luna's Appointment is `CANCELLED`

When an authorized User attempts to assign a replacement Veterinarian

Then the operation is denied
And no new current Veterinarian Assignment is established

---

### Scenario: Completed Appointment cannot be reassigned

Given Luna's Appointment is `COMPLETED`

When reassignment is attempted

Then the operation is denied
And the historically responsible professional information remains unchanged

---

### Scenario: Previous Veterinarian leaves Clinic before future Appointment

Given Dr. Garcia is assigned to Luna's future Appointment
And Dr. Garcia's Clinic Assignment ends
And Dr. Lopez is currently eligible at the same Clinic and Appointment time

When an authorized actor reassigns the Appointment to Dr. Lopez

Then Dr. Lopez becomes the current assigned Veterinarian
And Dr. Garcia remains historically identifiable as the previous assignment
And the Appointment remains the same domain entity

---

### Scenario: Clinic is unpublished before reassignment

Given Luna has an existing Appointment at Animalia Madrid Centro
And the Clinic has been unpublished
And the Clinic remains operational
And the required professional entitlements remain active
And Dr. Lopez is eligible

When an authorized actor reassigns the Appointment to Dr. Lopez

Then unpublication alone does not prevent reassignment
And all other professional and scheduling rules still apply

---

## 6. Current vs Historical Veterinarian

The system must be able to answer both:

    Who is currently expected to attend Luna's Appointment?

and:

    Which Veterinarians were previously assigned to this Appointment?

For example:

    Current:
    Dr. Lopez

    History:
    Dr. Garcia
      ↓ replaced by
    Dr. Lopez

The current Assignment is used for scheduling and current professional
eligibility.

Historical Assignments are retained for traceability.

---

## 7. Reassignment and Clinical Provenance

Appointment Veterinarian Assignment represents planned professional care.

It is not necessarily identical to the Veterinarian who ultimately performs
and documents clinical care.

For example:

    Appointment assigned to:
    Dr. Garcia

may later become:

    Appointment reassigned to:
    Dr. Lopez

and the clinical event may ultimately be authored by:

    Dr. Lopez

Clinical provenance must record the professional who actually performed or
authored the clinical activity.

Historical Appointment Assignment must not substitute for actual clinical
authorship.

---

## 8. Edge Cases

### Appointment is rescheduled after reassignment

If the Appointment time later changes, the current Veterinarian must again be
evaluated against the new scheduling context according to the applicable
rescheduling Specifications.

Successful eligibility at the old time does not imply eligibility at the new
time.

---

### Multiple reassignment operations

An Appointment may be reassigned more than once before care occurs.

Each meaningful professional change must remain historically traceable.

For example:

    Dr. Garcia
      ↓
    Dr. Lopez
      ↓
    Dr. Ruiz

Only Dr. Ruiz is current.

The earlier Assignments remain historical.

---

### Veterinarian becomes unavailable without leaving Clinic

Temporary unavailability may require reassignment even when the
Veterinarian's Clinic Assignment remains active.

Clinic Assignment determines professional relationship with the Clinic.

Scheduling eligibility determines whether the Veterinarian may handle the
specific Appointment at that time.

---

### Appointment reaches clinical activity while reassignment occurs

Once clinical care has begun, changing the responsible professional may have
clinical-provenance consequences.

In-progress clinical-care reassignment requires behavior from the Medical
Records domain and is outside this scheduling Specification.

---

## 9. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-007 — Clinic Assignment may be temporal.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 10. Dependencies

- SPEC-APT-007 — Assign Veterinarian to Appointment
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-ID-003 — Authenticate User

Scheduling changes are governed by:

- SPEC-APT-004 — Reschedule Requested Appointment
- SPEC-APT-005 — Propose Confirmed Appointment Reschedule
- SPEC-APT-006 — Accept Appointment Reschedule Proposal

---

## 11. Out of Scope

This Specification does not define:

- removing a Veterinarian without assigning a replacement;
- multiple simultaneous responsible Veterinarians;
- participating secondary professionals;
- professional availability configuration;
- shift management;
- Appointment completion;
- clinical-care handoff after treatment has begun;
- medical-record authorship;
- medical-access authorization;
- automatic reassignment;
- Guardian approval of Veterinarian reassignment;
- reassignment notifications.

---

## 12. Verification Notes

Verification must demonstrate that:

1. an authorized Clinic actor may replace the current Veterinarian;
2. reassignment preserves the existing Appointment identity;
3. the previous Veterinarian Assignment remains historically traceable;
4. exactly one current responsible Veterinarian remains after successful
   reassignment;
5. the replacement Veterinarian must have a current Clinic Assignment at the
   Appointment's Clinic;
6. historical or other-Clinic Assignments are insufficient;
7. the replacement Veterinarian must be eligible for the Appointment's current
   scheduling context;
8. reassignment must not silently change Appointment time;
9. Appointment lifecycle state remains unchanged;
10. Pet, Clinic, original requester, and scheduling history remain unchanged;
11. unauthorized professionals cannot self-assign or choose replacements;
12. Guardian preference does not establish professional reassignment;
13. reassignment does not create or modify Clinic Assignment;
14. failed reassignment preserves the existing current Veterinarian;
15. reassignment is atomic;
16. no-op reassignment creates no false history;
17. terminal Appointments cannot be reassigned through normal scheduling;
18. reassignment creates no clinical information;
19. Appointment professional Assignment history remains distinct from actual
    future clinical authorship.
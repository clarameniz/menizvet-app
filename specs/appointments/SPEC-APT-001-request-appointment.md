# SPEC-APT-001 — Request Appointment

**Status:** APPROVED
**Requirements:** REQ-APT-001, REQ-APT-002, REQ-APT-003, REQ-APT-004, REQ-APT-005, REQ-ACC-002, REQ-ACC-003
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Allow an authenticated Guardian to request a veterinary Appointment for a Pet at a published Clinic.

This Specification defines the creation of an Appointment request.

A successfully requested Appointment represents the Guardian's intention to receive veterinary care at a particular Clinic and requested time.

It does not yet imply:

* Clinic confirmation;
* assignment of a Veterinarian;
* creation of medical information;
* completion of veterinary care.

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies the account verification requirements applicable to Appointment requests.
* The Pet exists.
* The acting User has an active Guardianship relationship with the Pet.
* The Clinic exists.
* The Clinic is published.
* The Clinic has a currently configured standard Appointment duration (see
`SPEC-APT-013`).
* The Clinic's Veterinary Organization currently holds the `APPOINTMENT_MANAGEMENT` professional Entitlement.
* The requested Appointment start time is valid for the supported Appointment-request workflow.
* The acting Guardian grants the required care authorization for the Pet and
target Clinic.

---

## 3. Business Rules

### BR-1 — Appointment request requires an authenticated Guardian

A User may request an Appointment for a Pet only when they have an active Guardianship relationship with that Pet.

Authentication alone is not sufficient.

---

### BR-2 — Guardianship of another Pet grants no Appointment authority

Being Guardian of one Pet does not authorize the User to request an Appointment for another Pet.

The Appointment must concern a Pet for which the acting User has an active Guardianship relationship.

---

### BR-3 — Every Appointment concerns exactly one Pet

An Appointment request must identify exactly one Pet.

A single Appointment must not represent veterinary care for several Pets.

If several Pets require care, separate Appointments must be created unless a future approved Specification establishes another workflow.

---

### BR-4 — Every Appointment belongs to exactly one Clinic

An Appointment request must identify exactly one Clinic where the requested veterinary care is intended to occur.

The Appointment must not belong directly to a Veterinary Organization without identifying the physical Clinic.

---

### BR-5 — Guardian self-service requests require a published Clinic

The Guardian-facing Appointment-request workflow defined by this Specification may only target a currently published Clinic.

An unpublished Clinic must not accept new public self-service Appointment requests through this workflow.

Internal Clinic-created Appointments, if supported later, require separate behavior.

---

### BR-6 — Successful request creates an Appointment in requested state

A successfully created Appointment begins in the `REQUESTED` lifecycle state.

`REQUESTED` means that the Appointment has been submitted but has not yet been confirmed by the Clinic.

---

### BR-7 — Requested does not mean confirmed

Creating an Appointment request must not represent that the Clinic has accepted or guaranteed the requested time.

Confirmation requires a separate lifecycle operation.

---

### BR-8 — A Veterinarian is not required at request time

A Guardian may request an Appointment without selecting a specific Veterinarian.

The Appointment may initially exist without an assigned Veterinarian.

Veterinarian selection or assignment is governed separately.

---

### BR-9 — Appointment request records the requesting User

The system must preserve which User submitted the Appointment request.

The requesting User and the Pet are separate concepts.

The requester must not become part of the Pet's identity.

---

### BR-10 — Shared Guardians may independently request care

Any active Phase 1 Guardian of the Pet may request an Appointment for that Pet.

The User does not need to be the person who originally registered the Pet.

Example:

```text
Maria  ── Guardianship ──┐
                         │
                       Luna
                         │
Carlos ── Guardianship ──┘
```

Either Maria or Carlos may request an Appointment for Luna.

---

### BR-11 — Requesting an Appointment does not modify Guardianship

Creating an Appointment must not:

* create a new Guardian;
* remove an existing Guardian;
* modify existing Guardianship relationships.

---

### BR-12 — Requesting an Appointment does not create medical history

An Appointment request is not itself a clinical event.

Creating the Appointment must not automatically create:

* a Medical Record Entry;
* a diagnosis;
* a Treatment;
* a vaccination;
* a prescription;
* any other clinical statement.

Clinical information arises through the applicable veterinary-care workflow.

---

### BR-13 — Appointment request does not grant professional access by itself

Creating an Appointment must not automatically give every Veterinarian or Organization Member access to the Pet's protected medical information.

Any medical access associated with upcoming veterinary care must be governed by the Access Control Specifications.

---

### BR-14 — Requested time must be in the future

A new Guardian-facing Appointment request must target a future time.

The system must not create a new requested Appointment whose intended care time has already passed.

The exact timezone handling is an architectural concern and must preserve the Clinic's scheduling context.

---

### BR-15 — Appointment identity is independent from mutable Pet or Clinic display information

An Appointment must preserve its relationship with the relevant Pet and Clinic through their domain identities.

Changes to:

* Pet name;
* Clinic display name;
* Clinic public profile;

must not create a different Appointment.

---

### BR-16 — Clinic publication changes do not erase existing Appointments

If a Clinic is unpublished after an Appointment has already been requested, the existing Appointment must remain identifiable.

Unpublishing affects future public Discovery and self-service requests.

It must not delete previously created Appointments.

---

### BR-17 — Appointment creation must be atomic

A successful Appointment-request operation must create a valid Appointment with all required relationships.

The system must not expose a partial Appointment missing its required:

* Pet;
* Clinic;
* requester;
* lifecycle state;
* requested scheduling context.

---

### BR-18 — Appointment request requires a reason for visit

A Guardian-facing Appointment request must include a meaningful reason for
the intended veterinary visit.

The reason for visit provides the Clinic with enough context to understand
the purpose of the request and support operational planning.

The reason for visit is Guardian-provided information.

It must not be treated as:

- a veterinary diagnosis;
- a confirmed clinical finding;
- a Medical Record Entry;
- a substitute for professional veterinary assessment.

---

### BR-19 — Reason for visit must not require clinical terminology

A Guardian must be able to describe the reason for the visit using ordinary
language.

The system must not require the Guardian to identify a diagnosis or select a
clinical condition they may not be qualified to determine.

---

### BR-20 — Appointment request establishes an explicit care authorization

Requesting a Guardian-facing Appointment requires the acting Guardian to
explicitly authorize the target Clinic to access the Pet's relevant medical
information for the purposes of evaluating, preparing, organizing, and
providing the requested veterinary care.

The authorization applies to the Pet and Clinic identified by the Appointment.

Appointment creation alone must not be treated as implicit medical-access
authorization.

---

### BR-21 — Appointment request and required Care Authorization form one coherent operation

For the Guardian-facing Appointment workflow defined by this Specification,
successful Appointment creation and establishment of the required
Appointment-derived Care Authorization must behave as one coherent domain
operation.

Success requires both:

- a valid Appointment in `REQUESTED` state;
- the applicable active Pet Care Authorization required by this workflow.

The system must not expose the request as successfully established when only
one of those results exists.

---

### BR-22 — Successful Appointment request creates its required authorization

When the Guardian explicitly grants the Care Authorization required by this
Appointment workflow and the request succeeds:

- the Appointment must be established;
- the required Care Authorization must be established;
- both must refer to the same Pet;
- both must refer to the same target Clinic;
- the authorization must identify the Appointment-derived care context;
- the granting Guardian must be historically attributable.

Appointment existence must not substitute for the explicit authorization.

---

### BR-23 — Appointment creation failure must not leave an orphan Appointment-derived authorization

If creation of the Appointment request fails, a Care Authorization whose sole
purpose was to be established through that failed Appointment request must not
remain as a successful independent authorization.

The system must not expose:

    Care Authorization ACTIVE
        +
    no successfully established Appointment

when that authorization was created specifically as part of the failed request.

This rule does not affect Care Authorizations established independently through
another approved care workflow.

---

### BR-24 — Care Authorization creation failure must fail the Appointment request

If the required Appointment-derived Care Authorization cannot be established,
the Appointment request must not be considered successfully created.

The system must not expose:

    Appointment REQUESTED
        +
    missing required Appointment-derived Care Authorization

for this workflow.

---

### BR-25 — Partial failure preserves the previous valid domain state

If either Appointment creation or Care Authorization creation fails before the
combined operation can be committed coherently:

- no successful Appointment request is established;
- no successful Appointment-derived Care Authorization from that operation is
  established.

The previous valid domain state remains authoritative.

---

### BR-26 — Appointment-derived authorization must remain distinguishable from independent authorization

The Care Authorization created through this workflow must remain identifiable
as belonging to the Appointment-derived care context.

This must not imply that every Care Authorization requires an Appointment.

Other approved care workflows may establish Care Authorization without a
pre-existing Appointment.

---

### BR-27 — Existing unrelated Care Authorization is not silently reused

This Specification does not authorize the system to silently substitute an
unrelated existing Care Authorization for the explicit authorization required
by the Guardian-facing Appointment request.

Reuse or continuation of an existing authorization requires behavior supported
by the applicable Medical Access Control Specifications.

The request must preserve which authorization basis actually supports its care
context.

---

### BR-28 — Appointment request requires the target Organization's professional Entitlement

A Guardian-facing Appointment request must not succeed unless the target
Clinic's Veterinary Organization currently holds the `APPOINTMENT_MANAGEMENT`
professional Entitlement defined by `SPEC-SUB-003`.

This applies even though:

- the acting User is a Guardian, not a professional or Organization Member;
- the Guardian does not personally require any professional Entitlement;
- the Appointment is initially only `REQUESTED`;
- `REQUESTED` does not itself reserve confirmed professional capacity.

Accepting a new Appointment request means allowing the Organization to receive
new Appointment-management activity through the platform. That is normal paid
professional activity for the purposes of `SPEC-SUB-003`, independent of who
initiates the request.

Loss of `APPOINTMENT_MANAGEMENT` must stop new Guardian Appointment intake
without deleting or otherwise affecting existing Appointments. Existing
safe-resolution operations, including Clinic cancellation of an existing
Appointment, remain governed by `SPEC-SUB-004` and must not be blocked by the
absence of this Entitlement.

---

### BR-29 — Guardian selects only the requested start time

The Guardian-facing Appointment-request workflow requires the Guardian to
provide a single requested local start date, local start time, and the UTC
offset needed to resolve that civil time unambiguously.

The Guardian does not provide, and the system does not trust, any
Guardian-supplied end date, time, or UTC offset.

This supersedes any earlier version of this workflow that required the
Guardian to also supply an authoritative end date, time, and UTC offset.

---

### BR-30 — Appointment end time is derived from the Clinic's current standard duration as elapsed real time

The requested end time is established by the system, not the Guardian, from
the target Clinic's currently configured standard Appointment duration, as
defined by `SPEC-APT-013`.

The Guardian-supplied civil start (local date, local time, and UTC offset) is
first resolved to one unambiguous concrete instant using the Clinic's
authoritative scheduling timezone, exactly as today.

The Appointment's requested end time is then derived by adding the
configured standard duration to that resolved start instant as a fixed
elapsed-time interval — not by independently deriving and resolving a
separate civil end date and time.

The standard duration represents actual elapsed Appointment time: a
30-minute standard duration must represent exactly 30 minutes of real
elapsed time, including when that interval crosses a Clinic civil-time
offset transition (for example a daylight-saving change).

The Guardian never supplies, and the system never trusts, a Guardian-provided
end date, time, or UTC offset (BR-29).

The full resulting interval — from the resolved start instant to the
derived end instant — must satisfy the Clinic's current Appointment
Availability (`SPEC-APT-013`) before the Appointment may be created;
satisfying Availability only at the start instant is not sufficient.

---

### BR-31 — Appointment request requires a Clinic with a currently configured standard duration

A Guardian-facing Appointment request must not succeed when the target Clinic
has no currently configured standard Appointment duration.

Absence of a configured standard duration is a valid Clinic state and does
not affect Clinic existence or publication (`SPEC-APT-013` BR-62). However,
having a current configured standard duration is an additional necessary
condition for accepting a Guardian-facing Appointment request through this
workflow. This rule does not alter the existing authorization, Entitlement,
publication, non-disclosure, or validation-order requirements of this
Specification.

Rejection for this reason is a deterministic business-rule outcome, not a
transient or retryable failure, and remains distinguishable from other
rejection reasons defined by this Specification (for example an unavailable
time or a past requested time).

There is no fallback or implicit default standard duration; the system must
not substitute one.

---

### BR-32 — A previously displayed candidate start time carries no authority

Where a Guardian-facing candidate Appointment start-time read (`SPEC-APT-014`)
has been used before submitting this request, that prior read is advisory
only.

This Specification's request operation independently and authoritatively
re-reads the Clinic's current standard Appointment duration and current
Appointment Availability at the moment of the request.

A Guardian may submit a request for a start time even when no prior candidate
read was performed, or when a prior candidate read is stale. The request must
be evaluated entirely on current authoritative state; a previously displayed
candidate provides no guarantee and does not exempt the request from full
revalidation.

---

### BR-33 — Requested-time derivation does not introduce Clinic capacity or professional selection

Deriving the Appointment end from the Clinic's standard duration does not
change any other rule of this Specification.

In particular, it does not:

- require or introduce Veterinarian selection at request time (BR-8 remains
  unchanged);
- treat another Appointment's `REQUESTED` or `CONFIRMED` state at the same
  Clinic as blocking this request beyond the existing Clinic Appointment
  Availability check;
- assume or introduce a Clinic-level numerical scheduling capacity.

---

### BR-34 — Request evaluation order must not disclose commercial Entitlement state to an unauthorized caller

Guardian-domain authority over the Pet (BR-1, BR-2) must be established
before the Appointment-request workflow evaluates or exposes whether the
target Clinic's Veterinary Organization currently holds the commercial
Entitlement required by BR-28.

A caller who has not established a current Guardianship relationship with
the Pet must not be able to infer, from the outcome or behavior of this
operation, whether the target Clinic's Veterinary Organization currently
holds that Entitlement.

This rule governs only the relative order in which Guardian authority and
Entitlement state may be evaluated and disclosed. It does not change who is
authorized to request an Appointment, and it does not change the
Entitlement requirement itself (BR-28).

---

### BR-35 — At most one pending request per Pet and Clinic

Phase 1 permits several Appointments for the same Pet at the same Clinic, but
at most one **pending request** may exist for a given Pet and Clinic.

A pending request is an Appointment for that Pet and Clinic that:

- is in `REQUESTED` state; and
- whose latest requested scheduled start instant is strictly in the future
  according to authoritative backend time.

A new Appointment request for a Pet and Clinic that already have a pending
request must be rejected.

The following never block a new request:

- a `CONFIRMED` Appointment, including several future confirmed visits;
- a `COMPLETED`, `CANCELLED`, `NO_SHOW`, or `EXPIRED` Appointment;
- a `REQUESTED` Appointment whose latest requested start is no longer in the
  future, even if its expiry has not yet been materialized
  (`SPEC-APT-015` BR-4, BR-16);
- an Appointment for the same Pet at another Clinic;
- an Appointment for another Pet at the same Clinic.

The rule is Pet-scoped, not Guardian-scoped: shared Guardians (BR-10) cannot
together hold two simultaneous pending requests for the same Pet at the same
Clinic.

This rule does not introduce Clinic-level scheduling capacity (BR-33,
`SPEC-APT-013` BR-66/BR-67) and does not restrict requests for different Pets.
A Guardian who wants a different time for the existing pending request uses
rescheduling (`SPEC-APT-004`) or cancels it first (`SPEC-APT-003`).

---

### BR-36 — A rejected duplicate pending request changes nothing

A request rejected under BR-35 must not create:

- an Appointment;
- a Care Authorization;
- a Schedule Revision or Lifecycle Event;
- a Communication.

The existing pending Appointment, its scheduling history, and its Care
Authorization remain unchanged.

The rule must hold under concurrent requests: when several requests for the
same Pet and Clinic are evaluated concurrently, at most one pending request
results. The concurrency-control mechanism is architectural.

---

### BR-37 — The Guardian is informed of the Clinic's access to their contact details

Defined by **Appointment Requester Contact — Phase 1** (`SPEC-ID-006` BR-42,
`SPEC-APT-012` BR-49/BR-50).

Before submitting the request, the Guardian client states briefly and
non-intrusively that the Clinic will be able to see the requester's name and
email address to manage the Appointment.

The statement is information only. It is not a consent step, adds no input,
checkbox, or confirmation, does not change the request operation or its
evaluation, and records nothing. It does not state a legal basis.

---

## 4. Initial Appointment Information

The Appointment request must support enough information to represent the
intended veterinary visit.

### Required

- Pet;
- Clinic;
- requesting User;
- requested start date and time;
- reason for visit;
- Appointment lifecycle state.

The requested end time is not part of the Guardian-provided input. It is
derived by the system from the Clinic's currently configured standard
Appointment duration, as defined by BR-30 and `SPEC-APT-013`.

### Optional

- additional Guardian-provided notes;
- preferred Veterinarian where a later Specification permits selection.

Optional information must not become mandatory unless a later approved
Specification establishes that requirement.

---

## 5. Scenarios

### Scenario: Guardian requests an Appointment successfully

Given Maria is an authenticated User
And Maria satisfies the required verification state
And Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro is published
And Maria provides a valid future Appointment time
And Maria explicitly grants the required Care Authorization

When Maria requests an Appointment for Luna at Animalia Madrid Centro

Then an Appointment is created
And the Appointment concerns Luna
And the Appointment belongs to Animalia Madrid Centro
And Maria is recorded as the requesting User
And the Appointment state is `REQUESTED`
And no Veterinarian is required to be assigned
And the required Appointment-derived Care Authorization is established
And it concerns Luna
And it identifies Animalia Madrid Centro
And it is associated with the Appointment-derived care context

---

### Scenario: Shared Guardian requests an Appointment

Given Maria originally registered Luna
And Carlos later became an active Guardian of Luna
And Animalia Madrid Centro is published

When Carlos validly requests an Appointment for Luna

Then the Appointment may be created
And Carlos is recorded as the requesting User
And Luna remains the same Pet domain entity
And Maria's Guardianship remains unchanged

---

### Scenario: Authenticated User without Guardianship cannot request Appointment

Given Carlos is authenticated
And Luna exists
And Carlos has no active Guardianship relationship with Luna

When Carlos attempts to request an Appointment for Luna

Then the operation is denied
And no Appointment is created

---

### Scenario: Guardianship of another Pet grants no authority

Given Carlos has an active Guardianship relationship with Toby
And Carlos has no active Guardianship relationship with Luna

When Carlos attempts to request an Appointment for Luna

Then the operation is denied
And no Appointment is created

---

### Scenario: Appointment requires a Pet

Given Maria is authorized to request veterinary care

When Maria attempts to create an Appointment without identifying a Pet

Then the request is rejected
And no Appointment is created

---

### Scenario: Appointment requires a Clinic

Given Maria has an active Guardianship relationship with Luna

When Maria attempts to request an Appointment without identifying a Clinic

Then the request is rejected
And no Appointment is created

---

### Scenario: Public self-service Appointment cannot target unpublished Clinic

Given Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro exists
And Animalia Madrid Centro is not published

When Maria attempts to request an Appointment through the public Guardian workflow

Then the operation is denied
And no Appointment is created

---

### Scenario: Appointment may be requested without selecting a Veterinarian

Given Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro is published

When Maria requests a valid Appointment without selecting a Veterinarian

Then the Appointment is created in `REQUESTED` state
And the Appointment has no assigned Veterinarian
And the absence of a Veterinarian does not invalidate the request

---

### Scenario: Requested Appointment is not automatically confirmed

Given Maria validly requests an Appointment for Luna

When the Appointment is created

Then its state is `REQUESTED`
And it is not considered `CONFIRMED` solely because the request succeeded

---

### Scenario: Appointment request does not create clinical information

Given Maria validly requests an Appointment for Luna

When the Appointment is created

Then no Medical Record Entry is created solely because of the Appointment request
And no diagnosis is inferred
And no Treatment is created

---

### Scenario: Appointment request in the past is rejected

Given Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro is published

When Maria requests a new Appointment for a time that has already passed

Then the request is rejected
And no Appointment is created

---

### Scenario: Clinic becomes unpublished after Appointment request

Given Maria validly requested an Appointment for Luna at Animalia Madrid Centro
And the Appointment exists in `REQUESTED` state

When Animalia Madrid Centro is later unpublished

Then the existing Appointment remains identifiable
And the Clinic remains associated with that Appointment
And unpublishing does not delete the Appointment

---

### Scenario: Guardian provides a reason for visit

Given Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro is published

When Maria requests an Appointment for Luna
And provides "Luna has been limping since yesterday" as the reason for visit

Then the Appointment may be created
And the reason for visit is associated with the Appointment
And the reason is treated as Guardian-provided information
And no diagnosis is created

---

### Scenario: Appointment request without a reason is rejected

Given Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro is published

When Maria attempts to request an Appointment without a reason for visit

Then the request is rejected
And no Appointment is created

---

### Scenario: Appointment and Care Authorization are established together

Given Maria is an authenticated active Guardian of Luna
And Animalia Madrid Centro is published
And Maria provides a valid Appointment request
And Maria explicitly grants the required Care Authorization

When the Appointment request succeeds

Then the Appointment is created in `REQUESTED` state
And the required Care Authorization is established
And both concern Luna
And both concern Animalia Madrid Centro
And neither result is exposed as a partial successful request

---

### Scenario: Care Authorization failure prevents Appointment creation

Given Maria otherwise satisfies the Appointment-request requirements
And the workflow requires a new Appointment-derived Care Authorization

When that Care Authorization cannot be established

Then the Appointment request fails
And no `REQUESTED` Appointment from that operation is established
And no partial successful request is exposed

---

### Scenario: Appointment failure leaves no orphan Appointment-derived authorization

Given Maria explicitly grants the Care Authorization as part of an Appointment
request

When establishment of the Appointment fails

Then no successful Appointment is created
And no active Care Authorization whose sole basis is that failed Appointment
request remains established

---

### Scenario: Second pending request for the same Pet and Clinic is rejected

Given Maria and Carlos are current Guardians of Luna
And Maria has a `REQUESTED` Appointment for Luna at Animalia Madrid Centro
whose requested start is in the future

When Carlos requests another Appointment for Luna at Animalia Madrid Centro

Then the request is rejected
And no Appointment, Care Authorization, scheduling history, or Communication is
created
And Maria's pending request remains unchanged

---

### Scenario: Confirmed visit does not block a further request

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro next week
And Luna has no pending request at that Clinic

When Maria requests a follow-up Appointment for Luna at Animalia Madrid Centro

Then the request may succeed
And Luna may have several future Appointments at the Clinic

---

### Scenario: Passed unconfirmed request does not block

Given Luna's earlier request at Animalia Madrid Centro was never confirmed
And its requested start has passed
And its expiry has not yet been materialized

When Maria requests a new Appointment for Luna at Animalia Madrid Centro

Then the earlier request does not block the new request

---

### Scenario: Independent Care Authorization is unaffected by failed Appointment request

Given Luna already has another valid Care Authorization established through a
different approved care context

When a new Appointment request fails

Then the failed request does not delete or rewrite the unrelated existing Care
Authorization

---

## 6. Edge Cases

### Several Guardians request care for the same Pet

Multiple Guardians may independently interact with the same Pet.

At most one pending request may exist for the same Pet at the same Clinic,
whichever Guardian created it (BR-35). A second Guardian's request is rejected
while that pending request exists.

Requests for the same Pet at different Clinics, and confirmed Appointments, are
not treated as duplicates. This Specification does not otherwise infer that two
requests are duplicates solely because they concern the same Pet.

---

### Previous request has passed without confirmation

A `REQUESTED` Appointment whose latest requested start is no longer in the
future is logically expired (`SPEC-APT-015`). It does not count as a pending
request and does not block a new request for the same Pet and Clinic, even
before its `EXPIRED` outcome is materialized.

---

### Clinic has no assigned Veterinarian yet

A Clinic may receive an Appointment request without an assigned Veterinarian.

Professional assignment occurs separately.

---

### Clinic currently has no confirmed availability

The relationship between Appointment requests and real-time availability must be defined by the Appointment Availability Specifications.

`REQUESTED` must not be interpreted as guaranteed availability.

---

### Clinic information changes after request

Changes to the Clinic's public name, contact information, or current location must not cause the Appointment to become associated with another Clinic.

---

### Pet profile changes after request

Changes to the Pet's name or profile information must not create a new Pet identity or change which Pet the Appointment concerns.

---

### Guardian loses Guardianship after requesting

A User may cease to be a Guardian after requesting an Appointment.

The Appointment must not be deleted solely because the requesting User's Guardianship later changes.

The User's future ability to manage that Appointment requires dedicated Specifications.

---

## 7. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 8. Dependencies

* SPEC-ID-002 — Verify Email Address
* SPEC-ID-003 — Authenticate User
* SPEC-PET-004 — View My Pets
* SPEC-CLI-003 — Publish Clinic
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-APT-015 — Expire Unconfirmed Appointment Request (logical expiry used by
  the pending-request rule, BR-35)
* SPEC-ID-006 — Manage User Profile (BR-42, the requester contact information
  the Guardian is told about, BR-37)
* SPEC-APT-012 — View Clinic Appointment Schedule (BR-49/BR-50, where the Clinic
  sees it)

The active Guardianship behavior used by this Specification is established by:

* SPEC-PET-001 — Register Pet
* SPEC-PET-003 — Accept Guardianship Invitation

Medical authorization required by this workflow is established through:

- SPEC-ACC-001 — Grant Pet Care Authorization

The commercial Entitlement required by this workflow is evaluated through:

- SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 9. Out of Scope

This Specification does not define:

* Clinic confirmation of the Appointment;
* Appointment rejection;
* Appointment cancellation;
* Appointment rescheduling;
* Appointment completion;
* no-show behavior;
* Veterinarian selection;
* Veterinarian assignment;
* Clinic or Veterinarian availability;
* the exact standard Appointment duration value or how it is configured (governed by `SPEC-APT-013`);
* the Guardian-facing candidate Appointment start-time read (to be governed by `SPEC-APT-014`);
* double-booking prevention;
* Appointment reminders;
* medical-record access resulting from the Appointment;
* clinical documentation;
* payment for veterinary services;
* internal Clinic-created Appointments;
* recurring Appointments.

---

## 10. Verification Notes

Verification must demonstrate that:

1. an eligible active Guardian can request an Appointment;
2. authentication alone does not authorize requests for arbitrary Pets;
3. shared Guardians may request Appointments for the same Pet;
4. each Appointment concerns exactly one Pet;
5. each Appointment belongs to exactly one Clinic;
6. the public Guardian workflow requires a published Clinic;
7. a successful request creates the Appointment in `REQUESTED` state;
8. `REQUESTED` does not imply confirmation;
9. a Veterinarian is not required at request time;
10. the requesting User is preserved;
11. Appointment creation does not modify Guardianship;
12. Appointment creation does not create clinical information;
13. new Appointment requests cannot target past times;
14. later Clinic unpublication does not delete existing Appointments;
15. Appointment creation behaves atomically.
16. Appointment requests require a reason for visit;
17. the Guardian-provided reason is not treated as a diagnosis or Medical Record Entry.
18. successful Guardian-facing Appointment creation establishes the required
    Appointment-derived Care Authorization as part of the same coherent domain
    operation;
19. the Appointment and its required authorization refer to the same Pet and
    Clinic context;
20. Care Authorization creation failure prevents successful Appointment
    creation;
21. Appointment creation failure does not leave an orphan authorization whose
    sole basis was that failed request;
22. partial failure preserves the previous valid domain state;
23. Appointment-derived authorization remains distinguishable from Care
    Authorization established through another approved workflow;
24. unrelated existing Care Authorizations are not destroyed by failure of a
    new Appointment request.
25. a new Appointment request is denied when the target Organization does not
    currently hold `APPOINTMENT_MANAGEMENT`, without deleting or otherwise
    affecting existing Appointments.
26. the Guardian provides only a requested start date, time, and UTC offset —
    no end date, time, or offset is accepted as authoritative;
27. the Appointment end time is correctly derived from the Clinic's current
    standard Appointment duration as real elapsed time, including across a
    Clinic civil-time daylight-saving transition;
28. a request is rejected, deterministically and distinguishably from other
    rejection reasons, when the target Clinic has no currently configured
    standard Appointment duration;
29. a request is evaluated against current Availability and current standard
    duration regardless of whether, or how recently, a candidate Appointment
    start-time read was performed;
30. a caller without established Guardian authority over the Pet cannot
    infer, through this operation's outcome or behavior, whether the target
    Clinic's Veterinary Organization currently holds the required commercial
    Entitlement.
31. the Guardian request screen states, before submission, that the Clinic
    will be able to see the requester's name and email address to manage the
    Appointment, without adding any input or changing the request (BR-37).
31. a second request for the same Pet and Clinic is rejected while a pending
    request exists, whether made by the same Guardian or by another current
    Guardian of the Pet;
32. a rejected duplicate pending request creates no Appointment, Care
    Authorization, Schedule Revision, Lifecycle Event, or Communication, and
    leaves the existing pending Appointment unchanged;
33. concurrent requests for the same Pet and Clinic result in at most one
    pending request;
34. an existing `CONFIRMED` Appointment for the same Pet and Clinic does not
    block a new request;
35. a `REQUESTED` Appointment whose latest requested start is no longer in the
    future does not block a new request, even before its expiry is
    materialized;
36. `CANCELLED`, `COMPLETED`, `NO_SHOW`, and `EXPIRED` Appointments do not block
    a new request;
37. a pending request for the same Pet at another Clinic, or for another Pet at
    the same Clinic, does not block a new request.
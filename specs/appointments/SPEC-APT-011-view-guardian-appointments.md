# SPEC-APT-011 — View Guardian Appointments

**Status:** APPROVED  
**Requirements:** REQ-APT-007  
**Domain:** Appointments  
**Priority:** P1

> **Extended — Punto 9.** §13 adds two paged, Guardian-wide reads (Active and History across every Pet the acting User currently guards) for the Guardian's "My appointments" screen; §14 holds their Verification Notes. They add no visibility: every row is an Appointment `get_pet_appointments` already returns to the same User at the same instant. Nothing above changes. The row's `awaiting_clinic_confirmation` (BR-37) lets the list keep the distinct "awaiting clinic confirmation" tag of SPEC-APT-019 §5 "Appointment list", which stays in force.

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): references to Clinical Encounters read as Clinical Record Entries of the Appointment (SPEC-MED-010 §10); the Guardian read is otherwise unchanged. Recorded pending finding: `get_appointment_veterinarian_assignment_history`, used by the Guardian Appointment detail only to know whether a Veterinarian is assigned, returns Veterinarian Professional Profile and assigning User identifiers to Guardians; it must be replaced by a minimal Guardian-safe indicator (CLINICAL_DOCUMENTATION_TRANSITION.md §8). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Guardian to view relevant upcoming and historical
Appointments for Pets with which they currently have an active Guardianship
relationship.

Appointment visibility follows the Pet and the Guardian's current relationship
with that Pet.

It must not depend solely on:

- who originally created the Appointment;
- who originally registered the Pet;
- which Guardian requested the Appointment.

The view must preserve Appointment lifecycle, Clinic, scheduling, and relevant
professional information without exposing protected information beyond the
Guardian's authorized context.

---

## 2. Preconditions

- The acting User exists.
- The acting User is authenticated.
- The Pet exists.
- The acting User has an active Guardianship relationship with the Pet.
- Zero or more Appointments may exist for the Pet.

---

## 3. Business Rules

### BR-1 — Active Guardianship is the visibility basis

Normal Guardian Appointment access requires a current active Guardianship
relationship with the Pet.

The User does not need to have personally created the Appointment.

---

### BR-2 — Shared Guardians see the same Pet Appointment history

When several Users are active Guardians of the same Pet, they may view the
Appointments associated with that same Pet.

The system must not create separate Appointment histories per Guardian.

Conceptually:

    Maria ───┐
             │
             ▼
            Luna
             │
             ▼
       Appointments
             ▲
             │
    Carlos ──┘

---

### BR-3 — Original requester retains historical attribution

Where an Appointment was requested by a specific Guardian, that requesting User
must remain historically identifiable.

Visibility by another Guardian must not rewrite requester attribution.

---

### BR-4 — Pet creator status is irrelevant

The User who originally registered the Pet must not receive special Appointment
visibility solely because they created the Pet record.

Current Guardianship determines normal personal Appointment access.

---

### BR-5 — Former Guardian loses normal Appointment visibility

A User whose Guardianship relationship has ended must not retain normal
Guardian Appointment access solely because they:

- previously were a Guardian;
- registered the Pet;
- requested one or more Appointments;
- previously viewed the Appointment history.

Historical involvement does not imply current authorization.

---

### BR-6 — Upcoming Appointment information is visible

An active Guardian may view applicable non-terminal Appointments for the Pet.

This may include:

- `REQUESTED`;
- `CONFIRMED`.

The representation must preserve the actual Appointment lifecycle state.

---

### BR-7 — Historical Appointment information is visible

An active Guardian may view applicable terminal Appointment history.

This includes:

- `COMPLETED`;
- `CANCELLED`;
- `NO_SHOW`;
- `EXPIRED` (`SPEC-APT-015`).

Historical Appointments must not disappear from normal Pet Appointment history
merely because they are no longer active.

An `EXPIRED` Appointment is historical, not an upcoming obligation. Once the
authoritative `EXPIRED` outcome exists, a request whose time passed without
confirmation is no longer presented as active.

---

### BR-8 — Requested Appointment remains distinguishable from confirmed Appointment

The Guardian view must not present a `REQUESTED` Appointment as though the
Clinic had already confirmed it.

The current lifecycle state must remain meaningful.

---

### BR-9 — Terminal outcomes remain distinguishable

The Guardian must be able to distinguish:

    COMPLETED

from:

    CANCELLED

from:

    NO_SHOW

from:

    EXPIRED

These states represent materially different Appointment outcomes. In
particular, an `EXPIRED` request — one the Clinic did not confirm before its
requested time — must not be presented as cancelled.

---

### BR-10 — Appointment chronology remains meaningful

Guardian Appointment history must preserve clinically and operationally
relevant scheduling information.

Where applicable, this includes:

- original requested time;
- current requested time;
- confirmed time;
- accepted rescheduling history;
- terminal outcome time.

The exact visual layout is a UI concern.

---

### BR-11 — Appointment rescheduling must not create false duplicate history

When an existing Appointment was validly rescheduled, the Guardian view must
continue to represent the same Appointment identity.

The system must not display each accepted time change as though it were an
unrelated Appointment.

---

### BR-12 — Clinic remains visible

The Guardian Appointment view must identify the Clinic associated with the
Appointment.

Changing Clinic public profile information must not change which Clinic the
historical Appointment belonged to.

---

### BR-13 — Veterinary Organization may remain contextual

The Appointment's Veterinary Organization context may be presented where
useful.

The Clinic remains the primary physical care location associated with the
Appointment.

---

### BR-14 — Current assigned Veterinarian may be visible where applicable

Where an Appointment currently has an assigned Veterinarian, the Guardian view
may present that professional information.

The view must not infer a Veterinarian where no current Assignment exists.

---

### BR-15 — Veterinarian Assignment history must not be rewritten

If an Appointment was reassigned, the current Guardian-facing representation
may emphasize the current or final relevant Veterinarian.

Historical Appointment data must nevertheless preserve previous Assignment
history according to the applicable Specifications.

---

### BR-16 — Appointment Veterinarian is not automatically clinical author

Guardian Appointment presentation must not imply that the assigned
Veterinarian necessarily authored all later clinical information.

Appointment Assignment and clinical provenance remain separate concepts.

---

### BR-17 — Appointment view does not expose Draft clinical information

Viewing Appointments must not expose Draft Clinical Record Entries or Draft
Clinical Attachments.

Appointment visibility and Medical Records visibility are separate concerns.

---

### BR-18 — Appointment view does not expand medical access

An active Guardian's ability to view Appointment information must not grant
additional medical-access rights beyond the applicable Medical Records rules.

---

### BR-19 — Appointment view may link to finalized medical history where separately authorized

A completed Appointment may be associated with a Clinical Encounter and
finalized medical information.

The product may allow navigation from the Appointment to that medical history
when the Guardian independently has the required medical-history permission.

The Appointment itself is not the authorization basis.

---

### BR-20 — Care Authorization details are not automatically exposed

The existence of a Care Authorization associated with an Appointment does not
require the normal Guardian Appointment view to expose internal authorization
metadata.

Authorization status may be surfaced where product behavior requires it, but
the Appointment view must not become an unrestricted access-control inspection
tool.

---

### BR-21 — Appointment history follows the Pet

If the Pet later receives care at different Clinics, all applicable
Appointments remain associated with the same Pet domain identity.

For example:

    Luna
    ├── Animalia Madrid Centro
    │   └── COMPLETED
    ├── VetCare Toledo
    │   └── CANCELLED
    └── Animalia Getafe
        └── CONFIRMED

The Appointment history does not fragment per provider.

---

### BR-22 — Clinic unpublication does not remove historical Appointment visibility

If a Clinic is later unpublished, existing historical Appointments remain
identifiable to authorized Guardians.

Public Discovery and personal Appointment history are separate concerns.

---

### BR-23 — Subscription termination does not remove historical Appointments

Changes in the Clinic Organization's commercial Subscription must not erase
existing Appointment history.

---

### BR-24 — Guardianship changes do not rewrite Appointment history

Ending one Guardian's current access must not rewrite:

- who originally requested an Appointment;
- which Pet it concerned;
- which Clinic it belonged to;
- its lifecycle history.

---

### BR-25 — Viewing Appointments is read-only

This Specification grants Appointment visibility.

It does not independently authorize:

- cancellation;
- rescheduling;
- Veterinarian selection;
- Care Authorization changes;
- medical-record modification.

Those operations follow their own Specifications.

---

### BR-26 — Empty Appointment history is valid

A Pet may have no Appointments.

An authorized Guardian viewing that Pet's Appointments must receive a valid
empty result rather than an authorization or domain error.

---

### BR-27 — Guardian view is limited to Pets they currently guard

An active Guardianship relationship with Luna must not grant Appointment
visibility for Toby or another Pet.

---

### BR-28 — Multiple Pets remain separately identifiable

A Guardian responsible for several Pets may view Appointments for each Pet.

The system must preserve which Appointment belongs to which Pet.

---

### BR-29 — Appointment view must not imply complete medical history

Appointment history represents scheduling and attendance history.

It must not be presented as equivalent to the Pet's complete longitudinal
medical history.

A Pet may have Clinical Encounters without Appointments.

---

### BR-30 — Appointment retrieval must preserve consistent lifecycle state

The Guardian-facing representation must not expose contradictory current
Appointment state.

For example, the same Appointment must not be represented simultaneously as:

    CONFIRMED

and:

    CANCELLED

within one coherent current view.

---

### BR-31 — A cancelled Appointment shows its cancellation reason

For a `CANCELLED` Appointment, the Guardian view includes the cancellation
reason recorded by the cancellation (`SPEC-APT-003` BR-8, BR-9), whether the
Appointment was cancelled by a Guardian or by the Clinic, and whether it was
`REQUESTED` or `CONFIRMED` when cancelled.

The cancellation reason:

- is taken only from the Appointment's cancellation itself, exactly as it was
  recorded; it is never derived from the reason for visit, Guardian notes,
  Communications, or any other information;
- is absent when the cancellation recorded no reason, which is possible only
  for a Guardian cancellation (`SPEC-APT-003` BR-9);
- is absent for every Appointment that is not `CANCELLED`, including
  `REQUESTED`, `CONFIRMED`, `COMPLETED`, `NO_SHOW`, and `EXPIRED`;
- remains distinct from the reason for visit: neither replaces the other;
- is scheduling information, not clinical information (`SPEC-APT-003` BR-9).

Exposing the cancellation reason does not expose who cancelled, any other
lifecycle history, or any other Clinic-internal information.

---

### BR-32 — An actionable pending Reschedule Proposal is part of the Guardian view

For a `CONFIRMED` or `REQUESTED` Appointment with an actionable pending
Reschedule Proposal (`SPEC-APT-005` BR-31, `SPEC-APT-018` BR-17), the Guardian
view includes, through the same generic proposal projection for both
workflows:

- the proposal identity, used to accept it (`SPEC-APT-006` for a `CONFIRMED`
  Appointment, `SPEC-APT-019` for a `REQUESTED` Appointment);
- its state, `PENDING`;
- its proposing context, `GUARDIAN` or `CLINIC`; always `CLINIC` for a
  `REQUESTED` Appointment;
- the proposed start instant, end instant, and scheduling timezone, exactly as
  stored by the proposal;
- its reason, when one was recorded. A Clinic proposal always has a reason,
  and that reason is visible to current Guardians (`SPEC-APT-005` BR-30,
  `SPEC-APT-018` BR-6);
- its Guardian current acceptability (`SPEC-APT-005` BR-35), as the generic
  boolean `pending_reschedule_currently_acceptable`: for a Clinic proposal on a
  `REQUESTED` base, current scheduling feasibility (`SPEC-APT-005` BR-34); for
  a Clinic proposal on a `CONFIRMED` base, current scheduling feasibility and
  the Organization's current `APPOINTMENT_MANAGEMENT` Entitlement; for a
  Guardian proposal, `false`.

The acceptability value is present (`true` or `false`) exactly when the
proposal fields are present and absent (`null`) when no proposal is projected.
It is derived at read time, carries no reason, and reveals no Veterinarian
conflict, availability detail, or subscription state. It is never stored and
never changes the proposal. An actionable proposal is projected whether or not
it is currently acceptable; acceptability decides only whether the Guardian
client offers acceptance (`SPEC-APT-006` BR-36, `SPEC-APT-019` §5).

A pending proposal's base context always equals the Appointment's current
lifecycle state (`docs/RELATIONAL_MODEL.md` §4), so the lifecycle state
discriminates the workflow without an additional field:

- `CONFIRMED` with a pending proposal → a confirmed reschedule
  (`confirmedReschedule`);
- `REQUESTED` with a pending proposal → a Clinic alternative time for the
  request (`requestedAlternativeTime`).

At most one such proposal is shown per Appointment. A proposal that is
accepted, withdrawn (`SPEC-APT-016`), `VOID`, or otherwise not actionable is
not shown as pending.

The proposal never replaces the relevant scheduled interval (§4): the current
confirmed time remains the Appointment's commitment, and the current requested
time remains the Guardian's request, until the proposal is accepted. A pending
proposal must never be presented as though it had already changed the current
schedule.

The proposal reason is scheduling information. It is distinct from the reason
for visit, Guardian notes, and the cancellation reason (BR-31).

The view does not expose the proposing User's identity, the proposal's base
revision, or the history of proposals that were never accepted.

---

### BR-33 — The view exposes the provenance of the relevant scheduled interval

For every Appointment, the Guardian view includes the provenance of the
Schedule Revision that supplies the relevant scheduled interval (§4):

- `current_schedule_source_proposal_id`: the accepted Reschedule Proposal that
  established that revision, or none when the revision was not established by
  accepting a proposal;
- `current_schedule_source_proposing_context`: that proposal's proposing
  context (`GUARDIAN` or `CLINIC`), or none.

Both values derive from the revision's normalized source-proposal provenance;
no separate flag is persisted.

A `REQUESTED` Appointment whose relevant scheduled interval has a source
proposal from the `CLINIC` context is in the state "Guardian accepted the
Clinic's proposed time — awaiting Clinic confirmation" (`SPEC-APT-019` BR-14).
The Guardian client presents it as **Requested time updated — awaiting
confirmation from the Clinic** (`SPEC-APT-019` §5), never as confirmed.

The state ends when the Appointment leaves `REQUESTED` or when a later
unsourced requested context (a Guardian reschedule, `SPEC-APT-004`) becomes the
relevant scheduled interval.

The provenance exposes no proposing User, base revision, or history of
proposals that were never accepted.

---

### BR-34 — A confirmed Appointment whose start has passed awaits the Clinic's resolution

A `CONFIRMED` Appointment whose latest confirmed scheduled start (the start of
its relevant scheduled interval, §4) has been reached, and which the Clinic has
not yet resolved, remains `CONFIRMED`. It stays an active Appointment (§6) and
must not be presented as completed, cancelled, no-show, or expired.

For such an Appointment the Guardian client:

- does not offer Guardian cancellation, because the backend rejects it
  (`SPEC-APT-003` BR-31);
- shows a calm status note with this meaning:
  - ES: "La hora de la cita ya ha pasado. La clínica actualizará su estado."
  - EN: "The scheduled appointment time has passed. The clinic will update its
    status."

The note must not imply that a Veterinarian is assigned, that a clinical
record will be created, that the visit took place, or that the Pet did not
attend.

The state is derived from the existing lifecycle state and relevant scheduled
interval compared with the current time; no additional read field is required.
The client's time comparison is advisory and decides only presentation: the
cancellation operation enforces the cutoff with authoritative backend time,
and a later read showing the Clinic's resolution replaces the note with that
outcome.

---

### BR-35 — The view exposes the Appointment's medical-access state

Each Appointment exposes `medical_access_state`: the state of its own
Appointment-derived Care Authorization, as an operational state only
(`SPEC-ACC-002` BR-63, within BR-20):

- `ACTIVE` — the Appointment's Care Authorization is `ACTIVE`, so a current
  Guardian may withdraw it (`SPEC-ACC-002` BR-56);
- `REVOKED` — a Guardian withdrew it;
- `INACTIVE` — it ended normally (cancellation, no-show, expiry) or none
  exists.

The value is derived from the authorization's current state and never stored
on the Appointment. It exposes no Care Authorization identifier, grant or
revocation time, granting or revoking User, revocation reason, ending
context, Encounter state, professional identity, or medical information, and
it never concerns another Appointment, another Pet, or a `CLINICAL_INTAKE`
authorization. It is the same for every current Guardian of the Pet. The
Clinic Appointment Schedule does not expose it.

---

## 4. Guardian Appointment Representation

The Guardian Appointment view should support enough information to understand
the relevant scheduling context.

### Core information

- Appointment identity;
- Pet;
- Clinic;
- current lifecycle state;
- relevant requested or confirmed time, as the relevant scheduled interval
  defined below.

### Where applicable

- assigned Veterinarian;
- original requesting User;
- terminal outcome;
- cancellation reason, for a `CANCELLED` Appointment (BR-31);
- medical-access state (BR-35);
- relevant rescheduling information, including an actionable pending
  Reschedule Proposal for either workflow (BR-32) and the provenance of the
  relevant scheduled interval (BR-33);
- associated Clinical Encounter reference where useful and separately
  authorized.

### Relevant scheduled interval

The relevant scheduled interval of an Appointment is its latest effective
scheduling context: the latest requested context if the Appointment was never
confirmed, otherwise the latest confirmed context, including accepted
reschedules. Cancellation, completion, and no-show do not change it. Earlier
requested and confirmed contexts remain part of scheduling history and are not
replaced by it.

The exact UI presentation is outside this Specification.

---

## 5. Scenarios

### Scenario: Guardian views upcoming requested Appointment

Given Maria has an active Guardianship relationship with Luna
And Luna has a `REQUESTED` Appointment at Animalia Madrid Centro

When Maria views Luna's Appointments

Then the requested Appointment is visible
And its lifecycle state is shown as `REQUESTED`
And it is not represented as already confirmed

---

### Scenario: Guardian views confirmed Appointment

Given Maria is an active Guardian of Luna
And Luna has a `CONFIRMED` Appointment at VetCare Toledo

When Maria views Luna's upcoming Appointments

Then the confirmed Appointment is visible
And VetCare Toledo remains identifiable as the Clinic
And the confirmed scheduling information is available

---

### Scenario: Guardian who did not request Appointment may see it

Given Maria and Carlos are both active Guardians of Luna
And Carlos requested Luna's Appointment

When Maria views Luna's Appointments

Then the Appointment is visible to Maria
And Carlos remains historically identifiable as the requesting User
And Maria is not represented as the requester

---

### Scenario: Two Guardians see same Appointment

Given Maria and Carlos are both active Guardians of Luna
And Luna has one confirmed Appointment

When Maria views Luna's Appointments
And Carlos views Luna's Appointments

Then both Users may see the same Appointment domain entity
And separate copies of the Appointment are not created per Guardian

---

### Scenario: Former Guardian cannot view Appointments

Given Carlos previously had an active Guardianship relationship with Luna
And Carlos's Guardianship has ended
And Carlos has no other applicable Appointment-access basis

When Carlos attempts to view Luna's Appointments

Then access is denied
And historical Guardianship alone is insufficient

---

### Scenario: Completed Appointment remains visible

Given Luna previously had a `COMPLETED` Appointment at Animalia Madrid Centro
And Maria is an active Guardian of Luna

When Maria views Luna's historical Appointments

Then the completed Appointment remains visible
And it is distinguishable from active Appointments

---

### Scenario: Cancelled Appointment remains visible

Given Luna previously had a `CANCELLED` Appointment

When Maria views Luna's historical Appointments

Then the Appointment remains visible
And its outcome is shown as cancelled rather than completed

---

### Scenario: Guardian sees the Clinic's cancellation reason

Given Animalia Madrid Centro cancelled Luna's `CONFIRMED` Appointment
And the Clinic recorded the reason "Veterinarian unavailable that day"
And the Appointment's reason for visit is "Annual check-up"

When Maria, an active Guardian of Luna, views the Appointment

Then the Appointment is shown as `CANCELLED`
And its cancellation reason is "Veterinarian unavailable that day"
And its reason for visit is still "Annual check-up"

---

### Scenario: Cancellation reason belongs only to cancelled Appointments

Given Luna has `REQUESTED`, `CONFIRMED`, `COMPLETED`, `NO_SHOW`, and `EXPIRED`
Appointments

When Maria views them

Then none of them shows a cancellation reason

If a Guardian cancelled an Appointment without giving a reason, it is shown as
`CANCELLED` without a cancellation reason.

---

### Scenario: No-show Appointment remains visible

Given Luna previously had a `NO_SHOW` Appointment

When Maria views Luna's historical Appointments

Then the Appointment remains visible
And `NO_SHOW` remains distinguishable from `CANCELLED` and `COMPLETED`

---

### Scenario: Confirmed Appointment whose time has passed awaits the Clinic

Given Luna's Appointment is `CONFIRMED` for 10:00
And it is now 10:30
And the Clinic has not yet recorded completion, no-show, or cancellation

When Maria views Luna's Appointment

Then it is shown as `CONFIRMED` at 10:00
And Cancel is not offered
And Maria sees that the scheduled time has passed and the clinic will update
its status
And nothing suggests that a veterinarian, clinical record, attendance, or
non-attendance has been recorded

When the Clinic later completes it and Maria views it again

Then it is shown as `COMPLETED` and the note no longer appears

---

### Scenario: Rescheduled Appointment remains one Appointment

Given Luna's confirmed Appointment was rescheduled from 10:00 to 17:00
And the reschedule was validly accepted

When Maria views Luna's Appointment

Then the Appointment remains one domain entity
And the current confirmed time may be shown as 17:00
And the historical scheduling change remains traceable
And a false second Appointment is not created

---

### Scenario: Current assigned Veterinarian may be displayed

Given Luna has a `CONFIRMED` Appointment
And Dr. Garcia is the current assigned Veterinarian

When Maria views the Appointment

Then Dr. Garcia may be shown as the current assigned Veterinarian
And Appointment Assignment does not imply clinical authorship

---

### Scenario: Reassigned Veterinarian reflects current Appointment responsibility

Given Dr. Garcia was originally assigned to Luna's Appointment
And Dr. Lopez validly replaced Dr. Garcia

When Maria views the current upcoming Appointment

Then Dr. Lopez may be shown as the current assigned Veterinarian
And historical Appointment Assignment remains preserved independently

---

### Scenario: Draft clinical information is not exposed

Given Luna has a completed Appointment
And its Clinical Encounter contains a Draft Clinical Record Entry

When Maria views the Appointment

Then the Draft clinical content is not exposed through the Appointment view

---

### Scenario: Clinic unpublication does not remove Appointment

Given Luna previously had an Appointment at Animalia Madrid Centro
And Animalia Madrid Centro is later unpublished

When Maria views Luna's Appointment history

Then the historical Appointment remains visible
And it remains associated with Animalia Madrid Centro

---

### Scenario: Subscription expiration does not remove Appointment history

Given Luna has historical Appointments at Animalia Madrid Centro
And Animalia Veterinary Group's Subscription later expires

When Maria views Luna's Appointment history

Then the historical Appointments remain available
And their lifecycle history remains unchanged

---

### Scenario: Guardian with multiple Pets sees separate Appointment contexts

Given Maria is an active Guardian of Luna
And Maria is also an active Guardian of Toby
And both Pets have Appointments

When Maria views her Pets' Appointment information

Then Luna's Appointments remain associated with Luna
And Toby's Appointments remain associated with Toby
And the system does not merge the two Pet histories

---

### Scenario: Pet with no Appointments returns empty history

Given Maria is an active Guardian of Luna
And Luna has no Appointments

When Maria views Luna's Appointments

Then the operation succeeds
And the Appointment collection is empty

---

## 6. Upcoming vs Historical Appointments

The product should be capable of distinguishing current scheduling obligations
from concluded Appointment history.

Conceptually:

    Upcoming / active
    ├── REQUESTED
    └── CONFIRMED

    Historical
    ├── COMPLETED
    ├── CANCELLED
    ├── NO_SHOW
    └── EXPIRED

The exact screen organization is a UI concern.

The domain requirement is preservation of lifecycle meaning.

The active group holds every non-terminal Appointment, including a `CONFIRMED`
Appointment whose scheduled start has been reached but which the Clinic has not
yet resolved (BR-34). That Appointment is neither moved to history nor hidden,
and the group's presentation must not imply that every Appointment in it is
still in the future (for example, it is labelled "Active" rather than
"Upcoming").

`EXPIRED` does not change the relevant scheduled interval defined in §4: an
expired Appointment shows its latest requested scheduling context.

---

## 7. Relationship to Medical History

Appointment history and medical history are related but different.

Appointment history answers:

    What veterinary care was requested, scheduled, cancelled, missed, or
    completed?

Medical history answers:

    What clinical care and information actually occurred?

Therefore:

    COMPLETED Appointment
        may link to
    Clinical Encounter

but:

    Appointment history
        ≠
    complete medical history

A Clinical Encounter may exist without an Appointment.

---

## 8. Edge Cases

### Appointment requested by former Guardian

A User may have requested an Appointment while they were a valid Guardian and
later lose Guardianship.

The Appointment preserves that User as historical requester.

Current visibility follows current Guardianship rather than historical
requester status.

---

### Clinic changes display name

The Appointment remains associated with the same Clinic identity.

Current display information may differ from what was visible when the
Appointment occurred.

Historical Clinic identity must remain stable.

---

### Large Appointment history

A Pet may accumulate many historical Appointments.

Pagination, filtering, or date-based grouping may be introduced for usability
and performance.

Those mechanisms must not alter lifecycle or historical meaning.

---

### Same Pet has several upcoming Appointments

Multiple valid Appointments may exist for a Pet where allowed by the applicable
scheduling rules.

Each remains independently identifiable.

---

### Appointment has no assigned Veterinarian

The Guardian view must not invent or require professional Assignment.

A valid Appointment may exist without a specific Veterinarian where the
Appointment lifecycle permits it.

---

## 9. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 10. Dependencies

- SPEC-PET-001 — Register Pet
- SPEC-PET-003 — Accept Guardianship Invitation
- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-003 — Cancel Appointment
- SPEC-APT-004 — Reschedule Requested Appointment
- SPEC-APT-005 — Propose Confirmed Appointment Reschedule
- SPEC-APT-006 — Accept Appointment Reschedule Proposal
- SPEC-APT-007 — Assign Veterinarian to Appointment
- SPEC-APT-008 — Reassign Veterinarian
- SPEC-APT-009 — Complete Appointment
- SPEC-APT-010 — Mark Appointment No-Show
- SPEC-APT-015 — Expire Unconfirmed Appointment Request
- SPEC-APT-016 — Withdraw Clinic Reschedule Proposal
- SPEC-APT-018 — Propose Alternative Time for Requested Appointment
- SPEC-APT-019 — Accept Requested Appointment Alternative Time
- SPEC-ID-003 — Authenticate User

Where clinical navigation is supported, the applicable Medical Records and
Access Control Specifications also apply.

---

## 11. Out of Scope

This Specification does not define:

- Clinic Appointment schedule views;
- Appointment search or filtering;
- pagination, except the paged Guardian reads of §13;
- calendar UI;
- Appointment notifications;
- reminder behavior;
- medical-history viewing;
- Draft clinical-information access;
- Appointment modification behavior;
- historical Appointment correction;
- export or sharing of Appointment history.

---

## 12. Verification Notes

Verification must demonstrate that:

1. current active Guardianship grants normal Guardian Appointment visibility;
2. the User does not need to have created the Appointment;
3. shared Guardians may access the same Pet Appointment history;
4. original requester attribution remains preserved;
5. former Guardians do not retain normal visibility solely through historical
   involvement;
6. `REQUESTED` and `CONFIRMED` Appointments remain distinguishable;
7. `COMPLETED`, `CANCELLED`, and `NO_SHOW` remain visible and distinguishable as
   historical outcomes;
8. rescheduling preserves one Appointment identity;
9. Clinic identity and relevant scheduling history remain available;
10. current Veterinarian Assignment may be visible without implying clinical
    authorship;
11. Draft clinical information is not exposed through Appointment visibility;
12. Appointment visibility does not expand medical access;
13. historical Appointments survive Clinic unpublication and Subscription
    termination;
14. Appointment history follows the Pet rather than a particular Guardian or
    provider;
15. multiple Pets remain independently identifiable;
16. viewing is read-only and does not grant Appointment-management operations;
17. a Pet with no Appointments returns a valid empty result;
18. Appointment history remains distinct from longitudinal medical history;
19. every Appointment exposes the relevant scheduled interval defined in §4 in
    every lifecycle state, and it is the same interval exposed for that
    Appointment through the Clinic Appointment Schedule;
20. `EXPIRED` Appointments remain visible as historical outcomes, are never
    treated as upcoming or active obligations, and remain distinguishable from
    `CANCELLED`, `COMPLETED`, and `NO_SHOW`, whose meanings are unchanged;
21. a `CANCELLED` Appointment exposes exactly the cancellation reason recorded
    by its cancellation, for Guardian and Clinic cancellations and for
    `REQUESTED` and `CONFIRMED` Appointments, including after an accepted
    confirmed reschedule, and none when the cancellation recorded no reason;
22. every Appointment that is not `CANCELLED` exposes no cancellation reason;
23. the cancellation reason and the reason for visit remain distinct, and
    exposing the cancellation reason exposes no actor identity, other lifecycle
    history, Guardian notes, or medical information;
24. a `REQUESTED` Appointment with an actionable Clinic Alternative Time
    proposal exposes the proposal identity, `PENDING`, `CLINIC`, the frozen
    interval and timezone, and the reason, while its relevant scheduled
    interval remains the current requested time;
25. a proposal that is accepted, withdrawn, `VOID`, or lapsed is not exposed
    as pending, for either base context;
26. after a Guardian accepted a Clinic alternative, the Appointment is
    `REQUESTED`, exposes the accepted interval as its relevant scheduled
    interval, exposes `current_schedule_source_proposal_id` and
    `current_schedule_source_proposing_context = CLINIC`, and exposes no
    pending proposal;
27. an ordinary Guardian-requested or initial requested context exposes no
    source proposal, and a later Guardian reschedule clears the
    accepted-awaiting-confirmation provenance;
28. after a confirmed reschedule is accepted, the source provenance identifies
    that proposal, and the Appointment is not presented as awaiting
    confirmation because it is `CONFIRMED`;
29. the Guardian view and the Clinic Appointment Schedule expose the same
    pending proposal and the same provenance for the same Appointment;
30. `pending_reschedule_currently_acceptable` is `null` exactly when no
    proposal is projected and `true` or `false` otherwise (BR-32);
31. for a `REQUESTED`-base Clinic proposal it follows current scheduling
    feasibility; for a `CONFIRMED`-base Clinic proposal it is `false` when the
    proposal is infeasible or the Organization lacks `APPOINTMENT_MANAGEMENT`
    and `true` again when both recover while the proposal is actionable; for a
    Guardian proposal it is `false` (BR-32);
32. an actionable proposal that is not currently acceptable is still projected,
    and the value never reveals its cause (BR-32);
33. a `CONFIRMED` Appointment whose latest confirmed start has been reached and
    that the Clinic has not resolved is presented as `CONFIRMED`, without
    Guardian cancellation, and with the "scheduled time has passed; the clinic
    will update its status" note, which implies no Veterinarian, clinical
    record, attendance, or non-attendance (BR-34);
34. a future `CONFIRMED` Appointment still offers Guardian cancellation and
    shows no such note, and a resolved Appointment shows its outcome instead of
    the note (BR-34);
35. hiding Guardian cancellation is presentation only: the cancellation
    operation enforces the cutoff with backend time (`SPEC-APT-003` BR-31).
36. `medical_access_state` is `ACTIVE` while the Appointment's Care
    Authorization is `ACTIVE` in any lifecycle, `REVOKED` after a Guardian
    revocation, and `INACTIVE` after cancellation, no-show, or expiry ended it
    (BR-35);
37. the read exposes no Care Authorization identifier or other authorization
    metadata, and the Clinic Appointment Schedule does not expose the state
    (BR-35).

---

## 13. Paged Guardian Appointment reads — Phase 1

Defined by **Guardian "My appointments" with tabs and pagination — Phase 1**
(Punto 9). The Guardian's "My appointments" screen presents the Appointments of
every Pet the User currently guards in two tabs — Active and History (§6) —
each read one page at a time, instead of selecting one Pet and reading that
Pet's whole Appointment history (§8, "Large Appointment history").

These reads add no authority, no capability, and no write. Every row is an
Appointment that `get_pet_appointments` returns to the same User at the same
instant, with the same value for every column both reads share; the new reads
only gather the User's currently guarded Pets into one ordered list and project
fewer columns. `get_pet_appointments` is unchanged: the Guardian Appointment
detail, its operations and installed clients keep using it.

### BR-36 — Common rules

Both reads are `STABLE`, `SECURITY DEFINER`, have an empty `search_path`, and
are executable only by `authenticated`. Evaluation order:

1. authentication and a coherent domain User — otherwise `28000`;
2. input validation — a `p_limit` outside 1–50, or a cursor that is neither
   complete nor entirely null (or names an Active rank other than 1 or 2),
   fails with `22023` `Guardian appointment page is invalid`.

They take no Pet parameter and have no denial outcome. The visible set is the
Appointments of the Pets with which the acting User has a current Guardianship
(BR-1, BR-27), under exactly the Guardianship condition of
`get_pet_appointments`, and it is restricted inside the read **before** the
order, the cursor and the limit are applied. Consequently:

- a co-Guardian sees exactly what the primary Guardian sees for a shared Pet,
  including Appointments the other Guardian requested (BR-1, BR-2, BR-3);
- a former Guardian, the User who registered the Pet, or a past requester
  sees none of that Pet's Appointments without a current Guardianship (BR-4,
  BR-5);
- Appointments of Pets in unrelated Guardianships never appear (BR-27), and
  each row keeps its own Pet (BR-28);
- a User with no current Guardianship, or whose Pets have no Appointment in
  the tab, receives an empty page, never an error (BR-26).

Each call is one statement, observes one snapshot, uses one evaluation instant,
writes nothing, takes no lock, and returns no total count. The first page is
the one with no cursor; every later page holds the next `p_limit` rows strictly
after its cursor in the read's order. The page is chosen on the key alone and
only its Appointments are projected.

### BR-37 — Guardian Appointment row

Both reads return the same row:

    id uuid,
    pet_id uuid,
    pet_name text,
    clinic_id uuid,
    lifecycle_state text,
    current_scheduled_start_at timestamptz,
    current_scheduled_end_at timestamptz,
    current_scheduling_timezone_name text,
    pending_reschedule_proposing_context text,
    awaiting_clinic_confirmation boolean

- `id`, `clinic_id`, `lifecycle_state`, and the three `current_scheduled_*`
  columns have exactly the value of the same columns of `get_pet_appointments`:
  the actual lifecycle state (BR-6 to BR-9) and the relevant scheduled
  interval (§4) with the timezone in which it was established — never
  converted to another timezone;
- `pet_id` and `pet_name` are the Appointment's Pet and its current name
  (BR-28);
- `pending_reschedule_proposing_context` has exactly the value of the same
  column of `get_pet_appointments`: `CLINIC` or `GUARDIAN` while an actionable
  `PENDING` Reschedule Proposal is projected for the Appointment (BR-32), and
  `NULL` otherwise. It tells the list that a proposal exists, not its content;
- `awaiting_clinic_confirmation` is `true` exactly when the Appointment is
  `REQUESTED` and the Schedule Revision supplying its relevant scheduled
  interval was established by accepting a Clinic proposal — the state "Guardian
  accepted the Clinic's proposed time — awaiting Clinic confirmation" of BR-33
  and SPEC-APT-019 BR-14 — and `false` otherwise (never `NULL`). It equals
  `lifecycle_state = 'REQUESTED'` together with
  `current_schedule_source_proposing_context = 'CLINIC'` of
  `get_pet_appointments` for the same Appointment. It is derived by the backend
  from the revision's source-proposal provenance, never stored, and never
  inferred from the lifecycle state alone or from a pending proposal: a pending
  Clinic alternative that still needs the Guardian's answer is not awaiting
  confirmation, and an accepted alternative followed by a new pending Clinic
  alternative is both. It ends when the Appointment leaves `REQUESTED`
  (confirmation, cancellation, expiry) or when a later unsourced requested
  context (a Guardian reschedule, SPEC-APT-004) becomes the relevant scheduled
  interval.

The row deliberately excludes the reason for visit, Guardian notes, requester,
cancellation reason, Veterinarian Assignment, proposal identity, interval,
reason and acceptability, schedule provenance identifiers (only the derived
`awaiting_clinic_confirmation` is returned), and medical-access state. They
remain available only through the Appointment detail (`get_pet_appointments`).
No Clinic display name is returned.

### BR-38 — Active page

    get_guardian_active_appointments(
        p_after_rank integer default null,
        p_after_start_at timestamptz default null,
        p_after_id uuid default null,
        p_limit integer default 20
    ) returns table (… the columns of BR-37 …, active_rank integer)

The visible Appointments whose stored lifecycle state is `REQUESTED` or
`CONFIRMED` (§6), including a `CONFIRMED` Appointment whose start has been
reached (BR-34). The read never derives a lifecycle state: it shows the stored
one, and a request only leaves the tab once `EXPIRED` is recorded (BR-7).

`active_rank` is `1` when the relevant scheduled start is after the read's
instant and `2` when it has been reached. Order: rank 1 first, by start
ascending then `id` ascending (the next Appointment first); then rank 2, by
start descending then `id` descending (the most recently passed first). The
cursor is the complete `(active_rank, current_scheduled_start_at, id)` of the
last row of the previous page.

Between pages an Appointment can only move from rank 1 to rank 2, that is from
the front of rank 1 to the front of rank 2. Paging therefore never skips an
Appointment whose state and interval do not change: one that crosses before it
was returned is returned in rank 2; one that crosses after it was returned may
be returned again, and the client keeps one copy (BR-40). A change of state or
interval between pages (cancellation, confirmation, accepted reschedule) may
move an Appointment behind the cursor or out of the tab; it appears in its new
place on the next first read.

### BR-39 — History page

    get_guardian_appointment_history(
        p_before_start_at timestamptz default null,
        p_before_id uuid default null,
        p_limit integer default 20
    ) returns table (… the columns of BR-37 …)

The visible Appointments whose lifecycle state is `COMPLETED`, `CANCELLED`,
`NO_SHOW` or `EXPIRED` (§6), newest relevant scheduled start first, then `id`
descending. The cursor is the complete `(current_scheduled_start_at, id)` of the
last row of the previous page. `pending_reschedule_proposing_context` is always
`NULL` and `awaiting_clinic_confirmation` always `false` here (a terminal
Appointment has no actionable proposal and is no longer `REQUESTED`).

A terminal Appointment's relevant interval never changes, so its key is stable:
pages never repeat or skip one, ties on the start are resolved by `id`, and an
Appointment that becomes terminal while paging appears where its key sorts.

### BR-40 — Client use

The Guardian "My appointments" screen:

- shows two tabs, Active (initial) and History, each ONE compact list of rows
  stating only the Pet name, the Clinic, the date and time of the relevant
  scheduled start in its own timezone, the localized lifecycle state, and up
  to two short secondary tags, never merged and never presented as a lifecycle
  state:
  - for an actionable Clinic proposal (`CLINIC`), the existing proposal tag —
    SPEC-APT-019 §5's "La clínica propone otro horario" / "Clinic proposed
    another time" on a `REQUESTED` Appointment, "Propuesta de cambio de
    horario" / "Proposed time change" on a `CONFIRMED` one: the Guardian's
    answer is due;
  - when `awaiting_clinic_confirmation` is `true`, SPEC-APT-019 §5's distinct
    tag "Pendiente de confirmación de la clínica" / "Awaiting clinic
    confirmation": the Guardian already answered and the Clinic has to confirm.
    It looks different from the proposal tag (its own icon and a neutral tone,
    since nothing is asked of the Guardian);
  - when both apply (a new Clinic alternative after an accepted one), both tags
    are shown, the proposal tag first, as the detail shows both.
  The whole row opens the existing Guardian Appointment detail; no operation
  (cancel, accept, reschedule) and no extra card or button is offered in the
  list;
- reads Active's first page on entry and History's first page only when that
  tab is first shown, 20 rows per page, and offers "Load more" while the last
  page was full, sending back the complete cursor of the last row exactly as
  returned; one read at a time per tab; an answer to an older request is
  ignored; a row already shown is never shown twice;
- on focus (for example back from the detail, where writes happen) restarts
  only the tab on screen from its first page; the other tab restarts when it
  is next shown. Lists, cursors, loading and errors are independent per tab;
- resolves Clinic names for the page's Clinics through the published Clinic
  profiles, as the Pet-scoped list did; an unpublished Clinic shows the
  generic "Clinic unavailable" label. No new Clinic exposure is introduced;
- treats a row as navigation only: the detail re-reads through
  `get_pet_appointments`, which re-verifies the current Guardianship, so a row
  loaded earlier never grants access after the Guardianship ends;
- does not offer a new-appointment request: that flow keeps its current entry
  point, where the Clinic and Pet are chosen.

---

## 14. Paged Guardian Appointment reads — Verification Notes

In addition to §12, verification must demonstrate that:

38. an anonymous or unlinked caller fails with `28000`; `anon` cannot execute
    either read; an invalid limit, a partial cursor, or an Active rank other
    than 1 or 2 fails with `22023`;
39. the union of both reads equals, for every User, the union of
    `get_pet_appointments` over the Pets that User currently guards — for a
    primary Guardian and a co-Guardian of the same Pet alike, including an
    Appointment requested by the other Guardian; a former Guardian, a Pet
    creator without current Guardianship, and an unrelated User see none of
    that Pet's Appointments; a User guarding only one of two Pets sees only
    that Pet's; ending a Guardianship removes its Pet's rows from the next read;
40. Active holds exactly the `REQUESTED` and `CONFIRMED` Appointments,
    including those whose start has been reached, and History exactly the
    `COMPLETED`, `CANCELLED`, `NO_SHOW` and `EXPIRED` ones; no Appointment is in
    both;
41. concatenating the pages of each read, for every page size, equals the
    whole expected ordered list, without repetition; ties on the start are
    broken by `id`; a cursor at the last row returns an empty page, including
    after a page that was exactly full;
42. every shared column equals `get_pet_appointments` for the same
    Appointment, including after an accepted reschedule and for Appointments
    established in different timezones; `pet_name` is the current Pet name;
    `pending_reschedule_proposing_context` is `CLINIC` exactly while an
    actionable Clinic proposal is projected (for `REQUESTED` and `CONFIRMED`
    bases) and `NULL` after it is accepted, withdrawn or lapsed;
43. Active lists future Appointments by start ascending, then reached ones by
    start descending, and `active_rank` reports the group;
44. an Appointment cancelled between pages is not returned again by Active and
    appears in History; an Appointment completed between History pages appears
    only where its key sorts;
45. each read returns exactly the columns of BR-37 (plus `active_rank` for
    Active), no excluded column, and no total count;
46. the reads write nothing, `get_pet_appointments` keeps its signature, result
    and grants, and a first or deep page stays fast for a Guardian with
    thousands of Appointments while other Users' Appointments do not affect it;
47. `awaiting_clinic_confirmation` is `false` for a plain request, for a
    request with a pending Clinic alternative (the Guardian has not answered),
    and after a Clinic alternative is withdrawn without being accepted;
48. it becomes `true` for every current Guardian once either Guardian accepts
    the Clinic's alternative, with no pending proposal left;
49. a new Clinic alternative after an accepted one shows both the pending
    `CLINIC` proposal and `awaiting_clinic_confirmation = true`; withdrawing
    the new one, or accepting it, keeps `true`;
50. it becomes `false` after Clinic confirmation, a Guardian reschedule, a
    Guardian or Clinic cancellation, and expiry; it is never `true` for a
    `CONFIRMED` Appointment, including after an accepted Clinic reschedule,
    nor in History; and it always equals BR-33 evaluated on
    `get_pet_appointments`.

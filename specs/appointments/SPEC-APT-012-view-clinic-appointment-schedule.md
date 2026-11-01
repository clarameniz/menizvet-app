# SPEC-APT-012 — View Clinic Appointment Schedule

**Status:** APPROVED  
**Requirements:** REQ-APT-008  
**Domain:** Appointments  
**Priority:** P1

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the BR-48 flag `has_clinical_encounter` becomes `has_clinical_record` (`true` when at least one Clinical Record Entry exists); BR-23, BR-24, and BR-57 read per SPEC-MED-010 §10. The BR-51 projection and BR-52 read are unchanged; the assignment summary is read through `get_appointment_veterinarian_assignment` (SPEC-APT-007 BR-37). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Clinic actor to view the Appointments relevant to a
specific Clinic for operational scheduling and Appointment management.

The Clinic Appointment Schedule represents the scheduling obligations of one
Clinic.

It must preserve:

- Appointment lifecycle state;
- Pet identity;
- relevant scheduling information;
- current Veterinarian Assignment where applicable;
- historical Appointment outcomes.

Clinic schedule visibility must not automatically grant unrestricted access to
the Pet's medical history.

---

## 2. Preconditions

- The Clinic exists.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a current professional or operational relationship that
  permits Appointment schedule access for the target Clinic.
- The target Clinic belongs to a Veterinary Organization.
- Zero or more Appointments may exist for the Clinic.

---

## 3. Business Rules

### BR-1 — Schedule visibility is Clinic-specific

A Clinic Appointment Schedule contains Appointments belonging to the target
Clinic.

Access to:

    Animalia Madrid Centro

must not automatically expose Appointments belonging to:

    Animalia Getafe

even when both Clinics belong to the same Veterinary Organization.

---

### BR-2 — Organization Membership alone is insufficient

A User must not gain access to every Clinic Appointment Schedule merely because
they have an Organization Membership.

The User must have the applicable current responsibility or professional
context for the target Clinic.

---

### BR-3 — Organization-wide responsibilities may authorize several Clinics where explicitly permitted

A responsibility defined at Veterinary Organization scope may allow an
authorized User to manage Appointments across several Clinics where that
responsibility explicitly grants such capability.

The system must derive that access from the applicable responsibility model.

It must not assume that all Organization Members automatically have
Organization-wide scheduling access.

---

### BR-4 — Clinic schedule contains active Appointment obligations

Authorized Clinic actors may view non-terminal Appointments relevant to the
Clinic.

This includes, where applicable:

- `REQUESTED`;
- `CONFIRMED`.

These states must remain distinguishable.

---

### BR-5 — Clinic schedule may include historical Appointment outcomes

Authorized Clinic actors may access historical Appointment information required
for Clinic operations.

This includes:

- `COMPLETED`;
- `CANCELLED`;
- `NO_SHOW`;
- `EXPIRED` (`SPEC-APT-015`).

Historical Appointments must remain distinguishable from active scheduling
obligations.

---

### BR-6 — Appointment state must remain explicit

The schedule must not flatten all Appointments into a generic booked state.

For example:

    REQUESTED
    CONFIRMED
    COMPLETED
    CANCELLED
    NO_SHOW
    EXPIRED

must retain their domain meaning.

---

### BR-7 — Requested Appointment is not a confirmed booking

A `REQUESTED` Appointment must not be displayed or treated as though the Clinic
has already committed to the requested time.

The Clinic must be able to distinguish pending requests from confirmed
Appointments.

---

### BR-8 — Confirmed Appointment represents an active scheduling commitment

A `CONFIRMED` Appointment represents a current Clinic scheduling obligation
until it reaches an applicable terminal outcome.

---

### BR-9 — Historical Appointments are not active schedule obligations

Appointments in terminal states:

- `COMPLETED`;
- `CANCELLED`;
- `NO_SHOW`;
- `EXPIRED`;

must not be treated as current active Appointment commitments.

They remain historically identifiable.

Once the authoritative `EXPIRED` outcome exists, a request the Clinic did not
confirm before its requested time is no longer presented as an active
obligation. A `REQUESTED` Appointment whose requested start has passed cannot be
confirmed (`SPEC-APT-002` BR-19), even before `EXPIRED` is materialized.

---

### BR-10 — Appointment belongs to exactly one Clinic schedule

An Appointment associated with Animalia Madrid Centro must not simultaneously
appear as an Appointment belonging to Animalia Getafe.

Clinic identity must remain stable throughout the Appointment lifecycle.

---

### BR-11 — Pet remains identifiable

The Clinic schedule must preserve which Pet each Appointment concerns.

Appointments for different Pets must not be merged merely because they share:

- the same Guardian;
- the same Veterinarian;
- the same time;
- the same Clinic.

---

### BR-12 — Guardian requester may remain identifiable where operationally relevant

The User who requested the Appointment may be available to authorized Clinic
actors where required for Appointment management.

Requester identity must not be rewritten when another Guardian later becomes
involved.

BR-49 and BR-50 define exactly which requester information is available and
through which read (`SPEC-ID-006` BR-42).

---

### BR-13 — Shared Guardianship does not create duplicate Appointments

An Appointment belongs to the Pet rather than to a private copy of the Pet
owned by each Guardian.

If Luna has several Guardians, the Clinic schedule must contain one Appointment
domain entity rather than one copy per Guardian.

---

### BR-14 — Relevant confirmed time must be available

For confirmed Appointments, the Clinic schedule must preserve the applicable
confirmed scheduling information.

Where valid rescheduling occurred, the current confirmed time must reflect the
accepted scheduling state.

---

### BR-15 — Scheduling history remains traceable

Viewing the current Clinic schedule must not destructively rewrite or erase
previous scheduling information.

Accepted rescheduling and prior relevant scheduling history remain part of the
Appointment domain history.

---

### BR-16 — Current Veterinarian Assignment may be shown

Where an Appointment currently has an assigned Veterinarian, the Clinic
schedule may expose that Assignment to authorized operational actors.

The absence of an assigned Veterinarian must remain representable.

---

### BR-17 — Appointment may exist without assigned Veterinarian

A valid Clinic Appointment may appear in the schedule without a current
Veterinarian Assignment where the Appointment workflow permits Assignment to
occur later.

The schedule must not fabricate a professional Assignment.

---

### BR-18 — Historical Veterinarian Assignment remains preserved

If an Appointment is reassigned, the current schedule may emphasize the
current assigned Veterinarian.

Previous Assignment history must remain historically identifiable according to
the applicable Appointment Specifications.

---

### BR-19 — Clinic schedule does not establish clinical authorship

The assigned Appointment Veterinarian must not be represented as though they
necessarily:

- provided the eventual care;
- authored every Clinical Record Entry;
- finalized clinical documentation.

Appointment scheduling and clinical provenance remain separate concepts.

---

### BR-20 — Schedule visibility does not grant medical-history access

Authorization to view the Clinic Appointment Schedule must not automatically
authorize the actor to view the Pet's longitudinal medical history.

Medical information requires the applicable Medical Access Control basis.

---

### BR-21 — Operational Appointment information must follow least privilege

An actor viewing the Clinic schedule must receive only the information required
for their authorized operational purpose.

Appointment schedule visibility must not become an indirect mechanism for
exposing unrelated protected Pet information.

---

### BR-22 — Triage medical access requires separate authorization

Where Appointment triage requires relevant medical information, the applicable
Care Authorization and actor-specific medical-access rules must independently
permit that access.

The Clinic schedule itself is not the medical-access basis.

---

### BR-23 — Draft clinical information is not part of Clinic schedule

The Clinic Appointment Schedule must not expose Draft Clinical Record Entries
or Draft Clinical Attachments merely because they relate to an Appointment or
Clinical Encounter.

---

### BR-24 — Appointment schedule and Clinical Encounter remain separate

The Clinic schedule represents planned and resolved scheduling activity.

A Clinical Encounter represents actual care.

A completed or active Appointment view must not collapse these domain entities
into one object.

---

### BR-25 — Schedule may support clinically relevant operational context without becoming medical history

The schedule may expose information explicitly defined by Appointment
Specifications as necessary for managing the Appointment.

It must not become an unrestricted clinical record.

---

### BR-26 — Clinic schedule access is read behavior

This Specification defines visibility.

Being able to view an Appointment through the Clinic schedule does not
independently authorize the actor to:

- confirm it;
- cancel it;
- reschedule it;
- assign a Veterinarian;
- reassign a Veterinarian;
- mark it `COMPLETED`;
- mark it `NO_SHOW`.

Those capabilities follow their applicable Specifications.

---

### BR-27 — Multiple Clinics remain operationally separated

A User who legitimately works at several Clinics may access each applicable
Clinic schedule through its own professional context.

The system must preserve which Clinic context is being used.

For example:

    Dr. Garcia

    Animalia Madrid Centro
    → Madrid schedule

    Animalia Getafe
    → Getafe schedule

The two schedules must not be silently merged into one Clinic identity.

---

### BR-28 — Historical professional relationship alone does not grant current schedule access

A User who previously had operational authority at a Clinic must not retain
current Clinic schedule access solely because that relationship existed
historically.

Current authorization must be evaluated.

---

### BR-29 — Ending Organization Membership may remove current schedule access

Where Clinic schedule access derives from an Organization Membership or
responsibility, ending that current relationship must prevent future access
through that basis.

Historical Appointment information remains intact.

---

### BR-30 — Ending Clinic Assignment may remove Veterinarian schedule access where applicable

Where a Veterinarian's schedule visibility derives from their current Clinic
Assignment, an ended Assignment must no longer provide current schedule access.

Historical professional involvement remains preserved.

---

### BR-31 — Subscription loss does not delete Clinic Appointment information

Loss of professional Entitlement must not delete:

- active Appointments;
- historical Appointments;
- scheduling history;
- professional Assignment history.

Commercial state and Appointment existence remain separate.

---

### BR-32 — Historical Appointment access may remain required after Entitlement loss

An Organization that has lost normal professional Entitlement may still need
controlled access to existing Appointment information in order to:

- resolve existing obligations;
- cancel existing Appointments;
- preserve historical accountability.

Such access must follow the safe-resolution rules defined by
`SPEC-SUB-004`.

---

### BR-33 — Entitlement loss must not provide normal new scheduling capability

Any Clinic schedule access retained for safe resolution after Entitlement loss
must not be interpreted as permission to create or manage new paid Appointment
activity beyond the explicitly permitted resolution operations.

---

### BR-34 — Clinic unpublication does not remove internal Appointment history

Unpublishing a Clinic from public Discovery must not delete its Appointment
schedule or historical Appointment information.

Discovery visibility and internal Clinic operations are separate concerns.

---

### BR-35 — Empty Clinic schedule is valid

A Clinic may have no Appointments.

An authorized Clinic schedule request must succeed with an empty result.

---

### BR-36 — Schedule retrieval must preserve Appointment identity

Pagination, date grouping, filtering, or calendar presentation must not create
duplicate Appointment domain identities.

The same Appointment remains one Appointment regardless of presentation.

---

### BR-37 — Schedule chronology should use relevant Appointment time

The Clinic schedule should be capable of organizing Appointments according to
their applicable requested or confirmed scheduling time.

Historical terminal timestamps remain separate information.

The exact UI ordering rules are outside this Specification.

---

### BR-38 — Clinic schedule must distinguish current date range from historical completeness

A calendar or date-range view may intentionally show only part of the Clinic's
Appointment history.

The product must not treat that limited operational window as though no other
Appointments exist.

---

### BR-39 — Schedule access may be auditable where required

Access to Appointment operational data may be auditable where applicable
security or operational policy requires it.

This Specification does not classify ordinary Appointment schedule access as
medical-history access.

---

### BR-40 — Schedule retrieval must preserve coherent lifecycle information

The same Appointment must not be returned in contradictory current lifecycle
states within one coherent schedule representation.

---

### BR-41 — Pet is presented by its current name

Each Appointment in the Clinic schedule includes the current name of the Pet it
concerns (`pet_name`), resolved at read time from the current Pet Profile.

The Appointment remains associated with the Pet through its domain identity
(`pet_id`). The name is presentation, not identity.

The schedule does not preserve or reconstruct the Pet name that existed when
the Appointment was created. A later Pet rename changes the name shown for both
active and historical Appointments without changing Appointment identity or
lifecycle history.

---

### BR-42 — Pet name is the only Pet Profile information in the schedule

The Pet name is exposed only inside the already-authorized Clinic Appointment
Schedule.

The schedule must not expose any other Pet Profile, Guardianship, or Guardian
information, including:

- species;
- breed;
- sex;
- birth information;
- microchip identifier;
- profile image;
- behavioral safety information;
- Guardianship information;
- Guardian contact information.

The only exception is the requesting User's display name defined by BR-49.
The requester's email address is never part of the schedule; it is available
only through the single-Appointment read of BR-50.

Including the Pet name in the schedule does not create or imply a separate
professional Pet lookup, and does not widen professional visibility of Pets
beyond the Appointments of the authorized Clinic.

---

### BR-43 — Relevant scheduled interval carries its revision sequence

Each Appointment in the Clinic schedule includes
`current_schedule_revision_sequence`: the revision sequence of exactly the
Schedule Revision whose interval is returned as the relevant scheduled interval
(§4).

It is domain concurrency/version information for that Appointment's scheduling
context, used by Clinic-side mutations that must act only on the scheduling
context the actor reviewed (`SPEC-APT-002` BR-21). It is not a presentation
identity, does not identify a Schedule Revision outside its Appointment, and is
not an ordering key for the schedule.

The schedule exposes only this one sequence. It does not expose the complete
Schedule Revision history, earlier revisions, or Schedule Revision record
identifiers.

For a `CONFIRMED` Appointment, this sequence is the expected confirmed
revision sequence a Clinic reschedule proposal (`SPEC-APT-005` BR-26), a Clinic
cancellation (`SPEC-APT-003`), a `NO_SHOW` resolution (`SPEC-APT-010` BR-41),
and a completion (`SPEC-APT-009` BR-8) carry. For a `REQUESTED` Appointment, it
is the expected requested revision
sequence that confirmation (`SPEC-APT-002` BR-21) and a Clinic Alternative
Time proposal (`SPEC-APT-018` BR-8) carry. After a Guardian accepts a Clinic
alternative, it is the sequence of the accepted requested context.

---

### BR-44 — An actionable pending Reschedule Proposal is part of the schedule

For a `CONFIRMED` or `REQUESTED` Appointment with an actionable pending
Reschedule Proposal (`SPEC-APT-005` BR-31, `SPEC-APT-018` BR-17), the schedule
includes, through the same generic proposal projection for both workflows:

- the proposal identity, used to withdraw a Clinic proposal (`SPEC-APT-016`)
  or to accept a Guardian proposal on a confirmed Appointment
  (`SPEC-APT-006`);
- its state, `PENDING`;
- its proposing context, `GUARDIAN` or `CLINIC`; always `CLINIC` for a
  `REQUESTED` Appointment;
- the proposed start instant, end instant, and scheduling timezone, exactly as
  stored by the proposal;
- its reason, when one was recorded; a Clinic proposal always has one;
- its current scheduling feasibility (`SPEC-APT-005` BR-34), as the generic
  boolean `pending_reschedule_currently_feasible`: a valid current Clinic
  scheduling timezone and the frozen interval passing the proposal feasibility
  rules. It is scheduling-only (no Entitlement) and carries no reason in
  Phase 1.

The Appointment's lifecycle state discriminates the workflow, because a
pending proposal's base context always equals it (`SPEC-APT-011` BR-32).

The feasibility value is present (`true` or `false`) exactly when the proposal
fields are present and absent (`null`) when no proposal is projected. It is
derived at read time, never stored, and never changes the proposal. An
actionable proposal is projected whether or not it is currently feasible.

When a projected proposal is not currently feasible, the Professional client
keeps the proposal visible and keeps offering withdrawal of a Clinic proposal
under its existing rules (`SPEC-APT-016`), and may state generically: **This
proposed time is no longer available.** A new proposal still requires
withdrawing the current one first (`SPEC-APT-005` BR-14, `SPEC-APT-018`
BR-16); there is no combined replace operation.

At most one such proposal is included per Appointment. A proposal that is
accepted, withdrawn, `VOID`, or otherwise not actionable is not included. The
proposal never replaces the relevant scheduled interval or its revision
sequence.

The schedule does not expose the proposing User's identity or the history of
proposals that were never accepted.

---

### BR-45 — The schedule exposes the provenance of the relevant scheduled interval

For every Appointment, the schedule includes the same provenance as the
Guardian view (`SPEC-APT-011` BR-33):

- `current_schedule_source_proposal_id`;
- `current_schedule_source_proposing_context`.

Both describe the Schedule Revision that supplies the relevant scheduled
interval and its `current_schedule_revision_sequence`, and derive from that
revision's normalized source-proposal provenance; no separate flag is
persisted.

A `REQUESTED` Appointment whose relevant scheduled interval has a source
proposal from the `CLINIC` context is distinguishable from an ordinary
Guardian-authored request: the Guardian accepted the Clinic's proposed time
and the Clinic has not yet confirmed it. The Professional client presents it
as **Guardian accepted your proposed time — awaiting confirmation**
(`SPEC-APT-018` §5) and keeps the Confirm action available, subject to BR-61.

---

### BR-46 — Complete is a resolution action alongside NO_SHOW

The Professional client presents Appointment actions on the professional
Appointment detail, reached from the schedule.

For a `CONFIRMED` Appointment, the Professional client offers **Complete**
(`SPEC-APT-009`) next to **No-show** (`SPEC-APT-010`) as the two resolution
actions of a visit, when:

- the Appointment is `CONFIRMED`;
- the acting User holds `APPOINTMENT_COMPLETE` for the Clinic, as reported by
  the professional Clinic capabilities (`SPEC-ORG-008`);
- the relevant scheduled interval's start has been reached.

Complete submits the Appointment's `current_schedule_revision_sequence`
(BR-43) as the expected confirmed revision sequence.

These conditions are advisory presentation only. The backend remains
authoritative for capability, lifecycle, staleness, and the time rule, and the
client must handle a rejection — including a stale rejection, after which it
re-reads the schedule — without assuming the outcome.

Offering Complete must not depend on a Veterinarian Assignment, a Clinical
Encounter, or any clinical information, and the Professional client must not
require any of them before completing. No Veterinarian Assignment or Clinical
Encounter user interface is required for this action.

A past `CONFIRMED` Appointment awaiting resolution remains an active
obligation in the schedule until it is completed, marked `NO_SHOW`, or
cancelled; it then becomes historical (BR-9).

---

### BR-47 — A cancelled Appointment exposes its recorded cancellation reason

For a `CANCELLED` Appointment, the schedule includes `cancellation_reason`: the
reason recorded by its cancellation (`SPEC-APT-003` BR-8, BR-9), taken from the
Appointment's single `CANCELLED` Lifecycle Event, whether a Guardian or the
Clinic cancelled it and whether it was `REQUESTED` or `CONFIRMED` when
cancelled.

The cancellation reason:

- is returned verbatim, exactly as the cancellation stored it;
- is absent (`null`) when the cancellation recorded no reason, which is
  possible only for a Guardian cancellation (`SPEC-APT-003` BR-9);
- is absent (`null`) for every Appointment that is not `CANCELLED`, following
  the read's existing nullable-field convention;
- is never populated from the reason for visit, Guardian notes, a Reschedule
  Proposal reason, or any other free-text field;
- is the same value the Guardian view exposes for the same Appointment
  (`SPEC-APT-011` BR-31).

It is operational Appointment context, not clinical documentation or a Medical
Record Entry, and it exposes no cancelling actor identity, cancellation
context, Event time, or other lifecycle history.

The Professional client shows the cancellation reason on the professional
Appointment detail of a `CANCELLED` Appointment when one is present, separately
from the reason for visit, and shows no empty section when there is none.

Exposing the reason is read behavior only (BR-26); it does not change
cancellation semantics.

---

### BR-48 — The schedule exposes whether a Clinical Encounter exists

Defined by **Minimal Clinical Record — Phase 1**.

Each schedule row includes `has_clinical_encounter`: `true` when a Clinical
Encounter references the Appointment (`SPEC-MED-001` BR-35), whatever that
Encounter's lifecycle (`ACTIVE` or `CONCLUDED`); otherwise `false`. It is
always present.

It is operational Appointment context, not medical information:

- it exposes no Encounter identity, lifecycle state, care start, conclusion,
  responsible Veterinarian, Clinical Record Entry, Draft, category, content,
  Attachment, or Care Authorization (BR-23, BR-24);
- every actor authorized for the schedule (BR-1) receives it, including
  Owners, Administrators, and Receptionists without clinical capability. Those
  actors already learn the same fact when an Appointment action is rejected
  because an Encounter exists (`SPEC-APT-003`, `SPEC-APT-005` BR-29,
  `SPEC-APT-010` BR-5);
- reading it is not a medical-access operation and creates no Medical Access
  Audit Event (`SPEC-ACC-003`).

Its purpose is advisory presentation. When it is `true`, the Professional
client does not offer the actions the backend rejects because clinical care
has begun:

- Clinic cancellation (`SPEC-APT-003`);
- Mark as no-show (`SPEC-APT-010` BR-5);
- Propose a new time for a confirmed Appointment (`SPEC-APT-005` BR-29).

Mark as completed stays offered under its own lifecycle and time rules
(`SPEC-APT-009` BR-12). The client may show a neutral operational note such as
"Clinical care started / Atención clínica iniciada". It never derives the flag
from any other data. The backend operations remain authoritative and keep
rejecting those actions independently of the flag.

The flag does not change the Guardian Appointment view (`SPEC-APT-011`).

---

### BR-49 — The schedule presents the requesting User by current display name

Defined by **Appointment Requester Contact — Phase 1** (`SPEC-ID-006` BR-42).

Each schedule row includes `requester_display_name`: the current User Profile
display name of the Appointment's requesting User (`SPEC-APT-001` BR-9),
trimmed, or `null` when that User has no display name or only a blank one. It
is always present.

- It identifies the original requester, not necessarily a current Guardian.
  It is returned in every lifecycle state and whether or not the requester
  still holds a Guardianship of the Pet. Another Guardian of the Pet is never
  shown in its place (BR-12, BR-13).
- It is resolved at read time; no snapshot is kept. A display-name change is
  reflected on active and historical rows alike, without changing Appointment
  identity or history (same rule as `pet_name`, BR-41).
- Every actor authorized for the schedule (BR-1) receives it. Authorization,
  row set, ordering, and every other returned value are unchanged by it.
- The schedule never includes the requester's email address, any other User
  Profile field, Guardianship, or any other Guardian (BR-42).

The Professional client shows the name with the Pet on each schedule row and
uses a neutral localized fallback when it is `null`. A schedule row offers no
contact action.

---

### BR-50 — The requester contact is read for one Appointment at a time

Defined by **Appointment Requester Contact — Phase 1** (`SPEC-ID-006` BR-42).

The client reads the requester contact of one Appointment through

    get_clinic_appointment_requester_contact(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns table (
        requester_display_name text,
        requester_email text
    )

It is `SECURITY DEFINER`, `STABLE`, has an empty `search_path`, and is
executable only by `authenticated`.

Evaluation order:

1. authentication and a coherent domain User — otherwise `28000`;
2. the acting User currently holds `APPOINTMENT_VIEW_SCHEDULE` for
   `p_clinic_id` (BR-1–BR-3, BR-28–BR-30) **and** `p_appointment_id` is an
   Appointment of that Clinic. Otherwise one uniform `42501`
   `Appointment requester contact unavailable`, without hint, for a missing or
   foreign Clinic, a missing Appointment, an Appointment of another Clinic,
   and missing authority alike.

On success exactly one row is returned:

- `requester_display_name` — as defined by BR-49;
- `requester_email` — the requesting User's current authentication email
  address when that address is verified, otherwise `null`.

Both values follow the original requester (BR-12) in every lifecycle state —
`REQUESTED`, `CONFIRMED`, `COMPLETED`, `CANCELLED`, `NO_SHOW`, `EXPIRED` —
and whether or not the requester is still a Guardian of the Pet. They are
current values with no snapshot.

The read returns no other column and no identifier. It exposes no other
Guardian, Guardianship, User Profile field, phone number, or authentication
data other than the verified email address. It creates, changes, stores, or
logs nothing, and no error carries the email address.

The Professional client reads it from the Appointment detail only, never for
the whole schedule. The detail presents an "Appointment contact / Contacto de
la cita" section with the name, the email when present, and an action that
opens the device's email application to that address. Without an email it
shows a neutral note and offers no action. A failure of this read leaves the
rest of the Appointment detail usable. No phone, contact form, or in-app
messaging is offered.

---

## 4. Clinic Appointment Schedule Information

The schedule should provide enough information for authorized Clinic actors to
understand current scheduling obligations.

### Core information

- Appointment identity;
- Pet identity (`pet_id`);
- Pet current name (`pet_name`), as defined by BR-41;
- Clinic;
- current Appointment lifecycle state;
- relevant requested or confirmed time, as the relevant scheduled interval
  defined below;
- the revision sequence of that relevant scheduled interval
  (`current_schedule_revision_sequence`, BR-43).

### Where applicable

- requesting User, with the current display name of that User
  (`requester_display_name`, BR-49); the requester's email address is
  available only through the single-Appointment read of BR-50;
- current assigned Veterinarian;
- relevant rescheduling state, including an actionable pending Reschedule
  Proposal for either workflow (BR-44) and the provenance of the relevant
  scheduled interval (BR-45);
- terminal outcome, including the recorded cancellation reason of a
  `CANCELLED` Appointment (`cancellation_reason`, BR-47);
- whether a Clinical Encounter exists for the Appointment
  (`has_clinical_encounter`, BR-48), with no clinical information;
- relevant operational information defined by Appointment Specifications.

### Relevant scheduled interval

The relevant scheduled interval of an Appointment is its latest effective
scheduling context: the latest requested context if the Appointment was never
confirmed, otherwise the latest confirmed context, including accepted
reschedules. Cancellation, completion, and no-show do not change it. Earlier
requested and confirmed contexts remain part of scheduling history and are not
replaced by it.

### Relevant schedule revision sequence

`current_schedule_revision_sequence` (BR-43) is the revision sequence of the
same Schedule Revision that supplies `current_scheduled_start_at`,
`current_scheduled_end_at`, and `current_scheduling_timezone_name`. It is a
positive integer, always present, matching the persisted Schedule Revision
sequence (`integer`, greater than zero, unique and contiguous from 1 within
the Appointment).

For a `REQUESTED` Appointment it is the revision sequence of the latest
requested scheduling context. For an Appointment that was ever confirmed it is
the revision sequence of the latest confirmed scheduling context.

Medical information is not implicitly included.

No Pet Profile information other than the Pet's current name is included
(BR-42).

---

## 5. Scenarios

### Scenario: Clinic actor views requested Appointments

Given Animalia Madrid Centro has several `REQUESTED` Appointments
And Carlos is authorized to view that Clinic's Appointment schedule

When Carlos views the schedule

Then the requested Appointments are available
And each remains identifiable as `REQUESTED`
And they are not represented as confirmed commitments

---

### Scenario: Clinic actor views confirmed Appointments

Given Animalia Madrid Centro has confirmed Appointments
And Carlos is authorized to view the Clinic schedule

When Carlos views the schedule

Then the confirmed Appointments are available
And their confirmed scheduling information remains identifiable

---

### Scenario: Clinic sees terminal Appointment history

Given Animalia Madrid Centro has:

- one `COMPLETED` Appointment;
- one `CANCELLED` Appointment;
- one `NO_SHOW` Appointment

When an authorized Clinic actor views historical Appointment information

Then all three Appointments remain identifiable
And their terminal outcomes remain distinguishable
And none is treated as an active upcoming obligation

---

### Scenario: Organization Member without Clinic capability cannot view schedule

Given Maria has an active Membership in Animalia Veterinary Group
And Maria has no responsibility or professional context authorizing access to
Animalia Madrid Centro's schedule

When Maria attempts to view the Clinic schedule

Then access is denied
And Organization Membership alone is insufficient

---

### Scenario: Clinic authority does not expose another Clinic schedule

Given Carlos is authorized to manage Appointments at Animalia Madrid Centro
And Carlos has no applicable authority at Animalia Getafe

When Carlos attempts to view Animalia Getafe's schedule

Then access is denied
And Madrid authority is insufficient

---

### Scenario: Organization-wide scheduling responsibility may access multiple Clinics

Given Carlos has an explicit Organization-level responsibility granting
Appointment schedule access across Animalia Clinics
And Animalia operates Madrid Centro and Getafe

When Carlos accesses each Clinic schedule

Then Carlos may access Madrid Centro through its Clinic context
And Carlos may access Getafe through its Clinic context
And the two Clinic schedules remain distinct

---

### Scenario: Veterinarian sees schedule through valid Clinic context

Given Dr. Garcia has a current professional context at Animalia Madrid Centro
And that context includes Appointment schedule visibility

When Dr. Garcia views the Clinic schedule

Then applicable Madrid Appointments may be visible
And her professional status at Madrid does not grant access to unrelated Clinic
schedules

---

### Scenario: Ended Clinic Assignment no longer grants schedule access

Given Dr. Garcia previously had a Clinic Assignment at Animalia Madrid Centro
And that Assignment has ended
And no other applicable schedule-access capability exists

When Dr. Garcia attempts to view the current Madrid Clinic schedule

Then access is denied
And historical Clinic Assignment alone is insufficient

---

### Scenario: Appointment without Veterinarian is visible

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro
And no Veterinarian has yet been assigned

When an authorized Clinic actor views the schedule

Then Luna's Appointment remains visible
And no Veterinarian is fabricated

---

### Scenario: Current Veterinarian Assignment is visible

Given Luna has a `CONFIRMED` Appointment
And Dr. Garcia is currently assigned

When an authorized Clinic actor views the Appointment

Then Dr. Garcia may be shown as the current assigned Veterinarian

---

### Scenario: Reassignment preserves historical Assignment

Given Dr. Garcia was originally assigned to Luna's Appointment
And Dr. Lopez validly replaced her

When an authorized Clinic actor views the current schedule

Then Dr. Lopez may be shown as the current assigned Veterinarian
And Dr. Garcia's previous Assignment remains historical information

---

### Scenario: Schedule visibility does not expose Pet medical history

Given Carlos is authorized to view Animalia Madrid Centro's Appointment
schedule
And Luna has protected longitudinal medical history

When Carlos views Luna's Appointment through the schedule
And Carlos has no applicable medical-history access for that purpose

Then the Appointment information may be visible
And Luna's protected medical history is not automatically exposed

---

### Scenario: Triage requires separate medical authorization

Given Luna has a requested Appointment at Animalia Madrid Centro
And Carlos is authorized to perform Appointment triage
And the applicable Care Authorization permits relevant medical access

When Carlos enters the authorized triage workflow

Then the applicable medical information may be accessed according to the
Medical Access Control rules
And the Clinic schedule itself is not treated as the access basis

---

### Scenario: Draft clinical information is not exposed through schedule

Given Luna's Appointment has an associated Clinical Encounter
And that Encounter contains Draft Clinical Record Entries

When an operational Clinic actor views the Appointment schedule

Then Draft clinical content is not exposed merely because the Appointment is
visible

---

### Scenario: Appointment remains visible after Clinic unpublication

Given Luna has a historical Appointment at Animalia Madrid Centro
And the Clinic is later unpublished

When an authorized internal Clinic actor views historical Appointment data

Then Luna's Appointment remains identifiable
And Clinic unpublication does not erase Appointment history

---

### Scenario: Existing Appointments remain visible after Entitlement loss for safe resolution

Given Animalia Madrid Centro has existing Appointments
And Animalia Veterinary Group loses normal professional Entitlement
And Carlos remains authorized to resolve existing obligations under
`SPEC-SUB-004`

When Carlos accesses the applicable existing Appointment information

Then the Appointments remain identifiable for safe resolution
And the visibility does not authorize unrestricted new scheduling activity

---

### Scenario: Subscription loss does not erase historical Appointment schedule

Given Animalia Madrid Centro has historical completed, cancelled, and no-show
Appointments

When Animalia's Subscription becomes `EXPIRED`

Then the historical Appointment information remains intact

---

### Scenario: Empty Clinic schedule

Given Animalia Madrid Centro has no Appointments
And Carlos is authorized to view its schedule

When Carlos views the Clinic schedule

Then the operation succeeds
And the schedule contains no Appointments

---

### Scenario: Same Pet has several Clinic Appointments

Given Luna has one Appointment at Animalia Madrid Centro
And another Appointment at VetCare Toledo

When an authorized Animalia actor views the Madrid schedule

Then the Animalia Appointment may be visible
And the VetCare Appointment does not become part of Animalia's Clinic schedule

---

### Scenario: Authorized Clinic professional sees Pet identity and current name

Given Luna has an Appointment at Animalia Madrid Centro
And Carlos is authorized to view that Clinic's Appointment schedule

When Carlos views the schedule

Then Luna's Appointment includes Luna's `pet_id`
And it includes Luna's current name as `pet_name`
And no other Pet Profile, Guardianship, or Guardian information is included

---

### Scenario: Pet renamed after Appointment creation

Given Luna has a `CONFIRMED` Appointment and a `COMPLETED` Appointment at
Animalia Madrid Centro
And a current Guardian later renames Luna to "Luna María"

When an authorized Clinic actor views the schedule

Then both Appointments show `pet_name` "Luna María"
And both Appointments keep the same Appointment identity and `pet_id`
And their lifecycle state and scheduling history are unchanged

---

### Scenario: Unauthorized actor receives no Pet name

Given Luna has an Appointment at Animalia Getafe
And Carlos has no applicable schedule-view authority at Animalia Getafe

When Carlos attempts to view Animalia Getafe's schedule

Then access is denied
And no `pet_name` is disclosed

---

### Scenario: Different Pets with the same name remain distinct

Given two different Pets are both named "Luna"
And each has an Appointment at Animalia Madrid Centro

When an authorized Clinic actor views the schedule

Then both Appointments show `pet_name` "Luna"
And each Appointment carries its own distinct `pet_id`
And the Appointments are not merged

---

### Scenario: Requested Appointment exposes its current revision sequence

Given Luna's Appointment is `REQUESTED` with requested revision 1 for 10:00
And a current Guardian reschedules it to 11:00, establishing requested revision 2

When an authorized Clinic actor views the schedule

Then the Appointment shows 11:00 as its relevant scheduled interval
And its `current_schedule_revision_sequence` is 2
And revision 1 is not exposed

---

### Scenario: Confirmed Appointment exposes the confirmed revision sequence

Given Luna's Appointment was requested at revision 1 and confirmed at revision 2

When an authorized Clinic actor views the schedule

Then its relevant scheduled interval is the confirmed context of revision 2
And its `current_schedule_revision_sequence` is 2

---

## 6. Clinic Schedule vs Guardian Appointment View

Guardian Appointment visibility answers:

    "What Appointments does my Pet have?"

Clinic Appointment visibility answers:

    "What Appointment obligations does this Clinic have?"

These views operate over the same Appointment domain entities but through
different authorization contexts.

Conceptually:

    Luna
      ↓
    Appointment A
      ↓
    Animalia Madrid Centro

may be visible through:

    Maria → Guardian context

and:

    Carlos → Clinic operational context

The existence of two views must not create two Appointment records.

---

## 7. Clinic Schedule vs Medical Access

Operational schedule access and medical access are separate.

Conceptually:

    Clinic schedule capability
        ↓
    Appointment operational information

while:

    Care Authorization
        +
    actor-specific medical capability
        ↓
    relevant medical information

This distinction prevents ordinary scheduling personnel from receiving
unrestricted medical history merely because they can manage Clinic
Appointments.

---

## 8. Current and Historical Schedule Information

The Clinic must be capable of distinguishing:

    Active obligations
    ├── REQUESTED
    └── CONFIRMED

from:

    Historical outcomes
    ├── COMPLETED
    ├── CANCELLED
    ├── NO_SHOW
    └── EXPIRED

The exact calendar, list, tab, filter, or date-range interface is outside this
Specification.

---

## 9. Edge Cases

### User works at several Clinics

The User may legitimately access several Clinic schedules.

Each access must occur through the applicable Clinic or Organization
responsibility context.

The schedules remain independently identifiable.

---

### Same Appointment appears in different UI filters

An Appointment may appear in several legitimate presentation filters or views.

This must not create duplicate domain Appointments.

---

### Large Clinic schedule

A busy Clinic may contain many Appointments.

Date-range queries, pagination, incremental loading, or calendar-based
retrieval may be required.

Those mechanisms must not alter Appointment lifecycle meaning.

---

### Schedule is viewed while an Appointment state changes

An Appointment may change lifecycle state concurrently with schedule
retrieval.

The architecture must provide an appropriate consistency strategy.

The domain must not intentionally represent one Appointment as having two
contradictory current lifecycle states.

A schedule read may become stale after it is returned. The
`current_schedule_revision_sequence` (BR-43) lets a later Clinic-side mutation
detect that the scheduling context the actor reviewed has since been
superseded.

---

### Assigned Veterinarian leaves Clinic

Historical Assignment remains identifiable.

Current scheduling behavior must follow the applicable Veterinarian Assignment
and Appointment lifecycle rules.

---

### Pet changes Guardians

Guardian relationship changes do not alter the Clinic's historical Appointment
identity or requester attribution.

---

### Pet renamed after the Appointment

The schedule shows the Pet's current name for both active and historical
Appointments (BR-41).

No historical Pet name is preserved or reconstructed; the Appointment remains
historically identified by `pet_id`.

---

### Pet identity cannot be unresolved

An Appointment cannot validly reference a deleted Pet under the current model:
every Appointment requires a Pet, and Pets are not deleted through ordinary
operations.

The Pet name is required and non-empty (`SPEC-PET-001`, `SPEC-PET-005` BR-6).

Therefore every Appointment in the schedule has a Pet name, and no missing-name
fallback is required.

---

### Several Pets share a name

Pet names are not unique (`SPEC-PET-001` BR-12).

Pets with the same name remain distinct through `pet_id`, and their
Appointments must not be merged (BR-11).

---

## 10. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-004 — End Organization Membership
- SPEC-CLI-001 — Create Clinic
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
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
- SPEC-ID-006 — Manage User Profile (BR-42, Appointment requester contact
  visibility context)
- SPEC-ORG-008 — View My Professional Clinics (advisory capabilities for the
  Professional client's actions, BR-46)
- SPEC-PET-001 — Register Pet (Pet name is required)
- SPEC-PET-005 — Update Pet Profile (Pet name is mutable; ordinary name
  history is not preserved)

Where medical triage occurs:

- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke or End Pet Care Authorization

Loss-of-Entitlement behavior may additionally depend on:

- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-SUB-004 — Handle Loss of Professional Entitlements

---

## 12. Out of Scope

This Specification does not define:

- Guardian Appointment visibility;
- Clinic availability configuration;
- Veterinarian availability;
- Appointment booking conflict detection;
- calendar UI;
- drag-and-drop scheduling;
- Appointment search;
- Appointment filtering behavior;
- pagination implementation;
- medical-history visibility;
- Appointment notification behavior;
- analytics or operational reporting;
- Clinic staff rota management.

---

## 13. Verification Notes

Verification must demonstrate that:

1. authorized Clinic actors may view Appointments belonging to the applicable
   Clinic;
2. Organization Membership alone does not automatically grant Clinic schedule
   access;
3. Organization-wide responsibility may authorize several Clinics only where
   explicitly defined;
4. Clinic schedule access does not expose Appointments belonging to unrelated
   Clinics;
5. `REQUESTED` and `CONFIRMED` remain distinguishable active states;
6. `COMPLETED`, `CANCELLED`, and `NO_SHOW` remain distinguishable historical
   states;
7. Appointment Pet, Clinic, requester, scheduling, and professional Assignment
   information remain coherent;
8. an Appointment without a Veterinarian Assignment remains representable;
9. current Veterinarian Assignment may be displayed without erasing historical
   Assignment information;
10. schedule visibility does not imply clinical authorship;
11. Clinic schedule access does not automatically grant medical-history access;
12. triage medical access requires its independent authorization basis;
13. Draft clinical information is not exposed through ordinary schedule
    visibility;
14. viewing the schedule does not independently grant Appointment-management
    operations;
15. ended Membership or Clinic Assignment no longer grants current access where
    that relationship was the access basis;
16. Clinic unpublication and Subscription loss do not erase Appointment
    information;
17. safe-resolution visibility after Entitlement loss does not provide normal
    new scheduling capability;
18. empty Clinic schedules are valid;
19. the same Appointment remains one domain entity across operational views;
20. schedule retrieval preserves coherent current Appointment lifecycle state;
21. every returned Appointment includes its `pet_id` and the correct current
    `pet_name` of that Pet;
22. a Pet rename is reflected on both active and historical Appointments
    without changing Appointment identity, `pet_id`, lifecycle state, or
    scheduling history;
23. a caller denied schedule access receives no `pet_name`;
24. no additional Pet Profile, Guardianship, or Guardian information is exposed
    through the schedule, other than the requester's display name (BR-49);
25. different Pets with the same name remain distinct by `pet_id`;
26. all previously returned schedule information, authorization behavior, and
    ordering remain unchanged by the addition of `pet_name`;
27. every Appointment exposes the relevant scheduled interval defined in §4 in
    every lifecycle state, and it is the same interval exposed for that
    Appointment through the Guardian Appointment view;
28. every Appointment exposes `current_schedule_revision_sequence`, a positive
    integer equal to the revision sequence of exactly the Schedule Revision
    whose start, end, and timezone are returned, in every lifecycle state,
    including after a requested reschedule, a confirmation, and an accepted
    confirmed reschedule;
29. no earlier Schedule Revision, Schedule Revision record identifier, or
    complete scheduling history is exposed by the addition of
    `current_schedule_revision_sequence`;
30. all previously returned schedule information, authorization behavior, and
    ordering remain unchanged by the addition of
    `current_schedule_revision_sequence`;
31. `EXPIRED` Appointments are returned as historical outcomes, are never
    treated as active obligations, keep their relevant scheduled interval (§4),
    and remain distinguishable from `COMPLETED`, `CANCELLED`, and `NO_SHOW`,
    whose meanings are unchanged;
32. a `REQUESTED` Appointment with an actionable Clinic Alternative Time
    proposal exposes the proposal identity, `PENDING`, `CLINIC`, the frozen
    interval and timezone, and the reason, while its relevant scheduled
    interval and `current_schedule_revision_sequence` remain those of the
    current requested context;
33. a proposal that is accepted, withdrawn, `VOID`, or lapsed is not included,
    for either base context;
34. after a Guardian accepted a Clinic alternative, the Appointment is
    `REQUESTED` with the accepted interval, the new revision sequence,
    `current_schedule_source_proposal_id` set, and
    `current_schedule_source_proposing_context = CLINIC`, and no pending
    proposal;
35. an ordinary Guardian-requested or initial requested context exposes no
    source proposal;
36. all previously returned schedule information, authorization behavior, and
    ordering remain unchanged by the addition of the provenance fields;
37. for a `CONFIRMED` Appointment, `current_schedule_revision_sequence` is
    accepted as the expected confirmed revision sequence by completion
    (`SPEC-APT-009`), and a superseded value is rejected as stale;
38. a `COMPLETED` Appointment is returned as a historical outcome with its
    relevant scheduled interval unchanged, whether or not a Clinical Encounter
    exists for it;
39. the Professional client offers Complete only as advisory presentation for a
    `CONFIRMED` Appointment whose start has been reached and whose acting User
    holds `APPOINTMENT_COMPLETE`, without requiring a Veterinarian Assignment
    or Clinical Encounter;
40. `pending_reschedule_currently_feasible` is `null` exactly when no proposal
    is projected and `true` or `false` otherwise; it follows current scheduling
    feasibility only and does not change with the Organization's Entitlement
    (BR-44);
41. an actionable proposal that is not currently feasible is still projected,
    and withdrawal of a Clinic proposal remains offered and succeeds (BR-44);
42. a `CANCELLED` Appointment cancelled by a Guardian exposes the Guardian's
    recorded reason verbatim, and none when the Guardian gave no reason
    (BR-47);
43. a `CANCELLED` Appointment cancelled by the Clinic — whether `REQUESTED` or
    `CONFIRMED`, before or after the confirmed start, and after an accepted
    confirmed reschedule — exposes exactly the Clinic's recorded reason
    (BR-47);
44. for the same Appointment, `cancellation_reason` equals the value the
    Guardian view exposes (`SPEC-APT-011` BR-31);
45. `REQUESTED`, `CONFIRMED`, `COMPLETED`, `NO_SHOW`, and `EXPIRED`
    Appointments expose no cancellation reason;
46. an accepted or pending Reschedule Proposal reason, the reason for visit,
    and Guardian notes never appear as a cancellation reason;
47. reading the schedule, including the cancellation reason, creates or
    changes no Lifecycle Event, Schedule Revision, Care Authorization, or
    Communication;
48. the Professional client shows the cancellation reason on the detail of a
    `CANCELLED` Appointment only when one is present, separately from the
    reason for visit;
49. `has_clinical_encounter` is `false` for an Appointment with no Clinical
    Encounter and `true` once an Encounter references it, whether `ACTIVE` or
    `CONCLUDED`, and for `CONFIRMED` and `COMPLETED` Appointments alike
    (BR-48);
50. the flag carries no Encounter state, care time, Entry, Draft, or other
    clinical information, and is returned identically to Owners,
    Administrators, Receptionists, and Veterinarians authorized for the
    schedule (BR-48);
51. reading the flag creates no Medical Access Audit Event and changes no
    Appointment, Encounter, or Care Authorization (BR-48);
52. with the flag `true`, the Professional client offers no Clinic
    cancellation, no-show, or confirmed-reschedule proposal, and still offers
    completion when its own rules allow it; with the flag `false`, the offered
    actions are unchanged (BR-48);
53. every schedule row includes `requester_display_name`: the requesting
    User's current trimmed display name, or `null` when none or only a blank
    one is set, for Owners, Administrators, Receptionists, and assigned
    Veterinarians alike (BR-49);
54. `requester_display_name` is that of the original requester in every
    lifecycle state, also after the requester's Guardianship ended, and never
    that of another Guardian of the Pet (BR-49);
55. a display-name change is reflected by the next schedule read without
    changing any other returned value (BR-49);
56. the schedule never returns an email address, and all previously returned
    schedule information, authorization behavior, and ordering remain
    unchanged by the addition of `requester_display_name` (BR-42, BR-49);
57. the requester contact read returns exactly one row with the requester's
    current display name and current verified email to Owners,
    Administrators and Receptionists of the Clinic (Organization or Clinic
    scope) and to Veterinarians with a current Clinic Assignment there, in
    every lifecycle state and whether or not the requester is still a Guardian
    (BR-50);
58. the email is `null` while the requester's address is not verified, and
    the display name is `null` when none or a blank one is set (BR-50);
59. the requester contact read is denied with one uniform `42501`, revealing
    nothing, to a Clinic-scoped actor of another Clinic, a Veterinarian without
    a current Clinic Assignment there, a bare Member, an ended Membership or
    Responsibility Grant, a member of another Organization, a Guardian
    (including the requester), for a nonexistent Clinic or Appointment, and for
    an Appointment of another Clinic; `anon` cannot execute it (BR-50);
60. the requester contact read returns no identifier, no other Guardian, and
    no other User Profile or authentication data, creates or changes nothing,
    and grants no direct access to authentication data (BR-50);
61. the Professional client shows the requester's name or a neutral fallback
    on each schedule row with no contact action, and on the Appointment detail
    shows the contact section with an email action only when an email is
    present, keeping the rest of the detail usable when the contact read fails
    (BR-49, BR-50).

---

## 14. Professional calendar reads — Phase 1

Defined by **Professional Appointment Calendar — Phase 1, contracts**. The
Professional client will present the Clinic schedule as a monthly calendar with
the Appointments of the selected day, a separate Pending view, and a paginated
History. This section defines the reads that make that possible without
retrieving every Appointment of the Clinic.

It adds reads only. It does not change any Business Rule above, any lifecycle
state or transition, any write contract, or what an authorized actor may see:
every new read returns a subset of what `get_clinic_appointment_schedule`
returns, or an aggregate of it — except the calendar context of BR-60, which
adds only the Clinic's current valid scheduling timezone and its current local
date to the same schedule viewers. `get_clinic_appointment_schedule` itself
stays unchanged for the installed clients.

### BR-51 — One Clinic Appointment projection

Every row returned by a read of this section carries exactly the columns, value
semantics and nullability of a `get_clinic_appointment_schedule` row (BR-41 to
BR-49, §4) for the same Appointment, evaluated at read time. One internal
projection supplies them, so the schedule, the single-Appointment read and the
reads of BR-56, BR-57 and BR-59 cannot drift apart.

The requester's email is never part of these reads (BR-42); it remains
available only through BR-50.

### BR-52 — The Professional client reads one Appointment through its Clinic

    get_clinic_appointment(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns table (… the columns of BR-51 …)

It is `SECURITY DEFINER`, `STABLE`, has an empty `search_path`, and is
executable only by `authenticated`. The Appointment is resolved directly, never
by reading the Clinic's whole schedule.

Evaluation order:

1. authentication and a coherent domain User — otherwise `28000`;
2. the acting User currently holds `APPOINTMENT_VIEW_SCHEDULE` for
   `p_clinic_id` (BR-1–BR-3, BR-28–BR-30) **and** `p_appointment_id` is an
   Appointment of that Clinic. Otherwise one uniform `42501`
   `Clinic Appointment unavailable`, without hint, for a missing or foreign
   Clinic, missing authority, a missing Appointment, and an Appointment of
   another Clinic alike.

On success exactly one row is returned, in every lifecycle state. Reading it is
not a medical-access operation and creates or changes nothing.

The Professional Appointment detail and its sub-screens (reschedule proposal,
alternative time, clinical record and its entries) read their Appointment
through this read only, on every focus and after every mutation they perform —
any re-read this Specification asks of them (for example after a stale
rejection, BR-46) is this read. They never read the whole schedule to find one
Appointment, so an Appointment opens whatever its date. The Professional
client presents this read's uniform denial as an unavailable Appointment; it
does not try to tell an unknown or foreign Appointment from lost authority.

### BR-53 — Calendar Appointments and their Clinic-local date

An Appointment is a **calendar Appointment** when its lifecycle state is
`REQUESTED`, `CONFIRMED`, `COMPLETED`, or `NO_SHOW`: activity that is or was
scheduled for its day. `CANCELLED` and `EXPIRED` Appointments are not calendar
Appointments; they remain available through History (BR-59) and the schedule.

The stored lifecycle state is used as it is. A `REQUESTED` Appointment whose
requested start has passed stays a `REQUESTED` calendar Appointment until
expiry is materialized (`SPEC-APT-015`), whether or not the expiry job runs in
that environment; the reads never fabricate `EXPIRED` (BR-9).

The **Clinic-local date** of an Appointment is the civil date on which its
relevant scheduled interval (§4) starts, in the timezone that interval was
established in (`current_scheduling_timezone_name`, `SPEC-APT-013` BR-47–BR-49).
It is the date the Professional client shows for the Appointment. A later
change of the Clinic's current timezone does not move an existing Appointment
to another date (`SPEC-APT-013` BR-48), and the device's timezone never decides
it.

Each calendar Appointment has exactly one Clinic-local date. A pending
Reschedule Proposal (BR-44) never moves it or adds a second date; earlier
Schedule Revisions are not considered.

One internal definition of calendar Appointments and their Clinic-local dates
is shared by the month counts (BR-54) and the day read (BR-56), so a
day's count always equals the number of rows that day's read returns at the
same instant.

### BR-54 — Calendar Appointments per day of one month

    get_clinic_appointment_month_counts(
        p_clinic_id uuid,
        p_year integer,
        p_month integer
    ) returns table (day date, appointment_count integer)

It is `SECURITY DEFINER`, `STABLE`, has an empty `search_path`, and is
executable only by `authenticated`.

Evaluation order:

1. authentication and a coherent domain User — otherwise `28000`;
2. the acting User currently holds `APPOINTMENT_VIEW_SCHEDULE` for
   `p_clinic_id` — otherwise `42501`, the same outcome as the schedule read
   for a missing or foreign Clinic and missing authority;
3. `p_year` between 2000 and 2999 and `p_month` between 1 and 12, neither
   null — otherwise `22023` `Calendar month is invalid`.

It returns one row per Clinic-local date of that month with at least one
calendar Appointment (BR-53), ordered by `day`, with `appointment_count` the
number of distinct calendar Appointments on that date. A date without calendar
Appointments is absent and means zero; a month without any returns no rows.
Any month may be asked for, past or future.

The read returns no Appointment, Pet, requester, Veterinarian, lifecycle state,
or clinical information, and no identifier. It is computed in one aggregate
query over the month's Schedule Revisions, never per day and never over the
Clinic's whole Appointment history.

The count is presentation context, not an availability or capacity figure.

### BR-55 — Consistency and refresh

Every read of this section is advisory presentation (BR-26): mutations
re-authorize and re-check lifecycle and revision staleness themselves (BR-43).

Each read observes one snapshot. Different reads taken at different times may
disagree while Appointments change. The Professional client therefore:

- re-reads the visible month counts and the selected day together, on focus
  and after every Appointment mutation it performs;
- after a mutation that may change an Appointment's date or calendar
  membership (confirmation, cancellation, completion, no-show, accepted
  reschedule), re-reads the counts of the month that held the Appointment
  before and, if different, the month it is in after;
- treats the single-Appointment read (BR-52) as authoritative for the detail,
  and never infers a count from a list or a list from a count.

### Common rules of BR-56 to BR-59

Each read below is `SECURITY DEFINER`, `STABLE`, has an empty `search_path`,
and is executable only by `authenticated`. Evaluation order:

1. authentication and a coherent domain User — otherwise `28000`;
2. the acting User currently holds `APPOINTMENT_VIEW_SCHEDULE` for
   `p_clinic_id` — otherwise `42501`
   `Applicable Appointment schedule-view capability is required`, the same
   outcome as BR-54 for a missing, null or foreign Clinic and missing
   authority;
3. input validation — otherwise `22023` with the message given by each read.
   Invalid input never reveals more than step 2.

Rows are BR-51 rows of the requested Clinic only. Each read creates or changes
nothing and is one SQL statement, so one instant and one snapshot decide every
row it returns.

### BR-56 — Calendar Appointments of one day

    get_clinic_appointment_day(
        p_clinic_id uuid,
        p_day date
    ) returns table (… the columns of BR-51 …)

`p_day` must be non-null with a year between 2000 and 2999 — otherwise
`22023` `Calendar day is invalid`.

It returns one row per calendar Appointment (BR-53) whose Clinic-local date is
`p_day`, ordered by `current_scheduled_start_at`, then `id`, without
pagination. It uses the definition shared with BR-54, so in the same snapshot
its row count equals that day's `appointment_count` (absent = 0). The
requester display name stays on each row (BR-49); the email never does
(BR-50).

### BR-57 — Pending: Clinic work classified for the acting User

    get_clinic_appointment_pending(
        p_clinic_id uuid,
        p_after_rank integer default null,
        p_after_start_at timestamptz default null,
        p_after_id uuid default null,
        p_limit integer default 50
    ) returns table (
        … the columns of BR-51 …,
        pending_reason text,
        pending_category text,
        pending_rank integer,
        action_required_count integer,
        awaiting_guardian_count integer,
        informational_count integer
    )

Independent of any month or day, it returns the `REQUESTED` and `CONFIRMED`
Appointments of the Clinic that carry a pending reason **for the acting User**,
evaluated at the read's instant with that User's current Clinic capabilities
(and, where the operation requires it, the Organization's
`APPOINTMENT_MANAGEMENT` Entitlement). It offers no operation and invents no
capability: a reason is given only when the actor could perform its operation
in the Professional client, by the same lifecycle, time, Encounter and proposal
rules the backend enforces and the Appointment detail uses (BR-44, BR-46).

The proposal facts are those of BR-44: only an **actionable** PENDING proposal
counts, and its feasibility is the projection's
`pending_reschedule_currently_feasible`. A non-actionable PENDING proposal is
as if absent.

Each Appointment gets at most one reason — the first that applies:

| Rank | `pending_reason` | `pending_category` | Applies when |
|---|---|---|---|
| 1 | `ATTENDANCE_OUTCOME` | `ACTION_REQUIRED` | `CONFIRMED`, relevant start reached, and the actor holds `APPOINTMENT_COMPLETE`, or — without a Clinical Encounter — `APPOINTMENT_MARK_NO_SHOW` or `APPOINTMENT_CANCEL` |
| 2 | `REQUEST_DECISION` | `ACTION_REQUIRED` | `REQUESTED`, requested start still in the future, no actionable proposal, and the actor can confirm or propose an alternative time (`APPOINTMENT_CONFIRM` or `APPOINTMENT_RESCHEDULE`, with the Entitlement) or cancel (`APPOINTMENT_CANCEL`, without a Clinical Encounter) |
| 3 | `PROPOSAL_NOT_FEASIBLE` | `ACTION_REQUIRED` | an actionable Clinic proposal that is not currently feasible, and the actor holds `APPOINTMENT_RESCHEDULE` (withdrawal needs no Entitlement) |
| 4 | `GUARDIAN_PROPOSAL` | `INFORMATIONAL` | an actionable Guardian proposal, and the actor holds `APPOINTMENT_RESCHEDULE`. The Professional client offers no operation on it yet; it is shown for information only and is not counted as actionable |
| 5 | `AWAITING_GUARDIAN` | `AWAITING_GUARDIAN` | an actionable, currently feasible Clinic proposal awaiting the Guardian, and the actor holds `APPOINTMENT_RESCHEDULE` |

Consequences: a past `REQUESTED` Appointment is never pending (`SPEC-APT-002`
BR-19); a reached `CONFIRMED` Appointment is `ATTENDANCE_OUTCOME` whatever
lapsed proposal it keeps; a Veterinarian with a current Assignment, who can
only complete, sees only `ATTENDANCE_OUTCOME`. Reasons, categories and ranks
are stable identifiers; the client localizes them.

**Order and pages.** Rows are ordered by `pending_rank`, then
`current_scheduled_start_at`, then `id`. The cursor is the complete
`(pending_rank, current_scheduled_start_at, id)` of the last row of the
previous page, or entirely null for the first page; the page holds the next
`p_limit` rows after it. `p_limit` 1–100; a partial cursor or a rank outside
1–5 fails with `22023` `Pending page is invalid`.

**Classification precedes pagination.** Because feasibility, actionability and
the actor's capabilities decide reason, rank, order and page membership, the
read classifies every non-terminal Appointment of the Clinic first, then
applies the cursor and the limit on that order, and only then projects the
BR-51 columns of the page's Appointments. A page therefore never depends on
which rows other pages hold.

A proposal's actionability and feasibility are evaluated only where they can
change this actor's result: actionability when the actor holds
`APPOINTMENT_RESCHEDULE` or could otherwise decide that request, feasibility
only for a Clinic proposal and an actor holding `APPOINTMENT_RESCHEDULE`.
Where they are evaluated, they are evaluated in full, including the
proposer's continuous authority. This changes cost, never the result.

**Totals on every row.** `action_required_count`, `awaiting_guardian_count`
and `informational_count` are the numbers of Appointments per
`pending_category` in the **whole** classification of the same call, before
the cursor and the limit: every row of a call carries the same three values,
whatever the page. They come from the very classification the rows come from,
evaluated once, so rows and totals always agree.

**Empty pages.** A page with no rows carries no totals:

- an empty **first** page (no cursor) means the classification is empty, so
  every total is zero;
- an empty **later** page (after a cursor) only means the end of the list; the
  totals are not zero in general. The client keeps the totals of the previous
  page of the same reading, or reads BR-58 when it needs current totals
  without rows.

**Intended client use.** On opening Pending, the Professional client reads the
first page and takes the totals from its rows (no separate summary call);
further pages continue with the cursor and refresh the totals. A badge or
counter shown outside Pending reads BR-58 instead.

Between pages, Appointments may change. A page continues strictly after its
cursor's key in the order evaluated at its own instant: an Appointment is never
returned twice by pages that observe the same key for it, one that left Pending
is not returned, and one whose key now sorts before the cursor appears only on
a new first read. The client restarts from the first page on focus and after
every mutation it performs (BR-55).

### BR-58 — Pending summary

    get_clinic_appointment_pending_summary(
        p_clinic_id uuid
    ) returns table (
        action_required_count integer,
        awaiting_guardian_count integer,
        informational_count integer
    )

One row with the number of Appointments per `pending_category` of BR-57 for the
same actor, at the read's instant, from the same internal classification
without projecting any row. `action_required_count` is the main Pending figure;
the other two are secondary and never added to it. In one snapshot the counts
equal the rows BR-57 returns across all its pages and the totals each of its
rows carries. It serves reads that need the counts without rows: counters
outside Pending and the totals after an empty later page (BR-57).

### BR-59 — History pages

    get_clinic_appointment_history(
        p_clinic_id uuid,
        p_before_start_at timestamptz default null,
        p_before_id uuid default null,
        p_limit integer default 30
    ) returns table (… the columns of BR-51 …)

Terminal Appointments (`COMPLETED`, `NO_SHOW`, `CANCELLED`, `EXPIRED`) of the
Clinic, newest relevant scheduled start first, then `id` descending. The
cursor is the complete `(current_scheduled_start_at, id)` of the last row of
the previous page, or entirely null for the first page. `p_limit` 1–50; a
partial cursor fails with `22023` `History page is invalid`.

A terminal Appointment's relevant interval never changes, so its key is stable:
pages never repeat or skip an Appointment, ties on the start are resolved by
`id`, and an Appointment that becomes terminal while paging appears where its
key sorts — behind the cursor only on a new first read. The page is chosen on
the key alone and only its Appointments are projected; the read never returns
the whole history, and the client shows that more may exist (BR-38).

### BR-60 — Calendar context: the Clinic's current local date

    get_clinic_calendar_context(
        p_clinic_id uuid
    ) returns table (
        clinic_local_today date,
        scheduling_timezone_name text
    )

It follows the common rules of BR-56 to BR-59 (authentication `28000`, then
`APPOINTMENT_VIEW_SCHEDULE` for `p_clinic_id` or the uniform `42501` of BR-54,
so a missing, null or foreign Clinic is indistinguishable from missing
authority). Nothing about the Clinic is read before authorization succeeds. It
takes no other input.

On success it returns exactly one row:

- `scheduling_timezone_name` is the Clinic's **current** scheduling timezone
  when it is valid — the same validity rule the schedule projection uses for
  feasibility (BR-44) — otherwise `null`;
- `clinic_local_today` is the civil date of the server's statement instant in
  that timezone, otherwise `null`.

Both are `null` together, and only together. No alternative timezone is ever
substituted. The device's timezone and the database session's timezone never
decide `clinic_local_today`.

The Clinic's current timezone is presentation context for the calendar. It
never changes the timezone in which an existing Appointment's interval was
established, nor its Clinic-local date (BR-53, `SPEC-APT-013` BR-48).

The read returns no Appointment, Pet, requester, Veterinarian, clinical,
Subscription or publication information, and creates or changes nothing.

**Intended client use.** The Professional calendar:

- with a `clinic_local_today`, opens that month and selects that day, which it
  presents as "today";
- without it, may open on the device's current month, but presents neither
  that month nor any day as the Clinic's current month or day, and selects no
  day automatically; the actor selects dates manually;
- never presents an Appointment's historical timezone
  (`current_scheduling_timezone_name`) as the Clinic's current timezone; it may
  mark an Appointment whose timezone differs from `scheduling_timezone_name`;
- may read the context again when it regains focus after a long interval, so
  "today" does not go stale; the read is cheap and has no side effects.

### BR-61 — Professional presentation of Entitlement-dependent actions

Presentation only: it adds no backend authority and changes no operation.

**Confirm** (`SPEC-APT-002`, including the confirmation of an accepted
alternative, BR-45), **Propose a new time** (`SPEC-APT-005`) and **Propose
another time** (`SPEC-APT-018`) require the Organization's current
`APPOINTMENT_MANAGEMENT` Entitlement, as do the candidate reads behind the
two proposals (`SPEC-APT-017`, `SPEC-APT-020`). The Professional client
relates the Clinic to its Organization by Organization id (`SPEC-ORG-008`
BR-11) and takes that Organization's availability from the professional
context read (`SPEC-ORG-007` BR-7), read again with the Clinic on every focus
of the Appointment detail and its proposal screens. No responsibility implies
the Entitlement, and another Organization's availability never counts.

The availability is one of:

- **available** — the actions follow their own capability and lifecycle rules;
- **unavailable** — reported as not available: they are not offered;
- **unverified** — the read failed or did not report the Organization: they
  are not offered, the client says the availability could not be checked and
  offers a retry, and it never states that the Organization lacks it.

Only when one of those actions would otherwise be offered does the detail
show one short, neutral note; nothing is said when the capability or the
Appointment's state rules the action out anyway. A proposal screen reached
directly shows the same state instead of its form, reads no candidates, and
leads back to the Appointment.

**Cancel**, **Complete**, **No-show** and **Withdraw** never depend on the
Entitlement (`SPEC-APT-003` BR-19, `SPEC-APT-009` BR-6, `SPEC-APT-010` BR-34,
`SPEC-APT-016`). The Pending classification (BR-57) already applies it and is
unchanged. The backend stays authoritative: a denial after an attempt is
still mapped, and the detail then reads the availability again.

## 15. Professional calendar reads — Phase 1 Verification Notes

In addition to §13, verification must demonstrate that:

62. `get_clinic_appointment` returns exactly one row, equal column for column
    to that Appointment's `get_clinic_appointment_schedule` row, in every
    lifecycle state, with and without a pending proposal of either workflow,
    after revisions, and with a cancellation reason and a Clinical Encounter
    (BR-51, BR-52);
63. it is granted to Owners, Administrators and Receptionists of the Clinic
    (Organization or Clinic scope) and to Veterinarians with a current Clinic
    Assignment there, and fails with one uniform `42501` without hint for
    every other actor, for an unknown Clinic or Appointment, and for an
    Appointment of another Clinic; `28000` without subject or domain User;
    `anon` cannot execute it (BR-52);
64. `get_clinic_appointment_month_counts` counts each calendar Appointment
    once, on its Clinic-local date, for `REQUESTED` (including a past one not
    yet expired), `CONFIRMED`, `COMPLETED` and `NO_SHOW` only (BR-53, BR-54);
65. the date follows the latest Schedule Revision in its own establishment
    timezone, across midnight, daylight-saving transitions, months, and years;
    a pending proposal and earlier revisions never add or move a date; the
    session timezone has no effect (BR-53);
66. empty months, months of 28, 29, 30 and 31 days, and December→January are
    correct; invalid or null year and month fail with `22023` after
    authorization; authority outcomes equal the schedule read's (BR-54);
67. the counts expose no Appointment, Pet, requester, state, identifier, or
    clinical information, and equal, day by day, the calendar Appointments the
    shared definition assigns to each date (BR-53, BR-54);
68. the reads create or change nothing, and `get_clinic_appointment_schedule`
    keeps its signature, result, ordering and grants (BR-51);
69. the day read, Pending, its summary and History follow the common
    evaluation order, uniform `42501` and `22023` messages, and grants; the
    internal classification is not executable by clients;
70. for every date of several months, the day read returns exactly that
    date's `appointment_count` rows, in `(start, id)` order, including midnight
    and session-timezone cases; each row equals `get_clinic_appointment`
    (BR-53, BR-56);
71. every Pending reason is produced, with its category and rank, and the
    precedence holds: a reached `CONFIRMED` with a lapsed proposal is
    `ATTENDANCE_OUTCOME`; a `REQUESTED` with a non-actionable proposal is
    `REQUEST_DECISION`; a past `REQUESTED` and a future `CONFIRMED` without
    proposal are not Pending (BR-57);
72. Owners, Administrators and Receptionists (Organization or Clinic scope)
    receive the full classification; a Veterinarian receives only
    `ATTENDANCE_OUTCOME`; without the Entitlement and without cancellation a
    request is not actionable; actors without schedule view are denied
    (BR-57);
73. a change of feasibility moves an Appointment between `AWAITING_GUARDIAN`
    and `PROPOSAL_NOT_FEASIBLE`, changing its rank, its page, and the counts
    (BR-57, BR-58);
74. pages of every size from 1 to the whole set return the same sequence;
    ties are broken by `id`; Appointments changing between pages are neither
    duplicated nor returned after leaving Pending; a cursor of a vanished
    Appointment and a cursor past the end behave as specified (BR-57);
75. the summary equals the classified rows per category for every actor
    (BR-58);
76. History returns terminal Appointments only, in `(start, id)` descending
    order, identically for every page size; cursors inside ties and at the
    oldest row are correct; Appointments becoming terminal while paging do not
    disturb continuation (BR-59);
77. no read returns another Clinic's Appointment, the requester's email, or
    clinical content beyond BR-48 (BR-51);
78. every Pending row carries the totals of the whole classification of its
    call, identical on every page for every page size and cursor, equal to
    the categories of the rows and to the summary; an empty first page means
    all-zero totals, and an empty later page carries none while the summary
    keeps them (BR-57, BR-58);
79. evaluating proposal facts only where they can change the actor's result
    gives, for every User at every Clinic and across fixture changes
    (feasibility, Entitlement, Encounters, Appointments changing), exactly the
    classification obtained by evaluating them for every candidate (BR-57);
80. `get_clinic_calendar_context` is granted to Owners, Administrators and
    Receptionists of the Clinic (Organization or Clinic scope) and to
    Veterinarians with a current Clinic Assignment there, also for an
    unpublished Clinic, and fails with the uniform `42501` for every other
    actor, another Clinic or Organization, and an unknown or null Clinic;
    `28000` without subject or domain User; `anon` cannot execute it (BR-60);
81. with a valid timezone it returns exactly one row with that timezone and the
    civil date of the statement instant in it, across local midnight in zones
    on either side of UTC and across both daylight-saving transitions,
    independently of the session timezone; with a null or invalid timezone
    both values are `null` (BR-60);
82. it exposes nothing else, creates or changes nothing, and every earlier
    read keeps its signature, result and grants (BR-60);
83. the Professional client offers Confirm, Propose a new time and Propose
    another time only with the Clinic's own Organization's
    `APPOINTMENT_MANAGEMENT` available; unavailable and unverified are told
    apart, an unverified one is retryable, Cancel, Complete, No-show and
    Withdraw are unaffected, and a proposal screen reads no candidates without
    it (BR-61).

# SPEC-MED-001 — Create Clinical Encounter

**Status:** SUPERSEDED by SPEC-MED-010 (2026-10-23; describes the deployed schema until transition stage M2)  
**Requirements:** REQ-MED-001, REQ-MED-002, REQ-MED-013  
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): this Specification becomes `SUPERSEDED` by SPEC-MED-010. Clinical Record Entries belong directly to the Appointment and no Clinical Encounter exists. Clinical Intake (care without an Appointment) remains deferred and will need its own Specification. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Veterinarian to establish a Clinical Encounter representing
veterinary care actually provided to a Pet at a specific Clinic.

A Clinical Encounter represents a real professional care context.

It is distinct from an Appointment.

An Appointment represents planned care.

A Clinical Encounter represents care that actually occurred.

A Clinical Encounter provides the professional and historical context in which
clinical information may subsequently be recorded.

---

## 2. Preconditions

- The Pet exists.
- The Clinic exists.
- The Clinic belongs to a Veterinary Organization.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a Veterinarian Professional Profile.
- The acting Veterinarian has a current valid Clinic Assignment at the Clinic.
- A valid current Pet Care Authorization exists for the Pet, Clinic, and
  applicable care episode.
- The acting Veterinarian's current professional context permits participation
  in the authorized veterinary care.
- The clinical occurrence time is valid.
- If the Encounter is associated with an Appointment:
  - the Appointment belongs to the same Pet;
  - the Appointment belongs to the same Clinic;
  - the applicable Appointment-derived Care Authorization belongs to the same
    care context where relevant;
  - the Appointment is `CONFIRMED`, or `COMPLETED` after having been
    legitimately confirmed, and the clinical occurrence time satisfies BR-34.

---

## 3. Business Rules

### BR-1 — Clinical Encounter represents actual care

A Clinical Encounter represents veterinary care that actually occurred.

It must not be created merely because:

- an Appointment was requested;
- an Appointment was confirmed;
- a Veterinarian was assigned to an Appointment;
- a Clinic exists;
- a Pet is registered.

Planned care and actual care are separate domain concepts.

---

### BR-2 — Every Clinical Encounter concerns exactly one Pet

A Clinical Encounter must identify exactly one Pet.

A single Encounter must not represent clinical care for multiple Pets.

The Pet remains the central identity around which longitudinal medical history
is organized.

---

### BR-3 — Every Clinical Encounter occurs at exactly one Clinic

A Clinical Encounter must identify the Clinic at which the veterinary care was
provided.

The Encounter must not belong only to a Veterinary Organization without
identifying the applicable physical Clinic.

---

### BR-4 — Organization provenance is derived from the Clinic context

The Clinical Encounter must preserve the Veterinary Organization context under
which the Clinic operated when the care occurred.

Clinical provenance must therefore be capable of identifying:

- the Pet;
- the Clinic;
- the Veterinary Organization;
- the responsible Veterinarian;
- the time of care.

---

### BR-5 — Clinical Encounter requires a Veterinarian professional context

The acting User must have a Veterinarian Professional Profile.

A User must not create a Clinical Encounter merely because they are:

- an Organization Owner;
- an Organization Administrator;
- a Receptionist;
- a Pet Guardian;
- another Organization Member.

---

### BR-6 — Current Clinic Assignment is required

The acting Veterinarian must have a current valid Clinic Assignment at the
Clinic where the Encounter occurs.

A historical ended Clinic Assignment is insufficient for creating new clinical
care.

An Assignment at another Clinic is also insufficient.

The responsible Clinic Assignment must also have begun on or before the
Encounter's clinical occurrence time (`started_at`). A Veterinarian must not
establish an Encounter for care that started before their current Clinic
Assignment at that Clinic began.

Together these mean the same Clinic Assignment must cover the whole period from
the start of care to the establishment of the Encounter. Phase 1 does not
reconstruct historical professional authority: a Veterinarian whose Clinic
Assignment ended after the care, or who has since received a new Clinic
Assignment at the same Clinic, cannot establish the Encounter for that care.

---

### BR-7 — Phase 1 does not require platform credential verification

Phase 1 follows the professional-verification model already established for
Clinic and Appointment Assignment.

A Veterinarian may establish a Clinical Encounter when the applicable Phase 1
professional requirements are satisfied even if platform credential
verification has not yet been completed.

The Encounter must not be represented as proof that professional credentials
were platform-verified.

If a later approved Specification requires verified professional status for
clinical authorship, that requirement must be enforced independently.

---

### BR-8 — Clinic Assignment alone does not authorize arbitrary Pet care

A Veterinarian's Clinic Assignment establishes where they may practice.

It does not automatically authorize them to create Clinical Encounters for
arbitrary Pets.

The Pet must be part of a valid professional care context.

The exact medical-access authorization rules are defined separately.

---

### BR-9 — Clinical Encounter may originate from an Appointment

A Clinical Encounter may be associated with an existing Appointment.

When associated:

- the Appointment must concern the same Pet;
- the Appointment must belong to the same Clinic;
- the Appointment must be `CONFIRMED`, or `COMPLETED` after having been
  legitimately confirmed (BR-34);
- the Encounter must not change Appointment identity or lifecycle state
  (BR-36).

The Appointment remains scheduling history.

The Encounter represents the resulting clinical care.

---

### BR-10 — Appointment is not mandatory for Clinical Encounter

A valid Clinical Encounter must be possible without a pre-existing Appointment
when the applicable professional care workflow permits it.

This supports real-world situations such as:

- emergency care;
- walk-in care;
- internally registered visits;
- other future authorized care workflows.

The absence of an Appointment must not require creating a fake Appointment
solely to satisfy the clinical data model.

---

### BR-11 — Appointment and Clinical Encounter remain distinct

Creating a Clinical Encounter must not rewrite an Appointment as though both
concepts were the same entity.

For example:

    Appointment
    Scheduled: 10:00

may be associated with:

    Clinical Encounter
    Care actually began: 10:18

Both facts may be historically meaningful.

---

### BR-12 — Clinical occurrence time must represent actual care context

The Encounter must preserve when the veterinary care occurred.

The clinical occurrence time is distinct from:

- the time an Appointment was requested;
- the time an Appointment was confirmed;
- the time the Encounter record was technically created.

These timestamps must not be silently treated as interchangeable.

---

### BR-13 — Clinical provenance must preserve the responsible Veterinarian

The Clinical Encounter must identify the Veterinarian responsible for the
professional care context.

That professional identity must remain historically attributable even if the
Veterinarian later:

- leaves the Clinic;
- leaves the Organization;
- changes Organizations;
- changes professional information.

---

### BR-14 — Historical Clinic provenance must remain stable

If a Veterinarian later leaves the Clinic, the Encounter must remain attributed
to the Clinic where the care originally occurred.

Current employment state must not rewrite historical care provenance.

---

### BR-15 — Historical Organization provenance must remain stable

If a Veterinarian later leaves the Veterinary Organization, the Encounter must
remain attributed to the Organization under whose professional context the
care occurred.

Historical clinical provenance must not follow the Veterinarian to a later
employer.

---

### BR-16 — Clinic profile changes do not rewrite Encounter provenance

Changing the Clinic's:

- public display name;
- public profile;
- current location;
- publication state

must not change which Clinic provided the historical care.

The Encounter continues to reference the same Clinic domain identity.

---

### BR-17 — Pet profile changes do not rewrite Encounter identity

Changing the Pet's name, profile image, or other mutable profile information
must not change which Pet the Encounter concerns.

The Encounter references the Pet domain identity.

---

### BR-18 — Clinical Encounter creation does not create Pet Guardianship

Creating a Clinical Encounter must not:

- create a Guardian;
- remove a Guardian;
- modify existing Guardianship relationships.

Professional care and personal Guardianship remain separate concepts.

---

### BR-19 — Clinical Encounter creation does not itself create clinical statements

Creating the Encounter establishes the context for veterinary care.

It must not automatically create:

- a diagnosis;
- a Treatment;
- a vaccination;
- a prescription;
- a procedure;
- a finalized clinical note.

Those clinical statements require their applicable Medical Record workflows.

---

### BR-20 — Clinical Encounter is not itself a diagnosis

The existence of an Encounter proves that a professional care context existed.

It must not imply any specific diagnosis, finding, treatment, or clinical
conclusion.

---

### BR-21 — Clinical Encounter belongs to the Pet's longitudinal history

The Encounter must be associated with the Pet independently from the Pet's
current care provider.

A Pet's medical history must be able to include Encounters from different:

- Veterinary Organizations;
- Clinics;
- Veterinarians.

For example:

    Luna
    ├── 2026 — Animalia Madrid Centro
    ├── 2027 — VetCare Toledo
    └── 2028 — Animalia Getafe

These Encounters belong to Luna's longitudinal medical history.

---

### BR-22 — Encounter provenance must distinguish providers

When a Pet receives care at several veterinary providers, each Encounter must
preserve the Clinic and Organization responsible for that specific care.

The system must not flatten all clinical history into an unattributed global
timeline.

---

### BR-23 — Encounter creation must preserve who created it

The system must preserve enough information to establish:

- the Pet;
- the Clinic;
- the Veterinary Organization context;
- the responsible Veterinarian;
- the acting User;
- when the Encounter occurred;
- when the Encounter record was created;
- the associated Appointment where applicable.

---

### BR-24 — Clinical occurrence time cannot be silently inferred from Appointment time

If an Encounter is linked to an Appointment, the Appointment's scheduled time
must not automatically become the actual clinical occurrence time without an
explicit applicable rule.

Scheduled time and actual care time may differ.

---

### BR-25 — Future clinical care must not be represented as already occurred

A Clinical Encounter must not represent care that has not yet taken place.

Planned future care belongs to Appointment or Treatment-planning workflows.

---

### BR-26 — Encounter creation is atomic

A successfully created Clinical Encounter must establish one coherent
professional care context containing all required provenance.

The system must not expose a valid Encounter missing its:

- Pet;
- Clinic;
- Organization context;
- responsible Veterinarian;
- clinical occurrence context.

---

### BR-27 — Phase 1 Clinical Encounter requires a current Care Authorization

In the normal Phase 1 care workflow, a Clinical Encounter may be established
only when a valid current Pet Care Authorization exists for the Pet and Clinic.

The Care Authorization must apply to the care episode represented by the
Encounter.

The existence of an Appointment, Clinic Assignment, or Veterinarian
Professional Profile alone is insufficient.

---

### BR-28 — Care Authorization and professional authority are both required

Pet Care Authorization establishes the Pet-specific care basis.

The acting Veterinarian must independently satisfy the applicable professional
requirements for the Clinic.

Conceptually:

valid Pet Care Authorization
          +
current Veterinarian Clinic context
          ↓
authorized professional care context

Neither side of this relationship is sufficient by itself.

---

### BR-29 — Care Authorization may originate from Appointment or intake

A Clinical Encounter may use a Care Authorization established:

through the Guardian-facing Appointment workflow; or
through another authorized intake workflow when care occurs without a prior
Appointment.

A Clinical Encounter without an Appointment must not require fabrication of a
fake Appointment.

It still requires a valid medical-access basis.

---

### BR-30 — Revoked authorization cannot establish a new Clinical Encounter

A Care Authorization revoked before veterinary care begins must not be used to
establish a new Clinical Encounter.

Appointment existence or professional Clinic authority must not bypass the
revocation.

A new current valid authorization basis is required before normal care may
begin.

---

### BR-31 — Revocation after Encounter begins does not erase the Encounter

If a Care Authorization is revoked after a valid Clinical Encounter has
already begun, the Encounter must remain valid and historically identifiable.

Any limited continuing access required to safely conclude and document the
already-started care is governed by SPEC-ACC-002.

Revocation must not:

delete the Encounter;
rewrite its provenance;
retroactively invalidate care that validly began while authorization was
active.

---

### BR-32 — Clinical Encounter preserves its authorization basis

The system must be capable of establishing the medical-access basis under
which the Clinical Encounter was validly created.

For the normal Phase 1 workflow, this includes the applicable Pet Care
Authorization.

The authorization relationship must remain historically traceable even after
the authorization later ends or is revoked.

Historical traceability must not imply that the authorization continues to
grant current access.

---

### BR-33 — Cross-clinic history remains subject to least privilege

A valid Care Authorization may allow relevant longitudinal medical information
from other participating Clinics to be used in the care context.

The Clinical Encounter must not turn that authorization into unrestricted
access.

The acting professional may only access medical information permitted by the
applicable current care purpose and least-privilege rules.

---

### BR-34 — An Appointment-backed Clinical Encounter requires a confirmed or completed Appointment

Clinical documentation is optional. A Clinic may resolve its Appointments
without ever establishing a Clinical Encounter (`SPEC-APT-009`). When a Clinic
does choose to document an Appointment's care, the Appointment-backed Encounter
may be established either while the Appointment is `CONFIRMED` or after it has
become `COMPLETED`, so that clinical tooling remains adoptable even after
reception has resolved the Appointment.

An Appointment-backed Clinical Encounter may be established only when, at
establishment, all of the following hold:

1. the acting User is a Veterinarian with a current Clinic Assignment at the
   Appointment's Clinic (BR-5, BR-6);
2. the acting User holds the `CLINICAL_CARE` capability at that Clinic
   (`SPEC-ORG-005`);
3. the Organization currently holds the `CLINICAL_CARE` Entitlement
   (`SPEC-SUB-003`);
4. the Care Authorization is `ACTIVE`, has the `APPOINTMENT_CARE` purpose, is
   the Appointment's Appointment-derived Care Authorization, and matches the
   Appointment's Pet, Clinic, and Veterinary Organization (BR-27, BR-28);
5. no Clinical Encounter already exists for that Care Authorization, and
   therefore none for that Appointment;
6. the Appointment is `CONFIRMED`, or `COMPLETED`;
7. the Appointment has exactly one confirmation Lifecycle Event
   (`REQUESTED → CONFIRMED`), which is what makes a `COMPLETED` Appointment
   one that was legitimately confirmed;
8. `started_at` is at or after that confirmation event's effective time;
9. `started_at` is not in the future (BR-25);
10. if the Appointment is `COMPLETED`, `started_at` is at or before the
    effective time of its completion Lifecycle Event;
11. the responsible Clinic Assignment began on or before `started_at` (BR-6);
12. `started_at` is not earlier than the Care Authorization's grant.

A `REQUESTED`, `CANCELLED`, `NO_SHOW`, or `EXPIRED` Appointment can never back
a Clinical Encounter.

The rule bounds when care occurred, not when it is documented:

- the Encounter's creation time may be after the Appointment's completion; the
  delay is in documentation time, not care time;
- care must not be represented as having started after the Clinic declared the
  Appointment completed;
- care must not be represented as having started before the Clinic confirmed
  the Appointment.

Phase 1 imposes no fixed documentation window after completion. The bounds
above, together with a current Veterinarian authority, a current `CLINICAL_CARE`
Entitlement, a single Encounter per Care Authorization, and a Care Authorization
that is still `ACTIVE` and revocable by a Guardian (`SPEC-ACC-001` BR-42,
`SPEC-ACC-002` BR-55), are sufficient to prevent arbitrary retrospective
Encounters.

The establishment operation keeps its existing contract; only the accepted
Appointment states and the temporal and Clinic Assignment bounds above apply.

Clinical care that begins before or without Appointment confirmation — for
example walk-in or urgent care, or a Pet that arrives for a request the Clinic
has not confirmed — uses the independent Clinical Intake path: a Clinical Intake
Care Authorization and an Encounter that references no Appointment (BR-10,
BR-29). Any pending request continues its own Appointment lifecycle
independently.

---

### BR-35 — The Encounter is the source of truth for its Appointment relationship

The relationship between an Appointment and the clinical care that documents
it is established by the Clinical Encounter itself:

- the Encounter's reference to the Appointment; and
- the Encounter's reference to the Appointment-derived Care Authorization.

Appointment completion does not reference, consume, or validate the Encounter
(`SPEC-APT-009` BR-15). New Appointment Lifecycle Events carry no Encounter
reference.

Historical `COMPLETED` Lifecycle Events established before this rule may
reference an Encounter. That reference is legacy provenance only. It remains
valid and must stay consistent with the Encounter's own references, but it is
not the source of truth and is not required for any new completion.

Whichever order the Encounter and the completion occur in, every
Appointment-backed Encounter of a `COMPLETED` Appointment must have a care
start at or before that completion.

---

### BR-36 — Encounter establishment never changes the Appointment lifecycle

Establishing an Appointment-backed Clinical Encounter must not:

- confirm, complete, cancel, or otherwise transition the Appointment;
- change the Appointment's scheduling information or Veterinarian Assignment;
- change the completion time or completing User of a `COMPLETED` Appointment.

Establishing an Encounter on a `CONFIRMED` Appointment makes any pending
Reschedule Proposal `VOID` (`SPEC-APT-005` BR-33) and blocks later cancellation,
`NO_SHOW`, and rescheduling of that Appointment (`SPEC-APT-003`,
`SPEC-APT-005` BR-29, `SPEC-APT-010` BR-5). It does not block completion
(`SPEC-APT-009` BR-12).

Concluding the Encounter remains a separate operation (`SPEC-MED-008`) and
does not complete the Appointment.

---

## 4. Clinical Encounter Information

The domain must support enough information to establish the clinical and
historical context of the care.

### Required

- Pet;
- Clinic;
- Veterinary Organization context;
- responsible Veterinarian;
- clinical occurrence time;
- Encounter creation time;
- applicable medical-access basis.

For the normal Phase 1 workflow, the medical-access basis is the applicable
Pet Care Authorization.

### Optional

- associated Appointment;
- Guardian-provided contextual information where applicable;
- internal Encounter reference or operational information where later required.

The Encounter must not require clinical conclusions merely in order to exist.

---

## 5. Scenarios

### Scenario: Create Clinical Encounter from confirmed Appointment

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro  
And Dr. Garcia is the current assigned Veterinarian  
And Dr. Garcia has a valid current Clinic Assignment at Animalia Madrid Centro  
And the applicable Pet Care Authorization for Luna is active

When Dr. Garcia begins the valid Clinical Encounter

Then a Clinical Encounter is created for Luna  
And the Encounter identifies Animalia Madrid Centro  
And the Encounter identifies Animalia Veterinary Group  
And the Encounter identifies Dr. Garcia as the responsible Veterinarian  
And the Encounter may reference the existing Appointment  
And the applicable Care Authorization remains historically traceable as the medical-access basis  
And no diagnosis or Treatment is created solely because the Encounter exists

---

### Scenario: Requested Appointment cannot back a Clinical Encounter

Given Luna has a `REQUESTED` Appointment at Animalia Madrid Centro
And the Clinic has not confirmed it
And the Appointment's Care Authorization is active

When Dr. Garcia attempts to begin a Clinical Encounter referencing that
Appointment

Then the Encounter is not created
And if Luna is receiving care now, the Clinical Intake path is used instead,
with an Encounter that references no Appointment

---

### Scenario: Veterinarian documents a visit after reception completed it

Given Luna's Appointment at Animalia Madrid Centro was confirmed at 09:00 the
day before and was scheduled for 10:00
And Carlos, a Receptionist, completed it at 11:00
And no Clinical Encounter exists
And the Appointment-derived Care Authorization is still `ACTIVE`
And Dr. Garcia's current Clinic Assignment at the Clinic began before 10:00
And Animalia holds the `CLINICAL_CARE` Entitlement

When Dr. Garcia establishes the Encounter at 18:00 with care start 10:07

Then the Encounter is created referencing the Appointment and its Care
Authorization
And its creation time is 18:00 and its care start is 10:07
And the Appointment remains `COMPLETED` with Carlos's completion unchanged

---

### Scenario: Care start after completion is rejected

Given Luna's Appointment was completed at 11:00

When Dr. Garcia attempts to establish its Encounter with care start 12:00

Then the Encounter is not created

---

### Scenario: Care start before confirmation is rejected

Given Luna's Appointment was confirmed at 09:00

When Dr. Garcia attempts to establish its Encounter with care start 08:30,
whether the Appointment is `CONFIRMED` or `COMPLETED`

Then the Encounter is not created

---

### Scenario: Future care start is rejected

When Dr. Garcia attempts to establish an Appointment-backed Encounter whose
care start is in the future

Then the Encounter is not created

---

### Scenario: No-show, cancelled, or expired Appointment cannot back an Encounter

Given Luna's Appointment is `NO_SHOW`, `CANCELLED`, or `EXPIRED`

When Dr. Garcia attempts to establish an Encounter referencing it

Then the Encounter is not created

---

### Scenario: Second Encounter for the same Appointment is rejected

Given an Encounter already exists for Luna's Appointment

When another Encounter referencing the same Appointment and Care Authorization
is attempted, whether the Appointment is `CONFIRMED` or `COMPLETED`

Then the Encounter is not created

---

### Scenario: Guardian revocation blocks retrospective documentation

Given Luna's Appointment is `COMPLETED` with no Encounter
And Maria, a current Guardian, revoked its Care Authorization

When Dr. Garcia attempts to establish the Encounter for that visit

Then the Encounter is not created

---

### Scenario: Veterinarian who left the Clinic cannot document retrospectively

Given Dr. Lopez treated Luna at 10:00 under her Clinic Assignment
And reception completed the Appointment at 11:00
And Dr. Lopez's Clinic Assignment ended at 15:00

When Dr. Lopez attempts to establish the Encounter the next day

Then the Encounter is not created

---

### Scenario: Clinic Assignment that began after care is insufficient

Given Luna's Appointment was completed at 11:00 for care at 10:00
And Dr. Ruiz's current Clinic Assignment at the Clinic began at 14:00

When Dr. Ruiz attempts to establish the Encounter with care start 10:05

Then the Encounter is not created

---

### Scenario: Documentation continues after retrospective establishment

Given Dr. Garcia established the Encounter for Luna's `COMPLETED` Appointment

When Dr. Garcia creates and finalizes Clinical Record Entries and later
concludes the Encounter under the applicable Medical Records Specifications

Then those operations follow their own rules unchanged
And the Appointment remains `COMPLETED`

---

### Scenario: Create Clinical Encounter without Appointment

Given Luna requires veterinary care at Animalia Madrid Centro  
And no Appointment exists  
And Maria has an active Guardianship relationship with Luna  
And Maria grants the required Care Authorization through the applicable intake workflow  
And Dr. Garcia has a valid current Clinic Assignment at Animalia Madrid Centro

When Dr. Garcia establishes the Clinical Encounter

Then a Clinical Encounter may be created  
And no fake Appointment is required  
And the Encounter remains associated with Luna and Animalia Madrid Centro  
And the Care Authorization provides the Pet-specific medical-access basis

---

### Scenario: Organization Administrator cannot create Encounter without veterinary context

Given Carlos is an Administrator of Animalia Veterinary Group  
And Carlos does not have a Veterinarian Professional Profile

When Carlos attempts to create a Clinical Encounter for Luna

Then the operation is denied  
And no Clinical Encounter is created

---

### Scenario: Veterinarian assigned to another Clinic cannot create Encounter here

Given Dr. Garcia has a current Clinic Assignment at Animalia Getafe  
And Dr. Garcia has no current Clinic Assignment at Animalia Madrid Centro

When Dr. Garcia attempts to create a Clinical Encounter at Animalia Madrid Centro

Then the operation is denied  
And the Getafe Assignment is insufficient

---

### Scenario: Historical Clinic Assignment is insufficient

Given Dr. Garcia previously practiced at Animalia Madrid Centro  
And her Clinic Assignment there has ended

When Dr. Garcia attempts to create a new Clinical Encounter at Animalia Madrid Centro through the ended Assignment

Then the operation is denied  
And the historical Assignment does not grant current professional authority

---

### Scenario: Clinic professional without Care Authorization cannot create Encounter

Given Dr. Garcia has a current Clinic Assignment at Animalia Madrid Centro  
And Dr. Garcia has a Veterinarian Professional Profile  
And no valid Care Authorization or other applicable medical-access basis exists for Luna

When Dr. Garcia attempts to create a Clinical Encounter for Luna

Then the operation is denied  
And professional Clinic authority alone is insufficient

---

### Scenario: Revoked Care Authorization prevents Encounter creation

Given Luna has an Appointment at Animalia Madrid Centro  
And the related Care Authorization has been revoked  
And no Clinical Encounter has begun  
And no other valid medical-access basis exists

When Dr. Garcia attempts to establish a Clinical Encounter

Then the operation is denied  
And the Appointment does not itself provide medical authorization  
And Dr. Garcia's professional status does not bypass the revoked authorization

---

### Scenario: Authorization is revoked after care begins

Given Luna has a valid Clinical Encounter already underway  
And the Encounter began while its Care Authorization was active

When Maria revokes the Care Authorization

Then the existing Clinical Encounter remains valid  
And its historical provenance remains unchanged  
And the authorization no longer grants unrestricted current access  
And any limited continuity required to safely conclude the Encounter follows `SPEC-ACC-002`

---

### Scenario: Encounter preserves Pet identity

Given Luna has a valid Clinical Encounter  
And Luna's profile name later changes

When the historical Encounter is viewed

Then it remains associated with the same Pet domain entity  
And the profile change does not create another Pet or another Encounter

---

### Scenario: Encounter preserves Clinic after Clinic profile changes

Given Luna received care at Animalia Madrid Centro  
And a Clinical Encounter was created there  
And the Clinic later changes its public display name

When Luna's medical history is viewed

Then the Encounter remains attributed to the same Clinic domain entity  
And historical provenance is not reassigned to another Clinic

---

### Scenario: Veterinarian leaves Clinic after Encounter

Given Dr. Garcia validly provided care to Luna at Animalia Madrid Centro  
And the Clinical Encounter identifies Dr. Garcia as responsible Veterinarian  
And Dr. Garcia later ends her Clinic Assignment

When Luna's historical medical information is viewed

Then the Encounter remains attributed to Dr. Garcia  
And the Encounter remains attributed to Animalia Madrid Centro  
And Dr. Garcia's departure does not rewrite historical provenance

---

### Scenario: Veterinarian joins another Organization later

Given Dr. Garcia provided care to Luna while working for Animalia Veterinary Group  
And the Encounter preserves that Organization context  
And Dr. Garcia later joins VetCare Group

When Luna's historical Encounter is viewed

Then the Encounter remains attributed to Animalia Veterinary Group  
And it is not re-attributed to VetCare Group

---

### Scenario: Encounter linked to wrong Pet Appointment is rejected

Given an Appointment belongs to Toby  
And Dr. Garcia attempts to create a Clinical Encounter for Luna using that Appointment

When the Encounter is created

Then the operation is rejected  
And no incorrect Appointment-to-Pet association is established

---

### Scenario: Encounter linked to wrong Clinic Appointment is rejected

Given Luna has an Appointment at Animalia Getafe  
And Dr. Garcia attempts to create a Clinical Encounter at Animalia Madrid Centro using that Appointment

When the Encounter is created

Then the operation is rejected  
And Appointment and Encounter Clinic contexts remain consistent

---

### Scenario: Appointment scheduled time differs from actual care time

Given Luna has an Appointment scheduled for 10:00  
And the actual veterinary care begins at 10:18

When the Clinical Encounter is created

Then the Encounter may preserve 10:18 as the actual clinical occurrence time  
And the Appointment remains historically scheduled for 10:00  
And the two timestamps remain distinguishable

---

### Scenario: Encounter does not create clinical statements automatically

Given Dr. Garcia validly creates a Clinical Encounter for Luna

When the Encounter is established

Then no diagnosis is inferred  
And no Treatment is inferred  
And no vaccination is inferred  
And no prescription is created  
And no finalized clinical record is created solely because the Encounter exists

---

### Scenario: Different providers contribute to the same Pet history

Given Luna has a Clinical Encounter at Animalia Madrid Centro  
And Luna later has another valid Clinical Encounter at VetCare Toledo

When Luna's longitudinal medical history is evaluated

Then both Encounters belong to Luna  
And each Encounter preserves its own Clinic provenance  
And each Encounter preserves its own Veterinary Organization provenance  
And the two care contexts are not merged into one provider identity

---

## 6. Relationship to Appointment

Appointment and Clinical Encounter answer different questions.

    Appointment
    "What care was planned?"

    Clinical Encounter
    "What professional care actually occurred?"

An Appointment may exist without a Clinical Encounter when:

- the Appointment is cancelled;
- the Pet does not attend;
- care never occurs;
- care occurred but the Clinic does not use clinical documentation;
- the Appointment was completed and the visit has not (yet) been documented.

A `COMPLETED` Appointment therefore does not imply that a Clinical Encounter
exists.

A Clinical Encounter may exist without an Appointment when authorized care
occurs outside the normal scheduling workflow.

When an Encounter does reference an Appointment, that Appointment is
`CONFIRMED` or `COMPLETED` after a legitimate confirmation (BR-34); an
unconfirmed, cancelled, no-show, or expired Appointment never carries
Appointment-backed clinical care.

The Appointment lifecycle and the clinical-documentation lifecycle are
independent. Each of the following is valid:

    CONFIRMED → COMPLETED
    (no Encounter)

    CONFIRMED → Encounter established → COMPLETED

    CONFIRMED → COMPLETED → Encounter established later
    for the care that already occurred

In the last path the Encounter's care start must not be after the completion
(BR-34).

The domain must therefore not model these concepts as a mandatory one-to-one
identity relationship.

---

## 7. Relationship to Care Authorization

A Clinical Encounter requires both a Pet-specific medical-access basis and a
valid professional Clinic context.

Conceptually:

    valid Pet Care Authorization
              +
    current Veterinarian Clinic context
              ↓
    authorized professional care context
              ↓
    Clinical Encounter

The Care Authorization may originate from:

- an Appointment-derived care workflow;
- an authorized intake workflow where no Appointment exists.

The Clinical Encounter must preserve enough information to establish the
medical-access basis under which the care validly began.

If that authorization later ends or is revoked, its historical relationship to
the Encounter remains traceable.

Historical traceability does not imply continued current medical access.

---

## 8. Clinical Provenance

Every Clinical Encounter must preserve sufficient provenance to establish the
professional context in which care occurred.

Conceptually:

    Pet:
    Luna

    Encounter:
    2026-09-10 10:18

    Clinic:
    Animalia Madrid Centro

    Organization:
    Animalia Veterinary Group

    Responsible Veterinarian:
    Dr. Garcia

    Medical-access basis:
    Care Authorization A

    Appointment:
    optional reference

This provenance must remain historically meaningful even when current
relationships later change.

Cross-clinic medical access must not alter the provenance of information
created by another provider.

---

## 9. Longitudinal Pet History

Clinical Encounter history follows the Pet.

It does not belong exclusively to:

- the current Guardian;
- the current Veterinarian;
- the current Clinic;
- the current Veterinary Organization.

Conceptually:

    Luna
      │
      ├── Encounter A
      │     Animalia Madrid Centro
      │     Dr. Garcia
      │
      ├── Encounter B
      │     VetCare Toledo
      │     Dr. Lopez
      │
      └── Encounter C
            Animalia Getafe
            Dr. Ruiz

This structure allows the Pet's history to span multiple providers while
preserving who did what and where.

Access to that longitudinal history remains subject to the applicable current
Care Authorization and least-privilege rules.

---

## 10. Edge Cases

### Appointment exists but Pet never attends

The existence of an Appointment must not force creation of a Clinical
Encounter.

No-show and cancelled Appointments may exist without clinical care.

---

### Appointment completed before documentation

Reception may complete an Appointment before any Veterinarian documents the
visit. The Encounter may still be established afterwards under BR-34. Its
creation time records when the documentation began; its care start records
when the care began and must lie between the confirmation and the completion.

If reception completed the Appointment before care actually began, care
starting after the completion cannot be documented as Appointment-backed care
for that Appointment.

---

### Veterinarian leaves the Clinic before documenting

Phase 1 requires a current Clinic Assignment that already covered the care
start (BR-6). A Veterinarian whose Clinic Assignment ended between the visit
and the documentation cannot establish the Encounter. Another Veterinarian whose
current Clinic Assignment covered the care start may establish it and becomes
the responsible Veterinarian attesting the care.

Reconstructing historical professional authority is out of scope.

---

### Entitlement lapses before documenting

Establishing an Encounter is a new paid professional activity that requires the
current `CLINICAL_CARE` Entitlement, including for a `COMPLETED` Appointment.
Entitlement held at the time of the visit is not sufficient.

---

### Emergency care without prior scheduling

Authorized emergency or walk-in care must not require fabrication of an
earlier Appointment.

The Clinical Encounter itself provides the actual care context.

Normal Phase 1 care still requires an applicable medical-access basis.

Emergency access without normal Guardian authorization is outside Phase 1 and
is governed by future behavior under `REQ-ACC-008`.

---

### Care Authorization is revoked before Encounter begins

A revoked Care Authorization must not establish a new Clinical Encounter.

Another current valid medical-access basis is required before normal care may
begin.

---

### Care Authorization is revoked after Encounter begins

Revocation does not erase or retroactively invalidate an Encounter that
validly began while authorization was active.

Any access continuing after revocation must follow the limited active-care
continuity rules defined by `SPEC-ACC-002`.

---

### More than one Veterinarian participates in care

Phase 1 identifies one responsible Veterinarian for the Encounter.

Additional participating professionals may require dedicated clinical
authorship or participation relationships later.

The model must not assume that the responsible Veterinarian is necessarily the
only professional who can ever contribute clinical information.

---

### Responsible Veterinarian changes during care

Changing professional responsibility after care has begun has clinical
provenance implications.

Clinical handoff behavior must be explicitly specified if required.

Historical authorship must never be silently rewritten.

---

### Clinic closes later

Permanent Clinic closure must not remove historical Clinical Encounters.

The Clinic may cease current operation while remaining historically
identifiable as a provider of past care.

---

### Organization subscription ends

Subscription termination must not delete or rewrite Clinical Encounters.

Medical history and clinical provenance must survive commercial relationship
changes.

---

### Cross-clinic information is used during Encounter

A valid Care Authorization may allow relevant medical history from another
participating provider to be consulted.

The accessing Clinic must not:

- become the author of that historical information;
- rewrite the original provider provenance;
- gain unrestricted access beyond the authorized care purpose.

---

## 11. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**

---

## 12. Dependencies

- SPEC-ID-003 — Authenticate User
- SPEC-PET-001 — Register Pet
- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization

Where an Appointment exists, the Encounter may also relate to:

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment (an Appointment-backed Encounter requires a
  legitimately confirmed Appointment, BR-34)
- SPEC-APT-007 — Assign Veterinarian to Appointment
- SPEC-APT-008 — Reassign Veterinarian
- SPEC-APT-009 — Complete Appointment (completion neither requires nor prevents
  an Encounter; it bounds the care start of a later Encounter, BR-34)

Professional authorization and Entitlement:

- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-SUB-003 — Evaluate Professional Entitlements

Appointment existence is not mandatory for all Clinical Encounters.

---

## 13. Out of Scope

This Specification does not define:

- Clinical Record Entry creation;
- diagnosis creation;
- Treatment creation;
- vaccination recording;
- procedure recording;
- prescription creation;
- clinical-note finalization;
- clinical-record corrections;
- clinical attachments;
- detailed actor-level medical-data scopes;
- Guardian medical-history visibility;
- multi-professional clinical authorship;
- clinical-care handoff;
- professional credential verification requirements for future phases;
- Appointment completion;
- Clinical Encounter completion;
- Clinic closure;
- emergency medical-access behavior;
- a fixed documentation window after Appointment completion;
- establishment by a Veterinarian whose Clinic Assignment has since ended
  (historical professional authority);
- clinical report requirements for Appointment completion.

---

## 14. Verification Notes

Verification must demonstrate that:

1. a Clinical Encounter represents actual care rather than planned care;
2. every Encounter concerns exactly one Pet;
3. every Encounter identifies exactly one Clinic;
4. Veterinary Organization provenance is preserved;
5. a Veterinarian Professional Profile and current Clinic Assignment are required;
6. historical or other-Clinic Assignments are insufficient;
7. the normal Phase 1 Clinical Encounter requires a valid current Pet Care Authorization;
8. Appointment existence alone does not provide medical authorization;
9. professional Clinic authority alone does not provide Pet-specific medical authorization;
10. Care Authorization and professional Clinic context are both required;
11. an Encounter may reference a compatible Appointment;
12. an Appointment is not mandatory for every Encounter;
13. care without a prior Appointment may use an authorized intake Care Authorization;
14. linked Appointment, Pet, and Clinic contexts must be consistent;
15. actual care time remains distinguishable from Appointment scheduling time;
16. creating an Encounter does not automatically create diagnosis, Treatment,
    vaccination, prescription, or other clinical statements;
17. a revoked authorization cannot establish a new Clinical Encounter;
18. revocation after valid care begins does not erase or retroactively
    invalidate the Encounter;
19. the medical-access basis used by the Encounter remains historically
    traceable;
20. historical Veterinarian, Clinic, and Organization provenance survives later
    employment changes;
21. Clinic profile or location changes do not rewrite historical provenance;
22. the Pet's longitudinal history may contain Encounters from multiple Clinics
    and Organizations;
23. cross-clinic access remains subject to least privilege and preserves
    original clinical provenance;
24. subscription termination does not erase Clinical Encounters;
25. Encounter creation behaves atomically;
26. an Encounter referencing a `REQUESTED` Appointment is rejected and creates
    nothing;
27. an Encounter referencing a `CONFIRMED` Appointment succeeds where every other
    requirement holds, and cannot begin before the Appointment's confirmation;
28. a Clinical Intake authorization supports an Encounter without an Appointment
    independently of any pending request for the same Pet and Clinic.

Post-completion establishment (BR-34 to BR-36):

29. an Encounter referencing a `COMPLETED` Appointment succeeds where every
    other requirement holds, with a creation time after the completion and a
    care start between the confirmation and the completion;
30. a care start before the confirmation event is rejected for both `CONFIRMED`
    and `COMPLETED` Appointments;
31. for a `COMPLETED` Appointment, a care start after the completion event's
    effective time is rejected, and a care start exactly at it succeeds;
32. a future care start is rejected;
33. `CANCELLED`, `NO_SHOW`, and `EXPIRED` Appointments are rejected, like
    `REQUESTED`;
34. a second Encounter for the same Care Authorization or Appointment is
    rejected for both `CONFIRMED` and `COMPLETED` Appointments;
35. a current Clinic Assignment at the Clinic is required, and a Veterinarian
    whose Clinic Assignment ended after the care is rejected;
36. a Clinic Assignment that began after the care start is rejected, for both
    `CONFIRMED` and `COMPLETED` Appointments;
37. the `CLINICAL_CARE` capability and current `CLINICAL_CARE` Entitlement are
    required for a `COMPLETED` Appointment exactly as for a `CONFIRMED` one;
38. an `ACTIVE` `APPOINTMENT_CARE` Care Authorization of that Appointment is
    required, and a Care Authorization revoked by a Guardian after completion
    blocks establishment;
39. establishment never changes the Appointment's lifecycle state, scheduling
    information, Veterinarian Assignment, or completion information;
40. after post-completion establishment, Draft creation, update, finalization,
    Amendment, Clinical Attachment, and Encounter conclusion behave exactly as
    for an Encounter established before completion;
41. medical-access auditing and provenance of the Encounter and its
    documentation are unchanged;
42. Encounter establishment and Appointment completion for the same
    Appointment are serialized in either order, and both orders satisfy the
    care-start bound of BR-34 and BR-35;
43. Encounter establishment racing `NO_SHOW` or cancellation leaves either the
    Encounter with a `CONFIRMED` or `COMPLETED` Appointment, or the terminal
    `NO_SHOW` or `CANCELLED` outcome with no Encounter, never both;
44. a historical completion Lifecycle Event that references an Encounter
    remains valid and consistent with that Encounter's own Appointment
    reference, and new completions carry no Encounter reference.

---

## 15. Phase 1 Appointment-keyed client contract

Defined by **Minimal Clinical Record — Phase 1**. It narrows BR-1–BR-36 for the
mobile client; it does not change them.

### BR-37 — Appointment-keyed clinical context

Every client clinical operation of this phase (§15 here, `SPEC-MED-002` §14,
`SPEC-MED-003` §15, `SPEC-MED-008` §15, `SPEC-MED-009`) is keyed by the Clinic
and the Appointment the Professional client already shows
(`/professional/clinics/[clinicId]/appointments/[appointmentId]`). The server
derives everything else:

- the Veterinary Organization, from the Clinic;
- the Pet, from the Appointment;
- the Appointment-derived Care Authorization, which is unique per Appointment;
- the Clinical Encounter, which is unique per Care Authorization (BR-38);
- the acting Veterinarian's current Clinic Assignment.

The client never supplies or chooses a Care Authorization, Pet, Organization,
Clinic Assignment, or Encounter identifier. A Clinical Record Entry identifier
may be supplied; it is accepted only for an Entry of the Encounter resolved
from the authorized Appointment context.

Authority is decided before any target is revealed:

1. authentication and a coherent domain User — otherwise `28000`;
2. the acting User's current exact-Clinic Veterinarian context at the Clinic
   (current Membership, current Organization-scoped `VETERINARIAN`
   Responsibility, own Veterinarian Professional Profile, current Clinic
   Assignment) holding the operation's capability (`CLINICAL_CARE` to start or
   conclude an Encounter, `CLINICAL_DOCUMENTATION` to read or document) —
   otherwise `42501`;
3. the Appointment, which must belong to that Clinic — otherwise `42501`;
4. where supplied, the Entry, which must belong to the resolved Encounter —
   otherwise `42501`.

An unknown Clinic, Appointment, or Entry and one outside the actor's authority
produce the same `42501` with the same message and no hint, so no client learns
whether it exists. Every other rejection carries a stable hint; no raw database
message is part of the contract.

### BR-38 — One Encounter per Care Authorization is structural

At most one Clinical Encounter exists per Care Authorization, and therefore per
Appointment (BR-34 rule 5, `SPEC-ACC-001` BR-42). This is enforced by a unique
constraint in addition to the establishment operation, so no workflow, trusted
or client, can create a second one.

### BR-39 — Canonical Start operation

The client establishes the Appointment-backed Encounter only through

    start_appointment_clinical_encounter(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_started_at timestamptz default null
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It requires the `CLINICAL_CARE` capability (BR-37) and, for a
new Encounter, the Organization's current `CLINICAL_CARE` Entitlement.

The pre-existing `create_clinical_encounter(uuid, timestamptz, uuid)`, keyed by
a Care Authorization and reporting failures as raw database errors, is not a
client path. Client `EXECUTE` is withdrawn; it remains the trusted writer, kept
for trusted compatibility. Both apply the same establishment rules.

### BR-40 — Care start semantics

- For a `CONFIRMED` Appointment the client sends either an explicit care start
  or `NULL`. `NULL` is sent only when the Veterinarian explicitly chose
  **Start now / Empezar ahora**; the server then records the operation's
  statement instant as the care start. The device clock is never used.
- For a `COMPLETED` Appointment `NULL` is rejected (`START_TIME_REQUIRED`): the
  Veterinarian must enter the real care start. The server never substitutes the
  current time, the scheduled start, or the completion time (BR-12, BR-24).
- A care start must lie within the permitted window: not before the
  confirmation Lifecycle Event, the Care Authorization grant, or the start of
  the acting Veterinarian's current Clinic Assignment; not after the completion
  Lifecycle Event of a `COMPLETED` Appointment; and not in the future
  (BR-6, BR-25, BR-34). The same window is exposed before an Encounter exists
  by `SPEC-MED-009`. No documentation time limit applies (BR-34).

### BR-41 — Ordering

1. BR-37 steps 1–3; the Appointment and then its Care Authorization are locked;
2. an existing Encounter for the Appointment (BR-42);
3. the Organization's `CLINICAL_CARE` Entitlement — otherwise `42501`, hint
   `CLINICAL_SERVICE_UNAVAILABLE`;
4. Appointment lifecycle: `CONFIRMED` or `COMPLETED`, with exactly one
   confirmation Lifecycle Event and, when `COMPLETED`, exactly one completion
   Lifecycle Event — otherwise `23514`, hint `APPOINTMENT_STATE_INVALID`;
5. an `ACTIVE` Appointment-derived Care Authorization — otherwise `23514`, hint
   `CARE_AUTHORIZATION_INACTIVE`;
6. care start: `NULL` for a `COMPLETED` Appointment — `22023`, hint
   `START_TIME_REQUIRED`; a non-finite value — `22023`, hint
   `INVALID_START_TIME`; outside the window — `23514`, hint
   `START_TIME_OUT_OF_BOUNDS`;
7. establishment.

The Entitlement rejection is commercial and distinct from every domain
rejection (`SPEC-SUB-004` BR-34); it is presented as the Organization's clinical
service being unavailable, never as a plan.

### BR-42 — Outcomes and reconciliation

| Situation | Result |
| --- | --- |
| No Encounter exists and every rule holds | `CREATED` |
| An Encounter exists whose responsible Clinic Assignment is the acting Veterinarian's current one, and the request is `NULL` or the same care start | `ALREADY_EXISTS`; nothing is written |
| An Encounter exists with another responsible Clinic Assignment, or with a different care start | rejected, `23514`, hint `ENCOUNTER_EXISTS`; nothing is written |

Each successful result returns only `outcome`, `encounter_id`,
`lifecycle_state`, and `started_at`; never medical content. A retry after a lost
response therefore reconciles to the same Encounter without an idempotency key,
and another Veterinarian's Encounter is never reported as the caller's own.

Establishing the Encounter keeps every effect of BR-36: no Appointment
transition, a pending Reschedule Proposal becomes `VOID`, and cancellation,
`NO_SHOW`, and rescheduling are blocked from then on.

### Mobile presentation

- The professional Appointment detail shows a **Clinical record / Registro
  clínico** section only when the acting User's advisory Clinic capabilities
  (`SPEC-ORG-008`) include `CLINICAL_CARE` or `CLINICAL_DOCUMENTATION`, for a
  `CONFIRMED` or `COMPLETED` Appointment, or whenever an Encounter exists.
- `CONFIRMED` with no Encounter: **Start clinical record / Iniciar registro
  clínico**. It asks for an explicit choice: **Start now / Empezar ahora** or
  **Choose another time / Indicar otra hora**. No choice is preselected.
- `COMPLETED` with no Encounter: **Document this visit / Documentar esta
  visita**. Start now is not offered; the Veterinarian must enter the care
  start, within the window shown.
- After any outcome, including an apparent lost response, the client re-reads
  the clinical record (`SPEC-MED-009`) and the schedule; it never retries.
- No prompt forces documentation before or after completion (BR-34,
  `SPEC-APT-009` BR-2).

## 16. Phase 1 Appointment-keyed Start Verification Notes

In addition to §14, verification must demonstrate that:

45. a Veterinarian with the current exact-Clinic context starts the Encounter
    of a `CONFIRMED` Appointment with `NULL`, recorded at the statement instant,
    and with an explicit earlier valid care start;
46. a `COMPLETED` Appointment accepts an explicit care start within the window
    and rejects `NULL` with `START_TIME_REQUIRED`;
47. care starts before the confirmation, before the Care Authorization grant,
    before the Clinic Assignment start, after the completion, and in the future
    are rejected with `START_TIME_OUT_OF_BOUNDS` and nothing written;
48. `REQUESTED`, `CANCELLED`, `NO_SHOW`, and `EXPIRED` Appointments are rejected
    with `APPOINTMENT_STATE_INVALID`;
49. an actor without the clinical capability, at another Clinic, or naming an
    Appointment of another Clinic or an unknown Appointment receives the same
    `42501`;
50. without the `CLINICAL_CARE` Entitlement a new Encounter is rejected with
    `CLINICAL_SERVICE_UNAVAILABLE`;
51. a repeat by the same Veterinarian returns `ALREADY_EXISTS` with the same
    Encounter, and another Veterinarian or a different care start receives
    `ENCOUNTER_EXISTS`;
52. a second Encounter for the same Care Authorization cannot be inserted even
    outside the operation;
53. the operation accepts no Care Authorization identifier and returns no
    medical content;
54. no client role executes the generic establishment operation.

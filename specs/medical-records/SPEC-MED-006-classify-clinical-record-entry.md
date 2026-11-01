# SPEC-MED-006 — Classify Clinical Record Entry

**Status:** APPROVED  
**Requirements:** REQ-MED-006  
**Domain:** Medical Records  
**Priority:** P1

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the taxonomy is unchanged; Entries belong to an Appointment rather than an Encounter and the category is required at recording (SPEC-MED-010 BR-5), since no Draft exists. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Define a controlled Phase 1 clinical event taxonomy that allows Clinical Record
Entries to be classified according to the kind of clinical information they
represent.

Clinical event categories support:

- meaningful organization of the Pet's longitudinal medical history;
- clearer interpretation of clinical information;
- future filtering and presentation;
- evolution toward specialized medical domain models where required.

A clinical event category is a classification of a Clinical Record Entry.

It must not, by itself, replace the clinical content or define specialized
medical behavior.

---

## 2. Preconditions

- The Clinical Record Entry exists.
- The Clinical Record Entry belongs to a Clinical Encounter.
- The acting User is authorized to create or modify the applicable clinical
  information according to the Entry's current lifecycle state.
- The selected category is part of the supported clinical event taxonomy.
- If the Entry is being finalized, all category requirements applicable to
  finalization are satisfied.

---

## 3. Phase 1 Clinical Event Taxonomy

Phase 1 supports the following primary clinical event categories:

### EXAMINATION

Represents professional examination findings or clinical observations obtained
while evaluating the Pet.

Examples may include:

- physical examination;
- vital findings;
- observable symptoms;
- examination findings.

---

### DIAGNOSIS

Represents a professional diagnostic assessment or clinically meaningful
diagnostic conclusion.

The category itself does not imply diagnostic certainty.

Concepts such as:

- suspected;
- provisional;
- differential;
- confirmed;

may require structured behavior later.

---

### TREATMENT

Represents therapeutic care provided, recommended, or documented for the Pet.

Examples may include:

- therapeutic interventions;
- treatment plans;
- medication administration;
- ongoing therapy information.

Dedicated Treatment models may evolve later where required.

---

### PROCEDURE

Represents a veterinary procedure performed or documented as part of clinical
care.

Examples may include:

- wound care;
- dental procedure;
- minor intervention;
- surgery;
- other technical veterinary procedures.

A future specialized surgical or procedural model may refine this category.

---

### VACCINATION

Represents clinically meaningful vaccination information.

Phase 1 classification does not require Vaccination to already exist as a
dedicated domain model.

Future behavior may introduce structured vaccine information such as:

- vaccine product;
- dose;
- administration date;
- batch;
- next recommended dose;
- administration professional.

---

### PRESCRIPTION

Represents prescription-related clinical information.

This category does not by itself define a complete Prescription domain model.

Future requirements may introduce structured prescription behavior.

---

### LABORATORY_RESULT

Represents clinically relevant laboratory test results or interpretations.

Examples may include:

- blood analysis;
- urine analysis;
- microbiology;
- pathology;
- other laboratory findings.

Clinical attachments or future structured Laboratory Result models may provide
additional behavior.

---

### IMAGING_RESULT

Represents diagnostic imaging results or clinically relevant imaging
interpretation.

Examples may include:

- radiography;
- ultrasound;
- CT;
- MRI;
- other diagnostic imaging.

The image files themselves are governed separately by Clinical Attachment
behavior where applicable.

---

### CLINICAL_NOTE

Represents clinically meaningful narrative information that does not naturally
require one of the more specific supported categories.

`CLINICAL_NOTE` must not become a substitute for using a more appropriate
clinical event category when one clearly applies.

---

### OTHER

Represents clinically meaningful information that cannot reasonably be
classified using the supported Phase 1 taxonomy.

Use of `OTHER` requires a meaningful description of the event type before the
Entry may be finalized.

`OTHER` exists as an evolution escape hatch.

It must not become the default clinical event category.

---

## 4. Business Rules

### BR-1 — Every finalized Clinical Record Entry has one primary category

A Clinical Record Entry must have exactly one supported primary clinical event
category before it may be finalized.

A Draft may exist temporarily without a category while the clinical
information is still being prepared.

---

### BR-2 — Draft category may change

While a Clinical Record Entry remains in `DRAFT` state, an authorized
professional may change its clinical event category.

Changing Draft classification does not require a Clinical Amendment because the
Entry has not yet become finalized medical history.

---

### BR-3 — Finalization locks ordinary category editing

Once a Clinical Record Entry is `FINALIZED`, its clinical event category must
not be silently changed through ordinary editing.

A clinically meaningful correction to the classification must follow the
applicable amendment behavior.

---

### BR-4 — Category is classification, not clinical content

A clinical event category must not substitute for clinically meaningful
content.

For example:

    category = DIAGNOSIS

without meaningful clinical information is insufficient for finalization.

---

### BR-5 — Category does not imply clinical certainty

Selecting `DIAGNOSIS` must not automatically imply that a diagnosis is:

- confirmed;
- definitive;
- permanent.

Clinical certainty must come from the clinical information itself or from
future structured diagnostic behavior.

---

### BR-6 — Category does not imply medical access

A clinical event category must not grant or expand medical-access authority.

Access remains governed by Medical Access Control Specifications.

---

### BR-7 — Category does not change provenance

Changing or assigning a Draft clinical event category must not change:

- Pet;
- Clinical Encounter;
- Clinic;
- Veterinary Organization;
- original creator;
- contributors;
- responsible Veterinarian.

Classification and provenance are separate concerns.

---

### BR-8 — Category does not determine authorship

Clinical event classification must not determine who authored the clinical
information.

Authorship remains independently traceable.

---

### BR-9 — Several categories may appear within one Clinical Encounter

One Clinical Encounter may contain multiple Clinical Record Entries with
different event categories.

For example:

    Clinical Encounter
    ├── EXAMINATION
    ├── DIAGNOSIS
    ├── PROCEDURE
    └── TREATMENT

Each Entry remains independently identifiable and finalizable.

---

### BR-10 — One Entry has one primary Phase 1 category

Phase 1 assigns one primary clinical event category to each Clinical Record
Entry.

If one clinical care episode produces clinically distinct kinds of
information, separate Entries may be created.

This avoids ambiguous multi-category records in Phase 1.

Future requirements may introduce richer classification if justified.

---

### BR-11 — Category does not require specialized domain model

Selecting a category such as:

- VACCINATION;
- PRESCRIPTION;
- LABORATORY_RESULT;
- IMAGING_RESULT;

must not imply that a dedicated specialized domain entity already exists.

The Clinical Record Entry remains the Phase 1 longitudinal-history unit unless
another approved Specification introduces specialized behavior.

---

### BR-12 — Future specialized models must preserve longitudinal history

If a category later evolves into a dedicated domain model, the resulting
information must remain part of the same Pet longitudinal medical history.

Introducing a specialized model must not create a separate provider-specific or
feature-specific medical timeline.

---

### BR-13 — Future specialized models must preserve provenance

Evolution from a generic Clinical Record Entry toward a specialized medical
model must preserve applicable historical:

- Pet identity;
- Clinical Encounter;
- Clinic;
- Veterinary Organization;
- professional authorship;
- clinical event time;
- finalization history.

---

### BR-14 — Category identifiers must remain stable in meaning

Clinical event classification must not depend solely on mutable or localized
display labels.

For example, translating:

    PROCEDURE

as:

    Procedure
    Procedimiento
    Procédure

must not create three different clinical categories.

The domain category identity remains the same.

---

### BR-15 — Taxonomy evolution must not silently rewrite history

If the supported taxonomy changes in the future, previously finalized clinical
information must remain historically interpretable.

Changing the current taxonomy must not silently reclassify historical entries
as though they had originally been recorded under another category.

---

### BR-16 — Deprecated categories remain historically understandable

If a clinical event category is eventually replaced or deprecated, historical
Entries using that category must remain interpretable.

Taxonomy maintenance must not require deletion or destructive rewriting of
clinical history.

---

### BR-17 — OTHER requires additional classification context

A Clinical Record Entry classified as `OTHER` must contain enough additional
information to understand what kind of clinical event is being documented.

An Entry must not be finalized merely with:

    category = OTHER

and no meaningful event description.

---

### BR-18 — OTHER must not be automatically selected

The system must not silently classify an Entry as `OTHER` merely because the
professional has not selected a category.

Missing classification and explicit `OTHER` classification are different
states.

---

### BR-19 — CLINICAL_NOTE is clinically meaningful information

`CLINICAL_NOTE` is intended for clinically meaningful narrative information.

It must not be used for:

- billing notes;
- internal administrative comments;
- subscription information;
- unrelated operational communication.

Clinical Records and administrative records are separate concerns.

---

### BR-20 — PROCEDURE may represent surgery in Phase 1

Phase 1 does not require a dedicated `SURGERY` category.

Surgical care may be represented as a `PROCEDURE` Clinical Record Entry.

If surgical behavior later requires specialized structure, it may evolve into
a dedicated medical model without rewriting its historical Pet context.

---

### BR-21 — Laboratory and imaging category represent clinical information, not files

`LABORATORY_RESULT` and `IMAGING_RESULT` describe clinically meaningful record
content.

Associated reports, images, or files are separate protected Clinical
Attachments where applicable.

The existence of a file alone must not determine the clinical event category.

---

### BR-22 — Category participates in longitudinal history presentation

An authorized medical-history view may use clinical event category to organize,
label, group, or filter finalized information.

Classification must not change underlying chronological or provider
provenance.

---

### BR-23 — Category does not replace clinically relevant chronology

The clinical event category must not determine the chronological position of an
Entry.

Chronology continues to depend on the applicable clinical event time.

---

### BR-24 — Category correction after finalization must remain traceable

If a Finalized Clinical Record Entry was classified incorrectly, correcting the
classification must preserve the fact that the original finalized
classification existed.

The correction must use the applicable Clinical Amendment behavior rather than
silent replacement.

---

### BR-25 — Category assignment must respect Entry lifecycle

Category modification authority depends on whether the Clinical Record Entry is:

- `DRAFT`; or
- `FINALIZED`.

Draft classification may be ordinarily edited.

Finalized classification follows finalized-record integrity rules.

---

### BR-26 — Category classification does not complete Clinical Encounter

Assigning or changing a clinical event category must not:

- complete the Clinical Encounter;
- finalize the Clinical Record Entry;
- complete an Appointment.

Those lifecycle transitions remain separate explicit behaviors.

---

## 5. Scenarios

### Scenario: Draft is classified as Examination

Given Dr. Garcia has a Draft Clinical Record Entry for Luna
And Dr. Garcia is authorized to contribute to the Clinical Encounter

When the Entry is classified as `EXAMINATION`

Then the Draft remains the same Clinical Record Entry
And its category becomes `EXAMINATION`
And the Entry remains `DRAFT`

---

### Scenario: Draft category may be corrected before finalization

Given Luna has a Draft Clinical Record Entry classified as `CLINICAL_NOTE`

When an authorized professional determines that the information is more
appropriately classified as `EXAMINATION`
And updates the Draft category

Then the Entry remains the same Draft
And its category becomes `EXAMINATION`
And no Clinical Amendment is required

---

### Scenario: Finalized Entry requires category

Given Luna has a clinically meaningful Draft Clinical Record Entry
And the Entry has no clinical event category

When an authorized professional attempts to finalize it

Then finalization is rejected
And the Entry remains `DRAFT`

---

### Scenario: One Encounter contains several clinical event types

Given Luna has a Clinical Encounter at Animalia Madrid Centro
And Dr. Garcia documents an examination
And Dr. Garcia documents a diagnosis
And Dr. Garcia documents a treatment

When the clinical information is represented

Then separate Clinical Record Entries may exist with categories:

    EXAMINATION
    DIAGNOSIS
    TREATMENT

And all Entries remain associated with the same Clinical Encounter.

---

### Scenario: Surgery is represented as Procedure in Phase 1

Given Luna undergoes surgery during an authorized Clinical Encounter

When the applicable Clinical Record Entry is classified in Phase 1

Then the Entry may use the `PROCEDURE` category
And a dedicated Surgery domain model is not required solely for classification

---

### Scenario: Vaccination category does not create dedicated Vaccination model

Given Dr. Garcia creates a Clinical Record Entry documenting Luna's vaccination

When the Entry is classified as `VACCINATION`

Then the Clinical Record Entry may represent the vaccination in Phase 1
And classification alone does not require creation of a separate Vaccination
domain entity

---

### Scenario: Other requires meaningful description

Given Luna has a Draft Clinical Record Entry
And no supported specific category reasonably describes the clinical event

When an authorized professional selects `OTHER`

Then the Entry may remain Draft
But it cannot be finalized without meaningful information describing the
clinical event type

---

### Scenario: Missing category is not automatically Other

Given Luna has a Draft Clinical Record Entry
And no clinical event category has been selected

When the Draft is saved

Then the system does not silently classify it as `OTHER`
And the category may remain unset while the Entry remains Draft

---

### Scenario: Clinical Note is not used for administrative information

Given an internal Clinic comment concerns billing or operational administration
And does not represent clinically meaningful Pet information

When an actor attempts to store it as a `CLINICAL_NOTE`

Then the Clinical Record workflow must not treat the administrative information
as clinical history solely through that category

---

### Scenario: Finalized category cannot be silently changed

Given Luna has a Finalized Clinical Record Entry classified as `TREATMENT`

When a User attempts to directly change its category to `PROCEDURE`

Then ordinary editing is denied
And the original finalized classification remains unchanged
And correction requires the applicable Clinical Amendment workflow

---

### Scenario: Another Clinic sees original category

Given Animalia Madrid Centro finalized a `VACCINATION` Entry for Luna
And VetCare Toledo later receives authorized cross-clinic history access

When VetCare views the Entry

Then the Entry remains classified as `VACCINATION`
And Animalia remains the provider of origin
And cross-clinic access does not reclassify the Entry

---

### Scenario: Clinical category does not change authorship

Given Dr. Garcia created a Draft Clinical Record Entry
And Dr. Lopez later validly changes its category while contributing to the same
authorized care context

When the category is changed

Then Dr. Garcia remains identifiable as the original creator
And Dr. Lopez remains identifiable as a contributor
And category modification does not transfer authorship

---

### Scenario: Localized labels refer to same category

Given a finalized Clinical Record Entry has the domain category `PROCEDURE`

When the category is displayed in different supported languages

Then the localized labels may differ
And the underlying clinical event category remains the same

---

### Scenario: New specialized model does not fragment history

Given Luna has a historical `VACCINATION` Clinical Record Entry
And a future dedicated Vaccination model is later introduced

When Luna's longitudinal medical history is viewed

Then the historical vaccination remains part of Luna's longitudinal history
And introduction of the specialized model does not create a separate medical
timeline

---

## 6. Taxonomy Summary

The Phase 1 controlled clinical event taxonomy is:

    EXAMINATION
    DIAGNOSIS
    TREATMENT
    PROCEDURE
    VACCINATION
    PRESCRIPTION
    LABORATORY_RESULT
    IMAGING_RESULT
    CLINICAL_NOTE
    OTHER

Each Finalized Clinical Record Entry has one primary category.

The taxonomy describes the nature of the clinical contribution.

It does not replace the clinical information itself.

---

## 7. Category vs Specialized Domain Model

Clinical event category answers:

    "What general kind of clinical information is this?"

A specialized domain model answers questions such as:

    "What behavior and structured data does a Vaccination require?"

or:

    "How should a Prescription be issued, changed, expired, or renewed?"

These are different concerns.

For Phase 1:

    Clinical Record Entry
          +
    event category

is sufficient unless an approved Specification establishes dedicated behavior.

This preserves the evolution path required by `REQ-MED-012`.

---

## 8. Clinical Event Examples

A single Clinical Encounter may conceptually contain:

    Luna
    Animalia Madrid Centro
    2026-09-10

    EXAMINATION
    "Temperature elevated; abdominal discomfort on palpation."

    DIAGNOSIS
    "Acute gastroenteritis considered most likely."

    TREATMENT
    "Supportive treatment initiated."

    PRESCRIPTION
    "Medication prescribed according to documented instructions."

Each contribution remains independently identifiable.

They share the same Clinical Encounter context without becoming one
unstructured record.

---

## 9. Edge Cases

### Clinical information fits more than one category

Some clinical information may reasonably relate to several concepts.

Phase 1 uses one primary category per Clinical Record Entry.

Where clinically distinct information needs independent representation,
separate Clinical Record Entries should be preferred over ambiguous
multi-category classification.

---

### Taxonomy does not contain an exact category

When no supported category adequately represents the clinical event, `OTHER`
may be used together with meaningful descriptive information.

Repeated use of `OTHER` for the same type of clinically important event may be
evidence that the taxonomy should evolve.

---

### Category taxonomy evolves

Adding, deprecating, or refining categories in later product versions must not
require destructive rewriting of historical Finalized Clinical Record Entries.

---

### Specialized medical model is introduced

A future specialized model may associate structured behavior with information
that was previously represented by a generic Clinical Record Entry category.

The evolution must preserve longitudinal Pet history and original provenance.

---

### Category was incorrectly selected before finalization

An authorized professional may correct the category through ordinary Draft
editing.

No Clinical Amendment is required.

---

### Category was incorrectly selected after finalization

Correction must follow finalized-record Amendment rules.

The original finalized classification remains historically traceable.

---

## 10. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**

---

## 11. Dependencies

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-004 — Amend Finalized Clinical Record Entry
- SPEC-MED-005 — View Pet Medical History

---

## 12. Out of Scope

This Specification does not define:

- dedicated Diagnosis domain models;
- diagnostic certainty models;
- dedicated Treatment domain models;
- dedicated Procedure or Surgery models;
- dedicated Vaccination models;
- dedicated Prescription models;
- Laboratory Result schemas;
- Imaging schemas;
- clinical attachment behavior;
- multi-category Clinical Record Entries;
- clinical-event search or filtering UI;
- medical coding systems;
- standardized veterinary terminology;
- SNOMED or other external clinical vocabularies;
- billing or administrative event categories.

---

## 13. Verification Notes

Verification must demonstrate that:

1. Phase 1 provides a controlled clinical event taxonomy;
2. every Finalized Clinical Record Entry has exactly one primary supported
   category;
3. a Draft may temporarily have no category;
4. Draft category may be changed before finalization;
5. finalized category cannot be silently rewritten;
6. category correction after finalization follows Amendment behavior;
7. classification does not replace meaningful clinical content;
8. `DIAGNOSIS` does not automatically imply diagnostic certainty;
9. multiple independently classified Entries may exist within one Clinical
   Encounter;
10. clinical category does not modify Pet, Encounter, provider provenance, or
    authorship;
11. category does not grant medical access;
12. `OTHER` requires meaningful descriptive context before finalization;
13. missing category is not automatically converted to `OTHER`;
14. `CLINICAL_NOTE` is limited to clinically meaningful information;
15. `PROCEDURE` may represent surgery in Phase 1;
16. specialized medical models are not required merely because a category
    exists;
17. future specialized models preserve longitudinal history and provenance;
18. localized labels do not change domain category identity;
19. taxonomy evolution does not destructively rewrite historical records;
20. category classification remains independent from Clinical Encounter and
    Appointment lifecycle.
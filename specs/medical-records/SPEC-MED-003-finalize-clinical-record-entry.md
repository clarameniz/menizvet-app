# SPEC-MED-003 — Finalize Clinical Record Entry

**Status:** APPROVED  
**Requirements:** REQ-MED-003, REQ-MED-004, REQ-MED-005, REQ-MED-007, REQ-MED-008, REQ-AUD-001, REQ-AUD-002
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): finalization as a separate operation and §15 are retired; recording an Entry is its Guardian publication (SPEC-MED-010 BR-4). BR-38 publication semantics and the immutability rules continue to apply to recorded Entries. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized veterinary professional to finalize a Draft Clinical Record
Entry when the clinical information is sufficiently complete to become part of
the Pet's longitudinal medical history.

Finalization represents an explicit professional commitment that the Clinical
Record Entry is no longer ordinary work-in-progress information.

A finalized Clinical Record Entry must preserve its clinical meaning,
authorship, professional context, and historical provenance.

Corrections after finalization require a traceable amendment workflow.

---

## 2. Preconditions

- The Clinical Record Entry exists.
- The Clinical Record Entry is currently in `DRAFT` state.
- The Clinical Encounter exists.
- The Entry belongs to that Clinical Encounter.
- The Pet associated with the Encounter exists.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a Veterinarian Professional Profile.
- The acting User is currently authorized to contribute clinical information
  within the Clinical Encounter.
- The Entry satisfies the minimum information requirements applicable to
  finalization.
- The Entry contains clinically meaningful information.
- The clinical provenance required for finalization is available.

---

## 3. Business Rules

### BR-1 — Finalization must be explicit

A Draft Clinical Record Entry must not become finalized merely because:

- it was saved;
- the Clinical Encounter exists;
- an Appointment was completed;
- a Veterinarian stops editing;
- a period of time has elapsed.

Finalization requires an explicit authorized professional operation.

---

### BR-2 — Only Draft Entries may be finalized

The normal finalization workflow applies only to Clinical Record Entries that
remain in `DRAFT` state.

An Entry already finalized must not be finalized again through the same
workflow.

---

### BR-3 — Finalization transitions the existing Entry

Successful finalization changes the existing Clinical Record Entry from:

    DRAFT → FINALIZED

The operation must not create a replacement Clinical Record Entry solely to
represent finalization.

The Entry remains the same domain entity.

---

### BR-4 — Finalization makes the Entry part of longitudinal medical history

Once finalized, the Clinical Record Entry becomes part of the Pet's finalized
longitudinal medical history.

It may therefore become available to authorized Guardians and authorized
professionals according to the applicable Medical Access Control
Specifications.

---

### BR-5 — Finalization requires current clinical authorization

The professional performing finalization must currently be authorized to
contribute clinical information within the Clinical Encounter.

Historical professional involvement alone is insufficient.

Being a Veterinarian outside the Encounter's current authorized care context is
also insufficient.

---

### BR-6 — Finalizer does not need to be the original creator

A Draft Clinical Record Entry may be finalized by an authorized veterinary
professional other than the User who originally created it.

Clinical continuity must not depend on the original creator remaining
available.

For example:

    Created by:
    Dr. Garcia

    Later contributed by:
    Dr. Lopez

    Finalized by:
    Dr. Lopez

All relevant contributions remain historically distinguishable.

---

### BR-7 — Original creator remains identifiable

Finalization by another professional must not rewrite the identity of the
original Draft creator.

The system must preserve the distinction between:

- original creator;
- later contributors;
- finalizing professional.

---

### BR-8 — Material contributors remain traceable

Where multiple authorized veterinary professionals materially contributed to
the Draft before finalization, the finalized record must preserve sufficient
information to identify those contributions where required for clinical
provenance.

The finalizing User must not become falsely represented as the sole author of
information contributed by others.

---

### BR-9 — Finalizer assumes responsibility for finalization

The professional who finalizes the Entry must remain identifiable as the User
who committed the Entry to finalized medical history.

Finalization responsibility is distinct from original authorship and previous
contribution.

---

### BR-10 — Finalized Entry preserves Pet identity

Finalization must not change which Pet the Clinical Record Entry concerns.

The Pet is derived from the Clinical Encounter and must remain unchanged.

---

### BR-11 — Finalized Entry preserves Clinical Encounter identity

Finalization must not move the Clinical Record Entry to another Clinical
Encounter.

The Encounter in which the information was documented remains part of its
clinical provenance.

---

### BR-12 — Finalized Entry preserves Clinic provenance

The Clinic associated with the Clinical Encounter must remain part of the
finalized Entry's provenance.

Finalization must not move the record to another Clinic.

---

### BR-13 — Finalized Entry preserves Veterinary Organization provenance

The Veterinary Organization context under which the care occurred must remain
historically identifiable.

Later employment or Organization changes must not alter that attribution.

---

### BR-14 — Finalized Entry preserves responsible professional context

The responsible Veterinarian associated with the Clinical Encounter remains
part of the historical care context.

That concept remains distinct from:

- Draft creator;
- contributors;
- finalizing professional.

Where those Users differ, the system must not collapse them into one
professional identity.

---

### BR-15 — Finalization preserves clinically relevant event time

A finalized Clinical Record Entry must preserve the clinically relevant date
or time associated with the recorded event where applicable.

This may differ from:

- Encounter start time;
- Draft creation time;
- finalization time.

Those timestamps must remain conceptually distinguishable.

---

### BR-16 — Finalization preserves creation and finalization timestamps

The system must preserve:

- when the Entry was originally created;
- when it was finalized.

Finalization must not overwrite the original creation time.

---

### BR-17 — Minimum finalized clinical information is required

A Clinical Record Entry must contain enough information to represent a
meaningful clinical contribution before it may be finalized.

An empty or clinically meaningless Draft must not become finalized medical
history.

The exact required content may depend on the applicable clinical event
category.

---

### BR-18 — Finalized Entry must have a supported clinical event category

A Clinical Record Entry must identify an applicable supported clinical event
category before finalization.

The exact Phase 1 taxonomy is defined through the Specifications that refine
`REQ-MED-006`.

A Draft may exist before the final category is known.

---

### BR-19 — Finalization does not require every future specialized medical model

Phase 1 finalization must not depend on dedicated Treatment, Vaccination,
Prescription, Laboratory Result, or Imaging domain models unless their
applicable behavior has been separately specified.

The Clinical Record model must remain capable of evolving toward those
specialized models later.

---

### BR-20 — Finalized clinical content is no longer ordinarily editable

Once finalized, the clinically meaningful content of the Entry must not be
silently destructively rewritten through the normal Draft editing workflow.

Normal Draft mutability ends at finalization.

---

### BR-21 — Corrections after finalization require amendment

When finalized clinical information requires correction, clarification, or
additional context, the change must occur through the applicable Clinical
Amendment workflow.

The finalized historical information must not be silently replaced as though
the previous clinical statement never existed.

---

### BR-22 — Finalization does not erase Draft authorship history

Transitioning from `DRAFT` to `FINALIZED` must not discard meaningful
authorship or contribution information accumulated while the Entry was being
prepared.

---

### BR-23 — Finalization does not create a new Clinical Encounter

Finalizing a Clinical Record Entry must not:

- create another Clinical Encounter;
- complete the Clinical Encounter automatically;
- create an Appointment;
- change Appointment state.

Record finalization and care-episode lifecycle are separate concepts.

---

### BR-24 — Several Entries may be finalized independently

A Clinical Encounter may contain multiple Clinical Record Entries.

Finalizing one Entry must not automatically finalize all remaining Draft
Entries.

For example:

    Clinical Encounter
    ├── examination entry → FINALIZED
    ├── diagnosis entry   → DRAFT
    └── treatment entry   → DRAFT

Each Entry has an independent lifecycle.

---

### BR-25 — Finalized records from multiple providers belong to one Pet history

A Pet's longitudinal medical history may contain finalized Clinical Record
Entries originating from different Clinics and Veterinary Organizations.

For example:

    Luna
    ├── Animalia Madrid Centro
    │     └── Vaccination
    │
    ├── VetCare Toledo
    │     └── Surgery
    │
    └── Animalia Getafe
          └── Examination

Each Entry remains attributed to its original clinical provider context.

---

### BR-26 — Cross-clinic visibility does not transfer authorship

When another authorized Clinic later accesses a finalized Clinical Record
Entry, that access must not change:

- authorship;
- Clinic provenance;
- Organization provenance;
- clinical event date;
- finalization information.

Reading clinical history does not make the accessing provider its author.

---

### BR-27 — Employment changes do not rewrite finalized provenance

If a Veterinarian later:

- leaves the Clinic;
- joins another Clinic;
- leaves the Veterinary Organization;
- joins another Veterinary Organization;

previously finalized clinical information must remain attributed to the
original clinical context.

---

### BR-28 — Clinic changes do not rewrite finalized provenance

Changes to a Clinic's:

- public display name;
- current location;
- publication state;
- operational status

must not change which Clinic historically produced the finalized clinical
information.

The Clinic domain identity remains the historical reference.

---

### BR-29 — Subscription changes do not affect finalized history

Loss or termination of Organization subscription must not:

- delete finalized Clinical Record Entries;
- rewrite provenance;
- remove historical authorship;
- alter Pet medical history.

Commercial state and medical-history integrity are separate concerns.

---

### BR-30 — Finalization does not grant unrestricted medical access

Finalizing an Entry must not itself expand medical-access rights.

The Entry becomes eligible for access according to the applicable current
Guardian and professional access-control rules.

---

### BR-31 — Guardian visibility applies only after finalization

A Guardian must not receive the Entry through normal longitudinal medical
history access while it remains Draft.

Once finalized, it may become visible to an authorized Guardian according to
the applicable Guardian medical-history access rules.

---

### BR-32 — Cross-clinic visibility applies only after finalization

A Draft Entry must not be exposed as normal longitudinal history to another
Clinic.

A finalized Entry may participate in authorized cross-clinic medical history
access.

---

### BR-33 — Finalization does not imply clinical correctness forever

Finalization represents professional commitment to the clinical information at
that point in time.

It does not mean that medical understanding can never later change.

New clinical findings or corrections must be represented through new clinical
information or traceable amendments rather than destructive rewriting.

---

### BR-34 — Finalization is atomic

Successful finalization must atomically establish:

- finalized state;
- finalization time;
- finalizing professional;
- required clinical provenance;
- finalized clinical content.

The system must not expose an Entry as `FINALIZED` without the provenance
necessary to interpret that history.

---

### BR-35 — Failed finalization preserves the Draft

If finalization cannot be completed validly, the existing Clinical Record Entry
must remain a Draft.

A failed finalization attempt must not:

- partially finalize the Entry;
- lose Draft content;
- remove authorship;
- expose incomplete information as finalized history.

---

### BR-36 — Repeated finalization does not duplicate history

If an Entry is already finalized, another finalization attempt must not:

- create another Clinical Record Entry;
- duplicate medical-history entries;
- replace the original finalization time;
- replace the original finalizing professional.

---

## 4. Finalized Clinical Record Information

A finalized Clinical Record Entry must preserve enough information to represent
a meaningful and auditable contribution to the Pet's longitudinal medical
history.

### Required

- Clinical Record Entry identity;
- Clinical Encounter;
- Pet;
- Clinic;
- Veterinary Organization context;
- original creator;
- relevant clinical contributors where applicable;
- finalizing professional;
- creation time;
- finalization time;
- supported clinical event category;
- clinically meaningful finalized content;
- relevant clinical event date or time where applicable.

### Context inherited from the Clinical Encounter

- responsible Veterinarian;
- applicable historical care context;
- medical-access basis under which the Encounter was established.

The exact persistence representation is not defined by this Specification.

---

## 5. Scenarios

### Scenario: Original creator finalizes their Draft

Given Dr. Garcia created a Draft Clinical Record Entry for Luna
And Dr. Garcia remains currently authorized in Luna's Clinical Encounter
And the Draft satisfies the finalization requirements

When Dr. Garcia finalizes the Entry

Then the Entry becomes `FINALIZED`
And Dr. Garcia remains identifiable as the original creator
And Dr. Garcia is recorded as the finalizing professional
And the Entry becomes part of Luna's finalized longitudinal medical history

---

### Scenario: Another authorized Veterinarian finalizes the Draft

Given Dr. Garcia originally created a Draft Clinical Record Entry for Luna
And Dr. Lopez is currently authorized to contribute within the same Clinical
Encounter
And Dr. Lopez has reviewed the Draft
And the Draft satisfies finalization requirements

When Dr. Lopez finalizes the Entry

Then the Entry becomes `FINALIZED`
And Dr. Garcia remains identifiable as the original creator
And Dr. Lopez is recorded as the finalizing professional
And the existing Clinical Record Entry remains the same domain entity

---

### Scenario: Collaborative Draft preserves contributors at finalization

Given Dr. Garcia created Luna's Draft Clinical Record Entry
And Dr. Lopez later materially contributed to that Draft
And both contributions are validly traceable

When an authorized professional finalizes the Entry

Then the finalized Entry preserves Dr. Garcia as the original creator
And Dr. Lopez remains identifiable as a contributor
And the finalizing professional remains separately identifiable
And no contribution is silently attributed to another professional

---

### Scenario: Original creator leaves Clinic before finalization

Given Dr. Garcia created a Draft Clinical Record Entry for Luna
And Dr. Garcia later loses current professional authorization at the Clinic
And Dr. Lopez remains currently authorized within Luna's Clinical Encounter
And the Draft is otherwise valid for finalization

When Dr. Lopez reviews and finalizes the Draft

Then the Entry may become `FINALIZED`
And Dr. Garcia remains identifiable as the original creator
And Dr. Lopez is identified as the finalizing professional
And clinical continuity does not require Dr. Garcia to retain access

---

### Scenario: Former professional cannot finalize after losing authorization

Given Dr. Garcia created a Draft Clinical Record Entry
And Dr. Garcia no longer has current authorization within the Clinical
Encounter

When Dr. Garcia attempts to finalize the Draft solely because she originally
created it

Then the operation is denied
And historical authorship alone does not grant current finalization authority

---

### Scenario: Unauthorized Veterinarian cannot finalize Draft

Given Dr. Lopez is a Veterinarian
And Dr. Lopez has no current authorization to contribute within Luna's
Clinical Encounter

When Dr. Lopez attempts to finalize Luna's Draft

Then the operation is denied
And Veterinarian status alone is insufficient

---

### Scenario: Empty Draft cannot be finalized

Given Luna has a Draft Clinical Record Entry
And the Draft contains no clinically meaningful information

When an authorized Veterinarian attempts to finalize it

Then finalization is rejected
And the Entry remains `DRAFT`

---

### Scenario: Draft without required category cannot be finalized

Given Luna has a clinically meaningful Draft
And no supported clinical event category has been established

When an authorized Veterinarian attempts to finalize it

Then finalization is rejected
And the Entry remains `DRAFT`

---

### Scenario: Finalization preserves Pet and Encounter

Given Luna has a valid Draft Clinical Record Entry in Clinical Encounter A

When the Entry is finalized

Then the Entry remains associated with Luna
And the Entry remains associated with Clinical Encounter A
And finalization does not move it to another Pet or Encounter

---

### Scenario: Finalization preserves provider provenance

Given Luna's Clinical Encounter occurred at Animalia Madrid Centro
And the Encounter belongs to Animalia Veterinary Group

When a valid Clinical Record Entry from that Encounter is finalized

Then the finalized Entry remains attributed to Animalia Madrid Centro
And it remains attributed to Animalia Veterinary Group
And later provider changes do not rewrite that provenance

---

### Scenario: Finalization preserves different clinical timestamps

Given Luna's Clinical Encounter began at 10:18
And a clinical observation occurred at 10:35
And the Draft was created at 10:40
And the Entry was finalized at 11:15

When the finalized Entry is viewed

Then the relevant clinical event time may remain 10:35
And the creation time remains 10:40
And the finalization time remains 11:15
And those timestamps are not silently collapsed into one value

---

### Scenario: Finalized Entry becomes eligible for Guardian history

Given Maria is an authorized Guardian of Luna
And Luna has a Draft Clinical Record Entry

When the Entry is validly finalized

Then the Entry becomes part of Luna's finalized longitudinal medical history
And Maria may view it according to the applicable Guardian medical-history
access rules

---

### Scenario: Finalized Entry becomes eligible for cross-clinic history

Given Animalia Madrid Centro finalizes a Clinical Record Entry for Luna
And Luna later has an authorized care context at VetCare Toledo

When VetCare validly accesses Luna's relevant longitudinal history

Then the finalized Animalia Entry may be made available according to the
applicable access-control rules
And the Entry remains attributed to Animalia Madrid Centro
And its authorship remains unchanged

---

### Scenario: Finalized Entry cannot be edited through Draft workflow

Given Luna has a `FINALIZED` Clinical Record Entry

When a User attempts to modify its clinical content using the Draft editing
workflow

Then the operation is denied
And the finalized clinical content remains unchanged
And corrections require the applicable Clinical Amendment workflow

---

### Scenario: Finalizing one Entry does not finalize another

Given Luna's Clinical Encounter contains Draft Entry A and Draft Entry B

When an authorized Veterinarian finalizes Entry A

Then Entry A becomes `FINALIZED`
And Entry B remains `DRAFT`
And the Entries retain independent lifecycle states

---

### Scenario: Failed finalization preserves Draft

Given Luna has a valid Draft Clinical Record Entry
And finalization cannot be completed atomically

When the finalization operation fails

Then the Entry remains `DRAFT`
And the Draft content remains available according to applicable authorization
And no partial finalized history is exposed

---

### Scenario: Already finalized Entry is not finalized again

Given Luna's Clinical Record Entry is already `FINALIZED`

When another finalization attempt occurs

Then no duplicate medical-history Entry is created
And the original finalization time remains unchanged
And the original finalizing professional remains unchanged

---

### Scenario: Veterinarian changes Organization later

Given Dr. Garcia finalized clinical information for Luna while working at
Animalia Madrid Centro
And Dr. Garcia later joins VetCare Group

When Luna's historical medical record is viewed

Then the Entry remains attributed to Animalia Madrid Centro
And Animalia Veterinary Group
And Dr. Garcia's later employment does not rewrite the historical provider
context

---

### Scenario: Subscription termination does not erase finalized record

Given Animalia Veterinary Group has finalized clinical information for Luna

When Animalia later loses or terminates its platform subscription

Then Luna's finalized Clinical Record Entry remains part of her longitudinal
medical history
And clinical provenance remains unchanged

---

## 6. Draft to Finalized Transition

The Clinical Record Entry lifecycle established so far is:

    DRAFT
      ↓
    explicit authorized finalization
      ↓
    FINALIZED

Before finalization:

    ordinary Draft editing permitted
    incomplete information allowed
    not part of normal finalized longitudinal history

After finalization:

    ordinary Draft editing prohibited
    part of longitudinal medical history
    provenance preserved
    corrections require amendment

Finalization is therefore a clinically meaningful boundary.

---

## 7. Authorship and Finalization

Several professional identities may be relevant to one finalized Entry.

For example:

    Original creator:
    Dr. Garcia

    Contributor:
    Dr. Lopez

    Responsible Veterinarian for Encounter:
    Dr. Garcia

    Finalizing professional:
    Dr. Lopez

These concepts must not be collapsed merely because Phase 1 frequently results
in the same User occupying several roles.

The data model must remain capable of preserving the distinctions when they
differ.

---

## 8. Historical Integrity

A finalized Clinical Record Entry represents what was professionally committed
at a particular point in time.

The normal system must not transform:

    Finalized statement A

into:

    Finalized statement B

while making it appear that statement A never existed.

Instead:

    Finalized statement A
            ↓
    traceable Clinical Amendment
            ↓
    corrected / clarified current interpretation

The amendment workflow is defined separately.

---

## 9. Longitudinal Medical History

Finalized Clinical Record Entries contribute to the Pet's medical history
across providers.

Conceptually:

    Luna

    2026
    Animalia Madrid Centro
    Dr. Garcia
    Examination
    FINALIZED

    2027
    VetCare Toledo
    Dr. Lopez
    Surgery-related record
    FINALIZED

    2028
    Animalia Getafe
    Dr. Ruiz
    Vaccination
    FINALIZED

Each contribution remains historically attributable to its original provider
and professional context.

---

## 10. Edge Cases

### Clinical Encounter ends before Draft is finalized

A Draft may remain unfinished after actual care has ended.

The Draft must not become finalized automatically.

An authorized professional may finalize it later only through a valid
post-Encounter documentation context defined by the applicable clinical
workflow.

The exact duration and rules for delayed documentation may require future
refinement.

---

### Original creator is unavailable

The absence of the original creator must not permanently block clinical
documentation where another professional is appropriately authorized and able
to review and finalize the information.

Authorship history must remain preserved.

---

### Finalizing professional did not personally observe every fact

A professional who finalizes collaborative clinical information must do so
within an authorized professional context.

Detailed requirements for attestation, co-signature, supervision, or review of
another professional's observations may be introduced later where clinically
or legally required.

Phase 1 does not silently infer that finalization means the finalizer personally
observed every recorded event.

---

### Incorrect Pet context discovered before finalization

The Draft must not be finalized under a Pet context known to be incorrect.

Moving clinical information between Pets requires a dedicated safe correction
workflow.

---

### Incorrect Pet context discovered after finalization

A finalized record associated with the wrong Pet is a high-risk historical
correction case.

It must not be silently moved to another Pet.

A dedicated auditable correction workflow is required.

---

### Finalized information later becomes clinically outdated

A later change in clinical understanding does not make the earlier finalized
Entry historically false or deletable.

New clinical information or a Clinical Amendment may supersede or clarify the
earlier interpretation while preserving history.

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

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-ID-003 — Authenticate User

---

## 13. Out of Scope

This Specification does not define:

- Clinical Amendment creation;
- amendment display;
- clinical event taxonomy;
- dedicated Diagnosis models;
- dedicated Treatment models;
- Vaccination models;
- Prescription models;
- Laboratory Result models;
- Imaging models;
- clinical attachments;
- co-signature requirements;
- professional supervision;
- delayed-documentation time limits;
- incorrect-Pet finalized-record correction;
- Guardian medical-history access rules;
- Clinical Encounter completion.

---

## 14. Verification Notes

Verification must demonstrate that:

1. finalization is an explicit operation;
2. only Draft Entries may be finalized;
3. finalization preserves the same Clinical Record Entry identity;
4. finalized Entries become part of longitudinal medical history;
5. current clinical authorization is required;
6. an authorized professional other than the original creator may finalize;
7. original creator, contributors, responsible professional context, and
   finalizer remain distinguishable;
8. clinically meaningful information and a supported event category are
   required before finalization;
9. Pet, Encounter, Clinic, and Organization provenance remain unchanged;
10. clinical event, creation, and finalization timestamps remain conceptually
    distinguishable;
11. finalized content cannot be modified through normal Draft editing;
12. later corrections require traceable amendment behavior;
13. finalization does not erase Draft authorship history;
14. finalization does not complete the Clinical Encounter automatically;
15. Clinical Record Entries within one Encounter remain independently
    finalizable;
16. finalized Entries may participate in authorized Guardian and cross-clinic
    medical-history access;
17. employment, Clinic profile, and subscription changes do not rewrite or
    erase finalized clinical history;
18. failed finalization preserves the Draft;
19. repeated finalization does not duplicate medical history;
20. finalization behaves atomically.

---

## 15. Phase 1 Appointment-keyed Finalize contract

Defined by **Minimal Clinical Record — Phase 1**. It narrows BR-1–BR-36 for the
mobile client; it does not change them. The Appointment-keyed clinical context
and its authority ordering are those of `SPEC-MED-001` BR-37, with the
`CLINICAL_DOCUMENTATION` capability, followed by `SPEC-MED-002` §14
`ENCOUNTER_NOT_STARTED` and the Entry check.

### BR-37 — Canonical Finalize operation

    finalize_appointment_clinical_entry(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_entry_id uuid,
        p_expected_revision bigint
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, is executable only by
`authenticated`, and requires no Entitlement (`SPEC-SUB-004` BR-17). Any
Veterinarian whose current exact-Clinic context holds `CLINICAL_DOCUMENTATION`
may finalize (BR-5, BR-6); the finalizer's identity and Clinic Assignment are
recorded (BR-9).

Ordering after the Entry is resolved:

1. expected revision — `NULL` or negative is `22023`, hint `INVALID_REVISION`;
2. an Entry already `FINALIZED` — outcome `ALREADY_FINALIZED`, nothing written,
   the original finalization unchanged (BR-36);
3. a `CONCLUDED` Encounter whose Care Authorization is not `ACTIVE` — `23514`,
   hint `CARE_AUTHORIZATION_INACTIVE`;
4. a revision other than the current one — hint `STALE_REVISION` as a plain
   application error (never `40001` or `409`);
5. missing clinical content, missing category, or `OTHER` without its context
   (BR-17, BR-18, `SPEC-MED-006` BR-17) — `23514`, hint `ENTRY_INCOMPLETE`;
6. a current `PENDING` Clinical Attachment — `23514`, hint
   `PENDING_ATTACHMENT`; a current `AVAILABLE` Attachment whose stored object is
   missing — `23514`, hint `ATTACHMENT_UNAVAILABLE` (`SPEC-MED-007`). Having no
   Attachment never blocks finalization;
7. finalization.

The result is `FINALIZED` or `ALREADY_FINALIZED`, with `entry_id` and
`finalized_at`; never clinical content. A failed finalization leaves the Draft
unchanged (BR-35).

The pre-existing `finalize_clinical_record_entry(uuid, bigint)` is not a client
path. Client `EXECUTE` is withdrawn; it remains the trusted writer.

### BR-38 — Finalization is Guardian publication

Finalization is the exact event that makes the Entry part of the Pet's
finalized history and visible to authorized Guardians (BR-4, BR-31,
`SPEC-MED-005`). It requires neither a `COMPLETED` Appointment nor a
`CONCLUDED` Encounter, and it changes neither (BR-23). A Draft is never visible
to a Guardian.

### Mobile presentation

- **Finalize / Finalizar** is enabled only when the Draft has non-blank content,
  a category, and the `OTHER` context when needed; the check is advisory.
- Before finalizing, a review shows the Entry and states:
  "Al finalizar, esta entrada será visible para los responsables de la mascota
  y ya no podrá editarse directamente. Revisa el contenido antes de
  continuar." / "Once finalized, this entry will be visible to the pet's
  guardians and can no longer be edited directly. Review the content before you
  continue." It never says the Appointment will be completed, the care
  finished, or the record closed, and never promises an in-app correction
  workflow.
- After `FINALIZED`, `ALREADY_FINALIZED`, or an uncertain response, the client
  re-reads; a re-read showing the Entry finalized is reported neutrally as a
  success. A finalized Entry is read-only; its only follow-up is an Amendment
  (`SPEC-MED-004` §15), and its read-only note may say so ("Si necesitas
  corregirla, añade una corrección." / "If you need to correct it, add an
  amendment.").

## 16. Phase 1 Appointment-keyed Finalize Verification Notes

In addition to §14, verification must demonstrate that:

21. a Draft with content and category is finalized by the responsible or
    another currently assigned Veterinarian, recording that finalizer;
22. missing content, missing category, and `OTHER` without context are
    rejected with `ENTRY_INCOMPLETE` and the Draft is unchanged;
23. a stale revision is rejected with `STALE_REVISION`;
24. finalizing an already finalized Entry returns `ALREADY_FINALIZED` without
    changing its finalization time or finalizer;
25. a current `PENDING` Attachment blocks finalization and no Attachment never
    does;
26. the Guardian medical history shows the Entry immediately after
    finalization, while the Appointment is still `CONFIRMED` and the Encounter
    still `ACTIVE`, and never shows a Draft;
27. finalization leaves the Appointment and Encounter lifecycles unchanged;
28. no client role executes the generic finalization operation.
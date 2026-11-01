# SPEC-MED-005 — View Pet Medical History

**Status:** APPROVED  
**Requirements:** REQ-MED-001, REQ-MED-002, REQ-MED-004, REQ-MED-005, REQ-MED-010  
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the §15 history window (BR-40) is replaced by SPEC-MED-010 BR-14 (no Encounter condition; denied after completion or revocation), and the projection, ordering (BR-42), and payload field `encounter_started_at` (BR-43) by SPEC-MED-010 BR-22. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized User to view a Pet's longitudinal finalized medical
history across participating veterinary providers.

The medical history belongs to the Pet.

It may contain clinical information originating from different:

- Veterinarians;
- Clinics;
- Veterinary Organizations;
- Clinical Encounters;
- periods of care.

Every clinical contribution must preserve its original provenance.

Draft clinical information must not appear as finalized medical history.

---

## 2. Preconditions

- The Pet exists.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a current authorization basis that permits viewing the
  applicable medical information.
- Zero or more Finalized Clinical Record Entries may exist for the Pet.
- Zero or more Clinical Amendments may exist for those Entries.

For Phase 1, a valid viewing context may arise through:

- an active Guardianship relationship with the Pet; or
- an applicable authorized professional medical-access context.

---

## 3. Business Rules

### BR-1 — Medical history belongs to the Pet

The longitudinal medical history must be associated with the Pet domain
identity.

It must not belong exclusively to:

- a Guardian;
- a Veterinarian;
- a Clinic;
- a Veterinary Organization;
- an Appointment.

The same Pet history continues across changes in care provider and
Guardianship.

---

### BR-2 — Medical history contains finalized clinical information

Normal longitudinal medical-history views must contain finalized clinical
information.

Draft Clinical Record Entries must not be presented as finalized medical
history.

---

### BR-3 — Draft Clinical Record Entries are excluded

A User viewing normal longitudinal medical history must not receive Draft
Clinical Record Entries through this workflow.

Draft clinical information remains protected internal professional working
information according to `SPEC-MED-002`.

---

### BR-4 — Applicable Clinical Amendments are part of the history

When a Finalized Clinical Record Entry has one or more Clinical Amendments,
those Amendments form part of the longitudinal medical history.

The history must preserve the relationship between:

- the original finalized Entry;
- its subsequent Amendments.

---

### BR-5 — Clinical provenance must remain visible and meaningful

Every finalized clinical contribution must preserve enough provenance to
establish, where applicable:

- the Pet;
- relevant clinical event date or time;
- responsible professional context;
- original author;
- Clinic;
- Veterinary Organization;
- Clinical Encounter;
- finalization information;
- applicable Amendment information.

The exact visual presentation is a UI concern.

---

### BR-6 — Multi-clinic history must be supported

The medical history may contain finalized information from multiple Clinics
and Veterinary Organizations.

For example:

    Luna

    2026
    Animalia Madrid Centro
    Dr. Garcia
    Vaccination

    2027
    VetCare Toledo
    Dr. Lopez
    Surgery

    2028
    Animalia Getafe
    Dr. Ruiz
    Examination

These contributions form one longitudinal history for Luna.

---

### BR-7 — Provider boundaries remain preserved

Combining clinical information into one Pet history must not flatten provider
provenance.

A record created by Animalia Madrid Centro must remain identifiable as an
Animalia Madrid Centro contribution even when viewed:

- by the Guardian;
- by VetCare Toledo;
- years later;
- after the original Veterinarian has changed employer.

---

### BR-8 — Active Guardians may view the Pet's finalized history in Phase 1

In the Phase 1 Guardianship model, an active Guardian may view the finalized
longitudinal medical history of the Pet.

The Guardian does not need to:

- have registered the Pet originally;
- have requested the relevant Appointment;
- have attended the relevant Clinic;
- have personally granted every historical Care Authorization.

Current active Guardianship provides the applicable personal Pet relationship
for normal Guardian history access.

---

### BR-9 — Pet creator status does not determine history access

The User who originally registered the Pet does not receive special permanent
medical-history access solely because they created the Pet record.

Current authorization determines access.

---

### BR-10 — Shared Guardians view the same Pet history

When several Users have active Guardianship relationships with the same Pet,
they view the medical history of the same Pet domain entity.

The system must not create separate medical histories per Guardian.

Conceptually:

    Maria ─────┐
               │
               ▼
              Luna
               │
               ▼
        Medical History
               ▲
               │
    Carlos ────┘

---

### BR-11 — Former Guardians do not retain permanent history access

If a User no longer has an active Guardianship relationship with the Pet, they
must not retain normal Guardian medical-history access solely because:

- they previously were a Guardian;
- they registered the Pet;
- they requested an Appointment;
- they previously viewed the medical history.

Historical relationship does not imply current authorization.

---

### BR-12 — Professional history access requires an explicit current medical-access basis

Veterinarian status, Organization Membership, Clinic Assignment, or
Appointment Assignment alone must not grant access to the Pet's medical
history.

Professional access must follow the applicable Medical Access Control
Specifications.

---

### BR-13 — Care Authorization may support professional longitudinal-history access

A valid current Pet Care Authorization may allow appropriately authorized
professional actors to access relevant longitudinal medical history for the
authorized care purpose.

This may include finalized information originating from other participating
Clinics.

---

### BR-14 — Professional access remains subject to least privilege

A valid Care Authorization does not necessarily mean every professional actor
may view every item in the Pet's history.

The acting User's current professional or operational context must also justify
the requested access.

Medical information returned through a professional view must be limited to
the scope required by the authorized purpose.

---

### BR-15 — Appointment existence alone grants no history access

The existence of a requested or confirmed Appointment must not independently
authorize a User to view protected medical history.

Where professional history access is needed to prepare or provide care, the
applicable Care Authorization and actor context must support it.

---

### BR-16 — Revocation affects current professional history access

When a Care Authorization is revoked, professional actors must no longer use
that authorization as the normal basis for medical-history access.

Any limited access required to safely conclude an already-started Clinical
Encounter follows `SPEC-ACC-002`.

---

### BR-17 — Ended Care Authorization is not permanent professional access

A Clinic that previously treated the Pet must not receive indefinite access to
the Pet's complete longitudinal history solely because a past Care
Authorization once existed.

Current access requires a current valid basis.

Historical authorization remains traceable without granting current access.

---

### BR-18 — Viewing history does not grant modification authority

Being authorized to view a Finalized Clinical Record Entry must not
automatically allow the Viewer to:

- edit it;
- amend it;
- delete it;
- change its provenance;
- change its Pet;
- change its author.

Read authorization and clinical modification authority are separate
capabilities.

---

### BR-19 — Cross-clinic viewing does not transfer authorship

When a Clinic views information created by another Clinic, the viewing Clinic
must not become:

- the author;
- the provider of origin;
- the Veterinary Organization of origin.

Viewing does not alter historical provenance.

---

### BR-20 — Historical professional changes do not rewrite the history

If a Veterinarian later changes:

- Clinic;
- Veterinary Organization;
- current employment;
- Clinic Assignment;

previously finalized clinical information remains attributed to the
professional and provider context in which it was originally recorded.

---

### BR-21 — Clinical history should be organized by clinically relevant chronology

The longitudinal history should be capable of being presented according to the
clinically relevant occurrence dates of its entries.

Draft creation time or finalization time must not automatically replace the
actual clinical event date as the primary historical chronology.

The exact secondary ordering of records with equivalent timestamps is a
presentation concern.

---

### BR-22 — Clinical Encounter may provide grouping context

Finalized Clinical Record Entries originating from the same Clinical Encounter
may be presented together as one care episode.

For example:

    10 September 2026
    Animalia Madrid Centro
    Dr. Garcia

    ├── Examination
    ├── Diagnosis-related information
    └── Treatment-related information

The individual Clinical Record Entries remain independently identifiable.

---

### BR-23 — Encounter grouping must not collapse independent Entries

Grouping several Clinical Record Entries under one Clinical Encounter must not
merge their:

- identities;
- authorship;
- event categories;
- Amendments;
- clinical content.

Grouping is a representation of shared care context.

It is not a destructive merge.

---

### BR-24 — Encounter context must not expose Draft content

A Clinical Encounter may provide contextual information for visible finalized
history.

The existence of that Encounter must not cause Draft Clinical Record Entries
to become visible through the normal history view.

---

### BR-25 — Amendments must not be silently flattened into the original history

When a Clinical Record Entry has been amended, the system may provide a useful
current clinical interpretation.

However, it must remain possible for an authorized Viewer to establish:

- what was originally finalized;
- that an Amendment occurred;
- what the Amendment changed or clarified;
- who created the Amendment;
- when it occurred.

---

### BR-26 — Current interpretation must remain traceable

Where the product derives a current interpretation from an original Entry and
its Amendments, that interpretation must remain traceable to the underlying
clinical history.

A simplified current view must not destroy historical truth.

---

### BR-27 — New clinical understanding is not an Amendment by default

Separate Finalized Clinical Record Entries representing later legitimate
changes in medical understanding must remain distinct entries in chronology.

The history must not incorrectly present legitimate clinical evolution as
though the earlier provider's information was destructively corrected.

---

### BR-28 — Medical history survives subscription termination

Loss or termination of an Organization's commercial subscription must not
remove its historical finalized clinical contributions from the Pet's
longitudinal history.

---

### BR-29 — Medical history survives Clinic unpublication

Unpublishing a Clinic must not remove its historical clinical contributions
from the Pet's medical history.

Public Clinic Discovery and historical clinical provenance are separate
concerns.

---

### BR-30 — Medical history survives Clinic closure

If a Clinic later ceases operation, its historical clinical contributions must
remain identifiable in the Pet's medical history.

Closure must not cause historical records to be reassigned to another Clinic.

---

### BR-31 — Pet profile changes do not create a new medical history

Changing mutable Pet profile information such as:

- name;
- profile image;
- breed information;
- other non-identity profile data

must not create a separate medical history.

The history continues to belong to the same Pet domain identity.

---

### BR-32 — Accessing history does not create new clinical information

Viewing the Pet's medical history must not itself create:

- a Clinical Encounter;
- a Clinical Record Entry;
- a Clinical Amendment;
- a diagnosis;
- a Treatment;
- another medical statement.

Viewing is a read operation.

---

### BR-33 — Medical-history access may be auditable

The system must be capable of recording relevant access to sensitive medical
information where required by the applicable audit policy.

The absence of an explicit access-audit presentation in the medical history
must not prevent access auditing from occurring separately.

Detailed medical-access auditing is governed by the Access Control and Audit
Specifications.

---

### BR-34 — Restricted professional views must not imply completeness

When least-privilege rules return only a subset of the Pet's medical history
for a professional purpose, the system must not represent that subset as a
complete longitudinal history if doing so would be misleading.

The Viewer context must remain distinguishable from the underlying complete Pet
history.

---

### BR-35 — Empty medical history is valid

A Pet may have no Finalized Clinical Record Entries.

An authorized history request in that situation must succeed with an empty
medical history.

Absence of finalized history is not an error.

---

### BR-36 — History retrieval must preserve internal consistency

A medical-history representation must not combine clinical information in a
way that produces contradictory provenance relationships.

For example, an Amendment must remain associated with the correct Finalized
Clinical Record Entry and provider context.

The exact consistency and transaction mechanism is architectural.

---

### BR-37 — Phase 1 general professional longitudinal history is Veterinarian clinical-context access

The general Phase 1 professional longitudinal-history view is available only to
a Veterinarian acting in `PROFESSIONAL_CLINICAL` context with an authenticated
coherent domain User, that User's Veterinarian Professional Profile, a current
exact-Clinic Veterinarian Clinic Assignment, current applicable Membership and
`VETERINARIAN` responsibility, `CLINICAL_CARE` Clinic capability, current
Organization `CLINICAL_CARE` Entitlement, an `ACTIVE` Care Authorization for
the exact Pet and accessing provider context, and least-privilege clinical
purpose.

The permitted result is the complete Phase 1 finalized longitudinal clinical
model: Finalized Clinical Record Entries, applicable Clinical Amendments, and
their clinical, provider, and professional provenance, including authorized
cross-provider history. It excludes Drafts and Phase 1 Attachment binaries.

Receptionists, Administrators, `CLINIC_OPERATIONAL` context, bare Membership,
Professional Profile alone, Clinic Assignment alone, and Appointment Assignment
alone do not receive unrestricted longitudinal history through this use case.
Any future operational or triage projection requires a separately approved
least-privilege scope; this Specification does not invent field-level triage
visibility.

Revocation, Entitlement loss, or Encounter conclusion does not turn safe
Encounter-scoped continuity into general longitudinal-history permission.

---

## 4. Medical History Representation

The longitudinal medical history must support enough information for an
authorized Viewer to understand what happened clinically and where the
information originated.

For each visible finalized clinical contribution, the representation should
support, where applicable:

- clinical event date or time;
- clinical event category;
- finalized clinical content;
- Clinical Encounter context;
- responsible professional;
- original clinical author;
- Clinic;
- Veterinary Organization;
- applicable Clinical Amendments.

The exact UI layout is outside this Specification.

---

## 5. Scenarios

### Scenario: Guardian views longitudinal history from several Clinics

Given Maria has an active Guardianship relationship with Luna  
And Luna has finalized clinical information from Animalia Madrid Centro  
And Luna has finalized clinical information from VetCare Toledo  
And Luna has finalized clinical information from Animalia Getafe

When Maria views Luna's medical history

Then the applicable finalized information from all three Clinics is available  
And all information belongs to the same Luna Pet domain entity  
And each clinical contribution preserves its original Clinic provenance  
And each contribution preserves its applicable professional provenance

---

### Scenario: Two Guardians view the same medical history

Given Maria has an active Guardianship relationship with Luna  
And Carlos also has an active Guardianship relationship with Luna  
And Luna has finalized medical history

When Maria views Luna's medical history  
And Carlos views Luna's medical history

Then both Users access the medical history of the same Luna Pet  
And separate copies of Luna's clinical history are not created per Guardian

---

### Scenario: User who did not register Pet may view history as current Guardian

Given Maria originally registered Luna  
And Carlos later became an active Guardian of Luna

When Carlos views Luna's medical history

Then Carlos may access Luna's finalized history according to the Phase 1
Guardian rules  
And Carlos does not need to have originally registered Luna

---

### Scenario: Former Guardian cannot continue normal history access

Given Carlos previously had Guardianship of Luna  
And Carlos's Guardianship has ended  
And Carlos has no other applicable medical-access basis

When Carlos attempts to view Luna's protected medical history

Then access is denied  
And historical Guardianship alone is insufficient

---

### Scenario: Guardian does not see Draft Clinical Record Entry

Given Luna has a Draft Clinical Record Entry  
And Maria is an active Guardian of Luna

When Maria views Luna's normal medical history

Then the Draft is not included as finalized medical history

---

### Scenario: Finalized Entry becomes visible to Guardian

Given Luna has a Draft Clinical Record Entry  
And Maria is an active Guardian of Luna

When the Entry is validly finalized  
And Maria subsequently views Luna's medical history

Then the finalized Entry may be included  
And its clinical provenance is preserved

---

### Scenario: Guardian sees Amendment with original clinical record

Given Luna has a Finalized Clinical Record Entry  
And that Entry was later amended  
And Maria is an authorized Guardian of Luna

When Maria views Luna's medical history

Then the applicable Clinical Amendment is available with the related history  
And the system does not misleadingly present the superseded original
information as the only current interpretation  
And the original historical Entry remains traceable

---

### Scenario: Authorized Clinic accesses relevant cross-clinic history

Given Luna previously received care at Animalia Madrid Centro  
And Animalia finalized clinical information for Luna  
And Luna later has an active Care Authorization for VetCare Toledo  
And Dr. Lopez has an authorized professional care context at VetCare Toledo

When Dr. Lopez accesses Luna's relevant longitudinal history

Then applicable finalized Animalia information may be available  
And Animalia remains the Clinic of origin  
And the original clinical authors remain identifiable  
And VetCare does not become the author of that history

---

### Scenario: Veterinarian status alone cannot access history

Given Dr. Lopez has a Veterinarian Professional Profile  
And Dr. Lopez has no applicable current medical-access basis for Luna

When Dr. Lopez attempts to view Luna's protected medical history

Then access is denied  
And Veterinarian status alone is insufficient

---

### Scenario: Clinic Assignment alone cannot access history

Given Dr. Lopez has a current Clinic Assignment at VetCare Toledo  
And no valid Care Authorization or other applicable medical-access basis exists
for Luna

When Dr. Lopez attempts to access Luna's protected medical history

Then access is denied  
And Clinic Assignment alone is insufficient

---

### Scenario: Appointment alone cannot access history

Given Luna has an Appointment at VetCare Toledo  
And the required Care Authorization is absent or revoked  
And no other valid medical-access basis exists

When a professional attempts to view Luna's history solely because the
Appointment exists

Then access is denied

---

### Scenario: Revoked Care Authorization ends normal professional history access

Given VetCare Toledo previously had a valid Care Authorization for Luna  
And that authorization has been revoked  
And no limited active-care continuity or other valid access basis applies

When a VetCare professional attempts to access Luna's protected history through
the revoked authorization

Then access is denied

---

### Scenario: Operational actor cannot use the general longitudinal-history view

Given Luna has a valid Care Authorization at Animalia Madrid Centro  
And Carlos has a limited operational role for Appointment triage  
And Carlos does not have the required Veterinarian clinical context

When Carlos attempts to use the general professional longitudinal-history view

Then access to that longitudinal-history view is denied
And Care Authorization alone does not provide unrestricted history access
And any future triage projection requires separately approved least-privilege
scope

---

### Scenario: Clinical history remains attributed after Veterinarian changes employer

Given Dr. Garcia finalized clinical information for Luna while practicing at
Animalia Madrid Centro  
And Dr. Garcia later joins VetCare Group

When Luna's historical medical record is viewed

Then the clinical information remains attributed to Dr. Garcia  
And it remains attributed to Animalia Madrid Centro  
And it remains attributed to Animalia Veterinary Group  
And the later employment relationship does not rewrite the history

---

### Scenario: Clinic unpublication does not remove medical history

Given Animalia Madrid Centro finalized clinical information for Luna  
And the Clinic is later unpublished

When an authorized User views Luna's medical history

Then the historical Animalia clinical contribution remains available according
to the applicable access rules  
And unpublication does not erase clinical provenance

---

### Scenario: Subscription termination does not remove medical history

Given Animalia Veterinary Group contributed finalized clinical information to
Luna's history

When Animalia's subscription later ends

Then those finalized historical contributions remain part of Luna's medical
history  
And their provenance remains unchanged

---

### Scenario: History is organized by clinical occurrence

Given Luna has one clinical event that occurred on 2026-09-10  
And its record was finalized on 2026-09-11  
And Luna has another clinical event that occurred on 2026-09-12

When Luna's longitudinal history is presented chronologically

Then the clinically relevant occurrence dates may determine the historical
sequence  
And finalization time does not silently replace clinical event time

---

### Scenario: Several Entries from the same Encounter may be grouped

Given Luna has a Clinical Encounter at Animalia Madrid Centro  
And that Encounter contains a finalized examination Entry  
And a finalized treatment-related Entry

When an authorized User views Luna's medical history

Then the Entries may be presented within the same Encounter context  
And each Entry retains its own identity  
And each Entry retains its own clinical content and provenance

---

### Scenario: Encounter grouping does not expose Draft Entry

Given Luna has a Clinical Encounter containing one Finalized Entry  
And another Entry in the same Encounter remains `DRAFT`

When Maria views Luna's normal medical history

Then the Finalized Entry may be shown  
And the Draft Entry is not exposed merely because both belong to the same
Encounter

---

### Scenario: New clinical interpretation remains chronological history

Given Animalia previously finalized one clinical interpretation for Luna  
And VetCare later records a different valid clinical interpretation based on
new evidence

When Luna's longitudinal history is viewed

Then both clinical contributions remain historically identifiable  
And the later information does not destructively rewrite the earlier provider's
record

---

### Scenario: Pet with no finalized history

Given Maria has an active Guardianship relationship with Luna  
And Luna has no Finalized Clinical Record Entries

When Maria views Luna's medical history

Then the history is empty  
And the operation succeeds

---

## 6. Guardian Medical History View

The normal Phase 1 Guardian history represents the Pet's finalized longitudinal
medical history rather than the history of a particular Guardian.

Conceptually:

    Luna
      │
      ├── Animalia Madrid Centro
      │     Dr. Garcia
      │     Finalized clinical information
      │
      ├── VetCare Toledo
      │     Dr. Lopez
      │     Finalized clinical information
      │
      └── Animalia Getafe
            Dr. Ruiz
            Finalized clinical information

An active Guardian may access this Pet history according to the applicable
Guardian medical-access rules.

The history does not reset when Guardians change.

---

## 7. Professional Medical History View

Professional access to longitudinal history differs from Guardian access.

A Phase 1 Viewer through this use case must satisfy the Veterinarian clinical
context defined by BR-37.

Conceptually:

    valid Care Authorization
              +
    valid Veterinarian clinical actor context
              +
    current CLINICAL_CARE capability and Entitlement
              +
    least-privilege scope
              ↓
    permitted complete Phase 1 finalized Pet history

The existence of the complete longitudinal Pet history does not imply that
every professional Viewer receives every element of it.

---

## 8. Clinical Provenance in History

The product must make it possible to understand who contributed each
clinically meaningful part of the history.

For example:

    Luna

    10 September 2026

    Animalia Madrid Centro
    Animalia Veterinary Group

    Responsible Veterinarian:
    Dr. Garcia

    Examination:
    Finalized by Dr. Garcia


    15 March 2027

    VetCare Toledo
    VetCare Group

    Responsible Veterinarian:
    Dr. Lopez

    Procedure:
    Finalized by Dr. Lopez

The exact visual wording is a UI concern.

The domain requirement is preservation of provenance.

---

## 9. Amendments in History

An amended record must support both current clinical usefulness and historical
traceability.

For example:

    Original Entry
    Dose: 50 mg

    Amendment
    Reason: documentation error
    Correct dose: 5 mg

The product may emphasize 5 mg as the corrected current information.

It must nevertheless remain possible for an authorized Viewer to establish
that:

- 50 mg was originally finalized;
- the record was subsequently amended;
- 5 mg is the correction;
- the Amendment has its own professional provenance.

---

## 10. Edge Cases

### Very large longitudinal history

A Pet may accumulate a large medical history over many years and providers.

Pagination, incremental loading, search, and filtering may be required for
performance and usability.

Those mechanisms must not change the meaning or provenance of clinical
information.

---

### Several events share the same clinical timestamp

Several clinical contributions may have identical or effectively equivalent
event timestamps.

No clinically meaningful ordering between such Entries is defined solely by
this Specification.

A stable secondary ordering may be introduced architecturally.

---

### Original provider no longer operates

A historical provider may no longer have an active subscription or may no
longer operate.

Its finalized clinical contributions remain part of the Pet's history.

---

### Current professional sees only part of history

Least-privilege rules may intentionally limit the information available to a
particular professional context.

The resulting representation must not falsely imply that omitted information
does not exist when that implication would be clinically misleading.

---

### Guardian relationship ends while history is already displayed

Current authorization must be evaluated for subsequent protected operations.

Previously rendered client state must not become a source of permanent
authorization.

Client synchronization and cache invalidation are architectural concerns.

---

### Incorrect-Pet historical record

A finalized Entry associated with the wrong Pet must not be fixed through the
normal history-view workflow.

That condition requires the dedicated auditable correction behavior defined
separately when supported.

---

### Specialized medical models are introduced later

Future Treatments, Vaccinations, Prescriptions, Laboratory Results, Imaging,
or other dedicated medical models may contribute structured information to the
same longitudinal history.

Introducing specialized models must not fragment the Pet's medical history
into unrelated provider-specific timelines.

---

## 11. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-PET-003 — Accept Guardianship Invitation
- SPEC-PET-004 — View My Pets
- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-004 — Amend Finalized Clinical Record Entry
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-ID-003 — Authenticate User

---

## 13. Out of Scope

This Specification does not define:

- Draft clinical-information viewing;
- clinical event taxonomy;
- medical-history search;
- medical-history filtering;
- pagination, beyond the Phase 1 client contract of §15;
- clinical attachments;
- attachment download behavior;
- dedicated Treatment views;
- dedicated Vaccination views;
- dedicated Prescription views;
- Laboratory Result views;
- Imaging views;
- medical-history export;
- medical-history sharing outside normal authorization;
- access-event audit presentation;
- emergency medical access;
- incorrect-Pet historical correction;
- legal retention periods.

---

## 14. Verification Notes

Verification must demonstrate that:

1. longitudinal medical history is associated with the Pet rather than a
   provider or Guardian;
2. only finalized clinical information participates in normal longitudinal
   history;
3. Draft Clinical Record Entries are excluded;
4. applicable Clinical Amendments participate in the history;
5. clinical provenance remains available and meaningful;
6. finalized history may contain contributions from multiple Clinics and
   Veterinary Organizations;
7. provider boundaries and original attribution remain preserved;
8. active Phase 1 Guardians may view the same shared Pet history;
9. original Pet creator status does not determine history access;
10. former Guardians do not retain normal history access solely through
    historical Guardianship;
11. professional access requires an applicable explicit current medical-access
    basis;
12. Veterinarian status, Clinic Assignment, and Appointment existence alone are
    insufficient for professional history access;
13. professional history access remains subject to least privilege;
14. revoked or ended Care Authorization does not provide indefinite normal
    professional access;
15. viewing information does not grant modification authority;
16. cross-clinic viewing does not transfer authorship or provider provenance;
17. employment and provider changes do not rewrite finalized history;
18. clinically relevant event time remains distinguishable from creation and
    finalization time;
19. Entries may be grouped by Clinical Encounter without losing independent
    identity;
20. Encounter grouping does not expose Draft information;
21. original Entries and applicable Amendments remain historically traceable;
22. legitimate later changes in clinical understanding remain separate
    chronological clinical contributions;
23. Clinic unpublication, closure, and subscription termination do not erase
    historical clinical information;
24. Pet profile changes do not create a separate medical history;
25. an empty finalized medical history is a valid result;
26. restricted professional views must not misleadingly imply completeness;
27. medical-history retrieval preserves consistent clinical provenance.
28. the general professional longitudinal-history view is restricted to the
    complete current Veterinarian clinical context defined by BR-37, and
    operational Clinic roles do not receive unrestricted history through it.

---

## 15. Phase 1 Appointment-keyed professional history contract

Defined by **Professional Longitudinal / Cross-Clinic Medical History — Phase
1**. It narrows BR-12–BR-17, BR-33, BR-34 and BR-37 for the mobile client; it
does not change them. Like every other Phase 1 professional clinical operation
(`SPEC-MED-001` BR-37), it is keyed by the Clinic and Appointment the
Professional client already shows.

### BR-38 — Canonical read

    view_appointment_professional_medical_history(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_limit integer default 50,
        p_before_history_order_at timestamptz default null,
        p_before_entry_id uuid default null
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, is `VOLATILE` because it
writes Medical Access Audit Events, and is executable only by `authenticated`
(not `anon`, not `service_role`). It takes no Pet, Care Authorization,
Encounter, User, Membership, Clinic Assignment, or Organization identifier.
The server derives the Organization from the Clinic, the Pet from the
Appointment, the Appointment-derived Care Authorization (unique per
Appointment), its Clinical Encounter (unique per Care Authorization), and the
acting Veterinarian's context.

The pre-existing `view_professional_pet_medical_history` (client-supplied Pet,
Care Authorization and Encounter identifiers, internal identifiers in its
result) is not a client path: `authenticated` `EXECUTE` is withdrawn.

### BR-39 — Authority before existence

The read decides, in this order:

1. authentication and a coherent domain User — otherwise `28000`;
2. argument shape only, depending on no stored data: `p_limit` at least 1 (a
   larger value is capped at 100) — otherwise `22023`, hint `INVALID_LIMIT`;
   both cursor halves present or both absent, and a finite time — otherwise
   `22023`, hint `INVALID_CURSOR`;
3. the acting User's current exact-Clinic Veterinarian context at the named
   Clinic — current Membership, current Organization-scoped `VETERINARIAN`
   Responsibility, own Veterinarian Professional Profile, current Clinic
   Assignment at that Clinic — holding the `CLINICAL_CARE` capability, and the
   Organization's current `CLINICAL_CARE` Entitlement (BR-37);
4. the Appointment, which must belong to that Clinic;
5. the Pet, the Appointment-derived `APPOINTMENT_CARE` Care Authorization and
   its Encounter, if any;
6. the history window (BR-40).

Any failure of steps 3–6 returns exactly `{"status": "DENIED"}`. An unknown or
foreign Clinic, an unknown Appointment, an Appointment of another Clinic or
Organization, missing authority, a missing Entitlement and a closed window are
indistinguishable: no hint, no count, no cursor, no Clinic name.

The read does not require an Appointment Veterinarian Assignment, Veterinarian
Availability, being the Encounter's responsible Veterinarian, or authorship of
any Entry.

### BR-40 — History window

History is permitted only when the Appointment-derived Care Authorization is
`ACTIVE` and either:

- no Encounter exists for it and the Appointment permits pre-care access — it
  is `CONFIRMED`, or `REQUESTED` with its latest requested start strictly in
  the future (`SPEC-ACC-001` BR-8, BR-26, BR-39); or
- its Encounter is `ACTIVE` (`SPEC-ACC-001` BR-28, BR-42; `SPEC-ACC-002`
  BR-55).

| Appointment | Encounter | Care Authorization | History |
|---|---|---|---|
| `REQUESTED`, start in the future | none | `ACTIVE` | permitted |
| `REQUESTED`, start passed | none | `ACTIVE` | denied |
| `CONFIRMED` | none | `ACTIVE` | permitted |
| `CONFIRMED` | `ACTIVE` | `ACTIVE` | permitted |
| `CONFIRMED` | `CONCLUDED` | `ACTIVE` | denied |
| `COMPLETED` | none | `ACTIVE` | denied |
| `COMPLETED` | `ACTIVE` | `ACTIVE` | permitted |
| `COMPLETED` | `CONCLUDED` | `ACTIVE` | denied |
| any | any | `REVOKED` or `ENDED` | denied |
| `CANCELLED`, `NO_SHOW`, `EXPIRED` | — | — | denied |

Guardian revocation denies history immediately, also during an `ACTIVE`
Encounter: the revocation-safe continuity of `SPEC-ACC-002` BR-19/BR-20 and
`SPEC-MED-009` BR-4 stays limited to that Encounter's own clinical record.
Loss of the `CLINICAL_CARE` Entitlement likewise denies history, also during an
`ACTIVE` Encounter (BR-37); the Encounter's own record keeps its
`SPEC-MED-009` continuity.

A `COMPLETED` Appointment documented retrospectively has no history before its
Encounter is established, has it while that Encounter is `ACTIVE`, and loses it
once the Encounter is `CONCLUDED`.

Known unresolved policy, unchanged here: a `CONFIRMED` Appointment that is never
resolved after its scheduled time keeps permitting pre-care access while its
Care Authorization stays `ACTIVE`.

An Encounter without an Appointment (Clinical Intake) cannot be the root of
this read.

### BR-41 — Content: the complete cross-provider finalized history

Once permitted, the read returns every `FINALIZED` Clinical Record Entry of the
Pet from every Clinic and Veterinary Organization, each with its Clinical
Amendments. Content is never filtered by the accessing Clinic or Organization;
a Care Authorization at another Clinic, its state, and other Clinics'
Appointments neither add nor remove content (BR-13, `SPEC-ACC-001` BR-4,
BR-5). A Care Authorization at Clinic A never lets a Veterinarian act through
Clinic B.

Drafts, Encounters without a `FINALIZED` Entry, and other Pets never appear,
and no other Clinic's Care Authorization or Appointment is disclosed. Because
the complete Phase 1 finalized history is returned (BR-37), the result is not
a restricted subset (BR-34). Clinical Attachments — metadata and content — are
not part of this read (`SPEC-MED-007`).

### BR-42 — Ordering and pagination

Entries are ordered by `history_order_at = coalesce(clinical_event_at,
Encounter started_at)` descending, then Entry identity descending (§10).
Finalization time is never the primary chronology (BR-21), and an Amendment
never moves its Entry.

Pagination is keyset: `cursor` is `{before_history_order_at, before_entry_id}`
of the last returned Entry, or `null` when no further Entry exists. The default
page is 50 Entries, the maximum 100. Every page re-evaluates BR-39 and BR-40.
Amendments are nested in their Entry, oldest first (creation time, then
identity), at most 100, with `amendment_count` and `amendments_truncated`.

### BR-43 — Payload

    {"status": "PERMITTED", "entries": [...], "cursor": {...} | null}

Each Entry carries only: `entry_id`, `category`, `other_category_context`,
`clinical_content`, `clinical_event_at`, `history_order_at`, `finalized_at`,
`encounter_started_at`, `clinic_display_name`, `organization_display_name`,
`is_this_appointment`, `author`, `finalizer`, `amendments`,
`amendment_count`, `amendments_truncated`. `author` and `finalizer` are
`{display_name, is_me}`; `finalizer` is `null` when the Entry was finalized by
its author's own User. Each Amendment carries only `amendment_id`, `reason`,
`amendment_content`, `created_at` and `author`.

`clinic_display_name` is the originating Clinic's public-profile display name,
independent of its publication state (BR-29); `organization_display_name` is
the originating Organization's display name.

No User, authentication, Membership, Responsibility Grant, Clinic Assignment,
Care Authorization, Encounter, Clinic or Organization identifier, no other
Appointment identifier, no `draft_revision`, `last_modified_at`, Entry
creation time or Attachment metadata is returned.

### BR-44 — Veterinarian provenance identity

Each provenance role — the Entry's creator (its original author, who is the
Encounter's responsible Veterinarian), the Entry's finalizer, and each
Amendment's author — is resolved through the User historically recorded on that
clinical fact. `display_name` is that User's current User Profile display name,
trimmed, or `null` when absent or blank; the client then shows a neutral
**Veterinario / Veterinarian**.

Resolution never requires that person's current Membership, `VETERINARIAN`
Responsibility, Clinic Assignment or Professional Profile: offboarding does not
remove the name, and a renamed User shows the current name (`SPEC-ID-006`
BR-23). No historical snapshot is kept. No authentication email, Invitation
address, registration identifier, credential fact or identifier is returned,
and no professional title is added: the display name is self-entered and
unverified (`SPEC-ID-006` BR-17). `is_me` is relative to the reader.

This visibility is `SPEC-ID-006` BR-41. Guardians do not receive Veterinarian
names through any read (BR-46).

### BR-45 — Audit

A permitted page creates exactly one Medical Access Audit Event
(`SPEC-ACC-003` BR-48, BR-49), written before the history is released:
operation `VIEW_PET_MEDICAL_HISTORY`, actor context `PROFESSIONAL_CLINICAL`,
scope `LONGITUDINAL_MEDICAL_HISTORY`, with the Pet, Care Authorization,
accessing Clinic and Organization, Appointment, Encounter where one exists, and
the acting Membership, Responsibility Grant and Clinic Assignment — the current
access context, never the identities of historical authors. Never one per
Entry, Amendment or contributing Clinic.

A denied read whose Appointment belongs to the named Clinic creates one `DENIED`
event of the same operation and scope, with the Pet, Clinic, Organization,
Appointment, Care Authorization where present, and the professional context
where one exists (`SPEC-ACC-003` BR-55). An unknown Appointment, or one of
another Clinic, establishes no Pet context and creates none (`SPEC-ACC-003`
BR-56). If the audit event cannot be written, no history is returned
(`SPEC-ACC-003` BR-37).

### BR-46 — Guardian history payload

The Guardian read keeps its signature, authorization, audit, ordering and
cursor, and is built from the same private finalized-history projection. Each
Guardian Entry carries only `id`, `category`, `other_category_context`,
`clinical_content`, `clinical_event_at`, `history_order_at`, `finalized_at`,
`encounter_started_at`, `clinic_display_name`, `organization_display_name`,
`amendments` (`id`, `reason`, `amendment_content`, `created_at`),
`amendment_count`, `amendments_truncated` and `attachments` (the existing
Guardian Attachment metadata). It carries no User, Clinic Assignment,
Encounter, Clinic or Organization identifier, no `draft_revision` or
`last_modified_at`, and no Veterinarian name.

### BR-47 — Read only

The read changes nothing but the audit trail and offers no modification
(BR-18). Amendments remain created only from the Appointment clinical record
(`SPEC-MED-004` §15).

### Mobile presentation

- One route, `/professional/clinics/[clinicId]/appointments/[appointmentId]/history`,
  titled **Historial clínico / Medical history**. No Clinic, Organization or
  filter selector.
- History is read only on the explicit action **Ver historial clínico / View
  medical history**, on retry and on load more. Opening the Appointment detail
  or the Clinical record reads no history and creates no audit event; the
  history screen does not re-read on every focus.
- The Appointment detail offers the action, advisorily, when the actor holds
  `CLINICAL_CARE` at the Clinic, no Encounter exists, and the Appointment is
  `REQUESTED` with a future start or `CONFIRMED`. The Clinical record offers it
  while its Encounter is `ACTIVE` and the actor holds `CLINICAL_CARE`. Neither
  offers it for a `COMPLETED` Appointment without an Encounter or a `CONCLUDED`
  Encounter. The server decides.
- A flat timeline, newest first. A collapsed card shows the clinical date
  (`history_order_at`), category, Clinic · Organization, the Veterinarian's
  name (or the neutral fallback; the reader's own name may carry a secondary
  **Tú / You**), and the number of corrections when there are any. Expanded,
  it shows the content, the finalization time as secondary provenance, the
  finalizer when different, and the corrections beneath the unchanged original,
  oldest first, each with its reason, content, time and author.
- No Amendment action and no Attachment.
- An authorized empty history reads **Todavía no hay registros clínicos
  anteriores para esta mascota.** A denial, on the first page or any later
  page, drops every clinical content for a calm unavailable state that reveals
  nothing about the history.

## 16. Phase 1 Appointment-keyed professional history Verification Notes

In addition to §14, verification must demonstrate that:

29. history is permitted for a future `REQUESTED` and a `CONFIRMED`
    Appointment before an Encounter, and while an Encounter is `ACTIVE`,
    including after a `COMPLETED` Appointment's retrospective Encounter is
    established;
30. history is denied for a `REQUESTED` Appointment whose start has passed, a
    `CONCLUDED` Encounter, a `COMPLETED` Appointment without an Encounter, a
    `REVOKED` or `ENDED` Care Authorization (also during an `ACTIVE`
    Encounter), and after loss of the `CLINICAL_CARE` Entitlement (also during
    an `ACTIVE` Encounter);
31. an unknown Appointment, an Appointment of another Clinic or Organization,
    a Veterinarian of another Clinic of the same Organization, an ended Clinic
    Assignment, a non-Veterinarian, and a Receptionist, Administrator or Owner
    without Veterinarian context all receive the same `{"status": "DENIED"}`;
32. no Appointment Veterinarian Assignment or Veterinarian Availability is
    required;
33. the result contains every `FINALIZED` Entry of the Pet from every Clinic
    and Organization, no Draft and no other Pet, and acting through another
    Clinic without its own Care Authorization is denied;
34. the result contains no User, Membership, Clinic Assignment, Care
    Authorization, Encounter, Clinic, Organization or other-Appointment
    identifier;
35. Clinic and Organization names, the author's name, a distinct finalizer and
    each Amendment's author are present; a name survives the person's
    offboarding; a missing name is `null`;
36. Entries are ordered by clinical occurrence, not finalization, with a
    deterministic tie-breaker, and keyset pages neither duplicate nor skip;
37. each permitted page creates exactly one audit event with the current access
    context, never one per Entry or Amendment, and denials are audited as
    specified;
38. the Guardian payload carries no internal identifier and no Veterinarian
    name, while its content, Amendments, names, Attachments and cursor are
    unchanged;
39. `view_professional_pet_medical_history` is no longer client-executable.

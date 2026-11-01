# SPEC-MED-002 — Create Draft Clinical Record Entry

**Status:** APPROVED  
**Requirements:** REQ-MED-003, REQ-MED-007  
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): Draft creation, Draft update, and §14 are retired; an Entry is recorded once as clinical history (SPEC-MED-010 BR-1–BR-7, BR-23). Content, authorship, and provenance rules continue through SPEC-MED-010. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized veterinary professional to create clinical information in
draft form within an existing Clinical Encounter.

A Draft Clinical Record Entry represents clinical information that is still
being prepared, reviewed, or completed.

Draft information is not yet finalized medical history.

The draft workflow allows veterinary professionals to record and refine
clinical information before explicitly committing it to the Pet's finalized
longitudinal medical record.

---

## 2. Preconditions

- The Pet exists.
- The Clinical Encounter exists.
- The Clinical Encounter belongs to the Pet.
- The Clinic and Veterinary Organization context of the Encounter are known.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a Veterinarian Professional Profile.
- The acting User has a current professional context that authorizes clinical
  authorship within the Clinical Encounter.
- The Clinical Encounter remains in a state in which draft clinical
  documentation may be created.
- The applicable medical-access basis for the Encounter remains valid for the
  clinical activity being performed, including any limited continuity allowed
  by the Access Control Specifications.

---

## 3. Business Rules

### BR-1 — Draft Clinical Record Entry belongs to exactly one Clinical Encounter

Every Draft Clinical Record Entry must be associated with exactly one Clinical
Encounter.

The Entry must derive its Pet and clinical provider context from that
Encounter.

A Draft Clinical Record Entry must not float independently outside a clinical
care context.

---

### BR-2 — Draft Entry concerns the same Pet as its Clinical Encounter

The Pet associated with the Draft Clinical Record Entry must be the Pet
identified by the Clinical Encounter.

The Entry must not independently reference another Pet.

---

### BR-3 — Draft Entry preserves Encounter provider context

The Draft Clinical Record Entry must remain associated with the Clinic and
Veterinary Organization context established by the Clinical Encounter.

Creating or editing the Draft must not move the clinical information to another
Clinic or Organization.

---

### BR-4 — Draft Entry has an identifiable author

The system must preserve the veterinary professional who created the Draft
Clinical Record Entry.

The author must be distinguishable from:

- the Guardian;
- the requesting User of an Appointment;
- the Clinic Administrator;
- the responsible Veterinarian of the Encounter where those concepts differ in
  future workflows.

In the normal Phase 1 workflow, the responsible Veterinarian of the Clinical
Encounter is the clinical author.

Future multi-professional clinical participation may introduce additional
authorized authorship contexts.

---

### BR-5 — Clinical authorship requires explicit professional authorization

A User must not create a Draft Clinical Record Entry merely because they:

- belong to the Veterinary Organization;
- work at the Clinic in a non-veterinary role;
- are Guardian of the Pet;
- can manage Appointments;
- can view limited medical information for operational triage.

The acting User must have an authorized clinical authorship context for the
Encounter.

---

### BR-6 — Medical read access does not automatically grant authorship

An actor who is authorized to view some medical information must not
automatically gain permission to create clinical information.

Medical read access and clinical authorship are separate capabilities.

---

### BR-7 — Draft Entry begins as non-finalized clinical information

A newly created Clinical Record Entry begins in a draft state.

Conceptually:

    DRAFT

A Draft Entry must not be represented as finalized medical history.

Finalization requires a separate explicit workflow.

---

### BR-8 — Draft information may be incomplete

A Draft Clinical Record Entry may contain incomplete clinical information while
the author is preparing the record.

The Draft workflow must not require every field needed for finalization to be
present merely in order to save work in progress.

Finalization requirements are defined separately.

---

### BR-9 — Draft Entry may be edited while it remains draft

Authorized changes to a Draft Clinical Record Entry may be made while the Entry
remains non-finalized.

The author may correct, extend, reorganize, or remove draft content without
creating a Clinical Amendment because the information has not yet become
finalized medical history.

---

### BR-10 — Draft mutability ends when the Entry is finalized

The normal Draft editing model must apply only while the Clinical Record Entry
remains non-finalized.

Once finalized, the Entry must follow the integrity and amendment rules
applicable to finalized clinical information.

Finalization must not leave the Entry editable under ordinary Draft semantics.

---

### BR-11 — Draft Entry is not yet part of finalized longitudinal medical history

A Draft Clinical Record Entry must not be treated as a finalized contribution
to the Pet's longitudinal medical history.

The existence of the Draft must not imply that its clinical statements have
been professionally committed as final medical information.

---

### BR-12 — Guardians do not view Draft Entries through normal medical-history access

Guardian access to the Pet's normal longitudinal medical history must not
expose non-finalized Draft Clinical Record Entries.

Draft clinical work is internal professional working information until it is
finalized.

Any future workflow allowing explicit sharing of provisional information
requires separate behavior.

---

### BR-13 — Other Clinics do not receive Draft Entries through cross-clinic history

Cross-clinic longitudinal medical access must not expose Draft Clinical Record
Entries as though they were finalized historical records.

A Clinic accessing another provider's medical contribution receives only the
information permitted by the applicable Medical Records and Access Control
Specifications.

Non-finalized Draft Entries remain outside normal cross-provider history.

---

### BR-14 — Draft Entry remains protected information

Draft Clinical Record Entries contain sensitive medical information even though
they are not finalized.

They must remain subject to medical-access authorization and least-privilege
rules.

Draft status must not make clinical information less protected.

---

### BR-15 — Draft Entry identity is independent from its mutable content

A Draft Clinical Record Entry must have its own domain identity.

Editing its content must not create a new Entry solely because the text or
structured clinical information changed.

---

### BR-16 — Editing Draft content does not change Pet identity

Changes to Draft clinical content must not change the Pet to which the Entry
belongs.

If clinical information was created under the wrong Pet context, that error
must not be corrected by silently moving the Draft to another Pet.

The incorrect Draft must be resolved through an explicit safe workflow.

---

### BR-17 — Editing Draft content does not change Clinical Encounter identity

A Draft Clinical Record Entry must remain associated with the Clinical
Encounter in which it was created.

The normal Draft editing workflow must not move the Entry to another Encounter.

---

### BR-18 — Draft authorship and contribution history must remain traceable

The User who originally creates a Draft Clinical Record Entry must remain
historically identifiable as its original author.

Other authorized veterinary professionals participating in the same clinical
care context may modify the Draft where their current professional
authorization permits it.

Modification by another professional must not rewrite historical authorship or
make previous contributions appear to have been created by a different User.

The system must preserve sufficient authorship and contribution information to
establish who created and materially modified the clinical information.

---

### BR-19 — Draft editing may be collaborative within the authorized care context

A Draft Clinical Record Entry may be edited by another veterinary professional
when that professional is currently authorized to contribute clinical
information within the same Clinical Encounter.

Draft editing authority is derived from the current clinical care context, not
solely from being the User who originally created the Draft.

A professional who is not authorized within the Encounter must not modify the
Draft.

---

### BR-20 — Draft Entry creation preserves creation time

The system must preserve when the Draft Clinical Record Entry was originally
created.

Later edits must not replace the original creation time.

---

### BR-21 — Draft editing must support modification traceability where required

The system must be capable of distinguishing the original creation of the Draft
from later updates where operational or audit requirements require it.

This Specification does not require immutable storage of every keystroke or
every intermediate text version.

The exact Draft edit audit policy is an architectural and audit concern.

---

### BR-22 — Draft creation does not modify Clinical Encounter provenance

Creating a Draft Clinical Record Entry must not alter the Clinical Encounter's:

- Pet;
- Clinic;
- Veterinary Organization;
- responsible Veterinarian;
- medical-access basis;
- clinical occurrence context.

The Entry is created within that provenance.

It does not redefine it.

---

### BR-23 — Draft may contain clinically meaningful statements without making them final

A Draft may contain working clinical information such as:

- observations;
- findings;
- provisional assessments;
- diagnostic considerations;
- treatment information;
- procedure information;
- vaccination information;
- prescription-related information;
- free-text clinical notes.

The presence of clinically meaningful content in a Draft does not make that
content finalized medical history.

---

### BR-24 — Draft information must remain distinguishable from finalized facts

The system must not present Draft clinical information in a way that makes an
authorized Viewer reasonably believe it is finalized medical history.

Draft state must remain explicit wherever the Draft is accessible.

---

### BR-25 — Draft Entry may use supported clinical event categories

A Draft Clinical Record Entry may be classified using a supported clinical
event category.

The exact Phase 1 clinical event taxonomy is defined through dedicated
Specifications under `REQ-MED-006`.

Creating a Draft must not require specialized domain models such as Treatment,
Vaccination, Prescription, Laboratory Result, or Imaging unless their behavior
has been separately specified.

---

### BR-26 — Specialized medical concepts must not be prematurely collapsed into Draft text

A Draft Clinical Record Entry may initially describe clinical information using
the supported Phase 1 record model.

However, when a medical concept later requires dedicated domain behavior, the
system must be able to evolve without treating an arbitrary free-text Draft
field as the permanent domain model for that concept.

This preserves the evolution path defined by `REQ-MED-012`.

---

### BR-27 — Draft creation does not finalize the Clinical Encounter

Creating one or more Draft Clinical Record Entries must not by itself indicate
that the Clinical Encounter has ended or been completed.

Encounter lifecycle and Record Entry lifecycle are separate concepts.

---

### BR-28 — Multiple Draft Entries may exist within one Clinical Encounter

A Clinical Encounter may contain more than one Draft Clinical Record Entry.

For example:

    Clinical Encounter
    ├── Draft examination entry
    ├── Draft diagnosis-related entry
    └── Draft treatment-related entry

Each Entry remains an independent clinical information object.

---

### BR-29 — Draft Entries remain independently identifiable

Multiple Clinical Record Entries within the same Encounter must retain distinct
identities.

Finalizing one Entry must not implicitly finalize every other Draft in the
Encounter unless a later approved Specification explicitly defines such
behavior.

---

### BR-30 — Draft creation is atomic

A successfully created Draft Clinical Record Entry must establish at minimum:

- the Clinical Encounter;
- the Pet context;
- the author;
- the creation time;
- the Draft state.

The system must not expose a Draft Entry whose required authorship or clinical
context is ambiguous.

---

### BR-31 — Draft creator and later contributors are distinct concepts

The professional who originally creates a Draft Clinical Record Entry and the
professionals who later contribute to it may be different Users.

The system must not collapse all contributions into the identity of either:

- the original creator; or
- the most recent editor.

Clinical provenance must remain capable of representing meaningful
contributions from authorized professionals.

For the minimal Phase 1 Draft model, a material contribution occurs only when
a successful authorized update actually changes at least one authoritative
clinical field: clinical content, category, `OTHER` category context, or
clinical event time. A no-op, view, revision increment, timestamp-only change,
failed update, or stale-revision update is not a material contribution.

When the acting Veterinarian Clinic Assignment differs from the original
creator's Assignment, the first such material update establishes contributor
attribution for that Entry and Assignment. The original creator is not
duplicated as a contributor. Draft mutation and any required contributor
attribution are atomic, and finalization prevents later Draft contributor
insertion.

---

## 4. Draft Clinical Record Entry Information

The Draft model must support enough information to establish identity,
authorship, and clinical context while allowing the clinical content itself to
remain incomplete.

### Required at Draft creation

- Clinical Encounter;
- Pet context derived from the Encounter;
- author;
- creation time;
- Draft state.

### Optional or incomplete while Draft

- clinical event category;
- clinical event or observation time where different from Encounter time;
- structured clinical content;
- free-text clinical content;
- findings;
- provisional assessment;
- supporting clinical details;
- other information required by future clinical event types.

Information that is mandatory for finalization does not necessarily need to be
complete when the Draft is first created.

---

## 5. Scenarios

### Scenario: Veterinarian creates a Draft Clinical Record Entry

Given Luna has an active Clinical Encounter at Animalia Madrid Centro
And Dr. Garcia is authorized to author clinical information in that Encounter

When Dr. Garcia creates a Clinical Record Entry

Then a Draft Clinical Record Entry is created
And the Entry belongs to Luna's Clinical Encounter
And Dr. Garcia is recorded as the author
And the Entry has a creation time
And the Entry remains non-finalized

---

### Scenario: Draft may initially contain incomplete clinical information

Given Dr. Garcia is documenting Luna's active Clinical Encounter

When Dr. Garcia creates a Draft before all clinical information is known

Then the Draft may be saved
And incomplete information does not by itself require finalization
And the Entry remains clearly identified as Draft

---

### Scenario: Veterinarian edits their own Draft

Given Dr. Garcia has an existing Draft Clinical Record Entry for Luna
And Dr. Garcia remains authorized to work in the Clinical Encounter

When Dr. Garcia updates the clinical content

Then the existing Draft is updated
And the Draft remains the same Clinical Record Entry
And the original creation time remains preserved
And the Entry remains non-finalized

---

### Scenario: Draft correction does not require Clinical Amendment

Given Dr. Garcia has not finalized Luna's Clinical Record Entry

When Dr. Garcia corrects an error in the Draft

Then the Draft may be corrected through the normal Draft workflow
And no finalized-record amendment is required
And no false finalized history is created

---

### Scenario: Guardian cannot see Draft through normal medical history

Given Dr. Garcia has created a Draft Clinical Record Entry for Luna
And Maria is an authorized Guardian of Luna

When Maria views Luna's normal longitudinal medical history

Then the Draft Clinical Record Entry is not presented as finalized medical
history
And Draft working information is not exposed through normal Guardian history
access

---

### Scenario: Another Clinic cannot see Draft through cross-clinic history

Given Animalia Madrid Centro has a Draft Clinical Record Entry for Luna
And Luna later has an authorized care context at VetCare Toledo

When VetCare accesses Luna's longitudinal medical history

Then Animalia's Draft Entry is not exposed as cross-clinic finalized history
And only medical information permitted by the applicable finalized-record and
access-control rules may be returned

---

### Scenario: Reception actor cannot create Draft clinical information

Given Carlos is authorized to perform Appointment triage at Animalia Madrid
Centro
And Carlos may access limited information required for that function
And Carlos does not have an authorized clinical authorship context

When Carlos attempts to create a Draft Clinical Record Entry for Luna

Then the operation is denied
And medical read access does not grant clinical authorship

---

### Scenario: Veterinarian cannot create Draft for unrelated Pet

Given Dr. Garcia is authorized within Luna's Clinical Encounter
And Toby is another Pet

When Dr. Garcia attempts to create a Draft for Toby using Luna's Encounter

Then the operation is denied
And the Clinical Encounter cannot be used to author information for another Pet

---

### Scenario: Draft cannot be moved to another Clinical Encounter

Given Dr. Garcia created a Draft within Luna's Clinical Encounter A
And Luna also has Clinical Encounter B

When an attempt is made to change the Draft so that it belongs to Encounter B

Then the normal Draft editing workflow rejects the change
And the Draft remains associated with Encounter A

---

### Scenario: Another authorized Veterinarian contributes to the Draft

Given Dr. Garcia created a Draft Clinical Record Entry for Luna
And Dr. Lopez is also currently authorized to contribute clinical information
within Luna's Clinical Encounter

When Dr. Lopez modifies the Draft

Then the existing Draft may be updated
And the Draft remains the same Clinical Record Entry
And Dr. Garcia remains identifiable as the original creator
And Dr. Lopez remains identifiable as a later contributor
And the modification does not make Dr. Lopez appear to have created Dr.
Garcia's original contribution

---

### Scenario: Veterinarian outside the care context cannot modify the Draft

Given Dr. Garcia created a Draft Clinical Record Entry for Luna
And Dr. Lopez is a Veterinarian
And Dr. Lopez has no current authorization to contribute to Luna's Clinical
Encounter

When Dr. Lopez attempts to modify the Draft

Then the operation is denied
And Veterinarian status alone is insufficient

---

### Scenario: Multiple Draft Entries exist in one Encounter

Given Luna has an active Clinical Encounter
And Dr. Garcia is authorized to document the care

When Dr. Garcia creates separate Draft Entries for examination and
treatment-related information

Then both Draft Entries belong to the same Clinical Encounter
And each Entry has its own identity
And each Entry remains independently finalizable

---

### Scenario: Creating Draft does not create diagnosis automatically

Given Luna has an active Clinical Encounter

When Dr. Garcia creates a Draft Clinical Record Entry

Then no finalized diagnosis is created solely because the Draft exists
And no finalized Treatment is created
And no finalized clinical history is inferred

---

### Scenario: Draft preserves Clinical Encounter provenance

Given Luna's Encounter occurred at Animalia Madrid Centro
And Dr. Garcia creates a Draft Entry in that Encounter

When the Draft is evaluated

Then the Entry remains associated with Luna
And the Entry remains associated with the Animalia Madrid Centro care context
And Draft editing cannot move the Entry to another provider context

---

### Scenario: Draft does not finalize Encounter

Given Luna has an active Clinical Encounter
And Dr. Garcia creates and edits one or more Draft Clinical Record Entries

When those Draft operations succeed

Then the Clinical Encounter does not become completed solely because Draft
documentation exists

---

## 6. Draft vs Finalized Clinical Information

Draft and finalized clinical information have different semantics.

A Draft means:

    clinical work in progress
    editable
    potentially incomplete
    not part of normal finalized longitudinal history

A finalized Clinical Record Entry means:

    professionally committed clinical information
    longitudinal medical history
    historical provenance preserved
    destructive rewriting restricted
    corrections require traceable amendment behavior

The transition from Draft to finalized information is defined by a separate
Specification.

---

## 7. Authorship

Clinical authorship must remain explicit.

Conceptually:

    Clinical Encounter
          ↓
    Draft Clinical Record Entry
          ↓
    Author: Dr. Garcia

The Clinic or Veterinary Organization provides the professional context.

It is not itself the human clinical author.

A later finalized record must preserve the authorship information established
through the applicable clinical workflow.

---

## 8. Relationship to Clinical Encounter

The Clinical Encounter establishes:

- which Pet received care;
- where the care occurred;
- under which Veterinary Organization;
- the responsible professional care context;
- the relevant medical-access basis.

The Draft Clinical Record Entry establishes:

- which clinical information is being documented;
- who authored that information;
- the current non-finalized clinical content.

The two concepts must not be collapsed into one entity.

---

## 9. Edge Cases

### Care Authorization is revoked while Draft exists

If the applicable Care Authorization is revoked while a Clinical Encounter is
already underway, continued Draft access and documentation must follow the
limited active-care continuity rules defined by `SPEC-ACC-002`.

Revocation must not automatically delete the Draft.

It must not create indefinite access to edit the Draft after the care context
has ended.

---

### Original creator loses professional authorization while Draft remains unfinished

The professional who originally created a Draft may cease to have current
authorization to work in the Clinical Encounter before the Draft is finalized.

The Draft must not be deleted solely because the original creator loses that
authorization.

Another veterinary professional who is currently authorized to contribute
within the same Clinical Encounter may continue working on the Draft.

The original creator must remain historically identifiable.

Loss of current professional authorization must prevent the former
professional from continuing to modify the Draft unless another valid current
authorization basis applies.

---

### Clinical Encounter ends while Draft remains unfinished

A Clinical Encounter may reach the end of actual care while one or more Draft
Entries remain incomplete.

The system must not silently convert those Drafts into finalized medical
history.

The finalization workflow must explicitly determine whether they may still be
completed and finalized.

---

### Incorrect Pet context discovered

A Draft created under the wrong Pet context must not be silently moved to
another Pet.

Because Pet identity is clinically significant, correcting this condition
requires an explicit safe workflow.

---

### Draft is never finalized

A Draft may remain unfinalized.

The product may later require archival, cleanup, abandonment, or retention
rules for stale Drafts.

Those lifecycle rules are outside this Specification.

---

### Several professionals contribute to one Encounter

Phase 1 preserves one original creator per Clinical Record Entry and may also
preserve later material contributors under BR-18, BR-19, and BR-31.

This contributor attribution does not create co-authorship, a complete Draft
edit log, or a most-recent-editor role.

---

## 10. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 11. Dependencies

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-ID-003 — Authenticate User

---

## 12. Out of Scope

This Specification does not define:

- finalizing a Clinical Record Entry;
- finalized-record integrity;
- Clinical Amendments;
- final clinical-event taxonomy;
- dedicated Diagnosis models;
- dedicated Treatment models;
- Vaccination models;
- Prescription models;
- Laboratory Result models;
- Imaging models;
- clinical attachments;
- co-authorship;
- transfer of Draft authorship;
- abandonment or deletion of stale Drafts;
- Guardian access to provisional clinical information;
- cross-clinic access to Draft information;
- Clinical Encounter completion.

---

## 13. Verification Notes

Verification must demonstrate that:

1. an authorized veterinary professional may create a Draft Clinical Record
   Entry in an existing Clinical Encounter;
2. the Draft belongs to exactly one Clinical Encounter and Pet;
3. Draft provider context is inherited from and consistent with the Encounter;
4. clinical authorship is explicitly preserved;
5. medical read access alone does not grant authorship;
6. a newly created Entry begins as Draft;
7. Draft clinical information may be incomplete;
8. authorized Draft content may be edited before finalization;
9. Draft correction does not require finalized-record amendment behavior;
10. Draft information is not treated as finalized longitudinal medical history;
11. Guardians do not receive Drafts through normal medical-history access;
12. other Clinics do not receive Drafts through normal cross-clinic history;
13. Draft information remains protected medical information;
14. Draft editing does not change Pet, Encounter, provider context, or author;
15. Draft editing requires a current authorized professional context and
    preserves required material-contributor attribution;
16. creation time remains preserved across edits;
17. multiple independently identifiable Draft Entries may exist in one
    Clinical Encounter;
18. creating a Draft does not create finalized diagnosis, Treatment, or other
    clinical statements;
19. Draft creation does not complete the Clinical Encounter;
20. Draft creation behaves atomically.

---

## 14. Phase 1 Appointment-keyed Draft contract

Defined by **Minimal Clinical Record — Phase 1**. It narrows BR-1–BR-31 for the
mobile client; it does not change them. The Appointment-keyed clinical context
and its authority ordering are those of `SPEC-MED-001` BR-37, with the
`CLINICAL_DOCUMENTATION` capability. Any rejection before the Encounter is
resolved is the uniform `42501` of that rule. An authorized Appointment with no
Encounter yet is rejected with `23514`, hint `ENCOUNTER_NOT_STARTED`.

### BR-32 — Several Entries per Encounter

The client presents an Encounter as a list of Clinical Record Entries with
**Add entry / Añadir entrada** (BR-28, BR-29, `SPEC-MED-006` BR-9, BR-10). One
Entry is sufficient; the client never requires several, and never models the
whole visit as one note.

### BR-33 — Canonical Draft creation

    create_appointment_clinical_draft(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_creation_idempotency_key uuid,
        p_category text,
        p_clinical_content text,
        p_other_category_context text,
        p_clinical_event_at timestamptz
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It requires no Entitlement (`SPEC-SUB-004` BR-17).

- Only the Encounter's responsible Veterinarian Clinic Assignment may create a
  Draft (BR-4). Another Veterinarian is rejected with `23514`, hint
  `RESPONSIBLE_VETERINARIAN_REQUIRED`; this Phase defines no handoff
  (`SPEC-MED-001` §10).
- Every field may be empty (BR-8); an empty Draft is permitted.
- Clinical content and `OTHER` context are trimmed of surrounding whitespace;
  blank becomes absent.
- The category, when present, is one of the `SPEC-MED-006` taxonomy — otherwise
  `22023`, hint `INVALID_CATEGORY`. `OTHER` context is accepted only with the
  `OTHER` category — otherwise `22023`, hint `OTHER_CONTEXT_NOT_ALLOWED`.
- The clinical event time, when present, must be finite and not in the future —
  otherwise `22023`, hint `INVALID_EVENT_TIME` or `EVENT_TIME_IN_FUTURE`.
- For a `CONCLUDED` Encounter, creation requires the Care Authorization to
  remain `ACTIVE` (`SPEC-MED-008` BR-16, `SPEC-ACC-002` BR-35, BR-36) — otherwise
  `23514`, hint `CARE_AUTHORIZATION_INACTIVE`. An `ACTIVE` Encounter keeps the
  limited continuity of `SPEC-ACC-002` BR-19, BR-20.

The pre-existing `create_draft_clinical_record_entry(...)`, keyed by an
Encounter identifier, is not a client path. Client `EXECUTE` is withdrawn; it is
kept for trusted compatibility.

### BR-34 — Draft creation is idempotent per intent

Each client creation intent carries one caller-generated UUID, required —
otherwise `22023`, hint `KEY_REQUIRED`. The key is scoped to the acting User,
stored durably with the Entry together with a fingerprint of the requested
creation facts: the resolved Encounter, category, normalized clinical content,
normalized `OTHER` context, and clinical event time. The fingerprint records
the original request and is immutable; later Draft updates never change it.

| Situation | Result |
| --- | --- |
| The key is new | `CREATED` with `entry_id` and `revision_sequence` |
| The key was used by this User with exactly the same requested creation facts | `ALREADY_CREATED` with the same `entry_id` and its current `revision_sequence`; nothing is written |
| The key was used by this User with materially different facts, including another Encounter | rejected, `23505`, hint `KEY_CONFLICT`; nothing is written |

The comparison uses the original requested inputs, never the Entry's later
edited values. Different keys always create separate Drafts. Entries created
outside this operation may carry no key.

### BR-35 — Canonical Draft update

    update_appointment_clinical_draft(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_entry_id uuid,
        p_expected_revision bigint,
        p_category text,
        p_clinical_content text,
        p_other_category_context text,
        p_clinical_event_at timestamptz
    ) returns jsonb

It replaces all four editable fields, applies the field rules of BR-33, and is
executable only by `authenticated`. Any Veterinarian whose current exact-Clinic
context holds `CLINICAL_DOCUMENTATION` may update an existing Draft (BR-18,
BR-19); material contributor attribution follows BR-31. Ordering after the
Entry is resolved:

1. expected revision — `NULL` or negative is `22023`, hint `INVALID_REVISION`;
2. field rules of BR-33 — `22023`;
3. a `FINALIZED` Entry — `23514`, hint `ENTRY_FINALIZED`;
4. a `CONCLUDED` Encounter whose Care Authorization is not `ACTIVE` — `23514`,
   hint `CARE_AUTHORIZATION_INACTIVE`;
5. a revision other than the current one — rejected with hint
   `STALE_REVISION` as a plain application error (never `40001` or `409`), and
   nothing written;
6. update.

The result is `UPDATED` with the new `revision_sequence` when a clinical field
changed, or `UNCHANGED` with the same `revision_sequence` (BR-31). Results never
contain clinical content.

The pre-existing `update_draft_clinical_record_entry(...)` is not a client path.
Client `EXECUTE` is withdrawn; it remains the trusted writer.

### Mobile presentation

- Opening the editor creates nothing. The first explicit **Save draft /
  Guardar borrador** creates the Draft with a new key generated for that
  editor session; backing out before it leaves no row.
- After creation the editor keeps the returned Entry, and each later save is an
  update bound to the revision it was edited from.
- Fields: category (no default, all ten categories), clinical content, `OTHER`
  context only when `OTHER` is selected, and a collapsed optional **Different
  event date/time / Otra fecha/hora del evento** that is empty by default — never
  prefilled with the current time, the Encounter start, or the Appointment
  start. No structured diagnosis, medication, dose, or vitals fields exist.
- A saved Draft is labelled as not visible to the pet's guardians.
- `STALE_REVISION` re-reads the Entry and keeps the user's unsaved text on
  screen for comparison; nothing is overwritten silently.
- No request is retried automatically; after an uncertain response the client
  re-reads. A repeated creation with the same key is safe.
- **Add entry** is offered only when the read says the acting Veterinarian may
  create a Draft (`SPEC-MED-009`). No Delete action exists (§12).

## 15. Phase 1 Appointment-keyed Draft Verification Notes

In addition to §13, verification must demonstrate that:

21. the responsible Veterinarian creates Drafts with outcome `CREATED`, and
    another currently assigned Veterinarian is rejected with
    `RESPONSIBLE_VETERINARIAN_REQUIRED`;
22. an exact repeat with the same key returns `ALREADY_CREATED` and the same
    Entry, also after the Draft was later edited;
23. the same key with a different category, content, `OTHER` context, event
    time, or Appointment is rejected with `KEY_CONFLICT` and nothing written;
24. several keys create several independent Drafts with different categories,
    and an empty Draft is accepted;
25. a `CONCLUDED` Encounter accepts Draft creation and update while its Care
    Authorization is `ACTIVE`, and an `ACTIVE` Encounter keeps continuity after
    revocation;
26. responsible and other currently assigned Veterinarians update a Draft; a
    material change increments the revision, a no-op returns `UNCHANGED`, a
    stale revision is rejected with `STALE_REVISION`, and a `FINALIZED` Entry is
    rejected with `ENTRY_FINALIZED`;
27. an Entry of another Encounter, Appointment, or Clinic is rejected with the
    uniform `42501`;
28. the creation key and fingerprint cannot be changed after creation;
29. concurrent creations with the same key produce one Draft, and with
    different keys produce one Draft each;
30. no client role executes the generic Draft operations.

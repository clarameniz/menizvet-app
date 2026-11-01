# SPEC-MED-007 — Add Clinical Attachment

**Status:** APPROVED  
**Requirements:** REQ-MED-007, REQ-MED-008, REQ-MED-011, REQ-FIL-001, REQ-FIL-003
**Domain:** Medical Records  
**Priority:** P1

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the rules that require a Draft parent Entry, allow removal before finalization, and depend on Encounter or post-care windows are replaced by SPEC-MED-010 BR-19. Validation, storage, and download rules are unchanged. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.
>
> **Stage M4.** The professional upload, completion, removal, and professional download routes that implemented this Specification's professional workflow are retired (SPEC-MED-010 BR-19, BR-25). No professional client adds, removes, or downloads an Attachment until a new workflow is specified on SPEC-MED-010 BR-19. The Guardian download of BR-32 is unchanged in behavior and is now authorized by `authorize_guardian_clinical_attachment_download`, which takes only the authenticated subject and the Attachment.

## 1. Intent

Allow an authorized veterinary professional to associate a protected file with
a Clinical Record Entry when that file contributes meaningful supporting
information to the clinical record.

A Clinical Attachment may represent material such as:

- a report;
- a clinical image;
- a laboratory document;
- an imaging-related file;
- another supported clinical document.

The Attachment supplements the Clinical Record Entry.

It must not replace clinically meaningful record content or clinical
provenance.

---

## 2. Preconditions

- The Clinical Record Entry exists.
- The Clinical Record Entry belongs to a Clinical Encounter.
- The Pet and provider context of the Entry are identifiable.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a Veterinarian Professional Profile.
- The acting User is currently authorized to contribute clinical information
  within the applicable care context.
- The file belongs to a supported attachment type.
- The file satisfies the applicable validation and size constraints.
- The Attachment is clinically relevant to the Clinical Record Entry.

---

## 3. Business Rules

### BR-1 — Clinical Attachment belongs to exactly one Clinical Record Entry

Every Clinical Attachment must be associated with exactly one Clinical Record
Entry.

The Attachment must not exist as unattached medical content within the normal
clinical-history model.

---

### BR-2 — Attachment inherits Pet context from the Clinical Record Entry

A Clinical Attachment belongs to the same Pet as its parent Clinical Record
Entry.

The Attachment must not independently reference or be moved to another Pet.

---

### BR-3 — Attachment inherits clinical provider context

The Attachment remains associated with the Clinical Encounter, Clinic, and
Veterinary Organization context of its parent Clinical Record Entry.

Uploading a file must not move clinical information to another provider
context.

---

### BR-4 — Attachment supplements clinical information

A file must not replace the clinically meaningful content of the Clinical
Record Entry.

For example:

    LABORATORY_RESULT

    Clinical content:
    Relevant interpretation of laboratory findings

    Attachment:
    Original laboratory report PDF

The presence of the PDF must not be the only source of clinical meaning when
clinically meaningful record information is required.

---

### BR-5 — Attachment has its own domain identity

A Clinical Attachment must have an identity independent from:

- its filename;
- its storage location;
- its parent Clinical Record Entry;
- the underlying binary object identifier.

Changing technical storage representation must not require changing the
clinical identity of the Attachment.

---

### BR-6 — Attachment preserves who added it

The system must preserve the User who added the Clinical Attachment.

The uploading professional may differ from:

- the original creator of the Clinical Record Entry;
- previous contributors;
- the finalizing professional;
- the responsible Veterinarian of the Clinical Encounter.

These roles must remain distinguishable.

---

### BR-7 — Upload requires authorized clinical contribution context

A User must not add a Clinical Attachment merely because they:

- can view the Pet's history;
- have an Organization Membership;
- manage Appointments;
- are a Guardian;
- are a Veterinarian outside the applicable Clinical Encounter.

The User must have an authorized clinical contribution context.

---

### BR-8 — Read access does not grant upload authority

Being authorized to view a Clinical Record Entry or Attachment must not
automatically grant permission to add another Attachment.

Read access and clinical contribution authority are separate capabilities.

---

### BR-9 — Supported attachment types are controlled

The system must accept only file types explicitly supported by the current
clinical attachment policy.

Unsupported file types must not become available as Clinical Attachments.

The exact supported MIME types and file formats are an architectural and
configuration concern.

---

### BR-10 — File size is constrained

Clinical Attachments must be subject to configured file-size limits.

The system must reject files that exceed the applicable limit.

The exact limit is an architectural and operational configuration concern.

---

### BR-11 — Client-provided filename or MIME type is not sufficient validation

The system must not trust a file solely because the client reports:

- a particular filename extension;
- a particular MIME type.

The file must satisfy the applicable trusted validation checks before it
becomes available as a Clinical Attachment.

---

### BR-12 — Attachment must pass required security validation

A file must not become available to normal authorized medical-history viewers
until the required file validation and security checks have succeeded.

The exact validation mechanism may evolve independently from the medical
domain model.

---

### BR-13 — Attachment validation state must remain distinguishable

Where file validation is not instantaneous, the system must be capable of
distinguishing conceptually between states such as:

    pending validation

    available

    rejected

A file that has not successfully completed the required validation must not be
represented as an available Clinical Attachment.

The exact persistence representation is architectural.

---

### BR-14 — Rejected file does not become medical history

A file that fails required validation must not become an available part of the
Pet's medical history.

The failure must not require creation of false clinical information.

---

### BR-15 — Clinical Attachment remains protected information

Clinical Attachments must be treated as protected medical information.

They must not become publicly accessible merely because the underlying file can
technically be represented by a URL or object identifier.

---

### BR-16 — Attachment access follows medical-access authorization

Access to a Clinical Attachment must require an applicable current
medical-access basis.

The existence of the underlying file must not bypass:

- Guardianship access rules;
- Care Authorization;
- professional least privilege;
- revocation;
- other applicable medical-access controls.

---

### BR-17 — Storage reference does not constitute authorization

Possession of:

- a storage path;
- an object identifier;
- a filename;
- a cached technical URL;

must not independently establish medical-access authority.

Authorization must be evaluated through the application's medical-access model.

---

### BR-18 — Draft Attachments remain part of Draft clinical work

A Clinical Attachment associated with a `DRAFT` Clinical Record Entry remains
part of non-finalized clinical work.

It must not be exposed through normal Guardian longitudinal-history access.

It must not be exposed through normal cross-clinic finalized-history access.

---

### BR-19 — Draft Attachment may be removed before finalization

While the parent Clinical Record Entry remains `DRAFT`, an authorized clinical
contributor may remove an Attachment that was added incorrectly or is no longer
required.

Removing a Draft Attachment does not require a Clinical Amendment because the
Entry has not yet become finalized medical history.

---

### BR-20 — Draft Attachment may be replaced explicitly before finalization

While the parent Entry remains `DRAFT`, an authorized professional may remove
an incorrect Attachment and add a corrected file.

The system must not silently replace the underlying binary content while
pretending that no change occurred.

The resulting current Draft state must remain internally consistent.

---

### BR-21 — Finalization makes available Attachments part of finalized history

When a Clinical Record Entry is validly finalized, its successfully validated
Clinical Attachments become part of the finalized clinical contribution.

They may become visible to authorized Guardians and professional viewers
according to the applicable Medical Access Control rules.

---

### BR-22 — Pending or rejected files must not silently finalize as available Attachments

A Clinical Record Entry must not present a file as an available finalized
Clinical Attachment if the file has not successfully satisfied the required
validation process.

The applicable finalization workflow may require unresolved Attachment
validation to be completed or otherwise resolved before finalization.

---

### BR-23 — Finalized Attachment must not be silently replaced

Once an Attachment forms part of a Finalized Clinical Record Entry, its
underlying clinical file must not be silently replaced with different content
through ordinary editing.

For example:

    report.pdf
        ↓
    overwrite same object with different bytes

must not result in the system presenting the new file as though it were the
original finalized Attachment.

---

### BR-24 — Finalized Attachment must preserve file integrity information

The system must preserve sufficient integrity information to detect unintended
or unauthorized changes to the finalized Attachment content.

The exact integrity mechanism is architectural.

A cryptographic content checksum may be used as part of that mechanism.

---

### BR-25 — Finalized Attachment correction must be traceable

If a file associated with finalized clinical history is discovered to be:

- incorrect;
- incomplete;
- corrupted;
- attached to the wrong clinical record;
- otherwise clinically unsuitable;

the normal workflow must not silently replace or erase the historical
Attachment.

A traceable correction, Amendment, or dedicated Attachment-correction workflow
is required.

---

### BR-26 — Finalized Attachment deletion is not an ordinary operation

A Clinical Attachment that forms part of finalized medical history must not be
destructively deleted through normal clinical editing.

Exceptional deletion requirements arising from legal, privacy, or safety
obligations require an explicit controlled workflow.

---

### BR-27 — Attachment preserves original filename as metadata where useful

The system may preserve the original filename supplied during upload for
authorized presentation or traceability.

The original filename must not determine:

- Attachment identity;
- medical authorization;
- provider provenance.

---

### BR-28 — Attachment metadata must remain distinct from binary content

The Clinical Attachment domain model may preserve information such as:

- Attachment identity;
- original filename;
- media type;
- file size;
- integrity information;
- uploading User;
- creation time;
- technical storage reference.

The binary file content itself must not need to be stored inside the Clinical
Record Entry representation.

The exact storage technology is architectural.

---

### BR-29 — Technical storage location is not clinical provenance

Changing where or how the binary file is technically stored must not change:

- Pet;
- Clinical Record Entry;
- Clinical Encounter;
- Clinic;
- Veterinary Organization;
- uploading professional;
- historical medical meaning.

Storage architecture and clinical provenance are separate concepts.

---

### BR-30 — Cross-clinic access may include applicable Attachments

When another participating Clinic has valid authorization to access a Finalized
Clinical Record Entry, applicable Clinical Attachments may also be made
available when they fall within the authorized medical-access scope.

The accessing Clinic does not become the author or owner of the historical
Attachment.

---

### BR-31 — Cross-clinic access preserves provider provenance

A Clinical Attachment originating from Animalia Madrid Centro remains
associated with Animalia's clinical contribution when later accessed by
VetCare Toledo.

Cross-clinic viewing must not rewrite:

- Clinic provenance;
- Veterinary Organization provenance;
- clinical authorship;
- Attachment origin.

---

### BR-32 — Guardian access may include finalized Attachments

An authorized Guardian viewing a Pet's finalized longitudinal medical history
may access applicable finalized Clinical Attachments.

Draft, rejected, or otherwise non-available files must not be exposed through
normal Guardian history access.

---

### BR-33 — Revocation affects Attachment access

When professional medical access is revoked, Clinical Attachments must follow
the same applicable access-control restrictions as the clinical information to
which they belong.

Possession of a previously issued technical file reference must not create
permanent medical access.

---

### BR-34 — Attachment access does not grant access to unrelated files

Authorization to access one Clinical Attachment must not grant access to:

- other Pets' Attachments;
- unrelated Clinical Record Entries;
- arbitrary files belonging to the Clinic;
- other protected storage objects.

---

### BR-35 — Attachment is not itself a clinical event category

A file does not determine the Clinical Record Entry's event category.

For example:

    JPEG image

does not automatically imply:

    IMAGING_RESULT

and:

    PDF

does not automatically imply:

    LABORATORY_RESULT

Clinical classification depends on the clinical meaning of the Entry.

---

### BR-36 — Clinical event category does not determine file format

A particular clinical event category must not require one universal binary
format unless a later specialized Specification explicitly establishes that
requirement.

For example, `IMAGING_RESULT` may eventually support specialized imaging
formats without changing the general Clinical Attachment concept.

---

### BR-37 — Multiple Attachments may belong to one Clinical Record Entry

A Clinical Record Entry may have zero, one, or multiple Clinical Attachments.

For example:

    IMAGING_RESULT
    ├── radiograph-front.jpg
    ├── radiograph-side.jpg
    └── imaging-report.pdf

Each Attachment remains independently identifiable.

---

### BR-38 — One Attachment must not be shared by reference across unrelated Entries

The same Clinical Attachment identity must not be used to make one protected
file appear simultaneously authored as part of unrelated Clinical Record
Entries.

Where the same source document is clinically relevant to another context, the
relationship must be explicitly modeled rather than inferred through arbitrary
storage reference reuse.

---

### BR-39 — Attachment creation does not create clinical interpretation

Uploading a file must not automatically create:

- a diagnosis;
- a clinical conclusion;
- a Laboratory Result interpretation;
- an Imaging Result interpretation;
- a Treatment;
- another clinical statement.

The professional remains responsible for clinically meaningful documentation.

---

### BR-40 — Attachment creation does not finalize the parent Entry

Adding a Clinical Attachment to a Draft Clinical Record Entry must not
automatically finalize that Entry.

Attachment lifecycle and Clinical Record Entry lifecycle remain distinct.

---

### BR-41 — Attachment upload failure must not corrupt the Clinical Record Entry

If the underlying file cannot be validly stored or validated, the parent
Clinical Record Entry must remain coherent.

A failed file operation must not:

- corrupt Draft clinical content;
- change Pet identity;
- change Encounter provenance;
- falsely expose an Attachment as available.

---

### BR-42 — Attachment creation is atomic at the domain level

A Clinical Attachment must not become available as part of the clinical record
until its required domain metadata and valid binary reference are coherently
established.

The system must not expose an Attachment whose clinical relationship or file
identity is ambiguous.

---

## 4. Clinical Attachment Information

The Clinical Attachment domain must support enough information to identify the
file, its clinical relationship, and its provenance.

### Required

- Clinical Attachment identity;
- parent Clinical Record Entry;
- uploading User;
- creation time;
- supported media or file type;
- file size;
- technical binary reference;
- validation state;
- integrity information where applicable.

### Optional or presentation-oriented

- original filename;
- human-readable description;
- clinically relevant Attachment label;
- other non-authoritative metadata.

The technical binary reference must not be treated as medical-access
authorization.

---

## 5. Scenarios

### Scenario: Veterinarian adds PDF report to Draft Entry

Given Luna has a Draft `LABORATORY_RESULT` Clinical Record Entry  
And Dr. Garcia is authorized to contribute to the Clinical Encounter  
And the PDF satisfies the supported file and validation requirements

When Dr. Garcia adds the PDF as a Clinical Attachment

Then a Clinical Attachment is associated with the Draft Entry  
And Dr. Garcia is recorded as the uploading User  
And the Attachment remains protected Draft clinical information  
And the Draft Clinical Record Entry remains `DRAFT`

---

### Scenario: Veterinarian adds clinical image to Draft Entry

Given Luna has a Draft Clinical Record Entry  
And Dr. Garcia is authorized to contribute to the Encounter  
And the image uses a supported file type

When Dr. Garcia adds the image

Then the image may become a Clinical Attachment after successful validation  
And the Attachment belongs to the same Pet and Clinical Record Entry

---

### Scenario: Unsupported file type is rejected

Given Dr. Garcia is authorized to add a Clinical Attachment  
And the selected file type is not supported

When Dr. Garcia attempts to add the file

Then the file does not become an available Clinical Attachment  
And the parent Clinical Record Entry remains unchanged

---

### Scenario: Oversized file is rejected

Given Dr. Garcia is authorized to add a Clinical Attachment  
And the file exceeds the configured size limit

When Dr. Garcia attempts to add the file

Then the upload is rejected  
And no available Clinical Attachment is created

---

### Scenario: Client filename does not determine trusted file type

Given a file is named `report.pdf`  
And the file content does not satisfy the supported PDF validation rules

When the file is validated

Then the filename alone is insufficient  
And the file must not become an available Clinical Attachment solely because
it ends with `.pdf`

---

### Scenario: File remains unavailable while validation is pending

Given Dr. Garcia has submitted a supported Clinical Attachment  
And required validation has not yet completed

When an authorized Guardian views Luna's finalized medical history

Then the pending file is not presented as an available Clinical Attachment

---

### Scenario: File fails security validation

Given a submitted file fails a required security validation check

When validation completes

Then the file does not become an available Clinical Attachment  
And the Clinical Record Entry remains intact  
And the failed file is not exposed through normal medical-history access

---

### Scenario: Draft Attachment may be removed before finalization

Given Dr. Garcia added an incorrect PDF to Luna's Draft Clinical Record Entry  
And the Entry remains `DRAFT`  
And Dr. Lopez is also authorized to contribute within the same Clinical
Encounter

When Dr. Lopez removes the incorrect Draft Attachment

Then the Attachment no longer belongs to the current Draft state  
And no Clinical Amendment is required  
And the remaining Draft clinical information remains intact

---

### Scenario: Draft Attachment may be replaced explicitly

Given Luna has a Draft Clinical Record Entry  
And an Attachment contains the wrong version of a report

When an authorized clinical contributor removes the incorrect Draft Attachment
and adds the corrected file

Then the corrected file has its own valid Attachment identity  
And the incorrect binary content is not silently overwritten as though no
change occurred

---

### Scenario: Finalization makes validated Attachment eligible for history access

Given Luna has a Draft Clinical Record Entry  
And the Entry contains a successfully validated Clinical Attachment

When the Clinical Record Entry is validly finalized

Then the Attachment becomes part of that finalized clinical contribution  
And it may be accessed by authorized Viewers according to the applicable
medical-access rules

---

### Scenario: Draft Attachment is not visible to Guardian

Given Luna has a Draft Clinical Record Entry with a Clinical Attachment  
And Maria has an active Guardianship relationship with Luna

When Maria views Luna's normal longitudinal medical history

Then the Draft Attachment is not available through that history view

---

### Scenario: Finalized Attachment is visible to authorized Guardian

Given Luna has a Finalized Clinical Record Entry with an available Clinical
Attachment  
And Maria is an authorized Guardian of Luna

When Maria views the applicable medical-history Entry

Then the Attachment may be made available according to the applicable access
rules

---

### Scenario: Other Clinic may access finalized Attachment

Given Animalia Madrid Centro finalized a Clinical Record Entry for Luna  
And that Entry contains an available Clinical Attachment  
And VetCare Toledo later has a valid Care Authorization for Luna  
And Dr. Lopez has an applicable professional access context

When Dr. Lopez accesses the relevant longitudinal history

Then the applicable Clinical Attachment may be available  
And Animalia remains the provider of origin  
And VetCare does not become the Attachment author or clinical provider

---

### Scenario: Cross-clinic access does not expose Draft Attachment

Given Animalia Madrid Centro has a Draft Clinical Record Entry for Luna  
And the Draft contains a Clinical Attachment  
And VetCare Toledo has an authorized current care context for Luna

When VetCare accesses Luna's longitudinal finalized history

Then Animalia's Draft Attachment is not exposed through normal cross-clinic
history access

---

### Scenario: Finalized Attachment cannot be silently replaced

Given Luna has a Finalized Clinical Record Entry  
And `report.pdf` is an available Clinical Attachment belonging to that Entry

When a User attempts to replace the binary content of that finalized Attachment
through ordinary editing

Then the operation is denied  
And the original finalized Attachment remains historically intact  
And a traceable correction workflow is required

---

### Scenario: Finalized Attachment cannot be ordinarily deleted

Given Luna has a Finalized Clinical Record Entry with a Clinical Attachment

When a User attempts to destructively delete that Attachment through ordinary
clinical editing

Then the operation is denied  
And the finalized history remains intact

---

### Scenario: Attachment access is denied after Care Authorization revocation

Given VetCare Toledo previously had authorized access to Luna's finalized
Clinical Record Entry and Attachment  
And the applicable Care Authorization has been revoked  
And no other valid access basis applies

When a VetCare professional attempts to access the Attachment

Then access is denied  
And possession of an old technical file reference is insufficient

---

### Scenario: Attachment URL or storage reference does not bypass authorization

Given Carlos possesses a technical reference to Luna's Clinical Attachment  
And Carlos has no current authorization to access Luna's medical information

When Carlos attempts to use that reference to retrieve the file

Then access is denied  
And the technical reference does not constitute medical authorization

---

### Scenario: Multiple Attachments belong to one Entry

Given Luna has an `IMAGING_RESULT` Clinical Record Entry

When an authorized professional adds two supported images and one supported
report

Then three distinct Clinical Attachments may belong to the same Clinical Record
Entry  
And each Attachment retains its own identity and metadata

---

### Scenario: File upload does not create clinical interpretation

Given Dr. Garcia uploads a laboratory report PDF

When the Attachment becomes available

Then no clinical interpretation is inferred solely from the file  
And meaningful laboratory interpretation must still be documented through the
applicable Clinical Record workflow

---

### Scenario: Attachment upload failure leaves Draft intact

Given Luna has a Draft Clinical Record Entry  
And Dr. Garcia attempts to add a file  
And the file operation fails

When the failure occurs

Then Luna's Draft Clinical Record Entry remains valid  
And existing Draft content remains unchanged  
And no unavailable file is represented as a successful Attachment

---

## 6. Draft and Finalized Attachment Behavior

Clinical Attachment behavior follows the lifecycle of its parent Clinical
Record Entry.

While the parent Entry is `DRAFT`:

    Attachment may be added
    Attachment may be removed
    Attachment may be explicitly replaced
    Attachment is internal professional working information
    Attachment is not part of normal Guardian history
    Attachment is not part of normal cross-clinic history

After the parent Entry is `FINALIZED`:

    validated Attachment becomes finalized clinical history
    ordinary replacement is prohibited
    ordinary destructive deletion is prohibited
    corrections require traceable behavior
    authorized Guardian access may apply
    authorized cross-clinic access may apply

This preserves consistency between clinical content and its supporting files.

---

## 7. Attachment Security Boundary

A Clinical Attachment is protected medical information.

The domain must not rely on secrecy of a technical file reference for
authorization.

Conceptually:

    User requests Attachment
            ↓
    current medical-access authorization
            ↓
    applicable least-privilege checks
            ↓
    protected file access

not:

    User knows file URL
            ↓
    file access automatically granted

The exact storage and delivery mechanism is architectural.

---

## 8. Clinical Attachment and Binary Storage

Clinical Attachment identity and binary storage are separate concepts.

Conceptually:

    Clinical Record Entry
          ↓
    Clinical Attachment
          ↓
    protected binary object

The Clinical Attachment represents the domain relationship and clinical
metadata.

The protected binary object represents the file content.

The domain must not depend directly on a specific object-storage provider.

---

## 9. Integrity

Finalized Clinical Attachments must support detection of unintended or
unauthorized binary modification.

The implementation may preserve cryptographic content-integrity information.

This integrity mechanism supplements:

- access control;
- auditability;
- historical clinical provenance.

It does not replace them.

---

## 10. Edge Cases

### Attachment added to wrong Draft Entry

Before finalization, an authorized professional may remove the incorrect Draft
Attachment and add it to the correct Draft context where permitted.

The system must not silently change the Pet or Clinical Record Entry identity
of the existing Attachment.

---

### Attachment discovered to be wrong after finalization

A finalized Attachment must not be silently moved, replaced, or deleted.

A traceable clinical correction or dedicated Attachment-correction workflow is
required.

---

### Original uploaded file becomes unreadable or corrupted

Loss or corruption of finalized clinical binary content is an integrity
incident.

The system must not silently substitute unrelated content while preserving the
same historical Attachment identity.

Recovery behavior is architectural and operational, but historical integrity
must remain explicit.

---

### Very large clinical files

Some future medical formats may require substantially larger storage or
specialized delivery mechanisms.

Phase 1 file-size limits may intentionally exclude such formats.

Future support must not require changing the general Clinical Attachment
identity model.

---

### Specialized medical file formats

Formats such as dedicated medical imaging files may require specialized
validation, metadata, viewers, or domain behavior.

They should be introduced through explicit later requirements rather than
treated as ordinary arbitrary uploads by default.

---

### Original filename contains sensitive information

Original filename metadata may itself contain sensitive information.

It must be protected under the same applicable medical-access controls as the
Attachment.

Storage architecture must not rely on user-visible filenames as authorization
or identity.

---

### Attachment is accessed after Guardian relationship changes

A User who loses Guardianship must not retain permanent Attachment access merely
because the file was previously viewed or referenced.

Current authorization governs subsequent protected operations.

---

### Subscription termination

Subscription termination must not erase finalized Clinical Attachments or
detach them from the Pet's historical medical record.

Commercial state and clinical-history retention remain separate concerns.

---

## 11. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-004 — Amend Finalized Clinical Record Entry
- SPEC-MED-005 — View Pet Medical History
- SPEC-MED-006 — Classify Clinical Record Entry
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-ID-003 — Authenticate User

---

## 13. Out of Scope

This Specification does not define:

- the specific object-storage provider;
- bucket configuration;
- exact supported MIME-type list;
- exact file-size limits;
- malware-scanning vendor or implementation;
- signed-URL duration;
- file encryption implementation;
- dedicated DICOM support;
- image annotation;
- attachment preview implementation;
- attachment correction after finalization;
- exceptional legal deletion of finalized Attachments;
- bulk file import;
- external veterinary-system ingestion;
- attachment search;
- attachment export.

---

## 14. Verification Notes

Verification must demonstrate that:

1. an authorized veterinary professional may add a supported Clinical
   Attachment to a Clinical Record Entry;
2. every Attachment belongs to exactly one Clinical Record Entry and Pet
   context;
3. Attachment provider provenance remains consistent with the parent clinical
   context;
4. the uploading User remains traceable;
5. read access alone does not grant upload authority;
6. unsupported or oversized files do not become available Attachments;
7. client-provided filename or MIME type alone is insufficient trusted
   validation;
8. files do not become normally available until required validation succeeds;
9. Draft Attachments remain protected internal clinical information;
10. Draft Attachments may be removed or explicitly replaced before
    finalization;
11. finalized validated Attachments become part of finalized medical history;
12. finalized Attachments cannot be silently replaced or ordinarily
    destructively deleted;
13. finalized Attachments preserve sufficient integrity information;
14. Guardian and cross-clinic Attachment access follow current medical-access
    authorization;
15. technical file references do not bypass authorization;
16. cross-clinic access does not transfer clinical authorship or provider
    provenance;
17. multiple independent Attachments may belong to one Clinical Record Entry;
18. file upload does not create clinical interpretation;
19. Attachment creation does not finalize the Clinical Record Entry;
20. file-operation failure leaves the parent Clinical Record Entry coherent;
21. subscription termination does not erase finalized Clinical Attachments;
22. Attachment creation behaves atomically at the domain level.
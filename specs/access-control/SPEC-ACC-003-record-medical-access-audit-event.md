# SPEC-ACC-003 — Record Medical Access Audit Event

**Status:** APPROVED  
**Requirements:** REQ-ACC-007, REQ-AUD-001 
**Domain:** Medical Access Control  
**Priority:** P1

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the Appointment clinical record read audits with operation `VIEW_APPOINTMENT_CLINICAL_RECORD` and scope `APPOINTMENT_CLINICAL_RECORD` (SPEC-MED-010 BR-21); `ACCESS_FOR_POST_CARE_DOCUMENTATION` and `ENCOUNTER_MEDICAL_INFORMATION` are retired, and typed Entry references are correlated through the Entry's Appointment instead of an Encounter. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Ensure that clinically relevant access to protected Pet medical information can
be recorded in an auditable form.

A Medical Access Audit Event represents a meaningful attempt by a User or
authorized process to access protected medical information within a specific
domain and authorization context.

Audit information must make it possible, where required, to establish:

- who accessed or attempted to access protected medical information;
- which Pet was involved;
- when the access occurred;
- through which professional or Guardian context the access occurred;
- which Clinic or Veterinary Organization context applied where relevant;
- which authorization basis supported the access;
- what general type of protected medical resource was accessed;
- whether the access was permitted or denied.

Medical-access auditing must not depend on client-side behavior alone.

---

## 2. Preconditions

- A protected medical-access operation is being evaluated or performed.
- The acting User or authorized system process is identifiable.
- The Pet associated with the protected medical information is identifiable.
- The relevant authorization context can be evaluated.
- The applicable medical resource or resource category is identifiable.
- The audit policy determines that the access attempt is relevant for medical
  audit recording.

---

## 3. Business Rules

### BR-1 — Medical access audit is a security and accountability record

A Medical Access Audit Event represents security-relevant access activity.

It must remain distinct from:

- Clinical Record Entries;
- Clinical Amendments;
- Clinical Encounters;
- Appointment history;
- ordinary application analytics;
- debugging logs.

Medical-access auditing must not itself become part of the Pet's clinical
history.

---

### BR-2 — Audit recording must occur in trusted infrastructure

Medical Access Audit Events must be established through trusted backend
infrastructure.

The system must not rely solely on the mobile application to report whether
protected medical information was accessed.

A malicious or modified client must not be able to bypass required auditing
simply by omitting a client-side audit request.

---

### BR-3 — Domain-relevant access must be distinguishable from technical noise

The audit model should represent meaningful protected medical-access
operations rather than every low-level technical read.

For example, a single User action such as:

    View Luna's medical history

must not necessarily create separate domain audit events for:

- every database row retrieved;
- every React render;
- every pagination helper request;
- every internal authorization query.

The exact aggregation mechanism is architectural.

---

### BR-4 — Audit-required permitted access requires durable Audit Event capture

When an authenticated User or authorized process successfully performs a
protected medical-access operation that the applicable audit policy classifies
as audit-required, the required Medical Access Audit Event must be durably
established through trusted infrastructure.

The protected operation must not be considered successfully completed if its
required audit evidence cannot be durably captured.

Examples of operations that may be classified as audit-required include:

- viewing a Pet's longitudinal medical history;
- accessing cross-clinic medical history;
- opening a finalized Clinical Record Entry;
- accessing a protected Clinical Attachment;
- accessing medical information for Appointment triage;
- accessing medical information during an authorized Clinical Encounter.

The exact Phase 1 classification of audit-required operations must remain
explicit and must not be inferred from low-level database activity.

---

### BR-5 — Security-relevant denied access may also require an Audit Event

The audit model must support recording denied attempts to access protected
medical information where those attempts are security-relevant.

For example:

    Veterinarian without Care Authorization
    attempts to access Luna's medical history

may be auditable even though no medical information was disclosed.

The audit system must distinguish successful access from denied access.

---

### BR-6 — Not every authorization failure must become a permanent medical Audit Event

Routine technical or malformed requests do not necessarily need to become
long-term Medical Access Audit Events.

The audit policy may distinguish between:

- meaningful authenticated access attempts;
- security-relevant denied access;
- ordinary application or protocol errors.

The exact retention and security-log strategy is architectural.

---

### BR-7 — Audit Event identifies the acting User

Where the access is performed by a User, the Medical Access Audit Event must
identify that User.

The system must not record only a generic role such as:

    Veterinarian

when the individual User identity is known.

---

### BR-8 — Audit Event preserves actor context

The same User may act through different domain contexts.

The audit information must preserve the context through which medical access
was attempted.

Examples include:

- Guardian context;
- Veterinarian clinical-care context;
- Clinic triage context;
- authorized operational context.

The User identity alone is insufficient to explain why access was permitted.

---

### BR-9 — Professional access preserves Clinic context

When medical access occurs through a professional context, the applicable
Clinic must be identifiable where relevant.

For example:

    Dr. Garcia
    acting through:
    Animalia Madrid Centro

must remain distinguishable from the same User acting through another Clinic.

---

### BR-10 — Veterinary Organization context remains identifiable where applicable

Where the professional medical-access context derives from a Clinic operated by
a Veterinary Organization, the applicable Organization context must remain
traceable.

This supports reconstruction of the provider context under which access
occurred.

---

### BR-11 — Audit Event identifies the Pet

Every Medical Access Audit Event concerning Pet medical information must
identify the Pet whose protected information was accessed or targeted.

A single audit event must not ambiguously represent medical access to several
unrelated Pets.

---

### BR-12 — Audit Event preserves authorization basis where applicable

The audit model must be capable of identifying the medical-access basis used or
evaluated for the access operation.

Examples may include:

- active Guardianship;
- Pet Care Authorization;
- limited active-care continuity following revocation;
- another future authorized access basis.

The exact technical representation is architectural.

---

### BR-13 — Care Authorization should be traceable in professional access

Where professional access is permitted through a Pet Care Authorization, the
applicable Care Authorization should remain identifiable from the audit
information.

This allows the system to establish:

    who accessed Luna's history
    under which care authorization
    and through which Clinic context

without treating the Care Authorization itself as an audit log.

---

### BR-14 — Historical Care Authorization does not validate later access

Recording that a previous access used a Care Authorization must not imply that
the authorization remains currently valid.

Audit history records the authorization context that applied at the time.

Current authorization must still be independently evaluated for future access.

---

### BR-15 — Audit Event identifies access outcome

The event must distinguish, at minimum, whether the protected medical-access
operation was:

- permitted; or
- denied

where denied access is included by the applicable audit policy.

A denied operation must not be represented as though protected medical
information was successfully disclosed.

---

### BR-16 — Audit Event identifies resource scope without unnecessarily duplicating medical content

The audit system must preserve enough information to identify the general
protected resource or resource scope accessed.

Examples may include:

- longitudinal medical history;
- Clinical Record Entry;
- Clinical Amendment;
- Clinical Attachment;
- Encounter-related medical information.

Audit records should not unnecessarily duplicate full clinical content.

---

### BR-17 — Audit Event may identify specific resource identity

Where appropriate, the audit record may preserve the identity of the specific
protected medical resource accessed.

For example:

    Clinical Attachment ID
    Clinical Record Entry ID

This must not require copying the clinical content itself into the audit
record.

---

### BR-18 — Audit information is itself protected

Medical Access Audit Events contain sensitive information about:

- Users;
- Pets;
- Clinics;
- professional activity;
- medical-access patterns.

Audit information must not be treated as public or ordinary analytics data.

Access to audit information requires explicit authorization.

---

### BR-19 — Audit information must not expose additional medical content unnecessarily

An audit record should not store complete diagnoses, reports, clinical notes,
attachment contents, or other protected medical details merely to explain that
access occurred.

The principle of data minimization applies to audit records.

---

### BR-20 — Audit Event preserves time of access

The system must preserve when the audited medical-access operation occurred or
was evaluated.

Audit chronology must remain independently identifiable from:

- Clinical Encounter time;
- Clinical Record finalization time;
- Care Authorization grant time;
- Appointment time.

---

### BR-21 — Audit Event preserves relevant access purpose or operation type

The audit model should preserve enough information to distinguish why or how
the medical information was accessed.

Examples may include:

- GUARDIAN_HISTORY_VIEW;
- PROFESSIONAL_HISTORY_VIEW;
- APPOINTMENT_TRIAGE_ACCESS;
- CLINICAL_CARE_ACCESS;
- CLINICAL_ATTACHMENT_ACCESS.

The exact technical enumeration is architectural and may evolve.

The domain requirement is meaningful distinction between materially different
access contexts.

---

### BR-22 — Viewing a Clinical Attachment may be independently auditable

Accessing protected binary medical content may be recorded separately from
viewing the surrounding Clinical Record Entry where the audit policy requires
that distinction.

For example:

    User views Imaging Result
          ↓
    User opens attached radiograph

may represent distinct audit-relevant operations.

---

### BR-23 — Technical file references do not bypass auditing

Accessing a protected Clinical Attachment through:

- an authenticated storage request;
- a temporary signed URL;
- another protected delivery mechanism

must not bypass required medical-access auditability.

The technical delivery mechanism must preserve or establish the required audit
context before protected access is granted.

---

### BR-24 — Cross-clinic access must preserve accessing provider context

When one Clinic accesses clinical information created by another Clinic, the
audit information must identify the accessing professional context.

For example:

    Original provider:
    Animalia Madrid Centro

    Accessing provider:
    VetCare Toledo

The audit event must not confuse the provider of origin with the provider
performing the access.

---

### BR-25 — Audit does not modify clinical provenance

Recording access to clinical information must not change:

- original author;
- responsible Veterinarian;
- Clinic of origin;
- Veterinary Organization of origin;
- Clinical Record content;
- Clinical Amendment history.

Auditability and clinical provenance are separate concerns.

---

### BR-26 — Guardian access may be auditable

When an authorized Guardian views a Pet's protected medical history, the system
must be capable of recording that access where the applicable audit policy
requires it.

The audit record must preserve the acting Guardian User rather than only the
fact that some Guardian accessed the Pet.

---

### BR-27 — Shared Guardians remain independently auditable

When Maria and Carlos are both active Guardians of Luna, their medical-history
accesses must remain independently attributable.

The system must not collapse both Users into one generic:

    Guardian access

identity.

---

### BR-28 — Former Guardian denied access may be auditable

If a former Guardian attempts to access a Pet's protected medical history after
their Guardianship has ended, the denied attempt may be recorded as a
security-relevant Medical Access Audit Event.

The historical Guardianship must not cause the operation to be recorded as
permitted.

---

### BR-29 — Revoked Care Authorization denied access may be auditable

When a professional attempts access through a revoked Care Authorization, the
system may record:

- the acting User;
- Pet;
- Clinic context;
- attempted access type;
- denied outcome;
- authorization context indicating the Care Authorization was no longer valid.

The audit record must not restore the revoked authorization.

---

### BR-30 — Limited active-care continuity must remain distinguishable

Where `SPEC-ACC-002` permits minimum continuing access after Care Authorization
revocation to safely conclude an already-started Clinical Encounter, audit
information must be capable of distinguishing that access context from normal
active Care Authorization access.

This prevents exceptional continuity access from appearing as ordinary
unrestricted access.

---

### BR-31 — Audit history survives Care Authorization revocation

Revoking Care Authorization must not erase Medical Access Audit Events created
while that authorization was active.

Historical access and current authorization are separate concepts.

---

### BR-32 — Audit history survives Guardianship changes

Ending a User's Guardianship relationship must not erase previous Medical
Access Audit Events associated with that User's earlier authorized access.

---

### BR-33 — Audit history survives professional relationship changes

If a Veterinarian later:

- leaves the Clinic;
- leaves the Organization;
- changes Clinic Assignment;
- changes employer;

previous Medical Access Audit Events must remain attributed to the professional
and provider context that existed when access occurred.

---

### BR-34 — Subscription termination does not erase audit history

Loss or termination of a Veterinary Organization subscription must not erase
required historical Medical Access Audit Events.

Commercial state must not rewrite historical accountability.

---

### BR-35 — Audit Events must not be ordinarily mutable by audited Users

A User whose medical access was audited must not be able to delete or rewrite
the corresponding Audit Event through ordinary application behavior.

Audit integrity must not depend on the audited actor's cooperation.

---

### BR-36 — Audit correction must be controlled and traceable

If an Audit Event itself contains incorrect operational metadata, any
correction mechanism must preserve traceability.

The system must not silently rewrite security history in a way that destroys
the original audit trail.

The exact audit-correction mechanism is outside this Specification.

---

### BR-37 — Audit-required protected operations fail closed when durable audit capture fails

When a protected medical-access operation is classified as audit-required, the
operation must not succeed if its required Medical Access Audit Event cannot be
durably established.

For an audit-required permitted read:

    authorization valid
          +
    required audit durably captured
          ↓
    protected information may be released

If durable audit capture fails:

    protected information must not be released

For an audit-required domain mutation, where the mutation itself requires a
Medical Access Audit Event, the protected domain change and its required audit
evidence must commit coherently.

The system must not expose:

    protected change committed
        +
    required Audit Event missing

or:

    Audit Event records successful protected change
        +
    protected change did not commit

The exact transaction or trusted-backend mechanism is architectural and is
governed by ADR-004.

Failure of a secondary observability or log-exporting service after durable
audit capture has succeeded does not constitute failure of the authoritative
medical audit operation.

---

### BR-38 — Auditability must not depend on successful UI rendering

If protected medical information was validly disclosed by trusted backend
infrastructure, required audit behavior must not depend on whether:

- the client rendered the screen correctly;
- the User scrolled to the information;
- the React component completed rendering.

The audited event represents protected data access, not UI behavior.

---

### BR-39 — Audit Event creation must not grant medical access

Creating or querying an Audit Event must not itself provide access to the
underlying protected medical information.

Audit authorization and medical-content authorization are separate concerns.

---

### BR-40 — Audit Event creation must be atomic with its essential metadata

A Medical Access Audit Event must not be considered valid unless its essential
audit context is coherently established.

Where applicable, this includes:

- acting User or process;
- Pet;
- timestamp;
- access context;
- resource scope;
- outcome.

The exact transaction mechanism is architectural.

---

### BR-41 — Audit-required read is recorded before protected information is released

For an audit-required read operation, the required Medical Access Audit Event
must be durably established before the protected medical information is
released to the caller.

Authorization evaluation alone is insufficient to complete the disclosure.

Conceptually:

    evaluate authorization
          ↓
    determine permitted resource scope
          ↓
    durably establish Audit Event
          ↓
    release protected information

---

### BR-42 — Denied access remains denied if denial-audit persistence fails

Failure to record a denied Medical Access Audit Event must never cause a denied
protected operation to become permitted.

Where the audit policy requires the denied attempt to be recorded and that
recording fails:

- protected information remains unavailable;
- the authorization denial remains authoritative;
- the audit-persistence failure must be surfaced through operational
  diagnostics.

Audit failure must never become an authorization bypass.

---

### BR-43 — Meaningful audited operations have trusted correlation identity

A meaningful audit-relevant protected operation must be capable of carrying a
trusted operation correlation identifier.

The correlation identifier must be established by trusted backend
infrastructure.

An arbitrary client-provided identifier must not become authoritative merely
because the client supplied it.

---

### BR-44 — Correlation does not replace domain identity

An operation correlation identifier may associate:

- authorization evaluation;
- protected medical access;
- Medical Access Audit Event;
- trusted operational diagnostics.

It must not replace explicit domain references such as:

- User;
- Pet;
- Clinic;
- Veterinary Organization;
- Care Authorization;
- Clinical Encounter;
- Clinical Record Entry;
- Clinical Amendment;
- Clinical Attachment.

---

### BR-45 — Related technical activity may share one meaningful audit correlation

Several low-level technical operations performed as part of one meaningful
protected domain operation may share the same trusted correlation context.

This must not require creation of one Medical Access Audit Event per:

- SQL statement;
- database row;
- authorization query;
- pagination helper;
- storage-infrastructure call.

ADR-002 domain-level audit semantics continue to apply.

---

### BR-46 — Authoritative audit persistence is distinct from external observability

A required Medical Access Audit Event is authoritative audit evidence.

External systems used for:

- monitoring;
- alerting;
- log shipping;
- analytics;
- dashboards;
- diagnostics

are separate concerns.

Once the required Audit Event has been durably captured, later failure to
export or observe that event must not retroactively invalidate the protected
operation.

---

### BR-47 — Audit history is append-only through ordinary application behavior

Medical Access Audit Events represent historical security evidence.

Ordinary application workflows and audited actors must not:

- modify an existing Event;
- delete an existing Event;
- change its original outcome;
- replace its acting User;
- replace its Pet;
- rewrite its original access time.

If future requirements permit correction of incorrect audit metadata, the
correction must preserve the original Event through an append-only corrective
mechanism or equivalent traceable behavior.

The detailed correction workflow is outside Phase 1.

---

### BR-48 — Phase 1 audit-required medical-access operations are explicit

Phase 1 classifies the following meaningful protected medical-access operations as audit-required:

- `VIEW_PET_MEDICAL_HISTORY`;
- `VIEW_CLINICAL_RECORD_ENTRY`;
- `VIEW_CLINICAL_ATTACHMENT`;
- `ACCESS_FOR_APPOINTMENT_OPERATIONS`;
- `ACCESS_FOR_CLINICAL_CARE`;
- `ACCESS_FOR_POST_CARE_DOCUMENTATION`.

The operation identifiers represent domain-level access purposes.

They must not correspond one-to-one with:

- SQL queries;
- database rows;
- HTTP requests;
- pagination calls;
- React renders;
- object-storage implementation calls.

A single meaningful User operation may involve several lower-level technical operations while producing one coherent Medical Access Audit Event or one correlated audit context.

---

### BR-49 — VIEW_PET_MEDICAL_HISTORY is audit-required

When an authenticated User is permitted to view a Pet's protected longitudinal
medical history, the meaningful history-access operation is audit-required.

This applies to:

- professional access;
- authorized operational access;
- Guardian access.

Where the history includes information created by other Clinics or Veterinary Organizations, the applicable provider and cross-Clinic authorization context must remain identifiable.

Pagination or retrieval of several Clinical Record Entries as part of the same meaningful history-browsing operation must not require one independent Audit Event per record solely because several records were returned.

---

### BR-50 — VIEW_CLINICAL_RECORD_ENTRY is audit-required

Direct access to the protected content of a Clinical Record Entry is
audit-required.

Where opening a specific Entry is merely part of an already-established
meaningful `VIEW_PET_MEDICAL_HISTORY` operation, the architecture may preserve one coherent correlated audit context rather than generating artificial duplicate events.

The audit record must not duplicate the complete clinical content.

---

### BR-51 — VIEW_CLINICAL_ATTACHMENT is audit-required

Access to the protected binary content of a Clinical Attachment is
audit-required.

This includes meaningful operations that release the protected file content, such as:

- viewing;
- downloading;
- opening through a temporary authorized access mechanism.

The Audit Event should identify the applicable Clinical Attachment where
practical.

Generating or retrieving infrastructure metadata that does not disclose the
protected binary content must not independently create another domain Audit
Event merely because object storage was involved.

---

### BR-52 — ACCESS_FOR_APPOINTMENT_OPERATIONS is audit-required when protected medical information is accessed

Appointment management does not inherently constitute medical access.

However, when an authorized Clinic actor accesses protected medical information for an Appointment-related operational purpose, that protected access is audit-required.

Applicable purposes include, where supported:

- Appointment triage;
- preparation before confirmation;
- determining relevant professional routing;
- Veterinarian Assignment or reassignment where protected medical information is actually consulted.

Viewing ordinary Appointment metadata without accessing protected medical
information does not require a Medical Access Audit Event solely because an
Appointment operation occurred.

---

### BR-53 — ACCESS_FOR_CLINICAL_CARE is audit-required when existing protected medical information is accessed

When an authorized professional accesses existing protected medical
information while providing or preparing active veterinary care, that access is audit-required.

The applicable Clinical Encounter should remain identifiable where one exists.

The Audit Event must preserve the applicable professional, Clinic,
Organization, Care Authorization, and access-purpose context where relevant.

Creating the Clinical Encounter alone does not constitute a Medical Access
Audit Event unless that operation also accesses protected medical information.

---

### BR-54 — ACCESS_FOR_POST_CARE_DOCUMENTATION is audit-required when protected medical information is accessed

Where a Clinical Encounter has concluded but an authorized professional retains
limited access to complete legitimate documentation belonging to that care
episode, any access to existing protected medical information through that
continuity context is audit-required.

The audit context must distinguish post-care documentation access from:

- ordinary active-care access;
- unrelated future care;
- unrestricted historical browsing.

This rule also applies where limited continuity follows Care Authorization
revocation or Entitlement loss according to the applicable Specifications.

---

### BR-55 — Authenticated security-relevant denied medical access is audit-required

For Phase 1, an authenticated attempt to perform an audit-required protected
medical-access operation must also be audited when authorization denies the
operation and trusted infrastructure can establish a meaningful domain context.

The Audit Event must preserve:

- the attempted operation;
- `DENIED` outcome;
- acting User;
- Pet;
- applicable Clinic or Organization context where relevant;
- evaluated authorization basis or reason context where appropriate.

Examples include:

- a Veterinarian attempting medical-history access without an applicable Care
  Authorization;
- a professional attempting to reuse a `REVOKED` or `ENDED` Care Authorization;
- a former Guardian attempting to access a Pet's medical history;
- an actor attempting to use authorization belonging to another Pet;
- an actor attempting to use a Clinic-specific authorization from the wrong
  Clinic context.

A denied Audit Event must not itself reveal the protected medical content.

---

### BR-56 — Anonymous pre-domain failures are not Phase 1 Medical Access Audit Events

An anonymous request that is rejected before trusted infrastructure can
establish:

- an authenticated acting User;
- a Pet;
- a meaningful protected medical operation;
- an applicable domain authorization context

does not require a Medical Access Audit Event in Phase 1.

Such activity belongs to security, infrastructure, or application logging.

Once a meaningful authenticated domain access attempt exists, the applicable
Medical Access Audit policy applies.

---

### BR-57 — Domain traceability does not require duplicate Medical Access Audit Events

The following Phase 1 operations do not require an additional Medical Access
Audit Event solely because they are clinically or security relevant when their
own authoritative domain model already preserves the required actor, time,
state, and historical context:

- creating a Clinical Encounter;
- concluding a Clinical Encounter;
- creating or editing a Draft Clinical Record Entry;
- finalizing a Clinical Record Entry;
- creating a Clinical Amendment;
- creating or managing Clinical Attachment metadata;
- granting Care Authorization;
- revoking Care Authorization;
- normally ending Care Authorization;
- Appointment lifecycle transitions;
- Veterinarian Assignment or reassignment when no protected medical
  information is accessed.

These operations remain subject to their own authorship, provenance,
traceability, security, and auditability requirements.

If one of these operations also performs an audit-required protected medical
access, that medical access must still be audited.

A future Specification may explicitly classify additional mutations as
requiring a Medical Access Audit Event.

---

## 4. Medical Access Audit Event Information

The audit domain must support enough information to reconstruct a meaningful
protected medical-access event without unnecessarily duplicating clinical
content.

### Required where applicable

- Audit Event identity;
- acting User or authorized process;
- Pet;
- access timestamp;
- access operation or purpose;
- access outcome;
- actor context;
- protected resource scope.
- trusted operation correlation identifier.

### Professional context where applicable

- Clinic;
- Veterinary Organization;
- professional role or capability context;
- applicable Care Authorization or other medical-access basis.

### Resource context where applicable

- Clinical Record Entry identity;
- Clinical Amendment identity;
- Clinical Attachment identity;
- Clinical Encounter identity;
- longitudinal-history access scope.

The audit record should not duplicate complete protected clinical content.

---

## 5. Scenarios

### Scenario: Guardian medical-history access is audited

Given Maria has an active Guardianship relationship with Luna  
And Maria is authorized to view Luna's finalized medical history

When Maria accesses Luna's longitudinal medical history through an
audit-relevant operation

Then the medical history may be returned  
And a Medical Access Audit Event may record Maria as the acting User  
And Luna as the Pet  
And the Guardian context  
And the access time  
And the permitted outcome

---

### Scenario: Shared Guardians are audited independently

Given Maria and Carlos are both active Guardians of Luna

When Maria accesses Luna's history  
And Carlos later accesses Luna's history

Then the two access events may remain independently attributable  
And Maria's access is not collapsed into Carlos's access  
And both remain associated with Luna

---

### Scenario: Professional cross-clinic access is audited

Given Luna has historical finalized medical information from Animalia Madrid
Centro  
And Luna currently has a valid Care Authorization for VetCare Toledo  
And Dr. Lopez is authorized to access relevant history through VetCare Toledo

When Dr. Lopez accesses Luna's relevant Animalia history

Then a Medical Access Audit Event may identify Dr. Lopez  
And VetCare Toledo as the accessing Clinic context  
And the applicable Veterinary Organization context  
And the Care Authorization used for access  
And Luna as the Pet  
And the access outcome as permitted  
And Animalia remains the provider of origin of the clinical information

---

### Scenario: Appointment triage access is distinguishable

Given Luna has a requested Appointment at Animalia Madrid Centro  
And a valid Pet Care Authorization exists  
And Carlos has a limited authorized triage context

When Carlos accesses relevant medical information to organize Luna's care

Then the access may be audited as an Appointment triage access context  
And the Audit Event does not imply that Carlos had unrestricted clinical
access  
And the applicable least-privilege scope remains meaningful

---

### Scenario: Clinical-care access is distinguishable from triage access

Given Dr. Garcia is providing care to Luna in a valid Clinical Encounter

When Dr. Garcia accesses Luna's relevant protected medical history as part of
the clinical care

Then the Audit Event may identify the clinical-care context  
And that context remains distinguishable from an earlier operational triage
access

---

### Scenario: Opening Clinical Attachment is independently auditable

Given Maria is authorized to view Luna's finalized medical history  
And a Clinical Record Entry contains a protected PDF Attachment

When Maria opens the PDF through an audit-relevant file-access operation

Then an Audit Event may identify the Clinical Attachment  
And Maria as the acting User  
And Luna as the Pet  
And the access outcome as permitted

---

### Scenario: Signed file access does not bypass auditing

Given Dr. Garcia is authorized to access Luna's protected Clinical Attachment  
And the technical architecture uses a short-lived file-access mechanism

When the protected file access is established

Then the required medical-access audit context is recorded or otherwise
established through trusted infrastructure  
And possession of the technical file reference does not bypass auditing

---

### Scenario: Veterinarian without authorization is denied and audited

Given Dr. Lopez has a Veterinarian Professional Profile  
And no applicable current medical-access basis exists for Luna

When Dr. Lopez makes a security-relevant attempt to access Luna's protected
medical history

Then access is denied  
And the audit policy may record the denied attempt  
And the Audit Event identifies Dr. Lopez  
And Luna  
And the denied outcome  
And Veterinarian status does not become an access basis

---

### Scenario: Former Guardian access attempt is denied

Given Carlos previously had Guardianship of Luna  
And Carlos's Guardianship has ended  
And Carlos has no other medical-access basis

When Carlos attempts to access Luna's medical history

Then access is denied  
And the security-relevant denied attempt may be audited  
And historical Guardianship does not produce a permitted audit outcome

---

### Scenario: Revoked Care Authorization access attempt is denied

Given VetCare Toledo previously had a Care Authorization for Luna  
And that Care Authorization has been revoked  
And no other valid access basis exists

When Dr. Lopez attempts to access Luna's history through the revoked context

Then access is denied  
And the denied attempt may be audited  
And the historical Care Authorization remains identifiable without becoming
current authorization

---

### Scenario: Limited continuity after revocation is distinguishable

Given Luna's Care Authorization was revoked during an already-started Clinical
Encounter  
And `SPEC-ACC-002` permits minimum continuing access required to safely
conclude care

When Dr. Garcia accesses information under that limited continuity context

Then the access may be permitted according to the applicable rules  
And the Audit Event can distinguish limited continuity from normal active Care
Authorization access

---

### Scenario: Medical access auditing does not duplicate full record content

Given Dr. Garcia accesses a Finalized Clinical Record Entry containing
sensitive diagnostic information

When the access is audited

Then the Audit Event identifies the relevant protected resource or resource
scope  
And it does not need to copy the complete diagnostic content into the audit
record

---

### Scenario: React rerender does not create artificial domain Audit Events

Given Maria has validly opened Luna's medical-history view  
And the mobile interface rerenders the same already-authorized information
several times without a new protected backend access

When those UI rerenders occur

Then they do not independently require new domain Medical Access Audit Events
solely because presentation rerendered

---

### Scenario: Pagination may be represented as one meaningful access context

Given Luna has a large longitudinal medical history  
And Maria performs one logical medical-history browsing operation  
And the backend retrieves several pages of information

When the audit policy aggregates those reads into one meaningful access context

Then the domain need not represent every page retrieval as an unrelated medical
access event  
And meaningful auditability is preserved

---

### Scenario: Employment change does not rewrite previous Audit Event

Given Dr. Garcia accessed Luna's history while acting through Animalia Madrid
Centro  
And Dr. Garcia later joins VetCare Group

When the historical Medical Access Audit Event is reviewed

Then the access remains attributed to Dr. Garcia  
And the Animalia Madrid Centro context that applied at the time  
And the later employment change does not rewrite the audit history

---

### Scenario: Care Authorization revocation does not erase previous Audit Events

Given Dr. Garcia validly accessed Luna's history under Care Authorization A  
And Care Authorization A is later revoked

When the historical audit trail is reviewed

Then Dr. Garcia's earlier access remains recorded  
And it remains associated with the authorization context that was valid at the
time  
And revocation does not erase the historical access event

---

### Scenario: Subscription termination does not erase Audit Events

Given Animalia Veterinary Group has historical Medical Access Audit Events

When Animalia's subscription later ends

Then required historical audit information remains preserved  
And commercial state does not erase security accountability

---

### Scenario: User cannot delete their own Audit Event

Given Dr. Garcia has a Medical Access Audit Event associated with her previous
access to Luna's history

When Dr. Garcia attempts to delete or rewrite that Event through ordinary
application behavior

Then the operation is denied  
And the audit history remains protected

---

### Scenario: Required audit succeeds before protected history is released

Given Dr. Garcia is authorized to view Luna's protected medical history
And the operation is classified as audit-required

When Dr. Garcia requests the protected history
And the required Medical Access Audit Event is durably established

Then the protected information may be returned
And the Audit Event records the permitted access context

---

### Scenario: Required audit failure prevents protected read

Given Dr. Garcia would otherwise be authorized to view Luna's protected medical
history
And the operation is classified as audit-required

When the required Medical Access Audit Event cannot be durably established

Then Luna's protected information is not released through that operation
And the system does not report the protected access as successfully completed
And the audit-persistence failure is surfaced operationally

---

### Scenario: Denial remains effective when denial audit fails

Given Dr. Lopez has no valid medical-access basis for Luna
And Dr. Lopez performs a security-relevant access attempt
And the audit policy requires that denied attempt to be recorded

When authorization denies the operation
And persistence of the denied Audit Event also fails

Then access remains denied
And Luna's protected information is not released
And audit failure does not convert the denial into permission
And the audit-persistence failure is surfaced operationally

---

### Scenario: Protected mutation and required audit commit coherently

Given an authorized protected domain mutation requires a Medical Access Audit
Event

When the operation succeeds

Then the protected domain mutation and its required Audit Event are committed
coherently
And the system does not expose the mutation as successful without its required
audit evidence

---

### Scenario: Failed protected mutation does not produce false permitted history

Given a protected domain mutation requires a Medical Access Audit Event

When the protected mutation cannot be committed

Then the system must not preserve an Audit Event claiming that the mutation
successfully occurred when it did not

---

### Scenario: Related protected activity shares trusted correlation

Given Dr. Garcia performs one meaningful audit-relevant operation to view
Luna's longitudinal history
And trusted infrastructure performs several internal authorization and data
retrieval operations

When the access is audited

Then the meaningful domain operation has a trusted correlation identifier
And relevant trusted diagnostics may use the same correlation context
And separate Medical Access Audit Events are not required solely for every
internal technical operation

---

### Scenario: Client correlation value is not authoritative

Given a manipulated client submits an arbitrary correlation identifier

When trusted infrastructure performs an audit-relevant protected operation

Then trusted infrastructure establishes or validates the authoritative
correlation context
And the client cannot use its supplied identifier to falsify audit attribution

---

### Scenario: External monitoring failure does not invalidate durable audit

Given Dr. Garcia performs an audit-required permitted access
And the required Medical Access Audit Event is durably captured

When a later external log-exporting or monitoring operation fails

Then the protected access remains valid
And the required medical audit evidence remains available
And the external observability failure is handled separately

---

### Scenario: Guardian medical-history view is audit-required

Given Maria is an active Guardian of Luna
And Maria is authorized to view Luna's protected medical history

When Maria views Luna's longitudinal medical history

Then the access is permitted
And a Medical Access Audit Event is durably established
And Maria is identified as the acting Guardian
And Luna is identified as the Pet

---

### Scenario: Professional cross-Clinic history view is one meaningful audited access

Given Dr. Garcia validly accesses Luna's longitudinal history
And the returned history contains information from Animalia and VetCare

When the protected history is released

Then the meaningful history access is audited
And the cross-Clinic provider context remains identifiable
And one Audit Event per returned Clinical Record Entry is not required solely
because several Clinics contributed to the history

---

### Scenario: Protected Attachment access is audited

Given Dr. Garcia is authorized to access a protected Clinical Attachment

When the Attachment content is released

Then the protected access is audited
And the applicable Clinical Attachment may be identified from the Audit Event

---

### Scenario: Appointment metadata access alone is not a Medical Access Audit Event

Given Carlos is authorized to manage Luna's Appointment
And Carlos views only ordinary Appointment scheduling information
And no protected medical information is accessed

When Carlos performs that Appointment operation

Then no Medical Access Audit Event is required solely because the Appointment
was viewed

---

### Scenario: Appointment triage medical access is audited

Given Carlos is authorized to perform Appointment triage
And the applicable Care Authorization permits limited protected medical access

When Carlos accesses the permitted medical information for triage

Then the medical access is audit-required
And its purpose is attributable to the Appointment operational context

---

### Scenario: Authenticated unauthorized medical access is audited as denied

Given Dr. Garcia is authenticated
And Dr. Garcia has no valid medical-access basis for Luna

When Dr. Garcia attempts to view Luna's protected medical history

Then the operation is denied
And Luna's medical information is not released
And a Medical Access Audit Event records the attempted history-view operation
And its outcome is `DENIED`

---

## 6. Phase 1 Audit Scope

Phase 1 audit-required protected medical-access operations are:

    VIEW_PET_MEDICAL_HISTORY
    VIEW_CLINICAL_RECORD_ENTRY
    VIEW_CLINICAL_ATTACHMENT
    ACCESS_FOR_APPOINTMENT_OPERATIONS
    ACCESS_FOR_CLINICAL_CARE
    ACCESS_FOR_POST_CARE_DOCUMENTATION

The same attempted operation may have:

    PERMITTED

or:

    DENIED

outcome.

`DENIED_MEDICAL_ACCESS` is therefore not required as a separate operation
identifier.

Cross-Clinic access is preserved as part of the applicable provider,
authorization, and resource context rather than requiring a separate
fundamental access operation.

A meaningful operation may aggregate several low-level technical reads.

Audit aggregation must not hide a genuinely separate User access operation.

Phase 1 does not require a Medical Access Audit Event merely for:

- technical authorization queries;
- database row reads performed within one meaningful audited operation;
- pagination;
- UI rerenders;
- storage implementation calls;
- ordinary Appointment metadata access;
- domain mutations whose own approved model already preserves the required
  historical traceability and that do not themselves disclose protected
  medical information.

---

## 7. Access Outcome

The Audit Event model must distinguish successful protected access from denied
access attempts where such attempts are included in audit policy.

Conceptually:

    PERMITTED

or:

    DENIED

A permitted outcome means the protected access operation was authorized.

A denied outcome means the requested protected access was not provided through
that operation.

Audit outcome must not be inferred merely from HTTP status codes without the
applicable domain authorization context.

---

## 8. Professional Access Context

For professional medical access, the system should be capable of reconstructing
a context conceptually equivalent to:

    User:
    Dr. Garcia

    Pet:
    Luna

    Clinic:
    Animalia Madrid Centro

    Organization:
    Animalia Veterinary Group

    Purpose:
    Clinical care

    Access basis:
    Care Authorization A

    Resource:
    Longitudinal medical history

    Outcome:
    PERMITTED

    Time:
    2026-09-10 10:23

The exact persistence representation is not defined by this Specification.

---

## 9. Guardian Access Context

Guardian access may require less professional context but must remain
attributable.

Conceptually:

    User:
    Maria

    Pet:
    Luna

    Context:
    Active Guardianship

    Resource:
    Longitudinal medical history

    Outcome:
    PERMITTED

    Time:
    2026-09-12 19:05

The User identity and Pet relationship must remain explicit.

---

## 10. Audit Integrity

Medical Access Audit Events form part of the security and accountability
history of the system.

Ordinary audited Users must not be able to destructively rewrite that history.

The architecture should provide appropriate protection against unauthorized
modification or deletion.

This Specification does not require a specific append-only storage technology,
cryptographic log design, or external security platform.

Those choices may be recorded through architectural decisions when needed.

---

## 11. Edge Cases

### Anonymous access attempt

Normal protected medical information requires authenticated access.

Anonymous requests that fail before a meaningful User or domain access context
can be established may be handled through security or infrastructure logging
rather than permanent Medical Access Audit Events.

The exact boundary is architectural.

---

### System process accesses protected medical data

A trusted automated process may eventually require access to protected medical
information.

Where such access is audit-relevant, the acting system process must be
identifiable rather than falsely attributing the access to a human User.

---

### Background technical processing

Infrastructure operations such as backups, replication, encryption, integrity
checks, or storage maintenance must not automatically be represented as human
medical-access events.

Security and infrastructure audit requirements may apply separately.

---

### Failed audit subsystem

If an audit-required Medical Access Audit Event cannot be durably established,
the protected operation must fail closed.

For a protected read, the medical information must not be released.

For an applicable protected mutation, the mutation must not be exposed as
successfully committed without its required audit evidence.

A denied operation remains denied even if persistence of its denial Audit Event
also fails.

Failure of external monitoring, analytics, or log-exporting infrastructure
after authoritative audit evidence has already been durably captured does not
constitute failure of the Medical Access Audit Event itself.

See ADR-004.

---

### Very frequent professional access during active care

A Veterinarian may access the same Pet's medical information repeatedly during
one Clinical Encounter.

The audit model may group or correlate related access into a meaningful care
session where doing so preserves required accountability.

The exact session or correlation mechanism is architectural.

---

### Cached information on client device

Previously fetched protected information may exist temporarily in authorized
client state.

Medical Access Audit Events primarily represent trusted protected-data access
operations.

Secure client caching, persistence, expiration, and revocation behavior are
architectural security concerns and must not create permanent authorization.

---

### Audit retention

Medical Access Audit Events may require long retention periods.

The exact retention period depends on security, legal, and operational policy
and is not defined by this Specification.

---

## 12. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 13. Dependencies

- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-MED-005 — View Pet Medical History
- SPEC-MED-007 — Add Clinical Attachment
- SPEC-ID-003 — Authenticate User
- SPEC-PET-003 — Accept Guardianship Invitation
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment

Clinical-care access may additionally relate to:

- SPEC-MED-001 — Create Clinical Encounter

Architectural audit behavior follows:

- ADR-002 — Use Domain-Level Medical Access Auditing
- ADR-004 — Fail Closed When Required Medical Audit Cannot Be Durably Captured

---

## 14. Out of Scope

This Specification does not define:

- audit-log viewing UI;
- which Organization roles may inspect audit history;
- Guardian visibility into access history;
- security-alert generation;
- suspicious-access detection;
- SIEM integration;
- exact audit retention duration;
- exact audit storage technology;
- cryptographic audit-log signing;
- infrastructure logs;
- database query logs;
- analytics;
- client telemetry;
- emergency medical access;
- detailed incident-response workflows.

---

## 15. Verification Notes

Verification must demonstrate that:

1. meaningful protected medical access can be recorded as a Medical Access
   Audit Event;
2. audit recording occurs through trusted infrastructure rather than relying
   solely on the client;
3. audit scope distinguishes domain-relevant access from low-level technical
   noise;
4. permitted medical access may be audited;
5. security-relevant denied access may be audited;
6. acting User and Pet remain identifiable;
7. Guardian and professional access contexts remain distinguishable;
8. professional access preserves applicable Clinic and Organization context;
9. Care Authorization or other applicable access basis may remain traceable;
10. permitted and denied outcomes remain distinguishable;
11. resource scope may be identified without duplicating full medical content;
12. Clinical Attachment access can remain independently auditable where
    required;
13. technical file-delivery mechanisms do not bypass medical-access
    auditability;
14. cross-clinic audit information distinguishes provider of origin from
    accessing provider;
15. audit recording does not modify clinical provenance;
16. shared Guardians remain independently attributable;
17. revocation and Guardianship changes do not erase historical Audit Events;
18. professional or subscription changes do not rewrite audit history;
19. audited Users cannot ordinarily delete or rewrite their own Audit Events;
20. auditing does not itself grant access to protected medical information;
21. required audit failures cannot be silently ignored;
22. audit records remain protected and data-minimized.
23. an audit-required permitted protected operation does not succeed when its
    required Audit Event cannot be durably captured;
24. an audit-required protected read does not release medical information before
    required durable audit capture;
25. a denied access remains denied when persistence of its denied Audit Event
    fails;
26. audit failure cannot create an authorization bypass;
27. applicable protected mutations and their required Audit Events commit
    coherently;
28. failed protected mutations do not leave Audit Events falsely claiming a
    successful permitted mutation;
29. meaningful audited operations may carry a trusted correlation identifier;
30. client-provided correlation identifiers are not authoritative by
    themselves;
31. correlation does not replace explicit User, Pet, Clinic, Organization,
    authorization, or resource identity;
32. several low-level technical operations may remain part of one meaningful
    domain audit context;
33. durable medical audit capture remains distinct from external observability
    delivery;
34. failure of external monitoring after durable audit capture does not
    retroactively invalidate the protected operation;
35. ordinary application behavior cannot destructively rewrite append-only
    Medical Access Audit history.
36. Phase 1 has an explicit closed set of audit-required medical-access
    operation categories;
37. Guardian longitudinal medical-history access is audit-required;
38. professional longitudinal medical-history access is audit-required;
39. cross-Clinic access preserves provider context without requiring a separate
    audit event for every contributing Clinic or Entry;
40. direct protected Clinical Record Entry access is audit-required;
41. protected Clinical Attachment content access is audit-required;
42. Appointment operations are audit-required only when they access protected
    medical information;
43. active Clinical Encounter medical access is audit-required;
44. post-care and limited-continuity medical access is audit-required;
45. authenticated security-relevant denials of audit-required operations are
    themselves audit-required;
46. the attempted operation and `DENIED` outcome remain distinct concepts;
47. anonymous failures before meaningful authenticated domain context may
    remain technical security logs rather than Medical Access Audit Events;
48. ordinary clinical or lifecycle mutations do not receive duplicate Medical
    Access Audit Events solely because they are important;
49. such mutations still require a Medical Access Audit Event when they also
    perform an independently audit-required protected medical read;
50. technical reads, pagination, rerenders, and internal authorization checks do
    not independently create domain Audit Events.
    
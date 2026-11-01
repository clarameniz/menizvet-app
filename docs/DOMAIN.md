# Domain Model

**Status:** Draft
**Version:** 0.2

## 1. Purpose

This document defines the shared domain language, conceptual relationships, and fundamental invariants of the Veterinary Care Platform.

Its purpose is to ensure that requirements, specifications, code, tests, database structures, and API contracts use the same domain concepts consistently.

This document describes **what concepts mean**.

It intentionally does not define:

* database tables;
* foreign keys;
* API endpoints;
* framework-specific models;
* UI components;
* implementation architecture.

Those must be derived later from requirements, specifications, and architectural decisions.

---

# 2. Modeling Principles

## 2.1 Domain concepts must not be reduced to UI roles

Concepts such as Guardian, Veterinarian, Administrator, and Organization
Member must not be modeled as mutually exclusive global User types.

They arise from different domain structures:

- Guardian capability derives from current Guardianship;
- Veterinarian represents professional identity associated with a
  Veterinarian Professional Profile;
- Organization Member derives from Organization Membership;
- Administrator represents a scoped Organization Responsibility Grant.

One User may validly participate in several of these contexts simultaneously.

They are not mutually exclusive account types.

There is no stored professional User type or flag. A User's professional
context is derived at evaluation time from:

- active Organization Memberships;
- applicable active Organization Responsibility Grants and the capabilities
  they provide;
- a Veterinarian Professional Profile, where applicable;
- current Veterinarian Clinic Assignments, where applicable;
- the Organization's current Entitlements, for paid professional operations.

The same User may hold Guardian and professional contexts at the same time.

---

## 2.2 Current state and historical truth are different

The platform must distinguish between:

* what is true now;
* what was true when a historical event occurred.

Historical clinical information must never be reconstructed exclusively from current relationships.

---

## 2.3 Business organization and physical location are different

A veterinary business may operate multiple physical Clinics.

The platform must therefore distinguish between the commercial Organization and each care location.

---

## 2.4 Medical provenance is part of the domain

Clinical information must preserve where it came from, who produced it, and when it occurred.

Provenance is not merely logging metadata.

It is part of the medical meaning of the record.

---

## 2.5 Authorization is relationship-based

Access is derived from relationships and context rather than from a single global role field.

---

# 3. Identity Domain

## 3.1 User

A **User** represents a person with an identity in the platform.

A User may authenticate and establish relationships with other domain entities.

A User may simultaneously:

* be Guardian of one or more Pets;
* be a Veterinarian;
* belong to one or more Organizations;
* practice at one or more Clinics;
* administer an Organization;
* perform different responsibilities in different Organizations.

### Domain rules

* A person should normally have one platform identity.
* Personal and professional capabilities may coexist.
* Authentication identifiers are not domain roles.
* Clinic or Organization responsibilities must not be represented as mutually exclusive global User types.
* Changing professional relationships must not require creating a new User.

---

## 3.2 Authentication Identity

An **Authentication Identity** represents the credentials or identity mechanism used to authenticate a User.

The domain must not assume that a person's identity is permanently equivalent to one email address.

A User may reasonably have different personal and professional contact addresses during their lifetime.

The exact authentication implementation remains an infrastructure concern.

### Domain rules

* Authentication mechanism and professional identity are separate concepts.
* Changing an authentication identifier must not create a new Person conceptually.
* Professional Clinic email addresses must not determine ownership of professional history.

---

# 4. Pet Domain

## 4.1 Pet

A **Pet** represents an animal whose identity, care relationships, and veterinary history are managed by the platform.

A Pet exists independently from:

* current Guardians;
* current Clinic;
* current Veterinarian;
* Organization.

A Pet may receive care from multiple Clinics during its lifetime.

### Domain rules

* A Pet is not owned by a Clinic or Organization.
* A Pet's identity survives changes in Guardianship.
* A Pet's medical history survives changes in care provider.
* A Pet may be linked to multiple Guardians.

---

## 4.2 Pet Guardianship

**Pet Guardianship** represents an explicit relationship between a User and a
Pet from which current Guardian capability may be derived.

It is not a subtype of User.

Phase 1 does not distinguish differentiated Guardian roles or permission
levels.

A User may therefore be a current Guardian of a Pet independently from any
professional capability the same User may also hold.

Guardianship is temporal-capable.

Conceptually it preserves:

- the User;
- the Pet;
- when the Guardianship period began;
- whether that relationship is currently active;
- when it ended, where a future approved workflow establishes termination.

### Domain rules

- One User may have Guardianship relationships with multiple Pets.
- One Pet may have Guardianship relationships with multiple Users.
- Being a Veterinarian does not prevent a User from being a Guardian.
- A User account alone does not grant access to a Pet.
- Current Guardian capability requires a current active Guardianship.
- Historical Guardianship alone does not provide current Guardian capability.
- Historical Guardianship must be preserved rather than deleted when a
  relationship ends.
- An ended Guardianship period must not be reactivated.
- Future approved rejoining establishes a new Guardianship period.
- Phase 1 supports establishing Guardianship through Pet registration and the
  approved Guardian Invitation workflow.
- Phase 1 does not define a Guardianship-termination or transfer workflow merely
  because the persistence model supports historical periods.

Future differentiated Guardian responsibilities, transfer behavior, and
termination workflows require explicit Requirements and Specifications.

---

# 5. Veterinary Professional Domain

## 5.1 Veterinarian

A **Veterinarian** is a User with a recognized veterinary professional identity.

Veterinarian status belongs to the person rather than to an Organization or Clinic.

A Veterinarian may:

* work for multiple Organizations;
* practice at multiple Clinics;
* stop working for an Organization;
* move between Clinics;
* remain a Veterinarian after leaving an Organization;
* simultaneously act as a Pet Guardian.

### Domain rules

* Professional qualification is independent from employment.
* A Veterinarian must not require a separate professional User account.
* A Veterinarian may practice in multiple professional contexts.
* Being a Veterinarian does not automatically grant medical access.

---

## 5.2 Veterinarian Professional Profile

A **Veterinarian Professional Profile** represents professional information associated with a Veterinarian.

Phase 1 professional credential information includes the applicable
professional registration or license identifier and its issuing jurisdiction,
authority, or equivalent context.

It may include:

- specialties;
- biography;
- other professional presentation information required by approved workflows.

Future professional-verification behavior may associate platform verification
state with the applicable professional credential.

The presence of claimed professional credential information must not itself be
interpreted as platform verification.

Professional verification is delivered separately from the Phase 1
Professional Profile.

### Domain rules

* A professional profile belongs to one User.
* A professional profile is independent from a specific Organization.
* Moving between Organizations must not require creating a new professional profile.
* Verification and employment are separate concepts.

---

# 6. Veterinary Organization Domain

## 6.1 Veterinary Organization

A **Veterinary Organization** represents the business entity that operates veterinary services and subscribes to the platform.

Examples include:

* an independent veterinary practice;
* a veterinary company;
* a veterinary group operating multiple locations.

An Organization may operate one or more Clinics.

### Example

```text
Animalia Veterinary Group
├── Animalia Madrid Centro
├── Animalia Alcobendas
└── Animalia Getafe
```

### Domain rules

* The Organization is the commercial SaaS customer.
* A Veterinary Organization is established only through trusted Commercial
  Onboarding (§6.3). Authentication or verification alone never establishes an
  Organization.
* Every Organization is established together with its initial Owner
  Membership, its Owner responsibility, and its initial Subscription.
* Once established, an Organization continues to exist even if it later has no
  current Subscription, loses Entitlement, or its Subscription expires.
* An Organization exists independently from its members.
* An Organization may operate multiple Clinics.
* Historical records must remain associated with the relevant Organization context where needed.
* Removing a member does not remove the Organization's historical activity.

---

## 6.2 Organization Membership

An **Organization Membership** represents a User's temporal professional
relationship with a Veterinary Organization.

Membership itself establishes the professional relationship.

Organization capabilities are derived separately from the active
responsibilities granted within that Membership.

Conceptually, Membership has:

- a start;
- an optional end;
- zero or more Organization Responsibility Grants.

An **Organization Responsibility Grant** represents a controlled responsibility
held by the Member.

A Responsibility Grant:

- belongs to one Organization Membership;
- may have Organization-wide or Clinic-specific scope where supported;
- is temporal;
- may begin and end independently from the Membership;
- must remain historically identifiable after it ends.

Capabilities are derived from:

    authenticated User
        +
    active Organization Membership
        +
    active applicable Responsibility Grant
        +
    applicable scope
        +
    operation context

A capability is therefore not a permanent global property of the User.

Veterinarian professional identity is separate from Organization
responsibility.

For example, being a Veterinarian must not be modeled merely as an
Organization role.

Organization ownership is represented through an active Membership with the
applicable `OWNER` responsibility.

### Domain rules

- A User may belong to multiple Organizations.
- Membership history must be preserved.
- An ended Membership must not grant current Organization capabilities.
- Ending a Membership must not delete historical actions.
- Responsibility history must be preserved.
- An ended Responsibility Grant must not grant current capability.
- Regranting an ended responsibility establishes a new responsibility period.
- Organization and Clinic scope must remain distinguishable.
- Current relationships must not rewrite past events.
- A Veterinary Organization must retain at least one active Owner.
- An operation that would remove the last active Owner must not succeed.
- Ownership changes require an explicit ownership workflow.

### Organization Invitation

An **Organization Invitation** is the finite, pending offer through which a
person may establish a new Organization Membership (`SPEC-ORG-002`,
`SPEC-ORG-003`, `SPEC-ORG-010`).

- An Invitation belongs to one Organization, is addressed to a recipient email
  address, and records its intended responsibilities. It grants nothing while
  pending.
- The **Invitation reference** identifies an Invitation and proves nothing.
  The **Invitation secret** is a one-time bearer secret delivered only to the
  recipient address; presenting it, from an authenticated account with a
  confirmed email, is the proof of control of the recipient context. The
  accepting account's email need not equal the recipient address.
- An Invitation is valid for exactly 7 days from its creation, as determined
  by trusted backend time.
- A pending Invitation may be revoked by an authorized administrator. Revoked,
  expired, rejected, and accepted Invitations are no longer pending and remain
  as history.
- Acceptance establishes exactly one new Membership with exactly the intended
  responsibilities, atomically. It never reactivates an ended Membership and
  never creates a second domain User.

Staff management presentation and its identity-visibility context are defined
by `SPEC-ORG-009` and `SPEC-ID-006` BR-40. Ending a Membership removes all
authority derived from it immediately, because capability is always derived
from current relationships (INV-019), never from authentication tokens.

---

## 6.3 Commercial Onboarding

**Commercial Onboarding** is the trusted process through which a prospective
customer becomes a Veterinary Organization of the platform.

Commercial Onboarding:

- establishes the Veterinary Organization;
- establishes the initial Owner Membership and Owner responsibility for a
  designated initial Owner, who must already be an existing, verified User;
- establishes the Organization's initial Subscription, in the initial state
  determined by the commercial process (for example `PENDING` or `ACTIVE`).

Commercial Onboarding is not a User capability, not an Organization
responsibility, and not reachable by client applications. A User may request
it; only the trusted process performs it. Phase 1 may perform it through an
external, web, or manual process.

Phase 1 does not persist Commercial Onboarding requests as a domain concept.

Users who join an existing Organization through an Organization Invitation do
not go through Commercial Onboarding and do not need their own Subscription.

### Domain rules

- Only trusted Commercial Onboarding establishes a Veterinary Organization.
- Establishment never occurs without the initial Owner Membership and the
  initial Subscription.
- Establishment itself grants no paid professional Entitlement; Entitlement
  derives from Subscription state.
- Requesting Commercial Onboarding establishes nothing.

---

# 7. Clinic Domain

## 7.1 Clinic

A **Clinic** represents a physical veterinary care location operated by a Veterinary Organization.

A Clinic is the location where care is physically provided.

It may expose:

* name;
* address;
* geographic coordinates;
* public description;
* opening hours;
* contact information;
* offered services;

### Domain rules

* A Clinic belongs to an Organization.
* An Organization may operate multiple Clinics.
* Clinic identity must remain stable even when staff changes.
* A Clinic has provider-independent geographic identity.
* A currently published Clinic with the required valid public and geographic
  information may participate in public geographic Discovery.
* An unpublished Clinic must not participate in public Discovery.
* Publication or Discovery state does not determine whether the Clinic exists
  as a domain entity or historical provider.
* Publication is reversible: unpublishing removes the Clinic from public
  Discovery and new Guardian requests without deleting its configuration or
  affecting its existing Appointments.
* Medical actions performed at a Clinic retain that Clinic as historical provenance.

### Derived Clinic self-service statuses

Clinic self-service (`SPEC-CLI-007`) uses three derived statuses. None of them
is persisted, and they must not be collapsed into one another:

* **Ready to publish** — the Clinic has a valid public display name and a
  location, which are exactly the publication prerequisites.
* **Published** — the Clinic's persisted publication state; it makes the Clinic
  eligible for public Discovery.
* **Online Appointment setup complete** — an advisory status meaning the known
  configuration prerequisites for online Appointment requests are present
  (published, scheduling timezone, standard Appointment duration, current or
  future Appointment Availability, and the Organization's
  `APPOINTMENT_MANAGEMENT` Entitlement). It does not guarantee that any
  specific candidate time exists and is not called "bookable".

Publication and online Appointment setup are distinct: a published Clinic may
accept no online requests, and Opening Hours and Service Offerings affect
neither status.

---

## 7.2 Veterinarian Clinic Assignment

A **Veterinarian Clinic Assignment** represents the temporal professional
relationship through which a Veterinarian practices at a specific Clinic.

This concept is distinct from:

- Veterinarian Professional Profile;
- Organization Membership;
- Organization Responsibility Grant;
- Appointment Veterinarian Assignment.

A Veterinarian may belong to an Organization while being assigned only to some
of its Clinics.

Conceptually:

    Dr. Garcia
    Veterinarian Professional Profile
            +
    Animalia Organization Membership
            ↓
    Veterinarian Clinic Assignment
            ├── Animalia Madrid Centro
            └── Animalia Alcobendas

### Domain rules

- A Veterinarian may practice at multiple Clinics.
- Veterinarian Clinic Assignment is temporal.
- Current Assignment requires the applicable current professional context.
- Ending one Clinic Assignment does not necessarily end Organization Membership.
- An ended Clinic Assignment grants no current Clinic professional eligibility.
- Historical Clinic Assignments must remain identifiable.
- Historical clinical events preserve the Clinic where care occurred.
- Current Clinic Assignments must not determine historical provenance.
- Re-establishing a previously ended professional relationship creates a new
  Assignment period rather than rewriting the historical one.

---

# 8. Subscription Domain

## 8.1 Organization Subscription

An **Organization Subscription** represents the commercial relationship through
which a Veterinary Organization may obtain paid professional platform
capabilities.

The Subscription belongs to the Veterinary Organization.

Professional Entitlement is derived from authoritative current commercial state
and the capability being requested.

It is not a permanent property of the Organization or its Members.

Phase 1 defines the following normal professional Entitlement categories:

    APPOINTMENT_MANAGEMENT
    PROFESSIONAL_SCHEDULING
    CLINICAL_CARE
    CLINICAL_DOCUMENTATION

### Domain rules

- Pet Guardians do not require the professional Subscription for independent
  Guardian capability.
- Every Organization is established with an initial Subscription through
  Commercial Onboarding (§6.3). Once established, the Organization may later
  have no current Subscription and continues to exist.
- Organization Members never own, require, or establish their own
  Subscription; they act under the Organization's Entitlements.
- Individual Veterinarians do not own the Organization SaaS Subscription.
- One Organization Subscription may support multiple Organization Members.
- Entitlement remains Organization-specific.
- Entitlement does not replace User authorization.
- User authorization does not replace a required Entitlement.
- `ACTIVE` commercial validity provides normal Phase 1 professional
  Entitlements.
- `PENDING`, `PAST_DUE`, and `EXPIRED` do not provide normal new professional
  Entitlements.
- `CANCELLED` may remain commercially valid until its already-effective paid
  period ends.
- Loss of Entitlement prevents new normal paid activity but must not destroy
  historical information or prevent explicitly supported safe resolution of
  existing obligations.
- Subscription termination or payment failure must not delete medical history.
- Commercial state and historical domain truth are separate concerns.
- Future plans and limits require explicit Requirements and Specifications.

---

# 9. Appointment Domain

## 9.1 Appointment

An **Appointment** represents a planned veterinary interaction for one Pet at
one Clinic.

A Phase 1 Appointment requires:

- one Pet;
- one Clinic;
- one requesting User;
- an Appointment reason or supported request context;
- lifecycle state;
- requested scheduling context;
- the applicable Appointment-derived Care Authorization established through
  the request workflow.

An Appointment may additionally have:

- a current assigned Veterinarian;
- historical Veterinarian Assignments;
- confirmed scheduling context;
- scheduling revision history;
- Clinical Record Entries documenting the care, when the Clinic chooses to
  document it, whether before or after the Appointment is completed
  (ADR-011, `SPEC-MED-010`).

A specific Veterinarian is not required at request time, nor for any later
Appointment lifecycle transition. A current assigned Veterinarian is required
only to record clinical documentation (ADR-011).

Veterinarian Assignment and clinical documentation are optional professional
tooling. The core Appointment lifecycle — request, rescheduling, confirmation,
cancellation, no-show, and completion — must work without either. Where a
Clinic uses them, their own rules remain strict.

Guardians who may currently view or act on an Appointment are determined from
current Guardianship and the applicable Appointment rules rather than being
stored conceptually as an Appointment-owned list of Guardians.

### Domain rules

* Anonymous Visitors cannot create Appointments.
* An Appointment must concern a Pet.
* An Appointment must belong to a Clinic.
* A Veterinarian may be assigned after booking if the Clinic workflow permits it.
* Appointment lifecycle transitions must be explicit.
* Cancellation must not erase the historical Appointment.
* Completed Appointments remain historical events.
* Completion is the Clinic's administrative assertion that the confirmed visit
  occurred. It requires no Veterinarian Assignment or clinical documentation,
  and it does not imply that either exists.
* A request not confirmed before its requested time cannot be confirmed,
  rescheduled, or cancelled, and becomes EXPIRED.
* A Guardian may cancel a confirmed Appointment only before its latest
  confirmed scheduled start. From that start on, the outcome is the Clinic's
  to record: COMPLETED when the visit took place, NO_SHOW when the Pet did not
  attend, or a Clinic cancellation when the Clinic itself called the visit off.
  Until then the Appointment remains CONFIRMED.
* The Clinic may answer a request by proposing an alternative time. The
  proposal does not change the request; a Guardian's acceptance changes the
  requested time but never confirms the Appointment, which still requires
  Clinic confirmation.
* Clinical Record Entries may be recorded only for an Appointment that was
  legitimately confirmed and is `CONFIRMED` or `COMPLETED`, before or after its
  scheduled start and before or after completion. `REQUESTED`, `CANCELLED`,
  `NO_SHOW`, and `EXPIRED` Appointments never receive them.
* Once an Appointment has a Clinical Record Entry it can no longer be
  cancelled, marked `NO_SHOW`, or rescheduled; it can still be completed.
* An Appointment has at most one current Veterinarian Assignment. Only that
  Veterinarian, while still a current eligible Veterinarian of the Clinic, may
  record new Clinical Record Entries for it. Assignment is optional for
  requesting, confirming, and completing, and a `COMPLETED` Appointment may be
  assigned or reassigned to document the care that took place. The Guardian
  never chooses the Veterinarian.
* Reassignment never changes who authored existing clinical records; only an
  Entry's own author may amend it.
* The Appointment lifecycle and clinical documentation are independent:
  completion does not require, imply, or close documentation.

The Phase 1 Appointment lifecycle uses:

```text
REQUESTED
CONFIRMED
CANCELLED
COMPLETED
NO_SHOW
EXPIRED
```

Appointment state transitions are controlled by the applicable Specifications.

CANCELLED, COMPLETED, NO_SHOW, and EXPIRED represent preserved historical
outcomes rather than deletion of the Appointment.

CANCELLED means the Appointment was intentionally ended before normal
fulfillment. A Guardian therefore cannot cancel a confirmed Appointment once its
scheduled start has been reached: doing so could rewrite an outcome that only
the Clinic can know — pre-empting a NO_SHOW, or winning a race against the
completion of a visit that took place. Because completion is an administrative
assertion that may be recorded after the visit, an Appointment that is not yet
COMPLETED after its start does not reopen Guardian cancellation. A Clinic may
still record a cancellation after the start when it called the visit off.

EXPIRED means the Clinic did not confirm a request before its requested time
arrived. It is reached only from REQUESTED, is a system outcome rather than a
Guardian or Clinic decision, and is distinct from cancellation and no-show.

A pending request is a REQUESTED Appointment whose latest requested start is
still in the future. At most one pending request may exist for the same Pet at
the same Clinic; confirmed and historical Appointments do not count.

Appointment scheduling history is also distinct from current Appointment state.

A change to requested or confirmed scheduling must preserve the applicable
historical scheduling context rather than silently overwriting it.

A concrete Appointment scheduling context preserves the Clinic timezone under
which that schedule was established.

---

# 10. Medical Domain

## 10.1 Medical Record

A **Medical Record** represents the longitudinal clinical history of a Pet.

It is conceptually centered on the Pet.

It may contain clinical information produced by:

* different Veterinarians;
* different Clinics;
* different Organizations;
* different points in time.

The Medical Record is not conceptually owned by the Clinic currently treating the Pet.

### Domain rules

* A Pet has one continuous logical medical history.
* Multiple veterinary providers may contribute to that history.
* Every contribution must preserve its provenance.
* Access to medical information is authorization-controlled.
* Appointment request and establishment of its required Appointment-derived
  Care Authorization form one coherent domain operation.
* Appointment and Care Authorization remain distinct domain concepts.

---

## 10.2 Clinical Record Entry

A **Clinical Record Entry** represents a specific clinical event or
professional veterinary statement concerning a Pet, recorded for exactly one
Appointment that documents the care (ADR-011).

Phase 1 uses the following controlled primary categories:

- `EXAMINATION`;
- `DIAGNOSIS`;
- `TREATMENT`;
- `PROCEDURE`;
- `VACCINATION`;
- `PRESCRIPTION`;
- `LABORATORY_RESULT`;
- `IMAGING_RESULT`;
- `CLINICAL_NOTE`;
- `OTHER`.

These categories do not imply that each concept is a dedicated first-class
domain entity.

Specialized models may be introduced later where approved behavior requires
lifecycle, validation, or relationships that cannot reasonably be represented
by a Clinical Record Entry.

A Clinical Record Entry must preserve enough context to establish:

- the Pet;
- the Appointment it documents;
- what clinically happened or was recorded;
- the applicable clinical occurrence time, when known;
- when it was recorded;
- the authoring professional and that professional's concrete Clinic
  Assignment;
- the Clinic;
- the originating Veterinary Organization;
- the applicable historical professional and provider context.

The Pet, Clinic, and Veterinary Organization are derived from the Appointment
and its Clinic, which never change, so the provenance is stable without being
copied.

---

## 10.3 Clinical Encounter (retired)

**Clinical Encounter is no longer a domain concept** (ADR-011, `SPEC-MED-010`).
Veterinary care documented through an Appointment is represented by that
Appointment and its Clinical Record Entries: the Appointment answers "what visit
was this", each Entry answers "what was clinically recorded, by whom, and
when". No start, conclusion, care-start, or responsible-Veterinarian fact
exists for a visit.

Clinical care without an Appointment (Clinical Intake) is deferred. Its future
Specification must define its own care context; it must not reintroduce a
Clinical Encounter by analogy.

The text below describes the retired Phase 1 concept and remains only until the
schema transition of ADR-011 is completed.

### Retired description

A **Clinical Encounter** represents the professional care context in which
veterinary care is actually provided to a Pet.

When a Phase 1 Clinical Encounter is established, it must preserve the
historical care context in which veterinary care is provided.

This includes:

- the Pet receiving care;
- the Clinic where care is provided;
- the Veterinary Organization responsible for that care context;
- the responsible Veterinarian;
- the applicable Care Authorization;
- when the Encounter began.

A Clinical Encounter may reference an Appointment when the care originated
from an Appointment.

An Appointment is not required for every Clinical Encounter, and a Clinical
Encounter is not required for any Appointment, including a completed one.

The Encounter's own references to the Appointment and to its Care
Authorization are the authoritative relationship between the Appointment and
its clinical care. Appointment completion does not reference or consume an
Encounter.

An Appointment-backed Encounter may be established while the Appointment is
`CONFIRMED` or after it became `COMPLETED`. Its creation may be later than the
completion, but its care start must not be: the delay is in documentation, not
in care. Establishment still requires a current Veterinarian Clinic Assignment
that already covered the care start, current clinical capability and
Entitlement, and an `ACTIVE` Appointment-derived Care Authorization.

When the Encounter is concluded, it must additionally preserve:

- when the Encounter was concluded;
- the professional who concluded it.

Conclusion information does not exist merely because the Encounter was
created.

A Clinical Encounter may exist without a pre-existing Appointment when an
approved care workflow permits it.

Its Phase 1 lifecycle is:

```text
ACTIVE
   ↓
CONCLUDED
```

Establishing a Clinical Encounter never changes the Appointment lifecycle.

Concluding a Clinical Encounter does not by itself:

- complete the associated Appointment;
- finalize Draft Clinical Record Entries;
- end the applicable Care Authorization;
- prevent otherwise authorized completion of legitimate post-care
  documentation.

Those lifecycles remain separate.

Conclusion is terminal.

### Domain rules

* Clinical Encounter represents actual care, not merely planned scheduling.
* Appointment Veterinarian Assignment does not replace actual clinical
responsibility.
* A concluded Encounter remains historical.
* Conclusion must preserve the professional who concludes it and when.
* Entitlement or Care Authorization lifecycle changes must not destructively
rewrite an Encounter that validly existed.
* Safe-continuity rules may permit minimum completion of already-started care
without authorizing another Encounter.

---

## 10.4 Clinical Provenance

**Clinical Provenance** describes the origin and authorship of medical information.

For example:

```text
2027
Dr. Lopez works for Animalia Veterinary Group
and practices at Animalia Madrid Centro.

Dr. Lopez performs surgery on Luna.

2029
Dr. Lopez leaves Animalia and joins VetCare.
```

The 2027 surgery must continue to identify:

```text
Dr. Lopez
Animalia Madrid Centro
Animalia Veterinary Group
```

where relevant.

It must never be re-attributed to VetCare.

### Invariant

Historical provenance is derived from the event context at the time the event occurred, not from the professional's current relationships.

---

# 11. Clinical Record Lifecycle

Under ADR-011 a Clinical Record Entry has no lifecycle: it is recorded once, as
established clinical history immediately visible to authorized Guardians, and
is immutable from then on. Corrections are Clinical Amendments (§11.3). There
is no Draft and no separate finalization; unsaved text exists only in the
editor of the client writing it. New Entries are recorded only by the
Appointment's current assigned Veterinarian (§9.1). §11.1 and the Draft-related rules of §11.2
describe the retired Phase 1 lifecycle and remain only until the schema
transition is completed.

The retired Phase 1 lifecycle was:

```text
DRAFT
  ↓
FINALIZED
```

A Draft represents clinical information still being prepared.

A Finalized Clinical Record Entry represents established clinical history.

Finalization is one-way.

A Finalized Entry must not return to Draft or be silently destructively
rewritten.

Corrections to Finalized clinical information are represented through
Clinical Amendments rather than modification of the historical original.

---

## 11.1 Draft Clinical Information

Draft information may be mutable while the professional is preparing the record.

Draft Clinical Record Entries are protected clinical work but are not part of
the finalized longitudinal medical history.

---

## 11.2 Finalized Clinical Information

Once finalized, clinically meaningful content must not be silently destructively rewritten.

A finalized record represents a historical professional statement.

### Domain rules

- Finalization must preserve the original creator.
- Material contributors must remain attributable where applicable.
- The finalizing professional must remain identifiable.
- Creation time and finalization time must remain distinguishable.
- Finalized clinical information must retain its original clinical and
  provider provenance.
- A Finalized Clinical Record Entry must not return to `DRAFT`.
- A Finalized Clinical Record Entry must not be silently destructively
  rewritten.
- Corrections that alter historical meaning require a Clinical Amendment.

---

## 11.3 Clinical Amendment

A **Clinical Amendment** represents a correction, clarification, or addition to previously finalized clinical information without destroying the historical original.

Example:

```text
Original:
Medication dose recorded as 20 mg.

Amendment:
Dose corrected to 10 mg.
Reason: transcription error.
```

The system must be capable of establishing:

* the original information;
* the amendment;
* who made the amendment;
* when;
* the meaningful reason for the Amendment.

The exact implementation will be specification-driven.

Every Clinical Amendment requires a meaningful reason.

The Amendment must preserve:

- the original Finalized Clinical Record Entry;
- the amending professional;
- the Amendment time;
- the reason;
- the applicable clinical and provider context;
- the corrective or additional clinical content.

---

# 12. Treatments and Specialized Medical Concepts

## 12.1 Treatment

A **Treatment** may represent ongoing or prescribed veterinary care over a period of time.

Examples:

* antibiotic course;
* post-operative treatment;
* dietary therapy;
* chronic medication.

Treatment should only become a first-class implementation entity if its lifecycle requires behavior that cannot reasonably be represented by a generic Clinical Record Entry.

---

## 12.2 Vaccination

A **Vaccination** is a clinical event that may eventually require specialized information such as:

* vaccine;
* administration date;
* batch;
* next recommended dose.

In Phase 1, Vaccination is represented through the controlled
`VACCINATION` Clinical Record Entry category.

A future dedicated Vaccination domain model requires approved behavior that
justifies additional lifecycle, structure, or relationships.

Its eventual implementation model must be derived from specifications.

---

## 12.3 Clinical Attachment

A **Clinical Attachment** represents protected binary clinical content associated with one Clinical Record Entry.

Examples include:

- laboratory reports;
- diagnostic images;
- discharge reports;
- prescriptions;
- supporting documents.

Clinical Attachment metadata remains part of the relational clinical context.

Binary content is stored separately in protected private object storage.

### Domain rules

- A Clinical Attachment belongs to one Clinical Record Entry.
- Attachment access inherits the medical authorization sensitivity of its clinical context.
- Protected binary content must not be publicly accessible.
- Attachment provenance must identify the clinical context and the User who introduced the Attachment.
- Draft-associated Clinical Attachments may be explicitly removed or replaced through the supported Draft workflow.
- Finalized clinical Attachments must not be destructively rewritten through ordinary workflows.

---

# 13. Medical Access Domain

## 13.1 Medical Record Access

**Medical Record Access** represents authorization to access protected medical information concerning a Pet.

The following concepts must remain distinct:

```text
Veterinary qualification
```

```text
Professional relationship with an Organization
```

```text
Assignment to a Clinic
```

```text
Authorization to access a specific Pet's medical information
```

None automatically implies all the others.

---

## 13.2 Care Authorization

A **Care Authorization** represents an explicit Pet- and Clinic-specific
authorization basis for professional medical access within a defined care
context.

It is distinct from:

- Appointment;
- clinical documentation of the Appointment;
- Guardianship;
- Veterinarian qualification;
- Organization Membership;
- professional Entitlement.

A Care Authorization may be established through an Appointment workflow or
through another approved care workflow.

Its Phase 1 lifecycle is:

```text
ACTIVE
├──→ REVOKED
└──→ ENDED
```

REVOKED represents explicit withdrawal of the authorization.

ENDED represents normal conclusion of the authorization context, such as an
Appointment that was completed, cancelled, marked no-show, or expired without
confirmation.

Under ADR-011 the Appointment-derived Care Authorization governs only
**prior-history access**: access, through the Appointment, to the Pet's
longitudinal medical history. It never governs **Appointment documentation
access**: reading and writing the Appointment's own Clinical Record Entries,
Amendments, and Attachments, which depends only on the current Veterinarian
context and `CLINICAL_DOCUMENTATION` capability at the Appointment's Clinic and
on a legitimately confirmed `CONFIRMED` or `COMPLETED` Appointment
(`SPEC-MED-010` BR-11, BR-14).

Both are terminal and historically distinct.

### Domain rules
* Care Authorization concerns one Pet.
* Care Authorization concerns one target Clinic and applicable Organization
context.
* The granting Guardian remains historically identifiable.
* Appointment existence does not substitute for explicit Care Authorization.
* Revoked or ended authorization must not provide normal current access.
* Pre-care access through an unconfirmed Appointment request ends at the
requested start, even before the Appointment is recorded as expired.
* Appointment completion ends the Appointment-derived Care Authorization
(`ENDED`, `APPOINTMENT_COMPLETED`); a revoked one stays `REVOKED`.
* Revocation or ending stops prior-history access immediately, with no
continuity exception, and never stops documentation of the Appointment's own
care.
* Appointment documentation access never grants prior-history access.
* Revocation and normal ending must preserve historical evidence that the
authorization previously existed.
* Reauthorization creates a new authorization rather than reactivating a
terminal one.

---

## 13.3 Access Principles

### Explicit business basis

Medical access must have an explicit domain justification.

---

### Least privilege

Only the information required for the permitted professional operation must be accessible.

---

### Professional context

Professional access must be attributable to a professional and normally to an Organization / Clinic context.

---

### Revocability

Where access derives from Guardian authorization, revocation must be representable.

---

### Auditability

Protected medical-access operations classified as audit-required must produce
durable Medical Access Audit evidence through trusted infrastructure.

Phase 1 audit-required operation categories include:

- `VIEW_PET_MEDICAL_HISTORY`;
- `VIEW_CLINICAL_RECORD_ENTRY`;
- `VIEW_CLINICAL_ATTACHMENT`;
- `ACCESS_FOR_APPOINTMENT_OPERATIONS`;
- `ACCESS_FOR_CLINICAL_CARE`;
- `ACCESS_FOR_POST_CARE_DOCUMENTATION`.

An audit-required operation may have:

- `PERMITTED`;
- `DENIED`.

For an audit-required permitted read, the required Audit Event must be durably
captured before protected medical information is released.

If required durable audit capture fails, the protected operation fails closed.

Medical Access Audit represents meaningful domain-level access rather than
every low-level database or infrastructure operation.

External observability and log delivery remain separate from authoritative
Medical Access Audit persistence.

---

### No global veterinarian access

A Veterinarian cannot search the entire platform's Pet population and access arbitrary medical histories merely because they are professionally registered.

---

# 14. Public Discovery Domain

## 14.1 Clinic Discovery

**Clinic Discovery** allows Visitors and Users to find Clinics represented by the platform.

Discovery may use:

- current geographic position;
- geographic area;
- distance;
- other public characteristics explicitly supported by the applicable Discovery Specifications.

Service, specialty, and richer filtering capabilities require their
applicable approved delivery scope.

### Domain rules

* Authentication is not required for public discovery.
* Geographic discovery operates on Clinics, not Organizations.
* Public discovery must not expose private customer, operational, or medical information.

---

## 14.2 Clinic Public Profile

A **Clinic Public Profile** represents information intentionally exposed to the public.

Phase 1 public profile information includes the public Clinic identity required
by the publication workflow.

Public display name is required for publication.

Description and supported public contact information may be optional.

Location, services, and public opening hours are governed by their applicable
Clinic Specifications.

Public Clinic media and public Veterinarian presentation are separate or later
capabilities.

Public visibility rules must be explicitly defined.

---

# 15. Authorization Questions

Authorization should answer contextual questions such as:

```text
Is this User a Guardian of this Pet?

What kind of Guardianship relationship exists?

Is this User currently a member of this Organization?

What responsibilities does this membership grant?

Is this Veterinarian currently assigned to this Clinic?

Was this Veterinarian assigned to this Clinic
when the medical event occurred?

Does this professional context authorize access
to this Pet's medical information?

Has the relevant Guardian authorization been revoked?

Does the Organization subscription permit this operation?

Which professional contexts does this User currently hold?
(derived from current relationships and Entitlements; never stored)
```

These questions may ultimately be enforced through:

* domain services;
* application policies;
* PostgreSQL Row Level Security;
* server-side validation;
* automated tests.

---

# 16. Temporal Rules

Time is a first-class domain concern.

## 16.1 Organization Membership

Organization Membership has an effective start and optional end.

Ended Memberships remain historical and do not grant current capability.

## 16.2 Organization Responsibility Grant

Organization Responsibility Grants are temporal.

Ending a grant removes its current capability contribution without rewriting
the previous responsibility period.

## 16.3 Veterinarian Clinic Assignment

Veterinarian Clinic Assignment is temporal.

Historical Assignment remains identifiable after the professional stops
practicing at the Clinic.

## 16.4 Guardianship

Guardianship is temporal-capable.

Current Guardian capability depends on the current active relationship.

Historical periods remain preserved.

## 16.5 Appointments

Appointment lifecycle and scheduling history must remain distinguishable.

Schedule revisions preserve the applicable interval, actor, and Clinic timezone
context under which they were established.

Standard Appointment Duration is the Clinic policy used whenever a new
scheduled interval is constructed. Every operation that constructs a new
scheduled interval from an actor-selected start — a Guardian request, a
Guardian requested reschedule, a Clinic Alternative Time proposal, or a
Guardian or Clinic confirmed-reschedule proposal — uses the Clinic Standard
Appointment Duration current at that operation, and cannot construct one
without it. The resulting interval is frozen in the Schedule Revision or
Reschedule Proposal. Operations that adopt an existing interval — confirmation
and Proposal acceptance — use it exactly and do not read Standard Appointment
Duration. Configuration changes never rewrite existing Schedule Revisions or
pending Proposals. A Schedule Revision stores an interval; an Appointment has
no duration of its own (`SPEC-APT-013` BR-68).

A Reschedule Proposal is a frozen interval proposed to supersede one specific
current Schedule Revision of its Appointment, subject to the counterparty's
acceptance. Accepting it establishes the next Schedule Revision, in the same
scheduling context as the revision it supersedes; the Proposal's acceptance
facts are those of that revision. A Proposal is `PENDING` until it is
`ACCEPTED`, `WITHDRAWN`, or `VOID` (a system-observed permanent invalidation,
such as its base revision being superseded); all three outcomes are final. An
Appointment has at most one open (`PENDING`) Proposal.

Four properties of a Proposal are kept distinct:

- its **state** is persistent and changes only through acceptance, withdrawal,
  or permanent invalidation;
- it is **actionable** while it is `PENDING`, its base and proposed starts are
  still in the future, and its proposer has kept their authority;
- its **current scheduling feasibility** — whether its frozen interval satisfies
  the Clinic's current scheduling timezone, Availability, and assigned
  Veterinarian constraints — is derived when read;
- its **Guardian current acceptability** — scheduling feasibility plus, for a
  confirmed reschedule, the Organization's current Entitlement — is derived
  when read and generic.

Feasibility and acceptability can change in either direction and never change
the state or actionability. Acceptance revalidates everything.

The base context determines the workflow:

- **Confirmed reschedule** — a `CONFIRMED` base, proposed by a Guardian or the
  Clinic (`SPEC-APT-005`) and accepted by the counterparty (`SPEC-APT-006`);
  the Appointment stays `CONFIRMED`.
- **Alternative Time** — a `REQUESTED` base, proposed only by the Clinic
  (`SPEC-APT-018`) and accepted only by a current Guardian (`SPEC-APT-019`);
  acceptance establishes a new `REQUESTED` revision and the Appointment stays
  `REQUESTED` until the Clinic confirms it (`SPEC-APT-002`).

"Alternative Time" names a workflow, not a separate entity. A current
`REQUESTED` revision that was established by accepting a Clinic Proposal is
identified by its source Proposal; that provenance is how "accepted by the
Guardian, awaiting Clinic confirmation" is derived, not a stored flag.

## 16.6 Care Authorization

Care Authorization remains historically identifiable after `REVOKED` or
`ENDED`.

Terminal authorization periods are not reactivated.

## 16.7 Clinical Records and Medical Events

Clinical Record Entries and their Amendments and Attachments preserve the
Appointment, professional, Clinic, Organization, and occurrence context
applicable to the historical event.

## 16.8 Subscription

Subscription state and commercial validity evolve over time.

Current commercial state must not rewrite historical professional or medical
truth.

## 16.9 Medical Access Audit

Medical Access Audit Events represent append-only historical security evidence.

Ordinary lifecycle changes must not destructively rewrite them.

---

# 17. Core Invariants

## INV-001 — One User may have multiple capabilities

A User may simultaneously be a Guardian, Veterinarian, Organization Member, and hold an applicable ADMINISTRATOR Organization Responsibility Grant where the required relationships exist.

---

## INV-002 — Pet identity is provider-independent

A Pet exists independently from any current Clinic or Organization.

---

## INV-003 — Multiple Guardians are supported

The domain must not assume exactly one Guardian per Pet.

---

## INV-004 — Veterinarian identity is Organization-independent

A Veterinarian remains professionally identifiable after leaving an Organization.

---

## INV-005 — Organization and Clinic are different concepts

An Organization may operate multiple Clinics.

---

## INV-006 — Organization Membership is temporal

The system must preserve when membership starts and ends.

---

## INV-007 — Veterinarian Clinic Assignment is temporal

The system must preserve current and historical Veterinarian Clinic Assignment
periods.

An ended Assignment must not provide current professional eligibility.

---

## INV-008 — A Veterinarian may practice at multiple Clinics

The domain must not assume a one-to-one relationship between Veterinarian and Clinic.

---

## INV-009 — Historical clinical provenance is immutable

Current professional relationships must never rewrite the original provenance of a clinical event.

---

## INV-010 — Medical history follows the Pet

The logical medical history of a Pet may contain information from multiple Clinics and Organizations.

---

## INV-011 — Professional qualification does not imply medical access

Veterinarian status alone grants no universal access to Pet medical information.

---

## INV-012 — Subscription belongs to the Organization

The professional SaaS subscription is associated with the Veterinary Organization.

---

## INV-013 — Subscription termination does not erase history

Billing state changes must not delete previously recorded medical information.

---

## INV-014 — Anonymous public discovery is allowed

Authentication is not required to discover public Clinics.

---

## INV-015 — Private operations require an authenticated identity

Protected Pet, Appointment, and Medical operations require authenticated context.

---

## INV-016 — Finalized clinical information requires traceable correction

Clinically meaningful finalized information must not be silently destructively altered when a correction would change historical meaning.

---

## INV-017 — An Organization must retain an active Owner

A Veterinary Organization must have at least one active Owner.

An operation that would leave the Organization without an active Owner must
not succeed unless ownership is validly transferred or another Owner is
established through an explicit ownership workflow.

---

## INV-018 — Organization establishment is a trusted commercial operation

A Veterinary Organization is established only through trusted Commercial
Onboarding, together with its initial Owner Membership and its initial
Subscription.

Authentication, verification, professional identity, Guardianship, or
responsibility in another Organization never establishes an Organization.

---

## INV-019 — Professional context is derived, not stored

No persisted User attribute determines professional capability.

Professional context is derived from current Memberships, Responsibility
Grants, Professional Profile, Clinic Assignments, and Organization
Entitlements.

---

# 18. Conceptual Relationships

The conceptual domain can be visualized as:

                         User
                          │
          ┌───────────────┼────────────────────┐
          │               │                    │
          ▼               ▼                    ▼
    Guardianship    Veterinarian         Organization
          │        Professional Profile   Membership
          │                                    │
          ▼                                    ▼
         Pet                         Responsibility Grant
          │                                    │
          │                                    ▼
          │                          Veterinary Organization
          │                                    │
          │                         ┌───────────┴───────────┐
          │                         ▼                       ▼
          │                       Clinic             Organization
          │                         │                 Subscription
          │                         │
          │                         ▼
          │              Veterinarian Clinic Assignment
          │                         │
          │                         ▼
          └────────── Appointment ─ Veterinarian
                          │
               ┌──────────┴──────────┐
               ▼                     ▼
       Care Authorization   Clinical Record Entry
     (prior-history access)          │
                           ┌─────────┴─────────┐
                           ▼                   ▼
                   Clinical Amendment   Clinical Attachment

Medical Access Audit Events reference meaningful protected medical-access
operations and preserve the applicable User, Pet, authorization, provider,
professional, and protected-resource context.

Historical provenance is preserved through the original clinical context
rather than reconstructed from current Organization Membership,
Responsibility Grants, Clinic Assignments, or Guardianship.

This diagram is conceptual.

It does not define:

- database tables;
- exact foreign keys;
- implementation ownership boundaries;
- exact cardinalities;
- transaction mechanisms;
- infrastructure services.

---

# 19. Domain Areas

The current domain is separated into the following conceptual areas.

### Identity

- User;
- Authentication Identity;
- User Profile.

### Pets

- Pet;
- Guardianship;
- Guardianship Invitation.

### Veterinary Professionals

- Veterinarian;
- Veterinarian Professional Profile;
- professional credential information;
- future professional verification.

Professional verification is defined for future delivery and is not part of
the Phase 1 implementation scope.

### Organizations

- Veterinary Organization;
- Organization Invitation;
- Organization Membership;
- Organization Responsibility Grant;
- Organization ownership;
- Commercial Onboarding.

Organization capability is derived from Membership, Responsibility Grant,
scope, and operation context rather than from a global User role.

A Veterinary Organization is established only through trusted Commercial
Onboarding, together with its initial Owner Membership and initial
Subscription.

### Clinics

- Clinic;
- Clinic Location;
- Clinic Public Profile;
- Clinic publication;
- Clinic Service Offering;
- Clinic Opening Hours;
- Clinic scheduling timezone;
- Veterinarian Clinic Assignment.

### Appointments and Scheduling

- Appointment;
- Appointment lifecycle;
- Appointment Schedule Revision;
- Reschedule Proposal;
- Clinic Appointment Availability;
- Veterinarian Availability;
- Appointment Veterinarian Assignment.

Scheduling history remains distinct from current Appointment state.

### Clinical Care

- Clinical Record Entry (belongs to one Appointment);
- Clinical Amendment;
- Clinical Attachment;
- Clinical Provenance.

The logical Medical Record is the Pet-centered longitudinal projection of
finalized clinical information.

Treatments, Vaccinations, Prescriptions, Laboratory Results, Imaging Results,
and similar concepts remain represented through controlled Clinical Record
Entry categories unless future approved behavior requires dedicated domain
models.

### Medical Access Control

- Medical Record Access;
- Care Authorization;
- least-privilege medical access;
- revocation and normal authorization ending;
- prior-history access versus Appointment documentation access;
- Medical Access Audit Event.

Professional qualification, Organization relationship, Clinic Assignment,
Care Authorization, and commercial Entitlement remain separate authorization
dimensions.

### Subscriptions and Entitlements

- Organization Subscription;
- Subscription state and history;
- professional Entitlement evaluation;
- safe resolution after Entitlement loss.

Entitlement is derived from current trusted commercial state and requested
capability.

It is not a permanent User or Organization role.

### Public Discovery

- Clinic Discovery;
- Clinic Public Profile;
- geographic discovery.

Public Discovery operates on intentionally public Clinic information and must
remain separate from protected operational and medical information.

### Communications

- Transactional Communication;
- email delivery;
- Push Registration;
- push delivery;
- Appointment notifications;
- reminder behavior.

User-managed communication preferences remain a later capability.

These boundaries are conceptual.

They may evolve through approved Requirements and Specifications without
collapsing distinct domain concepts into infrastructure-specific models.

---

# 20. Deferred and Open Domain Questions

The following questions remain intentionally unresolved or deferred.

They must not be answered through implementation assumptions.

Where a capability is explicitly delivered `Later`, approved future
Specifications may already constrain the answer without making that capability
part of Phase 1.

---

## Identity

- Will a User be able to authenticate using multiple authentication
  identifiers simultaneously?
- Should personal and professional contact information be managed separately?
- What controlled account-merging or identity-recovery process applies if
  duplicate domain Users are created for the same person?
- How should account deletion or anonymization interact with historical
  clinical authorship, provenance, and audit evidence?

---

## Guardianship

Phase 1 uses an undifferentiated Guardian capability.

Future product behavior may still need to determine:

- whether differentiated Guardian relationship types are required;
- whether different Guardians may hold different permission levels;
- what explicit workflow may end a Guardianship;
- whether one Guardian may remove another Guardian;
- what constraints apply when the last active Guardian would be removed;
- whether and how Guardianship may be transferred.

Historical Guardianship preservation and temporal-capable persistence are no
longer open questions.

---

## Veterinary Verification

Professional verification is delivered `Later`.

Its approved Specifications define the future request and resolution workflow,
but future delivery may still need to determine:

- which authoritative professional sources are used in each jurisdiction;
- which evidence is required for a particular credential type;
- how credential expiry is represented;
- when re-verification is required;
- how materially changed professional credential information is re-evaluated.

Organization Membership, Clinic Assignment, and Appointment Assignment must
not be treated as professional verification.

---

## Organizations

Future Organization lifecycle behavior may need to determine:

- how Organization ownership is transferred;
- how additional Owners may be established outside initial Organization
  creation;
- whether an Organization may be archived;
- what archival means for current operational capability;
- whether Organizations may merge;
- how historical identity and provenance are preserved if a merge capability
  is ever introduced.

---

## Clinics

Future Clinic behavior may need to determine:

- whether a Clinic requires an explicit operationally inactive state distinct
  from public publication state;
- whether historical Clinic address changes eventually require dedicated
  location history;
- whether future Clinic lifecycle behavior includes archival or permanent
  closure.

Current Clinic identity, Organization ownership, geographic location,
publication, and Veterinarian Clinic Assignment behavior are defined
separately through approved Specifications.

---

## Organization Responsibilities

Phase 1 supports multiple temporal Responsibility Grants with Organization or
Clinic scope.

Future behavior may still need to determine:

- whether responsibility changes may be scheduled for a future effective time;
- whether additional controlled responsibility types are required;
- whether future capabilities require more granular scope than Organization or
  Clinic.

Arbitrary per-member custom permissions are not part of Phase 1.

---

## Appointments

Phase 1 does not require the Guardian to select a specific Veterinarian.

The Clinic may assign an eligible Veterinarian later according to the approved
Appointment Assignment workflow.

Remaining future questions include:

- whether one Appointment may require several simultaneously responsible
  professionals;
- whether specialized Appointment types require different scheduling or
  duration rules;
- whether rooms, equipment, or other constrained resources become part of
  scheduling;
- whether travel-time constraints between Clinics become relevant;
- what explicit correction workflow applies when a terminal Appointment
  outcome such as `COMPLETED` or `NO_SHOW` was recorded incorrectly;
- whether future reschedule proposals require additional lifecycle states such
  as rejection, Guardian withdrawal, counterproposal, or expiration. Clinic
  withdrawal of a Clinic-originated proposal (`WITHDRAWN`) is approved by
  `SPEC-APT-016` for both base contexts, and system-observed permanent
  invalidation (`VOID`) by `SPEC-APT-005`; a proposal whose time has lapsed is
  not a separate state;
- whether Guardian acceptance of a Clinic alternative time should ever confirm
  the Appointment directly, or notify the Clinic. Phase 1 does neither
  (`SPEC-APT-019`).

---

## Medical Records

Phase 1 defines Clinical Record Entries recorded directly for an Appointment,
Clinical Amendments, and Clinical Attachments (ADR-011). Drafts and Clinical
Encounters are retired.

Remaining questions include:

- how legal deletion, anonymization, or retention obligations interact with
  immutable clinical history;
- which medical concepts eventually require dedicated domain models rather
  than controlled Clinical Record Entry categories;
- whether Amendment-to-Amendment relationships require an explicit chain model
  beyond the current traceability requirements;
- what explicit corrective workflow applies to protected Clinical Attachments
  associated with finalized clinical information;
- whether future structured clinical information requires additional
  domain-specific validation or lifecycle behavior.

---

## Medical Access and Audit

Phase 1 uses explicit Care Authorization and an explicit catalog of
audit-required protected medical-access operations.

Remaining future questions include:

- whether an emergency or break-glass medical-access workflow is required;
- what exceptional authorization rules such emergency access would require;
- what legal retention periods apply to Medical Access Audit Events;
- whether an explicit append-only audit-correction workflow is required;
- how future jurisdictions affect medical-access, retention, and
  user-rights obligations.

Emergency access must not be invented until explicitly specified.

---

## Subscription and Commercial Model

Phase 1 defines normal professional Entitlements and the treatment of
`PAST_DUE`.

Future commercial behavior may still need to determine:

- whether several Subscription plans are introduced;
- whether future plans differ by Clinic count, Organization Member count,
  usage, or other limits;
- whether future commercial grace-period behavior is introduced;
- whether any currently unpaid capability becomes commercially gated;
- whether any paid Phase 1 capability becomes available under a future free
  professional offering.

Commercial packaging must not redefine established domain concepts.

---

## Public Discovery

Future public-discovery behavior may need to determine:

- whether individual Veterinarians are shown publicly;
- whether Users may filter Clinics by Veterinarian specialty;
- whether richer service or capability filters are introduced;
- how public Clinic media is represented when `REQ-FIL-002` is delivered;
- whether future Clinic archival or inactivity states affect Discovery.

Public Discovery must remain separate from protected operational and medical
information.

---

## Domain Evolution

An item in this section is not permission to implement speculative behavior.

When one of these questions becomes relevant, it should be resolved through
the appropriate combination of:

- Requirement;
- Specification;
- Domain invariant;
- Architectural Decision Record where a meaningful technical choice exists.

Resolved questions should be removed from this section and incorporated into
the applicable authoritative domain section.

---

# 21. Domain Evolution Rule

The domain should evolve from demonstrated product needs.

The preferred progression is:

```text
Product need
    ↓
Requirement
    ↓
Specification
    ↓
Domain rule
    ↓
Architectural decision if required
    ↓
Implementation model
```

Future evolution should be considered when defining boundaries.

Future behavior must not be implemented until it is justified.

The goal is not minimal architecture.

The goal is **appropriate architecture with controlled evolution**.

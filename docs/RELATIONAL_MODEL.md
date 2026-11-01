# Phase 1 Relational Model

**Status:** APPROVED

## 1. Purpose, Authority, Scope, and Precedence

This document is the canonical detailed relational-design baseline for Phase 1.
It records the model approved through human review before physical database and
migration design begins.

This is an approved design, not a proposal. Physical PostgreSQL structures,
constraints, indexes, functions, Row Level Security policies, migrations, and
trusted-operation mechanisms must preserve the boundaries recorded here.

This document does not:

- introduce product behavior beyond approved Requirements and Specifications;
- replace the ubiquitous language or domain invariants in [DOMAIN.md](DOMAIN.md);
- select unresolved physical schema mechanisms;
- contain SQL or migrations;
- authorize Later workflows merely because the model is extensible.

The source precedence in [CONVENTIONS.md](CONVENTIONS.md) continues to apply. If
this document appears to conflict with a higher-precedence approved source, the
conflict must be reported and resolved rather than silently implemented.

Applicable accepted architectural decisions include:

- [ADR-001 — Store Clinical Attachments in Private Object Storage](decisions/ADR-001-clinical-attachment-storage.md);
- [ADR-002 — Use Domain-Level Medical Access Auditing](decisions/ADR-002-domain-level-medical-access-auditing.md);
- [ADR-003 — Model Guardianship as a Temporal-Capable Relationship](decisions/ADR-003-temporal-guardianship-foundation.md);
- [ADR-004 — Fail Closed When Required Medical Audit Cannot Be Durably Captured](decisions/ADR-004-fail-closed-required-medical-auditing.md);
- [ADR-005 — Use Context-Dependent Medical Audit Correlation](decisions/ADR-005-context-dependent-medical-audit-correlation.md).
- [ADR-006 - Derive Current Subscription State from Initial Facts and Append-Only Transitions](decisions/ADR-006-derived-provider-independent-subscription-state.md)
- [ADR-007 — Structured Protected-Read Outcomes for Durable Denial Auditing](decisions/ADR-007-structured-protected-read-outcomes.md).


Classification used below:

- **M** — authoritative mutable/current state;
- **C** — current configuration;
- **T** — temporal relationship;
- **I** — immutable historical fact;
- **A** — append-only history;
- **O** — operational persistence.

## 2. Relational Structure Inventory

### 2.1 Identity and professional identity

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `users` | M | Stable provider-independent User identity and creation time. It contains no global role, password, or permanent capability. |
| `user_authentication_identities` | O | Maps a trusted authentication issuer/provider and opaque subject to a User. Authentication credentials, sessions, and recovery data remain provider-owned. |
| `user_profiles` | M | Optional current non-professional User presentation data. It carries no authentication, Guardianship, professional, Entitlement, or medical-access authority. |
| `veterinarian_professional_profiles` | M | Stable professional identity belonging to exactly one User. Profile existence alone grants no verification, Organization capability, Clinic Assignment, public visibility, Entitlement, or medical access. |
| `veterinarian_professional_credentials` | M | Separate Phase 1 registration/license structure with its own identity, identifier, and issuing jurisdiction/authority/context. Every Phase 1 Professional Profile has exactly one Credential. |

Registration/license fields are not embedded in the Professional Profile.
Credential-verification requests, evidence, review, and outcomes are not Phase 1
structures.

### 2.2 Veterinary Organizations and responsibilities

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `veterinary_organizations` | M | Stable business and commercial customer identity with only approved descriptive information. Also carries the immutable, non-public establishment record of trusted Commercial Onboarding (ADR-009, `SPEC-ORG-001` §10): `establishment_idempotency_key` (unique when present; also the initial Subscription's establishment key) and `establishment_request_digest` (SHA-256 of the canonical requested inputs, for exact replay). Both are absent together for Organizations established before that operation existed. |
| `organization_invitations` | O | Finite invitation to establish Membership, preserving Organization, inviter, recipient/contact context, creation/expiration, and applicable lifecycle facts. |
| `organization_invitation_responsibilities` | I/O | Responsibility identifiers and scopes authorized by an Invitation. The standard invitation workflow cannot grant `OWNER`. |
| `organization_memberships` | T | User-to-Organization relationship period with effective start, optional end, and originating Invitation where applicable. |
| `organization_responsibility_grants` | T | Responsibility and scope period belonging to one Membership. Current capability derives from active Membership plus applicable active Grant and scope. |

Organization ownership is represented by an active Membership with an active
Organization-scoped `OWNER` grant. There is no separate Organization Ownership
table.

### 2.3 Clinics, configuration, and professional context

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `clinics` | M/C | Stable physical Clinic identity, exactly one Veterinary Organization, creation time, current publication state, and authoritative current named scheduling timezone when required by scheduling configuration; also carries the weekly Appointment Availability revision (see `clinic_appointment_availability_periods`) and the immutable, non-public creation key of the client-safe creation operation (`SPEC-CLI-001` §10), unique per Organization when present. |
| `clinic_locations` | C | Optional current human-readable and geographic Location suitable for server-side spatial querying. |
| `clinic_public_profiles` | C | Optional current approved public Clinic information. Public display name is not assumed unique. |
| `clinic_service_offerings` | C | Zero or more current controlled Service Offerings. Equivalent current category is unique within one Clinic where required; `OTHER` requires meaningful description. |
| `clinic_opening_periods` | C | Zero or more recurring local Opening Periods. The applicable timezone derives from Clinic. |
| `clinic_opening_exceptions` | C | Zero or more specific-date closures or exceptional periods. The applicable timezone derives from Clinic. |
| `veterinarian_clinic_assignments` | T | Professional Profile-to-Clinic relationship period referencing the supporting Organization Membership period. |

Clinic creation requires no placeholder Location, Public Profile, Service
Offering, Opening Period, Opening Exception, or availability row. Publication
state belongs to Clinic and is not Clinic lifecycle.

### 2.4 Pets and Guardianship

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `pets` | M | Stable provider-independent Pet identity and current non-clinical profile. It contains no embedded Guardian, owner User, Clinic, or Organization identity. |
| `guardianships` | T | Explicit User-to-Pet relationship period from which current Guardian capability derives. |
| `guardianship_invitations` | O/I | Invitation to establish Guardianship, preserving Pet, authoritative inviting Guardianship, intended recipient/contact, optional existing recipient User, creation/expiration, and lifecycle facts. |

The inviting User derives through `inviting_guardianship_id`. Later loss or
ending of the inviting Guardian's Guardianship does not by itself invalidate an
otherwise valid pending Invitation.

### 2.5 Scheduling and Appointments

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `clinic_appointment_availability_periods` | C | Zero or more recurring Clinic-level bookable periods. Local values derive timezone from Clinic. The set is replaced as a whole and identified by the Clinic's `weekly_appointment_availability_revision` (non-negative `bigint`, default 0, incremented once per actual change of the set; an optimistic-concurrency token for whole-week replacement, not history; SPEC-APT-013 BR-75). Exceptions, standard duration, and timezone do not change it. |
| `clinic_appointment_availability_exceptions` | C | Zero or more date-specific Clinic availability overrides. |
| `veterinarian_availability_periods` | C | Zero or more recurring professional availability periods tied to a concrete Veterinarian Clinic Assignment. |
| `veterinarian_availability_exceptions` | C | Zero or more date-specific professional availability overrides tied to a concrete Clinic Assignment. |
| `appointments` | M/I | Planned-visit identity, Pet, Clinic, original requesting User, reason/notes, creation time, and explicit current lifecycle state. Appointment Organization derives through Clinic. |
| `appointment_lifecycle_events` | A/I | Successful lifecycle transitions after creation, preserving from/to state, actor/context, effective time, and reason where applicable. A system-performed transition (`REQUESTED → EXPIRED`) has a system actor context and no User actor. `clinical_encounter_id` is legacy provenance retained only on historical `COMPLETED` Events established while completion required Encounter evidence; new Events carry none, and it is not the source of truth for the Appointment–Encounter relationship (`clinical_encounters.appointment_id` and `care_authorization_id` are). |
| `appointment_schedule_revisions` | A/I | Immutable `REQUESTED` or `CONFIRMED` scheduling contexts with resolved actual interval, establishment-time Clinic timezone snapshot, actor/context, and source Proposal where applicable. |
| `appointment_reschedule_proposals` | O/I | A frozen interval proposed to supersede one specific current Schedule Revision of its Appointment, preserving the base revision and its context, the proposed resolved interval (start-only request; end = resolved start + the Clinic standard Appointment duration current at creation, for either base, frozen thereafter; no duration column), timezone snapshot, proposer and proposing context, reason, creation time, state, and — when withdrawn — the withdrawing User and time, or — when void — the observation time and reason. Acceptance facts are not stored on the Proposal: they are those of the resulting Schedule Revision. The entity is state-neutral. Approved workflows: a `CONFIRMED` base (SPEC-APT-005/006, Guardian or Clinic proposing) and a `REQUESTED` base — the Alternative Time workflow — Clinic proposing only, Guardian accepting only (SPEC-APT-018/019); withdrawal for either base (SPEC-APT-016). No second Proposal table exists for the `REQUESTED` workflow. Current scheduling feasibility and Guardian current acceptability are derived by the Clinic and Guardian reads (SPEC-APT-005 BR-34, BR-35); no column stores them. |
| `appointment_veterinarian_assignments` | T/I | Planned professional Assignment history. Every row references the concrete Veterinarian Clinic Assignment period supporting eligibility. |

Appointment request authority derives from the current applicable Guardianship
plus the other approved request-authorization rules. The resulting Care
Authorization does not authorize its own creation.

### 2.6 Care Authorization and medical-access auditing

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `care_authorizations` | T/I | Stable Pet-, Clinic-, Organization-, purpose-, and care-context-specific authorization basis. It preserves the authoritative granting Guardianship, granted time, lifecycle state, and optional Appointment. |
| `medical_access_audit_events` | A/I | Append-only security evidence for audit-required protected operations, distinguishing applicable acting User or authorized process, Pet, operation, outcome, time, protected-resource scope, and historical authority/provider context. |

Care Authorization is an authorization basis, not a persisted access decision.
No Medical Access Decision structure exists.

Medical Access Audit correlation/session context is optional or
context-dependent under ADR-005. The model supports trusted correlation where
applicable but requires no universal correlation column, identifier format,
uniqueness rule, one-event-per-correlation rule, or Audit Session entity.

### 2.7 Clinical care

> **Revised (ADR-011, `ACCEPTED`).** The clinical-care structures in
> this section, the Encounter rows of §3.3, §4, §5.6, §6, §7, and §9, and the
> legacy Encounter reference of `appointment_lifecycle_events` are replaced by
> the target model of [§14](#14-target-revision-appointment-owned-clinical-documentation-adr-011)
> as the transition stages are applied. Until then they describe the deployed
> schema.

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `clinical_encounters` | M/I | Actual care context preserving Pet, Clinic, Veterinary Organization provenance, responsible Veterinarian's concrete Clinic Assignment, creating User, occurrence/start time, creation time, applicable Care Authorization, optional Appointment, and lifecycle state. |
| `clinical_record_entries` | M while Draft; I when Finalized | Clinical statement belonging to exactly one Encounter, preserving original creator, lifecycle state, content/category/event-time semantics, and finalization provenance. Also carries the immutable creation record of the Appointment-keyed client operation (`SPEC-MED-002` BR-34): `creation_idempotency_key` (unique per creating User when present) and `creation_request_digest` (SHA-256 of the canonical requested creation facts — Encounter, category, normalized content, normalized `OTHER` context, event time — for exact replay after later Draft edits). Both are absent together for Entries created through any other path. |
| `clinical_record_entry_contributors` | Durable attribution; frozen on finalization | Sufficient attribution for professionals who materially contributed to an Entry, preferably through concrete Veterinarian Clinic Assignment context. |
| `clinical_amendments` | A/I | Append-only correction, clarification, or addition referencing the original Finalized Entry and preserving reason, content, amender, time, and its own professional/provider provenance. |
| `clinical_attachments` | O/M while Draft; I when finalized and available | Stable Attachment identity, parent Entry, uploader provenance, creation time, media/file type, size, opaque binary reference, validation semantics, and sufficient integrity information. |

Encounter conclusion additionally preserves effective conclusion time and the
concluding professional's concrete historical context. It does not replace the
responsible Veterinarian provenance.

### 2.8 Subscriptions and Entitlements

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `organization_subscriptions` | M/T | Provider-independent Organization commercial relationship preserving Subscription identity, exactly one Veterinary Organization, establishment time, and required trusted commercial context. |
| `subscription_provider_references` | O | Operational mappings to opaque provider/customer/subscription references and synchronization context. Exact provider uniqueness is not fixed. |
| `subscription_state_transitions` | A/I | Zero or more append-only Subscription State Transition rows preserving sufficient effective timing and commercial context. |

Under [ADR-006](decisions/ADR-006-derived-provider-independent-subscription-state.md),
current Subscription state is derived from immutable initial state facts and
the latest accepted append-only State Transition. No mutable current-state
projection is stored.

Subscription establishment must coherently establish its initial trusted state,
but it need not create an initial State Transition row. Overall commercial
history and validity gaps remain reconstructable.

Phase 1 accepts only the `SPEC-SUB-002` §5 transition graph, never a
future-dated transition, and nothing out of `EXPIRED`; restarting service after
`EXPIRED` is a new Subscription row (period). The trusted operation and the
transition insert trigger enforce this. A Subscription row is established only
as `PENDING` or `ACTIVE`, with an initial effective time not later than the
establishment instant (enforced by the trusted establishment operation). An open-ended `ACTIVE` (no
`commercial_valid_until`) is the Phase 1 manual commercial model; no column is
added and nothing materializes an end.

Professional Entitlement is derived at operation time. There is no authoritative
Entitlement table, assignment, decision row, or paid-access boolean.

### 2.9 Communications

| Structure | Class | Approved responsibility |
| --- | --- | --- |
| `transactional_communications` | O/I | Durable logical Communication intent linked to an authoritative originating context and one intended recipient context, which may or may not be a User. |
| `communication_delivery_jobs` | O | Non-authoritative mutable dispatch projection for one channel/destination, including claim lease, bounded retry, and current provider-feedback state. It is not Communication or domain truth. |
| `communication_delivery_attempts` | A/O | Channel- and destination-specific delivery history while retained. |
| `push_registrations` | O | Technical User push destinations and current eligibility/invalidation context. |

Communication never owns or recreates originating domain state. Complete
message content, sensitive tokens, fixed retry sequence fields, fixed failure
taxonomy, and duplicated authoritative delivery summaries are not mandatory.

### 2.10 Public Discovery

Phase 1 introduces no authoritative Discovery table. Basic, nearby, and map
Discovery are queries or projections over:

- Clinic;
- current Clinic publication state;
- Clinic Location when the operation is geographic;
- Clinic Public Profile and other approved public information.

Discovery Results, map markers, distances, Visitor reference locations,
searches, viewports, and ranking results are not independent copies of Clinic
state.

## 3. Relationship and Cardinality Matrix

### 3.1 Identity, Organizations, Clinics, and Pets

| Relationship | Cardinality | Notes |
| --- | --- | --- |
| User → Authentication Identity Link | `1:1` in Phase 1 | Required after successful registration; provider subject maps to at most one User. |
| User → User Profile | `1:0..1` | Optional current profile. |
| User → Veterinarian Professional Profile | `1:0..1` | At most one per User. |
| Professional Profile → Professional Credential | `1:1` | Exactly one separate Credential per Phase 1 Profile. |
| Organization → Organization Invitation | `1:0..N` | Invitation does not itself create Membership. |
| Organization Invitation → Intended Responsibility | `1:1..N` | Accepted Grants must agree with invited scope. |
| Organization Invitation → resulting Membership | `1:0..1` | Exactly one on successful acceptance. |
| User ↔ Organization through Membership | `M:N` over periods | Each Membership has one User and one Organization. |
| Membership → Responsibility Grant | `1:1..N` historical | Each Grant belongs to one Membership. |
| Organization → Clinic | `1:0..N` | Every Clinic belongs to exactly one Organization. |
| Clinic → current Location | `1:0..1` | Optional current configuration. |
| Clinic → current Public Profile | `1:0..1` | Optional current configuration. |
| Clinic → Service Offering | `1:0..N` | No minimum Offering requirement. |
| Clinic → Opening Period | `1:0..N` | No minimum Opening Hours requirement. |
| Clinic → Opening Exception | `1:0..N` | Optional current exceptions. |
| Professional Profile ↔ Clinic through Clinic Assignment | `M:N` over periods | Every Assignment references a supporting Membership period. |
| User ↔ Pet through Guardianship | `M:N` over periods | Pet registration creates the initial Guardianship. |
| Pet → Guardianship Invitation | `1:0..N` | Invitation does not grant access. |
| Inviting Guardianship → outgoing Invitation | `1:0..N` | Every Invitation has one inviting Guardianship. |
| Guardianship Invitation → resulting Guardianship | `1:0..1` | Exactly one on successful acceptance. |

### 3.2 Scheduling and Appointments

| Relationship | Cardinality | Notes |
| --- | --- | --- |
| Clinic → current scheduling timezone | `1:0..1` conditionally | Exactly one is required before timezone-dependent current configuration is usable. |
| Clinic → Appointment Availability Period | `1:0..N` | Current configuration. |
| Clinic → Appointment Availability Exception | `1:0..N` | Current configuration. |
| Veterinarian Clinic Assignment → Availability Period | `1:0..N` | Clinic and timezone derive through Assignment. |
| Veterinarian Clinic Assignment → Availability Exception | `1:0..N` | Same derivation. |
| User → requested Appointment | `1:0..N` | Every Appointment preserves one original requesting User. |
| Pet → Appointment | `1:0..N` | Every Appointment has one Pet. |
| Clinic → Appointment | `1:0..N` | Every Appointment has one Clinic. |
| Appointment → Appointment-derived Care Authorization | `1:1` | Mandatory for every successful Phase 1 request. |
| Care Authorization → Appointment | `1:0..1` | `APPOINTMENT_CARE` requires the unique Appointment reference; `CLINICAL_INTAKE` requires it to be absent. |
| Appointment → Lifecycle Event | `1:0..N` | A newly requested Appointment has zero Events. |
| Appointment → Schedule Revision | `1:1..N` | Initial `REQUESTED` revision is mandatory. |
| Appointment → requested Schedule Revision | `1:1..N` historical | Latest applicable revision supplies current requested context. |
| Appointment → confirmed Schedule Revision | `1:0..N` | Confirmation creates a distinct confirmed revision. |
| Appointment → Reschedule Proposal | `1:0..N` historical | At most one `PENDING` Proposal per Appointment. |
| Schedule Revision → Reschedule Proposal (base) | `1:0..N` historical | A Proposal supersedes exactly one base revision of the same Appointment and context; Appointment, base revision, and base context cannot disagree (composite foreign key). |
| Reschedule Proposal → resulting revision | `1:0..1` | An `ACCEPTED` Proposal is the source of exactly one Schedule Revision, of the same Appointment and context as its base and immediately following it. The link is held only by the revision (`source_proposal_id`). For a `REQUESTED` base the resulting revision is a `REQUESTED` revision established by the accepting Guardian. |
| Appointment → Appointment Veterinarian Assignment | `1:0..N` historical | At most one current Assignment. |
| Veterinarian Clinic Assignment → Appointment Assignment | `1:0..N` | Every Appointment Assignment references one concrete Clinic Assignment. |

### 3.3 Care Authorization, audit, and clinical care

| Relationship | Cardinality | Notes |
| --- | --- | --- |
| Guardianship → granted Care Authorization | `1:0..N` | Every Authorization has exactly one granting Guardianship. |
| Pet → Care Authorization | `1:0..N` | Every Authorization concerns one Pet. |
| Clinic → Care Authorization | `1:0..N` | Every Authorization targets one Clinic. |
| Organization → Care Authorization | `1:0..N` | Organization must operate the target Clinic. |
| Clinical Encounter → Care Authorization | Exactly `1` | Every Encounter requires one applicable Authorization. |
| Care Authorization → Clinical Encounter | `1:0..1` | At most one Encounter per Authorization, enforced by the creation operation and, since Minimal Clinical Record — Phase 1, by a unique constraint on `clinical_encounters.care_authorization_id` (`SPEC-MED-001` BR-38). No multiple-Encounter behavior is approved. |
| Clinical Encounter → Appointment | `0..1` | Optional and must match Pet and Clinic. Authoritative for the Appointment–Encounter relationship. |
| Appointment → Clinical Encounter | `1:0..1` through its Authorization | Never mandatory, including for a `COMPLETED` Appointment; at most one through the single Appointment-derived Authorization. |
| Appointment Lifecycle Event → Clinical Encounter | `0..1`, legacy only | Present only on historical `COMPLETED` Events; new Events carry none. |
| Pet → Clinical Encounter | `1:0..N` | Every Encounter concerns one Pet. |
| Clinic → Clinical Encounter | `1:0..N` | Every Encounter preserves one Clinic. |
| Veterinarian Clinic Assignment → responsible Encounter | `1:0..N` | Every Encounter has one responsible historical professional context. |
| Encounter → concluding professional context | `1:0..1` | Absent while active; exactly one when concluded. |
| Encounter → Clinical Record Entry | `1:0..N` | Every Entry has exactly one Encounter. |
| Entry → Contributor attribution | `1:0..N` | Material contribution support without a complete Draft edit log. |
| Finalized Entry → Clinical Amendment | `1:0..N` | Every Amendment references the original Finalized Entry. |
| Entry → Clinical Attachment | `1:0..N` | Every Attachment belongs to one Entry. |
| Audit Event → Pet | `N:1` | Mandatory. |
| Audit Event → acting User | Context-dependent | Required for User-performed access. |
| Audit Event → authorized process identity | Context-dependent | Required for process-performed access; representation remains architectural. |
| Audit Event → authority/provider context | `N:0..1` per applicable relationship | Guardianship, Membership, Grant, Clinic Assignment, Encounter, Authorization, Clinic, or Organization as applicable. |
| Audit Event → specific protected resource | Context-dependent | General scope remains present; reference normalization is open. |

### 3.4 Subscriptions and Communications

| Relationship | Cardinality | Notes |
| --- | --- | --- |
| Organization → Subscription | `1:0..N` historical | At most one equivalent current professional relationship. |
| Subscription → Provider Reference | `1:0..N` | Exact provider uniqueness remains integration-dependent. |
| Subscription → Subscription State Transition | `1:0..N` | Rows are append-only; an initial transition row is not required. |
| Originating domain context → Transactional Communication | `1:0..N` | One event may produce separate Communications for several recipients. |
| Communication → intended recipient context | Exactly `1` | May be a User or non-User contact context. |
| Communication → User | `0..1` | Absent for non-User recipients. |
| Communication → Delivery Job | `1:0..N` | Operational channel/destination work; mutable only as a non-authoritative queue projection. |
| Delivery Job → Delivery Attempt | `1:0..N` | Every actual provider submission appends one retained Attempt fact. |
| Communication → Delivery Attempt | `1:0..N` | Supports several channels, destinations, or retries. |
| Delivery Attempt → Communication | Exactly `1` | Mandatory parent. |
| Delivery Attempt → Push Registration | `0..1` | Only for registration-specific push attempts. |
| User → Push Registration | `1:0..N` | A User may have several eligible devices. |

## 4. Temporal and Lifecycle Model

| Structure | Approved lifecycle semantics |
| --- | --- |
| Organization Membership | Effective start and optional end. An ended period does not reactivate; rejoining creates a new Membership. |
| Responsibility Grant | Effective start and optional end. Removal or scope change ends the period; regranting creates a new Grant. |
| Guardianship | Effective start and optional future end. Phase 1 introduces no ending operation. An ended period does not reactivate. |
| Veterinarian Clinic Assignment | Effective start and optional end. Ended periods do not reactivate; supporting Membership history remains referenced. |
| Current Clinic configuration | Location, Public Profile, Services, Opening Hours, availability, publication, and timezone are current/mutable. Replacement or removal does not rewrite history. |
| Organization Invitation | Pending until accepted, revoked, rejected, or expired. Expires exactly 7 days after creation (SPEC-ORG-002 BR-18). Revocation is recorded only before expiry (existing revocation facts and checks; SPEC-ORG-010). Acceptance erases the stored secret digest. The Staff Phase 1 model needs no schema change. |
| Guardianship Invitation | Validity depends on its own lifecycle, expiration, revocation, recipient proof, and approved rules—not solely on later loss of the inviting Guardianship. |
| Appointment | Created directly in `REQUESTED`; later approved states are `CONFIRMED`, `CANCELLED`, `COMPLETED`, `NO_SHOW`, and `EXPIRED` (`REQUESTED → EXPIRED` only, by the system, per SPEC-APT-015). Terminal outcomes do not reactivate. |
| Appointment Lifecycle Event | Append-only evidence for successful later state changes. There is no initial Event merely duplicating creation. An `EXPIRED` Event preserves both the logical expiry instant (the latest requested start) and the time the system recorded it. |
| Schedule Revision | Immutable. Request creates a `REQUESTED` revision; confirmation creates a distinct `CONFIRMED` revision even if the interval is identical. |
| Reschedule Proposal | `PENDING → ACCEPTED | WITHDRAWN | VOID`; the three outcomes are final and immutable. `PENDING` is a stored invariant: the base is the Appointment's current revision, the Appointment's lifecycle state equals the base context, and no Clinical Encounter exists. A `PENDING` Proposal may still be non-actionable through a derived lapse (base or proposed start passed, or loss of the proposer's continuous authority), which is not stored. Acceptance changes it to `ACCEPTED` and creates exactly one resulting revision atomically; acceptance time, accepting User, and accepting context are those of that revision and the counterparty rule. Clinic withdrawal (SPEC-APT-016) records `withdrawn_at`/`withdrawn_by_user_id`. `VOID` records a system-observed permanent invalidation (`voided_at`, `void_reason`): eagerly when a later revision supersedes the base, the lifecycle state leaves the base context, or a Clinical Encounter is established; lazily, when a new Proposal needs the slot, for a passed proposed time or lost proposer authority. |
| Appointment Veterinarian Assignment | Reassignment ceases the previous current row and creates a replacement while preserving history. |
| Care Authorization | `ACTIVE → REVOKED` for explicit Guardian revocation; `ACTIVE → ENDED` when approved care-context rules determine the basis has ended. Both are terminal. |
| Clinical Encounter | `ACTIVE → CONCLUDED`. Conclusion is terminal for active care but does not seal documentation or cause unrelated lifecycle changes. Its lifecycle is independent of the Appointment lifecycle in both directions; an Appointment-backed Encounter may be established while the Appointment is `CONFIRMED` or after it is `COMPLETED`. |
| Clinical Record Entry | Mutable while `DRAFT`; explicit one-way `DRAFT → FINALIZED`. Finalized meaning and category are protected. |
| Material contributor attribution | Once a material contribution occurs, sufficient attribution remains traceable during Draft. Finalization freezes relevant attribution. |
| Clinical Amendment | Finalized and append-only from creation. Always references the original Finalized Entry. |
| Clinical Attachment | Pending/available/rejected validation semantics. Draft content may follow approved removal/replacement behavior; finalized available content is protected history. |
| Organization Subscription | Provider-independent commercial relationship. Current state derives from immutable initial facts and the latest accepted append-only State Transition under ADR-006. Historical periods and validity gaps remain reconstructable. |
| Subscription State Transition | Zero or more append-only transition rows. Establishment need not create an initial Transition row. |
| Transactional Communication | Durable logical intent remains separate from originating state. |
| Delivery Job | Mutable non-authoritative dispatch projection; it does not replace Communication intent or immutable provider-attempt history. |
| Delivery Attempt | Append-only while retained as delivery history. Retention duration remains unresolved. |
| Push Registration | Mutable technical destination that may rotate, become ineligible, be invalidated, or be reassociated without changing User identity. |

Clinic owns the authoritative current named scheduling timezone. Current Opening
Hours and availability derive their timezone through Clinic and must not own
independently authoritative timezone values. Schedule Revisions and Reschedule
Proposals preserve establishment-time named timezone snapshots and resolved
actual intervals.

The current timezone is set through the approved Clinic self-service operation
(`SPEC-APT-013` BR-76, gated by BR-56). It is a single current value on
`clinics`: it cannot be cleared, and setting it introduces no timezone history
structure. The change is prospective and cannot reinterpret historical
scheduling facts; stored Availability keeps its local values.

Subscription `EXPIRED` must not silently become commercially valid. Later
validity requires a trusted commercial workflow. Reuse of an existing domain
Subscription versus creation of a new period remains unresolved, but expired
periods and validity gaps must remain reconstructable.

## 5. Integrity Invariants

### 5.1 Identity and cardinality

- Core domain identities are provider-independent.
- Authentication subjects, billing identifiers, communication destinations,
  storage references, names, microchips, and license numbers do not replace
  domain identity.
- A User has at most one User Profile and one Professional Profile.
- Every Phase 1 Professional Profile has exactly one separate Credential.
- A completed Profile-creation operation cannot leave a Profile without its
  Credential or create a second Credential.
- Every Clinic belongs to exactly one Organization.
- A Clinic may exist with zero Services, Opening Periods, Opening Exceptions,
  availability periods, Location, or Public Profile.
- At least one active Organization Owner must remain.

### 5.2 Temporal authorization relationships

- Duplicate active Memberships, Guardianships, equivalent Responsibility Grants,
  and equivalent Clinic Assignments are prohibited.
- Effective ends cannot precede starts.
- Ended Membership, Grant, Guardianship, and Clinic Assignment periods do not
  reactivate.
- A Clinic Assignment's Clinic belongs to the Organization of its supporting
  Membership.
- Membership ending prevents linked historical Assignments from granting new
  current authority.
- Authentication alone grants no domain capability.
- Capability derives from active relationships, applicable scope, and operation
  context; no global Role or permanent User permission substitutes for them.

### 5.3 Guardianship Invitations

- Every Guardianship Invitation references one inviting Guardianship concerning
  the same Pet.
- The inviting Guardianship is active when the Invitation is created.
- Inviter User derives through the inviting Guardianship.
- Later loss or ending of the inviting Guardian's Guardianship does not
  retroactively invalidate an otherwise valid Invitation.
- Acceptance proves the recipient and atomically creates one non-duplicate
  Guardianship.

### 5.4 Appointment request and scheduling

- Appointment request authority is evaluated from the current applicable
  Guardianship plus the other approved request-authorization rules.
- The Appointment-derived Care Authorization does not authorize its own creation.
- Successful request atomically establishes the Appointment in `REQUESTED`, its
  original requesting User, an initial `REQUESTED` Schedule Revision, and exactly
  one Appointment-derived Care Authorization preserving the granting
  Guardianship used for the request.
- The granting Guardianship's User equals the original requesting User at
  establishment.
- Appointment and Appointment-derived Care Authorization Pet and Clinic contexts
  agree.
- The Care Authorization Organization is the Veterinary Organization operating
  that Clinic. Appointment Organization derives through Clinic and need not be
  duplicated as authoritative Appointment state.
- Appointment creation does not require an initial Lifecycle Event.
- Every later successful lifecycle transition requiring actor/time history
  creates one coherent Lifecycle Event.
- Requested and confirmed Schedule Revisions remain distinct even when their
  intervals match.
- Schedule Revisions and Proposals preserve resolved actual intervals and
  establishment-time timezone snapshots.
- A Reschedule Proposal's Appointment, base revision, and base context agree
  by composite foreign key; a revision sourced from a Proposal belongs to the
  same Appointment and context as that Proposal by composite foreign key. A
  revision has at most one source Proposal and a Proposal is the source of at
  most one revision. Revisions without a source are the initial request, a
  Guardian requested reschedule, or the Clinic confirmation. A `REQUESTED`
  revision with a source is a Guardian-accepted Clinic Alternative Time
  (SPEC-APT-019); a `CONFIRMED` revision with a source is an accepted confirmed
  reschedule.
- Approved Reschedule Proposal base contexts are `CONFIRMED` and `REQUESTED`.
  A `REQUESTED` base requires `proposing_context = 'CLINIC'` (candidate
  relational CHECK); the counterparty rule then makes the accepting context
  `GUARDIAN`. Migration 20261010090000 replaced the earlier `CONFIRMED`-only
  base CHECK accordingly.
- At most one `PENDING` Proposal exists per Appointment, whatever its base
  context (`UNIQUE (appointment_id) WHERE state = 'PENDING'`).
- "Guardian accepted the Clinic's alternative, awaiting confirmation" is
  derived — `REQUESTED` lifecycle plus a current revision whose source
  Proposal is Clinic-originated — and is not persisted.
- A requested Appointment or Assignment on it does not constitute confirmed
  capacity commitment.
- Confirmed Appointment commitment derives from Appointment lifecycle plus the
  current confirmed Schedule Revision.
- Where a current Veterinarian Assignment exists or Veterinarian-specific
  conflict evaluation applies, that Assignment additionally participates in the
  relevant professional scheduling commitment and conflict evaluation.
- Confirmed overlapping actual intervals cannot double-book the same assigned
  Veterinarian across Clinics.
- Every Appointment Assignment references one concrete Clinic Assignment, and
  duplicated Profile, Clinic, Organization, or Membership fields cannot become
  independent authority.
- Appointment Assignment remains distinct from responsible Veterinarian
  provenance and clinical authorship.
- No numerical Clinic capacity, room, equipment, employee-shift, or travel-time
  invariant is introduced.
- A pending request is a `REQUESTED` Appointment whose latest `REQUESTED`
  Schedule Revision start is strictly after authoritative current time. At
  most one pending request exists per Pet and Clinic. Because the definition
  depends on current time and on another table, it is enforced inside the
  trusted request operation under concurrency-safe serialization rather than by
  a time-independent uniqueness constraint; confirmed and terminal Appointments
  never participate.
- A `REQUESTED` Appointment whose latest requested start is not after current
  time is logically expired: confirmation, Guardian and Clinic cancellation,
  Guardian rescheduling, pending-request evaluation, and pre-care access
  evaluate that condition directly, without depending on `EXPIRED` having been
  materialized. Its only applicable terminal outcome is `EXPIRED`.
- `EXPIRED` is materialized by a trusted, idempotent system process, never by a
  read and never by a client. Materialization establishes state, exactly one
  `REQUESTED → EXPIRED` Lifecycle Event, and the Care Authorization ending
  together, and creates no Schedule Revision or Communication.
- System-performed Lifecycle Events are distinguishable from Guardian and
  Clinic actor events and identify no User actor. No fabricated, service, or
  placeholder User may be stored to satisfy actor storage; the lifecycle actor
  representation must therefore permit a system actor context without a User
  actor while still requiring a User actor for every Guardian or Clinic
  transition.

### 5.5 Care Authorization

- Granting Guardianship is the authoritative historical grant context; granting
  User derives through it.
- Care Authorization Pet equals granting Guardianship Pet.
- The target Organization operates the target Clinic.
- Every successful Appointment request creates exactly one Appointment-derived
  Authorization, and no replacement workflow exists.
- A Care Authorization references at most one Appointment.
- Phase 1 also supports Guardian establishment of a minimal non-Appointment
  `CLINICAL_INTAKE` Authorization for walk-in, unscheduled, or urgent arrival
  care. It remains Pet-, Clinic-, Organization-, and care-context-specific and
  is not an emergency or break-glass bypass.
- `APPOINTMENT_CARE` requires an Appointment; `CLINICAL_INTAKE` requires no
  Appointment.
- Historical grant attribution does not confer permanent revocation authority;
  current revocation authority is evaluated separately.
- `REVOKED` preserves revoking User and revocation time. Guardian-provided reason
  is optional.
- Generic normal ending remains deferred until the system can establish that
  every supported post-care obligation has been resolved. Encounter conclusion
  or absence of Draft Entries alone is insufficient before Slice 13 Attachment
  and post-care completion state can be represented.
- `ENDED` preserves terminal time and normal-ending context without requiring an
  ending User by default.
- Appointment expiry ends an `ACTIVE` `APPOINTMENT_CARE` Authorization with the
  distinct normal-ending context `APPOINTMENT_EXPIRED`, never a cancellation or
  no-show context.
- While its Appointment is `REQUESTED`, an `APPOINTMENT_CARE` Authorization
  provides pre-care access only while the latest requested start is strictly
  after current time, independently of whether `EXPIRED` has been
  materialized.
- Exactly one terminal result wins a concurrent revoke/end race.
- Terminal Authorizations do not reactivate; reauthorization creates a new
  identity.

### 5.6 Clinical care and provenance

- Every Encounter preserves one Pet, Clinic, Organization provenance,
  responsible Veterinarian Clinic Assignment, creating User, occurrence/start
  time, creation time, and applicable Care Authorization.
- Encounter Clinic, Organization, professional context, and Authorization agree.
- An optional Appointment matches Encounter Pet and Clinic, is `CONFIRMED` or
  `COMPLETED` at Encounter establishment, and was confirmed no later than the
  Encounter start; for a `COMPLETED` Appointment the Encounter start is no later
  than the completion Event. A `REQUESTED`, `CANCELLED`, `NO_SHOW`, or `EXPIRED`
  Appointment never backs an Encounter; care before confirmation uses a
  `CLINICAL_INTAKE` Authorization and an Encounter without Appointment.
- The responsible Clinic Assignment is current at establishment and began no
  later than the Encounter start.
- The Encounter's Appointment and Authorization references are the single
  source of truth for the Appointment–Encounter relationship; Appointment
  Lifecycle Events do not reference new Encounters.
- The trusted creation operation establishes at most one Encounter per Care
  Authorization, and therefore per Appointment. Phase 1 does not express this
  as a relational uniqueness constraint.
- Absence of a relational reverse uniqueness constraint does not approve
  multiple-Encounter workflows.
- Conclusion preserves its own professional context and does not replace
  responsible Veterinarian provenance.
- Entry Pet, Clinic, Organization, responsible professional, Authorization, and
  optional Appointment context derive through immutable Encounter provenance.
- Original creator and material contributors remain distinct attribution
  concepts. A later editor cannot replace or rewrite historical attribution.
- `most recent editor` is not a required authoritative persisted role.
- Material contributor traceability does not require immutable storage of every
  Draft edit or version.
- Finalization freezes creator, relevant contributors, finalizer, content,
  category, and applicable clinical-event provenance.
- Amendments preserve the original Finalized Entry, reason, content, amender,
  time, and distinct provenance.
- Amendment history is chronologically and logically reconstructable without a
  mandatory `prior_amendment_id`.
- Attachment identity is independent of storage identity.
- Storage references are not globally unique as a domain invariant.
- A cryptographic checksum is not mandatory, but sufficient integrity
  information is required.
- Finalized available Attachment content cannot be silently replaced or
  ordinarily destructively deleted.
- Encounter `CONCLUDED` does not seal documentation.

### 5.7 Medical Access Audit

- Medical Access Audit Events are append-only through ordinary application
  behavior and distinguish `PERMITTED` from `DENIED`.
- Every Event identifies the acting User or authorized process as applicable.
- No generic Actor, Principal, Role, or permission entity is introduced.
- Applicable Guardianship, Membership, Grant, Clinic Assignment, Encounter,
  Care Authorization, accessing Clinic, and accessing Organization context
  remains historically traceable.
- Accessing provider is distinct from the protected resource's provider of
  origin.
- Events preserve meaningful general protected-resource scope and specific
  resource identity where applicable without copying complete clinical payloads.
- Under ADR-005, correlation/session context is context-dependent. When present,
  it is trusted and is not domain identity.
- Audit Event presence or a previous `PERMITTED` outcome never grants later
  access.
- Required audited reads fail closed before release if durable evidence cannot
  be recorded.
- Required audited mutations and their Audit Events commit coherently.
- Failure to record a required denial cannot convert denial into permission.

### 5.8 Subscriptions and Communications

- Subscription belongs to Organization, not User, Clinic, Owner, Member, or
  Veterinarian.
- Phase 1 permits at most one equivalent current professional Subscription
  relationship per Organization.
- Provider references remain operational mappings; exact uniqueness depends on
  selected provider semantics.
- State Transition history is append-only. If a current-state projection is
  stored, it remains coherent with commercial history.
- Duplicate provider events do not duplicate logical transitions; stale events
  do not replace newer commercial truth.
- Historical commercial-validity gaps remain visible.
- Entitlement is Organization-scoped, capability-specific, and derived at
  operation time.
- `PAST_DUE` provides no normal Phase 1 Entitlement. `CANCELLED` may continue
  only while an already-valid commercial period remains effective.
- Entitlement loss does not delete historical Appointment, Authorization,
  clinical, audit, or commercial information.
- Safe resolution is limited operation-specific behavior for existing
  obligations, not a new Entitlement.
- Communication intent never owns originating domain state.
- Durable handoff prevents a successful required operation from silently losing
  its Communication intent.
- Delivery failure ordinarily does not roll back successful domain state.
- Email and push outcomes remain independently meaningful.
- Retry and callback handling does not repeat the originating operation.
- Provider push acceptance does not prove User delivery, display, read, or
  acknowledgement.
- Push token is not User identity, authentication, or authorization.
- Reminder dispatch re-evaluates current Appointment state, confirmed schedule,
  and current applicable Guardianship.
- A Proposal-originated Communication's type matches its Proposal's base
  context: `APPOINTMENT_RESCHEDULE_PROPOSED` and
  `APPOINTMENT_RESCHEDULE_ACCEPTED` for a `CONFIRMED` base,
  `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` for a `REQUESTED` base. Both proposed
  types require a Clinic-originated Proposal. One Proposal reference serves
  every type; no second nullable Proposal reference is introduced.

### 5.9 Discovery

- Public Discovery is anonymous and exposes only approved public Clinic
  information.
- Discovery grants no protected capability.
- Basic Public Discovery requires current public-discovery eligibility but does
  not universally require Location.
- Nearby Discovery additionally requires a valid current Clinic geographic
  Location, valid reference point, and finite supported radius.
- Map Discovery additionally requires a valid current Clinic geographic Location
  and applicable geographic area or viewport.
- A Clinic exactly on the Nearby radius boundary is included.
- Nearby results order nearest to farthest; no business-significant secondary
  order for equal distances is defined.
- Empty Nearby and Map results are valid, and radius is not silently broadened.
- Appointment availability is not a Discovery prerequisite.
- Geographic distance is derived proximity, not route distance, travel time, or
  traffic-aware duration.
- Geographic Discovery must not require downloading all Clinic Locations to the
  client.

## 6. Authoritative Versus Derived Inventory

| Derived concept | Authoritative source |
| --- | --- |
| Organization ownership | Active Membership plus an active Organization-scoped `OWNER` Responsibility Grant. |
| Organization capability | Active Membership plus the applicable active Responsibility Grant and scope for the requested operation. |
| Current Guardian capability | Active Guardianship. |
| `My Pets` | Active Guardianships joined to Pets. |
| Inviting User for Guardianship Invitation | Inviting Guardianship. |
| Request authority for Appointment | Current applicable Guardianship plus other approved request-authorization rules. Successful request then creates the Care Authorization using that Guardianship. |
| Granting User for Care Authorization | Granting Guardianship. |
| Current active status for temporal relationships | Effective period plus required supporting-relationship validity. |
| Timezone on recurring configuration | Clinic's authoritative current scheduling timezone. |
| Current requested/confirmed schedule | Immutable Schedule Revision history or a coherent derived pointer. |
| Current assigned Veterinarian | Current Appointment Veterinarian Assignment. |
| Appointment Assignment professional context | Referenced Veterinarian Clinic Assignment. |
| Available Appointment slots | Availability, exceptions, duration, existing commitments, timezone resolution, and applicable conflicts. |
| Confirmed Appointment commitment | Appointment lifecycle plus current confirmed Schedule Revision; current Veterinarian Assignment additionally participates where applicable. |
| Entry Pet/Clinic/Organization/responsible professional context | Immutable Clinical Encounter. |
| Logical Medical Record | Pet-centered projection of finalized Entries, Amendments, and available finalized Attachments. |
| Medical-access decision | Current authorization basis, actor authority, provider context, applicable Entitlement, purpose, lifecycle, and least privilege. |
| Professional Entitlement | Requested capability, Organization, trusted commercial state/validity, and Phase 1 policy. |
| Current Subscription state | Immutable initial Subscription facts plus the latest accepted append-only State Transition, as established by ADR-006. |
| Communication delivery summary | Append-only Delivery Attempts or the coherent non-authoritative Delivery Job projection. |
| Reminder eligibility | Current Appointment state/schedule and current recipient eligibility. |
| Discovery Result | Current eligible Clinic and approved public information. |
| Nearby distance and order | Query reference point, current Clinic Location, and effective radius. |
| Map representation | Current public Clinic identity, Location, and viewport context. |
| Visitor reference location | Query input only; not automatically profile or domain state. |

No authoritative Phase 1 tables exist for Medical Record, My Pets, Medical
Access Decision, Entitlement Decision, available slots, Discovery Results, map
markers, distances, generic Care Episode, reminder campaigns/preferences, or
external billing products as domain capabilities.

## 7. Transaction and Concurrency Boundaries

For structures not yet physically introduced, exact locking, constraint,
function, Row Level Security, outbox, inbox, and queue mechanisms remain open.
For Slices 1–9, the source-controlled migrations record the selected physical
mechanisms.

| Operation or lifecycle effect | Required coherent result |
| --- | --- |
| Register User | User and authentication linkage establish one coherent provider-independent identity. |
| Create Professional Profile | Profile and exactly one Credential succeed together. The client-safe self operation serializes on the acting User; an exact repeat returns the existing Profile and Credential (`ALREADY_EXISTS`) and a different credential request is rejected without overwriting (SPEC-VET-001 §13). |
| Establish Organization (Commercial Onboarding) | Organization, initial Membership, active Owner Grant, and initial Subscription all exist or none does, at one establishment instant; performed only in trusted service context by `establish_veterinary_organization`; a retried onboarding (same Organization establishment key and requested inputs) establishes nothing new and returns the original result; contradictory reuse of the key is rejected (ADR-009). The Organization → Subscription rule is guaranteed prospectively by this operation, not yet by a structural constraint. |
| Create Organization Invitation | Invitation, intended responsibilities, and its Communication succeed together; `expires_at = created_at + 7 days` from one trusted creation instant; at most one pending Invitation per Organization and normalized recipient address (SPEC-ORG-002 BR-18, BR-19). |
| Accept Organization Invitation | Invitation acceptance, Membership, and intended Grants are atomic and not repeatable. Proof is the bearer-secret digest compared inside the authenticated operation; the accepting User is derived from authentication; Organization → Invitation → Clinic lock order (SPEC-ORG-003). |
| Revoke Organization Invitation | Only a pending, unexpired Invitation receives revocation facts; repeated revocation and revocation of an accepted or expired Invitation change nothing; serialized with acceptance through Organization → Invitation (SPEC-ORG-010). |
| End Organization Membership (Staff Phase 1) | Every active Grant and the Membership end at one instant; no row is deleted; Owner and self targets are rejected; repeated ending changes nothing (SPEC-ORG-004 §10). |
| Change Responsibility / protect last Owner | Temporal Grant changes preserve history and cannot leave zero active Owners. |
| Change Responsibility (Staff, one Grant) | Add, Change, or End exactly one Grant, serialized on the Organization; Change ends the named Grant and starts its replacement at one instant with unrelated Grants untouched; `OWNER` Grants and other actors' Owner Memberships are never modified; the last current Grant is not ended; a current `VETERINARIAN` Grant is not ended or changed away while current Clinic Assignments exist; authorization precedes every target fact (SPEC-ORG-006 §14). |
| Establish / end Veterinarian Clinic Assignment (Staff) | Organization → Clinic → Membership lock order; the Profile is derived from the Membership's User; the client-safe path requires a current `VETERINARIAN` Grant to establish but not to end; statement-instant start and end; repeated attempts change nothing (SPEC-VET-004 §13, SPEC-VET-005 §13). |
| Create Clinic | Clinic may be created without placeholder configuration rows. The client-safe operation records the creation key on the Clinic in the same insert; the same Organization and key resolve to that one Clinic, a key in another Organization is a separate intent, and creations in one Organization serialize on the Organization row (`SPEC-CLI-001` §10). |
| Configure Services or availability | Resulting current configuration is coherent, non-duplicated where applicable, and interpretable through Clinic timezone. |
| Create Pet | Pet and initial active Guardianship succeed together. |
| Update Pet Profile | Current Guardianship is re-verified at execution time, not trusted from request construction; optimistic concurrency prevents a stale request from silently overwriting a concurrent change; a semantic no-op leaves the revision and all other Pet and Guardianship state unchanged. |
| Create Guardianship Invitation | Inviting Guardianship is active and Pet-matching at commit; the reference is preserved. |
| Accept Guardianship Invitation | Acceptance and a non-duplicate new Guardianship succeed together. |
| Request Appointment | Current Guardianship and other rules authorize the request before creation. Appointment `REQUESTED`, requester, initial requested revision, and exactly one matching Care Authorization succeed together; no initial Lifecycle Event is created. Concurrent requests for the same Pet and Clinic yield at most one pending request; a rejected duplicate writes nothing. |
| Grant `CLINICAL_INTAKE` Care Authorization | Current Guardianship authorizes one Pet-, Clinic-, Organization-, and care-context-specific `ACTIVE` Authorization with no Appointment. The grant neither creates clinical care nor depends on scheduling or Clinic publication. Trusted operation only: Clinical Intake has no Phase 1 client workflow, so no client establishes it (`SPEC-ACC-002` BR-62). |
| Confirm Appointment | State, Event, distinct confirmed revision, and confirmed commitment succeed together after applicable checks. Veterinarian Assignment is not universally required. A pending Clinic Alternative Time Proposal becomes `VOID` (`BASE_REVISION_SUPERSEDED`, recorded by the confirmed revision insert) in the same transaction. |
| Reschedule requested Appointment | A new requested revision is created; state remains `REQUESTED`; no Lifecycle Event is added. A request whose latest requested start is not after current time cannot be rescheduled. A pending Clinic Alternative Time Proposal becomes `VOID` (`BASE_REVISION_SUPERSEDED`) through the existing invalidation trigger. |
| Expire unconfirmed request | Trusted system process only. `REQUESTED → EXPIRED`, one system-actor Lifecycle Event, and the `APPOINTMENT_EXPIRED` Authorization ending succeed together, at most once per Appointment; concurrent confirmation, cancellation, or rescheduling yields exactly one coherent outcome. No Schedule Revision or Communication is created. |
| Propose confirmed reschedule | Proposal references the exact current confirmed context without changing it; Clinic proposals carry the expected confirmed revision sequence; for either proposing context the end is the resolved start plus the Clinic's current standard duration, which is required, frozen (the base confirmed elapsed duration is not used); the interval must be feasible and no Clinical Encounter may exist. |
| Accept Proposal | The Proposal becomes `ACCEPTED` and then its single resulting revision (same context as the base, immediately following it, exactly the frozen interval) is created, atomically, while Appointment remains `CONFIRMED`; a failure rolls both back. |
| Propose requested Alternative Time | Clinic only; `APPOINTMENT_RESCHEDULE` plus `APPOINTMENT_MANAGEMENT` are evaluated under the existing lock order; the Appointment must be `REQUESTED`; the expected requested revision sequence must equal the latest requested revision's, otherwise a stable `P0001` with zero writes (no lazy `VOID`, no Communication). The Proposal references exactly that revision with base context `REQUESTED`; its end is the resolved start plus the Clinic's current standard duration, frozen; feasibility is checked; any lapsed `PENDING` Proposal is lazily `VOID`; the `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` intents are established; all atomically. No revision or Lifecycle Event is created. |
| Accept requested Alternative Time | Guardian only, current Guardianship, no Entitlement gate; the Proposal must be actionable with a `REQUESTED` base; feasibility is revalidated. The Proposal becomes `ACCEPTED` and exactly one `REQUESTED` revision (immediately following the base, exactly the frozen interval, `established_by_user_id` = Guardian, `source_proposal_id` = Proposal) is created, atomically; the Appointment remains `REQUESTED`; no Lifecycle Event or Communication. |
| Invalidate pending Proposal | A Schedule Revision insert not sourced from the pending Proposal, a lifecycle change out of the base context, or a Clinical Encounter insert makes the pending Proposal `VOID` in the same transaction, through one internal operation invoked by row triggers; no Appointment workflow carries Proposal-cleanup code, and reads never write. |
| Assign or reassign Veterinarian | Concrete Clinic Assignment eligibility is validated; at most one current Appointment Assignment; failed reassignment preserves the prior row. |
| Cross-Clinic professional conflict | The same assigned Veterinarian cannot receive incompatible overlapping confirmed actual intervals. |
| Cancel Appointment | Terminal state/Event, commitment release, and applicable approved Authorization ending are coherent. A `REQUESTED` Appointment is cancellable only while its latest requested start is after current time; a rejected attempt writes nothing. |
| Complete Appointment | Clinic only; `APPOINTMENT_COMPLETE` under the existing lock order, no Entitlement gate; the Appointment must be `CONFIRMED`; the expected confirmed revision sequence is required (`22023` when missing or not positive, before state is read) and must equal the latest confirmed revision's, otherwise a stable `P0001` with zero writes; that revision's start must have been reached. `CONFIRMED → COMPLETED` state and one Clinic-actor Event at the operation time with no Encounter reference succeed together; a pending Proposal becomes `VOID` and the completion Communication intents are established through existing lifecycle behavior. No Veterinarian Assignment, Clinical Encounter, or clinical data is read or required; an existing Encounter does not block it. A historical completion Event that references an Encounter must stay consistent with it (same Appointment, Pet, and Clinic; Encounter start not after the Event). |
| Mark no-show | State/Event validate absence of incompatible actual-care/Encounter evidence. |
| Appointment ↔ Encounter coherence | An Appointment-backed Encounter's Appointment is `CONFIRMED` or `COMPLETED`, never `REQUESTED`, `CANCELLED`, `NO_SHOW`, or `EXPIRED`; its care start is at or after the single confirmation Event and, for a `COMPLETED` Appointment, at or before the completion Event; this holds whichever was recorded first. |
| Revoke Care Authorization | `ACTIVE → REVOKED` preserves revoker/time; exactly one terminal outcome wins. |
| Revoke Care Authorization (Guardian client path) | Appointment-keyed (`SPEC-ACC-002` §16): the caller's current Guardianship of the Appointment's Pet is decided with the Appointment, before any existence is revealed; locks Appointment (shared) → Guardianship → Care Authorization; an `ACTIVE` Appointment-derived Authorization becomes `REVOKED` through the trusted transition, anything else reconciles to `ALREADY_INACTIVE` unchanged; the Appointment and every clinical row are untouched. The generic Care-Authorization-keyed and Appointment-keyed revoke operations are trusted only. No schema change. |
| Establish applicable normal Authorization ending | Approved care-context behavior establishes `ACTIVE → ENDED` with terminal context; this is not a generic command. |
| Create Clinical Encounter | Matching `ACTIVE` Authorization, concrete current professional context whose Clinic Assignment began at or before the care start, authorization, and derived `CLINICAL_CARE` Entitlement are valid; at most one Encounter per Authorization (also a unique constraint); for an Appointment-backed Encounter, the Appointment-coherence bounds above apply and the Appointment lifecycle is not changed; no Entitlement Decision row is written. The client path is Appointment-keyed (`SPEC-MED-001` §15): the Authorization is derived from the Appointment, never supplied; a `NULL` care start means the statement instant and is accepted only for a `CONFIRMED` Appointment; a repeat by the responsible Clinic Assignment reconciles to the existing Encounter. |
| Conclude Encounter | First valid conclusion preserves its own professional context without replacing responsible provenance or sealing documentation. |
| Create Draft Entry (client path) | Appointment-keyed (`SPEC-MED-002` §14); only the responsible Clinic Assignment creates; the caller's creation key and the canonical request digest are written with the Entry; a repeat with the same key and identical requested facts returns the same Entry, a repeat with different facts is a deterministic `23505`; the key and digest are immutable. |
| Record material contribution | Attribution remains traceable and cannot later appear authored by another User. |
| Finalize Entry | Required content, creator, contributors, finalizer, and Attachment states freeze together; failure leaves Draft. |
| Create Amendment | Complete append-only Amendment is created while original Entry remains unchanged. The client path is Appointment-keyed (`SPEC-MED-004` §15): current exact-Clinic `CLINICAL_DOCUMENTATION` Veterinarian context decided before the Entry is resolved within that Clinic's Appointment Encounter, then the `SPEC-MED-009` access basis (Encounter `ACTIVE` or Care Authorization `ACTIVE`, one shared predicate) under the Care Authorization and Encounter locks; no Entitlement or original-author requirement; Encounter `CONCLUDED` and Appointment `COMPLETED` allowed within that basis; the existing per-User key reconciles an identical repeat and rejects a different one with `23505`. |
| View professional longitudinal history (client path) | Appointment-keyed (`SPEC-MED-005` §15): the current exact-Clinic Veterinarian context with `CLINICAL_CARE` and the Organization's `CLINICAL_CARE` Entitlement are decided first and share-locked (Membership, Grant, Clinic Assignment), then the Appointment of that Clinic, its Care Authorization and Encounter (share-locked), then one private history-window predicate (Authorization `ACTIVE` and either pre-care with no Encounter or an `ACTIVE` Encounter). The content is the Pet's every `FINALIZED` Entry from every Clinic and Organization, from one private projection shared with the Guardian read; Veterinarian names are resolved through the historically recorded Users (no current Membership required, no snapshot column); one `PERMITTED` audit event per page. No schema change. |
| Upload/validate Attachment | Relational availability cannot claim an unvalidated or missing binary; failure does not create false clinical history. |
| Audit-required protected read | Durable `PERMITTED` evidence exists before protected information is released. |
| Audit-required protected mutation | Domain mutation and required Audit Event both succeed or neither does. |
| Record denied access | An audit-required normal denial returns structured `DENIED` without protected payload and commits its required Event. Audit-persistence or infrastructure failure aborts and still returns no protected information. |
| Establish Subscription | Subscription-to-Organization relationship, establishment time, initial trusted state, and commercial context are coherent; an initial Transition row is optional. |
| Process Subscription update/callback | Derived current state and append-only history remain coherent; duplicates and stale callbacks are harmless. |
| Entitlement-protected operation | Derived Entitlement and separate domain authorization are evaluated coherently at operation time. |
| Durable Communication handoff | Successful required domain behavior cannot silently lose its logical Communication intent. |
| Establish alternative-time Communication | A Clinic Proposal on a `REQUESTED` base establishes `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` (never `APPOINTMENT_RESCHEDULE_PROPOSED`) for current Guardians, referencing it through the existing `appointment_reschedule_proposal_id`, at most once per Proposal and recipient; delivery requires the Proposal to remain actionable. |
| Delivery retry/provider callback | Retry does not repeat the originating operation; callbacks are idempotent and ordering-safe. |
| Reassociate/invalidate Push Registration | Private delivery eligibility changes without altering unrelated domain relationships. |
| Dispatch Appointment reminder | Obsolete reminders are suppressed; current confirmed schedule and current Guardianship determine relevance and recipients. |

The Phase 1 transaction matrix does not introduce `Change Clinic timezone` or
`Persist Entitlement Decision` operations.

## 8. Deletion and Retention Semantics

| Category | Approved semantics |
| --- | --- |
| Current configuration | Clinic Location, Public Profile, Services, Opening Hours, availability, and mutable profile data may be removed or replaced through approved behavior. Exact physical strategy remains architectural. |
| Technical registration | Push Registrations and authentication links may become ineligible, invalidated, or disconnected. No mandatory soft-delete implementation is prescribed. |
| Temporal relationships | Memberships, Grants, Guardianships where a future ending exists, Clinic Assignments, Appointment Assignments, Care Authorizations, and commercial periods end while history remains. |
| Immutable/append-only history | Schedule Revisions, later Appointment Lifecycle Events, Amendments, Medical Access Audit Events, and Subscription State Transitions are not ordinarily destructively rewritten. |
| Clinical Entry/Attachment lifecycle | Draft content follows approved mutable behavior. Finalized Entries and available finalized Attachments are protected history. |
| Communication history | Delivery Attempts are append-only while retained. Exact retention duration remains unresolved. |
| Invitations | Use semantic lifecycle rather than assuming deletion. Secret cleanup does not erase required attribution. |
| Domain roots and protected history | User, Pet, Organization, Clinic, Appointment, Encounter, Subscription, finalized clinical history, and audit history require legal- and product-policy-aware treatment. |

Ordinary deletion must not cascade through historical Membership, Guardianship,
Assignment, Appointment, Care Authorization, clinical, audit, commercial, or
communication provenance. No legal retention duration, anonymization policy,
physical-delete rule, soft-delete rule, or tombstone strategy is invented here.

## 9. Controlled Values and Semantic-Enum Status

Controlled concepts do not automatically require editable business tables.

### 9.1 Phase 1 values fixed by approved Specifications

| Concept | Values |
| --- | --- |
| Appointment lifecycle | `REQUESTED`, `CONFIRMED`, `CANCELLED`, `COMPLETED`, `NO_SHOW`, `EXPIRED` |
| Schedule Revision context | `REQUESTED`, `CONFIRMED` |
| Reschedule Proposal approved states | `PENDING`, `ACCEPTED`, `WITHDRAWN` (Clinic-originated only, SPEC-APT-016), `VOID` (system-observed permanent invalidation) |
| Reschedule Proposal void reasons | `BASE_REVISION_SUPERSEDED`, `APPOINTMENT_LIFECYCLE_CHANGED`, `CLINICAL_ENCOUNTER_STARTED`, `PROPOSED_TIME_PASSED`, `PROPOSING_AUTHORITY_LOST` |
| Clinical Encounter lifecycle | `ACTIVE`, `CONCLUDED` |
| Clinical Record Entry lifecycle | `DRAFT`, `FINALIZED` |
| Clinical Entry category | `EXAMINATION`, `DIAGNOSIS`, `TREATMENT`, `PROCEDURE`, `VACCINATION`, `PRESCRIPTION`, `LABORATORY_RESULT`, `IMAGING_RESULT`, `CLINICAL_NOTE`, `OTHER` |
| Care Authorization purpose | `APPOINTMENT_CARE`, `CLINICAL_INTAKE` |
| Care Authorization lifecycle | `ACTIVE`, `REVOKED`, `ENDED` |
| Medical audit outcome | `PERMITTED`, `DENIED` |
| Medical audit operation semantics | `VIEW_PET_MEDICAL_HISTORY`, `VIEW_CLINICAL_RECORD_ENTRY`, `VIEW_CLINICAL_ATTACHMENT`, `ACCESS_FOR_APPOINTMENT_OPERATIONS`, `ACCESS_FOR_CLINICAL_CARE`, `ACCESS_FOR_POST_CARE_DOCUMENTATION` |
| Subscription state | `PENDING`, `ACTIVE`, `PAST_DUE`, `CANCELLED`, `EXPIRED` |
| Professional Entitlement | `APPOINTMENT_MANAGEMENT`, `PROFESSIONAL_SCHEDULING`, `CLINICAL_CARE`, `CLINICAL_DOCUMENTATION` |
| Organization responsibility | `OWNER`, `ADMINISTRATOR`, `RECEPTIONIST`, `VETERINARIAN` |
| Responsibility scope | `ORGANIZATION`, `CLINIC` |
| Clinic service category | `GENERAL_CONSULTATION`, `VACCINATION`, `SURGERY`, `DENTISTRY`, `DIAGNOSTIC_IMAGING`, `LABORATORY`, `EMERGENCY_CARE`, `HOSPITALIZATION`, `OTHER` |

### 9.2 Required distinctions with open physical identifiers

- Attachment pending-validation, available, and rejected semantics;
- transactional email and push channel distinctions;
- Communication pending, sent, and failed outcomes where applicable;
- Communication types corresponding to approved events;
- User-performed versus authorized-process audit actor representation;
- Guardian, Clinic, and system Appointment Lifecycle Event actor
  representation, where a system event has no User actor;
- Care Authorization normal-ending context, including the distinct
  `APPOINTMENT_EXPIRED` context;
- provider callback, failure, and token-invalidation semantics.

These not-yet-implemented distinctions may use enums, checks, controlled
identifiers, or another coherent representation.

### 9.3 Invitation lifecycle normalization

Organization and Guardianship Invitations must represent, where applicable,
pending validity, acceptance, rejection, expiration, revocation, and otherwise
no-longer-valid semantics. Deployed Slices 3 and 5 represent those lifecycles
through immutable timestamps and related facts, with trusted operations and
integrity constraints deriving current validity.

## 10. Phase 1 Exclusions

Phase 1 excludes:

- multiple Credentials per Professional Profile;
- credential verification request/evidence/reviewer/outcome/history structures;
- global User Role, generic Actor, generic Principal, or permanent permission
  tables;
- unapproved Organization ownership-transfer, new-Owner, archival, or merge
  workflows;
- Guardianship termination, transfer, disagreement, differentiated roles,
  scheduled termination, or reactivation workflows;
- Clinic archival, transfer, closure, or operational-inactivity workflows;
- a Clinic-timezone-change user-facing/domain workflow;
- Guardian-selected/preferred-Veterinarian persistence without an approved
  workflow;
- multi-professional Appointment responsibility;
- multi-Encounter-per-Appointment behavior without an explicit approved source;
- unsupported reverse Encounter uniqueness constraints;
- replacement Care Authorization for one Appointment;
- generic Care Episode;
- Medical Access Decision table;
- persisted Entitlement decisions, assignments, continuity Entitlements, or
  paid-access booleans;
- emergency/break-glass behavior;
- numerical capacity, rooms, equipment, shifts, leave, payroll, or travel-time
  scheduling;
- specialized Treatment, Vaccination, Prescription, Laboratory Result, Imaging
  Result, or other unapproved clinical tables;
- immutable storage of every Draft edit, keystroke, or version;
- authoritative `most_recent_editor`;
- mandatory `prior_amendment_id` before chain representation is selected;
- mandatory cryptographic Attachment checksum;
- globally unique storage reference as a domain invariant;
- public Clinic media;
- public Veterinarian presentation/discovery;
- Discovery Result, map marker, distance, search, viewport, ranking, or
  persistent Visitor location/search-history tables;
- Phase 1 Discovery service/specialty filtering;
- Appointment availability as a Discovery prerequisite;
- User-managed communication preferences;
- Appointment Reminder entity or required relational Reminder Policy table;
- repeated reminder campaigns;
- marketing, SMS, WhatsApp, read receipts, acknowledgements, and notification
  inbox behavior;
- mandatory retry sequence, deduplication key, callback identifier, or fixed
  failure taxonomy;
- multiple Subscription plans, usage limits, Clinic/member quotas, or provider
  billing products as domain capabilities;
- legal retention, anonymization, audit-correction, or deletion-policy
  structures without approved rules;
- unapproved Proposal rejection, Guardian withdrawal, or expiration workflows
  (Clinic withdrawal is approved by SPEC-APT-016).

These exclusions do not prevent future extension after an approved Specification
introduces a workflow or relaxes a cardinality.

## 11. Conceptual Migration Dependency Order

This section records dependencies only; it is not a migration implementation.

1. **Identity foundation** — User, authentication linkage, User Profile.
2. **Professional identity** — Professional Profile and exactly one Credential
   in one coherent slice; Profile creation remains disabled until `1:1`
   integrity is enforceable.
3. **Organization foundation** — Organization, Invitations, intended
   responsibilities, Memberships, Responsibility Grants.
4. **Clinic foundation and professional context** — Clinic, Location, Public
   Profile, and Clinic Assignments referencing Membership periods.
5. **Pet and Guardianship** — Pet, Guardianship, Guardianship Invitation. The
   inviting Guardianship relationship exists from the Invitation's first
   schema.
6. **Clinic configuration and spatial support** — Services, Opening Hours,
   exceptions, Clinic timezone ownership, and spatial support on the one Clinic
   Location structure.
7. **Subscription and commercial history** — Subscription, Provider References,
   State Transitions, and derived current state under ADR-006.
8. **Scheduling configuration** — Clinic and Veterinarian availability plus
   exceptions, after Clinic timezone and Clinic Assignment paths exist.
9. **Appointment schema and schedule history** — Appointment, Lifecycle Events,
   Schedule Revisions, Proposals, and Appointment Assignments. New Appointment
   may have zero Lifecycle Events.
10. **Care Authorization** — granting Guardianship is mandatory from first
    introduction; optional Appointment FK follows Appointment schema. Request
    behavior remains disabled until Appointment, Schedule Revision, and exact-one
    Care Authorization results can be enforced atomically.
11. **Medical audit foundation** — after required User/process and relationship
    context can be represented. Audit-required behavior remains disabled until
    trusted durable fail-closed capture exists.
12. **Clinical care** — intake Care Authorization establishment, Encounter,
    Entry, contributor attribution, Amendment, structured protected-read
    outcomes under ADR-007; clinical resource-specific audit references may be
    added here.
13. **Clinical Attachments** — metadata, validation/integrity, private storage
    coordination, and Attachment-specific audit references.
14. **Communications** — logical Communication, Delivery Attempt, Push
    Registration, and durable handoff before communication-producing workflows
    are enabled.
15. **Discovery query support** — spatial indexes/query support and
    non-authoritative read projections over existing Clinic structures; no
    duplicate Location entity.

## 12. Genuinely Unresolved Architectural and Schema Questions

The following remain open for structures or workflows not yet physically
introduced and must not be silently resolved. Physical choices already recorded
by the source-controlled Slices 1–9 migrations are no longer open for those
implemented structures.

### Relationship and temporal enforcement

- Appointment-to-Clinical-Encounter reverse maximum;
- Care-Authorization-to-Clinical-Encounter reverse maximum;
- identifier generation and exact PostgreSQL types;
- enum versus check versus reference representation;
- timestamp versus range representation for temporal periods;
- temporal, exclusion, and one-active-relationship constraints;
- current-state pointers and projections;
- Row Level Security and trusted backend/function boundaries;
- locking, optimistic concurrency, advisory locking, and idempotency.

The unresolved reverse Encounter maxima permit neither reverse uniqueness nor an
approved multiple-Encounter workflow without a new explicit source.

### Clinical and audit normalization

- Amendment-chain physical representation;
- professional attribution normalization for creator, responsible professional,
  contributor, finalizer, amender, uploader, and concluding professional;
- contributor identity, duplicate prevention, and contributions under different
  Clinic Assignment periods;
- exact Draft-edit audit representation;
- clinical content representation;
- authorized-process audit identity and User/process exclusivity;
- audit correlation/session representation under ADR-005;
- protected-resource reference normalization;
- post-conclusion documentation enforcement;
- Attachment validation representation;
- Attachment integrity and storage coordination;
- Draft Attachment cleanup/removal representation.

### Subscription, Communications, and Discovery

- post-expiration reuse of a domain Subscription versus a new period;
- provider identifier formats and uniqueness;
- future provider-event inbox or integration-specific delivery representation;
- capability-policy representation and whether explicit versioning is required;
- Communication User versus non-User recipient normalization;
- delivery summary derivation/caching and retry/callback representation;
- Push Registration token normalization, rotation, invalidation, and
  reassociation;
- reminder configuration storage and scheduling;
- durable Communication handoff mechanism;
- Discovery spatial-index, distance, and viewport/radius query strategy over the established geographic Clinic Location representation;
- radius defaults/limits, pagination, result limits, and equal-distance technical
  ordering;
- legal retention, deletion, anonymization, and audit-retention policy.

Unspecified additional Organization descriptive fields are not an architectural
choice and must not be invented.

## 13. Traceability

The model is derived from the following approved source groups:

| Relational area | Requirements | Specifications / decisions |
| --- | --- | --- |
| Identity and authentication linkage | REQ-ID-001–008 | SPEC-ID-001–006 |
| Professional identity and Clinic Assignment | REQ-VET-001–005 | SPEC-VET-001, SPEC-VET-004/005 |
| Organizations and responsibilities | REQ-ORG-001–006 | SPEC-ORG-001–006 |
| Clinics and current configuration | REQ-CLI-001–005 | SPEC-CLI-001–006 |
| Pets and Guardianship | REQ-PET-001–006 | SPEC-PET-001–005; ADR-003 |
| Appointments and availability | REQ-APT-001–009 | SPEC-APT-001–020 |
| Care Authorization and audit | REQ-ACC-001–007; REQ-AUD-001–003 | SPEC-ACC-001–003; ADR-002/004/005/007 |
| Clinical care and Attachments | REQ-MED-001–013; REQ-FIL-001/003 | SPEC-MED-001–008; ADR-001; target: SPEC-MED-010, ADR-011 (§14) |
| Subscriptions and Entitlements | REQ-SUB-001–006 | SPEC-SUB-001–004 |
| Communications | REQ-COM-001–003 | SPEC-COM-001–003 |
| Public Discovery | REQ-DIS-001–004, REQ-DIS-006; REQ-NFR-006 | SPEC-DIS-001–004 |

Behavior marked Later remains outside this Phase 1 model even when a current
structure is deliberately extensible.

## 14. Target Revision: Appointment-Owned Clinical Documentation (ADR-011)

**Status:** `APPROVED` (2026-10-23) together with
[ADR-011](decisions/ADR-011-appointment-owned-clinical-documentation.md) and
[SPEC-MED-010](../specs/medical-records/SPEC-MED-010-document-appointment-clinical-record.md).
It replaces the clinical-care parts of §2–§9 as the transition stages are applied. The transition
procedure, inventory, and stages are in
[CLINICAL_DOCUMENTATION_TRANSITION.md](CLINICAL_DOCUMENTATION_TRANSITION.md).

### 14.1 Structure inventory

| Structure | Class | Responsibility |
| --- | --- | --- |
| `clinical_record_entries` | I | Clinical statement recorded once for exactly one Appointment: Appointment reference, authoring User, authoring concrete Veterinarian Clinic Assignment, recording time, category, clinical content, optional `OTHER` context, optional clinical event time, and the creation record (idempotency key unique per authoring User, request digest). No lifecycle state, Draft revision, modification time, or separate finalization facts. Never updated or deleted. |
| `clinical_amendments` | A/I | Unchanged: reason, content, amending User and Clinic Assignment, creation time, idempotency key, original Entry. |
| `clinical_attachments` | O until `AVAILABLE`, then I | Unchanged columns; parent is a recorded Entry. Only a non-`AVAILABLE` Attachment may be removed or expire. |
| `medical_access_audit_events` | A/I | Unchanged except that `clinical_encounter_id` no longer exists; typed clinical references are `appointment_id`, `clinical_record_entry_id`, and `clinical_amendment_id`. |
| `appointment_lifecycle_events` | A/I | Unchanged except that `clinical_encounter_id` and its shape rule no longer exist. |
| `care_authorizations` | T/I | Unchanged columns; the ending context set adds `APPOINTMENT_COMPLETED`. |
| `appointment_reschedule_proposals` | M → I | Unchanged columns; the void reason `CLINICAL_ENCOUNTER_STARTED` is renamed `CLINICAL_DOCUMENTATION_STARTED`. |
| `appointment_veterinarian_assignments` | T/I | Unchanged columns (Appointment, Veterinarian Clinic Assignment, start, optional end, assigning User; at most one current period per Appointment). It now designates the only Clinic Assignment allowed to record new Entries. Establishment also accepts a `COMPLETED` Appointment. |

Removed: `clinical_encounters`, `clinical_record_entry_contributors`.

### 14.2 Relationships and cardinalities

| Relationship | Cardinality | Rule |
| --- | --- | --- |
| Appointment → Clinical Record Entry | `1:0..N` | Every Entry has exactly one Appointment, immutable. |
| Entry → Pet, Clinic, Organization | derived | Through Appointment `pet_id`, `clinic_id` and Clinic `organization_id`, all immutable. Not stored on the Entry. |
| Entry → authoring Clinic Assignment | `N:1` | Belongs to the authoring User and to the Appointment's Clinic and Organization. |
| Entry → Amendment | `1:0..N` | Amending Clinic Assignment belongs to the amending User and to the Entry's Appointment's Clinic and Organization. |
| Entry → Attachment | `1:0..N` | Uploader Clinic Assignment as above. |
| Appointment → Care Authorization | `1:0..1` | Unchanged; governs prior-history access only. |
| Appointment → current Veterinarian Assignment | `1:0..1` current, `1:0..N` historical | Existing partial unique index on the current period. The assigned Clinic Assignment belongs to the Appointment's Clinic. |
| Entry → Veterinarian Assignment | derived | The authoring Clinic Assignment equals the Appointment's current assignment at recording; no reference is stored, the serialized insertion guarantees it. |
| Audit Event → Entry / Amendment | `N:0..1` | An Entry reference requires the event's Appointment to be the Entry's Appointment and its Pet the Appointment's Pet. |

### 14.3 Integrity invariants

- An Entry may be inserted only for an Appointment with exactly one
  `REQUESTED → CONFIRMED` Lifecycle Event whose current state is `CONFIRMED`
  or `COMPLETED`.
- Category is required and from the `SPEC-MED-006` taxonomy; content is
  trimmed and non-blank; `OTHER` context exists exactly with `OTHER`;
  timestamps are finite and not in the future; the recording time is the
  insertion statement time.
- Entries and Amendments are never updated or deleted; an `AVAILABLE`
  Attachment is never changed or removed.
- An Appointment with an Entry never becomes `CANCELLED` or `NO_SHOW` and
  receives no new Schedule Revision through rescheduling; the first Entry
  makes a pending Reschedule Proposal `VOID` with
  `CLINICAL_DOCUMENTATION_STARTED` in the same transaction.
- A `COMPLETED` Appointment has no `ACTIVE` Care Authorization; an `ENDED`
  authorization with `APPOINTMENT_COMPLETED` has `ended_at` equal to the
  completion Lifecycle Event's effective time.
- An Entry may be inserted only when the Appointment's current Veterinarian
  Assignment references the authoring Clinic Assignment and that Clinic
  Assignment is current.
- An Amendment's amending User and an Attachment's uploading User are the
  original Entry's `created_by_user_id`.
- A Veterinarian Assignment period may be established for a `CONFIRMED` or
  `COMPLETED` Appointment (and, through the trusted operation, `REQUESTED`);
  an ended period is always followed by a successor period starting at the
  same instant.

### 14.4 Derived, not stored

- Entry Pet, Clinic, and Organization provenance.
- `has_clinical_record` on schedule reads.
- Prior-history access and Appointment documentation access (two private
  predicates shared by reads and writes, `SPEC-MED-010` BR-11 and BR-14).
- History order `coalesce(clinical_event_at, recorded time)`.

### 14.5 Transaction and lock boundaries

Clinical writes lock, in order: Organization → Clinic → Membership / Grant /
Clinic Assignment → Appointment (share) → current Veterinarian Assignment
(read under the Appointment lock) → Entry → Attachments. Assignment,
reassignment, and self-assignment lock Organization → Clinic → (actor
context) → Appointment (update) → current Veterinarian Assignment → target
Clinic Assignment (share), so a save and a reassignment serialize. Cancellation,
`NO_SHOW`, completion, and rescheduling lock the Appointment for update, so a
first Entry and a non-attendance outcome serialize. Completion ends the Care
Authorization in its own transaction under the existing Appointment → Care
Authorization order. Prior-history reads share-lock the Care Authorization.

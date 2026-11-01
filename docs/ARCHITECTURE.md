# Architecture

**Status:** EVOLVING

This document describes the current high-level technical architecture of the
system.

Architecture evolves from the approved domain Specifications and the technical
decisions recorded in [`decisions/`](decisions/) and the initial technical
direction described in [PROJECT.md](PROJECT.md).

This document describes the resulting system structure.

Detailed architectural decisions, alternatives, and trade-offs should be
recorded as Architecture Decision Records rather than duplicated here.

---

## 1. Architectural Principles

The architecture should preserve the following principles.

### Domain-first design

Technical structures should follow the approved domain model and
Specifications rather than forcing domain concepts into infrastructure-specific
representations.

### Explicit authorization

Authentication, Organization responsibility, professional context,
Guardianship, and medical access are distinct concepts.

Infrastructure-level authorization must preserve the access rules defined by
the domain Specifications.

### Historical integrity

Historical clinical and professional provenance must not depend on mutable
current relationships.

Changes in employment, Clinic publication, subscriptions, or Guardianship must
not silently rewrite historical domain information.

### Provider-independent domain identity

Core domain identities such as Pet and Veterinarian must remain independent
from individual Clinics or Veterinary Organizations.

### Infrastructure isolation

Domain concepts should not depend directly on specific infrastructure
providers where avoidable.

External services and storage providers should be accessed through clear
technical boundaries so they may evolve without redefining the domain model.

### Least privilege

Sensitive operations and protected medical information must be accessible only
through the minimum authorization required by the applicable business context.

### Authorization enforcement

Authorization-sensitive domain operations must be enforced through trusted
server-side and data-access boundaries.

The mobile application may hide or disable unavailable operations for user
experience purposes, but client-side behavior is not the security boundary.

A manipulated, outdated, or alternative client must not be able to bypass:

- Organization capabilities;
- Clinic context;
- Guardianship;
- professional authorization;
- Subscription Entitlements;
- Medical Access Control.

Database-level policies and trusted backend operations should be used where
appropriate to enforce these constraints.

---

## 2. High-Level System Structure

The system currently consists conceptually of the following major components:

    Mobile Application (Guardian and professional contexts)
            │
            ▼
    Application / Backend Services
            │
            ├── Authentication
            ├── Domain operations
            ├── Authorization
            ├── Database
            ├── Object storage
            └── External service integrations

    Trusted commercial-onboarding operations
    (service context, not reachable by client applications)
            │
            ▼
    Application / Backend Services

The architecture will evolve as Specifications introduce additional required
behavior.

---

## 3. Mobile Application

The client application is planned as a React Native application written in
TypeScript.

The mobile application is responsible for:

- user interaction;
- navigation;
- authenticated session handling;
- presentation of domain information;
- initiating authorized domain operations;
- interacting with external device capabilities where required.

Business rules that protect domain integrity or sensitive information must not
rely solely on client-side enforcement.

The same application presents Guardian and professional contexts. There is no
stored professional User flag: professional context is obtained from a trusted
backend read derived from current domain relationships and Entitlements, and
it is used only for presentation. Every operation re-evaluates authorization
and Entitlement server-side.

See
[ADR-010 — Single Mobile Application with Derived Professional Context](decisions/ADR-010-single-mobile-app-with-derived-professional-context.md).

---

## 4. Backend Platform

Supabase is the current backend platform direction.

The expected backend capabilities include:

- PostgreSQL for relational domain persistence;
- Supabase Auth for authentication;
- Row Level Security where appropriate;
- Edge Functions for trusted server-side operations where required;
- private object storage for protected binary content.

The exact mapping of domain operations to database functions, Edge Functions,
Row Level Security policies, or other backend mechanisms will be defined as
implementation architecture evolves.

Domain Specifications remain authoritative over infrastructure convenience.

---

## 5. Relational Persistence

PostgreSQL is the primary relational persistence layer.

Relational data is expected to represent domain concepts such as:

- Users and domain profiles;
- Pets and Guardianships;
- Veterinary Organizations;
- Organization Memberships;
- Clinics;
- Veterinarian Professional Profiles;
- Clinic Assignments;
- Appointments;
- Care Authorizations;
- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachment metadata.

The final database schema must be derived from the approved Specifications and
domain invariants rather than directly from UI requirements.

The approved detailed Phase 1 relational-design baseline is recorded in
[RELATIONAL_MODEL.md](RELATIONAL_MODEL.md). Physical schema and migration design
must preserve its identity, relationship, cardinality, temporal, provenance,
authorization, and derived-state boundaries. Questions that document leaves
open remain architectural choices and must not be silently resolved here.

---

## 6. Data Integrity

Critical domain integrity must be enforced at the strongest appropriate
trusted boundary.

The architecture may use complementary mechanisms such as:

- relational foreign keys;
- uniqueness constraints;
- check constraints;
- transactional operations;
- database authorization policies;
- trusted domain validation.

Client-side validation may improve user experience but must not be the sole
protection against invalid persistent domain state.

Database constraints should be preferred where a rule can be expressed safely
and accurately at the relational level.

More complex lifecycle or authorization rules may require trusted domain
operations in addition to database constraints.

The persistence model must protect against invalid states such as:

- broken required relationships;
- unintended duplicate active relationships;
- contradictory current domain state;
- partial multi-step domain operations.

Integrity enforcement must preserve historical information required by the
approved Specifications.

---

## 7. Authentication and Authorization

Authentication and domain authorization are separate concerns.

Authentication establishes the User identity.

Domain authorization determines what that User may do in a particular context.

Examples include:

    authenticated User
            +
    active Guardianship
            ↓
    Guardian capability for a Pet

and:

    authenticated User
            +
    Organization Membership
            +
    responsibility-derived capability
            +
    Clinic context
            ↓
    professional operational capability

and:

    valid Care Authorization
            +
    valid professional context
            +
    least-privilege rules
            ↓
    permitted medical access

Authorization rules must be enforced in trusted backend infrastructure.

Client-side checks may improve user experience but must not constitute the
security boundary.

Veterinary Organization establishment and its initial Subscription
establishment are trusted service-context operations. They must not be
executable by authenticated client roles.

---

## 8. Clinical File Storage

Clinical binary content is stored separately from relational medical metadata.

Clinical Attachment metadata and domain relationships remain in PostgreSQL.

Binary file content is stored in private object storage.

The initial storage implementation uses Supabase Storage.

Permanent public access to protected clinical files is not permitted.

See:

- [ADR-001 — Store Clinical Attachments in Private Object Storage](decisions/ADR-001-clinical-attachment-storage.md)

---

## 9. External Services

External providers may be introduced for capabilities such as:

- subscription management;
- transactional email;
- maps and geospatial presentation;
- mobile application distribution;
- monitoring and observability.

An external service should not become part of the core domain model merely
because it provides the initial implementation of a capability.

Significant provider choices should be recorded through ADRs when the decision
has meaningful architectural consequences.

---

## 10. Security

Sensitive veterinary medical information must be treated as protected data.

The architecture must support:

- explicit authentication;
- least-privilege authorization;
- private clinical file storage;
- protected cross-clinic medical access;
- access revocation;
- preservation of medical provenance;
- appropriate auditability;
- server-side enforcement of sensitive domain operations.

Specific security mechanisms will be refined as the relevant Specifications
and implementation design are developed.

---

### Medical access auditing

Protected medical access is audited at the meaningful domain-operation level
rather than by treating every low-level database or infrastructure operation as
a Medical Access Audit Event.

Technical, application, and infrastructure logging remain separate concerns.

See:

- [ADR-002 — Use Domain-Level Medical Access Auditing](decisions/ADR-002-domain-level-medical-access-auditing.md)
- [ADR-007 — Structured Protected-Read Outcomes for Durable Denial Auditing](decisions/ADR-007-structured-protected-read-outcomes.md)

Protected medical PostgreSQL reads return structured `PERMITTED` or `DENIED`
domain outcomes. Normal denial commits its required audit evidence without
returning protected payload; infrastructure or required audit-persistence
failure aborts and returns no protected information.

---

## 11. Architecture Decision Records

Significant technical decisions are recorded in [`decisions/`](decisions/).

Current decisions:

| ADR | Decision | Status |
| --- | --- | --- |
| [ADR-001](decisions/ADR-001-clinical-attachment-storage.md) | Store Clinical Attachments in Private Object Storage | ACCEPTED |
| [ADR-002](decisions/ADR-002-domain-level-medical-access-auditing.md) | Use Domain-Level Medical Access Auditing | ACCEPTED |
| [ADR-003](decisions/ADR-003-temporal-guardianship-foundation.md) | Model Guardianship as a Temporal-Capable Relationship | ACCEPTED |
| [ADR-004](decisions/ADR-004-fail-closed-required-medical-auditing.md) | Fail Closed When Required Medical Audit Cannot Be Durably Captured | ACCEPTED |
| [ADR-005](decisions/ADR-005-context-dependent-medical-audit-correlation.md) | Use Context-Dependent Medical Audit Correlation | ACCEPTED |
| [ADR-006](decisions/ADR-006-derived-provider-independent-subscription-state.md) | Derive Current Subscription State from Initial Facts and Append-Only Transitions | ACCEPTED |
| [ADR-007](decisions/ADR-007-structured-protected-read-outcomes.md) | Structured Protected-Read Outcomes for Durable Denial Auditing | ACCEPTED |
| [ADR-008](decisions/ADR-008-durable-session-safe-communications-handoff.md) | Durable and Session-Safe Communications Handoff | ACCEPTED |
| [ADR-009](decisions/ADR-009-trusted-commercial-onboarding-establishes-organizations.md) | Trusted Commercial Onboarding Establishes Veterinary Organizations | ACCEPTED |
| [ADR-010](decisions/ADR-010-single-mobile-app-with-derived-professional-context.md) | Single Mobile Application with Derived Professional Context | ACCEPTED |


This document should reflect accepted architectural decisions but should not
duplicate their full rationale.

---

## 12. Evolution

This architecture is intentionally incomplete.

New components, boundaries, persistence strategies, and integrations should be
introduced when approved Specifications establish a concrete need for them.

Architecture should evolve through:

    Requirements
        ↓
    Specifications
        ↓
    Domain model
        ↓
    Architectural decisions
        ↓
    Implementation

The system should avoid introducing infrastructure complexity before the
domain behavior requiring that complexity has been established.

---

## 13. Geographic Querying

Clinic proximity search must be performed through a server-side geographic
query strategy.

The mobile application must not require downloading all Clinic locations in
order to calculate nearby Clinics locally.

The geographic persistence and query model must support:

- Clinic location coordinates;
- proximity filtering;
- bounded search results;
- future distance-based ordering where required.

The initial implementation should use PostgreSQL-compatible geographic
capabilities appropriate to the selected Supabase architecture.

The exact geographic extension, indexing strategy, and distance-query
implementation will be recorded as an architectural decision if the choice has
meaningful long-term consequences.

See:

- SPEC-DIS-002

---

## 14. Environment Separation

Development and production must operate as separated environments.

Production data, privileged credentials, and backend resources must not be
treated as interchangeable with development resources.

At minimum, environment separation must allow independent management of:

- database state;
- authentication configuration;
- object storage;
- privileged secrets;
- external integration credentials;
- deployment configuration.

Testing or staging environments may be introduced when integration or release
workflows require them.

Environment-specific configuration must not redefine domain behavior.

The exact Supabase project and deployment topology will be defined when the
deployment architecture is introduced.

---

## 15. Observability

Critical backend workflows must provide sufficient diagnostic information to
investigate failures without relying solely on client-side reports.

Observability should support investigation of workflows such as:

- authentication and account recovery failures;
- Appointment lifecycle failures;
- scheduling and availability conflicts;
- clinical attachment storage failures;
- Subscription synchronization failures;
- transactional communication failures;
- Medical Access Audit persistence failures;
- trusted backend operation failures.

Technical observability is distinct from domain auditability.

Conceptually:

    domain audit
    → who performed a meaningful sensitive action and under what context

    technical observability
    → why a system operation succeeded, failed, or behaved unexpectedly

Logs and diagnostics must avoid unnecessarily recording:

- authentication secrets;
- recovery tokens;
- privileged service credentials;
- protected clinical payloads;
- complete sensitive message bodies.

The exact logging, tracing, error-reporting, and monitoring providers will be
selected during implementation architecture.

---

## 16. Time and Scheduling

Clinic scheduling uses an explicit named timezone.

Each Clinic participating in Appointment scheduling has one current scheduling
timezone.

Concrete Appointment scheduling contexts must preserve both:

- the actual time interval required for ordering, concurrency, and conflict
  evaluation;
- the named Clinic timezone required to preserve the civil-time context in
  which the Appointment was scheduled.

Recurring Clinic and Veterinarian availability is expressed in local Clinic
time and interpreted through the Clinic's named timezone.

Cross-Clinic scheduling conflicts must be evaluated using resolved actual time
intervals rather than local clock values.

A later Clinic timezone change must not silently reinterpret historical
Appointment scheduling contexts.

Timezone, daylight-saving, ambiguous-time, and nonexistent-time handling must
be enforced through trusted backend scheduling logic rather than relying on the
client device timezone.

---

## 17. Guardianship Persistence

Guardianship is represented as a temporal-capable relationship between a User
and a Pet.

Current Guardian capability is derived from a currently active Guardianship
period rather than from permanent User ownership or a `Pet.owner_user_id`
relationship.

The persistence model must support an effective start and an optional effective
end so that current and historical Guardianship can remain distinguishable.

Phase 1 does not expose a Guardianship-termination workflow merely because the
persistence model supports a historical end boundary.

An ended Guardianship must not regain current capability through reactivation.
Future approved rejoining behavior should establish a new Guardianship period.

See:

- [ADR-003 — Model Guardianship as a Temporal-Capable Relationship](decisions/ADR-003-temporal-guardianship-foundation.md)

---

## 18. Communications Handoff and Delivery

Supported Invitation and Appointment operations establish a typed Transactional
Communication in the same PostgreSQL transaction as the authoritative origin.
Asynchronous Edge dispatch uses non-authoritative Delivery Jobs for leases and
retry while appending an immutable Delivery Attempt for each provider call.
Provider responses and callbacks remain technical delivery
facts and cannot modify Invitation, Appointment, Guardianship, Membership, or
medical state.

Private Push Registrations are bound to both domain User and concrete Supabase
Auth session. Every dispatch eligibility check requires that session to remain
present for the linked Auth subject. A client registration or token is not
authentication, authorization, or User identity.

Invitation creation uses trusted replacement commands. A versioned AES-256-GCM
envelope carries the one-time credential across the durable boundary without
plaintext persistence. Encryption keys, provider credentials, commercial
plans, and provider selection remain deployment concerns.

See:

- [ADR-008 — Durable and Session-Safe Communications Handoff](decisions/ADR-008-durable-session-safe-communications-handoff.md)
- [Communications Backend Operations](COMMUNICATIONS_BACKEND.md)

---

## 19. Professional Context and Commercial Onboarding

A Veterinary Organization is established only through trusted Commercial
Onboarding. That service-context operation establishes, atomically, the
Organization, the initial Owner Membership and Owner responsibility for an
existing verified User, and the Organization's initial Subscription in the
state determined by the commercial process. Establishment is idempotent under
retry. Authenticated client roles cannot establish Organizations.

Current implementation (migration `20261101090000`; in DEVELOPMENT, not yet
in Production): the
`service_role`-only `establish_veterinary_organization` operation
(`SPEC-ORG-001` §10) is that boundary. It receives the designated Owner's
domain User id (never an Auth subject or email), checks Owner account
eligibility itself, and is idempotent through an Organization-level
establishment key shared with the initial Subscription. The earlier
`create_veterinary_organization` is removed; no Owner session impersonation is
involved. Operators follow `docs/SUBSCRIPTION_OPERATIONS_RUNBOOK.md` §3.1. The
guarantee that every Organization has an initial Subscription is prospective;
legacy Organizations are inventoried, not reconciled.

Creating Clinics within an established Organization is not Commercial
Onboarding: it is operational self-service authorized by
`ORGANIZATION_CREATE_CLINICS` (`SPEC-CLI-001` §10).

A User may request Commercial Onboarding from the mobile application through an
external, web, or contact surface. Phase 1 does not persist onboarding requests
as a domain concept.

Once established, an Organization continues to exist whatever its later
commercial state. Paid professional operations remain gated by current
Entitlements derived from Subscription state; invited Members act under their
Organization's Entitlements and never hold their own Subscription.

Subscription state changes are trusted, manual Phase 1 operator operations
(`docs/SUBSCRIPTION_OPERATIONS_RUNBOOK.md`): an approved transition graph,
no future-dated transitions, `EXPIRED` terminal, and an open-ended `ACTIVE` as
the ordinary manual customer state. Organization management with
`ORGANIZATION_MANAGE_SUBSCRIPTION` reads the current state and Entitlement
availability through a dedicated status read (`SPEC-SUB-002` §15); Guardians
and public reads never receive commercial information.

The single mobile application derives each User's professional context from a
trusted read of current Memberships, Responsibility Grants, Professional
Profile, Clinic Assignments, and Organization Entitlements. That context is
advisory presentation information, never an authorization decision, and is not
persisted as a User flag.

See:

- [ADR-009 — Trusted Commercial Onboarding Establishes Veterinary Organizations](decisions/ADR-009-trusted-commercial-onboarding-establishes-organizations.md)
- [ADR-010 — Single Mobile Application with Derived Professional Context](decisions/ADR-010-single-mobile-app-with-derived-professional-context.md)

---

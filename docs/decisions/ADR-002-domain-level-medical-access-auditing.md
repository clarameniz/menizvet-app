# ADR-002 — Use Domain-Level Medical Access Auditing

**Status:** ACCEPTED

## Context

The system handles protected veterinary medical information and must support
meaningful auditability of sensitive medical access.

A single user-facing medical-access operation may result in multiple technical
operations, such as:

- authorization checks;
- database queries;
- pagination requests;
- storage requests;
- backend function calls;
- application retries.

Recording every technical operation as a permanent Medical Access Audit Event
would produce large amounts of low-value audit data and make meaningful
security analysis more difficult.

At the same time, relying only on infrastructure or application logs would not
provide the domain context required to understand why protected medical
information was accessed.

The system therefore needs to distinguish domain-level medical access auditing
from technical logging.

## Decision

Medical Access Audit Events will represent meaningful domain-level access to
protected medical information.

Examples include:

- viewing a Pet's longitudinal medical history;
- accessing medical information for Appointment triage;
- accessing cross-clinic medical history;
- accessing protected medical information during veterinary care;
- opening a protected Clinical Attachment;
- security-relevant denied medical-access attempts.

The system will not create permanent domain Medical Access Audit Events solely
for low-level implementation activity such as:

- individual SQL queries;
- React component rendering;
- internal authorization queries;
- routine pagination mechanics;
- database connection activity;
- storage metadata lookups;
- infrastructure health checks.

Technical logging and security infrastructure may still record those
operations separately where required.

## Domain and Technical Audit Separation

The architecture distinguishes:

    Medical Access Audit Events
    → meaningful domain accountability

from:

    application logs
    → operational diagnostics

and:

    infrastructure / security logs
    → technical and security observability

These mechanisms may correlate with each other but must not be treated as the
same data model.

## Access Outcomes

The medical audit model may record both:

- permitted access;
- security-relevant denied access.

Routine malformed or unauthenticated technical requests do not necessarily
become permanent domain Medical Access Audit Events.

The exact security logging policy for those requests is independent from the
medical audit domain.

## Trusted Boundary

Required Medical Access Audit Events must be generated or established through
trusted backend infrastructure.

The client application must not be the authoritative source of audit events.

## Correlation

Several technical requests may represent one meaningful domain access context.

For example, loading several pages of Luna's longitudinal history may be
correlated as one logical medical-history access session where doing so
preserves the required accountability.

The exact correlation mechanism will be defined during implementation.

## Failure Behavior

Required audit events must not be silently lost.

The architecture must explicitly define the behavior of protected operations
when required audit persistence is unavailable.

High-value medical-access operations may require fail-closed behavior.

The exact policy may vary by operation and will be refined during
implementation.

## Consequences

### Positive

- audit history remains meaningful to humans;
- security investigations are not overwhelmed by low-level technical noise;
- domain authorization context can be preserved;
- audit storage requirements remain manageable;
- implementation details may evolve without changing the semantic audit model.

### Negative

- the architecture must define what constitutes one meaningful access event;
- some operations may require correlation across several technical requests;
- technical logs remain necessary alongside domain audit information;
- careful implementation is required to avoid missing meaningful access.

## Alternatives Considered

### Audit every database or storage read

Rejected because low-level implementation activity does not map cleanly to
meaningful medical-access events and would generate excessive audit noise.

### Use infrastructure logs only

Rejected because infrastructure logs generally lack sufficient domain context
to explain:

- which Pet was involved;
- which Care Authorization applied;
- which Clinic context was used;
- why the access was permitted or denied.

### Client-generated medical audit events

Rejected because the client is not a trusted security boundary and required
audit events could be omitted or manipulated.

## Related Specifications

- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-ACC-003 — Record Medical Access Audit Event
- SPEC-MED-005 — View Pet Medical History
- SPEC-MED-007 — Add Clinical Attachment
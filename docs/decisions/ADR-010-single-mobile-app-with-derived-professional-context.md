# ADR-010 — Single Mobile Application with Derived Professional Context

**Status:** ACCEPTED

## Context

The domain already models Guardian, Veterinarian, Organization Member, and
Administrator as relationship-derived contexts rather than mutually exclusive
User types (DOMAIN §2.1, INV-001, REQ-ID-005). The same person may be a
Guardian and a professional at the same time.

Phase 1 had delivered only a Guardian-facing mobile application. Professional
operations existed in the backend but had no client. A Phase 1 client
architecture for professional contexts was therefore needed, and it had to
decide how the client knows which professional functionality a User may use.

## Decision

### One application for Guardian and professional contexts

MenizVet Phase 1 uses the same mobile application for Guardian and
professional contexts. There is no separate professional account type or
professional application.

### Professional context is derived, never stored

There is no stored `isProfessional` or equivalent User flag. A User's
professional context is derived at read time from:

- active Organization Memberships;
- active Organization Responsibility Grants and the capabilities they provide;
- a Veterinarian Professional Profile, where applicable;
- current Veterinarian Clinic Assignments, where applicable;
- the Organization's current Entitlements, for paid operations.

A User may remain a Guardian while also holding professional context.

### Context is read through a trusted backend surface

The client obtains professional context through a trusted, self-scoped backend
read defined by SPEC-ORG-007, following the established pattern of trusted
server-side operations rather than direct client table reads.

### Context is advisory

The client uses professional context only for presentation. Every professional
operation re-evaluates Membership, responsibility, Clinic Assignment, Medical
Access, and Entitlement server-side. A stale or manipulated client-side copy
authorizes nothing.

## Consequences

### Positive

- Matches the existing relationship-based domain model with no new persisted
  role concept.
- One installation, one identity, and one session serve both contexts.
- The backend remains the only security boundary.

### Negative

- A new approved read Specification and backend read operation are required
  before the client can present professional functionality.
- The mobile application must handle mixed and changing contexts, including a
  User gaining or losing professional context while signed in.

## Alternatives Considered

### Separate professional mobile application

Rejected for Phase 1. It would duplicate identity, session, and distribution
concerns without a domain need.

### Web back-office for professionals

Deferred. Web administration remains a possible future evolution
(PROJECT §10) and is compatible with this decision.

### Stored professional User flag or role

Rejected. It would contradict relationship-derived authorization and could
diverge from current Memberships, Assignments, and Entitlements.

## Related Documentation

- [SPEC-ORG-007 — View My Professional Context](../../specs/organizations/SPEC-ORG-007-view-my-professional-context.md)
- [SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities](../../specs/organizations/SPEC-ORG-005-evaluate-organization-responsibilities-and-capabilities.md)
- [SPEC-SUB-003 — Evaluate Professional Entitlements](../../specs/subscriptions/SPEC-SUB-003-evaluate-professional-entitlements.md)
- [ADR-009 — Trusted Commercial Onboarding Establishes Veterinary Organizations](ADR-009-trusted-commercial-onboarding-establishes-organizations.md)
- REQ-ID-005, REQ-ORG-008

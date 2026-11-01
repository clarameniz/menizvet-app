# ADR-009 — Trusted Commercial Onboarding Establishes Veterinary Organizations

**Status:** ACCEPTED

## Context

A Veterinary Organization is the platform's commercial SaaS customer. Paid
professional operations are already gated by Organization Entitlements derived
from trusted Subscription state (SPEC-SUB-003, ADR-006).

The previously approved SPEC-ORG-001 allowed any authenticated, verified User
to create a Veterinary Organization directly, and the implemented
`create_veterinary_organization` operation is executable by authenticated
Users. Such an Organization held no Subscription and therefore no paid
Entitlement, but its Owner could still configure and publish Clinics into
anonymous public Discovery (SPEC-SUB-003 BR-42).

MenizVet Phase 1 now exposes professional functionality in the same mobile
application used by Guardians (ADR-010). Open self-service Organization
creation from that application would let any verified User create commercially
unvetted Organizations and publish Clinics that cannot be booked, without any
commercial relationship.

The product decision is that becoming a customer is a commercial act: initial
Organization establishment must happen only through a trusted commercial
process, which also establishes the Organization's commercial relationship.

## Decision

### Establishment is a trusted service-context operation

A Veterinary Organization is established only through trusted Commercial
Onboarding. Authenticated client roles cannot establish Organizations.
Authentication, email verification, professional identity, Guardianship, or
responsibility in another Organization never suffice. No Organization
responsibility or capability authorizes establishing another Organization.

### Establishment is atomic with ownership and the initial Subscription

Commercial Onboarding establishes, in one atomic operation:

- the Veterinary Organization;
- the initial Owner Membership and active Organization-scoped `OWNER`
  responsibility for a designated initial Owner, who must already be an
  existing, verified User;
- the Organization's initial Subscription, in the initial state determined by
  the commercial process (for example `PENDING` or `ACTIVE`).

Every Organization is established with an initial Subscription. An Organization
is never established without it.

### Establishment is idempotent

Retrying Commercial Onboarding for the same commercial onboarding must not
establish a second Organization, Membership, Owner responsibility, or
Subscription, and must allow the already completed result to be recognized
safely.

### Establishment operation contract (amendment — Trusted Organization Establishment Hardening)

The trusted establishment boundary is one service-context database operation,
`establish_veterinary_organization`, executable only by `service_role` (no
`public`, `anon` or `authenticated` EXECUTE). Its full contract is
`SPEC-ORG-001` §10; the architectural decisions are:

- **Initial Owner identifier.** The operation receives the designated Owner's
  domain User id (`users.id`). It never receives, and never resolves, an Auth
  subject, a JWT subject or an email address. Operator or service tooling may
  resolve a person to that domain User in a read-only preflight outside the
  operation. The operation itself verifies the domain User → Auth mapping and
  the Owner account eligibility of `SPEC-ORG-001` BR-16. No session
  impersonation of the Owner is involved.
- **Idempotency anchor.** One caller-generated UUID,
  `establishment_idempotency_key`, is stored on the Organization
  (`veterinary_organizations.establishment_idempotency_key`, nullable for
  Organizations established before this amendment, unique when present,
  immutable) and is also the initial Subscription's
  `establishment_idempotency_key`. The Organization key is the recovery anchor
  for the whole establishment: the already established Organization, initial
  Owner Membership and initial Subscription are recovered from it. Display
  name, Owner + display name, email, provider references, timestamps and
  generated ids are never anchors. A future billing or backoffice service may
  derive the UUID deterministically from its own event or reference outside the
  database; the operation stays provider-neutral.
- **Replay fingerprint over requested inputs.** Exact replay compares the
  requested inputs, never resolved defaults (the establishment instant, a
  defaulted initial effective time, generated ids). The Organization durably
  records an immutable digest of its canonical requested inputs
  (`establishment_request_digest`) next to the key. Same key with the same
  requested inputs returns the original result; same key with any materially
  different requested input is rejected deterministically.
- **Atomicity and serialization.** One function, one transaction, one
  establishment instant `t = statement_timestamp()`. Identical concurrent calls
  serialize on the unique Organization key (insert-on-conflict, then re-read of
  the committed Organization); no advisory lock is used. The relevant deferred
  Organization, Membership, Grant and Subscription invariants are surfaced
  inside the operation before it reports success.
- **Former boundary removed.** `create_veterinary_organization`, which derived
  the Owner from the caller's authenticated subject and established no
  Subscription, is removed. `establish_organization_subscription` remains a
  `service_role` operation for a later Subscription period (after `EXPIRED`); it
  is no longer part of initial Organization establishment.
- **Prospective guarantee only.** Every Organization established through this
  operation has its initial Subscription. No structural Organization →
  Subscription invariant is added yet: legacy Organizations remain
  unreconciled (below) and `SPEC-SUB-002` §15 still models an Organization that
  never had a Subscription.

### Establishment grants no Entitlement by itself

Paid professional capability continues to derive only from Subscription state
through SPEC-SUB-003. An Organization established with a `PENDING` Subscription
has no normal paid professional Entitlement. The existing Entitlement model is
unchanged.

### Post-establishment commercial state does not end the Organization

Once established, an Organization continues to exist whatever its later
commercial state, including when it later has no current Subscription. Loss of
Entitlement or Subscription never deletes or rewrites Organization, Clinic,
Membership, Appointment, clinical, or audit information (SPEC-SUB-002,
SPEC-SUB-004).

### Requests are not domain state in Phase 1

A User may request Commercial Onboarding from the mobile application through
an external, web, or contact surface. Phase 1 does not persist onboarding
requests as a domain concept; a request establishes nothing.

### Invited Members are outside Commercial Onboarding

Users joining an existing Organization through an Organization Invitation do
not go through Commercial Onboarding and never hold their own Subscription.
They act under the Organization's current Entitlements, governed by their
Membership, responsibility, Clinic Assignment, and Medical Access
authorization (SPEC-ORG-003, SPEC-SUB-001 BR-31).

## Consequences

### Positive

- Only commercially onboarded Organizations can configure and publish Clinics,
  which removes the unvetted-Organization path into public Discovery without
  changing Clinic publication semantics.
- Every Organization has a coherent commercial history from establishment.
- The trusted onboarding boundary can later be automated by billing
  integration without changing domain identity or Entitlement semantics.
- Invited employees join without any commercial step.

### Negative

- A backend change is required: the existing authenticated
  `create_veterinary_organization` operation conflicts with this decision and
  must be withdrawn from client roles in favor of a trusted service-context
  operation.
- Phase 1 onboarding depends on a manual or external operator process and an
  operator runbook.
- Existing provisioning and test fixtures that create Organizations as an
  authenticated User must be updated.

### Legacy Organizations (implementation and migration consequence)

Organizations created before this decision, through the previous
authenticated creation operation, may not satisfy the new establishment
invariant that every Organization is established with an initial
Subscription.

Before the new invariant is enforced for existing data, those Organizations
must be inventoried. If any legacy Organization never had a Subscription,
implementation must not silently fabricate historical commercial facts, such
as a backdated initial Subscription, to make it conform. The migration or
reconciliation strategy for such Organizations must be explicitly decided and
documented before implementation.

This consequence concerns only pre-existing data. It does not weaken the rule
for any future Organization establishment, which always includes the initial
Subscription.

## Alternatives Considered

### Keep open self-service Organization creation

Rejected. Any verified User could create unvetted Organizations and publish
non-bookable Clinics into anonymous Discovery.

### Self-service creation without Entitlement plus a publication gate

Rejected. It would require changing Clinic publication semantics
(SPEC-SUB-003 BR-42, SPEC-CLI-003) and would still create customer entities
without any commercial relationship.

### Establish the Subscription in a separate later step

Rejected. It would permit Organizations established without their initial
Subscription and split one commercial act across two trust boundaries.

### Persist onboarding requests in the domain

Deferred. Phase 1 has no approved behavior requiring it. It may be specified
later if needed.

## Intentionally Unresolved or Later

- ~~The exact idempotency mechanism for establishment.~~ Decided by the
  amendment above (Organization-level key, shared with the initial
  Subscription, plus a requested-input digest). The Subscription key alone was
  not chosen as the anchor because its key space is shared with later
  Subscription periods and it cannot distinguish a requested from a defaulted
  initial effective time.
- A structural Organization → Subscription invariant, after legacy inventory,
  reconciliation and resolution of the `SPEC-SUB-002` §15 no-Subscription
  state.
- Billing-provider integration, payment UI, and automated activation.
- Persisted onboarding requests and commercial approval criteria.

## Related Documentation

- [SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding](../../specs/organizations/SPEC-ORG-001-establish-veterinary-organization-through-commercial-onboarding.md)
- [SPEC-SUB-001 — Establish Organization Subscription](../../specs/subscriptions/SPEC-SUB-001-establish-organization-subscription.md)
- [SPEC-SUB-003 — Evaluate Professional Entitlements](../../specs/subscriptions/SPEC-SUB-003-evaluate-professional-entitlements.md)
- [ADR-006 — Derive Current Subscription State from Initial Facts and Append-Only Transitions](ADR-006-derived-provider-independent-subscription-state.md)
- [ADR-010 — Single Mobile Application with Derived Professional Context](ADR-010-single-mobile-app-with-derived-professional-context.md)
- REQ-ORG-001, REQ-SUB-001, REQ-SUB-002, REQ-SUB-003

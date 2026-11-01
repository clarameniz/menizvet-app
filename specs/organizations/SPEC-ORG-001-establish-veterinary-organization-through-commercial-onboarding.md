# SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding

**Status:** APPROVED
**Requirements:** REQ-ORG-001, REQ-ORG-002, REQ-ORG-003, REQ-ORG-004, REQ-ORG-005, REQ-SUB-001, REQ-SUB-002
**Domain:** Organizations
**Priority:** P0

> **Revision (2026-09-30).** This Specification previously allowed any
> authenticated and verified User to create a Veterinary Organization directly
> ("Create Veterinary Organization"). By Phase 1 product decision, initial
> Organization establishment is no longer open self-service: it is performed
> only through trusted Commercial Onboarding, which also establishes the
> Organization's initial Subscription. The Specification identifier is
> unchanged. See
> [ADR-009](../../docs/decisions/ADR-009-trusted-commercial-onboarding-establishes-organizations.md).

## 1. Intent

Establish a Veterinary Organization as a platform customer through a trusted
Commercial Onboarding process.

Establishment creates the Organization as a distinct business entity,
establishes the professional relationship between the Organization and its
designated initial Owner, and establishes the Organization's initial
Subscription.

The designated initial Owner is an existing, verified User identified by the
onboarding process. That User becomes the initial Organization Owner.

Initial Organization establishment is not open self-service. An authenticated
User cannot establish a Veterinary Organization directly from a client
application.

---

## 2. Preconditions

* The operation is performed by the trusted Commercial Onboarding process.
* The designated initial Owner is an existing User.
* The designated initial Owner satisfies the account eligibility requirements
  for initial Organization ownership (BR-16).
* The submitted Organization information satisfies the requirements necessary
  to establish the Organization.
* The initial Subscription information required by SPEC-SUB-001 is available
  from the trusted commercial process.

---

## 3. Business Rules

### BR-1 — Organization is a distinct domain entity

Establishing a Veterinary Organization must create an Organization that exists independently from the User designated as its initial Owner.

The Organization must not be modeled as part of that User's profile.

---

### BR-2 — Organization establishment establishes initial ownership

A successfully established Organization must establish an Organization Membership between the designated initial Owner and the new Organization.

That Membership must grant the designated initial Owner the Organization Owner responsibility.

---

### BR-3 — Initial Membership starts with Organization establishment

The designated initial Owner's Organization Membership must become active as part of the Organization establishment.

Its effective start must correspond to the establishment of that professional relationship.

---

### BR-4 — Initial Membership has no end at establishment

The designated initial Owner's Organization Membership must be active when the Organization is established.

It must not have an effective end unless a later domain operation explicitly ends or changes the relationship.

---

### BR-5 — Organization establishment is atomic

The system must not leave an established Organization without its initial
Owner Membership, its active Owner responsibility, or its initial
Subscription.

If any of them cannot be established, none of them is established and the
operation must not be considered successful.

---

### BR-6 — Organization ownership does not grant unrelated global capabilities

Becoming Owner of an Organization grants responsibilities only within the relevant Organization context.

It must not automatically grant:

* ownership of another Organization;
* Pet Guardianship;
* access to arbitrary Pets;
* access to arbitrary medical records;
* Veterinarian professional status;
* professional status at any Clinic.

---

### BR-7 — Veterinary qualification is not required to own an Organization

Owning a Veterinary Organization does not inherently require the User to be a Veterinarian unless a later approved business rule explicitly requires it.

Organization ownership and veterinary professional qualification are separate concepts.

---

### BR-8 — Establishing an Organization does not automatically create a Clinic

A Veterinary Organization and a Clinic are separate domain concepts.

Successful Organization establishment must not automatically create a physical Clinic unless a separate Specification explicitly defines such behavior.

---

### BR-9 — An Organization may operate multiple Clinics

The domain must allow a Veterinary Organization to operate more than one
Clinic.

Organization establishment must not assume a one-to-one relationship between
an Organization and a physical Clinic.

The creation and management of Clinics are defined by separate
Specifications.

---

### BR-10 — Organization establishment requires trusted Commercial Onboarding

Only the trusted Commercial Onboarding process may establish a Veterinary
Organization.

The following must not, by themselves, allow a User to establish an
Organization:

* authentication;
* email verification;
* a Veterinarian Professional Profile;
* Guardianship;
* Membership or responsibility in another Organization.

No Organization responsibility or capability authorizes establishing another
Veterinary Organization.

---

### BR-11 — Requesting Commercial Onboarding establishes nothing

A User may express interest in, or initiate a request for, Commercial
Onboarding.

Initiating such a request must not establish an Organization, Organization
Membership, Organization responsibility, Subscription, or Entitlement.

Phase 1 does not persist Commercial Onboarding requests as a domain concept.
How requests are captured and reviewed is outside this Specification.

---

### BR-12 — Establishment includes the initial Subscription

Every Veterinary Organization is established with an initial Subscription.

The Commercial Onboarding operation must establish that initial Subscription,
as defined by SPEC-SUB-001, in the same atomic operation as the Organization
and its initial Owner Membership.

The initial Subscription state is determined by the trusted commercial process
(for example `PENDING` or `ACTIVE`).

An Organization must never be established without its initial Subscription.

---

### BR-13 — Establishment does not itself grant Entitlement

Establishing an Organization does not, by itself, grant any paid professional
Entitlement.

Paid professional capability derives only from the evaluation defined by
SPEC-SUB-003 of the Organization's current Subscription state.

An Organization established with a `PENDING` initial Subscription has no
normal paid professional Entitlement.

---

### BR-14 — Establishment is idempotent

Retrying the Commercial Onboarding operation for the same commercial
onboarding must not establish a second Organization, Organization Membership,
Owner responsibility, or Subscription.

The retry mechanism is architectural. It must allow the result of an already
completed establishment to be recognized safely.

---

### BR-15 — An established Organization outlives its commercial state

This rule applies only after establishment. Establishment itself always
includes the initial Subscription (BR-12).

Once established, an Organization continues to exist whatever its later
commercial state, including when its Subscription becomes `PAST_DUE`,
`CANCELLED`, or `EXPIRED`, loses Entitlement, or when the Organization later
has no current Subscription.

Loss of Entitlement or of a current Subscription must not delete or rewrite
Organization, Clinic, Organization Membership, responsibility, Appointment,
clinical, or audit information.

That behavior is governed by SPEC-SUB-002 and SPEC-SUB-004.

---

### BR-16 — Initial Owner account eligibility

The designated initial Owner is identified by their domain User. At
establishment, that User must:

* exist as a domain User;
* have exactly one coherent mapped authentication account;
* have a confirmed email address on that account;
* not have a deleted authentication account;
* not be an anonymous authentication account;
* not be currently banned: an account without a ban, or whose ban ends at or
  before the establishment instant, is eligible; an account banned until a
  later instant is not.

No User Profile is required.

This rule is scoped to designating the initial Owner through Commercial
Onboarding. It does not change the verification rules of any other identity,
Invitation, Guardianship or professional workflow.

An ineligible designated Owner causes the whole establishment to fail; nothing
is established (BR-5).

---

## 4. Scenarios

### Scenario: Establish a Veterinary Organization through Commercial Onboarding

Given Maria is an existing User
And Maria satisfies the required account verification state
And the trusted Commercial Onboarding process designates Maria as initial Owner
And valid Organization information is provided
And the trusted commercial process determines an initial Subscription state

When the trusted Commercial Onboarding process establishes Animalia Veterinary Group

Then Animalia Veterinary Group is established
And Animalia Veterinary Group exists independently from Maria's User identity
And Maria receives an active Organization Membership in Animalia Veterinary Group
And Maria has the Owner responsibility within Animalia Veterinary Group
And the Membership has an effective start
And the Membership has no effective end
And Animalia Veterinary Group has its initial Subscription in the state determined by the commercial process

---

### Scenario: Verified User cannot establish an Organization directly

Given Maria is authenticated
And Maria satisfies the required account verification state

When Maria attempts to establish a Veterinary Organization directly from a client application

Then the operation is denied
And no Organization is established
And no Organization Membership is created
And no Subscription is established

---

### Scenario: Untrusted caller cannot establish an Organization

Given a caller is not the trusted Commercial Onboarding process

When the caller attempts to establish a Veterinary Organization

Then the operation is denied
And no Organization, Organization Membership, or Subscription is established

---

### Scenario: Requesting Commercial Onboarding establishes nothing

Given Maria is an authenticated User

When Maria initiates a request for Commercial Onboarding from the application

Then no Organization is established
And Maria receives no Organization Membership or responsibility
And no Subscription or Entitlement is established

---

### Scenario: Designated Owner without required verification is rejected

Given Maria is an existing User
And Maria does not satisfy the account verification requirement for Organization ownership

When the trusted Commercial Onboarding process attempts to establish an Organization designating Maria as initial Owner

Then the operation fails
And no Organization, Organization Membership, or Subscription is established

---

### Scenario: Establishment with a PENDING Subscription grants no paid Entitlement

Given the trusted Commercial Onboarding process establishes Animalia Veterinary Group
And its initial Subscription state is `PENDING`

When a normal paid professional operation is evaluated for Animalia

Then the operation is denied for lack of professional Entitlement
And Animalia Veterinary Group continues to exist

---

### Scenario: Retried Commercial Onboarding is idempotent

Given the trusted Commercial Onboarding process has established Animalia Veterinary Group

When the same Commercial Onboarding operation is retried

Then no second Organization is established
And no second Organization Membership, Owner responsibility, or Subscription is established

---

### Scenario: Organization establishment does not create a Clinic

Given Animalia Veterinary Group has been established through Commercial Onboarding

When Organization establishment is completed

Then no physical Clinic is created solely because the Organization was established

---

### Scenario: Organization establishment does not make the Owner a Veterinarian

Given Maria is not a Veterinarian
And Maria is designated initial Owner by the trusted Commercial Onboarding process

When Animalia Veterinary Group is established

Then Maria becomes its Owner
And Maria does not become a Veterinarian solely because she owns the Organization

---

### Scenario: Establishment fails if any required part cannot be established

Given the trusted Commercial Onboarding process designates Maria as initial Owner

When the Organization cannot be established together with Maria's initial Owner Membership and the initial Subscription

Then the establishment operation fails
And the system must not expose an Organization without an Owner or without its initial Subscription

---

### Scenario: Established Organization survives later loss of its current Subscription

Given Animalia Veterinary Group was established with an initial Subscription
And its Subscription later becomes `EXPIRED`
And Animalia has no current Subscription

When Animalia is evaluated

Then Animalia Veterinary Group continues to exist
And its Clinics, Memberships, responsibilities, Appointments, clinical information, and audit information are preserved

---

## 5. Edge Cases

### User already owns another Organization

Existing ownership or Membership in another Organization must not by itself prevent the trusted Commercial Onboarding process from establishing an additional Organization designating the same User as initial Owner.

---

### Failure during Organization establishment

Organization establishment, the initial Owner Membership, and the initial Subscription form one logical domain operation.

Partial success must not leave an Organization without its initial ownership or without its initial Subscription.

---

### Duplicate Organization names

The platform must not assume that Organization display names are globally unique unless a dedicated Requirement establishes that constraint.

Unique technical identifiers may be required independently from public names.

---

## 6. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-005 — Organization and Clinic are different concepts.**
* **INV-006 — Organization Membership is temporal.**
* **INV-013 — Subscription termination does not erase history.**
* **INV-017 — An Organization must retain an active Owner.**
* **INV-018 — Organization establishment is a trusted commercial operation.**

---

## 7. Dependencies

* SPEC-ID-001 — Register User
* SPEC-ID-002 — Verify Email Address
* SPEC-SUB-001 — Establish Organization Subscription
* SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 8. Out of Scope

This Specification does not define:

* capture, persistence, or review of Commercial Onboarding requests;
* commercial approval criteria;
* payment collection, billing-provider integration, or payment UI;
* Clinic creation;
* inviting additional Organization members;
* Organization Membership termination;
* Organization ownership transfer;
* Organization deletion or archival;
* Veterinarian profile creation;
* professional credential verification;
* Clinic assignment;
* billing plans;
* legal verification of the business entity.

---

## 9. Verification Notes

Verification must demonstrate that:

1. only the trusted Commercial Onboarding process can establish a Veterinary Organization;
2. an authenticated verified User cannot establish an Organization directly;
3. the Organization is independent from the designated Owner's User identity;
4. establishment creates an active initial Membership with the Owner responsibility for the designated initial Owner;
5. the Organization, initial Owner Membership, Owner responsibility, and initial Subscription are established atomically, and never the Organization without its initial Subscription;
6. a designated Owner who does not satisfy the verification requirement is rejected;
7. a retried establishment does not create a second Organization, Membership, Owner responsibility, or Subscription;
8. an Organization established with a `PENDING` Subscription has no normal paid professional Entitlement;
9. establishment does not automatically create a Clinic;
10. establishment does not grant Veterinarian status;
11. after establishment, later loss of Entitlement or of a current Subscription does not delete or rewrite the Organization or its related information;
12. the operation of §10 is executable by `service_role` only, and the former `create_veterinary_organization` boundary no longer exists;
13. an eligible Owner without a User Profile is accepted; a missing domain User, an incoherent mapping, and unconfirmed, deleted, anonymous or currently banned accounts are rejected with nothing written; an expired ban is accepted;
14. establishment creates exactly one Organization, one Owner Membership, one active Organization-scoped `OWNER` Grant and one initial Subscription (plus the requested provider references), and no Clinic, Clinic configuration, Invitation, Professional Profile or `VETERINARIAN` responsibility;
15. the Membership, the `OWNER` Grant and the Subscription establishment share one establishment instant; an omitted initial effective time resolves to it; an explicit one not later than it is accepted; a later one is rejected;
16. an exact replay returns the original identifiers with `ALREADY_ESTABLISHED`, also after later Subscription transitions; contradictory reuse of the key for any material input is rejected; a replay supplying an omitted initial effective time is compared as omitted;
17. two concurrent identical requests establish exactly one footprint and both return the same identifiers; contradictory concurrent requests yield one establishment and one deterministic conflict;
18. an injected failure at any step leaves no Organization, Membership, Grant, Subscription, provider reference or idempotency record;
19. the same Owner may be initial Owner of several Organizations, and duplicate display names are permitted.

---

## 10. Trusted establishment operation (Phase 1)

### Operation contract

    establish_veterinary_organization(
        p_owner_user_id                  uuid,
        p_organization_display_name      text,
        p_establishment_idempotency_key  uuid,
        p_initial_subscription_state     text,
        p_initial_state_effective_at     timestamptz,
        p_commercial_valid_from          timestamptz,
        p_commercial_valid_until         timestamptz,
        p_establishment_source           text,
        p_provider_references            jsonb default null
    ) returns jsonb

- **Caller.** `service_role` only (the trusted Commercial Onboarding process:
  a manual operator, a backoffice service, or a later billing processor). No
  client role may execute it. It does not depend on any authenticated subject.
- **Owner.** `p_owner_user_id` is the designated Owner's domain User id; never
  an Auth subject or email. The operation checks BR-16 itself.
- **Initial Subscription inputs** come from the commercial process
  (`SPEC-SUB-001` §14): state `PENDING` or `ACTIVE`; optional initial effective
  time, not later than the establishment instant (omitted means the
  establishment instant); optional commercial validity start and end (an
  `ACTIVE` without an end is open-ended; no date is synthesized); non-blank
  establishment source; optional provider references
  (`[{provider, reference_kind: CUSTOMER|SUBSCRIPTION, opaque_reference}]`,
  without duplicates). There is no initiating User: this is not a
  User-initiated Subscription (`SPEC-SUB-001` BR-9).
- **Idempotency.** `p_establishment_idempotency_key` is required and identifies
  the commercial onboarding. It is the Organization's establishment key and the
  initial Subscription's establishment key.

### Creates, atomically, at one establishment instant `t`

1. the Veterinary Organization (server-generated id, requested display name,
   establishment key);
2. the Owner's Organization Membership, effective from `t`, without end or
   originating Invitation;
3. the active Organization-scoped `OWNER` Grant on it, effective from `t`,
   granted by the Owner (the existing establishment convention);
4. the initial Subscription, established at `t`, in the requested state,
   effective at the requested time or `t`, with the requested validity;
5. the requested provider references;
6. the durable idempotency record (key and requested-input digest on the
   Organization).

It creates nothing else (BR-7, BR-8).

### Result

    {
      "organization_id": uuid,
      "owner_membership_id": uuid,
      "subscription_id": uuid,
      "outcome": "ESTABLISHED" | "ALREADY_ESTABLISHED"
    }

The result never contains the key, an Auth subject, an email, provider
references, the current Subscription state, or source metadata.

### Replay

- Exact replay is decided over the requested inputs: Owner, normalized display
  name, initial state, requested initial effective time (omitted and explicit
  are different requests), validity start and end, normalized establishment
  source and the provider-reference set (order-insensitive).
- An exact replay returns the original identifiers with `ALREADY_ESTABLISHED`,
  even after later Subscription transitions or Membership changes, and writes
  nothing.
- Any material difference under the same key fails with `23505`
  (hint `ESTABLISHMENT_KEY_CONFLICT`), as does a key already used by a
  Subscription that was not established by this operation.

### Order and outcomes

1. input shape: missing key, Owner or source, blank display name, unknown
   state value, non-finite or incoherent times, malformed or duplicate provider
   references → `22023`;
2. exact replay / contradictory reuse (above);
3. Owner identity: no domain User or no coherent mapped account → `28000`
   (hint `OWNER_IDENTITY_UNAVAILABLE`); account not eligible (BR-16) → `42501`
   (hint `OWNER_ACCOUNT_INELIGIBLE`);
4. initial Subscription policy: state other than `PENDING`/`ACTIVE` → `23514`
   (hint `INITIAL_STATE_NOT_ALLOWED`); initial effective time later than `t` →
   `23514` (hint `FUTURE_EFFECTIVE_AT`);
5. writes.

No message contains the key, an email, an Auth subject or a provider
reference.

### Operational contract

The operation is called as one autocommit statement. A concurrent identical
request waits for the first and returns its result. The operation reports
success only after the Organization, Membership, Grant and Subscription
invariants have been checked.

### Boundaries

- No structural Organization → Subscription invariant exists yet; the
  guarantee of BR-12 is enforced prospectively by this operation. Legacy
  Organizations are not modified (ADR-009).
- Establishing a later Subscription period for an existing Organization is
  `SPEC-SUB-001` §14, not this operation.

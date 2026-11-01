# SPEC-SUB-001 — Establish Organization Subscription

**Status:** APPROVED  
**Requirements:** REQ-SUB-001, REQ-SUB-002  
**Domain:** Subscription and Entitlements  
**Priority:** P0

## 1. Intent

Allow a Veterinary Organization to establish a professional SaaS Subscription.

The Subscription belongs to the Veterinary Organization.

It does not belong to:

- the User who initiated the purchase;
- the Organization Owner personally;
- an individual Clinic;
- an individual Veterinarian.

The Subscription represents the Organization's commercial relationship with the
platform.

Establishing a Subscription does not, by itself, define which professional
capabilities are currently available.

Professional capability access is determined through the applicable
Entitlement Specifications.

---

## 2. Preconditions

- The Veterinary Organization exists, or is being established by the same
  trusted Commercial Onboarding operation (`SPEC-ORG-001`).
- The acting User exists when the workflow is User-initiated.
- The acting User is authenticated when the workflow is User-initiated.
- When the workflow is User-initiated, the acting User has the current
  `ORGANIZATION_MANAGE_SUBSCRIPTION` capability for the Organization.
- No equivalent current Organization Subscription already exists where the
  Phase 1 commercial model allows only one current professional Subscription.
- The Subscription establishment has been validated through the applicable
  trusted commercial process.
- An explicit initial Subscription state can be established.

---

## 3. Business Rules

### BR-1 — Subscription belongs to the Veterinary Organization

A professional SaaS Subscription must be associated with exactly one Veterinary
Organization.

The Organization is the commercial domain entity receiving the professional
Subscription relationship.

---

### BR-2 — Subscription does not belong to the purchasing User

The User who initiates or pays for the Subscription must not become the domain
owner of the Subscription.

For example:

    Carlos
      ↓
    initiates subscription for
      ↓
    Animalia Veterinary Group

The Subscription belongs to Animalia Veterinary Group.

It does not become Carlos's personal Subscription.

---

### BR-3 — Organization ownership changes do not transfer Subscription identity

If the Organization Owner later changes, the existing Organization Subscription
must remain associated with the same Veterinary Organization.

The Subscription must not need to be recreated solely because:

- the original Owner leaves;
- another User becomes Owner;
- billing responsibility changes between Organization Members.

---

### BR-4 — Subscription is not Clinic-specific

An Organization Subscription must not belong to an individual Clinic.

For example:

    Animalia Veterinary Group
    Subscription
          │
          ├── Animalia Madrid Centro
          └── Animalia Getafe

The Organization may operate several Clinics under the same Organization-level
commercial relationship.

Future plan limits may constrain the number of Clinics, but such limits are not
part of the Phase 1 Subscription identity model.

---

### BR-5 — Creating a Clinic does not create a Subscription

Clinic creation and Subscription establishment are separate domain behaviors.

The existence of one or more Clinics must not automatically create a
professional Subscription.

---

### BR-6 — Subscription may exist before Clinics are created

A Veterinary Organization may establish its Subscription before creating or
onboarding its first Clinic.

The commercial relationship must not depend on the Organization already having
a physical Clinic.

---

### BR-7 — Subscription is not Veterinarian-specific

A Subscription must not belong to an individual Veterinarian.

Adding, removing, or changing Veterinarians must not create or transfer the
Organization Subscription.

---

### BR-8 — Organization Membership does not create Subscription ownership

Organization Members may receive responsibilities allowing them to manage
commercial behavior.

Those responsibilities do not change the domain entity to which the
Subscription belongs.

---

### BR-9 — Only authorized Organization actors may initiate User-facing Subscription establishment

Where Subscription establishment is initiated by a User, that User must have
the `ORGANIZATION_MANAGE_SUBSCRIPTION` capability for the Organization.

Authentication or Organization Membership alone is insufficient.

Establishment performed by the trusted Commercial Onboarding process as part of
`SPEC-ORG-001` is not User-initiated establishment. It does not require the
designated initial Owner to hold `ORGANIZATION_MANAGE_SUBSCRIPTION` before the
Organization exists.

---

### BR-10 — Organization Owner status should not be hard-coded as the only authorization model

Phase 1 uses the responsibility-derived
`ORGANIZATION_MANAGE_SUBSCRIPTION` capability.

However, the domain must evaluate the applicable responsibility-derived
capability rather than permanently encoding:

    is Owner = may manage Subscription

This allows future approved responsibility mappings to evolve without changing
Subscription identity.

---

### BR-11 — Client assertion does not establish trusted Subscription state

The mobile application must not be authoritative for determining that an
Organization has successfully established a valid Subscription.

Where a trusted commercial or billing process is involved, the resulting
Subscription state must be established through trusted backend or provider
information.

A manipulated client must not be able to grant professional paid capabilities.

---

### BR-12 — Subscription has explicit state

An established Organization Subscription must have an explicit current
Subscription state.

The system must not infer commercial validity merely from the existence of a
Subscription record.

Conceptually:

    Organization Subscription
              +
    explicit current state

The complete state model and allowed transitions are defined separately.

---

### BR-13 — Subscription existence does not imply entitlement

The existence of an Organization Subscription must not, by itself, grant paid
professional capabilities.

For example:

    Subscription exists

does not necessarily mean:

    new Appointments may be managed
    professionals may be assigned
    paid Clinic capabilities are enabled

Professional capability access must be derived through the applicable
Entitlement rules.

---

### BR-14 — Entitlements depend on current commercial validity

A Subscription may contribute to professional Entitlements only when its
current state and applicable commercial information satisfy the Entitlement
rules.

The exact evaluation is defined by `SPEC-SUB-003`.

---

### BR-15 — Subscription establishment does not alter Organization Membership

Creating the Organization Subscription must not:

- add Organization Members;
- remove Organization Members;
- change Member responsibilities;
- change Organization ownership.

Commercial state and professional membership are separate concepts.

When Subscription establishment is part of Organization establishment through
Commercial Onboarding, the initial Owner Membership and Owner responsibility
result from `SPEC-ORG-001`, not from the Subscription.

---

### BR-16 — Subscription establishment does not alter Clinic relationships

Creating the Subscription must not:

- create a Clinic;
- delete a Clinic;
- publish a Clinic;
- assign Veterinarians to Clinics;
- modify Clinic ownership or Organization identity.

---

### BR-17 — Subscription establishment does not create professional identity

Creating the Subscription must not:

- create a Veterinarian Professional Profile;
- verify professional credentials;
- create Clinic Assignments;
- create Appointment Assignments.

---

### BR-18 — Subscription establishment does not create medical access

An Organization acquiring a Subscription must not gain access to Pet medical
information solely because it pays for the platform.

Medical access remains governed by the Medical Access Control domain.

---

### BR-19 — Subscription establishment does not create Pet relationships

Creating a Subscription must not:

- create Pets;
- create Guardianships;
- create Care Authorizations;
- create Clinical Encounters.

---

### BR-20 — Subscription identity is independent from commercial provider identity

The domain Subscription must have its own identity.

Any external billing or Subscription-provider identifiers are implementation or
integration references associated with that domain Subscription.

The domain must not require an external provider identifier to become its
primary business identity.

---

### BR-21 — External commercial references must remain attributable

Where an external billing or Subscription provider participates in the
commercial workflow, the system must preserve enough information to correlate
trusted provider information with the applicable Organization Subscription.

The exact provider and identifier format are architectural concerns.

---

### BR-22 — Phase 1 supports one current professional Subscription relationship per Organization

Phase 1 must avoid multiple simultaneous equivalent current professional SaaS
Subscriptions for the same Veterinary Organization.

The system must not create ambiguous parallel current Subscription
relationships for the same commercial capability.

Future multiple plans or Subscription products may refine this behavior.

---

### BR-23 — Historical Subscription periods may remain distinguishable

An Organization may eventually end a Subscription and later establish a new
commercial relationship.

The model must be capable of preserving distinct Subscription periods rather
than rewriting historical commercial state.

Conceptually:

    Subscription period #1
    established → ended

    later

    Subscription period #2
    established → current

The lifecycle behavior is defined by subsequent Specifications.

---

### BR-24 — Re-subscription must not rewrite previous commercial history

If an Organization later subscribes again after a previous Subscription period
ended, the previous historical Subscription relationship must not be
destructively rewritten as though uninterrupted commercial access existed.

---

### BR-25 — Subscription establishment is independent from public Clinic visibility

An Organization may establish a Subscription regardless of whether its Clinics
are currently:

- unpublished;
- being configured;
- not yet created.

Subscription and Discovery visibility are separate concerns.

---

### BR-26 — Subscription establishment must not rewrite historical information

Creating or re-establishing a Subscription must not alter historical:

- Appointments;
- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- Medical Access Audit Events;
- professional relationship history.

Commercial relationships and historical domain truth remain separate.

---

### BR-27 — Subscription establishment must be traceable

The system must preserve enough information to establish:

- the Veterinary Organization;
- the Subscription identity;
- when the Subscription relationship was established;
- its initial explicit state;
- the acting User where applicable;
- the applicable trusted commercial context.

---

### BR-28 — Duplicate establishment must be prevented

If the Organization already has an equivalent current Subscription relationship,
repeating the establishment operation must not create an accidental duplicate
current Subscription.

Technical retry behavior must not result in multiple equivalent commercial
relationships.

---

### BR-29 — Subscription establishment is atomic

A successfully established Subscription must coherently associate:

- the Subscription;
- the Veterinary Organization;
- the establishment time;
- the initial Subscription state;
- required commercial correlation information.

The system must not expose an ambiguous Subscription whose Organization or
commercial state cannot be determined.

---

### BR-30 — Every Organization is established with its initial Subscription

Every Veterinary Organization is established with an initial Subscription.

The trusted Commercial Onboarding operation defined by `SPEC-ORG-001`
establishes that initial Subscription in the same atomic operation as the
Organization. The initial state is determined by the trusted commercial process
(for example `PENDING` or `ACTIVE`).

An Organization must never be established without its initial Subscription.

Once established, an Organization may later have no current Subscription, for
example after expiration. That later condition does not end the
Organization's existence and does not permit establishing an Organization
without its initial Subscription.

---

### BR-31 — Organization Members do not establish Subscriptions

Accepting an Organization Invitation, receiving Organization responsibilities,
or being assigned to a Clinic must not require, create, or transfer a
Subscription.

Organization Members act under their Organization's Entitlements
(`SPEC-SUB-003` BR-1), subject to their own Membership, responsibility,
Clinic Assignment, and Medical Access authorization.

---

## 4. Organization Subscription Information

The Subscription domain must support enough information to identify the
commercial relationship independently from a specific billing provider.

### Required

- Subscription identity;
- Veterinary Organization;
- establishment time;
- current explicit Subscription state.

### Context-dependent

- acting User who initiated the commercial workflow;
- external commercial provider reference;
- external Subscription or customer reference;
- commercial synchronization metadata;
- state-change information.

Future commercial requirements may introduce additional plan or entitlement
information.

---

## 5. Scenarios

### Scenario: Authorized Owner establishes Organization Subscription

Given Carlos is authenticated  
And Carlos currently has `ORGANIZATION_MANAGE_SUBSCRIPTION` for Animalia
Veterinary Group
And Animalia Veterinary Group has no equivalent current Subscription  
And the applicable trusted commercial process succeeds

When Carlos establishes the professional Subscription

Then a Subscription is established for Animalia Veterinary Group  
And the Subscription identifies Animalia Veterinary Group as its Organization  
And Carlos does not become the personal owner of the Subscription  
And an explicit initial Subscription state is established

---

### Scenario: Subscription remains with Organization after Owner changes

Given Carlos established Animalia Veterinary Group's Subscription  
And Carlos later ceases to be Organization Owner  
And Maria becomes the new Organization Owner

When the current Organization Subscription is evaluated

Then the Subscription still belongs to Animalia Veterinary Group  
And the Subscription is not transferred from Carlos to Maria  
And the ownership change does not create another Subscription

---

### Scenario: Organization with multiple Clinics uses Organization-level Subscription

Given Animalia Veterinary Group operates Animalia Madrid Centro  
And Animalia Veterinary Group operates Animalia Getafe  
And Animalia has an Organization Subscription

When the Subscription relationship is evaluated

Then the Subscription belongs to Animalia Veterinary Group  
And separate equivalent Subscriptions are not required solely because Animalia
operates two Clinics

---

### Scenario: Organization may subscribe before creating Clinic

Given Animalia has no Clinics yet
And the Subscription is established through a valid trusted establishment
workflow: either Commercial Onboarding establishing Animalia (`SPEC-ORG-001`),
or, after establishment, a later re-subscription once Animalia has no current
Subscription

When the Subscription is established

Then Animalia may have a professional Subscription  
And absence of a Clinic does not invalidate the Organization Subscription

---

### Scenario: Commercial Onboarding establishes the initial Subscription with the Organization

Given Maria is an existing verified User
And the trusted Commercial Onboarding process designates Maria as initial Owner
And the trusted commercial process determines the initial state `PENDING`

When the trusted Commercial Onboarding process establishes Animalia Veterinary
Group

Then Animalia Veterinary Group is established together with its initial
Subscription
And the initial Subscription state is `PENDING`
And Maria's Owner Membership results from `SPEC-ORG-001`, not from the
Subscription
And Animalia has no normal paid professional Entitlement while the
Subscription is `PENDING`

---

### Scenario: Invited Member does not establish a Subscription

Given Animalia Veterinary Group has an `ACTIVE` Subscription
And Carlos accepts a valid Invitation to Animalia

When Carlos's Membership is established

Then no Subscription is created or transferred for Carlos
And Carlos's paid professional operations are evaluated against Animalia's
Entitlements and his own authorization

---

### Scenario: Organization Membership alone cannot establish Subscription

Given Maria has an active Membership in Animalia Veterinary Group  
And Maria does not have `ORGANIZATION_MANAGE_SUBSCRIPTION` for Animalia

When Maria attempts to establish Animalia's Subscription

Then the operation is denied  
And Organization Membership alone is insufficient

---

### Scenario: Subscription establishment does not grant medical access

Given Animalia Veterinary Group successfully establishes a Subscription  
And no valid Pet Care Authorization exists for Luna

When an Animalia professional attempts to access Luna's protected medical
history solely because Animalia has a Subscription

Then access is denied  
And commercial Subscription does not constitute medical authorization

---

### Scenario: Subscription existence alone does not prove paid capability

Given Animalia Veterinary Group has an Organization Subscription  
And the current Subscription state does not satisfy the applicable Entitlement
rules

When a User attempts a capability that requires a valid professional
Entitlement

Then Subscription existence alone is insufficient  
And the capability is denied according to the applicable Entitlement
Specification

---

### Scenario: Subscription establishment does not create Clinic

Given Animalia Veterinary Group has no Clinics

When Animalia validly establishes its Organization Subscription

Then no Clinic is created automatically

---

### Scenario: Subscription establishment does not create professional relationships

Given Animalia Veterinary Group establishes a Subscription

When the operation completes

Then no Veterinarian Professional Profile is created  
And no Organization Membership is created  
And no Clinic Assignment is created  
And no Appointment Veterinarian Assignment is created

---

### Scenario: Duplicate current Subscription is not created

Given Animalia Veterinary Group already has an equivalent current professional
Subscription

When an establishment operation is retried or repeated

Then another equivalent current Subscription is not created  
And the existing current Subscription remains authoritative

---

### Scenario: Former Subscription period remains historical after re-subscription

Given Animalia previously had Subscription period #1  
And Subscription period #1 ended  
And Animalia later validly establishes a new professional Subscription

When the new commercial relationship is established

Then a new current Subscription period may exist  
And Subscription period #1 remains historical  
And the earlier period is not rewritten as uninterrupted current access

---

### Scenario: Manipulated client cannot self-grant Subscription validity

Given Animalia Veterinary Group does not have a commercially valid
Subscription state  
And a manipulated client claims that Animalia is subscribed

When trusted Subscription state is evaluated

Then the client assertion alone is insufficient  
And paid professional capability is not granted solely from untrusted client
state

---

### Scenario: Subscription establishment preserves existing history

Given Animalia Veterinary Group has historical clinical and Appointment data  
And Animalia establishes or re-establishes a Subscription

When the Subscription operation completes

Then existing historical clinical information remains unchanged  
And Appointment history remains unchanged  
And audit history remains unchanged

---

## 6. Subscription Ownership Model

The commercial relationship should be understood as:

    Veterinary Organization
              ↓
    Organization Subscription

not:

    User
      ↓
    personal professional Subscription

and not:

    Clinic
      ↓
    Clinic Subscription

A User may manage the Organization Subscription through their current
Organization capabilities.

That management authority does not change Subscription ownership.

---

## 7. Subscription and Entitlements

Subscription and Entitlement are related but distinct concepts.

Subscription answers:

    "What commercial relationship currently exists for this Organization?"

Entitlement answers:

    "May this Organization currently use this paid professional capability?"

Conceptually:

    Organization
        ↓
    Subscription
        ↓
    current Subscription state
        +
    applicable entitlement rules
        ↓
    Professional Entitlements

The existence of the Subscription alone must not bypass Entitlement evaluation.

---

## 8. Historical Commercial Relationship

The Subscription model must be capable of preserving separate commercial
periods.

For example:

    Animalia Veterinary Group

    Subscription #1
    Established: 2026-01-01
    Ended:       2027-03-31

    No current Subscription
    2027-04-01 → 2027-06-14

    Subscription #2
    Established: 2027-06-15
    Current

The gap is meaningful commercial history.

It must not be silently collapsed into continuous Subscription validity.

---

## 9. Edge Cases

### Organization changes Owner

Organization ownership changes do not alter Subscription identity.

The new authorized Owner may gain management capability through the applicable
Organization responsibility model.

---

### Organization has no Clinic

The Organization may still establish a Subscription.

Clinic creation remains an independent workflow.

---

### Organization temporarily has no professional Members

Temporary absence of active professional Members does not by itself delete the
Organization Subscription.

Subscription lifecycle is governed by commercial state rather than the number
of current professionals.

---

### External billing provider retries an event

Technical retries must not create duplicate Organization Subscriptions.

Idempotency and provider-event handling are architectural concerns.

---

### External commercial provider changes

Future migration to another billing or Subscription provider must not require
creating a different Veterinary Organization or redefining historical medical
data.

The domain Subscription should remain provider-independent where practical.

---

### Multiple plans are introduced later

Phase 1 does not require multiple commercial plan levels.

Future plan or entitlement tiers must be introduced through the applicable
requirements without assuming that the initial Subscription identity belongs
to a particular permanent plan structure.

This supports `REQ-SUB-005` without implementing it in Phase 1.

---

## 10. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-004 — End Organization Membership
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ID-003 — Authenticate User

Professional capability evaluation will be defined by later Subscription and
Entitlement Specifications.

---

## 12. Out of Scope

This Specification does not define:

- complete Subscription state taxonomy;
- Subscription state transitions;
- payment failure behavior;
- cancellation behavior;
- Subscription termination;
- grace periods;
- billing retries;
- professional Entitlement evaluation;
- Entitlement loss behavior;
- multiple Subscription plans;
- usage limits;
- per-Clinic billing;
- invoices;
- taxes;
- refunds;
- payment methods;
- external billing-provider selection;
- billing-provider webhook implementation;
- App Store or Play Store billing implementation.

---

## 13. Verification Notes

Verification must demonstrate that:

1. a professional Subscription belongs to exactly one Veterinary Organization;
2. the initiating or paying User does not become the Subscription owner;
3. Organization ownership changes do not transfer or recreate Subscription
   identity;
4. Subscription is Organization-level rather than Clinic-level;
5. an Organization may establish a Subscription before creating Clinics;
6. `ORGANIZATION_MANAGE_SUBSCRIPTION` is required for User-initiated
   Subscription establishment;
7. untrusted client state cannot establish commercial validity;
8. an established Subscription has an explicit initial state;
9. Subscription existence alone does not grant professional Entitlements;
10. Subscription does not create Organization Membership, Clinic Assignment,
    professional identity, Pet relationships, or medical access;
11. the domain Subscription remains distinguishable from external billing
    provider identity;
12. Phase 1 avoids duplicate simultaneous equivalent current Subscriptions;
13. later re-subscription may preserve distinct historical commercial periods;
14. Subscription establishment does not rewrite medical, Appointment, or audit
    history;
15. duplicate or retried establishment operations do not create accidental
    duplicate current Subscriptions;
16. Subscription establishment behaves atomically;
17. every Organization established through Commercial Onboarding has its
    initial Subscription established in the same atomic operation;
18. Commercial Onboarding establishment does not require prior
    `ORGANIZATION_MANAGE_SUBSCRIPTION`;
19. accepting an Organization Invitation or receiving responsibilities does not
    require, create, or transfer a Subscription.

---

## 14. Phase 1 manual commercial establishment (Subscription Operational Safety)

For the Phase 1 manually managed commercial model (`SPEC-SUB-002` §14):

- the trusted commercial process supplies the initial state and its
  commercial-validity context; establishment chooses no commercial policy
  itself;
- the initial state is `PENDING` or `ACTIVE` only. Establishing a Subscription
  as `PAST_DUE`, `CANCELLED`, or `EXPIRED` is rejected;
- the initial state's effective time must not be later than the establishment
  instant (the exact instant is valid); a future-dated initial state is
  rejected;
- validity is never forced: an initial `ACTIVE` may have no
  commercial-validity end, and no end is synthesized;
- an exact replay of an already established Subscription (same idempotency
  key and facts) still returns it; contradictory reuse of the key is still
  rejected;
- an initial `ACTIVE` Subscription may deliberately be open-ended (no
  commercial-validity end). That is the default manual Phase 1 customer model;
  finite validity is used only where a real commercial end boundary is known;
- an Organization's Subscription period that has become `EXPIRED` is never
  reactivated. Restarting service establishes a new Subscription period with
  this operation once no non-`EXPIRED` Subscription occupies the Organization's
  current relationship (BR-22, BR-23, BR-24). Establishing it never rewrites
  the expired period or the validity gap;
- establishment remains trusted: no client role may establish a Subscription.

### Initial Subscription versus a later Subscription period

- An Organization's **initial** Subscription is established only by the atomic
  Commercial Onboarding operation `establish_veterinary_organization`
  (`SPEC-ORG-001` §10), together with the Organization and its initial Owner,
  at the establishment instant. It shares the Organization's establishment key.
- `establish_organization_subscription` (`service_role` only) establishes a
  **later** Subscription period for an already established Organization, once
  no non-`EXPIRED` Subscription occupies its current relationship. It is not an
  initial-establishment path, and the one-current-relationship invariant still
  rejects a second current Subscription.
- Exact replay of either operation compares the provider references as well:
  the same set of normalized `(provider, reference_kind, opaque_reference)`
  entries in any order is the same request; an added, removed or changed entry
  under the same idempotency key is contradictory reuse (`23505`). No provider
  reference is ever ignored on replay.

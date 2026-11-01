# SPEC-SUB-002 — Maintain Organization Subscription State

**Status:** APPROVED  
**Requirements:** REQ-SUB-002, REQ-SUB-004  
**Domain:** Subscription and Entitlements  
**Priority:** P0

## 1. Intent

Maintain an explicit and trustworthy lifecycle state for an Organization
Subscription.

Subscription state represents the current commercial condition of the
Organization's professional Subscription.

The state must be derived from trusted commercial information rather than
client-side assertions.

Subscription state is distinct from professional Entitlements.

Entitlements are derived from the Subscription state and applicable commercial
rules through a separate Specification.

---

## 2. Preconditions

- The Veterinary Organization exists.
- The Organization Subscription exists.
- The current Subscription state is identifiable.
- The state-change trigger originates from an authorized commercial workflow
  or trusted provider context.
- The requested transition is valid from the current Subscription state.

---

## 3. Phase 1 Subscription States

Phase 1 supports the following Subscription states.

### PENDING

The Subscription relationship has been established or initiated, but current
commercial validity has not yet been successfully established.

`PENDING` must not be treated as equivalent to a valid paid Subscription.

---

### ACTIVE

The Organization currently has a commercially valid Subscription relationship.

`ACTIVE` may satisfy the Subscription-state requirement for professional paid
Entitlements.

The existence of `ACTIVE` state does not independently bypass other
authorization requirements.

A Phase 1 manually managed `ACTIVE` Subscription may be open-ended: it has no
commercial-validity end and remains `ACTIVE` until an explicit trusted
transition changes it (§14).

---

### PAST_DUE

The Subscription has a payment or commercial validity problem that may still be
recoverable.

`PAST_DUE` represents a distinct condition from both:

- `ACTIVE`;
- `EXPIRED`.

Whether specific professional Entitlements remain temporarily available while
the Subscription is `PAST_DUE` is defined by the Entitlement Specification.

---

### CANCELLED

Future renewal of the Subscription has been cancelled.

`CANCELLED` does not necessarily mean that paid access has ended immediately.

The Organization may remain commercially covered until the end of an already
valid paid period.

Entitlement evaluation must consider the applicable commercial validity period
rather than interpreting cancellation alone as immediate expiration.

---

### EXPIRED

The Subscription no longer provides current commercial validity.

An `EXPIRED` Subscription must not independently provide normal paid
professional Entitlements.

Historical commercial information remains preserved.

---

## 4. Business Rules

### BR-1 — Subscription state is explicit

Every current Organization Subscription must have an explicit state.

The platform must not infer commercial validity merely from the existence of
the Subscription.

---

### BR-2 — Subscription state is trusted server-side information

The mobile client must not be authoritative for Subscription state.

A manipulated client must not be able to establish:

    ACTIVE

or any other trusted commercial state.

State changes must originate from trusted backend or commercial provider
information.

---

### BR-3 — Subscription state does not belong to the acting User

State changes affect the Veterinary Organization's Subscription.

They do not change the personal commercial status of the User who initiated
the original Subscription.

---

### BR-4 — PENDING does not imply Entitlement

A `PENDING` Subscription must not be treated as commercially equivalent to an
`ACTIVE` Subscription.

Professional paid capabilities must not be granted solely because a
Subscription establishment workflow has begun.

---

### BR-5 — ACTIVE represents current commercial validity

`ACTIVE` indicates that the Subscription currently satisfies the normal
commercial validity requirement.

The actual professional operation must still satisfy:

- Organization authorization;
- Clinic context where applicable;
- professional requirements;
- medical-access requirements where applicable.

---

### BR-6 — PAST_DUE represents recoverable commercial failure

A Subscription may enter `PAST_DUE` when a payment or commercial problem
prevents the Subscription from being considered normally healthy but the
relationship has not yet finally expired.

The system must preserve this condition distinctly from immediate permanent
loss of the Subscription relationship.

---

### BR-7 — PAST_DUE behavior is determined through Entitlements

`PAST_DUE` must not independently encode which professional capabilities remain
available.

For example, the product may later decide that some capabilities remain
available temporarily during a recovery window.

That behavior belongs to the Entitlement model.

---

### BR-8 — Cancellation does not necessarily immediately terminate commercial validity

A Subscription may be cancelled while the Organization remains covered through
the end of the already-valid commercial period.

Therefore:

    CANCELLED

must not automatically mean:

    no current Entitlements

without evaluating the applicable commercial validity information.

---

### BR-9 — Cancellation prevents expected future renewal

A `CANCELLED` Subscription represents that automatic or expected future renewal
is no longer active.

The current paid period may nevertheless remain valid.

---

### BR-10 — Expiration removes normal commercial validity

Once the Subscription becomes `EXPIRED`, it must no longer satisfy the normal
current commercial validity condition for paid professional Entitlements.

Historical information remains unaffected.

---

### BR-11 — Subscription state transitions must be controlled

The system must not allow arbitrary transitions between Subscription states.

Transitions must correspond to meaningful commercial events.

---

### BR-12 — Duplicate provider events must not create duplicate transitions

Repeated delivery of the same trusted commercial event must not create
multiple logically identical state transitions.

The exact idempotency mechanism is architectural.

---

### BR-13 — Out-of-order commercial events must not silently corrupt current state

Trusted commercial events may arrive later than other events.

The system must not blindly apply stale information when doing so would
incorrectly move the Subscription to an older commercial state.

The exact ordering and synchronization strategy is architectural.

---

### BR-14 — State changes must preserve historical commercial information

A Subscription state transition must not erase the previous commercial
condition where historical traceability is required.

The system must be capable of establishing meaningful Subscription history.

---

### BR-15 — State change preserves Organization identity

Changing Subscription state must not:

- create another Veterinary Organization;
- move the Subscription to another Organization;
- change Organization ownership.

---

### BR-16 — State change preserves Subscription identity

Normal state transitions modify the commercial state of the existing
Subscription.

They must not create a new Subscription identity solely because the state
changed.

---

### BR-17 — State change does not alter Organization Membership

Changing Subscription state must not:

- remove Organization Members;
- end Organization Memberships;
- change responsibilities.

Commercial validity and Organization Membership remain separate concepts.

---

### BR-18 — State change does not alter Clinic Assignment history

Subscription deterioration, cancellation, or expiration must not delete or
rewrite Veterinarian Clinic Assignment history.

Current Entitlements may restrict future operations, but historical
professional relationships remain preserved.

---

### BR-19 — Subscription state change does not delete Appointments

A Subscription becoming:

- `PAST_DUE`;
- `CANCELLED`;
- `EXPIRED`;

must not delete existing Appointments.

Appointment history and existing obligations remain identifiable.

The applicable Entitlement and Appointment Specifications determine which
future operations remain permitted.

---

### BR-20 — Subscription state change does not delete medical information

A Subscription state transition must not delete or rewrite:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- Pet medical history.

Commercial state and medical-history durability are separate concerns.

---

### BR-21 — Subscription state change does not revoke Pet Care Authorization

Commercial Subscription state and Pet Care Authorization are separate domain
concepts.

Changing Subscription state must not silently rewrite or delete Care
Authorization history.

Whether professional use of a Care Authorization remains operationally
available may depend on Entitlements.

---

### BR-22 — Subscription state change does not erase Medical Access Audit Events

Commercial deterioration or termination must not remove historical security
audit information.

---

### BR-23 — Historical clinical provenance survives expiration

An Organization whose Subscription later expires must remain identifiable as
the historical provider of clinical information it created while operating
validly.

---

### BR-24 — Subscription may recover from PAST_DUE

A `PAST_DUE` Subscription may return to `ACTIVE` when the commercial issue is
successfully resolved.

The earlier `PAST_DUE` period remains historically meaningful where required.

---

### BR-25 — EXPIRED Subscription does not reactivate silently

An `EXPIRED` Subscription must not become commercially valid merely because the
client resumes using the application.

In Phase 1 `EXPIRED` is terminal for that Subscription period: no transition
leaves it (§5, §14).

---

### BR-26 — Re-subscription after expiration requires a new Subscription period

Where the Organization later establishes a new commercial relationship after
expiration, it does so through a new Subscription period established by the
trusted commercial workflow (`SPEC-SUB-001`). The expired Subscription is never
reactivated.

The system must preserve the earlier expired period. The new relationship must
not silently rewrite the historical gap, and historical validity periods must
remain reconstructable.

---

### BR-27 — State changes must preserve effective timing

The system must preserve enough temporal information to determine when a
Subscription state became effective.

Where commercial validity ends at a known future time, that time must remain
distinguishable from the time cancellation was requested.

---

### BR-28 — Cancellation time and expiration time are distinct

The system must be able to represent:

    cancellation requested: 2026-09-10
    commercially valid until: 2026-09-30
    expired: 2026-10-01

These events must not be collapsed into one timestamp.

---

### BR-29 — State evaluation must use trusted current information

Professional Entitlement decisions must evaluate the authoritative current
Subscription condition.

A stale cached client state must not become the security boundary for paid
professional capabilities.

---

### BR-30 — State transition is atomic

A valid Subscription state change must establish a coherent new current
commercial condition together with its relevant effective information.

The system must not expose contradictory current Subscription states.

---

## 5. Subscription State Transitions

Phase 1 accepts exactly the following trusted transitions (§14):

    PENDING   → ACTIVE
    PENDING   → EXPIRED

    ACTIVE    → PAST_DUE
    ACTIVE    → CANCELLED
    ACTIVE    → EXPIRED

    PAST_DUE  → ACTIVE
    PAST_DUE  → EXPIRED

    CANCELLED → EXPIRED

Every other pair is rejected, including same-state transitions,
`CANCELLED → ACTIVE`, `PENDING → CANCELLED`, `PENDING → PAST_DUE`, and any
transition out of `EXPIRED`. A future product need for another edge requires a
Specification change first.

`PENDING → EXPIRED` closes a commercial relationship that never became
active: the Subscription never provided commercial validity or normal
Entitlements and is now permanently closed.

Not every commercial provider must expose exactly these transitions directly.

The domain must normalize trusted commercial information into a coherent
Subscription state within this graph.

---

## 6. Scenarios

### Scenario: Pending Subscription becomes active

Given Animalia Veterinary Group has a `PENDING` Organization Subscription
And trusted commercial confirmation establishes current validity

When the Subscription state is updated

Then the Subscription becomes `ACTIVE`
And the same Subscription identity is preserved
And Animalia remains the Subscription owner

---

### Scenario: Client cannot mark Subscription active

Given Animalia's Subscription is not currently `ACTIVE`
And a manipulated mobile client claims that the Subscription is active

When trusted Subscription state is evaluated

Then the client assertion is ignored as authoritative commercial state
And Animalia does not become `ACTIVE` solely through the client claim

---

### Scenario: Active Subscription becomes past due

Given Animalia has an `ACTIVE` Subscription
And a trusted commercial process reports a recoverable payment failure

When the Subscription state is updated

Then the Subscription may become `PAST_DUE`
And the Subscription remains historically identifiable
And Entitlement behavior is evaluated separately

---

### Scenario: Payment issue is resolved

Given Animalia's Subscription is `PAST_DUE`
And the commercial problem is successfully resolved

When trusted commercial state is updated

Then the Subscription may return to `ACTIVE`
And the previous `PAST_DUE` period is not required to disappear from
commercial history

---

### Scenario: Subscription is cancelled before paid period ends

Given Animalia has an `ACTIVE` Subscription
And the Subscription is commercially valid until 2026-09-30

When future renewal is cancelled on 2026-09-10

Then the Subscription may become `CANCELLED`
And the cancellation time remains distinguishable
And commercial validity may continue until 2026-09-30
And cancellation alone does not imply immediate expiration

---

### Scenario: Cancelled Subscription later expires

Given Animalia's Subscription is `CANCELLED`
And its valid commercial period ends

When the end of commercial validity is reached and trusted state is updated

Then the Subscription becomes `EXPIRED`
And normal paid Entitlement validity can no longer rely on that Subscription

---

### Scenario: Subscription expires after unrecovered payment failure

Given Animalia's Subscription is `PAST_DUE`
And the commercial issue is not resolved
And trusted commercial information establishes that validity has ended

When the Subscription state is updated

Then the Subscription becomes `EXPIRED`
And the historical `PAST_DUE` condition remains conceptually distinguishable

---

### Scenario: Expiration does not delete historical medical information

Given Animalia has finalized Clinical Record Entries for Luna
And Animalia's Subscription later becomes `EXPIRED`

When Luna's longitudinal medical history is viewed by an authorized User

Then Animalia's historical clinical contributions remain part of Luna's
medical history
And their provenance remains unchanged

---

### Scenario: Expiration does not delete Appointment history

Given Animalia has historical Appointments
And its Subscription becomes `EXPIRED`

When historical Appointment information is evaluated

Then the Appointments remain identifiable
And commercial expiration does not delete them

---

### Scenario: Expiration does not end Organization Membership

Given Maria has an active Membership in Animalia Veterinary Group
And Animalia's Subscription becomes `EXPIRED`

When Maria's Organization Membership is evaluated

Then the Membership remains historically and currently governed by the
Organization Membership lifecycle
And Subscription expiration does not automatically end it

---

### Scenario: Expiration does not erase Clinic Assignments

Given Dr. Garcia has a Clinic Assignment at Animalia Madrid Centro
And Animalia's Subscription becomes `EXPIRED`

When historical professional relationships are evaluated

Then the Clinic Assignment remains identifiable
And Subscription expiration does not delete the professional relationship

---

### Scenario: Duplicate provider state event is idempotent

Given Animalia's Subscription is already `ACTIVE`
And the same trusted commercial event confirming that state is delivered again

When the event is processed

Then no duplicate Subscription is created
And no misleading duplicate state transition is created

---

### Scenario: Stale provider event does not overwrite newer state

Given Animalia's Subscription has already transitioned to a newer authoritative
commercial state
And an older delayed provider event later arrives

When the old event is evaluated

Then the system must not blindly replace the newer authoritative state with
stale commercial information

---

### Scenario: Cancellation does not revoke Care Authorization

Given Luna has a valid Care Authorization with Animalia Madrid Centro
And Animalia's Organization Subscription becomes `CANCELLED`

When the Care Authorization record is evaluated

Then the Care Authorization is not deleted or rewritten solely because of
Subscription cancellation
And professional capability availability is evaluated separately

---

## 7. State vs Entitlement

Subscription state answers:

    What is the Organization's current commercial condition?

Entitlement answers:

    What paid professional behavior is currently permitted?

These must remain distinct.

For example:

    ACTIVE
    → normal paid Entitlements may apply

    PAST_DUE
    → some or no Entitlements may apply depending on policy

    CANCELLED but still commercially valid
    → Entitlements may remain until validity ends

    EXPIRED
    → normal paid Entitlements no longer apply

The exact capability mapping is defined by `SPEC-SUB-003`.

---

## 8. Commercial History

The system must preserve enough information to understand commercial periods.

For example:

    Animalia Veterinary Group

    2026-01-01
    ACTIVE

    2026-08-12
    PAST_DUE

    2026-08-14
    ACTIVE

    2026-09-10
    CANCELLED

    Commercially valid until:
    2026-09-30

    2026-10-01
    EXPIRED

This history must not rewrite medical or professional history.

---

## 9. Edge Cases

### Provider exposes additional states

An external commercial provider may expose states more detailed than the Phase
1 domain taxonomy.

The architecture may normalize provider-specific states into the supported
domain Subscription model.

Provider-specific terminology must not automatically become permanent domain
language.

---

### Payment retry is in progress

A payment retry process may correspond to `PAST_DUE` or another future
commercial interpretation.

The Phase 1 domain should avoid modeling provider-specific retry mechanics as
core Subscription states unless required by product behavior.

---

### Cancellation is reversed before expiration

A commercial provider may allow renewal cancellation to be reversed before the
current paid period ends.

Phase 1 does not support that workflow: `CANCELLED → ACTIVE` is not an accepted
transition (§5, §14). Supporting it later requires a Specification change.

---

### Organization re-subscribes after expiration

`EXPIRED` is terminal for that Subscription period. Restarting service
establishes a new Subscription period through trusted establishment
(`SPEC-SUB-001`); the expired Subscription is never reactivated. The historical
expired period and any gap in commercial validity are preserved.

---

### Commercial provider temporarily unavailable

Temporary inability to query an external provider must not automatically
change Subscription state to `EXPIRED`.

The architecture must distinguish:

    commercial state known to be invalid

from:

    authoritative commercial state temporarily unavailable

Caching and synchronization policy are architectural concerns.

---

## 10. Relevant Invariants

- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-SUB-001 — Establish Organization Subscription
- SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
- SPEC-ID-003 — Authenticate User

Professional Entitlement behavior is defined separately.

---

## 12. Out of Scope

This Specification does not define:

- professional Entitlement mapping;
- future commercial grace-period behavior beyond Phase 1;
- payment retry strategy;
- invoices;
- refunds;
- taxes;
- payment methods;
- provider-specific billing states;
- Subscription plans;
- usage limits;
- cancellation UI;
- billing notifications;
- commercial provider selection;
- webhook implementation.

---

## 13. Verification Notes

Verification must demonstrate that:

1. every Organization Subscription has an explicit current state;
2. trusted backend or commercial information determines Subscription state;
3. `PENDING` does not imply normal paid Entitlements;
4. `ACTIVE` represents normal current commercial validity;
5. `PAST_DUE` remains distinct from `ACTIVE` and `EXPIRED`;
6. recoverable payment failure may transition back to `ACTIVE`;
7. `CANCELLED` does not necessarily mean immediate loss of commercial validity;
8. cancellation and expiration remain distinct;
9. `EXPIRED` does not satisfy normal current commercial validity;
10. controlled transitions preserve the same Subscription identity;
11. duplicate commercial events do not create duplicate logical transitions;
12. stale events do not silently overwrite newer authoritative state;
13. Subscription transitions preserve Organization Membership and Clinic
    Assignment history;
14. Subscription transitions do not delete Appointments;
15. Subscription transitions do not delete or rewrite medical history;
16. Care Authorization history is not erased by commercial state changes;
17. audit history survives commercial termination;
18. cancellation time and commercial expiration time remain distinguishable;
19. Subscription state and professional Entitlement remain separate concepts;
20. state transitions behave atomically;
21. every transition in the §5 graph is accepted and every other pair,
    including same-state transitions, is rejected;
22. no transition leaves `EXPIRED`;
23. a transition whose effective time is later than the current instant is
    rejected, and one at exactly the current instant is accepted;
24. an open-ended `ACTIVE` Subscription keeps its state and its normal
    Entitlements until an explicit trusted transition changes it, with no
    scheduler or implicit state change;
25. omitted validity on a transition is not inherited from an earlier state
    fact;
26. `PENDING → EXPIRED` is accepted and `PENDING → CANCELLED` and
    `PENDING → PAST_DUE` are rejected.

---

## 14. Phase 1 manual commercial policy (Subscription Operational Safety)

Approved for the Phase 1 manually managed commercial model:

- **Open-ended manual `ACTIVE`.** An `ACTIVE` Subscription may deliberately
  have no commercial-validity end. It remains commercially active until an
  explicit trusted transition changes its state. Ordinary manually managed
  `ACTIVE` Subscriptions need no periodic renewal. Finite validity remains
  representable where a real commercial end boundary is known.
- **No periodic renewal operation.** There is no `ACTIVE → ACTIVE` renewal or
  extension transition, renewal must never be simulated through
  `ACTIVE → PAST_DUE → ACTIVE`, and immutable establishment facts are never
  mutated. Periodic billing and renewal are designed later with provider
  integration.
- **Explicit transition graph** as in §5. `EXPIRED` is terminal for that
  Subscription period; restarting service requires a new Subscription period.
  `PAST_DUE → ACTIVE` is recovery of the same commercial relationship.
  `PENDING → EXPIRED` permanently closes a relationship that never became
  active; there is no `PENDING → CANCELLED`.
- **Initial state.** A Subscription is established only as `PENDING` or
  `ACTIVE`, with an initial effective time not later than the establishment
  instant (`SPEC-SUB-001` §14).
- **No future-dated transitions.** A transition's effective time must be
  strictly later than the current state's effective time and not later than
  the current instant. End-of-period cancellation is a `CANCELLED` transition
  carrying an explicit commercial-validity end, never a future-dated
  transition.
- **`PAST_DUE`.** No grace period and no normal Entitlements (`SPEC-SUB-003`
  BR-12); no automatic timed expiry; no automatic recovery. A trusted operator
  resolves it explicitly with `PAST_DUE → ACTIVE` or `PAST_DUE → EXPIRED`. Its
  maximum duration is not automated in Phase 1.
- **Validity is carried by each transition** and is never inherited; an
  omitted end means none for the resulting state.
- **Transitions remain trusted.** Only the trusted commercial operation may
  apply them; no client role can.
---

## 15. View Organization Subscription status (Phase 1)

Authorized Organization management may read the Organization's current
commercial status without any billing or provider detail.

### Operation contract

    get_organization_subscription_status(p_organization_id uuid) returns jsonb

- **Callers.** `authenticated` only. The acting User comes from the
  authenticated subject; no subject, or no coherent domain User, fails with
  `28000`.
- **Authorization.** Requires `ORGANIZATION_MANAGE_SUBSCRIPTION` in that
  Organization (`SPEC-ORG-005`). It is decided before any Organization fact is
  read: a nonexistent Organization and one the caller may not manage fail
  identically with `42501`.
- **No Entitlement** is required to read it (`SPEC-SUB-003` BR-41).
- **Read-only**, non-locking, one evaluation instant.

### Result

    {
      "organization_id": uuid,
      "organization_display_name": text,
      "subscription": null | {
        "state": "PENDING" | "ACTIVE" | "PAST_DUE" | "CANCELLED" | "EXPIRED",
        "state_effective_at": timestamptz,
        "valid_from": timestamptz | null,
        "valid_until": timestamptz | null
      },
      "entitlements": {
        "APPOINTMENT_MANAGEMENT": boolean,
        "PROFESSIONAL_SCHEDULING": boolean,
        "CLINICAL_CARE": boolean,
        "CLINICAL_DOCUMENTATION": boolean
      }
    }

- `subscription` describes the Organization's current Subscription
  relationship (its non-`EXPIRED` Subscription). Without one, it describes the
  Organization's most recently established Subscription period, whose state is
  then `EXPIRED`. It is `null` only when the Organization never had a
  Subscription.
- `state` is the stored, derived Subscription state. It is never replaced by an
  inferred state: an `ACTIVE` Subscription whose validity end has passed is
  reported as `ACTIVE`, with `valid_until` in the past.
- `entitlements` reports current Entitlement availability evaluated by
  `SPEC-SUB-003` at the same instant. Stored state and current Entitlement
  availability are deliberately reported separately.
- The result never contains provider names or references, source systems,
  source event keys, establishment sources, idempotency keys, initiating Users,
  internal Subscription identifiers, or any other commercial correlation data.

### Boundaries

- `SPEC-ORG-007` professional context continues to exclude commercial dates and
  provider information; this operation is the only Phase 1 read of
  Subscription state.
- Guardians and anonymous viewers never receive Subscription state, validity,
  or billing information (`SPEC-SUB-003` §15).

### Presentation

The professional management surface shows the state with calm customer-facing
labels (Pending, Active, Payment issue, Cancelled, Expired), shows validity
dates only when present, shows no end or renewal date for an open-ended
`ACTIVE`, and shows service availability separately from the state.

### Verification

1. `ORGANIZATION_MANAGE_SUBSCRIPTION` holders read their Organization only;
   other roles, other Organizations, and unknown Organizations fail
   identically with `42501`;
2. unauthenticated or incoherent callers fail with `28000`;
3. no Subscription, `PENDING`, open-ended `ACTIVE`, finite current `ACTIVE`,
   finite lapsed `ACTIVE`, `PAST_DUE`, `CANCELLED` within and after validity,
   and `EXPIRED` are each reported with their stored state and the matching
   Entitlement availability;
4. a lapsed `ACTIVE` is never reported as `EXPIRED`;
5. no provider, source-event, or internal commercial data is returned.

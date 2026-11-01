# ADR-006 — Derive Current Subscription State from Initial Facts and Append-Only Transitions

**Status:** ACCEPTED

## Context

The Phase 1 Subscription model requires a provider-independent commercial
relationship belonging to a Veterinary Organization, an identifiable current
commercial state, effective commercial timing, append-only State Transition
history, idempotent trusted updates, and safe behavior when an external
commercial provider is unavailable.

The approved relational model permits current Subscription state to be either a
coherent stored projection or a coherent derivation. It also permits
Subscription establishment without creating an initial State Transition row.

The physical architecture must therefore choose how current truth is derived,
how accepted commercial events are ordered, how one current relationship is
enforced, and how duplicate or stale events are handled without coupling domain
identity to a commercial provider.

## Decision

### Provider-independent Subscription identity

`organization_subscriptions` provides the stable domain Subscription identity
and belongs to exactly one Veterinary Organization. External customer and
subscription identifiers remain subordinate operational mappings in
`subscription_provider_references`.

Provider references do not replace domain Subscription identity. Phase 1 does
not require provider-global uniqueness for those references.

### Initial state and derived current state

`organization_subscriptions` stores immutable initial trusted state facts,
including the initial normalized state, its effective time, and its applicable
commercial-validity context.

Establishment creates zero `subscription_state_transitions` rows.

Current Subscription state is the initial state when no accepted Transition
exists. Otherwise, it is the `to_state` of the accepted Transition with the
greatest `effective_at` for that Subscription.

The Subscription row does not store a mutable current-state projection,
current-state effective time, relationship-end marker, or current-Subscription
boolean.

### Accepted Transition ordering

`effective_at` is the authoritative business-ordering signal.
`recorded_at` records persistence or receipt timing only.

For one Subscription:

- each newly accepted Transition has an `effective_at` strictly later than the
  currently accepted state fact;
- the trusted operation derives `from_state` from current truth;
- `to_state` differs from current state;
- competing Transitions with equal effective times are rejected as ambiguous;
- a later-arriving event with an older effective time is stale and cannot
  become current;
- rejected stale deliveries are not authoritative State Transition rows.

No provider monotonic sequence is assumed. The database preserves normalized
states, ordering, timing, idempotency, and current-state coherence; the
approved Phase 1 transition graph and the no-future-transition rule below are
enforced by the trusted operation and by the Transition insert trigger.

### Phase 1 transition graph (amendment — Subscription Operational Safety)

Phase 1 accepts exactly these trusted transitions:

    PENDING   → ACTIVE   | EXPIRED
    ACTIVE    → PAST_DUE | CANCELLED | EXPIRED
    PAST_DUE  → ACTIVE   | EXPIRED
    CANCELLED → EXPIRED

Every other pair is rejected, including same-state transitions,
`CANCELLED → ACTIVE`, `PENDING → CANCELLED`, `PENDING → PAST_DUE`, and any
transition out of `EXPIRED`. `EXPIRED` is terminal for that Subscription
period. `PENDING → EXPIRED` is the terminal closure of a commercial
relationship that never became active: the Subscription never provided
commercial validity and is now permanently closed. Adding an edge requires a
Specification change first.

### Phase 1 initial state

A newly established Subscription starts only as `PENDING` or `ACTIVE`, and its
initial state's effective time must not be later than the establishment
statement instant (`<= statement_timestamp()`; the exact instant is valid).
Establishment never starts a Subscription as `PAST_DUE`, `CANCELLED`, or
`EXPIRED`, and never records a future-dated initial state. Exact replays of an
already established Subscription keep their idempotent result.

There is no `ACTIVE → ACTIVE` renewal or extension transition, and immutable
establishment facts are never mutated. `PAST_DUE → ACTIVE` is recovery of the
same commercial relationship, not renewal.

### No future-dated transitions in Phase 1

A newly accepted Transition must satisfy both:

- `effective_at` strictly later than the current state's effective instant;
- `effective_at <= statement_timestamp()` (the exact current instant is valid).

Scheduled future transitions are not supported. End-of-period cancellation is
represented by a `CANCELLED` Transition whose `commercial_valid_until` records
the end of already-valid coverage, never by a future-dated Transition.

### Validity per Transition

Each Transition records its own `commercial_valid_from` and
`commercial_valid_until`. Omitted values are absent for the resulting state;
they are never inherited from an earlier state fact.

### One current professional Subscription relationship

A Subscription occupies the Veterinary Organization's single current
professional Subscription relationship while its derived state is `PENDING`,
`ACTIVE`, `PAST_DUE`, or `CANCELLED`. An `EXPIRED` Subscription does not occupy
that relationship.

At most one non-`EXPIRED` Subscription relationship may exist for one
Organization. Trusted establishment and state-change operations serialize on
the Organization and applicable Subscription. Database-level deferred
integrity also protects the invariant.

A `CANCELLED` Subscription may stop providing Entitlement when its known
commercial-validity period ends while still occupying the current relationship
until trusted commercial state records `EXPIRED`.

Restarting service after `EXPIRED` establishes a new Subscription period (a
new domain Subscription) through trusted establishment. The expired period is
never reactivated and its history, including any validity gap, is preserved.

### Commercial validity

Commercial validity uses half-open semantics:

    [commercial_valid_from, commercial_valid_until)

Either bound may be absent. Stored timestamps are finite; PostgreSQL infinity
values are not domain values.

Phase 1 manual commercial policy: an `ACTIVE` Subscription may deliberately
have no `commercial_valid_until`. That is an approved open-ended commercial
state, not missing data: it remains commercially active until an explicit
trusted Transition changes its state, and needs no periodic renewal. Finite
validity remains representable where a real commercial end boundary is known.
Nothing creates a `commercial_valid_until` automatically.

`effective_at` records when the normalized state becomes effective. For a
Transition to `CANCELLED`, it also preserves the cancellation-effective time.
`commercial_valid_until` separately records the end of already-valid
commercial coverage. No duplicate `cancellation_at` field is required.

No wall-clock-dependent table constraint or index is used.

### Transition idempotency

Subscription establishment uses one required trusted-workflow UUID idempotency
key. Exact retries recognize the existing logical result; contradictory reuse
of the same key is rejected.

Accepted State Transitions may contain a required `source_system` and an
optional `source_event_key`. When an event key exists, uniqueness is scoped to:

    subscription_id
    + source_system
    + source_event_key

It is not global across all domain Subscriptions.
The uniqueness rule applies only where `source_event_key` is present.

Reuse of the same scoped event key with contradictory normalized facts is
rejected. When no stable source event key exists, semantic duplicate detection
runs under the Organization and Subscription locks. Exact normalized semantics
include at least Subscription, source system, effective time, resulting state,
and resulting commercial-validity context. `recorded_at` does not participate
in semantic idempotency.

An exact retry is a successful no-op or existing-result recognition. A stale
older-effective event or equal-effective conflicting event is rejected. A
later coherent event may append exactly one Transition.

Slice 7 does not introduce a provider-event inbox.

### Local trusted facts and provider unavailability

The latest accepted local trusted commercial fact remains authoritative until
a later trusted commercial fact replaces it or an explicit stored
`commercial_valid_until` boundary is reached.

Provider unavailability alone does not create `EXPIRED` or `PAST_DUE`, mutate
Subscription state, fabricate a Transition, or prove authoritative commercial
invalidity. A known validity boundary may deny normal Entitlement without
fabricating a new provider state.

`recorded_at` does not establish a maximum-cache-age policy. Slice 7 adds no
provider polling interval, webhook freshness time-to-live, retry policy,
provider-outage table, or synchronization-cache table.

### Entitlement derivation

Professional Entitlement remains derived from the requested normalized
Entitlement identifier, Veterinary Organization, authoritative current
Subscription state and validity, and Phase 1 commercial policy.

Phase 1 introduces no authoritative Entitlement table, policy table,
provider-product mapping, paid-access boolean, or persisted Entitlement
decision.

## Consequences

### Positive

- initial state remains meaningful without a synthetic initial Transition;
- current truth and append-only commercial history cannot drift through a
  duplicated mutable projection;
- effective ordering and stale-event rejection are provider-independent;
- retries are harmless without requiring provider-global event identifiers;
- provider outages remain distinguishable from known commercial invalidity;
- expired periods stay distinct history; restarting service never rewrites
  them.

### Negative

- current-state evaluation must combine initial facts with the latest accepted
  Transition;
- protected operations need transaction-safe evaluation and locking;
- deferred cross-row integrity is required for the one-current-relationship
  invariant;
- rejected provider deliveries are not durably retained unless later technical
  inbox infrastructure is approved;
- future provider integration must normalize its states and events before
  invoking the trusted domain operation.

## Alternatives Considered

### Store a mutable current-state projection

Rejected for Phase 1 because it would duplicate authoritative state and require
every Transition append to remain atomically coherent with mutable projection
fields.

### Require an initial State Transition row

Rejected because establishment already has immutable initial facts and the
approved relational model does not require a synthetic initial Transition.

### Use globally unique provider event keys

Rejected because Phase 1 has not established that identifiers from every
commercial source are globally unique across all domain Subscriptions.

### Add a provider-event inbox in Slice 7

Rejected because no approved Phase 1 provider integration requires raw delivery
retention, webhook processing, retry coordination, or provider-specific event
reconciliation yet.

## Intentionally Unresolved or Later

- commercial provider selection and integration;
- webhook or technical inbox infrastructure;
- provider polling and retry behavior;
- provider-global identifier uniqueness;
- periodic billing and renewal semantics (designed with provider integration);
- checkout, payment, invoice, refund, tax, pricing, and plan architecture;
- future synchronization or freshness-policy changes if approved product
  requirements evolve.

## Related Documentation

- REQ-SUB-001 through REQ-SUB-004
- SPEC-SUB-001 — Establish Organization Subscription
- SPEC-SUB-002 — Maintain Organization Subscription State
- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-SUB-004 — Handle Loss of Professional Entitlements
- `docs/RELATIONAL_MODEL.md`

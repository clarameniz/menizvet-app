# ADR-008 — Durable and Session-Safe Communications Handoff

**Status:** ACCEPTED

## Context

Transactional email and push reflect authoritative Invitation and Appointment
operations, but provider calls cannot participate in the PostgreSQL transaction
that establishes those operations. Calling a provider inline could either lose
the Communication after a committed domain operation or deliver a message for a
domain operation that later rolls back.

Invitation acceptance credentials must cross the asynchronous boundary without
being stored in plaintext. Private push destinations must also cease being
eligible when the authentication session that registered them no longer exists,
including after sign-out or account recovery.

These requirements must not make any email or push provider part of domain
identity or authoritative domain state.

## Decision

Supported domain operations establish a typed Transactional Communication in
the same database transaction as the authoritative origin. The Communication
references that origin and one intended recipient; logical-origin uniqueness
makes handoff retry-safe without repeating the domain operation.

Invitation creation uses a trusted replacement command. It creates the
Invitation and its email-only Communication atomically. The one-time acceptance secret is stored in the Communication only as a versioned AES-256-GCM envelope with authenticated context and a separately versioned deployment key. The plaintext is available only in trusted Edge memory while creating or rendering the handoff. The encrypted payload may be erased once the supported delivery and retry workflow no longer requires the Invitation credential. The exact Phase-1 erasure point is operational policy and must never extend or replace the underlying Invitation authorization. Key material is deployment configuration and is never stored in the repository or database.

Invitations created before the Slice 14 cutover whose plaintext credential is no longer available are treated as legacy records. They are not backfilled with a fabricated encrypted credential or Communication history, and their one-way digest is never treated as reversible. New Invitation creation after cutover must use the durable handoff path.

A Push Registration belongs to one domain User and one concrete authentication
session. Registration and every private push claim require the stored session
identifier to match a current `auth.sessions` row for the linked authentication
subject. Absence of that session makes the destination ineligible without
changing User identity, Guardianship, or other domain state.

Provider delivery is asynchronous and isolated by channel. A mutable Delivery
Job is a non-authoritative operational queue projection used only for leases,
retry, and current provider feedback. Every actual provider submission appends
an immutable Delivery Attempt; retained Attempts are never rewritten or
deleted. An email failure never blocks supplementary
push, a push failure never blocks baseline email, and neither failure rolls back
the originating operation. Provider callbacks and receipt processing update
technical delivery state monotonically and cannot mutate domain lifecycle.

The outbox, Push Registration, encryption-envelope, and Delivery Attempt
contracts remain provider-independent. Provider adapters, credentials,
commercial plans, prices, quotas, and provider-specific status mappings are
operational choices outside this ADR.

## Consequences

### Positive

- a committed supported domain operation cannot silently omit its required
  Communication intent;
- retry and provider callbacks cannot repeat Invitation or Appointment
  operations;
- pre-recovery and signed-out sessions fail the server-side private-push gate;
- Invitation credentials are not persisted in plaintext and are erased after
  successful provider handoff;
- email and push can fail, retry, and migrate independently;
- provider identifiers remain integration references rather than domain
  identities.
- mutable queue state cannot rewrite append-only provider-attempt history.

### Negative

- dispatch requires a maintenance scheduler and operational monitoring;
- encrypted Invitation handoff requires deployment key rotation and retention
  discipline while an envelope remains pending;
- a provider with no send-idempotency primitive may produce duplicate
  supplementary push after an ambiguous timeout;
- provider acceptance and device delivery remain distinct technical facts;
- session removal is evaluated at dispatch, so stale Push Registration rows may
  remain for history even though they are no longer eligible.

## Alternatives Considered

### Call providers inline from domain operations

Rejected because provider latency and failure would couple external
infrastructure to domain commit, while a post-commit crash could still lose the
message.

### Store only a mutable notification status on the origin

Rejected because it collapses domain truth and Communications, cannot represent
independent channels or devices, and obscures delivery history.

### Bind push only to User or device

Rejected because a lost device could retain private notification eligibility
after sign-out or recovery invalidates its authentication session.

### Persist an Invitation plaintext secret for later rendering

Rejected because the asynchronous handoff does not require plaintext at rest.

## Related Documentation

- SPEC-COM-001 — Send Transactional Email
- SPEC-COM-002 — Send Push Notification
- SPEC-COM-003 — Send Appointment Notifications
- SPEC-ID-005 — Recover Account Access
- `docs/ARCHITECTURE.md`
- `docs/RELATIONAL_MODEL.md`
- `docs/COMMUNICATIONS_OPERATIONAL_POLICY.md`
- `docs/COMMUNICATIONS_BACKEND.md`

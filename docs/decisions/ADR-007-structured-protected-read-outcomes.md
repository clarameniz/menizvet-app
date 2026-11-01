# ADR-007 — Structured Protected-Read Outcomes for Durable Denial Auditing

**Status:** ACCEPTED

## Context

Protected medical reads must preserve a Medical Access Audit Event for both
permitted access and authenticated security-relevant denial where the audit
policy requires it. ADR-004 also requires protected information to remain
unavailable when required audit evidence cannot be durably captured.

PostgreSQL exceptions abort the current transaction. A protected-read function
that inserted a `DENIED` Medical Access Audit Event and then raised an
authorization exception would therefore roll back the evidence it was required
to preserve.

The architecture needs one trusted transaction contract that keeps denial
authoritative, makes required denial evidence durable, and does not release
protected information before permitted evidence is committed.

## Decision

Protected medical PostgreSQL RPCs return an explicit structured domain outcome:

- `PERMITTED`; or
- `DENIED`.

A normal authorization denial does not raise inside the protected-read database
transaction. The RPC inserts the required `DENIED` Medical Access Audit Event
and returns `DENIED` normally so both the result and its audit evidence can
commit. A `DENIED` result contains no protected payload, protected metadata, or
continuation cursor.

For permitted access, the trusted operation authorizes the bounded protected
scope, constructs only that scope, inserts the required `PERMITTED` Medical
Access Audit Event, and returns the structured `PERMITTED` result. The
transaction and its required audit evidence must commit before the protected
payload is released to the caller.

Infrastructure, persistence, integrity, and required audit-capture failures
still raise and abort the transaction. They return no protected payload.
Failure to persist a denied event never converts denial into permission.

Clients cannot directly write authoritative Medical Access Audit Events. The
client, Edge, or application boundary may translate a structured `DENIED`
domain outcome into the applicable transport status and authorization-error
experience, but no HTTP status is a database invariant.

This contract applies to future protected medical PostgreSQL reads unless a
later deliberate architectural decision supersedes it.

## Transaction Semantics

Conceptually, a denied protected read is:

    authorize = false
        +
    required DENIED audit event inserted
        +
    structured DENIED result returned
        ↓
    commit

A permitted protected read is:

    authorize = true
        +
    bounded protected result constructed
        +
    required PERMITTED audit event inserted
        ↓
    commit
        ↓
    release protected result

An audit-persistence or infrastructure failure is:

    error
        ↓
    rollback
        ↓
    no protected result

## Consequences

### Positive

- required denial evidence survives the normal denial path;
- denial never becomes permission because audit capture failed;
- permitted information is not released before required audit evidence commits;
- the trusted database operation owns authorization and authoritative audit
  capture coherently;
- clients receive a stable domain outcome without becoming authoritative audit
  writers.

### Negative

- callers must distinguish a structured domain denial from infrastructure and
  input failures;
- protected-read response types differ from exception-only RPC conventions;
- application and transport layers must map the domain result without exposing
  internal authorization detail.

## Alternatives Considered

### Raise an authorization exception after inserting the denied event

Rejected because PostgreSQL transaction rollback would erase the required
`DENIED` Medical Access Audit Event.

### Use autonomous transaction mechanisms

Rejected. Phase 1 does not introduce `dblink`, `pg_background`, autonomous
transaction assumptions, or equivalent transaction-bypass mechanisms for
medical audit capture.

### Require two-transaction Edge orchestration

Rejected as a mandatory platform contract. It would separate authorization and
audit capture across additional trusted orchestration when the structured
single-transaction domain result provides the required durability.

### Let clients record denied events

Rejected because clients are not a trusted security boundary and cannot be the
authoritative source of Medical Access Audit Events.

## Related Documentation

- ADR-002 — Use Domain-Level Medical Access Auditing
- ADR-004 — Fail Closed When Required Medical Audit Cannot Be Durably Captured
- ADR-005 — Use Context-Dependent Medical Audit Correlation
- SPEC-ACC-003 — Record Medical Access Audit Event
- SPEC-MED-005 — View Pet Medical History
- `docs/ARCHITECTURE.md`
- `docs/RELATIONAL_MODEL.md`

# ADR-004 — Fail Closed When Required Medical Audit Cannot Be Durably Captured

**Status:** ACCEPTED

> **Partial supersession notice:**
> [ADR-005 — Use Context-Dependent Medical Audit Correlation](ADR-005-context-dependent-medical-audit-correlation.md)
> supersedes only this ADR's unconditional Audit Correlation requirement. All
> other decisions in this ADR remain accepted and applicable. The original text
> is retained below as decision history.

## Context

The platform handles protected veterinary medical information.

Approved Requirements require:

- traceability of clinically and security-relevant actions;
- medical-access auditability where auditing is required;
- server-side authorization enforcement;
- preservation of historical medical information.

ADR-002 establishes that Medical Access Audit Events represent meaningful
domain-level access operations rather than every low-level database or
infrastructure action.

The remaining architectural question is what should happen when an operation
that requires a Medical Access Audit Event is otherwise valid but the audit
event cannot be durably persisted.

Allowing such an operation to succeed would create protected medical activity
that the architecture explicitly required to be traceable.

At the same time, failure of an external monitoring or log-exporting service
must not unnecessarily make clinical workflows unavailable when the required
audit evidence has already been durably captured.

---

## Decision

Operations explicitly classified as requiring a Medical Access Audit Event
must use fail-closed audit semantics.

A successful audit-required protected operation must not become externally
successful unless the required audit evidence has been durably captured.

Conceptually:

    authorization valid
          +
    protected operation valid
          +
    required audit durably captured
          ↓
    operation may succeed

If required audit evidence cannot be durably captured:

    protected operation
          ↓
    must not succeed

This requirement applies to the authoritative audit capture, not to every
secondary logging or observability integration.

---

## Durable Audit Capture

For Phase 1, required audit evidence must be committed through trusted
infrastructure.

Where the protected operation mutates domain state, the domain change and its
required audit event must commit coherently.

Conceptually:

    domain mutation
          +
    audit event
          ↓
    one coherent commit

The system must not expose:

    clinical/security-sensitive change committed
        +
    required audit event missing

or:

    audit event claims operation succeeded
        +
    protected mutation rolled back

The exact transaction, trusted PostgreSQL function, backend operation, or
equivalent mechanism is implementation architecture.

---

## Audited Read Operations

An audit-required read of protected medical information has no corresponding
domain mutation to commit.

For such operations, the required audit event must be durably captured before
the protected information is released to the caller.

Conceptually:

    authorize request
          ↓
    determine permitted protected scope
          ↓
    durably record permitted access
          ↓
    release protected information

If durable audit capture fails, the protected information must not be returned
through that audited operation.

---

## Denied Access

Authorization denial remains authoritative even if persistence of a denied
audit event fails.

The system must never convert:

    DENIED

into:

    PERMITTED

because audit persistence failed.

Where a denied access attempt is itself required to be audited, trusted
infrastructure should attempt to preserve the denial event.

If that audit write cannot be persisted:

- protected information remains unavailable;
- the authorization denial remains effective;
- operational diagnostics must surface the audit-persistence failure.

A failed denial-audit write therefore cannot cause protected access to be
granted.

---

## Audit Correlation

Each meaningful protected domain operation must receive a trusted operation
correlation identifier.

The identifier is generated or established by trusted backend infrastructure.

It must not rely on an arbitrary client-provided value as its authoritative
identity.

The correlation identifier allows related technical activity and audit
evidence to be associated with the same domain operation.

For example:

    operation correlation
        │
        ├── authorization evaluation
        ├── protected medical query
        ├── Medical Access Audit Event
        └── operational diagnostics

A correlation identifier is not:

- User identity;
- Pet identity;
- Appointment identity;
- Clinical Encounter identity;
- Care Authorization identity.

Those domain relationships remain explicitly represented.

---

## Domain-Level Audit Granularity

Medical Access Audit Events remain domain-level events according to ADR-002.

One meaningful operation must not generate separate required audit events merely
because the implementation performs several:

- SQL statements;
- joins;
- storage reads;
- authorization checks;
- network calls.

For example:

    View relevant longitudinal history for Luna
    while preparing Animalia Madrid Centro care

may produce one meaningful access-audit event even though the implementation
reads several clinical records.

This does not prevent technical logging from recording lower-level operations.

---

## Phase 1 Audit-Required Medical Access

At minimum, Phase 1 must treat professional or operational access to protected
Pet medical information through a Care Authorization as audit-relevant when
the applicable Medical Access Specification requires auditing.

This includes particularly sensitive access such as:

- professional access to longitudinal medical history;
- cross-Clinic medical-history access;
- operational access to protected medical information for triage or
  professional assignment where such access is permitted;
- other protected medical-access operations explicitly classified as
  audit-required by approved Specifications.

The architecture must not infer that every database read is a separate Medical
Access Audit Event.

Guardian-facing medical-history access and other future access categories must
follow their applicable approved Specifications rather than being silently
classified here.

---

## Audit Event Content

A Medical Access Audit Event must preserve enough context to establish the
meaningful access that occurred.

Where applicable, the event should identify:

- acting User or trusted process;
- Pet;
- operation;
- access outcome;
- access purpose;
- effective time;
- Clinic;
- Veterinary Organization;
- applicable Care Authorization;
- applicable professional or operational context;
- protected resource scope;
- operation correlation identifier.

Specific protected resources such as:

- Clinical Encounter;
- Clinical Record Entry;
- Clinical Amendment;
- Clinical Attachment;

may also be referenced where required.

Audit events must not unnecessarily duplicate complete clinical payloads.

---

## Audit Outcome

The audit model must distinguish at least:

- `PERMITTED`;
- `DENIED`.

A `PERMITTED` event means that the audited protected operation was authorized
and allowed to proceed.

A `DENIED` event means that the protected operation was refused.

The audit event must not itself grant authorization.

---

## Append-Only History

Medical Access Audit Events are historical evidence.

Ordinary application workflows and audited actors must not:

- edit an existing audit event;
- delete an audit event;
- change its acting User;
- change its Pet;
- change its original outcome;
- rewrite its historical time.

If future operational or legal requirements require correction of erroneous
audit metadata, correction must preserve the original event and use an
append-only corrective relationship or equivalent auditable mechanism.

The exact correction workflow is outside Phase 1 unless separately specified.

---

## Retention

Medical audit information must not be deleted through ordinary lifecycle
changes involving:

- User;
- Organization Membership;
- Clinic Assignment;
- Care Authorization;
- Subscription;
- Pet Guardianship.

The exact legal retention period is not established by this ADR.

Retention and deletion must follow the applicable data-protection and legal
policy when formally defined.

The persistence model must therefore avoid accidental cascading deletion of
medical audit evidence.

---

## External Observability Failure

Medical audit persistence and external observability are separate concerns.

Once the required Medical Access Audit Event has been durably captured,
temporary failure of:

- monitoring;
- analytics;
- external log shipping;
- dashboards;
- alerting integrations

must not retroactively invalidate the successful protected domain operation.

Such failures must be observable and retryable where applicable.

---

## Emergency Access

Phase 1 does not define an emergency or break-glass medical-access mechanism.

Therefore this ADR does not introduce an audit bypass for urgent access.

If future approved requirements introduce emergency access, they must
explicitly define:

- authorization;
- audit guarantees;
- failure behavior;
- exceptional availability semantics.

---

## Consequences

### Positive

- audit-required protected operations cannot silently become unaudited;
- protected reads cannot disclose data when required audit capture fails;
- clinical mutations and their required audit evidence remain coherent;
- low-level logging failures do not unnecessarily block domain behavior;
- external observability outages do not become medical-access outages once
  durable audit capture has succeeded;
- audit history remains append-only and attributable.

### Negative

- failure of the authoritative audit persistence path can make an
  audit-required protected operation unavailable;
- audit persistence becomes part of the critical path for those operations;
- transactional boundaries must be designed carefully;
- future emergency-access behavior will require an explicit exception model.

---

## Alternatives Considered

### Fail open when audit persistence fails

The protected operation succeeds and missing audit evidence is repaired or
reported later.

Rejected for audit-required Phase 1 medical access because it permits the
system to perform operations that were explicitly required to be traceable
without durable evidence that they occurred.

### Depend on an external logging provider synchronously

Require successful delivery to a third-party logging or observability provider
before protected operations can succeed.

Rejected because external monitoring availability must not become the primary
availability boundary for veterinary workflows.

Durable first-party capture is sufficient for the domain operation; external
delivery may occur separately.

### Audit every database operation

Rejected by ADR-002.

Medical access auditing represents meaningful domain operations rather than
every infrastructure read or SQL statement.

---

## Related Requirements and Decisions

- REQ-ACC-007 — Medical access auditability
- REQ-AUD-001 — Sensitive action auditability
- REQ-NFR-003 — Data integrity
- REQ-NFR-005 — Auditability
- REQ-NFR-012 — Observability
- ADR-002 — Use Domain-Level Medical Access Auditing

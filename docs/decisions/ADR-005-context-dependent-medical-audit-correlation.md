# ADR-005 — Use Context-Dependent Medical Audit Correlation

**Status:** ACCEPTED

## Context

ADR-004 established fail-closed behavior when required Medical Access Audit
Events cannot be durably captured. Its Audit Correlation section also required
every meaningful protected domain operation in scope to receive a trusted
operation correlation identifier.

The approved Phase 1 relational design distinguishes the semantic need to
correlate related audit activity from any universal relational representation.
Some meaningful audited operations may require correlation or session context
for accountability or technical diagnostics, while other complete Audit Events
do not require such context.

Requiring a correlation identifier for every meaningful audited operation would
prematurely impose a universal persistence and operation contract that the
approved Phase 1 model does not require.

## Decision

Medical Access Audit correlation or session context is context-dependent rather
than universally required.

The architecture must support trusted correlation where it is applicable to the
meaningful audited behavior. When correlation is present, it must be generated,
established, or validated through trusted backend infrastructure. An arbitrary
client-supplied value must not become authoritative correlation context.

Phase 1 does not require:

- a correlation column on every Medical Access Audit Event;
- one universal correlation identifier format;
- uniqueness for correlation values;
- one Audit Event per correlation value;
- a dedicated audit-session domain entity.

Correlation does not replace User, Pet, Clinic, Veterinary Organization, Care
Authorization, Clinical Encounter, protected-resource, or other domain identity.

The exact correlation or session representation remains an architectural and
schema-design choice.

## Supersession Scope

This ADR supersedes only ADR-004's unconditional requirement that every
meaningful protected domain operation receive a correlation identifier, and any
corresponding implication that correlation is mandatory for every meaningful
Medical Access Audit Event.

All other ADR-004 decisions remain accepted and applicable, including:

- fail-closed behavior for required audited protected reads;
- coherent durable audit evidence for protected mutations;
- trusted backend audit capture;
- distinct `PERMITTED` and `DENIED` outcomes;
- append-only protection of audit history through ordinary application behavior;
- separation of Medical Access Audit Events from clinical history and technical
  observability;
- applicable audit durability requirements.

## Consequences

### Positive

- the relational model does not require unused correlation data on every Audit
  Event;
- operations that need meaningful correlation can still preserve trusted
  session or operation context;
- correlation representation can evolve without changing domain identities;
- ADR-004's fail-closed security boundary remains unchanged.

### Negative

- each audit-required behavior must determine whether correlation context is
  applicable;
- implementation must prevent untrusted client values from becoming
  authoritative correlation;
- a later architecture decision may still be needed if one shared correlation
  mechanism becomes operationally significant.

## Alternatives Considered

### Require one correlation identifier for every meaningful audited operation

Rejected because the approved Phase 1 relational model does not require
universal correlation and because it would prematurely constrain all audited
operations to one representation.

### Remove support for audit correlation

Rejected because some meaningful operations may require trusted grouping or
diagnostic association across related Audit Events and technical activity.

### Introduce an Audit Session domain entity

Rejected for Phase 1 because no approved behavior requires a persistent session
domain concept.

## Related Decisions and Specifications

- ADR-002 — Use Domain-Level Medical Access Auditing
- ADR-004 — Fail Closed When Required Medical Audit Cannot Be Durably Captured
- SPEC-ACC-003 — Record Medical Access Audit Event
- SPEC-MED-005 — View Pet Medical History


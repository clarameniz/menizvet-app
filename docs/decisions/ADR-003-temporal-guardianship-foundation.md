# ADR-003 — Model Guardianship as a Temporal-Capable Relationship

**Status:** ACCEPTED

## Context

Guardianship is the explicit relationship between a User and a Pet from which
current Pet-related capability is derived.

Approved Phase 1 Specifications repeatedly distinguish between:

- a current active Guardian;
- a User who does not currently have Guardianship;
- a former or historical Guardian.

For example, protected operations require current Guardianship rather than
historical association alone.

However, the product does not currently define a Phase 1 workflow for ending a
Guardianship relationship.

`REQ-PET-007 — Guardianship history` is delivered Later.

The persistence model therefore needs to support the distinction between
current and historical Guardianship without inventing a Phase 1 termination
workflow.

---

## Decision

Guardianship will be modeled as a temporal-capable User–Pet relationship.

The persistence model must be capable of representing:

- when a Guardianship period begins;
- whether that Guardianship is currently active;
- when that Guardianship period ended, when an approved workflow eventually
  permits termination.

Conceptually:

    Guardianship
    ├── User
    ├── Pet
    ├── effective start
    └── effective end (optional)

A Guardianship with no effective end represents a current active relationship.

A Guardianship with an effective end represents a historical relationship.

Phase 1 implementation must not introduce an operation that ends a Guardianship
unless that behavior is supported by an approved Specification.

The existence of an `effective_end` persistence capability is not itself
permission for application code, clients, administrative interfaces, or AI
agents to modify it.

---

## Rejoining

An ended Guardianship period must not be reactivated.

If future approved behavior allows a former Guardian to become a Guardian of
the same Pet again, a new Guardianship period must be established.

Conceptually:

    Maria ↔ Luna

    Guardianship A
    Jan 1 ───── Apr 10

    Guardianship B
                 Sep 3 ───── current

The previous historical period remains unchanged.

This preserves the ability to determine whether Guardianship was current at a
particular historical time.

The actual future workflow that permits Guardianship termination or
re-establishment remains outside Phase 1 until specified.

---

## Authorization Consequences

Current Pet-related capability must depend on an active Guardianship period.

Historical Guardianship alone must not provide current Pet capability.

Therefore:

    authenticated User
          +
    current Guardianship
          ↓
    Guardian capability

while:

    authenticated User
          +
    ended Guardianship
          ↓
    no current Guardian capability

This distinction must be enforced through trusted backend and data-access
boundaries.

A client-provided claim that a User is a Guardian is not authoritative.

---

## Historical Integrity

Ending a Guardianship in future approved behavior must not require deletion of
the relationship.

Historical Guardianship may remain relevant to interpreting:

- who requested an Appointment;
- who granted a Care Authorization;
- who performed historical Pet-related actions;
- previous authorization context.

Current authorization must nevertheless be evaluated using the relationship
state applicable at the time of the new operation.

Historical Guardianship must not permanently preserve current access.

---

## Phase 1 Boundary

Phase 1 supports:

- creation of initial Guardianship through Pet registration;
- creation of additional Guardianship through the approved Invitation workflow;
- evaluation of whether Guardianship is currently active;
- persistence capable of representing historical Guardianship periods.

Phase 1 does not introduce:

- ending Guardianship;
- Guardian self-removal;
- removing another Guardian;
- ownership transfer;
- differentiated Guardian roles;
- Guardian disagreement resolution;
- automatic Guardianship expiration;
- backdated Guardianship termination;
- scheduled future termination;
- reactivating an ended Guardianship.

Those behaviors require approved Requirements and Specifications.

---

## Consequences

### Positive

- current and historical Guardianship can be distinguished explicitly;
- future Guardianship lifecycle behavior does not require replacing the core
  relationship model;
- authorization can consistently depend on current relationship state;
- historical Pet, Appointment, and Care Authorization attribution can remain
  intact;
- former Guardians can be represented without deleting relationships.

### Negative

- the persistence model contains lifecycle capacity that Phase 1 product
  workflows do not yet expose;
- implementation must carefully prevent unsupported writes to the historical
  end boundary;
- future termination behavior still requires a dedicated Specification.

---

## Alternatives Considered

### Static Guardianship with no temporal boundary

Represent Guardianship only as a current User–Pet association and add temporal
history later.

Rejected because approved behavior already distinguishes current and former
Guardians, and converting the relationship later would unnecessarily redesign
an authorization-sensitive core concept.

### Implement Guardianship termination in Phase 1

Rejected because no approved Phase 1 Specification currently defines:

- who may terminate the relationship;
- whether a Guardian may remove themselves;
- whether one Guardian may remove another;
- last-Guardian constraints;
- disagreement behavior;
- effects on active care or Appointments.

Implementing those rules would invent product behavior.

---

## Related Requirements and Specifications

- REQ-PET-003 — Multiple Guardians
- REQ-PET-004 — Guardian relationship
- REQ-PET-006 — Guardianship management
- REQ-PET-007 — Guardianship history (Later)
- SPEC-PET-001 — Register Pet
- SPEC-PET-002 — Invite Guardian
- SPEC-PET-003 — Accept Guardianship Invitation
- SPEC-PET-004 — View My Pets

Medical and Appointment Specifications that require current Guardianship also
depend on this distinction.

---

## Notes

This ADR defines persistence and authorization shape only.

It must not be interpreted as approval of a Guardianship termination workflow.
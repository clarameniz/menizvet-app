# ADR-011 — Appointment-Owned Clinical Documentation Without Clinical Encounter

**Status:** ACCEPTED

Product decisions approved on 2026-10-23 (Punto 8: option B, the assignment
addendum, and the phase 0 closing decisions), together with
[SPEC-MED-010](../../specs/medical-records/SPEC-MED-010-document-appointment-clinical-record.md).

## Context

Phase 1 modelled actual veterinary care as a **Clinical Encounter** between the
Appointment and its Clinical Record Entries (`SPEC-MED-001`, `SPEC-MED-008`,
`SPEC-MED-009`). A Veterinarian had to start the Encounter (choosing a care
start), document Drafts, finalize them, and conclude the Encounter before or
after completing the Appointment.

A read-only audit of the repository established that, for Appointment-backed
care, the Encounter holds no fact that is both necessary and not already
available elsewhere:

- its Pet and Clinic are the Appointment's, which are immutable
  (`enforce_appointment_immutability`), and its Organization is the Clinic's,
  which is immutable;
- its Care Authorization is the Appointment's unique Appointment-derived Care
  Authorization (`care_authorizations_appointment_id_key`);
- authorship is already recorded on every Clinical Record Entry (User and
  concrete Veterinarian Clinic Assignment); Amendments, Attachments, and
  contributor attribution already belong to the Entry;
- `started_at` and `concluded_at` are the instants a button was pressed, not
  clinical facts;
- `ACTIVE` / `CONCLUDED` only supported revocation-safe continuity and post-care
  documentation windows, both replaced by the approved access model below.

The approved product decision is: Appointment → Clinical Record Entries →
Amendments / Attachments. A Veterinarian documents with "Add record" and "Save
record"; completion is independent; documentation may continue after
`COMPLETED`; Guardian revocation and completion end access to the Pet's prior
history but not to the Appointment's own records.

All existing Appointments, Encounters, and clinical records are disposable test
data used by a single developer (LOCAL and DEVELOPMENT). Production contains no
approved clinical use and must not be touched without explicit authorization.

## Decision

### 1. Clinical Encounter is removed from the model

No operation creates, starts, concludes, or reads a Clinical Encounter. The
`clinical_encounters` table, its triggers, its typed audit references, and the
legacy Encounter reference of Appointment Lifecycle Events are removed from the
final schema. No frozen historical copy is kept: its only content is disposable
test data, and keeping it would preserve a concept with no domain owner.

Clinical Intake (care without an Appointment) remains deferred. When it is
specified it must define its own care context; it must not reintroduce an
Encounter merely by analogy.

### 2. A Clinical Record Entry belongs to exactly one Appointment

Every Clinical Record Entry references exactly one Appointment, immutably. Pet,
Clinic, and Veterinary Organization provenance are derived through that
Appointment and its Clinic; none of them is copied onto the Entry.

### 3. An Entry is recorded once and is immediately part of the medical history

Saving a Clinical Record Entry records it as established clinical history,
visible to authorized Guardians. There is no server-side Draft and no separate
finalization. Corrections are Clinical Amendments. Entries are immutable.

The Draft lifecycle, contributor attribution (which only existed for Draft
edits), and the Draft operations are retired. No historical Draft is preserved
because all existing ones are disposable test data.

### 4. Two separate professional access bases

- **Prior-history access** — the Pet's longitudinal history — requires the
  Appointment's `ACTIVE` Appointment-derived Care Authorization, a `REQUESTED`
  (future start) or `CONFIRMED` Appointment, `CLINICAL_CARE`, and the
  Organization's `CLINICAL_CARE` Entitlement. Revocation ends it immediately;
  completion ends the Care Authorization (`ENDED`, `APPOINTMENT_COMPLETED`).
- **Appointment documentation access** — reading and writing the Appointment's
  own Clinical Record Entries, Amendments, and Attachments — requires a current
  Veterinarian context with `CLINICAL_DOCUMENTATION` at the Appointment's
  Clinic and a legitimately confirmed Appointment that is `CONFIRMED` or
  `COMPLETED`. It does not depend on the Care Authorization and never exposes
  information from other Appointments.

No new capability or Entitlement is introduced. Every new Clinical Record
Entry and Attachment requires the existing `CLINICAL_CARE` Entitlement; reads
and Amendments of existing Entries do not. `CLINICAL_DOCUMENTATION` is used
only as the professional capability.

### 5. The Appointment's assigned Veterinarian records new documentation

Product decision of 2026-10-23 (Punto 8, addendum). Each Appointment may have
at most one current Veterinarian, through the existing temporal Appointment
Veterinarian Assignment history (`SPEC-APT-007`, `SPEC-APT-008`); no new table
or care entity is introduced. Only that Veterinarian, while eligible, may
record new Clinical Record Entries. Authorship of every recorded Entry,
Amendment, and Attachment is fixed at recording and never follows a
reassignment; only an Entry's own author amends it or adds Attachments to it.

The assignment never grants or restricts prior-history access, which keeps its
existing professional scope under the Care Authorization. Assignment of
`REQUESTED` Appointments is not part of the new flow.

Assignment remains `APPOINTMENT_ASSIGN_VETERINARIAN`; additionally an eligible
Veterinarian (current Veterinarian context with `CLINICAL_DOCUMENTATION`) may
assign themselves to an unassigned or stale `CONFIRMED` or `COMPLETED`
Appointment. `COMPLETED` Appointments may be assigned and reassigned.
Veterinarian Availability is not required for this assignment, because Phase 1
has no Veterinarian Availability workflow and the assignment designates
documentation responsibility; the confirmed-commitment overlap rule still
applies to `CONFIRMED` Appointments. Contract: `SPEC-APT-007` §13.

Alternatives rejected: adding `APPOINTMENT_ASSIGN_VETERINARIAN` to the
`VETERINARIAN` responsibility (it would let any Veterinarian reassign
colleagues); requiring Veterinarian Availability (no client can configure it,
so no Veterinarian could ever be assigned); letting the current assignee amend
other authors' Entries (it would let assignment alter what another
Veterinarian wrote).

### 6. Data treatment

Before the schema cut, disposable clinical test data is removed from LOCAL and
DEVELOPMENT by an explicit operator procedure, not by a migration. The schema
migration is fail-closed: it aborts if any Clinical Record Entry, Amendment,
Attachment, contributor row, or clinical-scoped Medical Access Audit Event still
exists, so it can never silently discard real clinical documentation in any
environment.

## Consequences

### Positive

- One documentation context per visit by construction; no Encounter
  establishment race and no care-start window. Responsibility for new
  documentation is the Appointment's visible, auditable Veterinarian
  Assignment rather than whoever started an Encounter.
- Fewer operations: no Start, Conclude, Draft update, or Finalize.
- Documentation after completion and after revocation without widening history
  access.
- Indefinite history access through a forgotten `ACTIVE` Encounter, and
  unbounded revocation continuity, are no longer possible.

### Negative

- `SPEC-MED-001`, `SPEC-MED-008`, and `SPEC-MED-009` are superseded and many
  Specifications change.
- Saving publishes immediately; every correction is a visible Amendment.
- `REQ-MED-007` (prepare clinical information before finalization) is no longer
  delivered in Phase 1.
- A Clinic may record a first Entry on a `CONFIRMED` Appointment before its
  scheduled start, which then blocks Guardian cancellation (accepted: the
  scheduled time does not prove whether care began).
- An Entry whose author has left the Clinic can no longer be amended; the
  current assignee clarifies it with a new Entry of their own.
- Recording requires an assignment step when none exists ("Assign to me" is
  one tap).

## Alternatives Considered

### Keep Encounter as an internal entity without lifecycle

Rejected. It would keep a container whose every column is derived or a
button timestamp, plus coherence triggers, a uniqueness race, and an extra join
in every clinical read.

### Keep `clinical_encounters` frozen as history

Rejected. Its only rows are disposable test data; freezing it would keep FKs,
audit typing, and documentation for a concept the model no longer has.

### Automate the Encounter lifecycle (create on first save, conclude on completion)

Rejected. It would fabricate `started_at` and `concluded_at`.

## Related Documentation

- [SPEC-MED-010 — Document Appointment Clinical Record](../../specs/medical-records/SPEC-MED-010-document-appointment-clinical-record.md)
- [SPEC-APT-007 §13 — Appointment Veterinarian assignment contract](../../specs/appointments/SPEC-APT-007-assign-veterinarian-to-appointment.md)
- [CLINICAL_DOCUMENTATION_TRANSITION.md](../CLINICAL_DOCUMENTATION_TRANSITION.md)
- [DOMAIN.md](../DOMAIN.md) §9.1, §10, §11, §13.2
- [RELATIONAL_MODEL.md](../RELATIONAL_MODEL.md) §14
- [ADR-002](ADR-002-domain-level-medical-access-auditing.md),
  [ADR-004](ADR-004-fail-closed-required-medical-auditing.md),
  [ADR-005](ADR-005-context-dependent-medical-audit-correlation.md)
- REQ-MED-003, REQ-MED-004, REQ-MED-007, REQ-MED-013, REQ-ACC-002, REQ-ACC-004

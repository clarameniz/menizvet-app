# Project Conventions

**Status:** Draft  
**Version:** 0.1

## 1. Purpose

This document defines repository-wide conventions that should remain
consistent across documentation, specifications, source code, database
changes, tests, and AI-assisted development.

Conventions should be added when a repeated decision benefits from having
a single documented rule.

This document should not be used to introduce product behavior.
Product behavior belongs in requirements and specifications.

---

## 2. Language

The technical repository uses **English** as its primary language.

This includes:

- documentation;
- specifications;
- domain terminology;
- source code;
- database objects;
- test names;
- commit messages;
- architectural decisions.

User-facing application content may be localized independently.

The academic Master's Final Project document may be written in Spanish.

---

## 3. Domain Terminology

Names defined in `DOMAIN.md` form the project's ubiquitous language.

The same concept should use the same term consistently across:

- documentation;
- specifications;
- code;
- tests;
- APIs;
- database structures.

Avoid introducing synonyms for established domain concepts.

For example, once `Pet Guardian` is the accepted domain term, avoid
alternating between `owner`, `customer`, `pet user`, and `guardian`
unless they represent genuinely different concepts.

---

## 4. Requirement Identifiers

Requirements use stable identifiers composed of a domain prefix and
sequential number.

Examples:

REQ-ID-001
REQ-ORG-004
REQ-CLI-002
REQ-PET-003
REQ-MED-008
REQ-ACC-002

Requirement identifiers must not be reused after a requirement is removed,
superseded, or rejected.

---

## 5. Specification Identifiers

Specifications use the `SPEC` prefix followed by their domain and a
sequential number.

Examples:

SPEC-ID-001
SPEC-ORG-001
SPEC-PET-004
SPEC-MED-012

Specifications must reference the Requirement or Requirements they refine.

Specification identifiers must remain stable once referenced by code,
tests, pull requests, or documentation.

---

## 6. Architectural Decision Records

Architectural Decision Records use the following naming convention:

ADR-XXX-short-description.md

Example:

ADR-001-clinical-attachment-storage.md

ADR numbers are sequential and must not be reused.

ADRs should document decisions that:

- have meaningful alternatives;
- affect architecture or long-term development;
- benefit from preserving the reasoning behind the decision.

Minor implementation details do not require an ADR.

---

## 7. Documentation Links

Repository documentation should use relative links whenever possible.

Example:

[PROJECT.md](PROJECT.md)

[DOMAIN.md](DOMAIN.md)

[decisions/](decisions/)

Links should remain valid when browsing the repository through GitHub.

---

## 8. Dates and Time

When domain behavior depends on time, dates and timestamps must be treated
explicitly.

The system must distinguish between:

- business dates;
- timestamps;
- historical event time;
- record creation time;
- modification time;
- effective start and end times;
- scheduled local times.

Historical dates must not be inferred from current state when the original
event date is available.

Scheduling behavior must use an explicit applicable timezone.

A client device timezone must not become the authoritative interpretation of
Clinic Opening Hours, Appointment Availability, or confirmed Appointment
times.

Persistence and conversion rules will be defined by the architecture when the
database and scheduling implementation are introduced.

Timezone conversion must not rewrite the underlying historical or scheduling
meaning of an event.

---

## 9. Historical Data

Historical domain information must not be destructively removed merely
because a current relationship ends.

Examples include:

- Organization Memberships;
- Clinic assignments;
- Appointments;
- finalized clinical information;
- clinical provenance.

Deletion behavior must follow explicit specifications.

---

## 10. Naming

Use domain terminology rather than technical shorthand when naming
business concepts.

Prefer:

`organizationMembership`

over:

`orgRel`

Prefer:

`medicalRecordEntry`

over:

`medData`

Abbreviations should only be used when they are widely understood and
unambiguous.

---

## 11. Source of Truth

When repository artifacts disagree, product behavior should be resolved
using the following conceptual precedence:

1. approved product decisions;
2. `DOMAIN.md` invariants and terminology;
3. approved requirements;
4. approved specifications;
5. architectural decisions;
6. implementation.

Implementation must not silently redefine a Requirement or Specification.

If a conflict is detected, it should be surfaced and resolved explicitly.

---

## 12. Scope Discipline

Changes should remain focused on the Requirement or Specification being
implemented.

Do not:

- implement unrelated future functionality;
- perform unrelated refactors;
- introduce speculative abstractions;
- add dependencies without a concrete need;
- redesign unrelated domain areas as part of a small feature.

Refactoring is allowed when necessary to implement the current behavior
safely or when performed as an explicit standalone task.

---

## 13. AI-Assisted Changes

AI coding agents must:

1. read the relevant repository documentation before implementation;
2. identify the Requirement and Specification being addressed;
3. respect established domain terminology;
4. keep changes within the requested scope;
5. report conflicts instead of inventing missing business rules;
6. avoid adding dependencies without justification;
7. add or update automated verification when applicable;
8. summarize significant changes after implementation.

Agents must not modify Requirements or Specifications merely to make an
existing implementation pass.

---

## 14. Database Conventions

PostgreSQL and Supabase conventions are established incrementally through
source-controlled migrations and the durable rules below.

At minimum:

- database evolution must follow the migration rules defined in
  [## 18. Database Migrations](#18-database-migrations);
- authorization must not rely exclusively on the client;
- destructive changes require explicit consideration of existing data;
- critical domain integrity should be enforced at the strongest appropriate
  trusted boundary;
- database access must preserve the authorization context required by the
  applicable Specifications.

---

## 15. Testing Conventions

The project-wide testing strategy is defined in
[TESTING.md](TESTING.md).

Approved Specifications and their Verification Notes are the primary source
for behavioral test design.

Tests should:

- verify observable behavior rather than implementation details;
- include negative authorization cases for protected operations;
- protect critical domain invariants;
- verify historical integrity where lifecycle changes are involved;
- use the most appropriate testing level for the behavior being verified.

Tests must not modify or reinterpret approved product behavior merely to make
an implementation pass.

---

## 16. Code Conventions

Detailed TypeScript and React Native conventions will be introduced once
the application bootstrap is complete.

Topics to define later include:

- formatting;
- linting;
- strict TypeScript configuration;
- import conventions;
- file naming;
- component naming;
- error handling;
- validation;
- test naming;
- module boundaries.

Do not define these prematurely before the corresponding tooling is selected.

---

## 17. Convention Evolution

This document is expected to evolve with the project.

A new convention should normally be added when:

- the same decision appears repeatedly;
- inconsistency is becoming likely;
- tooling requires a project-wide rule;
- a development practice needs to be enforced consistently.

Avoid adding rules for situations the project has not encountered and is
unlikely to encounter soon.

---

## 18. Database Migrations

All database schema changes must be introduced through version-controlled
migrations.

Direct manual modification of shared or production database schemas is not an
accepted source of schema truth.

Migrations must be reproducible from source control.

---

## 19. Secrets and Sensitive Configuration

Private credentials, privileged service keys, provider secrets, signing
secrets, and equivalent sensitive configuration must not be:

- embedded in distributable client applications;
- committed to source control;
- included in ordinary application logs;
- exposed through public configuration;
- copied into documentation or test fixtures without an explicit safe reason.

Client-side configuration that is intentionally public must remain clearly
distinguishable from privileged server-side secrets.

Privileged credentials must only be available within trusted execution
environments that require them.

Example:

```text
acceptable in client
→ intentionally public project configuration

not acceptable in client
→ privileged service-role credential
→ email provider secret
→ billing provider secret
→ private signing secret
```

Local development secrets must use an ignored environment or secret-management
mechanism appropriate to the selected tooling.

Secret rotation must not require changes to domain identity or business data.

---

## 20. Data Access and Query Boundaries

Data-access operations should retrieve only the information required for the
current authorized use case.

Avoid application behavior that depends on:

- downloading unbounded collections;
- loading complete longitudinal histories when only a subset is required;
- retrieving protected files before they are needed;
- repeated network requests for information that can reasonably be obtained
  together;
- avoidable N+1 query patterns;
- downloading entire datasets to the client in order to perform filtering or
  authorization locally.

Potentially large collections should use bounded retrieval strategies such as:

- pagination;
- explicit limits;
- date ranges;
- server-side filtering;
- cursor-based retrieval where appropriate.

Geographic discovery must be performed through a server-side geographic query
strategy rather than downloading all Clinic locations to the client.

Performance optimizations must not weaken:

- authorization;
- domain integrity;
- historical integrity;
- auditability.

Specific performance targets should be introduced only when meaningful
measurements and product requirements justify them.

---

## 21. Accessibility

User-facing interfaces should be implemented so that essential product
behavior does not depend unnecessarily on visual presentation alone.

At minimum:

- interactive controls should expose meaningful accessible labels;
- important state must not be represented only through color;
- text should support platform accessibility and scaling behavior where
  practical;
- interactive targets should be usable without requiring excessive precision;
- screen-reader semantics should be provided for meaningful controls and
  content;
- disabled, selected, error, and status states should remain understandable
  through accessible semantics;
- decorative content should not create unnecessary accessibility noise.

Accessibility requirements apply to behavior and information hierarchy rather
than requiring every screen to use identical presentation.

Detailed platform-specific conventions may be added once the React Native UI
architecture and tooling are established.

---

## 22. Localization

User-facing text must remain separate from stable domain and application
identifiers.

Business logic must not depend on translated display strings.

Prefer:

```text
domain value
VACCINATION

display
Spanish → Vacunación
English → Vaccination

over:
business rule checks
if label == "Vacunación"
``` 

User-facing strings should be structured so that additional languages can be
introduced without redesigning domain logic.

At minimum:

stable domain identifiers must remain language-independent;
UI text should not be scattered through business logic where localization
resources are more appropriate;
translated labels must not become database or authorization identifiers;
dates, times, numbers, and other locale-sensitive presentation should be
formatted through the applicable presentation layer;
localization changes must not modify domain meaning.

The exact localization library and resource structure will be defined when the
client application tooling is introduced.

---
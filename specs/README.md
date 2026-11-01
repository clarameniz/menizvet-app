# Specifications

**Status:** Draft
**Version:** 0.1

## 1. Purpose

This directory contains the behavioral specifications of the Veterinary Care Platform.

Specifications translate approved product requirements into precise, testable behavior.

They form the primary contract between:

* product intent;
* domain rules;
* implementation;
* automated verification;
* human developers;
* AI coding agents.

The expected traceability flow is:

```text
PROJECT.md
    ↓
DOMAIN.md
    ↓
REQUIREMENTS.md
    ↓
Specification
    ↓
Implementation
    ↓
Automated verification
```

Specifications describe **what the system must do** under defined conditions.

They should not prescribe implementation details unless those details are themselves required by an approved architectural decision.

---

# 2. Source of Truth

Specifications refine approved Requirements.

Each Specification must reference at least one Requirement.

Example:

```text
REQ-ORG-004
Temporal Organization Membership

    ↓

SPEC-ORG-002
End an Organization Membership
```

A Specification must not introduce behavior that contradicts:

* `PROJECT.md`;
* `DOMAIN.md`;
* approved Requirements;
* established domain invariants.

If a required behavior conflicts with an existing domain rule or Requirement, the conflict must be resolved before implementation.

Implementation must not silently redefine a Specification.

---

# 3. Directory Structure

Specifications are grouped by domain area.

```text
specs/
├── README.md
├── identity/
├── organizations/
├── clinics/
├── professionals/
├── pets/
├── discovery/
├── appointments/
├── medical-records/
├── access-control/
├── subscriptions/
└── communications/
```

Additional directories may be introduced when the domain demonstrates a clear need for them.

Directory structure should follow the ubiquitous language defined in `DOMAIN.md`.

---

# 4. Specification Identifiers

Each Specification has a stable identifier.

Format:

```text
SPEC-{DOMAIN}-{NUMBER}
```

Examples:

```text
SPEC-ID-001
SPEC-ORG-002
SPEC-CLI-004
SPEC-VET-003
SPEC-PET-006
SPEC-APT-005
SPEC-MED-012
SPEC-ACC-004
SPEC-SUB-003
```

Numbers are sequential within each domain.

Once a Specification identifier has been referenced by implementation,
tests, commits, pull requests, or documentation, it must not be reused.

---

# 5. File Naming

Specification files use:

```text
SPEC-{DOMAIN}-{NUMBER}-{short-description}.md
```

Examples:

```text
SPEC-ORG-001-create-organization.md
SPEC-ORG-002-end-organization-membership.md
SPEC-PET-003-add-guardian.md
SPEC-MED-004-finalize-medical-record-entry.md
```

Descriptions should be short and use kebab-case.

The Specification identifier remains the canonical identity.

The filename description may be changed if clarification is needed.

---

# 6. Specification Scope

A Specification should describe one focused behavior or one tightly related business rule.

Prefer:

```text
SPEC-ORG-001
Create Organization Membership

SPEC-ORG-002
End Organization Membership

SPEC-ORG-003
Ended Membership does not grant active permissions
```

Avoid:

```text
SPEC-ORG-001
Manage Organizations and all their members, permissions,
subscriptions, clinics and veterinarians
```

A Specification that contains several independently testable behaviors should normally be split.

---

# 7. Specification Principles

## 7.1 Behavior over implementation

A Specification should describe observable system behavior.

Prefer:

> An ended Organization Membership must not grant current Organization permissions.

Avoid:

> Query the `organization_memberships` table where `ended_at IS NULL`.

The first statement specifies behavior.

The second describes one possible implementation.

---

## 7.2 Domain language

Specifications must use terminology defined in `DOMAIN.md`.

Prefer:

> Pet Guardian

over inconsistent alternatives such as:

> pet owner
> customer owner
> pet user

unless those terms represent genuinely different concepts.

---

## 7.3 Explicit conditions

Behavior must be described with enough context to determine when it applies.

Avoid:

> A Veterinarian can access a Pet.

Prefer:

> A Veterinarian acting within an authorized Clinic context may access the permitted medical information of a Pet when the applicable Care Authorization is valid.

---

## 7.4 Explicit negative behavior

Specifications should define important denied or invalid behavior as well as successful behavior.

For example:

```text
Authorized membership
→ operation succeeds

Ended membership
→ operation is denied
```

Security-sensitive specifications should almost always include negative scenarios.

---

## 7.5 No speculative behavior

A Specification must not include functionality solely because it might be useful later.

Future needs may influence domain boundaries.

They must not become executable requirements until explicitly approved.

---

## 7.6 Deterministic expected outcomes

Whenever possible, a Specification should define outcomes precisely enough that two independent implementations would agree on whether the behavior is correct.

---

# 8. Specification Template

Each Specification should normally follow this structure.

```markdown
# SPEC-XXX-000 — Specification title

**Status:** Proposed
**Requirements:** REQ-XXX-000
**Domain:** Domain name
**Priority:** P0 / P1 / P2 / P3

## 1. Intent

Explain the business behavior this Specification defines.

## 2. Preconditions

Describe conditions that must already be true.

## 3. Business Rules

List the rules that govern the behavior.

## 4. Scenarios

### Scenario: Successful behavior

Given ...
And ...
When ...
Then ...
And ...

### Scenario: Rejected behavior

Given ...
When ...
Then ...

## 5. Edge Cases

Describe relevant boundary or exceptional cases not already represented
clearly by the main scenarios.

## 6. Invariants

Reference relevant domain invariants when applicable.

Example:

- INV-005 — Organization Membership is temporal.
- INV-009 — Historical clinical provenance is immutable.

## 7. Out of Scope

Explicitly identify closely related behavior that this Specification does
not define.

## 8. Verification Notes

Describe the observable outcomes that must be verifiable.

Do not prescribe the testing framework or implementation unless required
by architecture.
```

Not every Specification requires every section.

Sections may be omitted when they add no useful information.

---

# 9. Specification Status

Specifications use the following lifecycle:

```text
PROPOSED
    ↓
APPROVED
    ↓
IMPLEMENTING
    ↓
IMPLEMENTED
    ↓
VERIFIED
```

Additional states may include:

```text
DEFERRED
SUPERSEDED
REJECTED
```

---

## 9.1 PROPOSED

The behavior is being discussed and may still change.

A `PROPOSED` Specification should not normally be implemented.

---

## 9.2 APPROVED

The intended behavior has been accepted.

Implementation may begin.

---

## 9.3 IMPLEMENTING

The Specification is currently being implemented.

This state is optional but may be useful during active development.

---

## 9.4 IMPLEMENTED

The expected implementation exists.

Implementation alone does not imply that verification is complete.

---

## 9.5 VERIFIED

The Specification has appropriate automated verification and the expected behavior is confirmed.

---

## 9.6 SUPERSEDED

The Specification has been replaced by newer behavior.

Superseded Specifications should normally be retained for traceability.

The replacement Specification must be referenced.

---

# 10. Scenarios

Behavioral scenarios should normally use Given / When / Then language.

Example:

```gherkin
Scenario: End an active Organization Membership

  Given Maria has an active membership in Animalia Veterinary Group
  And the membership started on 2026-01-10

  When an authorized administrator ends the membership on 2026-07-15

  Then the membership is no longer active
  And its start date remains 2026-01-10
  And its end date is 2026-07-15
  And the historical membership is preserved
```

The repository may use Gherkin-style scenarios without requiring a Gherkin execution framework.

The scenarios exist primarily to make behavior precise and testable.

Tooling may later execute them directly if there is a demonstrated benefit.

---

# 11. Scenario Design

## 11.1 One meaningful behavior per scenario

A scenario should test one coherent outcome.

Avoid scenarios that exercise an entire application journey unless the journey itself is the behavior being specified.

---

## 11.2 Happy paths are not enough

Relevant Specifications should consider:

* successful behavior;
* unauthorized behavior;
* invalid state;
* temporal boundaries;
* duplicate operations;
* conflicting operations;
* already-completed operations.

Not all apply to every Specification.

---

## 11.3 Avoid UI-specific scenarios unless UI behavior is the requirement

Prefer:

```text
When the Guardian requests an Appointment
```

over:

```text
When the Guardian presses the blue button
```

unless the Specification specifically concerns user-interface behavior.

---

## 11.4 Avoid implementation terminology

Prefer:

```text
Given the Organization Membership has ended
```

over:

```text
Given ended_at is not NULL
```

---

# 12. Preconditions

Preconditions define state required before the behavior starts.

Example:

```text
- The User is authenticated.
- The Organization exists.
- The acting User has permission to manage Organization memberships.
- The target membership is active.
```

Preconditions should not be used to hide important behavior.

If authentication or authorization behavior itself is relevant to the Specification, it should appear in the scenarios.

---

# 13. Business Rules

Business Rules should describe constraints that apply consistently across scenarios.

Example:

```text
BR-1. An Organization Membership cannot end before it starts.

BR-2. Ending a Membership must preserve the historical relationship.

BR-3. An ended Membership cannot grant current Organization capabilities.

BR-4. Ending a Clinic assignment must not implicitly end Organization
      Membership unless explicitly specified.
```

Business Rule identifiers only need to be unique within the Specification.

They are not global repository identifiers.

---

# 14. Invariants

Specifications should reference relevant invariants from `DOMAIN.md`.

Example:

```text
Relevant invariants:

- INV-006 — Organization Membership is temporal.
- INV-009 — Historical clinical provenance is immutable.
```

Specifications may refine an invariant.

They must not silently contradict one.

If an invariant is discovered to be wrong, the domain model should be reviewed explicitly.

---

# 15. Edge Cases

Edge cases should be included when they materially affect behavior.

Examples:

* attempting to end an already-ended Membership;
* end date before start date;
* duplicate Guardian invitation;
* Appointment requested for an inactive Clinic;
* access authorization expiring during a workflow;
* professional leaving a Clinic after producing a medical record.

Do not create artificial edge cases simply to make a Specification look exhaustive.

---

# 16. Out of Scope

Each Specification should explicitly exclude nearby behavior when ambiguity is likely.

Example:

```text
## Out of Scope

This Specification does not define:

- how a Veterinarian is invited to an Organization;
- professional credential verification;
- Clinic assignment;
- Organization subscription rules.
```

This section is especially important for AI-assisted implementation.

It prevents agents from expanding the task beyond its intended boundaries.

---

# 17. Verification

A Specification must be written so its behavior can be verified.

Verification may ultimately include:

* domain-level tests;
* database integration tests;
* Row Level Security tests;
* Edge Function tests;
* application integration tests;
* UI tests;
* end-to-end tests.

The Specification should not choose the testing layer unless the behavior inherently requires one.

Example:

A medical authorization rule might eventually require database-level
verification because client-side testing alone cannot prove that access
cannot be bypassed.

That decision belongs to architecture and test strategy.

---

# 18. Traceability

Specifications must reference their parent Requirements.

Implementation should reference Specifications where practical.

Examples include:

### Pull requests

```text
Implements SPEC-ORG-002
```

### Commit messages

```text
feat(organizations): end organization membership

Implements SPEC-ORG-002
```

### Tests

Where useful:

```text
SPEC-ORG-002: ended membership loses active permissions
```

Traceability should remain useful rather than becoming administrative noise.

---

# 19. Specification Dependencies

A Specification may depend on behavior defined elsewhere.

Dependencies should be explicit when necessary.

Example:

```text
Depends on:

- SPEC-ID-002 — Authenticate User
- SPEC-ORG-001 — Create Organization Membership
```

Avoid duplicating another Specification's rules.

Reference the existing Specification instead.

---

# 20. Cross-Domain Behavior

Some behaviors naturally cross domain boundaries.

For example:

```text
Booking an Appointment

Pets
+ Clinics
+ Identity
+ Appointments
```

The Specification should live in the domain that owns the behavior.

Related domains may be referenced as dependencies.

Do not create duplicate Specifications in several directories for the same behavior.

---

# 21. Security-Sensitive Specifications

Specifications involving sensitive information or authorization should explicitly define:

* who is acting;
* in what context;
* what resource is being accessed;
* what authorization is required;
* what happens when authorization is absent;
* what happens when authorization has expired or been revoked when relevant.

Example:

```gherkin
Scenario: Veterinarian without authorization cannot access medical history

  Given Dr. Lopez is a verified Veterinarian
  And Dr. Lopez is actively assigned to Animalia Madrid
  And Luna has no valid Care Authorization for the applicable Clinic

  When Dr. Lopez requests Luna's protected medical history

  Then access is denied
```

The mere existence of a professional role must never be treated as sufficient authorization unless a Specification explicitly establishes that rule.

---

# 22. Temporal Specifications

Time-dependent behavior must use explicit dates or times where ambiguity matters.

Prefer:

```text
The Membership started on 2026-01-15.
The Membership ended on 2026-07-31.
```

Avoid:

```text
The Membership ended later.
```

Specifications must distinguish where relevant between:

* effective business time;
* event occurrence time;
* system creation time;
* modification time.

---

# 23. Specification Changes

Specifications are expected to evolve during product development.

Before implementation, a `PROPOSED` Specification may change freely as understanding improves.

After approval or implementation, material changes should be handled deliberately.

When changing approved behavior:

1. identify affected Requirements;
2. identify dependent Specifications;
3. assess architecture and data impact;
4. update implementation;
5. update verification;
6. preserve decision history when useful.

Do not rewrite already-shipped behavior without understanding migration and compatibility implications.

---

# 24. AI Agent Rules

When implementing a Specification, an AI coding agent must:

1. read the Specification completely;
2. read its referenced Requirements;
3. consult relevant sections of `DOMAIN.md`;
4. consult applicable ADRs and architectural documentation;
5. identify the minimum implementation required;
6. avoid implementing Out-of-Scope behavior;
7. report contradictions or missing domain decisions;
8. implement relevant automated verification;
9. avoid modifying the Specification merely to match existing code;
10. summarize the relationship between the Specification and the implemented changes.

If a Specification is ambiguous in a way that materially changes business behavior, the agent must not invent the missing rule.

The ambiguity must be resolved at the specification level.

---

# 25. Definition of Ready

A Specification is normally ready for implementation when:

* its status is `APPROVED`;
* its parent Requirements are known;
* its intent is clear;
* relevant business rules are explicit;
* primary scenarios are defined;
* important authorization behavior is defined;
* significant edge cases are addressed;
* relevant domain invariants are known;
* nearby Out-of-Scope behavior is clear;
* no unresolved ambiguity materially affects implementation.

---

# 26. Definition of Done

A Specification may be considered `VERIFIED` when:

* the required behavior has been implemented;
* relevant automated tests exist;
* applicable authorization rules are enforced outside the client;
* tests pass;
* type checking and static checks pass where applicable;
* migrations are reproducible when data changes are involved;
* no unrelated behavior was introduced;
* documentation or ADRs were updated where necessary;
* implementation can be traced back to the Specification.

---

# 27. Guiding Principle

A good Specification should make the following question answerable:

> If two developers independently implemented this Specification, could we determine objectively whether both implementations satisfy the same intended behavior?

If the answer is no, the Specification probably needs further refinement before implementation.

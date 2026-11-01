# SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities

**Status:** APPROVED  
**Requirements:** REQ-ORG-005, REQ-ORG-006  
**Domain:** Organizations  
**Priority:** P0

> **Revised — Punto 8 (`APPROVED` 2026-10-23).** No capability is added. Under [SPEC-APT-007 §13](../appointments/SPEC-APT-007-assign-veterinarian-to-appointment.md) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md): `APPOINTMENT_ASSIGN_VETERINARIAN` keeps governing assignment of others; a Veterinarian holding `CLINICAL_DOCUMENTATION` at the Clinic may additionally assign themselves to an unassigned or stale `CONFIRMED` or `COMPLETED` Appointment; recording a Clinical Record Entry requires both `CLINICAL_DOCUMENTATION` and being the Appointment's current eligible assignee.

## 1. Intent

Define how Organization Membership responsibilities provide
Organization-context capabilities.

A User's current Organization capabilities are derived from:

- an active Organization Membership;
- one or more active Organization responsibilities;
- the scope of those responsibilities;
- the Organization and Clinic context of the requested operation.

Responsibilities are not global User roles.

The same User may simultaneously have:

- different responsibilities in the same Organization;
- different responsibilities in different Organizations;
- personal capabilities such as Guardianship;
- professional veterinary identity;
- Clinic Assignments.

Organization responsibility does not replace those independent domain
relationships.

---

## 2. Responsibility Model

Phase 1 supports the following controlled Organization responsibilities:

- `OWNER`
- `ADMINISTRATOR`
- `RECEPTIONIST`
- `VETERINARIAN`

Responsibilities may provide one or more domain capabilities.

A Membership may contain more than one responsibility.

For example:

    Dr. Garcia

    Animalia Membership
    ├── VETERINARIAN
    └── ADMINISTRATOR

must be valid where the scopes and other domain requirements are satisfied.

Responsibilities are not mutually exclusive global User types.

---

## 3. Responsibility Scope

A responsibility grant must have an explicit scope.

Phase 1 supports:

### ORGANIZATION

The responsibility applies within the Veterinary Organization.

Where the responsibility provides Clinic-management or Appointment capabilities,
Organization scope may make those capabilities applicable to Clinics operated
by that Organization.

It does not apply to another Organization.

### CLINIC

The responsibility applies only to one identified Clinic belonging to the
Membership's Veterinary Organization.

For example:

    Carlos
    Animalia Membership

    RECEPTIONIST
    scope = Animalia Madrid Centro

must not provide equivalent authority at:

    Animalia Getafe

unless another applicable responsibility grant exists.

---

## 4. Responsibility Scope Restrictions

### OWNER

`OWNER` is always Organization-scoped.

A Clinic-scoped Owner responsibility is invalid.

### ADMINISTRATOR

`ADMINISTRATOR` may be:

- Organization-scoped;
- Clinic-scoped.

An Organization-scoped Administrator may receive applicable Organization
administrative capabilities and applicable Clinic-management capabilities
across the Organization.

A Clinic-scoped Administrator receives only applicable capabilities for the
specified Clinic.

### RECEPTIONIST

`RECEPTIONIST` may be:

- Organization-scoped;
- Clinic-scoped.

An Organization-scoped Receptionist may support centralized scheduling across
the Organization's Clinics.

A Clinic-scoped Receptionist is limited to the specified Clinic.

### VETERINARIAN

`VETERINARIAN` is Organization-scoped.

Actual professional authority at a specific Clinic requires a valid
Veterinarian Clinic Assignment.

A Veterinary Organization responsibility must not be used as a replacement
for Clinic Assignment.

---

## 5. Phase 1 Organization Capabilities

Phase 1 uses stable capability concepts rather than checking responsibility
names directly throughout domain behavior.

### Organization administration

- `ORGANIZATION_INVITE_MEMBERS`
- `ORGANIZATION_REVOKE_INVITATIONS`
- `ORGANIZATION_END_MEMBERSHIPS`
- `ORGANIZATION_GRANT_RESPONSIBILITIES`
- `ORGANIZATION_CREATE_CLINICS`
- `ORGANIZATION_MANAGE_SUBSCRIPTION`

### Clinic administration

- `CLINIC_MANAGE_LOCATION`
- `CLINIC_MANAGE_PUBLICATION`
- `CLINIC_MANAGE_PUBLIC_PROFILE`
- `CLINIC_MANAGE_SERVICES`
- `CLINIC_MANAGE_OPENING_HOURS`
- `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`

`CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` authorizes establishing and ending
Veterinarian Clinic Assignments for the Clinic, as governed by `SPEC-VET-004`
and `SPEC-VET-005`. It is distinct from `APPOINTMENT_ASSIGN_VETERINARIAN`,
which concerns Appointment Veterinarian Assignment.

### Appointment operations

- `APPOINTMENT_VIEW_SCHEDULE`
- `APPOINTMENT_CONFIRM`
- `APPOINTMENT_CANCEL`
- `APPOINTMENT_RESCHEDULE`
- `APPOINTMENT_ASSIGN_VETERINARIAN`
- `APPOINTMENT_COMPLETE`
- `APPOINTMENT_MARK_NO_SHOW`
- `APPOINTMENT_MANAGE_AVAILABILITY`

### Clinical professional operations

- `CLINICAL_CARE`
- `CLINICAL_DOCUMENTATION`

These capability identifiers represent domain authorization concepts.

They are not external-provider permissions.

No Phase 1 responsibility or capability authorizes establishing another
Veterinary Organization. Organization establishment is performed only through
trusted Commercial Onboarding, as defined by `SPEC-ORG-001`.

---

## 6. Phase 1 Responsibility Capability Mapping

### OWNER — Organization scope

An active Organization-scoped `OWNER` responsibility provides:

- `ORGANIZATION_INVITE_MEMBERS`;
- `ORGANIZATION_REVOKE_INVITATIONS`;
- `ORGANIZATION_END_MEMBERSHIPS`;
- `ORGANIZATION_GRANT_RESPONSIBILITIES`;
- `ORGANIZATION_CREATE_CLINICS`;
- `ORGANIZATION_MANAGE_SUBSCRIPTION`;
- all Phase 1 Clinic-administration capabilities;
- all Phase 1 Appointment-management capabilities.

`OWNER` does not by itself provide:

- `CLINICAL_CARE`;
- `CLINICAL_DOCUMENTATION`;
- veterinary qualification;
- Clinic Assignment;
- medical-history access.

---

### ADMINISTRATOR — Organization scope

An active Organization-scoped `ADMINISTRATOR` responsibility provides:

- `ORGANIZATION_INVITE_MEMBERS`;
- `ORGANIZATION_REVOKE_INVITATIONS`;
- `ORGANIZATION_END_MEMBERSHIPS`;
- `ORGANIZATION_GRANT_RESPONSIBILITIES`;
- `ORGANIZATION_CREATE_CLINICS`;
- `ORGANIZATION_MANAGE_SUBSCRIPTION`;
- all Phase 1 Clinic-administration capabilities;
- all Phase 1 Appointment-management capabilities.

An Administrator must not:

- grant `OWNER` through the standard Invitation workflow;
- remove or end the sole active Owner Membership;
- transfer Organization ownership implicitly.

`ADMINISTRATOR` does not by itself provide clinical professional capability.

---

### ADMINISTRATOR — Clinic scope

An active Clinic-scoped `ADMINISTRATOR` responsibility provides, for the
specified Clinic only:

- `CLINIC_MANAGE_LOCATION`;
- `CLINIC_MANAGE_PUBLICATION`;
- `CLINIC_MANAGE_PUBLIC_PROFILE`;
- `CLINIC_MANAGE_SERVICES`;
- `CLINIC_MANAGE_OPENING_HOURS`;
- `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`;
- all Phase 1 Appointment-management capabilities.

A Clinic-scoped Administrator does not receive Organization Membership
administration, Clinic-creation capability, or
`ORGANIZATION_MANAGE_SUBSCRIPTION` solely from that responsibility.

---

### RECEPTIONIST

An active `RECEPTIONIST` responsibility provides, within its applicable scope:

- `APPOINTMENT_VIEW_SCHEDULE`;
- `APPOINTMENT_CONFIRM`;
- `APPOINTMENT_CANCEL`;
- `APPOINTMENT_RESCHEDULE`;
- `APPOINTMENT_ASSIGN_VETERINARIAN`;
- `APPOINTMENT_COMPLETE`;
- `APPOINTMENT_MARK_NO_SHOW`;
- `APPOINTMENT_MANAGE_AVAILABILITY`.

`RECEPTIONIST` does not by itself provide:

- Organization Membership administration;
- Clinic configuration administration;
- `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`, in any scope;
- veterinary qualification;
- `CLINICAL_CARE`;
- `CLINICAL_DOCUMENTATION`;
- unrestricted medical-history access.

---

### VETERINARIAN

An active Organization-scoped `VETERINARIAN` responsibility may provide:

- `APPOINTMENT_VIEW_SCHEDULE`;
- `APPOINTMENT_COMPLETE`;
- `CLINICAL_CARE`;
- `CLINICAL_DOCUMENTATION`;

only within a Clinic where the User also satisfies the applicable professional
requirements.

The responsibility alone is insufficient.

Professional operations additionally require, where applicable:

- an existing Veterinarian Professional Profile;
- a valid current Clinic Assignment;
- valid Clinic and Organization context;
- applicable Pet Care Authorization;
- least-privilege Medical Access Control;
- applicable professional Entitlement;
- valid domain lifecycle state.

`VETERINARIAN` does not provide `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`,
whether from the responsibility itself or from a Clinic Assignment.

### Subscription management scope

`ORGANIZATION_MANAGE_SUBSCRIPTION` is provided only by an active
Organization-scoped `OWNER` or `ADMINISTRATOR` responsibility in Phase 1.

It is not provided by:

- a Clinic-scoped `ADMINISTRATOR` responsibility;
- `RECEPTIONIST`;
- `VETERINARIAN`;
- bare Organization Membership;
- Veterinarian Professional Profile;
- Veterinarian Clinic Assignment.

Subscription management itself does not require a professional paid
Entitlement. Provider-driven trusted commercial state changes do not require a
User responsibility-derived capability.

### Veterinarian Clinic Assignment management scope

`CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` is provided in Phase 1 only by:

| Responsibility | Responsibility scope | Clinics for which the capability applies |
| --- | --- | --- |
| `OWNER` | Organization | every Clinic of that Veterinary Organization |
| `ADMINISTRATOR` | Organization | every Clinic of that Veterinary Organization |
| `ADMINISTRATOR` | Clinic | only the Clinic identified by the Responsibility Grant |

In every case the capability requires, at evaluation time:

- a current Organization Membership in the Veterinary Organization that
  operates the target Clinic;
- a current applicable Responsibility Grant within that Membership.

It is not provided by:

- `RECEPTIONIST`, in any scope;
- `VETERINARIAN`, whether from the responsibility itself or from any
  Veterinarian Clinic Assignment;
- bare Organization Membership;
- Veterinarian Professional Profile;
- a responsibility in another Veterinary Organization.

`CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` is not a paid professional capability.
It does not require a Subscription or professional Entitlement
(`SPEC-SUB-003` BR-3).

Establishing and ending Veterinarian Clinic Assignments, including their
preconditions and temporal and historical semantics, are governed by
`SPEC-VET-004` and `SPEC-VET-005`.

---

## 7. Delegation Policy

### Owner delegation

An active Organization Owner may use the standard Organization Invitation
workflow to grant:

- `ADMINISTRATOR`;
- `RECEPTIONIST`;
- `VETERINARIAN`;

with an allowed scope.

`OWNER` itself is not granted through the standard Invitation workflow.

---

### Organization Administrator delegation

An active Organization-scoped Administrator may use the standard Invitation
workflow to grant:

- `ADMINISTRATOR`;
- `RECEPTIONIST`;
- `VETERINARIAN`;

with an allowed scope.

An Administrator must not grant `OWNER`.

---

### Clinic-scoped Administrator delegation

A Clinic-scoped Administrator does not receive Organization Membership
invitation or responsibility-delegation capability solely from that
Clinic-scoped responsibility.

---

### Receptionist delegation

`RECEPTIONIST` does not grant Organization responsibility-delegation
capability.

---

### Veterinarian delegation

`VETERINARIAN` does not grant Organization responsibility-delegation
capability.

---

## 8. Business Rules

### BR-1 — Responsibilities belong to Organization Membership

An Organization responsibility must belong to an Organization Membership.

It must not be stored as a global property of the User.

---

### BR-2 — One User may have several responsibilities

A Membership may contain several compatible responsibilities.

The system must not force a User into one mutually exclusive Organization role.

---

### BR-3 — Responsibilities are Organization-specific

A responsibility granted through an Animalia Membership must not provide
capabilities in VetCare.

---

### BR-4 — Responsibilities may be independently scoped

Different responsibility grants belonging to the same Membership may have
different applicable scopes.

For example:

    Carlos
    Animalia Membership

    RECEPTIONIST → Madrid Centro
    ADMINISTRATOR → Getafe

may be represented without creating multiple domain Users.

---

### BR-5 — Capability is derived, not independently assigned to User

Phase 1 must not assign arbitrary capability flags directly to the global User.

Capabilities are derived from applicable current domain relationships.

---

### BR-6 — Responsibility name must not be checked as a global role

Protected domain operations should ask:

    "Does this User have the required capability
     in this Organization / Clinic context?"

rather than:

    "Is this User globally an Administrator?"

---

### BR-7 — Active Membership is required

An ended Organization Membership provides no current Organization capability,
even when its historical responsibility information remains preserved.

---

### BR-8 — Scope must match the target context

A Clinic-scoped responsibility only provides its capabilities when the
requested operation concerns that Clinic.

---

### BR-9 — Organization scope does not cross Organization boundaries

Organization-scoped responsibility applies only within the Organization that
owns the Membership.

---

### BR-10 — Clinic scope must belong to Membership Organization

A responsibility scoped to a Clinic is valid only when that Clinic belongs to
the same Veterinary Organization as the Membership.

---

### BR-11 — Organization-scoped Clinic capability applies only to Clinics of that Organization

Where an Organization-scoped responsibility provides Clinic capability, it may
apply to Clinics operated by that Organization.

It must not apply to Clinics operated by another Organization.

---

### BR-12 — Responsibility does not establish authentication

A User must still be authenticated where the applicable operation is private.

Responsibility is not authentication proof.

---

### BR-13 — Responsibility does not establish veterinary qualification

`VETERINARIAN` responsibility must not create a Veterinarian Professional
Profile or verified professional qualification.

---

### BR-14 — Responsibility does not create Clinic Assignment

No Organization responsibility automatically creates a Veterinarian Clinic
Assignment.

---

### BR-15 — Clinic Assignment does not create Organization responsibility

A Clinic Assignment must not silently grant Organization administrative or
Appointment-management responsibility.

The professional capabilities available through the Veterinarian path are
evaluated explicitly.

---

### BR-16 — Administrative responsibility does not grant medical access

`OWNER` and `ADMINISTRATOR` must not gain protected Pet medical access solely
because of their Organization authority.

Medical Access Control remains independently required.

---

### BR-17 — Receptionist responsibility does not grant unrestricted medical access

`RECEPTIONIST` Appointment capability must not become unrestricted access to
longitudinal medical history.

Any medical information required by an authorized operational or triage
workflow remains governed by Medical Access Control and least privilege.

---

### BR-18 — Veterinarian capability still requires medical-access basis

`CLINICAL_CARE` or `CLINICAL_DOCUMENTATION` derived from a Veterinary
responsibility does not by itself permit arbitrary Pet access.

The applicable Care Authorization and professional context remain required.

---

### BR-19 — Commercial Entitlement remains independent

Responsibility-derived capability does not replace a required professional
Organization Entitlement.

For paid professional operations:

    responsibility-derived capability
                +
    professional Entitlement
                +
    other applicable domain authorization
                ↓
    operation permitted

---

### BR-20 — Entitlement does not create responsibility

A paid Subscription or Entitlement must not create Organization responsibility
for a User.

---

### BR-21 — Standard Invitation cannot grant Owner

The `OWNER` responsibility must not be granted through the standard
Organization Invitation workflow.

Ownership changes require dedicated behavior.

---

### BR-22 — Delegation must be explicit

A User with invitation capability may only grant responsibilities permitted by
the Phase 1 delegation policy.

The ability to invite does not imply unrestricted delegation.

---

### BR-23 — Pending responsibility grants create no capability

Responsibilities contained in a pending Organization Invitation provide no
current Organization capability.

Capabilities begin only after successful acceptance creates the applicable
active Membership relationship.

---

### BR-24 — Historical responsibility context must not be rewritten by Membership termination

When a Membership ends, previous responsibility information required to
interpret historical actions must not be destructively reassigned to another
User or Organization.

---

### BR-25 — Responsibility evaluation uses current context

A protected operation must evaluate the current applicable Membership,
responsibility, scope, and supporting domain relationships when the operation
is performed.

Previous capability does not create permanent future authority.

---

### BR-26 — Client claims are not authoritative

A manipulated client must not gain a protected capability by asserting:

    role = ADMINISTRATOR

or:

    capability = APPOINTMENT_CONFIRM

Trusted infrastructure must derive the capability from authoritative domain
state.

---

### BR-27 — Capability evaluation does not mutate responsibility state

Checking a capability must not:

- create a responsibility;
- change its scope;
- activate Membership;
- modify Clinic Assignment;
- alter Organization ownership.

---

### BR-28 — Missing capability denies protected operation

When an operation requires a responsibility-derived capability and the acting
User does not currently have that capability in the relevant scope, the
operation must be denied.

---

### BR-29 — Capability denial does not destroy domain state

Authorization denial must not delete or rewrite:

- Membership;
- Appointment;
- Clinic;
- historical professional relationship;
- clinical information.

---

### BR-30 — Custom roles are not supported in Phase 1

Organizations must not define arbitrary custom role or permission bundles in
Phase 1.

The controlled responsibility model provides the supported capability bundles.

Future customizable authorization may be introduced through separate
requirements.

---

## 9. Capability Evaluation

Conceptually:

    authenticated User
            +
    active Organization Membership
            +
    active responsibility
            +
    matching responsibility scope
            ↓
    responsibility-derived capability

Then the target domain adds its own conditions.

Example:

    Maria
    ADMINISTRATOR @ Animalia
            +
    Animalia Madrid Centro belongs to Animalia
            ↓
    CLINIC_MANAGE_PUBLIC_PROFILE

Example:

    Carlos
    RECEPTIONIST @ Madrid Centro
            ↓
    APPOINTMENT_CONFIRM @ Madrid Centro

but:

    Carlos
    RECEPTIONIST @ Madrid Centro
            ↓
    no APPOINTMENT_CONFIRM @ Getafe

Example:

    Dr. Garcia
    VETERINARIAN @ Animalia
            +
    recognized Veterinarian
            +
    valid Clinic Assignment @ Madrid Centro
            +
    applicable Care Authorization
            ↓
    eligible clinical capability @ Madrid Centro

subject to all other Medical Access and Entitlement rules.

---

## 10. Scenarios

### Scenario: Owner has Organization-wide administrative capability

Given Maria has an active Membership in Animalia Veterinary Group
And Maria has the `OWNER` responsibility

When Maria manages an applicable Animalia Clinic configuration

Then the required Organization-derived capability may be satisfied
And Maria's Owner responsibility does not grant medical access

---

### Scenario: Owner capability does not cross Organizations

Given Maria owns Animalia Veterinary Group
And Maria has no applicable Membership in VetCare Group

When Maria attempts a protected VetCare Organization operation

Then the operation is denied
And Animalia ownership is insufficient

---

### Scenario: Organization Administrator manages several Clinics

Given Carlos has an active Animalia Membership
And Carlos has an Organization-scoped `ADMINISTRATOR` responsibility
And Animalia operates Madrid Centro and Getafe

When Carlos performs an applicable Clinic-management operation at Madrid Centro
or Getafe

Then the Organization-scoped capability may apply to each Animalia Clinic
And it does not apply to unrelated Organizations

---

### Scenario: Clinic Administrator is restricted to one Clinic

Given Carlos has an active Animalia Membership
And Carlos has `ADMINISTRATOR` scoped to Madrid Centro
And Animalia also operates Getafe

When Carlos manages Madrid Centro

Then the applicable Clinic capability may be satisfied

When Carlos attempts the equivalent operation at Getafe

Then the Clinic-scoped responsibility is insufficient

---

### Scenario: Clinic Administrator cannot manage Organization Memberships

Given Carlos has `ADMINISTRATOR` scoped only to Madrid Centro

When Carlos attempts to end another Animalia Organization Membership

Then the operation is denied
And Clinic administrative scope does not provide Organization Membership
administration

---

### Scenario: Receptionist manages Appointment lifecycle at scoped Clinic

Given Laura has an active Animalia Membership
And Laura has `RECEPTIONIST` scoped to Madrid Centro

When Laura performs an applicable Appointment-management operation for
Madrid Centro

Then the responsibility may satisfy the Organization capability requirement

---

### Scenario: Receptionist cannot manage another Clinic

Given Laura has `RECEPTIONIST` scoped to Madrid Centro

When Laura attempts the same protected Appointment operation at Getafe

Then the operation is denied unless another applicable responsibility exists

---

### Scenario: Organization-scoped Receptionist supports centralized scheduling

Given Laura has an Organization-scoped `RECEPTIONIST` responsibility in
Animalia
And Animalia operates Madrid Centro and Getafe

When Laura manages applicable Appointments at either Animalia Clinic

Then the responsibility may provide the applicable Appointment capability

---

### Scenario: User holds several responsibilities

Given Dr. Garcia has an active Animalia Membership
And Dr. Garcia has:

    VETERINARIAN @ Animalia
    ADMINISTRATOR @ Madrid Centro

When her capabilities are evaluated

Then both responsibility grants may contribute applicable capabilities
And they remain independently scoped

---

### Scenario: Veterinary responsibility does not create professional identity

Given Carlos has an active Animalia Membership
And Carlos has the `VETERINARIAN` responsibility
And Carlos has no Veterinarian Professional Profile

When Carlos attempts a clinical professional operation

Then the operation is denied
And the Organization responsibility does not establish veterinary
qualification

---

### Scenario: Veterinary responsibility does not assign Clinic

Given Dr. Garcia has the `VETERINARIAN` responsibility in Animalia
And Dr. Garcia has no Clinic Assignment at Animalia Madrid Centro

When Dr. Garcia attempts a Clinic-specific clinical operation at Madrid Centro

Then the operation is denied
And Organization responsibility alone does not establish Clinic practice
context

---

### Scenario: Veterinarian satisfies clinical Organization capability

Given Dr. Garcia has an active Animalia Membership
And Dr. Garcia has the `VETERINARIAN` responsibility
And Dr. Garcia has a recognized Veterinarian Professional Profile
And Dr. Garcia has a valid Clinic Assignment at Madrid Centro
And the applicable Care Authorization exists

When Dr. Garcia performs a supported clinical operation for the authorized Pet
at Madrid Centro

Then the Organization responsibility condition may be satisfied
And all other Medical Access, lifecycle, and Entitlement rules still apply

---

### Scenario: Owner cannot read arbitrary medical history

Given Maria is the Owner of Animalia
And Maria is not otherwise authorized to access Luna's medical history

When Maria attempts to view Luna's protected medical information

Then access is denied
And Organization ownership does not create medical access

---

### Scenario: Administrator delegates allowed responsibility

Given Maria has an Organization-scoped `ADMINISTRATOR` responsibility
And Maria is authorized to invite Organization Members

When Maria creates a standard Invitation granting `RECEPTIONIST` scoped to
Madrid Centro

Then the Invitation may be created
And it may record that responsibility and scope
And the pending Invitation grants no current capability

---

### Scenario: Administrator cannot invite Owner

Given Maria has an Organization-scoped `ADMINISTRATOR` responsibility

When Maria attempts to create a standard Organization Invitation granting
`OWNER`

Then the operation is denied
And Organization ownership is not changed

---

### Scenario: Receptionist cannot delegate responsibilities

Given Laura has a `RECEPTIONIST` responsibility

When Laura attempts to invite another User to Animalia

Then the operation is denied
And Receptionist responsibility does not provide Organization invitation
capability

---

### Scenario: Membership termination removes current capabilities

Given Carlos has an active Membership with `ADMINISTRATOR`
And Carlos's Membership later ends

When Carlos attempts a protected Animalia operation

Then the ended Membership provides no current capability
And the historical Membership remains preserved

---

### Scenario: Responsibility in another Organization is irrelevant

Given Carlos is an Administrator in VetCare
And Carlos has no applicable Animalia responsibility

When Carlos attempts an Animalia administrative operation

Then the operation is denied

---

### Scenario: Client claims false Administrator role

Given Laura is a Receptionist
And a manipulated client claims:

    responsibility = ADMINISTRATOR

When a protected administrative operation is evaluated

Then trusted infrastructure derives Laura's real capabilities
And the false client assertion is ignored
And unauthorized access is denied

---

## 11. Responsibility Changes

This Specification defines responsibility meaning, scope, capability derivation,
and delegation eligibility.

It does not define the workflow for changing the responsibilities of an
existing active Membership after it has been established.

That workflow is defined by `SPEC-ORG-006` — Change Organization Membership
Responsibilities. Responsibility changes must follow it and must not be
implemented as arbitrary editing.

The Phase 1 client workflow for responsibility changes is `SPEC-ORG-006` §14.

The Phase 1 Staff and Veterinarian workforce operations use only existing
catalog capabilities:

| Operation | Capability |
| --- | --- |
| View Organization Staff (`SPEC-ORG-009`) | `ORGANIZATION_INVITE_MEMBERS` or `ORGANIZATION_END_MEMBERSHIPS` |
| Invite (`SPEC-ORG-002`) | `ORGANIZATION_INVITE_MEMBERS` |
| Revoke Invitation (`SPEC-ORG-010`) | `ORGANIZATION_REVOKE_INVITATIONS` |
| End another Member's access (`SPEC-ORG-004` §10) | `ORGANIZATION_END_MEMBERSHIPS` |
| Preview / accept an Invitation (`SPEC-ORG-003`) | none — bearer-secret proof |
| Add / Change / End one Responsibility Grant (`SPEC-ORG-006` §14) | `ORGANIZATION_GRANT_RESPONSIBILITIES` |
| View Organization Veterinarian Workforce (`SPEC-VET-006`) | `ORGANIZATION_GRANT_RESPONSIBILITIES` |
| Establish / end a Veterinarian Clinic Assignment (`SPEC-VET-004` §13, `SPEC-VET-005` §13) | `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for the target Clinic |
| Create own Veterinarian Professional Profile (`SPEC-VET-001` §13) | none — self only, verified account |

No capability is added to the §5 catalog, and no responsibility-to-capability
mapping changes. In Phase 1 the workforce read and the Responsibility
operations are Organization-scoped Owner/Administrator tooling; a
Clinic-scoped Administrator keeps `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for
its Clinic, but no Phase 1 mobile surface is offered to it.

---

## 12. Ownership Changes

`OWNER` has special Organization invariants.

Phase 1 standard responsibility management must not:

- create another Owner through ordinary Invitation;
- transfer ownership implicitly;
- remove the sole active Owner;
- convert another responsibility into Owner through ordinary editing.

Additional Owner or ownership-transfer behavior requires a dedicated
Specification.

---

## 13. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-005 — Organization and Clinic are different concepts.**
- **INV-006 — Organization Membership is temporal.**
- **INV-007 — Clinic Assignment requires Organization Membership.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-015 — Private operations require an authenticated identity.**
- **INV-017 — An Organization must retain an active Owner.**

---

## 14. Dependencies

- SPEC-ID-003 — Authenticate User
- SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
- SPEC-ORG-002 — Invite User to Organization
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-004 — End Organization Membership

Clinic-specific professional capability and Veterinarian Clinic Assignment
management additionally depend on:

- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment

Medical behavior additionally depends on the applicable Medical Access Control
Specifications.

Paid professional operations additionally depend on:

- SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 15. Out of Scope

This Specification does not define:

- changing responsibilities on an existing Membership;
- arbitrary custom Organization roles;
- arbitrary per-User permission overrides;
- ownership transfer;
- adding another Owner;
- Organization archival;
- employment or payroll roles;
- Veterinarian Clinic Assignment lifecycle rules, such as establishment,
  termination, preconditions, and temporal semantics, which are governed by
  `SPEC-VET-004` and `SPEC-VET-005` (this Specification defines only which
  responsibilities provide `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`);
- veterinary credential verification;
- medical-access authorization;
- Subscription Entitlement behavior;
- implementation-specific RBAC libraries;
- database schema;
- Row Level Security policy syntax.

---

## 16. Verification Notes

Verification must demonstrate that:

1. Organization responsibilities belong to Memberships rather than global
   Users;
2. one Membership may hold multiple responsibilities;
3. responsibilities are not mutually exclusive global roles;
4. responsibilities remain Organization-specific;
5. Organization and Clinic responsibility scopes are distinguishable;
6. Clinic-scoped responsibility cannot authorize another Clinic;
7. Organization-scoped Clinic capability applies only to Clinics of the
   applicable Organization;
8. `OWNER` is Organization-scoped;
9. `VETERINARIAN` Organization responsibility does not establish Clinic
   Assignment;
10. capability is derived from active Membership, responsibility, and scope;
11. ended Membership provides no current Organization capability;
12. Owner and Administrator responsibilities do not grant medical access;
13. Receptionist responsibility does not grant unrestricted medical access;
14. Veterinary responsibility does not establish professional qualification;
15. clinical capability additionally requires applicable professional and
    Medical Access context;
16. commercial Entitlement remains independent from responsibility-derived
    capability;
17. standard Invitations cannot grant `OWNER`;
18. Organization-scoped Administrators may delegate supported non-Owner
    responsibilities;
19. Clinic-scoped Administrators, Receptionists, and Veterinarians do not gain
    Organization delegation capability solely from those responsibilities;
20. pending Invitation responsibilities grant no current capability;
21. client-provided role or capability claims are not authoritative;
22. responsibility-derived capability does not cross Organization boundaries;
23. multiple responsibilities may contribute capabilities independently;
24. responsibility evaluation does not mutate domain relationships;
25. custom Organization-defined roles are not required in Phase 1;
26. `ORGANIZATION_MANAGE_SUBSCRIPTION` is provided by active
    Organization-scoped `OWNER` and `ADMINISTRATOR` responsibilities;
27. Clinic-scoped Administrators, Receptionists, Veterinarians, bare
    Membership, Professional Profile, and Clinic Assignment do not provide
    `ORGANIZATION_MANAGE_SUBSCRIPTION`;
28. Subscription management does not require a professional paid Entitlement;
29. `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` is provided by active
    Organization-scoped `OWNER` and `ADMINISTRATOR` responsibilities for every
    Clinic of that Organization;
30. a Clinic-scoped `ADMINISTRATOR` receives
    `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` only for its own Clinic and not
    for another Clinic;
31. `RECEPTIONIST` in any scope, `VETERINARIAN`, Veterinarian Clinic
    Assignment, Professional Profile, bare Membership, and responsibilities in
    another Organization do not provide
    `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`;
32. an ended Membership or ended Responsibility Grant provides no
    `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`;
33. `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` does not require a Subscription
    or professional Entitlement;
34. `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` remains distinct from
    `APPOINTMENT_ASSIGN_VETERINARIAN`;
35. the capability identifiers accepted by the authoritative capability
    evaluation match the Phase 1 catalog in §5.

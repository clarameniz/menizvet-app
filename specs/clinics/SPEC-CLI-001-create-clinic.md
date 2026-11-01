# SPEC-CLI-001 — Create Clinic

**Status:** APPROVED
**Requirements:** REQ-CLI-001, REQ-ORG-005, REQ-ORG-006
**Domain:** Clinics
**Priority:** P0

> **Addendum (Clinic creation self-service Phase 1).** §10 pins the
> client-safe, idempotent creation operation and the Phase 1 mobile Add Clinic
> flow. Business rules BR-1 to BR-11 are unchanged.

## 1. Intent

Allow an authorized Organization Member to create a Clinic operated by a Veterinary Organization.

A Clinic represents a physical veterinary care location and exists as a distinct domain entity from the Veterinary Organization that operates it.

Creating a Clinic establishes its relationship with exactly one Veterinary Organization.

---

## 2. Preconditions

* The Veterinary Organization exists.
* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies any account verification requirement applicable to Clinic administration.
* The acting User has an active Organization Membership in the target Organization.
* The acting User's assigned responsibilities grant the capability to create Clinics.
* The submitted Clinic information satisfies the minimum requirements for Clinic creation.

---

## 3. Business Rules

### BR-1 — A Clinic belongs to a Veterinary Organization

Every Clinic must be associated with exactly one Veterinary Organization.

A Clinic must not exist without an Organization context.

---

### BR-2 — An Organization may operate multiple Clinics

Creating a Clinic must not assume a one-to-one relationship between Veterinary Organization and Clinic.

The same Organization may operate multiple Clinics.

Example:

```text
Animalia Veterinary Group
├── Animalia Madrid Centro
├── Animalia Getafe
└── Animalia Alcobendas
```

---

### BR-3 — Clinic creation requires Organization capability

An authenticated User may create a Clinic only when they have an active Organization Membership whose assigned responsibilities grant the capability to create Clinics.

Authentication or Organization Membership alone is not sufficient.

Capabilities held in another Organization do not authorize Clinic creation in the target Organization.

---

### BR-4 — Clinic identity is independent from Organization identity

A Clinic must have its own domain identity.

The Clinic must not be represented merely as address or profile information embedded directly into the Veterinary Organization.

---

### BR-5 — Clinic creation does not create another Organization

Creating a Clinic must use the existing Veterinary Organization context.

It must not create another Organization or another Organization Membership.

---

### BR-6 — Clinic creation does not assign Veterinarians

Creating a Clinic must not automatically assign any Veterinarian or other Organization Member to that Clinic.

Veterinarian Clinic Assignment is a separate domain relationship.

---

### BR-7 — Organization Membership does not imply Clinic Assignment

Members of the Veterinary Organization must not automatically become assigned to a newly created Clinic.

Clinic-specific professional relationships must be established explicitly through the applicable workflow.

---

### BR-8 — Clinic creation does not automatically make the Clinic publicly discoverable

The existence of a Clinic does not by itself imply that the Clinic is eligible for public discovery.

Public visibility must depend on the requirements defined for Clinic publication and discovery.

This allows a Clinic to exist while its public information is still incomplete or while it is not intended to be publicly visible.

---

### BR-9 — Clinic creation does not grant unrelated capabilities

Creating a Clinic must not automatically grant:

* new Organization responsibilities;
* Veterinarian professional status;
* Pet Guardianship;
* medical record access;
* Clinic Assignment;
* access to another Organization.

---

### BR-10 — Clinic names are not assumed to be globally unique

The platform must not assume that a Clinic's public display name uniquely identifies the Clinic across the entire system.

Different Organizations may operate Clinics with identical or similar public names.

Technical identity must remain independent from the public display name.

---

### BR-11 — Clinic Organization relationship is stable

A Clinic is created within the context of one Veterinary Organization.

This Specification does not allow an existing Clinic to be transferred to another Organization.

Any future transfer, merger, or reorganization workflow must explicitly preserve historical provenance.

---

## 4. Scenarios

### Scenario: Create a Clinic successfully

Given Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities grant the capability to create Clinics
And Animalia Veterinary Group exists
And Maria provides valid Clinic creation information

When Maria creates Animalia Madrid Centro

Then Animalia Madrid Centro is created
And the Clinic belongs to Animalia Veterinary Group
And the Clinic has its own domain identity
And Animalia Veterinary Group continues to exist independently from the Clinic

---

### Scenario: Create multiple Clinics in the same Organization

Given Animalia Veterinary Group already operates Animalia Madrid Centro
And Maria is authorized to create Clinics in Animalia Veterinary Group

When Maria creates Animalia Getafe

Then Animalia Getafe is created
And both Clinics belong to Animalia Veterinary Group
And Animalia Madrid Centro remains unchanged
And the two Clinics have distinct domain identities

---

### Scenario: Unauthorized Organization Member attempts Clinic creation

Given Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities do not grant the capability to create Clinics

When Maria attempts to create a Clinic for Animalia Veterinary Group

Then the operation is denied
And no Clinic is created

---

### Scenario: Member of another Organization attempts Clinic creation

Given Maria has an active Membership in VetCare Group
And Maria has no authorized Membership context in Animalia Veterinary Group

When Maria attempts to create a Clinic for Animalia Veterinary Group

Then the operation is denied
And no Animalia Clinic is created

---

### Scenario: Clinic creation does not assign Organization Members

Given Animalia Veterinary Group has multiple Organization Members

When an authorized User creates Animalia Madrid Centro

Then none of the existing Organization Members are automatically assigned to Animalia Madrid Centro solely because the Clinic was created

---

### Scenario: Clinic creation does not create Veterinarian status

Given Maria is not a recognized Veterinarian
And Maria is authorized to create Clinics

When Maria creates Animalia Madrid Centro

Then the Clinic is created
And Maria does not become a Veterinarian solely because she created the Clinic

---

### Scenario: Clinic creation does not imply public discovery

Given Maria successfully creates Animalia Madrid Centro

When Clinic creation completes

Then the Clinic exists within Animalia Veterinary Group
But the Clinic is not considered publicly discoverable solely because it exists

---

### Scenario: Another Organization uses the same Clinic display name

Given Animalia Veterinary Group operates a Clinic named Veterinary Center
And VetCare Group is authorized to create its own Clinics

When VetCare Group creates a Clinic also named Veterinary Center

Then the new Clinic may have the same public display name
And the Clinics remain distinct domain entities
And each Clinic remains associated with its respective Organization

---

## 5. Edge Cases

### Organization already has Clinics

The existence of one or more Clinics must not prevent an Organization from creating an additional Clinic unless future subscription or commercial rules explicitly impose such a limit.

---

### Incomplete public information

A Clinic may require additional information before becoming publicly discoverable.

Clinic creation and public publication are separate behaviors.

---

### Physical location not yet configured

A Clinic may exist before its physical location is configured.

The absence of a valid location does not invalidate the Clinic itself, but
capabilities that require a known physical location must remain unavailable.

No placeholder geographic position must be inferred merely to satisfy those
capabilities.

---

### Organization subscription limits

Future subscription plans may restrict how many Clinics an Organization may operate.

Such commercial limits must not be assumed by this Specification until defined by subscription Requirements and Specifications.

---

### Organization restructuring

Moving an existing Clinic from one Veterinary Organization to another may affect historical clinical provenance, billing, memberships, and authorization.

Such a workflow is explicitly outside this Specification and requires dedicated behavior if the product later supports it.

---

## 6. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-009 — Historical clinical provenance is immutable.**

---

## 7. Dependencies

* SPEC-ID-003 — Authenticate User
* SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
* SPEC-ORG-003 — Accept Organization Invitation
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
* SPEC-ORG-007 — View My Professional Context (advisory capabilities, §10)
* SPEC-ORG-008 — View My Professional Clinics (§10)
* SPEC-CLI-007 — View Managed Clinic Configuration (post-creation setup, §10)

Authorization follows the responsibility-derived capability model established by the Organization Specifications.

---

## 8. Out of Scope

This Specification does not define:

* Clinic physical-location configuration;
* Clinic public-profile completion;
* publishing a Clinic for public discovery;
* Clinic opening hours;
* Clinic services;
* Clinic archival, closure, or deletion (§10 BR-16);
* Clinic transfer between Organizations;
* Clinic ownership independent from Organization ownership;
* assigning Veterinarians to the Clinic;
* assigning other Organization Members to the Clinic;
* Appointment availability;
* Organization subscription limits;
* geographic discovery;
* medical record creation.

---

## 9. Verification Notes

Verification must demonstrate that:

1. an authorized Organization Member can create a Clinic;
2. unauthorized Users cannot create a Clinic for an Organization;
3. every created Clinic belongs to exactly one Veterinary Organization;
4. an Organization may operate multiple Clinics;
5. each Clinic has an independent domain identity;
6. Clinic creation does not create an Organization or Organization Membership;
7. Clinic creation does not automatically assign Veterinarians or Organization Members;
8. Clinic creation does not establish Veterinarian status;
9. Clinic creation does not automatically make the Clinic publicly discoverable;
10. public display names are not treated as global Clinic identifiers.

### Phase 1 creation contract and mobile flow (§10)

11. only `ORGANIZATION_CREATE_CLINICS` authorizes creation: Owner and
    Organization Administrator succeed; Clinic Administrator, Receptionist,
    Veterinarian, an ended or not-yet-started Membership or Grant, a member of
    another Organization, a User without Membership, and an unknown
    Organization are all denied with the same `42501`, and nothing is written;
12. creation requires no Subscription or professional Entitlement;
13. a created Clinic is unpublished and has no public profile, Location,
    scheduling timezone, standard duration, Appointment Availability, Opening
    Hours, Service Offerings, Clinic Assignment, or Responsibility Grant;
14. the same Organization and creation key return the same Clinic, with no
    second Clinic, for the same or another authorized caller; a different key
    creates another Clinic;
15. the same key in another Organization never returns or reveals the first
    Organization's Clinic;
16. a caller who may not create Clinics in the Organization learns nothing
    from a used key;
17. concurrent creations with the same key produce exactly one Clinic;
18. the new Clinic is immediately a Professional Clinic of the creating
    Organization's Owners and Administrators and of no other Organization, and
    is absent from public Discovery;
19. the creation key is never exposed by a client read and cannot be changed;
20. the client offers Add Clinic only with the advisory capability for the
    selected Organization, asks for confirmation, sends one key per creation
    intent, reuses it only for a deliberate retry of that intent, and opens the
    new Clinic's settings only after an authoritative success.

---

## 10. Phase 1 Clinic creation contract and mobile flow

This section specifies the Phase 1 client-safe creation operation and its
mobile presentation. It does not change Clinic creation into Commercial
Onboarding: Organization establishment, ownership, and the initial
Subscription remain governed by `SPEC-ORG-001` and ADR-009. Adding a Clinic to
an Organization that already exists is operational self-service.

### BR-12 — Creation operation

The client-safe operation is:

    create_clinic(p_organization_id uuid, p_idempotency_key uuid) returns jsonb

It is executable by authenticated clients only. The acting User is derived
from the authenticated subject; the client supplies only the Organization and
the creation key, never authorization facts.

The result is:

    { clinic_id, organization_id, outcome: CREATED | ALREADY_CREATED }

There is no other client-executable way to create a Clinic. The earlier
non-idempotent `create_clinic(p_organization_id uuid)` is withdrawn.

### BR-13 — Authorization and evaluation order

1. authentication and a coherent domain User (`28000`);
2. the current `ORGANIZATION_CREATE_CLINICS` capability in the target
   Organization (BR-3), evaluated before any Organization or Clinic fact is
   disclosed; a nonexistent Organization and one the caller may not create
   Clinics in fail identically with `42501`;
3. the same capability re-evaluated under the target Organization's lock;
4. the creation key is required (`22023`);
5. the creation-key lookup within that Organization;
6. Clinic creation.

No Subscription or professional Entitlement is evaluated (`SPEC-SUB-003`
BR-41). No Clinic-count or plan limit exists in Phase 1 (§5 "Organization
subscription limits").

### BR-14 — Creation key

The creation key identifies one creation intent within one Organization.

- The same Organization and key always return the Clinic created for that key,
  with outcome `ALREADY_CREATED`, and create nothing. This holds for any caller
  currently authorized to create Clinics there, so two administrators
  submitting the same intent obtain one Clinic.
- A different key creates a different Clinic.
- The key is scoped to its Organization. The same key used in another
  Organization is a different intent there: it never returns, reveals, or
  conflicts with the first Organization's Clinic.
- The key lookup happens only after authorization (BR-13), so an unauthorized
  caller learns nothing from a key.
- Concurrent creations in the same Organization are serialized on the
  Organization; concurrent requests with the same key produce exactly one
  Clinic.
- The key is durable, immutable operational metadata of the created Clinic,
  recorded atomically with it. It is not public Clinic information, it is
  never returned by Clinic reads, and it carries no authorization meaning.
- Retrying never depends on display names, timestamps, or comparing Clinic
  lists.

### BR-15 — What creation produces

A created Clinic:

- belongs to exactly the target Organization (BR-1);
- is unpublished (BR-8, `SPEC-CLI-003` BR-1);
- has no public profile, Location, scheduling timezone, standard Appointment
  duration, Appointment Availability, Opening Hours, Service Offerings,
  Veterinarian Clinic Assignment, or Responsibility Grant.

No configuration is auto-populated and no user-entered Clinic field is
required at creation. The Clinic is immediately a Professional Clinic
(`SPEC-ORG-008` BR-3) for the Organization's current Owners and Organization
Administrators, and is configured afterwards through the existing Clinic
settings (`SPEC-CLI-002`, `SPEC-CLI-003`, `SPEC-CLI-004`, `SPEC-CLI-007`,
`SPEC-APT-013`).

Existing, configured, published, and Appointment-ready remain distinct states:
creation produces only an existing Clinic.

### BR-16 — Clinics cannot be removed

Phase 1 provides no Clinic deletion or archival (§8, REQ-CLI-006). An
intentionally created but unwanted Clinic remains unpublished and outside
public Discovery. This is why creation must be idempotent.

### BR-17 — Mobile entry

Canonical placement:

    Professional → selected Organization → Professional Clinics → Add Clinic

The Professional landing offers the Professional Clinics entry for the selected
Organization when either:

- the User has at least one Professional Clinic in that Organization; or
- that Organization's advisory capabilities from `SPEC-ORG-007` include the
  Organization-scoped `ORGANIZATION_CREATE_CLINICS`.

Otherwise the entry is not offered. The Organization is matched by its id,
never by display name.

The Professional Clinics screen offers **Añadir clínica / Add Clinic** only
when the selected Organization's advisory capabilities include
`ORGANIZATION_CREATE_CLINICS`:

- with no Clinics there, the screen shows the Organization, a calm empty state
  explaining that a new Clinic stays private until it is configured and
  published, and Add Clinic as its primary action;
- with Clinics, the list is unchanged and Add Clinic is offered as a secondary
  action that does not dominate it;
- without the capability, no Add action is offered.

The advisory capability is presentation only; the backend authorizes every
creation.

### BR-18 — Mobile creation interaction

1. Add Clinic asks for a single confirmation explaining that the Clinic is
   created private, that Guardians will not see it until it is published, and
   that setup continues in Clinic settings. Cancel creates nothing.
2. Confirming starts one creation intent for the Organization shown, with one
   new client-generated creation key. While it is in flight, Add Clinic and
   the confirmation cannot be submitted again.
3. Only an authoritative result whose Clinic belongs to that Organization is
   success. No placeholder Clinic is shown before it.
4. On success the client opens that Clinic's settings overview directly. The
   overview is the setup checklist. Returning to Professional Clinics shows
   the new Clinic from a fresh read; navigating back never resubmits.
5. On an uncertain result (lost response, network failure, unexpected
   answer), the client keeps that intent — Organization and key — in memory
   and offers a deliberate retry. A retry reuses the same key and therefore
   returns the Clinic if the first attempt committed. While an uncertain
   intent exists for the Organization, the client does not start another
   intent with a new key. Leaving and re-entering the screen in the same app
   session keeps the intent; it is not persisted beyond the app session.
6. A definite rejection (`42501`, `28000`, `22023`) ends the intent with calm
   copy and creates nothing; a later Add Clinic is a new intent with a new key.
7. A changed Organization selection never redirects a pending intent: a retry
   always targets the Organization and key of the original intent.

No wizard and no form fields are part of creation. A display name is set
afterwards in the existing Public Profile editor.

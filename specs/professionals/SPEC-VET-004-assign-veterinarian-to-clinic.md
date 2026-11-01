# SPEC-VET-004 — Assign Veterinarian to Clinic

**Status:** APPROVED  
**Requirements:** REQ-VET-003, REQ-VET-004, REQ-VET-005  
**Domain:** Veterinary Professionals  
**Priority:** P0

## 1. Intent

Allow an authorized actor to establish that a Veterinarian practices at a
specific Clinic operated by a Veterinary Organization.

A Clinic Assignment represents the professional relationship between a
Veterinarian and a physical Clinic.

The Assignment is distinct from:

- Veterinarian Professional Profile;
- Organization Membership;
- professional credential verification;
- Appointment assignment;
- medical-access authorization.

---

## 2. Preconditions

- The target User exists.
- The target User has a Veterinarian Professional Profile.
- The target User has an active Organization Membership in the Veterinary
  Organization that operates the target Clinic.
- The Clinic exists.
- The Clinic belongs to that Veterinary Organization.
- The acting User exists.
- The acting User is authenticated.
- The acting User currently holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`
  for the target Clinic, as defined by `SPEC-ORG-005`.
- No equivalent active Clinic Assignment already exists for the same
  Veterinarian and Clinic.

---

## 3. Business Rules

### BR-1 — Clinic Assignment represents where the Veterinarian practices

A Clinic Assignment establishes that a Veterinarian practices at a specific
physical Clinic.

It must not be treated as the Veterinarian's professional identity.

The Veterinarian Professional Profile remains independent from the Clinic.

---

### BR-2 — Clinic Assignment requires Veterinarian Professional Profile

A User must have a Veterinarian Professional Profile before they may be
assigned to a Clinic as a Veterinarian.

Organization Membership alone is insufficient.

---

### BR-3 — Clinic Assignment requires active Organization Membership

The Veterinarian must have an active Organization Membership in the
Organization that operates the Clinic.

A Clinic Assignment must not be used to bypass the Organization Membership
model.

---

### BR-4 — Clinic and Organization contexts must match

The Organization Membership supporting the professional relationship must
belong to the same Veterinary Organization that operates the Clinic.

For example:

Maria
  Membership → Animalia Veterinary Group

may support:

Maria
  Assignment → Animalia Madrid Centro

but must not support:

Maria
  Assignment → VetCare Toledo

unless Maria also has an applicable active Membership in VetCare Group.

---

### BR-5 — Assignment does not create Organization Membership

Assigning a Veterinarian to a Clinic must not automatically create an
Organization Membership.

The required Organization relationship must already exist.

---

### BR-6 — Assignment does not create or verify professional identity

Creating a Clinic Assignment must not:

- create a Veterinarian Professional Profile;
- mark professional credentials as verified;
- alter professional-verification history.

Professional identity and professional verification are governed separately.

---

### BR-7 — Phase 1 Assignment does not require verified credentials

Phase 1 may establish a Clinic Assignment for a User who has a Veterinarian
Professional Profile even when the professional credential has not completed
the platform verification workflow.

The existence of such an Assignment must not be interpreted as verified
professional qualification.

Operations that explicitly require verified professional status must continue
to enforce that requirement independently.

---

### BR-8 — A Veterinarian may be assigned to multiple Clinics

A Veterinarian may have active Clinic Assignments at more than one Clinic.

Example:

Dr. Garcia
├── Animalia Madrid Centro
└── Animalia Getafe

The domain must not assume a one-Veterinarian-to-one-Clinic relationship.

---

### BR-9 — A Veterinarian may practice across multiple Organizations

A Veterinarian may have Clinic Assignments in Clinics operated by different
Veterinary Organizations when a valid active Organization Membership exists
in each Organization.

For example:

    Dr. Garcia
    ├── Animalia Veterinary Group
    │   ├── Animalia Madrid Centro
    │   └── Animalia Getafe
    │
    └── VetCare Group
        └── VetCare Toledo

Each professional context remains independent.

---

### BR-10 — Clinic Assignment is Clinic-specific

Assignment to one Clinic does not automatically assign the Veterinarian to
other Clinics operated by the same Organization.

For example:

    Assignment → Animalia Madrid Centro

does not imply:

    Assignment → Animalia Getafe

Each Clinic relationship must be explicit.

---

### BR-11 — Clinic Assignment is temporal

A Clinic Assignment represents a professional relationship that exists over
time.

The Assignment must support:

- an effective start;
- an optional effective end.

A newly established Assignment is active and has no effective end.

---

### BR-12 — Assignment start is established when the relationship begins

For the Phase 1 workflow defined by this Specification, a Clinic Assignment
becomes effective when the Assignment operation succeeds.

Scheduled future Assignments are outside this Specification.

---

### BR-13 — Active duplicate Assignment must not be created

A Veterinarian must not have multiple simultaneously active Clinic
Assignments representing the same relationship with the same Clinic.

Historical Assignments from separate professional periods may coexist.

---

### BR-14 — Assignment history must remain preservable

The model must support a Veterinarian leaving a Clinic and later returning
without rewriting the earlier professional period.

Conceptually:

    Dr. Garcia → Animalia Madrid Centro

    Assignment #1
    2026-01-15 → 2027-09-30

    Assignment #2
    2028-04-01 → active

These represent distinct professional periods.

The workflow for ending an Assignment is defined separately.

---

### BR-15 — Creating an Assignment does not grant arbitrary Clinic authority

Clinic Assignment indicates where the Veterinarian practices.

It must not by itself grant unrelated capabilities such as:

- managing Organization Members;
- managing subscription or billing;
- creating Clinics;
- publishing Clinics;
- arbitrary Appointment administration.

Such capabilities depend on the applicable responsibility-derived
authorization model.

---

### BR-16 — Clinic Assignment does not grant universal medical access

Being assigned to a Clinic must not automatically grant access to arbitrary
Pets or Medical Records.

Professional medical access requires the applicable authorization context.

---

### BR-17 — Clinic Assignment does not create Pet relationships

Assigning a Veterinarian to a Clinic must not:

- create Pet Guardianship;
- associate arbitrary Pets with the Veterinarian;
- create Medical Record Entries;
- create Appointments.

---

### BR-18 — Organization Membership termination overrides current Clinic authority

If the Organization Membership supporting a Clinic Assignment ends, the
Assignment must no longer provide current professional authority within that
Organization.

Historical Clinic Assignment information must remain preserved.

The detailed Assignment termination lifecycle is governed separately.

---

### BR-19 — Only authorized actors may establish Clinic Assignments

The acting User must currently hold `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`
for the target Clinic, as defined by `SPEC-ORG-005`.

Authentication, Organization Membership, Veterinarian Professional Profile, the
`VETERINARIAN` responsibility, the `RECEPTIONIST` responsibility, or a Clinic
Assignment is not sufficient unless the acting User's current responsibilities
provide that capability.

This applies equally when the target Veterinarian is the acting User.

Establishing a Clinic Assignment is not a paid professional operation and does
not require a Subscription or professional Entitlement.

---

### BR-20 — Authorization is scoped to the target Clinic

`CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` held for one Clinic must not
automatically authorize managing Assignments for another Clinic.

Organization-wide authority applies only where `SPEC-ORG-005` explicitly
provides it: an active Organization-scoped `OWNER` or `ADMINISTRATOR`
responsibility provides the capability for every Clinic of that Organization,
while a Clinic-scoped `ADMINISTRATOR` responsibility provides it only for its
own Clinic.

---

### BR-21 — Assignment creation must be atomic

A successful Assignment operation must establish one valid professional
relationship containing all required context.

The system must not expose a partial Assignment missing its:

- Veterinarian;
- Clinic;
- Organization context;
- effective start.

---

## 4. Clinic Assignment Information

The domain must support enough information to understand the professional
Clinic relationship.

### Required

- Veterinarian;
- Clinic;
- supporting Organization context;
- effective start.

### Optional while active

- effective end.

The Assignment may later require additional professional scheduling or
operational information, but such information must not be introduced until
the applicable behavior requires it.

---

## 5. Scenarios

### Scenario: Assign Veterinarian to Clinic successfully

Given Maria has a Veterinarian Professional Profile  
And Maria has an active Membership in Animalia Veterinary Group  
And Animalia Madrid Centro belongs to Animalia Veterinary Group  
And Carlos holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Animalia Madrid Centro

When Carlos assigns Maria to Animalia Madrid Centro

Then an active Clinic Assignment is created  
And the Assignment identifies Maria as the Veterinarian  
And the Assignment identifies Animalia Madrid Centro as the Clinic  
And the Assignment has an effective start  
And the Assignment has no effective end

---

### Scenario: Veterinarian may be assigned to multiple Clinics in the same Organization

Given Maria has an active Membership in Animalia Veterinary Group  
And Maria already has an active Assignment at Animalia Madrid Centro  
And Animalia Getafe also belongs to Animalia Veterinary Group  
And Carlos holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Animalia Getafe

When Carlos assigns Maria to Animalia Getafe

Then Maria has an active Assignment at Animalia Madrid Centro  
And Maria has an active Assignment at Animalia Getafe  
And both Assignments remain distinct professional relationships

---

### Scenario: Veterinarian may practice across multiple Organizations

Given Maria has an active Membership in Animalia Veterinary Group  
And Maria has an active Membership in VetCare Group  
And Maria has a Veterinarian Professional Profile  
And Animalia Madrid Centro belongs to Animalia Veterinary Group  
And VetCare Toledo belongs to VetCare Group

When Maria is validly assigned to each Clinic through the applicable authorized workflows

Then Maria may have an active Clinic Assignment at Animalia Madrid Centro  
And Maria may have an active Clinic Assignment at VetCare Toledo  
And the two professional contexts remain distinct

---

### Scenario: Organization Membership does not assign all Clinics

Given Maria has an active Membership in Animalia Veterinary Group  
And Animalia operates Madrid Centro and Getafe  
And Maria has only been assigned to Madrid Centro

When Maria's current Clinic Assignments are evaluated

Then Maria is assigned to Madrid Centro  
And Maria is not assigned to Getafe solely because of Organization Membership

---

### Scenario: User without Veterinarian Professional Profile cannot be assigned as Veterinarian

Given Carlos has an active Membership in Animalia Veterinary Group  
And Carlos does not have a Veterinarian Professional Profile

When an authorized actor attempts to assign Carlos to Animalia Madrid Centro as a Veterinarian

Then the operation is denied  
And no Veterinarian Clinic Assignment is created

---

### Scenario: Veterinarian without Organization Membership cannot be assigned

Given Maria has a Veterinarian Professional Profile  
And Maria has no active Membership in Animalia Veterinary Group

When an authorized actor attempts to assign Maria to Animalia Madrid Centro

Then the operation is denied  
And no Clinic Assignment is created

---

### Scenario: Membership in another Organization is insufficient

Given Maria has a Veterinarian Professional Profile  
And Maria has an active Membership in VetCare Group  
And Maria has no active Membership in Animalia Veterinary Group

When an authorized actor attempts to assign Maria to Animalia Madrid Centro

Then the operation is denied  
And Maria's VetCare Membership does not authorize an Animalia Assignment

---

### Scenario: Unverified Veterinarian may have Phase 1 Clinic Assignment

Given Maria has a Veterinarian Professional Profile  
And Maria's professional credential has not completed platform verification  
And Maria has an active Membership in Animalia Veterinary Group  
And Carlos holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Animalia Madrid Centro

When Carlos assigns Maria to Animalia Madrid Centro

Then the Clinic Assignment may be created  
And Maria remains professionally unverified  
And the Assignment must not be represented as proof of verified qualification  
And operations requiring verified status remain unavailable

---

### Scenario: Assignment does not grant medical access

Given Maria has a valid Clinic Assignment at Animalia Madrid Centro  
And Maria has no authorized medical-access context for Luna

When Maria attempts to access Luna's protected medical history solely because of the Clinic Assignment

Then access is denied

---

### Scenario: Duplicate active Assignment is not created

Given Maria already has an active Clinic Assignment at Animalia Madrid Centro

When an authorized actor attempts to establish the same active Assignment again

Then another active equivalent Assignment is not created  
And the existing Assignment remains authoritative

---

### Scenario: Assignment does not create administrative capabilities

Given Maria is validly assigned to Animalia Madrid Centro as a Veterinarian  
And Maria's Organization responsibilities do not grant Clinic-administration capabilities

When Maria attempts an administrative operation outside her granted responsibilities

Then Clinic Assignment alone does not authorize the operation

---

### Scenario: Organization Membership later ends

Given Maria has an active Clinic Assignment at Animalia Madrid Centro  
And that Assignment is supported by Maria's active Animalia Organization Membership

When Maria's Animalia Organization Membership later ends

Then the Clinic Assignment no longer grants current professional authority  
And the historical Assignment remains identifiable  
And professional history is not deleted

---

### Scenario: Assignment creates no Pet or clinical activity

Given Maria is validly assigned to Animalia Madrid Centro

When the Assignment is created

Then no Pet Guardianship is created  
And no Appointment is created  
And no Medical Record Entry is created  
And no arbitrary medical access is granted

---

### Scenario: Clinic-scoped Administrator cannot assign at another Clinic

Given Ana holds a Clinic-scoped `ADMINISTRATOR` responsibility for Animalia Getafe
And Maria has a Veterinarian Professional Profile and an active Membership in Animalia Veterinary Group

When Ana attempts to assign Maria to Animalia Madrid Centro

Then the operation is denied
And no Clinic Assignment is created

---

### Scenario: Receptionist cannot establish a Clinic Assignment

Given Luis holds a `RECEPTIONIST` responsibility in Animalia Veterinary Group
And Maria has a Veterinarian Professional Profile and an active Membership in Animalia Veterinary Group

When Luis attempts to assign Maria to Animalia Madrid Centro

Then the operation is denied
And no Clinic Assignment is created

---

### Scenario: Veterinarian cannot assign themselves without the capability

Given Maria has a Veterinarian Professional Profile
And Maria holds only the Organization-scoped `VETERINARIAN` responsibility in Animalia Veterinary Group

When Maria attempts to assign herself to Animalia Madrid Centro

Then the operation is denied
And no Clinic Assignment is created

---

### Scenario: Assignment does not require professional Entitlement

Given Animalia Veterinary Group currently has no normal professional Entitlement
And Carlos holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Animalia Madrid Centro
And Maria satisfies the Assignment preconditions

When Carlos assigns Maria to Animalia Madrid Centro

Then an active Clinic Assignment is created

---

## 6. Professional Relationship Model

The relationship should be understood conceptually as:

    User
      ↓
    Veterinarian Professional Profile

and independently:

    User
      ↓
    Organization Membership
      ↓
    Veterinary Organization
      ↓
    Clinic

with:

    Veterinarian Professional Profile
            +
    active Organization Membership
            +
    Clinic
            ↓
    Veterinarian Clinic Assignment

These concepts must not be collapsed into a single global Veterinarian role.

---

## 7. Temporal Model

A Veterinarian may have several professional periods at the same Clinic.

Example:

    Maria Garcia
    Animalia Madrid Centro

    Assignment #1
    Started: 2026-02-01
    Ended:   2027-06-30

    Assignment #2
    Started: 2028-01-15
    Ended:   active

The first Assignment remains historical.

The second represents the current professional relationship.

Rejoining must not erase the gap between professional periods.

---

## 8. Edge Cases

### Professional verification occurs after Assignment

A Veterinarian may receive a Phase 1 Clinic Assignment before completing the
future credential-verification workflow.

Later successful professional verification must not require creation of a new
Clinic Assignment.

The same Assignment may continue to represent where the Veterinarian
practices.

---

### Professional verification fails

A failed verification outcome must not be interpreted as successful
qualification simply because a Clinic Assignment already exists.

Capabilities explicitly requiring verified professional status must remain
unavailable.

Future policy may determine whether failed verification requires suspension
or termination of existing professional Assignments.

That behavior is outside this Specification.

---

### Organization operates only one Clinic

Even when an Organization currently operates a single Clinic, the Assignment
must still be represented as Clinic-specific.

The domain must not collapse Organization Membership and Clinic Assignment
because the Organization currently has only one physical location.

---

### Clinic becomes unpublished

Unpublishing a Clinic must not automatically terminate professional Clinic
Assignments.

Public visibility and professional operational relationships are separate
concerns.

---

### Clinic later closes

Permanent Clinic closure may require ending active Clinic Assignments.

Clinic closure behavior has not yet been specified and must not be inferred
from public unpublication.

---

## 9. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-007 — Clinic Assignment may be temporal.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 10. Dependencies

- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-CLI-001 — Create Clinic
- SPEC-ID-003 — Authenticate User

Professional verification behavior is defined by:

- SPEC-VET-002 — Request Veterinarian Credential Verification
- SPEC-VET-003 — Resolve Veterinarian Credential Verification

but Phase 1 Clinic Assignment does not require successful credential
verification.

---

## 11. Out of Scope

This Specification does not define:

- ending a Clinic Assignment;
- scheduled future Assignment;
- backdated Assignment;
- Clinic closure;
- professional availability;
- Appointment assignment;
- Appointment-management permissions;
- medical-record access;
- clinical-record creation;
- public Veterinarian visibility;
- professional credential verification;
- suspension after failed professional verification;
- employment contracts or employment-law semantics;
- compensation or payroll.

---

## 12. Verification Notes

Verification must demonstrate that:

1. a Veterinarian with an active applicable Organization Membership may be assigned to a Clinic by an authorized actor;
2. a Veterinarian Professional Profile is required;
3. active Organization Membership in the Clinic's Organization is required;
4. Membership in another Organization is insufficient;
5. Clinic Assignment does not create Organization Membership;
6. Clinic Assignment does not create or verify professional identity;
7. Phase 1 Assignment may exist without verified professional credentials;
8. one Veterinarian may have active Assignments at multiple Clinics;
9. one Veterinarian may have valid Assignments across multiple Organizations;
10. Organization Membership does not imply Assignment to every Clinic;
11. duplicate active Clinic Assignments are not created;
12. Clinic Assignment is temporal and preserves its effective start;
13. Clinic Assignment alone does not grant administrative or medical access;
14. Organization Membership termination removes current professional authority derived from the Assignment without deleting history;
15. Clinic unpublication does not automatically end professional Assignment;
16. Assignment creation does not create Pets, Appointments, or clinical data;
17. `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for the target Clinic is required
    to establish a Clinic Assignment;
18. an active Organization-scoped `OWNER` or `ADMINISTRATOR` may establish an
    Assignment at any Clinic of that Organization;
19. a Clinic-scoped `ADMINISTRATOR` may establish an Assignment only at its own
    Clinic and is denied at another Clinic;
20. `RECEPTIONIST` in any scope, `VETERINARIAN` alone (including
    self-assignment), bare Membership, an ended Membership or Responsibility
    Grant, and an administrator of another Organization are denied;
21. a target without a Professional Profile, with a Profile belonging to a
    different User, or without an active Membership in the Clinic's
    Organization is rejected;
22. establishing an Assignment does not require a Subscription or professional
    Entitlement;
23. only authenticated Users may invoke Assignment establishment.

---

## 13. Phase 1 client Assignment contract

Defined by **Staff Responsibility Editing + Veterinarian Enablement — Phase 1**.
It narrows BR-1–BR-21 for the client; it does not change them or the domain
invariants.

### BR-22 — Canonical Phase 1 operation

The client establishes a Clinic Assignment only through

    assign_staff_veterinarian_to_clinic(
        p_organization_id uuid,
        p_membership_id uuid,
        p_clinic_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. The acting User is derived from the authenticated subject.

The client never supplies a Professional Profile identifier. The Profile is
resolved server-side from the target Membership's User, which has at most one
Profile (`SPEC-VET-001` BR-2), so the Assignment's Profile and Membership always
belong to the same User (BR-2–BR-4).

The pre-existing `assign_veterinarian_to_clinic(uuid, uuid, uuid)` takes a
client Profile identifier and reports existence and lifecycle before
authorization. It is not a client path: client `EXECUTE` is withdrawn and it
remains for trusted compatibility only.

### BR-23 — Client-safe prerequisite: a current VETERINARIAN Grant

In addition to §2, the client-safe operation requires the target Membership to
hold a current Organization-scoped `VETERINARIAN` Responsibility Grant. The
product therefore cannot create a Clinic Assignment for a Member who holds no
`VETERINARIAN` Responsibility.

This is a Phase 1 client policy. The domain model is unchanged: historical or
trusted Assignment rows without such a Grant may exist and remain valid
history, and ending them stays possible (`SPEC-VET-005` §13).

### BR-24 — Fail-closed ordering

1. authentication and a coherent domain User — otherwise `28000`;
2. the named Clinic belongs to the named Organization and the acting User holds
   `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for it (BR-19, BR-20), decided
   together and re-decided under the Organization and Clinic locks — a
   nonexistent Organization or Clinic, a Clinic of another Organization, and a
   missing capability fail identically with SQLSTATE `42501` and one fixed
   message;
3. the target Membership within the named Organization — a nonexistent target
   and another Organization's Membership fail exactly as step 2;
4. lifecycle and prerequisites (`23514`): Membership not current
   (`MEMBERSHIP_INACTIVE`), no current Organization-scoped `VETERINARIAN` Grant
   (`VETERINARIAN_RESPONSIBILITY_REQUIRED`), no Professional Profile
   (`PROFILE_REQUIRED`);
5. an equivalent open Assignment — `ALREADY_ASSIGNED` (BR-13).

Errors carry fixed messages and stable hints, never raw database text.

### BR-25 — Outcomes, timestamps, concurrency

| Outcome | Meaning | Result members |
| --- | --- | --- |
| `ASSIGNED` | a new active Assignment began | `veterinarian_clinic_assignment_id`, `membership_id`, `clinic_id`, `effective_start` |
| `ALREADY_ASSIGNED` | an equivalent open Assignment exists; nothing is written | same, for that Assignment |

- The Assignment starts at the statement instant, never before its supporting
  Membership started (BR-12). No future or backdated start is accepted.
- The operation serializes on the Organization, then the Clinic, then the
  Membership, as the Responsibility and End access operations do, so a
  concurrent Membership end or `VETERINARIAN` end is either fully before
  (rejection) or fully after (the later operation sees the Assignment).
- No client idempotency key is used; a retry or lost response reconciles
  through `ALREADY_ASSIGNED` and the workforce read (`SPEC-VET-006`).
- The operation requires no Subscription or Entitlement (BR-19).

### Mobile presentation

In the Staff Member detail Veterinarian section (`SPEC-ORG-009` §7), offered
only to an actor whose advisory capabilities include
`ORGANIZATION_GRANT_RESPONSIBILITIES` (Phase 1 Organization Owner/Administrator
tooling):

- the Assign action — shown as **Add / Añadir** beside the **Clinics /
  Clínicas** subtitle, with the accessible name "Add Veterinarian clinic /
  Añadir clínica de Veterinario/a" — is shown only when the Member holds a
  current `VETERINARIAN` Grant and has a Professional Profile;
- when the Profile is missing the section states "Veterinarian profile pending
  — completed by the professional / Perfil veterinario pendiente — lo completa
  el profesional" and offers no Assign action; no one but the professional
  completes it;
- the Clinic is chosen from the route Organization's Clinics that do not
  already have a current Assignment for that Member;
- after every outcome the client re-reads the Staff and workforce reads.

A Clinic-scoped Administrator keeps the domain capability for its own Clinic,
but no Phase 1 mobile surface is offered to it.

## 14. Phase 1 client Assignment Verification Notes

In addition to §12, verification must demonstrate that:

24. an Organization Owner/Administrator assigns a Member holding `VETERINARIAN`
    and a Profile to one Clinic and then another, with both current;
25. a repeat returns `ALREADY_ASSIGNED` with the same Assignment;
26. a Member without a Profile, without a current `VETERINARIAN` Grant, or with
    an ended Membership is rejected with nothing written;
27. a Clinic of another Organization, an unknown Clinic, an unknown Membership,
    another Organization's Membership, and a caller without the capability fail
    identically with `42501`;
28. the operation accepts no Profile identifier;
29. the Assignment starts at the statement instant, not before the Membership;
30. concurrent assign/assign, assign/Membership end, and assign/`VETERINARIAN`
    end produce coherent outcomes with no deadlock;
31. no client role executes the generic Assignment operation.

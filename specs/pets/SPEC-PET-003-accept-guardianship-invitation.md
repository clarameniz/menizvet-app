# SPEC-PET-003 — Accept Guardianship Invitation

**Status:** APPROVED
**Requirements:** REQ-PET-003, REQ-PET-004, REQ-PET-006
**Domain:** Pets
**Priority:** P0

## 1. Intent

Allow the intended recipient of a valid Guardianship Invitation to explicitly accept the Invitation and establish an active Guardianship relationship with the existing Pet.

Acceptance gives another User a relationship with the same Pet domain entity.

It must not create a duplicate Pet.

The resulting model may therefore represent:

```text
             Luna
            /    \
           /      \
Guardianship    Guardianship
     /                \
  Maria              Carlos
```

Both Users relate to the same Pet.

---

## 2. Preconditions

* The Pet exists.
* The Guardianship Invitation exists.
* The Invitation refers to that Pet.
* The Invitation is pending.
* The Invitation has not expired.
* The Invitation has not been revoked.
* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies the account verification requirements applicable to Guardianship acceptance.
* The acting User has proven that they are the intended recipient of the Invitation.
* The acting User does not already have an equivalent active Guardianship relationship with the Pet.

---

## 3. Business Rules

### BR-1 — Acceptance must be explicit

A Guardianship relationship must not become active merely because an Invitation exists.

The intended recipient must explicitly accept the Invitation.

---

### BR-2 — Only the intended recipient may accept

A Guardianship Invitation may only be accepted by the User who has proven that they are its intended recipient.

Possession of an Invitation reference alone is insufficient.

---

### BR-3 — Acceptance creates Guardianship with the existing Pet

Successful acceptance must establish an active Guardianship relationship between the accepting User and the Pet identified by the Invitation.

The existing Pet must be reused.

Acceptance must not create another Pet representing the same invited Pet.

---

### BR-4 — Existing Guardians remain unchanged

Creating an additional Guardianship must not replace, remove, or otherwise modify existing Guardianship relationships.

Example:

```text
Before:

Maria ── Guardianship ── Luna


After Carlos accepts:

Maria  ── Guardianship ── Luna
Carlos ── Guardianship ── Luna
```

Maria's relationship remains unchanged.

---

### BR-5 — Existing Pets of the accepting User remain unchanged

If the accepting User already has Guardianship relationships with other Pets, those relationships must remain unchanged.

Example:

```text
Before:

Carlos ── Guardianship ── Toby


After accepting Luna:

Carlos
├── Guardianship ── Toby
└── Guardianship ── Luna
```

Toby and Luna remain distinct Pet entities.

---

### BR-6 — Acceptance does not create a domain User

The accepting User must already exist before Guardianship can be established.

If the recipient did not have an account when the Invitation was issued, they must complete the required Identity workflow before acceptance.

Registration and Invitation acceptance are separate operations.

---

### BR-7 — Invitation destination does not determine User identity

The Invitation may have been delivered to a contact address different from the authentication identifier used by the accepting User.

After the User proves control of the intended Invitation recipient context, the Guardianship must be established with the existing domain User.

A second User must not be created solely to match the Invitation destination.

---

### BR-8 — Guardianship creation and Invitation acceptance are atomic

Accepting the Invitation and establishing the corresponding Guardianship form one logical domain operation.

The Invitation must not become accepted if the Guardianship cannot be established.

Likewise, the Guardianship must not be established while leaving the Invitation pending.

---

### BR-9 — An accepted Invitation cannot be accepted again

Once successfully accepted, an Invitation must no longer be usable to establish another Guardianship.

Repeated acceptance attempts must not:

* create another Guardianship;
* create another Pet;
* duplicate access;
* modify existing relationships.

---

### BR-10 — Expired Invitations cannot be accepted

An expired Guardianship Invitation must not establish Guardianship.

---

### BR-11 — Revoked Invitations cannot be accepted

A revoked Guardianship Invitation must not establish Guardianship.

---

### BR-12 — Duplicate active Guardianship must not be created

A User must not have multiple simultaneous active Guardianship relationships representing the same relationship with the same Pet.

If the User already has an equivalent active Guardianship, acceptance must not create another one.

---

### BR-13 — Phase 1 Guardians receive the standard Guardianship relationship

Phase 1 does not define different Guardian roles, levels, or custom permissions.

A Guardianship created through Invitation acceptance establishes the same standard Guardian relationship used by the Phase 1 Pet domain.

Future requirements may introduce differentiated Guardian responsibilities without changing the identity of the Pet or User.

---

### BR-14 — Acceptance does not grant access to other Pets

Accepting an Invitation for one Pet must not grant Guardianship or access to any other Pet associated with the inviting Guardian.

An Invitation for Luna concerns Luna only.

---

### BR-15 — Acceptance does not grant unrelated professional capabilities

Accepting Guardianship must not automatically grant:

* Veterinarian professional status;
* Organization Membership;
* Clinic Assignment;
* Organization administrative capabilities;
* access to unrelated medical records.

---

### BR-16 — Guardianship and medical access remain conceptually distinct

Establishing Guardianship may make the User eligible for Pet-related capabilities defined by applicable Specifications.

The precise medical information a Guardian may view or authorize must be governed by the Medical Records and Access Control Specifications.

This Specification must not independently define the complete medical-access model.

---

### BR-17 — Inviter departure does not automatically invalidate the Invitation

A valid pending Invitation must not become invalid solely because the Guardian who originally created it later loses or ends their Guardianship relationship.

Invitation validity continues to depend on:

* its own state;
* expiration;
* revocation;
* other explicitly defined validity rules.

---

## 4. Scenarios

### Scenario: Existing User accepts Guardianship Invitation

Given Maria is an active Guardian of Luna
And Maria previously invited Carlos to become a Guardian of Luna
And Carlos is an existing User
And the Invitation is pending, unexpired, and unrevoked
And Carlos has proven that he is the intended recipient

When Carlos accepts the Invitation

Then the Invitation becomes accepted
And an active Guardianship relationship is created between Carlos and Luna
And Luna remains the same Pet domain entity
And Maria's existing Guardianship remains unchanged

---

### Scenario: Existing User already has another Pet

Given Carlos already has Guardianship of Toby
And Carlos has a valid pending Guardianship Invitation for Luna

When Carlos accepts the Invitation

Then Carlos gains Guardianship of Luna
And Carlos's Guardianship of Toby remains unchanged
And Luna and Toby remain distinct Pet entities
And no Pet is duplicated

---

### Scenario: Recipient had no account when invited

Given Maria sent a Guardianship Invitation for Luna to a person who did not yet have a platform account
And the Invitation remains valid
And the recipient later completes the required registration and verification workflow
And the resulting User proves control of the intended Invitation recipient context

When the User accepts the Invitation

Then an active Guardianship relationship is established between that User and Luna
And the existing Luna Pet is reused
And no additional domain User is created during acceptance

---

### Scenario: Invitation does not automatically accept after registration

Given a person received a Guardianship Invitation before having an account
And the person later registers successfully

When registration completes

Then the Invitation remains unaccepted
And no Guardianship is established solely because registration completed

---

### Scenario: Another User cannot accept the Invitation

Given Carlos is the intended recipient of a Guardianship Invitation for Luna
And Laura is authenticated
And Laura has not proven that she is the intended recipient

When Laura attempts to accept the Invitation

Then the operation is denied
And no Guardianship between Laura and Luna is created
And Luna remains unchanged

---

### Scenario: Accepted Invitation cannot be reused

Given Carlos has already successfully accepted a Guardianship Invitation for Luna
And Carlos has an active Guardianship relationship with Luna

When acceptance of the same Invitation is attempted again

Then no additional Guardianship is created
And no additional Pet is created
And Carlos's existing Guardianship remains unchanged

---

### Scenario: Expired Invitation cannot be accepted

Given Carlos has a Guardianship Invitation for Luna
And the Invitation has expired

When Carlos attempts to accept the Invitation

Then the operation is denied
And no Guardianship is created
And the Invitation does not become accepted

---

### Scenario: Revoked Invitation cannot be accepted

Given Carlos has a Guardianship Invitation for Luna
And the Invitation has been revoked

When Carlos attempts to accept the Invitation

Then the operation is denied
And no Guardianship is created
And the Invitation does not become accepted

---

### Scenario: User already has Guardianship

Given Carlos already has an active Guardianship relationship with Luna
And an equivalent Invitation still exists because of a concurrent or historical condition

When Carlos attempts to accept that Invitation

Then another Guardianship is not created
And Luna is not duplicated
And Carlos's existing relationship remains unchanged

---

### Scenario: Invitation for Luna grants no relationship with Toby

Given Maria has Guardianship of Luna
And Maria also has Guardianship of Toby
And Carlos has a valid Invitation for Luna

When Carlos accepts the Invitation

Then Carlos gains Guardianship of Luna
And Carlos gains no Guardianship of Toby solely because of that acceptance

---

### Scenario: Recipient authenticates using a different identifier

Given a Guardianship Invitation for Luna was delivered to Carlos's professional email address
And Carlos already has a domain User authenticated through another supported identifier
And Carlos proves control of the intended Invitation recipient context

When Carlos accepts the Invitation

Then Carlos's existing domain User receives the Guardianship relationship with Luna
And no second User is created
And no duplicate Pet is created

---

### Scenario: Guardianship creation fails during acceptance

Given Carlos has a valid pending Guardianship Invitation for Luna

When the required Guardianship relationship cannot be established

Then the acceptance operation fails
And the Invitation must not be considered successfully accepted
And no partial Guardianship relationship is exposed

---

### Scenario: Inviting Guardian loses Guardianship before acceptance

Given Maria validly invited Carlos to become a Guardian of Luna
And the Invitation remains pending, unexpired, and unrevoked
And Maria later ceases to be a Guardian of Luna

When Carlos accepts the still-valid Invitation

Then the Invitation may still be accepted
And Carlos's Guardianship with Luna is established
And Maria's current Guardianship state does not retroactively invalidate the Invitation

---

## 5. Edge Cases

### Recipient has many existing Pets

The number of Pets already associated with the accepting User must not affect their ability to accept a valid Guardianship Invitation unless a future explicit product rule introduces such a restriction.

---

### Multiple existing Guardians

The Pet may already have multiple Guardians.

Acceptance establishes another Guardianship without replacing existing relationships.

---

### Pet identity changed in presentation

Public or profile information about the Pet may have changed since the Invitation was created.

The Invitation must still identify the same Pet domain entity rather than relying on mutable information such as Pet name.

---

### Invitation becomes invalid during acceptance

Invitation validity must be evaluated as part of the acceptance operation.

A Guardianship must not be created from an Invitation that is no longer valid when the acceptance is processed.

---

### Concurrent acceptance attempts

Multiple simultaneous acceptance attempts for the same Invitation must result in at most one new active Guardianship.

---

### Pet already appears in recipient's account

If the User already has a valid active Guardianship relationship with the Pet, the system must not create another Pet or another equivalent Guardianship simply to satisfy the Invitation workflow.

---

## 6. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**

---

## 7. Dependencies

* SPEC-ID-001 — Register User
* SPEC-ID-002 — Verify Email Address
* SPEC-ID-003 — Authenticate User
* SPEC-PET-001 — Register Pet
* SPEC-PET-002 — Invite Guardian to Pet

---

## 8. Out of Scope

This Specification does not define:

* rejecting a Guardianship Invitation;
* revoking a Guardianship Invitation;
* resending Invitation communication;
* replacing an expired Invitation;
* removing an active Guardian;
* ending Guardianship;
* transferring Guardianship;
* differentiated Guardian roles;
* per-Guardian custom permissions;
* primary-Guardian semantics;
* Pet deletion or archival;
* Pet merging;
* duplicate-Pet reconciliation;
* detailed medical-record visibility;
* medical-access authorization;
* professional veterinary access.

---

## 9. Verification Notes

Verification must demonstrate that:

1. the intended recipient can accept a valid Guardianship Invitation;
2. acceptance creates a Guardianship with the existing Pet;
3. acceptance does not create a duplicate Pet;
4. existing Guardians remain unchanged;
5. the accepting User's other Pets and Guardianships remain unchanged;
6. a recipient without an account must complete Identity before acceptance;
7. registration alone does not automatically accept an Invitation;
8. acceptance does not create a second domain User;
9. Invitations cannot be accepted by unauthorized Users;
10. expired or revoked Invitations cannot establish Guardianship;
11. an accepted Invitation cannot be reused;
12. duplicate active Guardianships are not created;
13. acceptance and Guardianship creation behave atomically;
14. an Invitation concerning one Pet grants no relationship with another Pet;
15. Phase 1 acceptance establishes the standard Guardianship relationship;
16. using a different authentication identifier does not require a duplicate User;
17. concurrent acceptance attempts create at most one Guardianship;
18. the inviter losing Guardianship does not retroactively invalidate an otherwise valid Invitation.

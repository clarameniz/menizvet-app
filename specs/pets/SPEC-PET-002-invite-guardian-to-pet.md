# SPEC-PET-002 — Invite Guardian to Pet

**Status:** APPROVED
**Requirements:** REQ-PET-003, REQ-PET-004, REQ-PET-006
**Domain:** Pets
**Priority:** P0

## 1. Intent

Allow an authorized Guardian of a Pet to invite another person to establish a Guardianship relationship with that Pet.

Creating a Guardianship Invitation does not immediately grant the recipient access to the Pet.

The intended recipient must explicitly accept the Invitation before a Guardianship relationship is established.

---

## 2. Preconditions

* The Pet exists.
* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies any account verification requirement applicable to Guardianship management.
* The acting User has an active Guardianship relationship with the Pet.
* The Invitation identifies the intended recipient.

---

## 3. Business Rules

### BR-1 — Guardianship Invitation requires an authorized Guardian

A User may invite another person to become a Guardian only when their active Guardianship relationship grants the capability to manage Guardianship for that Pet.

Authentication alone is not sufficient.

Being Guardian of another Pet does not grant this capability.

---

### BR-2 — Invitation does not create Guardianship

Creating a Guardianship Invitation must not create an active Guardianship relationship for the recipient.

The relationship becomes active only through the applicable acceptance workflow.

---

### BR-3 — Invitation is Pet-specific

A Guardianship Invitation belongs to exactly one Pet.

An Invitation concerning one Pet must not grant access or Guardianship to another Pet.

---

### BR-4 — Invitation must identify the intended recipient

The Invitation must be associated with the person or recipient context for which it was created.

Another User must not be able to establish Guardianship merely because they obtained an Invitation reference.

The technical mechanism used to prove recipient control is an architectural concern.

---

### BR-5 — Existing Users and people without an account may be invited

The Guardianship Invitation model must support inviting:

* an existing User;
* a person who does not yet have a platform account.

A person without a platform account must complete the required Identity workflow before accepting the Invitation.

Sending the Invitation must not itself create a domain User.

If the intended recipient is already a User, their existing Pets,
Guardianships, and other domain relationships must remain unchanged.

---

### BR-6 — Invitation does not grant Pet access

A pending Guardianship Invitation must not grant the intended recipient access to protected Pet information.

Until acceptance succeeds, the recipient must not gain access solely because the Invitation exists.

---

### BR-7 — Invitation does not grant medical access by itself

A pending Guardianship Invitation must not grant access to the Pet's medical information.

Any medical access resulting from an established Guardianship must follow the applicable medical-access Specifications.

---

### BR-8 — Invitation does not change existing Guardianship

Creating an Invitation must not modify or remove existing Guardianship relationships.

Example:

```text
Luna
├── Maria → active Guardian
└── Carlos → pending Invitation
```

Maria's existing relationship remains unchanged.

---

### BR-9 — Multiple Guardians are supported

The Invitation workflow must support establishing more than one active Guardian for the same Pet.

The domain must not enforce a one-Guardian-only model.

---

### BR-10 — Existing active Guardianship must not be duplicated

If the intended recipient already has an active Guardianship relationship with the Pet, the system must not create another Invitation whose only purpose would be to duplicate that relationship.

Changes to an existing Guardian's permissions or relationship type require separate behavior.

---

### BR-11 — Duplicate pending Invitations should be avoided

The system must not create ambiguous duplicate pending Invitations for the same Pet and intended recipient when an equivalent valid Invitation already exists.

The exact behavior for resending or replacing Invitations is governed separately.

---

### BR-12 — Guardianship Invitation has finite validity

A Guardianship Invitation must have a finite validity period.

When the Invitation is created, an expiration time must be established according to the applicable Invitation-validity policy.

An expired Invitation must not be usable to establish Guardianship.

The exact validity duration is configurable product policy rather than a fundamental Pet-domain rule.

---

### BR-13 — Pending Invitations are revocable

A pending Guardianship Invitation must be capable of being revoked before acceptance.

Revocation requires an active Guardianship context with the capability to manage Guardianship Invitations for the Pet.

The detailed revocation workflow is outside this Specification.

---

### BR-14 — Resending communication does not create a new Invitation

The product may allow an authorized Guardian to resend the communication associated with a still-valid pending Invitation.

Resending must not by itself:

* create another Guardianship Invitation;
* extend the original Invitation validity period;
* create Guardianship;
* grant Pet access.

If the original Invitation is expired or revoked, issuing a new Invitation is a separate operation.

---

### BR-15 — Recipient authentication identifier may differ from Invitation destination

A Guardianship Invitation may be delivered to a contact address that differs from the authentication identifier used by the recipient's existing domain User.

The recipient must be able to use the existing domain User after proving control of the intended Invitation recipient context.

A second domain User must not be created solely because the Invitation was sent to a different address.

---

### BR-16 — Invitation does not establish ownership semantics by assumption

This Specification establishes an Invitation to become a Guardian.

It does not define whether the resulting relationship represents:

* primary ownership;
* co-ownership;
* authorized caregiving;
* another future Guardianship classification.

Guardianship relationship types and permission differences must be defined explicitly before implementation if the product requires them.

---

### BR-17 — Active Guardians may invite additional Guardians in Phase 1

In Phase 1, every active Guardian of a Pet may invite another person to
establish a Guardianship relationship with that Pet.

The product does not currently define different Guardian roles, permission
levels, or per-Guardian custom capabilities.

If future requirements introduce different Guardianship responsibilities,
this behavior may be refined through dedicated Specifications.

---

## 4. Scenarios

### Scenario: Invite an existing User successfully

Given Maria has an active Guardianship relationship with Luna
And Maria's Guardianship context grants the capability to invite additional Guardians
And Carlos is an existing User
And Carlos is not already a Guardian of Luna

When Maria invites Carlos to become a Guardian of Luna

Then a pending Guardianship Invitation is created
And the Invitation identifies Luna
And the Invitation identifies Carlos as the intended recipient
And Carlos does not yet have an active Guardianship relationship with Luna
And Carlos gains no Pet access solely because the Invitation exists

---

### Scenario: Invite a person who does not yet have an account

Given Maria is authorized to manage Guardianship for Luna
And the intended recipient does not yet have a platform account

When Maria sends a Guardianship Invitation to that recipient

Then a pending Guardianship Invitation is created
And no domain User is created solely because the Invitation was sent
And no Guardianship relationship is created
And the recipient may complete the required Identity workflow before accepting the Invitation

---

### Scenario: Guardian of another Pet cannot manage Luna

Given Maria is a Guardian of Toby
And Maria has no Guardianship relationship with Luna

When Maria attempts to invite Carlos to become a Guardian of Luna

Then the operation is denied
And no Guardianship Invitation for Luna is created

---

### Scenario: Guardian without invitation capability attempts invitation

Given Maria has an active Guardianship relationship with Luna
And Maria's Guardianship context does not grant the capability to invite additional Guardians

When Maria attempts to invite Carlos

Then the operation is denied
And no Guardianship Invitation is created

---

### Scenario: Pending Invitation grants no Pet access

Given Carlos has a pending Guardianship Invitation for Luna
And Carlos has not accepted it

When Carlos attempts to access protected information belonging to Luna solely through the pending Invitation

Then access is denied
And Carlos remains without active Guardianship

---

### Scenario: Existing Guardian is not invited again

Given Carlos already has an active Guardianship relationship with Luna

When Maria attempts to invite Carlos to establish the same Guardianship again

Then a duplicate active Guardianship must not be created
And an equivalent duplicate Guardianship Invitation must not be created

---

### Scenario: Invitation concerns only one Pet

Given Maria is Guardian of Luna and Toby
And Maria invites Carlos to become a Guardian of Luna

When the Invitation is created

Then the Invitation concerns Luna
And Carlos receives no Guardianship relationship or access concerning Toby

---

### Scenario: Existing Guardians remain unchanged

Given Maria has an active Guardianship relationship with Luna

When Maria validly invites Carlos to become another Guardian

Then Maria's Guardianship remains active and unchanged
And Carlos remains only an invited recipient until acceptance

---

### Scenario: Recipient authenticates using a different identifier

Given a Guardianship Invitation for Luna was delivered to Carlos's secondary email address
And Carlos already has a domain User using another authentication identifier
And Carlos proves control of the intended Invitation recipient context

When Carlos later accepts the Invitation through the applicable acceptance workflow

Then the existing Carlos domain User may receive the Guardianship relationship
And no second domain User is required

---

### Scenario: Invite an existing User who already has other Pets

Given Maria has an active Guardianship relationship with Luna
And Maria is authorized to invite additional Guardians
And Carlos is an existing User
And Carlos already has Guardianship of another Pet
And Carlos is not currently a Guardian of Luna

When Maria invites Carlos to become a Guardian of Luna

Then a pending Guardianship Invitation for Luna is created for Carlos
And Carlos's existing Guardianship relationships remain unchanged
And no new Pet is created
And Luna remains the same Pet domain entity
And Carlos gains no Guardianship of Luna until the Invitation is accepted

---

## 5. Edge Cases

### Recipient already has Guardianship

If the intended recipient already has an active Guardianship relationship with the Pet, a new Invitation must not be used to duplicate that relationship.

Changing the nature or permissions of the relationship is outside this Specification.

---

### Invitation recipient registers later

A Guardianship Invitation may exist before the recipient has a platform User.

Registration itself must not automatically accept the Invitation.

The recipient must still explicitly complete the acceptance workflow.

---

### Multiple Guardians already exist

The existence of multiple active Guardians must not prevent another Guardian from being invited unless a future product rule explicitly establishes a limit.

---

### Invitation expires

An expired Invitation remains historically distinguishable from an accepted Invitation but may no longer establish Guardianship.

The replacement workflow is outside this Specification.

---

### Guardian who created the Invitation later loses Guardianship

A valid pending Invitation must not automatically become invalid solely because the User who originally created it later ceases to be a Guardian.

Its validity continues to depend on its own state, expiration, revocation, and applicable domain rules.

An authorized current Guardian may revoke it through the applicable workflow.

---

## 6. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-011 — Professional qualification does not imply medical access.**

---

## 7. Dependencies

* SPEC-ID-001 — Register User
* SPEC-ID-002 — Verify Email Address
* SPEC-ID-003 — Authenticate User
* SPEC-PET-001 — Register Pet

---

## 8. Out of Scope

This Specification does not define:

* accepting a Guardianship Invitation;
* rejecting a Guardianship Invitation;
* detailed revocation workflow;
* exact Invitation expiration duration;
* changing an existing Guardianship relationship;
* Guardian permission levels;
* primary-Guardian semantics;
* Guardianship transfer;
* removing a Guardian;
* Pet deletion or archival;
* medical-access behavior resulting from Guardianship;
* duplicate-Pet resolution;
* arbitrary per-Guardian custom permissions.

---

## 9. Verification Notes

Verification must demonstrate that:

1. an authorized Guardian can create a Guardianship Invitation;
2. authentication alone is insufficient to invite a Guardian;
3. Guardianship of another Pet grants no authority over the target Pet;
4. an Invitation is associated with exactly one Pet;
5. creating an Invitation does not create Guardianship;
6. a pending Invitation grants no protected Pet access;
7. an existing User or a person without an account may be invited;
8. sending an Invitation does not create a domain User;
9. existing Guardianship relationships remain unchanged;
10. the model supports multiple Guardians;
11. equivalent active Guardianships are not duplicated;
12. equivalent pending Invitations are not duplicated;
13. Invitations have finite validity;
14. pending Invitations are revocable;
15. resending communication does not create another Invitation;
16. an existing domain User may accept an Invitation sent to a different contact address after proving recipient control.
17. inviting an existing User does not modify their existing Pets or Guardianships;
18. inviting an existing User to a Pet does not create a duplicate Pet.

# SPEC-PET-004 — View My Pets

**Status:** APPROVED
**Requirements:** REQ-PET-002, REQ-PET-003, REQ-PET-004, REQ-PET-005
**Domain:** Pets
**Priority:** P0

## 1. Intent

Allow an authenticated User to view the Pets for which they currently have an active Guardianship relationship.

The set commonly presented as **"My Pets"** is derived from Guardianship relationships.

It must not be derived from:

* who originally registered the Pet;
* which User created the Pet record;
* Clinic relationships;
* Veterinary Organization relationships;
* professional veterinary status.

Two different Users may therefore see the same Pet in their respective Pet collections when both have an active Guardianship relationship with that Pet.

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.
* Zero or more active Guardianship relationships may exist for the User.

A verified account may be required if the applicable Identity policy establishes that requirement for protected Pet access.

---

## 3. Business Rules

### BR-1 — My Pets is derived from active Guardianship

A Pet must appear in a User's Pet collection when the User has an active Guardianship relationship with that Pet.

The User does not need to have originally registered the Pet.

---

### BR-2 — Pet creation does not determine visibility

The User who originally registered a Pet has no special visibility rule based solely on record creation.

Pet visibility must result from the current Guardianship relationship.

---

### BR-3 — Shared Pets appear for each active Guardian

When multiple Users have active Guardianship relationships with the same Pet, that Pet may appear in each Guardian's Pet collection.

The Pet remains one domain entity.

Example:

```text
Maria ───── Guardianship ─────┐
                              │
                            Luna
                              │
Carlos ───── Guardianship ─────┘
```

Both Maria and Carlos may see Luna.

There is still only one Luna Pet.

---

### BR-4 — A User may see multiple Pets

A User may have active Guardianship relationships with multiple Pets.

Each distinct Pet must appear independently in the User's Pet collection.

Example:

```text
Carlos
├── Luna
├── Toby
└── Coco
```

---

### BR-5 — The same Pet must not appear more than once

A Pet must appear at most once in a User's Pet collection for a given current Guardianship relationship.

The presentation must not duplicate a Pet because of:

* Invitation history;
* Pet registration history;
* multiple previous operations;
* another Guardian;
* historical relationship records.

---

### BR-6 — Pending Invitations do not make a Pet part of My Pets

A pending Guardianship Invitation is not an active Guardianship relationship.

A Pet must not appear in the recipient's Pet collection solely because they have received an Invitation.

---

### BR-7 — Accepted Guardianship makes the existing Pet visible

When a valid Guardianship Invitation is successfully accepted and an active Guardianship relationship is established, the existing Pet becomes eligible to appear in the accepting User's Pet collection.

No duplicate Pet must be created.

---

### BR-8 — Guardianship of one Pet grants no visibility into another Pet

A Guardianship relationship applies only to the Pet it references.

Being Guardian of Luna must not make Toby visible unless a separate valid Guardianship relationship with Toby exists.

---

### BR-9 — Professional status does not determine My Pets

Being a Veterinarian, Organization Member, Clinic Member, Administrator, or Organization Owner must not cause Pets to appear in the personal Pet collection.

Professional access and personal Guardianship are separate concepts.

---

### BR-10 — Clinic treatment does not make a Pet personally owned or guarded

A Veterinarian treating a Pet or a Clinic holding clinical information about a Pet must not cause that Pet to appear in a professional User's personal Pet collection.

Example:

```text
Dr. Garcia treats Luna
```

does not imply:

```text
Dr. Garcia → Guardianship → Luna
```

---

### BR-11 — Pet collection exposes only information authorized by Guardianship

The Pet collection may expose Pet information that the active Guardianship relationship allows the User to view.

The collection must not expose unrelated protected information merely because the Pet is listed.

Detailed medical-record visibility is governed separately.

---

### BR-12 — Pet identity is preserved across Guardians

When several Guardians view the same Pet, all of them reference the same Pet domain identity.

Guardian-specific application state must not create independent copies of the Pet.

---

### BR-13 — Current Guardianship determines current collection membership

"My Pets" represents the User's current active Guardianship relationships.

Historical Guardianship relationships must not automatically cause a Pet to appear as currently managed.

Historical Guardianship access and presentation will be governed separately if required.

---

### BR-14 — Empty Pet collection is valid

A registered User may have no active Guardianship relationships.

In that case, their Pet collection is empty.

This is a valid state and not an error.

---

## 4. Scenarios

### Scenario: User views a Pet they registered

Given Maria registered Luna
And Maria has an active Guardianship relationship with Luna

When Maria views My Pets

Then Luna is included
And Luna appears once

---

### Scenario: User sees a shared Pet they did not register

Given Maria originally registered Luna
And Carlos later accepted a valid Guardianship Invitation for Luna
And Carlos now has an active Guardianship relationship with Luna

When Carlos views My Pets

Then Luna is included
And Carlos does not need to have originally registered Luna

---

### Scenario: Both Guardians see the same Pet

Given Maria has an active Guardianship relationship with Luna
And Carlos has an active Guardianship relationship with Luna

When Maria views My Pets
And Carlos views My Pets

Then Luna is included in Maria's Pet collection
And Luna is included in Carlos's Pet collection
And both references identify the same Luna Pet domain entity

---

### Scenario: User sees multiple Pets

Given Carlos has an active Guardianship relationship with Toby
And Carlos has an active Guardianship relationship with Luna

When Carlos views My Pets

Then Toby is included
And Luna is included
And each Pet appears once

---

### Scenario: Pending Invitation does not show the Pet

Given Carlos has a pending Guardianship Invitation for Luna
And Carlos has not accepted the Invitation
And Carlos has no other active Guardianship relationship with Luna

When Carlos views My Pets

Then Luna is not included solely because of the pending Invitation

---

### Scenario: Accepted Invitation makes the Pet visible

Given Carlos has a valid Guardianship Invitation for Luna
And Carlos successfully accepts the Invitation

When Carlos subsequently views My Pets

Then Luna is included
And Luna is the existing Pet identified by the accepted Invitation
And no duplicate Luna is created

---

### Scenario: Guardian of another Pet cannot see Luna

Given Carlos has an active Guardianship relationship with Toby
And Carlos has no active Guardianship relationship with Luna

When Carlos views My Pets

Then Toby is included
And Luna is not included

---

### Scenario: Veterinarian does not see treated Pets as personal Pets

Given Dr. Garcia is a recognized Veterinarian
And Dr. Garcia has treated Luna professionally
And Dr. Garcia has no Guardianship relationship with Luna

When Dr. Garcia views My Pets

Then Luna is not included solely because Dr. Garcia treated her

---

### Scenario: Organization Owner does not see customer Pets

Given Maria is Owner of Animalia Veterinary Group
And Animalia has provided veterinary care to Luna
And Maria has no Guardianship relationship with Luna

When Maria views My Pets

Then Luna is not included solely because Maria owns the Organization

---

### Scenario: User has no Pets

Given Maria is an authenticated User
And Maria has no active Guardianship relationships

When Maria views My Pets

Then the Pet collection is empty
And the operation succeeds

---

### Scenario: Shared Pet appears only once

Given Carlos has one active Guardianship relationship with Luna
And Luna has additional Guardianship relationships with other Users

When Carlos views My Pets

Then Luna appears exactly once in Carlos's Pet collection

---

## 5. Pet Collection Representation

The Pet collection may expose enough information to identify and present each Pet meaningfully.

It may include concepts such as:

* Pet identity;
* name;
* species;
* profile image where available;
* other approved Pet profile information.

The collection is a representation of existing Pet entities.

It must not become a separate source of Pet state.

---

## 6. Edge Cases

### Pet profile changes

If another authorized Guardian validly updates shared Pet profile information, subsequent Pet views by other Guardians should represent the current Pet information.

The Pet remains the same domain entity.

---

### Multiple Guardians modify the same Pet

Concurrent Pet-profile modification behavior is outside this Specification.

This Specification only defines which Pets belong in the User's current collection.

---

### Guardianship ends while the User is viewing the collection

If the User's Guardianship relationship ends, subsequent authorized Pet collection requests must no longer treat that Pet as currently guarded.

Immediate synchronization of already-rendered client state is an application concern.

---

### Pet is archived

Pet archival behavior has not yet been specified.

If archival is introduced, its effect on current Guardian collections must be explicitly defined rather than assumed.

---

### Historical Guardianship

A User may have previously been Guardian of a Pet without currently holding that relationship.

Historical Pet relationships must not be mixed with the current My Pets collection unless a future product capability explicitly introduces historical views.

---

## 7. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**

---

## 8. Dependencies

* SPEC-ID-003 — Authenticate User
* SPEC-PET-001 — Register Pet
* SPEC-PET-002 — Invite Guardian to Pet
* SPEC-PET-003 — Accept Guardianship Invitation

---

## 9. Out of Scope

This Specification does not define:

* Pet profile editing;
* Guardianship termination;
* historical Guardianship views;
* Pet archival;
* Pet deletion;
* Pet merging;
* Pet ordering;
* Pet search;
* pagination;
* medical-history visibility;
* Appointment visibility;
* clinical alerts;
* differentiated Guardian permissions.

---

## 10. Verification Notes

Verification must demonstrate that:

1. My Pets is derived from active Guardianship relationships;
2. the original Pet creator does not determine current Pet visibility;
3. multiple Guardians may independently see the same Pet;
4. all Guardians reference the same Pet domain entity;
5. a User may see multiple distinct Pets;
6. each Pet appears at most once in the collection;
7. pending Invitations do not make a Pet visible;
8. accepted Invitations make the existing Pet visible after Guardianship is established;
9. Guardianship of one Pet grants no visibility into another Pet;
10. professional veterinary relationships do not cause Pets to appear in My Pets;
11. Organization or Clinic relationships do not cause customer Pets to appear in My Pets;
12. an empty Pet collection is valid;
13. only current active Guardianship relationships determine current collection membership.

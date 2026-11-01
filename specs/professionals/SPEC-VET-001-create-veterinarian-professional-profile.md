# SPEC-VET-001 — Create Veterinarian Professional Profile

**Status:** APPROVED
**Requirements:** REQ-VET-001, REQ-VET-002
**Domain:** Veterinary Professionals
**Priority:** P0

## 1. Intent

Allow an authenticated User to establish a Veterinarian Professional Profile representing their veterinary professional identity within the platform.

The Professional Profile belongs to the existing User.

Creating a Veterinarian Professional Profile does not create a separate User identity and does not, by itself, establish verified veterinary qualification or grant professional capabilities.

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies the account verification requirements applicable to professional-profile creation.
* The User does not already have an existing Veterinarian Professional Profile.
* The submitted professional information satisfies the minimum profile-creation requirements.

---

## 3. Business Rules

### BR-1 — Professional Profile belongs to the existing User

A Veterinarian Professional Profile must be associated with exactly one existing User.

Creating the Profile must not create another domain User.

Conceptually:

```text
User: Maria Garcia
│
├── Guardianships
│   └── Luna
│
└── Veterinarian Professional Profile
```

Personal and professional capabilities coexist under the same User identity.

---

### BR-2 — A User has at most one Veterinarian Professional Profile

A User must not require separate Veterinarian Professional Profiles for:

* different Veterinary Organizations;
* different Clinics;
* different employment periods.

The Professional Profile represents the person's professional veterinary identity independently from where they currently practice.

---

### BR-3 — Professional Profile is Organization-independent

Creating a Veterinarian Professional Profile must not create:

* Organization Membership;
* Organization ownership;
* Organization administrative responsibility.

A Veterinarian may exist professionally in the platform without currently belonging to any Veterinary Organization.

---

### BR-4 — Professional Profile is Clinic-independent

Creating a Veterinarian Professional Profile must not:

* assign the User to a Clinic;
* create Clinic Assignment;
* imply that the Veterinarian currently practices at any particular physical location.

Clinic Assignment is a separate domain relationship.

---

### BR-5 — Profile creation does not establish verified qualification

Creating a Professional Profile represents professional information claimed or submitted by the User.

Profile creation alone must not be interpreted as platform verification that the User is legally or professionally qualified to practice veterinary medicine.

Professional verification requires a separate workflow.

---

### BR-6 — Unverified professional identity grants no verified-professional capabilities

A newly created but unverified Veterinarian Professional Profile must not, solely because it exists, grant capabilities that require verified veterinary professional status.

Such capabilities may include, where later Specifications require verification:

* acting as the responsible Veterinarian for clinical care;
* creating finalized clinical information;
* accessing protected medical information through professional authority;
* being publicly presented as a verified Veterinarian.

The exact capabilities requiring verification are defined by the Specifications governing those behaviors.

---

### BR-7 — Professional status does not imply medical access

Creating a Veterinarian Professional Profile must not grant access to arbitrary Pets or Medical Records.

Professional identity and authorization to access a specific Pet's medical information are separate domain concepts.

---

### BR-8 — Professional status does not modify Guardianship

Creating a Veterinarian Professional Profile must not:

* create Pet Guardianship;
* remove Pet Guardianship;
* change existing Guardianship relationships.

A User may simultaneously be a Veterinarian and Guardian.

---

### BR-9 — Existing personal domain relationships remain unchanged

If the User already has:

* Pets;
* Guardianships;
* Appointments;
* Organization relationships;

those relationships must remain unchanged when the Professional Profile is created.

---

### BR-10 — Minimum professional identity information is required

The Professional Profile must contain enough information to represent a meaningful claimed veterinary professional identity.

Phase 1 requires:

* a professional registration or license identifier;
* the jurisdiction, issuing authority, or equivalent context in which that identifier is meaningful.

The system must not assume that a registration identifier is globally unique without its professional jurisdiction or issuing context.

---

### BR-11 — Professional registration identifier is not User identity

A professional registration or license identifier must not replace the User's domain identity.

Changes in professional-registration information must not create another User.

---

### BR-12 — Claimed professional information must not be presented as verified information

Until the applicable verification workflow succeeds, professional information that requires verification must remain distinguishable from verified professional information.

The system must not present an unverified professional claim in a way that implies platform verification.

---

### BR-13 — Profile creation does not create public professional visibility

Creating a Professional Profile must not automatically make the Veterinarian publicly visible on:

* Clinic profiles;
* search results;
* maps;
* Organization pages.

Professional public visibility requires separate explicit behavior.

---

### BR-14 — Profile creation does not create Appointment authority

Creating a Veterinarian Professional Profile must not automatically authorize the User to:

* view Clinic Appointments;
* confirm Appointments;
* cancel Appointments;
* accept Appointment reschedule proposals;
* assign themselves to Appointments.

Appointment authority requires the applicable Organization and Clinic professional context.

---

### BR-15 — Profile creation does not create clinical activity

Creating a Professional Profile must not create:

* a Medical Record Entry;
* a clinical event;
* an Appointment;
* a Treatment;
* a diagnosis.

---

### BR-16 — Duplicate Professional Profiles must not be created

If the User already has a Veterinarian Professional Profile, attempting to create another one must not result in a second professional identity.

Editing or supplementing an existing Profile is a separate workflow.

---

## 4. Initial Professional Profile Information

Phase 1 Professional Profile creation must support enough information to represent the professional identity and enable later verification.

### Required

* professional registration or license identifier;
* issuing jurisdiction, authority, or equivalent professional context.

### Optional

The domain may support information such as:

* professional biography;
* specialties;
* additional professional registrations;
* professional profile image;
* public professional name where needed;
* other relevant professional information.

Optional information must not be required solely because it may become useful in future product capabilities.

Professional verification state is system-managed information and must not be arbitrarily selected by the User.

---

## 5. Scenarios

### Scenario: User creates a Veterinarian Professional Profile

Given Maria is an authenticated User
And Maria satisfies the required account verification state
And Maria does not already have a Veterinarian Professional Profile
And Maria provides valid minimum professional identity information

When Maria creates her Veterinarian Professional Profile

Then the Professional Profile is created
And the Profile belongs to Maria's existing User
And no additional domain User is created
And the Profile is not considered professionally verified solely because it exists

---

### Scenario: Existing Pet Guardian becomes a professional-profile holder

Given Maria has an active Guardianship relationship with Luna
And Maria does not yet have a Veterinarian Professional Profile

When Maria validly creates her Veterinarian Professional Profile

Then Maria remains Guardian of Luna
And Luna remains the same Pet domain entity
And the Professional Profile is associated with Maria's existing User
And no separate professional User account is created

---

### Scenario: Professional Profile does not create Organization Membership

Given Maria has no Organization Membership

When Maria successfully creates a Veterinarian Professional Profile

Then Maria still has no Organization Membership solely because the Profile exists
And Maria is not automatically associated with any Veterinary Organization

---

### Scenario: Professional Profile does not create Clinic Assignment

Given Maria successfully creates a Veterinarian Professional Profile

When Profile creation completes

Then Maria is not automatically assigned to any Clinic
And Maria receives no Clinic-specific professional authority

---

### Scenario: Professional Profile does not grant medical access

Given Maria successfully creates a Veterinarian Professional Profile
And Maria has no authorized medical-access context for Luna

When Maria attempts to access Luna's protected Medical Record solely because the Professional Profile exists

Then access is denied

---

### Scenario: Unverified Profile does not grant verified-professional capabilities

Given Maria has created a Veterinarian Professional Profile
And the Profile has not completed the applicable professional-verification workflow

When Maria attempts an operation that explicitly requires verified veterinary status

Then the operation is denied
And existence of the Professional Profile alone is insufficient

---

### Scenario: Existing Organization Membership remains independent

Given Maria already has an active Membership in Animalia Veterinary Group
And Maria does not yet have a Veterinarian Professional Profile

When Maria creates her Professional Profile

Then Maria's Organization Membership remains unchanged
And the Professional Profile does not automatically change her Organization responsibilities
And no Clinic Assignment is created

---

### Scenario: Duplicate Professional Profile creation is rejected

Given Maria already has a Veterinarian Professional Profile

When Maria attempts to create another Veterinarian Professional Profile

Then a second Profile is not created
And the existing Professional Profile remains the one associated with Maria

---

### Scenario: Professional registration identifier without issuing context is insufficient

Given Maria is allowed to create a Veterinarian Professional Profile

When Maria provides a professional registration identifier without the required jurisdiction or issuing context

Then Profile creation is rejected
And no incomplete Veterinarian Professional Profile is created

---

### Scenario: Same registration-number text may exist in different jurisdictions

Given one Veterinarian has professional registration identifier "12345" in Jurisdiction A
And Maria has professional registration identifier "12345" in Jurisdiction B

When Maria creates her Professional Profile with the appropriate Jurisdiction B context

Then the identifier text alone is not assumed to represent the same professional registration
And User identity is not determined solely by registration-number equality

---

### Scenario: Profile creation does not make Veterinarian public

Given Maria successfully creates a Veterinarian Professional Profile

When an Anonymous Visitor explores published Clinics

Then Maria does not become publicly visible solely because the Professional Profile exists

---

### Scenario: Profile creation does not grant Appointment-management capabilities

Given Maria successfully creates a Veterinarian Professional Profile
And Maria has no applicable Veterinarian Clinic Assignment or applicable Appointment-management authority

When Maria attempts to confirm a Clinic Appointment solely because she has a Professional Profile

Then the operation is denied

---

## 6. Professional Verification State

A Veterinarian Professional Profile must support a distinction between:

```text
professional identity submitted
```

and:

```text
professional identity verified
```

This Specification defines creation of the professional identity only.

The exact verification lifecycle, actors, evidence, and state transitions are defined separately.

The User must not be able to arbitrarily mark their own Professional Profile as verified.

---

## 7. Professional Identity Across Employment Changes

The Professional Profile represents the person rather than an employment relationship.

For example:

```text
2026
Dr. Garcia
Professional Profile
      │
      └── Animalia Veterinary Group

2028
Animalia Membership ends

2029
      └── VetCare Group
```

Dr. Garcia continues to have the same Veterinarian Professional Profile.

Leaving one Organization and joining another must not create a new professional identity.

---

## 8. Edge Cases

### Veterinarian is not currently employed

A User may maintain a Veterinarian Professional Profile without an active Organization Membership or Clinic Assignment.

Absence of current employment does not erase professional identity.

---

### Multiple professional registrations

A Veterinarian may hold more than one professional registration or license where real-world professional rules permit it.

Phase 1 does not need to model multiple registrations unless required by the professional-verification workflow.

The core Professional Profile must not be designed in a way that conceptually assumes only one registration can ever exist throughout the User's lifetime.

---

### Professional registration changes

A professional registration may change, expire, be replaced, or require updated verification.

Editing or lifecycle management of registration information is outside this Specification.

---

### Incorrect professional claim

A User may submit inaccurate professional information.

Profile creation must not be treated as verification.

The verification workflow must determine whether the claimed professional identity can be trusted for capabilities that require it.

---

### Duplicate professional identity across Users

Two different Users may attempt to claim the same professional registration within the same jurisdiction.

The system must eventually prevent a verified professional registration from representing multiple independent professional identities without explicit resolution.

The exact conflict and verification workflow is outside this Specification.

---

## 9. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-004 — Veterinarian identity is Organization-independent.**
* **INV-011 — Professional qualification does not imply medical access.**

---

## 10. Dependencies

* SPEC-ID-001 — Register User
* SPEC-ID-002 — Verify Email Address
* SPEC-ID-003 — Authenticate User

---

## 11. Out of Scope

This Specification does not define:

* professional credential verification;
* verification evidence;
* professional-registration expiration;
* Professional Profile editing;
* multiple professional-registration management;
* Organization Membership;
* Clinic Assignment;
* public Veterinarian profiles;
* specialties management;
* veterinary Appointment assignment;
* professional availability;
* Medical Record creation;
* medical-record access;
* professional suspension or revocation;
* legal disciplinary status.

---

## 12. Verification Notes

Verification must demonstrate that:

1. an eligible existing User can create a Veterinarian Professional Profile;
2. Profile creation uses the existing User rather than creating a professional User account;
3. one User does not receive duplicate Veterinarian Professional Profiles;
4. Professional Profile creation does not create Organization Membership;
5. Professional Profile creation does not create Clinic Assignment;
6. Profile creation does not modify existing Guardianships or personal relationships;
7. an unverified Professional Profile does not grant capabilities that require verified veterinary status;
8. Professional Profile existence does not grant medical access;
9. Professional Profile existence does not grant Clinic Appointment-management capabilities;
10. professional registration identifier and issuing context are required for Phase 1 Profile creation;
11. professional-registration identifier alone is not treated as globally unique identity;
12. Profile creation does not automatically create public professional visibility;
13. professional identity survives changes in Organization employment.

---

## 13. Phase 1 self-service Profile contract

Defined by **Staff Responsibility Editing + Veterinarian Enablement — Phase 1**.
It narrows BR-1–BR-16 for the mobile client; it does not change them.

### BR-17 — Canonical Phase 1 operation

The client creates the acting User's own Profile only through

    create_my_veterinarian_professional_profile(
        p_registration_identifier text,
        p_issuing_context text
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It takes no User, Membership, Organization, or Clinic input:
the Profile always belongs to the authenticated User. No actor can create,
edit, or replace another User's Profile.

The pre-existing `create_veterinarian_professional_profile(text, text)` reports
a duplicate as a raw database error. It is not a client path: client `EXECUTE`
is withdrawn and it remains for trusted compatibility only. Both share one
writer.

### BR-18 — Inputs

Exactly the Phase 1 credential facts of §4:

- registration or license identifier;
- issuing jurisdiction, authority, or equivalent context.

Both are trimmed of surrounding whitespace and must be non-blank. No other
Profile information is collected in Phase 1.

### BR-19 — Ordering

1. authentication and a coherent domain User — otherwise `28000`;
2. a confirmed account email — otherwise `42501`, hint
   `ACCOUNT_VERIFICATION_REQUIRED`;
3. input — blank identifier `22023`, hint `REGISTRATION_IDENTIFIER_REQUIRED`;
   blank context `22023`, hint `ISSUING_CONTEXT_REQUIRED`;
4. the User's existing Profile (BR-20);
5. creation of the Profile and its one Credential together.

Concurrent attempts by the same User serialize on that User.

### BR-20 — Outcomes and replay

| Situation | Result |
| --- | --- |
| No Profile exists | `CREATED` with `professional_profile_id`, `professional_credential_id` |
| A Profile exists whose Credential has exactly the requested normalized identifier and context | `ALREADY_EXISTS` with the same ids; nothing is written |
| A Profile exists with a materially different identifier or context | rejected, `23514`, hint `PROFILE_CREDENTIAL_MISMATCH`; nothing is written or overwritten |

An exact repeat, including a retry after a lost response, therefore reconciles
to the same Profile (BR-2, BR-16) without a client idempotency key. A
different request never silently succeeds and never edits the existing Profile
(editing remains out of scope, §11).

### BR-21 — No other effect

Creation establishes no Organization Membership, Responsibility Grant, Clinic
Assignment, verification state, public visibility, Appointment authority, or
medical access (BR-3–BR-15). Claimed credential facts are never presented as
platform-verified (BR-12).

### Mobile presentation

- Professional Home shows **Complete veterinarian profile / Completar perfil
  veterinario** only when the advisory professional context
  (`SPEC-ORG-007`) shows a current `VETERINARIAN` Responsibility in at least
  one current Organization and `has_veterinarian_professional_profile` is
  `false`. Users without that Responsibility are not prompted.
- The entry opens a dedicated, Organization-independent route
  (`/professional/veterinarian-profile`) with the two fields.
- Before submitting, a review step shows both values and states neutrally that
  the Profile cannot yet be edited after it is created. It never claims that
  MenizVet verified the credential.
- After `CREATED` or `ALREADY_EXISTS`, and after an apparent lost response, the
  client re-reads the professional context; once a Profile exists the prompt
  disappears and creation is not offered again.
- `PROFILE_CREDENTIAL_MISMATCH` is explained calmly as a Profile that already
  exists with different details.
- No credential value is shown anywhere else, including to administrators
  (`SPEC-VET-006`).

## 14. Phase 1 self-service Profile Verification Notes

In addition to §12, verification must demonstrate that:

14. an eligible authenticated User creates exactly one Profile and Credential
    with outcome `CREATED`;
15. an unauthenticated caller, an incoherent subject, and an unverified account
    are rejected with nothing written;
16. blank or whitespace-only inputs are rejected with nothing written;
17. an exact repeat returns `ALREADY_EXISTS` with the same ids, including when
    the values differ only by surrounding whitespace;
18. a different identifier or context is rejected with
    `PROFILE_CREDENTIAL_MISMATCH` and the stored Credential is unchanged;
19. the operation accepts no User parameter, and two Users each get their own
    Profile;
20. creation writes no Membership, Grant, or Assignment;
21. two concurrent creations by the same User produce one Profile, one
    `CREATED` and one `ALREADY_EXISTS`;
22. no client role executes the generic creation operation.

# SPEC-CLI-004 — Manage Clinic Public Profile

**Status:** APPROVED
**Requirements:** REQ-CLI-003, REQ-CLI-005, REQ-DIS-004, REQ-ORG-005, REQ-ORG-006
**Domain:** Clinics
**Priority:** P1

## 1. Intent

Allow an authorized Organization Member to manage the information that a Clinic intentionally exposes through its public profile.

The public profile represents the Clinic to Anonymous Visitors and registered Users.

Only information explicitly designated as public may be exposed through this profile.

Managing public-profile information must remain separate from:

* Clinic identity;
* Organization-private information;
* physical-location management;
* opening-hours management;
* services;
* professional assignments;
* medical or customer information.

---

## 2. Preconditions

* The Clinic exists.
* The Clinic belongs to a Veterinary Organization.
* The acting User exists.
* The acting User is authenticated.
* The acting User has an active Organization Membership in the Clinic's Organization.
* The acting User's assigned responsibilities grant the capability to manage Clinic public information.
* Submitted public-profile information satisfies the applicable validation rules.

---

## 3. Business Rules

### BR-1 — Public profile belongs to the Clinic

Public Clinic information describes a specific Clinic.

It must not be treated as the public profile of the Veterinary Organization itself.

An Organization operating multiple Clinics may therefore expose different public information for each Clinic.

---

### BR-2 — Public display name is required for publication

A Clinic intended for publication must have a valid public display name.

A public display name is human-facing information and must not be used as the Clinic's technical identity.

---

### BR-3 — Public display names are not globally unique

Multiple Clinics may use identical or similar public display names.

The system must not rely on display-name uniqueness to distinguish Clinics.

---

### BR-4 — Public-profile information may be edited

An authorized User may update public-profile information.

Editing public information must not create a new Clinic or change the Clinic's domain identity.

---

### BR-5 — Published Clinics must retain mandatory public information according to SPEC-CLI-003.

If the Clinic is currently published, an update must not remove or invalidate public information required for publication.

An operation that would make the Clinic fail its publication requirements must be rejected while the Clinic remains published.

The Clinic may first be unpublished and then modified under the rules applicable to unpublished Clinics.

---

### BR-6 — Optional public information may be omitted

Information that is not explicitly required for publication may remain absent.

The product must not require optional information solely because it could be useful in future workflows.

---

### BR-7 — Only explicitly public information may be exposed

The Clinic public profile must only expose information intentionally classified as public.

Private information must not become public merely because similar information exists elsewhere in the Organization or User domain.

---

### BR-8 — Private Organization information must not leak into the Clinic profile

The public profile must not implicitly expose private Organization information such as:

* billing information;
* subscription details;
* internal administrative contacts;
* Organization Memberships;
* internal responsibilities;
* operational notes.

Public Organization-related information may only appear where explicitly approved for public use.

---

### BR-9 — Professional information is not automatically public

Clinic public-profile management must not automatically expose:

* assigned Veterinarians;
* Organization Members;
* professional contact details;
* staff schedules.

Public professional visibility must be defined separately.

---

### BR-10 — Public contact information is distinct from account identity

A Clinic may expose public contact information that differs from:

* a User's authentication email;
* an Organization Member's personal contact information;
* internal administrative contacts.

A public Clinic email address or phone number must not determine User identity or Organization Membership.

---

### BR-11 — Public profile management does not modify physical location

Managing the public profile must not implicitly alter the Clinic's physical geographic location.

Physical location is governed by `SPEC-CLI-002`.

A human-facing address presentation may eventually be derived from or associated with Clinic location, but its source of truth must be defined architecturally rather than duplicated inconsistently.

---

### BR-12 — Public profile management does not publish the Clinic

Completing the public profile does not automatically publish the Clinic.

Publication remains an explicit operation governed by `SPEC-CLI-003`.

---

### BR-13 — Public profile management does not alter authorization

Changing public-profile information must not grant or revoke:

* Organization Membership;
* Clinic Assignment;
* Pet access;
* medical access;
* professional qualification;
* administrative capabilities.

---

### BR-14 — Public content must satisfy applicable validation constraints

Public-profile content must satisfy product-defined validation rules before being accepted.

Validation may include properties such as:

* required values;
* supported format;
* permitted length;
* valid contact-data structure where applicable.

Exact implementation-level validation limits should be defined when needed and must not be invented by the client independently.

---

### BR-15 — One save replaces the whole public profile

Phase 1 public-profile management uses replacement semantics.

One save submits all five profile values — display name, description, public
phone, public email, and website — and replaces all five stored values
together. A value omitted from the editor's intent must therefore be
re-submitted unchanged; the operation does not patch individual fields.

---

### BR-16 — Input normalization and absent values

Each submitted value is normalized by removing leading and trailing
whitespace, using the backend's existing whitespace set (space, tab, line feed,
carriage return, form feed, vertical tab).

A value that is blank after normalization means **absent** and is stored as
absent (`NULL`). Any optional value may therefore be cleared by submitting it
blank.

If every value is absent after normalization and the Clinic is unpublished,
the Clinic's stored public profile may be removed entirely. Removal does not
affect Clinic identity, location, publication state, or any other
configuration.

---

### BR-17 — Published Clinic keeps its display name

Consistent with BR-5 and `SPEC-CLI-003` BR-14, a save that would leave a
published Clinic without a display name is rejected, and nothing changes.
Optional values may still be cleared while published.

A client may prevent submitting a blank display name for a published Clinic,
but the backend rule remains authoritative.

---

### BR-18 — Phase 1 validation is limited to normalization and non-blank storage

No approved repository-wide format or length limits exist for public-profile
values. Phase 1 therefore preserves exactly the existing validation:

- normalization as defined in BR-16;
- stored values are never blank;
- the display-name publication rule of BR-17.

Phase 1 does not validate email format, phone format, URL format or scheme, or
length. Clients must not introduce their own format checks or length limits,
because such rules would not be enforced by the backend (BR-14).

Validation hardening — for example length limits for anonymous public
content, email or phone structure, or website scheme — is separate future work
that requires an amendment to this Specification and a backend change.

---

### BR-19 — Phase 1 saves are last-write-wins

Profile saves are last-write-wins in Phase 1. No revision token or
stale-edit detection is introduced.

A save prepared from an older read may overwrite a value another actor changed
in the meantime, including a field the saving actor did not edit. This is an
accepted Phase 1 risk, given how rarely the profile changes and how few actors
manage it. It is recorded deliberately rather than as an omission.

Clients must re-read after every save and present the authoritative profile.
A lost response is reconciled by re-reading: if the stored values equal the
submitted values after BR-16 normalization, the save succeeded.

---

### BR-20 — Authorization precedes resource disclosure

The save requires `CLINIC_MANAGE_PUBLIC_PROFILE` for the target Clinic.

Validation and disclosure ordering:

1. an unauthenticated caller is rejected as unauthenticated;
2. a nonexistent Clinic and a Clinic the caller may not manage are rejected
   with the same insufficient-capability outcome (`42501`), revealing neither
   existence nor publication state;
3. only for an authorized caller are profile rules evaluated, including the
   published display-name rule of BR-17.

The original implementation reported a nonexistent Clinic with a distinct
existence error before evaluating capability. Clinic self-service Slice B
closed this gap (`20261024090000_clinic_profile_location_fail_closed_writes.sql`;
see `docs/IMPLEMENTATION_STATUS.md`).

---

### BR-21 — Professional profile editor

The Phase 1 professional surface offers one profile and contact editor for the
Clinic, reached from Clinic settings (`SPEC-CLI-007` BR-12), containing the
display name, description, public phone, public email, and website.

- The editor indicates that the display name is required for publication.
- Optional values may be cleared.
- Save is disabled while nothing has changed or a save is in flight.
- Failures are presented as calm product copy; raw backend text is never
  shown.

Public imagery and branding remain outside Phase 1.

---

## 4. Initial Public Profile Information

The initial product model must support the following public-profile concepts.

### Required for publication

* **Public display name**

### Optional

The profile may support information such as:

* short description;
* public phone number;
* public email address;
* website;
* public imagery or branding.

Optional fields are not mandatory for publication unless a later approved Specification changes that requirement.

The following concepts are governed separately and should not be embedded into this Specification merely because they appear publicly:

* physical location;
* opening hours;
* services;
* Veterinarian profiles;
* Appointment availability.

---

## 5. Scenarios

### Scenario: Set the public display name

Given Animalia Madrid Centro exists
And Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities grant the capability to manage Clinic public information

When Maria sets the Clinic public display name to "Animalia Madrid Centro"

Then the public display name is stored for that Clinic
And the Clinic remains the same domain entity
And no other Clinic is modified

---

### Scenario: Update public profile information

Given Animalia Madrid Centro has existing public-profile information
And Maria is authorized to manage the Clinic public profile

When Maria replaces the Clinic description with another valid description

Then the new description becomes part of the Clinic's public-profile information
And the Clinic remains the same domain entity

---

### Scenario: Published Clinic display name may be changed

Given Animalia Madrid Centro is published
And its public profile satisfies all publication requirements
And Maria is authorized to manage its public information

When Maria replaces the public display name with another valid display name

Then the update succeeds
And the Clinic remains published
And the Clinic domain identity remains unchanged

---

### Scenario: Required public display name cannot be removed while published

Given Animalia Madrid Centro is published
And its public display name is required for publication

When Maria attempts to remove the public display name

Then the operation is denied
And the existing public display name remains unchanged
And the Clinic remains published

---

### Scenario: Required public display name may be absent while unpublished

Given Animalia Madrid Centro exists
And the Clinic is not published

When its public display name has not yet been configured

Then the Clinic continues to exist
And it remains unavailable for publication until the required profile information is provided

---

### Scenario: Optional profile information may be removed

Given Animalia Madrid Centro has an optional public description
And Maria is authorized to manage its public profile

When Maria removes the optional description

Then the description is removed
And the Clinic remains valid
And publication remains valid if all mandatory publication requirements are still satisfied

---

### Scenario: Unauthorized Member attempts profile modification

Given Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities do not grant the capability to manage Clinic public information

When Maria attempts to change Animalia Madrid Centro's public profile

Then the operation is denied
And the Clinic public profile remains unchanged

---

### Scenario: Member of another Organization attempts profile modification

Given Maria has an active Membership in VetCare Group
And Maria has no authorized Membership context in Animalia Veterinary Group

When Maria attempts to modify Animalia Madrid Centro's public profile

Then the operation is denied
And Animalia Madrid Centro remains unchanged

---

### Scenario: Public Clinic profile does not expose private Organization information

Given Animalia Madrid Centro is published
And Animalia Veterinary Group contains private administrative and billing information

When an Anonymous Visitor views Animalia Madrid Centro

Then approved public Clinic information is available
And private Organization information is not exposed

---

### Scenario: Public Clinic profile does not expose staff automatically

Given Animalia Madrid Centro is published
And several Organization Members are assigned to the Clinic

When an Anonymous Visitor views the public Clinic profile

Then the assigned Members are not exposed solely because they are associated with the Clinic

---

### Scenario: Two Clinics use the same display name

Given Animalia Veterinary Group operates a Clinic with the public display name "Centro Veterinario Animal"
And VetCare Group operates another Clinic

When VetCare sets its Clinic public display name to "Centro Veterinario Animal"

Then the public display name may be accepted
And both Clinics remain distinct domain entities

---

## 6. Edge Cases

### Public contact information changes

A Clinic may replace a public contact method without changing Clinic identity.

Changes to public contact information must not modify authentication identities or Organization Memberships.

---

### No public contact information

A Clinic may initially be published without a public phone number, email address, or website if those fields remain optional under the applicable publication requirements.

---

### Rich public content

Future product evolution may introduce:

* image galleries;
* accreditation badges;
* languages spoken;
* accessibility information;
* specialties;
* emergency-service indicators.

Such capabilities should receive dedicated requirements or specifications when their behavior becomes relevant.

---

### Organization branding

An Organization may eventually provide shared branding or default information to multiple Clinics.

Inheritance and override rules are not defined by this Specification and must not be assumed.

---

## 7. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-014 — Anonymous public discovery is allowed.**

---

## 8. Dependencies

* SPEC-CLI-001 — Create Clinic
* SPEC-CLI-002 — Set Clinic Location
* SPEC-CLI-003 — Publish Clinic
* SPEC-CLI-007 — View Managed Clinic Configuration
* SPEC-ID-003 — Authenticate User
* SPEC-ORG-003 — Accept Organization Invitation

Authorization follows the responsibility-derived capability model established by the Organization Specifications.

---

## 9. Out of Scope

This Specification does not define:

* physical Clinic location;
* opening hours;
* services;
* Clinic publication workflow;
* public Veterinarian visibility;
* Organization branding inheritance;
* Appointment availability;
* geographic discovery;
* map rendering;
* reviews or ratings;
* image-upload implementation;
* contact-form behavior;
* social-media profiles;
* arbitrary custom public fields.

---

## 10. Verification Notes

Verification must demonstrate that:

1. an authorized User can manage Clinic public-profile information;
2. unauthorized Users cannot modify the profile;
3. a public display name is required for publication;
4. the public display name is not treated as Clinic identity;
5. duplicate display names across Clinics are allowed;
6. mandatory public-profile information cannot be removed while the Clinic remains published;
7. optional information may be omitted or removed;
8. profile management does not automatically publish the Clinic;
9. public-profile changes do not modify physical location;
10. public-profile changes do not modify authentication or authorization relationships;
11. private Organization information is not exposed through the Clinic public profile;
12. staff information is not automatically made public;
13. one save replaces all five values together (BR-15);
14. values are normalized with the backend whitespace set, and a blank value
    is stored as absent (BR-16);
15. optional values can be cleared, both while unpublished and while
    published (BR-16, BR-17);
16. submitting all values absent for an unpublished Clinic removes the stored
    profile and changes nothing else (BR-16);
17. a save without a display name for a published Clinic is rejected with no
    change (BR-17);
18. no email, phone, URL, or length validation is applied beyond BR-18;
19. a later save overwrites an earlier one without stale detection, and the
    re-read shows the last committed values (BR-19);
20. a lost response is reconciled by re-reading and comparing normalized
    values (BR-19);
21. Owner, Organization Administrator, and Clinic Administrator (own Clinic)
    may save; Receptionist, Veterinarian, another Clinic's Administrator,
    another Organization's members, ended Memberships or Grants, and
    anonymous callers are denied with no change;
22. a nonexistent Clinic and an inaccessible Clinic produce the same `42501`
    outcome, and profile rules are evaluated only for an authorized caller
    (BR-20).

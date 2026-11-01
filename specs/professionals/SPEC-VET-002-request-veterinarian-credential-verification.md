# SPEC-VET-002 — Request Veterinarian Credential Verification

**Status:** APPROVED  
**Requirements:** REQ-VET-006  
**Domain:** Veterinary Professionals  
**Priority:** P2
**Delivery:** Later

## 1. Intent

Allow a User with a Veterinarian Professional Profile to request verification
of their claimed veterinary credentials.

Requesting verification submits the Professional Profile and the required
professional evidence to the platform's verification process.

Submitting a verification request does not itself make the Veterinarian
verified.

---

## Delivery Boundary

This Specification refines `REQ-VET-006 — Professional verification`.

`REQ-VET-006` is delivered `Later`.

Therefore, the professional credential-verification workflow defined by this
Specification is not part of Phase 1.

The Specification remains `APPROVED` because the intended future domain
behavior has been established. Approval does not imply Phase 1 delivery.

Phase 1 must not implement behavior exclusive to this verification workflow,
including, where applicable:

- Credential Verification Requests;
- submission or persistence of protected verification evidence for this
  workflow;
- verification review or resolution workflows;
- verified or rejected verification outcomes produced by this workflow;
- verification-resolution history;
- administrative verification queues or reviewer capabilities.

Phase 1 may preserve professional credential information required by
`SPEC-VET-001`.

The existence of professional credential information must not be interpreted as
platform verification.

Organization Membership, Clinic Assignment, or Appointment Veterinarian
Assignment must not be interpreted as proof of platform credential
verification.

---

## 2. Preconditions

- The acting User exists.
- The acting User is authenticated.
- The acting User owns the Veterinarian Professional Profile being submitted.
- The Professional Profile contains the professional registration information
  required for verification.
- The Professional Profile is not currently verified.
- Any evidence required by the applicable verification policy is available.

---

## 3. Business Rules

### BR-1 — Only the Professional Profile owner may request verification

A User may request verification only for their own Veterinarian Professional
Profile.

Organization ownership, Organization Membership, or Clinic authority must not
allow another User to submit professional verification on behalf of the
Veterinarian unless a future explicit workflow permits it.

---

### BR-2 — Verification request uses the existing Professional Profile

Requesting verification must not create:

- another User;
- another Veterinarian Professional Profile;
- another professional identity.

The verification process applies to the existing Professional Profile.

---

### BR-3 — Submission does not imply verification

Successfully submitting a verification request means only that the claimed
professional identity is awaiting or undergoing verification.

Submission must not grant capabilities that require verified veterinary
status.

---

### BR-4 — Verification is independent from Organization Membership

A User may request professional verification regardless of whether they
currently belong to a Veterinary Organization.

The platform must not require current employment merely to establish verified
professional identity.

---

### BR-5 — Verification is independent from Clinic Assignment

A User does not need to be assigned to a Clinic to request verification.

Likewise, requesting verification must not create a Clinic Assignment.

---

### BR-6 — Organization invitation does not constitute verification

Being invited to or accepted into a Veterinary Organization must not be
treated as evidence that the platform has verified the User's veterinary
credentials.

Employment relationships and professional verification are separate domain
concepts.

---

### BR-7 — Organization Owners cannot self-certify professional verification

An Organization Owner, Administrator, or other Organization Member must not
be able to make another User professionally verified merely through their
Organization authority.

The final verification outcome belongs to the authorized platform
verification process.

---

### BR-8 — Verification request must identify the credential being verified

A verification request must clearly identify the professional registration
or credential to which it applies.

At minimum, this includes:

- professional registration or license identifier;
- issuing jurisdiction, authority, or equivalent context.

---

### BR-9 — Evidence may be required

The verification process may require supporting evidence sufficient to
evaluate the claimed professional credential.

Examples may include:

- professional registration documentation;
- evidence obtained from an authoritative professional source;
- other approved verification evidence.

The exact evidence requirements are verification-policy concerns and must not
be invented independently by the client application.

---

### BR-10 — Verification evidence is protected information

Evidence submitted for professional verification must not automatically
become public Professional Profile information.

Verification evidence must only be accessible to actors or processes
authorized to perform the verification workflow.

---

### BR-11 — Verification status is system-managed

A User must not be able to directly set their own professional verification
status.

The User may request verification, but the result must be established through
the authorized verification workflow.

---

### BR-12 — Only one active verification process is required per credential

The system must avoid multiple equivalent unresolved verification requests for
the same Professional Profile and professional credential.

Submitting the same credential repeatedly must not create ambiguous concurrent
verification processes.

---

### BR-13 — Previously rejected verification may be submitted again when appropriate

A previous unsuccessful verification attempt must not necessarily permanently
prevent future verification.

A new request may be permitted when:

- corrected professional information is provided;
- new evidence is supplied;
- previous deficiencies have been addressed.

The previous verification history must remain traceable.

---

### BR-14 — Verification history must be preserved

The system must be capable of establishing meaningful professional
verification history.

This may include:

- when verification was requested;
- which professional credential was submitted;
- the outcome of previous verification attempts;
- when an outcome was established.

Sensitive evidence does not need to become generally visible in order for
verification history to remain auditable.

---

### BR-15 — Verification request does not grant medical access

Submitting professional credentials for verification must not grant access to:

- Pets;
- Medical Records;
- Clinic Appointments;
- protected clinical information.

---

### BR-16 — Verification request does not grant clinical authority

Submitting a verification request must not allow the User to act as a verified
Veterinarian while the verification process remains unresolved.

Whether a particular professional operation requires verified status is
defined by the Specification governing that operation.

---

## 4. Verification Request State

A successfully submitted verification request enters an unresolved state
conceptually equivalent to:

`PENDING`

This means that the credentials have been submitted for verification but no
successful verification outcome has yet been established.

The exact persistence representation is not defined by this Specification.

---

## 5. Scenarios

### Scenario: Veterinarian submits credentials for verification

Given Maria has a Veterinarian Professional Profile
And Maria is authenticated
And her Professional Profile contains the required professional registration information
And Maria provides the required verification evidence

When Maria requests professional verification

Then a verification request is created for Maria's existing Professional Profile
And the request is associated with the submitted professional credential
And the verification request is `PENDING`
And Maria is not considered verified solely because the request was submitted

---

### Scenario: Veterinarian without Organization Membership requests verification

Given Maria has a Veterinarian Professional Profile
And Maria does not currently belong to any Veterinary Organization
And Maria satisfies the verification-request requirements

When Maria requests professional verification

Then the request may be created
And absence of Organization Membership does not prevent verification submission

---

### Scenario: Organization Owner cannot verify another Veterinarian

Given Carlos owns Animalia Veterinary Group
And Maria has a Veterinarian Professional Profile
And Maria's professional credential has not been verified

When Carlos attempts to mark Maria as professionally verified solely through
his Organization authority

Then the operation is denied
And Maria remains unverified

---

### Scenario: Organization invitation does not verify Veterinarian

Given Maria has an unverified Veterinarian Professional Profile
And Maria accepts an Organization Invitation to Animalia Veterinary Group

When the Organization Membership becomes active

Then Maria's Professional Profile remains unverified
And Organization Membership does not constitute credential verification

---

### Scenario: Submission does not grant verified-professional capability

Given Maria has submitted a verification request
And the verification request remains `PENDING`

When Maria attempts an operation that explicitly requires verified veterinary status

Then the operation is denied
And the pending request is insufficient

---

### Scenario: Another User cannot submit verification for Maria

Given Maria owns a Veterinarian Professional Profile
And Carlos is authenticated
And Carlos does not own Maria's Professional Profile

When Carlos attempts to submit Maria's credentials for verification

Then the operation is denied
And no verification request is created through Carlos's identity

---

### Scenario: Duplicate unresolved verification request is not created

Given Maria already has a pending verification request for her professional credential

When Maria attempts to submit an equivalent verification request again

Then another equivalent pending verification request is not created
And the existing verification process remains authoritative

---

### Scenario: Previously rejected credential may be resubmitted with corrected evidence

Given Maria previously submitted a professional verification request
And that request did not result in verification
And Maria has corrected the relevant professional information or evidence

When Maria submits a new valid verification request

Then a new verification attempt may be created
And the previous verification history remains traceable

---

### Scenario: Verification evidence is not public

Given Maria submits supporting professional evidence

When an Anonymous Visitor or unrelated Organization Member views Maria's
publicly available information

Then the verification evidence is not exposed solely because it was submitted

---

### Scenario: Verification request does not create Clinic Assignment

Given Maria has a Veterinarian Professional Profile

When Maria submits a verification request

Then Maria is not automatically assigned to any Clinic
And no Clinic-specific authority is granted

---

## 6. Verification Evidence

Verification evidence is information used to assess whether the claimed
professional credential can be trusted.

Evidence is not part of the normal public Professional Profile by default.

The architecture must preserve an appropriate distinction between:

- public professional information;
- internal professional-registration information;
- protected verification evidence;
- verification outcome.

The exact storage mechanism is outside this Specification.

---

## 7. Verification History

Professional verification should remain historically understandable.

Conceptually:

Maria Garcia  
Veterinarian Professional Profile

2026-08-20  
Verification requested  
Credential: XXXXX / Authority A

2026-08-22  
Verification rejected  
Reason category: insufficient evidence

2026-08-25  
New verification requested

The detailed decision itself is governed by the verification-resolution
Specification.

---

## 8. Edge Cases

### Credential information changes while verification is pending

Professional credential information used by an active verification request
must not silently change underneath that verification process.

If material credential information changes, the existing request may need to
be invalidated or replaced.

The exact transition behavior is defined by the verification-resolution or
Professional Profile editing Specifications.

---

### Professional has credentials in multiple jurisdictions

The same Professional Profile may eventually contain multiple professional
credentials.

Each credential may require its own verification context.

The initial delivery of the professional-verification capability does not need to support multiple simultaneous professional registrations unless explicitly required by an approved Requirement or Specification.

---

### External authoritative source unavailable

Verification may depend on an external authoritative registry or manual review.

Temporary inability to perform verification must not result in automatic
successful verification.

The request may remain unresolved according to the verification workflow.

---

## 9. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 10. Dependencies

- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-ID-003 — Authenticate User

---

## 11. Out of Scope

This Specification does not define:

- approving professional verification;
- rejecting professional verification;
- verification-review actors;
- automatic verification provider;
- manual review interface;
- exact required evidence;
- public verification badges;
- professional suspension;
- credential expiration;
- credential renewal;
- Organization Membership;
- Clinic Assignment;
- medical-record access.

---

## 12. Verification Notes

Verification must demonstrate that:

1. a User may request verification only for their own Professional Profile;
2. the verification request applies to the existing Professional Profile;
3. submitting a request does not create another User or professional identity;
4. professional verification does not require Organization Membership;
5. submission does not create Organization Membership or Clinic Assignment;
6. Organization authority cannot directly establish platform professional verification;
7. a pending request does not grant verified-professional capabilities;
8. submitted evidence remains protected;
9. duplicate equivalent pending requests are avoided;
10. previous unsuccessful attempts may remain traceable while later corrected requests are possible;
11. verification status cannot be arbitrarily selected by the User;
12. verification submission grants no medical access.
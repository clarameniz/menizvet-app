# SPEC-VET-003 — Resolve Veterinarian Credential Verification

**Status:** APPROVED  
**Requirements:** REQ-VET-006  
**Domain:** Veterinary Professionals  
**Priority:** P2
**Delivery:** Later

## 1. Intent

Allow an authorized platform verification process to resolve a pending
Veterinarian credential verification request.

A verification request may result in either:

- successful verification of the submitted professional credential; or
- rejection of the verification request.

The verification outcome applies to the professional credential and evidence
that were actually evaluated.

Veterinary Organizations and Clinics must not be able to establish platform
professional verification solely through their own authority.

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

- The Veterinarian Professional Profile exists.
- A professional credential exists for the Profile.
- A verification request exists for that credential.
- The verification request is currently `PENDING`.
- The submitted credential information remains consistent with the
  information being evaluated.
- The required verification evidence is available.
- The resolving actor or process is authorized by the platform to establish
  professional verification outcomes.

---

## 3. Business Rules

### BR-1 — Verification outcome is established by an authorized platform process

A professional verification request may only be resolved by a verification
actor or process explicitly authorized by the platform.

The verification mechanism may eventually be:

- manual;
- automated against an authoritative source;
- hybrid.

This Specification does not require a particular implementation.

---

### BR-2 — Organization authority does not establish platform verification

Organization Owners, Administrators, Clinic personnel, or other Organization
Members must not be able to mark a Veterinarian as professionally verified
solely through their Organization authority.

An Organization may decide whether it wishes to employ or work with a User.

That decision is separate from platform professional verification.

---

### BR-3 — A User cannot verify their own professional credential

The owner of the Veterinarian Professional Profile must not be able to resolve
their own verification request as `VERIFIED`.

Submitting credentials and resolving their verification are separate
operations.

---

### BR-4 — A pending request may resolve to VERIFIED

When the submitted professional credential has been successfully validated
according to the applicable verification policy, the verification request may
transition from:

PENDING → VERIFIED

The successful outcome must identify the credential that was verified.

---

### BR-5 — A pending request may resolve to REJECTED

When the submitted professional credential cannot be successfully validated,
the verification request may transition from:

PENDING → REJECTED

A rejected verification request must not grant verified-professional
capabilities.

---

### BR-6 — Rejection requires a meaningful reason

A rejected verification request must preserve a meaningful reason or reason
category explaining why verification was not established.

The reason must be sufficient to support traceability and, where appropriate,
allow the professional to understand whether a corrected future submission is
possible.

The rejection reason must not unnecessarily expose sensitive internal
security or verification mechanisms.

---

### BR-7 — Verification applies to the evaluated credential

A successful verification outcome applies to the professional credential and
credential context that were actually evaluated.

It must not automatically verify:

- another professional registration;
- another jurisdiction;
- another User;
- another Professional Profile.

---

### BR-8 — Verification must be bound to the evaluated credential version

Material professional credential information must not silently change while
retaining a verification outcome that was established for different data.

If information relevant to the verification changes, the existing verification
must not be interpreted as validating information that was never evaluated.

The exact re-verification workflow is defined separately.

---

### BR-9 — Successful verification does not create Organization Membership

A `VERIFIED` professional credential must not automatically:

- join the User to a Veterinary Organization;
- create Organization Membership;
- assign Organization responsibilities;
- create Clinic Assignment.

Professional qualification and employment remain separate concepts.

---

### BR-10 — Successful verification does not create Clinic Assignment

Professional verification establishes trust in a professional credential.

It does not establish where the Veterinarian currently practices.

Clinic Assignment requires its own domain workflow.

---

### BR-11 — Successful verification does not grant universal medical access

A verified Veterinarian must not receive access to arbitrary Pets or Medical
Records solely because their professional credential is verified.

Medical access remains dependent on explicit authorization and professional
context.

---

### BR-12 — Successful verification enables only capabilities that explicitly require it

A verified professional credential may satisfy the professional-verification
condition of another Specification.

Verification alone does not grant that operation.

All other applicable requirements must still be satisfied.

For example, an operation may require:

- verified professional credential;
- active Organization Membership;
- active Clinic Assignment;
- valid Pet medical-access authorization.

Verification satisfies only the professional-verification condition.

---

### BR-13 — Verification outcome must be traceable

The system must preserve enough information to establish:

- which verification request was resolved;
- which professional credential was evaluated;
- the outcome;
- when the outcome was established;
- which authorized actor or process established the outcome;
- the rejection reason where applicable.

---

### BR-14 — Verification evidence remains protected

Resolving a verification request must not make submitted evidence public.

Verification evidence remains protected information even after the request has
been resolved.

A public verification indicator, if introduced later, must expose only the
information explicitly approved for public visibility.

---

### BR-15 — Resolving verification does not modify User identity

Verification must not:

- create a new User;
- replace the existing User;
- create another Veterinarian Professional Profile.

The verification outcome belongs to the existing professional identity.

---

### BR-16 — Resolving verification does not modify personal relationships

Verification must not alter:

- Pet Guardianships;
- personal Appointments;
- existing User profile relationships.

A User may remain both a verified Veterinarian and a Pet Guardian.

---

### BR-17 — Only PENDING requests may be resolved through this workflow

A verification request already resolved as `VERIFIED` or `REJECTED` must not
be resolved again through the same operation.

A later verification attempt requires a distinct verification request where
the applicable workflow permits it.

---

### BR-18 — Resolution is atomic

The verification outcome and its required traceability information form one
logical operation.

The system must not expose a request as resolved without preserving the
required outcome metadata.

---

### BR-19 — External verification failure must not produce automatic success

If an authoritative source or verification mechanism is temporarily
unavailable, the system must not treat that failure as successful
professional verification.

The request may remain unresolved or be handled according to the applicable
verification policy.

---

### BR-20 — Verified status must not be inferred from employment history

Past or current work at a Veterinary Organization, historical Clinic activity,
or an Organization's assertion that a User is a Veterinarian must not substitute
for the platform verification outcome where verified status is required.

---

## 4. Verification Request State Transitions

This Specification establishes:

PENDING → VERIFIED

and:

PENDING → REJECTED

A resolved request does not transition back to `PENDING`.

A future verification attempt must use a new verification request where
appropriate.

---

## 5. Scenarios

### Scenario: Professional credential is successfully verified

Given Maria has a Veterinarian Professional Profile
And Maria has a `PENDING` verification request
And the submitted professional credential is successfully validated
And the resolving process is authorized by the platform

When the verification request is resolved successfully

Then the request becomes `VERIFIED`
And the verified credential remains associated with Maria's existing Professional Profile
And the verification time is preserved
And the resolving actor or process is traceable
And no new User is created
And no new Professional Profile is created

---

### Scenario: Professional credential cannot be verified

Given Maria has a `PENDING` verification request
And the submitted credential cannot be successfully validated
And the resolving process is authorized

When the request is rejected with a meaningful reason

Then the verification request becomes `REJECTED`
And the rejection reason is preserved
And Maria does not gain verified-professional status from that request

---

### Scenario: Rejection without reason is not allowed

Given Maria has a `PENDING` verification request
And an authorized verification process determines that verification cannot
be established

When the process attempts to reject the request without a meaningful reason
or reason category

Then the resolution is not completed as a valid rejection
And the system must not expose an incomplete rejection outcome

---

### Scenario: Organization Owner cannot mark Veterinarian as verified

Given Carlos is Owner of Animalia Veterinary Group
And Maria has a pending professional verification request
And Carlos has no platform verification authority

When Carlos attempts to mark Maria's credential as `VERIFIED`

Then the operation is denied
And Maria's verification request remains unresolved
And Carlos's Organization ownership does not establish professional verification

---

### Scenario: Veterinarian cannot verify their own credential

Given Maria owns the Professional Profile associated with a pending
verification request

When Maria attempts to resolve her own request as `VERIFIED`

Then the operation is denied
And the verification request remains unchanged

---

### Scenario: Verification does not create Organization Membership

Given Maria has no Organization Membership
And Maria's credential is successfully verified

When the verification outcome is established

Then Maria remains without Organization Membership
And no Veterinary Organization relationship is created solely through
verification

---

### Scenario: Verification does not assign a Clinic

Given Maria has no Clinic Assignment
And Maria's professional credential is successfully verified

When verification completes

Then Maria remains unassigned to any Clinic
And no Clinic-specific professional authority is granted

---

### Scenario: Verified Veterinarian still cannot access arbitrary Pet records

Given Maria has a successfully verified professional credential
And Maria has no authorized professional medical-access context for Luna

When Maria attempts to access Luna's protected medical history solely because
she is verified

Then access is denied

---

### Scenario: Verified credential satisfies only the verification condition

Given Maria has a verified professional credential
And an operation requires both verified veterinary status and an active
Clinic Assignment
And Maria has no applicable Clinic Assignment

When Maria attempts the operation

Then the operation is denied
And verified professional status alone is insufficient

---

### Scenario: Already verified request cannot be resolved again

Given Maria's verification request is already `VERIFIED`

When another resolution attempt is made against the same request

Then no second verification outcome is created
And the original verification information remains unchanged

---

### Scenario: Rejected request cannot be converted into verified through the same request

Given Maria's verification request is `REJECTED`

When another attempt is made to resolve that same request as `VERIFIED`

Then the operation is denied
And the original rejected request remains unchanged
And a new verification attempt requires a new request where permitted

---

### Scenario: Credential information changed before resolution

Given Maria submitted a verification request for Credential Version A
And material credential information has since changed to Credential Version B

When the pending request is resolved

Then the system must not treat verification of Version A as verification of
Version B
And the changed professional information requires the applicable
re-verification behavior

---

### Scenario: Authoritative verification source is unavailable

Given Maria has a pending verification request
And the verification process depends on an authoritative external source
And that source is temporarily unavailable

When verification cannot be completed

Then Maria is not automatically considered verified
And the request remains unresolved or follows the applicable non-success
verification policy

---

### Scenario: Verification evidence remains private after success

Given Maria submitted protected evidence
And her professional credential is successfully verified

When an Anonymous Visitor or unrelated Organization Member accesses Maria's
publicly available information

Then the submitted verification evidence is not exposed solely because
verification succeeded

---

### Scenario: Existing Guardianship survives professional verification

Given Maria is Guardian of Luna
And Maria's professional credential is successfully verified

When verification completes

Then Maria remains Guardian of Luna
And Luna remains the same Pet domain entity
And professional verification does not modify the Guardianship relationship

---

## 6. Verified Professional Status

The platform may treat a Veterinarian as satisfying a professional-verification
requirement when the professional has a currently applicable successfully
verified credential.

The domain should avoid reducing this concept to an irreversible permanent
boolean.

Professional credentials may eventually:

- expire;
- be suspended;
- be revoked;
- require renewal;
- change jurisdiction;
- require re-verification.

Those lifecycle behaviors are outside this Specification.

The important rule is:

Verified professional capability must be grounded in an applicable verified
credential, not merely in the existence of a Professional Profile.

---

## 7. Verification Resolution Information

A resolved verification request must preserve sufficient information to make
the decision auditable.

At minimum:

- verification request;
- evaluated professional credential;
- outcome;
- resolution time;
- resolving actor or process;
- rejection reason where applicable.

Additional verification metadata may be stored where required without
becoming publicly visible.

---

## 8. Historical Traceability

Professional verification history must allow the platform to distinguish
different verification attempts.

Conceptually:

Maria Garcia
Veterinarian Professional Profile

Attempt #1
Requested: 2026-08-20
Credential: XXXXX / Authority A
Resolved: 2026-08-22
Outcome: REJECTED
Reason: insufficient evidence

Attempt #2
Requested: 2026-08-25
Credential: XXXXX / Authority A
Resolved: 2026-08-27
Outcome: VERIFIED

The previous rejected attempt remains part of the verification history.

A later successful verification must not rewrite the previous outcome.

---

## 9. Edge Cases

### Previously verified credential information changes

Material changes to a verified credential must not remain covered by the old
verification outcome automatically.

The applicable credential-editing or re-verification workflow must determine
the new status.

---

### Verified credential later expires or is revoked

Successful verification at one point in time does not imply that the
professional credential remains valid forever.

Expiration, suspension, revocation, and renewal require separate
Specifications.

---

### Multiple professional credentials

A Veterinarian may eventually have several professional credentials.

A verification outcome should apply to the specific credential evaluated.

How several verified credentials contribute to the overall professional
status is outside this Specification unless explicitly defined by another
approved Requirement or Specification.

---

### Verification policy changes

A credential verified under an earlier policy may be subject to future
re-verification requirements.

Policy migration behavior must be specified explicitly if introduced.

---

## 10. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 11. Dependencies

- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-002 — Request Veterinarian Credential Verification
- SPEC-ID-003 — Authenticate User

---

## 12. Out of Scope

This Specification does not define:

- the specific veterinary registry used for verification;
- manual-review user interface;
- automatic verification provider;
- exact evidence requirements;
- credential expiration;
- professional suspension;
- professional revocation;
- credential renewal;
- re-verification workflow;
- Professional Profile editing;
- public verification badges;
- Organization Membership;
- Clinic Assignment;
- medical-record access;
- professional disciplinary processes.

---

## 13. Verification Notes

Verification must demonstrate that:

1. only an authorized platform verification actor or process may resolve a
   professional verification request;
2. Organization or Clinic authority alone cannot establish platform
   verification;
3. a User cannot verify their own credential;
4. a pending request may resolve to `VERIFIED`;
5. a pending request may resolve to `REJECTED`;
6. rejection requires a meaningful reason or reason category;
7. verification applies to the credential that was actually evaluated;
8. materially changed credential information is not silently covered by an
   earlier verification outcome;
9. verification does not create Organization Membership or Clinic Assignment;
10. verified professional status does not grant universal medical access;
11. verification satisfies only the verification condition of operations that
    explicitly require it;
12. outcome, resolution time, and resolving actor or process remain traceable;
13. verification evidence remains protected;
14. resolved requests cannot be resolved again through the same workflow;
15. external verification failure cannot produce automatic successful
    verification;
16. historical verification attempts remain distinguishable.
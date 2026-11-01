# SPEC-ID-002 — Verify Email Address

**Status:** APPROVED  
**Requirements:** REQ-ID-001, REQ-ID-008  
**Domain:** Identity  
**Priority:** P0

## 1. Intent

Allow a User who registered using an email-based authentication identity
to prove ownership of that email address.

Email verification changes the verification state of the User's
authentication identity.

It does not create the domain User, since the User already exists after
successful authentication identity creation.

---

## 2. Preconditions

- A domain User exists.
- An email-based authentication identity exists for that User.
- The email address has not yet been successfully verified.

---

## 3. Business Rules

### BR-1 — Verification does not create the User

The domain User must already exist before email verification occurs.

Successful verification changes account state but must not create a second
User or a second domain identity.

---

### BR-2 — Verification proves control of the email address

Successful verification establishes that the User has demonstrated control
of the email address associated with the verification process.

---

### BR-3 — Unverified Users have restricted capabilities

An unverified User must not be allowed to perform operations that explicitly
require a verified account.

Whether a specific operation requires email verification must be defined by
the Specification governing that operation.

Public capabilities available to Anonymous Visitors remain available.

---

### BR-4 — Verification must be bound to the intended identity

A verification mechanism must only verify the authentication identity for
which the verification process was issued.

A verification intended for one identity must not verify another identity.

---

### BR-5 — Verification is idempotent from a domain perspective

Attempting to verify an already verified email must not create additional
Users, capabilities, or duplicated domain state.

---

### BR-6 — Verification does not grant domain roles

Successful email verification must not automatically create:

- Pet Guardianship;
- Veterinarian professional status;
- Organization Membership;
- Clinic assignment.

It only changes the verification state of the authentication identity.

---

## 4. Scenarios

### Scenario: Verify an email successfully

Given a domain User exists
And the User has an unverified email-based authentication identity
And a valid verification process exists for that identity

When the User successfully completes email verification

Then the email authentication identity is marked as verified
And the existing domain User remains the same User
And no additional domain User is created

---

### Scenario: Verified User may proceed to verified-account workflows

Given a User has successfully verified their required email address

When the User attempts an operation that requires a verified account

Then email verification itself does not prevent the operation
And all other authorization rules still apply

---

### Scenario: Unverified User attempts an operation requiring verification

Given a domain User exists
And the User's required email address has not been verified
And the requested operation requires a verified account

When the User attempts the operation

Then the operation is denied
And no protected domain state is created or modified

---

### Scenario: Unverified User accesses public functionality

Given a domain User exists
And the User's email address has not been verified

When the User accesses functionality that is also available to an Anonymous Visitor

Then the functionality remains available

---

### Scenario: Verification information is invalid

Given a User has an unverified email-based authentication identity

When the User attempts verification using invalid verification information

Then the email remains unverified
And the domain User remains unchanged

---

### Scenario: Verification information has expired

Given a User has an unverified email-based authentication identity
And the verification mechanism is no longer valid

When the User attempts to complete verification

Then the email remains unverified
And no domain capability is granted as a result

---

### Scenario: Email is already verified

Given the User's email authentication identity is already verified

When verification is attempted again

Then no duplicate User is created
And no duplicate domain relationship is created
And the verified state remains valid

---

## 5. Edge Cases

### Verification after registration delay

A User may complete email verification at a later time after registration.

The age of the domain User must not be inferred from the email verification
timestamp.

---

### Verification resend

The product may provide a mechanism to request new verification information
when previous verification information has expired or is unavailable.

The resend workflow may be specified separately if it requires meaningful
additional behavior.

---

### Email address change

Changing a verified email address may require the new address to be verified
before it becomes trusted.

The email-change workflow is outside this Specification.

---

## 6. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-015 — Private operations require an authenticated identity.**

Email verification represents account state and does not itself establish
domain capabilities.

---

## 7. Out of Scope

This Specification does not define:

- User registration;
- authentication credentials;
- sign in;
- password recovery;
- email address changes;
- account linking;
- identity merging;
- Organization creation;
- Pet registration;
- professional verification;
- specific verification-token implementation;
- specific email provider behavior.

---

## 8. Verification Notes

Verification must demonstrate that:

1. successful email verification updates the existing identity rather than
   creating a new User;
2. invalid or expired verification does not verify the email;
3. unverified Users cannot perform operations requiring a verified account;
4. public functionality remains available;
5. verification does not grant unrelated domain capabilities;
6. repeated verification does not create duplicated domain state.
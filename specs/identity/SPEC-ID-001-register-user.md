# SPEC-ID-001 — Register User

**Status:** APPROVED
**Requirements:** REQ-ID-001, REQ-ID-005
**Domain:** Identity
**Priority:** P0

## 1. Intent

Allow a person who does not yet have an account to create a User identity in the platform using a supported authentication mechanism.

Registration creates the person's platform identity.

It does not automatically make the User:

* a Pet Guardian;
* a Veterinarian;
* an Organization Member;
* an Organization Administrator.

Those capabilities must result from separate domain relationships or workflows.

---

## 2. Preconditions

* The person is not currently authenticated.
* The requested authentication identifier is valid according to the supported authentication mechanism.
* The identifier is not already associated with an existing authentication identity in a way that prevents registration.

---

## 3. Business Rules

### BR-1 — Registration creates a User identity

A successful registration must result in a User identity that can later participate in domain relationships.

---

### BR-2 — Registration does not assign domain capabilities

Registering an account must not automatically create:

* Pet Guardianship;
* Veterinarian professional status;
* Organization Membership;
* Clinic assignment.

---

### BR-3 — Authentication identity and domain User are distinct concepts

The authentication mechanism used during registration must not become the source of domain roles or capabilities.

---

### BR-4 — Duplicate identities must not be silently created

If the supplied authentication identifier is already associated with an existing account in a way that makes creating another identity invalid, registration must not silently create a second User.

The exact future account-linking or identity-merging behavior is outside this Specification.

---

### BR-5 — Registration outcome must not reveal unnecessary account information

When registration fails because an identifier already exists, the externally observable response must follow the security behavior supported by the authentication architecture.

The system must not expose more account information than necessary.

---

### BR-6 — Domain User creation

A successfully created authentication identity must result in the creation
of the corresponding domain User.

Email verification, when required, is a separate account state and must not
determine whether the domain User exists.

---

### BR-7 — Registration collects only registration-required information

Registration must require only the information necessary to establish the
supported authentication identity and create the corresponding domain User.

Additional personal profile information must not be required solely because
it may be useful in later workflows.

Profile completion is a separate behavior.

---

### BR-8 — Phase 1 registration mechanism

Phase 1 shall support registration using an email address and password.

The domain model must not assume that email and password are the only
authentication mechanisms that may ever be supported.

---

## 4. Scenarios

### Scenario: Register a new User successfully

Given a person is not authenticated
And no existing authentication identity conflicts with the supplied credentials

When the authentication identity is successfully created

Then the corresponding domain User is created
And the User can participate in platform workflows allowed by their current account state
And no Pet Guardianship is created
And no Veterinarian professional profile is created
And no Organization Membership is created
And no Clinic assignment is created

---

### Scenario: Registration does not create a professional identity

Given a person successfully registers

When their new User identity is created

Then the User is not considered a Veterinarian
And professional capabilities are not granted

---

### Scenario: Registration does not make the User a Pet Guardian

Given a person successfully registers

When their new User identity is created

Then the User is not associated with any Pet solely because of registration

---

### Scenario: Registration does not grant Organization capabilities

Given a person successfully registers

When their new User identity is created

Then the User does not belong to any Veterinary Organization solely because of registration
And the User has no Organization-specific administrative capabilities

---

### Scenario: Registration with conflicting existing identity

Given an authentication identity already exists for the supplied identifier

When another registration is attempted using that conflicting identifier

Then a second domain User is not silently created
And the registration attempt does not overwrite the existing User

---

### Scenario: Invalid registration data

Given a person is not authenticated

When they submit registration data that does not satisfy the supported authentication requirements

Then registration is rejected
And no User identity is created

---

## 5. Edge Cases

### Existing account

The system must avoid accidentally creating duplicate domain Users when the authentication mechanism indicates that the identity already exists.

---

### Registration interrupted before authentication identity creation

If registration is interrupted before the authentication identity is
successfully created, a domain User must not be created.

Once the authentication identity has been successfully created, the
corresponding domain User must exist.

Any later verification step, such as email verification, affects the
User's account state and permitted operations, but does not determine
whether the domain User exists.

---

### Email verification

A successfully created authentication identity results in the corresponding
domain User even when email verification is still pending.

An unverified User has restricted capabilities as defined by
[SPEC-ID-002 — Verify Email Address](SPEC-ID-002-verify-email-address.md).

---

## 6. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**

This Specification establishes the User identity without assigning those capabilities.

---

## 7. Out of Scope

This Specification does not define:

* sign in;
* sign out;
* password recovery;
* email verification behavior, defined by SPEC-ID-002;
* account deletion;
* multiple authentication identifiers;
* identity merging;
* Pet registration;
* Pet Guardianship;
* Veterinarian profile creation;
* Organization creation;
* Organization Membership;
* Clinic assignment;
* professional verification.
* user profile completion;
* additional authentication mechanisms beyond Phase 1 email/password registration;

---

## 8. Verification Notes

Verification must demonstrate that:

1. a valid registration can establish a User identity;
2. invalid registration does not create a User;
3. conflicting registration does not silently create a duplicate domain User;
4. registration does not automatically grant domain capabilities;
5. professional, Organization, Clinic, and Pet relationships remain independent from registration.

The testing mechanism must not rely only on client-side behavior.

# SPEC-ID-003 — Authenticate User

**Status:** APPROVED  
**Requirements:** REQ-ID-002, REQ-ID-005
**Domain:** Identity  
**Priority:** P0

## 1. Intent

Allow a registered User to prove their identity using a supported
authentication mechanism and establish an authenticated session.

Authentication establishes who the acting User is.

Authentication does not by itself determine what the User is authorized
to do.

---

## 2. Preconditions

- A corresponding authentication identity exists.
- The authentication mechanism used is supported by the platform.

---

## 3. Business Rules

### BR-1 — Valid credentials establish an authenticated session

When valid credentials are provided for an existing authentication identity,
the system must establish an authenticated session for the corresponding User.

---

### BR-2 — Invalid credentials must not establish a session

When the supplied authentication credentials are invalid, authentication
must fail and no authenticated session may be established.

---

### BR-3 — Authentication identifies the existing domain User

Successful authentication must resolve to the existing domain User associated
with the authentication identity.

Authentication must not create another domain User.

---

### BR-4 — Authentication and authorization are separate concerns

Successful authentication establishes the identity of the acting User.

It must not, by itself, grant:

- Pet access;
- medical record access;
- Organization capabilities;
- Clinic capabilities;
- professional veterinary capabilities.

Those permissions are determined independently from authentication.

---

### BR-5 — Authentication and email verification are separate states

A User may successfully prove their authentication credentials while their
required email address remains unverified.

The resulting account capabilities remain restricted according to
SPEC-ID-002.

---

### BR-6 — Authentication failure must not reveal sensitive account information

Failed authentication responses must not unnecessarily expose sensitive
information about the existence, state, or credentials of another account.

---

## 4. Scenarios

### Scenario: Authenticate with valid credentials

Given Maria has an existing domain User
And Maria has an email-based authentication identity
And Maria provides valid credentials

When Maria authenticates

Then an authenticated session is established
And the session represents Maria's existing domain User
And no additional domain User is created

---

### Scenario: Authenticate with invalid password

Given Maria has an existing email-based authentication identity

When authentication is attempted with an invalid password

Then authentication fails
And no authenticated session is established

---

### Scenario: Authenticate with an unknown identity

Given no authentication identity matches the supplied credentials

When authentication is attempted

Then authentication fails
And no domain User is created
And no authenticated session is established

---

### Scenario: Authentication does not grant domain permissions

Given Maria successfully authenticates
And Maria has no Organization Membership
And Maria has no Pet Guardianship

When the authenticated session is established

Then Maria does not gain Organization capabilities
And Maria does not gain access to any Pet solely because she authenticated

---

### Scenario: Authenticate before email verification

Given Maria has an existing domain User
And Maria's authentication credentials are valid
And Maria's required email address is not verified

When Maria authenticates

Then Maria's identity may be authenticated
And the domain User remains unchanged
And operations requiring a verified account remain unavailable according to SPEC-ID-002

---

## 5. Edge Cases

### Already authenticated User

Authenticating while a valid authenticated session already exists must not
create another domain User or duplicate domain relationships.

The exact client session replacement or reuse behavior is an authentication
architecture concern unless product behavior requires otherwise.

---

### Disabled or restricted account

The platform may later support account states that prevent authentication or
restrict account use.

Such states require dedicated specifications before they affect behavior.

---

## 6. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-015 — Private operations require an authenticated identity.**

Authentication establishes User identity but does not establish domain
authorization.

---

## 7. Dependencies

- SPEC-ID-001 — Register User
- SPEC-ID-002 — Verify Email Address

---

## 8. Out of Scope

This Specification does not define:

- User registration;
- email verification;
- sign out;
- password recovery;
- session expiration;
- refresh-token behavior;
- multiple concurrent sessions;
- account suspension;
- multiple authentication providers;
- Pet authorization;
- Organization authorization;
- medical record authorization.

---

## 9. Verification Notes

Verification must demonstrate that:

1. valid credentials can establish an authenticated session;
2. invalid credentials cannot establish a session;
3. authentication resolves to the existing domain User;
4. authentication never creates duplicate Users;
5. successful authentication does not grant unrelated domain capabilities;
6. email verification state remains independent from authentication state.
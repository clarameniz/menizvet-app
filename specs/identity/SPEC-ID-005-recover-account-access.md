# SPEC-ID-005 — Recover Account Access

**Status:** APPROVED  
**Requirements:** REQ-ID-004  
**Domain:** Identity  
**Priority:** P0

## 1. Intent

Allow a User who has lost access to their normal authentication credentials to
recover access to their existing platform account through an authorized
recovery workflow.

Account recovery restores authentication capability for the existing domain
User.

It must not:

- create a replacement User;
- duplicate the User's Pets;
- duplicate Guardianships;
- duplicate Organization Memberships;
- duplicate Veterinarian Professional identity;
- duplicate Clinic Assignments;
- duplicate Appointments;
- create new medical history.

Recovery changes how the User can authenticate.

It does not replace their domain identity.

---

## 2. Preconditions

- The User account already exists.
- The User has an authentication identity eligible for account recovery.
- A supported recovery mechanism is available.
- The recovery request can be associated with the intended authentication
  identity without exposing protected account information.
- The User successfully proves control of the applicable recovery context
  before recovery is completed.
- The recovery authorization has not expired or previously been consumed.

---

## 3. Business Rules

### BR-1 — Recovery preserves domain User identity

Successful account recovery must restore access to the existing domain User.

It must not create another domain User solely because:

- the User forgot a password;
- authentication credentials were replaced;
- a recovery link was used;
- another supported authentication credential was established.

Conceptually:

    Maria
    User ID: U-123
        ↓
    loses authentication access
        ↓
    recovery
        ↓
    Maria
    User ID: U-123

The domain identity remains unchanged.

---

### BR-2 — Recovery does not duplicate domain relationships

Successful recovery must preserve the User's existing relationships.

This includes, where applicable:

- Guardianships;
- Organization Memberships;
- Veterinarian Professional Profile;
- Clinic Assignments;
- Appointment relationships;
- historical authorship;
- medical-access audit attribution.

---

### BR-3 — Recovery requires proof of authorized recovery context

Possession of a User identifier, email address, display name, or other
publicly discoverable information must not be sufficient to recover an account.

The User must prove control of an approved recovery context.

The exact authentication-provider mechanism is architectural.

---

### BR-4 — Recovery mechanism must be bound to the intended account

A recovery authorization must apply only to the intended authentication
identity.

A recovery reference for one User must not be usable to change authentication
credentials for another User.

---

### BR-5 — Recovery authorization has finite validity

A recovery authorization must expire.

The system must not assume that a recovery link, token, or equivalent
authorization remains valid indefinitely.

The exact validity duration is a security configuration concern.

---

### BR-6 — Recovery authorization is single-use

Once a recovery authorization has been successfully consumed, it must not be
reusable to perform another account recovery.

Repeated use must not create additional credential changes or authentication
capabilities.

---

### BR-7 — Expired recovery authorization cannot be used

An expired recovery authorization must not allow account access to be restored.

A new recovery workflow is required.

---

### BR-8 — Previously used recovery authorization cannot be reused

A successfully consumed recovery authorization must no longer provide valid
recovery authority.

---

### BR-9 — Account recovery must not expose whether an account exists unnecessarily

The recovery-request workflow should avoid revealing account existence to an
unauthorized requester where doing so would enable account enumeration.

For example, the public response to:

    "Recover account for person@example.com"

must not needlessly reveal whether that address corresponds to a registered
User.

The exact user-facing response is a security and UX concern.

---

### BR-10 — Recovery requests do not themselves grant access

Requesting account recovery must not:

- authenticate the requester;
- reveal protected User information;
- grant Organization capability;
- grant Pet access;
- grant medical access.

Access is restored only after the applicable recovery proof succeeds.

---

### BR-11 — Recovery does not automatically change domain profile information

Recovering authentication access must not silently change:

- User Profile information;
- Pet Profile information;
- public professional information;
- Organization Membership information.

Authentication identity and domain profile information remain separate
concepts.

---

### BR-12 — Recovery does not change Organization Membership

Successful account recovery must not:

- create Organization Membership;
- end Organization Membership;
- change responsibilities;
- change effective Membership periods.

---

### BR-13 — Recovery preserves Memberships across several Organizations

If the User belongs to several Veterinary Organizations, recovering account
access must restore authentication to the same User associated with all those
existing Membership relationships.

For example:

    Dr. Garcia
    ├── Animalia Membership
    └── VetCare Membership

Recovery must not create separate Users for those Organization relationships.

---

### BR-14 — Recovery does not change Guardianship

Successful recovery must not:

- add a Guardian;
- remove a Guardian;
- change Pet identity;
- transfer Guardianship.

The recovered User regains the ability to authenticate and may then exercise
current Guardianship capabilities where those relationships remain active.

---

### BR-15 — Recovery does not change Veterinarian Professional identity

If the User has a Veterinarian Professional Profile, recovery must preserve
that professional identity.

Credential loss must not cause professional qualification to be recreated or
reverified solely because authentication was recovered.

---

### BR-16 — Recovery does not change Clinic Assignments

Current and historical Clinic Assignments must remain unchanged by account
recovery.

---

### BR-17 — Recovery does not alter Appointment lifecycle

Account recovery must not:

- create an Appointment;
- confirm an Appointment;
- cancel an Appointment;
- reschedule an Appointment;
- complete an Appointment;
- mark an Appointment `NO_SHOW`.

---

### BR-18 — Recovery does not alter medical history

Account recovery must not change:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- clinical provenance.

Historical medical authorship must remain attached to the same domain User.

---

### BR-19 — Recovery preserves historical authorship

If a professional previously authored clinical information, recovering their
account must not change or recreate that authorship.

For example:

    Dr. Garcia
    User U-123
    authored Entry E-99

after recovery remains:

    Dr. Garcia
    User U-123
    authored Entry E-99

---

### BR-20 — Recovery does not grant current capabilities automatically

Successful recovery restores authentication capability.

Current domain capabilities must still be evaluated from current relationships
and authorization state.

For example, if the User's Organization Membership ended while they lacked
account access, recovery must not restore the previous expired Membership
capabilities.

---

### BR-21 — Recovery reflects current domain state

After successful recovery and authentication, the User's permissions must be
derived from the current domain state.

Historical or cached pre-recovery permissions must not be blindly restored.

---

### BR-22 — Successful recovery invalidates previous authentication sessions

Successful Phase 1 account recovery must invalidate authentication sessions
established before the recovery completed.

This reduces the risk that:

- a lost device;
- stolen credentials;
- an unknown existing session

continues accessing the account after recovery.

The exact session-revocation mechanism is architectural.

---

### BR-23 — Recovery invalidates authentication sessions, not domain relationships

Revoking previous sessions after recovery must not:

- end Memberships;
- end Guardianships;
- revoke Clinic Assignments;
- delete Appointments;
- revoke Care Authorizations merely because authentication changed.

Session revocation and domain lifecycle remain separate.

---

### BR-24 — New authentication requires current credential state

After successful recovery, obsolete credentials must not continue providing
normal authentication where the recovery workflow replaced those credentials.

The exact credential-management mechanism depends on the authentication
provider.

---

### BR-25 — Recovery failure preserves existing domain state

If recovery fails, expires, or is rejected:

- the User domain identity remains unchanged;
- Organization Memberships remain unchanged;
- Guardianships remain unchanged;
- medical history remains unchanged.

The failed recovery attempt must not partially mutate unrelated domain state.

---

### BR-26 — Recovery attempt may be security-auditable

Security-relevant account recovery activity must be capable of being audited
where required.

This may include:

- recovery requested;
- recovery completed;
- suspicious or repeated failed recovery activity.

Authentication-security auditing remains distinct from Medical Access Audit
Events.

---

### BR-27 — Recovery secrets must not be exposed through ordinary application data

Recovery tokens, codes, or equivalent secrets must not become:

- User Profile fields;
- Organization-visible information;
- public data;
- analytics properties.

They are sensitive authentication material.

---

### BR-28 — Recovery secrets must not be stored as ordinary reusable credentials

The architecture must protect recovery authorization material appropriately.

Recovery mechanisms must not rely on permanently reusable plain-text recovery
secrets.

The exact cryptographic implementation is architectural.

---

### BR-29 — Recovery does not require the User to create another account

If the User can validly prove control of the recovery context, they must recover
the existing account rather than being instructed to create another domain
User.

---

### BR-30 — A different authentication identifier must not automatically imply a different User

Where the Identity architecture later permits changing or attaching
authentication identifiers, authentication identifier and domain User identity
must remain distinguishable.

However, changing the primary authentication identifier itself is not defined
by this Specification.

---

### BR-31 — Loss of the recovery channel is not automatically recoverable

If the User cannot prove control of any supported recovery context, the system
must not weaken authentication requirements merely to restore access.

A future assisted identity-recovery workflow may be introduced separately if
required.

---

### BR-32 — Support personnel must not bypass identity proof through ordinary application behavior

Phase 1 account recovery must not assume that an administrator can manually
take over an account without a dedicated controlled and auditable process.

Manual identity recovery is outside this Specification.

---

### BR-33 — Recovery completion is atomic

Successful recovery must coherently establish the new valid authentication
state and invalidate the applicable obsolete recovery authorization.

The system must not expose a partially recovered state in which:

- the recovery authorization remains reusable;
- the new credential is only partially established;
- account ownership is ambiguous.

---

## 4. Recovery Information

The Identity system must support enough information to perform account recovery
without making recovery data part of the business domain.

Conceptually, recovery may involve:

- intended authentication identity;
- recovery authorization;
- creation time;
- expiration time;
- consumed or invalid state;
- trusted verification context.

The exact persistence model belongs to authentication architecture.

---

## 5. Scenarios

### Scenario: Existing User successfully recovers account

Given Maria already has a platform User
And Maria has lost access to her normal authentication credential
And Maria requests account recovery
And Maria proves control of the approved recovery context
And the recovery authorization remains valid

When Maria completes account recovery

Then authentication capability is restored for Maria's existing User
And no new domain User is created
And the recovery authorization can no longer be reused

---

### Scenario: Recovery preserves Guardianship

Given Maria is an active Guardian of Luna
And Maria loses authentication access

When Maria successfully recovers her account

Then Maria remains the same domain User
And Maria remains Luna's Guardian
And Luna is not duplicated

---

### Scenario: Recovery preserves Organization Membership

Given Maria has an active Membership in Animalia Veterinary Group
And Maria successfully recovers her account

Then the existing Animalia Membership remains associated with Maria
And no duplicate Membership is created
And its responsibilities remain unchanged

---

### Scenario: Recovery preserves multiple Organization Memberships

Given Dr. Garcia has an active Membership in Animalia Veterinary Group
And an active Membership in VetCare Group
And Dr. Garcia loses account access

When Dr. Garcia successfully recovers the account

Then the same User remains associated with both Memberships
And neither Membership is duplicated
And Organization-specific capabilities remain scoped independently

---

### Scenario: Recovery preserves Veterinarian identity

Given Dr. Garcia has a Veterinarian Professional Profile

When Dr. Garcia successfully recovers account access

Then the existing Veterinarian Professional Profile remains unchanged
And a second professional identity is not created

---

### Scenario: Recovery preserves clinical authorship

Given Dr. Garcia previously finalized clinical information for Luna
And the record identifies Dr. Garcia as its author

When Dr. Garcia later recovers account access

Then the historical clinical information remains unchanged
And its authorship continues to refer to the same domain User and professional
identity

---

### Scenario: Recovery does not restore ended Membership capability

Given Maria previously had an active Membership in Animalia Veterinary Group
And Maria loses account access
And the Animalia Membership subsequently ends

When Maria later recovers and authenticates

Then Maria's domain User is recovered
And the historical Animalia Membership remains ended
And former Animalia capabilities are not restored

---

### Scenario: Unknown email does not need to reveal account existence

Given an unauthenticated person submits a recovery request using an email
address

When the recovery request is processed

Then the public response need not reveal whether a platform account exists for
that address
And protected account information is not disclosed

---

### Scenario: Recovery request alone grants no access

Given Carlos knows Maria's email address

When Carlos requests recovery using Maria's email address
But Carlos cannot prove control of the applicable recovery context

Then Carlos does not gain authentication
And Carlos gains no access to Maria's Pets, Organizations, or medical
information

---

### Scenario: Expired recovery authorization is rejected

Given Maria has a recovery authorization
And that authorization has expired

When Maria attempts to complete recovery using it

Then recovery is rejected
And the authorization does not restore account access
And a new valid recovery process is required

---

### Scenario: Recovery authorization cannot be reused

Given Maria successfully completed account recovery using Recovery
Authorization A

When Recovery Authorization A is presented again

Then it is rejected
And no further credential change occurs

---

### Scenario: Recovery for one User cannot modify another User

Given Maria has Recovery Authorization A
And Carlos has a separate platform User

When Recovery Authorization A is used

Then it can only affect Maria's intended authentication context
And Carlos's account remains unchanged

---

### Scenario: Previous sessions are invalidated

Given Maria has an authenticated session on a lost phone
And Maria completes account recovery from another device

When recovery succeeds

Then authentication sessions established before the recovery are invalidated
And the lost phone's previous session can no longer perform authenticated
private operations

---

### Scenario: Session invalidation does not remove Guardianship

Given Maria is Luna's Guardian
And recovery invalidates Maria's previous sessions

When Luna's domain relationships are evaluated

Then Maria remains Luna's Guardian
And only authentication session state changed

---

### Scenario: Failed recovery preserves domain state

Given Maria has an existing User with Pets and Organization Memberships
And a recovery attempt fails validation

When the failure occurs

Then Maria's User remains unchanged
And her Pets remain unchanged
And her Memberships remain unchanged
And no new User is created

---

### Scenario: User cannot prove recovery-channel control

Given Maria claims ownership of an existing account
And Maria cannot prove control of any supported recovery context

When account recovery is attempted

Then access is not restored through the normal Phase 1 workflow
And the authentication requirements are not weakened

---

## 6. Recovery vs Registration

Registration answers:

    "Create a new platform User."

Recovery answers:

    "Restore authentication access to an existing platform User."

Therefore:

    lost password
        ↓
    recovery

must not become:

    lost password
        ↓
    register another User
        ↓
    duplicate Maria

This distinction is critical because domain relationships belong to the
existing User identity.

---

## 7. Recovery vs Domain Relationships

The domain User may already participate in many relationships:

    Maria
      ├── Guardian → Luna
      ├── Guardian → Toby
      ├── Membership → Animalia
      └── Appointments

Account recovery changes:

    authentication access

It does not recreate:

    Maria
      ├── Luna
      ├── Toby
      ├── Animalia
      └── Appointments

Those relationships already exist.

---

## 8. Recovery and Session Security

Account recovery may occur because:

- the User forgot a credential;
- the User lost a device;
- the User suspects credential compromise.

For Phase 1, successful recovery therefore invalidates previous authentication
sessions.

Conceptually:

    old credential / sessions
            ↓
        no longer trusted

    recovery succeeds
            ↓
    new authentication state
            ↓
    new session established

Domain relationships remain unchanged.

---

## 9. Edge Cases

### User remembers credentials after requesting recovery

Requesting recovery does not itself need to invalidate existing credentials.

If the recovery authorization remains unused, normal authentication may remain
possible according to the authentication provider's policy.

Once recovery is successfully completed, the applicable previous sessions are
invalidated.

---

### Several recovery requests are created

The system must avoid allowing several outstanding recovery authorizations to
create ambiguous credential state.

Issuing a newer recovery authorization may invalidate earlier ones according to
the authentication security policy.

The exact mechanism is architectural.

---

### User loses access to email

If the normal recovery mechanism depends on control of an email address that
the User can no longer access, the system must not simply bypass identity proof.

Assisted account recovery requires separate requirements if supported.

---

### Authentication provider changes later

The domain User must remain stable even if the technical authentication
provider changes.

Provider migration must not require recreating Pets, Memberships, or clinical
authorship.

---

### User has several authentication methods in future

Future Identity architecture may allow several authentication mechanisms to
refer to one domain User.

This Specification does not define that model, but account recovery must not
assume permanently that one authentication identifier equals one domain User.

---

## 10. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-006 — Organization Membership is temporal.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-ID-001 — Register User
- SPEC-ID-002 — Verify Email Address
- SPEC-ID-003 — Authenticate User
- SPEC-ID-004 — Sign Out

Recovered domain capabilities remain governed by their applicable
Specifications.

---

## 12. Out of Scope

This Specification does not define:

- manual support-assisted identity recovery;
- changing the primary authentication email or identifier;
- account deletion;
- account deactivation;
- global authentication-provider migration;
- multi-factor authentication;
- recovery codes;
- password-policy details;
- exact recovery-token format;
- exact recovery-token duration;
- email-delivery provider;
- SMS recovery;
- social-login recovery;
- organization-admin account takeover;
- restoring deleted accounts.

---

## 13. Verification Notes

Verification must demonstrate that:

1. an eligible User can recover access to an existing account;
2. recovery does not create another domain User;
3. recovery preserves Pets and Guardianships;
4. recovery preserves Organization Memberships;
5. recovery preserves multiple independent Organization relationships;
6. recovery preserves Veterinarian Professional identity;
7. recovery preserves Clinic Assignments;
8. recovery preserves Appointment relationships and lifecycle;
9. recovery preserves historical clinical authorship and medical data;
10. recovery requires proof of an authorized recovery context;
11. recovery authorization is account-bound, finite, and single-use;
12. expired or previously consumed recovery authorization cannot be reused;
13. requesting recovery does not itself grant authentication or protected
    access;
14. recovery flows avoid unnecessarily exposing account existence;
15. successful recovery reflects current domain authorization rather than stale
    previous capability state;
16. successful recovery invalidates prior authentication sessions;
17. session invalidation does not modify domain relationships;
18. failed recovery leaves existing domain state unchanged;
19. lack of control of the supported recovery context does not weaken
    authentication requirements;
20. recovery completion behaves atomically.
# SPEC-ID-004 — Sign Out

**Status:** APPROVED  
**Requirements:** REQ-ID-003  
**Domain:** Identity  
**Priority:** P0

## 1. Intent

Allow an authenticated User to end their current authenticated session.

Signing out must remove the User's current authenticated access from the
applicable client or session context.

Signing out must not:

- delete the User;
- remove Organization Memberships;
- remove Guardianships;
- remove Veterinarian Professional identity;
- remove Clinic Assignments;
- delete Appointments;
- revoke Care Authorizations;
- delete medical history.

Authentication session lifecycle and domain relationship lifecycle are separate
concerns.

---

## 2. Preconditions

- The acting User has an active authenticated session.

---

## 3. Business Rules

### BR-1 — Sign out ends current authenticated access

A successful sign-out operation must end the authenticated session represented
by the applicable client or session context.

Subsequent private operations using that ended session must not be treated as
authenticated.

---

### BR-2 — Sign out does not delete the User

Signing out must not delete or deactivate the User domain identity.

The User may authenticate again later through the applicable authentication
workflow.

---

### BR-3 — Sign out does not end Organization Membership

Signing out must not:

- end an Organization Membership;
- modify its responsibilities;
- change its effective start or end.

Professional relationships remain intact.

---

### BR-4 — Sign out does not affect Memberships in other Organizations

A User may belong to several Veterinary Organizations.

Signing out must not alter any of those Membership relationships.

---

### BR-5 — Sign out does not affect Guardianship

Signing out must not:

- end Guardianship;
- remove the User from a Pet;
- remove another Guardian;
- change Pet identity.

The User's current access disappears because they are no longer authenticated,
not because the underlying Guardianship changed.

---

### BR-6 — Sign out does not affect Veterinarian Professional identity

If the User has a Veterinarian Professional Profile, signing out must not
remove or alter that professional identity.

---

### BR-7 — Sign out does not affect Clinic Assignment

Signing out must not end or modify current or historical Clinic Assignments.

---

### BR-8 — Sign out does not alter Appointment lifecycle

Signing out must not:

- cancel an Appointment;
- confirm an Appointment;
- complete an Appointment;
- mark an Appointment `NO_SHOW`;
- reschedule an Appointment.

Existing Appointment state remains unchanged.

---

### BR-9 — Sign out does not revoke Care Authorization

Signing out must not revoke or modify a Pet Care Authorization.

The authorization remains governed by its own lifecycle.

A signed-out User cannot exercise protected access because authentication is
absent.

---

### BR-10 — Sign out does not alter medical history

Signing out must not change:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- medical provenance.

---

### BR-11 — Signing out from one session need not invalidate every other session by default

Phase 1 sign out may end only the current authenticated session or client
context.

For example:

    User signed in on phone
    User signed in on tablet

Signing out on the phone does not necessarily require invalidating the tablet
session.

Global sign-out behavior must be defined separately if required.

---

### BR-12 — Ended session cannot be reused as valid authentication

Once the applicable session is successfully ended, its previous authentication
state must not continue to authorize private operations.

The exact token invalidation and session-management mechanism is
architectural.

---

### BR-13 — Client-side screen change alone is not sufficient

Merely navigating the client to a signed-out screen must not be treated as
authoritative session termination.

The applicable authentication session must be ended through trusted
authentication infrastructure.

---

### BR-14 — Cached domain information does not create authorization

Information previously displayed while the User was authenticated must not
become a source of continued authorization after sign out.

The client may need to clear or protect previously cached sensitive data.

Exact client-cache handling is architectural.

---

### BR-15 — Sensitive local state should not remain exposed after sign out

The client must not intentionally continue exposing protected information from
the previous authenticated session after sign out.

This may include information such as:

- Pet data;
- Appointments;
- Organization data;
- medical history;
- Clinical Attachments.

The exact local-state and secure-storage cleanup strategy is architectural.

---

### BR-16 — Sign out does not require network-domain mutation

Signing out is an authentication-session operation.

It must not require modifying unrelated domain entities merely to represent
that the User is no longer authenticated.

---

### BR-17 — Re-authentication restores access according to current domain state

If the User later signs in again, their capabilities must be evaluated from the
current domain state.

For example:

- current Organization Membership;
- current Guardianship;
- current Clinic Assignment;
- current Entitlements;
- current medical-access authorization.

Previous session capabilities must not be blindly restored from stale client
state.

---

### BR-18 — Relationships may change while User is signed out

A User may sign out and later return after some domain relationship changed.

For example:

    sign out
        ↓
    Organization Membership ends
        ↓
    sign in later

The new session must reflect the current Membership state rather than the state
that existed before sign out.

---

### BR-19 — Sign out is idempotent from the User perspective

Repeated attempts to sign out an already-ended session must not recreate
authentication or alter unrelated domain state.

The client may treat the User as signed out once the applicable session is no
longer valid.

---

### BR-20 — Sign out failure must not fabricate successful revocation

If the system cannot reliably end the applicable authenticated session, it must
not represent trusted session termination as successfully completed when the
session remains valid.

The exact degraded or retry behavior is architectural.

---

## 4. Scenarios

### Scenario: User signs out successfully

Given Maria has an active authenticated session

When Maria signs out

Then the current session ends
And subsequent private operations using that session are not authenticated
And Maria's User identity remains unchanged

---

### Scenario: Sign out preserves Organization Membership

Given Maria has an active Membership in Animalia Veterinary Group
And Maria is authenticated

When Maria signs out

Then Maria's Animalia Membership remains active
And its responsibilities remain unchanged
And Maria cannot exercise those capabilities again until she authenticates

---

### Scenario: Sign out preserves Memberships in several Organizations

Given Dr. Garcia has active Memberships in Animalia Veterinary Group and
VetCare Group

When Dr. Garcia signs out

Then both Memberships remain unchanged
And neither relationship is ended

---

### Scenario: Sign out preserves Guardianship

Given Maria is an active Guardian of Luna

When Maria signs out

Then Maria remains Luna's Guardian
And Luna's Pet identity remains unchanged
And Maria cannot access Luna's protected information until she authenticates
again

---

### Scenario: Sign out preserves Veterinarian identity

Given Dr. Garcia has a Veterinarian Professional Profile

When Dr. Garcia signs out

Then the Veterinarian Professional Profile remains unchanged

---

### Scenario: Sign out preserves Clinic Assignment

Given Dr. Garcia has an active Clinic Assignment at Animalia Madrid Centro

When Dr. Garcia signs out

Then the Clinic Assignment remains active
And no Assignment history is changed

---

### Scenario: Sign out preserves Appointment

Given Luna has a confirmed Appointment requested by Maria

When Maria signs out

Then Luna's Appointment remains `CONFIRMED`
And no Appointment lifecycle transition occurs

---

### Scenario: Sign out preserves Care Authorization

Given Luna has a current Care Authorization
And Maria signs out

When the authorization is evaluated

Then the Care Authorization remains governed by its own lifecycle
And Maria's signed-out session cannot use protected access

---

### Scenario: Previous session cannot perform private operation

Given Maria successfully signed out

When the ended session attempts to access a private Pet operation

Then authentication is rejected
And no private domain capability is granted through the ended session

---

### Scenario: Signing out on phone does not necessarily invalidate tablet session

Given Maria is authenticated on her phone
And Maria is separately authenticated on her tablet

When Maria signs out from the phone

Then the phone session ends
And the tablet session may remain valid
And no domain relationship is changed

---

### Scenario: Client navigation alone does not sign out

Given Maria has an active authenticated session

When the mobile interface merely navigates to a public screen without ending
the underlying session

Then the system must not treat the session as authoritatively signed out solely
because of navigation

---

### Scenario: User signs back in after Membership ended

Given Maria signs out while she has an active Animalia Membership
And that Membership later ends while Maria is signed out

When Maria authenticates again

Then the new session reflects that the Animalia Membership is no longer active
And stale pre-sign-out capabilities are not restored

---

### Scenario: Repeated sign-out attempt does not affect domain state

Given Maria's current session has already ended

When sign out is attempted again

Then Maria remains signed out
And no Organization, Pet, Appointment, or medical state is changed

---

## 5. Sign Out vs Domain Lifecycle

Sign out answers:

    "Is this session currently authenticated?"

It does not answer:

    "Does this User still belong to Animalia?"

or:

    "Is this User still Luna's Guardian?"

or:

    "Is this User still a Veterinarian?"

Those facts exist independently from the current authentication session.

Conceptually:

    User
      │
      ├── Organization Membership
      ├── Guardianship
      ├── Veterinarian Profile
      └── Clinic Assignment

    authentication session
      ↓
    may begin
    may end

Ending the session does not delete the relationships.

---

## 6. Sign Out vs Account Deletion

These operations must remain distinct.

### Sign out

    User continues to exist
    relationships continue to exist
    session ends

### Account deletion

    requires separate identity and historical-retention behavior

Account deletion is outside this Specification.

---

## 7. Edge Cases

### Authentication token expires naturally

Natural session expiration and explicit sign out may use different technical
mechanisms.

Both result in absence of valid authentication for subsequent protected
operations.

---

### User is offline while signing out

Client-side sensitive state should not remain casually exposed after the User
chooses to sign out.

The exact behavior for remote-session invalidation while offline is an
architectural concern.

---

### Device is shared

The client must avoid exposing the previous User's protected cached information
to the next User after sign out.

Secure local data handling is architectural.

---

### User has several devices

Phase 1 sign out need not mean global account sign out.

A future explicit:

    Sign out all devices

workflow may be introduced separately.

---

## 8. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-006 — Organization Membership is temporal.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 9. Dependencies

- SPEC-ID-001 — Register User
- SPEC-ID-002 — Verify Email Address
- SPEC-ID-003 — Authenticate User

Current domain capabilities after future re-authentication remain governed by
their applicable Specifications.

---

## 10. Out of Scope

This Specification does not define:

- global sign out from every device;
- account deletion;
- account deactivation;
- password reset;
- account recovery;
- authentication-token format;
- session-token implementation;
- refresh-token implementation;
- exact local-cache technology;
- exact secure-storage cleanup implementation;
- Organization Membership termination;
- Guardianship termination;
- Clinic Assignment termination.

---

## 11. Verification Notes

Verification must demonstrate that:

1. an authenticated User may end the applicable current session;
2. the ended session no longer provides valid authentication for private
   operations;
3. sign out does not delete or disable the User;
4. sign out does not alter Organization Memberships;
5. sign out does not alter Guardianships;
6. sign out does not alter Veterinarian Professional identity;
7. sign out does not alter Clinic Assignments;
8. sign out does not alter Appointment lifecycle;
9. sign out does not revoke Care Authorization;
10. sign out does not modify medical history;
11. current-session sign out does not necessarily invalidate other independent
    sessions;
12. client navigation alone is not authoritative session termination;
13. protected cached state must not become continued authorization after sign
    out;
14. later re-authentication reflects current domain state rather than stale
    pre-sign-out capabilities;
15. repeated sign-out attempts do not alter unrelated domain state.
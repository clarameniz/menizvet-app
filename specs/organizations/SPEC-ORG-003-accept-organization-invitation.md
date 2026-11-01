# SPEC-ORG-003 — Accept Organization Invitation

**Status:** APPROVED
**Requirements:** REQ-ORG-002, REQ-ORG-003, REQ-ORG-004, REQ-ORG-005
**Domain:** Organizations
**Priority:** P0

## 1. Intent

Allow the intended recipient of a valid Organization Invitation to explicitly accept the invitation and establish an active Organization Membership.

Acceptance converts an approved invitation into a professional relationship with the Veterinary Organization.

The resulting Membership receives only the responsibilities defined by the accepted Invitation.

---

## 2. Preconditions

* The Veterinary Organization exists.
* The Organization Invitation exists.
* The Invitation is pending.
* The Invitation has not expired.
* The Invitation has not been revoked.
* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies any account verification requirement applicable to Organization Membership acceptance.
* The acting User has proven that they are the intended recipient of the Invitation.
* The intended Organization responsibilities remain valid for acceptance.
* Accepting the Invitation would not create an invalid duplicate active Membership.

---

## 3. Business Rules

### BR-1 — Acceptance must be explicit

An Organization Membership must not become active merely because an Invitation exists.

The intended recipient must explicitly accept the Invitation.

---

### BR-2 — Only the intended recipient may accept

An Invitation may only be accepted by a User who has proven that they are the intended recipient.

Possession of an Invitation reference alone is insufficient.

The Invitation reference (`invitation_id`) is an identifier and proves nothing.
The approved proof is the Invitation's bearer secret (BR-18, `SPEC-ORG-002`
BR-21).

---

### BR-3 — Acceptance creates an active Organization Membership

Successful acceptance must establish an active Organization Membership between the accepting User and the Organization identified by the Invitation.

---

### BR-4 — Membership responsibilities come from the Invitation

The responsibilities initially assigned to the resulting Organization Membership must correspond to the responsibilities authorized and recorded by the accepted Invitation.

Acceptance must not allow the recipient to select or escalate their own Organization responsibilities.

---

### BR-5 — Membership start is established at acceptance

The resulting Organization Membership becomes effective when the Invitation is successfully accepted.

The Membership must preserve its effective start.

---

### BR-6 — New Membership has no effective end

A Membership created through Invitation acceptance must initially be active and have no effective end.

Ending the Membership requires a separate domain operation.

---

### BR-7 — Acceptance and Membership creation are atomic

Invitation acceptance and creation of the corresponding Organization Membership form one logical domain operation.

The system must not consider an Invitation successfully accepted if the required Membership cannot be established.

Likewise, the Membership must not be created while leaving the Invitation pending.

---

### BR-8 — An accepted Invitation cannot be accepted again

Once an Invitation has been successfully accepted, it must no longer be usable to create another Organization Membership.

Repeated acceptance attempts must not create duplicate Memberships or capabilities.

---

### BR-9 — Expired Invitations cannot be accepted

An Invitation whose validity period has expired must not create an Organization Membership.

---

### BR-10 — Revoked Invitations cannot be accepted

A revoked Invitation must not create an Organization Membership.

---

### BR-11 — Acceptance does not grant capabilities outside the invited Organization

The resulting Membership only establishes a relationship with the Organization identified by the Invitation.

Acceptance must not grant:

* Membership in another Organization;
* ownership of another Organization;
* Pet Guardianship;
* access to arbitrary Pets;
* access to arbitrary medical records;
* Clinic Assignment;
* veterinary professional qualification.

---

### BR-12 — Acceptance does not establish veterinary qualification

If the Invitation includes a veterinary Organization responsibility, successful acceptance does not itself establish that the User is a recognized Veterinarian.

Professional veterinary identity and Organization Membership remain separate domain concepts.

---

### BR-13 — Acceptance does not create Clinic Assignments

Successful acceptance establishes Organization Membership only.

It must not automatically assign the User to every Clinic, or to any Clinic, solely because the Invitation was accepted.

Clinic Assignment requires separate domain behavior.

---

### BR-14 — Invitation validity does not depend on the inviter remaining a Member

Once an Organization Invitation has been validly created, its continued validity must not depend solely on whether the User who created it still has an active Organization Membership.

If the Invitation remains pending, unexpired, unrevoked, and otherwise valid, it may still be accepted.

Organization members with the appropriate capability may revoke it through the applicable revocation workflow.

---

### BR-15 — Acceptance must not create a second domain User

If the Invitation was delivered to an address different from the User's authentication identifier, successful acceptance must use the existing domain User after the User has proven control of the intended recipient context.

A second domain User must not be created solely to match the Invitation destination.

---

### BR-16 — Membership in another Organization does not prevent acceptance

A User may have active Organization Memberships in multiple Veterinary
Organizations.

An active Membership in another Organization must not by itself prevent the
User from accepting a valid Invitation to the target Organization.

Each Membership remains an independent Organization relationship with its own:

- Veterinary Organization;
- responsibilities;
- effective start;
- effective end;
- derived capabilities.

---

### BR-17 — Acceptance requires no Commercial Onboarding or Subscription

Accepting a valid Organization Invitation must not require the accepting User
to:

- complete Commercial Onboarding;
- hold, establish, or pay for a Subscription;
- establish another Veterinary Organization.

The resulting Membership's paid professional operations are governed by the
inviting Organization's current Entitlements (`SPEC-SUB-003`), together with
the applicable responsibility, Clinic Assignment, and Medical Access rules.

---

### BR-18 — The bearer secret is the recipient proof

Proof that the acting User is the intended recipient (BR-2) is established by
presenting the Invitation's valid bearer secret together with the Invitation
reference.

Acceptance requires all of:

- an authenticated MenizVet User;
- a confirmed email address on that authenticated account (`SPEC-ID-002`);
- a valid Invitation reference;
- the valid bearer secret for that Invitation, verified by trusted backend
  code against the stored one-way digest.

The authenticated account's email address does **not** have to equal the
Invitation's recipient address. Receiving the Invitation at one address and
signing in with another verified MenizVet identity is approved behaviour
(BR-15, `SPEC-ORG-002` BR-16). Presenting the secret delivered to the recipient
address is the proof of control of that recipient context.

Possessing the Invitation reference without the secret is never sufficient,
and is never treated as partial proof.

---

### BR-19 — Authenticated acceptance derives every fact server-side

The client-facing acceptance operation (§11) is callable by `authenticated`
only and requires no `service_role` caller.

The client supplies only the Invitation reference and the bearer secret. It
never supplies:

- the accepting User id — the accepting domain User is derived from the
  authenticated subject;
- a Membership id;
- any responsibility, scope, Clinic, Organization, or effective time — these
  come from the stored Invitation.

The secret is hashed inside trusted backend code and compared with the stored
digest. The plaintext secret is never persisted.

The pre-existing service-role acceptance command, which takes an accepting User
id from its caller, may remain for trusted internal compatibility, but it is
not a client path and no client role holds `EXECUTE` on it.

---

### BR-20 — Proof precedes lifecycle disclosure

Before valid proof is established, every failure is uniform. An unknown
Invitation reference, a wrong secret, a malformed secret, and an Invitation
whose credential is no longer verifiable (for example because it was accepted
by another User) produce the same outcome: SQLSTATE `42501` with one fixed
"Invitation unavailable" message. That outcome must not reveal whether the
Invitation exists, which Organization it belongs to, or whether it is pending,
expired, revoked, rejected, or accepted.

The only checks that may be reported before proof concern the caller's own
account: authentication (`28000`) and, for acceptance, the confirmed-email
requirement (`42501` with its own fixed message). Neither reveals anything about
the Invitation.

After valid proof, the lifecycle outcome may be reported distinctly:

| State after proof | Acceptance result |
| --- | --- |
| pending and acceptable | Membership established |
| expired | rejected as expired |
| revoked | rejected as revoked |
| caller already has an active Membership in the Organization | rejected as already a Member; no second Membership |
| rejected, bound to another User, or carrying responsibilities no longer valid | rejected as unavailable |

This is the documented exception to the Organization-first ordering of the
other Staff operations: a bearer-secret operation has no Organization
capability to check, so proof takes that place in the ordering.

---

### BR-21 — Lost-response retry by the same User resolves as success

Successful acceptance erases the stored secret digest. A repeated acceptance
cannot therefore re-verify the secret.

If the Invitation has already been accepted, and the Membership established
from it belongs to the current authenticated User and is still active, a
repeated acceptance resolves as success and reports the existing Membership
(`ALREADY_ACCEPTED`). It creates nothing.

That proof uses the stored acceptance provenance (the Membership's originating
Invitation and its User). It is available only to that same User. For any other
User, the accepted Invitation produces the uniform pre-proof failure of BR-20.

If the Membership established from the Invitation has since ended, a repeated
acceptance is not success; it produces the uniform failure. The ended
Membership is never reactivated (`SPEC-ORG-004` BR-15).

First acceptance always requires full secret verification; this idempotency
does not weaken it.

---

### BR-22 — Invitation preview requires the same proof

An authenticated preview operation (§10) lets the recipient see what they are
accepting before accepting it. It follows the same proof rules as acceptance
(BR-18, BR-20, BR-21), except that it does not require a confirmed email, so
that an authenticated User can understand an Invitation before completing
email confirmation.

Preview never changes state.

---

### BR-23 — Acceptance creates no Communication

Accepting an Invitation creates no Transactional Communication and no
duplicate Invitation Communication. It does not resend or re-render the
Invitation email.

---

### BR-24 — Acceptance is serialized with revocation and expiry

Acceptance evaluates expiry and revocation under the established Organization →
Invitation → Clinic lock order (the same order revocation uses,
`SPEC-ORG-010` BR-11). Expiry is evaluated against authoritative backend time
at the acceptance instant.

The resulting Membership and every intended Responsibility Grant are created,
and the digest erased, in one atomic operation. Either all of them persist or
none does.

---

### BR-25 — Multiple-responsibility Invitations remain acceptable

Phase 1 creates Invitations with one intended responsibility
(`SPEC-ORG-002` BR-17). A legacy or trusted Invitation with several intended
responsibilities is accepted exactly as recorded: one Membership and exactly
the recorded Grants.

---

## 4. Scenarios

### Scenario: Accept a valid Organization Invitation

Given Carlos is an authenticated User
And Carlos satisfies the required account verification state
And Carlos has a pending Invitation to Animalia Veterinary Group
And the Invitation has not expired
And the Invitation has not been revoked
And Carlos has proven that he is the intended recipient
And the Invitation grants an allowed Organization responsibility

When Carlos accepts the Invitation

Then the Invitation becomes accepted
And an active Organization Membership is created between Carlos and Animalia Veterinary Group
And the Membership contains the responsibility defined by the Invitation
And the Membership has an effective start
And the Membership has no effective end

---

### Scenario: Acceptance does not allow responsibility escalation

Given Carlos has a valid pending Invitation to Animalia Veterinary Group
And the Invitation grants the Receptionist responsibility

When Carlos accepts the Invitation

Then Carlos receives the Receptionist responsibility
And Carlos cannot choose the Administrator responsibility during acceptance
And Carlos receives no additional Organization responsibility solely through acceptance

---

### Scenario: Invitation cannot be accepted by another User

Given Carlos is the intended recipient of a pending Invitation
And Laura is authenticated
And Laura has not proven that she is the intended recipient

When Laura attempts to accept Carlos's Invitation

Then the operation is denied
And no Organization Membership is created for Laura
And the Invitation remains unavailable for unauthorized acceptance

---

### Scenario: Expired Invitation cannot be accepted

Given Carlos has an Organization Invitation
And the Invitation has expired

When Carlos attempts to accept the Invitation

Then the operation is denied
And no Organization Membership is created
And the Invitation does not become accepted

---

### Scenario: Revoked Invitation cannot be accepted

Given Carlos has an Organization Invitation
And the Invitation has been revoked

When Carlos attempts to accept the Invitation

Then the operation is denied
And no Organization Membership is created
And the Invitation does not become accepted

---

### Scenario: Accepted Invitation cannot be accepted twice

Given Carlos has already accepted an Invitation to Animalia Veterinary Group
And the corresponding Organization Membership was successfully created

When acceptance of the same Invitation is attempted again

Then no additional Organization Membership is created
And no Organization responsibility is duplicated
And the previously established Membership remains unchanged

---

### Scenario: Acceptance does not establish Veterinarian status

Given Carlos is not a recognized Veterinarian
And Carlos has a valid Invitation containing an intended veterinary Organization responsibility

When Carlos accepts the Invitation

Then Carlos may receive the Organization responsibility represented by the Invitation
But Carlos does not become a recognized Veterinarian solely because of acceptance
And veterinary professional capabilities requiring professional qualification remain unavailable

---

### Scenario: Acceptance does not assign the User to a Clinic

Given Animalia Veterinary Group operates multiple Clinics
And Carlos has a valid Organization Invitation

When Carlos accepts the Invitation

Then Carlos becomes an Organization Member
And Carlos is not automatically assigned to any Clinic solely because of acceptance

---

### Scenario: Inviter leaves before Invitation acceptance

Given Maria validly invited Carlos to Animalia Veterinary Group
And the Invitation remains pending and valid
And Maria later ends her Membership in Animalia Veterinary Group
And the Invitation has not been revoked

When Carlos accepts the Invitation

Then the Invitation may still be accepted
And Carlos's Organization Membership is created according to the Invitation
And Maria's current Membership state does not retroactively invalidate the Invitation

---

### Scenario: Recipient authenticates with a different identifier

Given an Invitation was delivered to Carlos's professional email address
And Carlos already has a domain User using another authentication identifier
And Carlos proves control of the intended Invitation recipient

When Carlos accepts the Invitation

Then the existing Carlos domain User receives the Organization Membership
And no second domain User is created

---

### Scenario: Membership creation fails during acceptance

Given Carlos has a valid pending Invitation

When the system cannot establish the required Organization Membership

Then the acceptance operation fails
And the Invitation must not be considered successfully accepted
And the system must not expose a partial professional relationship

---

### Scenario: User already belongs to another Organization

Given Dr. Garcia has an active Membership in Animalia Veterinary Group
And Dr. Garcia has a valid pending Invitation to VetCare Group
And the VetCare Invitation satisfies all acceptance requirements

When Dr. Garcia accepts the VetCare Invitation

Then an active Membership in VetCare Group is created
And Dr. Garcia's Animalia Membership remains active
And the two Memberships remain independent
And capabilities derived from Animalia remain scoped to Animalia
And capabilities derived from VetCare remain scoped to VetCare

---

### Scenario: Invitation reference without the secret proves nothing

Given Laura knows the id of a pending Animalia Invitation
And Laura does not have its secret

When Laura previews or accepts the Invitation with a guessed secret

Then the operation fails with the uniform "Invitation unavailable" outcome
And Laura cannot tell whether the Invitation exists or is pending, expired,
revoked, or accepted

---

### Scenario: Different signed-in email may accept with the secret

Given an Invitation was sent to carlos.work@example.com
And Carlos is signed in as carlos.personal@example.com with a confirmed email
And Carlos holds the Invitation secret from the email link

When Carlos previews the Invitation

Then the preview shows `c***@example.com`
And reports that the invited address differs from the signed-in account

When Carlos explicitly confirms and accepts

Then the Membership is established for Carlos's existing domain User

---

### Scenario: Lost acceptance response is reconciled for the same User

Given Carlos accepted the Invitation and the response was lost

When Carlos repeats the acceptance

Then the outcome is `ALREADY_ACCEPTED` with the same Membership
And no second Membership or Grant is created

---

### Scenario: Another User cannot replay an accepted Invitation

Given Carlos accepted the Invitation
And Laura obtained the same link

When Laura attempts to accept it

Then the operation fails with the uniform "Invitation unavailable" outcome

---

### Scenario: Unconfirmed account cannot accept

Given Carlos is authenticated but has not confirmed his email address

When Carlos attempts to accept a valid Invitation

Then acceptance is rejected as requiring a confirmed email
And no Membership is created
And Carlos may still preview the Invitation

---

## 5. Edge Cases

### Existing active Membership

If the intended recipient already has an active Membership in the same Organization, acceptance must not create a duplicate active Membership.

Changing responsibilities on an existing Membership is outside this Specification.

---

### Invitation becomes invalid during acceptance

Invitation validity must be evaluated as part of the acceptance operation.

The system must not successfully create a Membership from an Invitation that is no longer valid when acceptance is processed.

---

### Responsibility is no longer valid

If a responsibility referenced by a pending Invitation is no longer valid for assignment when acceptance occurs, the system must not silently replace it with another responsibility.

The Invitation must not produce an unintended set of capabilities.

The exact replacement or re-invitation workflow may be specified separately.

---

### Different authentication identifier

The authentication identifier used by the recipient may differ from the contact address to which the Invitation was delivered.

This must not require creation of a duplicate User.

---

## 6. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-004 — Veterinarian identity is Organization-independent.**
* **INV-006 — Organization Membership is temporal.**
* **INV-011 — Professional qualification does not imply medical access.**

---

## 7. Dependencies

* SPEC-ID-001 — Register User
* SPEC-ID-002 — Verify Email Address
* SPEC-ID-003 — Authenticate User
* SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
* SPEC-ORG-002 — Invite User to Organization
* SPEC-ORG-009 — View Organization Staff
* SPEC-ORG-010 — Revoke Organization Invitation
* SPEC-COM-001 — Send Transactional Email

---

## 8. Out of Scope

This Specification does not define:

* rejecting or declining an Organization Invitation (deferred; Phase 1 offers
  only a local "Not now" that changes no domain state);
* revoking an Organization Invitation (`SPEC-ORG-010`);
* iOS universal-link delivery of the Invitation link (deferred);
* resending Invitation communication;
* creating a replacement for an expired Invitation;
* modifying Membership responsibilities after acceptance;
* ending an Organization Membership;
* Organization ownership transfer;
* assigning the User to a Clinic;
* creating a Veterinarian Professional Profile;
* verifying veterinary credentials;
* arbitrary per-member custom permissions;
* custom Organization-defined roles or permission sets.

---

## 9. Verification Notes

Verification must demonstrate that:

1. the intended recipient can accept a valid pending Invitation;
2. successful acceptance creates exactly one active Organization Membership;
3. Membership responsibilities correspond to the accepted Invitation;
4. the recipient cannot escalate responsibilities during acceptance;
5. expired or revoked Invitations cannot be accepted;
6. an Invitation cannot be successfully accepted more than once;
7. unauthorized Users cannot accept another person's Invitation;
8. acceptance and Membership creation behave atomically;
9. acceptance does not establish veterinary qualification;
10. acceptance does not create Clinic Assignments;
11. an inviter leaving the Organization does not retroactively invalidate an otherwise valid Invitation;
12. acceptance can use an existing domain User even when their authentication identifier differs from the Invitation destination.
13. an active Membership in another Organization does not prevent acceptance of
    a valid Invitation;
14. Memberships in different Organizations remain independent and
    Organization-scoped;
15. acceptance does not require Commercial Onboarding or a Subscription held
    by the accepting User, and does not create or transfer a Subscription.

---

## 10. Invitation preview contract

Staff access lifecycle Phase 1, Slice B2 (`SPEC-ORG-009` §2).

### Operation

    preview_organization_invitation(
        p_invitation_id uuid,
        p_acceptance_secret text
    ) returns jsonb

- executable only by `authenticated`; `SECURITY DEFINER`; empty
  `search_path`; `STABLE`; writes nothing; takes no row lock;
- does not require a confirmed email (BR-22);
- requires no Entitlement or Subscription.

### Evaluation order

1. Authentication — otherwise `28000`.
2. Same-User provenance — if a Membership was established from the Invitation,
   it belongs to the caller, and it is active, the state is `ACCEPTED_BY_YOU`
   (BR-21).
3. Proof — the Invitation exists and still has a stored digest, and the
   SHA-256 digest of the exact UTF-8 secret string equals it. Otherwise the
   uniform `42501` "Invitation unavailable" failure (BR-20). A malformed
   secret is treated as a wrong secret.
4. Lifecycle state, evaluated at one instant of authoritative backend time.

### Payload

```text
{
  "invitation_id": uuid,
  "state": "PENDING" | "EXPIRED" | "REVOKED" | "ALREADY_MEMBER"
         | "ACCEPTED_BY_YOU" | "UNAVAILABLE",
  "organization_display_name": text | null,
  "responsibilities": [
    {
      "responsibility": "ADMINISTRATOR" | "RECEPTIONIST" | "VETERINARIAN",
      "scope_type": "ORGANIZATION" | "CLINIC",
      "clinic": null | { "clinic_id": uuid, "clinic_display_name": text | null }
    }
  ],
  "masked_recipient_email": text | null,
  "invited_email_matches_current_account": boolean | null,
  "expires_at": timestamptz | null
}
```

- `PENDING` — acceptable now by the caller.
- `EXPIRED` — `expires_at` is not later than the evaluation instant.
- `REVOKED` — revoked (`SPEC-ORG-010`).
- `ALREADY_MEMBER` — the caller already has an active Membership in the
  Organization through another Membership.
- `ACCEPTED_BY_YOU` — BR-21 provenance.
- `UNAVAILABLE` — valid proof, but the Invitation cannot be accepted for
  another reason (rejected, bound to another User, or carrying responsibilities
  no longer valid). For `UNAVAILABLE` every member other than `invitation_id`
  and `state` is `null` or empty.

`masked_recipient_email` is the Invitation's normalized recipient address with
its local part reduced to its first character followed by `***`, keeping the
full domain (for example `c***@example.com`).

`invited_email_matches_current_account` is `true` when the Invitation's
normalized recipient address equals the normalized email address of the
caller's authenticated account, otherwise `false`. Only the boolean is
returned; the caller's account address is not echoed.

The preview never returns:

- the secret, its digest, or the encrypted delivery envelope;
- the unmasked recipient address;
- the Organization id, the inviting User, or any `recipient_user_id`;
- Communication, Delivery Job, or provider information;
- any Member, Invitation, Clinic, or data of the Organization beyond the
  intended responsibilities' Clinics.

---

## 11. Authenticated acceptance contract

### Operation

    accept_my_organization_invitation(
        p_invitation_id uuid,
        p_acceptance_secret text
    ) returns jsonb

- executable only by `authenticated`; `SECURITY DEFINER`; empty
  `search_path`;
- derives the accepting domain User from the authenticated subject;
- accepts no User id, Membership id, or responsibility input (BR-19).

### Evaluation order

1. Authentication and a coherent domain User — otherwise `28000`.
2. Confirmed email on the authenticated account — otherwise `42501` with its
   own fixed message (BR-20).
3. Serialization: lock the Invitation's Organization, then the Invitation
   (BR-24). An unknown Invitation produces the uniform failure.
4. Same-User provenance (BR-21) — success with `ALREADY_ACCEPTED`, creating
   nothing.
5. Proof (BR-18) — otherwise the uniform `42501` "Invitation unavailable"
   failure.
6. Lifecycle after proof (BR-20) — expired, revoked, already a Member, or
   unavailable, each with its own fixed outcome. On any such failure nothing is
   written.
7. Lock the Clinics referenced by the intended responsibilities in id order;
   create the Membership with effective start equal to the acceptance instant,
   create exactly the intended Grants with that same effective start, and erase
   the stored digest, atomically.

### Result

```text
{
  "invitation_id": uuid,
  "organization_id": uuid,
  "membership_id": uuid,
  "outcome": "ACCEPTED" | "ALREADY_ACCEPTED"
}
```

After any acceptance failure other than authentication, the client re-runs the
preview to present the authoritative state rather than parsing failure text.

---

## 12. Mobile deep-link and authentication flow (Android, Phase 1)

### Link

The Invitation email link is:

    https://app.menizvet.com/invitations/organization/accept?invitation=<invitation_id>#secret=<secret>

The secret is carried in the URL fragment, which browsers do not send to the
web origin (`SPEC-COM-001` BR-43).

### Route

The app provides the route `/invitations/organization/accept`. It is registered
outside authenticated-only navigation, so that the link can be received while
signed out, during cold start, and while the app is running.

On Android, `https://app.menizvet.com/invitations/*` is already declared as a
verified App Link path for the app (`docs/PRODUCTION_DEPLOYMENT.md`). The route
reads the full incoming URL, including its fragment, because route parameters
alone do not carry the fragment. Correct fragment delivery on cold and warm
start must be physically validated.

### Secret handling

The client:

- reads `invitation` and `secret` from the incoming link and validates their
  basic shape (UUID reference; non-empty base64url secret). An invalid shape
  shows the generic unavailable message and stores nothing;
- stores the pending proof `{ invitation_id, secret }` in the device secure
  store (SecureStore) while authentication completes; one pending Invitation at
  a time, a newer link replacing an older one;
- removes the secret from ordinary navigation and UI state as soon as it is
  stored (it is not kept in route parameters, screen state, or history entries
  beyond the initial read);
- never logs the secret and never includes it in analytics, crash metadata,
  error reports, or user-visible diagnostic copy;
- clears the pending proof after any terminal outcome (`ACCEPTED`,
  `ALREADY_ACCEPTED`, `EXPIRED`, `REVOKED`, `ALREADY_MEMBER`, `UNAVAILABLE`, or
  the uniform failure), after "Not now", and on sign-out.

### Signed out

The screen explains, without Organization details (the preview requires
authentication), that the person has been invited to join a veterinary
organization in MenizVet, and offers **Sign in** and **Create account**.

After successful sign-in — including after registration and email confirmation
(`SPEC-ID-001`, `SPEC-ID-002`), which may happen outside the app — the app
restores the pending proof from the secure store, runs the preview, and shows
it. Registration and sign-in never accept the Invitation automatically
(`SPEC-ORG-002` §5).

### Signed in

The app runs the preview and shows the Organization name, the intended role
and scope with Clinic names, and the masked invited address. Accept is an
explicit action.

- If the account's email is not yet confirmed, Accept is unavailable and the
  screen asks the User to confirm their email first.
- If `invited_email_matches_current_account` is `false`, the screen shows the
  masked invited address, states clearly that the currently signed-in account
  is different, and requires an explicit confirmation before Accept is enabled.
  Acceptance remains allowed, because the secret is the approved proof (BR-18).

### Outcomes

- `ACCEPTED` / `ALREADY_ACCEPTED` — the app re-reads professional context
  (`SPEC-ORG-007`), selects the new Organization, and navigates to the
  Professional area. A lost acceptance response is reconciled by retrying
  acceptance (BR-21) or re-running the preview.
- `EXPIRED` — calm message that the invitation has expired and that the
  Organization can send a new one.
- `REVOKED` — calm message that the invitation is no longer valid.
- `ALREADY_MEMBER` — calm message that the account already belongs to the
  Organization, with a path to the Professional area.
- Uniform failure or `UNAVAILABLE` — calm generic "This invitation is not
  available" message, never revealing why.

"Not now" leaves the Invitation pending and changes no domain state.

### App not installed or link opened in a browser

When the link is opened without the app handling it, the browser requests
`https://app.menizvet.com/invitations/organization/accept?invitation=<id>`;
the fragment stays in the browser. A fallback page for `/invitations/*` on
`app.menizvet.com` is a deployment requirement: it must explain that the
invitation is opened in the MenizVet Android app and must not log, transmit,
or persist the fragment. It is not part of this Specification's
implementation.

### iOS

iOS universal-link delivery is not supported in Phase 1. The project's native
configuration declares no iOS associated domains, and the production runbook
places iOS out of scope. No iOS behaviour is claimed.

---

## 13. Staff Phase 1 Verification Notes

In addition to §9, verification must demonstrate that:

16. acceptance with a valid reference and secret by an authenticated,
    email-confirmed User creates exactly one active Membership and exactly the
    intended Grants, with equal effective starts;
17. the accepting User is derived from authentication; no client-supplied User
    id, Membership id, or responsibility is accepted;
18. the client-facing acceptance and preview operations are executable by
    `authenticated` only, and no client role can execute the service-role
    acceptance command;
19. a wrong secret, a malformed secret, an unknown reference, and an Invitation
    accepted by another User produce the identical uniform failure;
20. the uniform failure precedes and hides expired, revoked, rejected, and
    accepted states;
21. with valid proof, expired, revoked, already-a-Member, and unavailable
    states are reported and nothing is written;
22. an authenticated User without a confirmed email cannot accept, but can
    preview;
23. an account whose email differs from the recipient address can accept with
    a valid secret, and the preview reports
    `invited_email_matches_current_account = false`;
24. a lost-response retry by the same User returns `ALREADY_ACCEPTED` with the
    same Membership and creates nothing;
25. a replay of an accepted Invitation by a different User fails uniformly;
26. a replay after the resulting Membership ended fails uniformly and does not
    reactivate it;
27. a failure while creating any intended Grant leaves no Membership, no Grant,
    and the Invitation still pending with its digest;
28. acceptance racing revocation, and acceptance at the expiry boundary, each
    produce one coherent outcome;
29. two concurrent acceptances produce one Membership;
30. acceptance creates no Communication;
31. the preview masks the recipient address as specified, writes nothing, and
    never returns the secret, digest, Organization id, or unmasked address;
32. the mobile route works signed out, cold, and warm; restores the pending
    proof after sign-in and registration; requires explicit Accept; requires an
    additional confirmation for a different signed-in email; and never
    auto-accepts;
33. the mobile client never logs the secret or keeps it in route or screen
    state, and clears it after terminal outcomes and on sign-out.

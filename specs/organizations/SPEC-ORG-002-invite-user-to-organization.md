# SPEC-ORG-002 — Invite User to Organization

**Status:** APPROVED
**Requirements:** REQ-ORG-002, REQ-ORG-005, REQ-ORG-006
**Domain:** Organizations
**Priority:** P0

## 1. Intent

Allow an authorized Organization Member to invite another person to establish a professional relationship with a Veterinary Organization.

Sending an invitation does not immediately create an active Organization Membership.

The invited person must explicitly accept the invitation before the professional relationship becomes active.

---

## 2. Preconditions

* The Veterinary Organization exists.
* The acting User is authenticated.
* The acting User satisfies any account verification requirement applicable to Organization administration.
* The acting User has an active Organization Membership whose assigned
responsibilities grant the capability to invite Organization members.
* The invitation identifies the intended recipient.
* The requested Organization responsibility is one the acting User is authorized to grant.

---

## 3. Business Rules

### BR-1 — Invitation requires the corresponding Organization capability

A User may invite another person to an Organization only when they have
an active Organization Membership whose assigned responsibilities grant
the capability to invite Organization members.

Authentication or Organization Membership alone is not sufficient.

Membership or responsibilities in another Organization do not grant this
capability in the target Organization.

---

### BR-2 — Invitation does not create an active Membership

Creating an Organization Invitation must not create an active Organization Membership for the recipient.

Membership becomes active only through the applicable acceptance workflow.

---

### BR-3 — Invitation is Organization-specific

An invitation belongs to exactly one Veterinary Organization.

An invitation to one Organization must not grant Membership or capabilities in another Organization.

---

### BR-4 — Invitation identifies the intended recipient

An Organization Invitation must be bound to the person or contact identity for which it was created.

Another User must not be able to accept the invitation merely because they have access to the invitation reference.

The exact technical mechanism used to bind an invitation to its recipient is an architectural concern.

---

### BR-5 — Invitation declares the intended responsibility

The invitation must identify the Organization responsibility or responsibilities that are intended to be granted if the invitation is accepted.

No Organization capability is granted while the invitation remains pending.

---

### BR-6 — Existing Users and people without an account may be invited

The invitation model must support inviting:

* an existing User;
* a person who does not yet have a platform account.

A person who does not yet have an account must complete the required Identity workflow before they can accept the invitation and establish an active Membership.

---

### BR-7 — Invitation does not imply veterinary qualification

Being invited with a veterinary Organization responsibility does not itself establish that the recipient is a recognized Veterinarian.

Organization Membership and veterinary professional qualification are separate concepts.

---

### BR-8 — Invitation does not imply Clinic Assignment

An Organization Invitation concerns the relationship with the Veterinary Organization.

Acceptance must not automatically assign the recipient to every Clinic operated by the Organization.

Clinic Assignment is a separate domain relationship and must be governed by separate Specifications.

---

### BR-9 — Duplicate active relationships must not be created

The system must not create a new invitation that would result in an unintended duplicate of an existing active Membership for the same User and Organization.

The exact behavior for changing responsibilities of an existing Member must be defined separately.

---

### BR-10 — Pending invitations must have an explicit lifecycle

An Organization Invitation must have a state that allows the system to distinguish at least between:

* pending;
* accepted;
* rejected;
* no longer valid.

The exact state model and invalidation rules may be refined by dedicated Specifications.

---

### BR-11 — Invitations must not remain valid indefinitely by assumption

The domain must support invitations becoming invalid.

The exact validity duration must be established by product or security requirements before implementation.

---

### BR-12 — Invitation capability does not imply unrestricted delegation

Having the capability to invite Organization members does not imply the
ability to grant every Organization responsibility.

The acting User must also be authorized to grant each responsibility
included in the Invitation.

A User must not be able to obtain or delegate additional Organization
capabilities indirectly through an Invitation they are not authorized
to issue.

---

### BR-13 — Owner responsibility is not granted through standard invitations

The Organization Owner responsibility must not be granted through the
standard Organization Invitation workflow.

Changes to Organization ownership require a dedicated Specification.

---

### BR-14 — Invitations have finite validity

An Organization Invitation must have a finite validity period.

When the Invitation is created, its expiration time must be determined
according to the applicable Invitation validity policy.

An expired Invitation must no longer be usable to establish an Organization
Membership.

The validity policy is fixed by BR-18: an Organization Invitation expires
exactly 7 days after its creation, as determined by the trusted backend.

---

### BR-15 — Pending Invitations are revocable

A pending Organization Invitation must be capable of being revoked before
acceptance.

Revocation requires an active Organization context with the capability to
manage Organization Invitations.

The User who originally created the Invitation does not retain special
revocation authority if they no longer have the required Organization
capability.

The revocation workflow is defined by `SPEC-ORG-010` — Revoke Organization
Invitation.

---

### BR-16 — Invitation acceptance requires proof of intended recipient

An Organization Invitation delivered to a contact address must only be
usable by a User who can prove control of the intended invitation recipient
context.

The authentication identifier used by the accepting User does not
necessarily need to be the same address to which the Invitation was sent.

Proving control of the Invitation recipient must not require creating a
second domain User.

The approved mechanism is the Invitation's bearer secret, delivered only to the
Invitation's recipient address (BR-21, `SPEC-ORG-003` BR-18).

---

### BR-17 — Phase 1 invitations carry exactly one intended responsibility

The client-facing Phase 1 invite operation (§10) creates an Invitation with
exactly one intended responsibility and scope.

The Phase 1 Staff invite form offers exactly these five combinations:

| Role | Scope |
| --- | --- |
| `ADMINISTRATOR` | Organization |
| `RECEPTIONIST` | Organization |
| `VETERINARIAN` | Organization |
| `ADMINISTRATOR` | one Clinic of the Organization |
| `RECEPTIONIST` | one Clinic of the Organization |

The Phase 1 form does not offer:

- `OWNER`, which no Invitation may grant (BR-13);
- a Clinic-scoped `VETERINARIAN`, which `SPEC-ORG-005` §4 forbids.

`VETERINARIAN` was added to the form by **Staff Responsibility Editing +
Veterinarian Enablement — Phase 1**, so that a person who joins only as a
Veterinarian does not need a fictional Administrator or Receptionist period
first. An Invitation intending `VETERINARIAN`:

- is Organization-scoped and carries no Clinic;
- creates no Veterinarian Professional Profile, credential, or Clinic
  Assignment at invitation or at acceptance (BR-7, BR-8);
- is accepted exactly as any other Invitation (`SPEC-ORG-003`); acceptance
  establishes the Membership and the `VETERINARIAN` Grant only. The recipient
  then creates their own Professional Profile (`SPEC-VET-001` §13) and an
  administrator establishes Clinic Assignments (`SPEC-VET-004` §13).

Adding `VETERINARIAN` to an existing Member follows `SPEC-ORG-006` §14.

The backend continues to accept every Invitation shape valid under
`SPEC-ORG-005`, including legacy multi-responsibility Invitations. Existing
Invitations of any valid shape remain valid.

The client never sends an arbitrary array of intended responsibilities; it
sends one responsibility, one scope, and a Clinic id only when Clinic-scoped.
The trusted backend derives the stored intended-responsibility facts from those
inputs.

---

### BR-18 — Invitation validity is exactly 7 days, determined by the backend

An Organization Invitation expires exactly 7 days after its creation:

    expires_at = created_at + 7 days

- `created_at` is a single creation instant fixed by trusted backend code from
  authoritative server time when the Invitation is created.
- `expires_at` is derived from that instant by trusted backend code.
- The client never chooses, proposes, shortens, or extends the expiry. A
  client-supplied expiry is not accepted.
- Expiry is evaluated against authoritative backend time, never device time.
- The duration is not configurable in Phase 1.
- An expired Invitation cannot be accepted (`SPEC-ORG-003` BR-9).
- Neither resending communication nor any other operation extends an
  Invitation's validity.

The expiry instant is also bound into the encrypted Invitation communication
envelope (`ADR-008`). The trusted creation path must therefore fix the
creation instant once and use the same derived expiry for both the stored
Invitation and the envelope's authenticated context. How that single instant is
established across the trusted Edge boundary and the database command is an
implementation concern; the stored relationship `expires_at = created_at + 7
days` is not.

---

### BR-19 — One pending Invitation per Organization and recipient address

At most one pending Organization Invitation may exist for the same Organization
and the same normalized recipient email address, regardless of the intended
responsibility.

The recipient address is normalized by trimming surrounding whitespace and
comparing case-insensitively.

Creating another Invitation while an equivalent one is pending fails with a
calm conflict outcome. No silent duplicate Invitation is created and the
existing Invitation is not modified.

Once the earlier Invitation is no longer pending — revoked (`SPEC-ORG-010`),
expired, accepted, or rejected — a new Invitation for the same address may be
created. The new Invitation is a separate domain entity with its own creation
time, expiry, and secret.

To change the intended role or scope of a pending Invitation, the
administrator revokes it and creates a new one.

---

### BR-20 — Already-active Members and former Members

A former Member, whose earlier Membership in the Organization has ended, may be
invited again. Acceptance establishes a new Membership (`SPEC-ORG-004` BR-15).

An existing active Member cannot meaningfully be invited again (BR-9). Because a
Phase 1 Invitation is addressed to an email address and the client supplies no
recipient User, the backend cannot always determine at creation time whether
the address belongs to an active Member. Reconciliation is defined as follows:

- creation fails with the same calm conflict outcome as BR-19 when an active
  Member of the Organization joined through an Invitation addressed to the same
  normalized email address (administrative Invitation context only; no
  authentication email is consulted);
- otherwise creation succeeds; if the recipient who later presents the valid
  secret already has an active Membership in the Organization, acceptance does
  not create a second Membership and reports the already-a-Member state
  (`SPEC-ORG-003` BR-20). The pending Invitation then remains revocable by an
  administrator;
- the backend must not match the recipient address against Users'
  authentication email addresses to detect Membership, because doing so would
  link contact addresses to authentication identities.

---

### BR-21 — Invitation reference versus Invitation secret

An Organization Invitation has two distinct client-visible artifacts:

- the **Invitation reference** (`invitation_id`) — an identifier. It proves
  nothing. Possessing it grants no ability to view, accept, or learn the
  lifecycle state of the Invitation;
- the **Invitation secret** — a one-time, high-entropy bearer secret generated
  by trusted backend code when the Invitation is created, delivered only through
  the Invitation email link, and persisted only as a one-way digest (plus the
  temporary encrypted delivery envelope of `ADR-008`). Presenting the secret is
  the approved proof of control of the Invitation recipient context.

Acceptance requires both, together with an authenticated, email-confirmed
account (`SPEC-ORG-003` BR-18, BR-19).

---

### BR-22 — Fail-closed ordering for Phase 1 invitation creation

The Phase 1 invite operation evaluates, in order:

1. authentication;
2. the acting account's verification state (confirmed email);
3. target Organization and capability together — a nonexistent Organization
   and an Organization in which the acting User lacks
   `ORGANIZATION_INVITE_MEMBERS` fail identically with one `42501`-class
   outcome;
4. input validity — recipient address, responsibility, scope; for a
   Clinic-scoped responsibility a nonexistent Clinic and a Clinic of another
   Organization produce the same invalid-scope outcome;
5. lifecycle rules — equivalent pending Invitation (BR-19) and active-Member
   reconciliation (BR-20).

An unauthorized caller must not learn whether the Organization exists, which
Clinics it has, or which Invitations are pending.

---

### BR-23 — The Phase 1 client supplies no recipient User

The Phase 1 client does not send a recipient User identifier. Invitations
created through the Phase 1 workflow are addressed to an email address only
and bind no recipient User.

The client cannot know another User's identifier, and the backend must not
expose one.

---

## 4. Scenarios

### Scenario: Invite an existing User successfully

Given Maria has an active Membership in Animalia Veterinary Group
And Maria is authorized to invite Organization Members
And Carlos is an existing User
And Carlos does not have an active Membership in Animalia Veterinary Group

When Maria invites Carlos to join Animalia Veterinary Group with an allowed responsibility

Then an Organization Invitation is created for Carlos
And the invitation is associated with Animalia Veterinary Group
And the invitation records the intended responsibility
And the invitation is pending
And Carlos does not yet have an active Organization Membership
And Carlos receives no Organization capability solely because the invitation exists

---

### Scenario: Invite a person who does not yet have an account

Given Maria is authorized to invite Organization Members
And the intended recipient does not yet have a platform account

When Maria sends a valid Organization Invitation to that recipient

Then a pending Organization Invitation is created
And no domain User is created solely because the invitation was sent
And no Organization Membership is created
And the recipient may complete the required registration and verification workflow before accepting the invitation

---

### Scenario: Unauthorized Organization Member attempts to invite

Given Maria has an active Membership in Animalia Veterinary Group
And Maria's Organization responsibilities do not allow her to invite Members

When Maria attempts to invite Carlos

Then the operation is denied
And no Organization Invitation is created
And no Organization Membership is created

---

### Scenario: User from another Organization attempts to invite

Given Maria is an Owner of VetCare Group
And Maria has no Membership in Animalia Veterinary Group

When Maria attempts to invite Carlos to Animalia Veterinary Group

Then the operation is denied
And no Organization Invitation is created for Animalia Veterinary Group

---

### Scenario: Invitation does not create Membership

Given Carlos has received a pending invitation to Animalia Veterinary Group

When Carlos has not yet accepted the invitation

Then Carlos does not have an active Membership in Animalia Veterinary Group
And Carlos has no Organization capabilities resulting from the pending invitation

---

### Scenario: Invitation with veterinary responsibility does not create Veterinarian status

Given Carlos is not a recognized Veterinarian
And Maria is authorized to invite Organization Members

When Maria invites Carlos with an intended veterinary responsibility

Then the Organization Invitation may represent the intended responsibility
But Carlos does not become a Veterinarian solely because the invitation was created
And Carlos does not gain veterinary professional capabilities

---

### Scenario: Invitation does not assign Clinics

Given Animalia Veterinary Group operates multiple Clinics
And Carlos receives an Organization Invitation

When the invitation is created

Then Carlos is not automatically assigned to any Clinic solely because of the invitation

---

### Scenario: Existing active Member is invited again

Given Carlos already has an active Membership in Animalia Veterinary Group

When Maria attempts to invite Carlos to establish the same Organization relationship again

Then a duplicate active relationship must not be created
And the system must not create an invitation whose only purpose would be to duplicate that Membership

---

### Scenario: Authorized Member grants an allowed responsibility

Given Maria has an active Membership in Animalia Veterinary Group
And Maria may invite Organization Members
And Maria is authorized to grant the Veterinarian responsibility

When Maria invites Carlos with the Veterinarian responsibility

Then the Invitation is created
And the intended responsibility is Veterinarian

---

### Scenario: Member attempts to grant an unauthorized responsibility

Given Maria may invite Organization Members
And Maria is not authorized to grant the Owner responsibility

When Maria attempts to invite Carlos as Owner

Then the operation is denied
And no Invitation granting Owner responsibility is created
And Carlos receives no Organization capability

---

## 5. Edge Cases

### Recipient registers after receiving the invitation

An invitation may exist before the recipient has a platform User identity.

If the recipient later registers, the invitation must only become available to the corresponding intended identity.

Registration itself must not automatically accept the invitation.

---

### Recipient authenticates using a different identifier

A recipient may receive an Organization Invitation through one contact
address while authenticating to the platform using another supported
authentication identity.

The recipient may accept the Invitation using their existing domain User
only after proving control of the intended Invitation recipient context.

A second domain User must not be created solely because the Invitation was
sent to a different address.

---

### Multiple pending invitations

The system should avoid ambiguous duplicate pending invitations for the same intended Organization relationship.

Defined by BR-19: a newer Invitation for the same Organization and normalized
recipient address cannot coexist with a pending one. It neither replaces nor
invalidates it; creation is rejected until the earlier Invitation is revoked,
expires, or is otherwise no longer pending.

---

### Responsibility changes before acceptance

If the Organization wishes to change the intended responsibility after an invitation has been sent, the system must not silently modify an accepted or historically relevant invitation.

Intended responsibilities are immutable. In Phase 1 the pending Invitation is
revoked (`SPEC-ORG-010`) and a new Invitation is created (BR-19).

---

### Resending a pending Invitation

The product may allow an authorized Organization Member to resend the
communication associated with a still-valid pending Invitation.

Resending communication must not by itself create a second Organization
Invitation, duplicate the intended relationship, or extend the original
Invitation validity period.

If an Invitation is already expired or revoked, issuing a new Invitation is
a separate operation.

Resending is deferred and not part of Staff Phase 1. Under the current
Communications design the Invitation secret is erased from its delivery
envelope once the email provider accepts the message (`SPEC-COM-001` BR-44), so
a resend workflow would require its own Specification. In Phase 1 the
administrator revokes the pending Invitation and creates a new one.

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
* SPEC-ORG-009 — View Organization Staff
* SPEC-ORG-010 — Revoke Organization Invitation
* SPEC-COM-001 — Send Transactional Email

---

## 8. Out of Scope

This Specification does not define:

* accepting an Organization Invitation;
* rejecting an Organization Invitation;
* the workflow for revoking a pending Invitation (defined by `SPEC-ORG-010`);
* resending an Invitation (deferred);
* changing an existing Member's responsibilities;
* ending an Organization Membership;
* creating a Veterinarian Professional Profile;
* verifying veterinary credentials;
* assigning a professional to a Clinic;
* Organization ownership transfer;
* Organization subscription behavior;
* the email delivery mechanism used to communicate the Invitation.
* arbitrary per-member custom permissions;
* custom Organization-defined roles or permission sets;

---

## 9. Verification Notes

Verification must demonstrate that:

1. an authorized Organization Member can create an Invitation;
2. an unauthorized User cannot create an Invitation;
3. an Invitation is scoped to one Organization;
4. creating an Invitation does not create an active Membership;
5. an Invitation may target an existing User or a person who has not registered yet;
6. an Invitation does not create a domain User;
7. veterinary responsibility in an Invitation does not establish professional qualification;
8. an Invitation does not automatically create Clinic Assignments;
9. an existing active Organization relationship is not duplicated;
10. no Organization capabilities are granted until the required acceptance workflow succeeds.

---

## 10. Staff Phase 1 invite contract

This section defines the Phase 1 client-facing invite workflow (Staff access
lifecycle Phase 1, Slice B1; `SPEC-ORG-009` §2).

### Operation

Invitation creation must generate the Invitation secret and its encrypted
delivery envelope with deployment key material (`ADR-008`), so the client-facing
operation remains the trusted Communications Edge route
`create-organization-invitation`, which calls the atomic
Invitation-plus-Communication database command. The client never calls the
database command directly and never uses `service_role`.

Phase 1 request (JSON object; members not listed are rejected as invalid):

```text
{
  "organization_id": uuid,
  "recipient_email": text,
  "responsibility": "ADMINISTRATOR" | "RECEPTIONIST" | "VETERINARIAN",
  "scope_type": "ORGANIZATION" | "CLINIC",
  "clinic_id": uuid | null
}
```

- `clinic_id` is required for `CLINIC` scope and must be `null` or absent for
  `ORGANIZATION` scope.
- The client does not send `expires_at`, `recipient_user_id`, a Membership id,
  or an `intended_responsibilities` array.
- The trusted backend derives the single intended-responsibility fact, the
  creation instant, and `expires_at = created_at + 7 days` (BR-18).

Response on success: `{ "invitation_id": uuid }` with HTTP `201`. The response
never contains the secret.

Outcome classes for the client:

| Outcome | Meaning |
| --- | --- |
| `201` | Invitation created and its email handed to the durable Communications outbox |
| `401` | not authenticated |
| `403` | acting account unverified, or the Organization is nonexistent or not manageable by the caller (indistinguishable, BR-22) |
| `400` | invalid recipient address, responsibility, scope, or Clinic (a nonexistent Clinic and a Clinic of another Organization are indistinguishable) |
| `409` | an equivalent pending Invitation exists, or the address belongs to an active Member who joined by Invitation (BR-19, BR-20) |

The currently deployed route accepts `intended_responsibilities`,
`expires_at`, and `recipient_user_id` from the caller and validates input before
capability. The Phase 1 implementation replaces that client-facing contract
with this one; the underlying database command continues to accept every valid
Invitation shape for trusted callers (BR-17).

### Mobile presentation

The invite form, reached from the Staff screen of the route Organization
(`SPEC-ORG-009` §7), collects:

- recipient email;
- one role: Administrator, Receptionist, or Veterinarian;
- scope: whole Organization, or one Clinic of the route Organization; for
  Veterinarian the scope is fixed to the whole Organization and no Clinic
  selector is shown;
- the Clinic, chosen from the route Organization's Clinics, when Clinic-scoped.

The form does not offer Owner or a Clinic-scoped Veterinarian, does not show or
accept an expiry, does not accept a recipient User, and collects no Clinic
Assignment.

The form may explain that the invitation link is valid for 7 days. Any expiry
shown afterwards comes from the backend read (`SPEC-ORG-009` BR-7), never from
device arithmetic.

After `201`, after `409`, and after an apparent lost response the client
re-reads `get_organization_staff`. A lost response must not be blindly retried
as a new creation: the re-read shows whether the Invitation exists, and
BR-19 prevents a duplicate if the user submits again.

`409` is presented calmly, for example "There is already a pending invitation
for this address" with the option to revoke it from the pending list.

---

## 11. Staff Phase 1 Verification Notes

In addition to §9, verification must demonstrate that:

11. each of the five Phase 1 combinations (Organization Administrator,
    Organization Receptionist, Organization Veterinarian, Clinic
    Administrator, Clinic Receptionist) creates an Invitation with exactly one
    intended responsibility of that role and scope;
12. a Clinic-scoped request for a nonexistent Clinic and for a Clinic of
    another Organization fail identically as invalid scope;
13. a Clinic-scoped `VETERINARIAN` and any `OWNER` request are rejected;
14. the stored `expires_at` equals the stored `created_at` plus exactly 7 days;
15. a client-supplied expiry is not accepted and cannot influence the stored
    expiry;
16. a second Invitation for the same Organization and normalized address
    while one is pending fails with the conflict outcome and creates nothing,
    including when the address differs only in case or surrounding whitespace;
17. after revocation or expiry of the earlier Invitation, a new Invitation for
    the same address may be created;
18. a former Member may be invited again;
19. an address that an active Member joined through is rejected with the
    conflict outcome;
20. an active Member invited through a different address is reconciled at
    acceptance as already a Member, with no second Membership;
21. a nonexistent Organization and an inaccessible Organization fail
    identically, before any input validation is reported;
22. an unverified acting account is rejected;
23. the Phase 1 request rejects `recipient_user_id`, `expires_at`, and
    `intended_responsibilities` members;
24. the Phase 1 mobile form offers neither Owner nor a Clinic-scoped
    Veterinarian; it offers Organization-scoped Veterinarian with no Clinic
    selector;
25. two concurrent creations for the same Organization and address produce
    exactly one pending Invitation;
26. the response never contains the Invitation secret or digest;
27. the Invitation reference alone grants no preview or acceptance
    (`SPEC-ORG-003`);
28. accepting an Organization-scoped `VETERINARIAN` Invitation establishes the
    Membership and the `VETERINARIAN` Grant and creates no Professional
    Profile, credential, or Clinic Assignment.

# SPEC-ORG-010 — Revoke Organization Invitation

**Status:** APPROVED
**Requirements:** REQ-ORG-002, REQ-ORG-005, REQ-ORG-006
**Domain:** Organizations
**Priority:** P1

## 1. Intent

Allow an authorized Organization administrator to revoke a pending
Organization Invitation before it is accepted, so that a mistaken, outdated,
or no-longer-wanted Invitation can no longer establish a Membership.

`SPEC-ORG-002` BR-15 requires pending Invitations to be revocable. This
Specification defines that workflow.

Revocation also unblocks re-inviting: while an equivalent pending Invitation
exists, a new one cannot be created (`SPEC-ORG-002` BR-9, BR-19), and the
original Invitation credential cannot be re-sent once delivered
(`SPEC-COM-001` BR-44). Without revocation an administrator would have to wait
for the 7-day expiry.

This Specification is part of Staff access lifecycle Phase 1, Slice B1
(`SPEC-ORG-009` §2).

---

## 2. Preconditions

- The acting User exists and is authenticated.
- The target Organization Invitation exists.
- The acting User currently holds `ORGANIZATION_REVOKE_INVITATIONS` in the
  Invitation's Veterinary Organization.

---

## 3. Business Rules

### BR-1 — Canonical operation

Revocation is performed by the authenticated trusted operation

    revoke_organization_invitation(p_invitation_id uuid) returns jsonb

returning exactly:

```text
{
  "invitation_id": uuid,
  "outcome": "REVOKED" | "ALREADY_REVOKED" | "ACCEPTED" | "EXPIRED" | "REJECTED"
}
```

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. The acting User is derived from the authenticated subject; the
client supplies only the Invitation id.

---

### BR-2 — Revocation requires the existing revocation capability

The acting User must currently hold `ORGANIZATION_REVOKE_INVITATIONS` in the
Organization that owns the Invitation, evaluated by the authoritative
Organization-capability evaluation (`SPEC-ORG-005`).

No new capability is introduced. Under the Phase 1 mapping the capability is
held only by an active Organization-scoped `OWNER` or `ADMINISTRATOR`.
Clinic-scoped Administrators, Receptionists, Veterinarians, bare Membership,
and Members of other Organizations cannot revoke.

The User who created the Invitation has no special revocation authority. If
they no longer hold the capability they cannot revoke it, and any other current
holder can (`SPEC-ORG-002` BR-15).

---

### BR-3 — Fail-closed authorization ordering

The operation evaluates, in order:

1. authentication — an unauthenticated caller fails with `28000`;
2. target resolution and capability together — a nonexistent Invitation and
   an Invitation in an Organization where the acting User lacks
   `ORGANIZATION_REVOKE_INVITATIONS` fail identically with SQLSTATE `42501` and
   one fixed message;
3. lifecycle state (BR-4–BR-7), reported only to an authorized caller.

An unauthorized caller must not learn whether the Invitation exists, which
Organization it belongs to, or whether it is pending, revoked, accepted,
rejected, or expired.

---

### BR-4 — A pending Invitation becomes revoked

When the Invitation is pending at the revocation instant — not revoked, not
rejected, not accepted, and the revocation instant earlier than its
`expires_at` — the operation records:

- the revocation instant (authoritative backend time);
- the acting User as the revoking User,

using the Invitation's existing revocation facts, and returns
`outcome = "REVOKED"`.

Revocation preserves the Invitation and its intended responsibilities as
history. Nothing is deleted.

---

### BR-5 — Revocation is evaluated under current state

The pending check of BR-4 is made against the Invitation's state after the
operation has serialized with concurrent acceptance and revocation (BR-11), not
against a state the client previously read.

---

### BR-6 — Revoking again is a safe no-op

If the Invitation is already revoked, the operation changes nothing and returns
`outcome = "ALREADY_REVOKED"`.

The original revocation instant and revoking User are never overwritten, even
when a different authorized User retries.

This makes revocation safe to retry after a lost response.

---

### BR-7 — Accepted, expired, and rejected Invitations are not transformed

- An Invitation that has already been accepted is not revoked. The operation
  changes nothing and returns `outcome = "ACCEPTED"`. The resulting Membership
  and its Grants are unaffected; ending access is `SPEC-ORG-004`.
- An Invitation whose `expires_at` is not later than the revocation instant is
  already non-accepting. The operation changes nothing and returns
  `outcome = "EXPIRED"`. (The persisted model allows revocation only before
  expiry.)
- An Invitation that carries a rejection fact (legacy or future workflow) is
  not revoked. The operation changes nothing and returns
  `outcome = "REJECTED"`.

None of these outcomes is an error. The client re-reads staff state
(`SPEC-ORG-009`) after every outcome.

---

### BR-8 — A revoked Invitation cannot be accepted

After revocation, acceptance of the Invitation fails with its revoked
presentation state, even with a valid Invitation secret (`SPEC-ORG-003` BR-10,
BR-20).

---

### BR-9 — Undelivered Invitation communication is suppressed

A revoked Invitation's Transactional Communication is no longer eligible for
delivery. If the Invitation email has not yet been handed to the email
provider, it is not sent.

An email already accepted by the provider cannot be recalled. Its link remains
unusable because acceptance rejects the revoked Invitation (BR-8).

Revocation creates no new Communication. Phase 1 sends no "your invitation was
revoked" email.

---

### BR-10 — Revocation does not change other state

Revocation must not:

- create, end, or modify any Organization Membership or Responsibility Grant;
- modify other Invitations;
- delete the Invitation or its intended responsibilities;
- restore or replace the Invitation's acceptance credential.

The Invitation's acceptance-secret digest is retained on revocation, so that a
recipient holding a valid secret is shown the revoked state rather than a
generic failure (`SPEC-ORG-003` BR-20). The digest is a one-way value and grants
nothing after revocation.

---

### BR-11 — Concurrency and lock order

Revocation serializes with acceptance and with other revocations of the same
Invitation using the established Organization → Invitation lock order (the same
order acceptance uses).

Consequently:

- revocation and acceptance racing for the same pending Invitation produce
  exactly one winner: either the Invitation becomes revoked and acceptance then
  fails, or the Membership is established and revocation then reports
  `ACCEPTED`;
- two concurrent revocations produce one `REVOKED` and one `ALREADY_REVOKED`,
  with a single recorded revocation instant and revoking User.

---

### BR-12 — A new Invitation may follow revocation

Once an Invitation is revoked it is no longer pending. A new Invitation for the
same recipient may then be created through `SPEC-ORG-002`, subject to its
ordinary rules. The new Invitation is a separate domain entity with its own
creation time, 7-day expiry, and secret.

---

## 4. Scenarios

### Scenario: Administrator revokes a pending Invitation

Given Animalia has a pending Invitation for laura@example.com
And Maria holds Organization-scoped `ADMINISTRATOR` in Animalia

When Maria revokes the Invitation

Then the outcome is `REVOKED`
And the Invitation records the revocation instant and Maria as revoking User
And the Invitation no longer appears as pending staff state
And no Membership is created

---

### Scenario: Retry after a lost response

Given Maria revoked the Invitation but the response was lost

When Maria retries the revocation

Then the outcome is `ALREADY_REVOKED`
And the original revocation instant and revoking User are unchanged

---

### Scenario: Accept after revoke is rejected

Given the Invitation for laura@example.com has been revoked
And Laura holds the valid Invitation secret

When Laura attempts to accept the Invitation

Then acceptance fails with the revoked state
And no Membership is created

---

### Scenario: Revoke after accept does not change the Membership

Given Laura has already accepted the Invitation
And Laura's Membership is active

When Maria attempts to revoke the Invitation

Then the outcome is `ACCEPTED`
And the Invitation is not marked revoked
And Laura's Membership and Grants are unchanged

---

### Scenario: Expired Invitation is reported, not revoked

Given the Invitation's expiry has passed

When Maria attempts to revoke it

Then the outcome is `EXPIRED`
And no revocation fact is recorded

---

### Scenario: Unauthorized caller cannot learn about the Invitation

Given Pedro holds `ADMINISTRATOR` scoped only to Madrid Centro

When Pedro attempts to revoke an Animalia Invitation

Then the operation fails with SQLSTATE `42501`
And the failure is identical to revoking an Invitation id that does not exist

---

### Scenario: Member of another Organization is denied

Given Maria owns VetCare Group and has no Animalia Membership

When Maria attempts to revoke an Animalia Invitation

Then the operation fails with the same `42501` outcome

---

### Scenario: Inviter who lost capability cannot revoke

Given Lucia created the Invitation while she was an Organization Administrator
And Lucia's `ADMINISTRATOR` Grant has since ended

When Lucia attempts to revoke it

Then the operation fails with the same `42501` outcome
And the Invitation remains pending

---

### Scenario: Undelivered email is suppressed

Given the Invitation email has not yet been handed to the email provider

When Maria revokes the Invitation

Then the Invitation email is not delivered

---

### Scenario: Revoke and accept race

Given Laura submits a valid acceptance
And Maria concurrently revokes the same pending Invitation

When both operations complete

Then exactly one of the following holds:
- the Invitation is revoked and no Membership exists; or
- a Membership exists from the Invitation and the revocation outcome is
  `ACCEPTED`

---

### Scenario: Re-invite after revocation

Given the Invitation for laura@example.com has been revoked

When Maria creates a new Invitation for laura@example.com

Then the new Invitation is created with its own 7-day expiry

---

## 5. Mobile presentation

On the Staff screen (`SPEC-ORG-009` §7), each pending Invitation row offers
**Revoke invitation / Revocar invitación**.

- The action requires an explicit confirmation naming the recipient email and
  stating that the invitation link will stop working.
- On `REVOKED` or `ALREADY_REVOKED`, a calm success message is shown.
- On `ACCEPTED` or `EXPIRED`, a calm explanatory message is shown (for example
  "This invitation was already accepted" / "This invitation had already
  expired").
- After every outcome, and after an apparent lost response, the client
  re-reads `get_organization_staff`; the re-read is authoritative.
- On `42501`, the client treats Staff access as lost (`SPEC-ORG-009` §7).

There is no recipient-side Decline action; declining is deferred.

---

## 6. Relevant Invariants

- **INV-006 — Organization Membership is temporal.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 7. Dependencies

- SPEC-ORG-002 — Invite User to Organization
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ORG-009 — View Organization Staff
- SPEC-COM-001 — Send Transactional Email

---

## 8. Out of Scope

This Specification does not define:

- recipient-side rejection or declining of an Invitation;
- resending Invitation communication;
- editing an Invitation's intended responsibility or recipient;
- revocation notification email;
- bulk revocation;
- revoking an accepted Invitation as a way of ending access (use
  `SPEC-ORG-004`);
- recalling an email already accepted by the provider.

---

## 9. Verification Notes

Verification must demonstrate that:

1. an authorized actor revokes a pending Invitation, recording the revocation
   instant and revoking User, with outcome `REVOKED`;
2. the revoked Invitation is no longer pending in `SPEC-ORG-009`;
3. a retry returns `ALREADY_REVOKED` and leaves the original revocation facts
   unchanged, including when a different authorized User retries;
4. acceptance after revocation fails, even with a valid secret, and creates no
   Membership;
5. revoking an accepted Invitation returns `ACCEPTED` and changes neither the
   Invitation nor the resulting Membership and Grants;
6. revoking an expired Invitation returns `EXPIRED` and records nothing;
7. a nonexistent Invitation and an inaccessible Invitation fail identically
   with `42501`;
8. a Clinic-scoped Administrator, a Receptionist, a Veterinarian, bare
   Membership, a Member of another Organization, and an inviter who lost the
   capability are denied;
9. an unauthenticated caller is rejected with `28000`;
10. an undelivered Invitation email is not delivered after revocation;
11. revocation creates no Communication;
12. revocation deletes nothing and does not modify Memberships, Grants, or other
    Invitations;
13. revocation and acceptance racing produce exactly one winner;
14. concurrent revocations record a single revocation;
15. a new Invitation for the same recipient may be created after revocation;
16. the mobile Revoke action requires confirmation and always re-reads staff
    state afterwards.

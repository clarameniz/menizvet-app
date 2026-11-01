# SPEC-ORG-004 — End Organization Membership

**Status:** APPROVED
**Requirements:** REQ-ORG-002, REQ-ORG-003, REQ-ORG-004, REQ-ORG-005, REQ-ORG-006, REQ-AUD-004
**Domain:** Organizations
**Priority:** P0

## 1. Intent

Allow an active Organization Membership to be ended while preserving the historical professional relationship between the User and the Veterinary Organization.

Ending a Membership removes the current Organization capabilities derived from that Membership.

It must not delete or rewrite historical information produced while the Membership was active.

---

## 2. Preconditions

* The Veterinary Organization exists.
* The target Organization Membership exists.
* The target Organization Membership is currently active.
* The acting User is authenticated.
* The acting User is either:

  * ending their own Membership where self-departure is permitted; or
  * acting within the Organization with the capability required to end the target Membership.
* Ending the Membership would not violate Organization ownership requirements.

---

## 3. Business Rules

### BR-1 — Ending a Membership preserves it historically

Ending an Organization Membership must establish an effective end for the relationship.

The Membership must not be deleted as part of the normal termination workflow.

Its historical start and end must remain identifiable.

---

### BR-2 — An ended Membership no longer grants current capabilities

Once the Membership reaches its effective end, responsibilities associated with that Membership must no longer grant current Organization capabilities.

Authentication or historical Membership alone is insufficient to continue acting within the Organization.

---

### BR-3 — Membership termination is Organization-specific

Ending a Membership in one Veterinary Organization must not affect the User's Memberships in other Organizations.

---

### BR-4 — Membership termination does not affect personal identity

Ending an Organization Membership must not:

* delete the User;
* disable the User's account;
* remove Pet Guardianship;
* remove unrelated personal capabilities.

---

### BR-5 — Membership termination does not remove veterinary professional identity

If the User is a recognized Veterinarian, ending an Organization Membership must not remove their Veterinarian Professional Profile or professional identity.

Veterinary qualification exists independently from employment or Organization Membership.

---

### BR-6 — Historical clinical provenance must remain unchanged

Ending a Membership must not modify the provenance, authorship, Clinic, Organization, or professional attribution of clinical information previously created in the valid professional context.

For example, if Dr. Garcia created a clinical record while working for Animalia Veterinary Group, that record must remain attributed to Animalia even after Dr. Garcia leaves the Organization.

---

### BR-7 — Historical Appointments must remain unchanged

Ending a Membership must not remove or rewrite historical Appointments involving the User.

The management of future Appointments assigned to a departing professional is a separate workflow.

---

### BR-8 — Clinic Assignments must no longer grant current professional authority

A User whose Organization Membership has ended must not continue exercising professional capabilities at Clinics belonging to that Organization through previously existing Clinic Assignments.

Historical Clinic Assignment information must remain preserved.

The detailed lifecycle of Clinic Assignments is defined separately.

---

### BR-9 — Ending a Membership must not affect unrelated Organizations or Clinics

Professional relationships outside the Organization whose Membership is being ended must remain unchanged.

For example, ending Maria's Membership in Animalia Veterinary Group must not affect her Membership or Clinic Assignments within VetCare Group.

---

### BR-10 — A User may leave their own Organization Membership

An active Organization Member may request to end their own Membership unless doing so would violate an Organization invariant, such as leaving the Organization without a required Owner.

Self-departure does not require the User to possess the capability used to manage other Members.

Self-departure remains approved domain behaviour but is deferred: Staff access
lifecycle Phase 1 provides no client path for it (§10, BR-22).

---

### BR-11 — Ending another User's Membership requires authorization

An Organization Member may end another User's Membership only when their active responsibilities grant the required capability.

Organization Membership alone is not sufficient.

---

### BR-12 — The Organization must retain an active Owner

Ending an Organization Membership must not leave the Veterinary Organization without at least one active Owner.

If the target Membership represents the Organization's only active ownership relationship, termination must be denied until ownership has been validly transferred or another valid Owner has been established through the dedicated ownership workflow.

Standard Membership termination must not implicitly transfer ownership.

---

### BR-13 — Standard Membership termination is immediately effective

For the behavior defined by this Specification, termination becomes effective when the operation successfully completes.

Scheduled future termination and backdated termination are outside this Specification.

---

### BR-14 — Effective end cannot precede effective start

The effective end of an Organization Membership must never precede its effective start.

---

### BR-15 — Ending a Membership is not reversible by reactivation

An ended Organization Membership represents a completed historical professional relationship and must not be reactivated as though the relationship had never ended.

If the User later rejoins the same Organization, a new Organization Membership must be established through the applicable Organization Invitation workflow.

---

### BR-16 — Only one active Membership for the same User and Organization relationship

A User must not have multiple simultaneously active Organization Memberships representing the same Organization relationship.

Historical Memberships from previous periods may coexist with one current active Membership.

Example:

```text
Maria → Animalia

Membership #1
2026-01-10 → 2027-03-31

Membership #2
2028-09-01 → active
```

This represents two distinct professional periods.

---

### BR-17 — Ending an already ended Membership must not alter history

A repeated termination attempt against an already ended Membership must not:

* overwrite its original effective end;
* create a second termination period;
* duplicate historical events;
* restore or otherwise alter the Membership.

---

### BR-18 — Membership termination and capability removal form one logical operation

The system must not expose a state in which a Membership is considered ended while capabilities derived exclusively from that Membership remain valid.

---

### BR-19 — Previously created Invitations are not retroactively invalidated solely by Membership termination

Ending the Membership of a User who previously created valid Organization Invitations must not automatically invalidate those Invitations solely because the inviter is no longer a Member.

Invitation validity continues to follow the rules defined by the Organization Invitation Specifications.

Authorized Organization Members may revoke pending Invitations through the applicable workflow.

---

## 4. Scenarios

### Scenario: Authorized Administrator ends another Member's Membership

Given Carlos has an active Membership in Animalia Veterinary Group
And Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities grant the capability to end Organization Memberships

When Maria ends Carlos's Membership

Then Carlos's Membership receives an effective end
And Carlos's historical Membership is preserved
And Carlos no longer receives current Animalia Organization capabilities from that Membership
And Carlos's User identity remains unchanged

---

### Scenario: Member leaves an Organization

Given Carlos has an active Membership in Animalia Veterinary Group
And Carlos is permitted to leave without violating an Organization invariant

When Carlos ends his own Membership

Then the Membership receives an effective end
And the historical relationship with Animalia Veterinary Group is preserved
And Carlos no longer receives Organization capabilities from that Membership

---

### Scenario: Unauthorized Member attempts to end another Membership

Given Carlos and Maria both have active Memberships in Animalia Veterinary Group
And Maria's responsibilities do not grant the capability to end other Memberships

When Maria attempts to end Carlos's Membership

Then the operation is denied
And Carlos's Membership remains active
And Carlos's Organization capabilities remain unchanged

---

### Scenario: Member of another Organization attempts termination

Given Maria is an Owner of VetCare Group
And Maria has no Membership in Animalia Veterinary Group
And Carlos has an active Membership in Animalia Veterinary Group

When Maria attempts to end Carlos's Animalia Membership

Then the operation is denied
And Carlos's Animalia Membership remains active

---

### Scenario: Sole Owner attempts to leave

Given Maria is the only active Owner of Animalia Veterinary Group
And Maria has an active Membership in Animalia Veterinary Group

When Maria attempts to end her own Membership

Then the operation is denied
And Maria's Membership remains active
And Animalia Veterinary Group retains its active Owner

---

### Scenario: Authorized Member attempts to remove the sole Owner

Given Maria is the only active Owner of Animalia Veterinary Group
And Carlos otherwise has the capability to manage Organization Memberships

When Carlos attempts to end Maria's Membership

Then the operation is denied
And Maria remains an active Owner
And no implicit ownership transfer occurs

---

### Scenario: Ending Membership preserves veterinary identity

Given Dr. Garcia is a recognized Veterinarian
And Dr. Garcia has an active Membership in Animalia Veterinary Group

When Dr. Garcia's Animalia Membership ends

Then Dr. Garcia remains a recognized Veterinarian
And the Veterinarian Professional Profile remains unchanged
And only capabilities derived from the ended Animalia Membership cease to apply

---

### Scenario: Ending Membership preserves previous clinical provenance

Given Dr. Garcia recorded a finalized clinical entry for Luna while validly practicing at Animalia Madrid Centro
And the entry identifies Dr. Garcia, Animalia Madrid Centro, and Animalia Veterinary Group as its historical provenance

When Dr. Garcia's Membership in Animalia Veterinary Group later ends

Then Luna's existing clinical entry remains unchanged
And the entry remains attributed to Dr. Garcia
And the entry remains attributed to Animalia Madrid Centro
And the entry remains attributed to Animalia Veterinary Group

---

### Scenario: Organization Membership termination affects Clinic authority

Given Dr. Garcia has an active Membership in Animalia Veterinary Group
And Dr. Garcia has a Clinic Assignment at Animalia Madrid Centro

When Dr. Garcia's Organization Membership ends

Then Dr. Garcia must no longer exercise current professional capabilities at Animalia Madrid Centro through that Organization relationship
And the historical Clinic Assignment information remains available

---

### Scenario: Membership in another Organization remains active

Given Dr. Garcia has an active Membership in Animalia Veterinary Group
And Dr. Garcia also has an active Membership in VetCare Group

When Dr. Garcia's Animalia Membership ends

Then the Animalia Membership becomes historical
And Dr. Garcia's VetCare Membership remains active
And capabilities derived from VetCare remain unaffected

---

### Scenario: User rejoins the same Organization later

Given Carlos previously had a Membership in Animalia Veterinary Group
And that Membership ended on 2027-03-31
And Carlos later accepts a new valid Organization Invitation

When Carlos rejoins Animalia Veterinary Group

Then a new active Organization Membership is established
And the previous Membership remains ended
And both professional periods remain historically identifiable

---

### Scenario: Attempt to end an already ended Membership

Given Carlos's Membership in Animalia Veterinary Group has already ended

When termination of the same Membership is attempted again

Then the original effective end remains unchanged
And no duplicate termination is created
And the historical Membership remains unchanged

---

### Scenario: Previously issued Invitation survives inviter departure

Given Maria validly created a pending Invitation for Carlos
And the Invitation remains unexpired and unrevoked

When Maria's Membership in the Organization ends

Then the Invitation is not automatically invalidated solely because Maria left
And its validity continues to be determined by the Invitation rules

---

## 5. Edge Cases

### Future Appointments

A departing professional may have future Appointments assigned to them.

Membership termination must prevent continued unauthorized professional activity, but reassignment or cancellation of those Appointments is outside this Specification.

---

### Active Clinic Assignments

A departing professional may have one or more Clinic Assignments associated with the Organization.

Such Assignments must not provide current authority after the Organization Membership ends.

Their exact termination behavior will be defined by the Clinic Assignment Specifications.

---

### Rejoining after departure

A User who rejoins an Organization establishes a new professional period.

The original Membership must remain unchanged and historical.

---

### Concurrent termination attempts

Multiple attempts to end the same Membership must not produce inconsistent effective end values or duplicated historical state.

---

### Ownership changes

A sole Owner who wishes to leave must first complete the applicable ownership workflow.

Organization Membership termination itself must not decide who the next Owner becomes.

---

## 6. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-004 — Veterinarian identity is Organization-independent.**
* **INV-006 — Organization Membership is temporal.**
* **INV-009 — Historical clinical provenance is immutable.**
* **INV-010 — Medical history follows the Pet.**
* **INV-017 — An Organization must retain an active Owner.**

---

## 7. Dependencies

* SPEC-ID-003 — Authenticate User
* SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
* SPEC-ORG-003 — Accept Organization Invitation

Organization Invitation behavior referenced by this Specification follows:

* SPEC-ORG-002 — Invite User to Organization
* SPEC-ORG-003 — Accept Organization Invitation

Staff access lifecycle Phase 1 presentation follows:

* SPEC-ORG-009 — View Organization Staff
* SPEC-VET-005 — End Veterinarian Clinic Assignment (BR-22)

---

## 8. Out of Scope

This Specification does not define:

* scheduled future Membership termination;
* backdated Membership termination;
* modifying Membership responsibilities;
* transferring Organization ownership;
* adding another Organization Owner;
* deleting or archiving an Organization;
* Clinic Assignment creation;
* the detailed Clinic Assignment termination workflow;
* reassignment of future Appointments;
* cancellation of future Appointments;
* revoking pending Organization Invitations;
* employment-law or contractual termination processes;
* disabling the User's platform account;
* removing veterinary professional qualification;
* a Phase 1 client path for self-departure (deferred, §10);
* ending an Owner's Membership through the Phase 1 Staff workflow (excluded,
  §10; ownership changes require a dedicated ownership Specification).

---

## 9. Verification Notes

Verification must demonstrate that:

1. an authorized actor can end an active Organization Membership;
2. a Member can leave their own Organization where Organization invariants permit it;
3. unauthorized Users cannot end another User's Membership;
4. termination preserves the Membership and records its effective end;
5. an ended Membership grants no current Organization capabilities;
6. termination does not delete or disable the User;
7. termination does not remove veterinary professional identity;
8. historical clinical provenance remains unchanged;
9. historical Appointments remain unchanged;
10. Clinic Assignments under the ended Organization relationship cannot continue granting current professional authority;
11. Memberships in other Organizations remain unaffected;
12. the sole active Owner cannot leave or be removed through standard Membership termination;
13. an ended Membership cannot be reactivated;
14. rejoining creates a new Membership and preserves previous professional periods;
15. repeated termination does not overwrite historical termination information;
16. previously valid Invitations are not automatically invalidated solely because their inviter leaves the Organization.

---

## 10. Staff Phase 1 end-access contract

Staff access lifecycle Phase 1, Slice C (`SPEC-ORG-009` §2). This section
narrows the general behaviour above for the Phase 1 client workflow. It does not
change BR-1–BR-19.

### BR-20 — Canonical Phase 1 operation

Ending another person's access through the Staff workflow uses the
authenticated trusted operation

    end_organization_staff_membership(p_membership_id uuid) returns jsonb

returning:

```text
{
  "membership_id": uuid,
  "effective_end": timestamptz,
  "outcome": "ENDED" | "ALREADY_ENDED"
}
```

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. The acting User is derived from the authenticated subject; the
client supplies only the Membership id.

---

### BR-21 — Capability

The acting User must currently hold `ORGANIZATION_END_MEMBERSHIPS` in the
Organization of the target Membership (`SPEC-ORG-005`). Under the Phase 1
mapping only an active Organization-scoped `OWNER` or `ADMINISTRATOR` holds it.
A Clinic-scoped Administrator, a Receptionist, a Veterinarian, bare Membership,
and a Member of another Organization cannot end access.

---

### BR-22 — No self-ending and no Owner ending in Phase 1

The Phase 1 operation rejects, for an otherwise authorized caller:

- a target Membership that belongs to the acting User (self-departure is
  deferred);
- a target Membership that holds an active `OWNER` Responsibility Grant at the
  operation instant, regardless of how many other active Owners exist.

Therefore an Organization Administrator cannot end a co-Owner through Staff,
and no Owner can be removed through Staff. Owner removal and ownership transfer
remain unspecified and require a dedicated ownership Specification. Nothing in
this section changes trusted provisioning.

---

### BR-23 — Fail-closed ordering

The operation evaluates, in order:

1. authentication — otherwise `28000`;
2. target resolution and capability together, after serializing on the
   target's Organization — a nonexistent Membership and a Membership in an
   Organization where the acting User lacks `ORGANIZATION_END_MEMBERSHIPS` fail
   identically with SQLSTATE `42501` and one fixed message;
3. self-target and Owner-target rejection (BR-22), each with its own fixed
   message;
4. lifecycle (BR-26).

An unauthorized caller must not learn whether the Membership exists, which
Organization it belongs to, whether it is active or already ended, or which
responsibilities it holds.

---

### BR-24 — Semantics

Ending a Membership through the Phase 1 operation:

- ends every active Responsibility Grant of the Membership and the Membership
  itself at the same effective instant, recording the acting User as the
  ending User for each;
- preserves every row — Membership, Grants, originating Invitation — as
  history; nothing is deleted;
- does not delete, disable, or modify the User or their User Profile;
- does not affect the User's Memberships, Grants, or Clinic Assignments in
  other Organizations;
- does not rewrite authored or historical rows (Appointment lifecycle events,
  Schedule Revisions, clinical provenance, Clinic configuration history, audit
  events);
- does not modify pending Invitations the User created (BR-19);
- does not modify Pet Guardianships or a Veterinarian Professional Profile.

---

### BR-25 — Immediate authorization loss

Organization, Clinic, Appointment, and clinical authority derived from the
Membership ends when the operation commits.

Every authorization helper evaluates live Membership and Responsibility Grant
state on each protected operation. The authentication token (JWT) supplies the
caller's identity only; it carries no Membership, responsibility, or capability
claim that authorization relies on. A still-valid JWT held by the former Member
therefore does not preserve any ended authority: their next protected
operation in the Organization is denied, with no sign-out, token refresh, or
session revocation required.

Ending access does not sign the former Member out of MenizVet and does not
affect their personal capabilities (BR-4).

Advisory client state, such as a previously loaded professional context, may
remain on the former Member's screen until refreshed; it grants nothing.

---

### BR-26 — Idempotent retry

If the target Membership has already ended, an authorized caller (BR-21,
evaluated at retry time) receives `outcome = "ALREADY_ENDED"` with the original
effective end. Nothing is changed (BR-17).

This lets an administrator reconcile a lost response. An unauthorized caller
receives the uniform `42501` failure and cannot learn that the Membership
existed or had ended.

Concurrent attempts serialize on the Organization; exactly one records the end.

---

### BR-27 — The more permissive generic operation is not a client path

The pre-existing generic operation `end_organization_membership(p_membership_id)`
permits self-departure, permits ending a non-sole Owner, and reports lifecycle
and existence before authorization. To prevent clients from reaching that more
permissive behaviour, Phase 1 withdraws client `EXECUTE` on it (from `public`,
`anon`, and `authenticated`). It may remain for trusted compatibility only.
Self-departure (BR-10) returns to clients only through a future dedicated
workflow.

---

### BR-28 — Veterinarian Clinic Assignments and Appointments

- Veterinarian Clinic Assignment rows supported by the ended Membership are not
  modified or closed; their history remains. They stop granting current
  professional authority immediately, because a current Assignment requires an
  active supporting Membership (`SPEC-VET-005` BR-22).
- Existing Appointment Veterinarian Assignments are not modified, reassigned,
  or cancelled (BR-7). Reassignment of future Appointments is a separate
  workflow.

---

### Mobile presentation

The Staff Member detail (`SPEC-ORG-009` §7) offers **End access**, labelled
**Remove from organization / Quitar de la organización**, as a secondary
action apart from the responsibility cards — except for the acting User's own
Membership and any Membership holding an active `OWNER` responsibility. The
Staff list is a summary and does not offer it.

- The action requires an explicit confirmation naming the member's display
  identity and the Organization, stating that their membership of and access to
  this Organization end immediately, that their MenizVet account is not deleted
  and other Organizations and history are not affected, and that rejoining
  requires a new invitation.
- On `ENDED` or `ALREADY_ENDED`, a calm success message is shown.
- After every outcome, and after an apparent lost response, the client
  re-reads `get_organization_staff`; the re-read is authoritative.
- On `42501`, the client treats Staff access as lost (`SPEC-ORG-009` §7).
- No role change, ownership action, or Leave Organization action is offered.

---

## 11. Staff Phase 1 Verification Notes

In addition to §9, verification must demonstrate that:

17. an Organization-scoped Owner or Administrator ends an active non-Owner
    Membership with outcome `ENDED`;
18. every active Grant and the Membership receive the same effective end and
    the acting User as ending User;
19. immediately after commit, the former Member holds no Organization, Clinic,
    or Appointment capability in that Organization, and their Veterinarian
    Clinic Assignment there is no longer current;
20. the former Member's same still-valid JWT cannot perform any protected
    operation in that Organization, with no sign-out or token refresh;
21. the former Member's Memberships and capabilities in other Organizations are
    unchanged;
22. no row is deleted and no historical or authored row is modified;
23. Veterinarian Clinic Assignment rows and Appointment Veterinarian
    Assignments are not modified;
24. a target holding an active `OWNER` Grant is rejected, both when it is the
    sole Owner and when another Owner exists;
25. the acting User's own Membership is rejected as a target;
26. a retry after the Membership already ended returns `ALREADY_ENDED` with the
    original effective end and changes nothing;
27. a nonexistent Membership and an inaccessible Membership fail identically
    with `42501`, including when the inaccessible Membership is already ended;
28. a Clinic-scoped Administrator, a Receptionist, a Veterinarian, and a Member
    of another Organization are denied;
29. concurrent end attempts record exactly one end;
30. no client role can execute the generic `end_organization_membership`;
31. the mobile Staff screen never offers End access on the caller's own row or
    on an Owner row, requires confirmation, and re-reads after every outcome.

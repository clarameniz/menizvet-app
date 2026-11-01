# SPEC-ORG-006 — Change Organization Membership Responsibilities

**Status:** APPROVED  
**Requirements:** REQ-ORG-005, REQ-ORG-006  
**Domain:** Organizations  
**Priority:** P0

## 1. Intent

Allow an authorized Organization actor to change the non-owner responsibilities
assigned to an existing active Organization Membership.

Responsibility changes must preserve historical meaning.

Changing a responsibility must not rewrite what authority the Member had before
the change.

For example:

    Carlos
    RECEPTIONIST @ Madrid Centro
        ↓ promotion
    ADMINISTRATOR @ Madrid Centro

must preserve that Carlos was previously a Receptionist and only became an
Administrator from the effective time of the change.

Organization Membership and responsibility lifecycle remain separate:

    Membership
        └── one or more responsibility grants over time

A responsibility change does not create another Membership and does not create
another domain User.

---

## 2. Preconditions

- The acting User exists.
- The acting User is authenticated.
- The target Veterinary Organization exists.
- The target Organization Membership exists.
- The target Membership is currently active.
- The acting User has a current Organization context granting capability to
  manage Organization responsibilities.
- Every requested responsibility is supported by the Phase 1 responsibility
  model.
- Every requested scope is valid for the target Organization.
- The requested change does not attempt to modify Organization ownership
  through this workflow.
- The resulting responsibility configuration does not violate an approved
  Organization invariant.

---

## 3. Responsibility Grant Lifecycle

A responsibility assignment must preserve an effective period.

Conceptually:

    Responsibility Grant
    ├── Membership
    ├── responsibility
    ├── scope
    ├── effective start
    └── effective end

An active responsibility grant has no effective end.

An ended responsibility grant remains historical.

A previously ended responsibility grant must not be reactivated.

If the same responsibility is granted again later, a new responsibility period
is created.

---

## 4. Business Rules

### BR-1 — Responsibilities belong to an Organization Membership

A responsibility change modifies responsibility grants belonging to an existing
Organization Membership.

It must not assign a global role directly to the User.

---

### BR-2 — Responsibility changes require an active Membership

Responsibilities must not be added to an ended Organization Membership.

If a former Member rejoins the Organization, the applicable new Membership
period must receive its own responsibility grants.

---

### BR-3 — Responsibility-management capability is required

Only an actor whose current Organization responsibilities provide
`ORGANIZATION_GRANT_RESPONSIBILITIES` may change another Member's
responsibilities through this workflow.

Authentication or Organization Membership alone is insufficient.

---

### BR-4 — Responsibility-management capability is Organization-specific

Authority derived from VetCare must not permit responsibility changes in
Animalia.

The acting capability must belong to the target Organization context.

---

### BR-5 — Clinic-scoped authority alone does not manage Membership responsibilities

A Clinic-scoped Administrator does not gain Organization Membership
responsibility-management authority solely from that Clinic-scoped
responsibility.

Responsibility changes are Organization relationship administration.

---

### BR-6 — Supported responsibilities may be added

An authorized actor may add a supported non-owner responsibility to an active
Membership where the requested scope is valid.

Phase 1 supported assignable responsibilities include:

- `ADMINISTRATOR`;
- `RECEPTIONIST`;
- `VETERINARIAN`.

`OWNER` follows separate ownership behavior.

---

### BR-7 — Supported responsibilities may be removed

An authorized actor may end a current non-owner responsibility grant where the
resulting Membership remains valid.

Ending the responsibility records an effective end.

The historical responsibility grant remains preserved.

---

### BR-8 — Responsibility change must not rewrite historical start

Changing or ending a responsibility must not modify its original effective
start.

---

### BR-9 — Ended responsibility grants are immutable historical records

Once a responsibility grant has ended, ordinary responsibility-management
operations must not:

- reactivate it;
- change its original responsibility;
- change its historical scope;
- change its effective start;
- silently replace its effective end.

---

### BR-10 — Regranting responsibility creates a new period

If Carlos previously held:

    RECEPTIONIST
    2026-01-01 → 2026-04-01

and later receives `RECEPTIONIST` again, the new authority must be represented
as a new responsibility period.

The previous grant remains unchanged.

---

### BR-11 — Promotion does not rewrite previous responsibility

Changing:

    RECEPTIONIST
        ↓
    ADMINISTRATOR

must preserve the ended Receptionist grant and establish a new Administrator
grant.

The system must not mutate the historical Receptionist row into Administrator.

---

### BR-12 — Demotion follows the same historical rule

Changing:

    ADMINISTRATOR
        ↓
    RECEPTIONIST

must preserve the previous Administrator period and create the new applicable
Receptionist period.

---

### BR-13 — Scope change creates a new responsibility period

Changing:

    RECEPTIONIST @ Madrid Centro

to:

    RECEPTIONIST @ Getafe

must not rewrite the historical Madrid scope.

The Madrid responsibility grant ends and a new Getafe responsibility grant is
created.

---

### BR-14 — Organization-wide to Clinic-scoped change preserves history

Changing:

    ADMINISTRATOR @ Organization

to:

    ADMINISTRATOR @ Madrid Centro

must preserve the previous Organization-scoped period and establish a new
Clinic-scoped period.

---

### BR-15 — Clinic-scoped to Organization-wide change preserves history

Changing:

    ADMINISTRATOR @ Madrid Centro

to:

    ADMINISTRATOR @ Organization

must create a new Organization-scoped responsibility period.

The previous Clinic-scoped period remains historical.

---

### BR-16 — Scope must belong to the Membership Organization

A Clinic-scoped responsibility may reference only a Clinic operated by the same
Veterinary Organization as the Membership.

For example:

    Animalia Membership
        +
    RECEPTIONIST @ VetCare Toledo

is invalid.

---

### BR-17 — Responsibility scope rules must be respected

The scope restrictions defined by `SPEC-ORG-005` remain applicable.

For example:

- `OWNER` is Organization-scoped;
- `VETERINARIAN` is Organization-scoped;
- `ADMINISTRATOR` may be Organization- or Clinic-scoped;
- `RECEPTIONIST` may be Organization- or Clinic-scoped.

---

### BR-18 — OWNER cannot be added through this workflow

This Specification must not allow an actor to add the `OWNER` responsibility.

Adding another Owner or transferring ownership requires a dedicated
Organization ownership workflow.

---

### BR-19 — OWNER cannot be removed through this workflow

This Specification must not remove an existing `OWNER` responsibility.

Ownership changes must preserve the active-Owner invariant and follow dedicated
behavior.

---

### BR-20 — Standard responsibility management must not implicitly transfer ownership

Changing another responsibility must never cause ownership to move from one User
to another.

---

### BR-21 — Responsibility change does not create another Membership

Promoting, demoting, adding, removing, or changing scope must operate within the
existing active Organization Membership.

It must not create another active Membership for the same User and Organization.

---

### BR-22 — Responsibility change does not create another User

Changing responsibilities must preserve the same domain User identity.

---

### BR-23 — Responsibility change does not establish veterinary qualification

Adding `VETERINARIAN` responsibility must not:

- create a Veterinarian Professional Profile;
- verify professional credentials;
- establish professional qualification.

Those remain separate domain concerns.

---

### BR-24 — Adding VETERINARIAN does not create Clinic Assignment

A responsibility change assigning `VETERINARIAN` must not automatically assign
the User to any Clinic.

Clinic Assignment remains governed by its own Specifications.

---

### BR-25 — Removing VETERINARIAN does not erase professional identity

Removing the Organization `VETERINARIAN` responsibility must not delete or
invalidate the User's Organization-independent Veterinarian Professional
Profile.

---

### BR-26 — Removing responsibility removes future derived capability

Once a responsibility grant ends, capabilities derived solely from that grant
must no longer authorize future operations.

---

### BR-27 — Removing responsibility does not rewrite previous authorized actions

Operations validly performed while the responsibility was active remain
historically valid.

For example, removing Administrator responsibility must not invalidate a Clinic
that Carlos validly created while authorized.

---

### BR-28 — Responsibility change does not rewrite clinical provenance

Historical clinical information must not be modified because a professional's
current Organization responsibilities change.

---

### BR-29 — Responsibility change does not modify Appointments

Changing Organization responsibilities must not automatically:

- cancel Appointments;
- confirm Appointments;
- reassign Veterinarians;
- reschedule Appointments;
- alter historical Appointment actions.

Future capability is reevaluated independently.

---

### BR-30 — Responsibility change does not modify Clinic Assignment

Adding or removing Organization responsibility must not silently create,
terminate, or rewrite Veterinarian Clinic Assignments.

Current professional authority may nevertheless cease if the required
responsibility is no longer present.

---

### BR-31 — Responsibility change does not modify Guardianship

Organization responsibility administration must not affect Pet Guardianship.

---

### BR-32 — Responsibility change does not grant medical access

Adding an administrative or veterinary responsibility must not itself create
Care Authorization or unrestricted Pet medical-history access.

Medical Access Control remains independently required.

---

### BR-33 — Responsibility change does not change Subscription state

Changing a Member's responsibility must not activate, cancel, or modify the
Organization Subscription.

---

### BR-34 — Responsibility change does not create Entitlement

A responsibility may be required for an Entitlement-protected operation, but
changing responsibility does not create the commercial Entitlement itself.

---

### BR-35 — Exact duplicate active responsibility grants must not be created

The same Membership must not contain two simultaneously active equivalent
responsibility grants with the same:

- responsibility;
- scope.

Repeated addition of the same already-active responsibility must not create
duplicate authority.

---

### BR-36 — No-op responsibility changes must not create false history

If a requested operation would leave the responsibility configuration
unchanged, the system must not create meaningless historical responsibility
periods.

---

### BR-37 — Multiple responsibilities may remain active simultaneously

Adding a responsibility does not require ending unrelated active
responsibilities.

For example:

    VETERINARIAN @ Animalia
        +
    ADMINISTRATOR @ Madrid Centro

may coexist.

---

### BR-38 — Removing one responsibility does not remove others

Ending:

    ADMINISTRATOR @ Madrid Centro

must not silently end:

    VETERINARIAN @ Animalia

or another independent responsibility grant.

---

### BR-39 — Responsibility changes use current authority

The acting User's authority must be evaluated when the change is performed.

A User who previously had administrative authority must not continue changing
responsibilities after that authority ends.

---

### BR-40 — User must not self-escalate without applicable authority

A Member must not add or increase their own responsibilities merely because
they can access their own Membership.

Self-directed responsibility changes require the same applicable authorization
as changes affecting another Member.

---

### BR-41 — Authorization must not trust client-provided role claims

A manipulated client must not successfully change responsibilities by
asserting:

    role = OWNER

or:

    can_manage_responsibilities = true

Trusted infrastructure must evaluate current authoritative Organization state.

---

### BR-42 — Responsibility changes must be atomic

A change involving replacement of one responsibility grant with another must
behave as one coherent domain operation.

For example:

    RECEPTIONIST → ADMINISTRATOR

must not expose an unintended partial state caused by only one half of the
change being persisted.

---

### BR-43 — Failed responsibility change preserves previous state

If validation or persistence fails, the previous valid responsibility
configuration must remain authoritative.

Historical grants must not be partially corrupted.

---

### BR-44 — Concurrent changes must preserve coherent responsibility history

Competing changes to the same responsibility configuration must not produce:

- duplicate active equivalent grants;
- contradictory effective periods;
- overwritten historical state;
- accidental privilege escalation.

The exact concurrency mechanism is architectural.

---

### BR-45 — Responsibility change should be attributable

The system must preserve sufficient traceability to determine, where required:

- which Membership changed;
- which responsibility changed;
- previous scope;
- new responsibility or scope where applicable;
- acting User;
- effective time.

The exact audit representation is architectural.

---

## 5. Responsibility History

Responsibility history answers:

    "What authority did this Member have at this point in time?"

It must not be reconstructed solely from the Member's current responsibility
configuration.

Conceptually:

    Carlos — Animalia Membership

    RECEPTIONIST @ Madrid
    Jan 1 → Mar 10

    ADMINISTRATOR @ Madrid
    Mar 10 → current

Current capability uses:

    ADMINISTRATOR @ Madrid

Historical interpretation for February uses:

    RECEPTIONIST @ Madrid

---

## 6. Membership vs Responsibility Lifecycle

These concepts are related but distinct.

Example:

    Membership
    Jan 1 ───────────────────────────── current

    RECEPTIONIST
    Jan 1 ───── Mar 10

    ADMINISTRATOR
                 Mar 10 ─────────────── current

The Membership remained active throughout.

A promotion therefore does not require:

    end Membership
        ↓
    create another Membership

Doing so would incorrectly fragment one continuous professional relationship.

---

## 7. Responsibility Removal vs Membership Termination

Removing a responsibility answers:

    "Does this Membership still provide this capability?"

Ending a Membership answers:

    "Does this professional Organization relationship still exist?"

They must remain separate operations.

Removing one responsibility must not implicitly end the Membership.

Membership termination remains governed by `SPEC-ORG-004`.

---

## 8. Scenarios

### Scenario: Promote Receptionist to Administrator

Given Carlos has an active Animalia Membership
And Carlos currently has `RECEPTIONIST` scoped to Madrid Centro
And Maria has authority to manage Animalia responsibilities

When Maria changes Carlos to `ADMINISTRATOR` scoped to Madrid Centro

Then the Receptionist grant receives an effective end
And a new Administrator responsibility grant becomes active
And Carlos's Organization Membership remains the same
And the previous Receptionist period remains historical

---

### Scenario: Demote Administrator to Receptionist

Given Carlos has an active `ADMINISTRATOR` responsibility at Madrid Centro
And Maria may manage Organization responsibilities

When Maria changes Carlos to `RECEPTIONIST` at Madrid Centro

Then Carlos's Administrator grant ends
And a new Receptionist grant begins
And previous Administrator authority remains historically identifiable

---

### Scenario: Move Receptionist scope to another Clinic

Given Carlos has `RECEPTIONIST` scoped to Madrid Centro

When Maria changes the applicable scope to Getafe

Then the Madrid responsibility grant ends
And a new Getafe responsibility grant begins
And the historical Madrid scope is not rewritten

---

### Scenario: Add responsibility without removing existing one

Given Dr. Garcia has active `VETERINARIAN` responsibility in Animalia

When Maria validly adds `ADMINISTRATOR` scoped to Madrid Centro

Then both responsibilities are active
And Dr. Garcia remains the same User
And the same Animalia Membership remains active

---

### Scenario: Remove one of several responsibilities

Given Dr. Garcia has:

    VETERINARIAN @ Animalia
    ADMINISTRATOR @ Madrid Centro

When Maria removes the Administrator responsibility

Then the Administrator grant ends
And `VETERINARIAN` remains active
And the Organization Membership remains active

---

### Scenario: Regrant previously ended responsibility

Given Carlos previously held Receptionist responsibility
And that grant ended
And Carlos remains an active Animalia Member

When Maria later grants Receptionist responsibility again

Then a new responsibility grant is created
And the old ended responsibility remains unchanged

---

### Scenario: Duplicate active responsibility is not created

Given Carlos already has active `RECEPTIONIST` responsibility at Madrid Centro

When Maria attempts to add the same responsibility and scope again

Then no duplicate active responsibility grant is created
And the existing responsibility remains authoritative

---

### Scenario: No-op scope change creates no false history

Given Carlos already has `RECEPTIONIST` scoped to Madrid Centro

When an update requests the same responsibility and same scope

Then no replacement responsibility period is created solely for the no-op
And current authority remains unchanged

---

### Scenario: Organization Administrator changes Member responsibility

Given Maria has active Organization-scoped `ADMINISTRATOR` responsibility in
Animalia
And Carlos has an active Animalia Membership

When Maria validly adds Receptionist responsibility to Carlos

Then the responsibility may be added
And Carlos receives only the capabilities derived from the resulting
responsibility and scope

---

### Scenario: Clinic Administrator cannot change Membership responsibilities

Given Maria has `ADMINISTRATOR` scoped only to Madrid Centro

When Maria attempts to change Carlos's Animalia Membership responsibilities

Then the operation is denied
And Carlos's responsibilities remain unchanged

---

### Scenario: Receptionist cannot change responsibilities

Given Laura has active `RECEPTIONIST` responsibility in Animalia

When Laura attempts to promote Carlos

Then the operation is denied
And Carlos's responsibility configuration remains unchanged

---

### Scenario: Administrator cannot add Owner

Given Maria has Organization-scoped `ADMINISTRATOR`

When Maria attempts to add `OWNER` to Carlos

Then the operation is denied
And Organization ownership remains unchanged

---

### Scenario: Owner cannot be removed through ordinary responsibility management

Given Maria is an active Animalia Owner

When an ordinary responsibility-management operation attempts to remove
Maria's `OWNER` responsibility

Then the operation is denied
And ownership remains unchanged

---

### Scenario: Changing responsibility in another Organization is denied

Given Maria is an Administrator in Animalia
And Carlos has an active Membership in VetCare
And Maria has no applicable VetCare responsibility

When Maria attempts to change Carlos's VetCare responsibilities

Then the operation is denied

---

### Scenario: Invalid Clinic scope is rejected

Given Carlos has an active Animalia Membership
And VetCare Toledo belongs to VetCare

When Maria attempts to grant:

    RECEPTIONIST @ VetCare Toledo

through Carlos's Animalia Membership

Then the operation is rejected
And Carlos's Animalia responsibility state remains unchanged

---

### Scenario: Adding Veterinarian responsibility does not establish qualification

Given Carlos is not a recognized Veterinarian
And Carlos has an active Animalia Membership

When Maria validly adds the Organization `VETERINARIAN` responsibility

Then Carlos receives the Organization responsibility
And Carlos does not become a recognized Veterinarian
And clinical professional operations remain unavailable until all applicable
professional requirements are satisfied

---

### Scenario: Adding Veterinarian responsibility does not assign Clinic

Given Dr. Garcia receives `VETERINARIAN` responsibility in Animalia
And Dr. Garcia has no Clinic Assignment at Madrid Centro

When her professional context is evaluated

Then the responsibility exists
And no Madrid Centro Clinic Assignment exists solely because of that
responsibility change

---

### Scenario: Removing Veterinarian responsibility preserves professional identity

Given Dr. Garcia has a Veterinarian Professional Profile
And an active Animalia `VETERINARIAN` responsibility

When Maria removes the Animalia veterinary responsibility

Then the Organization responsibility grant ends
And Dr. Garcia's Veterinarian Professional Profile remains unchanged
And historical clinical provenance remains unchanged

---

### Scenario: Responsibility removal affects future authorization

Given Carlos has `ADMINISTRATOR` responsibility
And Maria removes that responsibility

When Carlos later attempts an administrative operation that depended solely on
that responsibility

Then the operation is denied

---

### Scenario: Previous authorized action remains historical

Given Carlos validly published Madrid Centro while he was an Administrator
And Carlos's Administrator responsibility later ends

When Madrid Centro's historical context is evaluated

Then Carlos's previous authorized action is not invalidated
And the Clinic publication history is not rewritten solely because Carlos lost
current authority

---

### Scenario: Self-escalation is denied

Given Carlos has `RECEPTIONIST` responsibility
And Carlos lacks responsibility-management capability

When Carlos attempts to add `ADMINISTRATOR` to his own Membership

Then the operation is denied
And Carlos remains Receptionist

---

### Scenario: Concurrent duplicate promotion does not create duplicate grants

Given Carlos currently has `RECEPTIONIST` responsibility
And two authorized operations concurrently attempt the same promotion to
`ADMINISTRATOR`

When the operations are committed

Then the resulting responsibility history remains coherent
And duplicate equivalent active Administrator grants are not created

---

### Scenario: Failed promotion preserves previous authority

Given Carlos currently has valid Receptionist responsibility

When an attempted promotion fails before the new responsibility configuration
can be committed coherently

Then Carlos's previous valid responsibility state remains authoritative
And no partial promotion is exposed

---

## 9. Responsibility Change Traceability

A responsibility change is security-relevant Organization administration.

The system must be capable of preserving enough context to establish:

    target Membership
    previous responsibility/scope
    resulting responsibility/scope
    acting User
    effective time

This traceability must not require rewriting historical responsibility grants.

Whether this information is represented directly through temporal grants,
dedicated Organization administration events, or both is architectural.

---

## 10. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-005 — Organization and Clinic are different concepts.**
- **INV-006 — Organization Membership is temporal.**
- **INV-007 — Clinic Assignment requires Organization Membership.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-015 — Private operations require an authenticated identity.**
- **INV-017 — An Organization must retain an active Owner.**

---

## 11. Dependencies

- SPEC-ID-003 — Authenticate User
- SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
- SPEC-ORG-002 — Invite User to Organization
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-004 — End Organization Membership
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities

Professional behavior additionally depends on the applicable Veterinarian and
Clinic Assignment Specifications.

Medical behavior additionally depends on the applicable Medical Access Control
Specifications.

---

## 12. Out of Scope

This Specification does not define:

- adding another Organization Owner;
- ownership transfer;
- removing Organization ownership;
- custom Organization-defined roles;
- arbitrary per-User permission overrides;
- scheduled future responsibility changes;
- backdated responsibility changes;
- employment contracts;
- payroll roles;
- automatic responsibility changes based on Clinic Assignment;
- automatic responsibility changes based on Subscription state;
- Veterinarian Professional Profile creation;
- veterinary credential verification;
- Clinic Assignment creation or termination;
- Row Level Security implementation;
- database schema.

---

## 13. Verification Notes

Verification must demonstrate that:

1. authorized Organization actors may change supported non-owner
   responsibilities on an active Membership;
2. unauthorized Users cannot change Membership responsibilities;
3. Clinic-scoped administrative authority alone does not grant Organization
   responsibility-management capability;
4. responsibility changes preserve the existing Organization Membership;
5. responsibility changes preserve the existing domain User;
6. adding a responsibility creates a current responsibility grant without
   rewriting unrelated grants;
7. removing a responsibility ends the current grant while preserving its
   history;
8. promotion preserves the previous responsibility period;
9. demotion preserves the previous responsibility period;
10. changing scope ends the previous scoped grant and creates a new period;
11. ended responsibility grants cannot be reactivated or destructively
    rewritten;
12. regranting a previously ended responsibility creates a new responsibility
    period;
13. exact duplicate active responsibility grants are prevented;
14. no-op changes do not create false responsibility history;
15. several responsibilities may remain active simultaneously;
16. removing one responsibility does not remove unrelated active
    responsibilities;
17. responsibility scopes must belong to the Membership Organization;
18. responsibility scope restrictions defined by `SPEC-ORG-005` are enforced;
19. `OWNER` cannot be added or removed through ordinary responsibility
    management;
20. ownership is not implicitly transferred;
21. adding `VETERINARIAN` does not establish veterinary qualification;
22. adding `VETERINARIAN` does not create Clinic Assignment;
23. removing `VETERINARIAN` does not delete professional identity or historical
    clinical provenance;
24. ended responsibilities no longer grant future derived capabilities;
25. previous valid actions remain historically valid after responsibility
    changes;
26. responsibility changes do not modify Appointments, Guardianships,
    Subscription state, or medical records;
27. self-escalation without applicable authority is denied;
28. client-provided role or capability claims are not authoritative;
29. responsibility changes behave atomically;
30. failed changes preserve the previous valid responsibility configuration;
31. concurrent changes cannot produce duplicate active grants or contradictory
    responsibility history;
32. responsibility changes remain sufficiently attributable for security and
    operational traceability.

---

## 14. Staff Responsibility management Phase 1 contract

This section defines the Phase 1 client workflow for this Specification
(**Staff Responsibility Editing + Veterinarian Enablement — Phase 1**). It
narrows BR-1–BR-45 for the client; it does not change them. Staff access
lifecycle Phase 1 (`SPEC-ORG-009` §2) shipped without it.

### BR-46 — A Member holds a list of Responsibility Grants

The client models a Member's current authority as the list of their current
Responsibility Grants (BR-37, `SPEC-ORG-005` BR-2), never as one role. Each
Grant is managed individually:

- **Add** one Grant to a Membership;
- **Change** exactly one Grant (role and/or scope) through atomic replacement
  (BR-13–BR-15, BR-42);
- **End** exactly one Grant (BR-7).

No operation replaces, ends, or recreates the whole Grant set. Changing one
Grant never ends or recreates an unrelated Grant (BR-38).

Ending the Membership and re-inviting the person is never a way to change a
Responsibility: it fragments one continuous professional relationship into two
Memberships (§6). A mistaken role on a still-pending Invitation is corrected by
revoking it (`SPEC-ORG-010`) and inviting again.

### BR-47 — Canonical Phase 1 operations

The client uses only these authenticated trusted operations:

    add_staff_responsibility(
        p_organization_id uuid, p_membership_id uuid,
        p_responsibility text, p_scope_type text, p_clinic_id uuid
    ) returns jsonb

    replace_staff_responsibility(
        p_organization_id uuid, p_responsibility_grant_id uuid,
        p_responsibility text, p_scope_type text, p_clinic_id uuid
    ) returns jsonb

    end_staff_responsibility(
        p_organization_id uuid, p_responsibility_grant_id uuid
    ) returns jsonb

Each is `SECURITY DEFINER`, has an empty `search_path`, and is executable only
by `authenticated`. The acting User is derived from the authenticated subject.
The client names the Organization explicitly, so authorization is decided
before any target row is considered. Grant identifiers come from the Staff read
(`SPEC-ORG-009` BR-1).

The pre-existing generic operations (`add_organization_responsibility`,
`replace_organization_responsibility`, `end_organization_responsibility` and
their compatibility overloads) report target existence and lifecycle before
authorization. They are not a client path: client `EXECUTE` is withdrawn and
they remain for trusted compatibility only.

### BR-48 — Capability

The acting User must currently hold `ORGANIZATION_GRANT_RESPONSIBILITIES` in the
named Organization (BR-3–BR-5). Under the Phase 1 mapping only an active
Organization-scoped `OWNER` or `ADMINISTRATOR` holds it.

### BR-49 — Supported roles and scopes

Add and Change accept exactly:

| Role | Scope |
| --- | --- |
| `ADMINISTRATOR` | Organization, or one Clinic of the Organization |
| `RECEPTIONIST` | Organization, or one Clinic of the Organization |
| `VETERINARIAN` | Organization only |

`OWNER` is never accepted (BR-18). `VETERINARIAN` never takes a Clinic scope;
Clinic practice belongs to Veterinarian Clinic Assignment (`SPEC-ORG-005` §4,
BR-24), and adding `VETERINARIAN` creates no Profile or Assignment (BR-23,
BR-24). A Clinic-scoped Grant requires a Clinic of the named Organization; a
nonexistent Clinic and another Organization's Clinic are one outcome.

### BR-50 — OWNER Grants are immutable here

An `OWNER` Grant is never changed or ended through this workflow (BR-19,
BR-20), including by the Owner themselves.

### BR-51 — Owner Memberships are managed only by that Owner

When the target Membership currently holds an `OWNER` Grant, only the Owner
themselves may Add, Change, or End its non-`OWNER` Grants. Any other actor —
including an Organization Administrator or another Owner — is rejected.
Ownership management remains out of scope (§12).

### BR-52 — Self-targeted changes

- Any authorized actor may **Add** a Grant to their own Membership. For
  example, an Owner or Administrator who is also a veterinarian may add
  `VETERINARIAN` to themselves (BR-40 is satisfied because the same capability
  is required).
- An Owner may **Change** or **End** their own non-`OWNER` Grants.
- An actor whose own Membership holds no `OWNER` Grant may not **Change** or
  **End** a Grant of their own Membership. This prevents self-demotion and
  self-lockout through Staff.

### BR-53 — The last Responsibility is ended through End access

End must not leave a current Membership with zero current Grants. Ending the
last current Grant is rejected; the administrator uses End access
(`SPEC-ORG-004` §10) instead. Change of the last Grant is allowed, because the
replacement keeps the Membership continuously authorized (BR-42). Neither path
creates a second Membership or Invitation.

### BR-54 — VETERINARIAN with current Clinic Assignments

A current `VETERINARIAN` Grant may not be ended, or changed to another role,
while its Membership supports one or more current Veterinarian Clinic
Assignments (`SPEC-VET-004`). The administrator first ends every current Clinic
Assignment (`SPEC-VET-005` §13) and then ends or changes the Grant.

This workflow never ends Clinic Assignments automatically and never rewrites
Assignment history (BR-30). Ending the whole Membership (`SPEC-ORG-004` §10)
remains different: it makes those Assignments non-current through Membership
currentness, unchanged.

### BR-55 — Fail-closed ordering

Each operation evaluates, in order:

1. authentication and a coherent domain User — otherwise `28000`;
2. the named Organization and `ORGANIZATION_GRANT_RESPONSIBILITIES` together,
   re-decided under the Organization lock — a nonexistent Organization and one
   the caller cannot manage fail identically with SQLSTATE `42501` and one fixed
   message;
3. input (Add, Change): role and scope (`22023`, hint `INVALID_SCOPE`); Clinic
   of the Organization (`22023`, hint `INVALID_CLINIC`);
4. target: the Membership (Add) or Grant (Change, End) within the named
   Organization — a nonexistent target and a target of another Organization fail
   exactly as step 2;
5. protected targets (`23514`): `OWNER_GRANT` (BR-50), `OWNER_MEMBERSHIP`
   (BR-51), `SELF_MEMBERSHIP` (BR-52);
6. lifecycle: Membership not current (`23514`, `MEMBERSHIP_INACTIVE`); an ended
   target Grant (End: `ALREADY_ENDED`; Change: `ALREADY_CHANGED` or
   `GRANT_ENDED`, BR-56);
7. rules (`23514`): `NO_OP` (BR-36), `DUPLICATE` (Change into an equivalent
   active Grant, BR-35), `LAST_RESPONSIBILITY` (BR-53),
   `VETERINARIAN_ASSIGNMENTS_ACTIVE` (BR-54).

An unauthorized caller learns nothing about whether a Membership or Grant
exists, which Organization it belongs to, whether it is current or ended, or
which responsibility it holds. Errors carry fixed messages and stable hints,
never raw database text.

### BR-56 — Outcomes and lost responses

Successful results are compact JSON objects:

| Operation | Outcome | Result members |
| --- | --- | --- |
| Add | `ADDED` | `membership_id`, `responsibility_grant_id`, `effective_start` |
| Add | `ALREADY_PRESENT` — an equivalent active Grant already exists; nothing is written (BR-35) | same, for the existing Grant |
| Change | `REPLACED` | `membership_id`, `replaced_responsibility_grant_id`, `responsibility_grant_id`, `effective_instant` |
| Change | `ALREADY_CHANGED` — the named Grant already ended at the instant an active Grant with exactly the requested role and scope began on the same Membership; nothing is written | same, for that replacement |
| End | `ENDED` | `membership_id`, `responsibility_grant_id`, `effective_end` |
| End | `ALREADY_ENDED` — nothing is written; the original end is reported (BR-9) | same |

A Change whose named Grant has ended without that proof is rejected
(`23514`, `GRANT_ENDED`): the request is stale. No client idempotency key is
used. After every outcome, including an apparent lost response, the client
re-reads the Staff read; the re-read is authoritative.

### BR-57 — Temporal and concurrency semantics

- Add starts the Grant at the statement instant, never before the Membership
  start.
- Change ends the named Grant and starts its replacement at one statement
  instant, never before the Membership or superseded Grant start; unrelated
  Grants are untouched.
- End records the statement instant, never before the Grant start.
- Every operation serializes on the Organization (lock order Organization →
  Membership → Grant → Clinic, as the other Staff writes), so concurrent
  attempts cannot create duplicate active Grants or contradictory periods
  (BR-44).
- Grant rows record the granting and ending User (BR-45).

### Mobile presentation

Responsibilities are managed from the Staff Member detail
(`SPEC-ORG-009` §7):

- one row per current Grant: role, scope, and the Clinic name for Clinic
  scope; rows may be grouped under their role (`SPEC-ORG-009` §7), so that the
  role is shown once as the group heading and each row names its scope, while
  each row's accessible label still names role, scope, and Member;
- **Add responsibility / Añadir responsabilidad**; **Change / Cambiar** and
  **End / Finalizar** on each Grant row. They may be shown compactly — a
  global "Add / Añadir", edit and remove icons on each Clinic row, or edit and
  remove icons in the Veterinarian card header for the single `VETERINARIAN`
  Grant — provided each still acts on exactly one Grant and its accessible name
  says which responsibility (and scope, where it has one) of which Member it
  changes or ends. A card grouping several Grants offers no card-level removal;
- role choices Administrator, Receptionist, Veterinarian — never Owner; for
  Veterinarian the scope is fixed to the Organization and no Clinic selector is
  shown; for Administrator and Receptionist, Organization or one Clinic of the
  route Organization;
- Change and End are never shown on an `OWNER` Grant, on any Grant of an Owner
  Membership other than the acting Owner's own, or on the acting non-Owner's
  own Grants; Add is not shown on another actor's Owner Membership;
- `LAST_RESPONSIBILITY` is explained ("To have them leave the organization, use
  Remove from organization / Para que deje la organización, usa Quitar de la
  organización") and End access is offered where `SPEC-ORG-004` §10 allows it;
- `VETERINARIAN_ASSIGNMENTS_ACTIVE` explains that the Clinic Assignments must
  be ended first and points to the Veterinarian section; nothing is ended
  automatically;
- End requires an explicit confirmation naming the role, scope and Member;
- every action is advisory; the backend decides.

## 15. Staff Responsibility management Phase 1 Verification Notes

In addition to §13, verification must demonstrate that:

33. a multi-Grant Member keeps every unrelated Grant through Add, Change, and
    End;
34. Change replaces exactly the named Grant at one instant, including role
    change, Organization → Clinic, Clinic → Organization, and Clinic A →
    Clinic B;
35. `OWNER` cannot be added, changed, or ended, and `VETERINARIAN` with a Clinic
    scope is rejected;
36. an Administrator cannot Add, Change, or End Grants on an Owner Membership,
    while the Owner manages their own non-`OWNER` Grants;
37. an Administrator may Add to their own Membership but cannot Change or End
    their own Grants;
38. ending the last current Grant is rejected with `LAST_RESPONSIBILITY`, and
    changing it is allowed;
39. ending or changing away a `VETERINARIAN` Grant while current Clinic
    Assignments exist is rejected with `VETERINARIAN_ASSIGNMENTS_ACTIVE`, and
    succeeds once they are ended, without any Assignment being modified by the
    Responsibility operation;
40. unknown, inaccessible, and other-Organization targets fail identically with
    `42501`, before any input or lifecycle fact is reported;
41. retries reconcile: `ALREADY_PRESENT`, `ALREADY_CHANGED`, `ALREADY_ENDED`;
    a stale Change is `GRANT_ENDED`;
42. concurrent Add/Add, Change/End and Change/Change produce one coherent
    history with no duplicate active Grant and no deadlock;
43. no client role executes the generic Responsibility operations.

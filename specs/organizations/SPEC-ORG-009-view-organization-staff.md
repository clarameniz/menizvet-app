# SPEC-ORG-009 — View Organization Staff

**Status:** APPROVED
**Requirements:** REQ-ORG-002, REQ-ORG-005, REQ-ORG-006, REQ-ORG-008, REQ-ID-006
**Domain:** Organizations
**Priority:** P1

## 1. Intent

Allow an authorized Organization administrator to see who currently has
access to one Veterinary Organization, what Responsibilities they currently
hold, and which Organization Invitations are still pending, so that staff
access can be managed from the professional app instead of through SQL or
developer intervention.

This is the read side of **Staff access lifecycle Phase 1** (§2). The writes
it supports are governed by:

- `SPEC-ORG-002` — Invite User to Organization (Phase-1 invite);
- `SPEC-ORG-010` — Revoke Organization Invitation;
- `SPEC-ORG-003` — Accept Organization Invitation (recipient side);
- `SPEC-ORG-004` — End Organization Membership (Phase-1 end access).

The read reports current management state only. It is not a history or audit
view.

---

## 2. Staff access lifecycle Phase 1 scope

Staff access lifecycle Phase 1 consists of:

- **Slice A** — this Organization Staff read and the Staff screen (§7);
- **Slice B1** — invite one person into one supported initial role and scope
  with a server-controlled 7-day expiry (`SPEC-ORG-002` §10), and revoke a
  pending Invitation (`SPEC-ORG-010`);
- **Slice B2** — authenticated Invitation preview and acceptance through the
  email/deep-link flow (`SPEC-ORG-003` §10–§12);
- **Slice C** — end another person's Organization Membership with immediate
  authorization loss (`SPEC-ORG-004` §10).

Staff access lifecycle Phase 1 deferred post-acceptance Responsibility editing
and Veterinarian invitation/setup. Both are delivered by the follow-up
**Staff Responsibility Editing + Veterinarian Enablement — Phase 1**:

- Responsibility management per Grant (`SPEC-ORG-006` §14) from the Staff
  Member detail (§7);
- Veterinarian invitation (`SPEC-ORG-002` §10, BR-17);
- the self-created Veterinarian Professional Profile (`SPEC-VET-001` §13);
- the Organization Veterinarian workforce read (`SPEC-VET-006`) and Clinic
  Assignment management (`SPEC-VET-004` §13, `SPEC-VET-005` §13).

The following remain deferred (§10):

- declining or rejecting an Invitation;
- self-departure;
- resending Invitation communication;
- ended Membership / ended Grant history presentation;
- ownership transfer, additional Owners, and Owner removal;
- Clinic creation;
- iOS universal-link delivery.

---

## 3. Preconditions

- The acting User exists and is authenticated.
- The acting User has a current Organization Membership in the target
  Veterinary Organization.
- The acting User currently holds at least one of the capabilities listed in
  BR-2 for the target Organization.

---

## 4. Business Rules

### BR-1 — The read returns the Organization's current staff state

The Organization Staff management read

    get_organization_staff(p_organization_id uuid) returns jsonb

returns exactly one JSON object with this canonical shape:

```text
{
  "organization_id": uuid,
  "organization_display_name": text,
  "members": [
    {
      "membership_id": uuid,
      "effective_start": timestamptz,
      "is_self": boolean,
      "display_name": text | null,
      "invitation_recipient_email": text | null,
      "responsibilities": [
        {
          "responsibility_grant_id": uuid,
          "responsibility": "OWNER" | "ADMINISTRATOR" | "RECEPTIONIST" | "VETERINARIAN",
          "scope_type": "ORGANIZATION" | "CLINIC",
          "clinic": null | { "clinic_id": uuid, "clinic_display_name": text | null }
        }
      ]
    }
  ],
  "pending_invitations": [
    {
      "invitation_id": uuid,
      "recipient_email": text,
      "responsibilities": [
        {
          "responsibility": "ADMINISTRATOR" | "RECEPTIONIST" | "VETERINARIAN",
          "scope_type": "ORGANIZATION" | "CLINIC",
          "clinic": null | { "clinic_id": uuid, "clinic_display_name": text | null }
        }
      ],
      "created_at": timestamptz,
      "expires_at": timestamptz
    }
  ]
}
```

All members are always present. Absence is represented by `null` or by an
empty array, never by an omitted member.

`responsibility_grant_id` identifies one current Responsibility Grant of the
Member. It is a domain identifier used only to name that Grant to the Staff
Responsibility operations (`SPEC-ORG-006` §14). Pending Invitation
responsibilities carry no Grant identifier: they are intended facts, not
Grants (`SPEC-ORG-005` BR-23).

---

### BR-2 — Authorization requires an existing Organization administration capability

The read is allowed when the acting User currently holds, for the target
Organization, at least one of:

- `ORGANIZATION_INVITE_MEMBERS`;
- `ORGANIZATION_END_MEMBERSHIPS`,

evaluated by the same authoritative Organization-capability evaluation used by
every protected Organization operation (`SPEC-ORG-005`).

No new capability is introduced. The Phase 1 capability catalog
(`SPEC-ORG-005` §5) is unchanged.

Under the Phase 1 responsibility mapping these capabilities are held only by
an active Organization-scoped `OWNER` or `ADMINISTRATOR`. The read is not
granted by:

- a Clinic-scoped `ADMINISTRATOR`, even for the Clinic it manages
  (`SPEC-ORG-005` §7, `SPEC-ORG-006` BR-5);
- `RECEPTIONIST` in any scope;
- `VETERINARIAN`, a Veterinarian Professional Profile, or a Veterinarian Clinic
  Assignment;
- bare Organization Membership;
- an ended Membership or ended Responsibility Grant;
- any responsibility in another Veterinary Organization.

The read authorizes no change. Every Staff write re-authorizes itself with its
own capability.

---

### BR-3 — Nonexistent and inaccessible Organizations are indistinguishable

A nonexistent Organization and an Organization the acting User may not manage
produce the same failure: SQLSTATE `42501` with one fixed message.

The outcome must not reveal:

- whether the Organization exists;
- whether the acting User has, or previously had, a Membership in it;
- which capability is missing;
- how many Members or Invitations it has.

An unauthenticated caller is rejected as unauthenticated (`28000`) before any
Organization is considered.

---

### BR-4 — Active Members only

`members` contains exactly the Organization Memberships of the target
Organization that are current when the read is evaluated (effective start not
in the future and no effective end).

Ended Memberships are not returned. A User who left and rejoined appears once,
through the current Membership only.

Each User appears at most once, because a User has at most one active
Membership per Organization (`SPEC-ORG-004` BR-16).

Members are ordered by `effective_start` ascending, then `membership_id`.

---

### BR-5 — Active Responsibility Grants only

Each member's `responsibilities` contains exactly the Responsibility Grants of
that Membership that are current when the read is evaluated.

Ended Grants are not returned.

Each entry reports the Grant's identifier (`responsibility_grant_id`),
responsibility, and scope. For a Clinic-scoped
Grant, `clinic` identifies the Clinic and its current public-profile display
name (`null` when the Clinic has no display name). For an Organization-scoped
Grant, `clinic` is `null`.

Every responsibility is reported, including `OWNER` and `VETERINARIAN`. The
read reports facts; it does not filter roles that Phase 1 cannot assign.

Entries are ordered by responsibility, then scope type, then Clinic id.

A current Membership normally has at least one active Grant. A Membership with
none is still returned with an empty array; the read does not hide it.

---

### BR-6 — Member display identity is limited to the approved fields

For each active member the read exposes only:

- `display_name` — the member's current User Profile display name exactly as
  stored, or `null` when the member has none (`SPEC-ID-006` BR-7, BR-40);
- `invitation_recipient_email` — for a Membership that was established by
  accepting an Organization Invitation, the normalized recipient email address
  that the inviting administrator supplied on that originating Invitation;
  otherwise `null`;
- `is_self` — whether the Membership belongs to the acting User;
- `effective_start` — the Membership's effective start;
- the active Responsibility Grants (BR-5).

`invitation_recipient_email` is administrative Invitation context: it is the
address the Organization itself chose when inviting. It is not the member's
authentication identifier, it may differ from the address the member signs in
with (`SPEC-ORG-002` BR-16), and it must not be presented as "the member's
email".

The read must not expose:

- the member's authentication (Supabase Auth) email address or any other
  authentication identifier;
- the member's domain User id;
- any other User Profile field (for example a profile image reference);
- the member's Memberships, responsibilities, Guardianships, Pets,
  Appointments, or Clinic Assignments in any context outside this read's
  contract;
- Veterinarian Professional Profile or credential data;
- Subscription or Entitlement data.

A Membership created through trusted provisioning or SQL fixtures has no
originating Invitation and therefore `invitation_recipient_email = null`.

---

### BR-7 — Pending Invitations only

`pending_invitations` contains exactly the Organization Invitations of the
target Organization that are pending when the read is evaluated:

- not revoked;
- not rejected;
- not accepted (no Membership was established from it);
- not expired (`expires_at` later than the evaluation time).

Expired, revoked, rejected, and accepted Invitations are not returned.

For each pending Invitation the read exposes:

- `invitation_id`;
- `recipient_email` — the normalized recipient email address;
- `responsibilities` — every intended responsibility of the Invitation, with
  scope and Clinic identity as in BR-5;
- `created_at` and `expires_at` — the authoritative backend instants.

An Invitation created through the Phase-1 invite workflow has exactly one
intended responsibility (`SPEC-ORG-002` BR-17). Legacy or trusted Invitations
may carry several, and every one is reported.

The read must not expose:

- the Invitation acceptance secret or its digest;
- any `recipient_user_id`;
- the inviting User's identity;
- Transactional Communication, Delivery Job, Delivery Attempt, or provider
  information.

Pending Invitations are ordered by `created_at` ascending, then
`invitation_id`.

---

### BR-8 — The read does not depend on Entitlement

The read does not require a Subscription or professional Entitlement
(`SPEC-SUB-003`). Managing staff access is not paid professional activity, and
the read remains available after Entitlement loss.

---

### BR-9 — The read is side-effect free, non-locking, and consistent

The read:

- modifies no domain state;
- takes no row lock and does not wait for, or block, Staff writes;
- observes one consistent snapshot, so Members, Grants, and pending
  Invitations returned were current together;
- uses one evaluation instant for every "current", "pending", and "expired"
  decision;
- is a `STABLE` read operation, `SECURITY DEFINER`, with an empty
  `search_path`, executable only by `authenticated`.

No direct table access is granted to clients.

---

### BR-10 — The read is strictly Organization-scoped

The read returns only Members, Grants, Clinics, and Invitations of the target
Organization.

It never merges staff from several Organizations. A User who is a Member of
several Organizations appears in each Organization's read only through that
Organization's Membership and that Membership's Grants.

---

### BR-11 — The read is advisory for presentation

The read result is presentation context. Every Staff write re-evaluates
authorization and lifecycle state itself. A stale read must never cause a
write to succeed that the current state would reject.

---

## 5. Scenarios

### Scenario: Owner reads Organization staff

Given Maria holds Organization-scoped `OWNER` in Animalia Veterinary Group
And Carlos is an active Animalia Member with `RECEPTIONIST` scoped to Madrid
Centro
And a pending Invitation for laura@example.com intends `ADMINISTRATOR` scoped
to the Organization

When Maria reads Animalia staff

Then Maria and Carlos are returned as members
And Maria's row has `is_self = true`
And Carlos's responsibility reports Clinic scope with Madrid Centro's id and
display name
And the pending Invitation for laura@example.com is returned with its
`created_at` and `expires_at`

---

### Scenario: Organization Administrator reads staff

Given Lucia holds Organization-scoped `ADMINISTRATOR` in Animalia

When Lucia reads Animalia staff

Then the read succeeds

---

### Scenario: Clinic Administrator cannot read Organization staff

Given Pedro holds `ADMINISTRATOR` scoped only to Madrid Centro

When Pedro reads Animalia staff

Then the read fails with the inaccessible-Organization outcome
And nothing about Animalia's Members or Invitations is revealed

---

### Scenario: Receptionist cannot read Organization staff

Given Laura holds Organization-scoped `RECEPTIONIST` in Animalia

When Laura reads Animalia staff

Then the read fails with the inaccessible-Organization outcome

---

### Scenario: Veterinarian cannot read Organization staff

Given Dr. Garcia holds `VETERINARIAN` in Animalia and a current Clinic
Assignment at Madrid Centro

When Dr. Garcia reads Animalia staff

Then the read fails with the inaccessible-Organization outcome

---

### Scenario: Administrator of another Organization is denied

Given Maria owns VetCare Group
And Maria has no Membership in Animalia

When Maria reads Animalia staff

Then the read fails with the inaccessible-Organization outcome

---

### Scenario: Unknown Organization is indistinguishable from inaccessible

Given no Organization exists with the requested id

When an authenticated User reads staff for that id

Then the read fails with exactly the same SQLSTATE and message as an
inaccessible Organization

---

### Scenario: Anonymous caller is rejected

Given the caller is not authenticated

When the read is invoked

Then it fails as unauthenticated
And no Organization is considered

---

### Scenario: Ended Membership is not listed

Given Carlos's Animalia Membership ended yesterday

When Maria reads Animalia staff

Then Carlos is not returned

---

### Scenario: Ended Grant is not listed

Given Carlos's `ADMINISTRATOR` Grant ended
And Carlos still holds an active `RECEPTIONIST` Grant

When Maria reads Animalia staff

Then Carlos is returned with only `RECEPTIONIST`

---

### Scenario: Revoked, expired, and accepted Invitations are not listed

Given one Animalia Invitation was revoked
And another has expired
And another was accepted

When Maria reads Animalia staff

Then none of those Invitations appears in `pending_invitations`

---

### Scenario: Member who joined by Invitation shows the invited address

Given Carlos accepted an Invitation addressed to carlos.work@example.com
And Carlos signs in with carlos.personal@example.com
And Carlos has no profile display name

When Maria reads Animalia staff

Then Carlos's `invitation_recipient_email` is carlos.work@example.com
And Carlos's `display_name` is null
And carlos.personal@example.com is not returned anywhere

---

### Scenario: Provisioned Member without display identity

Given Ana's Membership was created through trusted provisioning
And Ana has no profile display name

When Maria reads Animalia staff

Then Ana is returned with `display_name = null` and
`invitation_recipient_email = null`
And the Staff screen shows "Unnamed member / Miembro sin nombre"

---

### Scenario: Existing Veterinarian Member appears

Given Dr. Garcia holds `VETERINARIAN` in Animalia

When Maria reads Animalia staff

Then Dr. Garcia appears with the `VETERINARIAN` responsibility
And no Professional Profile or Clinic Assignment data is returned

---

### Scenario: Staff of another Organization is never merged

Given Carlos is a Member of both Animalia and VetCare
And Maria administers Animalia only

When Maria reads Animalia staff

Then Carlos appears with his Animalia Grants only
And no VetCare Member, Grant, Clinic, or Invitation is returned

---

## 6. Edge Cases

### Read during a concurrent lifecycle transition

A read evaluated while an Invitation is being accepted, revoked, or a
Membership is being ended observes either the state before or after that
transaction, never a partial state (BR-9). For example, an Invitation being
accepted appears either as pending or, after commit, as a new Member with the
intended Grants — never both and never neither.

### Invitation expiring between read and action

An Invitation may appear pending and expire before the administrator acts on
it. Subsequent writes evaluate current state (`SPEC-ORG-010` BR-5).

### Acting User loses capability

If the acting User's own capability ends, the next read fails with the
inaccessible-Organization outcome. The client must treat that as loss of Staff
access, not as an empty Organization.

---

## 7. Staff screen presentation

### Placement

Canonical placement:

    Professional → selected Organization → Staff

The Staff screen route carries the Organization id explicitly, for example:

    /professional/organizations/[organizationId]/staff

The route Organization id is the authoritative presentation context for the
screen. The transient in-memory professional Organization selection may be used
to enter the route, but it must not be relied upon for authorization or for
deep navigation. The backend authorizes every call.

There is no all-Organizations Staff screen in Phase 1.

### Entry visibility

The Professional landing may show the Staff entry for the selected Organization
only when that Organization's advisory capabilities from `SPEC-ORG-007` include
`ORGANIZATION_INVITE_MEMBERS` or `ORGANIZATION_END_MEMBERSHIPS`. The entry is
presentation only; the backend remains authoritative.

### Content

The screen presents, for the route's Organization only, under its title and
the Organization's display name (from the professional context, `SPEC-ORG-007`),
two tabs — **Members / Miembros** (initial) and **Invitations / Invitaciones**
— each one list, read page by page through the reads of §12 and only once its
tab is shown. Invite sits in the Invitations tab. The content of each tab is:

- **Active staff**: a compact summary row per member — a display identity and
  the active responsibilities, summarised as one badge per responsibility with
  its Clinic coverage ("all clinics" or a Clinic count). The current User's
  own row is identifiable. Clinic names and Grant-level detail are in the
  Member detail; each row's accessible name still states every current Grant
  with its Clinic. When two members share a display name, the invitation
  address is shown to tell them apart.
- **Pending invitations**, separately from active staff: recipient email, a
  pending marker, the intended role and scope (with Clinic name where
  Clinic-scoped), and expiry time.

Display identity order of preference:

1. `display_name` when present;
2. otherwise `invitation_recipient_email`, presented as invitation context;
3. otherwise "Unnamed member / Miembro sin nombre".

Raw identifiers, capabilities, and Entitlements are never rendered.

### Actions offered (advisory)

- **Invite** — governed by `SPEC-ORG-002` §10.
- **Revoke invitation / Revocar invitación** on a pending Invitation row (a
  compact icon whose accessible name names the address) — governed by
  `SPEC-ORG-010`.
- **End access** — governed by `SPEC-ORG-004` §10 — is offered in the Member
  detail, not on the list row, and never:
  - for the acting User's own Membership (`is_self = true`);
  - for a Membership holding an active `OWNER` responsibility.
  Under the Phase 1 mapping (`SPEC-ORG-005` §6) every holder of
  `ORGANIZATION_END_MEMBERSHIPS` also holds `ORGANIZATION_GRANT_RESPONSIBILITIES`
  and can therefore open the Member detail.
- **Member detail** — when the route Organization's advisory capabilities
  include `ORGANIZATION_GRANT_RESPONSIBILITIES`, an active member row (the whole
  row, with a chevron as its accessible button) opens

      /professional/organizations/[organizationId]/staff/[membershipId]

  which presents, for that Member in the route Organization only:
  - the same Staff-safe display identity (above);
  - **Responsibilities**: one row per current Grant, managed per Grant as
    defined by `SPEC-ORG-006` §14;
  - **Veterinarian**, when the Member holds a current `VETERINARIAN` Grant or
    a current Clinic Assignment: Professional Profile completed / pending and
    the current Clinic Assignments, from the workforce read (`SPEC-VET-006`),
    joined by `membership_id`; Clinic Assignment actions follow
    `SPEC-VET-004` §13 and `SPEC-VET-005` §13;
  - End access, under the rules above.

  The Responsibilities and Veterinarian content may be presented grouped by
  responsibility — Owner, Veterinarian, Receptionist, Administrator — with
  each group's Clinics underneath: the Veterinarian group joins the
  `VETERINARIAN` Grant with the Profile status and current Clinic
  Assignments; Receptionist and Administrator list their Organization-scoped
  Grant (every Clinic, including future ones) and each Clinic-scoped Grant.
  Each group may be a compact card whose Clinics are list rows with icon
  actions, under one section-level Add.
  Grouping is presentation only: every current Grant and current Clinic
  Assignment is still shown individually with its own actions, none is
  hidden, merged, or changed by the client, and no new operation is implied.

  The Member detail never shows User or Auth identifiers, the Member's
  authentication email, or any credential data. A Member that is not in the
  Staff read (ended, unknown, or of another Organization) is shown as
  unavailable, never as an empty Member.

No Decline, Resend, Leave Organization, or ownership action is offered in
Phase 1. A Member is never presented as having one single role.

### Load, refresh, and stale behaviour

- The screen re-reads on focus and after every Staff write, including after an
  apparent lost response.
- Only the first load may replace the screen with an error state; a failed
  refresh keeps the last result.
- Latest request wins.
- With the tabs of §12, "re-reads" means the tab on screen restarts from its
  first page; the other tab restarts when shown again. A failure in one tab
  never clears the other.
- An inaccessible-Organization outcome after a previously successful load means
  the User has lost Staff access; the screen must stop offering actions and
  return the User to the Professional landing with a calm explanation.

---

## 8. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-005 — Organization and Clinic are different concepts.**
- **INV-006 — Organization Membership is temporal.**
- **INV-015 — Private operations require an authenticated identity.**
- **INV-017 — An Organization must retain an active Owner.**
- **INV-019 — Professional context is derived, not stored.**

---

## 9. Dependencies

- SPEC-ID-006 — Manage User Profile (BR-40, Staff management visibility)
- SPEC-ORG-002 — Invite User to Organization
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-004 — End Organization Membership
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ORG-007 — View My Professional Context
- SPEC-ORG-010 — Revoke Organization Invitation

---

## 10. Out of Scope

This Specification does not define:

- ended Membership or ended Responsibility Grant history presentation;
- audit or traceability views of Staff administration;
- the Responsibility management operations themselves (`SPEC-ORG-006` §14);
- Veterinarian Professional Profile, credential, or Clinic Assignment
  information, which this read never carries (the separate workforce read is
  `SPEC-VET-006`);
- searching Users or discovering Users outside the Organization;
- an all-Organizations Staff view;
- Clinic-scoped Staff management by Clinic-scoped Administrators;
- ownership information beyond the `OWNER` responsibility fact;
- Subscription or Entitlement information.

---

## 11. Verification Notes

Verification must demonstrate that:

1. an Organization-scoped `OWNER` may read the Organization's staff;
2. an Organization-scoped `ADMINISTRATOR` may read the Organization's staff;
3. a Clinic-scoped `ADMINISTRATOR`, a `RECEPTIONIST` in any scope, a
   `VETERINARIAN`, bare Membership, and a Member of another Organization are
   denied;
4. an anonymous caller is rejected as unauthenticated before any Organization
   is considered;
5. an unknown Organization and an inaccessible Organization fail with the
   identical SQLSTATE and message;
6. an ended Membership or ended Grant of the caller removes access on the next
   read;
7. only active Memberships are returned;
8. only active Responsibility Grants are returned, including `OWNER` and
   `VETERINARIAN`;
9. Clinic-scoped Grants report the correct Clinic id and display name, and
   Organization-scoped Grants report `clinic = null`;
10. only pending Invitations are returned; revoked, rejected, accepted, and
    expired ones are excluded, with expiry evaluated at the read's evaluation
    instant;
11. pending Invitations report recipient email, every intended
    responsibility with scope and Clinic, `created_at`, and `expires_at`;
12. `is_self` is true exactly for the caller's own Membership;
13. `display_name` is the stored profile display name or `null`;
14. `invitation_recipient_email` equals the originating Invitation's normalized
    recipient email for invitation-derived Memberships and is `null`
    otherwise;
15. the payload never contains an authentication email, a domain User id, the
    Invitation secret or digest, a `recipient_user_id`, the inviting User, or
    Communication data;
16. no other Organization's Members, Grants, Clinics, or Invitations are ever
    returned;
17. the read writes nothing and takes no row lock;
18. the read requires no Entitlement;
19. the payload shape is exactly BR-1, with every member present;
20. ordering follows BR-4, BR-5, and BR-7;
21. on the mobile Staff screen, End access is never offered on the caller's
    own row or on any row with an active `OWNER` responsibility;
22. the Staff screen route carries the Organization id and shows only that
    Organization's staff, even when several Organizations exist;
23. every current Grant entry carries its own `responsibility_grant_id`, which
    identifies exactly that current Grant of that Membership; pending
    Invitation responsibilities carry none;
24. the Member detail shows only the route Organization's Member, joins the
    workforce read by `membership_id` only, and never renders User/Auth ids or
    credential data.

---

## 12. Paged Staff reads — Phase 1

Defined by **Staff screen with tabs and pagination — Phase 1**. The Staff
screen (§7) reads its Members and its pending Invitations separately, one page
at a time, instead of the whole `get_organization_staff` payload.

These reads add no authority, no capability, and no write. Each returns a
subset of what `get_organization_staff` (BR-1) returns for the same instant,
plus BR-14's derived flag. `get_organization_staff` is unchanged: installed
clients and the Member detail and Invite screens keep using it.

### BR-12 — Common rules

Both reads are `STABLE`, `SECURITY DEFINER`, have an empty `search_path`, and
are executable only by `authenticated`. Evaluation order:

1. authentication and a coherent domain User — otherwise `28000`, before any
   Organization is considered;
2. the authorization of BR-2 for `p_organization_id`, with the outcome of BR-3:
   one `42501` `Organization Staff unavailable` for an unknown, null or
   inaccessible Organization alike;
3. input validation — a `p_limit` outside its range, or a cursor that is
   neither complete nor entirely null, fails with `22023`
   `Staff page is invalid`. Invalid input never reveals more than step 2.

Each call is one statement, observes one snapshot, and uses one evaluation
instant for every "current", "pending" and "expired" decision (BR-9). It
writes nothing and takes no lock. It returns only the target Organization's
rows (BR-10) and no total count. The first page is the one with no cursor;
every later page holds the next `p_limit` rows strictly after its cursor in
the read's order.

### BR-13 — Members page

    get_organization_staff_members(
        p_organization_id uuid,
        p_after_effective_start timestamptz default null,
        p_after_membership_id uuid default null,
        p_limit integer default 25
    ) returns table (
        membership_id uuid,
        effective_start timestamptz,
        is_self boolean,
        display_name text,
        invitation_recipient_email text,
        display_name_is_shared boolean,
        responsibilities jsonb
    )

The rows are the members of BR-4, in BR-4's order (`effective_start`, then
`membership_id`), and the cursor is the complete
`(effective_start, membership_id)` of the previous page's last row.
`p_limit` is 1–50. Every column except `display_name_is_shared` has exactly
the value and the restrictions of the same member in BR-1, BR-5 and BR-6;
`responsibilities` is that member's BR-1 array, with Grant ids and BR-5's
order.

A Membership's `effective_start` never changes, so pages neither repeat nor
skip a member that stays current. A member whose Membership ends between pages
is not returned by later pages; one that becomes current with a key before the
cursor appears on a new first read.

### BR-14 — Shared display names are flagged by the read

`display_name_is_shared` is `true` exactly when the member has a
`display_name` and at least one other current member of the same Organization,
at the same instant, has the identical `display_name`; otherwise `false`. It is
evaluated over all current members, not over the page, so the client can tell
same-named members apart (§7) without reading every member. It is derived at
read time, reveals no other member, and is not stored.

### BR-15 — Pending Invitations page

    get_organization_pending_invitations(
        p_organization_id uuid,
        p_after_created_at timestamptz default null,
        p_after_invitation_id uuid default null,
        p_limit integer default 20
    ) returns table (
        invitation_id uuid,
        recipient_email text,
        responsibilities jsonb,
        created_at timestamptz,
        expires_at timestamptz
    )

The rows are the pending Invitations of BR-7 at the read's instant, in BR-7's
order (`created_at`, then `invitation_id`), with exactly BR-7's columns and
restrictions; `responsibilities` is the BR-1 array, without Grant ids. The
cursor is the complete `(created_at, invitation_id)` of the previous page's
last row. `p_limit` is 1–50.

An Invitation's `created_at` never changes: pages neither repeat nor skip one
that stays pending. One that is accepted, revoked, rejected or expires between
pages is not returned by later pages; a new Invitation sorts after every
existing one and appears on a later page or a new first read.

### BR-16 — Client use

The Staff screen (§7) reads the Members tab's first page on entry and the
Invitations tab's first page only when that tab is first shown, and offers
"Load more" while the last page was full. On focus, and after every Staff
write it performs, the tab on screen restarts from its first page; the other
tab restarts when shown again. A restart discards the previous cursor, and an
answer to an older request is ignored. A `42501` from either read means the
Staff access was lost (§7).

---

## 13. Paged Staff reads — Verification Notes

In addition to §11, verification must demonstrate that:

25. both reads authorize exactly as `get_organization_staff` (BR-2, BR-3):
    Owner and Organization-scoped Administrator succeed; every denied actor,
    an unknown and a null Organization fail with the identical `42501`; an
    anonymous or unlinked caller fails with `28000` first; `anon` cannot
    execute them;
26. invalid limits and partial cursors fail with `22023` only after
    authorization;
27. concatenating the pages of the Members read, for every page size, equals
    the `members` of `get_organization_staff` in order and content, plus the
    flag of BR-14;
28. concatenating the pages of the Invitations read, for every page size,
    equals the `pending_invitations` of `get_organization_staff`;
29. ties on `effective_start` and on `created_at` are broken by id, and a
    cursor at the last row returns an empty page;
30. `display_name_is_shared` is true exactly for members sharing a non-null
    display name with another current member of the same Organization,
    including across pages, and never because of an ended member or a member
    of another Organization;
31. a member ended and an Invitation revoked between pages are not returned
    afterwards, and nothing is returned twice;
32. no read returns another Organization's rows, an authentication email, a
    User id, an Invitation secret, or a total count;
33. the reads write nothing, and `get_organization_staff` keeps its signature,
    result and grants.

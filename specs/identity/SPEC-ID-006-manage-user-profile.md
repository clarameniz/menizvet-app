# SPEC-ID-006 — Manage User Profile

**Status:** APPROVED  
**Requirements:** REQ-ID-006  
**Domain:** Identity  
**Priority:** P1

> **Revised — Punto 8 (`APPROVED` 2026-10-23).** Under [SPEC-APT-007 §13](../appointments/SPEC-APT-007-assign-veterinarian-to-appointment.md), actors holding `APPOINTMENT_VIEW_SCHEDULE` at a Clinic see the display name of an Appointment's assigned Veterinarian, and actors holding `APPOINTMENT_ASSIGN_VETERINARIAN` see the display names of the Clinic's eligible Veterinarians and of the Users who assigned them. No other identity fact is exposed, and Guardians receive no Veterinarian name.

## 1. Intent

Allow an authenticated User to view and maintain supported personal profile
information associated with their existing domain User identity.

The User Profile represents current user-maintained personal information.

Managing the User Profile must not:

- create another domain User;
- change authentication authorization by itself;
- create or end Organization Memberships;
- create or end Guardianships;
- create Veterinarian Professional identity;
- change Clinic Assignments;
- modify Appointment history;
- rewrite clinical authorship or medical history.

User Profile information and domain authorization are separate concerns.

---

## 2. Preconditions

- The acting User exists.
- The acting User is authenticated.
- The acting User is modifying their own User Profile through the normal Phase
  1 workflow.
- Submitted information belongs to the supported User Profile model.
- Submitted values satisfy the applicable validation rules.
- The resulting Profile remains internally valid.

---

## 3. Business Rules

### BR-1 — Every Profile belongs to one domain User

User Profile information must belong to a specific existing domain User.

The Profile must not become an independent identity that can exist without its
User.

---

### BR-2 — Profile management preserves User identity

Updating User Profile information must modify the existing User.

It must not create another domain User merely because personal information
changes.

For example:

    Maria
    User ID: U-123

may change her display information while remaining:

    Maria
    User ID: U-123

---

### BR-3 — User may maintain their own Profile

An authenticated User may update supported mutable information in their own
User Profile.

Phase 1 does not provide ordinary Users with authority to modify another
User's Profile.

---

### BR-4 — Authentication alone does not permit editing another User

Knowing another User's identifier or being able to view information about that
User must not permit Profile modification.

The acting User must be authorized for the Profile being changed.

---

### BR-5 — Profile information is separate from authentication identity

User Profile information must not be treated as the authoritative
authentication identity.

Changing Profile information must not implicitly change:

- authentication credentials;
- password;
- authentication provider identity;
- verified email status;
- active authentication sessions.

Those behaviors belong to the Identity authentication lifecycle.

---

### BR-6 — Authentication identifier must not be changed through ordinary Profile editing

Where an email address, phone number, or other identifier is used for
authentication, changing that authentication identifier must not occur merely
through a generic Profile update.

Changing authentication identifiers requires an explicit Identity workflow if
supported.

---

### BR-7 — Profile information may include a human-facing display name

Phase 1 may support a human-facing display name as part of the User Profile.

The display name:

- may be changed;
- need not be globally unique;
- must not be used as the technical User identity.

---

### BR-8 — Display name uniqueness must not be assumed

Several Users may have the same or similar human-facing display name.

The system must identify domain Users using stable technical identity rather
than display-name uniqueness.

---

### BR-9 — Profile may support optional presentation information

The supported User Profile may include optional presentation-oriented
information such as:

- profile image or avatar;
- other explicitly approved non-sensitive personal presentation information.

Optional Profile information may remain absent.

The exact Phase 1 field set should remain intentionally small.

---

### BR-10 — Optional Profile information may be added, changed, or removed

An authenticated User may add, replace, or remove supported optional Profile
information where permitted.

Removing optional information must not invalidate the User account.

---

### BR-11 — Profile update does not change Organization Membership

Updating a User Profile must not:

- create an Organization Membership;
- end an Organization Membership;
- change Membership responsibilities;
- change effective Membership dates.

Professional Organization relationships remain separate.

---

### BR-12 — Profile update does not change Organization ownership

Changing Profile information must not transfer or modify Veterinary
Organization ownership.

Organization ownership follows its dedicated domain lifecycle.

---

### BR-13 — Profile update does not change Guardianship

Updating User Profile information must not:

- create Guardianship;
- end Guardianship;
- invite a Guardian;
- transfer a Pet.

Guardianship remains a separate Pet relationship.

---

### BR-14 — Profile update does not change Veterinarian Professional identity

A User Profile and a Veterinarian Professional Profile are different concepts.

Changing personal User Profile information must not:

- create Veterinarian status;
- remove Veterinarian status;
- verify professional credentials;
- change professional qualification.

---

### BR-15 — Profile update does not change Clinic Assignment

Updating User Profile information must not create, terminate, or modify a
Veterinarian Clinic Assignment.

---

### BR-16 — User Profile must not become the source of professional qualification

Information presented in a User Profile must not independently prove that the
User is a Veterinarian or possesses a professional credential.

Professional qualification must come from the applicable Veterinary
Professional domain model.

---

### BR-17 — User Profile must remain distinct from public Veterinarian information

If professional public profiles are introduced, public veterinary information
must not be derived blindly from arbitrary User Profile fields.

For example:

    User display name

and:

    verified professional public identity

may be related in presentation but have different domain provenance.

---

### BR-18 — Profile update does not modify Clinic public information

Changing a User Profile must not modify:

- Clinic public display name;
- Clinic public contact information;
- Clinic Services;
- Clinic Opening Hours;
- Clinic publication state.

---

### BR-19 — Profile update does not modify Appointment lifecycle

Updating User Profile information must not:

- request an Appointment;
- confirm an Appointment;
- cancel an Appointment;
- reschedule an Appointment;
- complete an Appointment;
- mark an Appointment `NO_SHOW`.

---

### BR-20 — Historical Appointment attribution remains associated with the same User

If a User previously requested or managed an Appointment, changing their
current Profile must not transfer that historical action to another User.

The same stable User identity remains attributable.

---

### BR-21 — Profile update does not modify medical history

Changing current Profile information must not alter:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- clinical occurrence information.

---

### BR-22 — Historical clinical authorship preserves stable User identity

If Dr. Garcia authored clinical information and later changes Profile
information, the historical clinical contribution remains associated with the
same domain User and professional identity.

A Profile change must not create a new clinical author.

---

### BR-23 — Current presentation may differ from historical context

A User's current human-facing Profile information may change over time.

The system may use current presentation information where appropriate while
preserving immutable historical attribution through stable domain identities.

A current display-name change must not rewrite the historical provider or
clinical context.

---

### BR-24 — Profile update does not grant medical access

Changing User Profile information must not grant:

- Pet medical-history access;
- Care Authorization;
- clinical contribution capability;
- cross-clinic medical access.

Medical authorization remains governed separately.

---

### BR-25 — Profile update does not grant professional Entitlement

Changing the User Profile must not affect the Veterinary Organization's
Subscription or professional Entitlements.

Commercial capability belongs to the applicable Organization context.

---

### BR-26 — Profile data must satisfy applicable validation

Submitted Profile information must satisfy applicable rules concerning:

- supported fields;
- value format;
- permitted length;
- acceptable content where applicable.

Exact implementation limits may be defined architecturally or through product
configuration.

---

### BR-27 — Unsupported arbitrary fields must not be accepted

A manipulated client must not be able to extend the User domain model merely by
submitting arbitrary Profile properties.

Only explicitly supported Profile information may be persisted through this
workflow.

---

### BR-28 — Updating one field must not silently clear unrelated fields

A partial Profile update must not require replacement of the entire Profile.

For example:

    update profile image

must not silently remove:

    display name

where the display name was not part of the intended update.

---

### BR-29 — Profile information must follow appropriate privacy rules

Information stored in the User Profile must not automatically become public.

Each Profile field must have an explicitly defined visibility context before it
is exposed to other Users or Anonymous Visitors.

---

### BR-30 — Profile existence does not imply public discoverability

A User having a Profile must not make that User publicly searchable or
discoverable by default.

Public professional visibility, if supported, requires separate behavior.

---

### BR-31 — Private User information must not leak through Organization relationships

Being a Member of an Organization must not automatically make all User Profile
information visible to:

- other Organization Members;
- Clinics;
- Guardians;
- Anonymous Visitors.

Visibility must follow the applicable product context and least-privilege
rules.

BR-40 defines the Organization Staff management visibility context. It does
not create visibility of User Profile information in any other Organization
context. BR-41 defines the professional medical-history provenance visibility
context, limited to the display name. BR-42 defines the Appointment requester
contact context, limited to the requester's display name and verified
authentication email address.

---

### BR-32 — Profile image is presentation content, not identity proof

Where a Profile image is supported, possession or similarity of an image must
not establish authentication identity or professional qualification.

---

### BR-33 — Profile management requires authentication

An Anonymous Visitor must not update User Profile information.

A valid authenticated User context is required.

---

### BR-34 — Signed-out sessions cannot modify Profile

A User whose authentication session has ended must authenticate again before
performing private Profile modifications.

Existing Profile information remains preserved while the User is signed out.

---

### BR-35 — Account recovery preserves User Profile

Recovering authentication access through `SPEC-ID-005` must restore access to
the same User Profile.

Recovery must not create a blank replacement Profile attached to another User.

---

### BR-36 — Profile update does not invalidate sessions by default

Ordinary non-security-sensitive Profile changes must not automatically
invalidate authentication sessions.

Authentication-sensitive changes require their own Identity behavior.

---

### BR-37 — Profile changes may be traceable where required

The system should be capable of identifying:

- the User whose Profile changed;
- the authenticated actor;
- when the change occurred;

where security or operational traceability requires it.

Phase 1 does not require immutable historical versioning of every Profile
field.

---

### BR-38 — Profile update is atomic

A successful Profile update must leave one coherent valid current Profile.

The system must not expose partially applied Profile state.

---

### BR-39 — Failed Profile update preserves previous valid state

If validation or persistence fails, the User's previous valid Profile must
remain unchanged.

---

### BR-40 — Organization Staff management visibility context

`SPEC-ORG-009` — View Organization Staff defines one explicit visibility
context (BR-29, BR-31) for Organization administration.

An actor who currently holds `ORGANIZATION_INVITE_MEMBERS` or
`ORGANIZATION_END_MEMBERSHIPS` in a Veterinary Organization may see, for each
active Member of **that** Organization only:

- the Member's User Profile display name, when present;
- the Member's active responsibilities and their scope, with Clinic display
  names for Clinic-scoped responsibilities;
- the Membership's effective start;
- whether the Member is the acting User.

The Staff read may additionally show, for a Member who joined by accepting an
Organization Invitation, the normalized recipient email address that the
Organization's administrator supplied on that Invitation. That address is
administrative Invitation context created by the Organization itself. It is not
User Profile information and not an authentication identifier, and it may
differ from the address the Member authenticates with.

This context does not expose:

- the Member's authentication email address or any other authentication
  identifier;
- any other User Profile field;
- the Member's relationships in other Organizations, Guardianships, Pets, or
  Appointments;
- any information to other Organization Members, Receptionists, Veterinarians,
  Clinic-scoped Administrators, Guardians, or Anonymous Visitors.

Any other exposure of User Profile information to other Users still requires
its own explicitly specified visibility context.

---

### BR-41 — Professional medical-history provenance visibility context

`SPEC-MED-005` §15 defines a second explicit visibility context (BR-29,
BR-31), for clinical provenance.

A Veterinarian whose read of a Pet's professional longitudinal medical history
is permitted (`SPEC-MED-005` BR-38–BR-40) may see, for each returned clinical
fact only, the User Profile display name of the User historically recorded as:

- the Clinical Record Entry's creator (its original author);
- the Clinical Record Entry's finalizer;
- a Clinical Amendment's author.

The name is the User's current display name, trimmed, or absent when none is
set (BR-23): no historical snapshot is kept. It is resolved through that
historical attribution and never requires the person's current Organization
Membership, `VETERINARIAN` Responsibility, Clinic Assignment or Professional
Profile, so offboarding does not remove it.

This context does not expose:

- the authentication email address or any other authentication identifier;
- an Invitation recipient address;
- a professional registration identifier or any credential fact;
- any User, Membership or Clinic Assignment identifier;
- any other User Profile field;
- a professional title inferred by the product: the display name is
  self-entered and unverified (BR-17).

It gives Guardians, Receptionists, Administrators, Owners, Anonymous Visitors
and Veterinarians outside a permitted history read nothing. Showing Veterinarian
names to Guardians requires its own future visibility context.

---

### BR-42 — Appointment requester contact visibility context

`SPEC-APT-012` BR-49 and BR-50 define a third explicit visibility context
(BR-29, BR-31), so that a Clinic can identify and contact the person who asked
it for an Appointment.

An actor who currently holds `APPOINTMENT_VIEW_SCHEDULE` for the Clinic of an
Appointment (`SPEC-APT-012` BR-1–BR-3) may see, for that Appointment only, about
the User recorded as its requesting User (`SPEC-APT-001` BR-9):

- the User Profile display name, through the Clinic Appointment Schedule and
  the single-Appointment requester contact read;
- the authentication email address, only through the single-Appointment
  requester contact read, and only while that address is verified.

The context concerns the original requester of the Appointment, not
necessarily a current Guardian of the Pet. It applies to every Appointment
lifecycle state and does not depend on the requester still holding a
Guardianship of the Pet.

Both values are the User's current values, resolved at read time: the display
name trimmed, or absent when none is set (BR-23); the email address absent
when the account has no verified address. No snapshot is kept, and a later
change of either value is shown by the next read.

The authentication email address remains an authentication identifier
(BR-5, BR-6). Exposing it in this context does not make it User Profile
information, does not let anyone change it, and does not make it visible in
any other context.

The Guardian is informed, when requesting an Appointment, that the Clinic may
consult their name and email address to manage it (`SPEC-APT-001` BR-37).

Access follows current authority only. A User whose Organization Membership,
Responsibility Grant or Veterinarian Clinic Assignment no longer provides
`APPOINTMENT_VIEW_SCHEDULE` for that Clinic sees nothing (`SPEC-APT-012`
BR-28–BR-30).

This context does not expose:

- any User, authentication or Membership identifier;
- any other Guardian of the Pet, any Guardianship, or any Guardianship
  Invitation;
- any other User Profile field;
- a phone number;
- the requester's Appointments at other Clinics or relationships in other
  Organizations;
- anything to Guardians, Anonymous Visitors, or Users without current
  `APPOINTMENT_VIEW_SCHEDULE` for that Clinic.

---

## 4. Phase 1 User Profile Information

Phase 1 should keep the User Profile intentionally small.

### Supported current Profile concepts

The Profile may support:

- human-facing display name;
- optional profile image or avatar;
- other explicitly approved non-sensitive presentation information.

Authentication credentials and professional domain information must not be
stored merely as Profile fields.

### Not ordinary Profile information

The following concepts belong elsewhere:

- authentication password or secret;
- authentication-session information;
- email verification state;
- Organization Membership;
- Organization responsibility;
- Veterinarian qualification;
- Clinic Assignment;
- Guardianship;
- Pet information;
- professional Entitlements;
- medical-access authorization.

---

## 5. Scenarios

### Scenario: User updates display name

Given Maria is authenticated
And Maria has an existing User Profile

When Maria changes her display name to another valid value

Then Maria's existing User Profile is updated
And Maria remains the same domain User
And no domain relationship is recreated

---

### Scenario: Two Users may use the same display name

Given Maria has the display name "María García"
And another User also wishes to use "María García"

When the second User submits that valid display name

Then the display name may be accepted
And the two Users remain distinct through their stable domain identities

---

### Scenario: User adds optional profile image

Given Maria is authenticated
And profile images are supported

When Maria adds a valid profile image

Then the image may become part of Maria's current Profile presentation
And the image does not become authentication proof

---

### Scenario: User removes optional profile image

Given Maria currently has a Profile image

When Maria removes it

Then Maria's User remains valid
And her Organization Memberships and Guardianships remain unchanged

---

### Scenario: Profile update does not change authentication email

Given Maria authenticates using a verified authentication email
And Maria submits a generic Profile update

When the Profile update succeeds

Then Maria's authentication identifier remains unchanged
And changing the authentication email would require its own Identity workflow

---

### Scenario: Profile update does not change Organization Membership

Given Maria has an active Membership in Animalia Veterinary Group

When Maria changes her User Profile

Then her Animalia Membership remains unchanged
And its responsibilities remain unchanged

---

### Scenario: Profile update preserves several Organization Memberships

Given Dr. Garcia has active Memberships in Animalia and VetCare

When Dr. Garcia updates her User Profile

Then both Memberships remain associated with the same domain User
And neither relationship is recreated or transferred

---

### Scenario: Profile update does not change Guardianship

Given Maria is an active Guardian of Luna

When Maria updates her User Profile

Then Maria remains Luna's Guardian
And Luna's Pet Profile remains unchanged

---

### Scenario: Veterinarian Profile remains separate

Given Dr. Garcia has a recognized Veterinarian Professional Profile

When Dr. Garcia changes her personal User Profile information

Then her Veterinarian Professional Profile remains a separate professional
domain entity
And professional qualification is not altered by the personal Profile change

---

### Scenario: User cannot make themselves Veterinarian through Profile editing

Given Carlos is not a recognized Veterinarian

When Carlos attempts to submit arbitrary User Profile information claiming a
professional qualification

Then the User Profile workflow does not establish Veterinarian status
And professional qualification remains governed by the Veterinary domain

---

### Scenario: Profile update preserves historical Appointment requester

Given Maria previously requested an Appointment for Luna
And Maria later changes her display name

When the historical Appointment is viewed

Then the Appointment remains associated with the same requesting User
And the Profile update does not transfer requester attribution

---

### Scenario: Profile update preserves clinical authorship

Given Dr. Garcia previously authored a Finalized Clinical Record Entry
And Dr. Garcia later changes current User Profile information

When the historical Clinical Record is evaluated

Then the Entry remains attributed to the same User and professional context
And no new author identity is created

---

### Scenario: Profile information does not become public automatically

Given Maria has private User Profile information

When an Anonymous Visitor uses public product functionality

Then Maria's Profile information is not exposed solely because the Profile
exists

---

### Scenario: Organization Membership does not expose entire Profile

Given Maria and Carlos are both Members of Animalia Veterinary Group
And some Maria Profile information is not explicitly visible in the
Organization context

When Carlos views Organization information

Then that private Profile information is not exposed merely because both Users
belong to Animalia

---

### Scenario: Signed-out User cannot update Profile

Given Maria previously signed out

When Maria attempts to update her Profile using the ended session

Then authentication is rejected
And the Profile remains unchanged

---

### Scenario: Account recovery returns same Profile

Given Maria has an existing User Profile
And Maria loses account access

When Maria successfully completes account recovery

Then Maria regains access to the same domain User
And the same User Profile remains associated with that User
And a replacement User Profile is not created for a second User

---

### Scenario: Updating one Profile field preserves another

Given Maria has a display name and Profile image

When Maria changes only the display name

Then the display name is updated
And the Profile image remains unchanged

---

### Scenario: Invalid Profile update is rejected

Given Maria has a valid User Profile

When Maria submits an invalid Profile value

Then the update is rejected
And the previous valid Profile remains unchanged

---

### Scenario: Unsupported arbitrary field is rejected

Given Maria is authenticated
And the User Profile does not support a field named `organization_admin`

When a manipulated client attempts to persist:

    organization_admin = true

through the Profile workflow

Then the unsupported field does not grant or establish Organization capability
And the User authorization model remains unchanged

---

## 6. User Profile vs Authentication

These concepts answer different questions.

User Profile:

    "How is this User represented within supported product contexts?"

Authentication:

    "Has this User proven control of an authentication identity?"

Therefore:

    change display name

does not imply:

    change login credential

and:

    recover password

does not imply:

    recreate Profile

---

## 7. User Profile vs Professional Profile

A User may exist without being a Veterinarian.

Conceptually:

    Domain User
       │
       ├── User Profile
       │
       └── optional Veterinarian Professional Profile

The personal User Profile must not become the source of truth for professional
qualification.

This allows one stable User identity to participate in personal and
professional product contexts without duplicating the User.

---

## 8. User Profile vs Domain Relationships

The same User may simultaneously have:

    User Profile
         +
    Guardianship → Luna
         +
    Membership → Animalia
         +
    Membership → VetCare
         +
    Veterinarian Professional Profile

Changing the User Profile changes none of those relationships by itself.

This separation preserves stable domain identity.

---

## 9. Privacy Boundary

User Profile information must not be assumed public.

Conceptually:

    stored Profile information
             ≠
    globally public information

Visibility depends on the relevant product context.

For example, future product behavior may deliberately expose limited
professional information while keeping other personal information private.

Such visibility must be explicitly specified rather than inferred.

---

## 10. Edge Cases

### User changes display name frequently

Current display information may change without creating new User identity.

Phase 1 does not require immutable history for every display-name change.

---

### User has professional and personal contexts

The same User may act as:

- Guardian;
- Organization Member;
- Veterinarian.

One personal Profile supports the stable User identity while authorization
remains context-specific.

---

### Current display information differs from old screenshots or communications

User Profile represents current mutable presentation information.

Historical domain events remain associated through stable identity rather than
requiring all current Profile fields to remain frozen forever.

---

### User needs to change authentication email

This requires a dedicated verified Identity workflow if supported.

It must not be implemented as ordinary Profile editing.

---

### User attempts to encode permissions in Profile

Profile fields must not become authorization inputs unless an approved domain
Specification explicitly defines such behavior.

---

### Account is recovered after Profile changed on another valid session

Successful recovery must preserve the current authoritative User Profile rather
than restoring stale Profile information cached by the recovering client.

---

## 11. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-006 — Organization Membership is temporal.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-ID-001 — Register User
- SPEC-ID-002 — Verify Email Address
- SPEC-ID-003 — Authenticate User
- SPEC-ID-004 — Sign Out
- SPEC-ID-005 — Recover Account Access

Professional identity remains governed by the applicable Veterinary
Specifications.

Organization relationships remain governed by the Organization
Specifications.

Guardianship remains governed by the Pet Specifications.

The Appointment requester contact context (BR-42) is used by:

- SPEC-APT-001 — Request Appointment (BR-37, Guardian information);
- SPEC-APT-012 — View Clinic Appointment Schedule (BR-49, BR-50).

---

## 13. Out of Scope

This Specification does not define:

- changing authentication email;
- changing authentication phone number;
- password changes;
- account recovery;
- account deletion;
- account deactivation;
- public User search;
- public social profiles;
- public Veterinarian profile behavior;
- professional credential editing;
- Organization Membership editing;
- Guardianship management;
- custom per-Organization User profiles;
- social-media links;
- biography or rich social content;
- arbitrary custom Profile fields;
- immutable version history for every Profile field.

---

## 14. Verification Notes

Verification must demonstrate that:

1. an authenticated User may manage supported information in their own User
   Profile;
2. Profile updates preserve the existing domain User identity;
3. ordinary Users cannot modify another User's Profile;
4. User Profile and authentication identity remain separate;
5. ordinary Profile editing cannot change authentication identifiers;
6. display names need not be globally unique;
7. optional Profile information may be added, changed, or removed;
8. Profile changes do not alter Organization Membership or ownership;
9. Profile changes do not alter Guardianship;
10. Profile changes do not create or modify Veterinarian Professional identity;
11. Profile changes do not alter Clinic Assignments;
12. Profile changes do not alter Appointment lifecycle or historical requester
    attribution;
13. Profile changes do not rewrite medical history or clinical authorship;
14. Profile changes do not grant medical access or professional Entitlements;
15. unsupported arbitrary fields cannot create domain capabilities;
16. changing one Profile field does not silently clear unrelated fields;
17. User Profile information does not become public merely because it exists;
18. signed-out sessions cannot modify private Profile information;
19. account recovery preserves the same User Profile;
20. invalid or failed updates preserve the previous valid Profile;
21. successful Profile updates behave atomically;
22. within the Organization Staff management context (BR-40), only the
    display name is exposed from the User Profile, only to current holders of
    `ORGANIZATION_INVITE_MEMBERS` or `ORGANIZATION_END_MEMBERSHIPS` in the same
    Organization, and the authentication email address is never exposed;
23. within the professional medical-history provenance context (BR-41), only
    the display name of a User historically attributed to a returned clinical
    fact is exposed, only through a permitted professional history read, also
    after that User's offboarding, never with an identifier, email, Invitation
    address or credential fact, and never to Guardians;
24. within the Appointment requester contact context (BR-42), only the
    requesting User's current display name and, through the single-Appointment
    read only, current verified authentication email are exposed, only to
    current holders of `APPOINTMENT_VIEW_SCHEDULE` for that Appointment's
    Clinic, in every lifecycle state and whether or not the requester is still
    a Guardian of the Pet, never with an identifier and never for any other
    Guardian.
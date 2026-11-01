# SPEC-ORG-008 — View My Professional Clinics

**Status:** APPROVED
**Requirements:** REQ-ORG-008, REQ-ORG-005, REQ-APT-008
**Domain:** Organizations
**Priority:** P1

## 1. Intent

Allow an authenticated User to determine, from trusted backend information,
which Clinics are currently part of their operational professional context,
so that the single MenizVet application can offer those Clinics as entry
points into Clinic-level professional workflows, beginning with the Clinic
Appointment Schedule (`SPEC-APT-012`).

A Clinic is part of the User's operational professional context when the User
currently holds at least one effective Clinic-context capability for it under
`SPEC-ORG-005`.

`SPEC-ORG-007` reports the User's professional context per Organization
Membership. It deliberately does not enumerate the Clinics to which
Organization-scoped capabilities apply (`SPEC-ORG-007` §5 and §8). This
Specification performs that expansion server-side, so that the client does not
combine Organization-scoped and Clinic-scoped grants itself.

For each returned Clinic, the result includes the minimum Clinic and
Organization identity and the effective Clinic-context capabilities the User
currently holds for that Clinic.

Listing a Clinic grants no capability. Every professional operation at that
Clinic continues to evaluate its own authorization, any applicable Entitlement
requirement, and other operation-specific preconditions when it is performed.

See
[ADR-010](../../docs/decisions/ADR-010-single-mobile-app-with-derived-professional-context.md)
and
[SPEC-ORG-007](SPEC-ORG-007-view-my-professional-context.md).

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.

No professional relationship is a precondition. A User with no effective
Clinic-context capability receives an empty result (BR-12).

---

## 3. Business Rules

### BR-1 — Only the acting User's Clinics are returned

The result describes only the acting User.

The read accepts no User, Organization, or Clinic input. It must not reveal
another User's Memberships, responsibilities, capabilities, Clinic
Assignments, or personal information.

---

### BR-2 — Inclusion requires an effective Clinic-context capability

A Clinic is returned if and only if, at evaluation time, the acting User
currently holds at least one effective Clinic-context capability for that
Clinic under `SPEC-ORG-005`.

Clinic-context capabilities are the `SPEC-ORG-005` §5 Clinic-administration,
Appointment-operation, and clinical professional capabilities. Organization
administration capabilities (`ORGANIZATION_*`) do not by themselves include
any Clinic.

Effectiveness must be determined by the same authoritative capability
evaluation that protected Clinic operations use, not by a separately
maintained mapping that could diverge from `SPEC-ORG-005`.

---

### BR-3 — Organization-scoped responsibilities apply to the Organization's Clinics

Under the current `SPEC-ORG-005` rules:

* an active Organization-scoped `OWNER` responsibility includes every Clinic of
  that Veterinary Organization to which its Organization-scoped Clinic
  capabilities apply;
* an active Organization-scoped `ADMINISTRATOR` responsibility includes the
  same Clinics;
* an active Organization-scoped `RECEPTIONIST` responsibility includes every
  Clinic of that Veterinary Organization to which its Appointment capabilities
  apply.

This includes Clinics created after the responsibility was granted,
unpublished Clinics, and Clinics without a display name.

Organization-scoped responsibilities never include a Clinic of another
Veterinary Organization (`SPEC-ORG-005` BR-9, BR-11).

---

### BR-4 — Clinic-scoped responsibilities apply only to the covered Clinic

An active Clinic-scoped `ADMINISTRATOR` or `RECEPTIONIST` responsibility
includes only the Clinic identified by that Responsibility Grant
(`SPEC-ORG-005` BR-8, BR-10).

---

### BR-5 — Veterinarian path

The `VETERINARIAN` path includes a Clinic only where all of the following
currently hold and together produce an effective Clinic-context capability
under `SPEC-ORG-005`:

* an active Organization Membership in the Veterinary Organization that
  operates the Clinic;
* an active Organization-scoped `VETERINARIAN` responsibility within that
  Membership;
* a Veterinarian Professional Profile;
* a current Veterinarian Clinic Assignment to that Clinic supported by that
  Membership.

The `VETERINARIAN` responsibility without a current Clinic Assignment includes
no Clinic: actual professional authority at a specific Clinic requires a valid
Veterinarian Clinic Assignment (`SPEC-ORG-005` §4 and BR-14).

---

### BR-6 — A Clinic Assignment is not, by itself, professional Clinic access

A current Veterinarian Clinic Assignment can remain in place after the
`VETERINARIAN` responsibility has ended, because responsibility changes do not
modify Clinic Assignments (`SPEC-ORG-006` BR-30). In that state the Assignment
provides no effective Clinic-context capability.

`SPEC-ORG-007` may report such a current Clinic Assignment. This
Specification must not return that Clinic unless an effective Clinic-context
capability still exists for it through some other current basis.

The two reads answer different questions:

* `SPEC-ORG-007` Clinic Assignments are relationship and context facts;
* `SPEC-ORG-008` Professional Clinics are current operational professional
  contexts.

Professional workflow navigation into a Clinic must use the Professional
Clinics defined here, not the mere existence of a Clinic Assignment.

This Specification does not redefine the Clinic Assignments reported by
`SPEC-ORG-007`.

---

### BR-7 — Relationships that do not include a Clinic

A Clinic is not included merely because of:

* a bare Organization Membership without an applicable responsibility;
* a Veterinarian Professional Profile alone;
* a Veterinarian Clinic Assignment alone (BR-6);
* a pending Organization Invitation or its proposed responsibilities
  (`SPEC-ORG-005` BR-23);
* an ended Organization Membership, Responsibility Grant, or Clinic
  Assignment;
* a responsibility in another Veterinary Organization;
* a Subscription or Entitlement;
* Guardianship, Care Authorization, or Appointment history.

---

### BR-8 — One entry per Clinic

Each returned Clinic appears exactly once, identified together with the
Veterinary Organization that operates it.

When several current bases provide capabilities for the same Clinic — for
example an Organization-scoped `RECEPTIONIST` responsibility and a
Clinic-scoped `ADMINISTRATOR` responsibility — the Clinic is still returned
once, with the combined effective capability set (BR-10).

Clinics of several Veterinary Organizations are returned together by one
read.

---

### BR-9 — Minimum Clinic identity, independent of publication

Each returned Clinic is identified by:

* its stable Clinic identifier;
* its current display name, where the Clinic has one;
* the stable identifier and display name of the Veterinary Organization that
  operates it.

The Clinic display name is the same display identity reported by
`SPEC-ORG-007` BR-4.

Published and unpublished Clinics are both returned. A Clinic without a
display name is returned with its stable identifier and an indication that no
display name is available; it is not omitted.

The read imposes no publication requirement, does not use or require public
Clinic Discovery (`SPEC-DIS-001`), and does not report publication state.

---

### BR-10 — Effective Clinic-context capabilities are returned per Clinic

For each returned Clinic, the result includes the complete set of effective
Clinic-context capability identifiers the acting User currently holds for that
Clinic, whichever current Organization-scoped or Clinic-scoped basis provides
them.

The set:

* contains only Clinic-context identifiers from the `SPEC-ORG-005` §5 catalog;
* is never empty for a returned Clinic (BR-2);
* is returned in deterministic order (BR-15).

Capability identifiers are domain authorization concepts, not client-side
permissions. They are advisory presentation context (BR-13).

---

### BR-11 — No Entitlement or Subscription information

The result does not report Entitlement availability.

Entitlements belong to the Veterinary Organization (INV-012) and are already
reported per Organization by `SPEC-ORG-007` BR-7. Clients may relate the two
results through the Organization identifier.

The result must not expose Subscription state, provider references, commercial
validity dates, or billing information.

Entitlement or Subscription state never includes or excludes a Clinic
(`SPEC-SUB-003` BR-3).

---

### BR-12 — Absence of Professional Clinics is a normal result

An authenticated User with no effective Clinic-context capability, including
a Guardian-only User or a User with only Organization-level context, receives
an empty Clinic list.

This is a normal result, not an authorization error, and does not affect the
User's Guardian capabilities.

---

### BR-13 — Professional Clinics are advisory, not authorization

The result exists to support presentation and navigation.

It must not be used as, or replace, the authorization or Entitlement decision
of any professional operation. Every operation at a listed Clinic, including
viewing the Clinic Appointment Schedule (`SPEC-APT-012`), re-evaluates the
acting User's current authorization when it is performed.

A stale or manipulated client-side copy of the Clinic list or its capabilities
must not authorize any operation (`SPEC-ORG-005` BR-26).

---

### BR-14 — Professional Clinics are derived, not stored

Reading Professional Clinics must not persist a Clinic list, professional
flag, role, snapshot, or capability set.

Each read derives the result from current authoritative domain state
(INV-019).

---

### BR-15 — Deterministic ordering

Clinics are ordered by:

1. Veterinary Organization display name;
2. Veterinary Organization identifier;
3. Clinic display name, with Clinics without a display name last;
4. Clinic identifier.

Capability identifiers within a Clinic are ordered by identifier.

---

### BR-16 — No pagination in Phase 1

The read returns the complete current Professional Clinic list in one result.

This is an intentional Phase 1 boundary, consistent with `SPEC-ORG-007`, not
an accidental omission. Bounded or paginated retrieval requires a separate
approved change.

That change is §11. `get_my_professional_clinics()` itself stays complete and
unpaginated; bounded, searchable retrieval of one Veterinary Organization's
Professional Clinics is the separate read defined there.

---

### BR-17 — Data minimization

The result must not include:

* Clinic location, address, or coordinates;
* Clinic contact information or description;
* Clinic services or opening hours;
* Appointment Availability or standard Appointment duration;
* publication state;
* staff, Memberships, Invitations, Responsibility Grants, or Clinic
  Assignments;
* Subscription or billing information;
* Pets, Guardianships, Appointments, Care Authorizations, or medical
  information.

---

### BR-18 — Consistency with SPEC-ORG-007

For the same authoritative domain state, the set of returned Clinics equals
the union of:

* every Clinic for which `SPEC-ORG-007` reports a Clinic-scoped effective
  capability; and
* every Clinic of every Veterinary Organization for which `SPEC-ORG-007`
  reports an Organization-scoped effective Clinic-context capability.

---

## 4. Read Contract

The read is exposed as:

    get_my_professional_clinics() returns jsonb

with the shape:

    {
      "clinics": [
        {
          "clinic_id": uuid,
          "clinic_display_name": text | null,
          "organization_id": uuid,
          "organization_display_name": text,
          "capabilities": [text, ...]
        }
      ]
    }

* `clinics` is always present and may be empty: `{"clinics":[]}` (BR-12).
* `clinic_display_name` is `null` when the Clinic has no display name (BR-9).
* `capabilities` follows BR-10 and BR-15.
* No other property is returned (BR-11, BR-17).

Authentication failures are rejected as follows, consistent with
`get_my_professional_context()`:

* a caller in the `anon` or `public` role holds no `EXECUTE` privilege on the
  read, so the call is rejected by PostgreSQL with SQLSTATE `42501` before the
  read is evaluated;
* an `authenticated` execution context with no authenticated subject is
  rejected by the read with SQLSTATE `28000`;
* an authenticated subject with no coherent MenizVet domain User is rejected by
  the read with SQLSTATE `28000`.

`EXECUTE` is deliberately not granted to `anon` merely to produce `28000`. A
valid authenticated User is never rejected for lacking professional context.

Security boundary:

* self-scoped; no User, Organization, or Clinic input parameter (BR-1);
* `SECURITY DEFINER`, `STABLE`, with an empty `search_path`;
* `EXECUTE` revoked from `public`, `anon`, and `authenticated`, and granted
  only to `authenticated`;
* no direct client `SELECT` grant on the underlying Clinic, Organization,
  Membership, Responsibility Grant, Professional Profile, or Clinic Assignment
  tables;
* no leakage of the existence, identity, or name of any Clinic for which the
  acting User holds no effective Clinic-context capability.

---

## 5. Scenarios

### Scenario: Owner sees every Clinic of the Organization, including unpublished and unnamed Clinics

Given Maria holds the Organization-scoped `OWNER` responsibility in Animalia Veterinary Group
And Animalia operates Animalia Madrid Centro, which is published
And Animalia operates Animalia Getafe, which is not published
And Animalia operates a newly created Clinic with no display name

When Maria views her Professional Clinics

Then all three Clinics are returned, each once
And the newly created Clinic is identified by its stable identifier with no display name
And no publication state is returned
And no Clinic includes `CLINICAL_CARE` or `CLINICAL_DOCUMENTATION`

---

### Scenario: Clinic created after the responsibility was granted is included

Given Maria holds the Organization-scoped `OWNER` responsibility in Animalia Veterinary Group
And Animalia later creates Animalia Alcobendas

When Maria views her Professional Clinics

Then Animalia Alcobendas is returned

---

### Scenario: Organization-scoped Administrator sees the same Clinics as an Owner

Given Carlos holds the Organization-scoped `ADMINISTRATOR` responsibility in Animalia Veterinary Group

When Carlos views his Professional Clinics

Then every Animalia Clinic is returned
And no Clinic of another Veterinary Organization is returned

---

### Scenario: Organization-scoped Receptionist sees every Clinic with Appointment capabilities only

Given Laura holds the Organization-scoped `RECEPTIONIST` responsibility in Animalia Veterinary Group

When Laura views her Professional Clinics

Then every Animalia Clinic is returned
And each Clinic's capabilities are exactly the `SPEC-ORG-005` `RECEPTIONIST` Appointment capabilities
And no Clinic includes a `CLINIC_MANAGE_*` capability

---

### Scenario: Clinic-scoped Receptionist sees only the covered Clinic

Given Ana holds a Clinic-scoped `RECEPTIONIST` responsibility for Animalia Getafe
And Animalia also operates Animalia Madrid Centro

When Ana views her Professional Clinics

Then only Animalia Getafe is returned

---

### Scenario: Clinic-scoped Administrator sees only the covered Clinic

Given Ana holds a Clinic-scoped `ADMINISTRATOR` responsibility for Animalia Getafe

When Ana views her Professional Clinics

Then only Animalia Getafe is returned
And its capabilities include `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`

---

### Scenario: Veterinarian sees only the currently assigned Clinic

Given Carlos holds the Organization-scoped `VETERINARIAN` responsibility in Animalia Veterinary Group
And Carlos has a Veterinarian Professional Profile
And Carlos is currently assigned to Animalia Madrid Centro
And Carlos is not assigned to Animalia Getafe

When Carlos views his Professional Clinics

Then only Animalia Madrid Centro is returned
And its capabilities are `APPOINTMENT_COMPLETE`, `APPOINTMENT_VIEW_SCHEDULE`, `CLINICAL_CARE`, and `CLINICAL_DOCUMENTATION`

---

### Scenario: Clinic Assignment without VETERINARIAN responsibility does not include the Clinic

Given Carlos is currently assigned to Animalia Madrid Centro
And Carlos's `VETERINARIAN` responsibility in Animalia has ended
And Carlos has no other applicable responsibility in Animalia

When Carlos views his Professional Clinics

Then Animalia Madrid Centro is not returned
And the result is not an error

---

### Scenario: VETERINARIAN responsibility without Clinic Assignment includes no Clinic

Given Carlos holds the Organization-scoped `VETERINARIAN` responsibility in Animalia Veterinary Group
And Carlos has no current Clinic Assignment

When Carlos views his Professional Clinics

Then the result contains no Clinic

---

### Scenario: Combined responsibilities produce one Clinic entry

Given Laura holds the Organization-scoped `RECEPTIONIST` responsibility in Animalia Veterinary Group
And Laura holds a Clinic-scoped `ADMINISTRATOR` responsibility for Animalia Getafe

When Laura views her Professional Clinics

Then Animalia Getafe is returned once
And its capabilities combine the Appointment and Clinic-administration capabilities
And no capability is repeated

---

### Scenario: Clinics of several Organizations are returned together

Given Dr. Garcia holds the Organization-scoped `ADMINISTRATOR` responsibility in Animalia Veterinary Group
And Dr. Garcia holds a Clinic-scoped `RECEPTIONIST` responsibility for VetCare Toledo

When Dr. Garcia views her Professional Clinics

Then the Animalia Clinics and VetCare Toledo are returned by the same read
And they are ordered as defined by BR-15

---

### Scenario: Bare Membership includes no Clinic

Given Maria has an active Membership in Animalia Veterinary Group
And Maria holds no active responsibility in that Membership

When Maria views her Professional Clinics

Then the result is `{"clinics":[]}`
And the result is not an error

---

### Scenario: Guardian-only User receives an empty result

Given Lucia is an authenticated User
And Lucia has no Organization Membership, Professional Profile, or Clinic Assignment

When Lucia views her Professional Clinics

Then the result contains no Clinic
And the result is not an error

---

### Scenario: Ended Membership includes no Clinic

Given Carlos's Membership in VetCare ended on 2027-03-31

When Carlos views his Professional Clinics after that date

Then no VetCare Clinic is returned

---

### Scenario: Pending Invitation includes no Clinic

Given Ana has a pending Invitation to Animalia Veterinary Group proposing a Clinic-scoped `RECEPTIONIST` responsibility for Animalia Madrid Centro

When Ana views her Professional Clinics

Then Animalia Madrid Centro is not returned

---

### Scenario: Listed Clinic does not authorize a later operation

Given Laura's Professional Clinics previously included Animalia Getafe
And Laura's `RECEPTIONIST` responsibility has since ended

When Laura attempts to view Animalia Getafe's Appointment schedule

Then access is denied
And the earlier Professional Clinics result does not authorize the operation

---

### Scenario: Another User's Clinics are not revealed

Given Maria and Carlos both belong to Animalia Veterinary Group
And Carlos holds a Clinic-scoped `ADMINISTRATOR` responsibility for Animalia Getafe
And Maria holds a Clinic-scoped `RECEPTIONIST` responsibility for Animalia Madrid Centro only

When Maria views her Professional Clinics

Then only Animalia Madrid Centro is returned
And nothing derived from Carlos's relationships is returned

---

## 6. Edge Cases

### Organization with no Clinics

An Owner or Administrator of a Veterinary Organization that operates no Clinic
receives no Clinic for that Organization. `SPEC-ORG-007` still reports the
Organization context.

---

### Clinic without a public profile

A Clinic that has no public profile information at all is still returned when
BR-2 is satisfied, with no display name (BR-9).

---

### Clinic-scoped grant overlapping an Organization-scoped grant

The Clinic is returned once with the combined capability set (BR-8). Unlike
`SPEC-ORG-007`, which reports capabilities per Membership and scope rather
than per Clinic, this read reports the complete effective set per Clinic.

---

### Concurrent relationship change

The result reflects authoritative state at evaluation time. A later
relationship change is reflected by a later read; operations re-evaluate
independently (BR-13).

---

## 7. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-005 — Organization and Clinic are different concepts.**
* **INV-006 — Organization Membership is temporal.**
* **INV-007 — Veterinarian Clinic Assignment is temporal.**
* **INV-008 — A Veterinarian may practice at multiple Clinics.**
* **INV-012 — Subscription belongs to the Organization.**
* **INV-015 — Private operations require an authenticated identity.**
* **INV-019 — Professional context is derived, not stored.**

---

## 8. Dependencies

* SPEC-ID-003 — Authenticate User
* SPEC-ORG-003 — Accept Organization Invitation
* SPEC-ORG-004 — End Organization Membership
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
* SPEC-ORG-006 — Change Organization Membership Responsibilities
* SPEC-ORG-007 — View My Professional Context
* SPEC-CLI-001 — Create Clinic
* SPEC-CLI-003 — Publish Clinic
* SPEC-CLI-004 — Manage Clinic Public Profile
* SPEC-VET-001 — Create Veterinarian Professional Profile
* SPEC-VET-004 — Assign Veterinarian to Clinic
* SPEC-VET-005 — End Veterinarian Clinic Assignment
* SPEC-SUB-003 — Evaluate Professional Entitlements (referenced only to state
  that Entitlement does not affect inclusion, BR-11)

Consumer:

* SPEC-APT-012 — View Clinic Appointment Schedule

---

## 9. Out of Scope

This Specification does not define:

* reading another User's professional information;
* Clinic configuration reads or management (location, public profile,
  services, opening hours, Availability, standard duration);
* Clinic publication state or publication management;
* listing Organization Members, Invitations, Responsibility Grants, or Clinic
  Assignments;
* Entitlement availability or Subscription details;
* per-operation evaluation of whether a specific operation would succeed;
* new capability identifiers or changes to the responsibility-to-capability
  mapping of `SPEC-ORG-005`;
* changes to `SPEC-ORG-007` or to the Clinic Assignments it reports;
* public Clinic Discovery;
* Clinic lifecycle, inactivity, or archival (REQ-CLI-006);
* pagination or bounded retrieval of the complete read (BR-16); the paged
  read of one Organization's Professional Clinics is defined by §11;
* the Clinic Appointment Schedule itself;
* presentation or navigation of professional functionality in the client,
  except the client use of the §11 read (BR-26).

### Follow-up note — Clinic Appointment Schedule

The Clinic Appointment Schedule read, `get_clinic_appointment_schedule`, already
exists for `SPEC-APT-012`. A Professional Clinic returned here is the expected
entry point into it; that read independently re-authorizes the caller.

The immediate next schedule/UI gap is that its result identifies each
Appointment's Pet only by `pet_id` and contains no Pet display name, although
Pet identity is core schedule information (`SPEC-APT-012` BR-11 and §4). That
gap is recorded here only; it is neither designed nor changed by this
Specification.

---

## 10. Verification Notes

Verification must demonstrate, using rollback-only fixtures that retain no
synthetic state, that:

1. a caller in the `anon` or `public` role cannot execute the read and is
   rejected with `42501` before the read is evaluated; an `authenticated`
   execution context with no authenticated subject, and an authenticated
   subject with no coherent domain User, are each rejected with `28000`;
2. a Guardian-only User, a User with only a Veterinarian Professional Profile,
   and a User with a bare Membership each receive `{"clinics":[]}` without
   error;
3. an Organization-scoped `OWNER` receives every Clinic of the Organization,
   including published, unpublished, and unnamed Clinics, and a Clinic created
   after the grant;
4. an Organization-scoped `ADMINISTRATOR` receives the same Clinic set as an
   Organization-scoped `OWNER` of the same Organization;
5. a Clinic-scoped `ADMINISTRATOR` receives only the covered Clinic, including
   `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`, and never a sibling Clinic;
6. an Organization-scoped `RECEPTIONIST` receives every Clinic of the
   Organization, and a Clinic-scoped `RECEPTIONIST` only the covered Clinic,
   each with exactly the `RECEPTIONIST` Appointment capabilities and no
   `CLINIC_MANAGE_*` capability;
7. a `VETERINARIAN` with a Professional Profile and a current Clinic Assignment
   receives only the assigned Clinic, with exactly the `SPEC-ORG-005`
   Veterinarian capabilities;
8. a current Clinic Assignment without an active `VETERINARIAN`
   responsibility includes no Clinic, while `SPEC-ORG-007` may still report the
   Assignment;
9. an active `VETERINARIAN` responsibility without a current Clinic Assignment
   includes no Clinic;
10. an ended Membership, an ended Responsibility Grant, and an ended Clinic
    Assignment each stop including the Clinic through that basis;
11. a pending Invitation's proposed responsibility includes no Clinic;
12. a responsibility in one Veterinary Organization never includes a Clinic of
    another;
13. combined bases for the same Clinic produce exactly one Clinic entry with
    the combined capability set and no duplicate capability;
14. Clinics of several Veterinary Organizations are returned by one read in
    the BR-15 order, stable across repeated reads, including tied
    Organization and Clinic display names and Clinics without a display name;
15. capability identifiers within each Clinic are Clinic-context identifiers
    only, ordered by identifier, and never empty;
16. parity with the authoritative evaluation: for every Clinic and every
    Clinic-context catalog capability, the capability appears for that Clinic
    in the result if and only if `user_has_clinic_capability` holds for the
    acting User, and no Clinic for which any such capability holds is missing;
17. consistency with `SPEC-ORG-007` as defined by BR-18;
18. the result contains only the properties of §4: no publication state,
    location, contact, description, services, opening hours, Availability,
    duration, staff, Memberships, Invitations, Assignments, Entitlements,
    Subscription, Pet, Care Authorization, or medical information;
19. no Clinic for which the acting User holds no effective Clinic-context
    capability is revealed, by identifier or by name;
20. a Clinic returned earlier does not authorize a later operation once the
    supporting relationship has ended;
21. reading Professional Clinics writes no rows and persists no Clinic list or
    capability set;
22. `EXECUTE` is held only by `authenticated` (not `public` or `anon`), the
    function is `SECURITY DEFINER` and `STABLE` with an empty `search_path`,
    and the underlying tables remain non-selectable by `anon` and
    `authenticated`;
23. existing `SPEC-ORG-007` and other regression suites continue to pass
    unchanged.

---

## 11. Organization Professional Clinics page — Phase 1

Defined by **Organization Clinics list with search and pagination — Phase 1**.
The Professional Clinics screen of the selected Veterinary Organization reads
that Organization's Professional Clinics one page at a time, optionally
narrowed by a Clinic name search, instead of reading the complete result of
§4 and filtering it on the device.

This read adds no authority, no capability, no stored state, and no write.
For the same authoritative state and instant, its rows are a subset of what
`get_my_professional_clinics()` (§4) returns. `get_my_professional_clinics()`
is unchanged — signature, result, order, and grants — and every other
consumer keeps using it.

### BR-19 — Read contract

    get_my_organization_professional_clinics(
        p_organization_id    uuid,
        p_search             text    default null,
        p_after_display_name text    default null,
        p_after_clinic_id    uuid    default null,
        p_limit              integer default 20
    ) returns table (
        clinic_id           uuid,
        clinic_display_name text
    )

* `clinic_display_name` is the BR-9 display identity, `null` when the Clinic
  has no display name.
* No other column is returned: no capabilities, Organization identity,
  location, contact, publication state, Entitlement, or total count (BR-11,
  BR-17).
* The read is self-scoped like §4: it accepts no User input, and
  `p_organization_id` only narrows the acting User's own Professional
  Clinics; it never widens them (BR-1).

Security boundary, as §4: `SECURITY DEFINER`, `STABLE`, empty `search_path`;
`EXECUTE` revoked from `public`, `anon`, `authenticated`, and `service_role`,
and granted only to `authenticated`; exactly one overload; no direct client
`SELECT` grant on any underlying table. Any internal helper of the read (for
example the search normalization of BR-22) is executable by no client role.

### BR-20 — Evaluation order and errors

1. Authentication and a coherent domain User, exactly as §4: no `EXECUTE`
   for `anon` or `public` (`42501` by PostgreSQL); an `authenticated` context
   with no subject, or a subject with no coherent domain User, fails with
   `28000` before any input is considered.
2. Input validation, failing with `22023` `Professional Clinics page is
   invalid` when:
   * `p_limit` is `null` or outside 1–50;
   * `p_after_display_name` is not `null` while `p_after_clinic_id` is
     `null`;
   * `p_search` is longer than 100 characters, as received.

   Validation never depends on `p_organization_id`, so an invalid input
   reveals nothing about any Organization.
3. The read (BR-21 to BR-24).

The read raises no authorization error for any Organization. An unknown,
`null`, or inaccessible `p_organization_id` produces an empty page (BR-21).

### BR-21 — Inclusion is exactly BR-2, restricted to one Organization

A Clinic can be returned if and only if, at the evaluation instant:

* it is operated by `p_organization_id`; and
* it is one of the acting User's Professional Clinics under BR-2 to BR-7:
  there is at least one Clinic-context capability of the `SPEC-ORG-005`
  catalog for which `user_has_clinic_capability` holds for the acting User
  and that Clinic.

Inclusion is decided by that same authoritative predicate. It must not be
replaced by a responsibility-to-capability mapping, a role shortcut, a
Membership check, or any other separately maintained rule.

Before evaluating the predicate, the implementation may narrow the candidate
Clinics only by a condition that every branch of the predicate necessarily
requires, for example a current Organization Membership of the acting User
in `p_organization_id`. Such narrowing limits work; it never decides
inclusion. It must never exclude a Clinic that §4 returns for that
Organization.

Consequently, each of the following produces the same empty page, without
error, and none can be distinguished from the others:

* an unknown or `null` Organization;
* an Organization in which the acting User has no relationship, or only
  ended, pending, or non-qualifying ones (BR-7);
* an Organization of which the acting User has no Professional Clinic;
* an Organization that operates no Clinic.

The client tells these apart only through the authorized `SPEC-ORG-007`
context it already reads (BR-26), never through this read.

### BR-22 — Name search

`p_search` narrows the BR-21 Clinics by Clinic display name. The narrowing is
applied in the read, before ordering and before `p_limit` is applied, never
to a page that was already cut.

**Search normalization.** `N(text)` is computed, in this order, by:

1. Unicode compatibility decomposition (NFKD);
2. removing every combining mark in U+0300–U+036F;
3. the Unicode root-locale (`und`) lowercase mapping, applied with one fixed
   collation chosen by the read. It must not depend on the database's default
   collation or locale, or on the collation of the value passed in;
4. replacing every run of whitespace with one space (U+0020). Whitespace
   includes space, tab, line breaks, no-break space (U+00A0), and the Unicode
   space separators;
5. removing leading and trailing spaces.

**Matching.**

* When `p_search` is `null`, or `N(p_search)` is empty, there is no
  narrowing.
* Otherwise a Clinic matches if and only if it has a display name and
  `N(p_search)` occurs as a contiguous substring of `N(display name)`.
* Matching is literal. No character of the search (`%`, `_`, `\`, `[`, `*`,
  quotes, …) has wildcard or pattern meaning.
* A Clinic without a display name never matches a non-empty search. Its
  localized "unnamed Clinic" label is client presentation, not data.
* Only the display name is searched; no other Clinic or Organization
  information is (BR-17).

Accepted consequences of `N`:

| Search | Matches the display name |
|---|---|
| `clinica`, `Clínica`, `CLÍNICA` | `Clínica Centro` |
| `pena` | `Peña` (accepted tolerant behavior) |
| `peña` | `Pena` (folding is symmetric) |
| decomposed `Peña` (`n` + U+0303) | `Peña` composed, and the reverse |
| `veterinaria   peña`, `  vet  ` | `Clínica Veterinaria Peña` |
| `clinica centro` | `Clínica` + two spaces + `Centro`; `Clínica` + U+00A0 + `Centro` |
| `ﬁnca` (ligature), full-width `Ｃｌｉｎｉｃａ` | `finca`, `clinica` |
| `%`, `_` | only names containing that character |

Known, accepted limits:

* characters without a decomposition are not folded to ASCII: `ß`, `ø`, `œ`,
  `æ`, and `ł` stay distinct from `ss`, `o`, `oe`, `ae`, and `l`. Their
  uppercase forms still match their lowercase forms;
* combining marks outside U+0300–U+036F are kept;
* zero-width characters (for example U+200B) are not whitespace;
* the root-locale mapping is context-sensitive for Greek final sigma, so
  `ΟΔΟΣ` lowercases to `οδος`.

`N` is derived at read time. No normalized value, search term, or index
entry is persisted for this read (BR-14), and this Specification requires no
database extension.

### BR-23 — Order and cursor

Rows follow the BR-15 order, which inside one Organization reduces to:

1. Clinic display name, in the same collation §4 orders by, with Clinics
   without a display name last;
2. `clinic_id`.

This is one total order. The ordering of the rows and the cursor comparison
below use exactly the same key: the same expressions, collation, null
placement, and tie-breaker. The cursor never uses a normalized or otherwise
different value.

The search only removes rows. It never changes their relative order.

The cursor is the complete `(clinic_display_name, clinic_id)` of the previous
page's last row, exactly as returned: `p_after_display_name` is that name, or
`null` when the row had none, and `p_after_clinic_id` is its id. The first
page has both `null`. Each later page holds the next `p_limit` included,
matching rows strictly after the cursor in the order above:

* after a named cursor: named rows whose `(display name, clinic_id)` sorts
  after the cursor, then every unnamed row;
* after an unnamed cursor: unnamed rows with a greater `clinic_id`.

Identical display names are told apart only by `clinic_id`. Canonically
equivalent but differently encoded names (NFC and NFD) are distinct strings,
ordered deterministically. They are equal only for the search (BR-22).

A cursor is only a position in the order. It is never evidence of access:
a cursor naming a Clinic that is not included reveals nothing and returns
only included rows.

A page of exactly `p_limit` rows means more may exist. A shorter or empty
page ends the list. No total count is returned.

### BR-24 — Snapshot and consistency between pages

Each call is one statement: it observes one snapshot and uses one evaluation
instant for every "current" decision.

Between calls, state may change:

* a Clinic that stops being included, or is renamed so it no longer matches,
  is not returned by later pages;
* a concurrent rename may move a Clinic across the cursor, so the remaining
  pages may miss it or return it again. This is accepted. The client
  deduplicates by `clinic_id`, and a refresh (a new first read) is
  authoritative;
* a Clinic that becomes included and sorts before the cursor appears only on
  a new first read.

A cursor belongs to the search that produced it. When the search changes,
the client discards the cursor and restarts from the first page (BR-26). The
read does not bind a cursor to a search and need not recognize a cursor from
an earlier search. Whatever cursor is sent, it returns only included rows
that match the search of that call (BR-21, BR-22).

### BR-25 — Derived and side-effect free

The read writes nothing, takes no lock, and persists no Clinic list,
capability set, search term, cursor, or normalized name (BR-14, INV-019).
Subscription and Entitlement state are not consulted (BR-11). Publication
state is neither consulted nor returned (BR-9).

### BR-26 — Client use

The Professional Clinics screen of the selected Organization:

* reads pages of 20 Clinics and offers "Load more" while the last page was
  full. It never downloads the complete list to search or paginate it on the
  device;
* takes the Organization's heading name, whether Add Clinic is offered
  (`SPEC-CLI-001` BR-17), and whether there is any Organization context at
  all (no selection, or a selection the `SPEC-ORG-007` context no longer
  contains) from the authorized professional context. It never takes these
  from an empty page of this read;
* shows each Clinic as one compact row inside a single list: the display
  name, or the localized unnamed-Clinic label, and a chevron. The whole row
  opens the professional Clinic screen by id, which re-reads and
  re-authorizes. No location, publication state, or capability is shown;
* distinguishes an empty first page without a search, where the Organization
  has no Professional Clinic for the User (the existing empty state, with
  Add Clinic as its primary action when offered), from an empty first page
  with a search, where no Clinic matches (a distinct message that offers to
  clear the search);
* sends the search after the User pauses typing, limits it to 100
  characters, and restarts at once without a search when it is cleared;
* on every change of the submitted search, at once: withdraws every row read
  for the previous search, discards the cursor, shows the loading state, and
  starts a new first read. The answer to any older request is ignored. "No
  matches" appears only once the new search's first page has arrived empty;
* on every focus, for example back from a Clinic or from a newly created
  Clinic's settings, restarts from the first page and keeps the current
  search;
* never shows a Clinic twice: a row whose `clinic_id` is already shown is not
  appended again;
* keeps Clinic creation, its confirmation, the recovery of an uncertain
  creation with the same key (`SPEC-CLI-001` BR-18), and the existing
  navigation unchanged.

The list remains advisory (BR-13). Every operation at a listed Clinic
re-authorizes on the backend.

---

## 12. Organization Professional Clinics page — Verification Notes

In addition to §10, verification must demonstrate, using rollback-only
fixtures that retain no synthetic state, that:

24. `anon` and `public` cannot execute the read (`42501` before evaluation);
    an `authenticated` context with no subject, and a subject with no
    coherent domain User, fail with `28000` before any input validation; only
    `authenticated` holds `EXECUTE` (not `public`, `anon`, or `service_role`);
    the function is `STABLE`, `SECURITY DEFINER`, has an empty `search_path`,
    and has exactly one overload; every internal helper is executable by no
    client role;
25. `p_limit` `null`, 0 and 51, a named cursor without an id, and a 101-character
    search each fail with `22023`; a 100-character search and limits 1 and
    50 are accepted; each failure is identical whatever `p_organization_id`
    is, including unknown and `null`;
26. parity without a search: for every fixture actor of §10 (Organization-
    and Clinic-scoped `OWNER`, `ADMINISTRATOR` and `RECEPTIONIST`; a
    `VETERINARIAN` with and without a current Clinic Assignment; an
    Assignment without `VETERINARIAN`; a bare, ended, or pending
    relationship; a Guardian-only User), for every Organization, and for
    every page size from 1 to one more than the number of rows,
    concatenating the pages equals the §4 result restricted to that
    Organization, with the same ids, display names, and order;
27. completeness of any candidate narrowing: a Clinic included only through
    an Organization-scoped grant, only through a Clinic-scoped grant, or only
    through a current Veterinarian Clinic Assignment is returned; for every
    Clinic of the Organization, it is returned if and only if some
    Clinic-context catalog capability satisfies `user_has_clinic_capability`
    for the acting User;
28. an unknown Organization, `null`, an Organization with only ended or
    pending relationships, another User's Organization, and an Organization
    with no Clinic each return an empty page, identical to one another, with
    no error;
29. no row ever belongs to another Organization or to a Clinic without an
    effective Clinic-context capability, under any search, cursor, or page
    size, including a cursor that names such a Clinic;
30. ordering and cursors: identical display names are split across page
    boundaries in `clinic_id` order; unnamed Clinics come last in
    `clinic_id` order; a cursor at the last named row continues with the
    unnamed rows; a cursor at the last row returns an empty page; for stable
    state no row is repeated or skipped, for every page size;
31. the search is applied before the limit: when non-matching Clinics sort
    before the matching ones and outnumber `p_limit`, the first page still
    holds matching Clinics. For each search of item 32 and every page size,
    concatenating the pages equals the parity result of item 26 narrowed by
    BR-22;
32. normalization and matching, against display names stored both composed
    and decomposed:
    * `clinica`, `Clínica` and `CLÍNICA` match `Clínica Centro`;
    * `pena` matches `Peña`, and `peña` matches `Pena`;
    * decomposed and composed `Peña` match each other;
    * double spaces, tab, no-break space, and leading or trailing spaces in
      the search or the name match single-spaced text;
    * `ﬁ` and full-width letters match their plain forms;
    * `%`, `_`, `\` and `[` match only themselves;
    * `null`, `''` and `'   '` do not narrow;
    * an unnamed Clinic never matches a non-empty search;
    * Unicode uppercase letters (`Ø`, `Œ`, `Æ`, `Ł`, `İ`, Cyrillic) match
      their lowercase forms;
    * the Unicode space separators, U+202F, U+3000, U+2028, and U+0085 count
      as whitespace;
    * `ß` and `ø` are not folded to ASCII, and U+200B is not whitespace (the
      documented limits);
33. lowercase mapping does not depend on the default collation: the same
    results hold when the search and the display names carry collation `"C"`
    or a libc collation;
34. whatever cursor is sent with a search, including one produced by another
    search, only included rows matching that search are returned;
35. between pages, a Clinic whose supporting relationship ended, or that was
    renamed so it no longer matches, is not returned by a later page; a
    Clinic that becomes included and sorts after the cursor appears on a
    later page; a Clinic renamed across the cursor may be missed or returned
    again, and is never returned twice within one page;
36. the result has exactly the two columns of BR-19 and no capability,
    Organization identity, location, publication state, Entitlement, or
    count;
37. the read writes no rows, takes no lock, and persists nothing;
    `get_my_professional_clinics()` keeps its signature, result, order, and
    grants; the §10 suite and the other existing regression suites pass
    unchanged;
38. client: a change of search withdraws the previous rows at once and shows
    the loading state; a change while a page is in flight ignores the older
    answer; "no matches" appears only after the new search's first page
    arrived empty; clearing the search restarts without a search; a focus
    restarts the first page and keeps the search; "Load more" never appends a
    `clinic_id` already shown;
39. client: the empty state without a search, with Add Clinic offered only
    under advisory `ORGANIZATION_CREATE_CLINICS`, the no-Organization-context
    state, Clinic creation and confirmation, the same-key recovery of an
    uncertain creation, and navigation to the professional Clinic screen
    behave as before this change.

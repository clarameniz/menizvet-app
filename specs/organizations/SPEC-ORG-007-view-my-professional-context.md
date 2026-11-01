# SPEC-ORG-007 — View My Professional Context

**Status:** APPROVED
**Requirements:** REQ-ORG-008, REQ-ID-005, REQ-ORG-005, REQ-SUB-003
**Domain:** Organizations
**Priority:** P1

## 1. Intent

Allow an authenticated User to determine, from trusted backend information,
which professional contexts they currently hold, so that the single MenizVet
application can present professional functionality alongside Guardian
functionality.

There is no stored professional User type or flag. Professional context is
derived at read time from the User's current domain relationships and from
the current Entitlements of the Organizations involved.

The result includes the User's current responsibilities and the effective
capabilities derived from them server-side, so that the client does not
reimplement the responsibility-to-capability mapping defined by
`SPEC-ORG-005` in order to decide which professional functionality to
present.

Reading professional context grants no capability. Every professional
operation continues to evaluate its own authorization, Entitlement, and other
preconditions when it is performed.

See
[ADR-010](../../docs/decisions/ADR-010-single-mobile-app-with-derived-professional-context.md).

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.

---

## 3. Business Rules

### BR-1 — Only the acting User's own context is returned

The result describes only the acting User.

It must not reveal another User's Memberships, responsibilities, capabilities,
professional identity, Clinic Assignments, or personal information.

---

### BR-2 — Only current relationships are returned

The result includes only relationships that are current at evaluation time:

* active Organization Memberships;
* active Organization Responsibility Grants and their scope;
* current Veterinarian Clinic Assignments.

Ended Memberships, ended Responsibility Grants, and ended Clinic Assignments
are excluded, and contribute no effective capability.

Historical relationships remain preserved in the domain; they are simply not
part of current professional context.

---

### BR-3 — Returned context

For the acting User, the result includes:

* each active Organization Membership, identifying its Veterinary Organization
  by stable Organization identifier and Organization display name;
* the active responsibilities within each Membership, with Organization or
  Clinic scope;
* the current effective capabilities for each Membership (BR-5);
* whether the User has a Veterinarian Professional Profile;
* each current Veterinarian Clinic Assignment, identifying its Clinic (BR-4)
  and its Veterinary Organization;
* Entitlement availability for each Organization (BR-7).

Responsibilities remain part of the result even though effective capabilities
are also returned.

---

### BR-4 — Minimum Clinic display identity

Wherever the result refers to a Clinic — a Clinic-scoped responsibility, a
Clinic-scoped effective capability, or a current Veterinarian Clinic
Assignment — it identifies that Clinic by:

* its stable Clinic identifier;
* its current display name, where the Clinic has one.

This Clinic identity must be supplied by the professional-context read itself.
It must be available regardless of whether the Clinic is published, and it
must not require the client to perform a public Clinic Discovery read.

The result must not expose any other Clinic configuration, such as location,
contact details, description, services, opening hours, scheduling timezone,
Appointment Availability, standard Appointment duration, or publication state.

A Clinic may not yet have a display name before it is prepared for publication
(`SPEC-CLI-004`). In that case the Clinic is still identified by its stable
identifier, and the result indicates that no display name is available rather
than failing or omitting the Clinic.

---

### BR-5 — Effective capabilities are returned

For each active Membership, the result includes the effective capability
identifiers currently derived for the acting User under `SPEC-ORG-005` from
current authoritative relationships: active Membership, active Responsibility
Grants and their scope, and, where `SPEC-ORG-005` requires them, the
Veterinarian Professional Profile and current Clinic Assignment.

Capability identifiers are those defined by `SPEC-ORG-005`. They are domain
authorization concepts, not client-side permissions.

Each effective capability is scoped:

* **Organization scope** — the capability applies within the identified
  Veterinary Organization's context, for example a capability derived from an
  active Organization-scoped `OWNER` or `ADMINISTRATOR` responsibility;
* **Clinic scope** — the capability applies only to one identified Clinic
  (BR-4), for example a capability derived from a Clinic-scoped
  `ADMINISTRATOR` or `RECEPTIONIST` responsibility, or a Veterinarian
  capability that `SPEC-ORG-005` provides only within a Clinic where the User
  holds a current Clinic Assignment and satisfies the applicable professional
  requirements.

Effective capabilities must be derived by the same authoritative evaluation
that protected operations use, not by a separately maintained mapping that
could diverge from `SPEC-ORG-005`.

This includes every capability in the `SPEC-ORG-005` Phase 1 catalog. For
example, `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` is returned with Organization
scope when derived from an active Organization-scoped `OWNER` or
`ADMINISTRATOR` responsibility, and with Clinic scope, identifying that Clinic,
when derived from an active Clinic-scoped `ADMINISTRATOR` responsibility. It is
never returned because of `RECEPTIONIST`, `VETERINARIAN`, or a Clinic
Assignment.

---

### BR-6 — A returned capability does not guarantee that an operation succeeds

A returned effective capability means only that the acting User's current
relationships provide that capability in the stated scope at evaluation time.

It does not mean that an operation using that capability will succeed.
Each protected operation still evaluates, when it is performed, its own:

* authorization, re-derived from current relationships;
* required professional Entitlement;
* lifecycle and state preconditions;
* Care Authorization and Medical Access Control, where applicable;
* Clinic Assignment currency and other professional requirements;
* any other precondition defined by its own Specification.

---

### BR-7 — Entitlement availability is reported separately per Organization

For each Veterinary Organization in which the User has an active Membership,
the result reports whether each Phase 1 normal professional Entitlement is
currently available:

* `APPOINTMENT_MANAGEMENT`;
* `PROFESSIONAL_SCHEDULING`;
* `CLINICAL_CARE`;
* `CLINICAL_DOCUMENTATION`.

Availability is evaluated at read time as defined by `SPEC-SUB-003`.

Entitlement availability is reported separately from capability availability.
Neither implies the other: a User may hold a capability while the Organization
lacks the Entitlement a paid operation requires, and an Organization may hold
an Entitlement while the User lacks the capability.

The result must not expose Subscription commercial details such as provider
references, commercial validity dates, or billing information. Subscription
state and validity are available only through the separately authorized
status read of `SPEC-SUB-002` §15.

This supports distinguishing a commercial denial from an authorization denial
(`SPEC-SUB-003` BR-35).

---

### BR-8 — Absence of professional context is a normal result

A User with no active Organization Membership, no Veterinarian Professional
Profile, and no current Clinic Assignment receives an empty professional
context.

This is a normal result, not an error, and does not affect the User's Guardian
capabilities.

---

### BR-9 — Professional context is advisory, not authorization

The result exists to support presentation.

It must not be used as, or replace, the authorization or Entitlement decision
of any professional operation.

A client that presents or hides professional functionality based on this result
is not a security boundary. A stale or manipulated client-side copy of
responsibilities, capabilities, or Entitlement availability must not authorize
any operation.

---

### BR-10 — Professional context is derived, not stored

Reading professional context must not persist a professional User flag, role,
snapshot, responsibility summary, or effective capability set.

Each read derives the result from current authoritative domain state.

---

### BR-11 — No protected medical information

The result must not include Pet, Guardianship, Appointment, Care Authorization,
or medical information.

---

## 4. Scenarios

### Scenario: Guardian-only User has an empty professional context

Given Lucia is an authenticated User
And Lucia is the Guardian of Luna
And Lucia has no Organization Membership, Professional Profile, or Clinic Assignment

When Lucia views her professional context

Then the result contains no professional context
And the result is not an error
And Lucia's Guardian capabilities are unaffected

---

### Scenario: Organization Owner sees responsibility, effective capabilities, and separate Entitlement availability

Given Maria has an active Membership in Animalia Veterinary Group
And Maria holds the Organization-scoped `OWNER` responsibility
And Animalia's current Subscription is `PENDING`

When Maria views her professional context

Then the result identifies Animalia Veterinary Group by its identifier and display name
And the result includes her `OWNER` responsibility with Organization scope
And the result includes Organization-scoped effective capabilities derived from `OWNER` under `SPEC-ORG-005`, such as `ORGANIZATION_INVITE_MEMBERS`, `ORGANIZATION_CREATE_CLINICS`, `CLINIC_MANAGE_PUBLICATION`, `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`, and `APPOINTMENT_CONFIRM`
And the result does not include `CLINICAL_CARE` or `CLINICAL_DOCUMENTATION` for Maria
And every Phase 1 normal professional Entitlement is reported as unavailable for Animalia

---

### Scenario: Invited Veterinarian sees Clinic-scoped capabilities for the assigned Clinic only

Given Carlos accepted an Invitation to Animalia Veterinary Group
And Carlos holds the Organization-scoped `VETERINARIAN` responsibility
And Carlos has a Veterinarian Professional Profile
And Carlos is currently assigned to Animalia Madrid Centro
And Carlos is not assigned to Animalia Getafe
And Animalia's Subscription is `ACTIVE` and commercially valid

When Carlos views his professional context

Then the result includes his Membership, `VETERINARIAN` responsibility, Professional Profile, and Clinic Assignment
And the Clinic Assignment identifies Animalia Madrid Centro by its identifier and display name
And the result includes `CLINICAL_CARE`, `CLINICAL_DOCUMENTATION`, `APPOINTMENT_VIEW_SCHEDULE`, and `APPOINTMENT_COMPLETE` scoped to Animalia Madrid Centro
And the result includes no effective capability scoped to Animalia Getafe
And the result does not include `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Carlos
And `CLINICAL_CARE` is reported as an available Entitlement for Animalia
And Carlos holds no Subscription of his own

---

### Scenario: Veterinarian responsibility without a current Clinic Assignment provides no clinical capability

Given Carlos holds the Organization-scoped `VETERINARIAN` responsibility in Animalia Veterinary Group
And Carlos has no current Clinic Assignment in Animalia

When Carlos views his professional context

Then the result includes his `VETERINARIAN` responsibility
And the result includes no `CLINICAL_CARE` or `CLINICAL_DOCUMENTATION` capability

---

### Scenario: Clinic-scoped responsibility at an unpublished Clinic includes minimum Clinic identity

Given Ana holds a Clinic-scoped `RECEPTIONIST` responsibility for Animalia Getafe
And Animalia Getafe is not published

When Ana views her professional context

Then the responsibility identifies Animalia Getafe by its stable identifier and display name
And the result includes Appointment capabilities scoped to Animalia Getafe only
And no public Discovery read is required to obtain that identity
And the result does not include Animalia Getafe's location, opening hours, services, availability, or publication state

---

### Scenario: Clinic-scoped Administrator receives Veterinarian Assignment management for that Clinic only

Given Ana holds a Clinic-scoped `ADMINISTRATOR` responsibility for Animalia Getafe
And Animalia Veterinary Group also operates Animalia Madrid Centro

When Ana views her professional context

Then the result includes `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` scoped to Animalia Getafe, identified by its identifier and display name
And the result does not include that capability for Animalia Madrid Centro or with Organization scope

---

### Scenario: Clinic without a display name is still identified

Given Ana holds a Clinic-scoped `ADMINISTRATOR` responsibility for a newly created Clinic
And that Clinic has no display name yet

When Ana views her professional context

Then the responsibility identifies the Clinic by its stable identifier
And the result indicates that no display name is available
And the Clinic is not omitted from the result

---

### Scenario: Capability without Entitlement does not make a paid operation succeed

Given Maria's professional context reports `APPOINTMENT_CONFIRM` for Animalia
And the same context reports `APPOINTMENT_MANAGEMENT` as unavailable for Animalia

When Maria attempts to confirm an Appointment at an Animalia Clinic

Then the operation is denied for lack of professional Entitlement
And capability availability and Entitlement availability were reported independently

---

### Scenario: Capability and Entitlement do not replace operation preconditions

Given Carlos's professional context reports `CLINICAL_CARE` scoped to Animalia Madrid Centro
And `CLINICAL_CARE` is reported as an available Entitlement for Animalia
And Luna has no active Care Authorization for Animalia Madrid Centro

When Carlos attempts to create a Clinical Encounter for Luna at Animalia Madrid Centro

Then the operation is denied
And the returned capability did not authorize the operation

---

### Scenario: Ended relationships are excluded

Given Carlos's Membership in VetCare ended on 2027-03-31

When Carlos views his professional context after that date

Then VetCare is not part of his current professional context
And no effective capability for VetCare is returned
And the historical Membership remains preserved in the domain

---

### Scenario: Professional context does not authorize a later operation

Given the professional context previously reported `APPOINTMENT_MANAGEMENT` as available for Animalia
And Animalia's Subscription has since become `EXPIRED`

When Maria attempts to confirm an Appointment at an Animalia Clinic

Then the operation is denied for lack of professional Entitlement
And the earlier professional context result does not authorize the operation

---

### Scenario: Another User's context is not revealed

Given Maria and Carlos both belong to Animalia Veterinary Group

When Maria views her professional context

Then the result does not include Carlos's responsibilities, capabilities, Professional Profile, or Clinic Assignments

---

## 5. Edge Cases

### Membership without responsibilities

An active Membership whose responsibilities have all ended is still an active
Membership and is returned with no active responsibilities and no effective
capabilities.

---

### Professional Profile without Membership

A User may have a Veterinarian Professional Profile without any active
Organization Membership. The Profile is reported; no Organization context or
capability is implied.

---

### Organization with no current Subscription

After establishment, an Organization may later have no current Subscription
(`SPEC-SUB-001` BR-30). Its Entitlements are then reported as unavailable; the
Membership, responsibilities, and effective capabilities are still returned.

---

### Organization-scoped capability and specific Clinics

An Organization-scoped effective capability applies within the Organization's
context. This Specification does not enumerate the Organization's Clinics to
which such a capability may apply; listing managed Clinics is outside its
scope.

---

## 6. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-006 — Organization Membership is temporal.**
* **INV-012 — Subscription belongs to the Organization.**
* **INV-019 — Professional context is derived, not stored.**

---

## 7. Dependencies

* SPEC-ID-003 — Authenticate User
* SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
* SPEC-VET-001 — Create Veterinarian Professional Profile
* SPEC-VET-004 — Assign Veterinarian to Clinic
* SPEC-VET-005 — End Veterinarian Clinic Assignment
* SPEC-CLI-004 — Manage Clinic Public Profile
* SPEC-SUB-003 — Evaluate Professional Entitlements

---

## 8. Out of Scope

This Specification does not define:

* reading another User's professional information;
* listing an Organization's Members or pending Invitations;
* listing the Clinics to which Organization-scoped capabilities apply;
* reading managed Clinic configuration beyond the minimum display identity of BR-4;
* Subscription commercial details or Subscription management;
* per-operation evaluation of whether a specific operation would succeed;
* new capability identifiers or changes to the responsibility-to-capability mapping of `SPEC-ORG-005`;
* Commercial Onboarding or its requests;
* presentation or navigation of professional functionality in the client.

---

## 9. Verification Notes

Verification must demonstrate that:

1. an unauthenticated caller cannot read professional context: a caller in
   the `anon` or `public` role cannot execute the read and is rejected with
   `42501` before the read is evaluated; an `authenticated` execution context
   with no authenticated subject, and an authenticated subject with no
   coherent domain User, are each rejected with `28000`;
2. the result contains only the acting User's own context;
3. only active Memberships, active Responsibility Grants, and current Clinic Assignments are returned;
4. Organizations are identified by stable identifier and display name;
5. responsibilities are returned together with effective capabilities;
6. effective capabilities match `SPEC-ORG-005` for each supported responsibility and scope, including Organization-scoped `OWNER`, `ADMINISTRATOR`, and `RECEPTIONIST`; Clinic-scoped `ADMINISTRATOR` and `RECEPTIONIST`; and Organization-scoped `VETERINARIAN`, whose capabilities are Clinic-scoped to current Clinic Assignments;
7. Clinic-scoped capabilities are returned only for the identified Clinic and never for another Clinic;
8. `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` is returned with Organization scope for active Organization-scoped `OWNER` and `ADMINISTRATOR`, with Clinic scope for an active Clinic-scoped `ADMINISTRATOR`, and never for `RECEPTIONIST`, `VETERINARIAN`, or a Clinic Assignment;
9. Veterinarian clinical capabilities are returned only for Clinics where the User holds a current Clinic Assignment and satisfies the applicable professional requirements;
10. ended Memberships, Responsibility Grants, and Clinic Assignments contribute no effective capability;
11. effective capabilities agree with the authorization evaluation used by protected operations;
12. Clinic-scoped responsibilities, Clinic-scoped capabilities, and current Clinic Assignments identify the Clinic by stable identifier and, where present, display name, including for unpublished Clinics and without a public Discovery read;
13. a Clinic without a display name is still identified by its stable identifier and is not omitted;
14. no other Clinic configuration is exposed;
15. Professional Profile existence is reported correctly;
16. Entitlement availability per Organization matches `SPEC-SUB-003` evaluation at read time, including `PENDING`, `ACTIVE`, `CANCELLED` within and after validity, `PAST_DUE`, `EXPIRED`, and no current Subscription;
17. capability availability and Entitlement availability are reported independently;
18. a returned capability does not cause an operation to succeed when its Entitlement, lifecycle, Care Authorization, or other preconditions are not met;
19. no Subscription commercial details are exposed;
20. a User with no professional relationships receives an empty, non-error result;
21. reading professional context persists nothing, including no capability set;
22. no Pet, Guardianship, Appointment, Care Authorization, or medical information is returned;
23. a previously returned context does not authorize a later operation.

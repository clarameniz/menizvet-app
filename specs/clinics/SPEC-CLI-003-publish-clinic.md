# SPEC-CLI-003 — Publish Clinic

**Status:** APPROVED
**Requirements:** REQ-CLI-003, REQ-DIS-001, REQ-DIS-002, REQ-DIS-004, REQ-ORG-005, REQ-ORG-006
**Domain:** Clinics
**Priority:** P0

## 1. Intent

Allow an authorized Organization Member to make a Clinic publicly visible once the Clinic satisfies the minimum requirements for publication.

Publication makes the Clinic eligible to participate in public discovery and allows Anonymous Visitors and Users to access its approved public information.

Allow the same authorized Organization Member to unpublish the Clinic, removing it from public visibility without deleting it or affecting its existing Appointments.

Clinic creation and Clinic publication are separate behaviors.

---

## 2. Preconditions

* The Clinic exists.
* The Clinic belongs to a Veterinary Organization.
* The acting User exists.
* The acting User is authenticated.
* The acting User has an active Organization Membership in the Clinic's Organization.
* The acting User's assigned responsibilities grant the capability to manage Clinic publication.
* The Clinic has a valid physical location.
* The Clinic has a valid public display name as defined by SPEC-CLI-004.
* The Clinic is otherwise eligible for public publication.

---

## 3. Business Rules

### BR-1 — Publication is explicit

A Clinic must not become publicly visible automatically because it was created or configured.

Publication requires an explicit authorized operation.

---

### BR-2 — Publication requires a valid physical location

A Clinic must have and retain a valid physical location while published.

A Clinic without a valid physical location must not become publicly discoverable.

---

### BR-3 — Publication requires a valid public display name

A Clinic must have a valid public display name before it can be published.

The public display name requirements are defined by
SPEC-CLI-004 — Manage Clinic Public Profile.

Optional public-profile information must not be required for publication
unless a later approved Specification explicitly changes the publication
requirements.

---

### BR-4 — Publication requires Organization authorization

Only a User whose active Organization Membership grants the capability to manage Clinic publication may publish the Clinic.

Authentication or Organization Membership alone is insufficient.

Capabilities held in another Organization do not authorize publication.

---

### BR-5 — Publication makes the Clinic eligible for public discovery

Once successfully published, the Clinic becomes eligible to appear in public Clinic discovery.

This includes discovery by Anonymous Visitors.

Publication does not guarantee that the Clinic will appear in every discovery result, since filters, geographic queries, and other discovery criteria may apply.

---

### BR-6 — Public visibility exposes only approved public information

Publication must not expose private Organization, Clinic, User, Pet, Appointment, or medical information.

Only information explicitly classified as public may be included in the public Clinic profile.

---

### BR-7 — Publication does not grant medical or professional access

Publishing a Clinic must not grant:

* medical-record access;
* Pet access;
* Organization Membership;
* Clinic Assignment;
* Veterinarian professional status;
* administrative capabilities.

Public visibility and authorization are separate concerns.

---

### BR-8 — Publication does not automatically publish Organization Members

Publishing a Clinic must not automatically make all Organization Members or Veterinarians publicly visible.

Public visibility of individual professionals must be governed separately.

---

### BR-9 — Publication is reversible

An authorized Organization Member must be able to remove a Clinic from public visibility without deleting the Clinic.

Unpublishing a Clinic must preserve:

* Clinic identity;
* Organization relationship;
* historical Appointments;
* clinical provenance;
* historical professional relationships.

Publication is reversible in Phase 1. The unpublishing workflow is defined by
BR-16 to BR-18.

---

### BR-10 — Unpublished Clinics remain valid domain entities

Removing a Clinic from public visibility must not imply that the Clinic no longer exists.

A Clinic may continue to exist internally while not participating in public discovery.

---

### BR-11 — Publication state must be independent from Clinic identity

Publishing, unpublishing, or republishing a Clinic must not create new Clinic identities.

The same Clinic domain entity persists across publication-state changes.

---

### BR-12 — Publication does not imply appointment availability

A published Clinic may be publicly discoverable even when it currently has no available Appointments.

Public visibility and appointment availability are separate product concerns.

---

### BR-13 — Publication does not imply subscription semantics by assumption

Whether an Organization requires a particular active subscription or entitlement to publish a Clinic must be defined by the Subscription Specifications.

This Specification must not silently assume a billing rule that has not yet been approved.

---

### BR-14 — Published Clinics must continue satisfying publication requirements

A published Clinic must continue satisfying all mandatory publication
requirements for as long as it remains published.

Required public information may be updated, but it must not be removed or
changed in a way that makes the Clinic ineligible for publication.

An operation that would violate a mandatory publication requirement must be
rejected while the Clinic remains published.

The Clinic may first be unpublished and then modified according to the rules
applicable to unpublished Clinics.

---

### BR-15 — Publish operation

The publish operation

    publish_clinic(p_clinic_id uuid) returns uuid

requires the acting User's current `CLINIC_MANAGE_PUBLICATION` capability for
the target Clinic.

Publication requires exactly:

- a valid, non-empty public display name (BR-3); and
- a stored Clinic location (BR-2).

If either is missing, the operation is rejected and nothing changes.

Publication does not require:

- a scheduling timezone;
- a standard Appointment duration;
- Appointment Availability;
- Opening Hours;
- Service Offerings;
- any Subscription or professional Entitlement (`SPEC-SUB-003` BR-42).

Publish is idempotent: publishing an already published Clinic that still
satisfies the requirements succeeds and changes nothing.

Concurrent publication operations for the same Clinic are serialized by locking
the Clinic's Organization and then the Clinic, the same ordering used by other
Clinic configuration writes.

The operation changes only the Clinic's publication state. It creates no
Communication.

---

### BR-16 — Unpublish operation

The unpublish operation

    unpublish_clinic(p_clinic_id uuid) returns uuid

requires the acting User's current `CLINIC_MANAGE_PUBLICATION` capability for
the target Clinic, the same capability as Publish (BR-4).

It requires no Subscription or professional Entitlement. Phase 1 publication
is not a paid capability (`SPEC-SUB-003` BR-42), and an Organization that has
lost Entitlement must still be able to withdraw its Clinic from public
visibility.

It locks the Clinic's Organization and then the Clinic, as Publish does.

Unpublish:

- sets the Clinic's publication state to unpublished;
- is idempotent: unpublishing an already unpublished Clinic succeeds and
  changes nothing;
- changes only the publication state;
- does not delete or modify the public profile, location, scheduling
  timezone, standard duration, Appointment Availability, Opening Hours, Service
  Offerings, Clinic Assignments, or any other Clinic configuration;
- does not create, modify, cancel, expire, or otherwise transition any
  Appointment;
- creates no Communication, because no approved rule requires one.

An unpublished Clinic may be published again under BR-15. Republication
restores public visibility of the Clinic's current information; nothing is
restored from history because nothing was removed.

---

### BR-17 — Immediate effects of unpublication

From the moment an unpublish operation commits:

- the Clinic is excluded from public Clinic listing and detail reads
  (`SPEC-DIS-001`);
- the Clinic is excluded from nearby and map Discovery (`SPEC-DIS-002`,
  `SPEC-DIS-003`);
- the Guardian-facing candidate read returns no candidates for the Clinic
  (`SPEC-APT-014` BR-2);
- new Guardian Appointment requests for the Clinic are rejected
  (`SPEC-APT-001` BR-5).

These effects need no additional state: each of these reads and operations
already depends on the current publication state.

---

### BR-18 — Unpublication does not affect existing Appointments

Unpublication does not modify, invalidate, cancel, or expire existing:

- `REQUESTED` Appointments;
- `CONFIRMED` Appointments;
- Appointment Schedule Revisions and lifecycle history;
- Reschedule Proposals, including pending ones;
- Care Authorizations;
- Communications already created.

No new Appointment state, terminal outcome, or cancellation reason is
introduced.

Existing Appointments continue their normal lifecycle under their own
Specifications, none of which depends on current publication state:

- the Clinic may confirm a `REQUESTED` Appointment (`SPEC-APT-002`), propose a
  Clinic Alternative Time (`SPEC-APT-018`, whose Professional candidate read
  `SPEC-APT-020` requires no publication), cancel, complete, mark no-show,
  assign Veterinarians, and propose or withdraw reschedules of `CONFIRMED`
  Appointments (`SPEC-APT-005`, `SPEC-APT-016`, `SPEC-APT-017`);
- the Guardian may cancel, accept a Clinic Alternative Time
  (`SPEC-APT-019`), and accept or respond to Reschedule Proposals
  (`SPEC-APT-006`);
- a `REQUESTED` Appointment still expires under `SPEC-APT-015`.

The Guardian operation that reschedules a `REQUESTED` Appointment
(`SPEC-APT-004`) is not gated by publication and remains available, subject to
all of its own rules (including the standard duration and current Appointment
Availability). However, the Guardian-facing candidate read (`SPEC-APT-014`)
requires a published Clinic. The current Guardian surface, which offers only
candidate times from that read, therefore presents no new time to choose for
an unpublished Clinic. This is accepted Phase 1 behavior. Changing either rule
requires a separate approved change.

All professional operations remain subject to their own authorization and
Entitlement rules.

Guardian Appointment views continue to identify the Clinic by its current
public display name, regardless of publication state.

---

### BR-19 — Publication and online Appointment setup are distinct

Publication governs public visibility only.

A Clinic may be published without accepting online Appointment requests
(BR-12), and an unpublished Clinic cannot receive new Guardian requests even
when its scheduling configuration is complete.

The professional presentation of these concepts is defined by
`SPEC-CLI-007` BR-7 to BR-11. Clients may show readiness to publish before
offering Publish, but the backend requirements of BR-15 remain authoritative.

---

### BR-20 — Authorization precedes resource disclosure

For both Publish and Unpublish:

1. an unauthenticated caller is rejected as unauthenticated;
2. a nonexistent Clinic and a Clinic the caller may not manage are rejected
   with the same insufficient-capability outcome (`42501`), revealing neither
   existence nor publication state;
3. only for an authorized caller are the publication requirements of BR-15
   evaluated; a missing display name or location is then reported as an
   integrity rejection (`23514`) that the client may map to the item to fix.

The original Publish implementation reported a nonexistent Clinic with a
distinct existence error before evaluating capability. Clinic self-service
Slice C closed this gap and introduced Unpublish under this rule
(`20261025090000_clinic_timezone_publication_self_service.sql`; see
`docs/IMPLEMENTATION_STATUS.md`).

---

### BR-21 — Professional publication controls

Publish and Unpublish are offered on the Clinic settings overview
(`SPEC-CLI-007` BR-11, BR-12) to professionals whose advisory capabilities
include `CLINIC_MANAGE_PUBLICATION`.

- While the Clinic is not ready to publish, Publish is unavailable and the
  overview identifies what is missing, with navigation to fix it.
- The client may ask for a single confirmation before Publish or Unpublish,
  explaining that the Clinic will become, or stop being, visible to the
  public.
- A rejection is presented as calm copy that identifies the missing item; raw
  backend text is never shown.
- A lost response is reconciled by re-reading the publication state: because
  both operations are idempotent, a matching state means success, and
  retrying is safe.

---

## 4. Scenarios

### Scenario: Publish a Clinic successfully

Given Animalia Madrid Centro exists
And the Clinic belongs to Animalia Veterinary Group
And the Clinic has a valid physical location
And the Clinic has a valid public display name
And Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities grant the capability to manage Clinic publication

When Maria publishes Animalia Madrid Centro

Then the Clinic becomes publicly visible
And the Clinic becomes eligible for public discovery
And Anonymous Visitors may access its approved public information
And the Clinic remains the same domain entity

---

### Scenario: Clinic is not public before explicit publication

Given Animalia Madrid Centro exists
And the Clinic has a valid location
And the Clinic has complete public information
And the Clinic has not been published

When an Anonymous Visitor performs public Clinic discovery

Then Animalia Madrid Centro is not returned solely because it exists and is configured

---

### Scenario: Clinic without location cannot be published

Given Animalia Madrid Centro exists
And the Clinic does not have a valid physical location
And Maria is otherwise authorized to publish the Clinic

When Maria attempts to publish Animalia Madrid Centro

Then the operation is denied
And the Clinic remains unpublished
And the Clinic does not become geographically discoverable

---

### Scenario: Clinic without a public display name cannot be published

Given Animalia Madrid Centro exists
And the Clinic has a valid physical location
And the Clinic does not have a valid public display name
And Maria is authorized to manage publication

When Maria attempts to publish the Clinic

Then the operation is denied
And the Clinic remains unpublished

---

### Scenario: Unauthorized Member attempts publication

Given Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities do not grant the capability to manage Clinic publication

When Maria attempts to publish Animalia Madrid Centro

Then the operation is denied
And the Clinic remains unpublished

---

### Scenario: Member of another Organization attempts publication

Given Maria has an active Membership in VetCare Group
And Maria has no authorized Membership context in Animalia Veterinary Group

When Maria attempts to publish Animalia Madrid Centro

Then the operation is denied
And Animalia Madrid Centro remains unpublished

---

### Scenario: Published Clinic exposes only public information

Given Animalia Madrid Centro is published

When an Anonymous Visitor views the Clinic public profile

Then only approved public Clinic information is available
And private Organization information is not exposed
And private Member information is not exposed
And Pet information is not exposed
And Appointment records are not exposed
And medical information is not exposed

---

### Scenario: Publishing Clinic does not publish all Veterinarians

Given Animalia Madrid Centro is published
And multiple Veterinarians are assigned to the Clinic

When an Anonymous Visitor views the Clinic public profile

Then the Clinic publication itself does not automatically make every assigned Veterinarian publicly visible

---

### Scenario: Published Clinic has no appointment availability

Given Animalia Madrid Centro is published
And the Clinic currently has no Appointment availability

When an Anonymous Visitor discovers the Clinic

Then the Clinic may still appear in public discovery
And the absence of Appointment availability does not automatically unpublish the Clinic

---

### Scenario: Required public information is updated while Clinic remains published

Given Animalia Madrid Centro is published
And its public profile satisfies all mandatory publication requirements
And Maria is authorized to manage the Clinic

When Maria replaces a required public value with another valid value

Then the update succeeds
And the Clinic remains published
And all publication requirements continue to be satisfied

---

### Scenario: Required public information cannot be removed while Clinic is published

Given Animalia Madrid Centro is published
And its physical location is required for publication

When Maria attempts to remove the Clinic's physical location

Then the operation is denied
And the existing valid location remains unchanged
And the Clinic remains published

---

### Scenario: Publish without scheduling configuration

Given Animalia Getafe has a display name and a location
And it has no scheduling timezone, standard duration, Appointment
Availability, Opening Hours, or Service Offerings
And Animalia Veterinary Group holds no professional Entitlement

When an authorized administrator publishes Animalia Getafe

Then the Clinic becomes published
And it appears in public Discovery
And the Guardian candidate read returns no candidates for it

---

### Scenario: Repeated Publish

Given Animalia Madrid Centro is already published

When an authorized administrator publishes it again

Then the operation succeeds
And nothing changes

---

### Scenario: Unpublish a Clinic

Given Animalia Madrid Centro is published
And Maria holds `CLINIC_MANAGE_PUBLICATION` for it

When Maria unpublishes Animalia Madrid Centro

Then the Clinic is no longer published
And it no longer appears in public listing, nearby, or map Discovery
And its public detail is no longer available
And the Guardian candidate read returns no candidates for it
And its profile, location, timezone, and scheduling configuration remain stored

---

### Scenario: Repeated Unpublish

Given Animalia Getafe is not published

When an authorized administrator unpublishes it

Then the operation succeeds
And nothing changes

---

### Scenario: Unpublish does not affect existing Appointments

Given Luna has a `REQUESTED` Appointment at Animalia Madrid Centro
And Max has a `CONFIRMED` Appointment there with a pending Reschedule Proposal

When Animalia Madrid Centro is unpublished

Then both Appointments, their Schedule Revisions, and the pending proposal are
unchanged
And Animalia may still confirm Luna's request, subject to its own rules
And the Guardians may still cancel or accept proposals under their own rules
And no Communication is created by the unpublication

---

### Scenario: New request after Unpublish is rejected

Given Animalia Madrid Centro has been unpublished

When a Guardian attempts a new Appointment request at Animalia Madrid Centro

Then the request is rejected
And no Appointment is created

---

### Scenario: Republish after Unpublish

Given Animalia Madrid Centro was unpublished
And it still has a display name and a location

When an authorized administrator publishes it again

Then it is published with its current stored information
And it is the same Clinic as before

---

### Scenario: Unauthorized Unpublish

Given Carlos is a Receptionist at Animalia Madrid Centro

When Carlos attempts to unpublish Animalia Madrid Centro

Then the operation is denied
And the Clinic remains published

---

## 5. Edge Cases

### Temporary public withdrawal

An Organization may wish to temporarily remove a Clinic from discovery without closing or deleting it.

The domain must support this through publication state rather than destructive deletion.

Unpublish (BR-16) is that mechanism. A Clinic that only wants to stop
receiving new online requests while remaining discoverable may instead close
its Appointment Availability (`SPEC-APT-013`).

---

### Organization leaves the platform or loses Entitlement

Publication is not Entitlement-gated in Phase 1, so loss of Entitlement does
not unpublish a Clinic. The Guardian candidate read already returns no
candidates without `APPOINTMENT_MANAGEMENT`. An Organization that no longer
wants to be discoverable unpublishes its Clinic; Unpublish requires no
Entitlement (BR-16).

---

### Organization subscription changes

A future Subscription Specification may restrict public publication based on Organization entitlement.

Publication eligibility must then incorporate that rule without redefining Clinic identity.

---

## 6. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-014 — Anonymous public discovery is allowed.**

---

## 7. Dependencies

* SPEC-CLI-001 — Create Clinic
* SPEC-CLI-002 — Set Clinic Location
* SPEC-CLI-004 — Manage Clinic Public Profile
* SPEC-CLI-007 — View Managed Clinic Configuration
* SPEC-ID-003 — Authenticate User
* SPEC-ORG-003 — Accept Organization Invitation
* SPEC-APT-001 — Request Appointment
* SPEC-APT-014 — View Guardian Requestable Appointment Times
* SPEC-SUB-003 — Evaluate Professional Entitlements

Authorization follows the responsibility-derived capability model established by the Organization Specifications.

---

## 8. Out of Scope

This Specification does not define:

* the complete Clinic public-profile data model;
* Clinic opening-hours management;
* Clinic service management;
* public Veterinarian profiles;
* geographic ranking;
* nearby Clinic queries;
* search filters;
* map rendering;
* Appointment availability;
* Appointment booking;
* automatic publication-state transitions;
* Organization subscription requirements for publication;
* publication history or a publication timestamp;
* Clinic closure or archival.

---

## 9. Verification Notes

Verification must demonstrate that:

1. Clinic publication requires an explicit authorized operation;
2. a Clinic cannot be published without a valid physical location;
3. a Clinic cannot be published without a valid public display name;
4. unauthorized Users cannot publish a Clinic;
5. successful publication makes the Clinic eligible for public discovery;
6. Anonymous Visitors can access approved public Clinic information;
7. publication does not expose protected information;
8. publication does not automatically expose Organization Members or Veterinarians;
9. publication does not grant unrelated capabilities;
10. publication does not require current Appointment availability;
11. publication-state changes do not change Clinic identity;

### Publish

12. Publish without a display name and Publish without a location are each
    rejected with `23514` and nothing changes;
13. Publish succeeds with a display name and a location, without scheduling
    timezone, standard duration, Appointment Availability, Opening Hours,
    Service Offerings, or any professional Entitlement (BR-15);
14. repeated Publish succeeds with no change (BR-15);

### Unpublish

15. Unpublish by an Owner, Organization Administrator, or Clinic
    Administrator (own Clinic) makes the Clinic unpublished, without any
    professional Entitlement (BR-16);
16. repeated Unpublish succeeds with no change (BR-16);
17. after Unpublish the Clinic is absent from public listing and detail,
    nearby, and map Discovery, the Guardian candidate read returns no
    candidates, and a new Guardian request is rejected (BR-17);
18. Unpublish leaves the profile, location, timezone, standard duration,
    Availability, Opening Hours, Service Offerings, and Clinic Assignments
    stored and unchanged (BR-16);
19. an existing `REQUESTED` Appointment remains unchanged and can still be
    confirmed, cancelled, offered a Clinic Alternative Time, rescheduled by
    the Guardian through `SPEC-APT-004`, and expired; an existing `CONFIRMED`
    Appointment, its Schedule Revisions, and a pending Reschedule Proposal
    remain unchanged and their lifecycle operations still work (BR-18);
20. Unpublish creates no Communication and alters no existing Care
    Authorization or Communication (BR-16, BR-18);
21. republishing an unpublished Clinic that still satisfies BR-15 succeeds and
    restores public visibility of its current information (BR-16);

### Authorization and disclosure

22. Receptionist, Veterinarian, another Clinic's Administrator, another
    Organization's members, ended Memberships or Grants, and anonymous callers
    are denied Publish and Unpublish with no change;
23. for Publish and Unpublish a nonexistent Clinic and an inaccessible Clinic
    produce the same `42501` outcome, and publication requirements are
    evaluated only for an authorized caller (BR-20).

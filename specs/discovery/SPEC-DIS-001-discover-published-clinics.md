# SPEC-DIS-001 — Discover Published Clinics

**Status:** APPROVED
**Requirements:** REQ-DIS-001, REQ-DIS-004, REQ-CLI-003
**Domain:** Discovery
**Priority:** P0

## 1. Intent

Allow Anonymous Visitors and registered Users to discover Clinics that are currently published and eligible for public visibility.

Clinic Discovery provides access only to information intentionally exposed through the Clinic's public-facing domain.

Authentication is not required for this behavior.

This Specification defines which Clinics may participate in public discovery.

It does not yet define geographic proximity, map rendering, ranking, or filtering.

---

## 2. Preconditions

* Public Clinic discovery is available.
* Zero or more Clinics exist in the platform.
* Each Clinic has its own publication state and public information.

Authentication is not required.

---

## 3. Business Rules

### BR-1 — Discovery is available without authentication

Anonymous Visitors must be able to discover published Clinics without creating or authenticating a User account.

Authentication must not be introduced as a prerequisite for basic Clinic discovery.

---

### BR-2 — Only published Clinics participate in public discovery

A Clinic may participate in public discovery only while it is currently published.

An unpublished Clinic must not be returned through public discovery.

---

### BR-3 — Clinic creation alone does not make a Clinic discoverable

The existence of a Clinic is insufficient for public discovery.

A Clinic must complete the applicable publication workflow before becoming discoverable.

---

### BR-4 — A valid location alone does not make a Clinic discoverable

A Clinic with a valid physical location but without publication must not participate in public discovery.

---

### BR-5 — Public-profile completion alone does not make a Clinic discoverable

A Clinic with valid public-profile information but without publication must not participate in public discovery.

---

### BR-6 — Discovery exposes only public information

Discovery results must contain only information that is approved for public exposure.

Discovery must not expose protected or internal information belonging to:

* Veterinary Organizations;
* Organization Memberships;
* Clinic internal operations;
* Users;
* Pets;
* Appointments;
* medical records;
* subscriptions.

---

### BR-7 — Discovery identifies Clinics, not Organizations

Public geographic and Clinic discovery operates on physical Clinics.

A Veterinary Organization may therefore appear through multiple Clinics when it operates multiple published locations.

The Organization itself must not be treated as a physical search result unless a separate product capability explicitly defines such behavior.

---

### BR-8 — Multiple Clinics from the same Organization may be discoverable

If a Veterinary Organization operates multiple published Clinics, each Clinic may independently participate in Discovery.

Example:

```text
Animalia Veterinary Group
├── Animalia Madrid Centro   → published
├── Animalia Getafe          → published
└── Animalia Alcobendas      → unpublished
```

Public Discovery may expose Madrid Centro and Getafe but must not expose Alcobendas.

---

### BR-9 — Publication state is evaluated per Clinic

Publishing one Clinic must not make another Clinic of the same Organization discoverable.

Likewise, unpublishing one Clinic must not remove other published Clinics of the Organization from Discovery.

---

### BR-10 — Discovery must use current public information

When a published Clinic updates valid public information, future Discovery results must represent the current approved public information.

Updating public information must not change Clinic identity.

---

### BR-11 — Unpublishing removes the Clinic from future public discovery

Once a Clinic is no longer published, it must no longer be returned by subsequent public Discovery operations.

Unpublishing must not delete the Clinic or its historical domain information.

---

### BR-12 — Discovery does not imply Appointment availability

A published Clinic may be discoverable even when it currently has no Appointment availability.

Discovery represents public presence, not guaranteed ability to book a specific time.

---

### BR-13 — Discovery does not expose all Clinic relationships

A Clinic's public Discovery representation must not automatically expose:

* all assigned Veterinarians;
* all Organization Members;
* historical staff;
* internal schedules.

Such information may only appear when a dedicated public-visibility Specification allows it.

---

### BR-14 — Discovery does not grant additional access

Viewing or discovering a Clinic must not grant:

* Organization Membership;
* Clinic capabilities;
* Pet access;
* medical access;
* Appointment-management permissions;
* professional capabilities.

Discovery is a public read operation.

---

### BR-15 — Public Discovery must not depend on User-specific private relationships

The basic set of publicly discoverable Clinics must be determined by Clinic public eligibility rather than by whether the Visitor has an account, owns Pets, or belongs to an Organization.

Personalization may be introduced separately if required.

---

## 4. Scenarios

### Scenario: Anonymous Visitor discovers a published Clinic

Given Animalia Madrid Centro is published

When an Anonymous Visitor performs public Clinic discovery

Then Animalia Madrid Centro may be returned
And authentication is not required
And only approved public information is exposed

---

### Scenario: Registered User discovers the same published Clinic

Given Animalia Madrid Centro is published
And Maria is an authenticated User

When Maria performs public Clinic discovery

Then Animalia Madrid Centro may be returned under the same public eligibility rules
And Maria's authenticated state does not expose additional private Clinic information through the public Discovery operation

---

### Scenario: Unpublished Clinic is not discoverable

Given Animalia Madrid Centro exists
And the Clinic is not published

When an Anonymous Visitor performs public Clinic discovery

Then Animalia Madrid Centro is not returned

---

### Scenario: Configured but unpublished Clinic is not discoverable

Given Animalia Madrid Centro exists
And the Clinic has a valid physical location
And the Clinic has a valid public display name
And the Clinic has not been published

When public Clinic discovery is performed

Then Animalia Madrid Centro is not returned

---

### Scenario: Organization has both published and unpublished Clinics

Given Animalia Veterinary Group operates Animalia Madrid Centro
And Animalia Veterinary Group operates Animalia Getafe
And Animalia Veterinary Group operates Animalia Alcobendas
And Animalia Madrid Centro is published
And Animalia Getafe is published
And Animalia Alcobendas is not published

When an Anonymous Visitor performs public Clinic discovery

Then Animalia Madrid Centro may be returned
And Animalia Getafe may be returned
And Animalia Alcobendas is not returned

---

### Scenario: Unpublishing one Clinic does not hide another

Given Animalia Madrid Centro is published
And Animalia Getafe is published

When Animalia Madrid Centro is unpublished

Then Animalia Madrid Centro is no longer returned by subsequent public Discovery
And Animalia Getafe remains eligible for Discovery

---

### Scenario: Discovery exposes only public information

Given Animalia Madrid Centro is published
And Animalia Veterinary Group has private billing information
And the Clinic has internal operational information
And Organization Members are associated with the Clinic

When an Anonymous Visitor discovers Animalia Madrid Centro

Then approved public Clinic information may be exposed
And private Organization billing information is not exposed
And internal Clinic information is not exposed
And private Member information is not exposed

---

### Scenario: Clinic remains discoverable without Appointment availability

Given Animalia Madrid Centro is published
And Animalia Madrid Centro currently has no available Appointment slots

When public Clinic discovery is performed

Then Animalia Madrid Centro remains eligible for Discovery

---

### Scenario: Updated public display name appears in future Discovery

Given Animalia Madrid Centro is published
And its public display name is "Animalia Madrid Centro"

When an authorized User changes the public display name to another valid value
And public Clinic discovery is performed afterwards

Then Discovery exposes the current public display name
And the Clinic remains the same domain entity

---

### Scenario: Discovery does not grant access to protected data

Given an Anonymous Visitor discovers Animalia Madrid Centro

When the Clinic appears in Discovery

Then the Visitor gains no access to Pet information
And the Visitor gains no access to medical information
And the Visitor gains no Organization capability

---

## 5. Discovery Result Concepts

A public Discovery result may identify a Clinic using approved public information.

The exact result representation is not defined here.

Depending on the needs of later Specifications, it may include concepts such as:

* Clinic identity suitable for navigating to its public profile;
* public display name;
* approved public location representation;
* approved public profile information.

The result must not become a second independent copy of Clinic state.

The Clinic remains the source domain entity.

---

## 6. Edge Cases

### No published Clinics exist

Public Discovery must support a valid empty result when no Clinics currently satisfy public-discovery requirements.

An empty result is not an error.

---

### Clinic is unpublished while a Visitor is viewing previous results

A Visitor may have previously received public information for a Clinic that is subsequently unpublished.

Future Discovery requests must no longer return that Clinic.

The exact behavior of already-rendered client state is a user-interface concern unless later product requirements define otherwise.

---

### Recently published Clinic

A Clinic that has successfully completed publication becomes eligible for subsequent Discovery operations.

Infrastructure-level propagation or caching behavior must not change the domain publication semantics.

---

### Recently updated public information

Discovery should represent the current approved public state.

Caching may be introduced architecturally but must not redefine which information is authoritative.

---

### Duplicate public display names

Several published Clinics may have the same public display name.

Discovery must preserve their distinct Clinic identities.

---

## 7. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-014 — Anonymous public discovery is allowed.**

---

## 8. Dependencies

* SPEC-CLI-001 — Create Clinic
* SPEC-CLI-002 — Set Clinic Location
* SPEC-CLI-003 — Publish Clinic
* SPEC-CLI-004 — Manage Clinic Public Profile

---

## 9. Out of Scope

This Specification does not define:

* geographic proximity;
* search radius;
* distance calculation;
* sorting or ranking;
* map rendering;
* User device location;
* address search;
* geographic area search;
* Clinic service filtering;
* specialty filtering;
* text search;
* pagination;
* result-count limits;
* public Veterinarian profiles;
* Appointment availability;
* personalized recommendations.

Name search, alphabetical ordering, and pagination of the Clinic list are
defined by `SPEC-DIS-004`, which narrows, orders, and pages the Clinics this
Specification makes eligible without changing that eligibility.

---

## 10. Verification Notes

Verification must demonstrate that:

1. Anonymous Visitors can perform Clinic Discovery;
2. authentication is not required;
3. only published Clinics are eligible;
4. Clinic creation, location configuration, or profile completion alone do not establish Discoverability;
5. publication eligibility is evaluated independently for each Clinic;
6. multiple published Clinics belonging to one Organization may be returned;
7. unpublished Clinics are excluded;
8. unpublishing one Clinic does not affect other published Clinics;
9. Discovery exposes only approved public information;
10. current public information is used without changing Clinic identity;
11. absence of Appointment availability does not remove an otherwise published Clinic from Discovery;
12. Discovery does not grant access to protected domain information;
13. an empty Discovery result is valid.

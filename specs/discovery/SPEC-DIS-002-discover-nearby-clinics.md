# SPEC-DIS-002 — Discover Nearby Clinics

**Status:** APPROVED
**Requirements:** REQ-DIS-001, REQ-DIS-003, REQ-NFR-006
**Domain:** Discovery
**Priority:** P0

## 1. Intent

Allow an Anonymous Visitor or registered User to discover published Clinics near a geographic reference location.

Nearby Clinic Discovery applies geographic proximity to the public Clinic Discovery rules established by `SPEC-DIS-001`.

The reference location may originate from the User's current device location or another supported location-selection mechanism.

Authentication is not required.

---

## 2. Preconditions

* A valid geographic reference location is available for the Discovery operation.
* A supported search radius can be determined.
* Zero or more published Clinics exist.
* Clinics participating in geographic Discovery have valid physical locations.

Authentication is not required.

---

## 3. Business Rules

### BR-1 — Nearby Discovery does not require authentication

Anonymous Visitors must be able to perform nearby Clinic Discovery.

Authentication must not be required solely to search for nearby Clinics.

---

### BR-2 — Nearby Discovery requires a reference location

A nearby Clinic search must be evaluated relative to a valid geographic reference location.

The system must not invent a User location when none has been provided or obtained through an authorized mechanism.

---

### BR-3 — Reference location is independent from its source

The geographic reference location may come from different supported sources.

Examples may include:

* the User's current device location;
* a location explicitly selected by the User;
* a geographic point derived from a supported location-search workflow.

Nearby Discovery must depend on the resulting geographic reference point rather than on a specific location provider.

---

### BR-4 — Device location is not mandatory

A User must not be required to grant device-location permission in order to use the product's public Clinic Discovery capabilities.

If device location is unavailable or permission is denied, nearby Discovery may still be performed when another valid reference location is provided.

Basic public Discovery defined by `SPEC-DIS-001` remains available independently.

---

### BR-5 — Nearby Discovery uses a finite search area

A nearby search must operate within a supported finite geographic radius around the reference location.

The exact default, minimum, maximum, and selectable radius values are product or architectural configuration and are not defined by this Specification.

The system must not interpret "nearby" as an unbounded geographic query.

---

### BR-6 — Only published Clinics may be returned

Geographic proximity does not override public-visibility rules.

A Clinic must satisfy the public Discovery requirements defined by `SPEC-DIS-001` before it may appear in nearby results.

An unpublished Clinic must not be returned even if it is physically closer than every published Clinic.

---

### BR-7 — Distance is measured from the reference location to the Clinic

Geographic distance must be derived from:

* the search reference location;
* the Clinic's valid geographic location.

Distance must not be inferred from postal-address text alone when geographic location data is available.

---

### BR-8 — Results are ordered by geographic proximity

Unless another explicitly requested Discovery ordering applies in a future Specification, nearby Clinic results must be ordered from geographically nearest to farthest.

Clinics outside the supported search radius must not be included.

---

### BR-9 — Geographic distance is not travel time

Nearby Discovery represents geographic proximity.

It must not imply:

* driving distance;
* walking distance;
* travel duration;
* route availability;
* traffic conditions.

Routing and travel-time behavior require separate Specifications if introduced.

---

### BR-10 — Multiple Clinics from the same Organization are evaluated independently

Each published Clinic participates in proximity calculation using its own physical location.

Several Clinics belonging to the same Veterinary Organization may therefore appear at different distances.

---

### BR-11 — Organization location must not substitute Clinic location

Nearby Discovery operates on physical Clinics.

An Organization's administrative or business address must not be used as the geographic location of its Clinics.

---

### BR-12 — Location changes affect future proximity results

If a published Clinic validly changes its physical location, subsequent nearby Discovery operations must use the Clinic's current valid location.

The Clinic remains the same domain entity.

Historical clinical provenance remains unaffected.

---

### BR-13 — Nearby Discovery exposes only public information

Geographic search must not expose private information beyond the public Clinic information permitted by `SPEC-DIS-001`.

The existence of geographic processing must not expand data visibility.

---

### BR-14 — Distance may be exposed as derived public Discovery information

A nearby Discovery result may include the geographic distance between the reference location and the Clinic.

Such distance is derived for the current Discovery operation and is not part of the Clinic's persistent identity.

---

### BR-15 — User reference location is not Clinic or domain profile data

A geographic reference location supplied for public Discovery must not automatically become:

* the User's stored address;
* a Pet's location;
* an Organization location;
* a Clinic location;
* persistent profile information.

Using a location for Discovery and storing User location data are separate concerns.

---

### BR-16 — Public nearby Discovery must not require persistent location history

The product must not require a persistent history of the Visitor's geographic searches in order to perform basic nearby Clinic Discovery.

Analytics or location-history capabilities, if ever introduced, require separate privacy and product consideration.

---

### BR-17 — Empty nearby results are valid

A search in which no published Clinic exists within the supported radius must return a valid empty result.

The system must not automatically broaden the search radius without an explicit product rule.

---

## 4. Scenarios

### Scenario: Anonymous Visitor discovers nearby Clinics

Given Animalia Madrid Centro is published
And Animalia Getafe is published
And both Clinics have valid geographic locations
And a valid reference location is available

When an Anonymous Visitor searches for Clinics within a supported radius

Then published Clinics within that radius may be returned
And authentication is not required
And Clinics outside the radius are not returned

---

### Scenario: Nearby Clinics are ordered by distance

Given Clinic A is published and 2 geographic distance units from the reference location
And Clinic B is published and 5 geographic distance units from the reference location
And Clinic C is published and 8 geographic distance units from the reference location
And all three are within the search radius

When nearby Clinic Discovery is performed

Then Clinic A appears before Clinic B
And Clinic B appears before Clinic C

---

### Scenario: Closer unpublished Clinic is excluded

Given Clinic A is unpublished and is 1 geographic distance unit from the reference location
And Clinic B is published and is 3 geographic distance units from the reference location
And Clinic B is within the supported radius

When nearby Clinic Discovery is performed

Then Clinic A is not returned
And Clinic B may be returned

---

### Scenario: Clinic outside the search radius is excluded

Given Animalia Madrid Centro is published
And the Clinic has a valid geographic location
And the Clinic lies outside the requested supported radius

When nearby Clinic Discovery is performed

Then Animalia Madrid Centro is not returned

---

### Scenario: Several Clinics from the same Organization are evaluated independently

Given Animalia Veterinary Group operates Animalia Madrid Centro
And Animalia Veterinary Group operates Animalia Getafe
And both Clinics are published
And each Clinic has a different geographic location
And both are within the search radius

When nearby Clinic Discovery is performed

Then both Clinics may be returned
And each Clinic has its own geographic distance from the reference location
And each remains a distinct Discovery result

---

### Scenario: Device location is used as reference location

Given the Visitor has permitted use of their device location
And a valid geographic reference location is obtained
And published Clinics exist nearby

When nearby Clinic Discovery is performed using that reference location

Then eligible Clinics are evaluated relative to the obtained geographic point

---

### Scenario: Device location permission is denied

Given the Visitor does not grant device-location permission

When no alternative reference location has yet been provided

Then the system must not invent a geographic location
And public Clinic Discovery remains available
And the Visitor may use another supported mechanism to establish a reference location where available

---

### Scenario: User provides an alternative reference location

Given the Visitor has not provided device-location access
And the Visitor provides another valid supported geographic reference location

When nearby Clinic Discovery is performed

Then eligible Clinics are evaluated relative to that reference location
And device-location permission is not required

---

### Scenario: No Clinics exist within the radius

Given published Clinics exist
And none are within the supported search radius of the reference location

When nearby Clinic Discovery is performed

Then the result is empty
And the operation succeeds
And the search radius is not silently increased

---

### Scenario: Clinic changes location

Given Animalia Madrid Centro is published
And its current location is Location A
And a nearby search produces distance D1
And the Clinic later validly changes its physical location to Location B

When the same nearby search is performed again

Then the Clinic's distance is calculated using Location B
And the Clinic remains the same domain entity
And previous clinical provenance is unchanged

---

### Scenario: Nearby Discovery exposes no private information

Given Animalia Madrid Centro is published
And the Visitor searches from a valid reference location

When Animalia Madrid Centro appears in nearby Discovery

Then approved public Clinic information may be returned
And derived geographic distance may be returned
And private Organization information is not exposed
And private Member information is not exposed
And Pet or medical information is not exposed

---

## 5. Search Radius

Nearby Discovery operates within a finite supported radius.

The radius may be:

* explicitly selected by the User;
* provided by the consuming product experience;
* determined by a configured default when the product supports that behavior.

Exact numeric values are not part of the domain invariant.

They should be configurable without redefining the meaning of Clinic, Organization, or geographic location.

A future Specification may define product-specific radius-selection behavior.

---

## 6. Distance Semantics

Distance in this Specification means geographic proximity between two geographic positions.

It does not represent route distance or estimated travel duration.

The exact spatial calculation and storage technology are architectural concerns.

The implementation must provide sufficiently correct geographic ordering for the supported product experience.

---

## 7. Edge Cases

### Invalid reference location

If the supplied reference location is invalid, nearby Discovery must not be performed using an invented or fallback geographic point.

The operation must fail or request a valid location according to the consuming product workflow.

---

### Unsupported search radius

A requested radius outside supported product limits must not cause an unbounded query.

The exact validation or normalization behavior must be established by the product interface or architecture before implementation.

---

### Equal or effectively equal distances

Two Clinics may have identical or effectively equivalent geographic distances.

No business-significant ordering between equally distant Clinics is defined by this Specification.

A stable secondary ordering may be introduced architecturally if required.

---

### Clinic located exactly on the radius boundary

A Clinic whose geographic distance is equal to the effective search radius should be considered within the search area.

---

### Very dense geographic area

A search radius may contain a large number of published Clinics.

Result limits and pagination may be required for performance but are not defined by this Specification.

---

### Geographic reference near administrative boundaries

Nearby Discovery is based on geographic distance rather than municipal, regional, or postal boundaries.

A Clinic may therefore be considered nearby even when it lies in another administrative area.

---

## 8. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-014 — Anonymous public discovery is allowed.**

---

## 9. Dependencies

* SPEC-CLI-002 — Set Clinic Location
* SPEC-CLI-003 — Publish Clinic
* SPEC-DIS-001 — Discover Published Clinics

---

## 10. Out of Scope

This Specification does not define:

* map rendering;
* map markers;
* device-location permission UI;
* GPS provider implementation;
* geocoding provider;
* address autocomplete;
* address-to-coordinate conversion;
* routing;
* driving distance;
* walking distance;
* travel-time estimation;
* traffic conditions;
* text search;
* service filtering;
* specialty filtering;
* personalized recommendations;
* result pagination;
* result-count limits;
* persistent User location history;
* analytics tracking;
* exact numeric radius defaults or limits.

---

## 11. Verification Notes

Verification must demonstrate that:

1. nearby Clinic Discovery is available without authentication;
2. a valid reference location is required;
3. the reference location does not depend on a specific source;
4. device-location permission is not mandatory when another reference location is available;
5. only published Clinics are returned;
6. only Clinics within the effective search radius are returned;
7. Clinics at the radius boundary are considered within the search;
8. nearby results are ordered by geographic distance;
9. Clinic locations are evaluated independently even within the same Organization;
10. Organization location does not substitute Clinic location;
11. location changes affect subsequent distance calculation without changing Clinic identity;
12. geographic distance does not imply route distance or travel time;
13. an empty result is valid;
14. the search radius is not silently expanded when no Clinics are found;
15. public Discovery does not expose protected information;
16. use of a reference location does not automatically create persistent User location data.

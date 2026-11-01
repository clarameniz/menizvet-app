# SPEC-DIS-003 — View Clinics on Map

**Status:** APPROVED
**Requirements:** REQ-DIS-001, REQ-DIS-002, REQ-DIS-004
**Domain:** Discovery
**Priority:** P0

## 1. Intent

Allow Anonymous Visitors and registered Users to explore published Clinics through an interactive geographic map.

The map provides a visual representation of Clinics that satisfy the public Discovery rules.

Map interaction must not change the public eligibility rules defined by the Discovery domain.

Authentication is not required.

---

## 2. Preconditions

* The map-based Discovery experience is available.
* A geographic map area can be displayed.
* Zero or more published Clinics may exist within the relevant geographic area.
* Clinics represented on the map have valid geographic locations.

Device-location permission is not required.

---

## 3. Business Rules

### BR-1 — Map Discovery is available without authentication

Anonymous Visitors must be able to explore published Clinics on the map.

Authentication must not be required solely to access map-based Clinic Discovery.

---

### BR-2 — Only publicly discoverable Clinics may appear

A Clinic may be represented on the public map only when it satisfies the public Discovery rules defined by `SPEC-DIS-001`.

An unpublished Clinic must not appear on the public map.

---

### BR-3 — Map representation requires a valid Clinic location

A Clinic must have a valid geographic location to be represented geographically.

The system must not invent or substitute placeholder coordinates for a Clinic whose physical location is unknown.

---

### BR-4 — Clinic markers represent Clinics, not Organizations

Each map representation corresponds to a physical Clinic.

A Veterinary Organization operating multiple published Clinics may therefore have multiple locations represented on the map.

The Organization itself must not be represented as though it were a physical Clinic location.

---

### BR-5 — Map position does not depend on Clinic display name

A Clinic's map position is derived from its valid geographic location.

Changing its public display name must not alter its geographic position.

---

### BR-6 — Device location is optional

The map must remain usable when the Visitor does not grant device-location permission.

Device location may be used to improve the initial map experience or establish a geographic reference when permission is available.

Refusing device-location access must not prevent public map exploration.

---

### BR-7 — User location must not be fabricated

If device location is unavailable, denied, or unknown, the product must not display a fabricated position as though it represented the User.

The map may still display another supported geographic area independently from User location.

---

### BR-8 — User location and Clinic locations are distinct concepts

A User's current geographic position, when available, must not be treated as:

* a Clinic location;
* a User profile address;
* a Pet location;
* an Organization address.

It is contextual Discovery information.

---

### BR-9 — The visible map area may determine geographic results

When the product supports browsing by map area, Clinics represented on the map may be determined using the currently relevant geographic viewport or area.

Changing the viewed geographic area may therefore change which published Clinics are represented.

The exact query strategy, buffering, caching, and loading mechanism are architectural concerns.

---

### BR-10 — Moving the map does not modify domain state

Panning, zooming, or otherwise exploring the map must not modify:

* Clinic location;
* Clinic publication state;
* User profile information;
* Organization information;
* medical information.

Map navigation is a public read interaction.

---

### BR-11 — Selecting a Clinic identifies that Clinic

Selecting a Clinic representation on the map must identify the corresponding Clinic domain entity.

The selection must not rely on the Clinic's public display name being unique.

---

### BR-12 — Clinic selection may expose approved public summary information

Selecting a Clinic on the map may expose a public summary of that Clinic.

Only information approved for public exposure may be shown.

Selection must not expose protected Clinic, Organization, User, Pet, Appointment, subscription, or medical information.

---

### BR-13 — Selected Clinic may lead to its public profile

The product may allow the Visitor to continue from a selected map Clinic to the Clinic's public profile.

The public profile remains governed by the public-information and Discovery Specifications.

Map selection must not create a separate or inconsistent Clinic representation.

---

### BR-14 — Map presence does not imply Appointment availability

A Clinic may appear on the map even when it currently has no available Appointment slots.

Map presence represents public geographic discoverability, not guaranteed booking availability.

---

### BR-15 — Map presence does not imply that professionals are public

Representing a Clinic on the map must not automatically expose:

* assigned Veterinarians;
* Organization Members;
* professional schedules;
* internal staff information.

Professional public visibility must be explicitly specified separately.

---

### BR-16 — Clinic location changes affect future map representation

If a published Clinic validly changes its physical location, subsequent map Discovery must use the Clinic's current valid location.

The Clinic remains the same domain entity.

Historical clinical provenance remains unchanged.

---

### BR-17 — Unpublishing removes future public map representation

Once a Clinic is unpublished, subsequent public map Discovery must no longer represent that Clinic.

Unpublishing does not delete the Clinic or alter its historical domain information.

---

### BR-18 — Empty map areas are valid

A geographic area may contain no publicly discoverable Clinics.

The absence of Clinic markers in that area is a valid Discovery result and must not be treated as an error.

---

### BR-19 — Map interaction does not grant authorization

Viewing or selecting a Clinic on the map must not grant:

* Organization Membership;
* Clinic capabilities;
* Pet access;
* medical access;
* Appointment-management capabilities;
* veterinary professional capabilities.

---

## 4. Scenarios

### Scenario: Anonymous Visitor views published Clinics on the map

Given Animalia Madrid Centro is published
And Animalia Madrid Centro has a valid geographic location

When an Anonymous Visitor opens map-based Clinic Discovery for an area containing the Clinic

Then Animalia Madrid Centro may be represented on the map
And authentication is not required
And the Clinic is represented at its valid geographic location

---

### Scenario: Unpublished Clinic is not shown on the map

Given Animalia Madrid Centro exists
And the Clinic has a valid geographic location
And the Clinic is not published

When an Anonymous Visitor explores the geographic area containing the Clinic

Then Animalia Madrid Centro is not represented on the public map

---

### Scenario: Organization with multiple Clinics produces multiple map locations

Given Animalia Veterinary Group operates Animalia Madrid Centro
And Animalia Veterinary Group operates Animalia Getafe
And both Clinics are published
And both have different valid geographic locations

When a Visitor explores a map area containing both Clinics

Then Animalia Madrid Centro may be represented at its location
And Animalia Getafe may be represented at its location
And each representation identifies a distinct Clinic
And the Organization is not represented as a substitute physical location

---

### Scenario: Visitor denies device-location permission

Given the Visitor does not grant device-location permission

When the Visitor opens public map Discovery

Then map-based Clinic Discovery remains available
And the system does not fabricate a User position
And the Visitor may explore geographic areas without device location

---

### Scenario: Device location is available

Given the Visitor has granted device-location permission
And a valid current geographic location is available

When map Discovery uses that location to establish the initial geographic context

Then the map may use the location to improve the initial Discovery experience
And the location does not become persistent User profile data solely because it was used for Discovery

---

### Scenario: Visitor moves the map to another area

Given the Visitor is viewing a geographic area containing published Clinics
And another geographic area contains a different set of published Clinics

When the Visitor moves the map to the other area

Then the product may update the Clinic representations according to the new relevant geographic area
And moving the map does not modify any Clinic domain state

---

### Scenario: Visitor selects a Clinic marker

Given Animalia Madrid Centro is represented on the public map

When the Visitor selects its map representation

Then Animalia Madrid Centro becomes the selected Clinic
And approved public summary information may be shown
And the selected Clinic is identified by its domain identity rather than by display-name uniqueness

---

### Scenario: Visitor opens the Clinic public profile from the map

Given Animalia Madrid Centro is represented on the map
And the Visitor has selected the Clinic

When the Visitor requests additional Clinic information

Then the product may open Animalia Madrid Centro's public profile
And only approved public information is available
And authentication is not required for the public profile

---

### Scenario: Selecting a Clinic does not expose private information

Given Animalia Madrid Centro is represented on the map
And the Clinic belongs to Animalia Veterinary Group
And private Organization and operational information exists

When an Anonymous Visitor selects Animalia Madrid Centro

Then approved public Clinic information may be shown
And private Organization information is not exposed
And private staff information is not exposed
And Pet information is not exposed
And medical information is not exposed

---

### Scenario: Clinic moves to another physical location

Given Animalia Madrid Centro is published at Location A
And the Clinic is represented on the map at Location A
And the Clinic later validly changes its physical location to Location B

When public map Discovery is subsequently performed

Then Animalia Madrid Centro is represented using Location B
And the Clinic remains the same domain entity
And historical clinical provenance remains unchanged

---

### Scenario: Clinic is unpublished after appearing on the map

Given Animalia Madrid Centro is published
And the Clinic previously appeared on the public map

When Animalia Madrid Centro is validly unpublished
And a subsequent map Discovery operation is performed

Then Animalia Madrid Centro is no longer represented on the public map

---

### Scenario: Map area contains no published Clinics

Given no published Clinic exists in the currently explored geographic area

When the Visitor explores that area

Then no Clinic representations are shown for that area
And the map interaction remains valid
And the absence of results is not treated as an error

---

### Scenario: Clinic has no Appointment availability

Given Animalia Madrid Centro is published
And the Clinic has no currently available Appointment slots
And the Clinic is within the explored geographic area

When public map Discovery is performed

Then Animalia Madrid Centro may still be represented on the map

---

## 5. Clinic Map Representation

A public Clinic map representation must preserve the identity of the underlying Clinic.

It may include enough public information to support interaction, such as:

* Clinic identity;
* geographic position;
* public display name;
* approved summary information.

The representation must not become an independent copy of Clinic state.

The Clinic remains the authoritative domain entity.

---

## 6. Geographic Viewport

The product may use the currently visible map area as a geographic Discovery context.

The viewport may change as the Visitor:

* pans;
* zooms;
* selects another location;
* returns to their current location where available.

The Specification does not define:

* map tile behavior;
* geographic bounding-box implementation;
* query debounce timing;
* background fetching;
* result caching;
* prefetch distance.

Those are architectural and user-experience concerns.

---

## 7. Marker Density

A geographic area may contain more Clinics than can be usefully represented as individual interactive markers.

The domain must not assume that every eligible Clinic must always have an individually rendered marker at every zoom level.

Techniques such as:

* clustering;
* aggregation;
* density-based representation;

may be introduced as presentation behavior without changing Clinic Discovery eligibility.

The exact interaction model requires a dedicated Specification if it becomes product-significant.

---

## 8. Edge Cases

### Multiple Clinics at the same or nearly identical location

Distinct Clinics may share the same address or geographic position.

The map experience must not merge their domain identities merely because their positions overlap.

The presentation mechanism for overlapping Clinics is a UI concern unless additional product behavior is required.

---

### Duplicate public display names

Multiple Clinics may share the same public display name.

Map interaction must distinguish them through Clinic identity rather than name uniqueness.

---

### Map is opened without a User location

The product must support a meaningful map experience without requiring a current User position.

The choice of initial map area in this situation is a product/UI decision rather than a medical or Clinic domain rule.

---

### Temporary location-provider failure

Failure to obtain device location must not make published Clinic data unavailable.

The product may continue using another supported geographic context.

---

### Clinic becomes unpublished while already rendered

A Clinic may become unpublished while a previous client representation is still visible.

Subsequent public Discovery data must no longer include the Clinic.

Immediate removal from already-rendered client state depends on the application's synchronization strategy.

---

### Very large number of Clinics

A map area may contain a large number of eligible Clinics.

The implementation must avoid requiring unbounded Clinic data to be loaded solely for map rendering.

Exact result limits, viewport loading strategies, and clustering are architectural concerns.

---

## 9. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-014 — Anonymous public discovery is allowed.**

---

## 10. Dependencies

* SPEC-CLI-002 — Set Clinic Location
* SPEC-CLI-003 — Publish Clinic
* SPEC-CLI-004 — Manage Clinic Public Profile
* SPEC-DIS-001 — Discover Published Clinics

`SPEC-DIS-002 — Discover Nearby Clinics` may provide a geographic reference experience but is not required for all map exploration behavior.

---

## 11. Out of Scope

This Specification does not define:

* map provider;
* Google Maps;
* React Native map libraries;
* map tile implementation;
* marker visual design;
* marker clustering behavior;
* animation;
* viewport query implementation;
* map-query debounce timing;
* device-location permission UI;
* GPS provider implementation;
* route calculation;
* navigation directions;
* travel time;
* traffic information;
* Clinic service filtering;
* specialty filtering;
* Appointment availability display;
* public Veterinarian markers;
* persistent User location history;
* analytics tracking.

---

## 12. Verification Notes

Verification must demonstrate that:

1. map-based Clinic Discovery is available without authentication;
2. only publicly discoverable Clinics are eligible for public map representation;
3. Clinics require valid geographic locations to appear geographically;
4. map representations identify Clinics rather than Organizations;
5. multiple Clinics belonging to one Organization remain distinct;
6. device-location permission is optional;
7. the system does not fabricate a User location;
8. moving or zooming the map does not modify domain state;
9. selecting a Clinic identifies the correct Clinic independently of display-name uniqueness;
10. map selection exposes only approved public information;
11. Clinic location changes affect subsequent map representation without changing Clinic identity;
12. unpublished Clinics disappear from subsequent public map Discovery;
13. no Appointment availability is required for map representation;
14. empty geographic areas are valid;
15. map interaction grants no protected capabilities;
16. public map representation must not require unbounded Clinic data loading.

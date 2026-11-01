# SPEC-CLI-002 — Set Clinic Location

**Status:** APPROVED
**Requirements:** REQ-CLI-002, REQ-ORG-005, REQ-ORG-006
**Domain:** Clinics
**Priority:** P0

## 1. Intent

Allow an authorized Organization Member to establish or update the physical location of a Clinic.

A Clinic location represents where veterinary care is physically provided.

The location must support both:

* meaningful human-facing address information;
* geographic positioning suitable for location-based product capabilities.

Setting a Clinic location does not by itself make the Clinic publicly discoverable.

---

## 2. Preconditions

* The Clinic exists.
* The Clinic belongs to a Veterinary Organization.
* The acting User exists.
* The acting User is authenticated.
* The acting User has an active Organization Membership in the Clinic's Organization.
* The acting User's assigned responsibilities grant the capability to manage Clinic information.
* The submitted location information satisfies the minimum validity requirements.

---

## 3. Business Rules

### BR-1 — A Clinic may have a physical location

A Clinic must be capable of representing the physical place where veterinary care is provided.

The location belongs to the Clinic rather than directly to the Veterinary Organization.

---

### BR-2 — Address information and geographic position are distinct concepts

The Clinic location must be capable of representing both:

* human-readable location information;
* a geographic position suitable for spatial operations.

The system must not assume that a formatted postal address alone is sufficient for geographic proximity calculations.

---

### BR-3 — Location changes require authorization

A User may establish or update a Clinic location only when their active Organization context grants the capability to manage that Clinic's information.

Capabilities held in another Organization do not authorize the change.

---

### BR-4 — Setting a location does not publish the Clinic

A Clinic does not become publicly discoverable solely because a valid physical location has been established.

Public visibility is governed by separate publication and discovery behavior.

---

### BR-5 — Geographic position must represent the Clinic location

Where geographic coordinates are associated with a Clinic, they must represent the intended physical Clinic location.

Coordinates must be intentionally established for the Clinic by an authorized actor. Coordinates that were never chosen for the Clinic — such as a default, placeholder, or untouched map position — must not be stored as its location.

The platform does not verify that coordinates correspond to the textual address. In Phase 1, correspondence is the responsibility of the authorized actor, who explicitly positions or confirms the map position (BR-13). Backend validation is limited to the rules of BR-12.

Any future geocoding, address verification, or confidence mechanism is an architectural concern and requires its own approved behavior.

---

### BR-6 — Geographic search must use location data suitable for spatial operations

Clinic location information must support future geographic operations such as:

* finding Clinics near a location;
* ordering Clinics by distance;
* displaying Clinics on a map.

The Specification does not prescribe the spatial storage technology.

---

### BR-7 — Updating a Clinic location must not create a new Clinic

Changing the physical location of an existing Clinic updates the location associated with that Clinic.

It must not create a second Clinic solely because the address or geographic position changed.

---

### BR-8 — Changing current location must not rewrite historical clinical provenance

A Clinic may move to a different physical address while remaining the same Clinic.

Changing its current location must not alter the historical identity of clinical events previously attributed to that Clinic.

Where historical address information itself becomes relevant to medical or legal provenance, it must be preserved through an appropriate historical mechanism rather than inferred from the Clinic's current location.

---

### BR-9 — Location identity must not depend on address text equality

Two Clinics may have similar or identical address text while remaining different Clinics.

Likewise, changes in formatting of an address must not create a new Clinic identity.

---

### BR-10 — Location must be associated with the correct Clinic

Updating one Clinic's location must not change the location of another Clinic, including another Clinic belonging to the same Organization.

---

### BR-11 — A Clinic may exist before its physical location is configured

A Clinic may exist while its physical location is still pending or incomplete.

However, a Clinic without a valid physical location must not be eligible
for product capabilities that require a known physical care location.

At minimum, a Clinic without a valid physical location must not be publicly
discoverable through geographic search or map-based discovery.

Other capabilities that require a valid physical location must define that
precondition in their own Specifications.

---

### BR-12 — Phase 1 stored location and backend validity

In Phase 1 a Clinic location consists of exactly:

- a public address text — one human-readable line shown to the public when
  the Clinic is published;
- a latitude;
- a longitude.

The coordinates are the position used for nearby and map Discovery. The
address text and the coordinates are stored together but are distinct
information (BR-2).

A location is valid for storage when:

- the address text is not blank after removing leading and trailing
  whitespace (it is stored trimmed);
- the latitude is between -90 and 90 inclusive;
- the longitude is between -180 and 180 inclusive.

No other validity rule is applied. In particular, the backend does not
geocode, does not check that the address and the coordinates correspond, and
does not reject any in-range coordinate pair.

---

### BR-13 — Phase 1 professional location editor

The Phase 1 professional location editor, reached from Clinic settings
(`SPEC-CLI-007` BR-12), provides:

- a manually entered public address text;
- a map position (marker) that the authorized actor explicitly establishes.

The address text and the map position are independent values. Changing the
address never moves the marker, and moving the marker never changes the
address.

The marker is explicitly established only by one of these actions of the
authorized actor:

- tapping the map;
- dragging or otherwise repositioning the marker, including an equivalent
  accessible action such as placing it at the centre of the visible map;
- explicitly asking the app to use the device's current location as the
  proposed marker position (BR-18).

Phase 1 uses no geocoding, address search, address autocomplete, reverse
geocoding, or address-to-coordinate verification. No address is ever inferred
from a position, and no position from an address.

The editor must never save an untouched neutral or default map position as
the Clinic location; such a position is presentation only. When the Clinic has
no stored location, Save remains unavailable until the actor has entered a
non-blank address AND explicitly established the marker. When a location is
already stored, the editor starts from the stored position, which counts as an
established marker; keeping it unchanged is an explicit confirmation of that
stored position, and an address-only change can be saved without moving it.

The editor distinguishes, in presentation, the address shown to the public
from the map position used for nearby and map search.

Submitted coordinates may be rounded to a fixed precision of at least six
decimal places, so that saving and re-reading the same position is stable.

---

### BR-14 — Each save replaces the whole location

One save submits and replaces the address text, latitude, and longitude
together. If the Clinic has no stored location, the save establishes it. The
Clinic's identity, publication state, profile, and scheduling timezone are
unchanged (BR-7; `SPEC-APT-013` BR-45).

---

### BR-15 — No location removal in Phase 1

Phase 1 provides no operation that removes a Clinic's stored location. A
location can only be replaced.

Removing the location of a published Clinic would in any case be rejected
(`SPEC-CLI-003` BR-14).

---

### BR-16 — Phase 1 saves are last-write-wins

Location saves are last-write-wins in Phase 1. No revision token or
stale-edit detection is introduced. This is a deliberate decision: the
location is replaced as one unit, changes rarely, and is managed by few
actors.

Clients must re-read after every save. A lost response is reconciled by
re-reading: if the stored address text equals the submitted text after
trimming, and the stored coordinates equal the submitted (rounded)
coordinates, the save succeeded.

---

### BR-17 — Authorization precedes input-specific disclosure

The save requires `CLINIC_MANAGE_LOCATION` for the target Clinic.

Validation and disclosure ordering:

1. an unauthenticated caller is rejected as unauthenticated;
2. a nonexistent Clinic and a Clinic the caller may not manage are rejected
   with the same insufficient-capability outcome (`42501`), whatever location
   values were submitted;
3. only for an authorized caller is the submitted location validated; invalid
   input is then rejected as invalid input (`22023`) with no change.

An unauthorized caller must not be able to learn whether a Clinic exists, or
anything about the validity of its submitted input, from the outcome.

The original implementation validated the submitted location before it
established the Clinic and the caller's capability, and reported a nonexistent
Clinic with a distinct existence error. Clinic self-service Slice B closed
these gaps (`20261024090000_clinic_profile_location_fail_closed_writes.sql`;
see `docs/IMPLEMENTATION_STATUS.md`).

---

### BR-18 — Optional current-device-location assistance

The professional location editor may offer one optional, explicitly
user-triggered convenience action: **Usar mi ubicación actual / Use my current
location**. Its only purpose is to make placing the marker easier.

Device location is a positioning convenience, not proof that the Clinic is
located at the device's position. The authorized actor remains responsible for
the marker representing the Clinic (BR-5).

When — and only when — the actor invokes the action:

1. the app requests foreground location permission if it is not already
   granted, or uses the permission already granted;
2. the app obtains the device's current position once;
3. the map centres on that position;
4. the marker is placed there, and that position counts as an explicitly
   established marker (BR-13);
5. the actor may then adjust the marker manually;
6. nothing is persisted until the actor saves; Save persists the location
   exactly as any other save (BR-12, BR-14, BR-16).

The action must never:

- run, or request permission, when the editor opens or at any other time
  without the actor invoking it;
- move a stored or previously placed marker without the actor invoking it;
- fill, change, or infer the address text — there is no reverse geocoding;
- save anything by itself;
- request background location.

If permission is denied, location services are unavailable, or the position
cannot be obtained (including a timeout or any other failure), the editor
shows a calm message and keeps the typed address and any stored or manually
placed marker unchanged. Manual positioning remains fully available, and
device location is never required to save a location.

Privacy: the device position is used only on the device, transiently, to
propose the draft marker. It is not sent to any geocoder or other external
provider, and it is not logged or recorded for analytics. It becomes the
Clinic's coordinates only if the actor explicitly saves the location.

The native permission explanation shown by the operating system must describe
this use truthfully alongside the existing nearby-Clinic discovery use
(`SPEC-DIS-002`, `SPEC-DIS-003`).

---

## 4. Scenarios

### Scenario: Set a Clinic location successfully

Given Animalia Madrid Centro exists
And Animalia Madrid Centro belongs to Animalia Veterinary Group
And Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities grant the capability to manage Clinic information

When Maria sets a valid physical location for Animalia Madrid Centro

Then the Clinic has human-readable location information
And the Clinic has a geographic position suitable for spatial operations
And the Clinic remains the same domain entity

---

### Scenario: Update an existing Clinic location

Given Animalia Madrid Centro already has a physical location
And Maria is authorized to manage the Clinic

When Maria replaces the Clinic's location with a valid new physical location

Then Animalia Madrid Centro remains the same Clinic
And its current physical location reflects the new information
And no additional Clinic is created

---

### Scenario: Location does not make Clinic public

Given Animalia Madrid Centro exists
And the Clinic is not currently publicly discoverable

When an authorized User sets a valid location

Then the Clinic location is stored
But the Clinic does not become publicly discoverable solely because the location was set

---

### Scenario: Unauthorized Member attempts to change location

Given Maria has an active Membership in Animalia Veterinary Group
And Maria's responsibilities do not grant the capability to manage Clinic information

When Maria attempts to change the location of Animalia Madrid Centro

Then the operation is denied
And the Clinic location remains unchanged

---

### Scenario: Member of another Organization attempts to change location

Given Maria has an active Membership in VetCare Group
And Maria has no authorized Membership context in Animalia Veterinary Group

When Maria attempts to change the location of Animalia Madrid Centro

Then the operation is denied
And Animalia Madrid Centro remains unchanged

---

### Scenario: Updating one Clinic does not affect another Clinic

Given Animalia Veterinary Group operates Animalia Madrid Centro
And Animalia Veterinary Group also operates Animalia Getafe
And both Clinics have their own locations

When an authorized User changes the location of Animalia Madrid Centro

Then the location of Animalia Madrid Centro is updated
And the location of Animalia Getafe remains unchanged

---

### Scenario: Clinic moves after historical clinical activity

Given Animalia Madrid Centro was located at Location A
And Dr. Garcia created finalized clinical information for Luna at Animalia Madrid Centro
And the clinical information is historically attributed to Animalia Madrid Centro

When Animalia Madrid Centro later moves to Location B

Then the Clinic remains Animalia Madrid Centro
And its current location becomes Location B
And Luna's historical clinical information remains attributed to the same Clinic
And the clinical event is not re-attributed to another Clinic

---

### Scenario: Invalid location information is rejected

Given Maria is authorized to manage Animalia Madrid Centro

When Maria submits location information that does not satisfy the required validity rules

Then the location update is rejected
And the previously valid Clinic location, if any, remains unchanged

---

### Scenario: Clinic exists before location is configured

Given Animalia Madrid Centro has been created
And no valid physical location has yet been configured

When the Clinic remains in its configuration process

Then Animalia Madrid Centro continues to exist
And it remains associated with Animalia Veterinary Group
And it is not eligible for geographic public discovery
And no placeholder or invented location is assumed

---

### Scenario: Clinic without location cannot participate in geographic discovery

Given Animalia Madrid Centro exists
And the Clinic has no valid physical location

When geographic Clinic discovery is performed

Then Animalia Madrid Centro is not returned as a geographically discoverable Clinic

---

## 5. Edge Cases

### Address cannot be geocoded automatically

A valid real-world Clinic address may fail automated geocoding or may produce ambiguous results.

The product must not assume that external geocoding always succeeds.

Phase 1 uses no geocoding at all and deliberately avoids an external or paid
geocoding dependency. Its correction workflow is manual: the authorized actor
edits the address text and explicitly establishes the marker by tapping the
map, repositioning the marker, or — optionally — starting from the device's
current location (BR-13, BR-18). Address geocoding may be reconsidered only if
real usage shows meaningful friction, and would require separate approved
behavior.

---

### Clinic moves to another physical location

A Clinic may change physical address without changing its domain identity.

If future legal, audit, or medical requirements require historical Clinic addresses to be reconstructable, dedicated location history must be introduced rather than deriving past location from current Clinic data.

---

### Multiple Clinics at the same address

The domain must allow multiple distinct Clinics to share the same physical address or geographic position if the business reality requires it.

Location alone is not Clinic identity.

---

### Approximate geographic position

The product may need to distinguish between a verified precise position and an approximate or manually selected map position.

The exact confidence or verification model is outside this Specification.

---

## 6. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-009 — Historical clinical provenance is immutable.**

---

## 7. Dependencies

* SPEC-CLI-001 — Create Clinic
* SPEC-CLI-003 — Publish Clinic
* SPEC-CLI-007 — View Managed Clinic Configuration
* SPEC-DIS-002 — Discover Nearby Clinics (shares the device-location permission, BR-18)
* SPEC-DIS-003 — View Clinics on Map (shares the device-location permission, BR-18)
* SPEC-ID-003 — Authenticate User
* SPEC-ORG-003 — Accept Organization Invitation

Authorization follows the responsibility-derived capability model established by the Organization Specifications.

---

## 8. Out of Scope

This Specification does not define:

* the geocoding provider;
* map rendering;
* PostGIS or database storage representation;
* public Clinic publication;
* nearby Clinic search;
* geographic distance calculation;
* Clinic opening hours;
* Clinic services;
* address autocomplete;
* location verification workflows;
* historical Clinic-location storage;
* directions or routing;
* any use of User device location other than the explicit, foreground
  marker-positioning assistance of BR-18 (no background location, no tracking).

---

## 9. Verification Notes

Verification must demonstrate that:

1. an authorized User can establish a Clinic's physical location;
2. an authorized User can update that location;
3. unauthorized Users cannot modify Clinic location;
4. human-readable address information and geographic position can both be represented;
5. updating location does not create a new Clinic;
6. updating one Clinic does not affect another;
7. setting a location does not automatically publish the Clinic;
8. Clinic identity does not depend on address text;
9. changing current location does not rewrite historical clinical provenance;
10. invalid location information does not replace previously valid location data;
11. a first save establishes the location of a Clinic that had none, and a
    later save replaces address text and both coordinates together (BR-14);
12. blank address text, latitude outside -90..90, and longitude outside
    -180..180 are rejected with `22023` and no change, while boundary values
    are accepted (BR-12);
13. the stored address text is trimmed, and no address/coordinate
    correspondence check is performed (BR-12);
14. the professional editor cannot save an untouched default map position for
    a Clinic without a stored location, and saving with the stored position
    unchanged keeps it (BR-13);
15. no operation removes a stored location (BR-15);
16. a later save overwrites an earlier one without stale detection, and a lost
    response is reconciled by re-reading (BR-16);
17. a location change does not change the scheduling timezone, profile, or
    publication state (BR-14);
18. Owner, Organization Administrator, and Clinic Administrator (own Clinic)
    may save; Receptionist, Veterinarian, another Clinic's Administrator,
    another Organization's members, ended Memberships or Grants, and
    anonymous callers are denied with no change;
19. a nonexistent Clinic and an inaccessible Clinic produce the same `42501`
    outcome, for valid and invalid submitted values alike, and `22023` is
    reported only to an authorized caller (BR-17);
20. the marker is established only by a map tap, a marker repositioning, or
    the explicit current-location action; the neutral map centre is never an
    established marker, and an address alone or the neutral centre alone
    cannot be saved for a Clinic without a stored location (BR-13);
21. the current-location action runs only when the actor invokes it: opening
    the editor requests no permission and no device position (BR-18);
22. a successful current-location action centres the map and establishes the
    draft marker, which can then be adjusted manually and saved (BR-18);
23. the current-location action never changes the address text, never
    reverse-geocodes, and the address never moves the marker (BR-13, BR-18);
24. opening the editor for a stored location never replaces the stored
    marker with the device position; the action moves only the draft marker,
    and leaving without saving changes nothing (BR-13, BR-18);
25. a denied permission, unavailable location services, a timeout, or any
    other failure shows a calm message and keeps the typed address and any
    stored or manual marker unchanged (BR-18);
26. manual placement and saving work with the location permission never
    granted (BR-18);
27. only foreground location is requested; no background location (BR-18);
28. nothing is persisted before an explicit save, and the device position is
    not sent to any geocoder or other external provider (BR-18).

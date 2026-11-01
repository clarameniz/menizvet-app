# SPEC-CLI-005 — Manage Clinic Services

**Status:** APPROVED  
**Requirements:** REQ-CLI-004  
**Domain:** Clinics  
**Priority:** P1

## 1. Intent

Allow an authorized Organization actor to maintain the veterinary services that
a Clinic currently offers.

Clinic Services describe the kinds of veterinary care or operational veterinary
capabilities that the Clinic represents as available.

Services belong to the Clinic context.

They must remain separate from:

- the Clinic's public-profile descriptive text;
- Appointment availability;
- Veterinarian Clinic Assignments;
- Clinical Record event categories;
- individual clinical care actually provided to a Pet.

A Clinic Service describes what the Clinic offers.

It does not prove that a particular service was provided to a particular Pet.

---

## 2. Preconditions

- The Clinic exists.
- The Clinic belongs to a Veterinary Organization.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a current Organization or Clinic responsibility that
  grants the capability to manage Clinic services.
- Any service being added belongs to the supported service taxonomy or is
  otherwise valid under the applicable service model.
- The requested update leaves the Clinic Service configuration internally
  coherent.

---

## 3. Phase 1 Clinic Service Taxonomy

Phase 1 supports a controlled set of general veterinary service categories.

### GENERAL_CONSULTATION

Represents routine or general veterinary consultation and examination services.

Examples may include:

- general veterinary visits;
- routine examinations;
- common health concerns;
- general follow-up care.

---

### VACCINATION

Represents vaccination-related veterinary services.

This service category does not imply that Vaccination already exists as a
specialized medical domain model.

---

### SURGERY

Represents veterinary surgical services.

The service category indicates that the Clinic offers surgical care.

It does not define:

- surgical complexity;
- supported procedures;
- operating-room resources;
- anesthesia capability;
- specialist availability.

Those concepts may require later refinement.

---

### DENTISTRY

Represents veterinary dental services.

Examples may include:

- dental examinations;
- dental cleaning;
- dental procedures.

---

### DIAGNOSTIC_IMAGING

Represents diagnostic imaging services.

Examples may include:

- radiography;
- ultrasound;
- other supported imaging services.

The exact modalities available at a Clinic may require future structured
information.

---

### LABORATORY

Represents laboratory or diagnostic-testing services supported by the Clinic.

This category does not require the Clinic to perform every laboratory test
internally.

Future requirements may distinguish:

- on-site laboratory capability;
- external laboratory coordination;
- specific laboratory services.

---

### EMERGENCY_CARE

Represents veterinary emergency or urgent-care services.

Advertising this service must not automatically imply:

- 24-hour availability;
- continuous staffing;
- immediate Appointment availability.

Operating hours and scheduling availability remain separate concepts.

---

### HOSPITALIZATION

Represents the Clinic's ability to provide inpatient veterinary care or
hospitalization where applicable.

The service category does not define detailed bed, kennel, staffing, or
capacity management.

---

### OTHER

Represents a veterinary service that cannot reasonably be classified using the
supported Phase 1 taxonomy.

`OTHER` requires a meaningful human-readable service description.

It must not become the default category for ordinary supported services.

---

## 4. Business Rules

### BR-1 — Services belong to a specific Clinic

Every Clinic Service offering must be associated with a specific Clinic.

An Organization operating several Clinics may offer different services at each
location.

For example:

    Animalia Madrid Centro
    ├── GENERAL_CONSULTATION
    ├── VACCINATION
    └── SURGERY

    Animalia Getafe
    ├── GENERAL_CONSULTATION
    └── VACCINATION

The Organization relationship must not cause both Clinics to inherit identical
services automatically.

---

### BR-2 — Service configuration is independent from Clinic identity

Adding, removing, or changing Clinic Services must not create a new Clinic or
change the Clinic's domain identity.

---

### BR-3 — Authorized capability is required to manage services

Only an actor whose current Organization or Clinic responsibilities grant
Clinic service-management capability may modify the service offering.

Authentication or Organization Membership alone is insufficient.

---

### BR-4 — Responsibility in another Organization grants no authority

A User's service-management capability in one Veterinary Organization must not
authorize service changes for a Clinic belonging to another Organization.

---

### BR-5 — Clinic Services use controlled domain categories

Phase 1 Clinic Services should use stable service-category identities rather
than relying solely on arbitrary free-text labels.

For example:

    VACCINATION

may be displayed as:

    Vaccination
    Vacunación
    Vaccination service

without creating different domain services.

---

### BR-6 — Localized service labels do not change service identity

User-facing service labels may vary by supported language.

The underlying service category remains the same.

---

### BR-7 — Clinic may offer multiple services

A Clinic may have zero, one, or multiple supported Service offerings.

The service model must not assume that each Clinic provides every veterinary
service.

---

### BR-8 — The same service category may be offered by many Clinics

A service category is not owned exclusively by one Clinic.

For example, several unrelated Clinics may all offer `VACCINATION`.

---

### BR-9 — Duplicate service offering must not create duplicate capability

The same Clinic must not accidentally contain multiple equivalent active
offerings of the same service category.

For example:

    VACCINATION
    VACCINATION

must not be interpreted as two independent vaccination capabilities merely
because the operation was submitted twice.

---

### BR-10 — Service offering may be added

An authorized actor may add a supported service category to the Clinic's
current offering.

The update must not alter unrelated Clinic information.

---

### BR-11 — Service offering may be removed

An authorized actor may remove a currently offered service when the Clinic no
longer represents that service as available.

Removing a current service offering must not rewrite historical clinical care
that previously occurred.

---

### BR-12 — Removing a service does not rewrite Appointment history

If the Clinic previously accepted or completed Appointments related to a
service, later removing that service from the current Clinic offering must not
delete or rewrite those historical Appointments.

---

### BR-13 — Removing a service does not rewrite medical history

If the Clinic historically provided clinical care corresponding to a service,
removing the current service offering must not alter:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- clinical provenance.

Current service capability and historical care are separate concepts.

---

### BR-14 — Service offering is not clinical evidence

A Clinic advertising:

    SURGERY

must not imply that any particular Pet underwent surgery.

Clinical truth is established through Medical Records.

---

### BR-15 — Clinical Record category does not automatically create Clinic Service

A Clinic finalizing a Clinical Record Entry classified as:

    PROCEDURE

or:

    VACCINATION

must not automatically modify its current public Service offering.

Historical clinical activity and current represented capability are separate
concepts.

---

### BR-16 — Clinic Service is distinct from Clinical Event category

Clinic Service answers:

    "What kind of veterinary care does this Clinic offer?"

Clinical Event category answers:

    "What kind of clinical information does this record represent?"

These classifications may use related concepts but must remain separate domain
concerns.

---

### BR-17 — Service offering does not create Appointment availability

Adding a Clinic Service must not make a specific Appointment time available.

For example:

    VACCINATION offered

does not imply:

    vaccination Appointment available Monday at 10:00

Appointment availability follows `SPEC-APT-013`.

---

### BR-18 — Appointment availability does not imply service capability

A Clinic having free scheduling capacity must not imply that every veterinary
service can be booked during that time.

Service capability and scheduling capacity are separate conditions.

---

### BR-19 — Service offering does not guarantee immediate booking

A Clinic may offer a Service while currently having no available Appointment
capacity for it.

The Clinic may remain published and may continue describing the Service.

---

### BR-20 — Phase 1 does not require service-specific availability

Phase 1 does not require separate Appointment availability schedules for each
Clinic Service.

The current availability model may remain Clinic- and Veterinarian-based.

Future requirements may introduce service-specific scheduling when justified.

---

### BR-21 — Phase 1 does not require service-specific duration

A Clinic Service category must not automatically determine Appointment
duration.

Service-specific durations may be introduced later.

---

### BR-22 — Phase 1 does not require pricing per service

Clinic Service management does not require:

- prices;
- price ranges;
- estimates;
- taxes;
- billing codes.

Commercial service pricing is outside this Specification.

---

### BR-23 — Phase 1 does not require Veterinarian specialization mapping

Adding a Service does not require assigning specific Veterinarians to that
Service.

For example:

    Clinic offers SURGERY

does not automatically mean:

    every assigned Veterinarian may perform surgery.

Professional specialization and competency may require separate future
requirements.

---

### BR-24 — Service offering must not grant professional capability

A Veterinarian must not gain authority to provide a service merely because the
Clinic lists it.

Professional authorization, qualification, Clinic Assignment, and clinical
context remain independently required.

---

### BR-25 — Services may be exposed publicly when Clinic is published

Services that the Clinic intentionally maintains as part of its offered
veterinary capability may be exposed as public Clinic information when the
Clinic is published.

Public exposure must not reveal protected operational or medical information.

---

### BR-26 — Unpublished Clinic may still maintain Services

A Clinic does not need to be publicly published in order to configure its
Service offerings.

This allows the Clinic to prepare its information before publication.

---

### BR-27 — Adding a Service does not publish Clinic

Completing Clinic Service information must not automatically change the Clinic
publication state.

Publication remains governed by `SPEC-CLI-003`.

---

### BR-28 — Removing a Service does not automatically unpublish Clinic

Phase 1 publication does not require a minimum number of Services unless a
later approved Specification explicitly establishes that requirement.

Therefore, removing a Service must not automatically unpublish the Clinic.

---

### BR-29 — Clinic may be published with no configured Services

Unless publication requirements are later changed, absence of configured
Services must not by itself make an otherwise eligible Clinic unpublished.

Services are useful public information but are not currently mandatory for
publication.

---

### BR-30 — Services may support future public Discovery filtering

Stable Clinic Service categories must be capable of supporting later
service-based Clinic Discovery.

For example:

    find Clinics offering VACCINATION

may eventually use the Clinic Service relationship.

This Specification does not define the filtering workflow itself.

---

### BR-31 — Future Discovery filtering must use current Service offering

If service-based Discovery is introduced, it should represent the Clinic's
current Service offering.

Historical services no longer offered must not make the Clinic appear as
currently providing them.

---

### BR-32 — OTHER requires meaningful description

A Clinic Service categorized as `OTHER` must contain sufficient descriptive
information to explain the service being offered.

The service must not consist solely of:

    category = OTHER

without meaningful context.

---

### BR-33 — OTHER must not be selected automatically

If no service category has been chosen, the system must not silently create an
`OTHER` Service.

Missing configuration and explicit `OTHER` are different states.

---

### BR-34 — Service description must not replace category where supported

Where an existing supported category clearly applies, arbitrary free text
should not replace the controlled service classification.

For example:

    "We vaccinate pets"

should normally map to:

    VACCINATION

rather than creating an unrelated custom service category.

---

### BR-35 — Optional service description may supplement classification

The Clinic may support a human-readable description of a Service where useful.

For example:

    DIAGNOSTIC_IMAGING
    "Digital radiography and ultrasound"

The description supplements the controlled category.

It does not replace domain identity.

---

### BR-36 — Service description is public information where exposed

Any Service description exposed through public Clinic presentation must be
treated as intentionally public information.

It must not contain:

- private operational notes;
- Pet information;
- medical records;
- confidential staff information.

---

### BR-37 — Clinic Service management does not alter physical location

Changing Services must not modify the Clinic's physical geographic location.

---

### BR-38 — Clinic Service management does not alter public contact information

Changing Clinic Services must not implicitly modify:

- public phone;
- public email;
- website;
- public display name.

Those values are governed by the applicable Clinic Profile Specification.

---

### BR-39 — Clinic Service management does not alter opening hours

Adding or removing Services must not automatically modify Clinic opening hours.

Operating information is governed separately.

---

### BR-40 — Clinic Service management does not alter Appointment lifecycle

Service changes must not automatically:

- create Appointments;
- confirm Appointments;
- cancel Appointments;
- reschedule Appointments;
- complete Appointments;
- mark Appointments `NO_SHOW`.

---

### BR-41 — Service removal may create an operational conflict with future Appointments

A Clinic may remove a Service while future Appointments related to that Service
or care need already exist.

The existing Appointments must not be silently deleted.

The Clinic must resolve those existing obligations explicitly through the
applicable Appointment workflows.

---

### BR-42 — Current Service configuration must be internally coherent

A Clinic must not expose contradictory duplicate current service entries for the
same domain category.

The exact persistence and uniqueness mechanism is architectural.

---

### BR-43 — Subscription loss does not erase Service configuration

Loss of normal professional Entitlement must not destructively delete the
Clinic's configured Services.

Whether the Clinic may modify or publicly expose them while not entitled is a
separate commercial policy.

Historical data remains preserved.

---

### BR-44 — Service changes are atomic

A successful Clinic Service update must leave the Clinic with one coherent
current set of offered Services.

A failed update must preserve the previous valid configuration.

---

## 5. Clinic Service Information

Each current Clinic Service offering should support:

### Required

- Clinic;
- supported Service category.

### Where applicable

- human-readable public description;
- creation or update metadata;
- current active offering state.

For `OTHER`:

- meaningful service description is required.

The exact persistence representation is architectural.

---

## 6. Scenarios

### Scenario: Authorized actor adds Vaccination service

Given Animalia Madrid Centro exists
And Maria is authorized to manage the Clinic's Services

When Maria adds `VACCINATION`

Then Animalia Madrid Centro offers `VACCINATION`
And the Clinic remains the same domain entity
And no Appointment is created
And no clinical history is created

---

### Scenario: Clinic offers several Services

Given Maria is authorized to manage Animalia Madrid Centro

When Maria configures:

    GENERAL_CONSULTATION
    VACCINATION
    DENTISTRY
    DIAGNOSTIC_IMAGING

Then all four Services may belong to Animalia Madrid Centro
And each Service remains independently identifiable

---

### Scenario: Two Clinics in same Organization offer different Services

Given Animalia Veterinary Group operates Madrid Centro and Getafe
And Madrid Centro offers `SURGERY`
And Getafe does not

When the two Clinic Service configurations are evaluated

Then `SURGERY` belongs to Madrid Centro's current offering
And it is not automatically inherited by Getafe

---

### Scenario: Unauthorized Organization Member cannot modify Services

Given Maria has an active Membership in Animalia Veterinary Group
And Maria lacks Clinic Service-management capability

When Maria attempts to add `SURGERY` to Animalia Madrid Centro

Then the operation is denied
And the Clinic's Service configuration remains unchanged

---

### Scenario: Member of another Organization cannot modify Services

Given Maria has Service-management authority in VetCare Group
And no applicable authority in Animalia Veterinary Group

When Maria attempts to modify Animalia Madrid Centro's Services

Then the operation is denied

---

### Scenario: Duplicate Service is not created

Given Animalia Madrid Centro already offers `VACCINATION`

When an authorized actor attempts to add `VACCINATION` again

Then a duplicate current capability is not created
And the Clinic continues to have one current `VACCINATION` offering

---

### Scenario: Service may be removed

Given Animalia Madrid Centro currently offers `DENTISTRY`
And Maria is authorized to manage Services

When Maria removes `DENTISTRY`

Then the Clinic no longer represents `DENTISTRY` as a current offered Service
And historical clinical information remains unchanged

---

### Scenario: Service removal does not delete historical care

Given Animalia Madrid Centro previously provided dental care to Luna
And the related Clinical Record is finalized
And the Clinic later stops offering `DENTISTRY`

When `DENTISTRY` is removed from the current Clinic Services

Then Luna's historical Clinical Record remains unchanged
And Animalia remains the historical provider of that care

---

### Scenario: Service removal does not silently cancel future Appointment

Given Luna has a future confirmed Appointment related to dental care
And Animalia Madrid Centro removes `DENTISTRY` from its current Service offering

When the Service configuration changes

Then Luna's Appointment is not silently deleted or cancelled
And the Clinic must explicitly resolve the existing Appointment

---

### Scenario: Service does not create availability

Given Animalia Madrid Centro adds `SURGERY`
And the Clinic has no applicable bookable Appointment capacity

When scheduling availability is evaluated

Then the Clinic does not automatically gain available surgery times
And Service offering and Appointment availability remain separate

---

### Scenario: Available time does not prove Service capability

Given Animalia Madrid Centro has availability at 10:00
And the Clinic does not offer `SURGERY`

When a surgery-related booking need is evaluated

Then the free time alone does not establish that the Clinic provides surgery

---

### Scenario: Clinic may configure Services before publication

Given Animalia Madrid Centro is unpublished
And Maria is authorized to manage its Services

When Maria configures `GENERAL_CONSULTATION` and `VACCINATION`

Then the Service configuration may be saved
And the Clinic remains unpublished

---

### Scenario: Published Clinic exposes current Services

Given Animalia Madrid Centro is published
And it currently offers `GENERAL_CONSULTATION` and `VACCINATION`

When an Anonymous Visitor views applicable public Clinic information

Then those current Services may be exposed as public Clinic information
And protected operational or medical information is not exposed

---

### Scenario: Removing all Services does not automatically unpublish Clinic

Given Animalia Madrid Centro is published
And Services are not mandatory publication information

When an authorized actor removes the Clinic's final configured Service

Then the Clinic may remain published
And absence of Services alone does not invalidate publication

---

### Scenario: Surgery Service does not authorize every Veterinarian

Given Animalia Madrid Centro offers `SURGERY`
And Dr. Garcia is assigned to the Clinic

When Dr. Garcia's professional capability is evaluated

Then the Clinic Service alone does not establish that Dr. Garcia is qualified
or authorized to perform surgery

---

### Scenario: Clinical event does not modify Service offering

Given Animalia Madrid Centro does not currently advertise `VACCINATION`
And Dr. Garcia validly creates a `VACCINATION` Clinical Record Entry for Luna
within an authorized care context

When the medical record is finalized

Then the Clinic Service configuration is not automatically changed
And clinical history remains separate from represented current Services

---

### Scenario: Other Service requires description

Given Animalia Madrid Centro offers a veterinary service not represented by the
Phase 1 taxonomy

When Maria selects `OTHER`

Then a meaningful service description is required
And `OTHER` alone is insufficient

---

### Scenario: Missing category does not become Other automatically

Given Maria is editing the Clinic's Services
And no supported category has been selected

When the incomplete configuration is evaluated

Then the system does not silently create an `OTHER` Service

---

### Scenario: Service labels may be localized

Given Animalia Madrid Centro offers the domain Service `VACCINATION`

When the Service is displayed in Spanish and English

Then the user-facing labels may differ
And the underlying Service category remains `VACCINATION`

---

### Scenario: Subscription loss does not delete Services

Given Animalia Madrid Centro has configured Services
And Animalia Veterinary Group later loses normal professional Entitlement

When the Clinic domain state is evaluated

Then its Service configuration remains preserved
And commercial loss does not destructively erase the configuration

---

### Scenario: Failed update preserves previous Service set

Given Animalia Madrid Centro currently has a valid Service configuration

When a Service-management operation fails

Then the previous Service configuration remains valid
And no partial contradictory Service set is exposed

---

## 7. Clinic Services vs Clinical Event Types

These concepts may share terminology but answer different questions.

Clinic Service:

    VACCINATION

means:

    "This Clinic currently represents vaccination care as an offered service."

Clinical Record Entry:

    VACCINATION

means:

    "This finalized clinical contribution contains vaccination-related
    information."

Neither implies the other automatically.

---

## 8. Clinic Services vs Availability

A Clinic may offer:

    SURGERY

while:

    no Appointment capacity is currently available.

Likewise, a Clinic may have:

    free Appointment capacity

while:

    not offering SURGERY.

A supported booking may therefore eventually require both:

    appropriate Clinic Service
              +
    supported Appointment availability

where the applicable booking workflow requires service-specific validation.

Phase 1 does not yet require that complete service-aware booking engine.

---

## 9. Edge Cases

### Clinic stops offering Service temporarily

Phase 1 may represent this by removing the Service from the current offering.

A future model may introduce temporary activation periods if required.

---

### Service taxonomy is insufficient

`OTHER` provides an explicit temporary escape hatch.

Repeated use of the same `OTHER` concept may indicate that the controlled
taxonomy should evolve.

---

### Service taxonomy evolves

Adding or deprecating Service categories must not rewrite historical clinical
information or existing Clinic identity.

---

### Clinic has specialist capability only on some days

Phase 1 does not combine Services with time-specific specialist availability.

This may require future service-specific scheduling behavior.

---

### External contractor provides Service

Phase 1 Service offering describes the Clinic's represented capability.

It does not specify whether the professional is an employee, contractor, or
external provider.

Professional relationships remain governed separately.

---

## 10. Relevant Invariants

- **INV-005 — Organization and Clinic are different concepts.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-014 — Anonymous public discovery is allowed.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-CLI-001 — Create Clinic
- SPEC-CLI-003 — Publish Clinic
- SPEC-CLI-004 — Manage Clinic Public Profile
- SPEC-ID-003 — Authenticate User
- SPEC-ORG-003 — Accept Organization Invitation

Availability remains governed by:

- SPEC-APT-013 — Manage Appointment Availability

Authorization follows the Organization responsibility-derived capability
model.

---

## 12. Out of Scope

This Specification does not define:

- Clinic opening hours;
- Appointment availability;
- service-specific Appointment availability;
- service-specific Appointment duration;
- prices;
- billing;
- insurance;
- room or equipment requirements;
- Veterinarian specialties;
- individual professional competency;
- service-specific professional Assignment;
- Service-based Discovery filtering;
- automatic Appointment eligibility by Service;
- temporary Service scheduling;
- service capacity;
- public reviews of Services;
- specialized medical domain models.

---

## 13. Verification Notes

Verification must demonstrate that:

1. an authorized actor may manage Services for a specific Clinic;
2. Services remain Clinic-specific rather than Organization-global;
3. unauthorized Users cannot modify Clinic Services;
4. stable controlled Service categories are used in Phase 1;
5. localized labels do not change Service identity;
6. a Clinic may offer several Services;
7. several Clinics may independently offer the same Service;
8. duplicate current Service offerings are prevented;
9. Services may be added or removed without changing Clinic identity;
10. removing a Service does not rewrite Appointment or medical history;
11. Clinic Service is not clinical evidence;
12. Clinical Event categories do not automatically modify Clinic Services;
13. Services and Appointment availability remain separate;
14. Services do not determine Appointment duration in Phase 1;
15. Services do not automatically authorize individual Veterinarians;
16. unpublished Clinics may configure Services;
17. configuring Services does not publish a Clinic;
18. removing Services does not automatically unpublish a Clinic;
19. current Services may be exposed publicly for a published Clinic;
20. `OTHER` requires meaningful descriptive context;
21. missing classification is not automatically converted to `OTHER`;
22. future Discovery filtering can rely on stable Service categories;
23. Subscription loss does not erase Service configuration;
24. failed updates preserve the previous coherent Service configuration.
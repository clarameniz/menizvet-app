# SPEC-PET-001 — Register Pet

**Status:** APPROVED
**Requirements:** REQ-PET-001, REQ-PET-002, REQ-PET-003, REQ-PET-004, REQ-PET-005
**Domain:** Pets
**Priority:** P0

## 1. Intent

Allow an authenticated User with the required account state to register a Pet in the platform and establish the initial Guardianship relationship with that Pet.

Pet registration creates a Pet as an independent domain entity.

The Pet is not created as part of the User profile, a Clinic, or a Veterinary Organization.

---

## 2. Preconditions

* The acting User exists.
* The acting User is authenticated.
* The acting User satisfies the account verification requirements applicable to Pet registration.
* The submitted Pet information satisfies the minimum requirements for registration.

---

## 3. Business Rules

### BR-1 — A Pet is an independent domain entity

Registering a Pet must create a Pet with its own domain identity.

The Pet must not be represented merely as embedded data inside:

* a User profile;
* an Organization;
* a Clinic;
* an Appointment;
* a medical record.

---

### BR-2 — Registration establishes initial Guardianship

Successful Pet registration must establish an active Guardianship relationship between the registering User and the newly created Pet.

Creating the Pet and establishing its initial Guardianship form one logical domain operation.

---

### BR-3 — Pet registration must not leave an unassociated Pet

The registration workflow defined by this Specification must not be considered successful if the required initial Guardianship cannot be established.

The system must not expose a successfully registered Pet without the corresponding initial Guardian relationship.

---

### BR-4 — Guardianship is distinct from User identity

The registering User gains access to the Pet because an explicit Guardianship relationship is established.

The Pet must not be considered accessible merely because the User created a record while authenticated.

---

### BR-5 — A User may register multiple Pets

An existing Guardianship relationship with one or more Pets must not prevent a User from registering additional Pets.

Example:

```text
Maria
├── Luna
├── Toby
└── Coco
```

Each Pet remains a distinct domain entity.

---

### BR-6 — Pet registration does not prevent multiple Guardians

Creating the initial Guardianship relationship must not establish a one-Guardian-only model.

The Pet domain must continue supporting additional Guardians through separate Guardianship workflows.

---

### BR-7 — Registering a Pet does not grant unrelated capabilities

Pet registration must not automatically grant:

* Veterinarian professional status;
* Organization Membership;
* Clinic Assignment;
* Organization administrative capabilities;
* access to another Pet;
* access to unrelated medical records.

---

### BR-8 — Professional status does not change Pet registration behavior

A User who is also a Veterinarian may register a personal Pet through the same Guardianship model.

Veterinary professional status must not replace or bypass the required Guardianship relationship.

Example:

```text
Maria
├── Veterinarian Professional Profile
│
└── Guardianship
      └── Luna
```

These are independent capabilities.

---

### BR-9 — Pet registration does not create medical history by itself

Registering a Pet must not automatically create:

* a clinical consultation;
* a diagnosis;
* a vaccination;
* a Treatment;
* a Medical Record Entry;
* an Appointment.

A Pet may exist before any veterinary activity has been recorded in the platform.

---

### BR-10 — Pet registration does not associate the Pet with a Clinic

A newly registered Pet must not automatically belong to:

* a Clinic;
* a Veterinary Organization;
* a Veterinarian.

Care-provider relationships arise only through applicable veterinary workflows.

---

### BR-11 — Minimum registration data must be limited to Pet identification needs

Pet registration should require only the information necessary to establish a usable Pet identity for the supported product workflow.

Information that is not necessary for initial Pet registration must not become mandatory solely because it may be useful later.

---

### BR-12 — Pet name alone is not Pet identity

A Pet's public or human-facing name must not be used as its technical identity.

A User may have more than one Pet with the same name.

Example:

```text
Maria
├── Luna
└── Luna
```

The two Pets remain distinct domain entities.

---

### BR-13 — Microchip identification is not mandatory by assumption

A Pet must not be required to have a microchip identifier unless a dedicated Requirement establishes that restriction.

The product must support Pets for which no microchip identifier is available.

---

### BR-14 — Pet registration must not rely on microchip uniqueness alone

Where a microchip identifier is provided, it may become relevant to identity matching or duplicate detection.

However, Pet identity must not be reduced solely to the presence or absence of a microchip identifier.

Duplicate-detection and Pet-identity reconciliation require separate behavior.

---

### BR-15 — Registration must not silently merge Pets

If submitted information appears similar to an existing Pet, the registration workflow must not silently merge the new Pet with an existing domain entity.

Any Pet matching, duplicate resolution, or record-merging workflow requires explicit behavior.

---

### BR-16 — Initial Guardianship does not define the complete future permission model

The initial Guardian established during registration receives the permissions required by the applicable Guardianship model.

This Specification does not define all future Guardian relationship types or delegation rules.

Those behaviors must be specified separately.

---

### BR-17 — Behavioral safety information is optional

Pet registration may include optional behavioral or handling information
that may be relevant to the safety of the Pet, veterinary professionals,
or other people.

The absence of behavioral safety information must not prevent Pet
registration.

Behavioral safety information must not be reduced to a permanent assumption
about the Pet's behavior in every context.

---

### BR-18 — Minimum registration information

Pet registration requires a valid name and species.

All other initial Pet information defined by this Specification is optional
unless a later approved Specification explicitly establishes an additional
requirement.

Unknown optional information must not prevent registration.

The system must not require Users to invent unknown information merely to
satisfy Pet registration.

---

## 4. Initial Pet Information

Phase 1 Pet registration must support enough information to identify and
describe the Pet meaningfully.

### Required fields

- name;
- species.

### Optional fields

- breed where known;
- sex where known;
- date of birth where known;
- approximate date of birth where the exact date is unavailable;
- microchip identifier where available;
- profile image where supported;
- behavioral or handling safety information where relevant.

Optional information must not prevent Pet registration when omitted.

The system must not require Users to invent unknown information merely to
satisfy registration.

---

## 5. Scenarios

### Scenario: Register a Pet successfully

Given Maria is an authenticated User
And Maria satisfies the required account verification state
And Maria provides valid Pet registration information

When Maria registers Luna

Then Luna is created as a new Pet domain entity
And an active Guardianship relationship is established between Maria and Luna
And Luna has her own domain identity
And the registration operation succeeds atomically

---

### Scenario: Pet registration fails if initial Guardianship cannot be established

Given Maria is allowed to register a Pet

When the Pet cannot be created together with the required initial Guardianship

Then the Pet registration operation fails
And the system must not expose a successfully registered Pet without an initial Guardian

---

### Scenario: User registers multiple Pets

Given Maria already has Guardianship of Luna

When Maria successfully registers Toby

Then Toby is created as a separate Pet
And Maria has Guardianship of Toby
And Maria's Guardianship of Luna remains unchanged

---

### Scenario: Two Pets may have the same name

Given Maria already has Guardianship of a Pet named Luna

When Maria registers another valid Pet also named Luna

Then the second Luna may be created
And both Pets remain distinct domain entities
And Pet identity does not depend on name uniqueness

---

### Scenario: Veterinarian registers a personal Pet

Given Maria is a recognized Veterinarian
And Maria is authenticated
And Maria satisfies the requirements for Pet registration

When Maria registers Luna as a personal Pet

Then Luna is created
And Maria becomes Luna's Guardian through the normal Guardianship relationship
And Maria's Veterinarian Professional Profile remains independent
And professional status does not grant additional Pet ownership semantics

---

### Scenario: Registration does not associate Pet with a Clinic

Given Maria successfully registers Luna

When Pet registration completes

Then Luna is not automatically associated with any Clinic
And Luna is not automatically associated with any Veterinary Organization
And Luna is not automatically assigned to a Veterinarian

---

### Scenario: Registration does not create medical activity

Given Maria successfully registers Luna

When Pet registration completes

Then no Appointment is created solely because Luna was registered
And no Medical Record Entry is created solely because Luna was registered
And no clinical event is inferred

---

### Scenario: Pet without microchip can be registered

Given Maria is allowed to register a Pet
And Luna does not have an available microchip identifier
And all mandatory Pet registration information is otherwise valid

When Maria registers Luna

Then Luna may be registered successfully
And absence of a microchip identifier does not by itself prevent registration

---

### Scenario: Similar Pet data does not cause silent merge

Given Maria already has a Pet named Luna
And Maria submits registration information for another Pet with similar identifying characteristics

When the new Pet is registered through this workflow

Then the system must not silently replace or merge the existing Luna
And any duplicate-resolution behavior requires an explicit separate workflow

---

### Scenario: Unauthenticated User attempts Pet registration

Given Maria is not authenticated

When Maria attempts to register Luna

Then the operation is denied
And no Pet is created
And no Guardianship is created

---

### Scenario: User without required verification attempts Pet registration

Given Maria is authenticated
And Maria does not satisfy the verification requirement for Pet registration

When Maria attempts to register Luna

Then the operation is denied
And no Pet is created
And no Guardianship is created

---

### Scenario: Pet can be registered with behavioral safety information

Given Maria is allowed to register a Pet
And Luna may require additional handling precautions

When Maria registers Luna with optional behavioral safety information

Then Luna is registered successfully
And the behavioral safety information is associated with Luna
And the information does not change Luna's domain identity

---

### Scenario: Behavioral safety information is not required

Given Maria is allowed to register Luna
And Maria provides no behavioral safety information

When Maria registers Luna with all required Pet information

Then Luna may be registered successfully

---

### Scenario: Register Pet with only required information

Given Maria is allowed to register a Pet

When Maria registers Luna with a valid name and species

Then Luna is registered successfully
And optional Pet information may remain absent

---

### Scenario: Pet registration without species is rejected

Given Maria is allowed to register a Pet

When Maria attempts to register Luna without a species

Then the registration is rejected
And no Pet is created
And no Guardianship is created

---

### Scenario: Pet registration without name is rejected

Given Maria is allowed to register a Pet

When Maria attempts to register a Pet without a name

Then the registration is rejected
And no Pet is created
And no Guardianship is created

---

## 6. Edge Cases

### Unknown birth date

The system should support Pets whose exact date of birth is unknown.

An approximate age or approximate birth date may be represented if product requirements require it.

The product must not force Users to invent an exact birth date merely to satisfy a technical field.

---

### Unknown breed

A Pet may have an unknown, mixed, or non-applicable breed.

Breed must not be assumed to be universally known.

---

### Missing microchip

A missing microchip identifier does not invalidate Pet identity.

Microchip availability depends on the animal and real-world circumstances.

---

### Existing Pet may already be represented in the platform

A Guardian may attempt to register a Pet that another Guardian has already registered.

The system will eventually need a safe workflow for identifying and reconciling that situation.

This Specification must not guess that two Pets are the same solely from similar submitted information.

---

### Incorrect Pet registration

A User may register incorrect Pet information.

Editing normal Pet profile information and resolving mistaken duplicate Pet identities are separate concerns and may require different workflows.

---

## 7. Relevant Invariants

* **INV-001 — One User may have multiple capabilities.**
* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**

---

## 8. Dependencies

* SPEC-ID-001 — Register User
* SPEC-ID-002 — Verify Email Address
* SPEC-ID-003 — Authenticate User

---

## 9. Out of Scope

This Specification does not define:

* adding another Guardian;
* removing a Guardian;
* Guardianship transfer;
* Guardian permission levels;
* historical Guardianship;
* Pet profile editing;
* Pet deletion;
* Pet archival;
* duplicate-Pet resolution;
* Pet merging;
* microchip verification;
* ownership verification through external registries;
* Appointment creation;
* Medical Record creation;
* Clinic association;
* veterinary professional access;
* Pet sharing outside Guardianship;
* medical-access authorization.

---

## 10. Verification Notes

Verification must demonstrate that:

1. an eligible authenticated User can register a Pet;
2. Pet registration creates a distinct Pet domain entity;
3. registration creates the required initial Guardianship;
4. Pet creation and initial Guardianship behave atomically;
5. a User may register multiple Pets;
6. Pet names are not treated as unique identifiers;
7. a Veterinarian may also register and act as Guardian of a personal Pet;
8. Pet registration does not associate the Pet with a Clinic or Organization;
9. Pet registration does not create an Appointment or clinical information;
10. absence of a microchip identifier does not prevent registration;
11. similar submitted Pet information does not cause silent Pet merging;
12. unauthenticated or insufficiently verified Users cannot register Pets.

# SPEC-VET-006 — View Organization Veterinarian Workforce

**Status:** APPROVED
**Requirements:** REQ-VET-003, REQ-VET-004, REQ-ORG-005
**Domain:** Veterinary Professionals
**Priority:** P1

## 1. Intent

Allow an Organization administrator to see, for one Veterinary Organization,
which current Members take part in the Veterinarian workforce: whether each has
completed their Veterinarian Professional Profile and at which Clinics each
currently practices. This is the minimum information needed to manage Clinic
Assignments (`SPEC-VET-004` §13, `SPEC-VET-005` §13) from the professional app,
without SQL or developer intervention.

It is the read side of **Staff Responsibility Editing + Veterinarian Enablement
— Phase 1**. It complements the Organization Staff read (`SPEC-ORG-009`), which
deliberately carries no Profile or Clinic Assignment data. The two reads are
joined on the client by `membership_id` only.

The read reports current management state only. It is not a history view.

---

## 2. Preconditions

- The acting User exists and is authenticated.
- The acting User currently holds `ORGANIZATION_GRANT_RESPONSIBILITIES` in the
  target Veterinary Organization (`SPEC-ORG-005` §11).

---

## 3. Business Rules

### BR-1 — Canonical operation and payload

    get_organization_veterinarian_workforce(p_organization_id uuid) returns jsonb

returns exactly:

```text
{
  "organization_id": uuid,
  "members": [
    {
      "membership_id": uuid,
      "has_veterinarian_professional_profile": boolean,
      "clinic_assignments": [
        {
          "veterinarian_clinic_assignment_id": uuid,
          "clinic": { "clinic_id": uuid, "clinic_display_name": text | null }
        }
      ]
    }
  ]
}
```

All members are always present; absence is an empty array.

---

### BR-2 — Authorization and fail-closed outcome

The read requires `ORGANIZATION_GRANT_RESPONSIBILITIES` for the target
Organization, evaluated by the authoritative Organization-capability
evaluation. In Phase 1 only an active Organization-scoped `OWNER` or
`ADMINISTRATOR` holds it. A Clinic-scoped Administrator, a Receptionist, a
Veterinarian, bare Membership, an ended Membership or Grant, and a Member of
another Organization are denied.

A nonexistent Organization and an Organization the acting User may not manage
fail identically with SQLSTATE `42501` and one fixed message. An
unauthenticated caller is rejected as unauthenticated (`28000`) first.

No capability is added, and the read requires no Subscription or Entitlement.

---

### BR-3 — Which Members are listed

`members` contains exactly the current Memberships of the target Organization
(effective start not in the future and no effective end) that have at least one
of:

- a current Organization-scoped `VETERINARIAN` Responsibility Grant;
- a current Veterinarian Clinic Assignment supported by that Membership.

A Member whose `VETERINARIAN` Grant has ended but who still has a current
Clinic Assignment is therefore listed, so that the Assignment can be ended
(`SPEC-VET-005` §13). Members are ordered by Membership effective start, then
`membership_id`.

---

### BR-4 — Profile existence only

`has_veterinarian_professional_profile` reports whether the Member's User has a
Veterinarian Professional Profile. No credential fact — registration
identifier, issuing context, credential identifier, or verification state — and
no Profile identifier is exposed.

---

### BR-5 — Current Clinic Assignments only

`clinic_assignments` contains exactly the Member's Clinic Assignments that are
current (`SPEC-VET-005` §7) and supported by that Membership, at Clinics of the
target Organization, each with the Clinic identity and its current
public-profile display name (`null` when it has none). Ended Assignments are not
returned. Entries are ordered by Clinic id, then Assignment id.

---

### BR-6 — Identity privacy and isolation

The read never exposes a domain User id, an authentication identifier or email,
an Invitation address, a display name, or any data of another Organization.
Display identity comes from the Staff read, joined by `membership_id`.

---

### BR-7 — Side-effect free and consistent

The read modifies nothing, takes no row lock, observes one snapshot at one
evaluation instant, and is `STABLE`, `SECURITY DEFINER`, with an empty
`search_path`, executable only by `authenticated`. It is advisory: every
Assignment and Responsibility write re-authorizes itself.

---

## 4. Scenarios

### Scenario: Veterinarian without a Profile

Given Dr. Garcia accepted an Invitation as `VETERINARIAN` in Animalia
And has not created her Professional Profile

When Maria, an Animalia Owner, reads the workforce

Then Dr. Garcia is listed with `has_veterinarian_professional_profile = false`
and no Clinic Assignments

### Scenario: Veterinarian practicing at two Clinics

Given Dr. Garcia has a Profile and current Assignments at Madrid Centro and
Getafe

When Maria reads the workforce

Then both Assignments are listed with their Clinic names
And no credential data is returned

### Scenario: Stale Assignment remains manageable

Given Carlos's `VETERINARIAN` Grant was ended by trusted provisioning while his
Madrid Centro Assignment stayed open

When Maria reads the workforce

Then Carlos is listed with that current Assignment

### Scenario: Other roles are not listed

Given Laura holds only `RECEPTIONIST` and no Assignment

When Maria reads the workforce

Then Laura is not listed

### Scenario: Unauthorized and unknown Organizations are indistinguishable

When a Receptionist reads Animalia's workforce, or anyone reads an unknown
Organization

Then the same `42501` outcome is returned

---

## 5. Mobile presentation

The read is used only by the Staff Member detail (`SPEC-ORG-009` §7), loaded
together with the Staff read for the route Organization, keyed and invalidated
by that Organization. A `42501` clears managed content as for the Staff read.
The Veterinarian section shows "Veterinarian profile completed / Perfil
veterinario completado" or "Veterinarian profile pending — completed by the
professional / Perfil veterinario pendiente — lo completa el profesional", and
one row per current Clinic Assignment.

---

## 6. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-007 — Veterinarian Clinic Assignment is temporal.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-019 — Professional context is derived, not stored.**

---

## 7. Dependencies

- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ORG-006 — Change Organization Membership Responsibilities
- SPEC-ORG-009 — View Organization Staff
- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment

---

## 8. Out of Scope

- ended Assignment or Responsibility history;
- credential data or verification state;
- Veterinarian Availability and Appointment Veterinarian Assignment;
- Clinic-scoped administrator workforce views;
- an all-Organizations view.

---

## 9. Verification Notes

Verification must demonstrate that:

1. an Organization-scoped Owner or Administrator reads the workforce;
2. a Clinic-scoped Administrator, Receptionist, Veterinarian, bare Member, and
   a Member of another Organization are denied, identically to an unknown
   Organization;
3. Members with a current `VETERINARIAN` Grant are listed with Profile
   existence, with and without a Profile;
4. a Member with a current Assignment and no current `VETERINARIAN` Grant is
   listed;
5. Members with neither are not listed, nor are ended Memberships;
6. multiple current Assignments are listed with Clinic identity; ended ones are
   not;
7. no credential, Profile id, User id, Auth identifier, or email appears;
8. no other Organization's Member, Clinic, or Assignment appears;
9. the payload shape is exactly BR-1;
10. the read writes nothing and takes no row lock.

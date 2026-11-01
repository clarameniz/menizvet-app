# SPEC-MED-009 — View Appointment Clinical Record

**Status:** SUPERSEDED by SPEC-MED-010 (2026-10-23; describes the deployed schema until transition stage M2)  
**Requirements:** REQ-MED-003, REQ-MED-007, REQ-MED-013, REQ-ACC-002  
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): this Specification becomes `SUPERSEDED` by SPEC-MED-010 BR-20 and BR-21 (Appointment clinical record read and audit). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

Defined by **Minimal Clinical Record — Phase 1**.

## 1. Intent

Allow an authorized Veterinarian, from the professional Appointment detail, to
see what clinical documentation is possible for that Appointment and to read
the clinical work of its Appointment-backed Clinical Encounter, in one
audited read.

It is the read side of the Appointment-keyed client contract
(`SPEC-MED-001` §15, `SPEC-MED-002` §14, `SPEC-MED-003` §15, `SPEC-MED-008`
§15). It is not the Pet's longitudinal medical history (`SPEC-MED-005`): it
never returns information from other Encounters, Appointments, Clinics, or
Organizations.

---

## 2. Preconditions

- The acting User is authenticated and has a coherent domain User.
- The Clinic and Appointment are named by the Professional client.

---

## 3. Business Rules

### BR-1 — Canonical read

    view_appointment_clinical_record(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It takes no Care Authorization, Pet, Encounter, or Entry
identifier. It takes no row locks.

### BR-2 — Authority

Access requires the acting User's current exact-Clinic Veterinarian context
holding `CLINICAL_DOCUMENTATION` at the Clinic (`SPEC-MED-001` BR-37), and an
Appointment of that Clinic.

Otherwise the result is `{"status": "DENIED"}` with nothing else. An unknown
Clinic or Appointment, an Appointment of another Clinic, and a lack of
authority are indistinguishable.

### BR-3 — Before an Encounter exists: start context only

When no Clinical Encounter references the Appointment, the result is
operational start context, never medical information:

- `appointment`: `appointment_id`, `lifecycle_state`;
- `encounter`: `null`;
- `start`:
  - `can_start`;
  - `start_now_allowed` — `true` only for a `CONFIRMED` Appointment that can be
    started (`SPEC-MED-001` BR-40);
  - `care_start_required` — `true` for a `COMPLETED` Appointment;
  - `care_start_from` — the latest of the confirmation Lifecycle Event, the
    Care Authorization grant, and the start of the acting Veterinarian's
    current Clinic Assignment;
  - `care_start_until` — the completion Lifecycle Event of a `COMPLETED`
    Appointment, or `null` (meaning "now") for a `CONFIRMED` one;
  - `unavailable_reason` — `null` when `can_start` is `true`, otherwise exactly
    one of, evaluated in this order:
    `CLINICAL_CARE_NOT_PERMITTED` (no `CLINICAL_CARE` capability),
    `APPOINTMENT_STATE` (not `CONFIRMED` or `COMPLETED` with a legitimate
    confirmation and, when `COMPLETED`, completion),
    `CARE_AUTHORIZATION_INACTIVE` (the Appointment-derived Care Authorization
    is not `ACTIVE`),
    `CLINICAL_SERVICE_UNAVAILABLE` (the Organization lacks the `CLINICAL_CARE`
    Entitlement),
    `NO_VALID_CARE_START` (the window is empty).

`care_start_from` and `care_start_until` are present only when `can_start` is
`true`. The values are advisory; `start_appointment_clinical_encounter`
re-validates everything.

This branch exposes no prior medical information, consistent with the narrow
pre-Encounter boundary of a `COMPLETED` Appointment (`SPEC-ACC-001` BR-42,
`SPEC-ACC-002` BR-55), and creates no Medical Access Audit Event: it is not a
medical-access operation.

### BR-4 — With an Encounter: clinical work

When an Encounter references the Appointment, access is permitted when the
Encounter is `ACTIVE` (including revocation-safe active-care continuity,
`SPEC-ACC-002` BR-19, BR-20) or the Care Authorization is `ACTIVE` (post-care
documentation, `SPEC-ACC-002` BR-35, BR-36). Otherwise the result is
`{"status": "DENIED"}`. No Entitlement is required (`SPEC-SUB-004` BR-15–BR-18).
This basis is also the Amendment write basis (`SPEC-MED-004` BR-41); both use
one server-side predicate.

A permitted result contains:

- `appointment`: `appointment_id`, `lifecycle_state`;
- `start`: `null`;
- `encounter`:
  - `encounter_id`, `lifecycle_state` (`ACTIVE` / `CONCLUDED`), `started_at`,
    `concluded_at`;
  - `is_mine_responsible` — the Encounter's responsible Clinic Assignment is
    the acting Veterinarian's current one;
  - `may_create_draft` — equal to `is_mine_responsible` (`SPEC-MED-002`
    BR-33);
  - `may_edit`, `may_finalize` — `true` (a permitted read implies the
    documentation conditions of `SPEC-MED-002` BR-35 and `SPEC-MED-003` BR-37);
  - `may_conclude` — the Encounter is `ACTIVE` and the acting User holds
    `CLINICAL_CARE` at the Clinic;
  - `may_amend` — `true` (a permitted read implies the Amendment authority and
    access basis of `SPEC-MED-004` BR-40/BR-41; it applies only to `FINALIZED`
    Entries);
  - `entries` — every Clinical Record Entry of that Encounter, oldest first, at
    most 100, each with `entry_id`, `lifecycle_state` (`DRAFT` / `FINALIZED`),
    `revision_sequence`, `category`, `other_category_context`,
    `clinical_content`, `clinical_event_at`, `created_at`, `finalized_at`,
    `created_by_me`, `amendments`, and `amendments_truncated`;
  - `entries_truncated`.

`amendments` are the Clinical Amendments of that Entry (`SPEC-MED-004` §15),
oldest first (creation time, then identity), at most 100, each with
`amendment_id`, `reason`, `amendment_content`, `created_at`, and
`amended_by_me`; `amendments_truncated` is `true` when more exist. A Draft
always has none.

No Care Authorization, User, Auth, Membership, Responsibility Grant, or Clinic
Assignment identifier, no contributor list, and no Attachment metadata is
returned. The professional client presents authorship only as **You / Tú** or
**Another veterinarian / Otro veterinario** from these booleans; no
Veterinarian display name is part of this Phase.

### BR-5 — One audit event per clinical access

A permitted Encounter read creates exactly one Medical Access Audit Event
(`SPEC-ACC-003`), however many Entries and Amendments it returns: operation
`ACCESS_FOR_CLINICAL_CARE` for an `ACTIVE` Encounter or
`ACCESS_FOR_POST_CARE_DOCUMENTATION` for a `CONCLUDED` one, actor context
`PROFESSIONAL_CLINICAL`, scope `ENCOUNTER_MEDICAL_INFORMATION`, with the Pet,
Care Authorization, Clinic, Organization, Appointment, Encounter, and the
acting professional context.

A denied read of an Appointment that has an Encounter, by an authenticated
User, creates one `DENIED` event of the same operation and scope, with the
professional context only when one exists. A denial where the Appointment does
not belong to the Clinic, or has no Encounter, involves no medical information
and creates none.

### BR-6 — Read only

The read changes no Appointment, Care Authorization, Encounter, Entry, or
Communication.

---

## 4. Out of Scope

- the Pet's longitudinal and cross-clinic medical history (`SPEC-MED-005`),
  including Amendments of Entries outside this Encounter. Its Appointment-keyed
  client read (`SPEC-MED-005` §15) is a separate audited read with its own
  window (`SPEC-MED-005` BR-40); it does not widen or narrow this record's
  BR-4 basis;
- Clinical Attachments presentation (`SPEC-MED-007`);
- Encounters without an Appointment (Clinical Intake);
- Veterinarian display identity in this record (the longitudinal history shows
  names under `SPEC-MED-005` BR-44 and `SPEC-ID-006` BR-41).

---

## 5. Verification Notes

Verification must demonstrate that:

1. an unauthenticated caller is rejected and an unauthorized actor, an unknown
   Appointment, and an Appointment of another Clinic all receive the same
   `DENIED`;
2. before an Encounter exists, a `CONFIRMED` Appointment reports
   `can_start`, `start_now_allowed`, and `care_start_from`, a `COMPLETED` one
   reports `care_start_required` and both bounds, and each unavailable reason
   is reported in its order;
3. the start branch returns no medical information and creates no audit event;
4. with an Encounter, the read returns every Entry with its content and state,
   the Encounter state, and the permission booleans, and creates exactly one
   audit event regardless of the number of Entries;
5. a Draft is returned only to authorized Veterinarians, marked `DRAFT`;
6. `is_mine_responsible` and `may_create_draft` are `true` only for the
   responsible Veterinarian, and `may_conclude` is `false` once `CONCLUDED`;
7. a `CONCLUDED` Encounter whose Care Authorization is no longer `ACTIVE` is
   `DENIED` and audited as denied;
8. the result contains no Care Authorization, User, Auth, Membership, Grant, or
   Clinic Assignment identifier;
9. after the Organization loses the `CLINICAL_CARE` Entitlement, an existing
   Encounter remains readable;
10. reading changes no domain state;
11. each `FINALIZED` Entry carries its Amendments oldest first, with reason,
    content, time, and `amended_by_me`, and no User or Clinic Assignment
    identifier; the original Entry content is unchanged beside them;
12. a read returning Amendments still creates exactly one audit event.

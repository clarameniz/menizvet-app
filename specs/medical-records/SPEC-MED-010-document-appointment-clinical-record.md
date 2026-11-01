# SPEC-MED-010 — Document Appointment Clinical Record

**Status:** APPROVED  
**Requirements:** REQ-MED-001, REQ-MED-002, REQ-MED-003, REQ-MED-004, REQ-MED-005, REQ-MED-008, REQ-MED-009, REQ-MED-010, REQ-MED-011, REQ-MED-013, REQ-ACC-001, REQ-ACC-002, REQ-ACC-004, REQ-ACC-005  
**Domain:** Medical Records  
**Priority:** P0  
**Decision:** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (product decision approved 2026-10-23, Punto 8)

Approved on 2026-10-23. This Specification supersedes `SPEC-MED-001`,
`SPEC-MED-008`, and `SPEC-MED-009`, and amends the Specifications listed in
§11. It is implemented in the stages of
[CLINICAL_DOCUMENTATION_TRANSITION.md](../../docs/CLINICAL_DOCUMENTATION_TRANSITION.md) §5.

## 1. Intent

Allow the Veterinarian assigned to a confirmed Appointment to document its
veterinary care directly, as a list of Clinical Record Entries belonging to
that Appointment, without starting or concluding any separate care context.

The everyday flow is: assign the Veterinarian (or "Assign to me"), document
the visit, complete the Appointment — in any order after confirmation, except
that recording requires the assignment.

Conceptually:

    Appointment
      └── Clinical Record Entry 0..n   (version 1, never overwritten)
            ├── Clinical Amendment 0..n  (EDIT: version 2..n; ADDENDUM: legacy)
            └── Clinical Attachment 0..n

Documentation is independent of Appointment completion: it may happen before
or after `COMPLETED`.

Access to the Pet's prior medical history and access to the Appointment's own
records are separate. The Guardian's Care Authorization governs the first,
never the second.

---

## 2. Preconditions

- The acting User is authenticated and has a coherent domain User.
- The Professional client names the Clinic and the Appointment it shows
  (`/professional/clinics/[clinicId]/appointments/[appointmentId]`).

---

## 3. Business Rules

### Part A — Clinical Record Entries belong to the Appointment

#### BR-1 — Every Entry belongs to exactly one Appointment

A Clinical Record Entry references exactly one Appointment. The reference is
established at recording and is immutable.

There is no intermediate Clinical Encounter. No operation creates, starts,
concludes, or reads one.

#### BR-2 — Provenance is derived from the Appointment

The Entry's Pet is the Appointment's Pet, its Clinic is the Appointment's
Clinic, and its Veterinary Organization is that Clinic's Organization. All three
sources are immutable, so the derived provenance can never change after
recording (`SPEC-MED-005` BR-13, INV-009).

None of them is copied onto the Entry.

#### BR-3 — Only a confirmed Appointment can be documented

An Entry may be recorded only for an Appointment that:

1. has exactly one `REQUESTED → CONFIRMED` Lifecycle Event (it was legitimately
   confirmed while its Care Authorization was valid, `SPEC-APT-002`); and
2. is currently `CONFIRMED` or `COMPLETED`.

A `REQUESTED`, `CANCELLED`, `NO_SHOW`, or `EXPIRED` Appointment can never
receive an Entry.

No scheduled-start condition applies: the scheduled time does not prove whether
care has begun, and care may legitimately begin early.

This rule is enforced structurally on every insertion, not only by the client
operation.

#### BR-4 — An Entry is immediately clinical history and keeps every version

Saving an Entry records it as established clinical history of the Pet. It is
immediately part of the Pet's medical history and visible to authorized
Guardians (`SPEC-MED-005`).

There is no server-side Draft and no separate finalization step. An Entry is
never finalized later, reopened, or deleted. Its author may **edit** it
(BR-18): to the user an edit changes the record; in persistence nothing is
overwritten — the recorded Entry stays as version 1, each edit is a new,
immutable version, and every read presents the **current version** with the
earlier ones available as its history.

Unsaved text exists only in the editor of the client that is writing it.

#### BR-5 — Entry content

An Entry records:

- a category from the `SPEC-MED-006` taxonomy — required;
- clinical content — required, trimmed of surrounding whitespace, never blank;
- the `OTHER` context — required with `OTHER`, accepted only with `OTHER`.

The only date of a new Entry is its recording time, the server's statement
instant (BR-6a); the client never supplies a time. Since stage M5 no clinical
event time is recorded: `clinical_event_at` remains only on Entries recorded
before M5, is never set, defaulted, or changed, and is kept as recorded for
their history order (BR-22). The recording time is presented as when the
record was documented, never as when care occurred.

#### BR-6 — Only the assigned Veterinarian records new Entries

An Appointment may have at most one current Appointment Veterinarian
Assignment (`SPEC-APT-007` §13). A new Entry may be recorded only when:

1. the Appointment has a current Appointment Veterinarian Assignment; and
2. its Veterinarian Clinic Assignment is the acting User's own current Clinic
   Assignment at the Appointment's Clinic, within an eligible Veterinarian
   context (`SPEC-APT-007` BR-31).

A stale assignment — whose Clinic Assignment, Membership, or `VETERINARIAN`
Responsibility has ended — authorizes no write. Any other Veterinarian, an
Administrator, a Receptionist, or an Owner cannot record an Entry for the
Appointment, whatever their other capabilities.

The rule is evaluated by the server under the Appointment lock at recording
(BR-26) and enforced structurally on insertion; client state never decides it.

#### BR-6a — Authorship

An Entry preserves:

- the authoring User;
- the author's concrete Veterinarian Clinic Assignment, which is the assigned
  one at recording;
- the recording time, which is the server's statement instant.

Recording time, any historical clinical event time, and the Appointment's
scheduled time are distinct facts and are never substituted for one another
(`CONVENTIONS` §8). An edit never changes the recording time or the author; each
version records its own time and its own Clinic Assignment.

Authorship is fixed at recording. A later reassignment never changes the
author of an existing Entry, Amendment, or Attachment, and never gives the new
assignee authority over them (BR-18, BR-19).

#### BR-7 — Recording is idempotent per intent

Each recording intent carries one caller-generated key, required. The key is
unique per authoring User and is stored with the Entry together with a digest
of the requested facts: Appointment, category, normalized clinical content,
and normalized `OTHER` context (the digest keeps its former shape with an
absent event time, so a request is the same request across stage M5).

| Situation | Result |
| --- | --- |
| The key is new | `CREATED` with `entry_id` |
| The key was used by this User with the same requested facts | `ALREADY_CREATED` with the same `entry_id`; nothing is written |
| The key was used by this User with different facts, including another Appointment | rejected, `23505`, hint `KEY_CONFLICT`; nothing is written |

The client generates one key per editor session and reuses it only to retry the
same save after an uncertain response.

#### BR-8 — Recording does not change the Appointment

Recording an Entry never confirms, completes, cancels, or otherwise transitions
the Appointment, and never changes its scheduling, Veterinarian Assignment, or
Care Authorization.

The first Entry of a `CONFIRMED` Appointment makes a pending Reschedule Proposal
`VOID` with reason `CLINICAL_DOCUMENTATION_STARTED`, in the same transaction
(`SPEC-APT-005` BR-33).

#### BR-9 — Clinical documentation blocks non-attendance outcomes

Once at least one Entry exists for an Appointment:

- Guardian and Clinic cancellation are rejected (`SPEC-APT-003`);
- `NO_SHOW` is rejected (`SPEC-APT-010` BR-5);
- confirmed rescheduling, Reschedule Proposal creation, and acceptance are
  rejected (`SPEC-APT-005` BR-29, `SPEC-APT-006` BR-31).

Completion is not blocked (`SPEC-APT-009` BR-12). Documentation is consistent
with a visit that occurred, not with one that was cancelled or not attended.

#### BR-10 — Reading never writes clinical information

Opening a screen, reading the Appointment clinical record, or reading history
never creates an Entry or any other clinical information. The first clinical
write is always an explicit save.

#### BR-10a — Rules carried over from the superseded Specifications

The following rules of `SPEC-MED-001`, `SPEC-MED-002`, `SPEC-MED-003`,
`SPEC-MED-008`, and `SPEC-MED-009` remain in force for Clinical Record Entries:

- Recording requires a Veterinarian Professional Profile; Owner,
  Administrator, Receptionist, Guardian, or Membership alone never suffices
  (`SPEC-MED-001` BR-5).
- Phase 1 does not require platform credential verification to record, and an
  Entry is never evidence of verified credentials (`SPEC-MED-001` BR-7).
- A Clinic Assignment alone never authorizes documenting arbitrary Pets: the
  Entry is bound to a confirmed Appointment of that Clinic (`SPEC-MED-001`
  BR-8).
- Provenance survives later changes to the author's Membership, Clinic
  Assignment, Organization, or profile, to the Clinic's profile or
  publication, and to the Pet's profile (`SPEC-MED-001` BR-13–BR-17).
- Recording creates no Guardianship, Care Authorization, Appointment
  transition, diagnosis, or other statement beyond its own content
  (`SPEC-MED-001` BR-18–BR-20).
- An Entry belongs to the Pet's longitudinal, provider-independent history and
  keeps its own Clinic and Organization provenance (`SPEC-MED-001` BR-21,
  BR-22).
- Recording time, clinical event time, and scheduled time stay distinct, and
  no future clinical event is represented (`SPEC-MED-001` BR-12, BR-24, BR-25).
- Recording is atomic: an Entry exists with all its provenance, or nothing is
  written (`SPEC-MED-001` BR-26, `SPEC-MED-002` BR-30, `SPEC-MED-003` BR-34).
- The Care Authorization under which the visit was requested and confirmed
  stays traceable through the Appointment; an Entry never implies that it is
  still active (`SPEC-MED-001` BR-32).
- Subscription termination and Clinic closure never delete or rewrite Entries
  (`SPEC-MED-001` §10).
- The Appointment clinical record never returns information from other
  Appointments, Clinics, or Organizations (`SPEC-MED-009` §1).

---

### Part B — Two separate professional access bases

#### BR-11 — Appointment documentation access

A User holds **Appointment documentation access** to an Appointment when all of
the following hold at the time of the operation:

1. the User has a current exact-Clinic Veterinarian context at the
   Appointment's Clinic: current Organization Membership, current
   Organization-scoped `VETERINARIAN` Responsibility, own Veterinarian
   Professional Profile, and current Veterinarian Clinic Assignment at that
   Clinic;
2. that context holds the `CLINICAL_DOCUMENTATION` capability at the Clinic
   (`SPEC-ORG-005`);
3. the Appointment belongs to the Clinic named by the client.

It permits, for that Appointment only:

- reading its Entries, their Amendments, and Attachment metadata, whoever
  authored them;
- recording new Entries when the Appointment is documentable (BR-3) and the
  actor is its current eligible assignee (BR-6);
- editing the actor's own Entries (BR-18);
- managing Attachments of the actor's own Entries (BR-19).

It does **not** depend on the Care Authorization: it survives Guardian
revocation and Appointment completion. It has no time limit; it ends when the
User's own professional context ends (BR-11 rule 1 or 2).

It never permits reading information from other Appointments, other Clinics,
or the Pet's longitudinal history.

An Administrator, Receptionist, or Owner without the Veterinarian context of
rule 1 never holds it.

#### BR-12 — Revocation before any record

A Guardian revocation before any Entry exists closes prior-history access
immediately (BR-14). It does not prevent the Clinic from documenting care that
it actually provides for that confirmed Appointment (BR-11), and documenting
never reopens prior-history access.

#### BR-13 — Commercial gate for new clinical content

Every new Clinical Record Entry, and every new Clinical Attachment, is new
paid clinical activity and requires the Organization's current
`CLINICAL_CARE` Entitlement (`SPEC-SUB-003`) at the time of the operation,
whether or not the Appointment already has Entries. Without it the operation
is rejected with `42501`, hint `CLINICAL_SERVICE_UNAVAILABLE`, distinct from
every domain rejection (`SPEC-SUB-004` BR-34).

Reading the Appointment's records and editing existing Entries follow only their professional rules (BR-11, BR-18) and never depend
on a current Subscription or Entitlement (`SPEC-SUB-004` BR-20, BR-21).

`CLINICAL_DOCUMENTATION` in this Specification always means the professional
capability of `SPEC-ORG-005`, never a commercial Entitlement. No Entitlement is
added; the `CLINICAL_DOCUMENTATION` Entitlement identifier of `SPEC-SUB-003` is
not evaluated by any operation of this Specification.

This supersedes, for Appointment documentation, the `SPEC-SUB-004` BR-17 and
BR-18 continuity of new documentation after Entitlement loss: after the loss,
an author may still correct or complete an existing Entry by editing it (BR-18).

#### BR-14 — Prior-history access

A User holds **prior-history access** through an Appointment when all of the
following hold:

1. rule 1 of BR-11 holds and the context holds `CLINICAL_CARE`;
2. the Organization holds the current `CLINICAL_CARE` Entitlement;
3. the Appointment belongs to the named Clinic;
4. its Appointment-derived Care Authorization is `ACTIVE`;
5. the Appointment is `CONFIRMED`, or `REQUESTED` with its latest requested
   start strictly in the future (`SPEC-ACC-001` BR-39).

No condition depends on whether Entries exist. A `COMPLETED`, `CANCELLED`,
`NO_SHOW`, or `EXPIRED` Appointment never provides it.

The Appointment Veterinarian Assignment neither grants nor restricts it: any
Veterinarian of the Clinic meeting rules 1–5 holds it, assigned or not, and
being assigned never provides it without rules 1–5. The assignment decides
only who may record new documentation (BR-6).

It permits the Appointment-keyed professional longitudinal history read
(`SPEC-MED-005` §15) and nothing else.

#### BR-15 — The two bases are independent

Neither basis implies the other. Appointment documentation access never grants
prior-history access, and prior-history access never permits documentation.

#### BR-16 — Completion ends the Care Authorization

Completing an Appointment (`SPEC-APT-009`) ends its `ACTIVE`
Appointment-derived Care Authorization (`ACTIVE → ENDED`) with the normal-ending
context `APPOINTMENT_COMPLETED`, at the completion Lifecycle Event's effective
time, in the same transaction. A `REVOKED` authorization is unchanged
(`SPEC-ACC-002` BR-46).

`APPOINTMENT_COMPLETED` is distinct from the cancellation, no-show, and expiry
contexts.

Ending or revoking an Appointment's Care Authorization only removes that
Appointment as a basis for reading prior history. It never removes, hides, or
filters that Appointment's own Entries and Amendments: they remain in the
Guardian medical history (`SPEC-MED-005`, Guardianship-based) and in every
later professional history read that another currently authorized
Appointment permits (BR-14, BR-22), because the history projection is never
filtered by the state of the Care Authorization of the Appointment an Entry
belongs to (`SPEC-MED-005` BR-41).

#### BR-17 — Clinic and Pet segregation

Every operation of this Specification is keyed by the Clinic and the
Appointment. The server derives the Pet, the Organization, the Care
Authorization, and the acting professional context. The client never supplies
or chooses a Pet, Organization, Care Authorization, Membership, Responsibility
Grant, or Veterinarian Clinic Assignment.

Authority is decided before any target is revealed:

1. authentication and a coherent domain User — otherwise `28000`;
2. the acting professional context at the named Clinic — otherwise `42501`;
3. the Appointment, which must belong to that Clinic — otherwise `42501`;
4. where supplied, the Entry, Amendment, or Attachment, which must belong to
   that Appointment — otherwise `42501`.

An unknown Clinic, Appointment, Entry, Amendment, or Attachment, one outside
the actor's authority, and one belonging to another Appointment or Clinic all
produce the same `42501` `Clinical record unavailable`, with no hint. Every
other rejection carries a stable hint. No raw database message is part of the
contract.

Structurally, the authoring, amending, and uploading Veterinarian Clinic
Assignment must belong to the acting User and to the Appointment's Clinic and
Organization.

---

### Part C — Corrections and Attachments

#### BR-18 — Editing an Entry (versioned)

**Editing, as the user sees it.** The Entry's own author may edit its
category, clinical content, and `OTHER` context. The edit asks for no reason.
Every read then shows the edited content as the record, with a discreet
"edited" indication and its history of changes.

**Persistence.** An edit never updates the Entry. It appends one immutable
Clinical Amendment of kind `EDIT` that carries the complete new version — its
`version_number` (the recorded Entry is version 1; each edit is the next
integer), category, `OTHER` context, clinical content, the editing User, that
User's current Veterinarian Clinic Assignment at the Clinic, and the server's
time. The **current version** is the highest one; the Entry plus its `EDIT`
Amendments, in version order, are its complete history: what changed, when,
and by whom. Amendments are append-only and never deleted.

Amendments recorded before stage M5 are of kind `ADDENDUM` (the former
`SPEC-MED-004` §15 reason and additive text). They keep their facts, never
change the current version, and are read as earlier corrections; no new
`ADDENDUM` can be created.

**Who.** Editing requires Appointment documentation access (BR-11) to the
Entry's Appointment and is reserved to the Entry's authoring User — otherwise
`23514`, hint `ENTRY_AUTHOR_REQUIRED` — whether or not they are still the
Appointment's assignee. It requires no Entitlement (`SPEC-SUB-004` BR-20) and
does not depend on the Care Authorization: it remains possible after
`COMPLETED` and after a Guardian revocation, and ends only with the author's
own professional context (BR-11). The current assignee never edits another
Veterinarian's Entry; they record a clarifying Entry of their own.

**Field rules** are those of BR-5. Every edit is revalidated by the server.

The operation is BR-23b. Every version is immediately visible wherever its
Entry is, under exactly the Entry's read permissions.

#### BR-19 — Clinical Attachments

A Clinical Attachment belongs to one Entry of the Appointment and is managed
under Appointment documentation access (BR-11) by that Entry's own author only,
under the same conditions as an edit (BR-18). File validation, storage, and
download rules of `SPEC-MED-007` and ADR-001 are unchanged.

Because an Entry is already clinical history when recorded:

- an Attachment may be added to an existing Entry; it is visible to Guardians
  and in professional reads only once validated `AVAILABLE`;
- a `PENDING` Attachment may be abandoned or expire; a `REJECTED` one is never
  shown;
- an `AVAILABLE` Attachment is immutable and is not removed; a correction is an
  edit of the Entry that explains it.

No professional client Attachment workflow is part of this Specification's
first delivery; the rules above bind any later one. The professional
Attachment routes and operations of the former Encounter model are retired
(BR-25, stage M4): no professional client reaches an Attachment. The only
Attachment client path is the Guardian download (`SPEC-MED-007` BR-32), keyed
by the Attachment alone and authorized by the current Guardianship of the
Attachment's own Pet; it accepts no professional context. A later professional
workflow must be specified on these rules and must derive every authority from
the authenticated User and the Entry's Appointment, never from a
client-supplied Care Authorization, Clinic Assignment, Clinic, or Encounter
identifier.

---

### Part D — Reads and audit

#### BR-20 — Appointment clinical record read

    view_appointment_clinical_record(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, takes no row locks, and is
executable only by `authenticated`.

Without Appointment documentation access the result is `{"status": "DENIED"}`
with nothing else.

With it, the result is `{"status": "PERMITTED", ...}` with:

- `appointment`: `appointment_id`, `lifecycle_state`;
- `documentation`: `can_record` and `unavailable_reason` — `null` when
  `can_record`, otherwise the first applicable of `APPOINTMENT_STATE` (BR-3),
  `NO_VETERINARIAN_ASSIGNED`, `NOT_ASSIGNED_VETERINARIAN` (BR-6, including a
  stale assignment of the actor), or `CLINICAL_SERVICE_UNAVAILABLE` (BR-13);
- `entries`: every Entry of that Appointment, oldest first by recording time,
  then identity, at most 100, each with `entry_id`, `category`,
  `other_category_context` and `clinical_content` of the **current version**
  (BR-18), `clinical_event_at` (historical, `null` since M5), `recorded_at`
  (the Entry's original recording time), `recorded_by_me`, `may_edit` (equal
  to `recorded_by_me`, BR-18), `version` (the current version number),
  `edited_at` (the current version's time, `null` when never edited),
  `previous_versions` (every earlier version, oldest first, at most 100, each
  with `version`, `category`, `other_category_context`, `clinical_content`,
  `created_at`), `previous_versions_truncated`, `amendments` (the legacy
  `ADDENDUM` corrections only, oldest first, at most 100, each with
  `amendment_id`, `reason`, `amendment_content`, `created_at`,
  `amended_by_me`), and `amendments_truncated`;
- `entries_truncated`.

No User, authentication, Membership, Responsibility Grant, Clinic Assignment,
or Care Authorization identifier and no Veterinarian name are returned.
Authorship is presented only as **You / Tú** or **Another veterinarian / Otro
veterinario**.

The values are advisory; every write re-validates.

#### BR-21 — Audit of the Appointment clinical record

A permitted read of an Appointment that has at least one Entry creates exactly
one Medical Access Audit Event (`SPEC-ACC-003`), however many Entries and
Amendments it returns: operation `VIEW_APPOINTMENT_CLINICAL_RECORD`, actor
context `PROFESSIONAL_CLINICAL`, scope `APPOINTMENT_CLINICAL_RECORD`, with the
Pet, Appointment, accessing Clinic and Organization, acting Membership,
Responsibility Grant, and Veterinarian Clinic Assignment, and the Care
Authorization only as correlation context when one exists.

A denied read of an Appointment of the named Clinic that has at least one Entry,
by an authenticated User, creates one `DENIED` event of the same operation and
scope with the professional context where one exists.

A read of an Appointment with no Entry returns no medical information and
creates no event. If a required event cannot be written, no clinical content is
returned (ADR-004).

Recording or editing an Entry is not a medical-access read and creates no
audit event; the Entry and its versions preserve actor, time, and context
(`SPEC-ACC-003` BR-57).

#### BR-22 — Longitudinal history projection

The professional (`SPEC-MED-005` §15) and Guardian history reads derive each
Entry's Clinic and Organization display names from the Entry's Appointment and
that Appointment's Clinic.

`history_order_at` is `coalesce(clinical_event_at, recorded_at)` — the
recording time for every Entry recorded since M5. The payload field
`encounter_started_at` is removed. `is_this_appointment` is `true` when the
Entry belongs to the Appointment that roots the read.

Both reads present each Entry's **current version** (category, `OTHER`
context, clinical content) and add `version`, `edited_at`, `previous_versions`
(oldest first, at most 100, each with `version`, `category`,
`other_category_context`, `clinical_content`, `created_at`) and
`previous_versions_truncated`; `amendments`, `amendment_count`, and
`amendments_truncated` concern only legacy `ADDENDUM` corrections. Only the
Entry's author ever edits it, so the author's provenance is the provenance of
every version. No version is reachable without the Entry's own read
permission.

Every recorded Entry appears, because every Entry is clinical history (BR-4).

---

### Part E — Operations

#### BR-23 — Canonical record operation

    create_appointment_clinical_entry(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_idempotency_key uuid,
        p_category text,
        p_clinical_content text,
        p_other_category_context text
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It takes no time: the recording time is the server's (BR-5).
The former eight-argument signature with a clinical event time is retired
(BR-25).

Evaluation order:

1. BR-17 steps 1–3, with the acting context locked in the existing clinical
   lock order, then the Appointment share-locked;
2. key present — otherwise `22023`, hint `KEY_REQUIRED`;
3. field rules (BR-5) — `22023` with `INVALID_CATEGORY`, `CATEGORY_REQUIRED`,
   `CONTENT_REQUIRED`, `OTHER_CONTEXT_REQUIRED`, or `OTHER_CONTEXT_NOT_ALLOWED`;
4. key reconciliation (BR-7) — an exact replay by the original author returns
   `ALREADY_CREATED` even after a later reassignment, because nothing new is
   written;
5. documentable Appointment (BR-3) — otherwise `23514`, hint
   `APPOINTMENT_STATE_INVALID`;
6. current eligible assignee (BR-6), read under the Appointment lock — `23514`,
   hint `NO_VETERINARIAN_ASSIGNED` when there is no current assignment,
   otherwise `NOT_ASSIGNED_VETERINARIAN` when it is not the actor's own current
   Clinic Assignment;
7. the `CLINICAL_CARE` Entitlement (BR-13);
8. recording.

The result contains only `outcome` and `entry_id`; never clinical content.

#### BR-23b — Edit operation

    edit_appointment_clinical_entry(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_entry_id uuid,
        p_idempotency_key uuid,
        p_expected_version integer,
        p_category text,
        p_clinical_content text,
        p_other_category_context text
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. `p_expected_version` is the current version the editor was
opened on (BR-20 `version`).

Evaluation order:

1. authentication — otherwise `28000`;
2. the acting context with `CLINICAL_DOCUMENTATION` at the named Clinic, locked
   in the clinical lock order — otherwise the uniform `42501`;
3. the Entry of that Appointment of that Clinic, locked for update so edits of
   one Entry serialize — otherwise the uniform `42501`;
4. the Entry's author — otherwise `23514`, hint `ENTRY_AUTHOR_REQUIRED`;
5. key present — otherwise `22023`, hint `KEY_REQUIRED`; a positive
   `p_expected_version` — otherwise `22023`, hint `INVALID_VERSION`;
6. field rules (BR-5) — the BR-23 field hints;
7. key reconciliation: the key is unique per User across all Amendments; this
   User's earlier `EDIT` of this Entry with the same normalized fields and
   version `p_expected_version + 1` returns `ALREADY_EDITED` with that version
   and writes nothing; any other use is `23505`, hint `KEY_CONFLICT`;
8. `p_expected_version` equal to the current version — otherwise `P0001`, hint
   `STALE_VERSION` (never `40001` or `409`); nothing is written and the client
   keeps the user's text;
9. fields equal to the current version — `UNCHANGED` with the current version;
   nothing is written;
10. the new `EDIT` version, numbered current + 1 — `EDITED` with that version.

The result contains only `outcome` and `version`; never clinical content. No
Entitlement is evaluated (BR-18). Structurally, an `EDIT` is accepted only from
the Entry's author, only as the next version number (unique per Entry), and
only with BR-5 field shapes; Amendments are never updated or deleted.

#### BR-24 — Other client operations

- `view_appointment_clinical_record` (BR-20);
- `edit_appointment_clinical_entry` (BR-23b);
- `view_appointment_professional_medical_history` — signature and payload of
  `SPEC-MED-005` §15, with the BR-14 window and the BR-22 projection;
- the Guardian Attachment download of the `clinical-attachments` Edge Function
  (`guardian-download`, `authorize_guardian_clinical_attachment_download`),
  keyed by the Attachment alone (BR-19). No professional Attachment operation
  is a client path (BR-25).

#### BR-25 — Retired operations

The following are removed and have no replacement:

- `start_appointment_clinical_encounter`, `conclude_appointment_clinical_encounter`;
- `create_appointment_clinical_draft`, `update_appointment_clinical_draft`,
  `finalize_appointment_clinical_entry`;
- `create_clinical_encounter`, `conclude_clinical_encounter`,
  `create_draft_clinical_record_entry`, `update_draft_clinical_record_entry`,
  `finalize_clinical_record_entry`;
- `view_care_authorization_clinical_work_context`,
  `view_professional_pet_medical_history`, `view_clinical_record_entry`, and
  `get_professional_pet_active_care_authorizations` as client paths;
- since stage M5: the eight-argument `create_appointment_clinical_entry`
  with a clinical event time, `create_appointment_clinical_amendment` (the
  `SPEC-MED-004` §15 reason-and-addition form), and the trusted
  `create_clinical_amendment`; no `ADDENDUM` can be created;
- the professional routes `initiate`, `complete`, `remove`, and
  `professional-download` of the `clinical-attachments` Edge Function, with
  `initiate_clinical_attachment_upload`,
  `resolve_clinical_attachment_completion_target`,
  `remove_draft_clinical_attachment`, and the multi-context
  `authorize_clinical_attachment_download` (stage M4). The Guardian download
  keeps its contract through `authorize_guardian_clinical_attachment_download`;
  the server-to-server `maintenance` route and its Storage validation
  operations remain, with no client authority.

#### BR-26 — Concurrency

- Recording share-locks the Appointment; cancellation, `NO_SHOW`, completion,
  and rescheduling lock it for update. A first Entry and a cancellation or
  `NO_SHOW` therefore serialize: either the Entry exists and the other is
  rejected (BR-9), or the Appointment is terminal and the Entry is rejected
  (BR-3).
- Assignment, reassignment, and self-assignment lock the Appointment for update
  (`SPEC-APT-007` BR-34). A save racing a reassignment therefore serializes:
  either the Entry is recorded by the assignee of that instant and the
  reassignment follows, or the reassignment commits first and the save is
  rejected with `NOT_ASSIGNED_VETERINARIAN`, writing nothing.
- The end of the author's Clinic Assignment, Membership, or Responsibility
  serializes with recording through the locked acting context; after it
  commits, the stale assignment authorizes nothing.
- Recording and completion are compatible in either order, and a `COMPLETED`
  Appointment may be assigned or reassigned before documenting.
- Recording and Guardian revocation do not interact (BR-11, BR-12).
- Prior-history reads and revocation serialize on the Care Authorization, so
  no history is returned after a committed revocation (`SPEC-ACC-002` BR-54).

---

### Part F — Mobile presentation

- The professional Appointment detail shows the assigned Veterinarian and the
  **Assign to me / Asignarme esta cita** and **Assign / Change** actions of
  `SPEC-APT-007` §13.
- It shows a **Clinical record / Registro clínico** section when the advisory
  Clinic capabilities (`SPEC-ORG-008`) include `CLINICAL_DOCUMENTATION`, for a
  `CONFIRMED` or `COMPLETED` Appointment, or whenever Entries exist. Opening it
  performs the audited read of BR-20 only.
- **Add record / Añadir registro** appears only when `can_record`. Otherwise a
  single calm line explains why: no Veterinarian assigned (with **Assign to
  me** when offered), or "Only the assigned veterinarian can add records /
  Solo el veterinario asignado puede añadir registros".
- The section lists the Entries, oldest first, each showing its **current
  version** (category, `OTHER` context, content), one date — "Recorded on /
  Registrado el" with the original recording time — and **You / Another
  veterinarian**; an edited Entry adds a discreet "Edited / Editado" with the
  time of its current version. **View changes / Ver cambios** appears only when
  earlier versions or legacy corrections exist and expands them in place.
- **Add record / Añadir registro** opens an inline editor; opening it calls
  nothing. Fields: a compact category selector (no default), clinical content,
  and the `OTHER` context only for `OTHER`. No time is asked for.
- One short notice above the save action: the record will be visible to the
  Pet's guardians and later changes are documented.
- **Save record / Guardar registro** calls BR-23 once, with no further
  confirmation. After any outcome the client re-reads. An uncertain response
  is retried only with the same key. On `APPOINTMENT_STATE_INVALID` or a
  uniform denial the unsaved text stays on screen and is never stored on the
  device.
- **Editing and clarifications:**
  - on the reader's own Entry (`may_edit`), **Edit / Editar** opens the same
    inline editor filled with the current version; **Save changes / Guardar
    cambios** calls BR-23b once with the version it was opened on and one key
    per edit; no reason is asked for and there is no second confirmation;
    `STALE_VERSION` keeps the text and shows the newer version; an uncertain
    response is retried only with the same key;
  - on another Veterinarian's Entry no edit action is shown; when
    the reader can record (`can_record`), the Entry offers **Add a clarifying
    record / Añadir registro aclaratorio**, which opens the ordinary new-record
    editor with the note "This creates a new record of yours. The original
    record and its author do not change. / Esto crea un registro nuevo tuyo.
    El registro original y su autoría no cambian.";
  - a clarifying record is an ordinary Entry: it carries no reference to the
    original and is shown in the list in recording order under its own
    author.
- If a save is rejected with `NOT_ASSIGNED_VETERINARIAN` or
  `NO_VETERINARIAN_ASSIGNED`, the unsaved text stays on screen and the client
  re-reads the Appointment to show the current assignee.
- **Complete / Marcar como completada**, **No-show**, and cancellation remain
  the Appointment actions of `SPEC-APT-009`, `SPEC-APT-010`, and
  `SPEC-APT-003`; No-show and cancellation are not offered once Entries exist.
  While an editor is open, Complete is not shown.
- The detail is ordered for the visit: Pet, status and a compact date, time,
  and reason; the Veterinarian; prior history; the Clinical record; Complete;
  then the Appointment contact and the secondary administrative actions.
- **View prior history / Ver antecedentes** is offered advisorily when
  the actor holds `CLINICAL_CARE` and the Appointment is `CONFIRMED`, or
  `REQUESTED` with a future start. The server decides (BR-14).
- No Start, Conclude, Draft, or Finalize action exists, and no copy mentions a
  Clinical Encounter, a Care Authorization, an Entitlement, or an identifier.

---

## 4. Scenarios

### Scenario: Veterinarian documents a confirmed Appointment

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro
And Dr. Garcia has a current Veterinarian context there with
`CLINICAL_DOCUMENTATION` and is the Appointment's assigned Veterinarian
And Animalia holds the `CLINICAL_CARE` Entitlement

When Dr. Garcia saves an `EXAMINATION` record

Then one Entry is recorded for that Appointment, authored by Dr. Garcia
And it is immediately visible in Luna's Guardian medical history
And the Appointment remains `CONFIRMED`
And cancellation and `NO_SHOW` are no longer possible

### Scenario: Documentation continues after completion

Given Luna's Appointment was completed by reception without an assigned
Veterinarian

When reception assigns Dr. Garcia, or Dr. Garcia assigns herself, and she saves
a `TREATMENT` record a day later

Then the Entry is recorded for that Appointment
And the Appointment remains `COMPLETED`
And prior-history access through the Appointment is denied

### Scenario: Revocation ends history access but not documentation

Given Luna's Appointment is `CONFIRMED` and its Care Authorization `ACTIVE`

When Maria, a current Guardian, revokes it

Then the professional longitudinal history through the Appointment is denied
And Dr. Garcia can still read and add records of this Appointment
And no record reveals information from other Appointments

### Scenario: Revocation before any record

Given Luna's `CONFIRMED` Appointment has no Entry
And Dr. Garcia is its assigned Veterinarian
And Maria revoked its Care Authorization

When Dr. Garcia records the care actually provided

Then the Entry is recorded
And prior-history access remains denied

### Scenario: Non-attendance outcomes cannot be documented

Given Luna's Appointment is `CANCELLED`, `NO_SHOW`, `EXPIRED`, or `REQUESTED`

When Dr. Garcia attempts to save a record

Then it is rejected with `APPOINTMENT_STATE_INVALID` and nothing is written

### Scenario: Only the assigned Veterinarian records

Given Dr. Garcia is the Appointment's current assignee
And Dr. Lopez is another Veterinarian of the Clinic

When Dr. Lopez attempts to save a record

Then it is rejected with `NOT_ASSIGNED_VETERINARIAN` and nothing is written
And Dr. Lopez can still read the Appointment's records

### Scenario: Veterinarian assigns themselves and documents

Given Luna's `CONFIRMED` Appointment has no assigned Veterinarian
And Dr. Garcia is an eligible Veterinarian of the Clinic

When Dr. Garcia taps **Assign to me** and then saves a record

Then Dr. Garcia is the current assignee
And the Entry is recorded and attributed to Dr. Garcia

### Scenario: Reassignment keeps authorship

Given Dr. Garcia recorded two Entries
And reception reassigns the Appointment to Dr. Lopez

When Dr. Lopez saves a record and Dr. Garcia edits one of her own Entries

Then both succeed
And Dr. Garcia's Entries remain attributed to her
And Dr. Lopez cannot edit Dr. Garcia's Entries (`ENTRY_AUTHOR_REQUIRED`)
And Dr. Garcia can no longer record new Entries

### Scenario: Save racing a reassignment

Given Dr. Garcia is the assignee and is saving a record
And reception concurrently reassigns the Appointment to Dr. Lopez

When both operations commit

Then either Dr. Garcia's Entry was recorded before the reassignment
Or it was rejected with `NOT_ASSIGNED_VETERINARIAN` with nothing written
And never an Entry recorded by Dr. Garcia after Dr. Lopez became assignee

### Scenario: Assignee left the Clinic

Given Dr. Garcia is the assignee and her Clinic Assignment has ended

When she attempts to save a record

Then the operation returns the uniform `42501`
And another eligible Veterinarian may self-assign the stale Appointment

### Scenario: Retry after a lost response

When Dr. Garcia's save response is lost and the client retries with the same
key and content

Then the result is `ALREADY_CREATED` with the same Entry and nothing is
duplicated

### Scenario: Another Clinic cannot reach the record

Given Dr. Ruiz is a Veterinarian only at Animalia Getafe

When Dr. Ruiz names Animalia Madrid Centro or a Madrid Appointment, Entry, or
Amendment

Then every operation returns the uniform `42501` and reveals nothing

### Scenario: Veterinarian who left the Clinic loses documentation access

Given Dr. Lopez recorded an Entry and her Clinic Assignment later ended

When Dr. Lopez opens the Appointment clinical record

Then the read is `DENIED`
And her Entry remains attributed to her

### Scenario: Entitlement lapse after documentation began

Given Luna's Appointment already has an Entry
And Animalia lost the `CLINICAL_CARE` Entitlement

When Dr. Garcia, its assignee, saves another record

Then it is rejected with `CLINICAL_SERVICE_UNAVAILABLE` and nothing is written
And Dr. Garcia can still read the record and rectify her own Entries

### Scenario: Completion ends the Care Authorization

Given Luna's Appointment has an `ACTIVE` Care Authorization

When reception completes the Appointment

Then the authorization becomes `ENDED` with `APPOINTMENT_COMPLETED` at the
completion time
And Appointment documentation access is unchanged

---

## 5. Edge Cases

### Care begins before the scheduled start

It may be documented immediately: BR-3 has no scheduled-start condition.

### A record is written to prevent a Guardian cancellation

A first Entry before the scheduled start blocks Guardian cancellation (BR-9).
This is accepted: Entries are immutable, attributed, and immediately visible to
the Guardian, and the scheduled time does not prove whether care began.

### Typing errors

The author edits the Entry: a record saved as Vaccination, "Annual rabies
vaccine", edited to Clinical note, "Only a nail trim was done", is shown
everywhere as Clinical note with the corrected text, marked as edited; the
original version stays in its history, visible to whoever may read the
Entry.

### Reception completes while a Veterinarian is writing

Nothing is lost: documentation remains possible after completion.

### Reception reassigns while a Veterinarian is writing

The save is rejected (BR-26) and the text stays on screen; the Veterinarian
may ask to be reassigned. Nothing is written under an obsolete assignment.

### The author of an Entry is no longer at the Clinic

The Entry cannot be edited any more (BR-18). The current assignee may record
a new Entry that clarifies it.

---

## 6. Invariants

- Every Clinical Record Entry references exactly one Appointment, immutably.
- No Entry exists for an Appointment that was never confirmed, or that is
  `CANCELLED`, `NO_SHOW`, or `EXPIRED`.
- An Entry, an Amendment, and an `AVAILABLE` Attachment are never updated or
  deleted; an Entry's versions are its row (version 1) and its `EDIT`
  Amendments, numbered without gaps.
- Every author, amender, and uploader Clinic Assignment belongs to its User and
  to the Appointment's Clinic and Organization.
- Every Entry's authoring Clinic Assignment was the Appointment's current
  assignee at its recording instant.
- An Amendment's and an Attachment's User is the original Entry's author.
- At most one current Appointment Veterinarian Assignment exists per
  Appointment.
- An Appointment with an Entry is never `CANCELLED` or `NO_SHOW`.
- A `COMPLETED` Appointment never has an `ACTIVE` Care Authorization.
- **INV-009** — Historical clinical provenance is immutable.
- **INV-010** — Medical history follows the Pet.
- **INV-011** — Professional qualification does not imply medical access.

---

## 7. Dependencies

- SPEC-APT-002, SPEC-APT-003, SPEC-APT-005, SPEC-APT-006, SPEC-APT-007 §13,
  SPEC-APT-008, SPEC-APT-009, SPEC-APT-010, SPEC-APT-012
- SPEC-ACC-001, SPEC-ACC-002, SPEC-ACC-003
- SPEC-MED-004, SPEC-MED-005, SPEC-MED-006, SPEC-MED-007
- SPEC-ORG-005, SPEC-ORG-008, SPEC-SUB-003, SPEC-SUB-004

---

## 8. Out of Scope

- Clinical Intake: care without an Appointment (deferred; a future
  Specification defines its own care context);
- server-side Drafts or any preparation workflow before recording
  (`REQ-MED-007`, deferred);
- a documentation time window after completion;
- Veterinarian display names in the Appointment clinical record;
- the professional client Attachment workflow;
- multi-professional handoff or co-signature;
- correction of an incorrectly completed Appointment.

---

## 9. Retired Behavior

On approval the following behavior no longer exists:

- Clinical Encounter, its `ACTIVE` / `CONCLUDED` lifecycle, care start,
  conclusion, and the Encounter's responsible Veterinarian (the Appointment's
  current Veterinarian Assignment takes that role for new records, BR-6);
- Draft Clinical Record Entries, Draft revisions, finalization as a separate
  step, and contributor attribution;
- revocation-safe active-care continuity (`SPEC-ACC-002` BR-19–BR-21);
- post-care documentation windows tied to Encounter conclusion;
- the start window and `START_TIME_*` hints;
- the audit operation `ACCESS_FOR_POST_CARE_DOCUMENTATION` and scope
  `ENCOUNTER_MEDICAL_INFORMATION`;
- the Reschedule Proposal void reason `CLINICAL_ENCOUNTER_STARTED`, replaced by
  `CLINICAL_DOCUMENTATION_STARTED`;
- the schedule flag `has_clinical_encounter`, replaced by `has_clinical_record`
  (`SPEC-APT-012` BR-48);
- since stage M5: the clinical event time of new Entries and its **Now** choice,
  and the reason-and-addition rectification form (replaced by editing,
  BR-18).

---

## 10. Reading Rule for Other Specifications

Where another Specification lists "Clinical Encounters" among clinical history
that an operation must not create, delete, or rewrite, it reads as "Clinical
Record Entries and their Amendments and Attachments". Where it conditions
behavior on "an existing Clinical Encounter" of an Appointment, it reads as "at
least one Clinical Record Entry of that Appointment". Specifications with
materially affected rules carry an explicit supersession notice (§11).

---

## 11. Affected Specifications

| Specification | Effect |
| --- | --- |
| SPEC-MED-001 | `SUPERSEDED` by this Specification |
| SPEC-MED-008 | `SUPERSEDED`; no conclusion exists |
| SPEC-MED-009 | `SUPERSEDED` by BR-20 and BR-21 |
| SPEC-MED-002 | Draft creation and update retired; recording is BR-1–BR-7, BR-23 |
| SPEC-MED-003 | Separate finalization retired; recording is publication (BR-4) |
| SPEC-MED-004 | §15 replaced by BR-18 and BR-23b: the author edits through versioned `EDIT` Amendments; the reason-and-addition form is retired (stage M5) |
| SPEC-APT-007 | §13 assignment contract (assign, reassign, self-assign, reads) |
| SPEC-APT-008 | Client path replaced by SPEC-APT-007 §13; BR-6, BR-15, BR-25 superseded there |
| SPEC-ORG-005 | No new capability; self-assignment through `CLINICAL_DOCUMENTATION` |
| SPEC-ID-006 | Veterinarian display names in the assignment reads |
| SPEC-MED-005 | BR-40 window replaced by BR-14; projection and ordering by BR-22 |
| SPEC-MED-006 | Entries are categorized at recording; category required (BR-5) |
| SPEC-MED-007 | Attachment parent and removal rules replaced by BR-19 |
| SPEC-ACC-001 | BR-19, BR-20, BR-28, BR-29, BR-41, BR-42 replaced by BR-11–BR-16 |
| SPEC-ACC-002 | BR-15, BR-19–BR-21, BR-34–BR-38, BR-47, BR-48, BR-55, BR-61, §6, §9, §10 and the Guardian copy replaced by BR-11, BR-12, BR-14, BR-16 |
| SPEC-ACC-003 | Operation, scope, and typed-reference changes of BR-21 |
| SPEC-APT-003, SPEC-APT-005, SPEC-APT-006, SPEC-APT-010, SPEC-APT-016, SPEC-APT-017 | Encounter conditions read as Entry conditions (BR-9, §10) |
| SPEC-APT-009 | BR-12–BR-15, BR-21, §4 step 9, §7 replaced by BR-8, BR-9, BR-16 |
| SPEC-APT-012 | BR-48 flag renamed; BR-23, BR-24 read per §10 |
| SPEC-SUB-003 | `CLINICAL_CARE` gates every new Entry and Attachment (BR-13); the `CLINICAL_DOCUMENTATION` Entitlement is not evaluated |
| SPEC-SUB-004 | BR-14–BR-18, BR-24, BR-39 replaced by BR-13; BR-20 and BR-21 apply unchanged |

---

## 12. Verification Notes

Verification must demonstrate that:

1. an Entry is recorded for a legitimately confirmed `CONFIRMED` Appointment,
   before and after its scheduled start, and for a `COMPLETED` one;
2. `REQUESTED`, `CANCELLED`, `NO_SHOW`, `EXPIRED`, and never-confirmed
   Appointments are rejected with `APPOINTMENT_STATE_INVALID`, also for a
   direct insertion outside the operation;
3. the Entry's Appointment cannot be changed and the Entry cannot be updated or
   deleted — an edit appends a version;
4. Pet, Clinic, and Organization provenance in every read equals the
   Appointment's and its Clinic's;
5. a recorded Entry is immediately in the Guardian history, with its
   Amendments;
6. field rules reject a missing category or content and an invalid `OTHER`
   combination, writing nothing; a new Entry has no clinical event time and
   its only date is the server's recording time;
7. idempotency returns `ALREADY_CREATED` for an exact replay, `KEY_CONFLICT`
   for different facts or another Appointment, and distinct keys create
   distinct Entries;
8. only the current eligible assignee records: no assignment is
   `NO_VETERINARIAN_ASSIGNED`, another Veterinarian, an Administrator, or a
   Receptionist is `NOT_ASSIGNED_VETERINARIAN` or the uniform `42501`, a stale
   assignee is refused, and a direct insertion whose authoring Clinic
   Assignment is not the current assignee's is rejected structurally;
9. an actor without the Veterinarian context or `CLINICAL_DOCUMENTATION`, an
   actor of another Clinic, an unknown or foreign Appointment, Entry, or
   Amendment all receive the same `42501`;
10. every new Entry requires the current `CLINICAL_CARE` Entitlement, also
    when the Appointment already has Entries, while reads and Amendments
    succeed without it (no Attachment can be added through any client path
    since stage M4);
11. Appointment documentation access is unchanged by Guardian revocation and by
    completion, before or after the first Entry;
12. prior-history access is permitted only under BR-14, denied immediately
    after revocation and after completion, and never permitted by
    documentation access;
13. completion ends an `ACTIVE` Care Authorization with
    `APPOINTMENT_COMPLETED` at the completion time and leaves a `REVOKED` one
    unchanged;
14. the first Entry voids a pending Reschedule Proposal with
    `CLINICAL_DOCUMENTATION_STARTED`;
15. with an Entry, cancellation, `NO_SHOW`, and rescheduling are rejected and
    completion succeeds;
16. a first Entry racing cancellation or `NO_SHOW` yields exactly one coherent
    outcome;
17. a permitted read with Entries creates exactly one audit event, a read
    without Entries creates none, and a denied read with Entries creates one
    `DENIED` event;
18. reads write no clinical information and no read result carries an
    internal identifier;
19. edits follow BR-18 and BR-23b after completion, after revocation, and
    after reassignment, by the Entry's author only; the current assignee
    receives `ENTRY_AUTHOR_REQUIRED` on another Veterinarian's Entry; repeated
    edits number versions 2, 3, …; an exact replay is `ALREADY_EDITED`, a
    changed one `KEY_CONFLICT`, an edit of an older version `STALE_VERSION`,
    an edit without changes `UNCHANGED`, and two concurrent edits of one
    version yield one `EDITED` and one `STALE_VERSION`;
20. an `AVAILABLE` Attachment cannot be removed or changed, a `PENDING` one is
    never shown, and only the Entry's author manages its Attachments;
21. no retired operation is executable by any client role;
22. a save racing a reassignment either records under the assignee of that
    instant or is rejected with nothing written;
23. reassignment never changes the author of existing Entries, Amendments, or
    Attachments;
24. an exact replay by the original author after a reassignment returns
    `ALREADY_CREATED`, while a new key is rejected;
25. after completion ends, or a Guardian revokes, an Appointment's Care
    Authorization, that Appointment's Entries and Amendments are still
    returned by the Guardian history and by the professional history read
    through another Appointment whose prior-history access is permitted;
26. the retired professional Attachment routes answer `NOT_FOUND` before any
    authentication or body is read, their operations exist under no
    signature, and the Guardian download releases only an `AVAILABLE`,
    stored, current Attachment of a Pet the User currently guards, audited as
    a Guardian access, whatever professional standing or client-supplied
    identifiers the request carries;
27. the Appointment record, the Guardian history, and the professional history
    show each Entry's current version with its original recording time and
    author, `edited_at`, and every earlier version, under exactly the Entry's
    read permissions; legacy `ADDENDUM` corrections remain readable and change
    no version.

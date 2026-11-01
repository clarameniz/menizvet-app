# SPEC-MED-004 — Amend Finalized Clinical Record Entry

**Status:** APPROVED  
**Requirements:** REQ-MED-004, REQ-MED-005, REQ-MED-008, REQ-MED-009, REQ-AUD-001, REQ-AUD-002, REQ-AUD-003
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the Amendment model is unchanged and applies to every recorded Entry; the §15 access basis (BR-41, BR-40 step 2) is replaced by Appointment documentation access (SPEC-MED-010 BR-11, BR-18), which no longer depends on the Encounter or the Care Authorization. In addition, a client Amendment may be created only by the Entry's own author while that User holds a current Veterinarian context with `CLINICAL_DOCUMENTATION` at the Clinic (SPEC-MED-010 BR-18), superseding BR-6–BR-8 and the §15 BR-40 rule that any current Veterinarian may amend; the current Appointment assignee gains no authority over another Veterinarian's Entries. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

The Phase 1 Appointment-keyed client contract is §15 (**Clinical Amendments —
Phase 1**).

> **Superseded in part — Punto 8, stage M5.** [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) BR-18 and BR-23b replace the client form of §15: the Entry's author edits its category, content, and `OTHER` context without a reason, and each edit is persisted as an immutable Clinical Amendment of kind `EDIT` carrying the complete new version. Amendments remain append-only and attributed. Amendments created before M5 are kind `ADDENDUM` and stay readable; no new one can be created.

## 1. Intent

Allow an authorized veterinary professional to correct, clarify, or supplement
a Finalized Clinical Record Entry without destructively rewriting the original
clinical history.

A Clinical Amendment creates a traceable additional clinical record associated
with the original Finalized Clinical Record Entry.

The original finalized information must remain historically identifiable.

An Amendment must preserve:

- what was originally finalized;
- what was later corrected, clarified, or added;
- who performed the Amendment;
- when the Amendment occurred;
- why the Amendment was required.

---

## 2. Preconditions

- The original Clinical Record Entry exists.
- The original Clinical Record Entry is `FINALIZED`.
- The original Clinical Encounter exists.
- The original Pet, Clinic, Veterinary Organization, and professional
  provenance remain identifiable.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a Veterinarian Professional Profile.
- The acting User has a current professional context authorized to amend
  clinical information originating from the applicable provider context.
- The Amendment contains clinically meaningful information.
- A meaningful Amendment reason is provided.
- The acting User is not attempting to use the Amendment workflow to silently
  transfer the original Entry to another Pet, Clinic, Organization, or
  Encounter.

---

## 3. Business Rules

### BR-1 — Finalized clinical information must not be destructively rewritten

A Finalized Clinical Record Entry must not be changed through ordinary editing
when doing so would alter its historical clinical meaning.

Corrections, clarifications, and clinically meaningful additions must be
represented through a traceable Clinical Amendment.

---

### BR-2 — Amendment preserves the original Finalized Entry

Creating an Amendment must not:

- delete the original Clinical Record Entry;
- replace its original finalized content;
- overwrite its original finalization time;
- overwrite its original authorship;
- make the original historical statement appear never to have existed.

The original Entry remains historically identifiable.

---

### BR-3 — Amendment is a distinct domain entity

A Clinical Amendment must have its own identity.

It must reference the Finalized Clinical Record Entry being amended.

Conceptually:

    Clinical Record Entry A
    FINALIZED
          │
          └── Amendment #1

The Amendment does not become a replacement identity for Entry A.

---

### BR-4 — Amendment requires an explicit reason

Every Clinical Amendment must include a meaningful reason explaining why the
finalized information requires correction, clarification, or supplementation.

A clinically meaningful finalized record must not be altered through an
unexplained Amendment.

---

### BR-5 — Amendment reason is distinct from amended clinical content

The system must preserve both:

- why the Amendment was made;
- the clinical information introduced by the Amendment.

For example:

    Amendment reason:
    Incorrect dosage documented

    Amended clinical information:
    Correct dosage is 5 mg rather than 50 mg

The reason and clinical correction must not be collapsed into one ambiguous
field.

---

### BR-6 — Amendment must preserve who performed it

The system must preserve the veterinary professional who created the
Amendment.

The amending professional may differ from:

- the original creator;
- previous contributors;
- the original finalizing professional;
- the responsible Veterinarian of the Clinical Encounter.

Those professional roles must remain distinguishable.

---

### BR-7 — Original authorship remains unchanged

An Amendment created by another professional must not make that professional
appear to have authored the original finalized information.

For example:

    Original Entry
    Created by: Dr. Garcia
    Finalized by: Dr. Garcia

    Amendment
    Created by: Dr. Lopez

Both professional contributions remain historically distinguishable.

---

### BR-8 — Authorized professional other than original author may amend

The original author does not need to remain available in order for clinically
necessary corrections to be made.

Another veterinary professional may create an Amendment when their current
professional context authorizes them to amend clinical information originating
from that provider context.

Clinical continuity must not depend permanently on the original author.

---

### BR-9 — Historical authorship alone does not grant current amendment authority

A professional who originally created or finalized the Entry must not retain
permanent amendment authority solely because of that historical involvement.

Current professional authorization must be evaluated when the Amendment is
created.

---

### BR-10 — Cross-clinic read access does not grant amendment authority

A Clinic that is authorized to read another provider's finalized clinical
information must not gain authority to amend that provider's historical
records solely because it can access them.

For example:

    Animalia Madrid Centro
    authored Entry A

    VetCare Toledo
    later reads Entry A

VetCare Toledo must not amend Entry A through ordinary cross-clinic access.

---

### BR-11 — New provider may create new clinical information instead

If a veterinary professional at another Clinic disagrees with, updates, or
supersedes an earlier provider's clinical interpretation, they may create new
clinical information in their own authorized Clinical Encounter.

They must not rewrite the previous provider's finalized contribution.

This preserves the longitudinal sequence of clinical understanding.

---

### BR-12 — Amendment remains associated with the same Pet

An Amendment must concern the same Pet as the original Finalized Clinical
Record Entry.

The Amendment workflow must not move finalized clinical information to another
Pet.

Incorrect-Pet historical correction requires a dedicated high-risk workflow.

---

### BR-13 — Amendment preserves original Encounter provenance

An Amendment must retain a reference to the Clinical Record Entry and original
Clinical Encounter to which it applies.

It must not rewrite the original Encounter's:

- Pet;
- Clinic;
- Veterinary Organization;
- responsible Veterinarian;
- occurrence context.

---

### BR-14 — Amendment has its own professional provenance

Although an Amendment references the original provider context, the Amendment
must also preserve the professional context in which the correction was made.

The system must therefore be capable of distinguishing:

    Original clinical context

from:

    Amendment context

where relevant.

---

### BR-15 — Provider provenance must not be transferred

An Amendment must not make another Clinic or Veterinary Organization appear to
have authored the original clinical information.

Likewise, the original provider must not automatically become the author of
new amendment content created by another authorized professional.

---

### BR-16 — Amendment becomes part of longitudinal medical history

A valid Clinical Amendment becomes part of the Pet's finalized longitudinal
medical history.

Authorized viewers must be able to understand that the original Entry was
later amended.

---

### BR-17 — Amendment must not hide that a correction occurred

The normal presentation of clinically relevant amended information must not
make it appear that only the corrected version ever existed.

The history must preserve that:

- an original statement existed;
- a later Amendment changed or clarified its interpretation.

The exact user-interface presentation is outside this Specification.

---

### BR-18 — Current interpretation may incorporate Amendments

The system may provide a clinically useful current interpretation of a record
after one or more Amendments.

However, any derived current representation must remain traceable back to:

- the original Finalized Clinical Record Entry;
- the applicable Amendments.

A convenient current view must not destroy historical truth.

---

### BR-19 — Amendments are append-only clinical history

A Clinical Amendment adds historical clinical information.

It must not destructively modify previous finalized history.

Conceptually:

    Original Entry
          ↓
    Amendment #1
          ↓
    Amendment #2

not:

    Original Entry
          ↓
    overwritten repeatedly

---

### BR-20 — Amendment may itself require later Amendment

Clinical understanding may continue to evolve.

If a finalized Amendment later requires correction, another traceable
Amendment may be created.

An existing finalized Amendment must not be silently rewritten.

---

### BR-21 — Amendment chain must remain reconstructable

When several Amendments exist, the system must preserve enough information to
reconstruct their chronological and logical relationship.

For example:

    Entry A
    Finalized: 2026-09-10

    Amendment #1
    2026-09-11

    Amendment #2
    2026-09-13

The system must not collapse the sequence into an unattributed final value.

---

### BR-22 — Amendment time is distinct from clinical event time

The system must preserve when the Amendment was created.

Where the Amendment refers to an earlier clinical occurrence, that occurrence
time must remain distinguishable from the Amendment creation time.

---

### BR-23 — Amendment does not rewrite original timestamps

Creating an Amendment must not change:

- original clinical event time;
- original Draft creation time;
- original finalization time.

The Amendment has its own temporal information.

---

### BR-24 — Amendment is finalized clinical information

A successfully created Clinical Amendment is part of finalized medical
history.

It must not remain ambiguously editable under ordinary Draft semantics.

If a future workflow requires Draft Amendments before commitment, that behavior
must be specified separately.

---

### BR-25 — Amendment requires clinically meaningful content

An empty Amendment must not be created.

The Amendment must contain enough information to understand the correction,
clarification, or supplementation being made.

---

### BR-26 — Amendment does not require changing the original clinical event category

The original Clinical Record Entry retains its original clinical event
category.

An Amendment may clarify or correct information associated with that Entry
without silently reclassifying the historical Entry.

If reclassification itself is clinically significant, it must remain
traceable through the Amendment.

---

### BR-27 — Amendment does not create another Clinical Encounter automatically

Creating a Clinical Amendment must not automatically create:

- a new Clinical Encounter;
- an Appointment;
- a new Pet;
- a new original Clinical Record Entry.

The Amendment relates to existing finalized clinical history.

---

### BR-28 — Amendment does not complete or reopen the original Encounter

The lifecycle of the historical Clinical Encounter must not be silently changed
merely because a Clinical Amendment is created.

Retrospective documentation and Encounter lifecycle are separate concepts.

---

### BR-29 — Amendment access remains protected

A Clinical Amendment contains protected medical information.

Access to Amendments must follow the same applicable Guardian and professional
medical-access controls as finalized clinical history.

---

### BR-30 — Cross-clinic authorized history includes applicable Amendments

When another Clinic is authorized to access a finalized Clinical Record Entry,
applicable Amendments to that Entry must also be available where necessary to
avoid presenting clinically misleading outdated information.

The viewer must be able to distinguish the original provider history and later
Amendment information.

---

### BR-31 — Guardian history includes applicable Amendments

An authorized Guardian viewing finalized longitudinal medical history must be
able to receive applicable Clinical Amendments together with the related
clinical history.

The system must not knowingly present an amended historical statement as
current while concealing the clinically relevant Amendment.

---

### BR-32 — Employment changes do not rewrite Amendment provenance

If the amending professional later leaves the Clinic or Veterinary
Organization, the Amendment remains attributed to the professional and provider
context in which it was created.

---

### BR-33 — Subscription termination does not erase Amendments

Loss or termination of an Organization subscription must not:

- delete Clinical Amendments;
- detach them from the original Entry;
- erase amendment authorship;
- rewrite historical provenance.

Medical-history integrity survives commercial state changes.

Creating an Amendment does not require current commercial Entitlement
(`SPEC-SUB-004` BR-20, `SPEC-SUB-003` §4 `CLINICAL_DOCUMENTATION`): a necessary
correction stays possible after Entitlement loss. Every other rule of this
Specification, including the current professional authority of BR-9 and
BR-35, still applies.

---

### BR-34 — Amendment does not create arbitrary new medical access

Creating an Amendment must not expand the amending professional's access to
other unrelated Pet medical information.

The operation remains constrained by its authorized retrospective clinical
context.

---

### BR-35 — Amendment requires auditable professional context

The system must preserve enough information to establish:

- the original Clinical Record Entry;
- the Pet;
- the Amendment content;
- the Amendment reason;
- the amending professional;
- the Amendment time;
- the relevant professional provider context.

---

### BR-36 — Amendment creation is atomic

A successful Clinical Amendment must be established together with all required
clinical and provenance information.

The system must not expose a clinically effective Amendment without its
required:

- target Entry;
- reason;
- content;
- author;
- timestamp.

---

### BR-37 — Failed Amendment leaves finalized history unchanged

If an Amendment cannot be validly created, the original Finalized Clinical
Record Entry and any existing Amendments must remain unchanged.

No partial clinical correction must be exposed.

---

### BR-38 — Repeated submission must not create accidental duplicate Amendments

Retrying the same Amendment operation must not create multiple clinically
identical Amendments solely because of technical retry behavior.

The exact idempotency mechanism is architectural.

---

## 4. Clinical Amendment Information

A Clinical Amendment must preserve enough information to understand both the
historical correction and its professional provenance.

### Required

- Amendment identity;
- original Finalized Clinical Record Entry;
- Pet;
- Amendment reason;
- clinically meaningful amendment content;
- amending professional;
- Amendment creation time;
- applicable professional provider context.

### Inherited historical context

The original Finalized Clinical Record Entry continues to preserve:

- original Clinical Encounter;
- original Clinic;
- original Veterinary Organization;
- original responsible Veterinarian;
- original creator and contributors;
- original finalizer;
- original clinical event time;
- original finalization time.

The Amendment must not overwrite these values.

---

## 5. Scenarios

### Scenario: Original Veterinarian corrects finalized information

Given Dr. Garcia previously finalized a Clinical Record Entry for Luna
And Dr. Garcia is currently authorized to amend that provider's clinical
information
And Dr. Garcia discovers that the finalized Entry contains an error

When Dr. Garcia creates a valid Clinical Amendment with a meaningful reason

Then the original Finalized Clinical Record Entry remains unchanged
And a Clinical Amendment is created
And Dr. Garcia is identified as the amending professional
And the Amendment becomes part of Luna's longitudinal medical history

---

### Scenario: Another authorized colleague amends the Entry

Given Dr. Garcia originally created and finalized a Clinical Record Entry for
Luna at Animalia Madrid Centro
And Dr. Lopez is currently authorized to amend Animalia Madrid Centro clinical
information
And the Entry requires a clinically valid correction

When Dr. Lopez creates the Amendment

Then the Amendment may be created
And Dr. Garcia remains identifiable in the original Entry
And Dr. Lopez is identifiable as the amending professional
And the system does not rewrite Dr. Lopez as the original author

---

### Scenario: Former Veterinarian cannot amend solely because they authored the Entry

Given Dr. Garcia originally authored a Finalized Clinical Record Entry
And Dr. Garcia no longer has current professional authorization to amend
clinical information for that provider context

When Dr. Garcia attempts to create an Amendment solely because she originally
authored the Entry

Then the operation is denied
And historical authorship alone is insufficient

---

### Scenario: Another Clinic cannot amend cross-clinic history

Given Animalia Madrid Centro created a Finalized Clinical Record Entry for Luna
And VetCare Toledo has valid cross-clinic read access to that Entry

When a VetCare professional attempts to amend Animalia's historical Entry
solely through that cross-clinic access

Then the operation is denied
And cross-clinic read access does not grant amendment authority

---

### Scenario: Another Clinic records a different clinical interpretation

Given Animalia Madrid Centro previously finalized a diagnosis-related Entry
for Luna
And Luna later receives authorized care at VetCare Toledo
And Dr. Lopez reaches a different clinical interpretation

When Dr. Lopez documents the new interpretation

Then VetCare may create new clinical information in its own Clinical Encounter
And Animalia's original Finalized Entry remains unchanged
And both contributions may coexist in Luna's longitudinal medical history

---

### Scenario: Amendment requires a reason

Given Luna has a Finalized Clinical Record Entry
And Dr. Garcia is authorized to amend it

When Dr. Garcia attempts to create an Amendment without a meaningful reason

Then the operation is rejected
And no Clinical Amendment is created
And the original Entry remains unchanged

---

### Scenario: Amendment corrects a documented dosage

Given a Finalized Clinical Record Entry states a dosage of 50 mg
And the correct documented dosage should have been 5 mg
And Dr. Garcia is authorized to amend the Entry

When Dr. Garcia creates an Amendment explaining the documentation error and
recording 5 mg as the correction

Then the original 50 mg statement remains historically identifiable
And the Amendment records the corrected 5 mg information
And the reason for the correction remains traceable

---

### Scenario: Guardian sees clinically relevant Amendment

Given Maria is an authorized Guardian of Luna
And Luna has a Finalized Clinical Record Entry
And that Entry has a clinically relevant Amendment

When Maria views Luna's finalized longitudinal medical history

Then the applicable Amendment may be presented with the related Entry
And the history must not misleadingly present the superseded information as
the only current interpretation

---

### Scenario: Other Clinic sees applicable Amendment

Given Animalia Madrid Centro finalized a Clinical Record Entry for Luna
And Animalia later validly amended that Entry
And VetCare Toledo has current authorized cross-clinic access to Luna's relevant
history

When VetCare views the relevant clinical history

Then the applicable Amendment may be made available
And the original Entry remains attributed to Animalia Madrid Centro
And the Amendment's own professional provenance remains traceable

---

### Scenario: Amendment cannot move Entry to another Pet

Given a Finalized Clinical Record Entry belongs to Luna

When an authorized professional attempts to use an Amendment to make the Entry
belong to Toby

Then the operation is rejected
And the original Pet identity remains unchanged
And incorrect-Pet correction requires a dedicated safe workflow

---

### Scenario: Amendment does not replace original timestamps

Given Luna's original clinical event occurred on 2026-09-10
And the Entry was finalized on 2026-09-10
And an Amendment is created on 2026-09-12

When the medical history is evaluated

Then the original clinical event date remains 2026-09-10
And the original finalization date remains 2026-09-10
And the Amendment date remains 2026-09-12

---

### Scenario: Amendment may itself later require correction

Given Clinical Amendment #1 exists for Luna's Finalized Clinical Record Entry
And Amendment #1 later requires a clinically meaningful correction

When an authorized professional creates Amendment #2

Then Amendment #1 remains historically identifiable
And Amendment #2 is added to the Amendment history
And the earlier history is not destructively rewritten

---

### Scenario: Amendment does not reopen original Clinical Encounter

Given Luna's Clinical Encounter has already concluded
And a valid retrospective Clinical Amendment is required

When the Amendment is created

Then the historical Clinical Encounter is not silently reopened
And the Amendment remains linked to the relevant finalized clinical history

---

### Scenario: Failed Amendment preserves existing history

Given Luna has a Finalized Clinical Record Entry
And a professional attempts to create an Amendment
And the Amendment operation fails

When the failure occurs

Then the original Entry remains unchanged
And existing Amendments remain unchanged
And no partial correction appears in longitudinal history

---

### Scenario: Organization subscription ends after Amendment

Given Animalia Madrid Centro created a Finalized Clinical Record Entry for Luna
And later created a valid Clinical Amendment

When Animalia Veterinary Group's subscription later ends

Then the original Entry remains part of Luna's medical history
And the Clinical Amendment remains part of Luna's medical history
And both retain their historical provenance

---

## 6. Amendment Model

The medical history should be understood as append-only with respect to
clinically meaningful finalized information.

For example:

    Entry A
    "Dose: 50 mg"
    Finalized: 2026-09-10

        ↓

    Amendment #1
    Reason:
    Documentation error

    Correction:
    "Dose: 5 mg"

    Created: 2026-09-11

The system may present 5 mg as the current corrected interpretation.

However, it must remain possible to establish that the original finalized
record stated 50 mg and was later corrected.

---

## 7. Amendment Provenance

Clinical Amendment provenance is distinct from original clinical provenance.

For example:

    Original Entry

    Pet:
    Luna

    Clinic:
    Animalia Madrid Centro

    Original author:
    Dr. Garcia

    Finalized by:
    Dr. Garcia

    Finalized:
    2026-09-10


    Amendment

    Amending professional:
    Dr. Lopez

    Reason:
    Incorrect dosage documented

    Created:
    2026-09-11

Both histories remain meaningful.

---

## 8. Current Interpretation vs Historical Truth

The system may need to answer two different questions.

Current clinical interpretation:

    What information should an authorized professional rely on now?

Historical truth:

    What was originally documented, and what changes occurred later?

A useful current clinical view must not destroy the second answer.

Amendments provide the mechanism for supporting both.

---

## 9. Cross-Clinic Integrity

Cross-clinic medical history must preserve provider boundaries.

An authorized Clinic may:

- read relevant finalized history;
- read applicable Amendments;
- create new clinical information in its own authorized care context.

It must not:

- rewrite another Clinic's finalized Entry;
- create an Amendment pretending to originate from another provider;
- transfer original authorship to itself.

This distinction is fundamental to clinical provenance.

---

## 10. Edge Cases

### Original Clinic no longer has the original Veterinarian

The departure of the original author must not permanently prevent clinically
necessary correction.

Another appropriately authorized veterinary professional within the applicable
provider context may create the Amendment.

---

### Original Clinic closes

A finalized historical Entry may require correction after the originating
Clinic has permanently closed.

The normal Phase 1 provider Amendment workflow may no longer be sufficient.

A future controlled platform-level historical correction workflow may be
required.

The historical record must not be silently reassigned to another Clinic merely
because the original provider no longer operates.

---

### Incorrect Pet association

Moving finalized clinical information between Pets is higher risk than ordinary
clinical clarification.

The standard Amendment workflow must not silently transfer the record.

A dedicated auditable correction Specification is required if Phase 1 needs to
support this case.

---

### Duplicate Amendment submission

Network retry or repeated submission must not create duplicate clinically
identical Amendments accidentally.

Idempotency implementation is architectural.

---

### Clinical understanding changes rather than original record being wrong

A later clinical opinion does not necessarily mean an earlier record contained
a documentation error.

Where new evidence changes the medical interpretation, a new Clinical Record
Entry may be more appropriate than an Amendment.

Amendment should be used to correct or clarify the historical record, not to
erase legitimate evolution in medical understanding.

---

### Legal retention requirements

The exact retention duration and legal obligations applicable to veterinary
medical history depend on jurisdiction and policy.

This Specification requires preservation of historical meaning but does not
define legal retention periods.

---

## 11. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**

---

## 12. Dependencies

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization
- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-ID-003 — Authenticate User

---

## 13. Out of Scope

This Specification does not define:

- Draft Clinical Amendments;
- incorrect-Pet finalized-record transfer;
- platform-level correction after provider closure;
- deletion of finalized clinical history;
- legal retention periods;
- clinical event taxonomy;
- dedicated Treatment models;
- Vaccination models;
- Prescription models;
- Laboratory Result models;
- Imaging models;
- clinical attachments;
- amendment notification behavior;
- co-signature requirements;
- professional supervision;
- Clinical Encounter reopening.

---

## 14. Verification Notes

Verification must demonstrate that:

1. finalized clinical content is not destructively rewritten;
2. correction or clarification creates a distinct Clinical Amendment;
3. the original Finalized Clinical Record Entry remains historically
   identifiable;
4. every Amendment requires a meaningful reason and clinically meaningful
   content;
5. original authorship remains unchanged;
6. the amending professional remains independently traceable;
7. another currently authorized professional may amend without becoming the
   original author;
8. historical authorship alone does not grant permanent amendment authority;
9. cross-clinic read access does not grant amendment authority;
10. another provider may create new clinical information without rewriting the
    previous provider's history;
11. an Amendment cannot move finalized history to another Pet;
12. original Encounter and provider provenance remain unchanged;
13. Amendment provenance remains independently traceable;
14. Amendments become part of finalized longitudinal medical history;
15. clinically relevant Amendments may be visible to authorized Guardians and
    authorized cross-clinic viewers;
16. Amendments may themselves be followed by later Amendments without
    destructive rewriting;
17. original clinical-event and finalization timestamps remain unchanged;
18. Amendment creation does not reopen or replace the original Clinical
    Encounter;
19. subscription or employment changes do not erase Amendment history;
20. failed Amendment creation leaves existing history unchanged;
21. Amendment creation behaves atomically.

---

## 15. Phase 1 Appointment-keyed Amendment contract

Defined by **Clinical Amendments — Phase 1**. It narrows BR-1–BR-38 for the
mobile client; it does not change them. The Amendment model is the existing
one (§4, §6): an additive, immutable record with its own identity, a reason,
clinically meaningful amendment content, the amending User and Clinic
Assignment, and its creation time, referencing the original Finalized Entry.
It is not a replacement representation of the Entry, carries no category,
clinical event time, or structured content of its own, and never changes the
Entry. Several Amendments may exist for one Entry, ordered by creation time,
then identity (BR-19–BR-21).

### BR-39 — Canonical Amendment operation

    create_appointment_clinical_amendment(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_entry_id uuid,
        p_idempotency_key uuid,
        p_reason text,
        p_amendment_content text
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It takes no Care Authorization, User, Clinic Assignment,
Membership, original-author, or Organization identifier: the Organization,
Encounter, and amending professional context are derived.

The result is `{"outcome": "CREATED" | "ALREADY_CREATED", "amendment_id":
<uuid>}`; never clinical content, never the key.

The pre-existing `create_clinical_amendment(uuid, text, text, uuid)` is not a
client path. Client `EXECUTE` is withdrawn; it remains the trusted writer for
`service_role`.

### BR-40 — Authority before existence

Amendment authority is the acting User's current exact-Clinic Veterinarian
context at the named Clinic holding `CLINICAL_DOCUMENTATION` (`SPEC-MED-001`
BR-37: current Membership, current Organization-scoped `VETERINARIAN` Grant,
own Veterinarian Professional Profile, current Clinic Assignment at that
Clinic). It is decided first, under the existing clinical lock order.

Then, in order:

1. the Appointment of that Clinic, its Clinical Encounter, and the Entry of
   that Encounter are resolved together;
2. the clinical-record access basis of `SPEC-MED-009` BR-4 (BR-41), decided
   with the Care Authorization and Encounter locked;
3. an Entry that is not `FINALIZED` — `23514`, hint `ENTRY_NOT_FINALIZED`;
4. a missing key — `22023`, hint `KEY_REQUIRED`;
5. a reason blank after trimming — `22023`, hint `REASON_REQUIRED` (BR-4);
6. amendment content blank after trimming — `22023`, hint `CONTENT_REQUIRED`
   (BR-25);
7. reconciliation with the caller's key (BR-42), then creation.

Missing or ended authority, an unknown or foreign Clinic, an Appointment of
another Clinic or Organization, an Appointment without an Encounter, an
unknown Entry or an Entry of another Encounter, and an Encounter whose
clinical record is no longer accessible (BR-41) are one uniform `42501`
`Clinical record unavailable` with no hint: existence is never revealed before
authority and access, and an Entry identifier kept from an earlier read grants
nothing.

Amendment authority does **not** require: being the original creator or
finalizer (BR-6–BR-8); the original author's current Membership,
`VETERINARIAN` Grant, or Clinic Assignment (§10); being the Encounter's
responsible Veterinarian; an Appointment Veterinarian Assignment; Appointment
Availability; or a current Entitlement (BR-33, `SPEC-SUB-004` BR-20).
Historical authorship alone never grants it (BR-9). An Administrator,
Receptionist, or Owner without that Veterinarian context is refused with the
same `42501`.

### BR-41 — Same access basis as the Appointment clinical record

A client Amendment may be created only while the target Entry is currently
reachable through the Appointment clinical record: the Encounter is `ACTIVE`
(including revocation-safe active-care continuity, `SPEC-ACC-002` BR-19,
BR-20), or its Care Authorization is `ACTIVE` (post-care documentation,
`SPEC-ACC-002` BR-35, BR-36) — exactly `SPEC-MED-009` BR-4, evaluated by the
same server-side predicate. A `CONCLUDED` Encounter whose Care Authorization is
`REVOKED` or `ENDED` cannot be amended through the client: Guardian revocation
is not bypassed, and no Amendment-specific read exposes the Entry again.

Within that basis, the target must be `FINALIZED`; the Encounter may be
`ACTIVE` or `CONCLUDED` and the Appointment `CONFIRMED` or `COMPLETED`.
Subscription Entitlement loss is not an access-basis change (BR-33). Creating
an Amendment changes no Appointment, Care Authorization, Encounter, or Entry,
reopens nothing, and creates no Draft (BR-27, BR-28). Revocation or ending of
the Care Authorization never changes or removes the original Entry, existing
Amendments, or their provenance.

The trusted `create_clinical_amendment` keeps its existing semantics for
trusted internal use only; it is not a client path.

### BR-42 — Idempotent creation

The key is the existing Amendment key, unique per amending User. Its semantic
identity is exactly the existing one: the original Entry, the trimmed reason,
the trimmed amendment content, and the amending Clinic Assignment.

- the first request — `CREATED`;
- a repeat of the same key with the same identity, including after a lost
  response — `ALREADY_CREATED` with the same `amendment_id`, nothing written;
- the same key with any different identity — `23505`, hint `KEY_CONFLICT`,
  nothing written; the key is never echoed.

Each distinct Amendment intent uses its own key; there is no limit on the
number of Amendments of an Entry.

### BR-43 — Immutability

An Amendment cannot be updated or deleted, and creating one never modifies
the original Entry or an earlier Amendment. Both are structural (the existing
Amendment and Entry integrity triggers), not only conventional.

### BR-44 — Provenance and visibility

The Amendment records the amending User, the amending Clinic Assignment, and
its own creation time; the original Entry keeps its creator, finalizer,
event time, and finalization time (BR-7, BR-23). Amendments become visible in
the Guardian medical history (BR-31, `SPEC-MED-005`) and in the Appointment
clinical record (`SPEC-MED-009` BR-4) immediately. Creating an Amendment needs
no Medical Access Audit Event (`SPEC-ACC-003` BR-57): its own record preserves
actor, time, and context.

The client reaches a `FINALIZED` Entry only through `SPEC-MED-009`, and the
write applies the same basis (BR-41); this contract adds no read basis and no
longitudinal-history access (BR-34, `SPEC-MED-005` BR-18). The professional
longitudinal history (`SPEC-MED-005` §15) shows Amendments read-only and offers
no Amendment action (`SPEC-MED-005` BR-47).

### Mobile presentation

- A `FINALIZED` Entry offers **Añadir corrección / Add amendment**. A Draft
  never does. The action is never called Edit, Modify, or Reopen.
- The form shows the original Entry, unchanged, and asks only for the reason
  and the amendment content, stating that the original will remain unchanged
  and the amendment will be added after it.
- A review before submission states that the amendment will be recorded
  permanently, the original stays preserved, and the amendment becomes part of
  the pet's clinical history, visible to its guardians. It never says the
  original is overwritten, the Appointment reopened, or care resumed.
- One key per form session; after any outcome, or an uncertain response, the
  client re-reads. A lost response is retried only with the same key.
- When the re-read is `DENIED` (or a write returns the uniform `42501`), the
  form and every clinical content are dropped for the existing calm
  unavailable state; nothing says whether the Entry or an Amendment exists.
- Amendments are shown beneath their Entry, oldest first, each with its
  reason, content, creation time, and authorship only as **You / Tú** or
  **Another veterinarian / Otro veterinario**. The original stays visible.

## 16. Phase 1 Appointment-keyed Amendment Verification Notes

In addition to §14, verification must demonstrate that:

22. a current Veterinarian of the Clinic amends a `FINALIZED` Entry, whether
    original author or not, and the original Entry is unchanged;
23. the Guardian history and the Appointment clinical record show the original
    and the Amendment;
24. an Administrator, Receptionist, Owner without Veterinarian context,
    another Clinic, another Organization, an unknown Appointment, and an unknown
    or foreign Entry all receive the same `42501`;
25. the original author's ended Membership, `VETERINARIAN` Grant, or Clinic
    Assignment does not prevent another current Veterinarian from amending, and
    the original authorship is unchanged;
26. a Draft cannot be amended; a `CONCLUDED` Encounter and a `COMPLETED`
    Appointment can while the Care Authorization is `ACTIVE`, and nothing is
    reopened;
27. an Entitlement lapse does not block an Amendment;
28. an exact repeat returns `ALREADY_CREATED` with the same Amendment, a
    changed request with the same key is `KEY_CONFLICT`, and distinct keys
    create distinct Amendments;
29. Amendments cannot be updated or deleted;
30. no client role executes the generic Amendment operation;
31. concurrent requests produce no duplicate, a deterministic conflict, and a
    coherent authority boundary;
32. an `ACTIVE` Encounter under a `REVOKED` Care Authorization stays amendable,
    while a `CONCLUDED` Encounter under a `REVOKED` or `ENDED` one is refused
    with the uniform `42501` — also for an Entry identifier kept from before the
    revocation and for an exact replay — nothing is inserted, no clinical
    content is returned, and the original Entry, existing Amendments, and
    provenance are unchanged; a revocation racing an Amendment is serialized.
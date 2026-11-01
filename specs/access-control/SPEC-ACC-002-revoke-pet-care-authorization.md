# SPEC-ACC-002 — Revoke or End Pet Care Authorization

**Status:** APPROVED  
**Requirements:** REQ-ACC-002, REQ-ACC-004, REQ-ACC-005, REQ-ACC-006  
**Domain:** Medical Access Control  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): revocation and normal ending end prior-history access only and never affect the Appointment's own records (SPEC-MED-010 BR-11, BR-12). Active-care continuity (BR-19–BR-21), Encounter-based ending conditions (BR-34–BR-37), BR-38 and BR-47 (completion now ends the authorization, SPEC-MED-010 BR-16), BR-48, BR-55, BR-61, §6, §9, §10, the related scenarios and Verification Notes, and the §16 Guardian copy are replaced. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Define how an active Pet Care Authorization stops providing current medical
access through either:

- explicit Guardian revocation; or
- normal completion of the authorized care context.

These termination paths represent different historical facts.

Conceptually:

    ACTIVE
      ├── Guardian withdraws authorization ──→ REVOKED
      │
      └── authorized care context completes ─→ ENDED

`REVOKED` means that authorization was explicitly withdrawn before its normal
completion.

`ENDED` means that the authorization completed its intended care purpose
without being revoked.

Both terminal outcomes remove the Care Authorization as a normal current
medical-access basis.

Termination must not:

- delete the Pet;
- delete medical history;
- rewrite historical clinical provenance;
- erase historical evidence that the authorization existed;
- retroactively invalidate access that was valid while the authorization
  applied.

Where veterinary care has already begun, revocation must not require unsafe
abandonment of an active care episode.

Where active care has concluded but legitimate documentation belonging to that
care episode remains unfinished, normal authorization ending must not
prematurely make that documentation impossible.

---

## 2. Preconditions

- The Pet exists.
- The Pet Care Authorization exists.
- The Care Authorization is currently active and revocable.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a current active Guardianship relationship with the Pet.
- The acting User is authorized to manage Care Authorization for the Pet.
- The Care Authorization identifies the Clinic and care context to which it
  applies.

---

## 3. Business Rules

### BR-1 — Active Care Authorization may be revoked

An active Pet Care Authorization granted through a revocable care context may
be explicitly revoked by an authorized current Guardian.

Revocation must establish that the authorization no longer provides normal
current medical-access authority.

---

### BR-2 — Revocation requires current Guardianship

A User may revoke a Pet Care Authorization only when they currently have an
active Guardianship relationship with the Pet and the Phase 1 Guardianship
model permits them to manage Care Authorization.

Historical Guardianship alone is insufficient.

---

### BR-3 — Phase 1 current Guardians may revoke Care Authorization

Phase 1 does not define differentiated Guardian permission levels.

Therefore, any current active Guardian may revoke an active Care Authorization
for the Pet.

The revoking Guardian does not need to be the Guardian who originally granted
the authorization.

Future differentiated Guardian responsibilities may refine this behavior.

---

### BR-4 — Original grantor status does not provide permanent control

The Guardian who originally granted the Care Authorization remains
historically identifiable.

However, original grantor status alone does not provide permanent authority to
manage the authorization after that User no longer has an active Guardianship
relationship with the Pet.

---

### BR-5 — Revocation is Pet-specific

Revoking Care Authorization for one Pet must not affect authorization for
another Pet.

For example:

    Luna → Authorization A → revoked
    Toby → Authorization B → active

Authorization B remains unchanged.

---

### BR-6 — Revocation is care-context-specific

Revoking one Care Authorization must affect only the care context represented
by that authorization.

It must not automatically revoke unrelated authorizations involving:

- another Clinic;
- another care episode;
- another Veterinary Organization;
- another Pet.

---

### BR-7 — Revocation removes the authorization as a current access basis

Once revocation takes effect, professional actors must not continue using the
revoked Care Authorization as the normal basis for accessing protected medical
information.

Any subsequent access must be supported by another currently valid authorized
basis.

---

### BR-8 — Revocation applies to cross-clinic access

When the Care Authorization previously allowed access to relevant longitudinal
history created by other Clinics, revocation must remove that authorization as
a basis for continued cross-clinic access.

Previously accessed information must not thereby become re-authored, deleted,
or reassigned.

---

### BR-9 — Revocation does not retroactively invalidate prior authorized access

Access that occurred while the Care Authorization was valid must not be
retroactively treated as unauthorized solely because the authorization was
later revoked.

The system must preserve the distinction between:

- access that occurred while authorization was valid;
- access attempted after revocation.

---

### BR-10 — Revocation does not erase authorization history

The system must preserve enough information to establish that the Care
Authorization previously existed.

Historical authorization information must remain capable of identifying:

- the Pet;
- the Clinic;
- the Veterinary Organization context;
- the granting Guardian;
- the original care purpose;
- when authorization was granted;
- when it was revoked;
- who revoked it.

---

### BR-11 — Revocation reason is optional for Guardians

A Guardian may provide a reason when revoking Care Authorization.

A revocation reason is not required in Phase 1.

The absence of a reason must not prevent an otherwise valid Guardian
revocation.

A revocation reason must not be treated as clinical information.

---

### BR-12 — Revocation does not delete medical history

Revoking Care Authorization must not delete or modify:

- Clinical Encounters;
- Medical Record Entries;
- diagnoses;
- Treatments;
- Vaccinations;
- Procedures;
- prescriptions;
- clinical attachments;
- historical provenance.

Access lifecycle and medical-history lifecycle are separate concerns.

---

### BR-13 — Revocation does not rewrite clinical provenance

Clinical information previously created under a valid professional context
must remain attributed to its original:

- Pet;
- Veterinarian or author;
- Clinic;
- Veterinary Organization;
- clinical occurrence time;
- authorship context.

Revocation must not change who historically provided or documented care.

---

### BR-14 — Revocation does not remove the Clinic's own historical contribution

A Clinic must not lose the historical existence of clinical information it
validly created merely because a Guardian later revokes current Care
Authorization.

Whether and how the Clinic may later access retained historical information
that it originally created is governed by the applicable Medical Records,
retention, and access-control rules.

Revocation of cross-provider access must not be interpreted as deletion of the
Clinic's own historical clinical contribution.

---

### BR-15 — Revocation before care begins ends normal care access immediately

If Care Authorization is revoked before a Clinical Encounter has begun, the
authorization must cease granting current medical access for that intended
care episode when revocation takes effect.

The Clinic must not continue preparation, triage, or cross-clinic medical
access solely through the revoked authorization.

---

### BR-16 — Revocation before care does not silently cancel the Appointment

Revoking Appointment-derived Care Authorization must not automatically delete
or silently cancel the related Appointment.

The Appointment remains a separate domain entity.

However, Appointment operations that require a valid Care Authorization must
not proceed without another applicable authorized basis.

The Appointment must be resolved through the applicable Appointment workflow.

---

### BR-17 — Appointment confirmation must not bypass revoked authorization

If the applicable Appointment workflow requires current Care Authorization,
a Clinic must not confirm or otherwise progress the Appointment by relying on
a Care Authorization that has already been revoked.

Another valid medical-access basis must exist where the operation requires it.

---

### BR-18 — Veterinarian Assignment must not bypass revoked authorization

If medical context is required to triage or assign an appropriate
Veterinarian, actors performing that workflow must not continue accessing the
Pet's protected medical history through a revoked Care Authorization.

Professional Assignment must not create medical authorization by itself.

---

### BR-19 — Revocation during active care must not require unsafe abandonment

A Guardian may revoke a Care Authorization after a Clinical Encounter has
already begun.

Revocation must not be interpreted as requiring veterinary professionals to
unsafely abandon care that is already actively underway.

Where continued access is necessary to safely conclude and document the
already-started Encounter, only the minimum access required for that purpose
may continue.

This limited continuity must not become a general or indefinite medical-access
right.

---

### BR-20 — Active-care continuity is limited to the existing Encounter

Any limited access continuing after revocation for safety and care-completion
purposes must be scoped to the Clinical Encounter that was already underway.

It must not authorize:

- unrelated future care;
- a new Appointment;
- a new Clinical Encounter;
- unrelated historical browsing;
- unrestricted access after the active care context has concluded.

---

### BR-21 — Revocation during active care does not authorize expansion of access

After revocation, an existing care context must not use the prior
authorization to broaden access beyond what is necessary to safely conclude
and document care already underway.

Least privilege continues to apply.

---

### BR-22 — Revocation prevents reuse for future care episodes

A revoked Care Authorization must not be reused as an access basis for a later
care episode.

If the Pet later requires veterinary care, a new current valid authorization
basis must be established where required.

---

### BR-23 — Revocation does not terminate Guardianship

Revoking medical Care Authorization must not:

- remove the revoking Guardian;
- remove another Guardian;
- transfer Guardianship;
- otherwise change the Pet's Guardianship relationships.

---

### BR-24 — Revocation does not alter professional relationships

Revoking Care Authorization must not:

- end Organization Membership;
- end Clinic Assignment;
- remove a Veterinarian Professional Profile;
- modify professional verification;
- change Organization responsibilities.

Professional relationships remain independent from Pet-specific medical
authorization.

---

### BR-25 — Revocation does not create clinical information

The revocation operation must not itself create:

- a diagnosis;
- a Treatment;
- a Medical Record Entry;
- a clinical observation;
- another medical statement.

The revocation event is access-control information.

---

### BR-26 — Revoked authorization cannot be reactivated

A revoked Care Authorization represents a completed authorization period.

It must not later become active again by clearing or ignoring its revocation.

If authorization is granted again, a new Care Authorization must be
established.

This preserves distinct authorization periods.

---

### BR-27 — Reauthorization creates a new authorization period

If a Guardian later authorizes the same Clinic for another care episode, the
new authorization must remain distinguishable from the previously revoked
authorization.

For example:

    Authorization #1
    Granted: 2026-09-01
    Revoked: 2026-09-02

    Authorization #2
    Granted: 2027-01-15
    Active

The first authorization remains historical.

---

### BR-28 — Already ended authorization cannot be revoked as though active

A Care Authorization that has already ended because its care episode concluded
must not be rewritten as though it were later revoked while active.

The historical end condition must remain accurate.

---

### BR-29 — Already revoked authorization is not revoked again

Repeated revocation attempts must not:

- overwrite the original revocation time;
- replace the original revoking User;
- create duplicate revocation history;
- reactivate the authorization.

---

### BR-30 — Revocation must preserve actor and time

A successful revocation must preserve:

- the revoking User;
- the revocation time;
- the affected Care Authorization;
- the Pet;
- the Clinic context;
- the optional revocation reason where provided.

---

### BR-31 — Revocation and removal of current access are atomic

The system must not expose a final state in which:

- the Care Authorization is marked revoked while still granting normal current
  access; or
- normal current access has been removed while the authorization still appears
  active.

Revocation and removal of the authorization as a current access basis form one
logical domain operation.

---

### BR-32 — Revocation does not erase access audit information

Where medical-access auditing is supported, revocation must not erase records
of access that occurred while the authorization was active.

Historical access evidence and current authorization are separate concepts.

---

### BR-33 — Active Care Authorization may end normally

An active Care Authorization may end normally when the care context for which
it was granted has fulfilled its purpose.

Normal ending must be distinguishable from Guardian revocation.

---

### BR-34 — Normal end requires the active-care episode to be concluded

Where a Care Authorization supports an actual Clinical Encounter, the
authorization must not normally end while that Clinical Encounter remains
`ACTIVE`.

The applicable Clinical Encounter conclusion behavior is governed by
`SPEC-MED-008`.

---

### BR-35 — Clinical Encounter conclusion does not automatically end Care Authorization

A Clinical Encounter becoming `CONCLUDED` must not by itself immediately
terminate the Care Authorization.

Legitimate post-care activity belonging to the same care episode may still
require narrowly scoped medical access.

Examples may include:

- completing an existing Draft Clinical Record Entry;
- finalizing documentation of care already provided;
- completing Clinical Attachments;
- recording results arising from the concluded care episode;
- other supported documentation directly attributable to that care.

---

### BR-36 — Post-care access remains limited to the existing care context

After the associated Clinical Encounter is concluded, any continued access
through the Care Authorization must remain limited to operations genuinely
required to complete the already-established care episode.

It must not authorize:

- unrelated historical browsing;
- new veterinary care;
- another Clinical Encounter;
- another Pet;
- another Clinic care context;
- unrelated future Appointment activity.

Least privilege continues to apply.

---

### BR-37 — Concluded care must not create indefinite authorization

A Care Authorization must not remain a current medical-access basis
indefinitely merely because it was once associated with valid veterinary care.

Once:

- active veterinary care has concluded; and
- the supported post-care work requiring that authorization has been resolved;

the authorization must be eligible for normal ending.

---

### BR-38 — Normal end is an explicit trusted domain transition

A Care Authorization must not become `ENDED` merely because:

- time passes;
- the Appointment time passes;
- the Appointment becomes `COMPLETED`;
- the Clinical Encounter becomes `CONCLUDED`;
- a User signs out;
- a Subscription changes state.

Normal ending must result from a trusted domain operation after the applicable
end conditions have been validated.

The exact user-interface or automation mechanism is architectural.

---

### BR-39 — Normal ending does not require Guardian revocation

A Care Authorization may end normally without a Guardian explicitly revoking
permission.

Normal completion represents exhaustion of the authorized care purpose rather
than withdrawal of consent during that purpose.

---

### BR-40 — Normal ending must preserve the original grant

A normally ended authorization must preserve:

- Pet;
- Clinic;
- Veterinary Organization;
- granting Guardian;
- care purpose;
- grant time;
- applicable Appointment where present;
- applicable Clinical Encounter where present;
- normal end time.

The original authorization context must not be rewritten.

---

### BR-41 — Normal ending should preserve the ending context

The system must preserve sufficient information to establish when the
authorization ended normally and the trusted context responsible for that
transition.

The exact representation of the ending actor or system process is
architectural.

---

### BR-42 — ENDED authorization provides no normal current medical access

Once normal ending takes effect, the authorization must no longer provide
current medical-access authority.

Any later protected access requires another applicable authorized basis.

---

### BR-43 — ENDED authorization cannot be reactivated

A normally ended Care Authorization represents a completed authorization
period.

It must not return to `ACTIVE`.

If later care requires authorization, a new Care Authorization must be
established.

---

### BR-44 — Reauthorization after normal end creates a new period

Later authorization for another episode of care must create a new Care
Authorization even when:

- the Pet is the same;
- the Clinic is the same;
- the Guardian is the same;
- the general clinical purpose appears similar.

Historical authorization periods must remain distinguishable.

---

### BR-45 — Normal end must not be rewritten as revocation

A Care Authorization that reached `ENDED` must not later be rewritten as
`REVOKED`.

The historical fact remains:

    care authorization completed normally

rather than:

    Guardian withdrew authorization

---

### BR-46 — Revocation must not later be rewritten as normal end

A Care Authorization that reached `REVOKED` must remain historically revoked.

Later conclusion of an Encounter that was already underway must not change the
authorization's historical terminal reason to `ENDED`.

---

### BR-47 — Appointment completion and authorization ending remain separate

Appointment `COMPLETED` must not automatically establish that the Care
Authorization has ended.

Appointment operational completion and medical-access lifecycle represent
different domain facts.

---

### BR-48 — Encounter conclusion and authorization ending remain separate

Clinical Encounter `CONCLUDED` means active veterinary care has ended.

Care Authorization `ENDED` means the authorization is no longer required as a
current access basis for that care context.

The former may occur before the latter.

---

### BR-49 — Normal ending does not modify clinical documentation

Ending Care Authorization normally must not:

- finalize Draft Entries;
- modify Finalized Entries;
- create Amendments;
- remove Attachments;
- change clinical occurrence times;
- rewrite clinical authorship.

---

### BR-50 — Normal ending preserves medical history

A normally ended Care Authorization must not delete or alter medical history
created during its valid period.

---

### BR-51 — Concurrent normal end and revocation must produce one coherent terminal history

If valid revocation and normal-ending operations race against the same active
Care Authorization, the resulting authorization must have one coherent
terminal history.

It must not simultaneously appear as both normally ended and revoked.

The exact concurrency-control mechanism is architectural.

---

### BR-52 — Failed normal ending preserves previous authorization state

If normal ending cannot be committed coherently, the previous valid
authorization state must remain authoritative.

A partially ended Care Authorization must not be exposed.

---

### BR-53 — Repeated normal ending must not rewrite history

A repeated end attempt against an already normally ended Care Authorization
must not:

- replace the original end time;
- replace historical ending context;
- create another authorization period;
- reactivate the authorization.

---

### BR-54 — Authorization state must be evaluated at protected access time

Protected medical access must evaluate the current effective Care Authorization
state.

Stale client knowledge that an Authorization was previously `ACTIVE` must not
permit access after it has become `ENDED` or `REVOKED`.

---

### BR-55 — Completed Appointment without an Encounter keeps a narrow, revocable authorization

When an Appointment becomes `COMPLETED` (`SPEC-APT-009`), its
Appointment-derived Care Authorization remains `ACTIVE` (BR-38).

If no Clinical Encounter exists for that Appointment, the care episode may
still be documented later: the authorization may support establishment of at
most one Appointment-backed Clinical Encounter for care that started between
the Appointment's confirmation and its completion (`SPEC-MED-001` BR-34,
`SPEC-ACC-001` BR-42).

Until such an Encounter exists, the authorization provides no other medical
access through that Appointment. It must not be used for unrelated historical
browsing, a new care episode, another Pet, or another Clinic (BR-36).

A current Guardian may revoke it like any other `ACTIVE` authorization.
Revocation before an Encounter exists prevents any new Appointment-backed
Encounter for that Appointment; the Appointment itself remains `COMPLETED`.

If an Encounter is later established, the ordinary rules for active care,
conclusion, and post-care documentation of this Specification apply to it
unchanged.

This rule does not introduce a documentation time limit or a trusted normal
ending operation; both remain outside Phase 1 (§14).

---

## 4. Care Authorization Lifecycle

Phase 1 supports three conceptual Care Authorization states:

- `ACTIVE`
- `REVOKED`
- `ENDED`

Lifecycle:

    ACTIVE
      ├──────── explicit Guardian revocation ───────→ REVOKED
      │
      └──────── normal care-context completion ────→ ENDED

Both `REVOKED` and `ENDED` are terminal.

Neither state may return to `ACTIVE`.

Later authorization requires a new Care Authorization.

The states preserve different historical meaning:

    REVOKED
    → authorization was actively withdrawn

    ENDED
    → authorization completed its intended care purpose normally

The exact persistence representation does not require a specific status enum.

---

## 5. Scenarios

### Scenario: Current Guardian revokes active Care Authorization

Given Maria has an active Guardianship relationship with Luna
And Luna has an active Care Authorization for Animalia Madrid Centro
And no Clinical Encounter has begun

When Maria revokes the Care Authorization

Then the authorization no longer grants current medical access
And Maria is recorded as the revoking User
And the revocation time is preserved
And the authorization remains historically identifiable

---

### Scenario: Another current Guardian may revoke

Given Carlos originally granted a Care Authorization for Luna
And Maria also has an active Guardianship relationship with Luna
And the Care Authorization remains active

When Maria validly revokes the authorization

Then the authorization becomes revoked
And Carlos remains identifiable as the granting Guardian
And Maria is identifiable as the revoking Guardian
And the two historical roles remain distinct

---

### Scenario: Former Guardian cannot revoke

Given Carlos originally granted a Care Authorization for Luna
And Carlos no longer has an active Guardianship relationship with Luna
And Carlos has no other applicable authorization-management capability

When Carlos attempts to revoke the Care Authorization

Then the operation is denied solely through that historical Guardian context
And current Guardianship is required

---

### Scenario: Guardian may revoke without giving a reason

Given Maria is authorized to revoke Luna's active Care Authorization

When Maria revokes it without providing a reason

Then the revocation may succeed
And the absence of a reason does not prevent revocation

---

### Scenario: Revocation stops cross-clinic medical access

Given Luna has historical medical information from VetCare Toledo
And Animalia Madrid Centro currently has access through an active Care
Authorization
And no Clinical Encounter is underway

When the Care Authorization is revoked

Then Animalia Madrid Centro may no longer use that authorization as a basis
for continued access to VetCare's protected clinical history
And VetCare's historical information remains unchanged
And its original provenance remains intact

---

### Scenario: Revocation does not retroactively invalidate previous access

Given Animalia Madrid Centro validly accessed relevant Luna medical
information while the Care Authorization was active

When the Care Authorization is later revoked

Then the earlier access remains historically associated with the authorization
state that existed at the time
And revocation does not rewrite the prior authorized access as unauthorized

---

### Scenario: Revocation before care does not delete Appointment

Given Luna has a `REQUESTED` Appointment at Animalia Madrid Centro
And the Appointment has an active Care Authorization
And no Clinical Encounter has begun

When Maria revokes the Care Authorization

Then the Appointment continues to exist
And the Care Authorization no longer grants current medical access
And the Clinic must not continue operations requiring that authorization
without another valid basis
And Appointment resolution occurs through the applicable Appointment workflow

---

### Scenario: Revoked authorization cannot support Appointment triage

Given Luna has a requested Appointment
And its Appointment-derived Care Authorization has been revoked
And no other valid medical-access basis exists

When an actor attempts to access Luna's protected medical history for
Appointment triage using the revoked authorization

Then access is denied

---

### Scenario: Revoked authorization cannot support medical-context Veterinarian assignment

Given Luna has an Appointment
And the Care Authorization previously used for medical-context triage has been
revoked
And no other valid medical-access basis exists

When a Clinic actor attempts to inspect Luna's protected medical history in
order to assign a Veterinarian

Then the revoked authorization is insufficient
And Appointment or Clinic authority alone does not restore medical access

---

### Scenario: Guardian revokes while Clinical Encounter is active

Given Luna is currently receiving veterinary care at Animalia Madrid Centro
And a valid Clinical Encounter has already begun
And the care was established under an active Care Authorization

When Maria revokes the Care Authorization

Then the authorization must not provide unrestricted continuing access
And the Clinic must not use it for unrelated future access
And only the minimum access necessary to safely conclude and document the
already-started Encounter may continue where required
And the revocation remains historically traceable

---

### Scenario: Active-care continuity cannot authorize a later Encounter

Given Luna's Care Authorization was revoked during an active Clinical Encounter
And limited access continued only to safely conclude that Encounter
And the Encounter later ends

When Luna returns for a later unrelated veterinary visit

Then the previous limited continuity provides no medical-access basis
And a new valid authorization basis is required

---

### Scenario: Revocation does not erase clinical history

Given Luna previously received valid veterinary care
And clinical information exists in her longitudinal medical history

When a related Care Authorization is revoked

Then the clinical information remains intact
And Clinical Encounters remain intact
And original provenance remains intact

---

### Scenario: Revocation does not erase Clinic-authored history

Given Animalia Madrid Centro validly created clinical information for Luna
during an authorized care episode

When Luna's Guardian later revokes the Care Authorization

Then Animalia's historical clinical contribution is not deleted
And its authorship and provenance remain unchanged
And current access to other providers' history remains subject to current
authorization

---

### Scenario: Authorization cannot be reactivated

Given a Care Authorization for Luna and Animalia Madrid Centro was previously
revoked

When a User attempts to make that same authorization active again

Then the historical authorization remains revoked
And reauthorization requires creation of a new valid Care Authorization

---

### Scenario: Later authorization creates a new period

Given Luna previously had a Care Authorization for Animalia Madrid Centro
And that authorization was revoked
And Luna later requires a new episode of care at Animalia Madrid Centro
And Maria validly grants authorization again

When the new authorization is established

Then a new Care Authorization period is created
And the previous revoked authorization remains historical
And the two periods remain distinguishable

---

### Scenario: Already revoked authorization is not revoked again

Given Luna's Care Authorization has already been revoked

When another revocation attempt occurs

Then the original revocation time remains unchanged
And the original revoking User remains unchanged
And no duplicate revocation history is created

---

### Scenario: Normally ended authorization is not rewritten as revoked

Given Luna's Care Authorization ended because the applicable care episode
concluded

When a later revocation attempt targets that historical authorization

Then the historical normal end remains unchanged
And the authorization is not rewritten as though it had been actively revoked

---

### Scenario: Care Authorization ends normally after care is resolved

Given Luna has an active Care Authorization for Animalia Madrid Centro
And the associated Clinical Encounter has been concluded
And the supported post-care documentation requiring that authorization has
been resolved

When the Care Authorization is normally ended

Then it becomes `ENDED`
And it no longer grants current medical access
And the authorization remains historically identifiable
And it is not represented as Guardian-revoked

---

### Scenario: Encounter conclusion does not prematurely end authorization

Given Luna has an active Care Authorization
And Luna's Clinical Encounter has just been concluded
And a legitimate Draft Clinical Record Entry from that Encounter remains to be
completed

When the Encounter becomes `CONCLUDED`

Then the Care Authorization does not become `ENDED` solely because of that
transition
And any continued access remains limited to completing the existing care
context

---

### Scenario: Post-care authorization cannot be used for unrelated browsing

Given Luna's Clinical Encounter is concluded
And the Care Authorization remains current only because legitimate post-care
documentation is still being completed

When a professional attempts unrelated browsing of Luna's longitudinal medical
history

Then the existing post-care context does not itself authorize that unrelated
access

---

### Scenario: Normally ended authorization cannot support later care

Given Luna's previous Care Authorization ended normally

When Luna later requires a new veterinary care episode

Then the ended authorization provides no current medical-access basis
And a new valid authorization must be established where required

---

### Scenario: Later authorization after normal end creates new period

Given Luna previously had a Care Authorization at Animalia Madrid Centro
And that authorization ended normally
And Maria later authorizes a new episode of care at the same Clinic

When the new authorization is established

Then a new Care Authorization period is created
And the previous normally ended authorization remains unchanged

---

### Scenario: Normally ended authorization cannot later be revoked

Given Luna's Care Authorization already reached `ENDED`

When Maria later attempts to revoke that historical authorization

Then the original normal end remains authoritative
And the authorization is not rewritten as `REVOKED`

---

### Scenario: Revoked authorization does not become normally ended later

Given Luna's Care Authorization was revoked while an Encounter was underway
And minimum continuity allowed that Encounter to be safely concluded

When the Encounter later becomes `CONCLUDED`

Then the Care Authorization remains historically `REVOKED`
And it is not rewritten as normally `ENDED`

---

### Scenario: Appointment completion does not end authorization automatically

Given Luna has an Appointment and active Care Authorization

When the Appointment becomes `COMPLETED`

Then the Care Authorization does not become `ENDED` solely because of the
Appointment transition

---

### Scenario: Revocation after completion blocks retrospective documentation

Given Luna's Appointment is `COMPLETED`
And no Clinical Encounter exists for it
And its Care Authorization is `ACTIVE`

When Maria, a current Guardian, revokes the Care Authorization

Then the Care Authorization becomes `REVOKED`
And the Appointment remains `COMPLETED`
And no Appointment-backed Clinical Encounter may later be established for it

---

### Scenario: Completed Appointment authorization does not allow browsing

Given Luna's Appointment is `COMPLETED`
And no Clinical Encounter exists for it
And its Care Authorization is `ACTIVE`

When a Clinic professional attempts to read Luna's medical history through
that authorization without an established Encounter

Then access is denied

---

### Scenario: Concurrent revocation and normal ending remain coherent

Given Luna has one active Care Authorization
And the care context becomes eligible for normal ending
And an authorized Guardian concurrently revokes the Authorization

When the competing operations are committed

Then one coherent terminal authorization history is preserved
And the Authorization is not simultaneously represented as both `REVOKED` and
`ENDED`

---

### Scenario: Repeated normal ending preserves original history

Given Luna's Care Authorization was normally ended at T1

When another normal-ending attempt occurs at T2

Then T1 remains the authoritative end time
And no duplicate terminal history is created

---

## 6. Revocation Before Care vs During Care

Revocation has different consequences depending on whether actual veterinary
care has begun.

Before a Clinical Encounter:

    Care Authorization
           ↓ revoke
    current medical access ends

During an active Clinical Encounter:

    Care Authorization
           ↓ revoke
    broad current authorization ends
           +
    minimum continuity may remain only where required
    to safely conclude and document care already underway

After the care episode has already ended:

    authorization is historical
    and no longer grants current access

This distinction prevents both indefinite access and unsafe interruption of
active veterinary care.

---

## 7. Historical Authorization

A revoked authorization remains meaningful historical information.

For example:

    Luna
    Animalia Madrid Centro

    Granted:
    2026-09-01 09:15
    By: Carlos

    Revoked:
    2026-09-02 14:20
    By: Maria

    Current access through this authorization:
    No

The platform must be able to distinguish:

    "This authorization once existed"

from:

    "This authorization currently permits access"

---

## 8. Relationship to Appointment

Revoking Appointment-derived Care Authorization does not itself cancel the
Appointment.

Instead:

    Appointment remains
          +
    required medical authorization is absent
          ↓
    operations that require medical authorization cannot proceed
          ↓
    Appointment must be resolved through applicable Appointment behavior

This avoids coupling Appointment lifecycle and medical-access lifecycle into
one destructive operation.

---

## 9. Relationship to Clinical Encounter

A Care Authorization may be revoked before, during, or after the intended care
context.

If no Encounter has begun, normal access through the authorization ends.

If an Encounter is already underway, revocation must not create an unsafe
care-abandonment requirement.

Any continuing access must be limited to what is necessary to safely conclude
and document the already-started Encounter.

A future care episode requires a new current valid access basis.

---

## 10. Normal Care Authorization Ending

Normal ending occurs after the authorized care context has been resolved.

A typical sequence is:

    Care Authorization ACTIVE
            ↓
    Clinical Encounter ACTIVE
            ↓
    active care concludes
            ↓
    Clinical Encounter CONCLUDED
            ↓
    legitimate post-care documentation completed
            ↓
    Care Authorization ENDED

The interval between:

    Encounter CONCLUDED

and:

    Care Authorization ENDED

must not become unrestricted access.

Only access legitimately required to resolve the same existing care context
may continue.

Conversely, the system must not require the authorization to remain active
indefinitely after its care purpose has been resolved.

---

## 11. Edge Cases

### Guardian who granted authorization loses Guardianship

A Care Authorization that was validly granted while the User was an
authorized Guardian does not automatically become historically invalid if that
User later loses Guardianship.

Current Guardians may still revoke the active authorization.

The original grantor's loss of Guardianship removes their own authority to
manage the authorization going forward.

---

### Several Guardians disagree

Phase 1 gives current Guardians equivalent Care Authorization management
capability.

Therefore, one current Guardian may revoke an authorization originally granted
by another current Guardian.

More complex Guardian-consent or disagreement rules require a future dedicated
Specification if the product needs them.

---

### Revocation and access occur concurrently

Authorization state must be evaluated as part of protected medical access.

The system must avoid treating an access request occurring after effective
revocation as though the authorization remained active merely because of stale
client state.

The exact concurrency-control mechanism is architectural.

---

### Revocation and care-episode completion occur concurrently

The resulting authorization history must remain coherent.

The authorization must no longer grant normal current access once either valid
termination path takes effect.

The exact persistence ordering is architectural, but historical events must not
produce contradictory current authorization.

---

### Notification delivery fails

Failure to notify the Clinic or Guardian through email, push notification, or
another communication mechanism must not undo an otherwise valid revocation.

Authorization state and communication delivery are separate concerns.

---

### Emergency access

Emergency access that may override or operate independently from normal
Guardian Care Authorization is outside Phase 1.

No emergency bypass must be inferred from this Specification.

Future emergency behavior is governed by `REQ-ACC-008`.

---

## 12. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 13. Dependencies

- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ID-003 — Authenticate User
- SPEC-PET-003 — Accept Guardianship Invitation

Appointment-derived Care Authorization may interact with:

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-003 — Cancel Appointment
- SPEC-APT-007 — Assign Veterinarian to Appointment
- SPEC-APT-008 — Reassign Veterinarian

Active veterinary care may interact with:

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-008 — Conclude Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-007 — Manage Clinical Attachments

---

## 14. Out of Scope

This Specification does not define:

- granting a replacement Care Authorization;
- differentiated Guardian permissions;
- Guardian disagreement resolution;
- exact medical-data scopes for each professional capability;
- detailed access-event auditing;
- legal medical-record retention periods;
- automatic Appointment cancellation after revocation;
- Clinical Encounter completion;
- emergency medical access;
- legal consent wording;
- notification implementation.
- automatic timeout-based Care Authorization expiration;
- scheduled Care Authorization expiration;
- reopening an ended Care Authorization;
- detailed post-care documentation queue modeling;
- Clinic access to its own retained records after the Care Authorization has ended;
- the trusted normal-ending operation for the authorization of a `COMPLETED`
  Appointment;
- a fixed retrospective documentation window after Appointment completion;

---

## 15. Verification Notes

Verification must demonstrate that:

1. a current active Guardian may revoke an active revocable Care Authorization;
2. the revoking Guardian need not be the original granting Guardian;
3. historical Guardianship alone does not grant revocation authority;
4. revocation is Pet-specific and care-context-specific;
5. revocation removes the authorization as a normal current medical-access
   basis;
6. cross-clinic access through the revoked authorization no longer remains
   available;
7. previously valid authorized access is not retroactively invalidated;
8. authorization and access history are not erased by revocation;
9. clinical history and provenance remain unchanged;
10. revocation before care prevents continued access through that
    authorization;
11. revocation does not silently delete or cancel the Appointment;
12. Appointment operations requiring medical authorization cannot use a revoked
    authorization;
13. revocation during active care does not create an unsafe abandonment
    requirement;
14. any post-revocation active-care continuity is limited to the minimum
    necessary for the already-started Encounter;
15. a revoked authorization cannot authorize future care episodes;
16. revoked authorizations cannot be reactivated;
17. later authorization creates a distinct authorization period;
18. repeated revocation does not rewrite historical revocation information;
19. revocation and removal of normal current access behave atomically;
20. emergency-access behavior is not implicitly introduced.
21. an active Care Authorization may end normally after its authorized care
    purpose is resolved;
22. `REVOKED` and `ENDED` remain historically distinguishable;
23. an active Clinical Encounter prevents ordinary normal ending;
24. Clinical Encounter conclusion alone does not automatically end Care
    Authorization;
25. legitimate post-care documentation may continue before normal ending where
    the authorization remains applicable;
26. post-care access remains limited to the existing care episode;
27. Care Authorization must not remain current indefinitely after its purpose has been resolved;
28. normal ending removes the Authorization as a current medical-access basis;
29. normally ended Authorizations cannot be reactivated;
30. later authorization after normal end creates a new authorization period;
31. `ENDED` cannot later be rewritten as `REVOKED`;
32. `REVOKED` cannot later be rewritten as `ENDED`;
33. Appointment completion does not automatically end Care Authorization;
34. normal ending does not modify medical history or clinical provenance;
35. repeated normal ending does not rewrite original end information;
36. concurrent normal ending and revocation preserve one coherent terminal
    authorization history;
37. protected access evaluates current effective authorization state rather
    than stale client state;
38. a `COMPLETED` Appointment's `ACTIVE` authorization without an Encounter
    provides no medical access by itself;
39. a current Guardian may revoke the authorization of a `COMPLETED`
    Appointment, and revocation prevents establishment of a new
    Appointment-backed Encounter while leaving the Appointment `COMPLETED`.

---

## 16. Phase 1 Guardian Appointment-keyed client contract

Defined by **Guardian Appointment Medical Access Revocation — Phase 1**. It
narrows BR-1–BR-32 and BR-55 for the mobile client; it does not change them.
It is the only Phase 1 client path for revocation. It revokes exactly one
Appointment-derived (`APPOINTMENT_CARE`) Care Authorization, identified by its
Appointment. Pet-wide revocation, revocation of a `CLINICAL_INTAKE`
authorization, a revocation reason, and any Clinic notification are not part
of this contract.

### BR-56 — Canonical revoke operation

    revoke_my_appointment_care_authorization(
        p_appointment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated` (not `anon`, not `service_role`). The client supplies only the
Appointment. It never supplies a Care Authorization, Pet, Guardianship, User,
Clinic, or Organization identifier: the server derives the Pet from the
Appointment, the acting User's current Guardianship of that Pet, and the
Appointment's unique Appointment-derived Care Authorization.

### BR-57 — Authority before existence

The operation decides, in this order:

1. authentication and a coherent domain User — otherwise `28000`;
2. argument shape only, depending on no stored data: a present Appointment
   identifier — otherwise `22023`, hint `INVALID_APPOINTMENT`;
3. the acting User's current Guardianship (BR-2, BR-3) of the Pet of the named
   Appointment, resolved together with that Appointment, so an Appointment of
   a Pet the caller does not currently guard is indistinguishable from an
   Appointment that does not exist;
4. the Appointment-derived Care Authorization of that Appointment;
5. locks, in the order every Appointment operation uses: the Appointment
   (shared), the acting Guardianship, then the Care Authorization; the
   Guardianship is re-verified under its lock;
6. reconciliation of the Care Authorization's current state (BR-59);
7. revocation, through the same trusted transition every revocation uses
   (BR-1, BR-10, BR-30, BR-31).

An unknown Appointment, an Appointment of another Pet or another Guardian, a
former Guardian, and a missing Care Authorization all fail with the same
`42501` and the same message, with no hint. No raw database error and no
existence-revealing error (`23503`) is part of the contract.

Any current Guardian of the Pet may revoke, whoever requested the Appointment
or granted the authorization (BR-3, BR-4).

### BR-58 — Outcomes

| Situation | Result |
| --- | --- |
| The Care Authorization is `ACTIVE` | `{"outcome": "REVOKED"}`; it is now `REVOKED` with the acting User and the revocation time |
| The Care Authorization is already `REVOKED` or `ENDED` | `{"outcome": "ALREADY_INACTIVE"}`; nothing is written |

The result carries no identifier, no lifecycle detail, and no medical
information. No revocation reason is collected; the stored reason is empty
(BR-11).

### BR-59 — Replay and reconciliation

The operation is idempotent by state. An exact retry, a retry after a lost
response, a second Guardian's concurrent attempt, and an attempt after the
authorization already ended through cancellation, no-show, or expiry all
reconcile to `ALREADY_INACTIVE`. Nothing is recreated, reactivated, or
rewritten: the first revocation's actor and time stay (BR-29), and an `ENDED`
authorization is never rewritten as `REVOKED` (BR-45). A client that receives
`ALREADY_INACTIVE` re-reads the Appointment and presents the authoritative
state calmly.

### BR-60 — The Appointment and the clinical record are unchanged

Revocation through this operation:

- does not cancel, complete, or otherwise transition the Appointment, and
  changes none of its scheduling, Veterinarian Assignment, Reschedule
  Proposal, or Lifecycle Events (BR-16, §8);
- deletes and modifies no Clinical Encounter, Clinical Record Entry, Draft,
  Clinical Amendment, Clinical Attachment, or audit event (BR-12, BR-13,
  BR-32);
- leaves the Guardian's own medical history unchanged (`SPEC-MED-005`).

### BR-61 — Effects on professional access follow the existing rules

No new access rule is introduced; the existing predicates decide:

- professional longitudinal history through the Appointment is denied
  immediately, before care and also during an `ACTIVE` Encounter
  (`SPEC-MED-005` BR-40);
- an `ACTIVE` Encounter keeps its revocation-safe continuity for its own
  clinical record — read, Draft, Finalize, Conclude, and Amendment exactly as
  `SPEC-MED-009` BR-4 and `SPEC-MED-004` §15 already allow (BR-19, BR-20);
  revocation does not abort, conclude, or block that Encounter;
- once that Encounter is `CONCLUDED`, or when it was already `CONCLUDED`, its
  clinical record read and client Amendments are denied (`SPEC-MED-009` BR-4,
  `SPEC-MED-004` BR-39–BR-44 decision D2);
- with no Encounter, no Appointment-backed Encounter can be established for
  the Appointment any more (BR-55, `SPEC-MED-001` BR-30, BR-34).

Revocation is not itself a protected medical access and records no Medical
Access Audit Event; the Care Authorization keeps the revoking User and time
(BR-10, BR-30).

### BR-62 — Generic and deferred client paths are withdrawn

`revoke_pet_care_authorization(uuid, text)` (keyed by a Care Authorization
identifier) and `revoke_appointment_care_authorization(uuid, text)` (which
reveals Appointment and Care Authorization existence before authority and
reports raw errors) are not client paths: `authenticated` `EXECUTE` is
withdrawn. They remain trusted internal operations.

`grant_pet_care_authorization(uuid, uuid)`, which establishes a standing
`CLINICAL_INTAKE` authorization, has no Phase 1 client workflow because
Clinical Intake is deferred: `authenticated` `EXECUTE` is withdrawn as well.
The Clinical Intake domain model (`SPEC-ACC-001` BR-37, BR-41;
`SPEC-MED-001` BR-10, BR-29) and its trusted operations are unchanged.

### BR-63 — Guardian read state

The Guardian Appointment read exposes the medical-access state of each
Appointment's Appointment-derived Care Authorization as an operational state
only (`SPEC-APT-011` BR-35): `ACTIVE`, `REVOKED`, or `INACTIVE`.

### Mobile presentation

Revocation is exceptional and irreversible for the Appointment, so it is
never presented as a primary or habitual action. This presentation changes no
rule of this Specification: when revocation is possible (BR-56–BR-58) and its
effects (BR-59–BR-61) are unchanged.

- The Guardian Appointment detail shows a **Medical access / Acceso médico**
  card whenever the state is `ACTIVE` — in any Appointment lifecycle,
  including `COMPLETED`. Visibility depends on the state, never on the
  Appointment lifecycle alone. The card shows the status **Medical access
  active / Acceso médico activo**, a short neutral explanation of the access
  this Appointment provides, and one visible secondary action **Manage medical
  access / Gestionar acceso médico**. No destructive control is shown until
  the Guardian opens the management panel.
- The secondary action expands an inline management panel, in the same visual
  pattern as the Appointment cancellation panel. Opening it calls nothing. The
  panel states the real consequences of withdrawing, in a few short paragraphs
  readable on a small screen, by the Appointment lifecycle the Guardian sees
  (the Guardian is never told the Encounter state, which they do not know):
  - `REQUESTED` or `CONFIRMED`: the Appointment is not cancelled, but the
    Clinic loses access to the Pet's medical history; if care has not started
    yet, the Clinic cannot record this visit in the history; care already
    started can be finished;
  - `COMPLETED`: the Appointment stays completed and existing records are not
    deleted; the Clinic can no longer see the Pet's previous medical history;
    if care for this Appointment has not started yet, the Clinic can no longer
    record it; if it had already started, the Clinic can finish it (BR-61),
    but afterwards cannot view or correct its records through this
    Appointment;
  - in every case, as a discreetly emphasized last paragraph: it cannot be
    undone for this Appointment.

  The copy never says that the Appointment is cancelled or that records are
  deleted; it states that they are not. The panel offers the destructive action **Withdraw medical access /
  Retirar acceso médico** and **Go back / Volver**, which closes the panel and
  changes nothing.
- The destructive action opens a short final confirmation (a system alert)
  with **Go back / Volver** and **Withdraw access / Retirar acceso**; it does
  not repeat the consequences already shown in the panel. The operation is
  called only after this explicit confirmation, at most once while it is
  open or in flight. Dismissing it changes nothing. No reason is asked.
- After `REVOKED` or `ALREADY_INACTIVE` the client re-reads the Appointment;
  the card, panel, and actions disappear and a calm **Medical access
  withdrawn / Acceso médico retirado** state replaces them when the state is
  `REVOKED`; with `INACTIVE` nothing about medical access is shown. The panel
  never stays open once an authoritative read shows the state is no longer
  `ACTIVE`. A retry after an uncertain response is never presented as an
  error.
- The copy never mentions Care Authorization, capabilities, Entitlements,
  internal states, or identifiers. No Professional, Receptionist, or
  Administrator surface shows the revocation.

## 17. Phase 1 Guardian client contract Verification Notes

In addition to §15, verification must demonstrate that:

40. a current Guardian revokes the `ACTIVE` authorization of a `REQUESTED`,
    a `CONFIRMED` (before and after its start), and a `COMPLETED` Appointment
    through the Appointment alone, with outcome `REVOKED`;
41. a second current Guardian of the Pet may revoke; a Guardian of another
    Pet, a former Guardian, an unknown Appointment, and an unauthenticated
    caller are refused, the first three with the same `42501`, message, and
    no hint;
42. an exact retry and a retry after the authorization ended through
    cancellation, no-show, or expiry return `ALREADY_INACTIVE` and write
    nothing; the first revocation's actor and time stay;
43. the Appointment and every Encounter, Entry, Amendment, and audit event are
    unchanged by revocation;
44. professional longitudinal history is denied after revocation, before care
    and during an `ACTIVE` Encounter;
45. an `ACTIVE` Encounter's own record keeps its continuity, and after it is
    concluded the record and client Amendments are denied;
46. an already `CONCLUDED` Encounter's record and client Amendments are denied
    after revocation;
47. the Guardian's medical history is unchanged;
48. the result and the Guardian read carry no Care Authorization identifier;
49. the generic revoke operations and the `CLINICAL_INTAKE` grant are not
    executable by `authenticated`;
50. concurrent revocation, cancellation, no-show, professional reads, clinical
    writes, and Amendments serialize into one coherent terminal history with
    no deadlock and no resurrection;
51. with `ACTIVE` access, the Guardian detail shows the active status and the
    secondary **Manage medical access** action, and no destructive control
    until the management panel is opened (§16 Mobile presentation);
52. opening and closing the panel, and going back from the final
    confirmation, call no operation and change nothing;
53. the panel's consequences differ for `REQUESTED`/`CONFIRMED` and
    `COMPLETED` Appointments, state that the Appointment is not cancelled
    (and, once completed, that existing records are not deleted) and that
    withdrawal cannot be undone for the Appointment, and never claim
    cancellation, record deletion, or an Encounter state;
54. only the explicit final confirmation calls the operation, exactly once
    even under repeated taps; the panel closes once an authoritative read
    shows `REVOKED` or `INACTIVE`, and the outcome notices are unchanged.

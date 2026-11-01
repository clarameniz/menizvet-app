# SPEC-ACC-001 — Grant Pet Care Authorization

**Status:** APPROVED  
**Requirements:** REQ-ACC-001, REQ-ACC-002, REQ-ACC-003, REQ-ACC-005, REQ-ACC-006  
**Domain:** Medical Access Control  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the Care Authorization governs only prior-history access (SPEC-MED-010 BR-14) and no longer supports a Clinical Encounter; completion ends it with `APPOINTMENT_COMPLETED` (SPEC-MED-010 BR-16). BR-19, BR-20, BR-28, BR-29, BR-41, BR-42, §7, and Verification Notes 22–27 are replaced accordingly. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Guardian to explicitly authorize a Veterinary Clinic to
access relevant protected medical information for a Pet for the purpose of
evaluating, preparing, organizing, and providing veterinary care.

A Pet Care Authorization establishes an explicit business basis for
professional medical access.

The existence of:

- a Veterinarian Professional Profile;
- a Clinic Assignment;
- an Organization Membership;
- an Appointment;

must not, by itself, grant unrestricted access to the Pet's protected medical
information.

---

## 2. Preconditions

- The Pet exists.
- The Clinic exists.
- The Clinic belongs to a Veterinary Organization.
- The acting User exists.
- The acting User is authenticated.
- The acting User has an active Guardianship relationship with the Pet.
- The acting User is authorized to grant the applicable care authorization for
  the Pet.
- The intended care context is identifiable.
- The authorization purpose is valid and supported.

---

## 3. Business Rules

### BR-1 — Medical access requires an explicit authorized basis

Professional access to protected Pet medical information must not arise solely
from professional status.

A valid Pet Care Authorization may establish an explicit medical-access basis
for a specific care context.

---

### BR-2 — Veterinarian status alone grants no Pet access

A User must not gain access to arbitrary Pet medical information merely
because they:

- have a Veterinarian Professional Profile;
- have verified veterinary credentials;
- belong to a Veterinary Organization;
- practice at a Clinic.

Professional identity and Pet-specific medical authorization are separate
concepts.

---

### BR-3 — Care Authorization is Pet-specific

A Pet Care Authorization applies to exactly one Pet.

Authorization concerning Luna must not grant access to Toby or any other Pet.

---

### BR-4 — Care Authorization is Clinic-specific

A Pet Care Authorization applies to the Clinic identified by the authorized
care context.

Authorization granted to Animalia Madrid Centro must not automatically grant
medical access to:

- Animalia Getafe;
- another Clinic of the same Organization;
- another Veterinary Organization.

Each care-provider context must be explicitly authorized where required.

---

### BR-5 — Authorization may support access to cross-clinic history

A valid Pet Care Authorization may allow appropriately authorized
professionals in the target Clinic to access relevant medical history created
by other participating Clinics and Veterinary Organizations.

Cross-clinic access must preserve the original provenance of every clinical
record.

Access must not transfer authorship, ownership, or editing authority over
historical clinical information.

---

### BR-6 — Authorization is granted for a care purpose

The Care Authorization must be associated with an identifiable veterinary-care
purpose or context.

Examples may include:

- evaluating an Appointment request;
- preparing for an upcoming veterinary visit;
- triaging the reason for visit;
- assigning an appropriate Veterinarian;
- providing veterinary care;
- documenting the resulting authorized care.

The authorization must not become an unrestricted general-purpose right to
inspect the Pet's medical history.

---

### BR-7 — Appointment request may establish Care Authorization

When a Guardian requests an Appointment, the Appointment workflow may require
the Guardian to explicitly grant the target Clinic the applicable Pet Care
Authorization.

The Appointment itself must not be treated as implicit authorization.

The Guardian's authorization must be an explicit part of the applicable
workflow.

---

### BR-8 — Care Authorization may begin before Appointment confirmation

A valid Care Authorization associated with an Appointment request may become
effective before the Appointment reaches `CONFIRMED` state.

This allows the Clinic to access relevant information required to:

- evaluate the request;
- perform appropriate triage;
- determine suitable professional Assignment;
- decide whether and how the Appointment can be confirmed.

This pre-confirmation use is preparation and triage only. It is time-bounded by
BR-39 and does not by itself permit a Clinical Encounter for that Appointment
(BR-41).

---

### BR-9 — Care Authorization supports appropriate Veterinarian Assignment

Where medical context is necessary to determine an appropriate Veterinarian,
a valid Care Authorization may provide an access basis for authorized Clinic
actors performing that scheduling or triage function.

The existence of this authorization does not mean that every Clinic Member may
access the same medical information.

Actor-specific authorization and least-privilege rules still apply.

---

### BR-10 — Authorization is granted to a care-provider context, not every employee

Granting Pet Care Authorization to a Clinic must not make the Pet's protected
medical information universally accessible to every User associated with that
Clinic or Organization.

Medical access requires both:

- a valid Pet Care Authorization or other applicable medical-access basis;
- an actor whose current professional responsibilities justify the requested
  access.

---

### BR-11 — Least privilege applies within an authorized care context

An authorized professional or operational actor must only access medical
information required for the purpose they are currently authorized to perform.

For example, information required to organize an Appointment may differ from
information required by the Veterinarian providing clinical care.

This Specification does not define the exact field-level or record-level
visibility model.

---

### BR-12 — Care Authorization does not grant Organization capabilities

Granting medical access for a Pet must not create or modify:

- Organization Membership;
- Clinic Assignment;
- Organization responsibilities;
- administrative capabilities;
- subscription entitlements.

---

### BR-13 — Care Authorization does not modify Guardianship

Granting a Clinic access to a Pet's relevant medical information must not:

- create another Guardian;
- remove a Guardian;
- transfer Guardianship;
- modify existing Guardianship relationships.

---

### BR-14 — Care Authorization does not create clinical information

Granting medical access must not itself create:

- a Clinical Encounter;
- a Medical Record Entry;
- a diagnosis;
- a Treatment;
- a prescription;
- a vaccination;
- another clinical statement.

It establishes authorization, not clinical meaning.

---

### BR-15 — Authorization must preserve who granted it

The system must preserve enough information to establish:

- the Pet;
- the Clinic;
- the Veterinary Organization context;
- the granting Guardian;
- when authorization was granted;
- the care purpose or context;
- the authorization state.

---

### BR-16 — Authorization must be distinguishable from legal or product terms acceptance

A Pet Care Authorization is a domain authorization concerning access to
protected medical information.

It must not be reduced conceptually to a generic acceptance such as:

    terms_accepted = true

Acceptance of general terms and authorization of medical access may coexist
but represent different facts.

---

### BR-17 — Authorization may be revocable

A Pet Care Authorization must support revocation where the applicable care
context permits it.

Revocation behavior is defined by a separate Specification.

Historical evidence that authorization existed must not need to be deleted
when current access is revoked.

---

### BR-18 — Authorization is not assumed to be permanent

A Care Authorization granted for a particular episode of veterinary care must
not be interpreted as permanent unrestricted access to the Pet's longitudinal
medical history.

Its continued validity must be associated with the applicable care context and
authorization lifecycle.

---

### BR-19 — Appointment cancellation ends Appointment-derived authorization when care has not occurred

Where a Care Authorization exists specifically for an Appointment-derived
care episode and the Appointment is cancelled before veterinary care occurs,
that authorization must cease granting current medical access.

Historical evidence of the authorization remains traceable.

If veterinary care has already begun, the applicable Clinical Encounter and
care-episode rules determine the continuing authorization context.

---

### BR-20 — Authorized care may continue into a Clinical Encounter

When an Appointment-derived care context results in actual veterinary care,
the applicable Care Authorization may provide part of the authorized basis for
establishing the resulting Clinical Encounter.

The system must preserve the relationship between the access basis and the
professional care context where required.

---

### BR-21 — Care Authorization does not allow rewriting other providers' history

Access to clinical information created by another Clinic must be read access
unless an applicable Medical Records Specification explicitly permits another
operation.

The target Clinic must not silently modify or replace another provider's
finalized historical clinical information.

---

### BR-22 — Original clinical provenance remains authoritative

When cross-clinic medical history is accessed, every clinical entry must
continue to identify its original:

- Veterinarian or author;
- Clinic;
- Veterinary Organization;
- clinical date;
- authorship context.

The accessing Clinic must not become the historical source merely because it
viewed the information.

---

### BR-23 — Current authorization must be evaluated when access occurs

Historical existence of a Care Authorization must not automatically prove that
medical access is currently permitted.

The applicable authorization state and professional context must be evaluated
when protected information is accessed.

---

### BR-24 — Care Authorization creation is atomic

A successfully granted Care Authorization must establish one coherent access
basis containing the required Pet, Clinic, Guardian, purpose, and temporal
context.

The system must not expose an ambiguous partial authorization.

---

### BR-25 — Care Authorization is tied to a care episode

A Pet Care Authorization must be associated with an identifiable episode or
intended episode of veterinary care.

Its validity must not be treated as an indefinite standing permission for the
Clinic to access the Pet's longitudinal medical history.

The authorization may support the applicable care context from preparation and
triage through the resulting veterinary care.

---

### BR-26 — Appointment-derived authorization begins with the authorized request

When Care Authorization is explicitly granted as part of an Appointment
request, it may become active when the Appointment request is successfully
established.

The Clinic does not need to wait for Appointment confirmation before using the
authorization for legitimate preparation, triage, or professional Assignment
purposes, within the time bound of BR-39.

---

### BR-27 — Appointment cancellation ends the normal Appointment-derived access basis

If an Appointment-derived care context is cancelled before veterinary care
occurs, the associated Care Authorization must no longer grant current medical
access for that cancelled episode.

Historical evidence that the authorization existed must remain traceable.

Cancellation must not erase previous authorized-access history where such
history is retained for audit purposes.

---

### BR-28 — Care Authorization may continue into the resulting Clinical Encounter

When the authorized Appointment or intake process results in actual veterinary
care, the Care Authorization may continue to support the resulting Clinical
Encounter.

The transition from Appointment preparation to actual care must not require an
artificial gap in authorization solely because the care has begun.

---

### BR-29 — Authorization ends when the applicable care episode ends

A Care Authorization must cease granting current access when the veterinary
care episode for which it was granted has concluded, unless another valid
medical-access basis applies.

The system must preserve the distinction between:

- authorization that existed historically;
- authorization that currently permits access.

The exact definition of clinical episode completion is governed by the
Specifications that define completion of veterinary care.

---

### BR-30 — Ending one care authorization does not erase clinical history

When a Care Authorization ceases to grant current access, the Pet's medical
history must remain intact.

Ending authorization must not delete:

- Clinical Encounters;
- Medical Record Entries;
- clinical provenance;
- historical access or authorization evidence.

Access lifecycle and medical-history lifecycle are separate concerns.

---

### BR-31 — New care episodes require a current valid access basis

A previous Care Authorization must not automatically authorize a later
unrelated episode of veterinary care.

If the Pet returns to the same Clinic for a new care episode, current medical
access must be supported by the applicable valid authorization basis for that
new context.

Previous care history remains available only where current authorization rules
permit access.

---

### BR-32 — Appointment-derived authorization participates in the Appointment request transaction

When a Care Authorization is created specifically as part of the Guardian-facing
Appointment request defined by `SPEC-APT-001`, the authorization and Appointment
request must be established as one coherent domain operation.

The authorization must not be exposed as successfully established while its
required Appointment request failed.

---

### BR-33 — Appointment-derived authorization must match the Appointment context

A Care Authorization established through an Appointment request must refer to:

- the same Pet;
- the same target Clinic;
- the same intended care episode or Appointment-derived context.

A mismatched authorization must not satisfy the Appointment workflow.

For example:

    Appointment → Luna @ Animalia Madrid

must not be supported by:

    Care Authorization → Toby @ Animalia Madrid

or:

    Care Authorization → Luna @ Animalia Getafe

---

### BR-34 — Failed Appointment creation prevents successful Appointment-derived authorization creation

If the Appointment request cannot be successfully established, a Care
Authorization being created specifically through that request must not remain
as an independent active authorization.

This rule applies only to the authorization being created through that failed
Appointment operation.

---

### BR-35 — Authorization failure prevents successful Appointment request

Where `SPEC-APT-001` requires the Guardian to establish Care Authorization as
part of the request, failure to establish that authorization means the
Appointment request has not successfully completed.

---

### BR-36 — Combined creation is atomic at the domain-operation boundary

The system must not expose an externally observable committed state containing
only one half of the required Appointment-request result.

Conceptually:

    success
    → Appointment REQUESTED
      +
      Care Authorization ACTIVE

    failure
    → neither new result is successfully established

The exact database transaction, trusted function, or backend mechanism used to
provide this guarantee is architectural.

---

### BR-37 — Appointment-derived authorization does not make Appointment mandatory for all authorization

The atomicity rules for `SPEC-APT-001` apply only when Care Authorization is
being established through that Appointment workflow.

They must not prohibit another approved workflow from establishing valid Care
Authorization without an Appointment.

---

### BR-38 — Unrelated authorization state must not participate in rollback

Failure of an Appointment request must not revoke, end, delete, or rewrite an
independent Care Authorization that existed before the failed operation.

Only state being established as part of the failing domain operation is subject
to its atomic failure semantics.

---

### BR-39 — Pre-care access through a requested Appointment ends at the requested start

While an Appointment is `REQUESTED`, its Appointment-derived Care Authorization
may provide the pre-care access of BR-8 and BR-26 only while the scheduled start
instant of the Appointment's latest requested scheduling context is strictly in
the future, according to authoritative backend time.

Once that start instant is no longer in the future, the authorization must
immediately cease to provide pre-care medical access through that request, even
if the Appointment's `EXPIRED` outcome has not yet been materialized
(`SPEC-APT-015` BR-4).

A request that the Clinic never confirmed must not become an indefinite standing
authorization (BR-18, BR-25).

This rule does not change access for a `CONFIRMED` Appointment or for an
existing Clinical Encounter, which follow BR-20, BR-28, and BR-29.

---

### BR-40 — Appointment expiry ends the Appointment-derived authorization

When an Appointment becomes `EXPIRED` (`SPEC-APT-015`), its Appointment-derived
Care Authorization is ended (`ACTIVE → ENDED`) with the distinct normal-ending
context `APPOINTMENT_EXPIRED`.

`APPOINTMENT_EXPIRED` must remain distinguishable from the cancellation and
no-show ending contexts and must not reuse them.

An authorization already `REVOKED` or `ENDED` is left unchanged. Historical
evidence that the authorization existed remains traceable (BR-27, BR-30).

---

### BR-41 — Appointment-backed Clinical Encounters require a confirmed or completed Appointment

An Appointment-derived Care Authorization can support a Clinical Encounter for
its Appointment only once that Appointment has been confirmed, and not for care
starting before the confirmation (`SPEC-MED-001` BR-34).

The Appointment must be `CONFIRMED`, or `COMPLETED` after that confirmation.
It can never support an Encounter for a `REQUESTED`, `CANCELLED`, `NO_SHOW`, or
`EXPIRED` Appointment.

Clinical care that begins before or without Appointment confirmation, such as
walk-in or urgent care, uses an independent Clinical Intake authorization and
an Encounter that references no Appointment (BR-37).

Clinical Intake has no Phase 1 client workflow: the `CLINICAL_INTAKE` grant
and the Intake Encounter remain trusted operations, and no client can
establish a standing Intake authorization (`SPEC-ACC-002` BR-62).

---

### BR-42 — Appointment completion does not end the authorization or broaden access

An Appointment becoming `COMPLETED` (`SPEC-APT-009`) must not automatically end,
revoke, or otherwise change its Appointment-derived Care Authorization
(`SPEC-ACC-002` BR-38).

For a `COMPLETED` Appointment, an `ACTIVE` Appointment-derived Care
Authorization may support only:

- establishment of at most one valid Appointment-backed Clinical Encounter for
  that Appointment, under the bounds of `SPEC-MED-001` BR-34 — in particular,
  care that started between the confirmation and the completion;
- the authorized documentation lifecycle of that Encounter under the Medical
  Records and `SPEC-ACC-002` post-care rules.

It provides no pre-care access through the Appointment once the Appointment is
`COMPLETED`: the preparation and triage purpose of BR-26 ends with the
Appointment's resolution. Any medical access after completion arises only
through a validly established Encounter and the least-privilege rules that
govern it (§9, `SPEC-MED-001` BR-33).

Completion must not broaden general post-completion access, create standing
access to the Pet's longitudinal history, or authorize a second Encounter or a
new care episode (BR-31).

A current Guardian may revoke the authorization after completion
(`SPEC-ACC-002`). Revocation prevents establishment of any new
Appointment-backed Encounter for that Appointment.

Normal ending of such an authorization remains governed by `SPEC-ACC-002`
BR-37 and BR-38; its trusted ending operation is not defined in Phase 1.

Protected access remains fail-closed: where it is not established that the
authorization currently permits an operation, the operation is denied.

---

## 4. Care Authorization Information

The domain must support enough information to understand the authorized
medical-access context.

### Required

- Pet;
- target Clinic;
- target Veterinary Organization context;
- granting Guardian;
- authorization purpose or care context;
- granted time;
- current authorization state.
- care-episode context.

### Optional or context-dependent

- related Appointment;
- related Clinical Encounter once one exists;
- authorization expiration or end;
- additional purpose metadata required by future access policies.
- authorization end time;
- authorization end reason;

The exact persistence representation is not defined by this Specification.

---

## 5. Scenarios

### Scenario: Guardian grants Care Authorization when requesting Appointment

Given Maria has an active Guardianship relationship with Luna
And Animalia Madrid Centro is a valid target Clinic
And Maria is requesting an Appointment for Luna

When Maria explicitly grants the required Care Authorization to Animalia
Madrid Centro as part of the Appointment workflow

Then a Pet Care Authorization is established for Luna
And the authorization identifies Animalia Madrid Centro
And the authorization identifies Maria as the granting Guardian
And the authorization identifies the applicable care purpose
And the Appointment request may proceed according to its own Specification

---

### Scenario: Appointment does not imply authorization without explicit grant

Given Maria has an active Guardianship relationship with Luna
And Maria attempts to request an Appointment at Animalia Madrid Centro
And the applicable Appointment workflow requires Care Authorization
And Maria does not grant that authorization

When the Appointment request is evaluated

Then the system must not infer the existence of a Care Authorization solely from the
attempted Appointment request
And protected medical access is not granted through that missing basis

---

### Scenario: Clinic may use relevant history before confirmation

Given Maria has requested an Appointment for Luna at Animalia Madrid Centro
And Maria granted the applicable Care Authorization
And the Appointment remains `REQUESTED`
And Carlos has an authorized Clinic role for Appointment triage

When Carlos performs the authorized triage workflow

Then relevant medical information may be accessed according to the applicable
least-privilege rules
And Appointment confirmation is not required solely to establish the
authorized care context

---

### Scenario: Relevant cross-clinic history may be accessed

Given Luna previously received care at VetCare Toledo
And the resulting finalized clinical information is part of Luna's
longitudinal medical history
And Maria grants a valid Care Authorization to Animalia Madrid Centro
And Dr. Garcia has the applicable professional authorization at Animalia
Madrid Centro

When Dr. Garcia accesses relevant history while providing or preparing Luna's
care

Then the authorized VetCare information may be made available
And the information remains attributed to VetCare Toledo
And the information remains attributed to its original clinical authors
And Animalia does not become the author of that historical information

---

### Scenario: Authorization for Luna grants no access to Toby

Given Maria grants Animalia Madrid Centro a valid Care Authorization for Luna
And Toby is another Pet

When an Animalia professional attempts to access Toby's protected medical
information using Luna's authorization

Then access is denied
And Luna's authorization is insufficient

---

### Scenario: Authorization for one Clinic grants no access to another Clinic

Given Maria grants a Care Authorization for Luna to Animalia Madrid Centro
And Animalia Getafe is another Clinic in the same Organization

When a professional acts solely through the Animalia Getafe context and
attempts to use the Madrid authorization

Then the Madrid Care Authorization alone is insufficient
And Clinic-specific access rules must still be satisfied

---

### Scenario: Reception or scheduling actor does not receive unlimited clinical access

Given Luna has a valid Care Authorization with Animalia Madrid Centro
And Carlos is authorized to perform Appointment triage or scheduling
And Carlos is not authorized to perform full clinical care

When Carlos accesses Luna's information

Then Carlos may access only the information required by the authorized
operational context
And the Care Authorization does not grant unrestricted access to the complete
medical history

---

### Scenario: Veterinarian status without Care Authorization is insufficient

Given Dr. Garcia has a Veterinarian Professional Profile
And Dr. Garcia has a current Clinic Assignment at Animalia Madrid Centro
And no applicable Care Authorization or other valid medical-access basis exists
for Luna

When Dr. Garcia attempts to access Luna's protected medical history solely
because she is a Veterinarian at that Clinic

Then access is denied

---

### Scenario: Care Authorization does not create Clinical Encounter

Given Maria grants a valid Care Authorization for Luna

When the authorization is created

Then no Clinical Encounter is created solely because authorization exists
And no Medical Record Entry is created
And no diagnosis or Treatment is created

---

### Scenario: Care Authorization survives as historical evidence after access ends

Given Maria previously granted a Care Authorization for Luna
And that authorization later ceases to grant current access

When authorization history is evaluated

Then the system may preserve that the authorization previously existed
And historical evidence of the authorization must not itself grant current
medical access

---

### Scenario: Appointment-derived authorization becomes active before confirmation

Given Maria requests an Appointment for Luna at Animalia Madrid Centro
And Maria explicitly grants the required Care Authorization

When the Appointment request is successfully created

Then the Care Authorization may become active
And authorized Clinic actors may use it for legitimate preparation and triage
And Appointment confirmation is not required solely for that access basis

---

### Scenario: Appointment cancellation ends authorization before care occurs

Given Maria granted a Care Authorization for Luna as part of an Appointment
request
And no Clinical Encounter has begun

When the Appointment is cancelled

Then the Care Authorization no longer grants current medical access
And its historical existence remains traceable
And Luna's medical history is not deleted or modified

---

### Scenario: Authorization continues into actual care

Given Luna has an active Appointment-derived Care Authorization
And Luna attends the Clinic
And a valid Clinical Encounter begins

When veterinary care starts

Then the applicable authorization may continue to support that care context
And no artificial authorization gap is introduced between preparation and
actual care

---

### Scenario: Completed care episode ends current authorization

Given Luna received veterinary care under a valid Care Authorization
And the applicable care episode has concluded
And no other current medical-access basis exists

When current medical authorization is evaluated

Then the completed episode's Care Authorization no longer grants current access
And the historical authorization remains traceable
And the resulting medical history remains intact

---

### Scenario: Previous visit does not permanently authorize later care

Given Luna previously received care at Animalia Madrid Centro
And the Care Authorization for that episode has ended
And Luna later requires an unrelated new episode of care

When Animalia attempts to access Luna's protected longitudinal history solely
through the old authorization

Then the historical authorization is insufficient
And a current valid medical-access basis is required

---

### Scenario: Appointment-derived authorization commits with Appointment

Given Maria validly grants Care Authorization as part of requesting an
Appointment for Luna at Animalia Madrid Centro

When the combined Appointment request succeeds

Then the Care Authorization is established
And the Appointment is established
And they share the applicable Pet, Clinic, and care context

---

### Scenario: Failed Appointment does not create orphan authorization

Given Maria grants Care Authorization specifically as part of a new Appointment
request

When that Appointment request cannot be established

Then the Appointment-derived Care Authorization is not left active as an
independent successful authorization

---

### Scenario: Failed authorization prevents successful Appointment

Given Maria is requesting an Appointment
And the Appointment workflow requires explicit Care Authorization

When the required authorization cannot be established

Then no successful Appointment request is established through that operation

---

### Scenario: Independent authorization survives unrelated Appointment failure

Given Luna already has a valid Care Authorization from another approved care
context

When Maria attempts a separate new Appointment request
And that new request fails

Then the previously existing authorization remains unchanged

---

## 6. Relationship to Appointment

An Appointment may provide the care context in which authorization is
requested, but the two concepts remain distinct.

    Appointment
    "Luna is requested to be seen at Animalia Madrid"

    Care Authorization
    "Animalia Madrid may access the relevant protected medical information
    required to evaluate, prepare, organize, and provide this care"

An Appointment may be cancelled while the authorization history remains
auditable.

Medical-access validity must follow the authorization lifecycle rather than
being inferred solely from Appointment existence.

---

## 7. Relationship to Clinical Encounter

A valid Care Authorization may contribute to the professional authorization
basis for a Clinical Encounter.

Conceptually:

    active Guardianship
          +
    Pet Care Authorization
          +
    valid professional Clinic context
          ↓
    authorized care context
          ↓
    Clinical Encounter

This relationship must not be interpreted to mean that every Care
Authorization necessarily produces a Clinical Encounter.

An Appointment may be cancelled or care may never occur.

---

## 8. Cross-Clinic Access

Cross-clinic access is one of the primary purposes of the longitudinal medical
record.

For example:

    Luna

    VetCare Toledo
      └── Surgery

    Animalia Madrid Centro
      └── Current Appointment

A valid current Care Authorization may allow Animalia Madrid Centro to access
the relevant historical surgery information when required for Luna's current
care.

The historical surgery remains VetCare's clinical contribution to Luna's
medical history.

---

## 9. Least Privilege

Care Authorization establishes that the Clinic has a valid care-related basis
for medical access.

It does not answer every actor-level authorization question.

The effective decision is conceptually based on both:

    valid Pet Care Authorization
              +
    valid professional or operational actor context
              ↓
    permitted medical information for this purpose

The exact capability and data-scope model is defined by subsequent Access
Control Specifications.

---

## 10. Edge Cases

### Guardian revokes authorization before Appointment confirmation

The authorization must no longer grant current medical access once revocation
takes effect.

The Appointment's resulting behavior is governed by the applicable
Appointment and Access Control Specifications.

---

### Appointment is cancelled

An Appointment-derived Care Authorization may cease to be a valid current care
basis after cancellation.

Historical evidence of the authorization remains distinguishable.

---

### Appointment request is never confirmed

If the Clinic does not confirm a request before its latest requested start,
pre-care access through that request ends at that start instant (BR-39), and the
authorization is later ended with `APPOINTMENT_EXPIRED` when the Appointment
becomes `EXPIRED` (BR-40).

Existing requests whose time had already passed when this behavior was
introduced are reconciled the same way (`SPEC-APT-015` BR-17).

---

### Appointment is rescheduled

Rescheduling the same Appointment does not necessarily require creation of a
completely unrelated Care Authorization if the same Pet, Clinic, and care
purpose continue to apply.

The authorization lifecycle must nevertheless remain valid for the updated
care context.

---

### Pet changes Guardian after authorization was granted

The original granting Guardian remains historically identifiable.

Current access must continue to depend on the applicable authorization
lifecycle rather than assuming that historical Guardianship permanently
authorizes access.

---

### Clinical care occurs without Appointment

An authorized intake or other future care workflow may establish Care
Authorization without a pre-existing Appointment.

This allows valid Clinical Encounters without requiring fake Appointments.

---

### Emergency care without normal authorization

Emergency medical access without the normal Guardian authorization is outside
Phase 1.

It is reserved for the future behavior represented by `REQ-ACC-008`.

The normal workflow must not implement an undocumented emergency bypass.

---

## 11. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-ID-003 — Authenticate User
- SPEC-PET-001 — Register Pet
- SPEC-PET-003 — Accept Guardianship Invitation
- SPEC-CLI-001 — Create Clinic

Appointment-derived authorization may be used by:

- SPEC-APT-001 — Request Appointment

Appointment-derived authorization may be ended by:

- SPEC-APT-015 — Expire Unconfirmed Appointment Request

Appointment-derived authorization is not ended by:

- SPEC-APT-009 — Complete Appointment (BR-42)

Professional use of the authorization may depend on:

- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment

Clinical care may use the resulting authorization context through:

- SPEC-MED-001 — Create Clinical Encounter

---

## 13. Out of Scope

This Specification does not define:

- revoking Care Authorization;
- exact authorization expiration;
- actor-specific medical data scopes;
- field-level medical permissions;
- clinical-record creation;
- Guardian medical-history viewing;
- medical-access audit event creation;
- emergency access;
- legal consent wording;
- privacy-policy wording;
- UI checkbox design;
- exact retention periods;
- access to non-participating external veterinary systems.

---

## 14. Verification Notes

Verification must demonstrate that:

1. professional status alone does not grant arbitrary Pet medical access;
2. an active Guardian can explicitly grant a Pet-specific Care Authorization;
3. the authorization is scoped to one Clinic and care context;
4. Appointment creation is not treated as implicit medical authorization;
5. authorization may become applicable before Appointment confirmation;
6. authorized cross-clinic history may be accessed while original provenance
   remains unchanged;
7. authorization for one Pet grants no access to another Pet;
8. authorization for one Clinic does not automatically grant access through
   another Clinic context;
9. authorization applies together with actor-specific least-privilege rules;
10. operational actors do not receive unrestricted clinical access merely
    because the Clinic is authorized;
11. Care Authorization does not create Guardianship, Clinical Encounters, or
    clinical information;
12. historical authorization may remain auditable after current access ends;
13. normal authorization does not implement an undocumented emergency-access
    bypass.
14. Appointment-derived Care Authorization and the corresponding Appointment
    request are established as one coherent domain operation;
15. Appointment-derived authorization must match the Appointment Pet and Clinic;
16. failed Appointment creation does not leave its new Appointment-derived
    authorization active;
17. failure to create required Care Authorization prevents successful
    Appointment creation;
18. atomic failure does not modify unrelated pre-existing Care Authorizations;
19. these atomicity rules do not require all Care Authorizations to have an
    Appointment;
20. a `REQUESTED` Appointment's authorization provides pre-care access only
    while its latest requested start is strictly in the future, and stops
    providing it at that instant even before the `EXPIRED` outcome is
    materialized;
21. materialized Appointment expiry ends an `ACTIVE` Appointment-derived
    authorization with `APPOINTMENT_EXPIRED`, distinct from cancellation and
    no-show endings, and leaves a `REVOKED` or `ENDED` one unchanged;
22. an Appointment-derived authorization cannot support a Clinical Encounter
    for a `REQUESTED` Appointment, while a Clinical Intake authorization
    supports an Encounter without an Appointment independently;
23. Appointment completion leaves the Appointment-derived authorization
    unchanged;
24. an `ACTIVE` Appointment-derived authorization of a `COMPLETED` Appointment
    supports establishment of exactly one Appointment-backed Encounter within
    the `SPEC-MED-001` BR-34 bounds, and no second one;
25. a `COMPLETED` Appointment's authorization provides no pre-care access, and
    no medical access other than through a validly established Encounter;
26. a Guardian revocation after completion prevents establishment of a new
    Appointment-backed Encounter for that Appointment;
27. an Appointment-derived authorization cannot support an Encounter for a
    `CANCELLED`, `NO_SHOW`, or `EXPIRED` Appointment.
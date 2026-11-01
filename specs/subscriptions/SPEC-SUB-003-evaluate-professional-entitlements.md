# SPEC-SUB-003 — Evaluate Professional Entitlements

**Status:** APPROVED  
**Requirements:** REQ-SUB-003, REQ-SUB-004
**Domain:** Subscription and Entitlements  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): the `CLINICAL_CARE` Entitlement gates every new Clinical Record Entry and Clinical Attachment instead of establishing an Encounter (SPEC-MED-010 BR-13); reads and Amendments require no Entitlement; the `CLINICAL_DOCUMENTATION` Entitlement identifier is not evaluated by clinical documentation, and no Entitlement is added. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Determine whether a Veterinary Organization currently has the professional
Entitlement required to perform a paid platform capability.

Professional Entitlements are derived from trusted commercial state and
applicable product policy.

They must not be inferred solely from:

- the existence of an Organization;
- the existence of a Subscription;
- Organization Membership;
- Clinic ownership;
- Veterinarian status;
- client-side claims.

Entitlement evaluation determines whether the Organization may use a particular
paid professional capability.

It does not replace the domain authorization rules applicable to the acting
User, Clinic, Pet, Appointment, or medical-care context.

---

## 2. Preconditions

- The Veterinary Organization exists.
- The requested professional capability is identifiable.
- The system can determine whether that capability requires a professional
  Entitlement.
- Where a Subscription is required:
  - the Organization Subscription is identifiable;
  - its authoritative current commercial state is available;
  - the applicable commercial validity information is available.
- The Entitlement decision is evaluated through trusted backend
  infrastructure.

---

## 3. Entitlement Model

Entitlement evaluation answers:

    "May this Organization currently use this paid professional capability?"

It does not answer:

    "May this particular User perform the operation?"

A successful operation may therefore require both:

    valid Organization Entitlement
              +
    valid domain authorization
              ↓
    operation permitted

For example:

    Animalia has Appointment Management Entitlement
              +
    Carlos has Appointment-management capability at Madrid Centro
              ↓
    Carlos may perform the applicable Appointment operation

Neither condition is sufficient by itself.

---

## 4. Business Rules

### BR-1 — Entitlements belong to the Veterinary Organization context

Professional Entitlements are evaluated for a Veterinary Organization.

They must not be treated as personal paid capabilities belonging to:

- the purchasing User;
- an individual Organization Member;
- an individual Veterinarian;
- an individual Guardian.

---

### BR-2 — Entitlement is capability-specific

The system must evaluate Entitlement for the professional capability being
requested.

The domain must not rely on one universal:

    organization_has_paid_access = true

flag that automatically grants every professional operation.

This allows different professional capabilities to evolve independently.

---

### BR-3 — Only capabilities explicitly requiring Entitlement are gated

A Subscription must not become a global authorization switch for every domain
operation.

Only operations whose applicable Specification or product policy requires a
professional Entitlement must be denied because that Entitlement is absent.

This prevents commercial logic from silently overriding unrelated domain
behavior.

---

### BR-4 — Entitlement does not replace User authorization

Even when the Organization has the required professional Entitlement, the
acting User must still satisfy the applicable domain authorization rules.

For example:

    Organization Entitlement
    does not imply
    every Organization Member may perform the operation.

---

### BR-5 — User authorization does not replace Entitlement

An authorized Organization Member must not bypass a required professional
Entitlement merely because their responsibilities would otherwise permit the
operation.

For paid professional capabilities, both commercial and domain authorization
requirements apply.

---

### BR-6 — Client state is not authoritative for Entitlements

The mobile application must not be trusted to determine that a professional
Entitlement exists.

A manipulated client must not be able to enable a paid professional capability
by changing local application state.

---

### BR-7 — Entitlements are derived from trusted commercial information

Where a professional Entitlement depends on Subscription state, the Entitlement
decision must use authoritative commercial information.

Stale or untrusted client Subscription state must not become the security
boundary.

---

### BR-8 — Effective ACTIVE Subscription provides normal Phase 1 professional Entitlements

An Organization Subscription whose authoritative effective commercial state is
`ACTIVE` provides the normal Phase 1 professional Entitlements.

The requested operation must still satisfy:

- applicable Organization capability;
- Clinic context;
- professional qualification where required;
- Clinic Assignment where required;
- Medical Access Control where required;
- Appointment or clinical lifecycle rules;
- all other applicable domain authorization.

Entitlement is one required condition, not sufficient authorization by itself.

---

### BR-9 — PENDING Subscription does not provide normal paid Entitlements

A `PENDING` Subscription must not provide normal paid professional
Entitlements.

Subscription initiation alone is insufficient.

---

### BR-10 — EXPIRED Subscription does not provide normal paid Entitlements

An `EXPIRED` Subscription must not satisfy the commercial condition for normal
paid professional capabilities.

Historical and safety-preserving behavior remains governed separately.

---

### BR-11 — CANCELLED Subscription may retain Entitlements while commercial validity remains

A `CANCELLED` Subscription may continue providing normal professional
Entitlements when the Organization remains within an already-valid commercial
period.

Cancellation status alone must not be interpreted as immediate Entitlement
loss.

Once commercial validity ends, normal Entitlements must no longer be derived
from that Subscription.

---

### BR-12 — PAST_DUE does not provide normal Phase 1 professional Entitlements

A `PAST_DUE` Subscription does not provide normal Phase 1 professional
Entitlements.

Phase 1 does not provide an implicit commercial grace period during which new
normal paid professional activity remains available.

The system must not interpret `PAST_DUE` as equivalent to `ACTIVE`.

Safe resolution of obligations that already existed before Entitlement loss is
governed separately by `SPEC-SUB-004`.

---

### BR-13 — PAST_DUE recovery restores normal Entitlements only after effective recovery

A `PAST_DUE` Subscription may later recover to an authoritative commercially
valid `ACTIVE` state.

Normal Phase 1 professional Entitlements become available again only when that
recovery becomes effective.

The previous `PAST_DUE` period remains historical.

Operations denied or safely resolved during the non-entitled period must not be
retroactively rewritten as though Entitlement had remained continuously valid.

---

### BR-14 — Absence of current commercial validity denies normal paid operations

When the Organization has no currently valid commercial basis for a
professional capability, that normal paid operation must be denied.

The denial must not require deleting the underlying domain information.

---

### BR-15 — Entitlement loss does not delete Organization data

Failure to satisfy a professional Entitlement must not automatically delete:

- Veterinary Organization;
- Organization Memberships;
- Clinics;
- Veterinarian Professional Profiles;
- Clinic Assignments.

Commercial capability and domain existence are separate concerns.

---

### BR-16 — Entitlement loss does not delete Appointments

Absence of normal professional Entitlement must not delete existing
Appointments.

The Appointment remains historically and operationally identifiable.

The behavior allowed for existing Appointments after Entitlement loss is
defined by `SPEC-SUB-004`.

---

### BR-17 — Entitlement loss does not delete medical history

Absence of professional Entitlement must not delete or rewrite:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- longitudinal Pet medical history.

Historical clinical truth survives commercial state changes.

---

### BR-18 — Entitlement loss does not erase medical-access audit history

Medical Access Audit Events must remain preserved independently from current
commercial Entitlement.

---

### BR-19 — Entitlement does not grant medical access

An Organization having a valid professional Entitlement must not grant access
to arbitrary Pet medical information.

Medical access still requires the applicable:

- Pet Care Authorization;
- professional context;
- least-privilege rules.

Commercial payment is not medical authorization.

---

### BR-20 — Care Authorization does not create paid Entitlement

A valid Pet Care Authorization establishes a Pet-specific medical-access basis.

It must not enable paid professional platform operations when the required
Organization Entitlement is absent.

Care Authorization and commercial Entitlement are independent conditions.

---

### BR-21 — Clinic Assignment does not create Entitlement

A Veterinarian may have a valid Clinic Assignment even when the Organization
does not currently have the Entitlement required for a particular paid
operation.

Historical professional relationships remain valid as domain facts.

---

### BR-22 — Entitlement loss does not silently end Clinic Assignment

Commercial Entitlement loss must not automatically terminate or historically
rewrite active Clinic Assignments.

Whether a professional may perform a particular new platform operation depends
on the current Entitlement decision.

---

### BR-23 — Entitlement loss does not silently unpublish historical Clinic identity

Commercial Entitlement changes must not destroy the Clinic domain identity or
historical provider provenance.

Whether continued public publication requires Entitlement is a separate
capability decision.

---

### BR-24 — Public Discovery and paid professional capability remain distinguishable

The domain must not assume that all public Clinic information must disappear
immediately because normal professional Entitlements are unavailable.

Publication, discovery, commercial eligibility, and historical provider
identity are separate concepts.

Where continued publication requires Entitlement, that requirement must be
explicitly defined.

---

### BR-25 — Phase 1 normal paid professional Entitlements are explicit

Phase 1 defines the following normal paid professional Entitlements:

- `APPOINTMENT_MANAGEMENT`;
- `PROFESSIONAL_SCHEDULING`;
- `CLINICAL_CARE`;
- `CLINICAL_DOCUMENTATION`.

These identifiers represent stable domain-level commercial capability concepts.

They must not be external billing-provider product identifiers.

---

#### APPOINTMENT_MANAGEMENT

Normal `APPOINTMENT_MANAGEMENT` Entitlement is required for ordinary
professional Appointment operations that establish or modify professional
Appointment obligations.

This includes, where applicable:

- establishing a new Guardian-facing Appointment request (`SPEC-APT-001`),
  because accepting a new request commits the Organization to new
  Appointment-management activity even though the acting User is a Guardian;
- confirming Appointment commitments;
- ordinary Appointment rescheduling that establishes another future commitment;
- a Clinic proposing an alternative time for a requested Appointment
  (`SPEC-APT-018`);
- normal professional Appointment lifecycle management.

A Guardian changing an existing request — by rescheduling it (`SPEC-APT-004`)
or by accepting a Clinic alternative time (`SPEC-APT-019`) — establishes no
confirmed commitment and is not gated by this Entitlement; the Organization's
Entitlement is evaluated when it confirms the request.

Safe resolution of existing Appointments after Entitlement loss remains
governed by `SPEC-SUB-004`.

---

#### PROFESSIONAL_SCHEDULING

Normal `PROFESSIONAL_SCHEDULING` Entitlement is required for ordinary
professional scheduling operations such as:

- creating or modifying Clinic bookable availability;
- creating or modifying Veterinarian availability;
- changing a Clinic's current scheduling timezone while the Clinic has
  currently effective Clinic or Veterinarian Appointment Availability, because
  that change prospectively alters the actual-time interpretation of that
  Availability (see `SPEC-APT-013` BR-56 for the exact definition of
  currently effective Availability and the ended-Assignment exclusion);
- assigning a Veterinarian to an Appointment;
- reassigning a Veterinarian;
- other supported new scheduling activity explicitly requiring professional
  Entitlement.

Read access required solely to understand and safely resolve an existing
obligation must not automatically be classified as new paid scheduling
activity.

---

#### CLINICAL_CARE

Normal `CLINICAL_CARE` Entitlement is required to establish a new Clinical
Encounter and initiate a new normal paid professional care episode.

It does not replace:

- professional qualification;
- Clinic Assignment;
- Organization capability;
- Care Authorization;
- Medical Access Control.

---

#### CLINICAL_DOCUMENTATION

Normal `CLINICAL_DOCUMENTATION` Entitlement applies to ordinary creation,
editing, finalization, and attachment management of professional clinical
information where the operation forms part of normal new paid professional
activity.

Loss of normal Entitlement must not prevent the minimum documentation required
to preserve accurate medical history for care that was already validly
provided.

A Clinical Amendment to an existing finalized Clinical Record Entry
(`SPEC-MED-004`) does not require current commercial Entitlement: commercial
loss must not prevent a necessary correction to existing finalized clinical
history (`SPEC-SUB-004` BR-20). Every professional authorization and current
Veterinarian context that `SPEC-MED-004` requires still applies, and this never
makes a new Clinical Encounter or any other new clinical activity available.

That safe-continuity behavior is governed by `SPEC-SUB-004`.

---

### BR-26 — Historical read access is not automatically a normal paid operation

The ability to preserve or retrieve historical information must not be
classified blindly as an ordinary paid professional capability.

Historical access may be required for:

- continuity of care;
- legal or retention obligations;
- auditing;
- safe resolution of existing obligations.

`SPEC-SUB-004` defines behavior when normal Entitlements are lost.

---

### BR-27 — Safe resolution operations may differ from normal professional operations

An Organization without normal professional Entitlements may still need to
perform controlled operations required to safely resolve existing obligations.

Examples may eventually include:

- cancelling an existing Appointment;
- communicating an Appointment cancellation;
- safely concluding already-started care;
- preserving required clinical documentation.

Such behavior must be explicitly defined.

Entitlement loss must not force unsafe or historically destructive behavior.

---

### BR-28 — New professional activity and existing obligations are distinct

Entitlement evaluation must be capable of distinguishing:

    starting new paid professional activity

from:

    safely resolving activity that already exists

This distinction is defined in detail by `SPEC-SUB-004`.

---

### BR-29 — Entitlement is evaluated at operation time

A professional capability requiring Entitlement must evaluate current
commercial eligibility when the protected operation is performed.

A previous successful Entitlement check must not create permanent authorization
for unrelated future operations.

---

### BR-30 — Existing historical operation does not prove current Entitlement

The fact that an Organization previously:

- confirmed Appointments;
- assigned Veterinarians;
- created Clinical Encounters;
- finalized medical records;

must not prove that it currently has the Entitlement to perform new equivalent
operations.

Historical validity and current Entitlement are distinct.

---

### BR-31 — Entitlement evaluation must use the relevant Organization

Where a User belongs to multiple Veterinary Organizations, the Entitlement
decision must apply to the Organization context of the requested professional
operation.

For example:

    Dr. Garcia

    Animalia → Entitled
    VetCare  → Not entitled

An Animalia Entitlement must not authorize a VetCare professional operation.

---

### BR-32 — Entitlement at one Organization does not transfer to another

Professional Entitlements must not be shared merely because:

- the same User belongs to both Organizations;
- the same Veterinarian practices at both;
- the same Owner controls both.

Each Veterinary Organization has its own commercial context.

---

### BR-33 — Entitlement must use the Clinic's Organization context

For Clinic-specific operations, the required Organization Entitlement must be
evaluated against the Veterinary Organization that operates the target Clinic.

The acting User's other Organization memberships are irrelevant to that
commercial decision.

---

### BR-34 — Entitlement evaluation does not alter Subscription state

Checking whether a capability is entitled must not itself:

- activate a Subscription;
- cancel a Subscription;
- expire a Subscription;
- modify commercial history.

Entitlement evaluation is a decision based on commercial state.

---

### BR-35 — Entitlement evaluation should be explainable

When a paid professional capability is denied because of commercial
Entitlement, the system should be capable of distinguishing that reason from
other authorization failures.

For example:

    denied because Organization lacks Entitlement

must remain distinguishable from:

    denied because User lacks Clinic capability

or:

    denied because Pet Care Authorization is absent

This distinction supports correct product behavior, auditing, and support.

---

### BR-36 — Entitlement denial must not falsely reveal protected domain information

Although entitlement decisions should be explainable to appropriately
authorized actors, error behavior must not expose protected medical or
Organization information to unrelated Users.

---

### BR-37 — Phase 1 uses normalized professional Entitlement identifiers

Phase 1 uses the following normalized professional Entitlement identifiers:

- `APPOINTMENT_MANAGEMENT`;
- `PROFESSIONAL_SCHEDULING`;
- `CLINICAL_CARE`;
- `CLINICAL_DOCUMENTATION`.

Domain operations must evaluate the applicable Entitlement rather than relying
on an external Subscription product identifier.

A future approved commercial model may map different products or plans to
different Entitlement sets without changing these established domain
operations.

---

### BR-38 — External billing product identifiers must not become domain capabilities

An external commercial provider may represent purchased products using
provider-specific identifiers.

Those identifiers must not directly define domain authorization behavior.

The architecture must map trusted commercial information into the platform's
own Entitlement model.

---

### BR-39 — Future plan levels may map differently to Entitlements

Phase 1 may have a single professional commercial offering.

The Entitlement model must nevertheless allow future Subscription plans to
grant different capability sets without redefining established domain
operations.

This supports future `REQ-SUB-005` and `REQ-SUB-006` behavior without
implementing those plans now.

---

### BR-40 — Entitlement decisions must be atomic with the protected operation where required

A protected professional operation must not proceed based on an Entitlement
decision that can become incoherent before the operation is committed.

The exact transaction or consistency mechanism is architectural.

The domain requirement is that the operation must not complete under a
commercial condition that fails its required Entitlement check.

---

### BR-41 — Phase 1 does not make every Organization operation paid

Unless another approved Specification explicitly states otherwise, normal
professional Entitlement is not itself required for:

- authentication;
- User profile management;
- Organization Membership administration;
- Organization responsibility administration;
- Guardianship;
- Guardian medical-history access;
- Care Authorization management;
- historical-data preservation;
- Subscription-management operations;
- operations required to recover or manage the Organization's own commercial
  state.

These operations remain subject to their own domain authorization rules.

---

### BR-42 — Clinic publication is not a paid Phase 1 capability

Phase 1 does not require a professional Entitlement merely to preserve or
publish a Clinic's public identity.

Clinic publication and Discovery remain distinct from paid professional
Appointment, scheduling, and clinical capabilities.

A future approved commercial policy may change publication eligibility without
redefining Clinic identity or historical provenance.

---

## 5. Entitlement Decision

A professional Entitlement decision conceptually contains:

### Required

- Veterinary Organization;
- requested professional capability;
- current trusted commercial context;
- decision:
  - entitled;
  - not entitled.

### Useful decision context

- Subscription identity;
- Subscription state;
- applicable commercial validity period;
- reason for the Entitlement decision.

The Entitlement decision need not become a permanent domain entity for every
operation.

The persistence and caching strategy is architectural.

---

## 6. Scenarios

### Scenario: Active Subscription provides required Entitlement

Given Animalia Veterinary Group has an `ACTIVE` Organization Subscription
And `APPOINTMENT_MANAGEMENT` is a paid professional capability

When Animalia's Entitlement for `APPOINTMENT_MANAGEMENT` is evaluated

Then Animalia may satisfy the commercial requirement for that capability
And individual User authorization must still be evaluated separately

---

### Scenario: Entitled Organization Member still lacks User authorization

Given Animalia has the required Appointment-management Entitlement
And Maria is an Organization Member
And Maria does not have the applicable Appointment-management responsibility

When Maria attempts the professional operation

Then the operation is denied
And Organization Entitlement does not replace User authorization

---

### Scenario: Authorized User cannot bypass missing Entitlement

Given Carlos has the Organization responsibility required to manage
Appointments at Animalia Madrid Centro
And Animalia does not currently have the required Appointment-management
Entitlement

When Carlos attempts a normal paid Appointment-management operation

Then the operation is denied
And Carlos's Organization responsibility does not replace commercial
Entitlement

---

### Scenario: Pending Subscription does not grant normal capability

Given Animalia has a `PENDING` Subscription

When a paid professional capability is evaluated

Then the pending Subscription does not provide normal Entitlement
And Subscription initiation alone is insufficient

---

### Scenario: Cancelled Subscription remains entitled until paid period ends

Given Animalia's Subscription is `CANCELLED`
And the current commercial period remains valid until 2026-09-30

When an applicable paid professional capability is evaluated on 2026-09-20

Then the commercial condition may still satisfy the Entitlement policy
And cancellation alone does not imply immediate loss of access

---

### Scenario: Cancelled Subscription loses normal Entitlement after validity ends

Given Animalia's Subscription was cancelled
And its paid commercial validity has now ended
And the Subscription is `EXPIRED`

When a normal paid professional capability is evaluated

Then Animalia does not have the normal Entitlement for that capability

---

### Scenario: Past-due Subscription loses normal professional Entitlement

Given Animalia's Subscription is `PAST_DUE`

When a normal Phase 1 paid professional capability is evaluated

Then Animalia does not have the normal professional Entitlement for that
capability
And no implicit Phase 1 grace period enables new paid activity
And historical domain information remains intact
And safe resolution of existing obligations follows `SPEC-SUB-004`

---

### Scenario: Past-due Subscription later recovers

Given Animalia's Subscription was `PAST_DUE`
And normal professional Entitlements were unavailable during that period
And the Subscription later becomes effectively `ACTIVE`

When a normal paid professional capability is evaluated after recovery

Then the applicable normal Entitlement may again be available
And the historical `PAST_DUE` period remains preserved
And previous denied or resolved operations are not rewritten retroactively

---

### Scenario: Expired Subscription does not delete historical Appointment

Given Animalia has an existing Appointment
And its Subscription is `EXPIRED`
And Animalia lacks normal Appointment-management Entitlement

When the Appointment is evaluated

Then the Appointment still exists
And the lack of Entitlement does not delete its history
And allowed resolution behavior follows `SPEC-SUB-004`

---

### Scenario: Expired Subscription does not delete medical history

Given Animalia previously finalized Clinical Record Entries for Luna
And Animalia's Subscription later becomes `EXPIRED`

When Luna's medical history is evaluated

Then the historical Animalia Entries remain intact
And their provenance remains unchanged
And lack of current professional Entitlement does not destroy the records

---

### Scenario: Subscription Entitlement does not grant medical access

Given Animalia has an `ACTIVE` Subscription
And Animalia has the relevant professional SaaS Entitlement
And no applicable Care Authorization exists for Luna

When Dr. Garcia attempts to view Luna's protected medical history

Then access is denied
And paid Entitlement does not substitute for Pet-specific medical
authorization

---

### Scenario: Care Authorization does not bypass missing commercial Entitlement

Given Luna has a valid Care Authorization for Animalia Madrid Centro
And Animalia lacks the Entitlement required to start a new paid professional
care operation

When the relevant new professional operation is attempted

Then Care Authorization alone does not grant the paid capability
And the Entitlement requirement remains unsatisfied

---

### Scenario: Entitlement is Organization-specific

Given Dr. Garcia belongs to Animalia Veterinary Group
And Dr. Garcia also belongs to VetCare Group
And Animalia currently has the required professional Entitlement
And VetCare does not

When Dr. Garcia performs an Animalia operation

Then Animalia's Entitlement may satisfy the commercial requirement

When Dr. Garcia performs an equivalent VetCare operation

Then Animalia's Entitlement is insufficient
And VetCare's own commercial context must be evaluated

---

### Scenario: Clinic operation uses Clinic's Organization Entitlement

Given Animalia Madrid Centro belongs to Animalia Veterinary Group
And Carlos also belongs to another entitled Organization
And Animalia lacks the required Entitlement

When Carlos attempts the paid operation at Animalia Madrid Centro

Then the other Organization's Entitlement is irrelevant
And Animalia Veterinary Group must satisfy the commercial requirement

---

### Scenario: Historical successful use does not imply current Entitlement

Given Animalia previously had an `ACTIVE` Subscription
And previously used Appointment-management capabilities
And Animalia's current Subscription is now `EXPIRED`

When a new paid Appointment-management operation is attempted

Then the historical successful operations do not prove current Entitlement
And current commercial state is evaluated

---

### Scenario: Client claims Entitlement without trusted commercial basis

Given Animalia lacks the required trusted commercial Entitlement
And a manipulated client reports that the capability is enabled

When the protected operation is evaluated

Then the client assertion is insufficient
And the paid operation is denied

---

### Scenario: Entitlement denial does not end Membership

Given Maria has an active Organization Membership in Animalia
And Animalia lacks normal professional Entitlement

When the Entitlement decision is denied

Then Maria's Organization Membership remains unchanged

---

### Scenario: Entitlement denial does not end Clinic Assignment

Given Dr. Garcia has a valid Clinic Assignment at Animalia Madrid Centro
And Animalia lacks the Entitlement for a requested paid operation

When the operation is denied

Then Dr. Garcia's Clinic Assignment is not deleted or rewritten
And the professional relationship remains historically identifiable

---

### Scenario: Subscription loss does not remove Guardian capability

Given Dr. Garcia is a Veterinarian working through Animalia
And Dr. Garcia is also an active Guardian of Luna
And Animalia loses normal professional Entitlement

When Dr. Garcia exercises her independently authorized Guardian capability for
Luna

Then Animalia's Subscription state does not remove that Guardian capability
And Guardianship remains governed independently

---

### Scenario: Clinic publication is not blocked solely by missing Phase 1 professional Entitlement

Given Animalia Madrid Centro otherwise satisfies the applicable Clinic
publication requirements
And Animalia lacks normal professional Entitlement

When an authorized actor performs the Phase 1 Clinic publication workflow

Then missing `APPOINTMENT_MANAGEMENT`, `PROFESSIONAL_SCHEDULING`,
`CLINICAL_CARE`, or `CLINICAL_DOCUMENTATION` Entitlement is not by itself a
publication denial
And all ordinary Clinic publication rules still apply

---

## 7. Entitlement and Domain Authorization

A paid professional operation may require several independent conditions.

For example:

    Organization has professional Entitlement
                    +
    acting User has Appointment-management capability
                    +
    target Clinic belongs to Organization
                    +
    Appointment is in valid lifecycle state
                    ↓
    Appointment operation permitted

For clinical behavior:

    Organization has applicable professional Entitlement
                    +
    Veterinarian has valid professional Clinic context
                    +
    valid Pet Care Authorization
                    +
    applicable least-privilege rules
                    ↓
    new clinical operation permitted

Commercial Entitlement must remain one condition among several.

It must not collapse the authorization model into one global paid flag.

---

## 8. Normal Operations vs Existing Obligations

The platform must distinguish:

    normal new paid professional activity

from:

    safe handling of obligations or history that already exists

For example, Entitlement loss may prevent:

    creating new normal professional activity

while still requiring controlled ability to:

    resolve an existing Appointment
    preserve medical records
    conclude already-started care safely
    access required historical information
    preserve auditability

The detailed loss-of-Entitlement behavior is defined by `SPEC-SUB-004`.

---

## 9. Capability Evolution

The initial product may provide one Subscription offering that grants all normal
Phase 1 professional paid capabilities.

The domain must nevertheless avoid embedding commercial plan structure directly
into business entities.

Conceptually:

    commercial product
          ↓
    Entitlement mapping
          ↓
    domain capability

rather than:

    external billing product ID
          ↓
    hard-coded authorization everywhere

This allows future commercial plans to evolve without redefining core domain
behavior.

---

## 10. Edge Cases

### Commercial provider is temporarily unavailable

Temporary inability to contact an external commercial provider must not
automatically mean:

    Entitlement denied because Subscription expired

The architecture must use an explicit trusted synchronization and freshness
policy.

The system must distinguish:

    authoritative commercial invalidity

from:

    commercial provider temporarily unavailable

---

### Entitlement changes during a protected operation

A long-running professional workflow may begin while Entitlement is valid and
encounter a commercial-state change before completion.

The operation must not enter an unsafe or partially committed state.

The exact consistency strategy depends on the operation and is architectural.

Already-started clinical care is additionally governed by the safe-continuity
rules defined elsewhere.

---

### New capability introduced

A new professional capability must explicitly determine whether it requires a
commercial Entitlement.

It must not inherit paid or unpaid status accidentally merely because it is
implemented near another feature.

---

### Future free professional capability

The platform may eventually provide some professional capabilities without a
paid Subscription.

The Entitlement model must allow such operations to remain usable without
requiring fake commercial state.

---

### Multiple Subscription plans introduced later

Different plans may eventually map to different Entitlement sets.

The domain operation must ask:

    "Does this Organization have the required Entitlement?"

rather than:

    "Is this Organization on Plan X?"

This prevents commercial packaging from leaking throughout domain logic.

---

## 11. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-SUB-001 — Establish Organization Subscription
- SPEC-SUB-002 — Maintain Organization Subscription State
- SPEC-ORG-001 — Establish Veterinary Organization through Commercial Onboarding
- SPEC-ID-003 — Authenticate User

Domain operations requiring Entitlement may additionally depend on the
applicable Specifications for:

- Clinics;
- Appointments, including SPEC-APT-001 — Request Appointment;
- Veterinary Professionals;
- Medical Access Control;
- Medical Records.

Loss-of-Entitlement behavior is defined by:

- SPEC-SUB-004 — Handle Loss of Professional Entitlements

---

## 13. Out of Scope

This Specification does not define:

- future commercial grace-period behavior beyond Phase 1;
- billing retry strategy;
- external billing-provider selection;
- Subscription plan pricing;
- taxes;
- invoices;
- refunds;
- payment methods;
- multiple commercial plans;
- usage limits;
- exact technical Entitlement identifier format;
- Entitlement caching strategy;
- Subscription provider synchronization implementation;
- detailed behavior after Entitlement loss;
- billing notifications.

---

## 14. Verification Notes

Verification must demonstrate that:

1. professional Entitlements are evaluated for a Veterinary Organization;
2. Entitlement is capability-specific rather than one universal paid flag;
3. only explicitly paid capabilities require Entitlement;
4. Entitlement does not replace User or domain authorization;
5. User authorization does not bypass required Entitlement;
6. client-side state is not authoritative for Entitlement;
7. trusted commercial information drives Entitlement evaluation;
8. an effectively `ACTIVE` Subscription provides normal Phase 1 professional
   Entitlements;
9. `PENDING` does not provide normal paid Entitlements;
10. `EXPIRED` does not provide normal paid Entitlements;
11. `CANCELLED` may remain entitled while commercial validity continues;
12. `PAST_DUE` does not provide normal Phase 1 professional Entitlements and no
    implicit grace period permits new paid activity;
13. denied Entitlement does not delete Organizations, Memberships, Clinics,
    Appointments, Clinic Assignments, or medical history;
14. paid Entitlement does not grant Pet medical access;
15. Care Authorization does not bypass required commercial Entitlement;
16. Entitlements remain Organization-specific;
17. the Clinic's Organization determines the relevant commercial context;
18. historical successful operations do not prove current Entitlement;
19. Subscription state evaluation and Entitlement remain distinct;
20. loss of normal Entitlement remains distinguishable from safe resolution of
    existing obligations;
21. future commercial plans may map to capabilities without redefining domain
    operations;
22. protected operations evaluate current Entitlement through trusted
    infrastructure.
23. Phase 1 defines `APPOINTMENT_MANAGEMENT`, `PROFESSIONAL_SCHEDULING`,
    `CLINICAL_CARE`, and `CLINICAL_DOCUMENTATION` as normalized professional
    Entitlements;
24. normal Appointment-management operations evaluate
    `APPOINTMENT_MANAGEMENT` where applicable;
25. normal professional scheduling and Veterinarian Assignment operations
    evaluate `PROFESSIONAL_SCHEDULING` where applicable;
26. establishment of a new normal Clinical Encounter evaluates
    `CLINICAL_CARE`;
27. ordinary new clinical documentation evaluates `CLINICAL_DOCUMENTATION`
    where applicable;
28. safe completion of care and documentation already validly underway remains
    distinct from new paid professional activity;
29. personal Guardian capability is not removed by Organization Entitlement
    loss;
30. Phase 1 Clinic publication is not denied solely because these normal
    professional Entitlements are absent;
31. recovery from `PAST_DUE` to effective `ACTIVE` restores normal Entitlements
    prospectively;
32. Entitlement mapping remains independent from external billing-provider
    product identifiers.
33. a Clinical Amendment to an existing finalized Entry succeeds without
    current commercial Entitlement for an otherwise authorized current
    Veterinarian, while a new Clinical Encounter remains denied;
34. Guardian-facing and public reads never expose Subscription state,
    validity, or billing information.

---

## 15. Phase 1 commercial boundary toward Guardians and the public (Subscription Operational Safety)

- **Publication stays independent of Entitlement** (BR-23, BR-24, BR-42). Loss
  of normal Entitlement never unpublishes a Clinic automatically. A published
  Clinic remains publicly visible, profile-visible, location-visible, and
  eligible for Discovery under the existing publication semantics. Phase 1
  introduces no paid-publication gate.
- **Booking reflects unavailability without revealing why** (`SPEC-SUB-004`
  BR-5, `SPEC-APT-014` BR-4/BR-5). While the Clinic's Organization lacks
  `APPOINTMENT_MANAGEMENT`, requestable times and new Appointment requests stay
  unavailable. The privacy of the requestable-times read is preserved:
  - an empty requestable-times result is presented with one generic,
    reason-agnostic message ("No hay citas en línea disponibles para este
    periodo." / "There are no online appointment times available for this
    period."), identical whether the cause is missing Entitlement, no
    configured availability, no matching times, or any other reason the
    uniform empty outcome hides;
  - only when the Appointment request operation itself returns its
    unavailability outcome is the Guardian told that the Clinic is not
    currently accepting online appointment requests;
  - no new public or Guardian-facing signal of Subscription or Entitlement
    state is introduced.
- **No commercial detail reaches Guardians or the public.** Guardian-facing and
  public reads and copy never expose Subscription state, validity dates,
  billing information, or plan language.
- **Neutral professional copy.** Phase 1 has no plan model (REQ-SUB-005 is
  Later). Commercial denials shown to professionals describe current service
  or Subscription availability and never claim that a "current plan" excludes
  a capability. Subscription state itself is shown only through the
  authorized status read (`SPEC-SUB-002` §15).

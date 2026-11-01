# SPEC-SUB-004 — Handle Loss of Professional Entitlements

**Status:** APPROVED  
**Requirements:** REQ-SUB-003, REQ-SUB-004  
**Domain:** Subscription and Entitlements  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): BR-14–BR-18, BR-24, and BR-39 are replaced by SPEC-MED-010 BR-13: without the `CLINICAL_CARE` Entitlement no new Clinical Record Entry or Attachment may be recorded, even for an already documented Appointment, while reading and Amendments of existing Entries remain possible (BR-20, BR-21 unchanged). Encounter conclusion no longer exists. Assigning a Veterinarian to a `COMPLETED` Appointment requires no Entitlement (SPEC-APT-007 BR-34). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Define safe system behavior when a Veterinary Organization no longer has the
professional Entitlement required for normal paid platform operations.

Loss of professional Entitlement must prevent unauthorized continuation of new
paid professional activity without:

- deleting historical information;
- corrupting existing Appointments;
- abandoning already-started veterinary care;
- preventing required clinical documentation of care already provided;
- rewriting professional relationships;
- erasing audit or authorization history.

The platform must distinguish between:

- starting or continuing normal new paid professional activity;
- safely resolving obligations that already exist;
- preserving historical information.

---

## 2. Preconditions

- The Veterinary Organization exists.
- The requested operation belongs to that Organization context.
- The operation normally requires a professional Entitlement or is related to
  an existing obligation created while such Entitlement was available.
- The Organization's current Entitlement state can be evaluated through trusted
  infrastructure.
- The acting User satisfies any applicable non-commercial domain authorization
  required for the operation.

---

## 3. Business Rules

### BR-1 — Loss of Entitlement blocks normal new paid professional activity

When a Veterinary Organization no longer has the required professional
Entitlement, the system must deny new normal paid professional operations that
require that Entitlement.

Loss of Entitlement must not be bypassed through:

- Organization Membership;
- Organization ownership;
- Clinic Assignment;
- Veterinarian status;
- Pet Care Authorization;
- client-side state.

---

### BR-2 — Existing domain information is not deleted

Loss of professional Entitlement must not delete:

- Veterinary Organizations;
- Organization Memberships;
- Clinics;
- Veterinarian Professional Profiles;
- Clinic Assignments;
- Appointments;
- Care Authorizations;
- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- Medical Access Audit Events.

Commercial access and domain existence are separate concerns.

---

### BR-3 — Historical medical information remains durable

Loss or termination of professional Entitlement must not delete or
destructively rewrite historical medical information.

Historical clinical provenance must remain intact.

---

### BR-4 — Historical professional relationships remain preserved

Loss of Entitlement must not end or rewrite historical:

- Organization Membership periods;
- Clinic Assignment periods;
- Appointment professional Assignment history;
- clinical authorship;
- provider provenance.

Commercial validity and historical professional truth remain separate.

---

### BR-5 — New Appointment intake requiring paid professional operation is blocked

Where normal Appointment intake or management requires professional
Entitlement, an Organization without that Entitlement must not continue
accepting new paid professional Appointment activity through the platform.

The exact user-facing availability of booking must reflect that current
professional capability is unavailable.

---

### BR-6 — Existing Appointment requests are not deleted

Appointment requests that already exist when Entitlement is lost must remain
identifiable.

The Clinic must not erase them merely because normal Appointment-management
Entitlement is no longer available.

They require an explicit resolution.

---

### BR-7 — Existing requested Appointments may be safely declined or cancelled

An authorized Clinic actor may perform the minimum operation required to
resolve an existing `REQUESTED` Appointment after loss of normal Entitlement.

This may include declining or cancelling the existing request where supported
by the applicable Appointment lifecycle.

The operation must not be treated as permission to continue normal new
scheduling activity.

---

### BR-8 — Existing confirmed Appointments are not silently cancelled

Loss of Entitlement must not automatically change all existing `CONFIRMED`
Appointments to `CANCELLED`.

Each Appointment remains a real existing obligation until resolved through an
explicit applicable workflow.

---

### BR-9 — Existing confirmed Appointments may be safely cancelled

An authorized Clinic actor must remain able to cancel an existing confirmed
Appointment when cancellation is required to safely resolve the Organization's
existing obligation.

The ability to cancel does not imply entitlement to create a replacement
Appointment or continue normal scheduling.

---

### BR-10 — Loss of Entitlement does not silently reschedule Appointments

The system must not automatically move Appointment dates or assign alternative
times merely because commercial Entitlement is lost.

Any permitted scheduling resolution must remain explicit.

---

### BR-11 — Normal new Appointment confirmation may be denied

Where Appointment confirmation is a paid professional capability, an
Organization without the applicable Entitlement must not normally confirm a new
Appointment commitment.

A previously requested Appointment may instead require safe rejection or
cancellation.

---

### BR-12 — Normal new Veterinarian Assignment may be denied

An Organization without the applicable professional Entitlement must not
normally establish new Appointment Veterinarian Assignments or reassignments
when those are paid professional scheduling operations.

Existing professional Assignment history remains intact.

---

### BR-13 — Loss of Entitlement does not remove existing Appointment Assignment history

Existing current or historical Appointment Veterinarian Assignments must not be
deleted merely because the Organization loses commercial Entitlement.

Whether an unresolved future Appointment can still proceed is determined by the
applicable safe-resolution policy.

---

### BR-14 — New Clinical Encounters requiring paid professional Entitlement are blocked

An Organization without the applicable professional Entitlement must not start
a new normal Clinical Encounter through the platform when creation of that
Encounter requires paid professional capability.

A valid Care Authorization alone is insufficient to bypass missing commercial
Entitlement.

---

### BR-15 — Already-started Clinical Encounter must not be abandoned unsafely

If a valid Clinical Encounter began while the Organization had the required
professional Entitlement, later loss of that Entitlement must not require
unsafe abandonment of veterinary care already underway.

The system must permit the minimum operations required to safely conclude that
existing care context.

---

### BR-16 — Safe active-care continuity is limited to the existing Encounter

Post-Entitlement-loss continuity for veterinary care must apply only to the
Clinical Encounter that was already underway.

It must not authorize:

- unrelated new Clinical Encounters;
- unrelated Pets;
- new normal paid care episodes;
- unrestricted professional activity.

---

### BR-17 — Required documentation of already-provided care may continue

Loss of Entitlement must not prevent authorized veterinary professionals from
documenting care that was already validly provided within an existing Clinical
Encounter when that documentation is required to preserve safe and accurate
medical history.

This may include, where applicable:

- completing an existing Draft;
- creating necessary clinical documentation for care already delivered;
- finalizing clinically required Entries.

This continuity must not become permission to document unrelated new care.

---

### BR-18 — Required documentation may continue after the physical care activity ends

An Encounter may finish clinically before all required documentation has been
finalized.

Loss of Entitlement must not force clinically required documentation to remain
permanently incomplete solely because commercial eligibility ended during the
existing care episode.

The professional must still satisfy the applicable clinical authorization and
authorship rules.

---

### BR-19 — Entitlement continuity does not preserve former professional authority

Safe documentation continuity must not allow a User who has independently lost
their professional authorization to continue acting merely because the
Organization previously had Entitlement.

For example, loss of a Veterinarian's Clinic Assignment remains independently
significant.

Commercial continuity and professional authorization are separate conditions.

---

### BR-20 — Clinical Amendments to existing finalized history remain possible

Commercial loss must not prevent a necessary correction to existing finalized
clinical history. In Phase 1, creating a Clinical Amendment to an existing
finalized Clinical Record Entry (`SPEC-MED-004`) therefore does not require
current commercial Entitlement.

The Amendment must still satisfy all applicable Medical Records and
authorization rules, including the current Veterinarian professional context
at the Entry's Clinic that `SPEC-MED-004` requires. It remains append-only and
keeps its idempotency.

This limited correction capability must not grant new unrelated clinical
activity: it never makes a new Clinical Encounter available.

---

### BR-21 — Historical information remains available according to applicable access rules

Loss of Entitlement must not itself make historical medical information cease
to exist.

Access to that information remains governed by:

- Guardianship;
- Medical Access Control;
- provider context;
- least privilege;
- any applicable historical-access policy.

This Specification does not create unrestricted professional history access
after Subscription termination.

---

### BR-22 — Entitlement loss does not create medical access

An Organization without normal professional Entitlement does not gain any new
medical-access rights through safe-resolution behavior.

Care Authorization and other Medical Access Control rules remain independently
required.

---

### BR-23 — Existing Care Authorization is not deleted

Loss of professional Entitlement must not delete or rewrite a Pet Care
Authorization.

However, a Care Authorization does not bypass missing Entitlement for starting
new paid professional activity.

---

### BR-24 — Active-care access continuity remains least-privileged

Where existing clinical care may continue after Entitlement loss, medical
access must be limited to what is required to safely conclude and document that
already-started care.

Loss of Entitlement must not become a reason to broaden access.

---

### BR-25 — Public Clinic identity remains historically preserved

Loss of Entitlement must not delete the Clinic domain identity or historical
clinical attribution.

Historical references to the Clinic must remain valid.

---

### BR-26 — Public Clinic publication policy is separate from historical identity

The Organization's loss of Entitlement may affect whether a Clinic remains
eligible for ongoing public Discovery or new booking.

That commercial publication policy must not delete:

- the Clinic;
- its historical profile identity;
- historical Appointments;
- historical clinical provenance.

---

### BR-27 — Safe resolution capability must not become normal operation

The system must distinguish operations allowed solely to resolve existing
obligations from ordinary professional operations.

For example:

    cancel existing Appointment
    → may be permitted

does not imply:

    create new Appointment
    → permitted

and:

    finalize required documentation for existing Encounter
    → may be permitted

does not imply:

    create unrelated new Encounter
    → permitted

---

### BR-28 — Existing obligations must remain identifiable

The system must be capable of determining which operations relate to activity
that already existed before Entitlement loss.

A User must not be able to falsely classify a new professional operation as
safe resolution of an old obligation.

---

### BR-29 — Entitlement loss timing matters

The system must preserve enough information to determine whether an applicable
professional activity:

- began while Entitlement was valid;
- was attempted after Entitlement was lost.

This distinction is required for safe-continuity decisions.

---

### BR-30 — Historical Entitlement does not authorize future unrelated operations

The fact that an Organization had valid Entitlement when a previous
Appointment, Encounter, or Clinical Record was created must not provide
permanent commercial authorization for later unrelated activity.

---

### BR-31 — Recovery of Entitlement restores normal capabilities prospectively

If the Organization later regains the applicable professional Entitlement,
normal paid professional capabilities may again become available according to
the current domain authorization rules.

Recovery must not rewrite the historical period during which Entitlement was
absent.

---

### BR-32 — Restored Entitlement does not automatically recreate cancelled obligations

When Entitlement returns, previously cancelled Appointments or otherwise
resolved obligations must not automatically become active again.

New activity requires normal explicit workflows.

---

### BR-33 — Entitlement loss does not erase auditability

Medical Access Audit Events and other required security-relevant history must
remain intact after Entitlement loss.

Safe-resolution operations may themselves be auditable where required.

---

### BR-34 — Commercial denial and domain denial remain distinguishable

The system should be capable of distinguishing:

- operation denied because professional Entitlement is absent;
- operation denied because User authorization is absent;
- operation denied because medical authorization is absent;
- operation denied because domain lifecycle state is invalid.

This distinction supports correct operational and support behavior.

---

### BR-35 — Client-side capability visibility is not the security boundary

The application may hide or disable unavailable professional capabilities in
the UI.

However, trusted backend infrastructure must independently enforce Entitlement
loss.

A manipulated client must not continue normal paid operations.

---

### BR-36 — Loss-of-Entitlement behavior must preserve domain consistency

A protected operation denied because of missing Entitlement must not leave:

- partial Appointments;
- partial professional Assignments;
- partial Clinical Encounters;
- partially finalized clinical records;
- contradictory current state.

---

### BR-37 — PAST_DUE is Phase 1 loss of normal professional Entitlement

For Phase 1, an authoritative Subscription state of `PAST_DUE` means that the
Organization does not have normal professional Entitlement for new paid
professional activity.

The safe-resolution rules in this Specification apply from that loss point.

`PAST_DUE` must not be treated as an implicit unrestricted grace period.

---

### BR-38 — Safe Appointment resolution must not create another future commitment

After Entitlement loss, safe resolution of an existing Appointment may not be
used to:

- confirm another new Appointment commitment;
- reschedule the Appointment into a new future paid commitment;
- create a replacement Appointment;
- assign a Veterinarian through ordinary professional scheduling;
- reassign a Veterinarian through ordinary professional scheduling.

Where cancellation or another terminal resolution is permitted by the
Appointment lifecycle, only the minimum applicable resolution operation remains
available.

---

### BR-39 — Safe clinical continuity includes explicit Encounter conclusion

Where a Clinical Encounter validly began before Entitlement loss, an otherwise
authorized professional may perform the minimum operations required to
conclude that Encounter according to `SPEC-MED-008`.

Conclusion does not authorize creation of another Clinical Encounter.

---

### BR-40 — Existing care attachments may be completed where required

Where protected Clinical Attachments genuinely belong to care already validly
provided before Entitlement loss, otherwise authorized professionals may
complete the minimum supported attachment workflow required to preserve that
care episode.

This must not permit unrelated new clinical activity or unrelated file access.

Applicable Clinical Attachment authorization and validation rules continue to
apply.

---

### BR-41 — Recovery from PAST_DUE is prospective

When a `PAST_DUE` Subscription later becomes effectively `ACTIVE`, normal
professional Entitlements may become available again.

Recovery does not:

- erase the historical `PAST_DUE` period;
- reactivate cancelled Appointments;
- undo terminal Appointment outcomes;
- reopen concluded Clinical Encounters;
- retroactively authorize operations that were denied while Entitlement was
  absent.

---

## 4. Operation Classification

After professional Entitlement is lost, operations should conceptually be
classified into three groups.

### Normal new paid activity

Examples may include:

- accepting new normal Appointment activity;
- confirming new Appointment commitments;
- assigning or reassigning Veterinarians for new scheduling activity;
- starting new normal Clinical Encounters;
- starting unrelated new paid clinical workflows.

These operations require the applicable current professional Entitlement.

### Safe resolution of existing obligations

Examples may include:

- cancelling an existing requested or confirmed Appointment;
- safely concluding an already-started Clinical Encounter;
- completing required clinical documentation for care already provided;
- preserving clinically necessary correction of historical information where
  permitted.

These operations may remain available only to the minimum extent required to
resolve the existing obligation safely and consistently.

### Historical preservation and authorized read behavior

Examples include:

- retaining historical Appointments;
- retaining finalized medical history;
- retaining Clinical Attachments;
- retaining Medical Access Audit Events;
- authorized Guardian access to medical history.

Historical preservation does not depend on normal professional Entitlement.

Professional read access remains subject to its applicable Medical Access
Control rules.

---

## 5. Scenarios

### Scenario: Expired Organization cannot start new normal Appointment activity

Given Animalia Veterinary Group no longer has the required professional
Entitlement
And normal Appointment intake requires that Entitlement

When a new paid Appointment-management operation is attempted for Animalia

Then the normal professional operation is denied
And no false Appointment commitment is created

---

### Scenario: Existing requested Appointment survives Entitlement loss

Given Luna already has a `REQUESTED` Appointment at Animalia Madrid Centro
And Animalia later loses normal Appointment-management Entitlement

When the Appointment is evaluated

Then the Appointment remains identifiable
And it is not silently deleted
And it requires an explicit safe resolution

---

### Scenario: Existing requested Appointment may be cancelled

Given Luna has an existing `REQUESTED` Appointment
And Animalia has lost normal professional Entitlement
And Carlos remains authorized to resolve Appointments at that Clinic

When Carlos cancels the existing request through the permitted safe-resolution
workflow

Then the Appointment becomes cancelled according to its lifecycle
And the cancellation remains historical
And Carlos does not gain permission to create new paid Appointment activity

---

### Scenario: Existing confirmed Appointment is not automatically cancelled

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro
And Animalia loses normal professional Entitlement

When the Entitlement change occurs

Then Luna's Appointment remains `CONFIRMED`
And the Appointment is not silently deleted or cancelled
And the Clinic must resolve the existing obligation explicitly

---

### Scenario: Existing confirmed Appointment may be safely cancelled

Given Luna has an existing `CONFIRMED` Appointment
And Animalia no longer has normal Appointment-management Entitlement
And Carlos remains authorized to cancel existing Appointments

When Carlos cancels Luna's Appointment

Then the Appointment becomes `CANCELLED`
And its historical information remains intact
And the cancellation does not create Entitlement for new scheduling activity

---

### Scenario: Missing Entitlement prevents new Veterinarian Assignment

Given Luna has a future Appointment without a Veterinarian Assignment
And Animalia lacks the Entitlement required for normal professional scheduling

When Carlos attempts to assign Dr. Garcia through the normal scheduling
workflow

Then the operation is denied
And missing Entitlement is not bypassed by Carlos's Organization authority

---

### Scenario: Existing Veterinarian Assignment history remains intact

Given Dr. Garcia was assigned to Luna's Appointment while Animalia was entitled
And Animalia later loses professional Entitlement

When Appointment history is evaluated

Then Dr. Garcia's Assignment history remains identifiable
And Entitlement loss does not erase the professional scheduling history

---

### Scenario: New Clinical Encounter is denied after Entitlement loss

Given Luna has a valid Care Authorization for Animalia Madrid Centro
And Dr. Garcia has a valid Clinic Assignment
And Animalia lacks the Entitlement required to start new normal clinical care

When Dr. Garcia attempts to establish a new Clinical Encounter

Then the operation is denied
And Care Authorization does not bypass missing professional Entitlement

---

### Scenario: Already-started Clinical Encounter may continue safely

Given Luna has a Clinical Encounter already underway
And the Encounter validly began while Animalia had the required Entitlement
And Animalia then loses that Entitlement during care

When Dr. Garcia continues the already-started care

Then the system does not require unsafe abandonment
And only operations necessary to safely conclude the existing Encounter remain
eligible under the continuity rules
And no unrelated new care episode is authorized

---

### Scenario: Existing care may still be documented

Given Dr. Garcia validly provided care to Luna before Animalia lost Entitlement
And Luna's Clinical Encounter requires clinical documentation
And Dr. Garcia remains professionally authorized for the applicable care
context

When Dr. Garcia documents the care already provided

Then clinically required documentation may continue
And the resulting history remains attributable to the original care context
And the operation does not authorize unrelated new clinical activity

---

### Scenario: Existing Draft may be completed after Entitlement loss

Given Luna has a Draft Clinical Record Entry created during a valid Clinical
Encounter
And Animalia later loses normal professional Entitlement
And the Draft documents care already provided
And Dr. Lopez remains authorized within the applicable clinical context

When Dr. Lopez completes and finalizes the required clinical documentation

Then the Entry may become finalized according to the Medical Records rules
And original creator and contributor provenance remain preserved
And Entitlement loss does not force the clinical history to remain incomplete

---

### Scenario: Entitlement loss does not allow former Veterinarian to continue editing

Given Dr. Garcia created Luna's Draft Clinical Record Entry
And Animalia later loses Entitlement
And Dr. Garcia also independently loses her Clinic Assignment

When Dr. Garcia attempts to continue editing solely because safe documentation
continuity exists

Then the operation is denied
And loss-of-Entitlement continuity does not restore missing professional
authorization

---

### Scenario: Clinically necessary Amendment may remain possible

Given Animalia previously finalized a Clinical Record Entry for Luna
And a clinically significant documentation error is later discovered
And Animalia currently lacks normal professional Entitlement
And Dr. Lopez remains otherwise authorized to perform the provider's applicable
historical correction workflow

When Dr. Lopez creates the required Clinical Amendment

Then the correction may be permitted where the historical-integrity policy
allows it
And the original Finalized Entry remains unchanged
And no unrelated new clinical activity is enabled

---

### Scenario: Historical medical history survives Entitlement loss

Given Animalia previously contributed finalized clinical information to Luna's
medical history
And Animalia later loses all normal professional Entitlements

When Luna's longitudinal history is viewed by an authorized User

Then the historical Animalia contribution remains present
And its Clinic, Organization, and professional provenance remain unchanged

---

### Scenario: Guardian access is not removed by Clinic Subscription loss

Given Maria has an active Guardianship relationship with Luna
And Luna has finalized medical history from Animalia
And Animalia's Subscription later expires

When Maria views Luna's medical history

Then Animalia's historical clinical contribution remains available according
to Maria's Guardian access rules
And Animalia's commercial state does not erase Luna's history

---

### Scenario: Care Authorization survives as domain history

Given Luna has a Care Authorization for Animalia Madrid Centro
And Animalia loses professional Entitlement

When the Care Authorization is evaluated

Then the authorization is not deleted solely because of Entitlement loss
And the authorization does not bypass missing Entitlement for new paid activity

---

### Scenario: Another Organization's Entitlement is irrelevant

Given Dr. Garcia belongs to Animalia and VetCare
And Animalia lacks the required Entitlement
And VetCare is fully entitled

When Dr. Garcia attempts a paid professional operation at Animalia Madrid
Centro

Then VetCare's Entitlement does not authorize the Animalia operation

---

### Scenario: Entitlement later recovers

Given Animalia previously lost normal professional Entitlement
And some existing obligations were safely resolved
And Animalia later regains the required Entitlement

When a new normal professional operation is attempted

Then the current recovered Entitlement may satisfy the commercial requirement
And previously cancelled Appointments are not automatically restored
And the historical non-entitled period remains meaningful

---

### Scenario: Manipulated client attempts operation after Entitlement loss

Given Animalia lacks the required professional Entitlement
And a manipulated client displays normal professional controls as enabled

When the client attempts a protected paid operation

Then trusted backend enforcement denies the operation
And UI state does not bypass Entitlement enforcement

---

## 6. Existing Appointment Resolution

Loss of normal professional Entitlement does not erase Appointment obligations.

Conceptually:

    Existing Appointment
           ↓
    Entitlement lost
           ↓
    preserve Appointment
           ↓
    allow minimum safe resolution
           ↓
    historical lifecycle remains intact

Safe resolution does not imply permission to create replacement professional
activity.

---

## 7. Existing Clinical Care Resolution

Already-started veterinary care requires stronger continuity guarantees than
ordinary scheduling activity.

Conceptually:

    Clinical Encounter begins validly
              ↓
    Entitlement lost
              ↓
    do not abandon care unsafely
              ↓
    minimum access and professional operations
    required to conclude existing care
              ↓
    complete required documentation
              ↓
    no new unrelated care episode

Commercial failure must not corrupt the medical record of care already
provided.

---

## 8. Historical Durability

The following truths survive professional Entitlement loss:

    Luna was treated by Dr. Garcia
    at Animalia Madrid Centro
    on 2026-09-10

    Luna had Appointment A

    Dr. Garcia practiced at Animalia during period X

    Care Authorization A existed

    Medical Access Audit Event B occurred

Commercial state may change what the Organization can do now.

It must not rewrite what happened previously.

---

## 9. Edge Cases

### Entitlement is lost while Appointment operation is being committed

A protected operation must not reach an inconsistent partial state.

The architecture must define an appropriate consistency boundary between
Entitlement evaluation and the committed domain operation.

---

### Entitlement is lost during surgery or other active procedure

The platform must not require unsafe termination of care already underway.

Only the minimum capabilities required for safe completion and documentation
of that existing Encounter may continue.

---

### Clinical documentation remains unfinished for several professionals

More than one authorized professional may have contributed to an existing
Encounter.

Safe documentation continuity may allow currently authorized professionals to
complete clinically required documentation while preserving original
authorship and contribution history.

---

### Organization chooses not to renew

Intentional non-renewal and payment failure may both eventually produce loss of
normal Entitlement.

Historical durability and safe-resolution guarantees apply regardless of the
commercial reason for Entitlement loss.

---

### Entitlement returns before existing Appointment is resolved

Recovery of current Entitlement may restore normal capabilities.

The existing Appointment remains in whichever lifecycle state it actually
reached.

The system must not pretend the Entitlement-loss period never occurred.

---

### Professional access to own historical provider records

Loss of normal Entitlement does not automatically define whether a provider may
access all historical information it previously created.

Such access must follow the applicable Medical Access Control, retention, and
provider-history policy.

This Specification guarantees preservation, not unrestricted post-Subscription
access.

---

### Clinic remains publicly discoverable after Entitlement loss

Whether an unpaid Clinic remains publicly discoverable is a commercial product
policy separate from historical preservation.

If current publication requires Entitlement, Discovery eligibility may be
removed without deleting the Clinic or its historical information.

---

## 10. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-SUB-001 — Establish Organization Subscription
- SPEC-SUB-002 — Maintain Organization Subscription State
- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-APT-003 — Cancel Appointment
- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-004 — Amend Finalized Clinical Record Entry
- SPEC-MED-007 — Manage Clinical Attachments
- SPEC-MED-008 — Conclude Clinical Encounter
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke or End Pet Care Authorization
- SPEC-ID-003 — Authenticate User

Existing professional relationships may additionally depend on:

- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment

---

## 12. Out of Scope

This Specification does not define:

- Subscription pricing;
- future commercial grace-period behavior beyond Phase 1;
- payment retries;
- invoices;
- refunds;
- taxes;
- multiple Subscription plans;
- usage limits;
- automatic Appointment cancellation;
- automatic Appointment migration to another Clinic;
- provider-specific billing implementation;
- public Clinic publication Entitlement policy;
- unrestricted provider access to historical records after Subscription loss;
- legal retention duration;
- detailed communication or billing-notification behavior.

---

## 13. Verification Notes

Verification must demonstrate that:

1. loss of Entitlement blocks new normal paid professional activity;
2. loss of Entitlement does not delete domain or historical information;
3. historical medical information remains durable;
4. Organization Membership and professional relationship history remain intact;
5. existing requested Appointments remain identifiable;
6. existing Appointments may be safely resolved without granting normal new
   scheduling capability;
7. confirmed Appointments are not silently cancelled;
8. normal new Appointment confirmation or professional Assignment may be
   denied after Entitlement loss;
9. new normal Clinical Encounters are blocked when they require missing
   Entitlement;
10. already-started care is not abandoned unsafely;
11. active-care continuity is limited to the existing Clinical Encounter;
12. required documentation of already-provided care may continue;
13. existing Draft clinical information may be completed where required and
    otherwise authorized;
14. safe continuity does not restore independently lost professional authority;
15. clinically necessary historical correction may remain possible under the
    applicable correction policy;
16. historical medical history remains available according to its current
    access rules;
17. Care Authorization is not deleted and does not bypass missing commercial
    Entitlement;
18. safe-resolution behavior remains distinct from normal professional
    operation;
19. historical Entitlement does not authorize future unrelated activity;
20. recovery of Entitlement restores capabilities prospectively without
    rewriting the non-entitled period;
21. auditability survives Entitlement loss;
22. backend enforcement prevents manipulated clients from bypassing commercial
    restrictions;
23. denial behavior preserves domain consistency.
24. `PAST_DUE` constitutes loss of normal Phase 1 professional Entitlement;
25. `PAST_DUE` does not provide an implicit normal-activity grace period;
26. safe Appointment resolution cannot create another future paid commitment;
27. safe Appointment resolution does not permit normal Veterinarian Assignment
    or reassignment;
28. an already-active Clinical Encounter may be explicitly concluded after
    Entitlement loss where otherwise authorized;
29. Encounter conclusion under safe continuity cannot create another Encounter;
30. required Clinical Attachment completion for already-provided care may
    continue where otherwise authorized;
31. recovery from `PAST_DUE` to `ACTIVE` restores normal Entitlements only
    prospectively;
32. recovery does not recreate or rewrite obligations resolved while
    Entitlement was unavailable.33. after Entitlement loss, an otherwise authorized current Veterinarian can
    still amend an existing finalized Entry, the original Entry and its
    provenance stay unchanged, and a new Clinical Encounter remains denied;
34. a published Clinic stays published and discoverable after Entitlement
    loss while its requestable times and new requests stay unavailable.

---

## 14. Phase 1 summary (Subscription Operational Safety)

- `PAST_DUE` is loss of normal Entitlement with no grace period (BR-37,
  `SPEC-SUB-003` BR-12) and no automatic timed expiry or recovery; a trusted
  operator resolves it explicitly (`SPEC-SUB-002` §14).
- An open-ended `ACTIVE` Subscription never loses Entitlement by the passage of
  time; only an explicit trusted transition, or a known stored
  commercial-validity end, removes it.
- Clinics are never unpublished automatically on Entitlement loss
  (`SPEC-SUB-003` §15). Guardians see a reason-agnostic empty availability
  message, and only a denied request says that the Clinic is not currently
  accepting online appointment requests; no commercial state is revealed.
- Clinical Amendments to existing finalized history remain possible (BR-20);
  new Clinical Encounters do not (BR-14).

# SPEC-MED-008 — Conclude Clinical Encounter

**Status:** SUPERSEDED by SPEC-MED-010 (2026-10-23; describes the deployed schema until transition stage M2)  
**Requirements:** REQ-MED-013  
**Domain:** Medical Records  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): this Specification becomes `SUPERSEDED` by SPEC-MED-010: there is no Encounter and therefore no conclusion. The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized veterinary professional to explicitly conclude an active
Clinical Encounter when the applicable episode of active veterinary care has
ended.

A Clinical Encounter represents actual professional care.

Its lifecycle must distinguish between:

- care that is currently active;
- care that has been concluded.

Concluding the Clinical Encounter ends the active-care context.

It must not:

- delete the Clinical Encounter;
- rewrite its clinical provenance;
- finalize every Clinical Record Entry automatically;
- complete an associated Appointment automatically;
- revoke a Care Authorization automatically;
- delete or rewrite medical history.

---

## 2. Clinical Encounter Lifecycle

Phase 1 supports the following conceptual Clinical Encounter states:

- `ACTIVE`
- `CONCLUDED`

Lifecycle:

    ACTIVE
      ↓
    CONCLUDED

`CONCLUDED` is terminal for the active-care lifecycle.

A concluded Clinical Encounter must not be reopened through the ordinary
Phase 1 workflow.

If materially new veterinary care is later provided, that care requires a new
Clinical Encounter.

The exact persistence representation of this lifecycle is architectural.

For example, the implementation may represent the lifecycle through:

- explicit state;
- conclusion timestamp;
- or another equivalent model.

---

## 3. Preconditions

To conclude a Clinical Encounter:

- the acting User exists;
- the acting User is authenticated;
- the Clinical Encounter exists;
- the Clinical Encounter is currently active;
- the acting User has an applicable veterinary professional context;
- the acting User is authorized to perform clinical work in the applicable
  Clinic and Organization context;
- the operation concerns the same Pet and care context as the Clinical
  Encounter;
- concluding the Encounter does not require rewriting historical provenance.

The professional concluding the Encounter need not necessarily be the same
professional who originally created or was initially responsible for the
Encounter, provided the acting professional is currently authorized in the
applicable care context.

---

## 4. Business Rules

### BR-1 — New Clinical Encounters begin active

A newly established Clinical Encounter represents active veterinary care.

It must initially be considered `ACTIVE`.

---

### BR-2 — Conclusion requires an explicit operation

A Clinical Encounter must not become concluded merely because:

- time passes;
- an Appointment time passes;
- an Appointment becomes `COMPLETED`;
- a User signs out;
- a Subscription changes state;
- a professional leaves the application.

Conclusion requires an explicit trusted domain operation.

---

### BR-3 — Only active Clinical Encounters may be concluded

The normal conclusion workflow applies only to an `ACTIVE` Clinical Encounter.

A previously concluded Encounter must not receive a second independent
conclusion.

---

### BR-4 — Conclusion records when active care ended

Successful conclusion must preserve the effective time at which the Clinical
Encounter became concluded.

This time must not be silently derived later from current state.

---

### BR-5 — Conclusion preserves who performed the operation

The system must preserve sufficient information to identify the professional
context responsible for concluding the Clinical Encounter.

The concluding professional may differ from:

- the professional who created the Encounter;
- the professional originally responsible for the care;
- professionals who authored individual Clinical Record Entries.

Those identities must remain distinguishable.

---

### BR-6 — Concluding professional does not replace historical responsible Veterinarian

If Dr. Garcia is historically recorded as the responsible Veterinarian for the
Clinical Encounter and Dr. Lopez later validly concludes it, the system must
not rewrite the Encounter as though Dr. Lopez had been the original responsible
Veterinarian.

Historical provider context remains unchanged.

---

### BR-7 — Conclusion preserves Pet identity

Concluding an Encounter must not change the Pet associated with it.

---

### BR-8 — Conclusion preserves Clinic provenance

Concluding an Encounter must not change the Clinic in which the care occurred.

---

### BR-9 — Conclusion preserves Organization provenance

Concluding an Encounter must not change the Veterinary Organization associated
with the historical care context.

---

### BR-10 — Conclusion preserves associated Appointment attribution

Where the Clinical Encounter is associated with an Appointment, concluding the
Encounter must not replace, remove, or rewrite that Appointment relationship.

---

### BR-11 — Clinical Encounter and Appointment lifecycles remain separate

Appointment lifecycle and Clinical Encounter lifecycle represent different
facts.

For example:

    Appointment COMPLETED

answers:

    "Was the scheduled Appointment operationally completed?"

while:

    Clinical Encounter CONCLUDED

answers:

    "Has this active episode of veterinary care ended?"

Neither transition must be inferred solely from the other.

---

### BR-12 — Concluding Encounter does not automatically complete Appointment

Concluding a Clinical Encounter must not independently change an associated
Appointment to `COMPLETED`.

Appointment completion remains governed by its applicable Specification.

A trusted workflow may perform both explicit operations where appropriate, but
their domain meanings remain separate.

---

### BR-13 — Appointment completion does not automatically conclude Encounter

An Appointment becoming `COMPLETED` must not by itself silently conclude the
Clinical Encounter.

This is particularly important where active veterinary care legitimately
continues after the scheduled Appointment operation has been marked complete.

---

### BR-14 — Encounter conclusion does not require every Draft Entry to be finalized

Active veterinary care may end before all clinical documentation has been
completed.

Therefore, a Clinical Encounter may be concluded while Clinical Record Entries
associated with it remain `DRAFT`.

For example:

    care finishes
        ↓
    Encounter CONCLUDED
        ↓
    veterinarian finishes notes
        ↓
    Entry FINALIZED

must be representable.

---

### BR-15 — Conclusion does not automatically finalize Clinical Record Entries

Concluding an Encounter must not:

- convert Draft Entries to Finalized;
- select a clinical event category automatically;
- fabricate missing clinical content;
- establish authorship that did not occur.

Clinical Record Entry finalization remains governed by `SPEC-MED-003`.

---

### BR-16 — Documentation may continue after Encounter conclusion

Authorized professionals may complete documentation associated with a concluded
Clinical Encounter where the documentation genuinely belongs to that care
episode.

This may include, where allowed by the applicable Medical Record
Specifications:

- editing an existing Draft;
- creating necessary documentation of care already provided;
- finalizing Clinical Record Entries;
- completing applicable Clinical Attachments;
- recording results arising from that care episode;
- creating later Amendments to finalized information.

Encounter conclusion must not force clinicians to finish every administrative
or documentation task before active care can be considered ended.

---

### BR-17 — Post-conclusion documentation must not fabricate new active care

A concluded Clinical Encounter must not be used merely as a convenient active
context for unrelated new veterinary care.

Materially new care occurring after the previous care episode has concluded
requires a new Clinical Encounter.

---

### BR-18 — Documentation time and clinical occurrence time remain distinct

Clinical documentation may be created or finalized after the Encounter was
concluded.

The system must preserve the distinction between:

- when the underlying clinical event occurred;
- when the Encounter was concluded;
- when documentation was created;
- when documentation was finalized.

Later documentation must not rewrite the original clinical occurrence time.

---

### BR-19 — Later results may remain associated with the concluded care context

Information that becomes available after the active Encounter ended may still
belong to that historical Encounter where it results from the care performed
during that episode.

For example:

    diagnostic sample collected during Encounter
        ↓
    Encounter CONCLUDED
        ↓
    result becomes available later

The later result may remain attributable to the concluded Encounter where the
applicable clinical model supports it.

This does not reopen the Encounter.

---

### BR-20 — Conclusion does not revoke Care Authorization

Clinical Encounter conclusion and Care Authorization revocation are separate
concepts.

Concluding an Encounter must not represent the Guardian as having revoked
authorization.

Revocation remains governed by `SPEC-ACC-002`.

---

### BR-21 — Conclusion may inform normal Care Authorization ending

The fact that an Encounter has been concluded may be used by the applicable
Care Authorization lifecycle to determine when ordinary active-care access no
longer needs to remain available.

However, this Specification does not define automatic Care Authorization
termination.

The Care Authorization lifecycle must separately define:

- normal end;
- revocation;
- any post-care documentation access required after Encounter conclusion.

---

### BR-22 — Conclusion ends active-care status

Once concluded, the Encounter must no longer be treated as currently active
veterinary care.

A system operation that specifically requires an active Clinical Encounter must
therefore no longer succeed solely through the concluded Encounter.

---

### BR-23 — Conclusion does not remove access needed for valid historical documentation by itself

Encounter conclusion must not be interpreted as a blanket deletion of every
professional capability required to complete legitimate documentation.

Any post-care access must remain bounded by:

- applicable professional context;
- Medical Access Control;
- Care Authorization lifecycle;
- least privilege;
- applicable Entitlement rules.

---

### BR-24 — Existing care may be safely concluded after Entitlement loss where permitted

Where the Subscription and Entitlement Specifications permit safe resolution
of care that was already validly underway, concluding an existing active
Clinical Encounter must be treated as resolution of that existing care rather
than initiation of new care.

Entitlement loss must not require abandoning an already-active care episode in
an incoherent state.

This rule does not authorize creation of a new Clinical Encounter after the
required Entitlement has been lost.

---

### BR-25 — Conclusion does not restore lost professional authority

The ability to safely conclude existing care must not be interpreted as
restoring unrelated Organization, Clinic, professional, or Entitlement
capabilities.

Only the minimum operations required to safely resolve the existing care
context may remain available where the applicable Specifications permit them.

---

### BR-26 — Membership termination does not rewrite concluded or active history

Changes to current Organization Membership must not rewrite:

- Clinical Encounter provenance;
- clinical authorship;
- historical responsible professional;
- previously valid care.

Current authority to continue performing operations must nevertheless be
reevaluated.

---

### BR-27 — Clinic Assignment changes do not rewrite Encounter provenance

Ending or changing a Veterinarian's current Clinic Assignment must not change
the Clinic Assignment context that historically justified care already
provided.

---

### BR-28 — Conclusion is not medical-record sealing

`CONCLUDED` means:

    active veterinary care has ended

It does not mean:

    no further legitimate documentation may ever be associated
    with this care episode

Medical Record finalization and Amendment rules remain independently
applicable.

---

### BR-29 — Conclusion is not Pet discharge modeling

Phase 1 Clinical Encounter conclusion must not imply a broader hospitalization,
admission, discharge, inpatient, referral, or treatment-plan lifecycle unless a
separate approved Specification introduces those concepts.

---

### BR-30 — Reopening a concluded Encounter is not supported

A concluded Clinical Encounter must not be changed back to `ACTIVE` through the
ordinary Phase 1 workflow.

If the conclusion itself was incorrect, a dedicated correction mechanism would
be required.

Such correction behavior is outside this Specification.

---

### BR-31 — Repeated conclusion must preserve first historical conclusion

Repeated attempts to conclude an already concluded Encounter must not:

- replace the original conclusion time;
- replace the original concluding actor;
- create a second active/concluded period;
- reopen the Encounter;
- duplicate historical state.

---

### BR-32 — Concurrent conclusion attempts must produce one coherent result

If several authorized professionals concurrently attempt to conclude the same
active Encounter, the final domain state must contain one coherent conclusion.

The exact concurrency mechanism is architectural.

---

### BR-33 — Failed conclusion preserves active state

If the conclusion operation cannot be completed coherently, the Encounter must
remain in its previous valid state.

The system must not expose a partially concluded Encounter.

---

### BR-34 — Conclusion must be trusted

A manipulated client must not be able to mark an Encounter concluded merely by
asserting:

    state = CONCLUDED

Trusted infrastructure must validate the applicable professional and care
context.

---

### BR-35 — Conclusion may be clinically and operationally traceable

The system must preserve enough information to determine:

- which Clinical Encounter was concluded;
- who concluded it;
- applicable professional context;
- when conclusion became effective.

The exact audit representation is architectural.

---

## 5. Active vs Concluded Encounter

An active Clinical Encounter means:

    veterinary care is currently underway
    within this care context

A concluded Clinical Encounter means:

    the active-care episode represented by this Encounter has ended

It does not mean:

    every document is finalized

or:

    every result has already arrived

or:

    the associated Appointment necessarily changed state

or:

    Care Authorization was revoked

or:

    the historical record can no longer evolve through valid documentation
    and Amendments.

---

## 6. Clinical Encounter vs Appointment Completion

These lifecycles must remain distinct.

Example:

    Appointment
    CONFIRMED
        ↓
    care begins
        ↓
    Clinical Encounter ACTIVE
        ↓
    Appointment COMPLETED
        ↓
    care safely concludes
        ↓
    Clinical Encounter CONCLUDED

Another valid workflow may conclude the Encounter and complete the Appointment
in one trusted application operation.

The domain transitions remain conceptually separate.

---

## 7. Clinical Encounter vs Clinical Documentation

The following sequence must be valid:

    Clinical Encounter ACTIVE

        ↓ care ends

    Clinical Encounter CONCLUDED

        ↓ documentation continues

    Draft Entry updated

        ↓

    Entry FINALIZED

The system must not force:

    finalize every Entry
        ↓
    only then conclude Encounter

because the end of veterinary care and completion of clinical documentation are
different facts.

---

## 8. Clinical Encounter vs Care Authorization

The concepts answer different questions.

Clinical Encounter:

    "Is this episode of actual veterinary care still active?"

Care Authorization:

    "What authorized basis permits professional access
     for this Pet and care context?"

Therefore:

    Encounter CONCLUDED
        ≠
    Care Authorization REVOKED

The normal end of Care Authorization may depend on Encounter conclusion, but
its lifecycle remains separately governed.

---

## 9. Scenarios

### Scenario: Authorized professional concludes active Encounter

Given Luna has an active Clinical Encounter at Animalia Madrid Centro
And Dr. Garcia is currently authorized in the applicable clinical context

When Dr. Garcia concludes the Clinical Encounter

Then the Encounter becomes `CONCLUDED`
And its conclusion time is preserved
And Dr. Garcia is preserved as the concluding professional
And the historical care context remains unchanged

---

### Scenario: Another authorized colleague concludes Encounter

Given Luna has an active Clinical Encounter
And Dr. Garcia is recorded as its responsible Veterinarian
And Dr. Lopez is currently authorized in the same applicable Clinic and
Organization care context

When Dr. Lopez validly concludes the Encounter

Then the Encounter becomes `CONCLUDED`
And Dr. Garcia remains the historical responsible Veterinarian
And Dr. Lopez is identifiable as the professional who concluded the Encounter
And historical provenance is not rewritten

---

### Scenario: Unauthorized professional cannot conclude Encounter

Given Luna has an active Clinical Encounter at Animalia Madrid Centro
And Dr. Lopez has no applicable professional authority in that care context

When Dr. Lopez attempts to conclude the Encounter

Then the operation is denied
And the Encounter remains `ACTIVE`

---

### Scenario: Encounter conclusion preserves provenance

Given Luna's active Encounter records:

    Pet = Luna
    Clinic = Animalia Madrid Centro
    Organization = Animalia Veterinary Group
    responsible Veterinarian = Dr. Garcia

When the Encounter is concluded

Then all of those historical provenance values remain unchanged

---

### Scenario: Encounter may conclude with Draft Entries

Given Luna has an active Clinical Encounter
And the Encounter contains a Draft Clinical Record Entry
And active veterinary care has ended

When the authorized professional concludes the Encounter

Then the Encounter becomes `CONCLUDED`
And the Clinical Record Entry remains `DRAFT`
And no clinical content is fabricated or finalized automatically

---

### Scenario: Draft documentation is finalized after Encounter conclusion

Given Luna's Clinical Encounter is `CONCLUDED`
And Dr. Garcia has a legitimate Draft Clinical Record Entry from that care
episode
And Dr. Garcia remains authorized to complete the applicable documentation

When Dr. Garcia validly finalizes the Entry

Then the Entry becomes `FINALIZED`
And the Clinical Encounter remains `CONCLUDED`
And the later finalization does not change when the care occurred

---

### Scenario: Later diagnostic result belongs to concluded Encounter

Given a diagnostic sample was collected during Luna's Clinical Encounter
And the Encounter is later concluded
And the resulting clinical information becomes available afterwards

When the authorized professional records the result according to the applicable
Medical Record workflow

Then the information may remain associated with Luna's concluded Encounter
And the Encounter does not reopen

---

### Scenario: New care after conclusion requires new Encounter

Given Luna's previous Clinical Encounter is `CONCLUDED`
And Luna later receives materially new veterinary care

When the new care begins

Then the previous Encounter is not reopened
And a new Clinical Encounter must represent the new care context

---

### Scenario: Appointment completion does not silently conclude Encounter

Given Luna has an active Clinical Encounter associated with an Appointment

When the Appointment becomes `COMPLETED`

Then the Clinical Encounter does not become `CONCLUDED` solely because of the
Appointment transition

---

### Scenario: Encounter conclusion does not silently complete Appointment

Given Luna has an active Clinical Encounter associated with a confirmed
Appointment

When the Clinical Encounter is concluded

Then the Appointment lifecycle is not changed solely by Encounter conclusion

---

### Scenario: Conclusion does not revoke Care Authorization

Given Luna has an active Care Authorization supporting the current care context
And Luna's Clinical Encounter is active

When the Encounter is concluded

Then the Encounter becomes `CONCLUDED`
And the Care Authorization is not represented as Guardian-revoked solely
because care concluded

---

### Scenario: Safe conclusion after Entitlement loss

Given Luna has an active Clinical Encounter that began while Animalia had the
required professional Entitlement
And the applicable Entitlement is later lost
And the Subscription rules permit safe resolution of already-active care
And Dr. Garcia remains otherwise authorized to resolve that care

When Dr. Garcia concludes the existing Encounter

Then the Encounter may become `CONCLUDED`
And no new Clinical Encounter is created through that safe-resolution authority
And unrelated paid professional capabilities are not restored

---

### Scenario: Repeated conclusion does not rewrite history

Given Luna's Clinical Encounter was already concluded by Dr. Garcia at time T1

When another conclusion attempt is made at time T2

Then the original conclusion remains authoritative
And T1 is not overwritten
And the original concluding actor is not replaced
And the Encounter remains `CONCLUDED`

---

### Scenario: Concurrent conclusion remains coherent

Given Luna has one active Clinical Encounter
And Dr. Garcia and Dr. Lopez concurrently attempt valid conclusion

When the operations are committed

Then the Encounter has one coherent terminal conclusion
And no duplicate active/concluded periods are created

---

### Scenario: Failed conclusion preserves active Encounter

Given Luna has an active Clinical Encounter

When a conclusion attempt cannot be committed coherently

Then the Encounter remains `ACTIVE`
And no partial conclusion state is exposed

---

## 10. Historical Integrity

Clinical Encounter conclusion must preserve the care context established when
the Encounter was created.

The system must not use mutable current relationships to reconstruct historical
provenance later.

For example:

    Dr. Garcia treats Luna at Animalia Madrid Centro
        ↓
    Encounter later CONCLUDED
        ↓
    Dr. Garcia leaves Animalia
        ↓
    historical Encounter still records
    Dr. Garcia + Madrid Centro + Animalia

Current employment does not redefine previous care.

---

## 11. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-005 — Organization and Clinic are different concepts.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-011 — Professional qualification does not imply medical access.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 12. Dependencies

- SPEC-MED-001 — Create Clinical Encounter
- SPEC-MED-002 — Create Draft Clinical Record Entry
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-004 — Amend Finalized Clinical Information
- SPEC-MED-007 — Manage Clinical Attachments

Medical authorization follows:

- SPEC-ACC-001 — Authorize Professional Medical Access
- SPEC-ACC-002 — Revoke / End Care Authorization

Appointment lifecycle remains governed by the applicable Appointment
Specifications.

Professional authority remains governed by the Organization and Veterinarian
Specifications.

Safe resolution after commercial changes follows the applicable Subscription
and Entitlement Specifications.

---

## 13. Out of Scope

This Specification does not define:

- creating the Clinical Encounter;
- reopening a concluded Clinical Encounter;
- correcting an incorrectly concluded Encounter;
- automatic Encounter timeout;
- hospitalization;
- admission or discharge workflows;
- referral lifecycle;
- treatment-plan lifecycle;
- Appointment completion;
- Care Authorization revocation;
- exact normal Care Authorization ending behavior;
- post-care access duration;
- automatic finalization of clinical documentation;
- exact database lifecycle representation.

---

## 14. Verification Notes

Verification must demonstrate that:

1. newly established Clinical Encounters are active;
2. an authorized professional can explicitly conclude an active Encounter;
3. unauthorized actors cannot conclude the Encounter;
4. conclusion records an effective conclusion time;
5. conclusion preserves the professional responsible for performing the
   conclusion;
6. the concluding professional may differ from the historical responsible
   Veterinarian;
7. conclusion does not rewrite Pet, Clinic, Organization, responsible
   Veterinarian, or Appointment provenance;
8. Appointment completion and Encounter conclusion remain distinct;
9. Appointment completion does not silently conclude an Encounter;
10. Encounter conclusion does not silently complete an Appointment;
11. an Encounter may be concluded while Draft Clinical Record Entries remain;
12. conclusion does not automatically finalize clinical content;
13. legitimate documentation may continue after Encounter conclusion;
14. later documentation does not reopen the Encounter;
15. new materially distinct veterinary care requires a new Clinical Encounter;
16. clinical occurrence, Encounter conclusion, documentation creation, and
    finalization times remain distinguishable;
17. later results arising from the care episode may remain associated with the
    concluded Encounter where applicable;
18. conclusion does not represent Care Authorization revocation;
19. conclusion ends active-care status;
20. safe resolution of already-active care may allow Encounter conclusion after
    Entitlement loss where the applicable Subscription rules permit it;
21. safe-resolution capability does not create unrelated new professional
    authority;
22. current Membership or Clinic Assignment changes do not rewrite historical
    Encounter provenance;
23. a concluded Encounter cannot be reopened through the normal Phase 1
    workflow;
24. repeated conclusion does not overwrite the original conclusion;
25. concurrent conclusion attempts produce one coherent terminal state;
26. failed conclusion preserves the previous active Encounter state.

---

## 15. Phase 1 Appointment-keyed Conclude contract

Defined by **Minimal Clinical Record — Phase 1**. It narrows BR-1–BR-35 for the
mobile client; it does not change them. The Appointment-keyed clinical context
and its authority ordering are those of `SPEC-MED-001` BR-37, with the
`CLINICAL_CARE` capability. An authorized Appointment with no Encounter is
rejected with `23514`, hint `ENCOUNTER_NOT_STARTED`.

### BR-36 — Canonical Conclude operation

    conclude_appointment_clinical_encounter(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, is executable only by
`authenticated`, and requires no Entitlement (BR-24, `SPEC-SUB-004` BR-39). Any
Veterinarian whose current exact-Clinic context holds `CLINICAL_CARE` may
conclude (§3); the concluding User and Clinic Assignment are recorded (BR-5).

- An `ACTIVE` Encounter becomes `CONCLUDED` at the operation's statement instant
  (never earlier than its care start): outcome `CONCLUDED`.
- An already `CONCLUDED` Encounter is left unchanged: outcome
  `ALREADY_CONCLUDED`, the first conclusion time and actor preserved (BR-31).
- Conclusion is allowed with no Entries, with Drafts only, or with finalized
  Entries (BR-14). It finalizes nothing, completes no Appointment, ends no Care
  Authorization, and makes nothing visible to a Guardian (BR-12, BR-15, BR-20).

The result contains `outcome`, `encounter_id`, and `concluded_at`; never clinical
content.

The pre-existing `conclude_clinical_encounter(uuid)` is not a client path.
Client `EXECUTE` is withdrawn; it is kept for trusted compatibility.

### Mobile presentation

- The action is **Terminar atención / Mark care as finished**. "Finalizar
  atención" and "Cerrar atención" are not used: Entries already use Finalize,
  and conclusion does not close or seal the record (BR-28).
- A confirmation explains that the active episode of care is marked as
  finished, that the Appointment is not completed, that Drafts are not
  finalized automatically, and that the record can still be completed
  afterwards where the rules allow it (BR-16).
- A concluded Encounter shows **Atención terminada / Care finished** with its
  Entries and the documentation actions the read still permits
  (`SPEC-MED-009`).
- After any outcome or an uncertain response the client re-reads.

## 16. Phase 1 Appointment-keyed Conclude Verification Notes

In addition to §14, verification must demonstrate that:

27. an Encounter with no Entries, with Drafts only, and with finalized Entries
    each concludes with outcome `CONCLUDED`;
28. a repeat returns `ALREADY_CONCLUDED` with the original conclusion time and
    actor;
29. conclusion leaves the Appointment lifecycle, Drafts, and Care
    Authorization unchanged;
30. after conclusion, Draft creation, update, and finalization remain possible
    while the Care Authorization is `ACTIVE`;
31. conclusion succeeds after the Organization lost the `CLINICAL_CARE`
    Entitlement;
32. no client role executes the generic conclusion operation.
# SPEC-APT-010 — Mark Appointment No-Show

**Status:** APPROVED  
**Requirements:** REQ-APT-005, REQ-APT-006, REQ-APT-008  
**Domain:** Appointments  
**Priority:** P0

> **Superseded in part — Punto 8.** [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md) (`ACCEPTED`) and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md) (`APPROVED`, 2026-10-23): BR-4, BR-5, and §8 condition on Clinical Record Entries instead of an Encounter (SPEC-MED-010 BR-9). The replaced rules keep describing the deployed schema only until the transition stage that implements their replacement (`docs/CLINICAL_DOCUMENTATION_TRANSITION.md` §5); new work follows SPEC-MED-010.

## 1. Intent

Allow an authorized Clinic actor to mark a confirmed Appointment as `NO_SHOW`
when the Pet did not attend the scheduled veterinary Appointment and the
planned care did not occur.

`NO_SHOW` represents a historically meaningful Appointment outcome.

It must remain distinguishable from:

- `COMPLETED`, where the Clinic asserts that the visit occurred
  (`SPEC-APT-009`);
- `CANCELLED`, where the Appointment was explicitly cancelled;
- an Appointment whose scheduled time has merely passed without yet being
  resolved.

Marking an Appointment as `NO_SHOW` must preserve its scheduling,
professional, and historical information.

---

## 2. Preconditions

- The Appointment exists.
- The Appointment is currently `CONFIRMED`.
- The Appointment belongs to a Pet.
- The Appointment belongs to a Clinic.
- The confirmed Appointment time has been reached or passed sufficiently for
  the Clinic to determine that the Pet did not attend; the earliest permitted
  moment is the scheduled start of the latest confirmed scheduling context
  (BR-44).
- The caller identifies the confirmed scheduling context it reviewed, by its
  schedule revision sequence, and that context is still the Appointment's
  latest confirmed scheduling context (BR-41).
- Veterinary care associated with the Appointment did not occur.
- No valid Clinical Encounter representing actual care for that Appointment has
  begun.
- The acting User exists.
- The acting User is authenticated.
- The acting User has current authorization to manage Appointment attendance
  outcome for the relevant Clinic.

---

## 3. Business Rules

### BR-1 — NO_SHOW means the scheduled care did not occur because the Pet did not attend

An Appointment may become `NO_SHOW` when the Pet did not attend the confirmed
Appointment and the planned veterinary care did not occur.

`NO_SHOW` must not be used merely because:

- the Appointment time is in the past;
- documentation has not been completed;
- the Clinic is running late;
- the Veterinarian was temporarily unavailable;
- the Clinic wishes to remove the Appointment from the active schedule.

---

### BR-2 — Only confirmed Appointments may become NO_SHOW

The normal Phase 1 transition is:

    CONFIRMED
        ↓
    NO_SHOW

A `REQUESTED` Appointment must not become `NO_SHOW` because no confirmed
attendance commitment existed.

---

### BR-3 — Passing the scheduled time does not automatically create NO_SHOW

The system must not automatically mark an Appointment `NO_SHOW` solely because
its confirmed time has passed.

The Clinic must explicitly establish the attendance outcome.

Conceptually:

    confirmed time passed
        ≠
    NO_SHOW automatically

---

### BR-4 — NO_SHOW requires absence of actual veterinary care

An Appointment must not be marked `NO_SHOW` when actual veterinary care
associated with that Appointment occurred.

If care occurred, the Appointment must follow the applicable completion
workflow instead.

---

### BR-5 — Valid Clinical Encounter prevents ordinary NO_SHOW classification

If a valid Clinical Encounter associated with the Appointment has already
begun, the normal no-show workflow must not classify the Appointment as
`NO_SHOW`.

The existence of actual care context contradicts the ordinary meaning of
no-show.

Incorrect historical state correction requires separate controlled behavior.

---

### BR-6 — CANCELLED Appointment cannot become NO_SHOW

A `CANCELLED` Appointment must not later become `NO_SHOW` through the ordinary
workflow.

Cancellation and no-show represent different historical outcomes.

---

### BR-7 — COMPLETED Appointment cannot become NO_SHOW

A `COMPLETED` Appointment represents fulfilled care.

It must not later become `NO_SHOW` through ordinary Appointment lifecycle
behavior.

---

### BR-8 — NO_SHOW Appointment cannot be marked NO_SHOW again

Repeated no-show operations must not:

- create duplicate no-show history;
- overwrite the original no-show time;
- replace the User who originally recorded the outcome.

---

### BR-9 — NO_SHOW is terminal in the normal Phase 1 lifecycle

A `NO_SHOW` Appointment must not ordinarily transition back to:

- `REQUESTED`;
- `CONFIRMED`;
- `COMPLETED`.

If the outcome was recorded incorrectly, correction requires a dedicated
controlled workflow if later supported.

---

### BR-10 — NO_SHOW Appointment cannot be normally rescheduled

A `NO_SHOW` Appointment represents a concluded scheduling outcome.

A later visit requires a new Appointment rather than silently reusing the
historical no-show Appointment.

---

### BR-11 — NO_SHOW does not create another Appointment

Marking an Appointment `NO_SHOW` must not automatically create:

- a replacement Appointment;
- a new requested time;
- a new confirmed time.

A Guardian who still wants care must use the applicable new Appointment
workflow.

---

### BR-12 — NO_SHOW preserves Appointment identity

The existing Appointment remains the same domain entity.

Its lifecycle outcome changes to `NO_SHOW`.

The system must not create a replacement record merely to preserve the missed
Appointment.

---

### BR-13 — NO_SHOW preserves Pet identity

Marking an Appointment `NO_SHOW` must not change which Pet the Appointment
concerns.

---

### BR-14 — NO_SHOW preserves Clinic identity

Marking an Appointment `NO_SHOW` must not move the Appointment to another
Clinic.

---

### BR-15 — NO_SHOW preserves original requester

The User who originally requested the Appointment remains historically
identifiable.

---

### BR-16 — NO_SHOW preserves confirmed scheduling information

The system must preserve the confirmed time at which the Appointment was
expected to occur.

The missed scheduled commitment remains historically meaningful.

---

### BR-17 — NO_SHOW preserves scheduling history

Marking the Appointment `NO_SHOW` must not erase:

- original requested time;
- confirmed time;
- accepted reschedule history;
- relevant scheduling proposals;
- prior scheduling changes.

---

### BR-18 — NO_SHOW preserves Veterinarian Assignment history

Any current or historical Veterinarian Assignment associated with the
Appointment must remain identifiable.

The fact that care did not occur must not erase which Veterinarian had been
expected to attend.

---

### BR-19 — NO_SHOW does not create clinical information

Marking an Appointment `NO_SHOW` must not create:

- a Clinical Encounter;
- a Clinical Record Entry;
- a diagnosis;
- a Treatment;
- a Clinical Amendment;
- any clinical statement.

No-show is scheduling history, not clinical care.

---

### BR-20 — NO_SHOW must not fabricate Clinical Encounter

The system must not create a Clinical Encounter solely to record that the Pet
failed to attend.

A Clinical Encounter represents actual veterinary care.

---

### BR-21 — NO_SHOW does not imply a medical conclusion

No-show status must not be interpreted as clinical information about:

- the Pet's health;
- the Guardian's behavior;
- diagnosis;
- prognosis;
- clinical risk.

It records only the relevant Appointment attendance outcome.

---

### BR-22 — NO_SHOW records when the outcome was established

The system must preserve the time at which the Appointment was marked
`NO_SHOW`.

This time remains distinguishable from:

- the confirmed Appointment time;
- requested scheduling time;
- Appointment creation time.

---

### BR-23 — NO_SHOW preserves who recorded the outcome

The system must preserve the User who marked the Appointment `NO_SHOW`.

The recording User may differ from:

- the requesting Guardian;
- the assigned Veterinarian;
- the Organization Owner.

---

### BR-24 — Only authorized Clinic actors may mark NO_SHOW

The acting User must have current responsibility-derived capability to manage
Appointment attendance outcomes for the relevant Clinic.

Authentication or Organization Membership alone is insufficient.

---

### BR-25 — Guardian cannot mark Appointment NO_SHOW through normal workflow

A Guardian must not classify their own Pet's Appointment as `NO_SHOW` through
the Clinic attendance-management workflow.

A Guardian may cancel an Appointment through applicable Guardian behavior
beforehand, but no-show classification is a Clinic operational outcome.

"Beforehand" means strictly before the latest confirmed scheduled start:
Guardian cancellation of a `CONFIRMED` Appointment closes at that start
(`SPEC-APT-003` BR-31). From the start on, a Guardian cannot pre-empt the
Clinic's `NO_SHOW` or completion by cancelling.

---

### BR-26 — Veterinarian status alone does not grant NO_SHOW authority

A Veterinarian Professional Profile or Clinic Assignment alone must not allow a
User to mark arbitrary Appointments `NO_SHOW`.

The User must have the applicable Appointment-management capability.

---

### BR-27 — NO_SHOW becomes historical Appointment information

Once marked `NO_SHOW`, the Appointment must no longer be treated as an active
upcoming Appointment.

It remains part of the Pet's and Clinic's historical Appointment information.

---

### BR-28 — Authorized Guardians may later see the NO_SHOW outcome

An authorized Guardian must be able to distinguish the missed Appointment in
the applicable historical Appointment view.

The Appointment must not disappear merely because the Pet did not attend.

---

### BR-29 — Authorized Clinic actors may later see the NO_SHOW outcome

Authorized Clinic personnel must be able to distinguish historical no-show
Appointments from:

- completed Appointments;
- cancelled Appointments;
- current upcoming Appointments.

---

### BR-30 — NO_SHOW does not remove Care Authorization history

If the Appointment had an Appointment-derived Care Authorization, marking the
Appointment `NO_SHOW` must not erase the historical fact that the authorization
existed.

Current medical-access validity must follow the applicable Care Authorization
lifecycle.

---

### BR-31 — NO_SHOW ends the normal unused Appointment-derived care basis

Where a Care Authorization existed specifically for the Appointment and no
Clinical Encounter began, resolving the Appointment as `NO_SHOW` means that the
intended care episode did not occur.

The Appointment-derived Care Authorization must therefore no longer provide
normal current medical access for that missed care episode.

Historical authorization evidence remains traceable.

---

### BR-32 — NO_SHOW does not revoke unrelated Care Authorizations

Marking one Appointment `NO_SHOW` must not affect:

- another Care Authorization;
- another Appointment;
- another Clinic care episode.

The effect is limited to the applicable missed care context.

---

### BR-33 — Loss of professional Entitlement does not delete NO_SHOW history

Subscription deterioration, cancellation, expiration, or loss of professional
Entitlement must not delete historical no-show Appointments.

---

### BR-34 — Safe NO_SHOW resolution may remain possible after Entitlement loss

If the Appointment already existed before the Organization lost normal
professional Entitlement, an authorized Clinic actor may remain able to mark it
`NO_SHOW` where doing so accurately resolves the existing scheduling
obligation.

This safe-resolution capability must not authorize new paid professional
activity.

---

### BR-35 — Entitlement-loss resolution cannot fabricate a NO_SHOW

Safe resolution after Entitlement loss must still satisfy the ordinary no-show
meaning.

The Clinic must not use `NO_SHOW` merely as a convenient terminal state for
Appointments that should instead be cancelled or otherwise resolved.

---

### BR-36 — NO_SHOW does not impose future booking restrictions

Phase 1 no-show classification must not automatically:

- block the Guardian;
- block the Pet;
- require prepayment;
- reduce booking priority;
- create penalties.

Any future no-show policy requires separate explicit requirements.

---

### BR-37 — NO_SHOW does not affect Guardianship

Marking an Appointment `NO_SHOW` must not:

- remove a Guardian;
- modify Guardianship;
- transfer Pet responsibility.

Appointment attendance and Guardianship remain separate concepts.

---

### BR-38 — NO_SHOW does not modify professional relationships

Marking an Appointment `NO_SHOW` must not:

- end Clinic Assignment;
- alter Organization Membership;
- modify Veterinarian Professional Profile;
- change Organization responsibility.

---

### BR-39 — NO_SHOW operation is atomic

A successful no-show operation must atomically establish:

- `NO_SHOW` lifecycle state;
- no-show recording time;
- recording User;
- preservation of Appointment history.

The system must not expose a partial terminal state.

---

### BR-40 — Failed NO_SHOW operation preserves previous state

If no-show classification cannot be validly completed, the Appointment must
remain in its previous valid state.

A failed operation must not erase scheduling or professional history.

---

### BR-41 — NO_SHOW is bound to the reviewed confirmed scheduling context

Every confirmed scheduling context of an Appointment is established as a
Schedule Revision identified within that Appointment by its revision sequence.
A confirmed Appointment may receive later confirmed scheduling contexts through
an accepted reschedule (`SPEC-APT-005`, `SPEC-APT-006`).

The caller must supply the expected confirmed revision sequence: the revision
sequence of the confirmed scheduling context it reviewed, as exposed by the
Clinic Appointment Schedule for a `CONFIRMED` Appointment (`SPEC-APT-012`
BR-43).

The expected confirmed revision sequence is required. A missing or non-positive
value is an invalid request and is rejected before any state is changed.

Within the same serialized operation, after authorization has been evaluated
and the Appointment is protected against concurrent modification under the
existing lock order:

1. the Appointment must still be `CONFIRMED` (BR-2);
2. the revision sequence of the Appointment's latest confirmed scheduling
   context must equal the expected confirmed revision sequence;
3. only then are the remaining no-show rules evaluated, unchanged: the time
   rule (BR-44), the absence of a Clinical Encounter (BR-4, BR-5), and the
   Appointment-derived Care Authorization rules (BR-31).

Because the lifecycle check precedes the revision check, an Appointment that is
no longer `CONFIRMED` — for example already `NO_SHOW`, `COMPLETED`, or
`CANCELLED` — is rejected as an invalid lifecycle transition, not as a stale
request.

---

### BR-42 — Stale NO_SHOW fails without side effects

If the expected confirmed revision sequence differs from the revision sequence
of the Appointment's current latest confirmed scheduling context, the no-show
operation must fail.

A stale attempt must not create:

- a `NO_SHOW` Lifecycle Event;
- any Appointment lifecycle change;
- a Care Authorization ending;
- an Appointment Communication.

The caller must re-read the Appointment and review its current confirmed
scheduling context before attempting the operation again.

The stale outcome follows the repository's established optimistic-concurrency
convention for a deterministic client-input revision mismatch: an ordinary
raised exception (SQLSTATE `P0001`) with the stable, distinct message
`Stale confirmed Appointment schedule revision`. It must not use a SQLSTATE or
HTTP status that PostgREST or the client library treats as transient and
retries automatically, because retrying with the same stale expected sequence
can never succeed.

---

### BR-43 — Revision sequence, not presented time, determines staleness

Staleness is determined only by comparing revision sequences.

A no-show attempt made with a superseded expected confirmed revision sequence
must fail even when the current confirmed scheduling context has:

- the same start instant;
- the same formatted local date and time;
- only a different end instant, duration, or scheduling timezone;
- a start that, like the superseded one, is already in the past.

The operation must not compare presented or client-supplied scheduling values
in place of the revision sequence, and the caller does not supply an
authoritative interval.

---

### BR-44 — NO_SHOW is permitted from the latest confirmed start

An Appointment may be marked `NO_SHOW` only once the scheduled start of its
latest confirmed scheduling context has been reached, according to
authoritative backend time:

- before that start, the operation is rejected;
- at that start, it is permitted;
- after that start, it is permitted.

The scheduled end is not a requirement.

Phase 1 introduces no lateness threshold. Within this rule, the Clinic decides
operationally whether enough time has passed to determine that the Pet did not
attend (§9, "Guardian arrives significantly late").

---

## 4. No-Show Appointment Information

A no-show Appointment must preserve the existing Appointment information and
enough attendance-outcome information to reconstruct its lifecycle.

### Existing Appointment history

Where applicable:

- Appointment identity;
- Pet;
- Clinic;
- requesting User;
- requested scheduling information;
- confirmed scheduling information;
- rescheduling history;
- Veterinarian Assignment history.

### No-show information

- `NO_SHOW` state;
- no-show recording time;
- User who recorded the outcome.

The system does not need clinical content because no actual Clinical Encounter
occurred through this Appointment.

### Reviewed confirmed scheduling context

The no-show request identifies the Appointment and the expected confirmed
revision sequence (BR-41). The revision sequence is domain concurrency/version
information within one Appointment; it is not a presentation identity and does
not expose the Appointment's complete scheduling history.

### Contract compatibility

Adding the required expected confirmed revision sequence changes the no-show
operation's request contract and is a breaking change to the identifier-only
form.

No mobile client, Edge Function, or operational runbook calls the
identifier-only form, so the forward-only migration that introduces the new
contract removes it without a compatibility fallback. The identifier-only form
must not remain executable by authenticated callers alongside the new form,
because it would bypass BR-41 to BR-43.

---

## 5. Scenarios

### Scenario: Confirmed Appointment is marked no-show

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro
And the confirmed Appointment time has passed
And Luna did not attend
And no veterinary care occurred
And no associated Clinical Encounter began
And Carlos is authorized to manage Appointment attendance outcomes

When Carlos marks the Appointment `NO_SHOW`

Then the Appointment becomes `NO_SHOW`
And the no-show time is recorded
And Carlos is recorded as the User who established the outcome
And the Appointment remains historically identifiable

---

### Scenario: Passing time alone does not create no-show

Given Luna has a `CONFIRMED` Appointment at 10:00
And it is now after 10:00

When no authorized Clinic actor has yet established the attendance outcome

Then the Appointment does not automatically become `NO_SHOW`

---

### Scenario: Requested Appointment cannot become no-show

Given Luna's Appointment remains `REQUESTED`

When an authorized Clinic actor attempts to mark it `NO_SHOW`

Then the operation is denied
And the Appointment remains `REQUESTED`

---

### Scenario: Appointment with actual care cannot become no-show

Given Luna has a `CONFIRMED` Appointment
And Luna attended the Clinic
And a valid Clinical Encounter associated with the Appointment began

When a Clinic actor attempts to mark the Appointment `NO_SHOW`

Then the operation is denied
And actual care prevents ordinary no-show classification

---

### Scenario: Cancelled Appointment cannot become no-show

Given Luna's Appointment is `CANCELLED`

When a no-show operation is attempted

Then the operation is denied
And the Appointment remains `CANCELLED`

---

### Scenario: Completed Appointment cannot become no-show

Given Luna's Appointment is `COMPLETED`

When a no-show operation is attempted

Then the operation is denied
And the Appointment remains `COMPLETED`

---

### Scenario: No-show cannot be recorded twice

Given Luna's Appointment is already `NO_SHOW`

When another no-show operation is attempted

Then no duplicate outcome is created
And the original no-show time remains unchanged
And the original recording User remains unchanged

---

### Scenario: Guardian cannot mark own Appointment no-show

Given Maria is Luna's active Guardian
And Maria has no Clinic Appointment-management capability

When Maria attempts to mark Luna's Appointment `NO_SHOW`

Then the operation is denied
And Guardianship alone is insufficient

---

### Scenario: Veterinarian without Appointment-management authority cannot mark no-show

Given Dr. Garcia has a valid Clinic Assignment at Animalia Madrid Centro
And Dr. Garcia does not have the applicable Appointment attendance-management
capability

When Dr. Garcia attempts to mark Luna's Appointment `NO_SHOW`

Then the operation is denied
And Veterinarian status and Clinic Assignment alone are insufficient

---

### Scenario: No-show preserves Veterinarian Assignment history

Given Dr. Garcia was assigned to Luna's confirmed Appointment
And Luna did not attend

When the Appointment is validly marked `NO_SHOW`

Then Dr. Garcia remains historically identifiable as the assigned
Veterinarian
And the professional Assignment is not deleted

---

### Scenario: No-show creates no Clinical Encounter

Given Luna did not attend her confirmed Appointment

When the Appointment becomes `NO_SHOW`

Then no Clinical Encounter is created
And no Clinical Record Entry is created
And no clinical conclusion is inferred

---

### Scenario: No-show remains visible to Guardian history

Given Maria is an active Guardian of Luna
And Luna previously missed an Appointment that became `NO_SHOW`

When Maria views Luna's historical Appointments

Then the missed Appointment remains identifiable
And it is distinguishable from cancelled and completed Appointments

---

### Scenario: No-show remains visible to Clinic history

Given Animalia Madrid Centro previously marked Luna's Appointment `NO_SHOW`

When an authorized Clinic actor views historical Appointment information

Then the no-show Appointment remains identifiable
And it is no longer treated as an active scheduling obligation

---

### Scenario: No-show Appointment cannot be rescheduled

Given Luna's Appointment is `NO_SHOW`

When a normal rescheduling workflow is attempted

Then the operation is denied
And a later care request requires a new Appointment

---

### Scenario: Appointment-derived Care Authorization ends after no-show

Given Luna's Appointment had an active Appointment-derived Care Authorization
And no Clinical Encounter began
And the Appointment becomes `NO_SHOW`

When current medical authorization is evaluated

Then that missed Appointment's authorization no longer grants normal current
medical access
And the historical authorization remains traceable

---

### Scenario: No-show does not affect another active Care Authorization

Given Luna has Care Authorization A for her missed Animalia Appointment
And Luna separately has Care Authorization B for another valid care context

When the Animalia Appointment becomes `NO_SHOW`

Then Authorization A may cease providing access for that missed episode
And Authorization B remains governed by its own lifecycle

---

### Scenario: Existing Appointment may be resolved as no-show after Entitlement loss

Given Luna had a `CONFIRMED` Appointment before Animalia lost normal
professional Entitlement
And Luna did not attend
And no veterinary care occurred
And Carlos remains authorized to resolve the existing Appointment

When Carlos marks the Appointment `NO_SHOW`

Then the Appointment may become `NO_SHOW`
And the existing obligation is accurately resolved
And no new paid professional activity is enabled

---

### Scenario: Entitlement loss cannot turn cancelled Appointment into no-show

Given Luna's Appointment was already `CANCELLED`
And Animalia lacks normal professional Entitlement

When a User attempts to use safe-resolution behavior to mark it `NO_SHOW`

Then the operation is denied
And safe resolution does not override Appointment lifecycle truth

---

### Scenario: Subscription expiration does not erase no-show history

Given Luna's Appointment was validly marked `NO_SHOW`

When Animalia's Subscription later becomes `EXPIRED`

Then the no-show Appointment remains historically identifiable
And its Pet, Clinic, scheduling, and professional history remain intact

---

### Scenario: Failed no-show operation preserves confirmed state

Given Luna has a `CONFIRMED` Appointment
And a no-show operation cannot be committed atomically

When the operation fails

Then the Appointment remains `CONFIRMED`
And no partial no-show state is exposed

---

### Scenario: No-show recorded for the reviewed confirmed context

Given Luna's Appointment is `CONFIRMED` for 10:00
And its latest confirmed scheduling context has revision sequence N
And 10:00 has passed and Luna did not attend
And Maria, authorized to record attendance outcomes at the Clinic, reviews
revision N in the Clinic schedule

When Maria marks the Appointment `NO_SHOW` with expected confirmed revision
sequence N

Then the Appointment becomes `NO_SHOW`
And the Appointment-derived Care Authorization no longer provides normal access

---

### Scenario: Accepted reschedule makes the reviewed context stale

Given Maria reviewed Luna's `CONFIRMED` Appointment at revision N
And a reschedule was then accepted, establishing confirmed revision N+1

When Maria marks the Appointment `NO_SHOW` with expected confirmed revision
sequence N

Then the operation is rejected as stale
And the Appointment remains `CONFIRMED` at revision N+1
And no `NO_SHOW` Lifecycle Event, Care Authorization ending, or Communication
is created

---

### Scenario: Re-read then mark the current confirmed context

Given Maria's attempt with revision N was rejected as stale
And she re-reads the Clinic schedule and reviews revision N+1
And the start of revision N+1 has been reached

When Maria marks the Appointment `NO_SHOW` with expected confirmed revision
sequence N+1

Then the Appointment becomes `NO_SHOW`

If the start of revision N+1 has not yet been reached, the attempt is instead
rejected under BR-44.

---

### Scenario: Superseded revision with the same start is still stale

Given Luna's confirmed revision N was replaced by revision N+1 with the same
start but a different end
And both starts are already in the past

When Maria marks the Appointment `NO_SHOW` with expected confirmed revision
sequence N

Then the operation is rejected as stale
And the equal start does not make revision N current

---

### Scenario: Two Clinic actors record the same no-show

Given Maria and Jorge both reviewed Luna's `CONFIRMED` Appointment at revision N
And its start has passed

When Maria marks it `NO_SHOW` with revision N
And Jorge then marks it `NO_SHOW` with revision N

Then Maria's operation succeeds
And Jorge's operation is rejected because the Appointment is no longer
`CONFIRMED`
And exactly one `NO_SHOW` Lifecycle Event and one Communication set exist

---

### Scenario: Completion, cancellation, or care wins a race

Given Luna's `CONFIRMED` Appointment at revision N is shown to Maria
And, before Maria submits, the Appointment is completed, cancelled, or a
Clinical Encounter is established for it

When Maria marks it `NO_SHOW` with revision N

Then the operation is rejected — as an invalid lifecycle transition for a
`COMPLETED` or `CANCELLED` Appointment, or under BR-5 when a Clinical Encounter
exists
And the Appointment keeps its existing outcome

---

## 6. Terminal Appointment Outcomes

The normal Phase 1 Appointment lifecycle now supports three materially
different terminal outcomes.

### COMPLETED

    confirmed Appointment existed
        ↓
    Clinic asserts the scheduled visit occurred
    (`SPEC-APT-009`; no Clinical Encounter required)

### CANCELLED

    Appointment intentionally ended
    before normal fulfillment

### NO_SHOW

    confirmed Appointment existed
        ↓
    Pet did not attend
        ↓
    planned care did not occur

These outcomes must remain historically distinguishable.

---

## 7. NO_SHOW vs CANCELLED

`CANCELLED` and `NO_SHOW` must not be used interchangeably.

For example:

    Guardian cancels the day before
        ↓
    CANCELLED

whereas:

    Guardian does not cancel
    confirmed time arrives
    Pet does not attend
        ↓
    NO_SHOW

This distinction provides meaningful Appointment history without making a
clinical judgment about the Pet or Guardian.

---

## 8. NO_SHOW and Clinical Care

`NO_SHOW` means the expected Appointment did not produce the associated actual
care.

Therefore:

    Appointment → NO_SHOW
        ↓
    no Clinical Encounter for that Appointment, now or later

whereas:

    Appointment → COMPLETED
        ↓
    a Clinical Encounter may exist, may be established later,
    or may never exist (`SPEC-APT-009`, `SPEC-MED-001` BR-34)

An existing Clinical Encounter blocks `NO_SHOW` (BR-5) but does not block
completion (`SPEC-APT-009` BR-12): an Encounter contradicts non-attendance, not
a visit that occurred.

The Appointment lifecycle must not manufacture clinical information merely to
represent attendance outcome.

### Symmetry with completion

`NO_SHOW` and `COMPLETED` are symmetric Clinic resolutions of a `CONFIRMED`
Appointment after its scheduled start (`SPEC-APT-009` BR-25). Both require the
reviewed expected confirmed revision sequence (BR-41), reject a stale sequence
with the same stable message (BR-42), permit the operation from the latest
confirmed start (BR-44), and apply no Entitlement gate. They differ in meaning:
`NO_SHOW` asserts that the visit did not occur; `COMPLETED` asserts that it did.

---

## 9. Edge Cases

### Guardian arrives significantly late

A late arrival is not automatically a `NO_SHOW`.

The Clinic may still decide to provide care.

If actual care begins, the Appointment must not follow the ordinary no-show
workflow.

If the Clinic cannot provide care and the Appointment is considered missed,
the applicable attendance policy determines whether `NO_SHOW` is appropriate.

Exact lateness thresholds are outside this Specification.

---

### Clinic could not provide the care

If the Pet attended but the Clinic was unable to provide care because of an
internal Clinic problem, the Appointment should not be classified as
`NO_SHOW`.

A future operational cancellation or failure outcome may be more appropriate.

Phase 1 must not falsely attribute Clinic failure to Pet non-attendance.

---

### Guardian attempted to cancel but communication failed

If the system has no valid cancellation before the scheduled Appointment and
the Pet does not attend, the operational outcome may still require manual
resolution.

The exact dispute or communication-failure behavior is outside this
Specification.

---

### Pet attends but leaves before veterinary care begins

This case is not necessarily equivalent to ordinary `NO_SHOW`, because the Pet
did attend the Clinic.

A future attendance or incomplete-visit model may refine this behavior.

Phase 1 must avoid falsely recording a no-show where attendance is known to
have occurred.

---

### Incorrect no-show discovered later

A `NO_SHOW` Appointment must not be silently changed to another terminal state.

A controlled historical correction workflow may be introduced later if
required.

---

### Future no-show penalties

The existence of `NO_SHOW` history may later support commercial or operational
policies.

Phase 1 does not infer penalties, booking restrictions, or Guardian reputation
from the no-show state.

---

## 10. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-003 — Cancel Appointment
- SPEC-APT-005 — Propose Confirmed Appointment Reschedule
- SPEC-APT-006 — Accept Appointment Reschedule Proposal
- SPEC-APT-009 — Complete Appointment
- SPEC-APT-012 — View Clinic Appointment Schedule
- SPEC-ID-003 — Authenticate User
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization

Loss-of-Entitlement safe-resolution behavior is additionally governed by:

- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-SUB-004 — Handle Loss of Professional Entitlements

---

## 12. Out of Scope

This Specification does not define:

- automatic no-show classification;
- lateness thresholds;
- no-show penalties;
- prepayment requirements;
- booking restrictions after repeated no-shows;
- Guardian reputation or scoring;
- Clinic-caused Appointment failure;
- partial attendance;
- correction of an incorrectly recorded no-show;
- Appointment reminders;
- notification behavior;
- creation of a replacement Appointment.

---

## 13. Verification Notes

Verification must demonstrate that:

1. only a `CONFIRMED` Appointment may become `NO_SHOW` through the normal
   workflow;
2. the Pet must not have received the associated veterinary care;
3. a valid associated Clinical Encounter prevents ordinary no-show
   classification;
4. passing the confirmed time does not automatically create `NO_SHOW`;
5. `REQUESTED`, `CANCELLED`, `COMPLETED`, and already `NO_SHOW` Appointments
   cannot enter the no-show workflow;
6. authorized Clinic attendance-management capability is required;
7. Guardianship or Veterinarian status alone does not grant no-show authority;
8. no-show preserves Pet, Clinic, requester, scheduling, and Veterinarian
   Assignment history;
9. no-show creates no Clinical Encounter or clinical information;
10. the no-show recording User and time remain traceable;
11. `NO_SHOW` is terminal for ordinary Phase 1 scheduling behavior;
12. a no-show Appointment cannot be normally rescheduled;
13. authorized Guardians and Clinic actors may later distinguish no-show
    history;
14. Appointment-derived Care Authorization no longer grants normal access for a
    missed care episode where no care began;
15. unrelated Care Authorizations remain unaffected;
16. no-show classification imposes no automatic Phase 1 penalties;
17. an existing missed Appointment may be safely resolved after Entitlement
    loss;
18. safe resolution does not override Appointment lifecycle truth;
19. Subscription termination does not erase no-show history;
20. failed no-show operations preserve the previous valid state;
21. no-show transition behaves atomically;
22. the no-show operation requires an expected confirmed revision sequence, and
    a missing or non-positive value is rejected with no state change;
23. a no-show with the revision sequence of the current latest confirmed
    scheduling context succeeds when every other rule holds;
24. a no-show with a superseded expected confirmed revision sequence — for
    example after an accepted reschedule — is rejected as stale with SQLSTATE
    `P0001` and the stable message
    `Stale confirmed Appointment schedule revision`;
25. a stale rejection creates no Lifecycle Event, lifecycle change, Care
    Authorization ending, or Communication;
26. a stale rejection occurs even when the superseded and current confirmed
    contexts share the same start, differ only in end, duration, or timezone,
    or both have already started;
27. after a stale rejection, the freshly read current revision sequence
    succeeds when the time rule is satisfied;
28. an Appointment that is no longer `CONFIRMED` is rejected as an invalid
    lifecycle transition, including when a second actor submits the revision
    sequence that was just marked `NO_SHOW`, completed, or cancelled;
29. a no-show attempt racing Clinical Encounter establishment is serialized,
    and an established Encounter prevents the no-show;
30. the time rule is unchanged: rejected before the latest confirmed start,
    permitted at and after it, with no requirement on the scheduled end;
31. the identifier-only no-show form is not executable by authenticated
    callers after the contract change;
32. from the latest confirmed start on, a Guardian cancellation is rejected
    (`SPEC-APT-003` BR-31), so it can never pre-empt a `NO_SHOW` the Clinic
    is entitled to record; the no-show rules themselves are unchanged.
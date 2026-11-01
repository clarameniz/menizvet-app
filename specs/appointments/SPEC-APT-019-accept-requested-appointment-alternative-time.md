# SPEC-APT-019 — Accept Requested Appointment Alternative Time

**Status:** APPROVED
**Requirements:** REQ-APT-005, REQ-APT-007, REQ-APT-009
**Domain:** Appointments
**Priority:** P0

## 1. Intent

Allow a current Guardian to accept the alternative time a Clinic proposed for
a `REQUESTED` Appointment (`SPEC-APT-018`).

Acceptance changes the Guardian's request to exactly the proposed interval. It
does not confirm the Appointment: the Appointment remains `REQUESTED` and the
Clinic must still confirm it through `SPEC-APT-002`.

```text
REQUESTED, revision N = 10:00
pending Clinic proposal P = 12:00–12:30
        │
        │ Guardian accepts P
        ▼
REQUESTED, revision N+1 = 12:00–12:30 (source: P, established by the Guardian)
P = ACCEPTED
        │
        │ Clinic confirms N+1 (SPEC-APT-002)
        ▼
CONFIRMED, 12:00–12:30
```

---

## 2. Preconditions

* The proposal exists and is a Reschedule Proposal on a `REQUESTED` base
  (`SPEC-APT-018` BR-1).
* The proposal is actionable (`SPEC-APT-018` BR-17).
* The Appointment is `REQUESTED` and the proposal's base is still its current
  Schedule Revision.
* The acting User exists, is authenticated, and currently has an active
  Guardianship relationship with the Appointment's Pet.
* The stored proposed interval is still feasible (BR-6).

---

## 3. Business Rules

### BR-1 — Only the Guardian context may accept

An Alternative Time proposal is always Clinic-originated, so it is accepted
only through the Guardian context. The Clinic context cannot accept it.

The operation is Guardian-only and carries no accepting-context parameter.

Where a User holds both a Guardianship and Clinic authority, acceptance is
evaluated purely as a Guardian action.

---

### BR-2 — Current Guardianship is required; any current Guardian may accept

The acting User must currently have an active Guardianship relationship with
the Appointment's Pet when acceptance is processed.

Any current Phase 1 Guardian may accept. Being the original requesting User is
neither required nor sufficient.

---

### BR-3 — Evaluation order

Acceptance is evaluated in this order, within one serialized operation,
consistent with existing Guardian mutations (`SPEC-APT-004`, `SPEC-APT-006`):

1. the acting User must be authenticated and resolve to a domain User;
2. the proposal must exist; its Appointment is resolved;
3. current Guardianship of the Appointment's Pet is proven **before** any
   lifecycle state, proposal state, or proposal detail is disclosed; a User
   without it is denied identically whatever the proposal's state;
4. the Appointment is protected against concurrent modification under the
   existing lock order, and current Guardianship is revalidated under that
   protection;
5. the proposal must belong to this workflow (base context `REQUESTED`); a
   proposal on a `CONFIRMED` base is rejected here and is accepted only through
   `SPEC-APT-006`;
6. the Appointment must be `REQUESTED`;
7. the proposal must be actionable (`SPEC-APT-018` BR-17): `PENDING`, its base
   still current, the base requested start and the proposed start still in the
   future, and the proposing User's Clinic authority continuous since creation;
8. the stored interval is revalidated for feasibility (BR-6);
9. only then are the effects established (BR-7).

---

### BR-4 — No commercial Entitlement gate for Guardian acceptance

Guardian acceptance requires no professional Entitlement of the Clinic's
Organization.

Acceptance only changes the Guardian's own requested scheduling context, which
a current Guardian may already change unilaterally without an Entitlement gate
(`SPEC-APT-004`). A `REQUESTED` scheduling context is not a confirmed
scheduling commitment (`SPEC-APT-013` BR-13), so this is not "ordinary
Appointment rescheduling that establishes another future commitment"
(`SPEC-SUB-003`).

The Clinic's Entitlement is enforced where the Organization acts: when the
proposal is created (`SPEC-APT-018` BR-4) and when the Appointment is
confirmed (`SPEC-APT-002`). Clinic publication is irrelevant.

This intentionally differs from Guardian acceptance of a confirmed reschedule
(`SPEC-APT-006` BR-26), which establishes a new confirmed commitment.

---

### BR-5 — The proposal identity binds the base; no stale token is required

The proposal identifies exactly one base revision. Acceptance succeeds only
while that base is still the Appointment's current Schedule Revision, so a
proposal can never overwrite a newer requested time or a confirmation.

The caller supplies only the proposal identity. No expected revision sequence
is accepted.

---

### BR-6 — Feasibility is revalidated before writing

Acceptance revalidates the stored proposed interval with the feasibility rules
applied at creation (`SPEC-APT-018` BR-15):

* Clinic Appointment Availability;
* where the Appointment has a current Veterinarian Assignment: a still-current
  Clinic Assignment, that Veterinarian's Availability at the Clinic, and no
  other currently known overlapping `CONFIRMED` commitment of that Veterinarian
  at any Clinic, excluding this Appointment.

A failure is reported as a generic unavailability that discloses no detail of
another Appointment, Clinic, or Organization. It writes nothing: the request
keeps its current requested time and the proposal stays `PENDING`. A failed
feasibility check does not by itself make the proposal `VOID`.

The feasibility check never replaces the authoritative protection against
incompatible confirmed commitments of the same Veterinarian. Because a
`REQUESTED` context is not a confirmed commitment, that final race-condition
guard applies when the Clinic later confirms the Appointment (`SPEC-APT-002`
BR-16).

The Clinic's current standard Appointment duration is neither read nor
required: its later change or removal does not affect acceptance
(`SPEC-APT-018` BR-12).

---

### BR-7 — Effects of successful acceptance

Successful acceptance, as one atomic operation:

1. transitions the proposal `PENDING → ACCEPTED`;
2. creates exactly one new `REQUESTED` Schedule Revision N+1 of the same
   Appointment, immediately following the base revision N, with:
   * exactly the proposal's stored start instant, end instant, and scheduling
     timezone — never re-derived, extended, shortened, or recomputed;
   * `established_by_user_id` = the accepting Guardian;
   * `source_proposal_id` = the accepted proposal;
   * creation time = the acceptance time, recorded by the system.

The Appointment remains `REQUESTED`. No Lifecycle Event is created.

Acceptance does not change the Pet, the Clinic, the original requesting User,
the reason for visit, Guardian notes, Guardianship, the Veterinarian
Assignment, or the Appointment-derived Care Authorization.

If any part fails, nothing is written.

---

### BR-8 — Acceptance facts are those of the resulting revision

As in `SPEC-APT-006` BR-34, acceptance is recorded once, by the revision it
establishes:

* acceptance time = the resulting revision's creation time;
* accepting User = the resulting revision's establishing User;
* accepting context = `GUARDIAN`, the counterparty of the proposing context.

These facts are not recorded a second time on the proposal. An accepted
proposal is the source of exactly one revision, and that revision has exactly
one source proposal.

---

### BR-9 — Acceptance is not confirmation

Acceptance must not:

* make the Appointment `CONFIRMED`;
* create a `CONFIRMED` Schedule Revision or any Lifecycle Event;
* create a confirmed scheduling commitment.

Confirmation remains a separate Clinic action under `SPEC-APT-002`. After
acceptance the Clinic confirms using revision sequence N+1, and the confirmed
interval is exactly the accepted interval. A confirmation that carries N is
stale.

---

### BR-10 — The request's deadline follows the accepted time

After acceptance, revision N+1 is the Appointment's latest requested
scheduling context, so the request expires at the accepted start if the Clinic
does not confirm before it (`SPEC-APT-015` BR-3), exactly as after a Guardian
requested reschedule.

Before acceptance, the deadline is the base requested start; a proposal never
extends it (`SPEC-APT-018` BR-21).

---

### BR-11 — Repeated, late, or conflicting acceptance writes nothing

An attempt to accept a proposal that is `ACCEPTED`, `WITHDRAWN`, `VOID`, or
otherwise not actionable fails without creating a Schedule Revision, changing
the proposal, or creating a Communication. A caller that cannot tell whether an
earlier attempt succeeded must re-read the Appointment.

Acceptance is serialized with withdrawal (`SPEC-APT-016`), Guardian
rescheduling, confirmation, cancellation, and expiry of the same Appointment:
exactly one coherent outcome is established, and the others re-evaluate the
resulting state.

When two Guardians accept the same proposal, the first succeeds and the second
fails without effect.

---

### BR-12 — The workflows do not cross

* This operation accepts only proposals on a `REQUESTED` base.
* The confirmed acceptance operation (`SPEC-APT-006`) must reject a proposal
  on a `REQUESTED` base.

---

### BR-13 — Acceptance creates no Communication

Phase 1 creates no Communication for Guardian acceptance: none to Guardians and
none to the Clinic. The Clinic learns of the acceptance from its Appointment
reads (`SPEC-APT-012` BR-45).

A not-yet-delivered `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication for
the accepted proposal is suppressed because the proposal is no longer
actionable (`SPEC-COM-003` BR-72).

---

### BR-14 — State after acceptance

After acceptance:

```text
Appointment                = REQUESTED
current requested revision = N+1, sourced from the accepted Clinic proposal
pending proposal           = none
```

The one-open-proposal slot is free. From here the ordinary `REQUESTED` rules
apply unchanged:

* the Clinic may confirm N+1 (`SPEC-APT-002`), or cancel (`SPEC-APT-003`);
* the Clinic may propose a further alternative against N+1 (`SPEC-APT-018`);
* a Guardian may reschedule the request (`SPEC-APT-004`), creating an
  unsourced revision N+2; the read projections then no longer show the
  accepted-awaiting-confirmation state;
* a Guardian may cancel (`SPEC-APT-003`).

---

### BR-15 — Acceptance does not create clinical information

Acceptance must not create a Medical Record Entry, diagnosis, Treatment,
clinical observation, or other medical information.

---

## 4. Trusted Operation

A conceptual trusted operation is:

```text
accept_requested_appointment_alternative_time(p_proposal_id) → proposal identity
```

The exact technical signature is an implementation decision within these
constraints.

---

## 5. Guardian Presentation Contract

This section defines the Guardian client behavior required for the workflow to
be understood correctly. It adds no backend authority.

The client distinguishes the two proposal workflows from the read projection
(`SPEC-APT-011` BR-32): a pending proposal on a `REQUESTED` Appointment is a
`requestedAlternativeTime`; on a `CONFIRMED` Appointment it is a
`confirmedReschedule`.

### Appointment list

For a `REQUESTED` Appointment with a pending Clinic alternative:

* the lifecycle badge stays `REQUESTED`;
* the time shown stays the current requested time; the proposed time is never
  shown as current;
* an attention tag is shown: ES `La clínica propone otro horario`,
  EN `Clinic proposed another time`.

For a `REQUESTED` Appointment whose current requested context came from an
accepted Clinic proposal (`SPEC-APT-011` BR-33):

* a distinct tag is shown: ES `Pendiente de confirmación de la clínica`,
  EN `Awaiting clinic confirmation`.

### Appointment detail with a pending Clinic alternative

The detail shows:

* the current requested interval;
* the Clinic's proposed interval;
* the Clinic's reason;
* an **Accept** action, only while the Guardian view reports the alternative
  currently acceptable (`SPEC-APT-005` BR-35, `SPEC-APT-011` BR-32);
* the explicit statement: **Accepting changes your request; the Clinic still
  needs to confirm the Appointment.**
* the response deadline, based on the current requested start: **If you do not
  respond before the requested time, the request may expire.**

### Pending alternative that is not currently acceptable

When the Guardian view reports the alternative as not currently acceptable,
the detail still shows the current requested interval, the proposed interval,
the Clinic's reason, and the response deadline, but offers no **Accept**
action. Calm, generic copy conveys: **This proposed time can't be accepted
right now. The request keeps its current time.** It reveals no reason and does
not promise that the Clinic will propose another time, because the alternative
may become acceptable again while it is pending. Acceptance remains
authoritative (BR-6).

### After acceptance

The detail shows the new requested interval and **Requested time updated —
awaiting confirmation from the Clinic**. Nothing implies that the Appointment
is confirmed.

### Guardian requested-reschedule screen

When a Clinic alternative is pending, the reschedule screen warns that changing
the requested time will discard the Clinic's proposed alternative
(`SPEC-APT-004` BR-28). Rescheduling remains allowed.

---

## 6. Scenarios

### Scenario: Guardian accepts the Clinic's alternative

Given Luna's Appointment is `REQUESTED` for 10:00 as revision 1
And the Clinic proposed 12:00–12:30 with a reason
And Maria is a current Guardian of Luna
When Maria accepts the proposal
Then revision 2 is created as `REQUESTED` 12:00–12:30
And revision 2 is established by Maria and identifies the proposal as its source
And the proposal becomes `ACCEPTED`
And the Appointment remains `REQUESTED`
And no Lifecycle Event or Communication is created

---

### Scenario: Clinic confirms after acceptance

Given Maria accepted the Clinic's 12:00–12:30 alternative, creating revision 2
When a Clinic actor confirms with expected requested revision sequence 2
Then the Appointment becomes `CONFIRMED` for 12:00–12:30

---

### Scenario: Confirmation with the pre-acceptance sequence is stale

Given a Clinic actor reviewed revision 1 before Maria accepted the alternative
When the actor confirms with expected requested revision sequence 1
Then the confirmation fails as stale and nothing is written

---

### Scenario: Another current Guardian accepts

Given Carlos requested the Appointment and Maria is also a current Guardian
When Maria accepts the Clinic's alternative
Then the acceptance succeeds
And Carlos remains the original requester

---

### Scenario: Former Guardian cannot accept

Given Carlos's Guardianship of Luna has ended
When Carlos attempts to accept the Clinic's alternative
Then the operation is denied without disclosing the proposal's state

---

### Scenario: Clinic context cannot accept

When a Clinic actor attempts to accept the Clinic's own alternative
Then the operation is denied

---

### Scenario: Acceptance without the Clinic's Entitlement

Given the Organization no longer holds `APPOINTMENT_MANAGEMENT`
When a current Guardian accepts a still-actionable feasible alternative
Then the acceptance succeeds
And the Clinic cannot confirm the Appointment until its Entitlement is restored (`SPEC-APT-002`)

---

### Scenario: Proposed time no longer feasible

Given the Clinic closed its Availability at 12:00 after proposing it
When Maria attempts to accept
Then acceptance fails with a generic unavailability
And the request remains 10:00
And the proposal remains `PENDING`

---

### Scenario: Request expired before acceptance

Given the request is 10:00 and the Clinic's alternative is 12:00
And 10:00 has passed
When Maria attempts to accept
Then acceptance fails because the proposal is no longer actionable

---

### Scenario: Superseded, confirmed, cancelled, or withdrawn

Given the pending proposal was made `VOID` by a Guardian reschedule, a confirmation, or a cancellation, or was `WITHDRAWN`
When Maria attempts to accept it
Then acceptance fails and nothing is written

---

### Scenario: Repeated acceptance

Given Maria's acceptance succeeded
When Maria or Carlos accepts the same proposal again
Then no further revision is created and the proposal is unchanged

---

### Scenario: Confirmed-base proposal through this operation

Given a pending Clinic proposal on a `CONFIRMED` Appointment
When a Guardian submits it to this operation
Then the operation is rejected
And the proposal can be accepted only through `SPEC-APT-006`

---

## 7. Relevant Invariants

* **INV-002 — Pet identity is provider-independent.**
* **INV-003 — Multiple Guardians are supported.**
* **INV-015 — Private operations require an authenticated identity.**

---

## 8. Dependencies

* SPEC-APT-002 — Confirm Appointment
* SPEC-APT-004 — Reschedule Requested Appointment
* SPEC-APT-006 — Accept Appointment Reschedule Proposal
* SPEC-APT-011 — View Guardian Appointments
* SPEC-APT-012 — View Clinic Appointment Schedule
* SPEC-APT-013 — Manage Appointment Availability
* SPEC-APT-015 — Expire Unconfirmed Appointment Request
* SPEC-APT-016 — Withdraw Clinic Reschedule Proposal
* SPEC-APT-018 — Propose Alternative Time for Requested Appointment
* SPEC-COM-003 — Send Appointment Notifications
* SPEC-PET-003 — Accept Guardianship Invitation

---

## 9. Out of Scope

Explicitly deferred beyond Phase 1:

* a Guardian reject action;
* Guardian withdrawal;
* counterproposals;
* confirm-on-accept;
* Clinic-side notification of acceptance;
* an acceptance Communication to Guardians;
* proposal-history UI for proposals that were never accepted;
* a multi-session concurrency harness.

---

## 10. Verification Notes

Verification must demonstrate that:

1. a current Guardian, not necessarily the requester, accepts an actionable
   Alternative Time proposal;
2. acceptance creates exactly one new `REQUESTED` Schedule Revision of the same
   Appointment, immediately following the base, with exactly the frozen start,
   end, and timezone, established by the accepting Guardian, with the accepted
   proposal as its source;
3. the proposal becomes `ACCEPTED` and the Appointment remains `REQUESTED`,
   with no Lifecycle Event, no `CONFIRMED` revision, and no Communication;
4. the acceptance time, accepting User, and accepting context are exactly
   reconstructible from the resulting revision;
5. a former Guardian or a User without Guardianship is denied before any
   proposal or lifecycle state is disclosed;
6. no Clinic path accepts the proposal;
7. acceptance succeeds without the Organization's `APPOINTMENT_MANAGEMENT`
   Entitlement and with an unpublished Clinic;
8. acceptance does not read the standard duration, and a later
   standard-duration change or removal does not change the accepted interval;
9. Clinic Availability, the assigned Veterinarian's current Clinic Assignment
   and Availability, and known confirmed Veterinarian conflicts (excluding this
   Appointment) are revalidated, failing generically with no write and leaving
   the proposal `PENDING`;
10. acceptance fails without effect when the proposal is `ACCEPTED`,
    `WITHDRAWN`, or `VOID`, when the base or proposed start has passed, or when
    the proposer lost continuous authority;
11. acceptance and withdrawal are serialized, and two Guardians accepting
    concurrently produce exactly one resulting revision;
12. a subsequent Clinic confirmation with sequence N+1 confirms exactly the
    accepted interval, and one with sequence N is stale;
13. after acceptance the request expires at the accepted start if not
    confirmed;
14. this operation rejects a `CONFIRMED`-base proposal, and `SPEC-APT-006`
    rejects a `REQUESTED`-base proposal;
15. Guardian and Professional reads expose the accepted-awaiting-confirmation
    provenance after acceptance and no pending proposal (`SPEC-APT-011` BR-33,
    `SPEC-APT-012` BR-45);
16. an undelivered `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication is
    suppressed after acceptance;
17. the Guardian client offers **Accept** only while the alternative is
    reported currently acceptable, which for an alternative equals current
    scheduling feasibility; otherwise the alternative stays visible with
    generic copy and no acceptance action (§5);
18. acceptance needs no Entitlement and succeeds again once an infeasible
    alternative becomes feasible before it lapses (BR-4, BR-6).

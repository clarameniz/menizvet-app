# SPEC-VET-005 — End Veterinarian Clinic Assignment

**Status:** APPROVED  
**Requirements:** REQ-VET-003, REQ-VET-004, REQ-VET-005, REQ-AUD-004  
**Domain:** Veterinary Professionals  
**Priority:** P0

## 1. Intent

Allow an active Veterinarian Clinic Assignment to be ended while preserving
the historical professional relationship between the Veterinarian and the
Clinic.

Ending a Clinic Assignment means that the Veterinarian no longer currently
practices at that Clinic through that Assignment.

The Assignment must remain historically identifiable.

---

## 2. Preconditions

- The Veterinarian Professional Profile exists.
- The Clinic exists.
- The Clinic Assignment exists.
- The Clinic Assignment is currently active.
- The acting User exists.
- The acting User is authenticated.
- The acting User currently holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for
  the Clinic, as defined by `SPEC-ORG-005`. This applies equally when the
  acting User is the assigned Veterinarian (BR-18).
- The Assignment belongs to the Clinic and professional context being acted
  upon.

---

## 3. Business Rules

### BR-1 — Ending an Assignment preserves it historically

Ending a Clinic Assignment must establish an effective end for the
professional Clinic relationship.

The Assignment must not be deleted through the normal termination workflow.

Its historical effective start and end must remain identifiable.

---

### BR-2 — Ended Assignment no longer represents current practice

Once the Clinic Assignment ends, it must no longer represent that the
Veterinarian currently practices at that Clinic.

An ended Assignment must not grant current professional authority.

---

### BR-3 — Assignment termination is Clinic-specific

Ending a Veterinarian's Assignment at one Clinic must not automatically end
their Assignments at other Clinics.

For example:

    Dr. Garcia
    ├── Animalia Madrid Centro → ended
    └── Animalia Getafe        → active

The Getafe Assignment remains unchanged.

---

### BR-4 — Assignment termination is Organization-context-specific

Ending an Assignment in one Veterinary Organization must not affect valid
Clinic Assignments belonging to another Organization.

For example:

    Dr. Garcia
    ├── Animalia Madrid Centro → ended
    └── VetCare Toledo         → active

VetCare Toledo remains unaffected.

---

### BR-5 — Assignment termination does not end Organization Membership

Ending a Clinic Assignment must not automatically end the Veterinarian's
Organization Membership.

A Veterinarian may remain a Member of the Organization while no longer
practicing at a particular Clinic.

---

### BR-6 — Assignment termination does not remove professional identity

Ending a Clinic Assignment must not:

- delete the Veterinarian Professional Profile;
- remove professional credential information;
- alter professional verification history;
- create another professional identity.

The Veterinarian remains the same professional person.

---

### BR-7 — Assignment termination does not modify personal relationships

Ending a Clinic Assignment must not alter:

- Pet Guardianships;
- personal Pets;
- personal Appointments;
- unrelated User relationships.

Professional and personal contexts remain independent.

---

### BR-8 — Historical clinical provenance must remain unchanged

Ending a Clinic Assignment must not rewrite clinical information created while
the Veterinarian validly practiced at the Clinic.

If Dr. Garcia created clinical information for Luna while assigned to
Animalia Madrid Centro, that information must remain historically attributed
to:

- Dr. Garcia;
- Animalia Madrid Centro;
- the applicable Veterinary Organization;
- the original clinical context.

The current Assignment state must not rewrite historical clinical provenance.

---

### BR-9 — Historical Appointments remain identifiable

Ending a Clinic Assignment must not delete or rewrite historical Appointments
involving the Veterinarian.

Past professional participation remains part of Appointment history.

---

### BR-10 — Future Appointment Assignment requires current professional validity

Once the Clinic Assignment has ended, the Veterinarian must not be newly
assigned to future professional activity at that Clinic through the ended
Assignment.

Any future Appointment or clinical workflow requiring current Clinic practice
must evaluate current Assignment validity.

---

### BR-11 — Existing future Appointments are not silently deleted

A Veterinarian may have future Appointments already assigned when their Clinic
Assignment ends.

Ending the Clinic Assignment must not silently delete those Appointments.

The required reassignment, cancellation, or other resolution of affected
future Appointments is a separate scheduling workflow.

---

### BR-12 — Historical Assignment must not be reactivated

An ended Clinic Assignment represents a completed professional period.

It must not later be reactivated by removing or clearing its effective end.

If the Veterinarian returns to the Clinic, a new Clinic Assignment must be
created.

---

### BR-13 — Rejoining creates a new professional period

A Veterinarian who later returns to the same Clinic must receive a new active
Clinic Assignment.

For example:

    Assignment #1
    Started: 2026-02-01
    Ended:   2027-06-30

    Assignment #2
    Started: 2028-01-15
    Ended:   active

Both periods remain historically identifiable.

---

### BR-14 — Only one active equivalent Assignment is allowed

A Veterinarian must not have more than one simultaneously active Clinic
Assignment representing the same relationship with the same Clinic.

Historical ended Assignments may coexist with one current active Assignment.

---

### BR-15 — Effective end cannot precede effective start

The Assignment's effective end must not precede its effective start.

---

### BR-16 — Standard Phase 1 termination is immediately effective

For the workflow defined by this Specification, the Assignment becomes ended
when the termination operation succeeds.

Scheduled future termination and backdated termination are outside this
Specification.

---

### BR-17 — Ending an Assignment requires the Assignment-management capability

An actor may end a Veterinarian Clinic Assignment only when they currently hold
`CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for that Clinic, as defined by
`SPEC-ORG-005`.

Authentication, Organization Membership, Veterinarian Professional Profile, the
`VETERINARIAN` responsibility, the `RECEPTIONIST` responsibility, or a Clinic
Assignment is not sufficient.

Ending a Clinic Assignment is not a paid professional operation and does not
require a Subscription or professional Entitlement.

---

### BR-18 — Phase 1 does not permit Veterinarian self-departure

Phase 1 does not provide a self-departure path.

The assigned Veterinarian cannot end their own Clinic Assignment merely because
it is their own. Ending it requires `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS`
for that Clinic, exactly as for any other actor.

A Veterinarian who also holds that capability for the Clinic, for example
through an Organization-scoped `OWNER` or `ADMINISTRATOR` responsibility, may
end their own Clinic Assignment through that capability.

Ending their own Clinic Assignment must not automatically end Organization
Membership.

Introducing self-departure later requires an approved change to this
Specification.

---

### BR-19 — Authority at another Clinic is insufficient

`CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` held for another Clinic must not
authorize ending the target Clinic Assignment.

Only an Organization-scoped `OWNER` or `ADMINISTRATOR` responsibility provides
the capability across every Clinic of its Organization (`SPEC-ORG-005`).

---

### BR-20 — Ending an already ended Assignment does not alter history

A repeated termination attempt against an already ended Assignment must not:

- overwrite its original effective end;
- create another termination;
- reactivate the Assignment;
- modify historical professional periods.

---

### BR-21 — Assignment termination and removal of current Clinic authority are atomic

The system must not expose a state where:

- the Assignment is considered ended but still provides current professional
  authority; or
- current authority has been removed while the Assignment still represents an
  active professional relationship.

These effects form one logical domain operation.

---

### BR-22 — Organization Membership termination may make Assignment non-current independently

If the supporting Organization Membership ends, the Clinic Assignment must no
longer provide current authority even if its own effective end has not yet
been explicitly recorded.

The historical Assignment must remain identifiable.

A later synchronization or termination workflow may establish the Assignment's
own effective end, but current authorization must never depend on a stale
Assignment remaining technically open.

---

### BR-23 — Clinic unpublication does not end Assignment

A Clinic becoming unpublished must not automatically terminate active
Veterinarian Clinic Assignments.

Public visibility and professional practice relationships are separate
concepts.

---

### BR-24 — Clinic closure may require Assignment termination

Permanent Clinic closure may require all active Clinic Assignments to end.

That behavior belongs to the future Clinic closure Specification and must not
be inferred from unpublication alone.

---

## 4. Assignment State

For Phase 1, Assignment activity is represented temporally.

An active Assignment has:

    effective_start = established
    effective_end   = absent

An ended Assignment has:

    effective_start = established
    effective_end   = established

This Specification does not require a separate status field.

The eventual persistence model may introduce one only if architecture or
additional behavior requires it.

---

## 5. Scenarios

### Scenario: Authorized actor ends Veterinarian Clinic Assignment

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Carlos holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Animalia Madrid Centro

When Carlos ends Maria's Clinic Assignment

Then the Assignment receives an effective end
And the historical Assignment remains identifiable
And Maria no longer currently practices at Animalia Madrid Centro through that Assignment
And Maria's Veterinarian Professional Profile remains unchanged

---

### Scenario: Veterinarian cannot end their own Assignment without the capability

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Maria holds only the Organization-scoped `VETERINARIAN` responsibility in Animalia Veterinary Group

When Maria attempts to end her own Clinic Assignment

Then the operation is denied
And Maria's Assignment remains active

---

### Scenario: Veterinarian holding the capability ends their own Assignment

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Maria also holds the Organization-scoped `OWNER` responsibility in Animalia Veterinary Group

When Maria ends her own Clinic Assignment

Then the Assignment receives an effective end
And the historical Assignment remains identifiable
And Maria no longer currently practices at Animalia Madrid Centro
And Maria's Organization Membership remains unchanged
And Maria's Veterinarian Professional Profile remains unchanged

---

### Scenario: Ending one Clinic Assignment preserves another

Given Maria has an active Assignment at Animalia Madrid Centro
And Maria has an active Assignment at Animalia Getafe

When Maria's Assignment at Animalia Madrid Centro ends

Then the Madrid Assignment becomes historical
And the Getafe Assignment remains active

---

### Scenario: Ending Assignment in one Organization preserves another Organization

Given Maria has an active Assignment at Animalia Madrid Centro
And Maria has an active Assignment at VetCare Toledo

When Maria's Animalia Madrid Centro Assignment ends

Then the Animalia Assignment becomes historical
And the VetCare Toledo Assignment remains active

---

### Scenario: Ending Clinic Assignment does not end Organization Membership

Given Maria has an active Organization Membership in Animalia Veterinary Group
And Maria has an active Assignment at Animalia Madrid Centro

When Maria's Madrid Clinic Assignment ends

Then Maria's Clinic Assignment becomes historical
And Maria's Animalia Organization Membership remains active

---

### Scenario: Assignment termination preserves clinical provenance

Given Maria validly practiced at Animalia Madrid Centro
And Maria created finalized clinical information for Luna in that context
And the clinical information is attributed to Maria and Animalia Madrid Centro

When Maria's Clinic Assignment later ends

Then Luna's historical clinical information remains attributed to Maria
And the information remains attributed to Animalia Madrid Centro
And the historical professional context is not rewritten

---

### Scenario: Future assigned Appointment is not silently deleted

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Maria has a future Appointment assigned at that Clinic

When Maria's Clinic Assignment ends

Then the Appointment is not silently deleted
And Maria must not continue to be treated as currently eligible for future
professional activity through the ended Assignment
And the Appointment requires the applicable resolution workflow

---

### Scenario: Ended Assignment cannot be reactivated

Given Maria previously had a Clinic Assignment at Animalia Madrid Centro
And that Assignment has ended

When Maria later returns to practice at Animalia Madrid Centro

Then the previous Assignment remains ended
And a new Clinic Assignment must be established
And the gap between professional periods remains historically identifiable

---

### Scenario: Veterinarian returns to same Clinic

Given Maria's first Assignment at Animalia Madrid Centro ended on 2027-06-30
And Maria later validly rejoins the Clinic on 2028-01-15

When a new Assignment is established

Then Assignment #1 remains ended on 2027-06-30
And Assignment #2 begins on 2028-01-15
And only Assignment #2 represents current practice

---

### Scenario: Unauthorized User attempts Assignment termination

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Carlos does not hold `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for that
Clinic

When Carlos attempts to end Maria's Assignment

Then the operation is denied
And Maria's Assignment remains active

---

### Scenario: Manager of another Clinic attempts termination

Given Maria has an active Assignment at Animalia Madrid Centro
And Carlos holds a Clinic-scoped `ADMINISTRATOR` responsibility for Animalia Getafe
And Carlos therefore holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` only for Animalia Getafe

When Carlos attempts to end Maria's Madrid Assignment

Then the operation is denied
And Maria's Madrid Assignment remains active

---

### Scenario: Receptionist cannot end an Assignment

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Luis holds a `RECEPTIONIST` responsibility for Animalia Madrid Centro

When Luis attempts to end Maria's Clinic Assignment

Then the operation is denied
And Maria's Assignment remains active

---

### Scenario: Ending an Assignment does not require professional Entitlement

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And Animalia Veterinary Group currently has no normal professional Entitlement
And Carlos holds `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for Animalia Madrid Centro

When Carlos ends Maria's Clinic Assignment

Then the Assignment receives an effective end
And the historical Assignment remains identifiable

---

### Scenario: Already ended Assignment is not ended again

Given Maria's Assignment at Animalia Madrid Centro has already ended

When termination is attempted again

Then the original effective end remains unchanged
And no duplicate termination information is created
And the historical Assignment remains unchanged

---

### Scenario: Clinic becomes unpublished

Given Maria has an active Assignment at Animalia Madrid Centro
And the Clinic is currently published

When Animalia Madrid Centro is unpublished

Then Maria's Clinic Assignment remains active
And unpublication alone does not end her professional relationship with the Clinic

---

### Scenario: Organization Membership ends while Assignment exists

Given Maria has an active Clinic Assignment at Animalia Madrid Centro
And that Assignment depends on Maria's active Animalia Organization Membership

When Maria's Organization Membership ends

Then the Clinic Assignment must no longer grant current professional authority
And historical Assignment information remains preserved
And Maria cannot continue practicing through the stale professional context

---

## 6. Temporal History

The professional history should remain reconstructable.

For example:

    Maria Garcia
    Animalia Madrid Centro

    Assignment #1
    2026-02-01 → 2027-06-30

    No active Assignment
    2027-07-01 → 2028-01-14

    Assignment #2
    2028-01-15 → active

The gap is meaningful historical information.

The implementation must not collapse these periods into:

    2026-02-01 → active

because that would falsely claim uninterrupted practice.

---

## 7. Current Authority and Historical Relationship

An Assignment has two related but distinct uses.

Current authorization asks:

    Does this Veterinarian currently have a valid professional relationship
    with this Clinic?

Historical provenance asks:

    Did this Veterinarian have a valid professional relationship with this
    Clinic when a past event occurred?

An ended Assignment answers:

    current authority: no
    historical relationship: yes

The implementation must preserve this distinction.

---

## 8. Edge Cases

### Future Appointments

A Veterinarian may have future Appointments assigned when the Clinic Assignment
ends.

The Appointment must not be deleted.

The future Appointment must be resolved through the applicable reassignment,
rescheduling, or cancellation behavior.

---

### Active clinical work in progress

A Clinic Assignment may end while some professional workflow is incomplete.

The treatment of in-progress clinical work must be defined by the applicable
Medical Record or Appointment Specifications.

The Assignment must not remain artificially active merely to avoid resolving
such workflows.

---

### Organization Membership remains active

A Veterinarian may leave one Clinic while remaining employed by or associated
with the Veterinary Organization.

This is a valid state.

For example:

    Animalia Membership → active

    Madrid Assignment  → ended
    Getafe Assignment  → active

---

### Professional verification status

Ending a Clinic Assignment must not change professional verification status.

The same verified professional credential remains independent from the Clinic
relationship, subject to its own lifecycle.

---

### Clinic closes

If a Clinic permanently closes, active Assignments may need to be ended as
part of the Clinic closure workflow.

That behavior must preserve the actual historical end of professional
practice rather than deleting Assignments.

---

## 9. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-007 — Clinic Assignment may be temporal.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 10. Dependencies

- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-ORG-004 — End Organization Membership
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ID-003 — Authenticate User

Professional identity is defined by:

- SPEC-VET-001 — Create Veterinarian Professional Profile

---

## 11. Out of Scope

This Specification does not define:

- scheduled future Assignment termination;
- backdated Assignment termination;
- automatic reassignment of future Appointments;
- cancellation of affected Appointments;
- Clinic closure;
- Organization Membership termination workflow;
- professional credential expiration;
- professional suspension;
- public Veterinarian visibility;
- medical-record access;
- completion of in-progress clinical work;
- employment-law or contractual termination semantics.

---

## 12. Verification Notes

Verification must demonstrate that:

1. an actor holding `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for the Clinic
   may end an active Clinic Assignment;
2. Phase 1 provides no self-departure: the assigned Veterinarian without
   `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for the Clinic cannot end their own
   Assignment, while one who holds it may, without ending Organization
   Membership;
3. Assignment termination preserves the historical professional relationship;
4. an ended Assignment grants no current professional authority;
5. termination affects only the relevant Clinic relationship;
6. Assignments at other Clinics remain unchanged;
7. Assignments in other Organizations remain unchanged;
8. Organization Membership does not automatically end;
9. Veterinarian Professional Profile and verification state remain unchanged;
10. historical clinical provenance remains unchanged;
11. historical Appointments remain identifiable;
12. future Appointments are not silently deleted;
13. ended Assignments cannot be reactivated;
14. returning to the Clinic creates a new Assignment and preserves the gap
    between professional periods;
15. repeated termination does not overwrite historical end information;
16. Clinic unpublication does not automatically end Clinic Assignment;
17. Organization Membership termination prevents stale Clinic Assignments from
    granting current professional authority;
18. an active Organization-scoped `OWNER` or `ADMINISTRATOR` may end an
    Assignment at any Clinic of that Organization;
19. a Clinic-scoped `ADMINISTRATOR` may end an Assignment only at its own
    Clinic and is denied at another Clinic;
20. `RECEPTIONIST` in any scope, `VETERINARIAN` alone, bare Membership, an
    ended Membership or Responsibility Grant, and an administrator of another
    Organization are denied;
21. ending an already ended Assignment is rejected and leaves its history
    unchanged;
22. ending an Assignment does not require a Subscription or professional
    Entitlement;
23. only authenticated Users may invoke Assignment termination.

---

## 13. Phase 1 client Assignment-ending contract

Defined by **Staff Responsibility Editing + Veterinarian Enablement — Phase 1**.
It narrows BR-1–BR-24 for the client; it does not change them.

### BR-25 — Canonical Phase 1 operation

The client ends a Clinic Assignment only through

    end_staff_veterinarian_clinic_assignment(
        p_organization_id uuid,
        p_clinic_id uuid,
        p_veterinarian_clinic_assignment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. The client names the Organization and Clinic so that
authorization is decided before the Assignment is looked up. Identifiers come
from the workforce read (`SPEC-VET-006`).

The pre-existing `end_veterinarian_clinic_assignment(uuid)` reports existence
and lifecycle before authorization. It is not a client path: client `EXECUTE`
is withdrawn and it remains for trusted compatibility only.

### BR-26 — Cleanup does not require a VETERINARIAN Grant

Ending requires only `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for the Clinic
(BR-17). It does not require the assigned Member to still hold
`VETERINARIAN`, so legacy or stale Assignments remain manageable.

Ending all current Clinic Assignments is the required step before a current
`VETERINARIAN` Grant can be ended or changed (`SPEC-ORG-006` BR-54). Ending an
Assignment never changes any Responsibility Grant or Membership (BR-5).

### BR-27 — Fail-closed ordering

1. authentication and a coherent domain User — otherwise `28000`;
2. the named Clinic belongs to the named Organization and the acting User holds
   `CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS` for it, re-decided under the
   Organization and Clinic locks — every failure is the same `42501` with one
   fixed message;
3. the Assignment at the named Clinic — a nonexistent Assignment and one at
   another Clinic or Organization fail exactly as step 2;
4. lifecycle — an Assignment that already has an effective end returns
   `ALREADY_ENDED` with its original end and changes nothing (BR-20).

### BR-28 — Outcomes and timestamps

| Outcome | Result members |
| --- | --- |
| `ENDED` | `veterinarian_clinic_assignment_id`, `effective_end` |
| `ALREADY_ENDED` | same, with the original effective end |

- The effective end is the statement instant, never before the Assignment's
  effective start (BR-15, BR-16).
- Nothing is deleted; the Profile, Membership, Grants, Appointment Veterinarian
  Assignments, Availability, and clinical provenance are untouched (BR-6–BR-11).
- An open Assignment whose supporting Membership already ended is already
  non-current (BR-22); ending it records its own effective end as cleanup.
- Concurrent ends serialize on the Organization and Clinic; exactly one records
  the end.

### Mobile presentation

Each current Clinic Assignment in the Staff Member detail Veterinarian section
(`SPEC-ORG-009` §7) shows its Clinic name and **End assignment / Finalizar
asignación** — which may be a remove icon whose accessible name says it ends
that Member's assignment to that Clinic — behind an explicit confirmation
naming the Member and Clinic.
After every outcome the client re-reads the Staff and workforce reads. History
of ended Assignments is not presented in Phase 1.

## 14. Phase 1 client Assignment-ending Verification Notes

In addition to §12, verification must demonstrate that:

24. an Organization Owner/Administrator ends a current Assignment with `ENDED`
    at the statement instant, other Assignments unchanged;
25. a repeat returns `ALREADY_ENDED` with the original end;
26. an Assignment whose Member no longer holds `VETERINARIAN` can still be
    ended;
27. an unknown Assignment, an Assignment at another Clinic, a Clinic of another
    Organization, and a caller without the capability fail identically with
    `42501`;
28. after ending, capability derived from that Assignment is gone only at that
    Clinic;
29. no client role executes the generic ending operation.

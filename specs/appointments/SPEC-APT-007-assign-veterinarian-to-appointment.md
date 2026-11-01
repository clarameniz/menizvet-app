# SPEC-APT-007 — Assign Veterinarian to Appointment

**Status:** APPROVED  
**Requirements:** REQ-APT-004, REQ-APT-005, REQ-APT-008, REQ-APT-009  
**Domain:** Appointments  
**Priority:** P1

> **Revised — Punto 8.** §13 and §14 (`APPROVED` 2026-10-23, [ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md), [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md)) define the Appointment-keyed client contract in which the current assignee is the only Veterinarian who may record new clinical documentation. They supersede BR-6 for self-assignment and BR-17 (Veterinarian Availability) for that contract, and extend assignment to `COMPLETED` Appointments. Until transition stage M1 is deployed this Specification describes the current implementation.

## 1. Intent

Allow an authorized Clinic actor to assign an eligible Veterinarian to an
existing Appointment.

The Assignment identifies the Veterinarian currently expected to provide
professional care for the Appointment.

Assigning a Veterinarian does not:

- confirm a requested Appointment;
- complete the Appointment;
- create clinical information;
- grant unrestricted medical access;
- change the Appointment's Pet or Clinic.

---

## 2. Preconditions

- The Appointment exists.
- The Appointment is currently in either `REQUESTED` or `CONFIRMED` state.
- The Appointment identifies a Pet.
- The Appointment identifies a Clinic.
- The target User exists.
- The target User has a Veterinarian Professional Profile.
- The target Veterinarian has a current valid Clinic Assignment at the
  Appointment's Clinic.
- The acting User exists.
- The acting User is authenticated.
- The acting User has current authorization to manage Veterinarian assignment
  for Appointments at the relevant Clinic.
- No other current Veterinarian is already assigned to the Appointment through
  the Phase 1 responsible-Veterinarian model.

---

## 3. Business Rules

### BR-1 — Veterinarian Assignment is Clinic-specific

A Veterinarian may be assigned to an Appointment only when they have a current
valid Clinic Assignment at the Clinic where the Appointment will take place.

Assignment to another Clinic, including another Clinic belonging to the same
Veterinary Organization, is insufficient.

---

### BR-2 — Veterinarian Professional Profile is required

The target User must have a Veterinarian Professional Profile.

Organization Membership or Clinic employment alone must not cause a User to
be treated as a Veterinarian.

---

### BR-3 — Current Clinic Assignment is required

The Veterinarian's Clinic Assignment must provide a current professional
relationship with the Appointment's Clinic.

A historical ended Clinic Assignment must not authorize new Appointment
assignment.

---

### BR-4 — Phase 1 Appointment Assignment does not require platform credential verification

Because professional credential verification is not required for Phase 1
Clinic Assignment, assigning a Veterinarian to an Appointment does not itself
require a successfully verified professional credential.

The Assignment must not be represented as proof that the Veterinarian's
credentials have been verified.

Any operation that explicitly requires verified professional status must
enforce that requirement independently.

---

### BR-5 — Only authorized Clinic actors may assign a Veterinarian

The acting User must have a current professional context whose
responsibility-derived capabilities allow management of Veterinarian
assignment for Appointments at the relevant Clinic.

Authentication or Organization Membership alone is insufficient.

---

### BR-6 — A Veterinarian cannot self-assign solely because they practice at the Clinic

Having a Veterinarian Professional Profile or Clinic Assignment does not
automatically grant authority to assign oneself to Appointments.

A Veterinarian may perform the assignment only if their current professional
responsibilities independently grant the required Appointment-management
capability.

---

### BR-7 — Assignment may occur while Appointment is REQUESTED

A Veterinarian may be assigned to an Appointment that remains in `REQUESTED`
state.

Assigning the Veterinarian does not confirm the Appointment.

Conceptually:

    REQUESTED
       +
    Dr. Garcia assigned

remains:

    REQUESTED

The Clinic must still confirm the Appointment through `SPEC-APT-002`.

---

### BR-8 — Assignment may occur while Appointment is CONFIRMED

A Veterinarian may also be assigned after an Appointment has already become
`CONFIRMED`.

The Appointment remains `CONFIRMED`.

---

### BR-9 — Assignment does not change Appointment lifecycle state

Assigning a Veterinarian must not transition the Appointment between lifecycle
states.

In particular:

    REQUESTED + assignment → REQUESTED

and:

    CONFIRMED + assignment → CONFIRMED

Assignment and Appointment lifecycle are separate concerns.

---

### BR-10 — Phase 1 supports one current responsible Veterinarian per Appointment

Phase 1 supports at most one current responsible Veterinarian assignment for
an Appointment.

This does not imply that veterinary care can never involve several
professionals.

Additional participating professionals, assistants, specialists, or surgical
teams require separate behavior if introduced later.

---

### BR-11 — Assignment uses the existing Appointment

Assigning a Veterinarian must modify the professional context of the existing
Appointment.

It must not create another Appointment.

---

### BR-12 — Assignment preserves the Pet

Assigning a Veterinarian must not change which Pet the Appointment concerns.

---

### BR-13 — Assignment preserves the Clinic

Assigning a Veterinarian must not change the Clinic at which the Appointment
takes place.

A Veterinarian must not be used to implicitly move an Appointment to the
Clinic where that professional happens to work.

---

### BR-14 — Assignment preserves the original requester

The User who originally requested the Appointment must remain historically
identifiable after a Veterinarian is assigned.

Professional assignment must not replace requester information.

---

### BR-15 — Guardian preference is not Veterinarian Assignment

A Guardian may eventually be allowed to express a preferred Veterinarian when
requesting an Appointment.

Such a preference must not itself establish the professional Assignment.

The Clinic remains responsible for establishing the actual Appointment
Veterinarian through the applicable professional workflow.

---

### BR-16 — REQUESTED Appointment Assignment is not a scheduling commitment

Assigning a Veterinarian to a `REQUESTED` Appointment identifies the intended
professional but does not guarantee that the requested time has been committed.

When the Appointment is later confirmed, the existing Veterinarian Assignment
must satisfy the applicable scheduling and professional-validity rules.

---

### BR-17 — CONFIRMED Appointment Assignment must satisfy scheduling validity

When assigning a Veterinarian to an already `CONFIRMED` Appointment, the
professional must be eligible for the Appointment under the applicable current
scheduling constraints.

The system must not establish an Assignment that knowingly conflicts with
professional scheduling rules.

The exact availability model is defined separately.

---

### BR-18 — Assignment must preserve who performed it

The system must preserve enough information to establish:

- which Veterinarian was assigned;
- which Appointment was affected;
- who performed the Assignment;
- when the Assignment occurred;
- the Clinic context in which it occurred.

---

### BR-19 — Assignment does not grant unrestricted medical access

Being assigned to an Appointment must not automatically grant the Veterinarian
arbitrary or permanent access to the Pet's complete medical history.

Professional medical access must follow the applicable Access Control
Specifications.

Appointment Assignment may become part of an authorized care context, but it
must not independently define the full access model.

---

### BR-20 — Assignment does not create clinical information

Assigning a Veterinarian must not automatically create:

- a Medical Record Entry;
- a diagnosis;
- a Treatment;
- a clinical observation;
- a prescription;
- another clinical event.

---

### BR-21 — Assignment does not create or modify Clinic Assignment

Appointment Assignment uses an existing current Clinic Assignment.

It must not:

- create a Clinic Assignment;
- reactivate an ended Clinic Assignment;
- change the Veterinarian's Clinic employment period.

---

### BR-22 — Duplicate current Assignment must not be created

If the same Veterinarian is already the current assigned Veterinarian for the
Appointment, repeating the Assignment must not create duplicate professional
Assignment history.

---

### BR-23 — Changing to another Veterinarian is a separate workflow

If an Appointment already has a current assigned Veterinarian, replacing that
Veterinarian with another professional must not silently overwrite the
existing Assignment.

Reassignment requires separate behavior that preserves professional Assignment
history.

---

### BR-24 — Assignment history must remain preservable

The domain must support historical reconstruction of which Veterinarian was
assigned to an Appointment at different points in time.

For example:

    Appointment A

    2026-08-20
    Dr. Garcia assigned

    2026-08-25
    Dr. Garcia later replaced by Dr. Lopez

The second operation is outside this Specification, but the initial Assignment
must not be modeled in a way that requires the first professional relationship
to disappear.

---

### BR-25 — Ending Clinic Assignment removes future professional eligibility

If the assigned Veterinarian's Clinic Assignment later ends before the
Appointment takes place, the ended Clinic Assignment must no longer make that
Veterinarian eligible to provide current professional care at the Clinic.

The Appointment must not be silently deleted.

The existing Appointment requires an explicit reassignment, cancellation, or
other applicable resolution workflow.

Historical Assignment information must remain traceable.

---

### BR-26 — Organization Membership termination also removes current eligibility

If the Organization Membership supporting the Veterinarian's Clinic Assignment
ends, the Veterinarian must no longer be treated as currently eligible for the
Appointment through that professional context.

A technically open but no-longer-authoritative Clinic Assignment must not
continue granting current eligibility.

---

### BR-27 — Clinic unpublication does not prevent internal Veterinarian Assignment

A Clinic becoming unpublished does not by itself prevent authorized internal
management of existing Appointments.

Public visibility and professional operation are separate concerns.

Any professional entitlement requirements continue to apply.

---

### BR-28 — Professional entitlements may restrict new Assignment operations

Where the applicable Subscription rules require active professional
entitlements for normal Appointment management, a new Veterinarian Assignment
must satisfy those entitlement requirements.

Safe cancellation of existing obligations does not imply permission to
continue normal professional scheduling operations without entitlement.

---

### BR-29 — Assignment is atomic

A successful Veterinarian Assignment must establish one consistent
professional Appointment relationship.

The system must not expose a partial state in which the Appointment identifies
a Veterinarian who does not satisfy the required Clinic professional context.

---

## 4. Appointment Veterinarian Assignment Information

The domain must support enough information to understand the current and
historical professional Assignment.

At minimum:

### Required

- Appointment;
- assigned Veterinarian;
- Clinic context;
- assigning User;
- Assignment time.

The eventual model may also require temporal information to preserve
reassignment history.

The persistence representation is not defined by this Specification.

---

## 5. Scenarios

### Scenario: Assign Veterinarian to requested Appointment

Given Luna has an Appointment at Animalia Madrid Centro in `REQUESTED` state
And Maria has a Veterinarian Professional Profile
And Maria has an active Clinic Assignment at Animalia Madrid Centro
And Carlos is authorized to manage Appointment Veterinarian Assignments for
Animalia Madrid Centro

When Carlos assigns Maria to Luna's Appointment

Then Maria becomes the current assigned Veterinarian
And the Appointment remains `REQUESTED`
And Luna remains the Appointment's Pet
And Animalia Madrid Centro remains the Appointment's Clinic
And Carlos is recorded as the assigning User

---

### Scenario: Assign Veterinarian to confirmed Appointment

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro
And Maria has an active Clinic Assignment at Animalia Madrid Centro
And Maria is eligible under the applicable scheduling constraints
And Carlos is authorized to manage Veterinarian Assignment

When Carlos assigns Maria to the Appointment

Then Maria becomes the current assigned Veterinarian
And the Appointment remains `CONFIRMED`
And the confirmed time remains unchanged

---

### Scenario: Assignment does not confirm requested Appointment

Given Luna has an Appointment in `REQUESTED` state
And Maria is validly assigned as its Veterinarian

When the Assignment succeeds

Then the Appointment remains `REQUESTED`
And Clinic confirmation is still required through the applicable workflow

---

### Scenario: User without Veterinarian Professional Profile cannot be assigned

Given Carlos is a User
And Carlos belongs to Animalia Veterinary Group
And Carlos does not have a Veterinarian Professional Profile

When an authorized actor attempts to assign Carlos as Veterinarian to Luna's
Appointment

Then the operation is denied
And the Appointment remains without Carlos as its assigned Veterinarian

---

### Scenario: Veterinarian assigned to another Clinic is insufficient

Given Maria has a Veterinarian Professional Profile
And Maria has an active Clinic Assignment at Animalia Getafe
And Maria has no current Clinic Assignment at Animalia Madrid Centro
And Luna's Appointment belongs to Animalia Madrid Centro

When an authorized actor attempts to assign Maria to Luna's Madrid Appointment

Then the operation is denied
And Maria's Getafe Assignment is insufficient

---

### Scenario: Historical Clinic Assignment is insufficient

Given Maria previously practiced at Animalia Madrid Centro
And Maria's Clinic Assignment there has ended
And Luna has a current Appointment at Animalia Madrid Centro

When an authorized actor attempts to assign Maria using the ended Assignment

Then the operation is denied
And the historical professional relationship does not grant current eligibility

---

### Scenario: Veterinarian may be assigned before platform credential verification

Given Maria has a Veterinarian Professional Profile
And Maria has an active Clinic Assignment at Animalia Madrid Centro
And Maria's professional credential is not yet verified by the platform
And Carlos is authorized to assign Veterinarians

When Carlos assigns Maria to Luna's Appointment

Then the Appointment Assignment may be created
And Maria remains professionally unverified
And the Appointment Assignment must not be represented as proof of credential
verification

---

### Scenario: Unauthorized Clinic actor cannot assign Veterinarian

Given Luna has an Appointment at Animalia Madrid Centro
And Carlos is an Organization Member
And Carlos does not have the capability to manage Veterinarian Assignment for
that Clinic

When Carlos attempts to assign Maria

Then the operation is denied
And the Appointment's Veterinarian Assignment remains unchanged

---

### Scenario: Authority in another Clinic is insufficient

Given Carlos may manage Appointment Assignments at Animalia Getafe
And Carlos has no applicable Assignment-management capability at Animalia
Madrid Centro
And Luna's Appointment belongs to Madrid Centro

When Carlos attempts to assign a Veterinarian to Luna's Appointment

Then the operation is denied
And the Appointment remains unchanged

---

### Scenario: Veterinarian cannot self-assign without management capability

Given Maria is a Veterinarian
And Maria has an active Clinic Assignment at Animalia Madrid Centro
And Maria does not have the capability to manage Appointment Veterinarian
Assignments

When Maria attempts to assign herself to Luna's Appointment

Then the operation is denied
And Clinic Assignment alone is insufficient to authorize self-assignment

---

### Scenario: Same Veterinarian is not assigned twice

Given Maria is already the current assigned Veterinarian for Luna's
Appointment

When an authorized actor attempts to assign Maria again

Then no duplicate current Assignment is created
And no misleading duplicate Assignment history is created

---

### Scenario: Another Veterinarian cannot silently replace current Assignment

Given Maria is the current assigned Veterinarian for Luna's Appointment
And Carlos attempts to assign Dr. Lopez instead

When the standard initial Assignment workflow is used

Then Maria is not silently overwritten
And Dr. Lopez does not replace Maria through this workflow
And Veterinarian reassignment requires the applicable separate behavior

---

### Scenario: Guardian preference does not assign Veterinarian

Given Maria, as Luna's Guardian, requested an Appointment
And Maria expressed Dr. Garcia as a preferred Veterinarian
And the Clinic has not yet established a professional Appointment Assignment

When the Appointment request is evaluated

Then Dr. Garcia is not considered the assigned Veterinarian solely because of
the Guardian preference

---

### Scenario: Assignment preserves original requester

Given Carlos originally requested Luna's Appointment
And Maria is later assigned as the Veterinarian

When the professional Assignment is established

Then Carlos remains historically identifiable as the requesting User
And Maria is identified independently as the assigned Veterinarian

---

### Scenario: Assignment does not create medical information

Given Luna has an Appointment
And Maria is validly assigned as the Veterinarian

When the Assignment succeeds

Then no Medical Record Entry is created
And no diagnosis is created
And no Treatment is created

---

### Scenario: Appointment Assignment does not grant arbitrary medical access

Given Maria is assigned to Luna's Appointment
And the applicable medical-access authorization has not been established

When Maria attempts to access protected medical information beyond her
currently authorized professional context

Then Appointment Assignment alone is insufficient to grant that access

---

### Scenario: Veterinarian later leaves the Clinic before Appointment

Given Maria is the assigned Veterinarian for Luna's future Appointment
And Maria later ends her Clinic Assignment at Animalia Madrid Centro before
the Appointment takes place

When Maria's current professional eligibility is evaluated

Then Maria is no longer eligible to provide current care through the ended
Clinic Assignment
And the Appointment is not silently deleted
And Maria's historical Appointment Assignment remains traceable
And the Appointment requires an explicit resolution workflow

---

### Scenario: Organization Membership ends before Appointment

Given Maria is the assigned Veterinarian for Luna's future Appointment
And Maria's supporting Animalia Organization Membership ends

When current professional eligibility is evaluated

Then Maria must no longer be treated as eligible through that professional
context
And the Appointment remains historically identifiable
And an explicit resolution workflow is required

---

### Scenario: Clinic becomes unpublished after Veterinarian Assignment

Given Maria is assigned to Luna's Appointment at Animalia Madrid Centro
And Animalia Madrid Centro is subsequently unpublished
And the Clinic remains operational with the required professional entitlements

When the existing Appointment is managed internally

Then unpublication alone does not remove Maria's Appointment Assignment
And all current professional-validity rules still apply

---

## 6. Appointment Assignment and Clinic Assignment

These relationships must remain distinct.

    Clinic Assignment

    Maria
      ↓
    practices at
      ↓
    Animalia Madrid Centro

means that Maria may be eligible to perform professional work at that Clinic.

By contrast:

    Appointment Veterinarian Assignment

    Appointment A
      ↓
    Maria

means that Maria is the current Veterinarian expected to provide care for that
specific Appointment.

Clinic Assignment is therefore a prerequisite professional relationship.

Appointment Assignment is a specific scheduling relationship.

They must not be collapsed into the same concept.

---

## 7. Current and Historical Assignment

Appointment Assignment must eventually support two different questions:

    Who is currently expected to attend this Appointment?

and:

    Which Veterinarians were previously assigned during the Appointment's
    scheduling history?

Phase 1 permits only one current responsible Veterinarian.

Future reassignment must preserve previous professional Assignment history
rather than silently overwriting it.

---

## 8. Edge Cases

### Requested Appointment time changes after Veterinarian Assignment

A Veterinarian may already be assigned when a Guardian changes the requested
time through `SPEC-APT-004`.

The Appointment must not assume that professional eligibility or availability
for the previous requested time automatically remains valid for the new time.

The scheduling workflow must revalidate the existing Veterinarian Assignment
where required.

The exact resolution behavior may require refinement of the relevant
rescheduling Specification.

---

### Confirmed Appointment is successfully rescheduled

When a confirmed Appointment receives a newly agreed confirmed time through
the reschedule-proposal workflow, any existing Veterinarian Assignment must
remain valid only if the professional continues to satisfy the applicable
scheduling constraints for the new time.

The rescheduling workflow must not silently preserve an invalid professional
Assignment.

---

### Veterinarian becomes unavailable

Temporary professional unavailability does not by itself delete the
Appointment or its historical Assignment.

Reassignment or Appointment rescheduling must occur through explicit
workflows.

---

### Clinic Assignment ends

The historical Appointment Assignment remains meaningful, but it must no
longer be treated as evidence of current professional eligibility.

---

### Appointment is cancelled

Cancelling an Appointment does not require historical Veterinarian Assignment
information to be deleted.

The Appointment and its professional scheduling history remain traceable.

---

## 9. Relevant Invariants

- **INV-004 — Veterinarian identity is Organization-independent.**
- **INV-007 — Clinic Assignment may be temporal.**
- **INV-008 — A Veterinarian may practice at multiple Clinics.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-011 — Professional qualification does not imply medical access.**

---

## 10. Dependencies

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-VET-001 — Create Veterinarian Professional Profile
- SPEC-VET-004 — Assign Veterinarian to Clinic
- SPEC-VET-005 — End Veterinarian Clinic Assignment
- SPEC-ID-003 — Authenticate User

Professional credential verification is defined by:

- SPEC-VET-002 — Request Veterinarian Credential Verification
- SPEC-VET-003 — Resolve Veterinarian Credential Verification

but is not required for Phase 1 Appointment Assignment.

---

## 11. Out of Scope

This Specification does not define:

- replacing an already assigned Veterinarian;
- multiple simultaneous responsible Veterinarians;
- additional participating veterinary professionals;
- Veterinarian availability configuration;
- work schedules;
- shift management;
- Appointment duration;
- Guardian selection of the final Veterinarian;
- public Veterinarian profiles;
- Appointment completion;
- no-show behavior;
- medical-record creation;
- medical-access authorization;
- automatic Veterinarian assignment;
- workload balancing;
- professional compensation.

---

## 12. Verification Notes

Verification must demonstrate that:

1. an authorized Clinic actor may assign an eligible Veterinarian to a
   `REQUESTED` or `CONFIRMED` Appointment;
2. a Veterinarian Professional Profile is required;
3. the Veterinarian must have a current Clinic Assignment at the Appointment's
   Clinic;
4. Assignment at another Clinic is insufficient;
5. historical ended Clinic Assignments are insufficient;
6. professional credential verification is not required for Phase 1
   Appointment Assignment;
7. Assignment does not change Appointment lifecycle state;
8. assigning to a requested Appointment does not confirm it;
9. only one current responsible Veterinarian is supported in Phase 1;
10. Pet, Clinic, original requester, and Appointment identity remain unchanged;
11. unauthorized Clinic actors cannot assign Veterinarians;
12. Clinic Assignment does not authorize self-assignment by itself;
13. Guardian preference does not constitute professional Assignment;
14. duplicate Assignment of the same current Veterinarian is avoided;
15. replacing an existing Veterinarian requires a separate workflow;
16. assigning a Veterinarian does not create clinical information;
17. Appointment Assignment alone does not grant unrestricted medical access;
18. ending the supporting Clinic Assignment or Organization Membership removes
    current professional eligibility without deleting Appointment history;
19. Clinic unpublication alone does not remove an existing Appointment
    Assignment;
20. current and historical professional Assignment must remain distinguishable.

---

## 13. Phase 1 Appointment-keyed client contract — documentation responsibility (Punto 8)

**Status of this section:** `APPROVED` (2026-10-23) together with
[ADR-011](../../docs/decisions/ADR-011-appointment-owned-clinical-documentation.md)
and [SPEC-MED-010](../medical-records/SPEC-MED-010-document-appointment-clinical-record.md).
It narrows and, where stated, supersedes BR-1–BR-29 and `SPEC-APT-008` for the
Professional client.

The current Appointment Veterinarian Assignment designates the Veterinarian
responsible for the visit: only that Veterinarian may record new Clinical
Record Entries for the Appointment (`SPEC-MED-010` BR-6). It belongs to the
Appointment and uses the existing temporal Appointment Veterinarian Assignment
history; no other care entity exists.

### BR-30 — Scope and lifecycle states

Through the client, a Veterinarian may be assigned, reassigned, or
self-assigned only for an Appointment that has exactly one
`REQUESTED → CONFIRMED` Lifecycle Event and is `CONFIRMED` or `COMPLETED`.

A `COMPLETED` Appointment may be assigned or reassigned so that the care that
took place can be documented (supersedes `SPEC-APT-008` BR-25 and
`SPEC-APT-009` BR-19 for assignment). `CANCELLED`, `NO_SHOW`, and `EXPIRED`
Appointments never receive an assignment.

Assignment of a `REQUESTED` Appointment (BR-7) keeps its trusted operation and
has no Phase 1 client path.

An Appointment may be requested, confirmed, and completed without any
assignment. Completion never requires one.

### BR-31 — Eligible Veterinarian

A Veterinarian is eligible for an Appointment when, at the time of the
operation, they hold a current exact-Clinic Veterinarian context at the
Appointment's Clinic — current Organization Membership, current
Organization-scoped `VETERINARIAN` Responsibility, own Veterinarian
Professional Profile, current Veterinarian Clinic Assignment at that Clinic —
holding `CLINICAL_DOCUMENTATION` there (`SPEC-MED-010` BR-11).

The assignment references that concrete Veterinarian Clinic Assignment. An
assignment whose Clinic Assignment, Membership, or Responsibility later ends
remains historically recorded but is **stale**: it authorizes nothing
(`SPEC-MED-010` BR-6) and may be replaced (BR-32, BR-33).

### BR-32 — Managed assignment and reassignment

    assign_appointment_veterinarian(
        p_clinic_id uuid,
        p_appointment_id uuid,
        p_veterinarian_clinic_assignment_id uuid,
        p_expected_assignment_token uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. It requires `APPOINTMENT_ASSIGN_VETERINARIAN` at the Clinic
(`SPEC-ORG-005`: Owner, Administrator, Receptionist). One operation covers the
first assignment and every reassignment.

`p_expected_assignment_token` is the `assignment_token` of the current
assignment the actor reviewed (BR-37), or `NULL` when the actor saw no
assignment.

| Situation | Result |
| --- | --- |
| No current assignment and the token is `NULL` | `ASSIGNED` |
| A current assignment whose token equals the expected one, changed to another eligible Veterinarian | `REASSIGNED` |
| The requested Veterinarian is already the current eligible assignee | `ALREADY_ASSIGNED`; nothing is written |
| The current assignment differs from the expected one | `STALE_ASSIGNMENT` as a plain application error (`P0001`, never `40001` or `409`); nothing is written |

The result contains only `outcome` and the current `assignment_token`.

### BR-33 — Self-assignment

    assign_me_to_appointment(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, has an empty `search_path`, and is executable only by
`authenticated`. The actor must be eligible (BR-31); no
`APPOINTMENT_ASSIGN_VETERINARIAN` is required. This supersedes BR-6 and
`SPEC-APT-008` BR-15 for this operation only and introduces no capability.

| Situation | Result |
| --- | --- |
| No current assignment, or the current one is stale (BR-31) | `ASSIGNED` |
| The actor is already the current eligible assignee | `ALREADY_ASSIGNED`; nothing is written |
| Another eligible Veterinarian is the current assignee | rejected, `23514`, hint `ASSIGNED_TO_ANOTHER_VETERINARIAN`; nothing is written |

Self-assignment never displaces an eligible colleague; changing an eligible
assignee requires BR-32.

### BR-34 — Evaluation order

For BR-32 and BR-33:

1. authentication and a coherent domain User — otherwise `28000`;
2. argument shape, depending on no stored data — otherwise `22023`;
3. the actor's authority at the named Clinic (BR-32 capability, BR-33
   eligibility) — otherwise `42501`;
4. the Appointment, which must belong to that Clinic — otherwise `42501`;
5. locks, in the existing assignment order (that of `reassign_veterinarian`
   and the establishment rule): Organization → Clinic → Appointment for update
   → its current Appointment Veterinarian Assignment → the previous and target
   Veterinarian Professional Profiles in identity order → the target
   Veterinarian Clinic Assignment. The actor's own context is not locked
   before the Appointment, so assignment never inverts the clinical write
   order; for BR-33 the actor's eligibility is re-verified after the target
   Clinic Assignment is locked;
6. lifecycle (BR-30) — otherwise `23514`, hint `APPOINTMENT_STATE_INVALID`;
7. the BR-32 expected token, or the BR-33 current-assignee rule;
8. target eligibility (BR-31), for BR-32 — otherwise `23514`, hint
   `VETERINARIAN_NOT_ELIGIBLE`, identical for an unknown Clinic Assignment, one
   of another Clinic, and an ineligible one;
9. Entitlement: for a `CONFIRMED` Appointment the Organization's current
   `PROFESSIONAL_SCHEDULING` Entitlement (BR-28) — otherwise `42501`, hint
   `SCHEDULING_SERVICE_UNAVAILABLE`; none for a `COMPLETED` Appointment, whose
   assignment resolves an existing obligation and creates no new paid activity
   (`SPEC-SUB-004` BR-27, BR-28);
10. scheduling integrity (BR-35);
11. writes: the current assignment, if any, ends at the operation instant and
    the new one starts at the same instant, with the acting User recorded.

The uniform `42501` of steps 3–4 has the same message and no hint.

### BR-35 — Scheduling integrity

Veterinarian Availability coverage (BR-17, `SPEC-APT-008` BR-6) is not required
by this contract: the assignment designates the Veterinarian responsible for
the visit, and Phase 1 has no Veterinarian Availability client workflow.

For a `CONFIRMED` Appointment the existing structural rule that a Veterinarian
has no overlapping confirmed commitment at any Clinic still applies — otherwise
`23514`, hint `VETERINARIAN_SCHEDULE_CONFLICT`. A `COMPLETED` Appointment is
not a future commitment and is not checked.

### BR-36 — History and audit

Every assignment is one period with the assigned Clinic Assignment, the
assigning User, and its start. A period ends only by replacement in the same
operation, so every ended period is followed by a period starting at the same
instant: who reassigned, when, and from whom to whom are the successor's
assigning User and start together with both Veterinarians. There is no
unassignment operation. Periods are never deleted, and only the end of the
current period may be recorded.

### BR-37 — Professional read of the assignment

    get_appointment_veterinarian_assignment(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns jsonb

It is `SECURITY DEFINER`, `STABLE`, has an empty `search_path`, and is
executable only by `authenticated`. It has the authority and the uniform
`42501` `Clinic Appointment unavailable` of `get_clinic_appointment`
(`SPEC-APT-012` BR-52). That read and the BR-51 projection are unchanged,
because they must keep returning exactly the schedule row columns. The result
is:

- `status`: `UNASSIGNED` or `ASSIGNED`;
- for `ASSIGNED`: `display_name` (current User Profile display name, or `null`
  for the neutral **Veterinarian / Veterinario**), `is_me`, `is_eligible`
  (`false` when stale, BR-31), and `assignment_token` (an opaque identifier of
  the current period);
- `may_assign_me` and `may_manage` — advisory booleans for BR-33 and BR-32.

No User, Membership, Grant, or Clinic Assignment identifier is returned.

### BR-38 — Candidates and history read

    get_appointment_veterinarian_candidates(
        p_clinic_id uuid,
        p_appointment_id uuid
    ) returns jsonb

It requires `APPOINTMENT_ASSIGN_VETERINARIAN` at the Clinic and an Appointment
of that Clinic; otherwise `{"status": "DENIED"}`. It returns:

- `candidates`: every eligible Veterinarian (BR-31), each with
  `veterinarian_clinic_assignment_id`, `display_name`, `is_me`, and
  `is_current_assignee`, ordered by display name;
- `history`: every period, oldest first, with `veterinarian_display_name`,
  `assigned_at`, `ended_at`, and `assigned_by_display_name`.

It only reads and is not a medical-access operation.

### BR-39 — Effects

Assigning, reassigning, or self-assigning:

- changes no Appointment lifecycle, scheduling, Care Authorization, or
  Reschedule Proposal;
- creates no clinical information and grants no medical access (BR-19,
  BR-20);
- never changes the authorship of existing Clinical Record Entries,
  Amendments, or Attachments;
- does not block cancellation, `NO_SHOW`, or rescheduling; only Clinical
  Record Entries do (`SPEC-MED-010` BR-9).

### BR-40 — Withdrawn client paths

`assign_veterinarian_to_appointment(uuid, uuid)` and
`reassign_veterinarian(uuid, uuid)` reveal existence before authority, report
raw errors, and require Veterinarian Availability. Their `authenticated`
`EXECUTE` is withdrawn; they remain trusted operations.

### Mobile presentation

- The professional Appointment detail of a `CONFIRMED` or `COMPLETED`
  Appointment shows one **Veterinarian / Veterinario** row: the assignee's
  name (with **You / Tú**), **No longer at this clinic / Ya no está en esta
  clínica** when stale, or **No veterinarian assigned / Sin veterinario
  asignado**. Opening the detail writes nothing.
- **Assign to me / Asignarme esta cita** appears when `may_assign_me`: one tap,
  no dialog.
- **Assign / Asignar** or **Change / Cambiar** appears when `may_manage`. It
  opens a short list of candidates; selecting one assigns at once, and a
  change asks for one confirmation naming both Veterinarians.
- After any outcome, including `STALE_ASSIGNMENT`, the client re-reads the
  Appointment and shows the authoritative assignee calmly.
- The Guardian never chooses or changes the Veterinarian.

## 14. Phase 1 documentation-responsibility Verification Notes

In addition to §12, verification must demonstrate that:

21. an Owner, Administrator, or Receptionist assigns and reassigns an eligible
    Veterinarian on `CONFIRMED` and `COMPLETED` Appointments, and a
    Veterinarian without `APPOINTMENT_ASSIGN_VETERINARIAN` cannot use BR-32;
22. an eligible Veterinarian self-assigns an unassigned or stale Appointment,
    receives `ALREADY_ASSIGNED` on repeat, and
    `ASSIGNED_TO_ANOTHER_VETERINARIAN` when an eligible colleague is assigned;
23. `REQUESTED`, `CANCELLED`, `NO_SHOW`, and `EXPIRED` Appointments are
    rejected with `APPOINTMENT_STATE_INVALID`;
24. a Clinic Assignment of another Clinic, an unknown one, an ended one, and
    one without `VETERINARIAN` Responsibility are `VETERINARIAN_NOT_ELIGIBLE`;
25. an actor of another Clinic, an unknown Appointment, and missing authority
    receive the same `42501`;
26. two concurrent managed assignments with the same expected token produce
    one success and one `STALE_ASSIGNMENT`, and never two current assignments;
27. self-assignment racing a managed assignment yields exactly one current
    assignee;
28. a reassignment ends the previous period and starts the next at the same
    instant with the acting User, and nothing else changes;
29. no Veterinarian Availability is required, and a confirmed overlapping
    commitment is rejected for `CONFIRMED` only;
30. `PROFESSIONAL_SCHEDULING` is required for `CONFIRMED` and not for
    `COMPLETED`;
31. assignment never changes Entry authorship, the Appointment lifecycle, or
    the Care Authorization, and never blocks other operations;
32. the reads return no internal identifier other than the candidate Clinic
    Assignment identifier and the opaque token, and the candidates read is
    denied without `APPOINTMENT_ASSIGN_VETERINARIAN`;
33. the withdrawn operations are not executable by `authenticated`.

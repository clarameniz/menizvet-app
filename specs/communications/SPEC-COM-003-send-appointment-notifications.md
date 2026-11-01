# SPEC-COM-003 — Send Appointment Notifications

**Status:** APPROVED  
**Requirements:** REQ-COM-003  
**Domain:** Communications  
**Priority:** P1

## 1. Intent

Notify relevant Users when a meaningful Appointment event requires their
attention or awareness.

Appointment notifications support coordination between Guardians and Clinics.

They must reflect authoritative Appointment state without becoming the source
of that state.

For Phase 1, material Appointment changes affecting a Pet may notify all
current Guardians of that Pet where Guardian notification is applicable.

Appointment notifications may use:

- transactional email;
- push notification;
- other future supported transactional channels.

Notification delivery must not be required to establish the validity of the
underlying Appointment lifecycle transition.

---

## 2. Preconditions

For a Guardian Appointment notification:

- the Appointment exists;
- a supported Appointment notification event occurred;
- the Pet associated with the Appointment exists;
- current Guardianship relationships can be evaluated;
- the intended recipient is currently eligible for the applicable notification;
- the notification contains only the information required for its operational
  purpose.

For Clinic-side notification where applicable:

- the target Clinic exists;
- the Appointment belongs to that Clinic;
- the intended professional or operational recipient has a current applicable
  Clinic or Organization context.

Communication dispatch follows trusted infrastructure.

---

## 3. Phase 1 Notification Events

Phase 1 should support Appointment notification behavior for material lifecycle
and scheduling events.

Conceptually, these include:

- Appointment request created;
- Appointment confirmed;
- Appointment cancelled;
- confirmed Appointment reschedule proposed;
- Appointment reschedule accepted;
- Clinic alternative time proposed for a requested Appointment;
- Appointment completed;
- Appointment marked `NO_SHOW`.
- upcoming confirmed Appointment reminder;

Not every internal Appointment operation requires a User-visible notification.

The event must represent a meaningful change or required action.

Expiry of an unconfirmed Appointment request (`SPEC-APT-015`) is not a Phase 1
notification event: no Guardian or Clinic Communication is created because a
request becomes `EXPIRED`, and expiry must never reuse the Appointment
cancellation notification.

---

## 4. Business Rules

### BR-1 — Appointment notification follows an authoritative Appointment event

A notification must be created because an applicable Appointment operation
validly occurred.

The notification must not create the Appointment state itself.

For example:

    Appointment CONFIRMED
            ↓
    confirmation notification

not:

    confirmation notification sent
            ↓
    Appointment becomes CONFIRMED

---

### BR-2 — Notification failure does not rollback Appointment state

If an Appointment transition validly succeeds but notification delivery fails,
the Appointment remains in its authoritative state.

For example:

    Appointment becomes CONFIRMED
            ↓
    push fails

must not result in:

    Appointment returns to REQUESTED

Communication delivery and Appointment lifecycle remain separate concerns.

---

### BR-3 — Appointment notifications are Pet-related shared information

An Appointment belongs to a Pet rather than to a private copy owned by the
Guardian who requested it.

Where a notification event is relevant to Guardians generally, current active
Guardians of the Pet may be notified.

---

### BR-4 — Requesting Guardian is not the only possible Guardian recipient

The User who requested an Appointment must not automatically become the only
Guardian entitled to receive subsequent Appointment notifications.

For example:

    Maria and Carlos
    are Guardians of Luna

    Maria requests Appointment

    Clinic confirms Appointment

Both Maria and Carlos may receive the confirmation notification.

---

### BR-5 — All current Guardians may receive material Appointment lifecycle notifications

For Phase 1, material lifecycle changes affecting the shared Pet Appointment
may notify all current active Guardians of the Pet.

This includes, where applicable:

- confirmation;
- cancellation;
- accepted rescheduling;
- completion;
- no-show outcome.

This supports shared responsibility for the Pet.

---

### BR-6 — Current Guardianship is evaluated at notification time

Guardian recipients must be determined from current applicable Guardianship
state when the notification event is dispatched.

Historical Guardianship alone must not provide future notification eligibility.

---

### BR-7 — Former Guardian must not receive future private Appointment notifications

Once a User's Guardianship relationship with the Pet has ended, that User must
not receive future private Appointment notifications solely because they:

- originally requested the Appointment;
- previously received notifications;
- previously were a Guardian.

Historical requester attribution remains preserved independently.

---

### BR-8 — New Guardian does not require replay of all historical notifications

A User who becomes Guardian after earlier Appointment events occurred does not
need to receive retroactive copies of all previous notifications.

The User may access current Appointment information through the applicable
Guardian Appointment view.

Future applicable events may notify the new current Guardian.

---

### BR-9 — Request notification may be sent to the requesting Guardian

When an Appointment request is successfully created, the requesting Guardian
may receive confirmation that the request was submitted.

This communication must clearly preserve that the Appointment is still
`REQUESTED`.

It must not imply Clinic confirmation.

---

### BR-10 — Other current Guardians may also be informed of a new Appointment request

Because the Appointment belongs to the shared Pet context, Phase 1 may notify
the Pet's other current Guardians that a new Appointment request exists.

The requesting User remains historically identifiable.

The notification must not represent another Guardian as the requester.

---

### BR-11 — REQUESTED and CONFIRMED notifications must remain distinguishable

A message indicating:

    Appointment requested

must not use wording or presentation that implies:

    Appointment confirmed

The lifecycle distinction must remain clear.

---

### BR-12 — Appointment confirmation is a material Guardian notification event

When a Clinic validly confirms an Appointment, current Guardians may be
notified of:

- the Pet;
- Clinic;
- confirmed date and time;
- relevant operational instructions where applicable.

The notification must reflect the authoritative confirmed state.

---

### BR-13 — Appointment cancellation is a material Guardian notification event

When an Appointment is validly cancelled, current Guardians may be notified.

The message must not continue presenting the Appointment as active or
confirmed.

---

### BR-14 — Cancellation notification should identify the cancelled Appointment context

The notification should provide enough information to distinguish the affected
Appointment without unnecessarily exposing unrelated information.

This may include:

- Pet;
- Clinic;
- relevant scheduled date and time;
- cancellation outcome.

---

### BR-15 — Confirmed reschedule proposal requires actionable notification

When the Clinic proposes a new time for a confirmed Appointment and Guardian
acceptance is required, the affected current Guardians may receive an
actionable notification.

The message must preserve that the proposed time has not yet become final.

---

### BR-16 — Reschedule proposal notification does not accept the proposal

Receiving, opening, or reading a reschedule notification must not constitute
acceptance.

Acceptance requires the explicit Appointment workflow defined by
`SPEC-APT-006`.

---

### BR-17 — Reschedule proposal may be acted on by any currently authorized Guardian where Appointment rules permit it

Where the Appointment domain allows a current Guardian to accept the proposed
reschedule, the notification may direct current Guardians to that workflow.

The first valid accepted domain action determines the Appointment state.

Multiple notification deliveries must not result in multiple reschedules.

---

### BR-18 — Accepted reschedule produces updated scheduling notification

When a reschedule proposal is validly accepted, current Guardians may be
notified of the new authoritative confirmed scheduling information.

The previous proposed state must no longer be presented as pending.

---

### BR-19 — Appointment completion may be notified

When a Clinic validly marks an Appointment `COMPLETED`, current Guardians may
receive a completion notification.

The notification must not imply that:

- all clinical documentation is finalized;
- medical results are available;
- every Clinical Record Entry is complete.

Appointment completion and Medical Records lifecycle remain distinct.

---

### BR-20 — NO_SHOW may be notified

When a Clinic validly marks an Appointment `NO_SHOW`, current Guardians may
receive notification of the attendance outcome.

The communication must use neutral operational language.

It must not characterize the Guardian or Pet negatively beyond the actual
Appointment outcome.

---

### BR-21 — NO_SHOW notification must not create penalties

A no-show notification must not by itself:

- restrict future booking;
- charge a penalty;
- lower a reputation score;
- create a behavioral label.

Such policy requires separate requirements.

---

### BR-22 — Clinic may need notification of new Appointment requests

A new `REQUESTED` Appointment may generate operational notification for the
Clinic or applicable Clinic scheduling actors.

The recipient model must follow current Clinic and Organization authorization.

---

### BR-23 — Clinic notification must be scoped to the target Clinic

An Appointment request for:

    Animalia Madrid Centro

must not automatically notify operational personnel of:

    Animalia Getafe

unless a valid Organization-wide responsibility explicitly covers both Clinics.

---

### BR-24 — Organization Membership alone does not make a User a Clinic notification recipient

Professional or operational notification eligibility must follow the
applicable responsibility context.

The system must not send private Clinic Appointment notifications to every
Organization Member.

---

### BR-25 — Ended professional relationship removes future Clinic-side notification eligibility

If a User's relevant Organization Membership, responsibility, or Clinic
Assignment ends, that historical relationship must not continue producing
future private Clinic Appointment notifications.

---

### BR-26 — Veterinarian Assignment may create professional notification relevance

When a Veterinarian is validly assigned or reassigned to an Appointment, the
currently assigned professional may receive appropriate Appointment-related
notification where product policy requires it.

Assignment itself remains governed by the Appointment domain.

---

### BR-27 — Reassigned Veterinarian must not continue receiving future notifications solely from historical Assignment

If Dr. Garcia is replaced by Dr. Lopez on an Appointment, future
professional-specific notifications should follow the current Assignment where
applicable.

Dr. Garcia's historical Assignment remains preserved but does not create
permanent notification eligibility.

---

### BR-28 — Notification recipient resolution must use current domain relationships

The system must not rely solely on a recipient list copied at Appointment
creation time.

Relationships may change before later Appointment events occur.

Current relevant state must be evaluated when determining recipients.

---

### BR-29 — Notification must preserve Pet identity

A notification must correspond to the correct Pet associated with the
Appointment.

A Guardian responsible for several Pets must be able to distinguish which Pet
the Appointment concerns.

---

### BR-30 — Notification must preserve Clinic identity

Appointment communication must identify the applicable Clinic sufficiently for
the recipient to understand where the Appointment belongs.

The system must not confuse Clinics belonging to the same Organization.

---

### BR-31 — Assigned Veterinarian may be included when relevant

Where a specific Veterinarian is currently assigned and the information is
appropriate for the recipient context, Appointment communication may identify
that Veterinarian.

The notification must not imply clinical authorship or actual care before it
occurs.

---

### BR-32 — Unassigned Appointment must not invent a Veterinarian

If no Veterinarian is currently assigned, the notification must not fabricate
one.

---

### BR-33 — Appointment notifications must minimize medical information

Appointment communication should contain operational scheduling information.

It must not automatically expose:

- diagnoses;
- Clinical Record Entries;
- Clinical Attachments;
- laboratory details;
- complete medical history.

---

### BR-34 — Appointment reason must be treated carefully

Where Appointment reason or triage information may contain sensitive medical
content, ordinary external notification channels should avoid including
unnecessary details.

The recipient may authenticate in the application to access information they
are authorized to view.

---

### BR-35 — Push content must be more privacy-minimized than authenticated application content

Because push notifications may appear on lock screens, push presentation should
avoid sensitive Appointment or medical detail that is not necessary for
awareness.

For example:

    "Luna's appointment has been confirmed."

may be appropriate.

The protected application can provide fuller authorized context.

---

### BR-36 — Email may contain more operational detail than push where appropriate

Transactional email may include useful Appointment information such as:

- Clinic;
- date;
- time;
- action required.

However, email must still follow data-minimization and privacy rules.

---

### BR-37 — Notification channel failure does not invalidate another channel

If push delivery fails, transactional email may still succeed.

If email fails, push may still succeed.

Channels remain technically independent.

---

### BR-38 — User with no push destination may still receive email where applicable

Absence of a Push Registration must not prevent applicable transactional email
delivery.

---

### BR-39 — User without deliverable email may still receive push where applicable

Failure of an email destination must not prevent delivery through an eligible
push destination.

---

### BR-40 — Important Appointment state remains visible in the application regardless of notification delivery

Appointment notifications improve awareness.

They must not be the only way to discover current Appointment state.

An authorized User opening the application must see the authoritative current
Appointment information even if every external notification failed.

---

### BR-41 — Notification delivery does not prove acknowledgement

The system must not infer that a Guardian:

- saw the notification;
- understood it;
- agreed with it;
- accepted a proposal;

solely because a notification provider reports delivery.

---

### BR-42 — Notification opening does not perform domain action automatically

Opening a notification may navigate the User to the applicable application
context.

It must not automatically:

- confirm;
- cancel;
- reschedule;
- accept a proposal;
- complete;

the Appointment without the explicit applicable domain action.

---

### BR-43 — Deep links require current authorization

If an Appointment notification contains navigation context, current
authentication and authorization must be evaluated when the User accesses the
Appointment.

An old notification must not provide permanent access.

---

### BR-44 — Stale notifications must not override current Appointment state

A notification may arrive or be opened after the Appointment has changed again.

For example:

    CONFIRMED notification generated
            ↓
    Appointment CANCELLED
            ↓
    User opens old CONFIRMED notification

The application must display the current `CANCELLED` Appointment state.

---

### BR-45 — Superseded actionable notifications must not remain authoritative

Where an Appointment reschedule proposal is no longer actionable because:

- it was accepted;
- it was replaced;
- the Appointment was cancelled;
- lifecycle state changed;

opening an old notification must not allow the obsolete action to succeed.

Current Appointment validation remains authoritative.

---

### BR-46 — Duplicate notifications do not duplicate Appointment operations

If a communication is delivered twice because of retry or provider behavior,
the duplicate message must not cause duplicate Appointment lifecycle events.

---

### BR-47 — Notification event should be logically deduplicatable

The communication system should be capable of identifying repeated dispatch of
the same logical Appointment notification where required.

The exact deduplication mechanism is architectural.

---

### BR-48 — Notification ordering should preserve meaningful user experience where practical

If several Appointment events occur rapidly, communication delivery may arrive
out of order.

The system should avoid presenting obsolete messages as though they were the
current Appointment truth.

The application remains authoritative regardless of delivery order.

---

### BR-49 — Notification retry does not regenerate Appointment event

Retrying a failed communication must reuse the existing notification context
rather than repeating the Appointment operation that originally triggered it.

---

### BR-50 — Guardian notification preferences must not modify Appointment visibility

Future notification preferences may affect whether an optional external
notification is sent.

They must not remove the Appointment from the Guardian's authorized application
view.

---

### BR-51 — Notification preferences must not alter Guardianship

Changing communication preference must not:

- add a Guardian;
- remove a Guardian;
- transfer Pet responsibility.

---

### BR-52 — Phase 1 Appointment notifications are transactional, not marketing

Appointment lifecycle and scheduling notifications are operational
communications.

They must remain distinct from promotional or marketing communication.

---

### BR-53 — Subscription loss does not erase existing Appointment notifications

Loss of professional Entitlement must not destructively erase required
historical communication information.

---

### BR-54 — Safe resolution after Entitlement loss may still generate notifications

Where `SPEC-SUB-004` allows an existing Appointment to be safely:

- cancelled;
- completed;
- marked `NO_SHOW`;

the corresponding transactional notification may still be sent.

Commercial Entitlement loss must not prevent necessary communication about an
existing obligation being resolved.

---

### BR-55 — Clinic unpublication does not prevent necessary existing Appointment communication

If a Clinic becomes unpublished but existing Appointments still require
resolution, required transactional notifications may continue.

Public Discovery status and existing Appointment communication are separate
concerns.

---

### BR-56 — Appointment notification dispatch must be trusted

The mobile client must not be able to fabricate authoritative Appointment
notifications for lifecycle states that did not occur.

Trusted infrastructure determines the applicable notification event from valid
Appointment state.

---

### BR-57 — Notification event does not create medical access

Receiving an Appointment notification must not grant:

- longitudinal medical-history access;
- Clinical Attachment access;
- professional medical access;
- Care Authorization.

---

### BR-58 — Communication history and Appointment history remain separate

The Appointment domain preserves what happened to the Appointment.

The Communications domain may preserve which notifications were attempted.

Neither should replace the other.

---

### BR-59 — Confirmed Appointments may generate reminders

A future `CONFIRMED` Appointment may generate one or more transactional
reminders before its scheduled time according to the applicable Phase 1
reminder policy.

A reminder communicates an existing Appointment commitment.

It must not modify the Appointment lifecycle.

---

### BR-60 — Only active confirmed Appointments generate normal reminders

Normal Appointment reminders must apply only while the Appointment remains
`CONFIRMED`.

An Appointment that is:

- `REQUESTED`;
- `CANCELLED`;
- `COMPLETED`;
- `NO_SHOW`;

must not generate a normal upcoming Appointment reminder.

---

### BR-61 — Reminder eligibility must be evaluated using current Appointment state

The system must evaluate the current Appointment state before dispatching a
scheduled reminder.

A reminder that was previously planned must not be sent as though still valid
when the Appointment has since been:

- cancelled;
- completed;
- marked `NO_SHOW`;
- rescheduled to another time.

---

### BR-62 — Rescheduling updates reminder relevance

When a confirmed Appointment is validly rescheduled, future reminder behavior
must follow the new authoritative confirmed time.

The previous scheduled time must not continue generating ordinary reminders.

---

### BR-63 — Reminder does not create or confirm Appointment

Sending an Appointment reminder must not:

- create an Appointment;
- confirm an Appointment;
- reschedule an Appointment;
- change any Appointment lifecycle state.

The reminder reflects an existing confirmed commitment.

---

### BR-64 — Reminder recipients follow current Guardianship

Guardian reminder recipients must be determined from the current applicable
Guardianship relationships when the reminder is dispatched.

A former Guardian must not continue receiving private reminders solely because
they were a Guardian when the Appointment was originally confirmed.

---

### BR-65 — Reminder content must remain operational

An Appointment reminder may contain information such as:

- Pet;
- Clinic;
- confirmed date and time;
- current assigned Veterinarian where appropriate;
- necessary attendance instructions.

It must not unnecessarily expose protected medical information.

---

### BR-66 — Reminder delivery is not acknowledgement

Successful delivery of an Appointment reminder must not imply that the Guardian:

- saw it;
- read it;
- intends to attend;
- confirmed attendance.

Appointment lifecycle remains unchanged.

---

### BR-67 — Reminder failure does not alter Appointment state

Failure to deliver an Appointment reminder must not cancel or otherwise modify
the confirmed Appointment.

The authoritative Appointment remains available through the application.

---

### BR-68 — Phase 1 requires a configurable reminder policy

The system must support at least one pre-Appointment reminder for eligible
confirmed Appointments.

The exact advance interval must be configurable product policy rather than
hard-coded domain behavior.

For example, the product may configure a reminder approximately:

    24 hours before the Appointment

without making `24 hours` a permanent domain invariant.

---

### BR-69 — Phase 1 does not require repeated reminder campaigns

Phase 1 does not require an arbitrary sequence such as:

    7 days before
    3 days before
    24 hours before
    2 hours before
    30 minutes before

Additional or recurring reminder schedules may be introduced later.

The Phase 1 requirement is satisfied by supporting at least one meaningful
pre-Appointment reminder.

---

### BR-70 — Reschedule proposal notifications are delivered only while the proposal is actionable

An `APPOINTMENT_RESCHEDULE_PROPOSED` notification is established only for a
Clinic-originated proposal on a `CONFIRMED` base (BR-15). A Clinic proposal on
a `REQUESTED` base uses `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` instead
(BR-71).

Immediately before each delivery, the proposal must still be actionable under
the single authoritative definition of `SPEC-APT-005` BR-31. Delivery is
suppressed once the proposal is accepted or withdrawn (`SPEC-APT-016`), the
Appointment is cancelled or otherwise no longer `CONFIRMED`, a Clinical
Encounter exists, the base confirmed scheduling context was superseded, the
proposing User lost the authority of the proposing context, or the base or
proposed time has passed.

Delivery must use that authoritative definition rather than a separately
maintained partial condition.

Current scheduling feasibility and Guardian current acceptability
(`SPEC-APT-005` BR-34, BR-35) are not delivery conditions: a proposal that is
actionable but currently infeasible or not currently acceptable remains
eligible. Its creation required feasibility, both values can change back, and a
suppressed delivery is final, so a temporary scheduling or Entitlement
condition must not permanently discard a valid proposal notification.

Withdrawing a proposal creates no Communication in Phase 1 (`SPEC-APT-016`
BR-10).

---

### BR-71 — A Clinic alternative time for a request produces its own notification

When the Clinic creates an Alternative Time proposal for a `REQUESTED`
Appointment (`SPEC-APT-018`), one `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED`
Communication is established for each Guardian who is current when the
proposal is created (§5), in the same operation as the proposal.

It must not reuse `APPOINTMENT_RESCHEDULE_PROPOSED`, whose meaning — a change
to an already confirmed Appointment — would be false here.
`APPOINTMENT_RESCHEDULE_PROPOSED` and `APPOINTMENT_RESCHEDULE_ACCEPTED` keep
their confirmed-workflow meaning unchanged.

The Communication references the proposal through the same Reschedule
Proposal reference used by `APPOINTMENT_RESCHEDULE_PROPOSED`; no second
proposal reference is introduced. It references no Schedule Revision and no
Lifecycle Event.

Its content must make clear that:

- the Clinic proposes another time for the Guardian's **request**;
- the Appointment is **not yet confirmed**, and accepting the proposal does
  not confirm it;
- the proposed date and time is a proposal, not the current requested time.

Push content follows BR-35: it stays privacy-minimized and must not state or
imply that the Appointment is confirmed. Opening the notification never
accepts the proposal (BR-16, BR-42); acceptance requires `SPEC-APT-019`.

---

### BR-72 — Alternative time notifications are delivered only while the proposal is actionable

Immediately before each delivery, the proposal must still be actionable under
`SPEC-APT-018` BR-17, using the same single authoritative actionability
definition as BR-70.

Delivery is therefore suppressed once the proposal is accepted
(`SPEC-APT-019`) or withdrawn (`SPEC-APT-016`); once it is `VOID` because a
Guardian rescheduled the request, the Clinic confirmed the request, or the
Appointment was cancelled or expired; once the base requested start or the
proposed start has passed; or once the proposing User lost continuous Clinic
authority. Recipient eligibility follows the existing current-Guardianship
rules (BR-6, BR-7).

As in BR-70, current scheduling feasibility and Guardian current acceptability
are not delivery conditions.

---

### BR-73 — No Communication for acceptance or withdrawal of an alternative time

Phase 1 creates no Communication when:

- a Guardian accepts a Clinic alternative time (`SPEC-APT-019` BR-13): no
  Guardian notification and no Clinic-side notification;
- the Clinic withdraws it (`SPEC-APT-016` BR-10).

A later confirmation of the request produces the ordinary
`APPOINTMENT_CONFIRMED` notification (BR-12), whether the confirmed time is
the originally requested time or an accepted alternative. A cancellation
produces the ordinary `APPOINTMENT_CANCELLED` notification (BR-13). Expiry
produces none (`SPEC-APT-015` BR-13).

---

### BR-74 — Delivery capability must exist before the type is established

An environment must be able to render and deliver
`APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` — including its proposed date and time
taken from the referenced proposal — before the backend begins establishing
Communications of that type in that environment. The deployment order is
defined in `docs/COMMUNICATIONS_OPERATIONAL_POLICY.md`.

This is a deployment-sequencing constraint only; it does not change any
Appointment rule.

---

## 5. Guardian Recipient Policy

For Phase 1, the default Guardian recipient policy for material Appointment
events is:

    Pet
     ↓
    current active Guardians
     ↓
    applicable Appointment notification

For example:

    Luna
    ├── Maria — active Guardian
    └── Carlos — active Guardian

    Appointment confirmed
            ↓
    notify Maria
    notify Carlos

If Carlos's Guardianship later ends:

    Luna
    └── Maria — active Guardian

    Appointment cancelled later
            ↓
    notify Maria
    do not notify Carlos through former Guardianship

Historical requester attribution remains unchanged.

---

## 6. Clinic Recipient Policy

Clinic-side communication must be narrower than:

    notify every Organization Member

Potential recipients are determined from the applicable current professional
or operational context.

Conceptually:

    Appointment belongs to Clinic
              +
    User has applicable current responsibility
              ↓
    eligible Clinic-side recipient

The exact operational recipient groups may evolve without changing Appointment
identity.

---

## 7. Notification Information

Appointment notifications should support enough information for the recipient
to understand the event.

### Guardian-facing information may include

- Pet;
- Clinic;
- Appointment lifecycle event;
- relevant date and time;
- current assigned Veterinarian where appropriate;
- required User action where applicable.

### Clinic-facing information may include

- Pet identity required for scheduling;
- requesting Guardian context where appropriate;
- requested or confirmed scheduling information;
- Appointment lifecycle event;
- current professional Assignment where relevant.

Protected medical content is not implicitly included.

---

## 8. Scenarios

### Scenario: Requesting Guardian receives Appointment request confirmation

Given Maria is an active Guardian of Luna
And Maria validly requests an Appointment at Animalia Madrid Centro

When the request is created

Then Maria may receive an Appointment-request notification
And the message identifies the Appointment as `REQUESTED`
And the message does not imply Clinic confirmation

---

### Scenario: Second Guardian is informed of shared Pet Appointment

Given Maria and Carlos are active Guardians of Luna
And Maria requests an Appointment for Luna

When the applicable Guardian notification policy is applied

Then Maria may be notified
And Carlos may also be notified that Luna has a new Appointment request
And Maria remains identifiable as the requesting User
And Carlos is not represented as the requester

---

### Scenario: All current Guardians receive confirmation

Given Maria and Carlos are current Guardians of Luna
And Luna's Appointment becomes `CONFIRMED`

When confirmation notifications are dispatched

Then Maria may receive the confirmation
And Carlos may receive the confirmation
And both messages refer to the same Appointment
And no duplicate Appointment is created

---

### Scenario: Former Guardian does not receive later cancellation

Given Maria and Carlos were Guardians of Luna
And Maria requested Luna's Appointment
And Carlos's Guardianship later ends
And the Appointment is subsequently cancelled

When cancellation notifications are resolved

Then Maria may receive the cancellation notification
And Carlos does not receive it solely because he previously guarded Luna
And historical Appointment information still preserves Carlos's previous
relationship independently where relevant

---

### Scenario: New Guardian receives future events but not historical replay

Given Maria requested Luna's Appointment
And Carlos later becomes an active Guardian
And the Appointment was already confirmed before Carlos became Guardian

When Carlos becomes Guardian

Then the system need not replay the historical confirmation notification

When the Appointment is later rescheduled

Then Carlos may receive the new applicable rescheduling notification

---

### Scenario: Reschedule proposal notifies Guardians

Given Maria and Carlos are current Guardians of Luna
And Animalia proposes a new time for Luna's confirmed Appointment

When the proposal becomes valid

Then applicable current Guardians may receive an actionable notification
And the new time remains proposed rather than confirmed
And receiving the message does not accept the proposal

---

### Scenario: One Guardian accepts reschedule

Given Maria and Carlos both received the reschedule proposal
And Maria validly accepts it first

When Carlos later opens the earlier actionable notification

Then the Appointment already reflects the accepted authoritative schedule
And Carlos's old notification does not create a second reschedule

---

### Scenario: Clinic alternative time notifies Guardians of a request

Given Maria and Carlos are current Guardians of Luna
And Luna's Appointment is `REQUESTED` for 10:00
When the Clinic proposes 12:00 as an alternative time

Then Maria and Carlos each receive `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED`
And the message says the Clinic proposes another time for the request
And the message says the Appointment is not yet confirmed
And no `APPOINTMENT_RESCHEDULE_PROPOSED` Communication is created

---

### Scenario: Alternative time notification suppressed after confirmation

Given an `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication has not yet been delivered
And the Clinic confirms the originally requested time, making the proposal `VOID`

When delivery is attempted

Then delivery is suppressed

---

### Scenario: Acceptance of an alternative time sends nothing

Given Maria accepts the Clinic's alternative time

Then no Communication is created for the acceptance
And the Appointment remains `REQUESTED`

---

### Scenario: Appointment cancellation notifies current Guardians

Given Luna's confirmed Appointment is cancelled
And Maria and Carlos are current Guardians

When cancellation notifications are dispatched

Then both may be informed that the Appointment is cancelled
And the message no longer presents the Appointment as active

---

### Scenario: Completion notification does not imply finalized medical record

Given Luna receives veterinary care
And her Appointment becomes `COMPLETED`
And some clinical documentation remains `DRAFT`

When Maria receives an Appointment completion notification

Then the message may indicate that the Appointment was completed
And it does not claim that all medical documentation is finalized

---

### Scenario: No-show notification uses neutral operational language

Given Luna's Appointment validly becomes `NO_SHOW`

When current Guardians are notified

Then the message communicates the missed Appointment outcome
And it does not create a behavioral label or penalty for Luna or the Guardians

---

### Scenario: New request notifies authorized Clinic context

Given Maria requests an Appointment for Luna at Animalia Madrid Centro
And Carlos is an authorized scheduling actor for that Clinic
And Laura is only authorized for Animalia Getafe

When Clinic-side request notifications are evaluated

Then Carlos may receive the Madrid Appointment notification
And Laura does not receive it solely because both Clinics belong to Animalia

---

### Scenario: Reassigned Veterinarian notification follows current Assignment

Given Dr. Garcia was assigned to Luna's Appointment
And Dr. Lopez validly replaces her

When a later professional-specific Appointment notification is generated

Then Dr. Lopez may be the applicable current professional recipient
And Dr. Garcia's historical Assignment does not create permanent future
notification eligibility

---

### Scenario: Push fails but email succeeds

Given Luna's Appointment becomes `CONFIRMED`
And Maria has an eligible email destination
And Maria's current push destination fails

When communication is dispatched

Then the email may still succeed
And Luna remains `CONFIRMED`
And push failure does not invalidate the Appointment or email delivery

---

### Scenario: No push device exists

Given Carlos is a current Guardian of Luna
And Carlos has no eligible Push Registration
And applicable email communication remains available

When Luna's Appointment is confirmed

Then Carlos may receive email according to the communication policy
And absence of push capability does not affect Appointment state

---

### Scenario: Notification is stale when opened

Given Maria received a push saying Luna's Appointment is `CONFIRMED`
And the Appointment is later cancelled

When Maria opens the old notification

Then the application displays Luna's current `CANCELLED` Appointment
And the old push does not restore confirmed state

---

### Scenario: Notification deep link after Guardianship ends

Given Carlos received a notification about Luna while he was a Guardian
And Carlos's Guardianship later ends

When Carlos opens the old notification

Then current authorization is evaluated
And the old notification does not preserve Guardian Appointment access

---

### Scenario: Entitlement loss cancellation still notifies Guardians

Given Luna has an existing confirmed Appointment at Animalia
And Animalia later loses normal professional Entitlement
And the Clinic validly cancels the existing Appointment through safe resolution

When the cancellation succeeds

Then current Guardians may receive the cancellation notification
And Entitlement loss does not prevent necessary communication about the
existing obligation

---

### Scenario: Clinic unpublication does not suppress existing Appointment cancellation

Given Animalia Madrid Centro becomes unpublished
And Luna still has an existing Appointment there
And the Appointment is validly cancelled

When the cancellation occurs

Then applicable current Guardians may still receive transactional cancellation
communication
And public Discovery state does not suppress necessary existing Appointment
communication

---

### Scenario: Current Guardians receive upcoming Appointment reminder

Given Luna has a future `CONFIRMED` Appointment
And Maria and Carlos are current Guardians of Luna
And the Appointment reaches the configured reminder point

When the Appointment reminder is dispatched

Then Maria may receive the reminder
And Carlos may receive the reminder
And the reminder refers to the same confirmed Appointment
And the Appointment lifecycle remains unchanged

---

### Scenario: Cancelled Appointment does not receive scheduled reminder

Given Luna previously had a `CONFIRMED` Appointment
And a reminder had been expected before the scheduled time
And the Appointment is cancelled before the reminder is dispatched

When reminder eligibility is evaluated

Then the normal upcoming Appointment reminder is not sent as though the
Appointment were still confirmed

---

### Scenario: Rescheduled Appointment uses new reminder time

Given Luna has a confirmed Appointment for Monday at 10:00
And the Appointment is validly rescheduled to Tuesday at 17:00

When future reminder eligibility is evaluated

Then reminder behavior follows Tuesday at 17:00
And the previous Monday scheduling time does not remain the basis for the
normal reminder

---

### Scenario: Former Guardian does not receive future reminder

Given Carlos was a Guardian of Luna when the Appointment was confirmed
And Carlos's Guardianship ends before the configured reminder point

When the reminder is dispatched

Then Carlos does not receive the private Appointment reminder solely because of
his former Guardianship
And current Guardians remain eligible according to the applicable policy

---

### Scenario: Reminder failure does not cancel Appointment

Given Luna has a valid `CONFIRMED` Appointment
And the configured reminder delivery fails

When the communication failure occurs

Then Luna's Appointment remains `CONFIRMED`
And the current Appointment remains visible through the application

---

### Scenario: Reminder delivery does not confirm attendance

Given Maria receives Luna's Appointment reminder

When the notification is delivered or opened

Then the system does not infer that Maria confirmed attendance
And the Appointment remains governed by its existing lifecycle

---

## 9. Appointment Event vs Notification Event

The lifecycle remains:

    Appointment event
          ↓
    notification event
          ↓
    channel delivery attempts

For example:

    Appointment CANCELLED
          ↓
    Guardian cancellation notification
          ↓
    ├── email
    └── push

One Appointment cancellation may therefore produce several communication
attempts without becoming several cancellation events.

---

## 10. Shared Guardians

The Phase 1 rule intentionally favors shared awareness.

If several Users are current Guardians of the same Pet, material Appointment
changes may be communicated to all of them.

This follows the existing domain model:

    multiple Guardians
            ↓
    one Pet
            ↓
    one shared Appointment history

It avoids creating a hidden situation where:

    Maria knows Luna's Appointment was moved

while:

    Carlos remains an equally authorized Guardian
    but receives no awareness solely because Maria created the Appointment.

The original requester remains historically identifiable.

---

## 11. Privacy Boundary

Appointment notifications should communicate operational information rather
than detailed clinical information.

A push notification may say:

    Luna's appointment has been confirmed.

The authenticated application may then provide:

    Clinic
    date
    time
    assigned Veterinarian
    other authorized Appointment information

Sensitive medical information remains protected behind current authentication
and authorization.

---

## 12. Edge Cases

### Guardian intentionally wants fewer notifications

A future User preference model may allow some non-mandatory notification
categories to be disabled.

The exact preference behavior is outside this Specification.

---

### Two Guardians perform conflicting actions from notifications

The Appointment domain remains authoritative.

Only operations valid against the current lifecycle state may succeed.

The notification itself provides no locking or permanent right to perform the
action.

---

### Notification arrives after Appointment was changed again

The message may be stale.

Current application state always wins.

---

### User receives both email and push

This represents multi-channel delivery of one logical notification context, not
two Appointment events.

---

### User has several push devices

The same logical Appointment notification may produce several technical push
deliveries.

The Appointment event remains singular.

---

### Clinic has many operational staff members

Phase 1 must not blindly broadcast every Appointment event to every
Organization Member.

Recipient eligibility must follow current operational responsibilities.

---

### Several current Guardians share one email address

Recipient identity and delivery address are separate concerns.

The system must avoid treating a shared address as evidence that two domain
Users are the same User.

---

## 13. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-006 — Organization Membership is temporal.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 14. Dependencies

Communication channels:

- SPEC-COM-001 — Send Transactional Email
- SPEC-COM-002 — Send Push Notification

Appointment lifecycle:

- SPEC-APT-001 — Request Appointment
- SPEC-APT-002 — Confirm Appointment
- SPEC-APT-003 — Cancel Appointment
- SPEC-APT-004 — Reschedule Requested Appointment
- SPEC-APT-005 — Propose Confirmed Appointment Reschedule
- SPEC-APT-006 — Accept Appointment Reschedule Proposal
- SPEC-APT-007 — Assign Veterinarian to Appointment
- SPEC-APT-008 — Reassign Veterinarian
- SPEC-APT-009 — Complete Appointment
- SPEC-APT-010 — Mark Appointment No-Show
- SPEC-APT-011 — View Guardian Appointments
- SPEC-APT-012 — View Clinic Appointment Schedule
- SPEC-APT-015 — Expire Unconfirmed Appointment Request
- SPEC-APT-016 — Withdraw Clinic Reschedule Proposal
- SPEC-APT-018 — Propose Alternative Time for Requested Appointment
- SPEC-APT-019 — Accept Requested Appointment Alternative Time

Guardianship:

- SPEC-PET-003 — Accept Guardianship Invitation

Safe resolution after commercial changes:

- SPEC-SUB-004 — Handle Loss of Professional Entitlements

---

## 15. Out of Scope

This Specification does not define:

- exact notification wording;
- notification template implementation;
- exact email provider;
- exact push provider;
- marketing communications;
- multiple configurable reminder sequences;
- recurring reminder campaigns;
- attendance confirmation from reminder delivery;
- adaptive reminder timing;
- reminder timing based on no-show risk;
- SMS;
- WhatsApp;
- read receipts;
- Guardian acknowledgement tracking;
- notification inbox UI;
- notification preference UI;
- per-Guardian custom Appointment visibility;
- penalties for no-show;
- staff-wide broadcast behavior;
- service-specific notifications;
- medical-result notifications.

---

## 16. Verification Notes

Verification must demonstrate that:

1. Appointment notifications follow valid authoritative Appointment events;
2. notification failure does not rollback Appointment lifecycle;
3. material Guardian notifications may target all current Guardians of the
   Pet;
4. the requesting Guardian is not assumed to be the only notification
   recipient;
5. requester attribution remains preserved when other Guardians are notified;
6. former Guardians do not receive future notifications solely from historical
   Guardianship;
7. new Guardians need not receive replay of historical notifications but may
   receive future applicable events;
8. requested and confirmed Appointment communications remain distinguishable;
9. confirmation, cancellation, reschedule, completion, and no-show events may
   produce appropriate Guardian notifications;
10. receiving a reschedule proposal notification does not accept the proposal;
11. stale actionable notifications cannot override current Appointment state;
12. Clinic-side notifications remain scoped to applicable Clinic or
    Organization responsibility;
13. Organization Membership alone does not make every Member a Clinic
    notification recipient;
14. current professional Assignment may determine professional-specific
    notification eligibility;
15. notification content preserves Pet and Clinic context;
16. push and email channels remain independent;
17. failure of one communication channel does not invalidate another;
18. Appointment state remains available in the application even if all
    external notification delivery fails;
19. notification delivery or opening does not prove acknowledgement;
20. deep links require current authentication and authorization;
21. notifications minimize protected medical information;
22. duplicate technical deliveries do not duplicate Appointment events;
23. safe Appointment resolution after Entitlement loss may still communicate
    the resulting outcome;
24. Clinic unpublication does not suppress required communication about
    existing Appointments;
25. communication history remains separate from Appointment history.
26. future confirmed Appointments may generate at least one pre-Appointment
    reminder according to configurable policy;
27. reminders are only sent when the Appointment remains eligible and
    confirmed;
28. cancellation prevents an obsolete normal reminder from being dispatched;
29. rescheduling moves future reminder relevance to the new authoritative
    confirmed time;
30. reminder recipients follow current Guardianship at dispatch time;
31. reminder delivery does not modify Appointment state or prove attendance;
32. reminder failure does not modify or cancel the Appointment;
33. a Clinic Alternative Time proposal establishes exactly one
    `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` Communication per current Guardian
    at proposal creation, referencing the proposal and no revision or
    Lifecycle Event, and no `APPOINTMENT_RESCHEDULE_PROPOSED` Communication;
34. a Clinic proposal on a `CONFIRMED` base still establishes
    `APPOINTMENT_RESCHEDULE_PROPOSED` and never the new type;
35. a Guardian who is not current at proposal creation receives no
    alternative-time Communication, and a Guardian whose Guardianship ends
    receives no further delivery;
36. delivery of `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` is suppressed after
    acceptance, withdrawal, Guardian reschedule, confirmation, cancellation,
    expiry, a passed base or proposed start, or loss of proposer authority;
37. Guardian acceptance and Clinic withdrawal of an alternative time create no
    Communication;
38. a stale or otherwise rejected proposal creates no Communication;
39. alternative-time email content states that the Appointment is not yet
    confirmed, and push content does not imply confirmation;
40. a reschedule or alternative-time proposal notification remains eligible for
    delivery while its proposal is actionable, even when the proposal is not
    currently feasible or not currently acceptable (BR-70, BR-72).

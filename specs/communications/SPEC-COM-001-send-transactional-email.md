# SPEC-COM-001 — Send Transactional Email

**Status:** APPROVED  
**Requirements:** REQ-COM-001  
**Domain:** Communications  
**Priority:** P1

## 1. Intent

Allow the system to send transactional email when an approved domain or
Identity workflow requires communication with a User or intended recipient.

Transactional email supports product operations such as:

- email-address verification;
- Organization Invitations;
- account recovery;
- Appointment-related communication;
- other explicitly defined transactional workflows.

An email communicates information about a domain operation.

It must not become the authoritative source of truth for the domain state that
caused the communication.

---

## 2. Preconditions

- A supported transactional communication trigger exists.
- The intended recipient or delivery address can be determined.
- The communication type is supported.
- The system has enough trusted information to construct the applicable
  transactional message.
- The communication does not expose information beyond the recipient's
  permitted context.
- Where the email contains a sensitive action link or token, that authorization
  has been created according to the applicable Identity or domain
  Specification.

---

## 3. Business Rules

### BR-1 — Transactional email is caused by an explicit product event

A transactional email must correspond to an approved Identity, domain, or
operational event.

The system must not send transactional email merely because arbitrary
application code requests an email without an applicable product context.

---

### BR-2 — Email is not the source of domain truth

The email must describe or support a domain state.

It must not become the authoritative record of that state.

For example:

    Organization Invitation
        ↓
    transactional email

not:

    email exists
        ↓
    therefore Organization Invitation exists

The Organization Invitation remains the domain entity.

---

### BR-3 — Sending an email must not recreate the originating domain operation

Retrying email delivery must not:

- create another Organization Invitation;
- create another Appointment;
- repeat an Appointment lifecycle transition;
- create another recovery authorization;
- duplicate another originating domain action.

Communication retry and domain command execution are separate concerns.

---

### BR-4 — Transactional email must be distinguishable by communication type

The system must preserve enough information to distinguish materially different
transactional email purposes.

Examples may include:

    EMAIL_VERIFICATION
    ORGANIZATION_INVITATION
    ACCOUNT_RECOVERY
    APPOINTMENT_REQUESTED
    APPOINTMENT_CONFIRMED
    APPOINTMENT_CANCELLED
    APPOINTMENT_RESCHEDULE_PROPOSED
    APPOINTMENT_RESCHEDULE_ACCEPTED
    APPOINTMENT_ALTERNATIVE_TIME_PROPOSED
    APPOINTMENT_COMPLETED
    APPOINTMENT_NO_SHOW

The exact technical identifiers may evolve.

---

### BR-5 — Communication type must not determine domain state by itself

A message classified as:

    APPOINTMENT_CONFIRMED

must only be sent because the Appointment has validly reached the applicable
confirmed state.

Creating that communication record must not itself confirm the Appointment.

---

### BR-6 — Recipient must be explicitly derivable from the workflow

The intended recipient must come from the applicable product context.

The system must not infer arbitrary recipients from unrelated account,
Organization, Guardian, or professional information.

---

### BR-7 — Recipient email and domain User are distinct concepts

A transactional email may target:

- an existing User;
- a person who does not yet have a platform account.

Therefore, the recipient email address must not always be treated as a domain
User identity.

This is particularly relevant to Invitation workflows.

---

### BR-8 — Email delivery does not create a User

Sending an email to a person without an account must not create a domain User
solely because the email was sent.

Registration remains governed by the Identity Specifications.

---

### BR-9 — Email delivery does not establish recipient identity proof

Successful technical delivery to an email address does not by itself establish
that a particular authenticated User has proven control of that address.

Where proof of control is required, the applicable Identity or Invitation
workflow determines that proof.

---

### BR-10 — Sensitive authorization must remain server-controlled

Where an email contains a link or reference used for:

- email verification;
- account recovery;
- Invitation acceptance;
- another sensitive operation;

the authorization represented by that mechanism must be validated through
trusted infrastructure.

The email content itself must not bypass the applicable authorization rules.

---

### BR-11 — Sensitive links must not encode unnecessary protected information

Transactional URLs or references must avoid embedding unnecessary information
such as:

- Pet medical information;
- diagnoses;
- Organization billing information;
- internal authorization metadata;
- sensitive personal data.

The minimum information required to perform the intended workflow should be
used.

---

### BR-12 — Expiration belongs to the underlying authorization

Where a transactional email communicates an expiring operation, the applicable
expiration belongs to the underlying:

- verification authorization;
- Invitation;
- recovery authorization;
- other domain or security object.

Deleting or resending the email must not silently extend that validity period.

---

### BR-13 — Resending communication must not automatically extend authorization

If the product allows a transactional email to be resent for an existing valid
operation, the resend must not automatically:

- create a new domain object;
- restart the original validity period;
- change the original business state.

If a new authorization is required, that must be an explicit domain operation.

---

### BR-14 — Delivery success does not imply workflow completion

An email being technically delivered must not imply that the recipient:

- verified their email;
- accepted an Organization Invitation;
- recovered their account;
- read an Appointment update;
- accepted a reschedule.

Workflow completion requires its applicable explicit domain behavior.

---

### BR-15 — Delivery failure does not fabricate domain rollback

If a domain operation succeeds but the corresponding email cannot be delivered,
the system must not silently rewrite the successful domain operation as though
it never occurred unless that workflow explicitly requires atomic
communication.

For example:

    Appointment confirmed
        ↓
    confirmation email fails

must not ordinarily become:

    Appointment not confirmed

The Appointment domain state remains authoritative.

---

### BR-16 — Communication failure must remain detectable

A required transactional email must not silently disappear without any
operationally detectable failure state.

The system must be capable of distinguishing communication outcomes such as:

    pending
    sent
    failed

where needed.

Exact persistence and retry representation are architectural.

---

### BR-17 — Retriable delivery failure may be retried

Transient email-delivery failure may be retried without repeating the
originating domain action.

The exact retry strategy, backoff policy, and delivery provider behavior are
architectural.

---

### BR-18 — Permanent delivery failure must not retry indefinitely

Where delivery is determined to be permanently impossible or invalid, the
system must avoid uncontrolled infinite retry behavior.

The exact retry and dead-letter strategy is architectural.

---

### BR-19 — Communication status and domain state remain separate

The system must not collapse:

    Appointment state = CONFIRMED

and:

    confirmation email state = FAILED

into one shared state.

Both facts may simultaneously be true.

---

### BR-20 — Transactional email must minimize sensitive information

Email is not an appropriate place to expose unrestricted protected information.

Messages should contain only the information required for the transactional
purpose.

---

### BR-21 — Full medical records must not be included in ordinary transactional email

The system must not place complete protected medical history, Clinical
Attachments, or detailed clinical records directly into ordinary transactional
email unless a future explicitly approved secure-sharing workflow requires it.

---

### BR-22 — Appointment email should contain operationally necessary information only

Appointment-related email may contain information such as:

- Pet-facing identifier or name where appropriate;
- Clinic;
- Appointment lifecycle update;
- relevant date and time;
- necessary action instructions.

It must not automatically include unrelated medical history.

---

### BR-23 — Professional recipients receive only their applicable context

A professional transactional email must not expose information belonging to
another Clinic or Organization merely because the same User participates in
several professional contexts.

The communication must preserve the applicable Organization and Clinic scope.

---

### BR-24 — Shared Guardians do not imply every email goes to every Guardian

The existence of several Guardians for one Pet must not automatically mean that
every transactional email is sent to all Guardians.

The applicable workflow determines the intended recipients.

For example, an Appointment communication may need to notify:

- the requesting Guardian;
- another affected Guardian;
- all current Guardians;

depending on the explicitly approved Appointment notification policy.

That policy is defined separately by `SPEC-COM-003`.

---

### BR-25 — Email address changes must not rewrite historical communication meaning

If a User later changes their supported communication address through an
approved Identity workflow, previous transactional communication history must
not be rewritten as though it had originally been sent to the new address.

---

### BR-26 — Communication recipient address may be preserved for traceability

Where operationally required, the system may preserve the delivery address used
for a transactional email.

That address remains sensitive information and must be appropriately
protected.

---

### BR-27 — Transactional email is not marketing consent

The ability to send an operational transactional email must not automatically
grant permission to send marketing or promotional communication.

Transactional and marketing communication are separate concerns.

---

### BR-28 — Marketing preferences must not block mandatory security communication

Future marketing opt-out behavior must not prevent transactional security or
account communications that are required to operate the requested account
workflow.

---

### BR-29 — Email templates must not define business logic

Message templates may control presentation and wording.

They must not become the authoritative implementation of domain conditions.

For example, whether an Appointment is cancelled must be decided by the
Appointment domain, not by whether a cancellation template was selected.

---

### BR-30 — Localization may change presentation but not communication meaning

Transactional email may be localized into supported languages.

Localization must not change the underlying:

- domain event;
- recipient;
- authorization;
- lifecycle state.

---

### BR-31 — Missing localization must not create another domain event

Fallback to another supported language must not duplicate or change the
originating domain operation.

---

### BR-32 — Communication sending occurs through trusted infrastructure

Transactional email must be initiated or validated through trusted backend
infrastructure.

A manipulated client must not be able to send authoritative transactional
messages pretending that unsupported domain events occurred.

---

### BR-33 — Client must not choose arbitrary authoritative communication type

The client may initiate an applicable product operation.

It must not independently assert:

    send APPOINTMENT_CONFIRMED email

when the Appointment is not actually confirmed.

Trusted infrastructure must derive the communication from valid domain state.

---

### BR-34 — Provider-specific message identifiers are not domain identities

An external email provider may return identifiers for:

- message;
- delivery;
- request;
- event.

Those identifiers are integration metadata.

They must not become the primary identity of the originating domain operation.

---

### BR-35 — Email provider does not become source of domain state

A provider delivery webhook may update communication-delivery information.

It must not independently rewrite domain state such as:

- Appointment lifecycle;
- Organization Membership;
- Guardianship;
- Care Authorization.

---

### BR-36 — Duplicate provider callbacks must be idempotent

Repeated delivery or failure callbacks from the email provider must not create
duplicate communication outcomes or duplicate originating domain events.

The exact idempotency mechanism is architectural.

---

### BR-37 — Out-of-order provider callbacks must not corrupt final delivery state

The architecture must tolerate provider events arriving out of order.

A stale provider event must not blindly overwrite a newer authoritative
delivery outcome.

---

### BR-38 — Communication history may be operationally auditable

The system should be capable of determining, where required:

- which communication type was attempted;
- intended recipient;
- originating domain context;
- when delivery was attempted;
- delivery outcome.

This is communication auditability.

It is distinct from Medical Access Audit Events.

---

### BR-39 — Communication logs must not duplicate sensitive payload unnecessarily

Operational logging must avoid storing full message bodies or sensitive action
links where that information is unnecessary for diagnostics.

---

### BR-40 — Subscription loss does not erase historical transactional communication

Changes in Veterinary Organization Subscription or Entitlement must not
destructively erase transactional communication history that must be preserved
for operational or security reasons.

---

### BR-41 — Communication failure must not corrupt originating domain state

A failed communication operation must not leave the originating domain entity
in a partial or contradictory state.

---

### BR-42 — Domain operation and communication dispatch require reliable handoff

When an approved domain transition requires transactional communication, the
architecture must provide a reliable way to ensure that the communication
request is not silently lost after the domain operation succeeds.

The exact consistency mechanism is architectural.

Possible implementations may include durable events, transactional outbox, or
another reliable handoff mechanism.

This Specification does not choose the implementation.

---

### BR-43 — Organization Invitation link target

The Organization Invitation email contains exactly one protected action link:

    {public app base URL}/invitations/organization/accept?invitation=<invitation_id>#secret=<secret>

- `invitation_id` is the Invitation reference; it proves nothing by itself
  (`SPEC-ORG-002` BR-21).
- The bearer secret is carried only in the URL fragment, so that it is not sent
  to the web origin when the link is opened in a browser.
- The public app base URL is deployment configuration; for Production it is
  `https://app.menizvet.com`.
- The link target is handled by the mobile route of `SPEC-ORG-003` §12.
  Opening the link does not accept the Invitation; acceptance is an explicit,
  authenticated action.

The email contains no other Invitation authorization metadata, no intended
responsibility internals beyond human-readable context, and no
`recipient_user_id`.

---

### BR-44 — The Invitation credential is delivered once

The Invitation secret exists outside the database only in trusted backend
memory and, encrypted, in the Invitation Communication's delivery envelope
(`ADR-008`). Once the email provider accepts the Invitation email, the
encrypted secret is erased from the envelope.

Consequently the Invitation email cannot be re-rendered with the same secret
after delivery. Resending Invitation communication is not part of Staff access
lifecycle Phase 1. To give a recipient a new link, an administrator revokes the
pending Invitation (`SPEC-ORG-010`) and creates a new one (`SPEC-ORG-002`).

---

### BR-45 — No delivery for an Invitation that is no longer pending

An Invitation Communication that has not yet been handed to the email provider
is not delivered once its Invitation is revoked, expired, rejected, or
accepted. Such suppression changes no domain state.

An email already accepted by the provider cannot be recalled; its link is then
rejected by acceptance (`SPEC-ORG-003` BR-20).

---

### BR-46 — Invitation acceptance and revocation create no Communication

Accepting (`SPEC-ORG-003`) or revoking (`SPEC-ORG-010`) an Organization
Invitation creates no Transactional Communication, does not duplicate the
Invitation Communication, and does not re-render or resend the Invitation
email.

Staff access lifecycle Phase 1 introduces no new Communication type.

Acceptance verifies the bearer secret inside the authenticated trusted
acceptance operation by comparing its one-way digest; acceptance does not
require the Communications Edge Function or the encrypted envelope.

---

## 4. Transactional Communication Information

Where communication tracking is required, the system should support enough
information to identify the communication without making email the domain
source of truth.

### Core information

- communication identity;
- communication type;
- originating domain context or reference;
- intended recipient;
- creation time;
- delivery state.

### Where applicable

- delivery attempt time;
- external provider reference;
- failure classification;
- localization context.

Sensitive tokens or complete protected message content should not be retained
unless explicitly required.

---

## 5. Scenarios

### Scenario: Send email verification communication

Given Maria has registered
And Maria requires email verification
And a valid verification authorization exists

When the verification communication is dispatched

Then the email may contain the applicable verification action
And sending the email does not itself verify Maria's account
And the verification workflow remains authoritative

---

### Scenario: Organization Invitation email does not create Membership

Given Animalia Veterinary Group has a valid pending Organization Invitation for
Carlos

When the Invitation email is sent to Carlos

Then the existing Invitation remains the domain source of truth
And no Organization Membership is created solely because the email was sent

---

### Scenario: Person without account receives Invitation

Given Animalia has created an Organization Invitation for a person who does not
yet have an account

When the transactional email is sent

Then no domain User is created solely because of email delivery
And the intended recipient may later complete the applicable Identity workflow

---

### Scenario: Account recovery email does not recover account by itself

Given Maria has a valid account recovery authorization

When the recovery email is delivered

Then Maria's account is not considered recovered solely because delivery
succeeded
And recovery requires successful completion of `SPEC-ID-005`

---

### Scenario: Appointment confirmation email follows confirmed state

Given Luna's Appointment validly transitions to `CONFIRMED`

When the applicable transactional communication is created

Then a confirmation email may be sent
And the email reflects the confirmed Appointment
And the communication does not perform the Appointment confirmation itself

---

### Scenario: Confirmation email fails after Appointment confirms

Given Luna's Appointment has validly become `CONFIRMED`
And the corresponding email provider temporarily fails

When email delivery fails

Then Luna's Appointment remains `CONFIRMED`
And the communication failure remains detectable
And the email may be retried without confirming the Appointment again

---

### Scenario: Resending Invitation email does not extend Invitation validity

Given Carlos has a pending valid Organization Invitation
And the Organization resends its communication

When the email is resent

Then the existing Invitation remains the same domain entity
And its validity period is not silently restarted solely because of the resend

Resending is deferred in Staff access lifecycle Phase 1 (BR-44); this scenario
constrains any future resend workflow.

---

### Scenario: Revoked Invitation email is not delivered

Given Animalia created an Organization Invitation for Laura
And its email has not yet been handed to the email provider

When an authorized administrator revokes the Invitation

Then the Invitation email is not delivered
And no new Communication is created

---

### Scenario: Transactional email contains no full medical history

Given Luna has protected medical history
And Maria receives an Appointment confirmation email

When the message is generated

Then the email does not include Luna's complete medical history
And Appointment communication remains operationally scoped

---

### Scenario: Manipulated client cannot send false cancellation email

Given Luna's Appointment remains `CONFIRMED`
And a manipulated client attempts to request an authoritative
`APPOINTMENT_CANCELLED` communication

When trusted communication dispatch is evaluated

Then the false cancellation message is not generated as authoritative
communication
And the Appointment remains `CONFIRMED`

---

### Scenario: Duplicate provider callback is harmless

Given the email provider already reported successful delivery for a
transactional email

When the same provider event is delivered again

Then no duplicate domain operation is performed
And communication state remains coherent

---

### Scenario: Failed communication does not expose sensitive token in logs

Given an account recovery email cannot be delivered

When operational failure information is recorded

Then diagnostics may record the delivery failure
And the recovery secret need not be copied into ordinary application logs

---

### Scenario: User belongs to several Organizations

Given Dr. Garcia belongs to Animalia and VetCare
And Animalia generates an Organization-specific transactional communication

When the email is created

Then the message reflects the Animalia context
And unrelated VetCare private information is not included

---

### Scenario: Subscription termination preserves communication history

Given Animalia previously sent transactional Appointment communications

When Animalia's Subscription later expires

Then required historical communication information remains preserved
And commercial expiration does not rewrite previous delivery history

---

## 6. Transactional Email vs Domain Event

These are distinct:

    domain event
        ↓
    communication requested
        ↓
    email delivery attempted

For example:

    Appointment CONFIRMED
        ↓
    confirmation communication
        ↓
    delivered / failed / retried

The Appointment remains `CONFIRMED` regardless of whether the recipient's email
provider temporarily accepted the message.

---

## 7. Transactional Email vs Sensitive Action

For workflows such as verification or recovery:

    transactional email
        ↓
    delivers access to an action

but:

    trusted backend validation
        ↓
    authorizes and performs the action

The email must never be treated as the security boundary by itself.

---

## 8. Delivery Reliability

Transactional communication may happen after a successful domain operation.

The architecture must therefore prevent this failure pattern:

    Appointment confirmed in database
        ↓
    application crashes
        ↓
    communication request disappears forever

The system needs a durable handoff between domain state and communication
dispatch.

This Specification requires the reliability property.

It does not prescribe the mechanism.

---

## 9. Edge Cases

### Recipient mailbox is full

The originating domain operation remains authoritative.

Delivery may fail and follow the configured retry or failure workflow.

---

### Recipient address is invalid

The communication may reach a permanent failure state.

The system must not rewrite the originating domain operation solely because the
address was invalid.

---

### Email provider is temporarily unavailable

Transactional communication may remain pending and be retried.

Provider unavailability must not itself create another domain event.

---

### User receives message after state changes again

Email delivery is asynchronous.

For example:

    Appointment confirmed
        ↓
    confirmation email queued
        ↓
    Appointment cancelled
        ↓
    confirmation email arrives late

The product should avoid misleading stale communication where practical.

The exact cancellation, ordering, deduplication, or supersession strategy is
architectural and may vary by communication type.

---

### Communication is delayed

Delivery timestamp and originating domain-event timestamp may differ.

The email must not rewrite the time at which the underlying domain event
actually occurred.

---

### Recipient forwards transactional email

Forwarding a message must not transfer domain authorization.

Sensitive actions still require the applicable recipient and authorization
checks.

---

## 10. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-006 — Organization Membership is temporal.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

Identity-related transactional email may depend on:

- SPEC-ID-001 — Register User
- SPEC-ID-002 — Verify Email Address
- SPEC-ID-005 — Recover Account Access

Organization Invitation email may depend on:

- SPEC-ORG-002 — Invite User to Organization
- SPEC-ORG-003 — Accept Organization Invitation
- SPEC-ORG-010 — Revoke Organization Invitation

Appointment communication may depend on the applicable Appointment
Specifications.

Detailed Appointment notification behavior is defined separately by:

- SPEC-COM-003 — Send Appointment Notifications

---

## 12. Out of Scope

This Specification does not define:

- marketing email;
- newsletters;
- promotional communication;
- email provider selection;
- email provider API;
- template-engine implementation;
- exact email wording;
- localization catalogue;
- retry intervals;
- maximum retry count;
- dead-letter implementation;
- transactional outbox implementation;
- queue technology;
- SMTP configuration;
- bounce-management UI;
- changing a User's authentication email;
- push notifications;
- Appointment-specific notification recipient policy.

---

## 13. Verification Notes

Verification must demonstrate that:

1. supported transactional domain and Identity events may generate
   transactional email;
2. email does not become the source of truth for the originating domain state;
3. communication retries do not repeat the originating domain operation;
4. delivery success does not imply workflow completion;
5. delivery failure does not silently rollback a successful domain operation;
6. communication failure remains detectable;
7. transient failure may be retried independently;
8. Invitation email does not create User or Membership;
9. verification email does not verify the account by itself;
10. recovery email does not complete account recovery by itself;
11. sensitive actions remain validated through trusted infrastructure;
12. message content follows data-minimization principles;
13. ordinary transactional email does not expose complete medical history;
14. communication is Organization- and Clinic-scoped where applicable;
15. transactional email remains separate from marketing consent;
16. templates and provider callbacks do not define domain state;
17. manipulated clients cannot fabricate authoritative communication events;
18. duplicate provider events do not duplicate domain operations;
19. communication history may remain operationally traceable without storing
    unnecessary sensitive payload;
20. Subscription termination does not erase required communication history;
21. failed communication does not corrupt originating domain state;
22. required domain-to-communication handoff cannot be silently lost;
23. the Organization Invitation email link targets
    `/invitations/organization/accept` with the Invitation reference in the
    query and the secret only in the fragment;
24. an undelivered Invitation email is not delivered after the Invitation is
    revoked, expired, rejected, or accepted;
25. Invitation acceptance and revocation create no Communication;
26. the Invitation secret is erased from the delivery envelope after provider
    acceptance and is never persisted in plaintext.
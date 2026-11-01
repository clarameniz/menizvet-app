# Communications Operational Policy

Provider policy last reviewed: 2026-09-01.

## Purpose

This document records the current operational and provider policy for transactional
Communications.

It is not the authoritative source for domain behavior.

Requirements, Specifications, ADRs and migrations remain authoritative for domain and
technical invariants.

Values in this document such as provider choice, limits, schedules, retry intervals and
commercial tiers may change without redefining Communication identity or domain
semantics.

## Phase 1 scope

Phase 1 supports:

- transactional email;
- Push Notifications;
- Organization Invitation email;
- Guardianship Invitation email;
- Guardian-facing material Appointment notifications;
- one configurable pre-Appointment reminder.

Phase 1 does not provide:

- marketing Communications;
- SMS or WhatsApp;
- User-managed notification preferences;
- notification inbox;
- read receipts or acknowledgements;
- repeated reminder campaigns;
- Clinic-side Appointment notifications without an approved recipient policy;
- medical-result notifications.

## Email provider

### Current Phase 1 provider

Resend.

The commercial plan is operational rather than architectural.

Use the Resend Free tier while actual traffic remains within its operational limits.
Upgrade to a paid Resend tier when measured usage or required reliability exceeds the
free-tier limits.

Do not encode a particular Resend commercial plan in database schema or ADRs.

### Why Resend was selected

AWS SES, Brevo and Resend were evaluated.

AWS SES has materially lower direct per-email cost.

Resend was selected for Phase 1 because it currently provides a better combination of:

- low implementation complexity from Supabase Edge;
- straightforward HTTPS API integration;
- documented provider-send idempotency;
- cryptographically authenticated webhooks;
- clear delivery/bounce/failure events;
- simple Supabase Auth custom-SMTP integration;
- lower operational and incident-management complexity.

Phase 1 prioritizes engineering reliability and low operational complexity over the
lowest possible marginal email cost.

### AWS SES as growth candidate

AWS SES remains the preferred cost-optimization candidate if email volume makes provider
cost material.

A future migration to SES should principally affect:

- email provider adapter;
- provider callback/event adapter;
- provider credentials and IAM;
- sending-domain configuration;
- Supabase Auth SMTP configuration;
- provider-specific retry and ambiguous-timeout handling.

It must not require redesigning:

- `transactional_communications`;
- `communication_delivery_attempts`;
- typed domain handoff;
- recipient resolution;
- Appointment notification semantics;
- reminders;
- Push Registration.

### Provider reevaluation triggers

Reevaluate the email provider when any of the following becomes material:

- actual email volume makes provider cost significant;
- Resend pricing or limits materially change;
- deliverability requirements change;
- provider reliability becomes inadequate;
- AWS infrastructure already exists for other project needs;
- operational maturity makes SES complexity acceptable;
- regulatory or regional-processing requirements change.

Provider pricing is time-sensitive operational information and must be rechecked before
a migration decision.

## Supabase Auth email

Supabase Auth remains authoritative for:

- email verification;
- account recovery.

These workflows do not create domain `transactional_communications`.

Phase 1 configures the selected transactional email provider as Supabase Auth custom
SMTP.

No duplicate verification or recovery token is created by the Communications domain.

## Push provider

Phase 1 provider:

Expo Push Service.

Rationale:

- aligned with the expected Expo/React Native client;
- avoids separate Phase-1 APNs and FCM server adapters;
- supports multiple device destinations;
- provides ticket and receipt semantics;
- keeps provider identity outside the Communications domain model.

The domain must remain replaceable with direct FCM/APNs or another provider later.

Expo provider tokens are private technical destinations and must never be exposed through
ordinary User/Profile reads or logs.

## Channel policy

### Invitations

Organization Invitation:
- email only.

Guardianship Invitation:
- email only.

### Appointment Communications

For approved Guardian-facing Appointment events:

- email is attempted when a trusted deliverable email address is available;
- Push is independently attempted for every eligible Push Registration.

Email and Push are parallel independent channels.

Push is not a prerequisite for email.

Email is not a fallback triggered by Push failure.

If only one channel is available, use the available channel.

Provider failure in either channel does not roll back the originating Appointment
operation.

Clinic-side notifications remain disabled until an exact approved recipient policy
exists.

## Appointment Communication types

Phase 1 supports:

- APPOINTMENT_REQUESTED
- APPOINTMENT_CONFIRMED
- APPOINTMENT_CANCELLED
- APPOINTMENT_RESCHEDULE_PROPOSED
- APPOINTMENT_RESCHEDULE_ACCEPTED
- APPOINTMENT_ALTERNATIVE_TIME_PROPOSED (specified by SPEC-COM-003 BR-71 to
  BR-74; implemented locally in 20261010090000 and the shared templates, not
  deployed — see "Deployment order" below)
- APPOINTMENT_COMPLETED
- APPOINTMENT_NO_SHOW
- APPOINTMENT_REMINDER

Assignment/reassignment notifications are not included in Phase 1.

Appointment request expiry (`SPEC-APT-015`) creates no Communication in Phase 1
and must never reuse `APPOINTMENT_CANCELLED`.

`APPOINTMENT_RESCHEDULE_PROPOSED` is established for Guardians only when the
Proposal has `proposing_context = 'CLINIC'` and a `CONFIRMED` base
(`base_revision_context = 'CONFIRMED'`). A Guardian-originated Proposal does
not notify the same Guardian audience about its own proposal. Accepted
reschedule Communications remain unchanged for either proposing context.

Delivery of `APPOINTMENT_RESCHEDULE_PROPOSED` is suppressed whenever the
Proposal is no longer actionable, using the authoritative
`appointment_reschedule_proposal_is_actionable(...)` predicate (SPEC-COM-003
BR-70, SPEC-APT-005 BR-31): accepted, withdrawn, Appointment no longer
`CONFIRMED`, Clinical Encounter established, base revision superseded,
proposing authority lost, or base or proposed time passed.

Withdrawing a Clinic Proposal (SPEC-APT-016) creates no Communication.

### Requested-Appointment alternative time

`APPOINTMENT_ALTERNATIVE_TIME_PROPOSED` (SPEC-APT-018, SPEC-COM-003 BR-71) is
established, in the proposal-creating transaction, for every Guardian current
at the proposal's creation time, when a Proposal is created with
`proposing_context = 'CLINIC'` and `base_revision_context = 'REQUESTED'`. It
references the Proposal through the existing
`appointment_reschedule_proposal_id`; no second nullable proposal reference is
added, and it references no Schedule Revision or Lifecycle Event. At most one
exists per Proposal and recipient.

Required content meaning:

- the Clinic proposes another time for the Guardian's **request**;
- the Appointment is **not yet confirmed**;
- the date and time shown is the proposed one, taken from the Proposal.

Illustrative `es-ES` email sentence (wording is not normative):
`La clínica {clinic} propone otro horario para la solicitud de cita de {pet}:
{proposed date and time}. La cita aún no está confirmada.`

Push remains the existing privacy-minimized generic Appointment-update body
and never implies confirmation.

Delivery is suppressed whenever the Proposal is no longer actionable, using
the same authoritative `appointment_reschedule_proposal_is_actionable(...)`
predicate: accepted, withdrawn, `VOID` (Guardian requested reschedule, Clinic
confirmation, cancellation, expiry), base requested or proposed start passed,
or proposing authority lost.

Guardian acceptance (SPEC-APT-019) and Clinic withdrawal create no
Communication, and no Clinic-side notification exists for acceptance.
Confirmation and cancellation keep their ordinary Communications.

### Deployment order for `APPOINTMENT_ALTERNATIVE_TIME_PROPOSED`

The backend must not establish this type in an environment until that
environment can render and deliver it. The implementation must therefore be
deployed in this order, per environment:

1. Edge Function (`communications-dispatch` and the shared templates): accept
   the new type for email and push, render the request-not-confirmed wording,
   and take the date and time from the referenced Proposal. Until step 2 this
   is dormant.
2. Database migration: extend the Communication type and shape constraints,
   the per-Proposal-and-recipient uniqueness, and the origin integrity check
   (a Proposal-referencing Communication's type must match the Proposal's base
   context); make `get_communication_delivery_context(...)` resolve the
   proposed interval for the new type, as it does for
   `APPOINTMENT_RESCHEDULE_PROPOSED`; extend delivery eligibility to the new
   type with the same actionability predicate; and enqueue the new type —
   instead of `APPOINTMENT_RESCHEDULE_PROPOSED` — for a Clinic Proposal on a
   `REQUESTED` base.
3. Mobile client: present the Alternative Time workflow (SPEC-APT-018 §5,
   SPEC-APT-019 §5). The push payload shape (`route`, `appointment_id`,
   `pet_id`) is unchanged.

The Proposal-creating operation for a `REQUESTED` base must not be callable in
an environment before step 2 is applied there. Applying the migration before
the Edge Function would leave Communications that cannot be rendered; their
delivery would fail rather than silently send wrong content.

## Recipient policy

Material Guardian Appointment Communications target all Guardians who satisfy the
approved current-Guardianship predicate at the applicable resolution time.

Immediate event Communications establish recipient-specific intent from the current
Guardian set in the originating transaction.

A Guardian who becomes current later does not receive historical event replay.

Delivery fanout is materialized once under a Communication row lock. That first
materialization freezes the current email destination and all currently eligible Push
Registrations as the complete destination set. A later Push Registration or email-address
change never adds a destination to the historical Communication; retries use only the
already-created Delivery Jobs.

Before provider submission, current eligibility is revalidated so a former Guardian does
not receive new private delivery.

Reminder recipients are resolved from current Guardianship at reminder materialization.

Organization Membership alone never implies Clinic-side Communication eligibility.

## Reminder policy

Phase 1 supports one reminder policy.

Initial operational values:

- reminder advance: 24 hours before confirmed Appointment start;
- catch-up window: 6 hours;
- policy key: versioned source-controlled identifier;
- reminder scan cadence: implementation-defined source-controlled schedule.

These values are operational configuration, not permanent database invariants.

A reminder is created only when:

- the Appointment remains CONFIRMED;
- the candidate revision remains the latest applicable confirmed revision;
- current time is still before Appointment start;
- the current reminder occurrence has not already been created;
- the Guardian remains currently eligible.

Cancellation, completion, no-show or accepted reschedule must suppress obsolete
reminders.

## Localization

Initial default locale:

`es-ES`.

No User locale-preference table is introduced in Phase 1.

Communication stores a non-authoritative presentation-locale snapshot.

Missing localization falls back to the default locale without creating another logical
Communication.

## Invitation credential handling

Phase 1 implements the ADR-008 encrypted Invitation handoff using AES-256-GCM
with versioned deployment keys.

Legacy pre-Slice-14 Invitations are not backfilled.

Exact API, key names and deployment procedures are documented in the
Communications backend operations document.

## Push Registration security

ADR-008 session binding is the security boundary.

Phase 1 revalidates the bound `auth.sessions` row immediately before private
Push submission. Client-side unregister on sign-out remains best-effort cleanup.

The raw Expo token remains only in the private Push Registration. Delivery Jobs and
append-only Attempts retain the Push Registration identity and a stable SHA-256
destination reference, not the token. Trusted dispatch loads the raw token only after
the final Registration/session check for the imminent provider call.

The linked recovery validation confirmed that pre-recovery sessions are removed
in the development Supabase project.

## Push content privacy

Push payloads must be privacy-minimized because they may appear on a lock screen.

Do not include:

- Appointment reason;
- diagnosis;
- medical history;
- Clinical Attachments;
- Care Authorization internals;
- recipient email;
- provider token.

Permitted presentation may include minimal operational wording, Clinic name where useful,
and an opaque Appointment identifier for navigation.

Navigation identifiers do not grant authorization.

The application must reload current authoritative state after opening a notification.

## Email content privacy

Transactional email may contain the minimum operational context required to understand
the event, such as:

- Pet;
- Clinic;
- relevant date/time;
- operational Appointment state/action.

Do not include unrelated medical history or protected clinical content.

Invitation email contains only the required Invitation context and protected action link.

## Retry policy

Provider retries are bounded and source-controlled.

Taking a work lease is not a provider submission. The submission count and
submission timestamps advance only at the explicit provider-start boundary,
after locked final recipient/origin eligibility has passed. An expired
pre-submission lease is safe to reclaim without recording an Attempt.

Initial Phase 1 policy:

### Email

Transient failures may retry using provider idempotency where supported.

Ambiguous Resend submissions reuse the same provider idempotency key while the documented
provider idempotency window remains valid.

Do not generate a new idempotency key merely to escape an ambiguous prior send.

After an unresolved provider ambiguity can no longer be safely retried, record an
UNKNOWN/closed operational outcome rather than knowingly risking unbounded duplicate
email.

### Push

Retry only failures known to be safe before provider acceptance.

An Expo ticket with `status=ok` records the provider submission Attempt and
Delivery Job as `ACCEPTED` while receipt evidence is pending.

An ambiguous Expo submission for which provider acceptance cannot be excluded:

- appends its provider submission Attempt with outcome `UNKNOWN`;
- closes the Delivery Job as terminal `UNKNOWN`;
- is not claimed again for automatic provider submission.

If a worker lease expires after the explicit Expo provider-start boundary and
before the outcome is persisted, the same `UNKNOWN` terminal rule applies. If
the lease expires before that boundary, no Expo operation occurred and the work
may be reclaimed.

An explicit provider response such as HTTP `429` or `5xx` remains `RETRYABLE`
when that response proves the operation was rejected before provider
acceptance. This is distinct from losing the response after submission.

An Expo receipt with `status=ok` closes the Delivery Job as
`UPSTREAM_ACCEPTED`. This is upstream FCM/APNs infrastructure evidence only. It
is never recorded as `DELIVERED` and does not establish device delivery,
display, User read, or acknowledgement.

Receipt polling is used to obtain later provider evidence.

Expo receipt polling is bounded to a source-controlled 23-hour horizon from the
submission that produced the current accepted ticket. A later accepted ticket after a
retry starts a fresh receipt horizon from its own submission timestamp. An unresolved
`ACCEPTED` ticket that reaches the horizon closes as `UNKNOWN`; it is no longer polled
and is never resubmitted.

A provider response such as `DeviceNotRegistered` invalidates only the affected Push
Registration.

### General

Retries never repeat the originating Appointment or Invitation domain operation.

Exactly-once external delivery is not guaranteed.

## Provider observations

Provider callbacks/receipts are infrastructure evidence only.

They never mutate:

- Appointment state;
- Invitation authorization;
- Guardianship;
- Membership;
- Care Authorization.

Out-of-order or duplicate observations must be handled monotonically and idempotently.

Domain Resend API submissions carry the source-controlled
`petcare_source=domain_communication` provider tag. Signature verification always runs
before that tag is trusted. A signed event without the domain tag (including Supabase
Auth SMTP traffic) returns HTTP `200` as `IGNORED` without database mutation.

A tagged domain event received before its provider message identifier has been persisted
is `UNMATCHED`. The webhook endpoint returns HTTP `503` so the signed provider event can
be retried; it does not fabricate a Delivery Job or accept an unsigned replay. Once the
mapping exists, the same signed event is applied idempotently and later duplicates are
harmless.

## Dispatcher and scheduling

Communication intent is durable before dispatch.

Dispatch uses bounded batches and safe claims.

The dispatcher may be invoked repeatedly.

A crashed or missed invocation leaves durable eligible work for a future invocation.

Reminder materialization and provider dispatch scheduling must be source-controlled and
must not require manual Dashboard-only business logic.

Secrets used to invoke scheduled Edge work must not be stored directly in SQL source.

## Logging

Never log:

- Invitation plaintext credential;
- complete Invitation action URL;
- email-provider API key;
- webhook secret;
- Push token;
- encryption key;
- raw provider webhook body when unnecessary;
- full recipient email in general diagnostic logs where redaction is sufficient.

Use opaque domain/provider identifiers and sanitized error codes.

## Secrets and environment configuration

Expected deployment secrets include:

- email-provider API credential;
- email webhook verification secret;
- Expo access token where enabled;
- Invitation envelope key;
- Communications scheduler/dispatcher invocation secret;
- provider SMTP credentials for Supabase Auth.

Expected non-secret configuration includes:

- From address;
- optional Reply-To;
- Invitation link base URL;
- default locale;
- reminder advance;
- reminder catch-up;
- provider/project identifiers;
- retry-policy version;
- template version.

Secrets never belong in Git.

## Cost policy

Operating cost is a first-class Phase 1 consideration.

Prefer:

- zero fixed provider cost while usage is low;
- usage-based growth;
- simple provider replacement;
- no premature infrastructure whose operational burden outweighs its direct savings.

The current email-provider decision intentionally accepts a higher marginal provider cost
than AWS SES in exchange for lower implementation and operational complexity.

Provider choice must be reevaluated when actual measured volume makes the difference
material.

Do not encode provider pricing in domain schema or ADRs.

## Retention

No destructive Communication-history retention period is defined in Phase 1.

Delivery Attempt history is append-only while retained.

A future retention policy must be separately approved before destructive cleanup of
historical Communication records.

## Current exclusions

Phase 1 does not implement:

- communication preferences;
- marketing;
- SMS;
- WhatsApp;
- notification inbox;
- read receipts;
- acknowledgement;
- repeated reminder campaigns;
- Clinic-wide broadcasting;
- medical-result notifications;
- general event bus;
- generic job platform.

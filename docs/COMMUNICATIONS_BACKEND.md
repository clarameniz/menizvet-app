# Communications Backend Operations

## Operational policy

Phase-1 provider, channel, reminder, localization, privacy, retry and cost
policy is defined in [`COMMUNICATIONS_OPERATIONAL_POLICY.md`](COMMUNICATIONS_OPERATIONAL_POLICY.md).

This document defines the backend API, deployment configuration and operational integration contract.

## Repository boundary

This repository owns:

- the typed transactional outbox and origin/recipient constraints;
- atomic Invitation-plus-Communication replacement commands;
- non-authoritative Delivery Jobs, append-only Delivery Attempts, retry leases,
  frozen one-time destination fanout, callback ordering, and Expo receipts;
- session-bound Push Registration persistence and server eligibility checks;
- versioned Invitation envelope encryption/decryption at trusted Edge boundaries;
- Spanish Phase 1 transactional templates;
- the authenticated `communications` Edge API;
- the maintenance `communications-dispatch` Edge function;
- the signed `communications-resend-webhook` Edge function.

The eventual Expo mobile application owns:

- requesting operating-system notification permission;
- obtaining and refreshing its Expo push token;
- creating and securely retaining one random installation UUID per app install;
- calling registration only with its current authenticated access token;
- disabling its registration before sign-out where possible;
- handling privacy-minimized Appointment deep-link data;
- re-establishing registration after sign-in or account recovery.

The client is not the security boundary. A deleted `auth.sessions` row makes its
registration ineligible even when a client cannot call disable during sign-out.

## Authenticated client contract

All calls are `POST` requests to the `communications` Edge function with the
current Supabase access token. UUID values use canonical UUID text.

### `register-push`

Request:

```json
{
  "device_installation_id": "<installation UUID>",
  "expo_push_token": "ExponentPushToken[...]",
  "platform": "IOS",
  "application_id": "com.petcare.mobile"
}
```

The verified JWT must contain `session_id`, and that exact session must still
exist for the verified Auth subject. A repeated identical request is idempotent.
A token or installation rebound to a different session invalidates its previous
active registration. The response contains `registration_id`.

The raw token is private to Push Registration persistence. Delivery Jobs and Attempts
use its stable SHA-256 destination reference. Trusted dispatch resolves the raw token
only after final session/Registration eligibility for the imminent Expo call.

### `disable-push`

Request:

```json
{ "registration_id": "<Push Registration UUID>" }
```

Only the verified User and exact registering session can disable it through this
route. The response contains `invalidated`.

### `create-organization-invitation`

Staff Phase 1 contract (SPEC-ORG-002 §10; implemented LOCALLY in Slice B1, not
yet deployed — the deployed route still runs the previous contract until the
Communications Edge Function is redeployed together with migration
`20261027090000_staff_invitation_invite_and_revoke.sql`):

```json
{
  "organization_id": "<Organization UUID>",
  "recipient_email": "laura@example.com",
  "responsibility": "ADMINISTRATOR",
  "scope_type": "CLINIC",
  "clinic_id": "<Clinic UUID, or null for ORGANIZATION scope>"
}
```

Any other member — including `expires_at`, `recipient_user_id`, and
`intended_responsibilities` — is rejected with `400 INVALID_REQUEST` before any
database call. The acting User is the JWT subject verified with
`auth.getUser`. The route then calls the service-role
`authorize_organization_invitation_creation(subject, organization)`, which
decides authentication, inviter verification, and Organization + capability
(nonexistent and inaccessible Organizations are indistinguishable) and returns
the creation instant T from database time at millisecond precision. Only after
that are the values judged, the one-time secret generated, and its AES-GCM
envelope bound to exactly T + 7 days. The service-role
`create_staff_organization_invitation_with_communication(...)` re-checks
authority under the Organization lock, stores `created_at = T`, derives
`expires_at = T + 168 hours` itself, and creates the Invitation, its single
intended responsibility, and its Communication atomically; the Communication
integrity trigger rejects an envelope context that does not bind that expiry.
The command is called once and never retried. The response is
`201 { "invitation_id": "<uuid>" }` only; errors are `{ "error": <code> }` with
`401 AUTHENTICATION_REQUIRED`, `403 ACCOUNT_VERIFICATION_REQUIRED |
ORGANIZATION_UNAVAILABLE`, `400 INVALID_REQUEST | INVALID_RECIPIENT |
INVALID_ROLE_SCOPE | INVALID_CLINIC`, `409 PENDING_INVITATION_EXISTS |
ACTIVE_MEMBER`, or `500 INTERNAL_ERROR`. The trusted legacy
`create_scoped_organization_invitation_with_communication` remains for trusted
compatibility and is not called by the route.

The email link carries the secret in its URL fragment so it is not sent to the
web origin in the initial HTTP request. The link target is
`/invitations/organization/accept?invitation=<id>#secret=<secret>`
(SPEC-COM-001 BR-43).

Revocation (SPEC-ORG-010) is the authenticated RPC
`revoke_organization_invitation(p_invitation_id)`, not an Edge route. A revoked
Invitation's undelivered email is suppressed by the existing delivery
eligibility checks; `mark_communication_delivery_submission_started`
share-locks the Organization Invitation so the provider handoff serializes with
a concurrent revocation. An email already handed to the provider is not
recalled, and revocation creates no Communication.

Acceptance (approved, Staff access lifecycle Phase 1, not yet implemented):
the mobile client calls the authenticated RPC
`accept_my_organization_invitation(p_invitation_id, p_acceptance_secret)`
(SPEC-ORG-003 §11), which derives the accepting User from `auth.uid()` and
hashes the exact UTF-8 secret string with SHA-256 inside the database before
comparing it with the stored digest. Acceptance does not go through this Edge
Function and needs no `service_role` caller. The service-role
`accept_organization_invitation(p_accepting_user_id, ...)` command remains only
for trusted compatibility and is never a client path. Until Phase 1 ships, no
client acceptance path exists.

The AES-GCM additional authenticated data is derived by trusted code from the
Invitation kind, normalized recipient email, exact expiration instant, and
acceptance-secret digest. The database independently verifies that context;
callers cannot supply arbitrary AAD, and moving an envelope to another valid
Invitation fails authentication.

### `create-guardianship-invitation`

Request members are `pet_id`, `inviting_guardianship_id`, optional
`recipient_user_id`, `recipient_email`, and ISO-8601 `expires_at`. Secret handling
and response shape match Organization Invitation creation.

## Deployment configuration

Set these Edge secrets outside source control:

- `RESEND_API_KEY`;
- `RESEND_FROM_EMAIL` using a verified sending domain;
- `RESEND_WEBHOOK_SECRET`;
- `EXPO_ACCESS_TOKEN` when Expo enhanced push security is enabled;
- `COMMUNICATIONS_PUBLIC_APP_URL`;
- `COMMUNICATIONS_MAINTENANCE_SECRET`;
- `INVITATION_SECRET_ACTIVE_KEY_VERSION`, initially `1`;
- `INVITATION_SECRET_KEY_V1`, base64 for exactly 32 random bytes.

Separately configure the linked project's Supabase Auth custom SMTP settings
with the Resend SMTP credentials and verified sending domain. The domain
dispatcher uses the Resend API, while Auth uses SMTP; neither credential is
stored in this repository.

Optional policy variables are `REMINDER_ADVANCE_HOURS` (default `24`),
`REMINDER_CATCHUP_HOURS` (default `6`), and
`COMMUNICATIONS_DEFAULT_LOCALE` (default `es-ES`).

Configure Resend to send its delivery webhooks to
`communications-resend-webhook`. Domain API sends include the source-controlled
`petcare_source=domain_communication` tag. The signed endpoint ignores untagged Auth SMTP
events with HTTP `200`; a tagged event whose provider message mapping is not yet durable
returns HTTP `503` for provider retry.

After all three Edge Functions are deployed and their Edge secrets are set,
create these two Vault secrets in the target database through the deployment
secret-management process:

- `communications_dispatch_url`: the full HTTPS URL ending in
  `/functions/v1/communications-dispatch`;
- `communications_maintenance_secret`: the same value configured as the Edge
  `COMMUNICATIONS_MAINTENANCE_SECRET`.

Do not put either value in SQL source or deployment logs. Then apply
[`communications_dispatch_scheduler.sql`](../supabase/provisioning/communications_dispatch_scheduler.sql)
with `ON_ERROR_STOP`. It validates both Vault entries before replacing the
named five-minute `pg_cron` job and is safe to rerun. To stop scheduled dispatch
without deleting Communications state, apply
[`communications_dispatch_scheduler_disable.sql`](../supabase/provisioning/communications_dispatch_scheduler_disable.sql).
Reapply the provisioning script to enable it again.

A scheduler retry is safe: outbox and destination uniqueness prevent duplicate
logical work, and Resend retries reuse the Delivery Job UUID as the provider
idempotency key. Expo work is resubmitted only when the lease proves that the
provider-start boundary was never crossed.

Invitation key rotation adds a new `INVITATION_SECRET_KEY_V<n>` secret and then
changes the active version. Old keys must remain available until no pending
encrypted envelope references that version. They must not be removed based only
on Invitation creation date.

## Linked provider validation cleanup

Validation cleanup depends on the boundary exercised:

- deterministic, local, and rollback-only validation must retain zero synthetic
  state;
- removable linked setup state, including synthetic Auth users, sessions, and
  authentication identity links, must be cleaned after validation;
- a genuine committed provider delivery necessarily leaves its historical
  Communication, Delivery Job, Delivery Attempt, and applied provider
  observation. The production model intentionally provides no destructive purge
  path for that history.

Committed live-provider evidence may remain only when it is explicitly
identified as synthetic, minimized, isolated from unrelated state, terminal,
inert or subject to an existing finite expiry, and accounted for in the final
validation report. A blanket requirement for zero retained synthetic database
state is therefore not a valid completion criterion for a live-provider test
that has committed this append-only evidence. This exception does not authorize
a purge API, trigger bypass, destructive migration, or new retention policy.

The controlled Resend validation associated with Communication
`2ee85187-9c29-48ee-8207-3bd3ed898870` retains one isolated, terminal delivery
history. Its removable Auth setup has been cleaned. The related synthetic
Organization Invitation cannot currently be revoked legitimately because the
deployed lifecycle has no revocation or rejection command. It must not be
terminalized through a direct privileged rewrite; it will become non-accepting
through its existing finite expiration. Once `revoke_organization_invitation`
(SPEC-ORG-010) is implemented, a still-pending Invitation of this kind may be
revoked through that ordinary operation by an authorized administrator; an
already expired one is reported as `EXPIRED` and is not changed.

### Controlled Android Push live-provider validation

A controlled live-provider validation used a non-production Android Expo/EAS
development build with application ID `com.menizvet.dev` and a synthetic User.
The build signed in to the linked Supabase project, obtained Android notification
permission and a real Expo push token, and registered exactly one eligible
`EXPO` / `ANDROID` Push Registration through the authenticated Communications
endpoint. Read-only verification confirmed its live `auth.sessions` binding and
coherent Supabase Auth-to-domain-User mapping, with no pre-existing Push Delivery
Job or Attempt.

The fixture used the real `request_appointment(...)` path to establish one
synthetic Appointment and exactly one `APPOINTMENT_REQUESTED` Communication for
its Guardian User. Before dispatch, fanout was unmaterialized, the User had one
eligible Registration for the application, and the Communication had no
Delivery Job or Attempt. One controlled manual dispatcher invocation then
created exactly two Jobs and two provider-submission Attempts: one Resend email
and one Expo Push, both initially `ACCEPTED`. The email was received in the
controlled Gmail inbox, and the Push notification appeared on the physical
Android device through the Expo/FCM delivery path. The signed Resend webhook
subsequently advanced the email Job to `DELIVERED`.

After the configured Expo receipt delay, one further controlled manual dispatcher
invocation reported zero Jobs processed and one receipt processed. The Expo
ticket-plus-receipt lifecycle therefore ended with the Push Job
`UPSTREAM_ACCEPTED`. It was not recorded as `DELIVERED` or `READ`: the physical
device observation demonstrates this controlled delivery, while the durable
state deliberately preserves only the designed Expo upstream-acceptance fact.

The client then disabled the Push Registration through the authenticated endpoint
before signing out locally. Final read-only verification found one materialized
Communication, two Jobs (`EMAIL:DELIVERED` and `PUSH:UPSTREAM_ACCEPTED`), two
Attempts, an invalidated used Push Registration, no remaining bound Auth session,
and zero currently eligible Push Registrations for the User and application.

This validation retains synthetic Appointment, Communication, Job, Attempt, Push
Registration, and provider-observation history by design. It is committed
live-provider evidence, not failed cleanup, and the deployed integrity model
provides no approved destructive purge path. The controlled Clinic was returned
to `is_published = false` before commit, and the temporary synthetic Subscription
was transitioned through the trusted lifecycle to `EXPIRED`, leaving no active
synthetic professional Entitlement. The previously retained controlled
Organization-Invitation email fixture was reused only as the Organization anchor;
its Invitation, Communication, Job, Attempt, Membership, Responsibility Grant,
and provider evidence were neither rewritten nor deleted. The Communications
scheduler remained unprovisioned and dormant throughout this validation; both
dispatch invocations were explicit and controlled.

## Slice 14 closure validation

Slice 14 is closed.

Deterministic closure: a clean isolated database reconstructed from
source-controlled migrations from the Slice 13 boundary applied
`20260901120000_communications.sql` and then the corrective migration
`20260903120000_communications_recipient_guardian_establishment_hotfix.sql` in
order, and the rollback-only `supabase/tests/communications_slice14.sql` suite
passed. That suite now also covers Appointment reminder and terminal-state
notifications (`APPOINTMENT_CANCELLED` / `APPOINTMENT_COMPLETED` /
`APPOINTMENT_NO_SHOW`), in-window and suppressed reminder policy, reschedule
reminder reselection, reminder recipient resolution from current Guardianship,
the Push Registration lifecycle (idempotent re-registration, token rotation,
cross-session/User reassociation, second-device survival, authorized and
rejected disable), former-Guardian delivery suppression, dispatcher un-wedging,
and the Communications ACL/authorization boundary. Deno `fmt`, `lint`, and
typecheck for all three Edge Functions, the Communications Deno tests, the static
migration/config/ACL checks, a committed-credential scan, and `git diff --check`
all passed.

### Corrective former-Guardian hotfix

`20260903120000_communications_recipient_guardian_establishment_hotfix.sql`
replaces `enforce_transactional_communication_integrity()` so that its
"Appointment Communication recipient must be a current Guardian" assertion is an
establishment-time (`INSERT`) invariant only. It previously re-fired on trusted
immutable-row bookkeeping `UPDATE`s such as the `fanout_materialized_at` freeze,
so a Communication legitimately created for a then-current Guardian could abort
`materialize_communication_delivery_jobs()` — and therefore the whole dispatcher
— once that Guardianship ended. A former Guardian is now suppressed by the
existing current-eligibility machinery instead of raising, and the Communication
remains a valid historical row. `20260901120000_communications.sql` is unchanged,
and the trigger definition is unchanged; only the function body distinguishes
`TG_OP`.

### Final Auth-fixture cleanup accounting

The removable Push-test Auth fixture was cleaned through the normal Auth and
identity boundary. Final accounting: domain User — 1 retained historical row;
identity link — 0; Auth user — 0; currently eligible Push Registrations — 0.
Retained Communications, Delivery Jobs, Delivery Attempts, Push Registration
history, provider observations, Invitations, and Organization/domain history
remain intentional immutable live-provider evidence under the retention rule
stated above; they are not failed cleanup and have no approved destructive purge
path.

### Scheduler provisioning and scheduled-invocation validation

Before scheduler activation the linked-state preflight reported zero
unmaterialized Communications, zero unresolved Delivery Jobs, zero due Delivery
Jobs, zero expired Delivery leases, zero due Expo receipts, and zero due new
reminder recipients. `pg_cron`, `pg_net`, and Supabase Vault are enabled; Vault
holds the configured dispatcher URL and maintenance secret, whose values are
never written to documentation. Exactly one active job,
`petcare-communications-dispatch-v1`, is provisioned with cadence
`*/5 * * * *` from
[`communications_dispatch_scheduler.sql`](../supabase/provisioning/communications_dispatch_scheduler.sql).

The first real scheduled invocation succeeded: `pg_cron` execution succeeded,
`pg_net` received HTTP `200`, the dispatcher returned `COMPLETE` with
`jobs_processed = 0` and `receipts_processed = 0`, and no unintended Resend or
Expo work occurred.

Missed-cadence recovery was validated: the scheduler was legitimately unscheduled
with
[`communications_dispatch_scheduler_disable.sql`](../supabase/provisioning/communications_dispatch_scheduler_disable.sql)
(job count reached 0), at least one five-minute cadence elapsed while disabled,
the scheduler was reprovisioned from `communications_dispatch_scheduler.sql`, and
a later scheduled invocation again succeeded with HTTP `200`, dispatcher
`COMPLETE`, `jobs_processed = 0`, and `receipts_processed = 0`.

The scheduler is now provisioned and active and should remain active.

## Temporary Expo validation harness

Linked push validation does not require a production mobile repository. The
minimum temporary harness is a non-production Expo development build with:

- the correct project/application identifiers;
- one physical iOS or Android device;
- notification permission and `expo-notifications` token acquisition;
- a generated installation UUID;
- sign-in to the linked development Supabase project;
- calls to `register-push` and `disable-push`;
- display/deep-link logging sufficient to compare Expo ticket and receipt facts.

The harness must use synthetic development accounts, contain no service-role or
provider credential, and may be discarded after linked provider validation.

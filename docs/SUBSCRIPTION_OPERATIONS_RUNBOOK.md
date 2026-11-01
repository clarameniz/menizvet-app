# Subscription Operations Runbook (Phase 1, manual)

Operator procedures for the Phase 1 manually managed commercial model. The
approved policy is defined by ADR-006 (amended), `SPEC-SUB-001` §14,
`SPEC-SUB-002` §5/§14/§15, `SPEC-SUB-003` §15 and `SPEC-SUB-004` §14; this
runbook only explains how to apply it. Requires migration
`20261031090000_subscription_operational_safety.sql`; customer establishment
(§3.1) requires `20261101090000_trusted_organization_establishment.sql`.

## 1. Rules

- An ordinary manually managed customer is **`ACTIVE` with no
  `valid_until` (open-ended)**. It stays active until you record an explicit
  transition. There is no periodic renewal and no renewal operation.
- **No `ACTIVE → ACTIVE` renewal or extension.** Never simulate renewal with
  `ACTIVE → PAST_DUE → ACTIVE`. Establishment facts are immutable; never edit
  `organization_subscriptions` or `subscription_state_transitions` rows.
- **Allowed transitions only:** `PENDING → ACTIVE | EXPIRED`; `ACTIVE →
  PAST_DUE | CANCELLED | EXPIRED`; `PAST_DUE → ACTIVE | EXPIRED`;
  `CANCELLED → EXPIRED`. Anything else is rejected (there is no
  `PENDING → CANCELLED` or `PENDING → PAST_DUE`).
- **Establishment starts only as `PENDING` or `ACTIVE`**, effective no later
  than now. `PAST_DUE`, `CANCELLED`, `EXPIRED` or a future effective time are
  rejected (`INITIAL_STATE_NOT_ALLOWED`, `FUTURE_EFFECTIVE_AT`).
- **`EXPIRED` is terminal.** To restart service, establish a **new
  Subscription period** (§3.7).
- **No future-dated transitions.** Use `statement_timestamp()` as the
  effective time (never `clock_timestamp()`, which is later than the statement
  instant and is rejected, and never a future date). A past effective time is
  accepted only if it is later than the current state's effective time — record
  facts when they happen.
- **Validity is never inherited.** Each transition carries its own
  `valid_from`/`valid_until`; anything omitted is absent afterwards.
- **`PAST_DUE` = no Entitlements, no grace, no timer.** Resolve it explicitly
  (recover or expire). Nothing expires or recovers automatically.
- **Do not fabricate state.** Record only real commercial facts. Never
  backdate or invent a Subscription for a legacy Organization (§5).
- Clinics are never unpublished by Subscription changes; Guardians see only
  that online appointment requests are unavailable.

## 2. Session pattern

All operations below are trusted: run them in an operator database session
(Supabase SQL editor or psql as the session role, never as `authenticated`),
inside one transaction, after read-only checks. Customer establishment (§3.1)
is the exception: it is one self-contained autocommit call.

```sql
-- Read-only preflight: identify the Organization and its current state.
select s.id as subscription_id, d.*
from public.organization_subscriptions s
cross join lateral public.derive_organization_subscription_current_state(s.id) d
where s.organization_id = '<organization uuid>'
order by s.established_at desc;
```

Use one stable `source_system` (for example `operator-manual`) and a unique
`source_event_key` per business action (for example `op-2026-10-13-pastdue`):
retrying exactly the same call returns the same transition; reusing the key
with different facts is rejected.

Rejections are SQLSTATE `23514` with a HINT:

| HINT | Meaning |
| --- | --- |
| `SUBSCRIPTION_TRANSITION_NOT_ALLOWED` | not in the Phase 1 graph (includes same-state) |
| `SUBSCRIPTION_EXPIRED_TERMINAL` | the period is `EXPIRED`; establish a new period |
| `FUTURE_EFFECTIVE_AT` | effective time later than now |
| `STALE_EFFECTIVE_AT` | not later than the current state's effective time |
| `INITIAL_STATE_NOT_ALLOWED` | establishment requested as `PAST_DUE`, `CANCELLED` or `EXPIRED` |

`23505` means the source event key was already used with different facts.

## 3. Operations

### 3.1 Establish a customer (Organization + Owner + initial Subscription)

Requires migration `20261101090000_trusted_organization_establishment.sql`.
One trusted call establishes the Organization, the designated Owner's
Membership and `OWNER` responsibility, and the initial Subscription,
atomically and idempotently (ADR-009, `SPEC-ORG-001` §10). Never impersonate
the Owner, never `SET ROLE`, never write Memberships or Grants directly, and
never establish the initial Subscription with a second call.

1. **Read-only preflight: find the designated Owner's domain User and check
   eligibility** (`SPEC-ORG-001` BR-16: confirmed email, not deleted, not
   anonymous, not currently banned; no Profile needed). Email is used only
   here, never by the establishment call:

   ```sql
   select identity_link.user_id as owner_user_id,
          auth_user.email_confirmed_at is not null as email_confirmed,
          auth_user.deleted_at is null as not_deleted,
          not auth_user.is_anonymous as not_anonymous,
          (auth_user.banned_until is null or auth_user.banned_until <= now()) as not_banned
   from auth.users as auth_user
   join public.user_authentication_identities as identity_link
     on identity_link.provider_subject = auth_user.id
    and identity_link.provider = 'supabase_auth' and identity_link.issuer = 'primary'
   where lower(auth_user.email) = lower('<owner email>');
   ```

   Exactly one row, all four checks `true`. Otherwise stop.
2. **Generate one establishment key** (`select gen_random_uuid();`) and record
   it in the commercial ticket **before** calling. It identifies this
   onboarding for ever; never reuse it for anything else.
3. **Call once, in autocommit** (no surrounding `begin`), with literal values
   only — never `now()`/`statement_timestamp()` as an input:

   ```sql
   select public.establish_veterinary_organization(
       '<owner_user_id>',                -- domain User id from step 1
       '<Organization display name>',
       '<establishment key from step 2>',
       'ACTIVE',                         -- or 'PENDING' if service must not start yet
       null,                             -- initial effective time: null = establishment instant
       null, null,                       -- valid_from, valid_until: null = open-ended manual ACTIVE
       'operator-manual',                -- establishment source
       null);                            -- provider references (none for manual customers)
   ```

   Result: `{ organization_id, owner_membership_id, subscription_id,
   outcome: "ESTABLISHED" }`. Keep `subscription_id` for later transitions
   (§3.2).
4. **Unknown outcome** (timeout, lost connection): repeat **exactly the same
   call**. It returns the original ids with `"ALREADY_ESTABLISHED"` and
   writes nothing. Never change any argument on a retry, and never look for
   the Organization by its display name (names are not unique).

Outcomes:

| SQLSTATE / HINT | Meaning |
| --- | --- |
| `22023` | malformed input (missing key/Owner/source, blank name, unknown state, bad times or provider references) |
| `23505` `ESTABLISHMENT_KEY_CONFLICT` | the key was already used with different inputs (or by another Subscription): do not retry; investigate |
| `28000` `OWNER_IDENTITY_UNAVAILABLE` | no such domain User, or no coherent mapped account |
| `42501` `OWNER_ACCOUNT_INELIGIBLE` | unconfirmed, deleted, anonymous or currently banned account |
| `23514` `INITIAL_STATE_NOT_ALLOWED` / `FUTURE_EFFECTIVE_AT` | initial state other than `PENDING`/`ACTIVE`, or a future initial effective time |

After establishment the Owner signs in normally and does everything else
(Clinics, Staff, schedules) in the app. Establishment creates no Clinic.

### 3.2 Activate (`PENDING → ACTIVE`)

```sql
select * from public.apply_subscription_state_transition(
    '<subscription uuid>', 'ACTIVE', statement_timestamp(), null, null,
    'operator-manual', '<event key>');
```

### 3.3 Mark a payment issue (`ACTIVE → PAST_DUE`)

```sql
select * from public.apply_subscription_state_transition(
    '<subscription uuid>', 'PAST_DUE', statement_timestamp(), null, null,
    'operator-manual', '<event key>');
```

Effect: all professional Entitlements stop immediately. Clinics stay
published; existing Appointments can still be cancelled, completed or marked
no-show; Clinical Amendments remain possible.

### 3.4 Recover (`PAST_DUE → ACTIVE`)

```sql
select * from public.apply_subscription_state_transition(
    '<subscription uuid>', 'ACTIVE', statement_timestamp(),
    null, null,                      -- keep it open-ended: pass NULLs explicitly
    'operator-manual', '<event key>');
```

### 3.5 Cancel (`ACTIVE → CANCELLED`)

End-of-period cancellation keeps service until an explicit end:

```sql
select * from public.apply_subscription_state_transition(
    '<subscription uuid>', 'CANCELLED', statement_timestamp(),
    null, '<end of covered period, timestamptz>',
    'operator-manual', '<event key>');
```

With `valid_until` NULL, service stops immediately. Never record the
cancellation as a future-dated transition.

### 3.6 Expire (`PENDING | ACTIVE | PAST_DUE | CANCELLED → EXPIRED`)

```sql
select * from public.apply_subscription_state_transition(
    '<subscription uuid>', 'EXPIRED', statement_timestamp(), null, null,
    'operator-manual', '<event key>');
```

A `CANCELLED` Subscription stops providing Entitlements at its `valid_until`
by itself, but still occupies the Organization's current relationship until
you record `EXPIRED`.

For a `PENDING` Subscription that will never become active, `EXPIRED` is its
permanent closure: it never provided commercial validity, and the
Organization may later receive a new Subscription period (§3.7).

### 3.7 New Subscription period after `EXPIRED`

This is the only use of `establish_organization_subscription`: a **later**
period for an already established Organization. The initial Subscription is
never created this way (§3.1). Only once no non-`EXPIRED` Subscription exists
for the Organization (a second current Subscription is rejected):

```sql
select public.establish_organization_subscription(
    '<organization uuid>', null, 'ACTIVE', statement_timestamp(),
    null, null, 'operator-manual', '<new uuid idempotency key>', null);
```

The expired period and its history stay unchanged.

## 4. Customer visibility

Owners and Organization Administrators (`ORGANIZATION_MANAGE_SUBSCRIPTION`)
see the stored state, its effective time, the validity dates when present,
and service availability under MenizVet Professional → Management →
Subscription (`get_organization_subscription_status`). Guardians never see
commercial information: an empty availability window shows one
reason-agnostic message, and only a denied request says the Clinic is not
currently accepting online appointment requests.

## 5. Diagnostics and legacy Organizations

Run `supabase/provisioning/subscription_inventory_readonly.sql` (read-only,
rolled back) to list: Organizations that never had a Subscription; without a
current one; with more than one current one; with published Clinics but no
Appointment Entitlement; the current status of every Organization (open-ended,
validity ended, ending within 30 days, `PAST_DUE` duration); historical
future-dated or out-of-graph transitions; and each Organization's
establishment path (`ATOMIC_ESTABLISHMENT` through §3.1, or `PRE_ATOMIC_PATH`
for Organizations established before it).

Organizations without any Subscription must not be "fixed" by fabricating or
backdating one (ADR-009). Report them; their reconciliation policy is a
separate product decision.

## 6. Not available in Phase 1

Periodic renewal, scheduled transitions, grace periods, automatic expiry,
cancellation reversal (`CANCELLED → ACTIVE`), `PENDING → CANCELLED`,
reactivation of an `EXPIRED` period, establishing a Subscription in any state
other than `PENDING`/`ACTIVE` or with a future effective time,
billing-provider synchronization, and customer-facing billing or payment
screens.

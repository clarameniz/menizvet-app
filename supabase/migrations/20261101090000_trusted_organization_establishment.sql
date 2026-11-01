-- Trusted Organization Establishment Hardening (ADR-009 amendment,
-- SPEC-ORG-001 BR-16 / §10, SPEC-SUB-001 §14).
--
-- One service_role-only operation establishes, atomically and idempotently,
-- the Veterinary Organization, the designated Owner's Membership, the active
-- Organization-scoped OWNER Grant and the initial Subscription:
--
--   establish_veterinary_organization(owner domain User, display name, key,
--       initial state, initial effective time, valid_from, valid_until,
--       establishment source, provider references) returns jsonb
--
--   * Owner: the domain User id (never an Auth subject or email). The
--     operation checks the mapping and BR-16 account eligibility itself; no
--     session impersonation.
--   * Idempotency: veterinary_organizations.establishment_idempotency_key
--     (nullable for earlier Organizations, unique, immutable) is the recovery
--     anchor and also the initial Subscription's establishment key.
--     establishment_request_digest records SHA-256 of the canonical REQUESTED
--     inputs, so a replay is compared against what was asked (an omitted
--     initial effective time stays "omitted"), never against resolved
--     defaults. Identical concurrent calls serialize on the unique key
--     (insert-on-conflict, then re-read of the committed Organization).
--   * Order: shape (22023) -> replay / contradictory reuse (23505
--     ESTABLISHMENT_KEY_CONFLICT) -> Owner identity (28000
--     OWNER_IDENTITY_UNAVAILABLE) and eligibility (42501
--     OWNER_ACCOUNT_INELIGIBLE) -> initial Subscription policy (23514
--     INITIAL_STATE_NOT_ALLOWED / FUTURE_EFFECTIVE_AT) -> writes.
--   * Time: one t = statement_timestamp() for Membership and Grant starts and
--     Subscription establishment; an omitted initial effective time is t.
--   * The deferred Organization/Membership/Grant/Subscription invariants that
--     these writes queue are surfaced before returning (SET CONSTRAINTS on the
--     named constraint triggers, restored to their declared DEFERRED mode), so
--     ESTABLISHED is never reported for an establishment that would fail at
--     commit. No global constraint mode is changed.
--
-- Also:
--   * create_veterinary_organization(text) is dropped: it derived the Owner
--     from the caller's subject and established no Subscription; every caller
--     now uses the atomic operation and it has no reusable helper value;
--   * establish_organization_subscription keeps its signature, result and
--     service_role ACL (later Subscription periods after EXPIRED); its exact
--     replay now also compares the provider-reference set, and its conflict
--     message no longer echoes the key.
--
-- No backfill, no legacy reconciliation, no Organization -> Subscription
-- structural invariant (deferred: legacy inventory and SPEC-SUB-002 §15).
begin;

-- ==================================================================
-- 1. Durable establishment anchor on the Organization.
-- ==================================================================

alter table public.veterinary_organizations
    add column establishment_idempotency_key uuid,
    add column establishment_request_digest bytea;

alter table public.veterinary_organizations
    add constraint veterinary_organizations_establishment_idempotency_key_key
        unique (establishment_idempotency_key),
    add constraint veterinary_organizations_establishment_record_check
        check (
            (establishment_idempotency_key is null) = (establishment_request_digest is null)
            and (establishment_request_digest is null
                 or octet_length(establishment_request_digest) = 32)
        );

-- The establishment record is part of the Organization's establishment facts.
create or replace function public.enforce_veterinary_organization_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Veterinary Organizations cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id then
        raise exception 'Veterinary Organization identity is immutable'
            using errcode = '23514';
    end if;

    if old.establishment_idempotency_key is distinct from new.establishment_idempotency_key
       or old.establishment_request_digest is distinct from new.establishment_request_digest then
        raise exception 'Veterinary Organization establishment record is immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

-- ==================================================================
-- 2. Provider-reference canonical sets (private).
-- ==================================================================

-- Canonical, order-insensitive set of a requested provider-reference payload:
-- sorted distinct [provider, reference_kind, opaque_reference] triples with
-- the same trimming the stored rows use. NULL and [] are the empty set. The
-- payload is assumed to have passed shape validation.
create function public.canonical_subscription_provider_references(
    p_provider_references jsonb
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
    select coalesce(
        (select jsonb_agg(entry order by entry)
         from (
             select distinct jsonb_build_array(
                 btrim(reference_payload ->> 'provider', E' \t\n\r\f\013'),
                 reference_payload ->> 'reference_kind',
                 btrim(reference_payload ->> 'opaque_reference', E' \t\n\r\f\013')
             ) as entry
             from jsonb_array_elements(coalesce(p_provider_references, '[]'::jsonb)) as reference_payload
         ) as entries),
        '[]'::jsonb
    )
$$;

revoke all privileges
on function public.canonical_subscription_provider_references(jsonb)
from public, anon, authenticated, service_role;

-- The same canonical set for the references stored with a Subscription.
create function public.stored_subscription_provider_references(
    p_subscription_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(
        (select jsonb_agg(entry order by entry)
         from (
             select distinct jsonb_build_array(
                 reference.provider, reference.reference_kind, reference.opaque_reference
             ) as entry
             from public.subscription_provider_references as reference
             where reference.subscription_id = p_subscription_id
         ) as entries),
        '[]'::jsonb
    )
$$;

revoke all privileges
on function public.stored_subscription_provider_references(uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 3. Later-period establishment: provider references join exact replay.
--    Identical to 20261031090000 except the replay comparison (provider
--    reference set) and the conflict message (no key echoed). Same
--    signature, result, attributes and ACL.
-- ==================================================================

create or replace function public.establish_organization_subscription(
    p_organization_id uuid,
    p_initiated_by_user_id uuid,
    p_initial_state text,
    p_initial_state_effective_at timestamptz,
    p_initial_commercial_valid_from timestamptz,
    p_initial_commercial_valid_until timestamptz,
    p_establishment_source text,
    p_establishment_idempotency_key uuid,
    p_provider_references jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_initial_state text;
    normalized_establishment_source text;
    operation_timestamp timestamptz;
    existing_subscription_record public.organization_subscriptions%rowtype;
    created_subscription_id uuid;
begin
    if p_organization_id is null then
        raise exception 'Veterinary Organization is required'
            using errcode = '22023';
    end if;

    normalized_initial_state := p_initial_state;

    if normalized_initial_state is null
       or normalized_initial_state not in (
           'PENDING', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED'
       ) then
        raise exception 'Unsupported initial Organization Subscription state'
            using errcode = '22023';
    end if;

    if p_initial_state_effective_at is null
       or p_initial_state_effective_at = 'infinity'::timestamptz
       or p_initial_state_effective_at = '-infinity'::timestamptz then
        raise exception 'Organization Subscription initial effective time must be finite'
            using errcode = '22023';
    end if;

    if p_initial_commercial_valid_from is not null
       and (
           p_initial_commercial_valid_from = 'infinity'::timestamptz
           or p_initial_commercial_valid_from = '-infinity'::timestamptz
       ) then
        raise exception 'Organization Subscription initial commercial validity start must be finite'
            using errcode = '22023';
    end if;

    if p_initial_commercial_valid_until is not null
       and (
           p_initial_commercial_valid_until = 'infinity'::timestamptz
           or p_initial_commercial_valid_until = '-infinity'::timestamptz
       ) then
        raise exception 'Organization Subscription initial commercial validity end must be finite'
            using errcode = '22023';
    end if;

    if p_initial_commercial_valid_from is not null
       and p_initial_commercial_valid_until is not null
       and p_initial_commercial_valid_from >= p_initial_commercial_valid_until then
        raise exception 'Organization Subscription initial commercial validity interval is incoherent'
            using errcode = '22023';
    end if;

    normalized_establishment_source := btrim(p_establishment_source, E' \t\n\r\f\013');

    if normalized_establishment_source is null
       or normalized_establishment_source = '' then
        raise exception 'Organization Subscription establishment source must not be blank'
            using errcode = '22023';
    end if;

    if p_establishment_idempotency_key is null then
        raise exception 'Organization Subscription establishment idempotency key is required'
            using errcode = '22023';
    end if;

    if p_provider_references is not null then
        if jsonb_typeof(p_provider_references) <> 'array' then
            raise exception 'Subscription Provider References payload must be a JSON array'
                using errcode = '22023';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(p_provider_references) as reference_payload
            where jsonb_typeof(reference_payload) <> 'object'
               or reference_payload ->> 'provider' is null
               or btrim(reference_payload ->> 'provider', E' \t\n\r\f\013') = ''
               or reference_payload ->> 'reference_kind' not in ('CUSTOMER', 'SUBSCRIPTION')
               or reference_payload ->> 'opaque_reference' is null
               or btrim(reference_payload ->> 'opaque_reference', E' \t\n\r\f\013') = ''
        ) then
            raise exception 'Subscription Provider Reference payload is invalid'
                using errcode = '22023';
        end if;
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    if p_initiated_by_user_id is not null
       and not public.user_has_organization_capability(
           p_initiated_by_user_id,
           p_organization_id,
           'ORGANIZATION_MANAGE_SUBSCRIPTION'
       ) then
        raise exception 'Organization Subscription management capability is required'
            using errcode = '42501';
    end if;

    select subscription.*
    into existing_subscription_record
    from public.organization_subscriptions as subscription
    where subscription.establishment_idempotency_key = p_establishment_idempotency_key
    for update;

    if found then
        if existing_subscription_record.organization_id <> p_organization_id
           or existing_subscription_record.initiated_by_user_id
               is distinct from p_initiated_by_user_id
           or existing_subscription_record.initial_state <> normalized_initial_state
           or existing_subscription_record.initial_state_effective_at <> p_initial_state_effective_at
           or existing_subscription_record.initial_commercial_valid_from
               is distinct from p_initial_commercial_valid_from
           or existing_subscription_record.initial_commercial_valid_until
               is distinct from p_initial_commercial_valid_until
           or existing_subscription_record.establishment_source <> normalized_establishment_source
           or public.canonical_subscription_provider_references(p_provider_references)
               is distinct from public.stored_subscription_provider_references(existing_subscription_record.id) then
            raise exception 'Organization Subscription establishment idempotency key was already used with different facts'
                using errcode = '23505';
        end if;

        return existing_subscription_record.id;
    end if;

    -- Phase 1 initial state (ADR-006, SPEC-SUB-001 §14), after exact replays
    -- of an already established Subscription have been recognized above.
    if normalized_initial_state not in ('PENDING', 'ACTIVE') then
        raise exception 'A Subscription can only be established as PENDING or ACTIVE in Phase 1'
            using errcode = '23514',
                  hint = 'INITIAL_STATE_NOT_ALLOWED';
    end if;

    if p_initial_state_effective_at > statement_timestamp() then
        raise exception 'A Subscription cannot be established with a future-dated initial state'
            using errcode = '23514',
                  hint = 'FUTURE_EFFECTIVE_AT';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.organization_subscriptions (
        organization_id,
        established_at,
        initiated_by_user_id,
        initial_state,
        initial_state_effective_at,
        initial_commercial_valid_from,
        initial_commercial_valid_until,
        establishment_source,
        establishment_idempotency_key
    )
    values (
        p_organization_id,
        operation_timestamp,
        p_initiated_by_user_id,
        normalized_initial_state,
        p_initial_state_effective_at,
        p_initial_commercial_valid_from,
        p_initial_commercial_valid_until,
        normalized_establishment_source,
        p_establishment_idempotency_key
    )
    returning id into created_subscription_id;

    if p_provider_references is not null then
        insert into public.subscription_provider_references (
            subscription_id,
            provider,
            reference_kind,
            opaque_reference,
            recorded_at
        )
        select
            created_subscription_id,
            btrim(reference_payload ->> 'provider', E' \t\n\r\f\013'),
            reference_payload ->> 'reference_kind',
            btrim(reference_payload ->> 'opaque_reference', E' \t\n\r\f\013'),
            operation_timestamp
        from jsonb_array_elements(p_provider_references) as reference_payload;
    end if;

    return created_subscription_id;
end;
$$;

-- ==================================================================
-- 4. Initial Owner identity and eligibility (SPEC-ORG-001 BR-16, private).
-- ==================================================================

-- 28000 when the domain User does not exist or has no coherent mapped Auth
-- account; 42501 when that account is not eligible at p_instant. One hint per
-- outcome; no Auth fact is named in any message.
create function public.assert_initial_owner_eligible(
    p_owner_user_id uuid,
    p_instant timestamptz
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    owner_account record;
begin
    select
        auth_user.email_confirmed_at,
        auth_user.deleted_at,
        auth_user.is_anonymous,
        auth_user.banned_until
    into owner_account
    from public.users as domain_user
    join public.user_authentication_identities as identity_link
      on identity_link.user_id = domain_user.id
     and identity_link.provider = 'supabase_auth'
     and identity_link.issuer = 'primary'
    join auth.users as auth_user
      on auth_user.id = identity_link.provider_subject
    where domain_user.id = p_owner_user_id;

    if not found then
        raise exception 'The designated initial Owner has no coherent domain identity'
            using errcode = '28000',
                  hint = 'OWNER_IDENTITY_UNAVAILABLE';
    end if;

    if owner_account.email_confirmed_at is null
       or owner_account.deleted_at is not null
       or owner_account.is_anonymous is distinct from false
       or (owner_account.banned_until is not null
           and owner_account.banned_until > p_instant) then
        raise exception 'The designated initial Owner account is not eligible for Organization ownership'
            using errcode = '42501',
                  hint = 'OWNER_ACCOUNT_INELIGIBLE';
    end if;
end;
$$;

revoke all privileges
on function public.assert_initial_owner_eligible(uuid, timestamptz)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 5. The trusted atomic establishment operation.
-- ==================================================================

create function public.establish_veterinary_organization(
    p_owner_user_id uuid,
    p_organization_display_name text,
    p_establishment_idempotency_key uuid,
    p_initial_subscription_state text,
    p_initial_state_effective_at timestamptz,
    p_commercial_valid_from timestamptz,
    p_commercial_valid_until timestamptz,
    p_establishment_source text,
    p_provider_references jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    -- One establishment instant for every fact this operation records.
    establishment_instant constant timestamptz := statement_timestamp();
    normalized_display_name text;
    normalized_establishment_source text;
    requested_digest bytea;
    existing_organization public.veterinary_organizations%rowtype;
    created_organization_id uuid;
    created_membership_id uuid;
    created_subscription_id uuid;
begin
    -- 1. Shape. Nothing is read or written before the input is coherent.
    if p_establishment_idempotency_key is null then
        raise exception 'Organization establishment idempotency key is required'
            using errcode = '22023';
    end if;

    if p_owner_user_id is null then
        raise exception 'The designated initial Owner is required'
            using errcode = '22023';
    end if;

    normalized_display_name := btrim(p_organization_display_name, E' \t\n\r\f\013');

    if normalized_display_name is null or normalized_display_name = '' then
        raise exception 'Veterinary Organization display name must not be blank'
            using errcode = '22023';
    end if;

    if p_initial_subscription_state is null
       or p_initial_subscription_state not in (
           'PENDING', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED'
       ) then
        raise exception 'Unsupported initial Organization Subscription state'
            using errcode = '22023';
    end if;

    if (p_initial_state_effective_at is not null and not isfinite(p_initial_state_effective_at))
       or (p_commercial_valid_from is not null and not isfinite(p_commercial_valid_from))
       or (p_commercial_valid_until is not null and not isfinite(p_commercial_valid_until)) then
        raise exception 'Organization establishment times must be finite'
            using errcode = '22023';
    end if;

    if p_commercial_valid_from is not null
       and p_commercial_valid_until is not null
       and p_commercial_valid_from >= p_commercial_valid_until then
        raise exception 'Initial commercial validity interval is incoherent'
            using errcode = '22023';
    end if;

    normalized_establishment_source := btrim(p_establishment_source, E' \t\n\r\f\013');

    if normalized_establishment_source is null or normalized_establishment_source = '' then
        raise exception 'Organization establishment source must not be blank'
            using errcode = '22023';
    end if;

    if p_provider_references is not null then
        if jsonb_typeof(p_provider_references) <> 'array'
           or exists (
               select 1
               from jsonb_array_elements(p_provider_references) as reference_payload
               where jsonb_typeof(reference_payload) <> 'object'
                  or reference_payload ->> 'provider' is null
                  or btrim(reference_payload ->> 'provider', E' \t\n\r\f\013') = ''
                  or reference_payload ->> 'reference_kind' is null
                  or reference_payload ->> 'reference_kind' not in ('CUSTOMER', 'SUBSCRIPTION')
                  or reference_payload ->> 'opaque_reference' is null
                  or btrim(reference_payload ->> 'opaque_reference', E' \t\n\r\f\013') = ''
           )
           or jsonb_array_length(public.canonical_subscription_provider_references(p_provider_references))
              <> jsonb_array_length(p_provider_references) then
            raise exception 'Subscription Provider Reference payload is invalid'
                using errcode = '22023';
        end if;
    end if;

    -- The requested inputs, canonical and timezone-independent (epoch
    -- seconds). An omitted initial effective time is recorded as omitted.
    requested_digest := sha256(convert_to(jsonb_build_object(
        'owner_user_id', p_owner_user_id,
        'display_name', normalized_display_name,
        'initial_state', p_initial_subscription_state,
        'initial_state_effective_at', extract(epoch from p_initial_state_effective_at),
        'commercial_valid_from', extract(epoch from p_commercial_valid_from),
        'commercial_valid_until', extract(epoch from p_commercial_valid_until),
        'establishment_source', normalized_establishment_source,
        'provider_references', public.canonical_subscription_provider_references(p_provider_references)
    )::text, 'UTF8'));

    -- 2-3. Exact replay or contradictory reuse of an existing establishment.
    select organization.*
    into existing_organization
    from public.veterinary_organizations as organization
    where organization.establishment_idempotency_key = p_establishment_idempotency_key;

    if found then
        return public.replay_veterinary_organization_establishment(
            existing_organization, requested_digest
        );
    end if;

    -- The key is shared with the initial Subscription; a key already used by
    -- another Subscription is a different intent.
    if exists (
        select 1
        from public.organization_subscriptions as subscription
        where subscription.establishment_idempotency_key = p_establishment_idempotency_key
    ) then
        raise exception 'Organization establishment key was already used with different facts'
            using errcode = '23505',
                  hint = 'ESTABLISHMENT_KEY_CONFLICT';
    end if;

    -- 4. Owner identity and account eligibility (SPEC-ORG-001 BR-16).
    perform public.assert_initial_owner_eligible(p_owner_user_id, establishment_instant);

    -- 5. Initial Subscription policy (SPEC-SUB-001 §14).
    if p_initial_subscription_state not in ('PENDING', 'ACTIVE') then
        raise exception 'A Subscription can only be established as PENDING or ACTIVE in Phase 1'
            using errcode = '23514',
                  hint = 'INITIAL_STATE_NOT_ALLOWED';
    end if;

    if p_initial_state_effective_at > establishment_instant then
        raise exception 'A Subscription cannot be established with a future-dated initial state'
            using errcode = '23514',
                  hint = 'FUTURE_EFFECTIVE_AT';
    end if;

    -- 6. Writes. A concurrent request with the same key waits here for the
    -- first to finish; if it committed, its establishment is replayed.
    insert into public.veterinary_organizations (
        display_name,
        establishment_idempotency_key,
        establishment_request_digest
    )
    values (
        normalized_display_name,
        p_establishment_idempotency_key,
        requested_digest
    )
    on conflict (establishment_idempotency_key) do nothing
    returning id into created_organization_id;

    if created_organization_id is null then
        select organization.*
        into existing_organization
        from public.veterinary_organizations as organization
        where organization.establishment_idempotency_key = p_establishment_idempotency_key;

        if not found then
            raise exception 'A concurrent Organization establishment is not visible to this transaction'
                using errcode = '40001';
        end if;

        return public.replay_veterinary_organization_establishment(
            existing_organization, requested_digest
        );
    end if;

    insert into public.organization_memberships (
        organization_id,
        user_id,
        effective_start
    )
    values (
        created_organization_id,
        p_owner_user_id,
        establishment_instant
    )
    returning id into created_membership_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id
    )
    values (
        created_membership_id,
        'OWNER',
        'ORGANIZATION',
        null,
        establishment_instant,
        p_owner_user_id
    );

    insert into public.organization_subscriptions (
        organization_id,
        established_at,
        initiated_by_user_id,
        initial_state,
        initial_state_effective_at,
        initial_commercial_valid_from,
        initial_commercial_valid_until,
        establishment_source,
        establishment_idempotency_key
    )
    values (
        created_organization_id,
        establishment_instant,
        null,
        p_initial_subscription_state,
        coalesce(p_initial_state_effective_at, establishment_instant),
        p_commercial_valid_from,
        p_commercial_valid_until,
        normalized_establishment_source,
        p_establishment_idempotency_key
    )
    returning id into created_subscription_id;

    if p_provider_references is not null then
        insert into public.subscription_provider_references (
            subscription_id,
            provider,
            reference_kind,
            opaque_reference,
            recorded_at
        )
        select
            created_subscription_id,
            btrim(reference_payload ->> 'provider', E' \t\n\r\f\013'),
            reference_payload ->> 'reference_kind',
            btrim(reference_payload ->> 'opaque_reference', E' \t\n\r\f\013'),
            establishment_instant
        from jsonb_array_elements(p_provider_references) as reference_payload;
    end if;

    -- Surface the deferred invariants these writes queued (active Owner,
    -- Grant minimum, Grant within Membership, Invitation origin, single
    -- current Subscription) before reporting success, then restore their
    -- declared DEFERRED mode. Only these named constraint triggers change mode.
    set constraints
        public.veterinary_organizations_require_active_owner,
        public.organization_memberships_require_grant,
        public.organization_grants_preserve_membership_minimum,
        public.organization_memberships_preserve_active_owner,
        public.organization_responsibility_grants_preserve_active_owner,
        public.organization_memberships_enforce_grant_periods,
        public.organization_responsibility_grants_enforce_membership_period,
        public.organization_memberships_enforce_invitation_acceptance,
        public.organization_responsibility_grants_enforce_invitation_origin,
        public.organization_subscriptions_preserve_single_current
    immediate;

    set constraints
        public.veterinary_organizations_require_active_owner,
        public.organization_memberships_require_grant,
        public.organization_grants_preserve_membership_minimum,
        public.organization_memberships_preserve_active_owner,
        public.organization_responsibility_grants_preserve_active_owner,
        public.organization_memberships_enforce_grant_periods,
        public.organization_responsibility_grants_enforce_membership_period,
        public.organization_memberships_enforce_invitation_acceptance,
        public.organization_responsibility_grants_enforce_invitation_origin,
        public.organization_subscriptions_preserve_single_current
    deferred;

    return jsonb_build_object(
        'organization_id', created_organization_id,
        'owner_membership_id', created_membership_id,
        'subscription_id', created_subscription_id,
        'outcome', 'ESTABLISHED'
    );
end;
$$;

-- Replay of an existing establishment: same requested inputs return the
-- original identifiers; anything else is contradictory reuse of the key.
create function public.replay_veterinary_organization_establishment(
    p_organization public.veterinary_organizations,
    p_requested_digest bytea
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    initial_membership_id uuid;
    initial_subscription_id uuid;
begin
    if p_organization.establishment_request_digest is distinct from p_requested_digest then
        raise exception 'Organization establishment key was already used with different facts'
            using errcode = '23505',
                  hint = 'ESTABLISHMENT_KEY_CONFLICT';
    end if;

    -- The initial Owner Membership: the earliest Membership not created from
    -- an Invitation (nothing in the Organization can precede establishment).
    select membership.id
    into initial_membership_id
    from public.organization_memberships as membership
    where membership.organization_id = p_organization.id
      and membership.originating_invitation_id is null
    order by membership.effective_start, membership.id
    limit 1;

    select subscription.id
    into initial_subscription_id
    from public.organization_subscriptions as subscription
    where subscription.organization_id = p_organization.id
      and subscription.establishment_idempotency_key = p_organization.establishment_idempotency_key;

    if initial_membership_id is null or initial_subscription_id is null then
        raise exception 'Organization establishment record is incomplete'
            using errcode = '55000';
    end if;

    return jsonb_build_object(
        'organization_id', p_organization.id,
        'owner_membership_id', initial_membership_id,
        'subscription_id', initial_subscription_id,
        'outcome', 'ALREADY_ESTABLISHED'
    );
end;
$$;

revoke all privileges
on function public.replay_veterinary_organization_establishment(public.veterinary_organizations, bytea)
from public, anon, authenticated, service_role;

revoke all privileges
on function public.establish_veterinary_organization(
    uuid, text, uuid, text, timestamptz, timestamptz, timestamptz, text, jsonb
)
from public, anon, authenticated, service_role;

grant execute
on function public.establish_veterinary_organization(
    uuid, text, uuid, text, timestamptz, timestamptz, timestamptz, text, jsonb
)
to service_role;

-- ==================================================================
-- 6. The former composable boundary is removed.
-- ==================================================================

drop function public.create_veterinary_organization(text);

commit;

-- Subscription Operational Safety — Phase 1 (ADR-006 amendment,
-- SPEC-SUB-002 §5/§14/§15, SPEC-SUB-003 §4/§15, SPEC-SUB-004 BR-20/§14,
-- SPEC-MED-004 BR-33).
--
-- Approved Phase 1 manual commercial policy, enforced here:
--
--   * explicit transition graph (every other pair, same-state included, is
--     rejected):
--         PENDING   -> ACTIVE   | EXPIRED
--         ACTIVE    -> PAST_DUE | CANCELLED | EXPIRED
--         PAST_DUE  -> ACTIVE   | EXPIRED
--         CANCELLED -> EXPIRED
--   * EXPIRED is terminal for that Subscription period; PENDING -> EXPIRED
--     closes a relationship that never became active;
--   * establishment starts only as PENDING or ACTIVE, with an initial
--     effective time not later than statement_timestamp();
--   * no future-dated transitions: effective_at <= statement_timestamp(),
--     still strictly later than the current state's effective instant;
--   * each transition carries its own validity; nothing is inherited;
--   * an open-ended ACTIVE (no valid_until) keeps normal Entitlements until an
--     explicit trusted transition changes it — unchanged evaluation, nothing
--     here creates a valid_until.
--
-- Diagnostics: every policy rejection is SQLSTATE 23514 with a stable HINT:
--   SUBSCRIPTION_EXPIRED_TERMINAL, SUBSCRIPTION_TRANSITION_NOT_ALLOWED,
--   FUTURE_EFFECTIVE_AT, STALE_EFFECTIVE_AT, INITIAL_STATE_NOT_ALLOWED.
--
-- Also:
--   * get_organization_subscription_status(uuid): authenticated-only status
--     read for ORGANIZATION_MANAGE_SUBSCRIPTION holders (SPEC-SUB-002 §15);
--   * create_clinical_amendment no longer requires current
--     CLINICAL_DOCUMENTATION Entitlement (SPEC-SUB-004 BR-20). The current
--     Veterinarian context and CLINICAL_DOCUMENTATION capability are still
--     required; Encounter creation keeps its CLINICAL_CARE Entitlement gate.
--
-- Unchanged: tables, constraints, existing rows, derivation
-- (derive_organization_subscription_current_state), Entitlement evaluation
-- (organization_has_professional_entitlement), every ACL other than the new
-- read, and establishment/transition idempotency (exact replays of an already
-- established Subscription or accepted transition are still recognized before
-- the policy checks).

begin;

-- ==================================================================
-- 1. The Phase 1 transition graph (one definition for the trusted
--    operation and the insert trigger).
-- ==================================================================

create function public.subscription_transition_is_allowed(
    p_from_state text,
    p_to_state text
)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select (p_from_state, p_to_state) in (
        ('PENDING', 'ACTIVE'),
        ('PENDING', 'EXPIRED'),
        ('ACTIVE', 'PAST_DUE'),
        ('ACTIVE', 'CANCELLED'),
        ('ACTIVE', 'EXPIRED'),
        ('PAST_DUE', 'ACTIVE'),
        ('PAST_DUE', 'EXPIRED'),
        ('CANCELLED', 'EXPIRED')
    )
$$;

revoke all privileges
on function public.subscription_transition_is_allowed(text, text)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 2. Trusted transition operation.
-- ==================================================================

create or replace function public.apply_subscription_state_transition(
    p_subscription_id uuid,
    p_to_state text,
    p_effective_at timestamptz,
    p_commercial_valid_from timestamptz,
    p_commercial_valid_until timestamptz,
    p_source_system text,
    p_source_event_key text default null
)
returns table (
    transition_id uuid,
    subscription_id uuid,
    from_state text,
    to_state text,
    effective_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_organization_id uuid;
    normalized_to_state text;
    normalized_source_system text;
    normalized_source_event_key text;
    operation_timestamp timestamptz;
    derived_current_state text;
    derived_current_effective_at timestamptz;
    existing_transition_record public.subscription_state_transitions%rowtype;
    created_transition_id uuid;
begin
    if p_subscription_id is null then
        raise exception 'Organization Subscription is required'
            using errcode = '22023';
    end if;

    normalized_to_state := p_to_state;

    if normalized_to_state is null
       or normalized_to_state not in (
           'PENDING', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED'
       ) then
        raise exception 'Unsupported Subscription state transition target'
            using errcode = '22023';
    end if;

    if p_effective_at is null
       or p_effective_at = 'infinity'::timestamptz
       or p_effective_at = '-infinity'::timestamptz then
        raise exception 'Subscription state transition effective time must be finite'
            using errcode = '22023';
    end if;

    if p_commercial_valid_from is not null
       and (
           p_commercial_valid_from = 'infinity'::timestamptz
           or p_commercial_valid_from = '-infinity'::timestamptz
       ) then
        raise exception 'Subscription state transition commercial validity start must be finite'
            using errcode = '22023';
    end if;

    if p_commercial_valid_until is not null
       and (
           p_commercial_valid_until = 'infinity'::timestamptz
           or p_commercial_valid_until = '-infinity'::timestamptz
       ) then
        raise exception 'Subscription state transition commercial validity end must be finite'
            using errcode = '22023';
    end if;

    if p_commercial_valid_from is not null
       and p_commercial_valid_until is not null
       and p_commercial_valid_from >= p_commercial_valid_until then
        raise exception 'Subscription state transition commercial validity interval is incoherent'
            using errcode = '22023';
    end if;

    normalized_source_system := btrim(p_source_system, E' \t\n\r\f\013');

    if normalized_source_system is null or normalized_source_system = '' then
        raise exception 'Subscription state transition source system must not be blank'
            using errcode = '22023';
    end if;

    normalized_source_event_key := btrim(p_source_event_key, E' \t\n\r\f\013');

    if normalized_source_event_key = '' then
        raise exception 'Subscription state transition source event key must not be blank when supplied'
            using errcode = '22023';
    end if;

    select subscription.organization_id
    into target_organization_id
    from public.organization_subscriptions as subscription
    where subscription.id = p_subscription_id;

    if not found then
        raise exception 'Organization Subscription does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.organization_subscriptions as subscription
    where subscription.id = p_subscription_id
    for update;

    select derived.current_state, derived.current_state_effective_at
    into derived_current_state, derived_current_effective_at
    from public.derive_organization_subscription_current_state(p_subscription_id) as derived;

    -- Exact replays of an already accepted transition are recognized first, so
    -- a retry stays harmless even after later transitions (ADR-006).
    if normalized_source_event_key is not null then
        select transition.*
        into existing_transition_record
        from public.subscription_state_transitions as transition
        where transition.subscription_id = p_subscription_id
          and transition.source_system = normalized_source_system
          and transition.source_event_key = normalized_source_event_key
        for update;

        if found then
            if existing_transition_record.effective_at = p_effective_at
               and existing_transition_record.to_state = normalized_to_state
               and existing_transition_record.commercial_valid_from
                   is not distinct from p_commercial_valid_from
               and existing_transition_record.commercial_valid_until
                   is not distinct from p_commercial_valid_until then
                return query
                select
                    existing_transition_record.id,
                    existing_transition_record.subscription_id,
                    existing_transition_record.from_state,
                    existing_transition_record.to_state,
                    existing_transition_record.effective_at;
                return;
            end if;

            raise exception 'Subscription source event % under % was already recorded with different facts',
                normalized_source_event_key, normalized_source_system
                using errcode = '23505';
        end if;
    else
        select transition.*
        into existing_transition_record
        from public.subscription_state_transitions as transition
        where transition.subscription_id = p_subscription_id
          and transition.source_system = normalized_source_system
          and transition.effective_at = p_effective_at
          and transition.to_state = normalized_to_state
          and transition.commercial_valid_from is not distinct from p_commercial_valid_from
          and transition.commercial_valid_until is not distinct from p_commercial_valid_until
        for update;

        if found then
            return query
            select
                existing_transition_record.id,
                existing_transition_record.subscription_id,
                existing_transition_record.from_state,
                existing_transition_record.to_state,
                existing_transition_record.effective_at;
            return;
        end if;
    end if;

    -- Phase 1 policy (SPEC-SUB-002 §5/§14).
    if derived_current_state = 'EXPIRED' then
        raise exception 'An EXPIRED Subscription period is terminal; establish a new Subscription period instead'
            using errcode = '23514',
                  hint = 'SUBSCRIPTION_EXPIRED_TERMINAL';
    end if;

    if p_effective_at > statement_timestamp() then
        raise exception 'Future-dated Subscription transitions are not supported'
            using errcode = '23514',
                  hint = 'FUTURE_EFFECTIVE_AT';
    end if;

    if p_effective_at <= derived_current_effective_at then
        raise exception 'Subscription state transition effective time must be strictly later than the current accepted state'
            using errcode = '23514',
                  hint = 'STALE_EFFECTIVE_AT';
    end if;

    if normalized_to_state = derived_current_state then
        raise exception 'Subscription state transition target must differ from the current accepted state'
            using errcode = '23514',
                  hint = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED';
    end if;

    if not public.subscription_transition_is_allowed(derived_current_state, normalized_to_state) then
        raise exception 'Subscription transition % -> % is not allowed in Phase 1',
            derived_current_state, normalized_to_state
            using errcode = '23514',
                  hint = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.subscription_state_transitions (
        subscription_id,
        from_state,
        to_state,
        effective_at,
        recorded_at,
        commercial_valid_from,
        commercial_valid_until,
        source_system,
        source_event_key
    )
    values (
        p_subscription_id,
        derived_current_state,
        normalized_to_state,
        p_effective_at,
        operation_timestamp,
        p_commercial_valid_from,
        p_commercial_valid_until,
        normalized_source_system,
        normalized_source_event_key
    )
    returning id into created_transition_id;

    return query
    select
        created_transition_id,
        p_subscription_id,
        derived_current_state,
        normalized_to_state,
        p_effective_at;
end;
$$;

-- ==================================================================
-- 2b. Trusted establishment: Phase 1 initial state.
--     Identical to 20260826113000 except the two Phase 1 checks after the
--     idempotent-replay lookup. Same signature, result, attributes, ACL and
--     idempotency; validity is never forced (open-ended ACTIVE stays valid).
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
           or existing_subscription_record.establishment_source <> normalized_establishment_source then
            raise exception 'Organization Subscription establishment idempotency key % was already used with different facts',
                p_establishment_idempotency_key
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
-- 3. Insert-trigger backstop: the same policy holds for any insert path.
-- ==================================================================

create or replace function public.enforce_subscription_state_transition_sequence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_organization_id uuid;
    derived_current_state text;
    derived_current_effective_at timestamptz;
begin
    select subscription.organization_id
    into target_organization_id
    from public.organization_subscriptions as subscription
    where subscription.id = new.subscription_id;

    if not found then
        raise exception 'Organization Subscription does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.organization_subscriptions as subscription
    where subscription.id = new.subscription_id
    for update;

    select derived.current_state, derived.current_state_effective_at
    into derived_current_state, derived_current_effective_at
    from public.derive_organization_subscription_current_state(new.subscription_id) as derived;

    if new.from_state <> derived_current_state then
        raise exception 'Subscription Transition from_state must match the current accepted state'
            using errcode = '23514';
    end if;

    if derived_current_state = 'EXPIRED' then
        raise exception 'An EXPIRED Subscription period is terminal'
            using errcode = '23514',
                  hint = 'SUBSCRIPTION_EXPIRED_TERMINAL';
    end if;

    if new.effective_at > statement_timestamp() then
        raise exception 'Future-dated Subscription transitions are not supported'
            using errcode = '23514',
                  hint = 'FUTURE_EFFECTIVE_AT';
    end if;

    if new.effective_at <= derived_current_effective_at then
        raise exception 'Subscription Transition effective time must be strictly later than the current accepted state'
            using errcode = '23514',
                  hint = 'STALE_EFFECTIVE_AT';
    end if;

    if new.to_state = derived_current_state then
        raise exception 'Subscription Transition target must differ from the current accepted state'
            using errcode = '23514',
                  hint = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED';
    end if;

    if not public.subscription_transition_is_allowed(new.from_state, new.to_state) then
        raise exception 'Subscription transition % -> % is not allowed in Phase 1',
            new.from_state, new.to_state
            using errcode = '23514',
                  hint = 'SUBSCRIPTION_TRANSITION_NOT_ALLOWED';
    end if;

    return new;
end;
$$;

-- ==================================================================
-- 4. SPEC-SUB-002 §15 — Organization Subscription status read.
-- ==================================================================

create function public.get_organization_subscription_status(
    p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    organization_name text;
    status_subscription jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- Decided before any Organization fact: unknown and inaccessible
    -- Organizations fail identically.
    if p_organization_id is null
       or not public.user_has_organization_capability(
           acting_user_id, p_organization_id, 'ORGANIZATION_MANAGE_SUBSCRIPTION'
       ) then
        raise exception 'Organization Subscription status unavailable'
            using errcode = '42501';
    end if;

    select organization.display_name
    into organization_name
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id;

    -- The current relationship (non-EXPIRED); otherwise the most recently
    -- established period. Stored state as derived, never inferred.
    select jsonb_build_object(
        'state', derived.current_state,
        'state_effective_at', derived.current_state_effective_at,
        'valid_from', derived.current_commercial_valid_from,
        'valid_until', derived.current_commercial_valid_until
    )
    into status_subscription
    from public.organization_subscriptions as subscription
    cross join lateral
        public.derive_organization_subscription_current_state(subscription.id) as derived
    where subscription.organization_id = p_organization_id
    order by (derived.current_state = 'EXPIRED'),
             subscription.established_at desc,
             subscription.id desc
    limit 1;

    return jsonb_build_object(
        'organization_id', p_organization_id,
        'organization_display_name', organization_name,
        'subscription', status_subscription,
        'entitlements', jsonb_build_object(
            'APPOINTMENT_MANAGEMENT',
            public.organization_has_professional_entitlement(p_organization_id, 'APPOINTMENT_MANAGEMENT'),
            'PROFESSIONAL_SCHEDULING',
            public.organization_has_professional_entitlement(p_organization_id, 'PROFESSIONAL_SCHEDULING'),
            'CLINICAL_CARE',
            public.organization_has_professional_entitlement(p_organization_id, 'CLINICAL_CARE'),
            'CLINICAL_DOCUMENTATION',
            public.organization_has_professional_entitlement(p_organization_id, 'CLINICAL_DOCUMENTATION')
        )
    );
end;
$$;

revoke all privileges
on function public.get_organization_subscription_status(uuid)
from public, anon, authenticated, service_role;

grant execute
on function public.get_organization_subscription_status(uuid)
to authenticated;

-- ==================================================================
-- 5. SPEC-SUB-004 BR-20 — Amendment continuity after Entitlement loss.
--    Identical to 20260829120000 except that the Veterinarian context is
--    resolved without an Entitlement requirement. Same signature, result,
--    attributes, idempotency and ACL.
-- ==================================================================

create or replace function public.create_clinical_amendment(
    p_original_clinical_record_entry_id uuid,
    p_reason text,
    p_amendment_content text,
    p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    professional_context record;
    normalized_reason text;
    normalized_content text;
    amendment_record public.clinical_amendments%rowtype;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    normalized_content := nullif(btrim(p_amendment_content, E' \t\n\r\f\013'), '');
    if normalized_reason is null or normalized_content is null or p_idempotency_key is null then
        raise exception 'Amendment reason, content, and idempotency key are required' using errcode = '22023';
    end if;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_original_clinical_record_entry_id;
    if not found then raise exception 'Original Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    -- SPEC-SUB-004 BR-20: commercial loss never blocks a necessary correction;
    -- the current Veterinarian context and capability are still required.
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_original_clinical_record_entry_id for share;

    insert into public.clinical_amendments (
        original_clinical_record_entry_id, reason, amendment_content,
        amending_user_id, amending_veterinarian_clinic_assignment_id,
        created_at, idempotency_key
    ) values (
        p_original_clinical_record_entry_id, normalized_reason, normalized_content,
        acting_user_id, professional_context.veterinarian_clinic_assignment_id,
        clock_timestamp(), p_idempotency_key
    ) on conflict (amending_user_id, idempotency_key) do nothing;

    select clinical_amendment.* into amendment_record
    from public.clinical_amendments as clinical_amendment
    where clinical_amendment.amending_user_id = acting_user_id
      and clinical_amendment.idempotency_key = p_idempotency_key;
    if amendment_record.original_clinical_record_entry_id is distinct from p_original_clinical_record_entry_id
       or amendment_record.reason is distinct from normalized_reason
       or amendment_record.amendment_content is distinct from normalized_content
       or amendment_record.amending_veterinarian_clinic_assignment_id is distinct from
          professional_context.veterinarian_clinic_assignment_id then
        raise exception 'Idempotency key was already used with a different Amendment request' using errcode = '23505';
    end if;
    return amendment_record.id;
end;
$$;

commit;

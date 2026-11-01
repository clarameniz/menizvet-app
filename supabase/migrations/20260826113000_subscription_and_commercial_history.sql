begin;

create table public.organization_subscriptions (
    id uuid not null default gen_random_uuid(),
    organization_id uuid not null,
    established_at timestamptz not null,
    initiated_by_user_id uuid,
    initial_state text not null,
    initial_state_effective_at timestamptz not null,
    initial_commercial_valid_from timestamptz,
    initial_commercial_valid_until timestamptz,
    establishment_source text not null,
    establishment_idempotency_key uuid not null,
    constraint organization_subscriptions_pkey primary key (id),
    constraint organization_subscriptions_organization_id_fkey
        foreign key (organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict,
    constraint organization_subscriptions_initiated_by_user_id_fkey
        foreign key (initiated_by_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint organization_subscriptions_establishment_idempotency_key_key
        unique (establishment_idempotency_key),
    constraint organization_subscriptions_initial_state_check
        check (
            initial_state in (
                'PENDING',
                'ACTIVE',
                'PAST_DUE',
                'CANCELLED',
                'EXPIRED'
            )
        ),
    constraint organization_subscriptions_established_at_finite_check
        check (
            established_at <> 'infinity'::timestamptz
            and established_at <> '-infinity'::timestamptz
        ),
    constraint organization_subscriptions_initial_effective_finite_check
        check (
            initial_state_effective_at <> 'infinity'::timestamptz
            and initial_state_effective_at <> '-infinity'::timestamptz
        ),
    constraint organization_subscriptions_initial_valid_from_finite_check
        check (
            initial_commercial_valid_from is null
            or (
                initial_commercial_valid_from <> 'infinity'::timestamptz
                and initial_commercial_valid_from <> '-infinity'::timestamptz
            )
        ),
    constraint organization_subscriptions_initial_valid_until_finite_check
        check (
            initial_commercial_valid_until is null
            or (
                initial_commercial_valid_until <> 'infinity'::timestamptz
                and initial_commercial_valid_until <> '-infinity'::timestamptz
            )
        ),
    constraint organization_subscriptions_initial_validity_interval_check
        check (
            initial_commercial_valid_until is null
            or initial_commercial_valid_from is null
            or initial_commercial_valid_from < initial_commercial_valid_until
        ),
    constraint organization_subscriptions_establishment_source_check
        check (
            establishment_source = btrim(establishment_source, E' \t\n\r\f\013')
            and establishment_source <> ''
        )
);

create index organization_subscriptions_organization_id_idx
on public.organization_subscriptions (organization_id);

create table public.subscription_provider_references (
    id uuid not null default gen_random_uuid(),
    subscription_id uuid not null,
    provider text not null,
    reference_kind text not null,
    opaque_reference text not null,
    recorded_at timestamptz not null,
    constraint subscription_provider_references_pkey primary key (id),
    constraint subscription_provider_references_subscription_id_fkey
        foreign key (subscription_id)
        references public.organization_subscriptions (id)
        on update no action
        on delete restrict,
    constraint subscription_provider_references_reference_kind_check
        check (reference_kind in ('CUSTOMER', 'SUBSCRIPTION')),
    constraint subscription_provider_references_provider_check
        check (
            provider = btrim(provider, E' \t\n\r\f\013')
            and provider <> ''
        ),
    constraint subscription_provider_references_opaque_reference_check
        check (
            opaque_reference = btrim(opaque_reference, E' \t\n\r\f\013')
            and opaque_reference <> ''
        ),
    constraint subscription_provider_references_recorded_at_finite_check
        check (
            recorded_at <> 'infinity'::timestamptz
            and recorded_at <> '-infinity'::timestamptz
        ),
    constraint subscription_provider_references_exact_mapping_key
        unique (subscription_id, provider, reference_kind, opaque_reference)
);

create index subscription_provider_references_reconciliation_idx
on public.subscription_provider_references (provider, reference_kind, opaque_reference);

create table public.subscription_state_transitions (
    id uuid not null default gen_random_uuid(),
    subscription_id uuid not null,
    from_state text not null,
    to_state text not null,
    effective_at timestamptz not null,
    recorded_at timestamptz not null,
    commercial_valid_from timestamptz,
    commercial_valid_until timestamptz,
    source_system text not null,
    source_event_key text,
    constraint subscription_state_transitions_pkey primary key (id),
    constraint subscription_state_transitions_subscription_id_fkey
        foreign key (subscription_id)
        references public.organization_subscriptions (id)
        on update no action
        on delete restrict,
    constraint subscription_state_transitions_from_state_check
        check (
            from_state in (
                'PENDING',
                'ACTIVE',
                'PAST_DUE',
                'CANCELLED',
                'EXPIRED'
            )
        ),
    constraint subscription_state_transitions_to_state_check
        check (
            to_state in (
                'PENDING',
                'ACTIVE',
                'PAST_DUE',
                'CANCELLED',
                'EXPIRED'
            )
        ),
    constraint subscription_state_transitions_state_change_check
        check (from_state <> to_state),
    constraint subscription_state_transitions_effective_at_finite_check
        check (
            effective_at <> 'infinity'::timestamptz
            and effective_at <> '-infinity'::timestamptz
        ),
    constraint subscription_state_transitions_recorded_at_finite_check
        check (
            recorded_at <> 'infinity'::timestamptz
            and recorded_at <> '-infinity'::timestamptz
        ),
    constraint subscription_state_transitions_valid_from_finite_check
        check (
            commercial_valid_from is null
            or (
                commercial_valid_from <> 'infinity'::timestamptz
                and commercial_valid_from <> '-infinity'::timestamptz
            )
        ),
    constraint subscription_state_transitions_valid_until_finite_check
        check (
            commercial_valid_until is null
            or (
                commercial_valid_until <> 'infinity'::timestamptz
                and commercial_valid_until <> '-infinity'::timestamptz
            )
        ),
    constraint subscription_state_transitions_validity_interval_check
        check (
            commercial_valid_until is null
            or commercial_valid_from is null
            or commercial_valid_from < commercial_valid_until
        ),
    constraint subscription_state_transitions_source_system_check
        check (
            source_system = btrim(source_system, E' \t\n\r\f\013')
            and source_system <> ''
        ),
    constraint subscription_state_transitions_source_event_key_check
        check (
            source_event_key is null
            or (
                source_event_key = btrim(source_event_key, E' \t\n\r\f\013')
                and source_event_key <> ''
            )
        ),
    constraint subscription_state_transitions_subscription_effective_key
        unique (subscription_id, effective_at)
);

create index subscription_state_transitions_subscription_history_idx
on public.subscription_state_transitions (subscription_id, effective_at desc, id desc);

create unique index subscription_state_transitions_source_event_key
on public.subscription_state_transitions (subscription_id, source_system, source_event_key)
where source_event_key is not null;

create function public.enforce_organization_subscription_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Organization Subscriptions cannot be deleted'
            using errcode = '23514';
    end if;

    raise exception 'Organization Subscription establishment facts are immutable'
        using errcode = '23514';
end;
$$;

revoke all privileges
on function public.enforce_organization_subscription_immutability()
from public, anon, authenticated;

create trigger organization_subscriptions_preserve_history
before update or delete on public.organization_subscriptions
for each row
execute function public.enforce_organization_subscription_immutability();

create function public.enforce_subscription_provider_reference_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Subscription Provider References cannot be deleted'
            using errcode = '23514';
    end if;

    raise exception 'Subscription Provider References are immutable'
        using errcode = '23514';
end;
$$;

revoke all privileges
on function public.enforce_subscription_provider_reference_immutability()
from public, anon, authenticated;

create trigger subscription_provider_references_preserve_history
before update or delete on public.subscription_provider_references
for each row
execute function public.enforce_subscription_provider_reference_immutability();

create function public.enforce_subscription_state_transition_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Subscription State Transitions cannot be deleted'
            using errcode = '23514';
    end if;

    raise exception 'Subscription State Transitions are immutable'
        using errcode = '23514';
end;
$$;

revoke all privileges
on function public.enforce_subscription_state_transition_immutability()
from public, anon, authenticated;

create trigger subscription_state_transitions_preserve_history
before update or delete on public.subscription_state_transitions
for each row
execute function public.enforce_subscription_state_transition_immutability();

create function public.derive_organization_subscription_current_state(
    p_subscription_id uuid
)
returns table (
    current_state text,
    current_state_effective_at timestamptz,
    current_commercial_valid_from timestamptz,
    current_commercial_valid_until timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        case
            when latest_transition.id is not null then latest_transition.to_state
            else subscription.initial_state
        end,
        case
            when latest_transition.id is not null then latest_transition.effective_at
            else subscription.initial_state_effective_at
        end,
        case
            when latest_transition.id is not null then latest_transition.commercial_valid_from
            else subscription.initial_commercial_valid_from
        end,
        case
            when latest_transition.id is not null then latest_transition.commercial_valid_until
            else subscription.initial_commercial_valid_until
        end
    from public.organization_subscriptions as subscription
    left join lateral (
        select
            transition.id,
            transition.to_state,
            transition.effective_at,
            transition.commercial_valid_from,
            transition.commercial_valid_until
        from public.subscription_state_transitions as transition
        where transition.subscription_id = subscription.id
        order by transition.effective_at desc, transition.id desc
        limit 1
    ) as latest_transition on true
    where subscription.id = p_subscription_id
$$;

revoke all privileges
on function public.derive_organization_subscription_current_state(uuid)
from public, anon, authenticated;

create function public.enforce_subscription_state_transition_sequence()
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

    if new.effective_at <= derived_current_effective_at then
        raise exception 'Subscription Transition effective time must be strictly later than the current accepted state'
            using errcode = '23514';
    end if;

    if new.to_state = derived_current_state then
        raise exception 'Subscription Transition target must differ from the current accepted state'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_subscription_state_transition_sequence()
from public, anon, authenticated;

create trigger subscription_state_transitions_enforce_sequence
before insert on public.subscription_state_transitions
for each row
execute function public.enforce_subscription_state_transition_sequence();

create function public.assert_organization_single_current_subscription(
    p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    non_expired_count integer;
begin
    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found then
        return;
    end if;

    select count(*)
    into non_expired_count
    from public.organization_subscriptions as subscription
    cross join lateral
        public.derive_organization_subscription_current_state(subscription.id) as derived
    where subscription.organization_id = p_organization_id
      and derived.current_state <> 'EXPIRED';

    if non_expired_count > 1 then
        raise exception 'Veterinary Organization % may have at most one non-EXPIRED current Subscription relationship',
            p_organization_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_organization_single_current_subscription(uuid)
from public, anon, authenticated;

create function public.enforce_organization_single_current_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_organization_id uuid;
begin
    if tg_table_name = 'organization_subscriptions' then
        target_organization_id := new.organization_id;
    elsif tg_table_name = 'subscription_state_transitions' then
        select subscription.organization_id
        into target_organization_id
        from public.organization_subscriptions as subscription
        where subscription.id = new.subscription_id;
    else
        raise exception 'Unexpected Subscription single-current trigger invocation'
            using errcode = '55000';
    end if;

    perform public.assert_organization_single_current_subscription(target_organization_id);

    return null;
end;
$$;

revoke all privileges
on function public.enforce_organization_single_current_subscription()
from public, anon, authenticated;

create constraint trigger organization_subscriptions_preserve_single_current
after insert on public.organization_subscriptions
deferrable initially deferred
for each row
execute function public.enforce_organization_single_current_subscription();

create constraint trigger subscription_state_transitions_preserve_single_current
after insert on public.subscription_state_transitions
deferrable initially deferred
for each row
execute function public.enforce_organization_single_current_subscription();

create function public.organization_has_professional_entitlement(
    p_organization_id uuid,
    p_entitlement_identifier text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    evaluation_time timestamptz := statement_timestamp();
    matching_subscription_count integer;
    current_state_value text;
    current_valid_from timestamptz;
    current_valid_until timestamptz;
begin
    if p_entitlement_identifier is null
       or p_entitlement_identifier not in (
           'APPOINTMENT_MANAGEMENT',
           'PROFESSIONAL_SCHEDULING',
           'CLINICAL_CARE',
           'CLINICAL_DOCUMENTATION'
       ) then
        raise exception 'Unsupported professional Entitlement identifier'
            using errcode = '22023';
    end if;

    select count(*)
    into matching_subscription_count
    from public.organization_subscriptions as subscription
    cross join lateral
        public.derive_organization_subscription_current_state(subscription.id) as derived
    where subscription.organization_id = p_organization_id
      and derived.current_state <> 'EXPIRED';

    if matching_subscription_count = 0 then
        return false;
    end if;

    if matching_subscription_count > 1 then
        raise exception 'Veterinary Organization % has more than one non-EXPIRED current Subscription relationship',
            p_organization_id
            using errcode = '23514';
    end if;

    select derived.current_state,
           derived.current_commercial_valid_from,
           derived.current_commercial_valid_until
    into current_state_value,
         current_valid_from,
         current_valid_until
    from public.organization_subscriptions as subscription
    cross join lateral
        public.derive_organization_subscription_current_state(subscription.id) as derived
    where subscription.organization_id = p_organization_id
      and derived.current_state <> 'EXPIRED';

    case current_state_value
        when 'ACTIVE' then
            return (
                (current_valid_from is null or evaluation_time >= current_valid_from)
                and (current_valid_until is null or evaluation_time < current_valid_until)
            );
        when 'CANCELLED' then
            return (
                current_valid_until is not null
                and evaluation_time < current_valid_until
                and (current_valid_from is null or evaluation_time >= current_valid_from)
            );
        else
            return false;
    end case;
end;
$$;

revoke all privileges
on function public.organization_has_professional_entitlement(uuid, text)
from public, anon, authenticated;

create or replace function public.user_has_organization_capability(
    p_user_id uuid,
    p_organization_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        coalesce(
            p_capability in (
                'ORGANIZATION_INVITE_MEMBERS',
                'ORGANIZATION_REVOKE_INVITATIONS',
                'ORGANIZATION_END_MEMBERSHIPS',
                'ORGANIZATION_GRANT_RESPONSIBILITIES',
                'ORGANIZATION_CREATE_CLINICS',
                'ORGANIZATION_MANAGE_SUBSCRIPTION'
            ),
            false
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as grant_record
              on grant_record.membership_id = membership.id
            where membership.user_id = p_user_id
              and membership.organization_id = p_organization_id
              and membership.effective_end is null
              and grant_record.effective_end is null
              and grant_record.scope_type = 'ORGANIZATION'
              and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
        )
$$;

revoke all privileges
on function public.user_has_organization_capability(uuid, uuid, text)
from public, anon, authenticated;

create function public.establish_organization_subscription(
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

revoke all privileges
on function public.establish_organization_subscription(
    uuid, uuid, text, timestamptz, timestamptz, timestamptz, text, uuid, jsonb
)
from public, anon, authenticated;

grant execute
on function public.establish_organization_subscription(
    uuid, uuid, text, timestamptz, timestamptz, timestamptz, text, uuid, jsonb
)
to service_role;

create function public.apply_subscription_state_transition(
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

    if p_effective_at <= derived_current_effective_at then
        raise exception 'Subscription state transition effective time must be strictly later than the current accepted state'
            using errcode = '23514';
    end if;

    if normalized_to_state = derived_current_state then
        raise exception 'Subscription state transition target must differ from the current accepted state'
            using errcode = '23514';
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

revoke all privileges
on function public.apply_subscription_state_transition(
    uuid, text, timestamptz, timestamptz, timestamptz, text, text
)
from public, anon, authenticated;

grant execute
on function public.apply_subscription_state_transition(
    uuid, text, timestamptz, timestamptz, timestamptz, text, text
)
to service_role;

alter table public.organization_subscriptions enable row level security;
alter table public.subscription_provider_references enable row level security;
alter table public.subscription_state_transitions enable row level security;

revoke all privileges on table public.organization_subscriptions
from public, anon, authenticated;
revoke all privileges on table public.subscription_provider_references
from public, anon, authenticated;
revoke all privileges on table public.subscription_state_transitions
from public, anon, authenticated;

commit;

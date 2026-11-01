-- ============================================================================
-- MenizVet — Subscription / legacy Organization inventory (READ-ONLY)
--
-- Diagnostic preflight for DEVELOPMENT or Production (ADR-009 legacy
-- Organizations; SPEC-SUB-001 BR-30; SPEC-SUB-002 §14; ADR-006).
--
-- * Strictly read-only: runs inside a READ ONLY transaction that is rolled
--   back. It changes no row, grant, policy, or function. It never fabricates,
--   backdates, or reconciles a Subscription: it only reports.
-- * Run deliberately with psql against the intended project, for example:
--       psql "<connection>" -v ON_ERROR_STOP=1 -f supabase/provisioning/subscription_inventory_readonly.sql
--   (in the Supabase SQL Editor, drop the \set line).
-- * Every section is a plain SELECT; an empty result means "none found".
-- * Section 9 classifies each Organization's establishment path; it runs both
--   before and after migration 20261101090000.
-- * Reconciliation of anything reported in sections 1–3 is NOT defined here;
--   it waits for an explicit product decision (ADR-009 "Legacy
--   Organizations").
-- ============================================================================
\set ON_ERROR_STOP on

begin transaction read only;

-- 1. Organizations that never had any Subscription (legacy candidates).
select 'NO_SUBSCRIPTION_EVER' as finding, organization.id as organization_id, organization.display_name
from public.veterinary_organizations as organization
where not exists (
    select 1 from public.organization_subscriptions as subscription
    where subscription.organization_id = organization.id
)
order by organization.id;

-- 2. Organizations with no current (non-EXPIRED) Subscription relationship.
select 'NO_CURRENT_SUBSCRIPTION' as finding, organization.id as organization_id, organization.display_name,
    (select count(*) from public.organization_subscriptions as subscription
     where subscription.organization_id = organization.id) as subscription_periods
from public.veterinary_organizations as organization
where not exists (
    select 1
    from public.organization_subscriptions as subscription
    cross join lateral public.derive_organization_subscription_current_state(subscription.id) as derived
    where subscription.organization_id = organization.id
      and derived.current_state <> 'EXPIRED'
)
order by organization.id;

-- 3. Organizations with more than one non-EXPIRED Subscription (must be none).
select 'MULTIPLE_CURRENT_SUBSCRIPTIONS' as finding, subscription.organization_id, count(*) as current_relationships
from public.organization_subscriptions as subscription
cross join lateral public.derive_organization_subscription_current_state(subscription.id) as derived
where derived.current_state <> 'EXPIRED'
group by subscription.organization_id
having count(*) > 1
order by subscription.organization_id;

-- 4. Organizations with published Clinics but no current Appointment Entitlement
--    (Clinics stay published by design; Guardians cannot request Appointments).
select 'PUBLISHED_WITHOUT_APPOINTMENT_ENTITLEMENT' as finding, organization.id as organization_id,
    organization.display_name, count(clinic.id) as published_clinics
from public.veterinary_organizations as organization
join public.clinics as clinic on clinic.organization_id = organization.id and clinic.is_published
where not public.organization_has_professional_entitlement(organization.id, 'APPOINTMENT_MANAGEMENT')
group by organization.id, organization.display_name
order by organization.id;

-- 5. Current Subscription state and validity per Organization (operator view).
select 'CURRENT_STATUS' as finding, subscription.organization_id, subscription.id as subscription_id,
    derived.current_state, derived.current_state_effective_at,
    derived.current_commercial_valid_from, derived.current_commercial_valid_until,
    case
        when derived.current_state = 'ACTIVE' and derived.current_commercial_valid_until is null then 'OPEN_ENDED'
        when derived.current_state in ('ACTIVE', 'CANCELLED')
             and derived.current_commercial_valid_until <= statement_timestamp() then 'VALIDITY_ENDED'
        when derived.current_state in ('ACTIVE', 'CANCELLED')
             and derived.current_commercial_valid_until <= statement_timestamp() + interval '30 days' then 'ENDS_WITHIN_30_DAYS'
        else null
    end as validity_note,
    case when derived.current_state = 'PAST_DUE'
         then statement_timestamp() - derived.current_state_effective_at end as past_due_for
from public.organization_subscriptions as subscription
cross join lateral public.derive_organization_subscription_current_state(subscription.id) as derived
where derived.current_state <> 'EXPIRED'
order by subscription.organization_id;

-- 6. Transitions recorded with a future effective time (possible only before
--    the Phase 1 no-future-transition rule; must be none afterwards).
select 'FUTURE_DATED_TRANSITION' as finding, transition.subscription_id, transition.from_state,
    transition.to_state, transition.effective_at, transition.recorded_at
from public.subscription_state_transitions as transition
where transition.effective_at > transition.recorded_at
order by transition.subscription_id, transition.effective_at;

-- 7. Transitions outside the Phase 1 graph (historical, before enforcement).
select 'TRANSITION_OUTSIDE_PHASE_1_GRAPH' as finding, transition.subscription_id, transition.from_state,
    transition.to_state, transition.effective_at
from public.subscription_state_transitions as transition
where (transition.from_state, transition.to_state) not in (
    ('PENDING', 'ACTIVE'), ('PENDING', 'EXPIRED'), ('ACTIVE', 'PAST_DUE'), ('ACTIVE', 'CANCELLED'), ('ACTIVE', 'EXPIRED'),
    ('PAST_DUE', 'ACTIVE'), ('PAST_DUE', 'EXPIRED'), ('CANCELLED', 'EXPIRED'))
order by transition.subscription_id, transition.effective_at;

-- 8. Establishments outside the Phase 1 initial-state rules (historical,
--    before enforcement): initial state other than PENDING/ACTIVE, or an
--    initial effective time later than the establishment time.
select 'ESTABLISHMENT_OUTSIDE_PHASE_1_RULES' as finding, subscription.organization_id,
    subscription.id as subscription_id, subscription.initial_state, subscription.initial_state_effective_at,
    subscription.established_at
from public.organization_subscriptions as subscription
where subscription.initial_state not in ('PENDING', 'ACTIVE')
   or subscription.initial_state_effective_at > subscription.established_at
order by subscription.organization_id, subscription.established_at;

-- 9. Establishment path per Organization (ADR-009). ATOMIC_ESTABLISHMENT:
--    established by establish_veterinary_organization (migration
--    20261101090000), which always includes the initial Subscription.
--    PRE_ATOMIC_PATH: established earlier (client self-service, or the
--    interim operator path) or by a direct trusted fixture; such an
--    Organization may lack an initial Subscription (see section 1). Read
--    through to_jsonb so this also runs on a database that does not have the
--    establishment-key column yet.
select 'ESTABLISHMENT_PATH' as finding, organization.id as organization_id, organization.display_name,
    case when to_jsonb(organization.*) ->> 'establishment_idempotency_key' is not null
         then 'ATOMIC_ESTABLISHMENT' else 'PRE_ATOMIC_PATH' end as establishment_path,
    exists (select 1 from public.organization_subscriptions as subscription
            where subscription.organization_id = organization.id) as ever_had_subscription
from public.veterinary_organizations as organization
order by establishment_path, organization.id;

rollback;

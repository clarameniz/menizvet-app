import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_ENTITLEMENTS,
  type EntitlementAvailability,
} from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * SPEC-SUB-002 §15 — `public.get_organization_subscription_status(p_organization_id uuid)
 * returns jsonb`, defined in
 * supabase/migrations/20261031090000_subscription_operational_safety.sql.
 * Granted to `authenticated` only. It re-authorizes the caller itself
 * (`ORGANIZATION_MANAGE_SUBSCRIPTION` for that Organization): unknown and
 * inaccessible Organizations fail identically with `42501`.
 *
 *   {
 *     organization_id uuid, organization_display_name text,
 *     subscription: null | { state, state_effective_at, valid_from | null, valid_until | null },
 *     entitlements: { APPOINTMENT_MANAGEMENT, PROFESSIONAL_SCHEDULING, CLINICAL_CARE,
 *                     CLINICAL_DOCUMENTATION }
 *   }
 *
 * `state` is the stored Subscription state — an ACTIVE Subscription whose
 * validity ended stays ACTIVE — and Entitlement availability is reported
 * separately. The payload carries no provider, source-event or internal
 * commercial data; the strict parser rejects any extra member, so such data
 * could never be rendered by accident.
 */

export const SUBSCRIPTION_STATES = [
  'PENDING',
  'ACTIVE',
  'PAST_DUE',
  'CANCELLED',
  'EXPIRED',
] as const;
export type SubscriptionState = (typeof SUBSCRIPTION_STATES)[number];

export type OrganizationSubscription = {
  state: SubscriptionState;
  stateEffectiveAt: string;
  validFrom: string | null;
  validUntil: string | null;
};
export type OrganizationSubscriptionStatus = {
  organizationId: string;
  organizationDisplayName: string;
  /** `null` only when the Organization never had a Subscription. */
  subscription: OrganizationSubscription | null;
  entitlements: EntitlementAvailability;
};
export type SubscriptionStatusResult =
  { data: OrganizationSubscriptionStatus; error: null } | { data: null; error: string };
export const SUBSCRIPTION_STATUS_ACCESS_DENIED = 'SUBSCRIPTION_STATUS_ACCESS_DENIED';
export const SUBSCRIPTION_STATUS_MALFORMED = 'SUBSCRIPTION_STATUS_MALFORMED';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isId = (raw: unknown): raw is string => typeof raw === 'string' && UUID.test(raw);
const isInstant = (raw: unknown): raw is string =>
  typeof raw === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(raw) && Number.isFinite(Date.parse(raw));
const isNullableInstant = (raw: unknown): raw is string | null => raw === null || isInstant(raw);
function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}
function hasExactly(raw: Record<string, unknown>, keys: readonly string[]): boolean {
  const present = Object.keys(raw);
  return present.length === keys.length && keys.every((key) => key in raw);
}

function parseSubscription(raw: unknown): OrganizationSubscription | null | undefined {
  if (raw === null) return null;
  if (
    !isRecord(raw) ||
    !hasExactly(raw, ['state', 'state_effective_at', 'valid_from', 'valid_until'])
  )
    return undefined;
  const state = SUBSCRIPTION_STATES.find((candidate) => candidate === raw.state);
  if (
    state === undefined ||
    !isInstant(raw.state_effective_at) ||
    !isNullableInstant(raw.valid_from) ||
    !isNullableInstant(raw.valid_until)
  )
    return undefined;
  return {
    state,
    stateEffectiveAt: raw.state_effective_at,
    validFrom: raw.valid_from,
    validUntil: raw.valid_until,
  };
}

function parseEntitlements(raw: unknown): EntitlementAvailability | null {
  if (!isRecord(raw) || !hasExactly(raw, PROFESSIONAL_ENTITLEMENTS)) return null;
  if (!PROFESSIONAL_ENTITLEMENTS.every((key) => typeof raw[key] === 'boolean')) return null;
  return {
    APPOINTMENT_MANAGEMENT: raw.APPOINTMENT_MANAGEMENT as boolean,
    PROFESSIONAL_SCHEDULING: raw.PROFESSIONAL_SCHEDULING as boolean,
    CLINICAL_CARE: raw.CLINICAL_CARE as boolean,
    CLINICAL_DOCUMENTATION: raw.CLINICAL_DOCUMENTATION as boolean,
  };
}

/** Strict: the payload must describe exactly the requested Organization. */
export function parseOrganizationSubscriptionStatus(
  raw: unknown,
  organizationId: string,
): OrganizationSubscriptionStatus | null {
  if (
    !isRecord(raw) ||
    !hasExactly(raw, [
      'organization_id',
      'organization_display_name',
      'subscription',
      'entitlements',
    ])
  )
    return null;
  if (
    !isId(raw.organization_id) ||
    raw.organization_id.toLowerCase() !== organizationId.toLowerCase() ||
    typeof raw.organization_display_name !== 'string' ||
    raw.organization_display_name.trim() === ''
  )
    return null;
  const subscription = parseSubscription(raw.subscription);
  const entitlements = parseEntitlements(raw.entitlements);
  if (subscription === undefined || entitlements === null) return null;
  return {
    organizationId: raw.organization_id,
    organizationDisplayName: raw.organization_display_name,
    subscription,
    entitlements,
  };
}

/** Only the read RPC; every request authorizes the explicit route Organization server-side. */
export async function getOrganizationSubscriptionStatus(
  organizationId: string,
): Promise<SubscriptionStatusResult> {
  if (!isId(organizationId)) return { data: null, error: SUBSCRIPTION_STATUS_ACCESS_DENIED };
  try {
    const { data, error } = await supabase.rpc('get_organization_subscription_status', {
      p_organization_id: organizationId,
    });
    if (error)
      return {
        data: null,
        error:
          error.code === '28000'
            ? PROFESSIONAL_CONTEXT_AUTH_REQUIRED
            : error.code === '42501'
              ? SUBSCRIPTION_STATUS_ACCESS_DENIED
              : error.message,
      };
    const status = parseOrganizationSubscriptionStatus(data, organizationId);
    return status === null
      ? { data: null, error: SUBSCRIPTION_STATUS_MALFORMED }
      : { data: status, error: null };
  } catch (error) {
    return {
      data: null,
      error: error instanceof Error ? error.message : 'Subscription status read failed',
    };
  }
}

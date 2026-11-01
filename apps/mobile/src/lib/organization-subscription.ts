import type { Href } from 'expo-router';

import type {
  OrganizationSubscriptionStatus,
  SubscriptionState,
} from '@/data/organization-subscription';
import type {
  OrganizationProfessionalContext,
  ProfessionalEntitlement,
} from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import type { LocaleCode } from '@/i18n/types';

/**
 * Pure presentation for the Organization Subscription status screen
 * (SPEC-SUB-002 §15). Nothing here authorizes anything: the backend read
 * re-authorizes `ORGANIZATION_MANAGE_SUBSCRIPTION` on every request.
 */

/** Advisory entry only: offered with Organization-scoped ORGANIZATION_MANAGE_SUBSCRIPTION. */
export function offersOrganizationSubscription(
  organization: OrganizationProfessionalContext,
): boolean {
  return organization.capabilities.some(
    ({ capability, scope }) =>
      scope.type === 'ORGANIZATION' && capability === 'ORGANIZATION_MANAGE_SUBSCRIPTION',
  );
}

export function organizationSubscriptionHref(organizationId: string): Href {
  return {
    pathname: '/professional/organizations/[organizationId]/subscription',
    params: { organizationId },
  };
}

const STATE_KEYS: Record<SubscriptionState, TranslationKey> = {
  PENDING: 'subscription.statePending',
  ACTIVE: 'subscription.stateActive',
  PAST_DUE: 'subscription.statePastDue',
  CANCELLED: 'subscription.stateCancelled',
  EXPIRED: 'subscription.stateExpired',
};

const SERVICE_KEYS: Record<ProfessionalEntitlement, TranslationKey> = {
  APPOINTMENT_MANAGEMENT: 'subscription.serviceAppointments',
  PROFESSIONAL_SCHEDULING: 'subscription.serviceScheduling',
  CLINICAL_CARE: 'subscription.serviceClinicalCare',
  CLINICAL_DOCUMENTATION: 'subscription.serviceClinicalDocumentation',
};
const SERVICE_ORDER: ProfessionalEntitlement[] = [
  'APPOINTMENT_MANAGEMENT',
  'PROFESSIONAL_SCHEDULING',
  'CLINICAL_CARE',
  'CLINICAL_DOCUMENTATION',
];

/** One line of the status card; `date` (an instant) is formatted by the screen. */
export type SubscriptionLine = { key: TranslationKey; date: string | null };
export type SubscriptionService = { labelKey: TranslationKey; available: boolean };
export type SubscriptionStatusView = {
  /** `null` when the Organization never had a Subscription. */
  stateKey: TranslationKey | null;
  tone: 'positive' | 'attention' | 'neutral';
  lines: SubscriptionLine[];
  services: SubscriptionService[];
};

/**
 * The stored state is shown as stored: an ACTIVE Subscription whose validity
 * ended stays "Active", with a line saying its validity ended — never a
 * fabricated "Expired". Validity dates appear only when present; an
 * open-ended ACTIVE shows no end or renewal date. Service availability comes
 * from the read's Entitlements, separately from the state.
 */
export function subscriptionStatusView(
  status: OrganizationSubscriptionStatus,
  referenceInstant: Date = new Date(),
): SubscriptionStatusView {
  const services = SERVICE_ORDER.map((entitlement) => ({
    labelKey: SERVICE_KEYS[entitlement],
    available: status.entitlements[entitlement],
  }));
  const subscription = status.subscription;
  if (subscription === null) {
    return {
      stateKey: null,
      tone: 'neutral',
      lines: [{ key: 'subscription.noSubscription', date: null }],
      services,
    };
  }
  const now = referenceInstant.getTime();
  const ended = (instant: string | null) => instant !== null && Date.parse(instant) <= now;
  const notStarted = (instant: string | null) => instant !== null && Date.parse(instant) > now;
  const lines: SubscriptionLine[] = [
    { key: 'subscription.since', date: subscription.stateEffectiveAt },
  ];
  const { state, validFrom, validUntil } = subscription;

  if (state === 'ACTIVE') {
    if (notStarted(validFrom)) lines.push({ key: 'subscription.notStarted', date: validFrom });
    else if (validFrom !== null) lines.push({ key: 'subscription.validFrom', date: validFrom });
    if (ended(validUntil)) lines.push({ key: 'subscription.validityEnded', date: validUntil });
    else if (validUntil !== null) lines.push({ key: 'subscription.validUntil', date: validUntil });
  } else if (state === 'CANCELLED') {
    lines.push(
      validUntil !== null && !ended(validUntil)
        ? { key: 'subscription.cancelledUntil', date: validUntil }
        : validUntil !== null
          ? { key: 'subscription.cancelledEnded', date: validUntil }
          : { key: 'subscription.cancelledNoCoverage', date: null },
    );
  } else if (state === 'PENDING') {
    lines.push({ key: 'subscription.pendingNote', date: null });
  } else if (state === 'PAST_DUE') {
    lines.push({ key: 'subscription.pastDueNote', date: null });
  } else {
    lines.push({ key: 'subscription.expiredNote', date: null });
  }

  const anyAvailable = services.some((service) => service.available);
  return {
    stateKey: STATE_KEYS[state],
    tone:
      state === 'ACTIVE' && anyAvailable
        ? 'positive'
        : state === 'EXPIRED'
          ? 'neutral'
          : 'attention',
    lines,
    services,
  };
}

export function subscriptionInstantLabel(instant: string, locale: LocaleCode): string {
  return new Intl.DateTimeFormat(locale === 'es' ? 'es-ES' : 'en-GB', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(instant));
}

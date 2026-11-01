import { useCallback, useEffect, useRef, useState } from 'react';

import {
  getOrganizationSubscriptionStatus,
  SUBSCRIPTION_STATUS_ACCESS_DENIED,
  type OrganizationSubscriptionStatus,
  type SubscriptionStatusResult,
} from '@/data/organization-subscription';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import {
  createAppointmentHoursLifecycle,
  shouldApplyRead,
} from '@/lib/appointment-hours-lifecycle';

export type SubscriptionStatusState =
  | { kind: 'loading' }
  | { kind: 'unavailable' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'loaded'; status: OrganizationSubscriptionStatus };

export function subscriptionStatusReadFrom(
  result: SubscriptionStatusResult,
): Exclude<SubscriptionStatusState, { kind: 'loading' }> {
  if (result.error === SUBSCRIPTION_STATUS_ACCESS_DENIED) return { kind: 'unavailable' };
  if (result.error !== null)
    return {
      kind: 'error',
      messageKey:
        result.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED
          ? 'errors.sessionExpired'
          : 'subscription.loadError',
    };
  return { kind: 'loaded', status: result.data };
}

/**
 * A keyed screen owns one terminal lifecycle (as the Staff screens): blur
 * invalidates outstanding reads, latest read wins, an ordinary failed refresh
 * keeps the last status, and `unavailable` (42501) always replaces it so
 * inaccessible commercial content is never left on screen.
 */
export function useOrganizationSubscription(organizationId: string) {
  const [state, setState] = useState<SubscriptionStatusState>({ kind: 'loading' });
  const [lifecycle] = useState(createAppointmentHoursLifecycle);
  const hasLoaded = useRef(false);
  useEffect(() => {
    lifecycle.setMounted(true);
    return () => lifecycle.setMounted(false);
  }, [lifecycle]);
  const reload = useCallback(async () => {
    const token = lifecycle.beginLoad();
    const result = await getOrganizationSubscriptionStatus(organizationId);
    if (!lifecycle.isCurrentLoad(token)) return null;
    const read = subscriptionStatusReadFrom(result);
    if (
      read.kind === 'unavailable' ||
      shouldApplyRead(read.kind, hasLoaded.current) ||
      result.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED
    ) {
      if (read.kind === 'loaded') hasLoaded.current = true;
      setState(read);
    }
    return read;
  }, [lifecycle, organizationId]);
  const invalidate = useCallback(() => {
    lifecycle.beginLoad();
  }, [lifecycle]);
  const leave = useCallback((navigate: () => void) => lifecycle.leave(navigate), [lifecycle]);
  return { state, reload, invalidate, leave };
}

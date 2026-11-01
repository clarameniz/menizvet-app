import * as Linking from 'expo-linking';

import { ORGANIZATION_INVITATION_ROUTE } from '@/lib/organization-invitation-link';
import { routeIncomingSystemPath } from '@/lib/organization-invitation-intake';

/**
 * Expo Router native-intent hook: runs for the initial URL (cold start) and
 * every URL received while running, before the router resolves a route.
 * Organization Invitation links are captured here so their `#secret=...`
 * fragment never becomes a route param (see organization-invitation-intake.ts);
 * every other URL, including Appointment App Links, is returned unchanged.
 *
 * For the initial call, the natively cached launch URL is also offered, because
 * Expo Router's Android initial-URL read can time out to the root URL on a slow
 * cold start. Once an Invitation link is captured, the native cache is cleared
 * so a JavaScript reload cannot re-capture an already handled link.
 */
export function redirectSystemPath({ path, initial }: { path: string; initial: boolean }): string {
  const target = routeIncomingSystemPath(path, initial ? launchUrl() : null);
  if (target === ORGANIZATION_INVITATION_ROUTE) {
    try {
      Linking.clearInitialURL();
    } catch {
      // Best effort: the staged proof is already independent of the cache.
    }
  }
  return target;
}

function launchUrl(): string | null {
  try {
    return Linking.getLinkingURL();
  } catch {
    return null;
  }
}

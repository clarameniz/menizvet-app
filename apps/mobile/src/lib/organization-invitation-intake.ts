import {
  ORGANIZATION_INVITATION_ROUTE,
  parseOrganizationInvitationLink,
  type OrganizationInvitationLink,
} from '@/lib/organization-invitation-link';

/**
 * Hand-off of an incoming Organization Invitation link from Expo Router's
 * `+native-intent` hook (src/app/+native-intent.ts) to the acceptance screen.
 *
 * Expo Router copies a URL fragment into route params (as `#`), so the link
 * must never reach the router as-is: `routeIncomingSystemPath` captures the
 * reference and secret from the full URL here, at the routing boundary, and
 * rewrites the navigation target to the bare route — no query, no fragment.
 * The secret therefore never enters route params, navigation state or
 * history. The screen takes the staged link exactly once and moves the proof
 * into the secure store.
 *
 * In-memory only, and only until the screen takes it.
 */
let staged: OrganizationInvitationLink | null = null;
let intakeVersion = 0;
let mountedScreens = 0;
const listeners = new Set<() => void>();

/**
 * Expo Router `redirectSystemPath` body for both cold start (initial URL) and
 * links received while running. Every other URL passes through unchanged.
 *
 * `launchUrl` is the URL that launched the app as cached natively at Activity
 * creation (expo-linking `getLinkingURL()`), passed only for the initial call.
 * On Android, Expo Router races `Linking.getInitialURL()` against a 150 ms
 * timeout and substitutes the root URL when it loses, so on a slow cold start
 * `path` can be the root URL although an Invitation link launched the app; the
 * launch URL then still delivers it, through this same interception point.
 */
export function routeIncomingSystemPath(path: string, launchUrl: string | null = null): string {
  const link =
    parseOrganizationInvitationLink(path) ??
    (launchUrl === null ? null : parseOrganizationInvitationLink(launchUrl));
  if (link === null) return path;
  staged = link;
  intakeVersion += 1;
  for (const listener of listeners) listener();
  return ORGANIZATION_INVITATION_ROUTE;
}

/** The staged link, at most once. */
export function takeStagedOrganizationInvitationLink(): OrganizationInvitationLink | null {
  const link = staged;
  staged = null;
  return link;
}

/** Changes whenever a new link is staged (for a screen that is already open). */
export function getOrganizationInvitationIntakeVersion(): number {
  return intakeVersion;
}

export function subscribeOrganizationInvitationIntake(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/**
 * The screen stays mounted under the sign-in/registration screens it opens, so
 * it resumes on its own after authentication; the root-level resume only
 * navigates when it is not mounted (for example after an app restart).
 */
export function registerOrganizationInvitationScreen(): () => void {
  mountedScreens += 1;
  return () => {
    mountedScreens -= 1;
  };
}

export function isOrganizationInvitationScreenMounted(): boolean {
  return mountedScreens > 0;
}

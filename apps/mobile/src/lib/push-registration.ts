import { Platform } from 'react-native';
import Constants from 'expo-constants';
import * as Notifications from 'expo-notifications';

import { disablePushRegistration, registerPushToken, type PushPlatform } from '@/data/push';
import { getInstallationId } from '@/lib/installation-id';
import {
  beginRegistrationAttempt,
  getCurrentPushRegistrationId,
  getInFlightRegistration,
  invalidateRegistrationAttempts,
  isLatestRegistrationAttempt,
  setCurrentPushRegistrationId,
  setInFlightRegistration,
} from '@/lib/push-registration-state';

export function resolvePushPlatform(osName: typeof Platform.OS): PushPlatform | null {
  if (osName === 'ios') return 'IOS';
  if (osName === 'android') return 'ANDROID';
  return null;
}

/**
 * android.package is configured (app.config.ts); ios.bundleIdentifier is not
 * yet — iOS push provisioning/credentials are an explicit Milestone H
 * follow-up (see the Milestone H report), not this pass. Returning null here
 * for iOS makes ensurePushRegistered a safe no-op on iOS today rather than
 * sending a fabricated identifier.
 */
export function resolveApplicationId(osName: typeof Platform.OS): string | null {
  if (osName === 'android') {
    return Constants.expoConfig?.android?.package ?? null;
  }
  if (osName === 'ios') {
    return Constants.expoConfig?.ios?.bundleIdentifier ?? null;
  }
  return null;
}

export function resolveEasProjectId(): string | null {
  const projectId = Constants.easConfig?.projectId ?? Constants.expoConfig?.extra?.eas?.projectId;
  return typeof projectId === 'string' && projectId.length > 0 ? projectId : null;
}

/**
 * The permission+registration flow for one attempt. Only ever run from
 * within ensurePushRegistered's single-flight wrapper below — never called
 * directly, so at most one of these can be in flight at a time.
 */
async function runRegistrationAttempt(
  platform: PushPlatform,
  applicationId: string,
  projectId: string,
  attemptGeneration: number,
  isStale: () => boolean,
): Promise<string | null> {
  const currentPermissions = await Notifications.getPermissionsAsync();
  if (isStale()) return null;

  let status = currentPermissions.status;

  if (status === 'undetermined') {
    const requested = await Notifications.requestPermissionsAsync();
    if (isStale()) return null;
    status = requested.status;
  }

  if (status !== 'granted') {
    return null;
  }

  const installationId = await getInstallationId();
  if (isStale()) return null;

  let expoPushToken: string;
  try {
    const tokenResult = await Notifications.getExpoPushTokenAsync({ projectId });
    expoPushToken = tokenResult.data;
  } catch {
    // Offline/transient Expo-service failure. Push is a secondary
    // capability (Milestone H product decisions): fail silently and let a
    // later effect run (relaunch, reconnect, token rotation) retry.
    return null;
  }
  if (isStale()) return null;

  const result = await registerPushToken({
    installationId,
    expoPushToken,
    platform,
    applicationId,
  });
  if (result.error !== null) return null;

  // Only the most-recently-STARTED attempt may ever become "current",
  // regardless of completion order, and independent of the caller's own
  // effect-level isStale() — sign-out invalidates generations immediately
  // (invalidateRegistrationAttempts), before its own session state change
  // has necessarily propagated back to any effect's isMounted flag. This is
  // exactly the Milestone H logout-race fix: without this check, a
  // registration that completes after sign-out already read "the current
  // id" could silently become the new "current" id, and the row it created
  // would never be disabled.
  if (!isStale() && isLatestRegistrationAttempt(attemptGeneration)) {
    setCurrentPushRegistrationId(result.data.registrationId);
  }

  return result.data.registrationId;
}

/**
 * Phase 1 permission + registration lifecycle (Milestone H product
 * decisions):
 *
 * - only ever meaningful once a real authenticated session exists;
 * - requests permission only when still `undetermined`, never re-prompts
 *   after a denial;
 * - registers without prompting when permission is already `granted`,
 *   including on repeated calls from Expo push token rotation
 *   (addPushTokenListener), which reuses this exact function.
 *
 * Single-flight (Milestone H logout-race fix): Expo's own
 * getExpoPushTokenAsync/getDevicePushTokenAsync can itself trigger the
 * token-rotation listener (its docs warn "as it triggers the listener"), so
 * a registration already in flight from the permission+registration effect
 * can spawn a second, independent one from the token-rotation effect. If a
 * registration is already in flight when this is called, this awaits and
 * returns *that* attempt's result rather than issuing a second
 * register-push call — this is what a physical test caught creating two
 * push_registrations rows for the same user/session/installation, only one
 * of which ever got disabled at sign-out.
 *
 * `isStale` is re-checked immediately before every asynchronous
 * continuation so a slow permission/token/network round trip started under
 * a previous session or User can never land a registration under a newer
 * one.
 */
export async function ensurePushRegistered(
  isStale: () => boolean,
  osName: typeof Platform.OS = Platform.OS,
): Promise<string | null> {
  const platform = resolvePushPlatform(osName);
  if (!platform) return null;

  const applicationId = resolveApplicationId(osName);
  const projectId = resolveEasProjectId();
  if (!applicationId || !projectId) return null;

  const existing = getInFlightRegistration();
  if (existing) {
    return existing;
  }

  const attemptGeneration = beginRegistrationAttempt();
  const attempt = runRegistrationAttempt(
    platform,
    applicationId,
    projectId,
    attemptGeneration,
    isStale,
  );
  setInFlightRegistration(attempt);

  try {
    return await attempt;
  } finally {
    if (getInFlightRegistration() === attempt) {
      setInFlightRegistration(null);
    }
  }
}

/**
 * Best-effort sign-out cleanup (Milestone H logout-race fix). Disables the
 * currently-tracked registration and, if a registration attempt is still in
 * flight, awaits it and disables whatever id it produces too.
 *
 * invalidateRegistrationAttempts() runs first so that in-flight attempt can
 * never overwrite currentRegistrationId after this point (see
 * runRegistrationAttempt) — but that alone does not clean up a
 * push_registrations row the attempt may already have created server-side
 * by the time it resolves. Awaiting it here and disabling its result too is
 * what closes that gap: a registration that completes after sign-out has
 * already read "the current id" must still be found and disabled, not
 * silently orphaned (the exact bug a physical logout test caught).
 *
 * The backend's auth_session_id binding remains the real security boundary
 * regardless of whether this succeeds (SPEC-COM-002 BR-22) — callers must
 * never let a failure here block sign-out.
 */
export async function disableCurrentPushRegistrations(): Promise<void> {
  const previousRegistrationId = getCurrentPushRegistrationId();
  invalidateRegistrationAttempts();

  const inFlight = getInFlightRegistration();
  const inFlightResultId = inFlight ? await inFlight : null;

  setCurrentPushRegistrationId(null);

  const idsToDisable = new Set<string>();
  if (previousRegistrationId) idsToDisable.add(previousRegistrationId);
  if (inFlightResultId) idsToDisable.add(inFlightResultId);

  await Promise.all(
    [...idsToDisable].map((registrationId) => disablePushRegistration(registrationId)),
  );
}

/**
 * Shared Push Registration lifecycle/concurrency state (Milestone H logout
 * race fix). In memory only, never persisted, never React state.
 *
 * Beyond the tracked "current" registration id, this coordinates
 * registration attempts against three real races:
 *
 * - overlapping attempts: the permission+registration effect and the
 *   token-rotation listener can both call ensurePushRegistered close
 *   together — and Expo's own getExpoPushTokenAsync/getDevicePushTokenAsync
 *   can itself trigger the token-rotation listener (its own docs warn
 *   "as it triggers the listener"), so one registration can spawn a second,
 *   independent one. Single-flight (getInFlightRegistration /
 *   setInFlightRegistration, used by ensurePushRegistered in
 *   push-registration.ts) collapses these into one shared attempt so at
 *   most one register-push call is ever in flight at a time.
 * - out-of-order completion: even a single in-flight attempt can still be
 *   racing sign-out. The generation counter
 *   (beginRegistrationAttempt/isLatestRegistrationAttempt) ensures an
 *   attempt only ever commits currentRegistrationId if nothing has
 *   invalidated attempts since it started.
 * - sign-out racing an in-flight attempt: invalidateRegistrationAttempts()
 *   bumps the generation so an attempt already in flight can never commit
 *   after sign-out clears currentRegistrationId; disableCurrentPushRegistrations
 *   (push-registration.ts) also awaits any in-flight attempt so it can
 *   disable whatever registration id that attempt produces, even though it
 *   is no longer allowed to become "current".
 *
 * The backend's auth_session_id binding remains the actual security
 * boundary regardless of any of this (SPEC-COM-002 BR-22) — this is
 * hygiene/cleanup correctness, not authorization.
 */
let currentRegistrationId: string | null = null;
let generation = 0;
let inFlightRegistration: Promise<string | null> | null = null;

export function getCurrentPushRegistrationId(): string | null {
  return currentRegistrationId;
}

export function setCurrentPushRegistrationId(registrationId: string | null): void {
  currentRegistrationId = registrationId;
}

/**
 * Call once when a registration attempt starts; returns a ticket. The
 * attempt may only commit its result (see isLatestRegistrationAttempt) if
 * this exact ticket is still the latest one issued when it finishes.
 */
export function beginRegistrationAttempt(): number {
  generation += 1;
  return generation;
}

export function isLatestRegistrationAttempt(attemptGeneration: number): boolean {
  return attemptGeneration === generation;
}

/**
 * Call at sign-out: any attempt already in flight may still complete and
 * report its result (see getInFlightRegistration), but from this call
 * onward it can never again become the tracked "current" registration.
 */
export function invalidateRegistrationAttempts(): void {
  generation += 1;
}

export function getInFlightRegistration(): Promise<string | null> | null {
  return inFlightRegistration;
}

export function setInFlightRegistration(promise: Promise<string | null> | null): void {
  inFlightRegistration = promise;
}

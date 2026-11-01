import type { PushNavigationTarget } from '@/lib/push-notification-payload';

export type PushSessionReadiness = {
  isSessionLoading: boolean;
  hasSession: boolean;
  isPasswordRecovery: boolean;
};

export type PushResponseOutcome =
  | { kind: 'none' }
  | { kind: 'pending' }
  | { kind: 'navigate'; target: PushNavigationTarget }
  | { kind: 'discarded' };

/**
 * Cold-start bug fix (Milestone H): pure notification-response consumption
 * state machine, with no dependency on React, Expo, or the native
 * notifications module, so it is unit-testable without mocking any of
 * those.
 *
 * Root cause this replaces: the previous implementation called
 * Notifications.clearLastNotificationResponse() and marked a response
 * "handled" the instant it was observed — before checking whether an
 * authenticated session existed. On a cold start, SessionProvider's session
 * is still resolving (its `session` state starts `null` and its `isLoading`
 * starts `true`; supabase.auth.getSession() is async) at the exact moment
 * the tap-to-navigate effect's synchronous
 * Notifications.getLastNotificationResponse() check ran, so the response
 * was consumed/cleared before navigation could happen, and nothing
 * remained to navigate once the session became ready. A backgrounded app's
 * live listener never hit this: the app process (and its already-resolved
 * session) was already alive, so the session was ready the instant the tap
 * was observed.
 *
 * Fix: a captured response with a valid target is held as `pending` rather
 * than immediately consumed. It is only resolved (added to the handled
 * set, and only then eligible to navigate) once session bootstrap has
 * finished. If, once ready, no authenticated session exists (or a
 * password-recovery session is active), the response is discarded rather
 * than navigated — never left pending indefinitely, never leaked.
 *
 * Usage: call `capture` whenever a notification response is observed (the
 * cold-start check and the live listener both funnel through it), and
 * `updateReadiness` whenever session/bootstrap state changes. Each call
 * returns what the caller should do *right now*; the caller (the hook)
 * performs the actual side effects (navigate(),
 * Notifications.clearLastNotificationResponse()) — this module performs
 * none itself.
 */
export function createPushResponseConsumer() {
  const handledResponseIds = new Set<string>();
  let pending: { responseId: string; target: PushNavigationTarget } | null = null;
  let readiness: PushSessionReadiness = {
    isSessionLoading: true,
    hasSession: false,
    isPasswordRecovery: false,
  };

  function tryFlush(): PushResponseOutcome {
    if (!pending) return { kind: 'none' };
    if (readiness.isSessionLoading) return { kind: 'pending' };

    const resolved = pending;
    pending = null;
    handledResponseIds.add(resolved.responseId);

    if (!readiness.hasSession || readiness.isPasswordRecovery) {
      return { kind: 'discarded' };
    }

    return { kind: 'navigate', target: resolved.target };
  }

  return {
    /**
     * `target` is the already-validated navigation target (or `null` for a
     * malformed/unknown payload — parsePushNavigationTarget's job, not
     * this module's). A malformed payload is discarded immediately
     * regardless of session readiness, since there is nothing session-
     * dependent about it.
     */
    capture(responseId: string, target: PushNavigationTarget | null): PushResponseOutcome {
      if (handledResponseIds.has(responseId)) return { kind: 'none' };
      if (pending?.responseId === responseId) return { kind: 'pending' };

      if (!target) {
        handledResponseIds.add(responseId);
        return { kind: 'discarded' };
      }

      pending = { responseId, target };
      return tryFlush();
    },

    updateReadiness(next: PushSessionReadiness): PushResponseOutcome {
      readiness = next;
      return tryFlush();
    },
  };
}

export type PushResponseConsumer = ReturnType<typeof createPushResponseConsumer>;

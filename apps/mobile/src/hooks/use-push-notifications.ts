import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import { router } from 'expo-router';

import { ensurePushRegistered } from '@/lib/push-registration';
import {
  parsePushNavigationTarget,
  type PushNavigationTarget,
} from '@/lib/push-notification-payload';
import { createPushResponseConsumer, type PushResponseOutcome } from '@/lib/push-response-consumer';
import { useSession } from '@/lib/session-provider';

const ANDROID_CHANNEL_ID = 'default';

/**
 * Module-scope so this runs once, as early as possible (when this module is
 * first imported from the root layout), independent of session/permission
 * state. Phase 1 foreground behavior (Milestone H): always show the normal
 * banner/list when OS permission allows it — no in-app notification inbox,
 * no custom foreground suppression.
 */
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

/**
 * Owns the full Milestone H production push lifecycle: the Android
 * notification channel, permission request + registration tied to the
 * authenticated session (never before authentication, never re-prompting
 * after denial — see the Milestone H product decisions), Expo push token
 * rotation, and tap-to-navigate handling for cold start, background, and
 * foreground notification responses. Mounted once from the root layout
 * (src/app/_layout.tsx), matching SessionProvider's own lifetime.
 */
export function usePushNotifications(): void {
  const { session, isPasswordRecovery, isLoading: isSessionLoading } = useSession();
  const consumerRef = useRef<ReturnType<typeof createPushResponseConsumer> | null>(null);
  if (consumerRef.current === null) {
    consumerRef.current = createPushResponseConsumer();
  }

  // Android channel: created once, unconditionally, so it exists before any
  // notification can arrive — independent of session or permission state
  // (channel creation itself requires neither). Importance HIGH so a
  // time-sensitive Appointment update (REQ-COM-002) can appear as a
  // heads-up banner, without reserving MAX for this ordinary category.
  useEffect(() => {
    if (Platform.OS !== 'android') return;
    void Notifications.setNotificationChannelAsync(ANDROID_CHANNEL_ID, {
      name: 'MenizVet',
      importance: Notifications.AndroidImportance.HIGH,
    });
  }, []);

  // Permission + registration, tied to the authenticated app session only —
  // never during bootstrap and never during a password-recovery-only
  // session, matching how (app) itself is gated in src/app/_layout.tsx.
  useEffect(() => {
    if (isSessionLoading || !session || isPasswordRecovery) return;

    let isMounted = true;
    void ensurePushRegistered(() => !isMounted);

    return () => {
      isMounted = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.user.id, isPasswordRecovery, isSessionLoading]);

  // Expo push token rotation (SDK 57 addPushTokenListener delivers a raw
  // DevicePushToken, not an Expo token — ensurePushRegistered re-fetches the
  // current Expo token itself via getExpoPushTokenAsync). Reuses the exact
  // same permission+registration function as the effect above; scoped to
  // the same authenticated session so a token that rotates during a
  // sign-out/sign-in transition is never registered under the User it
  // rotated away from.
  useEffect(() => {
    if (!session || isPasswordRecovery) return;

    let isMounted = true;
    const subscription = Notifications.addPushTokenListener(() => {
      void ensurePushRegistered(() => !isMounted);
    });

    return () => {
      isMounted = false;
      subscription.remove();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.user.id, isPasswordRecovery]);

  // Tap-to-navigate, capture side: a synchronous cold-start check plus the
  // live response listener. Registered once for the hook's lifetime — it
  // must NOT depend on session state, because re-subscribing on every
  // session change is exactly what previously caused a cold-start response
  // to be captured (and consumed/cleared) before the session existed. Every
  // observed response is hard-validated here and handed to the consumer,
  // which alone decides whether it is safe to act on right now (see
  // push-response-consumer.ts for the cold-start race this fixes).
  useEffect(() => {
    function captureResponse(response: Notifications.NotificationResponse | null) {
      if (!response) return;
      if (response.actionIdentifier !== Notifications.DEFAULT_ACTION_IDENTIFIER) return;

      const responseId = response.notification.request.identifier;
      const target = parsePushNavigationTarget(response.notification.request.content.data);
      handlePushResponseOutcome(consumerRef.current!.capture(responseId, target));
    }

    captureResponse(Notifications.getLastNotificationResponse());

    const subscription = Notifications.addNotificationResponseReceivedListener(captureResponse);
    return () => subscription.remove();
  }, []);

  // Tap-to-navigate, readiness side: the sole place a pending response is
  // ever resolved. Fires on every session/bootstrap change so a response
  // captured before the session was ready is flushed the moment it is —
  // deep links require current authentication (SPEC-COM-002 BR-28,
  // SPEC-COM-003 BR-43), so a response that resolves with no session (or a
  // password-recovery-only session) is discarded rather than navigated or
  // queued indefinitely.
  useEffect(() => {
    handlePushResponseOutcome(
      consumerRef.current!.updateReadiness({
        isSessionLoading,
        hasSession: !!session,
        isPasswordRecovery,
      }),
    );
  }, [session, isPasswordRecovery, isSessionLoading]);
}

function handlePushResponseOutcome(outcome: PushResponseOutcome): void {
  if (outcome.kind === 'navigate') {
    Notifications.clearLastNotificationResponse();
    navigateToAppointment(outcome.target);
    return;
  }
  if (outcome.kind === 'discarded') {
    // Resolved but not navigable (no session, or password-recovery-only) —
    // still clear the native store so a stale response is never re-surfaced
    // by a later getLastNotificationResponse() call.
    Notifications.clearLastNotificationResponse();
  }
  // 'pending': held by the consumer until readiness changes again.
  // 'none': already handled or a duplicate observation of a pending
  // response — nothing to do.
}

function navigateToAppointment(target: PushNavigationTarget): void {
  // Navigates directly from the two validated ids the payload already
  // carries (Milestone H push-navigation correction — see
  // push-notification-payload.ts and
  // supabase/migrations/20260921170000_communications_push_navigation_pet_id.sql).
  // This does not trust the payload as authoritative Appointment state:
  // appointments/[id].tsx always re-fetches via get_pet_appointments on
  // mount, which re-verifies current Guardianship server-side regardless of
  // what this payload claims (SPEC-COM-002 BR-28/BR-29, SPEC-COM-003
  // BR-43/BR-44).
  router.push(`/appointments/${target.appointmentId}?petId=${target.petId}`);
}

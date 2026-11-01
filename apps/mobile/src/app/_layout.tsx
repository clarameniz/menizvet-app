import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';

import { AnimatedSplashOverlay } from '@/components/animated-icon';
import { usePendingOrganizationInvitationResume } from '@/hooks/use-pending-organization-invitation-resume';
import { usePushNotifications } from '@/hooks/use-push-notifications';
import { LocaleProvider, useLocale } from '@/i18n/locale-provider';
import { SessionProvider, useSession } from '@/lib/session-provider';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  return (
    <LocaleProvider>
      <SessionProvider>
        <RootNavigator />
      </SessionProvider>
    </LocaleProvider>
  );
}

// No React Navigation ThemeProvider: the app is Design System v1 light-only
// (every screen paints its own fixed light background), so the navigator
// uses its default light theme regardless of the device colour scheme — a
// system dark theme would only tint the navigator background behind screens.
function RootNavigator() {
  const { session, isLoading: isSessionLoading, isPasswordRecovery } = useSession();
  const { isLoading: isLocaleLoading } = useLocale();
  // Bootstrap visibility only — gates the splash, nothing else. Deliberately
  // NOT used in the route guards below: while this is true, `session` is
  // simply still at its unresolved default (null), so (auth)'s guard is
  // already correctly "eligible" (a real ordinary fallback) rather than
  // needing a separate loading gate. Folding this into the guards previously
  // made (app) AND (auth) unavailable at the same time during bootstrap,
  // leaving the unconditionally-registered reset-password as the only
  // navigable route on cold launch — a real startup-routing defect, not a
  // hypothetical one. The splash still fully masks this resolution window
  // from the user; it just no longer does so by disabling every ordinary
  // route at once.
  const isBootstrapping = isSessionLoading || isLocaleLoading;

  // Milestone H: mounted once for the app's lifetime, matching
  // SessionProvider — owns the Android notification channel, permission
  // request + Push Registration tied to the authenticated session, Expo
  // push token rotation, and notification tap-to-navigate handling. See
  // src/hooks/use-push-notifications.ts for the full contract.
  usePushNotifications();
  // Staff Phase 1 B2: reopens a pending Organization Invitation after sign-in.
  usePendingOrganizationInvitationResume();

  return (
    <>
      <AnimatedSplashOverlay ready={!isBootstrapping} />
      <Stack screenOptions={{ headerShown: false }}>
        {/* Route eligibility only — no bootstrap/loading condition here (see
            isBootstrapping above). A password-recovery session is a real
            Supabase session, but it must not unlock ordinary app access
            until a new password is set (see reset-password.tsx). */}
        <Stack.Protected guard={!!session && !isPasswordRecovery}>
          <Stack.Screen name="(app)" />
          {/* Top-level rather than nested in the (app) group; pushed on top
              of it instead. Same guard as (app) — authenticated only, and
              not usable mid-recovery either. */}
          <Stack.Screen name="profile" />
          <Stack.Screen name="pets" />
          {/* Mobile Milestone F (Guardian Appointment Request & View,
              SPEC-APT-001/003/004/011): Guardian-only, same guard as pets. */}
          <Stack.Screen name="appointments" />
          {/* Professional context landing (SPEC-ORG-007, ADR-010): same
              authenticated guard. Presentation only — the backend remains
              the sole authorization boundary for professional operations. */}
          <Stack.Screen name="professional" />
        </Stack.Protected>

        <Stack.Protected guard={!session}>
          <Stack.Screen name="(auth)" />
        </Stack.Protected>

        {/* Reachable via the password-recovery deep link regardless of
            session state: at click-time the user is normally signed out
            (guard above already covers them), but exchanging the recovery
            code establishes a real session before the new password is set,
            so this route cannot be gated on session state the way (auth) is.
            The screen itself independently validates the incoming code and
            rejects anything malformed or incomplete. */}
        <Stack.Screen name="reset-password" />

        {/* Organization Invitation acceptance (SPEC-ORG-003 §12): reached
            from the Invitation App Link, which must open signed out, on cold
            start and while running, so it is registered unconditionally like
            reset-password. The screen previews only when authenticated and
            shows nothing about the Invitation otherwise; the backend remains
            the sole authority for preview and acceptance. */}
        <Stack.Screen name="invitations/organization/accept" />

        {/* Public Clinic Discovery (Mobile Milestone E, SPEC-DIS-001/002/003):
            anonymous and authenticated Users share this exact route tree, so
            it is registered unconditionally — like reset-password above —
            rather than inside either Stack.Protected block. This does not
            weaken (app)'s authentication guard; it only adds a route that
            was never gated by it. */}
        <Stack.Screen name="clinics" />
      </Stack>
    </>
  );
}

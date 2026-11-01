import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AuthHeader } from '@/components/design-system/auth-header';
import { Button } from '@/components/design-system/button';
import { Input, PasswordToggle } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { mapErrorToKey } from '@/i18n/error-messages';
import { useLocale } from '@/i18n/locale-provider';
import { useSession } from '@/lib/session-provider';
import { supabase } from '@/lib/supabase';
import { MIN_PASSWORD_LENGTH } from '@/lib/validation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type UiPhase = 'exchanging' | 'ready' | 'invalid' | 'submitting';

/**
 * Reached via the com.menizvet://reset-password deep link sent by
 * resetPasswordForEmail. Deliberately NOT nested under (auth): exchanging the
 * recovery code establishes a real Supabase session before a new password is
 * set, and (auth) is gated on having no session. This route is registered
 * unconditionally in the root layout; safety comes from validating the
 * incoming code below, not from a route guard.
 *
 * PKCE same-device constraint: resetPasswordForEmail generates a code
 * verifier and stores it locally (via the shared client's SecureStore
 * adapter) before the email is sent; exchangeCodeForSession below can only
 * succeed on the same device/app install that requested the reset, because
 * the verifier never leaves that device. Opening the recovery link on a
 * different device or a fresh install has no matching verifier and
 * exchangeCodeForSession will fail — this is expected PKCE behavior, handled
 * below as the ordinary "invalid link" case, not a bug. No alternate
 * cross-device recovery mechanism is implemented in this pass.
 *
 * Visual pass only: uses the same Design System v1 (`AuthHeader`, `Button`,
 * `Input`) as Sign In/Register/Forgot Password, but `AuthHeader` is only
 * shown with its back control hidden (`showBackButton={false}`) on the
 * 'ready'/'submitting' phase — see AuthHeader's doc comment for why no
 * generic "back" destination is actually safe while a password-recovery
 * session is in progress (both (auth) and (app) are route-guarded out from
 * under it). The 'exchanging' and 'invalid' phases don't use AuthHeader at
 * all, matching the same plain centered treatment used for other terminal
 * states in this auth family (e.g. Register's verification-required screen);
 * 'invalid' keeps its own pre-existing, session-aware navigation button
 * completely unchanged.
 */
export default function ResetPasswordScreen() {
  const { t } = useLocale();
  const rawParams = useLocalSearchParams<{ code?: string | string[] }>();
  const code = Array.isArray(rawParams.code) ? rawParams.code[0] : rawParams.code;

  const { session, isPasswordRecovery, completePasswordRecovery, signOut } = useSession();

  // Only genuinely async outcomes get their own state: whether the exchange
  // has failed, and whether a submit is in flight. Everything else (whether
  // we're still "exchanging", or "ready") is derived below from
  // isPasswordRecovery/code — deriving during render instead of setting it
  // from an effect, per this project's "derive, don't effect" standard.
  const [hasExchangeFailed, setHasExchangeFailed] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
  const [isConfirmPasswordVisible, setIsConfirmPasswordVisible] = useState(false);
  const hasAttemptedExchange = useRef(false);

  const uiPhase: UiPhase = hasExchangeFailed
    ? 'invalid'
    : isPasswordRecovery
      ? isSubmitting
        ? 'submitting'
        : 'ready'
      : code
        ? 'exchanging'
        : 'invalid';

  useEffect(() => {
    let isMounted = true;

    // Nothing to do: either already recovering (handled by the derived
    // uiPhase above), or no code to exchange (also derived — falls to
    // 'invalid' above without needing state), or already attempted.
    if (isPasswordRecovery || !code || hasAttemptedExchange.current) {
      return () => {
        isMounted = false;
      };
    }
    hasAttemptedExchange.current = true;

    supabase.auth
      .exchangeCodeForSession(code)
      .then(({ error: exchangeError }) => {
        if (!isMounted) return;
        if (exchangeError) {
          setHasExchangeFailed(true);
          setError(t(mapErrorToKey(exchangeError)));
        }
        // On success, SessionProvider's onAuthStateChange receives the
        // PASSWORD_RECOVERY event and isPasswordRecovery flips true, which
        // flows straight into uiPhase above — no further state needed here.
      })
      .catch(() => {
        if (!isMounted) return;
        setHasExchangeFailed(true);
        setError(t('resetPassword.invalidLinkMessage'));
      });

    return () => {
      isMounted = false;
    };
  }, [code, isPasswordRecovery, t]);

  async function handleSubmit() {
    setError(null);

    if (password.length < MIN_PASSWORD_LENGTH) {
      setError(t('common.passwordTooShort', { count: MIN_PASSWORD_LENGTH }));
      return;
    }

    if (password !== confirmPassword) {
      setError(t('common.passwordsDontMatch'));
      return;
    }

    setIsSubmitting(true);

    const { error: updateError } = await supabase.auth.updateUser({ password });

    if (updateError) {
      setIsSubmitting(false);
      setError(t(mapErrorToKey(updateError)));
      return;
    }

    // SPEC-ID-005 BR-22: successful recovery must not silently continue into
    // an ordinary authenticated session — it must end in a fresh sign-in with
    // the new credential, not a direct hop into (app). signOut() ends with
    // the same underlying supabase.auth.signOut() used everywhere in this
    // app (session-provider.tsx's centralized signOut, Milestone H); a
    // password-recovery-only session is gated out of the push
    // permission/registration effect entirely (see
    // src/hooks/use-push-notifications.ts), so there is normally no
    // registration to best-effort disable here, but routing through the
    // same centralized helper keeps this path correct if that ever changes.
    // supabase.auth.signOut() itself already treats a session the server has
    // already invalidated (e.g. if updateUser itself ended it) as "ignore the
    // 401/403/404 and clear local state anyway" rather than as a failure, so
    // this is safe to call unconditionally and never leaves stale local auth
    // state behind. completePasswordRecovery() is called explicitly rather
    // than relying only on the SIGNED_OUT-triggered reset, so the recovery
    // flag is guaranteed cleared before navigating.
    await signOut();
    completePasswordRecovery();
    router.replace('/sign-in');
  }

  if (uiPhase === 'exchanging') {
    return (
      <SafeAreaView style={styles.safeArea}>
        {/* Always-light background — see the main return below for why
            every branch of this screen needs its own explicit style. */}
        <StatusBar style="dark" />
        <View style={styles.centeredContent}>
          <ActivityIndicator color={colors.primary} />
          <Text style={styles.centeredText}>{t('resetPassword.checkingLink')}</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (uiPhase === 'invalid') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.centeredContent}>
          <Text style={styles.headline} accessibilityRole="header">
            {t('resetPassword.invalidTitle')}
          </Text>
          <Notice tone="error" message={error ?? t('resetPassword.invalidLinkMessage')} />
          <Button
            label={t('common.backToSignIn')}
            onPress={() => router.replace(session ? '/(app)' : '/(auth)/sign-in')}
          />
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      {/* This screen's background is always light — explicit dark icons so
          they don't inherit whatever style was last active (the public
          home's own `style="light"`, or the OS-driven default under
          `userInterfaceStyle: 'automatic'` when the device is in dark
          mode). Scoped to this screen only. */}
      <StatusBar style="dark" />
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <AuthHeader
            headline={t('resetPassword.title')}
            support={t('resetPassword.support')}
            showBackButton={false}
          />

          <View style={styles.form}>
            <Input
              label={t('resetPassword.newPasswordLabel')}
              autoCapitalize="none"
              autoComplete="new-password"
              secureTextEntry={!isPasswordVisible}
              value={password}
              onChangeText={setPassword}
              rightElement={
                <PasswordToggle
                  visible={isPasswordVisible}
                  onToggle={() => setIsPasswordVisible((visible) => !visible)}
                  showLabel={t('common.showPassword')}
                  hideLabel={t('common.hidePassword')}
                />
              }
            />

            <Input
              label={t('resetPassword.confirmPasswordLabel')}
              autoCapitalize="none"
              autoComplete="new-password"
              secureTextEntry={!isConfirmPasswordVisible}
              value={confirmPassword}
              onChangeText={setConfirmPassword}
              rightElement={
                <PasswordToggle
                  visible={isConfirmPasswordVisible}
                  onToggle={() => setIsConfirmPasswordVisible((visible) => !visible)}
                  showLabel={t('common.showPassword')}
                  hideLabel={t('common.hidePassword')}
                />
              }
            />
          </View>

          <View style={styles.actions}>
            {error ? <Notice tone="error" message={error} /> : null}
            <Button
              label={t('resetPassword.submit')}
              onPress={handleSubmit}
              loading={uiPhase === 'submitting'}
            />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  flex: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxxl,
  },
  form: {
    marginTop: spacing.xl,
    gap: spacing.lg,
  },
  actions: {
    marginTop: spacing.xl,
    gap: spacing.sm,
  },
  centeredContent: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.screenHorizontal,
  },
  headline: {
    ...typography.h1,
    color: colors.textPrimary,
    textAlign: 'center',
  },
  centeredText: {
    ...typography.body,
    color: colors.textSecondary,
    textAlign: 'center',
  },
});

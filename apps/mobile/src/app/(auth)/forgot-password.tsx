import { Ionicons } from '@expo/vector-icons';
import { Link } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AuthHeader } from '@/components/design-system/auth-header';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { mapErrorToKey } from '@/i18n/error-messages';
import { useLocale } from '@/i18n/locale-provider';
import { normalizeEmail } from '@/lib/email';
import { supabase } from '@/lib/supabase';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

// Uses the app's already-configured scheme (app.json "scheme": "com.menizvet")
// pointed at the reset-password route. Requires this exact value to be added
// to the linked Supabase project's Auth "Redirect URLs" allow-list — see the
// milestone report for the exact string to add; not changed here.
//
// PKCE same-device constraint: this call stores a code verifier locally (see
// reset-password.tsx for the full explanation) that only this device/install
// has, so the resulting link can only be completed on the device that
// requested it. This is expected, not a bug to work around.
const RESET_PASSWORD_REDIRECT_URL = 'com.menizvet://reset-password';

/**
 * Forgot Password — same Design System v1 pieces as Sign In/Register
 * (`AuthHeader`, `Button`, `Input`). Auth behavior below is unchanged from
 * the previous implementation: same `resetPasswordForEmail` call, same
 * identical confirmation regardless of whether the email is registered
 * (this screen must not be usable to enumerate accounts).
 *
 * `fallbackHref="/sign-in"` on `AuthHeader`: this screen is conceptually a
 * sub-page of Sign In, so that's the sensible destination when there's
 * nothing to go back to (e.g. deep-linked directly) — unlike Sign In and
 * Register, which fall back to the public home.
 */
export default function ForgotPasswordScreen() {
  const { t } = useLocale();
  const [email, setEmail] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitted, setSubmitted] = useState(false);

  async function handleSubmit() {
    if (isSubmitting) return;

    setError(null);
    setIsSubmitting(true);

    const { error: resetError } = await supabase.auth.resetPasswordForEmail(normalizeEmail(email), {
      redirectTo: RESET_PASSWORD_REDIRECT_URL,
    });

    setIsSubmitting(false);

    if (resetError) {
      setError(t(mapErrorToKey(resetError)));
      return;
    }

    // Same confirmation regardless of whether the email is registered, so
    // this screen cannot be used to enumerate accounts.
    setSubmitted(true);
  }

  if (submitted) {
    return (
      <SafeAreaView style={styles.safeArea}>
        {/* Always-light background here too — see the main return below for
            why this needs its own explicit style. */}
        <StatusBar style="dark" />
        <View style={styles.confirmationContent}>
          <View style={styles.confirmationIconWrap}>
            <Ionicons name="mail-outline" size={28} color={colors.primary} />
          </View>
          <Text style={styles.headline} accessibilityRole="header">
            {t('forgotPassword.confirmationTitle')}
          </Text>
          <Text style={styles.confirmationBody}>{t('forgotPassword.confirmationBody')}</Text>
          <Link href="/sign-in">
            <Text style={styles.secondaryLink}>{t('common.backToSignIn')}</Text>
          </Link>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      {/* This screen's background is always light, unlike the public
          home's photographic hero — explicit dark icons so they don't
          inherit whatever style was last active (the public home's own
          `style="light"`, or the OS-driven default under
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
            headline={t('forgotPassword.title')}
            support={t('forgotPassword.support')}
            fallbackHref="/sign-in"
          />

          <View style={styles.form}>
            <Input
              label={t('common.emailLabel')}
              autoCapitalize="none"
              autoComplete="email"
              keyboardType="email-address"
              value={email}
              onChangeText={setEmail}
            />
          </View>

          <View style={styles.actions}>
            {error ? <Notice tone="error" message={error} /> : null}
            <Button
              label={t('forgotPassword.submit')}
              onPress={handleSubmit}
              loading={isSubmitting}
            />
          </View>

          <View style={styles.secondaryActions}>
            <Link href="/sign-in">
              <Text style={styles.secondaryLink}>{t('common.backToSignIn')}</Text>
            </Link>
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
  secondaryActions: {
    marginTop: spacing.xl,
  },
  secondaryLink: {
    ...typography.bodyStrong,
    color: colors.primary,
    textAlign: 'center',
  },
  confirmationContent: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.screenHorizontal,
  },
  confirmationIconWrap: {
    width: 56,
    height: 56,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headline: {
    ...typography.h1,
    color: colors.textPrimary,
    textAlign: 'center',
  },
  confirmationBody: {
    ...typography.body,
    color: colors.textSecondary,
    textAlign: 'center',
  },
});

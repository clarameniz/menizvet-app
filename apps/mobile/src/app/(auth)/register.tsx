import { Link } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AuthHeader } from '@/components/design-system/auth-header';
import { Button } from '@/components/design-system/button';
import { Input, PasswordToggle } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { mapErrorToKey } from '@/i18n/error-messages';
import { useLocale } from '@/i18n/locale-provider';
import { normalizeEmail } from '@/lib/email';
import { supabase } from '@/lib/supabase';
import { MIN_PASSWORD_LENGTH } from '@/lib/validation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Register — same Design System v1 pieces as Sign In (`AuthHeader`,
 * `Button`, `Input`). Auth behavior below is unchanged from the previous
 * implementation: same client-side password-length pre-check before calling
 * `supabase.auth.signUp` (the approved identity backend, via
 * handle_new_auth_user / SPEC-ID-001, still owns creating the domain User
 * row — this never duplicates that), same verification-required branch when
 * no session comes back.
 */
export default function RegisterScreen() {
  const { t } = useLocale();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [verificationRequired, setVerificationRequired] = useState(false);

  async function handleRegister() {
    if (isSubmitting) return;

    if (password.length < MIN_PASSWORD_LENGTH) {
      setError(t('common.passwordTooShort', { count: MIN_PASSWORD_LENGTH }));
      return;
    }

    setError(null);
    setIsSubmitting(true);

    const { data, error: signUpError } = await supabase.auth.signUp({
      email: normalizeEmail(email),
      password,
    });

    setIsSubmitting(false);

    if (signUpError) {
      setError(t(mapErrorToKey(signUpError)));
      return;
    }

    if (!data.session) {
      // Auth project requires email verification before a session is issued
      // (SPEC-ID-002). Nothing else to do client-side; no custom token
      // handling is implemented here.
      setVerificationRequired(true);
      return;
    }

    // A session was issued immediately (email confirmation disabled for this
    // project). SessionProvider + Stack.Protected pick it up and enter (app).
  }

  if (verificationRequired) {
    return (
      <SafeAreaView style={styles.safeArea}>
        {/* Always-light background here too — see the main return below for
            why this needs its own explicit style. */}
        <StatusBar style="dark" />
        <View style={styles.verificationContent}>
          <Text style={styles.headline} accessibilityRole="header">
            {t('register.verificationTitle')}
          </Text>
          <Text style={styles.verificationBody}>{t('register.verificationBody')}</Text>
          <Link href="/sign-in">
            <Text style={styles.secondaryLink}>{t('register.goToSignIn')}</Text>
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
          <AuthHeader headline={t('register.title')} support={t('register.support')} />

          <View style={styles.form}>
            <Input
              label={t('common.emailLabel')}
              autoCapitalize="none"
              autoComplete="email"
              keyboardType="email-address"
              value={email}
              onChangeText={setEmail}
            />

            <Input
              label={t('common.passwordLabel')}
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
          </View>

          <View style={styles.actions}>
            {error ? <Notice tone="error" message={error} /> : null}
            <Button label={t('register.submit')} onPress={handleRegister} loading={isSubmitting} />
          </View>

          <View style={styles.secondaryActions}>
            <Link href="/sign-in">
              <Text style={styles.secondaryLink}>{t('register.haveAccount')}</Text>
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
  verificationContent: {
    flex: 1,
    justifyContent: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.screenHorizontal,
  },
  headline: {
    ...typography.h1,
    color: colors.textPrimary,
    textAlign: 'center',
  },
  verificationBody: {
    ...typography.body,
    color: colors.textSecondary,
    textAlign: 'center',
  },
});

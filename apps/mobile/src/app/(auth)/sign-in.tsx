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
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Sign In — first real extension of the public home's Design System v1
 * (`AuthHeader`, `Button`, `Input`) beyond the public home itself. Auth
 * behavior below is unchanged from the previous implementation: same
 * `supabase.auth.signInWithPassword` call, same error mapping, same
 * "no manual navigation" comment still applies (SessionProvider picks up
 * the new session via onAuthStateChange and the root layout's
 * Stack.Protected guard enters (app) on its own).
 *
 * Top-aligned, not vertically centered: on a real device, centering left a
 * large empty gap above the content on typical screen heights. The public
 * home's anonymous Clinic Discovery already covers "browse without an
 * account", so that link (previously here too) was dropped from this
 * screen specifically — the route itself is untouched.
 */
export default function SignInScreen() {
  const { t } = useLocale();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSignIn() {
    if (isSubmitting) return;

    setError(null);
    setIsSubmitting(true);

    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: normalizeEmail(email),
      password,
    });

    setIsSubmitting(false);

    if (signInError) {
      setError(t(mapErrorToKey(signInError)));
      return;
    }

    // No manual navigation here: SessionProvider picks up the new session via
    // onAuthStateChange and the root layout's Stack.Protected guard enters
    // (app) on its own.
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
          <AuthHeader headline={t('signIn.title')} support={t('signIn.support')} />

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
              autoComplete="password"
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
            <Button label={t('signIn.submit')} onPress={handleSignIn} loading={isSubmitting} />
          </View>

          <View style={styles.secondaryActions}>
            <Link href="/forgot-password">
              <Text style={styles.secondaryLink}>{t('signIn.forgotPassword')}</Text>
            </Link>

            <Link href="/register">
              <Text style={styles.secondaryLink}>{t('signIn.createAccount')}</Text>
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
    gap: spacing.md,
  },
  secondaryLink: {
    ...typography.bodyStrong,
    color: colors.primary,
    textAlign: 'center',
  },
});

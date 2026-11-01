import { Ionicons } from '@expo/vector-icons';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { BrandMark } from '@/components/design-system/brand-mark';
import { LanguageSelector } from '@/components/language-selector';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type AuthHeaderProps = {
  headline: string;
  support: string;
  /**
   * Where the back control goes when there's nothing real to go back to
   * (e.g. this route was reached via a deep link, so `router.canGoBack()`
   * is false). Defaults to the public home — Forgot Password passes
   * `/sign-in` instead, since it's conceptually a sub-page of it.
   */
  fallbackHref?: '/' | '/sign-in';
  /**
   * Hides the back control entirely. Used by Reset Password while a
   * password-recovery session is actually in progress: at that point
   * `session` is truthy and `isPasswordRecovery` is true, which the root
   * layout's route guards use to gate OUT both `(auth)` (needs `!session`)
   * and `(app)` (needs `!isPasswordRecovery`) — there is no route left that
   * a generic back action could safely land on until the flow completes on
   * its own. Defaults to true (shown) for every other screen.
   */
  showBackButton?: boolean;
};

/**
 * Shared header for Sign In / Register / Forgot Password / (the resumable
 * part of) Reset Password: back/home control + the same brand mark +
 * compact language control as the public home, on the same light
 * background (no hero photo here) — kept deliberately smaller than the
 * public home's brand row, since on these screens the form is the visual
 * focus, not the brand.
 */
export function AuthHeader({
  headline,
  support,
  fallbackHref = '/',
  showBackButton = true,
}: AuthHeaderProps) {
  const { t } = useLocale();

  // Prefer real back navigation (preserves whatever the user actually came
  // from); `fallbackHref` is only used when there's nothing to go back to
  // (e.g. this route was deep-linked to directly).
  const handleBack = () => goBackOr(fallbackHref);

  return (
    <View style={styles.container}>
      <View style={styles.topRow}>
        <View style={styles.leftGroup}>
          {showBackButton && (
            <Pressable
              onPress={handleBack}
              accessibilityRole="button"
              accessibilityLabel={t('common.back')}
              hitSlop={8}
              style={styles.backButton}
            >
              <Ionicons name="chevron-back-outline" size={24} color={colors.textPrimary} />
            </Pressable>
          )}
          <View style={styles.brandRow}>
            <BrandMark size={22} />
            <Text style={styles.brand}>{t('publicHome.brandName')}</Text>
          </View>
        </View>
        <LanguageSelector />
      </View>

      <View style={styles.titleBlock}>
        <Text style={styles.headline} accessibilityRole="header">
          {headline}
        </Text>
        <Text style={styles.support}>{support}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: spacing.xl,
  },
  topRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'space-between',
    rowGap: spacing.sm,
    columnGap: spacing.md,
  },
  leftGroup: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  backButton: {
    width: 44,
    height: 44,
    marginLeft: -spacing.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  brandRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  brand: {
    ...typography.h3,
    color: colors.textPrimary,
  },
  titleBlock: {
    gap: spacing.sm,
  },
  headline: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  support: {
    ...typography.body,
    color: colors.textSecondary,
  },
});

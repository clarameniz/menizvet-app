import { Ionicons } from '@expo/vector-icons';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { BrandMark } from '@/components/design-system/brand-mark';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type AppTopBarProps = {
  /**
   * Back action. Omit for a root screen (the authenticated home), which then
   * shows the brand alone. Each screen owns what "back" means — e.g. Pet
   * detail returns to My Pets with `dismissTo` (lib/pets-navigation.ts).
   */
  onBack?: () => void;
};

/**
 * Compact top row for authenticated screens: optional back control + the
 * same small brand mark as `AuthHeader`/`PublicTopBar`. No language control
 * here — signed-in Users change language in Profile.
 */
export function AppTopBar({ onBack }: AppTopBarProps) {
  const { t } = useLocale();

  return (
    <View style={styles.row}>
      {onBack ? (
        <Pressable
          onPress={onBack}
          accessibilityRole="button"
          accessibilityLabel={t('common.back')}
          hitSlop={8}
          style={styles.backButton}
        >
          <Ionicons name="chevron-back-outline" size={24} color={colors.textPrimary} />
        </Pressable>
      ) : null}
      <View
        style={styles.brandRow}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <BrandMark size={22} />
        <Text style={styles.brand}>{t('publicHome.brandName')}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    minHeight: 44,
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
});

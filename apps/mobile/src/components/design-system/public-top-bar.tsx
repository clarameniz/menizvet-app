import { Ionicons } from '@expo/vector-icons';
import type { Href } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { BrandMark } from '@/components/design-system/brand-mark';
import { LanguageSelector } from '@/components/language-selector';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type PublicTopBarProps = {
  /**
   * Where the back control goes when there's nothing real to go back to
   * (e.g. the route was deep-linked to directly, so `router.canGoBack()` is
   * false).
   */
  fallbackHref: Href;
  /**
   * Shows this screen title in the row instead of the brand mark — for a
   * screen (the Discovery map) where a separate title block below would cost
   * space the content needs. Omit it to show the brand.
   */
  title?: string;
};

/**
 * Compact top row for public Clinic Discovery screens: back control + the
 * same small brand mark + compact language control as `AuthHeader`'s top
 * row, so Discovery reads as the same product as the public home and auth
 * screens. Title/support copy is normally left to each screen — Discovery
 * titles vary (a fixed "Clinics" vs. an arbitrary-length Clinic name) in ways
 * a single headline style doesn't fit; `title` is only for the map's
 * single-row header.
 */
export function PublicTopBar({ fallbackHref, title }: PublicTopBarProps) {
  const { t } = useLocale();

  // Real back navigation first (preserves whether the user came from the
  // list, Nearby or the Map), `replace` to the fallback only when there's
  // nothing to go back to.
  const handleBack = () => goBackOr(fallbackHref);

  return (
    <View style={styles.topRow}>
      <View style={styles.leftGroup}>
        <Pressable
          onPress={handleBack}
          accessibilityRole="button"
          accessibilityLabel={t('common.back')}
          hitSlop={8}
          style={styles.backButton}
        >
          <Ionicons name="chevron-back-outline" size={24} color={colors.textPrimary} />
        </Pressable>
        {title ? (
          <Text style={styles.title} accessibilityRole="header" numberOfLines={1}>
            {title}
          </Text>
        ) : (
          <View
            style={styles.brandRow}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            <BrandMark size={22} />
            <Text style={styles.brand}>{t('publicHome.brandName')}</Text>
          </View>
        )}
      </View>
      <LanguageSelector />
    </View>
  );
}

const styles = StyleSheet.create({
  topRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'space-between',
    rowGap: spacing.sm,
    columnGap: spacing.md,
  },
  leftGroup: {
    flexShrink: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  title: {
    ...typography.h3,
    color: colors.textPrimary,
    flexShrink: 1,
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

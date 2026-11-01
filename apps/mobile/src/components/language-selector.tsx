import { Pressable, StyleSheet, Text, View } from 'react-native';

import { ChevronMark } from '@/components/design-system/icon';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Minimal "EN ▾" toggle for public/auth contexts (public home, `AuthHeader`)
 * where a full language list would dominate the layout. It only switches
 * between the two explicit languages — "follow system language" stays
 * reachable from Profile's Preferences section, which owns the full
 * System/Español/English choice. Same `setPreference` call, same persisted
 * preference, same resolution logic.
 */
export function LanguageSelector() {
  const { locale, setPreference, t } = useLocale();
  const fullLabel = t(locale === 'es' ? 'language.spanish' : 'language.english');

  return (
    <Pressable
      onPress={() => setPreference(locale === 'es' ? 'en' : 'es')}
      accessibilityRole="button"
      accessibilityLabel={`${t('language.title')}: ${fullLabel}`}
      hitSlop={8}
      style={styles.compactControl}
    >
      <Text style={styles.compactLabel}>{locale.toUpperCase()}</Text>
      <View style={styles.compactChevron}>
        <ChevronMark color={colors.textSecondary} size={12} />
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  compactControl: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radius.pill,
    backgroundColor: colors.surfaceSoft,
  },
  compactLabel: {
    ...typography.caption,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  compactChevron: {
    transform: [{ rotate: '90deg' }],
  },
});

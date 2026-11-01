import { Ionicons } from '@expo/vector-icons';
import { StyleSheet, Text, View } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type NoticeProps = {
  tone: 'info' | 'error';
  message: string;
  /**
   * Renders on its own white surface with a soft shadow, for notices floating
   * over the Discovery map. Otherwise inline and centered (e.g. a failed
   * "Load more" under a list).
   */
  floating?: boolean;
};

/**
 * One-line inline status (icon + already-localized copy), smaller than
 * `StateMessage`. `colors.error` is under AA contrast for 14px text, so the
 * tone color goes on the icon only; the message stays on `textPrimary`.
 */
export function Notice({ tone, message, floating = false }: NoticeProps) {
  return (
    <View
      style={[styles.row, floating && styles.floating]}
      accessibilityRole={tone === 'error' ? 'alert' : undefined}
      accessibilityLiveRegion="polite"
    >
      <Ionicons
        name={tone === 'error' ? 'alert-circle-outline' : 'information-circle-outline'}
        size={18}
        color={tone === 'error' ? colors.error : colors.primary}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.message}>{message}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
  },
  floating: {
    justifyContent: 'flex-start',
    gap: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.medium,
    borderWidth: 1,
    borderColor: colors.border,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    shadowColor: colors.textPrimary,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 6,
    elevation: 2,
  },
  message: {
    ...typography.caption,
    color: colors.textPrimary,
    flexShrink: 1,
  },
});

import { Pressable, StyleSheet, Text } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type DateChipProps = {
  weekday: string;
  dayMonth: string;
  /** The complete one-line date ("mié, 23 sept"), announced as a single element. */
  accessibilityLabel: string;
  selected: boolean;
  onPress: () => void;
  /** Not pressable and announced as disabled (e.g. while saving); keeps its selection. */
  disabled?: boolean;
};

/**
 * Compact two-line date option for a horizontal date picker: weekday
 * (smaller, secondary) over day + month (stronger). Same selected/unselected
 * language as `ChoiceChip` — solid teal with white text vs. white surface
 * with a border. `minWidth`, not a fixed width: every chip is the same width
 * at normal text size, but grows with a large font scale instead of
 * clipping its label.
 */
export function DateChip({
  weekday,
  dayMonth,
  accessibilityLabel,
  selected,
  onPress,
  disabled = false,
}: DateChipProps) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="radio"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ selected, checked: selected, disabled }}
      style={({ pressed }) => [
        styles.chip,
        selected ? styles.selected : styles.unselected,
        pressed && !selected && !disabled && styles.pressed,
      ]}
    >
      <Text style={[styles.weekday, selected && styles.textSelected]}>{weekday}</Text>
      <Text style={[styles.dayMonth, selected && styles.textSelected]}>{dayMonth}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  chip: {
    minWidth: 96,
    minHeight: 68,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.sm,
    borderRadius: radius.medium,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
  },
  unselected: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
  },
  selected: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  pressed: {
    backgroundColor: colors.primarySoft,
  },
  weekday: {
    ...typography.caption,
    fontSize: 13,
    lineHeight: 18,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  dayMonth: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    textAlign: 'center',
  },
  textSelected: {
    color: colors.surface,
  },
});

import { Pressable, StyleSheet, Text } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ChoiceChipProps = {
  label: string;
  selected: boolean;
  onPress: () => void;
  /** Defaults to `label`; pass a fuller phrase when the visible label is abbreviated. */
  accessibilityLabel?: string;
  /** Not pressable and announced as disabled (e.g. read-only or while saving); keeps its selection. */
  disabled?: boolean;
};

/**
 * Design System v1 single-choice chip (a radio option): white surface +
 * border when unselected, solid teal with white bold text when selected —
 * selection never relies on color alone (weight + fill + radio state).
 * ≥44dp tall; grows with font scale instead of clipping.
 */
export function ChoiceChip({
  label,
  selected,
  onPress,
  accessibilityLabel,
  disabled = false,
}: ChoiceChipProps) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="radio"
      accessibilityLabel={accessibilityLabel ?? label}
      accessibilityState={{ selected, checked: selected, disabled }}
      style={({ pressed }) => [
        styles.chip,
        selected ? styles.selected : styles.unselected,
        pressed && !selected && !disabled && styles.pressed,
      ]}
    >
      <Text style={[styles.label, selected && styles.labelSelected]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  chip: {
    minHeight: 44,
    minWidth: 64,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: radius.medium,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
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
  label: {
    ...typography.caption,
    fontWeight: '500',
    color: colors.textPrimary,
    textAlign: 'center',
  },
  labelSelected: {
    fontWeight: '700',
    color: colors.surface,
  },
});

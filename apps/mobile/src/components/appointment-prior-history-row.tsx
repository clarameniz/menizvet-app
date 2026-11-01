import { Ionicons } from '@expo/vector-icons';
import { Pressable, StyleSheet, Text } from 'react-native';

import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * "View previous records" on the professional Appointment detail
 * (SPEC-MED-010 BR-14): one quiet navigation row at the foot of the Clinical
 * record card, visually secondary to the visit's own records. It only
 * navigates — nothing is read until the history screen opens, and that read
 * decides access. It sits inside a card with `spacing.lg` side padding and
 * spans it edge to edge when pressed.
 */
export function AppointmentPriorHistoryRow({
  onPress,
  disabled = false,
}: {
  onPress: () => void;
  disabled?: boolean;
}) {
  const { t } = useLocale();
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={t('professionalHistory.action')}
      accessibilityHint={t('professionalHistory.actionHint')}
      accessibilityState={{ disabled }}
      style={({ pressed }) => [
        styles.row,
        disabled && styles.disabled,
        pressed && !disabled && styles.pressed,
      ]}
    >
      <Ionicons
        name="book-outline"
        size={18}
        color={colors.textSecondary}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.label}>{t('professionalHistory.action')}</Text>
      <Ionicons
        name="chevron-forward"
        size={18}
        color={colors.textMuted}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    minHeight: 48,
    paddingVertical: spacing.sm,
    // Edge to edge inside the card, so the pressed state spans its width.
    marginHorizontal: -spacing.lg,
    paddingHorizontal: spacing.lg,
  },
  label: { ...typography.body, color: colors.textSecondary, flex: 1 },
  disabled: { opacity: 0.5 },
  pressed: { backgroundColor: colors.primarySoft },
});

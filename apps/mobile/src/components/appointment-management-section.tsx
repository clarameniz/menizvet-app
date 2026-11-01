import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps, ReactNode } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * "Appointment management" on the professional Appointment detail: one card,
 * after the Clinical record, that gathers every lifecycle and scheduling
 * action the detail offers. It only lays them out — which actions appear, and
 * what each one does, stays with the detail. Like the Clinical record card,
 * its content is separated by discreet dividers, never a card per action.
 */
export function AppointmentManagementSection({ children }: { children: ReactNode }) {
  const { t } = useLocale();
  return (
    <View style={styles.card}>
      <Text style={styles.title} accessibilityRole="header">
        {t('professionalAppointment.managementTitle')}
      </Text>
      {children}
    </View>
  );
}

/** A block of the card's content (a note, the primary action, a form). */
export function ManagementBlock({ children }: { children: ReactNode }) {
  return <View style={styles.block}>{children}</View>;
}

/**
 * A secondary action of the card: icon, label and, for an action that opens
 * its own screen, a chevron. `caution` is for actions that end the visit
 * without it taking place (cancellation). ≥48pt tall, edge to edge when
 * pressed, below a discreet divider.
 */
export function ManagementActionRow({
  icon,
  label,
  onPress,
  disabled = false,
  loading = false,
  tone = 'neutral',
  navigates = false,
}: {
  icon: ComponentProps<typeof Ionicons>['name'];
  label: string;
  onPress: () => void;
  disabled?: boolean;
  loading?: boolean;
  tone?: 'neutral' | 'caution';
  navigates?: boolean;
}) {
  const isDisabled = disabled || loading;
  const color = tone === 'caution' ? colors.errorDark : colors.primary;
  return (
    <Pressable
      onPress={onPress}
      disabled={isDisabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: isDisabled, busy: loading }}
      style={({ pressed }) => [
        styles.row,
        isDisabled && !loading && styles.disabled,
        pressed && !isDisabled && styles.pressed,
      ]}
    >
      {loading ? (
        <ActivityIndicator size="small" color={color} />
      ) : (
        <Ionicons
          name={icon}
          size={20}
          color={color}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        />
      )}
      <Text style={[styles.rowLabel, tone === 'caution' && styles.cautionLabel]}>{label}</Text>
      {navigates ? (
        <Ionicons
          name="chevron-forward"
          size={18}
          color={colors.textMuted}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        />
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    paddingHorizontal: spacing.lg,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  title: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  block: { gap: spacing.sm, paddingBottom: spacing.md },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    minHeight: 48,
    paddingVertical: spacing.sm,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
    // Edge to edge inside the card, so the pressed state spans its width.
    marginHorizontal: -spacing.lg,
    paddingHorizontal: spacing.lg,
  },
  rowLabel: { ...typography.body, color: colors.textPrimary, flex: 1 },
  cautionLabel: { color: colors.errorDark },
  disabled: { opacity: 0.5 },
  pressed: { backgroundColor: colors.primarySoft },
});

import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { useLocale } from '@/i18n/locale-provider';
import { lifecycleLabelKey, type AppointmentLifecycleState } from '@/lib/appointment-lifecycle';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type BadgeStyle = {
  icon: ComponentProps<typeof Ionicons>['name'];
  iconColor: string;
  backgroundColor: string;
};

/**
 * One visual treatment per known lifecycle state. Meaning
 * never rides on color alone: every badge carries its icon AND the localized
 * label (lifecycleLabelKey), and the label is always navy `textPrimary` for
 * contrast — the state color only tints the soft background and the icon.
 * Cancelled/No-show stay neutral grey rather than red, so a history of
 * cancellations never reads as an alarming screen.
 */
const BADGE_STYLES: Record<AppointmentLifecycleState, BadgeStyle> = {
  REQUESTED: {
    icon: 'time-outline',
    iconColor: colors.warning,
    backgroundColor: colors.warningSoft,
  },
  CONFIRMED: {
    icon: 'checkmark-circle-outline',
    iconColor: colors.success,
    backgroundColor: colors.successSoft,
  },
  CANCELLED: {
    icon: 'close-circle-outline',
    iconColor: colors.textSecondary,
    backgroundColor: colors.surfaceSoft,
  },
  COMPLETED: {
    icon: 'checkmark-done-outline',
    iconColor: colors.primary,
    backgroundColor: colors.primarySoft,
  },
  NO_SHOW: {
    icon: 'remove-circle-outline',
    iconColor: colors.textSecondary,
    backgroundColor: colors.surfaceSoft,
  },
  // Its own terminal outcome (SPEC-APT-015): the Clinic didn't confirm the
  // request in time. Deliberately not the Cancelled/No-show treatment.
  EXPIRED: {
    icon: 'hourglass-outline',
    iconColor: colors.accent,
    backgroundColor: colors.accentSoft,
  },
};

type AppointmentStatusBadgeProps = {
  state: AppointmentLifecycleState;
};

export function AppointmentStatusBadge({ state }: AppointmentStatusBadgeProps) {
  const { t } = useLocale();
  const style = BADGE_STYLES[state];

  return (
    <View style={[styles.badge, { backgroundColor: style.backgroundColor }]}>
      <Ionicons
        name={style.icon}
        size={14}
        color={style.iconColor}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.label}>{t(lifecycleLabelKey(state))}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    gap: spacing.xs,
    paddingVertical: 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.pill,
  },
  label: {
    ...typography.caption,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '600',
    color: colors.textPrimary,
  },
});

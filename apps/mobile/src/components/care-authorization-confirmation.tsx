import { Ionicons } from '@expo/vector-icons';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type CareAuthorizationConfirmationProps = {
  petName: string;
  clinicName: string;
  confirmed: boolean;
  onChange: (confirmed: boolean) => void;
};

/**
 * SPEC-ACC-001 BR-16: this must not be reduced to a generic
 * "terms accepted" boolean. Its copy names the specific Pet and Clinic and
 * states the concrete purpose (evaluate/prepare/organize/provide veterinary
 * care). There is no backend p_accept_care_authorization parameter —
 * request_appointment establishes the Care Authorization unconditionally as
 * part of a successful request, so this control's only role is making sure
 * the Guardian has explicitly seen and confirmed that before submitting
 * (see request-appointment.tsx, which blocks submission until it is
 * confirmed).
 *
 * Design System v1 presentation only: one bordered card with the
 * explanation, and a full-width checkbox row whose visible text and
 * accessible label are both the complete Pet- and Clinic-specific
 * confirmation sentence.
 */
export function CareAuthorizationConfirmation({
  petName,
  clinicName,
  confirmed,
  onChange,
}: CareAuthorizationConfirmationProps) {
  const { t } = useLocale();
  const confirmLabel = t('appointmentRequest.careAuthConfirmLabel', {
    pet: petName,
    clinic: clinicName,
  });

  return (
    <View style={styles.card}>
      <View style={styles.titleRow}>
        <View
          style={styles.titleIcon}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Ionicons name="shield-checkmark-outline" size={16} color={colors.primary} />
        </View>
        <Text style={styles.title} accessibilityRole="header">
          {t('appointmentRequest.careAuthTitle')}
        </Text>
      </View>

      <Text style={styles.body}>
        {t('appointmentRequest.careAuthBody', { pet: petName, clinic: clinicName })}
      </Text>

      <Pressable
        onPress={() => onChange(!confirmed)}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: confirmed }}
        accessibilityLabel={confirmLabel}
        style={({ pressed }) => [
          styles.confirmRow,
          confirmed && styles.confirmRowChecked,
          pressed && styles.pressed,
        ]}
      >
        <Ionicons
          name={confirmed ? 'checkbox' : 'square-outline'}
          size={24}
          color={confirmed ? colors.primary : colors.textSecondary}
        />
        <Text style={[styles.confirmText, confirmed && styles.confirmTextChecked]}>
          {confirmLabel}
        </Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    gap: spacing.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    padding: spacing.lg,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  titleIcon: {
    width: 28,
    height: 28,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  body: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  confirmRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    minHeight: 44,
    padding: spacing.md,
    borderRadius: radius.small,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  confirmRowChecked: {
    borderColor: colors.primary,
    backgroundColor: colors.primarySoft,
  },
  pressed: {
    opacity: 0.85,
  },
  confirmText: {
    ...typography.body,
    color: colors.textPrimary,
    flex: 1,
  },
  confirmTextChecked: {
    fontWeight: '600',
  },
});

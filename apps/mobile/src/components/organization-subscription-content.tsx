import { Ionicons } from '@expo/vector-icons';
import { StyleSheet, Text, View } from 'react-native';

import type { OrganizationSubscriptionStatus } from '@/data/organization-subscription';
import { useLocale } from '@/i18n/locale-provider';
import { subscriptionInstantLabel, subscriptionStatusView } from '@/lib/organization-subscription';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Read-only Subscription status (SPEC-SUB-002 §15): the stored state as
 * stored, validity dates only when present, and service availability shown
 * separately. Renders only what the strict status read returns — never
 * provider, event or internal commercial identifiers.
 */
export function OrganizationSubscriptionContent({
  status,
}: {
  status: OrganizationSubscriptionStatus;
}) {
  const { t, locale } = useLocale();
  const view = subscriptionStatusView(status);
  const lines = view.lines.map((line) =>
    line.date === null
      ? t(line.key)
      : t(line.key, { date: subscriptionInstantLabel(line.date, locale) }),
  );
  return (
    <>
      <Text style={styles.organization}>{status.organizationDisplayName}</Text>
      <View style={styles.section}>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {t('subscription.statusHeading')}
        </Text>
        <View
          style={styles.card}
          accessible
          accessibilityRole="text"
          accessibilityLabel={[view.stateKey === null ? null : t(view.stateKey), ...lines]
            .filter((part): part is string => part !== null)
            .join('. ')}
        >
          {view.stateKey !== null ? (
            <View style={styles.stateRow}>
              <Ionicons
                name={
                  view.tone === 'positive'
                    ? 'checkmark-circle-outline'
                    : view.tone === 'attention'
                      ? 'alert-circle-outline'
                      : 'ellipse-outline'
                }
                size={22}
                color={view.tone === 'positive' ? colors.primary : colors.textSecondary}
              />
              <Text style={styles.stateLabel}>{t(view.stateKey)}</Text>
            </View>
          ) : null}
          {lines.map((line, index) => (
            <Text key={index} style={styles.line}>
              {line}
            </Text>
          ))}
        </View>
      </View>
      <View style={styles.section}>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {t('subscription.servicesHeading')}
        </Text>
        <View style={styles.card}>
          {view.services.map((service) => (
            <View
              key={service.labelKey}
              style={styles.serviceRow}
              accessible
              accessibilityRole="text"
              accessibilityLabel={`${t(service.labelKey)}: ${t(
                service.available
                  ? 'subscription.serviceAvailable'
                  : 'subscription.serviceUnavailable',
              )}`}
            >
              <Text style={styles.serviceLabel}>{t(service.labelKey)}</Text>
              <Text style={service.available ? styles.available : styles.unavailable}>
                {t(
                  service.available
                    ? 'subscription.serviceAvailable'
                    : 'subscription.serviceUnavailable',
                )}
              </Text>
            </View>
          ))}
        </View>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  organization: { ...typography.h3, color: colors.textPrimary },
  section: { gap: spacing.sm },
  sectionTitle: { ...typography.caption, fontWeight: '600', color: colors.textSecondary },
  card: {
    gap: spacing.sm,
    padding: spacing.lg,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
  },
  stateRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  stateLabel: { ...typography.bodyStrong, color: colors.textPrimary },
  line: { ...typography.caption, color: colors.textSecondary },
  serviceRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: spacing.md,
  },
  serviceLabel: { ...typography.body, color: colors.textPrimary, flex: 1 },
  available: { ...typography.caption, fontWeight: '600', color: colors.textPrimary },
  unavailable: { ...typography.caption, color: colors.textSecondary },
});

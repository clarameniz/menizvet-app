import { Ionicons } from '@expo/vector-icons';
import { useState, type ComponentProps } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { ClinicalVersionHistory } from '@/components/clinical-version-history';
import { Button } from '@/components/design-system/button';
import type { ProfessionalHistoryEntry } from '@/data/professional-medical-history';
import { useLocale } from '@/i18n/locale-provider';
import { hasEntryChanges } from '@/lib/appointment-clinical-record';
import { categoryLabelKey, formatClinicalInstant } from '@/lib/clinical-history-display';
import { correctionCountLabel, provenanceName } from '@/lib/professional-medical-history';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ProfessionalHistoryEntryCardProps = {
  entry: ProfessionalHistoryEntry;
  expanded: boolean;
  onToggle: () => void;
};

/**
 * One finalized Entry of the professional longitudinal history (SPEC-MED-005
 * BR-43/BR-44), in its current version (SPEC-MED-010 BR-22). Collapsed, it
 * reads in this order: clinical date and category, Clinic · Organization, the
 * Veterinarian who recorded it, a discreet "Edited" when its author changed it,
 * and how many historical corrections it has. Expanded: the current clinical
 * content, when it was recorded and last edited, and "View changes" — only
 * when earlier versions or historical corrections exist — showing each, oldest
 * first, with its author. Read only: no edit action and no Attachment. No
 * identifier is ever rendered.
 */
export function ProfessionalHistoryEntryCard({
  entry,
  expanded,
  onToggle,
}: ProfessionalHistoryEntryCardProps) {
  const { t, locale } = useLocale();
  const [showChanges, setShowChanges] = useState(false);
  const changes = hasEntryChanges(entry);
  const editedLabel =
    entry.editedAt === null
      ? null
      : t('clinicalRecord.editedAt', { time: formatClinicalInstant(entry.editedAt, locale) });
  const fallback = t('professionalHistory.veterinarianFallback');
  const categoryLabel = t(categoryLabelKey(entry.category));
  const dateLabel = formatClinicalInstant(entry.historyOrderAt, locale);
  const providerLabel = [
    entry.clinicDisplayName ?? t('clinicalHistory.clinicUnavailable'),
    entry.organizationDisplayName,
  ]
    .filter((part): part is string => part !== null)
    .join(' · ');
  const authorLabel = entry.author.isMe
    ? `${provenanceName(entry.author, fallback)} ${t('professionalHistory.youSuffix')}`
    : provenanceName(entry.author, fallback);
  const corrections = entry.amendmentCount > 0 ? correctionCountLabel(entry.amendmentCount) : null;
  const correctionsLabel = corrections !== null ? t(corrections.key, corrections.params) : null;
  const otherContext =
    entry.category === 'OTHER' && entry.otherCategoryContext ? entry.otherCategoryContext : null;

  const accessibilityLabel = [
    dateLabel,
    categoryLabel,
    otherContext,
    providerLabel,
    authorLabel,
    entry.isThisAppointment ? t('professionalHistory.thisAppointment') : null,
    editedLabel,
    correctionsLabel,
  ]
    .filter((part): part is string => part !== null)
    .join(', ');

  return (
    <View style={styles.card}>
      <Pressable
        onPress={onToggle}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityHint={t(
          expanded ? 'professionalHistory.collapse' : 'professionalHistory.expand',
        )}
        accessibilityState={{ expanded }}
        style={({ pressed }) => [styles.header, pressed && styles.headerPressed]}
      >
        <View style={styles.headerText}>
          <Text style={styles.date}>{dateLabel}</Text>
          <View style={styles.pillRow}>
            <View style={styles.categoryPill}>
              <Text style={styles.categoryText}>{categoryLabel}</Text>
            </View>
            {entry.isThisAppointment ? (
              <View style={styles.thisPill}>
                <Text style={styles.thisText}>{t('professionalHistory.thisAppointment')}</Text>
              </View>
            ) : null}
          </View>
          {otherContext ? <Text style={styles.otherContext}>{otherContext}</Text> : null}
          <MetaRow icon="business-outline" text={providerLabel} />
          <MetaRow icon="person-outline" text={authorLabel} />
          {editedLabel !== null ? <MetaRow icon="create-outline" text={editedLabel} /> : null}
          {correctionsLabel !== null ? (
            <MetaRow icon="create-outline" text={correctionsLabel} emphasis />
          ) : null}
        </View>
        <Ionicons
          name={expanded ? 'chevron-up' : 'chevron-down'}
          size={20}
          color={colors.textSecondary}
          style={styles.chevron}
        />
      </Pressable>

      {expanded ? (
        <View style={styles.expanded}>
          <View style={styles.divider} />
          <Text style={styles.content}>{entry.clinicalContent}</Text>
          <Text style={styles.meta}>
            {t('professionalHistory.recordedAt', {
              time: formatClinicalInstant(entry.finalizedAt, locale),
            })}
          </Text>

          {changes ? (
            <View style={styles.changesAction}>
              <Button
                variant="tertiary"
                label={t(showChanges ? 'clinicalRecord.hideChanges' : 'clinicalRecord.viewChanges')}
                onPress={() => setShowChanges((current) => !current)}
              />
            </View>
          ) : null}

          {changes && showChanges ? (
            <ClinicalVersionHistory
              versions={entry.previousVersions}
              truncated={entry.previousVersionsTruncated}
              formatTime={(isoInstant) => formatClinicalInstant(isoInstant, locale)}
              authorLabel={authorLabel}
            />
          ) : null}

          {changes && showChanges && entry.amendments.length > 0 ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle} accessibilityRole="header">
                {t('professionalHistory.correctionsTitle')}
              </Text>
              {entry.amendments.map((amendment, index) => {
                const author = amendment.author.isMe
                  ? `${provenanceName(amendment.author, fallback)} ${t('professionalHistory.youSuffix')}`
                  : provenanceName(amendment.author, fallback);
                return (
                  <View key={amendment.amendmentId} style={styles.amendment}>
                    <Text style={styles.amendmentLabel} accessibilityRole="header">
                      {t('professionalHistory.correctionLabel', {
                        index: index + 1,
                        total: entry.amendmentCount,
                      })}
                    </Text>
                    <Text style={styles.amendmentReason}>
                      {t('professionalHistory.correctionReason', { reason: amendment.reason })}
                    </Text>
                    <Text style={styles.content}>{amendment.amendmentContent}</Text>
                    <Text style={styles.meta}>
                      {`${t('professionalHistory.correctionBy', { name: author })} · ${t(
                        'professionalHistory.correctionAddedAt',
                        { time: formatClinicalInstant(amendment.createdAt, locale) },
                      )}`}
                    </Text>
                  </View>
                );
              })}
              {entry.amendmentsTruncated ? (
                <Text style={styles.meta}>{t('professionalHistory.correctionsTruncated')}</Text>
              ) : null}
            </View>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

function MetaRow({
  icon,
  text,
  emphasis = false,
}: {
  icon: ComponentProps<typeof Ionicons>['name'];
  text: string;
  emphasis?: boolean;
}) {
  return (
    <View style={styles.metaRow}>
      <Ionicons name={icon} size={14} color={colors.textSecondary} />
      <Text style={emphasis ? styles.metaStrong : styles.meta}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  header: { flexDirection: 'row', padding: spacing.lg, gap: spacing.md },
  headerPressed: { backgroundColor: colors.surfaceSoft },
  headerText: { flex: 1, gap: spacing.xs },
  date: { ...typography.bodyStrong, color: colors.textPrimary },
  pillRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  categoryPill: {
    alignSelf: 'flex-start',
    backgroundColor: colors.surfaceSoft,
    borderRadius: radius.small,
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
  },
  categoryText: { ...typography.caption, fontWeight: '600', color: colors.textPrimary },
  thisPill: {
    alignSelf: 'flex-start',
    borderRadius: radius.small,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
  },
  thisText: { ...typography.caption, color: colors.textSecondary },
  otherContext: { ...typography.caption, color: colors.textSecondary },
  chevron: { alignSelf: 'center' },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  meta: { ...typography.caption, color: colors.textSecondary, flexShrink: 1 },
  metaStrong: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
    flexShrink: 1,
  },
  expanded: { paddingHorizontal: spacing.lg, paddingBottom: spacing.lg, gap: spacing.sm },
  divider: { height: 1, backgroundColor: colors.border },
  content: { ...typography.body, color: colors.textPrimary },
  section: { gap: spacing.sm, marginTop: spacing.sm },
  changesAction: { alignItems: 'flex-start' },
  sectionTitle: { ...typography.bodyStrong, color: colors.textPrimary },
  amendment: {
    gap: spacing.xs,
    backgroundColor: colors.surfaceSoft,
    borderRadius: radius.small,
    borderLeftWidth: 3,
    borderLeftColor: colors.border,
    padding: spacing.md,
  },
  amendmentLabel: { ...typography.caption, fontWeight: '600', color: colors.textPrimary },
  amendmentReason: { ...typography.caption, color: colors.textPrimary },
});

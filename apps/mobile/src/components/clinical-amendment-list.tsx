import { StyleSheet, Text, View } from 'react-native';

import type { AppointmentClinicalAmendment } from '@/data/appointment-clinical-record';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ClinicalAmendmentListProps = {
  amendments: readonly AppointmentClinicalAmendment[];
  truncated: boolean;
  /** Formats a correction's time the way the surrounding card formats its dates. */
  formatTime: (isoInstant: string) => string;
};

/**
 * The historical reason-and-addition corrections of one Entry (SPEC-MED-010
 * BR-18, kind ADDENDUM), recorded before Entries became editable, oldest
 * first, under "View changes": each its reason, its text, when it was added,
 * and authorship only as You / Another veterinarian. Read only — none can be
 * added any more. Renders nothing when the Entry has none.
 */
export function ClinicalAmendmentList({
  amendments,
  truncated,
  formatTime,
}: ClinicalAmendmentListProps) {
  const { t } = useLocale();
  if (amendments.length === 0) return null;

  return (
    <View style={styles.section}>
      {amendments.map((amendment) => {
        const addedAt = t('clinicalRecord.amendmentAddedAt', {
          time: formatTime(amendment.createdAt),
        });
        const author = t(
          amendment.amendedByMe ? 'clinicalRecord.byYou' : 'clinicalRecord.byAnother',
        );
        return (
          <View key={amendment.amendmentId} style={styles.amendment}>
            <Text style={styles.title}>{t('clinicalRecord.earlierCorrection')}</Text>
            <Text style={styles.reason}>
              {`${t('clinicalRecord.amendmentReasonLabel')}: ${amendment.reason}`}
            </Text>
            <Text style={styles.content}>{amendment.amendmentContent}</Text>
            <Text style={styles.meta}>{`${addedAt} · ${author}`}</Text>
          </View>
        );
      })}
      {truncated ? (
        <Text style={styles.meta}>{t('clinicalRecord.amendmentsTruncated')}</Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { gap: spacing.sm },
  title: { ...typography.caption, fontWeight: '600', color: colors.textPrimary },
  amendment: {
    gap: spacing.xs,
    backgroundColor: colors.surfaceSoft,
    borderRadius: radius.small,
    borderLeftWidth: 3,
    borderLeftColor: colors.border,
    padding: spacing.md,
  },
  reason: { ...typography.caption, color: colors.textPrimary },
  content: { ...typography.body, color: colors.textPrimary },
  meta: { ...typography.caption, color: colors.textSecondary },
});

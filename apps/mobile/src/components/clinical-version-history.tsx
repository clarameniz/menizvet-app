import { StyleSheet, Text, View } from 'react-native';

import type { ClinicalEntryVersion } from '@/data/clinical-entry-versions';
import { useLocale } from '@/i18n/locale-provider';
import { categoryLabelKey } from '@/lib/clinical-history-display';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ClinicalVersionHistoryProps = {
  /** The earlier versions, oldest first, as the read returns them. */
  versions: readonly ClinicalEntryVersion[];
  truncated: boolean;
  /** Formats a version's time the way the surrounding card formats its dates. */
  formatTime: (isoInstant: string) => string;
  /** Who saved every version — the Entry's author — or `null` where authorship is not shown. */
  authorLabel: string | null;
};

/**
 * The history of changes of one Clinical Record Entry (SPEC-MED-010 BR-18,
 * Part F), shown under "View changes": every earlier version, oldest first —
 * what it said (category, OTHER context, text), when it was saved, and by
 * whom where the surrounding read shows authorship. The current version is the
 * card itself and is not repeated. Renders nothing without earlier versions.
 */
export function ClinicalVersionHistory({
  versions,
  truncated,
  formatTime,
  authorLabel,
}: ClinicalVersionHistoryProps) {
  const { t } = useLocale();
  if (versions.length === 0) return null;

  return (
    <View style={styles.section}>
      {versions.map((version) => {
        const title = t(
          version.version === 1 ? 'clinicalRecord.originalVersion' : 'clinicalRecord.versionNumber',
          { number: version.version },
        );
        const when = t(
          version.version === 1 ? 'clinicalRecord.recordedOn' : 'clinicalRecord.savedOn',
          { time: formatTime(version.createdAt) },
        );
        const meta = authorLabel === null ? when : `${when} · ${authorLabel}`;
        const category = t(categoryLabelKey(version.category));
        const context =
          version.category === 'OTHER' && version.otherCategoryContext !== null
            ? version.otherCategoryContext
            : null;
        return (
          <View
            key={version.version}
            style={styles.version}
            accessible
            accessibilityLabel={[title, category, context, version.clinicalContent, meta]
              .filter((part): part is string => part !== null)
              .join(', ')}
          >
            <Text style={styles.title}>{title}</Text>
            <Text style={styles.category}>
              {context === null ? category : `${category} · ${context}`}
            </Text>
            <Text style={styles.content}>{version.clinicalContent}</Text>
            <Text style={styles.meta}>{meta}</Text>
          </View>
        );
      })}
      {truncated ? <Text style={styles.meta}>{t('clinicalRecord.versionsTruncated')}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { gap: spacing.sm },
  version: {
    gap: spacing.xs,
    backgroundColor: colors.surfaceSoft,
    borderRadius: radius.small,
    borderLeftWidth: 3,
    borderLeftColor: colors.border,
    padding: spacing.md,
  },
  title: { ...typography.caption, fontWeight: '600', color: colors.textPrimary },
  category: { ...typography.caption, color: colors.textPrimary },
  content: { ...typography.body, color: colors.textPrimary },
  meta: { ...typography.caption, color: colors.textSecondary },
});

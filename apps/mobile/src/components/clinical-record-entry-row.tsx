import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { ClinicalAmendmentList } from '@/components/clinical-amendment-list';
import { ClinicalVersionHistory } from '@/components/clinical-version-history';
import { CompactAction, RowIconAction } from '@/components/design-system/compact-action';
import type { AppointmentClinicalEntry } from '@/data/appointment-clinical-record';
import { useLocale } from '@/i18n/locale-provider';
import { hasEntryChanges } from '@/lib/appointment-clinical-record';
import { formatRecordedInstant } from '@/lib/appointment-time';
import { categoryLabelKey } from '@/lib/clinical-history-display';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

// Clinical text past either limit starts collapsed to COLLAPSED_LINES, with
// "Read in full"; anything shorter is always shown whole, so nothing is ever
// cut without that action.
const LONG_CONTENT_CHARACTERS = 280;
const LONG_CONTENT_LINES = 5;
const COLLAPSED_LINES = 6;

function isLongClinicalContent(content: string): boolean {
  return (
    content.length > LONG_CONTENT_CHARACTERS || content.split('\n').length > LONG_CONTENT_LINES
  );
}

type ClinicalRecordEntryRowProps = {
  entry: AppointmentClinicalEntry;
  timeZone: string;
  /** The pencil — only for the reader's own Entry. */
  onEdit?: () => void;
  /** "Add a clarifying record" — only on another Veterinarian's Entry, when the reader can record. */
  onClarify?: () => void;
  disabled?: boolean;
};

/**
 * One recorded Entry of the visit (SPEC-MED-010 Part F) as a row of the
 * Clinical record card, in its current version: the category (and the OTHER
 * context) with the row's icon actions beside it, the clinical text below at
 * full width, one date — "Recorded on", the original recording time — and
 * authorship only as You / Another veterinarian. An edited Entry adds a
 * discreet "Edited" with the time of its current version.
 *
 * The pencil edits (author only); the history icon appears only when earlier
 * versions or historical corrections exist and shows them in place. A long
 * text starts collapsed with "Read in full"; screen readers always get it
 * whole. No identifier is rendered.
 */
export function ClinicalRecordEntryRow({
  entry,
  timeZone,
  onEdit,
  onClarify,
  disabled = false,
}: ClinicalRecordEntryRowProps) {
  const { t, locale } = useLocale();
  const [showChanges, setShowChanges] = useState(false);
  const [readInFull, setReadInFull] = useState(false);
  const formatTime = (isoInstant: string) => formatRecordedInstant(isoInstant, timeZone, locale);
  const categoryLabel = t(categoryLabelKey(entry.category));
  const author = t(entry.recordedByMe ? 'clinicalRecord.byYou' : 'clinicalRecord.byAnother');
  const recordedLabel = t('clinicalRecord.recordedOn', { time: formatTime(entry.recordedAt) });
  const editedLabel =
    entry.editedAt === null
      ? null
      : t('clinicalRecord.editedAt', { time: formatTime(entry.editedAt) });
  const otherContext =
    entry.category === 'OTHER' && entry.otherCategoryContext !== null
      ? entry.otherCategoryContext
      : null;
  const changes = hasEntryChanges(entry);
  const long = isLongClinicalContent(entry.clinicalContent);
  const target = { category: categoryLabel };

  return (
    <View style={styles.row}>
      {/* The icons own their column, so a long category wraps instead of running under them. */}
      <View style={styles.header}>
        <Text style={styles.category}>
          {otherContext === null ? categoryLabel : `${categoryLabel} · ${otherContext}`}
        </Text>
        {onEdit !== undefined || changes ? (
          <View style={styles.icons}>
            {onEdit !== undefined ? (
              <RowIconAction
                icon="create-outline"
                accessibilityLabel={t('clinicalRecord.editAccessibility', target)}
                onPress={onEdit}
                disabled={disabled}
              />
            ) : null}
            {changes ? (
              <RowIconAction
                icon="time-outline"
                accessibilityLabel={t(
                  showChanges
                    ? 'clinicalRecord.hideChangesAccessibility'
                    : 'clinicalRecord.viewChangesAccessibility',
                  target,
                )}
                expanded={showChanges}
                onPress={() => setShowChanges((current) => !current)}
              />
            ) : null}
          </View>
        ) : null}
      </View>

      <Text
        style={styles.content}
        numberOfLines={long && !readInFull ? COLLAPSED_LINES : undefined}
        accessibilityLabel={entry.clinicalContent}
      >
        {entry.clinicalContent}
      </Text>
      {long ? (
        <Pressable
          onPress={() => setReadInFull((current) => !current)}
          accessibilityRole="button"
          accessibilityLabel={t(
            readInFull
              ? 'clinicalRecord.readLessAccessibility'
              : 'clinicalRecord.readMoreAccessibility',
            target,
          )}
          accessibilityState={{ expanded: readInFull }}
          hitSlop={12}
          style={styles.readMore}
        >
          <Text style={styles.readMoreText}>
            {t(readInFull ? 'clinicalRecord.readLess' : 'clinicalRecord.readMore')}
          </Text>
        </Pressable>
      ) : null}

      <Text style={styles.meta}>{`${recordedLabel} · ${author}`}</Text>
      {editedLabel !== null ? <Text style={styles.meta}>{editedLabel}</Text> : null}

      {changes && showChanges ? (
        <View style={styles.changes}>
          <ClinicalVersionHistory
            versions={entry.previousVersions}
            truncated={entry.previousVersionsTruncated}
            formatTime={formatTime}
            authorLabel={author}
          />
          <ClinicalAmendmentList
            amendments={entry.amendments}
            truncated={entry.amendmentsTruncated}
            formatTime={formatTime}
          />
        </View>
      ) : null}

      {onClarify !== undefined ? (
        <View style={styles.clarify}>
          <CompactAction
            icon="chatbox-ellipses-outline"
            label={t('clinicalRecord.clarify')}
            accessibilityLabel={t('clinicalRecord.clarifyAccessibility', target)}
            onPress={onClarify}
            disabled={disabled}
          />
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { gap: spacing.xs, paddingTop: spacing.sm, paddingBottom: spacing.md },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, minHeight: 44 },
  category: { ...typography.bodyStrong, color: colors.textPrimary, flex: 1 },
  // Flush right despite the icons' touch padding.
  icons: { flexDirection: 'row', marginRight: -spacing.sm },
  content: { ...typography.body, color: colors.textPrimary },
  readMore: { alignSelf: 'flex-start', paddingVertical: spacing.xs, borderRadius: radius.small },
  readMoreText: { ...typography.caption, fontWeight: '600', color: colors.primary },
  meta: { ...typography.caption, color: colors.textSecondary },
  changes: { gap: spacing.sm, paddingTop: spacing.sm },
  // The label lines up with the text despite the action's touch padding.
  clarify: { alignSelf: 'flex-start', marginLeft: -spacing.sm },
});

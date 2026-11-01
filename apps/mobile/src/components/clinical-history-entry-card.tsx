import { Ionicons } from '@expo/vector-icons';
import * as WebBrowser from 'expo-web-browser';
import { useRef, useState, type ComponentProps } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

import { ClinicalVersionHistory } from '@/components/clinical-version-history';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import {
  getGuardianClinicalAttachmentDownloadUrl,
  type ClinicalAttachment,
  type GuardianMedicalHistoryEntry,
} from '@/data/clinical-history';
import { mapClinicalHistoryErrorToKey } from '@/i18n/clinical-history-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { hasEntryChanges } from '@/lib/appointment-clinical-record';
import {
  categoryLabelKey,
  formatAttachmentSizeKb,
  formatClinicalInstant,
  resolveAttachmentLabel,
} from '@/lib/clinical-history-display';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ClinicalHistoryEntryCardProps = {
  entry: GuardianMedicalHistoryEntry;
  expanded: boolean;
  onToggle: () => void;
};

/**
 * One Guardian medical-history Entry, collapsed by default. Never renders
 * author/assigned-Veterinarian ids, Clinic/Organization/Appointment ids, or
 * any other internal identifier — none of those are carried
 * into GuardianMedicalHistoryEntry in the first place (see
 * data/clinical-history.ts), so there is nothing internal left to
 * accidentally leak here.
 *
 * Design System v1 presentation: category (+ "other" context), history date,
 * Clinic and Organization names when collapsed; when expanded, the Entry's
 * current version (SPEC-MED-010 BR-22), its recorded date, a discreet
 * "Edited" when its author changed it, "View changes" — only when earlier
 * versions or historical corrections exist — and attachments.
 */
export function ClinicalHistoryEntryCard({
  entry,
  expanded,
  onToggle,
}: ClinicalHistoryEntryCardProps) {
  const { t, locale } = useLocale();
  const [showChanges, setShowChanges] = useState(false);
  const changes = hasEntryChanges(entry);

  const categoryLabel = t(categoryLabelKey(entry.category));
  const otherContext =
    entry.category === 'OTHER' && entry.otherCategoryContext ? entry.otherCategoryContext : null;
  const eventDateLabel = formatClinicalInstant(entry.historyOrderAt, locale);
  const clinicLabel = entry.clinicDisplayName ?? t('clinicalHistory.clinicUnavailable');

  const accessibilityLabel = [categoryLabel, eventDateLabel, clinicLabel].join(', ');

  return (
    <View style={styles.card}>
      <Pressable
        onPress={onToggle}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityState={{ expanded }}
        style={({ pressed }) => [styles.header, pressed && styles.headerPressed]}
      >
        <View style={styles.headerText}>
          <View style={styles.categoryPill}>
            <Text style={styles.categoryText}>{categoryLabel}</Text>
          </View>
          {otherContext ? <Text style={styles.otherContext}>{otherContext}</Text> : null}
          <MetaRow icon="calendar-outline" text={eventDateLabel} />
          <MetaRow
            icon="business-outline"
            text={clinicLabel}
            secondaryText={entry.organizationDisplayName}
          />
        </View>
        <Ionicons
          name={expanded ? 'chevron-up' : 'chevron-down'}
          size={20}
          color={colors.textSecondary}
          style={styles.chevron}
        />
      </Pressable>

      {expanded ? (
        <View style={styles.expandedContent}>
          <View style={styles.divider} />

          {entry.clinicalContent ? (
            <Text style={styles.clinicalContent}>{entry.clinicalContent}</Text>
          ) : null}

          <MetaRow
            icon="checkmark-done-outline"
            text={`${t('clinicalHistory.recordedAtLabel')}: ${formatClinicalInstant(entry.finalizedAt, locale)}`}
          />

          {entry.editedAt !== null ? (
            <MetaRow
              icon="create-outline"
              text={t('clinicalRecord.editedAt', {
                time: formatClinicalInstant(entry.editedAt, locale),
              })}
            />
          ) : null}

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
              authorLabel={null}
            />
          ) : null}

          {changes && showChanges && entry.amendments.length > 0 ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle} accessibilityRole="header">
                {t('clinicalHistory.amendmentsHeading')}
              </Text>
              {entry.amendments.map((amendment) => (
                <View key={amendment.id} style={styles.amendment}>
                  <Text style={styles.amendmentReason}>
                    {t('clinicalHistory.amendmentReasonLabel')}: {amendment.reason}
                  </Text>
                  <Text style={styles.amendmentContent}>{amendment.amendmentContent}</Text>
                  <Text style={styles.metaText}>
                    {formatClinicalInstant(amendment.createdAt, locale)}
                  </Text>
                </View>
              ))}
              {entry.amendmentsTruncated ? (
                <Text style={styles.metaText}>{t('clinicalHistory.amendmentsTruncated')}</Text>
              ) : null}
            </View>
          ) : null}

          {entry.attachments.length > 0 ? (
            <View style={styles.section}>
              <View style={styles.divider} />
              <Text style={styles.sectionTitle} accessibilityRole="header">
                {t('clinicalHistory.attachmentsHeading')}
              </Text>
              {entry.attachments.map((attachment) => (
                <AttachmentRow key={attachment.id} attachment={attachment} />
              ))}
            </View>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

type MetaRowProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  text: string;
  /** Appended after a middle dot, when present (e.g. the Organization name). */
  secondaryText?: string | null;
};

/** Small decorative icon + one line of secondary text. */
function MetaRow({ icon, text, secondaryText }: MetaRowProps) {
  return (
    <View style={styles.metaRow}>
      <Ionicons
        name={icon}
        size={14}
        color={colors.textSecondary}
        style={styles.metaIcon}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.metaText}>{secondaryText ? `${text} · ${secondaryText}` : text}</Text>
    </View>
  );
}

type AttachmentRowProps = {
  attachment: ClinicalAttachment;
};

type AttachmentActionState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error'; messageKey: TranslationKey }
  | { status: 'denied' };

/**
 * Independent per-Attachment open action: fetches a fresh signed URL on every
 * tap (never cached — the fetched URL is a local variable only, never stored
 * in state) and hands it to the already-installed expo-web-browser. Its own
 * isMountedRef guards this row specifically, since attachment rows can
 * outlive an individual open action but the screen/card containing them
 * could unmount mid-request. A technical failure's raw message is mapped
 * through mapClinicalHistoryErrorToKey immediately and never itself stored
 * or rendered — only the resolved localized key.
 */
function AttachmentRow({ attachment }: AttachmentRowProps) {
  const { t } = useLocale();
  const [state, setState] = useState<AttachmentActionState>({ status: 'idle' });
  const isMountedRef = useRef(true);

  const label = resolveAttachmentLabel(
    attachment.originalFilename,
    t('clinicalHistory.attachmentGenericLabel'),
  );

  async function handleOpen() {
    if (state.status === 'loading') return;

    setState({ status: 'loading' });
    const result = await getGuardianClinicalAttachmentDownloadUrl(attachment.id);

    if (!isMountedRef.current) return;

    if (result.error !== null) {
      setState({ status: 'error', messageKey: mapClinicalHistoryErrorToKey(result.error) });
      return;
    }

    if (result.data.status === 'DENIED') {
      setState({ status: 'denied' });
      return;
    }

    setState({ status: 'idle' });
    await WebBrowser.openBrowserAsync(result.data.signedDownloadUrl);
  }

  const errorMessage =
    state.status === 'error'
      ? t(state.messageKey)
      : state.status === 'denied'
        ? t('clinicalHistory.attachmentDenied')
        : null;

  const isLoading = state.status === 'loading';

  return (
    <View style={styles.attachmentBlock}>
      <Pressable
        onPress={handleOpen}
        disabled={isLoading}
        accessibilityRole="button"
        accessibilityLabel={`${t('clinicalHistory.attachmentOpenAction')}: ${label}`}
        accessibilityState={{ disabled: isLoading, busy: isLoading }}
        style={({ pressed }) => [styles.attachmentRow, pressed && styles.attachmentRowPressed]}
      >
        <View
          style={styles.attachmentIcon}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Ionicons name="document-text-outline" size={18} color={colors.primary} />
        </View>
        <View style={styles.attachmentInfo}>
          <Text style={styles.attachmentName} numberOfLines={2}>
            {label}
          </Text>
          <Text style={styles.metaText}>
            {t('clinicalHistory.attachmentSizeKb', {
              count: formatAttachmentSizeKb(attachment.trustedByteSize),
            })}
          </Text>
        </View>
        <View style={styles.attachmentAction}>
          {isLoading ? <ActivityIndicator size="small" color={colors.primary} /> : null}
          <Text style={styles.attachmentActionText}>
            {isLoading
              ? t('clinicalHistory.attachmentOpening')
              : t('clinicalHistory.attachmentOpenAction')}
          </Text>
        </View>
      </Pressable>
      {errorMessage ? <Notice tone="error" message={errorMessage} /> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    minHeight: 44,
    padding: spacing.lg,
  },
  headerPressed: {
    backgroundColor: colors.surfaceSoft,
  },
  headerText: {
    flex: 1,
    gap: spacing.xs,
  },
  // Text label always present — the pill is a quiet grouping cue, never
  // color-only meaning, and deliberately one neutral tone for every category.
  categoryPill: {
    alignSelf: 'flex-start',
    backgroundColor: colors.primarySoft,
    borderRadius: radius.pill,
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    marginBottom: 2,
  },
  categoryText: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primaryDark,
  },
  otherContext: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  chevron: {
    marginTop: 2,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.xs,
  },
  metaIcon: {
    marginTop: 3,
  },
  metaText: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  expandedContent: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.lg,
    gap: spacing.md,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
  },
  clinicalContent: {
    ...typography.body,
    color: colors.textPrimary,
  },
  section: {
    gap: spacing.md,
  },
  changesAction: {
    alignItems: 'flex-start',
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  // Visually subordinate to the Entry itself: a soft inset block, so an
  // amendment never reads as a separate top-level history Entry.
  amendment: {
    gap: spacing.xs,
    backgroundColor: colors.surfaceSoft,
    borderRadius: radius.small,
    borderLeftWidth: 3,
    borderLeftColor: colors.border,
    padding: spacing.md,
  },
  amendmentReason: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  amendmentContent: {
    ...typography.body,
    color: colors.textPrimary,
  },
  attachmentBlock: {
    gap: spacing.sm,
  },
  attachmentRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 56,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.small,
    backgroundColor: colors.surface,
  },
  attachmentRowPressed: {
    backgroundColor: colors.primarySoft,
  },
  attachmentIcon: {
    width: 32,
    height: 32,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  // Takes all remaining width (minWidth 0 lets it actually shrink below its
  // content) so a long filename wraps within its own column.
  attachmentInfo: {
    flex: 1,
    minWidth: 0,
    gap: 2,
  },
  attachmentName: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  // Natural width, never squeezed by the filename.
  attachmentAction: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    flexShrink: 0,
  },
  attachmentActionText: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primary,
  },
});

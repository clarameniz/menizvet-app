import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps, ReactElement } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';

import { AppointmentStatusBadge } from '@/components/design-system/appointment-status-badge';
import {
  EmptyListMessage,
  FramedRow,
  LoadMoreFooter,
  PagedListStatus,
  pagedListStyles,
} from '@/components/paged-list-parts';
import type { PagedList } from '@/hooks/use-paged-list';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { lifecycleLabelKey } from '@/lib/appointment-lifecycle';
import {
  appointmentLocalDate,
  compactAppointmentDate,
  compactAppointmentTimes,
  formatDayHeading,
} from '@/lib/clinic-calendar';
import {
  guardianAppointmentRowLabel,
  guardianAppointmentRowTags,
  type GuardianAppointmentListItem,
  type GuardianAppointmentRowTag,
} from '@/lib/guardian-appointments';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** What differs between the Active and History tabs: only their wording. */
export type GuardianAppointmentListCopy = {
  loadingKey: TranslationKey;
  errorKey: TranslationKey;
  emptyKey: TranslationKey;
  emptyIcon: ComponentProps<typeof Ionicons>['name'];
};

/**
 * One tab of "My appointments" (SPEC-APT-011 BR-40): ONE virtualized list of
 * compact rows framed as a single card, read page by page, with the shared
 * first-page status, "Load more" footer and empty message of the agenda and
 * Staff lists. Both tabs use the same row.
 */
export function GuardianAppointmentList({
  header,
  list,
  copy,
  onOpen,
}: {
  /** The screen's shared header (title and tabs), rendered at the top of the list. */
  header: ReactElement;
  list: PagedList<GuardianAppointmentListItem, unknown>;
  copy: GuardianAppointmentListCopy;
  onOpen: (row: GuardianAppointmentListItem) => void;
}) {
  const { t } = useLocale();
  const { state } = list;
  const rows = state.rows ?? [];

  return (
    <FlatList
      data={rows}
      keyExtractor={(row) => row.id}
      contentContainerStyle={pagedListStyles.content}
      showsVerticalScrollIndicator={false}
      ListHeaderComponent={
        <View style={pagedListStyles.headerBlock}>
          {header}
          <PagedListStatus list={list} loadingKey={copy.loadingKey} errorKey={copy.errorKey} />
        </View>
      }
      renderItem={({ item, index }) => (
        <FramedRow first={index === 0} last={index === rows.length - 1}>
          <GuardianAppointmentRow row={item} onOpen={() => onOpen(item)} />
        </FramedRow>
      )}
      ListEmptyComponent={
        state.rows !== null && state.rows.length === 0 ? (
          <EmptyListMessage icon={copy.emptyIcon} message={t(copy.emptyKey)} />
        ) : null
      }
      ListFooterComponent={<LoadMoreFooter list={list} />}
    />
  );
}

/**
 * Pet, Clinic, start time over a short date in the timezone the interval was
 * established in (never the device's), the real lifecycle state as the shared
 * badge, and the secondary tags of BR-40: a due answer to a Clinic proposal
 * and/or a request awaiting the Clinic's confirmation of an accepted
 * alternative. The whole row is ONE button that opens the Appointment detail, where every action
 * lives. Long names are truncated; the accessible name carries everything.
 */
function GuardianAppointmentRow({
  row,
  onOpen,
}: {
  row: GuardianAppointmentListItem;
  onOpen: () => void;
}) {
  const { t, locale } = useLocale();
  const times = compactAppointmentTimes(row, locale);
  const clinicLabel = row.clinicDisplayName ?? t('appointments.clinicUnavailable');
  const lifecycleLabel = t(lifecycleLabelKey(row.lifecycleState));
  const tags = guardianAppointmentRowTags(row);

  return (
    <Pressable
      onPress={onOpen}
      accessibilityRole="button"
      accessibilityLabel={guardianAppointmentRowLabel({
        fullDate: formatDayHeading(appointmentLocalDate(row), locale),
        time: times.start,
        petName: row.petName,
        clinicLabel,
        lifecycleLabel,
        tagLabels: tags.map((tag) => t(tag.labelKey)),
      })}
      accessibilityHint={t('clinicSchedule.openDetailHint')}
      style={({ pressed }) => [styles.row, pressed && styles.pressed]}
    >
      <View style={styles.dateColumn}>
        <Text style={styles.startTime}>{times.start}</Text>
        <Text style={styles.date} numberOfLines={1}>
          {compactAppointmentDate(row, locale)}
        </Text>
      </View>

      <View style={styles.content}>
        <Text style={styles.petName} numberOfLines={1}>
          {row.petName}
        </Text>
        <Text style={styles.clinic} numberOfLines={1}>
          {clinicLabel}
        </Text>
        <View style={styles.tags}>
          <AppointmentStatusBadge state={row.lifecycleState} />
          {tags.map((tag) => (
            <RowTag key={tag.kind} tag={tag} />
          ))}
        </View>
      </View>

      <Ionicons
        name="chevron-forward"
        size={18}
        color={colors.textMuted}
        style={styles.chevron}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
    </Pressable>
  );
}

/**
 * A secondary tag: an icon AND text, never color alone. A due answer to a
 * Clinic proposal is highlighted; waiting for the Clinic, which asks nothing
 * of the Guardian, stays neutral with its own icon.
 */
function RowTag({ tag }: { tag: GuardianAppointmentRowTag }) {
  const { t } = useLocale();
  const isProposal = tag.kind === 'proposal';
  return (
    <View style={[styles.tag, isProposal ? styles.proposalTag : styles.awaitingTag]}>
      <Ionicons
        name={isProposal ? 'swap-horizontal-outline' : 'hourglass-outline'}
        size={13}
        color={isProposal ? colors.warning : colors.textSecondary}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.tagText} numberOfLines={1}>
        {t(tag.labelKey)}
      </Text>
    </View>
  );
}

// Same measures as the agenda's list row (clinic-calendar-appointment-row.tsx).
const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    minHeight: 44,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    backgroundColor: colors.surface,
  },
  pressed: {
    backgroundColor: colors.surfaceSoft,
  },
  // Sized by its content ("15 oct 2025", "10:00 AM"), never truncating it.
  dateColumn: {
    minWidth: 56,
    flexShrink: 0,
    paddingTop: 2,
  },
  startTime: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  date: {
    ...typography.caption,
    fontSize: 13,
    lineHeight: 18,
    color: colors.textMuted,
  },
  content: {
    flex: 1,
    gap: 2,
  },
  petName: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  clinic: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  tags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs,
    marginTop: spacing.xs,
  },
  tag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingVertical: 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.pill,
    maxWidth: '100%',
  },
  proposalTag: {
    backgroundColor: colors.warningSoft,
  },
  awaitingTag: {
    backgroundColor: colors.surfaceSoft,
  },
  tagText: {
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '600',
    color: colors.textPrimary,
    flexShrink: 1,
  },
  chevron: {
    alignSelf: 'center',
  },
});

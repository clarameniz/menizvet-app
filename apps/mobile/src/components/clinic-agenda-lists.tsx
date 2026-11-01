import { Ionicons } from '@expo/vector-icons';
import type { ReactElement } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';

import { ClinicCalendarAppointmentRow } from '@/components/clinic-calendar-appointment-row';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { ClinicPendingAppointment, PendingTotals } from '@/data/clinic-calendar';
import {
  EmptyListMessage,
  FramedRow,
  LoadMoreFooter,
  PagedListStatus,
  pagedListStyles,
} from '@/components/paged-list-parts';
import type { PagedList } from '@/hooks/use-paged-list';
import { useLocale } from '@/i18n/locale-provider';
import {
  PENDING_CATEGORY_PRESENTATION,
  PENDING_REASON_PRESENTATION,
  PENDING_SUMMARY_ORDER,
  pendingListItems,
  type PendingListItem,
} from '@/lib/clinic-agenda';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ListViewProps<TRow, TMeta> = {
  /** The agenda's shared header (title, Clinic, tabs), rendered at the top of this list. */
  header: ReactElement;
  list: PagedList<TRow, TMeta>;
  clinicTimezoneName: string | null;
  onOpen: (appointmentId: string) => void;
};

/**
 * The agenda's Pending view (SPEC-APT-012 BR-57): the whole classification's
 * totals per category, then ONE virtualized list of compact rows in the
 * backend's order, with a heading before each category. Only the first
 * category is presented as work; "Awaiting the guardian" and "For information"
 * are explained as such. Rows open the Appointment detail; nothing else here
 * is actionable except loading more and retrying.
 */
export function ClinicPendingList({
  header,
  list,
  clinicTimezoneName,
  onOpen,
}: ListViewProps<ClinicPendingAppointment, PendingTotals>) {
  const { t } = useLocale();
  const { state } = list;
  const items =
    state.rows !== null && state.meta !== null ? pendingListItems(state.rows, state.meta) : [];

  return (
    <FlatList
      data={items}
      keyExtractor={(item) =>
        item.kind === 'category' ? `category:${item.category}` : `row:${item.row.appointment.id}`
      }
      contentContainerStyle={pagedListStyles.content}
      showsVerticalScrollIndicator={false}
      ListHeaderComponent={
        <View style={pagedListStyles.headerBlock}>
          {header}
          <PagedListStatus
            list={list}
            loadingKey="clinicAgenda.pendingLoading"
            errorKey="clinicAgenda.pendingError"
          />
          {state.rows !== null && state.meta !== null ? (
            <PendingSummary totals={state.meta} />
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <PendingListEntry item={item} clinicTimezoneName={clinicTimezoneName} onOpen={onOpen} />
      )}
      ListEmptyComponent={
        state.rows !== null && state.rows.length === 0 ? (
          <EmptyListMessage
            icon="checkmark-done-outline"
            message={t('clinicAgenda.pendingEmpty')}
          />
        ) : null
      }
      ListFooterComponent={<LoadMoreFooter list={list} />}
    />
  );
}

/**
 * The agenda's History view (SPEC-APT-012 BR-59): terminal Appointments,
 * newest first, as ONE virtualized list of compact rows; more pages on demand.
 */
export function ClinicHistoryList({
  header,
  list,
  clinicTimezoneName,
  onOpen,
}: ListViewProps<ClinicScheduleAppointment, never>) {
  const { t } = useLocale();
  const { state } = list;
  const rows = state.rows ?? [];

  return (
    <FlatList
      data={rows}
      keyExtractor={(appointment) => appointment.id}
      contentContainerStyle={pagedListStyles.content}
      showsVerticalScrollIndicator={false}
      ListHeaderComponent={
        <View style={pagedListStyles.headerBlock}>
          {header}
          <PagedListStatus
            list={list}
            loadingKey="clinicAgenda.historyLoading"
            errorKey="clinicAgenda.historyError"
          />
        </View>
      }
      renderItem={({ item, index }) => (
        <FramedRow first={index === 0} last={index === rows.length - 1}>
          <ClinicCalendarAppointmentRow
            appointment={item}
            clinicTimezoneName={clinicTimezoneName}
            layout="list"
            onOpen={() => onOpen(item.id)}
          />
        </FramedRow>
      )}
      ListEmptyComponent={
        state.rows !== null && state.rows.length === 0 ? (
          <EmptyListMessage icon="time-outline" message={t('clinicAgenda.historyEmpty')} />
        ) : null
      }
      ListFooterComponent={<LoadMoreFooter list={list} />}
    />
  );
}

function PendingListEntry({
  item,
  clinicTimezoneName,
  onOpen,
}: {
  item: PendingListItem;
  clinicTimezoneName: string | null;
  onOpen: (appointmentId: string) => void;
}) {
  const { t } = useLocale();
  if (item.kind === 'category') {
    const presentation = PENDING_CATEGORY_PRESENTATION[item.category];
    const title = t(presentation.titleKey);
    const count =
      item.loaded < item.total
        ? t('clinicAgenda.categoryShownOfTotal', { shown: item.loaded, total: item.total })
        : String(item.total);
    return (
      <View
        style={styles.category}
        accessible
        accessibilityRole="header"
        accessibilityLabel={`${title}, ${count}`}
      >
        <View style={styles.categoryRow}>
          <Ionicons
            name={presentation.icon}
            size={16}
            color={item.category === 'ACTION_REQUIRED' ? colors.warning : colors.textSecondary}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          />
          <Text style={styles.categoryTitle}>{title}</Text>
          <Text style={styles.categoryCount}>{count}</Text>
        </View>
        {presentation.noteKey !== null ? (
          <Text style={styles.categoryNote}>{t(presentation.noteKey)}</Text>
        ) : null}
      </View>
    );
  }

  const { row } = item;
  const reason = PENDING_REASON_PRESENTATION[row.reason];
  return (
    <FramedRow first={item.first} last={item.last}>
      <ClinicCalendarAppointmentRow
        appointment={row.appointment}
        clinicTimezoneName={clinicTimezoneName}
        layout="list"
        note={{
          icon: reason.icon,
          iconColor: row.category === 'ACTION_REQUIRED' ? colors.warning : colors.textSecondary,
          text: t(reason.shortKey),
          accessibilityText: t(reason.labelKey),
        }}
        onOpen={() => onOpen(row.appointment.id)}
      />
    </FramedRow>
  );
}

/** The whole classification's totals: the main figure, then the two secondary ones. */
function PendingSummary({ totals }: { totals: PendingTotals }) {
  const { t } = useLocale();
  return (
    <View style={styles.summary}>
      {PENDING_SUMMARY_ORDER.map((category) => {
        const presentation = PENDING_CATEGORY_PRESENTATION[category];
        const main = category === 'ACTION_REQUIRED';
        return (
          <View
            key={category}
            style={styles.summaryItem}
            accessible
            accessibilityLabel={`${t(presentation.titleKey)}: ${totals[category]}`}
          >
            <Text style={[styles.summaryCount, !main && styles.summaryCountSecondary]}>
              {totals[category]}
            </Text>
            <Text style={styles.summaryLabel}>{t(presentation.titleKey)}</Text>
          </View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  summary: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  summaryItem: {
    flex: 1,
    gap: 2,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radius.small,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  summaryCount: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  summaryCountSecondary: {
    color: colors.textSecondary,
  },
  summaryLabel: {
    ...typography.caption,
    fontSize: 12,
    lineHeight: 16,
    color: colors.textSecondary,
  },
  category: {
    gap: 2,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  categoryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  categoryTitle: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
    flexShrink: 1,
  },
  categoryCount: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  categoryNote: {
    ...typography.caption,
    fontSize: 12,
    lineHeight: 16,
    color: colors.textSecondary,
  },
});

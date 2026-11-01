import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ClinicAgendaTabs, type ClinicAgendaTab } from '@/components/clinic-agenda-tabs';
import { ClinicHistoryList, ClinicPendingList } from '@/components/clinic-agenda-lists';
import { ClinicCalendarAppointmentRow } from '@/components/clinic-calendar-appointment-row';
import { ClinicCalendarMonth } from '@/components/clinic-calendar-month';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { StateMessage } from '@/components/design-system/state-message';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import {
  useClinicAppointmentHistory,
  useClinicPendingAppointments,
} from '@/hooks/use-clinic-appointment-pages';
import {
  useClinicCalendar,
  type CachedRead,
  type ClinicCalendarScreenState,
} from '@/hooks/use-clinic-calendar';
import { useLocale } from '@/i18n/locale-provider';
import { formatDayHeading } from '@/lib/clinic-calendar';
import { professionalAppointmentDetailHref } from '@/lib/clinic-schedule-display';
import { goBackOr } from '@/lib/navigation';
import { professionalClinicLabel } from '@/lib/professional-clinics-display';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * The Clinic's "Agenda de citas" (SPEC-APT-012 §14): three tabs under one
 * header — Calendar (the initial one), Pending and History — each with its
 * own reads and its own state, kept while another tab is shown.
 *
 * - Calendar: a month grid with each date's calendar Appointment count
 *   (BR-54) and the selected date's Appointments as compact rows (BR-56). The
 *   Clinic's local today comes only from the calendar context (BR-60): with
 *   it, the calendar opens on that month with today selected and offers
 *   "Today"; without it, it opens on the device's month provisionally, marks
 *   no day as today, selects nothing, and says why.
 * - Pending: the Appointments the backend classifies as pending for this
 *   actor (BR-57), by category, with the whole classification's totals.
 * - History: terminal Appointments, newest first (BR-59).
 *
 * Pending and History are read only once shown, page by page ("Load more").
 * A focus (e.g. back from the Appointment detail) refreshes only the tab on
 * screen; the others refresh when shown again. The calendar's checks (the
 * Clinic is still offered, the schedule still readable) gate the tabs: until
 * they pass, or once access is lost from any tab, only the calendar's state
 * is shown and only the calendar reads. It never reads the whole schedule.
 * Read-only: every row opens the professional Appointment detail, the single
 * action surface.
 */
export default function ClinicCalendarScreen() {
  const { t } = useLocale();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const [tab, setTab] = useState<ClinicAgendaTab>('calendar');
  const calendar = useClinicCalendar(clinicId, tab === 'calendar');
  const { screen, selectedDate, dayAppointments } = calendar;
  // Until the calendar's checks pass, or once access is lost, only its state shows.
  const activeTab: ClinicAgendaTab = screen.kind === 'ready' ? tab : 'calendar';
  const pending = useClinicPendingAppointments(
    clinicId,
    activeTab === 'pending',
    calendar.loseAccess,
  );
  const history = useClinicAppointmentHistory(
    clinicId,
    activeTab === 'history',
    calendar.loseAccess,
  );

  const goBack = () =>
    goBackOr({ pathname: '/professional/clinics/[clinicId]', params: { clinicId } });
  const backToClinics = () => router.dismissTo('/professional/clinics');
  const openAppointment = (appointmentId: string) =>
    router.push(professionalAppointmentDetailHref(clinicId, appointmentId));

  const clinic = clinicOf(screen);
  const rows =
    screen.kind === 'ready' && selectedDate !== null ? (dayAppointments?.data ?? []) : [];
  const clinicTimezoneName = screen.kind === 'ready' ? screen.context.schedulingTimezoneName : null;

  const header = (
    <View style={styles.headerBlock}>
      <AppTopBar onBack={goBack} />
      <View style={styles.titleBlock}>
        <Text style={styles.title} accessibilityRole="header">
          {t('clinicSchedule.title')}
        </Text>
        {clinic !== null ? <ClinicName clinic={clinic} /> : null}
      </View>
      {screen.kind === 'ready' ? <ClinicAgendaTabs selected={activeTab} onSelect={setTab} /> : null}
    </View>
  );

  if (activeTab === 'pending') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <ClinicPendingList
          header={header}
          list={pending}
          clinicTimezoneName={clinicTimezoneName}
          onOpen={openAppointment}
        />
      </SafeAreaView>
    );
  }
  if (activeTab === 'history') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <ClinicHistoryList
          header={header}
          list={history}
          clinicTimezoneName={clinicTimezoneName}
          onOpen={openAppointment}
        />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <FlatList
        data={rows}
        keyExtractor={(appointment) => appointment.id}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        ListHeaderComponent={
          <View style={styles.headerBlock}>
            {header}

            {screen.kind === 'loading' ? (
              <StateMessage tone="loading" message={t('clinicCalendar.loading')} />
            ) : screen.kind === 'error' ? (
              <View style={styles.stateBlock}>
                <StateMessage tone="error" message={t(screen.messageKey)} />
                <Button label={t('professional.retry')} onPress={calendar.retryScreen} />
                <Button variant="secondary" label={t('common.back')} onPress={goBack} />
              </View>
            ) : screen.kind === 'ready' ? (
              <>
                {calendar.visibleMonth !== null ? (
                  <ClinicCalendarMonth
                    visibleMonth={calendar.visibleMonth}
                    todayDate={screen.context.clinicLocalToday}
                    selectedDate={selectedDate}
                    monthCounts={calendar.monthCounts}
                    onSelectDate={calendar.selectDate}
                    onShowMonth={calendar.showMonth}
                    onShowToday={calendar.showToday}
                    onRetryCounts={calendar.retryMonth}
                  />
                ) : null}
                <DayHeading
                  selectedDate={selectedDate}
                  todayDate={screen.context.clinicLocalToday}
                  dayAppointments={dayAppointments}
                  onRetry={calendar.retryDay}
                />
              </>
            ) : (
              <View style={styles.stateBlock}>
                <StateMessage
                  tone="empty"
                  icon="calendar-outline"
                  message={t(
                    screen.kind === 'clinicUnavailable'
                      ? 'professionalClinic.notAvailable'
                      : screen.kind === 'scheduleUnavailable'
                        ? 'clinicSchedule.unavailable'
                        : 'clinicSchedule.accessError',
                  )}
                />
                <Button
                  variant="secondary"
                  label={t('professionalClinic.backToClinics')}
                  onPress={backToClinics}
                />
              </View>
            )}
          </View>
        }
        renderItem={({ item, index }) => (
          <View
            style={[
              styles.rowFrame,
              index === 0 && styles.rowFrameFirst,
              index === rows.length - 1 && styles.rowFrameLast,
            ]}
          >
            {index > 0 ? <View style={styles.separator} /> : null}
            <ClinicCalendarAppointmentRow
              appointment={item}
              clinicTimezoneName={clinicTimezoneName}
              onOpen={() => openAppointment(item.id)}
            />
          </View>
        )}
        ListEmptyComponent={
          screen.kind === 'ready' ? (
            <DayEmptyState
              selectedDate={selectedDate}
              hasClinicToday={screen.context.clinicLocalToday !== null}
              dayAppointments={dayAppointments}
              onRetry={calendar.retryDay}
            />
          ) : null
        }
      />
    </SafeAreaView>
  );
}

function clinicOf(screen: ClinicCalendarScreenState): ProfessionalClinic | null {
  return screen.kind === 'ready' ||
    screen.kind === 'scheduleUnavailable' ||
    screen.kind === 'accessLost'
    ? screen.clinic
    : null;
}

/** Clinic name (or the unnamed fallback) with its Organization, visually secondary. */
function ClinicName({ clinic }: { clinic: ProfessionalClinic }) {
  const { t } = useLocale();
  return (
    <View style={styles.clinicContext}>
      <Text
        style={[styles.clinicName, clinic.clinicDisplayName === null && styles.unnamed]}
        numberOfLines={2}
      >
        {professionalClinicLabel(clinic, t('professional.unnamedClinic'))}
      </Text>
      <Text style={styles.organizationName} numberOfLines={1}>
        {clinic.organizationDisplayName}
      </Text>
    </View>
  );
}

/** The selected date as a heading, "Today" when it is the Clinic's today, and a refresh failure. */
function DayHeading({
  selectedDate,
  todayDate,
  dayAppointments,
  onRetry,
}: {
  selectedDate: string | null;
  todayDate: string | null;
  dayAppointments: CachedRead<ClinicScheduleAppointment[]> | null;
  onRetry: () => void;
}) {
  const { t, locale } = useLocale();
  if (selectedDate === null) return null;
  const isToday = selectedDate === todayDate;
  const loaded = dayAppointments?.data ?? null;

  return (
    <View style={styles.dayHeading}>
      <View style={styles.dayHeadingRow}>
        <Text style={styles.dayTitle} accessibilityRole="header">
          {formatDayHeading(selectedDate, locale)}
        </Text>
        {isToday ? (
          <View style={styles.todayBadge}>
            <Text style={styles.todayBadgeText}>{t('clinicCalendar.todayAction')}</Text>
          </View>
        ) : null}
      </View>
      {loaded !== null && loaded.length > 0 ? (
        <Text style={styles.dayCount}>
          {t(
            loaded.length === 1
              ? 'clinicCalendar.appointmentCountOne'
              : 'clinicCalendar.appointmentCountOther',
            { count: loaded.length },
          )}
        </Text>
      ) : null}
      {loaded !== null && dayAppointments?.status === 'error' ? (
        <View style={styles.inlineError}>
          <Text style={styles.inlineErrorText}>{t('clinicCalendar.dayStale')}</Text>
          <Pressable onPress={onRetry} accessibilityRole="button" hitSlop={8}>
            <Text style={styles.retryText}>{t('professional.retry')}</Text>
          </Pressable>
        </View>
      ) : null}
    </View>
  );
}

/** No row to show: nothing selected, loading, failed before any data, or an empty day. */
function DayEmptyState({
  selectedDate,
  hasClinicToday,
  dayAppointments,
  onRetry,
}: {
  selectedDate: string | null;
  hasClinicToday: boolean;
  dayAppointments: CachedRead<ClinicScheduleAppointment[]> | null;
  onRetry: () => void;
}) {
  const { t } = useLocale();
  if (selectedDate === null) {
    return (
      <Text style={styles.mutedText}>
        {t(hasClinicToday ? 'clinicCalendar.selectDayPrompt' : 'clinicCalendar.noTimezoneNotice')}
      </Text>
    );
  }
  if (
    dayAppointments === null ||
    (dayAppointments.data === null && dayAppointments.status !== 'error')
  ) {
    return (
      <View style={styles.dayStatus}>
        <ActivityIndicator size="small" color={colors.primary} />
        <Text style={styles.mutedText}>{t('clinicCalendar.dayLoading')}</Text>
      </View>
    );
  }
  if (dayAppointments.data === null) {
    return (
      <View style={styles.dayStatus}>
        <Text style={styles.errorText}>
          {t(
            dayAppointments.errorKey === 'errors.sessionExpired'
              ? 'errors.sessionExpired'
              : 'clinicCalendar.dayError',
          )}
        </Text>
        <Pressable onPress={onRetry} accessibilityRole="button" hitSlop={8}>
          <Text style={styles.retryText}>{t('professional.retry')}</Text>
        </Pressable>
      </View>
    );
  }
  return (
    <View style={styles.emptyDay}>
      <Ionicons
        name="calendar-clear-outline"
        size={20}
        color={colors.textMuted}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.mutedText}>{t('clinicCalendar.dayEmpty')}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flexGrow: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
  },
  headerBlock: {
    gap: spacing.lg,
    paddingBottom: spacing.md,
  },
  titleBlock: {
    gap: spacing.xs,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  clinicContext: {
    gap: 2,
  },
  clinicName: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  unnamed: {
    fontStyle: 'italic',
  },
  organizationName: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  stateBlock: {
    gap: spacing.md,
  },
  dayHeading: {
    gap: 2,
    paddingTop: spacing.xs,
  },
  dayHeadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  dayTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  todayBadge: {
    paddingVertical: 1,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
  },
  todayBadgeText: {
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '700',
    color: colors.primaryDark,
  },
  dayCount: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  inlineError: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  inlineErrorText: {
    ...typography.caption,
    color: colors.errorDark,
    flexShrink: 1,
  },
  rowFrame: {
    borderLeftWidth: 1,
    borderRightWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  rowFrameFirst: {
    borderTopWidth: 1,
    borderTopLeftRadius: radius.medium,
    borderTopRightRadius: radius.medium,
  },
  rowFrameLast: {
    borderBottomWidth: 1,
    borderBottomLeftRadius: radius.medium,
    borderBottomRightRadius: radius.medium,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginHorizontal: spacing.lg,
  },
  dayStatus: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.md,
  },
  emptyDay: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.md,
  },
  mutedText: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  errorText: {
    ...typography.caption,
    color: colors.errorDark,
    flexShrink: 1,
  },
  retryText: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primaryDark,
  },
});

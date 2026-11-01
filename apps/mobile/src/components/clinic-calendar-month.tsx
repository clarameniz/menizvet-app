import { Ionicons } from '@expo/vector-icons';
import { createContext, useCallback, useContext, useMemo } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
// Only the month grid: importing the package root would also load Agenda,
// Timeline and their list dependencies, which this screen never uses.
import Calendar from 'react-native-calendars/src/calendar';
import type { DayProps } from 'react-native-calendars/src/calendar/day';
import type { DateData } from 'react-native-calendars/src/types';

import type { ClinicMonthCounts } from '@/data/clinic-calendar';
import type { CachedRead } from '@/hooks/use-clinic-calendar';
import { useLocale } from '@/i18n/locale-provider';
import {
  firstDateOfMonth,
  formatDayHeading,
  formatMonthTitle,
  isDateInMonth,
  isSupportedMonth,
  monthKey,
  mondayFirstWeekdays,
  shiftMonth,
  type CalendarMonth,
} from '@/lib/clinic-calendar';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * The month grid of the professional appointment calendar (SPEC-APT-012 §14).
 *
 * `react-native-calendars` lays out the Monday-first month (4, 5 or 6 week
 * rows, no other months' days); everything it would otherwise decide is ours:
 * the month header, the localized weekday row, and each day cell. Each cell
 * reads the Clinic's "today" (BR-60), the selection and the month's counts
 * (BR-54) from context — never the library's own "today" (the device date),
 * its selection state, or its English accessibility labels. The grid is
 * remounted per month, so the library never changes month on its own nor
 * announces one.
 */

type DayGridState = {
  counts: ClinicMonthCounts | null;
  selectedDate: string | null;
  todayDate: string | null;
  onSelectDate: (date: string) => void;
};

const DayGridContext = createContext<DayGridState | null>(null);

const CALENDAR_THEME = {
  calendarBackground: 'transparent',
  weekVerticalMargin: 2,
  'stylesheet.calendar.main': {
    container: { paddingLeft: 0, paddingRight: 0, backgroundColor: 'transparent' },
  },
};

export function ClinicCalendarMonth({
  visibleMonth,
  todayDate,
  selectedDate,
  monthCounts,
  onSelectDate,
  onShowMonth,
  onShowToday,
  onRetryCounts,
}: {
  visibleMonth: CalendarMonth;
  /** The Clinic's local today (BR-60), or `null`: then no day is "today". */
  todayDate: string | null;
  selectedDate: string | null;
  monthCounts: CachedRead<ClinicMonthCounts> | null;
  onSelectDate: (date: string) => void;
  onShowMonth: (month: CalendarMonth) => void;
  onShowToday: () => void;
  onRetryCounts: () => void;
}) {
  const { t, locale } = useLocale();
  const previous = shiftMonth(visibleMonth, -1);
  const next = shiftMonth(visibleMonth, 1);
  const title = formatMonthTitle(visibleMonth, locale);
  const counts = monthCounts?.data ?? null;

  const gridState = useMemo<DayGridState>(
    () => ({ counts, selectedDate, todayDate, onSelectDate }),
    [counts, selectedDate, todayDate, onSelectDate],
  );
  const handleDayPress = useCallback(
    (date: DateData) => onSelectDate(date.dateString),
    [onSelectDate],
  );

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title} accessibilityRole="header" accessibilityLiveRegion="polite">
          {title}
        </Text>
        <View style={styles.headerActions}>
          {todayDate !== null ? (
            <Pressable
              onPress={onShowToday}
              accessibilityRole="button"
              accessibilityLabel={t('clinicCalendar.todayAction')}
              accessibilityHint={t('clinicCalendar.todayHint')}
              hitSlop={6}
              style={({ pressed }) => [styles.todayButton, pressed && styles.pressed]}
            >
              <Text style={styles.todayButtonText}>{t('clinicCalendar.todayAction')}</Text>
            </Pressable>
          ) : null}
          <MonthArrow
            icon="chevron-back"
            label={t('clinicCalendar.previousMonth')}
            disabled={!isSupportedMonth(previous)}
            onPress={() => onShowMonth(previous)}
          />
          <MonthArrow
            icon="chevron-forward"
            label={t('clinicCalendar.nextMonth')}
            disabled={!isSupportedMonth(next)}
            onPress={() => onShowMonth(next)}
          />
        </View>
      </View>

      <View style={styles.card}>
        <DayGridContext.Provider value={gridState}>
          <Calendar
            key={monthKey(visibleMonth)}
            current={firstDateOfMonth(visibleMonth)}
            firstDay={1}
            hideExtraDays
            disableMonthChange
            customHeader={WeekdayRow}
            dayComponent={CalendarDayCell}
            onDayPress={handleDayPress}
            theme={CALENDAR_THEME}
          />
        </DayGridContext.Provider>
      </View>

      <MonthStatus visibleMonth={visibleMonth} monthCounts={monthCounts} onRetry={onRetryCounts} />
    </View>
  );
}

function MonthArrow({
  icon,
  label,
  disabled,
  onPress,
}: {
  icon: 'chevron-back' | 'chevron-forward';
  label: string;
  disabled: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled }}
      hitSlop={6}
      style={({ pressed }) => [
        styles.arrow,
        pressed && styles.pressed,
        disabled && styles.disabled,
      ]}
    >
      <Ionicons
        name={icon}
        size={22}
        color={colors.textPrimary}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
    </Pressable>
  );
}

/** The localized Monday-first weekday row (the library's `customHeader`). */
function WeekdayRow() {
  const { locale } = useLocale();
  const weekdays = useMemo(() => mondayFirstWeekdays(locale), [locale]);
  return (
    <View
      style={styles.weekdayRow}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      {weekdays.map((weekday) => (
        <Text key={weekday.long} style={styles.weekdayText} numberOfLines={1}>
          {weekday.short}
        </Text>
      ))}
    </View>
  );
}

/**
 * One date of the visible month: its number in ONE circle, and a discreet
 * count when it has calendar Appointments. The selected day — today or any
 * other — is a solid circle without border; today, when not selected, is an
 * outlined circle; any other day is just its number. Selection always wins,
 * so there is never a second ring. The count keeps its own light pill below,
 * separated from the circle, selected or not. One button whose name says the
 * full date, "today", and the count — or nothing about the count while the
 * month is not loaded.
 */
function CalendarDayCell({ date, onPress }: DayProps & { date?: DateData }) {
  const { t, locale } = useLocale();
  const grid = useContext(DayGridContext);
  if (date === undefined || grid === null) return <View style={styles.dayCell} />;

  const dateString = date.dateString;
  const isToday = dateString === grid.todayDate;
  const isSelected = dateString === grid.selectedDate;
  const look: DayLook = isSelected ? 'selected' : isToday ? 'today' : 'plain';
  const count = grid.counts === null ? null : (grid.counts[dateString] ?? 0);

  const label = [
    formatDayHeading(dateString, locale),
    isToday ? t('clinicCalendar.today') : null,
    count === null
      ? null
      : count === 0
        ? t('clinicCalendar.dayNoAppointments')
        : t(
            count === 1
              ? 'clinicCalendar.appointmentCountOne'
              : 'clinicCalendar.appointmentCountOther',
            {
              count,
            },
          ),
  ]
    .filter(Boolean)
    .join(', ');

  return (
    <Pressable
      onPress={() => (onPress ? onPress(date) : grid.onSelectDate(dateString))}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected: isSelected }}
      testID={`calendar-day-${dateString}`}
      style={({ pressed }) => [styles.dayCell, pressed && styles.pressed]}
    >
      {/* The whole circle is remounted per state, and every state sets every
          property explicitly: Android kept today's teal number on the teal
          circle when today was selected again, updating the views in place. */}
      <View
        key={look}
        testID={`calendar-day-circle-${dateString}`}
        style={[styles.dayNumber, CIRCLE_STYLES[look]]}
      >
        <Text style={[styles.dayNumberText, NUMBER_STYLES[look]]} maxFontSizeMultiplier={1.3}>
          {date.day}
        </Text>
      </View>
      {count !== null && count > 0 ? (
        <View style={styles.countPill}>
          <Text style={styles.countText} maxFontSizeMultiplier={1.3}>
            {count}
          </Text>
        </View>
      ) : (
        <View style={styles.countSpacer} />
      )}
    </Pressable>
  );
}

/** Loading, failed, empty, or the month's total — a loaded empty month is never shown as loading. */
function MonthStatus({
  visibleMonth,
  monthCounts,
  onRetry,
}: {
  visibleMonth: CalendarMonth;
  monthCounts: CachedRead<ClinicMonthCounts> | null;
  onRetry: () => void;
}) {
  const { t } = useLocale();
  if (monthCounts === null || (monthCounts.data === null && monthCounts.status === 'loading')) {
    return (
      <View style={styles.statusRow}>
        <ActivityIndicator size="small" color={colors.primary} />
        <Text style={styles.statusText}>{t('clinicCalendar.monthLoading')}</Text>
      </View>
    );
  }
  if (monthCounts.status === 'error') {
    return (
      <View style={styles.statusRow}>
        <Text style={styles.statusErrorText}>
          {t(
            monthCounts.errorKey === 'errors.sessionExpired'
              ? 'errors.sessionExpired'
              : monthCounts.data === null
                ? 'clinicCalendar.monthError'
                : 'clinicCalendar.monthStale',
          )}
        </Text>
        <Pressable onPress={onRetry} accessibilityRole="button" hitSlop={8}>
          <Text style={styles.retryText}>{t('professional.retry')}</Text>
        </Pressable>
      </View>
    );
  }
  if (monthCounts.data === null) return null;
  const total = Object.entries(monthCounts.data)
    .filter(([date]) => isDateInMonth(date, visibleMonth))
    .reduce((sum, [, count]) => sum + count, 0);
  return (
    <View style={styles.statusRow}>
      <Text style={styles.statusText}>
        {total === 0
          ? t('clinicCalendar.monthEmpty')
          : t(total === 1 ? 'clinicCalendar.monthTotalOne' : 'clinicCalendar.monthTotalOther', {
              count: total,
            })}
      </Text>
    </View>
  );
}

const DAY_NUMBER_SIZE = 34;

/** The day's look: selection always wins over today, so there is one circle at most. */
type DayLook = 'plain' | 'today' | 'selected';

const styles = StyleSheet.create({
  container: {
    gap: spacing.sm,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.sm,
  },
  title: {
    ...typography.h3,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  todayButton: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.md,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  todayButtonText: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primaryDark,
  },
  arrow: {
    width: 40,
    height: 40,
    borderRadius: radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pressed: {
    opacity: 0.6,
  },
  disabled: {
    opacity: 0.3,
  },
  card: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
  },
  weekdayRow: {
    flexDirection: 'row',
    paddingBottom: spacing.xs,
  },
  weekdayText: {
    flex: 1,
    textAlign: 'center',
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '600',
    color: colors.textMuted,
  },
  dayCell: {
    width: '100%',
    minHeight: 56,
    alignItems: 'center',
    paddingTop: 2,
    // Keeps the count's pill visibly apart from the day's circle.
    gap: 4,
  },
  // One fixed square box with half-side radius: always a perfect circle,
  // never stretched by the cell (flexShrink 0) nor by the count below.
  dayNumber: {
    width: DAY_NUMBER_SIZE,
    height: DAY_NUMBER_SIZE,
    borderRadius: DAY_NUMBER_SIZE / 2,
    flexShrink: 0,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dayNumberText: {
    fontSize: 15,
    lineHeight: 20,
    textAlign: 'center',
  },
  countPill: {
    minWidth: 18,
    height: 16,
    paddingHorizontal: 4,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  countText: {
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '700',
    color: colors.primaryDark,
  },
  countSpacer: {
    height: 16,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    minHeight: 24,
  },
  statusText: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  statusErrorText: {
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

const CIRCLE_STYLES: Record<DayLook, ViewStyle> = StyleSheet.create({
  plain: { borderWidth: 0, borderColor: 'transparent', backgroundColor: 'transparent' },
  today: { borderWidth: 1.5, borderColor: colors.primary, backgroundColor: 'transparent' },
  selected: { borderWidth: 0, borderColor: 'transparent', backgroundColor: colors.primary },
});

const NUMBER_STYLES: Record<DayLook, TextStyle> = StyleSheet.create({
  plain: { fontWeight: '500', color: colors.textPrimary },
  today: { fontWeight: '700', color: colors.primaryDark },
  selected: { fontWeight: '700', color: colors.surface },
});

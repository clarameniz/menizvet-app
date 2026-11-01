import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import { civilDateString, civilDateTimeInTimeZone } from '@/lib/appointment-time';

/**
 * Pure presentation helpers for the professional appointment calendar
 * (SPEC-APT-012 §14). Dates are plain Clinic-local calendar dates
 * ("YYYY-MM-DD"), handled with UTC-anchored arithmetic and formatted with
 * `timeZone: 'UTC'`, so the device's timezone can never shift which date is
 * meant. The Clinic's "today" comes only from the calendar context read
 * (BR-60); nothing here derives it from the device clock.
 */

/** One calendar month; `month` is 1–12. */
export type CalendarMonth = { year: number; month: number };

/** The months the backend accepts (SPEC-APT-012 BR-54: years 2000–2999). */
export const FIRST_CALENDAR_MONTH: CalendarMonth = { year: 2000, month: 1 };
export const LAST_CALENDAR_MONTH: CalendarMonth = { year: 2999, month: 12 };

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Whether `value` is a real "YYYY-MM-DD" calendar date (no 2026-02-30). */
export function isCalendarDate(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const match = DATE_PATTERN.exec(value);
  if (match === null) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
  );
}

function utcDate(localDate: string): Date {
  const [year, month, day] = localDate.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

export function monthOfDate(localDate: string): CalendarMonth {
  const [year, month] = localDate.split('-').map(Number);
  return { year, month };
}

/** "YYYY-MM": the cache key of a month. */
export function monthKey(month: CalendarMonth): string {
  return `${month.year.toString().padStart(4, '0')}-${month.month.toString().padStart(2, '0')}`;
}

/** "YYYY-MM-01". */
export function firstDateOfMonth(month: CalendarMonth): string {
  return `${monthKey(month)}-01`;
}

export function isDateInMonth(localDate: string, month: CalendarMonth): boolean {
  return localDate.startsWith(`${monthKey(month)}-`);
}

export function isSameMonth(a: CalendarMonth, b: CalendarMonth): boolean {
  return a.year === b.year && a.month === b.month;
}

export function shiftMonth(month: CalendarMonth, delta: number): CalendarMonth {
  const index = month.year * 12 + (month.month - 1) + delta;
  return { year: Math.floor(index / 12), month: (index % 12) + 1 };
}

function monthIndex(month: CalendarMonth): number {
  return month.year * 12 + month.month;
}

/** Whether the backend accepts this month (SPEC-APT-012 BR-54). */
export function isSupportedMonth(month: CalendarMonth): boolean {
  return (
    monthIndex(month) >= monthIndex(FIRST_CALENDAR_MONTH) &&
    monthIndex(month) <= monthIndex(LAST_CALENDAR_MONTH)
  );
}

export function daysInMonth(month: CalendarMonth): number {
  return new Date(Date.UTC(month.year, month.month, 0)).getUTCDate();
}

/**
 * Week rows of a month in a Monday-first grid without other months' days:
 * 4 (a 28-day February starting on Monday), 5, or 6.
 */
export function weekRowsInMonth(month: CalendarMonth): number {
  const firstWeekday = new Date(Date.UTC(month.year, month.month - 1, 1)).getUTCDay();
  const offset = (firstWeekday + 6) % 7; // Monday = 0
  return Math.ceil((offset + daysInMonth(month)) / 7);
}

/**
 * The device's current month — only the PROVISIONAL first month when the
 * Clinic has no valid timezone (BR-60). Never presented as the Clinic's
 * current month.
 */
export function deviceMonth(now: Date = new Date()): CalendarMonth {
  return { year: now.getFullYear(), month: now.getMonth() + 1 };
}

function capitalized(text: string): string {
  return text.length === 0 ? text : text.charAt(0).toLocaleUpperCase() + text.slice(1);
}

/** "Noviembre de 2026" / "November 2026". */
export function formatMonthTitle(month: CalendarMonth, locale: string): string {
  return capitalized(
    new Intl.DateTimeFormat(locale, { timeZone: 'UTC', month: 'long', year: 'numeric' }).format(
      new Date(Date.UTC(month.year, month.month - 1, 1)),
    ),
  );
}

/** Monday-first weekday names: a short visible label and the full accessible name. */
export function mondayFirstWeekdays(locale: string): { short: string; long: string }[] {
  const shortFormat = new Intl.DateTimeFormat(locale, { timeZone: 'UTC', weekday: 'short' });
  const longFormat = new Intl.DateTimeFormat(locale, { timeZone: 'UTC', weekday: 'long' });
  // 2024-01-01 was a Monday.
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(Date.UTC(2024, 0, 1 + index));
    return {
      short: capitalized(shortFormat.format(date).replace(/\.$/, '')),
      long: longFormat.format(date),
    };
  });
}

/** "Martes, 3 de noviembre de 2026" / "Tuesday, November 3, 2026". */
export function formatDayHeading(localDate: string, locale: string): string {
  return capitalized(
    new Intl.DateTimeFormat(locale, {
      timeZone: 'UTC',
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    }).format(utcDate(localDate)),
  );
}

/** What the calendar shows and selects. */
export type CalendarFocus = { visibleMonth: CalendarMonth; selectedDate: string | null };

/**
 * Where the calendar stands after a calendar context read (BR-60).
 *
 * - First read: the Clinic's today and its month, selected; without one, the
 *   device's month provisionally and nothing selected.
 * - Later reads keep the actor's own choice. Only when the actor is still on
 *   the previous "today" does a new Clinic date (midnight passed) move the
 *   selection — and the month, if it showed that day — to the new today; and
 *   a Clinic that just gained a valid timezone selects its today if nothing
 *   was selected yet.
 */
export function calendarFocusAfterContext(
  previous: (CalendarFocus & { today: string | null }) | null,
  today: string | null,
  now: Date = new Date(),
): CalendarFocus {
  if (previous === null) {
    return today === null
      ? { visibleMonth: deviceMonth(now), selectedDate: null }
      : { visibleMonth: monthOfDate(today), selectedDate: today };
  }
  const { visibleMonth, selectedDate } = previous;
  if (today === null || today === previous.today) return { visibleMonth, selectedDate };
  if (previous.today !== null && selectedDate === previous.today) {
    return {
      visibleMonth: isDateInMonth(previous.today, visibleMonth) ? monthOfDate(today) : visibleMonth,
      selectedDate: today,
    };
  }
  if (previous.today === null && selectedDate === null) {
    return { visibleMonth: monthOfDate(today), selectedDate: today };
  }
  return { visibleMonth, selectedDate };
}

/** An Appointment's relevant scheduled interval, as any Appointment read projects it. */
type ScheduledInterval = Pick<
  ClinicScheduleAppointment,
  'currentScheduledStartAt' | 'currentScheduledEndAt' | 'currentSchedulingTimezoneName'
>;

/**
 * The compact row's times, in the timezone the Appointment's interval was
 * established in (SPEC-APT-013 BR-47) — never the device's or the Clinic's
 * current one. `endsLater` when the interval ends on a later local date.
 */
export function compactAppointmentTimes(
  appointment: ScheduledInterval,
  locale: string,
): { start: string; end: string; endsLater: boolean } {
  const timeZone = appointment.currentSchedulingTimezoneName;
  const format = new Intl.DateTimeFormat(locale, { timeZone, hour: 'numeric', minute: '2-digit' });
  const startDate = civilDateString(
    civilDateTimeInTimeZone(appointment.currentScheduledStartAt, timeZone),
  );
  const endDate = civilDateString(
    civilDateTimeInTimeZone(appointment.currentScheduledEndAt, timeZone),
  );
  return {
    start: format.format(new Date(appointment.currentScheduledStartAt)),
    end: format.format(new Date(appointment.currentScheduledEndAt)),
    endsLater: endDate !== startDate,
  };
}

/** The Clinic-local date ("YYYY-MM-DD") on which the Appointment starts, in its own timezone (BR-53). */
export function appointmentLocalDate(
  appointment: Pick<ScheduledInterval, 'currentScheduledStartAt' | 'currentSchedulingTimezoneName'>,
): string {
  return civilDateString(
    civilDateTimeInTimeZone(
      appointment.currentScheduledStartAt,
      appointment.currentSchedulingTimezoneName,
    ),
  );
}

/**
 * A list row's short date, in the Appointment's own timezone: "15 oct" in the
 * current year there, "15 oct 2025" otherwise. The full date belongs in the
 * accessible name (`formatDayHeading`).
 */
export function compactAppointmentDate(
  appointment: Pick<ScheduledInterval, 'currentScheduledStartAt' | 'currentSchedulingTimezoneName'>,
  locale: string,
  now: Date = new Date(),
): string {
  const localDate = appointmentLocalDate(appointment);
  const currentYear = civilDateString(
    civilDateTimeInTimeZone(now.toISOString(), appointment.currentSchedulingTimezoneName),
  ).slice(0, 4);
  return new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    day: 'numeric',
    month: 'short',
    ...(localDate.startsWith(currentYear) ? {} : { year: 'numeric' }),
  })
    .format(utcDate(localDate))
    .replace(/\.$/, '');
}

/**
 * Whether a row names its interval's timezone: when it differs from the
 * Clinic's current one, or when the Clinic has no valid current timezone to
 * compare with. The zone is always the Appointment's own, never presented as
 * the Clinic's current zone (BR-60).
 */
export function showsAppointmentTimezone(
  appointment: ClinicScheduleAppointment,
  clinicTimezoneName: string | null,
): boolean {
  return (
    clinicTimezoneName === null || appointment.currentSchedulingTimezoneName !== clinicTimezoneName
  );
}

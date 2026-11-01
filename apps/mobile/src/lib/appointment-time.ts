/**
 * Clinic-timezone-authoritative civil-time helpers for Appointment
 * scheduling (SPEC-APT-013 BR-43/44/51/53). The device's own timezone is
 * never authoritative here — every function takes an explicit IANA Clinic
 * `scheduling_timezone_name` and never reads the runtime's local timezone to
 * decide what a stored civil date/time *means*.
 *
 * As of the Guardian requestable-times enhancement (SPEC-APT-001 BR-29/30,
 * SPEC-APT-004 BR-22/23, SPEC-APT-014), the Guardian no longer types a
 * civil date/time to submit: every start the client can submit to
 * `request_appointment`/`reschedule_requested_appointment` is a candidate
 * returned verbatim by `get_requestable_appointment_start_times`, already
 * carrying its own resolved local date, local time, and UTC offset — so the
 * client never independently resolves a civil time to an offset for
 * submission purposes. What remains here is calendar-date arithmetic for the
 * candidate query windows, and *display*: formatting candidate dates and
 * already-established stored instants in the Clinic's timezone.
 */

export type CivilDateTime = {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number; // 0-23
  minute: number;
};

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** The civil (Y/M/D/H/M) representation of a real instant, in the given zone. */
function civilAt(timeZone: string, epochMs: number): CivilDateTime {
  const parts = formatterFor(timeZone).formatToParts(new Date(epochMs));
  const get = (type: string): number => Number(parts.find((part) => part.type === type)?.value);

  return {
    year: get('year'),
    month: get('month'),
    day: get('day'),
    hour: get('hour'),
    minute: get('minute'),
  };
}

/**
 * Formats just the calendar-date portion of a CivilDateTime as `YYYY-MM-DD`,
 * for the `p_start_date`/`p_end_date` parameters of
 * get_requestable_appointment_start_times — a plain Clinic-local calendar
 * date, not an instant, so no timezone resolution applies here.
 */
export function civilDateString(civil: Pick<CivilDateTime, 'year' | 'month' | 'day'>): string {
  return `${civil.year.toString().padStart(4, '0')}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

/**
 * Adds `days` (may be negative) to a plain calendar date, with no timezone or
 * time-of-day involved — pure calendar arithmetic via a UTC-anchored Date, so
 * it can never be shifted by the device's own timezone.
 */
export function addCivilDays(
  civil: Pick<CivilDateTime, 'year' | 'month' | 'day'>,
  days: number,
): Pick<CivilDateTime, 'year' | 'month' | 'day'> {
  const utcDate = new Date(Date.UTC(civil.year, civil.month - 1, civil.day));
  utcDate.setUTCDate(utcDate.getUTCDate() + days);
  return {
    year: utcDate.getUTCFullYear(),
    month: utcDate.getUTCMonth() + 1,
    day: utcDate.getUTCDate(),
  };
}

/** Adds `days` (may be negative) to a "YYYY-MM-DD" calendar date. */
export function shiftLocalDate(localDate: string, days: number): string {
  const [year, month, day] = localDate.split('-').map(Number);
  return civilDateString(addCivilDays({ year, month, day }, days));
}

/**
 * Today's calendar date ("YYYY-MM-DD") in the Clinic's timezone — never the
 * device's. Computed from a real instant (defaulting to now), so a device in
 * another timezone than the Clinic never reads the wrong day.
 */
export function clinicLocalToday(
  schedulingTimezoneName: string,
  referenceInstant: Date = new Date(),
): string {
  return civilDateString(
    civilDateTimeInTimeZone(referenceInstant.toISOString(), schedulingTimezoneName),
  );
}

/** An inclusive range of Clinic-local calendar dates ("YYYY-MM-DD") for one candidate read. */
export type CandidateDateWindow = { startDate: string; endDate: string };

/** A window date for a window label, with its year (windows may be years ahead). */
export function formatCandidateWindowDate(localDate: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(utcDateFromLocalDate(localDate));
}

/**
 * The approved Guardian requestable-times horizon (SPEC-APT-014 BR-11):
 * Clinic-local today through today + 60, both inclusive — 61 dates.
 */
export const REQUESTABLE_HORIZON_DAYS = 60;

/** Dates in the first Guardian window: Clinic-local today through today + 29. */
export const REQUESTABLE_DATE_RANGE_DAYS = 30;

/**
 * The fixed partition of the 61 allowed Guardian dates into consecutive
 * windows, as inclusive day offsets from Clinic-local today: the first 30
 * dates, then the remaining 31 (today + 30 through today + 60). No gap, no
 * overlap, never before today, never after today + 60.
 */
const REQUESTABLE_WINDOW_OFFSETS: readonly (readonly [number, number])[] = [
  [0, REQUESTABLE_DATE_RANGE_DAYS - 1],
  [REQUESTABLE_DATE_RANGE_DAYS, REQUESTABLE_HORIZON_DAYS],
];

/** One Guardian candidate window: its position in the partition and its dates. */
export type RequestableCandidateWindow = CandidateDateWindow & { index: number };

/**
 * Window `index` of the Guardian partition anchored on Clinic-local `today`,
 * or `null` when no such window exists.
 */
export function requestableCandidateWindow(
  index: number,
  today: string,
): RequestableCandidateWindow | null {
  const offsets = REQUESTABLE_WINDOW_OFFSETS[index];
  if (offsets === undefined) return null;
  return {
    index,
    startDate: shiftLocalDate(today, offsets[0]),
    endDate: shiftLocalDate(today, offsets[1]),
  };
}

/** The first Guardian window: Clinic-local today through today + 29. */
export function initialRequestableCandidateWindow(
  schedulingTimezoneName: string,
  referenceInstant: Date = new Date(),
): RequestableCandidateWindow {
  const window = requestableCandidateWindow(
    0,
    clinicLocalToday(schedulingTimezoneName, referenceInstant),
  );
  if (window === null) throw new Error('The Guardian candidate partition has no first window');
  return window;
}

/**
 * The Guardian window after `window`, re-anchored on the current Clinic-local
 * today; `null` when `window` is the last one (the horizon is reached).
 */
export function nextRequestableCandidateWindow(
  window: RequestableCandidateWindow,
  schedulingTimezoneName: string,
  referenceInstant: Date = new Date(),
): RequestableCandidateWindow | null {
  return requestableCandidateWindow(
    window.index + 1,
    clinicLocalToday(schedulingTimezoneName, referenceInstant),
  );
}

/**
 * The Guardian window before `window`, re-anchored on the current Clinic-local
 * today; `null` for the first window (nothing before today).
 */
export function previousRequestableCandidateWindow(
  window: RequestableCandidateWindow,
  schedulingTimezoneName: string,
  referenceInstant: Date = new Date(),
): RequestableCandidateWindow | null {
  if (window.index <= 0) return null;
  return requestableCandidateWindow(
    window.index - 1,
    clinicLocalToday(schedulingTimezoneName, referenceInstant),
  );
}

/**
 * Displays a candidate's plain Clinic-local calendar date ("YYYY-MM-DD", as
 * returned by getRequestableAppointmentStartTimes) as a short localized
 * label for a date-chip, e.g. "Mon, Jan 5" / "lun, 5 ene" — via Intl, never a
 * hardcoded weekday/month string. Parsed as a UTC-anchored date so the
 * device's own timezone can never shift which calendar date is displayed.
 */
export function formatCandidateDateLabel(localDate: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  }).format(utcDateFromLocalDate(localDate));
}

/**
 * A plain Clinic-local calendar date in long natural language ("14 de octubre
 * de 2026" / "October 14, 2026"), UTC-anchored like the labels above so the
 * device's timezone can never shift it.
 */
export function formatLongLocalDate(localDate: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, { timeZone: 'UTC', dateStyle: 'long' }).format(
    utcDateFromLocalDate(localDate),
  );
}

/** "YYYY-MM-DD" -> a UTC-midnight Date, formatted with `timeZone: 'UTC'` above. */
function utcDateFromLocalDate(localDate: string): Date {
  const [year, month, day] = localDate.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

/**
 * The same candidate date split into the two lines of a compact date chip —
 * weekday ("mié" / "Wed") and day + month ("23 sept" / "Sep 23") — using the
 * same Intl options and UTC anchoring as formatCandidateDateLabel, so the
 * two presentations can never disagree about which date it is. The full
 * one-line label stays the accessible name.
 */
export function formatCandidateDateParts(
  localDate: string,
  locale: string,
): { weekday: string; dayMonth: string } {
  const utcDate = utcDateFromLocalDate(localDate);

  return {
    weekday: new Intl.DateTimeFormat(locale, { timeZone: 'UTC', weekday: 'short' }).format(utcDate),
    dayMonth: new Intl.DateTimeFormat(locale, {
      timeZone: 'UTC',
      month: 'short',
      day: 'numeric',
    }).format(utcDate),
  };
}

/** The civil (Y/M/D/H/M) representation, in `timeZone`, of a stored instant. */
export function civilDateTimeInTimeZone(isoInstant: string, timeZone: string): CivilDateTime {
  return civilAt(timeZone, new Date(isoInstant).getTime());
}

/**
 * Displays a stored Appointment instant (an ISO timestamptz string, as
 * returned by get_pet_appointments / get_appointment_scheduling_history)
 * using the Clinic timezone that was in effect when it was established —
 * never the device's current timezone (SPEC-APT-013 BR-47/BR-53). Plain
 * digit formatting (DD/MM/YYYY HH:mm), matching this app's existing
 * formatCalendarDateForDisplay convention, rather than a locale-formatted
 * Intl string — keeps output deterministic and easy to test.
 */
export function formatInstantInTimeZone(isoInstant: string, timeZone: string): string {
  const civil = civilAt(timeZone, new Date(isoInstant).getTime());
  return `${pad2(civil.day)}/${pad2(civil.month)}/${civil.year} ${pad2(civil.hour)}:${pad2(civil.minute)}`;
}

/**
 * Displays a stored instant in `timeZone` as a locale-formatted date and time
 * ("24 oct 2026, 09:44" / "Oct 24, 2026, 09:44 AM") — the clinical record's
 * "Recorded on" and "Edited" (SPEC-MED-010 Part F). Intl resolves the instant
 * in `timeZone`, never the device's.
 */
export function formatRecordedInstant(
  isoInstant: string,
  timeZone: string,
  locale: string,
): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone,
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(isoInstant));
}

/**
 * Displays a stored scheduled interval (two ISO timestamptz instants, e.g. the
 * relevant scheduled interval returned by get_clinic_appointment_schedule) in
 * the Clinic timezone it was established in — never the device's timezone —
 * as a locale-formatted date ("mar, 6 feb 2035" / "Tue, Feb 6, 2035") and a
 * time range ("17:00 – 17:45" / "5:00 PM – 5:45 PM"). Intl resolves each UTC
 * instant in `timeZone`, so DST is handled without applying any offset here.
 * If the interval ends on a later Clinic-local day, the end carries its date.
 */
export function formatScheduledInterval(
  startIso: string,
  endIso: string,
  timeZone: string,
  locale: string,
): { date: string; time: string } {
  const start = new Date(startIso);
  const end = new Date(endIso);
  const dateFormat = new Intl.DateTimeFormat(locale, {
    timeZone,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
  const timeFormat = new Intl.DateTimeFormat(locale, {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
  });

  const startCivil = civilAt(timeZone, start.getTime());
  const endCivil = civilAt(timeZone, end.getTime());
  const sameDay =
    startCivil.year === endCivil.year &&
    startCivil.month === endCivil.month &&
    startCivil.day === endCivil.day;

  const endLabel = sameDay
    ? timeFormat.format(end)
    : `${dateFormat.format(end)} ${timeFormat.format(end)}`;

  return { date: dateFormat.format(start), time: `${timeFormat.format(start)} – ${endLabel}` };
}

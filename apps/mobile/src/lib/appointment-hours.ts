import type {
  AvailabilityException,
  AvailabilityPeriod,
  ClinicAppointmentHours,
  ExceptionWrite,
  TimeRange,
} from '@/data/clinic-appointment-hours';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { ProfessionalContext } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure logic for the professional "Appointment hours" surface: Clinic
 * Appointment availability, one-day exceptions, and the standard Appointment
 * duration (SPEC-APT-013 BR-9–BR-11, BR-41, BR-57–BR-62, BR-72–BR-75).
 *
 * Everything here is ADVISORY form logic: it decides what to offer and when a
 * Save button is enabled. The backend re-validates and re-authorizes every
 * write, and every displayed value comes from a fresh management read.
 *
 * Local times are Clinic-local civil times, kept as the exact text the backend
 * accepts and returns (`HH:MM`, `HH:MM:SS`, `HH:MM:SS.ffffff`, or `24:00` as an
 * end). They are compared through `localTimeMicroseconds` and never converted
 * to instants or reinterpreted, so a stored value with second precision is
 * shown and re-submitted unchanged unless the user edits that field.
 */

// ---------------------------------------------------------------------------
// Weekdays
// ---------------------------------------------------------------------------

export const ISO_WEEKDAYS = [1, 2, 3, 4, 5, 6, 7] as const;
export type IsoWeekday = (typeof ISO_WEEKDAYS)[number];

export function isIsoWeekday(value: unknown): value is IsoWeekday {
  return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 7;
}

/** ISO weekday (Monday 1 … Sunday 7) of a "YYYY-MM-DD" calendar date — no timezone involved. */
export function isoWeekdayOfLocalDate(localDate: string): IsoWeekday {
  const [year, month, day] = localDate.split('-').map(Number);
  const sundayBased = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return (((sundayBased + 6) % 7) + 1) as IsoWeekday;
}

// ---------------------------------------------------------------------------
// Local times
// ---------------------------------------------------------------------------

/** Exactly the backend's accepted ISO local-time text (`parse_clinic_local_time`). */
const LOCAL_TIME_PATTERN =
  /^(([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\.[0-9]{1,6})?)?|24:00(:00(\.0{1,6})?)?)$/;

const LOCAL_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/** Microseconds since local midnight (24:00 → 86 400 000 000), or `null` when not a valid local time. */
export function localTimeMicroseconds(value: string): number | null {
  if (!LOCAL_TIME_PATTERN.test(value)) return null;
  const [clock, fraction = ''] = value.split('.');
  const [hours, minutes, seconds = '0'] = clock.split(':');
  return (
    ((Number(hours) * 60 + Number(minutes)) * 60 + Number(seconds)) * 1_000_000 +
    Number(fraction.padEnd(6, '0'))
  );
}

/** A real "YYYY-MM-DD" calendar date. */
export function isLocalDate(value: string): boolean {
  if (!LOCAL_DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
  );
}

/**
 * Display text for a stored local time: `HH:MM` when it is a whole minute
 * ("09:00:00" → "09:00", "24:00:00" → "24:00"); otherwise the stored text
 * itself, so precision is never hidden or rounded away.
 */
export function displayLocalTime(value: string): string {
  const microseconds = localTimeMicroseconds(value);
  if (microseconds === null || microseconds % 60_000_000 !== 0) return value;
  return value.slice(0, 5);
}

/**
 * Tidies what the user typed when a time field loses focus: "930" / "0930" →
 * "09:30", "9:30" → "09:30". Anything else is returned trimmed and unchanged,
 * to be reported by validation — never guessed.
 */
export function normalizeTimeInput(text: string): string {
  const trimmed = text.trim();
  if (/^\d{3,4}$/.test(trimmed)) {
    const padded = trimmed.padStart(4, '0');
    return `${padded.slice(0, 2)}:${padded.slice(2)}`;
  }
  if (/^\d:\d{2}(:\d{2}(\.\d{1,6})?)?$/.test(trimmed)) return `0${trimmed}`;
  return trimmed;
}

/**
 * A Clinic-local calendar date for an exception ("dom, 11 oct 2026" /
 * "Sun, Oct 11, 2026"), UTC-anchored so the device timezone never shifts it.
 */
export function formatExceptionDate(localDate: string, locale: string): string {
  const [year, month, day] = localDate.split('-').map(Number);
  return new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

/** "09:00–13:00". */
export function formatTimeRange(range: TimeRange): string {
  return `${displayLocalTime(range.startTime)}–${displayLocalTime(range.endTime)}`;
}

/** "09:00–13:00, 16:00–20:00". */
export function formatTimeRanges(ranges: readonly TimeRange[]): string {
  return ranges.map(formatTimeRange).join(', ');
}

function compareRanges(a: TimeRange, b: TimeRange): number {
  return (
    (localTimeMicroseconds(a.startTime) ?? 0) - (localTimeMicroseconds(b.startTime) ?? 0) ||
    (localTimeMicroseconds(a.endTime) ?? 0) - (localTimeMicroseconds(b.endTime) ?? 0)
  );
}

/** Canonical identity of a set of ranges: equal for the same times, whatever their text or order. */
function canonicalRanges(ranges: readonly TimeRange[]): string {
  return ranges
    .map(
      (range) =>
        `${localTimeMicroseconds(range.startTime)}-${localTimeMicroseconds(range.endTime)}`,
    )
    .sort()
    .join(',');
}

// ---------------------------------------------------------------------------
// Period drafts (shared by the weekly and the exception editors)
// ---------------------------------------------------------------------------

/** One editable period; `id` is a stable React key only. */
export type PeriodDraft = { id: string; start: string; end: string };

let periodIdCounter = 0;

export function newPeriodDraft(start = '', end = ''): PeriodDraft {
  periodIdCounter += 1;
  return { id: `period-${periodIdCounter}`, start, end };
}

function periodDraftsFromRanges(ranges: readonly TimeRange[]): PeriodDraft[] {
  return [...ranges]
    .sort(compareRanges)
    .map((range) =>
      newPeriodDraft(displayLocalTime(range.startTime), displayLocalTime(range.endTime)),
    );
}

export type PeriodIssue =
  | 'startRequired'
  | 'startInvalid'
  | 'endRequired'
  | 'endInvalid'
  /** Start is not before end (an overnight period must be split across two days). */
  | 'order'
  /** Overlaps another period of the same day; touching periods are fine. */
  | 'overlap';

/** The first problem of each period, in order, or `null` when it is valid. */
export function periodIssues(periods: readonly PeriodDraft[]): (PeriodIssue | null)[] {
  const parsed = periods.map((period) => {
    const start = period.start.trim();
    const end = period.end.trim();
    return {
      startText: start,
      endText: end,
      start: localTimeMicroseconds(start),
      end: localTimeMicroseconds(end),
    };
  });

  return parsed.map((period, index) => {
    const { start, end } = period;
    if (period.startText === '') return 'startRequired';
    if (start === null) return 'startInvalid';
    if (period.endText === '') return 'endRequired';
    if (end === null) return 'endInvalid';
    if (start >= end) return 'order';
    const overlaps = parsed.some(
      (other, otherIndex) =>
        otherIndex !== index &&
        other.start !== null &&
        other.end !== null &&
        other.start < other.end &&
        start < other.end &&
        other.start < end,
    );
    return overlaps ? 'overlap' : null;
  });
}

export function arePeriodsValid(periods: readonly PeriodDraft[]): boolean {
  return periodIssues(periods).every((issue) => issue === null);
}

function rangesFromDrafts(periods: readonly PeriodDraft[]): TimeRange[] {
  return periods
    .map((period) => ({ startTime: period.start.trim(), endTime: period.end.trim() }))
    .sort(compareRanges);
}

// ---------------------------------------------------------------------------
// Weekly availability (full-replacement semantics, BR-75)
// ---------------------------------------------------------------------------

export type WeeklyDraft = Record<IsoWeekday, PeriodDraft[]>;

export function recurringRangesFor(
  periods: readonly AvailabilityPeriod[],
  isoWeekday: IsoWeekday,
): TimeRange[] {
  return periods
    .filter((period) => period.isoWeekday === isoWeekday)
    .map(({ startTime, endTime }) => ({ startTime, endTime }))
    .sort(compareRanges);
}

/** The editor's whole-week draft from the stored recurring periods. */
export function weeklyDraftFrom(periods: readonly AvailabilityPeriod[]): WeeklyDraft {
  const draft = {} as WeeklyDraft;
  for (const weekday of ISO_WEEKDAYS) {
    draft[weekday] = periodDraftsFromRanges(recurringRangesFor(periods, weekday));
  }
  return draft;
}

export function isWeeklyDraftValid(draft: WeeklyDraft): boolean {
  return ISO_WEEKDAYS.every((weekday) => arePeriodsValid(draft[weekday]));
}

/** The complete week to submit, ordered by weekday then start. Only meaningful for a valid draft. */
export function weeklyPayload(draft: WeeklyDraft): AvailabilityPeriod[] {
  return ISO_WEEKDAYS.flatMap((weekday) =>
    rangesFromDrafts(draft[weekday]).map((range) => ({ isoWeekday: weekday, ...range })),
  );
}

function canonicalWeek(periods: readonly AvailabilityPeriod[]): string {
  return ISO_WEEKDAYS.map(
    (weekday) => `${weekday}:${canonicalRanges(recurringRangesFor(periods, weekday))}`,
  ).join('|');
}

/** Whether two recurring sets describe the same times (text and order aside). */
export function sameWeeklyAvailability(
  a: readonly AvailabilityPeriod[],
  b: readonly AvailabilityPeriod[],
): boolean {
  return canonicalWeek(a) === canonicalWeek(b);
}

/** Whether a valid draft differs from the stored week. */
export function isWeeklyDraftChanged(
  draft: WeeklyDraft,
  stored: readonly AvailabilityPeriod[],
): boolean {
  return !sameWeeklyAvailability(weeklyPayload(draft), stored);
}

/**
 * The weekly editor: the draft and the revision of the exact week it was
 * prepared from. The save sends that base revision (BR-75), never one from a
 * later read.
 */
export type WeeklyEditor = { draft: WeeklyDraft; baseRevision: number };

export function weeklyEditorFrom(config: ClinicAppointmentHours): WeeklyEditor {
  return {
    draft: weeklyDraftFrom(config.recurringPeriods),
    baseRevision: config.weeklyAvailabilityRevision,
  };
}

/** The editor after a read: an existing editor is kept, base revision included. */
export function weeklyEditorAfterRead(
  current: WeeklyEditor | null,
  config: ClinicAppointmentHours,
): WeeklyEditor {
  return current ?? weeklyEditorFrom(config);
}

/**
 * What a failed weekly save means, decided from the fresh read that follows it:
 * - `committed`: the stored week is what was sent — a lost response after the
 *   save committed, or another editor already saved the same week;
 * - `stale`: the week changed meanwhile; the draft is replaced by the latest
 *   week and revision (never merged);
 * - `failed`: anything else; the draft stays and the error is shown.
 */
export type WeeklySaveFailure =
  { kind: 'committed' } | { kind: 'stale'; editor: WeeklyEditor } | { kind: 'failed' };

export function weeklySaveFailure(input: {
  stale: boolean;
  latest: ClinicAppointmentHours | null;
  submitted: readonly AvailabilityPeriod[];
}): WeeklySaveFailure {
  const { stale, latest, submitted } = input;
  if (latest !== null && sameWeeklyAvailability(latest.recurringPeriods, submitted)) {
    return { kind: 'committed' };
  }
  if (stale && latest !== null) return { kind: 'stale', editor: weeklyEditorFrom(latest) };
  return { kind: 'failed' };
}

// ---------------------------------------------------------------------------
// Exceptions (BR-73)
// ---------------------------------------------------------------------------

/**
 * Exceptions on or after Clinic-local `today`, by date. The management read
 * returns past dates too; this is where they stop being presented. `null`
 * (no Clinic timezone, so no Clinic-local today) presents none — the backend
 * accepts no exception without a timezone.
 */
export function upcomingExceptions(
  exceptions: readonly AvailabilityException[],
  today: string | null,
): AvailabilityException[] {
  if (today === null) return [];
  return exceptions
    .filter((exception) => exception.localDate >= today)
    .sort((a, b) => (a.localDate < b.localDate ? -1 : a.localDate > b.localDate ? 1 : 0));
}

export function exceptionFor(
  exceptions: readonly AvailabilityException[],
  localDate: string,
): AvailabilityException | null {
  return exceptions.find((exception) => exception.localDate === localDate) ?? null;
}

/**
 * Presentation only — the backend has just OPEN and CLOSED:
 * - CLOSED → closed all day;
 * - OPEN on a weekday with no recurring hours → open exceptionally;
 * - OPEN on a normally open weekday → custom hours (e.g. closing early).
 */
export type ExceptionPresentation = 'closedAllDay' | 'openExceptionally' | 'customHours';

export function exceptionPresentation(
  exception: AvailabilityException,
  recurring: readonly AvailabilityPeriod[],
): ExceptionPresentation {
  if (exception.kind === 'CLOSED') return 'closedAllDay';
  return recurringRangesFor(recurring, isoWeekdayOfLocalDate(exception.localDate)).length === 0
    ? 'openExceptionally'
    : 'customHours';
}

/**
 * Starting periods for new custom hours on `localDate`: that weekday's normal
 * hours, so "close at 14:00 next Tuesday" is one edit; a normally closed day
 * starts with one empty period.
 */
export function prefillCustomHours(
  localDate: string,
  recurring: readonly AvailabilityPeriod[],
): PeriodDraft[] {
  const ranges = recurringRangesFor(recurring, isoWeekdayOfLocalDate(localDate));
  return ranges.length > 0 ? periodDraftsFromRanges(ranges) : [newPeriodDraft()];
}

export type ExceptionKindChoice = 'CLOSED' | 'OPEN';

export type ExceptionDraft = {
  localDate: string | null;
  kind: ExceptionKindChoice | null;
  /** Used only when `kind` is OPEN. */
  periods: PeriodDraft[];
};

export function exceptionDraftFrom(exception: AvailabilityException): ExceptionDraft {
  return {
    localDate: exception.localDate,
    kind: exception.kind,
    periods: exception.kind === 'OPEN' ? periodDraftsFromRanges(exception.periods) : [],
  };
}

export type ExceptionDateIssue = 'required' | 'invalid' | 'past';

/** Date is required, real, and today or later in Clinic-local time (a UI rule; the backend accepts any finite date). */
export function exceptionDateIssue(
  localDate: string | null,
  today: string,
): ExceptionDateIssue | null {
  if (localDate === null) return 'required';
  if (!isLocalDate(localDate)) return 'invalid';
  return localDate < today ? 'past' : null;
}

export function isExceptionDraftValid(draft: ExceptionDraft, today: string): boolean {
  if (exceptionDateIssue(draft.localDate, today) !== null || draft.kind === null) return false;
  if (draft.kind === 'CLOSED') return true;
  return draft.periods.length > 0 && arePeriodsValid(draft.periods);
}

/** The write for a valid draft. */
export function exceptionPayload(draft: ExceptionDraft): ExceptionWrite {
  return draft.kind === 'OPEN'
    ? { kind: 'OPEN', periods: rangesFromDrafts(draft.periods) }
    : { kind: 'CLOSED' };
}

/** Whether a stored exception is exactly what `write` describes. */
export function exceptionMatches(
  stored: AvailabilityException | null,
  write: ExceptionWrite,
): boolean {
  if (stored === null || stored.kind !== write.kind) return false;
  if (stored.kind === 'CLOSED' || write.kind === 'CLOSED') return true;
  return canonicalRanges(stored.periods) === canonicalRanges(write.periods);
}

/** Whether a valid draft differs from what is stored for its date (a new exception always does). */
export function isExceptionDraftChanged(
  draft: ExceptionDraft,
  stored: AvailabilityException | null,
): boolean {
  return !exceptionMatches(stored, exceptionPayload(draft));
}

/** Consecutive Clinic-local dates offered for a new exception, one window at a time. */
export const EXCEPTION_DATE_WINDOW_DAYS = 14;

export function exceptionDateWindow(startDate: string): string[] {
  const [year, month, day] = startDate.split('-').map(Number);
  return Array.from({ length: EXCEPTION_DATE_WINDOW_DAYS }, (_, offset) => {
    const date = new Date(Date.UTC(year, month - 1, day + offset));
    return date.toISOString().slice(0, 10);
  });
}

// ---------------------------------------------------------------------------
// Standard Appointment duration (BR-61)
// ---------------------------------------------------------------------------

export const MIN_STANDARD_DURATION_MINUTES = 10;
export const MAX_STANDARD_DURATION_MINUTES = 240;
export const DURATION_PRESETS_MINUTES = [10, 15, 20, 30, 45, 60, 90, 120] as const;

export function isValidStandardDuration(minutes: number): boolean {
  return (
    Number.isInteger(minutes) &&
    minutes >= MIN_STANDARD_DURATION_MINUTES &&
    minutes <= MAX_STANDARD_DURATION_MINUTES
  );
}

/** Whole minutes from the "other" field, or `null` when incomplete or outside 10–240. */
export function parseDurationInput(text: string): number | null {
  const trimmed = text.trim();
  if (!/^\d{1,3}$/.test(trimmed)) return null;
  const minutes = Number(trimmed);
  return isValidStandardDuration(minutes) ? minutes : null;
}

export function isDurationPreset(minutes: number | null): boolean {
  return minutes !== null && (DURATION_PRESETS_MINUTES as readonly number[]).includes(minutes);
}

// ---------------------------------------------------------------------------
// Access and Save readiness
// ---------------------------------------------------------------------------

/** Offer "Appointment hours" only with the KNOWN capability (advisory, SPEC-ORG-008 BR-13). */
export function offersAppointmentHours(clinic: ProfessionalClinic): boolean {
  return clinic.capabilities.includes('APPOINTMENT_MANAGE_AVAILABILITY');
}

/** The Appointment hours screen of a Professional Clinic. */
export function appointmentHoursHref(clinicId: string) {
  return {
    pathname: '/professional/clinics/[clinicId]/appointment-hours',
    params: { clinicId },
  } as const;
}

/**
 * Editable only while the Clinic's Organization currently holds
 * PROFESSIONAL_SCHEDULING; otherwise the configuration is shown read-only
 * (the read stays available, BR-74). An Organization absent from the
 * professional context is treated as read-only. `unconfirmed`: the
 * professional context (`null`) could not be read, so editing is not offered
 * — the configuration itself was authorized by its own management read.
 * Advisory: writes re-check.
 */
export type AppointmentHoursAccess = 'editable' | 'readOnly' | 'unconfirmed';

export function appointmentHoursAccess(
  context: ProfessionalContext | null,
  organizationId: string,
): AppointmentHoursAccess {
  if (context === null) return 'unconfirmed';
  const organization = context.organizations.find(
    (entry) => entry.organizationId === organizationId,
  );
  return organization?.entitlements.PROFESSIONAL_SCHEDULING === true ? 'editable' : 'readOnly';
}

/** Why editing is not offered, or `null` when it is. */
export function accessNoticeKey(access: AppointmentHoursAccess): TranslationKey | null {
  if (access === 'readOnly') return 'appointmentHours.readOnlyNotice';
  if (access === 'unconfirmed') return 'appointmentHours.accessUnconfirmedNotice';
  return null;
}

/**
 * Weekly hours and exceptions need the Clinic scheduling timezone (the
 * backend rejects them without one) and an editable access.
 */
export function canEditAvailability(
  config: ClinicAppointmentHours,
  access: AppointmentHoursAccess,
): boolean {
  return access === 'editable' && config.schedulingTimezoneName !== null;
}

/** The standard duration does not depend on the timezone. */
export function canEditDuration(access: AppointmentHoursAccess): boolean {
  return access === 'editable';
}

/**
 * The repository's required-field convention for a primary Save: enabled
 * only when editable, complete and valid, actually changed, and nothing is in
 * flight.
 */
export function canSaveConfiguration(input: {
  editable: boolean;
  valid: boolean;
  changed: boolean;
  busy: boolean;
}): boolean {
  return input.editable && input.valid && input.changed && !input.busy;
}

import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  CLINIC_SCHEDULE_MALFORMED,
  parseClinicAppointmentSchedule,
  type ClinicScheduleAppointment,
  type ClinicScheduleResult,
} from '@/data/clinic-appointment-schedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { civilDateTimeInTimeZone, civilDateString } from '@/lib/appointment-time';
import { isCalendarDate } from '@/lib/clinic-calendar';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the deployed professional calendar reads (SPEC-APT-012 §14):
 *
 * - `get_clinic_calendar_context(p_clinic_id uuid)` — BR-60, migration
 *   20261110090000_clinic_calendar_context.sql: exactly one row
 *   `(clinic_local_today date, scheduling_timezone_name text)`, both present
 *   or both null (no valid Clinic timezone). The date is computed by the
 *   server; the device clock never decides it.
 * - `get_clinic_appointment_month_counts(p_clinic_id uuid, p_year integer,
 *   p_month integer)` — BR-54, migration
 *   20261108090000_clinic_appointment_read_and_month_counts.sql: one row
 *   `(day date, appointment_count integer)` per Clinic-local date of that
 *   month with at least one calendar Appointment, ordered by day. Absent
 *   dates mean zero. The counted states are the backend's (BR-53); the client
 *   never recounts them.
 * - `get_clinic_appointment_day(p_clinic_id uuid, p_day date)` — BR-56,
 *   migration 20261109090000_clinic_appointment_day_pending_history.sql: the
 *   calendar Appointments of one Clinic-local date as schedule rows (BR-51),
 *   ordered by start then id. Parsed by the schedule's own strict row parser.
 * - `get_clinic_appointment_pending(p_clinic_id uuid, p_after_rank integer,
 *   p_after_start_at timestamptz, p_after_id uuid, p_limit integer)` — BR-57,
 *   same migration: one keyset page of the REQUESTED and CONFIRMED
 *   Appointments classified for the acting User, ordered by
 *   `(pending_rank, current_scheduled_start_at, id)`, each row with its
 *   reason, category, rank and the totals of the WHOLE classification. An
 *   empty first page means zero everywhere; an empty later page carries no
 *   totals.
 * - `get_clinic_appointment_history(p_clinic_id uuid, p_before_start_at
 *   timestamptz, p_before_id uuid, p_limit integer)` — BR-59, same migration:
 *   one keyset page of terminal Appointments, newest start first, then id
 *   descending.
 *
 * Cursors are the complete key of the last row of the previous page, sent
 * back exactly as the backend returned it (the timestamp string is never
 * re-formatted, so no precision is lost). The pending summary (BR-58) is not
 * read: the first page always carries the totals, and an empty later page
 * keeps those of the previous page.
 *
 * Every read re-authorizes the caller (`APPOINTMENT_VIEW_SCHEDULE` for the
 * Clinic). Parsing is strict: any malformed value rejects the whole read.
 * SQLSTATE 28000 is normalized to PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 42501
 * (no authority, or an unknown Clinic — indistinguishable) to
 * CLINIC_SCHEDULE_ACCESS_DENIED, and a malformed payload to
 * CLINIC_SCHEDULE_MALFORMED. Every call settles into `{data, error}` and never
 * rejects.
 */

/** The Clinic's calendar context (SPEC-APT-012 BR-60). Both null together, or both present. */
export type ClinicCalendarContext = {
  /** "YYYY-MM-DD": the Clinic's current local date, or `null` without a valid timezone. */
  clinicLocalToday: string | null;
  /** The Clinic's CURRENT valid scheduling timezone, or `null`. Never an Appointment's own zone. */
  schedulingTimezoneName: string | null;
};

/** Calendar Appointments per Clinic-local date of one month; absent dates mean zero. */
export type ClinicMonthCounts = Readonly<Record<string, number>>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isTimeZone(value: unknown): value is string {
  if (typeof value !== 'string' || value.trim().length === 0) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

/**
 * Exported for unit testing: exactly one row, with both values valid or both
 * null. Anything else is `null`.
 */
export function parseClinicCalendarContext(raw: unknown): ClinicCalendarContext | null {
  if (!Array.isArray(raw) || raw.length !== 1 || !isRecord(raw[0])) return null;
  const { clinic_local_today: today, scheduling_timezone_name: timeZone } = raw[0];
  if (today === null && timeZone === null) {
    return { clinicLocalToday: null, schedulingTimezoneName: null };
  }
  if (!isCalendarDate(today) || !isTimeZone(timeZone)) return null;
  return { clinicLocalToday: today, schedulingTimezoneName: timeZone };
}

/**
 * Exported for unit testing: the month's rows — each a real date of exactly
 * that month, at most once, with a positive integer count — as a date → count
 * map. Anything else is `null`.
 */
export function parseClinicMonthCounts(
  raw: unknown,
  year: number,
  month: number,
): ClinicMonthCounts | null {
  if (!Array.isArray(raw)) return null;
  const prefix = `${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-`;
  const counts: Record<string, number> = {};
  for (const item of raw) {
    if (!isRecord(item)) return null;
    const { day, appointment_count: count } = item;
    if (!isCalendarDate(day) || !day.startsWith(prefix) || day in counts) return null;
    if (typeof count !== 'number' || !Number.isInteger(count) || count <= 0) return null;
    counts[day] = count;
  }
  return counts;
}

/**
 * Exported for unit testing: the day's rows through the schedule's strict row
 * parser (no duplicate Appointment), each starting on exactly `day` in the
 * timezone its interval was established in (SPEC-APT-012 BR-53). Anything
 * else is `null`.
 */
export function parseClinicAppointmentDay(
  raw: unknown,
  day: string,
): ClinicScheduleAppointment[] | null {
  const appointments = parseClinicAppointmentSchedule(raw);
  if (appointments === null) return null;
  const onThatDay = appointments.every(
    (appointment) =>
      civilDateString(
        civilDateTimeInTimeZone(
          appointment.currentScheduledStartAt,
          appointment.currentSchedulingTimezoneName,
        ),
      ) === day,
  );
  return onThatDay ? appointments : null;
}

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

function normalizedError(error: { code?: string; message: string }): string {
  if (error.code === '28000') return PROFESSIONAL_CONTEXT_AUTH_REQUIRED;
  if (error.code === '42501') return CLINIC_SCHEDULE_ACCESS_DENIED;
  return error.message;
}

async function read<T>(
  name: string,
  args: Record<string, unknown>,
  parse: (raw: unknown) => T | null,
): Promise<ClinicScheduleResult<T>> {
  try {
    const { data, error } = await supabase.rpc(name, args);
    if (error) return { data: null, error: normalizedError(error) };
    const parsed = parse(data);
    if (parsed === null) return { data: null, error: CLINIC_SCHEDULE_MALFORMED };
    return { data: parsed, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/** The Clinic's current local date and valid timezone (SPEC-APT-012 BR-60). */
export function getClinicCalendarContext(
  clinicId: string,
): Promise<ClinicScheduleResult<ClinicCalendarContext>> {
  return read('get_clinic_calendar_context', { p_clinic_id: clinicId }, parseClinicCalendarContext);
}

/** Calendar Appointments per day of one month (SPEC-APT-012 BR-54); one request per month. */
export function getClinicAppointmentMonthCounts(
  clinicId: string,
  year: number,
  month: number,
): Promise<ClinicScheduleResult<ClinicMonthCounts>> {
  return read(
    'get_clinic_appointment_month_counts',
    { p_clinic_id: clinicId, p_year: year, p_month: month },
    (raw) => parseClinicMonthCounts(raw, year, month),
  );
}

/** The calendar Appointments of one Clinic-local date (SPEC-APT-012 BR-56). */
export function getClinicAppointmentDay(
  clinicId: string,
  day: string,
): Promise<ClinicScheduleResult<ClinicScheduleAppointment[]>> {
  return read('get_clinic_appointment_day', { p_clinic_id: clinicId, p_day: day }, (raw) =>
    parseClinicAppointmentDay(raw, day),
  );
}

// ---------------------------------------------------------------------------
// Pending (BR-57) and History (BR-59)
// ---------------------------------------------------------------------------

/** The backend's pending categories (BR-57); stable identifiers, localized by the client. */
export type PendingCategory = 'ACTION_REQUIRED' | 'AWAITING_GUARDIAN' | 'INFORMATIONAL';

/** The backend's pending reasons (BR-57), in rank order. */
export type PendingReason =
  | 'ATTENDANCE_OUTCOME'
  | 'REQUEST_DECISION'
  | 'PROPOSAL_NOT_FEASIBLE'
  | 'GUARDIAN_PROPOSAL'
  | 'AWAITING_GUARDIAN';

/** BR-57's fixed table: each reason has exactly one category and one rank. */
export const PENDING_REASONS: Readonly<
  Record<PendingReason, { category: PendingCategory; rank: number }>
> = {
  ATTENDANCE_OUTCOME: { category: 'ACTION_REQUIRED', rank: 1 },
  REQUEST_DECISION: { category: 'ACTION_REQUIRED', rank: 2 },
  PROPOSAL_NOT_FEASIBLE: { category: 'ACTION_REQUIRED', rank: 3 },
  GUARDIAN_PROPOSAL: { category: 'INFORMATIONAL', rank: 4 },
  AWAITING_GUARDIAN: { category: 'AWAITING_GUARDIAN', rank: 5 },
};

function isPendingReason(value: unknown): value is PendingReason {
  return typeof value === 'string' && Object.hasOwn(PENDING_REASONS, value);
}

/** Appointments per category in the whole classification of one call (BR-57, BR-58). */
export type PendingTotals = Readonly<Record<PendingCategory, number>>;

export const ZERO_PENDING_TOTALS: PendingTotals = {
  ACTION_REQUIRED: 0,
  AWAITING_GUARDIAN: 0,
  INFORMATIONAL: 0,
};

/** One Pending row: a BR-51 Appointment with the backend's classification for this actor. */
export type ClinicPendingAppointment = {
  appointment: ClinicScheduleAppointment;
  reason: PendingReason;
  category: PendingCategory;
  rank: number;
};

/** The complete key of a Pending row (BR-57), exactly as the backend returned it. */
export type PendingCursor = { rank: number; startAt: string; id: string };

/** The complete key of a History row (BR-59), exactly as the backend returned it. */
export type HistoryCursor = { startAt: string; id: string };

/**
 * One Pending page. `totals` are the whole classification's; `null` only for
 * an empty LATER page, which carries none (the caller keeps the previous ones).
 */
export type ClinicPendingPage = {
  rows: ClinicPendingAppointment[];
  totals: PendingTotals | null;
};

function isCount(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

/**
 * Exported for unit testing: one Pending page. Every row is a schedule row
 * (strict parser, no duplicate) of a REQUESTED or CONFIRMED Appointment whose
 * reason, category and rank match BR-57's table, in non-decreasing rank, and
 * every row carries the same totals, which cover at least the page's own rows
 * per category. An empty first page means zero totals; an empty later page,
 * none. Anything else is `null`.
 */
export function parseClinicPendingPage(
  raw: unknown,
  isFirstPage: boolean,
): ClinicPendingPage | null {
  const appointments = parseClinicAppointmentSchedule(raw);
  if (appointments === null || !Array.isArray(raw)) return null;
  if (appointments.length === 0) {
    return { rows: [], totals: isFirstPage ? ZERO_PENDING_TOTALS : null };
  }

  const rows: ClinicPendingAppointment[] = [];
  let totals: PendingTotals | null = null;
  const onPage: Record<PendingCategory, number> = { ...ZERO_PENDING_TOTALS };
  for (const [index, appointment] of appointments.entries()) {
    const item = raw[index] as Record<string, unknown>;
    const {
      pending_reason: reason,
      pending_category: category,
      pending_rank: rank,
      action_required_count: actionRequired,
      awaiting_guardian_count: awaitingGuardian,
      informational_count: informational,
    } = item;
    if (
      !isPendingReason(reason) ||
      PENDING_REASONS[reason].category !== category ||
      PENDING_REASONS[reason].rank !== rank ||
      (appointment.lifecycleState !== 'REQUESTED' && appointment.lifecycleState !== 'CONFIRMED') ||
      !isCount(actionRequired) ||
      !isCount(awaitingGuardian) ||
      !isCount(informational)
    ) {
      return null;
    }
    const rowTotals: PendingTotals = {
      ACTION_REQUIRED: actionRequired,
      AWAITING_GUARDIAN: awaitingGuardian,
      INFORMATIONAL: informational,
    };
    if (
      totals !== null &&
      (totals.ACTION_REQUIRED !== actionRequired ||
        totals.AWAITING_GUARDIAN !== awaitingGuardian ||
        totals.INFORMATIONAL !== informational)
    ) {
      return null;
    }
    const previous = rows.at(-1);
    if (previous !== undefined && previous.rank > rank) return null;
    totals = rowTotals;
    onPage[PENDING_REASONS[reason].category] += 1;
    rows.push({ appointment, reason, category: PENDING_REASONS[reason].category, rank });
  }
  const pageTotals = totals;
  if (pageTotals === null) return null;
  const covered = (Object.keys(onPage) as PendingCategory[]).every(
    (key) => onPage[key] <= pageTotals[key],
  );
  return covered ? { rows, totals: pageTotals } : null;
}

const TERMINAL_STATES = new Set(['COMPLETED', 'NO_SHOW', 'CANCELLED', 'EXPIRED']);

/**
 * Exported for unit testing: one History page — schedule rows (strict parser,
 * no duplicate) of terminal Appointments only (BR-59). A REQUESTED or
 * CONFIRMED row, however late, is never history. Anything else is `null`.
 */
export function parseClinicHistoryPage(raw: unknown): ClinicScheduleAppointment[] | null {
  const appointments = parseClinicAppointmentSchedule(raw);
  if (appointments === null) return null;
  return appointments.every((appointment) => TERMINAL_STATES.has(appointment.lifecycleState))
    ? appointments
    : null;
}

/** The cursor that continues after `row` (BR-57). */
export function pendingCursorOf(row: ClinicPendingAppointment): PendingCursor {
  return {
    rank: row.rank,
    startAt: row.appointment.currentScheduledStartAt,
    id: row.appointment.id,
  };
}

/** The cursor that continues after `appointment` (BR-59). */
export function historyCursorOf(appointment: ClinicScheduleAppointment): HistoryCursor {
  return { startAt: appointment.currentScheduledStartAt, id: appointment.id };
}

/** One page of Pending (SPEC-APT-012 BR-57); `after` null reads the first page. */
export function getClinicAppointmentPending(
  clinicId: string,
  after: PendingCursor | null,
  limit: number,
): Promise<ClinicScheduleResult<ClinicPendingPage>> {
  return read(
    'get_clinic_appointment_pending',
    {
      p_clinic_id: clinicId,
      p_after_rank: after?.rank ?? null,
      p_after_start_at: after?.startAt ?? null,
      p_after_id: after?.id ?? null,
      p_limit: limit,
    },
    (raw) => parseClinicPendingPage(raw, after === null),
  );
}

/** One page of History (SPEC-APT-012 BR-59); `before` null reads the first page. */
export function getClinicAppointmentHistory(
  clinicId: string,
  before: HistoryCursor | null,
  limit: number,
): Promise<ClinicScheduleResult<ClinicScheduleAppointment[]>> {
  return read(
    'get_clinic_appointment_history',
    {
      p_clinic_id: clinicId,
      p_before_start_at: before?.startAt ?? null,
      p_before_id: before?.id ?? null,
      p_limit: limit,
    },
    parseClinicHistoryPage,
  );
}

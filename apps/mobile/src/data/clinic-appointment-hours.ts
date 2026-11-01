import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import {
  isIsoWeekday,
  isLocalDate,
  isValidStandardDuration,
  localTimeMicroseconds,
  type IsoWeekday,
} from '@/lib/appointment-hours';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the Clinic Appointment availability management contract
 * (SPEC-APT-013 BR-57–BR-62, BR-72–BR-75): migrations
 * 20260826140000_scheduling_configuration.sql,
 * 20260920120000_standard_appointment_duration_and_candidate_times.sql, and
 * 20261013090000_clinic_appointment_hours_management_read.sql. Every RPC is
 * granted to authenticated and re-authorized by the backend on every call —
 * nothing here is a permission check.
 *
 * - `get_managed_clinic_appointment_availability(p_clinic_id uuid)` returns
 *   one row `(scheduling_timezone_name text | null,
 *   standard_appointment_duration_minutes integer | null,
 *   recurring_periods jsonb, exceptions jsonb,
 *   weekly_appointment_availability_revision bigint)`. Needs
 *   APPOINTMENT_MANAGE_AVAILABILITY; no Entitlement and no publication. It
 *   returns every stored exception, including past dates
 *   (20261019090000_weekly_appointment_availability_revision.sql).
 * - `replace_clinic_appointment_availability(p_clinic_id uuid, p_periods jsonb,
 *   p_expected_weekly_availability_revision bigint)` replaces the WHOLE week
 *   (`[]` clears it) only if the week is still at the expected revision;
 *   otherwise it changes nothing and fails as stale (normalized to
 *   APPOINTMENT_HOURS_WEEKLY_STALE). An identical week changes nothing.
 * - `set_clinic_appointment_availability_exception(p_clinic_id uuid,
 *   p_local_date date, p_exception_kind text, p_periods jsonb)` replaces that
 *   date's exception: CLOSED with `[]`, or OPEN with one or more periods.
 * - `clear_clinic_appointment_availability_exception(p_clinic_id uuid,
 *   p_local_date date)` — idempotent.
 * - `set_clinic_standard_appointment_duration(p_clinic_id uuid,
 *   p_duration_minutes integer)` — this app never sends NULL (that would stop
 *   Guardian booking, BR-62).
 *
 * Writes need APPOINTMENT_MANAGE_AVAILABILITY and PROFESSIONAL_SCHEDULING and
 * return the Clinic id. Only the weekly replacement is stale-protected;
 * exceptions and the duration are last-write-wins (BR-75). Callers re-read
 * after every write and show only the authoritative configuration.
 *
 * The read's payload is validated strictly (any violation rejects it as
 * APPOINTMENT_HOURS_MALFORMED). SQLSTATE 28000 is normalized to
 * PROFESSIONAL_CONTEXT_AUTH_REQUIRED; a read denied with 42501 — returned
 * alike for a missing capability and an unknown Clinic (migration
 * 20261014090000_professional_management_reads_without_locking.sql) — to
 * APPOINTMENT_HOURS_ACCESS_DENIED. Write errors keep the backend text for the
 * i18n mapper only; it never reaches the UI.
 * Every call settles into `{data, error}` and nothing is retried.
 */
export type AppointmentHoursResult<T> = { data: T; error: null } | { data: null; error: string };

export const APPOINTMENT_HOURS_ACCESS_DENIED = 'APPOINTMENT_HOURS_ACCESS_DENIED';
export const APPOINTMENT_HOURS_MALFORMED = 'APPOINTMENT_HOURS_MALFORMED';
export const APPOINTMENT_HOURS_INVALID_REQUEST = 'APPOINTMENT_HOURS_INVALID_REQUEST';
/** The weekly replacement was prepared from a week that has since changed. */
export const APPOINTMENT_HOURS_WEEKLY_STALE = 'APPOINTMENT_HOURS_WEEKLY_STALE';

const WEEKLY_STALE_MESSAGE = 'stale weekly clinic appointment availability revision';

/** A Clinic-local time range, as stored ("09:00:00"–"13:00:00"). */
export type TimeRange = { startTime: string; endTime: string };

export type AvailabilityPeriod = TimeRange & { isoWeekday: IsoWeekday };

/** One date's exception: CLOSED, or OPEN with its periods by start. */
export type AvailabilityException =
  { localDate: string; kind: 'CLOSED' } | { localDate: string; kind: 'OPEN'; periods: TimeRange[] };

export type ExceptionWrite = { kind: 'CLOSED' } | { kind: 'OPEN'; periods: TimeRange[] };

export type ClinicAppointmentHours = {
  /** `null` until the Clinic's scheduling timezone is configured. */
  schedulingTimezoneName: string | null;
  /** `null` when no standard duration is configured (BR-62). */
  standardAppointmentDurationMinutes: number | null;
  /** Backend order: weekday, then start. */
  recurringPeriods: AvailabilityPeriod[];
  /** Identifies exactly `recurringPeriods`; a weekly save must send it back. */
  weeklyAvailabilityRevision: number;
  /** One entry per date, by date — past dates included. */
  exceptions: AvailabilityException[];
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseRange(start: unknown, end: unknown): TimeRange | null {
  if (typeof start !== 'string' || typeof end !== 'string') return null;
  const startMicroseconds = localTimeMicroseconds(start);
  const endMicroseconds = localTimeMicroseconds(end);
  if (startMicroseconds === null || endMicroseconds === null) return null;
  if (startMicroseconds >= endMicroseconds) return null;
  return { startTime: start, endTime: end };
}

function parsePeriod(raw: unknown): AvailabilityPeriod | null {
  if (!isRecord(raw) || !isIsoWeekday(raw.iso_weekday)) return null;
  const range = parseRange(raw.start_time, raw.end_time);
  return range === null ? null : { isoWeekday: raw.iso_weekday, ...range };
}

/** Groups the flat exception rows by date; rejects a date mixing CLOSED and OPEN or repeating CLOSED. */
function parseExceptions(raw: unknown): AvailabilityException[] | null {
  if (!Array.isArray(raw)) return null;
  const byDate = new Map<string, AvailabilityException>();
  for (const item of raw) {
    if (!isRecord(item)) return null;
    const { local_date, exception_kind, start_time, end_time } = item;
    if (typeof local_date !== 'string' || !isLocalDate(local_date)) return null;
    const existing = byDate.get(local_date);

    if (exception_kind === 'CLOSED') {
      if (start_time !== null || end_time !== null || existing !== undefined) return null;
      byDate.set(local_date, { localDate: local_date, kind: 'CLOSED' });
    } else if (exception_kind === 'OPEN') {
      const range = parseRange(start_time, end_time);
      if (range === null || existing?.kind === 'CLOSED') return null;
      const periods = existing?.kind === 'OPEN' ? existing.periods : [];
      byDate.set(local_date, {
        localDate: local_date,
        kind: 'OPEN',
        periods: [...periods, range].sort(
          (a, b) =>
            (localTimeMicroseconds(a.startTime) ?? 0) - (localTimeMicroseconds(b.startTime) ?? 0),
        ),
      });
    } else {
      return null;
    }
  }
  return [...byDate.values()].sort((a, b) =>
    a.localDate < b.localDate ? -1 : a.localDate > b.localDate ? 1 : 0,
  );
}

/** Exported for unit testing: validates the read's single row. */
export function parseClinicAppointmentHours(raw: unknown): ClinicAppointmentHours | null {
  if (!Array.isArray(raw) || raw.length !== 1 || !isRecord(raw[0])) return null;
  const {
    scheduling_timezone_name,
    standard_appointment_duration_minutes,
    recurring_periods,
    exceptions,
    weekly_appointment_availability_revision,
  } = raw[0];

  if (!isWeeklyAvailabilityRevision(weekly_appointment_availability_revision)) return null;

  if (
    scheduling_timezone_name !== null &&
    (typeof scheduling_timezone_name !== 'string' || scheduling_timezone_name.length === 0)
  ) {
    return null;
  }
  if (
    standard_appointment_duration_minutes !== null &&
    (typeof standard_appointment_duration_minutes !== 'number' ||
      !isValidStandardDuration(standard_appointment_duration_minutes))
  ) {
    return null;
  }
  if (!Array.isArray(recurring_periods)) return null;

  const recurringPeriods: AvailabilityPeriod[] = [];
  for (const item of recurring_periods) {
    const period = parsePeriod(item);
    if (period === null) return null;
    recurringPeriods.push(period);
  }

  const parsedExceptions = parseExceptions(exceptions);
  if (parsedExceptions === null) return null;

  return {
    schedulingTimezoneName: scheduling_timezone_name,
    standardAppointmentDurationMinutes: standard_appointment_duration_minutes,
    recurringPeriods,
    weeklyAvailabilityRevision: weekly_appointment_availability_revision,
    exceptions: parsedExceptions,
  };
}

/** A bigint revision as PostgREST sends it: a non-negative safe integer. */
function isWeeklyAvailabilityRevision(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

// ---------------------------------------------------------------------------
// RPCs
// ---------------------------------------------------------------------------

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

function writeErrorFrom(error: { code?: string; message: string }): string {
  return error.code === '28000' ? PROFESSIONAL_CONTEXT_AUTH_REQUIRED : error.message;
}

function isValidRangeList(ranges: readonly TimeRange[]): boolean {
  return ranges.every((range) => parseRange(range.startTime, range.endTime) !== null);
}

/** Settles a write RPC that returns the Clinic id. */
async function settleWrite(
  clinicId: string,
  call: () => PromiseLike<{ data: unknown; error: { code?: string; message: string } | null }>,
): Promise<AppointmentHoursResult<null>> {
  try {
    const { data, error } = await call();
    if (error) return { data: null, error: writeErrorFrom(error) };
    if (typeof data !== 'string' || data.toLowerCase() !== clinicId.toLowerCase()) {
      return { data: null, error: APPOINTMENT_HOURS_MALFORMED };
    }
    return { data: null, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/** Reads the Clinic's current Appointment-scheduling configuration (SPEC-APT-013 BR-74). */
export async function getClinicAppointmentHours(
  clinicId: string,
): Promise<AppointmentHoursResult<ClinicAppointmentHours>> {
  if (!UUID_PATTERN.test(clinicId)) return { data: null, error: APPOINTMENT_HOURS_ACCESS_DENIED };

  try {
    const { data, error } = await supabase.rpc('get_managed_clinic_appointment_availability', {
      p_clinic_id: clinicId,
    });
    if (error) {
      if (error.code === '28000') return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      if (error.code === '42501') return { data: null, error: APPOINTMENT_HOURS_ACCESS_DENIED };
      return { data: null, error: error.message };
    }

    const hours = parseClinicAppointmentHours(data);
    if (hours === null) return { data: null, error: APPOINTMENT_HOURS_MALFORMED };
    return { data: hours, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/**
 * Replaces the Clinic's whole recurring week, provided it is still at
 * `expectedRevision` — the revision of the week the draft was prepared from.
 */
export async function replaceWeeklyAvailability(
  clinicId: string,
  periods: readonly AvailabilityPeriod[],
  expectedRevision: number,
): Promise<AppointmentHoursResult<null>> {
  if (
    !UUID_PATTERN.test(clinicId) ||
    !isWeeklyAvailabilityRevision(expectedRevision) ||
    !periods.every((period) => isIsoWeekday(period.isoWeekday)) ||
    !isValidRangeList(periods)
  ) {
    return { data: null, error: APPOINTMENT_HOURS_INVALID_REQUEST };
  }

  const result = await settleWrite(clinicId, () =>
    supabase.rpc('replace_clinic_appointment_availability', {
      p_clinic_id: clinicId,
      p_periods: periods.map((period) => ({
        iso_weekday: period.isoWeekday,
        start_time: period.startTime,
        end_time: period.endTime,
      })),
      p_expected_weekly_availability_revision: expectedRevision,
    }),
  );
  return result.error !== null && result.error.toLowerCase().includes(WEEKLY_STALE_MESSAGE)
    ? { data: null, error: APPOINTMENT_HOURS_WEEKLY_STALE }
    : result;
}

/** Establishes (replacing any existing) the exception for one Clinic-local date. */
export async function setAvailabilityException(
  clinicId: string,
  localDate: string,
  exception: ExceptionWrite,
): Promise<AppointmentHoursResult<null>> {
  if (
    !UUID_PATTERN.test(clinicId) ||
    !isLocalDate(localDate) ||
    (exception.kind === 'OPEN' &&
      (exception.periods.length === 0 || !isValidRangeList(exception.periods)))
  ) {
    return { data: null, error: APPOINTMENT_HOURS_INVALID_REQUEST };
  }

  return settleWrite(clinicId, () =>
    supabase.rpc('set_clinic_appointment_availability_exception', {
      p_clinic_id: clinicId,
      p_local_date: localDate,
      p_exception_kind: exception.kind,
      p_periods:
        exception.kind === 'OPEN'
          ? exception.periods.map((range) => ({
              start_time: range.startTime,
              end_time: range.endTime,
            }))
          : [],
    }),
  );
}

/** Removes one date's exception, restoring the normal weekly hours for it. */
export async function clearAvailabilityException(
  clinicId: string,
  localDate: string,
): Promise<AppointmentHoursResult<null>> {
  if (!UUID_PATTERN.test(clinicId) || !isLocalDate(localDate)) {
    return { data: null, error: APPOINTMENT_HOURS_INVALID_REQUEST };
  }

  return settleWrite(clinicId, () =>
    supabase.rpc('clear_clinic_appointment_availability_exception', {
      p_clinic_id: clinicId,
      p_local_date: localDate,
    }),
  );
}

/** Sets the standard Appointment duration (whole minutes, 10–240; never NULL from this app). */
export async function setStandardAppointmentDuration(
  clinicId: string,
  minutes: number,
): Promise<AppointmentHoursResult<null>> {
  if (!UUID_PATTERN.test(clinicId) || !isValidStandardDuration(minutes)) {
    return { data: null, error: APPOINTMENT_HOURS_INVALID_REQUEST };
  }

  return settleWrite(clinicId, () =>
    supabase.rpc('set_clinic_standard_appointment_duration', {
      p_clinic_id: clinicId,
      p_duration_minutes: minutes,
    }),
  );
}

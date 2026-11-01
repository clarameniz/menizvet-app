import {
  isAppointmentLifecycleState,
  type AppointmentLifecycleState,
} from '@/lib/appointment-lifecycle';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the paged Guardian Appointment reads (SPEC-APT-011 §13), migration
 * 20261117090000_guardian_appointment_paged_reads.sql:
 *
 * - `get_guardian_active_appointments(p_after_rank integer, p_after_start_at
 *   timestamptz, p_after_id uuid, p_limit integer)` — BR-38: one keyset page
 *   of the REQUESTED and CONFIRMED Appointments of every Pet the caller
 *   currently guards. Not-yet-started ones first (`active_rank` 1, start
 *   ascending), then those whose start was reached (`active_rank` 2, start
 *   descending).
 * - `get_guardian_appointment_history(p_before_start_at timestamptz,
 *   p_before_id uuid, p_limit integer)` — BR-39: one keyset page of their
 *   terminal Appointments, newest start first.
 *
 * Both return the compact row of BR-37 only (`awaiting_clinic_confirmation`
 * since 20261118090000_guardian_appointment_awaiting_clinic_confirmation.sql)
 * — no reason for visit, notes, requester, proposal content, provenance
 * identifiers or medical-access state; the detail reads those
 * through `get_pet_appointments` and re-authorizes on every visit. The backend
 * restricts to the caller's current Guardianships before ordering and cutting
 * the page; there is no Pet parameter and no denial (no Guardianship is an
 * empty page). Cursors are the complete key of the last row, sent back exactly
 * as returned (the timestamp string is never re-formatted).
 *
 * Parsing is strict: any malformed row rejects the whole page. SQLSTATE 28000
 * is normalized to GUARDIAN_APPOINTMENTS_AUTH_REQUIRED and a malformed payload
 * to GUARDIAN_APPOINTMENTS_MALFORMED. Every call settles into `{data, error}`
 * and never rejects.
 */

export type GuardianAppointmentsResult<T> =
  { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for SQLSTATE 28000 (no session, or no coherent domain User). */
export const GUARDIAN_APPOINTMENTS_AUTH_REQUIRED = 'GUARDIAN_APPOINTMENTS_AUTH_REQUIRED';

/** Normalized `error` when a page is not what this app version can represent. */
export const GUARDIAN_APPOINTMENTS_MALFORMED = 'GUARDIAN_APPOINTMENTS_MALFORMED';

/** Who proposed the Appointment's actionable pending new time (SPEC-APT-011 BR-32). */
export type ProposingContext = 'CLINIC' | 'GUARDIAN';

/** One row of either read (SPEC-APT-011 BR-37). */
export type GuardianAppointment = {
  id: string;
  petId: string;
  /** The Pet's current name. */
  petName: string;
  clinicId: string;
  lifecycleState: AppointmentLifecycleState;
  /** The relevant scheduled interval (§4), in the timezone it was established in. */
  currentScheduledStartAt: string;
  currentScheduledEndAt: string;
  currentSchedulingTimezoneName: string;
  /** `null` when no actionable pending proposal exists; always `null` in History. */
  pendingProposalContext: ProposingContext | null;
  /**
   * REQUESTED, carrying the Clinic's alternative a Guardian accepted, not yet
   * confirmed by the Clinic (SPEC-APT-011 BR-33, BR-37). Decided by the
   * backend from the interval's provenance; never inferred here.
   */
  awaitingClinicConfirmation: boolean;
};

/** An Active row (BR-38): `1` while its start is ahead, `2` once reached. */
export type GuardianActiveAppointment = GuardianAppointment & { activeRank: 1 | 2 };

/** The complete key of an Active row (BR-38), exactly as the backend returned it. */
export type ActiveCursor = { rank: 1 | 2; startAt: string; id: string };

/** The complete key of a History row (BR-39), exactly as the backend returned it. */
export type HistoryCursor = { startAt: string; id: string };

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// PostgREST serializes timestamptz as ISO 8601 with an explicit offset.
const TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;

const ACTIVE_STATES: ReadonlySet<AppointmentLifecycleState> = new Set(['REQUESTED', 'CONFIRMED']);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isTimestamp(value: unknown): value is string {
  return (
    typeof value === 'string' && TIMESTAMP_PATTERN.test(value) && Number.isFinite(Date.parse(value))
  );
}

function isTimeZone(value: unknown): value is string {
  if (!isNonEmptyString(value)) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

/** One BR-37 row, or `null`: a real interval in a valid timezone and a coherent proposal context. */
function parseRow(item: unknown): GuardianAppointment | null {
  if (!isRecord(item)) return null;
  const {
    id,
    pet_id: petId,
    pet_name: petName,
    clinic_id: clinicId,
    lifecycle_state: lifecycleState,
    current_scheduled_start_at: startAt,
    current_scheduled_end_at: endAt,
    current_scheduling_timezone_name: timeZone,
    pending_reschedule_proposing_context: context,
    awaiting_clinic_confirmation: awaiting,
  } = item;
  if (
    !isUuid(id) ||
    !isUuid(petId) ||
    !isNonEmptyString(petName) ||
    !isUuid(clinicId) ||
    !isAppointmentLifecycleState(lifecycleState) ||
    !isTimestamp(startAt) ||
    !isTimestamp(endAt) ||
    Date.parse(startAt) >= Date.parse(endAt) ||
    !isTimeZone(timeZone) ||
    (context !== null && context !== 'CLINIC' && context !== 'GUARDIAN') ||
    // An actionable proposal exists only on an active Appointment (BR-32).
    (context !== null && !ACTIVE_STATES.has(lifecycleState)) ||
    typeof awaiting !== 'boolean' ||
    // Only a request can await the Clinic's confirmation (BR-33).
    (awaiting && lifecycleState !== 'REQUESTED')
  ) {
    return null;
  }
  return {
    id,
    petId,
    petName,
    clinicId,
    lifecycleState,
    currentScheduledStartAt: startAt,
    currentScheduledEndAt: endAt,
    currentSchedulingTimezoneName: timeZone,
    pendingProposalContext: context,
    awaitingClinicConfirmation: awaiting,
  };
}

/** The rows of a page through `parseItem`, with no Appointment twice; `null` if any is malformed. */
function parsePage<T extends GuardianAppointment>(
  raw: unknown,
  parseItem: (item: unknown) => T | null,
): T[] | null {
  if (!Array.isArray(raw)) return null;
  const rows: T[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const row = parseItem(item);
    if (row === null || seen.has(row.id)) return null;
    seen.add(row.id);
    rows.push(row);
  }
  return rows;
}

/**
 * Exported for unit testing: one Active page (BR-38) — REQUESTED or CONFIRMED
 * rows only, each with rank 1 or 2, never a rank 1 after a rank 2. Anything
 * else is `null`.
 */
export function parseGuardianActivePage(raw: unknown): GuardianActiveAppointment[] | null {
  const rows = parsePage<GuardianActiveAppointment>(raw, (item) => {
    const row = parseRow(item);
    const rank = isRecord(item) ? item.active_rank : undefined;
    if (row === null || !ACTIVE_STATES.has(row.lifecycleState) || (rank !== 1 && rank !== 2)) {
      return null;
    }
    return { ...row, activeRank: rank };
  });
  if (rows === null) return null;
  const ordered = rows.every(
    (row, index) => index === 0 || rows[index - 1].activeRank <= row.activeRank,
  );
  return ordered ? rows : null;
}

/**
 * Exported for unit testing: one History page (BR-39) — terminal rows only. A
 * REQUESTED or CONFIRMED row, however late, is never history. Anything else is
 * `null`.
 */
export function parseGuardianHistoryPage(raw: unknown): GuardianAppointment[] | null {
  return parsePage(raw, (item) => {
    const row = parseRow(item);
    return row === null || ACTIVE_STATES.has(row.lifecycleState) ? null : row;
  });
}

/** The cursor that continues after `row` (BR-38). */
export function activeCursorOf(row: GuardianActiveAppointment): ActiveCursor {
  return { rank: row.activeRank, startAt: row.currentScheduledStartAt, id: row.id };
}

/** The cursor that continues after `row` (BR-39). */
export function historyCursorOf(row: GuardianAppointment): HistoryCursor {
  return { startAt: row.currentScheduledStartAt, id: row.id };
}

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

async function read<T>(
  name: string,
  args: Record<string, unknown>,
  parse: (raw: unknown) => T | null,
): Promise<GuardianAppointmentsResult<T>> {
  try {
    const { data, error } = await supabase.rpc(name, args);
    if (error) {
      return {
        data: null,
        error: error.code === '28000' ? GUARDIAN_APPOINTMENTS_AUTH_REQUIRED : error.message,
      };
    }
    const parsed = parse(data);
    if (parsed === null) return { data: null, error: GUARDIAN_APPOINTMENTS_MALFORMED };
    return { data: parsed, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/** One page of Active Appointments (SPEC-APT-011 BR-38); `after` null reads the first page. */
export function getGuardianActiveAppointments(
  after: ActiveCursor | null,
  limit: number,
): Promise<GuardianAppointmentsResult<GuardianActiveAppointment[]>> {
  return read(
    'get_guardian_active_appointments',
    {
      p_after_rank: after?.rank ?? null,
      p_after_start_at: after?.startAt ?? null,
      p_after_id: after?.id ?? null,
      p_limit: limit,
    },
    parseGuardianActivePage,
  );
}

/** One page of the Guardian History (SPEC-APT-011 BR-39); `before` null reads the first page. */
export function getGuardianAppointmentHistory(
  before: HistoryCursor | null,
  limit: number,
): Promise<GuardianAppointmentsResult<GuardianAppointment[]>> {
  return read(
    'get_guardian_appointment_history',
    {
      p_before_start_at: before?.startAt ?? null,
      p_before_id: before?.id ?? null,
      p_limit: limit,
    },
    parseGuardianHistoryPage,
  );
}

import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the Clinic side of the confirmed Appointment reschedule
 * (supabase/migrations/20261008090000_confirmed_appointment_reschedule_and_withdrawal.sql
 * and 20261015090000_unified_standard_appointment_duration.sql),
 * all granted to authenticated and all re-authorized by the backend on every
 * call — nothing here is a permission check:
 *
 * - `get_appointment_reschedule_candidate_start_times(p_appointment_id uuid,
 *   p_start_date date, p_end_date date)` (SPEC-APT-017): advisory candidate
 *   starts for one CONFIRMED Appointment, each with the end instant a proposal
 *   for it would store. The duration is the Clinic's current standard
 *   Appointment duration, applied by the backend (SPEC-APT-005 BR-24,
 *   SPEC-APT-017 BR-5); the client never computes an end. Without a configured
 *   standard duration the read and the proposal both fail with "Clinic has no
 *   currently configured standard Appointment duration". At most 60 days per
 *   call.
 * - `propose_confirmed_appointment_reschedule(p_appointment_id uuid,
 *   p_proposing_context text, p_start_local_date date, p_start_local_time time,
 *   p_start_utc_offset_seconds integer, p_reason text,
 *   p_expected_confirmed_revision_sequence integer) returns uuid`
 *   (SPEC-APT-005): start-only; always sent in the CLINIC context with a
 *   required reason (visible to the Pet's Guardians, BR-30) and the
 *   `currentScheduleRevisionSequence` of exactly the schedule row the actor
 *   reviewed (BR-26). A superseded sequence fails with P0001 "Stale confirmed
 *   Appointment schedule revision for reschedule proposal" and writes nothing.
 * - `withdraw_appointment_reschedule_proposal(p_proposal_id uuid) returns uuid`
 *   (SPEC-APT-016): withdraws an actionable Clinic proposal; no Entitlement and
 *   no Communication.
 *
 * Nothing is ever retried here. SQLSTATE 28000 is normalized to the shared
 * PROFESSIONAL_CONTEXT_AUTH_REQUIRED; every other failure keeps its stable,
 * hand-authored message for i18n/professional-reschedule-error-messages.ts
 * (the RPCs reuse 23514/42501 for several rules, so the text is the stable
 * discriminator). Every call settles into `{data, error}` and never rejects.
 */
export type ProfessionalRescheduleResult<T> =
  { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for arguments that can't be a valid request. */
export const PROFESSIONAL_RESCHEDULE_INVALID_REQUEST = 'PROFESSIONAL_RESCHEDULE_INVALID_REQUEST';

/** Normalized `error` for a payload that fails validation. */
export const PROFESSIONAL_RESCHEDULE_MALFORMED = 'PROFESSIONAL_RESCHEDULE_MALFORMED';

/** One candidate new start, exactly as the backend returned it (SPEC-APT-017 BR-8). */
export type RescheduleCandidate = {
  /** Clinic-local calendar date, "YYYY-MM-DD". */
  localDate: string;
  /** Clinic-local time, "HH:mm:ss" with optional fractional seconds. */
  localTime: string;
  /** The UTC offset that resolves the civil start unambiguously. */
  utcOffsetSeconds: number;
  /** The end instant a proposal for this start would store. */
  endAt: string;
};

// Same conventions as data/clinic-appointment-schedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;
const LOCAL_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
// PostgREST serializes `time` as HH:MM:SS, with fractional seconds when present.
const LOCAL_TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d{1,6})?$/;
// SQL bound of resolve_clinic_civil_instant: |offset| < 16 hours.
const MAX_OFFSET_SECONDS = 57599;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isPositiveInteger(value: number): boolean {
  return Number.isInteger(value) && value > 0;
}

function isLocalDate(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    LOCAL_DATE_PATTERN.test(value) &&
    Number.isFinite(Date.parse(`${value}T00:00:00Z`))
  );
}

function parseCandidate(raw: unknown): RescheduleCandidate | null {
  if (!isRecord(raw)) return null;
  const { candidate_local_date, candidate_local_time, utc_offset_seconds, candidate_end_at } = raw;
  if (
    !isLocalDate(candidate_local_date) ||
    typeof candidate_local_time !== 'string' ||
    !LOCAL_TIME_PATTERN.test(candidate_local_time) ||
    typeof utc_offset_seconds !== 'number' ||
    !Number.isInteger(utc_offset_seconds) ||
    Math.abs(utc_offset_seconds) > MAX_OFFSET_SECONDS ||
    typeof candidate_end_at !== 'string' ||
    !TIMESTAMP_PATTERN.test(candidate_end_at) ||
    !Number.isFinite(Date.parse(candidate_end_at))
  ) {
    return null;
  }
  return {
    localDate: candidate_local_date,
    localTime: candidate_local_time,
    utcOffsetSeconds: utc_offset_seconds,
    endAt: candidate_end_at,
  };
}

/**
 * Exported for unit testing: validates and reshapes the candidate rows,
 * preserving backend order. Any malformed row rejects the whole read, so a
 * candidate is never offered with a missing or invented end.
 */
export function parseRescheduleCandidates(raw: unknown): RescheduleCandidate[] | null {
  if (!Array.isArray(raw)) return null;
  const candidates: RescheduleCandidate[] = [];
  for (const item of raw) {
    const candidate = parseCandidate(item);
    if (candidate === null) return null;
    candidates.push(candidate);
  }
  return candidates;
}

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

function errorFrom(error: { code?: string; message: string }): string {
  return error.code === '28000' ? PROFESSIONAL_CONTEXT_AUTH_REQUIRED : error.message;
}

/** Reads candidate new starts for one CONFIRMED Appointment over Clinic-local dates. */
export async function getAppointmentRescheduleCandidates(
  appointmentId: string,
  startDate: string,
  endDate: string,
): Promise<ProfessionalRescheduleResult<RescheduleCandidate[]>> {
  if (!UUID_PATTERN.test(appointmentId) || !isLocalDate(startDate) || !isLocalDate(endDate)) {
    return { data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('get_appointment_reschedule_candidate_start_times', {
      p_appointment_id: appointmentId,
      p_start_date: startDate,
      p_end_date: endDate,
    });
    if (error) return { data: null, error: errorFrom(error) };

    const candidates = parseRescheduleCandidates(data);
    if (candidates === null) return { data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED };
    return { data: candidates, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

export type ClinicRescheduleProposalRequest = {
  appointmentId: string;
  candidate: RescheduleCandidate;
  reason: string;
  expectedConfirmedRevisionSequence: number;
};

/**
 * Proposes a new time in the CLINIC context for the reviewed CONFIRMED
 * Appointment: only the candidate's start travels; the backend derives and
 * stores the end. Returns the new proposal's id; callers re-read the schedule
 * for the authoritative state.
 */
export async function proposeClinicReschedule(
  request: ClinicRescheduleProposalRequest,
): Promise<ProfessionalRescheduleResult<{ proposalId: string }>> {
  const reason = request.reason.trim();
  const { candidate } = request;
  if (
    !UUID_PATTERN.test(request.appointmentId) ||
    reason.length === 0 ||
    !isPositiveInteger(request.expectedConfirmedRevisionSequence) ||
    parseCandidate({
      candidate_local_date: candidate.localDate,
      candidate_local_time: candidate.localTime,
      utc_offset_seconds: candidate.utcOffsetSeconds,
      candidate_end_at: candidate.endAt,
    }) === null
  ) {
    return { data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('propose_confirmed_appointment_reschedule', {
      p_appointment_id: request.appointmentId,
      p_proposing_context: 'CLINIC',
      p_start_local_date: candidate.localDate,
      p_start_local_time: candidate.localTime,
      p_start_utc_offset_seconds: candidate.utcOffsetSeconds,
      p_reason: reason,
      p_expected_confirmed_revision_sequence: request.expectedConfirmedRevisionSequence,
    });
    if (error) return { data: null, error: errorFrom(error) };

    if (typeof data !== 'string' || !UUID_PATTERN.test(data)) {
      return { data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED };
    }
    return { data: { proposalId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/** Withdraws an actionable Clinic-originated proposal (SPEC-APT-016). */
export async function withdrawRescheduleProposal(
  proposalId: string,
): Promise<ProfessionalRescheduleResult<{ proposalId: string }>> {
  if (!UUID_PATTERN.test(proposalId)) {
    return { data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('withdraw_appointment_reschedule_proposal', {
      p_proposal_id: proposalId,
    });
    if (error) return { data: null, error: errorFrom(error) };

    if (typeof data !== 'string' || data.toLowerCase() !== proposalId.toLowerCase()) {
      return { data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED };
    }
    return { data: { proposalId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

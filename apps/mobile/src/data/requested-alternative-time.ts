import {
  PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
  PROFESSIONAL_RESCHEDULE_MALFORMED,
  parseRescheduleCandidates,
  type ProfessionalRescheduleResult,
  type RescheduleCandidate,
} from '@/data/professional-appointment-reschedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the Clinic side of the REQUESTED Appointment Alternative Time
 * (supabase/migrations/20261010090000_requested_appointment_alternative_time.sql),
 * granted to authenticated and re-authorized by the backend on every call —
 * nothing here is a permission check:
 *
 * - `get_requested_appointment_alternative_candidate_start_times(p_appointment_id
 *   uuid, p_start_date date, p_end_date date)` (SPEC-APT-020): advisory
 *   candidate starts for one future REQUESTED Appointment, each with the end a
 *   proposal for it would store. The duration is the Clinic's current standard
 *   duration, applied by the backend; the client never computes an end. At most
 *   60 days per call, with no business horizon.
 * - `propose_requested_appointment_alternative_time(p_appointment_id uuid,
 *   p_start_local_date date, p_start_local_time time,
 *   p_start_utc_offset_seconds integer, p_reason text,
 *   p_expected_requested_revision_sequence integer) returns uuid`
 *   (SPEC-APT-018): Clinic only, start only, a required reason (visible to the
 *   Pet's Guardians), and the `currentScheduleRevisionSequence` of exactly the
 *   schedule row the actor reviewed. A superseded sequence fails with P0001
 *   "Stale requested Appointment schedule revision for alternative time
 *   proposal" and writes nothing.
 *
 * Withdrawal reuses `withdrawRescheduleProposal` (SPEC-APT-016 generalized).
 * Same candidate payload, normalization, and conventions as
 * data/professional-appointment-reschedule.ts; nothing is ever retried, and
 * every call settles into `{data, error}`.
 */

// Same conventions as data/professional-appointment-reschedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCAL_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function isLocalDate(value: string): boolean {
  return LOCAL_DATE_PATTERN.test(value) && Number.isFinite(Date.parse(`${value}T00:00:00Z`));
}

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

function errorFrom(error: { code?: string; message: string }): string {
  return error.code === '28000' ? PROFESSIONAL_CONTEXT_AUTH_REQUIRED : error.message;
}

/** Reads candidate alternative starts for one REQUESTED Appointment over Clinic-local dates. */
export async function getRequestedAlternativeCandidates(
  appointmentId: string,
  startDate: string,
  endDate: string,
): Promise<ProfessionalRescheduleResult<RescheduleCandidate[]>> {
  if (!UUID_PATTERN.test(appointmentId) || !isLocalDate(startDate) || !isLocalDate(endDate)) {
    return { data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc(
      'get_requested_appointment_alternative_candidate_start_times',
      { p_appointment_id: appointmentId, p_start_date: startDate, p_end_date: endDate },
    );
    if (error) return { data: null, error: errorFrom(error) };

    const candidates = parseRescheduleCandidates(data);
    if (candidates === null) return { data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED };
    return { data: candidates, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

export type AlternativeTimeProposalRequest = {
  appointmentId: string;
  candidate: RescheduleCandidate;
  reason: string;
  expectedRequestedRevisionSequence: number;
};

/**
 * Proposes an alternative time for the reviewed REQUESTED Appointment: only the
 * candidate's start travels; the backend derives and freezes the end. Returns
 * the new proposal's id; callers re-read the schedule for the authoritative
 * state.
 */
export async function proposeRequestedAlternativeTime(
  request: AlternativeTimeProposalRequest,
): Promise<ProfessionalRescheduleResult<{ proposalId: string }>> {
  const reason = request.reason.trim();
  const { candidate } = request;
  if (
    !UUID_PATTERN.test(request.appointmentId) ||
    reason.length === 0 ||
    !Number.isInteger(request.expectedRequestedRevisionSequence) ||
    request.expectedRequestedRevisionSequence <= 0 ||
    parseRescheduleCandidates([
      {
        candidate_local_date: candidate.localDate,
        candidate_local_time: candidate.localTime,
        utc_offset_seconds: candidate.utcOffsetSeconds,
        candidate_end_at: candidate.endAt,
      },
    ]) === null
  ) {
    return { data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('propose_requested_appointment_alternative_time', {
      p_appointment_id: request.appointmentId,
      p_start_local_date: candidate.localDate,
      p_start_local_time: candidate.localTime,
      p_start_utc_offset_seconds: candidate.utcOffsetSeconds,
      p_reason: reason,
      p_expected_requested_revision_sequence: request.expectedRequestedRevisionSequence,
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

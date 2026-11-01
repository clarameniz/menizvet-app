import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the CLINIC context of the SPEC-APT-003 mutation
 * `public.cancel_appointment(p_appointment_id uuid, p_cancelling_context text,
 * p_reason text default null,
 * p_expected_schedule_revision_sequence integer default null) returns uuid`
 * (supabase/migrations/20261006090000_stale_safe_clinic_appointment_cancellation.sql).
 * Granted to authenticated. The backend re-authorizes everything on every
 * call — APPOINTMENT_CANCEL for the Appointment's Clinic (deliberately without
 * an Entitlement gate), lifecycle, the pending-request rule, and the absence of
 * clinical records — so nothing here is a permission check.
 *
 * Professional-only: always sends `p_cancelling_context: 'CLINIC'`. The
 * Guardian cancellation in data/appointments.ts is a separate wrapper with its
 * own copy and never sends a revision sequence.
 *
 * Stale-safe (SPEC-APT-003 BR-24–BR-27): the caller sends the
 * `currentScheduleRevisionSequence` of exactly the schedule row the actor
 * reviewed. If that Appointment's scheduling context has changed since, the
 * backend rejects with P0001 "Stale Appointment schedule revision for
 * cancellation" and writes nothing. A failed cancellation is never retried here.
 *
 * A successful cancellation atomically ends the Appointment's Care
 * Authorization and enqueues the APPOINTMENT_CANCELLED Communications
 * server-side; the client never sends any notification.
 *
 * SQLSTATE 28000 is normalized to the shared PROFESSIONAL_CONTEXT_AUTH_REQUIRED.
 * Every other backend failure keeps its stable, hand-authored message for
 * i18n/professional-appointment-cancellation-error-messages.ts to map (the RPC
 * reuses 23514 for several unrelated rules, so the message text is the stable
 * discriminator). Every call settles into `{data, error}` and never rejects.
 */
export type ProfessionalCancellationResult<T> =
  { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for arguments that can't be a valid Clinic cancellation request. */
export const PROFESSIONAL_CANCELLATION_INVALID_REQUEST =
  'PROFESSIONAL_CANCELLATION_INVALID_REQUEST';

/** Normalized `error` for a success payload that isn't the cancelled Appointment's id. */
export const PROFESSIONAL_CANCELLATION_MALFORMED = 'PROFESSIONAL_CANCELLATION_MALFORMED';

// Same UUID convention as data/clinic-appointment-schedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/**
 * Cancels an Appointment in the Clinic context exactly as reviewed, with the
 * actor's (trimmed, required) reason. Returns the Appointment's id; callers
 * re-read the schedule for the authoritative state rather than marking
 * anything CANCELLED locally.
 */
export async function cancelProfessionalAppointment(
  appointmentId: string,
  reason: string,
  expectedScheduleRevisionSequence: number,
): Promise<ProfessionalCancellationResult<{ appointmentId: string }>> {
  const trimmedReason = reason.trim();
  if (
    !UUID_PATTERN.test(appointmentId) ||
    trimmedReason.length === 0 ||
    !Number.isInteger(expectedScheduleRevisionSequence) ||
    expectedScheduleRevisionSequence <= 0
  ) {
    return { data: null, error: PROFESSIONAL_CANCELLATION_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('cancel_appointment', {
      p_appointment_id: appointmentId,
      p_cancelling_context: 'CLINIC',
      p_reason: trimmedReason,
      p_expected_schedule_revision_sequence: expectedScheduleRevisionSequence,
    });

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      return { data: null, error: error.message };
    }

    if (typeof data !== 'string' || data.toLowerCase() !== appointmentId.toLowerCase()) {
      return { data: null, error: PROFESSIONAL_CANCELLATION_MALFORMED };
    }

    return { data: { appointmentId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

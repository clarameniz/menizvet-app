import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the SPEC-APT-009 mutation
 * `public.complete_appointment(p_appointment_id uuid,
 * p_expected_confirmed_revision_sequence integer) returns uuid`
 * (supabase/migrations/20261011090000_lightweight_appointment_completion.sql).
 * Granted to authenticated. The backend re-authorizes everything on every
 * call — APPOINTMENT_COMPLETE for the Appointment's Clinic (deliberately
 * without an Entitlement gate), lifecycle, and the reached confirmed start —
 * so nothing here is a permission check.
 *
 * Completion is the Clinic's administrative assertion that the visit occurred
 * (SPEC-APT-009 BR-1). It needs no Veterinarian Assignment or clinical
 * record, and none is sent. It also ends the Appointment's prior-history access
 * server-side (SPEC-MED-010 BR-16); documentation stays possible.
 *
 * Stale-safe (SPEC-APT-009 BR-8/BR-9/BR-10): the caller sends the
 * `currentScheduleRevisionSequence` of exactly the CONFIRMED schedule row the
 * actor reviewed. If the confirmed time has changed since, the backend rejects
 * with P0001 "Stale confirmed Appointment schedule revision" and writes
 * nothing. A stale or otherwise failed completion is never retried here.
 *
 * A successful completion enqueues the APPOINTMENT_COMPLETED Communications
 * server-side; the client never sends any notification.
 *
 * SQLSTATE 28000 is normalized to the shared PROFESSIONAL_CONTEXT_AUTH_REQUIRED.
 * Every other backend failure keeps its stable, hand-authored message for
 * i18n/appointment-completion-error-messages.ts to map (the RPC reuses 23514
 * for several unrelated rules, so the message text is the stable
 * discriminator). Every call settles into `{data, error}` and never rejects.
 */
export type AppointmentCompletionResult<T> =
  { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for arguments that can't be a valid completion request. */
export const APPOINTMENT_COMPLETION_INVALID_REQUEST = 'APPOINTMENT_COMPLETION_INVALID_REQUEST';

/** Normalized `error` for a success payload that isn't the completed Appointment's id. */
export const APPOINTMENT_COMPLETION_MALFORMED = 'APPOINTMENT_COMPLETION_MALFORMED';

// Same UUID convention as data/clinic-appointment-schedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/**
 * Completes a CONFIRMED Appointment exactly as reviewed. Returns the
 * Appointment's id; callers re-read the schedule for the authoritative state
 * rather than marking anything COMPLETED locally.
 */
export async function completeAppointment(
  appointmentId: string,
  expectedConfirmedRevisionSequence: number,
): Promise<AppointmentCompletionResult<{ appointmentId: string }>> {
  if (
    !UUID_PATTERN.test(appointmentId) ||
    !Number.isInteger(expectedConfirmedRevisionSequence) ||
    expectedConfirmedRevisionSequence <= 0
  ) {
    return { data: null, error: APPOINTMENT_COMPLETION_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('complete_appointment', {
      p_appointment_id: appointmentId,
      p_expected_confirmed_revision_sequence: expectedConfirmedRevisionSequence,
    });

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      return { data: null, error: error.message };
    }

    if (typeof data !== 'string' || data.toLowerCase() !== appointmentId.toLowerCase()) {
      return { data: null, error: APPOINTMENT_COMPLETION_MALFORMED };
    }

    return { data: { appointmentId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the SPEC-APT-010 mutation
 * `public.mark_appointment_no_show(p_appointment_id uuid,
 * p_expected_confirmed_revision_sequence integer) returns uuid`
 * (supabase/migrations/20261005090000_stale_safe_appointment_no_show.sql).
 * Granted to authenticated. The backend re-authorizes everything on every
 * call — APPOINTMENT_MARK_NO_SHOW for the Appointment's Clinic (deliberately
 * without an Entitlement gate), lifecycle, the reached confirmed start, and
 * the absence of clinical records — so nothing here is a permission check.
 *
 * Stale-safe (SPEC-APT-010 BR-41/BR-42/BR-43): the caller sends the
 * `currentScheduleRevisionSequence` of exactly the CONFIRMED schedule row the
 * actor reviewed. If the confirmed time has changed since, the backend rejects
 * with P0001 "Stale confirmed Appointment schedule revision" and writes
 * nothing. A stale or otherwise failed no-show is never retried here.
 *
 * A successful no-show atomically ends the Appointment's Care Authorization
 * and enqueues the APPOINTMENT_NO_SHOW Communications server-side; the client
 * never sends any notification.
 *
 * SQLSTATE 28000 is normalized to the shared PROFESSIONAL_CONTEXT_AUTH_REQUIRED.
 * Every other backend failure keeps its stable, hand-authored message for
 * i18n/appointment-no-show-error-messages.ts to map (the RPC reuses 23514 for
 * several unrelated rules, so the message text is the stable discriminator).
 * Every call settles into `{data, error}` and never rejects.
 */
export type AppointmentNoShowResult<T> = { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for arguments that can't be a valid no-show request. */
export const APPOINTMENT_NO_SHOW_INVALID_REQUEST = 'APPOINTMENT_NO_SHOW_INVALID_REQUEST';

/** Normalized `error` for a success payload that isn't the marked Appointment's id. */
export const APPOINTMENT_NO_SHOW_MALFORMED = 'APPOINTMENT_NO_SHOW_MALFORMED';

// Same UUID convention as data/clinic-appointment-schedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/**
 * Marks a CONFIRMED Appointment as NO_SHOW exactly as reviewed. Returns the
 * Appointment's id; callers re-read the schedule for the authoritative state
 * rather than marking anything NO_SHOW locally.
 */
export async function markAppointmentNoShow(
  appointmentId: string,
  expectedConfirmedRevisionSequence: number,
): Promise<AppointmentNoShowResult<{ appointmentId: string }>> {
  if (
    !UUID_PATTERN.test(appointmentId) ||
    !Number.isInteger(expectedConfirmedRevisionSequence) ||
    expectedConfirmedRevisionSequence <= 0
  ) {
    return { data: null, error: APPOINTMENT_NO_SHOW_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('mark_appointment_no_show', {
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
      return { data: null, error: APPOINTMENT_NO_SHOW_MALFORMED };
    }

    return { data: { appointmentId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

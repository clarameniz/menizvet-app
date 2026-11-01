import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the deployed SPEC-APT-002 mutation
 * `public.confirm_appointment(p_appointment_id uuid,
 * p_expected_requested_revision_sequence integer) returns uuid`
 * (supabase/migrations/20261003090000_stale_safe_appointment_confirmation.sql).
 * Granted to authenticated. The backend re-authorizes everything on every
 * call — APPOINTMENT_CONFIRM for the Appointment's Clinic, the Organization's
 * APPOINTMENT_MANAGEMENT Entitlement, lifecycle, future time, Clinic
 * Availability, and any assigned Veterinarian — so nothing here is a
 * permission check.
 *
 * Stale-safe (SPEC-APT-002 BR-21/BR-22/BR-23): the caller sends the
 * `currentScheduleRevisionSequence` of exactly the schedule row the actor
 * reviewed. If the Appointment's requested time has changed since, the backend
 * rejects with P0001 "Stale requested Appointment schedule revision" and writes
 * nothing. A stale or otherwise failed confirmation is never retried here.
 *
 * Successful confirmation atomically enqueues the APPOINTMENT_CONFIRMED
 * Communications server-side; the client never sends any notification.
 *
 * SQLSTATE 28000 is normalized to the shared PROFESSIONAL_CONTEXT_AUTH_REQUIRED.
 * Every other backend failure keeps its stable, hand-authored message for
 * i18n/appointment-confirmation-error-messages.ts to map (the RPC reuses
 * 23514 for several unrelated rules, so the message text is the stable
 * discriminator — the same precedent as i18n/appointment-error-messages.ts).
 * Every call settles into `{data, error}` and never rejects.
 */
export type AppointmentConfirmationResult<T> =
  { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for arguments that can't be a valid confirmation request. */
export const APPOINTMENT_CONFIRMATION_INVALID_REQUEST = 'APPOINTMENT_CONFIRMATION_INVALID_REQUEST';

/** Normalized `error` for a success payload that isn't the confirmed Appointment's id. */
export const APPOINTMENT_CONFIRMATION_MALFORMED = 'APPOINTMENT_CONFIRMATION_MALFORMED';

// Same UUID convention as data/clinic-appointment-schedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/**
 * Confirms a REQUESTED Appointment exactly as reviewed. Returns the confirmed
 * Appointment's id; callers re-read the schedule for the authoritative state
 * rather than marking anything CONFIRMED locally.
 */
export async function confirmAppointment(
  appointmentId: string,
  expectedRequestedRevisionSequence: number,
): Promise<AppointmentConfirmationResult<{ appointmentId: string }>> {
  if (
    !UUID_PATTERN.test(appointmentId) ||
    !Number.isInteger(expectedRequestedRevisionSequence) ||
    expectedRequestedRevisionSequence <= 0
  ) {
    return { data: null, error: APPOINTMENT_CONFIRMATION_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('confirm_appointment', {
      p_appointment_id: appointmentId,
      p_expected_requested_revision_sequence: expectedRequestedRevisionSequence,
    });

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      return { data: null, error: error.message };
    }

    if (typeof data !== 'string' || data.toLowerCase() !== appointmentId.toLowerCase()) {
      return { data: null, error: APPOINTMENT_CONFIRMATION_MALFORMED };
    }

    return { data: { appointmentId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

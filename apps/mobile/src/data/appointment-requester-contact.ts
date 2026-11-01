import { supabase } from '@/lib/supabase';

/**
 * Mirrors the SPEC-APT-012 BR-50 read
 * `public.get_clinic_appointment_requester_contact(p_clinic_id uuid,
 * p_appointment_id uuid)` from
 * supabase/migrations/20261107090000_appointment_requester_contact.sql
 * (SPEC-ID-006 BR-42). Granted to authenticated; the backend re-authorizes the
 * caller (`APPOINTMENT_VIEW_SCHEDULE` for that Clinic) and checks that the
 * Appointment belongs to it on every call. Returns exactly one row:
 *
 *   requester_display_name text | null, requester_email text | null
 *
 * — the original requester's current display name and current verified
 * email, in every lifecycle state, not necessarily a current Guardian. Read
 * for one Appointment at a time (the detail), never for the whole schedule.
 *
 * SQLSTATE 28000 is `authenticationRequired`; the uniform 42501 (unknown or
 * foreign Clinic/Appointment, or no current authority) is `accessDenied`;
 * anything else, including a malformed payload, is `unavailable`. The email is
 * never logged or put in an error. Never rejects.
 */
export type AppointmentRequesterContact = {
  displayName: string | null;
  email: string | null;
};

export type AppointmentRequesterContactResult =
  | { kind: 'contact'; contact: AppointmentRequesterContact }
  | { kind: 'accessDenied' }
  | { kind: 'authenticationRequired' }
  | { kind: 'unavailable' };

const isNullableNonBlank = (value: unknown): value is string | null =>
  value === null || (typeof value === 'string' && value.trim() !== '');

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** Exported for unit testing: exactly one well-formed row, otherwise `null`. */
export function parseAppointmentRequesterContact(raw: unknown): AppointmentRequesterContact | null {
  if (!Array.isArray(raw) || raw.length !== 1 || !isRecord(raw[0])) return null;
  const { requester_display_name, requester_email } = raw[0];
  if (!isNullableNonBlank(requester_display_name) || !isNullableNonBlank(requester_email))
    return null;
  return { displayName: requester_display_name, email: requester_email };
}

export async function getClinicAppointmentRequesterContact(
  clinicId: string,
  appointmentId: string,
): Promise<AppointmentRequesterContactResult> {
  try {
    const { data, error } = await supabase.rpc('get_clinic_appointment_requester_contact', {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
    });
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '42501') return { kind: 'accessDenied' };
      return { kind: 'unavailable' };
    }
    const contact = parseAppointmentRequesterContact(data);
    return contact === null ? { kind: 'unavailable' } : { kind: 'contact', contact };
  } catch {
    return { kind: 'unavailable' };
  }
}

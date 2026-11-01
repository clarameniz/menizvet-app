import {
  APPOINTMENT_HOURS_ACCESS_DENIED,
  APPOINTMENT_HOURS_INVALID_REQUEST,
  APPOINTMENT_HOURS_WEEKLY_STALE,
} from '@/data/clinic-appointment-hours';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Copy for Clinic Appointment hours management (SPEC-APT-013 BR-72–BR-75).
 * The write RPCs reuse SQLSTATEs 42501/22023/23514 for several rules (42501
 * is both a missing capability and a missing PROFESSIONAL_SCHEDULING
 * Entitlement), so — as in every other mapper — this matches the stable,
 * hand-authored message text of
 * supabase/migrations/20260826140000_scheduling_configuration.sql,
 * 20260826090643_clinic_configuration_and_spatial_support.sql, and
 * 20260920120000_standard_appointment_duration_and_candidate_times.sql.
 *
 * Every write outcome is followed by a re-read by the caller; this module
 * only chooses the copy. Raw backend text never reaches product UI.
 */
const SAVE_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'applicable appointment availability-management capability is required',
    key: 'appointmentHours.accessLost',
  },
  {
    substring: 'applicable clinic-management capability is required',
    key: 'appointmentHours.accessLost',
  },
  { substring: 'clinic does not exist', key: 'appointmentHours.accessLost' },
  {
    substring: 'professional scheduling entitlement is required',
    key: 'appointmentHours.entitlementDenied',
  },
  { substring: 'must not overlap', key: 'appointmentHours.overlapError' },
  { substring: 'must not contain duplicates', key: 'appointmentHours.duplicateError' },
  { substring: 'requires a valid scheduling timezone', key: 'appointmentHours.timezoneMissing' },
  { substring: 'between 10 and 240 minutes', key: 'appointmentHours.durationInvalid' },
  { substring: 'valid iso local-time representation', key: 'appointmentHours.invalidInput' },
  { substring: 'start_time before end_time', key: 'appointmentHours.invalidInput' },
  { substring: 'iso weekday must be between 1 and 7', key: 'appointmentHours.invalidInput' },
  { substring: 'must be a json', key: 'appointmentHours.invalidInput' },
  { substring: 'unsupported member', key: 'appointmentHours.invalidInput' },
  { substring: 'requires valid', key: 'appointmentHours.invalidInput' },
  { substring: 'kind must be closed or open', key: 'appointmentHours.invalidInput' },
  { substring: 'must be a finite date', key: 'appointmentHours.invalidInput' },
  { substring: 'local date is required', key: 'appointmentHours.invalidInput' },
  { substring: 'requires at least one period', key: 'appointmentHours.invalidInput' },
  { substring: 'must not contain periods', key: 'appointmentHours.invalidInput' },
];

/** Copy for a failed configuration change. */
export function mapAppointmentHoursSaveErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';
  if (error === APPOINTMENT_HOURS_INVALID_REQUEST) return 'appointmentHours.invalidInput';
  if (error === APPOINTMENT_HOURS_WEEKLY_STALE) return 'appointmentHours.weeklyStale';
  const lowerError = error.toLowerCase();
  for (const { substring, key } of SAVE_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }
  return 'appointmentHours.saveFailed';
}

/** Copy for a failed configuration read. */
export function mapAppointmentHoursLoadErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';
  if (error === APPOINTMENT_HOURS_ACCESS_DENIED) return 'appointmentHours.accessLost';
  return 'appointmentHours.loadError';
}

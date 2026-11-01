import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Professional (Clinic-side) copy for a failed `confirmAppointment`
 * (SPEC-APT-002). Deliberately separate from the Guardian
 * i18n/appointment-error-messages.ts: the same backend condition means
 * something different to a Clinic actor (e.g. an Entitlement denial is about
 * the actor's own Organization plan, not a Clinic that can't take requests).
 *
 * `confirm_appointment` reuses SQLSTATE 23514 for several unrelated rules and
 * 42501 for both capability and Entitlement, so — as in the Guardian mapper —
 * this matches the stable, hand-authored message text
 * (supabase/migrations/20261003090000_stale_safe_appointment_confirmation.sql).
 * The three assigned-Veterinarian failures (no longer a valid Clinic
 * Assignment, not available, deferred cross-Clinic commitment conflict) share
 * one calm message: this slice offers no assignment workflow to act on them.
 *
 * Every outcome is followed by a schedule re-read by the caller; this module
 * only chooses the copy. Raw backend text never reaches product UI.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'applicable appointment-management capability is required',
    key: 'appointmentConfirmation.accessLost',
  },
  {
    substring: 'applicable professional entitlement is required',
    key: 'appointmentConfirmation.entitlementDenied',
  },
  {
    substring: 'stale requested appointment schedule revision',
    key: 'appointmentConfirmation.staleRequest',
  },
  {
    substring: 'only a requested appointment may be confirmed',
    key: 'appointmentConfirmation.lifecycleChanged',
  },
  {
    substring: 'a past requested appointment cannot be confirmed',
    key: 'appointmentConfirmation.timePassed',
  },
  {
    substring: 'clinic appointment availability does not cover the requested interval',
    key: 'appointmentConfirmation.timeUnavailable',
  },
  {
    substring: 'currently assigned veterinarian',
    key: 'appointmentConfirmation.veterinarianUnavailable',
  },
  {
    substring: 'conflicting confirmed appointment commitments',
    key: 'appointmentConfirmation.veterinarianUnavailable',
  },
];

export function mapAppointmentConfirmationErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';

  const lowerError = error.toLowerCase();
  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }

  return 'appointmentConfirmation.failed';
}

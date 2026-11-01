import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Professional (Clinic-side) copy for a failed `cancelProfessionalAppointment`
 * (SPEC-APT-003). Deliberately separate from the Guardian
 * i18n/appointment-error-messages.ts: the same backend condition reads
 * differently to a Clinic actor. `cancel_appointment` reuses SQLSTATE 23514
 * for several unrelated rules, so — as in the confirmation and no-show
 * mappers — this matches the stable, hand-authored message text
 * (supabase/migrations/20261006090000_stale_safe_clinic_appointment_cancellation.sql).
 * Clinic cancellation has no Entitlement gate, so 42501 only ever means the
 * actor lost APPOINTMENT_CANCEL for this Clinic.
 *
 * Every outcome is followed by a schedule re-read by the caller; this module
 * only chooses the copy. Raw backend text never reaches product UI.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'applicable clinic-management capability is required',
    key: 'professionalCancellation.accessLost',
  },
  {
    substring: 'stale appointment schedule revision for cancellation',
    key: 'professionalCancellation.staleSchedule',
  },
  {
    substring: 'only a requested or confirmed appointment may be cancelled',
    key: 'professionalCancellation.lifecycleChanged',
  },
  {
    substring: 'a requested appointment whose requested time has passed cannot be cancelled',
    key: 'professionalCancellation.requestExpired',
  },
  {
    substring: 'appointment with clinical documentation cannot be cancelled',
    key: 'professionalCancellation.documented',
  },
  {
    substring: 'a meaningful reason is required for a clinic cancellation',
    key: 'professionalCancellation.reasonMissing',
  },
];

export function mapProfessionalCancellationErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';

  const lowerError = error.toLowerCase();
  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }

  return 'professionalCancellation.failed';
}

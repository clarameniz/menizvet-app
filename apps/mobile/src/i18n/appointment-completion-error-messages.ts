import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Professional (Clinic-side) copy for a failed `completeAppointment`
 * (SPEC-APT-009). `complete_appointment` reuses SQLSTATE 23514 for several
 * unrelated rules, so — as in i18n/appointment-no-show-error-messages.ts —
 * this matches the stable, hand-authored message text
 * (supabase/migrations/20261011090000_lightweight_appointment_completion.sql).
 * The operation has no Entitlement gate, so 42501 only ever means the actor
 * lost APPOINTMENT_COMPLETE for this Clinic.
 *
 * Every outcome is followed by a schedule re-read by the caller; this module
 * only chooses the copy. Raw backend text never reaches product UI.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'applicable clinic-management capability is required',
    key: 'appointmentCompletion.accessLost',
  },
  {
    substring: 'stale confirmed appointment schedule revision',
    key: 'appointmentCompletion.staleSchedule',
  },
  {
    substring: 'only a confirmed appointment may be completed',
    key: 'appointmentCompletion.lifecycleChanged',
  },
  {
    substring: 'cannot be completed before its confirmed scheduled start',
    key: 'appointmentCompletion.tooEarly',
  },
];

export function mapAppointmentCompletionErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';

  const lowerError = error.toLowerCase();
  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }

  return 'appointmentCompletion.failed';
}

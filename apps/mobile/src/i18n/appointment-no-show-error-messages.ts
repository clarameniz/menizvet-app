import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Professional (Clinic-side) copy for a failed `markAppointmentNoShow`
 * (SPEC-APT-010). `mark_appointment_no_show` reuses SQLSTATE 23514 for several
 * unrelated rules, so — as in i18n/appointment-confirmation-error-messages.ts —
 * this matches the stable, hand-authored message text
 * (supabase/migrations/20261005090000_stale_safe_appointment_no_show.sql).
 * The operation has no Entitlement gate, so 42501 only ever means the actor
 * lost APPOINTMENT_MARK_NO_SHOW for this Clinic.
 *
 * Every outcome is followed by a schedule re-read by the caller; this module
 * only chooses the copy. Raw backend text never reaches product UI.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'applicable clinic-management capability is required',
    key: 'appointmentNoShow.accessLost',
  },
  {
    substring: 'stale confirmed appointment schedule revision',
    key: 'appointmentNoShow.staleSchedule',
  },
  {
    substring: 'only a confirmed appointment may be marked no-show',
    key: 'appointmentNoShow.lifecycleChanged',
  },
  {
    substring: 'cannot be marked no-show before its confirmed scheduled start',
    key: 'appointmentNoShow.tooEarly',
  },
  {
    substring: 'appointment with clinical documentation cannot be marked no-show',
    key: 'appointmentNoShow.documented',
  },
];

export function mapAppointmentNoShowErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';

  const lowerError = error.toLowerCase();
  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }

  return 'appointmentNoShow.failed';
}

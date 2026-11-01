import { GUARDIAN_APPOINTMENTS_AUTH_REQUIRED } from '@/data/guardian-appointments';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * The paged "My appointments" reads (data/guardian-appointments.ts) fail only
 * for a lost session (28000, normalized) or for infrastructure reasons — they
 * have no denial — so a session loss gets the shared session-expired copy and
 * everything else the list's calm load error. Raw backend text never reaches
 * product UI.
 */
export function mapGuardianAppointmentsErrorToKey(error: string): TranslationKey {
  return error === GUARDIAN_APPOINTMENTS_AUTH_REQUIRED
    ? 'errors.sessionExpired'
    : 'appointments.loadError';
}

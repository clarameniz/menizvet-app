import { CLINIC_SCHEDULE_ACCESS_DENIED } from '@/data/clinic-appointment-schedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * `getMyProfessionalContext` and `getMyProfessionalClinics` both normalize
 * SQLSTATE 28000 (no authenticated subject / no coherent domain User) to
 * PROFESSIONAL_CONTEXT_AUTH_REQUIRED, which resolves to the same shared
 * session-expired copy used by the Appointment and clinical-history mappers.
 * Everything else — a malformed payload, a network failure, any other
 * Postgres error — falls back to the screen's calm generic load error; raw
 * backend text never reaches product UI.
 */
function mapWithFallback(error: string, fallback: TranslationKey): TranslationKey {
  return error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED ? 'errors.sessionExpired' : fallback;
}

export function mapProfessionalContextErrorToKey(error: string): TranslationKey {
  return mapWithFallback(error, 'professional.loadError');
}

export function mapProfessionalClinicsErrorToKey(error: string): TranslationKey {
  return mapWithFallback(error, 'professionalClinics.loadError');
}

/**
 * The Clinic Appointment reads additionally normalize SQLSTATE 42501 (no
 * current schedule-view authority for the Clinic) to
 * CLINIC_SCHEDULE_ACCESS_DENIED, shown as a calm access message rather than a
 * retryable load error.
 */
export function mapClinicScheduleErrorToKey(error: string): TranslationKey {
  if (error === CLINIC_SCHEDULE_ACCESS_DENIED) return 'clinicSchedule.accessError';
  return mapWithFallback(error, 'clinicSchedule.loadError');
}

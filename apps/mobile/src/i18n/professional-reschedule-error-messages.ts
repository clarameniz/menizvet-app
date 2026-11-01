import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Professional (Clinic-side) copy for a failed reschedule candidate read,
 * Clinic proposal, or withdrawal (SPEC-APT-005/016/017). The RPCs reuse
 * SQLSTATEs 23514/42501/22023 for several unrelated rules, so — as in the
 * confirmation, no-show, and cancellation mappers — this matches the stable,
 * hand-authored message text
 * (supabase/migrations/20261008090000_confirmed_appointment_reschedule_and_withdrawal.sql,
 * 20261015090000_unified_standard_appointment_duration.sql, and the Slice 9
 * authorization helpers). A Veterinarian conflict and missing
 * Veterinarian Availability share one backend message by design
 * (SPEC-APT-005 BR-28), so the copy never hints at another commitment.
 *
 * Every outcome is followed by a re-read by the caller; this module only
 * chooses the copy. Raw backend text never reaches product UI.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'stale confirmed appointment schedule revision for reschedule proposal',
    key: 'professionalReschedule.staleSchedule',
  },
  {
    substring: 'applicable appointment-management capability is required',
    key: 'professionalReschedule.accessLost',
  },
  {
    substring: 'applicable clinic-management capability is required',
    key: 'professionalReschedule.accessLost',
  },
  {
    substring: 'applicable professional entitlement is required',
    key: 'professionalReschedule.entitlementDenied',
  },
  {
    substring: 'only a confirmed appointment may receive a reschedule proposal',
    key: 'professionalReschedule.lifecycleChanged',
  },
  {
    substring: 'the current confirmed appointment time must still be in the future',
    key: 'professionalReschedule.startPassed',
  },
  {
    substring: 'appointment with clinical documentation cannot be rescheduled',
    key: 'professionalReschedule.documented',
  },
  {
    substring: 'clinic has no currently configured standard appointment duration',
    key: 'professionalReschedule.noStandardDuration',
  },
  {
    substring: 'already has an actionable unresolved reschedule proposal',
    key: 'professionalReschedule.pendingExists',
  },
  {
    substring: 'proposed time must differ from the current confirmed time',
    key: 'professionalReschedule.sameTime',
  },
  {
    substring: 'clinic appointment availability does not cover',
    key: 'professionalReschedule.timeUnavailable',
  },
  {
    substring: 'proposed appointment time must be in the future',
    key: 'professionalReschedule.timeUnavailable',
  },
  {
    substring: 'do not identify a valid occurrence of local civil time',
    key: 'professionalReschedule.timeUnavailable',
  },
  {
    substring: 'currently assigned veterinarian',
    key: 'professionalReschedule.veterinarianUnavailable',
  },
  {
    substring: 'a meaningful reason is required for a clinic-proposed reschedule',
    key: 'professionalReschedule.reasonMissing',
  },
  {
    substring: 'reschedule proposal is no longer actionable',
    key: 'professionalReschedule.proposalNoLongerPending',
  },
  {
    substring: 'only a clinic-originated reschedule proposal may be withdrawn',
    key: 'professionalReschedule.proposalNoLongerPending',
  },
];

/**
 * Copy for a failed Clinic proposal submission. Only for an attempted
 * submission: its fallback says the proposal could not be sent.
 */
export function mapProfessionalRescheduleErrorToKey(error: string): TranslationKey {
  return keyFor(error) ?? 'professionalReschedule.failed';
}

/**
 * Copy for a failed candidate-times read. Known rules keep their specific copy
 * (lost access, Entitlement, lifecycle, clinical documentation, …); anything else —
 * a network failure, a malformed payload, or a backend without the candidate
 * read — says the available times could not be loaded, never that a proposal
 * failed, since nothing was submitted.
 */
export function mapRescheduleCandidatesErrorToKey(error: string): TranslationKey {
  return keyFor(error) ?? 'professionalReschedule.candidatesLoadError';
}

/** Copy for a failed withdrawal. */
export function mapRescheduleWithdrawalErrorToKey(error: string): TranslationKey {
  return keyFor(error) ?? 'professionalReschedule.withdrawFailed';
}

function keyFor(error: string): TranslationKey | null {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';

  const lowerError = error.toLowerCase();
  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }
  return null;
}

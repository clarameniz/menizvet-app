import type { TranslationKey } from '@/i18n/i18n';

/**
 * Guardian copy for a failed acceptance of a Clinic reschedule proposal
 * (SPEC-APT-006). accept_appointment_reschedule_proposal reuses 23514/42501
 * for several rules, so — as in i18n/appointment-error-messages.ts — this
 * matches the stable, hand-authored message text
 * (supabase/migrations/20261008090000_confirmed_appointment_reschedule_and_withdrawal.sql).
 *
 * Every outcome that means "this proposal can no longer be accepted" (already
 * accepted or withdrawn, superseded, lapsed, proposer's authority lost,
 * Appointment no longer CONFIRMED) maps to one calm message: the caller
 * re-reads and shows the authoritative state, and the confirmed time stays the
 * commitment. Raw backend text never reaches product UI.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  { substring: 'current guardianship', key: 'appointmentErrors.lostGuardianship' },
  {
    substring: 'applicable professional entitlement is required',
    key: 'rescheduleProposal.clinicUnavailable',
  },
  {
    substring: 'appointment with clinical documentation cannot be rescheduled',
    key: 'rescheduleProposal.documented',
  },
  {
    substring: 'clinic appointment availability does not cover',
    key: 'rescheduleProposal.timeUnavailable',
  },
  { substring: 'currently assigned veterinarian', key: 'rescheduleProposal.timeUnavailable' },
  { substring: 'no longer actionable', key: 'rescheduleProposal.proposalUnavailable' },
  {
    substring: 'no longer the current confirmed context',
    key: 'rescheduleProposal.proposalUnavailable',
  },
  { substring: 'must remain confirmed', key: 'rescheduleProposal.proposalUnavailable' },
  { substring: 'must still be in the future', key: 'rescheduleProposal.proposalUnavailable' },
  { substring: 'must still be future', key: 'rescheduleProposal.proposalUnavailable' },
  {
    substring: 'reschedule proposal does not exist',
    key: 'rescheduleProposal.proposalUnavailable',
  },
];

export function mapRescheduleAcceptanceErrorToKey(error: string): TranslationKey {
  const lowerError = error.toLowerCase();
  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerError.includes(substring)) return key;
  }
  return 'rescheduleProposal.failed';
}

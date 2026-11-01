import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Copy for the REQUESTED Appointment Alternative Time (SPEC-APT-018/019/020).
 * The RPCs reuse SQLSTATEs 23514/42501/22023 for several unrelated rules, so —
 * as in every other Appointment mapper — this matches the stable, hand-authored
 * message text
 * (supabase/migrations/20261010090000_requested_appointment_alternative_time.sql
 * and the shared feasibility and authorization helpers). A Veterinarian
 * conflict and missing Veterinarian Availability share one backend message by
 * design, so the copy never hints at another commitment.
 *
 * Every outcome is followed by a re-read by the caller; this module only
 * chooses the copy. Raw backend text never reaches product UI. Withdrawal
 * reuses the confirmed-reschedule withdrawal mapper (the same RPC).
 */
const PROFESSIONAL_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'stale requested appointment schedule revision for alternative time proposal',
    key: 'alternativeTime.staleSchedule',
  },
  {
    substring: 'applicable appointment-management capability is required',
    key: 'alternativeTime.accessLost',
  },
  {
    substring: 'applicable clinic-management capability is required',
    key: 'alternativeTime.accessLost',
  },
  {
    substring: 'applicable professional entitlement is required',
    key: 'alternativeTime.entitlementDenied',
  },
  {
    substring: 'only a requested appointment may receive an alternative time proposal',
    key: 'alternativeTime.lifecycleChanged',
  },
  {
    substring: 'whose requested time has passed cannot receive an alternative time proposal',
    key: 'alternativeTime.startPassed',
  },
  {
    substring: 'clinic has no currently configured standard appointment duration',
    key: 'alternativeTime.noStandardDuration',
  },
  {
    substring: 'already has an actionable unresolved reschedule proposal',
    key: 'alternativeTime.pendingExists',
  },
  {
    substring: 'proposed time must differ from the current requested time',
    key: 'alternativeTime.sameTime',
  },
  {
    substring: 'clinic appointment availability does not cover',
    key: 'alternativeTime.timeUnavailable',
  },
  {
    substring: 'proposed appointment time must be in the future',
    key: 'alternativeTime.timeUnavailable',
  },
  {
    substring: 'do not identify a valid occurrence of local civil time',
    key: 'alternativeTime.timeUnavailable',
  },
  {
    substring: 'currently assigned veterinarian',
    key: 'alternativeTime.veterinarianUnavailable',
  },
  {
    substring: 'a meaningful reason is required for a clinic alternative time proposal',
    key: 'alternativeTime.reasonMissing',
  },
];

/**
 * Guardian acceptance (SPEC-APT-019). Every outcome meaning "this proposal can
 * no longer be accepted" (accepted, withdrawn, superseded, lapsed, the
 * request expired or confirmed, the proposer's authority lost) maps to one
 * calm message: the caller re-reads and shows the authoritative state.
 */
const ACCEPTANCE_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  { substring: 'current guardianship', key: 'appointmentErrors.lostGuardianship' },
  {
    substring: 'clinic appointment availability does not cover',
    key: 'alternativeTimeProposal.timeUnavailable',
  },
  { substring: 'currently assigned veterinarian', key: 'alternativeTimeProposal.timeUnavailable' },
  { substring: 'no longer actionable', key: 'alternativeTimeProposal.proposalUnavailable' },
  {
    substring: 'no longer the current requested context',
    key: 'alternativeTimeProposal.proposalUnavailable',
  },
  { substring: 'must remain requested', key: 'alternativeTimeProposal.proposalUnavailable' },
  { substring: 'requested time has passed', key: 'alternativeTimeProposal.proposalUnavailable' },
  { substring: 'must still be in the future', key: 'alternativeTimeProposal.proposalUnavailable' },
  {
    substring: 'only a clinic alternative time for a requested appointment',
    key: 'alternativeTimeProposal.proposalUnavailable',
  },
  {
    substring: 'reschedule proposal does not exist',
    key: 'alternativeTimeProposal.proposalUnavailable',
  },
];

function keyFor(
  error: string,
  table: readonly { substring: string; key: TranslationKey }[],
): TranslationKey | null {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';
  const lowerError = error.toLowerCase();
  for (const { substring, key } of table) {
    if (lowerError.includes(substring)) return key;
  }
  return null;
}

/** Copy for a failed alternative-time proposal submission. */
export function mapAlternativeTimeProposalErrorToKey(error: string): TranslationKey {
  return keyFor(error, PROFESSIONAL_MESSAGE_SUBSTRINGS) ?? 'alternativeTime.failed';
}

/**
 * Copy for a failed alternative-time candidate read. Known rules keep their
 * specific copy; anything else says the times could not be loaded, never that a
 * proposal failed, since nothing was submitted.
 */
export function mapAlternativeTimeCandidatesErrorToKey(error: string): TranslationKey {
  return keyFor(error, PROFESSIONAL_MESSAGE_SUBSTRINGS) ?? 'alternativeTime.candidatesLoadError';
}

/** Copy for a failed Guardian acceptance of an alternative time. */
export function mapAlternativeTimeAcceptanceErrorToKey(error: string): TranslationKey {
  return keyFor(error, ACCEPTANCE_MESSAGE_SUBSTRINGS) ?? 'alternativeTimeProposal.failed';
}

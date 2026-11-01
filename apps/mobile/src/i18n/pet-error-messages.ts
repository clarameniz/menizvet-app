import type { TranslationKey } from '@/i18n/i18n';

/**
 * register_pet and update_pet_profile raise plain Postgres exceptions, not
 * GoTrue-style semantic error codes — only a coarse 5-character SQLSTATE
 * shared across several unrelated raise sites in the same function (e.g.
 * '22023' covers "name blank", "species blank", and "exact/approximate
 * dates both supplied" alike), so matching on SQLSTATE can't tell those
 * apart. The raised message text itself is stable and hand-authored per
 * site (supabase/migrations/20260825170004_pet_and_guardianship.sql and
 * supabase/migrations/20260906090000_pet_profile_update_completion.sql), so
 * matching on it is more precise here.
 *
 * Mapped cases are the concrete, user-actionable, reachable-in-practice
 * ones: the verified-email precondition (register_pet), a stale
 * profile_revision (update_pet_profile — the edit form's data is older than
 * the current server state), and a lost/absent current Guardianship
 * (update_pet_profile — deliberately identical message for a nonexistent
 * Pet and an existing Pet the caller no longer guards, matching the
 * backend's own non-disclosure design; this module must not try to tell
 * those two cases apart). Every other raise (blank name/species, both birth
 * dates supplied, unauthenticated) is already prevented from being
 * reachable by this app's own client-side checks before the RPC is ever
 * called, so mapping them individually here would be speculative rather
 * than concrete.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'verified email address is required', key: 'errors.emailNotConfirmed' },
  { substring: 'stale pet profile revision', key: 'petForm.staleRevisionError' },
  {
    substring: 'current guardianship of the pet is required',
    key: 'petForm.lostGuardianshipError',
  },
];

export function mapPetErrorToKey(message: string): TranslationKey {
  const lowerMessage = message.toLowerCase();

  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerMessage.includes(substring)) {
      return key;
    }
  }

  return 'common.genericError';
}

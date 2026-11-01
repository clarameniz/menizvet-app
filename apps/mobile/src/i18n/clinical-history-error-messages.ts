import type { TranslationKey } from '@/i18n/i18n';

/**
 * Covers both `getGuardianPetMedicalHistory` (a plain Postgres/PostgREST
 * `error.message` string — see data/clinical-history.ts) and
 * `getGuardianClinicalAttachmentDownloadUrl` (either the same kind of RPC
 * message, or one of the `clinical-attachments` Edge Function's short
 * uppercase codes — AUTHENTICATION_REQUIRED, INVALID_REQUEST,
 * SIGNED_DOWNLOAD_UNAVAILABLE, INTERNAL_ERROR, NOT_FOUND,
 * METHOD_NOT_ALLOWED). Matching on lowercased substrings after the
 * `appointment-error-messages.ts` precedent handles both shapes uniformly;
 * `{status:'DENIED'}` is never passed here — it is a typed domain state
 * handled separately by the caller, not an error string (see this module's
 * data-layer counterpart).
 *
 * Raw SQLSTATEs, PostgREST codes/details/hints, Edge Function codes, Storage
 * paths, and bucket/object ids must never reach product UI — every branch
 * below resolves to a calm, generic, localized message; nothing here echoes
 * the matched text back to the caller.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  { substring: 'authentication_required', key: 'errors.sessionExpired' },
  {
    substring: 'signed_download_unavailable',
    key: 'clinicalHistory.attachmentError',
  },
  { substring: 'internal_error', key: 'clinicalHistory.attachmentError' },
];

export function mapClinicalHistoryErrorToKey(message: string): TranslationKey {
  const lowerMessage = message.toLowerCase();

  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerMessage.includes(substring)) {
      return key;
    }
  }

  return 'common.genericError';
}

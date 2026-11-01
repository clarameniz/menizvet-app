import type { TranslationKey } from '@/i18n/i18n';

/**
 * Small, concrete mapping for the errors actually encountered in Auth/Profile
 * today — not a speculative general taxonomy. Keyed on Supabase Auth's own
 * stable `error.code` (see @supabase/auth-js's ErrorCode union), which is
 * far more robust than matching on `.message` wording. Anything not listed
 * here — including PostgREST/Postgres errors from Profile reads/writes,
 * which have no defined user-facing taxonomy in this repository — falls
 * back to one generic localized message; the raw provider text is never
 * shown to the user.
 */
const KNOWN_ERROR_CODES: Record<string, TranslationKey> = {
  user_already_exists: 'errors.emailAlreadyRegistered',
  email_exists: 'errors.emailAlreadyRegistered',
  weak_password: 'errors.weakPassword',
  same_password: 'errors.samePassword',
  over_email_send_rate_limit: 'errors.rateLimited',
  over_request_rate_limit: 'errors.rateLimited',
  invalid_credentials: 'errors.invalidCredentials',
  email_not_confirmed: 'errors.emailNotConfirmed',
  session_expired: 'errors.sessionExpired',
  session_not_found: 'errors.sessionExpired',
  bad_code_verifier: 'resetPassword.invalidLinkMessage',
};

function hasErrorCode(error: unknown): error is { code?: string } {
  return typeof error === 'object' && error !== null && 'code' in error;
}

export function mapErrorToKey(error: unknown): TranslationKey {
  if (hasErrorCode(error) && typeof error.code === 'string' && error.code in KNOWN_ERROR_CODES) {
    return KNOWN_ERROR_CODES[error.code];
  }
  return 'common.genericError';
}

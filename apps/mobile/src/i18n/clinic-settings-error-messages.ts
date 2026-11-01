import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  CLINIC_SETTINGS_INVALID_REQUEST,
  CLINIC_SETTINGS_MALFORMED,
} from '@/data/clinic-settings';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Copy for Clinic settings (SPEC-CLI-007, SPEC-CLI-004, SPEC-CLI-002). The
 * writes reuse SQLSTATEs across rules, so — as in every other mapper — saves
 * are matched on the stable, hand-authored message text of
 * supabase/migrations/20261024090000_clinic_profile_location_fail_closed_writes.sql.
 * Every save outcome is followed by a re-read by the caller; this module only
 * chooses the copy. Raw backend text never reaches product UI.
 */

/** Copy for a failed Clinic settings read. */
export function mapClinicSettingsLoadErrorToKey(error: string): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';
  if (error === CLINIC_SETTINGS_ACCESS_DENIED) return 'clinicSettings.unavailable';
  return 'clinicSettings.loadError';
}

type SubstringKey = { substring: string; key: TranslationKey };

const COMMON_SAVE_SUBSTRINGS: readonly SubstringKey[] = [
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  // A nonexistent Clinic gets the same capability message (fail closed).
  { substring: 'management capability is required', key: 'clinicSettings.accessLost' },
];

const PROFILE_SAVE_SUBSTRINGS: readonly SubstringKey[] = [
  ...COMMON_SAVE_SUBSTRINGS,
  {
    substring: 'must retain a valid public display name',
    key: 'clinicSettingsProfile.nameRequiredWhilePublished',
  },
];

const LOCATION_SAVE_SUBSTRINGS: readonly SubstringKey[] = [
  ...COMMON_SAVE_SUBSTRINGS,
  { substring: 'address must not be blank', key: 'clinicSettingsLocation.addressRequired' },
  { substring: 'latitude must be between', key: 'clinicSettingsLocation.positionInvalid' },
  { substring: 'longitude must be between', key: 'clinicSettingsLocation.positionInvalid' },
];

function mapSaveError(error: string, substrings: readonly SubstringKey[]): TranslationKey {
  if (error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';
  if (error === CLINIC_SETTINGS_MALFORMED) return 'clinicSettings.saveUnconfirmed';
  if (error === CLINIC_SETTINGS_INVALID_REQUEST) return 'clinicSettings.saveFailed';
  const lowerError = error.toLowerCase();
  for (const { substring, key } of substrings) {
    if (lowerError.includes(substring)) return key;
  }
  return 'clinicSettings.saveFailed';
}

/** Copy for a failed profile save. */
export function mapClinicProfileSaveErrorToKey(error: string): TranslationKey {
  return mapSaveError(error, PROFILE_SAVE_SUBSTRINGS);
}

/** Copy for a failed location save. */
export function mapClinicLocationSaveErrorToKey(error: string): TranslationKey {
  return mapSaveError(error, LOCATION_SAVE_SUBSTRINGS);
}

// Matched on 20261025090000_clinic_timezone_publication_self_service.sql. The
// BR-56 denial shares SQLSTATE 42501 with the capability denial, so it is
// told apart by its own message (checked before the generic capability one).
const TIMEZONE_SAVE_SUBSTRINGS: readonly SubstringKey[] = [
  {
    substring: 'professional scheduling entitlement is required',
    key: 'clinicSettingsTimezone.blockedByAppointmentHours',
  },
  ...COMMON_SAVE_SUBSTRINGS,
  { substring: 'must be a valid named timezone', key: 'clinicSettingsTimezone.invalid' },
];

const PUBLICATION_SUBSTRINGS: readonly SubstringKey[] = [
  ...COMMON_SAVE_SUBSTRINGS,
  { substring: 'requires a valid public display name', key: 'clinicSettings.publishNeedsName' },
  { substring: 'requires a valid current location', key: 'clinicSettings.publishNeedsLocation' },
];

/** Copy for a failed scheduling timezone save. */
export function mapClinicTimezoneSaveErrorToKey(error: string): TranslationKey {
  return mapSaveError(error, TIMEZONE_SAVE_SUBSTRINGS);
}

/** Copy for a failed Publish or Unpublish. */
export function mapClinicPublicationErrorToKey(error: string): TranslationKey {
  return mapSaveError(error, PUBLICATION_SUBSTRINGS);
}

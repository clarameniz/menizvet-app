import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  CLINIC_SETTINGS_INVALID_REQUEST,
  CLINIC_SETTINGS_MALFORMED,
} from '@/data/clinic-settings';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import {
  mapClinicLocationSaveErrorToKey,
  mapClinicProfileSaveErrorToKey,
  mapClinicPublicationErrorToKey,
  mapClinicSettingsLoadErrorToKey,
  mapClinicTimezoneSaveErrorToKey,
} from '@/i18n/clinic-settings-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapClinicSettingsLoadErrorToKey', () => {
  it('maps an expired session', () => {
    expect(mapClinicSettingsLoadErrorToKey(PROFESSIONAL_CONTEXT_AUTH_REQUIRED)).toBe(
      'errors.sessionExpired',
    );
  });

  it('maps a denied read to the unavailable copy', () => {
    expect(mapClinicSettingsLoadErrorToKey(CLINIC_SETTINGS_ACCESS_DENIED)).toBe(
      'clinicSettings.unavailable',
    );
  });

  it.each([[CLINIC_SETTINGS_MALFORMED], ['raw backend text'], ['Network request failed']])(
    'maps anything else (%s) to the generic load error, never raw text',
    (error) => {
      expect(mapClinicSettingsLoadErrorToKey(error)).toBe('clinicSettings.loadError');
    },
  );
});

describe('mapClinicProfileSaveErrorToKey', () => {
  it.each([
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['No coherent domain User exists for the authenticated subject', 'errors.sessionExpired'],
    ['Clinic Public Profile-management capability is required', 'clinicSettings.accessLost'],
    [
      'A published Clinic must retain a valid public display name',
      'clinicSettingsProfile.nameRequiredWhilePublished',
    ],
    [CLINIC_SETTINGS_MALFORMED, 'clinicSettings.saveUnconfirmed'],
    [CLINIC_SETTINGS_INVALID_REQUEST, 'clinicSettings.saveFailed'],
    ['permission denied for table clinics', 'clinicSettings.saveFailed'],
    ['Network request failed', 'clinicSettings.saveFailed'],
  ])('maps %s', (error, key) => {
    expect(mapClinicProfileSaveErrorToKey(error)).toBe(key);
  });
});

describe('mapClinicLocationSaveErrorToKey', () => {
  it.each([
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['Authentication is required', 'errors.sessionExpired'],
    ['Clinic Location-management capability is required', 'clinicSettings.accessLost'],
    ['Clinic Location address must not be blank', 'clinicSettingsLocation.addressRequired'],
    [
      'Clinic Location latitude must be between -90 and 90',
      'clinicSettingsLocation.positionInvalid',
    ],
    [
      'Clinic Location longitude must be between -180 and 180',
      'clinicSettingsLocation.positionInvalid',
    ],
    [CLINIC_SETTINGS_MALFORMED, 'clinicSettings.saveUnconfirmed'],
    ['Network request failed', 'clinicSettings.saveFailed'],
  ])('maps %s', (error, key) => {
    expect(mapClinicLocationSaveErrorToKey(error)).toBe(key);
  });

  it('never maps a profile rule to a location message or the reverse', () => {
    expect(
      mapClinicLocationSaveErrorToKey('A published Clinic must retain a valid public display name'),
    ).toBe('clinicSettings.saveFailed');
    expect(mapClinicProfileSaveErrorToKey('Clinic Location address must not be blank')).toBe(
      'clinicSettings.saveFailed',
    );
  });
});

describe('mapClinicTimezoneSaveErrorToKey', () => {
  it.each([
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['Applicable Clinic-management capability is required', 'clinicSettings.accessLost'],
    [
      'Professional scheduling Entitlement is required to change scheduling timezone while Appointment Availability is currently effective',
      'clinicSettingsTimezone.blockedByAppointmentHours',
    ],
    ['Clinic scheduling timezone must be a valid named timezone', 'clinicSettingsTimezone.invalid'],
    [CLINIC_SETTINGS_MALFORMED, 'clinicSettings.saveUnconfirmed'],
    ['Network request failed', 'clinicSettings.saveFailed'],
  ])('maps %s', (error, key) => {
    expect(mapClinicTimezoneSaveErrorToKey(error)).toBe(key);
  });
});

describe('mapClinicPublicationErrorToKey', () => {
  it.each([
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['Clinic publication-management capability is required', 'clinicSettings.accessLost'],
    ['Clinic publication requires a valid public display name', 'clinicSettings.publishNeedsName'],
    ['Clinic publication requires a valid current Location', 'clinicSettings.publishNeedsLocation'],
    [CLINIC_SETTINGS_MALFORMED, 'clinicSettings.saveUnconfirmed'],
    ['Network request failed', 'clinicSettings.saveFailed'],
  ])('maps %s', (error, key) => {
    expect(mapClinicPublicationErrorToKey(error)).toBe(key);
  });
});

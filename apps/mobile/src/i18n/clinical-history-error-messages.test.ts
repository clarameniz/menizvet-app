import { mapClinicalHistoryErrorToKey } from '@/i18n/clinical-history-error-messages';

describe('mapClinicalHistoryErrorToKey', () => {
  it('maps an unauthenticated/session-less call to the shared sessionExpired key', () => {
    expect(mapClinicalHistoryErrorToKey('Authentication is required')).toBe(
      'errors.sessionExpired',
    );
  });

  it('maps a coherent-domain-User failure to the shared sessionExpired key', () => {
    expect(mapClinicalHistoryErrorToKey('No coherent domain User exists')).toBe(
      'errors.sessionExpired',
    );
  });

  it('maps the Edge Function AUTHENTICATION_REQUIRED code to the shared sessionExpired key', () => {
    expect(mapClinicalHistoryErrorToKey('AUTHENTICATION_REQUIRED')).toBe('errors.sessionExpired');
  });

  it.each(['SIGNED_DOWNLOAD_UNAVAILABLE', 'INTERNAL_ERROR'])(
    'maps the Edge Function %s code to the dedicated attachment-error key',
    (code) => {
      expect(mapClinicalHistoryErrorToKey(code)).toBe('clinicalHistory.attachmentError');
    },
  );

  it('falls back to the generic error key for an unrecognized message', () => {
    expect(mapClinicalHistoryErrorToKey('Page limit must be positive')).toBe('common.genericError');
  });

  it('never echoes the raw matched text back as the resolved key', () => {
    const key = mapClinicalHistoryErrorToKey('INTERNAL_ERROR');
    expect(key).not.toContain('INTERNAL_ERROR');
    expect(key).not.toContain('internal_error');
  });
});

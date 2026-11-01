import { mapErrorToKey } from '@/i18n/error-messages';

describe('mapErrorToKey', () => {
  it('maps a known Supabase Auth error code to its specific key', () => {
    expect(mapErrorToKey({ code: 'invalid_credentials' })).toBe('errors.invalidCredentials');
  });

  it('maps user_already_exists and email_exists to the same key', () => {
    expect(mapErrorToKey({ code: 'user_already_exists' })).toBe('errors.emailAlreadyRegistered');
    expect(mapErrorToKey({ code: 'email_exists' })).toBe('errors.emailAlreadyRegistered');
  });

  it('maps a PKCE code-verifier failure to the reset-password invalid-link key', () => {
    expect(mapErrorToKey({ code: 'bad_code_verifier' })).toBe('resetPassword.invalidLinkMessage');
  });

  it('falls back to the generic error for an unrecognized code', () => {
    expect(mapErrorToKey({ code: 'some_future_code_not_in_the_map' })).toBe('common.genericError');
  });

  it('falls back to the generic error when there is no code at all (e.g. a PostgREST error)', () => {
    expect(mapErrorToKey({ message: 'permission denied for table user_profiles' })).toBe(
      'common.genericError',
    );
  });

  it('falls back to the generic error for null, undefined, or non-object input', () => {
    expect(mapErrorToKey(null)).toBe('common.genericError');
    expect(mapErrorToKey(undefined)).toBe('common.genericError');
    expect(mapErrorToKey('a plain string error')).toBe('common.genericError');
  });
});

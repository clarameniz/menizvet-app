import { mapPetErrorToKey } from '@/i18n/pet-error-messages';

describe('mapPetErrorToKey', () => {
  it('maps the verified-email precondition message to the shared emailNotConfirmed key', () => {
    expect(mapPetErrorToKey('A verified email address is required')).toBe(
      'errors.emailNotConfirmed',
    );
  });

  it('matches case-insensitively', () => {
    expect(mapPetErrorToKey('a VERIFIED EMAIL ADDRESS IS REQUIRED')).toBe(
      'errors.emailNotConfirmed',
    );
  });

  it('maps a stale profile revision to the dedicated reload-product message', () => {
    expect(mapPetErrorToKey('Stale Pet Profile revision')).toBe('petForm.staleRevisionError');
  });

  it('maps a lost/absent current Guardianship to the dedicated lost-Guardianship message', () => {
    expect(mapPetErrorToKey('Current Guardianship of the Pet is required')).toBe(
      'petForm.lostGuardianshipError',
    );
  });

  it('maps the lost-Guardianship message identically regardless of whether the Pet exists, matching the backend non-disclosure design', () => {
    const nonexistentPetMessage = 'Current Guardianship of the Pet is required';
    const unauthorizedExistingPetMessage = 'Current Guardianship of the Pet is required';
    expect(mapPetErrorToKey(nonexistentPetMessage)).toBe(
      mapPetErrorToKey(unauthorizedExistingPetMessage),
    );
  });

  it('falls back to the generic error for an unrecognized message', () => {
    expect(mapPetErrorToKey('Pet name must not be blank')).toBe('common.genericError');
  });

  it('falls back to the generic error for an empty message', () => {
    expect(mapPetErrorToKey('')).toBe('common.genericError');
  });
});

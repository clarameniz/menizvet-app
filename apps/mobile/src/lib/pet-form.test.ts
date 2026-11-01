import { normalizePetFormFields, validatePetFormFields } from '@/lib/pet-form';

describe('validatePetFormFields', () => {
  it('accepts non-blank name/species with birth date mode "unknown"', () => {
    expect(
      validatePetFormFields({
        name: 'Luna',
        species: 'Dog',
        birthDate: { mode: 'unknown', year: '', month: '', day: '' },
      }),
    ).toBeNull();
  });

  it('rejects a blank name', () => {
    expect(
      validatePetFormFields({
        name: '   ',
        species: 'Dog',
        birthDate: { mode: 'unknown', year: '', month: '', day: '' },
      }),
    ).toBe('requiredField');
  });

  it('rejects a blank species', () => {
    expect(
      validatePetFormFields({
        name: 'Luna',
        species: '',
        birthDate: { mode: 'unknown', year: '', month: '', day: '' },
      }),
    ).toBe('requiredField');
  });

  it('rejects an incomplete exact birth date', () => {
    expect(
      validatePetFormFields({
        name: 'Luna',
        species: 'Dog',
        birthDate: { mode: 'exact', year: '2020', month: '', day: '' },
      }),
    ).toBe('invalidBirthDate');
  });

  it('accepts a complete, valid approximate birth date', () => {
    expect(
      validatePetFormFields({
        name: 'Luna',
        species: 'Dog',
        birthDate: { mode: 'approximate', year: '2020', month: '3', day: '5' },
      }),
    ).toBeNull();
  });
});

describe('normalizePetFormFields', () => {
  it('trims required fields and normalizes blank optional fields to null', () => {
    expect(
      normalizePetFormFields({
        name: '  Luna  ',
        species: '  Dog  ',
        breed: '   ',
        sex: '',
        microchip: '  ',
        behavioralInfo: '',
        birthDate: { mode: 'unknown', year: '', month: '', day: '' },
      }),
    ).toEqual({
      name: 'Luna',
      species: 'Dog',
      breed: null,
      sex: null,
      dateOfBirth: null,
      approximateDateOfBirth: null,
      microchipIdentifier: null,
      behavioralSafetyInformation: null,
    });
  });

  it('preserves trimmed non-blank optional fields', () => {
    expect(
      normalizePetFormFields({
        name: 'Luna',
        species: 'Dog',
        breed: '  Labrador  ',
        sex: ' Female ',
        microchip: ' 123456789012345 ',
        behavioralInfo: ' Nervous around loud noises. ',
        birthDate: { mode: 'unknown', year: '', month: '', day: '' },
      }),
    ).toEqual(
      expect.objectContaining({
        breed: 'Labrador',
        sex: 'Female',
        microchipIdentifier: '123456789012345',
        behavioralSafetyInformation: 'Nervous around loud noises.',
      }),
    );
  });

  it('normalizes an exact birth date into dateOfBirth only', () => {
    expect(
      normalizePetFormFields({
        name: 'Luna',
        species: 'Dog',
        breed: '',
        sex: '',
        microchip: '',
        behavioralInfo: '',
        birthDate: { mode: 'exact', year: '2020', month: '3', day: '5' },
      }),
    ).toEqual(
      expect.objectContaining({
        dateOfBirth: '2020-03-05',
        approximateDateOfBirth: null,
      }),
    );
  });

  it('normalizes an approximate birth date into approximateDateOfBirth only', () => {
    expect(
      normalizePetFormFields({
        name: 'Luna',
        species: 'Dog',
        breed: '',
        sex: '',
        microchip: '',
        behavioralInfo: '',
        birthDate: { mode: 'approximate', year: '2020', month: '3', day: '5' },
      }),
    ).toEqual(
      expect.objectContaining({
        dateOfBirth: null,
        approximateDateOfBirth: '2020-03-05',
      }),
    );
  });
});

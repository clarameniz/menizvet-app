/**
 * Field-normalization and validation rules shared between the Register and
 * Edit Pet screens. Both screens submit to a backend RPC with identical
 * normalization semantics (register_pet and update_pet_profile both trim
 * required/optional text the same way and enforce the same exact/approximate
 * birth-date mutual exclusivity — see
 * supabase/migrations/20260825170004_pet_and_guardianship.sql and
 * supabase/migrations/20260906090000_pet_profile_update_completion.sql), so
 * this is real shared contract logic, not a generic forms framework. It
 * returns a plain reason, not a translation key, so it stays free of any
 * i18n dependency — the same separation pet-date.ts already uses.
 */
import {
  hasIncompleteOrInvalidBirthDate,
  normalizeBirthDate,
  type BirthDateFormValue,
} from '@/lib/pet-date';

export type PetFormRawFields = {
  name: string;
  species: string;
  breed: string;
  sex: string;
  microchip: string;
  behavioralInfo: string;
  birthDate: BirthDateFormValue;
};

export type PetFormValidationError = 'requiredField' | 'invalidBirthDate';

export type NormalizedPetFormFields = {
  name: string;
  species: string;
  breed: string | null;
  sex: string | null;
  dateOfBirth: string | null;
  approximateDateOfBirth: string | null;
  microchipIdentifier: string | null;
  behavioralSafetyInformation: string | null;
};

/**
 * Checks the two rules the backend itself enforces and that both screens
 * must block submission on before calling their respective RPC: required
 * name/species must not be blank, and the birth date (if a mode other than
 * "unknown" is selected) must be a complete, valid calendar date. Returns
 * null when the fields are valid.
 */
export function validatePetFormFields(
  fields: Pick<PetFormRawFields, 'name' | 'species' | 'birthDate'>,
): PetFormValidationError | null {
  if (fields.name.trim().length === 0 || fields.species.trim().length === 0) {
    return 'requiredField';
  }

  if (hasIncompleteOrInvalidBirthDate(fields.birthDate)) {
    return 'invalidBirthDate';
  }

  return null;
}

/**
 * Trims required fields and normalizes optional text fields to null when
 * blank — the same "empty optional input becomes null, not ''" convention
 * register_pet's RPC contract already requires (an empty string is rejected
 * as "must not be blank when supplied", distinct from omission). Callers
 * must call validatePetFormFields first; this does not re-validate.
 */
export function normalizePetFormFields(fields: PetFormRawFields): NormalizedPetFormFields {
  const { dateOfBirth, approximateDateOfBirth } = normalizeBirthDate(fields.birthDate);

  return {
    name: fields.name.trim(),
    species: fields.species.trim(),
    breed: fields.breed.trim() || null,
    sex: fields.sex.trim() || null,
    dateOfBirth,
    approximateDateOfBirth,
    microchipIdentifier: fields.microchip.trim() || null,
    behavioralSafetyInformation: fields.behavioralInfo.trim() || null,
  };
}

import { fromRow, updatePetProfile, type PetRow } from '@/data/pets';

// fromRow doesn't use the Supabase client, but importing this module pulls
// in lib/supabase.ts, which throws if EXPO_PUBLIC_SUPABASE_* env vars are
// absent (as they are under Jest). Mocking it keeps this test isolated,
// deterministic, and free of any real network/Supabase contact — same
// pattern as data/user-profile.test.ts. jest.mock calls are hoisted above
// imports by Jest's babel transform regardless of source order, so writing
// the import first here is safe. The mock also captures the last rpc(...)
// call so updatePetProfile's parameter mapping can be asserted without any
// real Supabase contact.
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...args: unknown[]) => mockRpc(...args) },
}));

describe('fromRow', () => {
  it('maps a full row to the camelCase Pet shape', () => {
    const row: PetRow = {
      id: 'pet-123',
      name: 'Luna',
      species: 'Dog',
      breed: 'Mixed',
      sex: 'Female',
      date_of_birth: '2020-03-05',
      approximate_date_of_birth: null,
      microchip_identifier: '123456789012345',
      profile_image_reference: 'some-reference',
      behavioral_safety_information: 'May be shy with strangers.',
      profile_revision: 3,
      created_at: '2026-01-01T00:00:00Z',
    };

    expect(fromRow(row)).toEqual({
      id: 'pet-123',
      name: 'Luna',
      species: 'Dog',
      breed: 'Mixed',
      sex: 'Female',
      dateOfBirth: '2020-03-05',
      approximateDateOfBirth: null,
      microchipIdentifier: '123456789012345',
      profileImageReference: 'some-reference',
      behavioralSafetyInformation: 'May be shy with strangers.',
      profileRevision: 3,
      createdAt: '2026-01-01T00:00:00Z',
    });
  });

  it('preserves null optional fields rather than coercing them', () => {
    const row: PetRow = {
      id: 'pet-456',
      name: 'Toby',
      species: 'Cat',
      breed: null,
      sex: null,
      date_of_birth: null,
      approximate_date_of_birth: '2019-01-01',
      microchip_identifier: null,
      profile_image_reference: null,
      behavioral_safety_information: null,
      profile_revision: 0,
      created_at: '2026-01-02T00:00:00Z',
    };

    expect(fromRow(row)).toEqual({
      id: 'pet-456',
      name: 'Toby',
      species: 'Cat',
      breed: null,
      sex: null,
      dateOfBirth: null,
      approximateDateOfBirth: '2019-01-01',
      microchipIdentifier: null,
      profileImageReference: null,
      behavioralSafetyInformation: null,
      profileRevision: 0,
      createdAt: '2026-01-02T00:00:00Z',
    });
  });

  it('preserves profile_revision 0 rather than treating it as falsy/missing', () => {
    const row: PetRow = {
      id: 'pet-789',
      name: 'Milo',
      species: 'Dog',
      breed: null,
      sex: null,
      date_of_birth: null,
      approximate_date_of_birth: null,
      microchip_identifier: null,
      profile_image_reference: null,
      behavioral_safety_information: null,
      profile_revision: 0,
      created_at: '2026-01-03T00:00:00Z',
    };

    expect(fromRow(row).profileRevision).toBe(0);
  });
});

describe('updatePetProfile', () => {
  beforeEach(() => {
    mockRpc.mockReset();
  });

  it('maps every input field to its exact p_-prefixed RPC parameter, including profileImageReference round-tripped unchanged', async () => {
    mockRpc.mockResolvedValue({ data: 4, error: null });

    const result = await updatePetProfile({
      id: 'pet-123',
      expectedProfileRevision: 3,
      name: 'Luna',
      species: 'Dog',
      breed: 'Mixed',
      sex: 'Female',
      dateOfBirth: '2020-03-05',
      approximateDateOfBirth: null,
      microchipIdentifier: '123456789012345',
      profileImageReference: 'pets/pet-123/photo.jpg',
      behavioralSafetyInformation: 'May be shy with strangers.',
    });

    expect(mockRpc).toHaveBeenCalledWith('update_pet_profile', {
      p_pet_id: 'pet-123',
      p_expected_profile_revision: 3,
      p_name: 'Luna',
      p_species: 'Dog',
      p_breed: 'Mixed',
      p_sex: 'Female',
      p_date_of_birth: '2020-03-05',
      p_approximate_date_of_birth: null,
      p_microchip_identifier: '123456789012345',
      p_profile_image_reference: 'pets/pet-123/photo.jpg',
      p_behavioral_safety_information: 'May be shy with strangers.',
    });
    expect(result).toEqual({ data: { profileRevision: 4 }, error: null });
  });

  it('passes a null profileImageReference through unchanged rather than inventing a value', async () => {
    mockRpc.mockResolvedValue({ data: 1, error: null });

    await updatePetProfile({
      id: 'pet-456',
      expectedProfileRevision: 0,
      name: 'Toby',
      species: 'Cat',
      breed: null,
      sex: null,
      dateOfBirth: null,
      approximateDateOfBirth: null,
      microchipIdentifier: null,
      profileImageReference: null,
      behavioralSafetyInformation: null,
    });

    expect(mockRpc).toHaveBeenCalledWith(
      'update_pet_profile',
      expect.objectContaining({ p_profile_image_reference: null }),
    );
  });

  it('surfaces the raw RPC error message rather than throwing', async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: 'Stale Pet Profile revision' } });

    const result = await updatePetProfile({
      id: 'pet-123',
      expectedProfileRevision: 3,
      name: 'Luna',
      species: 'Dog',
      breed: null,
      sex: null,
      dateOfBirth: null,
      approximateDateOfBirth: null,
      microchipIdentifier: null,
      profileImageReference: null,
      behavioralSafetyInformation: null,
    });

    expect(result).toEqual({ data: null, error: 'Stale Pet Profile revision' });
  });

  it('resolves with a mapped error instead of rejecting when the RPC call itself throws (e.g. a network-level failure), so callers awaiting it can never be left stranded mid-submit', async () => {
    mockRpc.mockRejectedValue(new Error('Network request failed'));

    const resultPromise = updatePetProfile({
      id: 'pet-123',
      expectedProfileRevision: 3,
      name: 'Luna',
      species: 'Dog',
      breed: null,
      sex: null,
      dateOfBirth: null,
      approximateDateOfBirth: null,
      microchipIdentifier: null,
      profileImageReference: null,
      behavioralSafetyInformation: null,
    });

    await expect(resultPromise).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });

  it('resolves with a generic error string when the thrown value is not an Error instance', async () => {
    mockRpc.mockRejectedValue('a raw non-Error rejection');

    const result = await updatePetProfile({
      id: 'pet-123',
      expectedProfileRevision: 3,
      name: 'Luna',
      species: 'Dog',
      breed: null,
      sex: null,
      dateOfBirth: null,
      approximateDateOfBirth: null,
      microchipIdentifier: null,
      profileImageReference: null,
      behavioralSafetyInformation: null,
    });

    expect(result).toEqual({ data: null, error: 'Unknown error' });
  });
});

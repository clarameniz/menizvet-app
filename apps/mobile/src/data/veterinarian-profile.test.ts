import { createMyVeterinarianProfessionalProfile } from '@/data/veterinarian-profile';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;
const PROFILE = 'd0331000-0000-4000-8000-000000007001';
const CREDENTIAL = 'd0331000-0000-4000-8000-000000008001';
const INPUT = { registrationIdentifier: ' COL-1 ', issuingContext: 'Colegio de Madrid' };

beforeEach(() => rpc.mockReset());

it('sends only the two credential facts, as typed (no User parameter)', async () => {
  rpc.mockResolvedValue({
    data: {
      outcome: 'CREATED',
      professional_profile_id: PROFILE,
      professional_credential_id: CREDENTIAL,
    },
    error: null,
  });
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'outcome',
    outcome: 'CREATED',
  });
  expect(rpc).toHaveBeenCalledWith('create_my_veterinarian_professional_profile', {
    p_registration_identifier: ' COL-1 ',
    p_issuing_context: 'Colegio de Madrid',
  });
});
it('treats an exact replay (ALREADY_EXISTS) as the same success', async () => {
  rpc.mockResolvedValue({
    data: {
      outcome: 'ALREADY_EXISTS',
      professional_profile_id: PROFILE,
      professional_credential_id: CREDENTIAL,
    },
    error: null,
  });
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'outcome',
    outcome: 'ALREADY_EXISTS',
  });
});
it.each([
  ['23514', 'PROFILE_CREDENTIAL_MISMATCH'],
  ['42501', 'ACCOUNT_VERIFICATION_REQUIRED'],
  ['22023', 'REGISTRATION_IDENTIFIER_REQUIRED'],
  ['22023', 'ISSUING_CONTEXT_REQUIRED'],
])('maps %s/%s to a calm rejection', async (code, hint) => {
  rpc.mockResolvedValue({ data: null, error: { code, hint, message: 'x' } });
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'rejected',
    reason: hint,
  });
});
it('authentication, unknown errors, malformed successes and network failures', async () => {
  rpc.mockResolvedValue({ data: null, error: { code: '28000', message: 'x' } });
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'authenticationRequired',
  });
  rpc.mockResolvedValue({ data: null, error: { code: '23505', message: 'duplicate key' } });
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'uncertain',
  });
  rpc.mockResolvedValue({ data: { outcome: 'CREATED' }, error: null });
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'uncertain',
  });
  rpc.mockRejectedValue(new Error('offline'));
  await expect(createMyVeterinarianProfessionalProfile(INPUT)).resolves.toEqual({
    kind: 'uncertain',
  });
});

import { createClinic, parseClinicCreation } from '@/data/clinic-creation';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;

const ORG_A = 'aaaaaaaa-0000-4000-8000-000000000001';
const ORG_B = 'bbbbbbbb-0000-4000-8000-000000000002';
const CLINIC = 'cccccccc-0000-4000-8000-000000000003';
const KEY = 'dddddddd-0000-4000-8000-000000000004';

const answer = (overrides: Record<string, unknown> = {}) => ({
  clinic_id: CLINIC,
  organization_id: ORG_A,
  outcome: 'CREATED',
  ...overrides,
});

beforeEach(() => rpc.mockReset());

describe('parseClinicCreation', () => {
  it.each(['CREATED', 'ALREADY_CREATED'] as const)(
    '%s is a success for its Organization',
    (outcome) => {
      expect(parseClinicCreation(answer({ outcome }), ORG_A)).toEqual({
        kind: 'created',
        clinicId: CLINIC,
        outcome,
      });
    },
  );

  it('matches the Organization case-insensitively', () => {
    expect(parseClinicCreation(answer({ organization_id: ORG_A.toUpperCase() }), ORG_A).kind).toBe(
      'created',
    );
  });

  it.each([
    ['another Organization', answer({ organization_id: ORG_B })],
    ['an unknown outcome', answer({ outcome: 'MAYBE' })],
    ['a missing Clinic id', answer({ clinic_id: null })],
    ['a malformed Clinic id', answer({ clinic_id: 'clinic-1' })],
    ['a non-object', 'created'],
    ['null', null],
  ])('is never a success for %s', (_label, raw) => {
    expect(parseClinicCreation(raw, ORG_A)).toEqual({ kind: 'uncertain' });
  });
});

describe('createClinic', () => {
  it('sends only the Organization and the creation key', async () => {
    rpc.mockResolvedValue({ data: answer(), error: null });
    await expect(createClinic(ORG_A, KEY)).resolves.toEqual({
      kind: 'created',
      clinicId: CLINIC,
      outcome: 'CREATED',
    });
    expect(rpc).toHaveBeenCalledWith('create_clinic', {
      p_organization_id: ORG_A,
      p_idempotency_key: KEY,
    });
  });

  it.each([
    ['42501', { kind: 'accessDenied' }],
    ['28000', { kind: 'authenticationRequired' }],
    ['22023', { kind: 'rejected' }],
    ['PGRST301', { kind: 'uncertain' }],
    ['500', { kind: 'uncertain' }],
  ])('maps error %s', async (code, expected) => {
    rpc.mockResolvedValue({ data: null, error: { code, message: 'x' } });
    await expect(createClinic(ORG_A, KEY)).resolves.toEqual(expected);
  });

  it('a network failure is uncertain, never a rejection', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));
    await expect(createClinic(ORG_A, KEY)).resolves.toEqual({ kind: 'uncertain' });
  });

  it('a success for another Organization is uncertain', async () => {
    rpc.mockResolvedValue({ data: answer({ organization_id: ORG_B }), error: null });
    await expect(createClinic(ORG_A, KEY)).resolves.toEqual({ kind: 'uncertain' });
  });

  it.each([
    ['a malformed Organization id', 'A', KEY],
    ['a malformed key', ORG_A, 'key-1'],
    ['an empty key', ORG_A, ''],
  ])('sends nothing with %s', async (_label, organizationId, key) => {
    await expect(createClinic(organizationId, key)).resolves.toEqual({ kind: 'rejected' });
    expect(rpc).not.toHaveBeenCalled();
  });
});

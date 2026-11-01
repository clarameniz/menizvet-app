import {
  getMyOrganizationProfessionalClinicsPage,
  getMyProfessionalClinics,
  organizationClinicsCursorOf,
  parseOrganizationProfessionalClinicsPage,
  parseProfessionalClinics,
} from '@/data/professional-clinics';
import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_CONTEXT_MALFORMED,
} from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

// Importing the module pulls in lib/supabase.ts, which throws if
// EXPO_PUBLIC_SUPABASE_* env vars are absent (as they are under Jest) — same
// pattern as data/professional-context.test.ts.
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

function clinicRow(overrides: Record<string, unknown> = {}) {
  return {
    clinic_id: 'clinic-1',
    clinic_display_name: 'Animalia Madrid Centro',
    organization_id: 'organization-1',
    organization_display_name: 'Animalia Veterinary Group',
    capabilities: ['APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE'],
    ...overrides,
  };
}

describe('parseProfessionalClinics', () => {
  it('accepts an empty result as a normal result', () => {
    expect(parseProfessionalClinics({ clinics: [] })).toEqual({ clinics: [] });
  });

  it('maps one Clinic with known capabilities', () => {
    expect(parseProfessionalClinics({ clinics: [clinicRow()] })).toEqual({
      clinics: [
        {
          clinicId: 'clinic-1',
          clinicDisplayName: 'Animalia Madrid Centro',
          organizationId: 'organization-1',
          organizationDisplayName: 'Animalia Veterinary Group',
          capabilities: ['APPOINTMENT_COMPLETE', 'APPOINTMENT_VIEW_SCHEDULE'],
          unknownCapabilities: [],
        },
      ],
    });
  });

  it('keeps several Clinics across Organizations in backend order', () => {
    const parsed = parseProfessionalClinics({
      clinics: [
        clinicRow({ clinic_id: 'clinic-a5' }),
        clinicRow({ clinic_id: 'clinic-c1', organization_id: 'organization-3' }),
        clinicRow({
          clinic_id: 'clinic-b1',
          organization_id: 'organization-2',
          organization_display_name: 'VetCare Group',
        }),
      ],
    });

    expect(parsed?.clinics.map((clinic) => [clinic.clinicId, clinic.organizationId])).toEqual([
      ['clinic-a5', 'organization-1'],
      ['clinic-c1', 'organization-3'],
      ['clinic-b1', 'organization-2'],
    ]);
  });

  it('keeps an unnamed Clinic with a null display name', () => {
    const parsed = parseProfessionalClinics({
      clinics: [clinicRow({ clinic_display_name: null })],
    });
    expect(parsed?.clinics[0].clinicDisplayName).toBeNull();
  });

  describe('capability forward compatibility', () => {
    it('retains an unknown identifier separately and keeps the known ones', () => {
      const parsed = parseProfessionalClinics({
        clinics: [
          clinicRow({
            capabilities: ['APPOINTMENT_CONFIRM', 'FUTURE_CAPABILITY', 'CLINICAL_CARE'],
          }),
        ],
      });
      expect(parsed?.clinics[0].capabilities).toEqual(['APPOINTMENT_CONFIRM', 'CLINICAL_CARE']);
      expect(parsed?.clinics[0].unknownCapabilities).toEqual(['FUTURE_CAPABILITY']);
    });

    it('keeps a Clinic whose capabilities are all unknown, with no known capability', () => {
      const parsed = parseProfessionalClinics({
        clinics: [clinicRow({ capabilities: ['FUTURE_A', 'FUTURE_B'] })],
      });
      expect(parsed?.clinics).toHaveLength(1);
      expect(parsed?.clinics[0].capabilities).toEqual([]);
      expect(parsed?.clinics[0].unknownCapabilities).toEqual(['FUTURE_A', 'FUTURE_B']);
    });

    it('de-duplicates unknown (and known) identifiers in first-seen order', () => {
      const parsed = parseProfessionalClinics({
        clinics: [
          clinicRow({
            capabilities: [
              'FUTURE_B',
              'APPOINTMENT_CONFIRM',
              'FUTURE_A',
              'FUTURE_B',
              'APPOINTMENT_CONFIRM',
            ],
          }),
        ],
      });
      expect(parsed?.clinics[0].capabilities).toEqual(['APPOINTMENT_CONFIRM']);
      expect(parsed?.clinics[0].unknownCapabilities).toEqual(['FUTURE_B', 'FUTURE_A']);
    });
  });

  describe('rejects malformed payloads', () => {
    it.each([
      ['null', null],
      ['an array', []],
      ['a missing clinics key', {}],
      ['a non-array clinics', { clinics: 'clinic-1' }],
      ['a non-object Clinic', { clinics: ['clinic-1'] }],
      ['a missing Clinic id', { clinics: [clinicRow({ clinic_id: undefined })] }],
      ['an empty Clinic id', { clinics: [clinicRow({ clinic_id: '' })] }],
      ['a non-string Clinic display name', { clinics: [clinicRow({ clinic_display_name: 7 })] }],
      [
        'a missing Clinic display name key',
        { clinics: [clinicRow({ clinic_display_name: undefined })] },
      ],
      ['a missing Organization id', { clinics: [clinicRow({ organization_id: null })] }],
      [
        'a null Organization display name',
        { clinics: [clinicRow({ organization_display_name: null })] },
      ],
      ['a missing capability list', { clinics: [clinicRow({ capabilities: undefined })] }],
      ['an empty capability list', { clinics: [clinicRow({ capabilities: [] })] }],
      [
        'a non-string capability',
        { clinics: [clinicRow({ capabilities: ['APPOINTMENT_CONFIRM', 42] })] },
      ],
      ['an empty capability string', { clinics: [clinicRow({ capabilities: [''] })] }],
      [
        'the same Clinic returned twice',
        { clinics: [clinicRow(), clinicRow({ organization_display_name: 'Duplicate' })] },
      ],
    ])('rejects %s', (_label, payload) => {
      expect(parseProfessionalClinics(payload)).toBeNull();
    });
  });
});

describe('getMyProfessionalClinics', () => {
  const rpc = supabase.rpc as jest.Mock;

  afterEach(() => rpc.mockReset());

  it('calls the self-scoped RPC with no arguments and returns the parsed result', async () => {
    rpc.mockResolvedValue({ data: { clinics: [] }, error: null });

    await expect(getMyProfessionalClinics()).resolves.toEqual({
      data: { clinics: [] },
      error: null,
    });
    expect(rpc).toHaveBeenCalledWith('get_my_professional_clinics');
  });

  it('normalizes SQLSTATE 28000 to the shared auth-required error', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: {
        code: '28000',
        message: 'No coherent domain User exists for the authenticated subject',
      },
    });

    await expect(getMyProfessionalClinics()).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
  });

  it('fails safely on a malformed payload', async () => {
    rpc.mockResolvedValue({ data: { clinics: [{ clinic_id: 'x' }] }, error: null });

    await expect(getMyProfessionalClinics()).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_MALFORMED,
    });
  });

  it('settles instead of rejecting on a network failure', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));

    await expect(getMyProfessionalClinics()).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

describe('Organization page (SPEC-ORG-008 §11)', () => {
  const rpc = supabase.rpc as jest.Mock;
  const ORG = '00000000-0000-4000-8000-000000000001';
  const C1 = '00000000-0000-4000-8000-0000000000c1';
  const C2 = '00000000-0000-4000-8000-0000000000c2';

  afterEach(() => rpc.mockReset());

  describe('parseOrganizationProfessionalClinicsPage', () => {
    it('maps named and unnamed rows in backend order', () => {
      expect(
        parseOrganizationProfessionalClinicsPage([
          { clinic_id: C2, clinic_display_name: 'Clínica Centro' },
          { clinic_id: C1, clinic_display_name: null },
        ]),
      ).toEqual([
        { clinicId: C2, clinicDisplayName: 'Clínica Centro' },
        { clinicId: C1, clinicDisplayName: null },
      ]);
      expect(parseOrganizationProfessionalClinicsPage([])).toEqual([]);
    });

    it('drops any extra column from the client model', () => {
      expect(
        parseOrganizationProfessionalClinicsPage([
          { clinic_id: C1, clinic_display_name: 'A', capabilities: ['X'] },
        ]),
      ).toEqual([{ clinicId: C1, clinicDisplayName: 'A' }]);
    });

    it.each([
      ['a non-array payload', { clinics: [] }],
      ['a non-uuid id', [{ clinic_id: 'clinic-1', clinic_display_name: 'A' }]],
      ['a missing name', [{ clinic_id: C1 }]],
      ['a non-string name', [{ clinic_id: C1, clinic_display_name: 7 }]],
      ['a non-object row', [C1]],
      [
        'a Clinic twice (any case)',
        [
          { clinic_id: C1, clinic_display_name: 'A' },
          { clinic_id: C1.toUpperCase(), clinic_display_name: 'B' },
        ],
      ],
    ])('rejects %s', (_label, payload) => {
      expect(parseOrganizationProfessionalClinicsPage(payload)).toBeNull();
    });
  });

  it('the cursor is the complete key of the row, exactly as returned', () => {
    expect(organizationClinicsCursorOf({ clinicId: C1, clinicDisplayName: null })).toEqual({
      displayName: null,
      clinicId: C1,
    });
    expect(organizationClinicsCursorOf({ clinicId: C2, clinicDisplayName: 'Peña' })).toEqual({
      displayName: 'Peña',
      clinicId: C2,
    });
  });

  it('sends the Organization, search, complete cursor and limit, and parses the page', async () => {
    rpc.mockResolvedValue({ data: [{ clinic_id: C2, clinic_display_name: 'B' }], error: null });
    await expect(
      getMyOrganizationProfessionalClinicsPage(ORG, 'peña', { displayName: 'A', clinicId: C1 }, 20),
    ).resolves.toEqual({ data: [{ clinicId: C2, clinicDisplayName: 'B' }], error: null });
    expect(rpc).toHaveBeenCalledWith('get_my_organization_professional_clinics', {
      p_organization_id: ORG,
      p_search: 'peña',
      p_after_display_name: 'A',
      p_after_clinic_id: C1,
      p_limit: 20,
    });
  });

  it('a first page without a search sends nulls; an unnamed cursor keeps its null name', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await getMyOrganizationProfessionalClinicsPage(ORG, null, null, 20);
    await getMyOrganizationProfessionalClinicsPage(
      ORG,
      null,
      { displayName: null, clinicId: C1 },
      20,
    );
    expect(rpc.mock.calls).toEqual([
      [
        'get_my_organization_professional_clinics',
        {
          p_organization_id: ORG,
          p_search: null,
          p_after_display_name: null,
          p_after_clinic_id: null,
          p_limit: 20,
        },
      ],
      [
        'get_my_organization_professional_clinics',
        {
          p_organization_id: ORG,
          p_search: null,
          p_after_display_name: null,
          p_after_clinic_id: C1,
          p_limit: 20,
        },
      ],
    ]);
  });

  it('a malformed Organization id reads nothing and is an empty page', async () => {
    await expect(
      getMyOrganizationProfessionalClinicsPage('org-a', null, null, 20),
    ).resolves.toEqual({
      data: [],
      error: null,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('normalizes 28000, a malformed payload and a network failure', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });
    await expect(getMyOrganizationProfessionalClinicsPage(ORG, null, null, 20)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
    rpc.mockResolvedValueOnce({ data: [{ clinic_id: 'x' }], error: null });
    await expect(getMyOrganizationProfessionalClinicsPage(ORG, null, null, 20)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_MALFORMED,
    });
    rpc.mockRejectedValueOnce(new Error('Network request failed'));
    await expect(getMyOrganizationProfessionalClinicsPage(ORG, null, null, 20)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

import {
  getMyProfessionalContext,
  parseProfessionalContext,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_CONTEXT_MALFORMED,
} from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

// parseProfessionalContext doesn't touch the Supabase client, but importing
// this module pulls in lib/supabase.ts, which throws if EXPO_PUBLIC_SUPABASE_*
// env vars are absent (as they are under Jest) — same pattern as
// data/clinics.test.ts.
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const NO_ENTITLEMENTS = {
  APPOINTMENT_MANAGEMENT: false,
  PROFESSIONAL_SCHEDULING: false,
  CLINICAL_CARE: false,
  CLINICAL_DOCUMENTATION: false,
};

function organizationRow(overrides: Record<string, unknown> = {}) {
  return {
    membership_id: 'membership-1',
    organization_id: 'organization-1',
    organization_display_name: 'Animalia Veterinary Group',
    responsibilities: [{ responsibility: 'OWNER', scope_type: 'ORGANIZATION', clinic: null }],
    capabilities: [
      { capability: 'ORGANIZATION_CREATE_CLINICS', scope_type: 'ORGANIZATION', clinic: null },
    ],
    clinic_assignments: [],
    entitlements: NO_ENTITLEMENTS,
    ...overrides,
  };
}

function contextRow(organizations: unknown[], hasProfile = false) {
  return { has_veterinarian_professional_profile: hasProfile, organizations };
}

describe('parseProfessionalContext', () => {
  it('accepts an empty professional context as a normal result', () => {
    expect(parseProfessionalContext(contextRow([]))).toEqual({
      hasVeterinarianProfessionalProfile: false,
      organizations: [],
    });
  });

  it('reports a Professional Profile without any Organization', () => {
    expect(parseProfessionalContext(contextRow([], true))).toEqual({
      hasVeterinarianProfessionalProfile: true,
      organizations: [],
    });
  });

  it('maps one Organization with responsibilities, capabilities and separate Entitlements', () => {
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow({
          entitlements: { ...NO_ENTITLEMENTS, APPOINTMENT_MANAGEMENT: true },
        }),
      ]),
    );

    expect(parsed).toEqual({
      hasVeterinarianProfessionalProfile: false,
      organizations: [
        {
          membershipId: 'membership-1',
          organizationId: 'organization-1',
          organizationDisplayName: 'Animalia Veterinary Group',
          responsibilities: [{ responsibility: 'OWNER', scope: { type: 'ORGANIZATION' } }],
          capabilities: [
            { capability: 'ORGANIZATION_CREATE_CLINICS', scope: { type: 'ORGANIZATION' } },
          ],
          unknownCapabilities: [],
          clinicAssignments: [],
          entitlements: { ...NO_ENTITLEMENTS, APPOINTMENT_MANAGEMENT: true },
        },
      ],
    });
  });

  it('keeps several Organizations in server order', () => {
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow(),
        organizationRow({
          membership_id: 'membership-2',
          organization_id: 'organization-2',
          organization_display_name: 'VetCare',
        }),
      ]),
    );

    expect(parsed?.organizations.map((o) => o.organizationDisplayName)).toEqual([
      'Animalia Veterinary Group',
      'VetCare',
    ]);
  });

  it('keeps multiple Responsibilities with independent scopes', () => {
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow({
          responsibilities: [
            { responsibility: 'VETERINARIAN', scope_type: 'ORGANIZATION', clinic: null },
            {
              responsibility: 'ADMINISTRATOR',
              scope_type: 'CLINIC',
              clinic: { clinic_id: 'clinic-1', clinic_display_name: 'Animalia Madrid Centro' },
            },
          ],
        }),
      ]),
    );

    expect(parsed?.organizations[0].responsibilities).toEqual([
      { responsibility: 'VETERINARIAN', scope: { type: 'ORGANIZATION' } },
      {
        responsibility: 'ADMINISTRATOR',
        scope: {
          type: 'CLINIC',
          clinic: { clinicId: 'clinic-1', displayName: 'Animalia Madrid Centro' },
        },
      },
    ]);
  });

  it('keeps a Clinic with a null display name instead of failing or omitting it', () => {
    const unnamedClinic = { clinic_id: 'clinic-9', clinic_display_name: null };
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow({
          responsibilities: [
            { responsibility: 'RECEPTIONIST', scope_type: 'CLINIC', clinic: unnamedClinic },
          ],
          capabilities: [
            { capability: 'APPOINTMENT_CONFIRM', scope_type: 'CLINIC', clinic: unnamedClinic },
          ],
          clinic_assignments: [
            { veterinarian_clinic_assignment_id: 'assignment-1', clinic: unnamedClinic },
          ],
        }),
      ]),
    );

    const organization = parsed?.organizations[0];
    const expectedClinic = { clinicId: 'clinic-9', displayName: null };
    expect(organization?.responsibilities[0].scope).toEqual({
      type: 'CLINIC',
      clinic: expectedClinic,
    });
    expect(organization?.capabilities[0].scope).toEqual({ type: 'CLINIC', clinic: expectedClinic });
    expect(organization?.clinicAssignments).toEqual([
      { veterinarianClinicAssignmentId: 'assignment-1', clinic: expectedClinic },
    ]);
  });

  it('accepts an active Membership with no Responsibilities or capabilities', () => {
    const parsed = parseProfessionalContext(
      contextRow([organizationRow({ responsibilities: [], capabilities: [] })]),
    );
    expect(parsed?.organizations[0].responsibilities).toEqual([]);
    expect(parsed?.organizations[0].capabilities).toEqual([]);
  });

  describe('rejects malformed payloads', () => {
    it.each([
      ['null', null],
      ['an array', []],
      ['a missing profile flag', { organizations: [] }],
      ['a non-array organizations', { has_veterinarian_professional_profile: false }],
      ['a non-object organization', contextRow(['organization-1'])],
      ['a missing organization id', contextRow([organizationRow({ organization_id: undefined })])],
      [
        'a missing organization display name',
        contextRow([organizationRow({ organization_display_name: null })]),
      ],
      ['missing entitlements', contextRow([organizationRow({ entitlements: undefined })])],
      [
        'a non-boolean entitlement',
        contextRow([
          organizationRow({ entitlements: { ...NO_ENTITLEMENTS, CLINICAL_CARE: 'yes' } }),
        ]),
      ],
      [
        'a Clinic without an id',
        contextRow([
          organizationRow({
            clinic_assignments: [
              { veterinarian_clinic_assignment_id: 'a-1', clinic: { clinic_display_name: 'X' } },
            ],
          }),
        ]),
      ],
      [
        'a CLINIC scope without a Clinic',
        contextRow([
          organizationRow({
            responsibilities: [
              { responsibility: 'RECEPTIONIST', scope_type: 'CLINIC', clinic: null },
            ],
          }),
        ]),
      ],
      [
        'an ORGANIZATION scope carrying a Clinic',
        contextRow([
          organizationRow({
            capabilities: [
              {
                capability: 'APPOINTMENT_CONFIRM',
                scope_type: 'ORGANIZATION',
                clinic: { clinic_id: 'clinic-1', clinic_display_name: null },
              },
            ],
          }),
        ]),
      ],
      [
        'an unknown scope type',
        contextRow([
          organizationRow({
            responsibilities: [{ responsibility: 'OWNER', scope_type: 'GLOBAL', clinic: null }],
          }),
        ]),
      ],
    ])('rejects %s', (_label, payload) => {
      expect(parseProfessionalContext(payload)).toBeNull();
    });
  });

  describe('unknown controlled values', () => {
    it('rejects the whole payload for an unknown Responsibility rather than dropping it', () => {
      const payload = contextRow([
        organizationRow({
          responsibilities: [
            { responsibility: 'OWNER', scope_type: 'ORGANIZATION', clinic: null },
            { responsibility: 'SUPERUSER', scope_type: 'ORGANIZATION', clinic: null },
          ],
        }),
      ]);
      expect(parseProfessionalContext(payload)).toBeNull();
    });

    it('rejects an unknown Responsibility even when it is Clinic-scoped', () => {
      const payload = contextRow([
        organizationRow({
          responsibilities: [
            {
              responsibility: 'GROOMER',
              scope_type: 'CLINIC',
              clinic: { clinic_id: 'clinic-1', clinic_display_name: 'Animalia Getafe' },
            },
          ],
        }),
      ]);
      expect(parseProfessionalContext(payload)).toBeNull();
    });
  });
});

describe('capability forward compatibility', () => {
  const clinic = { clinic_id: 'clinic-1', clinic_display_name: 'Animalia Madrid Centro' };

  it('parses known capabilities normally with no unknown metadata', () => {
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow({
          capabilities: [
            { capability: 'ORGANIZATION_CREATE_CLINICS', scope_type: 'ORGANIZATION', clinic: null },
            { capability: 'CLINICAL_CARE', scope_type: 'CLINIC', clinic },
          ],
        }),
      ]),
    );

    expect(parsed?.organizations[0].capabilities).toEqual([
      { capability: 'ORGANIZATION_CREATE_CLINICS', scope: { type: 'ORGANIZATION' } },
      {
        capability: 'CLINICAL_CARE',
        scope: {
          type: 'CLINIC',
          clinic: { clinicId: 'clinic-1', displayName: 'Animalia Madrid Centro' },
        },
      },
    ]);
    expect(parsed?.organizations[0].unknownCapabilities).toEqual([]);
  });

  it('keeps the context and known capabilities when one identifier is unknown', () => {
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow({
          capabilities: [
            { capability: 'ORGANIZATION_CREATE_CLINICS', scope_type: 'ORGANIZATION', clinic: null },
            { capability: 'FUTURE_CAPABILITY', scope_type: 'ORGANIZATION', clinic: null },
            { capability: 'APPOINTMENT_CONFIRM', scope_type: 'CLINIC', clinic },
          ],
        }),
      ]),
    );

    expect(parsed).not.toBeNull();
    const organization = parsed?.organizations[0];
    expect(organization?.capabilities.map((entry) => entry.capability)).toEqual([
      'ORGANIZATION_CREATE_CLINICS',
      'APPOINTMENT_CONFIRM',
    ]);
    expect(organization?.unknownCapabilities).toEqual(['FUTURE_CAPABILITY']);
  });

  it('retains several unknown identifiers once each, in first-seen server order', () => {
    const parsed = parseProfessionalContext(
      contextRow([
        organizationRow({
          capabilities: [
            { capability: 'FUTURE_B', scope_type: 'ORGANIZATION', clinic: null },
            { capability: 'FUTURE_A', scope_type: 'CLINIC', clinic },
            { capability: 'FUTURE_B', scope_type: 'CLINIC', clinic },
          ],
        }),
      ]),
    );

    expect(parsed?.organizations[0].capabilities).toEqual([]);
    expect(parsed?.organizations[0].unknownCapabilities).toEqual(['FUTURE_B', 'FUTURE_A']);
  });

  it.each([
    ['a non-object capability entry', 'APPOINTMENT_CONFIRM'],
    ['a non-string identifier', { capability: 42, scope_type: 'ORGANIZATION', clinic: null }],
    ['an empty identifier', { capability: '', scope_type: 'ORGANIZATION', clinic: null }],
    [
      'an unknown identifier with an unknown scope',
      { capability: 'FUTURE', scope_type: 'GLOBAL', clinic: null },
    ],
    [
      'an unknown identifier with CLINIC scope and no Clinic',
      { capability: 'FUTURE', scope_type: 'CLINIC', clinic: null },
    ],
    [
      'an unknown identifier with ORGANIZATION scope carrying a Clinic',
      { capability: 'FUTURE', scope_type: 'ORGANIZATION', clinic },
    ],
    [
      'an unknown identifier with a Clinic missing its id',
      { capability: 'FUTURE', scope_type: 'CLINIC', clinic: { clinic_display_name: 'X' } },
    ],
  ])('still rejects %s', (_label, entry) => {
    expect(
      parseProfessionalContext(contextRow([organizationRow({ capabilities: [entry] })])),
    ).toBeNull();
  });

  it('keeps Entitlements strict alongside an unknown capability', () => {
    const payload = contextRow([
      organizationRow({
        capabilities: [{ capability: 'FUTURE', scope_type: 'ORGANIZATION', clinic: null }],
        entitlements: { ...NO_ENTITLEMENTS, CLINICAL_CARE: undefined },
      }),
    ]);
    expect(parseProfessionalContext(payload)).toBeNull();
  });
});

describe('getMyProfessionalContext', () => {
  const rpc = supabase.rpc as jest.Mock;

  afterEach(() => rpc.mockReset());

  it('calls the self-scoped RPC with no arguments and returns the parsed context', async () => {
    rpc.mockResolvedValue({ data: contextRow([]), error: null });

    await expect(getMyProfessionalContext()).resolves.toEqual({
      data: { hasVeterinarianProfessionalProfile: false, organizations: [] },
      error: null,
    });
    expect(rpc).toHaveBeenCalledWith('get_my_professional_context');
  });

  it('normalizes SQLSTATE 28000 to the auth-required error', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });

    await expect(getMyProfessionalContext()).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
  });

  it('fails safely on a malformed payload', async () => {
    rpc.mockResolvedValue({ data: { organizations: 'nope' }, error: null });

    await expect(getMyProfessionalContext()).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_MALFORMED,
    });
  });

  it('settles instead of rejecting on a network failure', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));

    await expect(getMyProfessionalContext()).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

import type { ProfessionalContext } from '@/data/professional-context';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { needsVeterinarianProfile } from '@/lib/professional-home';
import {
  canReviewVeterinarianProfile,
  reviewedVeterinarianProfile,
  veterinarianProfileAvailability,
  veterinarianProfileOutcome,
} from '@/lib/veterinarian-profile';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const context = (
  roles: ('OWNER' | 'ADMINISTRATOR' | 'RECEPTIONIST' | 'VETERINARIAN')[][],
  hasProfile = false,
): ProfessionalContext => ({
  hasVeterinarianProfessionalProfile: hasProfile,
  organizations: roles.map((orgRoles, index) => ({
    membershipId: `m${index}`,
    organizationId: `o${index}`,
    organizationDisplayName: `Org ${index}`,
    responsibilities: orgRoles.map((responsibility) => ({
      responsibility,
      scope: { type: 'ORGANIZATION' },
    })),
    capabilities: [],
    unknownCapabilities: [],
    clinicAssignments: [],
    entitlements: {
      APPOINTMENT_MANAGEMENT: false,
      PROFESSIONAL_SCHEDULING: false,
      CLINICAL_CARE: false,
      CLINICAL_DOCUMENTATION: false,
    },
  })),
});

describe('Home prompt (SPEC-VET-001 §13)', () => {
  it('prompts only a current Veterinarian without a Profile', () => {
    expect(needsVeterinarianProfile(context([['ADMINISTRATOR'], ['VETERINARIAN']]))).toBe(true);
    expect(needsVeterinarianProfile(context([['VETERINARIAN']], true))).toBe(false);
    expect(needsVeterinarianProfile(context([['OWNER', 'ADMINISTRATOR', 'RECEPTIONIST']]))).toBe(
      false,
    );
    expect(needsVeterinarianProfile(context([]))).toBe(false);
  });
  it('offers the form exactly when prompted', () => {
    expect(veterinarianProfileAvailability(context([['VETERINARIAN']]))).toBe('form');
    expect(veterinarianProfileAvailability(context([['VETERINARIAN']], true))).toBe('completed');
    expect(veterinarianProfileAvailability(context([['RECEPTIONIST']]))).toBe('notOffered');
  });
});

describe('form and review', () => {
  it('requires both non-blank facts and reviews them as the backend stores them', () => {
    expect(
      canReviewVeterinarianProfile({ registrationIdentifier: ' ', issuingContext: 'Madrid' }),
    ).toBe(false);
    expect(
      canReviewVeterinarianProfile({ registrationIdentifier: 'COL-1', issuingContext: '\t' }),
    ).toBe(false);
    expect(
      canReviewVeterinarianProfile({ registrationIdentifier: 'COL-1', issuingContext: 'Madrid' }),
    ).toBe(true);
    expect(
      reviewedVeterinarianProfile({
        registrationIdentifier: '  COL-1 ',
        issuingContext: ' Madrid\n',
      }),
    ).toEqual({
      registrationIdentifier: 'COL-1',
      issuingContext: 'Madrid',
    });
  });
});

describe('outcome after the re-read', () => {
  const withProfile = { data: context([['VETERINARIAN']], true), error: null };
  const without = { data: context([['VETERINARIAN']]), error: null };
  it('CREATED and ALREADY_EXISTS are the same success', () => {
    expect(veterinarianProfileOutcome({ kind: 'outcome', outcome: 'CREATED' }, without)).toBe(
      'created',
    );
    expect(
      veterinarianProfileOutcome({ kind: 'outcome', outcome: 'ALREADY_EXISTS' }, withProfile),
    ).toBe('created');
  });
  it('a lost response is success only when the re-read shows a Profile', () => {
    expect(veterinarianProfileOutcome({ kind: 'uncertain' }, withProfile)).toBe('created');
    expect(veterinarianProfileOutcome({ kind: 'uncertain' }, without)).toBe(
      'veterinarianProfile.unconfirmed',
    );
    expect(veterinarianProfileOutcome({ kind: 'uncertain' }, null)).toBe(
      'veterinarianProfile.unconfirmed',
    );
    expect(
      veterinarianProfileOutcome(
        { kind: 'uncertain' },
        { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED },
      ),
    ).toBe('errors.sessionExpired');
  });
  it('a different existing Profile is a calm conflict, never success', () => {
    expect(
      veterinarianProfileOutcome(
        { kind: 'rejected', reason: 'PROFILE_CREDENTIAL_MISMATCH' },
        withProfile,
      ),
    ).toBe('veterinarianProfile.mismatch');
    expect(
      veterinarianProfileOutcome(
        { kind: 'rejected', reason: 'ACCOUNT_VERIFICATION_REQUIRED' },
        without,
      ),
    ).toBe('veterinarianProfile.verificationRequired');
  });
});

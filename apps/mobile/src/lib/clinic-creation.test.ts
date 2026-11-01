import type {
  OrganizationProfessionalContext,
  ProfessionalContext,
  ScopedCapability,
} from '@/data/professional-context';
import {
  clinicCreationContext,
  clinicCreationStep,
  forgetClinicCreation,
  newClinicCreationIntent,
  offersClinicCreation,
  rememberClinicCreation,
  unresolvedClinicCreation,
} from '@/lib/clinic-creation';

const KEY_1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const KEY_2 = 'aaaaaaaa-0000-4000-8000-000000000002';

const organization = (
  id: string,
  capabilities: ScopedCapability[] = [],
  name = `Organization ${id}`,
): OrganizationProfessionalContext => ({
  organizationId: id,
  membershipId: `m-${id}`,
  organizationDisplayName: name,
  capabilities,
  responsibilities: [],
  unknownCapabilities: [],
  clinicAssignments: [],
  entitlements: {
    APPOINTMENT_MANAGEMENT: false,
    PROFESSIONAL_SCHEDULING: false,
    CLINICAL_CARE: false,
    CLINICAL_DOCUMENTATION: false,
  },
});
const CREATE: ScopedCapability = {
  capability: 'ORGANIZATION_CREATE_CLINICS',
  scope: { type: 'ORGANIZATION' },
};
const context = (...organizations: OrganizationProfessionalContext[]): ProfessionalContext => ({
  hasVeterinarianProfessionalProfile: false,
  organizations,
});

afterEach(() => {
  forgetClinicCreation('A');
  forgetClinicCreation('B');
});

describe('offersClinicCreation', () => {
  it('follows the Organization-scoped ORGANIZATION_CREATE_CLINICS only', () => {
    expect(offersClinicCreation(organization('A', [CREATE]))).toBe(true);
    expect(offersClinicCreation(organization('A'))).toBe(false);
    expect(
      offersClinicCreation(
        organization('A', [
          { capability: 'ORGANIZATION_INVITE_MEMBERS', scope: { type: 'ORGANIZATION' } },
        ]),
      ),
    ).toBe(false);
    expect(
      offersClinicCreation(
        organization('A', [
          {
            capability: 'ORGANIZATION_CREATE_CLINICS',
            scope: { type: 'CLINIC', clinic: { clinicId: 'c', displayName: 'C' } },
          },
        ]),
      ),
    ).toBe(false);
  });
});

describe('clinicCreationContext', () => {
  it('is the selected Organization, by id, when it offers creation', () => {
    expect(clinicCreationContext(context(organization('A', [CREATE])), 'A')).toEqual({
      organizationId: 'A',
      organizationDisplayName: 'Organization A',
    });
  });

  it('is evaluated per Organization: creation in A never applies to B', () => {
    const both = context(organization('A', [CREATE]), organization('B'));
    expect(clinicCreationContext(both, 'B')).toBeNull();
    expect(clinicCreationContext(both, 'A')?.organizationId).toBe('A');
  });

  it('never matches by display name', () => {
    const lookalikes = context(
      organization('A', [CREATE], 'Grupo'),
      organization('B', [], 'Grupo'),
    );
    expect(clinicCreationContext(lookalikes, 'B')).toBeNull();
  });

  it('is null without a selection, an unknown Organization, or an unreadable context', () => {
    expect(clinicCreationContext(context(organization('A', [CREATE])), null)).toBeNull();
    expect(clinicCreationContext(context(organization('A', [CREATE])), 'gone')).toBeNull();
    expect(clinicCreationContext(null, 'A')).toBeNull();
  });
});

describe('newClinicCreationIntent', () => {
  it('binds one fresh key to one Organization', () => {
    const generate = jest.fn().mockReturnValueOnce(KEY_1).mockReturnValueOnce(KEY_2);
    expect(newClinicCreationIntent('A', generate)).toEqual({ organizationId: 'A', key: KEY_1 });
    expect(newClinicCreationIntent('A', generate)).toEqual({ organizationId: 'A', key: KEY_2 });
    expect(generate).toHaveBeenCalledTimes(2);
  });

  it('produces no intent when no well-formed key is available', () => {
    expect(newClinicCreationIntent('A', () => 'not-a-uuid')).toBeNull();
    expect(
      newClinicCreationIntent('A', () => {
        throw new Error('no native UUID generator');
      }),
    ).toBeNull();
  });
});

describe('unresolved intents', () => {
  it('are kept per Organization until forgotten, and never cross Organizations', () => {
    rememberClinicCreation({ organizationId: 'A', key: KEY_1 });
    expect(unresolvedClinicCreation('A')).toEqual({ organizationId: 'A', key: KEY_1 });
    expect(unresolvedClinicCreation('B')).toBeNull();
    forgetClinicCreation('A');
    expect(unresolvedClinicCreation('A')).toBeNull();
  });

  it('store a copy, so the caller cannot change a kept intent', () => {
    const intent = { organizationId: 'A', key: KEY_1 };
    rememberClinicCreation(intent);
    intent.key = KEY_2;
    expect(unresolvedClinicCreation('A')?.key).toBe(KEY_1);
  });
});

describe('clinicCreationStep', () => {
  it.each(['CREATED', 'ALREADY_CREATED'] as const)('%s opens that Clinic', (outcome) => {
    expect(clinicCreationStep({ kind: 'created', clinicId: 'c-1', outcome })).toEqual({
      kind: 'open',
      clinicId: 'c-1',
    });
  });

  it('keeps an uncertain answer for a same-key retry', () => {
    expect(clinicCreationStep({ kind: 'uncertain' })).toEqual({ kind: 'uncertain' });
  });

  it.each([
    [{ kind: 'accessDenied' } as const, 'clinicCreation.notAllowed'],
    [{ kind: 'authenticationRequired' } as const, 'errors.sessionExpired'],
    [{ kind: 'rejected' } as const, 'clinicCreation.failed'],
  ])('definite rejection %o ends the intent calmly', (result, messageKey) => {
    expect(clinicCreationStep(result)).toEqual({ kind: 'failed', messageKey });
  });
});

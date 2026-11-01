import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type OrganizationProfessionalContext,
  type ProfessionalContext,
  type ProfessionalContextResult,
} from '@/data/professional-context';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import {
  appointmentManagementStatusFor,
  managedActionGate,
  managedActionsNotice,
} from '@/lib/appointment-management';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

function organization(
  organizationId: string,
  appointmentManagement: boolean,
  responsibility: 'OWNER' | 'ADMINISTRATOR' | 'RECEPTIONIST' | 'VETERINARIAN' = 'OWNER',
): OrganizationProfessionalContext {
  return {
    membershipId: `membership-${organizationId}`,
    organizationId,
    organizationDisplayName: organizationId,
    responsibilities: [{ responsibility, scope: { type: 'ORGANIZATION' } }],
    capabilities: [],
    unknownCapabilities: [],
    clinicAssignments: [],
    entitlements: {
      APPOINTMENT_MANAGEMENT: appointmentManagement,
      PROFESSIONAL_SCHEDULING: true,
      CLINICAL_CARE: true,
      CLINICAL_DOCUMENTATION: true,
    },
  };
}

const context = (
  ...organizations: OrganizationProfessionalContext[]
): ProfessionalContextResult<ProfessionalContext> => ({
  data: { hasVeterinarianProfessionalProfile: false, organizations },
  error: null,
});

describe('appointmentManagementStatusFor (SPEC-ORG-007 BR-7, SPEC-ORG-008 BR-11)', () => {
  it("reads the Entitlement of the Clinic's own Organization only", () => {
    const both = context(organization('org-1', false), organization('org-2', true));
    expect(appointmentManagementStatusFor(both, 'org-1')).toEqual({ kind: 'unavailable' });
    expect(appointmentManagementStatusFor(both, 'org-2')).toEqual({ kind: 'available' });
  });

  it.each(['OWNER', 'ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN'] as const)(
    'never infers it from a responsibility (%s without the Entitlement)',
    (responsibility) => {
      expect(
        appointmentManagementStatusFor(
          context(organization('org-1', false, responsibility)),
          'org-1',
        ),
      ).toEqual({ kind: 'unavailable' });
    },
  );

  it('is unknown, never unavailable, when it cannot be verified', () => {
    expect(
      appointmentManagementStatusFor({ data: null, error: 'Network request failed' }, 'org-1'),
    ).toEqual({ kind: 'unknown', messageKey: 'professional.loadError' });
    expect(
      appointmentManagementStatusFor(
        { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED },
        'org-1',
      ),
    ).toEqual({ kind: 'unknown', messageKey: 'errors.sessionExpired' });
    expect(appointmentManagementStatusFor(context(organization('org-2', true)), 'org-1')).toEqual({
      kind: 'unknown',
      messageKey: 'professional.loadError',
    });
  });
});

describe('managedActionGate', () => {
  const unknown = { kind: 'unknown', messageKey: 'professional.loadError' } as const;

  it('offers an eligible action only with the Entitlement available', () => {
    expect(managedActionGate(true, { kind: 'available' })).toBe('offered');
    expect(managedActionGate(true, { kind: 'unavailable' })).toBe('unavailable');
    expect(managedActionGate(true, unknown)).toBe('unverified');
  });

  it('says nothing about the Entitlement for an action that is not eligible anyway', () => {
    expect(managedActionGate(false, { kind: 'available' })).toBe('notApplicable');
    expect(managedActionGate(false, { kind: 'unavailable' })).toBe('notApplicable');
    expect(managedActionGate(false, unknown)).toBe('notApplicable');
  });
});

describe('managedActionsNotice', () => {
  it('shows one note at most, "unavailable" first', () => {
    expect(managedActionsNotice(['offered', 'notApplicable'])).toBeNull();
    expect(managedActionsNotice(['notApplicable', 'unverified'])).toBe('unverified');
    expect(managedActionsNotice(['unverified', 'unavailable'])).toBe('unavailable');
    expect(managedActionsNotice([])).toBeNull();
  });

  it('has its copy in Spanish and English', () => {
    for (const locale of [es, en]) {
      expect(locale.appointmentManagement.unavailable).toEqual(expect.any(String));
      expect(locale.appointmentManagement.unverified).toEqual(expect.any(String));
      expect(locale.appointmentManagement.retryLabel).toEqual(expect.any(String));
    }
  });
});

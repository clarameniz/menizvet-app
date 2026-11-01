import type {
  OrganizationProfessionalContext,
  ProfessionalContext,
} from '@/data/professional-context';
import {
  assignedClinics,
  clinicDisplayLabel,
  hasProfessionalOrganizations,
  resolveSelectedOrganization,
  responsibilityClinic,
  responsibilityLabelKey,
} from '@/lib/professional-context-display';

function organization(
  membershipId: string,
  overrides: Partial<OrganizationProfessionalContext> = {},
): OrganizationProfessionalContext {
  return {
    membershipId,
    organizationId: `organization-${membershipId}`,
    organizationDisplayName: `Organization ${membershipId}`,
    responsibilities: [],
    capabilities: [],
    unknownCapabilities: [],
    clinicAssignments: [],
    entitlements: {
      APPOINTMENT_MANAGEMENT: false,
      PROFESSIONAL_SCHEDULING: false,
      CLINICAL_CARE: false,
      CLINICAL_DOCUMENTATION: false,
    },
    ...overrides,
  };
}

describe('hasProfessionalOrganizations', () => {
  it('is false for an empty context, even with a Professional Profile', () => {
    const context: ProfessionalContext = {
      hasVeterinarianProfessionalProfile: true,
      organizations: [],
    };
    expect(hasProfessionalOrganizations(context)).toBe(false);
  });

  it('is true with one or more Organizations', () => {
    expect(
      hasProfessionalOrganizations({
        hasVeterinarianProfessionalProfile: false,
        organizations: [organization('m-1')],
      }),
    ).toBe(true);
  });
});

describe('resolveSelectedOrganization', () => {
  const organizations = [organization('m-1'), organization('m-2')];

  it('returns null with no Organizations', () => {
    expect(resolveSelectedOrganization([], null)).toBeNull();
  });

  it('defaults to the first Organization', () => {
    expect(resolveSelectedOrganization(organizations, null)?.membershipId).toBe('m-1');
  });

  it('keeps the picked Organization while it is still current', () => {
    expect(resolveSelectedOrganization(organizations, 'm-2')?.membershipId).toBe('m-2');
  });

  it('falls back to the first Organization when the picked one is no longer returned', () => {
    expect(resolveSelectedOrganization(organizations, 'm-ended')?.membershipId).toBe('m-1');
  });
});

describe('responsibilityLabelKey', () => {
  it('maps every controlled Responsibility to a translated label', () => {
    expect(responsibilityLabelKey('OWNER')).toBe('professional.responsibilityOwner');
    expect(responsibilityLabelKey('ADMINISTRATOR')).toBe(
      'professional.responsibilityAdministrator',
    );
    expect(responsibilityLabelKey('RECEPTIONIST')).toBe('professional.responsibilityReceptionist');
    expect(responsibilityLabelKey('VETERINARIAN')).toBe('professional.responsibilityVeterinarian');
  });
});

describe('responsibilityClinic', () => {
  it('is null for an Organization-scoped Responsibility', () => {
    expect(
      responsibilityClinic({ responsibility: 'OWNER', scope: { type: 'ORGANIZATION' } }),
    ).toBeNull();
  });

  it('is the scoped Clinic for a Clinic-scoped Responsibility', () => {
    const clinic = { clinicId: 'clinic-1', displayName: 'Animalia Getafe' };
    expect(
      responsibilityClinic({ responsibility: 'RECEPTIONIST', scope: { type: 'CLINIC', clinic } }),
    ).toEqual(clinic);
  });
});

describe('clinicDisplayLabel', () => {
  it('uses the Clinic display name when present', () => {
    expect(clinicDisplayLabel({ clinicId: 'c-1', displayName: 'Animalia' }, 'Unnamed clinic')).toBe(
      'Animalia',
    );
  });

  it('uses the localized fallback when the Clinic has no display name', () => {
    expect(clinicDisplayLabel({ clinicId: 'c-1', displayName: null }, 'Unnamed clinic')).toBe(
      'Unnamed clinic',
    );
  });
});

describe('assignedClinics', () => {
  it('lists distinct assigned Clinics in server order', () => {
    const madrid = { clinicId: 'c-madrid', displayName: 'Madrid Centro' };
    const unnamed = { clinicId: 'c-new', displayName: null };
    const result = assignedClinics(
      organization('m-1', {
        clinicAssignments: [
          { veterinarianClinicAssignmentId: 'a-1', clinic: madrid },
          { veterinarianClinicAssignmentId: 'a-2', clinic: unnamed },
          { veterinarianClinicAssignmentId: 'a-3', clinic: madrid },
        ],
      }),
    );
    expect(result).toEqual([madrid, unnamed]);
  });
});

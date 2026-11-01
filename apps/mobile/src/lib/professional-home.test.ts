import type { ProfessionalClinic, ProfessionalClinics } from '@/data/professional-clinics';
import type {
  OrganizationProfessionalContext,
  ProfessionalCapability,
  ScopedCapability,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import { resolveSelectedOrganization } from '@/lib/professional-context-display';
import { professionalManagementEntries, professionalAccessLines } from '@/lib/professional-home';

const LONG_NAME = 'MenizVet Slice 14 controlled dispatch fixture e0eddab4';

const organization = (
  id: string,
  overrides: Partial<OrganizationProfessionalContext> = {},
): OrganizationProfessionalContext => ({
  organizationId: id,
  membershipId: `m-${id}`,
  organizationDisplayName: `Organization ${id}`,
  capabilities: [],
  responsibilities: [],
  unknownCapabilities: [],
  clinicAssignments: [],
  entitlements: {
    APPOINTMENT_MANAGEMENT: false,
    PROFESSIONAL_SCHEDULING: false,
    CLINICAL_CARE: false,
    CLINICAL_DOCUMENTATION: false,
  },
  ...overrides,
});
const orgCapability = (capability: ProfessionalCapability): ScopedCapability => ({
  capability,
  scope: { type: 'ORGANIZATION' },
});
const clinic = (organizationId: string): ProfessionalClinic => ({
  clinicId: `c-${organizationId}`,
  clinicDisplayName: `Clinic ${organizationId}`,
  organizationId,
  organizationDisplayName: `Organization ${organizationId}`,
  capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
  unknownCapabilities: [],
});
const clinicsOf = (...organizationIds: string[]): ProfessionalClinics => ({
  clinics: organizationIds.map(clinic),
});
const t = i18n.t.bind(i18n);

afterEach(() => {
  i18n.locale = 'es';
});

describe('professionalAccessLines', () => {
  it('lists every active Responsibility Grant with its scope, in Spanish', () => {
    i18n.locale = 'es';
    const lines = professionalAccessLines(
      organization('A', {
        responsibilities: [
          { responsibility: 'OWNER', scope: { type: 'ORGANIZATION' } },
          { responsibility: 'VETERINARIAN', scope: { type: 'ORGANIZATION' } },
          {
            responsibility: 'RECEPTIONIST',
            scope: { type: 'CLINIC', clinic: { clinicId: 'c', displayName: 'A Centro' } },
          },
        ],
      }),
      t,
    );
    expect(lines).toEqual([
      'Propietario · Organización',
      'Veterinario · Organización',
      'Recepcionista · Clínica: A Centro',
    ]);
  });

  it('labels a single Administrator compactly in English', () => {
    i18n.locale = 'en';
    expect(
      professionalAccessLines(
        organization('A', {
          responsibilities: [{ responsibility: 'ADMINISTRATOR', scope: { type: 'ORGANIZATION' } }],
        }),
        t,
      ),
    ).toEqual(['Administrator · Organization']);
  });

  it('never repeats the Organization name, however long', () => {
    const lines = professionalAccessLines(
      organization('A', {
        organizationDisplayName: LONG_NAME,
        responsibilities: [{ responsibility: 'ADMINISTRATOR', scope: { type: 'ORGANIZATION' } }],
      }),
      t,
    );
    expect(lines.join(' ')).not.toContain(LONG_NAME);
  });

  it('states no active Responsibilities rather than leaving a blank', () => {
    expect(professionalAccessLines(organization('A'), t)).toEqual([
      t('professional.noResponsibilities'),
    ]);
  });

  it.each([
    ['es', 'Tu acceso en esta organización'],
    ['en', 'Your access in this organization'],
  ])('titles the access card in %s without naming the Organization', (locale, title) => {
    i18n.locale = locale;
    expect(t('professional.accessHeading')).toBe(title);
  });

  it('leaves assigned Clinics out of the access card', () => {
    const lines = professionalAccessLines(
      organization('A', {
        responsibilities: [{ responsibility: 'VETERINARIAN', scope: { type: 'ORGANIZATION' } }],
        clinicAssignments: [
          {
            veterinarianClinicAssignmentId: 'a-1',
            clinic: { clinicId: 'c-1', displayName: 'Madrid' },
          },
        ],
      }),
      t,
    );
    expect(lines).toEqual(['Veterinario · Organización']);
  });
});

describe('professionalManagementEntries', () => {
  const admin = organization('A', {
    capabilities: [orgCapability('ORGANIZATION_INVITE_MEMBERS')],
  });

  it('offers Subscription last, only with Organization-scoped ORGANIZATION_MANAGE_SUBSCRIPTION', () => {
    const owner = organization('A', {
      capabilities: [
        orgCapability('ORGANIZATION_INVITE_MEMBERS'),
        orgCapability('ORGANIZATION_MANAGE_SUBSCRIPTION'),
      ],
    });
    expect(professionalManagementEntries(owner, clinicsOf('A'))).toEqual([
      'staff',
      'clinics',
      'subscription',
    ]);
    expect(professionalManagementEntries(admin, clinicsOf('A'))).not.toContain('subscription');
  });

  it('offers both entries, Staff first, when both apply', () => {
    expect(professionalManagementEntries(admin, clinicsOf('A'))).toEqual(['staff', 'clinics']);
  });

  it('offers Staff alone when the Organization has no Professional Clinics', () => {
    expect(professionalManagementEntries(admin, clinicsOf('B'))).toEqual(['staff']);
    expect(professionalManagementEntries(admin, clinicsOf())).toEqual(['staff']);
  });

  it('offers Clinics alone without the Staff capabilities (e.g. Receptionist, Clinic Administrator)', () => {
    const receptionist = organization('A', {
      responsibilities: [{ responsibility: 'RECEPTIONIST', scope: { type: 'ORGANIZATION' } }],
      capabilities: [orgCapability('APPOINTMENT_VIEW_SCHEDULE')],
    });
    expect(professionalManagementEntries(receptionist, clinicsOf('A'))).toEqual(['clinics']);
    const clinicAdministrator = organization('A', {
      responsibilities: [
        {
          responsibility: 'ADMINISTRATOR',
          scope: { type: 'CLINIC', clinic: { clinicId: 'c-A', displayName: 'Clinic A' } },
        },
      ],
      capabilities: [
        {
          capability: 'ORGANIZATION_INVITE_MEMBERS',
          scope: { type: 'CLINIC', clinic: { clinicId: 'c-A', displayName: 'Clinic A' } },
        },
      ],
    });
    expect(professionalManagementEntries(clinicAdministrator, clinicsOf('A'))).toEqual(['clinics']);
  });

  it('is empty when neither applies, including before Clinics were read', () => {
    expect(professionalManagementEntries(organization('A'), clinicsOf('B'))).toEqual([]);
    expect(professionalManagementEntries(organization('A'), null)).toEqual([]);
    expect(professionalManagementEntries(admin, null)).toEqual(['staff']);
  });

  it('offers Clinics for an Organization with no Clinics when the User may add one', () => {
    const creator = organization('A', {
      capabilities: [orgCapability('ORGANIZATION_CREATE_CLINICS')],
    });
    expect(professionalManagementEntries(creator, clinicsOf())).toEqual(['clinics']);
    expect(professionalManagementEntries(creator, clinicsOf('B'))).toEqual(['clinics']);
    // Not yet read: creation alone still reaches the Clinics screen.
    expect(professionalManagementEntries(creator, null)).toEqual(['clinics']);
    const owner = organization('A', {
      capabilities: [
        orgCapability('ORGANIZATION_INVITE_MEMBERS'),
        orgCapability('ORGANIZATION_CREATE_CLINICS'),
      ],
    });
    expect(professionalManagementEntries(owner, clinicsOf())).toEqual(['staff', 'clinics']);
  });

  it('offers no Clinics entry with zero Clinics and no creation capability', () => {
    expect(professionalManagementEntries(organization('A'), clinicsOf())).toEqual([]);
    const clinicScoped = organization('A', {
      capabilities: [
        {
          capability: 'ORGANIZATION_CREATE_CLINICS',
          scope: { type: 'CLINIC', clinic: { clinicId: 'c-A', displayName: 'Clinic A' } },
        },
      ],
    });
    expect(professionalManagementEntries(clinicScoped, clinicsOf())).toEqual([]);
  });

  it('switching A → B evaluates creation per Organization, leaving no stale Clinics entry', () => {
    const organizations = [
      organization('A', { capabilities: [orgCapability('ORGANIZATION_CREATE_CLINICS')] }),
      organization('B'),
    ];
    const a = resolveSelectedOrganization(organizations, 'm-A');
    const b = resolveSelectedOrganization(organizations, 'm-B');
    expect(a && professionalManagementEntries(a, clinicsOf())).toEqual(['clinics']);
    expect(b && professionalManagementEntries(b, clinicsOf())).toEqual([]);
  });

  it('follows the selected Organization only, so switching never shows stale entries', () => {
    const organizations = [admin, organization('B')];
    const clinics = clinicsOf('B');
    const a = resolveSelectedOrganization(organizations, 'm-A');
    const b = resolveSelectedOrganization(organizations, 'm-B');
    expect(a?.organizationId).toBe('A');
    expect(b?.organizationId).toBe('B');
    expect(a && professionalManagementEntries(a, clinics)).toEqual(['staff']);
    expect(b && professionalManagementEntries(b, clinics)).toEqual(['clinics']);
  });
});

it('keeps long Organization names whole in the selected-Organization model', () => {
  const organizations = [
    organization('A'),
    organization('B', { organizationDisplayName: LONG_NAME }),
  ];
  expect(resolveSelectedOrganization(organizations, 'm-B')?.organizationDisplayName).toBe(
    LONG_NAME,
  );
});

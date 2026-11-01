import type { ProfessionalClinic, ProfessionalClinics } from '@/data/professional-clinics';
import type { ProfessionalContext } from '@/data/professional-context';
import {
  clinicsForOrganization,
  offersClinicSearch,
  organizationClinicLabel,
  organizationClinicsBody,
  organizationClinicsHeading,
  professionalClinicLabel,
  submittedClinicSearch,
} from '@/lib/professional-clinics-display';
import {
  getProfessionalOrganizationSelection,
  setProfessionalOrganizationSelection,
} from '@/lib/professional-organization-selection';

function clinic(
  clinicId: string,
  organizationId: string,
  overrides: Partial<ProfessionalClinic> = {},
): ProfessionalClinic {
  return {
    clinicId,
    clinicDisplayName: `Clinic ${clinicId}`,
    organizationId,
    organizationDisplayName: `Organization ${organizationId}`,
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
    unknownCapabilities: [],
    ...overrides,
  };
}

// One self-scoped read returning two Organizations' Clinics, in backend order.
const read: ProfessionalClinics = {
  clinics: [
    clinic('a1', 'org-a', { organizationDisplayName: 'Org A' }),
    clinic('a2', 'org-a', { organizationDisplayName: 'Org A' }),
    clinic('b1', 'org-b', { organizationDisplayName: 'Org B' }),
  ],
};

const ids = (clinics: readonly ProfessionalClinic[]) => clinics.map((entry) => entry.clinicId);

const organization = (organizationId: string, organizationDisplayName: string) => ({
  membershipId: `m-${organizationId}`,
  organizationId,
  organizationDisplayName,
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
});
const context: ProfessionalContext = {
  hasVeterinarianProfessionalProfile: false,
  organizations: [organization('org-a', 'Org A'), organization('org-b', 'Org B')],
};

/** The heading the Clinics screen shows for the current shared selection. */
const headingForCurrentSelection = () =>
  organizationClinicsHeading(
    context,
    getProfessionalOrganizationSelection()?.organizationId ?? null,
    null,
  );

afterEach(() => setProfessionalOrganizationSelection(null));

describe('professionalClinicLabel', () => {
  it('uses the Clinic display name when present', () => {
    expect(professionalClinicLabel(clinic('c-1', 'o-1'), 'Unnamed clinic')).toBe('Clinic c-1');
  });

  it('uses the localized fallback for an unnamed Clinic', () => {
    expect(
      professionalClinicLabel(clinic('c-1', 'o-1', { clinicDisplayName: null }), 'Unnamed clinic'),
    ).toBe('Unnamed clinic');
  });
});

describe('clinicsForOrganization', () => {
  it("returns only the selected Organization's Clinics, in backend order", () => {
    expect(ids(clinicsForOrganization(read, 'org-a'))).toEqual(['a1', 'a2']);
    expect(ids(clinicsForOrganization(read, 'org-b'))).toEqual(['b1']);
  });

  it('returns nothing without a selected Organization', () => {
    expect(clinicsForOrganization(read, null)).toEqual([]);
  });

  it('never filters by display name: same-named Clinics and Organizations elsewhere do not leak', () => {
    const lookalikes: ProfessionalClinics = {
      clinics: [
        clinic('a1', 'org-a', { clinicDisplayName: 'Centro', organizationDisplayName: 'Grupo' }),
        clinic('x1', 'org-x', { clinicDisplayName: 'Centro', organizationDisplayName: 'Grupo' }),
      ],
    };
    expect(ids(clinicsForOrganization(lookalikes, 'org-a'))).toEqual(['a1']);
    expect(ids(clinicsForOrganization(lookalikes, 'org-x'))).toEqual(['x1']);
  });

  it('only narrows the backend result: it never adds a Clinic, and keeps one the backend included', () => {
    const backendIncluded: ProfessionalClinics = {
      clinics: [
        clinic('a1', 'org-a', { capabilities: [], unknownCapabilities: ['FUTURE_CAPABILITY'] }),
      ],
    };
    expect(ids(clinicsForOrganization(backendIncluded, 'org-a'))).toEqual(['a1']);
    expect(clinicsForOrganization({ clinics: [] }, 'org-a')).toEqual([]);
  });
});

describe('organizationClinicLabel', () => {
  it('uses the display name, or the localized fallback for an unnamed Clinic', () => {
    expect(
      organizationClinicLabel({ clinicId: 'c-1', clinicDisplayName: 'Centro' }, 'Sin nombre'),
    ).toBe('Centro');
    expect(
      organizationClinicLabel({ clinicId: 'c-1', clinicDisplayName: null }, 'Sin nombre'),
    ).toBe('Sin nombre');
  });
});

describe('organizationClinicsHeading', () => {
  it('names the selected Organization from the professional context', () => {
    expect(organizationClinicsHeading(context, 'org-b', null)).toEqual({
      kind: 'organization',
      organizationId: 'org-b',
      organizationDisplayName: 'Org B',
      canCreate: false,
    });
  });

  it('offers Add Clinic only with creation for that same Organization (matched by id)', () => {
    const creationA = { organizationId: 'org-a', organizationDisplayName: 'Org A' };
    expect(organizationClinicsHeading(context, 'org-a', creationA)).toMatchObject({
      canCreate: true,
    });
    expect(organizationClinicsHeading(context, 'org-b', creationA)).toMatchObject({
      organizationId: 'org-b',
      canCreate: false,
    });
  });

  it('fails safe without a selection, or with one the context no longer contains', () => {
    expect(organizationClinicsHeading(context, null, null)).toEqual({ kind: 'noOrganization' });
    expect(organizationClinicsHeading(context, 'org-gone', null)).toEqual({
      kind: 'noOrganization',
    });
    expect(
      organizationClinicsHeading({ ...context, organizations: [] }, 'org-a', {
        organizationId: 'org-a',
        organizationDisplayName: 'Org A',
      }),
    ).toEqual({ kind: 'noOrganization' });
  });

  it('never matches by name: a same-named Organization is another Organization', () => {
    const twins: ProfessionalContext = {
      ...context,
      organizations: [organization('org-a', 'Grupo'), organization('org-x', 'Grupo')],
    };
    expect(organizationClinicsHeading(twins, 'org-x', null)).toMatchObject({
      organizationId: 'org-x',
    });
  });
});

describe('submittedClinicSearch', () => {
  it('drops outer whitespace only; blank is no search', () => {
    expect(submittedClinicSearch('  peña ')).toBe('peña');
    expect(submittedClinicSearch('clínica  centro')).toBe('clínica  centro');
    expect(submittedClinicSearch('   ')).toBe('');
    expect(submittedClinicSearch('')).toBe('');
  });
});

describe('organizationClinicsBody', () => {
  const row = { clinicId: 'c-1', clinicDisplayName: null };

  it('is pending until the first page of the current search arrives', () => {
    expect(organizationClinicsBody(null, '')).toBe('pending');
    expect(organizationClinicsBody(null, 'pena')).toBe('pending');
  });

  it('shows rows, or tells "no matches" from "no Clinics" by the search', () => {
    expect(organizationClinicsBody([row], 'pena')).toBe('rows');
    expect(organizationClinicsBody([], 'pena')).toBe('noMatches');
    expect(organizationClinicsBody([], '')).toBe('noClinics');
  });
});

describe('offersClinicSearch', () => {
  const base = { search: '', typed: '', clinicsListed: false };

  it('is hidden for an Organization without Clinics and before anything was listed', () => {
    expect(offersClinicSearch({ ...base, body: 'noClinics', clinicsListed: true })).toBe(false);
    expect(offersClinicSearch({ ...base, body: 'pending' })).toBe(false);
  });

  it('is shown with rows, and kept while a search is typed, submitted or reloading', () => {
    expect(offersClinicSearch({ ...base, body: 'rows' })).toBe(true);
    expect(offersClinicSearch({ ...base, body: 'pending', typed: 'p' })).toBe(true);
    expect(offersClinicSearch({ ...base, body: 'noMatches', search: 'zz' })).toBe(true);
    // Cleared after Clinics were listed: the field stays while the list reloads.
    expect(offersClinicSearch({ ...base, body: 'pending', clinicsListed: true })).toBe(true);
  });
});

describe('Professional Clinics follow the selected Organization', () => {
  const select = (organizationId: string) =>
    setProfessionalOrganizationSelection({ membershipId: `m-${organizationId}`, organizationId });

  it('Org A selected names Org A; Org B selected names Org B', () => {
    select('org-a');
    expect(headingForCurrentSelection()).toMatchObject({ organizationId: 'org-a' });
    select('org-b');
    expect(headingForCurrentSelection()).toMatchObject({ organizationId: 'org-b' });
  });

  it('cleared selection shows no Organization', () => {
    select('org-a');
    setProfessionalOrganizationSelection(null);
    expect(headingForCurrentSelection()).toEqual({ kind: 'noOrganization' });
  });
});

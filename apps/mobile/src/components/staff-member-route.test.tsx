import { createElement } from 'react';
import { AccessibilityInfo, Alert, Text, type AlertButton } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import StaffMemberRoute from '@/app/professional/organizations/[organizationId]/staff/[membershipId]';
import {
  endOrganizationStaffMembership,
  getOrganizationStaff,
  type StaffMember,
  type StaffResponsibility,
  type StaffResult,
} from '@/data/organization-staff';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext, type ProfessionalCapability } from '@/data/professional-context';
import {
  endStaffResponsibility,
  endStaffVeterinarianClinicAssignment,
  getOrganizationVeterinarianWorkforce,
  type WorkforceMember,
} from '@/data/staff-workforce';
import { i18n } from '@/i18n/i18n';

let mockParams = { organizationId: 'A', membershipId: 'm1' };
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => mockParams,
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => callback(), [callback]);
  },
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    push: jest.fn(),
  },
}));
jest.mock('@/components/design-system/app-top-bar', () => ({ AppTopBar: () => null }));
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  // One stable function, as the provider gives; it reads the current locale per call.
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: mockI18n.locale, t: mockTranslate }) };
});
jest.mock('@/data/organization-staff', () => ({
  ...jest.requireActual('@/data/organization-staff'),
  getOrganizationStaff: jest.fn(),
  endOrganizationStaffMembership: jest.fn(),
}));
jest.mock('@/data/staff-workforce', () => ({
  ...jest.requireActual('@/data/staff-workforce'),
  getOrganizationVeterinarianWorkforce: jest.fn(),
  endStaffResponsibility: jest.fn(),
  endStaffVeterinarianClinicAssignment: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/data/professional-clinics', () => ({
  ...jest.requireActual('@/data/professional-clinics'),
  getMyProfessionalClinics: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const staffRead = getOrganizationStaff as jest.Mock;
const workforceRead = getOrganizationVeterinarianWorkforce as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;
const clinicsRead = getMyProfessionalClinics as jest.Mock;
const endGrant = endStaffResponsibility as jest.Mock;
const endAccessMock = endOrganizationStaffMembership as jest.Mock;
const endAssignment = endStaffVeterinarianClinicAssignment as jest.Mock;

const LONG_CLINIC = 'Clínica Veterinaria del Ensanche de Vallecas con un nombre muy largo';
const grant = (
  id: string,
  responsibility: StaffResponsibility['responsibility'],
  clinicId: string | null = null,
): StaffResponsibility => ({
  responsibilityGrantId: id,
  responsibility,
  scope:
    clinicId === null
      ? { type: 'ORGANIZATION' }
      : { type: 'CLINIC', clinic: { clinicId, displayName: LONG_CLINIC } },
});
const member = (overrides: Partial<StaffMember> = {}): StaffMember => ({
  membershipId: 'm1',
  effectiveStart: '2020-01-01T00:00:00Z',
  isSelf: false,
  displayName: 'Laura Fernández',
  invitationRecipientEmail: null,
  responsibilities: [
    grant('g-recep', 'RECEPTIONIST', 'c1'),
    grant('g-admin', 'ADMINISTRATOR'),
    grant('g-vet', 'VETERINARIAN'),
  ],
  ...overrides,
});
const staff = (organizationId: string, members: StaffMember[]): StaffResult => ({
  data: {
    organizationId,
    organizationDisplayName: `Organization ${organizationId}`,
    members,
    pendingInvitations: [],
  },
  error: null,
});
const workforce = (organizationId: string, members: WorkforceMember[]) => ({
  data: { organizationId, members },
  error: null,
});
const vetEntry = (profile: boolean, clinicIds: string[] = []): WorkforceMember => ({
  membershipId: 'm1',
  hasVeterinarianProfessionalProfile: profile,
  clinicAssignments: clinicIds.map((clinicId) => ({
    veterinarianClinicAssignmentId: `a-${clinicId}`,
    clinic: { clinicId, displayName: clinicId === 'c1' ? LONG_CLINIC : `Clinic ${clinicId}` },
  })),
});
const MANAGER: ProfessionalCapability[] = [
  'ORGANIZATION_INVITE_MEMBERS',
  'ORGANIZATION_END_MEMBERSHIPS',
  'ORGANIZATION_GRANT_RESPONSIBILITIES',
  'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
];
const context = (organizationId: string, granted: ProfessionalCapability[] = MANAGER) => ({
  data: {
    hasVeterinarianProfessionalProfile: false,
    organizations: [
      {
        membershipId: `self-${organizationId}`,
        organizationId,
        organizationDisplayName: organizationId,
        responsibilities: [],
        capabilities: granted.map((capability) => ({
          capability,
          scope: { type: 'ORGANIZATION' },
        })),
        unknownCapabilities: [],
        clinicAssignments: [],
        entitlements: {
          APPOINTMENT_MANAGEMENT: true,
          PROFESSIONAL_SCHEDULING: true,
          CLINICAL_CARE: false,
          CLINICAL_DOCUMENTATION: false,
        },
      },
    ],
  },
  error: null,
});
const clinics = (organizationId: string) => ({
  data: {
    clinics: ['c1', 'c2'].map((clinicId) => ({
      clinicId,
      clinicDisplayName: clinicId === 'c1' ? LONG_CLINIC : `Clinic ${clinicId}`,
      organizationId,
      organizationDisplayName: organizationId,
      capabilities: [],
      unknownCapabilities: [],
    })),
  },
  error: null,
});

let tree: ReactTestRenderer;
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const buttons = () =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
  );
const button = (label: string) => {
  const found = buttons().find((node) => node.props.accessibilityLabel === label);
  if (!found) throw new Error(`No button ${label}`);
  return found;
};
const labels = () => [...new Set(buttons().map((node) => node.props.accessibilityLabel))];
/** The action shows only its icon (a font glyph): no visible word, just the accessible name. */
const iconOnly = (node: ReturnType<typeof button>, icon: string) =>
  node.findAll((child) => child.props.name === icon).length > 0 &&
  node
    .findAllByType(Text)
    .every((text) => !/\p{L}/u.test(([] as unknown[]).concat(text.props.children).join('')));
async function render() {
  await act(async () => {
    tree = create(createElement(StaffMemberRoute));
  });
}
async function press(label: string) {
  await act(async () => {
    button(label).props.onPress();
  });
}
const t = (key: string, options?: Record<string, string>) => i18n.t(key, options);
const NAME = 'Laura Fernández';
const recepLabel = () =>
  t('staff.roleInClinic', {
    role: t('professional.responsibilityReceptionist'),
    scopeLabel: t('staff.clinicScope'),
    clinic: LONG_CLINIC,
  });
const vetLabel = () =>
  t('staff.roleInOrganization', {
    role: t('professional.responsibilityVeterinarian'),
    scopeLabel: t('staff.organizationScope'),
  });
const endLabel = (responsibility: string) =>
  t('staffMember.endAccessibility', { responsibility, name: NAME });
const changeLabel = (responsibility: string) =>
  t('staffMember.changeAccessibility', { responsibility, name: NAME });
// The Veterinarian card header icons: they name the responsibility, not the Profile.
const vetChange = () => t('staffMember.changeVeterinarianAccessibility', { name: NAME });
const vetEnd = () => t('staffMember.endVeterinarianAccessibility', { name: NAME });
const GRANT_ACTION = /Cambiar|Finalizar|Editar la responsabilidad|Eliminar la responsabilidad/;
let alertSpy: jest.SpyInstance;

beforeEach(() => {
  i18n.locale = 'es';
  mockParams = { organizationId: 'A', membershipId: 'm1' };
  jest.clearAllMocks();
  staffRead.mockReset().mockResolvedValue(staff('A', [member()]));
  workforceRead.mockReset().mockResolvedValue(workforce('A', [vetEntry(false)]));
  contextRead.mockReset().mockResolvedValue(context('A'));
  clinicsRead.mockReset().mockResolvedValue(clinics('A'));
  // Confirm every destructive dialog.
  alertSpy = jest
    .spyOn(Alert, 'alert')
    .mockImplementation((_title, _message, actions?: AlertButton[]) => {
      actions?.find((action) => action.style === 'destructive')?.onPress?.();
    });
});
afterEach(() => {
  act(() => tree.unmount());
  alertSpy.mockRestore();
  i18n.locale = 'es';
});

const RECEPTION = () => t('staffRoles.receptionist');
const ADMINISTRATION = () => t('staffRoles.administrator');
const VETERINARIAN = () => t('staffRoles.veterinarian');
const headers = () =>
  tree.root
    .findAllByType(Text)
    .filter((node) => node.props.accessibilityRole === 'header')
    .map((node) => String(node.props.children));

it('groups the Grants by responsibility with their Clinics, each managed individually — never a single role', async () => {
  await render();
  expect(headers()).toEqual(
    expect.arrayContaining([VETERINARIAN(), RECEPTION(), ADMINISTRATION()]),
  );
  // Reception lists its Clinic; Organization-wide Administration covers every Clinic.
  expect(texts()).toEqual(expect.arrayContaining([NAME, LONG_CLINIC, t('staff.allClinics')]));
  expect(labels()).toContain(changeLabel(recepLabel()));
  expect(labels()).toContain(endLabel(recepLabel()));
  expect(labels()).toEqual(expect.arrayContaining([vetChange(), vetEnd()]));
  // Accessible names say the action concerns the responsibility, not the Profile.
  expect(vetEnd()).toMatch(/responsabilidad Veterinario\/a/);
  expect(vetEnd()).toMatch(/No borra su perfil profesional/);
  expect(labels()).toContain(t('staffMember.addAction'));
  expect(labels()).toContain(t('staff.endAccessAccessibility', { name: NAME }));
});

it('ends exactly the chosen Grant and shows the authoritative re-read with the others kept', async () => {
  await render();
  endGrant.mockResolvedValue({
    kind: 'outcome',
    outcome: 'ENDED',
    responsibilityGrantId: 'g-recep',
  });
  staffRead.mockResolvedValue(
    staff('A', [
      member({
        responsibilities: [grant('g-admin', 'ADMINISTRATOR'), grant('g-vet', 'VETERINARIAN')],
      }),
    ]),
  );
  await press(endLabel(recepLabel()));
  expect(endGrant).toHaveBeenCalledTimes(1);
  expect(endGrant).toHaveBeenCalledWith('A', 'g-recep');
  expect(texts()).toContain(t('staffMember.ended'));
  expect(headers()).not.toContain(RECEPTION());
  expect(texts()).not.toContain(LONG_CLINIC);
  expect(headers()).toEqual(expect.arrayContaining([VETERINARIAN(), ADMINISTRATION()]));
  expect(labels()).toContain(vetEnd());
});

it('guides the last Responsibility to End access instead of ending it', async () => {
  staffRead.mockResolvedValue(
    staff('A', [member({ responsibilities: [grant('g-recep', 'RECEPTIONIST', 'c1')] })]),
  );
  workforceRead.mockResolvedValue(workforce('A', []));
  await render();
  endGrant.mockResolvedValue({ kind: 'rejected', reason: 'LAST_RESPONSIBILITY' });
  await press(endLabel(recepLabel()));
  expect(texts()).toContain(t('staffMember.lastResponsibility'));
  expect(
    labels().filter((label) => label === t('staff.endAccessAccessibility', { name: NAME })),
  ).toHaveLength(1);
  expect(
    buttons().filter(
      (node) => node.props.accessibilityLabel === t('staff.endAccessAccessibility', { name: NAME }),
    ),
  ).toHaveLength(2);
});

it('explains that Clinic Assignments must be ended before VETERINARIAN; nothing ends automatically', async () => {
  workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c1'])]));
  await render();
  endGrant.mockResolvedValue({ kind: 'rejected', reason: 'VETERINARIAN_ASSIGNMENTS_ACTIVE' });
  await press(vetEnd());
  expect(texts()).toContain(t('staffMember.veterinarianAssignmentsActive'));
  expect(endAssignment).not.toHaveBeenCalled();
  expect(texts()).toContain(LONG_CLINIC);
});

it('protects an Owner Membership and the acting non-Owner’s own Grants', async () => {
  staffRead.mockResolvedValue(
    staff('A', [
      member({ responsibilities: [grant('g-owner', 'OWNER'), grant('g-vet', 'VETERINARIAN')] }),
    ]),
  );
  await render();
  expect(labels().some((label) => GRANT_ACTION.test(label))).toBe(false);
  expect(labels()).not.toContain(t('staffMember.addAction'));
  act(() => tree.unmount());

  staffRead.mockResolvedValue(
    staff('A', [member({ isSelf: true, responsibilities: [grant('g-admin', 'ADMINISTRATOR')] })]),
  );
  workforceRead.mockResolvedValue(workforce('A', []));
  await render();
  expect(labels()).toContain(t('staffMember.addAction'));
  expect(labels().some((label) => GRANT_ACTION.test(label))).toBe(false);
  act(() => tree.unmount());

  staffRead.mockResolvedValue(
    staff('A', [
      member({
        isSelf: true,
        responsibilities: [grant('g-owner', 'OWNER'), grant('g-vet', 'VETERINARIAN')],
      }),
    ]),
  );
  await render();
  expect(labels()).toContain(vetEnd());
  expect(labels().filter((label) => /Finalizar|Eliminar/.test(label))).toHaveLength(1);
});

const addVetClinic = () => t('staffMember.addClinicAccessibility', { role: VETERINARIAN() });

it('shows the Veterinarian Profile pending in one line with no Add clinic, and never credential data', async () => {
  await render();
  expect(texts()).toContain(t('staffMember.profilePending'));
  expect(texts()).toEqual(
    expect.arrayContaining([t('staffMember.clinicsHeading'), t('staffAssignment.none')]),
  );
  expect(labels()).not.toContain(addVetClinic());
  // Nothing asks the administrator for the professional's credential facts.
  expect(texts()).not.toContain(t('veterinarianProfile.identifierLabel'));
  expect(texts()).not.toContain(t('veterinarianProfile.contextLabel'));
});

it('shows a completed Profile without Assignments as a brief empty state with Add clinic', async () => {
  workforceRead.mockResolvedValue(workforce('A', [vetEntry(true)]));
  await render();
  expect(texts()).toContain(t('staffMember.profileCompleted'));
  expect(texts()).toContain(t('staffAssignment.none'));
  expect(texts()).not.toContain(t('staffMember.profilePending'));
  expect(labels()).toContain(addVetClinic());
  // Visible "Añadir": the section, Veterinario/a's and Recepción's "Clínicas" (Clinic c2 is free).
  expect(texts().filter((text) => text === t('staffMember.add'))).toHaveLength(3);
});

it('shows an assigned Veterinarian with its Clinics as a compact list, one remove icon per Clinic', async () => {
  workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c1', 'c2'])]));
  await render();
  expect(texts()).toEqual(
    expect.arrayContaining([t('staffMember.profileCompleted'), LONG_CLINIC, 'Clinic c2']),
  );
  expect(texts()).not.toContain(t('staffAssignment.none'));
  for (const clinic of [LONG_CLINIC, 'Clinic c2'])
    expect(
      iconOnly(
        button(t('staffAssignment.endAccessibility', { clinic, name: NAME })),
        'trash-outline',
      ),
    ).toBe(true);
});

it('gives no Veterinarian section or Profile note to a Member without VETERINARIAN', async () => {
  staffRead.mockResolvedValue(
    staff('A', [member({ responsibilities: [grant('g-recep', 'RECEPTIONIST', 'c1')] })]),
  );
  workforceRead.mockResolvedValue(workforce('A', []));
  await render();
  expect(headers()).not.toContain(VETERINARIAN());
  expect(texts()).not.toContain(t('staffMember.profilePending'));
});

it('explains the pending Profile in English', async () => {
  i18n.locale = 'en';
  await render();
  expect(texts()).toContain('Veterinarian profile pending — completed by the professional');
});

it('lists current Assignments with a remove icon, offers Add clinic for an unassigned Clinic, and ends one Assignment', async () => {
  workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c1'])]));
  await render();
  expect(texts()).toContain(t('staffMember.profileCompleted'));
  expect(labels()).toContain(addVetClinic());
  await press(addVetClinic());
  expect(router.push).toHaveBeenCalledWith({
    pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/assign-clinic',
    params: { organizationId: 'A', membershipId: 'm1' },
  });
  endAssignment.mockResolvedValue({
    kind: 'outcome',
    outcome: 'ENDED',
    veterinarianClinicAssignmentId: 'a-c1',
  });
  workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, [])]));
  await press(t('staffAssignment.endAccessibility', { clinic: LONG_CLINIC, name: NAME }));
  expect(endAssignment).toHaveBeenCalledWith('A', 'c1', 'a-c1');
  expect(texts()).toContain(t('staffAssignment.ended'));
});

it('opens Change for exactly the named Grant', async () => {
  await render();
  await press(changeLabel(recepLabel()));
  expect(router.push).toHaveBeenCalledWith({
    pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/responsibility',
    params: { organizationId: 'A', membershipId: 'm1', grantId: 'g-recep' },
  });
});

it('treats 42501 after a successful load as lost access and clears the screen', async () => {
  await render();
  endGrant.mockResolvedValue({ kind: 'accessDenied' });
  await press(endLabel(recepLabel()));
  expect(router.dismissTo).toHaveBeenCalledWith('/professional');
});

it('shows a Member that left the Staff read as unavailable, never an empty Member', async () => {
  staffRead.mockResolvedValue(staff('A', []));
  await render();
  expect(texts()).toContain(t('staffMember.memberUnavailable'));
  expect(labels()).not.toContain(t('staffMember.addAction'));
});

it('isolates Organizations: switching A → B → A shows only that route’s Member', async () => {
  await render();
  expect(staffRead).toHaveBeenLastCalledWith('A');
  mockParams = { organizationId: 'B', membershipId: 'm1' };
  staffRead.mockResolvedValue(
    staff('B', [member({ displayName: 'Bea', responsibilities: [grant('g-b', 'RECEPTIONIST')] })]),
  );
  workforceRead.mockResolvedValue(workforce('B', []));
  contextRead.mockResolvedValue(context('B'));
  clinicsRead.mockResolvedValue(clinics('B'));
  await act(async () => {
    tree.update(createElement(StaffMemberRoute));
  });
  expect(staffRead).toHaveBeenLastCalledWith('B');
  expect(workforceRead).toHaveBeenLastCalledWith('B');
  expect(texts()).toContain('Bea');
  expect(texts()).not.toContain(NAME);
  expect(headers()).not.toContain(VETERINARIAN());
});

it('is not offered without the advisory Responsibility-management capability', async () => {
  contextRead.mockResolvedValue(context('A', ['ORGANIZATION_INVITE_MEMBERS']));
  await render();
  expect(texts()).toContain(t('staff.unavailable'));
});

it('renders English labels for management actions', async () => {
  i18n.locale = 'en';
  await render();
  expect(labels()).toContain(
    "Remove Laura Fernández's Veterinarian responsibility. Their professional profile isn't deleted.",
  );
  expect(labels()).toContain('Remove Laura Fernández from this organization');
  expect(texts()).toContain('Remove from organization');
  expect(labels()).toContain('Add responsibility');
  expect(texts()).toContain('Responsibilities');
  expect(headers()).toEqual(
    expect.arrayContaining(['Veterinarian', 'Reception', 'Administration']),
  );
  expect(texts()).toContain('All clinics, including future ones');
});

describe('person → responsibility → Clinics', () => {
  const only = (...responsibilities: StaffResponsibility[]) =>
    staffRead.mockResolvedValue(staff('A', [member({ responsibilities })]));
  const addReceptionClinic = () => t('staffMember.addClinicAccessibility', { role: RECEPTION() });
  const clinicRecepLabel = (clinic: string) =>
    t('staff.roleInClinic', {
      role: t('professional.responsibilityReceptionist'),
      scopeLabel: t('staff.clinicScope'),
      clinic,
    });
  const orgLabel = (role: string) =>
    t('staff.roleInOrganization', { role, scopeLabel: t('staff.organizationScope') });
  beforeEach(() => workforceRead.mockResolvedValue(workforce('A', [])));

  it('shows a single responsibility as one group and offers one more reception Clinic', async () => {
    only(grant('g-recep', 'RECEPTIONIST', 'c1'));
    await render();
    expect(headers()).toContain(RECEPTION());
    expect(headers()).not.toContain(VETERINARIAN());
    expect(headers()).not.toContain(ADMINISTRATION());
    expect(labels()).toContain(addReceptionClinic());
    await press(addReceptionClinic());
    expect(router.push).toHaveBeenCalledWith({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/responsibility',
      params: { organizationId: 'A', membershipId: 'm1', clinicRole: 'RECEPTIONIST' },
    });
  });

  it('lists Reception at several Clinics under one heading, each Clinic with its own Change and End', async () => {
    staffRead.mockResolvedValue(
      staff('A', [
        member({
          responsibilities: [
            grant('g-c1', 'RECEPTIONIST', 'c1'),
            {
              responsibilityGrantId: 'g-c2',
              responsibility: 'RECEPTIONIST',
              scope: { type: 'CLINIC', clinic: { clinicId: 'c2', displayName: 'Clinic c2' } },
            },
          ],
        }),
      ]),
    );
    await render();
    expect(headers().filter((header) => header === RECEPTION())).toHaveLength(1);
    expect(texts()).toEqual(expect.arrayContaining([LONG_CLINIC, 'Clinic c2']));
    for (const clinic of [LONG_CLINIC, 'Clinic c2']) {
      expect(labels()).toContain(changeLabel(clinicRecepLabel(clinic)));
      expect(labels()).toContain(endLabel(clinicRecepLabel(clinic)));
    }
    // Every Clinic of the Organization is already covered: no duplicate is offered.
    expect(labels()).not.toContain(addReceptionClinic());
  });

  it('explains Organization-wide Reception as every Clinic, including future ones', async () => {
    only(grant('g-recep', 'RECEPTIONIST'));
    await render();
    expect(texts()).toContain(t('staff.allClinics'));
    expect(labels()).toContain(endLabel(orgLabel(t('professional.responsibilityReceptionist'))));
    expect(labels()).not.toContain(addReceptionClinic());
    expect(texts()).not.toContain(t('staffMember.redundantScope'));
  });

  it('keeps redundant Organization and Clinic Grants visible and individually manageable', async () => {
    only(grant('g-org', 'RECEPTIONIST'), grant('g-c1', 'RECEPTIONIST', 'c1'));
    await render();
    expect(texts()).toEqual(
      expect.arrayContaining([t('staff.allClinics'), LONG_CLINIC, t('staffMember.redundantScope')]),
    );
    expect(labels()).toContain(endLabel(orgLabel(t('professional.responsibilityReceptionist'))));
    expect(labels()).toContain(endLabel(clinicRecepLabel(LONG_CLINIC)));
    expect(endGrant).not.toHaveBeenCalled();
  });

  it('shows Veterinarian and Reception side by side, each with its own Clinics', async () => {
    only(grant('g-vet', 'VETERINARIAN'), grant('g-recep', 'RECEPTIONIST', 'c1'));
    workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c2'])]));
    await render();
    expect(headers()).toEqual(expect.arrayContaining([VETERINARIAN(), RECEPTION()]));
    expect(texts()).toEqual(expect.arrayContaining(['Clinic c2', LONG_CLINIC]));
    expect(labels()).toContain(
      t('staffAssignment.endAccessibility', { clinic: 'Clinic c2', name: NAME }),
    );
    expect(labels()).toContain(endLabel(clinicRecepLabel(LONG_CLINIC)));
    expect(labels()).toContain(vetEnd());
  });

  it('keeps a stale Assignment endable under Veterinarian when the Grant has ended', async () => {
    only(grant('g-recep', 'RECEPTIONIST', 'c1'));
    workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c2'])]));
    await render();
    expect(headers()).toContain(VETERINARIAN());
    expect(texts()).toContain(t('staffMember.veterinarianEnded'));
    expect(labels()).toContain(
      t('staffAssignment.endAccessibility', { clinic: 'Clinic c2', name: NAME }),
    );
    expect(labels()).not.toContain(addVetClinic());
    expect(labels()).not.toContain(vetEnd());
    expect(labels()).not.toContain(vetChange());
  });

  it('keeps OWNER read-only without hiding the Owner’s other responsibilities', async () => {
    only(grant('g-owner', 'OWNER'), grant('g-recep', 'RECEPTIONIST', 'c1'));
    await render();
    expect(headers()).toEqual(expect.arrayContaining([t('staffRoles.owner'), RECEPTION()]));
    expect(texts()).toEqual(expect.arrayContaining([t('staffMember.ownerNote'), LONG_CLINIC]));
    expect(labels().some((label) => /Cambiar|Finalizar|Añadir/.test(label))).toBe(false);
  });

  it('offers no Clinic Assignment action without the advisory Assignment capability', async () => {
    contextRead.mockResolvedValue(
      context('A', [
        'ORGANIZATION_INVITE_MEMBERS',
        'ORGANIZATION_END_MEMBERSHIPS',
        'ORGANIZATION_GRANT_RESPONSIBILITIES',
      ]),
    );
    only(grant('g-vet', 'VETERINARIAN'));
    workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c1'])]));
    await render();
    expect(texts()).toContain(LONG_CLINIC);
    expect(labels()).not.toContain(addVetClinic());
    expect(labels()).not.toContain(
      t('staffAssignment.endAccessibility', { clinic: LONG_CLINIC, name: NAME }),
    );
    // Responsibility actions still follow their own capability.
    expect(labels()).toContain(vetEnd());
  });

  it('shows a load error with Retry, then the Member once the re-read succeeds', async () => {
    staffRead.mockResolvedValueOnce({ data: null, error: 'boom' });
    await render();
    expect(texts()).toContain(t('staffMember.loadError'));
    only(grant('g-recep', 'RECEPTIONIST', 'c1'));
    await press(t('professional.retry'));
    expect(headers()).toContain(RECEPTION());
  });

  it('puts the Veterinarian Grant icons in the card header and Add beside each Clinics subtitle', async () => {
    only(grant('g-vet', 'VETERINARIAN'), grant('g-recep', 'RECEPTIONIST', 'c1'));
    workforceRead.mockResolvedValue(workforce('A', [vetEntry(true)]));
    await render();
    // Every card titles its list "Clínicas".
    expect(texts().filter((text) => text === 'Clínicas')).toHaveLength(2);
    expect(texts()).not.toContain('Clínicas donde ejerce');
    // "Añadir": once for the section, once per Clinics subtitle (Veterinarian, Reception);
    // the accessible names stay specific.
    expect(texts().filter((text) => text === 'Añadir')).toHaveLength(3);
    expect(addVetClinic()).toBe('Añadir clínica de Veterinario/a');
    expect(addReceptionClinic()).toBe('Añadir clínica de Recepción');
    expect(labels()).toEqual(
      expect.arrayContaining([addVetClinic(), addReceptionClinic(), t('staffMember.addAction')]),
    );
    // The Veterinarian Grant is edited/removed from header icons, no footer buttons.
    expect(iconOnly(button(vetChange()), 'create-outline')).toBe(true);
    expect(iconOnly(button(vetEnd()), 'trash-outline')).toBe(true);
    const header = tree.root.findAll(
      (node) =>
        node.findAllByType(Text).some((text) => text.props.children === VETERINARIAN()) &&
        node.findAll((child) => child.props.accessibilityLabel === vetEnd()).length > 0 &&
        node.findAll((child) => child.props.accessibilityLabel === addVetClinic()).length === 0,
    );
    expect(header.length).toBeGreaterThan(0);
    // The Reception Clinic row offers Edit and Remove as icons only.
    expect(iconOnly(button(changeLabel(clinicRecepLabel(LONG_CLINIC))), 'create-outline')).toBe(
      true,
    );
    expect(iconOnly(button(endLabel(clinicRecepLabel(LONG_CLINIC))), 'trash-outline')).toBe(true);
    for (const word of ['Cambiar', 'Finalizar', 'Editar', 'Eliminar'])
      expect(texts()).not.toContain(word);
  });

  it('offers no responsibility-wide removal for Reception with several Grants: one trash per Grant', async () => {
    only(grant('g-org', 'RECEPTIONIST'), grant('g-c1', 'RECEPTIONIST', 'c1'), {
      responsibilityGrantId: 'g-c2',
      responsibility: 'RECEPTIONIST',
      scope: { type: 'CLINIC', clinic: { clinicId: 'c2', displayName: 'Clinic c2' } },
    });
    await render();
    const ends = labels().filter(
      (label) => label.startsWith('Finalizar') || /Eliminar/.test(label),
    );
    expect(ends.sort()).toEqual(
      [
        endLabel(orgLabel(t('professional.responsibilityReceptionist'))),
        endLabel(clinicRecepLabel(LONG_CLINIC)),
        endLabel(clinicRecepLabel('Clinic c2')),
      ].sort(),
    );
    // The Organization-wide Grant keeps its own Change and End.
    expect(labels()).toContain(changeLabel(orgLabel(t('professional.responsibilityReceptionist'))));
    endGrant.mockResolvedValue({
      kind: 'outcome',
      outcome: 'ENDED',
      responsibilityGrantId: 'g-c1',
    });
    await press(endLabel(clinicRecepLabel(LONG_CLINIC)));
    expect(endGrant).toHaveBeenCalledTimes(1);
    expect(endGrant).toHaveBeenCalledWith('A', 'g-c1');
  });

  it('ends exactly the pressed Clinic Assignment, never the others or the Grant', async () => {
    only(grant('g-vet', 'VETERINARIAN'));
    workforceRead.mockResolvedValue(workforce('A', [vetEntry(true, ['c1', 'c2'])]));
    await render();
    endAssignment.mockResolvedValue({
      kind: 'outcome',
      outcome: 'ENDED',
      veterinarianClinicAssignmentId: 'a-c2',
    });
    await press(t('staffAssignment.endAccessibility', { clinic: 'Clinic c2', name: NAME }));
    expect(endAssignment).toHaveBeenCalledTimes(1);
    expect(endAssignment).toHaveBeenCalledWith('A', 'c2', 'a-c2');
    expect(endGrant).not.toHaveBeenCalled();
  });

  it('labels membership removal as "Quitar de la organización" and confirms the account is kept', async () => {
    await render();
    expect(texts()).toContain('Quitar de la organización');
    expect(labels()).toContain(t('staff.endAccessAccessibility', { name: NAME }));
    endAccessMock.mockResolvedValue({ kind: 'outcome', outcome: 'ENDED' });
    await press(t('staff.endAccessAccessibility', { name: NAME }));
    const [title, message, choices] = alertSpy.mock.calls.at(-1) as [string, string, AlertButton[]];
    expect(title).toBe('¿Quitar de Organization A?');
    expect(message).toMatch(/dejará de pertenecer a Organization A/);
    expect(message).toMatch(/No se elimina su cuenta de MenizVet/);
    expect(choices.map((choice) => choice.text)).toEqual(['Cancelar', 'Quitar']);
    expect(endAccessMock).toHaveBeenCalledWith('m1');
  });

  it('opens Edit for the VETERINARIAN Grant and removes it with the existing confirmation', async () => {
    only(grant('g-vet', 'VETERINARIAN'), grant('g-recep', 'RECEPTIONIST', 'c1'));
    await render();
    await press(vetChange());
    expect(router.push).toHaveBeenCalledWith({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/responsibility',
      params: { organizationId: 'A', membershipId: 'm1', grantId: 'g-vet' },
    });
    endGrant.mockResolvedValue({
      kind: 'outcome',
      outcome: 'ENDED',
      responsibilityGrantId: 'g-vet',
    });
    await press(vetEnd());
    expect(alertSpy).toHaveBeenCalledWith(
      t('staffMember.endConfirmTitle'),
      expect.stringContaining(vetLabel()),
      expect.any(Array),
    );
    expect(endGrant).toHaveBeenCalledTimes(1);
    expect(endGrant).toHaveBeenCalledWith('A', 'g-vet');
  });

  it('uses the short labels in English', async () => {
    i18n.locale = 'en';
    only(grant('g-vet', 'VETERINARIAN'), grant('g-recep', 'RECEPTIONIST', 'c1'));
    workforceRead.mockResolvedValue(workforce('A', [vetEntry(true)]));
    await render();
    expect(texts().filter((text) => text === 'Clinics')).toHaveLength(2);
    expect(texts().filter((text) => text === 'Add')).toHaveLength(3);
    expect(labels()).toEqual(
      expect.arrayContaining(['Add Veterinarian clinic', 'Add Reception clinic']),
    );
    expect(labels()).toContain(
      "Edit Laura Fernández's Veterinarian responsibility. Their professional profile doesn't change.",
    );
  });
});

describe('Remove from organization (End access) — now only in the Member detail', () => {
  const endAccessLabel = () => t('staff.endAccessAccessibility', { name: NAME });
  const listHref = {
    pathname: '/professional/organizations/[organizationId]/staff',
    params: { organizationId: 'A' },
  };
  let announce: jest.SpyInstance;
  beforeEach(() => {
    announce = jest
      .spyOn(AccessibilityInfo, 'announceForAccessibility')
      .mockImplementation(() => {});
  });
  afterEach(() => announce.mockRestore());

  it.each(['ENDED', 'ALREADY_ENDED'] as const)(
    '%s: re-reads, announces success and returns to the Staff list',
    async (outcome) => {
      await render();
      endAccessMock.mockResolvedValue({ kind: 'outcome', outcome, effectiveEnd: '2030-01-02' });
      staffRead.mockResolvedValue(staff('A', []));
      await press(endAccessLabel());
      expect(endAccessMock).toHaveBeenCalledTimes(1);
      expect(endAccessMock).toHaveBeenCalledWith('m1');
      expect(announce).toHaveBeenCalledWith(t('staff.endAccessDone'));
      expect(router.dismissTo).toHaveBeenCalledWith(listHref);
    },
  );

  it('a lost response whose re-read no longer lists the member is success', async () => {
    await render();
    endAccessMock.mockResolvedValue({ kind: 'uncertain' });
    staffRead.mockResolvedValue(staff('A', []));
    await press(endAccessLabel());
    expect(endAccessMock).toHaveBeenCalledTimes(1);
    expect(router.dismissTo).toHaveBeenCalledWith(listHref);
  });

  it('a lost response whose re-read still lists the member is a calm failure, never a retry', async () => {
    await render();
    endAccessMock.mockResolvedValue({ kind: 'uncertain' });
    await press(endAccessLabel());
    expect(endAccessMock).toHaveBeenCalledTimes(1);
    expect(texts()).toContain(t('staff.endAccessFailed'));
    expect(router.dismissTo).not.toHaveBeenCalled();
  });

  it('a protected target reached through stale state is reported calmly', async () => {
    await render();
    endAccessMock.mockResolvedValue({ kind: 'protected' });
    await press(endAccessLabel());
    expect(texts()).toContain(t('staff.endAccessNotAllowed'));
  });

  it('42501 means Staff access is lost: the screen leaves to Professional', async () => {
    await render();
    endAccessMock.mockResolvedValue({ kind: 'accessDenied' });
    staffRead.mockResolvedValue({ data: null, error: 'STAFF_ACCESS_DENIED' });
    await press(endAccessLabel());
    expect(router.dismissTo).toHaveBeenCalledWith('/professional');
  });

  it('Cancel performs no mutation', async () => {
    alertSpy.mockImplementation(() => undefined);
    await render();
    await press(endAccessLabel());
    expect(alertSpy).toHaveBeenCalled();
    expect(endAccessMock).not.toHaveBeenCalled();
  });

  it('is never offered on the caller’s own row, an Owner, or without the capability', async () => {
    staffRead.mockResolvedValue(staff('A', [member({ isSelf: true })]));
    await render();
    expect(labels()).not.toContain(endAccessLabel());
    act(() => tree.unmount());

    staffRead.mockResolvedValue(
      staff('A', [member({ responsibilities: [grant('g-owner', 'OWNER')] })]),
    );
    await render();
    expect(labels()).not.toContain(endAccessLabel());
    act(() => tree.unmount());

    staffRead.mockResolvedValue(staff('A', [member()]));
    contextRead.mockResolvedValue(
      context('A', ['ORGANIZATION_INVITE_MEMBERS', 'ORGANIZATION_GRANT_RESPONSIBILITIES']),
    );
    await render();
    expect(labels()).not.toContain(endAccessLabel());
  });
});

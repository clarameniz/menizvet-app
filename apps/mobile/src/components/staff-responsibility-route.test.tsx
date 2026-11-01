import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import StaffAssignClinicRoute from '@/app/professional/organizations/[organizationId]/staff/[membershipId]/assign-clinic';
import StaffResponsibilityRoute from '@/app/professional/organizations/[organizationId]/staff/[membershipId]/responsibility';
import {
  getOrganizationStaff,
  type StaffMember,
  type StaffResponsibility,
} from '@/data/organization-staff';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext, type ProfessionalCapability } from '@/data/professional-context';
import {
  addStaffResponsibility,
  assignStaffVeterinarianToClinic,
  getOrganizationVeterinarianWorkforce,
  replaceStaffResponsibility,
  type WorkforceMember,
} from '@/data/staff-workforce';
import { i18n } from '@/i18n/i18n';

let mockParams: Record<string, string> = { organizationId: 'A', membershipId: 'm1' };
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => mockParams,
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    push: jest.fn(),
  },
}));
jest.mock('@/components/design-system/app-top-bar', () => ({ AppTopBar: () => null }));
jest.mock('react-native-safe-area-context', () => {
  const { View } = jest.requireActual('react-native');
  return {
    SafeAreaView: View,
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
  };
});
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
});
jest.mock('@/data/organization-staff', () => ({
  ...jest.requireActual('@/data/organization-staff'),
  getOrganizationStaff: jest.fn(),
}));
jest.mock('@/data/staff-workforce', () => ({
  ...jest.requireActual('@/data/staff-workforce'),
  getOrganizationVeterinarianWorkforce: jest.fn(),
  addStaffResponsibility: jest.fn(),
  replaceStaffResponsibility: jest.fn(),
  assignStaffVeterinarianToClinic: jest.fn(),
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
const add = addStaffResponsibility as jest.Mock;
const replace = replaceStaffResponsibility as jest.Mock;
const assign = assignStaffVeterinarianToClinic as jest.Mock;

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
      : { type: 'CLINIC', clinic: { clinicId, displayName: `Clinic ${clinicId}` } },
});
const member = (responsibilities: StaffResponsibility[]): StaffMember => ({
  membershipId: 'm1',
  effectiveStart: '2020-01-01T00:00:00Z',
  isSelf: false,
  displayName: 'Laura',
  invitationRecipientEmail: null,
  responsibilities,
});
const staff = (responsibilities: StaffResponsibility[]) => ({
  data: {
    organizationId: 'A',
    organizationDisplayName: 'Org A',
    members: [member(responsibilities)],
    pendingInvitations: [],
  },
  error: null,
});
const workforce = (members: WorkforceMember[]) => ({
  data: { organizationId: 'A', members },
  error: null,
});
const MANAGER: ProfessionalCapability[] = [
  'ORGANIZATION_GRANT_RESPONSIBILITIES',
  'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
];
const context = {
  data: {
    hasVeterinarianProfessionalProfile: false,
    organizations: [
      {
        membershipId: 'self',
        organizationId: 'A',
        organizationDisplayName: 'A',
        responsibilities: [],
        capabilities: MANAGER.map((capability) => ({
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
};
const clinics = {
  data: {
    clinics: [
      ['c1', 'A'],
      ['c2', 'A'],
      ['b1', 'B'],
    ].map(([clinicId, organizationId]) => ({
      clinicId,
      clinicDisplayName: `Clinic ${clinicId}`,
      organizationId,
      organizationDisplayName: organizationId,
      capabilities: [],
      unknownCapabilities: [],
    })),
  },
  error: null,
};

let tree: ReactTestRenderer;
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const pressables = (role: string) =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === role && typeof node.props.onPress === 'function',
  );
const radioLabels = () => [
  ...new Set(pressables('radio').map((node) => node.props.accessibilityLabel)),
];
const press = async (role: string, label: string) => {
  const found = pressables(role).find((node) => node.props.accessibilityLabel === label);
  if (!found) throw new Error(`No ${role} ${label}`);
  await act(async () => {
    found.props.onPress();
  });
};
const disabled = (label: string) =>
  pressables('button').find((node) => node.props.accessibilityLabel === label)!.props
    .accessibilityState.disabled === true;
async function render(component: () => ReturnType<typeof StaffResponsibilityRoute>) {
  await act(async () => {
    tree = create(createElement(component));
  });
}
const t = (key: string) => i18n.t(key);
const ADMIN = t('staffRoles.administrator');
const RECEPTIONIST = t('staffRoles.receptionist');
const VETERINARIAN = t('staffRoles.veterinarian');

beforeEach(() => {
  jest.clearAllMocks();
  mockParams = { organizationId: 'A', membershipId: 'm1' };
  staffRead
    .mockReset()
    .mockResolvedValue(
      staff([grant('g-recep', 'RECEPTIONIST', 'c1'), grant('g-vet', 'VETERINARIAN')]),
    );
  workforceRead.mockReset().mockResolvedValue(workforce([]));
  contextRead.mockReset().mockResolvedValue(context);
  clinicsRead.mockReset().mockResolvedValue(clinics);
});
afterEach(() => act(() => tree.unmount()));

describe('Add / Change one Responsibility (SPEC-ORG-006 §14)', () => {
  it('offers Administrator, Receptionist and Veterinarian — never Owner — and only this Organization’s Clinics', async () => {
    await render(StaffResponsibilityRoute);
    expect(radioLabels()).toEqual([
      ADMIN,
      RECEPTIONIST,
      VETERINARIAN,
      t('staffInvite.scopeOrganization'),
      t('staffInvite.scopeClinic'),
    ]);
    await press('radio', t('staffInvite.scopeClinic'));
    expect(radioLabels()).toContain('Clinic c1');
    expect(radioLabels()).not.toContain('Clinic b1');
  });
  it('adds one Grant and returns to the Member detail', async () => {
    add.mockResolvedValue({ kind: 'outcome', outcome: 'ADDED', responsibilityGrantId: 'g-new' });
    await render(StaffResponsibilityRoute);
    expect(disabled(t('staffResponsibility.addSubmit'))).toBe(true);
    await press('radio', ADMIN);
    await press('button', t('staffResponsibility.addSubmit'));
    expect(add).toHaveBeenCalledWith('A', 'm1', {
      role: 'ADMINISTRATOR',
      scope: 'ORGANIZATION',
      clinicId: null,
    });
    expect(replace).not.toHaveBeenCalled();
    expect(router.dismissTo).toHaveBeenCalledWith({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]',
      params: { organizationId: 'A', membershipId: 'm1' },
    });
  });
  it('does not offer a Responsibility the Member already holds', async () => {
    await render(StaffResponsibilityRoute);
    await press('radio', VETERINARIAN);
    expect(radioLabels()).not.toContain(t('staffInvite.scopeClinic'));
    expect(texts()).toContain(t('staffInvite.veterinarianScope'));
    expect(disabled(t('staffResponsibility.addSubmit'))).toBe(true);
  });
  it('changes exactly the named Grant (Clinic A → Clinic B)', async () => {
    mockParams = { organizationId: 'A', membershipId: 'm1', grantId: 'g-recep' };
    replace.mockResolvedValue({
      kind: 'outcome',
      outcome: 'REPLACED',
      responsibilityGrantId: 'g-new',
    });
    await render(StaffResponsibilityRoute);
    expect(
      pressables('radio').find((node) => node.props.accessibilityLabel === 'Clinic c1')!.props
        .accessibilityState.selected,
    ).toBe(true);
    expect(disabled(t('staffResponsibility.changeSubmit'))).toBe(true);
    await press('radio', 'Clinic c2');
    await press('button', t('staffResponsibility.changeSubmit'));
    expect(replace).toHaveBeenCalledTimes(1);
    expect(replace).toHaveBeenCalledWith('A', 'g-recep', {
      role: 'RECEPTIONIST',
      scope: 'CLINIC',
      clinicId: 'c2',
    });
    expect(add).not.toHaveBeenCalled();
  });
  it('shows a stale Change as already changed and an uncertain write as unconfirmed', async () => {
    mockParams = { organizationId: 'A', membershipId: 'm1', grantId: 'g-gone' };
    await render(StaffResponsibilityRoute);
    expect(texts()).toContain(t('staffMember.grantChanged'));
    act(() => tree.unmount());

    mockParams = { organizationId: 'A', membershipId: 'm1', grantId: 'g-recep' };
    replace.mockResolvedValue({ kind: 'uncertain' });
    await render(StaffResponsibilityRoute);
    await press('radio', ADMIN);
    await press('button', t('staffResponsibility.changeSubmit'));
    expect(texts()).toContain(t('staffMember.unconfirmed'));
    expect(router.dismissTo).not.toHaveBeenCalled();
  });
  it('"Add reception clinic" presets Reception with Clinic scope and offers only Clinics not yet held', async () => {
    mockParams = { organizationId: 'A', membershipId: 'm1', clinicRole: 'RECEPTIONIST' };
    add.mockResolvedValue({ kind: 'outcome', outcome: 'ADDED', responsibilityGrantId: 'g-new' });
    await render(StaffResponsibilityRoute);
    expect(texts()).toContain(t('staffMember.addReceptionClinic'));
    const selected = (label: string) =>
      pressables('radio').find((node) => node.props.accessibilityLabel === label)!.props
        .accessibilityState.selected;
    expect(selected(RECEPTIONIST)).toBe(true);
    expect(selected(t('staffInvite.scopeClinic'))).toBe(true);
    // Clinic c1 is already a reception Clinic of this Member.
    expect(radioLabels()).toContain('Clinic c2');
    expect(radioLabels()).not.toContain('Clinic c1');
    await press('radio', 'Clinic c2');
    await press('button', t('staffResponsibility.addSubmit'));
    expect(add).toHaveBeenCalledTimes(1);
    expect(add).toHaveBeenCalledWith('A', 'm1', {
      role: 'RECEPTIONIST',
      scope: 'CLINIC',
      clinicId: 'c2',
    });
    expect(replace).not.toHaveBeenCalled();
  });
  it('ignores an unknown preset and starts an ordinary Add', async () => {
    mockParams = { organizationId: 'A', membershipId: 'm1', clinicRole: 'OWNER' };
    await render(StaffResponsibilityRoute);
    expect(texts()).toContain(t('staffResponsibility.addTitle'));
    expect(
      pressables('radio').some(
        (node) =>
          [ADMIN, RECEPTIONIST, VETERINARIAN].includes(node.props.accessibilityLabel) &&
          node.props.accessibilityState.selected === true,
      ),
    ).toBe(false);
  });
  it('never offers Change on an OWNER Grant', async () => {
    mockParams = { organizationId: 'A', membershipId: 'm1', grantId: 'g-owner' };
    staffRead.mockResolvedValue(staff([grant('g-owner', 'OWNER')]));
    await render(StaffResponsibilityRoute);
    expect(texts()).toContain(t('staffMember.notAllowed'));
    expect(radioLabels()).toEqual([]);
  });
});

describe('Assign Clinic (SPEC-VET-004 §13)', () => {
  const vet = (profile: boolean, clinicIds: string[] = []): WorkforceMember => ({
    membershipId: 'm1',
    hasVeterinarianProfessionalProfile: profile,
    clinicAssignments: clinicIds.map((clinicId) => ({
      veterinarianClinicAssignmentId: `a-${clinicId}`,
      clinic: { clinicId, displayName: `Clinic ${clinicId}` },
    })),
  });
  it('offers only this Organization’s unassigned Clinics and assigns by Membership', async () => {
    workforceRead.mockResolvedValue(workforce([vet(true, ['c1'])]));
    assign.mockResolvedValue({
      kind: 'outcome',
      outcome: 'ASSIGNED',
      veterinarianClinicAssignmentId: 'a-c2',
    });
    await render(StaffAssignClinicRoute);
    expect(radioLabels()).toEqual(['Clinic c2']);
    await press('radio', 'Clinic c2');
    await press('button', t('staffAssignment.submit'));
    expect(assign).toHaveBeenCalledWith('A', 'm1', 'c2');
    expect(router.dismissTo).toHaveBeenCalled();
  });
  it('is not offered while the Profile is pending', async () => {
    workforceRead.mockResolvedValue(workforce([vet(false)]));
    await render(StaffAssignClinicRoute);
    expect(texts()).toContain(t('staffMember.profilePending'));
    expect(radioLabels()).toEqual([]);
  });
  it('reports a backend prerequisite calmly and stays', async () => {
    workforceRead.mockResolvedValue(workforce([vet(true)]));
    assign.mockResolvedValue({ kind: 'rejected', reason: 'VETERINARIAN_RESPONSIBILITY_REQUIRED' });
    await render(StaffAssignClinicRoute);
    await press('radio', 'Clinic c1');
    await press('button', t('staffAssignment.submit'));
    expect(texts()).toContain(t('staffAssignment.veterinarianRequired'));
    expect(router.dismissTo).not.toHaveBeenCalled();
  });
});

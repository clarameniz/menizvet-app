import { createElement } from 'react';
import { Alert, Text, TextInput } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import StaffInviteRoute from '@/app/professional/organizations/[organizationId]/staff/invite';
import {
  getOrganizationStaff,
  inviteOrganizationStaff,
  type OrganizationStaff,
  type PendingStaffInvitation,
  type StaffInviteResult,
  type StaffResult,
} from '@/data/organization-staff';
import { getMyProfessionalClinics, type ProfessionalClinic } from '@/data/professional-clinics';
import { getMyProfessionalContext, type ProfessionalCapability } from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';

let mockOrganizationId = 'A';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ organizationId: mockOrganizationId }),
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    replace: jest.fn(),
    push: jest.fn(),
  },
}));
jest.mock('react-native-safe-area-context', () => {
  const { View } = jest.requireActual('react-native');
  return {
    SafeAreaView: View,
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
  };
});
jest.mock('@/components/design-system/app-top-bar', () => {
  const React = jest.requireActual('react');
  const { Pressable } = jest.requireActual('react-native');
  return {
    AppTopBar: ({ onBack }: { onBack: () => void }) =>
      React.createElement(Pressable, { onPress: onBack, testID: 'back' }),
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
  inviteOrganizationStaff: jest.fn(),
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
const invite = inviteOrganizationStaff as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;
const clinicsRead = getMyProfessionalClinics as jest.Mock;

const invitation = (
  invitationId: string,
  recipientEmail: string,
  scope: PendingStaffInvitation['responsibilities'][number]['scope'] = { type: 'ORGANIZATION' },
): PendingStaffInvitation => ({
  invitationId,
  recipientEmail,
  responsibilities: [{ responsibility: 'ADMINISTRATOR', scope }],
  createdAt: '2030-01-01T00:00:00Z',
  expiresAt: '2030-01-08T00:00:00Z',
});
const staff = (id: string, pending: PendingStaffInvitation[] = []): StaffResult => ({
  data: {
    organizationId: id,
    organizationDisplayName: `Organization ${id}`,
    members: [],
    pendingInvitations: pending,
  } satisfies OrganizationStaff,
  error: null,
});
const context = (organizationId: string, granted: ProfessionalCapability[]) => ({
  data: {
    hasVeterinarianProfessionalProfile: false,
    organizations: [
      {
        membershipId: `m-${organizationId}`,
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
const clinic = (clinicId: string, organizationId: string): ProfessionalClinic => ({
  clinicId,
  clinicDisplayName: `Clinic ${clinicId}`,
  organizationId,
  organizationDisplayName: organizationId,
  capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
  unknownCapabilities: [],
});

let tree: ReactTestRenderer;
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const pressables = (role: string) =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === role && typeof node.props.onPress === 'function',
  );
const radio = (label: string) => {
  const found = pressables('radio').find((node) => node.props.accessibilityLabel === label);
  if (!found) throw new Error(`No option ${label}`);
  return found;
};
const radioLabels = () => [
  ...new Set(pressables('radio').map((node) => node.props.accessibilityLabel)),
];
const send = () =>
  pressables('button').find(
    (node) => node.props.accessibilityLabel === i18n.t('staffInvite.submit'),
  )!;
const sendDisabled = () => send().props.accessibilityState.disabled === true;
async function choose(label: string) {
  await act(async () => {
    radio(label).props.onPress();
  });
}
async function type(email: string) {
  await act(async () => {
    tree.root.findByType(TextInput).props.onChangeText(email);
  });
}
async function submit() {
  await act(async () => {
    send().props.onPress();
  });
}
async function render() {
  await act(async () => {
    tree = create(createElement(StaffInviteRoute));
  });
}
const ADMIN = i18n.t('staffRoles.administrator');
const RECEPTIONIST = i18n.t('staffRoles.receptionist');
const VETERINARIAN = i18n.t('staffRoles.veterinarian');
const ORGANIZATION_SCOPE = i18n.t('staffInvite.scopeOrganization');
const CLINIC_SCOPE = i18n.t('staffInvite.scopeClinic');

beforeEach(() => {
  mockOrganizationId = 'A';
  jest.clearAllMocks();
  staffRead.mockReset().mockResolvedValue(staff('A'));
  invite.mockReset();
  contextRead.mockReset().mockResolvedValue(context('A', ['ORGANIZATION_INVITE_MEMBERS']));
  clinicsRead.mockReset().mockResolvedValue({
    data: { clinics: [clinic('a1', 'A'), clinic('b1', 'B'), clinic('a2', 'A')] },
    error: null,
  });
});
afterEach(() => act(() => tree.unmount()));

it('offers exactly Administrator, Receptionist and Veterinarian, two scopes, one email field and no expiry', async () => {
  await render();
  expect(radioLabels()).toEqual([
    ADMIN,
    RECEPTIONIST,
    VETERINARIAN,
    ORGANIZATION_SCOPE,
    CLINIC_SCOPE,
  ]);
  expect(radioLabels()).not.toContain(i18n.t('staffRoles.owner'));
  expect(tree.root.findAllByType(TextInput)).toHaveLength(1);
  expect(texts()).toContain(i18n.t('staffInvite.validity'));
});
it('asks what the person will do, explains each role, and says more can be added after acceptance', async () => {
  await render();
  expect(texts()).toEqual(
    expect.arrayContaining([
      '¿Qué hará esta persona?',
      i18n.t('staffInvite.moreLater'),
      'Todas las clínicas, incluidas las futuras',
    ]),
  );
  await choose(RECEPTIONIST);
  expect(texts()).toContain(i18n.t('staffInvite.roleHelpReceptionist'));
  await choose(ADMIN);
  expect(texts()).toContain(i18n.t('staffInvite.roleHelpAdministrator'));
  expect(texts()).not.toContain(i18n.t('staffInvite.roleHelpReceptionist'));
  // One role at a time: choosing another replaces the previous one.
  expect(radio(RECEPTIONIST).props.accessibilityState.selected).toBe(false);
  await choose(CLINIC_SCOPE);
  await choose('Clinic a1');
  await choose('Clinic a2');
  expect(radio('Clinic a1').props.accessibilityState.selected).toBe(false);
  expect(radio('Clinic a2').props.accessibilityState.selected).toBe(true);
});
it('reveals only this Organization Clinics for Clinic scope and clears them when switching back', async () => {
  await render();
  expect(radioLabels()).not.toContain('Clinic a1');
  await choose(CLINIC_SCOPE);
  expect(radioLabels()).toEqual([
    ADMIN,
    RECEPTIONIST,
    VETERINARIAN,
    ORGANIZATION_SCOPE,
    CLINIC_SCOPE,
    'Clinic a1',
    'Clinic a2',
  ]);
  await type('laura@example.test');
  await choose(RECEPTIONIST);
  expect(sendDisabled()).toBe(true);
  await choose('Clinic a2');
  expect(sendDisabled()).toBe(false);
  await choose(ORGANIZATION_SCOPE);
  expect(radioLabels()).not.toContain('Clinic a2');
  await choose(CLINIC_SCOPE);
  expect(radio('Clinic a2').props.accessibilityState.selected).toBe(false);
  expect(sendDisabled()).toBe(true);
});
it('invites a Veterinarian for the whole Organization only: no scope or Clinic choice, no Assignment', async () => {
  invite.mockResolvedValue({ kind: 'created', invitationId: 'new' } satisfies StaffInviteResult);
  await render();
  await choose(CLINIC_SCOPE);
  await choose('Clinic a1');
  await type('vet@example.test');
  await choose(VETERINARIAN);
  // SPEC-ORG-002 BR-17: Veterinarian fixes the scope; the drafted Clinic is dropped.
  expect(radioLabels()).toEqual([ADMIN, RECEPTIONIST, VETERINARIAN]);
  // The professional completes the Profile after accepting; Clinics come later.
  expect(texts()).toContain(i18n.t('staffInvite.veterinarianNextSteps'));
  expect(sendDisabled()).toBe(false);
  await submit();
  expect(invite).toHaveBeenCalledTimes(1);
  expect(invite).toHaveBeenCalledWith({
    organizationId: 'A',
    recipientEmail: 'vet@example.test',
    role: 'VETERINARIAN',
    scope: 'ORGANIZATION',
    clinicId: null,
  });
});
it('switching from Veterinarian back to another role restores the scope choice at Organization', async () => {
  await render();
  await choose(VETERINARIAN);
  await choose(RECEPTIONIST);
  expect(radioLabels()).toEqual([
    ADMIN,
    RECEPTIONIST,
    VETERINARIAN,
    ORGANIZATION_SCOPE,
    CLINIC_SCOPE,
  ]);
  expect(radio(ORGANIZATION_SCOPE).props.accessibilityState.selected).toBe(true);
});
it('enables Send only when email and role are complete', async () => {
  await render();
  expect(sendDisabled()).toBe(true);
  await type('   ');
  await choose(ADMIN);
  expect(sendDisabled()).toBe(true);
  await type('laura@example.test');
  expect(sendDisabled()).toBe(false);
});
it('sends one Invitation and returns to Staff, whose focus re-read is authoritative', async () => {
  invite.mockResolvedValue({ kind: 'created', invitationId: 'new' } satisfies StaffInviteResult);
  await render();
  await type(' Laura@Example.Test ');
  await choose(ADMIN);
  await choose(CLINIC_SCOPE);
  await choose('Clinic a1');
  await submit();
  expect(invite).toHaveBeenCalledTimes(1);
  expect(invite).toHaveBeenCalledWith({
    organizationId: 'A',
    recipientEmail: ' Laura@Example.Test ',
    role: 'ADMINISTRATOR',
    scope: 'CLINIC',
    clinicId: 'a1',
  });
  expect(router.dismissTo).toHaveBeenCalledWith({
    pathname: '/professional/organizations/[organizationId]/staff',
    params: { organizationId: 'A' },
  });
});
it('presents a duplicate pending Invitation calmly and re-reads', async () => {
  invite.mockResolvedValue({ kind: 'rejected', reason: 'PENDING_INVITATION_EXISTS' });
  await render();
  await type('laura@example.test');
  await choose(RECEPTIONIST);
  const readsBefore = staffRead.mock.calls.length;
  await submit();
  expect(texts()).toContain(i18n.t('staffInvite.pendingExists'));
  expect(staffRead.mock.calls.length).toBeGreaterThan(readsBefore + 1);
  expect(router.dismissTo).not.toHaveBeenCalled();
});
it.each([
  ['ACTIVE_MEMBER', 'staffInvite.activeMember'],
  ['ACCOUNT_VERIFICATION_REQUIRED', 'staffInvite.verificationRequired'],
  ['INVALID_RECIPIENT', 'staffInvite.invalidRecipient'],
  ['INVALID_CLINIC', 'staffInvite.invalidClinic'],
] as const)('presents %s calmly without leaving', async (reason, messageKey) => {
  invite.mockResolvedValue({ kind: 'rejected', reason });
  await render();
  await type('laura@example.test');
  await choose(RECEPTIONIST);
  await submit();
  expect(texts()).toContain(i18n.t(messageKey));
  expect(router.dismissTo).not.toHaveBeenCalled();
});
it('reconciles a lost response as success only for a new exactly matching Invitation', async () => {
  staffRead
    .mockResolvedValueOnce(staff('A'))
    .mockResolvedValueOnce(staff('A', [invitation('old', 'other@example.test')]))
    .mockResolvedValueOnce(
      staff('A', [
        invitation('old', 'other@example.test'),
        invitation('new', 'laura@example.test'),
      ]),
    );
  invite.mockResolvedValue({ kind: 'uncertain' });
  await render();
  await type('Laura@Example.Test');
  await choose(ADMIN);
  await submit();
  expect(invite).toHaveBeenCalledTimes(1);
  expect(router.dismissTo).toHaveBeenCalledWith({
    pathname: '/professional/organizations/[organizationId]/staff',
    params: { organizationId: 'A' },
  });
});
it('never retries or claims success when the re-read cannot prove it', async () => {
  staffRead
    .mockResolvedValueOnce(staff('A'))
    .mockResolvedValueOnce(staff('A', [invitation('old', 'laura@example.test')]))
    .mockResolvedValueOnce(staff('A', [invitation('old', 'laura@example.test')]));
  invite.mockResolvedValue({ kind: 'uncertain' });
  await render();
  await type('laura@example.test');
  await choose(ADMIN);
  await submit();
  expect(texts()).toContain(i18n.t('staffInvite.pendingExists'));
  staffRead.mockResolvedValue(staff('A'));
  await submit();
  expect(texts()).toContain(i18n.t('staffInvite.unconfirmed'));
  expect(invite).toHaveBeenCalledTimes(2);
  expect(router.dismissTo).not.toHaveBeenCalled();
});
it('is unavailable without the advisory invite capability', async () => {
  contextRead.mockResolvedValue(context('A', ['ORGANIZATION_END_MEMBERSHIPS']));
  await render();
  expect(texts()).toContain(i18n.t('staffInvite.unavailable'));
  expect(tree.root.findAllByType(TextInput)).toHaveLength(0);
});
it('leaves calmly when the backend reports the Organization unavailable', async () => {
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => undefined);
  invite.mockResolvedValue({ kind: 'rejected', reason: 'ORGANIZATION_UNAVAILABLE' });
  await render();
  await type('laura@example.test');
  await choose(ADMIN);
  await submit();
  expect(router.dismissTo).toHaveBeenCalledWith('/professional');
  alert.mockRestore();
});
it('switching Organization starts a fresh draft with only that Organization Clinics', async () => {
  await render();
  await type('laura@example.test');
  await choose(CLINIC_SCOPE);
  await choose('Clinic a1');
  staffRead.mockResolvedValue(staff('B'));
  contextRead.mockResolvedValue(context('B', ['ORGANIZATION_INVITE_MEMBERS']));
  mockOrganizationId = 'B';
  await act(async () => {
    tree.update(createElement(StaffInviteRoute));
  });
  expect(tree.root.findByType(TextInput).props.value).toBe('');
  await choose(CLINIC_SCOPE);
  expect(radioLabels()).toContain('Clinic b1');
  expect(radioLabels()).not.toContain('Clinic a1');
  expect(texts().join(' ')).toContain('Organization B');
});

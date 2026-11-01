import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import OrganizationStaffRoute from '@/app/professional/organizations/[organizationId]/staff';
import {
  endOrganizationStaffMembership,
  getOrganizationStaff,
  getOrganizationStaffMembersPage,
  type StaffMember,
  type StaffMemberRow,
  type StaffPageResult,
} from '@/data/organization-staff';
import {
  getMyProfessionalContext,
  type ProfessionalCapability,
  type ProfessionalContext,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';

let mockOrganizationId = 'A';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ organizationId: mockOrganizationId }),
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => callback(), [callback]);
  },
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    replace: jest.fn(),
    push: jest.fn(),
  },
}));
jest.mock('@/components/design-system/app-top-bar', () => ({ AppTopBar: () => null }));
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
});
jest.mock('@/data/organization-staff', () => ({
  ...jest.requireActual('@/data/organization-staff'),
  getOrganizationStaff: jest.fn(),
  getOrganizationStaffMembersPage: jest.fn(),
  revokeOrganizationInvitation: jest.fn(),
  endOrganizationStaffMembership: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const fullRead = getOrganizationStaff as jest.Mock;
// The Members tab reads pages (SPEC-ORG-009 §12); the full read is never called here.
const read = getOrganizationStaffMembersPage as jest.Mock;
const endAccess = endOrganizationStaffMembership as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;

const member = (membershipId: string, overrides: Partial<StaffMember> = {}): StaffMember => ({
  membershipId,
  displayName: `Name ${membershipId}`,
  isSelf: false,
  invitationRecipientEmail: null,
  effectiveStart: '2020-01-01T00:00:00Z',
  responsibilities: [
    {
      responsibilityGrantId: 'g-66',
      responsibility: 'RECEPTIONIST',
      scope: { type: 'ORGANIZATION' },
    },
  ],
  ...overrides,
});
const SELF = member('self', {
  isSelf: true,
  responsibilities: [
    {
      responsibilityGrantId: 'g-71',
      responsibility: 'ADMINISTRATOR',
      scope: { type: 'ORGANIZATION' },
    },
  ],
});
const OWNER = member('owner', {
  responsibilities: [
    { responsibilityGrantId: 'g-74', responsibility: 'OWNER', scope: { type: 'ORGANIZATION' } },
  ],
});
const ADMIN = member('admin', {
  responsibilities: [
    {
      responsibilityGrantId: 'g-77',
      responsibility: 'ADMINISTRATOR',
      scope: { type: 'ORGANIZATION' },
    },
  ],
});
const INVITED = member('invited', {
  displayName: null,
  invitationRecipientEmail: 'invited@example.test',
});
const UNNAMED = member('unnamed', { displayName: null });
/** One Members page, with the backend's namesake flag (BR-14) computed over the fixture. */
const ok = (_organizationId: string, members: StaffMember[]): StaffPageResult<StaffMemberRow> => ({
  data: members.map((entry) => ({
    ...entry,
    displayNameIsShared:
      entry.displayName !== null &&
      members.some(
        (other) =>
          other.membershipId !== entry.membershipId && other.displayName === entry.displayName,
      ),
  })),
  error: null,
});
const ALL = [SELF, OWNER, ADMIN, INVITED, UNNAMED];
const capabilities = (
  organizationId: string,
  granted: ProfessionalCapability[],
): { data: ProfessionalContext; error: null } => ({
  data: {
    hasVeterinarianProfessionalProfile: false,
    organizations: [
      {
        membershipId: `m-${organizationId}`,
        organizationId,
        organizationDisplayName: `Organization ${organizationId}`,
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
const MANAGER: ProfessionalCapability[] = [
  'ORGANIZATION_INVITE_MEMBERS',
  'ORGANIZATION_REVOKE_INVITATIONS',
  'ORGANIZATION_END_MEMBERSHIPS',
  'ORGANIZATION_GRANT_RESPONSIBILITIES',
];

let tree: ReactTestRenderer;
const texts = () => tree.root.findAllByType(Text).map((node) => node.props.children);
const buttonLabels = () => [
  ...new Set(
    tree.root
      .findAll(
        (node) =>
          node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
      )
      .map((node) => String(node.props.accessibilityLabel)),
  ),
];
const manageLabel = (name: string) => i18n.t('staff.manageAccessibility', { name });
const cardLabels = () =>
  tree.root
    .findAll((node) => node.props.accessibilityRole === 'text' && node.props.accessible === true)
    .map((node) => node.props.accessibilityLabel as string)
    .filter((label, index, all) => all.indexOf(label) === index);
async function render() {
  await act(async () => {
    tree = create(createElement(OrganizationStaffRoute));
  });
}
beforeEach(() => {
  mockOrganizationId = 'A';
  jest.clearAllMocks();
  read.mockReset();
  fullRead.mockReset();
  endAccess.mockReset();
  contextRead.mockReset();
});
afterEach(() => {
  expect(fullRead).not.toHaveBeenCalled();
  act(() => tree.unmount());
});

describe('The Staff list is a summary; End access lives in the Member detail', () => {
  it('offers no End access on any row, whatever the capabilities', async () => {
    read.mockResolvedValue(ok('A', ALL));
    contextRead.mockResolvedValue(capabilities('A', MANAGER));
    await render();
    expect(
      buttonLabels().filter((label) => label.startsWith('Quitar a ') || /Retirar/.test(label)),
    ).toEqual([]);
    expect(texts()).not.toContain(i18n.t('staff.endAccessAction'));
    expect(endAccess).not.toHaveBeenCalled();
  });

  it('leads every member row to the Member detail with a chevron', async () => {
    read.mockResolvedValue(ok('A', ALL));
    contextRead.mockResolvedValue(capabilities('A', MANAGER));
    await render();
    expect(buttonLabels()).toEqual(
      expect.arrayContaining([
        manageLabel('Name self'),
        manageLabel('Name owner'),
        manageLabel('Name admin'),
        manageLabel('invited@example.test'),
        manageLabel(i18n.t('staff.unnamedMember')),
      ]),
    );
    const [chevron] = tree.root.findAll(
      (node) =>
        node.props.accessibilityLabel === manageLabel('Name admin') &&
        typeof node.props.onPress === 'function',
    );
    await act(async () => chevron.props.onPress());
    expect(router.push).toHaveBeenCalledWith({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]',
      params: { organizationId: 'A', membershipId: 'admin' },
    });
  });

  it('shows no Manage access without the Responsibility-management capability', async () => {
    read.mockResolvedValue(ok('A', ALL));
    contextRead.mockResolvedValue(
      capabilities('A', ['ORGANIZATION_INVITE_MEMBERS', 'ORGANIZATION_END_MEMBERSHIPS']),
    );
    await render();
    expect(buttonLabels().some((label) => label.startsWith('Gestionar'))).toBe(false);
    expect(texts()).toContain('Name admin');
  });
});

describe('Member identity on compact rows', () => {
  const SIMILAR_ONE = member('ana-1', {
    displayName: 'Ana',
    invitationRecipientEmail: 'ana.one@example.test',
  });
  const SIMILAR_TWO = member('ana-2', {
    displayName: 'Ana',
    invitationRecipientEmail: 'ana.two@example.test',
  });
  const LONG = member('long', {
    displayName: null,
    invitationRecipientEmail: `${'a'.repeat(60)}+staff@example-long-domain.test`,
  });

  it('every row is read as identity, then responsibilities — never the Membership start', async () => {
    read.mockResolvedValue(ok('A', [SELF, OWNER, SIMILAR_ONE, INVITED, UNNAMED]));
    contextRead.mockResolvedValue(capabilities('A', MANAGER));
    await render();
    const labels = cardLabels();
    expect(labels).toContain(
      `Ana. ${i18n.t('staff.invitedAddress', { email: 'ana.one@example.test' })}. Recepción · Todas las clínicas, incluidas las futuras`,
    );
    expect(labels).toContain(
      `invited@example.test. ${i18n.t('staff.invitationAddressContext')}. Recepción · Todas las clínicas, incluidas las futuras`,
    );
    expect(labels).toContain(
      `${i18n.t('staff.unnamedMember')}. Recepción · Todas las clínicas, incluidas las futuras`,
    );
    expect(labels).toContain(
      `Name self. ${i18n.t('staff.self')}. Administración · Todas las clínicas, incluidas las futuras`,
    );
    expect(labels.some((label) => /Miembro desde/.test(label))).toBe(false);
    // Visually: compact badges, and the invitation address only where it is the heading.
    expect(texts()).toEqual(
      expect.arrayContaining(['Recepción · todas las clínicas', 'Propietario/a', 'Tú']),
    );
    expect(texts()).not.toContain(
      i18n.t('staff.invitedAddress', { email: 'ana.one@example.test' }),
    );
    expect(texts()).toContain(i18n.t('staff.invitationAddressContext'));
  });

  it('two members with the same name show their invitation addresses and distinct Manage labels', async () => {
    read.mockResolvedValue(ok('A', [SELF, SIMILAR_ONE, SIMILAR_TWO]));
    contextRead.mockResolvedValue(capabilities('A', MANAGER));
    await render();
    expect(texts()).toEqual(
      expect.arrayContaining([
        i18n.t('staff.invitedAddress', { email: 'ana.one@example.test' }),
        i18n.t('staff.invitedAddress', { email: 'ana.two@example.test' }),
      ]),
    );
    expect(buttonLabels()).toEqual(
      expect.arrayContaining([
        manageLabel('Ana (ana.one@example.test)'),
        manageLabel('Ana (ana.two@example.test)'),
      ]),
    );
    const anaRows = cardLabels().filter((label) => label.startsWith('Ana.'));
    expect(anaRows).toHaveLength(2);
    expect(anaRows[0]).not.toBe(anaRows[1]);
  });

  it('a long Invitation address is the whole heading and stays a wrapping text element', async () => {
    read.mockResolvedValue(ok('A', [SELF, LONG]));
    contextRead.mockResolvedValue(capabilities('A', MANAGER));
    await render();
    const heading = tree.root.findAll(
      (node) => node.type === Text && node.props.children === LONG.invitationRecipientEmail,
    );
    expect(heading.length).toBeGreaterThan(0);
    expect(heading[0].props.numberOfLines).toBeUndefined();
  });
});

describe('Organization isolation', () => {
  it('reads and shows only the route Organization', async () => {
    read.mockResolvedValue(ok('A', ALL));
    contextRead.mockResolvedValue(capabilities('A', MANAGER));
    await render();
    expect(read.mock.calls.every(([organizationId]) => organizationId === 'A')).toBe(true);
    expect(texts()).toContain('Organization A');
    expect(texts()).not.toContain('Organization B');
  });
});

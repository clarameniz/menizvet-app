import { createElement } from 'react';
import { Alert, FlatList, Text, type AlertButton } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import OrganizationStaffRoute from '@/app/professional/organizations/[organizationId]/staff';
import {
  getOrganizationPendingInvitationsPage,
  getOrganizationStaff,
  getOrganizationStaffMembersPage,
  recheckPendingInvitation,
  revokeOrganizationInvitation,
  type InvitationRevocationResult,
  type PendingStaffInvitation,
  type StaffPageResult,
} from '@/data/organization-staff';
import {
  getMyProfessionalContext,
  type ProfessionalCapability,
  type ProfessionalContext,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import { staffInstantLabel, staffShortDateLabel } from '@/lib/organization-staff';

/**
 * The Staff screen's Invitations tab (SPEC-ORG-009 §7, §12; SPEC-ORG-010 §5):
 * Invite, its keyset pages and Revoke. The full `get_organization_staff` read
 * is never called by this screen.
 */

type FocusCallback = () => void | (() => void);
const mockFocus = { callbacks: new Set<FocusCallback>() };
let mockOrganizationId = 'A';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ organizationId: mockOrganizationId }),
  useFocusEffect: (callback: FocusCallback) => {
    const React = jest.requireActual('react');
    React.useEffect(() => {
      mockFocus.callbacks.add(callback);
      const cleanup = callback();
      return () => {
        if (typeof cleanup === 'function') cleanup();
        mockFocus.callbacks.delete(callback);
      };
    }, [callback]);
  },
  router: {
    dismissTo: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    replace: jest.fn(),
    push: jest.fn(),
  },
}));
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
  getOrganizationStaffMembersPage: jest.fn(),
  getOrganizationPendingInvitationsPage: jest.fn(),
  recheckPendingInvitation: jest.fn(),
  revokeOrganizationInvitation: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const fullRead = getOrganizationStaff as jest.Mock;
const membersRead = getOrganizationStaffMembersPage as jest.Mock;
const invitationsRead = getOrganizationPendingInvitationsPage as jest.Mock;
const recheck = recheckPendingInvitation as jest.Mock;
const revoke = revokeOrganizationInvitation as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;

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
];

function invitation(
  id: string,
  overrides: Partial<PendingStaffInvitation> = {},
): PendingStaffInvitation {
  return {
    invitationId: id,
    recipientEmail: `${id}@example.test`,
    responsibilities: [{ responsibility: 'RECEPTIONIST', scope: { type: 'ORGANIZATION' } }],
    createdAt: '2030-01-01T00:00:00Z',
    expiresAt: '2030-01-08T00:00:00Z',
    ...overrides,
  };
}
const page = (rows: PendingStaffInvitation[]): StaffPageResult<PendingStaffInvitation> => ({
  data: rows,
  error: null,
});
const invitations = (count: number, prefix = 'p') =>
  Array.from({ length: count }, (_, index) =>
    invitation(
      `${prefix}${String(index + 1).padStart(2, '0')}`,
      index === count - 1 ? { createdAt: '2030-01-02T03:04:05.654321+00:00' } : {},
    ),
  );

let tree: ReactTestRenderer;
let alert: jest.SpyInstance;
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const shown = () => texts().join(' | ');
const buttons = () =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
  );
const labelled = (label: string) =>
  buttons().find((node) => node.props.accessibilityLabel === label) as ReactTestInstance;
const actionLabels = () =>
  [
    ...new Set(
      buttons()
        .map((node) => node.props.accessibilityLabel as string | undefined)
        .filter(
          (label): label is string => label !== undefined && label !== i18n.t('pagedList.loadMore'),
        ),
    ),
  ].sort();
const revokeLabel = (email: string) => i18n.t('staff.revokeAccessibility', { email });
const listData = () => tree.root.findByType(FlatList).props.data as PendingStaffInvitation[];
async function press(node: ReactTestInstance) {
  await act(async () => {
    node.props.onPress();
  });
}
async function render() {
  await act(async () => {
    tree = create(createElement(OrganizationStaffRoute));
  });
}
async function openInvitations() {
  await press(
    tree.root.find(
      (node) =>
        node.props.testID === 'staff-tab-invitations' && typeof node.props.onPress === 'function',
    ),
  );
}
async function refocus() {
  await act(async () => {
    for (const callback of mockFocus.callbacks) callback();
  });
}
async function confirmRevoke() {
  const [, , choices] = alert.mock.calls.at(-1) as [string, string, AlertButton[]];
  await act(async () => {
    choices.find((choice) => choice.style === 'destructive')?.onPress?.();
  });
}

beforeEach(() => {
  mockOrganizationId = 'A';
  jest.clearAllMocks();
  for (const mock of [fullRead, membersRead, invitationsRead, recheck, revoke, contextRead]) {
    mock.mockReset();
  }
  membersRead.mockResolvedValue({ data: [], error: null });
  contextRead.mockResolvedValue(capabilities('A', MANAGER));
  alert = jest.spyOn(Alert, 'alert').mockImplementation(() => undefined);
});
afterEach(() => {
  expect(fullRead).not.toHaveBeenCalled();
  act(() => tree.unmount());
  alert.mockRestore();
});

describe('Invitations tab', () => {
  it('shows each pending Invitation compactly, with its full details announced', async () => {
    invitationsRead.mockResolvedValue(
      page([
        invitation('p1', {
          responsibilities: [
            {
              responsibility: 'RECEPTIONIST',
              scope: { type: 'CLINIC', clinic: { clinicId: 'c1', displayName: 'Monte Jara' } },
            },
          ],
          expiresAt: '2030-10-28T10:00:00Z',
        }),
      ]),
    );
    await render();
    await openInvitations();
    const all = texts();
    expect(all).toEqual(
      expect.arrayContaining([
        i18n.t('staff.invitationsHeading'),
        'p1@example.test',
        i18n.t('staff.pending'),
        i18n.t('staff.taskLine', {
          role: i18n.t('staffRoles.receptionist'),
          coverage: i18n.t('staff.clinicsOne'),
        }),
        `Monte Jara · ${i18n.t('staff.expiresAt', { date: staffShortDateLabel('2030-10-28T10:00:00Z', 'es') })}`,
      ]),
    );
    expect(
      staffShortDateLabel('2030-10-28T10:00:00Z', 'es', new Date('2030-01-01T00:00:00Z')),
    ).toBe('28 oct');
    const label = tree.root.find(
      (node) =>
        typeof node.type === 'string' &&
        node.props.accessibilityRole === 'text' &&
        String(node.props.accessibilityLabel).startsWith('p1@example.test'),
    ).props.accessibilityLabel as string;
    expect(label).toContain('Monte Jara');
    expect(label).toContain(staffInstantLabel('2030-10-28T10:00:00Z', 'es'));
  });

  it('offers Invite (even with no Invitation) and Revoke only with the advisory capabilities', async () => {
    invitationsRead.mockResolvedValue(page([]));
    await render();
    await openInvitations();
    expect(shown()).toContain(i18n.t('staff.noInvitations'));
    await press(labelled(i18n.t('staff.inviteAction')));
    expect(router.push).toHaveBeenCalledWith({
      pathname: '/professional/organizations/[organizationId]/staff/invite',
      params: { organizationId: 'A' },
    });
    act(() => tree.unmount());

    invitationsRead.mockResolvedValue(page([invitation('p1'), invitation('p2')]));
    await render();
    await openInvitations();
    expect(actionLabels()).toEqual(
      [
        i18n.t('staff.inviteAction'),
        revokeLabel('p1@example.test'),
        revokeLabel('p2@example.test'),
      ].sort(),
    );
  });

  it('offers neither without the capability, for another Organization, or without context', async () => {
    for (const context of [
      capabilities('A', ['ORGANIZATION_END_MEMBERSHIPS']),
      capabilities('B', MANAGER),
      { data: null, error: 'offline' },
    ]) {
      invitationsRead.mockResolvedValue(page([invitation('p1')]));
      contextRead.mockResolvedValue(context);
      await render();
      await openInvitations();
      expect(texts()).toContain('p1@example.test');
      expect(actionLabels()).toEqual([]);
      act(() => tree.unmount());
    }
    await render();
  });

  it('pages 21 Invitations: 20, then the last from the exact key, without repeats', async () => {
    const first = invitations(20);
    invitationsRead.mockResolvedValueOnce(page(first));
    await render();
    await openInvitations();
    expect(listData()).toHaveLength(20);
    invitationsRead.mockResolvedValueOnce(page([first[19], invitation('p21')]));
    await press(labelled(i18n.t('pagedList.loadMore')));
    expect(invitationsRead.mock.calls[1]).toEqual([
      'A',
      { createdAt: '2030-01-02T03:04:05.654321+00:00', invitationId: 'p20' },
      20,
    ]);
    const ids = listData().map((row) => row.invitationId);
    expect(ids).toHaveLength(21);
    expect(new Set(ids).size).toBe(21);
    expect(labelled(i18n.t('pagedList.loadMore'))).toBeUndefined();
  });

  it('ends on an empty page after exactly 20, and reads one page at a time', async () => {
    invitationsRead.mockResolvedValueOnce(page(invitations(20)));
    await render();
    await openInvitations();
    let settle!: (value: StaffPageResult<PendingStaffInvitation>) => void;
    invitationsRead.mockReturnValueOnce(
      new Promise((resolve) => {
        settle = resolve;
      }),
    );
    const button = labelled(i18n.t('pagedList.loadMore'));
    await act(async () => {
      button.props.onPress();
      button.props.onPress();
    });
    expect(invitationsRead).toHaveBeenCalledTimes(2);
    await act(async () => settle(page([])));
    expect(listData()).toHaveLength(20);
    expect(labelled(i18n.t('pagedList.loadMore'))).toBeUndefined();
  });

  it('back from Invite (or any focus) re-reads only the Invitations from their first page', async () => {
    invitationsRead.mockResolvedValueOnce(page([invitation('p1')]));
    await render();
    await openInvitations();
    invitationsRead.mockResolvedValueOnce(page([]));
    await refocus();
    expect(invitationsRead).toHaveBeenLastCalledWith('A', null, 20);
    expect(membersRead).toHaveBeenCalledTimes(1);
    expect(texts()).not.toContain('p1@example.test');
    expect(texts()).toContain(i18n.t('staff.noInvitations'));
  });
});

describe('revocation (SPEC-ORG-010 §5)', () => {
  it('revokes only after explicit confirmation, then re-reads the Invitations', async () => {
    invitationsRead.mockResolvedValueOnce(page([invitation('p1')])).mockResolvedValueOnce(page([]));
    revoke.mockResolvedValue({ kind: 'outcome', outcome: 'REVOKED' });
    await render();
    await openInvitations();
    await press(labelled(revokeLabel('p1@example.test')));
    expect(revoke).not.toHaveBeenCalled();
    const [title, message, choices] = alert.mock.calls.at(-1) as [string, string, AlertButton[]];
    expect(title).toBe(i18n.t('staff.revokeConfirmTitle'));
    expect(message).toContain('p1@example.test');
    expect(choices.find((choice) => choice.style === 'cancel')?.onPress).toBeUndefined();
    await confirmRevoke();
    expect(revoke).toHaveBeenCalledWith('p1');
    expect(recheck).not.toHaveBeenCalled();
    expect(invitationsRead).toHaveBeenLastCalledWith('A', null, 20);
    expect(texts()).not.toContain('p1@example.test');
    expect(texts()).toContain(i18n.t('staff.revoked'));
    expect(membersRead).toHaveBeenCalledTimes(1);
  });

  it.each([
    [{ kind: 'outcome', outcome: 'ALREADY_REVOKED' }, null, 'staff.revoked'],
    [{ kind: 'outcome', outcome: 'ACCEPTED' }, null, 'staff.revokeAccepted'],
    [{ kind: 'outcome', outcome: 'EXPIRED' }, null, 'staff.revokeExpired'],
    [{ kind: 'outcome', outcome: 'REJECTED' }, null, 'staff.revokeRejected'],
    [{ kind: 'authenticationRequired' }, null, 'errors.sessionExpired'],
    [{ kind: 'uncertain' }, 'notPending', 'staff.revokeNoLongerPending'],
    [{ kind: 'uncertain' }, 'pending', 'staff.revokeFailed'],
    [{ kind: 'uncertain' }, 'error', 'staff.revokeFailed'],
  ] as [InvitationRevocationResult, string | null, string][])(
    'presents %j with the authoritative re-check',
    async (result, recheckOutcome, messageKey) => {
      invitationsRead.mockResolvedValue(page([invitation('p1'), invitation('p2')]));
      revoke.mockResolvedValue(result);
      if (recheckOutcome !== null) recheck.mockResolvedValue(recheckOutcome);
      await render();
      await openInvitations();
      await press(labelled(revokeLabel('p2@example.test')));
      await confirmRevoke();
      expect(revoke).toHaveBeenCalledTimes(1);
      expect(texts()).toContain(i18n.t(messageKey));
      if (result.kind === 'uncertain') {
        // One row right after the Invitation listed before it — never the full list.
        expect(recheck).toHaveBeenCalledWith('A', invitation('p2'), invitation('p1'));
        expect(texts()).not.toContain(i18n.t('staff.revoked'));
      } else {
        expect(recheck).not.toHaveBeenCalled();
      }
    },
  );

  describe('lost response, with the real one-row re-check', () => {
    const rpc = () => jest.requireMock('@/lib/supabase').supabase.rpc as jest.Mock;
    const wire = (id: string, createdAt: string) => ({
      invitation_id: id,
      recipient_email: `${id.slice(-3)}@example.test`,
      responsibilities: [
        { responsibility: 'RECEPTIONIST', scope_type: 'ORGANIZATION', clinic: null },
      ],
      created_at: createdAt,
      expires_at: '2030-01-08T00:00:00Z',
    });
    const FIRST = 'd0090000-0000-4000-8000-000000000805';
    const EARLIER = 'd0090000-0000-4000-8000-000000000802';
    const LATER = 'd0090000-0000-4000-8000-000000000809';
    // The real data read refuses a non-UUID Organization before calling the RPC.
    const ORG = 'd0090000-0000-4000-8000-000000000301';
    beforeEach(() => {
      mockOrganizationId = ORG;
      contextRead.mockResolvedValue(capabilities(ORG, MANAGER));
      recheck.mockImplementation(
        jest.requireActual('@/data/organization-staff').recheckPendingInvitation,
      );
      rpc().mockReset();
      revoke.mockResolvedValue({ kind: 'uncertain' });
    });

    it('a concurrent Invitation committed ahead of the first one never reads as its revocation', async () => {
      invitationsRead.mockResolvedValue(
        page([invitation(FIRST, { createdAt: '2030-01-01T10:00:00.123+00:00' })]),
      );
      rpc().mockResolvedValueOnce({
        data: [wire(EARLIER, '2030-01-01T09:59:59.999+00:00')],
        error: null,
      });
      await render();
      await openInvitations();
      await press(labelled(revokeLabel(`${FIRST}@example.test`)));
      await confirmRevoke();
      expect(rpc()).toHaveBeenCalledWith('get_organization_pending_invitations', {
        p_organization_id: ORG,
        p_after_created_at: null,
        p_after_invitation_id: null,
        p_limit: 1,
      });
      expect(texts()).toContain(i18n.t('staff.revokeFailed'));
      expect(texts()).not.toContain(i18n.t('staff.revokeNoLongerPending'));
      expect(texts()).not.toContain(i18n.t('staff.revoked'));
      // The list is still re-read authoritatively, and the retry stays available.
      expect(invitationsRead).toHaveBeenLastCalledWith(ORG, null, 20);
      expect(labelled(revokeLabel(`${FIRST}@example.test`))).toBeDefined();
    });

    it('only a later key, or none, after the previous one proves it is no longer pending', async () => {
      invitationsRead.mockResolvedValue(
        page([invitation(FIRST, { createdAt: '2030-01-01T10:00:00.123+00:00' })]),
      );
      rpc().mockResolvedValueOnce({
        data: [wire(LATER, '2030-01-01T11:00:00+00:00')],
        error: null,
      });
      await render();
      await openInvitations();
      await press(labelled(revokeLabel(`${FIRST}@example.test`)));
      await confirmRevoke();
      expect(texts()).toContain(i18n.t('staff.revokeNoLongerPending'));
    });
  });

  it('re-checks the first Invitation from the start of the list', async () => {
    invitationsRead.mockResolvedValue(page([invitation('p1')]));
    revoke.mockResolvedValue({ kind: 'uncertain' });
    recheck.mockResolvedValue('notPending');
    await render();
    await openInvitations();
    await press(labelled(revokeLabel('p1@example.test')));
    await confirmRevoke();
    expect(recheck).toHaveBeenCalledWith('A', invitation('p1'), null);
  });

  it('treats a denied revocation or re-check as lost Staff access and leaves calmly', async () => {
    for (const [result, recheckOutcome] of [
      [{ kind: 'accessDenied' }, null],
      [{ kind: 'uncertain' }, 'unavailable'],
    ] as const) {
      invitationsRead.mockResolvedValue(page([invitation('p1')]));
      revoke.mockResolvedValue(result);
      if (recheckOutcome !== null) recheck.mockResolvedValue(recheckOutcome);
      await render();
      await openInvitations();
      await press(labelled(revokeLabel('p1@example.test')));
      await confirmRevoke();
      expect(router.dismissTo).toHaveBeenLastCalledWith('/professional');
      act(() => tree.unmount());
    }
    await render();
  });

  it('keeps Organizations isolated: B shows and revokes only B Invitations', async () => {
    invitationsRead.mockImplementation(async (organizationId: string) =>
      page([invitation(organizationId === 'A' ? 'a1' : 'b1')]),
    );
    contextRead.mockResolvedValue({
      data: {
        hasVeterinarianProfessionalProfile: false,
        organizations: [
          capabilities('A', MANAGER).data.organizations[0],
          capabilities('B', MANAGER).data.organizations[0],
        ],
      },
      error: null,
    });
    revoke.mockResolvedValue({ kind: 'outcome', outcome: 'REVOKED' });
    await render();
    await openInvitations();
    mockOrganizationId = 'B';
    await act(async () => {
      tree.update(createElement(OrganizationStaffRoute));
    });
    await openInvitations();
    expect(texts()).not.toContain('a1@example.test');
    expect(actionLabels()).toEqual(
      [i18n.t('staff.inviteAction'), revokeLabel('b1@example.test')].sort(),
    );
    await press(labelled(revokeLabel('b1@example.test')));
    await confirmRevoke();
    expect(revoke).toHaveBeenCalledWith('b1');
    expect(invitationsRead).toHaveBeenLastCalledWith('B', null, 20);
  });
});

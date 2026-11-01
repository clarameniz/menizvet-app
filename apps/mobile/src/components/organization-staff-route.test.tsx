import { createElement } from 'react';
import { Alert, FlatList, Text } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import OrganizationStaffRoute from '@/app/professional/organizations/[organizationId]/staff';
import {
  getOrganizationPendingInvitationsPage,
  getOrganizationStaff,
  getOrganizationStaffMembersPage,
  STAFF_ACCESS_DENIED,
  type StaffMemberRow,
  type StaffPageResult,
} from '@/data/organization-staff';
import {
  getMyProfessionalContext,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ProfessionalCapability,
  type ProfessionalContext,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import {
  getProfessionalOrganizationSelection,
  setProfessionalOrganizationSelection,
} from '@/lib/professional-organization-selection';

/**
 * The Staff screen (SPEC-ORG-009 §7, §12): header and tabs, the Members tab
 * and its keyset pages. Invitations and revocation are covered by
 * staff-revoke-route.test.tsx. The full `get_organization_staff` read is never
 * called by this screen.
 */

type FocusCallback = () => void | (() => void);
const mockFocus = { callbacks: new Set<FocusCallback>() };
let mockOrganizationId = 'A';
const mockLocale = { value: 'es' as 'es' | 'en' };
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
  return {
    useLocale: () => ({
      locale: mockLocale.value,
      t: (key: string, options?: Record<string, unknown>) =>
        mockI18n.t(key, { ...options, locale: mockLocale.value }),
    }),
  };
});
jest.mock('@/data/organization-staff', () => ({
  ...jest.requireActual('@/data/organization-staff'),
  getOrganizationStaff: jest.fn(),
  getOrganizationStaffMembersPage: jest.fn(),
  getOrganizationPendingInvitationsPage: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const fullRead = getOrganizationStaff as jest.Mock;
const membersRead = getOrganizationStaffMembersPage as jest.Mock;
const invitationsRead = getOrganizationPendingInvitationsPage as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;
const t = (key: string, options?: Record<string, unknown>) =>
  i18n.t(key, { ...options, locale: mockLocale.value });

const MANAGER: ProfessionalCapability[] = [
  'ORGANIZATION_INVITE_MEMBERS',
  'ORGANIZATION_REVOKE_INVITATIONS',
  'ORGANIZATION_END_MEMBERSHIPS',
  'ORGANIZATION_GRANT_RESPONSIBILITIES',
];
function context(
  organizationId: string,
  granted: ProfessionalCapability[] = MANAGER,
): { data: ProfessionalContext; error: null } {
  return {
    data: {
      hasVeterinarianProfessionalProfile: false,
      organizations: [
        {
          membershipId: `self-${organizationId}`,
          organizationId,
          organizationDisplayName: `MenizVet Org ${organizationId}`,
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
  };
}

const CLINIC = (id: string, name: string) => ({
  type: 'CLINIC' as const,
  clinic: { clinicId: id, displayName: name },
});
function member(n: number, overrides: Partial<StaffMemberRow> = {}): StaffMemberRow {
  return {
    membershipId: `m-${String(n).padStart(3, '0')}`,
    effectiveStart: '2020-01-01T00:00:00Z',
    isSelf: false,
    displayName: `Member ${n}`,
    invitationRecipientEmail: null,
    displayNameIsShared: false,
    responsibilities: [
      {
        responsibilityGrantId: `g-${n}`,
        responsibility: 'RECEPTIONIST',
        scope: { type: 'ORGANIZATION' },
      },
    ],
    ...overrides,
  };
}
const page = <T,>(rows: T[]): StaffPageResult<T> => ({ data: rows, error: null });
/** `count` members, the last one keyed with a microsecond timestamp. */
const members = (count: number, from = 1) =>
  Array.from({ length: count }, (_, index) =>
    member(
      from + index,
      index === count - 1 ? { effectiveStart: '2021-03-04T05:06:07.123456+00:00' } : {},
    ),
  );

let tree: ReactTestRenderer;
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const shown = () => texts().join(' | ');
const buttons = () =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
  );
const labelled = (label: string) =>
  buttons().find((node) => node.props.accessibilityLabel === label) as ReactTestInstance;
const tab = (name: 'members' | 'invitations') =>
  tree.root.find(
    (node) => node.props.testID === `staff-tab-${name}` && typeof node.props.onPress === 'function',
  );
const listData = () => tree.root.findByType(FlatList).props.data as StaffMemberRow[];
const rowLabels = () =>
  tree.root
    .findAll(
      (node) =>
        typeof node.type === 'string' &&
        node.props.accessibilityRole === 'text' &&
        typeof node.props.accessibilityLabel === 'string',
    )
    .map((node) => node.props.accessibilityLabel as string);
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
async function refocus() {
  await act(async () => {
    for (const callback of mockFocus.callbacks) callback();
  });
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

beforeEach(() => {
  jest.clearAllMocks();
  for (const mock of [fullRead, membersRead, invitationsRead, contextRead]) mock.mockReset();
  mockOrganizationId = 'A';
  mockLocale.value = 'es';
  contextRead.mockResolvedValue(context('A'));
  membersRead.mockResolvedValue(page([member(1, { isSelf: true })]));
  invitationsRead.mockResolvedValue(page([]));
  setProfessionalOrganizationSelection({ membershipId: 'self-B', organizationId: 'B' });
});
afterEach(() => {
  expect(fullRead).not.toHaveBeenCalled();
  act(() => tree.unmount());
  setProfessionalOrganizationSelection(null);
});

describe('header and tabs', () => {
  it('shows Personal with the Organization, opens on Members and reads only its first page', async () => {
    await render();
    expect(shown()).toContain(t('staff.title'));
    expect(shown()).toContain('MenizVet Org A');
    expect(tab('members').props.accessibilityRole).toBe('tab');
    expect(tab('members').props.accessibilityState).toEqual({ selected: true });
    expect(tab('invitations').props.accessibilityState).toEqual({ selected: false });
    expect(membersRead.mock.calls).toEqual([['A', null, 25]]);
    expect(invitationsRead).not.toHaveBeenCalled();
    expect(shown()).not.toContain(t('staff.invitationsHeading'));
    // The landing's selection returns to the route Organization (presentation only).
    expect(getProfessionalOrganizationSelection()).toEqual({
      membershipId: 'self-A',
      organizationId: 'A',
    });
  });

  it('reads Invitations once, when first shown, and switching never re-reads a tab', async () => {
    await render();
    await press(tab('invitations'));
    expect(invitationsRead.mock.calls).toEqual([['A', null, 20]]);
    expect(shown()).not.toContain('Member 1');
    await press(tab('members'));
    await press(tab('invitations'));
    await press(tab('members'));
    expect(membersRead).toHaveBeenCalledTimes(1);
    expect(invitationsRead).toHaveBeenCalledTimes(1);
    expect(shown()).toContain('Member 1');
  });

  it('back from a detail refreshes only the tab shown; the other when shown again', async () => {
    await render();
    await refocus();
    expect(membersRead.mock.calls).toEqual([
      ['A', null, 25],
      ['A', null, 25],
    ]);
    expect(invitationsRead).not.toHaveBeenCalled();
    await press(tab('invitations'));
    await refocus();
    expect(invitationsRead).toHaveBeenCalledTimes(2);
    expect(membersRead).toHaveBeenCalledTimes(2);
    await press(tab('members'));
    expect(membersRead).toHaveBeenCalledTimes(3);
    expect(membersRead).toHaveBeenLastCalledWith('A', null, 25);
  });

  it('localizes the header and tabs in English', async () => {
    mockLocale.value = 'en';
    await render();
    expect(tab('members').props.accessibilityLabel).toBe('Members');
    expect(tab('invitations').props.accessibilityLabel).toBe('Invitations');
    expect(shown()).toContain('Staff');
  });
});

describe('member rows', () => {
  it('shows the name, "You" and compact responsibility badges, never dates or Clinic lists', async () => {
    membersRead.mockResolvedValue(
      page([
        member(1, {
          displayName: 'Ana García',
          isSelf: true,
          responsibilities: [
            {
              responsibilityGrantId: 'g1',
              responsibility: 'VETERINARIAN',
              scope: { type: 'ORGANIZATION' },
            },
            {
              responsibilityGrantId: 'g2',
              responsibility: 'RECEPTIONIST',
              scope: CLINIC('c1', 'Monte Jara'),
            },
            {
              responsibilityGrantId: 'g3',
              responsibility: 'RECEPTIONIST',
              scope: CLINIC('c2', 'Centro'),
            },
          ],
        }),
        member(2, {
          displayName: 'Luis Pérez',
          responsibilities: [
            {
              responsibilityGrantId: 'g4',
              responsibility: 'ADMINISTRATOR',
              scope: { type: 'ORGANIZATION' },
            },
          ],
        }),
      ]),
    );
    await render();
    const all = texts();
    expect(all).toEqual(
      expect.arrayContaining([
        'Ana García',
        t('staff.self'),
        t('staffRoles.veterinarian'),
        t('staff.taskLine', {
          role: t('staffRoles.receptionist'),
          coverage: t('staff.clinicsOther', { count: 2 }),
        }),
        'Luis Pérez',
        t('staff.taskLine', {
          role: t('staffRoles.administrator'),
          coverage: t('staff.coverageAll'),
        }),
      ]),
    );
    expect(all).not.toContain('Monte Jara');
    expect(shown()).not.toMatch(/2020/);
    // The accessible text names every current Grant with its Clinic.
    expect(rowLabels()[0]).toContain('Monte Jara');
    expect(rowLabels()[0]).toContain('Centro');
    expect(rowLabels()[0]).toContain(t('staff.self'));
    // No destructive or management button on the list.
    expect(
      buttons().some((node) =>
        String(node.props.accessibilityLabel).includes(t('staff.endAccessAction')),
      ),
    ).toBe(false);
  });

  it('tells namesakes apart with the server flag, even when the other one is on another page', async () => {
    membersRead.mockResolvedValue(
      page([
        member(1, {
          displayName: 'Ana',
          invitationRecipientEmail: 'ana.one@example.test',
          displayNameIsShared: true,
        }),
        member(2, {
          displayName: 'Luis',
          invitationRecipientEmail: 'luis@example.test',
          displayNameIsShared: false,
        }),
        member(3, { displayName: null, invitationRecipientEmail: 'unnamed@example.test' }),
        member(4, { displayName: null, invitationRecipientEmail: null }),
      ]),
    );
    await render();
    const all = texts();
    expect(all).toContain(t('staff.invitedAddress', { email: 'ana.one@example.test' }));
    expect(all).not.toContain(t('staff.invitedAddress', { email: 'luis@example.test' }));
    expect(all).toContain('unnamed@example.test');
    expect(all).toContain(t('staff.invitationAddressContext'));
    expect(all).toContain(t('staff.unnamedMember'));
  });

  it('the whole row opens the Member detail with the advisory capability, and only then', async () => {
    await render();
    const chevron = labelled(t('staff.manageAccessibility', { name: 'Member 1' }));
    await press(chevron);
    expect(router.push).toHaveBeenCalledWith({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]',
      params: { organizationId: 'A', membershipId: 'm-001' },
    });
    act(() => tree.unmount());
    contextRead.mockResolvedValue(context('A', ['ORGANIZATION_INVITE_MEMBERS']));
    await render();
    expect(
      buttons().filter(
        (node) =>
          node.props.testID !== 'back' && !String(node.props.testID).startsWith('staff-tab'),
      ),
    ).toHaveLength(0);
  });

  it('says so when the Organization has no member to show', async () => {
    membersRead.mockResolvedValue(page([]));
    await render();
    expect(shown()).toContain(t('staff.noMembers'));
    expect(shown()).toContain('Todavía no hay miembros que mostrar.');
  });
});

describe('Members pagination', () => {
  it('pages 26 members: 25, then the last from the exact key, without repeats', async () => {
    const first = members(25);
    membersRead.mockResolvedValueOnce(page(first));
    await render();
    expect(listData()).toHaveLength(25);
    membersRead.mockResolvedValueOnce(page([first[24], member(26)]));
    await press(labelled(t('pagedList.loadMore')));
    expect(membersRead.mock.calls[1]).toEqual([
      'A',
      { effectiveStart: '2021-03-04T05:06:07.123456+00:00', membershipId: 'm-025' },
      25,
    ]);
    const ids = listData().map((row) => row.membershipId);
    expect(ids).toHaveLength(26);
    expect(new Set(ids).size).toBe(26);
    expect(labelled(t('pagedList.loadMore'))).toBeUndefined();
  });

  it('shows no "Load more" under 25, and ends on an empty page after exactly 25', async () => {
    membersRead.mockResolvedValueOnce(page(members(24)));
    await render();
    expect(labelled(t('pagedList.loadMore'))).toBeUndefined();
    act(() => tree.unmount());
    membersRead.mockResolvedValueOnce(page(members(25))).mockResolvedValueOnce(page([]));
    await render();
    await press(labelled(t('pagedList.loadMore')));
    expect(listData()).toHaveLength(25);
    expect(labelled(t('pagedList.loadMore'))).toBeUndefined();
    expect(shown()).not.toContain(t('staff.noMembers'));
  });

  it('reads one page at a time, and a refresh ignores a page answered late', async () => {
    membersRead.mockResolvedValueOnce(page(members(25)));
    await render();
    const late = deferred<StaffPageResult<StaffMemberRow>>();
    membersRead.mockReturnValueOnce(late.promise);
    const button = labelled(t('pagedList.loadMore'));
    await act(async () => {
      button.props.onPress();
      button.props.onPress();
    });
    expect(membersRead).toHaveBeenCalledTimes(2);
    membersRead.mockResolvedValueOnce(page([member(90, { displayName: 'Fresh' })]));
    await refocus();
    expect(membersRead).toHaveBeenLastCalledWith('A', null, 25);
    await act(async () => late.resolve(page([member(91, { displayName: 'Stale' })])));
    expect(shown()).toContain('Fresh');
    expect(shown()).not.toContain('Stale');
  });

  it('a failed page keeps the rows and retries from the same cursor', async () => {
    membersRead.mockResolvedValueOnce(page(members(25)));
    await render();
    membersRead.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
    await press(labelled(t('pagedList.loadMore')));
    expect(shown()).toContain(t('pagedList.loadMoreError'));
    expect(listData()).toHaveLength(25);
    membersRead.mockResolvedValueOnce(page([member(26)]));
    await press(labelled(t('professional.retry')));
    expect(membersRead.mock.calls[2]).toEqual(membersRead.mock.calls[1]);
    expect(listData()).toHaveLength(26);
  });
});

describe('errors and access', () => {
  it('a first-page failure offers a retry; an expired session says so', async () => {
    membersRead.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
    await render();
    expect(shown()).toContain(t('staff.loadError'));
    await press(labelled(t('professional.retry')));
    expect(shown()).toContain('Member 1');
    act(() => tree.unmount());
    membersRead.mockResolvedValueOnce({ data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED });
    await render();
    expect(shown()).toContain(t('errors.sessionExpired'));
  });

  it('a denial on the first read says Staff is unavailable, without tabs or leaving', async () => {
    membersRead.mockResolvedValueOnce({ data: null, error: STAFF_ACCESS_DENIED });
    await render();
    expect(shown()).toContain(t('staff.unavailable'));
    expect(tree.root.findAll((node) => node.props.accessibilityRole === 'tab')).toHaveLength(0);
    expect(router.dismissTo).not.toHaveBeenCalled();
    await press(labelled(t('staff.backToProfessional')));
    expect(router.back).toHaveBeenCalled();
  });

  it('after Staff was shown, a denial from either tab leaves calmly for Professional', async () => {
    const announcement = jest.spyOn(Alert, 'alert').mockImplementation(() => undefined);
    await render();
    invitationsRead.mockResolvedValueOnce({ data: null, error: STAFF_ACCESS_DENIED });
    await press(tab('invitations'));
    expect(router.dismissTo).toHaveBeenCalledWith('/professional');
    expect(announcement).toHaveBeenCalledWith(t('staff.title'), t('staff.unavailable'));
    announcement.mockRestore();
  });
});

describe('Organization change', () => {
  it('changes A to B without retaining A, and ignores A answering late', async () => {
    const lateA = deferred<StaffPageResult<StaffMemberRow>>();
    membersRead.mockReturnValueOnce(lateA.promise);
    await render();
    mockOrganizationId = 'B';
    contextRead.mockResolvedValue(context('B'));
    membersRead.mockResolvedValueOnce(page([member(2, { displayName: 'Member of B' })]));
    await act(async () => {
      tree.update(createElement(OrganizationStaffRoute));
    });
    await act(async () => lateA.resolve(page([member(1, { displayName: 'Member of A' })])));
    expect(membersRead).toHaveBeenLastCalledWith('B', null, 25);
    expect(shown()).toContain('Member of B');
    expect(shown()).toContain('MenizVet Org B');
    expect(shown()).not.toContain('Member of A');
    expect(getProfessionalOrganizationSelection()).toEqual({
      membershipId: 'self-B',
      organizationId: 'B',
    });
  });
});

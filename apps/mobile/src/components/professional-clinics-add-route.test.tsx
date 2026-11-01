import { createElement } from 'react';
import {
  AccessibilityInfo,
  Alert,
  FlatList,
  Text,
  TextInput,
  type AlertButton,
} from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';
import { uuid } from 'expo-modules-core';

import ProfessionalClinicsScreen from '@/app/professional/clinics/index';
import { createClinic, type ClinicCreationResult } from '@/data/clinic-creation';
import {
  getMyOrganizationProfessionalClinicsPage,
  type OrganizationProfessionalClinic,
} from '@/data/professional-clinics';
import {
  getMyProfessionalContext,
  type ProfessionalCapability,
  type ProfessionalContext,
} from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import { forgetClinicCreation, rememberClinicCreation } from '@/lib/clinic-creation';
import { setProfessionalOrganizationSelection } from '@/lib/professional-organization-selection';

jest.mock('expo-router', () => {
  // Every mounted focus effect, so a test can simulate coming back to the screen.
  const focused = new Set<() => void>();
  return {
    mockRefocus: () => focused.forEach((callback) => callback()),
    useFocusEffect: (callback: () => void | (() => void)) => {
      const React = jest.requireActual('react');
      React.useEffect(() => {
        focused.add(callback);
        const cleanup = callback();
        return () => {
          focused.delete(callback);
          if (typeof cleanup === 'function') cleanup();
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
  };
});
jest.mock('@/components/design-system/app-top-bar', () => ({ AppTopBar: () => null }));
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
});
jest.mock('@/data/professional-clinics', () => ({
  ...jest.requireActual('@/data/professional-clinics'),
  getMyOrganizationProfessionalClinicsPage: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/data/clinic-creation', () => ({
  ...jest.requireActual('@/data/clinic-creation'),
  createClinic: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const pageRead = getMyOrganizationProfessionalClinicsPage as jest.Mock;
const { mockRefocus: refocus } = jest.requireMock('expo-router') as { mockRefocus: () => void };
const contextRead = getMyProfessionalContext as jest.Mock;
const create_ = createClinic as jest.Mock;
const key = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const LONG_NAME = 'Red Veterinaria de Validación MenizVet con un nombre de organización muy largo';

const clinic = (
  clinicId: string,
  name: string | null = `Clinic ${clinicId}`,
): OrganizationProfessionalClinic => ({ clinicId, clinicDisplayName: name });
const pageOk = (...rows: OrganizationProfessionalClinic[]) => ({ data: rows, error: null });
/** Pages per Organization, without a search; any other read is an empty page. */
const pagesByOrganization = (pages: Record<string, OrganizationProfessionalClinic[]>) =>
  pageRead.mockImplementation(async (organizationId: string) =>
    pageOk(...(pages[organizationId] ?? [])),
  );
const organization = (
  organizationId: string,
  granted: ProfessionalCapability[],
  name?: string,
) => ({
  membershipId: `m-${organizationId}`,
  organizationId,
  organizationDisplayName: name ?? `Organization ${organizationId}`,
  responsibilities: [],
  capabilities: granted.map((capability) => ({
    capability,
    scope: { type: 'ORGANIZATION' as const },
  })),
  unknownCapabilities: [],
  clinicAssignments: [],
  entitlements: {
    APPOINTMENT_MANAGEMENT: false,
    PROFESSIONAL_SCHEDULING: false,
    CLINICAL_CARE: false,
    CLINICAL_DOCUMENTATION: false,
  },
});
const contextOk = (
  ...organizations: ReturnType<typeof organization>[]
): { data: ProfessionalContext; error: null } => ({
  data: { hasVeterinarianProfessionalProfile: false, organizations },
  error: null,
});
const CREATE: ProfessionalCapability[] = ['ORGANIZATION_CREATE_CLINICS'];
const created = (clinicId: string): ClinicCreationResult => ({
  kind: 'created',
  clinicId,
  outcome: 'CREATED',
});
const select = (organizationId: string) =>
  setProfessionalOrganizationSelection({ membershipId: `m-${organizationId}`, organizationId });

let tree: ReactTestRenderer;
let alert: jest.SpyInstance;
let announce: jest.SpyInstance;
// The native UUID v4 generator: a predictable sequence of well-formed keys.
let generatedKeys = 0;
let generateKey: jest.SpyInstance;
const texts = () => tree.root.findAllByType(Text).map((node) => node.props.children);
const addLabel = (organization: string) =>
  i18n.t('clinicCreation.addAccessibility', { organization });
const buttons = (label: string) =>
  tree.root.findAll(
    (node) => node.props.accessibilityLabel === label && typeof node.props.onPress === 'function',
  );
const settingsOf = (clinicId: string) => ({
  pathname: '/professional/clinics/[clinicId]/settings',
  params: { clinicId },
});

const searchFields = () =>
  tree.root
    .findAllByType(TextInput)
    .filter(
      (node) => node.props.accessibilityLabel === i18n.t('professionalClinics.searchAccessibility'),
    );
const shownIds = () =>
  (tree.root.findByType(FlatList).props.data as OrganizationProfessionalClinic[]).map(
    (row) => row.clinicId,
  );
async function type(text: string) {
  await act(async () => {
    searchFields()[0].props.onChangeText(text);
  });
}
async function wait(ms: number) {
  await act(async () => {
    jest.advanceTimersByTime(ms);
  });
}

async function render() {
  await act(async () => {
    tree = create(createElement(ProfessionalClinicsScreen));
  });
}
async function press(label: string) {
  const [button] = buttons(label);
  await act(async () => {
    button.props.onPress();
  });
}
async function choose(text: string) {
  const [, , choices] = alert.mock.calls.at(-1) as [string, string, AlertButton[]];
  await act(async () => {
    choices.find((choice) => choice.text === text)?.onPress?.();
  });
}
const confirmCreate = () => choose(i18n.t('clinicCreation.confirm'));

beforeEach(() => {
  jest.clearAllMocks();
  pageRead.mockReset();
  contextRead.mockReset();
  create_.mockReset();
  generatedKeys = 0;
  generateKey = jest.spyOn(uuid, 'v4').mockImplementation(() => key(++generatedKeys));
  select('A');
  alert = jest.spyOn(Alert, 'alert').mockImplementation(() => undefined);
  announce = jest.spyOn(AccessibilityInfo, 'announceForAccessibility').mockImplementation(() => {});
});
afterEach(() => {
  act(() => tree.unmount());
  alert.mockRestore();
  announce.mockRestore();
  generateKey.mockRestore();
  forgetClinicCreation('A');
  forgetClinicCreation('B');
  setProfessionalOrganizationSelection(null);
});

describe('Clinics screen: Add Clinic visibility (advisory)', () => {
  it('an Organization with no Clinics and the capability shows its name, a calm empty state and Add Clinic', async () => {
    pagesByOrganization({ B: [clinic('b1')] });
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE), organization('B', [])));
    await render();
    expect(texts()).toContain('Organization A');
    expect(texts()).toContain(i18n.t('clinicCreation.emptyTitle'));
    expect(texts()).toContain(i18n.t('clinicCreation.emptyMessage'));
    expect(i18n.t('clinicCreation.emptyMessage')).toMatch(/privada/);
    expect(buttons(addLabel('Organization A')).length).toBeGreaterThan(0);
    expect(texts()).not.toContain('Clinic b1');
  });

  it('existing Clinics stay listed, with Add Clinic as a secondary action', async () => {
    pagesByOrganization({ A: [clinic('a1')], B: [clinic('b1')] });
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE)));
    await render();
    expect(texts()).toContain('Clinic a1');
    expect(texts()).not.toContain(i18n.t('clinicCreation.emptyTitle'));
    expect(buttons(addLabel('Organization A')).length).toBeGreaterThan(0);
  });

  it('offers no Add Clinic without the capability', async () => {
    pagesByOrganization({ A: [clinic('a1')] });
    contextRead.mockResolvedValue(contextOk(organization('A', ['ORGANIZATION_INVITE_MEMBERS'])));
    await render();
    expect(texts()).toContain('Clinic a1');
    expect(buttons(addLabel('Organization A'))).toHaveLength(0);
    expect(texts()).not.toContain(i18n.t('clinicCreation.addAction'));
  });

  it('with the capability in another Organization only, the selection is not an Organization of the User', async () => {
    pagesByOrganization({ A: [clinic('a1')] });
    contextRead.mockResolvedValue(contextOk(organization('B', CREATE)));
    await render();
    expect(texts()).toContain(i18n.t('professionalClinics.chooseOrganization'));
    expect(texts()).not.toContain(i18n.t('clinicCreation.addAction'));
    expect(pageRead).not.toHaveBeenCalled();
  });

  it('an unreadable professional context shows the error state with a retry, and reads no Clinic', async () => {
    pagesByOrganization({ A: [clinic('a1')] });
    contextRead.mockResolvedValueOnce({ data: null, error: 'offline' });
    await render();
    expect(texts()).toContain(i18n.t('professional.loadError'));
    expect(texts()).not.toContain('Clinic a1');
    expect(pageRead).not.toHaveBeenCalled();
    contextRead.mockResolvedValue(contextOk(organization('A', [])));
    await press(i18n.t('professional.retry'));
    expect(texts()).toContain('Clinic a1');
  });

  it('with zero Clinics and no capability shows the calm empty state, without Add or search', async () => {
    pagesByOrganization({ B: [clinic('b1')] });
    contextRead.mockResolvedValue(contextOk(organization('A', []), organization('B', [])));
    await render();
    expect(texts()).toContain(i18n.t('professionalClinics.empty'));
    expect(texts()).not.toContain(i18n.t('clinicCreation.addAction'));
    expect(searchFields()).toHaveLength(0);
  });

  it('a selection the context does not contain sends the User back to choose an Organization', async () => {
    contextRead.mockResolvedValue(contextOk(organization('B', [])));
    await render();
    expect(texts()).toContain(i18n.t('professionalClinics.chooseOrganization'));
    expect(pageRead).not.toHaveBeenCalled();
  });

  it('a long Organization name is shown whole and names the Add action', async () => {
    pagesByOrganization({});
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE, LONG_NAME)));
    await render();
    const heading = tree.root.findAll(
      (node) => node.type === Text && node.props.children === LONG_NAME,
    );
    expect(heading.length).toBeGreaterThan(0);
    expect(heading[0].props.numberOfLines).toBeUndefined();
    expect(buttons(addLabel(LONG_NAME)).length).toBeGreaterThan(0);
  });
});

describe('Add Clinic interaction', () => {
  beforeEach(() => {
    pagesByOrganization({});
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE)));
  });

  it('asks for one confirmation that explains the Clinic stays private; nothing is created before it', async () => {
    await render();
    await press(addLabel('Organization A'));
    expect(create_).not.toHaveBeenCalled();
    const [title, message] = alert.mock.calls.at(-1) as [string, string];
    expect(title).toBe(i18n.t('clinicCreation.confirmTitle', { organization: 'Organization A' }));
    expect(message).toBe(i18n.t('clinicCreation.confirmMessage'));
    expect(message).toMatch(/privada/);
    expect(message).toMatch(
      /no será visible para los responsables de mascotas hasta que la publiques/,
    );
    expect(message).not.toMatch(/tutor/i);
    expect(message).toMatch(/ajustes de la clínica/);
  });

  it('Cancel creates nothing', async () => {
    await render();
    await press(addLabel('Organization A'));
    await choose(i18n.t('clinicCreation.cancel'));
    expect(create_).not.toHaveBeenCalled();
    expect(router.push).not.toHaveBeenCalled();
  });

  it('Confirm sends one key for the shown Organization and opens the new Clinic settings', async () => {
    create_.mockResolvedValue(created('new-1'));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(create_).toHaveBeenCalledTimes(1);
    expect(create_).toHaveBeenCalledWith('A', key(1));
    expect(router.push).toHaveBeenCalledWith(settingsOf('new-1'));
    expect(router.replace).not.toHaveBeenCalled();
    expect(announce).toHaveBeenCalledWith(i18n.t('clinicCreation.creating'));
    expect(announce).toHaveBeenCalledWith(i18n.t('clinicCreation.created'));
  });

  it('a replayed intent (ALREADY_CREATED) opens the same Clinic', async () => {
    create_.mockResolvedValue({ kind: 'created', clinicId: 'new-1', outcome: 'ALREADY_CREATED' });
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(router.push).toHaveBeenCalledWith(settingsOf('new-1'));
  });

  it('each new Add Clinic intent gets a new key; a finished intent is never resent', async () => {
    create_.mockResolvedValueOnce(created('new-1')).mockResolvedValueOnce(created('new-2'));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(create_.mock.calls).toEqual([
      ['A', key(1)],
      ['A', key(2)],
    ]);
  });

  it('while creating, Add is busy and a second tap or confirmation sends nothing', async () => {
    let finish: (value: ClinicCreationResult) => void = () => {};
    create_.mockImplementation(() => new Promise((resolve) => (finish = resolve)));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    const busy = buttons(addLabel('Organization A')).filter(
      (node) => node.props.accessibilityState?.busy === true,
    );
    expect(busy.length).toBeGreaterThan(0);
    const confirmations = alert.mock.calls.length;
    await press(addLabel('Organization A'));
    expect(alert.mock.calls.length).toBe(confirmations);
    await confirmCreate();
    expect(create_).toHaveBeenCalledTimes(1);
    // No placeholder Clinic appears while the request is in flight.
    expect(texts()).not.toContain(i18n.t('professional.unnamedClinic'));
    await act(async () => finish(created('new-1')));
    expect(router.push).toHaveBeenCalledTimes(1);
  });

  it('an uncertain answer keeps the intent: a deliberate retry reuses the same key and opens the Clinic', async () => {
    create_.mockResolvedValueOnce({ kind: 'uncertain' }).mockResolvedValueOnce(created('new-1'));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(router.push).not.toHaveBeenCalled();
    expect(texts()).toContain(i18n.t('clinicCreation.uncertain'));
    expect(announce).toHaveBeenCalledWith(i18n.t('clinicCreation.uncertain'));
    // No new intent can start while this one is unresolved.
    expect(buttons(addLabel('Organization A'))).toHaveLength(0);
    // The re-read is authoritative: no optimistic Clinic was added.
    expect(pageRead).toHaveBeenCalledTimes(2);
    expect(texts()).not.toContain(i18n.t('professional.unnamedClinic'));
    await press(i18n.t('clinicCreation.retryAccessibility'));
    expect(create_.mock.calls).toEqual([
      ['A', key(1)],
      ['A', key(1)],
    ]);
    expect(router.push).toHaveBeenCalledWith(settingsOf('new-1'));
  });

  it('an uncertain intent survives leaving and re-entering the screen, with the same key', async () => {
    create_.mockResolvedValueOnce({ kind: 'uncertain' }).mockResolvedValueOnce(created('new-1'));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    act(() => tree.unmount());
    await render();
    expect(texts()).toContain(i18n.t('clinicCreation.uncertain'));
    expect(buttons(addLabel('Organization A'))).toHaveLength(0);
    await press(i18n.t('clinicCreation.retryAccessibility'));
    expect(create_).toHaveBeenLastCalledWith('A', key(1));
    expect(router.push).toHaveBeenCalledWith(settingsOf('new-1'));
  });

  it('a confirmation that meets an unresolved intent for the Organization reuses its key, never a new one', async () => {
    create_.mockResolvedValue(created('new-1'));
    await render();
    await press(addLabel('Organization A'));
    // Another screen instance left this Organization's intent unresolved meanwhile.
    rememberClinicCreation({ organizationId: 'A', key: key(41) });
    await confirmCreate();
    expect(create_).toHaveBeenCalledTimes(1);
    expect(create_).toHaveBeenCalledWith('A', key(41));
    expect(generateKey).not.toHaveBeenCalled();
  });

  it('a definite rejection ends the intent calmly; a later Add Clinic is a new intent with a new key', async () => {
    create_.mockResolvedValueOnce({ kind: 'accessDenied' }).mockResolvedValueOnce(created('new-2'));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(texts()).toContain(i18n.t('clinicCreation.notAllowed'));
    expect(texts()).not.toContain(i18n.t('clinicCreation.uncertain'));
    expect(router.push).not.toHaveBeenCalled();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(create_.mock.calls).toEqual([
      ['A', key(1)],
      ['A', key(2)],
    ]);
  });

  it('an error, then a deliberate new attempt, succeeds without any automatic retry', async () => {
    create_.mockResolvedValueOnce({ kind: 'rejected' }).mockResolvedValueOnce(created('new-2'));
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(create_).toHaveBeenCalledTimes(1);
    expect(texts()).toContain(i18n.t('clinicCreation.failed'));
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(create_).toHaveBeenCalledTimes(2);
    expect(router.push).toHaveBeenCalledWith(settingsOf('new-2'));
  });
});

describe('Organization isolation', () => {
  it('Add Clinic under A creates only in A, and B shows only its own state', async () => {
    pagesByOrganization({ B: [clinic('b1')] });
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE), organization('B', [])));
    create_.mockResolvedValue({ kind: 'uncertain' });
    await render();
    await press(addLabel('Organization A'));
    await confirmCreate();
    expect(create_).toHaveBeenCalledWith('A', key(1));
    await act(async () => select('B'));
    expect(texts()).toContain('Clinic b1');
    expect(texts()).not.toContain(i18n.t('clinicCreation.uncertain'));
    expect(buttons(i18n.t('clinicCreation.retryAccessibility'))).toHaveLength(0);
    expect(texts()).not.toContain(i18n.t('clinicCreation.addAction'));
    // Back to A: its own unresolved intent is still the only way forward.
    await act(async () => select('A'));
    expect(texts()).toContain(i18n.t('clinicCreation.uncertain'));
  });

  it('a selection changed while confirming never redirects the creation', async () => {
    pagesByOrganization({});
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE), organization('B', CREATE)));
    create_.mockResolvedValue(created('new-1'));
    await render();
    await press(addLabel('Organization A'));
    await act(async () => select('B'));
    await confirmCreate();
    expect(create_).toHaveBeenCalledTimes(1);
    expect(create_).toHaveBeenCalledWith('A', key(1));
  });

  it('capability is evaluated per Organization when switching A → B', async () => {
    pagesByOrganization({});
    contextRead.mockResolvedValue(contextOk(organization('A', CREATE), organization('B', [])));
    await render();
    expect(buttons(addLabel('Organization A')).length).toBeGreaterThan(0);
    await act(async () => select('B'));
    expect(texts()).not.toContain(i18n.t('clinicCreation.addAction'));
    expect(buttons(addLabel('Organization B'))).toHaveLength(0);
    expect(texts()).toContain(i18n.t('professionalClinics.empty'));
  });
});

describe('Search and pages (SPEC-ORG-008 BR-26)', () => {
  type Page =
    { data: OrganizationProfessionalClinic[]; error: null } | { data: null; error: string };
  const later = () => {
    let resolve: (page: Page) => void = () => {};
    const promise = new Promise<Page>((done) => (resolve = done));
    return { promise, resolve };
  };
  const callsWith = (search: string | null) =>
    pageRead.mock.calls.filter(([, sent]) => sent === search);
  const unnamedLabel = () => i18n.t('professional.unnamedClinic');

  beforeEach(() => {
    jest.useFakeTimers();
    contextRead.mockResolvedValue(contextOk(organization('A', [])));
  });
  afterEach(() => {
    jest.useRealTimers();
  });

  it('shows one list of compact rows: the name or the unnamed label, each one button', async () => {
    pagesByOrganization({
      A: [clinic('c1', 'Clínica Centro'), clinic('c2', 'Clínica Centro'), clinic('c3', null)],
    });
    await render();
    expect(shownIds()).toEqual(['c1', 'c2', 'c3']);
    expect(buttons('Clínica Centro')).toHaveLength(2);
    expect(buttons(unnamedLabel())).toHaveLength(1);
    expect(searchFields()).toHaveLength(1);
    expect(pageRead).toHaveBeenCalledWith('A', null, null, 20);
  });

  it('typing is sent once after a 300 ms pause, and the new search withdraws the previous rows at once', async () => {
    const pending = later();
    pageRead.mockImplementation(async (_organization: string, search: string | null) =>
      search === null ? pageOk(clinic('a1', 'Animalia')) : pending.promise,
    );
    await render();
    await type('p');
    await wait(100);
    await type('pe');
    await wait(100);
    await type('peñ');
    await wait(299);
    expect(pageRead.mock.calls.map(([, search]) => search)).toEqual([null]);
    expect(shownIds()).toEqual(['a1']);
    await wait(1);
    expect(pageRead).toHaveBeenLastCalledWith('A', 'peñ', null, 20);
    expect(callsWith('peñ')).toHaveLength(1);
    // Withdrawn at once: loading, never the previous search's rows.
    expect(shownIds()).toEqual([]);
    expect(texts()).toContain(i18n.t('professionalClinics.searching'));
    expect(texts()).not.toContain(i18n.t('professionalClinics.noMatches', { search: 'peñ' }));
    await act(async () => pending.resolve(pageOk(clinic('p1', 'Peña'))));
    expect(shownIds()).toEqual(['p1']);
  });

  it('a late answer to an earlier search is ignored', async () => {
    const first = later();
    pageRead.mockImplementation(async (_organization: string, search: string | null) =>
      search === 'a' ? first.promise : search === 'b' ? pageOk(clinic('b1')) : pageOk(clinic('x0')),
    );
    await render();
    await type('a');
    await wait(300);
    await type('b');
    await wait(300);
    expect(shownIds()).toEqual(['b1']);
    await act(async () => first.resolve(pageOk(clinic('late'))));
    expect(shownIds()).toEqual(['b1']);
  });

  it('"no matches" only once the first page arrived empty; clearing restarts at once without a search', async () => {
    const pending = later();
    pageRead.mockImplementation(async (_organization: string, search: string | null) =>
      search === null ? pageOk(clinic('a1')) : pending.promise,
    );
    await render();
    await type('zz');
    await wait(300);
    const noMatches = i18n.t('professionalClinics.noMatches', { search: 'zz' });
    expect(texts()).not.toContain(noMatches);
    await act(async () => pending.resolve(pageOk()));
    expect(texts()).toContain(noMatches);
    // The search field stays, so the User can change or clear it.
    expect(searchFields()).toHaveLength(1);
    const before = callsWith(null).length;
    await press(i18n.t('professionalClinics.clearSearch'));
    // No pause: the list restarts without a search immediately.
    expect(callsWith(null)).toHaveLength(before + 1);
    expect(searchFields()[0].props.value).toBe('');
    expect(shownIds()).toEqual(['a1']);
  });

  it('outer whitespace never starts a search; submitting searches at once', async () => {
    pagesByOrganization({ A: [clinic('a1')] });
    await render();
    await type('   ');
    await wait(1000);
    expect(pageRead).toHaveBeenCalledTimes(1);
    await type(' pe ');
    await act(async () => {
      searchFields()[0].props.onSubmitEditing();
    });
    expect(pageRead).toHaveBeenLastCalledWith('A', 'pe', null, 20);
    await wait(1000);
    expect(callsWith('pe')).toHaveLength(1);
  });

  it('Load more continues from the complete key of the last row and never shows a Clinic twice', async () => {
    const first = Array.from({ length: 19 }, (_, n) =>
      clinic(`r${String(n + 1).padStart(2, '0')}`, 'Clínica Centro'),
    );
    const unnamed = clinic('r20', null);
    pageRead.mockImplementation(
      async (_organization: string, _search: string | null, after: unknown) =>
        after === null ? pageOk(...first, unnamed) : pageOk(unnamed, clinic('r21', null)),
    );
    await render();
    expect(shownIds()).toHaveLength(20);
    await press(i18n.t('pagedList.loadMore'));
    expect(pageRead).toHaveBeenLastCalledWith(
      'A',
      null,
      { displayName: null, clinicId: 'r20' },
      20,
    );
    const ids = shownIds();
    expect(ids).toHaveLength(21);
    expect(ids.filter((id) => id === 'r20')).toHaveLength(1);
    expect(ids.at(-1)).toBe('r21');
    // A shorter page ends the list.
    expect(buttons(i18n.t('pagedList.loadMore'))).toHaveLength(0);
  });

  it('a search keeps its cursor to its own pages; a new search restarts from the first page', async () => {
    const full = Array.from({ length: 20 }, (_, n) => clinic(`p${n}`, `Peña ${n}`));
    pageRead.mockImplementation(async (_organization: string, search: string | null) =>
      search === 'pe' ? pageOk(...full) : pageOk(clinic('a1')),
    );
    await render();
    await type('pe');
    await wait(300);
    await press(i18n.t('pagedList.loadMore'));
    expect(pageRead).toHaveBeenLastCalledWith(
      'A',
      'pe',
      { displayName: 'Peña 19', clinicId: 'p19' },
      20,
    );
    await type('pen');
    await wait(300);
    expect(pageRead).toHaveBeenLastCalledWith('A', 'pen', null, 20);
  });

  it('coming back to the screen restarts the first page and keeps the search', async () => {
    pageRead.mockImplementation(async (_organization: string, search: string | null) =>
      search === 'pe' ? pageOk(clinic('p1', 'Peña')) : pageOk(clinic('a1')),
    );
    await render();
    await type('pe');
    await wait(300);
    const before = callsWith('pe').length;
    await act(async () => refocus());
    expect(callsWith('pe')).toHaveLength(before + 1);
    expect(pageRead).toHaveBeenLastCalledWith('A', 'pe', null, 20);
    expect(searchFields()[0].props.value).toBe('pe');
    expect(shownIds()).toEqual(['p1']);
  });

  it('lost access: an empty refresh shows the calm empty state; a context without the Organization sends back', async () => {
    pagesByOrganization({ A: [clinic('a1')] });
    await render();
    expect(shownIds()).toEqual(['a1']);
    pagesByOrganization({});
    await act(async () => refocus());
    expect(shownIds()).toEqual([]);
    expect(texts()).toContain(i18n.t('professionalClinics.empty'));
    expect(searchFields()).toHaveLength(0);
    contextRead.mockResolvedValue(contextOk(organization('B', [])));
    await act(async () => refocus());
    expect(texts()).toContain(i18n.t('professionalClinics.chooseOrganization'));
    expect(texts()).not.toContain('Clinic a1');
    // Without the Organization in the context, no Clinic of it is read any more.
    const reads = pageRead.mock.calls.length;
    await act(async () => refocus());
    expect(pageRead.mock.calls.length).toBe(reads);
  });

  it('a failed first page offers a retry; a failed refresh keeps the rows on screen', async () => {
    pageRead.mockResolvedValueOnce({ data: null, error: 'offline' });
    await render();
    expect(texts()).toContain(i18n.t('professionalClinics.loadError'));
    pagesByOrganization({ A: [clinic('a1')] });
    await press(i18n.t('professional.retry'));
    expect(shownIds()).toEqual(['a1']);
    pageRead.mockResolvedValueOnce({ data: null, error: 'offline' });
    await act(async () => refocus());
    expect(shownIds()).toEqual(['a1']);
    expect(texts()).toContain(i18n.t('pagedList.refreshError'));
  });
});

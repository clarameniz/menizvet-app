import { router } from 'expo-router';
import { createElement } from 'react';
import { FlatList, Text, TextInput } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import ClinicsScreen from '@/app/clinics';
import ClinicDetailScreen from '@/app/clinics/[id]';
import { getPublishedClinicDetail } from '@/data/clinics';
import { i18n } from '@/i18n/i18n';

/**
 * The public Clinic list (SPEC-DIS-004 §5) against an emulated
 * `discover_published_clinics` keyset backend: alphabetical pages of 20 with
 * the server's own cursor and `has_more`, a debounced server-side search that
 * withdraws the previous rows at once, late answers ignored, retries, empty
 * states, the Nearby/Map shortcuts, and — on return from a Clinic — the
 * search, pages and cursor kept. Focus is simulated by re-running the
 * registered focus callbacks, as expo-router does on return from a detail.
 */

let mockFocusCallbacks: (() => void)[] = [];
jest.mock('expo-router', () => {
  const { useEffect } = jest.requireActual<typeof import('react')>('react');
  return {
    useFocusEffect: (callback: () => void) => {
      useEffect(() => {
        mockFocusCallbacks.push(callback);
        callback();
        return () => {
          mockFocusCallbacks = mockFocusCallbacks.filter((registered) => registered !== callback);
        };
      }, [callback]);
    },
    useLocalSearchParams: () => ({ id: 'missing-clinic' }),
    router: {
      push: jest.fn(),
      replace: jest.fn(),
      back: jest.fn(),
      canGoBack: jest.fn(() => true),
    },
  };
});
jest.mock('@/components/design-system/public-top-bar', () => ({ PublicTopBar: () => null }));
jest.mock('react-native-safe-area-context', () => {
  const { View } = jest.requireActual('react-native');
  return {
    SafeAreaView: View,
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
  };
});
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  return { useLocale: () => ({ locale: 'es', t: mockI18n.t.bind(mockI18n) }) };
});
jest.mock('@/data/clinics', () => ({
  ...jest.requireActual('@/data/clinics'),
  getPublishedClinicDetail: jest.fn(),
}));
// The supabase client exposes only `rpc`: the list must never need a session.
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...args: unknown[]) => mockRpc(...args) },
}));

type ServerClinic = {
  clinic_id: string;
  display_name: string | null;
  description: string | null;
  address_text: string | null;
};

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const fold = (value: string) =>
  value.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

let serverClinics: ServerClinic[] = [];
let failNext = 0;
const held: { args: Record<string, unknown>; resolve: () => void }[] = [];
let holdNext = false;

/** A keyset backend: name order (unnamed last), then id; search by folded name. */
function respond(args: Record<string, unknown>) {
  const search = typeof args.p_search === 'string' ? fold(args.p_search) : '';
  const afterName = args.p_after_display_name as string | null;
  const afterId = args.p_after_clinic_id as string | null;
  const limit = args.p_limit as number;
  const ordered = [...serverClinics]
    .filter(
      (clinic) =>
        search === '' ||
        (clinic.display_name !== null && fold(clinic.display_name).includes(search)),
    )
    .sort((a, b) =>
      a.display_name === b.display_name
        ? a.clinic_id.localeCompare(b.clinic_id)
        : a.display_name === null
          ? 1
          : b.display_name === null
            ? -1
            : a.display_name.localeCompare(b.display_name),
    );
  const start =
    afterId === null
      ? 0
      : ordered.findIndex(
          (clinic) => clinic.clinic_id === afterId && clinic.display_name === afterName,
        ) + 1;
  const page = ordered.slice(start, start + limit + 1);
  const shown = page.slice(0, limit);
  const last = shown.at(-1) ?? null;
  return {
    data: {
      clinics: shown,
      has_more: page.length > limit,
      next_after_display_name: last?.display_name ?? null,
      next_after_clinic_id: last?.clinic_id ?? null,
    },
    error: null,
  };
}

function seed(count: number) {
  serverClinics = Array.from({ length: count }, (_, index) => ({
    clinic_id: ID(index + 1),
    display_name: `Clínica ${String(index + 1).padStart(2, '0')}`,
    description: index % 2 === 0 ? `Descripción ${index + 1}` : null,
    address_text: index % 3 === 0 ? `Calle ${index + 1}` : null,
  }));
}

let tree: ReactTestRenderer;
const t = (key: string, options?: Record<string, unknown>) => i18n.t(key, options);
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const allText = () => texts().join(' | ');
const button = (label: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.onPress === 'function' &&
      node.props.accessibilityLabel === label,
  )[0] as ReactTestInstance | undefined;
const buttonStartingWith = (prefix: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.onPress === 'function' &&
      typeof node.props.accessibilityLabel === 'string' &&
      node.props.accessibilityLabel.startsWith(prefix),
  )[0] as ReactTestInstance | undefined;
const searchInput = () => tree.root.findByType(TextInput);
/** The names of the rows the list holds (FlatList renders only the first ones). */
const listed = () =>
  (tree.root.findByType(FlatList).props.data as { displayName: string | null }[]).map(
    (row) => row.displayName,
  );
const loadMore = () => button(t('pagedList.loadMore'));
const lastArgs = () => mockRpc.mock.calls.at(-1)?.[1] as Record<string, unknown>;

async function press(node: ReactTestInstance | undefined) {
  if (node === undefined) throw new Error('No such control');
  await act(async () => node.props.onPress());
}
async function type(value: string) {
  await act(async () => searchInput().props.onChangeText(value));
}
async function pause(ms = 300) {
  await act(async () => {
    jest.advanceTimersByTime(ms);
  });
}
async function focusAgain() {
  await act(async () => {
    for (const callback of [...mockFocusCallbacks]) callback();
  });
}
async function render() {
  await act(async () => {
    tree = create(createElement(ClinicsScreen));
  });
}

beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  mockFocusCallbacks = [];
  i18n.locale = 'es';
  seed(45);
  failNext = 0;
  holdNext = false;
  held.length = 0;
  mockRpc.mockImplementation((name: string, args: Record<string, unknown>) => {
    if (name !== 'discover_published_clinics') throw new Error(`Unexpected read ${name}`);
    if (failNext > 0) {
      failNext -= 1;
      return Promise.resolve({ data: null, error: { message: 'timeout' } });
    }
    if (holdNext) {
      holdNext = false;
      return new Promise((resolve) => held.push({ args, resolve: () => resolve(respond(args)) }));
    }
    return Promise.resolve(respond(args));
  });
});
afterEach(() => {
  act(() => tree.unmount());
  jest.useRealTimers();
});

it('first entry reads the first page of 20, with no search and no cursor, and no session', async () => {
  await render();
  expect(mockRpc).toHaveBeenCalledTimes(1);
  expect(mockRpc).toHaveBeenCalledWith('discover_published_clinics', {
    p_search: null,
    p_after_display_name: null,
    p_after_clinic_id: null,
    p_limit: 20,
  });
  expect(listed()).toContain('Clínica 01');
  expect(listed()).toContain('Clínica 20');
  expect(listed()).not.toContain('Clínica 21');
});

it('each card shows the name and the public address, or else the description, and opens the Clinic', async () => {
  await render();
  // Clinic 01: address and description — the address wins.
  expect(allText()).toContain('Calle 1');
  expect(allText()).not.toContain('Descripción 1 |');
  // Clinic 03: description only.
  expect(allText()).toContain('Descripción 3');
  await press(buttonStartingWith('Clínica 02'));
  expect(router.push).toHaveBeenCalledWith(`/clinics/${ID(2)}`);
});

it('Load more continues from the server cursor while the read reports more', async () => {
  await render();
  await press(loadMore());
  expect(lastArgs()).toEqual({
    p_search: null,
    p_after_display_name: 'Clínica 20',
    p_after_clinic_id: ID(20),
    p_limit: 20,
  });
  expect(listed()).toContain('Clínica 40');
  await press(loadMore());
  expect(listed()).toContain('Clínica 45');
  expect(loadMore()).toBeUndefined();
  expect(mockRpc).toHaveBeenCalledTimes(3);
});

it('a full last page with has_more false offers no Load more', async () => {
  seed(20);
  await render();
  expect(listed()).toContain('Clínica 20');
  expect(loadMore()).toBeUndefined();
});

it('the search is sent after the pause and withdraws the previous rows at once', async () => {
  await render();
  await type('clinica 0');
  expect(mockRpc).toHaveBeenCalledTimes(1);
  await pause(299);
  expect(mockRpc).toHaveBeenCalledTimes(1);

  holdNext = true;
  await pause(1);
  expect(mockRpc).toHaveBeenCalledTimes(2);
  expect(lastArgs()).toMatchObject({ p_search: 'clinica 0', p_after_clinic_id: null });
  // Withdrawn while the new search loads.
  expect(listed()).not.toContain('Clínica 15');
  expect(allText()).toContain(t('discoveryBasic.searching'));

  await act(async () => held.shift()?.resolve());
  expect(listed()).toContain('Clínica 09');
  expect(listed()).not.toContain('Clínica 15');
});

it('outer whitespace never starts a new search; submitting searches at once', async () => {
  await render();
  await type('   ');
  await pause();
  expect(mockRpc).toHaveBeenCalledTimes(1);
  await type('Clínica 4');
  await act(async () => searchInput().props.onSubmitEditing());
  expect(lastArgs()).toMatchObject({ p_search: 'Clínica 4' });
  expect(listed()).toContain('Clínica 45');
});

it('ignores the late answer of an earlier search', async () => {
  await render();
  holdNext = true;
  await type('clinica 1');
  await pause();
  await type('clinica 2');
  await pause();
  expect(held).toHaveLength(1);
  expect(listed()).toContain('Clínica 20');

  // The answer for "clinica 1" arrives after the one for "clinica 2".
  await act(async () => held.shift()?.resolve());
  expect(listed()).toContain('Clínica 20');
  expect(listed()).not.toContain('Clínica 10');
});

it('clearing the search reads the list again at once', async () => {
  await render();
  await type('clinica 3');
  await pause();
  expect(listed()).not.toContain('Clínica 01');
  await press(button(t('discoveryBasic.clearSearch')));
  expect(lastArgs()).toMatchObject({ p_search: null });
  expect(listed()).toContain('Clínica 01');
});

it('no matches is shown only once the search arrived empty, with a clear action', async () => {
  await render();
  holdNext = true;
  await type('zz');
  await pause();
  expect(allText()).not.toContain(t('discoveryBasic.noMatches', { search: 'zz' }));
  await act(async () => held.shift()?.resolve());
  expect(allText()).toContain(t('discoveryBasic.noMatches', { search: 'zz' }));
  expect(allText()).not.toContain(t('discoveryBasic.emptyState'));
  const clearActions = tree.root.findAll(
    (node) =>
      node.props.accessibilityLabel === t('discoveryBasic.clearSearch') &&
      typeof node.props.onPress === 'function',
  );
  await press(clearActions.at(-1));
  expect(listed()).toContain('Clínica 01');
});

it('no published Clinic shows the empty state', async () => {
  seed(0);
  await render();
  expect(allText()).toContain(t('discoveryBasic.emptyState'));
  expect(loadMore()).toBeUndefined();
});

it('a failed first page shows the error with a retry, keeping search and shortcuts', async () => {
  failNext = 1;
  await render();
  expect(allText()).toContain(t('discoveryBasic.loadError'));
  expect(button(t('discoveryBasic.nearbyAction'))).toBeDefined();
  expect(button(t('discoveryBasic.mapAction'))).toBeDefined();
  expect(searchInput()).toBeDefined();
  expect(allText()).not.toContain('timeout');

  await press(button(t('professional.retry')));
  expect(listed()).toContain('Clínica 01');
  expect(allText()).not.toContain(t('discoveryBasic.loadError'));
});

it('a failed Load more keeps the rows and retries the same cursor', async () => {
  await render();
  failNext = 1;
  await press(loadMore());
  expect(listed()).toContain('Clínica 20');
  expect(allText()).toContain(t('pagedList.loadMoreError'));
  await press(button(t('professional.retry')));
  expect(lastArgs()).toMatchObject({
    p_after_display_name: 'Clínica 20',
    p_after_clinic_id: ID(20),
  });
  expect(listed()).toContain('Clínica 40');
});

it('back from a Clinic keeps the search, every loaded page and the cursor, with no read', async () => {
  await render();
  await type('clinica');
  await pause();
  await press(loadMore());
  const reads = mockRpc.mock.calls.length;
  expect(listed()).toContain('Clínica 40');

  await press(buttonStartingWith('Clínica 03'));
  expect(router.push).toHaveBeenCalledWith(`/clinics/${ID(3)}`);
  await focusAgain();
  await focusAgain();

  expect(mockRpc).toHaveBeenCalledTimes(reads);
  expect(searchInput().props.value).toBe('clinica');
  expect(listed()).toContain('Clínica 01');
  expect(listed()).toContain('Clínica 40');
  await press(loadMore());
  expect(lastArgs()).toMatchObject({ p_search: 'clinica', p_after_clinic_id: ID(40) });
  expect(listed()).toContain('Clínica 45');
});

it('a new search after returning still discards the previous search', async () => {
  await render();
  await press(loadMore());
  await focusAgain();
  await type('clinica 45');
  await pause();
  expect(listed()).toContain('Clínica 45');
  expect(listed()).not.toContain('Clínica 01');
  expect(loadMore()).toBeUndefined();
});

it('the Nearby and Map shortcuts open their unchanged routes', async () => {
  await render();
  await press(button(t('discoveryBasic.nearbyAction')));
  expect(router.push).toHaveBeenCalledWith('/clinics/nearby');
  await press(button(t('discoveryBasic.mapAction')));
  expect(router.push).toHaveBeenCalledWith('/clinics/map');
});

it('never shows a Clinic twice when pages overlap', async () => {
  await render();
  // A rename between pages moves Clinic 20 after the cursor (SPEC-DIS-004 BR-8).
  serverClinics = serverClinics.map((clinic) =>
    clinic.clinic_id === ID(20) ? { ...clinic, display_name: 'Clínica 20 bis' } : clinic,
  );
  serverClinics.push({ ...serverClinics[19], clinic_id: ID(20), display_name: 'Clínica 20' });
  await press(loadMore());
  expect(listed().filter((name) => name?.startsWith('Clínica 20'))).toHaveLength(1);
  expect(new Set(listed()).size).toBe(listed().length);
});

describe('Clinic detail "Back to clinics"', () => {
  const detailRead = getPublishedClinicDetail as jest.Mock;

  async function renderUnavailable() {
    detailRead.mockResolvedValueOnce({ data: null, error: null });
    await act(async () => {
      tree = create(createElement(ClinicDetailScreen));
    });
  }

  it('returns to the list beneath instead of opening a second list', async () => {
    await renderUnavailable();
    expect(allText()).toContain(t('discoveryDetail.notFound'));
    await press(button(t('discoveryDetail.backToList')));
    expect(router.back).toHaveBeenCalledTimes(1);
    expect(router.replace).not.toHaveBeenCalled();
  });

  it('opens the list when there is nothing to go back to', async () => {
    (router.canGoBack as jest.Mock).mockReturnValueOnce(false);
    await renderUnavailable();
    await press(button(t('discoveryDetail.backToList')));
    expect(router.replace).toHaveBeenCalledWith('/clinics');
    expect(router.back).not.toHaveBeenCalled();
  });
});

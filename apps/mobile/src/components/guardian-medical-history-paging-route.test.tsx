import * as WebBrowser from 'expo-web-browser';
import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import GuardianMedicalHistoryScreen from '@/app/pets/[id]/medical-history';
import {
  getGuardianClinicalAttachmentDownloadUrl,
  getGuardianPetMedicalHistory,
  type GuardianMedicalHistoryCursor,
  type GuardianMedicalHistoryEntry,
} from '@/data/clinical-history';
import { i18n } from '@/i18n/i18n';

/**
 * How the Guardian medical history is paged (SPEC-MED-005, Guardian read),
 * against a mocked data module: one page read at a time with the server's own
 * cursor, no Entry shown twice, late answers ignored, failures keeping what is
 * shown, DENIED dropping everything, and no re-read after opening an
 * Attachment.
 */

let mockPetId = 'pet-1';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: mockPetId }),
  router: { back: jest.fn(), canGoBack: jest.fn(() => true), dismissTo: jest.fn() },
}));
jest.mock('expo-web-browser', () => ({
  openBrowserAsync: jest.fn(() => Promise.resolve({ type: 'dismiss' })),
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
  return { useLocale: () => ({ locale: 'es', t: mockI18n.t.bind(mockI18n) }) };
});
jest.mock('@/data/clinical-history', () => ({
  ...jest.requireActual('@/data/clinical-history'),
  getGuardianPetMedicalHistory: jest.fn(),
  getGuardianClinicalAttachmentDownloadUrl: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: jest.fn(), functions: { invoke: jest.fn() } },
}));

const read = getGuardianPetMedicalHistory as jest.Mock;
const download = getGuardianClinicalAttachmentDownloadUrl as jest.Mock;
const openBrowser = WebBrowser.openBrowserAsync as jest.Mock;

type ReadResult = Awaited<ReturnType<typeof getGuardianPetMedicalHistory>>;

const entry = (id: string, clinic = `Clínica ${id}`): GuardianMedicalHistoryEntry => ({
  id,
  clinicDisplayName: clinic,
  organizationDisplayName: 'Org X',
  clinicalContent: `Contenido ${id}`,
  category: 'CLINICAL_NOTE',
  otherCategoryContext: null,
  clinicalEventAt: null,
  historyOrderAt: '2026-01-15T08:10:00Z',
  finalizedAt: '2026-01-15T08:10:00Z',
  version: 1,
  editedAt: null,
  previousVersions: [],
  previousVersionsTruncated: false,
  amendments: [],
  amendmentCount: 0,
  amendmentsTruncated: false,
  attachments: [],
});

const cursorAfter = (id: string): GuardianMedicalHistoryCursor => ({
  beforeHistoryOrderAt: '2026-01-15T08:10:00Z',
  beforeEntryId: id,
});

const permitted = (
  entries: GuardianMedicalHistoryEntry[],
  cursor: GuardianMedicalHistoryCursor | null,
): ReadResult => ({ data: { status: 'PERMITTED', page: { entries, cursor } }, error: null });

const denied: ReadResult = { data: { status: 'DENIED' }, error: null };

function deferred() {
  let resolve: (result: ReadResult) => void = () => {};
  const promise = new Promise<ReadResult>((settle) => {
    resolve = settle;
  });
  return { promise, resolve };
}

let tree: ReactTestRenderer;
const t = (key: string, options?: Record<string, unknown>) => i18n.t(key, options);
const allText = () =>
  tree.root
    .findAllByType(Text)
    .map((node) => String(node.props.children))
    .join(' | ');
const button = (label: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.onPress === 'function' &&
      node.props.accessibilityLabel === label,
  )[0] as ReactTestInstance | undefined;
const loadMore = () => button(t('clinicalHistory.loadMore'));
async function press(node: ReactTestInstance | undefined) {
  if (node === undefined) throw new Error('No such control');
  await act(async () => node.props.onPress());
}
async function settle(resolve: (result: ReadResult) => void, result: ReadResult) {
  await act(async () => resolve(result));
}

async function render() {
  await act(async () => {
    tree = create(createElement(GuardianMedicalHistoryScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  i18n.locale = 'es';
  mockPetId = 'pet-1';
});
afterEach(() => act(() => tree.unmount()));

it('reads the first page with no cursor, and continues only from the server cursor', async () => {
  read.mockResolvedValueOnce(permitted([entry('e1'), entry('e2')], cursorAfter('e2')));
  await render();
  expect(read).toHaveBeenCalledTimes(1);
  expect(read).toHaveBeenLastCalledWith('pet-1');

  read.mockResolvedValueOnce(permitted([entry('e3')], null));
  await press(loadMore());

  expect(read).toHaveBeenCalledTimes(2);
  expect(read).toHaveBeenLastCalledWith('pet-1', cursorAfter('e2'));
  expect(allText()).toContain('Clínica e1');
  expect(allText()).toContain('Clínica e3');
  // A null cursor ends the history: no further Load more.
  expect(loadMore()).toBeUndefined();
});

it('a second Load more while one is in flight sends no second read', async () => {
  read.mockResolvedValueOnce(permitted([entry('e1')], cursorAfter('e1')));
  await render();

  const pending = deferred();
  read.mockReturnValueOnce(pending.promise);
  const control = loadMore();
  await act(async () => {
    control?.props.onPress();
    control?.props.onPress();
  });
  expect(read).toHaveBeenCalledTimes(2);

  await settle(pending.resolve, permitted([entry('e2')], null));
  expect(allText()).toContain('Clínica e2');
  expect(read).toHaveBeenCalledTimes(2);
});

it('an Entry already shown is never shown a second time', async () => {
  read.mockResolvedValueOnce(permitted([entry('e1'), entry('e2')], cursorAfter('e2')));
  await render();

  read.mockResolvedValueOnce(permitted([entry('e2', 'Clínica repetida'), entry('e3')], null));
  await press(loadMore());

  expect(allText().match(/Clínica e2/g)).toHaveLength(1);
  expect(allText()).not.toContain('Clínica repetida');
  expect(allText()).toContain('Clínica e3');
});

it('a failed Load more keeps what is shown and retries the same cursor', async () => {
  read.mockResolvedValueOnce(permitted([entry('e1')], cursorAfter('e1')));
  await render();

  read.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
  await press(loadMore());
  expect(allText()).toContain('Clínica e1');
  expect(allText()).toContain(t('clinicalHistory.loadError'));

  read.mockResolvedValueOnce(permitted([entry('e2')], null));
  await press(loadMore());
  expect(read).toHaveBeenLastCalledWith('pet-1', cursorAfter('e1'));
  expect(allText()).toContain('Clínica e2');
  expect(allText()).not.toContain(t('clinicalHistory.loadError'));
});

it('a failed first page shows the error state and no history', async () => {
  read.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
  await render();
  expect(allText()).toContain(t('clinicalHistory.title'));
  expect(loadMore()).toBeUndefined();
});

it('DENIED on the first page shows only the calm unavailable state', async () => {
  read.mockResolvedValueOnce(denied);
  await render();
  expect(allText()).toContain(t('clinicalHistory.denied'));
  expect(loadMore()).toBeUndefined();
});

it('DENIED on a later page drops every Entry already shown at once', async () => {
  read.mockResolvedValueOnce(permitted([entry('e1'), entry('e2')], cursorAfter('e2')));
  await render();
  expect(allText()).toContain('Clínica e1');

  read.mockResolvedValueOnce(denied);
  await press(loadMore());

  expect(allText()).toContain(t('clinicalHistory.denied'));
  expect(allText()).not.toContain('Clínica e1');
  expect(allText()).not.toContain('Clínica e2');
  expect(loadMore()).toBeUndefined();
});

it('ignores a late answer once the screen is gone', async () => {
  const first = deferred();
  read.mockReturnValueOnce(first.promise);
  await render();
  act(() => tree.unmount());

  await settle(first.resolve, permitted([entry('e1')], null));
  // Remounted only so afterEach has something to unmount.
  read.mockResolvedValueOnce(permitted([], null));
  await render();
  expect(allText()).not.toContain('Clínica e1');
});

it("never shows another Pet's late answer", async () => {
  const firstPet = deferred();
  read.mockReturnValueOnce(firstPet.promise);
  await render();

  mockPetId = 'pet-2';
  read.mockResolvedValueOnce(permitted([entry('p2')], null));
  await act(async () => tree.update(createElement(GuardianMedicalHistoryScreen)));
  expect(read).toHaveBeenLastCalledWith('pet-2');

  await settle(firstPet.resolve, permitted([entry('p1')], null));
  expect(allText()).toContain('Clínica p2');
  expect(allText()).not.toContain('Clínica p1');
});

it('ignores a late Load more answer of another Pet', async () => {
  read.mockResolvedValueOnce(permitted([entry('p1')], cursorAfter('p1')));
  await render();
  const pending = deferred();
  read.mockReturnValueOnce(pending.promise);
  const control = loadMore();
  await act(async () => {
    control?.props.onPress();
  });

  mockPetId = 'pet-2';
  read.mockResolvedValueOnce(permitted([entry('p2')], null));
  await act(async () => tree.update(createElement(GuardianMedicalHistoryScreen)));

  await settle(pending.resolve, permitted([entry('p1-late')], null));
  expect(allText()).toContain('Clínica p2');
  expect(allText()).not.toContain('Clínica p1-late');
});

it('opening an Attachment does not re-read the history and keeps every loaded page', async () => {
  const withAttachment: GuardianMedicalHistoryEntry = {
    ...entry('e1'),
    attachments: [
      {
        id: 'att-1',
        originalFilename: 'analitica.pdf',
        createdAt: '2026-01-15T08:20:00Z',
        trustedMediaType: 'application/pdf',
        trustedByteSize: 2048,
        validationCompletedAt: '2026-01-15T08:21:00Z',
      },
    ],
  };
  read.mockResolvedValueOnce(permitted([withAttachment], cursorAfter('e1')));
  await render();
  read.mockResolvedValueOnce(permitted([entry('e2')], cursorAfter('e2')));
  await press(loadMore());

  const card = tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.onPress === 'function' &&
      typeof node.props.accessibilityState?.expanded === 'boolean',
  )[0];
  await press(card);

  download.mockResolvedValueOnce({
    data: {
      status: 'PERMITTED',
      signedDownloadUrl: 'https://signed.example/att-1',
      originalFilename: 'analitica.pdf',
      expiresInSeconds: 60,
    },
    error: null,
  });
  await press(button(`${t('clinicalHistory.attachmentOpenAction')}: analitica.pdf`));

  expect(download).toHaveBeenCalledWith('att-1');
  expect(openBrowser).toHaveBeenCalledWith('https://signed.example/att-1');
  expect(read).toHaveBeenCalledTimes(2);
  expect(allText()).toContain('Clínica e1');
  expect(allText()).toContain('Clínica e2');
  expect(loadMore()).toBeDefined();
});

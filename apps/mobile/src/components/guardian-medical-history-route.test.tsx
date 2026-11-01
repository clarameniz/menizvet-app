import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import GuardianMedicalHistoryScreen from '@/app/pets/[id]/medical-history';
import {
  getGuardianPetMedicalHistory,
  type GuardianMedicalHistoryEntry,
} from '@/data/clinical-history';
import { i18n } from '@/i18n/i18n';
import { formatClinicalInstant } from '@/lib/clinical-history-display';

/**
 * What a Guardian sees of an edited Clinical Record Entry (SPEC-MED-010 BR-22,
 * stage M5), against a mocked data module: the current version only, the
 * original recording date, a discreet "Edited", and the earlier versions only
 * under "View changes".
 */

jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: 'pet-1' }),
  router: { back: jest.fn(), canGoBack: jest.fn(() => true), dismissTo: jest.fn() },
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
}));
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: jest.fn(), functions: { invoke: jest.fn() } },
}));

const read = getGuardianPetMedicalHistory as jest.Mock;

const entry = (
  overrides: Partial<GuardianMedicalHistoryEntry> = {},
): GuardianMedicalHistoryEntry => ({
  id: 'entry-1',
  clinicDisplayName: 'Clínica Norte',
  organizationDisplayName: 'Org X',
  clinicalContent: 'Solo se realizó un corte de uñas',
  category: 'CLINICAL_NOTE',
  otherCategoryContext: null,
  clinicalEventAt: null,
  historyOrderAt: '2026-01-15T08:10:00Z',
  finalizedAt: '2026-01-15T08:10:00Z',
  version: 2,
  editedAt: '2026-01-15T09:00:00Z',
  previousVersions: [
    {
      version: 1,
      category: 'VACCINATION',
      otherCategoryContext: null,
      clinicalContent: 'Vacuna de la rabia anual',
      createdAt: '2026-01-15T08:10:00Z',
    },
  ],
  previousVersionsTruncated: false,
  amendments: [],
  amendmentCount: 0,
  amendmentsTruncated: false,
  attachments: [],
  ...overrides,
});

let tree: ReactTestRenderer;
const t = (key: string, options?: Record<string, unknown>) => i18n.t(key, options);
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const allText = () => texts().join(' | ');
const pressables = (predicate: (node: ReactTestInstance) => boolean) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.onPress === 'function' &&
      predicate(node),
  );
async function press(node: ReactTestInstance | undefined) {
  if (node === undefined) throw new Error('No such control');
  await act(async () => node.props.onPress());
}
const card = () =>
  pressables((node) => typeof node.props.accessibilityState?.expanded === 'boolean')[0];
const viewChanges = () =>
  pressables((node) => node.props.accessibilityLabel === t('clinicalRecord.viewChanges'))[0];

async function render(entries: GuardianMedicalHistoryEntry[]) {
  read.mockResolvedValue({
    data: { status: 'PERMITTED', page: { entries, cursor: null } },
    error: null,
  });
  await act(async () => {
    tree = create(createElement(GuardianMedicalHistoryScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  i18n.locale = 'es';
});
afterEach(() => act(() => tree.unmount()));

it('an edited record shows only its current version, the original date and a discreet Edited', async () => {
  await render([entry()]);
  expect(allText()).toContain(t('clinicalHistory.categoryClinicalNote'));
  await press(card());
  expect(allText()).toContain('Solo se realizó un corte de uñas');
  expect(allText()).not.toContain('Vacuna de la rabia anual');
  expect(allText()).toContain(
    `${t('clinicalHistory.recordedAtLabel')}: ${formatClinicalInstant('2026-01-15T08:10:00Z', 'es')}`,
  );
  expect(allText()).toContain(
    t('clinicalRecord.editedAt', { time: formatClinicalInstant('2026-01-15T09:00:00Z', 'es') }),
  );
});

it('View changes shows the earlier version — what and when — and never who by internal identifier', async () => {
  await render([entry()]);
  await press(card());
  await press(viewChanges());
  expect(allText()).toContain(t('clinicalRecord.originalVersion'));
  expect(allText()).toContain(t('clinicalHistory.categoryVaccination'));
  expect(allText()).toContain('Vacuna de la rabia anual');
  expect(allText()).toContain(
    t('clinicalRecord.recordedOn', { time: formatClinicalInstant('2026-01-15T08:10:00Z', 'es') }),
  );
  expect(allText()).not.toMatch(/entry-1|user|vca/);
});

it('a record never edited offers no View changes and no Edited', async () => {
  await render([entry({ version: 1, editedAt: null, previousVersions: [] })]);
  await press(card());
  expect(viewChanges()).toBeUndefined();
  expect(allText()).not.toMatch(/Editado el/);
});

it('a historical correction stays readable under View changes', async () => {
  await render([
    entry({
      version: 1,
      editedAt: null,
      previousVersions: [],
      clinicalContent: 'Dosis 50 mg',
      amendments: [
        {
          id: 'am-1',
          reason: 'Dosis mal registrada',
          amendmentContent: 'La dosis correcta es 5 mg',
          createdAt: '2026-01-16T08:00:00Z',
        },
      ],
      amendmentCount: 1,
    }),
  ]);
  await press(card());
  expect(allText()).not.toContain('La dosis correcta es 5 mg');
  await press(viewChanges());
  expect(allText()).toContain(t('clinicalHistory.amendmentsHeading'));
  expect(allText()).toContain('La dosis correcta es 5 mg');
});

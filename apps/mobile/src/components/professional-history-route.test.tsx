import { createElement } from 'react';
import { AccessibilityInfo, Text } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import ProfessionalMedicalHistoryScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]/history';
import {
  viewAppointmentProfessionalMedicalHistory,
  type ProfessionalHistoryEntry,
  type ProfessionalHistoryRead,
} from '@/data/professional-medical-history';
import { i18n } from '@/i18n/i18n';
import { formatClinicalInstant } from '@/lib/clinical-history-display';

let mockParams: Record<string, string> = { clinicId: 'clinic-a', appointmentId: 'appt-1' };
let mockLocale = 'es';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => mockParams,
  useFocusEffect: () => {
    throw new Error('The history screen must not re-read on focus');
  },
  router: {
    push: jest.fn(),
    canGoBack: jest.fn(() => true),
    back: jest.fn(),
    dismissTo: jest.fn(),
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
  return {
    useLocale: () => ({
      locale: mockLocale,
      t: (key: string, options?: Record<string, unknown>) =>
        mockI18n.t(key, { ...options, locale: mockLocale }),
    }),
  };
});
jest.mock('@/data/professional-medical-history', () => ({
  ...jest.requireActual('@/data/professional-medical-history'),
  viewAppointmentProfessionalMedicalHistory: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const read = viewAppointmentProfessionalMedicalHistory as jest.Mock;

const entry = (overrides: Partial<ProfessionalHistoryEntry> = {}): ProfessionalHistoryEntry => ({
  entryId: 'entry-1',
  category: 'TREATMENT',
  otherCategoryContext: null,
  clinicalContent: 'Dose 50 mg',
  clinicalEventAt: null,
  historyOrderAt: '2025-03-01T09:00:00Z',
  finalizedAt: '2025-12-01T00:00:00Z',
  clinicDisplayName: 'Clínica Norte',
  organizationDisplayName: 'Org X',
  isThisAppointment: false,
  author: { displayName: 'Elena Vidal', isMe: false },
  version: 1,
  editedAt: null,
  previousVersions: [],
  previousVersionsTruncated: false,
  amendments: [],
  amendmentCount: 0,
  amendmentsTruncated: false,
  ...overrides,
});
const permitted = (
  entries: ProfessionalHistoryEntry[],
  cursor: { beforeHistoryOrderAt: string; beforeEntryId: string } | null = null,
): ProfessionalHistoryRead => ({ kind: 'permitted', page: { entries, cursor } });

const corrected = entry({
  entryId: 'entry-a',
  amendments: [
    {
      amendmentId: 'am-1',
      reason: 'Incorrect dose',
      amendmentContent: 'Correct dose is 5 mg',
      createdAt: '2025-12-05T00:00:00Z',
      author: { displayName: 'Carlos Ruiz', isMe: false },
    },
    {
      amendmentId: 'am-2',
      reason: 'Clarification',
      amendmentContent: 'Given with food',
      createdAt: '2025-12-06T00:00:00Z',
      author: { displayName: 'Elena Vidal', isMe: false },
    },
  ],
  amendmentCount: 2,
});
const otherOrg = entry({
  entryId: 'entry-c',
  category: 'PROCEDURE',
  clinicalContent: 'Surgery: spay',
  historyOrderAt: '2025-09-01T09:00:00Z',
  clinicDisplayName: 'VetCare Toledo',
  organizationDisplayName: 'Org Y',
  author: { displayName: null, isMe: false },
});
const mine = entry({
  entryId: 'entry-m',
  category: 'EXAMINATION',
  clinicalContent: 'Current visit exam',
  historyOrderAt: '2026-06-01T10:10:00Z',
  isThisAppointment: true,
  author: { displayName: 'Ana García', isMe: true },
});

let tree: ReactTestRenderer;
const t = (key: string, options?: Record<string, unknown>) =>
  i18n.t(key, { ...options, locale: mockLocale });
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const allText = () => texts().join(' | ');
const cards = () =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.accessibilityState?.expanded === 'boolean' &&
      typeof node.props.onPress === 'function',
  );
const findButton = (label: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityLabel === label &&
      typeof node.props.onPress === 'function',
  )[0];
async function render() {
  await act(async () => {
    tree = create(createElement(ProfessionalMedicalHistoryScreen));
  });
}
async function press(node: ReactTestInstance) {
  await act(async () => {
    node.props.onPress();
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  read.mockReset();
  mockParams = { clinicId: 'clinic-a', appointmentId: 'appt-1' };
  mockLocale = 'es';
});
afterEach(() => act(() => tree.unmount()));

it('reads once on arrival, keyed only by the route Clinic and Appointment, and never on focus', async () => {
  read.mockResolvedValue(permitted([corrected]));
  await render();
  expect(read).toHaveBeenCalledTimes(1);
  expect(read).toHaveBeenCalledWith('clinic-a', 'appt-1');
  await act(async () => {
    tree.update(createElement(ProfessionalMedicalHistoryScreen));
  });
  expect(read).toHaveBeenCalledTimes(1);
});

it('an authorized empty history is a calm empty state', async () => {
  read.mockResolvedValue(permitted([]));
  await render();
  expect(texts()).toContain(t('professionalHistory.empty'));
  expect(texts()).toContain('Todavía no hay registros clínicos anteriores para esta mascota.');
});

it('shows a flat timeline across Clinics and Organizations with meaningful provenance', async () => {
  read.mockResolvedValue(permitted([mine, otherOrg, corrected]));
  await render();
  const shown = allText();
  expect(shown).toContain('Clínica Norte · Org X');
  expect(shown).toContain('VetCare Toledo · Org Y');
  expect(shown).toContain('Elena Vidal');
  expect(shown).toContain(`Ana García ${t('professionalHistory.youSuffix')}`);
  expect(shown).toContain(t('professionalHistory.veterinarianFallback'));
  expect(shown).toContain(t('professionalHistory.thisAppointment'));
  expect(shown).toContain('2 correcciones');
  expect(shown).not.toMatch(/\bDra?\.\s/);
  expect(shown).not.toMatch(/Añadir corrección|Add amendment/);
  expect(shown).not.toContain('Dose 50 mg');
  expect(cards()).toHaveLength(3);
});

it('reads a collapsed card date and category first, then provider, Veterinarian and corrections', async () => {
  read.mockResolvedValue(permitted([corrected]));
  await render();
  const label = String(cards()[0].props.accessibilityLabel);
  const order = [
    t('clinicalHistory.categoryTreatment'),
    'Clínica Norte · Org X',
    'Elena Vidal',
    '2 correcciones',
  ].map((part) => label.indexOf(part));
  expect(order.every((index) => index >= 0)).toBe(true);
  expect([...order].sort((a, b) => a - b)).toEqual(order);
  expect(label).not.toMatch(/entry-a|am-1/);
});

it('expanded, the record stays first and its earlier corrections follow under View changes, oldest first with their own author', async () => {
  const long = 'Línea clínica. '.repeat(120).trim();
  read.mockResolvedValue(permitted([{ ...corrected, clinicalContent: long }]));
  await render();
  await press(cards()[0]);
  expect(allText()).not.toContain('Correct dose is 5 mg');
  await press(findButton(t('clinicalRecord.viewChanges')));
  const shown = texts();
  const original = shown.indexOf(long);
  const first = shown.indexOf('Correct dose is 5 mg');
  const second = shown.indexOf('Given with food');
  expect(original).toBeGreaterThanOrEqual(0);
  expect(first).toBeGreaterThan(original);
  expect(second).toBeGreaterThan(first);
  expect(shown).toContain(
    t('professionalHistory.recordedAt', {
      time: formatClinicalInstant('2025-12-01T00:00:00Z', 'es'),
    }),
  );
  expect(shown).toContain(t('professionalHistory.correctionLabel', { index: 1, total: 2 }));
  expect(shown).toContain(t('professionalHistory.correctionReason', { reason: 'Incorrect dose' }));
  expect(allText()).toContain(t('professionalHistory.correctionBy', { name: 'Carlos Ruiz' }));
  expect(allText()).toContain(t('professionalHistory.correctionBy', { name: 'Elena Vidal' }));
});

it('an edited record shows its current version, a discreet Edited and, under View changes, the original by its author', async () => {
  read.mockResolvedValue(
    permitted([
      entry({
        category: 'CLINICAL_NOTE',
        clinicalContent: 'Solo se realizó un corte de uñas',
        version: 2,
        editedAt: '2025-12-02T10:00:00Z',
        previousVersions: [
          {
            version: 1,
            category: 'VACCINATION',
            otherCategoryContext: null,
            clinicalContent: 'Vacuna de la rabia anual',
            createdAt: '2025-12-01T00:00:00Z',
          },
        ],
      }),
    ]),
  );
  await render();
  const editedLabel = t('clinicalRecord.editedAt', {
    time: formatClinicalInstant('2025-12-02T10:00:00Z', 'es'),
  });
  expect(allText()).toContain(editedLabel);
  await press(cards()[0]);
  expect(allText()).toContain('Solo se realizó un corte de uñas');
  expect(allText()).not.toContain('Vacuna de la rabia anual');
  await press(findButton(t('clinicalRecord.viewChanges')));
  expect(allText()).toContain(t('clinicalRecord.originalVersion'));
  expect(allText()).toContain('Vacuna de la rabia anual');
  expect(allText()).toContain(t('clinicalHistory.categoryVaccination'));
  expect(allText()).toContain(
    `${t('clinicalRecord.recordedOn', { time: formatClinicalInstant('2025-12-01T00:00:00Z', 'es') })} · Elena Vidal`,
  );
});

it('a record never edited offers no View changes', async () => {
  read.mockResolvedValue(permitted([mine]));
  await render();
  await press(cards()[0]);
  expect(findButton(t('clinicalRecord.viewChanges'))).toBeUndefined();
});

it('load more appends the next page with its cursor and announces it', async () => {
  const announce = jest.spyOn(AccessibilityInfo, 'announceForAccessibility');
  const cursor = { beforeHistoryOrderAt: '2026-06-01T10:10:00Z', beforeEntryId: 'entry-m' };
  read.mockResolvedValueOnce(permitted([mine], cursor));
  await render();
  read.mockResolvedValueOnce(permitted([otherOrg, corrected]));
  await press(findButton(t('professionalHistory.loadMore')));
  expect(read).toHaveBeenLastCalledWith('clinic-a', 'appt-1', cursor);
  expect(cards()).toHaveLength(3);
  expect(findButton(t('professionalHistory.loadMore'))).toBeUndefined();
  expect(announce).toHaveBeenCalledWith(t('professionalHistory.loadedMore'));
});

it('access revoked while paging drops every clinical content for the calm unavailable state', async () => {
  read.mockResolvedValueOnce(
    permitted([mine], { beforeHistoryOrderAt: '2026-06-01T10:10:00Z', beforeEntryId: 'entry-m' }),
  );
  await render();
  expect(allText()).toContain('Ana García');
  read.mockResolvedValueOnce({ kind: 'denied' });
  await press(findButton(t('professionalHistory.loadMore')));
  expect(cards()).toHaveLength(0);
  expect(allText()).not.toMatch(/Ana García|Clínica Norte|corrección/);
  expect(texts()).toContain(t('professionalHistory.unavailable'));
});

it('a denial (revocation, closed window or Subscription lapse) reveals nothing about the history', async () => {
  read.mockResolvedValue({ kind: 'denied' });
  await render();
  expect(texts()).toContain(t('professionalHistory.unavailable'));
  expect(cards()).toHaveLength(0);
  expect(allText()).not.toMatch(/\d+ correcci|Clínica|Veterinario/);
  expect(findButton(t('professionalHistory.retry'))).toBeUndefined();
});

it('a failure offers Retry, which reads again', async () => {
  read.mockResolvedValueOnce({ kind: 'failed' });
  await render();
  expect(texts()).toContain(t('professionalHistory.loadError'));
  read.mockResolvedValueOnce(permitted([corrected]));
  await press(findButton(t('professionalHistory.retry')));
  expect(read).toHaveBeenCalledTimes(2);
  expect(cards()).toHaveLength(1);
});

it('a lost session asks to sign in again', async () => {
  read.mockResolvedValue({ kind: 'authenticationRequired' });
  await render();
  expect(texts()).toContain(t('errors.sessionExpired'));
});

it('switching Clinic A to Clinic B discards A and the latest request wins', async () => {
  let resolveA: (value: ProfessionalHistoryRead) => void = () => undefined;
  read.mockImplementationOnce(
    () =>
      new Promise<ProfessionalHistoryRead>((resolve) => {
        resolveA = resolve;
      }),
  );
  await render();
  read.mockResolvedValueOnce(permitted([otherOrg]));
  mockParams = { clinicId: 'clinic-b', appointmentId: 'appt-9' };
  await act(async () => {
    tree.update(createElement(ProfessionalMedicalHistoryScreen));
  });
  expect(read).toHaveBeenLastCalledWith('clinic-b', 'appt-9');
  await act(async () => {
    resolveA(permitted([mine]));
  });
  expect(allText()).toContain('VetCare Toledo');
  expect(allText()).not.toContain('Ana García');
});

it('renders in English with the neutral English fallback', async () => {
  mockLocale = 'en';
  read.mockResolvedValue(permitted([otherOrg, corrected]));
  await render();
  expect(allText()).toContain('Medical history');
  expect(allText()).toContain('Veterinarian');
  expect(allText()).toContain('2 corrections');
});

import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import ClinicDetailScreen from '@/app/clinics/[id]';
import {
  CLINIC_SERVICE_CATEGORIES,
  getPublishedClinicDetail,
  type ClinicDetail,
  type ClinicServiceOffering,
} from '@/data/clinics';
import { i18n } from '@/i18n/i18n';

/**
 * Public Clinic detail — Services section (SPEC-CLI-005 BR-5/BR-6/BR-35):
 * each category shows its localized label, never the raw backend code; the
 * Clinic's public description is shown exactly as published.
 */

let mockLocale = 'es';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: 'clinic-1' }),
  router: { push: jest.fn(), replace: jest.fn() },
}));
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
  return {
    useLocale: () => ({
      locale: mockLocale,
      t: (key: string, options?: Record<string, unknown>) =>
        mockI18n.t(key, { ...options, locale: mockLocale }),
    }),
  };
});
jest.mock('@/data/clinics', () => ({
  ...jest.requireActual('@/data/clinics'),
  getPublishedClinicDetail: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const read = getPublishedClinicDetail as jest.Mock;

const detail = (serviceOfferings: ClinicServiceOffering[]): ClinicDetail => ({
  profile: {
    clinicId: 'clinic-1',
    displayName: 'Clínica Norte',
    description: null,
    publicPhone: null,
    publicEmail: null,
    website: null,
  },
  location: null,
  serviceOfferings,
  openingHours: null,
});

let tree: ReactTestRenderer;
const t = (key: string) => i18n.t(key, { locale: mockLocale });
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));

async function render(serviceOfferings: ClinicServiceOffering[]) {
  read.mockResolvedValueOnce({ data: detail(serviceOfferings), error: null });
  await act(async () => {
    tree = create(createElement(ClinicDetailScreen));
  });
}

const allCategories = (): ClinicServiceOffering[] =>
  CLINIC_SERVICE_CATEGORIES.map((serviceCategory) => ({
    serviceCategory,
    publicDescription: serviceCategory === 'OTHER' ? 'Peluquería y baño para perros y gatos' : null,
  }));

beforeEach(() => {
  read.mockReset();
  mockLocale = 'es';
});
afterEach(() => {
  act(() => tree.unmount());
});

it.each(['es', 'en'])(
  'shows every service category localized in %s, never its raw code',
  async (locale) => {
    mockLocale = locale;
    await render(allCategories());

    expect(texts()).toContain(t('discoveryDetail.servicesTitle'));
    expect(texts()).toEqual(
      expect.arrayContaining([
        t('clinicServices.categoryGeneralConsultation'),
        t('clinicServices.categoryVaccination'),
        t('clinicServices.categorySurgery'),
        t('clinicServices.categoryDentistry'),
        t('clinicServices.categoryDiagnosticImaging'),
        t('clinicServices.categoryLaboratory'),
        t('clinicServices.categoryEmergencyCare'),
        t('clinicServices.categoryHospitalization'),
        t('clinicServices.categoryOther'),
      ]),
    );
    for (const category of CLINIC_SERVICE_CATEGORIES) {
      expect(texts()).not.toContain(category);
    }
  },
);

it('shows English labels in English', async () => {
  mockLocale = 'en';
  await render([
    { serviceCategory: 'GENERAL_CONSULTATION', publicDescription: null },
    { serviceCategory: 'DIAGNOSTIC_IMAGING', publicDescription: null },
  ]);
  expect(texts()).toEqual(expect.arrayContaining(['General consultation', 'Diagnostic imaging']));
});

it('keeps OTHER with its public description exactly as published, untranslated', async () => {
  mockLocale = 'en';
  await render([
    { serviceCategory: 'OTHER', publicDescription: 'Peluquería y baño para perros y gatos' },
  ]);
  const shown = texts();
  const label = shown.indexOf('Other services');
  expect(label).toBeGreaterThanOrEqual(0);
  expect(shown[label + 1]).toBe('Peluquería y baño para perros y gatos');
});

it('renders no description element for a null description', async () => {
  await render([{ serviceCategory: 'VACCINATION', publicDescription: null }]);
  const shown = texts();
  const label = shown.indexOf('Vacunación');
  expect(label).toBeGreaterThanOrEqual(0);
  const item = tree.root.findAllByType(Text)[label].parent;
  expect(item?.findAllByType(Text)).toHaveLength(1);
  expect(shown).not.toContain('');
  expect(shown).not.toContain('null');
});

it('shows an unknown runtime category as the generic localized service label', async () => {
  await render([{ serviceCategory: 'GROOMING', publicDescription: 'Baño y corte' }]);
  expect(texts()).toContain('Servicio veterinario');
  expect(texts()).toContain('Baño y corte');
  expect(texts()).not.toContain('GROOMING');
});

it('keeps the empty-services note when the Clinic publishes no services', async () => {
  await render([]);
  expect(texts()).toContain(t('discoveryDetail.noServices'));
});

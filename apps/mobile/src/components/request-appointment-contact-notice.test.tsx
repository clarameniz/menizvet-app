import { createElement } from 'react';
import { Text, TextInput } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import RequestAppointmentScreen from '@/app/clinics/[id]/request-appointment';
import { getRequestableAppointmentStartTimes } from '@/data/appointments';
import { getPublishedClinicOpeningHours, getPublishedClinicProfilesByIds } from '@/data/clinics';
import { getMyPets } from '@/data/pets';
import { i18n } from '@/i18n/i18n';

/**
 * SPEC-APT-001 BR-37: before submitting, the Guardian is told that the Clinic
 * will be able to see their name and email to manage the Appointment —
 * information only: no new input, checkbox, or confirmation.
 */

let mockLocale = 'es';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: 'clinic-1' }),
  router: { push: jest.fn(), back: jest.fn(), canGoBack: jest.fn(() => true), replace: jest.fn() },
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
jest.mock('@/lib/session-provider', () => {
  // One stable session, as the provider gives: the screen's load effect depends on it.
  const mockSessionState = {
    session: { user: { id: 'auth-1' } },
    isLoading: false,
    isPasswordRecovery: false,
  };
  return { useSession: () => mockSessionState };
});
jest.mock('@/data/clinics', () => ({
  ...jest.requireActual('@/data/clinics'),
  getPublishedClinicProfilesByIds: jest.fn(),
  getPublishedClinicOpeningHours: jest.fn(),
}));
jest.mock('@/data/pets', () => ({
  ...jest.requireActual('@/data/pets'),
  getMyPets: jest.fn(),
}));
jest.mock('@/data/appointments', () => ({
  ...jest.requireActual('@/data/appointments'),
  getRequestableAppointmentStartTimes: jest.fn(),
  requestAppointment: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

let tree: ReactTestRenderer;
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));

async function render() {
  await act(async () => {
    tree = create(createElement(RequestAppointmentScreen));
  });
}

beforeEach(() => {
  mockLocale = 'es';
  (getPublishedClinicProfilesByIds as jest.Mock).mockResolvedValue({
    data: new Map([
      [
        'clinic-1',
        {
          clinicId: 'clinic-1',
          displayName: 'Clínica Norte',
          description: null,
          publicPhone: null,
          publicEmail: null,
          website: null,
        },
      ],
    ]),
    error: null,
  });
  (getPublishedClinicOpeningHours as jest.Mock).mockResolvedValue({
    data: { schedulingTimezoneName: 'Europe/Madrid', recurringPeriods: [], exceptions: [] },
    error: null,
  });
  (getMyPets as jest.Mock).mockResolvedValue({
    data: [
      {
        id: 'pet-1',
        name: 'Luna',
        species: 'Dog',
        breed: null,
        sex: null,
        dateOfBirth: null,
        approximateDateOfBirth: null,
        microchipIdentifier: null,
        profileImageReference: null,
        behavioralSafetyInformation: null,
        profileRevision: 1,
        createdAt: '2026-01-01T00:00:00Z',
      },
    ],
    error: null,
  });
  (getRequestableAppointmentStartTimes as jest.Mock).mockResolvedValue({ data: [], error: null });
});
afterEach(() => act(() => tree.unmount()));

it('tells the Guardian, before submitting, that the Clinic will see their name and email', async () => {
  await render();
  const shown = texts();
  expect(shown).toContain(
    'La clínica podrá ver tu nombre y tu correo electrónico para gestionar esta cita.',
  );
  // Before the submit action, and information only: no additional input.
  expect(shown.indexOf(i18n.t('appointmentRequest.contactNotice', { locale: 'es' }))).toBeLessThan(
    shown.lastIndexOf(i18n.t('appointmentRequest.submitAction', { locale: 'es' })),
  );
  expect(tree.root.findAllByType(TextInput)).toHaveLength(2);
});

it('is localized in English', async () => {
  mockLocale = 'en';
  await render();
  expect(texts()).toContain(
    'The clinic will be able to see your name and email address to manage this appointment.',
  );
});

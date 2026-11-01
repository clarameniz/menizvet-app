import { createElement } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import ProfessionalAppointmentDetailScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]';
import { AppointmentRequesterContactRow } from '@/components/appointment-requester-contact-row';
import {
  getClinicAppointmentRequesterContact,
  type AppointmentRequesterContactResult,
} from '@/data/appointment-requester-contact';
import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import { openExternalUrl } from '@/lib/external-link';

/**
 * Appointment contact on the professional Appointment detail (SPEC-APT-012
 * BR-50): the requester's name and verified email from the single-Appointment
 * read, a mailto action only with a plain address, a neutral note without one,
 * and a failure of that read that leaves the rest of the detail usable.
 */

let mockLocale = 'es';
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ clinicId: 'clinic-a', appointmentId: 'appt-1' }),
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => callback(), [callback]);
  },
  useNavigation: () => ({ dispatch: jest.fn() }),
  router: {
    push: jest.fn(),
    back: jest.fn(),
    canGoBack: jest.fn(() => true),
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
jest.mock('@/data/professional-clinics', () => ({
  ...jest.requireActual('@/data/professional-clinics'),
  getMyProfessionalClinics: jest.fn(),
}));
jest.mock('@/data/professional-context', () => ({
  ...jest.requireActual('@/data/professional-context'),
  getMyProfessionalContext: jest.fn(),
}));
jest.mock('@/data/clinic-appointment-schedule', () => ({
  ...jest.requireActual('@/data/clinic-appointment-schedule'),
  getClinicAppointment: jest.fn(),
}));
jest.mock('@/data/appointment-requester-contact', () => ({
  ...jest.requireActual('@/data/appointment-requester-contact'),
  getClinicAppointmentRequesterContact: jest.fn(),
}));
jest.mock('@/lib/external-link', () => ({
  ...jest.requireActual('@/lib/external-link'),
  openExternalUrl: jest.fn(async () => true),
}));
jest.mock('expo-router/react-navigation', () => ({ usePreventRemove: jest.fn() }));
// The detail's other sections answer calmly; this suite is about the contact only.
jest.mock('@/data/appointment-veterinarian-assignment', () => ({
  ...jest.requireActual('@/data/appointment-veterinarian-assignment'),
  getAppointmentVeterinarianAssignment: jest.fn(async () => ({
    kind: 'loaded',
    assignment: { kind: 'unassigned', mayAssignMe: false, mayManage: false },
  })),
}));
jest.mock('@/data/appointment-clinical-record', () => ({
  ...jest.requireActual('@/data/appointment-clinical-record'),
  viewAppointmentClinicalRecord: jest.fn(async () => ({ kind: 'denied' })),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const clinicsRead = getMyProfessionalClinics as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;

/** The context read (SPEC-ORG-007) for one Organization, with its APPOINTMENT_MANAGEMENT. */
function professionalContext(appointmentManagement: boolean, organizationId = 'org-1') {
  return {
    data: {
      hasVeterinarianProfessionalProfile: false,
      organizations: [
        {
          membershipId: 'membership-1',
          organizationId,
          organizationDisplayName: 'Animalia Group',
          responsibilities: [],
          capabilities: [],
          unknownCapabilities: [],
          clinicAssignments: [],
          entitlements: {
            APPOINTMENT_MANAGEMENT: appointmentManagement,
            PROFESSIONAL_SCHEDULING: true,
            CLINICAL_CARE: true,
            CLINICAL_DOCUMENTATION: true,
          },
        },
      ],
    },
    error: null,
  };
}
// The Clinic's Appointments, as fixtures. The screens read only one Appointment,
// through getClinicAppointment, answered here from these fixtures with the
// backend's semantics (SPEC-APT-012 BR-52: an unknown, foreign or denied
// Appointment is `null`). The full schedule read must never be called.
const scheduleRead = jest.fn();
const fullScheduleRead = () =>
  (jest.requireMock('@/lib/supabase').supabase.rpc as jest.Mock).mock.calls.filter(
    ([name]) => name === 'get_clinic_appointment_schedule',
  );
const appointmentRead = getClinicAppointment as jest.Mock;
beforeEach(() => {
  appointmentRead.mockImplementation(async (clinicId: string, appointmentId: string) => {
    const result = await scheduleRead(clinicId);
    if (result.error === CLINIC_SCHEDULE_ACCESS_DENIED) return { data: null, error: null };
    if (result.error !== null) return result;
    const rows: { id: string }[] = result.data;
    return { data: rows.find((entry) => entry.id === appointmentId) ?? null, error: null };
  });
});
afterEach(() => expect(fullScheduleRead()).toEqual([]));
const contactRead = getClinicAppointmentRequesterContact as jest.Mock;
const openUrl = openExternalUrl as jest.Mock;

const row = (overrides: Partial<ClinicScheduleAppointment> = {}): ClinicScheduleAppointment => ({
  id: 'appt-1',
  petId: 'pet-1',
  petName: 'Luna',
  requestingUserId: 'user-1',
  requesterDisplayName: 'María López',
  reasonForVisit: 'Revisión',
  guardianNotes: null,
  lifecycleState: 'CONFIRMED',
  createdAt: '2026-01-01T00:00:00Z',
  currentScheduledStartAt: '2035-06-01T08:00:00Z',
  currentScheduledEndAt: '2035-06-01T08:30:00Z',
  currentSchedulingTimezoneName: 'Europe/Madrid',
  currentScheduleRevisionSequence: 2,
  currentVeterinarianClinicAssignmentId: null,
  pendingReschedule: null,
  currentScheduleSource: null,
  cancellationReason: null,
  hasClinicalRecord: false,
  ...overrides,
});
const contact = (
  displayName: string | null,
  email: string | null,
): AppointmentRequesterContactResult => ({ kind: 'contact', contact: { displayName, email } });

let tree: ReactTestRenderer;
const t = (key: string, options?: Record<string, string>) =>
  i18n.t(key, { ...options, locale: mockLocale });
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const buttons = () =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
  );
const labels = () => [...new Set(buttons().map((node) => String(node.props.accessibilityLabel)))];
const press = async (label: string) => {
  const target = buttons().find((node) => node.props.accessibilityLabel === label);
  if (!target) throw new Error(`No button ${label}`);
  await act(async () => {
    target.props.onPress();
  });
};
async function render(appointment = row()) {
  scheduleRead.mockResolvedValue({ data: [appointment], error: null });
  await act(async () => {
    tree = create(createElement(ProfessionalAppointmentDetailScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  mockLocale = 'es';
  contextRead.mockResolvedValue(professionalContext(true));
  clinicsRead.mockResolvedValue({
    data: {
      clinics: [
        {
          clinicId: 'clinic-a',
          clinicDisplayName: 'Animalia',
          organizationId: 'org-1',
          organizationDisplayName: 'Animalia Group',
          capabilities: [
            'APPOINTMENT_VIEW_SCHEDULE',
            'APPOINTMENT_CANCEL',
            'APPOINTMENT_RESCHEDULE',
          ],
          unknownCapabilities: [],
        },
      ],
    },
    error: null,
  });
  contactRead.mockResolvedValue(contact('María López', 'maria@example.test'));
});
afterEach(() => act(() => tree.unmount()));

it('shows the requester name and email with an email action that opens exactly that address', async () => {
  await render();
  expect(contactRead).toHaveBeenCalledWith('clinic-a', 'appt-1');
  expect(texts()).toEqual(
    expect.arrayContaining([t('appointmentContact.heading'), 'María López', 'maria@example.test']),
  );
  const emailLabel = t('appointmentContact.emailActionAccessibility', { name: 'María López' });
  expect(labels()).toContain(emailLabel);
  await press(emailLabel);
  expect(openUrl).toHaveBeenCalledTimes(1);
  expect(openUrl).toHaveBeenCalledWith('mailto:maria@example.test');
});

it('is the last row of the summary card, once, with no card of its own', async () => {
  await render();
  const contactRow = tree.root.findByType(AppointmentRequesterContactRow);
  // Same card as the date and reason.
  const summary = contactRow.parent!.findAllByType(Text).map((node) => String(node.props.children));
  expect(summary).toEqual(
    expect.arrayContaining([
      t('professionalAppointment.dateTimeLabel'),
      t('professionalAppointment.reasonLabel'),
      t('appointmentContact.heading'),
    ]),
  );
  // The contact closes the card: its label, then the name and the email.
  const heading = summary.indexOf(t('appointmentContact.heading'));
  expect(summary.slice(heading, heading + 3)).toEqual([
    t('appointmentContact.heading'),
    'María López',
    'maria@example.test',
  ]);
  expect(texts().filter((text) => text === t('appointmentContact.heading'))).toHaveLength(1);
  expect(texts().filter((text) => text === 'maria@example.test')).toHaveLength(1);
});

it('names the real requester, not the schedule row, once the read answers', async () => {
  contactRead.mockResolvedValue(contact('Pedro Ruiz', 'pedro@example.test'));
  await render(row({ requesterDisplayName: 'María López' }));
  expect(texts()).toContain('Pedro Ruiz');
  expect(labels()).toContain(
    t('appointmentContact.emailActionAccessibility', { name: 'Pedro Ruiz' }),
  );
});

it('a long name and address are shown whole, for the row to wrap', async () => {
  const longName = 'María de los Ángeles Fernández-Villaverde de la Concepción';
  const longEmail = `${'a'.repeat(48)}.requester@very-long-subdomain.example-clinic.test`;
  contactRead.mockResolvedValue(contact(longName, longEmail));
  await render();
  expect(texts()).toEqual(expect.arrayContaining([longName, longEmail]));
  const style = (value: string) =>
    tree.root.findAllByType(Text).find((node) => node.props.children === value)!.props
      .numberOfLines;
  expect(style(longName)).toBeUndefined();
  expect(style(longEmail)).toBeUndefined();
});

it('shows a neutral note and no email action without an email', async () => {
  contactRead.mockResolvedValue(contact('María López', null));
  await render();
  expect(texts()).toContain(t('appointmentContact.noEmail'));
  expect(labels().some((label) => label.startsWith('Enviar un correo'))).toBe(false);
});

it('uses neutral fallbacks without a name, on the detail', async () => {
  contactRead.mockResolvedValue(contact(null, null));
  await render(row({ requesterDisplayName: null }));
  expect(texts()).toContain(t('appointmentContact.unnamed'));
  expect(texts()).toContain(t('appointmentContact.noEmail'));
});

it('offers no action for an address that is not a plain one', async () => {
  contactRead.mockResolvedValue(contact('María López', 'maria@example.test?bcc=evil@example.test'));
  await render();
  expect(labels().some((label) => label.startsWith('Enviar un correo'))).toBe(false);
  expect(openUrl).not.toHaveBeenCalled();
});

it('reports calmly when the email app cannot be opened', async () => {
  openUrl.mockResolvedValueOnce(false);
  await render();
  await press(t('appointmentContact.emailActionAccessibility', { name: 'María López' }));
  expect(texts()).toContain(t('appointmentContact.emailOpenFailed'));
});

it('keeps the rest of the detail usable when the contact read fails, and retries on request', async () => {
  contactRead.mockResolvedValue({ kind: 'unavailable' });
  await render();
  expect(texts()).toEqual(
    expect.arrayContaining(['Luna', 'Revisión', 'María López', t('appointmentContact.loadError')]),
  );
  expect(labels()).toEqual(
    expect.arrayContaining([t('professionalCancellation.action'), t('appointmentContact.retry')]),
  );
  contactRead.mockResolvedValue(contact('María López', 'maria@example.test'));
  await press(t('appointmentContact.retry'));
  expect(contactRead).toHaveBeenCalledTimes(2);
  expect(texts()).toContain('maria@example.test');
});

it('shows the contact as not available, without retry, when the read is denied', async () => {
  contactRead.mockResolvedValue({ kind: 'accessDenied' });
  await render();
  expect(texts()).toContain(t('appointmentContact.notAvailable'));
  expect(labels()).not.toContain(t('appointmentContact.retry'));
  expect(texts()).toContain('Revisión');
});

it('shows the contact in every lifecycle state, terminal included', async () => {
  for (const lifecycleState of [
    'REQUESTED',
    'COMPLETED',
    'CANCELLED',
    'NO_SHOW',
    'EXPIRED',
  ] as const) {
    await render(row({ lifecycleState }));
    expect(texts()).toContain('maria@example.test');
    act(() => tree.unmount());
  }
  await render();
});

it('never renders an internal identifier', async () => {
  await render();
  const shown = texts().join(' ');
  expect(shown).not.toContain('user-1');
  expect(shown).not.toContain('appt-1');
  expect(shown).not.toContain('clinic-a');
});

it('is localized in English', async () => {
  mockLocale = 'en';
  contactRead.mockResolvedValue(contact('María López', null));
  await render();
  expect(texts()).toEqual(
    expect.arrayContaining(['Appointment contact', 'María López', 'Email not available']),
  );
  expect(texts()).toContain('Appointment management');
});

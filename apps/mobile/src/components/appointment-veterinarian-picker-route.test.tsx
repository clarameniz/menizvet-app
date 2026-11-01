import { createElement } from 'react';
import { Alert, Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import ProfessionalAppointmentDetailScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]';
import {
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';

/**
 * Regression: the Veterinarian picker of the professional Appointment detail,
 * opened by an actor who manages the assignment without being a Veterinarian
 * (Owner, Administrator, Receptionist). Each option must show the candidate's
 * name as `get_appointment_veterinarian_candidates` returns it (SPEC-APT-007
 * BR-38), so that several candidates can be told apart; the neutral
 * "Veterinario" is only for a candidate the read returns without a name.
 *
 * Unlike the journey suite, the assignment and candidate reads are NOT mocked
 * at the data module: the raw RPC payloads go through the real parser, so the
 * whole client path — RPC JSON, parsing, picker state, option label — is
 * covered.
 */

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
jest.mock('expo-router/react-navigation', () => ({ usePreventRemove: jest.fn() }));
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
  getClinicAppointmentRequesterContact: jest.fn(() => new Promise(() => {})),
}));
jest.mock('@/data/appointment-clinical-record', () => ({
  ...jest.requireActual('@/data/appointment-clinical-record'),
  viewAppointmentClinicalRecord: jest.fn(async () => ({ kind: 'denied' })),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const rpc = () => jest.requireMock('@/lib/supabase').supabase.rpc as jest.Mock;
const clinicsRead = getMyProfessionalClinics as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;
const appointmentRead = getClinicAppointment as jest.Mock;

// What each non-veterinarian responsibility yields at the Clinic (the server
// derives capabilities; the client never sees roles).
const OWNER_OR_ADMINISTRATOR = [
  'APPOINTMENT_VIEW_SCHEDULE',
  'APPOINTMENT_CONFIRM',
  'APPOINTMENT_CANCEL',
  'APPOINTMENT_COMPLETE',
  'APPOINTMENT_MARK_NO_SHOW',
  'APPOINTMENT_RESCHEDULE',
  'APPOINTMENT_ASSIGN_VETERINARIAN',
];
const RECEPTIONIST = OWNER_OR_ADMINISTRATOR.filter(
  (capability) => capability !== 'APPOINTMENT_COMPLETE',
);

const VCA = {
  ana: '11111111-1111-4111-8111-111111111111',
  luis: '22222222-2222-4222-8222-222222222222',
  marta: '33333333-3333-4333-8333-333333333333',
  unnamed: '44444444-4444-4444-8444-444444444444',
};
const TOKEN = '55555555-5555-4555-8555-555555555555';

type RawCandidate = {
  veterinarian_clinic_assignment_id: string;
  display_name: string | null;
  is_me: boolean;
  is_current_assignee: boolean;
};
const candidate = (id: string, displayName: string | null, extra: Partial<RawCandidate> = {}) => ({
  veterinarian_clinic_assignment_id: id,
  display_name: displayName,
  is_me: false,
  is_current_assignee: false,
  ...extra,
});

/** The raw RPC answers of the backend contract (SPEC-APT-007 BR-37, BR-38). */
function backend(assignment: Record<string, unknown>, candidates: RawCandidate[]) {
  rpc().mockImplementation(async (name: string) => {
    if (name === 'get_appointment_veterinarian_assignment')
      return { data: assignment, error: null };
    if (name === 'get_appointment_veterinarian_candidates')
      return { data: { status: 'PERMITTED', candidates, history: [] }, error: null };
    return { data: null, error: { code: 'XX000' } };
  });
}
const UNASSIGNED = { status: 'UNASSIGNED', may_assign_me: false, may_manage: true };
const assignedTo = (displayName: string | null) => ({
  status: 'ASSIGNED',
  display_name: displayName,
  is_me: false,
  is_eligible: true,
  assignment_token: TOKEN,
  may_assign_me: false,
  may_manage: true,
});

const row: ClinicScheduleAppointment = {
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
};

let tree: ReactTestRenderer;
const t = (key: string, options?: Record<string, unknown>) => i18n.t(key, options);
const FALLBACK = () => t('veterinarianAssignment.fallbackName');
// The row's own label is also "Veterinario" in Spanish, so the fallback is
// checked on the options themselves.
const FALLBACK_OPTION = () =>
  t('veterinarianAssignment.candidateAccessibility', { name: FALLBACK() });
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const pressables = () =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
  );
async function press(label: string) {
  const node = pressables().find((candidate) => candidate.props.accessibilityLabel === label);
  if (node === undefined) throw new Error(`No control labelled ${label}`);
  await act(async () => {
    node.props.onPress();
  });
}
/** The options of the open picker, as the reader sees and hears them. */
const options = () =>
  pressables()
    .map((node) => String(node.props.accessibilityLabel))
    .filter((label) => label.startsWith('Asignar a '));
const optionText = (name: string) =>
  texts().filter((text) => text === name).length > 0 &&
  options().includes(t('veterinarianAssignment.candidateAccessibility', { name }));

async function render(capabilities: string[]) {
  clinicsRead.mockResolvedValue({
    data: {
      clinics: [
        {
          clinicId: 'clinic-a',
          clinicDisplayName: 'Animalia',
          organizationId: 'org-1',
          organizationDisplayName: 'Animalia Group',
          capabilities,
          unknownCapabilities: [],
        },
      ],
    },
    error: null,
  });
  await act(async () => {
    tree = create(createElement(ProfessionalAppointmentDetailScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  i18n.locale = 'es';
  jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  contextRead.mockResolvedValue({
    data: { hasVeterinarianProfessionalProfile: false, organizations: [] },
    error: null,
  });
  appointmentRead.mockResolvedValue({ data: row, error: null });
});
afterEach(() => {
  act(() => tree.unmount());
  jest.restoreAllMocks();
});

describe.each([
  ['an Owner or Administrator', OWNER_OR_ADMINISTRATOR],
  ['a Receptionist', RECEPTIONIST],
])('%s assigning a Veterinarian', (_role, capabilities) => {
  it('sees each candidate by name, never the generic "Veterinario" for a named one', async () => {
    backend(UNASSIGNED, [
      candidate(VCA.ana, 'Ana García'),
      candidate(VCA.luis, 'Luis Pérez'),
      candidate(VCA.marta, 'Marta Ruiz'),
    ]);
    await render(capabilities);
    await press(t('veterinarianAssignment.assignAccessibility'));

    expect(rpc()).toHaveBeenCalledWith('get_appointment_veterinarian_candidates', {
      p_clinic_id: 'clinic-a',
      p_appointment_id: 'appt-1',
    });
    expect(optionText('Ana García')).toBe(true);
    expect(optionText('Luis Pérez')).toBe(true);
    expect(optionText('Marta Ruiz')).toBe(true);
    expect(options()).toHaveLength(3);
    // Three distinct options, none of them the neutral fallback.
    expect(new Set(options()).size).toBe(3);
    expect(options()).not.toContain(FALLBACK_OPTION());
  });

  it('changing the Veterinarian lists the others by name, without the current one', async () => {
    backend(assignedTo('Ana García'), [
      candidate(VCA.ana, 'Ana García', { is_current_assignee: true }),
      candidate(VCA.luis, 'Luis Pérez'),
      candidate(VCA.marta, 'Marta Ruiz'),
    ]);
    await render(capabilities);
    await press(t('veterinarianAssignment.changeAccessibility'));
    expect(options()).toEqual([
      t('veterinarianAssignment.candidateAccessibility', { name: 'Luis Pérez' }),
      t('veterinarianAssignment.candidateAccessibility', { name: 'Marta Ruiz' }),
    ]);
    expect(options()).not.toContain(FALLBACK_OPTION());
  });

  it('only a candidate returned without a name falls back to "Veterinario"', async () => {
    backend(UNASSIGNED, [
      candidate(VCA.ana, 'Ana García'),
      candidate(VCA.luis, 'Luis Pérez'),
      candidate(VCA.unnamed, null),
    ]);
    await render(capabilities);
    await press(t('veterinarianAssignment.assignAccessibility'));
    expect(optionText('Ana García')).toBe(true);
    expect(optionText('Luis Pérez')).toBe(true);
    expect(options().filter((label) => label === FALLBACK_OPTION())).toHaveLength(1);
  });

  it('never shows an internal identifier in place of a name', async () => {
    backend(UNASSIGNED, [candidate(VCA.ana, 'Ana García'), candidate(VCA.unnamed, null)]);
    await render(capabilities);
    await press(t('veterinarianAssignment.assignAccessibility'));
    const shown = [...texts(), ...options()].join(' ');
    for (const id of [...Object.values(VCA), TOKEN]) expect(shown).not.toContain(id);
    expect(shown).not.toContain('@');
  });
});

it('trims the name the read returns, as the backend stores it', async () => {
  backend(UNASSIGNED, [candidate(VCA.ana, '  Ana García '), candidate(VCA.luis, 'Luis Pérez')]);
  await render(RECEPTIONIST);
  await press(t('veterinarianAssignment.assignAccessibility'));
  expect(optionText('Ana García')).toBe(true);
});

it('a manager who is also a candidate sees their own name with "(Tú)"', async () => {
  backend(UNASSIGNED, [
    candidate(VCA.ana, 'Ana García', { is_me: true }),
    candidate(VCA.luis, 'Luis Pérez'),
  ]);
  await render(OWNER_OR_ADMINISTRATOR);
  await press(t('veterinarianAssignment.assignAccessibility'));
  expect(optionText(`Ana García ${t('veterinarianAssignment.youSuffix')}`)).toBe(true);
  expect(optionText('Luis Pérez')).toBe(true);
});

it('a malformed candidates answer is an error, never invented options', async () => {
  backend(UNASSIGNED, [candidate(VCA.ana, '')]);
  await render(RECEPTIONIST);
  await press(t('veterinarianAssignment.assignAccessibility'));
  expect(options()).toEqual([]);
  expect(texts()).toContain(t('veterinarianAssignment.pickerError'));
});

it('the assigned Veterinarian row shows the same name the picker offered', async () => {
  backend(assignedTo('Luis Pérez'), [
    candidate(VCA.luis, 'Luis Pérez', { is_current_assignee: true }),
  ]);
  await render(RECEPTIONIST);
  const shown = texts();
  // The row's label, then the assignee's name — not the fallback in its place.
  expect(shown[shown.indexOf(t('veterinarianAssignment.title')) + 1]).toBe('Luis Pérez');
  expect(shown.filter((text) => text === FALLBACK())).toHaveLength(1);
});

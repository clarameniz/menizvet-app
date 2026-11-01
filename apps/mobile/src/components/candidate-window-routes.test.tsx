import { createElement, type ComponentType } from 'react';
import { Text } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import ProfessionalAlternativeTimeScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]/alternative-time';
import ProfessionalRescheduleScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]/reschedule';
import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import {
  getAppointmentRescheduleCandidates,
  type RescheduleCandidate,
} from '@/data/professional-appointment-reschedule';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import { getRequestedAlternativeCandidates } from '@/data/requested-alternative-time';
import { i18n } from '@/i18n/i18n';
import { formatCandidateDateLabel } from '@/lib/appointment-time';

/**
 * The first candidate read of both Clinic candidate screens starts on the
 * Clinic-local today — never on the Appointment's own date, never on the
 * device's date — and the screen offers exactly what the backend returned.
 * The backend alone removes past positions, the current start and infeasible
 * intervals (SPEC-APT-020 BR-4/BR-6, SPEC-APT-017).
 *
 * Android finding (REQUESTED Alternative Time): a request for tomorrow may
 * receive an alternative later today (SPEC-APT-018 BR-14 has no date floor).
 */

let mockParams: Record<string, string> = {};
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => mockParams,
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => callback(), [callback]);
  },
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
  const mockTranslate = mockI18n.t.bind(mockI18n);
  return { useLocale: () => ({ locale: 'es', t: mockTranslate }) };
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
jest.mock('@/data/requested-alternative-time', () => ({
  ...jest.requireActual('@/data/requested-alternative-time'),
  getRequestedAlternativeCandidates: jest.fn(),
  proposeRequestedAlternativeTime: jest.fn(),
}));
jest.mock('@/data/professional-appointment-reschedule', () => ({
  ...jest.requireActual('@/data/professional-appointment-reschedule'),
  getAppointmentRescheduleCandidates: jest.fn(),
  proposeClinicReschedule: jest.fn(),
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
const alternativeRead = getRequestedAlternativeCandidates as jest.Mock;
const rescheduleRead = getAppointmentRescheduleCandidates as jest.Mock;

// 13:00 in Madrid (CET) on 2035-03-01; already 2035-03-02 01:00 in Auckland.
const NOW = new Date('2035-03-01T12:00:00Z');

const row = (overrides: Partial<ClinicScheduleAppointment> = {}): ClinicScheduleAppointment => ({
  id: 'appt-1',
  petId: 'pet-1',
  petName: 'Luna',
  requestingUserId: 'user-1',
  requesterDisplayName: 'María López',
  reasonForVisit: 'Revisión',
  guardianNotes: null,
  lifecycleState: 'REQUESTED',
  createdAt: '2035-02-01T00:00:00Z',
  // Requested for tomorrow, 10:00 Madrid.
  currentScheduledStartAt: '2035-03-02T09:00:00Z',
  currentScheduledEndAt: '2035-03-02T09:30:00Z',
  currentSchedulingTimezoneName: 'Europe/Madrid',
  currentScheduleRevisionSequence: 1,
  currentVeterinarianClinicAssignmentId: null,
  pendingReschedule: null,
  currentScheduleSource: null,
  cancellationReason: null,
  hasClinicalRecord: false,
  ...overrides,
});
const candidate = (localDate: string, localTime: string, endAt: string): RescheduleCandidate => ({
  localDate,
  localTime,
  utcOffsetSeconds: 3600,
  endAt,
});
const TODAY_1500 = candidate('2035-03-01', '15:00:00', '2035-03-01T14:30:00Z');
const TODAY_1530 = candidate('2035-03-01', '15:30:00', '2035-03-01T15:00:00Z');
const TOMORROW_0900 = candidate('2035-03-02', '09:00:00', '2035-03-02T08:30:00Z');

let tree: ReactTestRenderer;
const t = (key: string) => i18n.t(key);
const radios = () =>
  tree.root
    .findAll(
      (node) =>
        node.props.accessibilityRole === 'radio' && typeof node.props.onPress === 'function',
    )
    .map((node) => ({
      label: String(node.props.accessibilityLabel),
      selected: node.props.accessibilityState?.selected === true,
      press: () => node.props.onPress(),
    }));
const dateLabel = (localDate: string) => formatCandidateDateLabel(localDate, 'es');
const findButton = (label: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityLabel === label &&
      typeof node.props.onPress === 'function',
  )[0];
async function render(screen: ComponentType) {
  await act(async () => {
    tree = create(createElement(screen));
  });
}

beforeEach(() => {
  jest.useFakeTimers({
    now: NOW,
    doNotFake: [
      'nextTick',
      'setImmediate',
      'clearImmediate',
      'setTimeout',
      'clearTimeout',
      'setInterval',
      'clearInterval',
      'queueMicrotask',
    ],
  });
  jest.clearAllMocks();
  contextRead.mockResolvedValue(professionalContext(true));
  clinicsRead.mockResolvedValue({
    data: {
      clinics: [
        {
          clinicId: 'clinic-a',
          clinicDisplayName: 'Animalia',
          organizationId: 'org-1',
          organizationDisplayName: 'Animalia Group',
          capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_RESCHEDULE'],
          unknownCapabilities: [],
        },
      ],
    },
    error: null,
  });
  mockParams = { clinicId: 'clinic-a', appointmentId: 'appt-1', sequence: '1' };
});
afterEach(() => {
  act(() => tree.unmount());
  jest.useRealTimers();
});

describe('REQUESTED Alternative Time (SPEC-APT-020)', () => {
  it('reads from Clinic-local today, not from the requested date, and offers today first', async () => {
    scheduleRead.mockResolvedValue({ data: [row()], error: null });
    alternativeRead.mockResolvedValue({
      data: [TODAY_1500, TODAY_1530, TOMORROW_0900],
      error: null,
    });
    await render(ProfessionalAlternativeTimeScreen);

    expect(alternativeRead).toHaveBeenCalledTimes(1);
    expect(alternativeRead).toHaveBeenCalledWith('appt-1', '2035-03-01', '2035-04-29');
    const today = radios().find((radio) => radio.label === dateLabel('2035-03-01'));
    expect(today?.selected).toBe(true);
    // Exactly what the backend returned for today, in its order: no client filtering.
    expect(radios().map((radio) => radio.label)).toEqual([
      dateLabel('2035-03-01'),
      dateLabel('2035-03-02'),
      '15:00',
      '15:30',
    ]);

    await act(async () =>
      radios()
        .find((radio) => radio.label === '15:00')!
        .press(),
    );
    expect(radios().find((radio) => radio.label === '15:00')?.selected).toBe(true);
    expect(tree.root.findAllByType(Text).map((node) => String(node.props.children))).toContain(
      t('alternativeTime.proposedLabel'),
    );
  });

  it('tomorrow keeps working, and the requested start is never invented client-side', async () => {
    scheduleRead.mockResolvedValue({ data: [row()], error: null });
    alternativeRead.mockResolvedValue({ data: [TODAY_1500, TOMORROW_0900], error: null });
    await render(ProfessionalAlternativeTimeScreen);
    await act(async () =>
      radios()
        .find((radio) => radio.label === dateLabel('2035-03-02'))!
        .press(),
    );
    const labels = radios().map((radio) => radio.label);
    expect(labels).toContain('09:00');
    expect(labels).not.toContain('10:00');
  });

  it('without today in the backend result (no Availability left today) the first offered date is tomorrow', async () => {
    scheduleRead.mockResolvedValue({ data: [row()], error: null });
    alternativeRead.mockResolvedValue({ data: [TOMORROW_0900], error: null });
    await render(ProfessionalAlternativeTimeScreen);
    expect(alternativeRead).toHaveBeenCalledWith('appt-1', '2035-03-01', '2035-04-29');
    expect(radios().map((radio) => radio.label)).toEqual([dateLabel('2035-03-02'), '09:00']);
  });

  it('uses the Clinic-local date when it differs from the device and UTC dates', async () => {
    scheduleRead.mockResolvedValue({
      data: [
        row({
          currentScheduledStartAt: '2035-03-03T21:00:00Z',
          currentScheduledEndAt: '2035-03-03T21:30:00Z',
          currentSchedulingTimezoneName: 'Pacific/Auckland',
        }),
      ],
      error: null,
    });
    alternativeRead.mockResolvedValue({ data: [], error: null });
    await render(ProfessionalAlternativeTimeScreen);
    expect(alternativeRead).toHaveBeenCalledWith('appt-1', '2035-03-02', '2035-04-30');
  });

  it('pages later in 60-date windows and earlier back to today, never before', async () => {
    scheduleRead.mockResolvedValue({ data: [row()], error: null });
    alternativeRead.mockResolvedValue({ data: [TODAY_1500], error: null });
    await render(ProfessionalAlternativeTimeScreen);
    expect(findButton(t('candidatePicker.earlierDates'))).toBeUndefined();
    await act(async () => findButton(t('candidatePicker.laterDates')).props.onPress());
    expect(alternativeRead).toHaveBeenLastCalledWith('appt-1', '2035-04-30', '2035-06-28');
    await act(async () => findButton(t('candidatePicker.earlierDates')).props.onPress());
    expect(alternativeRead).toHaveBeenLastCalledWith('appt-1', '2035-03-01', '2035-04-29');
    expect(findButton(t('candidatePicker.earlierDates'))).toBeUndefined();
  });
});

describe('CONFIRMED reschedule shares the window rule (SPEC-APT-017)', () => {
  const confirmed = (overrides: Partial<ClinicScheduleAppointment> = {}) =>
    row({ lifecycleState: 'CONFIRMED', currentScheduleRevisionSequence: 2, ...overrides });

  beforeEach(() => {
    mockParams = { clinicId: 'clinic-a', appointmentId: 'appt-1', sequence: '2' };
  });

  it('reads from Clinic-local today and offers today first', async () => {
    scheduleRead.mockResolvedValue({ data: [confirmed()], error: null });
    rescheduleRead.mockResolvedValue({ data: [TODAY_1500, TOMORROW_0900], error: null });
    await render(ProfessionalRescheduleScreen);
    expect(rescheduleRead).toHaveBeenCalledWith('appt-1', '2035-03-01', '2035-04-29');
    expect(alternativeRead).not.toHaveBeenCalled();
    expect(radios().find((radio) => radio.label === dateLabel('2035-03-01'))?.selected).toBe(true);
    expect(radios().map((radio) => radio.label)).toContain('15:00');
  });

  it('uses the Clinic-local date across a timezone mismatch', async () => {
    scheduleRead.mockResolvedValue({
      data: [
        confirmed({
          currentScheduledStartAt: '2035-03-03T21:00:00Z',
          currentScheduledEndAt: '2035-03-03T21:30:00Z',
          currentSchedulingTimezoneName: 'Pacific/Auckland',
        }),
      ],
      error: null,
    });
    rescheduleRead.mockResolvedValue({ data: [], error: null });
    await render(ProfessionalRescheduleScreen);
    expect(rescheduleRead).toHaveBeenCalledWith('appt-1', '2035-03-02', '2035-04-30');
  });
});

describe('direct navigation and APPOINTMENT_MANAGEMENT (SPEC-APT-012 BR-61)', () => {
  const shown = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
  const CONFIRMED = row({ lifecycleState: 'CONFIRMED' });
  const screens = [
    {
      name: 'Propose another time',
      screen: ProfessionalAlternativeTimeScreen,
      appointment: row(),
      candidates: () => alternativeRead,
      notAvailableKey: 'alternativeTime.notAvailable',
      backKey: 'alternativeTime.backToAppointment',
    },
    {
      name: 'Propose a new time',
      screen: ProfessionalRescheduleScreen,
      appointment: CONFIRMED,
      candidates: () => rescheduleRead,
      notAvailableKey: 'professionalReschedule.notAvailable',
      backKey: 'professionalReschedule.backToAppointment',
    },
  ];

  describe.each(screens)(
    '$name',
    ({ screen, appointment, candidates, notAvailableKey, backKey }) => {
      beforeEach(() => {
        scheduleRead.mockResolvedValue({ data: [appointment], error: null });
        candidates().mockResolvedValue({ data: [TODAY_1500], error: null });
      });

      it('without the Entitlement shows no form, reads no candidates, and leads back', async () => {
        contextRead.mockResolvedValue(professionalContext(false));
        await render(screen);
        expect(shown()).toContain(t('appointmentManagement.unavailable'));
        expect(candidates()).not.toHaveBeenCalled();
        expect(radios()).toHaveLength(0);
        expect(findButton(t('appointmentManagement.retryLabel'))).toBeUndefined();
        const { router } = jest.requireMock('expo-router');
        await act(async () => findButton(t(backKey)).props.onPress());
        expect(router.dismissTo).toHaveBeenCalledWith({
          pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]',
          params: { clinicId: 'clinic-a', appointmentId: 'appt-1' },
        });
      });

      it("uses only the Clinic's own Organization", async () => {
        contextRead.mockResolvedValue({
          data: {
            hasVeterinarianProfessionalProfile: false,
            organizations: [
              professionalContext(false, 'org-1').data.organizations[0],
              professionalContext(true, 'org-2').data.organizations[0],
            ],
          },
          error: null,
        });
        await render(screen);
        expect(shown()).toContain(t('appointmentManagement.unavailable'));
        expect(candidates()).not.toHaveBeenCalled();
      });

      it('an unverified Entitlement offers a retry that, once verified, reads the candidates', async () => {
        contextRead.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
        await render(screen);
        expect(shown()).toContain(t('appointmentManagement.unverified'));
        expect(shown()).not.toContain(t('appointmentManagement.unavailable'));
        expect(candidates()).not.toHaveBeenCalled();

        await act(async () => findButton(t('appointmentManagement.retryLabel')).props.onPress());
        expect(contextRead).toHaveBeenCalledTimes(2);
        expect(candidates()).toHaveBeenCalledTimes(1);
        expect(radios().length).toBeGreaterThan(0);
      });

      it('an expired session while verifying says so', async () => {
        contextRead.mockResolvedValueOnce({
          data: null,
          error: 'PROFESSIONAL_CONTEXT_AUTH_REQUIRED',
        });
        await render(screen);
        expect(shown()).toContain(t('errors.sessionExpired'));
        expect(candidates()).not.toHaveBeenCalled();
      });

      it('when the proposal is not possible anyway, says so without mentioning the Entitlement', async () => {
        contextRead.mockResolvedValue(professionalContext(false));
        clinicsRead.mockResolvedValue({
          data: {
            clinics: [
              {
                clinicId: 'clinic-a',
                clinicDisplayName: 'Animalia',
                organizationId: 'org-1',
                organizationDisplayName: 'Animalia Group',
                capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CANCEL'],
                unknownCapabilities: [],
              },
            ],
          },
          error: null,
        });
        await render(screen);
        expect(shown()).toContain(t(notAvailableKey));
        expect(shown()).not.toContain(t('appointmentManagement.unavailable'));
        expect(candidates()).not.toHaveBeenCalled();
      });
    },
  );
});

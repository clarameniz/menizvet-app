import { createElement } from 'react';
import { Alert, Text, type AlertButton } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import ProfessionalAppointmentDetailScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]';
import { AppointmentClinicalRecordSection } from '@/components/appointment-clinical-record-section';
import {
  AppointmentManagementSection,
  ManagementActionRow,
} from '@/components/appointment-management-section';
import { AppointmentPriorHistoryRow } from '@/components/appointment-prior-history-row';
import { Button } from '@/components/design-system/button';
import {
  viewAppointmentClinicalRecord,
  type AppointmentClinicalRecordRead,
} from '@/data/appointment-clinical-record';
import { confirmAppointment } from '@/data/appointment-confirmation';
import { getAppointmentVeterinarianAssignment } from '@/data/appointment-veterinarian-assignment';
import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  CLINIC_SCHEDULE_MALFORMED,
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';

/**
 * The professional Appointment detail (SPEC-MED-010 Part F, SPEC-APT-007 §13):
 * the operational actions, the Veterinarian row, the explicit history action
 * and the visit's Clinical record. `has_clinical_record` hides Cancel, No-show
 * and Propose a new time; Complete stays under its own rules. The full
 * Veterinarian journey lives in professional-clinical-journey-route.test.tsx.
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
jest.mock('@/data/appointment-confirmation', () => ({
  ...jest.requireActual('@/data/appointment-confirmation'),
  confirmAppointment: jest.fn(),
}));
jest.mock('expo-router/react-navigation', () => ({ usePreventRemove: jest.fn() }));
jest.mock('@/data/appointment-veterinarian-assignment', () => ({
  ...jest.requireActual('@/data/appointment-veterinarian-assignment'),
  getAppointmentVeterinarianAssignment: jest.fn(),
}));
jest.mock('@/data/appointment-clinical-record', () => ({
  ...jest.requireActual('@/data/appointment-clinical-record'),
  viewAppointmentClinicalRecord: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const assignmentRead = getAppointmentVeterinarianAssignment as jest.Mock;
const recordRead = viewAppointmentClinicalRecord as jest.Mock;
const emptyRecord = (lifecycleState = 'CONFIRMED'): AppointmentClinicalRecordRead => ({
  kind: 'permitted',
  record: {
    appointmentId: 'appt-1',
    appointmentLifecycleState: lifecycleState,
    canRecord: true,
    unavailableReason: null,
    entries: [],
    entriesTruncated: false,
  },
});

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
const confirmRequest = confirmAppointment as jest.Mock;
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
const FUTURE = { start: '2035-06-01T08:00:00Z', end: '2035-06-01T08:30:00Z' };
const PAST = { start: '2026-01-15T08:00:00Z', end: '2026-01-15T08:30:00Z' };

const row = (
  lifecycleState: ClinicScheduleAppointment['lifecycleState'],
  hasClinicalRecord: boolean,
  when = FUTURE,
): ClinicScheduleAppointment => ({
  id: 'appt-1',
  petId: 'pet-1',
  petName: 'Luna',
  requestingUserId: 'user-1',
  requesterDisplayName: 'María López',
  reasonForVisit: 'Revisión',
  guardianNotes: null,
  lifecycleState,
  createdAt: '2026-01-01T00:00:00Z',
  currentScheduledStartAt: when.start,
  currentScheduledEndAt: when.end,
  currentSchedulingTimezoneName: 'Europe/Madrid',
  currentScheduleRevisionSequence: 2,
  currentVeterinarianClinicAssignmentId: null,
  pendingReschedule: null,
  currentScheduleSource: null,
  cancellationReason: null,
  hasClinicalRecord,
});

let tree: ReactTestRenderer;
const t = (key: string) => i18n.t(key);
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const buttonLabels = () =>
  tree.root
    .findAll(
      (node) =>
        node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
    )
    .map((node) => String(node.props.accessibilityLabel));
async function render(appointment: ClinicScheduleAppointment) {
  scheduleRead.mockResolvedValue({ data: [appointment], error: null });
  await act(async () => {
    tree = create(createElement(ProfessionalAppointmentDetailScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  assignmentRead.mockResolvedValue({
    kind: 'loaded',
    assignment: { kind: 'unassigned', mayAssignMe: true, mayManage: false },
  });
  recordRead.mockResolvedValue(emptyRecord());
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
            'APPOINTMENT_COMPLETE',
            'APPOINTMENT_MARK_NO_SHOW',
            'APPOINTMENT_RESCHEDULE',
            'CLINICAL_CARE',
            'CLINICAL_DOCUMENTATION',
          ],
          unknownCapabilities: [],
        },
      ],
    },
    error: null,
  });
});
afterEach(() => act(() => tree.unmount()));

// No retired Encounter wording, in any lifecycle.
function expectNoEncounterWording() {
  expect(texts().join(' ')).not.toMatch(
    /atención clínica iniciada|clinical care started|atención terminada|care finished|concluid|concluded|Iniciar registro|Start clinical record|Terminar atención|borrador|draft|finaliz/i,
  );
}

it('CONFIRMED without records: the operational actions, the Veterinarian and the Clinical record are offered', async () => {
  await render(row('CONFIRMED', false));
  expectNoEncounterWording();
  expect(texts()).toEqual(
    expect.arrayContaining([
      t('veterinarianAssignment.title'),
      t('veterinarianAssignment.unassigned'),
      t('clinicalRecord.sectionTitle'),
      t('professionalAppointment.managementTitle'),
    ]),
  );
  expect(texts().join(' ')).not.toMatch(/Otras acciones|Other actions/);
  expect(buttonLabels()).toEqual(
    expect.arrayContaining([
      t('professionalReschedule.action'),
      t('professionalCancellation.action'),
      t('veterinarianAssignment.assignMe'),
      t('clinicalRecord.addRecord'),
    ]),
  );
});

it('CONFIRMED with records: Cancel and Propose stay hidden', async () => {
  await render(row('CONFIRMED', true));
  expectNoEncounterWording();
  const labels = buttonLabels();
  expect(labels).not.toContain(t('professionalReschedule.action'));
  expect(labels).not.toContain(t('professionalCancellation.action'));
});

it('CONFIRMED after its start with records: No-show hidden, Complete offered after the visit sections', async () => {
  await render(row('CONFIRMED', true, PAST));
  const labels = buttonLabels();
  expect(labels).not.toContain(t('appointmentNoShow.action'));
  expect(labels).not.toContain(t('professionalCancellation.postStartAction'));
  expect(labels).toContain(t('appointmentCompletion.action'));
  // Complete is independent of documentation: it is never "Save and complete".
  expect(labels.join(' ')).not.toMatch(/Guardar y completar|Save and complete/);
});

describe('Appointment management card', () => {
  const management = () => tree.root.findAllByType(AppointmentManagementSection);
  const labelsIn = (node: ReactTestInstance) =>
    node
      .findAll(
        (candidate) =>
          candidate.props.accessibilityRole === 'button' &&
          typeof candidate.props.onPress === 'function',
      )
      .map((candidate) => String(candidate.props.accessibilityLabel));
  const textsIn = (node: ReactTestInstance) =>
    node.findAllByType(Text).map((candidate) => String(candidate.props.children));
  const rowTone = (label: string) =>
    tree.root.findAll((node) => node.type === ManagementActionRow && node.props.label === label)[0]
      ?.props.tone ?? 'neutral';

  it('gathers every state action after the Clinical record: Complete leads, No-show and Cancel are quieter rows', async () => {
    await render(row('CONFIRMED', false, PAST));
    const labels = buttonLabels();
    const complete = labels.indexOf(t('appointmentCompletion.action'));
    const addRecord = labels.indexOf(t('clinicalRecord.addRecord'));
    const noShow = labels.indexOf(t('appointmentNoShow.action'));
    const cancel = labels.indexOf(t('professionalCancellation.postStartAction'));
    expect(addRecord).toBeGreaterThanOrEqual(0);
    expect(addRecord).toBeLessThan(complete);
    expect(complete).toBeLessThan(noShow);
    expect(noShow).toBeLessThan(cancel);

    expect(management()).toHaveLength(1);
    expect(labelsIn(management()[0])).toEqual([
      t('appointmentCompletion.action'),
      t('appointmentNoShow.action'),
      t('professionalCancellation.postStartAction'),
    ]);
    // Complete is the one primary button; the others are rows, Cancel with caution.
    const completeButton = management()[0]
      .findAllByType(Button)
      .filter((node) => node.props.label === t('appointmentCompletion.action'));
    expect(completeButton).toHaveLength(1);
    expect(completeButton[0].props.variant ?? 'primary').toBe('primary');
    expect(rowTone(t('appointmentNoShow.action'))).toBe('neutral');
    expect(rowTone(t('professionalCancellation.postStartAction'))).toBe('caution');
    expect(textsIn(management()[0])).toContain(t('appointmentCompletion.resolutionHint'));
    // No state action is left in the Clinical record card.
    const record = tree.root.findByType(AppointmentClinicalRecordSection);
    expect(labelsIn(record)).not.toContain(t('appointmentCompletion.action'));
  });

  it('REQUESTED: Confirm leads, then Propose another time and Cancel', async () => {
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
              'APPOINTMENT_CONFIRM',
              'APPOINTMENT_CANCEL',
              'APPOINTMENT_RESCHEDULE',
            ],
            unknownCapabilities: [],
          },
        ],
      },
      error: null,
    });
    await render(row('REQUESTED', false));
    expect(labelsIn(management()[0])).toEqual([
      t('appointmentConfirmation.action'),
      t('alternativeTime.action'),
      t('professionalCancellation.action'),
    ]);
    expect(rowTone(t('professionalCancellation.action'))).toBe('caution');
  });

  it('CONFIRMED in the future: Propose a new time and Cancel, no primary action', async () => {
    await render(row('CONFIRMED', false));
    expect(labelsIn(management()[0])).toEqual([
      t('professionalReschedule.action'),
      t('professionalCancellation.action'),
    ]);
    expect(management()[0].findAllByType(Button)).toHaveLength(0);
  });

  it('opening Cancel shows its form in the same card, in place of the row', async () => {
    await render(row('CONFIRMED', false));
    await act(async () => {
      tree.root
        .findAll(
          (node) =>
            node.props.accessibilityLabel === t('professionalCancellation.action') &&
            typeof node.props.onPress === 'function',
        )[0]
        .props.onPress();
    });
    const card = management()[0];
    expect(textsIn(card)).toContain(t('professionalCancellation.panelTitle'));
    expect(labelsIn(card)).toEqual([
      t('professionalCancellation.submit'),
      t('professionalCancellation.back'),
    ]);
  });

  it('a pending Clinic proposal and its Withdraw live in the card', async () => {
    await render({
      ...row('CONFIRMED', false),
      pendingReschedule: {
        kind: 'confirmedReschedule',
        proposalId: 'proposal-1',
        proposingContext: 'CLINIC',
        reason: 'Agenda completa',
        proposedStartAt: '2035-06-02T08:00:00Z',
        proposedEndAt: '2035-06-02T08:30:00Z',
        proposedTimezoneName: 'Europe/Madrid',
        currentlyFeasible: true,
      },
    });
    const card = management()[0];
    expect(textsIn(card)).toEqual(
      expect.arrayContaining([t('professionalReschedule.pendingTitle'), 'Agenda completa']),
    );
    expect(labelsIn(card)).toContain(t('professionalReschedule.withdrawAction'));
  });

  it.each(['CANCELLED', 'NO_SHOW', 'EXPIRED'] as const)(
    '%s: no management card and no stray state button',
    async (lifecycleState) => {
      await render(row(lifecycleState, false, PAST));
      expect(management()).toHaveLength(0);
      expect(texts()).not.toContain(t('professionalAppointment.managementTitle'));
    },
  );

  it('COMPLETED: no management card; the Clinical record stays separate', async () => {
    recordRead.mockResolvedValue(emptyRecord('COMPLETED'));
    await render(row('COMPLETED', true, PAST));
    expect(management()).toHaveLength(0);
    expect(tree.root.findAllByType(AppointmentClinicalRecordSection)).toHaveLength(1);
  });

  it('the outcome of an action is shown in the card where it was taken', async () => {
    const alert = jest
      .spyOn(Alert, 'alert')
      .mockImplementation((_title, _message, buttons?: AlertButton[]) => {
        buttons?.find((button) => button.style !== 'cancel')?.onPress?.();
      });
    clinicsRead.mockResolvedValue({
      data: {
        clinics: [
          {
            clinicId: 'clinic-a',
            clinicDisplayName: 'Animalia',
            organizationId: 'org-1',
            organizationDisplayName: 'Animalia Group',
            capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CONFIRM'],
            unknownCapabilities: [],
          },
        ],
      },
      error: null,
    });
    confirmRequest.mockResolvedValue({ data: 'appt-1', error: null });
    await render(row('REQUESTED', false));
    scheduleRead.mockResolvedValue({ data: [row('CONFIRMED', false)], error: null });
    await act(async () => {
      tree.root
        .findAll(
          (node) =>
            node.props.accessibilityLabel === t('appointmentConfirmation.action') &&
            typeof node.props.onPress === 'function',
        )[0]
        .props.onPress();
    });
    expect(textsIn(management()[0])).toContain(t('appointmentConfirmation.confirmed'));
    alert.mockRestore();
  });

  it('a second tap while a dialog is open opens nothing more', async () => {
    const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
    await render(row('CONFIRMED', false, PAST));
    const pressComplete = () =>
      tree.root
        .findAll(
          (node) =>
            node.props.accessibilityLabel === t('appointmentCompletion.action') &&
            typeof node.props.onPress === 'function',
        )[0]
        .props.onPress();
    act(() => pressComplete());
    act(() => pressComplete());
    expect(alert).toHaveBeenCalledTimes(1);
    alert.mockRestore();
  });
});

it('COMPLETED: the record stays available; no Complete, no No-show', async () => {
  recordRead.mockResolvedValue(emptyRecord('COMPLETED'));
  await render(row('COMPLETED', true, PAST));
  expectNoEncounterWording();
  expect(texts()).toContain(t('clinicalRecord.sectionTitle'));
  expect(buttonLabels()).toContain(t('clinicalRecord.addRecord'));
  expect(buttonLabels()).not.toContain(t('appointmentCompletion.action'));
});

it('an actor without CLINICAL_DOCUMENTATION never triggers the audited record read', async () => {
  clinicsRead.mockResolvedValue({
    data: {
      clinics: [
        {
          clinicId: 'clinic-a',
          clinicDisplayName: 'Animalia',
          organizationId: 'org-1',
          organizationDisplayName: 'Animalia Group',
          capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE', 'CLINICAL_CARE'],
          unknownCapabilities: [],
        },
      ],
    },
    error: null,
  });
  await render(row('CONFIRMED', true));
  expect(texts()).not.toContain(t('clinicalRecord.sectionTitle'));
  expect(recordRead).not.toHaveBeenCalled();
  // The Veterinarian row is still shown to everyone who can see the Appointment.
  expect(texts()).toContain(t('veterinarianAssignment.title'));
});

it('REQUESTED and terminal Appointments show no Veterinarian row and no Clinical record', async () => {
  await render(row('REQUESTED', false));
  expect(texts()).not.toContain(t('veterinarianAssignment.title'));
  expect(texts()).not.toContain(t('clinicalRecord.sectionTitle'));
  expect(assignmentRead).not.toHaveBeenCalled();
  expect(recordRead).not.toHaveBeenCalled();
});

describe('Ver historial clínico (SPEC-MED-005 §15)', () => {
  const HISTORY = () => t('professionalHistory.action');
  const historyReads = () =>
    (jest.requireMock('@/lib/supabase').supabase.rpc as jest.Mock).mock.calls.filter(
      ([name]) => name === 'view_appointment_professional_medical_history',
    );
  const pressHistory = () =>
    act(() => {
      tree.root
        .findAll(
          (node) =>
            node.props.accessibilityLabel === HISTORY() && typeof node.props.onPress === 'function',
        )[0]
        .props.onPress();
    });

  it('opening the Appointment detail reads no history', async () => {
    await render(row('CONFIRMED', false));
    expect(historyReads()).toHaveLength(0);
  });

  it('is offered before care for a REQUESTED Appointment with a future start, in a small card of its own', async () => {
    await render(row('REQUESTED', false));
    expect(buttonLabels()).toContain(HISTORY());
    // No Clinical record card for a request: the row is not lost with it.
    expect(tree.root.findAllByType(AppointmentClinicalRecordSection)).toHaveLength(0);
    expect(tree.root.findAllByType(AppointmentPriorHistoryRow)).toHaveLength(1);
    expect(historyReads()).toHaveLength(0);
  });

  it('is the last row of the Clinical record card, not a separate button', async () => {
    await render(row('CONFIRMED', false));
    const card = tree.root.findByType(AppointmentClinicalRecordSection);
    expect(card.findAllByType(AppointmentPriorHistoryRow)).toHaveLength(1);
    expect(
      tree.root.findAllByType(Button).filter((node) => node.props.label === HISTORY()),
    ).toHaveLength(0);
    expect(texts()).not.toContain('Ver antecedentes');
  });

  it('is offered before care for a CONFIRMED Appointment and opens the history route on tap', async () => {
    const { router } = jest.requireMock('expo-router');
    await render(row('CONFIRMED', false));
    expect(buttonLabels()).toContain(HISTORY());
    expect(historyReads()).toHaveLength(0);
    pressHistory();
    expect(router.push).toHaveBeenCalledWith({
      pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/history',
      params: { clinicId: 'clinic-a', appointmentId: 'appt-1' },
    });
    expect(historyReads()).toHaveLength(0);
  });

  it('is not offered for a REQUESTED Appointment whose start has passed', async () => {
    await render(row('REQUESTED', false, PAST));
    expect(buttonLabels()).not.toContain(HISTORY());
  });

  it('is not offered for a COMPLETED Appointment, whose completion closed prior history', async () => {
    await render(row('COMPLETED', true, PAST));
    expect(buttonLabels()).not.toContain(HISTORY());
  });

  it('stays offered once the visit has records (SPEC-MED-010 BR-14), and is still never read here', async () => {
    await render(row('CONFIRMED', true));
    expect(buttonLabels()).toContain(HISTORY());
    expect(historyReads()).toHaveLength(0);
  });

  it('is not offered without CLINICAL_CARE at the Clinic', async () => {
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
              'APPOINTMENT_CONFIRM',
              'APPOINTMENT_CANCEL',
            ],
            unknownCapabilities: [],
          },
        ],
      },
      error: null,
    });
    await render(row('CONFIRMED', false));
    expect(buttonLabels()).not.toContain(HISTORY());
  });
});

describe('single-Appointment read (SPEC-APT-012 BR-52)', () => {
  const press = async (label: string) => {
    const [node] = tree.root.findAll(
      (candidate) =>
        candidate.props.accessibilityLabel === label &&
        typeof candidate.props.onPress === 'function',
    );
    await act(async () => node.props.onPress());
  };

  it('reads only this Appointment of the route Clinic, never the whole schedule', async () => {
    await render(row('CONFIRMED', false));
    expect(appointmentRead).toHaveBeenCalledTimes(1);
    expect(appointmentRead).toHaveBeenCalledWith('clinic-a', 'appt-1');
    expect(fullScheduleRead()).toEqual([]);
    expect(texts()).toContain('Luna');
  });

  it.each([
    ['unknown or of another Clinic', { data: [], error: null }],
    ['denied (the uniform 42501)', { data: null, error: CLINIC_SCHEDULE_ACCESS_DENIED }],
  ])('shows an Appointment that is %s as unavailable', async (_label, result) => {
    scheduleRead.mockResolvedValue(result);
    await act(async () => {
      tree = create(createElement(ProfessionalAppointmentDetailScreen));
    });
    expect(texts()).toContain(t('professionalAppointment.notFound'));
    expect(buttonLabels()).toContain(t('professionalAppointment.backToSchedule'));
    expect(texts()).not.toContain('Luna');
  });

  it('shows a malformed first read as a retryable error, then the Appointment on retry', async () => {
    appointmentRead.mockResolvedValueOnce({ data: null, error: CLINIC_SCHEDULE_MALFORMED });
    await render(row('CONFIRMED', false));
    expect(texts()).not.toContain('Luna');
    await press(t('professional.retry'));
    expect(texts()).toContain('Luna');
    expect(appointmentRead).toHaveBeenCalledTimes(2);
  });

  it('opens an Appointment years old, outside any monthly window', async () => {
    await render(
      row('COMPLETED', false, { start: '2019-03-01T09:00:00Z', end: '2019-03-01T09:30:00Z' }),
    );
    expect(texts()).toContain('Luna');
    expect(texts()).toContain(t('clinicalRecord.sectionTitle'));
  });

  it('ignores a read that answers after the screen has left', async () => {
    let answer: (value: unknown) => void = () => {};
    appointmentRead.mockImplementationOnce(() => new Promise((resolve) => (answer = resolve)));
    await act(async () => {
      tree = create(createElement(ProfessionalAppointmentDetailScreen));
    });
    act(() => tree.unmount());
    await act(async () => answer({ data: row('CONFIRMED', false), error: null }));
    // A fresh screen for the shared teardown.
    await render(row('CONFIRMED', false));
    expect(texts()).toContain('Luna');
  });

  it('after a write, re-reads only this Appointment and shows its authoritative state', async () => {
    const alert = jest
      .spyOn(Alert, 'alert')
      .mockImplementation((_title, _message, buttons?: AlertButton[]) => {
        buttons?.find((button) => button.style !== 'cancel')?.onPress?.();
      });
    clinicsRead.mockResolvedValue({
      data: {
        clinics: [
          {
            clinicId: 'clinic-a',
            clinicDisplayName: 'Animalia',
            organizationId: 'org-1',
            organizationDisplayName: 'Animalia Group',
            capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CONFIRM'],
            unknownCapabilities: [],
          },
        ],
      },
      error: null,
    });
    confirmRequest.mockResolvedValue({ data: 'appt-1', error: null });
    await render(row('REQUESTED', false));
    expect(buttonLabels()).toContain(t('appointmentConfirmation.action'));

    scheduleRead.mockResolvedValue({ data: [row('CONFIRMED', false)], error: null });
    await press(t('appointmentConfirmation.action'));

    expect(confirmRequest).toHaveBeenCalledWith('appt-1', 2);
    expect(appointmentRead).toHaveBeenCalledTimes(2);
    expect(appointmentRead).toHaveBeenLastCalledWith('clinic-a', 'appt-1');
    expect(texts()).toContain(t('appointmentConfirmation.confirmed'));
    expect(buttonLabels()).not.toContain(t('appointmentConfirmation.action'));
    alert.mockRestore();
  });
});

describe('APPOINTMENT_MANAGEMENT (SPEC-APT-012 BR-61)', () => {
  // What each responsibility typically yields as Clinic capabilities (the
  // server derives them; the client only sees capabilities, never roles).
  const MANAGER = [
    'APPOINTMENT_VIEW_SCHEDULE',
    'APPOINTMENT_CONFIRM',
    'APPOINTMENT_CANCEL',
    'APPOINTMENT_RESCHEDULE',
    'APPOINTMENT_COMPLETE',
    'APPOINTMENT_MARK_NO_SHOW',
  ];
  const VETERINARIAN = [
    'APPOINTMENT_VIEW_SCHEDULE',
    'APPOINTMENT_COMPLETE',
    'CLINICAL_CARE',
    'CLINICAL_DOCUMENTATION',
  ];
  const CONFIRM = t('appointmentConfirmation.action');
  const ALTERNATIVE = t('alternativeTime.action');
  const PROPOSE = t('professionalReschedule.action');
  const UNAVAILABLE = t('appointmentManagement.unavailable');
  const UNVERIFIED = t('appointmentManagement.unverified');

  function withCapabilities(capabilities: string[], organizationId = 'org-1') {
    clinicsRead.mockResolvedValue({
      data: {
        clinics: [
          {
            clinicId: 'clinic-a',
            clinicDisplayName: 'Animalia',
            organizationId,
            organizationDisplayName: 'Animalia Group',
            capabilities,
            unknownCapabilities: [],
          },
        ],
      },
      error: null,
    });
  }
  const shown = () => texts().join(' | ');
  const press = async (label: string) => {
    const [node] = tree.root.findAll(
      (candidate) =>
        candidate.props.accessibilityLabel === label &&
        typeof candidate.props.onPress === 'function',
    );
    // Not awaiting the handler's own promise: a read may be held open on purpose.
    await act(async () => {
      node.props.onPress();
    });
  };
  const clinicProposal = {
    kind: 'confirmedReschedule' as const,
    proposalId: 'proposal-1',
    proposingContext: 'CLINIC' as const,
    reason: 'Agenda completa',
    proposedStartAt: '2035-06-02T08:00:00Z',
    proposedEndAt: '2035-06-02T08:30:00Z',
    proposedTimezoneName: 'Europe/Madrid',
    currentlyFeasible: true,
  };

  it('with the Entitlement, a manager gets Confirm, Propose another time and Cancel, without a note', async () => {
    withCapabilities(MANAGER);
    await render(row('REQUESTED', false));
    expect(buttonLabels()).toEqual(
      expect.arrayContaining([CONFIRM, ALTERNATIVE, t('professionalCancellation.action')]),
    );
    expect(shown()).not.toContain(UNAVAILABLE);
    expect(shown()).not.toContain(UNVERIFIED);
    expect(contextRead).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['an Owner or Administrator', MANAGER],
    ['a Receptionist', MANAGER.filter((capability) => capability !== 'APPOINTMENT_COMPLETE')],
  ])(
    'without it, %s keeps Cancel; Confirm and Propose are held back with one note',
    async (_role, capabilities) => {
      withCapabilities(capabilities);
      contextRead.mockResolvedValue(professionalContext(false));
      await render(row('REQUESTED', false));
      const labels = buttonLabels();
      expect(labels).not.toContain(CONFIRM);
      expect(labels).not.toContain(ALTERNATIVE);
      expect(labels).toContain(t('professionalCancellation.action'));
      expect(texts().filter((text) => text === UNAVAILABLE)).toHaveLength(1);
    },
  );

  it('holds back Propose a new time on a future CONFIRMED Appointment, keeping Cancel', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValue(professionalContext(false));
    await render(row('CONFIRMED', false));
    expect(buttonLabels()).not.toContain(PROPOSE);
    expect(buttonLabels()).toContain(t('professionalCancellation.action'));
    expect(shown()).toContain(UNAVAILABLE);
  });

  it('holds back Confirm of an accepted alternative, still saying the Guardian accepted it', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValue(professionalContext(false));
    await render({
      ...row('REQUESTED', false),
      currentScheduleSource: { proposalId: 'proposal-1', proposingContext: 'CLINIC' },
    });
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(t('alternativeTime.acceptedAwaitingConfirmation'));
    expect(shown()).toContain(UNAVAILABLE);
  });

  it('never gates Complete, No-show or Cancel, and says nothing when no gated action applies', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValue(professionalContext(false));
    await render(row('CONFIRMED', false, PAST));
    expect(buttonLabels()).toEqual(
      expect.arrayContaining([
        t('appointmentCompletion.action'),
        t('appointmentNoShow.action'),
        t('professionalCancellation.postStartAction'),
      ]),
    );
    expect(shown()).not.toContain(UNAVAILABLE);
  });

  it('never gates Withdraw of a Clinic proposal', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValue(professionalContext(false));
    await render({ ...row('CONFIRMED', false), pendingReschedule: clinicProposal });
    expect(buttonLabels()).toContain(t('professionalReschedule.withdrawAction'));
    expect(buttonLabels()).not.toContain(PROPOSE);
    // Propose is not possible anyway while a proposal is pending: no note.
    expect(shown()).not.toContain(UNAVAILABLE);
  });

  it('keeps Cancel and says nothing for an actor who may cancel but not confirm', async () => {
    withCapabilities(['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CANCEL']);
    contextRead.mockResolvedValue(professionalContext(false));
    await render(row('REQUESTED', false));
    expect(buttonLabels()).toContain(t('professionalCancellation.action'));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).not.toContain(UNAVAILABLE);
  });

  it('says nothing to a Veterinarian, who cannot confirm or propose anyway', async () => {
    withCapabilities(VETERINARIAN);
    contextRead.mockResolvedValue(professionalContext(false));
    await render(row('REQUESTED', false));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).not.toContain(UNAVAILABLE);
    expect(shown()).not.toContain(UNVERIFIED);
  });

  it("uses only the Clinic's own Organization, never another one's Entitlement", async () => {
    withCapabilities(MANAGER, 'org-1');
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
    await render(row('REQUESTED', false));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(UNAVAILABLE);
  });

  it('an Organization missing from the context is unverified, never "unavailable"', async () => {
    withCapabilities(MANAGER, 'org-1');
    contextRead.mockResolvedValue(professionalContext(true, 'org-2'));
    await render(row('REQUESTED', false));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(UNVERIFIED);
    expect(shown()).not.toContain(UNAVAILABLE);
  });

  it('a failed context read is unverified, with a retry that re-reads and restores the actions', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
    await render(row('REQUESTED', false));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(UNVERIFIED);
    expect(shown()).not.toContain(UNAVAILABLE);
    // Actions that need no Entitlement stay available meanwhile.
    expect(buttonLabels()).toContain(t('professionalCancellation.action'));

    await press(t('appointmentManagement.retryLabel'));
    expect(contextRead).toHaveBeenCalledTimes(2);
    expect(buttonLabels()).toContain(CONFIRM);
    expect(shown()).not.toContain(UNVERIFIED);
  });

  it('an expired session while reading the context says so instead', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValueOnce({ data: null, error: 'PROFESSIONAL_CONTEXT_AUTH_REQUIRED' });
    await render(row('REQUESTED', false));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(t('errors.sessionExpired'));
  });

  it('ignores a context answer that arrives after a newer read', async () => {
    withCapabilities(MANAGER);
    contextRead.mockResolvedValueOnce({ data: null, error: 'Network request failed' });
    await render(row('REQUESTED', false));
    let late: (value: unknown) => void = () => {};
    contextRead
      .mockImplementationOnce(() => new Promise((resolve) => (late = resolve)))
      .mockResolvedValueOnce(professionalContext(false));
    await press(t('appointmentManagement.retryLabel'));
    await press(t('appointmentManagement.retryLabel'));
    expect(shown()).toContain(UNAVAILABLE);
    await act(async () => late(professionalContext(true)));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(UNAVAILABLE);
  });

  it('re-reads the Entitlement after a denied Confirm, then stops offering it', async () => {
    const alert = jest
      .spyOn(Alert, 'alert')
      .mockImplementation((_title, _message, buttons?: AlertButton[]) => {
        buttons?.find((button) => button.style !== 'cancel')?.onPress?.();
      });
    withCapabilities(MANAGER);
    await render(row('REQUESTED', false));
    confirmRequest.mockResolvedValue({
      data: null,
      error: 'Applicable professional Entitlement is required',
    });
    contextRead.mockResolvedValue(professionalContext(false));
    await press(CONFIRM);
    expect(contextRead).toHaveBeenCalledTimes(2);
    expect(shown()).toContain(t('appointmentConfirmation.entitlementDenied'));
    expect(buttonLabels()).not.toContain(CONFIRM);
    expect(shown()).toContain(UNAVAILABLE);
    alert.mockRestore();
  });
});

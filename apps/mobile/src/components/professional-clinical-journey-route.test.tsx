import { uuid } from 'expo-modules-core';
import { usePreventRemove } from 'expo-router/react-navigation';
import { createElement } from 'react';
import { AccessibilityInfo, Alert, Text, TextInput, type AlertButton } from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import ProfessionalAppointmentDetailScreen from '@/app/professional/clinics/[clinicId]/appointments/[appointmentId]';
import { AppointmentClinicalRecordSection } from '@/components/appointment-clinical-record-section';
import { AppointmentVeterinarianSection } from '@/components/appointment-veterinarian-section';
import { ClinicalRecordEntryRow } from '@/components/clinical-record-entry-row';
import {
  createAppointmentClinicalEntry,
  editAppointmentClinicalEntry,
  viewAppointmentClinicalRecord,
  type AppointmentClinicalEntry,
  type AppointmentClinicalRecord,
  type AppointmentClinicalRecordRead,
} from '@/data/appointment-clinical-record';
import {
  assignAppointmentVeterinarian,
  assignMeToAppointment,
  getAppointmentVeterinarianAssignment,
  getAppointmentVeterinarianCandidates,
  type AppointmentVeterinarianAssignment,
} from '@/data/appointment-veterinarian-assignment';
import {
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import { i18n } from '@/i18n/i18n';
import { formatRecordedInstant } from '@/lib/appointment-time';
import { categoryLabelKey } from '@/lib/clinical-history-display';

/**
 * The Veterinarian's journey on the professional Appointment detail
 * (SPEC-MED-010 Part F, SPEC-APT-007 §13), against mocked data modules: the
 * DEVELOPMENT backend does not run the M5 edit contract yet, so nothing here
 * claims a real integration.
 */

let mockParams: Record<string, string> = { clinicId: 'clinic-a', appointmentId: 'appt-1' };
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => mockParams,
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
jest.mock('@/data/appointment-veterinarian-assignment', () => ({
  ...jest.requireActual('@/data/appointment-veterinarian-assignment'),
  getAppointmentVeterinarianAssignment: jest.fn(),
  getAppointmentVeterinarianCandidates: jest.fn(),
  assignMeToAppointment: jest.fn(),
  assignAppointmentVeterinarian: jest.fn(),
}));
jest.mock('@/data/appointment-clinical-record', () => ({
  ...jest.requireActual('@/data/appointment-clinical-record'),
  viewAppointmentClinicalRecord: jest.fn(),
  createAppointmentClinicalEntry: jest.fn(),
  editAppointmentClinicalEntry: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: jest.fn(), functions: { invoke: jest.fn() } },
}));

const clinicsRead = getMyProfessionalClinics as jest.Mock;
const contextRead = getMyProfessionalContext as jest.Mock;
const appointmentRead = getClinicAppointment as jest.Mock;
const assignmentRead = getAppointmentVeterinarianAssignment as jest.Mock;
const candidatesRead = getAppointmentVeterinarianCandidates as jest.Mock;
const assignMe = assignMeToAppointment as jest.Mock;
const assign = assignAppointmentVeterinarian as jest.Mock;
const recordRead = viewAppointmentClinicalRecord as jest.Mock;
const createEntry = createAppointmentClinicalEntry as jest.Mock;
const editEntry = editAppointmentClinicalEntry as jest.Mock;
const preventRemove = usePreventRemove as jest.Mock;

const VETERINARIAN = [
  'APPOINTMENT_VIEW_SCHEDULE',
  'APPOINTMENT_COMPLETE',
  'CLINICAL_CARE',
  'CLINICAL_DOCUMENTATION',
];
const RECEPTION = [
  'APPOINTMENT_VIEW_SCHEDULE',
  'APPOINTMENT_CONFIRM',
  'APPOINTMENT_CANCEL',
  'APPOINTMENT_COMPLETE',
  'APPOINTMENT_ASSIGN_VETERINARIAN',
];
function withCapabilities(capabilities: string[], clinicId = 'clinic-a') {
  clinicsRead.mockResolvedValue({
    data: {
      clinics: [
        {
          clinicId,
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
}

const PAST = { start: '2026-01-15T08:00:00Z', end: '2026-01-15T08:30:00Z' };
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
  currentScheduledStartAt: PAST.start,
  currentScheduledEndAt: PAST.end,
  currentSchedulingTimezoneName: 'Europe/Madrid',
  currentScheduleRevisionSequence: 2,
  currentVeterinarianClinicAssignmentId: null,
  pendingReschedule: null,
  currentScheduleSource: null,
  cancellationReason: null,
  hasClinicalRecord: false,
  ...overrides,
});

const UNASSIGNED: AppointmentVeterinarianAssignment = {
  kind: 'unassigned',
  mayAssignMe: true,
  mayManage: false,
};
const assigned = (
  overrides: Partial<Extract<AppointmentVeterinarianAssignment, { kind: 'assigned' }>> = {},
): AppointmentVeterinarianAssignment => ({
  kind: 'assigned',
  displayName: 'Ana García',
  isMe: true,
  isEligible: true,
  assignmentToken: 'token-1',
  mayAssignMe: false,
  mayManage: false,
  ...overrides,
});
const loadedAssignment = (assignment: AppointmentVeterinarianAssignment) => ({
  kind: 'loaded' as const,
  assignment,
});

const entry = (overrides: Partial<AppointmentClinicalEntry> = {}): AppointmentClinicalEntry => ({
  entryId: 'entry-1',
  category: 'EXAMINATION',
  otherCategoryContext: null,
  clinicalContent: 'Peso 12 kg',
  clinicalEventAt: null,
  recordedAt: '2026-01-15T08:10:00Z',
  recordedByMe: true,
  mayEdit: true,
  version: 1,
  editedAt: null,
  previousVersions: [],
  previousVersionsTruncated: false,
  amendments: [],
  amendmentsTruncated: false,
  ...overrides,
});
// The typing-error example of SPEC-MED-010 §5: a vaccination recorded on the
// wrong visit, corrected to what was actually done.
const vaccination = (overrides: Partial<AppointmentClinicalEntry> = {}) =>
  entry({ category: 'VACCINATION', clinicalContent: 'Vacuna de la rabia anual', ...overrides });
const corrected = (overrides: Partial<AppointmentClinicalEntry> = {}) =>
  entry({
    category: 'CLINICAL_NOTE',
    clinicalContent: 'Solo se realizó un corte de uñas',
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
    ...overrides,
  });
const record = (
  overrides: Partial<AppointmentClinicalRecord> = {},
): AppointmentClinicalRecordRead => ({
  kind: 'permitted',
  record: {
    appointmentId: 'appt-1',
    appointmentLifecycleState: 'CONFIRMED',
    canRecord: true,
    unavailableReason: null,
    entries: [],
    entriesTruncated: false,
    ...overrides,
  },
});
const CANNOT_RECORD_UNASSIGNED = {
  canRecord: false,
  unavailableReason: 'NO_VETERINARIAN_ASSIGNED' as const,
};

let tree: ReactTestRenderer;
let alertSpy: jest.SpyInstance;
const t = (key: string, options?: Record<string, unknown>) => i18n.t(key, options);
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const findPressable = (label: string) =>
  tree.root.findAll(
    (node) =>
      (node.props.accessibilityRole === 'button' || node.props.accessibilityRole === 'radio') &&
      node.props.accessibilityLabel === label &&
      typeof node.props.onPress === 'function',
  )[0];
const has = (label: string) => findPressable(label) !== undefined;
async function press(label: string) {
  const node = findPressable(label);
  if (node === undefined) throw new Error(`No control labelled ${label}`);
  await act(async () => {
    node.props.onPress();
  });
}
const contentInput = () =>
  tree.root.findAllByType(TextInput).find((node) => node.props.multiline === true)!;
async function type(node: ReturnType<typeof contentInput>, value: string) {
  await act(async () => node.props.onChangeText(value));
}
async function render(appointment = row()) {
  appointmentRead.mockResolvedValue({ data: appointment, error: null });
  await act(async () => {
    tree = create(createElement(ProfessionalAppointmentDetailScreen));
  });
}
const EXAMINATION = () => t(categoryLabelKey('EXAMINATION'));
const CLINICAL_NOTE = () => t(categoryLabelKey('CLINICAL_NOTE'));
const VACCINATION = () => t(categoryLabelKey('VACCINATION'));
// The compact selector: open the field, then choose one category.
async function chooseCategory(label: string) {
  const field = tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityHint === t('clinicalRecord.categoryHint') &&
      typeof node.props.onPress === 'function',
  )[0];
  await act(async () => field.props.onPress());
  await press(label);
}
async function fillRecord(content = '  Peso 12 kg \n') {
  await press(t('clinicalRecord.addRecord'));
  await chooseCategory(EXAMINATION());
  await type(contentInput(), content);
}
const SAVE = () => t('clinicalRecord.saveRecord');
const SAVE_CHANGES = () => t('clinicalRecord.saveChanges');
const EDIT = (category = VACCINATION()) => t('clinicalRecord.editAccessibility', { category });
const VIEW_CHANGES = (category: string) =>
  t('clinicalRecord.viewChangesAccessibility', { category });
const recordedOn = (iso: string) =>
  t('clinicalRecord.recordedOn', { time: formatRecordedInstant(iso, 'Europe/Madrid', 'es') });
const lastPreventRemove = () => preventRemove.mock.calls.at(-1)?.[0];
const confirmAlerts = () =>
  alertSpy.mockImplementation((_title, _message, buttons?: AlertButton[]) => {
    buttons?.find((button) => button.style !== 'cancel')?.onPress?.();
  });

beforeEach(() => {
  jest.clearAllMocks();
  mockParams = { clinicId: 'clinic-a', appointmentId: 'appt-1' };
  i18n.locale = 'es';
  jest.spyOn(uuid, 'v4').mockReturnValue('key-1');
  jest.spyOn(AccessibilityInfo, 'announceForAccessibility').mockImplementation(() => {});
  alertSpy = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  withCapabilities(VETERINARIAN);
  contextRead.mockResolvedValue({
    data: { hasVeterinarianProfessionalProfile: true, organizations: [] },
    error: null,
  });
  assignmentRead.mockResolvedValue(loadedAssignment(assigned()));
  recordRead.mockResolvedValue(record());
});
afterEach(() => {
  act(() => tree.unmount());
  jest.restoreAllMocks();
  // Retired or protected operations are never reached from this screen.
  const rpcNames = (jest.requireMock('@/lib/supabase').supabase.rpc as jest.Mock).mock.calls.map(
    ([name]) => name,
  );
  for (const retired of [
    'start_appointment_clinical_encounter',
    'conclude_appointment_clinical_encounter',
    'create_appointment_clinical_draft',
    'update_appointment_clinical_draft',
    'finalize_appointment_clinical_entry',
    'view_appointment_professional_medical_history',
  ]) {
    expect(rpcNames).not.toContain(retired);
  }
});

describe('assignment (SPEC-APT-007 §13)', () => {
  it('an unassigned CONFIRMED Appointment says so, offers Assign me, and assigns nothing on open', async () => {
    assignmentRead.mockResolvedValue(loadedAssignment(UNASSIGNED));
    recordRead.mockResolvedValue(record(CANNOT_RECORD_UNASSIGNED));
    await render();
    expect(texts()).toEqual(
      expect.arrayContaining([
        t('veterinarianAssignment.unassigned'),
        t('clinicalRecord.unavailableNoVeterinarian'),
      ]),
    );
    expect(has(t('veterinarianAssignment.assignMe'))).toBe(true);
    expect(has(t('clinicalRecord.addRecord'))).toBe(false);
    expect(assignMe).not.toHaveBeenCalled();
    expect(assign).not.toHaveBeenCalled();
    expect(assignmentRead).toHaveBeenCalledWith('clinic-a', 'appt-1');
  });

  it('self-assignment is one tap with no dialog; the record re-reads and Add record appears', async () => {
    assignmentRead.mockResolvedValue(loadedAssignment(UNASSIGNED));
    recordRead.mockResolvedValue(record(CANNOT_RECORD_UNASSIGNED));
    await render();
    const recordReads = recordRead.mock.calls.length;
    assignMe.mockResolvedValue({ kind: 'outcome', outcome: 'ASSIGNED' });
    assignmentRead.mockResolvedValue(loadedAssignment(assigned()));
    recordRead.mockResolvedValue(record());
    await press(t('veterinarianAssignment.assignMe'));
    expect(alertSpy).not.toHaveBeenCalled();
    expect(assignMe).toHaveBeenCalledTimes(1);
    expect(assignMe).toHaveBeenCalledWith('clinic-a', 'appt-1');
    expect(recordRead.mock.calls.length).toBe(recordReads + 1);
    expect(texts()).toEqual(
      expect.arrayContaining([t('veterinarianAssignment.assignedToMe'), 'Ana García (Tú)']),
    );
    expect(has(t('veterinarianAssignment.assignMe'))).toBe(false);
    expect(has(t('clinicalRecord.addRecord'))).toBe(true);
    // Assigning creates no record.
    expect(createEntry).not.toHaveBeenCalled();
  });

  it('a colleague’s Appointment: no Assign me, one calm line, and neither edit nor clarify on their record', async () => {
    assignmentRead.mockResolvedValue(
      loadedAssignment(assigned({ displayName: 'Luis Pérez', isMe: false })),
    );
    recordRead.mockResolvedValue(
      record({
        canRecord: false,
        unavailableReason: 'NOT_ASSIGNED_VETERINARIAN',
        entries: [entry({ recordedByMe: false, mayEdit: false })],
      }),
    );
    await render();
    expect(texts()).toEqual(
      expect.arrayContaining([
        'Luis Pérez',
        t('clinicalRecord.unavailableNotAssigned'),
        'Peso 12 kg',
        `${recordedOn('2026-01-15T08:10:00Z')} · ${t('clinicalRecord.byAnother')}`,
      ]),
    );
    expect(has(t('veterinarianAssignment.assignMe'))).toBe(false);
    expect(has(t('clinicalRecord.addRecord'))).toBe(false);
    expect(has(EDIT(EXAMINATION()))).toBe(false);
    expect(texts()).not.toContain(t('clinicalRecord.clarify'));
    // Never edited: no history to show.
    expect(has(VIEW_CHANGES(EXAMINATION()))).toBe(false);
  });

  it('a stale assignment says the Veterinarian left, and the server may offer Assign me', async () => {
    assignmentRead.mockResolvedValue(
      loadedAssignment(
        assigned({ displayName: 'Luis Pérez', isMe: false, isEligible: false, mayAssignMe: true }),
      ),
    );
    await render();
    expect(texts()).toContain(t('veterinarianAssignment.stale'));
    expect(has(t('veterinarianAssignment.assignMe'))).toBe(true);
  });

  it('reception changes the Veterinarian: a short list, one confirmation naming both, the reviewed token', async () => {
    withCapabilities(RECEPTION);
    assignmentRead.mockResolvedValue(loadedAssignment(assigned({ isMe: false, mayManage: true })));
    candidatesRead.mockResolvedValue({
      kind: 'permitted',
      candidates: [
        {
          veterinarianClinicAssignmentId: 'vca-1',
          displayName: 'Ana García',
          isMe: false,
          isCurrentAssignee: true,
        },
        {
          veterinarianClinicAssignmentId: 'vca-2',
          displayName: 'Luis Pérez',
          isMe: false,
          isCurrentAssignee: false,
        },
      ],
    });
    await render();
    // Reception never triggers the audited record read.
    expect(recordRead).not.toHaveBeenCalled();
    await press(t('veterinarianAssignment.changeAccessibility'));
    expect(candidatesRead).toHaveBeenCalledWith('clinic-a', 'appt-1');
    expect(has(t('veterinarianAssignment.candidateAccessibility', { name: 'Ana García' }))).toBe(
      false,
    );
    confirmAlerts();
    assign.mockResolvedValue({ kind: 'outcome', outcome: 'REASSIGNED' });
    assignmentRead.mockResolvedValue(
      loadedAssignment(
        assigned({
          displayName: 'Luis Pérez',
          isMe: false,
          assignmentToken: 'token-2',
          mayManage: true,
        }),
      ),
    );
    await press(t('veterinarianAssignment.candidateAccessibility', { name: 'Luis Pérez' }));
    expect(alertSpy).toHaveBeenCalledTimes(1);
    expect(alertSpy.mock.calls[0][1]).toBe(
      t('veterinarianAssignment.changeDialogMessage', { from: 'Ana García', to: 'Luis Pérez' }),
    );
    expect(assign).toHaveBeenCalledWith('clinic-a', 'appt-1', 'vca-2', 'token-1');
    expect(texts()).toEqual(
      expect.arrayContaining([t('veterinarianAssignment.reassigned'), 'Luis Pérez']),
    );
    // The internal identifiers are never shown.
    expect(texts().join(' ')).not.toMatch(/vca-|token-/);
  });

  it('a first assignment by reception asks for no confirmation and sends no token', async () => {
    withCapabilities(RECEPTION);
    assignmentRead.mockResolvedValue(
      loadedAssignment({ kind: 'unassigned', mayAssignMe: false, mayManage: true }),
    );
    candidatesRead.mockResolvedValue({
      kind: 'permitted',
      candidates: [
        {
          veterinarianClinicAssignmentId: 'vca-2',
          displayName: 'Luis Pérez',
          isMe: false,
          isCurrentAssignee: false,
        },
      ],
    });
    assign.mockResolvedValue({ kind: 'outcome', outcome: 'ASSIGNED' });
    await render();
    await press(t('veterinarianAssignment.assignAccessibility'));
    await press(t('veterinarianAssignment.candidateAccessibility', { name: 'Luis Pérez' }));
    expect(alertSpy).not.toHaveBeenCalled();
    expect(assign).toHaveBeenCalledWith('clinic-a', 'appt-1', 'vca-2', null);
  });

  it('STALE_ASSIGNMENT re-reads and shows the current assignee calmly', async () => {
    withCapabilities(RECEPTION);
    assignmentRead.mockResolvedValue(loadedAssignment(assigned({ isMe: false, mayManage: true })));
    candidatesRead.mockResolvedValue({
      kind: 'permitted',
      candidates: [
        {
          veterinarianClinicAssignmentId: 'vca-2',
          displayName: 'Luis Pérez',
          isMe: false,
          isCurrentAssignee: false,
        },
      ],
    });
    await render();
    await press(t('veterinarianAssignment.changeAccessibility'));
    confirmAlerts();
    assign.mockResolvedValue({ kind: 'rejected', reason: 'STALE_ASSIGNMENT' });
    assignmentRead.mockResolvedValue(
      loadedAssignment(assigned({ displayName: 'Marta Ruiz', isMe: false, mayManage: true })),
    );
    await press(t('veterinarianAssignment.candidateAccessibility', { name: 'Luis Pérez' }));
    expect(assign).toHaveBeenCalledTimes(1);
    expect(texts()).toEqual(
      expect.arrayContaining([t('veterinarianAssignment.staleAssignment'), 'Marta Ruiz']),
    );
  });
});

describe('Save record (SPEC-MED-010 BR-23)', () => {
  it('opening the editor writes nothing; nothing is preselected; the notice says guardians will see it', async () => {
    await render();
    const reads = recordRead.mock.calls.length;
    await press(t('clinicalRecord.addRecord'));
    expect(createEntry).not.toHaveBeenCalled();
    expect(recordRead.mock.calls.length).toBe(reads);
    expect(texts()).toContain(t('clinicalRecord.publishNotice'));
    expect(texts()).toContain(t('clinicalRecord.categoryPrompt'));
    const selected = tree.root.findAll(
      (node) => node.props.accessibilityRole === 'radio' && node.props.accessibilityState?.selected,
    );
    expect(selected).toHaveLength(0);
    // The compact selector: the ten categories only once it is opened.
    expect(has(EXAMINATION())).toBe(false);
    // No clinical time, no care start or end, no draft, no second confirmation.
    expect(texts().join(' ')).not.toMatch(
      /Momento clínico|Ahora|Otra hora|inicio de la atención|fin de la atención|borrador/i,
    );
    expect(tree.root.findAllByType(TextInput)).toHaveLength(1);
    expect(lastPreventRemove()).toBe(false);
  });

  it('asks for a category and content before sending anything', async () => {
    await render();
    await press(t('clinicalRecord.addRecord'));
    await press(SAVE());
    expect(texts()).toContain(t('clinicalRecord.categoryRequired'));
    await chooseCategory(EXAMINATION());
    await press(SAVE());
    expect(texts()).toContain(t('clinicalRecord.contentRequired'));
    expect(createEntry).not.toHaveBeenCalled();
  });

  it('one tap sends one request with the editor key, re-reads, closes the editor and re-reads the Appointment', async () => {
    await render();
    await fillRecord();
    expect(lastPreventRemove()).toBe(true);
    const appointmentReads = appointmentRead.mock.calls.length;
    createEntry.mockResolvedValue({ kind: 'outcome', outcome: 'CREATED', entryId: 'entry-9' });
    recordRead.mockResolvedValue(record({ entries: [entry({ entryId: 'entry-9' })] }));
    await press(SAVE());
    expect(alertSpy).not.toHaveBeenCalled();
    expect(createEntry).toHaveBeenCalledTimes(1);
    // No clinical time is sent: the server records its own.
    expect(createEntry).toHaveBeenCalledWith('clinic-a', 'appt-1', 'key-1', {
      category: 'EXAMINATION',
      clinicalContent: 'Peso 12 kg',
      otherCategoryContext: null,
    });
    expect(texts()).toEqual(
      expect.arrayContaining([
        t('clinicalRecord.saved'),
        'Peso 12 kg',
        `${recordedOn('2026-01-15T08:10:00Z')} · ${t('clinicalRecord.byYou')}`,
      ]),
    );
    expect(has(t('clinicalRecord.addRecord'))).toBe(true);
    expect(texts()).not.toContain(t('clinicalRecord.publishNotice'));
    expect(appointmentRead.mock.calls.length).toBe(appointmentReads + 1);
    expect(AccessibilityInfo.announceForAccessibility).toHaveBeenCalledWith(
      t('clinicalRecord.saved'),
    );
    expect(lastPreventRemove()).toBe(false);
  });

  it('a second tap while saving sends nothing more', async () => {
    await render();
    await fillRecord();
    let finish: (value: unknown) => void = () => {};
    createEntry.mockImplementation(() => new Promise((resolve) => (finish = resolve)));
    await press(SAVE());
    await act(async () => {
      findPressable(SAVE())?.props.onPress();
    });
    expect(createEntry).toHaveBeenCalledTimes(1);
    await act(async () => finish({ kind: 'outcome', outcome: 'CREATED', entryId: 'entry-9' }));
  });

  it('a lost response keeps the text; the retry reuses the key and ALREADY_CREATED is saved', async () => {
    await render();
    await fillRecord();
    createEntry.mockResolvedValueOnce({ kind: 'uncertain' });
    await press(SAVE());
    expect(texts()).toContain(t('clinicalRecord.unconfirmedSave'));
    expect(contentInput().props.value).toBe('  Peso 12 kg \n');
    createEntry.mockResolvedValueOnce({
      kind: 'outcome',
      outcome: 'ALREADY_CREATED',
      entryId: 'entry-9',
    });
    await press(SAVE());
    expect(createEntry).toHaveBeenCalledTimes(2);
    expect(createEntry.mock.calls[0][2]).toBe('key-1');
    expect(createEntry.mock.calls[1][2]).toBe('key-1');
    expect(texts()).toContain(t('clinicalRecord.saved'));
  });

  it('a lost response that the re-read shows as recorded is saved without resubmitting', async () => {
    recordRead.mockResolvedValue(record({ entries: [entry()] }));
    await render();
    // The same text as an earlier record: only a NEW one of mine counts.
    await fillRecord('Peso 12 kg');
    createEntry.mockResolvedValueOnce({ kind: 'uncertain' });
    recordRead.mockResolvedValue(record({ entries: [entry(), entry({ entryId: 'entry-9' })] }));
    await press(SAVE());
    expect(createEntry).toHaveBeenCalledTimes(1);
    expect(texts()).toContain(t('clinicalRecord.saved'));
  });

  it('a missing Entitlement keeps the text and says the clinical service is unavailable', async () => {
    await render();
    await fillRecord();
    createEntry.mockResolvedValue({ kind: 'serviceUnavailable' });
    recordRead.mockResolvedValue(
      record({ canRecord: false, unavailableReason: 'CLINICAL_SERVICE_UNAVAILABLE' }),
    );
    await press(SAVE());
    expect(texts()).toContain(t('clinicalRecord.serviceUnavailable'));
    expect(contentInput().props.value).toBe('  Peso 12 kg \n');
  });

  it('a reassignment while writing keeps the text and re-reads who has the Appointment', async () => {
    await render();
    await fillRecord();
    const assignmentReads = assignmentRead.mock.calls.length;
    createEntry.mockResolvedValue({ kind: 'rejected', reason: 'NOT_ASSIGNED_VETERINARIAN' });
    assignmentRead.mockResolvedValue(
      loadedAssignment(assigned({ displayName: 'Luis Pérez', isMe: false })),
    );
    recordRead.mockResolvedValue(
      record({ canRecord: false, unavailableReason: 'NOT_ASSIGNED_VETERINARIAN' }),
    );
    await press(SAVE());
    expect(contentInput().props.value).toBe('  Peso 12 kg \n');
    expect(assignmentRead.mock.calls.length).toBe(assignmentReads + 1);
    expect(texts()).toEqual(
      expect.arrayContaining([t('clinicalRecord.unavailableNotAssigned'), 'Luis Pérez']),
    );
  });

  it('a uniform denial keeps the typed text on screen even though the record becomes unavailable', async () => {
    await render();
    await fillRecord();
    createEntry.mockResolvedValue({ kind: 'denied' });
    recordRead.mockResolvedValue({ kind: 'denied' });
    await press(SAVE());
    expect(texts()).toEqual(
      expect.arrayContaining([t('clinicalRecord.unavailable'), t('clinicalRecord.saveDenied')]),
    );
    expect(contentInput().props.value).toBe('  Peso 12 kg \n');
  });

  it('OTHER asks for its context, and only OTHER', async () => {
    await render();
    await press(t('clinicalRecord.addRecord'));
    await chooseCategory(t(categoryLabelKey('OTHER')));
    expect(tree.root.findAllByType(TextInput)).toHaveLength(2);
    await type(contentInput(), 'Revisión de comportamiento');
    await press(SAVE());
    expect(texts()).toContain(t('clinicalRecord.otherContextRequired'));
    expect(createEntry).not.toHaveBeenCalled();
  });

  it('the detail reads in visit order: summary with the Veterinarian and the contact, Clinical record with previous records, then Appointment management with Complete', async () => {
    await render();
    const shown = texts();
    const order = [
      t('professionalAppointment.dateTimeLabel'),
      t('professionalAppointment.reasonLabel'),
      t('veterinarianAssignment.title'),
      t('appointmentContact.heading'),
      t('clinicalRecord.sectionTitle'),
      t('professionalHistory.action'),
      t('professionalAppointment.managementTitle'),
      t('appointmentCompletion.action'),
    ].map((label) => shown.indexOf(label));
    expect(order.every((index) => index >= 0)).toBe(true);
    expect([...order].sort((a, b) => a - b)).toEqual(order);
  });

  it('the Veterinarian shares the summary card; previous records close the Clinical record card; Complete stays outside it', async () => {
    await render();
    // The Veterinarian row's card is the one holding the date, time and reason.
    const summaryTexts = tree.root
      .findByType(AppointmentVeterinarianSection)
      .parent!.findAllByType(Text)
      .map((node) => String(node.props.children));
    expect(summaryTexts).toEqual(
      expect.arrayContaining([
        t('professionalAppointment.dateTimeLabel'),
        t('professionalAppointment.reasonLabel'),
        t('veterinarianAssignment.title'),
      ]),
    );
    const card = tree.root.findByType(AppointmentClinicalRecordSection);
    const inCard = (label: string) =>
      card.findAll(
        (node) =>
          node.props.accessibilityLabel === label && typeof node.props.onPress === 'function',
      ).length > 0;
    expect(inCard(t('clinicalRecord.addRecord'))).toBe(true);
    expect(inCard(t('professionalHistory.action'))).toBe(true);
    // A state change of the Appointment, not an action of its record.
    expect(has(t('appointmentCompletion.action'))).toBe(true);
    expect(inCard(t('appointmentCompletion.action'))).toBe(false);
  });

  it('while the editor is open Complete is not shown; it returns once the editor closes', async () => {
    await render();
    expect(has(t('appointmentCompletion.action'))).toBe(true);
    expect(texts()).not.toContain(t('appointmentCompletion.editorOpenHint'));
    await press(t('clinicalRecord.addRecord'));
    expect(has(t('appointmentCompletion.action'))).toBe(false);
    // Said where Complete would be, so it never silently disappears.
    expect(texts()).toContain(t('appointmentCompletion.editorOpenHint'));
    await press(t('clinicalRecord.cancelEditor'));
    expect(has(t('appointmentCompletion.action'))).toBe(true);
    expect(texts()).not.toContain(t('appointmentCompletion.editorOpenHint'));
  });

  it('with unsaved changes in the editor Complete stays held back', async () => {
    await render();
    await fillRecord();
    expect(has(t('appointmentCompletion.action'))).toBe(false);
    expect(texts()).toContain(t('appointmentCompletion.editorOpenHint'));
  });

  it('cancelling with unsaved text asks first; an empty editor just closes', async () => {
    await render();
    await press(t('clinicalRecord.addRecord'));
    await press(t('clinicalRecord.cancelEditor'));
    expect(alertSpy).not.toHaveBeenCalled();
    expect(texts()).not.toContain(t('clinicalRecord.publishNotice'));
    await fillRecord();
    confirmAlerts();
    await press(t('clinicalRecord.cancelEditor'));
    expect(alertSpy).toHaveBeenCalledWith(
      t('clinicalRecord.discardTitle'),
      t('clinicalRecord.discardMessage'),
      expect.any(Array),
      expect.anything(),
    );
    expect(texts()).not.toContain(t('clinicalRecord.publishNotice'));
    expect(createEntry).not.toHaveBeenCalled();
  });

  it('never logs clinical content', async () => {
    const spies = (['log', 'info', 'warn', 'error'] as const).map((method) =>
      jest.spyOn(console, method).mockImplementation(() => {}),
    );
    await render();
    await fillRecord('Diagnóstico confidencial');
    createEntry.mockResolvedValue({ kind: 'uncertain' });
    await press(SAVE());
    for (const spy of spies) {
      expect(JSON.stringify(spy.mock.calls)).not.toContain('Diagnóstico confidencial');
    }
  });
});

describe('Edit (SPEC-MED-010 BR-18, BR-23b)', () => {
  it('the author edits category and text; no reason, no second confirmation; the card shows the current version', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    expect(tree.root.findAllByType(TextInput)).toHaveLength(0);
    await press(EDIT());
    // The same editor, filled with the current version; Complete steps aside.
    expect(contentInput().props.value).toBe('Vacuna de la rabia anual');
    expect(texts()).toEqual(
      expect.arrayContaining([t('clinicalRecord.editorEditTitle'), VACCINATION()]),
    );
    expect(texts()).not.toContain(t('clinicalRecord.publishNotice'));
    // No reason is asked for: the clinical text is the only field.
    expect(tree.root.findAllByType(TextInput)).toHaveLength(1);
    expect(texts().join(' ')).not.toMatch(/Motivo de la (rectificación|corrección)|Rectific/);
    expect(has(t('appointmentCompletion.action'))).toBe(false);
    expect(lastPreventRemove()).toBe(false);
    await chooseCategory(CLINICAL_NOTE());
    await type(contentInput(), 'Solo se realizó un corte de uñas');
    expect(lastPreventRemove()).toBe(true);
    editEntry.mockResolvedValue({ kind: 'outcome', outcome: 'EDITED', version: 2 });
    recordRead.mockResolvedValue(record({ entries: [corrected()] }));
    await press(SAVE_CHANGES());
    expect(alertSpy).not.toHaveBeenCalled();
    expect(createEntry).not.toHaveBeenCalled();
    expect(editEntry).toHaveBeenCalledTimes(1);
    expect(editEntry).toHaveBeenCalledWith('clinic-a', 'appt-1', 'entry-1', 'key-1', 1, {
      category: 'CLINICAL_NOTE',
      clinicalContent: 'Solo se realizó un corte de uñas',
      otherCategoryContext: null,
    });
    // The main card: Clinical note and the corrected text, the original date, a discreet Edited.
    const shown = texts();
    expect(shown).toEqual(
      expect.arrayContaining([
        t('clinicalRecord.changesSaved'),
        CLINICAL_NOTE(),
        'Solo se realizó un corte de uñas',
        `${recordedOn('2026-01-15T08:10:00Z')} · ${t('clinicalRecord.byYou')}`,
        t('clinicalRecord.editedAt', {
          time: formatRecordedInstant('2026-01-15T09:00:00Z', 'Europe/Madrid', 'es'),
        }),
      ]),
    );
    expect(shown).not.toContain('Vacuna de la rabia anual');
    expect(has(t('appointmentCompletion.action'))).toBe(true);
    expect(lastPreventRemove()).toBe(false);
    // View changes shows the original version, what, when and who.
    await press(VIEW_CHANGES(CLINICAL_NOTE()));
    expect(texts()).toEqual(
      expect.arrayContaining([
        t('clinicalRecord.originalVersion'),
        VACCINATION(),
        'Vacuna de la rabia anual',
        `${recordedOn('2026-01-15T08:10:00Z')} · ${t('clinicalRecord.byYou')}`,
      ]),
    );
  });

  it('an unchanged edit closes without asking; a changed one asks before discarding', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await press(t('clinicalRecord.cancelEditor'));
    expect(alertSpy).not.toHaveBeenCalled();
    expect(tree.root.findAllByType(TextInput)).toHaveLength(0);
    await press(EDIT());
    await type(contentInput(), 'Vacuna de la rabia trianual');
    confirmAlerts();
    await press(t('clinicalRecord.cancelEditor'));
    expect(alertSpy).toHaveBeenCalledWith(
      t('clinicalRecord.discardTitle'),
      t('clinicalRecord.discardMessage'),
      expect.any(Array),
      expect.anything(),
    );
    expect(editEntry).not.toHaveBeenCalled();
  });

  it('several edits in a row each open on the current version with a new key', async () => {
    const keys = jest.spyOn(uuid, 'v4');
    keys.mockReturnValueOnce('key-a').mockReturnValueOnce('key-b');
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await chooseCategory(CLINICAL_NOTE());
    await type(contentInput(), 'Solo se realizó un corte de uñas');
    editEntry.mockResolvedValueOnce({ kind: 'outcome', outcome: 'EDITED', version: 2 });
    recordRead.mockResolvedValue(record({ entries: [corrected()] }));
    await press(SAVE_CHANGES());
    await press(EDIT(CLINICAL_NOTE()));
    await type(contentInput(), 'Corte de uñas y limpieza de oídos');
    editEntry.mockResolvedValueOnce({ kind: 'outcome', outcome: 'EDITED', version: 3 });
    await press(SAVE_CHANGES());
    expect(editEntry.mock.calls.map((call) => [call[3], call[4]])).toEqual([
      ['key-a', 1],
      ['key-b', 2],
    ]);
  });

  it('a stale version keeps the text, shows the newer version, and the next save applies on top of it', async () => {
    const keys = jest.spyOn(uuid, 'v4');
    keys.mockReturnValueOnce('key-a').mockReturnValueOnce('key-b');
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await type(contentInput(), 'Mi corrección');
    editEntry.mockResolvedValueOnce({ kind: 'rejected', reason: 'STALE_VERSION' });
    recordRead.mockResolvedValue(
      record({ entries: [corrected({ clinicalContent: 'Cambio desde otro dispositivo' })] }),
    );
    await press(SAVE_CHANGES());
    expect(contentInput().props.value).toBe('Mi corrección');
    expect(texts()).toEqual(
      expect.arrayContaining([t('clinicalRecord.staleVersion'), 'Cambio desde otro dispositivo']),
    );
    editEntry.mockResolvedValueOnce({ kind: 'outcome', outcome: 'EDITED', version: 3 });
    await press(SAVE_CHANGES());
    expect(editEntry.mock.calls.map((call) => [call[3], call[4]])).toEqual([
      ['key-a', 1],
      ['key-b', 2],
    ]);
    expect(texts()).toContain(t('clinicalRecord.changesSaved'));
  });

  it('a lost response keeps the text; the retry reuses the key and ALREADY_EDITED is saved', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await type(contentInput(), 'Solo se realizó un corte de uñas');
    editEntry.mockResolvedValueOnce({ kind: 'uncertain' });
    await press(SAVE_CHANGES());
    expect(texts()).toContain(t('clinicalRecord.unconfirmedEdit'));
    expect(contentInput().props.value).toBe('Solo se realizó un corte de uñas');
    editEntry.mockResolvedValueOnce({ kind: 'outcome', outcome: 'ALREADY_EDITED', version: 2 });
    await press(SAVE_CHANGES());
    expect(editEntry.mock.calls.map((call) => [call[3], call[4]])).toEqual([
      ['key-1', 1],
      ['key-1', 1],
    ]);
    expect(texts()).toContain(t('clinicalRecord.changesSaved'));
  });

  it('a lost response that the re-read shows as the current version is saved without resubmitting', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await chooseCategory(CLINICAL_NOTE());
    await type(contentInput(), 'Solo se realizó un corte de uñas');
    editEntry.mockResolvedValueOnce({ kind: 'uncertain' });
    recordRead.mockResolvedValue(record({ entries: [corrected()] }));
    await press(SAVE_CHANGES());
    expect(editEntry).toHaveBeenCalledTimes(1);
    expect(texts()).toContain(t('clinicalRecord.changesSaved'));
  });

  it('a lost permission keeps the text on screen even though the record becomes unavailable', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await type(contentInput(), 'Solo se realizó un corte de uñas');
    editEntry.mockResolvedValue({ kind: 'denied' });
    recordRead.mockResolvedValue({ kind: 'denied' });
    await press(SAVE_CHANGES());
    expect(texts()).toEqual(
      expect.arrayContaining([t('clinicalRecord.unavailable'), t('clinicalRecord.editDenied')]),
    );
    expect(contentInput().props.value).toBe('Solo se realizó un corte de uñas');
  });

  it('never logs clinical content while editing', async () => {
    const spies = (['log', 'info', 'warn', 'error'] as const).map((method) =>
      jest.spyOn(console, method).mockImplementation(() => {}),
    );
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    await press(EDIT());
    await type(contentInput(), 'Diagnóstico confidencial');
    editEntry.mockResolvedValue({ kind: 'uncertain' });
    await press(SAVE_CHANGES());
    for (const spy of spies) {
      expect(JSON.stringify(spy.mock.calls)).not.toContain('Diagnóstico confidencial');
      expect(JSON.stringify(spy.mock.calls)).not.toContain('Vacuna de la rabia anual');
    }
  });
});

describe('after completion, editing and clarification', () => {
  it('a COMPLETED Appointment can still be documented; Complete is gone', async () => {
    recordRead.mockResolvedValue(record({ appointmentLifecycleState: 'COMPLETED' }));
    await render(row({ lifecycleState: 'COMPLETED' }));
    expect(has(t('appointmentCompletion.action'))).toBe(false);
    expect(has(t('clinicalRecord.addRecord'))).toBe(true);
    await fillRecord();
    createEntry.mockResolvedValue({ kind: 'outcome', outcome: 'CREATED', entryId: 'entry-9' });
    await press(SAVE());
    expect(texts()).toContain(t('clinicalRecord.saved'));
  });

  it('the author still edits a record of a COMPLETED Appointment, on the same screen', async () => {
    const { router } = jest.requireMock('expo-router');
    recordRead.mockResolvedValue(
      record({ appointmentLifecycleState: 'COMPLETED', entries: [vaccination()] }),
    );
    await render(row({ lifecycleState: 'COMPLETED' }));
    await press(EDIT());
    await type(contentInput(), 'Vacuna de la rabia, segunda dosis');
    editEntry.mockResolvedValue({ kind: 'outcome', outcome: 'EDITED', version: 2 });
    await press(SAVE_CHANGES());
    expect(editEntry).toHaveBeenCalledTimes(1);
    expect(router.push).not.toHaveBeenCalled();
  });

  it('on another Veterinarian’s record the assignee adds a clarifying record, never an edit', async () => {
    recordRead.mockResolvedValue(
      record({
        entries: [
          entry({
            recordedByMe: false,
            mayEdit: false,
            amendments: [
              {
                amendmentId: 'am-1',
                reason: 'Dosis',
                amendmentContent: 'Son 5 mg',
                createdAt: '2026-01-16T08:00:00Z',
                amendedByMe: false,
              },
            ],
          }),
        ],
      }),
    );
    await render();
    // A historical correction stays readable, under View changes.
    expect(texts()).not.toContain('Son 5 mg');
    await press(VIEW_CHANGES(EXAMINATION()));
    expect(texts()).toEqual(
      expect.arrayContaining([t('clinicalRecord.earlierCorrection'), 'Son 5 mg']),
    );
    expect(has(EDIT(EXAMINATION()))).toBe(false);
    await press(t('clinicalRecord.clarifyAccessibility', { category: EXAMINATION() }));
    expect(texts()).toEqual(
      expect.arrayContaining([
        t('clinicalRecord.editorClarifyTitle'),
        t('clinicalRecord.clarifyNote'),
      ]),
    );
    await chooseCategory(EXAMINATION());
    await type(contentInput(), 'Aclaro la pauta');
    createEntry.mockResolvedValue({ kind: 'outcome', outcome: 'CREATED', entryId: 'entry-9' });
    await press(SAVE());
    // An ordinary new record: no reference to the original.
    expect(createEntry.mock.calls[0][3]).toEqual({
      category: 'EXAMINATION',
      clinicalContent: 'Aclaro la pauta',
      otherCategoryContext: null,
    });
    expect(editEntry).not.toHaveBeenCalled();
  });
});

describe('the Clinical record card (compact list)', () => {
  const rows = () => tree.root.findAllByType(ClinicalRecordEntryRow);
  const contentText = (content: string) =>
    tree.root.findAllByType(Text).find((node) => node.props.children === content)!;
  const READ_MORE = (category: string) => t('clinicalRecord.readMoreAccessibility', { category });
  const READ_LESS = (category: string) => t('clinicalRecord.readLessAccessibility', { category });

  it('with no records: one card, a simple empty line and a compact Add in its header', async () => {
    await render();
    expect(tree.root.findAllByType(AppointmentClinicalRecordSection)).toHaveLength(1);
    expect(rows()).toHaveLength(0);
    expect(texts()).toContain(t('clinicalRecord.noEntries'));
    expect(has(t('clinicalRecord.addRecord'))).toBe(true);
    // Visibly short; its accessible name says what it adds.
    expect(texts()).toContain(t('clinicalRecord.add'));
    expect(texts()).not.toContain(t('clinicalRecord.addRecord'));
  });

  it('with one record: one row, no empty line', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination()] }));
    await render();
    expect(rows()).toHaveLength(1);
    expect(texts()).not.toContain(t('clinicalRecord.noEntries'));
    expect(texts()).toEqual(expect.arrayContaining([VACCINATION(), 'Vacuna de la rabia anual']));
  });

  it('with several records: rows in one card, each with only the icons it may offer', async () => {
    recordRead.mockResolvedValue(
      record({
        entries: [
          vaccination({ entryId: 'entry-1' }),
          entry({ entryId: 'entry-2', recordedByMe: false, mayEdit: false }),
          corrected({ entryId: 'entry-3' }),
        ],
      }),
    );
    await render();
    expect(tree.root.findAllByType(AppointmentClinicalRecordSection)).toHaveLength(1);
    expect(rows().map((row) => row.props.entry.entryId)).toEqual(['entry-1', 'entry-2', 'entry-3']);
    // The pencil only on the reader's own, editable records.
    expect(has(EDIT(VACCINATION()))).toBe(true);
    expect(has(EDIT(CLINICAL_NOTE()))).toBe(true);
    expect(has(EDIT(EXAMINATION()))).toBe(false);
    // The history icon only where earlier versions exist.
    expect(has(VIEW_CHANGES(CLINICAL_NOTE()))).toBe(true);
    expect(has(VIEW_CHANGES(VACCINATION()))).toBe(false);
    expect(has(VIEW_CHANGES(EXAMINATION()))).toBe(false);
    // Another Veterinarian's record offers the clarifying record instead.
    expect(has(t('clinicalRecord.clarifyAccessibility', { category: EXAMINATION() }))).toBe(true);
  });

  it('an own record the server no longer lets the reader edit shows no pencil', async () => {
    recordRead.mockResolvedValue(record({ entries: [vaccination({ mayEdit: false })] }));
    await render();
    expect(has(EDIT(VACCINATION()))).toBe(false);
    expect(texts()).toContain('Vacuna de la rabia anual');
  });

  it('the history icon shows and hides the earlier versions in place, saying which state it is in', async () => {
    recordRead.mockResolvedValue(record({ entries: [corrected()] }));
    await render();
    expect(texts()).not.toContain(t('clinicalRecord.originalVersion'));
    expect(findPressable(VIEW_CHANGES(CLINICAL_NOTE())).props.accessibilityState.expanded).toBe(
      false,
    );
    await press(VIEW_CHANGES(CLINICAL_NOTE()));
    expect(texts()).toContain(t('clinicalRecord.originalVersion'));
    const hide = t('clinicalRecord.hideChangesAccessibility', { category: CLINICAL_NOTE() });
    expect(findPressable(hide).props.accessibilityState.expanded).toBe(true);
    await press(hide);
    expect(texts()).not.toContain(t('clinicalRecord.originalVersion'));
  });

  it('a long record starts collapsed with "Read in full", never cut silently; screen readers get it whole', async () => {
    const long = 'Exploración completa sin hallazgos relevantes. '.repeat(8).trim();
    recordRead.mockResolvedValue(record({ entries: [entry({ clinicalContent: long })] }));
    await render();
    expect(contentText(long).props.numberOfLines).toBe(6);
    expect(contentText(long).props.accessibilityLabel).toBe(long);
    expect(texts()).toContain(t('clinicalRecord.readMore'));
    await press(READ_MORE(EXAMINATION()));
    expect(contentText(long).props.numberOfLines).toBeUndefined();
    expect(findPressable(READ_LESS(EXAMINATION())).props.accessibilityState.expanded).toBe(true);
    await press(READ_LESS(EXAMINATION()));
    expect(contentText(long).props.numberOfLines).toBe(6);
  });

  it('a record of many short lines is long too; a short record is always shown whole', async () => {
    const lines = ['Peso 12 kg', 'T 38,5', 'FC 90', 'FR 24', 'Mucosas rosadas', 'TRC < 2 s'].join(
      '\n',
    );
    recordRead.mockResolvedValue(
      record({
        entries: [
          entry({ entryId: 'entry-1', clinicalContent: lines }),
          vaccination({ entryId: 'entry-2' }),
        ],
      }),
    );
    await render();
    expect(contentText(lines).props.numberOfLines).toBe(6);
    expect(has(READ_MORE(EXAMINATION()))).toBe(true);
    expect(contentText('Vacuna de la rabia anual').props.numberOfLines).toBeUndefined();
    expect(has(READ_MORE(VACCINATION()))).toBe(false);
  });

  it('while an editor is open, no other record offers its pencil and Add steps aside', async () => {
    recordRead.mockResolvedValue(
      record({ entries: [vaccination({ entryId: 'entry-1' }), corrected({ entryId: 'entry-2' })] }),
    );
    await render();
    await press(EDIT(VACCINATION()));
    expect(has(EDIT(CLINICAL_NOTE()))).toBe(false);
    expect(has(t('clinicalRecord.addRecord'))).toBe(false);
    // The editor opens inside the same card, beneath its record.
    const card = tree.root.findByType(AppointmentClinicalRecordSection);
    expect(card.findAllByType(TextInput)).toHaveLength(1);
  });
});

describe('context changes', () => {
  it('another Appointment starts from nothing: the unsaved editor is gone and every read is re-keyed', async () => {
    await render();
    await fillRecord();
    mockParams = { clinicId: 'clinic-a', appointmentId: 'appt-2' };
    appointmentRead.mockResolvedValue({ data: row({ id: 'appt-2', petName: 'Max' }), error: null });
    await act(async () => {
      tree.update(createElement(ProfessionalAppointmentDetailScreen));
    });
    expect(texts()).toContain('Max');
    expect(texts()).not.toContain(t('clinicalRecord.publishNotice'));
    expect(recordRead).toHaveBeenLastCalledWith('clinic-a', 'appt-2');
    expect(assignmentRead).toHaveBeenLastCalledWith('clinic-a', 'appt-2');
  });

  it('another professional context (Clinic) re-keys the reads to that Clinic only', async () => {
    await render();
    mockParams = { clinicId: 'clinic-b', appointmentId: 'appt-1' };
    withCapabilities(VETERINARIAN, 'clinic-b');
    await act(async () => {
      tree.update(createElement(ProfessionalAppointmentDetailScreen));
    });
    expect(recordRead).toHaveBeenLastCalledWith('clinic-b', 'appt-1');
    expect(assignmentRead).toHaveBeenLastCalledWith('clinic-b', 'appt-1');
  });

  it('opening the detail reads the assignment and the record once each, and writes nothing', async () => {
    await render();
    expect(recordRead).toHaveBeenCalledTimes(1);
    expect(assignmentRead).toHaveBeenCalledTimes(1);
    expect(assignMe).not.toHaveBeenCalled();
    expect(assign).not.toHaveBeenCalled();
    expect(createEntry).not.toHaveBeenCalled();
  });
});

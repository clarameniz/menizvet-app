import { createElement } from 'react';
import {
  AccessibilityInfo,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  type AlertButton,
} from 'react-native';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import AppointmentDetailScreen from '@/app/appointments/[id]';
import { Button } from '@/components/design-system/button';
import {
  getPetAppointments,
  withdrawAppointmentMedicalAccess,
  type MedicalAccessState,
  type PetAppointment,
} from '@/data/appointments';
import { i18n } from '@/i18n/i18n';

/**
 * Guardian Appointment detail — medical access (SPEC-ACC-002 §16,
 * SPEC-APT-011 BR-35): while the state is ACTIVE, in any lifecycle, the active
 * status and a secondary "Manage medical access"; withdrawal only inside that
 * panel, with lifecycle-specific consequences, after a short final
 * confirmation; only the Appointment id is sent; the authoritative re-read
 * decides what is shown, so an uncertain response or a retry is calm.
 */

let mockLocale = 'es';
// The screen's latest focus callback, to simulate returning to it.
let mockFocus: (() => void | (() => void)) | null = null;
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: 'appt-1', petId: 'pet-1' }),
  useFocusEffect: (callback: () => void | (() => void)) => {
    const React = jest.requireActual('react');
    React.useEffect(() => {
      mockFocus = callback;
      return callback();
    }, [callback]);
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
  return {
    useLocale: () => ({
      locale: mockLocale,
      t: (key: string, options?: Record<string, unknown>) =>
        mockI18n.t(key, { ...options, locale: mockLocale }),
    }),
  };
});
jest.mock('@/data/appointments', () => ({
  ...jest.requireActual('@/data/appointments'),
  getPetAppointments: jest.fn(),
  getAppointmentSchedulingHistory: jest.fn(async () => ({ data: [], error: null })),
  getAppointmentVeterinarianAssignmentHistory: jest.fn(async () => ({ data: [], error: null })),
  withdrawAppointmentMedicalAccess: jest.fn(),
}));
jest.mock('@/data/clinics', () => ({
  getPublishedClinicProfilesByIds: jest.fn(async () => ({
    data: new Map([['clinic-1', { displayName: 'Clínica Norte' }]]),
    error: null,
  })),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const read = getPetAppointments as jest.Mock;
const withdraw = withdrawAppointmentMedicalAccess as jest.Mock;

const appointment = (
  medicalAccessState: MedicalAccessState,
  lifecycleState: PetAppointment['lifecycleState'] = 'CONFIRMED',
): PetAppointment => ({
  id: 'appt-1',
  clinicId: 'clinic-1',
  requestingUserId: 'user-1',
  reasonForVisit: 'Revisión anual',
  guardianNotes: null,
  lifecycleState,
  createdAt: '2026-01-01T00:00:00Z',
  currentScheduledStartAt: '2035-06-01T08:00:00Z',
  currentScheduledEndAt: '2035-06-01T08:30:00Z',
  currentSchedulingTimezoneName: 'Europe/Madrid',
  currentVeterinarianClinicAssignmentId: null,
  pendingReschedule: null,
  cancellationReason: lifecycleState === 'CANCELLED' ? 'Clinic closed' : null,
  currentScheduleSource: null,
  medicalAccessState,
});

let tree: ReactTestRenderer;
let alertSpy: jest.SpyInstance;
const t = (key: string) => i18n.t(key, { locale: mockLocale });
const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const allText = () => texts().join(' | ');
const findButton = (label: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      node.props.accessibilityLabel === label &&
      typeof node.props.onPress === 'function',
  )[0];
const manageButton = () => findButton(t('medicalAccess.manageActionAccessibility'));
const manageButtonElement = () =>
  tree.root
    .findAllByType(Button)
    .find((node) => node.props.label === t('medicalAccess.manageAction'));
const withdrawButton = () => findButton(t('medicalAccess.withdrawActionAccessibility'));
const withdrawButtonElement = () =>
  tree.root
    .findAllByType(Button)
    .find((node) => node.props.label === t('medicalAccess.withdrawAction'));
const backButton = () => findButton(t('medicalAccess.panelBack'));
const allButtonLabels = () =>
  tree.root
    .findAll(
      (node) =>
        node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
    )
    .map((node) => String(node.props.accessibilityLabel));

async function render(...reads: PetAppointment[]) {
  for (const value of reads) read.mockResolvedValueOnce({ data: [value], error: null });
  await act(async () => {
    tree = create(createElement(AppointmentDetailScreen));
  });
}
async function openPanel() {
  await act(async () => {
    manageButton().props.onPress();
  });
}
async function openDialog() {
  if (withdrawButton() === undefined) await openPanel();
  await act(async () => {
    withdrawButton().props.onPress();
  });
  const [, , buttons] = alertSpy.mock.calls[alertSpy.mock.calls.length - 1] as [
    string,
    string,
    AlertButton[],
  ];
  return buttons;
}
async function confirm() {
  const buttons = await openDialog();
  await act(async () => {
    buttons[1].onPress?.();
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  read.mockReset();
  withdraw.mockReset();
  mockLocale = 'es';
  alertSpy = jest.spyOn(Alert, 'alert').mockImplementation(() => undefined);
});
afterEach(() => {
  alertSpy.mockRestore();
  act(() => tree.unmount());
});

it('shows the active status, a short explanation and a secondary Manage action — no destructive control yet', async () => {
  await render(appointment('ACTIVE'));
  expect(texts()).toEqual(
    expect.arrayContaining([
      'Acceso médico',
      'Acceso médico activo',
      t('medicalAccess.activeBody'),
    ]),
  );
  expect(
    tree.root.findAll(
      (node) =>
        node.props.accessibilityRole === 'header' && node.props.children === 'Acceso médico',
    ),
  ).not.toHaveLength(0);
  expect(manageButtonElement()?.props.variant).toBe('secondary');
  expect(manageButton().props.accessibilityLabel).toBe('Gestionar el acceso médico de esta cita');
  // No withdrawal control of any kind until the panel is opened.
  expect(withdrawButton()).toBeUndefined();
  expect(withdrawButtonElement()).toBeUndefined();
  expect(allText()).not.toMatch(
    /[Aa]utorizaci[oó]n|[Aa]uthorization|CLINICAL_|ENTITLEMENT|\bACTIVE\b|REVOKED/,
  );
});

it('opening the panel calls nothing and shows the destructive action with Go back', async () => {
  await render(appointment('ACTIVE'));
  await openPanel();
  expect(withdraw).not.toHaveBeenCalled();
  expect(alertSpy).not.toHaveBeenCalled();
  expect(texts()).toContain(t('medicalAccess.panelTitle'));
  expect(withdrawButtonElement()?.props.variant).toBe('destructive');
  expect(withdrawButton().props.accessibilityLabel).toBe('Retirar acceso médico de esta cita');
  expect(backButton()).toBeDefined();
  // The Manage action gives way to the panel; never a toggle or switch.
  expect(manageButton()).toBeUndefined();
  expect(
    tree.root.findAll(
      (node) =>
        node.props.accessibilityRole === 'switch' || node.props.accessibilityRole === 'checkbox',
    ),
  ).toHaveLength(0);
});

it('Go back closes the panel without calling the backend', async () => {
  await render(appointment('ACTIVE'));
  await openPanel();
  await act(async () => {
    backButton().props.onPress();
  });
  expect(withdraw).not.toHaveBeenCalled();
  expect(alertSpy).not.toHaveBeenCalled();
  expect(withdrawButton()).toBeUndefined();
  expect(manageButton()).toBeDefined();
  expect(texts()).not.toContain(t('medicalAccess.panelTitle'));
});

it.each(['REQUESTED', 'CONFIRMED'] as const)(
  'a %s Appointment explains that prior history closes and documentation of the care given continues',
  async (lifecycle) => {
    await render(appointment('ACTIVE', lifecycle));
    await openPanel();
    const shown = texts();
    // Three short paragraphs, in order: what stays and is lost, care, permanence.
    const paragraphs = [
      'La cita no se cancelará, pero la clínica dejará de poder consultar el historial médico previo de tu mascota.',
      'La clínica podrá seguir documentando la atención que realmente preste en esta cita, y los registros de la visita no se borrarán.',
      'Esta acción no se puede deshacer para esta cita.',
    ];
    const positions = paragraphs.map((paragraph) => shown.indexOf(paragraph));
    expect(positions.every((position) => position >= 0)).toBe(true);
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
    // No action for the Guardian to delete professional records.
    expect(allText()).not.toMatch(/[Bb]orrar registros|[Ee]liminar registros/);
  },
);

it('a COMPLETED Appointment no longer keeps medical access: nothing to manage', async () => {
  await render(appointment('INACTIVE', 'COMPLETED'));
  expect(manageButton()).toBeUndefined();
  expect(withdrawButton()).toBeUndefined();
  expect(texts()).not.toContain(t('medicalAccess.activeStatus'));
});

it('the consequences never claim cancellation, deletion, a restore, or internal states', async () => {
  for (const lifecycle of ['REQUESTED', 'CONFIRMED'] as const) {
    await render(appointment('ACTIVE', lifecycle));
    await openPanel();
    // Only ever the negations "no se cancelará" / "no se borrarán".
    expect(allText()).not.toMatch(
      /(?<!no )se cancela|(?<!no )se borra|se eliminar|restaurar|reactivar|[Aa]utorizaci[oó]n|Encounter|\bACTIVE\b|REVOKED|INACTIVE/,
    );
    act(() => tree.unmount());
  }
  await render(appointment('ACTIVE'));
});

it('says the Appointment is not cancelled, records are not deleted, and emphasizes irreversibility', async () => {
  await render(appointment('ACTIVE', 'CONFIRMED'));
  await openPanel();
  expect(allText()).toContain('La cita no se cancelará');
  const irreversible = tree.root
    .findAllByType(Text)
    .find((node) => node.props.children === 'Esta acción no se puede deshacer para esta cita.');
  const body = tree.root
    .findAllByType(Text)
    .find((node) => node.props.children === t('medicalAccess.consequenceStays'));
  expect(StyleSheet.flatten(irreversible?.props.style).fontWeight).toBe('600');
  expect(StyleSheet.flatten(body?.props.style).fontWeight).not.toBe('600');
  expect(allText()).toContain('los registros de la visita no se borrarán');
});

it('keeps both panel actions inside the scrollable content, after the consequences', async () => {
  await render(appointment('ACTIVE'));
  await openPanel();
  const [scroll] = tree.root.findAllByType(ScrollView);
  const inScroll = (label: string) =>
    scroll.findAll(
      (node) =>
        node.props.accessibilityRole === 'button' &&
        node.props.accessibilityLabel === label &&
        typeof node.props.onPress === 'function',
    ).length > 0;
  expect(inScroll(t('medicalAccess.withdrawActionAccessibility'))).toBe(true);
  expect(inScroll(t('medicalAccess.panelBack'))).toBe(true);
  // Bottom padding keeps the last action clear of the Android navigation bar.
  expect(StyleSheet.flatten(scroll.props.contentContainerStyle).paddingBottom).toBeGreaterThan(0);
  const shown = texts();
  expect(shown.indexOf(t('medicalAccess.consequenceIrreversible'))).toBeLessThan(
    shown.lastIndexOf(t('medicalAccess.withdrawAction')),
  );
});

it('the final confirmation is short; going back from it changes nothing', async () => {
  await render(appointment('ACTIVE'));
  const buttons = await openDialog();
  const [title, message] = alertSpy.mock.calls[0] as [string, string];
  expect(title).toBe('¿Retirar el acceso médico?');
  expect(message).toBe(
    'La clínica dejará de poder consultar el historial médico previo de tu mascota. No se puede deshacer.',
  );
  // The consequences are in the panel, not repeated in the dialog.
  expect(message).not.toContain(t('medicalAccess.consequenceClinic'));
  expect(buttons.map((button) => button.text)).toEqual(['Volver', 'Retirar acceso']);
  expect(buttons[0].style).toBe('cancel');
  expect(buttons[1].style).toBe('destructive');
  await act(async () => {
    buttons[0].onPress?.();
  });
  expect(withdraw).not.toHaveBeenCalled();
  expect(withdrawButton()).toBeDefined();
});

it('shows the calm withdrawn state once REVOKED, with no action to manage, restore or re-authorize', async () => {
  await render(appointment('REVOKED'));
  expect(texts()).toContain('Acceso médico retirado');
  expect(texts()).toContain(
    'La cita se mantiene, pero esta clínica ya no puede consultar el historial médico previo de tu mascota mediante esta cita.',
  );
  expect(manageButton()).toBeUndefined();
  expect(withdrawButton()).toBeUndefined();
  expect(allButtonLabels().join(' | ')).not.toMatch(
    /[Rr]estaurar|[Rr]eautoriz|[Vv]olver a autorizar|[Dd]eshacer|[Rr]estore|[Rr]eauthori|[Uu]ndo|[Aa]cceso médico/,
  );
  expect(allText()).not.toMatch(/REVOKED|INACTIVE/);
});

it('shows nothing about medical access once it ended with the Appointment', async () => {
  await render(appointment('INACTIVE', 'CANCELLED'));
  expect(allText()).not.toMatch(/Acceso médico/);
  expect(manageButton()).toBeUndefined();
  expect(withdrawButton()).toBeUndefined();
});

it('withdraws once, with the Appointment id alone, re-reads, closes the panel and keeps the Appointment', async () => {
  const announce = jest.spyOn(AccessibilityInfo, 'announceForAccessibility');
  await render(appointment('ACTIVE'), appointment('REVOKED'));
  withdraw.mockResolvedValue({ kind: 'withdrawn' });
  await confirm();
  expect(withdraw).toHaveBeenCalledTimes(1);
  expect(withdraw).toHaveBeenCalledWith('appt-1');
  expect(read).toHaveBeenCalledTimes(2);
  expect(texts()).toContain('Revisión anual');
  expect(texts()).toContain('Acceso médico retirado');
  expect(texts()).not.toContain(t('medicalAccess.panelTitle'));
  expect(withdrawButton()).toBeUndefined();
  expect(manageButton()).toBeUndefined();
  expect(allText()).not.toContain(t('medicalAccess.failed'));
  expect(announce).toHaveBeenCalledWith('Acceso médico retirado');
});

it('an uncertain response whose re-read shows REVOKED is calm, never an error', async () => {
  await render(appointment('ACTIVE'), appointment('REVOKED'));
  withdraw.mockResolvedValue({ kind: 'failed' });
  await confirm();
  expect(texts()).toContain('Acceso médico retirado');
  expect(allText()).not.toContain(t('medicalAccess.failed'));
});

it('an exact retry reconciled to ALREADY_INACTIVE is calm', async () => {
  await render(appointment('ACTIVE'), appointment('REVOKED'));
  withdraw.mockResolvedValue({ kind: 'alreadyInactive' });
  await confirm();
  expect(texts()).toContain('Acceso médico retirado');
  expect(allText()).not.toMatch(/No se pudo|Ya no puedes/);
});

it('when a cancellation ended the access first, says so calmly and closes the panel', async () => {
  await render(appointment('ACTIVE'), appointment('INACTIVE', 'CANCELLED'));
  withdraw.mockResolvedValue({ kind: 'alreadyInactive' });
  await confirm();
  expect(texts()).toContain(t('medicalAccess.noLongerActive'));
  expect(texts()).not.toContain(t('medicalAccess.panelTitle'));
  expect(withdrawButton()).toBeUndefined();
});

it('a failure with access still ACTIVE keeps the panel and action and asks to try again', async () => {
  await render(appointment('ACTIVE'), appointment('ACTIVE'));
  withdraw.mockResolvedValue({ kind: 'failed' });
  await confirm();
  expect(texts()).toContain(t('medicalAccess.failed'));
  expect(withdrawButton()).toBeDefined();
});

it('a denied (foreign or no longer guarded) Appointment shows the calm unavailable message', async () => {
  read.mockResolvedValueOnce({ data: [appointment('ACTIVE')], error: null });
  await act(async () => {
    tree = create(createElement(AppointmentDetailScreen));
  });
  read.mockResolvedValueOnce({ data: null, error: 'Current Guardianship of the Pet is required' });
  withdraw.mockResolvedValue({ kind: 'unavailable' });
  await confirm();
  expect(texts()).toContain(t('medicalAccess.unavailable'));
  expect(texts()).toContain('Revisión anual');
});

it('a second tap while the dialog is open neither opens another dialog nor submits twice', async () => {
  await render(appointment('ACTIVE'), appointment('REVOKED'));
  withdraw.mockResolvedValue({ kind: 'withdrawn' });
  await openPanel();
  await act(async () => {
    withdrawButton().props.onPress();
    withdrawButton().props.onPress();
  });
  expect(alertSpy).toHaveBeenCalledTimes(1);
  const [, , buttons] = alertSpy.mock.calls[0] as [string, string, AlertButton[]];
  await act(async () => {
    buttons[1].onPress?.();
  });
  expect(withdraw).toHaveBeenCalledTimes(1);
});

it('a later read that is no longer ACTIVE closes an open panel', async () => {
  await render(appointment('ACTIVE'));
  await openPanel();
  expect(texts()).toContain(t('medicalAccess.panelTitle'));
  // Another Guardian withdrew it meanwhile; the next authoritative read says so.
  read.mockResolvedValueOnce({ data: [appointment('REVOKED')], error: null });
  await act(async () => {
    mockFocus?.();
  });
  expect(texts()).not.toContain(t('medicalAccess.panelTitle'));
  expect(withdrawButton()).toBeUndefined();
  expect(texts()).toContain('Acceso médico retirado');
  expect(withdraw).not.toHaveBeenCalled();
});

it('renders in English', async () => {
  mockLocale = 'en';
  await render(appointment('ACTIVE', 'CONFIRMED'), appointment('REVOKED'));
  expect(texts()).toEqual(
    expect.arrayContaining([
      'Medical access',
      'Medical access active',
      "The clinic can view your pet's previous medical history to prepare for and provide this appointment.",
    ]),
  );
  expect(manageButtonElement()?.props.label).toBe('Manage medical access');
  expect(manageButton().props.accessibilityLabel).toBe(
    'Manage medical access for this appointment',
  );
  await openPanel();
  expect(texts()).toEqual(
    expect.arrayContaining([
      'Withdraw medical access',
      "The appointment won't be cancelled, but the clinic will no longer be able to view your pet's previous medical history.",
      "The clinic can still document the care it actually provides in this appointment, and the visit's records won't be deleted.",
      "This action can't be undone for this appointment.",
    ]),
  );
  expect(withdrawButton().props.accessibilityLabel).toBe(
    'Withdraw medical access for this appointment',
  );
  expect(backButton()).toBeDefined();
  withdraw.mockResolvedValue({ kind: 'withdrawn' });
  const buttons = await openDialog();
  const [title, message] = alertSpy.mock.calls[0] as [string, string];
  expect(title).toBe('Withdraw medical access?');
  expect(withdraw).not.toHaveBeenCalled();
  expect(message).toBe(
    "The clinic will no longer be able to view your pet's previous medical history. This can't be undone.",
  );
  expect(buttons.map((button) => button.text)).toEqual(['Go back', 'Withdraw access']);
  await act(async () => {
    buttons[1].onPress?.();
  });
  expect(texts()).toContain('Medical access withdrawn');
  expect(allButtonLabels().join(' | ')).not.toMatch(/[Rr]estore|[Rr]eauthori|[Uu]ndo/);
});

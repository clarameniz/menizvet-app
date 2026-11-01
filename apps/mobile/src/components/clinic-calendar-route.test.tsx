import { createElement } from 'react';
import { FlatList, StyleSheet, Text } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import ClinicCalendarScreen from '@/app/professional/clinics/[clinicId]/calendar';
import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  type ClinicScheduleAppointment,
  type ClinicScheduleResult,
} from '@/data/clinic-appointment-schedule';
import {
  getClinicAppointmentDay,
  getClinicAppointmentHistory,
  getClinicAppointmentMonthCounts,
  getClinicAppointmentPending,
  getClinicCalendarContext,
  ZERO_PENDING_TOTALS,
  type ClinicPendingAppointment,
  type ClinicPendingPage,
  type PendingReason,
  type PendingTotals,
  PENDING_REASONS,
} from '@/data/clinic-calendar';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { i18n } from '@/i18n/i18n';
import { lifecycleLabelKey } from '@/lib/appointment-lifecycle';
import {
  compactAppointmentDate,
  deviceMonth,
  formatDayHeading,
  formatMonthTitle,
  mondayFirstWeekdays,
} from '@/lib/clinic-calendar';
import { professionalAppointmentDetailHref } from '@/lib/clinic-schedule-display';
import { colors } from '@/theme/colors';

/**
 * The professional agenda (SPEC-APT-012 §14): the Calendar tab (BR-54/56/60)
 * with the real `react-native-calendars` month grid, and the Pending (BR-57)
 * and History (BR-59) tabs. Each tab's reads are answered separately; the
 * full schedule read and the pending summary must never be called.
 */

type FocusCallback = () => void | (() => void);
// Every registered focus effect (one per agenda hook), as a real focus runs them all.
const mockFocus = {
  callbacks: new Set<FocusCallback>(),
  cleanups: new Map<FocusCallback, () => void>(),
};
const mockLocale = { value: 'es' as 'es' | 'en' };

jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ clinicId: 'clinic-a' }),
  useFocusEffect: (callback: FocusCallback) => {
    const React = jest.requireActual('react');
    React.useEffect(() => {
      mockFocus.callbacks.add(callback);
      const cleanup = callback();
      if (typeof cleanup === 'function') mockFocus.cleanups.set(callback, cleanup);
      return () => {
        mockFocus.cleanups.get(callback)?.();
        mockFocus.cleanups.delete(callback);
        mockFocus.callbacks.delete(callback);
      };
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
      locale: mockLocale.value,
      t: (key: string, options?: Record<string, unknown>) =>
        mockI18n.t(key, { ...options, locale: mockLocale.value }),
    }),
  };
});
jest.mock('@/data/professional-clinics', () => ({
  ...jest.requireActual('@/data/professional-clinics'),
  getMyProfessionalClinics: jest.fn(),
}));
jest.mock('@/data/clinic-calendar', () => ({
  ...jest.requireActual('@/data/clinic-calendar'),
  getClinicCalendarContext: jest.fn(),
  getClinicAppointmentMonthCounts: jest.fn(),
  getClinicAppointmentDay: jest.fn(),
  getClinicAppointmentPending: jest.fn(),
  getClinicAppointmentHistory: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const { router } = jest.requireMock('expo-router') as { router: { push: jest.Mock } };
const clinicsRead = getMyProfessionalClinics as jest.Mock;
const contextRead = getClinicCalendarContext as jest.Mock;
const monthRead = getClinicAppointmentMonthCounts as jest.Mock;
const dayRead = getClinicAppointmentDay as jest.Mock;
const pendingRead = getClinicAppointmentPending as jest.Mock;
const historyRead = getClinicAppointmentHistory as jest.Mock;
const forbiddenReads = () =>
  (jest.requireMock('@/lib/supabase').supabase.rpc as jest.Mock).mock.calls.filter(
    ([name]) =>
      name === 'get_clinic_appointment_schedule' ||
      name === 'get_clinic_appointment_pending_summary',
  );

const t = (key: string, options?: Record<string, unknown>) =>
  i18n.t(key, { ...options, locale: mockLocale.value });

function appointment(
  id: string,
  overrides: Partial<ClinicScheduleAppointment> = {},
): ClinicScheduleAppointment {
  return {
    id,
    petId: `pet-${id}`,
    petName: 'Luna',
    requestingUserId: 'user-1',
    requesterDisplayName: 'Marta Ruiz',
    reasonForVisit: 'Revisión anual',
    guardianNotes: null,
    lifecycleState: 'CONFIRMED',
    createdAt: '2026-10-01T08:00:00Z',
    // 9:00–9:30 in Madrid (UTC+1).
    currentScheduledStartAt: '2026-11-03T08:00:00Z',
    currentScheduledEndAt: '2026-11-03T08:30:00Z',
    currentSchedulingTimezoneName: 'Europe/Madrid',
    currentScheduleRevisionSequence: 1,
    currentVeterinarianClinicAssignmentId: null,
    pendingReschedule: null,
    currentScheduleSource: null,
    cancellationReason: null,
    hasClinicalRecord: false,
    ...overrides,
  };
}

const REQUESTED = appointment('appt-requested', {
  lifecycleState: 'REQUESTED',
  petName: 'Bartolomé Maximiliano de la Santísima Trinidad',
  requesterDisplayName: 'Guadalupe Fernández-Villaverde de los Ríos',
  reasonForVisit: 'Revisión completa con analítica y vacunación anual de refuerzo',
});
const CONFIRMED_WITH_PROPOSAL = appointment('appt-confirmed', {
  petName: 'Toby',
  requesterDisplayName: null,
  currentScheduledStartAt: '2026-11-03T09:00:00Z',
  currentScheduledEndAt: '2026-11-03T09:30:00Z',
  pendingReschedule: {
    kind: 'confirmedReschedule',
    proposalId: 'proposal-1',
    proposingContext: 'CLINIC',
    reason: 'Agenda completa',
    proposedStartAt: '2026-11-05T09:00:00Z',
    proposedEndAt: '2026-11-05T09:30:00Z',
    proposedTimezoneName: 'Europe/Madrid',
    currentlyFeasible: true,
  },
});
const OTHER_ZONE = appointment('appt-new-york', {
  petName: 'Kira',
  // 8:00 in New York (UTC-5) on 3 November.
  currentScheduledStartAt: '2026-11-03T13:00:00Z',
  currentScheduledEndAt: '2026-11-03T13:30:00Z',
  currentSchedulingTimezoneName: 'America/New_York',
});

const ok = <T,>(data: T): ClinicScheduleResult<T> => ({ data, error: null });
const failed = (error: string) => ({ data: null, error });

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

let tree: ReactTestRenderer;

const texts = () => tree.root.findAllByType(Text).map((node) => String(node.props.children));
const shown = () => texts().join(' | ');
const buttons = () =>
  tree.root.findAll(
    (node) => node.props.accessibilityRole === 'button' && typeof node.props.onPress === 'function',
  );
const dayButtons = () =>
  buttons().filter((node) => String(node.props.testID ?? '').startsWith('calendar-day-'));
function dayButton(date: string) {
  const match = dayButtons().find((node) => node.props.testID === `calendar-day-${date}`);
  if (match === undefined) throw new Error(`No day button for ${date}`);
  return match;
}
function buttonLabelled(label: string) {
  const match = buttons().find((node) => node.props.accessibilityLabel === label);
  if (match === undefined) throw new Error(`No button labelled ${label}`);
  return match;
}
async function press(node: ReactTestInstance) {
  await act(async () => {
    node.props.onPress();
  });
}
async function refocus() {
  await act(async () => {
    for (const callback of mockFocus.callbacks) {
      mockFocus.cleanups.get(callback)?.();
      const cleanup = callback();
      if (typeof cleanup === 'function') mockFocus.cleanups.set(callback, cleanup);
      else mockFocus.cleanups.delete(callback);
    }
  });
}
async function render() {
  await act(async () => {
    tree = create(createElement(ClinicCalendarScreen));
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  mockLocale.value = 'es';
  clinicsRead.mockResolvedValue(
    ok({
      clinics: [
        {
          clinicId: 'clinic-a',
          clinicDisplayName: 'Clínica Veterinaria Animalia',
          organizationId: 'org-1',
          organizationDisplayName: 'Animalia Group',
          capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
          unknownCapabilities: [],
        },
      ],
    }),
  );
  contextRead.mockResolvedValue(
    ok({ clinicLocalToday: '2026-11-03', schedulingTimezoneName: 'Europe/Madrid' }),
  );
  monthRead.mockImplementation(async (_clinicId: string, year: number, month: number) =>
    year === 2026 && month === 11 ? ok({ '2026-11-03': 3, '2026-11-20': 1 }) : ok({}),
  );
  dayRead.mockImplementation(async (_clinicId: string, day: string) =>
    day === '2026-11-03' ? ok([REQUESTED, CONFIRMED_WITH_PROPOSAL, OTHER_ZONE]) : ok([]),
  );
});
afterEach(() => {
  expect(forbiddenReads()).toEqual([]);
  act(() => tree.unmount());
});

describe('opening the calendar', () => {
  it("opens on the Clinic's month with today selected, one read per month and per day", async () => {
    await render();
    expect(shown()).toContain(t('clinicSchedule.title'));
    expect(shown()).toContain('Clínica Veterinaria Animalia');
    expect(shown()).toContain('Noviembre de 2026');
    expect(contextRead).toHaveBeenCalledWith('clinic-a');
    expect(monthRead.mock.calls).toEqual([['clinic-a', 2026, 11]]);
    expect(dayRead.mock.calls).toEqual([['clinic-a', '2026-11-03']]);

    const today = dayButton('2026-11-03');
    expect(today.props.accessibilityLabel).toBe(
      `${formatDayHeading('2026-11-03', 'es')}, ${t('clinicCalendar.today')}, 3 citas`,
    );
    expect(today.props.accessibilityState).toEqual({ selected: true });
    expect(shown()).toContain(formatDayHeading('2026-11-03', 'es'));
    expect(shown()).toContain(t('clinicCalendar.todayAction'));
  });

  it('starts weeks on Monday, with every date of the month and its count', async () => {
    await render();
    const weekdays = mondayFirstWeekdays('es').map((day) => day.short);
    const all = texts();
    const first = all.indexOf(weekdays[0]);
    expect(all.slice(first, first + 7)).toEqual(weekdays);
    expect(dayButtons()).toHaveLength(30);
    expect(dayButton('2026-11-20').props.accessibilityLabel).toBe(
      `${formatDayHeading('2026-11-20', 'es')}, 1 cita`,
    );
    expect(dayButton('2026-11-04').props.accessibilityLabel).toBe(
      `${formatDayHeading('2026-11-04', 'es')}, ${t('clinicCalendar.dayNoAppointments')}`,
    );
    expect(shown()).toContain(t('clinicCalendar.monthTotalOther', { count: 4 }));
  });

  it('never claims a count before the month is loaded', async () => {
    const month = deferred<ClinicScheduleResult<Record<string, number>>>();
    monthRead.mockReturnValueOnce(month.promise);
    await render();
    expect(shown()).toContain(t('clinicCalendar.monthLoading'));
    expect(dayButton('2026-11-04').props.accessibilityLabel).toBe(
      formatDayHeading('2026-11-04', 'es'),
    );
    await act(async () => month.resolve(ok({})));
    expect(shown()).toContain(t('clinicCalendar.monthEmpty'));
    expect(shown()).not.toContain(t('clinicCalendar.monthLoading'));
  });
});

describe('the selected day', () => {
  it('lists compact rows: time, Pet, requester, reason, real state, pending proposal, other zone', async () => {
    await render();
    const all = shown();
    expect(all).toContain('9:00');
    expect(all).toContain('10:00');
    expect(all).toContain(REQUESTED.petName);
    expect(all).toContain(
      t('appointmentContact.requestedBy', { name: REQUESTED.requesterDisplayName }),
    );
    expect(all).toContain(t('appointmentContact.requestedByUnnamed'));
    expect(all).toContain(REQUESTED.reasonForVisit);
    expect(all).toContain(t(lifecycleLabelKey('REQUESTED')));
    expect(all).toContain(t(lifecycleLabelKey('CONFIRMED')));
    expect(t(lifecycleLabelKey('REQUESTED'))).not.toBe(t(lifecycleLabelKey('CONFIRMED')));
    expect(all).toContain(t('clinicSchedule.pendingReschedule'));
    expect(all).toContain(t('clinicCalendar.timezoneNote', { zone: 'America/New_York' }));
    expect(all).not.toContain(t('clinicCalendar.timezoneNote', { zone: 'Europe/Madrid' }));
    expect(all).not.toMatch(/@/);
  });

  it('keeps the full details in each row’s accessible name, however the text is truncated', async () => {
    await render();
    const row = buttons().find((node) =>
      String(node.props.accessibilityLabel).includes(REQUESTED.petName),
    );
    expect(row?.props.accessibilityLabel).toBe(
      [
        '9:00 – 9:30',
        REQUESTED.petName,
        t('appointmentContact.requestedBy', { name: REQUESTED.requesterDisplayName }),
        t(lifecycleLabelKey('REQUESTED')),
        REQUESTED.reasonForVisit,
      ].join(', '),
    );
    expect(row?.props.accessibilityHint).toBe(t('clinicSchedule.openDetailHint'));
  });

  it('opens the Appointment detail from the whole row', async () => {
    await render();
    const row = buttons().find((node) => String(node.props.accessibilityLabel).includes('Toby'));
    expect(row).toBeDefined();
    await press(row as ReactTestInstance);
    expect(router.push).toHaveBeenCalledWith(
      professionalAppointmentDetailHref('clinic-a', 'appt-confirmed'),
    );
  });

  it('reads another day only when it is chosen, and a day already read not again', async () => {
    await render();
    await press(dayButton('2026-11-20'));
    expect(dayRead.mock.calls).toEqual([
      ['clinic-a', '2026-11-03'],
      ['clinic-a', '2026-11-20'],
    ]);
    expect(shown()).toContain(t('clinicCalendar.dayEmpty'));
    expect(dayButton('2026-11-20').props.accessibilityState).toEqual({ selected: true });
    await press(dayButton('2026-11-03'));
    expect(dayRead).toHaveBeenCalledTimes(2);
    expect(shown()).toContain('Toby');
  });

  it('shows the answer for the day selected last, whatever order the answers arrive in', async () => {
    await render();
    const twenty = deferred<ClinicScheduleResult<ClinicScheduleAppointment[]>>();
    const twentyOne = deferred<ClinicScheduleResult<ClinicScheduleAppointment[]>>();
    dayRead.mockReturnValueOnce(twenty.promise).mockReturnValueOnce(twentyOne.promise);
    await press(dayButton('2026-11-20'));
    await press(dayButton('2026-11-21'));
    await act(async () => twentyOne.resolve(ok([appointment('appt-21', { petName: 'Nala' })])));
    await act(async () => twenty.resolve(ok([appointment('appt-20', { petName: 'Coco' })])));
    expect(shown()).toContain('Nala');
    expect(shown()).not.toContain('Coco');
  });
});

describe('months', () => {
  it('changes month and year with the arrows, reading only the counts', async () => {
    await render();
    await press(buttonLabelled(t('clinicCalendar.nextMonth')));
    expect(shown()).toContain('Diciembre de 2026');
    expect(shown()).toContain(t('clinicCalendar.selectDayPrompt'));
    await press(buttonLabelled(t('clinicCalendar.nextMonth')));
    expect(shown()).toContain('Enero de 2027');
    expect(dayButtons()).toHaveLength(31);
    expect(monthRead.mock.calls).toEqual([
      ['clinic-a', 2026, 11],
      ['clinic-a', 2026, 12],
      ['clinic-a', 2027, 1],
    ]);
    expect(dayRead).toHaveBeenCalledTimes(1);
  });

  it('returns to today without reading again what is still fresh', async () => {
    await render();
    await press(buttonLabelled(t('clinicCalendar.previousMonth')));
    expect(shown()).toContain('Octubre de 2026');
    await press(buttonLabelled(t('clinicCalendar.todayAction')));
    expect(shown()).toContain('Noviembre de 2026');
    expect(dayButton('2026-11-03').props.accessibilityState).toEqual({ selected: true });
    expect(monthRead).toHaveBeenCalledTimes(2);
    expect(dayRead).toHaveBeenCalledTimes(1);
  });

  it('lays out four- and six-week months completely', async () => {
    contextRead.mockResolvedValue(
      ok({ clinicLocalToday: '2026-03-31', schedulingTimezoneName: 'Europe/Madrid' }),
    );
    await render();
    expect(shown()).toContain('Marzo de 2026');
    expect(dayButtons()).toHaveLength(31);
    for (let index = 0; index < 11; index += 1) {
      await press(buttonLabelled(t('clinicCalendar.nextMonth')));
    }
    expect(shown()).toContain('Febrero de 2027');
    expect(dayButtons()).toHaveLength(28);
  });

  it('shows the counts of the month shown last when answers arrive out of order', async () => {
    await render();
    const december = deferred<ClinicScheduleResult<Record<string, number>>>();
    const january = deferred<ClinicScheduleResult<Record<string, number>>>();
    monthRead.mockReturnValueOnce(december.promise).mockReturnValueOnce(january.promise);
    await press(buttonLabelled(t('clinicCalendar.nextMonth')));
    await press(buttonLabelled(t('clinicCalendar.nextMonth')));
    await act(async () => january.resolve(ok({ '2027-01-15': 5 })));
    await act(async () => december.resolve(ok({ '2026-12-15': 7 })));
    expect(shown()).toContain('Enero de 2027');
    expect(dayButton('2027-01-15').props.accessibilityLabel).toContain('5 citas');
    expect(shown()).toContain(t('clinicCalendar.monthTotalOther', { count: 5 }));
  });
});

describe('day circles', () => {
  /** The flattened style of a day's single circle. */
  function circleOf(date: string) {
    const circle = tree.root.find(
      (node) =>
        typeof node.type === 'string' && node.props.testID === `calendar-day-circle-${date}`,
    );
    return StyleSheet.flatten(circle.props.style);
  }

  it('selected (today or not) is one solid circle; today alone is outlined; never both', async () => {
    await render();
    // Today and selected: solid, no border.
    let today = circleOf('2026-11-03');
    expect(today.backgroundColor).toBe(colors.primary);
    expect(today.borderWidth ?? 0).toBe(0);
    expect(today.borderRadius).toBe(Number(today.width) / 2);
    expect(today.width).toBe(today.height);
    // Any other day: just its number.
    expect(circleOf('2026-11-04').backgroundColor).toBe('transparent');
    expect(circleOf('2026-11-04').borderWidth ?? 0).toBe(0);

    await press(dayButton('2026-11-20'));
    const selected = circleOf('2026-11-20');
    expect(selected.backgroundColor).toBe(colors.primary);
    expect(selected.borderWidth ?? 0).toBe(0);
    today = circleOf('2026-11-03');
    expect(today.backgroundColor).toBe('transparent');
    expect(today.borderWidth).toBeGreaterThan(0);
    expect(today.borderColor).toBe(colors.primary);
  });

  it("shows today's number in white again when today is selected again", async () => {
    await render();
    const numberColor = () => {
      const circle = tree.root.find(
        (node) =>
          typeof node.type === 'string' && node.props.testID === 'calendar-day-circle-2026-11-03',
      );
      return StyleSheet.flatten(circle.findByType(Text).props.style).color;
    };
    expect(numberColor()).toBe(colors.surface);
    await press(dayButton('2026-11-20'));
    expect(numberColor()).toBe(colors.primaryDark);
    await press(dayButton('2026-11-03'));
    expect(numberColor()).toBe(colors.surface);
    expect(circleOf('2026-11-03').backgroundColor).toBe(colors.primary);
  });
});

describe('a Clinic without a valid timezone (BR-60)', () => {
  it('opens on the device month provisionally, with no today and nothing selected', async () => {
    contextRead.mockResolvedValue(ok({ clinicLocalToday: null, schedulingTimezoneName: null }));
    await render();
    const month = deviceMonth();
    expect(shown()).toContain(formatMonthTitle(month, 'es'));
    expect(shown()).toContain(t('clinicCalendar.noTimezoneNotice'));
    expect(
      buttons().some((node) => node.props.accessibilityLabel === t('clinicCalendar.todayAction')),
    ).toBe(false);
    expect(
      dayButtons().some((node) =>
        String(node.props.accessibilityLabel).includes(`, ${t('clinicCalendar.today')}`),
      ),
    ).toBe(false);
    expect(dayButtons().every((node) => node.props.accessibilityState.selected === false)).toBe(
      true,
    );
    expect(monthRead.mock.calls).toEqual([['clinic-a', month.year, month.month]]);
    expect(dayRead).not.toHaveBeenCalled();
  });

  it('reads a day only when chosen, and names every row’s own timezone', async () => {
    contextRead.mockResolvedValue(ok({ clinicLocalToday: null, schedulingTimezoneName: null }));
    monthRead.mockResolvedValue(ok({}));
    dayRead.mockResolvedValue(ok([CONFIRMED_WITH_PROPOSAL, OTHER_ZONE]));
    await render();
    await press(dayButtons()[2]);
    expect(dayRead).toHaveBeenCalledTimes(1);
    expect(shown()).toContain(t('clinicCalendar.timezoneNote', { zone: 'Europe/Madrid' }));
    expect(shown()).toContain(t('clinicCalendar.timezoneNote', { zone: 'America/New_York' }));
  });
});

describe('errors', () => {
  it('a month error keeps the day; a retry reads the month again', async () => {
    monthRead.mockResolvedValueOnce(failed('Network request failed'));
    await render();
    expect(shown()).toContain(t('clinicCalendar.monthError'));
    expect(shown()).toContain('Toby');
    const retry = buttons().find(
      (node) =>
        node.props.accessibilityLabel === undefined &&
        node.findAllByType(Text).some((text) => text.props.children === t('professional.retry')),
    );
    expect(retry).toBeDefined();
    await press(retry as ReactTestInstance);
    expect(monthRead).toHaveBeenCalledTimes(2);
    expect(shown()).toContain(t('clinicCalendar.monthTotalOther', { count: 4 }));
  });

  it('a day error keeps the month counts', async () => {
    dayRead.mockResolvedValueOnce(failed('Network request failed'));
    await render();
    expect(shown()).toContain(t('clinicCalendar.dayError'));
    expect(dayButton('2026-11-03').props.accessibilityLabel).toContain('3 citas');
  });

  it('a failed refresh keeps the rows already shown', async () => {
    await render();
    dayRead.mockResolvedValueOnce(failed('Network request failed'));
    await refocus();
    expect(shown()).toContain('Toby');
    expect(shown()).toContain(t('clinicCalendar.dayStale'));
  });

  it('losing schedule access replaces the calendar', async () => {
    dayRead.mockResolvedValueOnce(failed(CLINIC_SCHEDULE_ACCESS_DENIED));
    await render();
    expect(shown()).toContain(t('clinicSchedule.accessError'));
    expect(dayButtons()).toHaveLength(0);
    expect(shown()).not.toContain('Toby');
  });

  it('an expired session on the first read shows the shared message with a retry', async () => {
    contextRead.mockResolvedValueOnce(failed(PROFESSIONAL_CONTEXT_AUTH_REQUIRED));
    await render();
    expect(shown()).toContain(t('errors.sessionExpired'));
    expect(monthRead).not.toHaveBeenCalled();
    await press(buttonLabelled(t('professional.retry')));
    expect(shown()).toContain('Noviembre de 2026');
  });

  it('a Clinic no longer offered shows the calm unavailable state', async () => {
    clinicsRead.mockResolvedValue(ok({ clinics: [] }));
    await render();
    expect(shown()).toContain(t('professionalClinic.notAvailable'));
    expect(monthRead).not.toHaveBeenCalled();
  });
});

describe('coming back to the calendar', () => {
  it('re-reads the context, the visible month and the selected day once each', async () => {
    await render();
    monthRead.mockResolvedValueOnce(ok({ '2026-11-03': 2 }));
    dayRead.mockResolvedValueOnce(ok([CONFIRMED_WITH_PROPOSAL, OTHER_ZONE]));
    await refocus();
    expect(contextRead).toHaveBeenCalledTimes(2);
    expect(clinicsRead).toHaveBeenCalledTimes(2);
    expect(monthRead).toHaveBeenCalledTimes(2);
    expect(dayRead).toHaveBeenCalledTimes(2);
    expect(dayButton('2026-11-03').props.accessibilityLabel).toContain('2 citas');
    expect(shown()).not.toContain(REQUESTED.petName);
  });

  it('moves to the new today when midnight passed while the actor was on today', async () => {
    await render();
    contextRead.mockResolvedValue(
      ok({ clinicLocalToday: '2026-11-04', schedulingTimezoneName: 'Europe/Madrid' }),
    );
    await refocus();
    expect(dayButton('2026-11-04').props.accessibilityState).toEqual({ selected: true });
    expect(dayButton('2026-11-04').props.accessibilityLabel).toContain(t('clinicCalendar.today'));
    expect(dayRead).toHaveBeenLastCalledWith('clinic-a', '2026-11-04');
  });

  it('ignores an older answer for the same day after a refresh', async () => {
    const first = deferred<ClinicScheduleResult<ClinicScheduleAppointment[]>>();
    dayRead.mockReturnValueOnce(first.promise);
    await render();
    dayRead.mockResolvedValueOnce(ok([appointment('appt-new', { petName: 'Nuevo' })]));
    await refocus();
    await act(async () => first.resolve(ok([appointment('appt-old', { petName: 'Antiguo' })])));
    expect(shown()).toContain('Nuevo');
    expect(shown()).not.toContain('Antiguo');
  });
});

// ---------------------------------------------------------------------------
// The agenda's tabs, Pending (BR-57) and History (BR-59)
// ---------------------------------------------------------------------------

function pendingRow(
  id: string,
  reason: PendingReason,
  overrides: Partial<ClinicScheduleAppointment> = {},
): ClinicPendingAppointment {
  return {
    appointment: appointment(id, overrides),
    reason,
    category: PENDING_REASONS[reason].category,
    rank: PENDING_REASONS[reason].rank,
  };
}

const pendingPage = (rows: ClinicPendingAppointment[], pageTotals: PendingTotals | null) =>
  ok<ClinicPendingPage>({ rows, totals: pageTotals });

const totals = (action: number, awaiting: number, informational: number): PendingTotals => ({
  ACTION_REQUIRED: action,
  AWAITING_GUARDIAN: awaiting,
  INFORMATIONAL: informational,
});

const ATTENDANCE = pendingRow('p-attend', 'ATTENDANCE_OUTCOME', {
  petName: 'Kira',
  currentScheduledStartAt: '2026-11-02T08:00:00Z',
  currentScheduledEndAt: '2026-11-02T08:30:00Z',
});
const DECISION = pendingRow('p-request', 'REQUEST_DECISION', {
  lifecycleState: 'REQUESTED',
  petName: 'Luna',
});
const GUARDIAN_PROPOSAL = pendingRow('p-guardian', 'GUARDIAN_PROPOSAL', { petName: 'Toby' });
const AWAITING = pendingRow('p-awaiting', 'AWAITING_GUARDIAN', {
  petName: 'Nala',
  requesterDisplayName: null,
});
const FIRST_PENDING_PAGE = pendingPage(
  [ATTENDANCE, DECISION, GUARDIAN_PROPOSAL, AWAITING],
  totals(2, 1, 1),
);

/** `count` ACTION_REQUIRED rows, the last one with a microsecond timestamp. */
function actionRows(count: number, prefix: string): ClinicPendingAppointment[] {
  return Array.from({ length: count }, (_, index) =>
    pendingRow(`${prefix}-${String(index).padStart(3, '0')}`, 'ATTENDANCE_OUTCOME', {
      petName: `${prefix} ${index}`,
      currentScheduledStartAt:
        index === count - 1 ? '2026-11-02T09:00:00.123456+00:00' : '2026-11-02T08:00:00Z',
      currentScheduledEndAt: '2026-11-02T09:30:00Z',
    }),
  );
}

function historyRows(count: number, prefix: string): ClinicScheduleAppointment[] {
  return Array.from({ length: count }, (_, index) =>
    appointment(`${prefix}-${String(index).padStart(3, '0')}`, {
      lifecycleState: 'COMPLETED',
      petName: `${prefix} ${index}`,
      currentScheduledStartAt:
        index === count - 1 ? '2026-10-01T08:00:00.654321+00:00' : '2026-10-02T08:00:00Z',
      currentScheduledEndAt: '2026-10-02T08:30:00Z',
    }),
  );
}

const HISTORY = [
  appointment('h-completed', { lifecycleState: 'COMPLETED', petName: 'Coco' }),
  appointment('h-no-show', { lifecycleState: 'NO_SHOW', petName: 'Rufo' }),
  appointment('h-cancelled', {
    lifecycleState: 'CANCELLED',
    petName: 'Mia',
    cancellationReason: 'Sin hueco',
  }),
  appointment('h-expired', { lifecycleState: 'EXPIRED', petName: 'Lola' }),
];

type TabName = 'calendar' | 'pending' | 'history';

function tab(name: TabName) {
  return tree.root.find(
    (node) =>
      node.props.testID === `agenda-tab-${name}` && typeof node.props.onPress === 'function',
  );
}
async function showTab(name: TabName) {
  await press(tab(name));
}
function loadMoreButton() {
  return buttons().find((node) => node.props.accessibilityLabel === t('pagedList.loadMore'));
}
function rowFor(petName: string) {
  return buttons().find((node) => String(node.props.accessibilityLabel).includes(petName));
}
function retryButton() {
  return buttons().find((node) =>
    node.findAllByType(Text).some((text) => text.props.children === t('professional.retry')),
  );
}
/** The Pending category headings' accessible names, in order. */
function headingLabels() {
  return tree.root
    .findAll(
      (node) =>
        typeof node.type === 'string' &&
        node.props.accessibilityRole === 'header' &&
        node.props.accessible === true &&
        typeof node.props.accessibilityLabel === 'string',
    )
    .map((node) => node.props.accessibilityLabel as string);
}
/** The list's whole `data` — FlatList renders only its first rows in the test renderer. */
function listData(): unknown[] {
  return tree.root.findByType(FlatList).props.data as unknown[];
}
function pendingRowIds() {
  return (listData() as { kind: string; row?: ClinicPendingAppointment }[])
    .filter((item) => item.kind === 'row')
    .map((item) => item.row?.appointment.id);
}
/** Each category heading in the list's data, as "CATEGORY loaded/total". */
function categoryItems() {
  return (listData() as { kind: string; category?: string; loaded?: number; total?: number }[])
    .filter((item) => item.kind === 'category')
    .map((item) => `${item.category} ${item.loaded}/${item.total}`);
}
function historyIds() {
  return (listData() as ClinicScheduleAppointment[]).map((item) => item.id);
}
function hasSummary(label: string) {
  return tree.root.findAll((node) => node.props.accessibilityLabel === label).length > 0;
}

describe('the agenda tabs', () => {
  beforeEach(() => {
    pendingRead.mockResolvedValue(FIRST_PENDING_PAGE);
    historyRead.mockResolvedValue(ok(HISTORY));
  });

  it('opens on Calendar under the header, reading neither Pending nor History', async () => {
    await render();
    for (const name of ['calendar', 'pending', 'history'] as const) {
      expect(tab(name).props.accessibilityRole).toBe('tab');
    }
    expect(tab('calendar').props.accessibilityState).toEqual({ selected: true });
    expect(tab('pending').props.accessibilityState).toEqual({ selected: false });
    expect(tab('calendar').props.accessibilityLabel).toBe('Calendario');
    expect(tab('pending').props.accessibilityLabel).toBe('Pendientes');
    expect(tab('history').props.accessibilityLabel).toBe('Historial');
    expect(pendingRead).not.toHaveBeenCalled();
    expect(historyRead).not.toHaveBeenCalled();
  });

  it('reads each tab once, when first shown, and switching never reads another tab', async () => {
    await render();
    await showTab('pending');
    expect(pendingRead.mock.calls).toEqual([['clinic-a', null, 50]]);
    expect(historyRead).not.toHaveBeenCalled();
    expect(tab('pending').props.accessibilityState).toEqual({ selected: true });

    await showTab('history');
    expect(historyRead.mock.calls).toEqual([['clinic-a', null, 30]]);

    await showTab('calendar');
    await showTab('pending');
    await showTab('history');
    await showTab('calendar');
    expect(pendingRead).toHaveBeenCalledTimes(1);
    expect(historyRead).toHaveBeenCalledTimes(1);
    expect(contextRead).toHaveBeenCalledTimes(1);
    expect(monthRead).toHaveBeenCalledTimes(1);
    expect(dayRead).toHaveBeenCalledTimes(1);
    expect(shown()).toContain('Noviembre de 2026');
  });

  it('back from the detail, refreshes only the tab shown; the others when shown again', async () => {
    await render();
    await showTab('pending');
    await refocus();
    expect(pendingRead.mock.calls).toEqual([
      ['clinic-a', null, 50],
      ['clinic-a', null, 50],
    ]);
    expect(contextRead).toHaveBeenCalledTimes(1);
    expect(clinicsRead).toHaveBeenCalledTimes(1);
    expect(monthRead).toHaveBeenCalledTimes(1);
    expect(dayRead).toHaveBeenCalledTimes(1);
    expect(historyRead).not.toHaveBeenCalled();

    await showTab('calendar');
    expect(contextRead).toHaveBeenCalledTimes(2);
    expect(monthRead).toHaveBeenCalledTimes(2);
    expect(dayRead).toHaveBeenCalledTimes(2);
    await showTab('pending');
    expect(pendingRead).toHaveBeenCalledTimes(2);

    await showTab('history');
    await refocus();
    expect(historyRead).toHaveBeenCalledTimes(2);
    await showTab('pending');
    expect(pendingRead).toHaveBeenCalledTimes(3);
    expect(pendingRead).toHaveBeenLastCalledWith('clinic-a', null, 50);
  });

  it('localizes the tabs in English', async () => {
    mockLocale.value = 'en';
    await render();
    expect(tab('calendar').props.accessibilityLabel).toBe('Calendar');
    expect(tab('pending').props.accessibilityLabel).toBe('Pending');
    expect(tab('history').props.accessibilityLabel).toBe('History');
  });
});

describe('Pending', () => {
  beforeEach(() => {
    pendingRead.mockResolvedValue(FIRST_PENDING_PAGE);
    historyRead.mockResolvedValue(ok([]));
  });

  it("groups compact rows by the backend's categories, in its order, with its totals", async () => {
    await render();
    await showTab('pending');
    expect(headingLabels()).toEqual([
      `${t('clinicAgenda.categoryActionRequired')}, 2`,
      `${t('clinicAgenda.categoryInformational')}, 1`,
      `${t('clinicAgenda.categoryAwaitingGuardian')}, 1`,
    ]);
    expect(hasSummary(`${t('clinicAgenda.categoryActionRequired')}: 2`)).toBe(true);
    expect(hasSummary(`${t('clinicAgenda.categoryAwaitingGuardian')}: 1`)).toBe(true);
    expect(hasSummary(`${t('clinicAgenda.categoryInformational')}: 1`)).toBe(true);
    const all = shown();
    expect(all).toContain(t('clinicAgenda.categoryInformationalNote'));
    expect(all).toContain(t('clinicAgenda.categoryAwaitingGuardianNote'));
    expect(all.indexOf('Kira')).toBeLessThan(all.indexOf('Luna'));
    expect(all.indexOf('Luna')).toBeLessThan(all.indexOf('Toby'));
    expect(all.indexOf('Toby')).toBeLessThan(all.indexOf('Nala'));
    expect(all).not.toMatch(/@/);
  });

  it('shows time, Pet, requester, the pending reason and the real state, fully announced', async () => {
    await render();
    await showTab('pending');
    const row = rowFor('Luna');
    expect(row?.props.accessibilityLabel).toBe(
      [
        formatDayHeading('2026-11-03', 'es'),
        '9:00 – 9:30',
        'Luna',
        t('appointmentContact.requestedBy', { name: 'Marta Ruiz' }),
        t(lifecycleLabelKey('REQUESTED')),
        t('clinicAgenda.reasonRequestDecision'),
      ].join(', '),
    );
    // Visible: the time over the short date, and the short reason on its own line.
    const visible = row?.findAllByType(Text).map((node) => String(node.props.children));
    expect(visible).toEqual(
      expect.arrayContaining([
        '9:00',
        compactAppointmentDate(DECISION.appointment, 'es'),
        t('clinicAgenda.reasonRequestDecisionShort'),
      ]),
    );
    expect(visible).not.toContain(t('clinicAgenda.reasonRequestDecision'));
    expect(rowFor('Nala')?.props.accessibilityLabel).toContain(
      t('appointmentContact.requestedByUnnamed'),
    );
    expect(rowFor('Kira')?.props.accessibilityLabel).toContain(
      t('clinicAgenda.reasonAttendanceOutcome'),
    );
    // A past CONFIRMED Appointment is pending (its outcome), never historical.
    expect(rowFor('Kira')?.props.accessibilityLabel).toContain(t(lifecycleLabelKey('CONFIRMED')));
    const all = shown();
    for (const key of [
      'reasonAttendanceOutcomeShort',
      'reasonRequestDecisionShort',
      'reasonGuardianProposalShort',
      'reasonAwaitingGuardianShort',
    ] as const) {
      expect(all).toContain(t(`clinicAgenda.${key}`));
    }
    expect(all).toContain('Resultado pendiente');
    // Rows name the situation, never an operation, and hold no action control.
    expect(all).not.toContain(t('appointmentConfirmation.action'));
    await press(row as ReactTestInstance);
    expect(router.push).toHaveBeenCalledWith(
      professionalAppointmentDetailHref('clinic-a', 'p-request'),
    );
  });

  it('an empty first page means nothing pending, with zero totals and no "Load more"', async () => {
    pendingRead.mockResolvedValue(pendingPage([], ZERO_PENDING_TOTALS));
    await render();
    await showTab('pending');
    expect(shown()).toContain(t('clinicAgenda.pendingEmpty'));
    expect(hasSummary(`${t('clinicAgenda.categoryActionRequired')}: 0`)).toBe(true);
    expect(loadMoreButton()).toBeUndefined();
  });

  it('pages 51 Pending Appointments of three categories: 50, then the rest from the exact key', async () => {
    // 46 + 3 + 2 = 51: the first page ends inside "Waiting for the guardian".
    const action = actionRows(46, 'A');
    const informational = [0, 1, 2].map((index) =>
      pendingRow(`I-${index}`, 'GUARDIAN_PROPOSAL', { petName: `I ${index}` }),
    );
    const awaiting = [0, 1].map((index) =>
      pendingRow(`W-${index}`, 'AWAITING_GUARDIAN', {
        petName: `W ${index}`,
        currentScheduledStartAt: `2026-11-0${index + 4}T08:00:00.12345${index}+00:00`,
      }),
    );
    const firstPage = [...action, ...informational, awaiting[0]];
    expect(firstPage).toHaveLength(50);
    pendingRead.mockResolvedValueOnce(pendingPage(firstPage, totals(46, 2, 3)));
    await render();
    await showTab('pending');
    expect(pendingRowIds()).toHaveLength(50);
    expect(categoryItems()).toEqual([
      'ACTION_REQUIRED 46/46',
      'INFORMATIONAL 3/3',
      'AWAITING_GUARDIAN 1/2',
    ]);
    expect(loadMoreButton()).toBeDefined();

    // The next page repeats the last Appointment (it changed between pages) and ends the list.
    pendingRead.mockResolvedValueOnce(pendingPage([awaiting[0], awaiting[1]], totals(46, 2, 3)));
    await press(loadMoreButton() as ReactTestInstance);
    expect(pendingRead.mock.calls[1]).toEqual([
      'clinic-a',
      { rank: 5, startAt: '2026-11-04T08:00:00.123450+00:00', id: 'W-0' },
      50,
    ]);
    const ids = pendingRowIds();
    expect(ids).toHaveLength(51);
    expect(new Set(ids).size).toBe(51);
    expect(categoryItems()).toEqual([
      'ACTION_REQUIRED 46/46',
      'INFORMATIONAL 3/3',
      'AWAITING_GUARDIAN 2/2',
    ]);
    expect(loadMoreButton()).toBeUndefined();
  });

  it('an empty later page ends the list and keeps the totals already read', async () => {
    pendingRead.mockResolvedValueOnce(pendingPage(actionRows(50, 'A'), totals(50, 2, 1)));
    await render();
    await showTab('pending');
    pendingRead.mockResolvedValueOnce(pendingPage([], null));
    await press(loadMoreButton() as ReactTestInstance);
    expect(loadMoreButton()).toBeUndefined();
    expect(hasSummary(`${t('clinicAgenda.categoryActionRequired')}: 50`)).toBe(true);
    expect(hasSummary(`${t('clinicAgenda.categoryAwaitingGuardian')}: 2`)).toBe(true);
    expect(shown()).not.toContain(t('clinicAgenda.pendingEmpty'));
  });

  it('reads one page at a time, however often "Load more" is pressed', async () => {
    pendingRead.mockResolvedValueOnce(pendingPage(actionRows(50, 'A'), totals(70, 0, 0)));
    await render();
    await showTab('pending');
    const next = deferred<ClinicScheduleResult<ClinicPendingPage>>();
    pendingRead.mockReturnValueOnce(next.promise);
    const button = loadMoreButton() as ReactTestInstance;
    await act(async () => {
      button.props.onPress();
      button.props.onPress();
    });
    expect(pendingRead).toHaveBeenCalledTimes(2);
    await act(async () => next.resolve(pendingPage(actionRows(20, 'B'), totals(70, 0, 0))));
    expect(headingLabels()).toEqual([`${t('clinicAgenda.categoryActionRequired')}, 70`]);
  });

  it('a refresh discards the old cursor and ignores a "Load more" answered late', async () => {
    pendingRead.mockResolvedValueOnce(pendingPage(actionRows(50, 'A'), totals(60, 0, 0)));
    await render();
    await showTab('pending');
    const late = deferred<ClinicScheduleResult<ClinicPendingPage>>();
    pendingRead.mockReturnValueOnce(late.promise);
    await press(loadMoreButton() as ReactTestInstance);

    pendingRead.mockResolvedValueOnce(pendingPage([DECISION], totals(1, 0, 0)));
    await refocus();
    expect(pendingRead).toHaveBeenLastCalledWith('clinic-a', null, 50);
    const old = pendingRow('p-old', 'ATTENDANCE_OUTCOME', { petName: 'Viejo' });
    await act(async () => late.resolve(pendingPage([old], totals(60, 0, 0))));
    expect(shown()).toContain('Luna');
    expect(shown()).not.toContain('Viejo');
    expect(shown()).not.toContain('A 0');
    expect(loadMoreButton()).toBeUndefined();
  });

  it('a first-page failure offers a retry; a failed refresh keeps the rows with a notice', async () => {
    pendingRead.mockResolvedValueOnce(failed('Network request failed'));
    await render();
    await showTab('pending');
    expect(shown()).toContain(t('clinicAgenda.pendingError'));
    await press(retryButton() as ReactTestInstance);
    expect(shown()).toContain('Kira');

    pendingRead.mockResolvedValueOnce(failed('Network request failed'));
    await refocus();
    expect(shown()).toContain('Kira');
    expect(shown()).toContain(t('pagedList.refreshError'));
  });

  it('a "Load more" failure keeps the rows and retries from the same cursor', async () => {
    pendingRead.mockResolvedValueOnce(pendingPage(actionRows(50, 'A'), totals(60, 0, 0)));
    await render();
    await showTab('pending');
    pendingRead.mockResolvedValueOnce(failed('Network request failed'));
    await press(loadMoreButton() as ReactTestInstance);
    expect(shown()).toContain(t('pagedList.loadMoreError'));
    expect(shown()).toContain('A 0');
    pendingRead.mockResolvedValueOnce(pendingPage(actionRows(10, 'B'), totals(60, 0, 0)));
    await press(retryButton() as ReactTestInstance);
    expect(pendingRead.mock.calls[2]).toEqual(pendingRead.mock.calls[1]);
    expect(headingLabels()).toEqual([`${t('clinicAgenda.categoryActionRequired')}, 60`]);
  });

  it('an expired session shows the shared message', async () => {
    pendingRead.mockResolvedValueOnce(failed(PROFESSIONAL_CONTEXT_AUTH_REQUIRED));
    await render();
    await showTab('pending');
    expect(shown()).toContain(t('errors.sessionExpired'));
  });

  it('losing schedule access (42501) replaces the whole agenda', async () => {
    pendingRead.mockResolvedValueOnce(failed(CLINIC_SCHEDULE_ACCESS_DENIED));
    await render();
    await showTab('pending');
    expect(shown()).toContain(t('clinicSchedule.accessError'));
    expect(tree.root.findAll((node) => node.props.accessibilityRole === 'tab')).toHaveLength(0);
    expect(shown()).not.toContain('Kira');
  });

  it('localizes categories, reasons and counts in English', async () => {
    mockLocale.value = 'en';
    pendingRead.mockResolvedValueOnce(pendingPage(actionRows(50, 'A'), totals(60, 3, 1)));
    await render();
    await showTab('pending');
    expect(headingLabels()).toEqual(['Action required, 50 of 60']);
    expect(shown()).toContain('Outcome pending');
    expect(rowFor('A 0')?.props.accessibilityLabel).toContain('Visit outcome pending');
    expect(hasSummary('Waiting for the guardian: 3')).toBe(true);
    expect(hasSummary('For your information: 1')).toBe(true);
    expect(loadMoreButton()?.props.accessibilityLabel).toBe('Load more');
  });
});

describe('History', () => {
  beforeEach(() => {
    pendingRead.mockResolvedValue(pendingPage([], ZERO_PENDING_TOTALS));
    historyRead.mockResolvedValue(ok(HISTORY));
  });

  it('lists terminal Appointments as compact rows with date, time, Pet, requester and state', async () => {
    await render();
    await showTab('history');
    expect(rowFor('Coco')?.props.accessibilityLabel).toBe(
      [
        formatDayHeading('2026-11-03', 'es'),
        '9:00 – 9:30',
        'Coco',
        t('appointmentContact.requestedBy', { name: 'Marta Ruiz' }),
        t(lifecycleLabelKey('COMPLETED')),
      ].join(', '),
    );
    const all = shown();
    for (const state of ['COMPLETED', 'NO_SHOW', 'CANCELLED', 'EXPIRED'] as const) {
      expect(all).toContain(t(lifecycleLabelKey(state)));
    }
    expect(all).not.toMatch(/@/);
    expect(loadMoreButton()).toBeUndefined();
    await press(rowFor('Mia') as ReactTestInstance);
    expect(router.push).toHaveBeenCalledWith(
      professionalAppointmentDetailHref('clinic-a', 'h-cancelled'),
    );
  });

  it('pages 31 historical Appointments: 30, then the last from the exact key, without repeats', async () => {
    const first = historyRows(30, 'H');
    historyRead.mockResolvedValueOnce(ok(first));
    await render();
    await showTab('history');
    expect(historyIds()).toHaveLength(30);
    expect(loadMoreButton()).toBeDefined();

    // The repeated last row (same key, a tie) must not appear twice.
    const last = appointment('H-030', { lifecycleState: 'NO_SHOW', petName: 'H 30' });
    historyRead.mockResolvedValueOnce(ok([first[29], last]));
    await press(loadMoreButton() as ReactTestInstance);
    expect(historyRead.mock.calls).toEqual([
      ['clinic-a', null, 30],
      ['clinic-a', { startAt: '2026-10-01T08:00:00.654321+00:00', id: 'H-029' }, 30],
    ]);
    const ids = historyIds();
    expect(ids).toHaveLength(31);
    expect(new Set(ids).size).toBe(31);
    expect(ids.at(-1)).toBe('H-030');
    expect(loadMoreButton()).toBeUndefined();
  });

  it('a full first page followed by an empty one ends the list', async () => {
    historyRead.mockResolvedValueOnce(ok(historyRows(30, 'H')));
    await render();
    await showTab('history');
    historyRead.mockResolvedValueOnce(ok([]));
    await press(loadMoreButton() as ReactTestInstance);
    expect(historyIds()).toHaveLength(30);
    expect(loadMoreButton()).toBeUndefined();
    expect(shown()).not.toContain(t('clinicAgenda.historyEmpty'));
  });

  it('an empty history says so', async () => {
    historyRead.mockResolvedValue(ok([]));
    await render();
    await showTab('history');
    expect(shown()).toContain(t('clinicAgenda.historyEmpty'));
  });

  it('a first-page failure offers a retry, and 42501 replaces the agenda', async () => {
    historyRead.mockResolvedValueOnce(failed('Network request failed'));
    await render();
    await showTab('history');
    expect(shown()).toContain(t('clinicAgenda.historyError'));

    historyRead.mockResolvedValueOnce(failed(CLINIC_SCHEDULE_ACCESS_DENIED));
    await press(retryButton() as ReactTestInstance);
    expect(shown()).toContain(t('clinicSchedule.accessError'));
    expect(tree.root.findAll((node) => node.props.accessibilityRole === 'tab')).toHaveLength(0);
  });
});

describe('English', () => {
  it('localizes the month, the weekdays and the accessible names', async () => {
    mockLocale.value = 'en';
    await render();
    expect(shown()).toContain('November 2026');
    const all = texts();
    const first = all.indexOf('Mon');
    expect(all.slice(first, first + 7)).toEqual(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    expect(dayButton('2026-11-03').props.accessibilityLabel).toBe(
      'Tuesday, November 3, 2026, today, 3 appointments',
    );
    expect(dayButton('2026-11-20').props.accessibilityLabel).toBe(
      'Friday, November 20, 2026, 1 appointment',
    );
    expect(shown()).toContain('9:00 AM');
    expect(shown()).toContain('Time in America/New_York');
  });
});

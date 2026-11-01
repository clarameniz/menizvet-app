import { es } from '@/i18n/locales/es';
import { en } from '@/i18n/locales/en';
import {
  APPOINTMENT_LIFECYCLE_STATES,
  canCancelAppointment,
  canRescheduleRequestedAppointment,
  guardianCancellationPresentation,
  guardianCancellationView,
  isAppointmentLifecycleState,
  isAwaitingClinicResolution,
  isPendingRequestedAppointment,
  isScheduledStartInFuture,
  isUpcomingAppointmentState,
  lifecycleLabelKey,
  shownCancellationReason,
  showsVeterinarianAssigned,
  type AppointmentLifecycleState,
  type AppointmentScheduleRevisionContext,
} from '@/lib/appointment-lifecycle';

const ALL_STATES: AppointmentLifecycleState[] = [
  'REQUESTED',
  'CONFIRMED',
  'CANCELLED',
  'COMPLETED',
  'NO_SHOW',
  'EXPIRED',
];

// Deterministic reference instant for every time-dependent rule.
const NOW = new Date('2035-03-06T10:00:00.000Z');
const FUTURE = '2035-03-06T10:00:00.001Z';
const EXACTLY_NOW = '2035-03-06T10:00:00.000Z';
const PAST = '2035-03-06T09:59:59.999Z';

describe('lifecycle state set', () => {
  it('knows exactly the six approved states, including EXPIRED (SPEC-APT-015)', () => {
    expect([...APPOINTMENT_LIFECYCLE_STATES]).toEqual(ALL_STATES);
  });

  it.each(ALL_STATES)('accepts %s', (state) => {
    expect(isAppointmentLifecycleState(state)).toBe(true);
  });

  it.each<[string, unknown]>([
    ['an unknown value', 'ARCHIVED'],
    ['a lowercase value', 'expired'],
    ['an empty string', ''],
    ['null', null],
    ['a number', 3],
  ])('rejects %s', (_label, value) => {
    expect(isAppointmentLifecycleState(value)).toBe(false);
  });
});

describe('isScheduledStartInFuture (absolute instants, strict)', () => {
  it('is true when the start is after the reference instant', () => {
    expect(isScheduledStartInFuture(FUTURE, NOW)).toBe(true);
  });

  it('is false when the start equals the reference instant', () => {
    expect(isScheduledStartInFuture(EXACTLY_NOW, NOW)).toBe(false);
  });

  it('is false when the start is before the reference instant', () => {
    expect(isScheduledStartInFuture(PAST, NOW)).toBe(false);
  });

  it('compares instants, not offset-formatted strings', () => {
    // 11:30 at +02:00 is 09:30Z — in the past despite the larger wall-clock hour.
    expect(isScheduledStartInFuture('2035-03-06T11:30:00+02:00', NOW)).toBe(false);
    // 06:00 at -05:00 is 11:00Z — in the future despite the smaller wall-clock hour.
    expect(isScheduledStartInFuture('2035-03-06T06:00:00-05:00', NOW)).toBe(true);
  });

  it('treats an unparseable value as not in the future', () => {
    expect(isScheduledStartInFuture('soon', NOW)).toBe(false);
  });
});

describe('isPendingRequestedAppointment', () => {
  it.each([
    ['start > now', FUTURE, true],
    ['start === now', EXACTLY_NOW, false],
    ['start < now', PAST, false],
  ] as const)('REQUESTED with %s -> %s', (_label, start, expected) => {
    expect(isPendingRequestedAppointment('REQUESTED', start, NOW)).toBe(expected);
  });

  it.each(ALL_STATES.filter((state) => state !== 'REQUESTED'))(
    'is never pending for %s, even with a future start',
    (state) => {
      expect(isPendingRequestedAppointment(state, FUTURE, NOW)).toBe(false);
    },
  );

  it('leaves a REQUESTED Appointment with no known start to the backend', () => {
    expect(isPendingRequestedAppointment('REQUESTED', null, NOW)).toBe(true);
  });
});

// SPEC-APT-003 §4 / BR-2 / BR-21 / BR-23 / BR-31.
describe('canCancelAppointment', () => {
  it.each([
    ['REQUESTED', FUTURE, true],
    ['REQUESTED', EXACTLY_NOW, false],
    ['REQUESTED', PAST, false],
    ['CONFIRMED', FUTURE, true],
    ['CONFIRMED', EXACTLY_NOW, false],
    ['CONFIRMED', PAST, false],
    ['CANCELLED', FUTURE, false],
    ['COMPLETED', PAST, false],
    ['NO_SHOW', PAST, false],
    ['EXPIRED', PAST, false],
    ['EXPIRED', FUTURE, false],
  ] as const)('%s with start %s -> %s', (state, start, expected) => {
    expect(canCancelAppointment(state, start, NOW)).toBe(expected);
  });

  it('leaves a CONFIRMED Appointment without a start to the backend', () => {
    expect(canCancelAppointment('CONFIRMED', null, NOW)).toBe(true);
  });
});

// SPEC-APT-011 BR-34.
describe('isAwaitingClinicResolution', () => {
  it.each([
    ['CONFIRMED', FUTURE, false],
    ['CONFIRMED', EXACTLY_NOW, true],
    ['CONFIRMED', PAST, true],
    ['REQUESTED', PAST, false],
    ['COMPLETED', PAST, false],
    ['NO_SHOW', PAST, false],
    ['CANCELLED', PAST, false],
    ['EXPIRED', PAST, false],
  ] as const)('%s with start %s -> %s', (state, start, expected) => {
    expect(isAwaitingClinicResolution(state, start, NOW)).toBe(expected);
  });

  it('is false without a known start', () => {
    expect(isAwaitingClinicResolution('CONFIRMED', null, NOW)).toBe(false);
  });
});

// SPEC-APT-003 BR-31 / SPEC-APT-011 BR-34: device clock first, then the
// backend's rejection for the same confirmed start.
describe('guardianCancellationView', () => {
  it('offers Cancel on a future CONFIRMED Appointment, with no status note', () => {
    expect(guardianCancellationView('CONFIRMED', FUTURE, NOW, null)).toEqual({
      offersCancel: true,
      awaitingClinicResolution: false,
      closedByBackend: false,
    });
  });

  it('hides Cancel and shows the status note once the confirmed start is reached', () => {
    expect(guardianCancellationView('CONFIRMED', PAST, NOW, null)).toEqual({
      offersCancel: false,
      awaitingClinicResolution: true,
      closedByBackend: false,
    });
  });

  it('after a backend cutoff rejection, hides Cancel even when the device clock is behind', () => {
    expect(guardianCancellationView('CONFIRMED', FUTURE, NOW, FUTURE)).toEqual({
      offersCancel: false,
      awaitingClinicResolution: true,
      closedByBackend: true,
    });
  });

  it('ignores a backend rejection recorded for a different confirmed start', () => {
    expect(guardianCancellationView('CONFIRMED', FUTURE, NOW, PAST)).toEqual({
      offersCancel: true,
      awaitingClinicResolution: false,
      closedByBackend: false,
    });
  });

  it('shows the resolved outcome instead of the note once the Clinic resolved it', () => {
    for (const state of ['COMPLETED', 'NO_SHOW', 'CANCELLED'] as const) {
      expect(guardianCancellationView(state, FUTURE, NOW, FUTURE)).toEqual({
        offersCancel: false,
        awaitingClinicResolution: false,
        closedByBackend: false,
      });
    }
  });

  it('leaves REQUESTED unchanged: pending offers Cancel, lapsed hides it, never the note', () => {
    expect(guardianCancellationView('REQUESTED', FUTURE, NOW, null)).toEqual({
      offersCancel: true,
      awaitingClinicResolution: false,
      closedByBackend: false,
    });
    expect(guardianCancellationView('REQUESTED', PAST, NOW, PAST)).toEqual({
      offersCancel: false,
      awaitingClinicResolution: false,
      closedByBackend: false,
    });
  });
});

// Physical finding: an open panel must survive a render after the start, so
// the submission reaches the backend (SPEC-APT-003 BR-31 is enforced there).
describe('guardianCancellationPresentation (panel lifecycle)', () => {
  const BEFORE_START = new Date('2035-03-06T09:59:00.000Z');
  const AFTER_START = new Date('2035-03-06T10:01:00.000Z');
  const START = '2035-03-06T10:00:00.000Z';
  const present = (
    state: AppointmentLifecycleState,
    at: Date,
    panelOpen: boolean,
    backendClosedForStart: string | null = null,
  ) =>
    guardianCancellationPresentation(
      guardianCancellationView(state, START, at, backendClosedForStart),
      state,
      panelOpen,
    );

  it('a future CONFIRMED Appointment offers Cancel to open the panel', () => {
    expect(present('CONFIRMED', BEFORE_START, false)).toEqual({
      showCancelAction: true,
      showPanel: false,
      showAwaitingNote: false,
    });
  });

  it('once opened before the start, the panel shows the form instead of the action', () => {
    expect(present('CONFIRMED', BEFORE_START, true)).toEqual({
      showCancelAction: false,
      showPanel: true,
      showAwaitingNote: false,
    });
  });

  it('an open panel stays open on a render after the device clock crosses the start', () => {
    expect(present('CONFIRMED', AFTER_START, true)).toEqual({
      showCancelAction: false,
      showPanel: true,
      showAwaitingNote: false,
    });
  });

  it('after the backend cutoff rejection, the panel closes and the status note appears', () => {
    expect(present('CONFIRMED', AFTER_START, true, START)).toEqual({
      showCancelAction: false,
      showPanel: false,
      showAwaitingNote: true,
    });
    // Even with the device clock still before the start.
    expect(present('CONFIRMED', BEFORE_START, false, START)).toEqual({
      showCancelAction: false,
      showPanel: false,
      showAwaitingNote: true,
    });
  });

  it('a fresh detail after the start cannot open Cancel', () => {
    expect(present('CONFIRMED', AFTER_START, false)).toEqual({
      showCancelAction: false,
      showPanel: false,
      showAwaitingNote: true,
    });
  });

  it.each<AppointmentLifecycleState>(['CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'])(
    'an open panel closes once a re-read shows %s',
    (state) => {
      expect(present(state, BEFORE_START, true).showPanel).toBe(false);
    },
  );

  it('REQUESTED keeps its rule: an open panel survives the requested start, and the backend decides', () => {
    expect(present('REQUESTED', BEFORE_START, false).showCancelAction).toBe(true);
    expect(present('REQUESTED', AFTER_START, true).showPanel).toBe(true);
    expect(present('REQUESTED', AFTER_START, false)).toEqual({
      showCancelAction: false,
      showPanel: false,
      showAwaitingNote: false,
    });
  });
});

describe('awaiting-clinic-resolution copy', () => {
  it('is calm and implies no attendance, no-show, veterinarian, or clinical record', () => {
    expect(es.appointments.awaitingClinicResolution).toBe(
      'La hora de la cita ya ha pasado. La clínica actualizará su estado.',
    );
    expect(en.appointments.awaitingClinicResolution).toBe(
      'The scheduled appointment time has passed. The clinic will update its status.',
    );
    for (const text of [
      es.appointments.awaitingClinicResolution,
      en.appointments.awaitingClinicResolution,
    ]) {
      expect(text.toLowerCase()).not.toMatch(
        /veterinar|record|registro|historial|informe|no-show|no presentad|attend|acud|asist|complet/,
      );
    }
  });
});

// SPEC-APT-004 §4 / BR-3 / BR-27.
describe('canRescheduleRequestedAppointment', () => {
  it.each([
    ['REQUESTED', FUTURE, true],
    ['REQUESTED', EXACTLY_NOW, false],
    ['REQUESTED', PAST, false],
    ['CONFIRMED', FUTURE, false],
    ['CANCELLED', FUTURE, false],
    ['COMPLETED', PAST, false],
    ['NO_SHOW', PAST, false],
    ['EXPIRED', PAST, false],
  ] as const)('%s with start %s -> %s', (state, start, expected) => {
    expect(canRescheduleRequestedAppointment(state, start, NOW)).toBe(expected);
  });

  it('never allows a CONFIRMED Appointment to use the requested-reschedule workflow (SPEC-APT-004 BR-3)', () => {
    expect(canRescheduleRequestedAppointment('CONFIRMED', FUTURE, NOW)).toBe(false);
  });
});

describe('isUpcomingAppointmentState', () => {
  it.each([
    ['REQUESTED', true],
    ['CONFIRMED', true],
    ['CANCELLED', false],
    ['COMPLETED', false],
    ['NO_SHOW', false],
    ['EXPIRED', false],
  ] as const)('%s -> %s', (state, expected) => {
    expect(isUpcomingAppointmentState(state)).toBe(expected);
  });
});

describe('lifecycleLabelKey', () => {
  it('maps every state to a distinct translation key, never the raw enum value', () => {
    const keys = ALL_STATES.map(lifecycleLabelKey);

    expect(new Set(keys).size).toBe(ALL_STATES.length);
    for (const key of keys) {
      expect(key.startsWith('appointments.lifecycle')).toBe(true);
    }
  });

  it('maps each specific state to its documented key', () => {
    expect(lifecycleLabelKey('REQUESTED')).toBe('appointments.lifecycleRequested');
    expect(lifecycleLabelKey('CONFIRMED')).toBe('appointments.lifecycleConfirmed');
    expect(lifecycleLabelKey('CANCELLED')).toBe('appointments.lifecycleCancelled');
    expect(lifecycleLabelKey('COMPLETED')).toBe('appointments.lifecycleCompleted');
    expect(lifecycleLabelKey('NO_SHOW')).toBe('appointments.lifecycleNoShow');
    expect(lifecycleLabelKey('EXPIRED')).toBe('appointments.lifecycleExpired');
  });

  it('labels EXPIRED as its own outcome in both catalogs', () => {
    expect(es.appointments.lifecycleExpired).toBe('Expirada');
    expect(en.appointments.lifecycleExpired).toBe('Expired');
    for (const catalog of [es, en]) {
      expect(catalog.appointments.lifecycleExpired).not.toBe(
        catalog.appointments.lifecycleCancelled,
      );
      expect(catalog.appointments.lifecycleExpired).not.toBe(catalog.appointments.lifecycleNoShow);
      expect(catalog.appointments.lifecycleExpired).not.toBe(
        catalog.appointments.lifecycleCompleted,
      );
    }
  });

  // Regression coverage for the scheduling-history screen (Appointment
  // detail route) showing a raw `revision_context` token such as
  // "REQUESTED · <date>" instead of the localized label in either catalog.
  const SCHEDULE_REVISION_CONTEXTS: AppointmentScheduleRevisionContext[] = [
    'REQUESTED',
    'CONFIRMED',
  ];

  it.each(SCHEDULE_REVISION_CONTEXTS)(
    'resolves %s scheduling-history entries to a localized label in both catalogs, never the raw token',
    (revisionContext) => {
      const key = lifecycleLabelKey(revisionContext);
      const [section, field] = key.split('.') as ['appointments', keyof typeof es.appointments];

      expect(es[section][field]).not.toBe(revisionContext);
      expect(en[section][field]).not.toBe(revisionContext);
    },
  );
});

describe('shownCancellationReason (SPEC-APT-011 BR-31)', () => {
  it('shows the recorded reason of a CANCELLED Appointment', () => {
    expect(shownCancellationReason('CANCELLED', 'Clinic closed that day')).toBe(
      'Clinic closed that day',
    );
  });

  it('shows nothing for a CANCELLED Appointment cancelled without a reason', () => {
    expect(shownCancellationReason('CANCELLED', null)).toBeNull();
  });

  it.each<AppointmentLifecycleState>(['REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'])(
    'never shows a reason as a cancellation reason on a %s Appointment',
    (state) => {
      expect(shownCancellationReason(state, 'Some text')).toBeNull();
    },
  );
});

describe('showsVeterinarianAssigned (optional Veterinarian Assignment)', () => {
  it('shows nothing without any Veterinarian Assignment — absence is not a pending state', () => {
    expect(showsVeterinarianAssigned([])).toBe(false);
  });

  it('shows nothing when every Veterinarian Assignment has ended', () => {
    expect(
      showsVeterinarianAssigned([
        { effectiveEnd: '2035-01-01T09:00:00Z' },
        { effectiveEnd: '2035-01-02T09:00:00Z' },
      ]),
    ).toBe(false);
  });

  it('shows the assigned note while a current Veterinarian Assignment exists', () => {
    expect(
      showsVeterinarianAssigned([{ effectiveEnd: '2035-01-01T09:00:00Z' }, { effectiveEnd: null }]),
    ).toBe(true);
  });

  it('has no "not assigned yet" copy in either catalog', () => {
    expect('noVeterinarianAssigned' in es.appointments).toBe(false);
    expect('noVeterinarianAssigned' in en.appointments).toBe(false);
  });
});

// SPEC-APT-011 §6 / BR-34: the non-terminal tab holds started CONFIRMED
// Appointments too, so it is never labelled "Upcoming".
describe('Active tab label', () => {
  it('labels the non-terminal tab Active, not Upcoming', () => {
    expect(es.appointments.activeSectionTitle).toBe('Activas');
    expect(en.appointments.activeSectionTitle).toBe('Active');
    expect('upcomingSectionTitle' in es.appointments).toBe(false);
    expect('upcomingSectionTitle' in en.appointments).toBe(false);
  });
});

describe('cancellation reason label', () => {
  it('is localized in both catalogs', () => {
    expect(es.appointments.cancellationReasonLabel).toBe('Motivo de la cancelación');
    expect(en.appointments.cancellationReasonLabel).toBe('Cancellation reason');
  });
});

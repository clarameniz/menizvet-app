import type {
  AvailabilityException,
  AvailabilityPeriod,
  ClinicAppointmentHours,
} from '@/data/clinic-appointment-hours';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { ProfessionalContext } from '@/data/professional-context';
import {
  accessNoticeKey,
  appointmentHoursAccess,
  appointmentHoursHref,
  canEditAvailability,
  canEditDuration,
  canSaveConfiguration,
  displayLocalTime,
  exceptionDateIssue,
  exceptionDateWindow,
  exceptionDraftFrom,
  exceptionMatches,
  exceptionPayload,
  exceptionPresentation,
  formatTimeRanges,
  isDurationPreset,
  isExceptionDraftChanged,
  isExceptionDraftValid,
  isWeeklyDraftChanged,
  isWeeklyDraftValid,
  isoWeekdayOfLocalDate,
  localTimeMicroseconds,
  newPeriodDraft,
  normalizeTimeInput,
  offersAppointmentHours,
  parseDurationInput,
  periodIssues,
  prefillCustomHours,
  sameWeeklyAvailability,
  upcomingExceptions,
  weeklyDraftFrom,
  weeklyPayload,
  weeklyEditorAfterRead,
  weeklyEditorFrom,
  weeklySaveFailure,
  type ExceptionDraft,
  type PeriodDraft,
} from '@/lib/appointment-hours';

const periods = (...ranges: [string, string][]): PeriodDraft[] =>
  ranges.map(([start, end]) => newPeriodDraft(start, end));

const withoutIds = (drafts: readonly PeriodDraft[]) =>
  drafts.map(({ start, end }) => ({ start, end }));

const WEEK: AvailabilityPeriod[] = [
  { isoWeekday: 1, startTime: '09:00:00', endTime: '13:00:00' },
  { isoWeekday: 1, startTime: '16:00:00', endTime: '20:00:00' },
  { isoWeekday: 2, startTime: '09:00:00', endTime: '20:00:00' },
];

describe('local times', () => {
  it.each([
    ['09:00', 9 * 3600e6],
    ['09:00:00', 9 * 3600e6],
    ['08:30:15', (8 * 3600 + 30 * 60 + 15) * 1e6],
    ['08:30:15.5', (8 * 3600 + 30 * 60 + 15) * 1e6 + 500000],
    ['00:00', 0],
    ['24:00', 24 * 3600e6],
    ['24:00:00', 24 * 3600e6],
  ])('parses %s like the backend', (text, expected) => {
    expect(localTimeMicroseconds(text)).toBe(expected);
  });

  it.each(['9:00', '25:00', '24:01', '12:60', 'noon', '', '09:00:00.1234567', ' 09:00'])(
    'rejects %p',
    (text) => {
      expect(localTimeMicroseconds(text)).toBeNull();
    },
  );

  it('displays whole minutes as HH:MM and keeps finer precision verbatim', () => {
    expect(displayLocalTime('09:00:00')).toBe('09:00');
    expect(displayLocalTime('24:00:00')).toBe('24:00');
    expect(displayLocalTime('08:30:15')).toBe('08:30:15');
    expect(displayLocalTime('08:30:00.000001')).toBe('08:30:00.000001');
  });

  it('tidies typed digits on blur but never guesses', () => {
    expect(normalizeTimeInput('930')).toBe('09:30');
    expect(normalizeTimeInput('0930')).toBe('09:30');
    expect(normalizeTimeInput(' 9:30 ')).toBe('09:30');
    expect(normalizeTimeInput('2400')).toBe('24:00');
    expect(normalizeTimeInput('9.30')).toBe('9.30');
    expect(normalizeTimeInput('93')).toBe('93');
  });

  it('formats ranges for display', () => {
    expect(
      formatTimeRanges([
        { startTime: '09:00:00', endTime: '13:00:00' },
        { startTime: '16:00:00', endTime: '20:00:00' },
      ]),
    ).toBe('09:00–13:00, 16:00–20:00');
  });
});

describe('periodIssues', () => {
  it('accepts valid and touching periods', () => {
    expect(periodIssues(periods(['09:00', '13:00'], ['13:00', '14:00']))).toEqual([null, null]);
  });

  it('flags overlaps on both periods, including identical ones', () => {
    expect(periodIssues(periods(['09:00', '13:00'], ['12:00', '14:00']))).toEqual([
      'overlap',
      'overlap',
    ]);
    expect(periodIssues(periods(['09:00', '13:00'], ['09:00', '13:00']))).toEqual([
      'overlap',
      'overlap',
    ]);
  });

  it('reports the first problem of each period', () => {
    expect(
      periodIssues(
        periods(
          ['', '10:00'],
          ['9:0', '10:00'],
          ['09:00', ''],
          ['09:00', '25:00'],
          ['20:00', '02:00'],
          ['13:00', '13:00'],
        ),
      ),
    ).toEqual(['startRequired', 'startInvalid', 'endRequired', 'endInvalid', 'order', 'order']);
  });

  it('does not count an invalid period as an overlap for the others', () => {
    expect(periodIssues(periods(['09:00', '13:00'], ['12:00', '11:00']))).toEqual([null, 'order']);
  });

  it('accepts a 24:00 end and rejects a 24:00 start', () => {
    expect(periodIssues(periods(['20:00', '24:00'], ['24:00', '24:00']))).toEqual([null, 'order']);
  });
});

describe('weekly draft (full replacement)', () => {
  it('groups stored periods by weekday with display times', () => {
    const draft = weeklyDraftFrom(WEEK);
    expect(withoutIds(draft[1])).toEqual([
      { start: '09:00', end: '13:00' },
      { start: '16:00', end: '20:00' },
    ]);
    expect(withoutIds(draft[2])).toEqual([{ start: '09:00', end: '20:00' }]);
    expect(draft[7]).toEqual([]);
  });

  it('round-trips unchanged, including stored second precision', () => {
    const stored: AvailabilityPeriod[] = [
      ...WEEK,
      { isoWeekday: 3, startTime: '08:30:15', endTime: '12:45:30' },
    ];
    const draft = weeklyDraftFrom(stored);
    expect(isWeeklyDraftValid(draft)).toBe(true);
    expect(isWeeklyDraftChanged(draft, stored)).toBe(false);
    expect(weeklyPayload(draft)).toContainEqual({
      isoWeekday: 3,
      startTime: '08:30:15',
      endTime: '12:45:30',
    });
  });

  it('submits the complete week ordered by weekday and start', () => {
    const draft = weeklyDraftFrom(WEEK);
    draft[5] = periods(['16:00', '20:00'], ['09:00', '13:00']);
    expect(weeklyPayload(draft)).toEqual([
      { isoWeekday: 1, startTime: '09:00', endTime: '13:00' },
      { isoWeekday: 1, startTime: '16:00', endTime: '20:00' },
      { isoWeekday: 2, startTime: '09:00', endTime: '20:00' },
      { isoWeekday: 5, startTime: '09:00', endTime: '13:00' },
      { isoWeekday: 5, startTime: '16:00', endTime: '20:00' },
    ]);
    expect(isWeeklyDraftChanged(draft, WEEK)).toBe(true);
  });

  it('treats a closed day (no periods) as valid and an emptied week as a change', () => {
    const draft = weeklyDraftFrom(WEEK);
    draft[1] = [];
    draft[2] = [];
    expect(isWeeklyDraftValid(draft)).toBe(true);
    expect(weeklyPayload(draft)).toEqual([]);
    expect(isWeeklyDraftChanged(draft, WEEK)).toBe(true);
  });

  it('is invalid with any problem on any day', () => {
    const draft = weeklyDraftFrom(WEEK);
    draft[4] = periods(['10:00', '']);
    expect(isWeeklyDraftValid(draft)).toBe(false);
  });

  it('compares weeks by time, not text or order (lost-response reconciliation)', () => {
    expect(
      sameWeeklyAvailability(
        [
          { isoWeekday: 1, startTime: '16:00', endTime: '20:00' },
          { isoWeekday: 1, startTime: '09:00', endTime: '13:00' },
        ],
        [
          { isoWeekday: 1, startTime: '09:00:00', endTime: '13:00:00' },
          { isoWeekday: 1, startTime: '16:00:00', endTime: '20:00:00' },
        ],
      ),
    ).toBe(true);
    expect(sameWeeklyAvailability(WEEK, WEEK.slice(1))).toBe(false);
    expect(
      sameWeeklyAvailability(
        [{ isoWeekday: 1, startTime: '09:00', endTime: '13:00' }],
        [{ isoWeekday: 2, startTime: '09:00', endTime: '13:00' }],
      ),
    ).toBe(false);
  });
});

describe('exceptions', () => {
  const closed: AvailabilityException = { localDate: '2026-10-06', kind: 'CLOSED' };
  const sundayOpen: AvailabilityException = {
    localDate: '2026-10-11',
    kind: 'OPEN',
    periods: [{ startTime: '10:00:00', endTime: '13:00:00' }],
  };
  const mondayCustom: AvailabilityException = {
    localDate: '2026-10-12',
    kind: 'OPEN',
    periods: [{ startTime: '09:00:00', endTime: '14:00:00' }],
  };

  it('knows the ISO weekday of a calendar date', () => {
    expect(isoWeekdayOfLocalDate('2026-10-11')).toBe(7);
    expect(isoWeekdayOfLocalDate('2026-10-12')).toBe(1);
    expect(isoWeekdayOfLocalDate('2026-10-13')).toBe(2);
  });

  it('presents only Clinic-local today and later, by date', () => {
    const past: AvailabilityException = { localDate: '2026-10-03', kind: 'CLOSED' };
    expect(upcomingExceptions([mondayCustom, past, closed, sundayOpen], '2026-10-06')).toEqual([
      closed,
      sundayOpen,
      mondayCustom,
    ]);
    expect(upcomingExceptions([closed], null)).toEqual([]);
  });

  it('classifies for presentation only', () => {
    expect(exceptionPresentation(closed, WEEK)).toBe('closedAllDay');
    expect(exceptionPresentation(sundayOpen, WEEK)).toBe('openExceptionally');
    expect(exceptionPresentation(mondayCustom, WEEK)).toBe('customHours');
  });

  it('prefills custom hours from the weekday, or starts empty on a closed day', () => {
    expect(withoutIds(prefillCustomHours('2026-10-12', WEEK))).toEqual([
      { start: '09:00', end: '13:00' },
      { start: '16:00', end: '20:00' },
    ]);
    expect(withoutIds(prefillCustomHours('2026-10-13', WEEK))).toEqual([
      { start: '09:00', end: '20:00' },
    ]);
    expect(withoutIds(prefillCustomHours('2026-10-11', WEEK))).toEqual([{ start: '', end: '' }]);
  });

  it('requires a real date from Clinic-local today', () => {
    expect(exceptionDateIssue(null, '2026-10-06')).toBe('required');
    expect(exceptionDateIssue('2026-02-30', '2026-10-06')).toBe('invalid');
    expect(exceptionDateIssue('2026-10-05', '2026-10-06')).toBe('past');
    expect(exceptionDateIssue('2026-10-06', '2026-10-06')).toBeNull();
  });

  it('validates a draft: date, kind, and for OPEN at least one valid period', () => {
    const base: ExceptionDraft = { localDate: '2026-10-11', kind: null, periods: [] };
    const today = '2026-10-06';
    expect(isExceptionDraftValid(base, today)).toBe(false);
    expect(isExceptionDraftValid({ ...base, kind: 'CLOSED' }, today)).toBe(true);
    expect(isExceptionDraftValid({ ...base, localDate: null, kind: 'CLOSED' }, today)).toBe(false);
    expect(isExceptionDraftValid({ ...base, kind: 'OPEN' }, today)).toBe(false);
    expect(
      isExceptionDraftValid({ ...base, kind: 'OPEN', periods: periods(['10:00', '13:00']) }, today),
    ).toBe(true);
    expect(
      isExceptionDraftValid(
        { ...base, kind: 'OPEN', periods: periods(['10:00', '13:00'], ['12:00', '14:00']) },
        today,
      ),
    ).toBe(false);
  });

  it('writes CLOSED without periods and OPEN with sorted periods', () => {
    expect(
      exceptionPayload({
        localDate: '2026-10-11',
        kind: 'CLOSED',
        periods: periods(['10:00', '13:00']),
      }),
    ).toEqual({ kind: 'CLOSED' });
    expect(
      exceptionPayload({
        localDate: '2026-10-11',
        kind: 'OPEN',
        periods: periods(['16:00', '18:00'], [' 10:00', '13:00 ']),
      }),
    ).toEqual({
      kind: 'OPEN',
      periods: [
        { startTime: '10:00', endTime: '13:00' },
        { startTime: '16:00', endTime: '18:00' },
      ],
    });
  });

  it('detects changes against the stored exception of the date', () => {
    const draft = exceptionDraftFrom(sundayOpen);
    expect(draft.kind).toBe('OPEN');
    expect(isExceptionDraftChanged(draft, sundayOpen)).toBe(false);
    expect(isExceptionDraftChanged({ ...draft, kind: 'CLOSED' }, sundayOpen)).toBe(true);
    expect(isExceptionDraftChanged(draft, null)).toBe(true);
    expect(isExceptionDraftChanged(exceptionDraftFrom(closed), closed)).toBe(false);
  });

  it('matches the stored state after a lost response', () => {
    expect(
      exceptionMatches(sundayOpen, {
        kind: 'OPEN',
        periods: [{ startTime: '10:00', endTime: '13:00' }],
      }),
    ).toBe(true);
    expect(exceptionMatches(sundayOpen, { kind: 'CLOSED' })).toBe(false);
    expect(exceptionMatches(null, { kind: 'CLOSED' })).toBe(false);
    expect(exceptionMatches(closed, { kind: 'CLOSED' })).toBe(true);
  });

  it('offers consecutive date windows across month ends', () => {
    const window = exceptionDateWindow('2026-10-25');
    expect(window).toHaveLength(14);
    expect(window[0]).toBe('2026-10-25');
    expect(window[7]).toBe('2026-11-01');
    expect(window[13]).toBe('2026-11-07');
  });
});

describe('standard duration', () => {
  it.each([
    ['10', 10],
    ['240', 240],
    [' 45 ', 45],
    ['9', null],
    ['241', null],
    ['30.5', null],
    ['', null],
    ['abc', null],
    ['-30', null],
  ])('parses %p as %p', (text, expected) => {
    expect(parseDurationInput(text)).toBe(expected);
  });

  it('recognizes presets', () => {
    expect(isDurationPreset(30)).toBe(true);
    expect(isDurationPreset(35)).toBe(false);
    expect(isDurationPreset(null)).toBe(false);
  });
});

describe('access and Save readiness', () => {
  const clinic = (capabilities: ProfessionalClinic['capabilities']): ProfessionalClinic => ({
    clinicId: 'c-1',
    clinicDisplayName: 'Animalia',
    organizationId: 'o-1',
    organizationDisplayName: 'Animalia Group',
    capabilities,
    unknownCapabilities: [],
  });

  const context = (scheduling: boolean): ProfessionalContext => ({
    hasVeterinarianProfessionalProfile: false,
    organizations: [
      {
        membershipId: 'm-1',
        organizationId: 'o-1',
        organizationDisplayName: 'Animalia Group',
        responsibilities: [],
        capabilities: [],
        unknownCapabilities: [],
        clinicAssignments: [],
        entitlements: {
          APPOINTMENT_MANAGEMENT: true,
          PROFESSIONAL_SCHEDULING: scheduling,
          CLINICAL_CARE: true,
          CLINICAL_DOCUMENTATION: true,
        },
      },
    ],
  });

  const config = (timezone: string | null): ClinicAppointmentHours => ({
    schedulingTimezoneName: timezone,
    standardAppointmentDurationMinutes: 30,
    recurringPeriods: [],
    weeklyAvailabilityRevision: 0,
    exceptions: [],
  });

  it('offers Appointment hours only with APPOINTMENT_MANAGE_AVAILABILITY', () => {
    expect(offersAppointmentHours(clinic(['APPOINTMENT_MANAGE_AVAILABILITY']))).toBe(true);
    expect(
      offersAppointmentHours(clinic(['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE'])),
    ).toBe(false);
  });

  it('is read-only without PROFESSIONAL_SCHEDULING or an Organization in context', () => {
    expect(appointmentHoursAccess(context(true), 'o-1')).toBe('editable');
    expect(appointmentHoursAccess(context(false), 'o-1')).toBe('readOnly');
    expect(appointmentHoursAccess(context(true), 'o-other')).toBe('readOnly');
  });

  it('is unconfirmed, never editable, when the professional context could not be read', () => {
    expect(appointmentHoursAccess(null, 'o-1')).toBe('unconfirmed');
    expect(canEditAvailability(config('Europe/Madrid'), 'unconfirmed')).toBe(false);
    expect(canEditDuration('unconfirmed')).toBe(false);
  });

  it('explains every access that withholds editing', () => {
    expect(accessNoticeKey('editable')).toBeNull();
    expect(accessNoticeKey('readOnly')).toBe('appointmentHours.readOnlyNotice');
    expect(accessNoticeKey('unconfirmed')).toBe('appointmentHours.accessUnconfirmedNotice');
  });

  it('needs the Clinic timezone for weekly hours and exceptions, not for the duration', () => {
    expect(canEditAvailability(config('Europe/Madrid'), 'editable')).toBe(true);
    expect(canEditAvailability(config(null), 'editable')).toBe(false);
    expect(canEditAvailability(config('Europe/Madrid'), 'readOnly')).toBe(false);
    expect(canEditDuration('editable')).toBe(true);
    expect(canEditDuration('readOnly')).toBe(false);
  });

  it('enables Save only when editable, valid, changed, and idle', () => {
    const ready = { editable: true, valid: true, changed: true, busy: false };
    expect(canSaveConfiguration(ready)).toBe(true);
    expect(canSaveConfiguration({ ...ready, editable: false })).toBe(false);
    expect(canSaveConfiguration({ ...ready, valid: false })).toBe(false);
    expect(canSaveConfiguration({ ...ready, changed: false })).toBe(false);
    expect(canSaveConfiguration({ ...ready, busy: true })).toBe(false);
  });
});

describe('appointmentHoursHref', () => {
  it('targets the Clinic Appointment hours route', () => {
    expect(appointmentHoursHref('c-1')).toEqual({
      pathname: '/professional/clinics/[clinicId]/appointment-hours',
      params: { clinicId: 'c-1' },
    });
  });
});

describe('weekly editor base revision and failed saves (BR-75)', () => {
  const week = (...items: [IsoWeekdayLike, string, string][]): AvailabilityPeriod[] =>
    items.map(([isoWeekday, startTime, endTime]) => ({ isoWeekday, startTime, endTime }));
  type IsoWeekdayLike = 1 | 2 | 3 | 4 | 5 | 6 | 7;

  const hours = (
    recurringPeriods: AvailabilityPeriod[],
    revision: number,
  ): ClinicAppointmentHours => ({
    schedulingTimezoneName: 'Europe/Madrid',
    standardAppointmentDurationMinutes: 30,
    recurringPeriods,
    weeklyAvailabilityRevision: revision,
    exceptions: [],
  });

  const mondayAndFriday = week([1, '09:00:00', '13:00:00'], [5, '09:00:00', '13:00:00']);

  it('captures the draft and the revision of the same read', () => {
    const editor = weeklyEditorFrom(hours(mondayAndFriday, 4));
    expect(editor.baseRevision).toBe(4);
    expect(weeklyPayload(editor.draft)).toEqual(week([1, '09:00', '13:00'], [5, '09:00', '13:00']));
  });

  it('accepts revision 0 for a week that never changed', () => {
    expect(weeklyEditorFrom(hours([], 0)).baseRevision).toBe(0);
  });

  it('keeps the draft and its base revision when a later read arrives', () => {
    const editor = weeklyEditorFrom(hours(mondayAndFriday, 4));
    const later = hours(week([1, '10:00:00', '14:00:00']), 5);
    expect(weeklyEditorAfterRead(editor, later)).toBe(editor);
    expect(weeklyEditorAfterRead(null, later).baseRevision).toBe(5);
  });

  it('treats a stored week equal to the submitted one as committed (lost response)', () => {
    expect(
      weeklySaveFailure({
        stale: false,
        latest: hours(mondayAndFriday, 5),
        submitted: week([5, '09:00', '13:00'], [1, '09:00', '13:00']),
      }),
    ).toEqual({ kind: 'committed' });
  });

  it('treats a stale rejection whose desired week is already stored as committed', () => {
    expect(
      weeklySaveFailure({
        stale: true,
        latest: hours(mondayAndFriday, 6),
        submitted: mondayAndFriday,
      }),
    ).toEqual({ kind: 'committed' });
  });

  it('replaces the draft and base revision with the latest week on a stale rejection', () => {
    const latest = hours(week([1, '10:00:00', '14:00:00'], [5, '09:00:00', '13:00:00']), 6);
    const outcome = weeklySaveFailure({
      stale: true,
      latest,
      submitted: week([1, '09:00', '13:00'], [5, '10:00', '14:00']),
    });
    expect(outcome.kind).toBe('stale');
    if (outcome.kind !== 'stale') return;
    expect(outcome.editor.baseRevision).toBe(6);
    expect(weeklyPayload(outcome.editor.draft)).toEqual(
      week([1, '10:00', '14:00'], [5, '09:00', '13:00']),
    );
  });

  it('keeps the draft on any other failure, including a stale rejection without a fresh read', () => {
    const submitted = week([1, '09:00', '13:00']);
    expect(
      weeklySaveFailure({ stale: false, latest: hours(mondayAndFriday, 5), submitted }),
    ).toEqual({ kind: 'failed' });
    expect(weeklySaveFailure({ stale: true, latest: null, submitted })).toEqual({
      kind: 'failed',
    });
  });

  it('leaves an unchanged draft unsaveable as before', () => {
    const editor = weeklyEditorFrom(hours(mondayAndFriday, 4));
    expect(isWeeklyDraftChanged(editor.draft, mondayAndFriday)).toBe(false);
  });
});

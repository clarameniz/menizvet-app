import {
  APPOINTMENT_HOURS_ACCESS_DENIED,
  APPOINTMENT_HOURS_INVALID_REQUEST,
  APPOINTMENT_HOURS_MALFORMED,
  APPOINTMENT_HOURS_WEEKLY_STALE,
  clearAvailabilityException,
  getClinicAppointmentHours,
  parseClinicAppointmentHours,
  replaceWeeklyAvailability,
  setAvailabilityException,
  setStandardAppointmentDuration,
} from '@/data/clinic-appointment-hours';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const CLINIC_ID = '11111111-1111-4111-8111-111111111111';

const row = (overrides: Record<string, unknown> = {}) => ({
  scheduling_timezone_name: 'Europe/Madrid',
  standard_appointment_duration_minutes: 30,
  recurring_periods: [
    { iso_weekday: 1, start_time: '09:00:00', end_time: '13:00:00' },
    { iso_weekday: 1, start_time: '16:00:00', end_time: '20:00:00' },
    { iso_weekday: 6, start_time: '20:00:00', end_time: '24:00:00' },
  ],
  exceptions: [
    {
      local_date: '2026-10-11',
      exception_kind: 'OPEN',
      start_time: '12:00:00',
      end_time: '13:00:00',
    },
    {
      local_date: '2026-10-11',
      exception_kind: 'OPEN',
      start_time: '10:00:00',
      end_time: '11:00:00',
    },
    { local_date: '2026-10-13', exception_kind: 'CLOSED', start_time: null, end_time: null },
  ],
  weekly_appointment_availability_revision: 7,
  ...overrides,
});

const rpc = supabase.rpc as jest.Mock;
afterEach(() => rpc.mockReset());

describe('parseClinicAppointmentHours (SPEC-APT-013 BR-74)', () => {
  it('reshapes the single row: timezone, duration, periods, and exceptions grouped by date', () => {
    expect(parseClinicAppointmentHours([row()])).toEqual({
      schedulingTimezoneName: 'Europe/Madrid',
      standardAppointmentDurationMinutes: 30,
      recurringPeriods: [
        { isoWeekday: 1, startTime: '09:00:00', endTime: '13:00:00' },
        { isoWeekday: 1, startTime: '16:00:00', endTime: '20:00:00' },
        { isoWeekday: 6, startTime: '20:00:00', endTime: '24:00:00' },
      ],
      weeklyAvailabilityRevision: 7,
      exceptions: [
        {
          localDate: '2026-10-11',
          kind: 'OPEN',
          periods: [
            { startTime: '10:00:00', endTime: '11:00:00' },
            { startTime: '12:00:00', endTime: '13:00:00' },
          ],
        },
        { localDate: '2026-10-13', kind: 'CLOSED' },
      ],
    });
  });

  it('accepts an unconfigured Clinic: no timezone, no duration, nothing configured', () => {
    expect(
      parseClinicAppointmentHours([
        row({
          scheduling_timezone_name: null,
          standard_appointment_duration_minutes: null,
          recurring_periods: [],
          exceptions: [],
          weekly_appointment_availability_revision: 0,
        }),
      ]),
    ).toEqual({
      schedulingTimezoneName: null,
      standardAppointmentDurationMinutes: null,
      recurringPeriods: [],
      weeklyAvailabilityRevision: 0,
      exceptions: [],
    });
  });

  it('keeps stored second and microsecond precision verbatim', () => {
    const parsed = parseClinicAppointmentHours([
      row({
        recurring_periods: [{ iso_weekday: 3, start_time: '08:30:15', end_time: '12:45:30.5' }],
      }),
    ]);
    expect(parsed?.recurringPeriods).toEqual([
      { isoWeekday: 3, startTime: '08:30:15', endTime: '12:45:30.5' },
    ]);
  });

  it.each<[string, unknown]>([
    ['not an array', row()],
    ['no row', []],
    ['two rows', [row(), row()]],
    ['a non-object row', ['x']],
    ['an empty timezone', [row({ scheduling_timezone_name: '' })]],
    ['a numeric timezone', [row({ scheduling_timezone_name: 1 })]],
    ['a duration below 10', [row({ standard_appointment_duration_minutes: 9 })]],
    ['a duration above 240', [row({ standard_appointment_duration_minutes: 241 })]],
    ['a fractional duration', [row({ standard_appointment_duration_minutes: 30.5 })]],
    ['a string duration', [row({ standard_appointment_duration_minutes: '30' })]],
    ['periods not an array', [row({ recurring_periods: {} })]],
    ['no weekly revision', [row({ weekly_appointment_availability_revision: undefined })]],
    ['a null weekly revision', [row({ weekly_appointment_availability_revision: null })]],
    ['a negative weekly revision', [row({ weekly_appointment_availability_revision: -1 })]],
    ['a fractional weekly revision', [row({ weekly_appointment_availability_revision: 1.5 })]],
    ['a string weekly revision', [row({ weekly_appointment_availability_revision: '7' })]],
    [
      'an unsafe weekly revision',
      [row({ weekly_appointment_availability_revision: Number.MAX_SAFE_INTEGER + 1 })],
    ],
    [
      'weekday 0',
      [row({ recurring_periods: [{ iso_weekday: 0, start_time: '09:00', end_time: '10:00' }] })],
    ],
    [
      'weekday 8',
      [row({ recurring_periods: [{ iso_weekday: 8, start_time: '09:00', end_time: '10:00' }] })],
    ],
    [
      'an invalid time',
      [row({ recurring_periods: [{ iso_weekday: 1, start_time: '9:00', end_time: '10:00' }] })],
    ],
    [
      'start not before end',
      [row({ recurring_periods: [{ iso_weekday: 1, start_time: '10:00', end_time: '10:00' }] })],
    ],
    ['exceptions not an array', [row({ exceptions: null })]],
    [
      'an unknown exception kind',
      [
        row({
          exceptions: [
            {
              local_date: '2026-10-11',
              exception_kind: 'PARTIAL',
              start_time: null,
              end_time: null,
            },
          ],
        }),
      ],
    ],
    [
      'a CLOSED exception with times',
      [
        row({
          exceptions: [
            {
              local_date: '2026-10-11',
              exception_kind: 'CLOSED',
              start_time: '09:00:00',
              end_time: '10:00:00',
            },
          ],
        }),
      ],
    ],
    [
      'an OPEN exception without times',
      [
        row({
          exceptions: [
            { local_date: '2026-10-11', exception_kind: 'OPEN', start_time: null, end_time: null },
          ],
        }),
      ],
    ],
    [
      'CLOSED and OPEN on the same date',
      [
        row({
          exceptions: [
            {
              local_date: '2026-10-11',
              exception_kind: 'CLOSED',
              start_time: null,
              end_time: null,
            },
            {
              local_date: '2026-10-11',
              exception_kind: 'OPEN',
              start_time: '09:00:00',
              end_time: '10:00:00',
            },
          ],
        }),
      ],
    ],
    [
      'an impossible date',
      [
        row({
          exceptions: [
            {
              local_date: '2026-02-30',
              exception_kind: 'CLOSED',
              start_time: null,
              end_time: null,
            },
          ],
        }),
      ],
    ],
  ])('rejects %s', (_label, raw) => {
    expect(parseClinicAppointmentHours(raw)).toBeNull();
  });
});

describe('getClinicAppointmentHours', () => {
  it('calls the management read with the Clinic id', async () => {
    rpc.mockResolvedValue({ data: [row()], error: null });

    const result = await getClinicAppointmentHours(CLINIC_ID);

    expect(rpc).toHaveBeenCalledWith('get_managed_clinic_appointment_availability', {
      p_clinic_id: CLINIC_ID,
    });
    expect(result.error).toBeNull();
    expect(result.data?.standardAppointmentDurationMinutes).toBe(30);
  });

  it.each([
    ['28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED],
    ['42501', APPOINTMENT_HOURS_ACCESS_DENIED],
  ])('normalizes SQLSTATE %s', async (code, expected) => {
    rpc.mockResolvedValue({ data: null, error: { code, message: 'raw backend text' } });
    expect(await getClinicAppointmentHours(CLINIC_ID)).toEqual({ data: null, error: expected });
  });

  it('keeps any other read error as backend text, not as access denied', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '23503', message: 'raw backend text' } });
    expect(await getClinicAppointmentHours(CLINIC_ID)).toEqual({
      data: null,
      error: 'raw backend text',
    });
  });

  it('reports a malformed payload', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    expect(await getClinicAppointmentHours(CLINIC_ID)).toEqual({
      data: null,
      error: APPOINTMENT_HOURS_MALFORMED,
    });
  });

  it('settles a network rejection into the result', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));
    expect(await getClinicAppointmentHours(CLINIC_ID)).toEqual({
      data: null,
      error: 'Network request failed',
    });
  });

  it('never calls the backend for a malformed Clinic id', async () => {
    expect(await getClinicAppointmentHours('not-a-uuid')).toEqual({
      data: null,
      error: APPOINTMENT_HOURS_ACCESS_DENIED,
    });
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('replaceWeeklyAvailability', () => {
  it('submits the complete week in backend member names', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });

    const result = await replaceWeeklyAvailability(
      CLINIC_ID,
      [
        { isoWeekday: 1, startTime: '09:00', endTime: '13:00' },
        { isoWeekday: 1, startTime: '13:00', endTime: '14:00' },
        { isoWeekday: 3, startTime: '08:30:15', endTime: '24:00' },
      ],
      3,
    );

    expect(rpc).toHaveBeenCalledWith('replace_clinic_appointment_availability', {
      p_clinic_id: CLINIC_ID,
      p_periods: [
        { iso_weekday: 1, start_time: '09:00', end_time: '13:00' },
        { iso_weekday: 1, start_time: '13:00', end_time: '14:00' },
        { iso_weekday: 3, start_time: '08:30:15', end_time: '24:00' },
      ],
      p_expected_weekly_availability_revision: 3,
    });
    expect(result).toEqual({ data: null, error: null });
  });

  it('submits an empty week to clear all recurring hours, from revision 0', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    await replaceWeeklyAvailability(CLINIC_ID, [], 0);
    expect(rpc).toHaveBeenCalledWith('replace_clinic_appointment_availability', {
      p_clinic_id: CLINIC_ID,
      p_periods: [],
      p_expected_weekly_availability_revision: 0,
    });
  });

  it.each([[-1], [1.5], [Number.NaN], [Number.MAX_SAFE_INTEGER + 1]])(
    'rejects expected revision %s without calling the backend',
    async (revision) => {
      expect(await replaceWeeklyAvailability(CLINIC_ID, [], revision)).toEqual({
        data: null,
        error: APPOINTMENT_HOURS_INVALID_REQUEST,
      });
      expect(rpc).not.toHaveBeenCalled();
    },
  );

  it('normalizes the stale-revision rejection', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: 'P0001', message: 'Stale weekly Clinic Appointment Availability revision' },
    });
    expect(await replaceWeeklyAvailability(CLINIC_ID, [], 3)).toEqual({
      data: null,
      error: APPOINTMENT_HOURS_WEEKLY_STALE,
    });
  });

  it('rejects an invalid period without calling the backend', async () => {
    expect(
      await replaceWeeklyAvailability(
        CLINIC_ID,
        [{ isoWeekday: 1, startTime: '13:00', endTime: '09:00' }],
        3,
      ),
    ).toEqual({ data: null, error: APPOINTMENT_HOURS_INVALID_REQUEST });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('keeps the backend text of a rejection for the mapper only', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '23P01', message: 'Clinic Appointment Availability Periods must not overlap' },
    });
    expect(
      await replaceWeeklyAvailability(
        CLINIC_ID,
        [{ isoWeekday: 1, startTime: '09:00', endTime: '13:00' }],
        3,
      ),
    ).toEqual({ data: null, error: 'Clinic Appointment Availability Periods must not overlap' });
  });

  it('normalizes SQLSTATE 28000 and an unexpected result', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '28000', message: 'x' } });
    expect((await replaceWeeklyAvailability(CLINIC_ID, [], 3)).error).toBe(
      PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    );
    rpc.mockResolvedValue({ data: '22222222-2222-4222-8222-222222222222', error: null });
    expect((await replaceWeeklyAvailability(CLINIC_ID, [], 3)).error).toBe(
      APPOINTMENT_HOURS_MALFORMED,
    );
  });
});

describe('setAvailabilityException / clearAvailabilityException', () => {
  it('writes CLOSED with no periods', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    await setAvailabilityException(CLINIC_ID, '2026-10-13', { kind: 'CLOSED' });
    expect(rpc).toHaveBeenCalledWith('set_clinic_appointment_availability_exception', {
      p_clinic_id: CLINIC_ID,
      p_local_date: '2026-10-13',
      p_exception_kind: 'CLOSED',
      p_periods: [],
    });
  });

  it('writes OPEN with its periods', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    await setAvailabilityException(CLINIC_ID, '2026-10-11', {
      kind: 'OPEN',
      periods: [{ startTime: '10:00', endTime: '13:00' }],
    });
    expect(rpc).toHaveBeenCalledWith('set_clinic_appointment_availability_exception', {
      p_clinic_id: CLINIC_ID,
      p_local_date: '2026-10-11',
      p_exception_kind: 'OPEN',
      p_periods: [{ start_time: '10:00', end_time: '13:00' }],
    });
  });

  it('rejects OPEN without periods and an impossible date locally', async () => {
    expect(
      (await setAvailabilityException(CLINIC_ID, '2026-10-11', { kind: 'OPEN', periods: [] }))
        .error,
    ).toBe(APPOINTMENT_HOURS_INVALID_REQUEST);
    expect(
      (await setAvailabilityException(CLINIC_ID, '2026-13-01', { kind: 'CLOSED' })).error,
    ).toBe(APPOINTMENT_HOURS_INVALID_REQUEST);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('clears one date', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    expect(await clearAvailabilityException(CLINIC_ID, '2026-10-11')).toEqual({
      data: null,
      error: null,
    });
    expect(rpc).toHaveBeenCalledWith('clear_clinic_appointment_availability_exception', {
      p_clinic_id: CLINIC_ID,
      p_local_date: '2026-10-11',
    });
  });
});

describe('setStandardAppointmentDuration', () => {
  it('sends whole minutes', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    await setStandardAppointmentDuration(CLINIC_ID, 45);
    expect(rpc).toHaveBeenCalledWith('set_clinic_standard_appointment_duration', {
      p_clinic_id: CLINIC_ID,
      p_duration_minutes: 45,
    });
  });

  it.each([9, 241, 30.5, Number.NaN])('never sends %p', async (minutes) => {
    expect((await setStandardAppointmentDuration(CLINIC_ID, minutes)).error).toBe(
      APPOINTMENT_HOURS_INVALID_REQUEST,
    );
    expect(rpc).not.toHaveBeenCalled();
  });
});

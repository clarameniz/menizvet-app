import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  CLINIC_SCHEDULE_MALFORMED,
  parseClinicAppointmentSchedule,
} from '@/data/clinic-appointment-schedule';
import {
  getClinicAppointmentDay,
  getClinicAppointmentHistory,
  getClinicAppointmentMonthCounts,
  getClinicAppointmentPending,
  getClinicCalendarContext,
  historyCursorOf,
  parseClinicAppointmentDay,
  parseClinicCalendarContext,
  parseClinicHistoryPage,
  parseClinicMonthCounts,
  parseClinicPendingPage,
  pendingCursorOf,
  ZERO_PENDING_TOTALS,
} from '@/data/clinic-calendar';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const rpc = supabase.rpc as jest.Mock;
const CLINIC_ID = '66666666-6666-4666-8666-666666666666';

/** One backend row of the BR-51 projection (as in clinic-appointment-schedule.test.ts). */
function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    pet_id: '22222222-2222-4222-8222-222222222222',
    pet_name: 'Luna',
    requesting_user_id: '33333333-3333-4333-8333-333333333333',
    requester_display_name: 'María López',
    reason_for_visit: 'Vacunación',
    guardian_notes: null,
    lifecycle_state: 'CONFIRMED',
    created_at: '2026-09-01T10:00:00+00:00',
    // 23:30 in Madrid (UTC+1) on 10 March 2035 — 22:30 the same day in UTC.
    current_scheduled_start_at: '2035-03-10T22:30:00+00:00',
    current_scheduled_end_at: '2035-03-10T23:15:00+00:00',
    current_scheduling_timezone_name: 'Europe/Madrid',
    current_schedule_revision_sequence: 2,
    current_veterinarian_clinic_assignment_id: null,
    pending_reschedule_proposal_id: null,
    pending_reschedule_proposal_state: null,
    pending_reschedule_proposing_context: null,
    pending_reschedule_proposed_start_at: null,
    pending_reschedule_proposed_end_at: null,
    pending_reschedule_proposed_timezone_name: null,
    pending_reschedule_reason: null,
    current_schedule_source_proposal_id: null,
    current_schedule_source_proposing_context: null,
    pending_reschedule_currently_feasible: null,
    cancellation_reason: null,
    has_clinical_record: false,
    ...overrides,
  };
}

beforeEach(() => rpc.mockReset());

describe('parseClinicCalendarContext (SPEC-APT-012 BR-60)', () => {
  it('accepts one row with a real date and a valid zone, or two nulls', () => {
    expect(
      parseClinicCalendarContext([
        { clinic_local_today: '2026-11-03', scheduling_timezone_name: 'Europe/Madrid' },
      ]),
    ).toEqual({ clinicLocalToday: '2026-11-03', schedulingTimezoneName: 'Europe/Madrid' });
    expect(
      parseClinicCalendarContext([{ clinic_local_today: null, scheduling_timezone_name: null }]),
    ).toEqual({ clinicLocalToday: null, schedulingTimezoneName: null });
  });

  it('rejects anything else, never inventing a zone or a date', () => {
    for (const raw of [
      [],
      [
        { clinic_local_today: '2026-11-03', scheduling_timezone_name: 'Europe/Madrid' },
        { clinic_local_today: '2026-11-03', scheduling_timezone_name: 'Europe/Madrid' },
      ],
      [{ clinic_local_today: '2026-11-03', scheduling_timezone_name: null }],
      [{ clinic_local_today: null, scheduling_timezone_name: 'Europe/Madrid' }],
      [{ clinic_local_today: '2026-02-30', scheduling_timezone_name: 'Europe/Madrid' }],
      [{ clinic_local_today: '2026-11-03', scheduling_timezone_name: 'Mars/Olympus' }],
      [{ clinic_local_today: '2026-11-03T00:00:00Z', scheduling_timezone_name: 'Europe/Madrid' }],
      { clinic_local_today: '2026-11-03', scheduling_timezone_name: 'Europe/Madrid' },
      null,
    ]) {
      expect(parseClinicCalendarContext(raw)).toBeNull();
    }
  });
});

describe('parseClinicMonthCounts (SPEC-APT-012 BR-54)', () => {
  it('maps each date of the month to its positive count; an empty month is an empty map', () => {
    expect(
      parseClinicMonthCounts(
        [
          { day: '2026-11-03', appointment_count: 2 },
          { day: '2026-11-30', appointment_count: 1 },
        ],
        2026,
        11,
      ),
    ).toEqual({ '2026-11-03': 2, '2026-11-30': 1 });
    expect(parseClinicMonthCounts([], 2026, 11)).toEqual({});
  });

  it('rejects other months, unreal or repeated dates, and non-positive or fractional counts', () => {
    for (const items of [
      [{ day: '2026-12-01', appointment_count: 1 }],
      [{ day: '2026-11-31', appointment_count: 1 }],
      [
        { day: '2026-11-03', appointment_count: 1 },
        { day: '2026-11-03', appointment_count: 1 },
      ],
      [{ day: '2026-11-03', appointment_count: 0 }],
      [{ day: '2026-11-03', appointment_count: 1.5 }],
      [{ day: '2026-11-03', appointment_count: '2' }],
      [{ day: '2026-11-03' }],
      [null],
    ]) {
      expect(parseClinicMonthCounts(items, 2026, 11)).toBeNull();
    }
    expect(parseClinicMonthCounts(null, 2026, 11)).toBeNull();
  });
});

describe('parseClinicAppointmentDay (SPEC-APT-012 BR-56)', () => {
  it('equals the schedule parser for rows starting on that local date', () => {
    const raw = [row()];
    expect(parseClinicAppointmentDay(raw, '2035-03-10')).toEqual(
      parseClinicAppointmentSchedule(raw),
    );
    expect(parseClinicAppointmentDay([], '2035-03-10')).toEqual([]);
  });

  it('dates each row in its own timezone: 23:30 in Madrid is that day, not the UTC or next one', () => {
    expect(parseClinicAppointmentDay([row()], '2035-03-11')).toBeNull();
    // 00:30 in Madrid on 11 March is still 10 March in UTC.
    const afterMidnight = row({
      current_scheduled_start_at: '2035-03-10T23:30:00+00:00',
      current_scheduled_end_at: '2035-03-11T00:00:00+00:00',
    });
    expect(parseClinicAppointmentDay([afterMidnight], '2035-03-11')).not.toBeNull();
    expect(parseClinicAppointmentDay([afterMidnight], '2035-03-10')).toBeNull();
  });

  it('rejects a malformed row or a repeated Appointment, as the schedule parser does', () => {
    expect(parseClinicAppointmentDay([row({ pet_name: '' })], '2035-03-10')).toBeNull();
    expect(parseClinicAppointmentDay([row(), row()], '2035-03-10')).toBeNull();
  });

  it('never carries an email', () => {
    const [appointment] = parseClinicAppointmentDay([row()], '2035-03-10') ?? [];
    expect(JSON.stringify(appointment)).not.toMatch(/email|@/i);
  });
});

describe('the reads', () => {
  it('call each RPC with exactly its contract arguments', async () => {
    rpc.mockResolvedValueOnce({
      data: [{ clinic_local_today: '2026-11-03', scheduling_timezone_name: 'Europe/Madrid' }],
      error: null,
    });
    await getClinicCalendarContext(CLINIC_ID);
    rpc.mockResolvedValueOnce({ data: [], error: null });
    await getClinicAppointmentMonthCounts(CLINIC_ID, 2026, 11);
    rpc.mockResolvedValueOnce({ data: [], error: null });
    await getClinicAppointmentDay(CLINIC_ID, '2026-11-03');
    expect(rpc.mock.calls).toEqual([
      ['get_clinic_calendar_context', { p_clinic_id: CLINIC_ID }],
      [
        'get_clinic_appointment_month_counts',
        { p_clinic_id: CLINIC_ID, p_year: 2026, p_month: 11 },
      ],
      ['get_clinic_appointment_day', { p_clinic_id: CLINIC_ID, p_day: '2026-11-03' }],
    ]);
  });

  it('normalize 28000, 42501, malformed payloads and rejections, never rejecting', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000', message: 'auth' } });
    expect(await getClinicCalendarContext(CLINIC_ID)).toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'denied' } });
    expect(await getClinicAppointmentMonthCounts(CLINIC_ID, 2026, 11)).toEqual({
      data: null,
      error: CLINIC_SCHEDULE_ACCESS_DENIED,
    });
    rpc.mockResolvedValueOnce({ data: [{ day: '2026-12-01', appointment_count: 1 }], error: null });
    expect(await getClinicAppointmentMonthCounts(CLINIC_ID, 2026, 11)).toEqual({
      data: null,
      error: CLINIC_SCHEDULE_MALFORMED,
    });
    rpc.mockRejectedValueOnce(new Error('Network request failed'));
    expect(await getClinicAppointmentDay(CLINIC_ID, '2035-03-10')).toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

const ID_A = '11111111-1111-4111-8111-111111111111';
const ID_B = '44444444-4444-4444-8444-444444444444';
const ID_C = '55555555-5555-4555-8555-555555555555';

/** One Pending row (BR-57): a BR-51 row with its classification and the call's totals. */
function pendingItem(
  reason: string,
  overrides: Record<string, unknown> = {},
  counts: [number, number, number] = [2, 1, 1],
): Record<string, unknown> {
  const table: Record<string, [string, number]> = {
    ATTENDANCE_OUTCOME: ['ACTION_REQUIRED', 1],
    REQUEST_DECISION: ['ACTION_REQUIRED', 2],
    PROPOSAL_NOT_FEASIBLE: ['ACTION_REQUIRED', 3],
    GUARDIAN_PROPOSAL: ['INFORMATIONAL', 4],
    AWAITING_GUARDIAN: ['AWAITING_GUARDIAN', 5],
  };
  const [category, rank] = table[reason] ?? ['ACTION_REQUIRED', 1];
  return row({
    pending_reason: reason,
    pending_category: category,
    pending_rank: rank,
    action_required_count: counts[0],
    awaiting_guardian_count: counts[1],
    informational_count: counts[2],
    ...overrides,
  });
}

describe('parseClinicPendingPage (SPEC-APT-012 BR-57)', () => {
  it("keeps the backend's order and classification and takes the totals from the rows", () => {
    const page = parseClinicPendingPage(
      [
        // A past CONFIRMED Appointment awaiting its outcome is pending, not history.
        pendingItem('ATTENDANCE_OUTCOME', {
          current_scheduled_start_at: '2020-01-01T09:00:00.123456+00:00',
          current_scheduled_end_at: '2020-01-01T09:30:00+00:00',
        }),
        pendingItem('REQUEST_DECISION', { id: ID_B, lifecycle_state: 'REQUESTED' }),
        pendingItem('GUARDIAN_PROPOSAL', { id: ID_C }),
      ],
      true,
    );
    expect(
      page?.rows.map((item) => [item.appointment.id, item.reason, item.category, item.rank]),
    ).toEqual([
      [ID_A, 'ATTENDANCE_OUTCOME', 'ACTION_REQUIRED', 1],
      [ID_B, 'REQUEST_DECISION', 'ACTION_REQUIRED', 2],
      [ID_C, 'GUARDIAN_PROPOSAL', 'INFORMATIONAL', 4],
    ]);
    expect(page?.totals).toEqual({ ACTION_REQUIRED: 2, AWAITING_GUARDIAN: 1, INFORMATIONAL: 1 });
    // The key is kept exactly as returned, for the cursor.
    expect(pendingCursorOf(page!.rows[0])).toEqual({
      rank: 1,
      startAt: '2020-01-01T09:00:00.123456+00:00',
      id: ID_A,
    });
  });

  it('an empty first page means zero totals; an empty later page carries none', () => {
    expect(parseClinicPendingPage([], true)).toEqual({ rows: [], totals: ZERO_PENDING_TOTALS });
    expect(parseClinicPendingPage([], false)).toEqual({ rows: [], totals: null });
  });

  it('the totals cover the whole classification, not just the page', () => {
    const page = parseClinicPendingPage(
      [pendingItem('ATTENDANCE_OUTCOME', {}, [120, 4, 0])],
      false,
    );
    expect(page?.totals).toEqual({ ACTION_REQUIRED: 120, AWAITING_GUARDIAN: 4, INFORMATIONAL: 0 });
  });

  it.each([
    ['an unknown reason', [pendingItem('CONFIRM_NOW')]],
    [
      'a category that does not match the reason',
      [pendingItem('AWAITING_GUARDIAN', { pending_category: 'ACTION_REQUIRED' })],
    ],
    [
      'a rank that does not match the reason',
      [pendingItem('REQUEST_DECISION', { pending_rank: 1 })],
    ],
    [
      'a terminal Appointment',
      [pendingItem('ATTENDANCE_OUTCOME', { lifecycle_state: 'COMPLETED' })],
    ],
    ['a missing total', [pendingItem('ATTENDANCE_OUTCOME', { informational_count: null })]],
    ['a negative total', [pendingItem('ATTENDANCE_OUTCOME', {}, [-1, 0, 0])]],
    [
      'totals that differ between rows',
      [
        pendingItem('ATTENDANCE_OUTCOME'),
        pendingItem('ATTENDANCE_OUTCOME', { id: ID_B }, [3, 1, 1]),
      ],
    ],
    [
      'totals smaller than the rows of the page',
      [
        pendingItem('ATTENDANCE_OUTCOME', {}, [1, 0, 0]),
        pendingItem('REQUEST_DECISION', { id: ID_B, lifecycle_state: 'REQUESTED' }, [1, 0, 0]),
      ],
    ],
    [
      'ranks out of order',
      [pendingItem('AWAITING_GUARDIAN'), pendingItem('ATTENDANCE_OUTCOME', { id: ID_B })],
    ],
    [
      'a repeated Appointment',
      [pendingItem('ATTENDANCE_OUTCOME'), pendingItem('ATTENDANCE_OUTCOME')],
    ],
    ['a malformed schedule row', [pendingItem('ATTENDANCE_OUTCOME', { pet_name: '' })]],
  ])('rejects %s', (_label, raw) => {
    expect(parseClinicPendingPage(raw, true)).toBeNull();
  });

  it('never carries an email', () => {
    const page = parseClinicPendingPage([pendingItem('ATTENDANCE_OUTCOME')], true);
    expect(JSON.stringify(page)).not.toMatch(/email|@/i);
  });
});

describe('parseClinicHistoryPage (SPEC-APT-012 BR-59)', () => {
  it('accepts the four terminal outcomes, in the given order', () => {
    const raw = [
      row({ lifecycle_state: 'COMPLETED' }),
      row({ id: ID_B, lifecycle_state: 'NO_SHOW' }),
      row({ id: ID_C, lifecycle_state: 'CANCELLED', cancellation_reason: 'Cierre' }),
      row({ id: '66666666-6666-4666-8666-666666666667', lifecycle_state: 'EXPIRED' }),
    ];
    expect(parseClinicHistoryPage(raw)?.map((item) => item.lifecycleState)).toEqual([
      'COMPLETED',
      'NO_SHOW',
      'CANCELLED',
      'EXPIRED',
    ]);
    expect(parseClinicHistoryPage([])).toEqual([]);
  });

  it('never accepts an active Appointment, even a CONFIRMED one whose time has passed', () => {
    const lateConfirmed = row({
      lifecycle_state: 'CONFIRMED',
      current_scheduled_start_at: '2020-01-01T09:00:00+00:00',
      current_scheduled_end_at: '2020-01-01T09:30:00+00:00',
    });
    expect(parseClinicHistoryPage([lateConfirmed])).toBeNull();
    expect(parseClinicHistoryPage([row({ lifecycle_state: 'REQUESTED' })])).toBeNull();
  });

  it('rejects a repeated Appointment and keeps the exact key for the cursor', () => {
    expect(
      parseClinicHistoryPage([
        row({ lifecycle_state: 'COMPLETED' }),
        row({ lifecycle_state: 'COMPLETED' }),
      ]),
    ).toBeNull();
    const [item] =
      parseClinicHistoryPage([
        row({
          lifecycle_state: 'COMPLETED',
          current_scheduled_start_at: '2035-03-10T22:30:00.654321+00:00',
        }),
      ]) ?? [];
    expect(historyCursorOf(item)).toEqual({
      startAt: '2035-03-10T22:30:00.654321+00:00',
      id: ID_A,
    });
  });
});

describe('the Pending and History reads', () => {
  it('send the first page without a cursor, and later pages with the complete key', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await getClinicAppointmentPending(CLINIC_ID, null, 50);
    await getClinicAppointmentPending(
      CLINIC_ID,
      { rank: 3, startAt: '2035-03-10T22:30:00.123456+00:00', id: ID_B },
      50,
    );
    await getClinicAppointmentHistory(CLINIC_ID, null, 30);
    await getClinicAppointmentHistory(
      CLINIC_ID,
      { startAt: '2035-03-10T22:30:00.654321+00:00', id: ID_C },
      30,
    );
    expect(rpc.mock.calls).toEqual([
      [
        'get_clinic_appointment_pending',
        {
          p_clinic_id: CLINIC_ID,
          p_after_rank: null,
          p_after_start_at: null,
          p_after_id: null,
          p_limit: 50,
        },
      ],
      [
        'get_clinic_appointment_pending',
        {
          p_clinic_id: CLINIC_ID,
          p_after_rank: 3,
          p_after_start_at: '2035-03-10T22:30:00.123456+00:00',
          p_after_id: ID_B,
          p_limit: 50,
        },
      ],
      [
        'get_clinic_appointment_history',
        { p_clinic_id: CLINIC_ID, p_before_start_at: null, p_before_id: null, p_limit: 30 },
      ],
      [
        'get_clinic_appointment_history',
        {
          p_clinic_id: CLINIC_ID,
          p_before_start_at: '2035-03-10T22:30:00.654321+00:00',
          p_before_id: ID_C,
          p_limit: 30,
        },
      ],
    ]);
    expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
      'get_clinic_appointment_pending_summary',
    );
  });

  it('interpret an empty page by its position', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    expect(await getClinicAppointmentPending(CLINIC_ID, null, 50)).toEqual({
      data: { rows: [], totals: ZERO_PENDING_TOTALS },
      error: null,
    });
    expect(
      await getClinicAppointmentPending(
        CLINIC_ID,
        { rank: 1, startAt: '2035-03-10T22:30:00+00:00', id: ID_A },
        50,
      ),
    ).toEqual({ data: { rows: [], totals: null }, error: null });
  });

  it('normalize 28000, 42501 and malformed pages, never rejecting', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000', message: 'auth' } });
    expect(await getClinicAppointmentPending(CLINIC_ID, null, 50)).toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'denied' } });
    expect(await getClinicAppointmentHistory(CLINIC_ID, null, 30)).toEqual({
      data: null,
      error: CLINIC_SCHEDULE_ACCESS_DENIED,
    });
    rpc.mockResolvedValueOnce({ data: [row({ lifecycle_state: 'CONFIRMED' })], error: null });
    expect(await getClinicAppointmentHistory(CLINIC_ID, null, 30)).toEqual({
      data: null,
      error: CLINIC_SCHEDULE_MALFORMED,
    });
    rpc.mockRejectedValueOnce(new Error('Network request failed'));
    expect(await getClinicAppointmentPending(CLINIC_ID, null, 50)).toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

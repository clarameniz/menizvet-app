import {
  activeCursorOf,
  getGuardianActiveAppointments,
  getGuardianAppointmentHistory,
  GUARDIAN_APPOINTMENTS_AUTH_REQUIRED,
  GUARDIAN_APPOINTMENTS_MALFORMED,
  historyCursorOf,
  parseGuardianActivePage,
  parseGuardianHistoryPage,
} from '@/data/guardian-appointments';

// Importing the module pulls in lib/supabase.ts, which throws under Jest
// without EXPO_PUBLIC_SUPABASE_* env vars; the mock also captures every call.
const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...args: unknown[]) => mockRpc(...args) },
}));

beforeEach(() => {
  mockRpc.mockReset();
});

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

function raw(n: number, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: ID(n),
    pet_id: ID(100),
    pet_name: 'Luna',
    clinic_id: ID(200),
    lifecycle_state: 'CONFIRMED',
    current_scheduled_start_at: '2035-03-01T09:00:00+00:00',
    current_scheduled_end_at: '2035-03-01T09:30:00+00:00',
    current_scheduling_timezone_name: 'Europe/Madrid',
    pending_reschedule_proposing_context: null,
    awaiting_clinic_confirmation: false,
    ...overrides,
  };
}

const activeRaw = (n: number, overrides: Record<string, unknown> = {}) =>
  raw(n, { active_rank: 1, ...overrides });
const historyRaw = (n: number, overrides: Record<string, unknown> = {}) =>
  raw(n, { lifecycle_state: 'COMPLETED', ...overrides });

describe('parseGuardianActivePage (SPEC-APT-011 BR-37, BR-38)', () => {
  it('maps every column and keeps the interval exactly as returned', () => {
    const [row] = parseGuardianActivePage([
      activeRaw(1, {
        pet_id: ID(101),
        pet_name: 'Toby with a very long name',
        clinic_id: ID(201),
        lifecycle_state: 'REQUESTED',
        current_scheduled_start_at: '2035-03-02T14:00:00-05:00',
        current_scheduled_end_at: '2035-03-02T14:30:00-05:00',
        current_scheduling_timezone_name: 'America/New_York',
        pending_reschedule_proposing_context: 'CLINIC',
        awaiting_clinic_confirmation: true,
      }),
    ])!;
    expect(row).toEqual({
      id: ID(1),
      petId: ID(101),
      petName: 'Toby with a very long name',
      clinicId: ID(201),
      lifecycleState: 'REQUESTED',
      currentScheduledStartAt: '2035-03-02T14:00:00-05:00',
      currentScheduledEndAt: '2035-03-02T14:30:00-05:00',
      currentSchedulingTimezoneName: 'America/New_York',
      pendingProposalContext: 'CLINIC',
      awaitingClinicConfirmation: true,
      activeRank: 1,
    });
  });

  it('accepts REQUESTED and CONFIRMED whose start was reached (rank 2), after the future ones', () => {
    const rows = parseGuardianActivePage([
      activeRaw(1),
      activeRaw(2, {
        active_rank: 2,
        current_scheduled_start_at: '2020-01-01T09:00:00+00:00',
        current_scheduled_end_at: '2020-01-01T09:30:00+00:00',
      }),
      activeRaw(3, { active_rank: 2, lifecycle_state: 'REQUESTED' }),
    ]);
    expect(rows?.map((row) => row.activeRank)).toEqual([1, 2, 2]);
  });

  it('accepts an empty page', () => {
    expect(parseGuardianActivePage([])).toEqual([]);
  });

  it.each([
    ['a terminal state', [activeRaw(1, { lifecycle_state: 'COMPLETED' })]],
    ['an unknown state', [activeRaw(1, { lifecycle_state: 'PENDING' })]],
    ['a missing rank', [raw(1)]],
    ['an unknown rank', [activeRaw(1, { active_rank: 3 })]],
    [
      'a rank 1 after a rank 2',
      [activeRaw(1, { active_rank: 2 }), activeRaw(2, { active_rank: 1 })],
    ],
    ['the same Appointment twice', [activeRaw(1), activeRaw(1)]],
    ['a non-uuid id', [activeRaw(1, { id: 'apt-1' })]],
    ['a missing Pet', [activeRaw(1, { pet_id: null })]],
    ['a blank Pet name', [activeRaw(1, { pet_name: '  ' })]],
    [
      'an end before the start',
      [activeRaw(1, { current_scheduled_end_at: '2035-03-01T08:00:00+00:00' })],
    ],
    ['an unknown timezone', [activeRaw(1, { current_scheduling_timezone_name: 'Mars/Olympus' })]],
    [
      'a timestamp without offset',
      [activeRaw(1, { current_scheduled_start_at: '2035-03-01 09:00' })],
    ],
    [
      'an unknown proposing context',
      [activeRaw(1, { pending_reschedule_proposing_context: 'SYSTEM' })],
    ],
    ['a missing awaiting flag', [activeRaw(1, { awaiting_clinic_confirmation: undefined })]],
    ['a null awaiting flag', [activeRaw(1, { awaiting_clinic_confirmation: null })]],
    [
      'a CONFIRMED Appointment awaiting confirmation',
      [activeRaw(1, { lifecycle_state: 'CONFIRMED', awaiting_clinic_confirmation: true })],
    ],
    ['a non-array payload', { rows: [] }],
  ])('rejects %s', (_label, payload) => {
    expect(parseGuardianActivePage(payload)).toBeNull();
  });
});

describe('parseGuardianHistoryPage (SPEC-APT-011 BR-39)', () => {
  it('accepts every terminal outcome', () => {
    const rows = parseGuardianHistoryPage(
      ['COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'].map((state, index) =>
        historyRaw(index + 1, { lifecycle_state: state }),
      ),
    );
    expect(rows?.map((row) => row.lifecycleState)).toEqual([
      'COMPLETED',
      'CANCELLED',
      'NO_SHOW',
      'EXPIRED',
    ]);
  });

  it.each([
    ['a REQUESTED row', [historyRaw(1, { lifecycle_state: 'REQUESTED' })]],
    ['a CONFIRMED row, however late', [historyRaw(1, { lifecycle_state: 'CONFIRMED' })]],
    [
      'a proposal on a terminal Appointment',
      [historyRaw(1, { pending_reschedule_proposing_context: 'CLINIC' })],
    ],
    [
      'a terminal Appointment awaiting confirmation',
      [historyRaw(1, { awaiting_clinic_confirmation: true })],
    ],
    ['the same Appointment twice', [historyRaw(1), historyRaw(1)]],
  ])('rejects %s', (_label, payload) => {
    expect(parseGuardianHistoryPage(payload)).toBeNull();
  });
});

describe('cursors', () => {
  it('are the complete key of the last row, untouched', () => {
    const [active] = parseGuardianActivePage([
      activeRaw(7, {
        active_rank: 2,
        current_scheduled_start_at: '2025-05-01T15:00:00.123456+00:00',
        current_scheduled_end_at: '2025-05-01T15:30:00+00:00',
      }),
    ])!;
    expect(activeCursorOf(active)).toEqual({
      rank: 2,
      startAt: '2025-05-01T15:00:00.123456+00:00',
      id: ID(7),
    });
    const [terminal] = parseGuardianHistoryPage([historyRaw(8)])!;
    expect(historyCursorOf(terminal)).toEqual({ startAt: '2035-03-01T09:00:00+00:00', id: ID(8) });
  });
});

describe('getGuardianActiveAppointments / getGuardianAppointmentHistory', () => {
  it('reads the first Active page with no cursor and the page size', async () => {
    mockRpc.mockResolvedValue({ data: [activeRaw(1)], error: null });
    const result = await getGuardianActiveAppointments(null, 20);
    expect(mockRpc).toHaveBeenCalledWith('get_guardian_active_appointments', {
      p_after_rank: null,
      p_after_start_at: null,
      p_after_id: null,
      p_limit: 20,
    });
    expect(result.data).toHaveLength(1);
  });

  it('sends the complete Active cursor exactly as returned', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    await getGuardianActiveAppointments(
      { rank: 2, startAt: '2025-05-01T15:00:00.1+00:00', id: ID(9) },
      20,
    );
    expect(mockRpc).toHaveBeenCalledWith('get_guardian_active_appointments', {
      p_after_rank: 2,
      p_after_start_at: '2025-05-01T15:00:00.1+00:00',
      p_after_id: ID(9),
      p_limit: 20,
    });
  });

  it('reads History with its own cursor', async () => {
    mockRpc.mockResolvedValue({ data: [historyRaw(1)], error: null });
    await getGuardianAppointmentHistory({ startAt: '2024-01-01T10:00:00+00:00', id: ID(3) }, 20);
    expect(mockRpc).toHaveBeenCalledWith('get_guardian_appointment_history', {
      p_before_start_at: '2024-01-01T10:00:00+00:00',
      p_before_id: ID(3),
      p_limit: 20,
    });
  });

  it('never calls the Pet-scoped read', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    await getGuardianActiveAppointments(null, 20);
    await getGuardianAppointmentHistory(null, 20);
    expect(mockRpc.mock.calls.map(([name]) => name)).not.toContain('get_pet_appointments');
  });

  it('normalizes a lost session, keeps other errors, and rejects malformed pages', async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });
    expect(await getGuardianActiveAppointments(null, 20)).toEqual({
      data: null,
      error: GUARDIAN_APPOINTMENTS_AUTH_REQUIRED,
    });
    mockRpc.mockResolvedValueOnce({ data: null, error: { code: '57014', message: 'timeout' } });
    expect(await getGuardianAppointmentHistory(null, 20)).toEqual({ data: null, error: 'timeout' });
    mockRpc.mockResolvedValueOnce({
      data: [historyRaw(1, { lifecycle_state: 'CONFIRMED' })],
      error: null,
    });
    expect(await getGuardianAppointmentHistory(null, 20)).toEqual({
      data: null,
      error: GUARDIAN_APPOINTMENTS_MALFORMED,
    });
  });

  it('settles a thrown network failure instead of rejecting', async () => {
    mockRpc.mockRejectedValueOnce(new Error('Network request failed'));
    await expect(getGuardianActiveAppointments(null, 20)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

import { createElement } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import {
  GUARDIAN_APPOINTMENTS_PAGE_SIZE,
  useGuardianActiveAppointments,
  useGuardianAppointmentHistory,
} from '@/hooks/use-guardian-appointment-pages';

// "My appointments" behavior (SPEC-APT-011 BR-40) through the real hooks and
// usePagedList, against an emulated keyset backend. Focus is simulated by
// re-running the registered focus callbacks, as expo-router does on return
// from the detail.
let mockFocusCallbacks: (() => void)[] = [];
jest.mock('expo-router', () => {
  const { useEffect } = jest.requireActual<typeof import('react')>('react');
  return {
    useFocusEffect: (callback: () => void) => {
      useEffect(() => {
        mockFocusCallbacks.push(callback);
        callback();
        return () => {
          mockFocusCallbacks = mockFocusCallbacks.filter((registered) => registered !== callback);
        };
      }, [callback]);
    },
  };
});

const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...args: unknown[]) => mockRpc(...args) },
}));

const mockClinicNames = jest.fn();
jest.mock('@/data/clinics', () => ({
  getPublishedClinicProfilesByIds: (ids: string[]) => mockClinicNames(ids),
}));

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const CLINIC_A = ID(9001);
const CLINIC_B = ID(9002);

type ServerRow = Record<string, unknown> & { id: string };

function activeRow(n: number, rank: 1 | 2 = 1): ServerRow {
  const start = new Date(Date.UTC(2035, 0, 1, 9) + n * 3_600_000).toISOString();
  return {
    id: ID(n),
    pet_id: n % 2 === 0 ? ID(8001) : ID(8002),
    pet_name: n % 2 === 0 ? 'Luna' : 'Toby',
    clinic_id: n % 3 === 0 ? CLINIC_B : CLINIC_A,
    lifecycle_state: n % 2 === 0 ? 'REQUESTED' : 'CONFIRMED',
    current_scheduled_start_at: start,
    current_scheduled_end_at: new Date(Date.parse(start) + 1_800_000).toISOString(),
    current_scheduling_timezone_name: 'Europe/Madrid',
    pending_reschedule_proposing_context: n === 1 ? 'CLINIC' : null,
    awaiting_clinic_confirmation: false,
    active_rank: rank,
  };
}

function historyRow(n: number, state = 'COMPLETED'): ServerRow {
  const { active_rank: _rank, ...rest } = activeRow(n);
  return {
    ...rest,
    id: ID(1000 + n),
    lifecycle_state: state,
    pending_reschedule_proposing_context: null,
  };
}

/** A keyset backend over fixed ordered lists: the page after the cursor's row. */
let serverActive: ServerRow[] = [];
let serverHistory: ServerRow[] = [];
const failing = new Set<string>();
const held = new Map<string, (value: unknown) => void>();
let holdNext: string | null = null;

function pageAfter(rows: ServerRow[], afterId: unknown, limit: number) {
  const start = afterId === null ? 0 : rows.findIndex((row) => row.id === afterId) + 1;
  return rows.slice(start, start + limit);
}

function respond(name: string, args: Record<string, unknown>) {
  if (failing.has(name)) return { data: null, error: { code: '57014', message: 'timeout' } };
  if (name === 'get_guardian_active_appointments') {
    return { data: pageAfter(serverActive, args.p_after_id, args.p_limit as number), error: null };
  }
  if (name === 'get_guardian_appointment_history') {
    return {
      data: pageAfter(serverHistory, args.p_before_id, args.p_limit as number),
      error: null,
    };
  }
  throw new Error(`Unexpected RPC ${name}`);
}

type Lists = {
  active: ReturnType<typeof useGuardianActiveAppointments>;
  history: ReturnType<typeof useGuardianAppointmentHistory>;
};
let latest: Lists | undefined;
function remember(lists: Lists) {
  latest = lists;
}

function Probe({ tab, onRender }: { tab: 'active' | 'history'; onRender: (lists: Lists) => void }) {
  const active = useGuardianActiveAppointments(tab === 'active');
  const history = useGuardianAppointmentHistory(tab === 'history');
  onRender({ active, history });
  return null;
}

let tree: ReactTestRenderer | undefined;
async function settle() {
  for (let i = 0; i < 5; i += 1) {
    await act(async () => {
      await Promise.resolve();
    });
  }
}
async function show(tab: 'active' | 'history') {
  await act(async () => {
    if (tree) tree.update(createElement(Probe, { tab, onRender: remember }));
    else tree = create(createElement(Probe, { tab, onRender: remember }));
  });
  await settle();
}
async function focusAgain() {
  await act(async () => {
    for (const callback of [...mockFocusCallbacks]) callback();
  });
  await settle();
}
const active = () => latest!.active;
const history = () => latest!.history;
const calls = (name: string) => mockRpc.mock.calls.filter(([called]) => called === name);
const ids = (rows: { id: string }[] | null) => (rows ?? []).map((row) => row.id);

beforeEach(() => {
  mockFocusCallbacks = [];
  failing.clear();
  held.clear();
  holdNext = null;
  latest = undefined;
  serverActive = Array.from({ length: 21 }, (_, index) => activeRow(index + 1, index < 16 ? 1 : 2));
  serverHistory = Array.from({ length: 21 }, (_, index) =>
    historyRow(index + 1, ['COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'][index % 4]),
  );
  mockRpc.mockReset();
  mockRpc.mockImplementation((name: string, args: Record<string, unknown>) => {
    if (holdNext === name) {
      holdNext = null;
      return new Promise((resolve) => held.set(name, () => resolve(respond(name, args))));
    }
    return Promise.resolve(respond(name, args));
  });
  mockClinicNames.mockReset();
  mockClinicNames.mockResolvedValue({
    data: new Map([[CLINIC_A, { displayName: 'Animalia Centro' }]]),
    error: null,
  });
});

afterEach(async () => {
  await act(async () => tree?.unmount());
  tree = undefined;
});

describe('opening "My appointments"', () => {
  it('reads only the first Active page — never History, never the Pet-scoped read', async () => {
    await show('active');
    expect(calls('get_guardian_active_appointments')).toEqual([
      [
        'get_guardian_active_appointments',
        { p_after_rank: null, p_after_start_at: null, p_after_id: null, p_limit: 20 },
      ],
    ]);
    expect(calls('get_guardian_appointment_history')).toHaveLength(0);
    expect(calls('get_pet_appointments')).toHaveLength(0);
    expect(active().state.rows).toHaveLength(GUARDIAN_APPOINTMENTS_PAGE_SIZE);
    expect(active().state.hasMore).toBe(true);
    expect(history().state.rows).toBeNull();
  });

  it('keeps Pets, Clinics and states apart and resolves Clinic names once per page', async () => {
    await show('active');
    const [first, second, third] = active().state.rows!;
    expect([first.petName, first.lifecycleState, first.clinicDisplayName]).toEqual([
      'Toby',
      'CONFIRMED',
      'Animalia Centro',
    ]);
    expect([second.petName, second.lifecycleState]).toEqual(['Luna', 'REQUESTED']);
    expect(third.clinicDisplayName).toBeNull();
    expect(first.pendingProposalContext).toBe('CLINIC');
    expect(mockClinicNames).toHaveBeenCalledTimes(1);
    expect(new Set(mockClinicNames.mock.calls[0][0])).toEqual(new Set([CLINIC_A, CLINIC_B]));
  });

  it('shows rows with the "Clinic unavailable" fallback when the name lookup fails', async () => {
    mockClinicNames.mockResolvedValue({ data: null, error: 'offline' });
    await show('active');
    expect(active().state.rows!.every((row) => row.clinicDisplayName === null)).toBe(true);
    expect(active().state.error).toBeNull();
  });
});

describe('"Load more"', () => {
  it('continues from the complete key of the last row: 20 then 1, no duplicates', async () => {
    await show('active');
    await act(async () => active().loadMore());
    await settle();
    const [, args] = calls('get_guardian_active_appointments')[1];
    const twentieth = serverActive[19];
    expect(args).toEqual({
      p_after_rank: 2,
      p_after_start_at: twentieth.current_scheduled_start_at,
      p_after_id: twentieth.id,
      p_limit: 20,
    });
    expect(ids(active().state.rows)).toEqual(serverActive.map((row) => row.id));
    expect(active().state.hasMore).toBe(false);
  });

  it('handles an exactly full page followed by an empty one', async () => {
    serverActive = serverActive.slice(0, 20);
    await show('active');
    await act(async () => active().loadMore());
    await settle();
    expect(active().state.rows).toHaveLength(20);
    expect(active().state.hasMore).toBe(false);
    expect(active().state.error).toBeNull();
  });

  it('ignores a second tap while the next page is loading', async () => {
    await show('active');
    holdNext = 'get_guardian_active_appointments';
    await act(async () => {
      active().loadMore();
      active().loadMore();
    });
    expect(calls('get_guardian_active_appointments')).toHaveLength(2);
    await act(async () => held.get('get_guardian_active_appointments')!(undefined));
    await settle();
    expect(active().state.rows).toHaveLength(21);
  });

  it('pages History independently: 20 then 1', async () => {
    await show('history');
    expect(history().state.rows).toHaveLength(20);
    await act(async () => history().loadMore());
    await settle();
    expect(ids(history().state.rows)).toEqual(serverHistory.map((row) => row.id));
    const [, args] = calls('get_guardian_appointment_history')[1];
    expect(args).toEqual({
      p_before_start_at: serverHistory[19].current_scheduled_start_at,
      p_before_id: serverHistory[19].id,
      p_limit: 20,
    });
  });
});

describe('tabs', () => {
  it('reads History only when shown, and keeps both lists across switches', async () => {
    await show('active');
    await show('history');
    expect(calls('get_guardian_appointment_history')).toHaveLength(1);
    await show('active');
    expect(calls('get_guardian_active_appointments')).toHaveLength(1);
    expect(active().state.rows).toHaveLength(20);
    expect(history().state.rows).toHaveLength(20);
  });

  it('refreshes only the tab on screen when returning from the detail', async () => {
    await show('active');
    await show('history');
    await focusAgain();
    expect(calls('get_guardian_appointment_history')).toHaveLength(2);
    expect(calls('get_guardian_active_appointments')).toHaveLength(1);
    // The hidden tab restarts once it is shown again.
    await show('active');
    expect(calls('get_guardian_active_appointments')).toHaveLength(2);
  });

  it('moves a cancelled Appointment from Active to History after the refresh', async () => {
    await show('active');
    const cancelled = serverActive[0];
    serverActive = serverActive.slice(1);
    serverHistory = [{ ...historyRow(0, 'CANCELLED'), id: cancelled.id }, ...serverHistory];
    await focusAgain();
    expect(ids(active().state.rows)).not.toContain(cancelled.id);
    await show('history');
    expect(ids(history().state.rows)[0]).toBe(cancelled.id);
    expect(history().state.rows![0].lifecycleState).toBe('CANCELLED');
  });

  it('keeps errors per tab: a failed History never touches Active', async () => {
    await show('active');
    failing.add('get_guardian_appointment_history');
    await show('history');
    expect(history().state.error).toEqual({
      during: 'first',
      messageKey: 'appointments.loadError',
    });
    expect(history().state.rows).toBeNull();
    expect(active().state.error).toBeNull();
    expect(active().state.rows).toHaveLength(20);
    failing.clear();
    await act(async () => history().retry());
    await settle();
    expect(history().state.rows).toHaveLength(20);
  });

  it('keeps shown rows when a refresh fails', async () => {
    await show('active');
    failing.add('get_guardian_active_appointments');
    await focusAgain();
    expect(active().state.rows).toHaveLength(20);
    expect(active().state.error?.during).toBe('first');
  });

  it('reports a lost session with the shared copy', async () => {
    mockRpc.mockImplementation(() =>
      Promise.resolve({
        data: null,
        error: { code: '28000', message: 'Authentication is required' },
      }),
    );
    await show('active');
    expect(active().state.error).toEqual({ during: 'first', messageKey: 'errors.sessionExpired' });
  });
});

describe('awaiting the Clinic’s confirmation (SPEC-APT-011 BR-37/BR-40, SPEC-APT-019 §5)', () => {
  const second = () => active().state.rows![1];
  const update = (changes: Record<string, unknown>) => {
    serverActive = serverActive.map((row, index) => (index === 1 ? { ...row, ...changes } : row));
  };

  it('appears and disappears with what the backend reports after each return from the detail', async () => {
    update({ pending_reschedule_proposing_context: 'CLINIC' });
    await show('active');
    expect([second().pendingProposalContext, second().awaitingClinicConfirmation]).toEqual([
      'CLINIC',
      false,
    ]);

    // The Guardian accepted the Clinic's alternative in the detail.
    update({ pending_reschedule_proposing_context: null, awaiting_clinic_confirmation: true });
    await focusAgain();
    expect([second().pendingProposalContext, second().awaitingClinicConfirmation]).toEqual([
      null,
      true,
    ]);

    // The Clinic proposed yet another time: both signals at once.
    update({ pending_reschedule_proposing_context: 'CLINIC' });
    await focusAgain();
    expect([second().pendingProposalContext, second().awaitingClinicConfirmation]).toEqual([
      'CLINIC',
      true,
    ]);

    // The Clinic confirmed it.
    update({
      lifecycle_state: 'CONFIRMED',
      pending_reschedule_proposing_context: null,
      awaiting_clinic_confirmation: false,
    });
    await focusAgain();
    expect([second().lifecycleState, second().awaitingClinicConfirmation]).toEqual([
      'CONFIRMED',
      false,
    ]);
  });

  it('rejects a page that claims a CONFIRMED Appointment awaits confirmation', async () => {
    update({ lifecycle_state: 'CONFIRMED', awaiting_clinic_confirmation: true });
    await show('active');
    expect(active().state.rows).toBeNull();
    expect(active().state.error).toEqual({ during: 'first', messageKey: 'appointments.loadError' });
  });
});

describe('late answers', () => {
  it('ignores a "Load more" answer that arrives after a refresh started', async () => {
    await show('active');
    holdNext = 'get_guardian_active_appointments';
    await act(async () => {
      void active().loadMore();
    });
    // The detail changed something: the refresh returns fewer rows first.
    serverActive = serverActive.slice(0, 3);
    await focusAgain();
    expect(active().state.rows).toHaveLength(3);
    await act(async () => held.get('get_guardian_active_appointments')!(undefined));
    await settle();
    expect(active().state.rows).toHaveLength(3);
    expect(active().state.hasMore).toBe(false);
  });
});

import {
  PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
  PROFESSIONAL_RESCHEDULE_MALFORMED,
  getAppointmentRescheduleCandidates,
  parseRescheduleCandidates,
  proposeClinicReschedule,
  withdrawRescheduleProposal,
  type RescheduleCandidate,
} from '@/data/professional-appointment-reschedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const APPOINTMENT_ID = '11111111-1111-4111-8111-111111111111';
const PROPOSAL_ID = '22222222-2222-4222-8222-222222222222';

const candidateRow = (overrides: Record<string, unknown> = {}) => ({
  candidate_local_date: '2035-04-02',
  candidate_local_time: '10:00:00',
  utc_offset_seconds: 7200,
  candidate_end_at: '2035-04-02T08:30:00+00:00',
  ...overrides,
});

const CANDIDATE: RescheduleCandidate = {
  localDate: '2035-04-02',
  localTime: '10:00:00',
  utcOffsetSeconds: 7200,
  endAt: '2035-04-02T08:30:00+00:00',
};

describe('parseRescheduleCandidates', () => {
  // A start with seconds arises from an Appointment Availability range that starts
  // with seconds (stored as time(6)); the end is that start plus a whole-minute
  // standard duration (30 minutes).
  it('reshapes rows in backend order, keeping the backend end and second precision', () => {
    expect(
      parseRescheduleCandidates([
        candidateRow(),
        candidateRow({
          candidate_local_time: '10:30:17',
          candidate_end_at: '2035-04-02T09:00:17Z',
        }),
      ]),
    ).toEqual([
      CANDIDATE,
      {
        localDate: '2035-04-02',
        localTime: '10:30:17',
        utcOffsetSeconds: 7200,
        endAt: '2035-04-02T09:00:17Z',
      },
    ]);
  });

  it('accepts the exact JSON PostgREST produces for the candidate read (to_json of date, time, integer, timestamptz)', () => {
    // The shape Postgres json_agg produces over the RPC's column types (session
    // TimeZone UTC); the second row starts at 00:30:17 local and lasts a 30-minute
    // standard duration.
    const payload = JSON.parse(
      '[{"candidate_local_date":"2035-04-02","candidate_local_time":"10:00:00","utc_offset_seconds":7200,"candidate_end_at":"2035-04-02T08:30:00+00:00"},' +
        '{"candidate_local_date":"2035-05-01","candidate_local_time":"00:30:17","utc_offset_seconds":7200,"candidate_end_at":"2035-04-30T23:00:17+00:00"}]',
    );
    expect(parseRescheduleCandidates(payload)).toEqual([
      CANDIDATE,
      {
        localDate: '2035-05-01',
        localTime: '00:30:17',
        utcOffsetSeconds: 7200,
        endAt: '2035-04-30T23:00:17+00:00',
      },
    ]);
  });

  it('accepts an empty result', () => {
    expect(parseRescheduleCandidates([])).toEqual([]);
  });

  it.each<[string, unknown]>([
    ['a non-array payload', { rows: [] }],
    ['a missing end', [candidateRow({ candidate_end_at: null })]],
    ['a malformed end', [candidateRow({ candidate_end_at: 'tomorrow' })]],
    ['a malformed date', [candidateRow({ candidate_local_date: '02/04/2035' })]],
    ['a malformed time', [candidateRow({ candidate_local_time: '25:00:00' })]],
    ['a fractional offset', [candidateRow({ utc_offset_seconds: 3600.5 })]],
    ['an out-of-range offset', [candidateRow({ utc_offset_seconds: 57600 })]],
  ])('rejects %s', (_label, raw) => {
    expect(parseRescheduleCandidates(raw)).toBeNull();
  });
});

describe('getAppointmentRescheduleCandidates', () => {
  const rpc = supabase.rpc as jest.Mock;
  afterEach(() => rpc.mockReset());

  it('reads the Appointment-specific candidates for the date window', async () => {
    rpc.mockResolvedValue({ data: [candidateRow()], error: null });

    await expect(
      getAppointmentRescheduleCandidates(APPOINTMENT_ID, '2035-04-01', '2035-05-30'),
    ).resolves.toEqual({ data: [CANDIDATE], error: null });
    expect(rpc).toHaveBeenCalledWith('get_appointment_reschedule_candidate_start_times', {
      p_appointment_id: APPOINTMENT_ID,
      p_start_date: '2035-04-01',
      p_end_date: '2035-05-30',
    });
  });

  it('rejects a malformed payload as a whole', async () => {
    rpc.mockResolvedValue({ data: [candidateRow({ candidate_end_at: null })], error: null });

    await expect(
      getAppointmentRescheduleCandidates(APPOINTMENT_ID, '2035-04-01', '2035-04-01'),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED });
  });

  it('refuses invalid arguments locally', async () => {
    await expect(
      getAppointmentRescheduleCandidates('a-1', '2035-04-01', '2035-04-01'),
    ).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('normalizes 28000 and keeps other backend messages', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });
    await expect(
      getAppointmentRescheduleCandidates(APPOINTMENT_ID, '2035-04-01', '2035-04-01'),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED });

    rpc.mockResolvedValue({
      data: null,
      error: { code: '42501', message: 'Applicable professional Entitlement is required' },
    });
    await expect(
      getAppointmentRescheduleCandidates(APPOINTMENT_ID, '2035-04-01', '2035-04-01'),
    ).resolves.toEqual({ data: null, error: 'Applicable professional Entitlement is required' });
  });
});

describe('proposeClinicReschedule', () => {
  const rpc = supabase.rpc as jest.Mock;
  afterEach(() => rpc.mockReset());

  it('sends only the start, the trimmed reason, the CLINIC context and exactly the reviewed sequence', async () => {
    rpc.mockResolvedValue({ data: PROPOSAL_ID, error: null });

    await expect(
      proposeClinicReschedule({
        appointmentId: APPOINTMENT_ID,
        candidate: CANDIDATE,
        reason: '  Vet unavailable \n',
        expectedConfirmedRevisionSequence: 3,
      }),
    ).resolves.toEqual({ data: { proposalId: PROPOSAL_ID }, error: null });

    expect(rpc).toHaveBeenCalledWith('propose_confirmed_appointment_reschedule', {
      p_appointment_id: APPOINTMENT_ID,
      p_proposing_context: 'CLINIC',
      p_start_local_date: '2035-04-02',
      p_start_local_time: '10:00:00',
      p_start_utc_offset_seconds: 7200,
      p_reason: 'Vet unavailable',
      p_expected_confirmed_revision_sequence: 3,
    });
    // The client never authors an end.
    expect(JSON.stringify(rpc.mock.calls[0][1])).not.toContain('08:30');
  });

  it.each<[string, Partial<Parameters<typeof proposeClinicReschedule>[0]>]>([
    ['a malformed Appointment id', { appointmentId: 'a-1' }],
    ['a blank reason', { reason: ' \t ' }],
    ['a zero sequence', { expectedConfirmedRevisionSequence: 0 }],
    ['a fractional sequence', { expectedConfirmedRevisionSequence: 1.5 }],
    ['a malformed candidate', { candidate: { ...CANDIDATE, localTime: 'noon' } }],
  ])('refuses %s locally', async (_label, overrides) => {
    await expect(
      proposeClinicReschedule({
        appointmentId: APPOINTMENT_ID,
        candidate: CANDIDATE,
        reason: 'Vet unavailable',
        expectedConfirmedRevisionSequence: 2,
        ...overrides,
      }),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('keeps the stale message for mapping, and never throws', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: {
        code: 'P0001',
        message: 'Stale confirmed Appointment schedule revision for reschedule proposal',
      },
    });
    const request = {
      appointmentId: APPOINTMENT_ID,
      candidate: CANDIDATE,
      reason: 'Vet unavailable',
      expectedConfirmedRevisionSequence: 2,
    };
    await expect(proposeClinicReschedule(request)).resolves.toEqual({
      data: null,
      error: 'Stale confirmed Appointment schedule revision for reschedule proposal',
    });

    rpc.mockRejectedValue(new Error('Network request failed'));
    await expect(proposeClinicReschedule(request)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });

  it('rejects a success payload that is not a UUID', async () => {
    rpc.mockResolvedValue({ data: 'ok', error: null });
    await expect(
      proposeClinicReschedule({
        appointmentId: APPOINTMENT_ID,
        candidate: CANDIDATE,
        reason: 'Vet unavailable',
        expectedConfirmedRevisionSequence: 2,
      }),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED });
  });
});

describe('withdrawRescheduleProposal', () => {
  const rpc = supabase.rpc as jest.Mock;
  afterEach(() => rpc.mockReset());

  it('withdraws by proposal id only', async () => {
    rpc.mockResolvedValue({ data: PROPOSAL_ID, error: null });

    await expect(withdrawRescheduleProposal(PROPOSAL_ID)).resolves.toEqual({
      data: { proposalId: PROPOSAL_ID },
      error: null,
    });
    expect(rpc).toHaveBeenCalledWith('withdraw_appointment_reschedule_proposal', {
      p_proposal_id: PROPOSAL_ID,
    });
  });

  it('refuses a malformed id locally and rejects a mismatched success payload', async () => {
    await expect(withdrawRescheduleProposal('p-1')).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();

    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });
    await expect(withdrawRescheduleProposal(PROPOSAL_ID)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_RESCHEDULE_MALFORMED,
    });
  });
});

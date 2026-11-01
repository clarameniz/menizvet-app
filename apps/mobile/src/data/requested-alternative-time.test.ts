import {
  PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
  PROFESSIONAL_RESCHEDULE_MALFORMED,
  type RescheduleCandidate,
} from '@/data/professional-appointment-reschedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import {
  getRequestedAlternativeCandidates,
  proposeRequestedAlternativeTime,
} from '@/data/requested-alternative-time';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const APPOINTMENT_ID = '11111111-1111-4111-8111-111111111111';
const PROPOSAL_ID = '22222222-2222-4222-8222-222222222222';

const candidateRow = (overrides: Record<string, unknown> = {}) => ({
  candidate_local_date: '2035-03-06',
  candidate_local_time: '12:00:00',
  utc_offset_seconds: 3600,
  candidate_end_at: '2035-03-06T11:30:00+00:00',
  ...overrides,
});

const CANDIDATE: RescheduleCandidate = {
  localDate: '2035-03-06',
  localTime: '12:00:00',
  utcOffsetSeconds: 3600,
  endAt: '2035-03-06T11:30:00+00:00',
};

const rpc = supabase.rpc as jest.Mock;
afterEach(() => rpc.mockReset());

describe('getRequestedAlternativeCandidates (SPEC-APT-020)', () => {
  it('reads the Appointment-specific alternative candidates, never the Guardian read', async () => {
    rpc.mockResolvedValue({ data: [candidateRow()], error: null });

    const result = await getRequestedAlternativeCandidates(
      APPOINTMENT_ID,
      '2035-03-01',
      '2035-04-30',
    );

    expect(rpc).toHaveBeenCalledWith(
      'get_requested_appointment_alternative_candidate_start_times',
      {
        p_appointment_id: APPOINTMENT_ID,
        p_start_date: '2035-03-01',
        p_end_date: '2035-04-30',
      },
    );
    expect(result).toEqual({ data: [CANDIDATE], error: null });
  });

  it('keeps the server-authored end of every candidate, in backend order', async () => {
    rpc.mockResolvedValue({
      data: [
        candidateRow(),
        candidateRow({
          candidate_local_time: '12:30:00',
          candidate_end_at: '2035-03-06T12:00:00+00:00',
        }),
      ],
      error: null,
    });

    const result = await getRequestedAlternativeCandidates(
      APPOINTMENT_ID,
      '2035-03-06',
      '2035-03-06',
    );

    expect(result.data?.map((candidate) => candidate.endAt)).toEqual([
      '2035-03-06T11:30:00+00:00',
      '2035-03-06T12:00:00+00:00',
    ]);
  });

  it('rejects a malformed payload as a whole (strict candidate parsing)', async () => {
    rpc.mockResolvedValue({
      data: [candidateRow(), candidateRow({ candidate_end_at: null })],
      error: null,
    });

    await expect(
      getRequestedAlternativeCandidates(APPOINTMENT_ID, '2035-03-06', '2035-03-06'),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED });
  });

  it('refuses invalid arguments locally', async () => {
    await expect(
      getRequestedAlternativeCandidates('apt-1', '2035-03-06', '2035-03-06'),
    ).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
    });
    await expect(
      getRequestedAlternativeCandidates(APPOINTMENT_ID, '06/03/2035', '2035-03-06'),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('normalizes 28000 and keeps other backend messages for mapping', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });
    await expect(
      getRequestedAlternativeCandidates(APPOINTMENT_ID, '2035-03-06', '2035-03-06'),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED });

    rpc.mockResolvedValueOnce({
      data: null,
      error: {
        code: '23514',
        message: 'Clinic has no currently configured standard Appointment duration',
      },
    });
    await expect(
      getRequestedAlternativeCandidates(APPOINTMENT_ID, '2035-03-06', '2035-03-06'),
    ).resolves.toEqual({
      data: null,
      error: 'Clinic has no currently configured standard Appointment duration',
    });
  });

  it('settles a thrown network failure into an error', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));
    await expect(
      getRequestedAlternativeCandidates(APPOINTMENT_ID, '2035-03-06', '2035-03-06'),
    ).resolves.toEqual({ data: null, error: 'Network request failed' });
  });
});

describe('proposeRequestedAlternativeTime (SPEC-APT-018)', () => {
  it('sends only the start, the trimmed reason, and exactly the reviewed requested sequence', async () => {
    rpc.mockResolvedValue({ data: PROPOSAL_ID, error: null });

    const result = await proposeRequestedAlternativeTime({
      appointmentId: APPOINTMENT_ID,
      candidate: CANDIDATE,
      reason: '  No veterinarian free at 10:00  ',
      expectedRequestedRevisionSequence: 3,
    });

    expect(rpc).toHaveBeenCalledWith('propose_requested_appointment_alternative_time', {
      p_appointment_id: APPOINTMENT_ID,
      p_start_local_date: '2035-03-06',
      p_start_local_time: '12:00:00',
      p_start_utc_offset_seconds: 3600,
      p_reason: 'No veterinarian free at 10:00',
      p_expected_requested_revision_sequence: 3,
    });
    // No end, duration, or proposing context ever travels.
    const sent = rpc.mock.calls[0][1] as Record<string, unknown>;
    expect(Object.keys(sent).some((key) => key.includes('end'))).toBe(false);
    expect('p_proposing_context' in sent).toBe(false);
    expect(result).toEqual({ data: { proposalId: PROPOSAL_ID }, error: null });
  });

  it.each<[string, Partial<Parameters<typeof proposeRequestedAlternativeTime>[0]>]>([
    ['a blank reason', { reason: ' \t ' }],
    ['a zero sequence', { expectedRequestedRevisionSequence: 0 }],
    ['a fractional sequence', { expectedRequestedRevisionSequence: 1.5 }],
    ['a malformed Appointment id', { appointmentId: 'apt-1' }],
    ['a candidate without a server end', { candidate: { ...CANDIDATE, endAt: 'later' } }],
  ])('refuses %s locally', async (_label, overrides) => {
    await expect(
      proposeRequestedAlternativeTime({
        appointmentId: APPOINTMENT_ID,
        candidate: CANDIDATE,
        reason: 'Busy',
        expectedRequestedRevisionSequence: 1,
        ...overrides,
      }),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_INVALID_REQUEST });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('keeps the stale P0001 message for mapping and never retries', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: {
        code: 'P0001',
        message: 'Stale requested Appointment schedule revision for alternative time proposal',
      },
    });

    await expect(
      proposeRequestedAlternativeTime({
        appointmentId: APPOINTMENT_ID,
        candidate: CANDIDATE,
        reason: 'Busy',
        expectedRequestedRevisionSequence: 1,
      }),
    ).resolves.toEqual({
      data: null,
      error: 'Stale requested Appointment schedule revision for alternative time proposal',
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it('rejects a success payload that is not a UUID', async () => {
    rpc.mockResolvedValue({ data: 'ok', error: null });
    await expect(
      proposeRequestedAlternativeTime({
        appointmentId: APPOINTMENT_ID,
        candidate: CANDIDATE,
        reason: 'Busy',
        expectedRequestedRevisionSequence: 1,
      }),
    ).resolves.toEqual({ data: null, error: PROFESSIONAL_RESCHEDULE_MALFORMED });
  });
});

import {
  APPOINTMENT_COMPLETION_INVALID_REQUEST,
  APPOINTMENT_COMPLETION_MALFORMED,
  completeAppointment,
} from '@/data/appointment-completion';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const APPOINTMENT_ID = '11111111-1111-4111-8111-111111111111';

describe('completeAppointment', () => {
  const rpc = supabase.rpc as jest.Mock;

  afterEach(() => rpc.mockReset());

  it('calls complete_appointment with exactly the id and the expected confirmed revision sequence', async () => {
    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });

    await completeAppointment(APPOINTMENT_ID, 2);

    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('complete_appointment', {
      p_appointment_id: APPOINTMENT_ID,
      p_expected_confirmed_revision_sequence: 2,
    });
  });

  it('sends no Veterinarian or clinical information', async () => {
    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });

    await completeAppointment(APPOINTMENT_ID, 2);

    expect(Object.keys(rpc.mock.calls[0][1]).sort()).toEqual([
      'p_appointment_id',
      'p_expected_confirmed_revision_sequence',
    ]);
  });

  it('returns the completed Appointment id on success', async () => {
    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });

    await expect(completeAppointment(APPOINTMENT_ID, 2)).resolves.toEqual({
      data: { appointmentId: APPOINTMENT_ID },
      error: null,
    });
  });

  it.each<[string, unknown]>([
    ['null', null],
    ['a non-string', 42],
    ['another Appointment id', '22222222-2222-4222-8222-222222222222'],
  ])('rejects %s as a malformed success payload', async (_label, data) => {
    rpc.mockResolvedValue({ data, error: null });

    await expect(completeAppointment(APPOINTMENT_ID, 2)).resolves.toEqual({
      data: null,
      error: APPOINTMENT_COMPLETION_MALFORMED,
    });
  });

  it.each<[string, string, number]>([
    ['a malformed Appointment id', 'a-1', 2],
    ['a zero sequence', APPOINTMENT_ID, 0],
    ['a negative sequence', APPOINTMENT_ID, -2],
    ['a fractional sequence', APPOINTMENT_ID, 1.5],
    ['a NaN sequence', APPOINTMENT_ID, Number.NaN],
  ])('refuses %s locally without calling the backend', async (_label, id, sequence) => {
    await expect(completeAppointment(id, sequence)).resolves.toEqual({
      data: null,
      error: APPOINTMENT_COMPLETION_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('normalizes SQLSTATE 28000 to the shared session-expired error', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });

    await expect(completeAppointment(APPOINTMENT_ID, 2)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
  });

  it('keeps the stable backend message of a stale rejection for mapping, without retrying', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: 'P0001', message: 'Stale confirmed Appointment schedule revision' },
    });

    await expect(completeAppointment(APPOINTMENT_ID, 2)).resolves.toEqual({
      data: null,
      error: 'Stale confirmed Appointment schedule revision',
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it('settles a network failure into an error result instead of rejecting, without retrying', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));

    await expect(completeAppointment(APPOINTMENT_ID, 2)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});

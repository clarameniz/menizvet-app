import {
  PROFESSIONAL_CANCELLATION_INVALID_REQUEST,
  PROFESSIONAL_CANCELLATION_MALFORMED,
  cancelProfessionalAppointment,
} from '@/data/professional-appointment-cancellation';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const APPOINTMENT_ID = '11111111-1111-4111-8111-111111111111';

describe('cancelProfessionalAppointment', () => {
  const rpc = supabase.rpc as jest.Mock;

  afterEach(() => rpc.mockReset());

  it('calls cancel_appointment in the CLINIC context with the reason and exactly the reviewed revision sequence', async () => {
    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });

    await cancelProfessionalAppointment(APPOINTMENT_ID, 'Clinic closed that day', 3);

    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('cancel_appointment', {
      p_appointment_id: APPOINTMENT_ID,
      p_cancelling_context: 'CLINIC',
      p_reason: 'Clinic closed that day',
      p_expected_schedule_revision_sequence: 3,
    });
  });

  it('sends the reason trimmed', async () => {
    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });

    await cancelProfessionalAppointment(APPOINTMENT_ID, '  Vet unavailable \n', 1);

    expect(rpc.mock.calls[0][1].p_reason).toBe('Vet unavailable');
  });

  it('returns the cancelled Appointment id on success', async () => {
    rpc.mockResolvedValue({ data: APPOINTMENT_ID, error: null });

    await expect(cancelProfessionalAppointment(APPOINTMENT_ID, 'Closed', 2)).resolves.toEqual({
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

    await expect(cancelProfessionalAppointment(APPOINTMENT_ID, 'Closed', 2)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CANCELLATION_MALFORMED,
    });
  });

  it.each<[string, string, string, number]>([
    ['a malformed Appointment id', 'a-1', 'Closed', 2],
    ['an empty reason', APPOINTMENT_ID, '', 2],
    ['a whitespace-only reason', APPOINTMENT_ID, ' \t\n ', 2],
    ['a zero sequence', APPOINTMENT_ID, 'Closed', 0],
    ['a negative sequence', APPOINTMENT_ID, 'Closed', -2],
    ['a fractional sequence', APPOINTMENT_ID, 'Closed', 1.5],
    ['a NaN sequence', APPOINTMENT_ID, 'Closed', Number.NaN],
  ])('refuses %s locally without calling the backend', async (_label, id, reason, sequence) => {
    await expect(cancelProfessionalAppointment(id, reason, sequence)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CANCELLATION_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('normalizes SQLSTATE 28000 to the shared session-expired error', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '28000', message: 'Authentication is required' },
    });

    await expect(cancelProfessionalAppointment(APPOINTMENT_ID, 'Closed', 2)).resolves.toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
  });

  it('keeps the stable backend message of a stale rejection for mapping, without retrying', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: 'P0001', message: 'Stale Appointment schedule revision for cancellation' },
    });

    await expect(cancelProfessionalAppointment(APPOINTMENT_ID, 'Closed', 2)).resolves.toEqual({
      data: null,
      error: 'Stale Appointment schedule revision for cancellation',
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it('settles a network failure into an error result instead of rejecting', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));

    await expect(cancelProfessionalAppointment(APPOINTMENT_ID, 'Closed', 2)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});

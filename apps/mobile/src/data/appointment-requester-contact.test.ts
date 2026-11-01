import {
  getClinicAppointmentRequesterContact,
  parseAppointmentRequesterContact,
} from '@/data/appointment-requester-contact';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;

const CLINIC_ID = '66666666-6666-4666-8666-666666666666';
const APPOINTMENT_ID = '11111111-1111-4111-8111-111111111111';

describe('parseAppointmentRequesterContact', () => {
  it('maps the single row', () => {
    expect(
      parseAppointmentRequesterContact([
        { requester_display_name: 'María López', requester_email: 'maria@example.test' },
      ]),
    ).toEqual({ displayName: 'María López', email: 'maria@example.test' });
  });

  it('keeps an absent name or email as null', () => {
    expect(
      parseAppointmentRequesterContact([{ requester_display_name: null, requester_email: null }]),
    ).toEqual({ displayName: null, email: null });
  });

  it.each<[string, unknown]>([
    ['no row', []],
    [
      'two rows',
      [
        { requester_display_name: null, requester_email: null },
        { requester_display_name: null, requester_email: null },
      ],
    ],
    ['a non-array', { requester_display_name: null, requester_email: null }],
    ['a missing column', [{ requester_display_name: 'María' }]],
    ['a blank email', [{ requester_display_name: 'María', requester_email: ' ' }]],
    ['a blank name', [{ requester_display_name: '', requester_email: null }]],
    ['a non-string email', [{ requester_display_name: 'María', requester_email: 7 }]],
  ])('rejects %s', (_label, raw) => {
    expect(parseAppointmentRequesterContact(raw)).toBeNull();
  });
});

describe('getClinicAppointmentRequesterContact', () => {
  beforeEach(() => rpc.mockReset());

  it('reads exactly one Appointment of one Clinic', async () => {
    rpc.mockResolvedValue({
      data: [{ requester_display_name: 'María López', requester_email: 'maria@example.test' }],
      error: null,
    });
    await expect(getClinicAppointmentRequesterContact(CLINIC_ID, APPOINTMENT_ID)).resolves.toEqual({
      kind: 'contact',
      contact: { displayName: 'María López', email: 'maria@example.test' },
    });
    expect(rpc).toHaveBeenCalledWith('get_clinic_appointment_requester_contact', {
      p_clinic_id: CLINIC_ID,
      p_appointment_id: APPOINTMENT_ID,
    });
  });

  it.each<[string, unknown, string]>([
    ['28000', { code: '28000', message: 'Authentication is required' }, 'authenticationRequired'],
    [
      'the uniform 42501',
      { code: '42501', message: 'Appointment requester contact unavailable' },
      'accessDenied',
    ],
    ['any other error', { code: 'XX000', message: 'boom' }, 'unavailable'],
  ])('maps %s', async (_label, error, kind) => {
    rpc.mockResolvedValue({ data: null, error });
    await expect(getClinicAppointmentRequesterContact(CLINIC_ID, APPOINTMENT_ID)).resolves.toEqual({
      kind,
    });
  });

  it('treats a malformed payload or a network failure as unavailable, never rejecting', async () => {
    rpc.mockResolvedValue({ data: [{ requester_email: 'x@y.z' }], error: null });
    await expect(getClinicAppointmentRequesterContact(CLINIC_ID, APPOINTMENT_ID)).resolves.toEqual({
      kind: 'unavailable',
    });
    rpc.mockRejectedValue(new Error('offline'));
    await expect(getClinicAppointmentRequesterContact(CLINIC_ID, APPOINTMENT_ID)).resolves.toEqual({
      kind: 'unavailable',
    });
  });
});

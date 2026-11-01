import {
  APPOINTMENT_NO_SHOW_INVALID_REQUEST,
  APPOINTMENT_NO_SHOW_MALFORMED,
} from '@/data/appointment-no-show';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { mapAppointmentNoShowErrorToKey } from '@/i18n/appointment-no-show-error-messages';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapAppointmentNoShowErrorToKey', () => {
  it.each<[string, string, string]>([
    ['normalized 28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['no authenticated subject', 'Authentication is required', 'errors.sessionExpired'],
    [
      'no domain User',
      'No coherent domain User exists for the authenticated subject',
      'errors.sessionExpired',
    ],
    [
      'capability denial (42501)',
      'Applicable Clinic-management capability is required',
      'appointmentNoShow.accessLost',
    ],
    [
      'stale P0001',
      'Stale confirmed Appointment schedule revision',
      'appointmentNoShow.staleSchedule',
    ],
    [
      'lifecycle changed',
      'Only a CONFIRMED Appointment may be marked no-show',
      'appointmentNoShow.lifecycleChanged',
    ],
    [
      'start not reached',
      'Appointment cannot be marked no-show before its confirmed scheduled start',
      'appointmentNoShow.tooEarly',
    ],
    [
      'clinical records exist',
      'Appointment with clinical documentation cannot be marked no-show',
      'appointmentNoShow.documented',
    ],
  ])('maps %s', (_label, error, key) => {
    expect(mapAppointmentNoShowErrorToKey(error)).toBe(key);
  });

  it.each<[string, string]>([
    ['an unknown Appointment', 'Appointment does not exist'],
    ['a missing Care Authorization', 'Appointment has no Care Authorization'],
    [
      'the stale requested-revision error of confirmation',
      'Stale requested Appointment schedule revision',
    ],
    ['a network failure', 'Network request failed'],
    ['an invalid local request', APPOINTMENT_NO_SHOW_INVALID_REQUEST],
    ['a malformed success payload', APPOINTMENT_NO_SHOW_MALFORMED],
    ['an empty message', ''],
  ])('falls back to the generic no-show failure for %s, never echoing raw text', (_l, error) => {
    expect(mapAppointmentNoShowErrorToKey(error)).toBe('appointmentNoShow.failed');
  });

  it('uses the specified stale copy in both locales', () => {
    expect(es.appointmentNoShow.staleSchedule).toBe(
      'La cita ha cambiado. Revisa el horario actualizado antes de marcarla como no presentada.',
    );
    expect(en.appointmentNoShow.staleSchedule).toBe(
      'The appointment has changed. Review the updated time before marking it as no-show.',
    );
  });
});

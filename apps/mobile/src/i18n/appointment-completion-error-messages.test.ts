import {
  APPOINTMENT_COMPLETION_INVALID_REQUEST,
  APPOINTMENT_COMPLETION_MALFORMED,
} from '@/data/appointment-completion';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { mapAppointmentCompletionErrorToKey } from '@/i18n/appointment-completion-error-messages';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapAppointmentCompletionErrorToKey', () => {
  it.each<[string, string, string]>([
    ['normalized 28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['no authenticated subject', 'Authentication is required', 'errors.sessionExpired'],
    ['no domain User', 'No coherent domain User exists', 'errors.sessionExpired'],
    [
      'capability denial (42501)',
      'Applicable Clinic-management capability is required',
      'appointmentCompletion.accessLost',
    ],
    [
      'stale P0001',
      'Stale confirmed Appointment schedule revision',
      'appointmentCompletion.staleSchedule',
    ],
    [
      'lifecycle changed',
      'Only a CONFIRMED Appointment may be completed',
      'appointmentCompletion.lifecycleChanged',
    ],
    [
      'start not reached',
      'Appointment cannot be completed before its confirmed scheduled start',
      'appointmentCompletion.tooEarly',
    ],
  ])('maps %s', (_label, error, key) => {
    expect(mapAppointmentCompletionErrorToKey(error)).toBe(key);
  });

  it.each<[string, string]>([
    ['an unknown Appointment', 'Appointment does not exist'],
    [
      'a no-show-only rule (clinical records never block completion)',
      'Appointment with clinical documentation cannot be marked no-show',
    ],
    ['the no-show lifecycle error', 'Only a CONFIRMED Appointment may be marked no-show'],
    [
      'the stale requested-revision error of confirmation',
      'Stale requested Appointment schedule revision',
    ],
    ['a network failure', 'Network request failed'],
    ['an invalid local request', APPOINTMENT_COMPLETION_INVALID_REQUEST],
    ['a malformed success payload', APPOINTMENT_COMPLETION_MALFORMED],
    ['an empty message', ''],
  ])('falls back to the generic completion failure for %s, never echoing raw text', (_l, error) => {
    expect(mapAppointmentCompletionErrorToKey(error)).toBe('appointmentCompletion.failed');
  });

  it('uses the specified stale copy in both locales', () => {
    expect(es.appointmentCompletion.staleSchedule).toBe(
      'La cita ha cambiado. Revisa el horario actualizado antes de marcarla como completada.',
    );
    expect(en.appointmentCompletion.staleSchedule).toBe(
      'The appointment has changed. Review the updated time before marking it as completed.',
    );
  });
});

describe('completion copy (SPEC-APT-009, SPEC-APT-012 BR-46)', () => {
  it('distinguishes completion (the visit took place) from no-show (the Pet did not attend)', () => {
    expect(es.appointmentCompletion.action).toBe('Marcar como completada');
    expect(en.appointmentCompletion.action).toBe('Mark as completed');
    expect(es.appointmentCompletion.action).not.toBe(es.appointmentNoShow.action);
    expect(en.appointmentCompletion.action).not.toBe(en.appointmentNoShow.action);
    expect(es.appointmentCompletion.dialogMessage).toContain('la visita de {{petName}} tuvo lugar');
    expect(en.appointmentCompletion.dialogMessage).toContain(
      'the visit for {{petName}} took place',
    );
    expect(es.appointmentNoShow.dialogMessage).toContain('no acudió');
    expect(en.appointmentNoShow.dialogMessage).toContain('did not attend');
    expect(es.appointmentCompletion.resolutionHint).toContain('tuvo lugar');
    expect(es.appointmentCompletion.resolutionHint).toContain('no acudió');
    expect(en.appointmentCompletion.resolutionHint).toContain('took place');
    expect(en.appointmentCompletion.resolutionHint).toContain('did not attend');
  });

  it('states that no Veterinarian or clinical record is required, and implies none exists', () => {
    expect(es.appointmentCompletion.dialogMessage).toContain(
      'No hace falta asignar un veterinario ni registrar información clínica.',
    );
    expect(en.appointmentCompletion.dialogMessage).toContain(
      'No veterinarian assignment or clinical record is needed.',
    );
    for (const text of [es.appointmentCompletion.completed, en.appointmentCompletion.completed]) {
      expect(text.toLowerCase()).not.toMatch(/cl[ií]nic|historial|record|diagn/);
    }
  });

  it('interpolates the reviewed Pet, date and time into the dialog', () => {
    for (const message of [
      es.appointmentCompletion.dialogMessage,
      en.appointmentCompletion.dialogMessage,
    ]) {
      expect(message).toContain('{{petName}}');
      expect(message).toContain('{{date}}');
      expect(message).toContain('{{time}}');
    }
  });
});

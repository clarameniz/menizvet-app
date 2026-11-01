import {
  PROFESSIONAL_CANCELLATION_INVALID_REQUEST,
  PROFESSIONAL_CANCELLATION_MALFORMED,
} from '@/data/professional-appointment-cancellation';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import { mapProfessionalCancellationErrorToKey } from '@/i18n/professional-appointment-cancellation-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapProfessionalCancellationErrorToKey', () => {
  it.each<[string, string, string]>([
    ['normalized 28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['no authenticated subject', 'Authentication is required', 'errors.sessionExpired'],
    ['no domain User', 'No coherent domain User exists', 'errors.sessionExpired'],
    [
      'capability denial (42501)',
      'Applicable Clinic-management capability is required',
      'professionalCancellation.accessLost',
    ],
    [
      'stale P0001',
      'Stale Appointment schedule revision for cancellation',
      'professionalCancellation.staleSchedule',
    ],
    [
      'lifecycle changed',
      'Only a REQUESTED or CONFIRMED Appointment may be cancelled',
      'professionalCancellation.lifecycleChanged',
    ],
    [
      'lapsed request',
      'A REQUESTED Appointment whose requested time has passed cannot be cancelled',
      'professionalCancellation.requestExpired',
    ],
    [
      'clinical records exist',
      'Appointment with clinical documentation cannot be cancelled',
      'professionalCancellation.documented',
    ],
    [
      'missing reason',
      'A meaningful reason is required for a Clinic cancellation',
      'professionalCancellation.reasonMissing',
    ],
  ])('maps %s', (_label, error, key) => {
    expect(mapProfessionalCancellationErrorToKey(error)).toBe(key);
  });

  it.each<[string, string]>([
    ['an unknown Appointment', 'Appointment does not exist'],
    ['a missing Care Authorization', 'Appointment has no Appointment-derived Care Authorization'],
    ['the stale error of no-show', 'Stale confirmed Appointment schedule revision'],
    ['the stale error of confirmation', 'Stale requested Appointment schedule revision'],
    ['the invalid-token error', 'Expected schedule revision sequence must be a positive integer'],
    ['a network failure', 'Network request failed'],
    ['an invalid local request', PROFESSIONAL_CANCELLATION_INVALID_REQUEST],
    ['a malformed success payload', PROFESSIONAL_CANCELLATION_MALFORMED],
    ['an empty message', ''],
  ])(
    'falls back to the generic cancellation failure for %s, never echoing raw text',
    (_l, error) => {
      expect(mapProfessionalCancellationErrorToKey(error)).toBe('professionalCancellation.failed');
    },
  );

  it('uses the specified copy in both locales', () => {
    expect(es.professionalCancellation.staleSchedule).toBe(
      'La cita ha cambiado. Revisa el horario actualizado antes de cancelarla.',
    );
    expect(en.professionalCancellation.staleSchedule).toBe(
      'The appointment has changed. Review the updated schedule before cancelling it.',
    );
    expect(es.professionalCancellation.accessLost).toBe(
      'Ya no puedes cancelar citas en esta clínica.',
    );
    expect(es.professionalCancellation.documented).toBe(
      'Esta cita ya tiene registros clínicos y no se puede cancelar.',
    );
    expect(es.professionalCancellation.reasonLabel).toBe('Motivo de la cancelación');
    expect(en.professionalCancellation.reasonLabel).toBe('Cancellation reason');
    expect(es.professionalCancellation.submit).toBe('Cancelar cita');
    expect(en.professionalCancellation.submit).toBe('Cancel appointment');
    expect(es.professionalCancellation.reasonVisibilityHint).toBe(
      'Este motivo será visible para los responsables de la mascota.',
    );
    expect(en.professionalCancellation.reasonVisibilityHint).toBe(
      "This reason will be visible to the pet's guardians.",
    );
  });
});

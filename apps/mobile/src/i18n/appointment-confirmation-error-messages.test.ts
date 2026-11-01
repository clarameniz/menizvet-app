import {
  APPOINTMENT_CONFIRMATION_INVALID_REQUEST,
  APPOINTMENT_CONFIRMATION_MALFORMED,
} from '@/data/appointment-confirmation';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { mapAppointmentConfirmationErrorToKey } from '@/i18n/appointment-confirmation-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapAppointmentConfirmationErrorToKey', () => {
  it.each<[string, string, string]>([
    ['normalized 28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['no authenticated subject', 'Authentication is required', 'errors.sessionExpired'],
    [
      'no domain User',
      'No coherent domain User exists for the authenticated subject',
      'errors.sessionExpired',
    ],
    [
      'capability denial',
      'Applicable Appointment-management capability is required',
      'appointmentConfirmation.accessLost',
    ],
    [
      'Entitlement denial',
      'Applicable professional Entitlement is required',
      'appointmentConfirmation.entitlementDenied',
    ],
    [
      'stale P0001',
      'Stale requested Appointment schedule revision',
      'appointmentConfirmation.staleRequest',
    ],
    [
      'lifecycle changed',
      'Only a REQUESTED Appointment may be confirmed',
      'appointmentConfirmation.lifecycleChanged',
    ],
    [
      'past time',
      'A past requested Appointment cannot be confirmed',
      'appointmentConfirmation.timePassed',
    ],
    [
      'Clinic Availability',
      'Clinic Appointment Availability does not cover the requested interval',
      'appointmentConfirmation.timeUnavailable',
    ],
    [
      'ended Veterinarian Clinic Assignment',
      'Currently assigned Veterinarian no longer has a valid Clinic Assignment',
      'appointmentConfirmation.veterinarianUnavailable',
    ],
    [
      'Veterinarian unavailable',
      'Currently assigned Veterinarian is not available for the requested interval',
      'appointmentConfirmation.veterinarianUnavailable',
    ],
    [
      'confirmed-commitment conflict',
      'Veterinarian Professional Profile 7c0f… has conflicting confirmed Appointment commitments across Clinics',
      'appointmentConfirmation.veterinarianUnavailable',
    ],
  ])('maps %s', (_label, error, key) => {
    expect(mapAppointmentConfirmationErrorToKey(error)).toBe(key);
  });

  it.each<[string, string]>([
    ['an unknown Appointment', 'Appointment does not exist'],
    ['a network failure', 'Network request failed'],
    ['an invalid local request', APPOINTMENT_CONFIRMATION_INVALID_REQUEST],
    ['a malformed success payload', APPOINTMENT_CONFIRMATION_MALFORMED],
    ['an empty message', ''],
  ])(
    'falls back to the generic confirmation failure for %s, never echoing raw text',
    (_l, error) => {
      expect(mapAppointmentConfirmationErrorToKey(error)).toBe('appointmentConfirmation.failed');
    },
  );

  it('does not reuse Guardian wording for the shared Entitlement or Availability conditions', () => {
    expect(
      mapAppointmentConfirmationErrorToKey('Applicable professional Entitlement is required'),
    ).not.toBe('appointmentErrors.entitlementDenied');
    expect(
      mapAppointmentConfirmationErrorToKey(
        'Clinic Appointment Availability does not cover the requested interval',
      ),
    ).not.toBe('appointmentErrors.timeUnavailable');
  });
});

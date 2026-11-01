import {
  APPOINTMENT_HOURS_ACCESS_DENIED,
  APPOINTMENT_HOURS_INVALID_REQUEST,
  APPOINTMENT_HOURS_MALFORMED,
  APPOINTMENT_HOURS_WEEKLY_STALE,
} from '@/data/clinic-appointment-hours';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import {
  mapAppointmentHoursLoadErrorToKey,
  mapAppointmentHoursSaveErrorToKey,
} from '@/i18n/appointment-hours-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapAppointmentHoursSaveErrorToKey', () => {
  it.each([
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    ['Authentication is required', 'errors.sessionExpired'],
    [APPOINTMENT_HOURS_INVALID_REQUEST, 'appointmentHours.invalidInput'],
    [APPOINTMENT_HOURS_WEEKLY_STALE, 'appointmentHours.weeklyStale'],
    [
      'Applicable Appointment Availability-management capability is required',
      'appointmentHours.accessLost',
    ],
    ['Applicable Clinic-management capability is required', 'appointmentHours.accessLost'],
    ['Clinic does not exist', 'appointmentHours.accessLost'],
    ['Professional scheduling Entitlement is required', 'appointmentHours.entitlementDenied'],
    ['Clinic Appointment Availability Periods must not overlap', 'appointmentHours.overlapError'],
    [
      'Clinic Appointment Availability Exception periods must not overlap',
      'appointmentHours.overlapError',
    ],
    [
      'Clinic Appointment Availability Periods must not contain duplicates',
      'appointmentHours.duplicateError',
    ],
    [
      'Clinic Appointment Availability requires a valid scheduling timezone',
      'appointmentHours.timezoneMissing',
    ],
    [
      'Clinic Appointment Availability Exception requires a valid scheduling timezone',
      'appointmentHours.timezoneMissing',
    ],
    [
      'Clinic standard Appointment duration must be between 10 and 240 minutes',
      'appointmentHours.durationInvalid',
    ],
    [
      'Clinic local time must use a valid ISO local-time representation',
      'appointmentHours.invalidInput',
    ],
    [
      'Clinic Appointment Availability Period must have start_time before end_time',
      'appointmentHours.invalidInput',
    ],
    [
      'Clinic Appointment Availability Period ISO weekday must be between 1 and 7',
      'appointmentHours.invalidInput',
    ],
    [
      'OPEN Clinic Appointment Availability Exception requires at least one period',
      'appointmentHours.invalidInput',
    ],
    [
      'CLOSED Clinic Appointment Availability Exception must not contain periods',
      'appointmentHours.invalidInput',
    ],
    [
      'Clinic Appointment Availability Exception kind must be CLOSED or OPEN',
      'appointmentHours.invalidInput',
    ],
    ['Network request failed', 'appointmentHours.saveFailed'],
    [APPOINTMENT_HOURS_MALFORMED, 'appointmentHours.saveFailed'],
  ])('maps %p to %p', (error, key) => {
    expect(mapAppointmentHoursSaveErrorToKey(error)).toBe(key);
  });

  it('distinguishes the missing Entitlement from the missing capability (both 42501)', () => {
    expect(
      mapAppointmentHoursSaveErrorToKey('Professional scheduling Entitlement is required'),
    ).not.toBe(
      mapAppointmentHoursSaveErrorToKey(
        'Applicable Appointment Availability-management capability is required',
      ),
    );
  });
});

describe('mapAppointmentHoursLoadErrorToKey', () => {
  it.each([
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    [APPOINTMENT_HOURS_ACCESS_DENIED, 'appointmentHours.accessLost'],
    [APPOINTMENT_HOURS_MALFORMED, 'appointmentHours.loadError'],
    ['canceling statement due to statement timeout', 'appointmentHours.loadError'],
  ])('maps %p to %p', (error, key) => {
    expect(mapAppointmentHoursLoadErrorToKey(error)).toBe(key);
  });
});

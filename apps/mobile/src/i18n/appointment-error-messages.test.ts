import { mapAppointmentErrorToKey } from '@/i18n/appointment-error-messages';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';

describe('mapAppointmentErrorToKey — Guardian cutoff at the confirmed start (SPEC-APT-003 BR-31)', () => {
  const CUTOFF =
    'A Guardian cannot cancel a CONFIRMED Appointment whose confirmed start has been reached';

  it('maps the backend cutoff rejection to its own calm key', () => {
    expect(mapAppointmentErrorToKey(CUTOFF)).toBe('appointmentErrors.confirmedStartReachedCancel');
  });

  it('keeps it distinct from the lapsed-request, lifecycle, and documentation rejections', () => {
    expect(
      mapAppointmentErrorToKey(
        'A REQUESTED Appointment whose requested time has passed cannot be cancelled',
      ),
    ).toBe('appointmentErrors.lapsedRequestCancel');
    expect(
      mapAppointmentErrorToKey('Only a REQUESTED or CONFIRMED Appointment may be cancelled'),
    ).toBe('appointmentErrors.lifecycleChanged');
    expect(
      mapAppointmentErrorToKey('Appointment with clinical documentation cannot be cancelled'),
    ).toBe('appointmentErrors.lifecycleChanged');
  });

  it('is localized in both catalogs without echoing the backend text', () => {
    expect(es.appointmentErrors.confirmedStartReachedCancel).toBe(
      'Esta cita ya no se puede cancelar.',
    );
    expect(en.appointmentErrors.confirmedStartReachedCancel).toBe(
      'This appointment can no longer be cancelled.',
    );
    expect(en.appointmentErrors.confirmedStartReachedCancel).not.toContain('CONFIRMED');
  });
});

describe('mapAppointmentErrorToKey — pending-request and lapsed-request rejections', () => {
  const DUPLICATE = 'A pending Appointment request already exists for this Pet at this Clinic';
  const LAPSED_CANCEL =
    'A REQUESTED Appointment whose requested time has passed cannot be cancelled';
  const LAPSED_RESCHEDULE =
    'A REQUESTED Appointment whose requested time has passed cannot be rescheduled';

  it('maps a second pending request for the same Pet and Clinic (SPEC-APT-001 BR-35)', () => {
    expect(mapAppointmentErrorToKey(DUPLICATE)).toBe('appointmentErrors.duplicatePendingRequest');
  });

  it('maps a lapsed-request cancellation rejection (SPEC-APT-003 BR-23)', () => {
    expect(mapAppointmentErrorToKey(LAPSED_CANCEL)).toBe('appointmentErrors.lapsedRequestCancel');
  });

  it('maps a lapsed-request reschedule rejection (SPEC-APT-004 BR-27)', () => {
    expect(mapAppointmentErrorToKey(LAPSED_RESCHEDULE)).toBe(
      'appointmentErrors.lapsedRequestReschedule',
    );
  });

  it('localizes all three in both catalogs, never echoing the backend text', () => {
    expect(es.appointmentErrors.duplicatePendingRequest).toBe(
      'Ya hay una solicitud pendiente para esta mascota en esta clínica.',
    );
    expect(en.appointmentErrors.duplicatePendingRequest).toBe(
      'There is already a pending appointment request for this pet at this clinic.',
    );
    expect(es.appointmentErrors.lapsedRequestCancel).toBe(
      'Esta solicitud ya ha vencido y no se puede cancelar.',
    );
    expect(en.appointmentErrors.lapsedRequestCancel).toBe(
      'This request has expired and can no longer be cancelled.',
    );
    expect(es.appointmentErrors.lapsedRequestReschedule).toBe(
      'Esta solicitud ya ha vencido. Crea una nueva solicitud para elegir otro horario.',
    );
    expect(en.appointmentErrors.lapsedRequestReschedule).toBe(
      'This request has expired. Create a new request to choose another time.',
    );
    for (const message of [DUPLICATE, LAPSED_CANCEL, LAPSED_RESCHEDULE]) {
      const key = mapAppointmentErrorToKey(message);
      expect(key).not.toBe(message);
      const field = key.split('.')[1] as keyof typeof es.appointmentErrors;
      expect(es.appointmentErrors[field]).not.toContain('Appointment');
      expect(en.appointmentErrors[field]).not.toBe(message);
    }
  });

  it('keeps the existing lifecycle and generic mappings unchanged', () => {
    expect(
      mapAppointmentErrorToKey('Only a REQUESTED or CONFIRMED Appointment may be cancelled'),
    ).toBe('appointmentErrors.lifecycleChanged');
    expect(
      mapAppointmentErrorToKey(
        'Only a REQUESTED Appointment may be rescheduled through this workflow',
      ),
    ).toBe('appointmentErrors.lifecycleChanged');
    expect(mapAppointmentErrorToKey('Some unknown backend failure')).toBe('common.genericError');
  });
});

describe('mapAppointmentErrorToKey', () => {
  it('maps the verified-email precondition to the shared emailNotConfirmed key', () => {
    expect(
      mapAppointmentErrorToKey('The acting User must satisfy account verification requirements'),
    ).toBe('errors.emailNotConfirmed');
  });

  it('maps an unauthenticated/session-less call to the shared sessionExpired key', () => {
    expect(mapAppointmentErrorToKey('Authentication is required')).toBe('errors.sessionExpired');
  });

  it('maps a coherent-domain-User failure to the shared sessionExpired key', () => {
    expect(
      mapAppointmentErrorToKey('No coherent domain User exists for the authenticated subject'),
    ).toBe('errors.sessionExpired');
  });

  it('maps missing APPOINTMENT_MANAGEMENT Entitlement to the dedicated calm denial message', () => {
    expect(mapAppointmentErrorToKey('Applicable professional Entitlement is required')).toBe(
      'appointmentErrors.entitlementDenied',
    );
  });

  it.each([
    'Current Guardianship of the Pet is required',
    'Current Guardianship of the Appointment Pet is required',
    'Current Guardianship or applicable Clinic schedule-view capability is required',
  ])('maps every current-Guardianship wording to the lostGuardianship key: %s', (message) => {
    expect(mapAppointmentErrorToKey(message)).toBe('appointmentErrors.lostGuardianship');
  });

  it('maps an unpublished-Clinic request rejection to clinicNotPublished', () => {
    expect(mapAppointmentErrorToKey('Appointment requests require a published Clinic')).toBe(
      'appointmentErrors.clinicNotPublished',
    );
  });

  it('maps an unavailable candidate interval to timeUnavailable', () => {
    expect(
      mapAppointmentErrorToKey(
        'Clinic Appointment Availability does not cover the requested interval',
      ),
    ).toBe('appointmentErrors.timeUnavailable');
    expect(
      mapAppointmentErrorToKey(
        'Clinic Appointment Availability does not cover the new requested interval',
      ),
    ).toBe('appointmentErrors.timeUnavailable');
  });

  it.each([
    'Requested Appointment time must be in the future',
    'Rescheduled Appointment time must be in the future',
  ])('maps a non-future candidate time to notFuture: %s', (message) => {
    expect(mapAppointmentErrorToKey(message)).toBe('appointmentErrors.notFuture');
  });

  it('maps a DST/offset-invalid civil time to invalidCivilTime', () => {
    expect(
      mapAppointmentErrorToKey(
        'UTC offset seconds 3600 do not identify a valid occurrence of local civil time 2026-03-29 02:30:00 in timezone Europe/Madrid',
      ),
    ).toBe('appointmentErrors.invalidCivilTime');
  });

  it('maps a same-time reschedule attempt to sameTimeReschedule', () => {
    expect(
      mapAppointmentErrorToKey('Rescheduled time must differ from the current requested time'),
    ).toBe('appointmentErrors.sameTimeReschedule');
  });

  it('maps a missing reason for visit to missingReason', () => {
    expect(mapAppointmentErrorToKey('Appointment request requires a reason for visit')).toBe(
      'appointmentErrors.missingReason',
    );
  });

  it.each(['Clinic has no currently configured standard Appointment duration'])(
    'maps an unconfigured standard duration to noStandardDuration: %s',
    (message) => {
      expect(mapAppointmentErrorToKey(message)).toBe('appointmentErrors.noStandardDuration');
    },
  );

  it.each([
    'Only a REQUESTED Appointment may be rescheduled through this workflow',
    'Only a REQUESTED or CONFIRMED Appointment may be cancelled',
    'Appointment with clinical documentation cannot be cancelled',
  ])('maps a lifecycle-state conflict to lifecycleChanged: %s', (message) => {
    expect(mapAppointmentErrorToKey(message)).toBe('appointmentErrors.lifecycleChanged');
  });

  it('matches case-insensitively', () => {
    expect(mapAppointmentErrorToKey('APPLICABLE PROFESSIONAL ENTITLEMENT IS REQUIRED')).toBe(
      'appointmentErrors.entitlementDenied',
    );
  });

  it('falls back to the generic error for an unrecognized message', () => {
    expect(mapAppointmentErrorToKey('Appointment does not exist')).toBe('common.genericError');
  });

  it('falls back to the generic error for an empty message', () => {
    expect(mapAppointmentErrorToKey('')).toBe('common.genericError');
  });

  it('never exposes the raw backend message as the mapped result', () => {
    const rawMessage = 'Clinic Appointment Availability does not cover the requested interval';
    expect(mapAppointmentErrorToKey(rawMessage)).not.toBe(rawMessage);
  });
});

import {
  CLINIC_SCHEDULE_ACCESS_DENIED,
  CLINIC_SCHEDULE_MALFORMED,
} from '@/data/clinic-appointment-schedule';
import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_CONTEXT_MALFORMED,
} from '@/data/professional-context';
import {
  mapClinicScheduleErrorToKey,
  mapProfessionalClinicsErrorToKey,
  mapProfessionalContextErrorToKey,
} from '@/i18n/professional-context-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapProfessionalContextErrorToKey', () => {
  it('maps SQLSTATE 28000 (normalized by the data layer) to the shared sessionExpired key', () => {
    expect(mapProfessionalContextErrorToKey(PROFESSIONAL_CONTEXT_AUTH_REQUIRED)).toBe(
      'errors.sessionExpired',
    );
  });

  it('maps a malformed payload to the generic professional load error', () => {
    expect(mapProfessionalContextErrorToKey(PROFESSIONAL_CONTEXT_MALFORMED)).toBe(
      'professional.loadError',
    );
  });

  it('never echoes raw backend or network text', () => {
    expect(mapProfessionalContextErrorToKey('Network request failed')).toBe(
      'professional.loadError',
    );
  });
});

describe('mapClinicScheduleErrorToKey', () => {
  it('maps SQLSTATE 28000 to the shared sessionExpired key', () => {
    expect(mapClinicScheduleErrorToKey(PROFESSIONAL_CONTEXT_AUTH_REQUIRED)).toBe(
      'errors.sessionExpired',
    );
  });

  it('maps SQLSTATE 42501 to the schedule access error', () => {
    expect(mapClinicScheduleErrorToKey(CLINIC_SCHEDULE_ACCESS_DENIED)).toBe(
      'clinicSchedule.accessError',
    );
  });

  it('maps a malformed payload or any other failure to the generic schedule error', () => {
    expect(mapClinicScheduleErrorToKey(CLINIC_SCHEDULE_MALFORMED)).toBe('clinicSchedule.loadError');
    expect(mapClinicScheduleErrorToKey('Network request failed')).toBe('clinicSchedule.loadError');
  });
});

describe('mapProfessionalClinicsErrorToKey', () => {
  it('maps SQLSTATE 28000 to the same shared sessionExpired key', () => {
    expect(mapProfessionalClinicsErrorToKey(PROFESSIONAL_CONTEXT_AUTH_REQUIRED)).toBe(
      'errors.sessionExpired',
    );
  });

  it('maps a malformed payload or any other failure to the Professional Clinics load error', () => {
    expect(mapProfessionalClinicsErrorToKey(PROFESSIONAL_CONTEXT_MALFORMED)).toBe(
      'professionalClinics.loadError',
    );
    expect(mapProfessionalClinicsErrorToKey('Network request failed')).toBe(
      'professionalClinics.loadError',
    );
  });
});

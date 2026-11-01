import {
  PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
  PROFESSIONAL_RESCHEDULE_MALFORMED,
} from '@/data/professional-appointment-reschedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import {
  mapProfessionalRescheduleErrorToKey,
  mapRescheduleCandidatesErrorToKey,
  mapRescheduleWithdrawalErrorToKey,
} from '@/i18n/professional-reschedule-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

describe('mapProfessionalRescheduleErrorToKey', () => {
  it.each<[string, string, string]>([
    ['normalized 28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    [
      'no domain User',
      'No coherent domain User exists for the authenticated subject',
      'errors.sessionExpired',
    ],
    [
      'stale P0001',
      'Stale confirmed Appointment schedule revision for reschedule proposal',
      'professionalReschedule.staleSchedule',
    ],
    [
      'capability denial',
      'Applicable Appointment-management capability is required',
      'professionalReschedule.accessLost',
    ],
    [
      'Entitlement denial',
      'Applicable professional Entitlement is required',
      'professionalReschedule.entitlementDenied',
    ],
    [
      'lifecycle changed',
      'Only a CONFIRMED Appointment may receive a reschedule Proposal',
      'professionalReschedule.lifecycleChanged',
    ],
    [
      'start reached',
      'The current confirmed Appointment time must still be in the future',
      'professionalReschedule.startPassed',
    ],
    [
      'clinical records',
      'Appointment with clinical documentation cannot be rescheduled',
      'professionalReschedule.documented',
    ],
    [
      'no standard duration',
      'Clinic has no currently configured standard Appointment duration',
      'professionalReschedule.noStandardDuration',
    ],
    [
      'pending proposal',
      'Appointment 1 already has an actionable unresolved reschedule Proposal',
      'professionalReschedule.pendingExists',
    ],
    [
      'same start',
      'Proposed time must differ from the current confirmed time',
      'professionalReschedule.sameTime',
    ],
    [
      'Clinic Availability',
      'Clinic Appointment Availability does not cover the proposed interval',
      'professionalReschedule.timeUnavailable',
    ],
    [
      'past proposed time',
      'Proposed Appointment time must be in the future',
      'professionalReschedule.timeUnavailable',
    ],
    [
      'Veterinarian unavailable or conflicting',
      'Currently assigned Veterinarian is not available for the proposed interval',
      'professionalReschedule.veterinarianUnavailable',
    ],
    [
      'Veterinarian assignment ended',
      'Currently assigned Veterinarian no longer has a valid Clinic Assignment',
      'professionalReschedule.veterinarianUnavailable',
    ],
    [
      'missing reason',
      'A meaningful reason is required for a Clinic-proposed reschedule',
      'professionalReschedule.reasonMissing',
    ],
    ['invalid request', PROFESSIONAL_RESCHEDULE_INVALID_REQUEST, 'professionalReschedule.failed'],
    ['malformed payload', PROFESSIONAL_RESCHEDULE_MALFORMED, 'professionalReschedule.failed'],
    ['network failure', 'Network request failed', 'professionalReschedule.failed'],
  ])('maps %s', (_label, error, key) => {
    expect(mapProfessionalRescheduleErrorToKey(error)).toBe(key);
  });
});

describe('mapRescheduleWithdrawalErrorToKey', () => {
  it.each<[string, string, string]>([
    [
      'capability denial',
      'Applicable Clinic-management capability is required',
      'professionalReschedule.accessLost',
    ],
    [
      'no longer actionable',
      'Reschedule Proposal is no longer actionable',
      'professionalReschedule.proposalNoLongerPending',
    ],
    [
      'Guardian proposal',
      'Only a Clinic-originated Reschedule Proposal may be withdrawn',
      'professionalReschedule.proposalNoLongerPending',
    ],
    ['anything else', 'Network request failed', 'professionalReschedule.withdrawFailed'],
  ])('maps %s', (_label, error, key) => {
    expect(mapRescheduleWithdrawalErrorToKey(error)).toBe(key);
  });
});

describe('professionalReschedule catalog', () => {
  it('has a non-empty Spanish and English string for every key', () => {
    for (const catalog of [es.professionalReschedule, en.professionalReschedule]) {
      for (const value of Object.values(catalog)) {
        expect(value.trim().length).toBeGreaterThan(0);
      }
    }
  });
});

describe('mapRescheduleCandidatesErrorToKey', () => {
  it.each<[string, string, string]>([
    // Unknown read failures say the times could not be loaded — never that a proposal failed.
    ['a network failure', 'Network request failed', 'professionalReschedule.candidatesLoadError'],
    [
      'a malformed payload',
      PROFESSIONAL_RESCHEDULE_MALFORMED,
      'professionalReschedule.candidatesLoadError',
    ],
    [
      'an invalid request',
      PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
      'professionalReschedule.candidatesLoadError',
    ],
    [
      'a backend without the candidate read (PostgREST PGRST202)',
      'Could not find the function public.get_appointment_reschedule_candidate_start_times(p_appointment_id, p_end_date, p_start_date) in the schema cache',
      'professionalReschedule.candidatesLoadError',
    ],
    // Known rules keep their specific copy.
    ['session expiry', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    [
      'capability denial',
      'Applicable Appointment-management capability is required',
      'professionalReschedule.accessLost',
    ],
    [
      'Entitlement denial',
      'Applicable professional Entitlement is required',
      'professionalReschedule.entitlementDenied',
    ],
    [
      'clinical records',
      'Appointment with clinical documentation cannot be rescheduled',
      'professionalReschedule.documented',
    ],
    [
      'no standard duration',
      'Clinic has no currently configured standard Appointment duration',
      'professionalReschedule.noStandardDuration',
    ],
    [
      'span too long',
      'Requested range must not span more than 60 days',
      'professionalReschedule.candidatesLoadError',
    ],
  ])('maps %s', (_label, error, key) => {
    expect(mapRescheduleCandidatesErrorToKey(error)).toBe(key);
  });

  it('never maps a candidate-read failure to the proposal-submission copy', () => {
    for (const error of ['Network request failed', PROFESSIONAL_RESCHEDULE_MALFORMED, 'anything']) {
      expect(mapRescheduleCandidatesErrorToKey(error)).not.toBe('professionalReschedule.failed');
    }
  });
});

import { mapRescheduleAcceptanceErrorToKey } from '@/i18n/reschedule-acceptance-error-messages';

describe('mapRescheduleAcceptanceErrorToKey', () => {
  it.each<[string, string, string]>([
    ['no authenticated subject', 'Authentication is required', 'errors.sessionExpired'],
    [
      'lost Guardianship',
      'Current Guardianship of the Appointment Pet is required',
      'appointmentErrors.lostGuardianship',
    ],
    [
      'Clinic Entitlement',
      'Applicable professional Entitlement is required',
      'rescheduleProposal.clinicUnavailable',
    ],
    [
      'clinical records',
      'Appointment with clinical documentation cannot be rescheduled',
      'rescheduleProposal.documented',
    ],
    [
      'Clinic Availability',
      'Clinic Appointment Availability does not cover the proposed interval',
      'rescheduleProposal.timeUnavailable',
    ],
    [
      'Veterinarian',
      'Currently assigned Veterinarian is not available for the proposed interval',
      'rescheduleProposal.timeUnavailable',
    ],
    [
      'already accepted or withdrawn',
      'Reschedule Proposal is no longer actionable',
      'rescheduleProposal.proposalUnavailable',
    ],
    [
      'proposer lost authority',
      'The Clinic Proposal is no longer actionable because proposing authority was lost',
      'rescheduleProposal.proposalUnavailable',
    ],
    [
      'superseded base',
      'Reschedule Proposal base revision is no longer the current confirmed context',
      'rescheduleProposal.proposalUnavailable',
    ],
    [
      'cancelled meanwhile',
      'Appointment must remain CONFIRMED to accept a reschedule Proposal',
      'rescheduleProposal.proposalUnavailable',
    ],
    [
      'lapsed proposed time',
      'Proposed Appointment time must still be in the future',
      'rescheduleProposal.proposalUnavailable',
    ],
    [
      'lapsed confirmed time',
      'The current confirmed Appointment time must still be future and actionable',
      'rescheduleProposal.proposalUnavailable',
    ],
    ['network failure', 'Network request failed', 'rescheduleProposal.failed'],
  ])('maps %s', (_label, error, key) => {
    expect(mapRescheduleAcceptanceErrorToKey(error)).toBe(key);
  });
});

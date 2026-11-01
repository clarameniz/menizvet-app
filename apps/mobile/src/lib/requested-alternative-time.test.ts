import type { PetAppointment } from '@/data/appointments';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { RescheduleCandidate } from '@/data/professional-appointment-reschedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import {
  canSubmitClinicRescheduleProposal,
  initialRescheduleCandidateWindow,
  nextRescheduleCandidateWindow,
} from '@/lib/appointment-reschedule';
import {
  alternativeTimeProposalRequestFor,
  classifyAlternativeTimeAppointment,
  discardsPendingAlternativeTime,
  isAwaitingClinicConfirmationOfAcceptedAlternative,
  offersAlternativeTimeAcceptance,
  offersAlternativeTimeProposal,
  pendingAlternativeTime,
  professionalAlternativeTimeHref,
  showsAlternativeTimeNotCurrentlyAcceptable,
  wasAlternativeTimeAccepted,
  type PendingAlternativeTime,
} from '@/lib/requested-alternative-time';

const NOW = new Date('2035-03-01T12:00:00Z');
const PROPOSAL_ID = '33333333-3333-4333-8333-333333333333';

function clinic(capabilities: ProfessionalClinic['capabilities']): ProfessionalClinic {
  return {
    clinicId: 'clinic-1',
    clinicDisplayName: 'Animalia',
    organizationId: 'org-1',
    organizationDisplayName: 'Animalia Group',
    capabilities,
    unknownCapabilities: [],
  };
}

const ALTERNATIVE: PendingAlternativeTime & {
  currentlyAcceptable: boolean;
  currentlyFeasible: boolean;
} = {
  kind: 'requestedAlternativeTime',
  proposalId: PROPOSAL_ID,
  proposingContext: 'CLINIC',
  proposedStartAt: '2035-03-06T11:00:00Z',
  proposedEndAt: '2035-03-06T11:30:00Z',
  proposedTimezoneName: 'Europe/Madrid',
  reason: 'No veterinarian free at 10:00',
  currentlyAcceptable: true,
  currentlyFeasible: true,
};

function scheduleRow(
  overrides: Partial<ClinicScheduleAppointment> = {},
): ClinicScheduleAppointment {
  return {
    id: 'apt-1',
    petId: 'pet-1',
    petName: 'Luna',
    requestingUserId: 'user-1',
    requesterDisplayName: 'María López',
    reasonForVisit: 'Limping',
    guardianNotes: null,
    lifecycleState: 'REQUESTED',
    createdAt: '2035-01-01T00:00:00Z',
    currentScheduledStartAt: '2035-03-05T09:00:00Z',
    currentScheduledEndAt: '2035-03-05T09:30:00Z',
    currentSchedulingTimezoneName: 'Europe/Madrid',
    currentScheduleRevisionSequence: 1,
    currentVeterinarianClinicAssignmentId: null,
    pendingReschedule: null,
    currentScheduleSource: null,
    cancellationReason: null,
    hasClinicalRecord: false,
    ...overrides,
  };
}

function petAppointment(overrides: Partial<PetAppointment> = {}): PetAppointment {
  return {
    id: 'apt-1',
    clinicId: 'clinic-1',
    requestingUserId: 'user-1',
    reasonForVisit: 'Limping',
    guardianNotes: null,
    lifecycleState: 'REQUESTED',
    createdAt: '2035-01-01T00:00:00Z',
    currentScheduledStartAt: '2035-03-05T09:00:00Z',
    currentScheduledEndAt: '2035-03-05T09:30:00Z',
    currentSchedulingTimezoneName: 'Europe/Madrid',
    currentVeterinarianClinicAssignmentId: null,
    pendingReschedule: ALTERNATIVE,
    cancellationReason: null,
    currentScheduleSource: null,
    medicalAccessState: 'ACTIVE',
    ...overrides,
  };
}

const CANDIDATE: RescheduleCandidate = {
  localDate: '2035-03-06',
  localTime: '12:00:00',
  utcOffsetSeconds: 3600,
  endAt: '2035-03-06T11:30:00Z',
};

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const AVAILABLE = { kind: 'available' } as const;
const UNAVAILABLE = { kind: 'unavailable' } as const;
const UNVERIFIED = { kind: 'unknown', messageKey: 'professional.loadError' } as const;

describe('the discriminated pending proposal', () => {
  it('reads a pending Clinic alternative, and nothing for a confirmed reschedule or none', () => {
    expect(pendingAlternativeTime(scheduleRow({ pendingReschedule: ALTERNATIVE }))).toBe(
      ALTERNATIVE,
    );
    expect(
      pendingAlternativeTime(
        scheduleRow({
          lifecycleState: 'CONFIRMED',
          pendingReschedule: { ...ALTERNATIVE, kind: 'confirmedReschedule' },
        }),
      ),
    ).toBeNull();
    expect(pendingAlternativeTime(scheduleRow())).toBeNull();
  });
});

describe('accepted alternative awaiting Clinic confirmation (SPEC-APT-011 BR-33, SPEC-APT-012 BR-45)', () => {
  const clinicSource = { proposalId: PROPOSAL_ID, proposingContext: 'CLINIC' as const };

  it('is derived from a REQUESTED Appointment whose current interval came from a Clinic proposal', () => {
    expect(
      isAwaitingClinicConfirmationOfAcceptedAlternative(
        scheduleRow({ currentScheduleSource: clinicSource }),
      ),
    ).toBe(true);
  });

  it('is not an ordinary Guardian-authored request', () => {
    expect(isAwaitingClinicConfirmationOfAcceptedAlternative(scheduleRow())).toBe(false);
  });

  it('ends once confirmed, cancelled, or expired, whatever the provenance', () => {
    for (const lifecycleState of ['CONFIRMED', 'CANCELLED', 'EXPIRED'] as const) {
      expect(
        isAwaitingClinicConfirmationOfAcceptedAlternative(
          scheduleRow({ lifecycleState, currentScheduleSource: clinicSource }),
        ),
      ).toBe(false);
    }
  });
});

describe('offersAlternativeTimeProposal (SPEC-APT-018 §5)', () => {
  const capable = clinic(['APPOINTMENT_RESCHEDULE']);

  it('offers a future REQUESTED Appointment with no pending proposal at a capable Clinic', () => {
    expect(offersAlternativeTimeProposal(capable, scheduleRow(), NOW)).toBe(true);
  });

  it('is still offered after a Guardian accepted an earlier alternative (a new proposal is allowed)', () => {
    expect(
      offersAlternativeTimeProposal(
        capable,
        scheduleRow({
          currentScheduleSource: { proposalId: PROPOSAL_ID, proposingContext: 'CLINIC' },
        }),
        NOW,
      ),
    ).toBe(true);
  });

  it.each<[string, ProfessionalClinic, ClinicScheduleAppointment]>([
    [
      'with only APPOINTMENT_CONFIRM',
      clinic(['APPOINTMENT_CONFIRM', 'APPOINTMENT_VIEW_SCHEDULE']),
      scheduleRow(),
    ],
    ['for a CONFIRMED Appointment', capable, scheduleRow({ lifecycleState: 'CONFIRMED' })],
    [
      'once the requested start has passed',
      capable,
      scheduleRow({ currentScheduledStartAt: '2035-03-01T11:00:00Z' }),
    ],
    ['while a proposal is pending', capable, scheduleRow({ pendingReschedule: ALTERNATIVE })],
  ])('does not offer %s', (_label, professionalClinic, appointment) => {
    expect(offersAlternativeTimeProposal(professionalClinic, appointment, NOW)).toBe(false);
  });
});

describe('alternative-time routing and classification', () => {
  it('carries the reviewed requested sequence as a route token', () => {
    expect(professionalAlternativeTimeHref('clinic-1', 'apt-1', 2)).toEqual({
      pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/alternative-time',
      params: { clinicId: 'clinic-1', appointmentId: 'apt-1', sequence: '2' },
    });
  });

  it('is proposable only for the same REQUESTED revision the actor reviewed', () => {
    const capable = clinic(['APPOINTMENT_RESCHEDULE']);
    expect(classifyAlternativeTimeAppointment(capable, scheduleRow(), 1, NOW, AVAILABLE)).toBe(
      'proposable',
    );
    expect(classifyAlternativeTimeAppointment(capable, null, 1, NOW, AVAILABLE)).toBe(
      'appointmentMissing',
    );
    // A Guardian rescheduled or accepted an alternative meanwhile: a new revision.
    expect(
      classifyAlternativeTimeAppointment(
        capable,
        scheduleRow({ currentScheduleRevisionSequence: 2 }),
        1,
        NOW,
        AVAILABLE,
      ),
    ).toBe('changed');
    // Confirmed meanwhile.
    expect(
      classifyAlternativeTimeAppointment(
        capable,
        scheduleRow({ lifecycleState: 'CONFIRMED', currentScheduleRevisionSequence: 2 }),
        2,
        NOW,
        AVAILABLE,
      ),
    ).toBe('changed');
    expect(classifyAlternativeTimeAppointment(capable, scheduleRow(), null, NOW, AVAILABLE)).toBe(
      'changed',
    );
    expect(
      classifyAlternativeTimeAppointment(
        capable,
        scheduleRow({ pendingReschedule: ALTERNATIVE }),
        1,
        NOW,
        AVAILABLE,
      ),
    ).toBe('notOffered');
  });

  it('binds the request to the reviewed row, the candidate start, and the trimmed reason', () => {
    expect(
      alternativeTimeProposalRequestFor(
        scheduleRow({ currentScheduleRevisionSequence: 3 }),
        CANDIDATE,
        '  Vet away  ',
      ),
    ).toEqual({
      appointmentId: 'apt-1',
      candidate: CANDIDATE,
      reason: 'Vet away',
      expectedRequestedRevisionSequence: 3,
    });
  });
});

describe('form readiness (Send proposal enabled only when complete)', () => {
  it('needs a currently offered candidate and a non-whitespace reason, and nothing in flight', () => {
    const base = {
      proposable: true,
      candidates: [CANDIDATE],
      selectedCandidate: CANDIDATE,
      reason: 'Vet away',
      busy: false,
    };
    expect(canSubmitClinicRescheduleProposal(base)).toBe(true);
    expect(canSubmitClinicRescheduleProposal({ ...base, reason: ' \n ' })).toBe(false);
    expect(canSubmitClinicRescheduleProposal({ ...base, selectedCandidate: null })).toBe(false);
    expect(canSubmitClinicRescheduleProposal({ ...base, candidates: [] })).toBe(false);
    expect(canSubmitClinicRescheduleProposal({ ...base, candidates: null })).toBe(false);
    expect(canSubmitClinicRescheduleProposal({ ...base, busy: true })).toBe(false);
    expect(canSubmitClinicRescheduleProposal({ ...base, proposable: false })).toBe(false);
  });
});

describe('candidate paging stays Professional-unlimited for the alternative time (SPEC-APT-020 BR-4)', () => {
  it('pages past the Guardian +60-day horizon in 60-date windows', () => {
    const first = initialRescheduleCandidateWindow('Europe/Madrid', NOW);
    let window = first;
    for (let i = 0; i < 10; i++) window = nextRescheduleCandidateWindow(window);
    const daysBetween = (a: string, b: string) =>
      (Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000;
    expect(first.startDate).toBe('2035-03-01');
    // Ten consecutive 60-date windows later: 600 days ahead, far beyond today + 60.
    expect(daysBetween(first.startDate, window.startDate)).toBe(600);
  });
});

describe('confirm and reschedule warnings (SPEC-APT-002 BR-24, SPEC-APT-004 BR-28)', () => {
  it('warns only when a Clinic alternative for the request is pending', () => {
    expect(discardsPendingAlternativeTime(scheduleRow({ pendingReschedule: ALTERNATIVE }))).toBe(
      true,
    );
    expect(discardsPendingAlternativeTime(scheduleRow())).toBe(false);
    expect(
      discardsPendingAlternativeTime(
        scheduleRow({
          lifecycleState: 'CONFIRMED',
          pendingReschedule: { ...ALTERNATIVE, kind: 'confirmedReschedule' },
        }),
      ),
    ).toBe(false);
  });
});

describe('Guardian acceptance (SPEC-APT-019)', () => {
  it('offers a future Clinic alternative on a future REQUESTED Appointment', () => {
    expect(offersAlternativeTimeAcceptance(petAppointment(), NOW)).toBe(true);
  });

  it.each<[string, Partial<PetAppointment>]>([
    ['without a proposal', { pendingReschedule: null }],
    [
      'for a confirmed reschedule',
      {
        lifecycleState: 'CONFIRMED',
        pendingReschedule: { ...ALTERNATIVE, kind: 'confirmedReschedule' },
      },
    ],
    ['once the requested start has passed', { currentScheduledStartAt: '2035-02-01T10:00:00Z' }],
    [
      'once the proposed start has passed',
      { pendingReschedule: { ...ALTERNATIVE, proposedStartAt: '2035-02-01T10:00:00Z' } },
    ],
    ['for a CANCELLED Appointment', { lifecycleState: 'CANCELLED' }],
    [
      'when the Guardian view reports it not currently acceptable',
      { pendingReschedule: { ...ALTERNATIVE, currentlyAcceptable: false } },
    ],
  ])('does not offer %s', (_label, overrides) => {
    expect(offersAlternativeTimeAcceptance(petAppointment(overrides), NOW)).toBe(false);
  });

  it('replaces Accept with the generic notice while the alternative is not currently acceptable (SPEC-APT-019 §5)', () => {
    const appointment = petAppointment({
      pendingReschedule: { ...ALTERNATIVE, currentlyAcceptable: false },
    });
    expect(offersAlternativeTimeAcceptance(appointment, NOW)).toBe(false);
    expect(showsAlternativeTimeNotCurrentlyAcceptable(appointment, NOW)).toBe(true);
    expect(showsAlternativeTimeNotCurrentlyAcceptable(petAppointment(), NOW)).toBe(false);
  });

  it('shows no notice once the requested start has passed', () => {
    expect(
      showsAlternativeTimeNotCurrentlyAcceptable(
        petAppointment({
          currentScheduledStartAt: '2035-02-01T10:00:00Z',
          pendingReschedule: { ...ALTERNATIVE, currentlyAcceptable: false },
        }),
        NOW,
      ),
    ).toBe(false);
  });

  it('recognizes an acceptance already applied (lost response) by the current provenance', () => {
    expect(
      wasAlternativeTimeAccepted(ALTERNATIVE, {
        currentScheduleSource: { proposalId: PROPOSAL_ID, proposingContext: 'CLINIC' },
      }),
    ).toBe(true);
    expect(wasAlternativeTimeAccepted(ALTERNATIVE, { currentScheduleSource: null })).toBe(false);
    expect(
      wasAlternativeTimeAccepted(ALTERNATIVE, {
        currentScheduleSource: {
          proposalId: '44444444-4444-4444-8444-444444444444',
          proposingContext: 'CLINIC',
        },
      }),
    ).toBe(false);
  });
});

describe('classifyAlternativeTimeAppointment and APPOINTMENT_MANAGEMENT (SPEC-APT-012 BR-61)', () => {
  const capable = clinic(['APPOINTMENT_RESCHEDULE']);

  it('holds back an eligible proposal when the Entitlement is missing or unverified', () => {
    expect(classifyAlternativeTimeAppointment(capable, scheduleRow(), 1, NOW, UNAVAILABLE)).toBe(
      'entitlementUnavailable',
    );
    expect(classifyAlternativeTimeAppointment(capable, scheduleRow(), 1, NOW, UNVERIFIED)).toBe(
      'entitlementUnverified',
    );
  });

  it('says nothing about the Entitlement when the proposal is not possible anyway', () => {
    expect(
      classifyAlternativeTimeAppointment(
        capable,
        scheduleRow({ pendingReschedule: ALTERNATIVE }),
        1,
        NOW,
        UNAVAILABLE,
      ),
    ).toBe('notOffered');
    expect(
      classifyAlternativeTimeAppointment(
        clinic(['APPOINTMENT_CONFIRM']),
        scheduleRow(),
        1,
        NOW,
        UNAVAILABLE,
      ),
    ).toBe('notOffered');
  });
});

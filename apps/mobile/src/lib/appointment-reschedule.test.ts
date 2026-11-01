import type { PetAppointment } from '@/data/appointments';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { RescheduleCandidate } from '@/data/professional-appointment-reschedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import {
  canSubmitClinicRescheduleProposal,
  isClinicRescheduleReasonComplete,
  classifyRescheduleAppointment,
  clinicRescheduleProposalRequestFor,
  isReviewedConfirmedContext,
  offersRescheduleAcceptance,
  offersRescheduleProposal,
  offersRescheduleWithdrawal,
  parseReviewedSequence,
  professionalRescheduleHref,
  currentRescheduleCandidateWindow,
  hasActionableClinicProposal,
  initialRescheduleCandidateWindow,
  isPendingRescheduleCurrentlyInfeasible,
  isRescheduleProposalNoLongerPending,
  showsRescheduleNotCurrentlyAcceptable,
  nextRescheduleCandidateWindow,
  previousRescheduleCandidateWindow,
  RESCHEDULE_CANDIDATE_RANGE_DAYS,
  rescheduleCandidateWindowFrom,
  rescheduleCandidateStartIso,
  wasRescheduleProposalApplied,
} from '@/lib/appointment-reschedule';
import { clinicLocalToday } from '@/lib/appointment-time';

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
    lifecycleState: 'CONFIRMED',
    createdAt: '2035-01-01T00:00:00Z',
    currentScheduledStartAt: '2035-03-05T10:00:00Z',
    currentScheduledEndAt: '2035-03-05T10:30:00Z',
    currentSchedulingTimezoneName: 'Europe/Madrid',
    currentScheduleRevisionSequence: 2,
    currentVeterinarianClinicAssignmentId: null,
    pendingReschedule: null,
    currentScheduleSource: null,
    cancellationReason: null,
    hasClinicalRecord: false,
    ...overrides,
  };
}

const CLINIC_PROPOSAL = {
  kind: 'confirmedReschedule' as const,
  proposalId: PROPOSAL_ID,
  proposingContext: 'CLINIC' as const,
  proposedStartAt: '2035-03-06T15:00:00Z',
  proposedEndAt: '2035-03-06T15:30:00Z',
  proposedTimezoneName: 'Europe/Madrid',
  reason: 'Vet unavailable',
  currentlyAcceptable: true,
  currentlyFeasible: true,
};

function petAppointment(overrides: Partial<PetAppointment> = {}): PetAppointment {
  return {
    id: 'apt-1',
    clinicId: 'clinic-1',
    requestingUserId: 'user-1',
    reasonForVisit: 'Limping',
    guardianNotes: null,
    lifecycleState: 'CONFIRMED',
    createdAt: '2035-01-01T00:00:00Z',
    currentScheduledStartAt: '2035-03-05T10:00:00Z',
    currentScheduledEndAt: '2035-03-05T10:30:00Z',
    currentSchedulingTimezoneName: 'Europe/Madrid',
    currentVeterinarianClinicAssignmentId: null,
    pendingReschedule: CLINIC_PROPOSAL,
    cancellationReason: null,
    currentScheduleSource: null,
    medicalAccessState: 'ACTIVE',
    ...overrides,
  };
}

const CANDIDATE: RescheduleCandidate = {
  localDate: '2035-03-06',
  localTime: '16:00:00',
  utcOffsetSeconds: 3600,
  endAt: '2035-03-06T15:30:00Z',
};

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const AVAILABLE = { kind: 'available' } as const;
const UNAVAILABLE = { kind: 'unavailable' } as const;
const UNVERIFIED = { kind: 'unknown', messageKey: 'professional.loadError' } as const;

describe('offersRescheduleProposal', () => {
  const capable = clinic(['APPOINTMENT_RESCHEDULE']);

  it('offers a future CONFIRMED Appointment without a pending proposal at a capable Clinic', () => {
    expect(offersRescheduleProposal(capable, scheduleRow(), NOW)).toBe(true);
  });

  it.each<[string, ProfessionalClinic, ClinicScheduleAppointment]>([
    ['without APPOINTMENT_RESCHEDULE', clinic(['APPOINTMENT_CANCEL']), scheduleRow()],
    ['for a REQUESTED Appointment', capable, scheduleRow({ lifecycleState: 'REQUESTED' })],
    [
      'once the confirmed start has been reached',
      capable,
      scheduleRow({ currentScheduledStartAt: '2035-03-01T12:00:00Z' }),
    ],
    ['while a proposal is pending', capable, scheduleRow({ pendingReschedule: CLINIC_PROPOSAL })],
    [
      'once clinical records exist (SPEC-MED-010 BR-9)',
      capable,
      scheduleRow({ hasClinicalRecord: true }),
    ],
  ])('does not offer %s', (_label, professionalClinic, appointment) => {
    expect(offersRescheduleProposal(professionalClinic, appointment, NOW)).toBe(false);
  });
});

describe('offersRescheduleWithdrawal', () => {
  it('offers withdrawing a Clinic proposal to any capable Clinic actor', () => {
    expect(
      offersRescheduleWithdrawal(
        clinic(['APPOINTMENT_RESCHEDULE']),
        scheduleRow({ pendingReschedule: CLINIC_PROPOSAL }),
      ),
    ).toBe(true);
  });

  it('never offers withdrawing a Guardian proposal, nothing, or without the capability', () => {
    const guardianProposal = {
      ...CLINIC_PROPOSAL,
      proposingContext: 'GUARDIAN' as const,
      reason: null,
    };
    expect(
      offersRescheduleWithdrawal(
        clinic(['APPOINTMENT_RESCHEDULE']),
        scheduleRow({ pendingReschedule: guardianProposal }),
      ),
    ).toBe(false);
    expect(offersRescheduleWithdrawal(clinic(['APPOINTMENT_RESCHEDULE']), scheduleRow())).toBe(
      false,
    );
    expect(
      offersRescheduleWithdrawal(
        clinic(['APPOINTMENT_VIEW_SCHEDULE']),
        scheduleRow({ pendingReschedule: CLINIC_PROPOSAL }),
      ),
    ).toBe(false);
  });
});

describe('reviewed-context routing', () => {
  it('carries the reviewed confirmed sequence as a route token', () => {
    expect(professionalRescheduleHref('clinic-1', 'apt-1', 3)).toEqual({
      pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/reschedule',
      params: { clinicId: 'clinic-1', appointmentId: 'apt-1', sequence: '3' },
    });
  });

  it.each<[string | string[] | undefined, number | null]>([
    ['3', 3],
    ['12', 12],
    ['0', null],
    ['-1', null],
    ['1.5', null],
    ['03', null],
    ['abc', null],
    [undefined, null],
    [['3'], null],
  ])('parses the sequence param %p as %p', (value, expected) => {
    expect(parseReviewedSequence(value)).toBe(expected);
  });

  it('matches only the same CONFIRMED revision', () => {
    expect(isReviewedConfirmedContext(scheduleRow(), 2)).toBe(true);
    expect(isReviewedConfirmedContext(scheduleRow({ currentScheduleRevisionSequence: 3 }), 2)).toBe(
      false,
    );
    expect(isReviewedConfirmedContext(scheduleRow({ lifecycleState: 'CANCELLED' }), 2)).toBe(false);
  });
});

describe('clinicRescheduleProposalRequestFor', () => {
  it('binds the request to the reviewed row and trims the reason', () => {
    expect(
      clinicRescheduleProposalRequestFor(
        scheduleRow({ currentScheduleRevisionSequence: 4 }),
        CANDIDATE,
        '  Vet away ',
      ),
    ).toEqual({
      appointmentId: 'apt-1',
      candidate: CANDIDATE,
      reason: 'Vet away',
      expectedConfirmedRevisionSequence: 4,
    });
  });
});

describe('candidate start instant', () => {
  it('derives the start instant from the civil time and offset, never an end', () => {
    expect(rescheduleCandidateStartIso(CANDIDATE)).toBe('2035-03-06T15:00:00.000Z');
    expect(
      rescheduleCandidateStartIso({
        ...CANDIDATE,
        localTime: '00:30:17.5',
        utcOffsetSeconds: 7200,
      }),
    ).toBe('2035-03-05T22:30:17.500Z');
  });
});

describe('offersRescheduleAcceptance', () => {
  it('offers a future Clinic proposal on a future CONFIRMED Appointment', () => {
    expect(offersRescheduleAcceptance(petAppointment(), NOW)).toBe(true);
  });

  it.each<[string, Partial<PetAppointment>]>([
    ['without a proposal', { pendingReschedule: null }],
    [
      'for a Guardian proposal',
      { pendingReschedule: { ...CLINIC_PROPOSAL, proposingContext: 'GUARDIAN', reason: null } },
    ],
    ['once the confirmed start has passed', { currentScheduledStartAt: '2035-02-01T10:00:00Z' }],
    [
      'once the proposed start has passed',
      { pendingReschedule: { ...CLINIC_PROPOSAL, proposedStartAt: '2035-02-01T10:00:00Z' } },
    ],
    ['for a CANCELLED Appointment', { lifecycleState: 'CANCELLED' }],
    [
      'when the Guardian view reports it not currently acceptable',
      { pendingReschedule: { ...CLINIC_PROPOSAL, currentlyAcceptable: false } },
    ],
  ])('does not offer %s', (_label, overrides) => {
    expect(offersRescheduleAcceptance(petAppointment(overrides), NOW)).toBe(false);
  });
});

describe('Guardian current acceptability (SPEC-APT-006 BR-36)', () => {
  const notAcceptable = { ...CLINIC_PROPOSAL, currentlyAcceptable: false };

  it('replaces Accept with the generic notice while the proposal is not currently acceptable', () => {
    const appointment = petAppointment({ pendingReschedule: notAcceptable });
    expect(offersRescheduleAcceptance(appointment, NOW)).toBe(false);
    expect(showsRescheduleNotCurrentlyAcceptable(appointment, NOW)).toBe(true);
  });

  it('shows no notice while the proposal is acceptable', () => {
    expect(showsRescheduleNotCurrentlyAcceptable(petAppointment(), NOW)).toBe(false);
  });

  it.each<[string, Partial<PetAppointment>]>([
    ['without a proposal', { pendingReschedule: null }],
    [
      'for a Guardian proposal (it has its own waiting copy)',
      {
        pendingReschedule: {
          ...notAcceptable,
          proposingContext: 'GUARDIAN',
          reason: null,
        },
      },
    ],
    [
      'once the proposed start has passed',
      { pendingReschedule: { ...notAcceptable, proposedStartAt: '2035-02-01T10:00:00Z' } },
    ],
    [
      'for a CANCELLED Appointment',
      { lifecycleState: 'CANCELLED', pendingReschedule: notAcceptable },
    ],
  ])('shows no notice %s', (_label, overrides) => {
    expect(showsRescheduleNotCurrentlyAcceptable(petAppointment(overrides), NOW)).toBe(false);
  });
});

describe('isPendingRescheduleCurrentlyInfeasible (SPEC-APT-012 BR-44)', () => {
  it('is true only when the Clinic schedule reports the projected proposal infeasible', () => {
    expect(
      isPendingRescheduleCurrentlyInfeasible(
        scheduleRow({ pendingReschedule: { ...CLINIC_PROPOSAL, currentlyFeasible: false } }),
      ),
    ).toBe(true);
    expect(
      isPendingRescheduleCurrentlyInfeasible(scheduleRow({ pendingReschedule: CLINIC_PROPOSAL })),
    ).toBe(false);
    expect(isPendingRescheduleCurrentlyInfeasible(scheduleRow({ pendingReschedule: null }))).toBe(
      false,
    );
  });

  it('never affects whether Withdraw is offered', () => {
    const infeasible = scheduleRow({
      pendingReschedule: { ...CLINIC_PROPOSAL, currentlyFeasible: false },
    });
    expect(offersRescheduleWithdrawal(clinic(['APPOINTMENT_RESCHEDULE']), infeasible)).toBe(true);
  });
});

describe('wasRescheduleProposalApplied', () => {
  it('recognizes the proposal as applied when the confirmed interval is exactly the proposed one', () => {
    expect(
      wasRescheduleProposalApplied(
        CLINIC_PROPOSAL,
        petAppointment({
          pendingReschedule: null,
          currentScheduledStartAt: '2035-03-06T15:00:00+00:00',
          currentScheduledEndAt: '2035-03-06T15:30:00+00:00',
        }),
      ),
    ).toBe(true);
  });

  it.each<[string, Partial<PetAppointment>]>([
    ['the proposal is still pending', {}],
    ['the time did not change', { pendingReschedule: null }],
    [
      'only the start matches',
      {
        pendingReschedule: null,
        currentScheduledStartAt: '2035-03-06T15:00:00Z',
        currentScheduledEndAt: '2035-03-06T15:45:00Z',
      },
    ],
    [
      'the Appointment was cancelled',
      {
        pendingReschedule: null,
        lifecycleState: 'CANCELLED',
        currentScheduledStartAt: '2035-03-06T15:00:00Z',
        currentScheduledEndAt: '2035-03-06T15:30:00Z',
      },
    ],
  ])('does not treat it as applied when %s', (_label, overrides) => {
    expect(wasRescheduleProposalApplied(CLINIC_PROPOSAL, petAppointment(overrides))).toBe(false);
  });
});

describe('candidate windows (SPEC-APT-017 BR-4: 60-day span per read, no horizon)', () => {
  // Inclusive days between two "YYYY-MM-DD" dates, computed independently.
  const daysBetween = (a: string, b: string) =>
    (Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000;

  it('starts the first window on Clinic-local today, not the device date', () => {
    // 23:30 UTC on 15 June is already 16 June in Auckland.
    const instant = new Date('2035-06-15T23:30:00Z');
    expect(clinicLocalToday('Pacific/Auckland', instant)).toBe('2035-06-16');
    expect(initialRescheduleCandidateWindow('Pacific/Auckland', instant)).toEqual({
      startDate: '2035-06-16',
      endDate: '2035-08-14',
    });
  });

  it('keeps every window within the backend span (end − start ≤ 60)', () => {
    const window = rescheduleCandidateWindowFrom('2035-02-01');
    expect(daysBetween(window.startDate, window.endDate)).toBe(RESCHEDULE_CANDIDATE_RANGE_DAYS - 1);
    expect(daysBetween(window.startDate, window.endDate)).toBeLessThanOrEqual(60);
  });

  it('chains consecutive windows with no gap or overlap, across month and leap-year boundaries', () => {
    let window = rescheduleCandidateWindowFrom('2035-12-20');
    for (let i = 0; i < 30; i++) {
      const next = nextRescheduleCandidateWindow(window);
      expect(daysBetween(window.endDate, next.startDate)).toBe(1);
      expect(daysBetween(next.startDate, next.endDate)).toBe(59);
      window = next;
    }
    // 30 windows later (30 × 60 = 1,800 days) — far beyond today + 60 — is still reachable.
    expect(daysBetween('2035-12-20', window.startDate)).toBe(30 * RESCHEDULE_CANDIDATE_RANGE_DAYS);
    expect(window.startDate).toBe('2040-11-23');
  });

  it('reaches any future date: some window contains a date years ahead', () => {
    const target = '2037-07-04';
    let window = rescheduleCandidateWindowFrom('2035-03-01');
    while (window.endDate < target) window = nextRescheduleCandidateWindow(window);
    expect(window.startDate <= target && target <= window.endDate).toBe(true);
  });

  it('goes back one window at a time and never before Clinic-local today', () => {
    const today = '2035-03-01';
    const first = rescheduleCandidateWindowFrom(today);
    const second = nextRescheduleCandidateWindow(first);
    const third = nextRescheduleCandidateWindow(second);

    expect(previousRescheduleCandidateWindow(third, today)).toEqual(second);
    expect(previousRescheduleCandidateWindow(second, today)).toEqual(first);
    expect(previousRescheduleCandidateWindow(first, today)).toBeNull();
    // A window that is no longer aligned (the Clinic-local date moved on) is clamped to today.
    expect(
      previousRescheduleCandidateWindow(rescheduleCandidateWindowFrom('2035-03-20'), today),
    ).toEqual(rescheduleCandidateWindowFrom(today));
  });

  it('keeps the window on screen on refocus unless today moved past it', () => {
    const later = rescheduleCandidateWindowFrom('2035-05-01');
    const instant = new Date('2035-03-01T12:00:00Z');
    expect(currentRescheduleCandidateWindow(later, 'Europe/Madrid', instant)).toEqual(later);
    expect(currentRescheduleCandidateWindow(null, 'Europe/Madrid', instant)).toEqual(
      rescheduleCandidateWindowFrom('2035-03-01'),
    );
    expect(
      currentRescheduleCandidateWindow(
        rescheduleCandidateWindowFrom('2035-02-01'),
        'Europe/Madrid',
        instant,
      ),
    ).toEqual(rescheduleCandidateWindowFrom('2035-03-01'));
  });

  it('is not limited by the Guardian +60-day horizon (SPEC-APT-014 does not apply)', () => {
    const today = '2035-03-01';
    const first = initialRescheduleCandidateWindow('Europe/Madrid', NOW);
    expect(first.startDate).toBe(today);
    const second = nextRescheduleCandidateWindow(first);
    const third = nextRescheduleCandidateWindow(second);
    // The second window already ends past today + 60, and a third still follows.
    expect(daysBetween(today, second.endDate)).toBe(119);
    expect(daysBetween(today, third.startDate)).toBe(120);
  });
});

describe('failure reconciliation', () => {
  it('treats a fresh actionable Clinic proposal as an effectively completed proposal', () => {
    expect(hasActionableClinicProposal(scheduleRow({ pendingReschedule: CLINIC_PROPOSAL }))).toBe(
      true,
    );
    expect(hasActionableClinicProposal(scheduleRow())).toBe(false);
    expect(
      hasActionableClinicProposal(
        scheduleRow({
          pendingReschedule: { ...CLINIC_PROPOSAL, proposingContext: 'GUARDIAN', reason: null },
        }),
      ),
    ).toBe(false);
    expect(hasActionableClinicProposal(null)).toBe(false);
  });

  it('treats a withdrawal as settled only when the fresh read no longer shows that proposal', () => {
    expect(isRescheduleProposalNoLongerPending(PROPOSAL_ID, scheduleRow())).toBe(true);
    expect(
      isRescheduleProposalNoLongerPending(
        PROPOSAL_ID,
        scheduleRow({
          pendingReschedule: {
            ...CLINIC_PROPOSAL,
            proposalId: '44444444-4444-4444-8444-444444444444',
          },
        }),
      ),
    ).toBe(true);
    // Still pending: a genuine failure keeps its mapped error.
    expect(
      isRescheduleProposalNoLongerPending(
        PROPOSAL_ID,
        scheduleRow({ pendingReschedule: CLINIC_PROPOSAL }),
      ),
    ).toBe(false);
    // Unknown when the fresh read found no Appointment.
    expect(isRescheduleProposalNoLongerPending(PROPOSAL_ID, null)).toBe(false);
  });
});

describe('classifyRescheduleAppointment (decided before anything is rendered)', () => {
  const capable = clinic(['APPOINTMENT_RESCHEDULE']);

  it('is proposable for the reviewed future CONFIRMED revision without a pending proposal', () => {
    expect(classifyRescheduleAppointment(capable, scheduleRow(), 2, NOW, AVAILABLE)).toBe(
      'proposable',
    );
  });

  it('distinguishes a missing Appointment from a changed or no-longer-proposable one', () => {
    expect(classifyRescheduleAppointment(capable, null, 2, NOW, AVAILABLE)).toBe(
      'appointmentMissing',
    );
    expect(
      classifyRescheduleAppointment(
        capable,
        scheduleRow({ currentScheduleRevisionSequence: 3 }),
        2,
        NOW,
        AVAILABLE,
      ),
    ).toBe('changed');
    expect(
      classifyRescheduleAppointment(
        capable,
        scheduleRow({ lifecycleState: 'CANCELLED' }),
        2,
        NOW,
        AVAILABLE,
      ),
    ).toBe('changed');
    expect(classifyRescheduleAppointment(capable, scheduleRow(), null, NOW, AVAILABLE)).toBe(
      'changed',
    );
  });

  it('is notOffered — not missing — when the Appointment exists but a proposal is no longer possible', () => {
    // After this actor's own committed proposal (the lost-response case), the
    // row shows a pending Clinic proposal: the submit path leaves instead.
    const withProposal = scheduleRow({ pendingReschedule: CLINIC_PROPOSAL });
    expect(classifyRescheduleAppointment(capable, withProposal, 2, NOW, AVAILABLE)).toBe(
      'notOffered',
    );
    expect(hasActionableClinicProposal(withProposal)).toBe(true);
    expect(
      classifyRescheduleAppointment(
        capable,
        scheduleRow({ currentScheduledStartAt: '2035-02-01T10:00:00Z' }),
        2,
        NOW,
        AVAILABLE,
      ),
    ).toBe('notOffered');
    expect(
      classifyRescheduleAppointment(
        clinic(['APPOINTMENT_VIEW_SCHEDULE']),
        scheduleRow(),
        2,
        NOW,
        AVAILABLE,
      ),
    ).toBe('notOffered');
  });
});

describe('Clinic proposal form readiness (Send proposal enabled only when complete)', () => {
  const slot: RescheduleCandidate = {
    localDate: '2035-03-06',
    localTime: '10:00:00',
    utcOffsetSeconds: 3600,
    endAt: '2035-03-06T09:30:00Z',
  };
  type ReadinessForm = Parameters<typeof canSubmitClinicRescheduleProposal>[0];
  const ready: ReadinessForm = {
    proposable: true,
    candidates: [slot],
    selectedCandidate: slot,
    reason: 'Veterinarian unavailable',
    busy: false,
  };

  it('treats empty and whitespace-only reasons as incomplete, as the backend does', () => {
    expect(isClinicRescheduleReasonComplete('')).toBe(false);
    expect(isClinicRescheduleReasonComplete(' \t\n ')).toBe(false);
    expect(isClinicRescheduleReasonComplete('  Vet away  ')).toBe(true);
  });

  it('is enabled with a server-returned candidate and a reason', () => {
    expect(canSubmitClinicRescheduleProposal(ready)).toBe(true);
  });

  it.each<[string, Partial<ReadinessForm>]>([
    ['no candidate and no reason', { selectedCandidate: null, reason: '' }],
    ['a candidate and an empty reason', { reason: '' }],
    ['a candidate and a whitespace-only reason', { reason: ' \t\n ' }],
    ['a reason and no candidate', { selectedCandidate: null }],
    [
      'a selected time no longer among the loaded candidates',
      { candidates: [{ ...slot, localTime: '11:00:00' }] },
    ],
    ['candidates still loading or failed', { candidates: null }],
    ['submitting, or leaving the screen', { busy: true }],
    ['an Appointment that is no longer proposable', { proposable: false }],
  ])('is disabled with %s', (_label, overrides) => {
    expect(canSubmitClinicRescheduleProposal({ ...ready, ...overrides })).toBe(false);
  });
});

describe('classifyRescheduleAppointment and APPOINTMENT_MANAGEMENT (SPEC-APT-012 BR-61)', () => {
  const capable = clinic(['APPOINTMENT_RESCHEDULE']);

  it('holds back an eligible proposal when the Entitlement is missing or unverified', () => {
    expect(classifyRescheduleAppointment(capable, scheduleRow(), 2, NOW, UNAVAILABLE)).toBe(
      'entitlementUnavailable',
    );
    expect(classifyRescheduleAppointment(capable, scheduleRow(), 2, NOW, UNVERIFIED)).toBe(
      'entitlementUnverified',
    );
  });

  it('says nothing about the Entitlement when the proposal is not possible anyway', () => {
    const withProposal = scheduleRow({ pendingReschedule: CLINIC_PROPOSAL });
    expect(classifyRescheduleAppointment(capable, withProposal, 2, NOW, UNAVAILABLE)).toBe(
      'notOffered',
    );
    expect(
      classifyRescheduleAppointment(
        clinic(['APPOINTMENT_VIEW_SCHEDULE']),
        scheduleRow(),
        2,
        NOW,
        UNAVAILABLE,
      ),
    ).toBe('notOffered');
    expect(
      classifyRescheduleAppointment(
        capable,
        scheduleRow({ currentScheduleRevisionSequence: 3 }),
        2,
        NOW,
        UNAVAILABLE,
      ),
    ).toBe('changed');
  });

  it('never gates withdrawal on the Entitlement', () => {
    const withProposal = scheduleRow({ pendingReschedule: CLINIC_PROPOSAL });
    expect(offersRescheduleWithdrawal(capable, withProposal)).toBe(true);
  });
});

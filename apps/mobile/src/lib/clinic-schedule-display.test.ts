import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import type { AppointmentLifecycleState } from '@/lib/appointment-lifecycle';
import { lifecycleLabelKey } from '@/lib/appointment-lifecycle';
import {
  cancellationReasonToShow,
  clinicCancellationRequestFor,
  clinicScheduleGroupOf,
  completionRequestFor,
  confirmationRequestFor,
  findProfessionalClinic,
  guardianNotesToShow,
  isAppointmentNowCompleted,
  isPostStartClinicCancellation,
  isSameReviewedAppointment,
  noShowRequestFor,
  offersAppointmentCompletion,
  offersAppointmentConfirmation,
  offersAppointmentNoShow,
  offersAppointmentSchedule,
  offersClinicCancellation,
  offersClinicalRecord,
  offersVeterinarianAssignment,
  professionalAppointmentDetailHref,
  professionalClinicWorkflows,
  resolveClinicScheduleAvailability,
  showsPendingReschedule,
} from '@/lib/clinic-schedule-display';
import { professionalClinicLabel } from '@/lib/professional-clinics-display';

function clinic(clinicId: string, overrides: Partial<ProfessionalClinic> = {}): ProfessionalClinic {
  return {
    clinicId,
    clinicDisplayName: `Clinic ${clinicId}`,
    organizationId: 'o-1',
    organizationDisplayName: 'Animalia',
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
    unknownCapabilities: [],
    ...overrides,
  };
}

function appointment(
  id: string,
  lifecycleState: AppointmentLifecycleState,
  startAt: string,
  overrides: Partial<ClinicScheduleAppointment> = {},
): ClinicScheduleAppointment {
  return {
    id,
    petId: 'p-1',
    petName: 'Luna',
    requestingUserId: 'u-1',
    requesterDisplayName: 'María López',
    reasonForVisit: 'Revisión',
    guardianNotes: null,
    lifecycleState,
    createdAt: '2026-01-01T00:00:00Z',
    currentScheduledStartAt: startAt,
    currentScheduledEndAt: new Date(Date.parse(startAt) + 30 * 60_000).toISOString(),
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

describe('offersAppointmentSchedule / professionalClinicWorkflows', () => {
  it('offers the Appointment schedule only for a known APPOINTMENT_VIEW_SCHEDULE', () => {
    const scheduling = clinic('c-1');
    expect(offersAppointmentSchedule(scheduling)).toBe(true);
    expect(professionalClinicWorkflows(scheduling)).toEqual(['APPOINTMENT_SCHEDULE']);
  });

  it('offers nothing without that capability', () => {
    const administration = clinic('c-1', { capabilities: ['CLINIC_MANAGE_SERVICES'] });
    expect(offersAppointmentSchedule(administration)).toBe(false);
    expect(professionalClinicWorkflows(administration)).toEqual([]);
  });

  it('offers nothing for unknown-only capabilities, even an unknown look-alike identifier', () => {
    const future = clinic('c-1', {
      capabilities: [],
      unknownCapabilities: ['APPOINTMENT_VIEW_SCHEDULE_V2', 'FUTURE'],
    });
    expect(professionalClinicWorkflows(future)).toEqual([]);
  });

  it('offers Appointment hours only for a known APPOINTMENT_MANAGE_AVAILABILITY', () => {
    const reception = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_MANAGE_AVAILABILITY'],
    });
    expect(professionalClinicWorkflows(reception)).toEqual([
      'APPOINTMENT_SCHEDULE',
      'APPOINTMENT_HOURS',
    ]);
    // A Veterinarian's Clinic capabilities never include it.
    const veterinarian = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE', 'CLINICAL_CARE'],
    });
    expect(professionalClinicWorkflows(veterinarian)).toEqual(['APPOINTMENT_SCHEDULE']);
    const lookAlike = clinic('c-1', {
      capabilities: [],
      unknownCapabilities: ['APPOINTMENT_MANAGE_AVAILABILITY_V2'],
    });
    expect(professionalClinicWorkflows(lookAlike)).toEqual([]);
  });

  it('offers Clinic settings after the existing workflows to Owners and Administrators', () => {
    // Owner, Organization Administrator, and a Clinic Administrator at its own Clinic.
    const administrator = clinic('c-1', {
      capabilities: [
        'APPOINTMENT_MANAGE_AVAILABILITY',
        'APPOINTMENT_VIEW_SCHEDULE',
        'CLINIC_MANAGE_LOCATION',
        'CLINIC_MANAGE_OPENING_HOURS',
        'CLINIC_MANAGE_PUBLICATION',
        'CLINIC_MANAGE_PUBLIC_PROFILE',
        'CLINIC_MANAGE_SERVICES',
      ],
    });
    expect(professionalClinicWorkflows(administrator)).toEqual([
      'APPOINTMENT_SCHEDULE',
      'APPOINTMENT_HOURS',
      'CLINIC_SETTINGS',
    ]);
    expect(
      professionalClinicWorkflows(clinic('c-1', { capabilities: ['CLINIC_MANAGE_LOCATION'] })),
    ).toEqual(['CLINIC_SETTINGS']);
  });

  it('never offers Clinic settings to a Receptionist or a Veterinarian, leaving their workflows unchanged', () => {
    const receptionist = clinic('c-1', {
      capabilities: [
        'APPOINTMENT_VIEW_SCHEDULE',
        'APPOINTMENT_CONFIRM',
        'APPOINTMENT_MANAGE_AVAILABILITY',
      ],
    });
    expect(professionalClinicWorkflows(receptionist)).toEqual([
      'APPOINTMENT_SCHEDULE',
      'APPOINTMENT_HOURS',
    ]);
    const veterinarian = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE', 'CLINICAL_CARE'],
    });
    expect(professionalClinicWorkflows(veterinarian)).toEqual(['APPOINTMENT_SCHEDULE']);
    const servicesOnly = clinic('c-1', { capabilities: ['CLINIC_MANAGE_SERVICES'] });
    expect(professionalClinicWorkflows(servicesOnly)).toEqual([]);
  });
});

describe('offersAppointmentConfirmation (detail-screen Confirm)', () => {
  // Deterministic reference instant; START is one hour later.
  const NOW = new Date('2035-02-06T08:00:00Z');
  const START = '2035-02-06T09:00:00Z';
  const confirmer = clinic('c-1', {
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CONFIRM'],
  });

  it('offers Confirm on a future REQUESTED Appointment when the known capabilities hold APPOINTMENT_CONFIRM', () => {
    expect(
      offersAppointmentConfirmation(confirmer, appointment('a-1', 'REQUESTED', START), NOW),
    ).toBe(true);
  });

  it.each<[string, string]>([
    ['start === now', '2035-02-06T08:00:00Z'],
    ['start < now', '2035-02-06T07:59:59Z'],
  ])(
    'hides Confirm on a REQUESTED Appointment whose %s (advisory, SPEC-APT-002 BR-19)',
    (_l, start) => {
      expect(
        offersAppointmentConfirmation(confirmer, appointment('a-1', 'REQUESTED', start), NOW),
      ).toBe(false);
    },
  );

  it('hides Confirm without APPOINTMENT_CONFIRM (e.g. a schedule-viewing Veterinarian)', () => {
    const viewer = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE', 'CLINICAL_CARE'],
    });
    expect(offersAppointmentConfirmation(viewer, appointment('a-1', 'REQUESTED', START), NOW)).toBe(
      false,
    );
  });

  it('never lets an unknown capability enable Confirm', () => {
    const unknownOnly = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
      unknownCapabilities: ['APPOINTMENT_CONFIRM_V2', 'FUTURE'],
    });
    expect(
      offersAppointmentConfirmation(unknownOnly, appointment('a-1', 'REQUESTED', START), NOW),
    ).toBe(false);
  });

  it.each<AppointmentLifecycleState>(['CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'])(
    'hides Confirm on a %s Appointment regardless of capability or time',
    (state) => {
      expect(offersAppointmentConfirmation(confirmer, appointment('a-1', state, START), NOW)).toBe(
        false,
      );
    },
  );
});

describe('confirmationRequestFor (stale-safe token)', () => {
  it('sends the displayed row’s own id and revision sequence', () => {
    expect(
      confirmationRequestFor(
        appointment('a-1', 'REQUESTED', '2035-02-06T09:00:00Z', {
          currentScheduleRevisionSequence: 3,
        }),
      ),
    ).toEqual({ appointmentId: 'a-1', expectedRequestedRevisionSequence: 3 });
  });

  it('never substitutes a newer sequence for the same Appointment from another read', () => {
    const displayed = appointment('a-1', 'REQUESTED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 1,
    });
    // A later read of the same Appointment after a Guardian reschedule.
    const newer = appointment('a-1', 'REQUESTED', '2035-02-06T11:00:00Z', {
      currentScheduleRevisionSequence: 2,
    });

    expect(confirmationRequestFor(displayed).expectedRequestedRevisionSequence).toBe(1);
    expect(confirmationRequestFor(newer).expectedRequestedRevisionSequence).toBe(2);
  });

  it('does not derive the token from the displayed times', () => {
    const sameTimes = { currentScheduledEndAt: '2035-02-06T09:30:00Z' };
    const first = appointment('a-1', 'REQUESTED', '2035-02-06T09:00:00Z', {
      ...sameTimes,
      currentScheduleRevisionSequence: 1,
    });
    const second = appointment('a-1', 'REQUESTED', '2035-02-06T09:00:00Z', {
      ...sameTimes,
      currentScheduleRevisionSequence: 2,
    });

    expect(confirmationRequestFor(first)).not.toEqual(confirmationRequestFor(second));
  });
});

describe('findProfessionalClinic', () => {
  it('finds a listed Clinic by id, including one with unknown-only capabilities', () => {
    const future = clinic('c-2', { capabilities: [], unknownCapabilities: ['FUTURE'] });
    expect(findProfessionalClinic({ clinics: [clinic('c-1'), future] }, 'c-2')).toBe(future);
  });

  it('returns null for a Clinic that is not (or no longer) listed', () => {
    expect(findProfessionalClinic({ clinics: [clinic('c-1')] }, 'c-9')).toBeNull();
  });
});

describe('resolveClinicScheduleAvailability', () => {
  it('is available for a listed Clinic offering the schedule', () => {
    const scheduling = clinic('c-1');
    expect(resolveClinicScheduleAvailability({ clinics: [scheduling] }, 'c-1')).toEqual({
      kind: 'available',
      clinic: scheduling,
    });
  });

  it('is clinicUnavailable when the Clinic is not listed', () => {
    expect(resolveClinicScheduleAvailability({ clinics: [] }, 'c-1')).toEqual({
      kind: 'clinicUnavailable',
    });
  });

  it('is scheduleUnavailable when the listed Clinic offers no known schedule capability', () => {
    const future = clinic('c-1', { capabilities: [], unknownCapabilities: ['FUTURE'] });
    expect(resolveClinicScheduleAvailability({ clinics: [future] }, 'c-1')).toEqual({
      kind: 'scheduleUnavailable',
      clinic: future,
    });
  });
});

describe('professionalClinicLabel (reused for the Clinic and schedule screens)', () => {
  it('falls back to the localized unnamed-Clinic label', () => {
    expect(professionalClinicLabel(clinic('c-1', { clinicDisplayName: null }), 'Sin nombre')).toBe(
      'Sin nombre',
    );
  });
});

describe('offersAppointmentNoShow (detail-screen Mark as no-show)', () => {
  // Deterministic reference instant.
  const NOW = new Date('2035-02-06T09:00:00Z');
  const marker = clinic('c-1', {
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_MARK_NO_SHOW'],
  });

  it.each<[string, string]>([
    ['at the confirmed start', '2035-02-06T09:00:00Z'],
    ['between start and end', '2035-02-06T08:45:00Z'],
    ['after the end', '2035-02-05T09:00:00Z'],
  ])('offers it on a CONFIRMED Appointment %s with APPOINTMENT_MARK_NO_SHOW', (_label, start) => {
    expect(offersAppointmentNoShow(marker, appointment('a-1', 'CONFIRMED', start), NOW)).toBe(true);
  });

  it('hides it before the confirmed start (advisory, SPEC-APT-010 BR-44)', () => {
    expect(
      offersAppointmentNoShow(marker, appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:01Z'), NOW),
    ).toBe(false);
  });

  it('hides it on an unparseable start', () => {
    const unparseable = {
      ...appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z'),
      currentScheduledStartAt: 'not-a-date',
    };
    expect(offersAppointmentNoShow(marker, unparseable, NOW)).toBe(false);
  });

  it('hides it without APPOINTMENT_MARK_NO_SHOW (e.g. a Veterinarian with schedule and care capabilities)', () => {
    const viewer = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE', 'APPOINTMENT_CONFIRM'],
    });
    expect(
      offersAppointmentNoShow(viewer, appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z'), NOW),
    ).toBe(false);
  });

  it('never lets an unknown capability enable it', () => {
    const unknownOnly = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
      unknownCapabilities: ['APPOINTMENT_MARK_NO_SHOW_V2'],
    });
    expect(
      offersAppointmentNoShow(
        unknownOnly,
        appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z'),
        NOW,
      ),
    ).toBe(false);
  });

  it.each<AppointmentLifecycleState>(['REQUESTED', 'CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'])(
    'hides it on a past %s Appointment regardless of capability',
    (state) => {
      expect(
        offersAppointmentNoShow(marker, appointment('a-1', state, '2035-02-06T08:00:00Z'), NOW),
      ).toBe(false);
    },
  );
});

describe('noShowRequestFor (stale-safe token)', () => {
  it('sends the displayed row’s own id and confirmed revision sequence', () => {
    expect(
      noShowRequestFor(
        appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
          currentScheduleRevisionSequence: 4,
        }),
      ),
    ).toEqual({ appointmentId: 'a-1', expectedConfirmedRevisionSequence: 4 });
  });

  it('never substitutes a newer sequence for the same Appointment from another read', () => {
    const displayed = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 2,
    });
    // A later read of the same Appointment after an accepted confirmed reschedule.
    const newer = appointment('a-1', 'CONFIRMED', '2035-02-06T07:00:00Z', {
      currentScheduleRevisionSequence: 3,
    });

    expect(noShowRequestFor(displayed).expectedConfirmedRevisionSequence).toBe(2);
    expect(noShowRequestFor(newer).expectedConfirmedRevisionSequence).toBe(3);
  });

  it('does not derive the token from the displayed times', () => {
    const first = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 2,
    });
    const second = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 3,
    });

    expect(noShowRequestFor(first)).not.toEqual(noShowRequestFor(second));
  });
});

describe('offersAppointmentCompletion (detail-screen Mark as completed)', () => {
  // Deterministic reference instant.
  const NOW = new Date('2035-02-06T09:00:00Z');
  const completer = clinic('c-1', {
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE'],
  });

  it.each<[string, string]>([
    ['at the confirmed start', '2035-02-06T09:00:00Z'],
    ['between start and end', '2035-02-06T08:45:00Z'],
    ['after the end', '2035-02-05T09:00:00Z'],
  ])('offers it on a CONFIRMED Appointment %s with APPOINTMENT_COMPLETE', (_label, start) => {
    expect(
      offersAppointmentCompletion(completer, appointment('a-1', 'CONFIRMED', start), NOW),
    ).toBe(true);
  });

  it('hides it before the confirmed start (advisory, SPEC-APT-009 BR-7)', () => {
    expect(
      offersAppointmentCompletion(
        completer,
        appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:01Z'),
        NOW,
      ),
    ).toBe(false);
  });

  it('hides it on an unparseable start', () => {
    const unparseable = {
      ...appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z'),
      currentScheduledStartAt: 'not-a-date',
    };
    expect(offersAppointmentCompletion(completer, unparseable, NOW)).toBe(false);
  });

  it('hides it without APPOINTMENT_COMPLETE, even with APPOINTMENT_MARK_NO_SHOW', () => {
    const noShowOnly = clinic('c-1', {
      capabilities: [
        'APPOINTMENT_VIEW_SCHEDULE',
        'APPOINTMENT_MARK_NO_SHOW',
        'APPOINTMENT_CONFIRM',
      ],
    });
    expect(
      offersAppointmentCompletion(
        noShowOnly,
        appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z'),
        NOW,
      ),
    ).toBe(false);
  });

  it('offers it to a Veterinarian whose capabilities hold APPOINTMENT_COMPLETE but not no-show', () => {
    const veterinarian = clinic('c-1', {
      capabilities: [
        'APPOINTMENT_VIEW_SCHEDULE',
        'APPOINTMENT_COMPLETE',
        'CLINICAL_CARE',
        'CLINICAL_DOCUMENTATION',
      ],
    });
    const item = appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z');
    expect(offersAppointmentCompletion(veterinarian, item, NOW)).toBe(true);
    expect(offersAppointmentNoShow(veterinarian, item, NOW)).toBe(false);
  });

  it('never lets an unknown capability enable it', () => {
    const unknownOnly = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
      unknownCapabilities: ['APPOINTMENT_COMPLETE_V2'],
    });
    expect(
      offersAppointmentCompletion(
        unknownOnly,
        appointment('a-1', 'CONFIRMED', '2035-02-06T08:00:00Z'),
        NOW,
      ),
    ).toBe(false);
  });

  it('does not depend on a Veterinarian Assignment (SPEC-APT-009 BR-2)', () => {
    const start = '2035-02-06T08:00:00Z';
    expect(
      offersAppointmentCompletion(
        completer,
        appointment('a-1', 'CONFIRMED', start, { currentVeterinarianClinicAssignmentId: null }),
        NOW,
      ),
    ).toBe(true);
    expect(
      offersAppointmentCompletion(
        completer,
        appointment('a-1', 'CONFIRMED', start, {
          currentVeterinarianClinicAssignmentId: 'vca-1',
        }),
        NOW,
      ),
    ).toBe(true);
  });

  it.each<AppointmentLifecycleState>(['REQUESTED', 'CANCELLED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'])(
    'hides it on a past %s Appointment regardless of capability',
    (state) => {
      expect(
        offersAppointmentCompletion(
          completer,
          appointment('a-1', state, '2035-02-06T08:00:00Z'),
          NOW,
        ),
      ).toBe(false);
    },
  );
});

describe('completionRequestFor (stale-safe token)', () => {
  it('sends the displayed row id and confirmed revision sequence', () => {
    expect(
      completionRequestFor(
        appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
          currentScheduleRevisionSequence: 4,
        }),
      ),
    ).toEqual({ appointmentId: 'a-1', expectedConfirmedRevisionSequence: 4 });
  });

  it('never substitutes a newer sequence or derives it from the displayed times', () => {
    const displayed = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 2,
    });
    // A later read of the same Appointment after an accepted confirmed reschedule
    // to the very same time.
    const newer = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 3,
    });

    expect(completionRequestFor(displayed).expectedConfirmedRevisionSequence).toBe(2);
    expect(completionRequestFor(newer).expectedConfirmedRevisionSequence).toBe(3);
  });
});

describe('isAppointmentNowCompleted (completed-state reconciliation)', () => {
  const start = '2035-02-06T08:00:00Z';

  it('is true when the authoritative re-read shows the same Appointment COMPLETED', () => {
    expect(isAppointmentNowCompleted('a-1', appointment('a-1', 'COMPLETED', start))).toBe(true);
  });

  it.each<AppointmentLifecycleState>(['CONFIRMED', 'NO_SHOW', 'CANCELLED'])(
    'is false when the re-read shows %s (a stale rejection or another outcome)',
    (state) => {
      expect(isAppointmentNowCompleted('a-1', appointment('a-1', state, start))).toBe(false);
    },
  );

  it('is false without a re-read Appointment or for another Appointment', () => {
    expect(isAppointmentNowCompleted('a-1', null)).toBe(false);
    expect(isAppointmentNowCompleted('a-1', appointment('a-2', 'COMPLETED', start))).toBe(false);
  });
});

describe('lifecycle display mapping (shared Guardian vocabulary)', () => {
  it.each<[AppointmentLifecycleState, string]>([
    ['REQUESTED', 'appointments.lifecycleRequested'],
    ['CONFIRMED', 'appointments.lifecycleConfirmed'],
    ['CANCELLED', 'appointments.lifecycleCancelled'],
    ['COMPLETED', 'appointments.lifecycleCompleted'],
    ['NO_SHOW', 'appointments.lifecycleNoShow'],
  ])('maps %s to its existing localized label key', (state, key) => {
    expect(lifecycleLabelKey(state)).toBe(key);
  });
});

describe('showsPendingReschedule', () => {
  it('is false without a pending proposal', () => {
    expect(showsPendingReschedule(appointment('a', 'CONFIRMED', '2035-01-01T09:00:00Z'))).toBe(
      false,
    );
  });

  it('is true with an actionable pending proposal', () => {
    expect(
      showsPendingReschedule(
        appointment('a', 'CONFIRMED', '2035-01-01T09:00:00Z', {
          pendingReschedule: {
            kind: 'confirmedReschedule',
            proposalId: 'r-1',
            proposingContext: 'GUARDIAN',
            proposedStartAt: '2035-01-02T09:00:00Z',
            proposedEndAt: '2035-01-02T09:30:00Z',
            proposedTimezoneName: 'Europe/Madrid',
            reason: null,
            currentlyFeasible: true,
          },
        }),
      ),
    ).toBe(true);
  });
});

describe('offersClinicCancellation (detail-screen Cancel; Clinic keeps post-start cancellation, SPEC-APT-003 BR-31)', () => {
  // Deterministic reference instant; FUTURE is one hour later.
  const NOW = new Date('2035-02-06T08:00:00Z');
  const FUTURE = '2035-02-06T09:00:00Z';
  const canceller = clinic('c-1', {
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CANCEL'],
  });

  it.each<AppointmentLifecycleState>(['REQUESTED', 'CONFIRMED'])(
    'offers Cancel on a future %s Appointment with APPOINTMENT_CANCEL',
    (state) => {
      expect(offersClinicCancellation(canceller, appointment('a-1', state, FUTURE), NOW)).toBe(
        true,
      );
    },
  );

  it.each<[string, AppointmentLifecycleState, string]>([
    ['a past REQUESTED awaiting EXPIRED materialization', 'REQUESTED', '2035-02-06T07:00:00Z'],
    ['a REQUESTED exactly at its start', 'REQUESTED', '2035-02-06T08:00:00Z'],
  ])('hides Cancel on %s', (_label, state, start) => {
    expect(offersClinicCancellation(canceller, appointment('a-1', state, start), NOW)).toBe(false);
  });

  it.each<[string, string]>([
    ['exactly at its start', '2035-02-06T08:00:00Z'],
    ['after its start (Needs resolution)', '2035-02-05T09:00:00Z'],
  ])('still offers Clinic Cancel on a CONFIRMED Appointment %s', (_label, start) => {
    expect(offersClinicCancellation(canceller, appointment('a-1', 'CONFIRMED', start), NOW)).toBe(
      true,
    );
  });

  it.each<AppointmentLifecycleState>(['COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'])(
    'hides Cancel on a %s Appointment even with a future time',
    (state) => {
      expect(offersClinicCancellation(canceller, appointment('a-1', state, FUTURE), NOW)).toBe(
        false,
      );
    },
  );

  it('hides Cancel without APPOINTMENT_CANCEL (e.g. a schedule-viewing Veterinarian)', () => {
    const viewer = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE', 'APPOINTMENT_CONFIRM'],
    });
    expect(offersClinicCancellation(viewer, appointment('a-1', 'CONFIRMED', FUTURE), NOW)).toBe(
      false,
    );
  });

  it('never lets an unknown capability enable Cancel', () => {
    const unknownOnly = clinic('c-1', {
      capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
      unknownCapabilities: ['APPOINTMENT_CANCEL_V2', 'FUTURE'],
    });
    expect(
      offersClinicCancellation(unknownOnly, appointment('a-1', 'REQUESTED', FUTURE), NOW),
    ).toBe(false);
  });

  it('hides Cancel on an unparseable start', () => {
    const unparseable = {
      ...appointment('a-1', 'CONFIRMED', FUTURE),
      currentScheduledStartAt: 'not-a-date',
    };
    expect(offersClinicCancellation(canceller, unparseable, NOW)).toBe(false);
  });

  it('hides post-start Clinic Cancel without APPOINTMENT_CANCEL', () => {
    const resolver = clinic('c-1', {
      capabilities: [
        'APPOINTMENT_VIEW_SCHEDULE',
        'APPOINTMENT_COMPLETE',
        'APPOINTMENT_MARK_NO_SHOW',
      ],
    });
    expect(
      offersClinicCancellation(
        resolver,
        appointment('a-1', 'CONFIRMED', '2035-02-05T09:00:00Z'),
        NOW,
      ),
    ).toBe(false);
  });
});

describe('isPostStartClinicCancellation (secondary presentation)', () => {
  const NOW = new Date('2035-02-06T08:00:00Z');

  it.each<[string, AppointmentLifecycleState, string, boolean]>([
    ['a future CONFIRMED', 'CONFIRMED', '2035-02-06T09:00:00Z', false],
    ['a CONFIRMED exactly at its start', 'CONFIRMED', '2035-02-06T08:00:00Z', true],
    ['a past CONFIRMED', 'CONFIRMED', '2035-02-05T09:00:00Z', true],
    ['a future REQUESTED', 'REQUESTED', '2035-02-06T09:00:00Z', false],
    ['a past REQUESTED', 'REQUESTED', '2035-02-05T09:00:00Z', false],
  ])('%s -> %s', (_label, state, start, expected) => {
    expect(isPostStartClinicCancellation(appointment('a-1', state, start), NOW)).toBe(expected);
  });

  it('is labelled as a clinic-side cancellation and explains completion and no-show', () => {
    expect(es.professionalCancellation.postStartAction).toBe(
      'Registrar cancelación por la clínica',
    );
    expect(en.professionalCancellation.postStartAction).toBe('Record a clinic cancellation');
    expect(es.professionalCancellation.postStartHint).toContain('Marcar como completada');
    expect(es.professionalCancellation.postStartHint).toContain('Marcar como no presentado');
    expect(en.professionalCancellation.postStartHint).toContain('completed');
    expect(en.professionalCancellation.postStartHint).toContain('no-show');
  });
});

describe('clinicCancellationRequestFor (stale-safe token)', () => {
  it('sends the reviewed row’s own id and revision sequence with the trimmed reason', () => {
    expect(
      clinicCancellationRequestFor(
        appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
          currentScheduleRevisionSequence: 4,
        }),
        '  Clinic closed  ',
      ),
    ).toEqual({
      appointmentId: 'a-1',
      reason: 'Clinic closed',
      expectedScheduleRevisionSequence: 4,
    });
  });

  it('never substitutes a newer sequence for the same Appointment from another read', () => {
    const reviewed = appointment('a-1', 'REQUESTED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 1,
    });
    // A later read of the same Appointment after a Guardian requested-time reschedule.
    const newer = appointment('a-1', 'REQUESTED', '2035-02-06T11:00:00Z', {
      currentScheduleRevisionSequence: 2,
    });

    expect(clinicCancellationRequestFor(reviewed, 'x').expectedScheduleRevisionSequence).toBe(1);
    expect(clinicCancellationRequestFor(newer, 'x').expectedScheduleRevisionSequence).toBe(2);
  });

  it('produces a different request for the same displayed times with a different sequence', () => {
    const first = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 2,
    });
    const second = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
      currentScheduleRevisionSequence: 3,
    });

    expect(clinicCancellationRequestFor(first, 'x')).not.toEqual(
      clinicCancellationRequestFor(second, 'x'),
    );
  });
});

describe('isSameReviewedAppointment', () => {
  const reviewed = appointment('a-1', 'CONFIRMED', '2035-02-06T09:00:00Z', {
    currentScheduleRevisionSequence: 2,
  });

  it('is true for an identical re-read', () => {
    expect(isSameReviewedAppointment(reviewed, { ...reviewed })).toBe(true);
  });

  it.each<[string, Partial<ClinicScheduleAppointment>]>([
    ['a newer revision with the same times', { currentScheduleRevisionSequence: 3 }],
    ['a changed lifecycle', { lifecycleState: 'CANCELLED' }],
    ['a different end only', { currentScheduledEndAt: '2035-02-06T09:45:00.000Z' }],
    ['a different timezone only', { currentSchedulingTimezoneName: 'Atlantic/Canary' }],
    ['another Appointment', { id: 'a-2' }],
  ])('is false for %s', (_label, change) => {
    expect(isSameReviewedAppointment(reviewed, { ...reviewed, ...change })).toBe(false);
  });
});

describe('clinicScheduleGroupOf (detail header)', () => {
  const NOW = new Date('2035-01-03T12:00:00Z');

  it.each<[string, AppointmentLifecycleState, string, string]>([
    ['future REQUESTED', 'REQUESTED', '2035-01-04T09:00:00Z', 'upcoming'],
    ['past REQUESTED awaiting expiry', 'REQUESTED', '2035-01-01T09:00:00Z', 'upcoming'],
    ['future CONFIRMED', 'CONFIRMED', '2035-01-04T09:00:00Z', 'upcoming'],
    ['CONFIRMED at its start', 'CONFIRMED', '2035-01-03T12:00:00Z', 'needsResolution'],
    ['past CONFIRMED', 'CONFIRMED', '2035-01-02T09:00:00Z', 'needsResolution'],
    ['COMPLETED', 'COMPLETED', '2035-01-04T09:00:00Z', 'historical'],
    ['CANCELLED', 'CANCELLED', '2035-01-04T09:00:00Z', 'historical'],
    ['NO_SHOW', 'NO_SHOW', '2035-01-02T09:00:00Z', 'historical'],
    ['EXPIRED', 'EXPIRED', '2035-01-02T09:00:00Z', 'historical'],
  ])('places a %s Appointment in %s', (_label, state, start, group) => {
    expect(clinicScheduleGroupOf(appointment('a-1', state, start), NOW)).toBe(group);
  });
});

describe('professionalAppointmentDetailHref (agenda row navigation)', () => {
  it('opens the professional Appointment detail of exactly that Clinic and Appointment', () => {
    expect(professionalAppointmentDetailHref('c-1', 'a-7')).toEqual({
      pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]',
      params: { clinicId: 'c-1', appointmentId: 'a-7' },
    });
  });

  it('carries only the two ids', () => {
    expect(Object.keys(professionalAppointmentDetailHref('c-1', 'a-7').params).sort()).toEqual([
      'appointmentId',
      'clinicId',
    ]);
  });
});

describe('detail-screen action set by situation', () => {
  const NOW = new Date('2035-02-06T08:00:00Z');
  const manager = clinic('c-1', {
    capabilities: [
      'APPOINTMENT_VIEW_SCHEDULE',
      'APPOINTMENT_CONFIRM',
      'APPOINTMENT_CANCEL',
      'APPOINTMENT_COMPLETE',
      'APPOINTMENT_MARK_NO_SHOW',
    ],
  });
  const actionsFor = (item: ClinicScheduleAppointment) =>
    [
      offersAppointmentConfirmation(manager, item, NOW) ? 'confirm' : null,
      offersAppointmentCompletion(manager, item, NOW) ? 'complete' : null,
      offersAppointmentNoShow(manager, item, NOW) ? 'noShow' : null,
      offersClinicCancellation(manager, item, NOW) ? 'cancel' : null,
    ].filter(Boolean);

  it.each<[string, AppointmentLifecycleState, string, string[]]>([
    ['future REQUESTED', 'REQUESTED', '2035-02-06T09:00:00Z', ['confirm', 'cancel']],
    ['future CONFIRMED', 'CONFIRMED', '2035-02-06T09:00:00Z', ['cancel']],
    [
      'past CONFIRMED (Needs resolution)',
      'CONFIRMED',
      '2035-02-06T07:00:00Z',
      ['complete', 'noShow', 'cancel'],
    ],
    ['past REQUESTED awaiting expiry', 'REQUESTED', '2035-02-06T07:00:00Z', []],
    ['COMPLETED', 'COMPLETED', '2035-02-06T07:00:00Z', []],
    ['CANCELLED', 'CANCELLED', '2035-02-06T09:00:00Z', []],
    ['NO_SHOW', 'NO_SHOW', '2035-02-06T07:00:00Z', []],
    ['EXPIRED', 'EXPIRED', '2035-02-06T07:00:00Z', []],
  ])('a %s Appointment offers %j', (_label, state, start, expected) => {
    expect(actionsFor(appointment('a-1', state, start))).toEqual(expected);
  });
});

describe('guardianNotesToShow (professional Appointment detail)', () => {
  it('is null when the pet guardian left no notes, so no empty section is shown', () => {
    expect(guardianNotesToShow(appointment('a', 'REQUESTED', '2035-01-01T09:00:00Z'))).toBeNull();
  });

  it('is null for blank notes', () => {
    expect(
      guardianNotesToShow(
        appointment('a', 'REQUESTED', '2035-01-01T09:00:00Z', { guardianNotes: ' \n ' }),
      ),
    ).toBeNull();
  });

  it('returns multiline notes exactly as written', () => {
    const notes = '  Es tímida.\nPrefiere entrar en transportín.  ';
    expect(
      guardianNotesToShow(
        appointment('a', 'REQUESTED', '2035-01-01T09:00:00Z', { guardianNotes: notes }),
      ),
    ).toBe(notes);
  });

  it.each<AppointmentLifecycleState>([
    'REQUESTED',
    'CONFIRMED',
    'COMPLETED',
    'CANCELLED',
    'NO_SHOW',
    'EXPIRED',
  ])('stays visible as request context for a %s Appointment', (state) => {
    expect(
      guardianNotesToShow(
        appointment('a', state, '2035-01-01T09:00:00Z', { guardianNotes: 'Es tímida' }),
      ),
    ).toBe('Es tímida');
  });
});

describe('cancellationReasonToShow (professional Appointment detail)', () => {
  it('shows the reason the Clinic recorded for a cancellation after the start, multiline included', () => {
    const reason = 'El veterinario se puso enfermo.\nAvisamos por teléfono.';
    expect(
      cancellationReasonToShow(
        appointment('a', 'CANCELLED', '2035-01-01T09:00:00Z', { cancellationReason: reason }),
      ),
    ).toBe(reason);
  });

  it('shows nothing for a cancellation recorded without a reason', () => {
    expect(
      cancellationReasonToShow(appointment('a', 'CANCELLED', '2035-01-01T09:00:00Z')),
    ).toBeNull();
  });

  it.each<AppointmentLifecycleState>(['REQUESTED', 'CONFIRMED', 'COMPLETED', 'NO_SHOW', 'EXPIRED'])(
    'never shows a reason on a %s Appointment',
    (state) => {
      expect(
        cancellationReasonToShow(
          appointment('a', state, '2035-01-01T09:00:00Z', { cancellationReason: 'Some text' }),
        ),
      ).toBeNull();
    },
  );

  it('is labelled with the shared cancellation-reason wording', () => {
    expect(es.professionalAppointment.cancellationReasonLabel).toBe(
      es.appointments.cancellationReasonLabel,
    );
    expect(en.professionalAppointment.cancellationReasonLabel).toBe(
      en.appointments.cancellationReasonLabel,
    );
  });
});

describe('Clinical documentation action suppression (SPEC-MED-010 BR-9)', () => {
  const now = new Date('2035-06-01T12:00:00Z');
  const everyAction = clinic('c-1', {
    capabilities: [
      'APPOINTMENT_VIEW_SCHEDULE',
      'APPOINTMENT_CANCEL',
      'APPOINTMENT_COMPLETE',
      'APPOINTMENT_MARK_NO_SHOW',
      'APPOINTMENT_RESCHEDULE',
    ],
  });
  const pastStart = '2035-06-01T10:00:00Z';
  const futureStart = '2035-06-02T10:00:00Z';

  it('keeps every action unchanged without clinical records', () => {
    const past = appointment('a', 'CONFIRMED', pastStart);
    const future = appointment('b', 'CONFIRMED', futureStart);
    expect(offersClinicCancellation(everyAction, past, now)).toBe(true);
    expect(offersAppointmentNoShow(everyAction, past, now)).toBe(true);
    expect(offersAppointmentCompletion(everyAction, past, now)).toBe(true);
    expect(offersClinicCancellation(everyAction, future, now)).toBe(true);
  });

  it('hides Cancel and No-show once records exist, and keeps Complete', () => {
    const past = appointment('a', 'CONFIRMED', pastStart, { hasClinicalRecord: true });
    expect(offersClinicCancellation(everyAction, past, now)).toBe(false);
    expect(offersAppointmentNoShow(everyAction, past, now)).toBe(false);
    expect(offersAppointmentCompletion(everyAction, past, now)).toBe(true);
  });

  it('hides Cancel for a visit documented before the confirmed start', () => {
    const future = appointment('b', 'CONFIRMED', futureStart, { hasClinicalRecord: true });
    expect(offersClinicCancellation(everyAction, future, now)).toBe(false);
    expect(offersAppointmentCompletion(everyAction, future, now)).toBe(false);
  });
});

describe('offersClinicalRecord (SPEC-MED-010 Part F)', () => {
  const veterinarian = clinic('c-1', {
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'],
  });
  const receptionist = clinic('c-1', {
    capabilities: ['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CANCEL', 'APPOINTMENT_COMPLETE'],
  });

  it('is offered only to actors holding CLINICAL_DOCUMENTATION', () => {
    const confirmed = appointment('a', 'CONFIRMED', '2035-06-01T10:00:00Z');
    expect(offersClinicalRecord(veterinarian, confirmed)).toBe(true);
    expect(offersClinicalRecord(receptionist, confirmed)).toBe(false);
    expect(
      offersClinicalRecord(clinic('c-1', { capabilities: ['CLINICAL_CARE'] }), confirmed),
    ).toBe(false);
    expect(
      offersClinicalRecord(clinic('c-1', { capabilities: ['CLINICAL_DOCUMENTATION'] }), confirmed),
    ).toBe(true);
  });

  it('is offered for CONFIRMED and COMPLETED Appointments, or whenever records exist', () => {
    for (const state of ['CONFIRMED', 'COMPLETED'] as const) {
      expect(
        offersClinicalRecord(veterinarian, appointment('a', state, '2035-06-01T10:00:00Z')),
      ).toBe(true);
    }
    for (const state of ['REQUESTED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'] as const) {
      expect(
        offersClinicalRecord(veterinarian, appointment('a', state, '2035-06-01T10:00:00Z')),
      ).toBe(false);
    }
    expect(
      offersClinicalRecord(
        veterinarian,
        appointment('a', 'CANCELLED', '2035-06-01T10:00:00Z', { hasClinicalRecord: true }),
      ),
    ).toBe(true);
  });
});

describe('offersVeterinarianAssignment (SPEC-APT-007 §13)', () => {
  it('shows the assigned Veterinarian only for CONFIRMED and COMPLETED Appointments', () => {
    for (const state of ['CONFIRMED', 'COMPLETED'] as const) {
      expect(offersVeterinarianAssignment(appointment('a', state, '2035-06-01T10:00:00Z'))).toBe(
        true,
      );
    }
    for (const state of ['REQUESTED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'] as const) {
      expect(offersVeterinarianAssignment(appointment('a', state, '2035-06-01T10:00:00Z'))).toBe(
        false,
      );
    }
  });
});

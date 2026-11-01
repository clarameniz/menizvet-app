import {
  PROFESSIONAL_RESCHEDULE_INVALID_REQUEST,
  PROFESSIONAL_RESCHEDULE_MALFORMED,
} from '@/data/professional-appointment-reschedule';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import {
  mapAlternativeTimeAcceptanceErrorToKey,
  mapAlternativeTimeCandidatesErrorToKey,
  mapAlternativeTimeProposalErrorToKey,
} from '@/i18n/requested-alternative-time-error-messages';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

/** Resolves a "namespace.key" in a catalog, so every mapped key is proven to exist. */
function lookup(catalog: Record<string, Record<string, string>>, key: string): string | undefined {
  const [namespace, leaf] = key.split('.');
  return catalog[namespace]?.[leaf];
}

describe('mapAlternativeTimeProposalErrorToKey (SPEC-APT-018)', () => {
  it.each<[string, string, string]>([
    ['normalized 28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
    [
      'stale P0001',
      'Stale requested Appointment schedule revision for alternative time proposal',
      'alternativeTime.staleSchedule',
    ],
    [
      'capability denial',
      'Applicable Appointment-management capability is required',
      'alternativeTime.accessLost',
    ],
    [
      'Entitlement denial',
      'Applicable professional Entitlement is required',
      'alternativeTime.entitlementDenied',
    ],
    [
      'no longer REQUESTED',
      'Only a REQUESTED Appointment may receive an alternative time proposal',
      'alternativeTime.lifecycleChanged',
    ],
    [
      'request lapsed',
      'A REQUESTED Appointment whose requested time has passed cannot receive an alternative time proposal',
      'alternativeTime.startPassed',
    ],
    [
      'no standard duration',
      'Clinic has no currently configured standard Appointment duration',
      'alternativeTime.noStandardDuration',
    ],
    [
      'one open proposal',
      'Appointment 1 already has an actionable unresolved reschedule Proposal',
      'alternativeTime.pendingExists',
    ],
    [
      'same start',
      'Proposed time must differ from the current requested time',
      'alternativeTime.sameTime',
    ],
    [
      'Clinic Availability',
      'Clinic Appointment Availability does not cover the proposed interval',
      'alternativeTime.timeUnavailable',
    ],
    [
      'past start',
      'Proposed Appointment time must be in the future',
      'alternativeTime.timeUnavailable',
    ],
    [
      'Veterinarian unavailable or conflicting (one generic message)',
      'Currently assigned Veterinarian is not available for the proposed interval',
      'alternativeTime.veterinarianUnavailable',
    ],
    [
      'Veterinarian Clinic Assignment ended',
      'Currently assigned Veterinarian no longer has a valid Clinic Assignment',
      'alternativeTime.veterinarianUnavailable',
    ],
    [
      'missing reason',
      'A meaningful reason is required for a Clinic alternative time proposal',
      'alternativeTime.reasonMissing',
    ],
    ['an unknown failure', 'connection reset by peer', 'alternativeTime.failed'],
    ['a local invalid request', PROFESSIONAL_RESCHEDULE_INVALID_REQUEST, 'alternativeTime.failed'],
  ])('maps %s', (_label, error, key) => {
    expect(mapAlternativeTimeProposalErrorToKey(error)).toBe(key);
  });

  it('never returns raw backend text, and every key exists in both catalogs', () => {
    for (const error of [
      'Stale requested Appointment schedule revision for alternative time proposal',
      'syntax error at or near "select"',
    ]) {
      const key = mapAlternativeTimeProposalErrorToKey(error);
      expect(lookup(es, key)).toBeDefined();
      expect(lookup(en, key)).toBeDefined();
      expect(key).not.toContain(' ');
    }
  });
});

describe('mapAlternativeTimeCandidatesErrorToKey (SPEC-APT-020)', () => {
  it('keeps specific copy for known rules and says the times could not be loaded otherwise', () => {
    expect(
      mapAlternativeTimeCandidatesErrorToKey(
        'Clinic has no currently configured standard Appointment duration',
      ),
    ).toBe('alternativeTime.noStandardDuration');
    expect(
      mapAlternativeTimeCandidatesErrorToKey('Requested range must not span more than 60 days'),
    ).toBe('alternativeTime.candidatesLoadError');
    expect(mapAlternativeTimeCandidatesErrorToKey(PROFESSIONAL_RESCHEDULE_MALFORMED)).toBe(
      'alternativeTime.candidatesLoadError',
    );
    expect(mapAlternativeTimeCandidatesErrorToKey('Network request failed')).toBe(
      'alternativeTime.candidatesLoadError',
    );
  });
});

describe('mapAlternativeTimeAcceptanceErrorToKey (SPEC-APT-019)', () => {
  it.each<[string, string, string]>([
    [
      'no domain User',
      'No coherent domain User exists for the authenticated subject',
      'errors.sessionExpired',
    ],
    [
      'lost Guardianship',
      'Current Guardianship of the Appointment Pet is required',
      'appointmentErrors.lostGuardianship',
    ],
    [
      'Availability changed',
      'Clinic Appointment Availability does not cover the proposed interval',
      'alternativeTimeProposal.timeUnavailable',
    ],
    [
      'Veterinarian no longer available',
      'Currently assigned Veterinarian is not available for the proposed interval',
      'alternativeTimeProposal.timeUnavailable',
    ],
    [
      'withdrawn or VOID',
      'Reschedule Proposal is no longer actionable',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    [
      'superseded by a Guardian reschedule',
      'Alternative time proposal base revision is no longer the current requested context',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    [
      'confirmed or cancelled meanwhile',
      'Appointment must remain REQUESTED to accept an alternative time',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    [
      'request lapsed',
      'A REQUESTED Appointment whose requested time has passed cannot be rescheduled',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    [
      'proposed time lapsed',
      'Proposed Appointment time must still be in the future',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    [
      'proposer authority lost',
      'The Clinic Proposal is no longer actionable because proposing authority was lost',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    [
      'a confirmed-reschedule proposal',
      'Only a Clinic alternative time for a requested Appointment can be accepted through this operation',
      'alternativeTimeProposal.proposalUnavailable',
    ],
    ['an unknown failure', 'Network request failed', 'alternativeTimeProposal.failed'],
  ])('maps %s', (_label, error, key) => {
    expect(mapAlternativeTimeAcceptanceErrorToKey(error)).toBe(key);
  });
});

describe('the alternative-time copy says what it must (SPEC-APT-018 §5, SPEC-APT-019 §5)', () => {
  it('keeps the list tags of the approved presentation contract', () => {
    expect(es.appointments.alternativeTimeProposedIndicator).toBe(
      'La clínica propone otro horario',
    );
    expect(en.appointments.alternativeTimeProposedIndicator).toBe('Clinic proposed another time');
    expect(es.appointments.awaitingClinicConfirmationIndicator).toBe(
      'Pendiente de confirmación de la clínica',
    );
    expect(en.appointments.awaitingClinicConfirmationIndicator).toBe(
      'Awaiting clinic confirmation',
    );
  });

  it('says that accepting changes the request and the Clinic still confirms, with the deadline', () => {
    expect(en.alternativeTimeProposal.acceptExplanation).toBe(
      'Accepting changes your request; the clinic still needs to confirm the appointment.',
    );
    for (const catalog of [es, en]) {
      expect(catalog.alternativeTimeProposal.deadline).toContain('{{current}}');
      expect(catalog.alternativeTimeProposal.dialogMessage).toContain('{{current}}');
      expect(catalog.alternativeTimeProposal.dialogMessage).toContain('{{proposed}}');
    }
  });

  it('warns that confirming discards the pending alternative, and that rescheduling discards it', () => {
    for (const catalog of [es, en]) {
      expect(catalog.alternativeTime.confirmWithPendingDialogMessage).toContain('{{proposed}}');
      expect(catalog.alternativeTime.confirmWithPendingDialogMessage).toContain('{{petName}}');
      expect(catalog.appointmentReschedule.discardsAlternativeWarning.length).toBeGreaterThan(0);
    }
    expect(en.alternativeTime.confirmWithPendingDialogMessage).toContain(
      'discards the pending alternative proposal',
    );
  });

  it('states in the proposal dialog that the Appointment stays requested', () => {
    expect(en.alternativeTime.dialogMessage).toContain('The appointment stays requested');
    expect(es.alternativeTime.dialogMessage).toContain('La cita sigue solicitada');
  });

  it('never presents the accepted state as confirmed', () => {
    expect(en.alternativeTimeProposal.awaitingConfirmation).toBe(
      'Requested time updated — awaiting confirmation from the clinic.',
    );
    expect(en.alternativeTime.acceptedAwaitingConfirmation).toBe(
      'The guardian accepted the proposed time. Awaiting clinic confirmation.',
    );
    expect(es.alternativeTime.acceptedAwaitingConfirmation).toBe(
      'El responsable aceptó el horario propuesto. Pendiente de confirmación.',
    );
  });
});

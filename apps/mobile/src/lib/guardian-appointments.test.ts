import type { GuardianAppointment } from '@/data/guardian-appointments';
import { mapGuardianAppointmentsErrorToKey } from '@/i18n/guardian-appointments-error-messages';
import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import {
  guardianAppointmentRowLabel,
  guardianAppointmentRowTags,
  withClinicNames,
} from '@/lib/guardian-appointments';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));

function row(overrides: Partial<GuardianAppointment> = {}): GuardianAppointment {
  return {
    id: 'apt-1',
    petId: 'pet-luna',
    petName: 'Luna',
    clinicId: 'clinic-a',
    lifecycleState: 'CONFIRMED',
    currentScheduledStartAt: '2035-03-01T09:00:00+00:00',
    currentScheduledEndAt: '2035-03-01T09:30:00+00:00',
    currentSchedulingTimezoneName: 'Europe/Madrid',
    pendingProposalContext: null,
    awaitingClinicConfirmation: false,
    ...overrides,
  };
}

describe('withClinicNames', () => {
  const names = new Map([
    ['clinic-a', { displayName: 'Animalia Centro' }],
    ['clinic-b', { displayName: null }],
  ]);

  it('attaches each Clinic’s published name, keeping several Pets and Clinics apart', () => {
    const rows = withClinicNames(
      [row(), row({ id: 'apt-2', petId: 'pet-toby', petName: 'Toby', clinicId: 'clinic-b' })],
      names,
    );
    expect(rows.map((item) => [item.petName, item.clinicDisplayName])).toEqual([
      ['Luna', 'Animalia Centro'],
      ['Toby', null],
    ]);
  });

  it('leaves null for an unpublished Clinic or a failed lookup', () => {
    expect(withClinicNames([row({ clinicId: 'clinic-x' })], names)[0].clinicDisplayName).toBeNull();
    expect(withClinicNames([row()], null)[0].clinicDisplayName).toBeNull();
  });
});

describe('guardianAppointmentRowTags (SPEC-APT-011 BR-40, SPEC-APT-019 §5)', () => {
  const kinds = (overrides: Partial<GuardianAppointment>) =>
    guardianAppointmentRowTags(row(overrides)).map((tag) => tag.labelKey);

  it('names a due answer: a Clinic alternative for a request, a Clinic new time for a confirmed one', () => {
    expect(kinds({ lifecycleState: 'REQUESTED', pendingProposalContext: 'CLINIC' })).toEqual([
      'appointments.alternativeTimeProposedIndicator',
    ]);
    expect(kinds({ lifecycleState: 'CONFIRMED', pendingProposalContext: 'CLINIC' })).toEqual([
      'appointments.pendingRescheduleIndicator',
    ]);
  });

  it('names an accepted alternative awaiting the Clinic with its own, different tag', () => {
    const tags = guardianAppointmentRowTags(
      row({ lifecycleState: 'REQUESTED', awaitingClinicConfirmation: true }),
    );
    expect(tags).toEqual([
      { kind: 'awaitingClinic', labelKey: 'appointments.awaitingClinicConfirmationIndicator' },
    ]);
  });

  it('shows both, never merged, when a new Clinic alternative follows an accepted one', () => {
    expect(
      guardianAppointmentRowTags(
        row({
          lifecycleState: 'REQUESTED',
          pendingProposalContext: 'CLINIC',
          awaitingClinicConfirmation: true,
        }),
      ).map((tag) => tag.kind),
    ).toEqual(['proposal', 'awaitingClinic']);
  });

  it('never infers the awaiting tag from the state or from a proposal', () => {
    expect(kinds({ lifecycleState: 'REQUESTED' })).toEqual([]);
    expect(kinds({ lifecycleState: 'REQUESTED', pendingProposalContext: 'CLINIC' })).not.toContain(
      'appointments.awaitingClinicConfirmationIndicator',
    );
  });

  it('shows nothing for a Guardian’s own proposal, without a proposal, or on history', () => {
    expect(kinds({ lifecycleState: 'CONFIRMED', pendingProposalContext: 'GUARDIAN' })).toEqual([]);
    expect(kinds({ lifecycleState: 'CONFIRMED' })).toEqual([]);
    expect(kinds({ lifecycleState: 'COMPLETED', pendingProposalContext: 'CLINIC' })).toEqual([]);
  });

  it('keeps SPEC-APT-019 §5’s copy for both list tags', () => {
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
});

describe('guardianAppointmentRowLabel', () => {
  it('announces Pet, Clinic, full date, time, state and the tags, in that order', () => {
    expect(
      guardianAppointmentRowLabel({
        fullDate: 'Jueves, 1 de marzo de 2035',
        time: '10:00',
        petName: 'Luna',
        clinicLabel: 'Animalia Centro',
        lifecycleLabel: 'Solicitada',
        tagLabels: ['La clínica propone otro horario', 'Pendiente de confirmación de la clínica'],
      }),
    ).toBe(
      'Luna, Animalia Centro, Jueves, 1 de marzo de 2035, 10:00, Solicitada, La clínica propone otro horario, Pendiente de confirmación de la clínica',
    );
  });

  it('omits absent tags', () => {
    expect(
      guardianAppointmentRowLabel({
        fullDate: 'Thursday, March 1, 2035',
        time: '10:00 AM',
        petName: 'Luna',
        clinicLabel: 'Clinic unavailable',
        lifecycleLabel: 'Completed',
        tagLabels: [],
      }),
    ).toBe('Luna, Clinic unavailable, Thursday, March 1, 2035, 10:00 AM, Completed');
  });
});

describe('"My appointments" copy and errors', () => {
  it('has both tabs and their loading, error and empty states in ES and EN', () => {
    expect([
      es.appointments.title,
      es.appointments.activeSectionTitle,
      es.appointments.historicalSectionTitle,
    ]).toEqual(['Mis citas', 'Activas', 'Historial']);
    expect([
      en.appointments.title,
      en.appointments.activeSectionTitle,
      en.appointments.historicalSectionTitle,
    ]).toEqual(['My appointments', 'Active', 'History']);
    for (const catalog of [es, en]) {
      const {
        activeLoading,
        activeLoadError,
        activeEmpty,
        historyLoading,
        historyLoadError,
        historyEmpty,
      } = catalog.appointments;
      const copy = [
        activeLoading,
        activeLoadError,
        activeEmpty,
        historyLoading,
        historyLoadError,
        historyEmpty,
      ];
      expect(copy.every((text) => text.trim().length > 0)).toBe(true);
      expect(new Set(copy).size).toBe(copy.length);
    }
  });

  it('maps a lost session to the shared copy and everything else to the calm load error', () => {
    expect(mapGuardianAppointmentsErrorToKey('GUARDIAN_APPOINTMENTS_AUTH_REQUIRED')).toBe(
      'errors.sessionExpired',
    );
    expect(mapGuardianAppointmentsErrorToKey('GUARDIAN_APPOINTMENTS_MALFORMED')).toBe(
      'appointments.loadError',
    );
    expect(mapGuardianAppointmentsErrorToKey('Network request failed')).toBe(
      'appointments.loadError',
    );
  });
});

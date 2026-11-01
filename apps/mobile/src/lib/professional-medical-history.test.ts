import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { ProfessionalHistoryEntry } from '@/data/professional-medical-history';
import {
  appendProfessionalHistoryPage,
  correctionCountLabel,
  offersHistoryFromAppointmentDetail,
  professionalMedicalHistoryHref,
  provenanceName,
} from '@/lib/professional-medical-history';

const NOW = Date.parse('2026-10-14T12:00:00Z');

const clinic = (capabilities: ProfessionalClinic['capabilities']): ProfessionalClinic =>
  ({
    clinicId: 'clinic-a',
    clinicDisplayName: 'Clínica Norte',
    organizationId: 'org-1',
    organizationDisplayName: 'Org X',
    capabilities,
    unknownCapabilities: [],
  }) as ProfessionalClinic;

const appointment = (
  lifecycleState: ClinicScheduleAppointment['lifecycleState'],
  start: string,
  hasClinicalRecord = false,
): ClinicScheduleAppointment =>
  ({
    id: 'appt-1',
    lifecycleState,
    currentScheduledStartAt: start,
    hasClinicalRecord,
  }) as ClinicScheduleAppointment;

const VET = clinic(['APPOINTMENT_VIEW_SCHEDULE', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION']);
const RECEPTION = clinic(['APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_CONFIRM']);
const FUTURE = '2026-10-20T09:00:00Z';
const PAST = '2026-10-01T09:00:00Z';

describe('offersHistoryFromAppointmentDetail', () => {
  it('offers prior history for CONFIRMED and for REQUESTED with a future start', () => {
    expect(offersHistoryFromAppointmentDetail(VET, appointment('CONFIRMED', PAST), NOW)).toBe(true);
    expect(offersHistoryFromAppointmentDetail(VET, appointment('REQUESTED', FUTURE), NOW)).toBe(
      true,
    );
  });

  it('does not offer it for a REQUESTED start that has passed, or a COMPLETED Appointment', () => {
    expect(offersHistoryFromAppointmentDetail(VET, appointment('REQUESTED', PAST), NOW)).toBe(
      false,
    );
    expect(offersHistoryFromAppointmentDetail(VET, appointment('COMPLETED', PAST), NOW)).toBe(
      false,
    );
  });

  it('keeps offering it once the visit has records (SPEC-MED-010 BR-14), never for terminal Appointments', () => {
    expect(offersHistoryFromAppointmentDetail(VET, appointment('CONFIRMED', PAST, true), NOW)).toBe(
      true,
    );
    expect(offersHistoryFromAppointmentDetail(VET, appointment('COMPLETED', PAST, true), NOW)).toBe(
      false,
    );
    for (const state of ['CANCELLED', 'NO_SHOW', 'EXPIRED'] as const) {
      expect(offersHistoryFromAppointmentDetail(VET, appointment(state, FUTURE), NOW)).toBe(false);
    }
  });

  it('requires CLINICAL_CARE at the Clinic; Appointment Assignment and Availability play no part', () => {
    expect(offersHistoryFromAppointmentDetail(RECEPTION, appointment('CONFIRMED', PAST), NOW)).toBe(
      false,
    );
    expect(
      offersHistoryFromAppointmentDetail(
        VET,
        { ...appointment('CONFIRMED', PAST), currentVeterinarianClinicAssignmentId: null },
        NOW,
      ),
    ).toBe(true);
  });
});

describe('provenance and corrections', () => {
  it('shows the display name as entered, or the neutral fallback, never a title', () => {
    expect(provenanceName({ displayName: 'Ana García', isMe: false }, 'Veterinario')).toBe(
      'Ana García',
    );
    expect(provenanceName({ displayName: null, isMe: true }, 'Veterinario')).toBe('Veterinario');
  });

  it('chooses the singular or plural correction count', () => {
    expect(correctionCountLabel(1)).toEqual({
      key: 'professionalHistory.correctionsOne',
      params: { count: 1 },
    });
    expect(correctionCountLabel(2)).toEqual({
      key: 'professionalHistory.correctionsOther',
      params: { count: 2 },
    });
  });
});

describe('navigation and pages', () => {
  it('builds the Appointment-scoped history route with no other identifier', () => {
    expect(professionalMedicalHistoryHref('clinic-a', 'appt-1')).toEqual({
      pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/history',
      params: { clinicId: 'clinic-a', appointmentId: 'appt-1' },
    });
  });

  it('appends pages in server order, adopting the new cursor and never duplicating an Entry', () => {
    const entry = (entryId: string) => ({ entryId }) as ProfessionalHistoryEntry;
    const next = appendProfessionalHistoryPage(
      {
        entries: [entry('a'), entry('b')],
        cursor: { beforeHistoryOrderAt: 'x', beforeEntryId: 'b' },
      },
      { entries: [entry('b'), entry('c')], cursor: null },
    );
    expect(next.entries.map((item) => item.entryId)).toEqual(['a', 'b', 'c']);
    expect(next.cursor).toBeNull();
  });
});

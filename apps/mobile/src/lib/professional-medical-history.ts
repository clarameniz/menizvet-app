import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type {
  ProfessionalHistoryIdentity,
  ProfessionalHistoryPage,
} from '@/data/professional-medical-history';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Presentation decisions for the professional longitudinal history
 * (SPEC-MED-005 §15 Mobile presentation). Every offer here is advisory: the
 * server decides, and an offered action may still end in the calm
 * unavailable state. Nothing here reads history, so the decisions never
 * create a medical-access audit event.
 */

export function professionalMedicalHistoryHref(clinicId: string, appointmentId: string) {
  return {
    pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/history',
    params: { clinicId, appointmentId },
  } as const;
}

/**
 * The Appointment detail offers prior history from the schedule row only
 * (SPEC-MED-010 BR-14, Part F): the actor holds CLINICAL_CARE at the Clinic and
 * the Appointment is CONFIRMED, or REQUESTED with a future start. Whether the
 * visit already has records never matters. Never for a COMPLETED or terminal
 * Appointment. Advisory: the read itself decides, and runs only when tapped.
 */
export function offersHistoryFromAppointmentDetail(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  now: number,
): boolean {
  if (!clinic.capabilities.includes('CLINICAL_CARE')) return false;
  if (appointment.lifecycleState === 'CONFIRMED') return true;
  return (
    appointment.lifecycleState === 'REQUESTED' &&
    Date.parse(appointment.currentScheduledStartAt) > now
  );
}

/**
 * The Veterinarian name to show: the display name as entered (no title is
 * ever added), or the neutral fallback when none is set.
 */
export function provenanceName(identity: ProfessionalHistoryIdentity, fallback: string): string {
  return identity.displayName ?? fallback;
}

export function correctionCountLabel(count: number): {
  key: TranslationKey;
  params: { count: number };
} {
  return {
    key:
      count === 1 ? 'professionalHistory.correctionsOne' : 'professionalHistory.correctionsOther',
    params: { count },
  };
}

/** Appends a further page in server order, adopting its cursor verbatim. */
export function appendProfessionalHistoryPage(
  current: ProfessionalHistoryPage,
  next: ProfessionalHistoryPage,
): ProfessionalHistoryPage {
  const known = new Set(current.entries.map((entry) => entry.entryId));
  return {
    entries: [...current.entries, ...next.entries.filter((entry) => !known.has(entry.entryId))],
    cursor: next.cursor,
  };
}

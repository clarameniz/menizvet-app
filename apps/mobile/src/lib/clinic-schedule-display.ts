import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type { ProfessionalClinic, ProfessionalClinics } from '@/data/professional-clinics';
import { offersAppointmentHours } from '@/lib/appointment-hours';
import {
  isPendingRequestedAppointment,
  isScheduledStartInFuture,
  isUpcomingAppointmentState,
} from '@/lib/appointment-lifecycle';
import { offersClinicSettings } from '@/lib/clinic-settings';

/**
 * Pure presentation helpers for the professional Clinic landing and the
 * read-only Clinic Appointment Schedule (SPEC-ORG-008, SPEC-APT-012). Nothing
 * here authorizes anything: Professional Clinic capabilities are advisory
 * (SPEC-ORG-008 BR-13) and only decide what the app OFFERS; the schedule read
 * re-authorizes the caller server-side on every call.
 */

/** The professional workflows this app version implements for a Clinic. */
export type ProfessionalClinicWorkflow =
  'APPOINTMENT_SCHEDULE' | 'APPOINTMENT_HOURS' | 'CLINIC_SETTINGS';

/** The Professional Clinic with this id in a fresh ORG-008 read, or `null` if it is not listed. */
export function findProfessionalClinic(
  result: ProfessionalClinics,
  clinicId: string,
): ProfessionalClinic | null {
  return result.clinics.find((clinic) => clinic.clinicId === clinicId) ?? null;
}

/**
 * Whether to offer the Appointment schedule for this Clinic — only when the
 * KNOWN capability set holds APPOINTMENT_VIEW_SCHEDULE. Unknown identifiers
 * never count.
 */
export function offersAppointmentSchedule(clinic: ProfessionalClinic): boolean {
  return clinic.capabilities.includes('APPOINTMENT_VIEW_SCHEDULE');
}

/**
 * The workflow entries to show on the professional Clinic screen, derived only
 * from known capabilities. Empty for a Clinic whose capabilities this app
 * version doesn't know — the Clinic stays valid, it just offers nothing.
 */
export function professionalClinicWorkflows(
  clinic: ProfessionalClinic,
): ProfessionalClinicWorkflow[] {
  const workflows: ProfessionalClinicWorkflow[] = [];
  if (offersAppointmentSchedule(clinic)) workflows.push('APPOINTMENT_SCHEDULE');
  if (offersAppointmentHours(clinic)) workflows.push('APPOINTMENT_HOURS');
  if (offersClinicSettings(clinic)) workflows.push('CLINIC_SETTINGS');
  return workflows;
}

/** What the schedule screen may show for a route `clinicId`, from a fresh ORG-008 read. */
export type ClinicScheduleAvailability =
  | { kind: 'available'; clinic: ProfessionalClinic }
  /** No longer a Professional Clinic for this User (or never was). */
  | { kind: 'clinicUnavailable' }
  /** Still a Professional Clinic, but this app version offers no schedule for it. */
  | { kind: 'scheduleUnavailable'; clinic: ProfessionalClinic };

export function resolveClinicScheduleAvailability(
  result: ProfessionalClinics,
  clinicId: string,
): ClinicScheduleAvailability {
  const clinic = findProfessionalClinic(result, clinicId);
  if (clinic === null) return { kind: 'clinicUnavailable' };
  if (!offersAppointmentSchedule(clinic)) return { kind: 'scheduleUnavailable', clinic };
  return { kind: 'available', clinic };
}

function startMs(appointment: ClinicScheduleAppointment): number {
  return Date.parse(appointment.currentScheduledStartAt);
}

/**
 * Whether a CONFIRMED Appointment's confirmed start has been reached at
 * `referenceInstant` (start <= reference; the end is not required —
 * SPEC-APT-010 BR-44). ADVISORY: device clock; the backend decides. An
 * unparseable start is never treated as reached.
 */
function isConfirmedStartReached(
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  const start = startMs(appointment);
  return (
    appointment.lifecycleState === 'CONFIRMED' &&
    Number.isFinite(start) &&
    start <= referenceInstant.getTime()
  );
}

/** The presentation group of one Appointment, named in the detail header. */
export type ClinicScheduleGroup = 'upcoming' | 'needsResolution' | 'historical';

/**
 * Which group the Appointment detail header names at `referenceInstant`
 * (advisory device clock): historical for every terminal outcome,
 * needs-resolution for a CONFIRMED Appointment whose start has been reached,
 * otherwise upcoming — including a stored REQUESTED whose time has passed,
 * which is never relabelled.
 */
export function clinicScheduleGroupOf(
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): ClinicScheduleGroup {
  if (!isUpcomingAppointmentState(appointment.lifecycleState)) return 'historical';
  if (isConfirmedStartReached(appointment, referenceInstant)) return 'needsResolution';
  return 'upcoming';
}

/**
 * Whether to show the "pending reschedule" indicator. The backend only returns
 * an actionable PENDING proposal, so its presence is the whole decision; the
 * proposed interval is never shown as the Appointment's scheduled interval.
 */
export function showsPendingReschedule(appointment: ClinicScheduleAppointment): boolean {
  return appointment.pendingReschedule !== null;
}

/**
 * The reason recorded by the cancellation of a CANCELLED Appointment — the
 * Clinic's own reason, or a Guardian's — exactly as stored (SPEC-APT-003
 * BR-8/BR-9), or `null` for any other state and for a cancellation without a
 * reason, so no empty section is shown.
 */
export function cancellationReasonToShow(appointment: ClinicScheduleAppointment): string | null {
  const reason = appointment.cancellationReason;
  return appointment.lifecycleState === 'CANCELLED' && reason !== null && reason.trim() !== ''
    ? reason
    : null;
}

/**
 * The optional notes a pet guardian wrote for the Clinic when requesting the
 * Appointment (SPEC-APT-001 §4, preserved by rescheduling, SPEC-APT-004 BR-16),
 * exactly as written — or `null` when there are none, so no empty section is
 * shown. Request context in every lifecycle state, never clinical
 * documentation.
 */
export function guardianNotesToShow(appointment: ClinicScheduleAppointment): string | null {
  const notes = appointment.guardianNotes;
  return notes !== null && notes.trim() !== '' ? notes : null;
}

/**
 * Whether to offer Confirm on this Appointment (SPEC-APT-002): only a
 * still-pending REQUESTED Appointment — its requested start strictly after
 * `referenceInstant` (BR-19) — at a Clinic whose KNOWN capabilities hold
 * APPOINTMENT_CONFIRM. Unknown identifiers never count. This is eligibility
 * only: the APPOINTMENT_MANAGEMENT Entitlement is applied on top by
 * `managedActionGate` (SPEC-APT-012 BR-61), and a backend denial is still
 * mapped after an attempt. The time check is advisory (device clock); a past
 * REQUESTED row is never relabelled EXPIRED.
 */
export function offersAppointmentConfirmation(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isPendingRequestedAppointment(
      appointment.lifecycleState,
      appointment.currentScheduledStartAt,
      referenceInstant,
    ) && clinic.capabilities.includes('APPOINTMENT_CONFIRM')
  );
}

export type AppointmentConfirmationRequest = {
  appointmentId: string;
  expectedRequestedRevisionSequence: number;
};

/**
 * The stale-safe confirmation request for the Appointment row exactly as it
 * was displayed (SPEC-APT-002 BR-21): its own id and the revision sequence of
 * the very interval shown in the detail. Never re-read, substituted with a newer
 * sequence, or derived from the displayed times.
 */
export function confirmationRequestFor(
  appointment: ClinicScheduleAppointment,
): AppointmentConfirmationRequest {
  return {
    appointmentId: appointment.id,
    expectedRequestedRevisionSequence: appointment.currentScheduleRevisionSequence,
  };
}

/**
 * Whether to offer "Mark as no-show" on this Appointment (SPEC-APT-010): only
 * a CONFIRMED Appointment whose confirmed start has been reached at
 * `referenceInstant` (BR-44; the end is not required), at a Clinic whose KNOWN
 * capabilities hold APPOINTMENT_MARK_NO_SHOW, and with no Clinical Record Entry
 * (SPEC-MED-010 BR-9, advisory through `hasClinicalRecord`). Unknown
 * identifiers never count; there is no Entitlement gate (BR-34). The time
 * check is advisory (device clock); the backend is authoritative.
 */
export function offersAppointmentNoShow(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isConfirmedStartReached(appointment, referenceInstant) &&
    !appointment.hasClinicalRecord &&
    clinic.capabilities.includes('APPOINTMENT_MARK_NO_SHOW')
  );
}

export type AppointmentNoShowRequest = {
  appointmentId: string;
  expectedConfirmedRevisionSequence: number;
};

/**
 * The stale-safe no-show request for the CONFIRMED Appointment row exactly as
 * it was displayed (SPEC-APT-010 BR-41): its own id and the revision sequence
 * of the very confirmed interval shown in the detail. Never re-read, substituted
 * with a newer sequence, or derived from the displayed times.
 */
export function noShowRequestFor(appointment: ClinicScheduleAppointment): AppointmentNoShowRequest {
  return {
    appointmentId: appointment.id,
    expectedConfirmedRevisionSequence: appointment.currentScheduleRevisionSequence,
  };
}

/**
 * Whether to offer "Mark as completed" on this Appointment (SPEC-APT-009,
 * SPEC-APT-012 BR-46): exactly the NO_SHOW situation — a CONFIRMED
 * Appointment whose confirmed start has been reached at `referenceInstant`
 * (BR-7; the end is not required) — at a Clinic whose KNOWN capabilities hold
 * APPOINTMENT_COMPLETE. Unknown identifiers never count; there is no
 * Entitlement gate (BR-6). It deliberately ignores any Veterinarian Assignment
 * and any clinical documentation (BR-2, BR-12): completion needs neither, and
 * existing records do not block it. The time check is advisory (device
 * clock); the backend is authoritative.
 */
export function offersAppointmentCompletion(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isConfirmedStartReached(appointment, referenceInstant) &&
    clinic.capabilities.includes('APPOINTMENT_COMPLETE')
  );
}

export type AppointmentCompletionRequest = {
  appointmentId: string;
  expectedConfirmedRevisionSequence: number;
};

/**
 * The stale-safe completion request for the CONFIRMED Appointment row exactly
 * as it was displayed (SPEC-APT-009 BR-8): its own id and the revision
 * sequence of the very confirmed interval shown in the detail. Never re-read,
 * substituted with a newer sequence, or derived from the displayed times.
 */
export function completionRequestFor(
  appointment: ClinicScheduleAppointment,
): AppointmentCompletionRequest {
  return {
    appointmentId: appointment.id,
    expectedConfirmedRevisionSequence: appointment.currentScheduleRevisionSequence,
  };
}

/**
 * Whether a re-read after a failed completion shows the Appointment already
 * COMPLETED — after a lost response to this actor's own successful call, or a
 * completion by another actor — so the outcome is reported neutrally instead
 * of as a failure. Any other refreshed state (still CONFIRMED after a stale
 * rejection, NO_SHOW, CANCELLED, or no Appointment) is not.
 */
export function isAppointmentNowCompleted(
  appointmentId: string,
  refreshed: ClinicScheduleAppointment | null,
): boolean {
  return (
    refreshed !== null && refreshed.id === appointmentId && refreshed.lifecycleState === 'COMPLETED'
  );
}

/**
 * Whether to offer Clinic cancellation of this Appointment (SPEC-APT-003), at
 * a Clinic whose KNOWN capabilities hold APPOINTMENT_CANCEL (unknown
 * identifiers never count; no Entitlement gate, BR-19), never once a Clinical
 * Record Entry exists (advisory, SPEC-MED-010 BR-9):
 * - a REQUESTED Appointment only while its requested start is strictly after
 *   `referenceInstant` — afterwards it is logically expired (BR-23);
 * - a CONFIRMED Appointment while it is CONFIRMED, before or after its start:
 *   the Guardian cutoff at the confirmed start (BR-31) never applies to the
 *   Clinic, which may record that it called the visit off. After the start it
 *   is presented as a secondary option (`isPostStartClinicCancellation`).
 * The time check is advisory (device clock); the backend is authoritative.
 */
export function offersClinicCancellation(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  if (!clinic.capabilities.includes('APPOINTMENT_CANCEL')) return false;
  if (appointment.hasClinicalRecord) return false;
  if (appointment.lifecycleState === 'CONFIRMED') {
    return Number.isFinite(Date.parse(appointment.currentScheduledStartAt));
  }
  return (
    appointment.lifecycleState === 'REQUESTED' &&
    isScheduledStartInFuture(appointment.currentScheduledStartAt, referenceInstant)
  );
}

/**
 * Whether a Clinic cancellation would concern a CONFIRMED Appointment whose
 * start has been reached (Needs resolution). Completion and no-show are the
 * usual resolutions; cancellation is then only for a visit the Clinic itself
 * called off (SPEC-APT-003 BR-31), so it is shown as a less prominent,
 * explicitly labelled action. Presentation only.
 */
export function isPostStartClinicCancellation(
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  return (
    appointment.lifecycleState === 'CONFIRMED' &&
    Number.isFinite(Date.parse(appointment.currentScheduledStartAt)) &&
    !isScheduledStartInFuture(appointment.currentScheduledStartAt, referenceInstant)
  );
}

export type ClinicCancellationRequest = {
  appointmentId: string;
  reason: string;
  expectedScheduleRevisionSequence: number;
};

/**
 * The stale-safe Clinic cancellation request for the Appointment row exactly
 * as it was reviewed (SPEC-APT-003 BR-24): its own id and the revision
 * sequence of the very interval shown, plus the actor's trimmed reason. Never
 * re-read, substituted with a newer sequence, or derived from the times.
 */
export function clinicCancellationRequestFor(
  appointment: ClinicScheduleAppointment,
  reason: string,
): ClinicCancellationRequest {
  return {
    appointmentId: appointment.id,
    reason: reason.trim(),
    expectedScheduleRevisionSequence: appointment.currentScheduleRevisionSequence,
  };
}

/**
 * Whether two reads of one Appointment show the same reviewable state: same
 * Appointment, lifecycle, scheduling revision, and interval. Used to close a
 * cancellation form whose reviewed row has since been replaced by a different
 * one, so a newer revision is never cancelled from a form showing an older one.
 */
export function isSameReviewedAppointment(
  reviewed: ClinicScheduleAppointment,
  current: ClinicScheduleAppointment,
): boolean {
  return (
    reviewed.id === current.id &&
    reviewed.lifecycleState === current.lifecycleState &&
    reviewed.currentScheduleRevisionSequence === current.currentScheduleRevisionSequence &&
    reviewed.currentScheduledStartAt === current.currentScheduledStartAt &&
    reviewed.currentScheduledEndAt === current.currentScheduledEndAt &&
    reviewed.currentSchedulingTimezoneName === current.currentSchedulingTimezoneName
  );
}

/**
 * The professional Appointment detail route an agenda row opens. Only the
 * Clinic and Appointment ids travel; the detail screen re-reads everything else.
 */
export function professionalAppointmentDetailHref(clinicId: string, appointmentId: string) {
  return {
    pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]',
    params: { clinicId, appointmentId },
  } as const;
}

/**
 * Whether the professional Appointment detail shows the Clinical record section
 * (SPEC-MED-010 Part F): only for an actor whose KNOWN Clinic capabilities
 * include CLINICAL_DOCUMENTATION, for a CONFIRMED or COMPLETED Appointment, or
 * whenever Entries exist. Showing it performs the audited record read; nobody
 * else triggers it. Advisory — every clinical operation re-authorizes.
 */
export function offersClinicalRecord(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
): boolean {
  return (
    clinic.capabilities.includes('CLINICAL_DOCUMENTATION') &&
    (appointment.hasClinicalRecord ||
      appointment.lifecycleState === 'CONFIRMED' ||
      appointment.lifecycleState === 'COMPLETED')
  );
}

/**
 * Whether the detail shows the assigned Veterinarian (SPEC-APT-007 §13): only
 * the CONFIRMED and COMPLETED Appointments that can carry an assignment.
 */
export function offersVeterinarianAssignment(appointment: ClinicScheduleAppointment): boolean {
  return appointment.lifecycleState === 'CONFIRMED' || appointment.lifecycleState === 'COMPLETED';
}

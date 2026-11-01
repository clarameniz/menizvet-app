import type { PetAppointment } from '@/data/appointments';
import type {
  ClinicScheduleAppointment,
  PendingRescheduleProposal,
} from '@/data/clinic-appointment-schedule';
import type { RescheduleCandidate } from '@/data/professional-appointment-reschedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { AlternativeTimeProposalRequest } from '@/data/requested-alternative-time';
import { isScheduledStartInFuture } from '@/lib/appointment-lifecycle';
import { managedActionGate, type AppointmentManagementStatus } from '@/lib/appointment-management';

/**
 * Pure rules for the REQUESTED Appointment Alternative Time
 * (SPEC-APT-018/019/020). Everything here is ADVISORY: it only decides what the
 * app OFFERS and SHOWS from the reads, known capabilities, and the device
 * clock. The backend re-authorizes and revalidates every proposal, acceptance,
 * and withdrawal. Nothing here derives an end or a duration.
 */

/** A pending Clinic alternative time for a REQUESTED Appointment. */
export type PendingAlternativeTime = Extract<
  PendingRescheduleProposal,
  { kind: 'requestedAlternativeTime' }
>;

// Either read's Appointment: only the proposal facts shared by both are used.
type WithLifecycleAndProposal = Pick<ClinicScheduleAppointment, 'lifecycleState'> & {
  pendingReschedule: PendingRescheduleProposal | null;
};
type WithLifecycleAndSource = Pick<
  ClinicScheduleAppointment,
  'lifecycleState' | 'currentScheduleSource'
>;

/** The pending Clinic alternative time, or `null` (SPEC-APT-011 BR-32). */
export function pendingAlternativeTime(appointment: {
  pendingReschedule: PendingRescheduleProposal | null;
}): PendingAlternativeTime | null {
  const proposal = appointment.pendingReschedule;
  return proposal?.kind === 'requestedAlternativeTime' ? proposal : null;
}

/**
 * Whether the request currently carries the Clinic's accepted alternative and
 * awaits Clinic confirmation (SPEC-APT-011 BR-33, SPEC-APT-012 BR-45):
 * REQUESTED, and its current requested context was established by accepting a
 * Clinic proposal. Derived from provenance, never a stored flag; a later
 * Guardian reschedule or the confirmation itself ends it.
 */
export function isAwaitingClinicConfirmationOfAcceptedAlternative(
  appointment: WithLifecycleAndSource,
): boolean {
  return (
    appointment.lifecycleState === 'REQUESTED' &&
    appointment.currentScheduleSource?.proposingContext === 'CLINIC'
  );
}

/**
 * Whether to offer "Propose another time" on the professional detail
 * (SPEC-APT-018 §5): a REQUESTED Appointment whose requested start is still in
 * the future, with no pending proposal (one open proposal per Appointment), at
 * a Clinic whose KNOWN capabilities hold APPOINTMENT_RESCHEDULE. This is
 * eligibility only: the APPOINTMENT_MANAGEMENT Entitlement is applied on top
 * by `managedActionGate` (SPEC-APT-012 BR-61); a configured standard duration
 * stays backend-authoritative.
 */
export function offersAlternativeTimeProposal(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  return (
    appointment.lifecycleState === 'REQUESTED' &&
    isScheduledStartInFuture(appointment.currentScheduledStartAt, referenceInstant) &&
    appointment.pendingReschedule === null &&
    clinic.capabilities.includes('APPOINTMENT_RESCHEDULE')
  );
}

/**
 * The professional alternative-time route for one Appointment. It carries the
 * requested revision sequence of the row the detail displayed, so the proposal
 * is bound to the request the actor reviewed (SPEC-APT-018 BR-8). Only a
 * token: the backend checks it.
 */
export function professionalAlternativeTimeHref(
  clinicId: string,
  appointmentId: string,
  reviewedSequence: number,
) {
  return {
    pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/alternative-time',
    params: { clinicId, appointmentId, sequence: String(reviewedSequence) },
  } as const;
}

/** What a fresh schedule row means for the alternative-time screen. */
export type AlternativeTimeAppointmentClassification =
  | 'appointmentMissing'
  | 'changed'
  | 'notOffered'
  /** Eligible, but the Organization's APPOINTMENT_MANAGEMENT is known to be missing. */
  | 'entitlementUnavailable'
  /** Eligible, but that Entitlement could not be verified. */
  | 'entitlementUnverified'
  | 'proposable';

/**
 * Classifies a fresh schedule row for the alternative-time screen, before
 * anything is rendered: gone from the schedule; no longer the REQUESTED
 * revision the actor reviewed; still that revision but no longer proposable (a
 * proposal now exists, the start passed, the capability was lost); still
 * proposable but held back by the Organization's APPOINTMENT_MANAGEMENT
 * (missing or unverified, so no candidate is read); or proposable.
 */
export function classifyAlternativeTimeAppointment(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment | null,
  reviewedSequence: number | null,
  referenceInstant: Date,
  appointmentManagement: AppointmentManagementStatus,
): AlternativeTimeAppointmentClassification {
  if (appointment === null) return 'appointmentMissing';
  if (
    reviewedSequence === null ||
    appointment.lifecycleState !== 'REQUESTED' ||
    appointment.currentScheduleRevisionSequence !== reviewedSequence
  ) {
    return 'changed';
  }
  const gate = managedActionGate(
    offersAlternativeTimeProposal(clinic, appointment, referenceInstant),
    appointmentManagement,
  );
  return gate === 'offered'
    ? 'proposable'
    : gate === 'unavailable'
      ? 'entitlementUnavailable'
      : gate === 'unverified'
        ? 'entitlementUnverified'
        : 'notOffered';
}

/**
 * The stale-safe proposal for the row the actor reviewed: its id, the selected
 * candidate's start only, the trimmed reason, and the reviewed requested
 * revision sequence — never a newer one (SPEC-APT-018 BR-8).
 */
export function alternativeTimeProposalRequestFor(
  appointment: ClinicScheduleAppointment,
  candidate: RescheduleCandidate,
  reason: string,
): AlternativeTimeProposalRequest {
  return {
    appointmentId: appointment.id,
    candidate,
    reason: reason.trim(),
    expectedRequestedRevisionSequence: appointment.currentScheduleRevisionSequence,
  };
}

/**
 * Whether confirming now would discard a pending Clinic alternative
 * (SPEC-APT-002 BR-24): the confirmation dialog must say so. The same fact
 * drives the Guardian reschedule warning (SPEC-APT-004 BR-28).
 */
export function discardsPendingAlternativeTime(appointment: WithLifecycleAndProposal): boolean {
  return (
    appointment.lifecycleState === 'REQUESTED' &&
    appointment.pendingReschedule?.kind === 'requestedAlternativeTime'
  );
}

/**
 * Whether a pending Clinic alternative is still within its response window on
 * the Guardian detail: a REQUESTED Appointment whose current requested start
 * and proposed start are both still in the future (device clock, advisory).
 */
function isAlternativeTimeWithinResponseWindow(
  appointment: PetAppointment,
  referenceInstant: Date,
): boolean {
  const proposal = pendingAlternativeTime(appointment);
  return (
    appointment.lifecycleState === 'REQUESTED' &&
    proposal !== null &&
    appointment.currentScheduledStartAt !== null &&
    isScheduledStartInFuture(appointment.currentScheduledStartAt, referenceInstant) &&
    isScheduledStartInFuture(proposal.proposedStartAt, referenceInstant)
  );
}

/**
 * Whether to offer "Accept proposed time" on the Guardian detail
 * (SPEC-APT-019 §5): a pending Clinic alternative within its response window
 * that the Guardian view reports currently acceptable (SPEC-APT-011 BR-32).
 * Advisory: acceptance revalidates everything.
 */
export function offersAlternativeTimeAcceptance(
  appointment: PetAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isAlternativeTimeWithinResponseWindow(appointment, referenceInstant) &&
    appointment.pendingReschedule?.currentlyAcceptable === true
  );
}

/**
 * Whether to show, instead of Accept, the generic "can't be accepted right
 * now" copy (SPEC-APT-019 §5): the alternative is within its response window
 * but not currently acceptable. The cause is never shown, and the condition
 * may recover.
 */
export function showsAlternativeTimeNotCurrentlyAcceptable(
  appointment: PetAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isAlternativeTimeWithinResponseWindow(appointment, referenceInstant) &&
    appointment.pendingReschedule?.currentlyAcceptable === false
  );
}

/**
 * After an acceptance attempt failed (for example a retry after a lost
 * response), whether the fresh read shows this very proposal was already
 * accepted: the current requested context names it as its source.
 */
export function wasAlternativeTimeAccepted(
  proposal: PendingAlternativeTime,
  refreshed: Pick<PetAppointment, 'currentScheduleSource'>,
): boolean {
  return refreshed.currentScheduleSource?.proposalId === proposal.proposalId;
}

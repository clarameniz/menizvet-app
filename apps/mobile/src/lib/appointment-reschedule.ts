import type { PetAppointment } from '@/data/appointments';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import type {
  ClinicRescheduleProposalRequest,
  RescheduleCandidate,
} from '@/data/professional-appointment-reschedule';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import { isScheduledStartInFuture } from '@/lib/appointment-lifecycle';
import { managedActionGate, type AppointmentManagementStatus } from '@/lib/appointment-management';
import { clinicLocalToday, shiftLocalDate, type CandidateDateWindow } from '@/lib/appointment-time';
import { isSameCandidate } from '@/lib/candidate-selection';

/**
 * Pure rules for the confirmed Appointment reschedule (SPEC-APT-005/006/016/017).
 * Everything here is ADVISORY: it only decides what the app OFFERS from known
 * capabilities and the device clock. The backend re-authorizes and revalidates
 * every proposal, withdrawal, and acceptance. No function here derives an end
 * or a duration: proposed intervals and candidate ends always come from the
 * backend.
 */

/**
 * Whether to offer "Propose a new time" (SPEC-APT-005) on the professional
 * detail: a CONFIRMED Appointment whose confirmed start is still in the future,
 * with no actionable pending proposal (BR-14 — the backend allows one), at a
 * Clinic whose KNOWN capabilities hold APPOINTMENT_RESCHEDULE, and no Clinical
 * Record Entry (SPEC-MED-010 BR-9). This is eligibility only: the
 * APPOINTMENT_MANAGEMENT Entitlement is applied on top by `managedActionGate`
 * (SPEC-APT-012 BR-61), and the backend stays authoritative.
 */
export function offersRescheduleProposal(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
  referenceInstant: Date,
): boolean {
  return (
    appointment.lifecycleState === 'CONFIRMED' &&
    isScheduledStartInFuture(appointment.currentScheduledStartAt, referenceInstant) &&
    appointment.pendingReschedule === null &&
    // SPEC-MED-010 BR-9: clinical documentation blocks rescheduling (advisory).
    !appointment.hasClinicalRecord &&
    clinic.capabilities.includes('APPOINTMENT_RESCHEDULE')
  );
}

/**
 * Whether to offer "Withdraw proposal" (SPEC-APT-016): the actionable pending
 * proposal was made by the Clinic, and the Clinic's KNOWN capabilities hold
 * APPOINTMENT_RESCHEDULE — any such actor may withdraw, not only the
 * proposer, and no Entitlement applies. A Guardian-originated proposal is
 * never withdrawable here.
 */
export function offersRescheduleWithdrawal(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment,
): boolean {
  return (
    appointment.pendingReschedule?.proposingContext === 'CLINIC' &&
    clinic.capabilities.includes('APPOINTMENT_RESCHEDULE')
  );
}

/**
 * The professional reschedule route for one Appointment. Besides the ids, it
 * carries the confirmed revision sequence of the row the detail displayed, so
 * the proposal is bound to the context the actor actually reviewed
 * (SPEC-APT-005 BR-26). It is only a token: the backend checks it.
 */
export function professionalRescheduleHref(
  clinicId: string,
  appointmentId: string,
  reviewedSequence: number,
) {
  return {
    pathname: '/professional/clinics/[clinicId]/appointments/[appointmentId]/reschedule',
    params: { clinicId, appointmentId, sequence: String(reviewedSequence) },
  } as const;
}

/** A route `sequence` param as a positive revision sequence, or `null`. */
export function parseReviewedSequence(value: string | string[] | undefined): number | null {
  if (typeof value !== 'string' || !/^[1-9]\d*$/.test(value)) return null;
  const sequence = Number(value);
  return Number.isSafeInteger(sequence) ? sequence : null;
}

/**
 * Whether a fresh schedule row is still the confirmed scheduling context the
 * actor reviewed on the detail: CONFIRMED, at the same revision sequence. If
 * not, the reschedule screen stops and asks for a new review rather than
 * proposing against a context nobody looked at.
 */
export function isReviewedConfirmedContext(
  appointment: ClinicScheduleAppointment,
  reviewedSequence: number,
): boolean {
  return (
    appointment.lifecycleState === 'CONFIRMED' &&
    appointment.currentScheduleRevisionSequence === reviewedSequence
  );
}

/** What a fresh schedule row means for the reschedule screen. */
export type RescheduleAppointmentClassification =
  | 'appointmentMissing'
  | 'changed'
  | 'notOffered'
  /** Eligible, but the Organization's APPOINTMENT_MANAGEMENT is known to be missing. */
  | 'entitlementUnavailable'
  /** Eligible, but that Entitlement could not be verified. */
  | 'entitlementUnverified'
  | 'proposable';

/**
 * Classifies a fresh schedule row for the reschedule screen, without side
 * effects so the screen can decide before rendering anything: gone from the
 * schedule; no longer the CONFIRMED revision the actor reviewed; still that
 * revision but no longer proposable (a proposal now exists, the start passed,
 * the capability was lost); still proposable but held back by the
 * Organization's APPOINTMENT_MANAGEMENT (missing or unverified, so no candidate
 * is read); or proposable.
 */
export function classifyRescheduleAppointment(
  clinic: ProfessionalClinic,
  appointment: ClinicScheduleAppointment | null,
  reviewedSequence: number | null,
  referenceInstant: Date,
  appointmentManagement: AppointmentManagementStatus,
): RescheduleAppointmentClassification {
  if (appointment === null) return 'appointmentMissing';
  if (reviewedSequence === null || !isReviewedConfirmedContext(appointment, reviewedSequence)) {
    return 'changed';
  }
  const gate = managedActionGate(
    offersRescheduleProposal(clinic, appointment, referenceInstant),
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
 * Calendar dates per candidate read. The backend accepts an inclusive range
 * whose end is at most 60 days after its start (SPEC-APT-017 BR-4); 60
 * inclusive dates stay within it. This bounds one request, not how far ahead a
 * professional may look: there is no business horizon.
 */
export const RESCHEDULE_CANDIDATE_RANGE_DAYS = 60;

/** One Clinic reschedule candidate read: an inclusive range of Clinic-local dates. */
export type RescheduleCandidateWindow = CandidateDateWindow;

/** The window of RESCHEDULE_CANDIDATE_RANGE_DAYS dates starting on `startDate`. */
export function rescheduleCandidateWindowFrom(startDate: string): RescheduleCandidateWindow {
  return { startDate, endDate: shiftLocalDate(startDate, RESCHEDULE_CANDIDATE_RANGE_DAYS - 1) };
}

/** The first window: Clinic-local today through today + 59 days. */
export function initialRescheduleCandidateWindow(
  schedulingTimezoneName: string,
  referenceInstant: Date = new Date(),
): RescheduleCandidateWindow {
  return rescheduleCandidateWindowFrom(clinicLocalToday(schedulingTimezoneName, referenceInstant));
}

/** The window starting the day after `window` ends: consecutive, no gap, no overlap, no limit. */
export function nextRescheduleCandidateWindow(
  window: RescheduleCandidateWindow,
): RescheduleCandidateWindow {
  return rescheduleCandidateWindowFrom(shiftLocalDate(window.endDate, 1));
}

/**
 * The window before `window`, never starting before Clinic-local `today`; `null`
 * when `window` already starts on or before today (no earlier dates to offer).
 */
export function previousRescheduleCandidateWindow(
  window: RescheduleCandidateWindow,
  today: string,
): RescheduleCandidateWindow | null {
  if (window.startDate <= today) return null;
  const start = shiftLocalDate(window.startDate, -RESCHEDULE_CANDIDATE_RANGE_DAYS);
  return rescheduleCandidateWindowFrom(start < today ? today : start);
}

/**
 * The window to read on (re)focus: the one already shown while it still
 * starts on or after Clinic-local today, otherwise the first window (the
 * Clinic-local date moved past it).
 */
export function currentRescheduleCandidateWindow(
  shown: RescheduleCandidateWindow | null,
  schedulingTimezoneName: string,
  referenceInstant: Date = new Date(),
): RescheduleCandidateWindow {
  const today = clinicLocalToday(schedulingTimezoneName, referenceInstant);
  return shown !== null && shown.startDate >= today ? shown : rescheduleCandidateWindowFrom(today);
}

/**
 * Whether a fresh schedule row carries an actionable Clinic-originated
 * proposal. After a failed proposal attempt (for example a lost response after
 * the server committed), the authoritative state then shows the operation as
 * effectively done: the screen returns to the detail, which shows it.
 */
export function hasActionableClinicProposal(
  appointment: ClinicScheduleAppointment | null,
): boolean {
  return appointment?.pendingReschedule?.proposingContext === 'CLINIC';
}

/**
 * After a failed withdrawal, whether the fresh read shows that proposal is no
 * longer pending (withdrawn by this or an earlier attempt, or otherwise
 * resolved): the outcome is then presented neutrally instead of as a failure.
 * Unknown when the fresh read found no Appointment.
 */
export function isRescheduleProposalNoLongerPending(
  proposalId: string,
  refreshed: ClinicScheduleAppointment | null,
): boolean {
  return refreshed !== null && refreshed.pendingReschedule?.proposalId !== proposalId;
}

/**
 * The start instant a candidate denotes: its Clinic-local civil time minus the
 * UTC offset the backend resolved it with. Exact, no timezone database
 * involved; used only to display the proposed interval.
 */
export function rescheduleCandidateStartIso(candidate: RescheduleCandidate): string {
  const [year, month, day] = candidate.localDate.split('-').map(Number);
  const [hourMinuteSecond, fraction = ''] = candidate.localTime.split('.');
  const [hour, minute, second] = hourMinuteSecond.split(':').map(Number);
  const milliseconds = Number(fraction.padEnd(3, '0').slice(0, 3));
  const civilAsUtcMs = Date.UTC(year, month - 1, day, hour, minute, second, milliseconds);
  return new Date(civilAsUtcMs - candidate.utcOffsetSeconds * 1000).toISOString();
}

/**
 * The stale-safe Clinic proposal for the row the actor reviewed: its id, the
 * selected candidate's start only, the trimmed reason, and the reviewed
 * confirmed revision sequence — never a newer one (SPEC-APT-005 BR-26).
 */
export function clinicRescheduleProposalRequestFor(
  appointment: ClinicScheduleAppointment,
  candidate: RescheduleCandidate,
  reason: string,
): ClinicRescheduleProposalRequest {
  return {
    appointmentId: appointment.id,
    candidate,
    reason: reason.trim(),
    expectedConfirmedRevisionSequence: appointment.currentScheduleRevisionSequence,
  };
}

/**
 * Whether the required Clinic reason is complete: some content after
 * trimming, as the backend normalizes it (`btrim` of whitespace, then
 * non-empty). The displayed text is never changed; only the request is
 * trimmed (`clinicRescheduleProposalRequestFor`).
 */
export function isClinicRescheduleReasonComplete(reason: string): boolean {
  return reason.trim().length > 0;
}

/**
 * Whether the Clinic proposal form's primary action ("Send proposal") is
 * enabled — a client-side UX guard only; the backend revalidates everything.
 * Every required input must be complete:
 * - the Appointment is still proposable (`proposable`);
 * - candidates are loaded (`candidates` is `null` while loading or failed) and
 *   the selected time is one of them — a server-returned candidate;
 * - the required reason is complete;
 * - nothing is loading, submitting, or leaving (`busy`).
 */
export function canSubmitClinicRescheduleProposal(form: {
  proposable: boolean;
  candidates: readonly RescheduleCandidate[] | null;
  selectedCandidate: RescheduleCandidate | null;
  reason: string;
  busy: boolean;
}): boolean {
  const { proposable, candidates, selectedCandidate, reason, busy } = form;
  return (
    proposable &&
    !busy &&
    candidates !== null &&
    selectedCandidate !== null &&
    candidates.some((candidate) => isSameCandidate(candidate, selectedCandidate)) &&
    isClinicRescheduleReasonComplete(reason)
  );
}

/**
 * Whether a Clinic proposal for a CONFIRMED Appointment is still within its
 * response window on the Guardian detail: its current and proposed starts are
 * both still in the future (device clock, advisory). A Guardian-originated
 * proposal is never accepted by a Guardian (SPEC-APT-006 BR-5).
 */
function isClinicRescheduleWithinResponseWindow(
  appointment: PetAppointment,
  referenceInstant: Date,
): boolean {
  const proposal = appointment.pendingReschedule;
  return (
    appointment.lifecycleState === 'CONFIRMED' &&
    proposal !== null &&
    proposal.proposingContext === 'CLINIC' &&
    appointment.currentScheduledStartAt !== null &&
    isScheduledStartInFuture(appointment.currentScheduledStartAt, referenceInstant) &&
    isScheduledStartInFuture(proposal.proposedStartAt, referenceInstant)
  );
}

/**
 * Whether to offer "Accept proposed time" on the Guardian detail
 * (SPEC-APT-006 BR-36): a Clinic proposal within its response window that the
 * Guardian view reports currently acceptable (SPEC-APT-011 BR-32). Advisory:
 * acceptance revalidates everything, including the Entitlement.
 */
export function offersRescheduleAcceptance(
  appointment: PetAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isClinicRescheduleWithinResponseWindow(appointment, referenceInstant) &&
    appointment.pendingReschedule?.currentlyAcceptable === true
  );
}

/**
 * Whether to show, instead of Accept, the generic "can't be accepted right
 * now" copy (SPEC-APT-006 BR-36): a Clinic proposal within its response window
 * that is not currently acceptable. The cause (scheduling or Entitlement) is
 * never shown, and the condition may recover.
 */
export function showsRescheduleNotCurrentlyAcceptable(
  appointment: PetAppointment,
  referenceInstant: Date,
): boolean {
  return (
    isClinicRescheduleWithinResponseWindow(appointment, referenceInstant) &&
    appointment.pendingReschedule?.currentlyAcceptable === false
  );
}

/**
 * Whether the professional detail notes that a projected proposal's time is no
 * longer available (SPEC-APT-012 BR-44, SPEC-APT-018 §5): the Clinic schedule
 * reports it not currently feasible. The proposal stays visible and
 * withdrawable; no reason is shown.
 */
export function isPendingRescheduleCurrentlyInfeasible(
  appointment: ClinicScheduleAppointment,
): boolean {
  return appointment.pendingReschedule?.currentlyFeasible === false;
}

/**
 * After an acceptance attempt failed (for example a retry after a lost
 * response), whether the fresh read shows that this very proposal was already
 * applied: no pending proposal any more, still CONFIRMED, and the current
 * confirmed interval is exactly the proposed one. Lets the screen present the
 * authoritative accepted state calmly instead of an alarming error.
 */
export function wasRescheduleProposalApplied(
  proposal: NonNullable<PetAppointment['pendingReschedule']>,
  refreshed: PetAppointment,
): boolean {
  return (
    refreshed.pendingReschedule === null &&
    refreshed.lifecycleState === 'CONFIRMED' &&
    refreshed.currentScheduledStartAt !== null &&
    refreshed.currentScheduledEndAt !== null &&
    Date.parse(refreshed.currentScheduledStartAt) === Date.parse(proposal.proposedStartAt) &&
    Date.parse(refreshed.currentScheduledEndAt) === Date.parse(proposal.proposedEndAt)
  );
}

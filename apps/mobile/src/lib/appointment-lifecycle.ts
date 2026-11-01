/**
 * Pure mapping from an Appointment's backend lifecycle_state to the actions
 * Milestone F's Guardian-facing UI may offer. This is a literal transcription
 * of the state-transition diagrams in SPEC-APT-003 §4 (cancel) and
 * SPEC-APT-004 §4 (reschedule) — not an inferred or invented rule — plus the
 * pending-request time bound of SPEC-APT-003 BR-23 / SPEC-APT-004 BR-27.
 * Confirmed Appointment reschedule proposals (SPEC-APT-005/006) are out of
 * Milestone F scope, so CONFIRMED never allows reschedule here.
 *
 * `EXPIRED` (SPEC-APT-015) is a known terminal state. This app version must be
 * available in an environment before the backend starts materializing
 * `EXPIRED` there: older builds don't know the value.
 */
export type AppointmentLifecycleState =
  'REQUESTED' | 'CONFIRMED' | 'CANCELLED' | 'COMPLETED' | 'NO_SHOW' | 'EXPIRED';

/** The closed set of lifecycle states this app version knows; anything else is malformed. */
export const APPOINTMENT_LIFECYCLE_STATES: readonly AppointmentLifecycleState[] = [
  'REQUESTED',
  'CONFIRMED',
  'CANCELLED',
  'COMPLETED',
  'NO_SHOW',
  'EXPIRED',
];

export function isAppointmentLifecycleState(value: unknown): value is AppointmentLifecycleState {
  return (
    typeof value === 'string' && (APPOINTMENT_LIFECYCLE_STATES as readonly string[]).includes(value)
  );
}

/**
 * appointment_schedule_revisions.revision_context's domain (SQL check
 * constraint in 20260826163000_appointment_schema_and_scheduling_history.sql)
 * is a strict subset of the full Appointment lifecycle: a scheduling
 * revision is only ever REQUESTED or CONFIRMED, never CANCELLED/COMPLETED/
 * NO_SHOW.
 */
export type AppointmentScheduleRevisionContext = Extract<
  AppointmentLifecycleState,
  'REQUESTED' | 'CONFIRMED'
>;

/**
 * Whether a resolved scheduled start instant (backend ISO timestamptz) is
 * strictly after `referenceInstant`. Compares absolute instants only — never
 * Clinic-local wall-clock reconstruction or formatted strings. An unparseable
 * value is not in the future.
 */
export function isScheduledStartInFuture(startIso: string, referenceInstant: Date): boolean {
  const startMs = Date.parse(startIso);
  return Number.isFinite(startMs) && startMs > referenceInstant.getTime();
}

/**
 * Whether a REQUESTED Appointment is still a pending request (SPEC-APT-001
 * BR-35): its latest requested start — the relevant scheduled interval the
 * reads return for a never-confirmed Appointment — is strictly in the future.
 * Once it isn't, the request is logically expired (SPEC-APT-015 BR-4) even
 * while still stored as REQUESTED; the client never relabels it EXPIRED.
 *
 * ADVISORY presentation only: the device clock may be wrong, and the backend
 * enforces authoritative time. A missing start (never expected from the reads)
 * is treated as unknown, leaving the decision to the backend.
 */
export function isPendingRequestedAppointment(
  state: AppointmentLifecycleState,
  requestedStartIso: string | null,
  referenceInstant: Date,
): boolean {
  if (state !== 'REQUESTED') return false;
  if (requestedStartIso === null) return true;
  return isScheduledStartInFuture(requestedStartIso, referenceInstant);
}

/**
 * Whether a Guardian may be offered Cancel: a CONFIRMED Appointment only while
 * its latest confirmed start — the relevant scheduled interval the Guardian
 * read returns for it — is strictly in the future (SPEC-APT-003 BR-31); a
 * REQUESTED one only while it is still a pending request (BR-2/BR-23).
 * Terminal states — including EXPIRED (BR-21) — never.
 *
 * ADVISORY presentation only: the backend enforces both cutoffs with its own
 * time. A missing start (never expected from the reads) leaves the decision to
 * the backend.
 */
export function canCancelAppointment(
  state: AppointmentLifecycleState,
  currentScheduledStartIso: string | null,
  referenceInstant: Date,
): boolean {
  if (state === 'CONFIRMED') {
    return (
      currentScheduledStartIso === null ||
      isScheduledStartInFuture(currentScheduledStartIso, referenceInstant)
    );
  }
  return isPendingRequestedAppointment(state, currentScheduledStartIso, referenceInstant);
}

/**
 * A CONFIRMED Appointment whose latest confirmed start has been reached and
 * that the Clinic has not resolved yet (SPEC-APT-011 BR-34): it stays
 * CONFIRMED, the Guardian can no longer cancel it (SPEC-APT-003 BR-31), and
 * the Clinic will record its outcome. Advisory device-clock presentation.
 */
export function isAwaitingClinicResolution(
  state: AppointmentLifecycleState,
  currentScheduledStartIso: string | null,
  referenceInstant: Date,
): boolean {
  return (
    state === 'CONFIRMED' &&
    currentScheduledStartIso !== null &&
    !isScheduledStartInFuture(currentScheduledStartIso, referenceInstant)
  );
}

export type GuardianCancellationView = {
  /** Offer the Guardian Cancel action. */
  offersCancel: boolean;
  /** Show "the scheduled time has passed; the clinic will update its status". */
  awaitingClinicResolution: boolean;
  /** The backend rejected a cancellation of this confirmed start (BR-31). */
  closedByBackend: boolean;
};

/**
 * Guardian cancellation presentation for one Appointment. The device clock
 * decides first (advisory); `backendClosedForStartIso` is the confirmed start
 * for which the backend already rejected a Guardian cancellation because that
 * start had been reached (SPEC-APT-003 BR-31). It closes Cancel even when the
 * device clock is behind, and only for that same start: a later confirmed
 * start (an accepted reschedule) or another lifecycle state ignores it.
 */
export function guardianCancellationView(
  state: AppointmentLifecycleState,
  currentScheduledStartIso: string | null,
  referenceInstant: Date,
  backendClosedForStartIso: string | null,
): GuardianCancellationView {
  const closedByBackend =
    state === 'CONFIRMED' &&
    backendClosedForStartIso !== null &&
    backendClosedForStartIso === currentScheduledStartIso;
  return {
    offersCancel:
      !closedByBackend && canCancelAppointment(state, currentScheduledStartIso, referenceInstant),
    awaitingClinicResolution:
      closedByBackend ||
      isAwaitingClinicResolution(state, currentScheduledStartIso, referenceInstant),
    closedByBackend,
  };
}

export type GuardianCancellationPresentation = {
  /** Show the Cancel action that opens the panel. */
  showCancelAction: boolean;
  /** Keep the cancellation panel (reason + submit) on screen. */
  showPanel: boolean;
  /** Show "the scheduled time has passed; the clinic will update its status". */
  showAwaitingNote: boolean;
};

/**
 * What the Guardian detail renders for cancellation. `view.offersCancel`
 * (device clock, advisory) decides only whether the panel may be OPENED. Once
 * opened, the panel stays while the Appointment is still REQUESTED or
 * CONFIRMED, even if the device clock crosses the start meanwhile: the
 * Guardian may submit, and the backend decides (SPEC-APT-003 BR-23/BR-31).
 * It closes when the backend rejected the cancellation for this confirmed
 * start (`view.closedByBackend`) or the Appointment is no longer cancellable
 * in any state (terminal). While the panel is open the "time has passed" note
 * is withheld, so the screen never shows a form and a note that contradict
 * each other; after a backend rejection the note appears.
 */
export function guardianCancellationPresentation(
  view: GuardianCancellationView,
  state: AppointmentLifecycleState,
  panelOpen: boolean,
): GuardianCancellationPresentation {
  const showPanel =
    panelOpen && (state === 'REQUESTED' || state === 'CONFIRMED') && !view.closedByBackend;
  return {
    showCancelAction: view.offersCancel && !showPanel,
    showPanel,
    showAwaitingNote: view.awaitingClinicResolution && !showPanel,
  };
}

/** Only a still-pending REQUESTED Appointment may be rescheduled (SPEC-APT-004 BR-3/BR-27). */
export function canRescheduleRequestedAppointment(
  state: AppointmentLifecycleState,
  currentScheduledStartIso: string | null,
  referenceInstant: Date,
): boolean {
  return isPendingRequestedAppointment(state, currentScheduledStartIso, referenceInstant);
}

/**
 * The cancellation reason to show on an Appointment (SPEC-APT-011 BR-31): the
 * recorded reason of a CANCELLED Appointment, or `null` — for any other state,
 * and for a cancellation recorded without a reason. Never falls back to the
 * reason for visit or any other text.
 */
export function shownCancellationReason(
  state: AppointmentLifecycleState,
  cancellationReason: string | null,
): string | null {
  return state === 'CANCELLED' ? cancellationReason : null;
}

/**
 * Whether the Guardian Appointment detail shows its "a veterinarian is
 * assigned" note: only while a current Veterinarian Assignment exists (an
 * entry with no effective end). Assignment is optional (SPEC-APT-012 BR-17;
 * SPEC-APT-009 completes without one), so its absence is not a pending or
 * incomplete state and nothing is shown for it. No veterinarian identity is
 * read or shown.
 */
export function showsVeterinarianAssigned(
  assignmentHistory: readonly { effectiveEnd: string | null }[],
): boolean {
  return assignmentHistory.some((entry) => entry.effectiveEnd === null);
}

/**
 * SPEC-APT-011 §6 / SPEC-APT-012 §8: REQUESTED/CONFIRMED are upcoming; the
 * rest — COMPLETED, CANCELLED, NO_SHOW, and EXPIRED — are historical. A
 * still-stored REQUESTED whose time has passed stays REQUESTED here until the
 * backend records EXPIRED.
 */
export function isUpcomingAppointmentState(state: AppointmentLifecycleState): boolean {
  return state === 'REQUESTED' || state === 'CONFIRMED';
}

/**
 * The localized-label i18n key for a lifecycle state — the raw backend enum
 * value must never be shown directly in the UI (SPEC-APT-011 BR-8/BR-9: the
 * Guardian must be able to distinguish states, but they're product-facing
 * concepts, not database literals).
 */
type LifecycleLabelKey =
  | 'appointments.lifecycleRequested'
  | 'appointments.lifecycleConfirmed'
  | 'appointments.lifecycleCancelled'
  | 'appointments.lifecycleCompleted'
  | 'appointments.lifecycleNoShow'
  | 'appointments.lifecycleExpired';

const LIFECYCLE_LABEL_KEYS: Record<AppointmentLifecycleState, LifecycleLabelKey> = {
  REQUESTED: 'appointments.lifecycleRequested',
  CONFIRMED: 'appointments.lifecycleConfirmed',
  CANCELLED: 'appointments.lifecycleCancelled',
  COMPLETED: 'appointments.lifecycleCompleted',
  NO_SHOW: 'appointments.lifecycleNoShow',
  EXPIRED: 'appointments.lifecycleExpired',
};

export function lifecycleLabelKey(state: AppointmentLifecycleState) {
  return LIFECYCLE_LABEL_KEYS[state];
}

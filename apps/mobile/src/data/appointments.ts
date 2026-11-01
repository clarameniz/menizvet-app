import {
  parseCurrentScheduleSourceColumns,
  parsePendingRescheduleColumns,
  type CurrentScheduleSource,
  type PendingRescheduleProposal,
} from '@/data/clinic-appointment-schedule';
import {
  isAppointmentLifecycleState,
  type AppointmentLifecycleState,
  type AppointmentScheduleRevisionContext,
} from '@/lib/appointment-lifecycle';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the exact deployed contracts, updated for the Slice 16 Guardian
 * requestable-times enhancement
 * (supabase/migrations/20260920120000_standard_appointment_duration_and_candidate_times.sql):
 *
 * - get_requestable_appointment_start_times(p_clinic_id, p_start_date,
 *   p_end_date) — SPEC-APT-014. Granted to authenticated, no account
 *   verification or Guardianship precondition (Clinic-level, not
 *   Pet-specific). Advisory only: a returned candidate is never a
 *   reservation or guarantee (BR-16/BR-17).
 * - request_appointment(...) — SPEC-APT-001 BR-29/30/31/32/34. The Guardian
 *   supplies only a start (local date, local time, UTC offset); the backend
 *   derives the end from the Clinic's *current* standard Appointment
 *   duration and rejects deterministically if none is configured. No
 *   Guardian-supplied end parameter exists in this contract. Atomically
 *   creates the Appointment in REQUESTED, its initial requested Schedule
 *   Revision, and the required Appointment-derived Care Authorization
 *   (SPEC-ACC-001). There is no separate consent parameter — the Guardian's
 *   explicit confirmation immediately before calling this RPC *is* the
 *   grant.
 * - reschedule_requested_appointment(...) — SPEC-APT-004 BR-22/23/24. Same
 *   start-only contract as request_appointment; only valid while REQUESTED;
 *   rejects a same-resolved-interval no-op and a past time.
 * - cancel_appointment(p_appointment_id, p_cancelling_context, p_reason) —
 *   latest definition in
 *   supabase/migrations/20261006090000_stale_safe_clinic_appointment_cancellation.sql,
 *   whose extra p_expected_schedule_revision_sequence is for CLINIC
 *   cancellations only and is never sent here. Mobile always passes
 *   p_cancelling_context: 'GUARDIAN' (SPEC-APT-003). Neither this nor
 *   reschedule_requested_appointment take an expected-revision parameter —
 *   both use pessimistic row locking server-side, so the client-visible
 *   "stale state" signal is a lifecycle mismatch or Availability-conflict
 *   error rather than a dedicated stale-revision SQLSTATE.
 * - get_pet_appointments(p_pet_id) — Pet-scoped, current-Guardianship-gated
 *   (SPEC-APT-011); latest definition in
 *   supabase/migrations/20261007090000_guardian_appointment_cancellation_reason.sql,
 *   which appends `cancellation_reason` (BR-31): the reason recorded by a
 *   CANCELLED Appointment's cancellation, NULL otherwise. Returns only
 *   *current* scheduling context — there is no per-Pet-across-Pets aggregate
 *   read, so /appointments is Pet-first. Its `pending_reschedule_*` columns
 *   project only an actionable pending proposal (SPEC-APT-011 BR-32,
 *   SPEC-APT-005 BR-31) and are validated strictly.
 * - accept_appointment_reschedule_proposal(p_proposal_id, p_accepting_context)
 *   — SPEC-APT-006, latest definition in
 *   supabase/migrations/20261008090000_confirmed_appointment_reschedule_and_withdrawal.sql.
 *   This app accepts only Clinic-originated proposals, in the GUARDIAN
 *   context; the stored proposed interval is established unchanged (BR-28).
 * - accept_requested_appointment_alternative_time(p_proposal_id) —
 *   SPEC-APT-019, supabase/migrations/20261010090000_requested_appointment_alternative_time.sql.
 *   Accepts a Clinic alternative time for a REQUESTED Appointment: the request
 *   changes to exactly the stored interval and stays REQUESTED; the Clinic
 *   still has to confirm it. No stale token.
 * - get_pet_appointments also projects, since 20261010090000, the provenance of
 *   the relevant scheduled interval (`current_schedule_source_*`,
 *   SPEC-APT-011 BR-33), validated strictly; and, since
 *   20261016090000_reschedule_proposal_current_feasibility.sql,
 *   `pending_reschedule_currently_acceptable` (SPEC-APT-011 BR-32): a boolean
 *   exactly when a proposal is projected, null otherwise.
 * - get_pet_appointments also projects, since
 *   20261106090000_guardian_appointment_medical_access_revocation.sql,
 *   `medical_access_state` (SPEC-APT-011 BR-35): ACTIVE, REVOKED or INACTIVE —
 *   the operational state of the Appointment's own Care Authorization, never
 *   its identifier or metadata. Validated strictly.
 * - revoke_my_appointment_care_authorization(p_appointment_id) — SPEC-ACC-002
 *   §16, same migration. Appointment-keyed: the server derives the Pet, the
 *   caller's current Guardianship and the Care Authorization. Outcomes
 *   REVOKED / ALREADY_INACTIVE; a foreign, unknown or no-longer-guarded
 *   Appointment is one uniform 42501.
 * - get_appointment_scheduling_history / get_appointment_veterinarian_assignment_history
 *   (Slice 9) — Guardian- or Clinic-schedule-capability-gated, full revision
 *   and Assignment history for one Appointment.
 *
 * Every exported function settles into { data, error } and never rejects —
 * this domain is entirely authenticated, mutation-heavy, and user-triggered
 * (request/cancel/reschedule), so every call gets the same network-rejection
 * guard data/pets.ts's updatePetProfile established, not only the historically
 * affected one.
 */
export type AppointmentsResult<T> = { data: T; error: null } | { data: null; error: string };

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

// ---------------------------------------------------------------------------
// get_pet_appointments
// ---------------------------------------------------------------------------

/**
 * The Appointment's actionable pending reschedule proposal (SPEC-APT-011
 * BR-32): its id (to accept it), origin, exact stored proposed interval, and
 * reason — a Clinic proposal always has one, visible to Guardians
 * (SPEC-APT-005 BR-30). Never the Appointment's current interval.
 *
 * `currentlyAcceptable` is the Guardian current acceptability (SPEC-APT-005
 * BR-35): whether the current Guardian could accept it now. It is `false` for
 * a Guardian's own proposal, an infeasible one, or (for a confirmed
 * reschedule) when the Clinic cannot take on a new commitment — never with a
 * reason. Acceptance stays authoritative.
 */
export type PendingReschedule = PendingRescheduleProposal & { currentlyAcceptable: boolean };

/** The accepted proposal that established the relevant scheduled interval (SPEC-APT-011 BR-33). */
export type ScheduleSource = CurrentScheduleSource;

/**
 * The Appointment's medical-access state (SPEC-APT-011 BR-35): `ACTIVE` while
 * the Clinic may use the Appointment's medical access and a current Guardian
 * may withdraw it, `REVOKED` once a Guardian withdrew it, `INACTIVE` once it
 * ended with the Appointment (cancellation, no-show, expiry).
 */
export type MedicalAccessState = 'ACTIVE' | 'REVOKED' | 'INACTIVE';

const MEDICAL_ACCESS_STATES: readonly MedicalAccessState[] = ['ACTIVE', 'REVOKED', 'INACTIVE'];

export function isMedicalAccessState(value: unknown): value is MedicalAccessState {
  return MEDICAL_ACCESS_STATES.includes(value as MedicalAccessState);
}

export type PetAppointment = {
  id: string;
  clinicId: string;
  requestingUserId: string;
  reasonForVisit: string;
  guardianNotes: string | null;
  lifecycleState: AppointmentLifecycleState;
  createdAt: string;
  currentScheduledStartAt: string | null;
  currentScheduledEndAt: string | null;
  currentSchedulingTimezoneName: string | null;
  currentVeterinarianClinicAssignmentId: string | null;
  pendingReschedule: PendingReschedule | null;
  /**
   * The reason recorded when this Appointment was cancelled (SPEC-APT-011
   * BR-31) — by a Guardian or by the Clinic. `null` when not CANCELLED, or
   * when a Guardian cancelled without a reason. Never the reason for visit.
   */
  cancellationReason: string | null;
  /** Provenance of the relevant scheduled interval, or `null` (SPEC-APT-011 BR-33). */
  currentScheduleSource: ScheduleSource | null;
  /** The Appointment's medical-access state (SPEC-APT-011 BR-35). */
  medicalAccessState: MedicalAccessState;
};

export type PetAppointmentRow = {
  id: string;
  clinic_id: string;
  requesting_user_id: string;
  reason_for_visit: string;
  guardian_notes: string | null;
  lifecycle_state: AppointmentLifecycleState;
  created_at: string;
  current_scheduled_start_at: string | null;
  current_scheduled_end_at: string | null;
  current_scheduling_timezone_name: string | null;
  current_veterinarian_clinic_assignment_id: string | null;
  pending_reschedule_proposal_id: string | null;
  pending_reschedule_proposal_state: string | null;
  pending_reschedule_proposing_context: string | null;
  pending_reschedule_proposed_start_at: string | null;
  pending_reschedule_proposed_end_at: string | null;
  pending_reschedule_proposed_timezone_name: string | null;
  pending_reschedule_reason: string | null;
  cancellation_reason: string | null;
  current_schedule_source_proposal_id: string | null;
  current_schedule_source_proposing_context: string | null;
  pending_reschedule_currently_acceptable: boolean | null;
  medical_access_state: MedicalAccessState;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
// Rows reaching this mapper from getPetAppointments have passed
// hasKnownLifecycleStates, which rejects a malformed pending proposal or
// schedule provenance; the `?? null` only keeps the type total.
export function fromPetAppointmentRow(row: PetAppointmentRow): PetAppointment {
  const pendingReschedule: PendingReschedule | null =
    parsePendingRescheduleColumns(row, row.lifecycle_state, 'currentlyAcceptable') ?? null;
  const currentScheduleSource: ScheduleSource | null =
    parseCurrentScheduleSourceColumns(row, row.lifecycle_state) ?? null;

  return {
    id: row.id,
    clinicId: row.clinic_id,
    requestingUserId: row.requesting_user_id,
    reasonForVisit: row.reason_for_visit,
    guardianNotes: row.guardian_notes,
    lifecycleState: row.lifecycle_state,
    createdAt: row.created_at,
    currentScheduledStartAt: row.current_scheduled_start_at,
    currentScheduledEndAt: row.current_scheduled_end_at,
    currentSchedulingTimezoneName: row.current_scheduling_timezone_name,
    currentVeterinarianClinicAssignmentId: row.current_veterinarian_clinic_assignment_id,
    pendingReschedule,
    cancellationReason: row.cancellation_reason,
    currentScheduleSource,
    medicalAccessState: row.medical_access_state,
  };
}

/** Normalized `error` when get_pet_appointments returns a payload this app version can't represent. */
export const PET_APPOINTMENTS_MALFORMED = 'PET_APPOINTMENTS_MALFORMED';

/**
 * A row's `cancellation_reason` as the backend guarantees it (SPEC-APT-011
 * BR-31): present on every row; `null`, or a non-blank string only on a
 * CANCELLED Appointment (the lifecycle-event check constraint stores reasons
 * trimmed and non-empty).
 */
function hasValidCancellationReason(row: Record<string, unknown>): boolean {
  const reason = row.cancellation_reason;
  if (reason === null) return true;
  return (
    typeof reason === 'string' && reason.trim().length > 0 && row.lifecycle_state === 'CANCELLED'
  );
}

/**
 * A row's `pending_reschedule_*` columns as the backend guarantees them
 * (SPEC-APT-011 BR-32): no proposal at all, or one complete actionable
 * PENDING proposal — a confirmed reschedule on a CONFIRMED Appointment, or a
 * Clinic alternative time on a REQUESTED one — with a UUID id, a known
 * proposing context, a real interval in a valid timezone, and a reason
 * whenever the Clinic proposed it. Anything partial or incoherent is malformed.
 */
function hasValidPendingReschedule(row: Record<string, unknown>): boolean {
  return (
    isAppointmentLifecycleState(row.lifecycle_state) &&
    parsePendingRescheduleColumns(row, row.lifecycle_state, 'currentlyAcceptable') !== undefined
  );
}

/**
 * A row's `current_schedule_source_*` columns as the backend guarantees them
 * (SPEC-APT-011 BR-33): both null, or a UUID and a known proposing context —
 * always the Clinic on a REQUESTED Appointment. Missing or partial is malformed.
 */
function hasValidScheduleSource(row: Record<string, unknown>): boolean {
  return (
    isAppointmentLifecycleState(row.lifecycle_state) &&
    parseCurrentScheduleSourceColumns(row, row.lifecycle_state) !== undefined
  );
}

/**
 * Exported for unit testing: whether the payload is an array of rows whose
 * `lifecycle_state` is a lifecycle state this app version knows (including
 * `EXPIRED`, SPEC-APT-015), whose `cancellation_reason` is valid, and whose
 * pending reschedule proposal, if any, is complete and coherent, and whose
 * `medical_access_state` is one this app version knows. An unknown
 * state would otherwise reach the status badge and label maps as an
 * unhandled state, a reason outside a CANCELLED Appointment would be shown as
 * one, a partial proposal would silently disappear or be offered for
 * acceptance with missing facts, and an unknown medical-access state could
 * offer or hide the withdrawal wrongly, so any of them rejects the whole read
 * instead. Other columns keep this read's existing trusted reshaping.
 */
export function hasKnownLifecycleStates(raw: unknown): raw is PetAppointmentRow[] {
  return (
    Array.isArray(raw) &&
    raw.every(
      (row) =>
        typeof row === 'object' &&
        row !== null &&
        isAppointmentLifecycleState((row as Record<string, unknown>).lifecycle_state) &&
        hasValidCancellationReason(row as Record<string, unknown>) &&
        hasValidPendingReschedule(row as Record<string, unknown>) &&
        hasValidScheduleSource(row as Record<string, unknown>) &&
        isMedicalAccessState((row as Record<string, unknown>).medical_access_state),
    )
  );
}

/**
 * Pet-scoped (never accepts a User id — current_domain_user_id() resolves the
 * caller server-side). Re-verifies current Guardianship itself; a Pet the
 * caller does not currently guard raises 42501, mapped by
 * mapAppointmentErrorToKey. A payload with an unknown lifecycle state settles
 * into PET_APPOINTMENTS_MALFORMED.
 */
export async function getPetAppointments(
  petId: string,
): Promise<AppointmentsResult<PetAppointment[]>> {
  try {
    const { data, error } = await supabase.rpc('get_pet_appointments', { p_pet_id: petId });

    if (error) {
      return { data: null, error: error.message };
    }

    const rows: unknown = data ?? [];
    if (!hasKnownLifecycleStates(rows)) {
      return { data: null, error: PET_APPOINTMENTS_MALFORMED };
    }

    return { data: rows.map(fromPetAppointmentRow), error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// get_requestable_appointment_start_times
// ---------------------------------------------------------------------------

export type RequestableCandidate = {
  localDate: string;
  localTime: string;
  utcOffsetSeconds: number;
};

export type RequestableCandidateRow = {
  candidate_local_date: string;
  candidate_local_time: string;
  utc_offset_seconds: number;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
export function fromRequestableCandidateRow(row: RequestableCandidateRow): RequestableCandidate {
  return {
    localDate: row.candidate_local_date,
    localTime: row.candidate_local_time,
    utcOffsetSeconds: row.utc_offset_seconds,
  };
}

/**
 * Guardian-facing, advisory-only read (SPEC-APT-014). `startDate`/`endDate`
 * are plain Clinic-local calendar dates ("YYYY-MM-DD") — never resolved
 * against any offset client-side, since a bare date has no time-of-day and
 * therefore no DST ambiguity/nonexistence question. A returned candidate is
 * never a reservation or guarantee: request_appointment and
 * reschedule_requested_appointment independently re-validate current
 * Availability and the Clinic's current standard duration at submission
 * time regardless of what this read most recently returned (SPEC-APT-001
 * BR-32, SPEC-APT-004 BR-25).
 */
export async function getRequestableAppointmentStartTimes(
  clinicId: string,
  startDate: string,
  endDate: string,
): Promise<AppointmentsResult<RequestableCandidate[]>> {
  try {
    const { data, error } = await supabase.rpc('get_requestable_appointment_start_times', {
      p_clinic_id: clinicId,
      p_start_date: startDate,
      p_end_date: endDate,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return {
      data: ((data ?? []) as RequestableCandidateRow[]).map(fromRequestableCandidateRow),
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// request_appointment
// ---------------------------------------------------------------------------

export type RequestAppointmentInput = {
  petId: string;
  clinicId: string;
  candidate: RequestableCandidate;
  reasonForVisit: string;
  guardianNotes: string | null;
};

/**
 * Calls only the approved request_appointment RPC. The caller must have
 * already presented and obtained the explicit Care Authorization confirmation
 * (SPEC-ACC-001 BR-16) before invoking this — there is no
 * p_accept_care_authorization parameter; the RPC call itself is the grant.
 * `candidate` must be a value returned verbatim by
 * getRequestableAppointmentStartTimes: the Guardian no longer supplies an end
 * date/time/offset, and the backend derives the end from the Clinic's
 * current standard Appointment duration (SPEC-APT-001 BR-29/30). Returns
 * only the new Appointment's id, matching the RPC's own return type; callers
 * re-read via getPetAppointments rather than constructing an Appointment
 * from submitted form values.
 */
export async function requestAppointment(
  input: RequestAppointmentInput,
): Promise<AppointmentsResult<{ appointmentId: string }>> {
  try {
    const { data, error } = await supabase.rpc('request_appointment', {
      p_pet_id: input.petId,
      p_clinic_id: input.clinicId,
      p_start_local_date: input.candidate.localDate,
      p_start_local_time: input.candidate.localTime,
      p_start_utc_offset_seconds: input.candidate.utcOffsetSeconds,
      p_reason_for_visit: input.reasonForVisit,
      p_guardian_notes: input.guardianNotes,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return { data: { appointmentId: data as string }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// reschedule_requested_appointment
// ---------------------------------------------------------------------------

/**
 * Only valid while the Appointment is REQUESTED (SPEC-APT-004). `candidate`
 * must be a value returned verbatim by getRequestableAppointmentStartTimes;
 * the Guardian no longer supplies an end date/time/offset, and the backend
 * derives it from the Clinic's *current* standard Appointment duration —
 * not necessarily the duration that produced the Appointment's existing
 * scheduling context (SPEC-APT-004 BR-23). No optimistic update: callers
 * must re-read via getPetAppointments/getAppointmentSchedulingHistory after a
 * successful result rather than trusting the submitted candidate.
 */
export async function rescheduleRequestedAppointment(
  appointmentId: string,
  candidate: RequestableCandidate,
): Promise<AppointmentsResult<{ appointmentId: string }>> {
  try {
    const { data, error } = await supabase.rpc('reschedule_requested_appointment', {
      p_appointment_id: appointmentId,
      p_start_local_date: candidate.localDate,
      p_start_local_time: candidate.localTime,
      p_start_utc_offset_seconds: candidate.utcOffsetSeconds,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return { data: { appointmentId: data as string }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// cancel_appointment
// ---------------------------------------------------------------------------

/**
 * Always calls with p_cancelling_context: 'GUARDIAN' — this app never acts in
 * the CLINIC context. A Guardian cancellation reason is optional
 * (SPEC-APT-003 BR-9); pass null when not supplied, never ''.
 */
export async function cancelAppointment(
  appointmentId: string,
  reason: string | null,
): Promise<AppointmentsResult<{ appointmentId: string }>> {
  try {
    const { data, error } = await supabase.rpc('cancel_appointment', {
      p_appointment_id: appointmentId,
      p_cancelling_context: 'GUARDIAN',
      p_reason: reason,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return { data: { appointmentId: data as string }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// revoke_my_appointment_care_authorization
// ---------------------------------------------------------------------------

/**
 * Outcome of withdrawing an Appointment's medical access (SPEC-ACC-002 BR-58):
 * `withdrawn` (REVOKED), `alreadyInactive` (an earlier attempt, another
 * Guardian, cancellation, no-show or expiry already ended it — a normal retry
 * result, never an error), `unavailable` (the uniform 42501: the Appointment
 * is not one of a Pet the caller currently guards), `authenticationRequired`
 * (28000), or `failed` (anything else, including no response).
 */
export type MedicalAccessWithdrawal =
  | { kind: 'withdrawn' }
  | { kind: 'alreadyInactive' }
  | { kind: 'unavailable' }
  | { kind: 'authenticationRequired' }
  | { kind: 'failed' };

/**
 * Appointment-keyed: only the Appointment id is sent; the backend derives the
 * Pet, the caller's current Guardianship and the Care Authorization. Never
 * retried here — callers re-read getPetAppointments, whose
 * `medicalAccessState` is authoritative.
 */
export async function withdrawAppointmentMedicalAccess(
  appointmentId: string,
): Promise<MedicalAccessWithdrawal> {
  if (!UUID_PATTERN.test(appointmentId)) return { kind: 'unavailable' };

  try {
    const { data, error } = await supabase.rpc('revoke_my_appointment_care_authorization', {
      p_appointment_id: appointmentId,
    });

    if (error) {
      if (error.code === '42501') return { kind: 'unavailable' };
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      return { kind: 'failed' };
    }

    const outcome =
      typeof data === 'object' && data !== null && Object.keys(data).length === 1
        ? (data as { outcome?: unknown }).outcome
        : undefined;
    if (outcome === 'REVOKED') return { kind: 'withdrawn' };
    if (outcome === 'ALREADY_INACTIVE') return { kind: 'alreadyInactive' };
    return { kind: 'failed' };
  } catch {
    return { kind: 'failed' };
  }
}

// ---------------------------------------------------------------------------
// accept_appointment_reschedule_proposal
// ---------------------------------------------------------------------------

/** Normalized `error` for a proposal id that can't be a valid acceptance request. */
export const RESCHEDULE_ACCEPTANCE_INVALID_REQUEST = 'RESCHEDULE_ACCEPTANCE_INVALID_REQUEST';

/** Normalized `error` for a success payload that isn't the accepted proposal's id. */
export const RESCHEDULE_ACCEPTANCE_MALFORMED = 'RESCHEDULE_ACCEPTANCE_MALFORMED';

// Same UUID convention as data/clinic-appointment-schedule.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Accepts a Clinic-originated reschedule proposal in the GUARDIAN context
 * (SPEC-APT-006). The proposal id is the whole request: a proposal is
 * immutable and bound to the confirmed scheduling context it replaces, so the
 * backend rejects it if anything it was based on has changed (BR-15), and
 * re-verifies current Guardianship, the Clinic's Entitlement, Availability,
 * the assigned Veterinarian, and the absence of clinical records. On
 * success the stored interval becomes the new confirmed time (BR-28) and the
 * backend sends the APPOINTMENT_RESCHEDULE_ACCEPTED Communications. Never
 * retried here: a repeated acceptance fails as no longer actionable (BR-33),
 * so callers always re-read getPetAppointments to learn the outcome.
 */
export async function acceptRescheduleProposal(
  proposalId: string,
): Promise<AppointmentsResult<{ proposalId: string }>> {
  if (!UUID_PATTERN.test(proposalId)) {
    return { data: null, error: RESCHEDULE_ACCEPTANCE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('accept_appointment_reschedule_proposal', {
      p_proposal_id: proposalId,
      p_accepting_context: 'GUARDIAN',
    });

    if (error) {
      return { data: null, error: error.message };
    }

    if (typeof data !== 'string' || data.toLowerCase() !== proposalId.toLowerCase()) {
      return { data: null, error: RESCHEDULE_ACCEPTANCE_MALFORMED };
    }

    return { data: { proposalId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// accept_requested_appointment_alternative_time
// ---------------------------------------------------------------------------

/**
 * Accepts a Clinic alternative time for a REQUESTED Appointment
 * (SPEC-APT-019). The proposal id is the whole request — it binds the
 * requested context it would replace, so no stale token exists. The backend
 * re-verifies current Guardianship (no Entitlement gate, BR-4), actionability,
 * and the feasibility of the stored interval; on success the request becomes
 * exactly that interval and stays REQUESTED (the Clinic still confirms it), and
 * no Communication is sent. Never retried: callers re-read getPetAppointments.
 */
export async function acceptRequestedAlternativeTime(
  proposalId: string,
): Promise<AppointmentsResult<{ proposalId: string }>> {
  if (!UUID_PATTERN.test(proposalId)) {
    return { data: null, error: RESCHEDULE_ACCEPTANCE_INVALID_REQUEST };
  }

  try {
    const { data, error } = await supabase.rpc('accept_requested_appointment_alternative_time', {
      p_proposal_id: proposalId,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    if (typeof data !== 'string' || data.toLowerCase() !== proposalId.toLowerCase()) {
      return { data: null, error: RESCHEDULE_ACCEPTANCE_MALFORMED };
    }

    return { data: { proposalId: data }, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// get_appointment_scheduling_history
// ---------------------------------------------------------------------------

export type AppointmentScheduleHistoryEntry = {
  revisionSequence: number;
  revisionContext: AppointmentScheduleRevisionContext;
  scheduledStartAt: string;
  scheduledEndAt: string;
  establishmentTimezoneName: string;
  establishedByUserId: string;
  establishedAt: string;
  isAcceptedReschedule: boolean;
  rescheduleProposingContext: string | null;
  rescheduleProposedByUserId: string | null;
  rescheduleReason: string | null;
  rescheduleProposedAt: string | null;
  rescheduleAcceptingContext: string | null;
  rescheduleAcceptedByUserId: string | null;
  rescheduleAcceptedAt: string | null;
};

export type AppointmentScheduleHistoryRow = {
  revision_sequence: number;
  revision_context: AppointmentScheduleRevisionContext;
  scheduled_start_at: string;
  scheduled_end_at: string;
  establishment_timezone_name: string;
  established_by_user_id: string;
  established_at: string;
  is_accepted_reschedule: boolean;
  reschedule_proposing_context: string | null;
  reschedule_proposed_by_user_id: string | null;
  reschedule_reason: string | null;
  reschedule_proposed_at: string | null;
  reschedule_accepting_context: string | null;
  reschedule_accepted_by_user_id: string | null;
  reschedule_accepted_at: string | null;
};

export function fromAppointmentScheduleHistoryRow(
  row: AppointmentScheduleHistoryRow,
): AppointmentScheduleHistoryEntry {
  return {
    revisionSequence: row.revision_sequence,
    revisionContext: row.revision_context,
    scheduledStartAt: row.scheduled_start_at,
    scheduledEndAt: row.scheduled_end_at,
    establishmentTimezoneName: row.establishment_timezone_name,
    establishedByUserId: row.established_by_user_id,
    establishedAt: row.established_at,
    isAcceptedReschedule: row.is_accepted_reschedule,
    rescheduleProposingContext: row.reschedule_proposing_context,
    rescheduleProposedByUserId: row.reschedule_proposed_by_user_id,
    rescheduleReason: row.reschedule_reason,
    rescheduleProposedAt: row.reschedule_proposed_at,
    rescheduleAcceptingContext: row.reschedule_accepting_context,
    rescheduleAcceptedByUserId: row.reschedule_accepted_by_user_id,
    rescheduleAcceptedAt: row.reschedule_accepted_at,
  };
}

export async function getAppointmentSchedulingHistory(
  appointmentId: string,
): Promise<AppointmentsResult<AppointmentScheduleHistoryEntry[]>> {
  try {
    const { data, error } = await supabase.rpc('get_appointment_scheduling_history', {
      p_appointment_id: appointmentId,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return {
      data: ((data ?? []) as AppointmentScheduleHistoryRow[]).map(
        fromAppointmentScheduleHistoryRow,
      ),
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// get_appointment_veterinarian_assignment_history
// ---------------------------------------------------------------------------

export type AppointmentVeterinarianAssignmentHistoryEntry = {
  appointmentVeterinarianAssignmentId: string;
  veterinarianProfessionalProfileId: string;
  effectiveStart: string;
  effectiveEnd: string | null;
  assignedByUserId: string;
};

export type AppointmentVeterinarianAssignmentHistoryRow = {
  appointment_veterinarian_assignment_id: string;
  veterinarian_professional_profile_id: string;
  effective_start: string;
  effective_end: string | null;
  assigned_by_user_id: string;
};

export function fromAppointmentVeterinarianAssignmentHistoryRow(
  row: AppointmentVeterinarianAssignmentHistoryRow,
): AppointmentVeterinarianAssignmentHistoryEntry {
  return {
    appointmentVeterinarianAssignmentId: row.appointment_veterinarian_assignment_id,
    veterinarianProfessionalProfileId: row.veterinarian_professional_profile_id,
    effectiveStart: row.effective_start,
    effectiveEnd: row.effective_end,
    assignedByUserId: row.assigned_by_user_id,
  };
}

export async function getAppointmentVeterinarianAssignmentHistory(
  appointmentId: string,
): Promise<AppointmentsResult<AppointmentVeterinarianAssignmentHistoryEntry[]>> {
  try {
    const { data, error } = await supabase.rpc('get_appointment_veterinarian_assignment_history', {
      p_appointment_id: appointmentId,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return {
      data: ((data ?? []) as AppointmentVeterinarianAssignmentHistoryRow[]).map(
        fromAppointmentVeterinarianAssignmentHistoryRow,
      ),
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

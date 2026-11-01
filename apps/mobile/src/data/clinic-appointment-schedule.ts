import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import {
  isAppointmentLifecycleState,
  type AppointmentLifecycleState,
} from '@/lib/appointment-lifecycle';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the row of the deployed SPEC-APT-012 read
 * `public.get_clinic_appointment_schedule(p_clinic_id uuid)` — latest
 * definition in supabase/migrations/20261107090000_appointment_requester_contact.sql
 * (`has_clinical_record` from 20261113090000_appointment_owned_clinical_documentation.sql,
 * `cancellation_reason` from 20261022090000_clinic_schedule_cancellation_reason.sql,
 * `pet_name` from 20261001170000_clinic_appointment_schedule_pet_name.sql,
 * relevant scheduled interval from 20261002090000_appointment_relevant_scheduled_interval.sql,
 * revision sequence from 20261003090000_stale_safe_appointment_confirmation.sql).
 * This app no longer calls that full read (installed versions still may, so
 * it stays deployed): every Clinic Appointment read it uses returns exactly
 * this row (SPEC-APT-012 BR-51) — the single Appointment (BR-52, below) and
 * the agenda's day, Pending and History reads (data/clinic-calendar.ts). Each
 * re-authorizes the caller itself (`APPOINTMENT_VIEW_SCHEDULE` for that
 * Clinic): a Professional Clinic's advisory capabilities only decide whether
 * the app OFFERS the agenda, never whether it may be read. A row:
 *
 *   id uuid, pet_id uuid, pet_name text, requesting_user_id uuid,
 *   requester_display_name text | null, reason_for_visit text, guardian_notes text | null, lifecycle_state text,
 *   created_at timestamptz,
 *   current_scheduled_start_at timestamptz, current_scheduled_end_at timestamptz,
 *   current_scheduling_timezone_name text,
 *   current_schedule_revision_sequence integer,
 *   current_veterinarian_clinic_assignment_id uuid | null,
 *   pending_reschedule_proposal_id uuid | null, pending_reschedule_proposal_state text | null,
 *   pending_reschedule_proposing_context text | null,
 *   pending_reschedule_proposed_start_at timestamptz | null,
 *   pending_reschedule_proposed_end_at timestamptz | null,
 *   pending_reschedule_proposed_timezone_name text | null,
 *   pending_reschedule_reason text | null,
 *   current_schedule_source_proposal_id uuid | null,
 *   current_schedule_source_proposing_context text | null,
 *   pending_reschedule_currently_feasible boolean | null,
 *   cancellation_reason text | null,
 *   has_clinical_record boolean
 *
 * Nullability follows the backend invariants rather than the SQL column
 * types alone:
 * - `pet_name` is the Pet's current name (SPEC-APT-012 BR-41), always present
 *   (inner join; `pets.name` is NOT NULL and non-empty).
 * - `requester_display_name` (SPEC-APT-012 BR-49) is the original requester's
 *   current display name, trimmed, or null when none is set. The column is
 *   always present: a schedule without it (a backend older than this app) is
 *   malformed, so the backend must be deployed first. The schedule never
 *   carries an email (see data/appointment-requester-contact.ts).
 * - The relevant scheduled interval (SPEC-APT-012 §4) is the latest Schedule
 *   Revision, and every Appointment has an initial REQUESTED revision
 *   (`assert_appointment_lifecycle_coherence`), so start/end/timezone are
 *   always present; a missing or incoherent interval is a malformed payload.
 * - `current_schedule_revision_sequence` (SPEC-APT-012 BR-43) is the positive
 *   integer sequence of exactly that same Schedule Revision, always present.
 *   It is concurrency/version metadata — the token a stale-safe confirmation
 *   sends back (SPEC-APT-002 BR-21) — and is never rendered or announced.
 * - The pending-reschedule columns come from one actionable PENDING Proposal
 *   (SPEC-APT-005 BR-31, SPEC-APT-018 BR-17 — never ACCEPTED, WITHDRAWN, or
 *   VOID): either all of id/state/context/start/end/timezone are present, or
 *   all are null. A PENDING Proposal's base context always equals the
 *   Appointment's lifecycle state, so the lifecycle discriminates the workflow
 *   (SPEC-APT-012 BR-44): on a CONFIRMED Appointment it is a confirmed
 *   reschedule (Guardian or Clinic); on a REQUESTED one, a Clinic alternative
 *   time for the request. A Clinic-originated Proposal always carries a reason.
 *   The proposed interval is the exact stored one; the client never derives an
 *   end or duration.
 * - `pending_reschedule_currently_feasible` (SPEC-APT-012 BR-44, SPEC-APT-005
 *   BR-34) is a boolean exactly when a proposal is projected and null
 *   otherwise: whether its frozen interval could be established right now
 *   under the Clinic's current scheduling constraints. Scheduling-only (no
 *   Entitlement), generic (no reason), derived at read time; an infeasible
 *   proposal is still projected and still withdrawable.
 * - The two `current_schedule_source_*` columns (SPEC-APT-012 BR-45) are the
 *   accepted Proposal that established the relevant scheduled interval, or
 *   both null. On a REQUESTED Appointment a source is always Clinic-originated
 *   (an accepted alternative time, awaiting Clinic confirmation).
 *
 * Parsing is strict: any malformed row rejects the whole schedule (it is never
 * silently dropped). SQLSTATE 28000 is normalized to the shared
 * PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 42501 (no current schedule-view
 * authority, or an unknown Clinic) to CLINIC_SCHEDULE_ACCESS_DENIED, and a
 * malformed payload to CLINIC_SCHEDULE_MALFORMED. Every call settles into
 * `{data, error}` and never rejects.
 */
export type ClinicScheduleResult<T> = { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for SQLSTATE 42501 — see the module doc comment. */
export const CLINIC_SCHEDULE_ACCESS_DENIED = 'CLINIC_SCHEDULE_ACCESS_DENIED';

/** Normalized `error` for a payload that fails validation. */
export const CLINIC_SCHEDULE_MALFORMED = 'CLINIC_SCHEDULE_MALFORMED';

export type RescheduleProposingContext = 'GUARDIAN' | 'CLINIC';

type PendingProposalFacts = {
  proposalId: string;
  proposedStartAt: string;
  proposedEndAt: string;
  proposedTimezoneName: string;
};

/**
 * An actionable pending Reschedule Proposal — never the Appointment's current
 * interval — discriminated by its workflow (SPEC-APT-011 BR-32, SPEC-APT-012
 * BR-44): a confirmed reschedule of a CONFIRMED Appointment (SPEC-APT-005), or
 * a Clinic alternative time for a REQUESTED one (SPEC-APT-018), which is
 * always Clinic-originated with a reason. Each read adds its own derived,
 * read-time value (see `PendingRescheduleDerivedKey`).
 */
export type PendingRescheduleProposal =
  | (PendingProposalFacts & {
      kind: 'confirmedReschedule';
      proposingContext: RescheduleProposingContext;
      reason: string | null;
    })
  | (PendingProposalFacts & {
      kind: 'requestedAlternativeTime';
      proposingContext: 'CLINIC';
      reason: string;
    });

/**
 * The derived value each read projects with its pending proposal:
 * `currentlyFeasible` in the Clinic schedule (SPEC-APT-012 BR-44,
 * scheduling-only) and `currentlyAcceptable` in the Guardian view
 * (SPEC-APT-011 BR-32: can the current Guardian accept it now). Neither is
 * proposal state, and neither carries a reason.
 */
export type PendingRescheduleDerivedKey = 'currentlyFeasible' | 'currentlyAcceptable';

const DERIVED_COLUMNS: Record<PendingRescheduleDerivedKey, string> = {
  currentlyFeasible: 'pending_reschedule_currently_feasible',
  currentlyAcceptable: 'pending_reschedule_currently_acceptable',
};

/** The Clinic schedule's pending proposal, with its current scheduling feasibility. */
export type ClinicSchedulePendingReschedule = PendingRescheduleProposal & {
  currentlyFeasible: boolean;
};

/**
 * The accepted Proposal that established the relevant scheduled interval
 * (SPEC-APT-011 BR-33, SPEC-APT-012 BR-45). Derived from the current
 * revision's provenance; never a stored flag.
 */
export type CurrentScheduleSource = {
  proposalId: string;
  proposingContext: RescheduleProposingContext;
};

export type ClinicScheduleAppointment = {
  id: string;
  petId: string;
  /** The Pet's current name at read time (SPEC-APT-012 BR-41) — presentation, not identity. */
  petName: string;
  requestingUserId: string;
  /**
   * The original requester's current display name (SPEC-APT-012 BR-49), or
   * `null` when none is set. Not necessarily a current Guardian.
   */
  requesterDisplayName: string | null;
  reasonForVisit: string;
  guardianNotes: string | null;
  lifecycleState: AppointmentLifecycleState;
  createdAt: string;
  /** The relevant scheduled interval (SPEC-APT-012 §4), in the Clinic timezone it was established in. */
  currentScheduledStartAt: string;
  currentScheduledEndAt: string;
  currentSchedulingTimezoneName: string;
  /**
   * Sequence of the Schedule Revision that supplies the interval above
   * (SPEC-APT-012 BR-43). Concurrency/version metadata only — never shown.
   */
  currentScheduleRevisionSequence: number;
  currentVeterinarianClinicAssignmentId: string | null;
  pendingReschedule: ClinicSchedulePendingReschedule | null;
  currentScheduleSource: CurrentScheduleSource | null;
  /**
   * The reason recorded by the cancellation of a CANCELLED Appointment, by the
   * Clinic or a Guardian (SPEC-APT-003 BR-8/BR-9); `null` for every other
   * state and for a Guardian cancellation without a reason.
   */
  cancellationReason: string | null;
  /**
   * Whether at least one Clinical Record Entry belongs to the Appointment
   * (SPEC-MED-010 BR-9). Existence only — no clinical content. Advisory: it
   * hides the actions the backend rejects once the visit is documented; the
   * backend stays authoritative.
   */
  hasClinicalRecord: boolean;
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

// Same UUID convention as lib/push-notification-payload.ts.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// PostgREST serializes timestamptz as ISO 8601 with an explicit offset.
const TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isNullableNonEmptyString(value: unknown): value is string | null {
  return value === null || isNonEmptyString(value);
}

function isTimestamp(value: unknown): value is string {
  return (
    typeof value === 'string' && TIMESTAMP_PATTERN.test(value) && Number.isFinite(Date.parse(value))
  );
}

function isTimeZone(value: unknown): value is string {
  if (!isNonEmptyString(value)) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

function isRevisionSequence(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0;
}

type Interval = { startAt: string; endAt: string; timezoneName: string };

/** A real interval (start before end) in a valid IANA timezone, or `null`. */
function parseInterval(start: unknown, end: unknown, timeZone: unknown): Interval | null {
  if (!isTimestamp(start) || !isTimestamp(end) || !isTimeZone(timeZone)) return null;
  if (Date.parse(start) >= Date.parse(end)) return null;
  return { startAt: start, endAt: end, timezoneName: timeZone };
}

const PENDING_COLUMNS = [
  'pending_reschedule_proposal_id',
  'pending_reschedule_proposal_state',
  'pending_reschedule_proposing_context',
  'pending_reschedule_proposed_start_at',
  'pending_reschedule_proposed_end_at',
  'pending_reschedule_proposed_timezone_name',
] as const;

/**
 * The actionable pending reschedule proposal projected by a row of either
 * Appointment read — `get_clinic_appointment_schedule` (SPEC-APT-012 BR-44) or
 * `get_pet_appointments` (SPEC-APT-011 BR-32), which project the same
 * `pending_reschedule_*` columns with the same backend semantics, plus each
 * read's own derived boolean (`derivedKey`). Exported so both parsers apply
 * one strict rule. `undefined` = malformed (a partial or incoherent proposal,
 * or a derived value that is not a boolean exactly when a proposal is present,
 * must reject the whole read, never become "no proposal" or default to
 * `true`); `null` = no pending proposal.
 */
export function parsePendingRescheduleColumns<K extends PendingRescheduleDerivedKey>(
  row: Record<string, unknown>,
  lifecycleState: AppointmentLifecycleState,
  derivedKey: K,
): (PendingRescheduleProposal & Record<K, boolean>) | null | undefined {
  const reason = row.pending_reschedule_reason;
  const derived = row[DERIVED_COLUMNS[derivedKey]];
  if (PENDING_COLUMNS.every((column) => row[column] === null)) {
    return reason === null && derived === null ? null : undefined;
  }
  if (typeof derived !== 'boolean') return undefined;
  const derivedValue = { [derivedKey]: derived } as Record<K, boolean>;

  const {
    pending_reschedule_proposal_id: proposalId,
    pending_reschedule_proposal_state: state,
    pending_reschedule_proposing_context: proposingContext,
    pending_reschedule_proposed_start_at: proposedStartAt,
    pending_reschedule_proposed_end_at: proposedEndAt,
    pending_reschedule_proposed_timezone_name: proposedTimezoneName,
  } = row;

  const proposedInterval = parseInterval(proposedStartAt, proposedEndAt, proposedTimezoneName);
  if (
    !isUuid(proposalId) ||
    state !== 'PENDING' ||
    (proposingContext !== 'GUARDIAN' && proposingContext !== 'CLINIC') ||
    proposedInterval === null ||
    !isNullableNonEmptyString(reason) ||
    (proposingContext === 'CLINIC' && reason === null)
  ) {
    return undefined;
  }

  const facts: PendingProposalFacts = {
    proposalId,
    proposedStartAt: proposedInterval.startAt,
    proposedEndAt: proposedInterval.endAt,
    proposedTimezoneName: proposedInterval.timezoneName,
  };
  if (lifecycleState === 'CONFIRMED') {
    return { ...facts, kind: 'confirmedReschedule', proposingContext, reason, ...derivedValue };
  }
  // A REQUESTED base is always Clinic-originated, with a reason (SPEC-APT-018).
  if (lifecycleState === 'REQUESTED' && proposingContext === 'CLINIC' && reason !== null) {
    return {
      ...facts,
      kind: 'requestedAlternativeTime',
      proposingContext,
      reason,
      ...derivedValue,
    };
  }
  // No other lifecycle state can carry an actionable proposal.
  return undefined;
}

/**
 * The provenance of the relevant scheduled interval projected by a row of
 * either Appointment read (SPEC-APT-011 BR-33, SPEC-APT-012 BR-45). Exported
 * so both parsers apply one strict rule. `undefined` = malformed (partial,
 * missing, or a REQUESTED interval sourced by anything but the Clinic);
 * `null` = the interval was not established by accepting a proposal.
 */
export function parseCurrentScheduleSourceColumns(
  row: Record<string, unknown>,
  lifecycleState: AppointmentLifecycleState,
): CurrentScheduleSource | null | undefined {
  const {
    current_schedule_source_proposal_id: proposalId,
    current_schedule_source_proposing_context: proposingContext,
  } = row;
  if (proposalId === null && proposingContext === null) return null;
  if (!isUuid(proposalId) || (proposingContext !== 'GUARDIAN' && proposingContext !== 'CLINIC')) {
    return undefined;
  }
  if (lifecycleState === 'REQUESTED' && proposingContext !== 'CLINIC') return undefined;
  return { proposalId, proposingContext };
}

function parseAppointment(raw: unknown): ClinicScheduleAppointment | null {
  if (!isRecord(raw)) return null;
  const {
    id,
    pet_id,
    pet_name,
    requesting_user_id,
    requester_display_name,
    reason_for_visit,
    guardian_notes,
    lifecycle_state,
    created_at,
    current_scheduled_start_at,
    current_scheduled_end_at,
    current_scheduling_timezone_name,
    current_schedule_revision_sequence,
    current_veterinarian_clinic_assignment_id,
    cancellation_reason,
    has_clinical_record,
  } = raw;

  const interval = parseInterval(
    current_scheduled_start_at,
    current_scheduled_end_at,
    current_scheduling_timezone_name,
  );
  if (
    !isUuid(id) ||
    !isUuid(pet_id) ||
    !isNonEmptyString(pet_name) ||
    !isUuid(requesting_user_id) ||
    // Always present (SPEC-APT-012 BR-49): null or a non-blank name.
    !isNullableNonEmptyString(requester_display_name) ||
    !isNonEmptyString(reason_for_visit) ||
    !isNullableNonEmptyString(guardian_notes) ||
    !isAppointmentLifecycleState(lifecycle_state) ||
    !isTimestamp(created_at) ||
    interval === null ||
    !isRevisionSequence(current_schedule_revision_sequence) ||
    (current_veterinarian_clinic_assignment_id !== null &&
      !isUuid(current_veterinarian_clinic_assignment_id)) ||
    // Present on every row: null, or a non-blank reason only on CANCELLED.
    (cancellation_reason !== null &&
      (!isNonEmptyString(cancellation_reason) || lifecycle_state !== 'CANCELLED')) ||
    // Always present (SPEC-APT-012 BR-48).
    typeof has_clinical_record !== 'boolean'
  ) {
    return null;
  }

  const pendingReschedule = parsePendingRescheduleColumns(
    raw,
    lifecycle_state,
    'currentlyFeasible',
  );
  if (pendingReschedule === undefined) return null;
  const currentScheduleSource = parseCurrentScheduleSourceColumns(raw, lifecycle_state);
  if (currentScheduleSource === undefined) return null;

  return {
    id,
    petId: pet_id,
    petName: pet_name,
    requestingUserId: requesting_user_id,
    requesterDisplayName: requester_display_name,
    reasonForVisit: reason_for_visit,
    guardianNotes: guardian_notes,
    lifecycleState: lifecycle_state,
    createdAt: created_at,
    currentScheduledStartAt: interval.startAt,
    currentScheduledEndAt: interval.endAt,
    currentSchedulingTimezoneName: interval.timezoneName,
    currentScheduleRevisionSequence: current_schedule_revision_sequence,
    currentVeterinarianClinicAssignmentId: current_veterinarian_clinic_assignment_id,
    pendingReschedule,
    currentScheduleSource,
    cancellationReason: cancellation_reason,
    hasClinicalRecord: has_clinical_record,
  };
}

/**
 * Exported for unit testing: validates and reshapes the RPC's rows, preserving
 * backend order. Returns `null` if any row is malformed or an Appointment is
 * returned twice (SPEC-APT-012 BR-36).
 */
export function parseClinicAppointmentSchedule(raw: unknown): ClinicScheduleAppointment[] | null {
  if (!Array.isArray(raw)) return null;

  const appointments: ClinicScheduleAppointment[] = [];
  const seenIds = new Set<string>();
  for (const item of raw) {
    const appointment = parseAppointment(item);
    if (appointment === null || seenIds.has(appointment.id)) return null;
    seenIds.add(appointment.id);
    appointments.push(appointment);
  }
  return appointments;
}

// ---------------------------------------------------------------------------
// RPC
// ---------------------------------------------------------------------------

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/**
 * Exported for unit testing: the single Appointment of a
 * `get_clinic_appointment` response — exactly one row, parsed by the schedule's
 * own strict row parser, and for the Appointment that was asked for. Anything
 * else (no row, several rows, another id, a malformed row) is `null`.
 */
export function parseClinicAppointment(
  raw: unknown,
  appointmentId: string,
): ClinicScheduleAppointment | null {
  const rows = parseClinicAppointmentSchedule(raw);
  if (rows === null || rows.length !== 1) return null;
  const [appointment] = rows;
  return appointment.id.toLowerCase() === appointmentId.toLowerCase() ? appointment : null;
}

/**
 * Reads one Appointment of one Clinic (SPEC-APT-012 BR-52,
 * `get_clinic_appointment`), with exactly the columns and rules of a schedule
 * row (BR-51) and never the requester's email (BR-50). The backend
 * re-authorizes the caller for this Clinic on every call and resolves only
 * this Appointment.
 *
 * `data: null` means the Appointment is unavailable here: the backend answers
 * one uniform 42501 for an unknown Appointment, an Appointment of another
 * Clinic, and an actor without schedule-view authority, and the client does
 * not try to tell them apart. SQLSTATE 28000 is normalized to
 * PROFESSIONAL_CONTEXT_AUTH_REQUIRED and an unexpected payload to
 * CLINIC_SCHEDULE_MALFORMED. Never rejects.
 */
export async function getClinicAppointment(
  clinicId: string,
  appointmentId: string,
): Promise<ClinicScheduleResult<ClinicScheduleAppointment | null>> {
  try {
    const { data, error } = await supabase.rpc('get_clinic_appointment', {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
    });

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      if (error.code === '42501') {
        return { data: null, error: null };
      }
      return { data: null, error: error.message };
    }

    const appointment = parseClinicAppointment(data, appointmentId);
    if (appointment === null) {
      return { data: null, error: CLINIC_SCHEDULE_MALFORMED };
    }

    return { data: appointment, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

import { supabase } from '@/lib/supabase';

/**
 * The Appointment's documentation responsibility: who may record new Clinical
 * Record Entries for the visit (SPEC-APT-007 §13 BR-30–BR-39;
 * supabase/migrations/20261112090000_appointment_veterinarian_assignment_contract.sql).
 * Keyed only by the Clinic and Appointment the professional detail shows.
 *
 * Nothing here creates clinical information or grants medical access, and no
 * read writes anything: opening the detail never assigns. The only identifiers
 * received are an opaque `assignmentToken` (the reviewed period, sent back as
 * the stale-safe expectation) and each candidate's Clinic Assignment id (sent
 * back to choose them) — both kept in memory and never displayed.
 *
 * No function here throws or retries. A write without a trustworthy answer is
 * `uncertain`: the caller re-reads the assignment and decides from it.
 */

export type AppointmentVeterinarianAssignment =
  | { kind: 'unassigned'; mayAssignMe: boolean; mayManage: boolean }
  | {
      kind: 'assigned';
      /** The assignee's current display name, or null for the neutral fallback. */
      displayName: string | null;
      isMe: boolean;
      /** False when the assignee's Clinic context ended: the assignment is stale. */
      isEligible: boolean;
      assignmentToken: string;
      mayAssignMe: boolean;
      mayManage: boolean;
    };

export type AppointmentVeterinarianAssignmentRead =
  | { kind: 'loaded'; assignment: AppointmentVeterinarianAssignment }
  /** The uniform denial of get_clinic_appointment (SPEC-APT-012 BR-52). */
  | { kind: 'unavailable' }
  | { kind: 'authenticationRequired' }
  | { kind: 'failed' };

export type AppointmentVeterinarianCandidate = {
  /** Sent back to choose this Veterinarian; never displayed. */
  veterinarianClinicAssignmentId: string;
  displayName: string | null;
  isMe: boolean;
  isCurrentAssignee: boolean;
};

export type AppointmentVeterinarianCandidatesRead =
  | { kind: 'permitted'; candidates: AppointmentVeterinarianCandidate[] }
  | { kind: 'denied' }
  | { kind: 'authenticationRequired' }
  | { kind: 'failed' };

export const ASSIGNMENT_REJECTIONS = [
  'VETERINARIAN_REQUIRED',
  'APPOINTMENT_STATE_INVALID',
  'ASSIGNED_TO_ANOTHER_VETERINARIAN',
  'STALE_ASSIGNMENT',
  'VETERINARIAN_NOT_ELIGIBLE',
  'VETERINARIAN_SCHEDULE_CONFLICT',
] as const;
export type AssignmentRejection = (typeof ASSIGNMENT_REJECTIONS)[number];

export type AssignmentWriteResult =
  | { kind: 'outcome'; outcome: 'ASSIGNED' | 'REASSIGNED' | 'ALREADY_ASSIGNED' }
  | { kind: 'rejected'; reason: AssignmentRejection }
  /** The uniform 42501: no authority now, or an Appointment of another Clinic. */
  | { kind: 'denied' }
  /** The Organization's scheduling service is unavailable (CONFIRMED only). */
  | { kind: 'serviceUnavailable' }
  | { kind: 'authenticationRequired' }
  | { kind: 'uncertain' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
const isId = (value: unknown): value is string => typeof value === 'string' && UUID.test(value);
const isNullableName = (value: unknown): value is string | null =>
  value === null || (typeof value === 'string' && value.trim() !== '');

/** Exported for unit testing. `null` = malformed. */
export function parseAppointmentVeterinarianAssignment(
  raw: unknown,
): AppointmentVeterinarianAssignment | null {
  if (!isRecord(raw)) return null;
  const { status, may_assign_me, may_manage } = raw;
  if (typeof may_assign_me !== 'boolean' || typeof may_manage !== 'boolean') return null;
  if (status === 'UNASSIGNED') {
    return { kind: 'unassigned', mayAssignMe: may_assign_me, mayManage: may_manage };
  }
  if (status !== 'ASSIGNED') return null;
  const { display_name, is_me, is_eligible, assignment_token } = raw;
  if (
    !isNullableName(display_name) ||
    typeof is_me !== 'boolean' ||
    typeof is_eligible !== 'boolean' ||
    !isId(assignment_token)
  )
    return null;
  return {
    kind: 'assigned',
    displayName: display_name === null ? null : display_name.trim(),
    isMe: is_me,
    isEligible: is_eligible,
    assignmentToken: assignment_token,
    mayAssignMe: may_assign_me,
    mayManage: may_manage,
  };
}

/** Exported for unit testing. `null` = malformed. */
export function parseAppointmentVeterinarianCandidates(
  raw: unknown,
):
  | { kind: 'permitted'; candidates: AppointmentVeterinarianCandidate[] }
  | { kind: 'denied' }
  | null {
  if (!isRecord(raw)) return null;
  if (raw.status === 'DENIED') return { kind: 'denied' };
  if (raw.status !== 'PERMITTED' || !Array.isArray(raw.candidates)) return null;
  const candidates: AppointmentVeterinarianCandidate[] = [];
  const seen = new Set<string>();
  for (const item of raw.candidates) {
    if (!isRecord(item)) return null;
    const { veterinarian_clinic_assignment_id, display_name, is_me, is_current_assignee } = item;
    if (
      !isId(veterinarian_clinic_assignment_id) ||
      seen.has(veterinarian_clinic_assignment_id) ||
      !isNullableName(display_name) ||
      typeof is_me !== 'boolean' ||
      typeof is_current_assignee !== 'boolean'
    )
      return null;
    seen.add(veterinarian_clinic_assignment_id);
    candidates.push({
      veterinarianClinicAssignmentId: veterinarian_clinic_assignment_id,
      displayName: display_name === null ? null : display_name.trim(),
      isMe: is_me,
      isCurrentAssignee: is_current_assignee,
    });
  }
  return { kind: 'permitted', candidates };
}

/** SPEC-APT-007 BR-37: who has the Appointment, and what the reader may do about it. */
export async function getAppointmentVeterinarianAssignment(
  clinicId: string,
  appointmentId: string,
): Promise<AppointmentVeterinarianAssignmentRead> {
  try {
    const { data, error } = await supabase.rpc('get_appointment_veterinarian_assignment', {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
    });
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '42501') return { kind: 'unavailable' };
      return { kind: 'failed' };
    }
    const assignment = parseAppointmentVeterinarianAssignment(data);
    return assignment === null ? { kind: 'failed' } : { kind: 'loaded', assignment };
  } catch {
    return { kind: 'failed' };
  }
}

/** SPEC-APT-007 BR-38: the eligible Veterinarians a manager may choose from. Not a medical access. */
export async function getAppointmentVeterinarianCandidates(
  clinicId: string,
  appointmentId: string,
): Promise<AppointmentVeterinarianCandidatesRead> {
  try {
    const { data, error } = await supabase.rpc('get_appointment_veterinarian_candidates', {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
    });
    if (error) {
      return error.code === '28000' ? { kind: 'authenticationRequired' } : { kind: 'failed' };
    }
    return parseAppointmentVeterinarianCandidates(data) ?? { kind: 'failed' };
  } catch {
    return { kind: 'failed' };
  }
}

type RpcError = { code?: string; hint?: string | null } | null;

function mapError(error: RpcError): AssignmentWriteResult {
  const code = error?.code ?? '';
  if (code === '28000') return { kind: 'authenticationRequired' };
  if (code === '42501')
    return error?.hint === 'SCHEDULING_SERVICE_UNAVAILABLE'
      ? { kind: 'serviceUnavailable' }
      : { kind: 'denied' };
  const reason = ASSIGNMENT_REJECTIONS.find((candidate) => candidate === error?.hint);
  return reason !== undefined ? { kind: 'rejected', reason } : { kind: 'uncertain' };
}

async function callAssign(
  rpc: string,
  args: Record<string, unknown>,
): Promise<AssignmentWriteResult> {
  try {
    const { data, error } = await supabase.rpc(rpc, args);
    if (error) return mapError(error);
    if (!isRecord(data) || !isId(data.assignment_token)) return { kind: 'uncertain' };
    const outcome = (['ASSIGNED', 'REASSIGNED', 'ALREADY_ASSIGNED'] as const).find(
      (candidate) => candidate === data.outcome,
    );
    return outcome === undefined ? { kind: 'uncertain' } : { kind: 'outcome', outcome };
  } catch {
    return { kind: 'uncertain' };
  }
}

/**
 * SPEC-APT-007 BR-33: the eligible reader takes an unassigned (or stale)
 * Appointment. Never displaces an eligible colleague
 * (`ASSIGNED_TO_ANOTHER_VETERINARIAN`). Safe to repeat (`ALREADY_ASSIGNED`).
 */
export function assignMeToAppointment(
  clinicId: string,
  appointmentId: string,
): Promise<AssignmentWriteResult> {
  return callAssign('assign_me_to_appointment', {
    p_clinic_id: clinicId,
    p_appointment_id: appointmentId,
  });
}

/**
 * SPEC-APT-007 BR-32: a manager assigns or changes the Veterinarian.
 * `expectedAssignmentToken` is the token of the assignment the actor reviewed,
 * or null when they saw none; anything else changed since is `STALE_ASSIGNMENT`.
 */
export function assignAppointmentVeterinarian(
  clinicId: string,
  appointmentId: string,
  veterinarianClinicAssignmentId: string,
  expectedAssignmentToken: string | null,
): Promise<AssignmentWriteResult> {
  return callAssign('assign_appointment_veterinarian', {
    p_clinic_id: clinicId,
    p_appointment_id: appointmentId,
    p_veterinarian_clinic_assignment_id: veterinarianClinicAssignmentId,
    p_expected_assignment_token: expectedAssignmentToken,
  });
}

import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ClinicIdentity,
} from '@/data/professional-context';
import { STAFF_ACCESS_DENIED } from '@/data/organization-staff';
import { supabase } from '@/lib/supabase';

/**
 * Staff Responsibility Editing + Veterinarian Enablement — Phase 1.
 *
 * Mirrors the client-safe operations of
 * supabase/migrations/20261102090000_staff_responsibility_and_veterinarian_workforce.sql:
 *
 *   add_staff_responsibility / replace_staff_responsibility /
 *   end_staff_responsibility (SPEC-ORG-006 §14),
 *   get_organization_veterinarian_workforce (SPEC-VET-006),
 *   assign_staff_veterinarian_to_clinic (SPEC-VET-004 §13),
 *   end_staff_veterinarian_clinic_assignment (SPEC-VET-005 §13).
 *
 * Every operation names the route Organization so the backend decides
 * authorization before any target fact; the client sends only domain ids it
 * received from the authorized reads (never a User, Auth, or Profile id). A
 * 42501 is loss of access; a 23514/22023 carries a stable hint; anything else,
 * including a malformed success, is `uncertain` and is reconciled by the
 * authoritative re-read, never retried blindly. Every function settles and
 * never rejects.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isId = (raw: unknown): raw is string => typeof raw === 'string' && UUID.test(raw);
const isInstant = (raw: unknown): raw is string =>
  typeof raw === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(raw) && Number.isFinite(Date.parse(raw));
function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}
const sameId = (a: unknown, b: string) => isId(a) && a.toLowerCase() === b.toLowerCase();

// ---------------------------------------------------------------------------
// Responsibility management (SPEC-ORG-006 §14)
// ---------------------------------------------------------------------------

/** Roles the Phase 1 Staff editor may Add or Change to (BR-49). Never OWNER. */
export const STAFF_EDITABLE_ROLES = ['ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN'] as const;
export type StaffEditableRole = (typeof STAFF_EDITABLE_ROLES)[number];
export type StaffScopeType = 'ORGANIZATION' | 'CLINIC';
export type StaffResponsibilityInput = {
  role: StaffEditableRole;
  scope: StaffScopeType;
  clinicId: string | null;
};

/** Stable hints of the Responsibility operations (BR-55). */
export const STAFF_RESPONSIBILITY_REJECTIONS = [
  'INVALID_SCOPE',
  'INVALID_CLINIC',
  'OWNER_GRANT',
  'OWNER_MEMBERSHIP',
  'SELF_MEMBERSHIP',
  'MEMBERSHIP_INACTIVE',
  'GRANT_ENDED',
  'NO_OP',
  'DUPLICATE',
  'LAST_RESPONSIBILITY',
  'VETERINARIAN_ASSIGNMENTS_ACTIVE',
] as const;
export type StaffResponsibilityRejection = (typeof STAFF_RESPONSIBILITY_REJECTIONS)[number];

export type StaffResponsibilityOutcome =
  'ADDED' | 'ALREADY_PRESENT' | 'REPLACED' | 'ALREADY_CHANGED' | 'ENDED' | 'ALREADY_ENDED';

export type StaffWriteFailure =
  | { kind: 'accessDenied' }
  | { kind: 'authenticationRequired' }
  /** No trustworthy answer: the caller re-reads; the operation is never retried here. */
  | { kind: 'uncertain' };

export type StaffResponsibilityResult =
  | { kind: 'outcome'; outcome: StaffResponsibilityOutcome; responsibilityGrantId: string }
  | { kind: 'rejected'; reason: StaffResponsibilityRejection }
  | StaffWriteFailure;

type RpcError = { code?: string; hint?: string | null } | null;

function failureFrom<R extends string>(
  error: NonNullable<RpcError>,
  rejections: readonly R[],
): { kind: 'rejected'; reason: R } | StaffWriteFailure {
  if (error.code === '42501') return { kind: 'accessDenied' };
  if (error.code === '28000') return { kind: 'authenticationRequired' };
  const hint = rejections.find((candidate) => candidate === error.hint);
  if ((error.code === '23514' || error.code === '22023') && hint !== undefined)
    return { kind: 'rejected', reason: hint };
  return { kind: 'uncertain' };
}

function responsibilityArgs(input: StaffResponsibilityInput) {
  return {
    p_responsibility: input.role,
    p_scope_type: input.scope,
    p_clinic_id: input.scope === 'CLINIC' ? input.clinicId : null,
  };
}

async function responsibilityCall(
  name: string,
  args: Record<string, unknown>,
  expected: readonly StaffResponsibilityOutcome[],
  membershipId: string | null,
): Promise<StaffResponsibilityResult> {
  try {
    const { data, error } = await supabase.rpc(name, args);
    if (error) return failureFrom(error, STAFF_RESPONSIBILITY_REJECTIONS);
    const outcome = expected.find((candidate) => isRecord(data) && data.outcome === candidate);
    if (
      outcome === undefined ||
      !isRecord(data) ||
      !isId(data.responsibility_grant_id) ||
      !isId(data.membership_id) ||
      (membershipId !== null && !sameId(data.membership_id, membershipId))
    )
      return { kind: 'uncertain' };
    return { kind: 'outcome', outcome, responsibilityGrantId: data.responsibility_grant_id };
  } catch {
    return { kind: 'uncertain' };
  }
}

export async function addStaffResponsibility(
  organizationId: string,
  membershipId: string,
  input: StaffResponsibilityInput,
): Promise<StaffResponsibilityResult> {
  if (!isId(organizationId) || !isId(membershipId)) return { kind: 'accessDenied' };
  return responsibilityCall(
    'add_staff_responsibility',
    {
      p_organization_id: organizationId,
      p_membership_id: membershipId,
      ...responsibilityArgs(input),
    },
    ['ADDED', 'ALREADY_PRESENT'],
    membershipId,
  );
}

/** Changes exactly the named Grant (BR-46); unrelated Grants are untouched. */
export async function replaceStaffResponsibility(
  organizationId: string,
  responsibilityGrantId: string,
  input: StaffResponsibilityInput,
): Promise<StaffResponsibilityResult> {
  if (!isId(organizationId) || !isId(responsibilityGrantId)) return { kind: 'accessDenied' };
  return responsibilityCall(
    'replace_staff_responsibility',
    {
      p_organization_id: organizationId,
      p_responsibility_grant_id: responsibilityGrantId,
      ...responsibilityArgs(input),
    },
    ['REPLACED', 'ALREADY_CHANGED'],
    null,
  );
}

export async function endStaffResponsibility(
  organizationId: string,
  responsibilityGrantId: string,
): Promise<StaffResponsibilityResult> {
  if (!isId(organizationId) || !isId(responsibilityGrantId)) return { kind: 'accessDenied' };
  const result = await responsibilityCall(
    'end_staff_responsibility',
    { p_organization_id: organizationId, p_responsibility_grant_id: responsibilityGrantId },
    ['ENDED', 'ALREADY_ENDED'],
    null,
  );
  return result.kind === 'outcome' && !sameId(result.responsibilityGrantId, responsibilityGrantId)
    ? { kind: 'uncertain' }
    : result;
}

// ---------------------------------------------------------------------------
// Organization Veterinarian workforce read (SPEC-VET-006)
// ---------------------------------------------------------------------------

export type WorkforceClinicAssignment = {
  veterinarianClinicAssignmentId: string;
  clinic: ClinicIdentity;
};
export type WorkforceMember = {
  membershipId: string;
  hasVeterinarianProfessionalProfile: boolean;
  clinicAssignments: WorkforceClinicAssignment[];
};
export type VeterinarianWorkforce = { organizationId: string; members: WorkforceMember[] };
export type WorkforceResult =
  { data: VeterinarianWorkforce; error: null } | { data: null; error: string };
export const WORKFORCE_MALFORMED = 'WORKFORCE_MALFORMED';

function parseAssignment(raw: unknown): WorkforceClinicAssignment | null {
  if (
    !isRecord(raw) ||
    !isId(raw.veterinarian_clinic_assignment_id) ||
    !isRecord(raw.clinic) ||
    !isId(raw.clinic.clinic_id) ||
    !(raw.clinic.clinic_display_name === null || typeof raw.clinic.clinic_display_name === 'string')
  )
    return null;
  return {
    veterinarianClinicAssignmentId: raw.veterinarian_clinic_assignment_id,
    clinic: { clinicId: raw.clinic.clinic_id, displayName: raw.clinic.clinic_display_name },
  };
}
function parseWorkforceMember(raw: unknown): WorkforceMember | null {
  if (
    !isRecord(raw) ||
    !isId(raw.membership_id) ||
    typeof raw.has_veterinarian_professional_profile !== 'boolean' ||
    !Array.isArray(raw.clinic_assignments)
  )
    return null;
  const assignments: WorkforceClinicAssignment[] = [];
  for (const item of raw.clinic_assignments) {
    const assignment = parseAssignment(item);
    if (assignment === null) return null;
    assignments.push(assignment);
  }
  return {
    membershipId: raw.membership_id,
    hasVeterinarianProfessionalProfile: raw.has_veterinarian_professional_profile,
    clinicAssignments: assignments,
  };
}

/** All-or-nothing; another Organization's payload rejects the whole read. */
export function parseVeterinarianWorkforce(
  raw: unknown,
  organizationId: string,
): VeterinarianWorkforce | null {
  if (!isRecord(raw) || !sameId(raw.organization_id, organizationId) || !Array.isArray(raw.members))
    return null;
  const members: WorkforceMember[] = [];
  for (const item of raw.members) {
    const member = parseWorkforceMember(item);
    if (member === null) return null;
    members.push(member);
  }
  return { organizationId: raw.organization_id as string, members };
}

export async function getOrganizationVeterinarianWorkforce(
  organizationId: string,
): Promise<WorkforceResult> {
  if (!isId(organizationId)) return { data: null, error: STAFF_ACCESS_DENIED };
  try {
    const { data, error } = await supabase.rpc('get_organization_veterinarian_workforce', {
      p_organization_id: organizationId,
    });
    if (error)
      return {
        data: null,
        error:
          error.code === '28000'
            ? PROFESSIONAL_CONTEXT_AUTH_REQUIRED
            : error.code === '42501'
              ? STAFF_ACCESS_DENIED
              : error.message,
      };
    const workforce = parseVeterinarianWorkforce(data, organizationId);
    return workforce === null
      ? { data: null, error: WORKFORCE_MALFORMED }
      : { data: workforce, error: null };
  } catch (error) {
    return { data: null, error: error instanceof Error ? error.message : 'Workforce read failed' };
  }
}

// ---------------------------------------------------------------------------
// Veterinarian Clinic Assignment (SPEC-VET-004 §13, SPEC-VET-005 §13)
// ---------------------------------------------------------------------------

export const CLINIC_ASSIGNMENT_REJECTIONS = [
  'MEMBERSHIP_INACTIVE',
  'VETERINARIAN_RESPONSIBILITY_REQUIRED',
  'PROFILE_REQUIRED',
] as const;
export type ClinicAssignmentRejection = (typeof CLINIC_ASSIGNMENT_REJECTIONS)[number];
export type ClinicAssignmentOutcome = 'ASSIGNED' | 'ALREADY_ASSIGNED' | 'ENDED' | 'ALREADY_ENDED';
export type ClinicAssignmentResult =
  | { kind: 'outcome'; outcome: ClinicAssignmentOutcome; veterinarianClinicAssignmentId: string }
  | { kind: 'rejected'; reason: ClinicAssignmentRejection }
  | StaffWriteFailure;

async function assignmentCall(
  name: string,
  args: Record<string, unknown>,
  expected: readonly ClinicAssignmentOutcome[],
  check: (data: Record<string, unknown>) => boolean,
): Promise<ClinicAssignmentResult> {
  try {
    const { data, error } = await supabase.rpc(name, args);
    if (error) return failureFrom(error, CLINIC_ASSIGNMENT_REJECTIONS);
    const outcome = expected.find((candidate) => isRecord(data) && data.outcome === candidate);
    if (
      outcome === undefined ||
      !isRecord(data) ||
      !isId(data.veterinarian_clinic_assignment_id) ||
      !check(data)
    )
      return { kind: 'uncertain' };
    return {
      kind: 'outcome',
      outcome,
      veterinarianClinicAssignmentId: data.veterinarian_clinic_assignment_id,
    };
  } catch {
    return { kind: 'uncertain' };
  }
}

/** Membership-keyed: the Profile is derived server-side, never sent (BR-22). */
export async function assignStaffVeterinarianToClinic(
  organizationId: string,
  membershipId: string,
  clinicId: string,
): Promise<ClinicAssignmentResult> {
  if (!isId(organizationId) || !isId(membershipId) || !isId(clinicId))
    return { kind: 'accessDenied' };
  return assignmentCall(
    'assign_staff_veterinarian_to_clinic',
    { p_organization_id: organizationId, p_membership_id: membershipId, p_clinic_id: clinicId },
    ['ASSIGNED', 'ALREADY_ASSIGNED'],
    (data) =>
      sameId(data.membership_id, membershipId) &&
      sameId(data.clinic_id, clinicId) &&
      isInstant(data.effective_start),
  );
}

export async function endStaffVeterinarianClinicAssignment(
  organizationId: string,
  clinicId: string,
  veterinarianClinicAssignmentId: string,
): Promise<ClinicAssignmentResult> {
  if (!isId(organizationId) || !isId(clinicId) || !isId(veterinarianClinicAssignmentId))
    return { kind: 'accessDenied' };
  return assignmentCall(
    'end_staff_veterinarian_clinic_assignment',
    {
      p_organization_id: organizationId,
      p_clinic_id: clinicId,
      p_veterinarian_clinic_assignment_id: veterinarianClinicAssignmentId,
    },
    ['ENDED', 'ALREADY_ENDED'],
    (data) =>
      sameId(data.veterinarian_clinic_assignment_id, veterinarianClinicAssignmentId) &&
      isInstant(data.effective_end),
  );
}

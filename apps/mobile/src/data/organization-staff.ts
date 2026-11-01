import {
  ORGANIZATION_RESPONSIBILITIES,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ScopedResponsibility,
} from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * One current Responsibility Grant of a Member (SPEC-ORG-009 BR-1). The Grant
 * id names exactly this Grant to the Staff Responsibility operations
 * (SPEC-ORG-006 §14); it is a domain identifier, never rendered.
 */
export type StaffResponsibility = ScopedResponsibility & { responsibilityGrantId: string };
/** SPEC-ORG-009 BR-1: invitation email is administrative context, never Auth identity. */
export type StaffMember = {
  membershipId: string;
  effectiveStart: string;
  isSelf: boolean;
  displayName: string | null;
  invitationRecipientEmail: string | null;
  responsibilities: StaffResponsibility[];
};
export type PendingStaffInvitation = {
  invitationId: string;
  recipientEmail: string;
  responsibilities: ScopedResponsibility[];
  createdAt: string;
  expiresAt: string;
};
export type OrganizationStaff = {
  organizationId: string;
  organizationDisplayName: string;
  members: StaffMember[];
  pendingInvitations: PendingStaffInvitation[];
};
export type StaffResult = { data: OrganizationStaff; error: null } | { data: null; error: string };
export const STAFF_ACCESS_DENIED = 'STAFF_ACCESS_DENIED';
export const STAFF_MALFORMED = 'STAFF_MALFORMED';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isId = (raw: unknown): raw is string => typeof raw === 'string' && UUID.test(raw);
const isInstant = (raw: unknown): raw is string =>
  typeof raw === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(raw) && Number.isFinite(Date.parse(raw));
const isNullableText = (raw: unknown): raw is string | null =>
  raw === null || typeof raw === 'string';
const isEmail = (raw: unknown): raw is string =>
  typeof raw === 'string' && raw.length > 0 && raw === raw.trim().toLowerCase();
function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}
function parseArray<T>(raw: unknown, parse: (item: unknown) => T | null): T[] | null {
  if (!Array.isArray(raw)) return null;
  const items: T[] = [];
  for (const item of raw) {
    const parsed = parse(item);
    if (parsed === null) return null;
    items.push(parsed);
  }
  return items;
}
function parseResponsibility(raw: unknown): ScopedResponsibility | null {
  if (!isRecord(raw)) return null;
  const responsibility = ORGANIZATION_RESPONSIBILITIES.find((role) => role === raw.responsibility);
  if (!responsibility) return null;
  if (raw.scope_type === 'ORGANIZATION' && raw.clinic === null) {
    return { responsibility, scope: { type: 'ORGANIZATION' } };
  }
  if (
    raw.scope_type !== 'CLINIC' ||
    !isRecord(raw.clinic) ||
    !isId(raw.clinic.clinic_id) ||
    !isNullableText(raw.clinic.clinic_display_name) ||
    responsibility === 'OWNER' ||
    responsibility === 'VETERINARIAN'
  )
    return null;
  return {
    responsibility,
    scope: {
      type: 'CLINIC',
      clinic: {
        clinicId: raw.clinic.clinic_id,
        displayName: raw.clinic.clinic_display_name,
      },
    },
  };
}
function parseMemberResponsibility(raw: unknown): StaffResponsibility | null {
  const responsibility = parseResponsibility(raw);
  if (responsibility === null || !isRecord(raw) || !isId(raw.responsibility_grant_id)) return null;
  return { ...responsibility, responsibilityGrantId: raw.responsibility_grant_id };
}
function parseMember(raw: unknown): StaffMember | null {
  if (
    !isRecord(raw) ||
    !isId(raw.membership_id) ||
    !isInstant(raw.effective_start) ||
    typeof raw.is_self !== 'boolean' ||
    !isNullableText(raw.display_name) ||
    !(raw.invitation_recipient_email === null || isEmail(raw.invitation_recipient_email))
  )
    return null;
  const responsibilities = parseArray(raw.responsibilities, parseMemberResponsibility);
  if (responsibilities === null) return null;
  return {
    membershipId: raw.membership_id,
    effectiveStart: raw.effective_start,
    isSelf: raw.is_self,
    displayName: raw.display_name,
    invitationRecipientEmail: raw.invitation_recipient_email,
    responsibilities,
  };
}
function parseInvitation(raw: unknown): PendingStaffInvitation | null {
  if (
    !isRecord(raw) ||
    !isId(raw.invitation_id) ||
    !isEmail(raw.recipient_email) ||
    !isInstant(raw.created_at) ||
    !isInstant(raw.expires_at) ||
    Date.parse(raw.expires_at) <= Date.parse(raw.created_at)
  )
    return null;
  const responsibilities = parseArray(raw.responsibilities, parseResponsibility);
  if (responsibilities === null || responsibilities.some((role) => role.responsibility === 'OWNER'))
    return null;
  return {
    invitationId: raw.invitation_id,
    recipientEmail: raw.recipient_email,
    responsibilities,
    createdAt: raw.created_at,
    expiresAt: raw.expires_at,
  };
}

/** All-or-nothing parsing; context mismatch rejects the entire read. Unknown fields never enter the client model. */
export function parseOrganizationStaff(
  raw: unknown,
  organizationId: string,
): OrganizationStaff | null {
  if (
    !isRecord(raw) ||
    !isId(raw.organization_id) ||
    raw.organization_id.toLowerCase() !== organizationId.toLowerCase() ||
    typeof raw.organization_display_name !== 'string' ||
    raw.organization_display_name.length === 0
  )
    return null;
  const members = parseArray(raw.members, parseMember);
  const pendingInvitations = parseArray(raw.pending_invitations, parseInvitation);
  if (members === null || pendingInvitations === null) return null;
  return {
    organizationId: raw.organization_id,
    organizationDisplayName: raw.organization_display_name,
    members,
    pendingInvitations,
  };
}

/**
 * SPEC-ORG-002 BR-17: the Phase 1 client offers exactly five combinations —
 * Administrator or Receptionist at Organization or one Clinic, and Veterinarian
 * at Organization scope only (never a Clinic; Clinic practice is a Clinic
 * Assignment, SPEC-ORG-005 §4).
 */
export const STAFF_INVITE_ROLES = ['ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN'] as const;
export type StaffInviteRole = (typeof STAFF_INVITE_ROLES)[number];
export type StaffInviteScope = 'ORGANIZATION' | 'CLINIC';
export type StaffInviteInput = {
  organizationId: string;
  recipientEmail: string;
  role: StaffInviteRole;
  scope: StaffInviteScope;
  clinicId: string | null;
};
/** Calm codes of the `create-organization-invitation` route (SPEC-ORG-002 §10). */
export const STAFF_INVITE_REJECTIONS = [
  'INVALID_REQUEST',
  'AUTHENTICATION_REQUIRED',
  'ACCOUNT_VERIFICATION_REQUIRED',
  'ORGANIZATION_UNAVAILABLE',
  'INVALID_RECIPIENT',
  'INVALID_ROLE_SCOPE',
  'INVALID_CLINIC',
  'PENDING_INVITATION_EXISTS',
  'ACTIVE_MEMBER',
] as const;
export type StaffInviteRejection = (typeof STAFF_INVITE_REJECTIONS)[number];
/**
 * `uncertain`: no definite answer (network failure, relay error, 5xx, or a
 * malformed success). The Invitation may or may not exist; the caller
 * reconciles by re-reading Staff and never retries the creation itself.
 */
export type StaffInviteResult =
  | { kind: 'created'; invitationId: string }
  | { kind: 'rejected'; reason: StaffInviteRejection }
  | { kind: 'uncertain' };

/** The exact Phase 1 request body: no expiry, recipient User, or responsibility array. */
export function staffInviteRequestBody(input: StaffInviteInput): Record<string, unknown> {
  return {
    organization_id: input.organizationId,
    // Sent as typed: the backend's trim/case normalization is authoritative.
    recipient_email: input.recipientEmail,
    responsibility: input.role,
    scope_type: input.scope,
    clinic_id: input.scope === 'CLINIC' ? input.clinicId : null,
  };
}

function isRejection(raw: unknown): raw is StaffInviteRejection {
  return (STAFF_INVITE_REJECTIONS as readonly unknown[]).includes(raw);
}

/** A non-2xx Edge answer carries its Response as `context` (FunctionsHttpError). */
async function inviteFailure(error: unknown): Promise<StaffInviteResult> {
  if (!(error instanceof Error) || error.name !== 'FunctionsHttpError')
    return { kind: 'uncertain' };
  const context = (error as Error & { context?: unknown }).context;
  if (!isRecord(context) || typeof context.status !== 'number') return { kind: 'uncertain' };
  const status = context.status;
  if (status === 401) return { kind: 'rejected', reason: 'AUTHENTICATION_REQUIRED' };
  if (status !== 400 && status !== 403 && status !== 409) return { kind: 'uncertain' };
  let code: unknown = null;
  try {
    const body: unknown = typeof context.json === 'function' ? await context.json() : null;
    code = isRecord(body) ? body.error : null;
  } catch {
    code = null;
  }
  if (isRejection(code)) return { kind: 'rejected', reason: code };
  // A definite rejection whose detail is unreadable still created nothing.
  return {
    kind: 'rejected',
    reason:
      status === 403
        ? 'ORGANIZATION_UNAVAILABLE'
        : status === 409
          ? 'PENDING_INVITATION_EXISTS'
          : 'INVALID_REQUEST',
  };
}

/** Creates one Invitation through the trusted Communications route; never retried here. */
export async function inviteOrganizationStaff(input: StaffInviteInput): Promise<StaffInviteResult> {
  try {
    const { data, error } = await supabase.functions.invoke<unknown>(
      'communications/create-organization-invitation',
      { body: staffInviteRequestBody(input) },
    );
    if (error) return await inviteFailure(error);
    return isRecord(data) && isId(data.invitation_id)
      ? { kind: 'created', invitationId: data.invitation_id }
      : { kind: 'uncertain' };
  } catch {
    return { kind: 'uncertain' };
  }
}

/** SPEC-ORG-010 BR-1 outcomes. Only `REVOKED` changed state. */
export const INVITATION_REVOCATION_OUTCOMES = [
  'REVOKED',
  'ALREADY_REVOKED',
  'ACCEPTED',
  'EXPIRED',
  'REJECTED',
] as const;
export type InvitationRevocationOutcome = (typeof INVITATION_REVOCATION_OUTCOMES)[number];
export type InvitationRevocationResult =
  | { kind: 'outcome'; outcome: InvitationRevocationOutcome }
  | { kind: 'accessDenied' }
  | { kind: 'authenticationRequired' }
  | { kind: 'uncertain' };

export async function revokeOrganizationInvitation(
  invitationId: string,
): Promise<InvitationRevocationResult> {
  if (!isId(invitationId)) return { kind: 'accessDenied' };
  try {
    const { data, error } = await supabase.rpc('revoke_organization_invitation', {
      p_invitation_id: invitationId,
    });
    if (error) {
      if (error.code === '42501') return { kind: 'accessDenied' };
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      return { kind: 'uncertain' };
    }
    const outcome = INVITATION_REVOCATION_OUTCOMES.find(
      (candidate) => isRecord(data) && data.outcome === candidate,
    );
    return outcome !== undefined &&
      isRecord(data) &&
      typeof data.invitation_id === 'string' &&
      data.invitation_id.toLowerCase() === invitationId.toLowerCase()
      ? { kind: 'outcome', outcome }
      : { kind: 'uncertain' };
  } catch {
    return { kind: 'uncertain' };
  }
}

/** SPEC-ORG-004 BR-20/BR-26 outcomes; both mean the Membership has ended. */
export const STAFF_END_ACCESS_OUTCOMES = ['ENDED', 'ALREADY_ENDED'] as const;
export type StaffEndAccessOutcome = (typeof STAFF_END_ACCESS_OUTCOMES)[number];
export type StaffEndAccessResult =
  | { kind: 'outcome'; outcome: StaffEndAccessOutcome; effectiveEnd: string }
  | { kind: 'accessDenied' }
  | { kind: 'authenticationRequired' }
  /** Own Membership or an Owner (BR-22): never offered, but stale state can reach it. */
  | { kind: 'protected' }
  | { kind: 'uncertain' };

/** The client sends only the Membership id; the backend decides everything else. */
export async function endOrganizationStaffMembership(
  membershipId: string,
): Promise<StaffEndAccessResult> {
  if (!isId(membershipId)) return { kind: 'accessDenied' };
  try {
    const { data, error } = await supabase.rpc('end_organization_staff_membership', {
      p_membership_id: membershipId,
    });
    if (error) {
      if (error.code === '42501') return { kind: 'accessDenied' };
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '23514') return { kind: 'protected' };
      return { kind: 'uncertain' };
    }
    const outcome = STAFF_END_ACCESS_OUTCOMES.find(
      (candidate) => isRecord(data) && data.outcome === candidate,
    );
    return outcome !== undefined &&
      isRecord(data) &&
      typeof data.membership_id === 'string' &&
      data.membership_id.toLowerCase() === membershipId.toLowerCase() &&
      isInstant(data.effective_end)
      ? { kind: 'outcome', outcome, effectiveEnd: data.effective_end }
      : { kind: 'uncertain' };
  } catch {
    return { kind: 'uncertain' };
  }
}

// ---------------------------------------------------------------------------
// Paged reads of the Staff screen (SPEC-ORG-009 §12)
// ---------------------------------------------------------------------------

/**
 * One row of `get_organization_staff_members` (BR-13): a BR-1 member plus
 * `displayNameIsShared` (BR-14) — whether another current member of the
 * Organization has the identical display name, decided by the backend over
 * every current member, so namesakes stay distinguishable across pages.
 */
export type StaffMemberRow = StaffMember & { displayNameIsShared: boolean };

/** The complete key of a Members row (BR-13), exactly as the backend returned it. */
export type StaffMembersCursor = { effectiveStart: string; membershipId: string };

/** The complete key of a pending Invitation row (BR-15), exactly as the backend returned it. */
export type StaffInvitationsCursor = { createdAt: string; invitationId: string };

export type StaffPageResult<T> = { data: T[]; error: null } | { data: null; error: string };

/**
 * Exported for unit testing: one Members page — every row a strict BR-1
 * member with a boolean `display_name_is_shared` that is never true without a
 * name, no member twice. Anything else is `null`.
 */
export function parseStaffMembersPage(raw: unknown): StaffMemberRow[] | null {
  if (!Array.isArray(raw)) return null;
  const rows: StaffMemberRow[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const member = parseMember(item);
    if (member === null || !isRecord(item) || typeof item.display_name_is_shared !== 'boolean') {
      return null;
    }
    if (item.display_name_is_shared && member.displayName === null) return null;
    if (seen.has(member.membershipId)) return null;
    seen.add(member.membershipId);
    rows.push({ ...member, displayNameIsShared: item.display_name_is_shared });
  }
  return rows;
}

/** Exported for unit testing: one pending Invitations page — strict BR-7 rows, none twice. */
export function parseStaffInvitationsPage(raw: unknown): PendingStaffInvitation[] | null {
  const invitations = parseArray(raw, parseInvitation);
  if (invitations === null) return null;
  const ids = new Set(invitations.map((invitation) => invitation.invitationId));
  return ids.size === invitations.length ? invitations : null;
}

export function staffMembersCursorOf(row: StaffMemberRow): StaffMembersCursor {
  return { effectiveStart: row.effectiveStart, membershipId: row.membershipId };
}

export function staffInvitationsCursorOf(
  invitation: PendingStaffInvitation,
): StaffInvitationsCursor {
  return { createdAt: invitation.createdAt, invitationId: invitation.invitationId };
}

async function readStaffPage<T>(
  name: string,
  args: Record<string, unknown>,
  parse: (raw: unknown) => T[] | null,
): Promise<StaffPageResult<T>> {
  try {
    const { data, error } = await supabase.rpc(name, args);
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
    const rows = parse(data);
    return rows === null ? { data: null, error: STAFF_MALFORMED } : { data: rows, error: null };
  } catch (error) {
    return { data: null, error: error instanceof Error ? error.message : 'Staff read failed' };
  }
}

/**
 * One page of the Organization's current members (SPEC-ORG-009 BR-13);
 * `after` null reads the first page. The backend authorizes the route
 * Organization on every call; its uniform 42501 is STAFF_ACCESS_DENIED.
 */
export function getOrganizationStaffMembersPage(
  organizationId: string,
  after: StaffMembersCursor | null,
  limit: number,
): Promise<StaffPageResult<StaffMemberRow>> {
  if (!isId(organizationId)) return Promise.resolve({ data: null, error: STAFF_ACCESS_DENIED });
  return readStaffPage(
    'get_organization_staff_members',
    {
      p_organization_id: organizationId,
      p_after_effective_start: after?.effectiveStart ?? null,
      p_after_membership_id: after?.membershipId ?? null,
      p_limit: limit,
    },
    parseStaffMembersPage,
  );
}

/** One page of the Organization's pending Invitations (SPEC-ORG-009 BR-15). */
export function getOrganizationPendingInvitationsPage(
  organizationId: string,
  after: StaffInvitationsCursor | null,
  limit: number,
): Promise<StaffPageResult<PendingStaffInvitation>> {
  if (!isId(organizationId)) return Promise.resolve({ data: null, error: STAFF_ACCESS_DENIED });
  return readStaffPage(
    'get_organization_pending_invitations',
    {
      p_organization_id: organizationId,
      p_after_created_at: after?.createdAt ?? null,
      p_after_invitation_id: after?.invitationId ?? null,
      p_limit: limit,
    },
    parseStaffInvitationsPage,
  );
}

// A backend timestamptz as exact microseconds since the epoch, or `null` when
// it cannot be read without losing precision. `Date.parse` alone would drop
// the microseconds that order two keys.
const TIMESTAMP =
  /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?)(?:\.(\d{1,6}))?(Z|[+-]\d{2}(?::?\d{2})?)$/;
function exactMicroseconds(instant: string): bigint | null {
  const match = TIMESTAMP.exec(instant);
  if (match === null) return null;
  const [, base, fraction = '', zone] = match;
  const offset =
    zone === 'Z' ? 'Z' : zone.length === 3 ? `${zone}:00` : `${zone.slice(0, 3)}:${zone.slice(-2)}`;
  const milliseconds = Date.parse(`${base}${offset}`);
  if (!Number.isFinite(milliseconds)) return null;
  return BigInt(milliseconds) * 1000n + BigInt(fraction.padEnd(6, '0'));
}

/**
 * The order of two pending-Invitation keys exactly as BR-15 sorts them —
 * `created_at`, then the uuid, whose order is its lowercase hexadecimal text —
 * or `null` when a timestamp cannot be compared exactly.
 */
export function compareStaffInvitationKeys(
  a: StaffInvitationsCursor,
  b: StaffInvitationsCursor,
): number | null {
  const first = exactMicroseconds(a.createdAt);
  const second = exactMicroseconds(b.createdAt);
  if (first === null || second === null) return null;
  if (first !== second) return first < second ? -1 : 1;
  const left = a.invitationId.toLowerCase();
  const right = b.invitationId.toLowerCase();
  return left === right ? 0 : left < right ? -1 : 1;
}

/**
 * Whether one Invitation is still pending after a revocation whose response
 * was lost, read as ONE row (SPEC-ORG-009 BR-15) instead of the whole list.
 *
 * The read returns the smallest pending key after `previous` — the Invitation
 * listed just before it, or `null` when it was listed first. Only what that
 * key proves is reported:
 * - it is this Invitation → `pending`;
 * - there is none, or it sorts AFTER this Invitation → `notPending`: had this
 *   Invitation still been pending, its smaller key would have been returned;
 * - it sorts BEFORE this Invitation → `error` (inconclusive). That is another
 *   Invitation that became visible meanwhile — e.g. created concurrently and
 *   committed after the list was read, whose `created_at` (the statement's
 *   start, to the millisecond) still precedes this one's, or tied in the same
 *   millisecond with a smaller id. Its presence says nothing about this
 *   Invitation, so a change of position is never taken as a revocation.
 */
export async function recheckPendingInvitation(
  organizationId: string,
  invitation: PendingStaffInvitation,
  previous: PendingStaffInvitation | null,
): Promise<'pending' | 'notPending' | 'unavailable' | 'error'> {
  const result = await getOrganizationPendingInvitationsPage(
    organizationId,
    previous === null ? null : staffInvitationsCursorOf(previous),
    1,
  );
  if (result.error === STAFF_ACCESS_DENIED) return 'unavailable';
  if (result.error !== null) return 'error';
  const next = result.data[0];
  if (next === undefined) return 'notPending';
  if (next.invitationId.toLowerCase() === invitation.invitationId.toLowerCase()) return 'pending';
  const order = compareStaffInvitationKeys(
    staffInvitationsCursorOf(next),
    staffInvitationsCursorOf(invitation),
  );
  return order !== null && order > 0 ? 'notPending' : 'error';
}

/**
 * Only the full read RPC; every request authorizes the explicit route
 * Organization server-side. Kept for the Member detail and the Invite flow;
 * the Staff list reads the pages above.
 */
export async function getOrganizationStaff(organizationId: string): Promise<StaffResult> {
  if (!isId(organizationId)) return { data: null, error: STAFF_ACCESS_DENIED };
  try {
    const { data, error } = await supabase.rpc('get_organization_staff', {
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
    const staff = parseOrganizationStaff(data, organizationId);
    return staff === null ? { data: null, error: STAFF_MALFORMED } : { data: staff, error: null };
  } catch (error) {
    return { data: null, error: error instanceof Error ? error.message : 'Staff read failed' };
  }
}

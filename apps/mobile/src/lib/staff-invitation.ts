import type {
  InvitationRevocationOutcome,
  InvitationRevocationResult,
  OrganizationStaff,
  StaffEndAccessResult,
  StaffInviteInput,
  StaffInviteRejection,
  StaffInviteRole,
  StaffInviteScope,
  StaffResult,
} from '@/data/organization-staff';
import { STAFF_ACCESS_DENIED } from '@/data/organization-staff';
import type { ProfessionalCapability, ProfessionalContext } from '@/data/professional-context';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Advisory Staff actions (SPEC-ORG-009 §7). The backend re-authorizes every
 * write. `manage` opens the Member detail and its Responsibility actions
 * (ORGANIZATION_GRANT_RESPONSIBILITIES, SPEC-ORG-006 §14); `manageAssignments`
 * offers Clinic Assignment actions there (Organization-scoped
 * CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS, SPEC-VET-004/005 §13).
 */
export type StaffActions = {
  invite: boolean;
  revoke: boolean;
  endAccess: boolean;
  manage: boolean;
  manageAssignments: boolean;
};
export const NO_STAFF_ACTIONS: StaffActions = {
  invite: false,
  revoke: false,
  endAccess: false,
  manage: false,
  manageAssignments: false,
};

export function staffActionsFor(
  context: ProfessionalContext | null,
  organizationId: string,
): StaffActions {
  const organization = context?.organizations.find(
    (candidate) => candidate.organizationId.toLowerCase() === organizationId.toLowerCase(),
  );
  const holds = (capability: ProfessionalCapability) =>
    organization?.capabilities.some(
      (entry) => entry.capability === capability && entry.scope.type === 'ORGANIZATION',
    ) ?? false;
  return {
    invite: holds('ORGANIZATION_INVITE_MEMBERS'),
    revoke: holds('ORGANIZATION_REVOKE_INVITATIONS'),
    endAccess: holds('ORGANIZATION_END_MEMBERSHIPS'),
    manage: holds('ORGANIZATION_GRANT_RESPONSIBILITIES'),
    manageAssignments: holds('CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'),
  };
}

export type StaffInviteDraft = {
  email: string;
  role: StaffInviteRole | null;
  scope: StaffInviteScope;
  clinicId: string | null;
};
export const EMPTY_STAFF_INVITE_DRAFT: StaffInviteDraft = {
  email: '',
  role: null,
  scope: 'ORGANIZATION',
  clinicId: null,
};

/** Changing the scope always discards a drafted Clinic. */
export function withInviteScope(
  draft: StaffInviteDraft,
  scope: StaffInviteScope,
): StaffInviteDraft {
  if (draft.role === 'VETERINARIAN') return draft;
  return scope === draft.scope ? draft : { ...draft, scope, clinicId: null };
}

/** VETERINARIAN is Organization-scoped only (SPEC-ORG-002 BR-17): its scope is fixed. */
export function withInviteRole(draft: StaffInviteDraft, role: StaffInviteRole): StaffInviteDraft {
  return role === 'VETERINARIAN'
    ? { ...draft, role, scope: 'ORGANIZATION', clinicId: null }
    : { ...draft, role };
}

/** Whether the form shows the scope and Clinic choices for the drafted role. */
export function inviteRoleHasScopeChoice(role: StaffInviteRole | null): boolean {
  return role !== 'VETERINARIAN';
}

export type InviteClinicOption = { clinicId: string; displayName: string | null };

/** Only the route Organization's Clinics, from the authorized Professional Clinics read. */
export function inviteClinicOptions(
  clinics: readonly ProfessionalClinic[],
  organizationId: string,
): InviteClinicOption[] {
  return clinics
    .filter((clinic) => clinic.organizationId.toLowerCase() === organizationId.toLowerCase())
    .map((clinic) => ({ clinicId: clinic.clinicId, displayName: clinic.clinicDisplayName }));
}

/** Completeness only; address validity is the backend's decision. */
export function canSendInvite(
  draft: StaffInviteDraft,
  clinics: readonly InviteClinicOption[],
  busy: boolean,
): boolean {
  return (
    !busy &&
    draft.email.trim() !== '' &&
    draft.role !== null &&
    (draft.role !== 'VETERINARIAN' || draft.scope === 'ORGANIZATION') &&
    (draft.scope === 'ORGANIZATION' ||
      (draft.clinicId !== null && clinics.some((clinic) => clinic.clinicId === draft.clinicId)))
  );
}

export function inviteInputFrom(
  organizationId: string,
  draft: StaffInviteDraft,
): StaffInviteInput | null {
  if (
    draft.role === null ||
    (draft.scope === 'CLINIC' && (draft.clinicId === null || draft.role === 'VETERINARIAN'))
  )
    return null;
  return {
    organizationId,
    recipientEmail: draft.email,
    role: draft.role,
    scope: draft.scope,
    clinicId: draft.scope === 'CLINIC' ? draft.clinicId : null,
  };
}

// The backend's btrim set and case-insensitive comparison (SPEC-ORG-002 BR-19).
// Used only to recognize the read's normalized address, never to alter input.
export function normalizedInvitationEmail(email: string): string {
  return email.replace(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g, '').toLowerCase();
}

export function pendingInvitationIds(staff: OrganizationStaff): Set<string> {
  return new Set(staff.pendingInvitations.map((invitation) => invitation.invitationId));
}

export type LostInviteReconciliation =
  'created' | 'pendingExists' | 'unconfirmed' | 'accessLost' | 'authenticationRequired';

/**
 * After an uncertain invite (SPEC-ORG-002 §10): success is proven only by a
 * pending Invitation that was absent from the read taken just before
 * submitting and matches the submitted address, role, scope and Clinic
 * exactly. An older pending Invitation for the address is reported as the
 * conflict BR-19 would have produced, never as this request's success.
 */
export function reconcileLostInvite(
  read: StaffResult,
  input: StaffInviteInput,
  pendingBefore: ReadonlySet<string>,
): LostInviteReconciliation {
  if (read.error === STAFF_ACCESS_DENIED) return 'accessLost';
  if (read.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'authenticationRequired';
  if (read.error !== null) return 'unconfirmed';
  const address = normalizedInvitationEmail(input.recipientEmail);
  const sameAddress = read.data.pendingInvitations.filter(
    (invitation) => invitation.recipientEmail === address,
  );
  const created = sameAddress.find((invitation) => {
    const [only, ...rest] = invitation.responsibilities;
    return (
      !pendingBefore.has(invitation.invitationId) &&
      rest.length === 0 &&
      only !== undefined &&
      only.responsibility === input.role &&
      only.scope.type === input.scope &&
      (only.scope.type === 'ORGANIZATION' || only.scope.clinic.clinicId === input.clinicId)
    );
  });
  if (created !== undefined) return 'created';
  return sameAddress.some((invitation) => pendingBefore.has(invitation.invitationId))
    ? 'pendingExists'
    : 'unconfirmed';
}

const INVITE_REJECTION_KEYS: Record<StaffInviteRejection, TranslationKey> = {
  INVALID_REQUEST: 'staffInvite.failed',
  AUTHENTICATION_REQUIRED: 'errors.sessionExpired',
  ACCOUNT_VERIFICATION_REQUIRED: 'staffInvite.verificationRequired',
  ORGANIZATION_UNAVAILABLE: 'staffInvite.unavailable',
  INVALID_RECIPIENT: 'staffInvite.invalidRecipient',
  INVALID_ROLE_SCOPE: 'staffInvite.invalidRoleScope',
  INVALID_CLINIC: 'staffInvite.invalidClinic',
  PENDING_INVITATION_EXISTS: 'staffInvite.pendingExists',
  ACTIVE_MEMBER: 'staffInvite.activeMember',
};
export function inviteRejectionKey(reason: StaffInviteRejection): TranslationKey {
  return INVITE_REJECTION_KEYS[reason];
}

const REVOCATION_OUTCOME_KEYS: Record<InvitationRevocationOutcome, TranslationKey> = {
  REVOKED: 'staff.revoked',
  ALREADY_REVOKED: 'staff.revoked',
  ACCEPTED: 'staff.revokeAccepted',
  EXPIRED: 'staff.revokeExpired',
  REJECTED: 'staff.revokeRejected',
};

export type StaffNotice = { tone: 'info' | 'error'; messageKey: TranslationKey };

/**
 * What the Staff screen learned when it re-checked one Invitation after a
 * revocation attempt (SPEC-ORG-010 §5): still pending, no longer pending, the
 * Staff access was denied, or the check failed; `null` when the screen is no
 * longer active or did not need to check.
 */
export type RevocationRecheck = 'pending' | 'notPending' | 'unavailable' | 'error' | null;

/**
 * What the Staff screen says after a revocation attempt and its authoritative
 * re-check (SPEC-ORG-010 §5). `accessLost` means the screen must leave. An
 * uncertain attempt whose Invitation is no longer pending is reported as
 * exactly that, never as a revocation: it may have been accepted or expired.
 */
export function revocationNotice(
  result: InvitationRevocationResult,
  recheck: RevocationRecheck,
): StaffNotice | 'accessLost' {
  if (result.kind === 'accessDenied' || recheck === 'unavailable') return 'accessLost';
  if (result.kind === 'outcome') {
    return { tone: 'info', messageKey: REVOCATION_OUTCOME_KEYS[result.outcome] };
  }
  if (result.kind === 'authenticationRequired') {
    return { tone: 'error', messageKey: 'errors.sessionExpired' };
  }
  if (recheck === 'notPending') {
    return { tone: 'info', messageKey: 'staff.revokeNoLongerPending' };
  }
  return { tone: 'error', messageKey: 'staff.revokeFailed' };
}

/** The Member detail's re-read, structurally (null when the screen is no longer active). */
export type StaffReread =
  { kind: 'loaded'; staff: OrganizationStaff } | { kind: 'unavailable' } | { kind: 'error' } | null;

/**
 * What the Member detail says after an End access attempt and its
 * authoritative re-read (SPEC-ORG-004 §10). `ENDED` and `ALREADY_ENDED` are the
 * same success: the Membership has ended. A lost response is success only when
 * the re-read no longer lists the Membership; otherwise it stays a calm
 * failure that can be retried deliberately (the operation is idempotent).
 */
export function endAccessNotice(
  result: StaffEndAccessResult,
  reread: StaffReread,
  membershipId: string,
): StaffNotice | 'accessLost' {
  if (result.kind === 'accessDenied' || reread?.kind === 'unavailable') return 'accessLost';
  if (result.kind === 'outcome') return { tone: 'info', messageKey: 'staff.endAccessDone' };
  if (result.kind === 'authenticationRequired') {
    return { tone: 'error', messageKey: 'errors.sessionExpired' };
  }
  if (result.kind === 'protected')
    return { tone: 'error', messageKey: 'staff.endAccessNotAllowed' };
  if (
    reread?.kind === 'loaded' &&
    !reread.staff.members.some((member) => member.membershipId === membershipId)
  ) {
    return { tone: 'info', messageKey: 'staff.endAccessDone' };
  }
  return { tone: 'error', messageKey: 'staff.endAccessFailed' };
}

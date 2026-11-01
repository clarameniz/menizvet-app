import type { Href } from 'expo-router';

import type {
  OrganizationStaff,
  StaffMember,
  StaffResponsibility,
} from '@/data/organization-staff';
import type {
  ClinicAssignmentRejection,
  ClinicAssignmentResult,
  StaffEditableRole,
  StaffResponsibilityInput,
  StaffResponsibilityRejection,
  StaffResponsibilityResult,
  StaffScopeType,
  VeterinarianWorkforce,
  WorkforceClinicAssignment,
  WorkforceMember,
} from '@/data/staff-workforce';
import type { TranslationKey } from '@/i18n/i18n';
import { staffMemberName, staffResponsibilityLabel } from '@/lib/organization-staff';
import type { InviteClinicOption, StaffActions } from '@/lib/staff-invitation';

/**
 * Pure presentation model of the Staff Member detail (SPEC-ORG-009 §7,
 * SPEC-ORG-006 §14, SPEC-VET-004/005 §13, SPEC-VET-006). Everything here is
 * advisory: the backend re-decides every rule and every write.
 */

type Translate = (key: TranslationKey, options?: Record<string, string | number>) => string;

export function staffMemberHref(organizationId: string, membershipId: string): Href {
  return {
    pathname: '/professional/organizations/[organizationId]/staff/[membershipId]',
    params: { organizationId, membershipId },
  };
}
/** A role that may be added for one more Clinic ("Añadir clínica de recepción"). */
export type ClinicRole = 'ADMINISTRATOR' | 'RECEPTIONIST';
/**
 * Add when `responsibilityGrantId` is null — optionally preset to one more
 * Clinic of `clinicRole` — otherwise Change exactly that Grant.
 */
export function staffResponsibilityEditorHref(
  organizationId: string,
  membershipId: string,
  responsibilityGrantId: string | null,
  clinicRole: ClinicRole | null = null,
): Href {
  return {
    pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/responsibility',
    params:
      responsibilityGrantId !== null
        ? { organizationId, membershipId, grantId: responsibilityGrantId }
        : clinicRole !== null
          ? { organizationId, membershipId, clinicRole }
          : { organizationId, membershipId },
  };
}
export function parseClinicRole(value: unknown): ClinicRole | null {
  return value === 'ADMINISTRATOR' || value === 'RECEPTIONIST' ? value : null;
}
export function staffClinicAssignmentHref(organizationId: string, membershipId: string): Href {
  return {
    pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/assign-clinic',
    params: { organizationId, membershipId },
  };
}

export const holdsOwner = (member: StaffMember) =>
  member.responsibilities.some((role) => role.responsibility === 'OWNER');
export const holdsVeterinarian = (member: StaffMember) =>
  member.responsibilities.some((role) => role.responsibility === 'VETERINARIAN');

/**
 * SPEC-ORG-006 BR-50–BR-52: OWNER Grants are never changed or ended; another
 * actor's Owner Membership is never touched; a non-Owner never changes or
 * ends their own Grants (Add to oneself is allowed).
 */
export type ResponsibilityPolicy = {
  canAdd: boolean;
  canChange: (grant: StaffResponsibility) => boolean;
  canEnd: (grant: StaffResponsibility) => boolean;
};
export function responsibilityPolicy(
  member: StaffMember,
  actions: StaffActions,
): ResponsibilityPolicy {
  const owner = holdsOwner(member);
  const othersOwner = owner && !member.isSelf;
  const selfNonOwner = member.isSelf && !owner;
  const canEdit = (grant: StaffResponsibility) =>
    actions.manage && grant.responsibility !== 'OWNER' && !othersOwner && !selfNonOwner;
  return { canAdd: actions.manage && !othersOwner, canChange: canEdit, canEnd: canEdit };
}

export type VeterinarianSection =
  | { visible: false }
  | {
      visible: true;
      profile: 'completed' | 'pending';
      assignments: WorkforceClinicAssignment[];
      canAssign: boolean;
      canEndAssignments: boolean;
    };
/**
 * Shown for a current VETERINARIAN Grant or a current Clinic Assignment
 * (SPEC-VET-006 BR-3). Assign requires VETERINARIAN and a Profile
 * (SPEC-VET-004 BR-23); ending never requires VETERINARIAN (SPEC-VET-005
 * BR-26). Joined to the Staff read by Membership id only.
 */
export function veterinarianSection(
  member: StaffMember,
  workforce: WorkforceMember | null,
  actions: StaffActions,
  clinics: readonly InviteClinicOption[],
): VeterinarianSection {
  const assignments = workforce?.clinicAssignments ?? [];
  const veterinarian = holdsVeterinarian(member);
  if (!veterinarian && assignments.length === 0) return { visible: false };
  const completed = workforce?.hasVeterinarianProfessionalProfile === true;
  return {
    visible: true,
    profile: completed ? 'completed' : 'pending',
    assignments,
    canAssign:
      actions.manageAssignments &&
      veterinarian &&
      completed &&
      assignableClinics(clinics, assignments).length > 0,
    canEndAssignments: actions.manageAssignments,
  };
}
// ---------------------------------------------------------------------------
// Grouped presentation: person → responsibility → Clinics
// ---------------------------------------------------------------------------

/** One current Grant with the actions the policy offers on it. */
export type GrantRow = { grant: StaffResponsibility; canChange: boolean; canEnd: boolean };
export type ResponsibilityGroup =
  | { role: 'OWNER'; grants: StaffResponsibility[] }
  | {
      role: 'VETERINARIAN';
      /** Null for a stale Assignment whose VETERINARIAN Grant already ended. */
      grant: GrantRow | null;
      section: Extract<VeterinarianSection, { visible: true }>;
    }
  | {
      role: ClinicRole;
      /** The Organization-scoped Grant: every Clinic, including future ones. */
      organizationGrant: GrantRow | null;
      clinicGrants: GrantRow[];
      /** An Organization-scoped Grant already covers the Clinic-scoped ones. */
      redundant: boolean;
      /** Add one more Clinic: only while some Clinic is not yet covered. */
      canAddClinic: boolean;
    };
const GROUP_ORDER = ['OWNER', 'VETERINARIAN', 'RECEPTIONIST', 'ADMINISTRATOR'] as const;
/**
 * The Member detail grouped by responsibility, with each responsibility's
 * Clinics underneath (SPEC-ORG-009 §7). Purely presentational: every current
 * Grant appears exactly once with its own actions, nothing is merged,
 * hidden or changed, and the Veterinarian group joins the Grant with the
 * Profile status and Clinic Assignments from the workforce read.
 */
export function responsibilityGroups(
  member: StaffMember,
  workforce: WorkforceMember | null,
  actions: StaffActions,
  clinics: readonly InviteClinicOption[],
): ResponsibilityGroup[] {
  const policy = responsibilityPolicy(member, actions);
  const row = (grant: StaffResponsibility): GrantRow => ({
    grant,
    canChange: policy.canChange(grant),
    canEnd: policy.canEnd(grant),
  });
  const held = (role: StaffResponsibility['responsibility']) =>
    member.responsibilities.filter((grant) => grant.responsibility === role);
  const groups: ResponsibilityGroup[] = [];
  for (const role of GROUP_ORDER) {
    const grants = held(role);
    if (role === 'OWNER') {
      if (grants.length > 0) groups.push({ role, grants });
    } else if (role === 'VETERINARIAN') {
      const section = veterinarianSection(member, workforce, actions, clinics);
      if (section.visible)
        groups.push({ role, grant: grants.length > 0 ? row(grants[0]) : null, section });
    } else if (grants.length > 0) {
      const organizationGrant = grants.find((grant) => grant.scope.type === 'ORGANIZATION');
      const clinicGrants = grants.filter((grant) => grant.scope.type === 'CLINIC');
      groups.push({
        role,
        organizationGrant: organizationGrant === undefined ? null : row(organizationGrant),
        clinicGrants: clinicGrants.map(row),
        redundant: organizationGrant !== undefined && clinicGrants.length > 0,
        canAddClinic:
          policy.canAdd &&
          organizationGrant === undefined &&
          clinicChoices(role, member, clinics, null).length > 0,
      });
    }
  }
  return groups;
}
/**
 * The route Organization's Clinics a `role` may still be given, keeping the
 * Clinic of the Grant being changed: a Clinic the Member already holds for
 * that role would be a duplicate (SPEC-ORG-006 BR-35). Advisory only.
 */
export function clinicChoices(
  role: StaffEditableRole | null,
  member: StaffMember,
  clinics: readonly InviteClinicOption[],
  original: StaffResponsibility | null,
): InviteClinicOption[] {
  const taken = new Set(
    member.responsibilities
      .filter(
        (grant) =>
          grant.responsibility === role &&
          grant.responsibilityGrantId !== original?.responsibilityGrantId,
      )
      .flatMap((grant) =>
        grant.scope.type === 'CLINIC' ? [grant.scope.clinic.clinicId.toLowerCase()] : [],
      ),
  );
  return clinics.filter((clinic) => !taken.has(clinic.clinicId.toLowerCase()));
}

export function workforceEntryFor(
  workforce: VeterinarianWorkforce,
  membershipId: string,
): WorkforceMember | null {
  return (
    workforce.members.find(
      (entry) => entry.membershipId.toLowerCase() === membershipId.toLowerCase(),
    ) ?? null
  );
}
/** The route Organization's Clinics without a current Assignment for the Member. */
export function assignableClinics(
  clinics: readonly InviteClinicOption[],
  assignments: readonly WorkforceClinicAssignment[],
): InviteClinicOption[] {
  const assigned = new Set(assignments.map((entry) => entry.clinic.clinicId.toLowerCase()));
  return clinics.filter((clinic) => !assigned.has(clinic.clinicId.toLowerCase()));
}

// ---------------------------------------------------------------------------
// Responsibility editor draft (SPEC-ORG-006 BR-49)
// ---------------------------------------------------------------------------

export type ResponsibilityDraft = {
  role: StaffEditableRole | null;
  scope: StaffScopeType;
  clinicId: string | null;
};
export const EMPTY_RESPONSIBILITY_DRAFT: ResponsibilityDraft = {
  role: null,
  scope: 'ORGANIZATION',
  clinicId: null,
};
/** "Añadir clínica de recepción" starts at that role with Clinic scope and no Clinic yet. */
export function initialAddDraft(clinicRole: ClinicRole | null): ResponsibilityDraft {
  return clinicRole === null
    ? EMPTY_RESPONSIBILITY_DRAFT
    : { role: clinicRole, scope: 'CLINIC', clinicId: null };
}
export function draftFromGrant(grant: StaffResponsibility): ResponsibilityDraft {
  return {
    role: grant.responsibility === 'OWNER' ? null : grant.responsibility,
    scope: grant.scope.type,
    clinicId: grant.scope.type === 'CLINIC' ? grant.scope.clinic.clinicId : null,
  };
}
/** VETERINARIAN fixes the scope to the Organization and drops any Clinic. */
export function withDraftRole(
  draft: ResponsibilityDraft,
  role: StaffEditableRole,
): ResponsibilityDraft {
  return role === 'VETERINARIAN'
    ? { role, scope: 'ORGANIZATION', clinicId: null }
    : { ...draft, role };
}
export function withDraftScope(
  draft: ResponsibilityDraft,
  scope: StaffScopeType,
): ResponsibilityDraft {
  if (draft.role === 'VETERINARIAN' || scope === draft.scope) return draft;
  return { ...draft, scope, clinicId: null };
}
export function draftHasScopeChoice(draft: ResponsibilityDraft): boolean {
  return draft.role !== 'VETERINARIAN';
}
export function responsibilityInputFrom(
  draft: ResponsibilityDraft,
): StaffResponsibilityInput | null {
  if (draft.role === null) return null;
  if (draft.role === 'VETERINARIAN')
    return { role: draft.role, scope: 'ORGANIZATION', clinicId: null };
  if (draft.scope === 'CLINIC' && draft.clinicId === null) return null;
  return {
    role: draft.role,
    scope: draft.scope,
    clinicId: draft.scope === 'CLINIC' ? draft.clinicId : null,
  };
}
const sameResponsibility = (grant: StaffResponsibility, input: StaffResponsibilityInput) =>
  grant.responsibility === input.role &&
  grant.scope.type === input.scope &&
  (grant.scope.type === 'ORGANIZATION' ||
    grant.scope.clinic.clinicId.toLowerCase() === (input.clinicId ?? '').toLowerCase());
/**
 * Completeness, a Clinic of the route Organization, not a no-op Change, and
 * not a Responsibility the Member already holds (BR-35, BR-36).
 */
export function canSubmitResponsibility(
  draft: ResponsibilityDraft,
  member: StaffMember,
  clinics: readonly InviteClinicOption[],
  busy: boolean,
): boolean {
  const input = responsibilityInputFrom(draft);
  if (busy || input === null) return false;
  if (input.scope === 'CLINIC' && !clinics.some((clinic) => clinic.clinicId === input.clinicId))
    return false;
  return !member.responsibilities.some((grant) => sameResponsibility(grant, input));
}

// ---------------------------------------------------------------------------
// Outcomes after the authoritative re-read
// ---------------------------------------------------------------------------

export type MemberReread =
  | { kind: 'loaded'; staff: OrganizationStaff; workforce: VeterinarianWorkforce }
  | { kind: 'unavailable' }
  /** The Staff read no longer lists the Membership: it is not current any more. */
  | { kind: 'memberGone' }
  | { kind: 'error' }
  | null;
export type MemberNotice = {
  tone: 'info' | 'error';
  messageKey: TranslationKey;
  /** LAST_RESPONSIBILITY points to End access; VETERINARIAN_ASSIGNMENTS_ACTIVE to the Veterinarian section. */
  guidance?: 'endAccess' | 'veterinarianSection';
};
export type ResponsibilityIntent =
  | { kind: 'add'; membershipId: string; input: StaffResponsibilityInput }
  | { kind: 'change'; membershipId: string; grantId: string; input: StaffResponsibilityInput }
  | { kind: 'end'; membershipId: string; grantId: string };

const RESPONSIBILITY_REJECTION_KEYS: Record<StaffResponsibilityRejection, TranslationKey> = {
  INVALID_SCOPE: 'staffMember.invalidScope',
  INVALID_CLINIC: 'staffMember.invalidClinic',
  OWNER_GRANT: 'staffMember.ownerProtected',
  OWNER_MEMBERSHIP: 'staffMember.ownerProtected',
  SELF_MEMBERSHIP: 'staffMember.selfProtected',
  MEMBERSHIP_INACTIVE: 'staffMember.memberUnavailable',
  GRANT_ENDED: 'staffMember.grantChanged',
  NO_OP: 'staffMember.noChange',
  DUPLICATE: 'staffMember.duplicate',
  LAST_RESPONSIBILITY: 'staffMember.lastResponsibility',
  VETERINARIAN_ASSIGNMENTS_ACTIVE: 'staffMember.veterinarianAssignmentsActive',
};
const SUCCESS_KEYS: Record<ResponsibilityIntent['kind'], TranslationKey> = {
  add: 'staffMember.added',
  change: 'staffMember.changed',
  end: 'staffMember.ended',
};

/**
 * What the Member detail says after a Responsibility write and its re-read.
 * A lost response is success only when the re-read proves the intended state;
 * otherwise it is a calm "couldn't confirm" that the administrator may retry
 * deliberately (every operation reconciles a repeat).
 */
export function responsibilityNotice(
  result: StaffResponsibilityResult,
  reread: MemberReread,
  intent: ResponsibilityIntent,
): MemberNotice | 'accessLost' {
  if (result.kind === 'accessDenied' || reread?.kind === 'unavailable') return 'accessLost';
  if (result.kind === 'outcome') return { tone: 'info', messageKey: SUCCESS_KEYS[intent.kind] };
  if (result.kind === 'authenticationRequired')
    return { tone: 'error', messageKey: 'errors.sessionExpired' };
  if (result.kind === 'rejected') {
    const notice: MemberNotice = {
      tone: 'error',
      messageKey: RESPONSIBILITY_REJECTION_KEYS[result.reason],
    };
    if (result.reason === 'LAST_RESPONSIBILITY') notice.guidance = 'endAccess';
    if (result.reason === 'VETERINARIAN_ASSIGNMENTS_ACTIVE')
      notice.guidance = 'veterinarianSection';
    return notice;
  }
  const member =
    reread?.kind === 'loaded'
      ? reread.staff.members.find(
          (candidate) => candidate.membershipId.toLowerCase() === intent.membershipId.toLowerCase(),
        )
      : undefined;
  if (member !== undefined) {
    const holdsGrant = (grantId: string) =>
      member.responsibilities.some(
        (grant) => grant.responsibilityGrantId.toLowerCase() === grantId.toLowerCase(),
      );
    const proven =
      intent.kind === 'add'
        ? member.responsibilities.some((grant) => sameResponsibility(grant, intent.input))
        : intent.kind === 'change'
          ? !holdsGrant(intent.grantId) &&
            member.responsibilities.some((grant) => sameResponsibility(grant, intent.input))
          : !holdsGrant(intent.grantId);
    if (proven) return { tone: 'info', messageKey: SUCCESS_KEYS[intent.kind] };
  }
  return { tone: 'error', messageKey: 'staffMember.unconfirmed' };
}

export type AssignmentIntent =
  | { kind: 'assign'; membershipId: string; clinicId: string }
  | { kind: 'end'; membershipId: string; assignmentId: string };
const ASSIGNMENT_REJECTION_KEYS: Record<ClinicAssignmentRejection, TranslationKey> = {
  MEMBERSHIP_INACTIVE: 'staffMember.memberUnavailable',
  VETERINARIAN_RESPONSIBILITY_REQUIRED: 'staffAssignment.veterinarianRequired',
  PROFILE_REQUIRED: 'staffAssignment.profileRequired',
};
export function assignmentNotice(
  result: ClinicAssignmentResult,
  reread: MemberReread,
  intent: AssignmentIntent,
): MemberNotice | 'accessLost' {
  if (result.kind === 'accessDenied' || reread?.kind === 'unavailable') return 'accessLost';
  const success: TranslationKey =
    intent.kind === 'assign' ? 'staffAssignment.assigned' : 'staffAssignment.ended';
  if (result.kind === 'outcome') return { tone: 'info', messageKey: success };
  if (result.kind === 'authenticationRequired')
    return { tone: 'error', messageKey: 'errors.sessionExpired' };
  if (result.kind === 'rejected')
    return { tone: 'error', messageKey: ASSIGNMENT_REJECTION_KEYS[result.reason] };
  if (reread?.kind === 'loaded') {
    const assignments =
      workforceEntryFor(reread.workforce, intent.membershipId)?.clinicAssignments ?? [];
    const proven =
      intent.kind === 'assign'
        ? assignments.some(
            (entry) => entry.clinic.clinicId.toLowerCase() === intent.clinicId.toLowerCase(),
          )
        : !assignments.some(
            (entry) =>
              entry.veterinarianClinicAssignmentId.toLowerCase() ===
              intent.assignmentId.toLowerCase(),
          );
    if (proven) return { tone: 'info', messageKey: success };
  }
  return { tone: 'error', messageKey: 'staffAssignment.unconfirmed' };
}

// ---------------------------------------------------------------------------
// Confirmations
// ---------------------------------------------------------------------------

export function endResponsibilityConfirmation(
  member: StaffMember,
  grant: StaffResponsibility,
  t: Translate,
): { title: string; message: string } {
  return {
    title: t('staffMember.endConfirmTitle'),
    message: t('staffMember.endConfirmMessage', {
      responsibility: staffResponsibilityLabel(grant, t),
      name: staffMemberName(member, t),
    }),
  };
}
export function endAssignmentConfirmation(
  member: StaffMember,
  assignment: WorkforceClinicAssignment,
  t: Translate,
): { title: string; message: string } {
  return {
    title: t('staffAssignment.endConfirmTitle'),
    message: t('staffAssignment.endConfirmMessage', {
      clinic: assignment.clinic.displayName ?? t('professional.unnamedClinic'),
      name: staffMemberName(member, t),
    }),
  };
}

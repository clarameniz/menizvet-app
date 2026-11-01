import type { Href } from 'expo-router';

import type { StaffMember } from '@/data/organization-staff';
import type {
  OrganizationProfessionalContext,
  ScopedResponsibility,
} from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import type { LocaleCode } from '@/i18n/types';
import { responsibilityLabelKey } from '@/lib/professional-context-display';

/** Advisory entry only. Neither roles nor Entitlements decide Staff visibility. */
export function offersOrganizationStaff(organization: OrganizationProfessionalContext): boolean {
  return organization.capabilities.some(
    ({ capability, scope }) =>
      scope.type === 'ORGANIZATION' &&
      (capability === 'ORGANIZATION_INVITE_MEMBERS' ||
        capability === 'ORGANIZATION_END_MEMBERSHIPS'),
  );
}
export function organizationStaffHref(organizationId: string): Href {
  return {
    pathname: '/professional/organizations/[organizationId]/staff',
    params: { organizationId },
  };
}
export function organizationStaffInviteHref(organizationId: string): Href {
  return {
    pathname: '/professional/organizations/[organizationId]/staff/invite',
    params: { organizationId },
  };
}
type Translate = (key: TranslationKey, options?: Record<string, string | number>) => string;
/**
 * A member's identity as one heading and at most one supporting line, in the
 * SPEC-ORG-009 §7 order: display name, else the originating Invitation
 * address, else "Unnamed member". The Invitation address is administrative
 * Invitation context and must never read as "the member's email"
 * (SPEC-ORG-009 §4, SPEC-ID-006 BR-40): as the heading it carries a context
 * caption; under a display name it is labelled as the Invitation address.
 * Uses only what the Staff read returns — never the Auth email or an id.
 */
export type StaffMemberIdentity = { heading: string; supporting: string | null };
export function staffMemberIdentity(member: StaffMember, t: Translate): StaffMemberIdentity {
  const email = member.invitationRecipientEmail;
  if (member.displayName !== null) {
    return {
      heading: member.displayName,
      supporting: email === null ? null : t('staff.invitedAddress', { email }),
    };
  }
  if (email !== null) return { heading: email, supporting: t('staff.invitationAddressContext') };
  return { heading: t('staff.unnamedMember'), supporting: null };
}

/**
 * The fullest approved identity in one phrase, for the End access accessible
 * label: two members with the same display name stay distinguishable by
 * their Invitation address when the Staff read has one.
 */
export function staffMemberTargetLabel(member: StaffMember, t: Translate): string {
  const name = staffMemberName(member, t);
  return member.displayName !== null && member.invitationRecipientEmail !== null
    ? t('staff.memberWithInvitationAddress', { name, email: member.invitationRecipientEmail })
    : name;
}
/**
 * The member as named in a sentence (End access confirmation): the same
 * SPEC-ORG-009 identity order, with the invitation address used bare. Never
 * the Auth email.
 */
export function staffMemberName(member: StaffMember, t: Translate): string {
  return member.displayName ?? member.invitationRecipientEmail ?? t('staff.unnamedMember');
}
/**
 * SPEC-ORG-004 §10 / SPEC-ORG-009 §7: End access is never offered on the
 * caller's own row or on a row holding an active OWNER responsibility.
 * Advisory only — the backend rejects both regardless.
 */
export function isEndAccessTarget(member: StaffMember): boolean {
  return !member.isSelf && !member.responsibilities.some((role) => role.responsibility === 'OWNER');
}
export function staffResponsibilityLabel(role: ScopedResponsibility, t: Translate): string {
  const label = t(responsibilityLabelKey(role.responsibility));
  return role.scope.type === 'ORGANIZATION'
    ? t('staff.roleInOrganization', { role: label, scopeLabel: t('staff.organizationScope') })
    : t('staff.roleInClinic', {
        role: label,
        scopeLabel: t('staff.clinicScope'),
        clinic: role.scope.clinic.displayName ?? t('professional.unnamedClinic'),
      });
}

const STAFF_ROLE_KEYS: Record<ScopedResponsibility['responsibility'], TranslationKey> = {
  OWNER: 'staffRoles.owner',
  ADMINISTRATOR: 'staffRoles.administrator',
  RECEPTIONIST: 'staffRoles.receptionist',
  VETERINARIAN: 'staffRoles.veterinarian',
};
/** The responsibility named as the task a small clinic recognises ("Recepción"). */
export function staffRoleLabel(
  responsibility: ScopedResponsibility['responsibility'],
  t: Translate,
): string {
  return t(STAFF_ROLE_KEYS[responsibility]);
}
/**
 * Where a responsibility applies, in Clinic terms (SPEC-ORG-005 §3–§4): a
 * Clinic-scoped one names its Clinic; an Organization-scoped Administrator or
 * Receptionist covers every Clinic, including future ones. OWNER and
 * VETERINARIAN are always Organization-scoped and have no Clinic coverage of
 * their own (a Veterinarian practises through Clinic Assignments), so null.
 */
export function staffScopeLabel(role: ScopedResponsibility, t: Translate): string | null {
  if (role.scope.type === 'CLINIC')
    return role.scope.clinic.displayName ?? t('professional.unnamedClinic');
  return role.responsibility === 'ADMINISTRATOR' || role.responsibility === 'RECEPTIONIST'
    ? t('staff.allClinics')
    : null;
}
/** One responsibility as one task-oriented line, e.g. "Recepción · Centro". */
export function staffTaskLabel(role: ScopedResponsibility, t: Translate): string {
  const coverage = staffScopeLabel(role, t);
  const label = staffRoleLabel(role.responsibility, t);
  // Not `scope`: i18n-js reserves that option name.
  return coverage === null ? label : t('staff.taskLine', { role: label, coverage });
}
const BADGE_ORDER = ['OWNER', 'VETERINARIAN', 'RECEPTIONIST', 'ADMINISTRATOR'] as const;
/**
 * The Staff list's compact summary: one badge per responsibility, in the
 * Member detail's order. Administrator and Receptionist add their Clinic
 * coverage as a count, or "all clinics" when an Organization-scoped Grant
 * covers every Clinic. Clinic names and details stay in the Member detail.
 */
export function staffRoleBadges(
  responsibilities: readonly ScopedResponsibility[],
  t: Translate,
): string[] {
  return BADGE_ORDER.flatMap((role) => {
    const held = responsibilities.filter((entry) => entry.responsibility === role);
    if (held.length === 0) return [];
    const label = staffRoleLabel(role, t);
    if (role !== 'ADMINISTRATOR' && role !== 'RECEPTIONIST') return [label];
    const clinics = held.filter((entry) => entry.scope.type === 'CLINIC').length;
    const coverage = held.some((entry) => entry.scope.type === 'ORGANIZATION')
      ? t('staff.coverageAll')
      : t(clinics === 1 ? 'staff.clinicsOne' : 'staff.clinicsOther', { count: clinics });
    return [t('staff.taskLine', { role: label, coverage })];
  });
}
/**
 * The End access confirmation (SPEC-ORG-004 §10): the target's full approved
 * identity and active responsibilities (with Clinic names) so the
 * administrator can verify exactly whom they are about to remove, then the
 * consequences.
 */
export function endAccessConfirmation(
  member: StaffMember,
  organizationDisplayName: string,
  t: Translate,
): { title: string; message: string } {
  const identity = staffMemberIdentity(member, t);
  const target = [
    identity.heading,
    ...(identity.supporting === null ? [] : [identity.supporting]),
    ...member.responsibilities.map((role) => staffResponsibilityLabel(role, t)),
  ].join('\n');
  const names = { name: staffMemberName(member, t), organization: organizationDisplayName };
  return {
    title: t('staff.endAccessConfirmTitle', names),
    message: `${target}\n\n${t('staff.endAccessConfirmMessage', names)}`,
  };
}
/**
 * A compact expiry for a list row: "28 oct" in the current year, "28 oct 2027"
 * otherwise, on the device's calendar like `staffInstantLabel` (the row's
 * accessible name keeps the full date and time).
 */
export function staffShortDateLabel(
  instant: string,
  locale: LocaleCode,
  now: Date = new Date(),
): string {
  const date = new Date(instant);
  return new Intl.DateTimeFormat(locale === 'es' ? 'es-ES' : 'en-GB', {
    day: 'numeric',
    month: 'short',
    ...(date.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' }),
  })
    .format(date)
    .replace(/\.$/, '');
}

export function staffInstantLabel(instant: string, locale: LocaleCode): string {
  return new Intl.DateTimeFormat(locale === 'es' ? 'es-ES' : 'en-GB', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(instant));
}

import type {
  ClinicIdentity,
  OrganizationProfessionalContext,
  OrganizationResponsibility,
  ProfessionalContext,
  ScopedResponsibility,
} from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure presentation helpers for the professional-context landing screen and
 * the Home entry point — kept out of route components so they're unit-testable
 * without component-rendering test infrastructure.
 *
 * Nothing here decides what a User is allowed to do: there is no
 * responsibility-to-capability mapping and no capability/Entitlement check.
 * Responsibilities are only translated to readable labels.
 */

const RESPONSIBILITY_LABEL_KEYS: Record<OrganizationResponsibility, TranslationKey> = {
  OWNER: 'professional.responsibilityOwner',
  ADMINISTRATOR: 'professional.responsibilityAdministrator',
  RECEPTIONIST: 'professional.responsibilityReceptionist',
  VETERINARIAN: 'professional.responsibilityVeterinarian',
};

/** Localized label key for a Responsibility — the raw backend value is never shown. */
export function responsibilityLabelKey(responsibility: OrganizationResponsibility): TranslationKey {
  return RESPONSIBILITY_LABEL_KEYS[responsibility];
}

/** The Clinic's display name, or the caller's localized fallback when it has none (SPEC-ORG-007 BR-4). */
export function clinicDisplayLabel(clinic: ClinicIdentity, unnamedClinicLabel: string): string {
  return clinic.displayName ?? unnamedClinicLabel;
}

/**
 * `null` for an Organization-scoped Responsibility; the Clinic it is limited
 * to otherwise, so the UI can say e.g. "Receptionist · Animalia Getafe".
 */
export function responsibilityClinic(responsibility: ScopedResponsibility): ClinicIdentity | null {
  return responsibility.scope.type === 'CLINIC' ? responsibility.scope.clinic : null;
}

/** Whether Home should offer the professional entry point: one or more current Organizations. */
export function hasProfessionalOrganizations(context: ProfessionalContext): boolean {
  return context.organizations.length > 0;
}

/**
 * The Organization to present: the one the User picked, while it is still
 * part of the latest context, otherwise the first one. Selection is local
 * presentation state only — never an authorization fact.
 */
export function resolveSelectedOrganization(
  organizations: readonly OrganizationProfessionalContext[],
  selectedMembershipId: string | null,
): OrganizationProfessionalContext | null {
  return (
    organizations.find((organization) => organization.membershipId === selectedMembershipId) ??
    organizations[0] ??
    null
  );
}

/**
 * Distinct Clinics of the User's current Veterinarian Clinic Assignments in
 * this Organization, in server order.
 */
export function assignedClinics(organization: OrganizationProfessionalContext): ClinicIdentity[] {
  const seen = new Set<string>();
  const clinics: ClinicIdentity[] = [];
  for (const assignment of organization.clinicAssignments) {
    if (seen.has(assignment.clinic.clinicId)) continue;
    seen.add(assignment.clinic.clinicId);
    clinics.push(assignment.clinic);
  }
  return clinics;
}

import type { ProfessionalClinics } from '@/data/professional-clinics';
import type {
  OrganizationProfessionalContext,
  ProfessionalContext,
} from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import { offersClinicCreation } from '@/lib/clinic-creation';
import { offersOrganizationStaff, staffResponsibilityLabel } from '@/lib/organization-staff';
import { offersOrganizationSubscription } from '@/lib/organization-subscription';
import { clinicsForOrganization } from '@/lib/professional-clinics-display';

/**
 * Pure presentation model for the `/professional` landing: the selected
 * Organization's access card and its Management entries. Nothing here
 * authorizes anything — the backend stays authoritative for every action.
 */

type Translate = (key: TranslationKey, options?: Record<string, string | number>) => string;

/**
 * Lines of the "Your access in this organization" card: one per active
 * Responsibility Grant (role · scope), or the no-Responsibilities text. The
 * Organization name is deliberately absent — the selector already shows it —
 * and so are assigned Clinics, which belong to the actions below.
 */
export function professionalAccessLines(
  organization: OrganizationProfessionalContext,
  t: Translate,
): string[] {
  return organization.responsibilities.length === 0
    ? [t('professional.noResponsibilities')]
    : organization.responsibilities.map((role) => staffResponsibilityLabel(role, t));
}

export type ProfessionalManagementEntry = 'staff' | 'clinics' | 'subscription';

/**
 * Management entries of the selected Organization, in display order. Staff
 * follows the advisory capability gate. Professional Clinics appears when this
 * Organization has some (`null` = not read successfully yet) or when the User
 * may add the first one there (SPEC-CLI-001 §10 BR-17). Subscription follows
 * advisory ORGANIZATION_MANAGE_SUBSCRIPTION (SPEC-SUB-002 §15).
 */
export function professionalManagementEntries(
  organization: OrganizationProfessionalContext,
  clinics: ProfessionalClinics | null,
): ProfessionalManagementEntry[] {
  const entries: ProfessionalManagementEntry[] = [];
  if (offersOrganizationStaff(organization)) entries.push('staff');
  if (
    offersClinicCreation(organization) ||
    (clinics !== null && clinicsForOrganization(clinics, organization.organizationId).length > 0)
  )
    entries.push('clinics');
  if (offersOrganizationSubscription(organization)) entries.push('subscription');
  return entries;
}

/**
 * SPEC-VET-001 §13: prompt the User to complete their own Veterinarian
 * Professional Profile only while they hold a current VETERINARIAN
 * Responsibility in some current Organization and have no Profile yet. Users
 * without that Responsibility are never prompted.
 */
export function needsVeterinarianProfile(context: ProfessionalContext): boolean {
  return (
    !context.hasVeterinarianProfessionalProfile &&
    context.organizations.some((organization) =>
      organization.responsibilities.some((role) => role.responsibility === 'VETERINARIAN'),
    )
  );
}
export const VETERINARIAN_PROFILE_HREF = '/professional/veterinarian-profile' as const;

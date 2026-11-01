import type {
  OrganizationProfessionalClinic,
  ProfessionalClinic,
  ProfessionalClinics,
} from '@/data/professional-clinics';
import type { ProfessionalContext } from '@/data/professional-context';

/**
 * Pure presentation helpers for Professional Clinics (SPEC-ORG-008) — kept out
 * of route components so they're unit-testable without component-rendering
 * test infrastructure.
 *
 * Nothing here decides what a User is allowed to do. In particular, a Clinic
 * whose capabilities are all unknown to this app version stays listed: its
 * inclusion is a backend fact, and the backend re-authorizes every operation.
 */

/** The Clinic's display name, or the caller's localized fallback when it has none. */
export function professionalClinicLabel(
  clinic: ProfessionalClinic,
  unnamedClinicLabel: string,
): string {
  return clinic.clinicDisplayName ?? unnamedClinicLabel;
}

/**
 * The Professional Clinics of one Organization, in backend order. Matching is
 * by Organization id, never by display name: two Organizations — and Clinics
 * in different Organizations — may share a display name. Presentation only;
 * the backend re-authorizes every operation at every Clinic.
 */
export function clinicsForOrganization(
  result: ProfessionalClinics,
  organizationId: string | null,
): ProfessionalClinic[] {
  if (organizationId === null) return [];
  return result.clinics.filter((clinic) => clinic.organizationId === organizationId);
}

/**
 * The selected Organization as the professional context reports it, when the
 * User may add Clinics there (advisory `ORGANIZATION_CREATE_CLINICS`,
 * SPEC-CLI-001 §10 BR-17). `null` when they may not, or when the context
 * could not be read — then no Add action is offered.
 */
export type ClinicCreationContext = { organizationId: string; organizationDisplayName: string };

/** The Clinic's display name, or the localized fallback, for one row of the Organization page. */
export function organizationClinicLabel(
  clinic: OrganizationProfessionalClinic,
  unnamedClinicLabel: string,
): string {
  return clinic.clinicDisplayName ?? unnamedClinicLabel;
}

/**
 * The selected Organization of the Clinics screen (SPEC-ORG-008 BR-26), taken
 * from the authorized professional context — never from an empty page of the
 * Clinics read, which is the same for "no access" and "no Clinic" (BR-21):
 * - `noOrganization` — no selection, or one the context no longer contains
 *   (a direct route, or access that ended): the screen sends the User back to
 *   choose one;
 * - `organization` — its id and name for the heading, and whether Add Clinic
 *   is offered (creation matched by Organization id only).
 */
export type OrganizationClinicsHeading =
  | { kind: 'noOrganization' }
  | {
      kind: 'organization';
      organizationId: string;
      organizationDisplayName: string;
      canCreate: boolean;
    };

export function organizationClinicsHeading(
  context: ProfessionalContext,
  organizationId: string | null,
  creation: ClinicCreationContext | null,
): OrganizationClinicsHeading {
  const organization =
    organizationId === null
      ? undefined
      : context.organizations.find((candidate) => candidate.organizationId === organizationId);
  if (organization === undefined) return { kind: 'noOrganization' };
  return {
    kind: 'organization',
    organizationId: organization.organizationId,
    organizationDisplayName: organization.organizationDisplayName,
    canCreate: creation !== null && creation.organizationId === organization.organizationId,
  };
}

/** Clinic search length (SPEC-ORG-008 BR-20, BR-26). */
export const CLINIC_SEARCH_MAX_LENGTH = 100;

/** Pause after typing before a search is sent (SPEC-ORG-008 BR-26). */
export const CLINIC_SEARCH_DEBOUNCE_MS = 300;

/**
 * The search a typed text submits: outer whitespace never starts a new search
 * (the backend ignores it too); '' is no search.
 */
export function submittedClinicSearch(typed: string): string {
  return typed.trim();
}

/**
 * What the list shows below its header for the current search:
 * - `pending` — its first page has not arrived (loading, or failed before
 *   anything was shown): no row and no empty message;
 * - `rows` — the Clinics read so far;
 * - `noMatches` — the search's first page arrived empty;
 * - `noClinics` — without a search, the first page arrived empty: the
 *   Organization has no Professional Clinic for the User.
 */
export type OrganizationClinicsBody = 'pending' | 'rows' | 'noMatches' | 'noClinics';

export function organizationClinicsBody(
  rows: readonly OrganizationProfessionalClinic[] | null,
  search: string,
): OrganizationClinicsBody {
  if (rows === null) return 'pending';
  if (rows.length > 0) return 'rows';
  return search === '' ? 'noClinics' : 'noMatches';
}

/**
 * Whether the search field is shown: not for an Organization without Clinics
 * (nothing to search), but kept while a search is typed or submitted and once
 * Clinics were listed, so it never disappears under the User's keyboard while
 * a new search loads.
 */
export function offersClinicSearch(input: {
  body: OrganizationClinicsBody;
  search: string;
  typed: string;
  clinicsListed: boolean;
}): boolean {
  if (input.body === 'noClinics') return false;
  return input.search !== '' || input.typed !== '' || input.clinicsListed || input.body === 'rows';
}

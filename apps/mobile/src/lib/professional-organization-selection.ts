/**
 * The Organization the User selected on the professional landing
 * (`/professional`), shared with the Professional Clinics list so that list
 * shows only that Organization's Clinics.
 *
 * Local, in-memory presentation state only: never persisted, never sent to
 * the backend, never an authorization fact. Every operation at a Clinic is
 * still authorized by the backend. Kept outside the route params on purpose:
 * the Clinic screens return to the list with `dismissTo('/professional/clinics')`,
 * which would replace route params, while this selection survives that.
 *
 * The landing re-resolves it against every fresh professional-context read,
 * so a selection that no longer belongs to the User is replaced there; the
 * Clinics list itself also fails safe when the selection is not an
 * Organization of its own context read (see `organizationClinicsHeading`).
 */

export type ProfessionalOrganizationSelection = {
  membershipId: string;
  organizationId: string;
};

let current: ProfessionalOrganizationSelection | null = null;
const listeners = new Set<() => void>();

export function getProfessionalOrganizationSelection(): ProfessionalOrganizationSelection | null {
  return current;
}

/** Replaces the selection; listeners run only when it actually changes. */
export function setProfessionalOrganizationSelection(
  next: ProfessionalOrganizationSelection | null,
): void {
  if (
    current?.membershipId === next?.membershipId &&
    current?.organizationId === next?.organizationId
  ) {
    return;
  }
  current = next === null ? null : { ...next };
  for (const listener of listeners) listener();
}

export function subscribeProfessionalOrganizationSelection(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

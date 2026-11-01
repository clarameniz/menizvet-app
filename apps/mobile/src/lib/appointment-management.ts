import type { ProfessionalContextResult, ProfessionalContext } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import { mapProfessionalContextErrorToKey } from '@/i18n/professional-context-error-messages';

/**
 * The Organization's `APPOINTMENT_MANAGEMENT` Entitlement as the Professional
 * client knows it (SPEC-ORG-007 BR-7, SPEC-APT-012 BR-61). ADVISORY ONLY: it
 * decides what the app OFFERS; Confirm, both proposals and both candidate
 * reads re-check it server-side.
 *
 * - `available` / `unavailable`: the context read reported it for the Clinic's
 *   own Organization.
 * - `unknown`: it could not be verified (the read failed, or the Organization
 *   is missing from it). Never presented as a missing Entitlement.
 */
export type AppointmentManagementStatus =
  { kind: 'available' } | { kind: 'unavailable' } | { kind: 'unknown'; messageKey: TranslationKey };

/**
 * The status for the Organization that operates the Clinic, from a
 * `get_my_professional_context()` result. Related only by Organization id
 * (SPEC-ORG-008 BR-11): another Organization's Entitlement never counts, and
 * no responsibility (Owner, Administrator, …) implies it.
 */
export function appointmentManagementStatusFor(
  result: ProfessionalContextResult<ProfessionalContext>,
  organizationId: string,
): AppointmentManagementStatus {
  if (result.error !== null) {
    return { kind: 'unknown', messageKey: mapProfessionalContextErrorToKey(result.error) };
  }
  const organization = result.data.organizations.find(
    (candidate) => candidate.organizationId === organizationId,
  );
  if (organization === undefined) {
    return { kind: 'unknown', messageKey: 'professional.loadError' };
  }
  return organization.entitlements.APPOINTMENT_MANAGEMENT
    ? { kind: 'available' }
    : { kind: 'unavailable' };
}

/**
 * What the client does with an action that needs `APPOINTMENT_MANAGEMENT`
 * (Confirm, Propose a new time, Propose another time):
 *
 * - `offered`: eligible (capability and the Appointment's own conditions,
 *   decided by its `offers*` rule) and the Entitlement is available;
 * - `unavailable` / `unverified`: eligible, but the Entitlement is known to
 *   be missing or could not be verified — not offered, briefly explained;
 * - `notApplicable`: not eligible anyway; nothing about the Entitlement is
 *   said.
 *
 * Cancel, Complete, No-show and Withdraw never pass through here.
 */
export type ManagedActionGate = 'offered' | 'unavailable' | 'unverified' | 'notApplicable';

export function managedActionGate(
  eligible: boolean,
  status: AppointmentManagementStatus,
): ManagedActionGate {
  if (!eligible) return 'notApplicable';
  if (status.kind === 'available') return 'offered';
  return status.kind === 'unavailable' ? 'unavailable' : 'unverified';
}

/**
 * The single note the detail shows for its Entitlement-dependent actions: the
 * Entitlement is missing (`unavailable`) or unverified, for at least one
 * action that would otherwise be offered; `null` when nothing is held back.
 */
export function managedActionsNotice(
  gates: readonly ManagedActionGate[],
): 'unavailable' | 'unverified' | null {
  if (gates.includes('unavailable')) return 'unavailable';
  if (gates.includes('unverified')) return 'unverified';
  return null;
}

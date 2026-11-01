import { uuid } from 'expo-modules-core';

import type { ClinicCreationResult } from '@/data/clinic-creation';
import type {
  OrganizationProfessionalContext,
  ProfessionalContext,
} from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import type { ClinicCreationContext } from '@/lib/professional-clinics-display';

/**
 * Add Clinic presentation and creation intents (SPEC-CLI-001 §10 BR-17,
 * BR-18). Nothing here authorizes anything: the backend decides every
 * creation.
 */

/** Advisory only: the Organization-scoped ORGANIZATION_CREATE_CLINICS capability. */
export function offersClinicCreation(organization: OrganizationProfessionalContext): boolean {
  return organization.capabilities.some(
    ({ capability, scope }) =>
      capability === 'ORGANIZATION_CREATE_CLINICS' && scope.type === 'ORGANIZATION',
  );
}

/**
 * The selected Organization's creation context, matched by Organization id
 * (never by name). `null` without the advisory capability there, without a
 * selection, or when the professional context could not be read.
 */
export function clinicCreationContext(
  context: ProfessionalContext | null,
  organizationId: string | null,
): ClinicCreationContext | null {
  if (context === null || organizationId === null) return null;
  const organization = context.organizations.find(
    (candidate) => candidate.organizationId === organizationId,
  );
  return organization !== undefined && offersClinicCreation(organization)
    ? { organizationId, organizationDisplayName: organization.organizationDisplayName }
    : null;
}

/** One creation intent: the Organization it targets and its one creation key. */
export type ClinicCreationIntent = { organizationId: string; key: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A new intent with a fresh key from the native UUID v4 generator of
 * expo-modules-core (already part of the app; no new dependency). `null` when
 * no well-formed key can be produced — nothing is then sent.
 */
export function newClinicCreationIntent(
  organizationId: string,
  generateKey: () => string = uuid.v4,
): ClinicCreationIntent | null {
  try {
    const key = generateKey();
    return UUID.test(key) ? { organizationId, key } : null;
  } catch {
    return null;
  }
}

/**
 * Unresolved intents by Organization id: recorded before the request is sent
 * and kept until a definite answer arrives (in flight, or uncertain after a
 * lost response). In memory for the app session only — never persisted, never
 * sent anywhere but the same retry — so a screen that is left and re-entered
 * finishes the same intent with the same key, and no new key is created for
 * that Organization while one is unresolved.
 */
const unresolved = new Map<string, ClinicCreationIntent>();

export function unresolvedClinicCreation(organizationId: string): ClinicCreationIntent | null {
  return unresolved.get(organizationId) ?? null;
}

export function rememberClinicCreation(intent: ClinicCreationIntent): void {
  unresolved.set(intent.organizationId, { ...intent });
}

/** Called once the intent has a definite answer. */
export function forgetClinicCreation(organizationId: string): void {
  unresolved.delete(organizationId);
}

/** What the screen does with one answer to one intent. */
export type ClinicCreationStep =
  | { kind: 'open'; clinicId: string }
  | { kind: 'uncertain' }
  | { kind: 'failed'; messageKey: TranslationKey };

export function clinicCreationStep(result: ClinicCreationResult): ClinicCreationStep {
  switch (result.kind) {
    case 'created':
      return { kind: 'open', clinicId: result.clinicId };
    case 'uncertain':
      return { kind: 'uncertain' };
    case 'accessDenied':
      return { kind: 'failed', messageKey: 'clinicCreation.notAllowed' };
    case 'authenticationRequired':
      return { kind: 'failed', messageKey: 'errors.sessionExpired' };
    case 'rejected':
      return { kind: 'failed', messageKey: 'clinicCreation.failed' };
  }
}

import { supabase } from '@/lib/supabase';

/**
 * Mirrors the deployed SPEC-ORG-007 read `public.get_my_professional_context()`
 * (supabase/migrations/20261001120000_professional_context_read.sql),
 * verified directly against that SQL. Granted to authenticated; takes no
 * arguments and is self-scoped server-side via current_domain_user_id(), so
 * this module never accepts a User id. Returns one jsonb object:
 *
 *   { has_veterinarian_professional_profile: boolean,
 *     organizations: [ { membership_id, organization_id,
 *                        organization_display_name,
 *                        responsibilities: [{ responsibility, scope_type, clinic }],
 *                        capabilities: [{ capability, scope_type, clinic }],
 *                        clinic_assignments: [{ veterinarian_clinic_assignment_id, clinic }],
 *                        entitlements: { APPOINTMENT_MANAGEMENT, PROFESSIONAL_SCHEDULING,
 *                                        CLINICAL_CARE, CLINICAL_DOCUMENTATION } } ] }
 *
 * where `clinic` is `null` for ORGANIZATION scope and
 * `{ clinic_id, clinic_display_name: text | null }` otherwise (SPEC-ORG-007
 * BR-4: an unnamed Clinic is still identified, never omitted).
 *
 * An unauthenticated caller, or one with no coherent domain User, gets
 * SQLSTATE 28000; that is normalized here to `PROFESSIONAL_CONTEXT_AUTH_REQUIRED`
 * (keyed on the SQLSTATE, not the message wording) so the i18n mapper can
 * resolve it to the shared session-expired copy.
 *
 * ADVISORY ONLY (SPEC-ORG-007 BR-6/BR-9, ADR-010): responsibilities,
 * effective capabilities, and Entitlement availability exist solely to decide
 * what to PRESENT. They are never an authorization source on the client —
 * every professional operation re-evaluates Membership, responsibility,
 * Clinic Assignment, Medical Access, and Entitlement server-side. Do not
 * persist them, do not derive capabilities from responsibilities here (the
 * server already did, BR-5), and do not merge a capability with an
 * Entitlement into a single "can do" flag (BR-7).
 *
 * The payload has no compile-time guarantee from supabase-js, so it is
 * validated by a pure parser before being trusted (same approach as
 * data/clinics.ts's Discovery envelopes). Responsibilities, scope types,
 * Clinic identity, and the four Entitlement identifiers are strict closed
 * unions: an unrecognized value rejects the payload as a whole.
 *
 * Capability IDENTIFIERS are the one forward-compatible exception: the
 * backend catalog (`professional_capability_catalog()`) may grow before an
 * older app is updated. A structurally valid capability entry whose
 * identifier this build doesn't know is neither a permission nor rendered —
 * it is kept only as `unknownCapabilities` metadata on its Organization, and
 * never makes the whole context fail. A structurally malformed capability
 * entry (non-object, non-string identifier, bad scope/Clinic) still rejects
 * the payload.
 *
 * Every exported async function settles into `{data, error}` and never
 * rejects (same network-rejection guard as data/clinics.ts).
 */
export type ProfessionalContextResult<T> = { data: T; error: null } | { data: null; error: string };

/** Normalized `error` for SQLSTATE 28000 — see the module doc comment. */
export const PROFESSIONAL_CONTEXT_AUTH_REQUIRED = 'PROFESSIONAL_CONTEXT_AUTH_REQUIRED';

/** Normalized `error` for a payload that fails validation. */
export const PROFESSIONAL_CONTEXT_MALFORMED = 'PROFESSIONAL_CONTEXT_MALFORMED';

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/** SPEC-ORG-005 §2 — public.organization_responsibility_grants CHECK constraint. */
export const ORGANIZATION_RESPONSIBILITIES = [
  'OWNER',
  'ADMINISTRATOR',
  'RECEPTIONIST',
  'VETERINARIAN',
] as const;
export type OrganizationResponsibility = (typeof ORGANIZATION_RESPONSIBILITIES)[number];

/** SPEC-ORG-005 §5 — mirrors `professional_capability_catalog()`. Identifiers only; never rendered. */
export const PROFESSIONAL_CAPABILITIES = [
  'ORGANIZATION_INVITE_MEMBERS',
  'ORGANIZATION_REVOKE_INVITATIONS',
  'ORGANIZATION_END_MEMBERSHIPS',
  'ORGANIZATION_GRANT_RESPONSIBILITIES',
  'ORGANIZATION_CREATE_CLINICS',
  'ORGANIZATION_MANAGE_SUBSCRIPTION',
  'CLINIC_MANAGE_LOCATION',
  'CLINIC_MANAGE_PUBLICATION',
  'CLINIC_MANAGE_PUBLIC_PROFILE',
  'CLINIC_MANAGE_SERVICES',
  'CLINIC_MANAGE_OPENING_HOURS',
  'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
  'APPOINTMENT_VIEW_SCHEDULE',
  'APPOINTMENT_CONFIRM',
  'APPOINTMENT_CANCEL',
  'APPOINTMENT_RESCHEDULE',
  'APPOINTMENT_ASSIGN_VETERINARIAN',
  'APPOINTMENT_COMPLETE',
  'APPOINTMENT_MARK_NO_SHOW',
  'APPOINTMENT_MANAGE_AVAILABILITY',
  'CLINICAL_CARE',
  'CLINICAL_DOCUMENTATION',
] as const;
export type ProfessionalCapability = (typeof PROFESSIONAL_CAPABILITIES)[number];

/** SPEC-ORG-007 BR-7 — the Phase 1 normal professional Entitlements. Identifiers only; never rendered. */
export const PROFESSIONAL_ENTITLEMENTS = [
  'APPOINTMENT_MANAGEMENT',
  'PROFESSIONAL_SCHEDULING',
  'CLINICAL_CARE',
  'CLINICAL_DOCUMENTATION',
] as const;
export type ProfessionalEntitlement = (typeof PROFESSIONAL_ENTITLEMENTS)[number];

/** SPEC-ORG-007 BR-4 minimum Clinic display identity. */
export type ClinicIdentity = {
  clinicId: string;
  /** `null` when the Clinic has no display name yet (e.g. not prepared for publication). */
  displayName: string | null;
};

/** ORGANIZATION scope never carries a Clinic; CLINIC scope always does. */
export type ProfessionalScope =
  { type: 'ORGANIZATION' } | { type: 'CLINIC'; clinic: ClinicIdentity };

export type ScopedResponsibility = {
  responsibility: OrganizationResponsibility;
  scope: ProfessionalScope;
};

/** Advisory presentation context only — see the module doc comment. */
export type ScopedCapability = {
  capability: ProfessionalCapability;
  scope: ProfessionalScope;
};

export type VeterinarianClinicAssignment = {
  veterinarianClinicAssignmentId: string;
  clinic: ClinicIdentity;
};

/** Advisory presentation context only — reported independently of capabilities (BR-7). */
export type EntitlementAvailability = Record<ProfessionalEntitlement, boolean>;

export type OrganizationProfessionalContext = {
  membershipId: string;
  organizationId: string;
  organizationDisplayName: string;
  responsibilities: ScopedResponsibility[];
  /** Known catalog capabilities only — the sole capability input for presentation. */
  capabilities: ScopedCapability[];
  /**
   * Distinct capability identifiers this build doesn't recognize, in first-seen
   * server order. Diagnostic metadata only: never a permission, never rendered.
   */
  unknownCapabilities: string[];
  clinicAssignments: VeterinarianClinicAssignment[];
  entitlements: EntitlementAvailability;
};

export type ProfessionalContext = {
  hasVeterinarianProfessionalProfile: boolean;
  /** Empty is a normal, non-error result (SPEC-ORG-007 BR-8). */
  organizations: OrganizationProfessionalContext[];
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isOneOf<T extends string>(values: readonly T[], value: unknown): value is T {
  return typeof value === 'string' && (values as readonly string[]).includes(value);
}

/** Parses every element or rejects the whole array — never a partial list. */
function parseArray<T>(raw: unknown, parseItem: (item: unknown) => T | null): T[] | null {
  if (!Array.isArray(raw)) return null;
  const parsed: T[] = [];
  for (const item of raw) {
    const value = parseItem(item);
    if (value === null) return null;
    parsed.push(value);
  }
  return parsed;
}

function parseClinicIdentity(raw: unknown): ClinicIdentity | null {
  if (!isRecord(raw)) return null;
  const { clinic_id, clinic_display_name } = raw;
  if (typeof clinic_id !== 'string' || clinic_id.length === 0) return null;
  if (clinic_display_name !== null && typeof clinic_display_name !== 'string') return null;
  return { clinicId: clinic_id, displayName: clinic_display_name };
}

function parseScope(scopeType: unknown, clinic: unknown): ProfessionalScope | null {
  if (scopeType === 'ORGANIZATION') {
    return clinic === null ? { type: 'ORGANIZATION' } : null;
  }
  if (scopeType === 'CLINIC') {
    const identity = parseClinicIdentity(clinic);
    return identity === null ? null : { type: 'CLINIC', clinic: identity };
  }
  return null;
}

function parseResponsibility(raw: unknown): ScopedResponsibility | null {
  if (!isRecord(raw)) return null;
  const { responsibility, scope_type, clinic } = raw;
  if (!isOneOf(ORGANIZATION_RESPONSIBILITIES, responsibility)) return null;
  const scope = parseScope(scope_type, clinic);
  return scope === null ? null : { responsibility, scope };
}

type ParsedCapability =
  { kind: 'known'; value: ScopedCapability } | { kind: 'unknown'; identifier: string };

/** `null` only for a structurally malformed entry; an unrecognized identifier is `unknown`. */
function parseCapability(raw: unknown): ParsedCapability | null {
  if (!isRecord(raw)) return null;
  const { capability, scope_type, clinic } = raw;
  if (typeof capability !== 'string' || capability.length === 0) return null;
  const scope = parseScope(scope_type, clinic);
  if (scope === null) return null;
  return isOneOf(PROFESSIONAL_CAPABILITIES, capability)
    ? { kind: 'known', value: { capability, scope } }
    : { kind: 'unknown', identifier: capability };
}

function splitCapabilities(
  parsed: ParsedCapability[],
): Pick<OrganizationProfessionalContext, 'capabilities' | 'unknownCapabilities'> {
  const capabilities: ScopedCapability[] = [];
  const unknownCapabilities: string[] = [];
  for (const entry of parsed) {
    if (entry.kind === 'known') {
      capabilities.push(entry.value);
    } else if (!unknownCapabilities.includes(entry.identifier)) {
      unknownCapabilities.push(entry.identifier);
    }
  }
  return { capabilities, unknownCapabilities };
}

function parseClinicAssignment(raw: unknown): VeterinarianClinicAssignment | null {
  if (!isRecord(raw)) return null;
  const { veterinarian_clinic_assignment_id, clinic } = raw;
  if (typeof veterinarian_clinic_assignment_id !== 'string') return null;
  const identity = parseClinicIdentity(clinic);
  return identity === null
    ? null
    : { veterinarianClinicAssignmentId: veterinarian_clinic_assignment_id, clinic: identity };
}

function parseEntitlements(raw: unknown): EntitlementAvailability | null {
  if (!isRecord(raw)) return null;
  const { APPOINTMENT_MANAGEMENT, PROFESSIONAL_SCHEDULING, CLINICAL_CARE, CLINICAL_DOCUMENTATION } =
    raw;
  if (
    typeof APPOINTMENT_MANAGEMENT !== 'boolean' ||
    typeof PROFESSIONAL_SCHEDULING !== 'boolean' ||
    typeof CLINICAL_CARE !== 'boolean' ||
    typeof CLINICAL_DOCUMENTATION !== 'boolean'
  ) {
    return null;
  }
  return { APPOINTMENT_MANAGEMENT, PROFESSIONAL_SCHEDULING, CLINICAL_CARE, CLINICAL_DOCUMENTATION };
}

function parseOrganization(raw: unknown): OrganizationProfessionalContext | null {
  if (!isRecord(raw)) return null;
  const { membership_id, organization_id, organization_display_name } = raw;
  if (typeof membership_id !== 'string' || membership_id.length === 0) return null;
  if (typeof organization_id !== 'string' || organization_id.length === 0) return null;
  if (typeof organization_display_name !== 'string') return null;

  const responsibilities = parseArray(raw.responsibilities, parseResponsibility);
  const parsedCapabilities = parseArray(raw.capabilities, parseCapability);
  const clinicAssignments = parseArray(raw.clinic_assignments, parseClinicAssignment);
  const entitlements = parseEntitlements(raw.entitlements);
  if (
    responsibilities === null ||
    parsedCapabilities === null ||
    clinicAssignments === null ||
    entitlements === null
  ) {
    return null;
  }

  return {
    membershipId: membership_id,
    organizationId: organization_id,
    organizationDisplayName: organization_display_name,
    responsibilities,
    ...splitCapabilities(parsedCapabilities),
    clinicAssignments,
    entitlements,
  };
}

/**
 * Exported for unit testing: validates and reshapes the RPC's jsonb result.
 * Returns `null` for any structural or controlled-value mismatch.
 */
export function parseProfessionalContext(raw: unknown): ProfessionalContext | null {
  if (!isRecord(raw)) return null;
  const { has_veterinarian_professional_profile } = raw;
  if (typeof has_veterinarian_professional_profile !== 'boolean') return null;

  const organizations = parseArray(raw.organizations, parseOrganization);
  if (organizations === null) return null;

  return {
    hasVeterinarianProfessionalProfile: has_veterinarian_professional_profile,
    organizations,
  };
}

// ---------------------------------------------------------------------------
// RPC
// ---------------------------------------------------------------------------

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/** Reads the acting User's own current professional context (SPEC-ORG-007). */
export async function getMyProfessionalContext(): Promise<
  ProfessionalContextResult<ProfessionalContext>
> {
  try {
    const { data, error } = await supabase.rpc('get_my_professional_context');

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      return { data: null, error: error.message };
    }

    const context = parseProfessionalContext(data);
    if (context === null) {
      return { data: null, error: PROFESSIONAL_CONTEXT_MALFORMED };
    }

    return { data: context, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

import {
  PROFESSIONAL_CAPABILITIES,
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_CONTEXT_MALFORMED,
  type ProfessionalCapability,
} from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the deployed SPEC-ORG-008 read `public.get_my_professional_clinics()`
 * (supabase/migrations/20261001150000_professional_clinics_read.sql). Granted
 * to authenticated; takes no arguments and is self-scoped server-side, so this
 * module never accepts a User, Organization, or Clinic id. Returns:
 *
 *   { clinics: [ { clinic_id, clinic_display_name: text | null,
 *                  organization_id, organization_display_name,
 *                  capabilities: [text, ...] } ] }
 *
 * in backend order (Organization name, Organization id, Clinic name nulls
 * last, Clinic id — BR-15), one entry per Clinic (BR-8), each with a
 * non-empty capability list (BR-10). An empty list is a normal result (BR-12).
 *
 * These are the Clinics the User currently has operational professional
 * context for (SPEC-ORG-008 BR-6) — the source for professional workflow
 * navigation. They are distinct from the Clinic Assignments reported by
 * SPEC-ORG-007, which remain relationship/context facts.
 *
 * ADVISORY ONLY (BR-13): capabilities decide what to PRESENT, never what is
 * allowed. Every operation at a listed Clinic re-authorizes server-side.
 *
 * Parsing follows data/professional-context.ts: the shape, ids, display
 * names, and one-entry-per-Clinic / non-empty-capabilities invariants are
 * strict (any violation rejects the whole payload); capability IDENTIFIERS are
 * forward-compatible — a non-empty identifier this build doesn't know is kept
 * only as `unknownCapabilities` metadata, never as a permission, never
 * rendered, and never makes the Clinic or the payload fail.
 *
 * SQLSTATE 28000 is normalized to PROFESSIONAL_CONTEXT_AUTH_REQUIRED, and a
 * malformed payload to PROFESSIONAL_CONTEXT_MALFORMED — the same values
 * getMyProfessionalContext() uses, so session-expired handling is shared.
 */
export type ProfessionalClinicsResult<T> = { data: T; error: null } | { data: null; error: string };

export type ProfessionalClinic = {
  clinicId: string;
  /** `null` when the Clinic has no display name yet (SPEC-ORG-008 BR-9). */
  clinicDisplayName: string | null;
  organizationId: string;
  organizationDisplayName: string;
  /** Known effective Clinic-context capabilities, distinct, in backend order. Advisory only. */
  capabilities: ProfessionalCapability[];
  /**
   * Distinct identifiers this build doesn't recognize, in first-seen backend
   * order. Diagnostic metadata only: never a permission, never rendered.
   */
  unknownCapabilities: string[];
};

export type ProfessionalClinics = {
  /** Backend order; empty is a normal, non-error result. */
  clinics: ProfessionalClinic[];
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isKnownCapability(value: string): value is ProfessionalCapability {
  return (PROFESSIONAL_CAPABILITIES as readonly string[]).includes(value);
}

function parseCapabilities(
  raw: unknown,
): Pick<ProfessionalClinic, 'capabilities' | 'unknownCapabilities'> | null {
  // A returned Clinic always has at least one capability (SPEC-ORG-008 BR-10).
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const capabilities: ProfessionalCapability[] = [];
  const unknownCapabilities: string[] = [];
  for (const item of raw) {
    if (typeof item !== 'string' || item.length === 0) return null;
    if (isKnownCapability(item)) {
      if (!capabilities.includes(item)) capabilities.push(item);
    } else if (!unknownCapabilities.includes(item)) {
      unknownCapabilities.push(item);
    }
  }
  return { capabilities, unknownCapabilities };
}

function parseClinic(raw: unknown): ProfessionalClinic | null {
  if (!isRecord(raw)) return null;
  const { clinic_id, clinic_display_name, organization_id, organization_display_name } = raw;
  if (typeof clinic_id !== 'string' || clinic_id.length === 0) return null;
  if (clinic_display_name !== null && typeof clinic_display_name !== 'string') return null;
  if (typeof organization_id !== 'string' || organization_id.length === 0) return null;
  if (typeof organization_display_name !== 'string') return null;

  const parsedCapabilities = parseCapabilities(raw.capabilities);
  if (parsedCapabilities === null) return null;

  return {
    clinicId: clinic_id,
    clinicDisplayName: clinic_display_name,
    organizationId: organization_id,
    organizationDisplayName: organization_display_name,
    ...parsedCapabilities,
  };
}

/**
 * Exported for unit testing: validates and reshapes the RPC's jsonb result.
 * Returns `null` for any structural violation, including a Clinic returned
 * twice (SPEC-ORG-008 BR-8).
 */
export function parseProfessionalClinics(raw: unknown): ProfessionalClinics | null {
  if (!isRecord(raw) || !Array.isArray(raw.clinics)) return null;

  const clinics: ProfessionalClinic[] = [];
  const seenClinicIds = new Set<string>();
  for (const item of raw.clinics) {
    const clinic = parseClinic(item);
    if (clinic === null || seenClinicIds.has(clinic.clinicId)) return null;
    seenClinicIds.add(clinic.clinicId);
    clinics.push(clinic);
  }

  return { clinics };
}

// ---------------------------------------------------------------------------
// RPC
// ---------------------------------------------------------------------------

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

// ---------------------------------------------------------------------------
// Organization page (SPEC-ORG-008 §11)
// ---------------------------------------------------------------------------

/**
 * One row of `get_my_organization_professional_clinics` (BR-19): the Clinic id
 * and its display name, `null` when it has none. No capability or Organization
 * data — the Clinic screen re-reads and re-authorizes.
 */
export type OrganizationProfessionalClinic = {
  clinicId: string;
  clinicDisplayName: string | null;
};

/** The complete key of a row (BR-23), exactly as the backend returned it. */
export type OrganizationClinicsCursor = { displayName: string | null; clinicId: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Exported for unit testing: one page — an array of strict two-column rows,
 * no Clinic twice. Anything else is `null`.
 */
export function parseOrganizationProfessionalClinicsPage(
  raw: unknown,
): OrganizationProfessionalClinic[] | null {
  if (!Array.isArray(raw)) return null;
  const rows: OrganizationProfessionalClinic[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    if (!isRecord(item)) return null;
    const { clinic_id, clinic_display_name } = item;
    if (typeof clinic_id !== 'string' || !UUID.test(clinic_id)) return null;
    if (clinic_display_name !== null && typeof clinic_display_name !== 'string') return null;
    if (seen.has(clinic_id.toLowerCase())) return null;
    seen.add(clinic_id.toLowerCase());
    rows.push({ clinicId: clinic_id, clinicDisplayName: clinic_display_name });
  }
  return rows;
}

export function organizationClinicsCursorOf(
  row: OrganizationProfessionalClinic,
): OrganizationClinicsCursor {
  return { displayName: row.clinicDisplayName, clinicId: row.clinicId };
}

/**
 * One page of the acting User's Professional Clinics of one Organization,
 * optionally narrowed by a name search (SPEC-ORG-008 BR-19–BR-23); `after`
 * null reads the first page. The search is sent as given (the backend
 * normalizes it); `null` means no search. Self-scoped server-side: an
 * Organization without access is an empty page, never an error (BR-21).
 */
export async function getMyOrganizationProfessionalClinicsPage(
  organizationId: string,
  search: string | null,
  after: OrganizationClinicsCursor | null,
  limit: number,
): Promise<ProfessionalClinicsResult<OrganizationProfessionalClinic[]>> {
  // A malformed id can name no Organization of the User.
  if (!UUID.test(organizationId)) return { data: [], error: null };
  try {
    const { data, error } = await supabase.rpc('get_my_organization_professional_clinics', {
      p_organization_id: organizationId,
      p_search: search,
      p_after_display_name: after?.displayName ?? null,
      p_after_clinic_id: after?.clinicId ?? null,
      p_limit: limit,
    });

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      return { data: null, error: error.message };
    }

    const rows = parseOrganizationProfessionalClinicsPage(data);
    if (rows === null) {
      return { data: null, error: PROFESSIONAL_CONTEXT_MALFORMED };
    }

    return { data: rows, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/** Reads the acting User's own current Professional Clinics (SPEC-ORG-008). */
export async function getMyProfessionalClinics(): Promise<
  ProfessionalClinicsResult<ProfessionalClinics>
> {
  try {
    const { data, error } = await supabase.rpc('get_my_professional_clinics');

    if (error) {
      if (error.code === '28000') {
        return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      }
      return { data: null, error: error.message };
    }

    const clinics = parseProfessionalClinics(data);
    if (clinics === null) {
      return { data: null, error: PROFESSIONAL_CONTEXT_MALFORMED };
    }

    return { data: clinics, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

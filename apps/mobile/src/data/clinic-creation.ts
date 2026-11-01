import { supabase } from '@/lib/supabase';

/**
 * Client for `public.create_clinic(p_organization_id uuid, p_idempotency_key
 * uuid) returns jsonb` (SPEC-CLI-001 §10 BR-12–BR-14,
 * supabase/migrations/20261030090000_idempotent_clinic_creation.sql).
 *
 * The client sends only the Organization and the creation key of one
 * creation intent; the backend derives the acting User and authorizes the
 * call. The same Organization and key always return the same Clinic, so an
 * uncertain answer is resolved by calling again with the SAME key — never by
 * comparing Clinic lists and never with a new key.
 *
 * Settles into a result and never rejects.
 */
export type ClinicCreationOutcome = 'CREATED' | 'ALREADY_CREATED';
export type ClinicCreationResult =
  | { kind: 'created'; clinicId: string; outcome: ClinicCreationOutcome }
  /** 42501: no ORGANIZATION_CREATE_CLINICS there (or an unknown Organization). Nothing was created. */
  | { kind: 'accessDenied' }
  /** 28000: no authenticated subject or coherent domain User. Nothing was created. */
  | { kind: 'authenticationRequired' }
  /** 22023: the request itself was invalid. Nothing was created. */
  | { kind: 'rejected' }
  /** No definite answer (network, 5xx, malformed success): retry with the same key. */
  | { kind: 'uncertain' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isId = (raw: unknown): raw is string => typeof raw === 'string' && UUID.test(raw);
const OUTCOMES: readonly ClinicCreationOutcome[] = ['CREATED', 'ALREADY_CREATED'];

function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}

/** Exported for unit testing: an answer is success only for this Organization. */
export function parseClinicCreation(raw: unknown, organizationId: string): ClinicCreationResult {
  if (
    !isRecord(raw) ||
    !isId(raw.clinic_id) ||
    !isId(raw.organization_id) ||
    raw.organization_id.toLowerCase() !== organizationId.toLowerCase()
  )
    return { kind: 'uncertain' };
  const outcome = OUTCOMES.find((candidate) => candidate === raw.outcome);
  return outcome === undefined
    ? { kind: 'uncertain' }
    : { kind: 'created', clinicId: raw.clinic_id, outcome };
}

export async function createClinic(
  organizationId: string,
  idempotencyKey: string,
): Promise<ClinicCreationResult> {
  // Never sent: the backend would reject it, and nothing must be guessed.
  if (!isId(organizationId) || !isId(idempotencyKey)) return { kind: 'rejected' };
  try {
    const { data, error } = await supabase.rpc('create_clinic', {
      p_organization_id: organizationId,
      p_idempotency_key: idempotencyKey,
    });
    if (error) {
      if (error.code === '42501') return { kind: 'accessDenied' };
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '22023') return { kind: 'rejected' };
      return { kind: 'uncertain' };
    }
    return parseClinicCreation(data, organizationId);
  } catch {
    return { kind: 'uncertain' };
  }
}

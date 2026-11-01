import { supabase } from '@/lib/supabase';

/**
 * SPEC-VET-001 §13: the acting User creates their own Veterinarian
 * Professional Profile through
 * `create_my_veterinarian_professional_profile(p_registration_identifier,
 * p_issuing_context)`. No User, Membership, Organization or Clinic is ever
 * sent. An exact repeat (including a lost response) returns ALREADY_EXISTS
 * with the same ids; a different request for an existing Profile is
 * PROFILE_CREDENTIAL_MISMATCH and never overwrites it. Anything without a
 * trustworthy answer is `uncertain`: the caller re-reads the professional
 * context instead of retrying. Never rejects.
 */
export type VeterinarianProfileInput = { registrationIdentifier: string; issuingContext: string };

export const VETERINARIAN_PROFILE_REJECTIONS = [
  'ACCOUNT_VERIFICATION_REQUIRED',
  'REGISTRATION_IDENTIFIER_REQUIRED',
  'ISSUING_CONTEXT_REQUIRED',
  'PROFILE_CREDENTIAL_MISMATCH',
] as const;
export type VeterinarianProfileRejection = (typeof VETERINARIAN_PROFILE_REJECTIONS)[number];

export type VeterinarianProfileResult =
  | { kind: 'outcome'; outcome: 'CREATED' | 'ALREADY_EXISTS' }
  | { kind: 'rejected'; reason: VeterinarianProfileRejection }
  | { kind: 'authenticationRequired' }
  | { kind: 'uncertain' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isId = (raw: unknown): raw is string => typeof raw === 'string' && UUID.test(raw);

export async function createMyVeterinarianProfessionalProfile(
  input: VeterinarianProfileInput,
): Promise<VeterinarianProfileResult> {
  try {
    const { data, error } = await supabase.rpc('create_my_veterinarian_professional_profile', {
      // Sent as typed: the backend's trim normalization is authoritative.
      p_registration_identifier: input.registrationIdentifier,
      p_issuing_context: input.issuingContext,
    });
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      const reason = VETERINARIAN_PROFILE_REJECTIONS.find((candidate) => candidate === error.hint);
      if (reason !== undefined && ['42501', '22023', '23514'].includes(error.code ?? ''))
        return { kind: 'rejected', reason };
      return { kind: 'uncertain' };
    }
    const record =
      typeof data === 'object' && data !== null && !Array.isArray(data)
        ? (data as Record<string, unknown>)
        : null;
    const outcome =
      record?.outcome === 'CREATED' || record?.outcome === 'ALREADY_EXISTS' ? record.outcome : null;
    if (
      outcome === null ||
      !isId(record?.professional_profile_id) ||
      !isId(record?.professional_credential_id)
    )
      return { kind: 'uncertain' };
    return { kind: 'outcome', outcome };
  } catch {
    return { kind: 'uncertain' };
  }
}

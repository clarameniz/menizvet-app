import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ProfessionalContext,
  type ProfessionalContextResult,
} from '@/data/professional-context';
import type {
  VeterinarianProfileInput,
  VeterinarianProfileRejection,
  VeterinarianProfileResult,
} from '@/data/veterinarian-profile';
import type { TranslationKey } from '@/i18n/i18n';
import { needsVeterinarianProfile } from '@/lib/professional-home';

/** Pure model of the self-service Profile screen (SPEC-VET-001 §13). */

export type VeterinarianProfileAvailability = 'form' | 'completed' | 'notOffered';
/** The form is offered exactly while the Home prompt would be shown. */
export function veterinarianProfileAvailability(
  context: ProfessionalContext,
): VeterinarianProfileAvailability {
  if (context.hasVeterinarianProfessionalProfile) return 'completed';
  return needsVeterinarianProfile(context) ? 'form' : 'notOffered';
}

export type VeterinarianProfileDraft = VeterinarianProfileInput;
export const EMPTY_VETERINARIAN_PROFILE_DRAFT: VeterinarianProfileDraft = {
  registrationIdentifier: '',
  issuingContext: '',
};
// The backend's btrim set; used only to decide completeness and what to review.
const trim = (value: string) => value.replace(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g, '');
export function canReviewVeterinarianProfile(draft: VeterinarianProfileDraft): boolean {
  return trim(draft.registrationIdentifier) !== '' && trim(draft.issuingContext) !== '';
}
/** The values exactly as the backend will store them (shown in the review step). */
export function reviewedVeterinarianProfile(
  draft: VeterinarianProfileDraft,
): VeterinarianProfileDraft {
  return {
    registrationIdentifier: trim(draft.registrationIdentifier),
    issuingContext: trim(draft.issuingContext),
  };
}

const REJECTION_KEYS: Record<VeterinarianProfileRejection, TranslationKey> = {
  ACCOUNT_VERIFICATION_REQUIRED: 'veterinarianProfile.verificationRequired',
  REGISTRATION_IDENTIFIER_REQUIRED: 'veterinarianProfile.identifierRequired',
  ISSUING_CONTEXT_REQUIRED: 'veterinarianProfile.contextRequired',
  PROFILE_CREDENTIAL_MISMATCH: 'veterinarianProfile.mismatch',
};

/**
 * After a submission and the authoritative re-read of the professional
 * context: CREATED and ALREADY_EXISTS are the same success; a lost response
 * is success only when the re-read shows a Profile. Never a blind retry.
 */
export function veterinarianProfileOutcome(
  result: VeterinarianProfileResult,
  reread: ProfessionalContextResult<ProfessionalContext> | null,
): 'created' | TranslationKey {
  if (result.kind === 'outcome') return 'created';
  if (result.kind === 'authenticationRequired') return 'errors.sessionExpired';
  if (result.kind === 'rejected') return REJECTION_KEYS[result.reason];
  if (reread?.error === PROFESSIONAL_CONTEXT_AUTH_REQUIRED) return 'errors.sessionExpired';
  if (reread !== null && reread.error === null && reread.data.hasVeterinarianProfessionalProfile)
    return 'created';
  return 'veterinarianProfile.unconfirmed';
}

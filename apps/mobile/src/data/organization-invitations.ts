import type { OrganizationResponsibility, ScopedResponsibility } from '@/data/professional-context';
import {
  isInvitationId,
  isInvitationSecret,
  type OrganizationInvitationCredential,
} from '@/lib/organization-invitation-link';
import { supabase } from '@/lib/supabase';

/**
 * SPEC-ORG-003 §10/§11 bearer-secret operations, both `authenticated`-only:
 *
 *   preview_organization_invitation(p_invitation_id, p_acceptance_secret) -> jsonb
 *   accept_my_organization_invitation(p_invitation_id, p_acceptance_secret) -> jsonb
 *
 * The only inputs are the Invitation reference and the secret from the email
 * link; the secret goes nowhere but the RPC body. The accepting User, the
 * Organization and every responsibility come from the backend. Results are
 * outcome kinds, never backend text, so no error message can carry the secret.
 *
 * Presentation-only: the preview decides what to show, never what is allowed.
 */

export const INVITATION_PREVIEW_STATES = [
  'PENDING',
  'EXPIRED',
  'REVOKED',
  'ALREADY_MEMBER',
  'ACCEPTED_BY_YOU',
  'UNAVAILABLE',
] as const;
export type InvitationPreviewState = (typeof INVITATION_PREVIEW_STATES)[number];

export type InvitationPreview = {
  invitationId: string;
  state: InvitationPreviewState;
  organizationDisplayName: string | null;
  responsibilities: ScopedResponsibility[];
  maskedRecipientEmail: string | null;
  invitedEmailMatchesCurrentAccount: boolean | null;
  expiresAt: string | null;
};

export type InvitationPreviewResult =
  | { kind: 'preview'; preview: InvitationPreview }
  /** The uniform pre-proof failure (wrong/unknown/used): nothing is disclosed. */
  | { kind: 'unavailable' }
  | { kind: 'authenticationRequired' }
  /** Network, server or malformed payload: retryable, credential kept. */
  | { kind: 'failed' };

export type InvitationAcceptanceOutcome = 'ACCEPTED' | 'ALREADY_ACCEPTED';

export type InvitationAcceptanceResult =
  | {
      kind: 'accepted';
      outcome: InvitationAcceptanceOutcome;
      organizationId: string;
      membershipId: string;
    }
  | { kind: 'verificationRequired' }
  | { kind: 'authenticationRequired' }
  /**
   * Any other failure, or no trustworthy response at all. The client re-runs
   * the preview for the authoritative state (SPEC-ORG-003 §11) and never
   * parses failure text or retries acceptance blindly.
   */
  | { kind: 'previewAgain' };

const ORGANIZATION_ROLES: readonly OrganizationResponsibility[] = [
  'ADMINISTRATOR',
  'RECEPTIONIST',
  'VETERINARIAN',
];
const CLINIC_ROLES: readonly OrganizationResponsibility[] = ['ADMINISTRATOR', 'RECEPTIONIST'];
const INSTANT = /^\d{4}-\d{2}-\d{2}T/;

function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}

function hasExactKeys(raw: Record<string, unknown>, keys: readonly string[]): boolean {
  const present = Object.keys(raw);
  return present.length === keys.length && keys.every((key) => present.includes(key));
}

function parseResponsibility(raw: unknown): ScopedResponsibility | null {
  if (!isRecord(raw)) return null;
  const responsibility = ORGANIZATION_ROLES.find((role) => role === raw.responsibility);
  if (responsibility === undefined) return null;
  if (raw.scope_type === 'ORGANIZATION' && raw.clinic === null) {
    return { responsibility, scope: { type: 'ORGANIZATION' } };
  }
  if (
    raw.scope_type !== 'CLINIC' ||
    !CLINIC_ROLES.includes(responsibility) ||
    !isRecord(raw.clinic) ||
    !isInvitationId(raw.clinic.clinic_id) ||
    !(raw.clinic.clinic_display_name === null || typeof raw.clinic.clinic_display_name === 'string')
  ) {
    return null;
  }
  return {
    responsibility,
    scope: {
      type: 'CLINIC',
      clinic: { clinicId: raw.clinic.clinic_id, displayName: raw.clinic.clinic_display_name },
    },
  };
}

const PREVIEW_KEYS = [
  'invitation_id',
  'state',
  'organization_display_name',
  'responsibilities',
  'masked_recipient_email',
  'invited_email_matches_current_account',
  'expires_at',
] as const;

/**
 * Exported for unit testing. All-or-nothing; a payload for another Invitation
 * than the one requested is rejected.
 */
export function parseInvitationPreview(
  raw: unknown,
  invitationId: string,
): InvitationPreview | null {
  if (!isRecord(raw) || !hasExactKeys(raw, PREVIEW_KEYS)) return null;
  if (
    !isInvitationId(raw.invitation_id) ||
    raw.invitation_id.toLowerCase() !== invitationId.toLowerCase()
  ) {
    return null;
  }
  const state = INVITATION_PREVIEW_STATES.find((candidate) => candidate === raw.state);
  if (state === undefined || !Array.isArray(raw.responsibilities)) return null;

  if (state === 'UNAVAILABLE') {
    const disclosesNothing =
      raw.organization_display_name === null &&
      raw.responsibilities.length === 0 &&
      raw.masked_recipient_email === null &&
      raw.invited_email_matches_current_account === null &&
      raw.expires_at === null;
    return disclosesNothing
      ? {
          invitationId: raw.invitation_id.toLowerCase(),
          state,
          organizationDisplayName: null,
          responsibilities: [],
          maskedRecipientEmail: null,
          invitedEmailMatchesCurrentAccount: null,
          expiresAt: null,
        }
      : null;
  }

  const responsibilities: ScopedResponsibility[] = [];
  for (const item of raw.responsibilities) {
    const parsed = parseResponsibility(item);
    if (parsed === null) return null;
    responsibilities.push(parsed);
  }
  if (
    typeof raw.organization_display_name !== 'string' ||
    responsibilities.length === 0 ||
    typeof raw.masked_recipient_email !== 'string' ||
    !raw.masked_recipient_email.includes('***') ||
    typeof raw.invited_email_matches_current_account !== 'boolean' ||
    typeof raw.expires_at !== 'string' ||
    !INSTANT.test(raw.expires_at) ||
    !Number.isFinite(Date.parse(raw.expires_at))
  ) {
    return null;
  }
  return {
    invitationId: raw.invitation_id.toLowerCase(),
    state,
    organizationDisplayName: raw.organization_display_name,
    responsibilities,
    maskedRecipientEmail: raw.masked_recipient_email,
    invitedEmailMatchesCurrentAccount: raw.invited_email_matches_current_account,
    expiresAt: raw.expires_at,
  };
}

function rpcArguments(credential: OrganizationInvitationCredential) {
  return { p_invitation_id: credential.invitationId, p_acceptance_secret: credential.secret };
}

function isWellFormed(credential: OrganizationInvitationCredential): boolean {
  return isInvitationId(credential.invitationId) && isInvitationSecret(credential.secret);
}

export async function previewOrganizationInvitation(
  credential: OrganizationInvitationCredential,
): Promise<InvitationPreviewResult> {
  if (!isWellFormed(credential)) return { kind: 'unavailable' };
  try {
    const { data, error } = await supabase.rpc(
      'preview_organization_invitation',
      rpcArguments(credential),
    );
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '42501') return { kind: 'unavailable' };
      return { kind: 'failed' };
    }
    const preview = parseInvitationPreview(data, credential.invitationId);
    return preview === null ? { kind: 'failed' } : { kind: 'preview', preview };
  } catch {
    return { kind: 'failed' };
  }
}

export async function acceptOrganizationInvitation(
  credential: OrganizationInvitationCredential,
): Promise<InvitationAcceptanceResult> {
  if (!isWellFormed(credential)) return { kind: 'previewAgain' };
  try {
    const { data, error } = await supabase.rpc(
      'accept_my_organization_invitation',
      rpcArguments(credential),
    );
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '42501' && error.hint === 'ACCOUNT_VERIFICATION_REQUIRED') {
        return { kind: 'verificationRequired' };
      }
      return { kind: 'previewAgain' };
    }
    if (
      !isRecord(data) ||
      !hasExactKeys(data, ['invitation_id', 'organization_id', 'membership_id', 'outcome']) ||
      !isInvitationId(data.invitation_id) ||
      data.invitation_id.toLowerCase() !== credential.invitationId.toLowerCase() ||
      !isInvitationId(data.organization_id) ||
      !isInvitationId(data.membership_id) ||
      (data.outcome !== 'ACCEPTED' && data.outcome !== 'ALREADY_ACCEPTED')
    ) {
      return { kind: 'previewAgain' };
    }
    return {
      kind: 'accepted',
      outcome: data.outcome,
      organizationId: data.organization_id.toLowerCase(),
      membershipId: data.membership_id.toLowerCase(),
    };
  } catch {
    return { kind: 'previewAgain' };
  }
}

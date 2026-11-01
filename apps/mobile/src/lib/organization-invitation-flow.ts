import type { InvitationPreview, InvitationPreviewResult } from '@/data/organization-invitations';

/**
 * Screen states of the Organization Invitation acceptance flow (SPEC-ORG-003
 * §12). None of them holds the secret: the proof lives only in the secure
 * store (lib/pending-organization-invitation.ts) and in the RPC body.
 */
export type InvitationTerminalReason =
  'EXPIRED' | 'REVOKED' | 'ALREADY_MEMBER' | 'ACCEPTED_BY_YOU' | 'UNAVAILABLE';

export type InvitationReviewNotice = 'verificationRequired' | 'notAccepted' | null;

export type InvitationFlowPhase =
  | { kind: 'loading' }
  /** Generic copy only: the preview requires authentication. */
  | { kind: 'signedOut' }
  | {
      kind: 'review';
      preview: InvitationPreview;
      step: 'ready' | 'confirmMismatch' | 'accepting';
      notice: InvitationReviewNotice;
    }
  | { kind: 'terminal'; reason: InvitationTerminalReason; organizationDisplayName: string | null }
  /** The preview could not be read; the proof is kept and the read can be retried. */
  | { kind: 'failed' }
  /** Accepted; the professional context is being re-read. */
  | { kind: 'completing' }
  /** Accepted, but the professional context could not be re-read. Never re-accepts. */
  | { kind: 'contextFailed' };

/**
 * Where leaving the acceptance screen goes. Not `/`: both `(app)/index` and
 * `(auth)/index` serve `/`, and Expo Router resolves it to `(app)` regardless
 * of session, which `Stack.Protected` removes while signed out — the replace
 * would be dropped and the screen would stay. Same convention as
 * reset-password and request-appointment.
 */
export function invitationExitHref(hasSession: boolean): '/(app)' | '/(auth)' {
  return hasSession ? '/(app)' : '/(auth)';
}

export const UNAVAILABLE_PHASE: InvitationFlowPhase = {
  kind: 'terminal',
  reason: 'UNAVAILABLE',
  organizationDisplayName: null,
};

/**
 * Maps an authoritative preview read to the next phase, and whether the
 * pending proof must be cleared (every terminal outcome, including the uniform
 * failure, clears it; a retryable read failure or lost authentication keeps it).
 */
export function phaseForPreview(result: InvitationPreviewResult): {
  phase: InvitationFlowPhase;
  clearCredential: boolean;
} {
  switch (result.kind) {
    case 'authenticationRequired':
      return { phase: { kind: 'signedOut' }, clearCredential: false };
    case 'failed':
      return { phase: { kind: 'failed' }, clearCredential: false };
    case 'unavailable':
      return { phase: UNAVAILABLE_PHASE, clearCredential: true };
    case 'preview': {
      const { preview } = result;
      if (preview.state === 'PENDING') {
        return {
          phase: { kind: 'review', preview, step: 'ready', notice: null },
          clearCredential: false,
        };
      }
      return {
        phase: {
          kind: 'terminal',
          reason: preview.state,
          organizationDisplayName: preview.organizationDisplayName,
        },
        clearCredential: true,
      };
    }
  }
}

/**
 * Accept is explicit. A different signed-in address needs one more explicit
 * confirmation; an account the session reports as unconfirmed cannot accept
 * (the backend enforces both regardless).
 */
export function acceptStep(
  phase: Extract<InvitationFlowPhase, { kind: 'review' }>,
  isEmailConfirmed: boolean,
): 'blocked' | 'confirmMismatch' | 'accept' {
  if (!isEmailConfirmed || phase.step === 'accepting') return 'blocked';
  if (
    phase.preview.invitedEmailMatchesCurrentAccount === false &&
    phase.step !== 'confirmMismatch'
  ) {
    return 'confirmMismatch';
  }
  return 'accept';
}

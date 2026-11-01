import type { InvitationPreview } from '@/data/organization-invitations';
import {
  acceptStep,
  phaseForPreview,
  type InvitationFlowPhase,
} from '@/lib/organization-invitation-flow';

const preview = (overrides: Partial<InvitationPreview> = {}): InvitationPreview => ({
  invitationId: '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f',
  state: 'PENDING',
  organizationDisplayName: 'Animalia Group',
  responsibilities: [{ responsibility: 'RECEPTIONIST', scope: { type: 'ORGANIZATION' } }],
  maskedRecipientEmail: 'c***@example.com',
  invitedEmailMatchesCurrentAccount: true,
  expiresAt: '2030-01-08T10:00:00Z',
  ...overrides,
});

describe('phaseForPreview', () => {
  it('reviews a PENDING Invitation and keeps the proof', () => {
    expect(phaseForPreview({ kind: 'preview', preview: preview() })).toEqual({
      phase: { kind: 'review', preview: preview(), step: 'ready', notice: null },
      clearCredential: false,
    });
  });

  it.each(['EXPIRED', 'REVOKED', 'ALREADY_MEMBER', 'ACCEPTED_BY_YOU', 'UNAVAILABLE'] as const)(
    'ends on %s and clears the proof',
    (state) => {
      expect(phaseForPreview({ kind: 'preview', preview: preview({ state }) })).toEqual({
        phase: { kind: 'terminal', reason: state, organizationDisplayName: 'Animalia Group' },
        clearCredential: true,
      });
    },
  );

  it('ends on the uniform failure as unavailable, revealing nothing, and clears the proof', () => {
    expect(phaseForPreview({ kind: 'unavailable' })).toEqual({
      phase: { kind: 'terminal', reason: 'UNAVAILABLE', organizationDisplayName: null },
      clearCredential: true,
    });
  });

  it('keeps the proof when the read failed or authentication was lost', () => {
    expect(phaseForPreview({ kind: 'failed' })).toEqual({
      phase: { kind: 'failed' },
      clearCredential: false,
    });
    expect(phaseForPreview({ kind: 'authenticationRequired' })).toEqual({
      phase: { kind: 'signedOut' },
      clearCredential: false,
    });
  });
});

describe('acceptStep', () => {
  const review = (
    overrides: Partial<InvitationPreview>,
    step: 'ready' | 'confirmMismatch' | 'accepting' = 'ready',
  ): Extract<InvitationFlowPhase, { kind: 'review' }> => ({
    kind: 'review',
    preview: preview(overrides),
    step,
    notice: null,
  });

  it('accepts directly when the signed-in address matches', () => {
    expect(acceptStep(review({ invitedEmailMatchesCurrentAccount: true }), true)).toBe('accept');
  });

  it('asks for a second explicit confirmation when the signed-in address differs', () => {
    expect(acceptStep(review({ invitedEmailMatchesCurrentAccount: false }), true)).toBe(
      'confirmMismatch',
    );
    expect(
      acceptStep(review({ invitedEmailMatchesCurrentAccount: false }, 'confirmMismatch'), true),
    ).toBe('accept');
  });

  it('blocks an unconfirmed account and a second tap while accepting', () => {
    expect(acceptStep(review({}), false)).toBe('blocked');
    expect(acceptStep(review({}, 'accepting'), true)).toBe('blocked');
  });
});

import {
  acceptOrganizationInvitation,
  parseInvitationPreview,
  previewOrganizationInvitation,
} from '@/data/organization-invitations';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;

const ID = '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f';
const CLINIC = '7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const ORG = '11111111-2222-4333-8444-555555555555';
const MEMBERSHIP = '66666666-7777-4888-8999-aaaaaaaaaaaa';
const SECRET = 'cmVkYWN0ZWQtYnV0LXJlYWxpc3RpYy1zaGFwZWQtc2VjcmV0';
const CREDENTIAL = { invitationId: ID, secret: SECRET };

const pending = {
  invitation_id: ID,
  state: 'PENDING',
  organization_display_name: 'Animalia Group',
  responsibilities: [
    { responsibility: 'RECEPTIONIST', scope_type: 'ORGANIZATION', clinic: null },
    {
      responsibility: 'ADMINISTRATOR',
      scope_type: 'CLINIC',
      clinic: { clinic_id: CLINIC, clinic_display_name: null },
    },
  ],
  masked_recipient_email: 'c***@example.com',
  invited_email_matches_current_account: false,
  expires_at: '2030-01-08T10:00:00+00:00',
};
const unavailable = {
  invitation_id: ID,
  state: 'UNAVAILABLE',
  organization_display_name: null,
  responsibilities: [],
  masked_recipient_email: null,
  invited_email_matches_current_account: null,
  expires_at: null,
};

beforeEach(() => rpc.mockReset());

describe('parseInvitationPreview', () => {
  it('parses a PENDING preview with Organization and Clinic scopes', () => {
    expect(parseInvitationPreview(pending, ID)).toEqual({
      invitationId: ID,
      state: 'PENDING',
      organizationDisplayName: 'Animalia Group',
      responsibilities: [
        { responsibility: 'RECEPTIONIST', scope: { type: 'ORGANIZATION' } },
        {
          responsibility: 'ADMINISTRATOR',
          scope: { type: 'CLINIC', clinic: { clinicId: CLINIC, displayName: null } },
        },
      ],
      maskedRecipientEmail: 'c***@example.com',
      invitedEmailMatchesCurrentAccount: false,
      expiresAt: '2030-01-08T10:00:00+00:00',
    });
  });

  it.each(['EXPIRED', 'REVOKED', 'ALREADY_MEMBER', 'ACCEPTED_BY_YOU'])('parses %s', (state) => {
    expect(parseInvitationPreview({ ...pending, state }, ID)?.state).toBe(state);
  });

  it('parses UNAVAILABLE only when it discloses nothing else', () => {
    expect(parseInvitationPreview(unavailable, ID)?.state).toBe('UNAVAILABLE');
    expect(
      parseInvitationPreview({ ...unavailable, organization_display_name: 'Leak' }, ID),
    ).toBeNull();
  });

  it.each([
    ['a preview of another Invitation', { ...pending, invitation_id: CLINIC }],
    ['an unknown state', { ...pending, state: 'REJECTED' }],
    ['an extra member', { ...pending, organization_id: ORG }],
    ['a missing member', { ...pending, expires_at: undefined }],
    ['an unmasked address', { ...pending, masked_recipient_email: 'carlos@example.com' }],
    [
      'an OWNER responsibility',
      {
        ...pending,
        responsibilities: [{ responsibility: 'OWNER', scope_type: 'ORGANIZATION', clinic: null }],
      },
    ],
    [
      'a Clinic-scoped Veterinarian',
      {
        ...pending,
        responsibilities: [
          {
            responsibility: 'VETERINARIAN',
            scope_type: 'CLINIC',
            clinic: { clinic_id: CLINIC, clinic_display_name: 'x' },
          },
        ],
      },
    ],
    ['no responsibilities', { ...pending, responsibilities: [] }],
    ['a non-boolean email match', { ...pending, invited_email_matches_current_account: 'false' }],
    ['a non-object', 'PENDING'],
  ])('rejects %s', (_label, raw) => {
    expect(parseInvitationPreview(raw, ID)).toBeNull();
  });
});

describe('previewOrganizationInvitation', () => {
  it('sends only the reference and the secret, and only in the RPC body', async () => {
    rpc.mockResolvedValue({ data: pending, error: null });

    const result = await previewOrganizationInvitation(CREDENTIAL);

    expect(result.kind).toBe('preview');
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('preview_organization_invitation', {
      p_invitation_id: ID,
      p_acceptance_secret: SECRET,
    });
  });

  it.each([
    [{ code: '28000' }, 'authenticationRequired'],
    [{ code: '42501' }, 'unavailable'],
    [{ code: 'PGRST301' }, 'failed'],
  ])('maps %o to %s without exposing backend text', async (error, kind) => {
    rpc.mockResolvedValue({ data: null, error: { ...error, message: `failed ${SECRET}` } });
    const result = await previewOrganizationInvitation(CREDENTIAL);
    expect(result).toEqual({ kind });
    expect(JSON.stringify(result)).not.toContain(SECRET);
  });

  it('treats a malformed payload and a network rejection as retryable failures', async () => {
    rpc.mockResolvedValueOnce({ data: { ...pending, state: 'NOPE' }, error: null });
    await expect(previewOrganizationInvitation(CREDENTIAL)).resolves.toEqual({ kind: 'failed' });
    rpc.mockRejectedValueOnce(new Error(`network ${SECRET}`));
    await expect(previewOrganizationInvitation(CREDENTIAL)).resolves.toEqual({ kind: 'failed' });
  });

  it('never calls the backend with an ill-shaped proof', async () => {
    await expect(
      previewOrganizationInvitation({ invitationId: 'x', secret: SECRET }),
    ).resolves.toEqual({
      kind: 'unavailable',
    });
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('acceptOrganizationInvitation', () => {
  const accepted = {
    invitation_id: ID,
    organization_id: ORG,
    membership_id: MEMBERSHIP,
    outcome: 'ACCEPTED',
  };

  it('sends only the reference and the secret and returns the established Membership', async () => {
    rpc.mockResolvedValue({ data: accepted, error: null });

    await expect(acceptOrganizationInvitation(CREDENTIAL)).resolves.toEqual({
      kind: 'accepted',
      outcome: 'ACCEPTED',
      organizationId: ORG,
      membershipId: MEMBERSHIP,
    });
    expect(rpc).toHaveBeenCalledWith('accept_my_organization_invitation', {
      p_invitation_id: ID,
      p_acceptance_secret: SECRET,
    });
  });

  it('reports the idempotent lost-response outcome', async () => {
    rpc.mockResolvedValue({ data: { ...accepted, outcome: 'ALREADY_ACCEPTED' }, error: null });
    await expect(acceptOrganizationInvitation(CREDENTIAL)).resolves.toMatchObject({
      kind: 'accepted',
      outcome: 'ALREADY_ACCEPTED',
    });
  });

  it.each([
    [{ code: '28000' }, 'authenticationRequired'],
    [{ code: '42501', hint: 'ACCOUNT_VERIFICATION_REQUIRED' }, 'verificationRequired'],
    [{ code: '42501', hint: null }, 'previewAgain'],
    [{ code: '23514', hint: 'INVITATION_EXPIRED' }, 'previewAgain'],
    [{ code: '23514', hint: 'INVITATION_REVOKED' }, 'previewAgain'],
    [{ code: '23505', hint: 'ALREADY_MEMBER' }, 'previewAgain'],
  ])('maps %o to %s and never parses failure text', async (error, kind) => {
    rpc.mockResolvedValue({ data: null, error: { ...error, message: 'Invitation unavailable' } });
    await expect(acceptOrganizationInvitation(CREDENTIAL)).resolves.toEqual({ kind });
  });

  it('treats a lost or untrustworthy response as previewAgain, never as success', async () => {
    rpc.mockRejectedValueOnce(new Error('network'));
    await expect(acceptOrganizationInvitation(CREDENTIAL)).resolves.toEqual({
      kind: 'previewAgain',
    });
    rpc.mockResolvedValueOnce({ data: { ...accepted, invitation_id: CLINIC }, error: null });
    await expect(acceptOrganizationInvitation(CREDENTIAL)).resolves.toEqual({
      kind: 'previewAgain',
    });
    rpc.mockResolvedValueOnce({ data: { ...accepted, outcome: 'MAYBE' }, error: null });
    await expect(acceptOrganizationInvitation(CREDENTIAL)).resolves.toEqual({
      kind: 'previewAgain',
    });
  });
});

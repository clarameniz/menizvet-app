import {
  inviteOrganizationStaff,
  revokeOrganizationInvitation,
  staffInviteRequestBody,
  STAFF_INVITE_ROLES,
  type StaffInviteInput,
} from '@/data/organization-staff';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({
  supabase: { rpc: jest.fn(), functions: { invoke: jest.fn() } },
}));
const rpc = supabase.rpc as jest.Mock;
const invoke = supabase.functions.invoke as jest.Mock;
const A = 'd0270000-0000-4000-8000-000000000301';
const C = 'd0270000-0000-4000-8000-000000000401';
const I = 'd0270000-0000-4000-8000-000000000701';
const input = (overrides: Partial<StaffInviteInput> = {}): StaffInviteInput => ({
  organizationId: A,
  recipientEmail: ' Laura@Example.Test ',
  role: 'RECEPTIONIST',
  scope: 'ORGANIZATION',
  clinicId: null,
  ...overrides,
});
/** What supabase-js produces for a non-2xx Edge answer. */
const httpError = (status: number, body: unknown) =>
  Object.assign(new Error('Edge Function returned a non-2xx status code'), {
    name: 'FunctionsHttpError',
    context: { status, json: () => Promise.resolve(body) },
  });
beforeEach(() => {
  rpc.mockReset();
  invoke.mockReset();
});

describe('inviteOrganizationStaff', () => {
  it('offers exactly Administrator, Receptionist and Veterinarian (SPEC-ORG-002 BR-17)', () => {
    expect(STAFF_INVITE_ROLES).toEqual(['ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN']);
  });
  it('sends the exact Phase 1 body: no expiry, recipient User, or responsibility array', async () => {
    invoke.mockResolvedValue({ data: { invitation_id: I }, error: null });
    expect(await inviteOrganizationStaff(input())).toEqual({ kind: 'created', invitationId: I });
    expect(invoke).toHaveBeenCalledWith('communications/create-organization-invitation', {
      body: {
        organization_id: A,
        recipient_email: ' Laura@Example.Test ',
        responsibility: 'RECEPTIONIST',
        scope_type: 'ORGANIZATION',
        clinic_id: null,
      },
    });
    const clinic = staffInviteRequestBody(
      input({ role: 'ADMINISTRATOR', scope: 'CLINIC', clinicId: C }),
    );
    expect(Object.keys(clinic).sort()).toEqual([
      'clinic_id',
      'organization_id',
      'recipient_email',
      'responsibility',
      'scope_type',
    ]);
    expect(clinic.clinic_id).toBe(C);
    // A stale Clinic never leaks into an Organization-scoped request.
    expect(staffInviteRequestBody(input({ clinicId: C })).clinic_id).toBeNull();
  });
  it.each([
    [400, 'INVALID_RECIPIENT'],
    [400, 'INVALID_ROLE_SCOPE'],
    [400, 'INVALID_CLINIC'],
    [400, 'INVALID_REQUEST'],
    [403, 'ACCOUNT_VERIFICATION_REQUIRED'],
    [403, 'ORGANIZATION_UNAVAILABLE'],
    [409, 'PENDING_INVITATION_EXISTS'],
    [409, 'ACTIVE_MEMBER'],
  ])('maps a definite %i %s rejection', async (status, code) => {
    invoke.mockResolvedValue({ data: null, error: httpError(status, { error: code }) });
    expect(await inviteOrganizationStaff(input())).toEqual({ kind: 'rejected', reason: code });
  });
  it('treats 401 as authentication loss and unreadable definite rejections conservatively', async () => {
    invoke.mockResolvedValueOnce({ data: null, error: httpError(401, { error: 'whatever' }) });
    expect(await inviteOrganizationStaff(input())).toEqual({
      kind: 'rejected',
      reason: 'AUTHENTICATION_REQUIRED',
    });
    invoke.mockResolvedValueOnce({ data: null, error: httpError(403, 'not json') });
    expect(await inviteOrganizationStaff(input())).toEqual({
      kind: 'rejected',
      reason: 'ORGANIZATION_UNAVAILABLE',
    });
    invoke.mockResolvedValueOnce({
      data: null,
      error: httpError(409, { error: 'SQLSTATE 23505' }),
    });
    expect(await inviteOrganizationStaff(input())).toEqual({
      kind: 'rejected',
      reason: 'PENDING_INVITATION_EXISTS',
    });
  });
  it('never claims success or failure without a definite answer', async () => {
    const lost = [
      { data: null, error: httpError(500, { error: 'INTERNAL_ERROR' }) },
      { data: null, error: httpError(502, null) },
      {
        data: null,
        error: Object.assign(new Error('fetch failed'), { name: 'FunctionsFetchError' }),
      },
      { data: null, error: Object.assign(new Error('relay'), { name: 'FunctionsRelayError' }) },
      { data: { invitation_id: 'not-a-uuid' }, error: null },
      { data: { secret: 'x' }, error: null },
    ];
    for (const response of lost) {
      invoke.mockResolvedValueOnce(response);
      expect(await inviteOrganizationStaff(input())).toEqual({ kind: 'uncertain' });
    }
    invoke.mockRejectedValueOnce(new Error('Network request failed'));
    expect(await inviteOrganizationStaff(input())).toEqual({ kind: 'uncertain' });
    expect(invoke).toHaveBeenCalledTimes(lost.length + 1);
  });
});

describe('revokeOrganizationInvitation', () => {
  it.each(['REVOKED', 'ALREADY_REVOKED', 'ACCEPTED', 'EXPIRED', 'REJECTED'])(
    'reports the authoritative %s outcome',
    async (outcome) => {
      rpc.mockResolvedValue({ data: { invitation_id: I, outcome }, error: null });
      expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'outcome', outcome });
      expect(rpc).toHaveBeenCalledWith('revoke_organization_invitation', { p_invitation_id: I });
    },
  );
  it('separates access loss, authentication loss and uncertainty', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'x' } });
    expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'accessDenied' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000', message: 'x' } });
    expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'authenticationRequired' });
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '', message: 'Network request failed' },
    });
    expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'uncertain' });
    rpc.mockResolvedValueOnce({ data: { invitation_id: C, outcome: 'REVOKED' }, error: null });
    expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'uncertain' });
    rpc.mockResolvedValueOnce({ data: { invitation_id: I, outcome: 'DELETED' }, error: null });
    expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'uncertain' });
    rpc.mockRejectedValueOnce(new Error('offline'));
    expect(await revokeOrganizationInvitation(I)).toEqual({ kind: 'uncertain' });
  });
  it('never sends a malformed Invitation reference', async () => {
    expect(await revokeOrganizationInvitation('i-1')).toEqual({ kind: 'accessDenied' });
    expect(rpc).not.toHaveBeenCalled();
  });
});

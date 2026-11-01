import {
  compareStaffInvitationKeys,
  endOrganizationStaffMembership,
  getOrganizationPendingInvitationsPage,
  getOrganizationStaff,
  getOrganizationStaffMembersPage,
  parseOrganizationStaff,
  parseStaffInvitationsPage,
  parseStaffMembersPage,
  recheckPendingInvitation,
  STAFF_ACCESS_DENIED,
  STAFF_MALFORMED,
} from '@/data/organization-staff';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;
const A = 'd0090000-0000-4000-8000-000000000301';
const B = 'd0090000-0000-4000-8000-000000000302';
const M = 'd0090000-0000-4000-8000-000000000501';
const I = 'd0090000-0000-4000-8000-000000000701';
const C = 'd0090000-0000-4000-8000-000000000401';
const G1 = 'd0090000-0000-4000-8000-000000000601';
const G2 = 'd0090000-0000-4000-8000-000000000602';
const G3 = 'd0090000-0000-4000-8000-000000000603';
const payload = () => ({
  organization_id: A,
  organization_display_name: 'A',
  members: [
    {
      membership_id: M,
      effective_start: '2020-01-01T00:00:00Z',
      is_self: true,
      display_name: null,
      invitation_recipient_email: 'invited@example.test' as string | null,
      responsibilities: [
        {
          responsibility_grant_id: G1,
          responsibility: 'OWNER',
          scope_type: 'ORGANIZATION',
          clinic: null,
        },
        {
          responsibility_grant_id: G2,
          responsibility: 'VETERINARIAN',
          scope_type: 'ORGANIZATION',
          clinic: null,
        },
        {
          responsibility_grant_id: G3,
          responsibility: 'RECEPTIONIST',
          scope_type: 'CLINIC',
          clinic: { clinic_id: C, clinic_display_name: 'A Centro' },
        },
      ],
    },
  ],
  pending_invitations: [
    {
      invitation_id: I,
      recipient_email: 'pending@example.test',
      responsibilities: [
        { responsibility: 'ADMINISTRATOR', scope_type: 'ORGANIZATION', clinic: null },
      ],
      created_at: '2030-01-01T00:00:00Z',
      expires_at: '2030-01-08T00:00:00Z',
    },
  ],
});
beforeEach(() => rpc.mockReset());
it('parses approved identity, every current role, and separate pending invitations', () => {
  const staff = parseOrganizationStaff(payload(), A)!;
  expect(staff.members[0]).toMatchObject({
    membershipId: M,
    displayName: null,
    invitationRecipientEmail: 'invited@example.test',
    isSelf: true,
  });
  expect(staff.members[0].responsibilities.map((r) => r.responsibility)).toEqual([
    'OWNER',
    'VETERINARIAN',
    'RECEPTIONIST',
  ]);
  expect(staff.members[0].responsibilities[2].scope).toEqual({
    type: 'CLINIC',
    clinic: { clinicId: C, displayName: 'A Centro' },
  });
  // SPEC-ORG-009 BR-1: each current Grant names itself for Staff writes.
  expect(staff.members[0].responsibilities.map((r) => r.responsibilityGrantId)).toEqual([
    G1,
    G2,
    G3,
  ]);
  expect(Object.keys(staff.pendingInvitations[0].responsibilities[0]).sort()).toEqual([
    'responsibility',
    'scope',
  ]);
  expect(staff.pendingInvitations[0]).toMatchObject({
    invitationId: I,
    recipientEmail: 'pending@example.test',
  });
});
it('preserves absent identity and empty arrays without expecting Auth email', () => {
  const raw = payload();
  raw.members[0].invitation_recipient_email = null;
  raw.members[0].responsibilities = [];
  raw.pending_invitations = [];
  expect(parseOrganizationStaff(raw, A)?.members[0]).toMatchObject({
    displayName: null,
    invitationRecipientEmail: null,
    responsibilities: [],
  });
  expect(parseOrganizationStaff({ ...raw, members: [] }, A)).toMatchObject({
    members: [],
    pendingInvitations: [],
  });
});
it('never copies unknown authentication or User identity fields into the client model', () => {
  const raw = payload();
  Object.assign(raw.members[0], { auth_email: 'private@example.test', user_id: 'hidden' });
  const member = parseOrganizationStaff(raw, A)!.members[0];
  expect(Object.keys(member).sort()).toEqual([
    'displayName',
    'effectiveStart',
    'invitationRecipientEmail',
    'isSelf',
    'membershipId',
    'responsibilities',
  ]);
  expect(JSON.stringify(member)).not.toContain('private@example.test');
});
it('rejects another Organization response instead of merging rows', () => {
  expect(parseOrganizationStaff(payload(), B)).toBeNull();
  expect(
    parseOrganizationStaff(
      { ...payload(), organization_id: B, organization_display_name: 'B', members: [] },
      B,
    )?.members,
  ).toEqual([]);
});
it.each(['members', 'pending_invitations', 'organization_display_name'])(
  'rejects missing %s',
  (key) => {
    const raw: Record<string, unknown> = payload();
    delete raw[key];
    expect(parseOrganizationStaff(raw, A)).toBeNull();
  },
);
it('rejects malformed roles, Clinic identity, instants and unnormalized address', () => {
  for (const patch of [
    { effective_start: 'yesterday' },
    { invitation_recipient_email: 'UPPER@example.test' },
    {
      responsibilities: [
        {
          responsibility: 'OWNER',
          scope_type: 'CLINIC',
          clinic: { clinic_id: C, clinic_display_name: 'A' },
        },
      ],
    },
    { responsibilities: [{ responsibility: 'RECEPTIONIST', scope_type: 'CLINIC', clinic: null }] },
    { responsibilities: [{ responsibility: 'UNKNOWN', scope_type: 'ORGANIZATION', clinic: null }] },
    // A member Grant without its identifier cannot be managed: reject the read.
    {
      responsibilities: [
        { responsibility: 'RECEPTIONIST', scope_type: 'ORGANIZATION', clinic: null },
      ],
    },
    {
      responsibilities: [
        {
          responsibility_grant_id: 'not-a-uuid',
          responsibility: 'RECEPTIONIST',
          scope_type: 'ORGANIZATION',
          clinic: null,
        },
      ],
    },
  ]) {
    const raw = payload();
    Object.assign(raw.members[0], patch);
    expect(parseOrganizationStaff(raw, A)).toBeNull();
  }
});
it('uses only the Organization read RPC with explicit Organization context', async () => {
  rpc.mockResolvedValue({ data: payload(), error: null });
  expect((await getOrganizationStaff(A)).error).toBeNull();
  expect(rpc).toHaveBeenCalledTimes(1);
  expect(rpc).toHaveBeenCalledWith('get_organization_staff', { p_organization_id: A });
});
it.each([
  ['42501', STAFF_ACCESS_DENIED],
  ['28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED],
])('normalizes %s', async (code, expected) => {
  rpc.mockResolvedValue({ data: null, error: { code, message: 'server' } });
  expect(await getOrganizationStaff(A)).toEqual({ data: null, error: expected });
});
it('settles malformed, invalid route and network failures without stale data', async () => {
  expect(await getOrganizationStaff('invalid')).toEqual({ data: null, error: STAFF_ACCESS_DENIED });
  expect(rpc).not.toHaveBeenCalled();
  rpc.mockResolvedValueOnce({ data: payload(), error: null });
  expect(await getOrganizationStaff(B)).toEqual({ data: null, error: STAFF_MALFORMED });
  rpc.mockRejectedValueOnce(new Error('offline'));
  expect(await getOrganizationStaff(A)).toEqual({ data: null, error: 'offline' });
});

describe('endOrganizationStaffMembership', () => {
  const MEMBERSHIP = '6f1d2c3b-4a59-4687-9a6b-5c4d3e2f1a0b';
  const rpc = supabase.rpc as jest.Mock;
  beforeEach(() => rpc.mockReset());

  it('sends only the Membership id and returns the outcome with its effective end', async () => {
    rpc.mockResolvedValue({
      data: {
        membership_id: MEMBERSHIP,
        effective_end: '2030-01-02T00:00:00+00:00',
        outcome: 'ENDED',
      },
      error: null,
    });
    await expect(endOrganizationStaffMembership(MEMBERSHIP)).resolves.toEqual({
      kind: 'outcome',
      outcome: 'ENDED',
      effectiveEnd: '2030-01-02T00:00:00+00:00',
    });
    expect(rpc).toHaveBeenCalledWith('end_organization_staff_membership', {
      p_membership_id: MEMBERSHIP,
    });
  });

  it('treats ALREADY_ENDED as an outcome, not an error', async () => {
    rpc.mockResolvedValue({
      data: {
        membership_id: MEMBERSHIP,
        effective_end: '2021-01-01T00:00:00+00:00',
        outcome: 'ALREADY_ENDED',
      },
      error: null,
    });
    await expect(endOrganizationStaffMembership(MEMBERSHIP)).resolves.toMatchObject({
      kind: 'outcome',
      outcome: 'ALREADY_ENDED',
    });
  });

  it.each([
    [{ code: '42501' }, 'accessDenied'],
    [{ code: '28000' }, 'authenticationRequired'],
    [{ code: '23514', hint: 'SELF_MEMBERSHIP' }, 'protected'],
    [{ code: '23514', hint: 'OWNER_MEMBERSHIP' }, 'protected'],
    [{ code: 'PGRST301' }, 'uncertain'],
  ])('maps %o to %s', async (error, kind) => {
    rpc.mockResolvedValue({ data: null, error: { ...error, message: 'x' } });
    await expect(endOrganizationStaffMembership(MEMBERSHIP)).resolves.toEqual({ kind });
  });

  it('never trusts an untrustworthy response and never calls with a malformed id', async () => {
    rpc.mockRejectedValueOnce(new Error('network'));
    await expect(endOrganizationStaffMembership(MEMBERSHIP)).resolves.toEqual({
      kind: 'uncertain',
    });
    rpc.mockResolvedValueOnce({
      data: { membership_id: 'another', effective_end: '2030-01-02T00:00:00Z', outcome: 'ENDED' },
      error: null,
    });
    await expect(endOrganizationStaffMembership(MEMBERSHIP)).resolves.toEqual({
      kind: 'uncertain',
    });
    rpc.mockReset();
    await expect(endOrganizationStaffMembership('not-an-id')).resolves.toEqual({
      kind: 'accessDenied',
    });
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('paged Staff reads (SPEC-ORG-009 §12)', () => {
  const memberRow = (overrides: Record<string, unknown> = {}) => ({
    ...payload().members[0],
    display_name: 'Ana',
    display_name_is_shared: true,
    ...overrides,
  });
  const invitationRow = () => payload().pending_invitations[0];

  it('parses a Members page with the shared-name flag, strictly', () => {
    const [row] = parseStaffMembersPage([memberRow()])!;
    expect(row).toMatchObject({ membershipId: M, displayName: 'Ana', displayNameIsShared: true });
    expect(row.responsibilities).toHaveLength(3);
    expect(parseStaffMembersPage([])).toEqual([]);
    for (const raw of [
      [memberRow({ display_name_is_shared: undefined })],
      [memberRow({ display_name_is_shared: 'yes' })],
      // A shared flag without a name is incoherent.
      [memberRow({ display_name: null, display_name_is_shared: true })],
      [memberRow(), memberRow()],
      [memberRow({ membership_id: 'not-a-uuid' })],
      null,
    ]) {
      expect(parseStaffMembersPage(raw)).toBeNull();
    }
  });

  it('parses an Invitations page strictly, with no Invitation twice', () => {
    expect(parseStaffInvitationsPage([invitationRow()])).toEqual([
      expect.objectContaining({ invitationId: I, recipientEmail: 'pending@example.test' }),
    ]);
    expect(parseStaffInvitationsPage([invitationRow(), invitationRow()])).toBeNull();
    expect(
      parseStaffInvitationsPage([{ ...invitationRow(), expires_at: '2029-01-01T00:00:00Z' }]),
    ).toBeNull();
  });

  it('sends the first page without a cursor and later pages with the exact key', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await getOrganizationStaffMembersPage(A, null, 25);
    await getOrganizationStaffMembersPage(
      A,
      { effectiveStart: '2021-03-04T05:06:07.123456+00:00', membershipId: M },
      25,
    );
    await getOrganizationPendingInvitationsPage(A, null, 20);
    await getOrganizationPendingInvitationsPage(
      A,
      { createdAt: '2030-01-02T03:04:05.654321+00:00', invitationId: I },
      20,
    );
    expect(rpc.mock.calls).toEqual([
      [
        'get_organization_staff_members',
        {
          p_organization_id: A,
          p_after_effective_start: null,
          p_after_membership_id: null,
          p_limit: 25,
        },
      ],
      [
        'get_organization_staff_members',
        {
          p_organization_id: A,
          p_after_effective_start: '2021-03-04T05:06:07.123456+00:00',
          p_after_membership_id: M,
          p_limit: 25,
        },
      ],
      [
        'get_organization_pending_invitations',
        {
          p_organization_id: A,
          p_after_created_at: null,
          p_after_invitation_id: null,
          p_limit: 20,
        },
      ],
      [
        'get_organization_pending_invitations',
        {
          p_organization_id: A,
          p_after_created_at: '2030-01-02T03:04:05.654321+00:00',
          p_after_invitation_id: I,
          p_limit: 20,
        },
      ],
    ]);
    expect(rpc.mock.calls.map(([name]) => name)).not.toContain('get_organization_staff');
  });

  it('normalizes 28000, 42501, malformed pages and rejections; never calls with a bad id', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000', message: 'auth' } });
    expect(await getOrganizationStaffMembersPage(A, null, 25)).toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'denied' } });
    expect(await getOrganizationPendingInvitationsPage(A, null, 20)).toEqual({
      data: null,
      error: STAFF_ACCESS_DENIED,
    });
    rpc.mockResolvedValueOnce({ data: [memberRow({ display_name_is_shared: null })], error: null });
    expect(await getOrganizationStaffMembersPage(A, null, 25)).toEqual({
      data: null,
      error: STAFF_MALFORMED,
    });
    rpc.mockRejectedValueOnce(new Error('Network request failed'));
    expect(await getOrganizationPendingInvitationsPage(A, null, 20)).toEqual({
      data: null,
      error: 'Network request failed',
    });
    rpc.mockClear();
    expect(await getOrganizationStaffMembersPage('A', null, 25)).toEqual({
      data: null,
      error: STAFF_ACCESS_DENIED,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('re-checks one Invitation as the single row after the one listed before it', async () => {
    const target = parseStaffInvitationsPage([invitationRow()])![0];
    const previous = { ...target, invitationId: B, createdAt: '2029-12-31T00:00:00Z' };
    rpc.mockResolvedValueOnce({ data: [invitationRow()], error: null });
    expect(await recheckPendingInvitation(A, target, previous)).toBe('pending');
    expect(rpc).toHaveBeenLastCalledWith('get_organization_pending_invitations', {
      p_organization_id: A,
      p_after_created_at: '2029-12-31T00:00:00Z',
      p_after_invitation_id: B,
      p_limit: 1,
    });
    rpc.mockResolvedValueOnce({ data: [], error: null });
    expect(await recheckPendingInvitation(A, target, null)).toBe('notPending');
    expect(rpc).toHaveBeenLastCalledWith('get_organization_pending_invitations', {
      p_organization_id: A,
      p_after_created_at: null,
      p_after_invitation_id: null,
      p_limit: 1,
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'denied' } });
    expect(await recheckPendingInvitation(A, target, null)).toBe('unavailable');
    rpc.mockRejectedValueOnce(new Error('offline'));
    expect(await recheckPendingInvitation(A, target, null)).toBe('error');
  });
});

describe('lost revocation response: the one-row re-check proves, or stays uncertain', () => {
  // Keys in BR-15 order: created_at, then id. T is the revoked Invitation's.
  const T = '2030-01-01T10:00:00.123+00:00';
  const ID = (n: number) => `d0090000-0000-4000-8000-00000000080${n}`;
  const row = (id: string, createdAt: string) => ({
    invitation_id: id,
    recipient_email: `${id.slice(-3)}@example.test`,
    responsibilities: [
      { responsibility: 'RECEPTIONIST', scope_type: 'ORGANIZATION', clinic: null },
    ],
    created_at: createdAt,
    expires_at: '2030-01-08T00:00:00Z',
  });
  const parsed = (id: string, createdAt: string) =>
    parseStaffInvitationsPage([row(id, createdAt)])![0];
  const target = () => parsed(ID(5), T);
  const answer = (...rows: ReturnType<typeof row>[]) =>
    rpc.mockResolvedValueOnce({ data: rows, error: null });

  it('still pending when the next pending key is this Invitation, even if the one before it was revoked meanwhile', async () => {
    answer(row(ID(5), T));
    expect(await recheckPendingInvitation(A, target(), parsed(ID(1), '2030-01-01T09:00:00Z'))).toBe(
      'pending',
    );
  });

  it('not pending only when nothing, or only a LATER key, follows the previous one', async () => {
    answer();
    expect(await recheckPendingInvitation(A, target(), null)).toBe('notPending');
    // A newer Invitation (created after this one) now comes next.
    answer(row(ID(9), '2030-01-01T11:00:00Z'));
    expect(await recheckPendingInvitation(A, target(), null)).toBe('notPending');
    // Same millisecond, larger id: still after it.
    answer(row(ID(6), T));
    expect(await recheckPendingInvitation(A, target(), null)).toBe('notPending');
  });

  it('first in the list + a concurrent Invitation committed late with an EARLIER key: uncertain, never "not pending"', async () => {
    // Created by a statement that started before ours but committed after the
    // list was read: it now sorts first, whether ours is pending or not.
    answer(row(ID(2), '2030-01-01T09:59:59.999+00:00'));
    expect(await recheckPendingInvitation(A, target(), null)).toBe('error');
  });

  it('an earlier key appearing between the previous row and this one: uncertain', async () => {
    answer(row(ID(3), '2030-01-01T09:30:00Z'));
    expect(await recheckPendingInvitation(A, target(), parsed(ID(1), '2030-01-01T09:00:00Z'))).toBe(
      'error',
    );
  });

  it('a tie in the same millisecond with a smaller id: uncertain', async () => {
    answer(row(ID(4), T));
    expect(await recheckPendingInvitation(A, target(), null)).toBe('error');
  });

  it('orders keys exactly: microseconds, offsets written differently, ties by id', () => {
    const key = (createdAt: string, invitationId = ID(5)) => ({ createdAt, invitationId });
    expect(
      compareStaffInvitationKeys(key('2030-01-01T10:00:00.000001Z'), key('2030-01-01T10:00:00Z')),
    ).toBe(1);
    expect(
      compareStaffInvitationKeys(
        key('2030-01-01T10:00:00.12345+00:00'),
        key('2030-01-01T10:00:00.123451+00:00'),
      ),
    ).toBe(-1);
    expect(
      compareStaffInvitationKeys(key('2030-01-01T12:00:00+02:00'), key('2030-01-01T10:00:00Z')),
    ).toBe(0);
    expect(
      compareStaffInvitationKeys(
        key('2030-01-01T12:00:00+02'),
        key('2030-01-01T10:00:00.000000+00:00'),
      ),
    ).toBe(0);
    expect(compareStaffInvitationKeys(key(T, ID(4)), key(T, ID(5)))).toBe(-1);
    expect(compareStaffInvitationKeys(key('2030-01-01T10:00:00.1234567Z'), key(T))).toBeNull();
    expect(compareStaffInvitationKeys(key('not a time'), key(T))).toBeNull();
  });

  it('a key that cannot be compared exactly stays uncertain', async () => {
    answer(row(ID(9), '2030-01-01T11:00:00.1234567+00:00'));
    // Whether the page or the comparison refuses it, it is never a conclusion.
    expect(await recheckPendingInvitation(A, target(), null)).toBe('error');
  });
});

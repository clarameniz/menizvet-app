import {
  STAFF_ACCESS_DENIED,
  type OrganizationStaff,
  type PendingStaffInvitation,
  type StaffInviteInput,
  type StaffMember,
  type StaffResult,
} from '@/data/organization-staff';
import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type OrganizationProfessionalContext,
  type ProfessionalCapability,
  type ProfessionalContext,
} from '@/data/professional-context';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import { isEndAccessTarget } from '@/lib/organization-staff';
import {
  canSendInvite,
  EMPTY_STAFF_INVITE_DRAFT,
  endAccessNotice,
  inviteClinicOptions,
  inviteInputFrom,
  inviteRejectionKey,
  normalizedInvitationEmail,
  pendingInvitationIds,
  reconcileLostInvite,
  revocationNotice,
  staffActionsFor,
  withInviteScope,
  type StaffReread,
} from '@/lib/staff-invitation';

// The data modules' constants pull in lib/supabase, which needs env vars under Jest.
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const organization = (
  organizationId: string,
  capabilities: [ProfessionalCapability, 'ORGANIZATION' | 'CLINIC'][],
): OrganizationProfessionalContext => ({
  membershipId: `m-${organizationId}`,
  organizationId,
  organizationDisplayName: organizationId,
  responsibilities: [],
  capabilities: capabilities.map(([capability, scope]) => ({
    capability,
    scope:
      scope === 'ORGANIZATION'
        ? { type: 'ORGANIZATION' }
        : { type: 'CLINIC', clinic: { clinicId: 'c', displayName: null } },
  })),
  unknownCapabilities: [],
  clinicAssignments: [],
  entitlements: {
    APPOINTMENT_MANAGEMENT: false,
    PROFESSIONAL_SCHEDULING: false,
    CLINICAL_CARE: false,
    CLINICAL_DOCUMENTATION: false,
  },
});
const context = (...organizations: OrganizationProfessionalContext[]): ProfessionalContext => ({
  hasVeterinarianProfessionalProfile: false,
  organizations,
});
const clinic = (clinicId: string, organizationId: string): ProfessionalClinic => ({
  clinicId,
  clinicDisplayName: clinicId === 'a2' ? null : `Clinic ${clinicId}`,
  organizationId,
  organizationDisplayName: organizationId,
  capabilities: ['APPOINTMENT_VIEW_SCHEDULE'],
  unknownCapabilities: [],
});
const pending = (
  invitationId: string,
  recipientEmail: string,
  responsibilities: PendingStaffInvitation['responsibilities'],
): PendingStaffInvitation => ({
  invitationId,
  recipientEmail,
  responsibilities,
  createdAt: '2030-01-01T00:00:00Z',
  expiresAt: '2030-01-08T00:00:00Z',
});
const staff = (...pendingInvitations: PendingStaffInvitation[]): StaffResult => ({
  data: {
    organizationId: 'A',
    organizationDisplayName: 'A',
    members: [],
    pendingInvitations,
  } satisfies OrganizationStaff,
  error: null,
});
const input: StaffInviteInput = {
  organizationId: 'A',
  recipientEmail: '  Laura@Example.Test ',
  role: 'ADMINISTRATOR',
  scope: 'CLINIC',
  clinicId: 'a1',
};
const clinicAdmin = [
  {
    responsibility: 'ADMINISTRATOR' as const,
    scope: { type: 'CLINIC' as const, clinic: { clinicId: 'a1', displayName: 'Clinic a1' } },
  },
];

describe('advisory actions', () => {
  it('needs the exact Organization-scoped capability in the route Organization', () => {
    const both = context(
      organization('A', [
        ['ORGANIZATION_INVITE_MEMBERS', 'ORGANIZATION'],
        ['ORGANIZATION_REVOKE_INVITATIONS', 'ORGANIZATION'],
      ]),
      organization('B', [['ORGANIZATION_END_MEMBERSHIPS', 'ORGANIZATION']]),
    );
    expect(staffActionsFor(both, 'A')).toEqual({
      invite: true,
      revoke: true,
      endAccess: false,
      manage: false,
      manageAssignments: false,
    });
    expect(staffActionsFor(both, 'a')).toEqual({
      invite: true,
      revoke: true,
      endAccess: false,
      manage: false,
      manageAssignments: false,
    });
    expect(staffActionsFor(both, 'B')).toEqual({
      invite: false,
      revoke: false,
      endAccess: true,
      manage: false,
      manageAssignments: false,
    });
    expect(staffActionsFor(both, 'C')).toEqual({
      invite: false,
      revoke: false,
      endAccess: false,
      manage: false,
      manageAssignments: false,
    });
    expect(
      staffActionsFor(
        context(organization('A', [['ORGANIZATION_REVOKE_INVITATIONS', 'ORGANIZATION']])),
        'A',
      ),
    ).toEqual({
      invite: false,
      revoke: true,
      endAccess: false,
      manage: false,
      manageAssignments: false,
    });
    expect(
      staffActionsFor(context(organization('A', [['ORGANIZATION_INVITE_MEMBERS', 'CLINIC']])), 'A'),
    ).toEqual({
      invite: false,
      revoke: false,
      endAccess: false,
      manage: false,
      manageAssignments: false,
    });
    expect(staffActionsFor(null, 'A')).toEqual({
      invite: false,
      revoke: false,
      endAccess: false,
      manage: false,
      manageAssignments: false,
    });
  });
});

describe('invite draft', () => {
  it('starts with no role, Organization scope and no Clinic, expiry or User fields', () => {
    expect(EMPTY_STAFF_INVITE_DRAFT).toEqual({
      email: '',
      role: null,
      scope: 'ORGANIZATION',
      clinicId: null,
    });
  });
  it('switching scope discards the drafted Clinic', () => {
    const clinicDraft = {
      email: 'x@y',
      role: 'RECEPTIONIST' as const,
      scope: 'CLINIC' as const,
      clinicId: 'a1',
    };
    expect(withInviteScope(clinicDraft, 'ORGANIZATION')).toEqual({
      ...clinicDraft,
      scope: 'ORGANIZATION',
      clinicId: null,
    });
    expect(
      withInviteScope(withInviteScope(clinicDraft, 'ORGANIZATION'), 'CLINIC').clinicId,
    ).toBeNull();
    expect(withInviteScope(clinicDraft, 'CLINIC')).toBe(clinicDraft);
  });
  it('lists only the route Organization Clinics, in backend order', () => {
    const options = inviteClinicOptions(
      [clinic('a1', 'A'), clinic('b1', 'B'), clinic('a2', 'a')],
      'A',
    );
    expect(options).toEqual([
      { clinicId: 'a1', displayName: 'Clinic a1' },
      { clinicId: 'a2', displayName: null },
    ]);
  });
  it('enables sending only when the chosen scope is complete', () => {
    const clinics = [{ clinicId: 'a1', displayName: null }];
    const base = { ...EMPTY_STAFF_INVITE_DRAFT, email: 'x@example.test' };
    expect(canSendInvite(base, clinics, false)).toBe(false);
    expect(canSendInvite({ ...base, role: 'ADMINISTRATOR' }, clinics, false)).toBe(true);
    expect(canSendInvite({ ...base, role: 'ADMINISTRATOR', email: '   ' }, clinics, false)).toBe(
      false,
    );
    expect(canSendInvite({ ...base, role: 'ADMINISTRATOR' }, clinics, true)).toBe(false);
    const clinicScoped = { ...base, role: 'RECEPTIONIST' as const, scope: 'CLINIC' as const };
    expect(canSendInvite(clinicScoped, clinics, false)).toBe(false);
    expect(canSendInvite({ ...clinicScoped, clinicId: 'b1' }, clinics, false)).toBe(false);
    expect(canSendInvite({ ...clinicScoped, clinicId: 'a1' }, clinics, false)).toBe(true);
    // Address validity is left to the backend.
    expect(
      canSendInvite({ ...base, role: 'ADMINISTRATOR', email: 'not-an-email' }, clinics, false),
    ).toBe(true);
  });
  it('builds the request only from complete drafts and never a stale Clinic', () => {
    expect(inviteInputFrom('A', EMPTY_STAFF_INVITE_DRAFT)).toBeNull();
    expect(
      inviteInputFrom('A', {
        email: 'x',
        role: 'ADMINISTRATOR',
        scope: 'ORGANIZATION',
        clinicId: 'a1',
      }),
    ).toEqual({
      organizationId: 'A',
      recipientEmail: 'x',
      role: 'ADMINISTRATOR',
      scope: 'ORGANIZATION',
      clinicId: null,
    });
    expect(
      inviteInputFrom('A', { email: 'x', role: 'ADMINISTRATOR', scope: 'CLINIC', clinicId: null }),
    ).toBeNull();
  });
});

describe('lost-response invite reconciliation', () => {
  const before = new Set(['old']);
  it('proves success only with a new exactly matching pending Invitation', () => {
    expect(normalizedInvitationEmail(input.recipientEmail)).toBe('laura@example.test');
    expect(
      reconcileLostInvite(staff(pending('new', 'laura@example.test', clinicAdmin)), input, before),
    ).toBe('created');
  });
  it('never mistakes an older or different Invitation for this request', () => {
    expect(
      reconcileLostInvite(staff(pending('old', 'laura@example.test', clinicAdmin)), input, before),
    ).toBe('pendingExists');
    const differentRole = [{ ...clinicAdmin[0], responsibility: 'RECEPTIONIST' as const }];
    const differentClinic = [
      {
        ...clinicAdmin[0],
        scope: { type: 'CLINIC' as const, clinic: { clinicId: 'a2', displayName: null } },
      },
    ];
    const organizationScope = [
      { responsibility: 'ADMINISTRATOR' as const, scope: { type: 'ORGANIZATION' as const } },
    ];
    for (const responsibilities of [
      differentRole,
      differentClinic,
      organizationScope,
      [...clinicAdmin, ...organizationScope],
    ]) {
      expect(
        reconcileLostInvite(
          staff(pending('new', 'laura@example.test', responsibilities)),
          input,
          before,
        ),
      ).toBe('unconfirmed');
    }
    expect(
      reconcileLostInvite(staff(pending('new', 'other@example.test', clinicAdmin)), input, before),
    ).toBe('unconfirmed');
    expect(reconcileLostInvite(staff(), input, before)).toBe('unconfirmed');
  });
  it('reports access, authentication and unreadable re-reads without guessing', () => {
    expect(reconcileLostInvite({ data: null, error: STAFF_ACCESS_DENIED }, input, before)).toBe(
      'accessLost',
    );
    expect(
      reconcileLostInvite({ data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED }, input, before),
    ).toBe('authenticationRequired');
    expect(reconcileLostInvite({ data: null, error: 'offline' }, input, before)).toBe(
      'unconfirmed',
    );
  });
  it('maps every definite rejection to calm copy', () => {
    expect(inviteRejectionKey('PENDING_INVITATION_EXISTS')).toBe('staffInvite.pendingExists');
    expect(inviteRejectionKey('ACTIVE_MEMBER')).toBe('staffInvite.activeMember');
    expect(inviteRejectionKey('ACCOUNT_VERIFICATION_REQUIRED')).toBe(
      'staffInvite.verificationRequired',
    );
    expect(inviteRejectionKey('INVALID_CLINIC')).toBe('staffInvite.invalidClinic');
    expect(inviteRejectionKey('AUTHENTICATION_REQUIRED')).toBe('errors.sessionExpired');
  });
});

describe('revocation notice', () => {
  it.each([
    ['REVOKED', 'staff.revoked'],
    ['ALREADY_REVOKED', 'staff.revoked'],
    ['ACCEPTED', 'staff.revokeAccepted'],
    ['EXPIRED', 'staff.revokeExpired'],
    ['REJECTED', 'staff.revokeRejected'],
  ] as const)('reports %s calmly', (outcome, messageKey) => {
    expect(revocationNotice({ kind: 'outcome', outcome }, null)).toEqual({
      tone: 'info',
      messageKey,
    });
  });
  it('after an uncertain attempt says "no longer pending", never "revoked"', () => {
    expect(revocationNotice({ kind: 'uncertain' }, 'notPending')).toEqual({
      tone: 'info',
      messageKey: 'staff.revokeNoLongerPending',
    });
    expect(revocationNotice({ kind: 'uncertain' }, 'pending')).toEqual({
      tone: 'error',
      messageKey: 'staff.revokeFailed',
    });
    expect(revocationNotice({ kind: 'uncertain' }, 'error')).toEqual({
      tone: 'error',
      messageKey: 'staff.revokeFailed',
    });
    expect(revocationNotice({ kind: 'uncertain' }, null)).toEqual({
      tone: 'error',
      messageKey: 'staff.revokeFailed',
    });
  });
  it('treats denial or a denied re-read as lost Staff access', () => {
    expect(revocationNotice({ kind: 'accessDenied' }, null)).toBe('accessLost');
    expect(revocationNotice({ kind: 'outcome', outcome: 'REVOKED' }, 'unavailable')).toBe(
      'accessLost',
    );
  });
  it('collects the pending set used as the reconciliation baseline', () => {
    const read = staff(pending('a', 'a@x', []), pending('b', 'b@x', []));
    expect(read.error === null ? [...pendingInvitationIds(read.data)] : null).toEqual(['a', 'b']);
  });
});

describe('End access (SPEC-ORG-004 §10)', () => {
  const member = (overrides: Partial<StaffMember>): StaffMember => ({
    membershipId: 'm1',
    effectiveStart: '2020-01-01T00:00:00Z',
    isSelf: false,
    displayName: 'Ana',
    invitationRecipientEmail: null,
    responsibilities: [
      {
        responsibilityGrantId: 'g-325',
        responsibility: 'RECEPTIONIST',
        scope: { type: 'ORGANIZATION' },
      },
    ],
    ...overrides,
  });
  const loaded = (memberIds: string[]): StaffReread => ({
    kind: 'loaded',
    staff: {
      organizationId: 'A',
      organizationDisplayName: 'A',
      members: memberIds.map((membershipId) => member({ membershipId })),
      pendingInvitations: [],
    },
  });

  it('is a target only for another member without an active OWNER responsibility', () => {
    expect(isEndAccessTarget(member({}))).toBe(true);
    expect(isEndAccessTarget(member({ isSelf: true }))).toBe(false);
    expect(
      isEndAccessTarget(
        member({
          responsibilities: [
            {
              responsibilityGrantId: 'g-345',
              responsibility: 'RECEPTIONIST',
              scope: { type: 'ORGANIZATION' },
            },
            {
              responsibilityGrantId: 'g-346',
              responsibility: 'OWNER',
              scope: { type: 'ORGANIZATION' },
            },
          ],
        }),
      ),
    ).toBe(false);
  });

  it('reports ENDED and ALREADY_ENDED as the same success', () => {
    for (const outcome of ['ENDED', 'ALREADY_ENDED'] as const) {
      expect(
        endAccessNotice(
          { kind: 'outcome', outcome, effectiveEnd: '2030-01-01T00:00:00Z' },
          loaded([]),
          'm1',
        ),
      ).toEqual({ tone: 'info', messageKey: 'staff.endAccessDone' });
    }
  });

  it('keeps a backend-confirmed outcome as success even when the re-read fails', () => {
    for (const outcome of ['ENDED', 'ALREADY_ENDED'] as const) {
      expect(
        endAccessNotice(
          { kind: 'outcome', outcome, effectiveEnd: '2030-01-01T00:00:00Z' },
          { kind: 'error' },
          'm1',
        ),
      ).toEqual({ tone: 'info', messageKey: 'staff.endAccessDone' });
    }
  });

  it('reconciles a lost response only through the re-read', () => {
    expect(endAccessNotice({ kind: 'uncertain' }, loaded([]), 'm1')).toEqual({
      tone: 'info',
      messageKey: 'staff.endAccessDone',
    });
    expect(endAccessNotice({ kind: 'uncertain' }, loaded(['m1']), 'm1')).toEqual({
      tone: 'error',
      messageKey: 'staff.endAccessFailed',
    });
    expect(endAccessNotice({ kind: 'uncertain' }, { kind: 'error' }, 'm1')).toEqual({
      tone: 'error',
      messageKey: 'staff.endAccessFailed',
    });
    expect(endAccessNotice({ kind: 'uncertain' }, null, 'm1')).toEqual({
      tone: 'error',
      messageKey: 'staff.endAccessFailed',
    });
  });

  it('leaves on lost access and explains protected targets and expired sessions', () => {
    expect(endAccessNotice({ kind: 'accessDenied' }, loaded(['m1']), 'm1')).toBe('accessLost');
    expect(endAccessNotice({ kind: 'uncertain' }, { kind: 'unavailable' }, 'm1')).toBe(
      'accessLost',
    );
    expect(endAccessNotice({ kind: 'protected' }, loaded(['m1']), 'm1')).toEqual({
      tone: 'error',
      messageKey: 'staff.endAccessNotAllowed',
    });
    expect(endAccessNotice({ kind: 'authenticationRequired' }, loaded(['m1']), 'm1')).toEqual({
      tone: 'error',
      messageKey: 'errors.sessionExpired',
    });
  });
});

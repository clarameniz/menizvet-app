import type {
  OrganizationStaff,
  StaffMember,
  StaffResponsibility,
} from '@/data/organization-staff';
import type { VeterinarianWorkforce, WorkforceMember } from '@/data/staff-workforce';
import {
  assignableClinics,
  assignmentNotice,
  canSubmitResponsibility,
  clinicChoices,
  draftFromGrant,
  EMPTY_RESPONSIBILITY_DRAFT,
  initialAddDraft,
  parseClinicRole,
  responsibilityGroups,
  responsibilityInputFrom,
  responsibilityNotice,
  responsibilityPolicy,
  staffClinicAssignmentHref,
  staffMemberHref,
  staffResponsibilityEditorHref,
  veterinarianSection,
  withDraftRole,
  withDraftScope,
  type MemberNotice,
  type MemberReread,
} from '@/lib/staff-member-detail';
import { NO_STAFF_ACTIONS, type StaffActions } from '@/lib/staff-invitation';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const key = (notice: MemberNotice | 'accessLost') =>
  notice === 'accessLost' ? notice : notice.messageKey;
const MANAGER: StaffActions = {
  ...NO_STAFF_ACTIONS,
  manage: true,
  manageAssignments: true,
  endAccess: true,
};
const grant = (
  id: string,
  responsibility: StaffResponsibility['responsibility'],
  clinicId: string | null = null,
): StaffResponsibility => ({
  responsibilityGrantId: id,
  responsibility,
  scope:
    clinicId === null
      ? { type: 'ORGANIZATION' }
      : { type: 'CLINIC', clinic: { clinicId, displayName: `Clinic ${clinicId}` } },
});
const member = (overrides: Partial<StaffMember> = {}): StaffMember => ({
  membershipId: 'm1',
  effectiveStart: '2020-01-01T00:00:00Z',
  isSelf: false,
  displayName: 'Laura',
  invitationRecipientEmail: null,
  responsibilities: [grant('g-recep', 'RECEPTIONIST', 'c1'), grant('g-vet', 'VETERINARIAN')],
  ...overrides,
});
const CLINICS = [
  { clinicId: 'c1', displayName: 'Centro' },
  { clinicId: 'c2', displayName: 'Getafe' },
];
const staffWith = (members: StaffMember[]): OrganizationStaff => ({
  organizationId: 'A',
  organizationDisplayName: 'Org A',
  members,
  pendingInvitations: [],
});
const workforce = (members: WorkforceMember[]): VeterinarianWorkforce => ({
  organizationId: 'A',
  members,
});
const loaded = (
  members: StaffMember[],
  workforceMembers: WorkforceMember[] = [],
): MemberReread => ({
  kind: 'loaded',
  staff: staffWith(members),
  workforce: workforce(workforceMembers),
});

describe('routes', () => {
  it('carry the Organization and Membership explicitly', () => {
    expect(staffMemberHref('A', 'm1')).toEqual({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]',
      params: { organizationId: 'A', membershipId: 'm1' },
    });
    expect(staffResponsibilityEditorHref('A', 'm1', null)).toEqual({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/responsibility',
      params: { organizationId: 'A', membershipId: 'm1' },
    });
    expect(staffResponsibilityEditorHref('A', 'm1', 'g1')).toMatchObject({
      params: { grantId: 'g1' },
    });
    expect(staffClinicAssignmentHref('A', 'm1')).toMatchObject({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/assign-clinic',
    });
  });
});

describe('responsibility policy (SPEC-ORG-006 BR-50–BR-52)', () => {
  it('lets an administrator manage every Grant of an ordinary Member', () => {
    const policy = responsibilityPolicy(member(), MANAGER);
    expect(policy.canAdd).toBe(true);
    expect(member().responsibilities.every((g) => policy.canChange(g) && policy.canEnd(g))).toBe(
      true,
    );
  });
  it('never offers Change/End on OWNER, nor anything on another actor’s Owner Membership', () => {
    const owner = member({
      responsibilities: [grant('g-owner', 'OWNER'), grant('g-vet', 'VETERINARIAN')],
    });
    const policy = responsibilityPolicy(owner, MANAGER);
    expect(policy.canAdd).toBe(false);
    expect(owner.responsibilities.some((g) => policy.canChange(g) || policy.canEnd(g))).toBe(false);
  });
  it('lets the Owner manage their own non-OWNER Grants and add to themselves', () => {
    const self = member({
      isSelf: true,
      responsibilities: [grant('g-owner', 'OWNER'), grant('g-vet', 'VETERINARIAN')],
    });
    const policy = responsibilityPolicy(self, MANAGER);
    expect(policy.canAdd).toBe(true);
    expect(policy.canChange(self.responsibilities[0])).toBe(false);
    expect(policy.canEnd(self.responsibilities[1])).toBe(true);
  });
  it('lets a non-Owner administrator add to themselves but never change or end their own Grants', () => {
    const self = member({ isSelf: true, responsibilities: [grant('g-admin', 'ADMINISTRATOR')] });
    const policy = responsibilityPolicy(self, MANAGER);
    expect(policy.canAdd).toBe(true);
    expect(
      policy.canChange(self.responsibilities[0]) || policy.canEnd(self.responsibilities[0]),
    ).toBe(false);
  });
  it('offers nothing without the advisory capability', () => {
    const policy = responsibilityPolicy(member(), NO_STAFF_ACTIONS);
    expect(policy.canAdd || policy.canEnd(member().responsibilities[0])).toBe(false);
  });
});

describe('Veterinarian section (SPEC-VET-006, SPEC-VET-004 BR-23)', () => {
  const assignment = (id: string, clinicId: string) => ({
    veterinarianClinicAssignmentId: id,
    clinic: { clinicId, displayName: `Clinic ${clinicId}` },
  });
  it('is hidden without VETERINARIAN or a current Assignment', () => {
    const plain = member({ responsibilities: [grant('g', 'RECEPTIONIST')] });
    expect(veterinarianSection(plain, null, MANAGER, CLINICS)).toEqual({ visible: false });
  });
  it('shows Profile pending and offers no Assign without a Profile', () => {
    expect(
      veterinarianSection(
        member(),
        { membershipId: 'm1', hasVeterinarianProfessionalProfile: false, clinicAssignments: [] },
        MANAGER,
        CLINICS,
      ),
    ).toMatchObject({ visible: true, profile: 'pending', canAssign: false });
  });
  it('a Profile without any Clinic Assignment is completed and assignable', () => {
    expect(
      veterinarianSection(
        member(),
        { membershipId: 'm1', hasVeterinarianProfessionalProfile: true, clinicAssignments: [] },
        MANAGER,
        CLINICS,
      ),
    ).toMatchObject({
      visible: true,
      profile: 'completed',
      assignments: [],
      canAssign: true,
    });
  });
  it('shows a pending Profile only for a current VETERINARIAN, whatever the actor may manage', () => {
    const entry = {
      membershipId: 'm1',
      hasVeterinarianProfessionalProfile: false,
      clinicAssignments: [],
    };
    expect(
      veterinarianSection(member(), entry, { ...MANAGER, manageAssignments: false }, CLINICS),
    ).toMatchObject({ profile: 'pending', canAssign: false });
    const plain = member({ responsibilities: [grant('g', 'RECEPTIONIST')] });
    expect(veterinarianSection(plain, entry, MANAGER, CLINICS)).toEqual({ visible: false });
  });
  it('offers Assign with a Profile while an unassigned Clinic remains', () => {
    const entry = {
      membershipId: 'm1',
      hasVeterinarianProfessionalProfile: true,
      clinicAssignments: [assignment('a1', 'c1')],
    };
    expect(veterinarianSection(member(), entry, MANAGER, CLINICS)).toMatchObject({
      profile: 'completed',
      canAssign: true,
      canEndAssignments: true,
    });
    expect(assignableClinics(CLINICS, entry.clinicAssignments)).toEqual([CLINICS[1]]);
    const full = { ...entry, clinicAssignments: [assignment('a1', 'c1'), assignment('a2', 'c2')] };
    expect(veterinarianSection(member(), full, MANAGER, CLINICS)).toMatchObject({
      canAssign: false,
    });
  });
  it('keeps a stale Assignment endable after VETERINARIAN ended, without offering Assign', () => {
    const stale = member({ responsibilities: [grant('g', 'RECEPTIONIST')] });
    const entry = {
      membershipId: 'm1',
      hasVeterinarianProfessionalProfile: true,
      clinicAssignments: [assignment('a1', 'c1')],
    };
    expect(veterinarianSection(stale, entry, MANAGER, CLINICS)).toMatchObject({
      visible: true,
      canAssign: false,
      canEndAssignments: true,
    });
  });
});

describe('responsibility groups (person → responsibility → Clinics)', () => {
  const entry = (profile: boolean, clinicIds: string[] = []): WorkforceMember => ({
    membershipId: 'm1',
    hasVeterinarianProfessionalProfile: profile,
    clinicAssignments: clinicIds.map((clinicId) => ({
      veterinarianClinicAssignmentId: `a-${clinicId}`,
      clinic: { clinicId, displayName: `Clinic ${clinicId}` },
    })),
  });
  const ids = (groups: ReturnType<typeof responsibilityGroups>) =>
    groups.flatMap((group) =>
      group.role === 'OWNER'
        ? group.grants.map((g) => g.responsibilityGrantId)
        : group.role === 'VETERINARIAN'
          ? group.grant === null
            ? []
            : [group.grant.grant.responsibilityGrantId]
          : [
              ...(group.organizationGrant === null
                ? []
                : [group.organizationGrant.grant.responsibilityGrantId]),
              ...group.clinicGrants.map((row) => row.grant.responsibilityGrantId),
            ],
    );

  it('orders Owner, Veterinarian, Reception, Administration and shows every Grant exactly once', () => {
    const m = member({
      responsibilities: [
        grant('g-admin', 'ADMINISTRATOR', 'c2'),
        grant('g-r-org', 'RECEPTIONIST'),
        grant('g-r-c1', 'RECEPTIONIST', 'c1'),
        grant('g-vet', 'VETERINARIAN'),
        grant('g-owner', 'OWNER'),
      ],
      isSelf: true,
    });
    const groups = responsibilityGroups(m, entry(true), MANAGER, CLINICS);
    expect(groups.map((group) => group.role)).toEqual([
      'OWNER',
      'VETERINARIAN',
      'RECEPTIONIST',
      'ADMINISTRATOR',
    ]);
    expect(ids(groups).sort()).toEqual(
      m.responsibilities.map((g) => g.responsibilityGrantId).sort(),
    );
  });
  it('marks an Organization Grant beside Clinic Grants as redundant, hiding none, and offers no add', () => {
    const m = member({
      responsibilities: [grant('g-org', 'RECEPTIONIST'), grant('g-c1', 'RECEPTIONIST', 'c1')],
    });
    expect(responsibilityGroups(m, null, MANAGER, CLINICS)).toEqual([
      expect.objectContaining({
        role: 'RECEPTIONIST',
        organizationGrant: expect.objectContaining({ canChange: true, canEnd: true }),
        clinicGrants: [expect.objectContaining({ canChange: true, canEnd: true })],
        redundant: true,
        canAddClinic: false,
      }),
    ]);
  });
  it('offers one more Clinic only while an uncovered Clinic remains and Grants may be added', () => {
    const one = member({ responsibilities: [grant('g-c1', 'RECEPTIONIST', 'c1')] });
    expect(responsibilityGroups(one, null, MANAGER, CLINICS)[0]).toMatchObject({
      canAddClinic: true,
      redundant: false,
    });
    const both = member({
      responsibilities: [grant('g-c1', 'RECEPTIONIST', 'c1'), grant('g-c2', 'RECEPTIONIST', 'c2')],
    });
    expect(responsibilityGroups(both, null, MANAGER, CLINICS)[0]).toMatchObject({
      canAddClinic: false,
    });
    expect(responsibilityGroups(one, null, NO_STAFF_ACTIONS, CLINICS)[0]).toMatchObject({
      canAddClinic: false,
      clinicGrants: [expect.objectContaining({ canChange: false, canEnd: false })],
    });
  });
  it('joins the VETERINARIAN Grant with Profile and Assignments, or keeps a stale Assignment alone', () => {
    const vet = responsibilityGroups(member(), entry(true, ['c1']), MANAGER, CLINICS).find(
      (group) => group.role === 'VETERINARIAN',
    );
    expect(vet).toMatchObject({
      grant: { grant: { responsibilityGrantId: 'g-vet' }, canEnd: true },
      section: { profile: 'completed', assignments: [{ veterinarianClinicAssignmentId: 'a-c1' }] },
    });
    const stale = member({ responsibilities: [grant('g-recep', 'RECEPTIONIST', 'c1')] });
    expect(
      responsibilityGroups(stale, entry(true, ['c2']), MANAGER, CLINICS).find(
        (group) => group.role === 'VETERINARIAN',
      ),
    ).toMatchObject({ grant: null, section: { canAssign: false, canEndAssignments: true } });
  });
  it('keeps another actor’s Owner Membership read-only in every group', () => {
    const owner = member({
      responsibilities: [grant('g-owner', 'OWNER'), grant('g-recep', 'RECEPTIONIST', 'c1')],
    });
    expect(responsibilityGroups(owner, null, MANAGER, CLINICS)).toEqual([
      { role: 'OWNER', grants: [owner.responsibilities[0]] },
      expect.objectContaining({
        role: 'RECEPTIONIST',
        clinicGrants: [expect.objectContaining({ canChange: false, canEnd: false })],
        canAddClinic: false,
      }),
    ]);
  });
});

describe('add-Clinic preset and Clinic choices', () => {
  it('accepts only Administrator or Receptionist as a Clinic preset', () => {
    expect(parseClinicRole('RECEPTIONIST')).toBe('RECEPTIONIST');
    expect(parseClinicRole('ADMINISTRATOR')).toBe('ADMINISTRATOR');
    for (const value of ['VETERINARIAN', 'OWNER', ['RECEPTIONIST'], undefined])
      expect(parseClinicRole(value)).toBeNull();
    expect(initialAddDraft('RECEPTIONIST')).toEqual({
      role: 'RECEPTIONIST',
      scope: 'CLINIC',
      clinicId: null,
    });
    expect(initialAddDraft(null)).toBe(EMPTY_RESPONSIBILITY_DRAFT);
    expect(staffResponsibilityEditorHref('A', 'm1', null, 'RECEPTIONIST')).toEqual({
      pathname: '/professional/organizations/[organizationId]/staff/[membershipId]/responsibility',
      params: { organizationId: 'A', membershipId: 'm1', clinicRole: 'RECEPTIONIST' },
    });
  });
  it('omits Clinics already held for the role, except the Grant being changed', () => {
    const m = member();
    expect(clinicChoices('RECEPTIONIST', m, CLINICS, null)).toEqual([CLINICS[1]]);
    expect(clinicChoices('ADMINISTRATOR', m, CLINICS, null)).toEqual(CLINICS);
    expect(clinicChoices('RECEPTIONIST', m, CLINICS, m.responsibilities[0])).toEqual(CLINICS);
    expect(clinicChoices(null, m, CLINICS, null)).toEqual(CLINICS);
  });
});

describe('editor draft (SPEC-ORG-006 BR-49)', () => {
  it('fixes VETERINARIAN to the Organization and drops a Clinic', () => {
    const clinicDraft = { role: 'RECEPTIONIST' as const, scope: 'CLINIC' as const, clinicId: 'c1' };
    expect(withDraftRole(clinicDraft, 'VETERINARIAN')).toEqual({
      role: 'VETERINARIAN',
      scope: 'ORGANIZATION',
      clinicId: null,
    });
    expect(withDraftScope(withDraftRole(clinicDraft, 'VETERINARIAN'), 'CLINIC').scope).toBe(
      'ORGANIZATION',
    );
    expect(withDraftScope(clinicDraft, 'ORGANIZATION')).toEqual({
      role: 'RECEPTIONIST',
      scope: 'ORGANIZATION',
      clinicId: null,
    });
  });
  it('starts a Change from the named Grant and never drafts OWNER', () => {
    expect(draftFromGrant(grant('g', 'RECEPTIONIST', 'c1'))).toEqual({
      role: 'RECEPTIONIST',
      scope: 'CLINIC',
      clinicId: 'c1',
    });
    expect(draftFromGrant(grant('g', 'OWNER')).role).toBeNull();
  });
  it('requires completeness, a route Clinic, and a Responsibility the Member does not hold', () => {
    const m = member();
    expect(canSubmitResponsibility(EMPTY_RESPONSIBILITY_DRAFT, m, CLINICS, false)).toBe(false);
    expect(
      canSubmitResponsibility(
        { role: 'ADMINISTRATOR', scope: 'CLINIC', clinicId: null },
        m,
        CLINICS,
        false,
      ),
    ).toBe(false);
    expect(
      canSubmitResponsibility(
        { role: 'ADMINISTRATOR', scope: 'CLINIC', clinicId: 'zz' },
        m,
        CLINICS,
        false,
      ),
    ).toBe(false);
    expect(
      canSubmitResponsibility(
        { role: 'RECEPTIONIST', scope: 'CLINIC', clinicId: 'c1' },
        m,
        CLINICS,
        false,
      ),
    ).toBe(false);
    expect(
      canSubmitResponsibility(
        { role: 'VETERINARIAN', scope: 'ORGANIZATION', clinicId: null },
        m,
        CLINICS,
        false,
      ),
    ).toBe(false);
    expect(
      canSubmitResponsibility(
        { role: 'RECEPTIONIST', scope: 'CLINIC', clinicId: 'c2' },
        m,
        CLINICS,
        false,
      ),
    ).toBe(true);
    expect(
      canSubmitResponsibility(
        { role: 'RECEPTIONIST', scope: 'CLINIC', clinicId: 'c2' },
        m,
        CLINICS,
        true,
      ),
    ).toBe(false);
    expect(
      responsibilityInputFrom({ role: 'VETERINARIAN', scope: 'CLINIC', clinicId: 'c1' }),
    ).toEqual({
      role: 'VETERINARIAN',
      scope: 'ORGANIZATION',
      clinicId: null,
    });
  });
});

describe('Responsibility outcomes and lost responses (BR-56)', () => {
  const input = { role: 'ADMINISTRATOR' as const, scope: 'ORGANIZATION' as const, clinicId: null };
  it('reports outcomes, guidance for the last Grant and active Assignments, and loss of access', () => {
    expect(
      responsibilityNotice(
        { kind: 'outcome', outcome: 'ALREADY_ENDED', responsibilityGrantId: 'g' },
        null,
        { kind: 'end', membershipId: 'm1', grantId: 'g' },
      ),
    ).toEqual({ tone: 'info', messageKey: 'staffMember.ended' });
    expect(
      responsibilityNotice({ kind: 'rejected', reason: 'LAST_RESPONSIBILITY' }, null, {
        kind: 'end',
        membershipId: 'm1',
        grantId: 'g',
      }),
    ).toEqual({
      tone: 'error',
      messageKey: 'staffMember.lastResponsibility',
      guidance: 'endAccess',
    });
    expect(
      responsibilityNotice({ kind: 'rejected', reason: 'VETERINARIAN_ASSIGNMENTS_ACTIVE' }, null, {
        kind: 'end',
        membershipId: 'm1',
        grantId: 'g-vet',
      }),
    ).toMatchObject({
      guidance: 'veterinarianSection',
    });
    expect(
      responsibilityNotice({ kind: 'accessDenied' }, null, {
        kind: 'add',
        membershipId: 'm1',
        input,
      }),
    ).toBe('accessLost');
    expect(
      responsibilityNotice(
        { kind: 'uncertain' },
        { kind: 'unavailable' },
        { kind: 'add', membershipId: 'm1', input },
      ),
    ).toBe('accessLost');
  });
  it('proves a lost Add, Change, or End only from the re-read', () => {
    const before = member();
    const added = member({
      responsibilities: [...before.responsibilities, grant('g-new', 'ADMINISTRATOR')],
    });
    expect(
      key(
        responsibilityNotice({ kind: 'uncertain' }, loaded([added]), {
          kind: 'add',
          membershipId: 'm1',
          input,
        }),
      ),
    ).toBe('staffMember.added');
    expect(
      key(
        responsibilityNotice({ kind: 'uncertain' }, loaded([before]), {
          kind: 'add',
          membershipId: 'm1',
          input,
        }),
      ),
    ).toBe('staffMember.unconfirmed');
    const changed = member({
      responsibilities: [grant('g-new', 'ADMINISTRATOR'), grant('g-vet', 'VETERINARIAN')],
    });
    const change = { kind: 'change' as const, membershipId: 'm1', grantId: 'g-recep', input };
    expect(key(responsibilityNotice({ kind: 'uncertain' }, loaded([changed]), change))).toBe(
      'staffMember.changed',
    );
    expect(key(responsibilityNotice({ kind: 'uncertain' }, loaded([before]), change))).toBe(
      'staffMember.unconfirmed',
    );
    const ended = member({ responsibilities: [grant('g-vet', 'VETERINARIAN')] });
    const end = { kind: 'end' as const, membershipId: 'm1', grantId: 'g-recep' };
    expect(key(responsibilityNotice({ kind: 'uncertain' }, loaded([ended]), end))).toBe(
      'staffMember.ended',
    );
    expect(key(responsibilityNotice({ kind: 'uncertain' }, loaded([]), end))).toBe(
      'staffMember.unconfirmed',
    );
    expect(key(responsibilityNotice({ kind: 'uncertain' }, { kind: 'error' }, end))).toBe(
      'staffMember.unconfirmed',
    );
  });
});

describe('Assignment outcomes (SPEC-VET-004/005 §13)', () => {
  const entry = (clinicIds: string[]): WorkforceMember => ({
    membershipId: 'm1',
    hasVeterinarianProfessionalProfile: true,
    clinicAssignments: clinicIds.map((clinicId) => ({
      veterinarianClinicAssignmentId: `a-${clinicId}`,
      clinic: { clinicId, displayName: null },
    })),
  });
  it('maps rejections and proves lost responses from the workforce re-read', () => {
    expect(
      key(
        assignmentNotice({ kind: 'rejected', reason: 'PROFILE_REQUIRED' }, null, {
          kind: 'assign',
          membershipId: 'm1',
          clinicId: 'c1',
        }),
      ),
    ).toBe('staffAssignment.profileRequired');
    expect(
      key(
        assignmentNotice({ kind: 'uncertain' }, loaded([member()], [entry(['c1'])]), {
          kind: 'assign',
          membershipId: 'm1',
          clinicId: 'c1',
        }),
      ),
    ).toBe('staffAssignment.assigned');
    expect(
      key(
        assignmentNotice({ kind: 'uncertain' }, loaded([member()], [entry([])]), {
          kind: 'assign',
          membershipId: 'm1',
          clinicId: 'c1',
        }),
      ),
    ).toBe('staffAssignment.unconfirmed');
    expect(
      key(
        assignmentNotice({ kind: 'uncertain' }, loaded([member()], [entry([])]), {
          kind: 'end',
          membershipId: 'm1',
          assignmentId: 'a-c1',
        }),
      ),
    ).toBe('staffAssignment.ended');
    expect(
      key(
        assignmentNotice({ kind: 'uncertain' }, loaded([member()], [entry(['c1'])]), {
          kind: 'end',
          membershipId: 'm1',
          assignmentId: 'a-c1',
        }),
      ),
    ).toBe('staffAssignment.unconfirmed');
    expect(
      assignmentNotice({ kind: 'accessDenied' }, null, {
        kind: 'end',
        membershipId: 'm1',
        assignmentId: 'a-c1',
      }),
    ).toBe('accessLost');
  });
});

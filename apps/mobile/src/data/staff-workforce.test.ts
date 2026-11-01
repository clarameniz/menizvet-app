import { STAFF_ACCESS_DENIED } from '@/data/organization-staff';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import {
  addStaffResponsibility,
  assignStaffVeterinarianToClinic,
  endStaffResponsibility,
  endStaffVeterinarianClinicAssignment,
  getOrganizationVeterinarianWorkforce,
  parseVeterinarianWorkforce,
  replaceStaffResponsibility,
  WORKFORCE_MALFORMED,
} from '@/data/staff-workforce';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;
const ORG = 'd0330000-0000-4000-8000-000000003001';
const OTHER = 'd0330000-0000-4000-8000-000000003002';
const MEMBER = 'd0330000-0000-4000-8000-000000005007';
const GRANT = 'd0330000-0000-4000-8000-000000006007';
const NEW_GRANT = 'd0330000-0000-4000-8000-000000006099';
const CLINIC = 'd0330000-0000-4000-8000-000000004001';
const ASSIGNMENT = 'd0330000-0000-4000-8000-000000008005';
const ADMIN_ORG = { role: 'ADMINISTRATOR', scope: 'ORGANIZATION', clinicId: null } as const;

beforeEach(() => rpc.mockReset());

describe('Responsibility operations (SPEC-ORG-006 §14)', () => {
  it('Add names the Organization and Membership and sends one role and scope', async () => {
    rpc.mockResolvedValue({
      data: { outcome: 'ADDED', membership_id: MEMBER, responsibility_grant_id: NEW_GRANT },
      error: null,
    });
    await expect(
      addStaffResponsibility(ORG, MEMBER, {
        role: 'ADMINISTRATOR',
        scope: 'CLINIC',
        clinicId: CLINIC,
      }),
    ).resolves.toEqual({ kind: 'outcome', outcome: 'ADDED', responsibilityGrantId: NEW_GRANT });
    expect(rpc).toHaveBeenCalledWith('add_staff_responsibility', {
      p_organization_id: ORG,
      p_membership_id: MEMBER,
      p_responsibility: 'ADMINISTRATOR',
      p_scope_type: 'CLINIC',
      p_clinic_id: CLINIC,
    });
  });
  it('never sends a Clinic for Organization scope', async () => {
    rpc.mockResolvedValue({ data: null, error: null });
    await addStaffResponsibility(ORG, MEMBER, {
      role: 'VETERINARIAN',
      scope: 'ORGANIZATION',
      clinicId: CLINIC,
    });
    expect(rpc.mock.calls[0][1].p_clinic_id).toBeNull();
  });
  it('Change names exactly one Grant; End names exactly one Grant', async () => {
    rpc.mockResolvedValue({
      data: { outcome: 'REPLACED', membership_id: MEMBER, responsibility_grant_id: NEW_GRANT },
      error: null,
    });
    await expect(replaceStaffResponsibility(ORG, GRANT, ADMIN_ORG)).resolves.toMatchObject({
      outcome: 'REPLACED',
    });
    expect(rpc).toHaveBeenCalledWith('replace_staff_responsibility', {
      p_organization_id: ORG,
      p_responsibility_grant_id: GRANT,
      p_responsibility: 'ADMINISTRATOR',
      p_scope_type: 'ORGANIZATION',
      p_clinic_id: null,
    });
    rpc.mockResolvedValue({
      data: { outcome: 'ALREADY_ENDED', membership_id: MEMBER, responsibility_grant_id: GRANT },
      error: null,
    });
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({
      kind: 'outcome',
      outcome: 'ALREADY_ENDED',
      responsibilityGrantId: GRANT,
    });
    expect(rpc).toHaveBeenLastCalledWith('end_staff_responsibility', {
      p_organization_id: ORG,
      p_responsibility_grant_id: GRANT,
    });
  });
  it.each([
    'OWNER_GRANT',
    'OWNER_MEMBERSHIP',
    'SELF_MEMBERSHIP',
    'LAST_RESPONSIBILITY',
    'VETERINARIAN_ASSIGNMENTS_ACTIVE',
    'GRANT_ENDED',
    'DUPLICATE',
    'NO_OP',
    'MEMBERSHIP_INACTIVE',
  ])('maps the stable hint %s to a calm rejection', async (hint) => {
    rpc.mockResolvedValue({ data: null, error: { code: '23514', hint, message: 'x' } });
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({
      kind: 'rejected',
      reason: hint,
    });
  });
  it('maps 42501 to loss of access, 28000 to authentication, and anything else to uncertain', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'unavailable' } });
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({ kind: 'accessDenied' });
    rpc.mockResolvedValue({ data: null, error: { code: '28000', message: 'auth' } });
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({
      kind: 'authenticationRequired',
    });
    rpc.mockResolvedValue({
      data: null,
      error: { code: '23514', hint: 'SOMETHING_NEW', message: 'x' },
    });
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({ kind: 'uncertain' });
    rpc.mockRejectedValue(new Error('offline'));
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({ kind: 'uncertain' });
  });
  it('treats a malformed or mismatched success as uncertain', async () => {
    rpc.mockResolvedValue({ data: { outcome: 'ADDED' }, error: null });
    await expect(addStaffResponsibility(ORG, MEMBER, ADMIN_ORG)).resolves.toEqual({
      kind: 'uncertain',
    });
    rpc.mockResolvedValue({
      data: { outcome: 'ADDED', membership_id: OTHER, responsibility_grant_id: NEW_GRANT },
      error: null,
    });
    await expect(addStaffResponsibility(ORG, MEMBER, ADMIN_ORG)).resolves.toEqual({
      kind: 'uncertain',
    });
    rpc.mockResolvedValue({
      data: { outcome: 'ENDED', membership_id: MEMBER, responsibility_grant_id: NEW_GRANT },
      error: null,
    });
    await expect(endStaffResponsibility(ORG, GRANT)).resolves.toEqual({ kind: 'uncertain' });
  });
  it('never calls the backend with a non-domain identifier', async () => {
    await expect(endStaffResponsibility('A', GRANT)).resolves.toEqual({ kind: 'accessDenied' });
    await expect(addStaffResponsibility(ORG, 'user-id', ADMIN_ORG)).resolves.toEqual({
      kind: 'accessDenied',
    });
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('workforce read (SPEC-VET-006)', () => {
  const payload = () => ({
    organization_id: ORG,
    members: [
      {
        membership_id: MEMBER,
        has_veterinarian_professional_profile: false,
        clinic_assignments: [],
      },
      {
        membership_id: 'd0330000-0000-4000-8000-000000005005',
        has_veterinarian_professional_profile: true,
        clinic_assignments: [
          {
            veterinarian_clinic_assignment_id: ASSIGNMENT,
            clinic: { clinic_id: CLINIC, clinic_display_name: null },
          },
        ],
      },
    ],
  });
  it('parses Profile existence and current Assignments only, keeping no unknown fields', () => {
    const raw = payload();
    Object.assign(raw.members[0], { registration_identifier: 'SECRET', user_id: 'hidden' });
    const workforce = parseVeterinarianWorkforce(raw, ORG)!;
    expect(workforce.members[0]).toEqual({
      membershipId: MEMBER,
      hasVeterinarianProfessionalProfile: false,
      clinicAssignments: [],
    });
    expect(workforce.members[1].clinicAssignments).toEqual([
      {
        veterinarianClinicAssignmentId: ASSIGNMENT,
        clinic: { clinicId: CLINIC, displayName: null },
      },
    ]);
    expect(JSON.stringify(workforce)).not.toContain('SECRET');
  });
  it('rejects another Organization and malformed entries as a whole', () => {
    expect(parseVeterinarianWorkforce(payload(), OTHER)).toBeNull();
    const raw = payload();
    (
      raw.members[1].clinic_assignments[0] as Record<string, unknown>
    ).veterinarian_clinic_assignment_id = 'x';
    expect(parseVeterinarianWorkforce(raw, ORG)).toBeNull();
    expect(parseVeterinarianWorkforce({ ...payload(), members: null }, ORG)).toBeNull();
  });
  it('reads with explicit Organization context and normalizes failures', async () => {
    rpc.mockResolvedValue({ data: payload(), error: null });
    expect((await getOrganizationVeterinarianWorkforce(ORG)).error).toBeNull();
    expect(rpc).toHaveBeenCalledWith('get_organization_veterinarian_workforce', {
      p_organization_id: ORG,
    });
    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'x' } });
    expect((await getOrganizationVeterinarianWorkforce(ORG)).error).toBe(STAFF_ACCESS_DENIED);
    rpc.mockResolvedValue({ data: null, error: { code: '28000', message: 'x' } });
    expect((await getOrganizationVeterinarianWorkforce(ORG)).error).toBe(
      PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    );
    rpc.mockResolvedValue({ data: { organization_id: OTHER, members: [] }, error: null });
    expect((await getOrganizationVeterinarianWorkforce(ORG)).error).toBe(WORKFORCE_MALFORMED);
  });
});

describe('Clinic Assignment (SPEC-VET-004/005 §13)', () => {
  it('assigns by Organization, Membership and Clinic — never a Profile id', async () => {
    rpc.mockResolvedValue({
      data: {
        outcome: 'ALREADY_ASSIGNED',
        veterinarian_clinic_assignment_id: ASSIGNMENT,
        membership_id: MEMBER,
        clinic_id: CLINIC,
        effective_start: '2030-01-01T00:00:00Z',
      },
      error: null,
    });
    await expect(assignStaffVeterinarianToClinic(ORG, MEMBER, CLINIC)).resolves.toEqual({
      kind: 'outcome',
      outcome: 'ALREADY_ASSIGNED',
      veterinarianClinicAssignmentId: ASSIGNMENT,
    });
    expect(rpc).toHaveBeenCalledWith('assign_staff_veterinarian_to_clinic', {
      p_organization_id: ORG,
      p_membership_id: MEMBER,
      p_clinic_id: CLINIC,
    });
    expect(Object.keys(rpc.mock.calls[0][1])).not.toContain('p_professional_profile_id');
  });
  it.each(['PROFILE_REQUIRED', 'VETERINARIAN_RESPONSIBILITY_REQUIRED', 'MEMBERSHIP_INACTIVE'])(
    'maps %s to a calm rejection',
    async (hint) => {
      rpc.mockResolvedValue({ data: null, error: { code: '23514', hint, message: 'x' } });
      await expect(assignStaffVeterinarianToClinic(ORG, MEMBER, CLINIC)).resolves.toEqual({
        kind: 'rejected',
        reason: hint,
      });
    },
  );
  it('ends by Organization, Clinic and Assignment; a mismatched result is uncertain', async () => {
    rpc.mockResolvedValue({
      data: {
        outcome: 'ENDED',
        veterinarian_clinic_assignment_id: ASSIGNMENT,
        effective_end: '2030-01-01T00:00:00Z',
      },
      error: null,
    });
    await expect(
      endStaffVeterinarianClinicAssignment(ORG, CLINIC, ASSIGNMENT),
    ).resolves.toMatchObject({
      outcome: 'ENDED',
    });
    expect(rpc).toHaveBeenCalledWith('end_staff_veterinarian_clinic_assignment', {
      p_organization_id: ORG,
      p_clinic_id: CLINIC,
      p_veterinarian_clinic_assignment_id: ASSIGNMENT,
    });
    rpc.mockResolvedValue({
      data: {
        outcome: 'ENDED',
        veterinarian_clinic_assignment_id: NEW_GRANT,
        effective_end: '2030-01-01T00:00:00Z',
      },
      error: null,
    });
    await expect(endStaffVeterinarianClinicAssignment(ORG, CLINIC, ASSIGNMENT)).resolves.toEqual({
      kind: 'uncertain',
    });
  });
});

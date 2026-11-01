import {
  assignAppointmentVeterinarian,
  assignMeToAppointment,
  getAppointmentVeterinarianAssignment,
  getAppointmentVeterinarianCandidates,
  parseAppointmentVeterinarianAssignment,
  parseAppointmentVeterinarianCandidates,
} from '@/data/appointment-veterinarian-assignment';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));
const rpc = supabase.rpc as jest.Mock;

const CLINIC = 'd0340000-0000-4000-8000-000000004001';
const APPOINTMENT = 'd0340000-0000-4000-8000-000000011001';
const TOKEN = 'd0340000-0000-4000-8000-000000030001';
const VCA = 'd0340000-0000-4000-8000-000000040001';
const OTHER_VCA = 'd0340000-0000-4000-8000-000000040002';

beforeEach(() => rpc.mockReset());

describe('parseAppointmentVeterinarianAssignment', () => {
  it('maps an unassigned Appointment with the advisory actions', () => {
    expect(
      parseAppointmentVeterinarianAssignment({
        status: 'UNASSIGNED',
        may_assign_me: true,
        may_manage: false,
      }),
    ).toEqual({ kind: 'unassigned', mayAssignMe: true, mayManage: false });
  });

  it('maps the assignee, a stale assignment and the opaque token', () => {
    expect(
      parseAppointmentVeterinarianAssignment({
        status: 'ASSIGNED',
        display_name: ' Ana García ',
        is_me: false,
        is_eligible: false,
        assignment_token: TOKEN,
        may_assign_me: true,
        may_manage: true,
      }),
    ).toEqual({
      kind: 'assigned',
      displayName: 'Ana García',
      isMe: false,
      isEligible: false,
      assignmentToken: TOKEN,
      mayAssignMe: true,
      mayManage: true,
    });
    expect(
      parseAppointmentVeterinarianAssignment({
        status: 'ASSIGNED',
        display_name: null,
        is_me: true,
        is_eligible: true,
        assignment_token: TOKEN,
        may_assign_me: false,
        may_manage: false,
      }),
    ).toMatchObject({ displayName: null, isMe: true });
  });

  it.each<[string, unknown]>([
    ['no object', null],
    ['an unknown status', { status: 'MAYBE', may_assign_me: false, may_manage: false }],
    ['missing flags', { status: 'UNASSIGNED' }],
    [
      'a malformed token',
      {
        status: 'ASSIGNED',
        display_name: 'Ana',
        is_me: false,
        is_eligible: true,
        assignment_token: 'token-1',
        may_assign_me: false,
        may_manage: false,
      },
    ],
  ])('rejects %s', (_label, raw) => {
    expect(parseAppointmentVeterinarianAssignment(raw)).toBeNull();
  });
});

describe('parseAppointmentVeterinarianCandidates', () => {
  it('maps the eligible candidates and ignores the history', () => {
    expect(
      parseAppointmentVeterinarianCandidates({
        status: 'PERMITTED',
        candidates: [
          {
            veterinarian_clinic_assignment_id: VCA,
            display_name: 'Ana García',
            is_me: false,
            is_current_assignee: true,
          },
          {
            veterinarian_clinic_assignment_id: OTHER_VCA,
            display_name: null,
            is_me: true,
            is_current_assignee: false,
          },
        ],
        history: [{ veterinarian_display_name: 'Ana García', assigned_at: 'x' }],
      }),
    ).toEqual({
      kind: 'permitted',
      candidates: [
        {
          veterinarianClinicAssignmentId: VCA,
          displayName: 'Ana García',
          isMe: false,
          isCurrentAssignee: true,
        },
        {
          veterinarianClinicAssignmentId: OTHER_VCA,
          displayName: null,
          isMe: true,
          isCurrentAssignee: false,
        },
      ],
    });
  });

  it('keeps DENIED typed, and rejects duplicates and malformed candidates', () => {
    expect(parseAppointmentVeterinarianCandidates({ status: 'DENIED' })).toEqual({
      kind: 'denied',
    });
    const candidate = {
      veterinarian_clinic_assignment_id: VCA,
      display_name: 'Ana',
      is_me: false,
      is_current_assignee: false,
    };
    expect(
      parseAppointmentVeterinarianCandidates({
        status: 'PERMITTED',
        candidates: [candidate, candidate],
      }),
    ).toBeNull();
    expect(
      parseAppointmentVeterinarianCandidates({
        status: 'PERMITTED',
        candidates: [{ ...candidate, is_me: 'no' }],
      }),
    ).toBeNull();
  });
});

describe('reads', () => {
  it('read the assignment by Clinic and Appointment only, and never write', async () => {
    rpc.mockResolvedValue({
      data: { status: 'UNASSIGNED', may_assign_me: true, may_manage: true },
      error: null,
    });
    expect(await getAppointmentVeterinarianAssignment(CLINIC, APPOINTMENT)).toEqual({
      kind: 'loaded',
      assignment: { kind: 'unassigned', mayAssignMe: true, mayManage: true },
    });
    expect(rpc).toHaveBeenCalledWith('get_appointment_veterinarian_assignment', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it('maps the uniform denial, authentication and failures', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    expect(await getAppointmentVeterinarianAssignment(CLINIC, APPOINTMENT)).toEqual({
      kind: 'unavailable',
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '28000' } });
    expect(await getAppointmentVeterinarianAssignment(CLINIC, APPOINTMENT)).toEqual({
      kind: 'authenticationRequired',
    });
    rpc.mockRejectedValueOnce(new Error('offline'));
    expect(await getAppointmentVeterinarianAssignment(CLINIC, APPOINTMENT)).toEqual({
      kind: 'failed',
    });
    rpc.mockResolvedValueOnce({ data: { status: 'DENIED' }, error: null });
    expect(await getAppointmentVeterinarianCandidates(CLINIC, APPOINTMENT)).toEqual({
      kind: 'denied',
    });
    expect(rpc).toHaveBeenLastCalledWith('get_appointment_veterinarian_candidates', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
    });
  });
});

describe('writes', () => {
  it('self-assignment sends only the Clinic and Appointment', async () => {
    rpc.mockResolvedValue({ data: { outcome: 'ASSIGNED', assignment_token: TOKEN }, error: null });
    expect(await assignMeToAppointment(CLINIC, APPOINTMENT)).toEqual({
      kind: 'outcome',
      outcome: 'ASSIGNED',
    });
    expect(rpc).toHaveBeenCalledWith('assign_me_to_appointment', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
    });
  });

  it('managed assignment sends the chosen Clinic Assignment and the reviewed token', async () => {
    rpc.mockResolvedValue({
      data: { outcome: 'REASSIGNED', assignment_token: TOKEN },
      error: null,
    });
    expect(await assignAppointmentVeterinarian(CLINIC, APPOINTMENT, VCA, TOKEN)).toEqual({
      kind: 'outcome',
      outcome: 'REASSIGNED',
    });
    expect(rpc).toHaveBeenCalledWith('assign_appointment_veterinarian', {
      p_clinic_id: CLINIC,
      p_appointment_id: APPOINTMENT,
      p_veterinarian_clinic_assignment_id: VCA,
      p_expected_assignment_token: TOKEN,
    });
  });

  it.each([
    ['P0001', 'STALE_ASSIGNMENT'],
    ['23514', 'ASSIGNED_TO_ANOTHER_VETERINARIAN'],
    ['23514', 'APPOINTMENT_STATE_INVALID'],
    ['23514', 'VETERINARIAN_NOT_ELIGIBLE'],
    ['23514', 'VETERINARIAN_SCHEDULE_CONFLICT'],
    ['22023', 'VETERINARIAN_REQUIRED'],
  ])('maps %s %s to a rejection', async (code, hint) => {
    rpc.mockResolvedValue({ data: null, error: { code, hint } });
    expect(await assignAppointmentVeterinarian(CLINIC, APPOINTMENT, VCA, null)).toEqual({
      kind: 'rejected',
      reason: hint,
    });
  });

  it('maps the scheduling Entitlement apart from the uniform denial, and lost answers as uncertain', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '42501', hint: 'SCHEDULING_SERVICE_UNAVAILABLE' },
    });
    expect(await assignMeToAppointment(CLINIC, APPOINTMENT)).toEqual({
      kind: 'serviceUnavailable',
    });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    expect(await assignMeToAppointment(CLINIC, APPOINTMENT)).toEqual({ kind: 'denied' });
    rpc.mockRejectedValueOnce(new Error('network'));
    expect(await assignMeToAppointment(CLINIC, APPOINTMENT)).toEqual({ kind: 'uncertain' });
    rpc.mockResolvedValueOnce({ data: { outcome: 'ASSIGNED' }, error: null });
    expect(await assignMeToAppointment(CLINIC, APPOINTMENT)).toEqual({ kind: 'uncertain' });
  });
});

import type { AppointmentVeterinarianAssignment } from '@/data/appointment-veterinarian-assignment';
import {
  assignmentNotice,
  currentAssigneeFor,
  expectedTokenFor,
  selectableCandidates,
  veterinarianName,
} from '@/lib/appointment-veterinarian-assignment';

const unassigned: AppointmentVeterinarianAssignment = {
  kind: 'unassigned',
  mayAssignMe: true,
  mayManage: true,
};
const assigned = (
  overrides: Partial<Extract<AppointmentVeterinarianAssignment, { kind: 'assigned' }>> = {},
): AppointmentVeterinarianAssignment => ({
  kind: 'assigned',
  displayName: 'Ana García',
  isMe: false,
  isEligible: true,
  assignmentToken: 'token-1',
  mayAssignMe: false,
  mayManage: true,
  ...overrides,
});

describe('presentation', () => {
  it('shows the name as entered, the neutral fallback, and "(You)"', () => {
    expect(
      veterinarianName({ displayName: 'Ana García', isMe: false }, 'Veterinario', '(Tú)'),
    ).toBe('Ana García');
    expect(veterinarianName({ displayName: null, isMe: true }, 'Veterinario', '(Tú)')).toBe(
      'Veterinario (Tú)',
    );
  });

  it('a first assignment sends no token and asks for no confirmation; a change sends the reviewed token', () => {
    expect(expectedTokenFor(unassigned)).toBeNull();
    expect(currentAssigneeFor(unassigned)).toBeNull();
    expect(expectedTokenFor(assigned())).toBe('token-1');
    expect(currentAssigneeFor(assigned())).toEqual({ displayName: 'Ana García', isMe: false });
  });

  it('never offers the current assignee as a change', () => {
    const current = {
      veterinarianClinicAssignmentId: 'vca-1',
      displayName: 'Ana',
      isMe: false,
      isCurrentAssignee: true,
    };
    const other = { ...current, veterinarianClinicAssignmentId: 'vca-2', isCurrentAssignee: false };
    expect(selectableCandidates([current, other])).toEqual([other]);
  });
});

describe('assignmentNotice (after the authoritative re-read)', () => {
  it('reports each outcome', () => {
    expect(
      assignmentNotice({ kind: 'outcome', outcome: 'ASSIGNED' }, 'self', null).messageKey,
    ).toBe('veterinarianAssignment.assignedToMe');
    expect(
      assignmentNotice({ kind: 'outcome', outcome: 'ASSIGNED' }, 'manage', null).messageKey,
    ).toBe('veterinarianAssignment.assigned');
    expect(
      assignmentNotice({ kind: 'outcome', outcome: 'REASSIGNED' }, 'manage', null).messageKey,
    ).toBe('veterinarianAssignment.reassigned');
    expect(
      assignmentNotice({ kind: 'outcome', outcome: 'ALREADY_ASSIGNED' }, 'manage', null).messageKey,
    ).toBe('veterinarianAssignment.alreadyAssigned');
  });

  it('a stale assignment and a colleague who acted first are calm, not errors', () => {
    expect(
      assignmentNotice({ kind: 'rejected', reason: 'STALE_ASSIGNMENT' }, 'manage', assigned()),
    ).toEqual({ tone: 'info', messageKey: 'veterinarianAssignment.staleAssignment' });
    expect(
      assignmentNotice(
        { kind: 'rejected', reason: 'ASSIGNED_TO_ANOTHER_VETERINARIAN' },
        'self',
        assigned(),
      ),
    ).toEqual({ tone: 'info', messageKey: 'veterinarianAssignment.assignedToAnother' });
  });

  it('a lost self-assignment is a success only when the re-read shows the reader holds it', () => {
    expect(
      assignmentNotice({ kind: 'uncertain' }, 'self', assigned({ isMe: true })).messageKey,
    ).toBe('veterinarianAssignment.assignedToMe');
    expect(assignmentNotice({ kind: 'uncertain' }, 'self', assigned()).messageKey).toBe(
      'veterinarianAssignment.unconfirmed',
    );
    expect(
      assignmentNotice({ kind: 'uncertain' }, 'self', assigned({ isMe: true, isEligible: false }))
        .messageKey,
    ).toBe('veterinarianAssignment.unconfirmed');
    expect(assignmentNotice({ kind: 'uncertain' }, 'manage', assigned()).messageKey).toBe(
      'veterinarianAssignment.unconfirmed',
    );
  });

  it.each([
    [{ kind: 'denied' as const }, 'veterinarianAssignment.denied'],
    [{ kind: 'serviceUnavailable' as const }, 'veterinarianAssignment.serviceUnavailable'],
    [{ kind: 'authenticationRequired' as const }, 'errors.sessionExpired'],
    [
      { kind: 'rejected' as const, reason: 'VETERINARIAN_SCHEDULE_CONFLICT' as const },
      'veterinarianAssignment.scheduleConflict',
    ],
    [
      { kind: 'rejected' as const, reason: 'VETERINARIAN_NOT_ELIGIBLE' as const },
      'veterinarianAssignment.notEligible',
    ],
    [
      { kind: 'rejected' as const, reason: 'APPOINTMENT_STATE_INVALID' as const },
      'veterinarianAssignment.stateInvalid',
    ],
  ])('maps %o', (result, messageKey) => {
    expect(assignmentNotice(result, 'manage', null)).toEqual({ tone: 'error', messageKey });
  });
});

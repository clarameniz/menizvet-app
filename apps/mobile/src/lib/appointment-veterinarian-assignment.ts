import type {
  AppointmentVeterinarianAssignment,
  AppointmentVeterinarianCandidate,
  AssignmentRejection,
  AssignmentWriteResult,
} from '@/data/appointment-veterinarian-assignment';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Presentation of the Appointment's assigned Veterinarian (SPEC-APT-007 §13
 * Mobile presentation). Advisory only: `may_assign_me` / `may_manage` come
 * from the server and every write re-authorizes. Nothing here assigns.
 */

/** The name shown for an assignee or candidate: as entered, or the neutral fallback. */
export function veterinarianName(
  person: { displayName: string | null; isMe: boolean },
  fallback: string,
  youSuffix: string,
): string {
  const name = person.displayName ?? fallback;
  return person.isMe ? `${name} ${youSuffix}` : name;
}

/**
 * Who the change dialog names as the current Veterinarian: the reviewed
 * assignee. `null` when nobody is assigned — a first assignment asks for no
 * confirmation (SPEC-APT-007 §13: only a change does).
 */
export function currentAssigneeFor(
  assignment: AppointmentVeterinarianAssignment,
): { displayName: string | null; isMe: boolean } | null {
  return assignment.kind === 'assigned'
    ? { displayName: assignment.displayName, isMe: assignment.isMe }
    : null;
}

/** The stale-safe expectation sent with a managed assignment (BR-32). */
export function expectedTokenFor(assignment: AppointmentVeterinarianAssignment): string | null {
  return assignment.kind === 'assigned' ? assignment.assignmentToken : null;
}

/** Candidates other than the current assignee: choosing the current one changes nothing. */
export function selectableCandidates(
  candidates: readonly AppointmentVeterinarianCandidate[],
): AppointmentVeterinarianCandidate[] {
  return candidates.filter((candidate) => !candidate.isCurrentAssignee);
}

export type AssignmentIntent = 'self' | 'manage';
export type AssignmentNotice = { tone: 'info' | 'error'; messageKey: TranslationKey };

const REJECTION_KEYS: Record<AssignmentRejection, AssignmentNotice> = {
  VETERINARIAN_REQUIRED: { tone: 'error', messageKey: 'veterinarianAssignment.unconfirmed' },
  APPOINTMENT_STATE_INVALID: { tone: 'error', messageKey: 'veterinarianAssignment.stateInvalid' },
  // A colleague or a manager acted first: the re-read shows who has it, calmly.
  ASSIGNED_TO_ANOTHER_VETERINARIAN: {
    tone: 'info',
    messageKey: 'veterinarianAssignment.assignedToAnother',
  },
  STALE_ASSIGNMENT: { tone: 'info', messageKey: 'veterinarianAssignment.staleAssignment' },
  VETERINARIAN_NOT_ELIGIBLE: { tone: 'error', messageKey: 'veterinarianAssignment.notEligible' },
  VETERINARIAN_SCHEDULE_CONFLICT: {
    tone: 'error',
    messageKey: 'veterinarianAssignment.scheduleConflict',
  },
};

/**
 * The notice after an assignment attempt and the authoritative re-read
 * (`after`, null when it failed). A lost self-assignment response is judged
 * from the re-read: if the reader now holds the Appointment, it worked.
 */
export function assignmentNotice(
  result: AssignmentWriteResult,
  intent: AssignmentIntent,
  after: AppointmentVeterinarianAssignment | null,
): AssignmentNotice {
  switch (result.kind) {
    case 'outcome':
      if (intent === 'self')
        return { tone: 'info', messageKey: 'veterinarianAssignment.assignedToMe' };
      if (result.outcome === 'ALREADY_ASSIGNED')
        return { tone: 'info', messageKey: 'veterinarianAssignment.alreadyAssigned' };
      return {
        tone: 'info',
        messageKey:
          result.outcome === 'REASSIGNED'
            ? 'veterinarianAssignment.reassigned'
            : 'veterinarianAssignment.assigned',
      };
    case 'rejected':
      return REJECTION_KEYS[result.reason];
    case 'denied':
      return { tone: 'error', messageKey: 'veterinarianAssignment.denied' };
    case 'serviceUnavailable':
      return { tone: 'error', messageKey: 'veterinarianAssignment.serviceUnavailable' };
    case 'authenticationRequired':
      return { tone: 'error', messageKey: 'errors.sessionExpired' };
    case 'uncertain':
      return intent === 'self' && after?.kind === 'assigned' && after.isMe && after.isEligible
        ? { tone: 'info', messageKey: 'veterinarianAssignment.assignedToMe' }
        : { tone: 'error', messageKey: 'veterinarianAssignment.unconfirmed' };
  }
}

import type { RequestableCandidate } from '@/data/appointments';

/**
 * The Reschedule Requested Appointment form rule (SPEC-APT-004). Candidate
 * date/time selection itself is shared by every candidate picker
 * (lib/candidate-selection.ts).
 */

/** Save is only possible once a concrete candidate slot is selected. */
export function canSubmitReschedule(selectedCandidate: RequestableCandidate | null): boolean {
  return selectedCandidate !== null;
}

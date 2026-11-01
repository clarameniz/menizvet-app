/**
 * Pure candidate date/time selection rules shared by every Appointment
 * candidate picker: Guardian request (SPEC-APT-001/014), Guardian requested
 * reschedule (SPEC-APT-004/014), and Clinic confirmed reschedule
 * (SPEC-APT-005/017).
 *
 * They work on the common candidate identity only — Clinic-local date, local
 * time, and the UTC offset the backend resolved it with — and are generic so a
 * flow's richer candidate (for example a Professional candidate carrying its
 * server-authored end) always comes back as the exact fresh object. Nothing
 * here computes a duration or an end, reads a clock, or knows which flow,
 * read, or policy produced the candidates.
 */

/** What identifies one candidate slot. */
export type CandidateIdentity = {
  localDate: string;
  localTime: string;
  utcOffsetSeconds: number;
};

/** Two candidates are the same slot iff date, time and UTC offset all match. */
export function isSameCandidate(a: CandidateIdentity, b: CandidateIdentity): boolean {
  return (
    a.localDate === b.localDate &&
    a.localTime === b.localTime &&
    a.utcOffsetSeconds === b.utcOffsetSeconds
  );
}

/** A stable key for one candidate slot (same identity as `isSameCandidate`). */
export function candidateKey(candidate: CandidateIdentity): string {
  return `${candidate.localDate}T${candidate.localTime}${candidate.utcOffsetSeconds}`;
}

/**
 * The distinct Clinic-local dates present in a candidate read, ascending — the
 * exact set a date picker may offer (a date with zero candidates is simply
 * absent, never a disabled chip).
 */
export function distinctSortedCandidateDates(candidates: readonly CandidateIdentity[]): string[] {
  return [...new Set(candidates.map((candidate) => candidate.localDate))].sort();
}

/**
 * The already-loaded candidates of one Clinic-local date, in backend order,
 * as the same objects — selecting a date never triggers another read.
 */
export function candidatesForDate<T extends CandidateIdentity>(
  candidates: readonly T[],
  localDate: string,
): T[] {
  return candidates.filter((candidate) => candidate.localDate === localDate);
}

/**
 * The selected slot after `localDate` is picked: kept only if it already
 * belongs to that date, otherwise cleared (a slot never silently carries over
 * to another day).
 */
export function candidateAfterDateChange<T extends CandidateIdentity>(
  previous: T | null,
  localDate: string,
): T | null {
  return previous !== null && previous.localDate === localDate ? previous : null;
}

/**
 * The date to show after a candidate read: `preferredDate` while the read
 * offers it, otherwise the first date that has candidates; `null` only when
 * the read returned none. A date without candidates is never selected.
 *
 * Flows choose the preference: nothing (request), the Appointment's current
 * Clinic-local date (Guardian reschedule), or the date already selected
 * (Clinic reschedule refresh).
 */
export function preferredCandidateDate(
  candidates: readonly CandidateIdentity[],
  preferredDate: string | null,
): string | null {
  const dates = distinctSortedCandidateDates(candidates);
  return preferredDate !== null && dates.includes(preferredDate)
    ? preferredDate
    : (dates[0] ?? null);
}

/**
 * The selected slot after a candidate read: the fresh candidate for the same
 * slot — the complete fresh object, so any server-authored field such as a
 * candidate end is the latest one — or `null` when the slot is no longer
 * offered.
 */
export function rematchSelectedCandidate<T extends CandidateIdentity>(
  candidates: readonly T[],
  previous: CandidateIdentity | null,
): T | null {
  if (previous === null) return null;
  return candidates.find((candidate) => isSameCandidate(candidate, previous)) ?? null;
}

/** "HH:mm:ss" -> "HH:mm"; candidates are always returned with seconds. */
export function formatCandidateTime(localTime: string): string {
  return localTime.slice(0, 5);
}

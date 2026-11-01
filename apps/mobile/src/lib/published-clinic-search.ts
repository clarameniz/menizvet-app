/**
 * Pure presentation helpers for the public Clinic list (`/clinics`,
 * SPEC-DIS-004 §5) — kept out of the route component so they are
 * unit-testable. Deliberately separate from the professional Clinics list's
 * helpers: the public list depends on no professional module.
 */

/** Characters a search may have (SPEC-DIS-004 §4: longer is rejected). */
export const PUBLISHED_CLINIC_SEARCH_MAX_LENGTH = 100;

/** Pause after typing before a search is sent (SPEC-DIS-004 §5). */
export const PUBLISHED_CLINIC_SEARCH_DEBOUNCE_MS = 300;

/**
 * The search a typed text submits: outer whitespace never starts a new search
 * (the backend ignores it too); '' is no search.
 */
export function submittedPublishedClinicSearch(typed: string): string {
  return typed.trim();
}

/**
 * What the list shows below its header for the current search:
 * - `pending` — its first page has not arrived (loading, or failed before
 *   anything was shown): no row and no empty message;
 * - `rows` — the Clinics read so far;
 * - `noClinics` — no published Clinic at all;
 * - `noMatches` — the search's first page arrived empty.
 */
export type PublishedClinicsBody = 'pending' | 'rows' | 'noClinics' | 'noMatches';

export function publishedClinicsBody(
  rows: readonly unknown[] | null,
  search: string,
): PublishedClinicsBody {
  if (rows === null) return 'pending';
  if (rows.length > 0) return 'rows';
  return search === '' ? 'noClinics' : 'noMatches';
}

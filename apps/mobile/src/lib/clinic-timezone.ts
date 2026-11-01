import { SCHEDULING_TIMEZONES } from '@/constants/scheduling-timezones';
import type { EditorReadAfterFailure, EditorSaveFailure } from '@/lib/clinic-settings-editors';

/**
 * Pure logic for the Clinic scheduling timezone editor (SPEC-APT-013 BR-76).
 * The actor chooses one named IANA timezone from an explicit, searchable
 * list; the device timezone may be offered as a suggestion that applies only
 * when selected. Nothing is ever derived from the Clinic's location or
 * address. The canonical IANA name is what is saved; the backend validates it
 * and applies BR-56.
 */

export type TimezoneLabel = {
  /** "Buenos Aires" — the last segment, readable. */
  city: string;
  /** "America / Argentina" — the leading segments. */
  region: string;
  /** The canonical IANA name, always shown for clarity. */
  name: string;
};

const readable = (segment: string) => segment.replace(/_/g, ' ');

export function timezoneLabel(name: string): TimezoneLabel {
  const segments = name.split('/');
  const city = segments.length > 1 ? (segments.at(-1) as string) : name;
  return {
    city: readable(city),
    region: segments.slice(0, -1).map(readable).join(' / '),
    name,
  };
}

/** Lower case, accents removed, underscores and slashes as spaces. */
function searchable(text: string): string {
  return text
    .normalize('NFD')
    .split('')
    .filter((character) => {
      const code = character.charCodeAt(0);
      return code < 0x300 || code > 0x36f; // drop combining diacritical marks
    })
    .join('')
    .toLowerCase()
    .replace(/[_/]+/g, ' ')
    .trim();
}

/** How many results the editor shows at once; a longer list asks for a more specific search. */
export const TIMEZONE_RESULTS_LIMIT = 40;

/**
 * Timezones whose city, region, or IANA name contain every word of `query`
 * (accent- and case-insensitive), cities starting with the query first, then
 * alphabetically. An empty query matches nothing: the list is searched, not
 * scrolled through.
 */
export function searchTimezones(
  query: string,
  zones: readonly string[] = SCHEDULING_TIMEZONES,
): string[] {
  const terms = searchable(query).split(/\s+/).filter(Boolean);
  if (terms.length === 0) return [];
  const prefix = searchable(query);
  return zones
    .filter((zone) => {
      const haystack = searchable(zone);
      return terms.every((term) => haystack.includes(term));
    })
    .sort((a, b) => {
      const aPrefix = searchable(timezoneLabel(a).city).startsWith(prefix) ? 0 : 1;
      const bPrefix = searchable(timezoneLabel(b).city).startsWith(prefix) ? 0 : 1;
      return aPrefix - bPrefix || (a < b ? -1 : a > b ? 1 : 0);
    });
}

/**
 * The device's timezone as a suggestion, only when it is one the editor
 * offers; `null` otherwise. Never applied without an explicit selection.
 */
export function deviceTimezoneSuggestion(
  deviceTimezone: string | null | undefined,
  zones: readonly string[] = SCHEDULING_TIMEZONES,
): string | null {
  return deviceTimezone != null && zones.includes(deviceTimezone) ? deviceTimezone : null;
}

export type TimezoneSelectionState = {
  /**
   * The explicit choice that differs from the stored timezone — an unsaved
   * change, shown prominently next to the controls — or `null`.
   */
  pending: TimezoneLabel | null;
  /** Whether the device timezone is still worth offering as a one-tap suggestion. */
  offerDeviceSuggestion: boolean;
};

/**
 * One selection model for both ways of choosing (a search result or the
 * device suggestion): whatever was chosen last is the selection, presented
 * the same way. Choosing the stored timezone again is not an unsaved change.
 * Nothing here saves; Save stays explicit.
 */
export function timezoneSelectionState(input: {
  selected: string | null;
  stored: string | null;
  suggestion: string | null;
}): TimezoneSelectionState {
  const { selected, stored, suggestion } = input;
  return {
    pending: selected !== null && selected !== stored ? timezoneLabel(selected) : null,
    offerDeviceSuggestion: suggestion !== null && suggestion !== stored && suggestion !== selected,
  };
}

/** Save needs an explicit selection different from the stored timezone, and nothing in flight. */
export function canSaveTimezone(input: {
  selected: string | null;
  stored: string | null;
  busy: boolean;
}): boolean {
  return !input.busy && input.selected !== null && input.selected !== input.stored;
}

/** What a failed timezone save means, decided from the fresh read that follows it. */
export function timezoneSaveFailure(
  read: EditorReadAfterFailure,
  submitted: string,
): EditorSaveFailure {
  if (read?.kind === 'unavailable') return 'accessLost';
  if (read?.kind === 'loaded' && read.profile.schedulingTimezoneName === submitted) {
    return 'committed';
  }
  return 'failed';
}

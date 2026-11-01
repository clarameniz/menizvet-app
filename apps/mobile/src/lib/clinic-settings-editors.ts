import type {
  ManagedClinicLocation,
  ManagedClinicProfile,
  ManagedClinicPublicProfile,
} from '@/data/clinic-settings';

/**
 * Pure logic for the Clinic settings Profile and Location editors
 * (SPEC-CLI-004 BR-15–BR-21, SPEC-CLI-002 BR-12–BR-17). Everything here is
 * ADVISORY form logic — what to offer and when Save is enabled. The backend
 * re-validates and re-authorizes every save, and every value shown comes from
 * a fresh management read.
 */

// ---------------------------------------------------------------------------
// Backend whitespace (SPEC-CLI-004 BR-16, SPEC-CLI-002 BR-12)
// ---------------------------------------------------------------------------

/**
 * Exactly the backend's whitespace set, `E' \t\n\r\f\013'`: space, tab, line
 * feed, carriage return, form feed, vertical tab. Deliberately NOT
 * `String.prototype.trim`, which also removes non-breaking and other Unicode
 * spaces the backend keeps — comparing with it would misjudge "unchanged" and
 * lost-response reconciliation.
 */
const BACKEND_EDGE_WHITESPACE = /^[ \t\n\r\f\u000B]+|[ \t\n\r\f\u000B]+$/g;

/** `btrim(value, E' \t\n\r\f\013')`. */
export function backendTrim(value: string): string {
  return value.replace(BACKEND_EDGE_WHITESPACE, '');
}

/** What the backend stores for one profile value: trimmed, or `null` when blank. */
export function storedValueOf(value: string): string | null {
  const trimmed = backendTrim(value);
  return trimmed === '' ? null : trimmed;
}

// ---------------------------------------------------------------------------
// Profile (one save replaces all five values, BR-15)
// ---------------------------------------------------------------------------

/** The editor's text, exactly as typed (never rewritten while typing). */
export type ProfileDraft = {
  displayName: string;
  description: string;
  publicPhone: string;
  publicEmail: string;
  website: string;
};

/** The draft from the stored profile; an absent profile or value starts empty. */
export function profileDraftFrom(profile: ManagedClinicPublicProfile | null): ProfileDraft {
  return {
    displayName: profile?.displayName ?? '',
    description: profile?.description ?? '',
    publicPhone: profile?.publicPhone ?? '',
    publicEmail: profile?.publicEmail ?? '',
    website: profile?.website ?? '',
  };
}

/** The complete save: all five values as the backend will store them. */
export function profilePayload(draft: ProfileDraft): ManagedClinicPublicProfile {
  return {
    displayName: storedValueOf(draft.displayName),
    description: storedValueOf(draft.description),
    publicPhone: storedValueOf(draft.publicPhone),
    publicEmail: storedValueOf(draft.publicEmail),
    website: storedValueOf(draft.website),
  };
}

const EMPTY_PROFILE: ManagedClinicPublicProfile = {
  displayName: null,
  description: null,
  publicPhone: null,
  publicEmail: null,
  website: null,
};

/**
 * Whether the stored profile is exactly what `payload` stores. An absent
 * profile equals an all-absent payload (an all-absent save of an unpublished
 * Clinic removes the profile, BR-16).
 */
export function profileMatches(
  stored: ManagedClinicPublicProfile | null,
  payload: ManagedClinicPublicProfile,
): boolean {
  const current = stored ?? EMPTY_PROFILE;
  return (
    current.displayName === payload.displayName &&
    current.description === payload.description &&
    current.publicPhone === payload.publicPhone &&
    current.publicEmail === payload.publicEmail &&
    current.website === payload.website
  );
}

/**
 * A published Clinic must keep its display name (BR-17); an unpublished one
 * may be saved without it. `null` when the draft can be saved.
 */
export type ProfileDraftIssue = 'nameRequiredWhilePublished';

export function profileDraftIssue(
  draft: ProfileDraft,
  isPublished: boolean,
): ProfileDraftIssue | null {
  return isPublished && storedValueOf(draft.displayName) === null
    ? 'nameRequiredWhilePublished'
    : null;
}

/** Save is enabled when the draft is valid, actually changes something, and nothing is in flight. */
export function canSaveProfile(input: {
  draft: ProfileDraft;
  profile: ManagedClinicProfile;
  busy: boolean;
}): boolean {
  const { draft, profile, busy } = input;
  return (
    !busy &&
    profileDraftIssue(draft, profile.isPublished) === null &&
    !profileMatches(profile.publicProfile, profilePayload(draft))
  );
}

// ---------------------------------------------------------------------------
// Location (address text + map position, BR-12–BR-14)
// ---------------------------------------------------------------------------

export type Coordinate = { latitude: number; longitude: number };

/** Decimal places kept for a map position (~0.1 m), so a save re-reads exactly. */
export const COORDINATE_DECIMALS = 6;

/** The canonical coordinate value: rounded to 6 decimals, never `-0`. */
export function roundCoordinate(value: number): number {
  const rounded = Math.round(value * 10 ** COORDINATE_DECIMALS) / 10 ** COORDINATE_DECIMALS;
  return rounded === 0 ? 0 : rounded;
}

export function roundedCoordinate(coordinate: Coordinate): Coordinate {
  return {
    latitude: roundCoordinate(coordinate.latitude),
    longitude: roundCoordinate(coordinate.longitude),
  };
}

function isInRange(coordinate: Coordinate): boolean {
  return (
    Number.isFinite(coordinate.latitude) &&
    Number.isFinite(coordinate.longitude) &&
    Math.abs(coordinate.latitude) <= 90 &&
    Math.abs(coordinate.longitude) <= 180
  );
}

/**
 * The editor's state. `pin` is `null` until a map position has been
 * established: a Clinic without a stored location starts with no pin, and
 * the map's neutral starting region is never one (BR-13). A stored location
 * starts with its stored position, which counts as confirmed.
 */
export type LocationDraft = { addressText: string; pin: Coordinate | null };

export function locationDraftFrom(location: ManagedClinicLocation | null): LocationDraft {
  return location === null
    ? { addressText: '', pin: null }
    : {
        addressText: location.addressText,
        pin: { latitude: location.latitude, longitude: location.longitude },
      };
}

/** Sets the pin from an explicit user action (map press, pin drag, "place at centre"). */
export function withPin(draft: LocationDraft, coordinate: Coordinate): LocationDraft {
  return { ...draft, pin: coordinate };
}

export type LocationDraftIssue = 'addressRequired' | 'pinRequired' | 'pinOutOfRange';

/** Every reason the draft can't be saved yet, in display order. */
export function locationDraftIssues(draft: LocationDraft): LocationDraftIssue[] {
  const issues: LocationDraftIssue[] = [];
  if (backendTrim(draft.addressText) === '') issues.push('addressRequired');
  if (draft.pin === null) issues.push('pinRequired');
  else if (!isInRange(draft.pin)) issues.push('pinOutOfRange');
  return issues;
}

/** The save — trimmed address and rounded position — or `null` while the draft is incomplete. */
export function locationPayload(draft: LocationDraft): ManagedClinicLocation | null {
  if (locationDraftIssues(draft).length > 0 || draft.pin === null) return null;
  const pin = roundedCoordinate(draft.pin);
  return {
    addressText: backendTrim(draft.addressText),
    latitude: pin.latitude,
    longitude: pin.longitude,
  };
}

/** Whether the stored location is exactly what `payload` stores (positions compared rounded). */
export function locationMatches(
  stored: ManagedClinicLocation | null,
  payload: ManagedClinicLocation,
): boolean {
  if (stored === null) return false;
  const storedPin = roundedCoordinate(stored);
  return (
    stored.addressText === payload.addressText &&
    storedPin.latitude === payload.latitude &&
    storedPin.longitude === payload.longitude
  );
}

/** Save is enabled when the draft is complete and valid, changes something, and nothing is in flight. */
export function canSaveLocation(input: {
  draft: LocationDraft;
  stored: ManagedClinicLocation | null;
  busy: boolean;
}): boolean {
  const payload = locationPayload(input.draft);
  return !input.busy && payload !== null && !locationMatches(input.stored, payload);
}

/** "40.416800, -3.703800" — the map position as text, for display and screen readers. */
export function formatCoordinate(coordinate: Coordinate): string {
  const pin = roundedCoordinate(coordinate);
  return `${pin.latitude.toFixed(COORDINATE_DECIMALS)}, ${pin.longitude.toFixed(COORDINATE_DECIMALS)}`;
}

/**
 * The map's starting camera for a Clinic without a stored location: the same
 * neutral, non-market-specific world view as Map Discovery. Its centre is
 * never treated as a chosen position.
 */
export const NEUTRAL_MAP_REGION = {
  latitude: 0,
  longitude: 0,
  latitudeDelta: 80,
  longitudeDelta: 80,
} as const;

/** A street-level camera around a position. */
export function regionAround(coordinate: Coordinate) {
  return {
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
    latitudeDelta: 0.01,
    longitudeDelta: 0.01,
  };
}

// ---------------------------------------------------------------------------
// Save failure reconciliation (SPEC-CLI-004 BR-19, SPEC-CLI-002 BR-16)
// ---------------------------------------------------------------------------

/** The editor's read after a failed save: the managed profile, access lost, or still unreadable. */
export type EditorReadAfterFailure =
  | { kind: 'loaded'; profile: ManagedClinicProfile }
  | { kind: 'unavailable' }
  | { kind: 'error' }
  | null;

/**
 * What a failed save means, decided from the fresh read that follows it:
 * - `committed`: the stored values are exactly what was sent (a lost
 *   response after the save committed) — treated as success;
 * - `accessLost`: the editor is no longer available to this User; the screen
 *   shows that instead of an editable stale form;
 * - `failed`: anything else; the draft is kept as typed and the error shown.
 */
export type EditorSaveFailure = 'committed' | 'accessLost' | 'failed';

export function profileSaveFailure(
  read: EditorReadAfterFailure,
  submitted: ManagedClinicPublicProfile,
): EditorSaveFailure {
  if (read?.kind === 'unavailable') return 'accessLost';
  if (read?.kind === 'loaded' && profileMatches(read.profile.publicProfile, submitted)) {
    return 'committed';
  }
  return 'failed';
}

export function locationSaveFailure(
  read: EditorReadAfterFailure,
  submitted: ManagedClinicLocation,
): EditorSaveFailure {
  if (read?.kind === 'unavailable') return 'accessLost';
  if (read?.kind === 'loaded' && locationMatches(read.profile.location, submitted)) {
    return 'committed';
  }
  return 'failed';
}

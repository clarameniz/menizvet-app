import type { ViewportBounds } from '@/data/clinics';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure Discovery helpers with no Supabase/React dependency: map-region math,
 * antimeridian normalization, cross-query de-duplication, request-staleness
 * sequencing, and distance formatting. Kept dependency-free so every one of
 * these is plainly unit-testable (see discovery-viewport.test.ts).
 */

// ---------------------------------------------------------------------------
// Viewport bounds
// ---------------------------------------------------------------------------

/**
 * Structurally matches react-native-maps' `Region` — defined locally rather
 * than imported so this module stays free of that native dependency.
 */
export type MapRegion = {
  latitude: number;
  longitude: number;
  latitudeDelta: number;
  longitudeDelta: number;
};

/**
 * Like ViewportBounds, but longitude may fall outside [-180, 180] and/or
 * (before splitting) implicitly represent a crossing span — the raw output
 * of region math, not yet legal input for discover_clinics_in_viewport.
 */
export type RawViewportBounds = {
  minLatitude: number;
  maxLatitude: number;
  minLongitude: number;
  maxLongitude: number;
};

/**
 * The Map's default starting camera: mainland Spain and the Balearic Islands
 * (the product/UI choice SPEC-DIS-003 §8 "Map is opened without a User
 * location" leaves open). A starting view only — never a User position and
 * never a geographic limit: the map moves freely and Discovery is not
 * restricted to Spain.
 */
export const INITIAL_MAP_REGION: MapRegion = {
  latitude: 40.0,
  longitude: -2.9,
  latitudeDelta: 9,
  longitudeDelta: 15.2,
};

const MIN_LATITUDE = -90;
const MAX_LATITUDE = 90;
const MIN_LONGITUDE = -180;
const MAX_LONGITUDE = 180;
const FULL_LONGITUDE_SPAN = 360;

/** Clamps latitude into the backend's legal range; longitude is left raw. */
export function regionToViewportBounds(region: MapRegion): RawViewportBounds {
  const halfLatitude = region.latitudeDelta / 2;
  const halfLongitude = region.longitudeDelta / 2;

  return {
    minLatitude: Math.max(MIN_LATITUDE, region.latitude - halfLatitude),
    maxLatitude: Math.min(MAX_LATITUDE, region.latitude + halfLatitude),
    minLongitude: region.longitude - halfLongitude,
    maxLongitude: region.longitude + halfLongitude,
  };
}

/**
 * Wraps into [-180, 180], leaving values already inside that range
 * untouched — in particular, an exact 180 (a legal non-crossing upper bound)
 * must not be forced to -180, or a non-crossing viewport that happens to
 * reach the boundary would be misdetected as crossing below.
 */
function normalizeLongitude(longitude: number): number {
  let normalized = longitude;
  while (normalized > MAX_LONGITUDE) normalized -= FULL_LONGITUDE_SPAN;
  while (normalized < MIN_LONGITUDE) normalized += FULL_LONGITUDE_SPAN;
  return normalized;
}

/**
 * discover_clinics_in_viewport rejects min_longitude > max_longitude
 * outright (a documented Phase-1 API limitation, not wrap-around support —
 * docs/DISCOVERY_BACKEND.md). A visible map region that genuinely straddles
 * ±180° is split here into exactly one or two legal, non-crossing
 * ViewportBounds; backend semantics are never changed.
 */
export function splitViewportAtAntimeridian(bounds: RawViewportBounds): ViewportBounds[] {
  const { minLatitude, maxLatitude } = bounds;

  if (bounds.maxLongitude - bounds.minLongitude >= FULL_LONGITUDE_SPAN) {
    return [{ minLatitude, maxLatitude, minLongitude: MIN_LONGITUDE, maxLongitude: MAX_LONGITUDE }];
  }

  const normalizedMin = normalizeLongitude(bounds.minLongitude);
  const normalizedMax = normalizeLongitude(bounds.maxLongitude);

  if (normalizedMin <= normalizedMax) {
    return [{ minLatitude, maxLatitude, minLongitude: normalizedMin, maxLongitude: normalizedMax }];
  }

  return [
    { minLatitude, maxLatitude, minLongitude: normalizedMin, maxLongitude: MAX_LONGITUDE },
    { minLatitude, maxLatitude, minLongitude: MIN_LONGITUDE, maxLongitude: normalizedMax },
  ];
}

/**
 * Merges one or two viewport-query result pages strictly by clinic_id —
 * never by display name or coordinates, both of which distinct Clinics may
 * legitimately share (SPEC-DIS-003 §8). The first occurrence wins; a Clinic
 * sitting exactly on the ±180° boundary (inclusive bounds on both split
 * queries) is otherwise returned twice.
 */
export function mergeClinicsById<T extends { clinicId: string }>(pages: T[][]): T[] {
  const byId = new Map<string, T>();

  for (const page of pages) {
    for (const clinic of page) {
      if (!byId.has(clinic.clinicId)) {
        byId.set(clinic.clinicId, clinic);
      }
    }
  }

  return [...byId.values()];
}

// ---------------------------------------------------------------------------
// Camera for a selected Clinic
// ---------------------------------------------------------------------------

/**
 * The widest view that shows a selected Clinic's local surroundings: 0.1° of
 * latitude by 0.06° of longitude — about 11 km north–south by 5 km east–west
 * at Spain's latitude, i.e. the district around it and its main roads: close
 * enough to tell nearby Clinics apart, wide enough to keep context. A view
 * wider on either side is zoomed in on that side; a closer one is kept.
 */
export const SELECTED_CLINIC_MAX_DELTAS = { latitudeDelta: 0.1, longitudeDelta: 0.06 };

/**
 * Share of the visible span a selected marker should keep from each edge.
 * Larger at the top (the pin is drawn above its point) and at the bottom (the
 * Clinic card appearing below can shorten the map).
 */
const SELECTED_CLINIC_MARGINS = { top: 0.2, bottom: 0.3, side: 0.15 };

/**
 * Where the camera should go when a Clinic is selected, or `null` to leave it
 * as it is:
 * - wider than SELECTED_CLINIC_MAX_DELTAS on either side: centred on the
 *   Clinic, each side narrowed to at most its maximum;
 * - close enough, with the Clinic clear of the edges: `null` (no move);
 * - close enough, but the Clinic near or past an edge: centred on it at the
 *   current span.
 * No side ever grows: selecting never zooms out.
 */
export function regionToShowSelectedClinic(
  current: MapRegion,
  clinic: { latitude: number; longitude: number },
): MapRegion | null {
  const { latitudeDelta, longitudeDelta } = SELECTED_CLINIC_MAX_DELTAS;
  if (current.latitudeDelta > latitudeDelta || current.longitudeDelta > longitudeDelta) {
    return {
      latitude: clinic.latitude,
      longitude: clinic.longitude,
      latitudeDelta: Math.min(current.latitudeDelta, latitudeDelta),
      longitudeDelta: Math.min(current.longitudeDelta, longitudeDelta),
    };
  }

  const bounds = regionToViewportBounds(current);
  const { top, bottom, side } = SELECTED_CLINIC_MARGINS;
  const clear =
    clinic.latitude <= bounds.maxLatitude - current.latitudeDelta * top &&
    clinic.latitude >= bounds.minLatitude + current.latitudeDelta * bottom &&
    clinic.longitude >= bounds.minLongitude + current.longitudeDelta * side &&
    clinic.longitude <= bounds.maxLongitude - current.longitudeDelta * side;
  if (clear) return null;

  return {
    latitude: clinic.latitude,
    longitude: clinic.longitude,
    latitudeDelta: current.latitudeDelta,
    longitudeDelta: current.longitudeDelta,
  };
}

const METERS_PER_DEGREE_LATITUDE = 111_320;

/**
 * Derives a MapRegion's zoom from a radius in meters, for recentering the
 * map after "Use my location" — reuses the one approved Nearby radius
 * constant (src/constants/discovery.ts) instead of inventing an unrelated
 * zoom number. Longitude degrees shrink toward the poles; the cosine
 * denominator is bounded away from 0 so a location near a pole can't
 * produce an unbounded delta.
 */
export function regionForRadiusMeters(
  center: { latitude: number; longitude: number },
  radiusMeters: number,
): MapRegion {
  const latitudeDelta = (radiusMeters * 2) / METERS_PER_DEGREE_LATITUDE;
  const longitudeMetersPerDegree =
    METERS_PER_DEGREE_LATITUDE * Math.max(Math.cos((center.latitude * Math.PI) / 180), 0.01);
  const longitudeDelta = (radiusMeters * 2) / longitudeMetersPerDegree;

  return {
    latitude: center.latitude,
    longitude: center.longitude,
    latitudeDelta,
    longitudeDelta,
  };
}

// ---------------------------------------------------------------------------
// Latest-request-wins sequencing
// ---------------------------------------------------------------------------

export type RequestGuard = {
  /** Call when a new request starts; returns the token to check on completion. */
  begin: () => number;
  /** True only if no newer request has begun since this token was issued. */
  isCurrent: (token: number) => boolean;
};

/**
 * Plain incrementing-token guard — no debounce/cache library. A screen holds
 * one of these in a ref and combines `isCurrent` with its own isMounted ref
 * before every setState from an async Discovery call, so neither a stale
 * request nor an unmounted screen can apply an outdated result.
 */
export function createLatestRequestGuard(): RequestGuard {
  let latestToken = 0;

  return {
    begin: () => {
      latestToken += 1;
      return latestToken;
    },
    isCurrent: (token: number) => token === latestToken,
  };
}

// ---------------------------------------------------------------------------
// Distance formatting
// ---------------------------------------------------------------------------

export type FormattedDistance = { key: TranslationKey; count: string };

const METERS_ROUNDING_STEP = 10;

/**
 * Returns a translation key plus a pre-formatted `count` for
 * t(key, { count }) — never a hardcoded unit string, per this repo's
 * localization rule that display text stays out of application logic.
 * Below 1 km, rounds to the nearest 10 m; at or above, one decimal of km.
 */
export function formatDistanceMeters(meters: number): FormattedDistance {
  if (meters < 1000) {
    const rounded = Math.max(0, Math.round(meters / METERS_ROUNDING_STEP) * METERS_ROUNDING_STEP);
    return { key: 'discoveryDistance.meters', count: String(rounded) };
  }

  const kilometers = Math.round((meters / 1000) * 10) / 10;
  return { key: 'discoveryDistance.kilometers', count: kilometers.toFixed(1) };
}

import {
  BASIC_DISCOVERY_PAGE_SIZE,
  NEARBY_DISCOVERY_PAGE_SIZE,
  VIEWPORT_DISCOVERY_PAGE_SIZE,
} from '@/constants/discovery';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the approved Milestone E Discovery read surfaces, verified
 * directly against migration SQL (not assumed from a prior summary):
 *
 * - public.published_clinic_public_profiles (view, Slice 4 —
 *   supabase/migrations/20260825150316_clinic_foundation_and_professional_context.sql) —
 *   `select clinic_id, display_name, description, public_phone,
 *   public_email, website ... where clinic.is_published = true`. This is
 *   the basic/existence surface: it never joins clinic_locations, and a
 *   nonexistent Clinic id produces the exact same zero rows as an
 *   unpublished one (SPEC-DIS-001 non-disclosure). Queried here through
 *   `.from(...)`, not an RPC — granted `SELECT` to anon/authenticated — for
 *   the Clinic detail and the Appointment screens' Clinic names.
 * - discover_published_clinics (SPEC-DIS-004 —
 *   supabase/migrations/20261120090000_published_clinic_name_search.sql) —
 *   the Clinic list: the same Clinics as the view, in alphabetical keyset
 *   pages, optionally narrowed by name, each with its public address or
 *   `null` (a Clinic without a Location is still listed). `jsonb` envelope,
 *   validated by a pure parser.
 * - discover_nearby_clinics / discover_clinics_in_viewport / (Slice 15 —
 *   supabase/migrations/20260905090000_discovery_query_support.sql) —
 *   bounded, keyset-paginated `jsonb`-returning RPCs. Their envelope shape
 *   has no compile-time guarantee from supabase-js, so every row is
 *   validated by a pure parser before being trusted.
 * - get_published_clinic_location / get_published_clinic_service_offerings /
 *   get_published_clinic_opening_hours (Slice 4/6) — single-Clinic `returns
 *   table` RPCs; 0 rows for a nonexistent/unpublished Clinic, identically.
 *
 * Every exported async function here settles into the established
 * { data, error } shape and never rejects — including a thrown/rejected
 * network promise, not only an ordinary Postgrest-level { error } response
 * (same reasoning as data/pets.ts's updatePetProfile; Discovery is this
 * app's first anonymous, high-frequency, cold-network-exposed surface, so
 * every call here gets that guard, not only the one that historically
 * needed it).
 */

export type ClinicsResult<T> = { data: T; error: null } | { data: null; error: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

// ---------------------------------------------------------------------------
// Basic Clinic public profile (published_clinic_public_profiles)
// ---------------------------------------------------------------------------

export type ClinicPublicProfile = {
  clinicId: string;
  displayName: string | null;
  description: string | null;
  publicPhone: string | null;
  publicEmail: string | null;
  website: string | null;
};

export type ClinicPublicProfileRow = {
  clinic_id: string;
  display_name: string | null;
  description: string | null;
  public_phone: string | null;
  public_email: string | null;
  website: string | null;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
export function fromClinicPublicProfileRow(row: ClinicPublicProfileRow): ClinicPublicProfile {
  return {
    clinicId: row.clinic_id,
    displayName: row.display_name,
    description: row.description,
    publicPhone: row.public_phone,
    publicEmail: row.public_email,
    website: row.website,
  };
}

// ---------------------------------------------------------------------------
// Clinic list by name (discover_published_clinics — SPEC-DIS-004)
// ---------------------------------------------------------------------------

/** One row of the Clinic list: only what the read returns (SPEC-DIS-004 BR-4). */
export type PublishedClinicSummary = {
  clinicId: string;
  displayName: string | null;
  description: string | null;
  /** The public address of the Clinic's current Location; `null` without one. */
  addressText: string | null;
};

/** The complete `(display_name, clinic_id)` of a page's last row (BR-7). */
export type PublishedClinicsCursor = { displayName: string | null; clinicId: string };

export type PublishedClinicsPage = {
  clinics: PublishedClinicSummary[];
  hasMore: boolean;
  next: PublishedClinicsCursor | null;
};

function parsePublishedClinicRow(raw: unknown): PublishedClinicSummary | null {
  if (!isRecord(raw)) return null;
  const { clinic_id, display_name, description, address_text } = raw;

  if (typeof clinic_id !== 'string') return null;
  if (display_name !== null && typeof display_name !== 'string') return null;
  if (description !== null && typeof description !== 'string') return null;
  if (address_text !== null && typeof address_text !== 'string') return null;

  return {
    clinicId: clinic_id,
    displayName: display_name,
    description,
    addressText: address_text,
  };
}

/** Exported for unit testing: validates discover_published_clinics' jsonb envelope. */
export function parsePublishedClinicsEnvelope(raw: unknown): PublishedClinicsPage | null {
  if (!isRecord(raw)) return null;

  const { clinics, has_more, next_after_display_name, next_after_clinic_id } = raw;

  if (!Array.isArray(clinics)) return null;
  if (typeof has_more !== 'boolean') return null;
  if (next_after_display_name !== null && typeof next_after_display_name !== 'string') return null;
  if (next_after_clinic_id !== null && typeof next_after_clinic_id !== 'string') return null;

  const parsedClinics: PublishedClinicSummary[] = [];
  for (const item of clinics) {
    const parsed = parsePublishedClinicRow(item);
    if (parsed === null) return null;
    parsedClinics.push(parsed);
  }

  return {
    clinics: parsedClinics,
    hasMore: has_more,
    next:
      next_after_clinic_id === null
        ? null
        : { displayName: next_after_display_name, clinicId: next_after_clinic_id },
  };
}

/** The cursor that continues after a row: its complete `(name, id)`, never a normalized value. */
export function publishedClinicsCursorOf(clinic: PublishedClinicSummary): PublishedClinicsCursor {
  return { displayName: clinic.displayName, clinicId: clinic.clinicId };
}

/**
 * One keyset page of the published Clinics in alphabetical order, optionally
 * narrowed by name (`null` = no search). The same for anonymous and
 * authenticated callers, and independent of any Clinic having a Location.
 * Omit `after` for the first page; pass back a page's own cursor verbatim.
 */
export async function discoverPublishedClinicsPage(
  search: string | null,
  after: PublishedClinicsCursor | null,
  limit: number = BASIC_DISCOVERY_PAGE_SIZE,
): Promise<ClinicsResult<PublishedClinicsPage>> {
  try {
    const { data, error } = await supabase.rpc('discover_published_clinics', {
      p_search: search,
      p_after_display_name: after?.displayName ?? null,
      p_after_clinic_id: after?.clinicId ?? null,
      p_limit: limit,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    const envelope = parsePublishedClinicsEnvelope(data);

    if (envelope === null) {
      return { data: null, error: 'Unexpected Discovery response shape' };
    }

    return { data: envelope, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Batch profile lookup (Milestone F: Appointment list/detail Clinic display)
// ---------------------------------------------------------------------------

/**
 * Bounded lookup over the same published_clinic_public_profiles view used
 * throughout this module, for the set of distinct Clinic ids an Appointment
 * list/detail screen needs to display — never one request per Appointment
 * row. A Clinic id absent from the result (nonexistent or unpublished,
 * identically — SPEC-DIS-001 non-disclosure) means the caller must fall back
 * to a generic "Clinic unavailable" label: there is no Guardian-facing
 * surface for an unpublished Clinic's display name, and this module
 * deliberately does not add one (no private/internal Clinic lookup).
 */
export async function getPublishedClinicProfilesByIds(
  clinicIds: readonly string[],
): Promise<ClinicsResult<Map<string, ClinicPublicProfile>>> {
  const uniqueIds = [...new Set(clinicIds)];

  if (uniqueIds.length === 0) {
    return { data: new Map(), error: null };
  }

  try {
    const { data, error } = await supabase
      .from('published_clinic_public_profiles')
      .select('clinic_id, display_name, description, public_phone, public_email, website')
      .in('clinic_id', uniqueIds);

    if (error) {
      return { data: null, error: error.message };
    }

    const profiles = new Map<string, ClinicPublicProfile>();
    for (const row of (data ?? []) as ClinicPublicProfileRow[]) {
      const profile = fromClinicPublicProfileRow(row);
      profiles.set(profile.clinicId, profile);
    }

    return { data: profiles, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Geographic Clinic summary (discover_clinics_in_viewport — Map)
// ---------------------------------------------------------------------------

export type GeographicClinicSummary = ClinicPublicProfile & {
  addressText: string;
  latitude: number;
  longitude: number;
};

export type ViewportBounds = {
  minLatitude: number;
  maxLatitude: number;
  minLongitude: number;
  maxLongitude: number;
};

export type GeographicClinicsPage = {
  clinics: GeographicClinicSummary[];
  hasMore: boolean;
  nextAfterClinicId: string | null;
};

function parseGeographicClinicRow(raw: unknown): GeographicClinicSummary | null {
  if (!isRecord(raw)) return null;

  const { clinic_id, display_name, description, public_phone, public_email, website } = raw;
  const { address_text, latitude, longitude } = raw;

  if (typeof clinic_id !== 'string') return null;
  if (typeof address_text !== 'string') return null;
  if (typeof latitude !== 'number' || !Number.isFinite(latitude)) return null;
  if (typeof longitude !== 'number' || !Number.isFinite(longitude)) return null;

  return {
    clinicId: clinic_id,
    displayName: typeof display_name === 'string' ? display_name : null,
    description: typeof description === 'string' ? description : null,
    publicPhone: typeof public_phone === 'string' ? public_phone : null,
    publicEmail: typeof public_email === 'string' ? public_email : null,
    website: typeof website === 'string' ? website : null,
    addressText: address_text,
    latitude,
    longitude,
  };
}

/** Exported for unit testing: validates discover_clinics_in_viewport's jsonb envelope. */
export function parseGeographicClinicsEnvelope(raw: unknown): GeographicClinicsPage | null {
  if (!isRecord(raw)) return null;

  const { clinics, has_more, next_after_clinic_id } = raw;

  if (!Array.isArray(clinics)) return null;
  if (typeof has_more !== 'boolean') return null;
  if (next_after_clinic_id !== null && typeof next_after_clinic_id !== 'string') return null;

  const parsedClinics: GeographicClinicSummary[] = [];
  for (const item of clinics) {
    const parsed = parseGeographicClinicRow(item);
    if (parsed === null) return null;
    parsedClinics.push(parsed);
  }

  return { clinics: parsedClinics, hasMore: has_more, nextAfterClinicId: next_after_clinic_id };
}

/**
 * Single backend page per call — the Map screen never chains
 * next_after_clinic_id automatically; a caller that wants the next page
 * (there isn't one in this milestone's UX) would pass it explicitly.
 */
export async function discoverClinicsInViewport(
  bounds: ViewportBounds,
  after: { clinicId: string } | null,
  limit: number = VIEWPORT_DISCOVERY_PAGE_SIZE,
): Promise<ClinicsResult<GeographicClinicsPage>> {
  try {
    const { data, error } = await supabase.rpc('discover_clinics_in_viewport', {
      p_min_latitude: bounds.minLatitude,
      p_max_latitude: bounds.maxLatitude,
      p_min_longitude: bounds.minLongitude,
      p_max_longitude: bounds.maxLongitude,
      p_limit: limit,
      p_after_clinic_id: after?.clinicId ?? null,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    const envelope = parseGeographicClinicsEnvelope(data);

    if (envelope === null) {
      return { data: null, error: 'Unexpected Discovery response shape' };
    }

    return { data: envelope, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Nearby Clinic summary (discover_nearby_clinics — Nearby)
// ---------------------------------------------------------------------------

export type NearbyClinicSummary = GeographicClinicSummary & { distanceMeters: number };

export type NearbyClinicsPage = {
  clinics: NearbyClinicSummary[];
  hasMore: boolean;
  nextAfterDistanceMeters: number | null;
  nextAfterClinicId: string | null;
};

function parseNearbyClinicRow(raw: unknown): NearbyClinicSummary | null {
  const base = parseGeographicClinicRow(raw);
  if (base === null || !isRecord(raw)) return null;

  const { distance_meters } = raw;
  if (typeof distance_meters !== 'number' || !Number.isFinite(distance_meters)) return null;

  return { ...base, distanceMeters: distance_meters };
}

/** Exported for unit testing: validates discover_nearby_clinics' jsonb envelope. */
export function parseNearbyClinicsEnvelope(raw: unknown): NearbyClinicsPage | null {
  if (!isRecord(raw)) return null;

  const { clinics, has_more, next_after_distance_meters, next_after_clinic_id } = raw;

  if (!Array.isArray(clinics)) return null;
  if (typeof has_more !== 'boolean') return null;
  if (next_after_distance_meters !== null && typeof next_after_distance_meters !== 'number') {
    return null;
  }
  if (next_after_clinic_id !== null && typeof next_after_clinic_id !== 'string') return null;

  const parsedClinics: NearbyClinicSummary[] = [];
  for (const item of clinics) {
    const parsed = parseNearbyClinicRow(item);
    if (parsed === null) return null;
    parsedClinics.push(parsed);
  }

  return {
    clinics: parsedClinics,
    hasMore: has_more,
    nextAfterDistanceMeters: next_after_distance_meters,
    nextAfterClinicId: next_after_clinic_id,
  };
}

/**
 * p_radius_meters is a required caller input (no backend default) — callers
 * pass NEARBY_SEARCH_RADIUS_METERS (src/constants/discovery.ts) explicitly.
 * next_after_distance_meters/next_after_clinic_id must be threaded back
 * verbatim for continuation; this never re-derives or re-sorts them.
 */
export async function discoverNearbyClinics(
  reference: { latitude: number; longitude: number },
  radiusMeters: number,
  after: { distanceMeters: number; clinicId: string } | null,
  limit: number = NEARBY_DISCOVERY_PAGE_SIZE,
): Promise<ClinicsResult<NearbyClinicsPage>> {
  try {
    const { data, error } = await supabase.rpc('discover_nearby_clinics', {
      p_latitude: reference.latitude,
      p_longitude: reference.longitude,
      p_radius_meters: radiusMeters,
      p_limit: limit,
      p_after_distance_meters: after?.distanceMeters ?? null,
      p_after_clinic_id: after?.clinicId ?? null,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    const envelope = parseNearbyClinicsEnvelope(data);

    if (envelope === null) {
      return { data: null, error: 'Unexpected Discovery response shape' };
    }

    return { data: envelope, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Location (get_published_clinic_location)
// ---------------------------------------------------------------------------

export type ClinicLocation = {
  clinicId: string;
  addressText: string;
  latitude: number;
  longitude: number;
};

type ClinicLocationRow = {
  clinic_id: string;
  address_text: string;
  latitude: number;
  longitude: number;
};

export function fromClinicLocationRow(row: ClinicLocationRow): ClinicLocation {
  return {
    clinicId: row.clinic_id,
    addressText: row.address_text,
    latitude: row.latitude,
    longitude: row.longitude,
  };
}

/**
 * At most one row; a nonexistent/unpublished Clinic and — at the mobile
 * composition level — a published Clinic without a current Location are all
 * treated the same way: `data: null` with no error, never a distinguishing
 * message (SPEC-DIS-001 non-disclosure; see the module doc comment above).
 */
export async function getPublishedClinicLocation(
  clinicId: string,
): Promise<ClinicsResult<ClinicLocation | null>> {
  try {
    const { data, error } = await supabase.rpc('get_published_clinic_location', {
      p_clinic_id: clinicId,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    const rows = (data ?? []) as ClinicLocationRow[];
    return { data: rows.length > 0 ? fromClinicLocationRow(rows[0]) : null, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Service offerings (get_published_clinic_service_offerings)
// ---------------------------------------------------------------------------

/** The clinic_service_offerings_category_check codes (SPEC-CLI-005 §3). */
export const CLINIC_SERVICE_CATEGORIES = [
  'GENERAL_CONSULTATION',
  'VACCINATION',
  'SURGERY',
  'DENTISTRY',
  'DIAGNOSTIC_IMAGING',
  'LABORATORY',
  'EMERGENCY_CARE',
  'HOSPITALIZATION',
  'OTHER',
] as const;

export type ClinicServiceCategory = (typeof CLINIC_SERVICE_CATEGORIES)[number];

export type ClinicServiceOffering = {
  /**
   * Kept as the raw string the backend returned, not narrowed to
   * ClinicServiceCategory: a code this client doesn't know yet must still
   * load, and lib/clinic-service-display.ts resolves it to a generic label.
   */
  serviceCategory: string;
  publicDescription: string | null;
};

type ClinicServiceOfferingRow = {
  service_category: string;
  public_description: string | null;
};

export function fromClinicServiceOfferingRow(row: ClinicServiceOfferingRow): ClinicServiceOffering {
  return {
    serviceCategory: row.service_category,
    publicDescription: row.public_description,
  };
}

export async function getPublishedClinicServiceOfferings(
  clinicId: string,
): Promise<ClinicsResult<ClinicServiceOffering[]>> {
  try {
    const { data, error } = await supabase.rpc('get_published_clinic_service_offerings', {
      p_clinic_id: clinicId,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return {
      data: ((data ?? []) as ClinicServiceOfferingRow[]).map(fromClinicServiceOfferingRow),
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Opening hours (get_published_clinic_opening_hours)
// ---------------------------------------------------------------------------

export type ClinicOpeningPeriod = { isoWeekday: number; startTime: string; endTime: string };

export type ClinicOpeningException = {
  localDate: string;
  exceptionKind: string;
  startTime: string | null;
  endTime: string | null;
};

export type ClinicOpeningHours = {
  schedulingTimezoneName: string;
  recurringPeriods: ClinicOpeningPeriod[];
  exceptions: ClinicOpeningException[];
};

type ClinicOpeningHoursRow = {
  scheduling_timezone_name: string;
  recurring_periods: unknown;
  exceptions: unknown;
};

function parseOpeningPeriod(raw: unknown): ClinicOpeningPeriod | null {
  if (!isRecord(raw)) return null;
  const { iso_weekday, start_time, end_time } = raw;

  if (typeof iso_weekday !== 'number') return null;
  if (typeof start_time !== 'string') return null;
  if (typeof end_time !== 'string') return null;

  return { isoWeekday: iso_weekday, startTime: start_time, endTime: end_time };
}

function parseOpeningException(raw: unknown): ClinicOpeningException | null {
  if (!isRecord(raw)) return null;
  const { local_date, exception_kind, start_time, end_time } = raw;

  if (typeof local_date !== 'string') return null;
  if (typeof exception_kind !== 'string') return null;
  if (start_time !== null && typeof start_time !== 'string') return null;
  if (end_time !== null && typeof end_time !== 'string') return null;

  return {
    localDate: local_date,
    exceptionKind: exception_kind,
    startTime: start_time ?? null,
    endTime: end_time ?? null,
  };
}

/** Exported for unit testing: validates the two jsonb array columns. */
export function fromClinicOpeningHoursRow(row: ClinicOpeningHoursRow): ClinicOpeningHours | null {
  if (!Array.isArray(row.recurring_periods) || !Array.isArray(row.exceptions)) return null;

  const recurringPeriods: ClinicOpeningPeriod[] = [];
  for (const item of row.recurring_periods) {
    const parsed = parseOpeningPeriod(item);
    if (parsed === null) return null;
    recurringPeriods.push(parsed);
  }

  const exceptions: ClinicOpeningException[] = [];
  for (const item of row.exceptions) {
    const parsed = parseOpeningException(item);
    if (parsed === null) return null;
    exceptions.push(parsed);
  }

  return { schedulingTimezoneName: row.scheduling_timezone_name, recurringPeriods, exceptions };
}

export async function getPublishedClinicOpeningHours(
  clinicId: string,
): Promise<ClinicsResult<ClinicOpeningHours | null>> {
  try {
    const { data, error } = await supabase.rpc('get_published_clinic_opening_hours', {
      p_clinic_id: clinicId,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    const rows = (data ?? []) as ClinicOpeningHoursRow[];
    if (rows.length === 0) {
      return { data: null, error: null };
    }

    const parsed = fromClinicOpeningHoursRow(rows[0]);
    if (parsed === null) {
      return { data: null, error: 'Unexpected opening-hours response shape' };
    }

    return { data: parsed, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// Clinic detail composition (/clinics/[id])
// ---------------------------------------------------------------------------

export type ClinicDetail = {
  profile: ClinicPublicProfile;
  location: ClinicLocation | null;
  serviceOfferings: ClinicServiceOffering[];
  openingHours: ClinicOpeningHours | null;
};

/**
 * published_clinic_public_profiles is the existence/eligibility gate, not
 * get_published_clinic_location: a published Clinic is not guaranteed to
 * expose Location at this composition level, and only the profile view's
 * own join/WHERE gives the required "nonexistent and unpublished are
 * identical" non-disclosure behavior. The remaining three reads only run
 * once that gate returns a row, and are independent of one another.
 */
export async function getPublishedClinicDetail(
  clinicId: string,
): Promise<ClinicsResult<ClinicDetail | null>> {
  try {
    const { data: profileRow, error: profileError } = await supabase
      .from('published_clinic_public_profiles')
      .select('clinic_id, display_name, description, public_phone, public_email, website')
      .eq('clinic_id', clinicId)
      .maybeSingle();

    if (profileError) {
      return { data: null, error: profileError.message };
    }

    if (!profileRow) {
      return { data: null, error: null };
    }

    const profile = fromClinicPublicProfileRow(profileRow as ClinicPublicProfileRow);

    const [locationResult, serviceOfferingsResult, openingHoursResult] = await Promise.all([
      getPublishedClinicLocation(clinicId),
      getPublishedClinicServiceOfferings(clinicId),
      getPublishedClinicOpeningHours(clinicId),
    ]);

    if (locationResult.error !== null) {
      return { data: null, error: locationResult.error };
    }
    if (serviceOfferingsResult.error !== null) {
      return { data: null, error: serviceOfferingsResult.error };
    }
    if (openingHoursResult.error !== null) {
      return { data: null, error: openingHoursResult.error };
    }

    return {
      data: {
        profile,
        location: locationResult.data,
        serviceOfferings: serviceOfferingsResult.data,
        openingHours: openingHoursResult.data,
      },
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

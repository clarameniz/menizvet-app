import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the managed Clinic configuration read of Clinic self-service
 * (SPEC-CLI-007 BR-1–BR-6; migration 20261023090000_managed_clinic_profile_read.sql).
 * Granted to authenticated and re-authorized by the backend on every call —
 * nothing here is a permission check.
 *
 * `get_managed_clinic_profile(p_clinic_id uuid) returns jsonb`:
 *
 *   { "clinic_id": uuid,
 *     "is_published": boolean,
 *     "scheduling_timezone_name": text | null,
 *     "public_profile": null | { "display_name", "description", "public_phone",
 *                                "public_email", "website" },   // each text | null
 *     "location": null | { "address_text": text, "latitude": float8,
 *                          "longitude": float8 } }
 *
 * Every member is always present. Needs one of CLINIC_MANAGE_PUBLIC_PROFILE,
 * _LOCATION, _PUBLICATION, or _OPENING_HOURS; no Entitlement and no
 * publication, so an unpublished Clinic is readable.
 *
 * The payload is parsed strictly: a missing member, a wrong type, `null`
 * where the Spec does not allow it, blank stored text, a non-finite or
 * out-of-range coordinate, or another Clinic's id rejects the whole payload
 * as CLINIC_SETTINGS_MALFORMED. Absent configuration stays absent (`null`) —
 * it is never defaulted to empty text, coordinates, the device timezone, or
 * "not published". Stored text is kept exactly as returned. Members this
 * version does not know are ignored, so an additive backend change does not
 * break the screen.
 *
 * SQLSTATE 28000 is normalized to PROFESSIONAL_CONTEXT_AUTH_REQUIRED; 42501 —
 * returned alike for a missing capability and an unknown Clinic (BR-4) — to
 * CLINIC_SETTINGS_ACCESS_DENIED. Every call settles into `{data, error}` and
 * nothing is retried.
 */
export type ClinicSettingsResult<T> = { data: T; error: null } | { data: null; error: string };

export const CLINIC_SETTINGS_ACCESS_DENIED = 'CLINIC_SETTINGS_ACCESS_DENIED';
export const CLINIC_SETTINGS_MALFORMED = 'CLINIC_SETTINGS_MALFORMED';
/** A write this client refused to send (it could never be valid). */
export const CLINIC_SETTINGS_INVALID_REQUEST = 'CLINIC_SETTINGS_INVALID_REQUEST';

/** The stored public profile. Each value is `null` when absent. */
export type ManagedClinicPublicProfile = {
  displayName: string | null;
  description: string | null;
  publicPhone: string | null;
  publicEmail: string | null;
  website: string | null;
};

/** The stored location: public address text and the map position used by Discovery. */
export type ManagedClinicLocation = {
  addressText: string;
  latitude: number;
  longitude: number;
};

export type ManagedClinicProfile = {
  clinicId: string;
  isPublished: boolean;
  /** `null` until a scheduling timezone is configured; stored text, not validated here. */
  schedulingTimezoneName: string | null;
  /** `null` when the Clinic has no stored public profile. */
  publicProfile: ManagedClinicPublicProfile | null;
  /** `null` when the Clinic has no stored location. */
  location: ManagedClinicLocation | null;
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Marks a member as malformed; distinct from a legitimately absent (`null`) value. */
const MALFORMED = Symbol('malformed');

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasMembers(record: Record<string, unknown>, members: readonly string[]): boolean {
  return members.every((member) => Object.prototype.hasOwnProperty.call(record, member));
}

/** Stored text is never blank (the backend trims and rejects blanks). */
function isStoredText(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function optionalText(value: unknown): string | null | typeof MALFORMED {
  if (value === null) return null;
  return isStoredText(value) ? value : MALFORMED;
}

function isCoordinate(value: unknown, bound: number): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= -bound && value <= bound;
}

const PROFILE_MEMBERS = [
  'display_name',
  'description',
  'public_phone',
  'public_email',
  'website',
] as const;

function parsePublicProfile(raw: unknown): ManagedClinicPublicProfile | null | typeof MALFORMED {
  if (raw === null) return null;
  if (!isRecord(raw) || !hasMembers(raw, PROFILE_MEMBERS)) return MALFORMED;
  const displayName = optionalText(raw.display_name);
  const description = optionalText(raw.description);
  const publicPhone = optionalText(raw.public_phone);
  const publicEmail = optionalText(raw.public_email);
  const website = optionalText(raw.website);
  if (
    displayName === MALFORMED ||
    description === MALFORMED ||
    publicPhone === MALFORMED ||
    publicEmail === MALFORMED ||
    website === MALFORMED
  ) {
    return MALFORMED;
  }
  return { displayName, description, publicPhone, publicEmail, website };
}

function parseLocation(raw: unknown): ManagedClinicLocation | null | typeof MALFORMED {
  if (raw === null) return null;
  if (!isRecord(raw) || !hasMembers(raw, ['address_text', 'latitude', 'longitude'])) {
    return MALFORMED;
  }
  const { address_text, latitude, longitude } = raw;
  if (!isStoredText(address_text) || !isCoordinate(latitude, 90) || !isCoordinate(longitude, 180)) {
    return MALFORMED;
  }
  return { addressText: address_text, latitude, longitude };
}

/**
 * Exported for unit testing: validates the read's payload for the requested
 * Clinic. `null` means malformed — never "not configured".
 */
export function parseManagedClinicProfile(
  raw: unknown,
  expectedClinicId: string,
): ManagedClinicProfile | null {
  if (
    !isRecord(raw) ||
    !hasMembers(raw, [
      'clinic_id',
      'is_published',
      'scheduling_timezone_name',
      'public_profile',
      'location',
    ])
  ) {
    return null;
  }
  const { clinic_id, is_published, scheduling_timezone_name } = raw;

  if (
    typeof clinic_id !== 'string' ||
    !UUID_PATTERN.test(clinic_id) ||
    clinic_id.toLowerCase() !== expectedClinicId.toLowerCase()
  ) {
    return null;
  }
  if (typeof is_published !== 'boolean') return null;

  const schedulingTimezoneName = optionalText(scheduling_timezone_name);
  const publicProfile = parsePublicProfile(raw.public_profile);
  const location = parseLocation(raw.location);
  if (
    schedulingTimezoneName === MALFORMED ||
    publicProfile === MALFORMED ||
    location === MALFORMED
  ) {
    return null;
  }

  return {
    clinicId: clinic_id,
    isPublished: is_published,
    schedulingTimezoneName,
    publicProfile,
    location,
  };
}

// ---------------------------------------------------------------------------
// RPC
// ---------------------------------------------------------------------------

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

/** Settles a write RPC that returns the Clinic id. */
async function settleWrite(
  clinicId: string,
  call: () => PromiseLike<{ data: unknown; error: { code?: string; message: string } | null }>,
): Promise<ClinicSettingsResult<null>> {
  try {
    const { data, error } = await call();
    if (error) {
      // Backend text is kept for the i18n mapper only; it never reaches the UI.
      return {
        data: null,
        error: error.code === '28000' ? PROFESSIONAL_CONTEXT_AUTH_REQUIRED : error.message,
      };
    }
    if (typeof data !== 'string' || data.toLowerCase() !== clinicId.toLowerCase()) {
      return { data: null, error: CLINIC_SETTINGS_MALFORMED };
    }
    return { data: null, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/**
 * Replaces the Clinic's whole public profile (SPEC-CLI-004 BR-15–BR-17):
 * `set_clinic_public_profile(p_clinic_id, p_display_name, p_description,
 * p_public_phone, p_public_email, p_website)`. All five values are always
 * sent — `null` for absent — because one save replaces all of them. Needs
 * CLINIC_MANAGE_PUBLIC_PROFILE; last-write-wins (BR-19).
 */
export async function saveClinicPublicProfile(
  clinicId: string,
  profile: ManagedClinicPublicProfile,
): Promise<ClinicSettingsResult<null>> {
  if (!UUID_PATTERN.test(clinicId)) return { data: null, error: CLINIC_SETTINGS_INVALID_REQUEST };

  return settleWrite(clinicId, () =>
    supabase.rpc('set_clinic_public_profile', {
      p_clinic_id: clinicId,
      p_display_name: profile.displayName,
      p_description: profile.description,
      p_public_phone: profile.publicPhone,
      p_public_email: profile.publicEmail,
      p_website: profile.website,
    }),
  );
}

/**
 * Establishes or replaces the Clinic's whole location (SPEC-CLI-002 BR-12,
 * BR-14): `set_clinic_location(p_clinic_id, p_address_text, p_latitude,
 * p_longitude)`. Needs CLINIC_MANAGE_LOCATION; last-write-wins (BR-16).
 * A location that could never be valid is not sent.
 */
export async function saveClinicLocation(
  clinicId: string,
  location: ManagedClinicLocation,
): Promise<ClinicSettingsResult<null>> {
  if (
    !UUID_PATTERN.test(clinicId) ||
    location.addressText.length === 0 ||
    !isCoordinate(location.latitude, 90) ||
    !isCoordinate(location.longitude, 180)
  ) {
    return { data: null, error: CLINIC_SETTINGS_INVALID_REQUEST };
  }

  return settleWrite(clinicId, () =>
    supabase.rpc('set_clinic_location', {
      p_clinic_id: clinicId,
      p_address_text: location.addressText,
      p_latitude: location.latitude,
      p_longitude: location.longitude,
    }),
  );
}

/**
 * Sets the Clinic's scheduling timezone (SPEC-APT-013 BR-76):
 * `set_clinic_scheduling_timezone(p_clinic_id, p_timezone_name)`. Needs
 * CLINIC_MANAGE_OPENING_HOURS; BR-56 may additionally require
 * PROFESSIONAL_SCHEDULING. Always sends a named timezone — never clears it.
 */
export async function saveClinicSchedulingTimezone(
  clinicId: string,
  timezoneName: string,
): Promise<ClinicSettingsResult<null>> {
  if (!UUID_PATTERN.test(clinicId) || !isStoredText(timezoneName)) {
    return { data: null, error: CLINIC_SETTINGS_INVALID_REQUEST };
  }

  return settleWrite(clinicId, () =>
    supabase.rpc('set_clinic_scheduling_timezone', {
      p_clinic_id: clinicId,
      p_timezone_name: timezoneName,
    }),
  );
}

/**
 * Publishes the Clinic (SPEC-CLI-003 BR-15): `publish_clinic(p_clinic_id)`.
 * Needs CLINIC_MANAGE_PUBLICATION; requires a display name and a location;
 * idempotent.
 */
export async function publishClinic(clinicId: string): Promise<ClinicSettingsResult<null>> {
  if (!UUID_PATTERN.test(clinicId)) return { data: null, error: CLINIC_SETTINGS_INVALID_REQUEST };
  return settleWrite(clinicId, () => supabase.rpc('publish_clinic', { p_clinic_id: clinicId }));
}

/**
 * Unpublishes the Clinic (SPEC-CLI-003 BR-16): `unpublish_clinic(p_clinic_id)`.
 * Needs CLINIC_MANAGE_PUBLICATION; changes only the publication state;
 * idempotent.
 */
export async function unpublishClinic(clinicId: string): Promise<ClinicSettingsResult<null>> {
  if (!UUID_PATTERN.test(clinicId)) return { data: null, error: CLINIC_SETTINGS_INVALID_REQUEST };
  return settleWrite(clinicId, () => supabase.rpc('unpublish_clinic', { p_clinic_id: clinicId }));
}

/** Reads the Clinic's current self-service configuration (SPEC-CLI-007 BR-1). */
export async function getManagedClinicProfile(
  clinicId: string,
): Promise<ClinicSettingsResult<ManagedClinicProfile>> {
  if (!UUID_PATTERN.test(clinicId)) return { data: null, error: CLINIC_SETTINGS_ACCESS_DENIED };

  try {
    const { data, error } = await supabase.rpc('get_managed_clinic_profile', {
      p_clinic_id: clinicId,
    });
    if (error) {
      if (error.code === '28000') return { data: null, error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED };
      if (error.code === '42501') return { data: null, error: CLINIC_SETTINGS_ACCESS_DENIED };
      return { data: null, error: error.message };
    }

    const profile = parseManagedClinicProfile(data, clinicId);
    if (profile === null) return { data: null, error: CLINIC_SETTINGS_MALFORMED };
    return { data: profile, error: null };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

/**
 * Combines the Request Appointment screen's independent initial reads
 * (Clinic public profile, Clinic opening hours, the Guardian's Pet list)
 * into one load outcome.
 *
 * Unlike the full ClinicDetail composition /clinics/[id] uses
 * (data/clinics.ts's getPublishedClinicDetail, which also fetches Location
 * and Service Offerings), this screen only ever reads the Clinic's public
 * profile (display name) and opening hours (scheduling timezone) directly —
 * neither Location nor Service Offerings is used here, so a failure in
 * either of those unrelated, unused reads can never force this screen into
 * its fatal "could not load clinic information" state. Both remaining reads
 * already independently gate on publication server-side
 * (get_published_clinic_opening_hours's own WHERE clause; the
 * published_clinic_public_profiles view underlying getPublishedClinicProfilesByIds),
 * so a nonexistent and an unpublished Clinic are indistinguishable here,
 * exactly as SPEC-DIS-001 requires — clinicNotFound covers both.
 *
 * A Pet-list failure never escalates to the fatal state either: the two
 * Clinic reads succeeding is what "enough Clinic context to render the
 * request screen" means for this screen. The Pet list instead degrades to
 * the same empty list a Guardian with zero registered Pets already sees,
 * distinguished only by petsLoadFailed so the screen can show a
 * connectivity-specific message instead of the misleading "register a pet"
 * prompt.
 */
import type { ClinicOpeningHours, ClinicPublicProfile, ClinicsResult } from '@/data/clinics';
import type { Pet, PetsResult } from '@/data/pets';

export type RequestAppointmentInitialLoad =
  | { status: 'fatalError' }
  | { status: 'clinicNotFound' }
  | {
      status: 'loaded';
      clinicName: string | null;
      schedulingTimezoneName: string;
      pets: Pet[];
      petsLoadFailed: boolean;
    };

export function resolveRequestAppointmentInitialLoad(
  clinicId: string,
  profilesResult: ClinicsResult<Map<string, ClinicPublicProfile>>,
  openingHoursResult: ClinicsResult<ClinicOpeningHours | null>,
  petsResult: PetsResult<Pet[]>,
): RequestAppointmentInitialLoad {
  if (profilesResult.error !== null || openingHoursResult.error !== null) {
    return { status: 'fatalError' };
  }

  const profile = profilesResult.data.get(clinicId) ?? null;
  const openingHours = openingHoursResult.data;

  if (!profile || !openingHours) {
    return { status: 'clinicNotFound' };
  }

  return {
    status: 'loaded',
    clinicName: profile.displayName,
    schedulingTimezoneName: openingHours.schedulingTimezoneName,
    pets: petsResult.error !== null ? [] : petsResult.data,
    petsLoadFailed: petsResult.error !== null,
  };
}

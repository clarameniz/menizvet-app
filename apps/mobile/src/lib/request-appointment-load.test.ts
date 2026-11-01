import { resolveRequestAppointmentInitialLoad } from '@/lib/request-appointment-load';
import type { ClinicOpeningHours, ClinicPublicProfile, ClinicsResult } from '@/data/clinics';
import type { Pet, PetsResult } from '@/data/pets';

const CLINIC_ID = 'clinic-1';

const PROFILE: ClinicPublicProfile = {
  clinicId: CLINIC_ID,
  displayName: 'Animalia Madrid Centro',
  description: null,
  publicPhone: null,
  publicEmail: null,
  website: null,
};

const OPENING_HOURS: ClinicOpeningHours = {
  schedulingTimezoneName: 'Europe/Madrid',
  recurringPeriods: [],
  exceptions: [],
};

const PET: Pet = {
  id: 'pet-1',
  name: 'Luna',
  species: 'Dog',
  breed: null,
  sex: null,
  dateOfBirth: null,
  approximateDateOfBirth: null,
  microchipIdentifier: null,
  profileImageReference: null,
  behavioralSafetyInformation: null,
  profileRevision: 1,
  createdAt: '2026-01-01T00:00:00.000Z',
};

const okProfiles: ClinicsResult<Map<string, ClinicPublicProfile>> = {
  data: new Map([[CLINIC_ID, PROFILE]]),
  error: null,
};
const okOpeningHours: ClinicsResult<ClinicOpeningHours | null> = {
  data: OPENING_HOURS,
  error: null,
};
const okPets: PetsResult<Pet[]> = { data: [PET], error: null };
const failedPets: PetsResult<Pet[]> = { data: null, error: 'Network request failed' };

describe('resolveRequestAppointmentInitialLoad', () => {
  it('loads normally when every read succeeds', () => {
    expect(
      resolveRequestAppointmentInitialLoad(CLINIC_ID, okProfiles, okOpeningHours, okPets),
    ).toEqual({
      status: 'loaded',
      clinicName: 'Animalia Madrid Centro',
      schedulingTimezoneName: 'Europe/Madrid',
      pets: [PET],
      petsLoadFailed: false,
    });
  });

  it('does not force the fatal Clinic-load state when only the Pet list fails (offline candidate/network failure)', () => {
    const result = resolveRequestAppointmentInitialLoad(
      CLINIC_ID,
      okProfiles,
      okOpeningHours,
      failedPets,
    );

    expect(result).toEqual({
      status: 'loaded',
      clinicName: 'Animalia Madrid Centro',
      schedulingTimezoneName: 'Europe/Madrid',
      pets: [],
      petsLoadFailed: true,
    });
  });

  it('is fatal when the Clinic profile read fails, even if Pets and opening hours succeed', () => {
    const failedProfiles: ClinicsResult<Map<string, ClinicPublicProfile>> = {
      data: null,
      error: 'Network request failed',
    };

    expect(
      resolveRequestAppointmentInitialLoad(CLINIC_ID, failedProfiles, okOpeningHours, okPets),
    ).toEqual({ status: 'fatalError' });
  });

  it('is fatal when the opening-hours read fails, even if the profile and Pets succeed', () => {
    const failedOpeningHours: ClinicsResult<ClinicOpeningHours | null> = {
      data: null,
      error: 'Network request failed',
    };

    expect(
      resolveRequestAppointmentInitialLoad(CLINIC_ID, okProfiles, failedOpeningHours, okPets),
    ).toEqual({ status: 'fatalError' });
  });

  it('treats a nonexistent/unpublished Clinic (absent profile) as clinicNotFound, not fatal', () => {
    const emptyProfiles: ClinicsResult<Map<string, ClinicPublicProfile>> = {
      data: new Map(),
      error: null,
    };

    expect(
      resolveRequestAppointmentInitialLoad(CLINIC_ID, emptyProfiles, okOpeningHours, okPets),
    ).toEqual({ status: 'clinicNotFound' });
  });

  it('treats a Clinic with no current opening hours as clinicNotFound, not fatal', () => {
    const noOpeningHours: ClinicsResult<ClinicOpeningHours | null> = { data: null, error: null };

    expect(
      resolveRequestAppointmentInitialLoad(CLINIC_ID, okProfiles, noOpeningHours, okPets),
    ).toEqual({ status: 'clinicNotFound' });
  });
});

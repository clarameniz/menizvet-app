import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  CLINIC_SETTINGS_MALFORMED,
  type ManagedClinicProfile,
} from '@/data/clinic-settings';
import type { ProfessionalClinics } from '@/data/professional-clinics';
import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  type ProfessionalCapability,
} from '@/data/professional-context';
import { clinicSettingsEditorReadFrom } from '@/hooks/use-clinic-settings-editor';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const CLINIC_ID = 'c-1';

const clinics = (capabilities: ProfessionalCapability[]): ProfessionalClinics => ({
  clinics: [
    {
      clinicId: CLINIC_ID,
      clinicDisplayName: 'Animalia',
      organizationId: 'o-1',
      organizationDisplayName: 'Animalia Group',
      capabilities,
      unknownCapabilities: [],
    },
  ],
});

const profile: ManagedClinicProfile = {
  clinicId: CLINIC_ID,
  isPublished: false,
  schedulingTimezoneName: null,
  publicProfile: null,
  location: null,
};

const ok = <T>(data: T) => ({ data, error: null });
const failed = (error: string) => ({ data: null, error });

describe('clinicSettingsEditorReadFrom', () => {
  it('loads an editor the User holds the capability for', () => {
    const list = clinics(['CLINIC_MANAGE_PUBLIC_PROFILE']);
    expect(clinicSettingsEditorReadFrom(CLINIC_ID, 'profile', ok(list), ok(profile))).toEqual({
      kind: 'loaded',
      clinic: list.clinics[0],
      profile,
    });
  });

  it("is unavailable without the editor's own capability, even with another settings capability", () => {
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'profile',
        ok(clinics(['CLINIC_MANAGE_LOCATION'])),
        ok(profile),
      ),
    ).toEqual({ kind: 'unavailable' });
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'location',
        ok(clinics(['CLINIC_MANAGE_PUBLIC_PROFILE', 'CLINIC_MANAGE_PUBLICATION'])),
        ok(profile),
      ),
    ).toEqual({ kind: 'unavailable' });
  });

  it('is unavailable for a Clinic no longer listed', () => {
    expect(
      clinicSettingsEditorReadFrom(
        'c-2',
        'location',
        ok(clinics(['CLINIC_MANAGE_LOCATION'])),
        ok(profile),
      ),
    ).toEqual({ kind: 'unavailable' });
  });

  it('is unavailable when the managed read is denied (unknown and inaccessible alike)', () => {
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'location',
        ok(clinics(['CLINIC_MANAGE_LOCATION'])),
        failed(CLINIC_SETTINGS_ACCESS_DENIED),
      ),
    ).toEqual({ kind: 'unavailable' });
  });

  it.each([
    [CLINIC_SETTINGS_MALFORMED, 'clinicSettings.loadError'],
    ['Network request failed', 'clinicSettings.loadError'],
    [PROFESSIONAL_CONTEXT_AUTH_REQUIRED, 'errors.sessionExpired'],
  ])('shows a load error, never invented data, when the managed read fails (%s)', (error, key) => {
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'profile',
        ok(clinics(['CLINIC_MANAGE_PUBLIC_PROFILE'])),
        failed(error),
      ),
    ).toEqual({ kind: 'error', messageKey: key });
  });

  it('shows the Clinic list error when it cannot be read', () => {
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'profile',
        failed('Network request failed'),
        ok(profile),
      ),
    ).toEqual({ kind: 'error', messageKey: 'professionalClinics.loadError' });
  });
});

describe('clinicSettingsEditorReadFrom — timezone editor', () => {
  it('needs CLINIC_MANAGE_OPENING_HOURS; a Receptionist who manages Appointment hours gets no editor', () => {
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'timezone',
        ok(clinics(['CLINIC_MANAGE_OPENING_HOURS'])),
        ok(profile),
      ),
    ).toMatchObject({ kind: 'loaded' });
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'timezone',
        ok(clinics(['APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE'])),
        ok(profile),
      ),
    ).toEqual({ kind: 'unavailable' });
    expect(
      clinicSettingsEditorReadFrom(
        CLINIC_ID,
        'timezone',
        ok(clinics(['CLINIC_MANAGE_PUBLICATION'])),
        ok(profile),
      ),
    ).toEqual({ kind: 'unavailable' });
  });
});

import {
  APPOINTMENT_HOURS_ACCESS_DENIED,
  APPOINTMENT_HOURS_MALFORMED,
  type ClinicAppointmentHours,
} from '@/data/clinic-appointment-hours';
import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  CLINIC_SETTINGS_MALFORMED,
  type ManagedClinicProfile,
} from '@/data/clinic-settings';
import type { ProfessionalClinics } from '@/data/professional-clinics';
import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_CONTEXT_MALFORMED,
  type ProfessionalContext,
} from '@/data/professional-context';
import { clinicSettingsReadFrom } from '@/hooks/use-clinic-settings';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const CLINIC_ID = 'c-1';

const clinics = (capabilities: ProfessionalClinics['clinics'][number]['capabilities']) => ({
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
const administrator = clinics([
  'APPOINTMENT_MANAGE_AVAILABILITY',
  'CLINIC_MANAGE_LOCATION',
  'CLINIC_MANAGE_OPENING_HOURS',
  'CLINIC_MANAGE_PUBLICATION',
  'CLINIC_MANAGE_PUBLIC_PROFILE',
]);

const context = (appointmentManagement: boolean): ProfessionalContext => ({
  hasVeterinarianProfessionalProfile: false,
  organizations: [
    {
      membershipId: 'm-1',
      organizationId: 'o-1',
      organizationDisplayName: 'Animalia Group',
      responsibilities: [],
      capabilities: [],
      unknownCapabilities: [],
      clinicAssignments: [],
      entitlements: {
        APPOINTMENT_MANAGEMENT: appointmentManagement,
        PROFESSIONAL_SCHEDULING: true,
        CLINICAL_CARE: false,
        CLINICAL_DOCUMENTATION: false,
      },
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

const hours: ClinicAppointmentHours = {
  schedulingTimezoneName: null,
  standardAppointmentDurationMinutes: null,
  recurringPeriods: [],
  weeklyAvailabilityRevision: 0,
  exceptions: [],
};

const ok = <T>(data: T) => ({ data, error: null });
const failed = (error: string) => ({ data: null, error });

describe('clinicSettingsReadFrom', () => {
  it('loads every input when all reads succeed', () => {
    expect(
      clinicSettingsReadFrom(
        CLINIC_ID,
        ok(administrator),
        ok(context(true)),
        ok(profile),
        ok(hours),
      ),
    ).toEqual({
      kind: 'loaded',
      clinic: administrator.clinics[0],
      profile,
      scheduling: { kind: 'known', hours },
      appointmentManagement: true,
      appointmentHoursAccess: 'editable',
      subscriptionStatusAccess: false,
    });
  });

  it('offers the Subscription status only with advisory ORGANIZATION_MANAGE_SUBSCRIPTION', () => {
    const owner = context(false);
    owner.organizations[0].capabilities = [
      { capability: 'ORGANIZATION_MANAGE_SUBSCRIPTION', scope: { type: 'ORGANIZATION' } },
    ];
    const read = clinicSettingsReadFrom(
      CLINIC_ID,
      ok(administrator),
      ok(owner),
      ok(profile),
      ok(hours),
    );
    expect(read.kind === 'loaded' && read.subscriptionStatusAccess).toBe(true);
    const unreadable = clinicSettingsReadFrom(
      CLINIC_ID,
      ok(administrator),
      failed('network'),
      ok(profile),
      ok(hours),
    );
    expect(unreadable.kind === 'loaded' && unreadable.subscriptionStatusAccess).toBe(false);
  });

  it('carries a missing APPOINTMENT_MANAGEMENT as false', () => {
    const read = clinicSettingsReadFrom(
      CLINIC_ID,
      ok(administrator),
      ok(context(false)),
      ok(profile),
      ok(hours),
    );
    expect(read).toMatchObject({ kind: 'loaded', appointmentManagement: false });
  });

  it.each([
    ['Network request failed'],
    [APPOINTMENT_HOURS_MALFORMED],
    [APPOINTMENT_HOURS_ACCESS_DENIED],
  ])(
    'keeps the Clinic settings and marks scheduling unknown when Appointment hours fails (%s)',
    (error) => {
      const read = clinicSettingsReadFrom(
        CLINIC_ID,
        ok(administrator),
        ok(context(true)),
        ok(profile),
        failed(error),
      );
      expect(read).toMatchObject({ kind: 'loaded', profile, scheduling: { kind: 'unknown' } });
    },
  );

  it.each([['Network request failed'], [PROFESSIONAL_CONTEXT_MALFORMED]])(
    'keeps the Clinic settings with an unknown Entitlement when the context fails (%s)',
    (error) => {
      const read = clinicSettingsReadFrom(
        CLINIC_ID,
        ok(administrator),
        failed(error),
        ok(profile),
        ok(hours),
      );
      expect(read).toMatchObject({
        kind: 'loaded',
        appointmentManagement: null,
        appointmentHoursAccess: 'unconfirmed',
        subscriptionStatusAccess: false,
      });
    },
  );

  it.each([['Network request failed'], [CLINIC_SETTINGS_MALFORMED]])(
    'shows a load error, never partial data, when the managed Clinic read fails (%s)',
    (error) => {
      expect(
        clinicSettingsReadFrom(
          CLINIC_ID,
          ok(administrator),
          ok(context(true)),
          failed(error),
          ok(hours),
        ),
      ).toEqual({ kind: 'error', messageKey: 'clinicSettings.loadError' });
    },
  );

  it('is unavailable when the managed read is denied', () => {
    expect(
      clinicSettingsReadFrom(
        CLINIC_ID,
        ok(administrator),
        ok(context(true)),
        failed(CLINIC_SETTINGS_ACCESS_DENIED),
        ok(hours),
      ),
    ).toEqual({ kind: 'unavailable' });
  });

  it('is unavailable for a Clinic not listed or without a Clinic settings capability', () => {
    const receptionist = clinics(['APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE']);
    expect(
      clinicSettingsReadFrom(
        CLINIC_ID,
        ok(receptionist),
        ok(context(true)),
        ok(profile),
        ok(hours),
      ),
    ).toEqual({ kind: 'unavailable' });
    expect(
      clinicSettingsReadFrom('c-2', ok(administrator), ok(context(true)), ok(profile), ok(hours)),
    ).toEqual({ kind: 'unavailable' });
  });

  it('shows the Clinic list error when it cannot be read', () => {
    expect(
      clinicSettingsReadFrom(
        CLINIC_ID,
        failed('Network request failed'),
        ok(context(true)),
        ok(profile),
        ok(hours),
      ),
    ).toEqual({ kind: 'error', messageKey: 'professionalClinics.loadError' });
  });

  it.each(['context', 'hours', 'profile'] as const)(
    'stops with an expired session in the %s read',
    (which) => {
      const expired = failed(PROFESSIONAL_CONTEXT_AUTH_REQUIRED);
      const read = clinicSettingsReadFrom(
        CLINIC_ID,
        ok(administrator),
        which === 'context' ? expired : ok(context(true)),
        which === 'profile' ? expired : ok(profile),
        which === 'hours' ? expired : ok(hours),
      );
      expect(read).toEqual({ kind: 'error', messageKey: 'errors.sessionExpired' });
    },
  );
});

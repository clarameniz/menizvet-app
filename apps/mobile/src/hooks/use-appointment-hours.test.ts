import {
  APPOINTMENT_HOURS_ACCESS_DENIED,
  APPOINTMENT_HOURS_MALFORMED,
  type ClinicAppointmentHours,
} from '@/data/clinic-appointment-hours';
import type { ProfessionalClinics } from '@/data/professional-clinics';
import {
  PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
  PROFESSIONAL_CONTEXT_MALFORMED,
  type ProfessionalContext,
} from '@/data/professional-context';
import { appointmentHoursReadFrom } from '@/hooks/use-appointment-hours';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const CLINIC_ID = 'c-1';

const clinics: ProfessionalClinics = {
  clinics: [
    {
      clinicId: CLINIC_ID,
      clinicDisplayName: 'Animalia',
      organizationId: 'o-1',
      organizationDisplayName: 'Animalia Group',
      capabilities: ['APPOINTMENT_MANAGE_AVAILABILITY'],
      unknownCapabilities: [],
    },
  ],
};

const context: ProfessionalContext = {
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
        APPOINTMENT_MANAGEMENT: true,
        PROFESSIONAL_SCHEDULING: true,
        CLINICAL_CARE: true,
        CLINICAL_DOCUMENTATION: true,
      },
    },
  ],
};

const config: ClinicAppointmentHours = {
  schedulingTimezoneName: 'Europe/Madrid',
  standardAppointmentDurationMinutes: 30,
  recurringPeriods: [],
  weeklyAvailabilityRevision: 0,
  exceptions: [],
};

const ok = <T>(data: T) => ({ data, error: null });
const failed = (error: string) => ({ data: null, error });

describe('appointmentHoursReadFrom', () => {
  it('loads an editable configuration when every read succeeds', () => {
    expect(appointmentHoursReadFrom(CLINIC_ID, ok(clinics), ok(context), ok(config))).toEqual({
      kind: 'loaded',
      clinic: clinics.clinics[0],
      access: 'editable',
      config,
    });
  });

  it.each([['Network request failed'], [PROFESSIONAL_CONTEXT_MALFORMED]])(
    'still shows the authorized configuration, not editable, when the context read fails (%s)',
    (error) => {
      expect(appointmentHoursReadFrom(CLINIC_ID, ok(clinics), failed(error), ok(config))).toEqual({
        kind: 'loaded',
        clinic: clinics.clinics[0],
        access: 'unconfirmed',
        config,
      });
    },
  );

  it('stops on an expired session from the context read', () => {
    expect(
      appointmentHoursReadFrom(
        CLINIC_ID,
        ok(clinics),
        failed(PROFESSIONAL_CONTEXT_AUTH_REQUIRED),
        ok(config),
      ),
    ).toEqual({ kind: 'error', messageKey: 'errors.sessionExpired' });
  });

  it('never shows configuration the management read did not return', () => {
    expect(
      appointmentHoursReadFrom(
        CLINIC_ID,
        ok(clinics),
        failed('Network request failed'),
        failed(APPOINTMENT_HOURS_ACCESS_DENIED),
      ),
    ).toEqual({ kind: 'unavailable' });
    expect(
      appointmentHoursReadFrom(
        CLINIC_ID,
        ok(clinics),
        failed('Network request failed'),
        failed(APPOINTMENT_HOURS_MALFORMED),
      ),
    ).toEqual({ kind: 'error', messageKey: 'appointmentHours.loadError' });
  });

  it('is unavailable without the advisory capability, whatever the other reads', () => {
    const withoutCapability: ProfessionalClinics = {
      clinics: [{ ...clinics.clinics[0], capabilities: ['APPOINTMENT_VIEW_SCHEDULE'] }],
    };
    expect(
      appointmentHoursReadFrom(CLINIC_ID, ok(withoutCapability), ok(context), ok(config)),
    ).toEqual({ kind: 'unavailable' });
    expect(
      appointmentHoursReadFrom(
        'c-other',
        ok(clinics),
        failed('Network request failed'),
        ok(config),
      ),
    ).toEqual({ kind: 'unavailable' });
  });
});

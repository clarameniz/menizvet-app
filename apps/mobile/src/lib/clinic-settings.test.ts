import type { ClinicAppointmentHours } from '@/data/clinic-appointment-hours';
import type { ManagedClinicProfile } from '@/data/clinic-settings';
import type { ProfessionalClinic } from '@/data/professional-clinics';
import type { ProfessionalCapability } from '@/data/professional-context';
import {
  clinicSettingsEditorHref,
  clinicSettingsHref,
  offersClinicSettingsEditor,
  clinicSettingsOverview,
  clinicSettingsStatusSummary,
  hasCurrentOrFutureAppointmentAvailability,
  isSettingsItemActionable,
  SETTINGS_STATUS_TONE,
  isPublished,
  isReadyToPublish,
  isValidTimeZoneName,
  offersClinicSettings,
  onlineAppointmentSetup,
  publicationAction,
  publicationSaveFailure,
  SETTINGS_ITEM_COPY,
  type ClinicSettingsInput,
  type SettingsItem,
  type SettingsItemKey,
  type SettingsItemStatus,
} from '@/lib/clinic-settings';
import { i18n } from '@/i18n/i18n';

jest.mock('expo-localization', () => ({ getLocales: jest.fn(() => [{ languageCode: 'es' }]) }));

describe('SETTINGS_ITEM_COPY', () => {
  const inLocale = (locale: 'es' | 'en', key: string) => i18n.t(key, { locale });

  it('presents the Profile row as the whole public profile, not only the name', () => {
    const { labelKey, supportKey } = SETTINGS_ITEM_COPY.profile;
    expect(inLocale('es', labelKey)).toBe('Perfil público');
    expect(inLocale('en', labelKey)).toBe('Public profile');
    expect(supportKey).not.toBeNull();
    expect(inLocale('es', supportKey as string)).toBe('Nombre, descripción y datos de contacto');
    expect(inLocale('en', supportKey as string)).toBe('Name, description and contact details');
  });

  it('presents the Location row as covering both the public address and the map position', () => {
    const { labelKey, supportKey } = SETTINGS_ITEM_COPY.location;
    expect(inLocale('es', labelKey)).toBe('Ubicación');
    expect(inLocale('en', labelKey)).toBe('Location');
    expect(inLocale('es', supportKey as string)).toBe('Dirección pública y posición en el mapa');
    expect(inLocale('en', supportKey as string)).toBe('Public address and map position');
  });

  it('gives every other row a label without a subtitle', () => {
    for (const key of ['timezone', 'duration', 'appointmentHours', 'publication'] as const) {
      expect(SETTINGS_ITEM_COPY[key].supportKey).toBeNull();
    }
  });
});

// 12:00 UTC: 2026-10-06 in Madrid, already 2026-10-07 in Kiritimati (UTC+14).
const NOW = new Date('2026-10-06T12:00:00Z');

/** Owner / Organization Administrator / Clinic Administrator capability set (SPEC-ORG-005). */
const ADMINISTRATOR: ProfessionalCapability[] = [
  'APPOINTMENT_MANAGE_AVAILABILITY',
  'APPOINTMENT_VIEW_SCHEDULE',
  'CLINIC_MANAGE_LOCATION',
  'CLINIC_MANAGE_OPENING_HOURS',
  'CLINIC_MANAGE_PUBLICATION',
  'CLINIC_MANAGE_PUBLIC_PROFILE',
  'CLINIC_MANAGE_SERVICES',
  'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
];
const RECEPTIONIST: ProfessionalCapability[] = [
  'APPOINTMENT_CANCEL',
  'APPOINTMENT_COMPLETE',
  'APPOINTMENT_CONFIRM',
  'APPOINTMENT_MANAGE_AVAILABILITY',
  'APPOINTMENT_VIEW_SCHEDULE',
];
const VETERINARIAN: ProfessionalCapability[] = [
  'APPOINTMENT_COMPLETE',
  'APPOINTMENT_VIEW_SCHEDULE',
  'CLINICAL_CARE',
  'CLINICAL_DOCUMENTATION',
];

function clinic(capabilities: ProfessionalCapability[] = ADMINISTRATOR): ProfessionalClinic {
  return {
    clinicId: 'c-1',
    clinicDisplayName: 'Animalia',
    organizationId: 'o-1',
    organizationDisplayName: 'Animalia Group',
    capabilities,
    unknownCapabilities: [],
  };
}

function profile(overrides: Partial<ManagedClinicProfile> = {}): ManagedClinicProfile {
  return {
    clinicId: 'c-1',
    isPublished: true,
    schedulingTimezoneName: 'Europe/Madrid',
    publicProfile: {
      displayName: 'Animalia',
      description: null,
      publicPhone: null,
      publicEmail: null,
      website: null,
    },
    location: { addressText: 'Calle Mayor 1', latitude: 40.4168, longitude: -3.7038 },
    ...overrides,
  };
}

function hours(overrides: Partial<ClinicAppointmentHours> = {}): ClinicAppointmentHours {
  return {
    schedulingTimezoneName: 'Europe/Madrid',
    standardAppointmentDurationMinutes: 30,
    recurringPeriods: [{ isoWeekday: 1, startTime: '09:00:00', endTime: '13:00:00' }],
    weeklyAvailabilityRevision: 0,
    exceptions: [],
    ...overrides,
  };
}

function input(overrides: Partial<ClinicSettingsInput> = {}): ClinicSettingsInput {
  return {
    clinic: clinic(),
    profile: profile(),
    scheduling: { kind: 'known', hours: hours() },
    appointmentManagement: true,
    appointmentHoursAccess: 'editable',
    subscriptionStatusAccess: false,
    ...overrides,
  };
}

const itemOf = (items: SettingsItem[], key: SettingsItemKey) =>
  items.find((entry) => entry.key === key) as SettingsItem;

describe('offersClinicSettings', () => {
  it('offers Clinic settings to Owners and Organization or Clinic Administrators', () => {
    expect(offersClinicSettings(clinic(ADMINISTRATOR))).toBe(true);
  });

  it.each([
    'CLINIC_MANAGE_PUBLIC_PROFILE',
    'CLINIC_MANAGE_LOCATION',
    'CLINIC_MANAGE_PUBLICATION',
    'CLINIC_MANAGE_OPENING_HOURS',
  ] as const)('offers it with %s alone', (capability) => {
    expect(offersClinicSettings(clinic([capability]))).toBe(true);
  });

  it('does not offer it to a Receptionist, a Veterinarian, or other capabilities alone', () => {
    expect(offersClinicSettings(clinic(RECEPTIONIST))).toBe(false);
    expect(offersClinicSettings(clinic(VETERINARIAN))).toBe(false);
    expect(offersClinicSettings(clinic(['CLINIC_MANAGE_SERVICES']))).toBe(false);
    expect(
      offersClinicSettings({ ...clinic([]), unknownCapabilities: ['CLINIC_MANAGE_LOCATION_V2'] }),
    ).toBe(false);
  });

  it('links to the overview route', () => {
    expect(clinicSettingsHref('c-1')).toEqual({
      pathname: '/professional/clinics/[clinicId]/settings',
      params: { clinicId: 'c-1' },
    });
  });
});

describe('offersClinicSettingsEditor', () => {
  it('offers the Profile editor only with CLINIC_MANAGE_PUBLIC_PROFILE', () => {
    expect(offersClinicSettingsEditor(clinic(ADMINISTRATOR), 'profile')).toBe(true);
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_PUBLIC_PROFILE']), 'profile')).toBe(
      true,
    );
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_LOCATION']), 'profile')).toBe(false);
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_PUBLICATION']), 'profile')).toBe(
      false,
    );
  });

  it('offers the Location editor only with CLINIC_MANAGE_LOCATION', () => {
    expect(offersClinicSettingsEditor(clinic(ADMINISTRATOR), 'location')).toBe(true);
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_LOCATION']), 'location')).toBe(true);
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_PUBLIC_PROFILE']), 'location')).toBe(
      false,
    );
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_OPENING_HOURS']), 'location')).toBe(
      false,
    );
  });

  it('offers neither editor to a Receptionist or a Veterinarian', () => {
    for (const editor of ['profile', 'location'] as const) {
      expect(offersClinicSettingsEditor(clinic(RECEPTIONIST), editor)).toBe(false);
      expect(offersClinicSettingsEditor(clinic(VETERINARIAN), editor)).toBe(false);
    }
  });

  it('links to the editor routes', () => {
    expect(clinicSettingsEditorHref('c-1', 'profile')).toEqual({
      pathname: '/professional/clinics/[clinicId]/settings/profile',
      params: { clinicId: 'c-1' },
    });
    expect(clinicSettingsEditorHref('c-1', 'location')).toEqual({
      pathname: '/professional/clinics/[clinicId]/settings/location',
      params: { clinicId: 'c-1' },
    });
  });
});

describe('isReadyToPublish / isPublished', () => {
  it('is ready to publish exactly with a display name and a location', () => {
    expect(isReadyToPublish(profile({ isPublished: false }))).toBe(true);
    expect(isReadyToPublish(profile({ isPublished: false, location: null }))).toBe(false);
    expect(isReadyToPublish(profile({ isPublished: false, publicProfile: null }))).toBe(false);
    expect(
      isReadyToPublish(
        profile({
          publicProfile: {
            displayName: null,
            description: 'Only a description',
            publicPhone: '+34 910 000 001',
            publicEmail: null,
            website: null,
          },
        }),
      ),
    ).toBe(false);
  });

  it('ignores scheduling configuration for readiness to publish', () => {
    expect(isReadyToPublish(profile({ schedulingTimezoneName: null }))).toBe(true);
  });

  it('reports the persisted publication state', () => {
    expect(isPublished(profile())).toBe(true);
    expect(isPublished(profile({ isPublished: false }))).toBe(false);
  });
});

describe('isValidTimeZoneName', () => {
  it('accepts IANA names and rejects unknown ones', () => {
    expect(isValidTimeZoneName('Europe/Madrid')).toBe(true);
    expect(isValidTimeZoneName('Atlantic/Canary')).toBe(true);
    expect(isValidTimeZoneName('Mars/Olympus_Mons')).toBe(false);
  });
});

describe('hasCurrentOrFutureAppointmentAvailability', () => {
  const noWeek = { recurringPeriods: [] };

  it('counts any recurring period', () => {
    expect(hasCurrentOrFutureAppointmentAvailability(hours(), '2026-10-06')).toBe(true);
  });

  it('counts an OPEN exception for Clinic-local today or later', () => {
    const today = hours({
      ...noWeek,
      exceptions: [
        {
          localDate: '2026-10-06',
          kind: 'OPEN',
          periods: [{ startTime: '09:00', endTime: '10:00' }],
        },
      ],
    });
    const later = hours({
      ...noWeek,
      exceptions: [
        {
          localDate: '2026-12-24',
          kind: 'OPEN',
          periods: [{ startTime: '09:00', endTime: '10:00' }],
        },
      ],
    });
    expect(hasCurrentOrFutureAppointmentAvailability(today, '2026-10-06')).toBe(true);
    expect(hasCurrentOrFutureAppointmentAvailability(later, '2026-10-06')).toBe(true);
  });

  it('does not count CLOSED exceptions alone', () => {
    const closedOnly = hours({
      ...noWeek,
      exceptions: [{ localDate: '2026-12-24', kind: 'CLOSED' }],
    });
    expect(hasCurrentOrFutureAppointmentAvailability(closedOnly, '2026-10-06')).toBe(false);
  });

  it('does not count historical OPEN exceptions alone', () => {
    const pastOnly = hours({
      ...noWeek,
      exceptions: [
        {
          localDate: '2026-10-05',
          kind: 'OPEN',
          periods: [{ startTime: '09:00', endTime: '10:00' }],
        },
      ],
    });
    expect(hasCurrentOrFutureAppointmentAvailability(pastOnly, '2026-10-06')).toBe(false);
  });

  it('counts no exception without a Clinic-local today, but still counts the week', () => {
    const futureOpen = hours({
      ...noWeek,
      exceptions: [
        {
          localDate: '2026-12-24',
          kind: 'OPEN',
          periods: [{ startTime: '09:00', endTime: '10:00' }],
        },
      ],
    });
    expect(hasCurrentOrFutureAppointmentAvailability(futureOpen, null)).toBe(false);
    expect(hasCurrentOrFutureAppointmentAvailability(hours(), null)).toBe(true);
  });
});

describe('onlineAppointmentSetup', () => {
  it('is complete only when every condition holds', () => {
    expect(onlineAppointmentSetup([true, true, true, true, true])).toBe('complete');
  });

  it('is incomplete when any condition is known to fail, even with unknowns', () => {
    expect(onlineAppointmentSetup([false, true, null, null, true])).toBe('incomplete');
  });

  it('is unknown when nothing fails but something could not be read', () => {
    expect(onlineAppointmentSetup([true, true, null, null, true])).toBe('unknown');
  });
});

describe('clinicSettingsOverview', () => {
  it('reports a fully configured, published Clinic as complete', () => {
    const overview = clinicSettingsOverview(input(), NOW);

    expect(overview).toMatchObject({
      readyToPublish: true,
      published: true,
      onlineAppointmentSetup: 'complete',
      showPlanNotice: false,
      schedulingUnknown: false,
    });
    expect(overview.items.map((entry) => [entry.key, entry.status])).toEqual([
      ['profile', 'complete'],
      ['location', 'complete'],
      ['timezone', 'complete'],
      ['duration', 'complete'],
      ['appointmentHours', 'complete'],
      ['publication', 'published'],
    ]);
  });

  it('reports an empty unpublished Clinic as missing, with publication separate', () => {
    const overview = clinicSettingsOverview(
      input({
        profile: profile({
          isPublished: false,
          schedulingTimezoneName: null,
          publicProfile: null,
          location: null,
        }),
        scheduling: {
          kind: 'known',
          hours: hours({
            schedulingTimezoneName: null,
            standardAppointmentDurationMinutes: null,
            recurringPeriods: [],
          }),
        },
      }),
      NOW,
    );

    expect(overview).toMatchObject({
      readyToPublish: false,
      published: false,
      onlineAppointmentSetup: 'incomplete',
    });
    expect(overview.items.map((entry) => [entry.key, entry.status])).toEqual([
      ['profile', 'missing'],
      ['location', 'missing'],
      ['timezone', 'missing'],
      ['duration', 'missing'],
      ['appointmentHours', 'missing'],
      ['publication', 'notPublished'],
    ]);
    // An administrator manages every missing row; nobody else needs to be asked.
    expect(overview.items.every((entry) => entry.canManage && !entry.askAdministrator)).toBe(true);
  });

  it('keeps ready to publish and published distinct', () => {
    const ready = clinicSettingsOverview(input({ profile: profile({ isPublished: false }) }), NOW);
    expect(ready).toMatchObject({
      readyToPublish: true,
      published: false,
      onlineAppointmentSetup: 'incomplete',
    });
  });

  it.each<[string, Partial<ClinicSettingsInput>, SettingsItemKey, SettingsItemStatus]>([
    [
      'missing timezone',
      { profile: profile({ schedulingTimezoneName: null }) },
      'timezone',
      'missing',
    ],
    [
      'unrecognized timezone',
      { profile: profile({ schedulingTimezoneName: 'Mars/Olympus_Mons' }) },
      'timezone',
      'needsAttention',
    ],
    [
      'missing duration',
      {
        scheduling: {
          kind: 'known',
          hours: hours({ standardAppointmentDurationMinutes: null }),
        },
      },
      'duration',
      'missing',
    ],
    [
      'missing Availability',
      { scheduling: { kind: 'known', hours: hours({ recurringPeriods: [] }) } },
      'appointmentHours',
      'missing',
    ],
  ])('is incomplete with a %s', (_label, overrides, key, status) => {
    const overview = clinicSettingsOverview(input(overrides), NOW);
    expect(overview.onlineAppointmentSetup).toBe('incomplete');
    expect(itemOf(overview.items, key).status).toBe(status);
  });

  it('uses the Clinic-local date for exceptions, not UTC or the device', () => {
    const exceptionToday = (timezone: string) =>
      input({
        profile: profile({ schedulingTimezoneName: timezone }),
        scheduling: {
          kind: 'known',
          hours: hours({
            schedulingTimezoneName: timezone,
            recurringPeriods: [],
            exceptions: [
              {
                localDate: '2026-10-06',
                kind: 'OPEN',
                periods: [{ startTime: '18:00', endTime: '19:00' }],
              },
            ],
          }),
        },
      });

    // 2026-10-06 is today in Madrid but already yesterday in Kiritimati.
    expect(
      clinicSettingsOverview(exceptionToday('Europe/Madrid'), NOW).onlineAppointmentSetup,
    ).toBe('complete');
    expect(
      clinicSettingsOverview(exceptionToday('Pacific/Kiritimati'), NOW).onlineAppointmentSetup,
    ).toBe('incomplete');
  });

  it('is complete with only a current/future OPEN exception, but not with CLOSED or past ones', () => {
    const withExceptions = (exceptions: ClinicAppointmentHours['exceptions']) =>
      clinicSettingsOverview(
        input({
          scheduling: { kind: 'known', hours: hours({ recurringPeriods: [], exceptions }) },
        }),
        NOW,
      ).onlineAppointmentSetup;

    expect(
      withExceptions([
        {
          localDate: '2026-11-02',
          kind: 'OPEN',
          periods: [{ startTime: '09:00', endTime: '10:00' }],
        },
      ]),
    ).toBe('complete');
    expect(withExceptions([{ localDate: '2026-11-02', kind: 'CLOSED' }])).toBe('incomplete');
    expect(
      withExceptions([
        {
          localDate: '2026-09-30',
          kind: 'OPEN',
          periods: [{ startTime: '09:00', endTime: '10:00' }],
        },
      ]),
    ).toBe('incomplete');
  });

  it('shows the plan notice and is incomplete without APPOINTMENT_MANAGEMENT, leaving other items alone', () => {
    const overview = clinicSettingsOverview(input({ appointmentManagement: false }), NOW);
    expect(overview.onlineAppointmentSetup).toBe('incomplete');
    expect(overview.showPlanNotice).toBe(true);
    expect(overview.readyToPublish).toBe(true);
    expect(overview.items.every((entry) => entry.status !== 'missing')).toBe(true);
  });

  it('marks only the scheduling items unknown when the Appointment hours read failed', () => {
    const overview = clinicSettingsOverview(input({ scheduling: { kind: 'unknown' } }), NOW);

    expect(overview.schedulingUnknown).toBe(true);
    expect(overview.onlineAppointmentSetup).toBe('unknown');
    expect(itemOf(overview.items, 'duration').status).toBe('unknown');
    expect(itemOf(overview.items, 'appointmentHours').status).toBe('unknown');
    expect(itemOf(overview.items, 'profile').status).toBe('complete');
    expect(itemOf(overview.items, 'location').status).toBe('complete');
    expect(itemOf(overview.items, 'publication').status).toBe('published');
  });

  it('stays incomplete, not unknown, when a known prerequisite fails and scheduling is unknown', () => {
    const overview = clinicSettingsOverview(
      input({ profile: profile({ isPublished: false }), scheduling: { kind: 'unknown' } }),
      NOW,
    );
    expect(overview.onlineAppointmentSetup).toBe('incomplete');
  });

  it('is unknown without a plan notice when the Entitlement could not be read', () => {
    const overview = clinicSettingsOverview(input({ appointmentManagement: null }), NOW);
    expect(overview.onlineAppointmentSetup).toBe('unknown');
    expect(overview.showPlanNotice).toBe(false);
  });

  it('never claims setup is complete while unpublished, whatever the scheduling configuration', () => {
    expect(
      clinicSettingsOverview(input({ profile: profile({ isPublished: false }) }), NOW)
        .onlineAppointmentSetup,
    ).toBe('incomplete');
  });

  describe('capability-aware rows', () => {
    it('lets an administrator manage every row, each opening its editor or the Appointment hours screens', () => {
      const { items } = clinicSettingsOverview(input(), NOW);
      expect(items.every((entry) => entry.canManage && !entry.askAdministrator)).toBe(true);
      expect(items.map((entry) => [entry.key, entry.target])).toEqual([
        ['profile', 'profileEditor'],
        ['location', 'locationEditor'],
        ['timezone', 'timezoneEditor'],
        ['duration', 'durationEditor'],
        ['appointmentHours', 'appointmentHours'],
        ['publication', null],
      ]);
    });

    it('opens each editor only with its own capability; other settings users see the state only', () => {
      const profileOnly = clinicSettingsOverview(
        input({ clinic: clinic(['CLINIC_MANAGE_PUBLIC_PROFILE']) }),
        NOW,
      );
      expect(itemOf(profileOnly.items, 'profile').target).toBe('profileEditor');
      expect(itemOf(profileOnly.items, 'location')).toMatchObject({
        status: 'complete',
        canManage: false,
        target: null,
      });

      const locationOnly = clinicSettingsOverview(
        input({ clinic: clinic(['CLINIC_MANAGE_LOCATION']) }),
        NOW,
      );
      expect(itemOf(locationOnly.items, 'location').target).toBe('locationEditor');
      expect(itemOf(locationOnly.items, 'profile')).toMatchObject({
        canManage: false,
        target: null,
      });

      const timezoneOnly = clinicSettingsOverview(
        input({ clinic: clinic(['CLINIC_MANAGE_OPENING_HOURS']) }),
        NOW,
      );
      expect(itemOf(timezoneOnly.items, 'profile').target).toBeNull();
      expect(itemOf(timezoneOnly.items, 'location').target).toBeNull();
    });

    it('opens Appointment hours instead of the duration editor while editing is not available', () => {
      for (const access of ['readOnly', 'unconfirmed'] as const) {
        const { items } = clinicSettingsOverview(input({ appointmentHoursAccess: access }), NOW);
        expect(itemOf(items, 'duration').target).toBe('appointmentHours');
      }
    });

    it('asks for an administrator on incomplete rows this User cannot manage, without an action', () => {
      // A User with only CLINIC_MANAGE_PUBLICATION.
      const { items } = clinicSettingsOverview(
        input({
          clinic: clinic(['CLINIC_MANAGE_PUBLICATION']),
          profile: profile({ isPublished: false, schedulingTimezoneName: null, location: null }),
          scheduling: {
            kind: 'known',
            hours: hours({ standardAppointmentDurationMinutes: null }),
          },
        }),
        NOW,
      );

      expect(itemOf(items, 'location')).toEqual({
        key: 'location',
        status: 'missing',
        canManage: false,
        askAdministrator: true,
        target: null,
      });
      expect(itemOf(items, 'timezone').askAdministrator).toBe(true);
      expect(itemOf(items, 'duration')).toMatchObject({ askAdministrator: true, target: null });
      // Complete rows need no help, and publication is this User's own.
      expect(itemOf(items, 'profile').askAdministrator).toBe(false);
      expect(itemOf(items, 'publication')).toMatchObject({
        status: 'notPublished',
        canManage: true,
        askAdministrator: false,
      });
    });

    it('does not ask for an administrator when a row is merely unknown', () => {
      const { items } = clinicSettingsOverview(
        input({
          clinic: clinic(['CLINIC_MANAGE_PUBLIC_PROFILE']),
          scheduling: { kind: 'unknown' },
        }),
        NOW,
      );
      expect(itemOf(items, 'duration')).toMatchObject({
        status: 'unknown',
        askAdministrator: false,
      });
    });
  });
});

describe('Slice C — timezone editor gating', () => {
  it('opens the timezone editor only with CLINIC_MANAGE_OPENING_HOURS', () => {
    const timezoneOnly = clinicSettingsOverview(
      input({ clinic: clinic(['CLINIC_MANAGE_OPENING_HOURS']) }),
      NOW,
    );
    expect(itemOf(timezoneOnly.items, 'timezone')).toMatchObject({
      canManage: true,
      target: 'timezoneEditor',
    });
    const publicationOnly = clinicSettingsOverview(
      input({ clinic: clinic(['CLINIC_MANAGE_PUBLICATION']) }),
      NOW,
    );
    expect(itemOf(publicationOnly.items, 'timezone')).toMatchObject({
      canManage: false,
      target: null,
    });
    expect(offersClinicSettingsEditor(clinic(['CLINIC_MANAGE_OPENING_HOURS']), 'timezone')).toBe(
      true,
    );
    expect(offersClinicSettingsEditor(clinic(RECEPTIONIST), 'timezone')).toBe(false);
    expect(offersClinicSettingsEditor(clinic(VETERINARIAN), 'timezone')).toBe(false);
    expect(clinicSettingsEditorHref('c-1', 'timezone')).toEqual({
      pathname: '/professional/clinics/[clinicId]/settings/timezone',
      params: { clinicId: 'c-1' },
    });
  });
});

describe('publicationAction', () => {
  it('offers Publish for an unpublished Clinic with a display name and a location', () => {
    expect(publicationAction(input({ profile: profile({ isPublished: false }) }))).toEqual({
      kind: 'publish',
    });
  });

  it('does not require a scheduling timezone, duration, Availability, or plan to publish (SPEC-CLI-003 BR-15)', () => {
    expect(
      publicationAction(
        input({
          profile: profile({ isPublished: false, schedulingTimezoneName: null }),
          scheduling: { kind: 'unknown' },
          appointmentManagement: false,
        }),
      ),
    ).toEqual({ kind: 'publish' });
  });

  it('blocks Publish and lists exactly what is missing', () => {
    expect(
      publicationAction(input({ profile: profile({ isPublished: false, location: null }) })),
    ).toEqual({ kind: 'publishBlocked', missing: ['location'] });
    expect(
      publicationAction(input({ profile: profile({ isPublished: false, publicProfile: null }) })),
    ).toEqual({ kind: 'publishBlocked', missing: ['profile'] });
    expect(
      publicationAction(
        input({
          profile: profile({
            isPublished: false,
            publicProfile: {
              displayName: null,
              description: 'Only a description',
              publicPhone: null,
              publicEmail: null,
              website: null,
            },
            location: null,
          }),
        }),
      ),
    ).toEqual({ kind: 'publishBlocked', missing: ['profile', 'location'] });
  });

  it('offers Unpublish for a published Clinic', () => {
    expect(publicationAction(input())).toEqual({ kind: 'unpublish' });
  });

  it('offers no publication action without CLINIC_MANAGE_PUBLICATION, published or not', () => {
    for (const capabilities of [
      ['CLINIC_MANAGE_PUBLIC_PROFILE', 'CLINIC_MANAGE_LOCATION', 'CLINIC_MANAGE_OPENING_HOURS'],
      RECEPTIONIST,
    ] as ProfessionalCapability[][]) {
      expect(publicationAction(input({ clinic: clinic(capabilities) }))).toEqual({ kind: 'none' });
      expect(
        publicationAction(
          input({ clinic: clinic(capabilities), profile: profile({ isPublished: false }) }),
        ),
      ).toEqual({ kind: 'none' });
    }
  });
});

describe('publicationSaveFailure (lost-response reconciliation)', () => {
  it('treats a re-read already in the requested state as done', () => {
    expect(publicationSaveFailure({ kind: 'loaded', profile: profile() }, true)).toBe('committed');
    expect(
      publicationSaveFailure({ kind: 'loaded', profile: profile({ isPublished: false }) }, false),
    ).toBe('committed');
  });

  it('reports a failure when the state did not change, and lost access as such', () => {
    expect(
      publicationSaveFailure({ kind: 'loaded', profile: profile({ isPublished: false }) }, true),
    ).toBe('failed');
    expect(publicationSaveFailure({ kind: 'error' }, true)).toBe('failed');
    expect(publicationSaveFailure(null, false)).toBe('failed');
    expect(publicationSaveFailure({ kind: 'unavailable' }, true)).toBe('accessLost');
  });

  it('keeps the whole configuration visible after an unpublish (only the state changes)', () => {
    const unpublished = profile({ isPublished: false });
    const overview = clinicSettingsOverview(input({ profile: unpublished }), NOW);
    expect(overview.published).toBe(false);
    expect(overview.readyToPublish).toBe(true);
    expect(itemOf(overview.items, 'profile').status).toBe('complete');
    expect(itemOf(overview.items, 'location').status).toBe('complete');
    expect(itemOf(overview.items, 'timezone').status).toBe('complete');
    expect(publicationAction(input({ profile: unpublished }))).toEqual({ kind: 'publish' });
  });
});

describe('overview presentation (post-Phase-1 hierarchy)', () => {
  it('keeps visibility and online-appointment readiness separate: published but setup incomplete', () => {
    const summary = clinicSettingsStatusSummary(
      clinicSettingsOverview(input({ profile: profile({ schedulingTimezoneName: null }) }), NOW),
    );
    expect(summary.visibility).toBe('published');
    expect(summary.onlineAppointments).toBe('incomplete');
  });

  it('never reports visibility from readiness: unpublished stays unpublished even when everything else is set', () => {
    const summary = clinicSettingsStatusSummary(
      clinicSettingsOverview(input({ profile: profile({ isPublished: false }) }), NOW),
    );
    expect(summary).toEqual({
      visibility: 'notPublished',
      onlineAppointments: 'incomplete',
      planNotice: false,
    });
  });

  it('shows the plan notice only inside the online card, leaving visibility untouched', () => {
    const summary = clinicSettingsStatusSummary(
      clinicSettingsOverview(input({ appointmentManagement: false }), NOW),
    );
    expect(summary).toEqual({
      visibility: 'published',
      onlineAppointments: 'incomplete',
      planNotice: true,
    });
  });

  it('marks missing and needs-attention rows for attention, complete rows as positive', () => {
    expect(SETTINGS_STATUS_TONE.complete).toBe('positive');
    expect(SETTINGS_STATUS_TONE.missing).toBe('attention');
    expect(SETTINGS_STATUS_TONE.needsAttention).toBe('attention');
    expect(SETTINGS_STATUS_TONE.unknown).toBe('neutral');

    const { items } = clinicSettingsOverview(
      input({ profile: profile({ isPublished: false, location: null }) }),
      NOW,
    );
    expect(SETTINGS_STATUS_TONE[itemOf(items, 'location').status]).toBe('attention');
    expect(SETTINGS_STATUS_TONE[itemOf(items, 'profile').status]).toBe('positive');
  });

  it('makes rows actionable only with their capability; the Visibility row is never a second Publish control', () => {
    const admin = clinicSettingsOverview(input(), NOW).items;
    expect(admin.filter(isSettingsItemActionable).map((entry) => entry.key)).toEqual([
      'profile',
      'location',
      'timezone',
      'duration',
      'appointmentHours',
    ]);

    const publicationOnly = clinicSettingsOverview(
      input({ clinic: clinic(['CLINIC_MANAGE_PUBLICATION']) }),
      NOW,
    ).items;
    expect(publicationOnly.filter(isSettingsItemActionable)).toEqual([]);
  });
});

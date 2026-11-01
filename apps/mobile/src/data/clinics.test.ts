import {
  fromClinicLocationRow,
  fromClinicOpeningHoursRow,
  fromClinicPublicProfileRow,
  fromClinicServiceOfferingRow,
  parseGeographicClinicsEnvelope,
  parseNearbyClinicsEnvelope,
  parsePublishedClinicsEnvelope,
  discoverPublishedClinicsPage,
  publishedClinicsCursorOf,
  type ClinicPublicProfileRow,
} from '@/data/clinics';
import { supabase } from '@/lib/supabase';

// None of the functions under test touch the Supabase client, but importing
// this module pulls in lib/supabase.ts, which throws if EXPO_PUBLIC_SUPABASE_*
// env vars are absent (as they are under Jest). Mocking it keeps this test
// isolated and free of any real network/Supabase contact — same pattern as
// data/pets.test.ts and data/user-profile.test.ts.
jest.mock('@/lib/supabase', () => ({
  supabase: { from: jest.fn(), rpc: jest.fn() },
}));

describe('fromClinicPublicProfileRow', () => {
  it('maps a full row to the camelCase ClinicPublicProfile shape', () => {
    const row: ClinicPublicProfileRow = {
      clinic_id: 'clinic-1',
      display_name: 'Animalia Madrid Centro',
      description: 'General veterinary care.',
      public_phone: '+34 900 000 000',
      public_email: 'info@animalia.example',
      website: 'https://animalia.example',
    };

    expect(fromClinicPublicProfileRow(row)).toEqual({
      clinicId: 'clinic-1',
      displayName: 'Animalia Madrid Centro',
      description: 'General veterinary care.',
      publicPhone: '+34 900 000 000',
      publicEmail: 'info@animalia.example',
      website: 'https://animalia.example',
    });
  });

  it('preserves null optional fields rather than coercing them', () => {
    const row: ClinicPublicProfileRow = {
      clinic_id: 'clinic-2',
      display_name: 'Animalia Getafe',
      description: null,
      public_phone: null,
      public_email: null,
      website: null,
    };

    expect(fromClinicPublicProfileRow(row)).toEqual({
      clinicId: 'clinic-2',
      displayName: 'Animalia Getafe',
      description: null,
      publicPhone: null,
      publicEmail: null,
      website: null,
    });
  });
});

describe('parsePublishedClinicsEnvelope', () => {
  it('parses rows with and without an address, and the next cursor of the last row', () => {
    expect(
      parsePublishedClinicsEnvelope({
        clinics: [
          {
            clinic_id: 'clinic-1',
            display_name: 'Animalia Getafe',
            description: null,
            address_text: 'Avenida de España 2, Getafe',
          },
          {
            clinic_id: 'clinic-2',
            display_name: 'Animalia Toledo',
            description: 'Centro',
            address_text: null,
          },
        ],
        has_more: true,
        next_after_display_name: 'Animalia Toledo',
        next_after_clinic_id: 'clinic-2',
      }),
    ).toEqual({
      clinics: [
        {
          clinicId: 'clinic-1',
          displayName: 'Animalia Getafe',
          description: null,
          addressText: 'Avenida de España 2, Getafe',
        },
        {
          clinicId: 'clinic-2',
          displayName: 'Animalia Toledo',
          description: 'Centro',
          addressText: null,
        },
      ],
      hasMore: true,
      next: { displayName: 'Animalia Toledo', clinicId: 'clinic-2' },
    });
  });

  it('keeps an unnamed cursor (name null, id present) and no cursor for an empty page', () => {
    expect(
      parsePublishedClinicsEnvelope({
        clinics: [
          { clinic_id: 'clinic-9', display_name: null, description: null, address_text: null },
        ],
        has_more: false,
        next_after_display_name: null,
        next_after_clinic_id: 'clinic-9',
      })?.next,
    ).toEqual({ displayName: null, clinicId: 'clinic-9' });
    expect(
      parsePublishedClinicsEnvelope({
        clinics: [],
        has_more: false,
        next_after_display_name: null,
        next_after_clinic_id: null,
      }),
    ).toEqual({ clinics: [], hasMore: false, next: null });
  });

  it.each([
    ['a non-object payload', null],
    [
      'a missing has_more',
      { clinics: [], next_after_display_name: null, next_after_clinic_id: null },
    ],
    [
      'a row without an id',
      {
        clinics: [{ display_name: 'X', description: null, address_text: null }],
        has_more: false,
        next_after_display_name: null,
        next_after_clinic_id: null,
      },
    ],
    [
      'a row with a non-string address',
      {
        clinics: [{ clinic_id: 'c', display_name: 'X', description: null, address_text: 3 }],
        has_more: false,
        next_after_display_name: null,
        next_after_clinic_id: null,
      },
    ],
    [
      'a row missing its address key',
      {
        clinics: [{ clinic_id: 'c', display_name: 'X', description: null }],
        has_more: false,
        next_after_display_name: null,
        next_after_clinic_id: null,
      },
    ],
  ])('rejects %s', (_label, payload) => {
    expect(parsePublishedClinicsEnvelope(payload)).toBeNull();
  });
});

describe('discoverPublishedClinicsPage', () => {
  const rpc = supabase.rpc as jest.Mock;
  const emptyEnvelope = {
    clinics: [],
    has_more: false,
    next_after_display_name: null,
    next_after_clinic_id: null,
  };

  beforeEach(() => rpc.mockReset());

  it('reads the first page of 20 with no search and no cursor', async () => {
    rpc.mockResolvedValueOnce({ data: emptyEnvelope, error: null });
    await expect(discoverPublishedClinicsPage(null, null)).resolves.toEqual({
      data: { clinics: [], hasMore: false, next: null },
      error: null,
    });
    expect(rpc).toHaveBeenCalledWith('discover_published_clinics', {
      p_search: null,
      p_after_display_name: null,
      p_after_clinic_id: null,
      p_limit: 20,
    });
  });

  it('sends the search and the complete cursor verbatim', async () => {
    rpc.mockResolvedValueOnce({ data: emptyEnvelope, error: null });
    await discoverPublishedClinicsPage('peña', {
      displayName: 'Animalia Getafe',
      clinicId: 'clinic-3',
    });
    expect(rpc).toHaveBeenCalledWith('discover_published_clinics', {
      p_search: 'peña',
      p_after_display_name: 'Animalia Getafe',
      p_after_clinic_id: 'clinic-3',
      p_limit: 20,
    });
  });

  it('settles a backend error, a malformed envelope and a rejected request into `error`', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Published Clinics page is invalid' },
    });
    await expect(discoverPublishedClinicsPage(null, null)).resolves.toEqual({
      data: null,
      error: 'Published Clinics page is invalid',
    });
    rpc.mockResolvedValueOnce({ data: { clinics: 'x' }, error: null });
    await expect(discoverPublishedClinicsPage(null, null)).resolves.toEqual({
      data: null,
      error: 'Unexpected Discovery response shape',
    });
    rpc.mockRejectedValueOnce(new Error('Network request failed'));
    await expect(discoverPublishedClinicsPage(null, null)).resolves.toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

describe('publishedClinicsCursorOf', () => {
  it('continues after the complete (name, id) of a row', () => {
    expect(
      publishedClinicsCursorOf({
        clinicId: 'c',
        displayName: null,
        description: 'd',
        addressText: 'a',
      }),
    ).toEqual({ displayName: null, clinicId: 'c' });
  });
});

describe('parseGeographicClinicsEnvelope', () => {
  it('parses a well-formed discover_clinics_in_viewport envelope', () => {
    const raw = {
      clinics: [
        {
          clinic_id: 'clinic-1',
          display_name: 'Animalia Madrid Centro',
          description: null,
          public_phone: null,
          public_email: null,
          website: null,
          address_text: 'Calle Falsa 123',
          latitude: 40.4168,
          longitude: -3.7038,
        },
      ],
      has_more: false,
      next_after_clinic_id: 'clinic-1',
    };

    expect(parseGeographicClinicsEnvelope(raw)).toEqual({
      clinics: [
        {
          clinicId: 'clinic-1',
          displayName: 'Animalia Madrid Centro',
          description: null,
          publicPhone: null,
          publicEmail: null,
          website: null,
          addressText: 'Calle Falsa 123',
          latitude: 40.4168,
          longitude: -3.7038,
        },
      ],
      hasMore: false,
      nextAfterClinicId: 'clinic-1',
    });
  });

  it('rejects a non-object payload', () => {
    expect(parseGeographicClinicsEnvelope(null)).toBeNull();
    expect(parseGeographicClinicsEnvelope('unexpected')).toBeNull();
  });

  it('rejects a payload with a malformed clinic row', () => {
    const raw = {
      clinics: [{ clinic_id: 'clinic-1' /* missing address_text/latitude/longitude */ }],
      has_more: false,
      next_after_clinic_id: null,
    };

    expect(parseGeographicClinicsEnvelope(raw)).toBeNull();
  });

  it('rejects a non-finite latitude/longitude', () => {
    const raw = {
      clinics: [
        {
          clinic_id: 'clinic-1',
          display_name: null,
          description: null,
          public_phone: null,
          public_email: null,
          website: null,
          address_text: 'Calle Falsa 123',
          latitude: Number.NaN,
          longitude: -3.7038,
        },
      ],
      has_more: false,
      next_after_clinic_id: null,
    };

    expect(parseGeographicClinicsEnvelope(raw)).toBeNull();
  });
});

describe('parseNearbyClinicsEnvelope', () => {
  it('parses a well-formed discover_nearby_clinics envelope, including distance_meters', () => {
    const raw = {
      clinics: [
        {
          clinic_id: 'clinic-1',
          display_name: 'Animalia Madrid Centro',
          description: null,
          public_phone: null,
          public_email: null,
          website: null,
          address_text: 'Calle Falsa 123',
          latitude: 40.4168,
          longitude: -3.7038,
          distance_meters: 1234.567,
        },
      ],
      has_more: true,
      next_after_distance_meters: 1234.567,
      next_after_clinic_id: 'clinic-1',
    };

    const parsed = parseNearbyClinicsEnvelope(raw);

    expect(parsed?.clinics[0].distanceMeters).toBe(1234.567);
    expect(parsed?.hasMore).toBe(true);
    expect(parsed?.nextAfterDistanceMeters).toBe(1234.567);
    expect(parsed?.nextAfterClinicId).toBe('clinic-1');
  });

  it('accepts null cursor fields on the last/only page', () => {
    const raw = {
      clinics: [],
      has_more: false,
      next_after_distance_meters: null,
      next_after_clinic_id: null,
    };

    expect(parseNearbyClinicsEnvelope(raw)).toEqual({
      clinics: [],
      hasMore: false,
      nextAfterDistanceMeters: null,
      nextAfterClinicId: null,
    });
  });

  it('rejects a row missing distance_meters', () => {
    const raw = {
      clinics: [
        {
          clinic_id: 'clinic-1',
          display_name: null,
          description: null,
          public_phone: null,
          public_email: null,
          website: null,
          address_text: 'Calle Falsa 123',
          latitude: 40.4168,
          longitude: -3.7038,
        },
      ],
      has_more: false,
      next_after_distance_meters: null,
      next_after_clinic_id: null,
    };

    expect(parseNearbyClinicsEnvelope(raw)).toBeNull();
  });
});

describe('fromClinicLocationRow', () => {
  it('maps a location row to the camelCase shape', () => {
    expect(
      fromClinicLocationRow({
        clinic_id: 'clinic-1',
        address_text: 'Calle Falsa 123',
        latitude: 40.4168,
        longitude: -3.7038,
      }),
    ).toEqual({
      clinicId: 'clinic-1',
      addressText: 'Calle Falsa 123',
      latitude: 40.4168,
      longitude: -3.7038,
    });
  });
});

describe('fromClinicServiceOfferingRow', () => {
  it('maps a service-offering row and preserves a null description', () => {
    expect(
      fromClinicServiceOfferingRow({ service_category: 'VACCINATION', public_description: null }),
    ).toEqual({ serviceCategory: 'VACCINATION', publicDescription: null });
  });

  it('preserves the description verbatim and an unrecognized category unchanged', () => {
    expect(
      fromClinicServiceOfferingRow({
        service_category: 'GROOMING',
        public_description: 'Peluquería y baño',
      }),
    ).toEqual({ serviceCategory: 'GROOMING', publicDescription: 'Peluquería y baño' });
  });
});

describe('fromClinicOpeningHoursRow', () => {
  it('parses recurring periods and exceptions', () => {
    const parsed = fromClinicOpeningHoursRow({
      scheduling_timezone_name: 'Europe/Madrid',
      recurring_periods: [{ iso_weekday: 1, start_time: '09:00', end_time: '18:00' }],
      exceptions: [
        { local_date: '2026-12-25', exception_kind: 'CLOSED', start_time: null, end_time: null },
      ],
    });

    expect(parsed).toEqual({
      schedulingTimezoneName: 'Europe/Madrid',
      recurringPeriods: [{ isoWeekday: 1, startTime: '09:00', endTime: '18:00' }],
      exceptions: [
        { localDate: '2026-12-25', exceptionKind: 'CLOSED', startTime: null, endTime: null },
      ],
    });
  });

  it('rejects a non-array recurring_periods/exceptions column', () => {
    expect(
      fromClinicOpeningHoursRow({
        scheduling_timezone_name: 'Europe/Madrid',
        recurring_periods: null,
        exceptions: [],
      }),
    ).toBeNull();
  });
});

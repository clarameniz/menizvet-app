import {
  CLINIC_SETTINGS_ACCESS_DENIED,
  CLINIC_SETTINGS_INVALID_REQUEST,
  CLINIC_SETTINGS_MALFORMED,
  getManagedClinicProfile,
  parseManagedClinicProfile,
  publishClinic,
  saveClinicLocation,
  saveClinicPublicProfile,
  saveClinicSchedulingTimezone,
  unpublishClinic,
} from '@/data/clinic-settings';
import { PROFESSIONAL_CONTEXT_AUTH_REQUIRED } from '@/data/professional-context';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const rpc = supabase.rpc as jest.Mock;

const CLINIC_ID = '11111111-1111-4111-8111-111111111111';

const profile = (overrides: Record<string, unknown> = {}) => ({
  display_name: 'Animalia Madrid Centro',
  description: 'Línea uno\nLínea  dos',
  public_phone: '+34 910 000 001',
  public_email: 'centro@example.test',
  website: 'https://centro.example.test',
  ...overrides,
});

const location = (overrides: Record<string, unknown> = {}) => ({
  address_text: 'Calle Mayor 1, 28013 Madrid',
  latitude: 40.4168,
  longitude: -3.7038,
  ...overrides,
});

const payload = (overrides: Record<string, unknown> = {}) => ({
  clinic_id: CLINIC_ID,
  is_published: true,
  scheduling_timezone_name: 'Europe/Madrid',
  public_profile: profile(),
  location: location(),
  ...overrides,
});

function without(record: Record<string, unknown>, member: string): Record<string, unknown> {
  const copy = { ...record };
  delete copy[member];
  return copy;
}

beforeEach(() => {
  rpc.mockReset();
});

describe('parseManagedClinicProfile', () => {
  it('parses a complete payload, keeping stored text exactly', () => {
    expect(parseManagedClinicProfile(payload(), CLINIC_ID)).toEqual({
      clinicId: CLINIC_ID,
      isPublished: true,
      schedulingTimezoneName: 'Europe/Madrid',
      publicProfile: {
        displayName: 'Animalia Madrid Centro',
        description: 'Línea uno\nLínea  dos',
        publicPhone: '+34 910 000 001',
        publicEmail: 'centro@example.test',
        website: 'https://centro.example.test',
      },
      location: {
        addressText: 'Calle Mayor 1, 28013 Madrid',
        latitude: 40.4168,
        longitude: -3.7038,
      },
    });
  });

  it('keeps absent configuration absent: null sections and timezone are never defaulted', () => {
    expect(
      parseManagedClinicProfile(
        payload({
          is_published: false,
          scheduling_timezone_name: null,
          public_profile: null,
          location: null,
        }),
        CLINIC_ID,
      ),
    ).toEqual({
      clinicId: CLINIC_ID,
      isPublished: false,
      schedulingTimezoneName: null,
      publicProfile: null,
      location: null,
    });
  });

  it('keeps individually absent profile values null', () => {
    const parsed = parseManagedClinicProfile(
      payload({
        public_profile: profile({ display_name: null, public_email: null, website: null }),
      }),
      CLINIC_ID,
    );
    expect(parsed?.publicProfile).toEqual({
      displayName: null,
      description: 'Línea uno\nLínea  dos',
      publicPhone: '+34 910 000 001',
      publicEmail: null,
      website: null,
    });
  });

  it('accepts a different letter case of the requested Clinic id', () => {
    expect(parseManagedClinicProfile(payload(), CLINIC_ID.toUpperCase())).not.toBeNull();
  });

  it('ignores members this version does not know', () => {
    expect(parseManagedClinicProfile(payload({ future_member: 1 }), CLINIC_ID)).not.toBeNull();
  });

  it.each(['clinic_id', 'is_published', 'scheduling_timezone_name', 'public_profile', 'location'])(
    'rejects a payload missing %s (absent is null, never an omitted member)',
    (member) => {
      expect(parseManagedClinicProfile(without(payload(), member), CLINIC_ID)).toBeNull();
    },
  );

  it.each([
    ['not an object', null],
    ['an array', [payload()]],
    ['a string', 'payload'],
  ])('rejects a payload that is %s', (_label, raw) => {
    expect(parseManagedClinicProfile(raw, CLINIC_ID)).toBeNull();
  });

  it.each([
    ['another Clinic', '22222222-2222-4222-8222-222222222222'],
    ['not a uuid', 'clinic-1'],
    ['a number', 1],
    ['null', null],
  ])('rejects a clinic_id that is %s', (_label, clinicId) => {
    expect(parseManagedClinicProfile(payload({ clinic_id: clinicId }), CLINIC_ID)).toBeNull();
  });

  it.each([
    ['null', null],
    ['a string', 'true'],
    ['a number', 1],
  ])('rejects is_published that is %s (never defaulted to false)', (_label, value) => {
    expect(parseManagedClinicProfile(payload({ is_published: value }), CLINIC_ID)).toBeNull();
  });

  it.each([
    ['empty', ''],
    ['blank', '   '],
    ['a number', 1],
    ['an object', { name: 'Europe/Madrid' }],
  ])('rejects a scheduling timezone that is %s', (_label, value) => {
    expect(
      parseManagedClinicProfile(payload({ scheduling_timezone_name: value }), CLINIC_ID),
    ).toBeNull();
  });

  it.each([
    ['an array', [profile()]],
    ['a string', 'Animalia'],
    ['missing display_name', without(profile(), 'display_name')],
    ['missing website', without(profile(), 'website')],
    ['a numeric phone', profile({ public_phone: 910000001 })],
    ['a blank description', profile({ description: '  ' })],
    ['an empty display name', profile({ display_name: '' })],
  ])('rejects a public profile that is %s', (_label, value) => {
    expect(parseManagedClinicProfile(payload({ public_profile: value }), CLINIC_ID)).toBeNull();
  });

  it.each([
    ['a string', 'Calle Mayor 1'],
    ['missing latitude', without(location(), 'latitude')],
    ['missing address_text', without(location(), 'address_text')],
    ['with a null address', location({ address_text: null })],
    ['with a blank address', location({ address_text: ' ' })],
    ['with a null latitude', location({ latitude: null })],
    ['with a string latitude', location({ latitude: '40.4' })],
    ['with latitude above 90', location({ latitude: 90.0001 })],
    ['with latitude below -90', location({ latitude: -91 })],
    ['with longitude above 180', location({ longitude: 180.5 })],
    ['with longitude below -180', location({ longitude: -181 })],
    ['with a NaN latitude', location({ latitude: Number.NaN })],
    ['with an infinite longitude', location({ longitude: Number.POSITIVE_INFINITY })],
  ])('rejects a location %s', (_label, value) => {
    expect(parseManagedClinicProfile(payload({ location: value }), CLINIC_ID)).toBeNull();
  });

  it('accepts boundary coordinates', () => {
    expect(
      parseManagedClinicProfile(
        payload({ location: location({ latitude: -90, longitude: 180 }) }),
        CLINIC_ID,
      )?.location,
    ).toEqual({ addressText: 'Calle Mayor 1, 28013 Madrid', latitude: -90, longitude: 180 });
  });
});

describe('getManagedClinicProfile', () => {
  it('calls the managed read with the Clinic id', async () => {
    rpc.mockResolvedValue({ data: payload(), error: null });

    const result = await getManagedClinicProfile(CLINIC_ID);

    expect(rpc).toHaveBeenCalledWith('get_managed_clinic_profile', { p_clinic_id: CLINIC_ID });
    expect(result.error).toBeNull();
    expect(result.data?.isPublished).toBe(true);
  });

  it.each([
    ['28000', PROFESSIONAL_CONTEXT_AUTH_REQUIRED],
    ['42501', CLINIC_SETTINGS_ACCESS_DENIED],
  ])('normalizes SQLSTATE %s', async (code, expected) => {
    rpc.mockResolvedValue({ data: null, error: { code, message: 'raw backend text' } });
    expect(await getManagedClinicProfile(CLINIC_ID)).toEqual({ data: null, error: expected });
  });

  it('keeps any other read error as backend text, for the mapper only', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '57014', message: 'raw backend text' } });
    expect(await getManagedClinicProfile(CLINIC_ID)).toEqual({
      data: null,
      error: 'raw backend text',
    });
  });

  it('reports a malformed payload', async () => {
    rpc.mockResolvedValue({ data: payload({ is_published: null }), error: null });
    expect(await getManagedClinicProfile(CLINIC_ID)).toEqual({
      data: null,
      error: CLINIC_SETTINGS_MALFORMED,
    });
  });

  it('denies a non-uuid Clinic id without calling the backend', async () => {
    expect(await getManagedClinicProfile('clinic-1')).toEqual({
      data: null,
      error: CLINIC_SETTINGS_ACCESS_DENIED,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('settles a thrown error into a result', async () => {
    rpc.mockRejectedValue(new Error('Network request failed'));
    expect(await getManagedClinicProfile(CLINIC_ID)).toEqual({
      data: null,
      error: 'Network request failed',
    });
  });
});

describe('saveClinicPublicProfile', () => {
  const values = {
    displayName: 'Animalia',
    description: null,
    publicPhone: '+34 910 000 001',
    publicEmail: null,
    website: null,
  };

  it('always sends all five values, absent ones as null', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });

    expect(await saveClinicPublicProfile(CLINIC_ID, values)).toEqual({ data: null, error: null });
    expect(rpc).toHaveBeenCalledWith('set_clinic_public_profile', {
      p_clinic_id: CLINIC_ID,
      p_display_name: 'Animalia',
      p_description: null,
      p_public_phone: '+34 910 000 001',
      p_public_email: null,
      p_website: null,
    });
  });

  it('normalizes an expired session and keeps other errors for the mapper', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '28000', message: 'raw' } });
    expect(await saveClinicPublicProfile(CLINIC_ID, values)).toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
    rpc.mockResolvedValue({
      data: null,
      error: {
        code: '23514',
        message: 'A published Clinic must retain a valid public display name',
      },
    });
    expect(await saveClinicPublicProfile(CLINIC_ID, values)).toEqual({
      data: null,
      error: 'A published Clinic must retain a valid public display name',
    });
  });

  it('reports a response that is not this Clinic id as malformed', async () => {
    rpc.mockResolvedValue({ data: '22222222-2222-4222-8222-222222222222', error: null });
    expect(await saveClinicPublicProfile(CLINIC_ID, values)).toEqual({
      data: null,
      error: CLINIC_SETTINGS_MALFORMED,
    });
  });

  it('does not send a non-uuid Clinic id', async () => {
    expect(await saveClinicPublicProfile('clinic-1', values)).toEqual({
      data: null,
      error: CLINIC_SETTINGS_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('saveClinicLocation', () => {
  const value = { addressText: 'Calle Mayor 1', latitude: 40.4168, longitude: -3.7038 };

  it('sends the whole location', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });

    expect(await saveClinicLocation(CLINIC_ID, value)).toEqual({ data: null, error: null });
    expect(rpc).toHaveBeenCalledWith('set_clinic_location', {
      p_clinic_id: CLINIC_ID,
      p_address_text: 'Calle Mayor 1',
      p_latitude: 40.4168,
      p_longitude: -3.7038,
    });
  });

  it('sends 0,0 and boundary positions', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    for (const [latitude, longitude] of [
      [0, 0],
      [90, 180],
      [-90, -180],
    ]) {
      expect(await saveClinicLocation(CLINIC_ID, { ...value, latitude, longitude })).toEqual({
        data: null,
        error: null,
      });
    }
  });

  it.each([
    ['an empty address', { ...value, addressText: '' }],
    ['latitude above 90', { ...value, latitude: 90.1 }],
    ['longitude below -180', { ...value, longitude: -180.1 }],
    ['a NaN latitude', { ...value, latitude: Number.NaN }],
  ])('does not send %s', async (_label, invalid) => {
    expect(await saveClinicLocation(CLINIC_ID, invalid)).toEqual({
      data: null,
      error: CLINIC_SETTINGS_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('keeps backend errors for the mapper', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '42501', message: 'Clinic Location-management capability is required' },
    });
    expect(await saveClinicLocation(CLINIC_ID, value)).toEqual({
      data: null,
      error: 'Clinic Location-management capability is required',
    });
  });
});

describe('saveClinicSchedulingTimezone', () => {
  it('sends the canonical timezone name', async () => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    expect(await saveClinicSchedulingTimezone(CLINIC_ID, 'Atlantic/Canary')).toEqual({
      data: null,
      error: null,
    });
    expect(rpc).toHaveBeenCalledWith('set_clinic_scheduling_timezone', {
      p_clinic_id: CLINIC_ID,
      p_timezone_name: 'Atlantic/Canary',
    });
  });

  it('never sends a blank timezone (the timezone is never cleared)', async () => {
    expect(await saveClinicSchedulingTimezone(CLINIC_ID, ' ')).toEqual({
      data: null,
      error: CLINIC_SETTINGS_INVALID_REQUEST,
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('keeps the BR-56 denial text for the mapper', async () => {
    const message =
      'Professional scheduling Entitlement is required to change scheduling timezone while Appointment Availability is currently effective';
    rpc.mockResolvedValue({ data: null, error: { code: '42501', message } });
    expect(await saveClinicSchedulingTimezone(CLINIC_ID, 'Atlantic/Canary')).toEqual({
      data: null,
      error: message,
    });
  });
});

describe('publishClinic / unpublishClinic', () => {
  it.each([
    ['publish_clinic', publishClinic],
    ['unpublish_clinic', unpublishClinic],
  ] as const)('%s sends only the Clinic id', async (name, call) => {
    rpc.mockResolvedValue({ data: CLINIC_ID, error: null });
    expect(await call(CLINIC_ID)).toEqual({ data: null, error: null });
    expect(rpc).toHaveBeenCalledWith(name, { p_clinic_id: CLINIC_ID });
  });

  it.each([publishClinic, unpublishClinic])('normalizes an expired session', async (call) => {
    rpc.mockResolvedValue({ data: null, error: { code: '28000', message: 'raw' } });
    expect(await call(CLINIC_ID)).toEqual({
      data: null,
      error: PROFESSIONAL_CONTEXT_AUTH_REQUIRED,
    });
  });

  it.each([publishClinic, unpublishClinic])(
    'reports another Clinic id as malformed',
    async (call) => {
      rpc.mockResolvedValue({ data: '22222222-2222-4222-8222-222222222222', error: null });
      expect(await call(CLINIC_ID)).toEqual({ data: null, error: CLINIC_SETTINGS_MALFORMED });
    },
  );

  it('keeps the publication requirement text for the mapper', async () => {
    rpc.mockResolvedValue({
      data: null,
      error: { code: '23514', message: 'Clinic publication requires a valid current Location' },
    });
    expect(await publishClinic(CLINIC_ID)).toEqual({
      data: null,
      error: 'Clinic publication requires a valid current Location',
    });
  });
});

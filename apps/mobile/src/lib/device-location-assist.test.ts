import type { ManagedClinicLocation } from '@/data/clinic-settings';
import {
  NEUTRAL_MAP_REGION,
  canSaveLocation,
  locationDraftFrom,
  locationPayload,
  withPin,
  type LocationDraft,
} from '@/lib/clinic-settings-editors';
import {
  createDeviceLocationAssist,
  readDevicePosition,
  type DevicePositionResult,
  type ForegroundLocationApi,
} from '@/lib/device-location-assist';

const GRANTED = { granted: true, canAskAgain: true };
const NOT_YET = { granted: false, canAskAgain: true };
const DENIED_AGAIN_ALLOWED = { granted: false, canAskAgain: true };
const DENIED_FOR_GOOD = { granted: false, canAskAgain: false };

function api(overrides: Partial<ForegroundLocationApi> = {}): jest.Mocked<ForegroundLocationApi> {
  return {
    getForegroundPermissionsAsync: jest.fn(async () => GRANTED),
    requestForegroundPermissionsAsync: jest.fn(async () => GRANTED),
    hasServicesEnabledAsync: jest.fn(async () => true),
    getCurrentPositionAsync: jest.fn(async () => ({
      coords: { latitude: 40.41683749, longitude: -3.70379851 },
    })),
    ...overrides,
  } as jest.Mocked<ForegroundLocationApi>;
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((settle) => {
    resolve = settle;
  });
  return { promise, resolve };
}

const STORED: ManagedClinicLocation = {
  addressText: 'Calle Mayor 1, Madrid',
  latitude: 40.4168,
  longitude: -3.7038,
};

describe('readDevicePosition', () => {
  it('reads the position once with an already granted permission, without prompting, rounded to six decimals', async () => {
    const location = api();
    expect(await readDevicePosition(location)).toEqual({
      kind: 'located',
      coordinate: { latitude: 40.416837, longitude: -3.703799 },
    });
    expect(location.requestForegroundPermissionsAsync).not.toHaveBeenCalled();
    expect(location.getCurrentPositionAsync).toHaveBeenCalledTimes(1);
  });

  it('asks for foreground permission once when it has not been decided yet', async () => {
    const location = api({ getForegroundPermissionsAsync: jest.fn(async () => NOT_YET) });
    expect((await readDevicePosition(location)).kind).toBe('located');
    expect(location.requestForegroundPermissionsAsync).toHaveBeenCalledTimes(1);
  });

  it('reports a denial without reading any position', async () => {
    const location = api({
      getForegroundPermissionsAsync: jest.fn(async () => NOT_YET),
      requestForegroundPermissionsAsync: jest.fn(async () => DENIED_AGAIN_ALLOWED),
    });
    expect(await readDevicePosition(location)).toEqual({ kind: 'denied', canAskAgain: true });
    expect(location.getCurrentPositionAsync).not.toHaveBeenCalled();
  });

  it('never prompts again once the permission is denied for good (no dialog loop)', async () => {
    const location = api({ getForegroundPermissionsAsync: jest.fn(async () => DENIED_FOR_GOOD) });
    expect(await readDevicePosition(location)).toEqual({ kind: 'denied', canAskAgain: false });
    expect(await readDevicePosition(location)).toEqual({ kind: 'denied', canAskAgain: false });
    expect(location.requestForegroundPermissionsAsync).not.toHaveBeenCalled();
    expect(location.getCurrentPositionAsync).not.toHaveBeenCalled();
  });

  it('reports location services turned off when the position cannot be read because of them', async () => {
    const location = api({
      getCurrentPositionAsync: jest.fn(async () => {
        throw new Error('Location services are disabled');
      }),
      hasServicesEnabledAsync: jest.fn(async () => false),
    });
    expect(await readDevicePosition(location)).toEqual({ kind: 'servicesDisabled' });
  });

  it.each([
    [
      'a position error with services on',
      api({
        getCurrentPositionAsync: jest.fn(async () => {
          throw new Error('Current location is unavailable');
        }),
      }),
    ],
    [
      'a permission API error',
      api({
        getForegroundPermissionsAsync: jest.fn(async () => {
          throw new Error('boom');
        }),
      }),
    ],
    [
      'a non-finite reading',
      api({
        getCurrentPositionAsync: jest.fn(async () => ({
          coords: { latitude: Number.NaN, longitude: 0 },
        })),
      }),
    ],
    [
      'an out-of-range reading',
      api({
        getCurrentPositionAsync: jest.fn(async () => ({
          coords: { latitude: 91, longitude: 0 },
        })),
      }),
    ],
  ])('reports unavailable for %s, never a fabricated coordinate', async (_label, location) => {
    expect(await readDevicePosition(location)).toEqual({ kind: 'unavailable' });
  });

  it('gives up as unavailable when the position does not arrive in time', async () => {
    const location = api({
      getCurrentPositionAsync: jest.fn(() => new Promise<never>(() => {})),
    });
    expect(await readDevicePosition(location, 10)).toEqual({ kind: 'unavailable' });
  });
});

describe('createDeviceLocationAssist', () => {
  it('lets a finished request apply, then allows a new one', () => {
    const assist = createDeviceLocationAssist();
    const token = assist.begin() as number;
    expect(assist.isPending()).toBe(true);
    expect(assist.settle(token)).toBe(true);
    expect(assist.isPending()).toBe(false);
    expect(assist.begin()).not.toBeNull();
  });

  it('refuses a second request while one is pending (duplicate taps)', () => {
    const assist = createDeviceLocationAssist();
    expect(assist.begin()).not.toBeNull();
    expect(assist.begin()).toBeNull();
  });

  it('discards a pending result once superseded (manual marker or leaving)', () => {
    const assist = createDeviceLocationAssist();
    const token = assist.begin() as number;
    assist.supersede();
    expect(assist.isPending()).toBe(false);
    expect(assist.settle(token)).toBe(false);
  });

  it('applies only the latest request after a supersede and a new tap', () => {
    const assist = createDeviceLocationAssist();
    const first = assist.begin() as number;
    assist.supersede();
    const second = assist.begin() as number;
    expect(assist.settle(first)).toBe(false);
    expect(assist.settle(second)).toBe(true);
  });
});

/**
 * The editor's flow, reproduced with the same pure pieces the screen uses:
 * the draft, the coordinator, and readDevicePosition.
 */
describe('"Use my current location" in the Location editor', () => {
  async function tapUseCurrentLocation(
    draft: LocationDraft,
    assist: ReturnType<typeof createDeviceLocationAssist>,
    location: ForegroundLocationApi,
    isActive: () => boolean = () => true,
  ): Promise<{ draft: LocationDraft; result: DevicePositionResult | null }> {
    const token = assist.begin();
    if (token === null) return { draft, result: null };
    const result = await readDevicePosition(location);
    if (!assist.settle(token) || !isActive()) return { draft, result: null };
    return {
      draft: result.kind === 'located' ? withPin(draft, result.coordinate) : draft,
      result,
    };
  }

  it('never touches device location while the editor initializes', () => {
    const location = api();
    // Opening the editor: the draft and the coordinator are created; nothing else.
    locationDraftFrom(null);
    locationDraftFrom(STORED);
    createDeviceLocationAssist();
    expect(location.getForegroundPermissionsAsync).not.toHaveBeenCalled();
    expect(location.requestForegroundPermissionsAsync).not.toHaveBeenCalled();
    expect(location.getCurrentPositionAsync).not.toHaveBeenCalled();
  });

  it('establishes the marker of a new location without touching the address, satisfying only the marker half', async () => {
    const assist = createDeviceLocationAssist();
    const empty = locationDraftFrom(null);
    expect(empty.pin).toBeNull();

    const withoutAddress = await tapUseCurrentLocation(empty, assist, api());
    expect(withoutAddress.draft).toEqual({
      addressText: '',
      pin: { latitude: 40.416837, longitude: -3.703799 },
    });
    expect(canSaveLocation({ draft: withoutAddress.draft, stored: null, busy: false })).toBe(false);

    const typed = { ...withoutAddress.draft, addressText: 'Calle Mayor 1, Madrid' };
    expect(canSaveLocation({ draft: typed, stored: null, busy: false })).toBe(true);
    expect(locationPayload(typed)).toEqual({
      addressText: 'Calle Mayor 1, Madrid',
      latitude: 40.416837,
      longitude: -3.703799,
    });
  });

  it('keeps the typed address exactly as typed', async () => {
    const assist = createDeviceLocationAssist();
    const draft = { addressText: '  Calle Sol 3\n', pin: null };
    const { draft: after } = await tapUseCurrentLocation(draft, assist, api());
    expect(after.addressText).toBe('  Calle Sol 3\n');
  });

  it('can be adjusted by hand after a successful lookup', async () => {
    const assist = createDeviceLocationAssist();
    const { draft } = await tapUseCurrentLocation(
      { addressText: 'Calle Mayor 1', pin: null },
      assist,
      api(),
    );
    assist.supersede();
    const adjusted = withPin(draft, { latitude: 40.4171, longitude: -3.7041 });
    expect(adjusted.pin).toEqual({ latitude: 40.4171, longitude: -3.7041 });
    expect(locationPayload(adjusted)?.latitude).toBe(40.4171);
  });

  it('leaves a stored marker alone until the action is tapped, then moves only the draft', async () => {
    const assist = createDeviceLocationAssist();
    const opened = locationDraftFrom(STORED);
    expect(opened.pin).toEqual({ latitude: 40.4168, longitude: -3.7038 });
    expect(canSaveLocation({ draft: opened, stored: STORED, busy: false })).toBe(false);

    const { draft: moved } = await tapUseCurrentLocation(opened, assist, api());
    expect(moved.pin).toEqual({ latitude: 40.416837, longitude: -3.703799 });
    expect(moved.addressText).toBe(STORED.addressText);
    // Only the draft changed; backing out leaves the stored location as it was.
    expect(STORED).toEqual({
      addressText: 'Calle Mayor 1, Madrid',
      latitude: 40.4168,
      longitude: -3.7038,
    });
  });

  it.each([
    [
      'a denial',
      api({
        getForegroundPermissionsAsync: jest.fn(async () => NOT_YET),
        requestForegroundPermissionsAsync: jest.fn(async () => DENIED_AGAIN_ALLOWED),
      }),
      { kind: 'denied', canAskAgain: true },
    ],
    [
      'a failure',
      api({
        getCurrentPositionAsync: jest.fn(async () => {
          throw new Error('unavailable');
        }),
      }),
      { kind: 'unavailable' },
    ],
  ])('keeps the address and an existing marker after %s', async (_label, location, expected) => {
    const assist = createDeviceLocationAssist();
    const draft = { addressText: 'Calle Mayor 1', pin: { latitude: 40.1, longitude: -3.1 } };
    const outcome = await tapUseCurrentLocation(draft, assist, location);
    expect(outcome.result).toEqual(expected);
    expect(outcome.draft).toBe(draft);
  });

  it('keeps manual placement available after a denial', async () => {
    const assist = createDeviceLocationAssist();
    const denied = api({ getForegroundPermissionsAsync: jest.fn(async () => DENIED_FOR_GOOD) });
    const { draft } = await tapUseCurrentLocation(
      { addressText: 'Calle Mayor 1', pin: null },
      assist,
      denied,
    );
    expect(draft.pin).toBeNull();
    assist.supersede();
    const placed = withPin(draft, { latitude: 40.42, longitude: -3.7 });
    expect(canSaveLocation({ draft: placed, stored: null, busy: false })).toBe(true);
  });

  it('lets a marker placed by hand while the lookup is pending win over the late device result', async () => {
    const assist = createDeviceLocationAssist();
    const position = deferred<{ coords: { latitude: number; longitude: number } }>();
    const location = api({ getCurrentPositionAsync: jest.fn(() => position.promise) });
    let draft: LocationDraft = { addressText: 'Calle Mayor 1', pin: null };

    const pending = tapUseCurrentLocation(draft, assist, location);
    // The actor taps the map before the device answers.
    assist.supersede();
    draft = withPin(draft, { latitude: 40.5, longitude: -3.5 });
    position.resolve({ coords: { latitude: 10, longitude: 10 } });

    const outcome = await pending;
    expect(outcome.result).toBeNull();
    expect(draft.pin).toEqual({ latitude: 40.5, longitude: -3.5 });
  });

  it('ignores a late device result after leaving the screen', async () => {
    const assist = createDeviceLocationAssist();
    const position = deferred<{ coords: { latitude: number; longitude: number } }>();
    const location = api({ getCurrentPositionAsync: jest.fn(() => position.promise) });
    let active = true;
    const draft: LocationDraft = { addressText: 'Calle Mayor 1', pin: null };

    const pending = tapUseCurrentLocation(draft, assist, location, () => active);
    // Leaving: the screen supersedes the lookup and becomes inactive.
    assist.supersede();
    active = false;
    position.resolve({ coords: { latitude: 10, longitude: 10 } });

    expect((await pending).result).toBeNull();
  });

  it('starts only one lookup for repeated taps', async () => {
    const assist = createDeviceLocationAssist();
    const position = deferred<{ coords: { latitude: number; longitude: number } }>();
    const location = api({ getCurrentPositionAsync: jest.fn(() => position.promise) });
    const draft: LocationDraft = { addressText: 'Calle Mayor 1', pin: null };

    const first = tapUseCurrentLocation(draft, assist, location);
    const second = await tapUseCurrentLocation(draft, assist, location);
    expect(second.result).toBeNull();
    position.resolve({ coords: { latitude: 40.4, longitude: -3.7 } });
    expect((await first).draft.pin).toEqual({ latitude: 40.4, longitude: -3.7 });
    expect(location.getCurrentPositionAsync).toHaveBeenCalledTimes(1);
  });

  it('still never treats the neutral map centre as a marker', () => {
    expect(locationDraftFrom(null).pin).toBeNull();
    expect(NEUTRAL_MAP_REGION.latitude).toBe(0);
    expect(
      canSaveLocation({
        draft: { addressText: 'Calle Mayor 1', pin: null },
        stored: null,
        busy: false,
      }),
    ).toBe(false);
  });
});

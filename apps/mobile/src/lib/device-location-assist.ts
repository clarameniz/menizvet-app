import { roundedCoordinate, type Coordinate } from '@/lib/clinic-settings-editors';

/**
 * "Use my current location" for the Clinic Location editor (SPEC-CLI-002
 * BR-13, BR-18): an optional, explicitly user-triggered convenience that reads
 * the device's foreground position once to PROPOSE the draft marker. It is
 * not proof that the Clinic is there; the actor can adjust the marker, and
 * only Save persists anything. No address is read, written, or inferred, and
 * the position is never sent anywhere or logged.
 *
 * Plain, React-free logic so its decisions are unit-tested; the screen wires it
 * to `expo-location` and to its own lifecycle.
 */

/** The subset of `expo-location` this module uses (injected, so tests need no device). */
export type ForegroundLocationApi = {
  getForegroundPermissionsAsync: () => Promise<{ granted: boolean; canAskAgain: boolean }>;
  requestForegroundPermissionsAsync: () => Promise<{ granted: boolean; canAskAgain: boolean }>;
  hasServicesEnabledAsync: () => Promise<boolean>;
  getCurrentPositionAsync: () => Promise<{ coords: { latitude: number; longitude: number } }>;
};

export type DevicePositionResult =
  | { kind: 'located'; coordinate: Coordinate }
  /** Permission not granted; `canAskAgain: false` means only the device settings can change it. */
  | { kind: 'denied'; canAskAgain: boolean }
  | { kind: 'servicesDisabled' }
  /** No position: timeout, error, or an unusable reading. */
  | { kind: 'unavailable' };

/** How long one position lookup may take before it is treated as unavailable. */
export const DEVICE_POSITION_TIMEOUT_MS = 15_000;

class DevicePositionTimeout extends Error {}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new DevicePositionTimeout()), timeoutMs);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error: unknown) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

function isUsable(coordinate: Coordinate): boolean {
  return (
    Number.isFinite(coordinate.latitude) &&
    Number.isFinite(coordinate.longitude) &&
    Math.abs(coordinate.latitude) <= 90 &&
    Math.abs(coordinate.longitude) <= 180
  );
}

/**
 * Reads the device's current foreground position once. Asks for foreground
 * permission only if it is not granted and the system still allows asking —
 * a permanently denied permission is reported without prompting again, so a
 * repeated tap never loops the system dialog. Never requests background
 * location. The coordinate is canonicalized to the editor's six decimals.
 */
export async function readDevicePosition(
  api: ForegroundLocationApi,
  timeoutMs: number = DEVICE_POSITION_TIMEOUT_MS,
): Promise<DevicePositionResult> {
  try {
    let permission = await api.getForegroundPermissionsAsync();
    if (!permission.granted) {
      if (!permission.canAskAgain) return { kind: 'denied', canAskAgain: false };
      permission = await api.requestForegroundPermissionsAsync();
      if (!permission.granted) return { kind: 'denied', canAskAgain: permission.canAskAgain };
    }
  } catch {
    return { kind: 'unavailable' };
  }

  try {
    const position = await withTimeout(api.getCurrentPositionAsync(), timeoutMs);
    const coordinate = {
      latitude: position.coords.latitude,
      longitude: position.coords.longitude,
    };
    return isUsable(coordinate)
      ? { kind: 'located', coordinate: roundedCoordinate(coordinate) }
      : { kind: 'unavailable' };
  } catch (error) {
    if (error instanceof DevicePositionTimeout) return { kind: 'unavailable' };
    // Distinguish "location services are off" for clearer copy; anything
    // else (or an error while checking) is simply unavailable.
    try {
      return (await api.hasServicesEnabledAsync())
        ? { kind: 'unavailable' }
        : { kind: 'servicesDisabled' };
    } catch {
      return { kind: 'unavailable' };
    }
  }
}

/**
 * Coordinates "Use my current location" requests with everything else that
 * can establish the marker:
 *
 * - `begin()` starts a request and returns its token, or `null` while one is
 *   already pending, so repeated taps never start conflicting requests;
 * - `supersede()` — called when the actor places the marker by hand (map tap,
 *   drag, "centre of the map") or the screen leaves — invalidates any pending
 *   request: its late result must not overwrite the actor's choice;
 * - `settle(token)` says whether a finished request may still apply: only the
 *   latest, not superseded one. It also ends the pending state.
 */
export type DeviceLocationAssist = {
  begin: () => number | null;
  supersede: () => void;
  settle: (token: number) => boolean;
  isPending: () => boolean;
};

export function createDeviceLocationAssist(): DeviceLocationAssist {
  let latest = 0;
  let pending: number | null = null;

  return {
    begin() {
      if (pending !== null) return null;
      latest += 1;
      pending = latest;
      return latest;
    },
    supersede() {
      latest += 1;
      pending = null;
    },
    settle(token) {
      const current = token === latest && pending === token;
      if (pending === token) pending = null;
      return current;
    },
    isPending() {
      return pending !== null;
    },
  };
}

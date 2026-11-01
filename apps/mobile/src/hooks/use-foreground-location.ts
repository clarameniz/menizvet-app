import * as Location from 'expo-location';
import { useCallback, useEffect, useRef, useState } from 'react';

export type ForegroundLocationStatus =
  'idle' | 'requesting' | 'locating' | 'located' | 'denied' | 'unavailable';

export type ForegroundLocationCoords = { latitude: number; longitude: number };

export type ForegroundLocationState = {
  status: ForegroundLocationStatus;
  coords: ForegroundLocationCoords | null;
  requestLocation: () => Promise<void>;
};

/**
 * Foreground-only device location (no background permission, no background
 * task — SPEC-DIS-002/003 both require device location to remain optional
 * and never fabricated). Shared by /clinics/nearby and /clinics/map's
 * "Use my location" action: the only two screens that need this exact
 * permission → one-shot-position lifecycle, which is genuine reusable
 * React-lifecycle behavior, not a relocated plain function.
 */
export function useForegroundLocation(): ForegroundLocationState {
  const [status, setStatus] = useState<ForegroundLocationStatus>('idle');
  const [coords, setCoords] = useState<ForegroundLocationCoords | null>(null);
  const isMountedRef = useRef(true);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const requestLocation = useCallback(async () => {
    setStatus('requesting');

    try {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (!isMountedRef.current) return;

      if (permission.status !== Location.PermissionStatus.GRANTED) {
        setStatus('denied');
        return;
      }

      setStatus('locating');

      const position = await Location.getCurrentPositionAsync({
        accuracy: Location.Accuracy.Balanced,
      });
      if (!isMountedRef.current) return;

      setCoords({ latitude: position.coords.latitude, longitude: position.coords.longitude });
      setStatus('located');
    } catch {
      if (!isMountedRef.current) return;
      setStatus('unavailable');
    }
  }, []);

  return { status, coords, requestLocation };
}

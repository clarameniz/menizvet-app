import {
  createLatestRequestGuard,
  formatDistanceMeters,
  INITIAL_MAP_REGION,
  mergeClinicsById,
  regionForRadiusMeters,
  regionToShowSelectedClinic,
  regionToViewportBounds,
  SELECTED_CLINIC_MAX_DELTAS,
  splitViewportAtAntimeridian,
} from '@/lib/discovery-viewport';

describe('regionToShowSelectedClinic', () => {
  const MADRID = { latitude: 40.4168, longitude: -3.7038 };
  const close = (center: { latitude: number; longitude: number }, latitudeDelta = 0.02) => ({
    ...center,
    latitudeDelta,
    longitudeDelta: latitudeDelta * 0.7,
  });

  it('zooms in to the local view of 0.1° by 0.06°, centred on the Clinic', () => {
    expect(SELECTED_CLINIC_MAX_DELTAS).toEqual({ latitudeDelta: 0.1, longitudeDelta: 0.06 });
    const far = { latitude: 40, longitude: -2.9, latitudeDelta: 21.4, longitudeDelta: 15.2 };
    expect(regionToShowSelectedClinic(far, MADRID)).toEqual({
      ...MADRID,
      latitudeDelta: 0.1,
      longitudeDelta: 0.06,
    });
  });

  it('a view wider on one side only is narrowed on that side alone', () => {
    // Landscape-like: latitude already close, longitude too wide.
    const wide = { ...MADRID, latitudeDelta: 0.05, longitudeDelta: 0.2 };
    expect(regionToShowSelectedClinic(wide, MADRID)).toEqual({
      ...MADRID,
      latitudeDelta: 0.05,
      longitudeDelta: 0.06,
    });
    // Portrait-like: longitude already close, latitude too tall.
    const tall = { ...MADRID, latitudeDelta: 0.3, longitudeDelta: 0.04 };
    expect(regionToShowSelectedClinic(tall, MADRID)).toEqual({
      ...MADRID,
      latitudeDelta: 0.1,
      longitudeDelta: 0.04,
    });
  });

  it('keeps a close enough view with the Clinic clear of the edges', () => {
    expect(regionToShowSelectedClinic(close(MADRID), MADRID)).toBeNull();
    expect(
      regionToShowSelectedClinic({ ...MADRID, ...SELECTED_CLINIC_MAX_DELTAS }, MADRID),
    ).toBeNull();
    // Slightly off centre, still clear.
    expect(
      regionToShowSelectedClinic(close(MADRID), { latitude: 40.4188, longitude: -3.7008 }),
    ).toBeNull();
  });

  it.each([
    ['the top edge', { latitude: 40.4168 + 0.0085, longitude: -3.7038 }],
    ['the bottom edge', { latitude: 40.4168 - 0.0055, longitude: -3.7038 }],
    ['the left edge', { latitude: 40.4168, longitude: -3.7038 - 0.0055 }],
    ['the right edge', { latitude: 40.4168, longitude: -3.7038 + 0.0055 }],
    ['outside the view', { latitude: 41.39, longitude: 2.17 }],
  ])('recentres at the same span when the Clinic is near %s', (_edge, clinic) => {
    const current = close(MADRID);
    expect(regionToShowSelectedClinic(current, clinic)).toEqual({
      ...clinic,
      latitudeDelta: current.latitudeDelta,
      longitudeDelta: current.longitudeDelta,
    });
  });

  it('never zooms out', () => {
    for (const latitudeDelta of [0.001, 0.01, 0.05, 0.051, 0.5, 5, 60]) {
      const current = { latitude: 0, longitude: 0, latitudeDelta, longitudeDelta: latitudeDelta };
      for (const clinic of [
        { latitude: 0, longitude: 0 },
        { latitude: latitudeDelta * 0.49, longitude: 0 },
        { latitude: 10, longitude: 10 },
      ]) {
        const focus = regionToShowSelectedClinic(current, clinic);
        if (focus === null) continue;
        expect(focus.latitudeDelta).toBeLessThanOrEqual(latitudeDelta);
        expect(focus.longitudeDelta).toBeLessThanOrEqual(latitudeDelta);
      }
    }
  });
});

describe('INITIAL_MAP_REGION', () => {
  const bounds = regionToViewportBounds(INITIAL_MAP_REGION);

  it.each([
    ['Estaca de Bares (north)', 43.79, -7.69],
    ['Tarifa (south)', 36.01, -5.6],
    ['Fisterra (west)', 42.88, -9.27],
    ['Cap de Creus (north-east)', 42.32, 3.32],
    ['Menorca, east coast', 39.87, 4.32],
    ['Formentera', 38.7, 1.45],
    ['Madrid', 40.42, -3.7],
  ])('shows %s', (_place, latitude, longitude) => {
    expect(latitude).toBeGreaterThanOrEqual(bounds.minLatitude);
    expect(latitude).toBeLessThanOrEqual(bounds.maxLatitude);
    expect(longitude).toBeGreaterThanOrEqual(bounds.minLongitude);
    expect(longitude).toBeLessThanOrEqual(bounds.maxLongitude);
  });

  it('is one legal viewport the size of a country, never the whole world', () => {
    const legal = splitViewportAtAntimeridian(bounds);
    expect(legal).toHaveLength(1);
    expect(legal[0].maxLongitude - legal[0].minLongitude).toBeLessThan(20);
    expect(legal[0].maxLatitude - legal[0].minLatitude).toBeLessThan(12);
  });
});

describe('regionToViewportBounds', () => {
  it('derives min/max lat/lon from a region centered away from any boundary', () => {
    expect(
      regionToViewportBounds({
        latitude: 40,
        longitude: -3,
        latitudeDelta: 10,
        longitudeDelta: 10,
      }),
    ).toEqual({ minLatitude: 35, maxLatitude: 45, minLongitude: -8, maxLongitude: 2 });
  });

  it('clamps latitude at the poles rather than exceeding [-90, 90]', () => {
    const bounds = regionToViewportBounds({
      latitude: 85,
      longitude: 0,
      latitudeDelta: 20,
      longitudeDelta: 10,
    });

    expect(bounds.maxLatitude).toBe(90);
    expect(bounds.minLatitude).toBe(75);
  });

  it('clamps the south pole the same way', () => {
    const bounds = regionToViewportBounds({
      latitude: -85,
      longitude: 0,
      latitudeDelta: 20,
      longitudeDelta: 10,
    });

    expect(bounds.minLatitude).toBe(-90);
    expect(bounds.maxLatitude).toBe(-75);
  });

  it('leaves longitude raw (possibly outside [-180, 180]) for splitViewportAtAntimeridian to normalize', () => {
    const bounds = regionToViewportBounds({
      latitude: 0,
      longitude: 179,
      latitudeDelta: 10,
      longitudeDelta: 10,
    });

    expect(bounds.minLongitude).toBe(174);
    expect(bounds.maxLongitude).toBe(184);
  });
});

describe('splitViewportAtAntimeridian', () => {
  it('returns a single legal range unchanged when there is no crossing', () => {
    const result = splitViewportAtAntimeridian({
      minLatitude: -10,
      maxLatitude: 10,
      minLongitude: 10,
      maxLongitude: 20,
    });

    expect(result).toEqual([
      { minLatitude: -10, maxLatitude: 10, minLongitude: 10, maxLongitude: 20 },
    ]);
  });

  it('does not misdetect a non-crossing viewport that exactly reaches the +180 boundary', () => {
    const result = splitViewportAtAntimeridian({
      minLatitude: -10,
      maxLatitude: 10,
      minLongitude: 160,
      maxLongitude: 180,
    });

    expect(result).toEqual([
      { minLatitude: -10, maxLatitude: 10, minLongitude: 160, maxLongitude: 180 },
    ]);
  });

  it('splits a genuinely crossing viewport into two legal, non-crossing ranges', () => {
    const result = splitViewportAtAntimeridian({
      minLatitude: -5,
      maxLatitude: 5,
      minLongitude: 174,
      maxLongitude: 184,
    });

    expect(result).toEqual([
      { minLatitude: -5, maxLatitude: 5, minLongitude: 174, maxLongitude: 180 },
      { minLatitude: -5, maxLatitude: 5, minLongitude: -180, maxLongitude: -176 },
    ]);
  });

  it('splits a viewport that wraps on the negative side', () => {
    const result = splitViewportAtAntimeridian({
      minLatitude: -5,
      maxLatitude: 5,
      minLongitude: -185,
      maxLongitude: -170,
    });

    expect(result).toEqual([
      { minLatitude: -5, maxLatitude: 5, minLongitude: 175, maxLongitude: 180 },
      { minLatitude: -5, maxLatitude: 5, minLongitude: -180, maxLongitude: -170 },
    ]);
  });

  it('collapses a whole-world span to the full legal range without treating it as crossing', () => {
    const result = splitViewportAtAntimeridian({
      minLatitude: -90,
      maxLatitude: 90,
      minLongitude: -400,
      maxLongitude: 400,
    });

    expect(result).toEqual([
      { minLatitude: -90, maxLatitude: 90, minLongitude: -180, maxLongitude: 180 },
    ]);
  });
});

describe('mergeClinicsById', () => {
  it('de-duplicates strictly by clinicId across split-query pages', () => {
    const pageA = [{ clinicId: 'a', displayName: 'Alpha' }];
    const pageB = [
      { clinicId: 'a', displayName: 'Alpha' },
      { clinicId: 'b', displayName: 'Beta' },
    ];

    expect(mergeClinicsById([pageA, pageB])).toEqual([
      { clinicId: 'a', displayName: 'Alpha' },
      { clinicId: 'b', displayName: 'Beta' },
    ]);
  });

  it('never merges distinct Clinics that merely share a display name', () => {
    const pageA = [{ clinicId: 'a', displayName: 'Animalia' }];
    const pageB = [{ clinicId: 'b', displayName: 'Animalia' }];

    expect(mergeClinicsById([pageA, pageB])).toEqual([
      { clinicId: 'a', displayName: 'Animalia' },
      { clinicId: 'b', displayName: 'Animalia' },
    ]);
  });

  it('returns an empty array for empty input', () => {
    expect(mergeClinicsById([])).toEqual([]);
  });
});

describe('createLatestRequestGuard', () => {
  it('treats the most recently begun token as current', () => {
    const guard = createLatestRequestGuard();
    const first = guard.begin();
    const second = guard.begin();

    expect(guard.isCurrent(first)).toBe(false);
    expect(guard.isCurrent(second)).toBe(true);
  });

  it('treats a single begun token as current until a newer one starts', () => {
    const guard = createLatestRequestGuard();
    const token = guard.begin();

    expect(guard.isCurrent(token)).toBe(true);
  });
});

describe('formatDistanceMeters', () => {
  it('rounds sub-kilometer distances to the nearest 10 meters', () => {
    expect(formatDistanceMeters(432)).toEqual({ key: 'discoveryDistance.meters', count: '430' });
  });

  it('never rounds below zero for a very small distance', () => {
    expect(formatDistanceMeters(2)).toEqual({ key: 'discoveryDistance.meters', count: '0' });
  });

  it('formats distances at or above 1 km with one decimal', () => {
    expect(formatDistanceMeters(1500)).toEqual({
      key: 'discoveryDistance.kilometers',
      count: '1.5',
    });
  });

  it('formats exactly 1000 meters as kilometers, not meters', () => {
    expect(formatDistanceMeters(1000)).toEqual({
      key: 'discoveryDistance.kilometers',
      count: '1.0',
    });
  });
});

describe('regionForRadiusMeters', () => {
  it('derives a positive, finite lat/lon delta from the approved radius constant', () => {
    const region = regionForRadiusMeters({ latitude: 40.4168, longitude: -3.7038 }, 10_000);

    expect(region.latitude).toBe(40.4168);
    expect(region.longitude).toBe(-3.7038);
    expect(region.latitudeDelta).toBeGreaterThan(0);
    expect(region.longitudeDelta).toBeGreaterThan(0);
    expect(Number.isFinite(region.latitudeDelta)).toBe(true);
    expect(Number.isFinite(region.longitudeDelta)).toBe(true);
  });

  it('keeps the longitude delta bounded even very close to a pole', () => {
    const region = regionForRadiusMeters({ latitude: 89.99, longitude: 0 }, 10_000);

    expect(Number.isFinite(region.longitudeDelta)).toBe(true);
  });
});

import { router } from 'expo-router';
import { createElement } from 'react';
import { AccessibilityInfo, StyleSheet, Text } from 'react-native';
import { act, create, type ReactTestInstance, type ReactTestRenderer } from 'react-test-renderer';

import ClinicsMapScreen from '@/app/clinics/map';
import { discoverClinicsInViewport, type GeographicClinicSummary } from '@/data/clinics';
import { i18n } from '@/i18n/i18n';
import { INITIAL_MAP_REGION } from '@/lib/discovery-viewport';
import { colors } from '@/theme/colors';

/**
 * Map Discovery's start (SPEC-DIS-003 §8, BR-9): the map opens on Spain, the
 * only automatic read is of the region the map first reports as visible —
 * never before it, never the whole world, never twice — and every later read
 * is explicit ("Search this area", "My location"). The native map is replaced
 * by a host component that exposes its props, so the test drives the
 * region reports and presses the real map would emit.
 *
 * Selection: no native callout unless a screen reader is on, the selected
 * marker drawn as the app's own pin in the MenizVet green, the bottom card as the only summary, and a
 * tap on the map itself clearing the selection.
 */

jest.mock('react-native-maps', () => {
  const {
    createElement: mockCreateElement,
    forwardRef,
    useImperativeHandle,
  } = jest.requireActual<typeof import('react')>('react');
  const MockMapView = forwardRef((props: Record<string, unknown>, ref) => {
    useImperativeHandle(ref, () => ({ animateToRegion: mockAnimateToRegion }));
    return mockCreateElement('MockMapView', props, props.children as never);
  });
  const MockMarker = (props: Record<string, unknown>) =>
    mockCreateElement('MockMarker', props, props.children as never);
  return { __esModule: true, default: MockMapView, Marker: MockMarker };
});
const mockAnimateToRegion = jest.fn();
jest.mock('expo-router', () => ({
  router: { push: jest.fn(), replace: jest.fn(), back: jest.fn(), canGoBack: jest.fn(() => true) },
}));
jest.mock('@/components/design-system/public-top-bar', () => ({ PublicTopBar: () => null }));
jest.mock('react-native-safe-area-context', () => ({
  useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
}));
jest.mock('@/i18n/locale-provider', () => {
  const { i18n: mockI18n } = jest.requireActual('@/i18n/i18n');
  return { useLocale: () => ({ locale: 'es', t: mockI18n.t.bind(mockI18n) }) };
});
let mockLocation: {
  status: string;
  coords: { latitude: number; longitude: number } | null;
  requestLocation: jest.Mock;
};
jest.mock('@/hooks/use-foreground-location', () => ({
  useForegroundLocation: () => mockLocation,
}));
jest.mock('@/data/clinics', () => ({
  ...jest.requireActual('@/data/clinics'),
  discoverClinicsInViewport: jest.fn(),
}));
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: jest.fn() } }));

const read = discoverClinicsInViewport as jest.Mock;

const clinic = (n: number, latitude: number, longitude: number): GeographicClinicSummary => ({
  clinicId: `clinic-${n}`,
  displayName: `Clínica ${n}`,
  description: null,
  publicPhone: null,
  publicEmail: null,
  website: null,
  addressText: `Calle ${n}`,
  latitude,
  longitude,
});

const page = (clinics: GeographicClinicSummary[], hasMore = false) => ({
  data: { clinics, hasMore, nextAfterClinicId: null },
  error: null,
});

// What a portrait phone shows for the starting camera: the map widens the
// latitude span to fit the screen's aspect ratio.
const SHOWN_SPAIN = { latitude: 40.0, longitude: -2.9, latitudeDelta: 21.4, longitudeDelta: 15.2 };
const SHOWN_LISBON = { latitude: 38.72, longitude: -9.14, latitudeDelta: 0.6, longitudeDelta: 0.4 };

let tree: ReactTestRenderer;
const t = (key: string) => i18n.t(key);
const allText = () =>
  tree.root
    .findAllByType(Text)
    .map((node) => String(node.props.children))
    .join(' | ');
const map = () => tree.root.find((node) => (node.type as unknown) === 'MockMapView');
const markers = () => tree.root.findAll((node) => (node.type as unknown) === 'MockMarker');
const button = (label: string) =>
  tree.root.findAll(
    (node) =>
      node.props.accessibilityRole === 'button' &&
      typeof node.props.onPress === 'function' &&
      node.props.accessibilityLabel === label,
  )[0] as ReactTestInstance | undefined;
async function press(node: ReactTestInstance | undefined) {
  if (node === undefined) throw new Error('No such control');
  await act(async () => node.props.onPress());
}
async function reportRegion(region: typeof SHOWN_SPAIN) {
  await act(async () => map().props.onRegionChangeComplete(region, { isGesture: false }));
}
async function render() {
  await act(async () => {
    tree = create(createElement(ClinicsMapScreen));
  });
}

let screenReaderOn = false;
let screenReaderListener: ((enabled: boolean) => void) | null = null;
const announce = jest
  .spyOn(AccessibilityInfo, 'announceForAccessibility')
  .mockImplementation(() => {});
jest
  .spyOn(AccessibilityInfo, 'isScreenReaderEnabled')
  .mockImplementation(() => Promise.resolve(screenReaderOn));
jest.spyOn(AccessibilityInfo, 'addEventListener').mockImplementation((_event, listener) => {
  screenReaderListener = listener as unknown as (enabled: boolean) => void;
  return { remove: () => (screenReaderListener = null) } as unknown as ReturnType<
    typeof AccessibilityInfo.addEventListener
  >;
});

const marker = (id: string) => markers().find((node) => node.props.identifier === id)!;
// Drawn with the app's own green pin (never the platform's hue-only `pinColor`).
const isHighlighted = (node: ReactTestInstance) =>
  node.findAll((child) => child.props.testID === 'selected-clinic-pin').length > 0 &&
  node.props.pinColor === undefined;
async function pressMarker(id: string) {
  await act(async () => marker(id).props.onPress());
}
async function pressMap(action: 'press' | 'marker-press' = 'press') {
  await act(async () =>
    map().props.onPress({ nativeEvent: { action, coordinate: { latitude: 40, longitude: -3 } } }),
  );
}
// Host nodes only: each card is one native view, however many components wrap it.
const cardFor = (name: string) =>
  tree.root.findAll(
    (node) =>
      typeof node.type === 'string' &&
      node.props.accessibilityRole === 'button' &&
      typeof node.props.accessibilityLabel === 'string' &&
      node.props.accessibilityLabel.startsWith(name),
  );
// The card's pressable component (the one carrying onPress).
const openCard = (name: string) =>
  press(
    tree.root.findAll(
      (node) =>
        node.props.accessibilityRole === 'button' &&
        typeof node.props.onPress === 'function' &&
        typeof node.props.accessibilityLabel === 'string' &&
        node.props.accessibilityLabel.startsWith(name),
    )[0],
  );

beforeEach(() => {
  jest.clearAllMocks();
  i18n.locale = 'es';
  screenReaderOn = false;
  mockLocation = { status: 'idle', coords: null, requestLocation: jest.fn() };
  read.mockResolvedValue(page([clinic(1, 40.42, -3.7), clinic(2, 41.39, 2.17)]));
});
afterEach(() => act(() => tree.unmount()));

it('opens on Spain and reads nothing until the map reports what it shows', async () => {
  await render();
  expect(map().props.initialRegion).toEqual(INITIAL_MAP_REGION);
  expect(read).not.toHaveBeenCalled();
  expect(mockLocation.requestLocation).not.toHaveBeenCalled();
});

it('the first reported region is read once, with its visible bounds — never the world', async () => {
  await render();
  await reportRegion(SHOWN_SPAIN);
  expect(read).toHaveBeenCalledTimes(1);
  const [bounds, cursor] = read.mock.calls[0];
  expect(cursor).toBeNull();
  expect(bounds.minLatitude).toBeCloseTo(29.3);
  expect(bounds.maxLatitude).toBeCloseTo(50.7);
  expect(bounds.minLongitude).toBeCloseTo(-10.5);
  expect(bounds.maxLongitude).toBeCloseTo(4.7);
  expect(bounds.maxLongitude - bounds.minLongitude).toBeLessThan(20);
  expect(markers().map((marker) => marker.props.identifier)).toEqual(['clinic-1', 'clinic-2']);
});

it('repeated start-up reports and later movements read nothing by themselves', async () => {
  await render();
  await reportRegion(SHOWN_SPAIN);
  await reportRegion(SHOWN_SPAIN);
  await reportRegion(SHOWN_LISBON);
  expect(read).toHaveBeenCalledTimes(1);
});

it('panning and zooming elsewhere, then Search this area, reads the new visible area', async () => {
  await render();
  await reportRegion(SHOWN_SPAIN);
  read.mockResolvedValueOnce(page([clinic(3, 38.72, -9.14)]));
  await reportRegion(SHOWN_LISBON);
  await press(button(t('discoveryMap.searchThisArea')));
  expect(read).toHaveBeenCalledTimes(2);
  const [bounds] = read.mock.calls[1];
  expect(bounds.minLongitude).toBeCloseTo(-9.34);
  expect(bounds.maxLongitude).toBeCloseTo(-8.94);
  expect(markers().map((marker) => marker.props.identifier)).toEqual(['clinic-3']);
});

it('a search started before the first report is not followed by an automatic one', async () => {
  await render();
  await press(button(t('discoveryMap.searchThisArea')));
  expect(read).toHaveBeenCalledTimes(1);
  await reportRegion(SHOWN_SPAIN);
  expect(read).toHaveBeenCalledTimes(1);
});

it('My location still recentres and reads around the device position', async () => {
  await render();
  await reportRegion(SHOWN_SPAIN);
  await press(button(t('discoveryMap.myLocation')));
  expect(mockLocation.requestLocation).toHaveBeenCalledTimes(1);

  mockLocation = {
    ...mockLocation,
    status: 'located',
    coords: { latitude: 37.39, longitude: -5.98 },
  };
  await act(async () => tree.update(createElement(ClinicsMapScreen)));
  expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
  expect(read).toHaveBeenCalledTimes(2);
  const [bounds] = read.mock.calls[1];
  expect(bounds.minLatitude).toBeLessThan(37.39);
  expect(bounds.maxLatitude).toBeGreaterThan(37.39);
  expect(bounds.maxLatitude - bounds.minLatitude).toBeLessThan(1);
});

it('a failed first read shows the error, and Search this area retries', async () => {
  read.mockResolvedValueOnce({ data: null, error: 'timeout' });
  await render();
  await reportRegion(SHOWN_SPAIN);
  expect(allText()).toContain(t('discoveryMap.loadError'));
  expect(markers()).toHaveLength(0);

  await press(button(t('discoveryMap.searchThisArea')));
  expect(allText()).not.toContain(t('discoveryMap.loadError'));
  expect(markers()).toHaveLength(2);
});

it('an area without Clinics shows the empty notice', async () => {
  read.mockResolvedValueOnce(page([]));
  await render();
  await reportRegion(SHOWN_SPAIN);
  expect(allText()).toContain(t('discoveryMap.emptyArea'));
  expect(markers()).toHaveLength(0);
});

it('more Clinics than one page asks to zoom in', async () => {
  read.mockResolvedValueOnce(page([clinic(1, 40.42, -3.7)], true));
  await render();
  await reportRegion(SHOWN_SPAIN);
  expect(allText()).toContain(t('discoveryMap.zoomInPrompt'));
});

it('a selected marker shows its card, which opens the Clinic', async () => {
  await render();
  await reportRegion(SHOWN_SPAIN);
  await act(async () => markers()[1].props.onPress());
  expect(allText()).toContain('Clínica 2');
  await press(
    tree.root.findAll(
      (node) =>
        node.props.accessibilityRole === 'button' &&
        typeof node.props.accessibilityLabel === 'string' &&
        node.props.accessibilityLabel.startsWith('Clínica 2'),
    )[0],
  );
  expect(router.push).toHaveBeenCalledWith('/clinics/clinic-2');
});

describe('Marker selection', () => {
  const NEAR = [clinic(1, 40.4168, -3.7038), clinic(2, 40.4169, -3.7037), clinic(3, 41.39, 2.17)];

  beforeEach(() => {
    read.mockResolvedValue(page(NEAR));
  });

  it('shows no native callout: markers carry no title, only their accessible name', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    for (const node of markers()) {
      expect(node.props.title).toBeUndefined();
      expect(node.props.accessibilityLabel).toMatch(/^Clínica \d$/);
      expect(isHighlighted(node)).toBe(false);
    }
  });

  it('a selected marker turns green, shows the bottom card and is announced', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await pressMarker('clinic-2');
    expect(isHighlighted(marker('clinic-2'))).toBe(true);
    // Exactly the app's primary green, never a platform tint.
    const pinColors = marker('clinic-2')
      .findAll((node) => typeof node.type === 'string')
      .map((node) => StyleSheet.flatten(node.props.style) ?? {})
      .flatMap((style) => [style.backgroundColor, style.borderTopColor])
      .filter(
        (color) => color !== undefined && color !== 'transparent' && color !== colors.surface,
      );
    expect(new Set(pinColors)).toEqual(new Set([colors.primary]));
    expect(marker('clinic-2').props.anchor).toEqual({ x: 0.5, y: 1 });
    expect(marker('clinic-2').props.accessibilityState).toEqual({ selected: true });
    expect(isHighlighted(marker('clinic-1'))).toBe(false);
    expect(isHighlighted(marker('clinic-3'))).toBe(false);
    expect(cardFor('Clínica 2')).toHaveLength(1);
    expect(announce).toHaveBeenCalledWith(
      i18n.t('discoveryMap.selectedAnnouncement', { name: 'Clínica 2' }),
    );
  });

  it('choosing a nearby marker moves the highlight and the card', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await pressMarker('clinic-1');
    await pressMarker('clinic-2');
    expect(isHighlighted(marker('clinic-1'))).toBe(false);
    expect(isHighlighted(marker('clinic-2'))).toBe(true);
    expect(cardFor('Clínica 1')).toHaveLength(0);
    expect(cardFor('Clínica 2')).toHaveLength(1);
  });

  it('a tap on an empty part of the map clears the selection', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await pressMarker('clinic-3');
    await pressMap('press');
    expect(isHighlighted(marker('clinic-3'))).toBe(false);
    expect(cardFor('Clínica 3')).toHaveLength(0);
    expect(read).toHaveBeenCalledTimes(1);
  });

  it('a marker press bubbled up to the map (iOS) keeps the selection', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await pressMarker('clinic-3');
    await pressMap('marker-press');
    expect(isHighlighted(marker('clinic-3'))).toBe(true);
    expect(cardFor('Clínica 3')).toHaveLength(1);
  });

  it('the bottom card opens the profile; back on the map the selection is kept', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await pressMarker('clinic-1');
    await openCard('Clínica 1');
    expect(router.push).toHaveBeenCalledWith('/clinics/clinic-1');
    // The map stays mounted beneath the profile: nothing is reset or re-read.
    expect(isHighlighted(marker('clinic-1'))).toBe(true);
    expect(read).toHaveBeenCalledTimes(1);
  });

  it('a new search clears the selection', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await pressMarker('clinic-1');
    await press(button(i18n.t('discoveryMap.searchThisArea')));
    expect(cardFor('Clínica 1')).toHaveLength(0);
    expect(markers().some(isHighlighted)).toBe(false);
  });

  it('with a screen reader on, markers keep their native title (their spoken name)', async () => {
    screenReaderOn = true;
    await render();
    await reportRegion(SHOWN_SPAIN);
    expect(markers().map((node) => node.props.title)).toEqual([
      'Clínica 1',
      'Clínica 2',
      'Clínica 3',
    ]);
  });

  it('follows the screen reader being turned on and off', async () => {
    await render();
    await reportRegion(SHOWN_SPAIN);
    await act(async () => screenReaderListener?.(true));
    expect(marker('clinic-1').props.title).toBe('Clínica 1');
    await act(async () => screenReaderListener?.(false));
    expect(marker('clinic-1').props.title).toBeUndefined();
  });
});

describe('Contextual zoom on selection', () => {
  const MADRID_1 = clinic(1, 40.4168, -3.7038);
  const MADRID_2 = clinic(2, 40.4178, -3.7028);
  const BARCELONA = clinic(3, 41.39, 2.17);
  // The local view the camera reaches around Clínica 1, as the map reports it.
  const LOCAL = {
    latitude: 40.4168,
    longitude: -3.7038,
    latitudeDelta: 0.1,
    longitudeDelta: 0.06,
  };

  beforeEach(() => {
    read.mockResolvedValue(page([MADRID_1, MADRID_2, BARCELONA]));
  });

  async function startOnSpain() {
    await render();
    await reportRegion(SHOWN_SPAIN);
    mockAnimateToRegion.mockClear();
  }

  it('the map never moves to a pressed marker by itself (Android)', async () => {
    await render();
    expect(map().props.moveOnMarkerPress).toBe(false);
  });

  it('from far away, selecting zooms smoothly to the Clinic surroundings', async () => {
    await startOnSpain();
    await pressMarker('clinic-1');
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
    const [region, duration] = mockAnimateToRegion.mock.calls[0];
    expect(region.latitude).toBe(40.4168);
    expect(region.longitude).toBe(-3.7038);
    expect(region.latitudeDelta).toBeCloseTo(0.1);
    expect(region.longitudeDelta).toBeCloseTo(0.06);
    expect(duration).toBeGreaterThan(0);
    expect(cardFor('Clínica 1')).toHaveLength(1);
    expect(isHighlighted(marker('clinic-1'))).toBe(true);
  });

  it('already close, with the Clinic in view, the camera is left as it is', async () => {
    await startOnSpain();
    await reportRegion(LOCAL);
    await pressMarker('clinic-2');
    expect(mockAnimateToRegion).not.toHaveBeenCalled();
    expect(cardFor('Clínica 2')).toHaveLength(1);
  });

  it('closer than the local view, selecting never zooms out', async () => {
    await startOnSpain();
    const street = {
      latitude: 40.4168,
      longitude: -3.7038,
      latitudeDelta: 0.004,
      longitudeDelta: 0.003,
    };
    await reportRegion(street);
    await pressMarker('clinic-1');
    await pressMarker('clinic-2');
    for (const [region] of mockAnimateToRegion.mock.calls) {
      expect(region.latitudeDelta).toBeLessThanOrEqual(street.latitudeDelta);
      expect(region.longitudeDelta).toBeLessThanOrEqual(street.longitudeDelta);
    }
  });

  it('switching markers applies the same rule to each', async () => {
    await startOnSpain();
    await pressMarker('clinic-1');
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
    // The animation ends: the map reports the local view.
    await reportRegion(LOCAL);

    // A neighbour already in view: no move.
    await pressMarker('clinic-2');
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
    expect(isHighlighted(marker('clinic-2'))).toBe(true);

    // A Clinic out of view: recentred at the same local span, not zoomed out.
    await pressMarker('clinic-3');
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(2);
    const [region] = mockAnimateToRegion.mock.calls[1];
    expect(region).toMatchObject({
      latitude: 41.39,
      longitude: 2.17,
      latitudeDelta: 0.1,
      longitudeDelta: 0.06,
    });
    expect(cardFor('Clínica 3')).toHaveLength(1);
  });

  it('pressing the selected marker again does not animate again', async () => {
    await startOnSpain();
    await pressMarker('clinic-1');
    await reportRegion(LOCAL);
    await pressMarker('clinic-1');
    await pressMarker('clinic-1');
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
  });

  it('the camera move triggers no read and no further animation', async () => {
    await startOnSpain();
    expect(read).toHaveBeenCalledTimes(1);
    await pressMarker('clinic-1');
    // Intermediate and final region reports of the programmatic move.
    await reportRegion({ ...SHOWN_SPAIN, latitudeDelta: 4, longitudeDelta: 2.8 });
    await reportRegion(LOCAL);
    expect(read).toHaveBeenCalledTimes(1);
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
    expect(isHighlighted(marker('clinic-1'))).toBe(true);
  });

  it('deselecting keeps the camera where it is', async () => {
    await startOnSpain();
    await pressMarker('clinic-1');
    await reportRegion(LOCAL);
    await pressMap('press');
    expect(mockAnimateToRegion).toHaveBeenCalledTimes(1);
    expect(cardFor('Clínica 1')).toHaveLength(0);
  });

  it('Search this area then reads the zoomed-in view, and the profile still opens', async () => {
    await startOnSpain();
    await pressMarker('clinic-1');
    await reportRegion(LOCAL);
    await press(button(i18n.t('discoveryMap.searchThisArea')));
    expect(read).toHaveBeenCalledTimes(2);
    const [bounds] = read.mock.calls[1];
    expect(bounds.maxLatitude - bounds.minLatitude).toBeCloseTo(0.1);

    await pressMarker('clinic-2');
    await openCard('Clínica 2');
    expect(router.push).toHaveBeenCalledWith('/clinics/clinic-2');
  });
});

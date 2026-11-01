import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, StyleSheet, View } from 'react-native';
import MapView, { Marker, type MapPressEvent, type Region } from 'react-native-maps';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ClinicCard } from '@/components/design-system/clinic-card';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import { PublicTopBar } from '@/components/design-system/public-top-bar';
import { NEARBY_SEARCH_RADIUS_METERS } from '@/constants/discovery';
import { discoverClinicsInViewport, type GeographicClinicSummary } from '@/data/clinics';
import { useForegroundLocation } from '@/hooks/use-foreground-location';
import { useScreenReaderEnabled } from '@/hooks/use-screen-reader-enabled';
import { useLocale } from '@/i18n/locale-provider';
import {
  createLatestRequestGuard,
  INITIAL_MAP_REGION,
  mergeClinicsById,
  regionForRadiusMeters,
  regionToShowSelectedClinic,
  regionToViewportBounds,
  splitViewportAtAntimeridian,
} from '@/lib/discovery-viewport';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';

type SearchState = 'idle' | 'loading' | 'error' | 'loaded';

/**
 * Map Discovery (SPEC-DIS-003): no marker ever represents the User (BR-7).
 * The only automatic query is the first one: the area the map first reports
 * as visible for its starting camera (BR-9) — nothing is read before the map
 * reports it, and never the whole world. Every later viewport query is
 * explicit — "Search this area" or "My location" — never an automatic
 * pan/zoom trigger, so no zoom/delta auto-fire threshold needs to be
 * invented. Neither the viewport nor any obtained location is persisted. A
 * crossing region is split into legal backend queries and merged strictly by
 * clinic_id.
 *
 * Design System v1 layout: a single-row header, the map filling everything
 * between it and a compact bottom panel, and the two query controls as
 * small pills floating over the map's top edge. The bottom panel stays in
 * normal flow (not overlaid) on purpose: the MapView's own frame — and so
 * the region "Search this area" queries — is exactly the visible map, and
 * Google's attribution/toolbar at the map's bottom edge are never covered.
 *
 * Selection: the bottom ClinicCard is the only summary of the selected
 * Clinic, and its marker is drawn as a small pin in the exact MenizVet green
 * (a marker child view — `pinColor` cannot do it: Android keeps only its hue,
 * at full saturation); every other marker keeps the default pin. Selecting
 * zooms in to the Clinic's surroundings when the map is farther out (see
 * regionToShowSelectedClinic), never out, and a deselection leaves the camera
 * where it is. A tap on the map itself clears the selection. The native
 * callout is shown only while a screen reader is on: on Android the marker's
 * `title` is also its only spoken name (react-native-maps does not pass
 * `accessibilityLabel` to Google Maps markers), so it stays for TalkBack and
 * VoiceOver users and is dropped otherwise.
 */
export default function ClinicsMapScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const location = useForegroundLocation();
  const screenReaderEnabled = useScreenReaderEnabled();
  const mapRef = useRef<MapView>(null);
  const requestGuardRef = useRef(createLatestRequestGuard());
  const isMountedRef = useRef(true);
  // Whether any search has started: the map's later (or repeated start-up)
  // region reports never search by themselves.
  const hasSearchedRef = useRef(false);

  const [currentRegion, setCurrentRegion] = useState<Region>(INITIAL_MAP_REGION);
  const [searchState, setSearchState] = useState<SearchState>('idle');
  const [clinics, setClinics] = useState<GeographicClinicSummary[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [selectedClinic, setSelectedClinic] = useState<GeographicClinicSummary | null>(null);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useEffect(() => {
    if (location.coords) {
      const region = regionForRadiusMeters(location.coords, NEARBY_SEARCH_RADIUS_METERS);
      // Not setCurrentRegion(region) directly here: animateToRegion's own
      // completion fires onRegionChangeComplete (wired below), which is the
      // single place currentRegion is ever set from — avoiding a duplicate,
      // synchronous setState inside this effect.
      mapRef.current?.animateToRegion(region);
      void performSearch(region);
    }
  }, [location.coords]);

  function selectClinic(clinic: GeographicClinicSummary) {
    setSelectedClinic(clinic);
    // Zoom in to the Clinic's surroundings only when farther out, or bring it
    // clear of the edges; never zoom out. The resulting region report only
    // updates currentRegion: it reads nothing and animates nothing again.
    const focus = regionToShowSelectedClinic(currentRegion, clinic);
    if (focus !== null) mapRef.current?.animateToRegion(focus, SELECTED_CLINIC_ANIMATION_MS);
    AccessibilityInfo.announceForAccessibility(
      t('discoveryMap.selectedAnnouncement', { name: clinicName(clinic) }),
    );
  }

  // A tap on the map itself — not a marker press bubbled up to it (iOS).
  function handleMapPress(event: MapPressEvent) {
    if (event.nativeEvent.action !== 'marker-press') setSelectedClinic(null);
  }

  function clinicName(clinic: GeographicClinicSummary) {
    return clinic.displayName ?? t('discoveryList.unnamedClinic');
  }

  function handleRegionChangeComplete(region: Region) {
    setCurrentRegion(region);
    // The first reported region is the starting camera as actually shown.
    if (!hasSearchedRef.current) void performSearch(region);
  }

  async function performSearch(region: Region) {
    hasSearchedRef.current = true;
    const token = requestGuardRef.current.begin();
    setSearchState('loading');
    setSelectedClinic(null);

    const rawBounds = regionToViewportBounds(region);
    const legalBounds = splitViewportAtAntimeridian(rawBounds);
    const results = await Promise.all(
      legalBounds.map((bounds) => discoverClinicsInViewport(bounds, null)),
    );

    if (!isMountedRef.current || !requestGuardRef.current.isCurrent(token)) return;

    const pages: GeographicClinicSummary[][] = [];
    let anyHasMore = false;

    for (const result of results) {
      if (result.error !== null) {
        setSearchState('error');
        return;
      }
      pages.push(result.data.clinics);
      anyHasMore = anyHasMore || result.data.hasMore;
    }

    setClinics(mergeClinicsById(pages));
    setHasMore(anyHasMore);
    setSearchState('loaded');
  }

  const showEmptyArea = searchState === 'loaded' && clinics.length === 0;
  const showZoomIn = searchState === 'loaded' && hasMore;
  // The panel collapses to just the bottom inset when it has nothing to say,
  // so the map gets that space back.
  const hasPanelContent =
    location.status === 'denied' ||
    location.status === 'unavailable' ||
    searchState === 'idle' ||
    searchState === 'error' ||
    showEmptyArea ||
    showZoomIn ||
    selectedClinic !== null;

  return (
    <View style={styles.container}>
      {/* The header behind the status bar is white: dark icons. */}
      <StatusBar style="dark" />

      <View style={[styles.header, { paddingTop: insets.top + spacing.xs }]}>
        <PublicTopBar fallbackHref="/clinics" title={t('discoveryMap.title')} />
      </View>

      <View style={styles.mapArea}>
        <MapView
          ref={mapRef}
          style={StyleSheet.absoluteFill}
          initialRegion={INITIAL_MAP_REGION}
          onRegionChangeComplete={handleRegionChangeComplete}
          onPress={handleMapPress}
          // Android would otherwise centre on a pressed marker by itself;
          // the camera moves only through selectClinic (iOS never does).
          moveOnMarkerPress={false}
        >
          {clinics.map((clinic) => {
            const selected = clinic.clinicId === selectedClinic?.clinicId;
            return (
              <Marker
                // A new native marker when its look changes between the
                // default pin and the custom one.
                key={selected ? `${clinic.clinicId}:selected` : clinic.clinicId}
                identifier={clinic.clinicId}
                coordinate={{ latitude: clinic.latitude, longitude: clinic.longitude }}
                title={screenReaderEnabled ? clinicName(clinic) : undefined}
                accessibilityLabel={clinicName(clinic)}
                accessibilityHint={t('discoveryMap.markerAccessibilityHint')}
                accessibilityState={{ selected }}
                anchor={selected ? SELECTED_PIN_ANCHOR : undefined}
                onPress={() => selectClinic(clinic)}
              >
                {selected ? <SelectedClinicPin /> : null}
              </Marker>
            );
          })}
        </MapView>

        {/* Floating query controls, grouped top-left at their intrinsic
            width. `box-none` so map gestures pass through everywhere outside
            the two controls' own bounds. */}
        <View style={styles.mapControls} pointerEvents="box-none">
          <View style={styles.searchControl}>
            <PillButton
              floating
              icon="search-outline"
              label={t('discoveryMap.searchThisArea')}
              onPress={() => performSearch(currentRegion)}
              loading={searchState === 'loading'}
            />
          </View>
          <PillButton
            floating
            iconOnly
            icon="navigate-outline"
            label={t('discoveryMap.myLocation')}
            onPress={location.requestLocation}
            loading={location.status === 'requesting' || location.status === 'locating'}
          />
        </View>
      </View>

      <View
        style={[
          styles.panel,
          hasPanelContent && styles.panelWithContent,
          { paddingBottom: insets.bottom + (hasPanelContent ? spacing.md : 0) },
        ]}
      >
        {location.status === 'denied' ? (
          <Notice tone="info" message={t('discoveryMap.permissionDenied')} />
        ) : null}
        {location.status === 'unavailable' ? (
          <Notice tone="info" message={t('discoveryMap.unavailable')} />
        ) : null}

        {searchState === 'idle' ? (
          <Notice tone="info" message={t('discoveryMap.initialPrompt')} />
        ) : null}

        {searchState === 'error' ? (
          <Notice tone="error" message={t('discoveryMap.loadError')} />
        ) : null}

        {showEmptyArea ? <Notice tone="info" message={t('discoveryMap.emptyArea')} /> : null}

        {showZoomIn ? <Notice tone="info" message={t('discoveryMap.zoomInPrompt')} /> : null}

        {selectedClinic ? (
          <ClinicCard clinic={selectedClinic} addressText={selectedClinic.addressText} />
        ) : null}
      </View>
    </View>
  );
}

/** A short, smooth camera move to a selected Clinic. */
const SELECTED_CLINIC_ANIMATION_MS = 450;

/** The tip of the selected pin — its bottom centre — sits on the Clinic. */
const SELECTED_PIN_ANCHOR = { x: 0.5, y: 1 };

/**
 * The selected Clinic's marker: a round head with a white ring and centre in
 * the app's primary green, over a short point. Purely visual — the Marker
 * itself carries the name, hint and selected state.
 */
function SelectedClinicPin() {
  return (
    <View
      testID="selected-clinic-pin"
      style={styles.selectedPin}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <View style={styles.selectedPinHead}>
        <View style={styles.selectedPinDot} />
      </View>
      <View style={styles.selectedPinPoint} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.surface,
  },
  header: {
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.screenHorizontal,
    paddingBottom: spacing.xs,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  mapArea: {
    flex: 1,
  },
  // Left-anchored, never wrapping; `right` only caps how wide the group can
  // get (a very large font scale truncates the search label rather than
  // pushing the group across the map).
  mapControls: {
    position: 'absolute',
    top: spacing.md,
    left: spacing.lg,
    right: spacing.lg,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-start',
    gap: spacing.sm,
  },
  searchControl: {
    flexShrink: 1,
    maxWidth: 260,
  },
  panel: {
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.screenHorizontal,
    gap: spacing.sm,
  },
  selectedPin: {
    alignItems: 'center',
  },
  selectedPinHead: {
    width: 30,
    height: 30,
    borderRadius: 15,
    borderWidth: 3,
    borderColor: colors.surface,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selectedPinDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.surface,
  },
  // A downward triangle drawn with borders, meeting the head's ring.
  selectedPinPoint: {
    width: 0,
    height: 0,
    marginTop: -2,
    borderLeftWidth: 7,
    borderRightWidth: 7,
    borderTopWidth: 10,
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
    borderTopColor: colors.primary,
  },
  panelWithContent: {
    paddingTop: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

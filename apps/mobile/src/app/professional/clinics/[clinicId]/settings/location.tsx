import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import * as Location from 'expo-location';
import {
  AccessibilityInfo,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import MapView, { Marker, type Region } from 'react-native-maps';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { ClinicSettingsEditorStateView } from '@/components/clinic-settings-editor-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import { saveClinicLocation, type ManagedClinicLocation } from '@/data/clinic-settings';
import {
  useClinicSettingsEditor,
  type ClinicSettingsEditorRead,
} from '@/hooks/use-clinic-settings-editor';
import { mapClinicLocationSaveErrorToKey } from '@/i18n/clinic-settings-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { clinicSettingsHref } from '@/lib/clinic-settings';
import {
  NEUTRAL_MAP_REGION,
  canSaveLocation,
  formatCoordinate,
  locationDraftFrom,
  locationDraftIssues,
  locationPayload,
  locationSaveFailure,
  regionAround,
  withPin,
  type Coordinate,
  type LocationDraft,
} from '@/lib/clinic-settings-editors';
import {
  createDeviceLocationAssist,
  readDevicePosition,
  type DevicePositionResult,
  type ForegroundLocationApi,
} from '@/lib/device-location-assist';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

const MAP_HEIGHT = 280;

/**
 * Foreground-only `expo-location` calls, with the same balanced accuracy as
 * nearby/map discovery (hooks/use-foreground-location.ts). No background
 * permission is ever requested.
 */
const FOREGROUND_LOCATION: ForegroundLocationApi = {
  getForegroundPermissionsAsync: () => Location.getForegroundPermissionsAsync(),
  requestForegroundPermissionsAsync: () => Location.requestForegroundPermissionsAsync(),
  hasServicesEnabledAsync: () => Location.hasServicesEnabledAsync(),
  getCurrentPositionAsync: () =>
    Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }),
};

/** Calm copy for each way "Use my current location" can fail; the draft is always kept. */
function deviceLocationNoticeKey(
  result: Exclude<DevicePositionResult, { kind: 'located' }>,
): TranslationKey {
  if (result.kind === 'denied') {
    return result.canAskAgain
      ? 'clinicSettingsLocation.currentLocationDenied'
      : 'clinicSettingsLocation.currentLocationBlocked';
  }
  if (result.kind === 'servicesDisabled')
    return 'clinicSettingsLocation.currentLocationServicesOff';
  return 'clinicSettingsLocation.currentLocationUnavailable';
}

/**
 * Edits the Clinic's location (SPEC-CLI-002 BR-12–BR-18): the address shown
 * to patients (typed text) and the map position used for nearby and map
 * search (a pin the actor places explicitly). Nothing connects the two: no
 * geocoding, no address search, no reverse geocoding.
 *
 * A Clinic without a stored location starts on the neutral world map with no
 * pin, and Save stays disabled until the actor has typed an address AND
 * placed the pin — by tapping the map, dragging the pin, "Place the marker at
 * the centre of the map" (the accessible alternative), or "Use my current
 * location". The map's starting centre is never a chosen position. A stored
 * location starts with its own pin, which counts as confirmed, so an
 * address-only change can be saved.
 *
 * "Use my current location" (BR-18) runs only when tapped: it asks for
 * foreground permission if needed, reads the device position once, and
 * proposes the draft marker there (centring the map and announcing it). It
 * never touches the address and never saves. Failure or denial shows a calm
 * notice and keeps the draft. A marker placed by hand while a lookup is
 * pending wins; leaving discards a pending lookup (lib/device-location-assist.ts).
 * Positions are rounded to 6 decimals for the save, the unchanged check, and
 * lost-response reconciliation alike.
 *
 * Save, re-read, lost-response, access-loss, and terminal-leaving behaviour
 * are those of the Profile editor; location saves are last-write-wins (BR-16).
 */
export default function ClinicLocationEditorScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const {
    state,
    reload,
    leave: leaveScreen,
    isActive,
  } = useClinicSettingsEditor(clinicId, 'location');
  const [draft, setDraft] = useState<LocationDraft | null>(null);
  const [initialRegion, setInitialRegion] = useState<Region | null>(null);
  const [mapCenter, setMapCenter] = useState<Coordinate | null>(null);
  const [scrollEnabled, setScrollEnabled] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);
  const [locating, setLocating] = useState(false);
  const [deviceNoticeKey, setDeviceNoticeKey] = useState<TranslationKey | null>(null);
  // One coordinator per screen instance, created once and never replaced.
  const [deviceLocation] = useState(createDeviceLocationAssist);

  const busyRef = useRef(false);
  const mapRef = useRef<MapView>(null);

  const leave = useCallback(() => {
    // A device-location lookup still in flight can never apply after leaving.
    deviceLocation.supersede();
    leaveScreen(() => router.dismissTo(clinicSettingsHref(clinicId)));
  }, [deviceLocation, leaveScreen, clinicId]);

  // Draft and starting camera come from the first successful read only.
  const initialize = useCallback(
    (read: ClinicSettingsEditorRead | null) => {
      if (read?.kind !== 'loaded' || !isActive()) return;
      const stored = read.profile.location;
      setDraft((previous) => previous ?? locationDraftFrom(stored));
      setInitialRegion(
        (previous) => previous ?? (stored === null ? NEUTRAL_MAP_REGION : regionAround(stored)),
      );
    },
    [isActive],
  );

  useEffect(() => {
    reload().then(initialize);
  }, [reload, initialize]);

  if (state.kind !== 'loaded' || draft === null || initialRegion === null) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={leave} />
          <ClinicSettingsEditorStateView
            state={state.kind === 'loaded' ? { kind: 'loading' } : state}
            onRetry={() => reload().then(initialize)}
            onBack={leave}
          />
        </View>
      </SafeAreaView>
    );
  }

  const stored = state.profile.location;
  const issues = locationDraftIssues(draft);
  const saveEnabled = canSaveLocation({ draft, stored, busy: saving });
  const addressMissing = issues.includes('addressRequired') && draft.addressText !== '';

  const establishPin = (coordinate: Coordinate) =>
    setDraft((previous) => (previous === null ? previous : withPin(previous, coordinate)));

  // A marker placed by hand (map tap, drag, "centre of the map") always wins:
  // any pending "Use my current location" result is discarded.
  const placePin = (coordinate: Coordinate) => {
    if (saving) return;
    deviceLocation.supersede();
    setLocating(false);
    setDeviceNoticeKey(null);
    establishPin(coordinate);
  };

  // Explicit only (BR-18): nothing here runs on load. Proposes the draft
  // marker at the device's position; never touches the address, never saves.
  async function placePinAtCurrentLocation() {
    if (saving || !isActive()) return;
    const token = deviceLocation.begin();
    if (token === null) return; // a lookup is already pending
    setLocating(true);
    setDeviceNoticeKey(null);
    const result = await readDevicePosition(FOREGROUND_LOCATION);
    // Superseded by a manual marker, a newer request, or leaving: ignore.
    if (!deviceLocation.settle(token) || !isActive()) return;
    setLocating(false);
    if (result.kind !== 'located') {
      setDeviceNoticeKey(deviceLocationNoticeKey(result));
      return;
    }
    establishPin(result.coordinate);
    mapRef.current?.animateToRegion(regionAround(result.coordinate));
    AccessibilityInfo.announceForAccessibility(
      t('clinicSettingsLocation.currentLocationPlaced', {
        coordinates: formatCoordinate(result.coordinate),
      }),
    );
  }

  async function save() {
    if (busyRef.current || !isActive() || !saveEnabled || draft === null) return;
    const submitted: ManagedClinicLocation | null = locationPayload(draft);
    if (submitted === null) return;
    busyRef.current = true;
    setSaving(true);
    setErrorKey(null);
    try {
      const result = await saveClinicLocation(clinicId, submitted);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      const outcome = locationSaveFailure(read, submitted);
      if (outcome === 'committed') {
        leave();
        return;
      }
      if (outcome === 'failed') setErrorKey(mapClinicLocationSaveErrorToKey(result.error));
    } finally {
      busyRef.current = false;
      if (isActive()) setSaving(false);
    }
  }

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
          scrollEnabled={scrollEnabled}
        >
          <AppTopBar onBack={leave} />
          <Text style={styles.title} accessibilityRole="header">
            {t('clinicSettingsLocation.title')}
          </Text>

          <View style={styles.section}>
            <Input
              label={t('clinicSettingsLocation.addressLabel')}
              value={draft.addressText}
              onChangeText={(addressText) =>
                setDraft((previous) =>
                  previous === null ? previous : { ...previous, addressText },
                )
              }
              editable={!saving}
              autoCapitalize="words"
              error={addressMissing ? t('clinicSettingsLocation.addressRequired') : undefined}
            />
            <Text style={styles.hint}>{t('clinicSettingsLocation.addressHint')}</Text>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              {t('clinicSettingsLocation.mapHeading')}
            </Text>
            <Text style={styles.hint}>{t('clinicSettingsLocation.mapHint')}</Text>
            {/* While a finger is on the map, the page doesn't scroll, so the
                map gets every pan, zoom, and drag. */}
            <View
              style={styles.mapFrame}
              onTouchStart={() => setScrollEnabled(false)}
              onTouchEnd={() => setScrollEnabled(true)}
              onTouchCancel={() => setScrollEnabled(true)}
            >
              <MapView
                ref={mapRef}
                style={StyleSheet.absoluteFill}
                initialRegion={initialRegion}
                onRegionChangeComplete={(region) =>
                  setMapCenter({ latitude: region.latitude, longitude: region.longitude })
                }
                onPress={(event) => placePin(event.nativeEvent.coordinate)}
                accessibilityLabel={t('clinicSettingsLocation.mapAccessibility')}
              >
                {draft.pin !== null ? (
                  <Marker
                    coordinate={draft.pin}
                    draggable={!saving}
                    onDragEnd={(event) => placePin(event.nativeEvent.coordinate)}
                    title={t('clinicSettingsLocation.pinTitle')}
                  />
                ) : null}
              </MapView>
            </View>
            <View style={styles.mapActions}>
              <PillButton
                icon="navigate-outline"
                label={t('clinicSettingsLocation.useCurrentLocation')}
                onPress={placePinAtCurrentLocation}
                loading={locating}
              />
              <PillButton
                icon="locate-outline"
                label={t('clinicSettingsLocation.placeAtCenter')}
                onPress={() => {
                  if (mapCenter !== null) placePin(mapCenter);
                  else
                    placePin({
                      latitude: initialRegion.latitude,
                      longitude: initialRegion.longitude,
                    });
                }}
              />
            </View>
            <Text style={styles.hint}>{t('clinicSettingsLocation.useCurrentLocationHint')}</Text>
            {deviceNoticeKey !== null ? <Notice tone="info" message={t(deviceNoticeKey)} /> : null}
            <Text style={styles.value} accessibilityLiveRegion="polite">
              {draft.pin === null
                ? t('clinicSettingsLocation.pinMissing')
                : t('clinicSettingsLocation.pinValue', {
                    coordinates: formatCoordinate(draft.pin),
                  })}
            </Text>
            <Text style={styles.hint}>{t('clinicSettingsLocation.correspondenceNote')}</Text>
          </View>
        </ScrollView>

        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          {issues.includes('pinRequired') ? (
            <Notice tone="info" message={t('clinicSettingsLocation.pinRequired')} />
          ) : null}
          <Button
            label={t('clinicSettings.save')}
            onPress={save}
            loading={saving}
            disabled={!saveEnabled}
          />
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  flex: {
    flex: 1,
  },
  stateContent: {
    flex: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    gap: spacing.lg,
  },
  scrollContent: {
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xl,
    gap: spacing.xl,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  section: {
    gap: spacing.sm,
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  hint: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  value: {
    ...typography.body,
    color: colors.textPrimary,
  },
  mapActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  mapFrame: {
    height: MAP_HEIGHT,
    borderRadius: radius.medium,
    overflow: 'hidden',
    backgroundColor: colors.surfaceSoft,
  },
  footer: {
    gap: spacing.sm,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.md,
    backgroundColor: colors.background,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

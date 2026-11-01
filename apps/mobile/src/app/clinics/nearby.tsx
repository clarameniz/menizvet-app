import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { Button } from '@/components/design-system/button';
import { ClinicCard } from '@/components/design-system/clinic-card';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import { PublicTopBar } from '@/components/design-system/public-top-bar';
import { StateMessage } from '@/components/design-system/state-message';
import { NEARBY_SEARCH_RADIUS_METERS } from '@/constants/discovery';
import { discoverNearbyClinics, type NearbyClinicSummary } from '@/data/clinics';
import { useForegroundLocation } from '@/hooks/use-foreground-location';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type NearbyCursor = { distanceMeters: number; clinicId: string };
// No separate 'loading' member: once location.coords is set, 'idle' *is*
// the loading state until the fetch below settles into 'error' or 'loaded'
// — avoiding a synchronous setState at the top of the effect (React/ESLint
// discourage that pattern; see the effect below).
type ClinicsLoadState = 'idle' | 'error' | 'loaded';

/**
 * Nearby Discovery (SPEC-DIS-002): device location is always optional
 * (BR-4) — denial/unavailability never blocks Basic Discovery or the Map,
 * both offered here as explicit alternatives, since no geocoder/address
 * search is currently approved. NEARBY_SEARCH_RADIUS_METERS is the single
 * approved Phase-1 constant; no automatic widening on an empty page (BR-17).
 * The exact next_after_distance_meters/next_after_clinic_id cursor is
 * threaded back verbatim and nearest-first order is never re-sorted.
 *
 * Design System v1 presentation, same shape as the Basic list: header,
 * alternatives and load-more footer scroll with the results.
 */
export default function NearbyClinicsScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const location = useForegroundLocation();

  const [clinicsState, setClinicsState] = useState<ClinicsLoadState>('idle');
  const [clinics, setClinics] = useState<NearbyClinicSummary[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<NearbyCursor | null>(null);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [loadMoreError, setLoadMoreError] = useState(false);

  useEffect(() => {
    if (!location.coords) return;

    let isMounted = true;

    discoverNearbyClinics(location.coords, NEARBY_SEARCH_RADIUS_METERS, null).then((result) => {
      if (!isMounted) return;

      if (result.error !== null) {
        setClinicsState('error');
        return;
      }

      setClinics(result.data.clinics);
      setHasMore(result.data.hasMore);
      setNextCursor(
        result.data.nextAfterDistanceMeters !== null && result.data.nextAfterClinicId !== null
          ? {
              distanceMeters: result.data.nextAfterDistanceMeters,
              clinicId: result.data.nextAfterClinicId,
            }
          : null,
      );
      setClinicsState('loaded');
    });

    return () => {
      isMounted = false;
    };
  }, [location.coords]);

  async function handleLoadMore() {
    if (isLoadingMore || nextCursor === null || !location.coords) return;

    setIsLoadingMore(true);
    setLoadMoreError(false);

    const result = await discoverNearbyClinics(
      location.coords,
      NEARBY_SEARCH_RADIUS_METERS,
      nextCursor,
    );

    setIsLoadingMore(false);

    if (result.error !== null) {
      setLoadMoreError(true);
      return;
    }

    setClinics((current) => [...current, ...result.data.clinics]);
    setHasMore(result.data.hasMore);
    setNextCursor(
      result.data.nextAfterDistanceMeters !== null && result.data.nextAfterClinicId !== null
        ? {
            distanceMeters: result.data.nextAfterDistanceMeters,
            clinicId: result.data.nextAfterClinicId,
          }
        : null,
    );
  }

  const isLoaded =
    location.status === 'located' && location.coords !== null && clinicsState === 'loaded';

  const header = (
    <View style={styles.header}>
      <PublicTopBar fallbackHref="/clinics" />

      <View style={styles.titleBlock}>
        <Text style={styles.title} accessibilityRole="header">
          {t('discoveryNearby.title')}
        </Text>
        <Text style={styles.support}>{t('discoveryNearby.support')}</Text>
      </View>

      {/* Location is optional (BR-4): Basic list and Map stay one tap away
          in every state. `replace`, as before. */}
      <View style={styles.actionsRow}>
        <PillButton
          icon="list-outline"
          label={t('discoveryNearby.viewBasicAction')}
          onPress={() => router.replace('/clinics')}
        />
        <PillButton
          icon="map-outline"
          label={t('discoveryNearby.viewMapAction')}
          onPress={() => router.replace('/clinics/map')}
        />
      </View>
    </View>
  );

  const footer =
    isLoaded && (loadMoreError || hasMore) ? (
      <View style={styles.footer}>
        {loadMoreError ? <Notice tone="error" message={t('discoveryNearby.loadError')} /> : null}
        {hasMore ? (
          <Button
            variant="secondary"
            label={isLoadingMore ? t('discoveryNearby.loadingMore') : t('discoveryNearby.loadMore')}
            onPress={handleLoadMore}
            loading={isLoadingMore}
          />
        ) : null}
      </View>
    ) : null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      {/* Always-light background: explicit dark status-bar icons. */}
      <StatusBar style="dark" />
      <FlatList
        data={isLoaded ? clinics : []}
        keyExtractor={(clinic) => clinic.clinicId}
        renderItem={({ item }) => (
          <ClinicCard
            clinic={item}
            addressText={item.addressText}
            distanceMeters={item.distanceMeters}
          />
        )}
        ListHeaderComponent={header}
        ListEmptyComponent={<NearbyStatus location={location} clinicsState={clinicsState} />}
        ListFooterComponent={footer}
        ItemSeparatorComponent={ItemSeparator}
        contentContainerStyle={[styles.listContent, { paddingBottom: insets.bottom + spacing.xl }]}
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

type NearbyStatusProps = {
  location: ReturnType<typeof useForegroundLocation>;
  clinicsState: ClinicsLoadState;
};

/** Everything shown in place of results: permission prompt/outcome, loading, error, empty. */
function NearbyStatus({ location, clinicsState }: NearbyStatusProps) {
  const { t } = useLocale();

  if (location.status === 'idle' || location.status === 'requesting') {
    return (
      <View style={styles.status}>
        <StateMessage tone="location" message={t('discoveryNearby.permissionRationale')} />
        <PillButton
          icon="navigate-outline"
          label={t('discoveryNearby.requestPermission')}
          onPress={location.requestLocation}
          loading={location.status === 'requesting'}
        />
      </View>
    );
  }

  if (location.status === 'denied' || location.status === 'unavailable') {
    return (
      <View style={styles.status}>
        <StateMessage
          tone="location"
          message={
            location.status === 'denied'
              ? t('discoveryNearby.permissionDenied')
              : t('discoveryNearby.unavailable')
          }
        />
        <Text style={styles.statusDetail}>{t('discoveryNearby.permissionDeniedAction')}</Text>
        <PillButton
          icon="navigate-outline"
          label={t('discoveryNearby.requestPermission')}
          onPress={location.requestLocation}
        />
      </View>
    );
  }

  if (location.status === 'locating' || clinicsState === 'idle') {
    return (
      <StateMessage
        tone="loading"
        message={
          location.status === 'locating'
            ? t('discoveryNearby.locating')
            : t('discoveryNearby.loading')
        }
      />
    );
  }

  if (clinicsState === 'error') {
    return <StateMessage tone="error" message={t('discoveryNearby.loadError')} />;
  }

  return <StateMessage tone="empty" message={t('discoveryNearby.emptyState')} />;
}

function ItemSeparator() {
  return <View style={styles.separator} />;
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  listContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
  },
  header: {
    gap: spacing.xl,
    marginBottom: spacing.xl,
  },
  titleBlock: {
    gap: spacing.xs,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  support: {
    ...typography.body,
    color: colors.textSecondary,
  },
  actionsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  status: {
    alignItems: 'center',
    gap: spacing.md,
    paddingBottom: spacing.xl,
  },
  statusDetail: {
    ...typography.caption,
    color: colors.textSecondary,
    textAlign: 'center',
    marginTop: -spacing.lg,
    paddingHorizontal: spacing.lg,
  },
  separator: {
    height: spacing.md,
  },
  footer: {
    marginTop: spacing.xl,
    gap: spacing.sm,
  },
});

import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { ClinicCard } from '@/components/design-system/clinic-card';
import { CompactAction } from '@/components/design-system/compact-action';
import { PillButton } from '@/components/design-system/pill-button';
import { PublicTopBar } from '@/components/design-system/public-top-bar';
import { SearchField } from '@/components/design-system/search-field';
import { StateMessage } from '@/components/design-system/state-message';
import { EmptyListMessage, LoadMoreFooter, PagedListStatus } from '@/components/paged-list-parts';
import { usePublishedClinicsPage } from '@/hooks/use-published-clinics-page';
import { useLocale } from '@/i18n/locale-provider';
import {
  PUBLISHED_CLINIC_SEARCH_DEBOUNCE_MS,
  PUBLISHED_CLINIC_SEARCH_MAX_LENGTH,
  publishedClinicsBody,
  submittedPublishedClinicSearch,
} from '@/lib/published-clinic-search';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * The Clinic list (SPEC-DIS-001, SPEC-DIS-004 §5): public, the same for
 * anonymous and authenticated callers, requires no device location, and
 * lists Clinics without a Location too.
 *
 * The published Clinics are read 20 at a time, in alphabetical order, through
 * `discover_published_clinics`, with "Load more" while the read reports more.
 * The search is sent to the backend after a 300 ms pause (at once when
 * cleared or submitted); every new search withdraws the previous rows and
 * cursor at once, shows the loading state, and ignores late answers. "No
 * matches" appears only once the new search's first page arrived empty.
 *
 * Returning from a Clinic keeps the search, every loaded page and the scroll
 * position: the list stays mounted beneath the Clinic and is not re-read on
 * focus. Each card shows only what its row carries — name, public address or
 * else description — and opens `/clinics/[id]`, which re-reads the Clinic.
 *
 * The header, the search field and the Nearby/Map shortcuts scroll with the
 * list, so the results — not the chrome — own the viewport; the shortcuts are
 * offered in every state, errors included.
 */
export default function ClinicsScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const [typed, setTyped] = useState('');
  const [search, setSearch] = useState('');
  const list = usePublishedClinicsPage(search);
  const rows = list.state.rows;
  const body = publishedClinicsBody(rows, search);

  // A typed search is submitted after a pause (clearing is submitted at once,
  // in `changeTyped`).
  useEffect(() => {
    const next = submittedPublishedClinicSearch(typed);
    if (next === '' || next === search) return;
    const timer = setTimeout(() => setSearch(next), PUBLISHED_CLINIC_SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [typed, search]);

  const changeTyped = useCallback((value: string) => {
    setTyped(value);
    if (submittedPublishedClinicSearch(value) === '') setSearch('');
  }, []);

  const clearSearch = useCallback(() => {
    setTyped('');
    setSearch('');
  }, []);

  const header = (
    <View style={styles.header}>
      <PublicTopBar fallbackHref="/" />

      <View style={styles.titleBlock}>
        <Text style={styles.title} accessibilityRole="header">
          {t('discoveryBasic.title')}
        </Text>
        <Text style={styles.support}>{t('discoveryBasic.support')}</Text>
      </View>

      <SearchField
        value={typed}
        onChangeText={changeTyped}
        onClear={clearSearch}
        onSubmit={() => setSearch(submittedPublishedClinicSearch(typed))}
        placeholder={t('discoveryBasic.searchPlaceholder')}
        accessibilityLabel={t('discoveryBasic.searchAccessibility')}
        clearAccessibilityLabel={t('discoveryBasic.clearSearch')}
        maxLength={PUBLISHED_CLINIC_SEARCH_MAX_LENGTH}
      />

      {/* Navigation utilities, not the primary content — the Nearby/Map
          routes themselves are unchanged. */}
      <View style={styles.actionsRow}>
        <PillButton
          icon="navigate-outline"
          label={t('discoveryBasic.nearbyAction')}
          onPress={() => router.push('/clinics/nearby')}
        />
        <PillButton
          icon="map-outline"
          label={t('discoveryBasic.mapAction')}
          onPress={() => router.push('/clinics/map')}
        />
      </View>

      <PagedListStatus
        list={list}
        loadingKey={search === '' ? 'discoveryBasic.loading' : 'discoveryBasic.searching'}
        errorKey="discoveryBasic.loadError"
      />
    </View>
  );

  const emptyContent =
    body === 'noMatches' ? (
      <View style={styles.emptyBlock}>
        <EmptyListMessage
          icon="search-outline"
          message={t('discoveryBasic.noMatches', { search })}
        />
        <View style={styles.actionsRow}>
          <CompactAction
            icon="close-circle-outline"
            label={t('discoveryBasic.clearSearch')}
            accessibilityLabel={t('discoveryBasic.clearSearch')}
            onPress={clearSearch}
          />
        </View>
      </View>
    ) : body === 'noClinics' ? (
      <StateMessage tone="empty" message={t('discoveryBasic.emptyState')} />
    ) : null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      {/* Always-light background: explicit dark status-bar icons, same as
          the auth screens (never inherit the public home's `light`). */}
      <StatusBar style="dark" />
      <FlatList
        data={rows ?? []}
        keyExtractor={(clinic) => clinic.clinicId}
        renderItem={({ item }) => (
          <ClinicCard clinic={item} addressText={item.addressText ?? undefined} />
        )}
        ListHeaderComponent={header}
        ListEmptyComponent={emptyContent}
        ListFooterComponent={<LoadMoreFooter list={list} />}
        ItemSeparatorComponent={ItemSeparator}
        contentContainerStyle={[styles.listContent, { paddingBottom: insets.bottom + spacing.xl }]}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
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
    gap: spacing.lg,
    marginBottom: spacing.lg,
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
  emptyBlock: {
    gap: spacing.sm,
  },
  separator: {
    height: spacing.sm,
  },
});

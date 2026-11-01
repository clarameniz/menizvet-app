import { useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, FlatList, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { ProfessionalHistoryEntryCard } from '@/components/professional-history-entry-card';
import {
  viewAppointmentProfessionalMedicalHistory,
  type ProfessionalHistoryEntry,
  type ProfessionalHistoryPage,
  type ProfessionalHistoryRead,
} from '@/data/professional-medical-history';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { professionalAppointmentDetailHref } from '@/lib/clinic-schedule-display';
import { goBackOr } from '@/lib/navigation';
import { appendProfessionalHistoryPage } from '@/lib/professional-medical-history';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type HistoryState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** Denied on any page: every clinical content already shown is dropped. */
  | { kind: 'unavailable' }
  | { kind: 'loaded'; page: ProfessionalHistoryPage };

type ScreenState = {
  routeKey: string;
  view: HistoryState;
  loadingMore: boolean;
  loadMoreError: boolean;
  expandedIds: ReadonlySet<string>;
};

function freshScreen(routeKey: string, view: HistoryState = { kind: 'loading' }): ScreenState {
  return { routeKey, view, loadingMore: false, loadMoreError: false, expandedIds: new Set() };
}

function viewOf(read: ProfessionalHistoryRead): HistoryState {
  if (read.kind === 'permitted') return { kind: 'loaded', page: read.page };
  if (read.kind === 'denied') return { kind: 'unavailable' };
  return {
    kind: 'error',
    messageKey:
      read.kind === 'authenticationRequired'
        ? 'errors.sessionExpired'
        : 'professionalHistory.loadError',
  };
}

/**
 * The professional longitudinal history of the Appointment's Pet
 * (SPEC-MED-005 §15), keyed only by the route's Clinic and Appointment.
 *
 * Opening this screen is the explicit "View medical history" action, so it
 * reads once on arrival — not on every focus — and again only on Retry or
 * Load more: each read is one audited protected access. The latest request
 * wins; a change of Clinic or Appointment discards everything shown. A denial
 * on any page replaces all clinical content with the calm unavailable state,
 * which reveals nothing about whether records exist.
 *
 * A flat timeline, newest clinical occurrence first; read only.
 */
export default function ProfessionalMedicalHistoryScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId, appointmentId } = useLocalSearchParams<{
    clinicId: string;
    appointmentId: string;
  }>();
  // Everything shown belongs to one route; another Clinic or Appointment
  // starts from nothing.
  const routeKey = `${clinicId}/${appointmentId}`;
  const [screen, setScreen] = useState<ScreenState>(() => freshScreen(routeKey));
  const current = screen.routeKey === routeKey ? screen : freshScreen(routeKey);
  const { view: state, loadingMore, loadMoreError, expandedIds } = current;
  const requestRef = useRef(0);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      requestRef.current += 1;
    };
  }, []);

  const fetchFirstPage = useCallback(async () => {
    const request = ++requestRef.current;
    const read = await viewAppointmentProfessionalMedicalHistory(clinicId, appointmentId);
    if (!mountedRef.current || request !== requestRef.current) return;
    setScreen(freshScreen(routeKey, viewOf(read)));
  }, [clinicId, appointmentId, routeKey]);

  useEffect(() => {
    void fetchFirstPage();
  }, [fetchFirstPage]);

  function retry() {
    setScreen(freshScreen(routeKey));
    void fetchFirstPage();
  }

  async function loadMore() {
    if (state.kind !== 'loaded' || state.page.cursor === null || loadingMore) return;
    const request = ++requestRef.current;
    const cursor = state.page.cursor;
    setScreen({ ...current, loadingMore: true, loadMoreError: false });
    const read = await viewAppointmentProfessionalMedicalHistory(clinicId, appointmentId, cursor);
    if (!mountedRef.current || request !== requestRef.current) return;
    if (read.kind === 'denied' || read.kind === 'authenticationRequired') {
      // Access ended while paging: every clinical content shown is dropped.
      setScreen(freshScreen(routeKey, viewOf(read)));
      return;
    }
    if (read.kind === 'failed') {
      setScreen((latest) => ({ ...latest, loadingMore: false, loadMoreError: true }));
      return;
    }
    setScreen((latest) =>
      latest.view.kind === 'loaded'
        ? {
            ...latest,
            loadingMore: false,
            view: {
              kind: 'loaded',
              page: appendProfessionalHistoryPage(latest.view.page, read.page),
            },
          }
        : latest,
    );
    AccessibilityInfo.announceForAccessibility(t('professionalHistory.loadedMore'));
  }

  function toggle(entryId: string) {
    setScreen((latest) => {
      const next = new Set(latest.expandedIds);
      if (next.has(entryId)) next.delete(entryId);
      else next.add(entryId);
      return { ...latest, expandedIds: next };
    });
  }

  const back = () => goBackOr(professionalAppointmentDetailHref(clinicId, appointmentId));

  if (state.kind !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={back} />
          {state.kind === 'loading' ? (
            <StateMessage tone="loading" message={t('professionalHistory.loading')} />
          ) : state.kind === 'unavailable' ? (
            <StateMessage
              tone="empty"
              icon="lock-closed-outline"
              title={t('professionalHistory.title')}
              message={t('professionalHistory.unavailable')}
            />
          ) : (
            <StateMessage
              tone="error"
              title={t('professionalHistory.title')}
              message={t(state.messageKey)}
            />
          )}
          {state.kind === 'error' ? (
            <Button label={t('professionalHistory.retry')} onPress={retry} />
          ) : null}
          {state.kind === 'loading' ? null : (
            <Button variant="secondary" label={t('professionalHistory.back')} onPress={back} />
          )}
        </View>
      </SafeAreaView>
    );
  }

  const { page } = state;
  const header = (
    <View style={styles.header}>
      <AppTopBar onBack={back} />
      <View style={styles.titleBlock}>
        <Text style={styles.title} accessibilityRole="header">
          {t('professionalHistory.title')}
        </Text>
        <Text style={styles.subtitle}>{t('professionalHistory.subtitle')}</Text>
      </View>
    </View>
  );
  const footer =
    loadMoreError || page.cursor !== null ? (
      <View style={styles.footer}>
        {loadMoreError ? (
          <Notice tone="error" message={t('professionalHistory.loadError')} />
        ) : null}
        {page.cursor !== null ? (
          <Button
            variant="secondary"
            label={t(
              loadingMore ? 'professionalHistory.loadingMore' : 'professionalHistory.loadMore',
            )}
            onPress={() => void loadMore()}
            loading={loadingMore}
          />
        ) : null}
      </View>
    ) : null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <FlatList
        data={page.entries}
        keyExtractor={(entry: ProfessionalHistoryEntry) => entry.entryId}
        renderItem={({ item }) => (
          <ProfessionalHistoryEntryCard
            entry={item}
            expanded={expandedIds.has(item.entryId)}
            onToggle={() => toggle(item.entryId)}
          />
        )}
        ListHeaderComponent={header}
        ListEmptyComponent={
          <StateMessage
            tone="empty"
            icon="document-text-outline"
            message={t('professionalHistory.empty')}
          />
        }
        ListFooterComponent={footer}
        ItemSeparatorComponent={ItemSeparator}
        contentContainerStyle={[styles.listContent, { paddingBottom: insets.bottom + spacing.xl }]}
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

function ItemSeparator() {
  return <View style={styles.separator} />;
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  stateContent: {
    flex: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    gap: spacing.lg,
  },
  listContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
  },
  header: { gap: spacing.xl, marginBottom: spacing.xl },
  titleBlock: { gap: spacing.xs },
  title: { ...typography.h1, color: colors.textPrimary },
  subtitle: { ...typography.body, color: colors.textSecondary },
  separator: { height: spacing.md },
  footer: { gap: spacing.md, marginTop: spacing.xl },
});

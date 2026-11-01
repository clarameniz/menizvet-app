import { useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { ClinicalHistoryEntryCard } from '@/components/clinical-history-entry-card';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import {
  getGuardianPetMedicalHistory,
  type GuardianMedicalHistoryEntry,
} from '@/data/clinical-history';
import { mapClinicalHistoryErrorToKey } from '@/i18n/clinical-history-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  appendHistoryPage,
  deriveHistoryLoadOutcome,
  type HistoryPageState,
} from '@/lib/clinical-history-display';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type Stage = 'loading' | 'denied' | 'error' | 'loaded';

/**
 * Guardian-only, read-only medical-history view (Milestone G first slice).
 * Single screen with expandable entry cards — deliberately no independent
 * detail route and no deep link by Clinical Record Entry id: there is no
 * single-Entry read for Guardians (see data/clinical-history.ts's module doc
 * comment). Every entry already
 * carries everything a detail view would need, so there is nothing to fetch
 * a second time.
 *
 * DENIED is a normal, non-error outcome (current Guardianship ended, or the
 * Pet no longer exists) and is deliberately never distinguished further in
 * the UI, matching the data layer's own non-disclosure behavior.
 *
 * Pages of GUARDIAN_MEDICAL_HISTORY_PAGE_SIZE, read only on entry and on
 * "Load more" — never on focus, so coming back from an opened Attachment
 * keeps every loaded page (and creates no audit event).
 */
export default function PetMedicalHistoryRoute() {
  const { id: petId } = useLocalSearchParams<{ id: string }>();
  // Another Pet is another history: nothing read for one Pet — not even a
  // late answer — is ever shown under another.
  return <PetMedicalHistoryScreen key={petId} petId={petId} />;
}

function PetMedicalHistoryScreen({ petId }: { petId: string }) {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();

  const [stage, setStage] = useState<Stage>('loading');
  const [errorKey, setErrorKey] = useState<TranslationKey>('clinicalHistory.loadError');
  const [page, setPage] = useState<HistoryPageState>({ entries: [], cursor: null });
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [loadMoreError, setLoadMoreError] = useState(false);
  const [expandedIds, setExpandedIds] = useState<ReadonlySet<string>>(new Set());

  // Answers of an older generation (an unmounted screen) are ignored.
  const generationRef = useRef(0);
  // At most one page read at a time, so a cursor is never requested twice.
  const isReadingRef = useRef(false);
  // The cursor of the last page shown; `null` once there is no further page.
  const cursorRef = useRef<HistoryPageState['cursor']>(null);

  // DENIED — on the first page or any later one — drops every clinical
  // content at once.
  const deny = useCallback(() => {
    cursorRef.current = null;
    setPage({ entries: [], cursor: null });
    setExpandedIds(new Set());
    setLoadMoreError(false);
    setStage('denied');
  }, []);

  useEffect(() => {
    const generation = ++generationRef.current;
    isReadingRef.current = true;

    getGuardianPetMedicalHistory(petId).then((result) => {
      if (generation !== generationRef.current) return;
      isReadingRef.current = false;

      if (result.error !== null) {
        setErrorKey(mapClinicalHistoryErrorToKey(result.error));
        setStage('error');
        return;
      }

      const outcome = deriveHistoryLoadOutcome(result.data);

      if (outcome.kind === 'denied') {
        deny();
        return;
      }

      cursorRef.current = outcome.cursor;
      setPage({ entries: outcome.entries, cursor: outcome.cursor });
      setStage('loaded');
    });

    return () => {
      generationRef.current += 1;
    };
  }, [deny, petId]);

  async function handleLoadMore() {
    const cursor = cursorRef.current;
    if (isReadingRef.current || cursor === null) return;

    isReadingRef.current = true;
    const generation = generationRef.current;
    setIsLoadingMore(true);
    setLoadMoreError(false);

    const result = await getGuardianPetMedicalHistory(petId, cursor);

    if (generation !== generationRef.current) return;
    isReadingRef.current = false;
    setIsLoadingMore(false);

    if (result.error !== null) {
      // What is shown stays; "Load more" retries the same cursor.
      setLoadMoreError(true);
      return;
    }

    const outcome = deriveHistoryLoadOutcome(result.data);

    if (outcome.kind === 'denied') {
      // Guardianship ended (or the Pet became unavailable) between page
      // loads — a normal authorization-state change, not a technical error.
      deny();
      return;
    }

    cursorRef.current = outcome.cursor;
    setPage((current) => appendHistoryPage(current, outcome));
  }

  function toggleExpanded(entryId: string) {
    setExpandedIds((current) => {
      const next = new Set(current);
      if (next.has(entryId)) {
        next.delete(entryId);
      } else {
        next.add(entryId);
      }
      return next;
    });
  }

  // Every exit (top-bar back and the Denied/Error "Back" button): pushed from
  // Pet detail, so pop back to it exactly like Android hardware back — no
  // second Pet detail entry is stacked. Falls back to that same Pet detail
  // only when there's nothing to pop.
  const handleBack = () => goBackOr(`/pets/${petId}`);

  if (stage === 'loading' || stage === 'denied' || stage === 'error') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={handleBack} />
          {stage === 'loading' ? (
            <StateMessage tone="loading" message={t('clinicalHistory.loading')} />
          ) : (
            <>
              {/* DENIED is a normal, deliberately non-specific outcome: the
                  same calm lock message, never an error tone or a reason. */}
              {stage === 'denied' ? (
                <StateMessage
                  tone="empty"
                  icon="lock-closed-outline"
                  title={t('clinicalHistory.title')}
                  message={t('clinicalHistory.denied')}
                />
              ) : (
                <StateMessage
                  tone="error"
                  title={t('clinicalHistory.title')}
                  message={t(errorKey)}
                />
              )}
              <Button variant="secondary" label={t('common.back')} onPress={handleBack} />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  const header = (
    <View style={styles.header}>
      <AppTopBar onBack={handleBack} />
      <Text style={styles.title} accessibilityRole="header">
        {t('clinicalHistory.title')}
      </Text>
    </View>
  );

  const footer =
    loadMoreError || page.cursor !== null ? (
      <View style={styles.footer}>
        {loadMoreError ? <Notice tone="error" message={t('clinicalHistory.loadError')} /> : null}
        {page.cursor !== null ? (
          <Button
            variant="secondary"
            label={isLoadingMore ? t('clinicalHistory.loadingMore') : t('clinicalHistory.loadMore')}
            onPress={handleLoadMore}
            loading={isLoadingMore}
          />
        ) : null}
      </View>
    ) : null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <FlatList
        data={page.entries}
        keyExtractor={(entry: GuardianMedicalHistoryEntry) => entry.id}
        renderItem={({ item }) => (
          <ClinicalHistoryEntryCard
            entry={item}
            expanded={expandedIds.has(item.id)}
            onToggle={() => toggleExpanded(item.id)}
          />
        )}
        ListHeaderComponent={header}
        ListEmptyComponent={
          <StateMessage
            tone="empty"
            icon="document-text-outline"
            message={t('clinicalHistory.emptyState')}
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
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
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
  header: {
    gap: spacing.xl,
    marginBottom: spacing.xl,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  separator: {
    height: spacing.md,
  },
  footer: {
    gap: spacing.md,
    marginTop: spacing.xl,
  },
});

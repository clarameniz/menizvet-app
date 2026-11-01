import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { PetCard } from '@/components/design-system/pet-card';
import { StateMessage } from '@/components/design-system/state-message';
import { getMyPets, type Pet } from '@/data/pets';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'error' | 'loaded';

/**
 * Re-reads get_my_pets() on every focus, not just on mount: Pet detail
 * returns here with router.dismissTo (popping back to this same instance, see
 * lib/pets-navigation.ts) and Android back pops here too — after a possible
 * register/edit — so the list is never shown stale. Same pattern as
 * Appointments. Only the first load shows the loading/error states; a later
 * refresh updates in place and a failed refresh keeps the list on screen.
 *
 * Design System v1 presentation: header scrolls with the list; "Register
 * pet" is pinned above the bottom inset whenever the list loaded (including
 * the zero-pets state), and absent on a load error, as before.
 */
export default function MyPetsScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [pets, setPets] = useState<Pet[]>([]);

  const isMountedRef = useRef(true);
  // Latest-load-wins: focus reloads can overlap; only the newest may write state.
  const loadSeqRef = useRef(0);
  // Whether a list is already on screen (a ref: read from the focus callback).
  const hasLoadedRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useFocusEffect(
    useCallback(() => {
      const seq = ++loadSeqRef.current;

      getMyPets().then((result) => {
        if (!isMountedRef.current || seq !== loadSeqRef.current) return;

        if (result.error !== null) {
          // Only the first load may replace the screen with the error state.
          if (!hasLoadedRef.current) {
            setLoadState('error');
          }
          return;
        }

        // get_my_pets() has no ORDER BY — no ordering guarantee. Sorting here
        // is presentation only, not an authorization decision.
        const sorted = [...result.data].sort((a, b) => a.name.localeCompare(b.name));
        hasLoadedRef.current = true;
        setPets(sorted);
        setLoadState('loaded');
      });
    }, []),
  );

  const handleBack = () => goBackOr('/');

  const header = (
    <View style={styles.header}>
      <AppTopBar onBack={handleBack} />
      <View style={styles.titleBlock}>
        <Text style={styles.title} accessibilityRole="header">
          {t('pets.title')}
        </Text>
        <Text style={styles.support}>{t('pets.support')}</Text>
      </View>
    </View>
  );

  const emptyContent =
    loadState === 'loading' ? (
      <StateMessage tone="loading" message={t('pets.loading')} />
    ) : loadState === 'error' ? (
      <StateMessage tone="error" message={t('pets.loadError')} />
    ) : (
      <StateMessage tone="empty" icon="paw-outline" message={t('pets.emptyState')} />
    );

  const isLoaded = loadState === 'loaded';

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <FlatList
        data={isLoaded ? pets : []}
        keyExtractor={(pet) => pet.id}
        renderItem={({ item }) => <PetCard pet={item} />}
        ListHeaderComponent={header}
        ListEmptyComponent={emptyContent}
        ItemSeparatorComponent={ItemSeparator}
        contentContainerStyle={[
          styles.listContent,
          !isLoaded && { paddingBottom: insets.bottom + spacing.xl },
        ]}
        showsVerticalScrollIndicator={false}
      />

      {isLoaded ? (
        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          <Button label={t('pets.registerAction')} onPress={() => router.push('/pets/new')} />
        </View>
      ) : null}
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
    paddingBottom: spacing.xl,
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
  separator: {
    height: spacing.md,
  },
  footer: {
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.md,
    backgroundColor: colors.background,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ComponentProps,
  type ReactNode,
} from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { PetAvatar } from '@/components/design-system/pet-card';
import { StateMessage } from '@/components/design-system/state-message';
import { getMyPetById, type Pet } from '@/data/pets';
import { useLocale } from '@/i18n/locale-provider';
import { formatCalendarDateForDisplay } from '@/lib/pet-date';
import { petSummary } from '@/lib/pet-summary';
import { returnToPetsList } from '@/lib/pets-navigation';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'error' | 'notFound' | 'loaded';

/**
 * Reads via getMyPetById (src/data/pets.ts), a client-side convenience over
 * the same approved get_my_pets() contract — there is no single-Pet read
 * RPC in the backend, and get_my_pets() already returns full profile detail,
 * so no second read API was invented.
 *
 * The Edit action navigates to /pets/[id]/edit (src/app/pets/[id]/edit.tsx),
 * which calls the approved update_pet_profile RPC. This screen never
 * optimistically reflects an edit's result — the edit screen returns here
 * with router.dismissTo on success, and this screen re-reads fresh state on
 * every focus (not just on mount), so the returning instance is never stale.
 *
 * "Back to my pets" uses router.dismissTo('/pets') (lib/pets-navigation.ts),
 * not replace: it pops back to the My Pets already beneath — which re-reads on
 * focus — instead of stacking a second list over a stale one, and replaces
 * this screen with My Pets only when none is beneath (direct/deep-link entry).
 *
 * profile_image_reference is never rendered — see src/data/pets.ts's module
 * doc comment for why.
 */
export default function PetDetailScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [pet, setPet] = useState<Pet | null>(null);

  const isMountedRef = useRef(true);
  // Latest-load-wins: focus reloads can overlap; only the newest may write state.
  const loadSeqRef = useRef(0);
  // Whether a Pet is already on screen (a ref: read from the focus callback).
  const hasPetRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useFocusEffect(
    useCallback(() => {
      const seq = ++loadSeqRef.current;

      getMyPetById(id).then((result) => {
        if (!isMountedRef.current || seq !== loadSeqRef.current) return;

        if (result.error !== null) {
          // Only the first load may replace the screen with the error state;
          // a failed refresh keeps the Pet already shown.
          if (!hasPetRef.current) {
            setLoadState('error');
          }
          return;
        }

        // Authoritative: the Pet is no longer among the Guardian's current
        // Pets (e.g. Guardianship ended meanwhile) — shown even on refresh.
        if (!result.data) {
          setLoadState('notFound');
          return;
        }

        hasPetRef.current = true;
        setPet(result.data);
        setLoadState('loaded');
      });
    }, [id]),
  );

  const backToList = returnToPetsList;

  if (loadState !== 'loaded' || !pet) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={backToList} />
          {loadState === 'loading' ? (
            <StateMessage tone="loading" message={t('pets.loading')} />
          ) : (
            <>
              <StateMessage
                tone="error"
                message={loadState === 'notFound' ? t('pets.detailNotFound') : t('pets.loadError')}
              />
              <Button variant="secondary" label={t('pets.backToList')} onPress={backToList} />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  const notSpecified = t('pets.notSpecified');
  const birthDateRow =
    pet.dateOfBirth !== null
      ? { label: t('petForm.birthDateExact'), value: formatCalendarDateForDisplay(pet.dateOfBirth) }
      : pet.approximateDateOfBirth !== null
        ? {
            label: t('petForm.birthDateApproximate'),
            value: formatCalendarDateForDisplay(pet.approximateDateOfBirth),
          }
        : null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView
        contentContainerStyle={[
          styles.scrollContent,
          { paddingBottom: insets.bottom + spacing.xl },
        ]}
        showsVerticalScrollIndicator={false}
      >
        <AppTopBar onBack={backToList} />

        <View style={styles.identity}>
          <PetAvatar size={56} />
          <View style={styles.identityText}>
            <Text style={styles.name} accessibilityRole="header">
              {pet.name}
            </Text>
            <Text style={styles.summary}>{petSummary(pet)}</Text>
          </View>
        </View>

        <View style={styles.infoCard}>
          <InfoSection icon="paw-outline" title={t('pets.sectionProfile')}>
            <InfoRow
              label={t('petForm.speciesLabel')}
              value={pet.species}
              fallback={notSpecified}
            />
            <InfoRow label={t('petForm.breedLabel')} value={pet.breed} fallback={notSpecified} />
            <InfoRow label={t('petForm.sexLabel')} value={pet.sex} fallback={notSpecified} />
            {/* Same "date (Exact|Approximate)" composition as before —
                presentation-only change. */}
            <InfoRow
              label={t('petForm.birthDateLabel')}
              value={birthDateRow ? `${birthDateRow.value} (${birthDateRow.label})` : null}
              fallback={notSpecified}
            />
          </InfoSection>

          <Divider />

          <InfoSection icon="barcode-outline" title={t('pets.sectionIdentification')}>
            <InfoRow
              label={t('petForm.microchipLabel')}
              value={pet.microchipIdentifier}
              fallback={notSpecified}
            />
          </InfoSection>

          <Divider />

          <InfoSection icon="shield-checkmark-outline" title={t('pets.sectionBehavior')}>
            <Text
              style={pet.behavioralSafetyInformation ? styles.paragraph : styles.missingValue}
              accessibilityLabel={`${t('petForm.behavioralInfoLabel')}: ${
                pet.behavioralSafetyInformation ?? notSpecified
              }`}
            >
              {pet.behavioralSafetyInformation ?? notSpecified}
            </Text>
          </InfoSection>
        </View>

        <View style={styles.actions}>
          <Button
            label={t('clinicalHistory.entryPointAction')}
            onPress={() => router.push(`/pets/${pet.id}/medical-history`)}
          />
          <Button
            variant="secondary"
            label={t('pets.editAction')}
            onPress={() => router.push(`/pets/${pet.id}/edit`)}
          />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

type InfoSectionProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  title: string;
  children: ReactNode;
};

function InfoSection({ icon, title, children }: InfoSectionProps) {
  return (
    <View style={styles.section}>
      <View style={styles.sectionHeader}>
        <View
          style={styles.sectionIcon}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Ionicons name={icon} size={16} color={colors.primary} />
        </View>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {title}
        </Text>
      </View>
      <View style={styles.sectionBody}>{children}</View>
    </View>
  );
}

type InfoRowProps = {
  label: string;
  value: string | null;
  /** The translated "Not specified" — shown (muted) and announced when value is null. */
  fallback: string;
};

function InfoRow({ label, value, fallback }: InfoRowProps) {
  return (
    <View style={styles.row} accessible accessibilityLabel={`${label}: ${value ?? fallback}`}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={value !== null ? styles.rowValue : [styles.rowValue, styles.missingValue]}>
        {value ?? fallback}
      </Text>
    </View>
  );
}

function Divider() {
  return <View style={styles.divider} />;
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
  scrollContent: {
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    gap: spacing.xl,
  },
  identity: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
  },
  identityText: {
    flex: 1,
    gap: 2,
  },
  name: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  summary: {
    ...typography.body,
    color: colors.textSecondary,
  },
  infoCard: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingHorizontal: spacing.lg,
  },
  section: {
    paddingVertical: spacing.lg,
    gap: spacing.md,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  sectionIcon: {
    width: 28,
    height: 28,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  sectionBody: {
    gap: spacing.md,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: spacing.lg,
  },
  rowLabel: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 0,
    maxWidth: '45%',
  },
  rowValue: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
    flexShrink: 1,
    textAlign: 'right',
  },
  paragraph: {
    ...typography.body,
    color: colors.textPrimary,
  },
  // Muted but still AA (`textSecondary`, not `textMuted`) and still the
  // real translated "Not specified" text, so the meaning survives for
  // sighted and screen-reader users alike.
  missingValue: {
    ...typography.caption,
    fontWeight: '400',
    fontStyle: 'italic',
    color: colors.textSecondary,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
  },
  actions: {
    gap: spacing.md,
  },
});

import { useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { PetProfileFields } from '@/components/pet-profile-fields';
import { getMyPetById, updatePetProfile, type Pet } from '@/data/pets';
import { useLocale } from '@/i18n/locale-provider';
import { mapPetErrorToKey } from '@/i18n/pet-error-messages';
import { goBackOr } from '@/lib/navigation';
import { returnToPetDetail, returnToPetsList } from '@/lib/pets-navigation';
import { parseCalendarDate } from '@/lib/pet-date';
import {
  normalizePetFormFields,
  validatePetFormFields,
  type PetFormRawFields,
} from '@/lib/pet-form';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'error' | 'notFound' | 'loaded';
type SubmissionErrorKind = 'stale' | 'lostGuardianship' | 'other';

function fieldsFromPet(pet: Pet): PetFormRawFields {
  const { year, month, day } = parseCalendarDate(pet.dateOfBirth ?? pet.approximateDateOfBirth);

  return {
    name: pet.name,
    species: pet.species,
    breed: pet.breed ?? '',
    sex: pet.sex ?? '',
    microchip: pet.microchipIdentifier ?? '',
    behavioralInfo: pet.behavioralSafetyInformation ?? '',
    birthDate: {
      mode:
        pet.dateOfBirth !== null
          ? 'exact'
          : pet.approximateDateOfBirth !== null
            ? 'approximate'
            : 'unknown',
      year,
      month,
      day,
    },
  };
}

/**
 * Calls only the approved update_pet_profile RPC (src/data/pets.ts). This is
 * a full-replacement operation, so the submitted payload always includes
 * every current mutable field, not only the ones changed here — including
 * profileImageReference, round-tripped byte-for-byte from the loaded Pet
 * since mobile has no way to display, interpret, or edit that value (see
 * src/data/pets.ts's module doc comment).
 *
 * Authorization is never checked or assumed client-side: the form is
 * initialized only from a fresh Guardian-authorized read (getMyPetById), and
 * every outcome the RPC can return — including a lost/absent current
 * Guardianship (SQLSTATE 42501, indistinguishable from a nonexistent Pet by
 * design) and a stale profile_revision (SQLSTATE P0001, meaning the Pet
 * changed elsewhere since this form was loaded) — is handled explicitly
 * rather than assumed away.
 */
export default function EditPetScreen() {
  const { t } = useLocale();
  const { id } = useLocalSearchParams<{ id: string }>();

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [pet, setPet] = useState<Pet | null>(null);
  const [fields, setFields] = useState<PetFormRawFields | null>(null);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submissionError, setSubmissionError] = useState<string | null>(null);
  const [submissionErrorKind, setSubmissionErrorKind] = useState<SubmissionErrorKind | null>(null);

  const isMountedRef = useRef(true);

  useEffect(() => {
    isMountedRef.current = true;

    getMyPetById(id).then((result) => {
      if (!isMountedRef.current) return;

      if (result.error !== null) {
        setLoadState('error');
        return;
      }

      if (!result.data) {
        setLoadState('notFound');
        return;
      }

      setPet(result.data);
      setFields(fieldsFromPet(result.data));
      setLoadState('loaded');
    });

    return () => {
      isMountedRef.current = false;
    };
  }, [id]);

  // Used only by the stale-revision "reload current data" action below
  // (never called from the effect above, which loads independently on
  // mount): re-reads the Pet through the same Guardian-authorized path and
  // resets the form and any submission error to match the fresh state.
  async function handleReload() {
    const result = await getMyPetById(id);
    if (!isMountedRef.current) return;

    if (result.error !== null) {
      setLoadState('error');
      return;
    }

    if (!result.data) {
      setLoadState('notFound');
      return;
    }

    setPet(result.data);
    setFields(fieldsFromPet(result.data));
    setSubmissionError(null);
    setSubmissionErrorKind(null);
    setLoadState('loaded');
  }

  async function handleSubmit() {
    if (isSubmitting || !pet || !fields) return;

    setSubmissionError(null);
    setSubmissionErrorKind(null);

    const validationError = validatePetFormFields(fields);
    if (validationError === 'requiredField') {
      setSubmissionError(t('petForm.requiredFieldError'));
      return;
    }
    if (validationError === 'invalidBirthDate') {
      setSubmissionError(t('petForm.birthDateInvalid'));
      return;
    }

    const normalized = normalizePetFormFields(fields);

    setIsSubmitting(true);

    // try/finally, not a bare await: every terminal outcome — success,
    // stale revision, lost Guardianship, generic RPC/network failure, or an
    // unexpected thrown error — must leave the screen in a non-submitting
    // state. A bare await here previously let any rejection (updatePetProfile
    // is documented to resolve {data, error}, but that was never a
    // structural guarantee) skip every line below it, including
    // setIsSubmitting(false), permanently stranding the Save button in its
    // loading state — the defect this fixes. The finally below cannot be
    // bypassed by a return or a throw in the try block.
    try {
      const result = await updatePetProfile({
        id: pet.id,
        expectedProfileRevision: pet.profileRevision,
        ...normalized,
        profileImageReference: pet.profileImageReference,
      });

      if (!isMountedRef.current) return;

      if (result.error !== null) {
        const key = mapPetErrorToKey(result.error);
        setSubmissionError(t(key));
        setSubmissionErrorKind(
          key === 'petForm.staleRevisionError'
            ? 'stale'
            : key === 'petForm.lostGuardianshipError'
              ? 'lostGuardianship'
              : 'other',
        );
        return;
      }

      // The RPC's returned revision is not treated as sufficient proof of
      // the full profile: return to the detail screen, which performs its
      // own fresh Guardian-authorized read on focus, so rendered state is
      // always confirmed backend state, never the submitted values.
      // dismissTo, not replace: pops back to the detail already beneath (no
      // duplicate detail left in the stack), or replaces this screen with
      // it on direct/deep-link entry.
      returnToPetDetail(pet.id);
    } finally {
      if (isMountedRef.current) {
        setIsSubmitting(false);
      }
    }
  }

  // Pushed from Pet detail: visible back pops to it, exactly like Android
  // hardware back (fallback to that same detail when there's nothing to pop).
  const handleBack = () => goBackOr(`/pets/${id}`);

  // Safe exit for the terminal states below: back to My Pets via dismissTo —
  // pops to the list already beneath (which re-reads on focus) instead of
  // stacking a duplicate, or replaces this screen with it on direct entry.
  const backToList = returnToPetsList;

  if (loadState === 'loading') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={handleBack} />
          <StateMessage tone="loading" message={t('pets.loading')} />
        </View>
      </SafeAreaView>
    );
  }

  if (loadState === 'error' || loadState === 'notFound') {
    return (
      <TerminalState
        message={loadState === 'notFound' ? t('pets.detailNotFound') : t('pets.loadError')}
        actionLabel={t('pets.backToList')}
        onAction={backToList}
      />
    );
  }

  if (!pet || !fields) return null;

  // UX only, same rule as Register Pet: the normal Save button stays (quietly)
  // disabled until the exact rule handleSubmit enforces passes. Validity only —
  // not whether anything changed. Never applied to the stale-revision Reload
  // action below, which must stay available whatever the local draft holds.
  const canSave = !isSubmitting && validatePetFormFields(fields) === null;

  if (submissionErrorKind === 'lostGuardianship') {
    return (
      <TerminalState
        message={submissionError ?? t('petForm.lostGuardianshipError')}
        actionLabel={t('pets.backToList')}
        onAction={backToList}
      />
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      {/* Always-light background — explicit dark status-bar icons. */}
      <StatusBar style="dark" />
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <AppTopBar onBack={handleBack} />

          <Text style={styles.title} accessibilityRole="header">
            {t('petForm.editTitle')}
          </Text>

          <PetProfileFields value={fields} onChange={setFields} markRequired />

          <View style={styles.actions}>
            {submissionError ? <Notice tone="error" message={submissionError} /> : null}

            {submissionErrorKind === 'stale' ? (
              <Button label={t('petForm.staleRevisionReload')} onPress={handleReload} />
            ) : (
              <Button
                label={t('petForm.submitEdit')}
                onPress={handleSubmit}
                loading={isSubmitting}
                disabled={!canSave}
              />
            )}
            <Button
              variant="secondary"
              label={t('petForm.cancel')}
              onPress={handleBack}
              disabled={isSubmitting}
            />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

type TerminalStateProps = {
  message: string;
  actionLabel: string;
  onAction: () => void;
};

/**
 * Not-found / load-error / lost-Guardianship: one already-localized message
 * and the single safe exit (fresh My Pets). The top-bar back goes to the same
 * place, so no path from here lands on a possibly stale Pet detail.
 */
function TerminalState({ message, actionLabel, onAction }: TerminalStateProps) {
  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <View style={styles.stateContent}>
        <AppTopBar onBack={onAction} />
        <StateMessage tone="error" message={message} />
        <Button variant="secondary" label={actionLabel} onPress={onAction} />
      </View>
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
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  actions: {
    gap: spacing.md,
  },
});

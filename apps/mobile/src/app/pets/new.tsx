import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { PetProfileFields } from '@/components/pet-profile-fields';
import { registerPet } from '@/data/pets';
import { mapPetErrorToKey } from '@/i18n/pet-error-messages';
import { useLocale } from '@/i18n/locale-provider';
import type { PetFormRawFields } from '@/lib/pet-form';
import { goBackOr } from '@/lib/navigation';
import { normalizePetFormFields, validatePetFormFields } from '@/lib/pet-form';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

const INITIAL_FIELDS: PetFormRawFields = {
  name: '',
  species: '',
  breed: '',
  sex: '',
  microchip: '',
  behavioralInfo: '',
  birthDate: { mode: 'unknown', year: '', month: '', day: '' },
};

/**
 * Calls only the approved register_pet RPC (src/data/pets.ts). Field
 * rendering and normalization are shared with the Edit screen
 * (src/components/pet-profile-fields.tsx, src/lib/pet-form.ts) since both
 * submit the same fields under identical normalization rules; only the RPC
 * call and its result handling differ, and stay owned by this route.
 *
 * Pushed from My Pets, so the visible back control pops back to it — the
 * same destination as Android hardware back (with a `replace('/pets')`
 * fallback when there is nothing to pop, e.g. a direct deep link).
 *
 * profile_image_reference is never collected — see src/data/pets.ts's
 * module doc comment for why.
 */
export default function RegisterPetScreen() {
  const { t } = useLocale();

  const [fields, setFields] = useState<PetFormRawFields>(INITIAL_FIELDS);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleBack = () => goBackOr('/pets');

  // UX only: the button stays (quietly) disabled until the exact same rule
  // handleSubmit enforces passes — name and species non-blank, and a complete
  // valid date only when "exact"/"approximate" is chosen. No error is shown for
  // an incomplete form; handleSubmit still re-validates defensively.
  const canSubmit = !isSubmitting && validatePetFormFields(fields) === null;

  async function handleSubmit() {
    if (isSubmitting) return;

    setError(null);

    const validationError = validatePetFormFields(fields);
    if (validationError === 'requiredField') {
      setError(t('petForm.requiredFieldError'));
      return;
    }
    if (validationError === 'invalidBirthDate') {
      setError(t('petForm.birthDateInvalid'));
      return;
    }

    const normalized = normalizePetFormFields(fields);

    setIsSubmitting(true);

    const result = await registerPet(normalized);

    setIsSubmitting(false);

    if (result.error !== null) {
      setError(t(mapPetErrorToKey(result.error)));
      return;
    }

    // Navigate to the created Pet rather than back to the list: replace (not
    // push) so this screen isn't left in the stack, and the detail screen
    // does its own fresh get_my_pets() read on mount — no optimistic
    // insert, the list/detail always reflect confirmed backend state.
    router.replace(`/pets/${result.data.id}`);
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

          <View style={styles.titleBlock}>
            <Text style={styles.title} accessibilityRole="header">
              {t('petForm.registerTitle')}
            </Text>
            <Text style={styles.support}>{t('petForm.registerSupport')}</Text>
          </View>

          <PetProfileFields value={fields} onChange={setFields} markRequired />

          <View style={styles.actions}>
            {error ? <Notice tone="error" message={error} /> : null}
            <Button
              label={t('petForm.submit')}
              onPress={handleSubmit}
              loading={isSubmitting}
              disabled={!canSubmit}
            />
          </View>
        </ScrollView>
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
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
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
  actions: {
    gap: spacing.md,
  },
});

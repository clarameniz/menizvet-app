import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { getMyProfessionalContext } from '@/data/professional-context';
import { createMyVeterinarianProfessionalProfile } from '@/data/veterinarian-profile';
import { useVeterinarianProfile } from '@/hooks/use-veterinarian-profile';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import {
  canReviewVeterinarianProfile,
  EMPTY_VETERINARIAN_PROFILE_DRAFT,
  reviewedVeterinarianProfile,
  veterinarianProfileOutcome,
  type VeterinarianProfileDraft,
} from '@/lib/veterinarian-profile';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * SPEC-VET-001 §13: the professional completes their own Veterinarian
 * Professional Profile — exactly the registration identifier and its issuing
 * context — after a review step, because the Profile cannot yet be edited
 * once created. Nothing here claims that MenizVet verified the credential.
 * Organization-independent: the Profile belongs to the User.
 */
export default function VeterinarianProfileScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { state, reload: load, markCompleted, leave, isActive } = useVeterinarianProfile();
  const [draft, setDraft] = useState<VeterinarianProfileDraft>(EMPTY_VETERINARIAN_PROFILE_DRAFT);
  const [step, setStep] = useState<'edit' | 'review'>('edit');
  const [sending, setSending] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);
  const busyRef = useRef(false);
  useEffect(() => {
    void load();
  }, [load]);
  const back = useCallback(() => {
    leave(() => goBackOr('/professional'));
  }, [leave]);

  async function create() {
    if (busyRef.current || !isActive() || !canReviewVeterinarianProfile(draft)) return;
    busyRef.current = true;
    setSending(true);
    setErrorKey(null);
    try {
      const result = await createMyVeterinarianProfessionalProfile(draft);
      if (!isActive()) return;
      // Always the authoritative re-read: it also clears the Home prompt.
      const reread = await getMyProfessionalContext();
      if (!isActive()) return;
      const outcome = veterinarianProfileOutcome(result, reread);
      if (outcome === 'created') {
        leave(() => {
          AccessibilityInfo.announceForAccessibility(t('veterinarianProfile.created'));
          router.dismissTo('/professional');
        });
        return;
      }
      setErrorKey(outcome);
      if (reread.error === null && reread.data.hasVeterinarianProfessionalProfile) markCompleted();
    } finally {
      busyRef.current = false;
      if (isActive()) setSending(false);
    }
  }

  if (state.kind !== 'loaded' || state.availability !== 'form') {
    const messageKey: TranslationKey =
      state.kind === 'loading'
        ? 'veterinarianProfile.loading'
        : state.kind === 'error'
          ? state.messageKey
          : state.availability === 'completed'
            ? 'veterinarianProfile.completed'
            : 'veterinarianProfile.notOffered';
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={back} />
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          <StateMessage
            tone={state.kind === 'loading' ? 'loading' : state.kind === 'error' ? 'error' : 'empty'}
            message={t(messageKey)}
          />
          {state.kind === 'loaded' && state.availability === 'completed' ? (
            <Text style={styles.hint}>{t('veterinarianProfile.completedAssignmentNote')}</Text>
          ) : null}
          {state.kind === 'error' ? (
            <Button label={t('professional.retry')} onPress={() => void load()} />
          ) : null}
          {state.kind === 'loading' ? null : (
            <Button variant="secondary" label={t('veterinarianProfile.back')} onPress={back} />
          )}
        </View>
      </SafeAreaView>
    );
  }

  const reviewed = reviewedVeterinarianProfile(draft);
  const update = (next: VeterinarianProfileDraft) => {
    if (busyRef.current) return;
    setDraft(next);
    setErrorKey(null);
  };

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
        >
          <AppTopBar
            onBack={() => {
              if (step === 'review' && !busyRef.current) setStep('edit');
              else back();
            }}
          />
          <Text style={styles.title} accessibilityRole="header">
            {t(step === 'edit' ? 'veterinarianProfile.title' : 'veterinarianProfile.reviewTitle')}
          </Text>
          {step === 'edit' ? (
            <>
              <Text style={styles.hint}>{t('veterinarianProfile.intro')}</Text>
              <Text style={styles.hint}>{t('veterinarianProfile.assignmentNote')}</Text>
              <Input
                label={t('veterinarianProfile.identifierLabel')}
                value={draft.registrationIdentifier}
                onChangeText={(registrationIdentifier) =>
                  update({ ...draft, registrationIdentifier })
                }
                autoCapitalize="characters"
                autoCorrect={false}
                required
              />
              <Input
                label={t('veterinarianProfile.contextLabel')}
                value={draft.issuingContext}
                onChangeText={(issuingContext) => update({ ...draft, issuingContext })}
                autoCorrect={false}
                required
              />
              <Text style={styles.hint}>{t('veterinarianProfile.contextHint')}</Text>
            </>
          ) : (
            <>
              <View
                style={styles.review}
                accessible
                accessibilityRole="text"
                accessibilityLabel={`${t('veterinarianProfile.identifierLabel')}: ${reviewed.registrationIdentifier}. ${t('veterinarianProfile.contextLabel')}: ${reviewed.issuingContext}`}
              >
                <Text style={styles.reviewLabel}>{t('veterinarianProfile.identifierLabel')}</Text>
                <Text style={styles.reviewValue}>{reviewed.registrationIdentifier}</Text>
                <Text style={styles.reviewLabel}>{t('veterinarianProfile.contextLabel')}</Text>
                <Text style={styles.reviewValue}>{reviewed.issuingContext}</Text>
              </View>
              <Text style={styles.hint}>{t('veterinarianProfile.notEditableNote')}</Text>
              <Text style={styles.hint}>{t('veterinarianProfile.notVerifiedNote')}</Text>
            </>
          )}
        </ScrollView>
        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          {step === 'edit' ? (
            <Button
              label={t('veterinarianProfile.reviewAction')}
              onPress={() => setStep('review')}
              disabled={!canReviewVeterinarianProfile(draft)}
            />
          ) : (
            <>
              <Button
                label={t('veterinarianProfile.submit')}
                onPress={() => void create()}
                loading={sending}
                disabled={sending}
              />
              <Button
                variant="secondary"
                label={t('veterinarianProfile.editAction')}
                onPress={() => setStep('edit')}
                disabled={sending}
              />
            </>
          )}
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  flex: { flex: 1 },
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
    gap: spacing.lg,
  },
  title: { ...typography.h2, color: colors.textPrimary },
  hint: { ...typography.caption, color: colors.textSecondary },
  review: {
    gap: spacing.xs,
    padding: spacing.lg,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  reviewLabel: { ...typography.caption, color: colors.textSecondary },
  reviewValue: { ...typography.bodyStrong, color: colors.textPrimary, flexShrink: 1 },
  footer: {
    gap: spacing.sm,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.md,
    backgroundColor: colors.background,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

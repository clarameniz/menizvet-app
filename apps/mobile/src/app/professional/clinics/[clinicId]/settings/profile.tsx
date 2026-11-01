import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { ClinicSettingsEditorStateView } from '@/components/clinic-settings-editor-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { saveClinicPublicProfile } from '@/data/clinic-settings';
import {
  useClinicSettingsEditor,
  type ClinicSettingsEditorRead,
} from '@/hooks/use-clinic-settings-editor';
import { mapClinicProfileSaveErrorToKey } from '@/i18n/clinic-settings-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { clinicSettingsHref } from '@/lib/clinic-settings';
import {
  canSaveProfile,
  profileDraftFrom,
  profileDraftIssue,
  profilePayload,
  profileSaveFailure,
  type ProfileDraft,
} from '@/lib/clinic-settings-editors';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Edits the Clinic's public profile (SPEC-CLI-004 BR-15–BR-21): clinic name,
 * description, public phone, public email, and website, in one save that
 * replaces all five values. Blank means absent, so any optional value can be
 * cleared; the name is needed to publish, and a published Clinic cannot save
 * without one. No format or length rules exist (BR-18), so none are invented.
 *
 * Reads fresh on mount; the draft starts from that authoritative read and
 * keeps the text exactly as typed. Save is enabled only when the draft is
 * valid, changes something, and nothing is in flight. On success it returns
 * to Clinic settings, which re-reads. On failure it re-reads: values that
 * already match what was sent (a lost response) count as saved; a lost
 * editor capability replaces the form with the unavailable state; otherwise
 * calm mapped copy is shown and the draft is kept. Nothing is retried, and
 * no stale-edit check exists (last-write-wins, BR-19). Leaving is terminal
 * and owned by the hook (`leave`).
 */
export default function ClinicProfileEditorScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const {
    state,
    reload,
    leave: leaveScreen,
    isActive,
  } = useClinicSettingsEditor(clinicId, 'profile');
  const [draft, setDraft] = useState<ProfileDraft | null>(null);
  const [saving, setSaving] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);

  // A save is in flight; a ref, so a second tap in the same frame can't submit twice.
  const busyRef = useRef(false);

  const leave = useCallback(() => {
    leaveScreen(() => router.dismissTo(clinicSettingsHref(clinicId)));
  }, [leaveScreen, clinicId]);

  // The draft starts from the first successful read only, and never once leaving.
  const initialize = useCallback(
    (read: ClinicSettingsEditorRead | null) => {
      if (read?.kind !== 'loaded' || !isActive()) return;
      setDraft((previous) => previous ?? profileDraftFrom(read.profile.publicProfile));
    },
    [isActive],
  );

  useEffect(() => {
    reload().then(initialize);
  }, [reload, initialize]);

  if (state.kind !== 'loaded' || draft === null) {
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

  const { profile } = state;
  const issue = profileDraftIssue(draft, profile.isPublished);
  const saveEnabled = canSaveProfile({ draft, profile, busy: saving });

  const update = (field: keyof ProfileDraft) => (text: string) =>
    setDraft((previous) => (previous === null ? previous : { ...previous, [field]: text }));

  async function save() {
    if (busyRef.current || !isActive() || !saveEnabled || draft === null) return;
    const submitted = profilePayload(draft);
    busyRef.current = true;
    setSaving(true);
    setErrorKey(null);
    try {
      const result = await saveClinicPublicProfile(clinicId, submitted);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      const outcome = profileSaveFailure(read, submitted);
      if (outcome === 'committed') {
        // Committed despite the failed response: done.
        leave();
        return;
      }
      // 'accessLost': the re-read already replaced the form with the unavailable state.
      if (outcome === 'failed') setErrorKey(mapClinicProfileSaveErrorToKey(result.error));
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
        >
          <AppTopBar onBack={leave} />
          <Text style={styles.title} accessibilityRole="header">
            {t('clinicSettingsProfile.title')}
          </Text>
          <Text style={styles.hint}>{t('clinicSettingsProfile.intro')}</Text>

          <View style={styles.field}>
            <Input
              label={t('clinicSettingsProfile.nameLabel')}
              accessibilityLabel={t('clinicSettingsProfile.nameAccessibility')}
              value={draft.displayName}
              onChangeText={update('displayName')}
              editable={!saving}
              autoCapitalize="words"
              error={
                issue === 'nameRequiredWhilePublished'
                  ? t('clinicSettingsProfile.nameRequiredWhilePublished')
                  : undefined
              }
            />
            {issue === null ? (
              <Text style={styles.hint}>{t('clinicSettingsProfile.nameHint')}</Text>
            ) : null}
          </View>

          <Input
            label={t('clinicSettingsProfile.descriptionLabel')}
            value={draft.description}
            onChangeText={update('description')}
            editable={!saving}
            multiline
          />
          <Input
            label={t('clinicSettingsProfile.phoneLabel')}
            value={draft.publicPhone}
            onChangeText={update('publicPhone')}
            editable={!saving}
            keyboardType="phone-pad"
            autoComplete="off"
          />
          <Input
            label={t('clinicSettingsProfile.emailLabel')}
            value={draft.publicEmail}
            onChangeText={update('publicEmail')}
            editable={!saving}
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="off"
          />
          <Input
            label={t('clinicSettingsProfile.websiteLabel')}
            value={draft.website}
            onChangeText={update('website')}
            editable={!saving}
            keyboardType="url"
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="off"
          />
          <Text style={styles.hint}>{t('clinicSettingsProfile.optionalHint')}</Text>
          <Text style={styles.hint}>
            {t(
              profile.isPublished
                ? 'clinicSettingsProfile.publishedNote'
                : 'clinicSettingsProfile.unpublishedNote',
            )}
          </Text>
        </ScrollView>

        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
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
    gap: spacing.lg,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  field: {
    gap: spacing.xs,
  },
  hint: {
    ...typography.caption,
    color: colors.textSecondary,
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

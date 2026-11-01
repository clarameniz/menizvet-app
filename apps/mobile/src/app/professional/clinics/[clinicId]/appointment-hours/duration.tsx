import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppointmentHoursStateView } from '@/components/appointment-hours-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { ChoiceChip } from '@/components/design-system/choice-chip';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { setStandardAppointmentDuration } from '@/data/clinic-appointment-hours';
import { useAppointmentHours, type AppointmentHoursRead } from '@/hooks/use-appointment-hours';
import { mapAppointmentHoursSaveErrorToKey } from '@/i18n/appointment-hours-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  DURATION_PRESETS_MINUTES,
  accessNoticeKey,
  appointmentHoursHref,
  canEditDuration,
  canSaveConfiguration,
  isDurationPreset,
  parseDurationInput,
} from '@/lib/appointment-hours';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** The chosen duration: a preset chip, or the "other" field's text. */
type DurationDraft = { source: 'preset'; minutes: number } | { source: 'other'; text: string };

function draftFrom(stored: number | null): DurationDraft {
  if (stored !== null && isDurationPreset(stored)) return { source: 'preset', minutes: stored };
  return { source: 'other', text: stored === null ? '' : String(stored) };
}

function minutesOf(draft: DurationDraft): number | null {
  return draft.source === 'preset' ? draft.minutes : parseDurationInput(draft.text);
}

/**
 * Edits the Clinic's standard Appointment duration (SPEC-APT-013 BR-57–BR-64):
 * common presets plus any other whole number of minutes from 10 to 240. A
 * valid duration is always required — this app never clears it (BR-62).
 *
 * Reads fresh on mount. Save is enabled only when the value is valid,
 * different from the stored one, editable, and nothing is in flight. On
 * success it returns to Appointment hours, which re-reads. On failure it
 * re-reads: if the stored duration already equals the submitted one (the
 * response was lost after commit) it returns as on success; otherwise it
 * shows calm mapped copy and keeps the draft. Nothing is retried. Leaving is
 * terminal and owned by the hook (`leave`): afterwards no read, initialization,
 * reconciliation, or `finally` updates this screen.
 */
export default function AppointmentDurationScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const { state, reload, leave: leaveScreen, isActive } = useAppointmentHours(clinicId);
  const [draft, setDraft] = useState<DurationDraft | null>(null);
  const [saving, setSaving] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);

  // A save is in flight; a ref, so a second tap in the same frame can't submit twice.
  const busyRef = useRef(false);

  const leave = useCallback(() => {
    leaveScreen(() => router.dismissTo(appointmentHoursHref(clinicId)));
  }, [leaveScreen, clinicId]);

  // The draft starts from the first successful read only, and never once leaving.
  const initialize = useCallback(
    (read: AppointmentHoursRead | null) => {
      if (read?.kind !== 'loaded' || !isActive()) return;
      setDraft((previous) => previous ?? draftFrom(read.config.standardAppointmentDurationMinutes));
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
          <AppointmentHoursStateView
            state={state.kind === 'loaded' ? { kind: 'loading' } : state}
            onRetry={() => reload().then(initialize)}
            onBack={leave}
            backLabel={t('appointmentHours.backToHours')}
          />
        </View>
      </SafeAreaView>
    );
  }

  const stored = state.config.standardAppointmentDurationMinutes;
  const editable = canEditDuration(state.access);
  const accessNotice = accessNoticeKey(state.access);
  const minutes = minutesOf(draft);
  const otherText = draft.source === 'other' ? draft.text : '';
  const otherInvalid = draft.source === 'other' && draft.text.trim() !== '' && minutes === null;
  const saveEnabled = canSaveConfiguration({
    editable,
    valid: minutes !== null,
    changed: minutes !== stored,
    busy: saving,
  });

  async function save() {
    if (busyRef.current || !isActive() || !saveEnabled || minutes === null) return;
    busyRef.current = true;
    setSaving(true);
    setErrorKey(null);
    try {
      const result = await setStandardAppointmentDuration(clinicId, minutes);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      if (read?.kind === 'loaded' && read.config.standardAppointmentDurationMinutes === minutes) {
        // Committed despite the failed response: done.
        leave();
        return;
      }
      setErrorKey(mapAppointmentHoursSaveErrorToKey(result.error));
    } finally {
      busyRef.current = false;
      if (isActive()) setSaving(false);
    }
  }

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <AppTopBar onBack={leave} />
        <Text style={styles.title} accessibilityRole="header">
          {t('appointmentHours.durationHeading')}
        </Text>
        <Text style={styles.hint}>{t('appointmentHours.durationIntro')}</Text>
        {accessNotice !== null ? <Notice tone="info" message={t(accessNotice)} /> : null}

        <View style={styles.section}>
          <Text style={styles.sectionTitle} accessibilityRole="header">
            {t('appointmentHours.durationPresetsLabel')}
          </Text>
          <View
            style={styles.chips}
            accessibilityRole="radiogroup"
            accessibilityLabel={t('appointmentHours.durationPresetsLabel')}
          >
            {DURATION_PRESETS_MINUTES.map((preset) => (
              <ChoiceChip
                key={preset}
                label={t('appointmentHours.durationValue', { minutes: preset })}
                accessibilityLabel={t('appointmentHours.durationPresetAccessibility', {
                  minutes: preset,
                })}
                selected={draft.source === 'preset' && draft.minutes === preset}
                disabled={!editable || saving}
                onPress={() => {
                  if (editable && !saving) setDraft({ source: 'preset', minutes: preset });
                }}
              />
            ))}
          </View>
        </View>

        <View style={styles.section}>
          <Input
            label={t('appointmentHours.durationOtherLabel')}
            accessibilityLabel={t('appointmentHours.durationOtherAccessibility')}
            value={otherText}
            keyboardType="number-pad"
            maxLength={3}
            editable={editable && !saving}
            onChangeText={(text) => setDraft({ source: 'other', text })}
            error={otherInvalid ? t('appointmentHours.durationInvalid') : undefined}
          />
          <Text style={styles.hint}>{t('appointmentHours.durationOtherHint')}</Text>
        </View>

        <Text style={styles.hint}>{t('appointmentHours.existingAppointmentsNote')}</Text>
      </ScrollView>

      {editable ? (
        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          <Button
            label={t('appointmentHours.save')}
            onPress={save}
            loading={saving}
            disabled={!saveEnabled}
          />
        </View>
      ) : null}
    </SafeAreaView>
  );
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
    paddingBottom: spacing.xl,
    gap: spacing.xl,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  section: {
    gap: spacing.sm,
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  chips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
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

import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppointmentHoursStateView } from '@/components/appointment-hours-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { TimePeriodListEditor } from '@/components/time-period-list-editor';
import {
  APPOINTMENT_HOURS_WEEKLY_STALE,
  replaceWeeklyAvailability,
} from '@/data/clinic-appointment-hours';
import { useAppointmentHours, type AppointmentHoursRead } from '@/hooks/use-appointment-hours';
import { mapAppointmentHoursSaveErrorToKey } from '@/i18n/appointment-hours-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  ISO_WEEKDAYS,
  accessNoticeKey,
  appointmentHoursHref,
  canEditAvailability,
  canSaveConfiguration,
  isWeeklyDraftChanged,
  isWeeklyDraftValid,
  weeklyEditorAfterRead,
  weeklyPayload,
  weeklySaveFailure,
  type WeeklyEditor,
} from '@/lib/appointment-hours';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Edits the Clinic's recurring weekly Appointment availability (SPEC-APT-013
 * BR-9, BR-41, BR-42, BR-75). The backend replaces the WHOLE week, so this
 * editor owns a draft of all seven ISO weekdays and one Save submits the
 * complete week — never weekday by weekday. A day without periods is closed;
 * periods need a start before their end and must not overlap within the day
 * (touching is fine); overnight hours are two days (… 24:00, then 00:00 …).
 *
 * Reads fresh on mount; the draft and the weekly revision it was prepared
 * from start from that first read, and the save sends that revision (BR-75).
 * On a failed save it re-reads: if the stored week already equals the
 * submitted one (a lost response after commit, or another editor saved the
 * same week) it returns as on success; if the save was stale it replaces the
 * draft with the latest week and revision and says so (never merged);
 * otherwise it shows calm mapped copy and keeps the draft. Nothing is
 * retried. Leaving is terminal and owned by the hook (`leave`): afterwards no
 * read, initialization, reconciliation, or `finally` updates this screen.
 */
export default function WeeklyAppointmentHoursScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const { state, reload, leave: leaveScreen, isActive } = useAppointmentHours(clinicId);
  const [editor, setEditor] = useState<WeeklyEditor | null>(null);
  const [saving, setSaving] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);
  // The draft was just replaced by the latest week after a stale save.
  const [refreshedAfterStale, setRefreshedAfterStale] = useState(false);

  // A save is in flight; a ref, so a second tap in the same frame can't submit twice.
  const busyRef = useRef(false);

  const leave = useCallback(() => {
    leaveScreen(() => router.dismissTo(appointmentHoursHref(clinicId)));
  }, [leaveScreen, clinicId]);

  // The draft and its base revision start from the first successful read
  // only, and never once leaving; later reads never replace either.
  const initialize = useCallback(
    (read: AppointmentHoursRead | null) => {
      if (read?.kind !== 'loaded' || !isActive()) return;
      setEditor((previous) => weeklyEditorAfterRead(previous, read.config));
    },
    [isActive],
  );

  useEffect(() => {
    reload().then(initialize);
  }, [reload, initialize]);

  if (state.kind !== 'loaded' || editor === null) {
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

  const { draft } = editor;
  const editable = canEditAvailability(state.config, state.access);
  const accessNotice = accessNoticeKey(state.access);
  const valid = isWeeklyDraftValid(draft);
  const saveEnabled = canSaveConfiguration({
    editable,
    valid,
    changed: valid && isWeeklyDraftChanged(draft, state.config.recurringPeriods),
    busy: saving,
  });

  async function save(base: WeeklyEditor) {
    if (busyRef.current || !isActive() || !saveEnabled) return;
    busyRef.current = true;
    setSaving(true);
    setErrorKey(null);
    setRefreshedAfterStale(false);
    const submitted = weeklyPayload(base.draft);
    try {
      const result = await replaceWeeklyAvailability(clinicId, submitted, base.baseRevision);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      const outcome = weeklySaveFailure({
        stale: result.error === APPOINTMENT_HOURS_WEEKLY_STALE,
        latest: read?.kind === 'loaded' ? read.config : null,
        submitted,
      });
      if (outcome.kind === 'committed') {
        leave();
      } else if (outcome.kind === 'stale') {
        setEditor(outcome.editor);
        setRefreshedAfterStale(true);
      } else {
        setErrorKey(mapAppointmentHoursSaveErrorToKey(result.error));
      }
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
        <View style={styles.titleBlock}>
          <Text style={styles.title} accessibilityRole="header">
            {t('appointmentHours.weeklyHeading')}
          </Text>
          {state.config.schedulingTimezoneName !== null ? (
            <Text style={styles.hint}>
              {t('appointmentHours.timezoneCaption', {
                timezone: state.config.schedulingTimezoneName,
              })}
            </Text>
          ) : null}
        </View>
        <Text style={styles.hint}>{t('appointmentHours.weeklyIntro')}</Text>
        {refreshedAfterStale ? (
          <Notice tone="info" message={t('appointmentHours.weeklyStale')} />
        ) : null}
        {state.config.schedulingTimezoneName === null ? (
          <Notice tone="info" message={t('appointmentHours.timezoneMissingNotice')} />
        ) : accessNotice !== null ? (
          <Notice tone="info" message={t(accessNotice)} />
        ) : null}

        {ISO_WEEKDAYS.map((weekday) => {
          const dayName = t(`appointmentHours.weekday${weekday}`);
          return (
            <View key={weekday} style={styles.day}>
              <Text style={styles.dayTitle} accessibilityRole="header">
                {dayName}
              </Text>
              <TimePeriodListEditor
                groupLabel={dayName}
                periods={draft[weekday]}
                editable={editable && !saving}
                emptyLabel={t('appointmentHours.closed')}
                onChange={(periods) =>
                  setEditor((previous) =>
                    previous === null
                      ? previous
                      : { ...previous, draft: { ...previous.draft, [weekday]: periods } },
                  )
                }
              />
            </View>
          );
        })}

        <Text style={styles.hint}>{t('appointmentHours.existingAppointmentsNote')}</Text>
      </ScrollView>

      {editable ? (
        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          {!valid ? <Notice tone="info" message={t('appointmentHours.invalidFormHint')} /> : null}
          <Button
            label={t('appointmentHours.save')}
            onPress={() => save(editor)}
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
    gap: spacing.lg,
  },
  titleBlock: {
    gap: spacing.xs,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  day: {
    gap: spacing.sm,
    padding: spacing.md,
    borderRadius: radius.medium,
    backgroundColor: colors.surfaceSoft,
  },
  dayTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
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

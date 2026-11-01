import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppointmentHoursStateView } from '@/components/appointment-hours-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { CandidateWindowNavigator } from '@/components/design-system/candidate-window-navigator';
import { ChoiceChip } from '@/components/design-system/choice-chip';
import { DateChip } from '@/components/design-system/date-chip';
import { Notice } from '@/components/design-system/notice';
import { TimePeriodListEditor } from '@/components/time-period-list-editor';
import {
  clearAvailabilityException,
  setAvailabilityException,
  type ClinicAppointmentHours,
} from '@/data/clinic-appointment-hours';
import { useAppointmentHours, type AppointmentHoursRead } from '@/hooks/use-appointment-hours';
import { mapAppointmentHoursSaveErrorToKey } from '@/i18n/appointment-hours-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  EXCEPTION_DATE_WINDOW_DAYS,
  accessNoticeKey,
  appointmentHoursHref,
  canEditAvailability,
  canSaveConfiguration,
  exceptionDateWindow,
  exceptionDraftFrom,
  exceptionFor,
  exceptionMatches,
  exceptionPayload,
  formatExceptionDate,
  isExceptionDraftChanged,
  isExceptionDraftValid,
  isLocalDate,
  isoWeekdayOfLocalDate,
  prefillCustomHours,
  recurringRangesFor,
  type ExceptionDraft,
  type ExceptionKindChoice,
  type PeriodDraft,
} from '@/lib/appointment-hours';
import {
  clinicLocalToday,
  formatCandidateDateLabel,
  formatCandidateDateParts,
  formatCandidateWindowDate,
  shiftLocalDate,
} from '@/lib/appointment-time';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type Editor = {
  draft: ExceptionDraft;
  /** Editing the stored exception of a fixed date (offers Remove), or creating one. */
  mode: 'edit' | 'new';
  /** Whether the user changed the periods; until then custom hours follow the chosen date. */
  periodsTouched: boolean;
  /** First date of the date window on screen (new exceptions only). */
  windowStart: string;
};

function editorFrom(config: ClinicAppointmentHours, routeDate: string | null): Editor | null {
  if (config.schedulingTimezoneName === null) return null;
  const today = clinicLocalToday(config.schedulingTimezoneName);
  const date = routeDate !== null && isLocalDate(routeDate) ? routeDate : null;
  const stored = date === null ? null : exceptionFor(config.exceptions, date);
  if (stored !== null) {
    return {
      draft: exceptionDraftFrom(stored),
      mode: 'edit',
      periodsTouched: true,
      windowStart: today,
    };
  }
  const selectable = date !== null && date >= today ? date : null;
  return {
    draft: { localDate: selectable, kind: null, periods: [] },
    mode: 'new',
    periodsTouched: false,
    windowStart: selectable ?? today,
  };
}

/**
 * Creates, changes, or removes the Appointment availability exception of one
 * Clinic-local date (SPEC-APT-013 BR-10, BR-11, BR-73, BR-75). The backend has
 * only CLOSED (no periods) and OPEN (one or more periods); either fully
 * replaces that date's weekly hours, and establishing one replaces any other
 * on the same date. "Closed all day" writes CLOSED; "Custom hours" writes
 * OPEN. New custom hours start from that weekday's usual hours, so a
 * partial-day closure ("close at 14:00 next Tuesday") is one edit, and a
 * normally closed day starts from one empty period.
 *
 * Route: `?date=YYYY-MM-DD` edits that date's stored exception (with Remove);
 * no date creates a new one on a date chosen from Clinic-local today onwards.
 * Reads fresh on mount and never trusts navigation for the stored exception.
 * Saves and removals re-read on failure: if the stored state already matches
 * what was sent (a lost response after commit) it returns as on success.
 * Nothing is retried. Leaving is terminal and owned by the hook (`leave`):
 * afterwards no read, initialization, reconciliation, or `finally` updates
 * this screen.
 */
export default function AppointmentHoursExceptionScreen() {
  const { t, locale } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId, date: routeDate } = useLocalSearchParams<{ clinicId: string; date?: string }>();
  const { state, reload, leave: leaveScreen, isActive } = useAppointmentHours(clinicId);
  const [editor, setEditor] = useState<Editor | null>(null);
  const [busy, setBusy] = useState<'save' | 'remove' | null>(null);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);

  // A dialog is open or a write is in flight; a ref, so a second tap in the
  // same frame can't open another dialog or submit twice.
  const busyRef = useRef(false);

  const leave = useCallback(() => {
    leaveScreen(() => router.dismissTo(appointmentHoursHref(clinicId)));
  }, [leaveScreen, clinicId]);

  // The editor starts from the first successful read only, and never once leaving.
  const initialize = useCallback(
    (read: AppointmentHoursRead | null) => {
      if (read?.kind !== 'loaded' || !isActive()) return;
      setEditor((previous) => previous ?? editorFrom(read.config, routeDate ?? null));
    },
    [isActive, routeDate],
  );

  useEffect(() => {
    reload().then(initialize);
  }, [reload, initialize]);

  if (state.kind !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={leave} />
          <AppointmentHoursStateView
            state={state}
            onRetry={() => reload().then(initialize)}
            onBack={leave}
            backLabel={t('appointmentHours.backToHours')}
          />
        </View>
      </SafeAreaView>
    );
  }

  const { config, access } = state;
  const timezone = config.schedulingTimezoneName;
  if (timezone === null || !canEditAvailability(config, access)) {
    // Weekly hours and exceptions are not editable here (no timezone, or not editable access).
    const accessNotice = accessNoticeKey(access);
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={leave} />
          {timezone === null ? (
            <Notice tone="info" message={t('appointmentHours.timezoneMissingNotice')} />
          ) : null}
          {accessNotice !== null ? <Notice tone="info" message={t(accessNotice)} /> : null}
          <Button variant="secondary" label={t('appointmentHours.backToHours')} onPress={leave} />
        </View>
      </SafeAreaView>
    );
  }

  if (editor === null) {
    // Loaded and editable; the editor is initialized from this first read right after.
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={leave} />
          <AppointmentHoursStateView
            state={{ kind: 'loading' }}
            onRetry={() => reload().then(initialize)}
            onBack={leave}
            backLabel={t('appointmentHours.backToHours')}
          />
        </View>
      </SafeAreaView>
    );
  }

  const { draft, mode, periodsTouched, windowStart } = editor;
  const today = clinicLocalToday(timezone);
  const stored = draft.localDate === null ? null : exceptionFor(config.exceptions, draft.localDate);
  const valid = isExceptionDraftValid(draft, today);
  const saveEnabled = canSaveConfiguration({
    editable: true,
    valid,
    changed: valid && isExceptionDraftChanged(draft, stored),
    busy: busy !== null,
  });
  const normallyClosed =
    draft.localDate !== null &&
    recurringRangesFor(config.recurringPeriods, isoWeekdayOfLocalDate(draft.localDate)).length ===
      0;
  const dateLabel = draft.localDate === null ? null : formatExceptionDate(draft.localDate, locale);

  function update(change: (current: Editor) => Editor) {
    setEditor((current) => (current === null ? current : change(current)));
  }

  function chooseDate(localDate: string) {
    update((current) => ({
      ...current,
      draft: {
        ...current.draft,
        localDate,
        periods:
          current.draft.kind === 'OPEN' && !current.periodsTouched
            ? prefillCustomHours(localDate, config.recurringPeriods)
            : current.draft.periods,
      },
    }));
  }

  function chooseKind(kind: ExceptionKindChoice) {
    update((current) => ({
      ...current,
      draft: {
        ...current.draft,
        kind,
        periods:
          kind === 'OPEN' && (!current.periodsTouched || current.draft.periods.length === 0)
            ? current.draft.localDate === null
              ? current.draft.periods
              : prefillCustomHours(current.draft.localDate, config.recurringPeriods)
            : current.draft.periods,
      },
    }));
  }

  function changePeriods(periods: PeriodDraft[]) {
    update((current) => ({
      ...current,
      periodsTouched: true,
      draft: { ...current.draft, periods },
    }));
  }

  async function save(submittedDraft: ExceptionDraft) {
    const localDate = submittedDraft.localDate;
    if (busyRef.current || !isActive() || !saveEnabled || localDate === null) return;
    busyRef.current = true;
    setBusy('save');
    setErrorKey(null);
    const write = exceptionPayload(submittedDraft);
    try {
      const result = await setAvailabilityException(clinicId, localDate, write);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      if (
        read?.kind === 'loaded' &&
        exceptionMatches(exceptionFor(read.config.exceptions, localDate), write)
      ) {
        leave();
        return;
      }
      setErrorKey(mapAppointmentHoursSaveErrorToKey(result.error));
    } finally {
      busyRef.current = false;
      if (isActive()) setBusy(null);
    }
  }

  async function remove(localDate: string) {
    if (!isActive()) {
      busyRef.current = false;
      return;
    }
    setBusy('remove');
    setErrorKey(null);
    try {
      const result = await clearAvailabilityException(clinicId, localDate);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      if (read?.kind === 'loaded' && exceptionFor(read.config.exceptions, localDate) === null) {
        leave();
        return;
      }
      setErrorKey(mapAppointmentHoursSaveErrorToKey(result.error));
    } finally {
      busyRef.current = false;
      if (isActive()) setBusy(null);
    }
  }

  function confirmRemove(localDate: string, label: string) {
    if (busyRef.current || !isActive()) return;
    busyRef.current = true;
    const release = () => {
      busyRef.current = false;
    };
    Alert.alert(
      t('appointmentHours.removeDialogTitle'),
      t('appointmentHours.removeDialogMessage', { date: label }),
      [
        { text: t('appointmentHours.dialogCancel'), style: 'cancel', onPress: release },
        {
          text: t('appointmentHours.removeDialogConfirm'),
          style: 'destructive',
          onPress: () => {
            remove(localDate);
          },
        },
      ],
      { cancelable: true, onDismiss: release },
    );
  }

  const windowDates = exceptionDateWindow(windowStart);
  const earlierStart =
    windowStart > today
      ? (() => {
          const candidate = shiftLocalDate(windowStart, -EXCEPTION_DATE_WINDOW_DAYS);
          return candidate < today ? today : candidate;
        })()
      : null;

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
            {t(
              mode === 'edit'
                ? 'appointmentHours.exceptionTitleEdit'
                : 'appointmentHours.exceptionTitleNew',
            )}
          </Text>
          <Text style={styles.hint}>{t('appointmentHours.timezoneCaption', { timezone })}</Text>
        </View>
        <Text style={styles.hint}>{t('appointmentHours.exceptionIntro')}</Text>

        <View style={styles.section}>
          <Text style={styles.sectionTitle} accessibilityRole="header">
            {t('appointmentHours.exceptionDateLabel')}
          </Text>
          {mode === 'edit' && dateLabel !== null ? (
            <Text style={styles.value}>{dateLabel}</Text>
          ) : (
            <>
              <CandidateWindowNavigator
                label={t('candidatePicker.windowLabel', {
                  start: formatCandidateWindowDate(windowDates[0], locale),
                  end: formatCandidateWindowDate(windowDates[windowDates.length - 1], locale),
                })}
                earlierLabel={t('candidatePicker.earlierDates')}
                laterLabel={t('candidatePicker.laterDates')}
                onEarlier={
                  earlierStart === null
                    ? null
                    : () => update((current) => ({ ...current, windowStart: earlierStart }))
                }
                onLater={() =>
                  update((current) => ({
                    ...current,
                    windowStart: shiftLocalDate(current.windowStart, EXCEPTION_DATE_WINDOW_DAYS),
                  }))
                }
                disabled={busy !== null}
              />
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                style={styles.dateScroller}
                contentContainerStyle={styles.dateRow}
                accessibilityRole="radiogroup"
                accessibilityLabel={t('appointmentHours.exceptionDateLabel')}
              >
                {windowDates.map((localDate) => {
                  const { weekday, dayMonth } = formatCandidateDateParts(localDate, locale);
                  return (
                    <DateChip
                      key={localDate}
                      weekday={weekday}
                      dayMonth={dayMonth}
                      accessibilityLabel={formatCandidateDateLabel(localDate, locale)}
                      selected={localDate === draft.localDate}
                      disabled={busy !== null}
                      onPress={() => {
                        if (busy === null) chooseDate(localDate);
                      }}
                    />
                  );
                })}
              </ScrollView>
              {draft.localDate === null ? (
                <Text style={styles.hint}>{t('appointmentHours.exceptionDateRequired')}</Text>
              ) : (
                <Text style={styles.value}>{dateLabel}</Text>
              )}
              {stored !== null ? (
                <Notice tone="info" message={t('appointmentHours.exceptionReplacesExisting')} />
              ) : null}
            </>
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle} accessibilityRole="header">
            {t('appointmentHours.exceptionKindLabel')}
          </Text>
          <View
            style={styles.kinds}
            accessibilityRole="radiogroup"
            accessibilityLabel={t('appointmentHours.exceptionKindLabel')}
          >
            <ChoiceChip
              label={t('appointmentHours.exceptionKindClosed')}
              selected={draft.kind === 'CLOSED'}
              disabled={busy !== null}
              onPress={() => {
                if (busy === null) chooseKind('CLOSED');
              }}
            />
            <ChoiceChip
              label={t('appointmentHours.exceptionKindOpen')}
              selected={draft.kind === 'OPEN'}
              disabled={busy !== null}
              onPress={() => {
                if (busy === null) chooseKind('OPEN');
              }}
            />
          </View>
        </View>

        {draft.kind === 'OPEN' ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              {t('appointmentHours.exceptionPeriodsLabel')}
            </Text>
            {!periodsTouched && draft.localDate !== null ? (
              <Text style={styles.hint}>
                {t(
                  normallyClosed
                    ? 'appointmentHours.exceptionNormallyClosedHint'
                    : 'appointmentHours.exceptionPrefillHint',
                )}
              </Text>
            ) : null}
            <TimePeriodListEditor
              groupLabel={dateLabel ?? t('appointmentHours.exceptionPeriodsLabel')}
              periods={draft.periods}
              editable={busy === null}
              onChange={changePeriods}
            />
            {draft.periods.length === 0 ? (
              <Text style={styles.issue}>{t('appointmentHours.exceptionNoPeriods')}</Text>
            ) : null}
          </View>
        ) : null}

        {mode === 'edit' && dateLabel !== null ? (
          <View style={styles.section}>
            <Button
              variant="destructive"
              label={t('appointmentHours.removeException')}
              onPress={() => {
                if (draft.localDate !== null) confirmRemove(draft.localDate, dateLabel);
              }}
              loading={busy === 'remove'}
              disabled={busy !== null}
            />
            <Text style={styles.hint}>{t('appointmentHours.removeExceptionHint')}</Text>
          </View>
        ) : null}

        <Text style={styles.hint}>{t('appointmentHours.existingAppointmentsNote')}</Text>
      </ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
        {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
        <Button
          label={t('appointmentHours.save')}
          onPress={() => save(draft)}
          loading={busy === 'save'}
          disabled={!saveEnabled}
        />
      </View>
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
  titleBlock: {
    gap: spacing.xs,
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
  value: {
    ...typography.body,
    color: colors.textPrimary,
  },
  hint: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  issue: {
    ...typography.caption,
    color: colors.errorDark,
  },
  dateScroller: {
    marginHorizontal: -spacing.screenHorizontal,
  },
  dateRow: {
    gap: spacing.sm,
    paddingHorizontal: spacing.screenHorizontal,
  },
  kinds: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
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

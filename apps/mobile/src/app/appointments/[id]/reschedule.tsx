import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { CandidateDateTimePicker } from '@/components/design-system/candidate-date-time-picker';
import { CandidateWindowNavigator } from '@/components/design-system/candidate-window-navigator';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import {
  getPetAppointments,
  getRequestableAppointmentStartTimes,
  rescheduleRequestedAppointment,
  type PetAppointment,
  type RequestableCandidate,
} from '@/data/appointments';
import { mapAppointmentErrorToKey } from '@/i18n/appointment-error-messages';
import { useLocale } from '@/i18n/locale-provider';
import { canRescheduleRequestedAppointment } from '@/lib/appointment-lifecycle';
import {
  civilDateString,
  civilDateTimeInTimeZone,
  formatCandidateWindowDate,
  formatInstantInTimeZone,
  initialRequestableCandidateWindow,
  nextRequestableCandidateWindow,
  previousRequestableCandidateWindow,
  type RequestableCandidateWindow,
} from '@/lib/appointment-time';
import { appointmentDetailHref } from '@/lib/appointments-navigation';
import {
  candidateAfterDateChange,
  distinctSortedCandidateDates,
  preferredCandidateDate,
  rematchSelectedCandidate,
} from '@/lib/candidate-selection';
import { discardsPendingAlternativeTime } from '@/lib/requested-alternative-time';
import { canSubmitReschedule } from '@/lib/reschedule-selection';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'error' | 'notFound' | 'notEligible' | 'loaded';
type CandidatesLoadState = 'loading' | 'loaded' | 'error';

/**
 * REQUESTED-only reschedule (SPEC-APT-004). Always re-reads through
 * getPetAppointments(petId) rather than trusting navigation params, and
 * always re-reads again after a successful RPC rather than optimistically
 * replacing the interval.
 *
 * As of the Guardian requestable-times enhancement (SPEC-APT-004
 * BR-22/23/24), the Guardian no longer types a new start or end time, nor
 * picks a date from a native calendar widget: getRequestableAppointmentStartTimes
 * is queried for one window of the approved Guardian horizon at a time
 * (Clinic-local today + 0…29, then + 30…60 via "Later dates"; SPEC-APT-014
 * BR-11), and only the dates that window returned ≥1 candidate for are ever
 * offered as selectable — a date with zero candidates is unselectable by
 * omission. Changing window clears the selection; the latest read wins. If the
 * Appointment's current requested date is among the returned dates it is
 * preselected; otherwise the first available date is (the current date is
 * never forced to appear if the backend didn't return candidates for it). A
 * prior candidate read is advisory only; if the backend rejects the
 * reschedule because Availability or the Clinic's standard duration changed
 * meanwhile, the mapped product error is shown — this screen never
 * automatically retries the mutation. Window rules live in
 * lib/appointment-time.ts and selection rules in lib/candidate-selection.ts
 * (unit tested).
 *
 * If the Clinic has a pending alternative time for this request, the screen
 * warns that changing the requested time discards it (SPEC-APT-004 BR-28); the
 * Guardian's own reschedule stays allowed and is never an acceptance (BR-29).
 *
 * Every exit returns to this Appointment's detail with router.dismissTo —
 * never replace/push — so exactly one detail stays in the stack: it pops
 * back to the detail beneath (which re-reads on focus, showing the new
 * schedule), or replaces this screen with one if none is beneath. Back from
 * that detail then reaches this Pet's freshly loaded list; no stale
 * pre-reschedule detail is ever left behind.
 */
export default function RescheduleAppointmentScreen() {
  const { t, locale } = useLocale();
  const insets = useSafeAreaInsets();
  const { id, petId } = useLocalSearchParams<{ id: string; petId: string }>();

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [appointment, setAppointment] = useState<PetAppointment | null>(null);
  const [schedulingTimezoneName, setSchedulingTimezoneName] = useState<string | null>(null);
  const [candidateWindow, setCandidateWindow] = useState<RequestableCandidateWindow | null>(null);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [candidates, setCandidates] = useState<RequestableCandidate[]>([]);
  const [candidatesLoadState, setCandidatesLoadState] = useState<CandidatesLoadState>('loading');
  const [selectedCandidate, setSelectedCandidate] = useState<RequestableCandidate | null>(null);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submissionError, setSubmissionError] = useState<string | null>(null);

  const isMountedRef = useRef(true);
  const candidateRequestSeqRef = useRef(0);

  function backToDetail() {
    router.dismissTo(appointmentDetailHref(id, petId));
  }

  useEffect(() => {
    isMountedRef.current = true;

    getPetAppointments(petId).then((result) => {
      if (!isMountedRef.current) return;

      if (result.error !== null) {
        setLoadState('error');
        return;
      }

      const found = result.data.find((row) => row.id === id) ?? null;
      if (found === null) {
        setLoadState('notFound');
        return;
      }

      if (
        !canRescheduleRequestedAppointment(
          found.lifecycleState,
          found.currentScheduledStartAt,
          new Date(),
        ) ||
        !found.currentScheduledStartAt ||
        !found.currentSchedulingTimezoneName
      ) {
        setLoadState('notEligible');
        return;
      }

      setAppointment(found);
      setSchedulingTimezoneName(found.currentSchedulingTimezoneName);
      setCandidateWindow(initialRequestableCandidateWindow(found.currentSchedulingTimezoneName));
      setLoadState('loaded');
    });

    return () => {
      isMountedRef.current = false;
    };
  }, [id, petId]);

  // Loads the window on screen once (per window) rather than once per date
  // change. Latest-request-wins: a stale in-flight load must never overwrite
  // state for the Appointment or window currently displayed. On success the
  // date is the current requested date if offered, else the first.
  useEffect(() => {
    if (loadState !== 'loaded' || !appointment || !schedulingTimezoneName || !candidateWindow) {
      return;
    }

    const requestSeq = ++candidateRequestSeqRef.current;

    getRequestableAppointmentStartTimes(
      appointment.clinicId,
      candidateWindow.startDate,
      candidateWindow.endDate,
    ).then((result) => {
      if (!isMountedRef.current || requestSeq !== candidateRequestSeqRef.current) return;

      if (result.error !== null) {
        setCandidatesLoadState('error');
        setCandidates([]);
        return;
      }

      setCandidates(result.data);
      setCandidatesLoadState('loaded');

      const currentDate = appointment.currentScheduledStartAt
        ? civilDateString(
            civilDateTimeInTimeZone(appointment.currentScheduledStartAt, schedulingTimezoneName),
          )
        : null;
      setSelectedDate(preferredCandidateDate(result.data, currentDate));
      setSelectedCandidate((previous) => rematchSelectedCandidate(result.data, previous));
    });
  }, [appointment, candidateWindow, loadState, schedulingTimezoneName]);

  function handleWindowChange(window: RequestableCandidateWindow) {
    setCandidateWindow(window);
    setSelectedDate(null);
    setSelectedCandidate(null);
    setCandidates([]);
    setCandidatesLoadState('loading');
  }

  function handleDateChange(localDate: string) {
    setSelectedDate(localDate);
    setSelectedCandidate((previous) => candidateAfterDateChange(previous, localDate));
  }

  async function handleSubmit() {
    if (isSubmitting || !appointment || !selectedCandidate) return;

    setSubmissionError(null);
    setIsSubmitting(true);

    try {
      const rpcResult = await rescheduleRequestedAppointment(appointment.id, selectedCandidate);

      if (!isMountedRef.current) return;

      if (rpcResult.error !== null) {
        setSubmissionError(t(mapAppointmentErrorToKey(rpcResult.error)));
        return;
      }

      // Re-read authoritative server state: the detail re-reads
      // getPetAppointments + scheduling history whenever it regains focus.
      router.dismissTo(appointmentDetailHref(appointment.id, petId));
    } finally {
      if (isMountedRef.current) {
        setIsSubmitting(false);
      }
    }
  }

  if (
    loadState === 'loading' ||
    loadState === 'error' ||
    loadState === 'notFound' ||
    loadState === 'notEligible'
  ) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={backToDetail} />
          {loadState === 'loading' ? (
            <StateMessage tone="loading" message={t('appointments.detailLoading')} />
          ) : (
            <>
              <StateMessage
                tone="error"
                message={
                  loadState === 'notFound'
                    ? t('appointments.detailNotFound')
                    : loadState === 'notEligible'
                      ? t('appointmentErrors.lifecycleChanged')
                      : t('appointments.detailLoadError')
                }
              />
              <Button
                variant="secondary"
                label={t('appointmentReschedule.backToAppointment')}
                onPress={backToDetail}
              />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  if (!appointment || !appointment.currentScheduledStartAt) {
    return null;
  }

  const availableDates = distinctSortedCandidateDates(candidates);
  const timezoneName = appointment.currentSchedulingTimezoneName ?? 'UTC';
  const previousWindow =
    candidateWindow === null
      ? null
      : previousRequestableCandidateWindow(candidateWindow, timezoneName);
  const nextWindow =
    candidateWindow === null ? null : nextRequestableCandidateWindow(candidateWindow, timezoneName);
  const currentTime = formatInstantInTimeZone(
    appointment.currentScheduledStartAt,
    appointment.currentSchedulingTimezoneName ?? 'UTC',
  );

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppTopBar onBack={backToDetail} />

        <View style={styles.titleBlock}>
          <Text style={styles.title} accessibilityRole="header">
            {t('appointmentReschedule.title')}
          </Text>
          <View style={styles.currentRow}>
            <Ionicons
              name="time-outline"
              size={16}
              color={colors.textSecondary}
              accessibilityElementsHidden
              importantForAccessibility="no-hide-descendants"
            />
            <Text style={styles.currentText}>
              {`${t('appointmentReschedule.currentTimeLabel')}: ${currentTime}`}
            </Text>
          </View>
        </View>

        {discardsPendingAlternativeTime(appointment) ? (
          <Notice tone="info" message={t('appointmentReschedule.discardsAlternativeWarning')} />
        ) : null}

        {candidateWindow !== null ? (
          <CandidateWindowNavigator
            label={t('candidatePicker.windowLabel', {
              start: formatCandidateWindowDate(candidateWindow.startDate, locale),
              end: formatCandidateWindowDate(candidateWindow.endDate, locale),
            })}
            earlierLabel={t('candidatePicker.earlierDates')}
            laterLabel={t('candidatePicker.laterDates')}
            onEarlier={previousWindow !== null ? () => handleWindowChange(previousWindow) : null}
            onLater={nextWindow !== null ? () => handleWindowChange(nextWindow) : null}
            disabled={isSubmitting}
          />
        ) : null}

        {candidatesLoadState === 'loading' ? (
          <StateMessage tone="loading" message={t('appointmentRequest.loadingCandidates')} />
        ) : candidatesLoadState === 'error' ? (
          <StateMessage tone="error" message={t('appointmentRequest.candidatesLoadError')} />
        ) : availableDates.length === 0 ? (
          <StateMessage
            tone="empty"
            icon="calendar-outline"
            message={t('appointmentRequest.noRequestableDatesError')}
          />
        ) : (
          <CandidateDateTimePicker
            candidates={candidates}
            selectedDate={selectedDate}
            selectedCandidate={selectedCandidate}
            onSelectDate={handleDateChange}
            onSelectCandidate={setSelectedCandidate}
            dateLabel={t('appointmentReschedule.dateLabel')}
            timeLabel={t('appointmentRequest.candidateListLabel')}
            locale={locale}
          />
        )}
      </ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
        {submissionError ? <Notice tone="error" message={submissionError} /> : null}
        <Button
          label={t('appointmentReschedule.submitAction')}
          onPress={handleSubmit}
          loading={isSubmitting}
          disabled={!canSubmitReschedule(selectedCandidate)}
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
    gap: spacing.sm,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  currentRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  currentText: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
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

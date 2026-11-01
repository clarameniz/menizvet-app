import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { CandidateDateTimePicker } from '@/components/design-system/candidate-date-time-picker';
import { CandidateWindowNavigator } from '@/components/design-system/candidate-window-navigator';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import {
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import {
  getAppointmentRescheduleCandidates,
  proposeClinicReschedule,
  type RescheduleCandidate,
} from '@/data/professional-appointment-reschedule';
import { getMyProfessionalClinics } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  mapProfessionalRescheduleErrorToKey,
  mapRescheduleCandidatesErrorToKey,
} from '@/i18n/professional-reschedule-error-messages';
import {
  mapClinicScheduleErrorToKey,
  mapProfessionalClinicsErrorToKey,
} from '@/i18n/professional-context-error-messages';
import {
  canSubmitClinicRescheduleProposal,
  clinicRescheduleProposalRequestFor,
  currentRescheduleCandidateWindow,
  classifyRescheduleAppointment,
  hasActionableClinicProposal,
  isClinicRescheduleReasonComplete,
  nextRescheduleCandidateWindow,
  parseReviewedSequence,
  previousRescheduleCandidateWindow,
  rescheduleCandidateStartIso,
  type RescheduleCandidateWindow,
} from '@/lib/appointment-reschedule';
import {
  clinicLocalToday,
  formatCandidateWindowDate,
  formatScheduledInterval,
} from '@/lib/appointment-time';
import {
  candidateAfterDateChange,
  distinctSortedCandidateDates,
  preferredCandidateDate,
  rematchSelectedCandidate,
} from '@/lib/candidate-selection';
import {
  professionalAppointmentDetailHref,
  resolveClinicScheduleAvailability,
} from '@/lib/clinic-schedule-display';
import { appointmentManagementStatusFor } from '@/lib/appointment-management';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** The Clinic is no longer a Professional Clinic offering the schedule. */
  | { kind: 'accessLost' }
  /** The Appointment can't be read in this Clinic (unknown, another Clinic's, or access lost). */
  | { kind: 'appointmentMissing' }
  /** The Appointment is no longer the confirmed context reviewed on the detail. */
  | { kind: 'changed' }
  /**
   * The Appointment is still the reviewed one, but a proposal is no longer
   * offered (a proposal now exists, the start passed, capability lost, …).
   */
  | { kind: 'notOffered' }
  /**
   * Still proposable, but the Organization's APPOINTMENT_MANAGEMENT is known to
   * be missing (SPEC-APT-012 BR-61): no form, no candidate read.
   */
  | { kind: 'entitlementUnavailable' }
  /** Still proposable, but that Entitlement could not be verified: retryable. */
  | { kind: 'entitlementUnverified'; messageKey: TranslationKey }
  | { kind: 'loaded'; appointment: ClinicScheduleAppointment };

/**
 * What one Appointment re-read found, before it is applied to the screen: the
 * screen state it implies and the fresh row, if any. Reading and applying are
 * separate so the submit path can decide to leave without first re-rendering
 * this screen into another branch.
 */
type AppointmentRead = {
  state: Exclude<LoadState, { kind: 'loading' }>;
  appointment: ClinicScheduleAppointment | null;
};

type CandidatesState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'loaded'; candidates: RescheduleCandidate[] };

/**
 * Clinic proposal of a new time for a CONFIRMED Appointment (SPEC-APT-005),
 * reached from the professional Appointment detail. The route carries the
 * Clinic id, the Appointment id, and the confirmed revision sequence of the row
 * the detail displayed — the context the actor reviewed.
 *
 * On mount it re-reads the Professional Clinics and this Appointment (SPEC-APT-012 BR-52)
 * (nothing displayed is trusted from navigation). If the Appointment is no
 * longer that same CONFIRMED revision, or no longer offers a proposal, the
 * screen stops and sends the actor back to review it: a proposal is never made
 * against a context nobody looked at (BR-26).
 *
 * Candidate starts come only from get_appointment_reschedule_candidate_start_times
 * (SPEC-APT-017), read for one window of 60 Clinic-local calendar dates at a
 * time (within the backend's per-request span). The first window starts on
 * Clinic-local today; "Later dates" reads the next consecutive window and
 * "Earlier dates" the previous one, never before today, with no overall
 * horizon. Changing window clears the selection; the latest read wins. Each
 * candidate carries the end the proposal will store, so the screen never
 * computes a duration. The actor picks a start, writes the required reason
 * (visible to the Pet's Guardians, BR-30), and confirms a dialog showing current
 * versus proposed.
 *
 * Exactly one submission is in flight; it is never retried. On success the
 * screen returns to the detail, which re-reads and shows the pending proposal.
 *
 * Leaving is terminal and has a single owner (`leaveToDetail`): once the
 * screen navigates away it never updates its own state again — no
 * `setSubmitting(false)`, no branch change, no late candidate or focus read.
 * React Native's Fabric renderer (with react-native-screens) moves a popped
 * screen's native views for the exit transition; inserting a new native child
 * into that subtree then (for example the Button swapping its spinner back to
 * its label) fails with "The specified child already has a parent". The
 * confirmation is a native Alert, already closed when its button handler runs,
 * so it is out of the tree before any of this happens.
 * On any failure the Appointment is re-read and decides: if it now shows an
 * actionable Clinic proposal (for example the response was lost after the
 * server committed), the screen returns to the detail without reporting a
 * failure; a stale outcome switches the screen to "changed"; otherwise the
 * mapped error is shown with fresh candidates.
 */
export default function ProfessionalRescheduleScreen() {
  const { t, locale } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId, appointmentId, sequence } = useLocalSearchParams<{
    clinicId: string;
    appointmentId: string;
    sequence: string;
  }>();
  const reviewedSequence = parseReviewedSequence(sequence);

  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' });
  const [candidatesState, setCandidatesState] = useState<CandidatesState>({ kind: 'loading' });
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [selectedCandidate, setSelectedCandidate] = useState<RescheduleCandidate | null>(null);
  const [reason, setReason] = useState('');
  // Whether the reason was edited: a blank reason is flagged only after that.
  const [reasonTouched, setReasonTouched] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submissionErrorKey, setSubmissionErrorKey] = useState<TranslationKey | null>(null);

  const [candidateWindow, setCandidateWindow] = useState<RescheduleCandidateWindow | null>(null);

  const isMountedRef = useRef(true);
  // Set once the screen has started leaving: from then on nothing may update it.
  const leavingRef = useRef(false);
  const loadSeqRef = useRef(0);
  const candidatesSeqRef = useRef(0);
  // The window on screen, readable from the focus callback without
  // re-creating it.
  const windowRef = useRef<RescheduleCandidateWindow | null>(null);
  // A dialog is open or the proposal is in flight; a ref, so a second tap in
  // the same frame can't open another dialog or submit twice.
  const busyRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  // The single owner of leaving this screen. Terminal: see the doc comment.
  const leaveToDetail = useCallback(() => {
    if (leavingRef.current) return;
    leavingRef.current = true;
    router.dismissTo(professionalAppointmentDetailHref(clinicId, appointmentId));
  }, [clinicId, appointmentId]);

  /** Whether async work may still update this screen. */
  const isActive = () => isMountedRef.current && !leavingRef.current;

  // Re-reads the Clinic and the Appointment WITHOUT changing the screen. Resolves
  // to `null` when superseded by a later read or once the screen is leaving.
  const readAppointment = useCallback(async (): Promise<AppointmentRead | null> => {
    const seq = ++loadSeqRef.current;
    const isCurrent = () =>
      isMountedRef.current && !leavingRef.current && seq === loadSeqRef.current;

    // The Organization's Entitlements come only from the context read, related
    // to this Clinic by Organization id (SPEC-ORG-008 BR-11).
    const [clinicsResult, contextResult] = await Promise.all([
      getMyProfessionalClinics(),
      getMyProfessionalContext(),
    ]);
    if (!isCurrent()) return null;
    if (clinicsResult.error !== null) {
      return {
        state: { kind: 'error', messageKey: mapProfessionalClinicsErrorToKey(clinicsResult.error) },
        appointment: null,
      };
    }
    const availability = resolveClinicScheduleAvailability(clinicsResult.data, clinicId);
    if (availability.kind !== 'available') {
      return { state: { kind: 'accessLost' }, appointment: null };
    }

    // Only this Appointment is read (SPEC-APT-012 BR-52); its uniform denial
    // reads as a missing Appointment.
    const appointmentResult = await getClinicAppointment(
      availability.clinic.clinicId,
      appointmentId,
    );
    if (!isCurrent()) return null;
    if (appointmentResult.error !== null) {
      return {
        state: { kind: 'error', messageKey: mapClinicScheduleErrorToKey(appointmentResult.error) },
        appointment: null,
      };
    }

    const appointment = appointmentResult.data;
    const management = appointmentManagementStatusFor(
      contextResult,
      availability.clinic.organizationId,
    );
    const classification = classifyRescheduleAppointment(
      availability.clinic,
      appointment,
      reviewedSequence,
      new Date(),
      management,
    );
    if (classification === 'proposable' && appointment !== null) {
      return { state: { kind: 'loaded', appointment }, appointment };
    }
    if (classification === 'entitlementUnverified') {
      return {
        state: {
          kind: 'entitlementUnverified',
          messageKey:
            management.kind === 'unknown' ? management.messageKey : 'professional.loadError',
        },
        appointment,
      };
    }
    return {
      state: { kind: classification === 'proposable' ? 'appointmentMissing' : classification },
      appointment,
    };
  }, [clinicId, appointmentId, reviewedSequence]);

  // Reads one window of candidates; only the latest read updates the screen.
  const loadCandidates = useCallback(
    async (appointment: ClinicScheduleAppointment, window: RescheduleCandidateWindow) => {
      const seq = ++candidatesSeqRef.current;
      setCandidatesState({ kind: 'loading' });
      const result = await getAppointmentRescheduleCandidates(
        appointment.id,
        window.startDate,
        window.endDate,
      );
      if (!isMountedRef.current || leavingRef.current || seq !== candidatesSeqRef.current) return;
      if (result.error !== null) {
        // A read failure, never a submission failure: nothing was sent.
        setCandidatesState({
          kind: 'error',
          messageKey: mapRescheduleCandidatesErrorToKey(result.error),
        });
        return;
      }
      const candidates = result.data;
      setCandidatesState({ kind: 'loaded', candidates });
      // Keep the date and time the actor chose while the fresh read still
      // offers them; otherwise show the first date that has times.
      setSelectedDate((previous) => preferredCandidateDate(candidates, previous));
      setSelectedCandidate((previous) => rematchSelectedCandidate(candidates, previous));
    },
    [],
  );

  // Re-reads the Appointment, then the candidates of the window on screen
  // (or the first window once the Clinic-local date moved past it).
  const refresh = useCallback(async () => {
    const read = await readAppointment();
    if (read === null) return;
    setLoadState(read.state);
    if (read.state.kind !== 'loaded') return;
    const window = currentRescheduleCandidateWindow(
      windowRef.current,
      read.state.appointment.currentSchedulingTimezoneName,
    );
    if (windowRef.current === null || windowRef.current.startDate !== window.startDate) {
      setSelectedCandidate(null);
    }
    windowRef.current = window;
    setCandidateWindow(window);
    await loadCandidates(read.state.appointment, window);
  }, [readAppointment, loadCandidates]);

  // Like the detail screen, every focus re-reads authoritative state.
  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  function handleWindowChange(
    appointment: ClinicScheduleAppointment,
    window: RescheduleCandidateWindow,
  ) {
    windowRef.current = window;
    setCandidateWindow(window);
    setSelectedDate(null);
    setSelectedCandidate(null);
    loadCandidates(appointment, window);
  }

  function handleDateChange(localDate: string) {
    setSelectedDate(localDate);
    setSelectedCandidate((previous) => candidateAfterDateChange(previous, localDate));
  }

  async function submit(appointment: ClinicScheduleAppointment, candidate: RescheduleCandidate) {
    setSubmitting(true);
    setSubmissionErrorKey(null);
    try {
      // The row the actor reviewed — never a newer read (SPEC-APT-005 BR-26).
      const result = await proposeClinicReschedule(
        clinicRescheduleProposalRequestFor(appointment, candidate, reason),
      );
      if (!isActive()) return;
      if (result.error === null) {
        // Leave without touching this screen again; the detail re-reads the
        // authoritative state (with the pending proposal) when it regains focus.
        leaveToDetail();
        return;
      }
      // The authoritative state decides; the proposal is never retried. Read
      // first, apply only if staying, so leaving never follows a branch change.
      const read = await readAppointment();
      if (!isActive()) return;
      if (read !== null && hasActionableClinicProposal(read.appointment)) {
        // The server holds a Clinic proposal (e.g. the response was lost after
        // it committed): effectively done — the detail shows it.
        leaveToDetail();
        return;
      }
      setSelectedCandidate(null);
      setSubmissionErrorKey(mapProfessionalRescheduleErrorToKey(result.error));
      if (read === null) return;
      setLoadState(read.state);
      // A time that became unavailable disappears from the fresh candidates.
      if (read.state.kind === 'loaded' && windowRef.current !== null) {
        await loadCandidates(read.state.appointment, windowRef.current);
      }
    } finally {
      busyRef.current = false;
      // Never after leaving: the screen's native views are being torn down.
      if (isActive()) setSubmitting(false);
    }
  }

  // Client-side UX guard only: whether every required input of the proposal
  // form is complete and nothing is loading or submitting. Leaving needs no
  // render-time check: once leaving, this screen never renders again, and the
  // press handler checks it.
  const submitEnabled = canSubmitClinicRescheduleProposal({
    proposable: loadState.kind === 'loaded',
    candidates: candidatesState.kind === 'loaded' ? candidatesState.candidates : null,
    selectedCandidate,
    reason,
    busy: submitting,
  });

  function handleSubmit(appointment: ClinicScheduleAppointment) {
    // The button is already disabled unless the form is complete; this guard
    // also covers a tap racing a state change. The backend revalidates all.
    if (busyRef.current || leavingRef.current || selectedCandidate === null || !submitEnabled) {
      return;
    }
    const candidate = selectedCandidate;
    const current = formatScheduledInterval(
      appointment.currentScheduledStartAt,
      appointment.currentScheduledEndAt,
      appointment.currentSchedulingTimezoneName,
      locale,
    );
    const proposed = formatScheduledInterval(
      rescheduleCandidateStartIso(candidate),
      candidate.endAt,
      appointment.currentSchedulingTimezoneName,
      locale,
    );

    busyRef.current = true;
    setSubmissionErrorKey(null);
    const release = () => {
      busyRef.current = false;
    };
    Alert.alert(
      t('professionalReschedule.dialogTitle'),
      t('professionalReschedule.dialogMessage', {
        petName: appointment.petName,
        current: `${current.date}, ${current.time}`,
        proposed: `${proposed.date}, ${proposed.time}`,
      }),
      [
        { text: t('professionalReschedule.dialogCancel'), style: 'cancel', onPress: release },
        {
          text: t('professionalReschedule.dialogConfirm'),
          onPress: () => {
            submit(appointment, candidate);
          },
        },
      ],
      { cancelable: true, onDismiss: release },
    );
  }

  function retryVerification() {
    setLoadState({ kind: 'loading' });
    refresh();
  }

  if (loadState.kind !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={leaveToDetail} />
          {loadState.kind === 'loading' ? (
            <StateMessage tone="loading" message={t('professionalAppointment.loading')} />
          ) : (
            <>
              {submissionErrorKey !== null ? (
                <Notice tone="error" message={t(submissionErrorKey)} />
              ) : null}
              <StateMessage
                tone={loadState.kind === 'error' ? 'error' : 'empty'}
                icon="calendar-outline"
                message={
                  loadState.kind === 'error'
                    ? t(loadState.messageKey)
                    : loadState.kind === 'changed'
                      ? t('professionalReschedule.contextChanged')
                      : loadState.kind === 'notOffered'
                        ? t('professionalReschedule.notAvailable')
                        : loadState.kind === 'entitlementUnavailable'
                          ? t('appointmentManagement.unavailable')
                          : loadState.kind === 'entitlementUnverified'
                            ? t(
                                loadState.messageKey === 'errors.sessionExpired'
                                  ? 'errors.sessionExpired'
                                  : 'appointmentManagement.unverified',
                              )
                            : loadState.kind === 'appointmentMissing'
                              ? t('professionalAppointment.notFound')
                              : t('clinicSchedule.accessError')
                }
              />
              {loadState.kind === 'entitlementUnverified' ? (
                <Button
                  label={t('professional.retry')}
                  accessibilityLabel={t('appointmentManagement.retryLabel')}
                  onPress={retryVerification}
                />
              ) : null}
              <Button
                variant="secondary"
                label={t('professionalReschedule.backToAppointment')}
                onPress={leaveToDetail}
              />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  const { appointment } = loadState;
  const current = formatScheduledInterval(
    appointment.currentScheduledStartAt,
    appointment.currentScheduledEndAt,
    appointment.currentSchedulingTimezoneName,
    locale,
  );
  const selectedInterval =
    selectedCandidate === null
      ? null
      : formatScheduledInterval(
          rescheduleCandidateStartIso(selectedCandidate),
          selectedCandidate.endAt,
          appointment.currentSchedulingTimezoneName,
          locale,
        );
  const dates =
    candidatesState.kind === 'loaded'
      ? distinctSortedCandidateDates(candidatesState.candidates)
      : [];
  const previousWindow =
    candidateWindow === null
      ? null
      : previousRescheduleCandidateWindow(
          candidateWindow,
          clinicLocalToday(appointment.currentSchedulingTimezoneName),
        );

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <AppTopBar onBack={leaveToDetail} />

        <View style={styles.titleBlock}>
          <Text style={styles.title} accessibilityRole="header">
            {t('professionalReschedule.title')}
          </Text>
          <Text style={styles.petName}>{appointment.petName}</Text>
        </View>

        <View
          style={styles.intervalCard}
          accessible
          accessibilityLabel={`${t('professionalReschedule.currentLabel')}: ${current.date}, ${current.time}`}
        >
          <Text style={styles.intervalLabel}>{t('professionalReschedule.currentLabel')}</Text>
          <Text style={styles.intervalValue}>{current.date}</Text>
          <Text style={styles.intervalValue}>{current.time}</Text>
          <Text style={styles.hint}>{t('professionalReschedule.durationHint')}</Text>
        </View>

        {candidateWindow !== null ? (
          // No horizon: "Later dates" is always offered (SPEC-APT-017 BR-4).
          <CandidateWindowNavigator
            label={t('candidatePicker.windowLabel', {
              start: formatCandidateWindowDate(candidateWindow.startDate, locale),
              end: formatCandidateWindowDate(candidateWindow.endDate, locale),
            })}
            earlierLabel={t('candidatePicker.earlierDates')}
            laterLabel={t('candidatePicker.laterDates')}
            onEarlier={
              previousWindow !== null ? () => handleWindowChange(appointment, previousWindow) : null
            }
            onLater={() =>
              handleWindowChange(appointment, nextRescheduleCandidateWindow(candidateWindow))
            }
            disabled={submitting}
          />
        ) : null}

        {candidatesState.kind === 'loading' ? (
          <StateMessage tone="loading" message={t('professionalReschedule.loadingCandidates')} />
        ) : candidatesState.kind === 'error' ? (
          <View style={styles.section}>
            <StateMessage tone="error" message={t(candidatesState.messageKey)} />
            <Button variant="secondary" label={t('professional.retry')} onPress={() => refresh()} />
          </View>
        ) : dates.length === 0 ? (
          <StateMessage
            tone="empty"
            icon="calendar-outline"
            message={t('professionalReschedule.noCandidates')}
          />
        ) : (
          <>
            <CandidateDateTimePicker
              candidates={candidatesState.candidates}
              selectedDate={selectedDate}
              selectedCandidate={selectedCandidate}
              onSelectDate={handleDateChange}
              onSelectCandidate={setSelectedCandidate}
              dateLabel={t('professionalReschedule.dateLabel')}
              timeLabel={t('professionalReschedule.timeListLabel')}
              locale={locale}
            />

            {selectedInterval !== null ? (
              <View
                style={styles.intervalCard}
                accessible
                accessibilityLabel={`${t('professionalReschedule.proposedLabel')}: ${selectedInterval.date}, ${selectedInterval.time}`}
              >
                <Text style={styles.intervalLabel}>
                  {t('professionalReschedule.proposedLabel')}
                </Text>
                <Text style={styles.intervalValue}>{selectedInterval.date}</Text>
                <Text style={styles.intervalValue}>{selectedInterval.time}</Text>
              </View>
            ) : null}

            <View style={styles.reasonField}>
              <Input
                label={t('professionalReschedule.reasonLabel')}
                accessibilityLabel={t('professionalReschedule.reasonAccessibilityLabel')}
                required
                multiline
                value={reason}
                onChangeText={(text) => {
                  setReason(text);
                  setReasonTouched(true);
                }}
                editable={!submitting}
                error={
                  reasonTouched && !isClinicRescheduleReasonComplete(reason)
                    ? t('professionalReschedule.reasonMissing')
                    : undefined
                }
              />
              {/* Informational, not an error: plain text that screen readers
                  read right after the field (SPEC-APT-005 BR-30). */}
              <Text style={styles.hint}>{t('professionalReschedule.reasonVisibilityHint')}</Text>
            </View>
          </>
        )}
      </ScrollView>

      {candidatesState.kind === 'loaded' && dates.length > 0 ? (
        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {submissionErrorKey !== null ? (
            <Notice tone="error" message={t(submissionErrorKey)} />
          ) : null}
          {/* Says up front what the disabled button is waiting for. */}
          {selectedCandidate === null ? (
            <View style={styles.selectionHint}>
              <Ionicons
                name="information-circle-outline"
                size={16}
                color={colors.textSecondary}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.hint}>{t('professionalReschedule.selectTimeHint')}</Text>
            </View>
          ) : null}
          <Button
            label={t('professionalReschedule.submit')}
            onPress={() => handleSubmit(appointment)}
            loading={submitting}
            disabled={!submitEnabled}
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
  titleBlock: {
    gap: spacing.xs,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  petName: {
    ...typography.bodyStrong,
    color: colors.textSecondary,
  },
  intervalCard: {
    gap: 2,
    padding: spacing.md,
    borderRadius: radius.medium,
    backgroundColor: colors.surfaceSoft,
  },
  intervalLabel: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  intervalValue: {
    ...typography.body,
    color: colors.textPrimary,
  },
  hint: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  section: {
    gap: spacing.md,
  },
  reasonField: {
    gap: spacing.xs,
  },
  selectionHint: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
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

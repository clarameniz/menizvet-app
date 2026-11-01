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
import { AccessibilityInfo, Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { AppointmentStatusBadge } from '@/components/design-system/appointment-status-badge';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import {
  acceptRequestedAlternativeTime,
  acceptRescheduleProposal,
  cancelAppointment,
  getAppointmentSchedulingHistory,
  getAppointmentVeterinarianAssignmentHistory,
  getPetAppointments,
  withdrawAppointmentMedicalAccess,
  type AppointmentScheduleHistoryEntry,
  type AppointmentVeterinarianAssignmentHistoryEntry,
  type PendingReschedule,
  type PetAppointment,
} from '@/data/appointments';
import { getPublishedClinicProfilesByIds } from '@/data/clinics';
import { mapAppointmentErrorToKey } from '@/i18n/appointment-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { mapAlternativeTimeAcceptanceErrorToKey } from '@/i18n/requested-alternative-time-error-messages';
import { mapRescheduleAcceptanceErrorToKey } from '@/i18n/reschedule-acceptance-error-messages';
import {
  canRescheduleRequestedAppointment,
  guardianCancellationPresentation,
  guardianCancellationView,
  lifecycleLabelKey,
  shownCancellationReason,
  showsVeterinarianAssigned,
} from '@/lib/appointment-lifecycle';
import {
  offersRescheduleAcceptance,
  showsRescheduleNotCurrentlyAcceptable,
  wasRescheduleProposalApplied,
} from '@/lib/appointment-reschedule';
import {
  medicalAccessConsequenceKeys,
  medicalAccessView,
  medicalAccessWithdrawalNotice,
  type MedicalAccessNotice,
} from '@/lib/appointment-medical-access';
import { formatInstantInTimeZone, formatScheduledInterval } from '@/lib/appointment-time';
import { appointmentsListHref } from '@/lib/appointments-navigation';
import {
  isAwaitingClinicConfirmationOfAcceptedAlternative,
  offersAlternativeTimeAcceptance,
  showsAlternativeTimeNotCurrentlyAcceptable,
  wasAlternativeTimeAccepted,
  type PendingAlternativeTime,
} from '@/lib/requested-alternative-time';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'error' | 'notFound' | 'loaded';

/** Outcome of the latest reschedule acceptance, shown above the proposal. */
type AcceptanceNotice = { tone: 'info' | 'error'; messageKey: TranslationKey };

/**
 * Guardian Appointment detail (SPEC-APT-011). Besides cancellation and the
 * REQUESTED-only reschedule, it shows an actionable pending reschedule
 * proposal (BR-32) — current versus exactly the stored proposed interval, and
 * the Clinic's reason — and lets a current Guardian accept a Clinic proposal
 * (SPEC-APT-006). Acceptance is confirmed in a dialog, never retried, and
 * always followed by a fresh read; if a failed attempt turns out to have been
 * applied already (a lost response), the authoritative accepted state is
 * presented calmly. Doing nothing keeps the confirmed time. A Guardian-
 * originated proposal is shown read-only (Clinic acceptance is a professional
 * workflow), and there is no reject, counterproposal, or Guardian withdrawal.
 *
 * For a REQUESTED Appointment, a Clinic alternative time (SPEC-APT-019 §5) is
 * shown beside the current requested time, with the Clinic's reason, the
 * statement that accepting changes the request but the Clinic still has to
 * confirm it, and the response deadline (the current requested start, after
 * which the request may expire). Acceptance never confirms the Appointment;
 * afterwards the request shows "awaiting confirmation from the clinic"
 * (SPEC-APT-011 BR-33) and nothing implies it is confirmed.
 *
 * Medical access (SPEC-ACC-002 §16, SPEC-APT-011 BR-35): while the read says
 * ACTIVE — in any lifecycle, including COMPLETED — the card shows the active
 * status and a secondary "Manage medical access". Withdrawal is exceptional and
 * irreversible for the Appointment, so it lives in that inline panel, with its
 * consequences for the lifecycle shown, and runs only after a short final
 * confirmation. Only the Appointment id is sent; the Appointment itself stays.
 * The outcome is always followed by a fresh read, which decides what is shown:
 * REVOKED becomes a calm "Medical access withdrawn" state, so a retry after an
 * uncertain response is never an error.
 */
export default function AppointmentDetailScreen() {
  const { t, locale } = useLocale();
  const insets = useSafeAreaInsets();
  const { id, petId } = useLocalSearchParams<{ id: string; petId: string }>();

  /**
   * Back to *this Pet's* list, never pet selection: `/appointments?petId=…`.
   * `dismissTo`, not `back()`/`replace()`: if the list is already beneath
   * this screen it pops back to that same instance (no stale duplicate left
   * in the stack) and hands it the petId; if not — push/deep-link entry,
   * pushed straight over home — it replaces this screen with the list. The
   * list re-reads on focus either way, so a cancellation/reschedule made
   * here is never shown stale, and it re-validates petId against the
   * Guardian's Pets.
   */
  function backToList() {
    router.dismissTo(appointmentsListHref(petId));
  }

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [appointment, setAppointment] = useState<PetAppointment | null>(null);
  const [clinicName, setClinicName] = useState<string | null>(null);
  const [schedulingHistory, setSchedulingHistory] = useState<AppointmentScheduleHistoryEntry[]>([]);
  const [assignmentHistory, setAssignmentHistory] = useState<
    AppointmentVeterinarianAssignmentHistoryEntry[]
  >([]);

  const [isCancelConfirming, setIsCancelConfirming] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [isCancelling, setIsCancelling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  // The confirmed start for which the backend rejected a Guardian cancellation
  // because it had been reached (SPEC-APT-003 BR-31), so Cancel stays closed
  // even if the device clock is behind.
  const [cancellationClosedForStart, setCancellationClosedForStart] = useState<string | null>(null);

  const [isAccepting, setIsAccepting] = useState(false);
  const [acceptanceNotice, setAcceptanceNotice] = useState<AcceptanceNotice | null>(null);
  // The acceptance dialog is open or the acceptance is in flight; a ref, so a
  // second tap in the same frame can't open another dialog or submit twice.
  const acceptBusyRef = useRef(false);

  // The "Manage medical access" panel is open (SPEC-ACC-002 §16). Opening it
  // calls nothing; a read showing the access is no longer ACTIVE closes it.
  const [isManagingAccess, setIsManagingAccess] = useState(false);
  const [isWithdrawing, setIsWithdrawing] = useState(false);
  const [withdrawalNotice, setWithdrawalNotice] = useState<MedicalAccessNotice | null>(null);
  // The withdrawal dialog is open or the withdrawal is in flight; a ref, so a
  // second tap in the same frame can't open another dialog or submit twice.
  const withdrawBusyRef = useRef(false);

  const isMountedRef = useRef(true);
  // Whether an Appointment is already on screen. A ref, not the `appointment`
  // state, because `load()` is also invoked from the focus callback, whose
  // closure would otherwise see the first render's `null` forever.
  const hasAppointmentRef = useRef(false);

  /**
   * Always re-reads through getPetAppointments(petId) and locates the
   * requested Appointment by id — this screen never trusts a display value
   * passed via navigation params, only the petId used to reach the
   * authoritative Guardian-scoped read (SPEC-APT-011). Resolves to the
   * Appointment it read, or `null` when none was read.
   */
  async function load(): Promise<PetAppointment | null> {
    const [appointmentsResult, historyResult, assignmentResult] = await Promise.all([
      getPetAppointments(petId),
      getAppointmentSchedulingHistory(id),
      getAppointmentVeterinarianAssignmentHistory(id),
    ]);

    if (!isMountedRef.current) return null;

    if (appointmentsResult.error !== null) {
      // Only the initial load (no Appointment on screen yet) may show the
      // fatal "couldn't load" screen. `load()` is also used to re-read
      // authoritative state after a mutation (e.g. cancelAppointment) — if
      // that refresh fails (dropped connection), the Appointment detail
      // already rendered must not be discarded; the mutation's own error
      // (cancelError) already tells the Guardian the action didn't go
      // through, and the detail stays re-readable once connectivity returns.
      if (!hasAppointmentRef.current) {
        setLoadState('error');
      }
      return null;
    }

    const found = appointmentsResult.data.find((row) => row.id === id) ?? null;
    if (found === null) {
      setLoadState('notFound');
      return null;
    }

    hasAppointmentRef.current = true;
    if (found.medicalAccessState !== 'ACTIVE') setIsManagingAccess(false);
    setAppointment(found);
    setSchedulingHistory(historyResult.data ?? []);
    setAssignmentHistory(assignmentResult.data ?? []);

    const clinicsResult = await getPublishedClinicProfilesByIds([found.clinicId]);
    if (!isMountedRef.current) return found;
    setClinicName(clinicsResult.data?.get(found.clinicId)?.displayName ?? null);

    setLoadState('loaded');
    return found;
  }

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  // Re-reads on every focus, not just on mount: Reschedule returns here with
  // router.dismissTo (popping back to this same instance after a successful
  // save), so the new schedule must be read fresh rather than shown stale.
  // `load` only calls setState after its first `await` (never
  // synchronously); it is a named, reusable function because
  // handleConfirmCancel below also calls it after a mutation.
  useFocusEffect(
    useCallback(() => {
      load();
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [id, petId]),
  );

  async function handleConfirmCancel() {
    if (isCancelling) return;

    setIsCancelling(true);
    setCancelError(null);

    try {
      const result = await cancelAppointment(id, cancelReason.trim() || null);

      if (!isMountedRef.current) return;

      if (result.error !== null) {
        const errorKey = mapAppointmentErrorToKey(result.error);
        if (errorKey === 'appointmentErrors.confirmedStartReachedCancel' && appointment !== null) {
          // SPEC-APT-003 BR-31: the backend closed cancellation for this
          // confirmed start; the panel closes and the status note explains.
          setCancellationClosedForStart(appointment.currentScheduledStartAt);
          setIsCancelConfirming(false);
          setCancelReason('');
        } else {
          setCancelError(t(errorKey));
        }
        // A lifecycle-changed conflict (or any other outcome) is resolved by
        // re-reading authoritative state, never by retrying the mutation.
        await load();
        return;
      }

      setIsCancelConfirming(false);
      setCancelReason('');
      // Re-read authoritative server state rather than optimistically
      // marking the Appointment CANCELLED locally.
      await load();
    } finally {
      if (isMountedRef.current) {
        setIsCancelling(false);
      }
    }
  }

  async function acceptProposal(proposal: PendingReschedule) {
    setIsAccepting(true);
    setAcceptanceNotice(null);
    try {
      const result = await acceptRescheduleProposal(proposal.proposalId);
      if (!isMountedRef.current) return;
      // Always re-read: the authoritative state decides what is shown.
      const refreshed = await load();
      if (!isMountedRef.current) return;
      if (result.error === null) {
        setAcceptanceNotice({ tone: 'info', messageKey: 'rescheduleProposal.accepted' });
      } else if (refreshed !== null && wasRescheduleProposalApplied(proposal, refreshed)) {
        // An earlier attempt already applied it (e.g. a lost response).
        setAcceptanceNotice({ tone: 'info', messageKey: 'rescheduleProposal.accepted' });
      } else {
        setAcceptanceNotice({
          tone: 'error',
          messageKey: mapRescheduleAcceptanceErrorToKey(result.error),
        });
      }
    } finally {
      acceptBusyRef.current = false;
      if (isMountedRef.current) setIsAccepting(false);
    }
  }

  async function acceptAlternative(proposal: PendingAlternativeTime) {
    setIsAccepting(true);
    setAcceptanceNotice(null);
    try {
      const result = await acceptRequestedAlternativeTime(proposal.proposalId);
      if (!isMountedRef.current) return;
      // Always re-read: the authoritative state decides what is shown.
      const refreshed = await load();
      if (!isMountedRef.current) return;
      if (
        result.error === null ||
        // An earlier attempt already accepted it (e.g. a lost response).
        (refreshed !== null && wasAlternativeTimeAccepted(proposal, refreshed))
      ) {
        setAcceptanceNotice({ tone: 'info', messageKey: 'alternativeTimeProposal.accepted' });
      } else {
        setAcceptanceNotice({
          tone: 'error',
          messageKey: mapAlternativeTimeAcceptanceErrorToKey(result.error),
        });
      }
    } finally {
      acceptBusyRef.current = false;
      if (isMountedRef.current) setIsAccepting(false);
    }
  }

  function handleAcceptAlternative(
    proposal: PendingAlternativeTime,
    shownCurrent: string,
    shownProposed: string,
  ) {
    if (acceptBusyRef.current) return;
    acceptBusyRef.current = true;
    setAcceptanceNotice(null);
    const release = () => {
      acceptBusyRef.current = false;
    };
    Alert.alert(
      t('alternativeTimeProposal.dialogTitle'),
      t('alternativeTimeProposal.dialogMessage', {
        current: shownCurrent,
        proposed: shownProposed,
      }),
      [
        { text: t('alternativeTimeProposal.dialogCancel'), style: 'cancel', onPress: release },
        {
          text: t('alternativeTimeProposal.dialogConfirm'),
          onPress: () => {
            acceptAlternative(proposal);
          },
        },
      ],
      { cancelable: true, onDismiss: release },
    );
  }

  function handleAccept(proposal: PendingReschedule, shownCurrent: string, shownProposed: string) {
    if (acceptBusyRef.current) return;
    acceptBusyRef.current = true;
    setAcceptanceNotice(null);
    const release = () => {
      acceptBusyRef.current = false;
    };
    Alert.alert(
      t('rescheduleProposal.dialogTitle'),
      t('rescheduleProposal.dialogMessage', { current: shownCurrent, proposed: shownProposed }),
      [
        { text: t('rescheduleProposal.dialogCancel'), style: 'cancel', onPress: release },
        {
          text: t('rescheduleProposal.dialogConfirm'),
          onPress: () => {
            acceptProposal(proposal);
          },
        },
      ],
      { cancelable: true, onDismiss: release },
    );
  }

  async function withdrawMedicalAccess() {
    setIsWithdrawing(true);
    setWithdrawalNotice(null);
    try {
      const result = await withdrawAppointmentMedicalAccess(id);
      if (!isMountedRef.current) return;
      // Always re-read: the authoritative state decides what is shown.
      const refreshed = await load();
      if (!isMountedRef.current) return;
      const refreshedState = refreshed?.medicalAccessState ?? null;
      setWithdrawalNotice(medicalAccessWithdrawalNotice(result, refreshedState));
      if (refreshedState === 'REVOKED') {
        AccessibilityInfo.announceForAccessibility(t('medicalAccess.withdrawn'));
      }
    } finally {
      withdrawBusyRef.current = false;
      if (isMountedRef.current) setIsWithdrawing(false);
    }
  }

  function handleWithdrawMedicalAccess() {
    if (withdrawBusyRef.current) return;
    withdrawBusyRef.current = true;
    setWithdrawalNotice(null);
    const release = () => {
      withdrawBusyRef.current = false;
    };
    Alert.alert(
      t('medicalAccess.dialogTitle'),
      t('medicalAccess.dialogMessage'),
      [
        { text: t('medicalAccess.dialogCancel'), style: 'cancel', onPress: release },
        {
          text: t('medicalAccess.dialogConfirm'),
          style: 'destructive',
          onPress: () => {
            withdrawMedicalAccess();
          },
        },
      ],
      { cancelable: true, onDismiss: release },
    );
  }

  if (loadState === 'loading' || loadState === 'error' || loadState === 'notFound') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={backToList} />
          {loadState === 'loading' ? (
            <StateMessage tone="loading" message={t('appointments.detailLoading')} />
          ) : (
            <>
              <StateMessage
                tone="error"
                message={
                  loadState === 'notFound'
                    ? t('appointments.detailNotFound')
                    : t('appointments.detailLoadError')
                }
              />
              <Button
                variant="secondary"
                label={t('appointments.backToList')}
                onPress={backToList}
              />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  if (!appointment) return null;

  const clinicLabel = clinicName ?? t('appointments.clinicUnavailable');
  const scheduledLabel =
    appointment.currentScheduledStartAt && appointment.currentSchedulingTimezoneName
      ? formatInstantInTimeZone(
          appointment.currentScheduledStartAt,
          appointment.currentSchedulingTimezoneName,
        )
      : null;

  // Advisory: a REQUESTED Appointment whose requested start has passed can no
  // longer be cancelled or rescheduled (SPEC-APT-003 BR-23, SPEC-APT-004
  // BR-27), and a CONFIRMED one whose confirmed start has been reached can no
  // longer be cancelled by a Guardian (BR-31) — it awaits the Clinic's
  // resolution (SPEC-APT-011 BR-34). The backend stays authoritative.
  const renderedAt = new Date();
  const cancellationView = guardianCancellationView(
    appointment.lifecycleState,
    appointment.currentScheduledStartAt,
    renderedAt,
    cancellationClosedForStart,
  );
  // The device clock decides only whether Cancel may be OPENED; an open panel
  // survives a render after the start, so a submission reaches the backend.
  const cancellation = guardianCancellationPresentation(
    cancellationView,
    appointment.lifecycleState,
    isCancelConfirming,
  );
  const showReschedule = canRescheduleRequestedAppointment(
    appointment.lifecycleState,
    appointment.currentScheduledStartAt,
    renderedAt,
  );
  const veterinarianAssigned = showsVeterinarianAssigned(assignmentHistory);
  const cancellationReason = shownCancellationReason(
    appointment.lifecycleState,
    appointment.cancellationReason,
  );
  const proposal = appointment.pendingReschedule;
  const showAccept = offersRescheduleAcceptance(appointment, renderedAt);
  const showAcceptAlternative = offersAlternativeTimeAcceptance(appointment, renderedAt);
  // SPEC-APT-006 BR-36, SPEC-APT-019 §5: the proposal stays visible; only the
  // Accept action depends on the read's generic current acceptability.
  const showNotAcceptable = showsRescheduleNotCurrentlyAcceptable(appointment, renderedAt);
  const showAlternativeNotAcceptable = showsAlternativeTimeNotCurrentlyAcceptable(
    appointment,
    renderedAt,
  );
  const awaitingConfirmation = isAwaitingClinicConfirmationOfAcceptedAlternative(appointment);
  const medicalAccess = medicalAccessView(appointment.medicalAccessState);
  const currentInterval =
    appointment.currentScheduledStartAt !== null &&
    appointment.currentScheduledEndAt !== null &&
    appointment.currentSchedulingTimezoneName !== null
      ? formatScheduledInterval(
          appointment.currentScheduledStartAt,
          appointment.currentScheduledEndAt,
          appointment.currentSchedulingTimezoneName,
          locale,
        )
      : null;
  const proposedInterval =
    proposal === null
      ? null
      : formatScheduledInterval(
          proposal.proposedStartAt,
          proposal.proposedEndAt,
          proposal.proposedTimezoneName,
          locale,
        );
  const shownCurrent =
    currentInterval === null ? '' : `${currentInterval.date}, ${currentInterval.time}`;
  const shownProposed =
    proposedInterval === null ? '' : `${proposedInterval.date}, ${proposedInterval.time}`;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView
        contentContainerStyle={[
          styles.scrollContent,
          { paddingBottom: insets.bottom + spacing.xl },
        ]}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <AppTopBar onBack={backToList} />

        <View style={styles.identity}>
          <Text style={styles.reasonTitle} accessibilityRole="header">
            {appointment.reasonForVisit}
          </Text>
          <AppointmentStatusBadge state={appointment.lifecycleState} />
        </View>

        <View style={styles.infoCard}>
          <InfoSection icon="business-outline" title={t('appointments.clinicLabel')} first>
            <Text style={styles.bodyText}>{clinicLabel}</Text>
          </InfoSection>

          {scheduledLabel ? (
            <InfoSection icon="calendar-outline" title={t('appointments.scheduledLabel')}>
              <Text style={styles.bodyText}>{scheduledLabel}</Text>
            </InfoSection>
          ) : null}

          <InfoSection icon="document-text-outline" title={t('appointments.reasonLabel')}>
            <Text style={styles.bodyText}>{appointment.reasonForVisit}</Text>
          </InfoSection>

          {/* SPEC-APT-011 BR-31: only a CANCELLED Appointment's recorded
              reason, in its own section — never the reason for visit. */}
          {cancellationReason !== null ? (
            <InfoSection
              icon="close-circle-outline"
              title={t('appointments.cancellationReasonLabel')}
            >
              <Text style={styles.bodyText}>{cancellationReason}</Text>
            </InfoSection>
          ) : null}

          {appointment.guardianNotes ? (
            <InfoSection icon="chatbubble-ellipses-outline" title={t('appointments.notesLabel')}>
              <Text style={styles.bodyText}>{appointment.guardianNotes}</Text>
            </InfoSection>
          ) : null}

          {/* Veterinarian Assignment is optional, so only a current assignment
              is mentioned; no veterinarian identity is read or shown. */}
          {veterinarianAssigned ? (
            <InfoSection icon="medkit-outline" title={t('appointments.veterinarianSectionTitle')}>
              <Text style={styles.bodyText}>{t('appointments.veterinarianAssignedIndicator')}</Text>
            </InfoSection>
          ) : null}

          {/* Same visibility rule (more than one revision) and the backend's
              order, unchanged. */}
          {schedulingHistory.length > 1 ? (
            <InfoSection icon="time-outline" title={t('appointments.schedulingHistoryTitle')}>
              {schedulingHistory.map((entry, index) => {
                const contextLabel = t(lifecycleLabelKey(entry.revisionContext));
                const when = formatInstantInTimeZone(
                  entry.scheduledStartAt,
                  entry.establishmentTimezoneName,
                );
                return (
                  <View
                    key={entry.revisionSequence}
                    style={[styles.historyRow, index > 0 && styles.historyRowDivider]}
                    accessible
                    accessibilityLabel={`${contextLabel} · ${when}`}
                  >
                    <Text style={styles.historyContext}>{contextLabel}</Text>
                    <Text style={styles.historyWhen}>{when}</Text>
                  </View>
                );
              })}
            </InfoSection>
          ) : null}
        </View>

        {acceptanceNotice !== null ? (
          <Notice tone={acceptanceNotice.tone} message={t(acceptanceNotice.messageKey)} />
        ) : null}

        {/* SPEC-APT-011 BR-34: still CONFIRMED, its time has passed, and the
            Clinic will record the outcome — no attendance, no-show,
            veterinarian, or clinical record is implied. */}
        {cancellationView.closedByBackend ? (
          <Notice tone="info" message={t('appointmentErrors.confirmedStartReachedCancel')} />
        ) : null}
        {cancellation.showAwaitingNote ? (
          <Notice tone="info" message={t('appointments.awaitingClinicResolution')} />
        ) : null}

        {/* SPEC-APT-011 BR-33: the request now carries the Clinic's accepted
            alternative; it is still REQUESTED, not confirmed. */}
        {awaitingConfirmation ? (
          <Notice tone="info" message={t('alternativeTimeProposal.awaitingConfirmation')} />
        ) : null}

        {/* SPEC-APT-019 §5: the Clinic's alternative for the request, beside
            the current requested time, which it never replaces until accepted. */}
        {proposal !== null &&
        proposal.kind === 'requestedAlternativeTime' &&
        proposedInterval !== null ? (
          <View style={styles.proposalCard}>
            <View style={styles.cancelHeader}>
              <Ionicons
                name="swap-horizontal-outline"
                size={20}
                color={colors.warning}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.cancelTitle} accessibilityRole="header">
                {t('alternativeTimeProposal.sectionTitle')}
              </Text>
            </View>
            {currentInterval !== null ? (
              <View
                style={styles.proposalRow}
                accessible
                accessibilityLabel={`${t('alternativeTimeProposal.currentLabel')}: ${shownCurrent}`}
              >
                <Text style={styles.proposalLabel}>
                  {t('alternativeTimeProposal.currentLabel')}
                </Text>
                <Text style={styles.bodyText}>{currentInterval.date}</Text>
                <Text style={styles.bodyText}>{currentInterval.time}</Text>
              </View>
            ) : null}
            <View
              style={styles.proposalRow}
              accessible
              accessibilityLabel={`${t('alternativeTimeProposal.proposedLabel')}: ${shownProposed}`}
            >
              <Text style={styles.proposalLabel}>{t('alternativeTimeProposal.proposedLabel')}</Text>
              <Text style={styles.proposedText}>{proposedInterval.date}</Text>
              <Text style={styles.proposedText}>{proposedInterval.time}</Text>
            </View>
            <View
              style={styles.proposalRow}
              accessible
              accessibilityLabel={`${t('alternativeTimeProposal.clinicReasonLabel')}: ${proposal.reason}`}
            >
              <Text style={styles.proposalLabel}>
                {t('alternativeTimeProposal.clinicReasonLabel')}
              </Text>
              <Text style={styles.bodyText}>{proposal.reason}</Text>
            </View>
            <Text style={styles.cancelBody}>{t('alternativeTimeProposal.acceptExplanation')}</Text>
            {currentInterval !== null ? (
              <Text style={styles.cancelBody}>
                {t('alternativeTimeProposal.deadline', { current: shownCurrent })}
              </Text>
            ) : null}
            {showAcceptAlternative ? (
              <Button
                label={t('alternativeTimeProposal.acceptAction')}
                onPress={() => handleAcceptAlternative(proposal, shownCurrent, shownProposed)}
                loading={isAccepting}
                disabled={isAccepting}
              />
            ) : null}
            {showAlternativeNotAcceptable ? (
              <Notice tone="info" message={t('alternativeTimeProposal.notCurrentlyAcceptable')} />
            ) : null}
          </View>
        ) : null}

        {/* SPEC-APT-011 BR-32: a Clinic proposal, its exact stored interval and
            the Clinic's reason — separate from the reason for visit and any
            cancellation reason. The confirmed time stays the commitment. */}
        {proposal !== null &&
        proposal.kind === 'confirmedReschedule' &&
        proposal.proposingContext === 'CLINIC' &&
        proposedInterval !== null ? (
          <View style={styles.proposalCard}>
            <View style={styles.cancelHeader}>
              <Ionicons
                name="swap-horizontal-outline"
                size={20}
                color={colors.warning}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.cancelTitle} accessibilityRole="header">
                {t('rescheduleProposal.sectionTitle')}
              </Text>
            </View>
            {currentInterval !== null ? (
              <View
                style={styles.proposalRow}
                accessible
                accessibilityLabel={`${t('rescheduleProposal.currentLabel')}: ${shownCurrent}`}
              >
                <Text style={styles.proposalLabel}>{t('rescheduleProposal.currentLabel')}</Text>
                <Text style={styles.bodyText}>{currentInterval.date}</Text>
                <Text style={styles.bodyText}>{currentInterval.time}</Text>
              </View>
            ) : null}
            <View
              style={styles.proposalRow}
              accessible
              accessibilityLabel={`${t('rescheduleProposal.proposedLabel')}: ${shownProposed}`}
            >
              <Text style={styles.proposalLabel}>{t('rescheduleProposal.proposedLabel')}</Text>
              <Text style={styles.proposedText}>{proposedInterval.date}</Text>
              <Text style={styles.proposedText}>{proposedInterval.time}</Text>
            </View>
            {proposal.reason !== null ? (
              <View
                style={styles.proposalRow}
                accessible
                accessibilityLabel={`${t('rescheduleProposal.clinicReasonLabel')}: ${proposal.reason}`}
              >
                <Text style={styles.proposalLabel}>
                  {t('rescheduleProposal.clinicReasonLabel')}
                </Text>
                <Text style={styles.bodyText}>{proposal.reason}</Text>
              </View>
            ) : null}
            <Text style={styles.cancelBody}>{t('rescheduleProposal.keepsCurrent')}</Text>
            {showAccept ? (
              <Button
                label={t('rescheduleProposal.acceptAction')}
                onPress={() => handleAccept(proposal, shownCurrent, shownProposed)}
                loading={isAccepting}
                disabled={isAccepting}
              />
            ) : null}
            {showNotAcceptable ? (
              <Notice tone="info" message={t('rescheduleProposal.notCurrentlyAcceptable')} />
            ) : null}
          </View>
        ) : null}

        {/* A Guardian-originated proposal waits for the Clinic: read-only. */}
        {proposal !== null &&
        proposal.kind === 'confirmedReschedule' &&
        proposal.proposingContext === 'GUARDIAN' ? (
          <Notice tone="info" message={t('rescheduleProposal.guardianProposalPending')} />
        ) : null}

        {showReschedule || cancellation.showCancelAction || cancellation.showPanel ? (
          <View style={styles.actions}>
            {showReschedule ? (
              <Button
                variant="secondary"
                label={t('appointments.rescheduleAction')}
                onPress={() =>
                  router.push(`/appointments/${appointment.id}/reschedule?petId=${petId}`)
                }
              />
            ) : null}

            {cancellation.showCancelAction ? (
              <Button
                variant="destructive"
                label={t('appointments.cancelAction')}
                onPress={() => setIsCancelConfirming(true)}
              />
            ) : null}

            {cancellation.showPanel ? (
              <View style={styles.cancelPanel}>
                <View style={styles.cancelHeader}>
                  <Ionicons
                    name="alert-circle-outline"
                    size={20}
                    color={colors.errorDark}
                    accessibilityElementsHidden
                    importantForAccessibility="no-hide-descendants"
                  />
                  <Text style={styles.cancelTitle} accessibilityRole="header">
                    {t('appointments.cancelConfirmTitle')}
                  </Text>
                </View>
                <Text style={styles.cancelBody}>{t('appointments.cancelConfirmBody')}</Text>
                <Input
                  label={t('appointments.cancelReasonLabel')}
                  value={cancelReason}
                  onChangeText={setCancelReason}
                />
                {cancelError ? <Notice tone="error" message={cancelError} /> : null}
                <Button
                  variant="destructive"
                  label={t('appointments.cancelConfirmButton')}
                  onPress={handleConfirmCancel}
                  loading={isCancelling}
                />
                <Button
                  variant="secondary"
                  label={t('appointments.cancelDismissButton')}
                  onPress={() => {
                    setIsCancelConfirming(false);
                    setCancelError(null);
                  }}
                  disabled={isCancelling}
                />
              </View>
            ) : null}
          </View>
        ) : null}

        {/* SPEC-ACC-002 §16: decided by the medical-access state alone. */}
        {medicalAccess === 'offerWithdrawal' ? (
          <View style={styles.proposalCard}>
            <View style={styles.cancelHeader}>
              <Ionicons
                name="shield-checkmark-outline"
                size={20}
                color={colors.primary}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.cancelTitle} accessibilityRole="header">
                {t('medicalAccess.sectionTitle')}
              </Text>
            </View>
            <Text style={styles.accessStatus}>{t('medicalAccess.activeStatus')}</Text>
            <Text style={styles.cancelBody}>{t('medicalAccess.activeBody')}</Text>
            {withdrawalNotice !== null ? (
              <Notice tone={withdrawalNotice.tone} message={t(withdrawalNotice.messageKey)} />
            ) : null}
            {isManagingAccess ? null : (
              <Button
                variant="secondary"
                label={t('medicalAccess.manageAction')}
                accessibilityLabel={t('medicalAccess.manageActionAccessibility')}
                onPress={() => setIsManagingAccess(true)}
              />
            )}
          </View>
        ) : null}
        {/* An exceptional consent control, irreversible for this Appointment:
            only inside the management panel, as for cancellation. */}
        {medicalAccess === 'offerWithdrawal' && isManagingAccess ? (
          <View style={styles.cancelPanel}>
            <View style={styles.cancelHeader}>
              <Ionicons
                name="alert-circle-outline"
                size={20}
                color={colors.errorDark}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.cancelTitle} accessibilityRole="header">
                {t('medicalAccess.panelTitle')}
              </Text>
            </View>
            {medicalAccessConsequenceKeys().map((key) => (
              <Text
                key={key}
                style={
                  key === 'medicalAccess.consequenceIrreversible'
                    ? styles.irreversibleNote
                    : styles.cancelBody
                }
              >
                {t(key)}
              </Text>
            ))}
            <Button
              variant="destructive"
              label={t('medicalAccess.withdrawAction')}
              accessibilityLabel={t('medicalAccess.withdrawActionAccessibility')}
              onPress={handleWithdrawMedicalAccess}
              loading={isWithdrawing}
              disabled={isWithdrawing}
            />
            <Button
              variant="secondary"
              label={t('medicalAccess.panelBack')}
              onPress={() => setIsManagingAccess(false)}
              disabled={isWithdrawing}
            />
          </View>
        ) : null}
        {medicalAccess === 'withdrawn' ? (
          <View style={styles.proposalCard}>
            <View style={styles.cancelHeader}>
              <Ionicons
                name="shield-outline"
                size={20}
                color={colors.textSecondary}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.cancelTitle} accessibilityRole="header">
                {t('medicalAccess.withdrawn')}
              </Text>
            </View>
            <Text style={styles.cancelBody}>{t('medicalAccess.withdrawnBody')}</Text>
          </View>
        ) : null}
        {medicalAccess === 'none' && withdrawalNotice !== null ? (
          <Notice tone={withdrawalNotice.tone} message={t(withdrawalNotice.messageKey)} />
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

type InfoSectionProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  title: string;
  /** The first section draws no top divider. */
  first?: boolean;
  children: ReactNode;
};

function InfoSection({ icon, title, first = false, children }: InfoSectionProps) {
  return (
    <View style={[styles.section, !first && styles.sectionDivider]}>
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
    gap: spacing.sm,
  },
  reasonTitle: {
    ...typography.h2,
    color: colors.textPrimary,
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
    gap: spacing.sm,
  },
  sectionDivider: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
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
  // Aligned with the section title's text, not the icon badge.
  sectionBody: {
    paddingLeft: 28 + spacing.sm,
    gap: spacing.sm,
  },
  bodyText: {
    ...typography.body,
    color: colors.textPrimary,
  },
  historyRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: spacing.md,
  },
  historyRowDivider: {
    paddingTop: spacing.sm,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  historyContext: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  historyWhen: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
    textAlign: 'right',
  },
  actions: {
    gap: spacing.md,
  },
  cancelPanel: {
    gap: spacing.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    padding: spacing.lg,
  },
  cancelHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  cancelTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  cancelBody: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  accessStatus: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primary,
  },
  // The withdrawal panel's last paragraph: discreetly emphasized, not alarming.
  irreversibleNote: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  proposalCard: {
    gap: spacing.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    padding: spacing.lg,
  },
  proposalRow: {
    gap: 2,
  },
  proposalLabel: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  proposedText: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
});

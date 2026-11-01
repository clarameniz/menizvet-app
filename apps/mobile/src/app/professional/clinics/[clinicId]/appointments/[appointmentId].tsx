import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState, type ComponentProps } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppointmentClinicalRecordSection } from '@/components/appointment-clinical-record-section';
import {
  AppointmentManagementSection,
  ManagementActionRow,
  ManagementBlock,
} from '@/components/appointment-management-section';
import { AppointmentPriorHistoryRow } from '@/components/appointment-prior-history-row';
import { AppointmentRequesterContactRow } from '@/components/appointment-requester-contact-row';
import { AppointmentVeterinarianSection } from '@/components/appointment-veterinarian-section';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { AppointmentStatusBadge } from '@/components/design-system/appointment-status-badge';
import { Button } from '@/components/design-system/button';
import { CompactAction } from '@/components/design-system/compact-action';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { completeAppointment } from '@/data/appointment-completion';
import { confirmAppointment } from '@/data/appointment-confirmation';
import { markAppointmentNoShow } from '@/data/appointment-no-show';
import {
  getClinicAppointment,
  type ClinicScheduleAppointment,
} from '@/data/clinic-appointment-schedule';
import { getMyProfessionalClinics, type ProfessionalClinic } from '@/data/professional-clinics';
import { getMyProfessionalContext } from '@/data/professional-context';
import { cancelProfessionalAppointment } from '@/data/professional-appointment-cancellation';
import { withdrawRescheduleProposal } from '@/data/professional-appointment-reschedule';
import { mapAppointmentCompletionErrorToKey } from '@/i18n/appointment-completion-error-messages';
import { mapAppointmentConfirmationErrorToKey } from '@/i18n/appointment-confirmation-error-messages';
import { mapAppointmentNoShowErrorToKey } from '@/i18n/appointment-no-show-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { mapProfessionalCancellationErrorToKey } from '@/i18n/professional-appointment-cancellation-error-messages';
import {
  mapClinicScheduleErrorToKey,
  mapProfessionalClinicsErrorToKey,
} from '@/i18n/professional-context-error-messages';
import { mapRescheduleWithdrawalErrorToKey } from '@/i18n/professional-reschedule-error-messages';
import { lifecycleLabelKey } from '@/lib/appointment-lifecycle';
import {
  appointmentManagementStatusFor,
  managedActionGate,
  managedActionsNotice,
  type AppointmentManagementStatus,
} from '@/lib/appointment-management';
import {
  isRescheduleProposalNoLongerPending,
  offersRescheduleProposal,
  offersRescheduleWithdrawal,
  isPendingRescheduleCurrentlyInfeasible,
  professionalRescheduleHref,
} from '@/lib/appointment-reschedule';
import { formatScheduledInterval } from '@/lib/appointment-time';
import {
  clinicCancellationRequestFor,
  clinicScheduleGroupOf,
  completionRequestFor,
  confirmationRequestFor,
  cancellationReasonToShow,
  guardianNotesToShow,
  isAppointmentNowCompleted,
  isPostStartClinicCancellation,
  isSameReviewedAppointment,
  noShowRequestFor,
  offersAppointmentCompletion,
  offersAppointmentConfirmation,
  offersAppointmentNoShow,
  offersClinicCancellation,
  offersClinicalRecord,
  offersVeterinarianAssignment,
  resolveClinicScheduleAvailability,
  type ClinicScheduleGroup,
} from '@/lib/clinic-schedule-display';
import {
  offersHistoryFromAppointmentDetail,
  professionalMedicalHistoryHref,
} from '@/lib/professional-medical-history';
import { goBackOr } from '@/lib/navigation';
import { professionalClinicLabel } from '@/lib/professional-clinics-display';
import {
  discardsPendingAlternativeTime,
  isAwaitingClinicConfirmationOfAcceptedAlternative,
  offersAlternativeTimeProposal,
  professionalAlternativeTimeHref,
} from '@/lib/requested-alternative-time';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'clinicUnavailable' }
  | { kind: 'scheduleUnavailable'; clinic: ProfessionalClinic }
  /**
   * The single read's uniform denial: an unknown Appointment, one of another
   * Clinic, or schedule-view authority lost since the Clinic read.
   */
  | { kind: 'appointmentUnavailable'; clinic: ProfessionalClinic }
  | {
      kind: 'loaded';
      clinic: ProfessionalClinic;
      appointment: ClinicScheduleAppointment;
      /** The Clinic's Organization's APPOINTMENT_MANAGEMENT, read with the Clinic (BR-61). */
      appointmentManagement: AppointmentManagementStatus;
    };

/** The Appointment mutations this screen offers — at most one in flight. */
type MutationKind = 'confirm' | 'complete' | 'noShow' | 'cancel' | 'withdraw';

/** Outcome of the latest mutation, shown above the Appointment until the next one. */
type MutationNotice = { tone: 'info' | 'error'; messageKey: TranslationKey };

const GROUP_LABEL_KEYS: Record<ClinicScheduleGroup, TranslationKey> = {
  upcoming: 'clinicSchedule.upcomingSectionTitle',
  needsResolution: 'clinicSchedule.needsResolutionSectionTitle',
  historical: 'appointments.historicalSectionTitle',
};

/**
 * Professional Appointment detail, reached from the Clinic Appointment
 * Schedule (SPEC-APT-012). Only the Clinic and Appointment ids travel in the
 * route; nothing displayed is trusted from navigation. Beside the date, time,
 * and reason for visit it shows the pet guardian's optional request notes,
 * verbatim, in every lifecycle state (request context, not clinical
 * documentation), and the Appointment contact — the original requester's name
 * and verified email from its own single-Appointment read (SPEC-APT-012 BR-50).
 *
 * Every focus re-reads get_my_professional_clinics() (is the Clinic still a
 * Professional Clinic offering the schedule?) and then only this Appointment
 * through get_clinic_appointment() (SPEC-APT-012 BR-52) — never the whole
 * schedule, so any Appointment of the Clinic opens, however old. Latest read
 * wins. Only the first load shows the loading/retryable error states; losing
 * the Clinic, the schedule, or the Appointment always replaces the content.
 *
 * Contextual actions, each offered only from KNOWN capabilities and the
 * advisory device clock (the backend stays authoritative):
 * - Confirm a pending REQUESTED Appointment (SPEC-APT-002);
 * - Mark as completed (the visit took place, SPEC-APT-009) or as no-show (the
 *   Pet did not attend, SPEC-APT-010) a CONFIRMED Appointment whose start was
 *   reached — the two resolutions of a visit (SPEC-APT-012 BR-46). Completion
 *   is independent of documentation: it needs no Veterinarian Assignment or
 *   record, and documenting continues after it; a re-read showing it
 *   COMPLETED after a failed call (a lost response, or another actor) is
 *   reported neutrally;
 * - Cancel a REQUESTED Appointment whose start is still in the future, or a
 *   CONFIRMED one before or after its start (SPEC-APT-003; the Guardian cutoff
 *   at the confirmed start, BR-31, never applies to the Clinic). After the
 *   start it is a less prominent "record a clinic cancellation" action under
 *   Complete and No-show, for a visit the Clinic itself called off;
 * - Propose a new time for a future CONFIRMED Appointment with no pending
 *   proposal (SPEC-APT-005), on its own screen, bound to the confirmed
 *   revision this detail displays;
 * - Propose another time for a future REQUESTED Appointment with no pending
 *   proposal (SPEC-APT-018 §5), on its own screen, bound to the requested
 *   revision this detail displays;
 * - Withdraw the Clinic's own pending proposal, of either kind (SPEC-APT-016).
 *
 * Confirm, Propose a new time and Propose another time also need the
 * Organization's APPOINTMENT_MANAGEMENT Entitlement (SPEC-APT-012 BR-61): it
 * is read on every focus from get_my_professional_context(), beside the
 * Clinic read and related by Organization id. When it is known to be missing
 * those three are not offered and one short note says so; when it could not be
 * verified they are not offered either, with a retry — never claiming it is
 * missing. The note appears only if one of them would otherwise be offered.
 * Cancel, Complete, No-show and Withdraw never depend on it.
 *
 * The detail is the Veterinarian's entry point to the visit (SPEC-MED-010
 * Part F, SPEC-APT-007 §13), in this order: the Pet, status and Clinic; one
 * summary card with the date and time, the reason, the assigned Veterinarian
 * (with "Assign to me" or "Assign / Change" when the server offers them —
 * never automatically) and, last, the Appointment contact; one Clinical record
 * card with "Add", the visit's records and, last, "View previous records" (an
 * explicit action only; nothing here reads it); then one "Appointment
 * management" card holding every lifecycle and scheduling action with its
 * rules — Confirm or Complete as its primary action, then No-show, the time
 * proposals (and any pending one, with Withdraw) and Cancel as quieter rows,
 * with the outcome of the latest of them. While a record editor is open
 * Complete is not shown, so it never competes with an unsaved record; a short
 * note says why. The Clinical record card is shown only to actors holding
 * CLINICAL_DOCUMENTATION; it performs the audited record read itself. Without
 * it, "View previous records" keeps a small card of its own. Once the visit
 * has records (`hasClinicalRecord`, SPEC-MED-010 BR-9), Cancel, No-show, and
 * Propose a new time are not offered — the backend rejects them; Complete
 * stays.
 *
 * A pending proposal is shown with its exact stored interval, origin, and
 * reason. A Guardian-originated proposal is read-only here: accepting it in the
 * Clinic context (SPEC-APT-006) is not part of this app's Phase 1 workflow, and
 * while it is pending no Clinic proposal is possible (SPEC-APT-005 BR-14).
 * A pending Clinic alternative for a request shows the current requested time
 * beside the proposed one, "awaiting guardian response", and Withdraw; Confirm
 * stays available, and its dialog warns that confirming the requested time
 * discards the alternative (SPEC-APT-002 BR-24). Once a Guardian accepted the
 * alternative, the request shows "the guardian accepted the proposed time —
 * awaiting confirmation" (SPEC-APT-012 BR-45) and Confirm confirms it.
 *
 * Cancellation is an inline form, as in the Guardian Appointment detail: it
 * shows the reviewed Pet, lifecycle, date and time and asks for the required
 * reason. The form keeps the exact row it was opened for and sends that row's
 * revision sequence (SPEC-APT-003 BR-24) — never a newer one from a later
 * read. If a later read shows that Appointment in a different state or
 * revision, the form closes so the actor must review again.
 *
 * One mutation at most is in flight; none is retried. Every outcome re-reads
 * the Clinic capabilities and the Appointment. After a successful cancellation the
 * screen stays, showing the refreshed CANCELLED Appointment (as the Guardian
 * detail does).
 */
export default function ProfessionalAppointmentDetailScreen() {
  const { t, locale } = useLocale();
  const { clinicId, appointmentId } = useLocalSearchParams<{
    clinicId: string;
    appointmentId: string;
  }>();
  const [loadState, setLoadState] = useState<LoadState>({ kind: 'loading' });
  const [submitting, setSubmitting] = useState<MutationKind | null>(null);
  const [mutationNotice, setMutationNotice] = useState<MutationNotice | null>(null);
  // The exact schedule row the cancellation form was opened for.
  const [cancelTarget, setCancelTarget] = useState<ClinicScheduleAppointment | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  const [showReasonError, setShowReasonError] = useState(false);
  // Bumped after every successful read, so the sections re-read with the
  // detail; each section also asks for the other's refresh when it changes.
  const [assignmentRefresh, setAssignmentRefresh] = useState(0);
  const [recordRefresh, setRecordRefresh] = useState(0);
  // A record editor is open in the Clinical record section (SPEC-MED-010 Part F).
  const [recordEditorOpen, setRecordEditorOpen] = useState(false);

  const isMountedRef = useRef(true);
  const loadSeqRef = useRef(0);
  const hasLoadedRef = useRef(false);
  // A dialog is open or a mutation is in flight; a ref, so a second tap in the
  // same frame can't open another dialog or submit twice.
  const mutationBusyRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  // Resolves to the Appointment this read found, or `null` when none was read.
  // `refreshSections: false` re-reads only the Appointment row (after a saved
  // record, which the record section has just re-read itself).
  const load = useCallback(
    async (refreshSections = true): Promise<ClinicScheduleAppointment | null> => {
      const seq = ++loadSeqRef.current;
      const isCurrent = () => isMountedRef.current && seq === loadSeqRef.current;

      function showFirstLoadError(messageKey: TranslationKey) {
        if (!hasLoadedRef.current) setLoadState({ kind: 'error', messageKey });
      }

      function replaceContent(next: LoadState) {
        hasLoadedRef.current = false;
        setCancelTarget(null);
        setLoadState(next);
      }

      // Entitlements come only from the context read (SPEC-ORG-008 BR-11).
      const [clinicsResult, contextResult] = await Promise.all([
        getMyProfessionalClinics(),
        getMyProfessionalContext(),
      ]);
      if (!isCurrent()) return null;
      if (clinicsResult.error !== null) {
        showFirstLoadError(mapProfessionalClinicsErrorToKey(clinicsResult.error));
        return null;
      }

      const availability = resolveClinicScheduleAvailability(clinicsResult.data, clinicId);
      if (availability.kind === 'clinicUnavailable') {
        replaceContent({ kind: 'clinicUnavailable' });
        return null;
      }
      if (availability.kind === 'scheduleUnavailable') {
        replaceContent({ kind: 'scheduleUnavailable', clinic: availability.clinic });
        return null;
      }

      const { clinic } = availability;
      // Only this Appointment is read (SPEC-APT-012 BR-52), never the whole schedule.
      const appointmentResult = await getClinicAppointment(clinic.clinicId, appointmentId);
      if (!isCurrent()) return null;
      if (appointmentResult.error !== null) {
        showFirstLoadError(mapClinicScheduleErrorToKey(appointmentResult.error));
        return null;
      }

      const appointment = appointmentResult.data;
      if (appointment === null) {
        replaceContent({ kind: 'appointmentUnavailable', clinic });
        return null;
      }

      hasLoadedRef.current = true;
      if (refreshSections) {
        setAssignmentRefresh((value) => value + 1);
        setRecordRefresh((value) => value + 1);
      }
      // A cancellation form opened for a row that this read has replaced closes:
      // the actor must review the new state before cancelling (SPEC-APT-003 BR-26).
      setCancelTarget((target) =>
        target !== null && !isSameReviewedAppointment(target, appointment) ? null : target,
      );
      setLoadState({
        kind: 'loaded',
        clinic,
        appointment,
        appointmentManagement: appointmentManagementStatusFor(contextResult, clinic.organizationId),
      });
      return appointment;
    },
    [clinicId, appointmentId],
  );

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  function handleRetry() {
    setLoadState({ kind: 'loading' });
    load();
  }

  // Runs one mutation, shows its outcome, and always re-reads before releasing
  // the busy state. Never retries. After a failure, `reconcileFailure` may
  // read the fresh Appointment and replace the error with a neutral outcome
  // when the authoritative state shows the intended effect already holds.
  async function runMutation(
    kind: MutationKind,
    mutate: () => Promise<{ error: string | null }>,
    successKey: TranslationKey,
    mapErrorToKey: (error: string) => TranslationKey,
    reconcileFailure?: (refreshed: ClinicScheduleAppointment | null) => MutationNotice | null,
  ) {
    mutationBusyRef.current = true;
    setSubmitting(kind);
    setMutationNotice(null);

    try {
      const result = await mutate();
      if (!isMountedRef.current) return;

      if (kind === 'cancel') {
        // Success or failure, the reviewed form is done: a failure (stale,
        // lifecycle changed, …) requires reopening it on the refreshed state.
        setCancelTarget(null);
        if (result.error === null) setCancelReason('');
      }
      if (result.error === null) {
        setMutationNotice({ tone: 'info', messageKey: successKey });
        await load();
        return;
      }
      const error = result.error;
      const refreshed = await load();
      if (!isMountedRef.current) return;
      setMutationNotice(
        reconcileFailure?.(refreshed) ?? { tone: 'error', messageKey: mapErrorToKey(error) },
      );
    } finally {
      mutationBusyRef.current = false;
      if (isMountedRef.current) setSubmitting(null);
    }
  }

  // Opens the native dialog for Confirm, completion, or no-show unless another
  // mutation is open or in flight.
  function openMutationDialog(
    title: string,
    message: string,
    cancelLabel: string,
    submitLabel: string,
    submit: () => void,
  ) {
    if (mutationBusyRef.current) return;
    mutationBusyRef.current = true;
    setMutationNotice(null);

    const release = () => {
      mutationBusyRef.current = false;
    };

    Alert.alert(
      title,
      message,
      [
        { text: cancelLabel, style: 'cancel', onPress: release },
        { text: submitLabel, onPress: submit },
      ],
      { cancelable: true, onDismiss: release },
    );
  }

  function handleConfirm(
    appointment: ClinicScheduleAppointment,
    shownDate: string,
    shownTime: string,
    shownPendingAlternative: string | null,
  ) {
    openMutationDialog(
      t('appointmentConfirmation.dialogTitle'),
      // Confirming discards a pending Clinic alternative (SPEC-APT-002 BR-24):
      // the dialog says so before anything is sent.
      shownPendingAlternative !== null
        ? t('alternativeTime.confirmWithPendingDialogMessage', {
            petName: appointment.petName,
            date: shownDate,
            time: shownTime,
            proposed: shownPendingAlternative,
          })
        : t('appointmentConfirmation.dialogMessage', {
            petName: appointment.petName,
            date: shownDate,
            time: shownTime,
          }),
      t('appointmentConfirmation.dialogCancel'),
      t('appointmentConfirmation.dialogConfirm'),
      () => {
        // Exactly the reviewed row's id and revision (SPEC-APT-002 BR-21).
        const request = confirmationRequestFor(appointment);
        runMutation(
          'confirm',
          () =>
            confirmAppointment(request.appointmentId, request.expectedRequestedRevisionSequence),
          'appointmentConfirmation.confirmed',
          mapAppointmentConfirmationErrorToKey,
        );
      },
    );
  }

  function handleComplete(
    appointment: ClinicScheduleAppointment,
    shownDate: string,
    shownTime: string,
  ) {
    openMutationDialog(
      t('appointmentCompletion.dialogTitle'),
      t('appointmentCompletion.dialogMessage', {
        petName: appointment.petName,
        date: shownDate,
        time: shownTime,
      }),
      t('appointmentCompletion.dialogCancel'),
      t('appointmentCompletion.dialogConfirm'),
      () => {
        // Exactly the reviewed row's id and confirmed revision (SPEC-APT-009 BR-8).
        const request = completionRequestFor(appointment);
        runMutation(
          'complete',
          () =>
            completeAppointment(request.appointmentId, request.expectedConfirmedRevisionSequence),
          'appointmentCompletion.completed',
          mapAppointmentCompletionErrorToKey,
          // A lost response to a successful call, or a completion by another
          // actor: the authoritative re-read shows COMPLETED, so say so
          // neutrally instead of reporting a failure.
          (refreshed) =>
            isAppointmentNowCompleted(request.appointmentId, refreshed)
              ? { tone: 'info', messageKey: 'appointmentCompletion.alreadyCompleted' }
              : null,
        );
      },
    );
  }

  function handleNoShow(
    appointment: ClinicScheduleAppointment,
    shownDate: string,
    shownTime: string,
  ) {
    openMutationDialog(
      t('appointmentNoShow.dialogTitle'),
      t('appointmentNoShow.dialogMessage', {
        petName: appointment.petName,
        date: shownDate,
        time: shownTime,
      }),
      t('appointmentNoShow.dialogCancel'),
      t('appointmentNoShow.dialogConfirm'),
      () => {
        // Exactly the reviewed row's id and confirmed revision (SPEC-APT-010 BR-41).
        const request = noShowRequestFor(appointment);
        runMutation(
          'noShow',
          () =>
            markAppointmentNoShow(request.appointmentId, request.expectedConfirmedRevisionSequence),
          'appointmentNoShow.marked',
          mapAppointmentNoShowErrorToKey,
        );
      },
    );
  }

  function handleWithdraw(proposalId: string, shownCurrent: string, isAlternativeTime: boolean) {
    openMutationDialog(
      t('professionalReschedule.withdrawDialogTitle'),
      // The request, not a confirmed commitment, keeps its time (SPEC-APT-016 BR-7).
      t(
        isAlternativeTime
          ? 'alternativeTime.withdrawDialogMessage'
          : 'professionalReschedule.withdrawDialogMessage',
        { current: shownCurrent },
      ),
      t('professionalReschedule.withdrawDialogCancel'),
      t('professionalReschedule.withdrawDialogConfirm'),
      () => {
        runMutation(
          'withdraw',
          () => withdrawRescheduleProposal(proposalId),
          isAlternativeTime ? 'alternativeTime.withdrawn' : 'professionalReschedule.withdrawn',
          mapRescheduleWithdrawalErrorToKey,
          // A retry after a lost response, or a proposal resolved meanwhile:
          // if it is no longer pending, say so neutrally instead of failing.
          (refreshed) =>
            isRescheduleProposalNoLongerPending(proposalId, refreshed)
              ? { tone: 'info', messageKey: 'professionalReschedule.proposalNoLongerPending' }
              : null,
        );
      },
    );
  }

  function openCancelForm(appointment: ClinicScheduleAppointment) {
    if (mutationBusyRef.current) return;
    setMutationNotice(null);
    setShowReasonError(false);
    setCancelTarget(appointment);
  }

  function closeCancelForm() {
    setCancelTarget(null);
    setShowReasonError(false);
  }

  function submitCancellation() {
    if (mutationBusyRef.current || cancelTarget === null) return;
    if (cancelReason.trim().length === 0) {
      setShowReasonError(true);
      return;
    }
    // The row the form was opened for — never a newer read (SPEC-APT-003 BR-24).
    const request = clinicCancellationRequestFor(cancelTarget, cancelReason);
    runMutation(
      'cancel',
      () =>
        cancelProfessionalAppointment(
          request.appointmentId,
          request.reason,
          request.expectedScheduleRevisionSequence,
        ),
      'professionalCancellation.cancelled',
      mapProfessionalCancellationErrorToKey,
    );
  }

  const goBack = () =>
    goBackOr({ pathname: '/professional/clinics/[clinicId]/calendar', params: { clinicId } });
  const backToClinics = () => router.dismissTo('/professional/clinics');

  if (loadState.kind !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          <AppTopBar onBack={goBack} />
          {loadState.kind === 'loading' ? (
            <StateMessage tone="loading" message={t('professionalAppointment.loading')} />
          ) : loadState.kind === 'error' ? (
            <View style={styles.stateBlock}>
              <StateMessage tone="error" message={t(loadState.messageKey)} />
              <Button label={t('professional.retry')} onPress={handleRetry} />
              <Button variant="secondary" label={t('common.back')} onPress={goBack} />
            </View>
          ) : loadState.kind === 'appointmentUnavailable' ? (
            <View style={styles.stateBlock}>
              <StateMessage
                tone="empty"
                icon="calendar-outline"
                message={t('professionalAppointment.notFound')}
              />
              <Button
                variant="secondary"
                label={t('professionalAppointment.backToSchedule')}
                onPress={goBack}
              />
            </View>
          ) : (
            <View style={styles.stateBlock}>
              <StateMessage
                tone="empty"
                icon="calendar-outline"
                message={t(
                  loadState.kind === 'clinicUnavailable'
                    ? 'professionalClinic.notAvailable'
                    : 'clinicSchedule.unavailable',
                )}
              />
              <Button
                variant="secondary"
                label={t('professionalClinic.backToClinics')}
                onPress={backToClinics}
              />
            </View>
          )}
        </ScrollView>
      </SafeAreaView>
    );
  }

  const { clinic, appointment, appointmentManagement } = loadState;
  const interval = formatScheduledInterval(
    appointment.currentScheduledStartAt,
    appointment.currentScheduledEndAt,
    appointment.currentSchedulingTimezoneName,
    locale,
  );
  // One advisory device-clock instant for the group and every offered action.
  const renderedAt = new Date();
  const group = clinicScheduleGroupOf(appointment, renderedAt);
  const guardianNotes = guardianNotesToShow(appointment);
  const cancellationReason = cancellationReasonToShow(appointment);
  // SPEC-APT-012 BR-61: eligibility, then the Organization's APPOINTMENT_MANAGEMENT.
  const confirmGate = managedActionGate(
    offersAppointmentConfirmation(clinic, appointment, renderedAt),
    appointmentManagement,
  );
  const proposeGate = managedActionGate(
    offersRescheduleProposal(clinic, appointment, renderedAt),
    appointmentManagement,
  );
  const alternativeGate = managedActionGate(
    offersAlternativeTimeProposal(clinic, appointment, renderedAt),
    appointmentManagement,
  );
  const managementNotice = managedActionsNotice([confirmGate, proposeGate, alternativeGate]);
  const offersConfirm = confirmGate === 'offered';
  const offersRecord = offersClinicalRecord(clinic, appointment);
  // An open record editor holds Complete back (SPEC-MED-010 Part F).
  const completeHeldByEditor = offersRecord && recordEditorOpen;
  const completable = offersAppointmentCompletion(clinic, appointment, renderedAt);
  const offersComplete = completable && !completeHeldByEditor;
  const offersNoShow = offersAppointmentNoShow(clinic, appointment, renderedAt);
  const offersCancel = offersClinicCancellation(clinic, appointment, renderedAt);
  const postStartCancel = offersCancel && isPostStartClinicCancellation(appointment, renderedAt);
  const offersPropose = proposeGate === 'offered';
  const offersProposeAlternative = alternativeGate === 'offered';
  const offersWithdraw = offersRescheduleWithdrawal(clinic, appointment);
  // SPEC-MED-010 BR-14: prior history, advisory; read only on the explicit action.
  const offersHistory = offersHistoryFromAppointmentDetail(
    clinic,
    appointment,
    renderedAt.getTime(),
  );
  // SPEC-APT-012 BR-44: an infeasible proposal stays visible and withdrawable.
  const proposalInfeasible = isPendingRescheduleCurrentlyInfeasible(appointment);
  const proposal = appointment.pendingReschedule;
  const awaitingConfirmation = isAwaitingClinicConfirmationOfAcceptedAlternative(appointment);
  const proposedInterval =
    proposal === null
      ? null
      : formatScheduledInterval(
          proposal.proposedStartAt,
          proposal.proposedEndAt,
          proposal.proposedTimezoneName,
          locale,
        );
  const formTarget =
    cancelTarget !== null && offersCancel && isSameReviewedAppointment(cancelTarget, appointment)
      ? cancelTarget
      : null;
  const formInterval =
    formTarget === null
      ? null
      : formatScheduledInterval(
          formTarget.currentScheduledStartAt,
          formTarget.currentScheduledEndAt,
          formTarget.currentSchedulingTimezoneName,
          locale,
        );
  const busy = submitting !== null;
  const shownProposal = proposal !== null && proposedInterval !== null ? proposal : null;
  const offersManagement =
    mutationNotice !== null ||
    awaitingConfirmation ||
    shownProposal !== null ||
    managementNotice !== null ||
    offersConfirm ||
    completable ||
    offersNoShow ||
    offersPropose ||
    offersProposeAlternative ||
    offersCancel;
  const shownPendingAlternative =
    discardsPendingAlternativeTime(appointment) && proposedInterval !== null
      ? `${proposedInterval.date}, ${proposedInterval.time}`
      : null;
  // Prior history: reading it is the explicit action, never this screen.
  const priorHistoryRow = offersHistory ? (
    <AppointmentPriorHistoryRow
      onPress={() => router.push(professionalMedicalHistoryHref(clinic.clinicId, appointment.id))}
      disabled={busy}
    />
  ) : null;

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <AppTopBar onBack={goBack} />

        <View style={styles.header}>
          <Text style={styles.title} accessibilityRole="header">
            {appointment.petName}
          </Text>
          <AppointmentStatusBadge state={appointment.lifecycleState} />
          <Text style={styles.groupLabel}>{t(GROUP_LABEL_KEYS[group])}</Text>
          <View style={styles.context}>
            <Text style={[styles.clinicName, clinic.clinicDisplayName === null && styles.unnamed]}>
              {professionalClinicLabel(clinic, t('professional.unnamedClinic'))}
            </Text>
            <Text style={styles.organizationName}>{clinic.organizationDisplayName}</Text>
          </View>
        </View>

        <View style={styles.infoCard}>
          <InfoRow icon="calendar-outline" label={t('professionalAppointment.dateTimeLabel')} first>
            {`${interval.date} · ${interval.time}`}
          </InfoRow>
          <InfoRow icon="document-text-outline" label={t('professionalAppointment.reasonLabel')}>
            {appointment.reasonForVisit}
          </InfoRow>
          {/* Only a CANCELLED Appointment's recorded reason, in its own row —
              never the reason for visit (SPEC-APT-003 BR-9). */}
          {cancellationReason !== null ? (
            <InfoRow
              icon="close-circle-outline"
              label={t('professionalAppointment.cancellationReasonLabel')}
            >
              {cancellationReason}
            </InfoRow>
          ) : null}
          {guardianNotes !== null ? (
            <InfoRow
              icon="chatbubble-ellipses-outline"
              label={t('professionalAppointment.guardianNotesLabel')}
            >
              {guardianNotes}
            </InfoRow>
          ) : null}
          {offersVeterinarianAssignment(appointment) ? (
            <AppointmentVeterinarianSection
              key={`assignment:${clinic.clinicId}:${appointment.id}`}
              clinicId={clinic.clinicId}
              appointmentId={appointment.id}
              refreshKey={assignmentRefresh}
              onChanged={() => setRecordRefresh((value) => value + 1)}
              disabled={busy}
            />
          ) : null}
          {/* SPEC-APT-012 BR-50: the original requester, in every lifecycle
              state; its own read, whose failure leaves this detail usable. */}
          <AppointmentRequesterContactRow
            key={`${clinic.clinicId}:${appointment.id}`}
            clinicId={clinic.clinicId}
            appointmentId={appointment.id}
            scheduleDisplayName={appointment.requesterDisplayName}
          />
        </View>

        {offersRecord ? (
          <AppointmentClinicalRecordSection
            key={`record:${clinic.clinicId}:${appointment.id}`}
            clinicId={clinic.clinicId}
            appointmentId={appointment.id}
            timeZone={appointment.currentSchedulingTimezoneName}
            refreshKey={recordRefresh}
            onRecorded={() => void load(false)}
            onAssignmentStale={() => setAssignmentRefresh((value) => value + 1)}
            onEditorOpenChange={setRecordEditorOpen}
            footer={priorHistoryRow ?? undefined}
            disabled={busy}
          />
        ) : priorHistoryRow !== null ? (
          // No Clinical record for this actor or state: the row keeps its own quiet card.
          <View style={styles.infoCard}>{priorHistoryRow}</View>
        ) : null}

        {offersManagement ? (
          <AppointmentManagementSection>
            {/* The outcome of the latest action, where it was taken. */}
            {mutationNotice !== null ? (
              <ManagementBlock>
                <Notice tone={mutationNotice.tone} message={t(mutationNotice.messageKey)} />
              </ManagementBlock>
            ) : null}

            {/* SPEC-APT-012 BR-45: the current request came from the Clinic's own
                alternative, accepted by a Guardian; Confirm below confirms it. */}
            {awaitingConfirmation ? (
              <ManagementBlock>
                <Notice tone="info" message={t('alternativeTime.acceptedAwaitingConfirmation')} />
              </ManagementBlock>
            ) : null}

            {shownProposal !== null && proposedInterval !== null ? (
              <ManagementBlock>
                <View style={styles.proposalPanel}>
                  <View style={styles.proposalHeader}>
                    <Ionicons
                      name="swap-horizontal-outline"
                      size={18}
                      color={colors.warning}
                      accessibilityElementsHidden
                      importantForAccessibility="no-hide-descendants"
                    />
                    <Text style={styles.proposalTitle} accessibilityRole="header">
                      {t(
                        shownProposal.kind === 'requestedAlternativeTime'
                          ? 'alternativeTime.pendingTitle'
                          : 'professionalReschedule.pendingTitle',
                      )}
                    </Text>
                  </View>
                  {shownProposal.kind === 'confirmedReschedule' ? (
                    <Text style={styles.proposalOrigin}>
                      {t(
                        shownProposal.proposingContext === 'CLINIC'
                          ? 'professionalReschedule.originClinic'
                          : 'professionalReschedule.originGuardian',
                      )}
                    </Text>
                  ) : null}
                  <View>
                    {shownProposal.kind === 'requestedAlternativeTime' ? (
                      <InfoRow icon="time-outline" label={t('alternativeTime.currentLabel')} first>
                        {`${interval.date}, ${interval.time}`}
                      </InfoRow>
                    ) : null}
                    <InfoRow
                      icon="calendar-outline"
                      label={t(
                        shownProposal.kind === 'requestedAlternativeTime'
                          ? 'alternativeTime.proposedLabel'
                          : 'professionalReschedule.proposedLabel',
                      )}
                      first={shownProposal.kind === 'confirmedReschedule'}
                    >
                      {`${proposedInterval.date}, ${proposedInterval.time}`}
                    </InfoRow>
                    {shownProposal.reason !== null ? (
                      <InfoRow
                        icon="chatbubble-ellipses-outline"
                        label={t('professionalReschedule.reasonShownLabel')}
                      >
                        {shownProposal.reason}
                      </InfoRow>
                    ) : null}
                  </View>
                  <Text style={styles.proposalNote}>
                    {t(
                      shownProposal.kind === 'requestedAlternativeTime'
                        ? 'alternativeTime.awaitingGuardian'
                        : shownProposal.proposingContext === 'CLINIC'
                          ? 'professionalReschedule.awaitingGuardian'
                          : 'professionalReschedule.guardianProposalLimitation',
                    )}
                  </Text>
                  {proposalInfeasible ? (
                    <Text style={styles.proposalNote}>
                      {t('professionalReschedule.proposedTimeUnavailable')}
                    </Text>
                  ) : null}
                  {offersWithdraw ? (
                    <View style={styles.proposalAction}>
                      <CompactAction
                        icon="arrow-undo-outline"
                        label={t('professionalReschedule.withdrawAction')}
                        accessibilityLabel={t('professionalReschedule.withdrawAction')}
                        onPress={() =>
                          handleWithdraw(
                            shownProposal.proposalId,
                            `${interval.date}, ${interval.time}`,
                            shownProposal.kind === 'requestedAlternativeTime',
                          )
                        }
                        disabled={busy}
                        loading={submitting === 'withdraw'}
                      />
                    </View>
                  ) : null}
                </View>
              </ManagementBlock>
            ) : null}

            {managementNotice !== null ? (
              <ManagementBlock>
                <Notice
                  tone="info"
                  message={t(
                    managementNotice === 'unavailable'
                      ? 'appointmentManagement.unavailable'
                      : appointmentManagement.kind === 'unknown' &&
                          appointmentManagement.messageKey === 'errors.sessionExpired'
                        ? 'errors.sessionExpired'
                        : 'appointmentManagement.unverified',
                  )}
                />
                {managementNotice === 'unverified' ? (
                  <Button
                    variant="tertiary"
                    label={t('professional.retry')}
                    accessibilityLabel={t('appointmentManagement.retryLabel')}
                    onPress={() => load()}
                    disabled={busy}
                  />
                ) : null}
              </ManagementBlock>
            ) : null}

            {/* The primary action: Confirm a request, or Complete a visit that started. */}
            {offersConfirm || completable ? (
              <ManagementBlock>
                {offersConfirm ? (
                  <Button
                    label={t('appointmentConfirmation.action')}
                    onPress={() =>
                      handleConfirm(
                        appointment,
                        interval.date,
                        interval.time,
                        shownPendingAlternative,
                      )
                    }
                    disabled={busy}
                    loading={submitting === 'confirm'}
                  />
                ) : null}

                {/* SPEC-APT-012 BR-46: the two resolutions of a visit that started —
                    it took place (Complete) or the Pet did not attend (No-show).
                    The hint explains both, so it appears only when both are offered. */}
                {offersComplete && offersNoShow ? (
                  <Text style={styles.hint}>{t('appointmentCompletion.resolutionHint')}</Text>
                ) : null}

                {offersComplete ? (
                  <Button
                    label={t('appointmentCompletion.action')}
                    onPress={() => handleComplete(appointment, interval.date, interval.time)}
                    disabled={busy}
                    loading={submitting === 'complete'}
                  />
                ) : completable ? (
                  <Text style={styles.hint}>{t('appointmentCompletion.editorOpenHint')}</Text>
                ) : null}
              </ManagementBlock>
            ) : null}

            {offersNoShow ? (
              <ManagementActionRow
                icon="person-remove-outline"
                label={t('appointmentNoShow.action')}
                onPress={() => handleNoShow(appointment, interval.date, interval.time)}
                disabled={busy}
                loading={submitting === 'noShow'}
              />
            ) : null}

            {offersPropose && formTarget === null ? (
              <ManagementActionRow
                icon="time-outline"
                label={t('professionalReschedule.action')}
                navigates
                onPress={() =>
                  router.push(
                    professionalRescheduleHref(
                      clinic.clinicId,
                      appointment.id,
                      appointment.currentScheduleRevisionSequence,
                    ),
                  )
                }
                disabled={busy}
              />
            ) : null}

            {offersProposeAlternative && formTarget === null ? (
              <ManagementActionRow
                icon="time-outline"
                label={t('alternativeTime.action')}
                navigates
                onPress={() =>
                  router.push(
                    professionalAlternativeTimeHref(
                      clinic.clinicId,
                      appointment.id,
                      appointment.currentScheduleRevisionSequence,
                    ),
                  )
                }
                disabled={busy}
              />
            ) : null}

            {/* After the start, the longer "record a clinic cancellation" wording
                keeps it apart from the two resolutions above. */}
            {offersCancel && formTarget === null ? (
              <ManagementActionRow
                icon="close-circle-outline"
                tone="caution"
                label={t(
                  postStartCancel
                    ? 'professionalCancellation.postStartAction'
                    : 'professionalCancellation.action',
                )}
                onPress={() => openCancelForm(appointment)}
                disabled={busy}
              />
            ) : null}

            {formTarget !== null && formInterval !== null ? (
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
                    {t('professionalCancellation.panelTitle')}
                  </Text>
                </View>
                <View
                  style={styles.reviewed}
                  accessible
                  accessibilityLabel={[
                    formTarget.petName,
                    t(lifecycleLabelKey(formTarget.lifecycleState)),
                    formInterval.date,
                    formInterval.time,
                  ].join(', ')}
                >
                  <Text style={styles.reviewedPet}>{formTarget.petName}</Text>
                  <Text style={styles.reviewedMeta}>
                    {t(lifecycleLabelKey(formTarget.lifecycleState))}
                  </Text>
                  <Text style={styles.reviewedMeta}>{formInterval.date}</Text>
                  <Text style={styles.reviewedMeta}>{formInterval.time}</Text>
                </View>
                <Text style={styles.cancelBody}>{t('professionalCancellation.panelBody')}</Text>
                {postStartCancel ? (
                  <Text style={styles.cancelBody}>
                    {t('professionalCancellation.postStartHint')}
                  </Text>
                ) : null}
                <View style={styles.reasonField}>
                  <Input
                    label={t('professionalCancellation.reasonLabel')}
                    accessibilityLabel={t('professionalCancellation.reasonAccessibilityLabel')}
                    required
                    multiline
                    value={cancelReason}
                    onChangeText={(text) => {
                      setCancelReason(text);
                      if (text.trim().length > 0) setShowReasonError(false);
                    }}
                    editable={!busy}
                    error={
                      showReasonError ? t('professionalCancellation.reasonMissing') : undefined
                    }
                  />
                  {/* Informational, not an error: plain text that screen readers
                      read right after the field (SPEC-APT-011 BR-31). */}
                  <Text style={styles.reasonHelper}>
                    {t('professionalCancellation.reasonVisibilityHint')}
                  </Text>
                </View>
                <Button
                  variant="destructive"
                  label={t('professionalCancellation.submit')}
                  onPress={submitCancellation}
                  disabled={busy}
                  loading={submitting === 'cancel'}
                />
                <Button
                  variant="tertiary"
                  label={t('professionalCancellation.back')}
                  onPress={closeCancelForm}
                  disabled={busy}
                />
              </View>
            ) : null}
          </AppointmentManagementSection>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

function InfoRow({
  icon,
  label,
  first = false,
  children,
}: {
  icon: ComponentProps<typeof Ionicons>['name'];
  label: string;
  first?: boolean;
  children: string;
}) {
  return (
    <View
      style={[styles.row, !first && styles.rowDivider]}
      accessible
      accessibilityLabel={`${label}: ${children}`}
    >
      <Ionicons
        name={icon}
        size={16}
        color={colors.primary}
        style={styles.rowIcon}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <View style={styles.rowText}>
        <Text style={styles.rowLabel}>{label}</Text>
        <Text style={styles.rowValue}>{children}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  stateBlock: {
    gap: spacing.md,
  },
  header: {
    gap: spacing.sm,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  groupLabel: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  context: {
    gap: 2,
  },
  clinicName: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  unnamed: {
    fontStyle: 'italic',
  },
  organizationName: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  infoCard: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingHorizontal: spacing.lg,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
    paddingVertical: spacing.md,
  },
  rowDivider: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  // Centers the 16px icon on the caption's first 20px line box.
  rowIcon: {
    marginTop: 2,
  },
  rowText: {
    flexShrink: 1,
    gap: 2,
  },
  rowLabel: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  rowValue: {
    ...typography.body,
    color: colors.textPrimary,
  },
  // A pending proposal: a soft inset of the management card, above its actions.
  proposalPanel: {
    gap: spacing.sm,
    backgroundColor: colors.surfaceSoft,
    borderRadius: radius.medium,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  proposalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  proposalTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  proposalOrigin: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  proposalNote: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  // Withdraw, flush left with the panel's text despite its touch padding.
  proposalAction: {
    alignSelf: 'flex-start',
    marginLeft: -spacing.sm,
  },
  hint: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  // The cancellation form replaces Cancel inside the management card.
  cancelPanel: {
    gap: spacing.md,
    paddingVertical: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
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
  reviewed: {
    gap: 2,
    padding: spacing.md,
    borderRadius: radius.medium,
    backgroundColor: colors.surfaceSoft,
  },
  reviewedPet: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  reviewedMeta: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  cancelBody: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  reasonField: {
    gap: spacing.xs,
  },
  reasonHelper: {
    ...typography.caption,
    color: colors.textSecondary,
  },
});

import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { CareAuthorizationConfirmation } from '@/components/care-authorization-confirmation';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { CandidateDateTimePicker } from '@/components/design-system/candidate-date-time-picker';
import { CandidateWindowNavigator } from '@/components/design-system/candidate-window-navigator';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { PetAvatar } from '@/components/design-system/pet-card';
import { StateMessage } from '@/components/design-system/state-message';
import {
  getRequestableAppointmentStartTimes,
  requestAppointment,
  type RequestableCandidate,
} from '@/data/appointments';
import { getPublishedClinicOpeningHours, getPublishedClinicProfilesByIds } from '@/data/clinics';
import { getMyPets, type Pet } from '@/data/pets';
import { mapAppointmentErrorToKey } from '@/i18n/appointment-error-messages';
import { useLocale } from '@/i18n/locale-provider';
import {
  formatCandidateWindowDate,
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
import { goBackOr } from '@/lib/navigation';
import { petSummary } from '@/lib/pet-summary';
import { resolveRequestAppointmentInitialLoad } from '@/lib/request-appointment-load';
import { useSession } from '@/lib/session-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'clinicNotFound' | 'error' | 'loaded';
type CandidatesLoadState = 'loading' | 'loaded' | 'error';

/**
 * Guardian-only, entered from /clinics/[id] (SPEC-APT-001 BR-5 — Clinic
 * identity is fixed by route context and must already be published). The
 * parent `clinics` route tree is intentionally unauthenticated (public
 * Discovery), so this specific screen gates on session itself rather than at
 * the layout level — the same explicit, in-screen state-machine style every
 * other screen in this app already uses for its load/error states.
 *
 * Both the Clinic (display name + scheduling timezone) and the Pet list are
 * freshly re-resolved here through approved reads — never trusted from
 * navigation params.
 *
 * As of the Guardian requestable-times enhancement (SPEC-APT-014), the
 * Guardian no longer types a start or end time, nor picks a date from a
 * native calendar widget: getRequestableAppointmentStartTimes is queried for
 * one window of the approved Guardian horizon at a time (Clinic-local
 * today + 0…29, then + 30…60 via "Later dates"; SPEC-APT-014 BR-11), and only
 * the dates that window actually returned ≥1 candidate for are ever offered
 * as selectable — a date with zero candidates is unselectable by omission,
 * never a picker date the Guardian can tap into an empty state. Picking a
 * date then just filters the already-loaded candidate array in memory; no
 * second RPC call. Changing window clears the selection; the latest read
 * wins. The selected candidate's exact date/time/offset is submitted to
 * request_appointment unchanged; nothing about Availability or duration is
 * computed client-side. The date/time picker and selection rules are shared
 * with every candidate flow (CandidateDateTimePicker,
 * lib/candidate-selection.ts).
 */
export default function RequestAppointmentScreen() {
  const { t, locale } = useLocale();
  const { id: clinicId } = useLocalSearchParams<{ id: string }>();
  const { session, isLoading: isSessionLoading, isPasswordRecovery } = useSession();

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [clinicName, setClinicName] = useState<string | null>(null);
  const [schedulingTimezoneName, setSchedulingTimezoneName] = useState<string | null>(null);
  const [pets, setPets] = useState<Pet[]>([]);
  const [petsLoadFailed, setPetsLoadFailed] = useState(false);

  const [selectedPetId, setSelectedPetId] = useState<string | null>(null);
  const [candidateWindow, setCandidateWindow] = useState<RequestableCandidateWindow | null>(null);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [candidates, setCandidates] = useState<RequestableCandidate[]>([]);
  const [candidatesLoadState, setCandidatesLoadState] = useState<CandidatesLoadState>('loading');
  const [selectedCandidate, setSelectedCandidate] = useState<RequestableCandidate | null>(null);
  const [reasonForVisit, setReasonForVisit] = useState('');
  const [guardianNotes, setGuardianNotes] = useState('');
  const [careAuthConfirmed, setCareAuthConfirmed] = useState(false);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submissionError, setSubmissionError] = useState<string | null>(null);

  const isMountedRef = useRef(true);
  const candidateRequestSeqRef = useRef(0);

  // Derived, not effect-set (this project's "derive, don't effect" standard
  // — see reset-password.tsx): whether sign-in is required is fully computed
  // from useSession()'s own state, so it never needs its own setState.
  const isSignInRequired = !isSessionLoading && (!session || isPasswordRecovery);

  useEffect(() => {
    isMountedRef.current = true;

    if (isSessionLoading || !session || isPasswordRecovery) return;

    Promise.all([
      getPublishedClinicProfilesByIds([clinicId]),
      getPublishedClinicOpeningHours(clinicId),
      getMyPets(),
    ]).then(([profilesResult, openingHoursResult, petsResult]) => {
      if (!isMountedRef.current) return;

      const outcome = resolveRequestAppointmentInitialLoad(
        clinicId,
        profilesResult,
        openingHoursResult,
        petsResult,
      );

      if (outcome.status === 'fatalError') {
        setLoadState('error');
        return;
      }

      if (outcome.status === 'clinicNotFound') {
        setLoadState('clinicNotFound');
        return;
      }

      setClinicName(outcome.clinicName);
      setSchedulingTimezoneName(outcome.schedulingTimezoneName);
      setCandidateWindow(initialRequestableCandidateWindow(outcome.schedulingTimezoneName));
      setPetsLoadFailed(outcome.petsLoadFailed);

      const sortedPets = [...outcome.pets].sort((a, b) => a.name.localeCompare(b.name));
      setPets(sortedPets);
      if (sortedPets.length === 1) {
        setSelectedPetId(sortedPets[0].id);
      }

      setLoadState('loaded');
    });

    return () => {
      isMountedRef.current = false;
    };
  }, [clinicId, isSessionLoading, session, isPasswordRecovery]);

  // Loads the window on screen once (per window) rather than once per date
  // change. Latest-request-wins: a stale in-flight load (e.g. from a fast
  // re-navigation or window change) must never overwrite state for the Clinic
  // or window currently displayed. On success, the first requestable date is
  // auto-selected — a window change has already cleared the previous choice,
  // so this never overrides a Guardian choice.
  useEffect(() => {
    if (loadState !== 'loaded' || !candidateWindow) return;

    const requestSeq = ++candidateRequestSeqRef.current;

    getRequestableAppointmentStartTimes(
      clinicId,
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
      setSelectedDate(preferredCandidateDate(result.data, null));
      setSelectedCandidate((previous) => rematchSelectedCandidate(result.data, previous));
    });
  }, [clinicId, candidateWindow, loadState]);

  function handleWindowChange(window: RequestableCandidateWindow) {
    setCandidateWindow(window);
    setSelectedDate(null);
    setSelectedCandidate(null);
    setCandidates([]);
    setCandidatesLoadState('loading');
  }

  // The Care Authorization confirmation names one specific Pet (SPEC-ACC-001
  // BR-16), so switching to a different Pet invalidates it — the Guardian
  // must explicitly re-confirm for the newly named Pet. Re-tapping the
  // already-selected Pet changes nothing.
  function handleSelectPet(petId: string) {
    if (petId === selectedPetId) return;
    setSelectedPetId(petId);
    setCareAuthConfirmed(false);
  }

  function handleDateChange(localDate: string) {
    setSelectedDate(localDate);
    setSelectedCandidate((previous) => candidateAfterDateChange(previous, localDate));
  }

  // Pushed from Clinic detail: visible back pops to it, exactly like Android
  // hardware back (fallback to that same Clinic when there's nothing to pop).
  const handleBack = () => goBackOr(`/clinics/${clinicId}`);

  async function handleSubmit() {
    if (isSubmitting) return;

    setSubmissionError(null);

    if (
      !selectedPetId ||
      reasonForVisit.trim().length === 0 ||
      !careAuthConfirmed ||
      !selectedCandidate
    ) {
      setSubmissionError(t('appointmentRequest.requiredFieldError'));
      return;
    }

    setIsSubmitting(true);

    try {
      const rpcResult = await requestAppointment({
        petId: selectedPetId,
        clinicId,
        candidate: selectedCandidate,
        reasonForVisit: reasonForVisit.trim(),
        guardianNotes: guardianNotes.trim() || null,
      });

      if (!isMountedRef.current) return;

      if (rpcResult.error !== null) {
        setSubmissionError(t(mapAppointmentErrorToKey(rpcResult.error)));
        return;
      }

      // Navigate to the authoritative Appointment detail, which performs its
      // own fresh getPetAppointments read — never constructed from form values.
      // replace (not push), so this form is not left in the stack.
      router.replace(appointmentDetailHref(rpcResult.data.appointmentId, selectedPetId));
    } finally {
      if (isMountedRef.current) {
        setIsSubmitting(false);
      }
    }
  }

  if (isSignInRequired) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={handleBack} />
          <StateMessage tone="empty" icon="log-in-outline" message={t('errors.sessionExpired')} />
          <Button label={t('common.backToSignIn')} onPress={() => router.replace('/(auth)')} />
        </View>
      </SafeAreaView>
    );
  }

  if (loadState === 'loading') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={handleBack} />
          <StateMessage tone="loading" message={t('discoveryDetail.loading')} />
        </View>
      </SafeAreaView>
    );
  }

  if (loadState === 'clinicNotFound' || loadState === 'error') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={handleBack} />
          <StateMessage
            tone="error"
            message={
              loadState === 'clinicNotFound'
                ? t('appointmentRequest.clinicNotFound')
                : t('appointmentRequest.clinicLoadError')
            }
          />
          <Button
            variant="secondary"
            label={t('discoveryDetail.backToList')}
            onPress={() => router.replace(`/clinics/${clinicId}`)}
          />
        </View>
      </SafeAreaView>
    );
  }

  const selectedPet = pets.find((pet) => pet.id === selectedPetId) ?? null;
  const availableDates = distinctSortedCandidateDates(candidates);
  const previousWindow =
    candidateWindow === null || schedulingTimezoneName === null
      ? null
      : previousRequestableCandidateWindow(candidateWindow, schedulingTimezoneName);
  const nextWindow =
    candidateWindow === null || schedulingTimezoneName === null
      ? null
      : nextRequestableCandidateWindow(candidateWindow, schedulingTimezoneName);

  // UX only: keeps the CTA disabled (quietly — no error shown) until every
  // locally known requirement is met. The same requirements are still
  // re-checked defensively in handleSubmit, and the backend stays the
  // authority on everything else.
  const canSubmit =
    pets.length > 0 &&
    selectedPetId !== null &&
    availableDates.length > 0 &&
    selectedCandidate !== null &&
    reasonForVisit.trim().length > 0 &&
    careAuthConfirmed &&
    !isSubmitting;

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
              {t('appointmentRequest.title')}
            </Text>
            <View style={styles.clinicRow}>
              <Ionicons
                name="business-outline"
                size={16}
                color={colors.textSecondary}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              />
              <Text style={styles.clinicName} numberOfLines={2}>
                {clinicName ?? t('discoveryList.unnamedClinic')}
              </Text>
            </View>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              {t('appointmentRequest.petLabel')}
            </Text>
            {pets.length === 0 ? (
              <Notice
                tone="info"
                message={t(
                  petsLoadFailed
                    ? 'appointmentRequest.petsLoadError'
                    : 'appointmentRequest.noPetsError',
                )}
              />
            ) : (
              <View style={styles.petList} accessibilityRole="radiogroup">
                {pets.map((pet) => (
                  <SelectablePetRow
                    key={pet.id}
                    pet={pet}
                    selected={pet.id === selectedPetId}
                    onPress={() => handleSelectPet(pet.id)}
                  />
                ))}
              </View>
            )}
          </View>

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

          {candidatesLoadState === 'loaded' && availableDates.length > 0 ? (
            <CandidateDateTimePicker
              candidates={candidates}
              selectedDate={selectedDate}
              selectedCandidate={selectedCandidate}
              onSelectDate={handleDateChange}
              onSelectCandidate={setSelectedCandidate}
              dateLabel={t('appointmentRequest.dateLabel')}
              timeLabel={t('appointmentRequest.candidateListLabel')}
              locale={locale}
            />
          ) : (
            <View style={styles.section}>
              <Text style={styles.sectionTitle} accessibilityRole="header">
                {t('appointmentRequest.dateLabel')}
              </Text>
              {candidatesLoadState === 'loading' ? (
                <StateMessage tone="loading" message={t('appointmentRequest.loadingCandidates')} />
              ) : candidatesLoadState === 'error' ? (
                <StateMessage tone="error" message={t('appointmentRequest.candidatesLoadError')} />
              ) : (
                <StateMessage
                  tone="empty"
                  icon="calendar-outline"
                  message={t('appointmentRequest.noRequestableDatesError')}
                />
              )}
            </View>
          )}

          <View style={styles.section}>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              {t('appointmentRequest.visitDetailsTitle')}
            </Text>
            <Input
              label={t('appointmentRequest.reasonLabel')}
              value={reasonForVisit}
              onChangeText={setReasonForVisit}
              multiline
            />
            <Input
              label={t('appointmentRequest.notesLabel')}
              value={guardianNotes}
              onChangeText={setGuardianNotes}
              multiline
            />
          </View>

          {selectedPet && clinicName ? (
            <CareAuthorizationConfirmation
              petName={selectedPet.name}
              clinicName={clinicName}
              confirmed={careAuthConfirmed}
              onChange={setCareAuthConfirmed}
            />
          ) : null}

          <View style={styles.actions}>
            {/* SPEC-APT-001 BR-37: information only — no input, no consent step. */}
            <Text style={styles.contactNotice}>{t('appointmentRequest.contactNotice')}</Text>
            {submissionError ? <Notice tone="error" message={submissionError} /> : null}
            <Button
              label={t('appointmentRequest.submitAction')}
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

type SelectablePetRowProps = {
  pet: Pet;
  selected: boolean;
  onPress: () => void;
};

/**
 * `PetCard`'s visual language (paw avatar, name, get_my_pets() summary) as a
 * single-choice radio instead of a navigation row: a radio mark replaces the
 * chevron, and the selected card takes the teal border/soft fill.
 */
function SelectablePetRow({ pet, selected, onPress }: SelectablePetRowProps) {
  const summary = petSummary(pet);

  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="radio"
      accessibilityLabel={`${pet.name}, ${summary}`}
      accessibilityState={{ selected, checked: selected }}
      style={({ pressed }) => [
        styles.petRow,
        selected && styles.petRowSelected,
        pressed && !selected && styles.petRowPressed,
      ]}
    >
      <PetAvatar size={40} />
      <View style={styles.petText}>
        <Text style={styles.petName}>{pet.name}</Text>
        <Text style={styles.petSummary} numberOfLines={1}>
          {summary}
        </Text>
      </View>
      <Ionicons
        name={selected ? 'radio-button-on' : 'radio-button-off'}
        size={22}
        color={selected ? colors.primary : colors.textSecondary}
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  contactNotice: {
    ...typography.caption,
    color: colors.textSecondary,
  },
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
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  titleBlock: {
    gap: spacing.sm,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  clinicRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  clinicName: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  section: {
    gap: spacing.md,
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  petList: {
    gap: spacing.sm,
  },
  petRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 56,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.lg,
  },
  petRowSelected: {
    borderColor: colors.primary,
    backgroundColor: colors.primarySoft,
  },
  petRowPressed: {
    backgroundColor: colors.surfaceSoft,
  },
  petText: {
    flex: 1,
    gap: 2,
  },
  petName: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  petSummary: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  actions: {
    gap: spacing.md,
  },
});

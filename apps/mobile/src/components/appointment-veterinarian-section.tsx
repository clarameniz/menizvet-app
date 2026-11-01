import { Ionicons } from '@expo/vector-icons';
import { useEffect, useRef, useState } from 'react';
import { Alert, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/design-system/button';
import { CompactAction } from '@/components/design-system/compact-action';
import { Notice } from '@/components/design-system/notice';
import {
  assignAppointmentVeterinarian,
  assignMeToAppointment,
  getAppointmentVeterinarianAssignment,
  getAppointmentVeterinarianCandidates,
  type AppointmentVeterinarianAssignment,
  type AppointmentVeterinarianAssignmentRead,
  type AppointmentVeterinarianCandidate,
  type AssignmentWriteResult,
} from '@/data/appointment-veterinarian-assignment';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  assignmentNotice,
  currentAssigneeFor,
  expectedTokenFor,
  selectableCandidates,
  veterinarianName,
  type AssignmentIntent,
  type AssignmentNotice,
} from '@/lib/appointment-veterinarian-assignment';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type AssignmentState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** The uniform denial: the detail itself reports a lost Appointment. */
  | { kind: 'unavailable' }
  | { kind: 'loaded'; assignment: AppointmentVeterinarianAssignment };

type PickerState =
  | { kind: 'closed' }
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  | { kind: 'unavailable' }
  | { kind: 'loaded'; candidates: AppointmentVeterinarianCandidate[] };

/** A read's effect on what is shown: a failed refresh keeps the assignment already shown. */
function nextAssignmentState(
  current: AssignmentState,
  result: AppointmentVeterinarianAssignmentRead,
): AssignmentState {
  if (result.kind === 'loaded') return { kind: 'loaded', assignment: result.assignment };
  if (result.kind === 'unavailable') return { kind: 'unavailable' };
  if (current.kind === 'loaded') return current;
  return {
    kind: 'error',
    messageKey:
      result.kind === 'authenticationRequired'
        ? 'errors.sessionExpired'
        : 'veterinarianAssignment.loadError',
  };
}

/**
 * The Appointment's Veterinarian row on the professional detail (SPEC-APT-007
 * §13), the last row of its summary card under the date, time and reason: the
 * assignee's name (with "You"), "No longer at this clinic" when the
 * assignment is stale, or "No veterinarian assigned". Its own read, keyed by
 * Clinic and Appointment and repeated whenever `refreshKey` changes; reading
 * writes nothing, so opening the detail never assigns.
 *
 * - "Assign to me" when the server offers it (`may_assign_me`): one tap, no
 *   dialog. It is never offered over an eligible colleague.
 * - "Assign" / "Change", compact beside the name, when the reader may manage
 *   (`may_manage`): a short inline list of eligible candidates; selecting one
 *   assigns at once, and a
 *   change asks for one confirmation naming both Veterinarians.
 *
 * At most one write is in flight and none is retried. After any outcome —
 * including a stale assignment — the assignment is re-read and shown calmly,
 * and `onChanged` lets the detail re-read what depends on it. Assigning
 * creates no clinical record and grants no access to the medical history.
 */
export function AppointmentVeterinarianSection({
  clinicId,
  appointmentId,
  refreshKey,
  onChanged,
  disabled = false,
}: {
  clinicId: string;
  appointmentId: string;
  refreshKey: number;
  onChanged: () => void;
  disabled?: boolean;
}) {
  const { t } = useLocale();
  const [state, setState] = useState<AssignmentState>({ kind: 'loading' });
  const [picker, setPicker] = useState<PickerState>({ kind: 'closed' });
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<AssignmentNotice | null>(null);
  const [attempt, setAttempt] = useState(0);
  const busyRef = useRef(false);
  const isMountedRef = useRef(true);
  const readSeqRef = useRef(0);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  // Latest read wins; each one is numbered when it starts.
  async function read(): Promise<AppointmentVeterinarianAssignment | null> {
    const seq = ++readSeqRef.current;
    const result = await getAppointmentVeterinarianAssignment(clinicId, appointmentId);
    if (!isMountedRef.current || seq !== readSeqRef.current) return null;
    setState((current) => nextAssignmentState(current, result));
    return result.kind === 'loaded' ? result.assignment : null;
  }

  // Re-read on every refresh the detail asks for, and on Retry.
  useEffect(() => {
    const seq = ++readSeqRef.current;
    getAppointmentVeterinarianAssignment(clinicId, appointmentId).then((result) => {
      if (isMountedRef.current && seq === readSeqRef.current)
        setState((current) => nextAssignmentState(current, result));
    });
  }, [clinicId, appointmentId, refreshKey, attempt]);

  async function runAssignment(
    intent: AssignmentIntent,
    write: () => Promise<AssignmentWriteResult>,
  ) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setNotice(null);
    try {
      const result = await write();
      if (!isMountedRef.current) return;
      const after = await read();
      if (!isMountedRef.current) return;
      setPicker({ kind: 'closed' });
      setNotice(assignmentNotice(result, intent, after));
      onChanged();
    } finally {
      busyRef.current = false;
      if (isMountedRef.current) setBusy(false);
    }
  }

  async function openPicker() {
    if (busyRef.current) return;
    setNotice(null);
    setPicker({ kind: 'loading' });
    const result = await getAppointmentVeterinarianCandidates(clinicId, appointmentId);
    if (!isMountedRef.current) return;
    if (result.kind === 'permitted') {
      setPicker({ kind: 'loaded', candidates: selectableCandidates(result.candidates) });
    } else if (result.kind === 'denied') {
      setPicker({ kind: 'unavailable' });
    } else {
      setPicker({
        kind: 'error',
        messageKey:
          result.kind === 'authenticationRequired'
            ? 'errors.sessionExpired'
            : 'veterinarianAssignment.pickerError',
      });
    }
  }

  function choose(
    assignment: AppointmentVeterinarianAssignment,
    candidate: AppointmentVeterinarianCandidate,
  ) {
    if (busyRef.current) return;
    // The reviewed assignment, sent back so a concurrent change is detected (BR-32).
    const expectedToken = expectedTokenFor(assignment);
    const assign = () =>
      runAssignment('manage', () =>
        assignAppointmentVeterinarian(
          clinicId,
          appointmentId,
          candidate.veterinarianClinicAssignmentId,
          expectedToken,
        ),
      );
    const current = currentAssigneeFor(assignment);
    if (current === null) {
      void assign();
      return;
    }
    const fallback = t('veterinarianAssignment.fallbackName');
    const you = t('veterinarianAssignment.youSuffix');
    Alert.alert(
      t('veterinarianAssignment.changeDialogTitle'),
      t('veterinarianAssignment.changeDialogMessage', {
        from: veterinarianName(current, fallback, you),
        to: veterinarianName(candidate, fallback, you),
      }),
      [
        { text: t('veterinarianAssignment.changeDialogCancel'), style: 'cancel' },
        { text: t('veterinarianAssignment.changeDialogConfirm'), onPress: () => void assign() },
      ],
      { cancelable: true },
    );
  }

  if (state.kind === 'unavailable') return null;

  const fallback = t('veterinarianAssignment.fallbackName');
  const you = t('veterinarianAssignment.youSuffix');
  const assignment = state.kind === 'loaded' ? state.assignment : null;
  const assigneeLine =
    assignment === null
      ? null
      : assignment.kind === 'assigned'
        ? veterinarianName(assignment, fallback, you)
        : t('veterinarianAssignment.unassigned');
  const stale = assignment?.kind === 'assigned' && !assignment.isEligible;
  const inactive = busy || disabled;

  return (
    <View style={styles.section}>
      <View style={styles.line}>
        <View
          style={styles.row}
          accessible
          accessibilityLabel={[
            t('veterinarianAssignment.title'),
            assigneeLine ?? t('veterinarianAssignment.loading'),
            stale ? t('veterinarianAssignment.stale') : null,
          ]
            .filter((part): part is string => part !== null)
            .join(', ')}
        >
          <Ionicons
            name="medkit-outline"
            size={16}
            color={colors.primary}
            style={styles.rowIcon}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          />
          <View style={styles.rowText}>
            <Text style={styles.label}>{t('veterinarianAssignment.title')}</Text>
            {state.kind === 'loading' ? (
              <Text style={styles.meta}>{t('veterinarianAssignment.loading')}</Text>
            ) : state.kind === 'error' ? (
              <Text style={styles.meta}>{t(state.messageKey)}</Text>
            ) : (
              <Text style={[styles.value, assignment?.kind === 'unassigned' && styles.unassigned]}>
                {assigneeLine}
              </Text>
            )}
            {stale ? <Text style={styles.meta}>{t('veterinarianAssignment.stale')}</Text> : null}
          </View>
        </View>

        {assignment?.mayManage && picker.kind === 'closed' ? (
          <View style={styles.lineAction}>
            <CompactAction
              icon={
                assignment.kind === 'assigned' ? 'swap-horizontal-outline' : 'person-add-outline'
              }
              label={t(
                assignment.kind === 'assigned'
                  ? 'veterinarianAssignment.change'
                  : 'veterinarianAssignment.assign',
              )}
              accessibilityLabel={t(
                assignment.kind === 'assigned'
                  ? 'veterinarianAssignment.changeAccessibility'
                  : 'veterinarianAssignment.assignAccessibility',
              )}
              onPress={() => void openPicker()}
              disabled={inactive}
            />
          </View>
        ) : null}
      </View>

      {state.kind === 'error' ? (
        <Button
          variant="tertiary"
          label={t('veterinarianAssignment.retry')}
          onPress={() => setAttempt((value) => value + 1)}
          disabled={inactive}
        />
      ) : null}

      {notice !== null ? <Notice tone={notice.tone} message={t(notice.messageKey)} /> : null}

      {assignment?.mayAssignMe ? (
        <Button
          label={t('veterinarianAssignment.assignMe')}
          onPress={() =>
            void runAssignment('self', () => assignMeToAppointment(clinicId, appointmentId))
          }
          loading={busy && picker.kind === 'closed'}
          disabled={inactive}
        />
      ) : null}

      {assignment !== null && picker.kind !== 'closed' ? (
        <View style={styles.picker}>
          <Text style={styles.label} accessibilityRole="header">
            {t('veterinarianAssignment.pickerTitle')}
          </Text>
          {picker.kind === 'loading' ? (
            <Text style={styles.meta}>{t('veterinarianAssignment.pickerLoading')}</Text>
          ) : picker.kind === 'error' ? (
            <Text style={styles.meta}>{t(picker.messageKey)}</Text>
          ) : picker.kind === 'unavailable' ? (
            <Text style={styles.meta}>{t('veterinarianAssignment.pickerUnavailable')}</Text>
          ) : picker.candidates.length === 0 ? (
            <Text style={styles.meta}>{t('veterinarianAssignment.pickerEmpty')}</Text>
          ) : (
            picker.candidates.map((candidate) => {
              const name = veterinarianName(candidate, fallback, you);
              return (
                <Button
                  key={candidate.veterinarianClinicAssignmentId}
                  variant="secondary"
                  label={name}
                  accessibilityLabel={t('veterinarianAssignment.candidateAccessibility', { name })}
                  onPress={() => choose(assignment, candidate)}
                  loading={busy}
                  disabled={inactive}
                />
              );
            })
          )}
          <Button
            variant="tertiary"
            label={t('veterinarianAssignment.pickerClose')}
            onPress={() => setPicker({ kind: 'closed' })}
            disabled={busy}
          />
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  // The last row of the detail's summary card, below a discreet divider.
  section: {
    gap: spacing.md,
    paddingVertical: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  // The Veterinarian left, "Assign" / "Change" right; a long name wraps.
  line: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  // Flush right despite the action's touch padding.
  lineAction: { marginRight: -spacing.sm },
  row: { flex: 1, flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  // Centers the 16px icon on the caption's first 20px line box.
  rowIcon: { marginTop: 2 },
  rowText: { flexShrink: 1, gap: 2 },
  label: { ...typography.caption, fontWeight: '600', color: colors.textSecondary },
  value: { ...typography.body, color: colors.textPrimary },
  unassigned: { fontStyle: 'italic' },
  meta: { ...typography.caption, color: colors.textSecondary },
  picker: { gap: spacing.sm },
});

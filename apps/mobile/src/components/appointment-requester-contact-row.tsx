import { Ionicons } from '@expo/vector-icons';
import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { CompactAction, RowIconAction } from '@/components/design-system/compact-action';
import { Notice } from '@/components/design-system/notice';
import {
  getClinicAppointmentRequesterContact,
  type AppointmentRequesterContact,
  type AppointmentRequesterContactResult,
} from '@/data/appointment-requester-contact';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { requesterMailtoUrl, requesterName } from '@/lib/appointment-requester-contact';
import { openExternalUrl } from '@/lib/external-link';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ContactState =
  | { kind: 'loading' }
  | { kind: 'loaded'; contact: AppointmentRequesterContact }
  | { kind: 'failed'; messageKey: TranslationKey; retryable: boolean };

/**
 * "Appointment contact", the last row of the professional Appointment
 * detail's summary card (SPEC-APT-012 BR-50, SPEC-ID-006 BR-42): the original
 * requester's name and, when the single-Appointment read returns one, their
 * verified email with a compact action that opens the device's email
 * application (`mailto:`, nothing prefilled).
 *
 * Its own read, independent of the detail's: until it answers, or if it fails,
 * the requester's name from the schedule row is shown and the rest of the
 * detail is unaffected. Without an email it shows a neutral note and no
 * action. No identifier, phone, other Guardian, or in-app messaging.
 */
export function AppointmentRequesterContactRow({
  clinicId,
  appointmentId,
  scheduleDisplayName,
}: {
  clinicId: string;
  appointmentId: string;
  /** The requester's name from the schedule row (BR-49), shown until the read answers. */
  scheduleDisplayName: string | null;
}) {
  const { t } = useLocale();
  const [state, setState] = useState<ContactState>({ kind: 'loading' });
  // Bumped by Retry; each value is one read, and only the latest one applies.
  const [attempt, setAttempt] = useState(0);
  const [openFailed, setOpenFailed] = useState(false);
  const isMountedRef = useRef(true);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useEffect(() => {
    let isCurrent = true;
    getClinicAppointmentRequesterContact(clinicId, appointmentId).then((result) => {
      if (isCurrent) setState(contactStateFor(result));
    });
    return () => {
      isCurrent = false;
    };
  }, [clinicId, appointmentId, attempt]);

  const name = requesterName(
    state.kind === 'loaded' ? state.contact.displayName : scheduleDisplayName,
    t,
  );
  const email = state.kind === 'loaded' ? state.contact.email : null;
  const mailto = requesterMailtoUrl(email);
  // The line under the name: the email, a neutral note, or the read's status.
  const detail =
    state.kind === 'loading'
      ? t('appointmentContact.loading')
      : state.kind === 'loaded'
        ? (email ?? t('appointmentContact.noEmail'))
        : t(state.messageKey);
  const label = t('appointmentContact.heading');

  async function openEmail(url: string) {
    setOpenFailed(false);
    const opened = await openExternalUrl(url);
    if (isMountedRef.current && !opened) setOpenFailed(true);
  }

  return (
    <View style={styles.section}>
      <View style={styles.line}>
        <View style={styles.row} accessible accessibilityLabel={`${label}: ${name}, ${detail}`}>
          <Ionicons
            name="person-outline"
            size={16}
            color={colors.primary}
            style={styles.rowIcon}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          />
          <View style={styles.rowText}>
            <Text style={styles.label}>{label}</Text>
            <Text style={styles.value}>{name}</Text>
            <Text style={email !== null && state.kind === 'loaded' ? styles.email : styles.meta}>
              {detail}
            </Text>
          </View>
        </View>

        {mailto !== null ? (
          <View style={styles.lineAction}>
            <RowIconAction
              icon="mail-outline"
              accessibilityLabel={t('appointmentContact.emailActionAccessibility', { name })}
              onPress={() => void openEmail(mailto)}
            />
          </View>
        ) : state.kind === 'failed' && state.retryable ? (
          <View style={styles.lineAction}>
            <CompactAction
              icon="refresh-outline"
              label={t('appointmentContact.retry')}
              accessibilityLabel={t('appointmentContact.retry')}
              onPress={() => {
                setState({ kind: 'loading' });
                setAttempt((current) => current + 1);
              }}
            />
          </View>
        ) : null}
      </View>

      {openFailed ? (
        <Notice tone="error" message={t('appointmentContact.emailOpenFailed')} />
      ) : null}
    </View>
  );
}

function contactStateFor(result: AppointmentRequesterContactResult): ContactState {
  if (result.kind === 'contact') return { kind: 'loaded', contact: result.contact };
  if (result.kind === 'authenticationRequired')
    return { kind: 'failed', messageKey: 'errors.sessionExpired', retryable: false };
  if (result.kind === 'accessDenied')
    return { kind: 'failed', messageKey: 'appointmentContact.notAvailable', retryable: false };
  return { kind: 'failed', messageKey: 'appointmentContact.loadError', retryable: true };
}

const styles = StyleSheet.create({
  // The last row of the detail's summary card, below a discreet divider.
  section: {
    gap: spacing.sm,
    paddingVertical: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  // The requester left, the email action right; a long name or address wraps.
  line: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  // Flush right despite the action's touch padding.
  lineAction: { marginRight: -spacing.sm },
  row: { flex: 1, flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  // Centers the 16px icon on the caption's first 20px line box.
  rowIcon: { marginTop: 2 },
  rowText: { flexShrink: 1, gap: 2 },
  label: { ...typography.caption, fontWeight: '600', color: colors.textSecondary },
  value: { ...typography.body, color: colors.textPrimary },
  email: { ...typography.caption, color: colors.textPrimary },
  meta: { ...typography.caption, color: colors.textSecondary },
});

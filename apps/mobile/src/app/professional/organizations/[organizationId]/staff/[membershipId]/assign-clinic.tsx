import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { ChoiceChip } from '@/components/design-system/choice-chip';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { assignStaffVeterinarianToClinic } from '@/data/staff-workforce';
import { useStaffMember } from '@/hooks/use-staff-member';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { staffMemberName } from '@/lib/organization-staff';
import {
  assignableClinics,
  assignmentNotice,
  staffMemberHref,
  veterinarianSection,
  type MemberNotice,
} from '@/lib/staff-member-detail';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

export default function StaffClinicAssignmentRoute() {
  const { organizationId, membershipId } = useLocalSearchParams<{
    organizationId: string | string[];
    membershipId: string | string[];
  }>();
  const organization = typeof organizationId === 'string' ? organizationId : '';
  const membership = typeof membershipId === 'string' ? membershipId : '';
  return (
    <ClinicAssignmentScreen
      key={`${organization}/${membership}`}
      organizationId={organization}
      membershipId={membership}
    />
  );
}

/**
 * SPEC-VET-004 §13: assign the Member to one Clinic of the route
 * Organization. Offered only for a current VETERINARIAN with a completed
 * Profile; the Profile is never sent — the backend derives it from the
 * Membership. A lost response is reconciled by the workforce re-read.
 */
function ClinicAssignmentScreen({
  organizationId,
  membershipId,
}: {
  organizationId: string;
  membershipId: string;
}) {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { state, reload, leave, isActive } = useStaffMember(organizationId, membershipId);
  const [clinicId, setClinicId] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [notice, setNotice] = useState<MemberNotice | null>(null);
  const busyRef = useRef(false);
  useEffect(() => {
    void reload();
  }, [reload]);

  const back = useCallback(() => {
    leave(() => goBackOr(staffMemberHref(organizationId, membershipId)));
  }, [leave, organizationId, membershipId]);
  const loseAccess = useCallback(() => {
    leave(() => {
      Alert.alert(t('staff.title'), t('staff.unavailable'));
      router.dismissTo('/professional');
    });
  }, [leave, t]);

  const section =
    state.kind === 'loaded'
      ? veterinarianSection(state.member, state.workforceMember, state.actions, state.clinics)
      : null;
  const options =
    state.kind === 'loaded' && section?.visible
      ? assignableClinics(state.clinics, section.assignments)
      : [];

  if (state.kind !== 'loaded' || !section?.visible || !(section.canAssign || sending)) {
    const messageKey: TranslationKey =
      state.kind === 'loading'
        ? 'staffMember.loading'
        : state.kind === 'error'
          ? state.messageKey
          : state.kind === 'unavailable'
            ? 'staff.unavailable'
            : state.kind === 'memberGone'
              ? 'staffMember.memberUnavailable'
              : section?.visible && section.profile === 'pending'
                ? 'staffMember.profilePending'
                : 'staffAssignment.notAvailable';
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={back} />
          <StateMessage
            tone={state.kind === 'loading' ? 'loading' : state.kind === 'error' ? 'error' : 'empty'}
            message={t(messageKey)}
          />
          {state.kind === 'loading' ? null : (
            <Button variant="secondary" label={t('staffMember.backToMember')} onPress={back} />
          )}
        </View>
      </SafeAreaView>
    );
  }

  const selectable = options.some((clinic) => clinic.clinicId === clinicId);
  async function assign() {
    if (busyRef.current || !isActive() || clinicId === null || !selectable) return;
    const chosen = clinicId;
    busyRef.current = true;
    setSending(true);
    setNotice(null);
    try {
      const result = await assignStaffVeterinarianToClinic(organizationId, membershipId, chosen);
      if (!isActive()) return;
      const read = await reload();
      if (!isActive()) return;
      const next = assignmentNotice(
        result,
        read === null
          ? null
          : read.kind === 'loaded'
            ? { kind: 'loaded', staff: read.staff, workforce: read.workforce }
            : read.kind === 'unavailable'
              ? { kind: 'unavailable' }
              : { kind: 'error' },
        { kind: 'assign', membershipId, clinicId: chosen },
      );
      if (next === 'accessLost') {
        loseAccess();
        return;
      }
      if (next.tone === 'info') {
        leave(() => {
          AccessibilityInfo.announceForAccessibility(t(next.messageKey));
          router.dismissTo(staffMemberHref(organizationId, membershipId));
        });
        return;
      }
      setNotice(next);
    } finally {
      busyRef.current = false;
      if (isActive()) setSending(false);
    }
  }

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <AppTopBar onBack={back} />
        <Text style={styles.title} accessibilityRole="header">
          {t('staffAssignment.title')}
        </Text>
        <Text style={styles.hint}>
          {t('staffAssignment.intro', { name: staffMemberName(state.member, t) })}
        </Text>
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('staffInvite.clinicHeading')}</Text>
          <View style={styles.choices} accessibilityRole="radiogroup">
            {options.map((clinic) => (
              <ChoiceChip
                key={clinic.clinicId}
                label={clinic.displayName ?? t('professional.unnamedClinic')}
                selected={clinicId === clinic.clinicId}
                disabled={sending}
                onPress={() => {
                  if (busyRef.current) return;
                  setClinicId(clinic.clinicId);
                  setNotice(null);
                }}
              />
            ))}
          </View>
        </View>
      </ScrollView>
      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
        {notice !== null ? <Notice tone={notice.tone} message={t(notice.messageKey)} /> : null}
        <Button
          label={t('staffAssignment.submit')}
          onPress={() => void assign()}
          loading={sending}
          disabled={sending || !selectable}
        />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
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
  title: { ...typography.h2, color: colors.textPrimary },
  section: { gap: spacing.sm },
  sectionTitle: { ...typography.bodyStrong, color: colors.textPrimary },
  choices: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  hint: { ...typography.caption, color: colors.textSecondary },
  footer: {
    gap: spacing.sm,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.md,
    backgroundColor: colors.background,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

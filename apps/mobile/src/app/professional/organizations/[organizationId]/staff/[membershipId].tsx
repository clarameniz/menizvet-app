import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useRef, useState } from 'react';
import { AccessibilityInfo, Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { CompactAction } from '@/components/design-system/compact-action';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { ResponsibilityCard } from '@/components/staff-responsibility-card';
import {
  endOrganizationStaffMembership,
  type StaffMember,
  type StaffResponsibility,
} from '@/data/organization-staff';
import {
  endStaffResponsibility,
  endStaffVeterinarianClinicAssignment,
  type WorkforceClinicAssignment,
} from '@/data/staff-workforce';
import { useStaffMember } from '@/hooks/use-staff-member';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import {
  endAccessConfirmation,
  isEndAccessTarget,
  organizationStaffHref,
  staffMemberIdentity,
  staffMemberTargetLabel,
} from '@/lib/organization-staff';
import {
  assignmentNotice,
  endAssignmentConfirmation,
  endResponsibilityConfirmation,
  responsibilityGroups,
  responsibilityNotice,
  responsibilityPolicy,
  staffClinicAssignmentHref,
  staffResponsibilityEditorHref,
  type MemberNotice,
  type MemberReread,
  type ResponsibilityGroup,
} from '@/lib/staff-member-detail';
import { endAccessNotice } from '@/lib/staff-invitation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

export default function StaffMemberRoute() {
  const { organizationId, membershipId } = useLocalSearchParams<{
    organizationId: string | string[];
    membershipId: string | string[];
  }>();
  const organization = typeof organizationId === 'string' ? organizationId : '';
  const membership = typeof membershipId === 'string' ? membershipId : '';
  // A changed route owns fresh state: one Member or Organization never shows another's.
  return (
    <StaffMemberScreen
      key={`${organization}/${membership}`}
      organizationId={organization}
      membershipId={membership}
    />
  );
}

/**
 * SPEC-ORG-009 §7 Member detail: the Member's current Responsibility Grants,
 * each managed individually (SPEC-ORG-006 §14), and, for the Veterinarian
 * workforce, Profile status and current Clinic Assignments (SPEC-VET-006,
 * SPEC-VET-004/005 §13). One write at a time; every outcome is followed by
 * the authoritative re-read of both reads.
 */
function StaffMemberScreen({
  organizationId,
  membershipId,
}: {
  organizationId: string;
  membershipId: string;
}) {
  const { t } = useLocale();
  const { state, reload, invalidate, leave, isActive } = useStaffMember(
    organizationId,
    membershipId,
  );
  const hasShown = useRef(false);
  const busyRef = useRef(false);
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [notice, setNotice] = useState<MemberNotice | null>(null);

  const loseAccess = useCallback(() => {
    leave(() => {
      Alert.alert(t('staff.title'), t('staff.unavailable'));
      router.dismissTo('/professional');
    });
  }, [leave, t]);
  const refresh = useCallback(async (): Promise<MemberReread> => {
    const read = await reload();
    if (read === null) return null;
    if (read.kind === 'loaded') hasShown.current = true;
    if (read.kind === 'unavailable' && hasShown.current) loseAccess();
    return read.kind === 'loaded'
      ? { kind: 'loaded', staff: read.staff, workforce: read.workforce }
      : read.kind === 'unavailable' || read.kind === 'memberGone'
        ? { kind: read.kind }
        : { kind: 'error' };
  }, [reload, loseAccess]);
  useFocusEffect(
    useCallback(() => {
      setNotice(null);
      void refresh();
      return invalidate;
    }, [refresh, invalidate]),
  );
  const back = () => leave(() => goBackOr(organizationStaffHref(organizationId)));

  const runWrite = useCallback(
    async (key: string, write: () => Promise<MemberNotice | 'accessLost' | 'memberEnded'>) => {
      if (busyRef.current || !isActive()) return;
      busyRef.current = true;
      setBusyKey(key);
      setNotice(null);
      try {
        const next = await write();
        if (!isActive()) return;
        if (next === 'accessLost') {
          loseAccess();
          return;
        }
        if (next === 'memberEnded') {
          leave(() => {
            AccessibilityInfo.announceForAccessibility(t('staff.endAccessDone'));
            router.dismissTo(organizationStaffHref(organizationId));
          });
          return;
        }
        setNotice(next);
        AccessibilityInfo.announceForAccessibility(t(next.messageKey));
      } finally {
        busyRef.current = false;
        if (isActive()) setBusyKey(null);
      }
    },
    [isActive, loseAccess, leave, organizationId, t],
  );

  const endGrant = useCallback(
    (member: StaffMember, grant: StaffResponsibility) =>
      runWrite(`grant:${grant.responsibilityGrantId}`, async () => {
        const result = await endStaffResponsibility(organizationId, grant.responsibilityGrantId);
        if (!isActive()) return 'accessLost';
        const reread = await refresh();
        return responsibilityNotice(result, reread, {
          kind: 'end',
          membershipId: member.membershipId,
          grantId: grant.responsibilityGrantId,
        });
      }),
    [runWrite, organizationId, isActive, refresh],
  );
  const endAssignment = useCallback(
    (member: StaffMember, assignment: WorkforceClinicAssignment) =>
      runWrite(`assignment:${assignment.veterinarianClinicAssignmentId}`, async () => {
        const result = await endStaffVeterinarianClinicAssignment(
          organizationId,
          assignment.clinic.clinicId,
          assignment.veterinarianClinicAssignmentId,
        );
        if (!isActive()) return 'accessLost';
        const reread = await refresh();
        return assignmentNotice(result, reread, {
          kind: 'end',
          membershipId: member.membershipId,
          assignmentId: assignment.veterinarianClinicAssignmentId,
        });
      }),
    [runWrite, organizationId, isActive, refresh],
  );
  const endAccess = useCallback(
    (member: StaffMember) =>
      runWrite('endAccess', async () => {
        const result = await endOrganizationStaffMembership(member.membershipId);
        if (!isActive()) return 'accessLost';
        const reread = await refresh();
        // SPEC-ORG-004 §10: a lost response whose re-read no longer lists the
        // Membership is success, as on the Staff list.
        if (
          reread?.kind === 'memberGone' &&
          (result.kind === 'outcome' || result.kind === 'uncertain')
        )
          return 'memberEnded';
        const staffReread =
          reread?.kind === 'loaded'
            ? { kind: 'loaded' as const, staff: reread.staff }
            : reread?.kind === 'memberGone'
              ? { kind: 'error' as const }
              : reread;
        const next = endAccessNotice(result, staffReread, member.membershipId);
        if (next === 'accessLost') return next;
        return next.messageKey === 'staff.endAccessDone' ? 'memberEnded' : next;
      }),
    [runWrite, isActive, refresh],
  );

  const confirm = (title: string, message: string, label: string, onConfirm: () => void) => {
    if (busyRef.current) return;
    Alert.alert(title, message, [
      { text: t('staff.endAccessCancel'), style: 'cancel' },
      { text: label, style: 'destructive', onPress: onConfirm },
    ]);
  };
  const open = (href: Parameters<typeof router.push>[0]) => {
    if (!busyRef.current && isActive()) router.push(href);
  };

  if (state.kind !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <ScrollView contentContainerStyle={styles.content}>
          <AppTopBar onBack={back} />
          {state.kind === 'loading' ? (
            <StateMessage tone="loading" message={t('staffMember.loading')} />
          ) : (
            <View style={styles.section}>
              <StateMessage
                tone={state.kind === 'error' ? 'error' : 'empty'}
                message={t(
                  state.kind === 'error'
                    ? state.messageKey
                    : state.kind === 'memberGone'
                      ? 'staffMember.memberUnavailable'
                      : 'staff.unavailable',
                )}
              />
              {state.kind === 'error' ? (
                <Button label={t('professional.retry')} onPress={() => void refresh()} />
              ) : null}
              <Button variant="secondary" label={t('staffMember.backToStaff')} onPress={back} />
            </View>
          )}
        </ScrollView>
      </SafeAreaView>
    );
  }

  const { member, actions, staff } = state;
  const identity = staffMemberIdentity(member, t);
  const policy = responsibilityPolicy(member, actions);
  const groups = responsibilityGroups(member, state.workforceMember, actions, state.clinics);
  const busy = busyKey !== null;
  const name = staffMemberTargetLabel(member, t);
  const offersEndAccess = actions.endAccess && isEndAccessTarget(member);
  const confirmEndAccess = () => {
    const confirmation = endAccessConfirmation(member, staff.organizationDisplayName, t);
    confirm(confirmation.title, confirmation.message, t('staff.endAccessConfirm'), () => {
      void endAccess(member);
    });
  };

  // Each card action names exactly one Grant or Assignment; the confirmations
  // and writes stay here, unchanged.
  const changeGrant = (grant: StaffResponsibility) =>
    open(
      staffResponsibilityEditorHref(
        organizationId,
        member.membershipId,
        grant.responsibilityGrantId,
      ),
    );
  const confirmEndGrant = (grant: StaffResponsibility) => {
    const confirmation = endResponsibilityConfirmation(member, grant, t);
    confirm(confirmation.title, confirmation.message, t('staffMember.endConfirm'), () => {
      void endGrant(member, grant);
    });
  };
  const confirmEndAssignment = (assignment: WorkforceClinicAssignment) => {
    const confirmation = endAssignmentConfirmation(member, assignment, t);
    confirm(confirmation.title, confirmation.message, t('staffAssignment.endConfirm'), () => {
      void endAssignment(member, assignment);
    });
  };
  const addClinic = (role: Exclude<ResponsibilityGroup['role'], 'OWNER'>) =>
    open(
      role === 'VETERINARIAN'
        ? staffClinicAssignmentHref(organizationId, member.membershipId)
        : staffResponsibilityEditorHref(organizationId, member.membershipId, null, role),
    );

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.content}>
        <AppTopBar onBack={back} />
        <View
          style={styles.identityBlock}
          accessible
          accessibilityRole="header"
          accessibilityLabel={[
            identity.heading,
            identity.supporting,
            member.isSelf ? t('staff.self') : null,
          ]
            .filter((line) => line !== null)
            .join('. ')}
        >
          <Text style={styles.title}>{identity.heading}</Text>
          {identity.supporting === null ? null : (
            <Text style={styles.supporting}>{identity.supporting}</Text>
          )}
          {member.isSelf ? <Text style={styles.supporting}>{t('staff.self')}</Text> : null}
          <Text style={styles.organization}>{staff.organizationDisplayName}</Text>
        </View>

        {notice !== null ? (
          <View style={styles.section}>
            <Notice tone={notice.tone} message={t(notice.messageKey)} />
            {notice.guidance === 'endAccess' && offersEndAccess ? (
              <View style={styles.membershipAction}>
                <CompactAction
                  icon="exit-outline"
                  destructive
                  label={t('staff.endAccessAction')}
                  accessibilityLabel={t('staff.endAccessAccessibility', { name })}
                  disabled={busy}
                  onPress={confirmEndAccess}
                />
              </View>
            ) : null}
          </View>
        ) : null}

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.heading} accessibilityRole="header">
              {t('staffMember.responsibilitiesHeading')}
            </Text>
            {policy.canAdd ? (
              <CompactAction
                icon="add"
                label={t('staffMember.add')}
                accessibilityLabel={t('staffMember.addAction')}
                disabled={busy}
                onPress={() =>
                  open(staffResponsibilityEditorHref(organizationId, member.membershipId, null))
                }
              />
            ) : null}
          </View>
          {groups.length === 0 ? (
            <Text style={styles.note}>{t('staff.noRoles')}</Text>
          ) : (
            groups.map((group) => (
              <ResponsibilityCard
                key={group.role}
                group={group}
                memberName={name}
                busyKey={busyKey}
                onAddClinic={addClinic}
                onChangeGrant={changeGrant}
                onEndGrant={confirmEndGrant}
                onEndAssignment={confirmEndAssignment}
              />
            ))
          )}
        </View>

        {offersEndAccess ? (
          // Membership in the Organization, apart from its responsibilities.
          <View style={styles.membershipSection}>
            <View style={styles.membershipAction}>
              <CompactAction
                icon="exit-outline"
                destructive
                label={t('staff.endAccessAction')}
                accessibilityLabel={t('staff.endAccessAccessibility', { name })}
                loading={busyKey === 'endAccess'}
                disabled={busy}
                onPress={confirmEndAccess}
              />
            </View>
          </View>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  content: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  identityBlock: { gap: spacing.xs },
  title: { ...typography.h1, color: colors.textPrimary, flexShrink: 1 },
  supporting: { ...typography.caption, color: colors.textSecondary, flexShrink: 1 },
  organization: { ...typography.bodyStrong, color: colors.textSecondary },
  section: { gap: spacing.md },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.sm,
  },
  heading: { ...typography.h3, color: colors.textPrimary, flexShrink: 1 },
  note: { ...typography.caption, color: colors.textSecondary },
  membershipSection: {
    paddingTop: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  // Flush with the content edge despite the action's touch padding.
  membershipAction: { flexDirection: 'row', marginLeft: -spacing.sm },
});

import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { TabSelector } from '@/components/design-system/tab-selector';
import { StaffInvitationsList, StaffMembersList } from '@/components/organization-staff-lists';
import {
  recheckPendingInvitation,
  revokeOrganizationInvitation,
  type PendingStaffInvitation,
} from '@/data/organization-staff';
import {
  useStaffInvitations,
  useStaffMembers,
  useStaffScreenContext,
} from '@/hooks/use-organization-staff-pages';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { organizationStaffInviteHref } from '@/lib/organization-staff';
import { staffMemberHref } from '@/lib/staff-member-detail';
import { revocationNotice, type StaffNotice } from '@/lib/staff-invitation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type StaffTab = 'members' | 'invitations';

export default function OrganizationStaffRoute() {
  const { organizationId } = useLocalSearchParams<{ organizationId: string | string[] }>();
  const id = typeof organizationId === 'string' ? organizationId : '';
  // A changed route owns fresh state: Org A is never rendered under Org B.
  return <StaffScreen key={id} organizationId={id} />;
}

/**
 * Organization Staff (SPEC-ORG-009 §7, §12): "Personal" with the
 * Organization's name, then two tabs — Members (initial) and Invitations —
 * each read page by page through its own read (BR-13, BR-15), only once its
 * tab is shown, with its own rows, cursor, loading and errors, kept while the
 * other tab is shown. A focus (back from the Member detail or the Invite
 * screen) restarts only the tab on screen; the other restarts when shown
 * again. Never the full `get_organization_staff` read.
 *
 * Actions are advisory (from the professional context) and re-authorized by
 * every write: the Member detail from a Members row, Invite in the
 * Invitations tab (also when it is empty), and Revoke on an Invitation row
 * after a confirmation, one at a time, followed by the authoritative re-read
 * of the Invitations tab. A 42501 from either read means Staff access was
 * lost: before anything was shown, the screen says so; afterwards it leaves
 * for the Professional landing with a calm explanation (§7).
 */
function StaffScreen({ organizationId }: { organizationId: string }) {
  const { t } = useLocale();
  const [tab, setTab] = useState<StaffTab>('members');
  const [unavailable, setUnavailable] = useState(false);
  const [revokingId, setRevokingId] = useState<string | null>(null);
  const [notice, setNotice] = useState<StaffNotice | null>(null);
  const context = useStaffScreenContext(organizationId);

  const isMountedRef = useRef(true);
  const leavingRef = useRef(false);
  const hasShownRef = useRef(false);
  const revokingRef = useRef(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const isActive = useCallback(() => isMountedRef.current && !leavingRef.current, []);
  const leave = useCallback((navigate: () => void) => {
    if (leavingRef.current) return;
    leavingRef.current = true;
    navigate();
  }, []);

  const loseAccess = useCallback(() => {
    if (!isActive()) return;
    if (!hasShownRef.current) {
      setUnavailable(true);
      return;
    }
    leave(() => {
      Alert.alert(t('staff.title'), t('staff.unavailable'));
      router.dismissTo('/professional');
    });
  }, [isActive, leave, t]);

  const members = useStaffMembers(organizationId, !unavailable && tab === 'members', loseAccess);
  const invitations = useStaffInvitations(
    organizationId,
    !unavailable && tab === 'invitations',
    loseAccess,
  );

  useEffect(() => {
    if (members.state.rows !== null || invitations.state.rows !== null) {
      hasShownRef.current = true;
    }
  }, [members.state.rows, invitations.state.rows]);

  useFocusEffect(
    useCallback(() => {
      setNotice(null);
    }, []),
  );

  const back = () => leave(() => goBackOr('/professional'));

  // SPEC-ORG-010 §5: one revocation at a time, then always the authoritative
  // re-read. A lost response is reconciled by re-checking that one Invitation.
  const revoke = useCallback(
    async (invitation: PendingStaffInvitation, previous: PendingStaffInvitation | null) => {
      if (revokingRef.current || !isActive()) return;
      revokingRef.current = true;
      setRevokingId(invitation.invitationId);
      setNotice(null);
      try {
        const result = await revokeOrganizationInvitation(invitation.invitationId);
        if (!isActive()) return;
        const recheck =
          result.kind === 'uncertain'
            ? await recheckPendingInvitation(organizationId, invitation, previous)
            : null;
        if (!isActive()) return;
        const next = revocationNotice(result, recheck);
        if (next === 'accessLost') {
          loseAccess();
          return;
        }
        setNotice(next);
        await invitations.reload();
      } finally {
        revokingRef.current = false;
        if (isActive()) setRevokingId(null);
      }
    },
    [invitations, isActive, loseAccess, organizationId],
  );

  const confirmRevoke = useCallback(
    (invitation: PendingStaffInvitation, previous: PendingStaffInvitation | null) => {
      if (revokingRef.current) return;
      Alert.alert(
        t('staff.revokeConfirmTitle'),
        t('staff.revokeConfirmMessage', { email: invitation.recipientEmail }),
        [
          { text: t('staff.revokeCancel'), style: 'cancel' },
          {
            text: t('staff.revokeConfirm'),
            style: 'destructive',
            onPress: () => {
              void revoke(invitation, previous);
            },
          },
        ],
      );
    },
    [revoke, t],
  );

  const header = (
    <View style={styles.header}>
      <AppTopBar onBack={back} />
      <View style={styles.titleBlock}>
        <Text style={styles.title} accessibilityRole="header">
          {t('staff.title')}
        </Text>
        {context.organizationName !== null ? (
          <Text style={styles.organization} numberOfLines={2}>
            {context.organizationName}
          </Text>
        ) : null}
      </View>
      {unavailable ? null : (
        <TabSelector
          tabs={[
            { value: 'members', label: t('staff.membersTab') },
            { value: 'invitations', label: t('staff.invitationsTab') },
          ]}
          selected={tab}
          onSelect={setTab}
          testIDPrefix="staff-tab"
        />
      )}
    </View>
  );

  if (unavailable) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.unavailable}>
          {header}
          <StateMessage tone="empty" message={t('staff.unavailable')} />
          <Button variant="secondary" label={t('staff.backToProfessional')} onPress={back} />
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      {tab === 'members' ? (
        <StaffMembersList
          header={header}
          list={members}
          busy={revokingId !== null}
          onOpen={
            context.actions.manage
              ? (member) => {
                  if (!revokingRef.current && isActive())
                    router.push(staffMemberHref(organizationId, member.membershipId));
                }
              : undefined
          }
        />
      ) : (
        <StaffInvitationsList
          header={header}
          list={invitations}
          notice={
            notice !== null ? <Notice tone={notice.tone} message={t(notice.messageKey)} /> : null
          }
          revokingInvitationId={revokingId}
          onInvite={
            context.actions.invite
              ? () => {
                  if (!revokingRef.current && isActive())
                    router.push(organizationStaffInviteHref(organizationId));
                }
              : undefined
          }
          onRevoke={context.actions.revoke ? confirmRevoke : undefined}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  header: { gap: spacing.lg },
  titleBlock: { gap: spacing.xs },
  title: { ...typography.h1, color: colors.textPrimary },
  organization: { ...typography.bodyStrong, color: colors.textSecondary },
  unavailable: {
    flexGrow: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    gap: spacing.lg,
  },
});

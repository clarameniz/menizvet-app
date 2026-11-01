import type { ReactElement } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';

import { RowIconAction } from '@/components/design-system/compact-action';
import { PillButton } from '@/components/design-system/pill-button';
import {
  EmptyListMessage,
  FramedRow,
  LoadMoreFooter,
  PagedListStatus,
  pagedListStyles,
} from '@/components/paged-list-parts';
import type { PendingStaffInvitation, StaffMemberRow } from '@/data/organization-staff';
import type { PagedList } from '@/hooks/use-paged-list';
import { useLocale } from '@/i18n/locale-provider';
import {
  staffInstantLabel,
  staffMemberIdentity,
  staffMemberTargetLabel,
  staffRoleBadges,
  staffScopeLabel,
  staffShortDateLabel,
  staffTaskLabel,
} from '@/lib/organization-staff';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * The Staff screen's two tabs (SPEC-ORG-009 §7, §12), each ONE virtualized
 * list of compact rows read page by page, under the screen's shared header.
 */

/**
 * Members: name, "You", one badge per responsibility with its Clinic coverage
 * (SPEC-ORG-009 §7) and, when the Member detail is offered, a chevron — the
 * whole row opens it. The Invitation address appears only as the heading's
 * context (no name) or to tell namesakes apart (`displayNameIsShared`,
 * BR-14). Each row's text is one accessible element stating every current
 * Grant with its Clinic. No date, Clinic list or destructive action.
 */
export function StaffMembersList({
  header,
  list,
  onOpen,
  busy,
}: {
  header: ReactElement;
  list: PagedList<StaffMemberRow, never>;
  /** Opens the Member detail; absent without the advisory capability. */
  onOpen?: (member: StaffMemberRow) => void;
  busy: boolean;
}) {
  const { t } = useLocale();
  const { state } = list;
  const rows = state.rows ?? [];

  return (
    <FlatList
      data={rows}
      keyExtractor={(member) => member.membershipId}
      contentContainerStyle={pagedListStyles.content}
      showsVerticalScrollIndicator={false}
      ListHeaderComponent={
        <View style={pagedListStyles.headerBlock}>
          {header}
          <PagedListStatus list={list} loadingKey="staff.loading" errorKey="staff.loadError" />
        </View>
      }
      renderItem={({ item, index }) => (
        <FramedRow first={index === 0} last={index === rows.length - 1}>
          <MemberRow member={item} onOpen={onOpen} busy={busy} />
        </FramedRow>
      )}
      ListEmptyComponent={
        state.rows !== null && state.rows.length === 0 ? (
          <EmptyListMessage icon="people-outline" message={t('staff.noMembers')} />
        ) : null
      }
      ListFooterComponent={<LoadMoreFooter list={list} />}
    />
  );
}

/**
 * Pending Invitations: "Pending invitations" with "+ Invite" (when offered,
 * also with no Invitation), then address, "Pending", what accepting grants,
 * the Clinic when Clinic-scoped, a short expiry and, when offered, the trash
 * that revokes after a confirmation.
 */
export function StaffInvitationsList({
  header,
  list,
  notice,
  onInvite,
  onRevoke,
  revokingInvitationId,
}: {
  header: ReactElement;
  list: PagedList<PendingStaffInvitation, never>;
  /** The latest revocation outcome, shown above the list. */
  notice: ReactElement | null;
  onInvite?: () => void;
  onRevoke?: (invitation: PendingStaffInvitation, previous: PendingStaffInvitation | null) => void;
  revokingInvitationId: string | null;
}) {
  const { t } = useLocale();
  const { state } = list;
  const rows = state.rows ?? [];

  return (
    <FlatList
      data={rows}
      keyExtractor={(invitation) => invitation.invitationId}
      contentContainerStyle={pagedListStyles.content}
      showsVerticalScrollIndicator={false}
      ListHeaderComponent={
        <View style={pagedListStyles.headerBlock}>
          {header}
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              {t('staff.invitationsHeading')}
            </Text>
            {onInvite !== undefined ? (
              <PillButton
                icon="person-add-outline"
                label={t('staff.inviteAction')}
                onPress={onInvite}
              />
            ) : null}
          </View>
          {notice}
          <PagedListStatus
            list={list}
            loadingKey="staff.invitationsLoading"
            errorKey="staff.loadError"
          />
        </View>
      }
      renderItem={({ item, index }) => (
        <FramedRow first={index === 0} last={index === rows.length - 1}>
          <InvitationRow
            invitation={item}
            onRevoke={
              onRevoke === undefined ? undefined : () => onRevoke(item, rows[index - 1] ?? null)
            }
            revoking={revokingInvitationId === item.invitationId}
            busy={revokingInvitationId !== null}
          />
        </FramedRow>
      )}
      ListEmptyComponent={
        state.rows !== null && state.rows.length === 0 ? (
          <EmptyListMessage icon="mail-outline" message={t('staff.noInvitations')} />
        ) : null
      }
      ListFooterComponent={<LoadMoreFooter list={list} />}
    />
  );
}

function MemberRow({
  member,
  onOpen,
  busy,
}: {
  member: StaffMemberRow;
  onOpen?: (member: StaffMemberRow) => void;
  busy: boolean;
}) {
  const { t } = useLocale();
  const identity = staffMemberIdentity(member, t);
  const supporting =
    member.displayName === null || member.displayNameIsShared ? identity.supporting : null;
  const label = [
    identity.heading,
    identity.supporting,
    member.isSelf ? t('staff.self') : null,
    ...member.responsibilities.map((role) => staffTaskLabel(role, t)),
    member.responsibilities.length === 0 ? t('staff.noRoles') : null,
  ]
    .filter((line) => line !== null)
    .join('. ');
  const body = (
    <View style={styles.body} accessible accessibilityRole="text" accessibilityLabel={label}>
      <View style={styles.headingLine}>
        <Text style={styles.heading}>{identity.heading}</Text>
        {member.isSelf ? <Badge label={t('staff.self')} tone="neutral" /> : null}
      </View>
      {supporting === null ? null : <Text style={styles.caption}>{supporting}</Text>}
      <Badges
        labels={
          member.responsibilities.length === 0
            ? [t('staff.noRoles')]
            : staffRoleBadges(member.responsibilities, t)
        }
      />
    </View>
  );
  if (onOpen === undefined) return <View style={styles.row}>{body}</View>;
  // The whole row opens the detail; the chevron is its accessible button.
  return (
    <Pressable
      accessible={false}
      disabled={busy}
      onPress={() => onOpen(member)}
      style={({ pressed }) => [styles.row, pressed && !busy && styles.pressed]}
    >
      {body}
      <RowIconAction
        icon="chevron-forward"
        accessibilityLabel={t('staff.manageAccessibility', {
          name: staffMemberTargetLabel(member, t),
        })}
        disabled={busy}
        onPress={() => onOpen(member)}
      />
    </Pressable>
  );
}

function InvitationRow({
  invitation,
  onRevoke,
  revoking,
  busy,
}: {
  invitation: PendingStaffInvitation;
  onRevoke?: () => void;
  revoking: boolean;
  busy: boolean;
}) {
  const { t, locale } = useLocale();
  // Clinic names are what a Clinic-scoped Invitation adds beyond its badge.
  const clinics = invitation.responsibilities.flatMap((role) =>
    role.scope.type === 'CLINIC' ? [staffScopeLabel(role, t) ?? ''] : [],
  );
  const shortExpiry = t('staff.expiresAt', {
    date: staffShortDateLabel(invitation.expiresAt, locale),
  });
  const label = [
    invitation.recipientEmail,
    t('staff.pending'),
    ...invitation.responsibilities.map((role) =>
      t('staff.grantedOnAccept', { responsibility: staffTaskLabel(role, t) }),
    ),
    t('staff.expiresAt', { date: staffInstantLabel(invitation.expiresAt, locale) }),
  ].join('. ');

  return (
    <View style={styles.row}>
      <View style={styles.body} accessible accessibilityRole="text" accessibilityLabel={label}>
        <View style={styles.headingLine}>
          <Text style={styles.heading}>{invitation.recipientEmail}</Text>
          <Badge label={t('staff.pending')} tone="pending" />
        </View>
        <Badges labels={staffRoleBadges(invitation.responsibilities, t)} />
        <Text style={styles.caption}>{[...clinics, shortExpiry].join(' · ')}</Text>
      </View>
      {onRevoke !== undefined ? (
        <RowIconAction
          icon="trash-outline"
          destructive
          accessibilityLabel={t('staff.revokeAccessibility', { email: invitation.recipientEmail })}
          loading={revoking}
          disabled={busy}
          onPress={onRevoke}
        />
      ) : null}
    </View>
  );
}

function Badges({ labels }: { labels: string[] }) {
  return (
    <View style={styles.badges}>
      {labels.map((label) => (
        <Badge key={label} label={label} tone="role" />
      ))}
    </View>
  );
}

/** A small pill; its text is also part of the row's accessible label. */
function Badge({ label, tone }: { label: string; tone: 'role' | 'neutral' | 'pending' }) {
  return (
    <View style={[styles.badge, styles[`${tone}Badge`]]}>
      <Text style={[styles.badgeText, styles[`${tone}BadgeText`]]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  sectionTitle: { ...typography.h3, color: colors.textPrimary, flexShrink: 1 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    backgroundColor: colors.surface,
  },
  pressed: { backgroundColor: colors.primarySoft },
  body: { flex: 1, gap: spacing.xs },
  headingLine: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.sm },
  // A long Invitation address has no spaces; it must still wrap in the row.
  heading: { ...typography.body, fontWeight: '600', color: colors.textPrimary, flexShrink: 1 },
  caption: { ...typography.caption, color: colors.textSecondary, flexShrink: 1 },
  badges: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  badge: { paddingHorizontal: spacing.sm, paddingVertical: 2, borderRadius: radius.pill },
  badgeText: { ...typography.caption, fontWeight: '600' },
  roleBadge: { backgroundColor: colors.primarySoft },
  roleBadgeText: { color: colors.primaryDark },
  neutralBadge: { backgroundColor: colors.surfaceSoft },
  neutralBadgeText: { color: colors.textSecondary },
  pendingBadge: { backgroundColor: colors.warningSoft },
  pendingBadgeText: { color: colors.textPrimary },
});

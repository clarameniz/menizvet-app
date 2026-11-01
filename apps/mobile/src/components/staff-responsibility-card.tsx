import type { ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { CompactAction, RowIconAction } from '@/components/design-system/compact-action';
import type { StaffResponsibility } from '@/data/organization-staff';
import type { WorkforceClinicAssignment } from '@/data/staff-workforce';
import { useLocale } from '@/i18n/locale-provider';
import {
  staffResponsibilityLabel,
  staffRoleLabel,
  staffScopeLabel,
} from '@/lib/organization-staff';
import type { GrantRow, ResponsibilityGroup } from '@/lib/staff-member-detail';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ResponsibilityCardProps = {
  group: ResponsibilityGroup;
  /** The Member as named in accessible labels (SPEC-ORG-009 identity order). */
  memberName: string;
  /** The write in flight, if any: every action waits for it. */
  busyKey: string | null;
  onAddClinic: (role: Exclude<ResponsibilityGroup['role'], 'OWNER'>) => void;
  onChangeGrant: (grant: StaffResponsibility) => void;
  onEndGrant: (grant: StaffResponsibility) => void;
  onEndAssignment: (assignment: WorkforceClinicAssignment) => void;
};

/**
 * One responsibility of a Staff Member as a compact card (SPEC-ORG-009 §7):
 * its name (with the VETERINARIAN Grant's own icon actions), then its Clinics
 * as list rows with icon actions under a "Clinics" subtitle that carries "Add".
 * Presentation only — each action names exactly one Grant or one Clinic
 * Assignment, and the screen confirms and performs it.
 */
export function ResponsibilityCard({
  group,
  memberName,
  busyKey,
  onAddClinic,
  onChangeGrant,
  onEndGrant,
  onEndAssignment,
}: ResponsibilityCardProps) {
  const { t } = useLocale();
  const busy = busyKey !== null;
  // Visible actions are short ("Editar", "Eliminar", an icon); every accessible
  // name still says exactly which Grant or Assignment of which Member it acts on.
  const changeLabel = (grant: StaffResponsibility) =>
    t('staffMember.changeAccessibility', {
      responsibility: staffResponsibilityLabel(grant, t),
      name: memberName,
    });
  const endLabel = (grant: StaffResponsibility) =>
    t('staffMember.endAccessibility', {
      responsibility: staffResponsibilityLabel(grant, t),
      name: memberName,
    });
  const endingGrant = (grant: StaffResponsibility) =>
    busyKey === `grant:${grant.responsibilityGrantId}`;

  const addClinic = (role: Exclude<ResponsibilityGroup['role'], 'OWNER'>) => (
    <CompactAction
      key="addClinic"
      icon="add-circle-outline"
      label={t('staffMember.add')}
      accessibilityLabel={t('staffMember.addClinicAccessibility', {
        role: staffRoleLabel(role, t),
      })}
      disabled={busy}
      onPress={() => onAddClinic(role)}
    />
  );
  const grantRow = ({ grant, canChange, canEnd }: GrantRow, text: string, first: boolean) => (
    <ListRow key={grant.responsibilityGrantId} text={text} first={first}>
      {canChange ? (
        <RowIconAction
          icon="create-outline"
          accessibilityLabel={changeLabel(grant)}
          disabled={busy}
          onPress={() => onChangeGrant(grant)}
        />
      ) : null}
      {canEnd ? (
        <RowIconAction
          icon="trash-outline"
          destructive
          accessibilityLabel={endLabel(grant)}
          loading={endingGrant(grant)}
          disabled={busy}
          onPress={() => onEndGrant(grant)}
        />
      ) : null}
    </ListRow>
  );

  /** Divider, then the Clinics subtitle with its own "Add" beside it. */
  const clinicsHeader = (title: string, add: ReactNode) => (
    <>
      <View style={styles.divider} />
      <View style={styles.subheader}>
        <Text style={styles.subtitle}>{title}</Text>
        {add}
      </View>
    </>
  );

  let headerActions: ReactNode = null;
  let body: ReactNode;
  if (group.role === 'OWNER') {
    body = <Text style={styles.note}>{t('staffMember.ownerNote')}</Text>;
  } else if (group.role === 'VETERINARIAN') {
    const { grant, section } = group;
    // The header icons act on the VETERINARIAN Grant only, never on the
    // Professional Profile; the backend still refuses to end it while Clinic
    // Assignments are current (SPEC-ORG-006 BR-54).
    headerActions =
      grant === null ? null : (
        <>
          {grant.canChange ? (
            <RowIconAction
              icon="create-outline"
              accessibilityLabel={t('staffMember.changeVeterinarianAccessibility', {
                name: memberName,
              })}
              disabled={busy}
              onPress={() => onChangeGrant(grant.grant)}
            />
          ) : null}
          {grant.canEnd ? (
            <RowIconAction
              icon="trash-outline"
              destructive
              accessibilityLabel={t('staffMember.endVeterinarianAccessibility', {
                name: memberName,
              })}
              loading={endingGrant(grant.grant)}
              disabled={busy}
              onPress={() => onEndGrant(grant.grant)}
            />
          ) : null}
        </>
      );
    body = (
      <>
        <Text style={styles.note}>
          {grant === null
            ? t('staffMember.veterinarianEnded')
            : t(
                section.profile === 'completed'
                  ? 'staffMember.profileCompleted'
                  : 'staffMember.profilePending',
              )}
        </Text>
        {clinicsHeader(
          t('staffMember.clinicsHeading'),
          section.canAssign ? addClinic(group.role) : null,
        )}
        {section.assignments.length > 0 ? (
          <View>
            {section.assignments.map((assignment, index) => {
              const clinic = assignment.clinic.displayName ?? t('professional.unnamedClinic');
              return (
                <ListRow
                  key={assignment.veterinarianClinicAssignmentId}
                  text={clinic}
                  first={index === 0}
                >
                  {section.canEndAssignments ? (
                    <RowIconAction
                      icon="trash-outline"
                      destructive
                      accessibilityLabel={t('staffAssignment.endAccessibility', {
                        clinic,
                        name: memberName,
                      })}
                      loading={
                        busyKey === `assignment:${assignment.veterinarianClinicAssignmentId}`
                      }
                      disabled={busy}
                      onPress={() => onEndAssignment(assignment)}
                    />
                  ) : null}
                </ListRow>
              );
            })}
          </View>
        ) : (
          <Text style={styles.empty}>{t('staffAssignment.none')}</Text>
        )}
      </>
    );
  } else {
    const rows = [
      ...(group.organizationGrant === null
        ? []
        : [{ row: group.organizationGrant, text: t('staff.allClinics') }]),
      ...group.clinicGrants.map((row) => ({ row, text: staffScopeLabel(row.grant, t) ?? '' })),
    ];
    // Several independent Grants: each row keeps its own Change / End; there is
    // deliberately no card-level "remove the responsibility".
    body = (
      <>
        {clinicsHeader(
          t('staffMember.clinicsHeading'),
          group.canAddClinic ? addClinic(group.role) : null,
        )}
        <View>{rows.map(({ row, text }, index) => grantRow(row, text, index === 0))}</View>
        {group.redundant ? (
          <Text style={styles.note}>{t('staffMember.redundantScope')}</Text>
        ) : null}
      </>
    );
  }

  return (
    <View style={styles.card}>
      <View style={styles.header}>
        <Text style={styles.title} accessibilityRole="header">
          {staffRoleLabel(group.role, t)}
        </Text>
        {headerActions === null ? null : <View style={styles.rowActions}>{headerActions}</View>}
      </View>
      {body}
    </View>
  );
}

/** One compact list row: the Clinic (or "all Clinics") and its icon actions. */
function ListRow({ text, first, children }: { text: string; first: boolean; children: ReactNode }) {
  return (
    <View style={[styles.row, !first && styles.rowDivider]}>
      <Text style={styles.rowText}>{text}</Text>
      <View style={styles.rowActions}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  // Title left, the responsibility's own icon actions right.
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, minHeight: 44 },
  title: { ...typography.bodyStrong, color: colors.textPrimary, flex: 1 },
  note: { ...typography.caption, color: colors.textSecondary },
  empty: { ...typography.body, color: colors.textSecondary },
  divider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border },
  // The Clinics subtitle and its "Add", flush right despite touch padding.
  subheader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginRight: -spacing.sm,
  },
  subtitle: { ...typography.caption, fontWeight: '600', color: colors.textSecondary, flex: 1 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, minHeight: 44 },
  rowDivider: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border },
  // Long Clinic names wrap instead of pushing the icons off the row.
  rowText: { ...typography.body, color: colors.textPrimary, flex: 1 },
  rowActions: { flexDirection: 'row' },
});

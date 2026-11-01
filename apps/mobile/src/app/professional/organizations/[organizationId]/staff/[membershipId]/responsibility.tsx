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
import {
  addStaffResponsibility,
  replaceStaffResponsibility,
  STAFF_EDITABLE_ROLES,
  type StaffScopeType,
} from '@/data/staff-workforce';
import type { StaffResponsibility } from '@/data/organization-staff';
import { useStaffMember } from '@/hooks/use-staff-member';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import {
  staffMemberName,
  staffResponsibilityLabel,
  staffRoleLabel,
} from '@/lib/organization-staff';
import {
  canSubmitResponsibility,
  clinicChoices,
  draftFromGrant,
  draftHasScopeChoice,
  initialAddDraft,
  parseClinicRole,
  responsibilityInputFrom,
  responsibilityNotice,
  responsibilityPolicy,
  staffMemberHref,
  withDraftRole,
  withDraftScope,
  type ClinicRole,
  type MemberNotice,
  type ResponsibilityDraft,
} from '@/lib/staff-member-detail';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

const SCOPES: readonly { scope: StaffScopeType; labelKey: TranslationKey }[] = [
  { scope: 'ORGANIZATION', labelKey: 'staffInvite.scopeOrganization' },
  { scope: 'CLINIC', labelKey: 'staffInvite.scopeClinic' },
];

export default function StaffResponsibilityRoute() {
  const { organizationId, membershipId, grantId, clinicRole } = useLocalSearchParams<{
    organizationId: string | string[];
    membershipId: string | string[];
    grantId?: string | string[];
    clinicRole?: string | string[];
  }>();
  const organization = typeof organizationId === 'string' ? organizationId : '';
  const membership = typeof membershipId === 'string' ? membershipId : '';
  const grant = typeof grantId === 'string' ? grantId : null;
  const preset = grant === null ? parseClinicRole(clinicRole) : null;
  return (
    <ResponsibilityEditor
      key={`${organization}/${membership}/${grant ?? preset ?? 'add'}`}
      organizationId={organization}
      membershipId={membership}
      grantId={grant}
      clinicRole={preset}
    />
  );
}

/**
 * SPEC-ORG-006 §14: Add one Grant, or Change exactly the named Grant. Roles:
 * Administrator, Receptionist, Veterinarian — never Owner. Veterinarian is
 * always the whole Organization, with no Clinic selector. "Add a reception /
 * administration clinic" opens Add preset to that role and Clinic scope; it
 * is still one ordinary Add. Clinics the Member already holds for the drafted
 * role are not offered. Nothing else about the Member changes. A lost
 * response is never retried: the re-read decides.
 */
function ResponsibilityEditor({
  organizationId,
  membershipId,
  grantId,
  clinicRole,
}: {
  organizationId: string;
  membershipId: string;
  grantId: string | null;
  clinicRole: ClinicRole | null;
}) {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { state, reload, leave, isActive } = useStaffMember(organizationId, membershipId);
  const [draft, setDraft] = useState<ResponsibilityDraft | null>(null);
  const [sending, setSending] = useState(false);
  const [notice, setNotice] = useState<MemberNotice | null>(null);
  const busyRef = useRef(false);

  // The named Grant as first read; frozen so the re-read after a successful
  // Change (which ends it) never re-targets or flashes a stale state.
  const [original, setOriginal] = useState<StaffResponsibility | null>(null);
  useEffect(() => {
    void reload().then((read) => {
      if (read?.kind !== 'loaded') return;
      const named =
        grantId === null
          ? null
          : (read.member.responsibilities.find(
              (grant) => grant.responsibilityGrantId.toLowerCase() === grantId.toLowerCase(),
            ) ?? null);
      setOriginal(named);
      setDraft(named === null ? initialAddDraft(clinicRole) : draftFromGrant(named));
    });
  }, [reload, grantId, clinicRole]);

  const back = useCallback(() => {
    leave(() => goBackOr(staffMemberHref(organizationId, membershipId)));
  }, [leave, organizationId, membershipId]);
  const loseAccess = useCallback(() => {
    leave(() => {
      Alert.alert(t('staff.title'), t('staff.unavailable'));
      router.dismissTo('/professional');
    });
  }, [leave, t]);

  const allowed =
    state.kind === 'loaded' &&
    (grantId === null
      ? responsibilityPolicy(state.member, state.actions).canAdd
      : original !== null && responsibilityPolicy(state.member, state.actions).canChange(original));

  if (state.kind !== 'loaded' || draft === null || !allowed) {
    const messageKey: TranslationKey =
      state.kind === 'loading' || (state.kind === 'loaded' && draft === null)
        ? 'staffMember.loading'
        : state.kind === 'error'
          ? state.messageKey
          : state.kind === 'unavailable'
            ? 'staff.unavailable'
            : state.kind === 'memberGone'
              ? 'staffMember.memberUnavailable'
              : grantId !== null && original === null
                ? 'staffMember.grantChanged'
                : 'staffMember.notAllowed';
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={back} />
          <StateMessage
            tone={
              messageKey === 'staffMember.loading'
                ? 'loading'
                : state.kind === 'error'
                  ? 'error'
                  : 'empty'
            }
            message={t(messageKey)}
          />
          {messageKey === 'staffMember.loading' ? null : (
            <Button variant="secondary" label={t('staffMember.backToMember')} onPress={back} />
          )}
        </View>
      </SafeAreaView>
    );
  }

  const { member, clinics } = state;
  const submitEnabled = canSubmitResponsibility(draft, member, clinics, sending);
  const choices = clinicChoices(draft.role, member, clinics, original);
  const update = (next: ResponsibilityDraft) => {
    if (busyRef.current) return;
    setDraft(next);
    setNotice(null);
  };

  async function submit() {
    const input = draft === null ? null : responsibilityInputFrom(draft);
    if (busyRef.current || !isActive() || !submitEnabled || input === null) return;
    busyRef.current = true;
    setSending(true);
    setNotice(null);
    try {
      const result =
        original === null
          ? await addStaffResponsibility(organizationId, membershipId, input)
          : await replaceStaffResponsibility(organizationId, original.responsibilityGrantId, input);
      if (!isActive()) return;
      const read = await reload();
      if (!isActive()) return;
      const next = responsibilityNotice(
        result,
        read === null
          ? null
          : read.kind === 'loaded'
            ? { kind: 'loaded', staff: read.staff, workforce: read.workforce }
            : read.kind === 'unavailable'
              ? { kind: 'unavailable' }
              : { kind: 'error' },
        original === null
          ? { kind: 'add', membershipId, input }
          : { kind: 'change', membershipId, grantId: original.responsibilityGrantId, input },
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
      <ScrollView contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
        <AppTopBar onBack={back} />
        <Text style={styles.title} accessibilityRole="header">
          {t(
            original !== null
              ? 'staffResponsibility.changeTitle'
              : clinicRole === 'RECEPTIONIST'
                ? 'staffMember.addReceptionClinic'
                : clinicRole === 'ADMINISTRATOR'
                  ? 'staffMember.addAdministrationClinic'
                  : 'staffResponsibility.addTitle',
          )}
        </Text>
        <Text style={styles.hint}>
          {original === null
            ? t('staffResponsibility.addIntro', { name: staffMemberName(member, t) })
            : t('staffResponsibility.changeIntro', {
                name: staffMemberName(member, t),
                responsibility: staffResponsibilityLabel(original, t),
              })}
        </Text>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('staffInvite.roleHeading')}</Text>
          <View style={styles.choices} accessibilityRole="radiogroup">
            {STAFF_EDITABLE_ROLES.map((role) => (
              <ChoiceChip
                key={role}
                label={staffRoleLabel(role, t)}
                selected={draft.role === role}
                disabled={sending}
                onPress={() => update(withDraftRole(draft, role))}
              />
            ))}
          </View>
        </View>

        {draftHasScopeChoice(draft) ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('staffInvite.scopeHeading')}</Text>
            <View style={styles.choices} accessibilityRole="radiogroup">
              {SCOPES.map(({ scope, labelKey }) => (
                <ChoiceChip
                  key={scope}
                  label={t(labelKey)}
                  selected={draft.scope === scope}
                  disabled={sending}
                  onPress={() => update(withDraftScope(draft, scope))}
                />
              ))}
            </View>
          </View>
        ) : (
          <Text style={styles.hint}>{t('staffInvite.veterinarianScope')}</Text>
        )}

        {draftHasScopeChoice(draft) && draft.scope === 'CLINIC' ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('staffInvite.clinicHeading')}</Text>
            {choices.length === 0 ? (
              <Text style={styles.hint}>
                {t(clinics.length === 0 ? 'staffInvite.noClinics' : 'staffMember.duplicate')}
              </Text>
            ) : (
              <View style={styles.choices} accessibilityRole="radiogroup">
                {choices.map((clinic) => (
                  <ChoiceChip
                    key={clinic.clinicId}
                    label={clinic.displayName ?? t('professional.unnamedClinic')}
                    selected={draft.clinicId === clinic.clinicId}
                    disabled={sending}
                    onPress={() => update({ ...draft, clinicId: clinic.clinicId })}
                  />
                ))}
              </View>
            )}
          </View>
        ) : null}
        <Text style={styles.hint}>{t('staffResponsibility.otherResponsibilitiesKept')}</Text>
      </ScrollView>
      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
        {notice !== null ? <Notice tone={notice.tone} message={t(notice.messageKey)} /> : null}
        <Button
          label={t(
            original === null
              ? 'staffResponsibility.addSubmit'
              : 'staffResponsibility.changeSubmit',
          )}
          onPress={() => void submit()}
          loading={sending}
          disabled={!submitEnabled}
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
